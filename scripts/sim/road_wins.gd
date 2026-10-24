class_name RoadWins
extends RefCounted
## "The road wins" (Brawn): any road can go through anything, and the world
## adapts the way a real county does. Fields are trimmed back to the road's
## edge and scraps too small to farm go back to grass; a farmhouse, company
## yard or service building in the way is bulldozed and paid back; a lane
## the road cut is rerouted to the nearest road; a pad that's hit closes and
## the company reopens it on other good ground. Lots are the lots thread's.
##
## Everything here follows from the road network alone, so every copy of the
## city (multiplayer) and every reload comes out the same.

## Extra clear ground fields leave beside the right of way (ditch and fence line).
const VERGE := 1.0
## Buildings may stand flush with the right of way (placing allows half a
## metre over it), so only a road that takes more than this clears them.
const BUILDING_SLACK := -1.0
## A trimmed field keeps going while this much of it is left: farmers
## plant right up to the ditch, so the field's edge runs along the road
## instead of leaving a 40 m notch where a road clipped a corner.
const MIN_FIELD_SHARE := 0.15
## Pieces smaller than this (square metres) are slivers and go back to grass.
const MIN_PIECE := 150.0

## Road outlines already worked out: "id|extra" -> [the road's shape, outline].
static var _kept := {}


## The ground every road takes: one outline per segment, round at the ends
## so junctions are covered, widened by `extra` metres each side. Each
## entry: {bounds: Rect2, polys: Array}.
static func corridors(net: RoadNetwork, extra: float) -> Array:
	var out := []
	var ids := net.segments.keys()
	ids.sort()
	for id in ids:
		# Each road's outline is kept until the road changes: a big town
		# has thousands, and only the edited ones need working out again.
		var c := net.curve_of(id)
		var sig := "%s|%s|%s|%d|%s" % [c[0], c[1], c[2], net.segments[id].type, extra]
		var key := "%d|%s" % [id, extra]
		var kept: Array = _kept.get(key, [])
		if not kept.is_empty() and kept[0] == sig:
			out.append(kept[1])
			continue
		var half := RoadStyle.right_of_way_half(net.segments[id].type) + extra
		var line := PackedVector2Array()
		for p in net.sample_segment(id):
			line.append(Vector2(p.x, p.z))
		var polys := Geometry2D.offset_polyline(line, half, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		var box := Rect2(line[0], Vector2.ZERO)
		for p in line:
			box = box.expand(p)
		var corr := {"bounds": box.grow(half), "polys": polys}
		_kept[key] = [sig, corr]
		out.append(corr)
	return out


## The ground painted roads take (county roads and state highways the town
## hasn't built, CitySim.painted_near lines), as corridors does for built
## ones: a field stops at their right of way too (Brawn, 2026-10-24).
static func painted(lines: Array, extra: float) -> Array:
	var out := []
	for l in lines:
		var half := RoadStyle.right_of_way_half(l.type) + extra
		var line: PackedVector2Array = l.pts
		var box := Rect2(line[0], Vector2.ZERO)
		for p in line:
			box = box.expand(p)
		out.append({"bounds": box.grow(half),
			"polys": Geometry2D.offset_polyline(line, half, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)})
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	return box


## True when any road takes some of this ground.
static func hits(corr: Array, poly: PackedVector2Array) -> bool:
	var box := _bounds(poly)
	for c in corr:
		if not c.bounds.intersects(box):
			continue
		for r in c.polys:
			if not Geometry2D.intersect_polygons(poly, r).is_empty():
				return true
	return false


## True when a line (a lane) runs through a road anywhere but its last
## `skip` metres, where it meets its own road.
static func cuts(corr: Array, line: Array, skip: float) -> bool:
	if line.size() < 2:
		return false
	var end: Vector3 = line[-1]
	for p in line:
		if (p as Vector3).distance_to(end) < skip:
			continue
		var q := Vector2(p.x, p.z)
		for c in corr:
			if not c.bounds.has_point(q):
				continue
			for r in c.polys:
				if Geometry2D.is_point_in_polygon(q, r):
					return true
	return false


## What's left of a piece of ground once the roads take theirs: outer
## outlines only, slivers dropped.
static func clip(corr: Array, poly: PackedVector2Array) -> Array:
	var pieces := [poly]
	var box := _bounds(poly)
	for c in corr:
		if not c.bounds.intersects(box):
			continue
		for r in c.polys:
			var next := []
			for piece in pieces:
				for part in Geometry2D.clip_polygons(piece, r):
					# A road wholly inside a field would leave a hole; keep it simple and drop holes.
					if not Geometry2D.is_polygon_clockwise(part) == Geometry2D.is_polygon_clockwise(poly):
						continue
					next.append(part)
			pieces = next
	return pieces.filter(func(p): return area(p) >= MIN_PIECE)


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5
