class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes), CommercialBuilder (shops), FactoryBuilder
## (factories, one design per industry chain) and
## DenseBuilder (row homes, apartments, Main Street blocks, offices). Each
## building is drawn for its type and stage, and redrawn when it grows. New
## ones go up stage by stage (ConstructionSite).
##
## Far off, each 128 m square of town is one simple mesh instead (HLOD, as
## Cities: Skylines 2 and every big city builder do): every building as its
## own walls, roofs and windows, the big pieces of its close-up drawing in
## their real colours, without trim, gutters, porches and the rest (as
## Anno 1800's far models keep each building's outline, roof and colours),
## about a hundred triangles a building. Each building's own meshes name
## that square as their visibility parent, so Godot swaps them by distance;
## how near the swap comes follows the graphics tier (GraphicsQuality.detail).

var sim: CitySim
var _nodes := {}  # lot key -> Node3D
var _trees := TreeField.new()
static var _footing_mat: Material

const FAR_CHUNK := 128.0
## Full buildings out to this far from a square's centre (times the tier's
## detail, never under 0.6 so nearby streets stay real, and never over 1.2:
## past about 700 m a house is a few pixels tall even on a 5K screen, and
## drawing every one in full there swamped a Mac Studio); past it, the
## square's blocks.
const FAR_FROM := 600.0
## How far past the swap the camera must go back before it swaps again
## (hysteresis): without it, a square right at the swap distance flickered
## between its close-up and far versions while the camera eased or zoomed
## (Brawn's apartment block, 2026-10-24).
const FAR_MARGIN := 40.0
## The parts of a close-up drawing its far version keeps: walls, roofs and
## windows (and a factory's metal cladding). Everything else is small.
const FAR_KEEP := ["siding", "brick", "roof", "membrane", "glass"]
static var _far_kinds := {}  # Material -> its HouseMaterials name
var _far := {}  # Vector2i -> MeshInstance3D
var _far_dirty := {}  # Vector2i -> true
var _by_chunk := {}  # Vector2i -> {lot key: true}, the buildings in each square

## The town changes many times a second while it grows, so a change only
## marks the view dirty: the next frame finds what was added or removed,
## builds new buildings a few at a time (nearest the camera first, within
## SPAWN_MS; a big batch such as a load, see LOAD_MS), and rechecks the
## rest for a new look or sign in slices of RECHECK_MS.
const SPAWN_MS := 4
const RECHECK_MS := 2
const SPAWN_ALL := 300
var _dirty := false
var _pending: Array = []  # lot keys waiting to be built, nearest last
var _regraded := {}  # lot keys drawn again once the ground under them was regraded
var _recheck: Array = []  # lot keys still to look over since the last change
var _recheck_again := false  # changed again while a look-over was under way
var _first := true  # the town as it loads: nearest the camera first, for up to LOAD_MS
## Opening a town draws what's around the camera behind the loading screen,
## then the rest FILL_MS a frame while you play (far boxes once it's all in).
const LOAD_MS := 1500
const FILL_MS := 8
var _filling := false
## A neighbor's whole town lands at once, while you play: drawn a few
## buildings a frame even then, its far boxes once it's all in (RegionView).
var sliced := false
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
	# Build nearest first until the frame's share is used. A town opening (or any big batch) gets LOAD_MS now, nearest the camera
	# first, and the rest FILL_MS a frame after.
	var budget := FILL_MS if _filling else SPAWN_MS
	if not sliced and not _filling and not _pending.is_empty() and (_first or _pending.size() > SPAWN_ALL):
		_first = false
		_filling = true
		budget = LOAD_MS
	while not _pending.is_empty():
		var key: String = _pending.pop_back()
		# Swapped in the same frame, so it never blinks out.
		if _regraded.has(key):
			_regraded.erase(key)
			if _nodes.has(key):
				_unspawn(key)
		if _nodes.has(key) or not sim.buildings.has(key) or not sim.lots.has(key):
			continue
		var root := _spawn(key, sim.lots[key], sim.buildings[key])
		_nodes[key] = root
		var c := _far_chunk(root)
		if not _by_chunk.has(c):
			_by_chunk[c] = {}
		_by_chunk[c][key] = true
		_far_dirty[c] = true
		if Time.get_ticks_usec() - start > budget * 1000:
			break
	if (sliced or _filling) and not _pending.is_empty():
		return
	_filling = false
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


