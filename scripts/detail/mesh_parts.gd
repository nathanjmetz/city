class_name MeshParts
extends RefCounted
## A drawing as plain arrays instead of a mesh on the graphics chip: a list
## of parts, each [material (a HouseMaterials name or a Material), surface
## arrays]. The art builders hand their drawings over this way when
## HouseBuilder.keep_arrays is set, so BuildingView can merge a whole square
## of buildings into one batch without sending each building to the chip
## first, or reading it back off the chip (surface_get_arrays waits for the
## graphics chip to finish everything it was doing).


## The parts of a builder's mesh: its "parts" meta when it was built with
## keep_arrays, else read off the mesh (slow; tests and tools only).
static func of(mesh: Mesh) -> Array:
	if mesh == null:
		return []
	if mesh.has_meta("parts"):
		return mesh.get_meta("parts")
	var out := []
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		out.append([mesh.surface_get_material(i), mesh.surface_get_arrays(i)])
	return out


static func material(part: Array) -> Material:
	return HouseMaterials.get_mat(part[0]) if part[0] is String else part[0]


## The material's HouseMaterials name, or "" for one of its own.
static func kind(part: Array) -> String:
	if part[0] is String:
		return part[0]
	return HouseMaterials.name_of(part[0])


static func vertex_count(parts: Array) -> int:
	var n := 0
	for p in parts:
		var v = p[1][Mesh.ARRAY_VERTEX] if p[1].size() > Mesh.ARRAY_VERTEX else null
		if v != null:
			n += (v as PackedVector3Array).size()
	return n


## The box round every part.
static func aabb(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for p in parts:
		var a: Array = p[1]
		if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null:
			continue
		for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box


## A real mesh of the parts (a building going up needs one of its own).
static func to_mesh(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for p in parts:
		var a: Array = p[1]
		if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(p))
	return mesh


## The lot's flat work laid on the land, as Terrain.drape_local does it for
## a mesh: `xform` places the parts' frame (a node standing on the land);
## each vertex keeps its height above the ground as drawn, and long
## triangles are split first so a big yard follows the slope.
static func drape(parts: Array, xform: Transform3D, max_edge := 4.0) -> Array:
	var inv := xform.affine_inverse()
	var seen := {}
	var out := []
	for p in parts:
		var arrays: Array = p[1]
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		if max_edge > 0.0:
			arrays = Terrain._split(arrays, max_edge)
		else:
			arrays = arrays.duplicate()
		var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		for i in verts.size():
			var w := xform * verts[i]
			var at := Vector2(w.x, w.z)
			var g = seen.get(at)
			if g == null:
				g = Terrain.ground_y(w.x, w.z)
				seen[at] = g
			w.y = g + verts[i].y
			verts[i] = inv * w
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.append([p[0], arrays])
	return out


## Which arrays a surface carries, so only alike surfaces are merged.
static func format_of(a: Array) -> int:
	var f := 0
	for i in Mesh.ARRAY_MAX:
		if i < a.size() and a[i] != null:
			f |= 1 << i
	return f


## The parts moved by `xf` (positions and normals; nothing here is scaled).
static func moved(a: Array, xf: Transform3D) -> Array:
	var out := a.duplicate()
	out[Mesh.ARRAY_VERTEX] = xf * (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	if a[Mesh.ARRAY_NORMAL] != null:
		out[Mesh.ARRAY_NORMAL] = Transform3D(xf.basis, Vector3.ZERO) * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)
	return out


## Appends surface arrays `b` to `a` (same format), offsetting `b`'s index.
static func append(a: Array, b: Array) -> void:
	var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for i in Mesh.ARRAY_MAX:
		if i == Mesh.ARRAY_INDEX or a[i] == null or b[i] == null:
			continue
		a[i].append_array(b[i])
	if a[Mesh.ARRAY_INDEX] != null and b[Mesh.ARRAY_INDEX] != null:
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var add: PackedInt32Array = b[Mesh.ARRAY_INDEX]
		var at := idx.size()
		idx.resize(at + add.size())
		for k in add.size():
			idx[at + k] = add[k] + n
		a[Mesh.ARRAY_INDEX] = idx


## A fresh copy of surface arrays to append others to.
static func copy(a: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for i in Mesh.ARRAY_MAX:
		if i < a.size() and a[i] != null:
			out[i] = a[i].duplicate()
	return out
