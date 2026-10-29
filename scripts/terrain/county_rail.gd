class_name CountyRail
## The real railroads across the county (terrain/grant_in/rail.json, from
## OpenStreetMap through Overture, tools/terrain/build_roads.py), as a route
## layer like the state highways (Highways): each line's points, its length
## along, and the level its track is laid at, every STEP metres. Region
## coordinates throughout.
##
## Scenery for now, drawn by CountyRailView on the desktop app (the browser
## leaves it out), with the trees and crops kept off its right of way. The
## routes, near() and crossing() are what a train or a town's own track
## (Rail) can later run on and join.
##
## The track's level: real main lines climb at most about 1 % and run on a
## low fill of their own across flat Indiana, so the bed follows the base
## ground (Terrain.base: graded, and a deck over rivers) averaged over
## SMOOTH metres either way, never below the ground where it stands. Where a
## road crosses at grade, the bed eases down so the rail tops are flush with
## the road (MUTCD/AREMA grade crossings: a level surface across the rails).

## Metres between the samples of a line's profile.
const STEP := 4.0
## Metres either way a line's corners are rounded over.
const CURVE := 16.0
## Metres either way the bed's level is averaged over.
const SMOOTH := 32.0
## Half the right of way kept clear of trees (a 100 ft right of way, brush
## cut back about 40 ft from the track).
const TREE_CLEAR := 12.0
## Half the strip crops keep off (the bed, its ditches and fence).
const CROP_CLEAR := 9.0
## From the track's level up to the top of the rail (RailView draws the
## ballast, ties and rails on it, as on a town's own track).
const RAIL_TOP := RailView.RAIL_Y
## The steepest the track climbs away from a crossing (a branch line's
## ruling grade; main lines keep nearer 1 %).
const GRADE := 0.02
## A road within this many metres of the track's middle line: a grade
## crossing (the road's half width and its crossing panels).
const CROSSING := 7.0
## Metres over which the bed eases down to a crossing.
const RAMP := 24.0
## Two lines nearer than this (metres) share one bed (track centres are
## 14 ft apart on double track).
const PAIRED := 6.0
## The longest gap between two mapped lines that is joined (metres).
const GAP := 320.0
## Size of the bins the lines are filed in for lookups, metres.
const BIN := 256.0

static var _loaded := false
## Each route: {pts: PackedVector2Array, cum: PackedFloat32Array}; read
## them through all(). Profiles are made the first time a line is asked.
static var routes: Array = []
static var _bins := {}  # Vector2i -> [[route, segment], ...]
## route -> {at: PackedVector2Array, bed: PackedFloat32Array, kind:
## PackedByteArray} every STEP metres along it (kind: 0 bed, 1 grade
## crossing, 2 bridge, 3 not drawn: inside a backdrop town).
static var _profiles := {}
static var _settled := {}


## Whether the railroads are drawn here and keep the trees off: the desktop
## app only (the browser stays as it was).
static func drawn() -> bool:
	return not OS.has_feature("web")


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := Terrain.DIR + "rail.json"
	if not FileAccess.file_exists(path):
		return
	var json = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(json) != TYPE_DICTIONARY:
		push_error("CountyRail: can't read rail.json")
		return
	var lo := Terrain.CENTRE - Vector2.ONE * Terrain.SIZE * 0.5
	var area := Rect2(lo, Vector2.ONE * Terrain.SIZE)
	var runs := []
	for line in json.lines:
		var pts := PackedVector2Array()
		for q in line:
			pts.append(Vector2(float(q[0]), float(q[1])))
		# Only the part on the map (the rest of the file runs on into the
		# next counties), as one route per stretch on it.
		var run := PackedVector2Array()
		for i in pts.size():
			if area.has_point(pts[i]):
				if run.is_empty() and i > 0:
					run.append(pts[i - 1].clamp(area.position, area.end))
				run.append(pts[i])
			elif not run.is_empty():
				run.append(pts[i].clamp(area.position, area.end))
				runs.append(run)
				run = PackedVector2Array()
		if not run.is_empty():
			runs.append(run)
	_join(runs)
	for r in runs:
		_add(r)


## The mapped lines stop short of each other in places (up to a few
## hundred metres where a way was left out): a line's end that heads
## straight at another line within GAP metres carries on to it.
static func _join(runs: Array) -> void:
	for a in runs.size():
		for end in [0, 1]:
			var pts: PackedVector2Array = runs[a]
			if pts.size() < 2:
				continue
			var e := pts[pts.size() - 1] if end == 1 else pts[0]
			var before := pts[pts.size() - 2] if end == 1 else pts[1]
			var dir := (e - before).normalized()
			var best := Vector2.INF
			var best_d := GAP
			var joined := false  # already meets a line
			for b in runs.size():
				if b == a:
					continue
				for q: Vector2 in runs[b]:
					var d := e.distance_to(q)
					joined = joined or d <= 3.0
					if d > 3.0 and d < best_d and dir.dot((q - e) / d) > cos(deg_to_rad(30.0)):
						best_d = d
						best = q
			if best != Vector2.INF and not joined:
				if end == 1:
					pts.append(best)
				else:
					pts.insert(0, best)
				runs[a] = pts


