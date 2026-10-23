class_name LotPlanner
extends RefCounted
## Surveys building lots the way a real plat is drawn, not as a grid of equal
## boxes. The player zones street frontage; the planner then:
##   - gives every bit of a block to the street it is closest to, so the backs
##     of the lots meet in the middle of the block and nothing is left over
##   - draws side lot lines at right angles (or radial) to the street, so lots
##     fan out on curves and narrow to pie shapes on the inside of bends
##   - varies widths within real ranges, makes corner lots wider and joins the
##     two halves of a corner into one lot with frontage on both streets
##   - puts flag lots (a 20 ft drive "pole" out to the street) in blocks too
##     deep for one row of lots
## Benchmarks: Midwestern plats and county parcel maps first, then the
## zoning strips of Cities: Skylines 2.
##
## Lots come only from the roads, the zones and the saved parcels (lots that
## already have a building), so every player works out the same lots.

const DEPTH := 36.0  # a typical lot depth, for rings and searches
const FRONTAGE := 20.0  # a typical lot width
## Spacing of the survey lines along each street.
const RAY_STEP := 3.0
## How far back from a street the survey looks for land.
const REACH := 110.0
## Where along its depth a lot reads its zone (the brush paints here).
const ZONE_PROBE := 5.0
## A flag lot's drive strip: 20 ft, the usual minimum.
const POLE := 6.0
## Spare depth behind a full lot that is worth a flag lot.
const FLAG_MIN := 24.0
## How deep a flag lot's back yard can go.
const REAR_CAP := 40.0

## Real lot sizes in metres (zone ints match ZoneMap.Zone: 1 homes, 2 shops,
## 3 industry). w: width range along the street; cap: usual depth;
## min_d: shallowest buildable lot. Homes and shops run 50 to 80 ft wide
## (real Midwestern town and suburban lots, 130 ft deep); plants are wider.
const SIZES := {
	1: {"w": [15.0, 24.0], "cap": 40.0, "min_d": 18.0, "flags": true},
	2: {"w": [15.0, 24.0], "cap": 38.0, "min_d": 18.0, "flags": false},
	3: {"w": [26.0, 44.0], "cap": 60.0, "min_d": 26.0, "flags": false},
}
## The most a lot can grow to by merging: [frontage m, area m²], from typical
## Midwest zoning codes. Shops on a Street are main-street storefronts; on an
## Avenue or Boulevard they are highway commercial.
const MAX_LOT := {
	"home": [46.0, 2800.0],  # about 150 ft, two-thirds of an acre (estate lots)
	"apartments": [60.0, 6000.0],
	"main_street": [30.0, 1500.0],
	"highway_shop": [120.0, 20000.0],  # a big box, about 5 acres
	"industry": [200.0, 80000.0],  # about 20 acres
}

## How well-off the neighbourhood at a point is, 0 (struggling) to 1
## (wealthy). Wealthier streets get platted with wider lots, as real
## subdivisions do. Must be deterministic sim state (multiplayer).
var wealth := Callable()

# Survey cache: the survey lines only change when roads do.
var _sig := {}     # seg id -> String (its shape and type)
var _seg_box := {}  # seg id -> Rect2 (its centre line)
var _pieces := {}  # seg id -> Array of [Vector2 a, Vector2 b, float half ROW, Rect2]
var _sides := {}   # "seg:side" -> side Dictionary (see _side)
var _grown := {}   # parcel hash -> [box, outline grown 0.3 m, hash]
var _unions := {}  # corner pair -> [hash of both outlines, merged outline]
var _last_parcels := {}  # parcel key -> hash, from the last plan
## Areas where zones or parcels changed: only street sides near them are cut
## again; the rest keep their lots (the same inputs give the same lots).
var _dirty: Array = []
var _fresh := true
## Areas where roads changed on the last plan (for saved parcels).
var changed_boxes: Array = []


## Returns an Array of lot Dictionaries:
## key, seg, side, pos (middle), front (where the building's street edge is),
## road (the street centre opposite the front), zone_pt (where the lot reads
## its zone), dir (along the street), normal (away from it), corners (the
## outline, any number of points), at_frac, to_curb, width, depth, area,
## corner, flag, sig.
## `frozen` maps key -> lot for parcels that must stay as they are.
## Call update(network) first.
func plan(network: RoadNetwork, zones: ZoneMap, frozen: Dictionary) -> Array:
	var parcels := []
	var keys := frozen.keys()
	keys.sort()
	for key in keys:
		var c: PackedVector2Array = frozen[key].corners
		if c.size() < 3:
			continue
		var h := hash([key, c])
		if not _grown.has(h):
			var grown := Geometry2D.offset_polygon(c, 0.3)
			_grown[h] = [_box(c).grow(0.5), grown[0] if not grown.is_empty() else c, h]
		parcels.append(_grown[h])
	# Parcels that came, went or changed mark their ground for re-cutting.
	var now := {}
	for p in parcels:
		now[p[2]] = p
	for h in now:
		if not _last_parcels.has(h):
			_dirty.append((now[h][0] as Rect2).grow(1.0))
	for h in _last_parcels:
		if not now.has(h):
			_dirty.append((_last_parcels[h] as Rect2).grow(1.0))
	_last_parcels.clear()
	for h in now:
		_last_parcels[h] = now[h][0]
	_dirty.append_array(zones.dirty)
	zones.dirty.clear()
	if _grown.size() > parcels.size() * 2 + 64:
		var keep := {}
		for p in parcels:
			keep[p[2]] = _grown[p[2]]
		_grown = keep
	var all := []
	var corners := []
	var ids := network.segments.keys()
	ids.sort()
	for id in ids:
		if not _lot_road(network, id):
			continue
		for side in [-1, 1]:
			var s := _side(network, id, side)
			if s.is_empty():
				continue
			var lots_here: Array = s.cut
			if _fresh or s.cut_sig == 0 or _near_dirty(s):
				lots_here = _plan_side(s, zones, parcels)
			for cached in lots_here:
				var lot: Dictionary = cached.duplicate()
				all.append(lot)
				if lot.has("corner_by"):
					corners.append(lot)
	_dirty.clear()
	_fresh = false
	_join_corners(all, corners)
	var out := []
	for lot in all:
		if not frozen.has(lot.key):
			lot.erase("corner_by")
			out.append(lot)
	return out


