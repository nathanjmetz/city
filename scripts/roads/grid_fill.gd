class_name GridFill
extends RefCounted
## Fills any shape the player draws with a street grid that fits the roads
## already there. Benchmarks: the Cities: Skylines 2 grid tool and the Move It
## and Network Anarchy mods; real Midwestern street grids break ties.
##
## - The shape's sides become streets, except where a road already runs.
## - Grid streets run square to one side of the shape, spread evenly across
##   it, and are clipped to it however irregular it is.
## - Grid streets shift to line up with junctions already inside the shape.
## - No new street runs alongside another closer than one row of lots needs,
##   so roads and sidewalks never overlap.
## - Loose ends join the nearest road or junction, stubs that poke past a road
##   are cut back, and dead ends of old roads inside the shape are joined up.
##
## Works in 2D on the ground plane (x, z). Returns curves as
## [start, control, end] like RoadShapes, so the preview and the simulation
## build exactly the same thing.

## Shallowest lot worth platting between two side-by-side streets: 80 ft,
## the shallow end of US single-family lots.
const MIN_LOT_DEPTH := 24.0
## Streets within this angle of each other count as side by side (sin 12°).
const ALONGSIDE := 0.21
## Ends this close to a junction move onto it, instead of making a second
## junction a few metres away whose corners and sidewalks would overlap
## (AASHTO: keep intersections well apart; streets meet head on, not jogged).
const NODE_SNAP := 20.0
## Streets meeting at less than this angle leave thin wedges and blind
## corners; AASHTO calls skews under 60° undesirable (sin 40°).
const SKEW := 0.64
## Junctions this close across the grid's direction pull a grid street over
## to line up with them, so streets continue straight instead of jogging.
const ALIGN := 18.0
## A street end that pokes this far or less past a road is cut back to it.
const STUB := 20.0
## Pieces shorter than this between two roads are dropped (no sliver blocks).
const MIN_PIECE := 20.0
## Distance at which an end counts as touching a road.
const TOUCH := 0.5
## A side this close to an old road's line is drawn along it: the old road
## is reused where they overlap and the side carries straight on past its
## end, the way a real street is extended.
const ON_LINE := 4.0


## Real US grid sizes, largest first, as centre-line spacing in metres:
## "block" runs along the first side drawn, "across" square to it.
## PLSS sections are a mile square with county roads on the section lines;
## Chicago puts streets every 1/8 and 1/16 mile; Manhattan's avenues are
## ~900 ft apart and its streets 20 to the mile (264 ft); an old Midwest
## town plat is about 400 x 300 ft; Portland's are 200 ft blocks on 60 ft
## streets (260 ft).
const PRESETS := [
	{"name": "Section", "block": 1609.0, "across": 1609.0, "about": "Farm section: 1 mile square (PLSS)"},
	{"name": "Half mile", "block": 805.0, "across": 805.0, "about": "Half-mile grid: quarter sections"},
	{"name": "Quarter mile", "block": 402.0, "across": 402.0, "about": "Quarter-mile grid: arterials and big farm lots"},
	{"name": "Manhattan", "block": 274.0, "across": 80.0, "about": "Manhattan: 900 x 264 ft"},
	{"name": "Chicago", "block": 201.0, "across": 101.0, "about": "Chicago: 1/8 x 1/16 mile (660 x 330 ft)"},
	{"name": "Town", "block": 122.0, "across": 91.0, "about": "Midwest town plat: 400 x 300 ft"},
	{"name": "Portland", "block": 79.0, "across": 79.0, "about": "Portland: 260 ft square"},
]
const BLOCK_MIN := 60.0
const BLOCK_MAX := 1700.0
const ACROSS_MIN := 70.0


## Centre-line distance two streets running side by side must keep: both
## right-of-ways (curb, parkway, sidewalk) plus a row of lots between.
static func side_gap(type_a: int, type_b: int) -> float:
	return RoadStyle.right_of_way_half(type_a) + RoadStyle.right_of_way_half(type_b) + MIN_LOT_DEPTH


