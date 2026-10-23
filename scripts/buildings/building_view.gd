class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes), CommercialBuilder (shops), FactoryBuilder
## (factories, one design per industry chain) and
## DenseBuilder (row homes, apartments, Main Street blocks, offices). Each
## building is drawn for its type and stage, and redrawn when it grows. New
## ones go up stage by stage (ConstructionSite).
##
## Far off, each 128 m square of town is one simple mesh instead: every
## building as its block, with wall and roof colours (HLOD, as Cities: Skylines 2
## and every big city builder do). Each building's own meshes name that box
## as their visibility parent, so Godot swaps them by distance; how near the
## swap comes follows the graphics tier (GraphicsQuality.detail).

var sim: CitySim
var _nodes := {}  # lot key -> Node3D
var _trees := TreeField.new()
static var _footing_mat: Material
static var _far_mat: Material

const FAR_CHUNK := 128.0
## Full buildings out to this far from a square's centre (times the tier's
## detail, never under 0.6 so nearby streets stay real); past it, the
## square's blocks.
const FAR_FROM := 600.0
var _far := {}  # Vector2i -> MeshInstance3D
var _far_dirty := {}  # Vector2i -> true


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(func():
			for c in _far:
				_far[c].visibility_range_begin = _far_from())
	sim.buildings_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	# A business renamed, bought or with a new look gets new signs.
	sim.families.changed.connect(_sync)
	_sync()


func _sync() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var t := Perf.now()
	_sync_all()
	Perf.add("frame.buildings", t)
	Terrain.shift = Vector2.ZERO


func _sync_all() -> void:
	for key in _nodes.keys():
		# Gone, or its lot moved (the road was widened), or its sign changed.
		if not sim.buildings.has(key) or not sim.lots.has(key) \
				or not _nodes[key].get_meta("front").is_equal_approx(sim.lots[key].front) \
				or _nodes[key].get_meta("look") != _look(sim.buildings[key]) \
				or _nodes[key].get_meta("sign") != sim.families.sign_key(sim, "lot:" + key) \
				or _nodes[key].get_meta("chain") != sim.buildings[key].get("chain", ""):
			_far_dirty[_far_chunk(_nodes[key])] = true
			_nodes[key].queue_free()
			_nodes.erase(key)
			_trees.remove(key)
	for key in sim.buildings:
		if not _nodes.has(key) and sim.lots.has(key):
			_nodes[key] = _spawn(key, sim.lots[key], sim.buildings[key])
			_far_dirty[_far_chunk(_nodes[key])] = true
	for c in _far_dirty:
		_build_far(c)
	_far_dirty.clear()
	for key in _nodes:
		if _nodes[key].get_meta("far", Vector2i(1 << 30, 0)) != _far_chunk(_nodes[key]):
			_link_far(_nodes[key])


## What the drawing depends on: type, stage and size.
static func _look(b: Dictionary) -> Array:
	return [BuildingTypes.type_of(b), int(b.get("level", 0)), int(b.get("units", 1))]


func _spawn(key: String, lot: Dictionary, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.set_meta("look", _look(b))
	add_child(root)
	root.set_meta("front", lot.front)
	root.set_meta("sign", sim.families.sign_key(sim, "lot:" + key))
	var spec := sim.families.sign_of(sim, "lot:" + key)
	root.set_meta("chain", b.get("chain", ""))  # a factory's look follows its chain
	# On the land: the lot is graded level with the road at its middle.
	root.position = Vector3(lot.front.x, Terrain.base_y(lot.pos.x, lot.pos.z), lot.front.z)
	# Local -Z faces the street, +Z runs back into the lot.
	root.basis = Basis.looking_at(-lot.normal, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var built := []
	var fit := _local_lot(lot, Transform3D(root.basis, root.position))
	var s := rng.randi()
	var storeys := BuildingTypes.storeys(b)
	match BuildingTypes.type_of(b):
		"house": built = HouseBuilder.build(s, lot.to_curb, fit, storeys)
		"row_home": built = MetroBuilder.build_row(s, lot.to_curb, fit, int(b.get("units", 2)), storeys)
		"apartments": built = MetroBuilder.build_apartments(s, lot.to_curb, fit, storeys)
		"shop": built = DenseBuilder.build_retail(s, lot.to_curb, fit, spec)
		"mixed_use": built = DenseBuilder.build_mixed(s, lot.to_curb, fit, storeys, spec)
		"office":
			# Eight storeys and up is a downtown tower, built for its era.
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, lot.to_curb, fit, storeys, spec)
			else:
				built = DenseBuilder.build_office(s, lot.to_curb, fit, storeys, spec)
		_: built = FactoryBuilder.build_chain(b.get("chain", "general"), s, lot.to_curb, fit, spec)
	if built.is_empty():
		return root
	root.set_meta("box", built[0].get_aabb())
	root.set_meta("wall", _wall_colour(int(b.zone), rng))
	var pitched: bool = BuildingTypes.type_of(b) in ["house", "row_home"]
	root.set_meta("pitched", pitched)
	root.set_meta("roof", _roof_colour(pitched, rng))
	# Drives, walks and beds lie on the ground, following it.
	built[1] = Terrain.drape_local(built[1], root.transform)
	# It goes up stage by stage; the trees and the sign's lettering go in
	# once it's done.
	var ref := "lot:" + key
	var labels: Array = built[3] if built.size() > 3 else []
	ConstructionSite.add_to(root, built, CitySim.PROFILE_OF_ZONE.get(int(b.zone), "house"),
		func(): return sim.construction.state(ref, sim.tick_count), _plant.bind(key, root, built[2], labels),
		_footing(built[0]))
	return root


## Trees go to the shared tree field, placed in world space on the ground,
## and the business's name onto its sign.
func _plant(key: String, root: Node3D, planted: Array, labels := []) -> void:
	if not is_instance_valid(root) or _nodes.get(key, root) != root:
		return
	SignText.add(root, labels)
	_link_far(root)
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in planted:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2]])
	Terrain.shift = was
	_trees.set_trees(key, trees)


