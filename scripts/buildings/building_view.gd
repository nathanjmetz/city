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
##
## Houses are drawn the new way (docs/scale-test-2026-10-25.md, "The new
## drawing style, measured"), grown from their facts (lot, kind, age, seed)
## by the same builder, in three rings:
##   far     every house's far version, merged for each 256 m square
##           (FarSquares): one record of about a hundred triangles a house,
##           and nothing else kept
##   middle  within FULL_FROM, each 128 m square's houses in full, merged
##           into one mesh per material (BatchSquare), swapped for the far
##           versions once it's all merged; past it the full drawings are let
##           go, so memory follows the camera, not the size of the town
##   near    within about 100 m, brick by brick, lap by lap and course by
##           course over the house's own walls and roofs (NearDetail), grown
##           a few small jobs a frame
## Shops, civic buildings and factories follow in later steps (NEW_TYPES).

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

## The types drawn the new way (see the top of this file).
const NEW_TYPES := ["house"]
## Houses in full out to this far from a square's middle (times the tier's
## detail, 0.6 to 1: 360 m on Low, 420 m on Medium, 600 m on High and up);
## past it, their far versions. Leaving takes FULL_MARGIN more.
const FULL_FROM := 600.0
const FULL_MARGIN := 60.0
## Per frame (ms): merging squares of houses, and growing the close-up
## detail (the browser gets less of both).
const MERGE_MS := 3.0
const NEAR_MS := 2.5
## A merged square that changes waits this long to merge again, so a block
## filling in is merged a few times, not once a house.
const REMERGE_MS := 1500
var _homes := {}  # lot key -> {sq, xf, centre, front, look, sign, chain, site}
var _home_sq := {}  # Vector2i -> {lot key: true}, the houses in each 128 m square
var _far_sq := FarSquares.new()
var _near := NearDetail.new()
var _batches := {}  # Vector2i -> BatchSquare: squares drawn in full
var _fill: Array = []  # houses a square drawn in full still waits for, nearest last
var _merge_due := {}  # Vector2i -> msec when it's merged
var _merging := {}  # Vector2i -> true: being merged
var _merge_again := {}  # Vector2i -> true: changed while merging
var _retire := {}  # Vector2i -> [Node3D]: houses just built, drawn on their own until the next merge
var _hidden := {}  # Vector2i -> how far its far versions are hidden (0 to 1)
var _asked := {}  # Vector2i -> true: its houses' arrays are asked for again
var _eye := Vector3.ZERO
var _has_eye := false


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	add_child(_far_sq)
	add_child(_near)
	_near.parts_of = _near_parts
	_near.set_reach(GraphicsQuality.detail, _msaa())
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		_near.budget_ms = NEAR_MS * 0.6
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(func():
			_near.set_reach(GraphicsQuality.detail, _msaa())
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


func _process(delta: float) -> void:
	_look_from()
	if _dirty or not _pending.is_empty() or not _recheck.is_empty() or not _fill.is_empty():
		_sync()
	if not _bake_due.is_empty():
		_bake_some()
	_rings(delta)


## Where the camera is, in this view's frame.
func _look_from() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_has_eye = cam != null
	if _has_eye:
		_eye = to_local(cam.global_position)


func _sync() -> void:
	_look_from()
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
		for key in _nodes.keys() + _homes.keys():
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_unspawn(key)
		var fresh := []
		for key in sim.buildings:
			if not _nodes.has(key) and not _homes.has(key) and sim.lots.has(key):
				fresh.append(key)
		var have := {}
		for key in _pending:
			have[key] = true
		for key in fresh:
			if not have.has(key):
				_pending.append(key)
		_sort_pending()
		if _recheck.is_empty():
			_recheck = _nodes.keys() + _homes.keys()
		else:
			_recheck_again = true
	# Look the rest over for a moved lot (a road widened), a new look or a
	# new sign, a slice at a time.
	while not _recheck.is_empty() and Time.get_ticks_usec() - start < RECHECK_MS * 1000:
		var key: String = _recheck.pop_back()
		if (_nodes.has(key) or _homes.has(key)) and _stale(key):
			_unspawn(key)
			_pending.append(key)
	if _recheck.is_empty() and _recheck_again:
		_recheck_again = false
		_recheck = _nodes.keys() + _homes.keys()
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
			if _nodes.has(key) or _homes.has(key):
				_unspawn(key)
		if _nodes.has(key) or _homes.has(key) or not sim.buildings.has(key) or not sim.lots.has(key):
			continue
		if BuildingTypes.type_of(sim.buildings[key]) in NEW_TYPES:
			_spawn_home(key)
			if Time.get_ticks_usec() - start > budget * 1000:
				break
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
	# Squares that came near enough to draw in full get their houses' full
	# drawings back, nearest first, in what's left of the frame's share.
	while not _fill.is_empty() and Time.get_ticks_usec() - start < budget * 1000:
		var key: String = _fill.pop_back()
		var rec: Dictionary = _homes.get(key, {})
		if rec.is_empty() or rec.site != null or not _batches.has(rec.sq) or _batches[rec.sq].parts.has(key):
			continue
		_spawn_home(key, true)
	if (sliced or _filling) and not _pending.is_empty():
		return
	if _filling:
		_far_sq.rebuild_some(0, true)
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
	for key in _nodes.keys() + _homes.keys():
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
	var b: Dictionary = sim.buildings[key]
	if _homes.has(key):
		var rec: Dictionary = _homes[key]
		return not rec.front.is_equal_approx(sim.lots[key].front) or rec.look != _look(b, key) \
				or rec.sign != sim.families.sign_key(sim, "lot:" + key) or rec.chain != b.get("chain", "")
	var n: Node3D = _nodes[key]
	return not n.get_meta("front").is_equal_approx(sim.lots[key].front) \
			or n.get_meta("look") != _look(b, key) \
			or n.get_meta("sign") != sim.families.sign_key(sim, "lot:" + key) \
			or n.get_meta("chain") != b.get("chain", "")


func _unspawn(key: String) -> void:
	if _homes.has(key):
		_drop_home(key)
		return
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


# ------------------------------------------------------------------ houses
# The new drawing (see the top of this file): far versions everywhere,
# squares near the camera in full, and the close-up ring.

## Draws house `key` (or, `refill`, only fetches its full drawing again for
## a square that came near): builds it with its builder as plain arrays,
## seats it on the land, and files its far version, its trees, and, when
## its square is drawn in full, its full drawing. One still going up is
## drawn on its own, stage by stage, until it's done.
func _spawn_home(key: String, refill := false) -> void:
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	# Placed as _spawn places a building: on the land, graded level with the
	# road at its middle, local -Z facing the street.
	var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP),
		Vector3(lot.front.x, Terrain.base_y(lot.pos.x, lot.pos.z), lot.front.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var fit := _local_lot(lot, xf)
	var s := rng.randi()
	HouseBuilder.owner_care = sim.care.tier_of(key)
	HouseBuilder.restored = sim.heritage.protected(key)
	HouseBuilder.keep_arrays = true
	var built := HouseBuilder.build(s, lot.to_curb, fit, BuildingTypes.storeys(b))
	HouseBuilder.keep_arrays = false
	HouseBuilder.owner_care = 0
	HouseBuilder.restored = false
	var masses: Array = HouseBuilder.last_masses
	var seat := seat_on(masses, xf, Terrain.ground_y)
	xf.origin.y += seat.x
	var solid: Array = built[0].get_meta("parts", [])
	var flat: Array = built[1].get_meta("parts", [])
	var footing := _footing_parts(masses, seat.y)
	var draped := MeshParts.drape(flat, xf)
	if refill:
		var had: Dictionary = _homes[key]
		if _batches.has(had.sq):
			_batches[had.sq].set_building(key, had.xf, solid, draped, footing, [])
			_merge_soon(had.sq)
		return
	var sq := Vector2i(floori(xf.origin.x / FAR_CHUNK), floori(xf.origin.z / FAR_CHUNK))
	# The middle of the house itself, for how near the camera is to it.
	var mid := Vector3.ZERO
	for m: Rect2 in masses:
		mid += Vector3(m.get_center().x, 0.0, m.get_center().y)
	if not masses.is_empty():
		mid /= masses.size()
	var rec := {"sq": sq, "xf": xf, "centre": xf * mid, "front": lot.front, "look": _look(b, key),
		"sign": sim.families.sign_key(sim, "lot:" + key), "chain": b.get("chain", ""), "site": null}
	_homes[key] = rec
	if not _home_sq.has(sq):
		_home_sq[sq] = {}
	_home_sq[sq][key] = true
	# Near enough to draw in full: its square is opened now, so the town
	# opening isn't built twice.
	if not _batches.has(sq) and _has_eye and _square_dist(sq) < _full_from():
		_open_square(sq)
	# Its far version, from the drawing (a house drawn with no masses noted
	# stands as the box of its drawing).
	var bulk := masses
	if bulk.is_empty():
		var box := MeshParts.aabb(solid)
		bulk = [Rect2(box.position.x, box.position.z, box.size.x, box.size.z)]
	var far := far_arrays(_far_surfaces(solid), bulk, false, _wall_colour(int(b.zone), rng),
		_roof_colour(true, rng), flat[0][1] if not flat.is_empty() else [])
	_plant_home(key, xf, built[2])
	var ref := "lot:" + key
	var st: Dictionary = sim.construction.state(ref, sim.tick_count)
	if st.is_empty():
		_home_place(key, solid, draped, footing, far)
		return
	# Going up: drawn on its own, stage by stage, then filed like the rest.
	var root := Node3D.new()
	root.transform = xf
	add_child(root)
	rec.site = root
	var foot: MeshInstance3D = null
	if not footing.is_empty():
		foot = MeshInstance3D.new()
		foot.mesh = MeshParts.to_mesh(footing)
		foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ConstructionSite.add_to(root, [MeshParts.to_mesh(solid), MeshParts.to_mesh(draped), []],
		CitySim.PROFILE_OF_ZONE.get(int(b.zone), "house"), func(): return sim.construction.state(ref, sim.tick_count),
		_home_done.bind(key, root, [solid, draped, footing, far]), foot)


## A house going up is finished: its own drawing goes, and it's filed with
## the rest of its square.
func _home_done(key: String, root: Node3D, drawn: Array) -> void:
	var rec: Dictionary = _homes.get(key, {})
	if rec.is_empty() or rec.site != root:
		return
	rec.site = null
	_home_place(key, drawn[0], drawn[1], drawn[2], drawn[3])
	# Its own drawing stays until its square's next merge shows it.
	if _batches.has(rec.sq):
		if not _retire.has(rec.sq):
			_retire[rec.sq] = []
		_retire[rec.sq].append(root)
	else:
		root.queue_free()


func _home_place(key: String, solid: Array, draped: Array, footing: Array, far: Array) -> void:
	var rec: Dictionary = _homes[key]
	_far_sq.put(key, rec.sq, rec.xf, far)
	if _batches.has(rec.sq):
		_batches[rec.sq].set_building(key, rec.xf, solid, draped, footing, [])
		_merge_soon(rec.sq)
	_near.index(key, rec.centre)


func _drop_home(key: String) -> void:
	var rec: Dictionary = _homes[key]
	_homes.erase(key)
	if _home_sq.has(rec.sq):
		_home_sq[rec.sq].erase(key)
		if _home_sq[rec.sq].is_empty():
			_home_sq.erase(rec.sq)
	if rec.site != null:
		rec.site.queue_free()
	_far_sq.drop(key)
	if _batches.has(rec.sq):
		_batches[rec.sq].remove_building(key)
		# Torn down: it leaves at once. Drawn again (a new look, a regraded
		# lot): the old one shows until the new one is merged in its place.
		_merge_soon(rec.sq, not sim.buildings.has(key) or not sim.lots.has(key))
	_near.unindex(key)
	_trees.remove(key)


## A house's yard and street trees, to the shared tree field (as _plant).
func _plant_home(key: String, frame: Transform3D, planted: Array) -> void:
	var trees := []
	for t in planted:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2]])
	_trees.set_trees(key, trees)


