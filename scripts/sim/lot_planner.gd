class_name LotPlanner
extends RefCounted
## Works out building lots along both sides of every road, like the zoning
## strips in Cities: Skylines. Lots come from the roads alone, so the same
## roads always give the same lots (needed for multiplayer later).

const FRONTAGE := 20.0
const DEPTH := 32.0
## Keep corners near junctions empty.
const END_MARGIN := 12.0
## Lots only check roads whose bounds come this close.
const NEAR := DEPTH + 30.0


## Returns an Array of lot Dictionaries:
## key, seg, side, pos (middle), front (middle of the street edge),
## zone_pt (where the lot reads its zone: near the street, where players paint),
## dir (along the street), normal (away from the street), corners (Vector2).
static func plan(network: RoadNetwork) -> Array:
	var lines := {}
	var bounds := {}
	var types := {}
	for id in network.segments:
		var pts := network.sample_segment(id, 32)
		lines[id] = pts
		types[id] = network.segments[id].type
		var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
		for p in pts:
			r = r.expand(Vector2(p.x, p.z))
		bounds[id] = r.grow(NEAR)
	var placed := []
	var lots := []
	var seg_ids := network.segments.keys()
	seg_ids.sort()
	for id in seg_ids:
		var pts: PackedVector3Array = lines[id]
		# Highways, ramps, bridges and tunnels have no driveways.
		if not RoadStyle.TYPES[types[id]].lots or absf(pts[0].y) > 0.5 or absf(pts[pts.size() - 1].y) > 0.5:
			continue
		var usable := RoadNetwork.polyline_length(pts) - END_MARGIN * 2.0
		if usable < FRONTAGE * 0.5:
			continue
		var n := int(usable / FRONTAGE) + 1
		var start := END_MARGIN + (usable - (n - 1) * FRONTAGE) * 0.5
		for side in [-1, 1]:
			for i in n:
				var lot := _make_lot(id, side, i, pts, start + i * FRONTAGE, types[id])
				if _clear_of_roads(lot, lines, bounds, types) and _clear_of_lots(lot, placed):
					placed.append(lot)
					lots.append(lot)
	return lots


static func _make_lot(seg: int, side: int, index: int, pts: PackedVector3Array, at: float, type: int) -> Dictionary:
	var road := point_at(pts, at)
	var dir: Vector3 = road[1]
	var normal := Vector3(-dir.z, 0.0, dir.x) * side
	var front_off := RoadStyle.right_of_way_half(type) + 0.3
	var front: Vector3 = road[0] + normal * front_off
	var pos := front + normal * (DEPTH * 0.5)
	var hw := dir * (FRONTAGE * 0.5)
	var back := normal * DEPTH
	var corners := PackedVector2Array()
	for p in [front - hw, front + hw, front + hw + back, front - hw + back]:
		corners.append(Vector2(p.x, p.z))
	return {
		"key": "%d:%d:%d" % [seg, side, index],
		"seg": seg, "side": side,
		# Where the driveway meets the road, as a share of the road's length.
		"at_frac": at / maxf(RoadNetwork.polyline_length(pts), 0.001),
		"pos": pos, "front": front, "zone_pt": front + normal * 8.0, "dir": dir, "normal": normal,
		"corners": corners,
		# From the lot's street edge back out to the asphalt, for driveways.
		"to_curb": front_off - RoadStyle.half_width(type),
	}


static func _clear_of_roads(lot: Dictionary, lines: Dictionary, bounds: Dictionary, types: Dictionary) -> bool:
	var c: PackedVector2Array = lot.corners
	var mid := Vector2(lot.pos.x, lot.pos.z)
	var probes := [c[0].lerp(c[1], 0.15), c[0].lerp(c[1], 0.85), c[2], c[3], mid,
		c[2].lerp(c[3], 0.5), c[1].lerp(c[2], 0.5), c[0].lerp(c[3], 0.5)]
	for id in lines:
		if not (bounds[id] as Rect2).has_point(mid):
			continue
		var pts: PackedVector3Array = lines[id]
		var min_d := RoadStyle.right_of_way_half(types[id])
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			for p in probes:
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < min_d:
					return false
	return true


static func _clear_of_lots(lot: Dictionary, placed: Array) -> bool:
	var mine := _shrunk(lot.corners)
	for other in placed:
		if (other.pos as Vector3).distance_to(lot.pos) > DEPTH * 1.3:
			continue
		if not Geometry2D.intersect_polygons(mine, _shrunk(other.corners)).is_empty():
			return false
	return true


static func _shrunk(c: PackedVector2Array) -> PackedVector2Array:
	var mid := (c[0] + c[1] + c[2] + c[3]) * 0.25
	var out := PackedVector2Array()
	for p in c:
		out.append(p + (mid - p).normalized() * 0.8)
	return out


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
