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
## detail, never under 0.6 so nearby streets stay real, and never over 1.2:
## past about 700 m a house is a few pixels tall even on a 5K screen, and
## drawing every one in full there swamped a Mac Studio); past it, the
## square's blocks.
const FAR_FROM := 600.0
var _far := {}  # Vector2i -> MeshInstance3D
var _far_dirty := {}  # Vector2i -> true
var _by_chunk := {}  # Vector2i -> {lot key: true}, the buildings in each square

## The town changes many times a second while it grows, so a change only
## marks the view dirty: the next frame finds what was added or removed,
## builds new buildings a few at a time (nearest the camera first, within
## SPAWN_MS; a big batch such as a load goes in at once), and rechecks the
## rest for a new look or sign in slices of RECHECK_MS.
const SPAWN_MS := 4
const RECHECK_MS := 2
const SPAWN_ALL := 300
var _dirty := false
var _pending: Array = []  # lot keys waiting to be built, nearest last
var _recheck: Array = []  # lot keys still to look over since the last change
var _recheck_again := false  # changed again while a look-over was under way
var _first := true  # the town as it loads goes in at once
## Finished buildings are drawn merged, one mesh per material for each
## 128 m square, instead of a dozen draw calls each: a town of a few
## hundred homes was thousands of draw calls, most of the frame on a Mac.
## Buildings still going up draw on their own until they're done.
var _baked := {}  # Vector2i -> [MeshInstance3D casting shadows, one not]
var _bake_due := {}  # Vector2i -> msec when its square is merged again
var _unbaked := {}  # Vector2i -> true: lost a merged building this frame
## A square that gains a building waits this long, so a block filling in
## is merged once, not once a house.
const BAKE_WAIT_MS := 3000
const BAKE_BUDGET_MS := 6.0


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(func():
			for c in _far:
				_far[c].visibility_range_begin = _far_from())
	sim.buildings_changed.connect(_mark)
	sim.lots_changed.connect(_mark)
	# A business renamed, bought or with a new look gets new signs.
	sim.families.changed.connect(_mark)
	_dirty = true
	_sync()


func _mark() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty or not _pending.is_empty() or not _recheck.is_empty():
		_sync()
	if not _bake_due.is_empty():
		_bake_some()


func _sync() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var t := Perf.now()
	_sync_all()
	Perf.add("frame.buildings", t)
	Terrain.shift = Vector2.ZERO


func _sync_all() -> void:
	var start := Time.get_ticks_usec()
	if _dirty:
		_dirty = false
		for key in _nodes.keys():
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_unspawn(key)
		var fresh := []
		for key in sim.buildings:
			if not _nodes.has(key) and sim.lots.has(key):
				fresh.append(key)
		var have := {}
		for key in _pending:
			have[key] = true
		for key in fresh:
			if not have.has(key):
				_pending.append(key)
		_sort_pending()
		if _recheck.is_empty():
			_recheck = _nodes.keys()
		else:
			_recheck_again = true
	# Look the rest over for a moved lot (a road widened), a new look or a
	# new sign, a slice at a time.
	while not _recheck.is_empty() and Time.get_ticks_usec() - start < RECHECK_MS * 1000:
		var key: String = _recheck.pop_back()
		if _nodes.has(key) and _stale(key):
			_unspawn(key)
			_pending.append(key)
	if _recheck.is_empty() and _recheck_again:
		_recheck_again = false
		_recheck = _nodes.keys()
	# Build: everything at once for a big batch (loading a town), otherwise
	# nearest first until the frame's share is used.
	var all_now := _first or _pending.size() > SPAWN_ALL
	_first = false
	while not _pending.is_empty():
		var key: String = _pending.pop_back()
		if _nodes.has(key) or not sim.buildings.has(key) or not sim.lots.has(key):
			continue
		var root := _spawn(key, sim.lots[key], sim.buildings[key])
		_nodes[key] = root
		var c := _far_chunk(root)
		if not _by_chunk.has(c):
			_by_chunk[c] = {}
		_by_chunk[c][key] = true
		_far_dirty[c] = true
		if not all_now and Time.get_ticks_usec() - start > SPAWN_MS * 1000:
			break
	for c in _far_dirty:
		var had := _far.has(c)
		_build_far(c)
		# A square's far boxes just appeared: point its buildings at them.
		if not had and _far.has(c):
			for key in _by_chunk.get(c, {}):
				_link_far(_nodes[key])
	_far_dirty.clear()
	# A building torn down or replaced leaves its square's merged mesh at
	# once, so it doesn't linger.
	for c in _unbaked:
		_bake(c)
		_bake_due.erase(c)
	_unbaked.clear()


## Whether a building's drawing is out of date.
func _stale(key: String) -> bool:
	var n: Node3D = _nodes[key]
	var b: Dictionary = sim.buildings[key]
	return not n.get_meta("front").is_equal_approx(sim.lots[key].front) \
			or n.get_meta("look") != _look(b, key) \
			or n.get_meta("sign") != sim.families.sign_key(sim, "lot:" + key) \
			or n.get_meta("chain") != b.get("chain", "")


func _unspawn(key: String) -> void:
	var c := _far_chunk(_nodes[key])
	_far_dirty[c] = true
	if _nodes[key].get_meta("bake", false):
		_unbaked[c] = true
	if _by_chunk.has(c):
		_by_chunk[c].erase(key)
		if _by_chunk[c].is_empty():
			_by_chunk.erase(c)
	_nodes[key].queue_free()
	_nodes.erase(key)
	_trees.remove(key)