## The streets to build for a grid filling `shape` (corner points, in order).
## Grid streets run square to side number `side`. `across` is the spacing of
## streets parallel to that side, `block` the spacing of the cross streets.
static func plan(network: RoadNetwork, shape: Array, block: float, type := 0, side := 0,
		across := RoadShapes.GRID_ACROSS) -> Array:
	var poly := _clean(shape)
	if poly.size() < 3 or absf(_area(poly)) < 400.0:
		return []
	side = posmod(side, poly.size())
	var o := poly[side]
	var u := (poly[(side + 1) % poly.size()] - o).normalized()
	var v := Vector2(-u.y, u.x)
	var reach := side_gap(type, RoadStyle.Type.BOULEVARD) + STUB
	var region := _box(poly).grow(reach)

	# Old roads near the shape, as polylines, and their junctions.
	var refs := []  # {"pts": PackedVector2Array, "type", "box": Rect2, "old": bool}
	for id in network.segments:
		var c := network.curve_of(id)
		if absf(c[0].y) >= RoadNetwork.SAME_LEVEL or absf(c[1].y) >= RoadNetwork.SAME_LEVEL \
				or absf(c[2].y) >= RoadNetwork.SAME_LEVEL:
			continue  # bridges and tunnels pass over or under the grid
		var pts := PackedVector2Array()
		var mid: Vector3 = (c[0] + c[2]) * 0.5
		var bend := Vector2(c[1].x - mid.x, c[1].z - mid.z).length()
		for p in RoadNetwork.sample_curve(c[0], c[1], c[2], 1 if bend < 0.01 else 32):
			pts.append(Vector2(p.x, p.z))
		var box := _box(pts)
		if box.intersects(region):
			refs.append({"pts": pts, "type": network.segments[id].type, "box": box.grow(0.5), "old": true, "id": id})
	var junctions := []  # Vector2
	var junction_ids := []
	for id in network.nodes:
		var p: Vector3 = network.nodes[id]
		if absf(p.y) < RoadNetwork.SAME_LEVEL and region.has_point(Vector2(p.x, p.z)):
			junctions.append(Vector2(p.x, p.z))
			junction_ids.append(id)
	var inside := Array(poly)  # the shape's own corners, then old junctions
	for q in junctions:
		if Geometry2D.is_point_in_polygon(q, poly) or _dist_to_outline(q, poly) < 2.0:
			inside.append(q)

	# Old roads through the shape split it into areas. A thin wedge between a
	# side and a road crossing it at a shallow angle gets no streets: the old
	# road is its edge, as a real plat stops at the county road.
	var areas := _areas(poly, refs, minf(block, across))
	if areas.is_empty():
		return []
	var corners := PackedVector2Array()  # the player's corners still in use
	for p in poly:
		for ar in areas:
			if _dist_to_outline(p, ar) < 1.0:
				corners.append(p)
				break

	# Candidates: the areas' sides first, then both families of grid streets.
	var cands := []  # [a, b, is_side]
	for ar in areas:
		for i in ar.size():
			cands.append([ar[i], ar[(i + 1) % ar.size()], true])
	for line in _family(poly, o, u, v, across, inside) + _family(poly, o, v, u, block, inside):
		for ar in areas:
			for part in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array(line), ar):
				if part.size() >= 2:
					cands.append([part[0], part[part.size() - 1], false])

	# Keep only the parts that don't run alongside a road (old or new).
	var pieces := []  # [a, b, is_side]
	for c in cands:
		for run in _free_runs(c[0], c[1], refs, type):
			pieces.append([run[0], run[1], c[2]])
			refs.append(_ref([run[0], run[1]], type))

	# Tidy the ends: join loose ones to roads, cut stubs, merge near-junctions.
	var targets := junctions.duplicate()
	targets.append_array(corners)
	for i in pieces.size():
		for k in 2:
			if not _is_corner(pieces[i][k], corners):  # the player's corners stay put
				_settle_end(pieces, i, k, refs, targets)
	var out_pieces := []
	for i in pieces.size():
		if pieces[i][0].distance_to(pieces[i][1]) >= MIN_PIECE:
			out_pieces.append(pieces[i])

	# Old dead ends inside the shape reach over to the new streets.
	var fresh := []
	for p in out_pieces:
		fresh.append(_ref(p, type))
	for id in network.nodes:
		var segs := network.segments_at(id)
		var n3: Vector3 = network.nodes[id]
		var q := Vector2(n3.x, n3.z)
		if segs.size() != 1 or absf(n3.y) >= RoadNetwork.SAME_LEVEL or not region.has_point(q):
			continue
		if not Geometry2D.is_point_in_polygon(q, poly) and _dist_to_outline(q, poly) > reach * 0.5:
			continue
		var c := network.curve_of(segs[0])
		var t := 0.0 if network.segments[segs[0]].a == id else 1.0
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
		var dir := Vector2(tan.x, tan.z).normalized() * (-1.0 if t == 0.0 else 1.0)
		var hit := _ray(q, dir, side_gap(type, network.segments[segs[0]].type), fresh, [])
		if not hit.is_empty() and q.distance_to(hit.point) > TOUCH:
			out_pieces.append([q, hit.point, true])

	# Ends that land on an old road or junction take its exact position.
	var curves := []
	var old := refs.filter(func(r): return r.old)
	for p in _drop_wedges(out_pieces, old, u, across, block, junctions, corners):
		var a := _on_network(network, p[0], old, junctions, junction_ids)
		var b := _on_network(network, p[1], old, junctions, junction_ids)
		if a.distance_to(b) >= RoadNetwork.MIN_LENGTH:
			curves.append([a, a.lerp(b, 0.5), b])
	return curves