static func _add(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	if cum[cum.size() - 1] < 50.0:
		return
	var id := routes.size()
	routes.append({"pts": pts, "cum": cum})
	for i in pts.size() - 1:
		var lo := Vector2i((pts[i].min(pts[i + 1]) / BIN).floor())
		var hi := Vector2i((pts[i].max(pts[i + 1]) / BIN).floor())
		for bx in range(lo.x, hi.x + 1):
			for bz in range(lo.y, hi.y + 1):
				var k := Vector2i(bx, bz)
				if not _bins.has(k):
					_bins[k] = []
				_bins[k].append([id, i])


## The routes (see `routes`), loaded.
static func all() -> Array:
	_load()
	return routes


## A route's length, metres.
static func length(route: int) -> float:
	_load()
	var cum: PackedFloat32Array = routes[route].cum
	return cum[cum.size() - 1]


## The point metres `s` along a route.
static func point(route: int, s: float) -> Vector2:
	_load()
	var r: Dictionary = routes[route]
	var pts: PackedVector2Array = r.pts
	var cum: PackedFloat32Array = r.cum
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var i := clampi(cum.bsearch(s) - 1, 0, pts.size() - 2)
	var span := cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], (s - cum[i]) / span if span > 0.0 else 0.0)


## The track nearest a point, if one runs within `reach` metres: {route,
## seg, on (the nearest point), along (metres from the route's start),
## dist}, or {}.
static func near(x: float, z: float, reach: float) -> Dictionary:
	_load()
	var p := Vector2(x, z)
	var best := {}
	var best_d := reach
	var lo := Vector2i(((p - Vector2(reach, reach)) / BIN).floor())
	var hi := Vector2i(((p + Vector2(reach, reach)) / BIN).floor())
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			for e in _bins.get(Vector2i(bx, bz), []):
				var r: Dictionary = routes[e[0]]
				var a: Vector2 = r.pts[e[1]]
				var b: Vector2 = r.pts[e[1] + 1]
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := q.distance_to(p)
				if d <= best_d:
					best_d = d
					best = {"route": e[0], "seg": e[1], "on": q, "dist": d,
						"along": r.cum[e[1]] + a.distance_to(q)}
	return best


## How far a point is from the nearest track's middle line, metres, or INF
## past `reach`.
static func distance(x: float, z: float, reach := 30.0) -> float:
	var n := near(x, z, reach)
	return n.dist if not n.is_empty() else INF


## True where the railroad's right of way keeps trees (or, with `half`,
## anything else) off, on the desktop app.
static func clears(x: float, z: float, half := TREE_CLEAR) -> bool:
	if not drawn():
		return false
	var n := near(x, z, half)
	return not n.is_empty() and kind_at(n.route, n.along) != 3


## Where the line a-b (region coordinates) crosses a track: {route, seg,
## on, along}, or {}.
static func crossing(a: Vector2, b: Vector2) -> Dictionary:
	_load()
	var lo := Vector2i((a.min(b) / BIN).floor())
	var hi := Vector2i((a.max(b) / BIN).floor())
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			for e in _bins.get(Vector2i(bx, bz), []):
				var r: Dictionary = routes[e[0]]
				var p: Vector2 = r.pts[e[1]]
				var q: Vector2 = r.pts[e[1] + 1]
				var hit = Geometry2D.segment_intersects_segment(a, b, p, q)
				if hit != null:
					return {"route": e[0], "seg": e[1], "on": hit, "along": r.cum[e[1]] + p.distance_to(hit)}
	return {}


## The routes with a piece in the square bin `b` (BIN metres).
static func routes_in(b: Vector2i) -> Array:
	_load()
	var out := []
	for e in _bins.get(b, []):
		if not e[0] in out:
			out.append(e[0])
	return out


## Whether any track runs through a box (region coordinates), by its bins.
static func any_in(box: Rect2) -> bool:
	_load()
	var lo := Vector2i((box.position / BIN).floor())
	var hi := Vector2i((box.end / BIN).floor())
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			if _bins.has(Vector2i(bx, bz)):
				return true
	return false


