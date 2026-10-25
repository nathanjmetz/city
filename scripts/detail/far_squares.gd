class_name FarSquares
extends Node3D
## The far drawing of a town's buildings: every building's far version
## (BuildingView.far_version: its walls, roofs and windows as drawn, about a
## hundred triangles) merged into one mesh for each 256 m square, one shared
## look for the whole town, so the whole town far off is a few dozen draw
## calls. Each square is four of the view's 128 m squares; a quarter whose
## full drawing has faded in is hidden (FadeMats.far_square), so the far
## blocks and the full drawing never show at once.
##
## Each building's far version is kept as plain arrays (a few KB), so a
## square is merged again from them when a building changes, without
## rebuilding anything.

const SIZE := 256.0
## A square merged again waits this long after its last merge, so a block
## filling in is merged a few times, not once a house.
const REMERGE_MS := 1500

var _items := {}  # Vector2i -> {key: arrays (square-local, unindexed; UV2.x the quarter)}
var _where := {}  # key -> Vector2i
var _mi := {}  # Vector2i -> MeshInstance3D
var _mat := {}  # Vector2i -> ShaderMaterial
var _hide := {}  # Vector2i -> Vector4
var _dirty := {}  # Vector2i -> true
var _merged_at := {}  # Vector2i -> msec


static func square_of(sq128: Vector2i) -> Vector2i:
	return Vector2i(floori(sq128.x / 2.0), floori(sq128.y / 2.0))


static func quarter_of(sq128: Vector2i) -> int:
	return posmod(sq128.x, 2) + 2 * posmod(sq128.y, 2)


## Sets building `key`'s far version: mesh arrays in its own frame, `xf`
## placing it in the view, `sq128` the view square it belongs to.
func put(key: String, sq128: Vector2i, xf: Transform3D, arrays: Array) -> void:
	drop(key)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var c := square_of(sq128)
	var centre := Vector3((c.x + 0.5) * SIZE, 0.0, (c.y + 0.5) * SIZE)
	var a := _flat(MeshParts.moved(arrays, Transform3D(Basis.IDENTITY, -centre) * xf))
	var uv2 := PackedVector2Array()
	uv2.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uv2.fill(Vector2(quarter_of(sq128), 0.0))
	a[Mesh.ARRAY_TEX_UV2] = uv2
	if not _items.has(c):
		_items[c] = {}
	_items[c][key] = a
	_where[key] = c
	_dirty[c] = true


func drop(key: String) -> void:
	var c = _where.get(key)
	if c == null:
		return
	_where.erase(key)
	_items[c].erase(key)
	_dirty[c] = true


func has_dirty() -> bool:
	return not _dirty.is_empty()


## Merges dirty squares until `budget_us` is spent. `all` merges every one
## now, waiting or not (a town opening).
func rebuild_some(budget_us: int, all := false) -> void:
	var t := Time.get_ticks_usec()
	var now := Time.get_ticks_msec()
	for c in _dirty.keys():
		if not all and _mi.has(c) and now - int(_merged_at.get(c, 0)) < REMERGE_MS:
			continue
		_dirty.erase(c)
		_rebuild(c)
		_merged_at[c] = now
		if Time.get_ticks_usec() - t > budget_us:
			break


## Hides (w = 1) or shows (0) one 128 m square's far blocks, in between
## while it dissolves.
func set_hidden(sq128: Vector2i, w: float) -> void:
	var c := square_of(sq128)
	var h: Vector4 = _hide.get(c, Vector4.ZERO)
	h[quarter_of(sq128)] = w
	_hide[c] = h
	if _mat.has(c):
		_mat[c].set_shader_parameter("hide", h)


func _rebuild(c: Vector2i) -> void:
	var items: Dictionary = _items.get(c, {})
	if items.is_empty():
		if _mi.has(c):
			_mi[c].queue_free()
			_mi.erase(c)
			_mat.erase(c)
		_items.erase(c)
		return
	var merged := []
	for key in items:
		if merged.is_empty():
			merged = MeshParts.copy(items[key])
		else:
			MeshParts.append(merged, items[key])
	if not _mi.has(c):
		var mi := MeshInstance3D.new()
		mi.position = Vector3((c.x + 0.5) * SIZE, 0.0, (c.y + 0.5) * SIZE)
		var m := FadeMats.far_square()
		m.set_shader_parameter("hide", _hide.get(c, Vector4.ZERO))
		mi.material_override = m
		mi.mesh = ArrayMesh.new()
		add_child(mi)
		_mi[c] = mi
		_mat[c] = m
	var mesh: ArrayMesh = _mi[c].mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)


## Surface arrays without an index (each triangle's corners listed), so
## buildings merge by appending.
static func _flat(a: Array) -> Array:
	var idx = a[Mesh.ARRAY_INDEX]
	if idx == null:
		return MeshParts.copy(a)
	var order: PackedInt32Array = idx
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ov := PackedVector3Array()
	ov.resize(order.size())
	for k in order.size():
		ov[k] = v[order[k]]
	out[Mesh.ARRAY_VERTEX] = ov
	if a[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var on := PackedVector3Array()
		on.resize(order.size())
		for k in order.size():
			on[k] = n[order[k]]
		out[Mesh.ARRAY_NORMAL] = on
	if a[Mesh.ARRAY_COLOR] != null:
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var oc := PackedColorArray()
		oc.resize(order.size())
		for k in order.size():
			oc[k] = col[order[k]]
		out[Mesh.ARRAY_COLOR] = oc
	if a[Mesh.ARRAY_TEX_UV] != null:
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var ou := PackedVector2Array()
		ou.resize(order.size())
		for k in order.size():
			ou[k] = uv[order[k]]
		out[Mesh.ARRAY_TEX_UV] = ou
	return out


## For tests and tools: how many far squares are drawn.
func square_count() -> int:
	return _mi.size()