## Lots never cross a saved parcel: trims them, or drops them if little is
## left.
static func _clear_of_parcels(lots: Array, parcels: Array) -> Array:
	var out := []
	for lot in lots:
		var keep := true
		var box := _box(lot.corners)
		for p in parcels:
			if not (p[0] as Rect2).intersects(box):
				continue
			var cut := Geometry2D.clip_polygons(lot.corners, p[1])
			var best := _largest(cut)
			var before := absf(_area(lot.corners))
			if absf(_area(best)) < before - 1.0:
				if absf(_area(best)) < before * 0.7 or cut.size() > 1 and _holes(cut):
					keep = false
					break
				_set_shape(lot, best)
		if keep:
			out.append(lot)
	return out


# --------------------------------------------------------------- survey cache

## True for roads that have driveways (not highways, ramps, rings or bridges).
static func _lot_road(network: RoadNetwork, id: int) -> bool:
	var c := network.curve_of(id)
	return RoadStyle.TYPES[network.segments[id].type].lots and absf(c[0].y) <= 0.5 and absf(c[2].y) <= 0.5


## The shape signature of a road, as saved parcels remember it.
func sig_of(id: int) -> String:
	return _sig.get(id, "")


## One street side's survey: {"rays": [[a, front, normal, depth, by]...], ...},
## or {} for roads without lots.
func side_survey(network: RoadNetwork, id: int, side: int) -> Dictionary:
	if not network.segments.has(id) or not _lot_road(network, id):
		return {}
	var s := _side(network, id, side)
	_survey(s)
	return s


## Brings the survey up to date with the roads. Call before plan().
func update(network: RoadNetwork) -> void:
	changed_boxes.clear()
	var seen := {}
	for id in network.segments:
		seen[id] = true
		var c := network.curve_of(id)
		var sig := "%s|%s|%s|%d" % [c[0], c[1], c[2], network.segments[id].type]
		if _sig.get(id, "") == sig:
			continue
		if _seg_box.has(id):
			changed_boxes.append(_seg_box[id])
		_sig[id] = sig
		var pts := _sample(network, id)
		var half := RoadStyle.right_of_way_half(network.segments[id].type)
		var pieces := []
		var box := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			pieces.append([a, b, half, Rect2(a, Vector2.ZERO).expand(b), id])
			box = box.expand(b)
		_pieces[id] = pieces
		_seg_box[id] = box
		changed_boxes.append(box)
	for id in _sig.keys():
		if not seen.has(id):
			changed_boxes.append(_seg_box[id])
			_sig.erase(id)
			_pieces.erase(id)
			_seg_box.erase(id)
	if changed_boxes.is_empty():
		return
	# Any side whose survey could reach a changed road is surveyed again.
	var reach := REACH * 2.0 + 30.0
	for key in _sides.keys():
		var s: Dictionary = _sides[key]
		if not network.segments.has(s.seg) or _sig.get(s.seg, "") != s.sig:
			_sides.erase(key)
			continue
		var box: Rect2 = (s.box as Rect2).grow(reach)
		for b in changed_boxes:
			if box.intersects(b):
				_sides.erase(key)
				break


## Straight roads need just their two ends; curves get more points.
static func _sample(network: RoadNetwork, id: int) -> PackedVector3Array:
	var c := network.curve_of(id)
	var mid: Vector3 = (c[0] + c[2]) * 0.5
	var bend := Vector2(c[1].x - mid.x, c[1].z - mid.z).length()
	return network.sample_segment(id, 1 if bend < 0.05 else 16)


## One side of a street: its centre line, frontage offset and survey lines.
func _side(network: RoadNetwork, id: int, side: int) -> Dictionary:
	var key := "%d:%d" % [id, side]
	if _sides.has(key):
		return _sides[key]
	var pts := _sample(network, id)
	var type: int = network.segments[id].type
	var s := {
		"seg": id, "side": side, "type": type, "sig": _sig[id], "pts": pts,
		"len": RoadNetwork.polyline_length(pts),
		"off": RoadStyle.right_of_way_half(type) + 0.3,
		"to_curb": RoadStyle.right_of_way_half(type) + 0.3 - RoadStyle.half_width(type),
		"box": _seg_box[id], "curve": network.curve_of(id),
	}
	# Roads that can claim this side's land.
	var near := (s.box as Rect2).grow(REACH * 2.0 + 30.0)
	var claim := []
	var others := _pieces.keys()
	others.sort()
	var mid := (s.box as Rect2).get_center()
	for o in others:
		if o != id and near.intersects(_seg_box[o]):
			for p in _pieces[o]:
				claim.append([_rect_dist(p[3], mid), p])
	# Nearest roads first, so most lines find their claim early.
	claim.sort()
	s.claim = claim.map(func(c): return c[1])
	# Where each survey line meets the street; depths come later, only for
	# sides that are zoned.
	var fronts := []
	var n := maxi(1, ceili(s.len / RAY_STEP))
	for i in n + 1:
		var a: float = s.len * i / n
		var at := _on_curve(s, a)
		var nn := Vector2(-at[1].z, at[1].x) * side
		fronts.append([a, Vector2(at[0].x, at[0].z) + nn * s.off, nn])
	s.fronts = fronts
	s.rays = []
	s.cut_sig = 0
	s.cut = []
	_sides[key] = s
	return s