## A route's profile every STEP metres (see _profiles).
static func profile(route: int) -> Dictionary:
	_load()
	if _profiles.has(route):
		return _profiles[route]
	var total := length(route)
	var n := maxi(2, ceili(total / STEP) + 1)
	var at := PackedVector2Array()
	var raw := PackedFloat32Array()
	var road := PackedFloat32Array()
	var kind := PackedByteArray()
	at.resize(n)
	raw.resize(n)
	road.resize(n)
	kind.resize(n)
	for i in n:
		at[i] = point(route, minf(i * STEP, total))
	# Real track bends in smooth curves; the mapped line has a corner at
	# each of its points. Averaged over CURVE metres either way (the ends
	# stay put, so lines still meet).
	var c := int(CURVE / STEP)
	var line := at.duplicate()
	for i in range(1, n - 1):
		var k := mini(c, mini(i, n - 1 - i))
		var sum := Vector2.ZERO
		for j in range(i - k, i + k + 1):
			sum += line[j]
		at[i] = sum / float(2 * k + 1)
	for i in n:
		var p := at[i]
		raw[i] = Terrain.base(p.x, p.y)
		road[i] = minf(CountyGrid.distance(p.x, p.y), Highways.distance(p.x, p.y))
		if Backdrop.inside(p):
			kind[i] = 3
		elif Terrain.water(p.x, p.y) > 0.3 and raw[i] - Terrain.height(p.x, p.y) > 2.5:
			kind[i] = 2
		elif road[i] < CROSSING:
			kind[i] = 1
		if kind[i] != 2:
			# Off a bridge, never under the ground as drawn, across the
			# ballast's whole crown.
			var t := point(route, minf(i * STEP + 1.0, total)) - point(route, maxf(i * STEP - 1.0, 0.0))
			var side := Vector2(-t.y, t.x).normalized() * 1.6
			var edges := maxf(Terrain.height(p.x + side.x, p.y + side.y), Terrain.height(p.x - side.x, p.y - side.y))
			raw[i] = maxf(raw[i], maxf(Terrain.height(p.x, p.y), edges - 0.25))
	# The bed: the base averaged either way (a running sum), never under it.
	var w := int(SMOOTH / STEP)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	sums[0] = 0.0
	for i in n:
		sums[i + 1] = sums[i] + raw[i]
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var a := maxi(0, i - w)
		var b := mini(n - 1, i + w)
		var avg := (sums[b + 1] - sums[a]) / float(b - a + 1)
		bed[i] = maxf(avg, raw[i])
	# No steeper than GRADE either way: a bump in the ground lifts the track
	# onto a gentle hump of fill, as a real line would be built.
	var rise := GRADE * STEP
	for i in range(1, n):
		if kind[i] != 2 and kind[i - 1] != 2:
			bed[i] = maxf(bed[i], bed[i - 1] - rise)
	for i in range(n - 2, -1, -1):
		if kind[i] != 2 and kind[i + 1] != 2:
			bed[i] = maxf(bed[i], bed[i + 1] - rise)
	# Down to the road at each grade crossing, easing in over RAMP metres:
	# the rail tops at the road's surface.
	var ramp := int(RAMP / STEP)
	for i in n:
		if kind[i] != 1:
			continue
		var flush := raw[i] - RAIL_TOP + RailView.CROSSING_RAIL
		for j in range(maxi(0, i - ramp), mini(n, i + ramp + 1)):
			var t := clampf((absf(j - i) * STEP - CROSSING) / (RAMP - CROSSING), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			bed[j] = minf(bed[j], lerpf(flush, maxf(bed[j], flush), t))
	var prof := {"at": at, "bed": bed, "kind": kind}
	_profiles[route] = prof
	return prof


## What the track is at metres `s` along a route (see _profiles' kind).
static func kind_at(route: int, s: float) -> int:
	var prof := profile(route)
	var k: PackedByteArray = prof.kind
	return k[clampi(roundi(s / STEP), 0, k.size() - 1)]


## The bed's level at metres `s` along a route (metres above sea level);
## the rail tops are RAIL_TOP above it.
static func bed_at(route: int, s: float) -> float:
	var prof := profile(route)
	var bed: PackedFloat32Array = prof.bed
	var f := clampf(s / STEP, 0.0, bed.size() - 1.0)
	var i := mini(floori(f), bed.size() - 2)
	return lerpf(bed[i], bed[i + 1], f - i)


## Where two lines run side by side in the square bin `b` (double track,
## a siding, a passing track: about 14 ft apart), lays both at the higher
## level, on one shared bed. Once a square.
static func settle(b: Vector2i) -> void:
	if _settled.has(b):
		return
	_settled[b] = true
	var box := Rect2(Vector2(b) * BIN, Vector2.ONE * BIN).grow(PAIRED)
	var list := routes_in(b)
	for ia in list.size():
		for ib in range(ia + 1, list.size()):
			var pa := profile(list[ia])
			var pb := profile(list[ib])
			var at_a: PackedVector2Array = pa.at
			var at_b: PackedVector2Array = pb.at
			var bed_a: PackedFloat32Array = pa.bed
			var bed_b: PackedFloat32Array = pb.bed
			var kind_a: PackedByteArray = pa.kind
			var kind_b: PackedByteArray = pb.kind
			var near_b := []
			for j in at_b.size():
				if box.has_point(at_b[j]):
					near_b.append(j)
			if near_b.is_empty():
				continue
			for i in at_a.size():
				if not box.has_point(at_a[i]):
					continue
				for j in near_b:
					if kind_a[i] == kind_b[j] and at_a[i].distance_squared_to(at_b[j]) < PAIRED * PAIRED:
						var top := maxf(bed_a[i], bed_b[j])
						bed_a[i] = top
						bed_b[j] = top
			pa.bed = bed_a
			pb.bed = bed_b
