class_name RoadMesh
extends RefCounted
## Turns sampled centre lines into flat ribbon meshes.


## Adds a ribbon running alongside pts, from offset `from` to offset `to`
## (negative = left side, positive = right side).
static func add_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float) -> void:
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


## A complete street (asphalt, curbs and sidewalks on both sides) as one mesh.
static func street(pts: PackedVector3Array, asphalt: Material, curb: Material, walk: Material) -> ArrayMesh:
	var hw := RoadStyle.half_width()
	var cw := RoadStyle.CURB_WIDTH
	var w0 := hw + cw + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var mesh := ArrayMesh.new()
	var layers := [
		[asphalt, [[-hw, hw]], RoadStyle.Y_ASPHALT],
		[curb, [[-hw - cw, -hw], [hw, hw + cw]], RoadStyle.Y_CURB],
		[walk, [[-w1, -w0], [w0, w1]], RoadStyle.Y_SIDEWALK],
	]
	for layer in layers:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for span in layer[1]:
			add_strip(st, pts, span[0], span[1], layer[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, layer[0])
	return mesh


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