## The side's survey lines with their depths (worked out once).
static func _survey(s: Dictionary) -> Array:
	if s.rays.is_empty():
		var rays := []
		for f in s.fronts:
			rays.append(_ray(s, f[0]))
		_converge(rays)
		s.rays = rays
	return s.rays


## A survey line at distance `a` along the street: [a, front Vector2,
## normal Vector2, depth (-1 = the front is inside another road), claimed by
## (that road's half right-of-way, or -1 when it ran to REACH), claiming road
## id (or -1)].
static func _ray(s: Dictionary, a: float) -> Array:
	var at := _on_curve(s, a)
	var dir: Vector3 = at[1]
	var n: Vector2 = Vector2(-dir.z, dir.x) * s.side
	var road := Vector2(at[0].x, at[0].z)
	var f: Vector2 = road + n * s.off
	var best := REACH
	var by := -1.0
	var by_seg := -1
	for p in s.claim:
		var box: Rect2 = p[3]
		var k: float = p[2] + 0.25
		# Too far away to reach this line within `best`.
		if _rect_dist(box, f) > best * 2.0 + k:
			continue
		var t := _first_claim(f, n, p[0], p[1], k)
		if t < 0.0:
			return [a, f, n, -1.0, p[2], p[4]]
		if t < best:
			best = t
			by = p[2]
			by_seg = p[4]
	return [a, f, n, best, by, by_seg]


## Point and smooth direction at distance `a` along a side's street (the
## curve's own tangent, so survey lines fan evenly round bends).
static func _on_curve(s: Dictionary, a: float) -> Array:
	var pts: PackedVector3Array = s.pts
	var c: Array = s.curve
	var n := pts.size() - 1
	var dist := 0.0
	for i in n:
		var d := pts[i].distance_to(pts[i + 1])
		if dist + d >= a or i == n - 1:
			var t := (i + clampf((a - dist) / maxf(d, 0.001), 0.0, 1.0)) / n
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
			tan.y = 0.0
			return [RoadNetwork.bezier(c[0], c[1], c[2], t), tan.normalized()]
		dist += d
	return [pts[0], Vector3.FORWARD]


## Inside a curve the survey lines cross: stop each where it meets the next.
static func _converge(rays: Array) -> void:
	for i in range(rays.size() - 1):
		var r: Array = rays[i]
		var q: Array = rays[i + 1]
		if r[3] <= 0.0 or q[3] <= 0.0 or (r[2] as Vector2).dot(q[2]) > 0.9998:
			continue
		var hit = Geometry2D.line_intersects_line(r[1], r[2], q[1], q[2])
		if hit == null:
			continue
		var tr: float = ((hit as Vector2) - r[1]).dot(r[2])
		var tq: float = ((hit as Vector2) - q[1]).dot(q[2])
		if tr > 0.0 and tq > 0.0:
			r[3] = minf(r[3], tr)
			q[3] = minf(q[3], tq)


## First distance t along the line f + n·t where a road piece a-b (with
## half right-of-way k) is no farther than the street the line starts from,
## i.e. dist(p, ab) <= t + k. -1 if f itself is inside that road; INF if never.
## Exact: the distance is linear along the line (sides) or a square root that
## cancels (ends), so every case is a linear equation.
static func _first_claim(f: Vector2, n: Vector2, a: Vector2, b: Vector2, k: float) -> float:
	var d0 := Geometry2D.get_closest_point_to_segment(f, a, b).distance_to(f)
	if d0 <= k - 0.3:
		return -1.0
	if d0 <= k:
		return 0.0
	var cands := []
	var d := b - a
	var l := d.length()
	if l > 0.0001:
		var u := d / l
		var m := Vector2(-u.y, u.x)
		var s0 := m.dot(f - a)
		var s1 := m.dot(n)
		for sg in [1.0, -1.0]:
			var den: float = sg * s1 - 1.0
			if absf(den) > 0.000001:
				cands.append((k - sg * s0) / den)
	for e in [a, b]:
		var w: Vector2 = f - e
		var den := 2.0 * (n.dot(w) - k)
		if absf(den) > 0.000001:
			cands.append((k * k - w.length_squared()) / den)
	cands.sort()
	for t in cands:
		if t < 0.0 or t > REACH:
			continue
		var p: Vector2 = f + n * t
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= t + k + 0.01:
			return t
	return INF


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)


# ------------------------------------------------------------------ lot lines

## Cuts one street side's zoned frontage into lots.
func _near_dirty(s: Dictionary) -> bool:
	var area := (s.box as Rect2).grow(REACH + 10.0)
	for r in _dirty:
		if area.intersects(r):
			return true
	return false