static func _far_from() -> float:
	return FAR_FROM * maxf(GraphicsQuality.detail, 0.6)


func _far_chunk(root: Node3D) -> Vector2i:
	return Vector2i(floori(root.position.x / FAR_CHUNK), floori(root.position.z / FAR_CHUNK))


## Points every mesh of a building at its square's far boxes, so it shows
## only while they don't.
func _link_far(root: Node3D) -> void:
	var c := _far_chunk(root)
	if not _far.has(c):
		return
	root.set_meta("far", c)
	var path: NodePath = _far[c].get_path()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			n.visibility_parent = path
		stack.append_array(n.get_children())


## One square's buildings as boxes: walls in their colour, a darker roof.
func _build_far(c: Vector2i) -> void:
	var centre := Vector3((c.x + 0.5) * FAR_CHUNK, 0.0, (c.y + 0.5) * FAR_CHUNK)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for key in _nodes:
		var root: Node3D = _nodes[key]
		if not root.has_meta("box") or _far_chunk(root) != c:
			continue
		any = true
		_box(st, Transform3D(root.basis, root.position - centre), root.get_meta("box"), root.get_meta("wall"),
			root.get_meta("roof"), root.get_meta("pitched"))
	if not any:
		if _far.has(c):
			_far[c].queue_free()
			_far.erase(c)
		return
	if not _far.has(c):
		var mi := MeshInstance3D.new()
		mi.position = centre
		mi.visibility_range_begin = _far_from()
		if _far_mat == null:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_far_mat = m
		mi.material_override = _far_mat
		mi.mesh = ArrayMesh.new()
		add_child(mi)
		_far[c] = mi
	# Refill the same mesh: swapping it trips the buildings that name this
	# box as their visibility parent while they're hidden.
	var mesh: ArrayMesh = _far[c].mesh
	mesh.clear_surfaces()
	st.commit(mesh)