## The shape cut into areas by the old roads that cross it, leaving out thin
## wedges: an area thinner than half a block (twice its area over its
## perimeter) with a corner sharper than 50°.
static func _areas(poly: PackedVector2Array, refs: Array, spacing: float) -> Array:
	var inner := Geometry2D.offset_polygon(poly, -1.0)
	if inner.size() != 1:
		return [poly]
	var ccw := poly.duplicate()
	if Geometry2D.is_polygon_clockwise(ccw):
		ccw.reverse()
	var areas := [ccw]
	for r in refs:
		for part in Geometry2D.intersect_polyline_with_polygon(r.pts, inner[0]):
			if part.size() < 2:
				continue
			var cut := Geometry2D.offset_polyline(part, TOUCH * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)
			var next := []
			for ar in areas:
				for c in cut:
					for piece in Geometry2D.clip_polygons(ar, c):
						if not Geometry2D.is_polygon_clockwise(piece):  # clockwise ones are holes
							next.append(piece)
					break
			if not next.is_empty():
				areas = next
	if areas.size() == 1:
		return [poly]
	var out := []
	for ar in areas:
		var a := absf(_area(ar))
		var perimeter := 0.0
		for i in ar.size():
			perimeter += ar[i].distance_to(ar[(i + 1) % ar.size()])
		if a < 400.0:
			continue
		if 2.0 * a / perimeter < spacing * 0.5 and _sharpest(ar) < deg_to_rad(50.0):
			continue
		out.append(ar)
	return out


## The sharpest outward corner of a polygon, ignoring edges under 2 m.
static func _sharpest(ar: PackedVector2Array) -> float:
	var pts := PackedVector2Array()
	for p in ar:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 2.0:
			pts.append(p)
	var best := PI
	var n := pts.size()
	var turn := signf(_area(pts))
	for i in n:
		var a := pts[(i + n - 1) % n] - pts[i]
		var b := pts[(i + 1) % n] - pts[i]
		if a.length() > 0.001 and b.length() > 0.001 and (-a).cross(b) * turn > 0.0:  # convex corners only
			best = minf(best, absf(a.angle_to(b)))
	return best


