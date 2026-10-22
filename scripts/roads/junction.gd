class_name Junction
extends RefCounted
## Real street corners (AASHTO Green Book, ADA/PROWAG): where town streets
## meet, each road stops at the junction, the pavement between them is one
## piece, and every corner between two roads is a rounded curb return. The
## curb, grass strip and sidewalk wrap around that curve, and a concrete
## curb ramp with a detectable-warning pad crosses the grass to the street
## where people cross. Sharp Y junctions get the same long, clean return
## instead of ragged overlapping strips.
##
## Only junctions of curbed two-way streets are shaped here; highways,
## ramps, roundabouts and country roads keep their own joins.

## Curb return radius by the larger road at the corner, in metres
## (Green Book: 15-25 ft on local streets, 25-40 ft where trucks turn).
const RETURN_RADIUS := {RoadStyle.Type.STREET: 6.0, RoadStyle.Type.AVENUE: 9.0, RoadStyle.Type.BOULEVARD: 12.0}
## Corners wider than this (radians) are a road bending, not a corner.
const STRAIGHT := deg_to_rad(160.0)
## A return never takes more than this share of a road's length.
const MAX_SHARE := 0.45
## Curb ramp width along the street, and how far it sits past the junction
## (ADA: 4 ft minimum ramp; 2 ft deep detectable warnings at the curb).
const RAMP_WIDTH := 2.4
const RAMP_GAP := 0.3
const DOMES_DEPTH := 0.6
const DOMES_COLOR := Color(0.55, 0.22, 0.16)


## Every shaped junction: node id -> {"trim": {seg id: metres}, "arms",
## "corners"}. Roads stop `trim` metres short of the node; the junction
## draws the rest. Nodes not in here keep the plain disc.
static func plan(net: RoadNetwork, rural: Dictionary = {}) -> Dictionary:
	var out := {}
	var ids := net.nodes.keys()
	ids.sort()
	for node in ids:
		var j := _plan_node(net, node, rural)
		if not j.is_empty():
			out[node] = j
	return out


## How far a road stops short of a node (0 when the node isn't shaped).
static func trim(plans: Dictionary, node: int, seg: int) -> float:
	return plans.get(node, {}).get("trim", {}).get(seg, 0.0)


static func _plan_node(net: RoadNetwork, node: int, rural: Dictionary) -> Dictionary:
	var segs := net.segments_at(node)
	var center: Vector3 = net.nodes[node]
	if segs.size() < 2 or center.y < -1.0:
		return {}
	var arms := []
	for id in segs:
		var sg: Dictionary = net.segments[id]
		var type: int = sg.type
		if RoadStyle.TYPES[type].oneway or RoadStyle.is_ring(type) or rural.has(id) or sg.a == sg.b:
			return {}
		var pts := net.sample_segment(id)
		if pts[pts.size() / 2].y < -1.0:
			return {}
		if sg.b == node:
			pts.reverse()
		var length := RoadNetwork.polyline_length(pts)
		var ahead: Vector3 = LotPlanner.point_at(pts, minf(3.0, length * 0.5))[0]
		var u := Vector2(ahead.x - center.x, ahead.z - center.z).normalized()
		arms.append({"seg": id, "u": u, "n": Vector2(-u.y, u.x), "hw": RoadStyle.half_width(type),
			"type": type, "pts": pts, "length": length, "d": 0.0})
	arms.sort_custom(func(a, b): return a.u.angle() < b.u.angle())
	# Each corner: arm i and the next arm round (counter-clockwise).
	var corners := []
	for i in arms.size():
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % arms.size()]
		var theta := fposmod(b.u.angle() - a.u.angle(), TAU)
		var c := {"a": i, "b": (i + 1) % arms.size(), "theta": theta, "fillet": false}
		if theta < STRAIGHT and theta > 0.01:
			_fillet(c, a, b, theta)
		corners.append(c)
	for c in corners:
		if c.fillet:
			arms[c.a].d = maxf(arms[c.a].d, c.ta)
			arms[c.b].d = maxf(arms[c.b].d, c.tb)
	if not corners.any(func(c): return c.fillet):
		return {}  # a road bending at a node: the plain disc joins it
	var trims := {}
	for arm in arms:
		trims[arm.seg] = arm.d
	var j := {"center": center, "arms": arms, "corners": corners, "trim": trims}
	j.poly = _outline(j)
	j.tris = Geometry2D.triangulate_polygon(j.poly)
	if j.tris.is_empty():
		return {}  # roads crowding each other: the plain disc covers it
	return j


