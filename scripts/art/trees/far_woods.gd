class_name FarWoods
extends Node3D
## The wild woods past the edge of WildView's reach, out toward the
## horizon: every tree one quad facing the camera, the size and colour of
## its card crown (TreeField), with the same leaf shader (TreeLook, zone
## mode 6), so from far off the woods, fencerows and lone trees are still
## there, and when the camera comes closer the cards take over each tree
## where it stands with a dither, instead of trees growing out of empty
## land. Benchmark: Flight Simulator's and Cities: Skylines 2's distant
## forests, drawn as cheap stand-ins out to the haze.
##
## The trees are WildView's (the same plants, the same spots, the same
## kinds); this node only keeps them packed for the graphics card, a
## buffer per 256 m chunk, drawn as one MultiMesh per TILE square: a few
## dozen draw calls for the whole ring.

## Tiles the far woods are drawn in (m): each is one draw call.
const TILE := 1024.0
## How much of the crown's box the quad covers: the leaf texture is a
## ragged disc, not a square (looked at against the cards at the hand-over).
const FILL := 1.05
## The quads' shade (see far_shade): where the woods cast shadows, and not.
const SHADE_SHADOWED := 0.55
const SHADE := 0.75
const SHADE_BROWSER := 0.7
## Floats per tree in a MultiMesh buffer: a 3x4 transform, colour, custom.
const STRIDE := 20

var _chunks := {}  # Vector2i chunk -> PackedFloat32Array of trees
var _tiles := {}  # Vector2i tile -> MultiMeshInstance3D
var _dirty := {}  # Vector2i tile -> true
var _trees := 0

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


## Replaces a chunk's trees: WildView's trees as TreeField takes them
## ([placement, kind, tint, facts]); brush is left out (it has no far version).
func set_chunk(c: Vector2i, trees: Array) -> void:
	var t := tile_of(c)
	var centre := _tile_centre(t)
	var buf := PackedFloat32Array()
	for tree in trees:
		var facts: Dictionary = tree[3] if tree.size() > 3 and tree[3] is Dictionary else {}
		if facts.has("shrub"):
			continue
		var r := TreeField.resolve(tree)
		var xf: Transform3D = r[0]
		var b := xf.basis
		var o := xf.origin - centre
		var custom := TreeField.custom_of(r[2], r[1], true)
		buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
			1.0, 1.0, 1.0, 1.0, custom.r, custom.g, custom.b, custom.a])
	_trees += buf.size() / STRIDE - (_chunks[c].size() / STRIDE if _chunks.has(c) else 0)
	_chunks[c] = buf
	_dirty[t] = true


func drop_chunk(c: Vector2i) -> void:
	if _chunks.has(c):
		_trees -= _chunks[c].size() / STRIDE
		_chunks.erase(c)
		_dirty[tile_of(c)] = true


func has_chunk(c: Vector2i) -> bool:
	return _chunks.has(c)


func chunks() -> Array:
	return _chunks.keys()


## Trees drawn far (for the labs and tests).
func tree_count() -> int:
	return _trees


## A chunk's trees as drawn: [transform (view space), custom data].
func chunk_trees(c: Vector2i) -> Array:
	var out := []
	if not _chunks.has(c):
		return out
	var buf: PackedFloat32Array = _chunks[c]
	var centre := _tile_centre(tile_of(c))
	for i in range(0, buf.size(), STRIDE):
		var b := Basis(Vector3(buf[i], buf[i + 4], buf[i + 8]), Vector3(buf[i + 1], buf[i + 5], buf[i + 9]),
			Vector3(buf[i + 2], buf[i + 6], buf[i + 10]))
		out.append([Transform3D(b, Vector3(buf[i + 3], buf[i + 7], buf[i + 11]) + centre),
			Color(buf[i + 16], buf[i + 17], buf[i + 18], buf[i + 19])])
	return out