## The shape's outline as curves, for drawing it while it is placed.
static func outline(shape: Array, closed: bool) -> Array:
	var out := []
	var n := shape.size()
	for i in (n if closed else n - 1):
		var a: Vector3 = shape[i]
		var b: Vector3 = shape[(i + 1) % n]
		if a.distance_to(b) > 0.1:
			out.append([a, a.lerp(b, 0.5), b])
	return out


# --- Internals --------------------------------------------------------------

## Lines along w, spread evenly across the shape in the n direction, clipped
## to the shape. Each line shifts onto a junction inside the shape if one is
## close, so old streets carry straight on through the grid.
static func _family(poly: PackedVector2Array, o: Vector2, w: Vector2, n: Vector2,
		spacing: float, inside: Array) -> Array:
	var lo := INF
	var hi := -INF
	var wlo := INF
	var whi := -INF
	for p in poly:
		lo = minf(lo, (p - o).dot(n))
		hi = maxf(hi, (p - o).dot(n))
		wlo = minf(wlo, (p - o).dot(w))
		whi = maxf(whi, (p - o).dot(w))
	var count := maxi(1, roundi((hi - lo) / spacing))
	var step := (hi - lo) / count
	var out := []
	for i in range(1, count):
		var d := lo + i * step
		var best := minf(ALIGN, step * 0.3)
		for q in inside:
			var dq: float = (q - o).dot(n)
			if absf(dq - d) < best:
				best = absf(dq - d)
				d = dq
		var a := o + n * d + w * (wlo - 10.0)
		var b := o + n * d + w * (whi + 10.0)
		for part in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly):
			if part.size() >= 2:
				out.append([part[0], part[part.size() - 1]])
	return out


## Parts of a-b that don't run alongside any road closer than side_gap.
static func _free_runs(a: Vector2, b: Vector2, refs: Array, type: int) -> Array:
	var length := a.distance_to(b)
	if length < MIN_PIECE * 0.5:
		return []
	var w := (b - a) / length
	var near := []
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(side_gap(type, RoadStyle.Type.BOULEVARD))
	for r in refs:
		if r.box.intersects(box):
			near.append(r)
	# Each stretch of road alongside blocks one interval of a-b: distance to a
	# straight piece is convex along a-b, so search for its edges.
	var blocked := []
	for r in near:
		var gap := side_gap(type, r.type)
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			var d := pts[j + 1] - pts[j]
			if d.length() < 0.001 or absf(w.cross(d.normalized())) > ALONGSIDE:
				continue
			var f := func(t: float) -> float:
				var p := a.lerp(b, t)
				return Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p)
			var lo := 0.0
			var hi := 1.0
			for _i in 40:
				var m1 := lerpf(lo, hi, 0.382)
				var m2 := lerpf(lo, hi, 0.618)
				if f.call(m1) < f.call(m2):
					hi = m2
				else:
					lo = m1
			var best := (lo + hi) * 0.5
			if f.call(best) >= gap:
				continue
			var line := Geometry2D.get_closest_point_to_segment_uncapped
			if line.call(pts[j], a, b).distance_to(pts[j]) < ON_LINE \
					and line.call(pts[j + 1], a, b).distance_to(pts[j + 1]) < ON_LINE:
				var t0 := (pts[j] - a).dot(w) / length
				var t1 := (pts[j + 1] - a).dot(w) / length
				blocked.append([minf(t0, t1), maxf(t0, t1)])
				continue
			blocked.append([_edge_of(f, gap, best, 0.0), _edge_of(f, gap, best, 1.0)])
	blocked.sort_custom(func(x, y): return x[0] < y[0])
	var runs := []
	var start := 0.0
	for iv in blocked:
		if iv[0] > start:
			runs.append([a.lerp(b, start), a.lerp(b, iv[0])])
		start = maxf(start, iv[1])
	if start < 1.0:
		runs.append([a.lerp(b, start), b])
	var out := []
	for r in runs:
		if r[0].distance_to(r[1]) >= MIN_PIECE * 0.5:
			out.append(r)
	return out


