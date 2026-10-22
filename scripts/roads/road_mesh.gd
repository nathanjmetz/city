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
		var p := Vector3(pts[i].x, y, pts[i].z)
		lefts.append(p + side * from)
		rights.append(p + side * to)
	var dist := 0.0
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		_quad(st, lefts[i], rights[i], lefts[i + 1], rights[i + 1], dist, dist + d)
		dist += d


## A flat disc, used to fill road junctions.
static func add_disc(st: SurfaceTool, center: Vector3, radius: float, y: float, steps := 24) -> void:
	var c := Vector3(center.x, y, center.z)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		_tri(st, [c, Vector2.ZERO],
			[c + Vector3(cos(a0), 0.0, sin(a0)) * radius, Vector2.ZERO],
			[c + Vector3(cos(a1), 0.0, sin(a1)) * radius, Vector2.ZERO])


## A complete road of the given type (asphalt, median, markings, curbs and
## sidewalks) as one mesh. `mats` maps a name to a material: asphalt, curb,
## walk, median, yellow, white.
static func street(pts: PackedVector3Array, type: int, mats: Dictionary) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw := RoadStyle.half_width(type)
	var cw := RoadStyle.CURB_WIDTH
	var w0 := hw + cw + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var hm: float = spec.median * 0.5
	var lane := 3.6
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
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
	# Medians stop short of the junctions so turning cars can cross.
	var inner := trimmed(pts, hw + 2.0)
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