## Nearest the camera last, so pop_back takes it first.
func _sort_pending() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _pending.size() < 2:
		return
	var eye := cam.global_position
	var shift := Terrain.shift
	_pending.sort_custom(func(a, b):
		var pa: Vector3 = sim.lots[a].pos if sim.lots.has(a) else Vector3.INF
		var pb: Vector3 = sim.lots[b].pos if sim.lots.has(b) else Vector3.INF
		return Vector2(pa.x + shift.x - eye.x, pa.z + shift.y - eye.z).length_squared() \
				> Vector2(pb.x + shift.x - eye.x, pb.z + shift.y - eye.z).length_squared())


## What the drawing depends on: type, stage, size and how well it's kept.
func _look(b: Dictionary, key: String) -> Array:
	return [BuildingTypes.type_of(b), int(b.get("level", 0)), int(b.get("units", 1)), sim.care.tier_of(key),
		sim.heritage.protected(key)]


func _spawn(key: String, lot: Dictionary, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.set_meta("look", _look(b, key))
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
	HouseBuilder.owner_care = sim.care.tier_of(key)
	HouseBuilder.restored = sim.heritage.protected(key)
	match BuildingTypes.type_of(b):
		"house": built = HouseBuilder.build(s, lot.to_curb, fit, storeys)
		"row_home": built = MetroBuilder.build_row(s, lot.to_curb, fit, int(b.get("units", 2)), storeys)
		"apartments":
			# A high-rise is a tower like the offices (860-880 Lake Shore
			# Drive is apartments).
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, lot.to_curb, fit, storeys, {}, "", true)
			else:
				built = MetroBuilder.build_apartments(s, lot.to_curb, fit, storeys)
		"shop": built = DenseBuilder.build_retail(s, lot.to_curb, fit, spec)
		"shopping_center":
			CommercialBuilder.force_shop = "strip"
			built = DenseBuilder.build_retail(s, lot.to_curb, fit, spec)
			CommercialBuilder.force_shop = ""
		"mixed_use": built = DenseBuilder.build_mixed(s, lot.to_curb, fit, storeys, spec)
		"office":
			# Eight storeys and up is a downtown tower, built for its era.
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, lot.to_curb, fit, storeys, spec)
			else:
				built = DenseBuilder.build_office(s, lot.to_curb, fit, storeys, spec)
		_: built = FactoryBuilder.build_chain(b.get("chain", "general"), s, lot.to_curb, fit, spec)
	HouseBuilder.owner_care = 0
	HouseBuilder.restored = false
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
	root.set_meta("bake", true)
	var c := _far_chunk(root)
	if not _bake_due.has(c):
		_bake_due[c] = Time.get_ticks_msec() + (BAKE_WAIT_MS if _baked.has(c) else 0)
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


func _bake_some() -> void:
	var t := Perf.now()
	var now := Time.get_ticks_msec()
	for c in _bake_due.keys():
		if _bake_due[c] > now:
			continue
		_bake_due.erase(c)
		_bake(c)
		if (Perf.now() - t) / 1000.0 > BAKE_BUDGET_MS:
			break
	Perf.add("frame.buildings", t)


## Merges a square's finished buildings (walls and roofs, and their drives
## and walks) into one mesh per material, and hides their own meshes.
func _bake(c: Vector2i) -> void:
	var centre := Vector3((c.x + 0.5) * FAR_CHUNK, 0.0, (c.y + 0.5) * FAR_CHUNK)
	var to_square := Transform3D(Basis.IDENTITY, -centre) * global_transform.affine_inverse()
	var parts := {}  # [material, format, casts shadow] -> SurfaceTool
	var members := []
	for key in _by_chunk.get(c, {}):
		var root: Node3D = _nodes[key]
		if not root.get_meta("bake", false) or not root.is_inside_tree():
			continue
		for site in root.get_children():
			if not site is ConstructionSite or site.building():
				continue
			for mi: MeshInstance3D in [site._final, site._ground]:
				if mi.mesh == null:
					continue
				var xf := to_square * mi.global_transform
				for i in mi.mesh.get_surface_count():
					var k := [mi.get_active_material(i), mi.mesh.surface_get_format(i), mi == site._final]
					if not parts.has(k):
						parts[k] = SurfaceTool.new()
						parts[k].begin(Mesh.PRIMITIVE_TRIANGLES)
					parts[k].append_from(mi.mesh, i, xf)
				members.append(mi)
	if not _baked.has(c):
		var pair := []
		for shadow in [true, false]:
			var mi := MeshInstance3D.new()
			mi.position = centre
			mi.mesh = ArrayMesh.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			pair.append(mi)
		_baked[c] = pair
	var meshes: Array = [_baked[c][0].mesh, _baked[c][1].mesh]
	for m: ArrayMesh in meshes:
		m.clear_surfaces()
	for k in parts:
		var m: ArrayMesh = meshes[0] if k[2] else meshes[1]
		parts[k].commit(m)
		m.surface_set_material(m.get_surface_count() - 1, k[0])
	for mi in members:
		mi.visible = false
	_link_baked(c)


## The merged square shows only while its far boxes don't.
func _link_baked(c: Vector2i) -> void:
	if not _baked.has(c) or not _far.has(c):
		return
	for mi: MeshInstance3D in _baked[c]:
		mi.visibility_parent = _far[c].get_path()


static func _far_from() -> float:
	return FAR_FROM * clampf(GraphicsQuality.detail, 0.6, 1.2)


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
	for key in _by_chunk.get(c, {}):
		var root: Node3D = _nodes[key]
		if not root.has_meta("box"):
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
	_link_baked(c)


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