## Merges a square of houses soon: at once the first time, or when a house
## left it (so it doesn't linger); otherwise after REMERGE_MS.
func _merge_soon(sq: Vector2i, now := false) -> void:
	if _merging.has(sq):
		_merge_again[sq] = true
		return
	var at := Time.get_ticks_msec() + (0 if now or not _batches[sq].shown else REMERGE_MS)
	_merge_due[sq] = mini(int(_merge_due.get(sq, at)), at)


## The screen's antialiasing (GraphicsQuality.msaa; 4x when there's no
## autoload, in tests).
static func _msaa() -> int:
	return GraphicsQuality.current.msaa() if GraphicsQuality.current and GraphicsQuality.current.active else 2


static func _full_from() -> float:
	return FULL_FROM * clampf(GraphicsQuality.detail, 0.6, 1.0)


func _square_dist(sq: Vector2i) -> float:
	var mid := Vector3((sq.x + 0.5) * FAR_CHUNK, 0.0, (sq.y + 0.5) * FAR_CHUNK)
	mid.y = minf(_eye.y, Terrain.base_y(mid.x, mid.z))
	return _eye.distance_to(mid)


## The rings, every frame: which squares are drawn in full, their merges
## and dissolves, the far squares, and the close-up detail.
func _rings(delta: float) -> void:
	var t := Perf.now()
	if _has_eye and not _filling:
		var reach := _full_from()
		for sq in _home_sq:
			var d := _square_dist(sq)
			var batch: BatchSquare = _batches.get(sq)
			if d < reach:
				if batch == null:
					_open_square(sq)
				elif batch.target < 1.0:
					batch.target = 1.0
			elif batch != null and d > reach + FULL_MARGIN and batch.target > 0.0:
				_close_square(sq)
	var tm := Perf.now()
	_merge_some()
	Perf.add("frame.buildings_merge", tm)
	for sq in _batches.keys():
		var batch: BatchSquare = _batches[sq]
		if not batch.shown:
			continue
		batch.step_fade(delta)
		if _hidden.get(sq, -1.0) != batch.fade:
			_hidden[sq] = batch.fade
			_far_sq.set_hidden(sq, batch.fade)
		if batch.target <= 0.0 and batch.fade <= 0.0:
			_forget_square(sq)
	if _far_sq.has_dirty():
		_far_sq.rebuild_some(int(MERGE_MS * 300.0))
	if _has_eye:
		var tn := Perf.now()
		_near.update(_eye)
		Perf.add("frame.buildings_near", tn)
	Perf.add("frame.buildings", t)