## The junction's pavement, about the node: round each road's end, then the
## corner to the next road.
static func _outline(j: Dictionary) -> PackedVector2Array:
	var arms: Array = j.arms
	var poly := PackedVector2Array()
	for c in j.corners:
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		poly.append(a.u * a.d - a.n * a.hw)
		poly.append(a.u * a.d + a.n * a.hw)
		if c.fillet:
			poly.append_array(_arc(c, a, b, c.r))
		elif c.theta > PI:
			# The outside of a bend: round it off about the node.
			var a0: float = (a.n as Vector2).angle()
			var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
			for k in 9:
				poly.append(Vector2.from_angle(a0 + sweep * k / 8.0) * lerpf(a.hw, b.hw, k / 8.0))
	return poly


## A curb return between arm a's left edge and arm b's right edge: the
## circle of radius R touching both curb lines, shrunk if the roads are too
## short to fit it.
static func _fillet(c: Dictionary, a: Dictionary, b: Dictionary, theta: float) -> void:
	var r: float = RETURN_RADIUS.get(maxi(a.type, b.type), 6.0)
	while true:
		# The centre sits hw + r off both centre lines, inside the corner.
		var p1: Vector2 = a.n * (a.hw + r)
		var p2: Vector2 = -b.n * (b.hw + r)
		var hit = Geometry2D.line_intersects_line(p1, a.u, p2, b.u)
		if hit == null:
			return
		var ctr: Vector2 = hit
		var ta: float = ctr.dot(a.u)
		var tb: float = ctr.dot(b.u)
		if (ta <= a.length * MAX_SHARE and tb <= b.length * MAX_SHARE) or r <= 0.5:
			if ta < 0.0 or tb < 0.0:
				return
			c.fillet = true
			c.r = r
			c.ctr = ctr
			c.ta = minf(ta, a.length * MAX_SHARE)
			c.tb = minf(tb, b.length * MAX_SHARE)
			return
		r *= 0.6


## Points around a corner's curb return at radius `rad` from its centre,
## from arm a's side to arm b's (relative to the node).
static func _arc(c: Dictionary, a: Dictionary, b: Dictionary, rad: float, steps := 10) -> PackedVector2Array:
	var a0: float = (-a.n as Vector2).angle()
	var a1: float = (b.n as Vector2).angle()
	var sweep := wrapf(a1 - a0, -PI, PI)
	var out := PackedVector2Array()
	for k in steps + 1:
		out.append(c.ctr + Vector2.from_angle(a0 + sweep * k / steps) * rad)
	return out


## Draws every shaped junction: pavement into `asphalt`, curbs into `curb`,
## sidewalks and curb ramps into `walk`, warning pads into `domes`.
static func draw(plans: Dictionary, asphalt: SurfaceTool, curb: SurfaceTool, walk: SurfaceTool,
		domes: SurfaceTool) -> void:
	for node in plans:
		_draw_node(plans[node], asphalt, curb, walk, domes)


static func _draw_node(j: Dictionary, asphalt: SurfaceTool, curb: SurfaceTool, walk: SurfaceTool,
		domes: SurfaceTool) -> void:
	var arms: Array = j.arms
	var center: Vector3 = j.center
	var poly: PackedVector2Array = j.poly
	var tris: PackedInt32Array = j.tris
	var cw := RoadStyle.CURB_WIDTH
	var back := cw + RoadStyle.PARKWAY_WIDTH  # curb face to sidewalk
	var walk_w := RoadStyle.SIDEWALK_WIDTH
	for k in range(0, tris.size(), 3):
		_tri(asphalt, center, [poly[tris[k]], poly[tris[k + 1]], poly[tris[k + 2]]], RoadStyle.Y_ASPHALT)
	for c in j.corners:
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		if c.fillet:
			# Curb and sidewalk wrap the return, then run straight on to where each road starts.
			_ring(curb, center, c, a, b, c.r - cw, c.r, RoadStyle.Y_CURB)
			_ring(walk, center, c, a, b, c.r - back - walk_w, c.r - back, RoadStyle.Y_SIDEWALK)
			_side(curb, walk, center, a, 1.0, c.ta, a.d)
			_side(curb, walk, center, b, -1.0, c.tb, b.d)
			_ramp(walk, domes, center, a, 1.0)
			_ramp(walk, domes, center, b, -1.0)
		else:
			_side(curb, walk, center, a, 1.0, 0.0, a.d)
			_side(curb, walk, center, b, -1.0, 0.0, b.d)
			if c.theta > PI:
				_bend(curb, center, a, b, a.hw, a.hw + cw, RoadStyle.Y_CURB)
				_bend(walk, center, a, b, a.hw + back, a.hw + back + walk_w, RoadStyle.Y_SIDEWALK)