func _plan_side(s: Dictionary, zones: ZoneMap, all_parcels: Array) -> Array:
	# Zones first: most street sides aren't zoned and need no survey.
	var any := false
	for f in s.fronts:
		if zones.zone_at(_v3((f[1] as Vector2) + (f[2] as Vector2) * ZONE_PROBE)) != 0:
			any = true
			break
	if not any:
		s.cut_sig = 1
		s.cut = []
		return []
	var area := (s.box as Rect2).grow(REACH + 10.0)
	var parcels := []
	var near_keys := []
	for p in all_parcels:
		if area.intersects(p[0]):
			parcels.append(p)
			near_keys.append(p[2])
	var rays := _survey(s)
	# What each survey line is: its zone, or 0 when it can't hold a lot.
	var kinds := []
	for r in rays:
		var k := 0
		if r[3] >= 0.0 and not _in_parcel(r[1], parcels):
			k = zones.zone_at(_v3((r[1] as Vector2) + (r[2] as Vector2) * ZONE_PROBE))
		kinds.append(k)
	var mid: Vector2 = s.fronts[s.fronts.size() / 2][1]
	var sig := hash([kinds, near_keys, wealth.call(mid) if wealth.is_valid() else 0.5])
	if sig == s.cut_sig:
		return s.cut
	var out := []
	var i := 0
	while i < rays.size():
		if kinds[i] == 0:
			i += 1
			continue
		var j := i
		while j + 1 < rays.size() and kinds[j + 1] == kinds[i]:
			j += 1
		var a0: float = rays[i][0]
		var a1: float = rays[j][0]
		var start_corner := false
		var end_corner := false
		# Find the exact ends of the run between survey lines.
		if i > 0:
			a0 = _edge(s, rays[i - 1][0], a0, kinds[i - 1], kinds[i], zones, parcels)
			start_corner = rays[i - 1][3] < 0.0
		elif rays[i][3] < SIZES[kinds[i]].cap * 0.5 and rays[i][4] >= 0.0:
			start_corner = true
		if j < rays.size() - 1:
			a1 = _edge(s, a1, rays[j + 1][0], kinds[j], kinds[j + 1], zones, parcels)
			end_corner = rays[j + 1][3] < 0.0
		elif rays[j][3] < SIZES[kinds[j]].cap * 0.5 and rays[j][4] >= 0.0:
			end_corner = true
		out.append_array(_cut_run(s, kinds[i], a0, a1, start_corner, end_corner))
		i = j + 1
	out = _clear_of_parcels(out, parcels)
	s.cut_sig = sig
	s.cut = out
	return out


## Where a run ends between two survey lines a_in (inside) and a_out.
func _edge(s: Dictionary, a_in: float, a_out: float, k_in: int, k_out: int, zones: ZoneMap, parcels: Array) -> float:
	if k_in != 0 and k_out != 0 and k_in != k_out:
		return (a_in + a_out) * 0.5  # zone changes: split the difference
	var inside := k_in != 0
	var lo := a_in if inside else a_out
	var hi := a_out if inside else a_in
	for _n in 7:
		var mid := (lo + hi) * 0.5
		var r := _ray(s, mid)
		var ok: bool = r[3] >= 0.0 and not _in_parcel(r[1], parcels)
		if ok:
			lo = mid
		else:
			hi = mid
	return lo