## Where f crosses gap between inside (f < gap) and outside, searching
## from t_in toward t_out.
static func _edge_of(f: Callable, gap: float, t_in: float, t_out: float) -> float:
	if f.call(t_out) < gap:
		return t_out
	for _i in 30:
		var m := (t_in + t_out) * 0.5
		if f.call(m) < gap:
			t_in = m
		else:
			t_out = m
	return (t_in + t_out) * 0.5


## Splits the pieces at every crossing, then removes grid streets that meet
## another road at a sharp angle (and any dead end that leaves), so no two
## streets peel apart in a thin wedge with their sidewalks overlapping.
## Sides of the shape and old roads are never removed. Returns [a, b] edges.
static func _drop_wedges(pieces: Array, old: Array, u: Vector2, across: float, block: float,
		junctions: Array, corners: PackedVector2Array) -> Array:
	var edges := []  # [a, b, keep]
	for i in pieces.size():
		var a: Vector2 = pieces[i][0]
		var b: Vector2 = pieces[i][1]
		var ts := [0.0, 1.0]
		for j in pieces.size():
			if j != i:
				var hit = Geometry2D.segment_intersects_segment(a, b, pieces[j][0], pieces[j][1])
				if hit != null:
					ts.append(a.distance_to(hit) / maxf(a.distance_to(b), 0.001))
		for r in old:
			var pts: PackedVector2Array = r.pts
			for k in pts.size() - 1:
				var hit = Geometry2D.segment_intersects_segment(a, b, pts[k], pts[k + 1])
				if hit != null:
					ts.append(a.distance_to(hit) / maxf(a.distance_to(b), 0.001))
		ts.sort()
		for k in ts.size() - 1:
			var p := a.lerp(b, ts[k])
			var q := a.lerp(b, ts[k + 1])
			if p.distance_to(q) > TOUCH:
				edges.append([p, q, pieces[i][2]])
	# Old blocks are already blocks: a new street through one no bigger than
	# a grid block would only cut it into slivers.
	for i in range(edges.size() - 1, -1, -1):
		var a: Vector2 = edges[i][0]
		var b: Vector2 = edges[i][1]
		var dir := (b - a).normalized()
		var spacing := minf(across, block)
		if absf(dir.cross(u)) < 0.2:
			spacing = across
		elif absf(dir.dot(u)) < 0.2:
			spacing = block
		var reach := spacing * 1.5
		var mid := a.lerp(b, 0.5)
		var n := Vector2(-dir.y, dir.x)
		var left := _ray(mid, n, reach, old, [])
		var right := _ray(mid, -n, reach, old, [])
		if not left.is_empty() and not right.is_empty() \
				and mid.distance_to(left.point) + mid.distance_to(right.point) < reach:
			edges.remove_at(i)
	# Junctions a few metres apart become one (their corners and sidewalks
	# would overlap). Old junctions and the player's corners stay put.
	var fixed := junctions.duplicate()
	fixed.append_array(corners)
	var merge := NODE_SNAP * 0.75
	for e in edges:
		for k in 2:
			var at: Vector2 = e[k]
			if _is_corner(at, corners) or _near_any(at, junctions, TOUCH):
				continue
			var best := merge
			var to := at
			for q in fixed:
				if q.distance_to(at) < best and q.distance_to(e[1 - k]) > MIN_PIECE:
					best = q.distance_to(at)
					to = q
			if to == at:
				for f in edges:
					for m in 2:
						var q: Vector2 = f[m]
						if q.distance_to(at) > TOUCH and q.distance_to(at) < best and q.distance_to(e[1 - k]) > MIN_PIECE:
							best = q.distance_to(at)
							to = q
			if to != at:
				for f in edges:
					for m in 2:
						if f[m].distance_to(at) <= TOUCH:
							f[m] = to
	# A grid street running into an old road less than half a block on would
	# only cut off a strip too shallow for lots (the tip of a wedge).
	var shallow := minf(across, block) * 0.5
	for i in range(edges.size() - 1, -1, -1):
		var e: Array = edges[i]
		if e[0].distance_to(e[1]) >= shallow:
			continue
		var on_old := [not _old_dirs(e[0], old).is_empty(), not _old_dirs(e[1], old).is_empty()]
		if not e[2] and (on_old[0] or on_old[1]):
			edges.remove_at(i)
		elif e[2] and ((on_old[0] and _is_corner(e[1], corners)) or (on_old[1] and _is_corner(e[0], corners))):
			edges.remove_at(i)  # a corner poking just past an old road
	for i in range(edges.size() - 1, -1, -1):
		if edges[i][0].distance_to(edges[i][1]) < RoadNetwork.MIN_LENGTH:
			edges.remove_at(i)
	# Where each end meets other ends (bucketed by position) and old roads.
	var gone := []
	gone.resize(edges.size())
	gone.fill(false)
	var buckets := {}
	for i in edges.size():
		for k in 2:
			var key := Vector2i(edges[i][k].round())
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([i, k])
	var changed := true
	while changed:
		changed = false
		for i in edges.size():
			if gone[i]:
				continue
			if edges[i][2]:
				# The player's sides stay, except a stretch that leaves an old
				# road at a sharp angle (a wedge too thin to build on).
				for k in 2:
					var dir: Vector2 = (edges[i][1 - k] - edges[i][k]).normalized()
					for dj in _old_dirs(edges[i][k], old):
						if dir.dot(dj) > 0.0 and absf(dir.cross(dj)) < SKEW:
							gone[i] = true
							changed = true
				continue
			for k in 2:
				var at: Vector2 = edges[i][k]
				var dir: Vector2 = (edges[i][1 - k] - at).normalized()
				var degree := 0
				var sharp := false
				var cell := Vector2i(at.round())
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						for hit in buckets.get(cell + Vector2i(dx, dz), []):
							var j: int = hit[0]
							var m: int = hit[1]
							if j == i or gone[j] or edges[j][m].distance_to(at) > TOUCH:
								continue
							degree += 1
							var dj: Vector2 = (edges[j][1 - m] - at).normalized()
							if dir.dot(dj) > 0.0 and absf(dir.cross(dj)) < SKEW:
								sharp = true
				for dj in _old_dirs(at, old):
					degree += 1
					if dir.dot(dj) > 0.0 and absf(dir.cross(dj)) < SKEW:
						sharp = true
				if sharp or degree == 0:
					gone[i] = true
					changed = true
					break
	var kept := []
	for i in edges.size():
		if not gone[i]:
			kept.append(edges[i])
	edges = kept
	var out := []
	for e in edges:
		if e[0].distance_to(e[1]) < RoadNetwork.MIN_LENGTH:
			continue
		var dup := false
		for f in out:
			if (f[0].distance_to(e[0]) < TOUCH and f[1].distance_to(e[1]) < TOUCH) \
					or (f[0].distance_to(e[1]) < TOUCH and f[1].distance_to(e[0]) < TOUCH):
				dup = true
		if not dup:
			out.append(e)
	return out