## The ground was regraded inside `box` (view coordinates, a new road's
## strip): buildings with lots reaching into it are drawn again, so their
## walls, drives and parking sit on the graded pad instead of the land as it
## was (Brawn 2026-10-24: lots and drives half under the grass).
func regraded(box: Rect2) -> void:
	var near := box.grow(LOT_REACH)
	var any := false
	for key in _nodes:
		if _regraded.has(key) or not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		if near.has_point(Vector2(p.x, p.z)):
			_regraded[key] = true
			_pending.append(key)
			any = true
	if any:
		_sort_pending()


## How far a lot's paving reaches from its middle (the deepest lots are
## about 60 m, 200 ft).
const LOT_REACH := 45.0


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
	var masses: Array = HouseBuilder.last_masses
	# On a hillside the house stands on the highest ground under its walls,
	# with a walkout foundation down to the low side: never with the hill
	# coming up through the floor (Brawn's homes built through a forest).
	var seat := seat_on(masses, root.transform, Terrain.ground_y)
	root.position.y += seat.x
	# Its far version, for its square's far mesh (a building drawn with no
	# masses noted stands as the box of its drawing).
	var bulk := masses
	if bulk.is_empty():
		var box := built[0].get_aabb() as AABB
		bulk = [Rect2(box.position.x, box.position.z, box.size.x, box.size.z)]
	var pitched: bool = BuildingTypes.type_of(b) in ["house", "row_home"]
	root.set_meta("far_mesh", far_version(built[0], bulk, int(b.zone) == ZoneMap.Zone.INDUSTRIAL,
		_wall_colour(int(b.zone), rng), _roof_colour(pitched, rng), built[1]))
	# Drives, walks and beds lie on the ground, following it.
	built[1] = Terrain.drape_local(built[1], root.transform)
	# It goes up stage by stage; the trees and the sign's lettering go in
	# once it's done.
	var ref := "lot:" + key
	var labels: Array = built[3] if built.size() > 3 else []
	ConstructionSite.add_to(root, built, CitySim.PROFILE_OF_ZONE.get(int(b.zone), "house"),
		func(): return sim.construction.state(ref, sim.tick_count), _plant.bind(key, root, built[2], labels),
		_footing(masses, seat.y))
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
		var far: ArrayMesh = root.get_meta("far_mesh", null)
		if far == null or far.get_surface_count() == 0:
			continue
		any = true
		st.append_from(far, 0, Transform3D(root.basis, root.position - centre))
	if not any:
		if _far.has(c):
			_far[c].queue_free()
			_far.erase(c)
		return
	if not _far.has(c):
		var mi := MeshInstance3D.new()
		mi.position = centre
		mi.visibility_range_begin = _far_from()
		mi.visibility_range_begin_margin = FAR_MARGIN
		# One material for the whole town (towers' far walls use it too):
		# each shader seen for the first time is a stall while it compiles.
		mi.material_override = HouseMaterials.get_mat("far")
		mi.mesh = ArrayMesh.new()
		add_child(mi)
		_far[c] = mi
	# Refill the same mesh: swapping it trips the buildings that name this
	# box as their visibility parent while they're hidden.
	var mesh: ArrayMesh = _far[c].mesh
	mesh.clear_surfaces()
	st.commit(mesh)
	_link_baked(c)