static func _in_parcel(p: Vector2, parcels: Array) -> bool:
	for q in parcels:
		if (q[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, q[1]):
			return true
	return false


## Splits frontage a0..a1 into lots of real, varied widths.
func _cut_run(s: Dictionary, zone: int, a0: float, a1: float, start_corner: bool, end_corner: bool) -> Array:
	var size: Dictionary = SIZES[zone]
	var length := a1 - a0
	var rich := 0.5
	if wealth.is_valid():
		var mid := _ray(s, (a0 + a1) * 0.5)
		rich = clampf(wealth.call(_at(mid, ZONE_PROBE)), 0.0, 1.0)
	# From 0.85x widths in struggling areas to 1.3x in wealthy ones.
	var scale := lerpf(0.85, 1.0, rich * 2.0) if rich < 0.5 else lerpf(1.0, 1.3, rich * 2.0 - 1.0)
	var wmin: float = size.w[0] * scale
	var wmax: float = size.w[1] * scale
	if length < wmin * 0.75:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([s.seg, s.side, roundi(a0 * 10.0), roundi(a1 * 10.0), zone])
	var n := maxi(1, roundi(length / ((wmin + wmax) * 0.5)))
	var widths := []
	for _try in 5:
		widths.clear()
		var total := 0.0
		for k in n:
			var w := 1.0 + rng.randf_range(-0.22, 0.22)
			# Corner lots are platted wider for their second front yard.
			if (k == 0 and start_corner) or (k == n - 1 and end_corner):
				w *= 1.25
			widths.append(w)
			total += w
		var lo := INF
		var hi := 0.0
		for k in n:
			widths[k] = widths[k] * length / total
			lo = minf(lo, widths[k])
			hi = maxf(hi, widths[k])
		if lo < wmin * 0.8 and n > 1:
			n -= 1
		elif hi > wmax * 1.4:
			n += 1
		else:
			break
	# Lot lines along the street, then flag lots where the block is deep.
	var lines := [a0]
	for w in widths:
		lines.append(lines[-1] + w)
	lines[-1] = a1
	var flags := {}
	if size.flags:
		var k := 0 if not start_corner else 1
		while k + 1 < n - (1 if end_corner else 0):
			if _deep_enough(s, lines[k], lines[k + 2], size.cap) and widths[k] - POLE * 0.5 >= wmin * 0.8 \
					and widths[k + 1] - POLE * 0.5 >= wmin * 0.8:
				flags[k] = true
				k += 2
			else:
				k += 1
	var out := []
	for k in n:
		var b0: float = lines[k] + (POLE * 0.5 if flags.has(k - 1) else 0.0)
		var b1: float = lines[k + 1] - (POLE * 0.5 if flags.has(k) else 0.0)
		# Lots run back to the middle of the block; where no street closes
		# the block (open land), they stop at the usual depth.
		var capped: bool = flags.has(k) or flags.has(k - 1) or _median_depth(s, b0, b1) > size.cap + FLAG_MIN \
			or not _bounded(s, b0, b1)
		var lot := _front_lot(s, zone, b0, b1, size.cap if capped else size.cap + FLAG_MIN)
		if lot.is_empty():
			continue
		var by := []
		if k == 0 and start_corner:
			by.append(_ray(s, b0)[5])
		if k == n - 1 and end_corner:
			by.append(_ray(s, b1)[5])
		if by.any(func(x): return x >= 0):
			lot["corner_by"] = by
		if lot.area >= wmin * size.min_d * 0.5:
			out.append(lot)
		if flags.has(k):
			var rear := _flag_lot(s, zone, lines[k], lines[k + 1], lines[k + 2], size.cap)
			if not rear.is_empty():
				out.append(rear)
	return out


## Room for a flag lot behind: land enclosed by streets (flag lots are how
## deep blocks are filled; open country just isn't platted yet).
func _deep_enough(s: Dictionary, a0: float, a1: float, cap: float) -> bool:
	for r in _rays_between(s, a0, a1):
		if r[3] < cap + FLAG_MIN * 0.85 or r[4] < 0.0:
			return false
	return true


func _bounded(s: Dictionary, a0: float, a1: float) -> bool:
	for r in _rays_between(s, a0, a1):
		if r[4] < 0.0:
			return false
	return true


func _median_depth(s: Dictionary, a0: float, a1: float) -> float:
	var ds := []
	for r in _rays_between(s, a0, a1):
		ds.append(r[3])
	ds.sort()
	return ds[ds.size() / 2]


## Survey lines from a0 to a1: exact ones at both ends, cached ones between.
func _rays_between(s: Dictionary, a0: float, a1: float) -> Array:
	var out := [_ray(s, a0)]
	for r in _survey(s):
		if r[0] > a0 + 0.5 and r[0] < a1 - 0.5:
			out.append(r.duplicate())
	out.append(_ray(s, a1))
	_converge(out)
	return out


## A lot from the street back to the middle of the block (at most `cap`).
func _front_lot(s: Dictionary, zone: int, a0: float, a1: float, cap: float) -> Dictionary:
	var rays := _rays_between(s, a0, a1)
	var poly := PackedVector2Array()
	for r in rays:
		poly.append(r[1])
	var depths := []
	for k in range(rays.size() - 1, -1, -1):
		var r: Array = rays[k]
		var d := clampf(r[3], 0.0, cap)
		depths.append(d)
		poly.append((r[1] as Vector2) + (r[2] as Vector2) * d)
	poly = _clean(poly)
	if poly.size() < 3:
		return {}
	depths.sort()
	var mid := _ray(s, (a0 + a1) * 0.5)
	var probe := _zone_probe(s, rays, (a0 + a1) * 0.5)
	return _lot(s, "%d:%d:%d" % [s.seg, s.side, roundi(a0 * 10.0)], poly, mid, probe,
		a1 - a0, depths[depths.size() / 2], 0.0, zone)


## A flag lot behind two front lots, reached by a drive strip between them.
func _flag_lot(s: Dictionary, zone: int, a0: float, b: float, a1: float, cap: float) -> Dictionary:
	var pl := _ray(s, b - POLE * 0.5)
	var pr := _ray(s, b + POLE * 0.5)
	var rays := _rays_between(s, a0, a1)
	var right := []
	var left := []
	for r in rays:
		if r[0] > b:
			right.append(r)
		else:
			left.append(r)
	var poly := PackedVector2Array([pl[1], pr[1], _at(pr, cap)])
	for r in right:
		if r[0] > pr[0] + 0.5:
			poly.append(_at(r, cap))
	var depths := []
	for k in range(rays.size() - 1, -1, -1):
		var d := minf(rays[k][3], cap + REAR_CAP)
		depths.append(d - cap)
		poly.append(_at(rays[k], d))
	poly.append(_at(left[0], cap))
	for r in left:
		if r[0] > a0 + 0.5 and r[0] < pl[0] - 0.5:
			poly.append(_at(r, cap))
	poly.append(_at(pl, cap))
	poly = _clean(poly)
	if poly.size() < 3:
		return {}
	depths.sort()
	var mid := _ray(s, b)
	var probe: Vector2 = (mid[1] as Vector2) + (mid[2] as Vector2) * ZONE_PROBE
	var lot := _lot(s, "%d:%d:%dF" % [s.seg, s.side, roundi(b * 10.0)], poly, mid, probe,
		a1 - a0, depths[depths.size() / 2], cap, zone)
	lot.flag = true
	return lot


static func _at(r: Array, d: float) -> Vector2:
	return (r[1] as Vector2) + (r[2] as Vector2) * d


## The zone probe of the survey line nearest `a` (it read the run's zone).
static func _zone_probe(s: Dictionary, rays: Array, a: float) -> Vector2:
	var best: Array = rays[0]
	for r in rays:
		if absf(r[0] - a) < absf(best[0] - a) and r[3] >= ZONE_PROBE:
			best = r
	return (best[1] as Vector2) + (best[2] as Vector2) * ZONE_PROBE


## `pad` moves the building back from the street (flag lots).
static func _lot(s: Dictionary, key: String, poly: PackedVector2Array, mid: Array, probe: Vector2,
		width: float, depth: float, pad: float, zone: int) -> Dictionary:
	var at := _on_curve(s, mid[0])
	var dir: Vector3 = at[1]
	var n: Vector2 = mid[2]
	var front: Vector2 = (mid[1] as Vector2) + n * pad
	var lot := {
		"key": key, "seg": s.seg, "side": s.side, "plat_zone": zone, "pad": pad,
		"at_frac": mid[0] / maxf(s.len, 0.001),
		"front": _v3(front), "road": Vector3(at[0].x, 0.0, at[0].z),
		"zone_pt": _v3(probe), "dir": dir, "normal": Vector3(n.x, 0.0, n.y),
		"to_curb": s.to_curb + pad,
		"width": width, "depth": depth, "corner": false, "flag": false, "sig": s.sig,
	}
	_set_shape(lot, poly)
	return lot


## Sets a lot's outline, middle and area.
static func _set_shape(lot: Dictionary, poly: PackedVector2Array) -> void:
	if _area(poly) < 0.0:
		poly.reverse()
	lot.corners = poly
	lot.area = _area(poly)
	lot.pos = _v3(_centroid(poly))


# -------------------------------------------------------------- corner lots

## Joins the two wedges that meet at a block corner into one corner lot,
## fronting the busier street (or the shorter side), as plats do.
func _join_corners(all: Array, corners: Array) -> void:
	var gone := {}
	for i in corners.size():
		var x: Dictionary = corners[i]
		if gone.has(x.key):
			continue
		for j in range(i + 1, corners.size()):
			var y: Dictionary = corners[j]
			# Only the two halves of the same corner: each one's street
			# is the road that ends the other's frontage.
			if gone.has(y.key) or y.seg == x.seg or y.plat_zone != x.plat_zone \
					or not (x.corner_by as Array).has(y.seg) or not (y.corner_by as Array).has(x.seg):
				continue
			var pair_key: String = x.key + "+" + y.key
			var h := hash([x.corners, y.corners])
			if not _unions.has(pair_key) or _unions[pair_key][0] != h:
				_unions[pair_key] = [h, union(x.corners, y.corners)]
			var merged: PackedVector2Array = _unions[pair_key][1]
			if merged.is_empty():
				continue
			var keep := x
			var drop := y
			var rank_x: int = RoadStyle.TYPES[_seg_type(x)].lanes
			var rank_y: int = RoadStyle.TYPES[_seg_type(y)].lanes
			if rank_y > rank_x or (rank_y == rank_x and y.width < x.width):
				keep = y
				drop = x
			_set_shape(keep, merged)
			keep.corner = true
			keep.depth = maxf(keep.depth, drop.width)
			gone[drop.key] = true
			break
	if gone.is_empty():
		return
	for k in range(all.size() - 1, -1, -1):
		if gone.has(all[k].key):
			all.remove_at(k)


func _seg_type(lot: Dictionary) -> int:
	return _sides["%d:%d" % [lot.seg, lot.side]].type


## One outline covering both (empty if they don't touch).
static func union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var ga := Geometry2D.offset_polygon(a, 0.4, Geometry2D.JOIN_MITER)
	var gb := Geometry2D.offset_polygon(b, 0.4, Geometry2D.JOIN_MITER)
	if ga.is_empty() or gb.is_empty():
		return PackedVector2Array()
	var m := Geometry2D.merge_polygons(ga[0], gb[0])
	if m.size() != 1:
		return PackedVector2Array()
	return _clean(_largest(Geometry2D.offset_polygon(m[0], -0.4, Geometry2D.JOIN_MITER)))


# --------------------------------------------------------- parcels (agency)

## Real size limit for a lot of this zone on this road.
static func max_lot(zone: int, road_type: int) -> Array:
	match zone:
		1: return MAX_LOT.home
		2: return MAX_LOT.main_street if RoadStyle.TYPES[road_type].lanes <= 2 else MAX_LOT.highway_shop
		_: return MAX_LOT.industry


## A saved parcel checked against the roads as they are now. Returns the lot
## (moved back if its street was widened, re-linked if its street was split)
## or {} when a road now runs through it.
func revalidate(network: RoadNetwork, lot: Dictionary) -> Dictionary:
	var moved: bool = not network.segments.has(lot.seg) or _sig.get(lot.seg, "") != lot.sig
	var box := _box(lot.corners)
	var touched := moved
	for b in changed_boxes:
		touched = touched or box.grow(30.0).intersects(b)
	if not touched:
		return lot
	if not moved:
		# Its street is the same: only check no new road runs through it.
		var cut := _clip_roads(lot.corners, box)
		if cut.size() < 3 or _area(cut) < _area(lot.corners) * 0.75 and _area(cut) < _area(lot.corners) - 1.0:
			return {}
		if absf(_area(cut) - _area(lot.corners)) < 0.5:
			return lot
		var kept := lot.duplicate()
		_set_shape(kept, cut)
		return kept
	var near := network.find_segment_near(lot.road, 4.0, 1.0)
	if near.is_empty() or not _lot_road(network, near.seg):
		return {}
	var id: int = near.seg
	var type: int = network.segments[id].type
	var c := network.curve_of(id)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	var n := Vector2(-tan.z, tan.x).normalized()
	var side := 1 if n.dot(Vector2(lot.normal.x, lot.normal.z)) >= 0.0 else -1
	n *= side
	# Cut away any road right-of-way now inside the parcel.
	var before := _area(lot.corners)
	var poly := _clip_roads(lot.corners, box)
	if poly.size() < 3 or _area(poly) < before * 0.75 and _area(poly) < before - 1.0:
		return {}
	var out := lot.duplicate()
	_set_shape(out, poly)
	var road := Vector2(near.point.x, near.point.z)
	var pad: float = lot.get("pad", 0.0)
	# How far the lot's street edge is from the road's centre now.
	var edge := Vector2(lot.front.x, lot.front.z).distance_to(road) - pad
	var shift := maxf(0.0, RoadStyle.right_of_way_half(type) + 0.3 - edge)
	out.seg = id
	out.side = side
	out.sig = _sig.get(id, "")
	out.at_frac = near.t
	out.road = Vector3(road.x, 0.0, road.y)
	out.dir = Vector3(tan.x, 0.0, tan.z).normalized()
	out.normal = Vector3(n.x, 0.0, n.y)
	out.front = lot.front + out.normal * shift
	out.to_curb = edge + shift + pad - RoadStyle.half_width(type)
	return out


## The outline minus every road right-of-way near it.
func _clip_roads(poly: PackedVector2Array, box: Rect2) -> PackedVector2Array:
	var ids := _pieces.keys()
	ids.sort()
	for o in ids:
		if not (_seg_box[o] as Rect2).grow(30.0).intersects(box):
			continue
		for p in _pieces[o]:
			if not (p[3] as Rect2).grow(p[2] + 1.0).intersects(box):
				continue
			for q in Geometry2D.offset_polyline(PackedVector2Array([p[0], p[1]]), p[2] + 0.2):
				poly = _largest(Geometry2D.clip_polygons(poly, q))
				if poly.size() < 3:
					return PackedVector2Array()
	return poly


## True if lots a and b can become one: same zone, sharing at least 3 m of
## lot line, and the result inside the zone's real size limit.
static func can_merge(sim, a: String, b: String) -> bool:
	if a == b or not sim.lots.has(a) or not sim.lots.has(b):
		return false
	var la: Dictionary = sim.lots[a]
	var lb: Dictionary = sim.lots[b]
	var za: int = sim.zones.zone_at(la.zone_pt)
	if za == 0 or za != sim.zones.zone_at(lb.zone_pt):
		return false
	var shared := Geometry2D.intersect_polygons(
		Geometry2D.offset_polygon(la.corners, 0.4)[0], Geometry2D.offset_polygon(lb.corners, 0.4)[0])
	var len := 0.0
	for p in shared:
		len = maxf(len, _span(p))
	if len < 3.0:
		return false
	var cap := max_lot(za, _road_type(sim, la))
	var width: float = la.width + (lb.width if lb.seg == la.seg and lb.side == la.side else 0.0)
	return width <= cap[0] and la.area + lb.area <= cap[1]


## Joins lot b into lot a. a keeps its key (and its building); b is gone, so
## move or drop anything keyed by b. Returns a, or "" if they can't merge.
static func merge_lots(sim, a: String, b: String) -> String:
	if not can_merge(sim, a, b):
		return ""
	var la: Dictionary = sim.lots[a]
	var lb: Dictionary = sim.lots[b]
	var poly := union(la.corners, lb.corners)
	if poly.is_empty():
		return ""
	if lb.seg == la.seg and lb.side == la.side:
		var wa: float = la.width
		var wb: float = lb.width
		la.front = (la.front * wa + lb.front * wb) / (wa + wb)
		la.road = (la.road * wa + lb.road * wb) / (wa + wb)
		la.at_frac = (la.at_frac * wa + lb.at_frac * wb) / (wa + wb)
		la.width = wa + wb
	else:
		la.corner = true
	la.depth = maxf(la.depth, lb.depth)
	_set_shape(la, poly)
	sim.lots.erase(b)
	sim.buildings.erase(b)
	sim.lots_changed.emit()
	sim.buildings_changed.emit()
	return a


## Adds land to a lot, clipped to ground no other lot or road holds.
## Returns false if nothing was added.
static func enlarge_lot(sim, key: String, extra: PackedVector2Array) -> bool:
	if not sim.lots.has(key):
		return false
	var lot: Dictionary = sim.lots[key]
	var add := extra
	for other in sim.lots:
		if other == key:
			continue
		var c: PackedVector2Array = sim.lots[other].corners
		if not _box(c).intersects(_box(add)):
			continue
		add = _largest(Geometry2D.clip_polygons(add, c))
		if add.size() < 3:
			return false
	for id in sim.network.segments:
		var pts: PackedVector3Array = sim.network.sample_segment(id, 12)
		var line := PackedVector2Array()
		for p in pts:
			line.append(Vector2(p.x, p.z))
		for q in Geometry2D.offset_polyline(line, RoadStyle.right_of_way_half(sim.network.segments[id].type) + 0.3):
			add = _largest(Geometry2D.clip_polygons(add, q))
			if add.size() < 3:
				return false
	var poly := union(lot.corners, add)
	if poly.is_empty() or _area(poly) < lot.area + 1.0:
		return false
	var cap := max_lot(sim.zones.zone_at(lot.zone_pt), _road_type(sim, lot))
	if _area(poly) > cap[1]:
		return false
	_set_shape(lot, poly)
	lot.depth = maxf(lot.depth, (lot.pos - lot.front).dot(lot.normal) * 2.0)
	sim.lots_changed.emit()
	return true


## Splits a lot in two along its frontage. The original key keeps the half
## nearer its start; the other half gets key + "/1". Returns both keys, or []
## if the halves would be too narrow for the zone.
static func split_lot(sim, key: String) -> Array:
	if not sim.lots.has(key):
		return []
	var lot: Dictionary = sim.lots[key]
	var zone: int = sim.zones.zone_at(lot.zone_pt)
	if not SIZES.has(zone) or lot.width < SIZES[zone].w[0] * 1.6:
		return []
	# Cut along a line through the middle, square to the street.
	var dir := Vector2(lot.dir.x, lot.dir.z)
	var n := Vector2(lot.normal.x, lot.normal.z)
	var mid := Vector2(lot.front.x, lot.front.z)
	var big := 1000.0
	var half_a := PackedVector2Array([mid - n * big - dir * big, mid - n * big, mid + n * big, mid + n * big - dir * big])
	var half_b := PackedVector2Array([mid - n * big, mid - n * big + dir * big, mid + n * big + dir * big, mid + n * big])
	var pa := _largest(Geometry2D.intersect_polygons(lot.corners, half_a))
	var pb := _largest(Geometry2D.intersect_polygons(lot.corners, half_b))
	if pa.size() < 3 or pb.size() < 3:
		return []
	var w: float = lot.width * 0.5
	var b := lot.duplicate()
	b.key = key + "/1"
	b.front = lot.front + lot.dir * (w * 0.5)
	b.road = lot.road + lot.dir * (w * 0.5)
	b.zone_pt = lot.zone_pt + lot.dir * (w * 0.5)
	b.width = w
	b.corner = false
	_set_shape(b, pb)
	lot.front = lot.front - lot.dir * (w * 0.5)
	lot.road = lot.road - lot.dir * (w * 0.5)
	lot.zone_pt = lot.zone_pt - lot.dir * (w * 0.5)
	lot.width = w
	_set_shape(lot, pa)
	sim.lots[b.key] = b
	sim.lots_changed.emit()
	return [key, b.key]


## The lots on the same side of the same street between its two junctions,
## in order along the street.
static func block_face(sim, key: String) -> Array:
	if not sim.lots.has(key):
		return []
	var lot: Dictionary = sim.lots[key]
	var face := []
	for k in sim.lots:
		var o: Dictionary = sim.lots[k]
		if o.seg == lot.seg and o.side == lot.side:
			face.append([o.at_frac, k])
	face.sort()
	var out := []
	for f in face:
		out.append(f[1])
	return out


static func _road_type(sim, lot: Dictionary) -> int:
	return sim.network.segments[lot.seg].type if sim.network.segments.has(lot.seg) else 0


# ------------------------------------------------------------------- saving

## A lot as plain JSON values (for parcels in saves).
static func lot_to_save(lot: Dictionary) -> Dictionary:
	var out := {}
	for k in lot:
		var v = lot[k]
		if v is Vector3:
			out[k] = [v.x, v.y, v.z]
		elif v is PackedVector2Array:
			var flat := []
			for p in v:
				flat.append_array([p.x, p.y])
			out[k] = flat
		else:
			out[k] = v
	return out


static func lot_from_save(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if k == "corners":
			var poly := PackedVector2Array()
			for i in range(0, v.size() - 1, 2):
				poly.append(Vector2(float(v[i]), float(v[i + 1])))
			out[k] = poly
		elif v is Array and v.size() == 3:
			out[k] = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif k in ["seg", "side", "plat_zone"]:
			out[k] = int(v)
		else:
			out[k] = v
	return out


# ------------------------------------------------------------------ helpers

static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


static func _box(c: PackedVector2Array) -> Rect2:
	var r := Rect2(c[0], Vector2.ZERO)
	for p in c:
		r = r.expand(p)
	return r


static func _area(c: PackedVector2Array) -> float:
	var s := 0.0
	for i in c.size():
		var j := (i + 1) % c.size()
		s += c[i].x * c[j].y - c[j].x * c[i].y
	return s * 0.5


static func _centroid(c: PackedVector2Array) -> Vector2:
	var a := _area(c)
	if absf(a) < 0.001:
		var m := Vector2.ZERO
		for p in c:
			m += p
		return m / maxf(c.size(), 1)
	var cx := 0.0
	var cy := 0.0
	for i in c.size():
		var j := (i + 1) % c.size()
		var cr := c[i].x * c[j].y - c[j].x * c[i].y
		cx += (c[i].x + c[j].x) * cr
		cy += (c[i].y + c[j].y) * cr
	return Vector2(cx, cy) / (6.0 * a)


static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p in polys:
		if absf(_area(p)) > absf(_area(best)):
			best = p
	return best


static func _holes(polys: Array) -> bool:
	var big := _largest(polys)
	for p in polys:
		if p != big and Geometry2D.is_polygon_clockwise(p) != Geometry2D.is_polygon_clockwise(big):
			return true
	return false


## Drops points closer than 0.25 m to the one before.
static func _clean(c: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in c:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.25:
			out.append(p)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.25:
		out.remove_at(out.size() - 1)
	return out if out.size() >= 3 else PackedVector2Array()


## Longest distance across a polygon (how long a shared edge strip is).
static func _span(c: PackedVector2Array) -> float:
	var best := 0.0
	for i in c.size():
		for j in range(i + 1, c.size()):
			best = maxf(best, c[i].distance_to(c[j]))
	return best


## Point and direction at distance `at` along a polyline.
static func point_at(pts: PackedVector3Array, at: float) -> Array:
	var dist := 0.0
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		if dist + d >= at or i == pts.size() - 2:
			var f := clampf((at - dist) / maxf(d, 0.001), 0.0, 1.0)
			var dir := Vector3(pts[i + 1].x - pts[i].x, 0.0, pts[i + 1].z - pts[i].z).normalized()
			return [pts[i].lerp(pts[i + 1], f), dir]
		dist += d
	return [pts[0], Vector3.FORWARD]


# ------------------------------------------------------------- older saves

## The fixed 20 x 32 m lots of saves made before natural lots, so their
## buildings keep the lots they stand on.
static func legacy_plan(network: RoadNetwork) -> Array:
	const LDEPTH := 32.0
	const MARGIN := 12.0
	var lots := []
	var ids := network.segments.keys()
	ids.sort()
	for id in ids:
		var pts := network.sample_segment(id, 32)
		var type: int = network.segments[id].type
		if not RoadStyle.TYPES[type].lots or absf(pts[0].y) > 0.5 or absf(pts[pts.size() - 1].y) > 0.5:
			continue
		var length := RoadNetwork.polyline_length(pts)
		var usable := length - MARGIN * 2.0
		if usable < FRONTAGE * 0.5:
			continue
		var n := int(usable / FRONTAGE) + 1
		var start := MARGIN + (usable - (n - 1) * FRONTAGE) * 0.5
		for side in [-1, 1]:
			for i in n:
				var at := start + i * FRONTAGE
				var road := point_at(pts, at)
				var dir: Vector3 = road[1]
				var normal: Vector3 = Vector3(-dir.z, 0.0, dir.x) * side
				var off := RoadStyle.right_of_way_half(type) + 0.3
				var front: Vector3 = road[0] + normal * off
				var hw := dir * (FRONTAGE * 0.5)
				var corners := PackedVector2Array()
				for p in [front - hw, front + hw, front + hw + normal * LDEPTH, front - hw + normal * LDEPTH]:
					corners.append(Vector2(p.x, p.z))
				var lot := {
					"key": "%d:%d:%d" % [id, side, i], "seg": id, "side": side,
					"at_frac": at / maxf(length, 0.001), "front": front,
					"road": Vector3(road[0].x, 0.0, road[0].z),
					"zone_pt": front + normal * 8.0, "dir": dir, "normal": normal,
					"to_curb": off - RoadStyle.half_width(type),
					"width": FRONTAGE, "depth": LDEPTH, "corner": false, "flag": false, "sig": "",
				}
				_set_shape(lot, corners)
				lots.append(lot)
	return lots