## Joins one end of a piece to the road network: cut a stub back to the road
## it pokes past, or reach forward to a road or junction just ahead, then move
## onto a junction if one is within NODE_SNAP.
static func _settle_end(pieces: Array, i: int, k: int, refs: Array, targets: Array) -> void:
	var p: Vector2 = pieces[i][k]
	var other: Vector2 = pieces[i][1 - k]
	var length := p.distance_to(other)
	if length < 0.01:
		return
	var w := (p - other) / length  # pointing out of this end
	var mine := _ref([pieces[i][0], pieces[i][1]], 0)
	var others := []
	for r in refs:
		if not (r.pts.size() == 2 and _same_piece(r.pts, [pieces[i][0], pieces[i][1]])):
			others.append(r)
	var back := _last_crossing(other, p, others)
	var touch := _touch_dir(p, others)
	if touch == Vector2.ZERO:
		if back >= 0.0 and length * (1.0 - back) <= STUB:
			p = other.lerp(p, back)
		else:
			var hit := _ray(p, w, side_gap(0, 0), others, targets)
			if not hit.is_empty():
				p = hit.point
	elif back >= 0.0 and absf(w.cross(touch)) < SKEW:
		# Meets its road at a sharp angle: end at the last crossing instead,
		# folding the thin wedge it would leave into the block next door.
		p = other.lerp(p, back)
	# Merge with a junction (old, or another piece's end) a few metres away.
	var best := NODE_SNAP
	var snap := p
	for q in targets:
		var d: float = q.distance_to(p)
		if d < best and q.distance_to(other) > MIN_PIECE:
			best = d
			snap = q
	for j in pieces.size():
		if j == i:
			continue
		for e in [pieces[j][0], pieces[j][1]]:
			var d: float = e.distance_to(p)
			if d < best and d > 0.001 and e.distance_to(other) > MIN_PIECE and _touching(e, others):
				best = d
				snap = e
	if snap != p and _touching(p, others):
		p = snap
	pieces[i][k] = p
	# Keep this piece's own entry in refs in step.
	for r in refs:
		if r.pts.size() == 2 and _same_piece(r.pts, [mine.pts[0], mine.pts[1]]):
			r.pts = PackedVector2Array([pieces[i][0], pieces[i][1]])
			r.box = Rect2(pieces[i][0], Vector2.ZERO).expand(pieces[i][1]).grow(0.5)
			break