## A square came near: its houses' full drawings are fetched again, nearest
## the camera first, and merged once they're all in.
func _open_square(sq: Vector2i) -> void:
	var batch := BatchSquare.new(sq, FAR_CHUNK)
	batch.instant = true
	add_child(batch)
	_batches[sq] = batch
	for key in _home_sq.get(sq, {}):
		if _homes[key].site == null:
			_fill.append(key)
	_asked[sq] = true
	_merge_due[sq] = Time.get_ticks_msec()
	_sort_fill()


## A square went far: it dissolves back into its far versions and its full
## drawings are let go.
func _close_square(sq: Vector2i) -> void:
	var batch: BatchSquare = _batches[sq]
	batch.target = 0.0
	for key in _home_sq.get(sq, {}):
		_near.release(key)
	if not batch.shown:
		_forget_square(sq)


func _forget_square(sq: Vector2i) -> void:
	_batches[sq].queue_free()
	_batches.erase(sq)
	_merge_due.erase(sq)
	_merging.erase(sq)
	_merge_again.erase(sq)
	_hidden.erase(sq)
	_asked.erase(sq)
	_far_sq.set_hidden(sq, 0.0)
	for root in _retire.get(sq, []):
		root.queue_free()
	_retire.erase(sq)


## Nearest the camera last, so pop_back takes it first.
func _sort_fill() -> void:
	if not _has_eye:
		return
	_fill.sort_custom(func(a, b):
		var pa: Vector3 = _homes[a].centre if _homes.has(a) else Vector3.INF
		var pb: Vector3 = _homes[b].centre if _homes.has(b) else Vector3.INF
		return _eye.distance_squared_to(pa) > _eye.distance_squared_to(pb))