static func tile_of(c: Vector2i) -> Vector2i:
	var per := int(TILE / Vegetation.CHUNK)
	return Vector2i(floori(float(c.x) / per), floori(float(c.y) / per))


static func _tile_centre(t: Vector2i) -> Vector3:
	return Vector3((t.x + 0.5) * TILE, 0.0, (t.y + 0.5) * TILE)


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	var start := Perf.now()
	var per := int(TILE / Vegetation.CHUNK)
	for t in _dirty:
		var buf := PackedFloat32Array()
		for x in per:
			for z in per:
				var c := Vector2i(t.x * per + x, t.y * per + z)
				if _chunks.has(c):
					buf.append_array(_chunks[c])
		var n := buf.size() / STRIDE
		if n == 0:
			if _tiles.has(t):
				_tiles[t].queue_free()
				_tiles.erase(t)
			continue
		var mmi: MultiMeshInstance3D = _tiles.get(t)
		if mmi == null:
			mmi = _tile(t)
		mmi.multimesh.instance_count = n
		mmi.multimesh.buffer = buf
	_dirty.clear()
	Perf.add("frame.trees.far", start)


func _tile(t: Vector2i) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# White instance colours: the browser's renderer multiplies vertex COLOR
	# by the instance colour (TreeField).
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = _tile_centre(t)
	# The quads are placed in the shader: the tile's box, with room for the
	# hills and the tallest crowns.
	mmi.custom_aabb = AABB(Vector3(-TILE * 0.5 - 20.0, -200.0, -TILE * 0.5 - 20.0), Vector3(TILE + 40.0, 500.0, TILE + 40.0))
	# Far trees' shadows would cost more than they show.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_tiles[t] = mmi
	return mmi


## One quad (UV2: its corner, -1 to 1), placed and sized in the shader.
## Vertex colour as TreeField's cards use it: r how far out in the crown
## (a little in), g the top of the crown, b the cluster's hue, alpha 0.5
## a far tree's card.
static func quad_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var n := PackedVector3Array()
	for k in corners:
		v.append(Vector3(k.x * 8.0, 8.0 + k.y * 8.0, 0.0))
		uv.append(Vector2(k.x * 0.5 + 0.5, 0.5 - k.y * 0.5))
		uv2.append(k)
		col.append(Color(0.75, k.y * 0.5 + 0.5, 0.5, 0.5))
		n.append(Vector3.BACK)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, material())
	return _mesh


static func material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = TreeLook.card_material(TreeLook.far_shader_code(), 6, true, TreeField.leaf_texture(), TreeField.twig_texture())
	_mat.set_shader_parameter("crown_box", crown_boxes())
	_mat.set_shader_parameter("far_shade", far_shade())
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(func(): _mat.set_shader_parameter("far_shade", far_shade()))
	return _mat


## How much darker than lit leaves the quads are drawn: a crown of cards
## shades its own inner leaves, and more where the woods cast shadows
## (matched against the cards at the hand-over, in pictures from
## tools/tree_lod_shot.gd compare).
static func far_shade() -> float:
	# The browser's renderer lights the cards' crowns darker still.
	return (SHADE_SHADOWED if GraphicsQuality.tree_shadows else SHADE) * (SHADE_BROWSER if TreeLook.browser() else 1.0)


## Each kind's crown at full size, for the shader: centre height, half
## width, half height (TreeField.crown_bounds, times FILL), and the trunk's
## radius (as TreeField's cards draw it) over the half width.
static func crown_boxes() -> PackedVector4Array:
	var out := PackedVector4Array()
	for sp in 16:
		var k := sp if sp < TreeKinds.count() else 0
		var b := TreeField.crown_bounds(k)
		var half_w := (b.size.x + b.size.z) * 0.25 * FILL
		var trunk := TreeKinds.dbh(k, TreeKinds.REF_AGE) * 0.006
		out.append(Vector4(b.position.y + b.size.y * 0.5, half_w, b.size.y * 0.5 * FILL, trunk / half_w))
	return out
