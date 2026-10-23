class_name Overpass
extends RefCounted
## A raised road drawn across roads or track at ground level climbs over them
## on its own (Brawn, 2026-10-23), the way Cities: Skylines 2 lifts a road
## you drag across another: the deck rises to real clearance over what it
## crosses, the approaches climb at no more than the road's grade, and the
## bridge drawing puts piers under it. A road at ground level still meets the
## roads it crosses in a junction (RoadNetwork.build_road).
##
## Real reference:
##   - Vertical clearance over a road: 16.5 ft (5.0 m) on highways and
##     streets (AASHTO Green Book; FHWA's interstate rule, 23 CFR 625).
##   - Over a railroad: 23 ft (7.0 m) above the top of rail (AREMA, and the
##     clearance most states require for new overpasses).
##   - The deck adds about 1.5 m between road surfaces (RoadNetwork.CLEARANCE).
##   - The deck runs level past the edge of what it crosses before the
##     approaches start down (a bridge's end span and abutment).
##   - Approaches climb at the road type's maximum grade (RoadStyle "grade",
##     AASHTO: 5% on a freeway, up to 12% on a local street).

## Surface to surface over a railroad: 23 ft over the rail plus the deck.
const RAIL_CLEARANCE := 7.0 + 1.5
## Level deck past the edge of what it crosses, each side (m).
const SHOULDER := 4.0
## Half the width of a track's bed.
const RAIL_HALF := 3.0
## Sampling step along the new road (m).
const STEP := 1.0
## Sampling step when looking for crossings (m).
const HIT_STEP := 4.0
## Height kept above the clearance, so the deck still clears it between
## samples (m).
const MARGIN := 0.15