## Nearest thing straight ahead of p within max_dist: a road it would cross,
## or a junction roughly in line. Returns {} or {"point"}.
static func _ray(p: Vector2, w: Vector2, max_dist: float, refs: Array, targets: Array) -> Dictionary:
	var end := p + w * max_dist
	var best := max_dist + 1.0
	var out := {}
	var box := Rect2(p, Vector2.ZERO).expand(end).grow(1.0)
	for r in refs:
		if not r.box.intersects(box):
			continue
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(p, end, pts[j], pts[j + 1])
			if hit != null and p.distance_to(hit) < best:
				best = p.distance_to(hit)
				out = {"point": hit}
	# A junction roughly ahead wins over a crossing a little nearer, so the
	# street carries straight on instead of jogging.
	for q in targets:
		var d: Vector2 = q - p
		var l := d.length()
		if l - NODE_SNAP < best and l > TOUCH and l <= max_dist + NODE_SNAP \
				and (l < 6.0 or d.normalized().dot(w) > cos(deg_to_rad(25.0))):
			best = l - NODE_SNAP
			out = {"point": q}
	return out


## Where (0..1 from a to b) a-b last crosses a road, ignoring the very end; -1 if never.
static func _last_crossing(a: Vector2, b: Vector2, refs: Array) -> float:
	var best := -1.0
	var length := a.distance_to(b)
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(1.0)
	for r in refs:
		if not r.box.intersects(box):
			continue
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(a, b, pts[j], pts[j + 1])
			if hit == null:
				continue
			var t: float = a.distance_to(hit) / length
			if t > best and length * t > MIN_PIECE:
				best = t
	return best


static func _near_any(p: Vector2, pts: Array, dist: float) -> bool:
	for q in pts:
		if q.distance_to(p) <= dist:
			return true
	return false


