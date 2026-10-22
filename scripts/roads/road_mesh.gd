class_name RoadMesh
extends RefCounted
## Turns sampled centre lines into flat ribbon meshes.


## Adds a ribbon running alongside pts, from offset `from` to offset `to`
## (negative = left side, positive = right side).
static func add_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float) -> void:
	if pts.size() < 2:
		return
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in pts.size():
		var side := _side(pts, i)
		var p := Vector3(pts[i].x, pts[i].y + y, pts[i].z)
		lefts.append(p + side * from)
		rights.append(p + side * to)
	var dist := 0.0
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		_quad(st, lefts[i], rights[i], lefts[i + 1], rights[i + 1], dist, dist + d)
		dist += d


## A flat disc, used to fill road junctions.
static func add_disc(st: SurfaceTool, center: Vector3, radius: float, y: float, steps := 24) -> void:
	var c := Vector3(center.x, center.y + y, center.z)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		_tri(st, [c, Vector2.ZERO],
			[c + Vector3(cos(a0), 0.0, sin(a0)) * radius, Vector2.ZERO],
			[c + Vector3(cos(a1), 0.0, sin(a1)) * radius, Vector2.ZERO])


## A complete road of the given type (asphalt, median, markings, curbs and
## sidewalks) as one mesh. `mats` maps a name to a material: asphalt, curb,
## walk, median, yellow, white.
## `gaps` leaves a one-way road's barrier out where a ramp opens off it:
## {side (+1/-1): [from, to] metres along pts}.
static func street(pts: PackedVector3Array, type: int, mats: Dictionary, gaps := {}) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw := RoadStyle.half_width(type)
	var cw := RoadStyle.CURB_WIDTH
	var w0 := hw + cw + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var hm: float = spec.median * 0.5
	var lane := 3.6
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	if spec.oneway:
		return _oneway(pts, spec, mats, gaps)
	var layers := [
		["asphalt", [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
		["curb", [[-hw - cw, -hw], [hw, hw + cw]], RoadStyle.Y_CURB, ""],
		["walk", [[-w1, -w0], [w0, w1]], RoadStyle.Y_SIDEWALK, ""],
	]
	if hm > 0.0:
		layers.append(["curb", [[-hm - cw, -hm], [hm, hm + cw]], y_mark + 0.02, "median"])
		layers.append(["median", [[-hm, hm]], y_mark + 0.03, "median"])
	elif spec.lanes > 2:
		# Double yellow centre line.
		layers.append(["yellow", [[-0.25, -0.12], [0.12, 0.25]], y_mark, ""])
	# Dashed white lines between lanes going the same way.
	var dashes := []
	for k in range(1, spec.lanes / 2):
		var off := hm + (cw if hm > 0.0 else 0.0) + lane * k
		dashes.append([off - 0.06, off + 0.06])
		dashes.append([-off - 0.06, -off + 0.06])
	if not dashes.is_empty():
		layers.append(["white", dashes, y_mark, "dashed"])
	return _build_layers(pts, layers, trimmed(pts, hw + 2.0), mats)


## Highways and ramps: shoulders, a yellow line on the left edge, a white
## line on the right, dashed lanes, and a concrete barrier each side.
static func _oneway(pts: PackedVector3Array, spec: Dictionary, mats: Dictionary, gaps := {}) -> ArrayMesh:
	var hw: float = spec.width * 0.5
	var left := -hw + 1.2
	var right: float = left + 3.6 * spec.lanes
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var dashes := []
	for k in range(1, spec.lanes):
		var off := left + 3.6 * k
		dashes.append([off - 0.075, off + 0.075])
	var layers := [
		["asphalt", [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
		["yellow", [[left - 0.15, left]], y_mark, ""],
		["white", [[right, right + 0.15]], y_mark, ""],
	]
	if not dashes.is_empty():
		layers.append(["white", dashes, y_mark, "dashed"])
	var mesh := _build_layers(pts, layers, pts, mats)
	# Concrete barrier each side, broken where a ramp opens off the road.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := RoadNetwork.polyline_length(pts)
	for side in [-1.0, 1.0]:
		var span: Array = gaps.get(side, [length + 1.0, length + 1.0])
		var span_from: float = maxf(span[0], 0.0)
		var span_to: float = minf(span[1], length)
		var from := hw if side > 0.0 else -hw - 0.6
		for piece in [[0.0, span_from], [span_to, length]]:
			if piece[1] - piece[0] > 0.5:
				add_strip(st, _between(pts, piece[0], piece[1]), from, from + 0.6, RoadStyle.Y_ASPHALT + 0.5)
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mats.curb)
	return mesh


## The part of a polyline from `from` to `to` metres along it.
static func _between(pts: PackedVector3Array, from: float, to: float) -> PackedVector3Array:
	if from <= 0.0 and to >= RoadNetwork.polyline_length(pts):
		return pts
	var out := PackedVector3Array()
	var n := maxi(2, int((to - from) / 3.0))
	for k in n + 1:
		out.append(LotPlanner.point_at(pts, lerpf(from, to, float(k) / n))[0])
	return out


static func _build_layers(pts: PackedVector3Array, layers: Array, inner: PackedVector3Array,
		mats: Dictionary) -> ArrayMesh:
	# Medians stop short of the junctions so turning cars can cross.
	var mesh := ArrayMesh.new()
	for layer in layers:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for span in layer[1]:
			match layer[3]:
				"dashed": add_dashed_strip(st, pts, span[0], span[1], layer[2])
				"median": add_strip(st, inner, span[0], span[1], layer[2])
				_: add_strip(st, pts, span[0], span[1], layer[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[layer[0]])
	return mesh


## Bridge parts under any part of the road raised above the ground: deck
## sides and underside, and a pier every 30 m. `ground` gives the height of
## the land at a point (flat ground at 0 when not given).
static func bridge(pts: PackedVector3Array, half: float, st: SurfaceTool, ground := Callable()) -> bool:
	var any := false
	var deck := 1.5
	var since := 15.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var ga := 0.0 if not ground.is_valid() else float(ground.call(a.x, a.z))
		var gb := 0.0 if not ground.is_valid() else float(ground.call(b.x, b.z))
		if minf(a.y - ga, b.y - gb) < 1.5:
			since = 15.0
			continue
		any = true
		var side_a := _side(pts, i) * half
		var side_b := _side(pts, i + 1) * half
		var down := Vector3(0, -deck, 0)
		for sgn in [-1.0, 1.0]:
			var ta: Vector3 = a + side_a * sgn
			var tb: Vector3 = b + side_b * sgn
			_wall(st, ta, tb, ta + down, tb + down)
		_wall(st, a - side_a + down, b - side_b + down, a + side_a + down, b + side_b + down)
		since += seg
		if since >= 30.0:
			since = 0.0
			var mid := a.lerp(b, 0.5)
			# Piers stand on the river bed (or the land), a little below it.
			var foot := minf(ga, gb) - 1.0 if ground.is_valid() else 0.0
			var top := mid.y - deck
			add_box(st, Vector3(mid.x, (top + foot) * 0.5, mid.z), Vector3(1.4, top - foot, half * 1.2),
				atan2(b.x - a.x, b.z - a.z))
	return any


## A box standing on its centre, turned `yaw` radians about the vertical.
static func add_box(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var corners := []
	for k in 8:
		var v := Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		corners.append(c + basis * v)
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_wall(st, corners[f[0]], corners[f[1]], corners[f[3]], corners[f[2]])


## A four-sided panel a0-b0 over a1-b1 (any orientation, both faces drawn).
static func _wall(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3) -> void:
	for v in [a0, b0, a1, b0, b1, a1]:
		st.add_vertex(v)


## The polyline with `cut` metres taken off each end.
static func trimmed(pts: PackedVector3Array, cut: float) -> PackedVector3Array:
	var length := RoadNetwork.polyline_length(pts)
	var out := PackedVector3Array()
	if length <= cut * 2.0 + 1.0:
		return out
	var n := maxi(2, pts.size())
	for k in n:
		out.append(LotPlanner.point_at(pts, lerpf(cut, length - cut, float(k) / (n - 1)))[0])
	return out


## Like add_strip, but in 3 m dashes with 9 m gaps (the US standard).
static func add_dashed_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float) -> void:
	var length := RoadNetwork.polyline_length(pts)
	var at := 6.0
	while at + 3.0 < length - 6.0:
		var piece := PackedVector3Array()
		for k in 3:
			piece.append(LotPlanner.point_at(pts, at + k * 1.5)[0])
		add_strip(st, piece, from, to, y)
		at += 12.0


static func _side(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-dir.z, 0.0, dir.x)


static func _quad(st: SurfaceTool, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, v0: float, v1: float) -> void:
	_tri(st, [l0, Vector2(0, v0)], [r0, Vector2(1, v0)], [l1, Vector2(0, v1)])
	_tri(st, [r0, Vector2(1, v0)], [r1, Vector2(1, v1)], [l1, Vector2(0, v1)])


## Adds an upward-facing triangle. Each corner is [position, uv].
## Godot treats clockwise (seen from above) as the front face.
static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var corners := [a, b, c] if (pb - pa).cross(pc - pa).y < 0.0 else [a, c, b]
	for v in corners:
		st.set_normal(Vector3.UP)
		st.set_uv(v[1] * 0.25)
		st.add_vertex(v[0])