## Whether a square drawn in full still waits for a house's full drawing
## (its arrays were let go after the last merge, or it's new): any it lacks
## are asked for again.
func _waiting(sq: Vector2i) -> bool:
	var batch: BatchSquare = _batches[sq]
	var missing := []
	for key in _home_sq.get(sq, {}):
		if _homes[key].site == null and not batch.parts.has(key):
			missing.append(key)
	if missing.is_empty():
		_asked.erase(sq)
		return false
	if not _asked.has(sq):
		_asked[sq] = true
		_fill.append_array(missing)
		_sort_fill()
	return true


## Merges squares of houses that are due, one material group a step, within
## MERGE_MS; a square shows what was merged only once it's all merged.
func _merge_some() -> void:
	var start := Time.get_ticks_usec()
	var limit := int(MERGE_MS * 1000.0 * (0.6 if _near.budget_ms < NEAR_MS else 1.0))
	var now := Time.get_ticks_msec()
	for sq in _merge_due.keys():
		if Time.get_ticks_usec() - start > limit:
			return
		if not _batches.has(sq):
			_merge_due.erase(sq)
			continue
		var batch: BatchSquare = _batches[sq]
		if not _merging.has(sq):
			if _merge_due[sq] > now or _waiting(sq):
				continue
			batch.begin()
			_merging[sq] = true
		if not batch.merge_step(start + limit):
			return
		batch.finish()
		batch.drop_parts()
		_merging.erase(sq)
		_merge_due.erase(sq)
		for root in _retire.get(sq, []):
			root.queue_free()
		_retire.erase(sq)
		if _merge_again.has(sq):
			_merge_again.erase(sq)
			_merge_due[sq] = now + REMERGE_MS