static func _is_corner(p: Vector2, poly: PackedVector2Array) -> bool:
	for q in poly:
		if q.distance_to(p) < 0.01:
			return true
	return false


## Directions old roads leave p in (none if no old road passes p).
static func _old_dirs(at: Vector2, old: Array) -> Array:
	var out := []
	for r in old:
		if not r.box.grow(TOUCH).has_point(at):
			continue
		var pts: PackedVector2Array = r.pts
		for m in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(at, pts[m], pts[m + 1]).distance_to(at) <= TOUCH:
				for end in [pts[m], pts[m + 1]]:
					if end.distance_to(at) > TOUCH:
						out.append((end - at).normalized())
	return out


## Direction of the road p sits on, or ZERO if it isn't on one.
static func _touch_dir(p: Vector2, refs: Array) -> Vector2:
	for r in refs:
		if not r.box.grow(TOUCH).has_point(p):
			continue
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p) <= TOUCH \
					and pts[j].distance_to(pts[j + 1]) > 0.001:
				return (pts[j + 1] - pts[j]).normalized()
	return Vector2.ZERO


static func _touching(p: Vector2, refs: Array) -> bool:
	for r in refs:
		if not r.box.grow(TOUCH).has_point(p):
			continue
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p) <= TOUCH:
				return true
	return false


static func _same_piece(pts: PackedVector2Array, piece: Array) -> bool:
	return (pts[0].is_equal_approx(piece[0]) and pts[1].is_equal_approx(piece[1])) \
		or (pts[0].is_equal_approx(piece[1]) and pts[1].is_equal_approx(piece[0]))


static func _ref(piece: Array, type: int) -> Dictionary:
	var pts := PackedVector2Array([piece[0], piece[1]])
	return {"pts": pts, "type": type, "box": _box(pts).grow(0.5), "old": false}


## A ground point on the network: an old junction or road if one is right
## there (exactly, so build_road joins it), otherwise the point itself.
static func _on_network(network: RoadNetwork, q: Vector2, old: Array, junctions: Array,
		junction_ids: Array) -> Vector3:
	for i in junctions.size():
		if junctions[i].distance_to(q) <= 2.0:
			return network.nodes[junction_ids[i]]
	for r in old:
		if not r.box.grow(2.0).has_point(q):
			continue
		var pts: PackedVector2Array = r.pts
		for j in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(q, pts[j], pts[j + 1]).distance_to(q) > 2.0:
				continue
			# Closest point on the real curve, found finely along this road only.
			var c := network.curve_of(r.id)
			var best := INF
			var at := Vector3(q.x, 0.0, q.y)
			for k in 257:
				var b := RoadNetwork.bezier(c[0], c[1], c[2], k / 256.0)
				var d := Vector2(b.x, b.z).distance_to(q)
				if d < best:
					best = d
					at = b
			return at
	return Vector3(q.x, 0.0, q.y)


static func _clean(shape: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in shape:
		var q := Vector2(p.x, p.z)
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 1.0:
			out.append(q)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 1.0:
		out.remove_at(out.size() - 1)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


static func _box(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


static func _dist_to_outline(q: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q))
	return best


## The rectangle the old three-click grid meant: a to b is the first street,
## c sets how far back it reaches, in whole rows of lots. Two points if it
## doesn't reach back at all (a single street).
static func rect(a: Vector3, b: Vector3, c: Vector3, across := RoadShapes.GRID_ACROSS) -> Array:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length() < RoadNetwork.MIN_LENGTH:
		return []
	var u := along.normalized()
	var v := Vector3(-u.z, 0.0, u.x)
	var reach := (c - a).dot(v)
	if reach < 0.0:
		v = -v
		reach = -reach
	var rows := roundi(reach / across)
	if rows == 0:
		return [a, b]
	var back := v * (rows * across)
	return [a, b, b + back, a + back]