## A building's far version, from its close-up drawing: the walls, roofs
## and windows as drawn (FAR_KEEP, a hundred triangles or so), merged into
## one surface for the "far" shader: colour in RGB, and UV picking what the
## shader draws there (zero: the plain colour; panes sit in a window cell,
## so they show as glass and light up after dark). Under them each mass is
## a box a little inside its walls, up to its eaves, so walls drawn in other
## parts (trim, painted fronts) never leave a hole; a mass with no roof
## drawn over it gets a flat one in `flat`. `wall` colours the boxes when
## the drawing has no siding or brick. From `ground` (the lot's flat work,
## before it's laid on the land) come its drives, walks and parking: pale
## concrete and dark asphalt strips are much of what a street of homes
## looks like from afar.
static func far_version(mesh: ArrayMesh, masses: Array, industrial: bool, wall: Color, flat: Color,
		ground: ArrayMesh = null) -> ArrayMesh:
	if _far_kinds.is_empty():
		for k in FAR_KEEP + ["metal"]:
			_far_kinds[HouseMaterials.get_mat(k)] = k
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var roofs := PackedVector3Array()
	var sides := PackedVector3Array()
	var most := 0
	for i in mesh.get_surface_count():
		var kind: String = _far_kinds.get(mesh.surface_get_material(i), "")
		if kind == "" or (kind == "metal" and not industrial):
			continue
		var a := mesh.surface_get_arrays(i)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var base := verts.size()
		verts.append_array(v)
		var n = a[Mesh.ARRAY_NORMAL]
		if n == null or (n as PackedVector3Array).size() != v.size():
			n = PackedVector3Array()
			n.resize(v.size())
			n.fill(Vector3.UP)
		normals.append_array(n)
		var at := colours.size()
		var c = a[Mesh.ARRAY_COLOR]
		if kind == "glass" or c == null or (c as PackedColorArray).size() != v.size():
			c = PackedColorArray()
			c.resize(v.size())
			c.fill(Color(0.16, 0.18, 0.2, 0.5) if kind == "glass" else wall)
		colours.append_array(c)
		var uv := PackedVector2Array()
		uv.resize(v.size())
		uv.fill(Vector2(1.0, 1.85) if kind == "glass" else Vector2.ZERO)
		uvs.append_array(uv)
		var idx = a[Mesh.ARRAY_INDEX]
		if idx == null:
			for k in v.size():
				index.append(base + k)
		else:
			for k: int in idx:
				index.append(base + k)
		if kind == "roof" or kind == "membrane":
			roofs.append_array(v)
		elif kind != "glass":
			sides.append_array(v)
			if v.size() > most and kind != "metal":
				most = v.size()
				wall = colours[at]
	wall.a = 0.0
	if ground != null and ground.get_surface_count() > 0:
		_far_paving(ground, verts, normals, colours, uvs, index)
	for m: Rect2 in masses:
		var r := m.grow(-0.25)
		if r.size.x <= 0.5 or r.size.y <= 0.5:
			continue
		# The eaves: the lowest roof edge over the mass; with no roof drawn
		# over it, the tops of its walls, under a flat roof.
		var eave := INF
		var cover := m.grow(0.6)
		for p in roofs:
			if cover.has_point(Vector2(p.x, p.z)):
				eave = minf(eave, p.y)
		var capped := eave == INF
		if capped:
			eave = 0.0
			for p in sides:
				if cover.has_point(Vector2(p.x, p.z)):
					eave = maxf(eave, p.y)
			if eave <= 0.5:
				continue
		var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
		var corners := [Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.0, r.position.y),
			Vector3(r.end.x, 0.0, r.end.y), Vector3(r.position.x, 0.0, r.end.y)]
		var up := Vector3.UP * eave
		for k in 4:
			var p0: Vector3 = corners[k]
			var p1: Vector3 = corners[(k + 1) % 4]
			var out := (p1 - p0).cross(Vector3.UP).normalized()
			if out.dot((p0 + p1) * 0.5 - mid) < 0.0:
				out = -out
			_far_quad(verts, normals, colours, uvs, index, [p0, p1, p1 + up, p0 + up], out, wall)
		if capped:
			var top := flat
			top.a = 0.0
			var lid := Vector3.UP * (eave + 0.05)
			_far_quad(verts, normals, colours, uvs, index,
				[corners[0] + lid, corners[1] + lid, corners[2] + lid, corners[3] + lid], Vector3.UP, top)
	var out_mesh := ArrayMesh.new()
	if verts.is_empty():
		return out_mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out_mesh