## The pieces to build a road `c` ([p0, ctrl, p2], heights above ground) so it
## clears every road and track it crosses at ground level. Returns
## {ok, pieces: [[p0, ctrl, p2], ...], crossed: int, why}. With nothing to
## clear it hands back `c` as the one piece.
static func plan(sim, c: Array, type: int) -> Dictionary:
	var p0: Vector3 = c[0]
	var p1: Vector3 = c[1]
	var p2: Vector3 = c[2]
	var n := maxi(8, ceili(Vector2(p2.x - p0.x, p2.z - p0.z).length() * 1.3 / STEP))
	var pts := RoadNetwork.sample_curve(p0, p1, p2, n)
	var along := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		along.append(along[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
	var length := along[along.size() - 1]
	# Crossings found on a coarser line (cheap enough to run while the
	# player drags), placed exactly where the lines meet.
	var m := maxi(4, ceili(length / HIT_STEP))
	var coarse := RoadNetwork.sample_curve(p0, p1, p2, m)
	var c_along := PackedFloat32Array([0.0])
	for i in range(1, coarse.size()):
		c_along.append(c_along[i - 1] + Vector2(coarse[i].x - coarse[i - 1].x, coarse[i].z - coarse[i - 1].z).length())
	var hits := _crossings(sim, coarse, c_along)
	for h in hits:
		h.s *= length / maxf(c_along[c_along.size() - 1], 0.001)
	if hits.is_empty():
		return {"ok": true, "pieces": [c], "crossed": 0, "why": ""}
	var grade := float(RoadStyle.TYPES[type].grade) * 0.98
	# The height the road must keep: its own line, or over each crossing the
	# clearance there, falling away at the grade past the level deck.
	var ys := PackedFloat32Array()
	for i in pts.size():
		var y := pts[i].y
		for h in hits:
			y = maxf(y, h.y + MARGIN - grade * maxf(0.0, absf(along[i] - h.s) - h.pad))
		ys.append(y)
	if ys[0] > p0.y + 0.05 or ys[ys.size() - 1] > p2.y + 0.05:
		var worst: Dictionary = hits[0]
		var run := float(worst.pad) + (float(worst.y) - minf(p0.y, p2.y)) / grade
		return {"ok": false, "pieces": [], "crossed": hits.size(), "why":
			"Too short to climb over: a %s needs about %d ft each side to clear it at %d%% grade." \
			% [RoadStyle.TYPES[type].name, roundi(run * 3.28084), roundi(grade / 0.98 * 100.0)]}
	# Pieces end where the climb changes: the foot of each approach and each
	# end of the level deck.
	var keep := _corners(along, ys)
	var pieces := []
	for k in range(1, keep.size()):
		var i0: int = keep[k - 1]
		var i1: int = keep[k]
		var t0 := float(i0) / n
		var t1 := float(i1) / n
		var a := RoadNetwork.bezier(p0, p1, p2, t0)
		var b := RoadNetwork.bezier(p0, p1, p2, t1)
		a.y = ys[i0]
		b.y = ys[i1]
		var mid := RoadNetwork.sub_control(p0, p1, p2, t0, t1)
		mid.y = (a.y + b.y) * 0.5
		if k == 1:
			a = p0
		if k == keep.size() - 1:
			b = p2
		pieces.append([a, mid, b])
	return {"ok": true, "pieces": pieces, "crossed": hits.size(), "why": ""}


## Where the road crosses roads and track at ground level, away from its own
## ends: [{s (m along), y (deck height it needs), pad (level deck each side)}].
static func _crossings(sim, pts: PackedVector3Array, along: PackedFloat32Array) -> Array:
	var out := []
	var length := along[along.size() - 1]
	var net: RoadNetwork = sim.network
	var box := RoadNetwork._bounds(pts).grow(2.0)
	for id in net.segments:
		if not box.intersects(RoadNetwork._bounds(PackedVector3Array(net.curve_of(id))), true):
			continue
		var old := net.sample_segment(id, 32)
		var half := RoadStyle.right_of_way_half(int(net.segments[id].type))
		for h in _hits(pts, along, old):
			if absf(h.y_old) < RoadNetwork.SAME_LEVEL:
				out.append({"s": h.s, "y": h.y_old + RoadNetwork.CLEARANCE, "pad": half + SHOULDER})
	if sim.get("rail") != null:
		for pid in sim.rail.pieces:
			var track := PackedVector3Array(sim.rail.pieces[pid].pts)
			if track.size() < 2 or not box.intersects(RoadNetwork._bounds(track), true):
				continue
			for h in _hits(pts, along, track):
				out.append({"s": h.s, "y": RAIL_CLEARANCE, "pad": RAIL_HALF + SHOULDER})
	for h in _county_hits(sim, pts, along):
		out.append(h)
	# A crossing at the road's own end is the junction it starts or ends on.
	out = out.filter(func(h): return h.s > RoadNetwork.MERGE_DIST and h.s < length - RoadNetwork.MERGE_DIST)
	# One crossing found twice (where the sampled lines meet at a point) is one.
	out.sort_custom(func(x, y): return x.s < y.s)
	var one := []
	for h in out:
		if not one.is_empty() and h.s - float(one[-1].s) < 1.0:
			one[-1].y = maxf(float(one[-1].y), float(h.y))
			one[-1].pad = maxf(float(one[-1].pad), float(h.pad))
			continue
		one.append(h)
	return one


static func _hits(pts: PackedVector3Array, along: PackedFloat32Array, old: PackedVector3Array) -> Array:
	var out := []
	var box := RoadNetwork._bounds(pts)
	for j in range(old.size() - 1):
		var oa := Vector2(old[j].x, old[j].z)
		var ob := Vector2(old[j + 1].x, old[j + 1].z)
		if not box.intersects(Rect2(oa, Vector2.ZERO).expand(ob), true):
			continue
		for i in range(pts.size() - 1):
			var na := Vector2(pts[i].x, pts[i].z)
			var nb := Vector2(pts[i + 1].x, pts[i + 1].z)
			var hit = Geometry2D.segment_intersects_segment(na, nb, oa, ob)
			if hit == null:
				continue
			var fj: float = oa.distance_to(hit) / maxf(oa.distance_to(ob), 0.001)
			out.append({"s": along[i] + na.distance_to(hit), "y_old": lerpf(old[j].y, old[j + 1].y, fj)})
	return out


## County section-line roads the town hasn't taken over (painted, not in the
## network yet) count as roads at ground level.
static func _county_hits(sim, pts: PackedVector3Array, along: PackedFloat32Array) -> Array:
	var out := []
	if sim.get("terrain_offset") == null:
		return out
	var o: Vector2 = sim.terrain_offset
	var half := RoadStyle.right_of_way_half(HubRoads.TYPE)
	for i in range(pts.size() - 1):
		var a := Vector2(pts[i].x + o.x, pts[i].z + o.y)
		var b := Vector2(pts[i + 1].x + o.x, pts[i + 1].z + o.y)
		for ns in [true, false]:
			var ca: float = a.x if ns else a.y
			var cb: float = b.x if ns else b.y
			var la := floori(ca / CountyGrid.SECTION)
			var lb := floori(cb / CountyGrid.SECTION)
			if la == lb:
				continue
			var line := float(maxi(la, lb)) * CountyGrid.SECTION
			var f := (line - ca) / (cb - ca)
			var q := a.lerp(b, f)
			var other: float = q.y if ns else q.x
			var seg := floori(other / CountyGrid.SECTION)
			var lid := maxi(la, lb)
			var key := "%s:%d:%d" % ["ns" if ns else "ew", lid, seg]
			if not CountyGrid.has_mile(lid if ns else lid + (1 << 20), seg) or sim.county_removed.has(key):
				continue
			out.append({"s": along[i] + a.distance_to(q), "y": RoadNetwork.CLEARANCE, "pad": half + SHOULDER})
	return out


## The samples where the height line bends, ends included.
static func _corners(along: PackedFloat32Array, ys: PackedFloat32Array) -> Array:
	var keep := [0]
	for i in range(1, ys.size() - 1):
		var g0 := (ys[i] - ys[i - 1]) / maxf(along[i] - along[i - 1], 0.001)
		var g1 := (ys[i + 1] - ys[i]) / maxf(along[i + 1] - along[i], 0.001)
		if absf(g1 - g0) > 0.002 and along[i] - along[keep[keep.size() - 1]] >= RoadNetwork.MIN_LENGTH:
			keep.append(i)
	var last := ys.size() - 1
	if keep.size() > 1 and along[last] - along[keep[keep.size() - 1]] < RoadNetwork.MIN_LENGTH:
		keep.pop_back()
	keep.append(last)
	return keep