## A band of the curb return between two radii from its centre.
static func _ring(st: SurfaceTool, center: Vector3, c: Dictionary, a: Dictionary, b: Dictionary,
		r0: float, r1: float, y: float) -> void:
	var inner := _arc(c, a, b, maxf(r0, 0.0))
	var outer := _arc(c, a, b, maxf(r1, 0.0))
	for k in inner.size() - 1:
		_tri(st, center, [inner[k], outer[k], outer[k + 1]], y)
		_tri(st, center, [inner[k], outer[k + 1], inner[k + 1]], y)


## The outside of a bend: a band about the node from arm a's left to b's right.
static func _bend(st: SurfaceTool, center: Vector3, a: Dictionary, b: Dictionary, r0: float, r1: float, y: float) -> void:
	var a0: float = (a.n as Vector2).angle()
	var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
	for k in 8:
		var d0 := Vector2.from_angle(a0 + sweep * k / 8.0)
		var d1 := Vector2.from_angle(a0 + sweep * (k + 1) / 8.0)
		_tri(st, center, [d0 * r0, d0 * r1, d1 * r1], y)
		_tri(st, center, [d0 * r0, d1 * r1, d1 * r0], y)


## Straight curb and sidewalk along one side of an arm, from `from` to `to`
## metres out from the node (side +1 = toward the next arm round).
static func _side(curb: SurfaceTool, walk: SurfaceTool, center: Vector3, arm: Dictionary, side: float,
		from: float, to: float) -> void:
	if to - from < 0.05:
		return
	var hw: float = arm.hw
	var back := hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	_band(curb, center, arm, side, hw, hw + RoadStyle.CURB_WIDTH, from, to, RoadStyle.Y_CURB)
	_band(walk, center, arm, side, back, back + RoadStyle.SIDEWALK_WIDTH, from, to, RoadStyle.Y_SIDEWALK)


## A curb ramp where people cross the arm: concrete across the grass strip
## from the sidewalk to the curb, with the warning pad at the street edge.
static func _ramp(walk: SurfaceTool, domes: SurfaceTool, center: Vector3, arm: Dictionary, side: float) -> void:
	var hw: float = arm.hw
	var from: float = arm.d + RAMP_GAP
	var to := from + RAMP_WIDTH
	if to > arm.length * 0.5:
		return
	var cw := RoadStyle.CURB_WIDTH
	_band(walk, center, arm, side, hw, hw + cw + RoadStyle.PARKWAY_WIDTH, from, to, RoadStyle.Y_SIDEWALK + 0.035)
	_band(domes, center, arm, side, hw, hw + DOMES_DEPTH, from, to, RoadStyle.Y_CURB + 0.01)


## A band beside an arm, offsets `o0`..`o1` from its centre line on `side`,
## `from`..`to` metres out. Follows the arm's own (maybe curved) line.
static func _band(st: SurfaceTool, center: Vector3, arm: Dictionary, side: float, o0: float, o1: float,
		from: float, to: float, y: float) -> void:
	var n := maxi(1, ceili((to - from) / 3.0))
	var prev := []
	for k in n + 1:
		var at := lerpf(from, to, float(k) / n)
		var p: Array = LotPlanner.point_at(arm.pts, at)
		var q := Vector2(p[0].x - center.x, p[0].z - center.z)
		var dir := Vector2(p[1].x, p[1].z)
		var nrm := Vector2(-dir.y, dir.x) * side
		var pair := [q + nrm * o0, q + nrm * o1]
		if not prev.is_empty():
			_tri(st, center, [prev[0], prev[1], pair[1]], y)
			_tri(st, center, [prev[0], pair[1], pair[0]], y)
		prev = pair


## One flat triangle, from points about the node.
static func _tri(st: SurfaceTool, center: Vector3, p: Array, y: float) -> void:
	var o := Vector3(center.x, center.y + y, center.z)
	RoadMesh._tri(st, [o + Vector3(p[0].x, 0.0, p[0].y), Vector2(p[0].x, p[0].y)],
		[o + Vector3(p[1].x, 0.0, p[1].y), Vector2(p[1].x, p[1].y)],
		[o + Vector3(p[2].x, 0.0, p[2].y), Vector2(p[2].x, p[2].y)])