## The drives, walks and lots of a lot's flat work (the yard shader's kinds
## in vertex alpha: 0 concrete, 0.4 asphalt), a little above the lot so
## they hold on the land however far off.
static func _far_paving(ground: ArrayMesh, verts: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, uvs: PackedVector2Array, index: PackedInt32Array) -> void:
	var a := ground.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c = a[Mesh.ARRAY_COLOR]
	if c == null or a[Mesh.ARRAY_INDEX] != null:
		return
	var lift := Vector3.UP * 0.12
	for t in range(0, v.size() - 2, 3):
		var kind: float = c[t].a
		if kind > 0.5:
			continue
		var col := Color(0.78, 0.77, 0.73, 0.0) if kind < 0.2 else Color(0.24, 0.24, 0.25, 0.0)
		var base := verts.size()
		for k in 3:
			verts.append(v[t + k] + lift)
			normals.append(Vector3.UP)
			colours.append(col)
			uvs.append(Vector2.ZERO)
			index.append(base + k)


## A flat face of a far version, both triangles.
static func _far_quad(verts: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray,
		uvs: PackedVector2Array, index: PackedInt32Array, q: Array, n: Vector3, col: Color) -> void:
	var base := verts.size()
	for p: Vector3 in q:
		verts.append(p)
		normals.append(n)
		colours.append(col)
		uvs.append(Vector2.ZERO)
	for k in [0, 1, 2, 0, 2, 3]:
		index.append(base + k)


## Seen from far off, roofs are asphalt shingle on homes; flat commercial
## and industrial roofs are pale membrane (white or grey TPO) or gravel.
static func _roof_colour(pitched: bool, rng: RandomNumberGenerator) -> Color:
	var options := [Color("#4d4a47"), Color("#5b544c"), Color("#3f4144"), Color("#6a5f55")] if pitched \
		else [Color("#c4c2bb"), Color("#d2d0ca"), Color("#a9a7a1")]
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


## How a building meets sloping ground: [how far to raise it so no ground
## stands above its floor anywhere under its walls, how deep its foundation
## must reach to meet the lowest ground there]. `xform` places the building's
## local frame; `ground` is Callable(x, z) -> height in that frame's parent.
## A hillside home is built this way: the uphill wall at grade and a walkout
## basement (or a taller foundation) exposed on the downhill side.
static func seat_on(masses: Array, xform: Transform3D, ground: Callable) -> Vector2:
	var floor_y := xform.origin.y
	var hi := -INF
	var lo := INF
	for m: Rect2 in masses:
		var r := m.grow(-0.15)
		for fx in [0.0, 0.5, 1.0]:
			for fz in [0.0, 0.5, 1.0]:
				var w := xform * Vector3(r.position.x + r.size.x * fx, 0.0, r.position.y + r.size.y * fz)
				var g: float = ground.call(w.x, w.z)
				hi = maxf(hi, g)
				lo = minf(lo, g)
	if hi == -INF:
		return Vector2(0.0, FOOTING_DEPTH)
	var lift := maxf(hi - floor_y, 0.0)
	return Vector2(lift, maxf(FOOTING_DEPTH, floor_y + lift - lo + 0.3))


## How deep a foundation shows below the floor on level ground.
const FOOTING_DEPTH := 2.95


## A foundation down into the ground under each building mass, for lots on
## a slope (or null): just under the walls, as a real one is, never a slab
## across the yard; `depth` reaches the lowest ground under them.
func _footing(masses: Array, depth := FOOTING_DEPTH) -> MeshInstance3D:
	if masses.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m: Rect2 in masses:
		var r := m.grow(-0.15)
		if r.size.x <= 0.3 or r.size.y <= 0.3:
			continue
		var lo := Vector3(r.position.x, -depth, r.position.y)
		var hi := Vector3(r.end.x, 0.05, r.end.y)
		var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
			Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		for f in [[0, 1, 5, 4, Vector3.FORWARD], [1, 2, 6, 5, Vector3.RIGHT], [2, 3, 7, 6, Vector3.BACK],
				[3, 0, 4, 7, Vector3.LEFT], [4, 5, 6, 7, Vector3.UP]]:
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(f[4])
				st.add_vertex(c[f[i]])
	var footing := MeshInstance3D.new()
	footing.mesh = st.commit()
	if footing.mesh.get_surface_count() == 0:
		return null
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	footing.material_override = _footing_mat
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return footing