## One building as its block: walls in its colour; a houses' pitched
## shingle roof (ridge along the long side) or a commercial flat roof.
static func _box(st: SurfaceTool, xf: Transform3D, box: AABB, wall: Color, roof: Color, pitched: bool) -> void:
	var lo := box.position
	var hi := box.end
	var mid: Vector3 = xf * box.get_center()
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var eave := lo.y + (hi.y - lo.y) * 0.62 if pitched else hi.y
	# Walls.
	_quad(st, mid, wall, [p.call(lo.x, lo.y, lo.z), p.call(hi.x, lo.y, lo.z), p.call(hi.x, eave, lo.z), p.call(lo.x, eave, lo.z)])
	_quad(st, mid, wall, [p.call(hi.x, lo.y, hi.z), p.call(lo.x, lo.y, hi.z), p.call(lo.x, eave, hi.z), p.call(hi.x, eave, hi.z)])
	_quad(st, mid, wall, [p.call(lo.x, lo.y, hi.z), p.call(lo.x, lo.y, lo.z), p.call(lo.x, eave, lo.z), p.call(lo.x, eave, hi.z)])
	_quad(st, mid, wall, [p.call(hi.x, lo.y, lo.z), p.call(hi.x, lo.y, hi.z), p.call(hi.x, eave, hi.z), p.call(hi.x, eave, lo.z)])
	if not pitched:
		_quad(st, mid, roof, [p.call(lo.x, hi.y, lo.z), p.call(hi.x, hi.y, lo.z), p.call(hi.x, hi.y, hi.z), p.call(lo.x, hi.y, hi.z)])
		return
	if box.size.x >= box.size.z:
		var zc := (lo.z + hi.z) * 0.5
		_quad(st, mid, roof, [p.call(lo.x, eave, lo.z), p.call(hi.x, eave, lo.z), p.call(hi.x, hi.y, zc), p.call(lo.x, hi.y, zc)])
		_quad(st, mid, roof, [p.call(hi.x, eave, hi.z), p.call(lo.x, eave, hi.z), p.call(lo.x, hi.y, zc), p.call(hi.x, hi.y, zc)])
		_quad(st, mid, wall, [p.call(lo.x, eave, hi.z), p.call(lo.x, eave, lo.z), p.call(lo.x, hi.y, zc), p.call(lo.x, hi.y, zc)])
		_quad(st, mid, wall, [p.call(hi.x, eave, lo.z), p.call(hi.x, eave, hi.z), p.call(hi.x, hi.y, zc), p.call(hi.x, hi.y, zc)])
	else:
		var xc := (lo.x + hi.x) * 0.5
		_quad(st, mid, roof, [p.call(lo.x, eave, hi.z), p.call(lo.x, eave, lo.z), p.call(xc, hi.y, lo.z), p.call(xc, hi.y, hi.z)])
		_quad(st, mid, roof, [p.call(hi.x, eave, lo.z), p.call(hi.x, eave, hi.z), p.call(xc, hi.y, hi.z), p.call(xc, hi.y, lo.z)])
		_quad(st, mid, wall, [p.call(lo.x, eave, lo.z), p.call(hi.x, eave, lo.z), p.call(xc, hi.y, lo.z), p.call(xc, hi.y, lo.z)])
		_quad(st, mid, wall, [p.call(hi.x, eave, hi.z), p.call(lo.x, eave, hi.z), p.call(xc, hi.y, hi.z), p.call(xc, hi.y, hi.z)])


## A face as two triangles (one when two corners meet), lit facing away
## from the building's middle.
static func _quad(st: SurfaceTool, mid: Vector3, col: Color, q: Array) -> void:
	var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
	if n.dot((q[0] + q[1] + q[2]) / 3.0 - mid) < 0.0:
		n = -n
	st.set_color(col)
	st.set_normal(n)
	var tris := [0, 2, 1] if q[2].is_equal_approx(q[3]) else [0, 2, 1, 0, 3, 2]
	for i in tris:
		st.add_vertex(q[i])


## Seen from far off, roofs are asphalt shingle on homes; flat commercial
## and industrial roofs are pale membrane or gravel.
static func _roof_colour(pitched: bool, rng: RandomNumberGenerator) -> Color:
	var options := [Color("#4d4a47"), Color("#5b544c"), Color("#3f4144"), Color("#6a5f55")] if pitched \
		else [Color("#9c9a95"), Color("#b5b3ad"), Color("#86847f")]
	return options[rng.randi() % options.size()]


## A building's walls seen from far off: siding and brick for homes,
## brick and stone downtown, metal and block for industry.
static func _wall_colour(zone: int, rng: RandomNumberGenerator) -> Color:
	var options: Array
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			options = [Color("#d8d2c4"), Color("#b9b3a5"), Color("#8f6a55"), Color("#c9c1a8"), Color("#9aa3a6")]
		ZoneMap.Zone.COMMERCIAL:
			options = [Color("#8a5a46"), Color("#a89c86"), Color("#7b7770"), Color("#b5aa95")]
		_:
			options = [Color("#9a9a94"), Color("#7d7a72"), Color("#a8a49a")]
	return options[rng.randi() % options.size()]


## The lot as the art builders want it: width, depth, flag pad, and the
## outline in the building's own frame (x across, z back from the street).
static func _local_lot(lot: Dictionary, frame: Transform3D) -> Dictionary:
	var fit := {"width": lot.get("width", 20.0), "depth": lot.get("depth", 32.0), "pad": lot.get("pad", 0.0),
		"at": Vector2(frame.origin.x, frame.origin.z), "corner": lot.get("corner", false)}
	var corners: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if corners.size() >= 3:
		var inv := frame.affine_inverse()
		var local := PackedVector2Array()
		for c in corners:
			var q := inv * Vector3(c.x, 0.0, c.y)
			local.append(Vector2(q.x, q.z))
		fit.outline = local
	return fit


## A foundation down into the ground, for lots on a slope (or null).
func _footing(building: Mesh) -> MeshInstance3D:
	var box := building.get_aabb()
	if box.size.x <= 0.5:
		return null
	var footing := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(box.size.x * 0.96, 3.0, box.size.z * 0.96)
	footing.mesh = cube
	footing.position = Vector3(box.get_center().x, -1.45, box.get_center().z)
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	footing.material_override = _footing_mat
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return footing