## The close-up ring's question: a house's walls and roofs, in its square's
## frame, once its square shows it in full.
func _near_parts(key: String) -> Array:
	var rec: Dictionary = _homes.get(key, {})
	if rec.is_empty() or rec.site != null or not _batches.has(rec.sq):
		return []
	var batch: BatchSquare = _batches[rec.sq]
	if batch.fade < 1.0 or not batch.merged.has(key) or not batch.near.has(key):
		return []
	return [rec.sq, batch.kind_parts(key, ["siding", "brick", "roof"])]


## True when nothing is waiting to be drawn, merged or grown (for tools and
## tests that take pictures).
func idle() -> bool:
	if not _pending.is_empty() or not _bake_due.is_empty() or _filling or not _fill.is_empty():
		return false
	if not _merge_due.is_empty() or not _merging.is_empty() or _far_sq.has_dirty():
		return false
	for sq in _batches:
		if _batches[sq].fade != _batches[sq].target:
			return false
	return _near.caught_up()


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
	var surfaces := []
	for i in mesh.get_surface_count():
		var kind: String = _far_kinds.get(mesh.surface_get_material(i), "")
		if kind != "":
			surfaces.append([kind, mesh.surface_get_arrays(i)])
	var g := []
	if ground != null and ground.get_surface_count() > 0:
		g = ground.surface_get_arrays(0)
	var out_mesh := ArrayMesh.new()
	var arrays := far_arrays(surfaces, masses, industrial, wall, flat, g)
	if not arrays.is_empty():
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out_mesh


## The parts of a drawing its far version keeps (MeshParts: [kind, arrays]).
static func _far_surfaces(parts: Array) -> Array:
	var out := []
	for p in parts:
		var kind := MeshParts.kind(p)
		if kind in FAR_KEEP or kind == "metal":
			out.append([kind, p[1]])
	return out


## far_version as surface arrays (empty when there's nothing to draw), from
## `surfaces` ([kind, arrays] of FAR_KEEP and metal) and `ground` (the flat
## work's arrays, or []).
static func far_arrays(surfaces: Array, masses: Array, industrial: bool, wall: Color, flat: Color,
		ground: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var roofs := PackedVector3Array()
	var sides := PackedVector3Array()
	var most := 0
	for sf in surfaces:
		var kind: String = sf[0]
		if kind == "metal" and not industrial:
			continue
		var a: Array = sf[1]
		if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null:
			continue
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
	if not ground.is_empty():
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
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## The drives, walks and lots of a lot's flat work (the yard shader's kinds
## in vertex alpha: 0 concrete, 0.4 asphalt), a little above the lot so
## they hold on the land however far off.
static func _far_paving(a: Array, verts: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, uvs: PackedVector2Array, index: PackedInt32Array) -> void:
	if a[Mesh.ARRAY_VERTEX] == null:
		return
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


## _footing as MeshParts ([[material, arrays]], or [] with no masses).
func _footing_parts(masses: Array, depth := FOOTING_DEPTH) -> Array:
	var st := _footing_tool(masses, depth)
	var a := st.commit_to_arrays()
	if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return []
	return [[_footing_material(), a]]


static func _footing_material() -> Material:
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	return _footing_mat


## A foundation down into the ground under each building mass, for lots on
## a slope (or null): just under the walls, as a real one is, never a slab
## across the yard; `depth` reaches the lowest ground under them.
func _footing(masses: Array, depth := FOOTING_DEPTH) -> MeshInstance3D:
	if masses.is_empty():
		return null
	var footing := MeshInstance3D.new()
	footing.mesh = _footing_tool(masses, depth).commit()
	if footing.mesh.get_surface_count() == 0:
		return null
	footing.material_override = _footing_material()
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return footing


func _footing_tool(masses: Array, depth: float) -> SurfaceTool:
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
	return st
