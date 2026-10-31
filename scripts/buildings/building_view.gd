class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes), CommercialBuilder (shops), FactoryBuilder
## (factories, one design per industry chain) and
## DenseBuilder (row homes, apartments, Main Street blocks, offices). Each
## building is drawn for its type and stage, and redrawn when it grows. New
## ones go up stage by stage (ConstructionSite).
##
## Drawn the new way (docs/scale-test-2026-10-25.md, "The new drawing style,
## measured"): every building grown from its facts (lot, kind, age, seed) by
## its builder, and kept and drawn in three rings round the camera:
##   far     every building's far version (its walls, roofs and windows as
##           drawn, in their real colours, without trim, porches and the
##           rest, as Anno 1800's far models keep each building's outline,
##           roof and colours; about a hundred triangles), merged for each
##           256 m square (FarSquares). Far off, that's all that's kept.
##   middle  within FULL_FROM, each 128 m square's buildings in full, merged
##           into one mesh per material (BatchSquare): a town of a few
##           hundred homes drawn one by one was thousands of draw calls, most
##           of the frame on a Mac. It replaces the far versions once it's
##           all merged; past the ring the full drawings are let go, so
##           memory follows the camera, not the size of the town.
##   near    within about 100 m, brick by brick, lap by lap and course by
##           course over each building's own walls and roofs (NearDetail),
##           grown a few small jobs a frame.
## How far each ring reaches follows the graphics tier (GraphicsQuality).
## Buildings still going up draw on their own until they're done.

var sim: CitySim
var _trees := TreeField.new()
static var _footing_mat: Material

const FAR_CHUNK := 128.0
## The parts of a close-up drawing its far version keeps: walls, roofs and
## windows (and a factory's metal cladding). Everything else is small.
const FAR_KEEP := ["siding", "brick", "roof", "membrane", "glass"]
static var _far_kinds := {}  # Material -> its HouseMaterials name

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
## then the rest FILL_MS a frame while you play (far versions once it's all in).
const LOAD_MS := 1500
const FILL_MS := 8
## Behind the loading screen (LoadGate): milliseconds a frame, so the bar still moves.
const LOAD_BOOST_MS := 150.0
## The loading screen waits for buildings this near the camera (metres): the
## ground out to where far boxes take over (FAR_FROM).
const LOAD_RANGE := 900.0
var _filling := false
## A neighbor's whole town lands at once, while you play: drawn a few
## buildings a frame even then, its far versions once it's all in (RegionView).
var sliced := false

## Buildings in full out to this far from a square's middle (times the tier's
## detail, 0.6 to 1: 360 m on Low, 420 m on Medium, 600 m on High and up:
## past about 700 m a house is a few pixels tall even on a 5K screen, and
## drawing every one in full there swamped a Mac Studio); past it, their far
## versions. Leaving takes FULL_MARGIN more (hysteresis: without it, a square
## right at the swap distance flickered between its close-up and far
## versions while the camera eased or zoomed, Brawn's apartment block,
## 2026-10-24).
const FULL_FROM := 600.0
const FULL_MARGIN := 60.0
## Per frame (ms): merging squares, and growing the close-up detail (the
## browser gets less of both).
const MERGE_MS := 3.0
const NEAR_MS := 2.5
## A merged square that changes waits this long to merge again, so a block
## filling in is merged a few times, not once a building.
const REMERGE_MS := 1500
var _recs := {}  # lot key -> {sq, xf, centre, front, look, sign, chain, site}
var _by_sq := {}  # Vector2i -> {lot key: true}, the buildings in each 128 m square
var _far_sq := FarSquares.new()
var _near := NearDetail.new()
## A finished building was filed (drawn and in place), or one was let go
## (torn down, or about to be drawn again): for the views that follow
## buildings one at a time (StateView).
signal building_placed(key: String)
signal building_removed(key: String)
var _batches := {}  # Vector2i -> BatchSquare: squares drawn in full
var _fill: Array = []  # buildings a square drawn in full still waits for, nearest last
## The queue wants sorting before the next fill (sorted once a frame, not
## once per square opened: review, 2026-10-25, a jump opening many squares
## sorted it again and again).
var _fill_unsorted := false
var _merge_due := {}  # Vector2i -> msec when it's merged
var _merging := {}  # Vector2i -> true: being merged
var _merge_again := {}  # Vector2i -> true: changed while merging
var _retire := {}  # Vector2i -> [Node3D]: just built, drawn on their own until the next merge
var _retire_far := {}  # Node3D -> Vector2i: just built in a far square, drawn on their own until it merges
var _hidden := {}  # Vector2i -> how far its far versions are hidden (0 to 1)
var _asked := {}  # Vector2i -> true: its buildings' arrays are asked for again
var _eye := Vector3.ZERO
var _has_eye := false
## The game sets this: until its camera exists nothing is drawn in full (a
## test or tool with no camera at all draws everything in full). Review,
## 2026-10-25: the view came up before the camera and opened every square.
var wait_for_eye := false
## Share of the full-drawing reach inside which squares keep their arrays.
const KEEP_PARTS := 0.5


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
		GraphicsQuality.current.changed.connect(func(): _near.set_reach(GraphicsQuality.detail, _msaa()))
	sim.buildings_changed.connect(_mark)
	sim.lots_changed.connect(_mark)
	# A business renamed, bought or with a new look gets new signs.
	sim.families.changed.connect(_mark)
	_dirty = true
	_sync()


func _mark() -> void:
	_dirty = true


## True once nothing near the camera waits to be drawn or merged (the
## loading screen waits for this; LoadGate). Far squares keep filling in.
func is_drawn() -> bool:
	return not _dirty and _recheck.is_empty() and _pending.is_empty() and not _filling \
		and _fill.is_empty() and _merge_due.is_empty() and _merging.is_empty()


func _process(delta: float) -> void:
	_look_from()
	_check_parkways()
	if not _refilter.is_empty():
		_refilter_some()
	if _dirty or not _pending.is_empty() or not _recheck.is_empty() or not _fill.is_empty():
		_sync()
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
		for key in _recs.keys():
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_unspawn(key)
		var fresh := []
		for key in sim.buildings:
			if not _recs.has(key) and sim.lots.has(key):
				fresh.append(key)
		var have := {}
		for key in _pending:
			have[key] = true
		for key in fresh:
			if not have.has(key):
				_pending.append(key)
		_sort_pending()
		if _recheck.is_empty():
			_recheck = _recs.keys()
		else:
			_recheck_again = true
	# Look the rest over for a moved lot (a road widened), a new look or a
	# new sign, a slice at a time.
	while not _recheck.is_empty() and Time.get_ticks_usec() - start < LoadGate.ms(RECHECK_MS) * 1000:
		var key: String = _recheck.pop_back()
		if _recs.has(key) and _stale(key):
			_unspawn(key)
			_pending.append(key)
	if _recheck.is_empty() and _recheck_again:
		_recheck_again = false
		_recheck = _recs.keys()
	# Build nearest first until the frame's share is used. A town opening (or
	# any big batch) gets LOAD_MS now, nearest the camera first, and the rest
	# FILL_MS a frame after.
	var budget := FILL_MS if _filling else SPAWN_MS
	if not sliced and not _filling and not _pending.is_empty() and (_first or _pending.size() > SPAWN_ALL):
		_first = false
		_filling = true
		budget = LOAD_MS
	# Behind the loading screen: a bigger share each frame, so the bar moves.
	if LoadGate.loading:
		budget = int(LoadGate.ms(0.0, LOAD_BOOST_MS))
	while not _pending.is_empty():
		var key: String = _pending.pop_back()
		# Swapped in the same frame, so it never blinks out.
		if _regraded.has(key):
			_regraded.erase(key)
			if _recs.has(key):
				_unspawn(key)
		if _recs.has(key) or not sim.buildings.has(key) or not sim.lots.has(key):
			continue
		_spawn(key)
		if Time.get_ticks_usec() - start > budget * 1000:
			break
	# Squares that came near enough to draw in full get their buildings' full
	# drawings back, nearest first, in what's left of the frame's share.
	if _fill_unsorted:
		_sort_fill_now()
	while not _fill.is_empty() and Time.get_ticks_usec() - start < budget * 1000:
		var key: String = _fill.pop_back()
		var rec: Dictionary = _recs.get(key, {})
		if rec.is_empty() or rec.site != null or not _batches.has(rec.sq) or _batches[rec.sq].parts.has(key):
			continue
		_spawn(key, true)
	if (sliced or _filling) and not _pending.is_empty():
		return
	if _filling:
		_far_sq.rebuild_some(0, true)
	_filling = false


## The ground was regraded inside `box` (view coordinates, a new road's
## strip): buildings with lots reaching into it are drawn again, so their
## walls, drives and parking sit on the graded pad instead of the land as it
## was (Brawn 2026-10-24: lots and drives half under the grass).
func regraded(box: Rect2) -> void:
	var near := box.grow(LOT_REACH)
	var any := false
	for key in _recs:
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
	var rec: Dictionary = _recs[key]
	return not rec.front.is_equal_approx(sim.lots[key].front) or rec.look != _look(b, key) \
			or rec.sign != sim.families.sign_key(sim, "lot:" + key) or rec.chain != b.get("chain", "")


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
		sim.heritage.protected(key), int(b.get("added_from", 0))]


## The building on lot `key` as its builder draws it, as plain arrays
## (HouseBuilder.keep_arrays): [walls and roofs, flat work, trees, labels,
## the doors it logged (DoorLog)].
func _draw(key: String, lot: Dictionary, b: Dictionary, fit: Dictionary, s: int) -> Array:
	var spec := sim.families.sign_of(sim, "lot:" + key)
	var storeys := BuildingTypes.storeys(b)
	HouseBuilder.owner_care = sim.care.tier_of(key)
	HouseBuilder.restored = sim.heritage.protected(key)
	if b.has("added_from"):
		fit = fit.duplicate()
		fit.added_from = int(b.added_from)  # floors added on top of a block this tall
	HouseBuilder.keep_arrays = true
	HouseBuilder.flat_weeds = not LawnMap.paints(sim)
	var box := []  # (a lambda can't set the caller's variable)
	var doors := DoorLog.collect(func(): box.append(build_for(BuildingTypes.type_of(b), storeys, s, lot.to_curb, fit, spec,
		int(b.get("units", 2)), b.get("chain", "general"), int(b.get("level", 0)))))
	var built: Array = box[0]
	HouseBuilder.keep_arrays = false
	HouseBuilder.flat_weeds = true
	HouseBuilder.owner_care = 0
	HouseBuilder.restored = false
	if built.size() < 2:
		return []
	return [built[0].get_meta("parts", []), built[1].get_meta("parts", []), built[2] if built.size() > 2 else [],
		built[3] if built.size() > 3 else [], doors]


## The doors the builder of the shop or plant on lot `key` draws (DoorLog:
## factory bays, stockroom roll-ups; in the lot's frame), from a dry run of
## the very builder this view draws it with, as _draw hands it the lot: what
## doors_of keeps from the drawing itself. For tests and tools.
static func doors_drawn(sim: CitySim, key: String) -> Array:
	if not sim.lots.has(key) or not sim.buildings.has(key):
		return []
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var fit := fit_for(sim, key, xf)
	if b.has("added_from"):
		fit.added_from = int(b.added_from)
	var keep := [HouseBuilder.last_masses, HouseBuilder.last_info, HouseBuilder.keep_arrays, HouseBuilder.owner_care,
		HouseBuilder.restored]
	HouseBuilder.owner_care = sim.care.tier_of(key)
	HouseBuilder.restored = sim.heritage.protected(key)
	HouseBuilder.dry_all = true
	var spec := sim.families.sign_of(sim, "lot:" + key)
	var out := DoorLog.collect(func(): build_for(BuildingTypes.type_of(b), BuildingTypes.storeys(b), rng.randi(), lot.to_curb,
		fit, spec, int(b.get("units", 2)), b.get("chain", "general"), int(b.get("level", 0))))
	HouseBuilder.dry_all = false
	HouseBuilder.last_masses = keep[0]
	HouseBuilder.last_info = keep[1]
	HouseBuilder.keep_arrays = keep[2]
	HouseBuilder.owner_care = keep[3]
	HouseBuilder.restored = keep[4]
	return out


## The doors the building on lot `key` was drawn with (_draw; a shop's or a
## plant's, never a home's, whose garages its plan carries), or [].
func doors_of(key: String) -> Array:
	return _recs.get(key, {}).get("doors", [])


## What a type's builder draws for a stage of `storeys` on lot `fit` (the
## game's own pick, shared with tools/growth_strip.gd).
static func build_for(type: String, storeys: int, s: int, to_curb: float, fit: Dictionary, spec := {}, units := 2, chain := "general", level := 0) -> Array:
	var built := []
	match type:
		"house":
			# Its third stage has built on out back (Home with addition).
			HouseBuilder.grown = maxi(0, level - 1)
			built = HouseBuilder.build(s, to_curb, fit, storeys)
			HouseBuilder.grown = 0
		"duplex": built = DuplexBuilder.build(s, to_curb, fit, level)
		"row_home": built = MetroBuilder.build_row(s, to_curb, fit, units, storeys)
		"apartments":
			# A high-rise is a tower like the offices (860-880 Lake Shore
			# Drive is apartments).
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, to_curb, fit, storeys, {}, "", true)
			else:
				built = MetroBuilder.build_apartments(s, to_curb, fit, storeys)
		"shop": built = DenseBuilder.build_retail(s, to_curb, fit, spec, level)
		"shopping_center":
			# A neighborhood center (the second stage) has a grocer anchor, a
			# community center (the third) a discount store too, a power
			# center (the fourth) a home improvement store and junior boxes.
			CommercialBuilder.force_shop = ["strip", "center", "community", "power"][clampi(level, 0, 3)]
			built = DenseBuilder.build_retail(s, to_curb, fit, spec)
			CommercialBuilder.force_shop = ""
		"mixed_use":
			# On a corner, an old corner store that grew a storey of flats.
			built = CornerStore.build_grown(s, to_curb, fit, storeys, spec)
			if built.is_empty():
				built = DenseBuilder.build_mixed(s, to_curb, fit, storeys, spec)
		"commercial_block": built = MainBlock.build(s, to_curb, fit, storeys, spec)
		"office_park": built = DenseBuilder.build_office_park(s, to_curb, fit, level, spec)
		"hotel": built = HotelBuilder.build(s, to_curb, fit, level, spec)
		"office":
			# Eight storeys and up is a downtown tower, built for its era.
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, to_curb, fit, storeys, spec)
			else:
				built = DenseBuilder.build_office(s, to_curb, fit, storeys, spec)
		_: built = FactoryBuilder.build_chain(chain, s, to_curb, fit, spec)
	return built


## The lot `key` as its builder is handed it (frame `xf`): _local_lot, a
## corner shop's side street, a row's back lane, and a corner house's drive
## kept away from the corner (SiteLayout.drive_away) with its street trees
## off the mailbox beside that drive (CurbClaims.mailbox_at). Shared with
## tools/overlap_audit.gd.
func fit_of(key: String, xf: Transform3D) -> Dictionary:
	return fit_for(sim, key, xf)


static func fit_for(sim: CitySim, key: String, xf: Transform3D) -> Dictionary:
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	var type := BuildingTypes.type_of(b)
	var fit := _local_lot(lot, xf)
	if fit.corner and int(b.zone) == ZoneMap.Zone.COMMERCIAL:
		fit.side = SiteLayout.corner_side(sim.network, lot)
	if type in ["row_home", "apartments"]:
		fit.alley = SiteLayout.back_lane(sim.network, lot)
	var away := SiteLayout.drive_away(sim, key)
	if away != 0.0:
		fit.drive_away = away
	if type == "house" and int(b.get("built", 0)) >= sim.curb_drives_from:
		# Where the box goes by its own drive alone (its neighbours come and
		# go; the trees must not move with them). A town saved before keeps
		# its street trees where they grew.
		var box := CurbClaims.of(sim).mailbox_at(key, true)
		if box.is_finite():
			fit.mail_x = (xf.affine_inverse() * Vector3(box.x, xf.origin.y, box.y)).x
	return fit


## What the builder of the shop, office, plant or flats on lot `key` paves
## across the parkway to the curb (HouseBuilder.cuts_drawn: [x0, x1, curb z,
## flare] each, lot frame), from a dry run of the very builder this view
## draws it with, on the lot as it is handed to it (fit_for) and from the
## building's own seed: the lot's plan, never its drawing (CurbClaims).
static func curb_paving(sim: CitySim, key: String) -> Array:
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var fit := fit_for(sim, key, xf)
	if b.has("added_from"):
		fit.added_from = int(b.added_from)
	var keep := [HouseBuilder.last_masses, HouseBuilder.last_info, HouseBuilder.keep_arrays, HouseBuilder.owner_care,
		HouseBuilder.restored, HouseBuilder.cuts_drawn]
	HouseBuilder.cuts_drawn = []
	HouseBuilder.dry_all = true
	build_for(BuildingTypes.type_of(b), BuildingTypes.storeys(b), rng.randi(), lot.to_curb, fit, {}, int(b.get("units", 2)),
		b.get("chain", "general"), int(b.get("level", 0)))
	HouseBuilder.dry_all = false
	var out: Array = HouseBuilder.cuts_drawn
	HouseBuilder.last_masses = keep[0]
	HouseBuilder.last_info = keep[1]
	HouseBuilder.keep_arrays = keep[2]
	HouseBuilder.owner_care = keep[3]
	HouseBuilder.restored = keep[4]
	HouseBuilder.cuts_drawn = keep[5]
	return out


## Draws building `key` (or, `refill`, only fetches its full drawing again
## for a square that came near): has its builder draw it as plain arrays,
## seats it on the land, and files its far version, its trees, and, when
## its square is drawn in full, its full drawing. One still going up is
## drawn on its own, stage by stage, until it's done.
func _spawn(key: String, refill := false) -> void:
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	# On the land: the lot is graded level with the road at its middle.
	# Local -Z faces the street, +Z runs back into the lot.
	var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP),
		Vector3(lot.front.x, Terrain.base_y(lot.pos.x, lot.pos.z), lot.front.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var fit := fit_of(key, xf)
	HouseBuilder.last_info = {}
	var drawn := _draw(key, lot, b, fit, rng.randi())
	if drawn.is_empty():
		return
	var masses: Array = HouseBuilder.last_masses
	# A house's plan as drawn (its walk and all), for the yard props.
	var plan: Dictionary = HouseBuilder.last_info.duplicate() if BuildingTypes.type_of(b) == "house" else {}
	# On a hillside a building stands on the highest ground under its walls,
	# with a walkout foundation down to the low side: never with the hill
	# coming up through the floor (Brawn's homes built through a forest).
	var seat := seat_on(masses, xf, Terrain.ground_y)
	xf.origin.y += seat.x
	var solid: Array = drawn[0]
	var flat: Array = drawn[1]
	var footing := _footing_parts(masses, seat.y)
	# Drives, walks and beds lie on the ground, following it.
	var draped := MeshParts.drape(flat, xf)
	var labels: Array = drawn[3]
	if refill:
		var had: Dictionary = _recs[key]
		if not masses.is_empty():
			had.masses = masses.duplicate()
		had.plan = plan
		had.erase("doors")
		if not drawn[4].is_empty() and int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
			had.doors = drawn[4]
		if _batches.has(had.sq):
			_batches[had.sq].set_building(key, had.xf, solid, draped, footing, labels)
			_merge_soon(had.sq)
		return
	var sq := Vector2i(floori(xf.origin.x / FAR_CHUNK), floori(xf.origin.z / FAR_CHUNK))
	# The middle of the building itself, for how near the camera is to it.
	var mid := Vector3.ZERO
	for m: Rect2 in masses:
		mid += Vector3(m.get_center().x, 0.0, m.get_center().y)
	if not masses.is_empty():
		mid /= masses.size()
	var rec := {"sq": sq, "xf": xf, "centre": xf * mid, "front": lot.front, "look": _look(b, key),
		"sign": sim.families.sign_key(sim, "lot:" + key), "chain": b.get("chain", ""), "site": null}
	_recs[key] = rec
	if not _by_sq.has(sq):
		_by_sq[sq] = {}
	_by_sq[sq][key] = true
	# Near enough to draw in full: its square is opened now, so the town
	# opening isn't built twice.
	if not _batches.has(sq) and (not _has_eye and not wait_for_eye or _has_eye and _square_dist(sq) < _full_from()):
		_open_square(sq)
	# Its far version, from the drawing (a building drawn with no masses
	# noted stands as the box of its drawing).
	var bulk := masses
	if bulk.is_empty():
		var box := MeshParts.aabb(solid)
		bulk = [Rect2(box.position.x, box.position.z, box.size.x, box.size.z)]
	rec.masses = bulk.duplicate()  # its footprints, for the yard props (StateView)
	rec.plan = plan
	if not drawn[4].is_empty() and int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
		rec.doors = drawn[4]  # (never in the browser: DoorLog.collect)
	var pitched: bool = BuildingTypes.type_of(b) in ["house", "duplex", "row_home"]
	var far := far_arrays(_far_surfaces(solid), bulk, int(b.zone) == ZoneMap.Zone.INDUSTRIAL,
		_wall_colour(int(b.zone), rng), _roof_colour(pitched, rng), flat[0][1] if not flat.is_empty() else [])
	var parts := [solid, draped, footing, far, drawn[2], labels]
	var ref := "lot:" + key
	if sim.construction.state(ref, sim.tick_count).is_empty():
		_place(key, parts)
		return
	# Going up: drawn on its own, stage by stage; then filed like the rest,
	# its trees and the sign's lettering going in once it's done.
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
		str(sim.construction.sites[ref].profile), func(): return sim.construction.state(ref, sim.tick_count),
		_site_done.bind(key, root, parts), foot)


## A building going up is finished: it's filed with the rest of its square,
## its own drawing staying until the square's next merge shows it.
func _site_done(key: String, root: Node3D, parts: Array) -> void:
	var rec: Dictionary = _recs.get(key, {})
	if rec.is_empty() or rec.site != root:
		return
	rec.site = null
	_place(key, parts)
	if _batches.has(rec.sq):
		if not _retire.has(rec.sq):
			_retire[rec.sq] = []
		_retire[rec.sq].append(root)
	else:
		# Far away: its own drawing stays until the far square it joined is
		# merged again (a few seconds at most), so it never blinks out.
		_retire_far[root] = rec.sq


## Files a finished building: its far version, its trees, and its full
## drawing when its square is drawn in full. `parts`: [walls and roofs, flat
## work laid on the land, footing, far version, trees, labels].
func _place(key: String, parts: Array) -> void:
	var rec: Dictionary = _recs[key]
	_far_sq.put(key, rec.sq, rec.xf, parts[3])
	_plant(key, rec.xf, parts[4])
	if _batches.has(rec.sq):
		_batches[rec.sq].set_building(key, rec.xf, parts[0], parts[1], parts[2], parts[5])
		_merge_soon(rec.sq)
	_near.index(key, rec.centre)
	building_placed.emit(key)


func _unspawn(key: String) -> void:
	var rec: Dictionary = _recs[key]
	_recs.erase(key)
	building_removed.emit(key)
	if _by_sq.has(rec.sq):
		_by_sq[rec.sq].erase(key)
		if _by_sq[rec.sq].is_empty():
			_by_sq.erase(rec.sq)
	if rec.site != null:
		rec.site.queue_free()
	_far_sq.drop(key)
	if _batches.has(rec.sq):
		_batches[rec.sq].remove_building(key)
		# Torn down, or going up again behind scaffolding: it leaves at once
		# (review, 2026-10-25: the old house showed through the scaffold).
		# Drawn again otherwise (a new look, a regraded lot): the old one
		# shows until the new one is merged in its place.
		_merge_soon(rec.sq, not sim.buildings.has(key) or not sim.lots.has(key)
			or sim.construction.sites.has("lot:" + key))
	_near.unindex(key)
	_trees.remove(key)
	_planted.erase(key)
	_kept.erase(key)
	street_trees -= int(_street_of.get(key, 0))
	_street_of.erase(key)


## Trees go to the shared tree field, placed in world space on the ground.
func _plant(key: String, frame: Transform3D, planted: Array) -> void:
	_check_parkways()
	_planted[key] = [frame, planted]
	_set_trees(key)


## Files a lot's trees in the tree field: those its builder planted, less
## street trees that stand where the town keeps the parkway clear. Only
## when they changed, unless `always`.
func _set_trees(key: String, always := true) -> int:
	var frame: Transform3D = _planted[key][0]
	var planted: Array = _planted[key][1]
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	var trees := []
	var street := 0
	# Yard trees go in as nursery stock when the building is finished and
	# grow with the game's years (TreeField, TreeKinds): the planting date is
	# the building's own build date, so nothing new is saved.
	var b: Dictionary = sim.buildings.get(key, {})
	var when := {"planted": int(b.get("built", sim.tick_count)) + Construction.duration(
		CitySim.profile_of(b))}
	# A home's own yard trees come in grown, at mixed ages from the lot's seed
	# (TreeField.yard_age), unless the building was begun before this came
	# in (a town saved before keeps its trees as they were:
	# CitySim.grown_yards_from).
	# Street trees are the town's and go in as nursery stock.
	var grown := int(b.get("built", sim.tick_count)) >= sim.grown_yards_from
	var lot_seed := int(b.get("seed", hash(key)))
	# The mailbox by the lot's own drive (where it stands is worked out from
	# the neighbours' drives too, which come and go; the trees must not).
	var mailbox := CurbClaims.of(sim).mailbox_at(key, true)
	# Which trees stand (by number), to tell whether anything changed.
	var kept := PackedInt32Array()
	for i in planted.size():
		var t: Array = planted[i]
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		var facts := when
		if t[0].z < -0.5:
			# Out past the lot line: a tree in the parkway.
			var q := Vector2(at.origin.x, at.origin.z)
			if not _parkway_free(q) or q.distance_to(mailbox) < MAILBOX_CLEAR:
				continue
			street += 1
		elif grown and t.size() > 4:
			# A home's yard tree, with its room to spread (HouseBuilder._yard_room).
			# Shops', factories', civic and apartment lots' trees go in as
			# nursery stock, as before.
			facts = {"planted": when.planted, "start": TreeField.yard_age(t[1], hash([lot_seed, i]), float(t[4]))}
		kept.append(i)
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2], facts])
	var side := _side_trees(key)
	for i in side.size():
		var q: Vector2 = side[i][0]
		if not _parkway_free(q):
			continue
		kept.append(1000 + i)
		var yaw := Basis(Vector3.UP, fposmod(q.x * 7.3 + q.y * 3.1, TAU))
		trees.append([Transform3D(yaw.scaled(Vector3.ONE * float(side[i][3])), Vector3(q.x, Terrain.ground_y(q.x, q.y), q.y)),
			side[i][1], side[i][2], when])
		street += 1
	Terrain.shift = was
	if not always and _kept.get(key) == kept:
		return trees.size()
	_kept[key] = kept
	street_trees += street - int(_street_of.get(key, 0))
	_street_of[key] = street
	_trees.set_trees(key, trees)
	return trees.size()


# ------------------------------------------------------- parkway keep-clear

## Street trees kept back from a junction's centre by this much more than
## the widest road there's half width: about 30 ft back from where the curb
## lines meet, the sight triangle Indiana towns keep clear of trees so a
## driver at the stop sign sees down the cross street (INDOT and the usual
## municipal code).
const SIGHT_CLEAR := 10.5
## And this far from a streetlight's pole (so the lamp isn't buried in the
## crown), a bus stop's sign and shelter, and the mailbox at the curb.
const LAMP_CLEAR := 5.0
const STOP_CLEAR := 6.0
const MAILBOX_CLEAR := 1.6
const CLEAR_CELL := 32.0

## Street trees standing in the parkways now (for the tools and tests).
var street_trees := 0
var _street_of := {}  # lot key -> street trees it has now
var _planted := {}  # lot key -> [frame, trees as its builder planted them]
var _clear_stamp := []
var _clear := {}  # Vector2i cell -> [[Vector2 centre, radius], ...]
var _pieces := {}  # the roads in short straight pieces (StreetLights._pieces), for side streets
var _kept := {}  # lot key -> which of its trees stand (see _set_trees)
var _refilter: Array = []  # lots still to look over since the keep-clear spots changed
## Milliseconds a frame may spend looking lots' street trees over again.
const REFILTER_MS := 1.0


## What the parkway's keep-clear spots are worked out from: the roads and
## the bus stops, and the corners' curb ramps and crosswalks (CurbClaims).
func _parkway_stamp() -> Array:
	var stops = sim.get("buses")
	return [sim.network.revision, sim.network.segments.size(), stops.stops.size() if stops != null else 0,
		CurbClaims.of(sim).junction_version]


## Works the keep-clear spots out again when the roads or the bus stops
## changed, and takes back (or plants again) the street trees they touch.
func _check_parkways() -> void:
	var stamp := _parkway_stamp()
	if stamp == _clear_stamp:
		return
	_clear_stamp = stamp
	_clear.clear()
	var net: RoadNetwork = sim.network
	_pieces = StreetLights._pieces(net)
	for n in net.nodes:
		var segs := net.segments_at(n)
		if segs.size() < 2 or (segs.size() == 2 and _straight_through(net, n, segs)):
			continue
		var hw := 0.0
		for id in segs:
			hw = maxf(hw, RoadStyle.half_width(net.segments[id].type))
		var p: Vector3 = net.nodes[n]
		_keep_clear(Vector2(p.x, p.z), hw + SIGHT_CLEAR)
	for l in StreetLights.place(net):
		_keep_clear(Vector2(l[1].x, l[1].z), LAMP_CLEAR)
	var stops = sim.get("buses")
	if stops != null:
		for sid in stops.stops:
			var st: Dictionary = stops.stops[sid]
			if st.has("pos"):
				var along: Vector3 = st.dir
				var out: Vector3 = Vector3(-along.z, 0.0, along.x) * float(st.side)
				var base: Vector3 = st.pos + out * (RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
				_keep_clear(Vector2(base.x, base.z), STOP_CLEAR)
	# Each lot's street trees looked over again, a slice a frame.
	_refilter = _planted.keys()


## Looks a slice of the lots' street trees over again (see _check_parkways).
func _refilter_some() -> void:
	var start := Time.get_ticks_usec()
	while not _refilter.is_empty() and Time.get_ticks_usec() - start < REFILTER_MS * 1000.0:
		var key: String = _refilter.pop_back()
		if _planted.has(key):
			_set_trees(key, false)


## A corner lot's street trees down its side street: along the lot line it
## shares with the second street it fronts, in that street's parkway, about
## every STREET_TREE_GAP, as the town plants both frontages of a corner
## (HouseBuilder._street_trees plants the front). Its own random numbers.
## Each: [Vector2 where (this view's frame), species, tint, size].
func _side_trees(key: String) -> Array:
	var lot: Dictionary = sim.lots.get(key, {})
	var b: Dictionary = sim.buildings.get(key, {})
	if not lot.get("corner", false) or lot.get("flag", false) or int(b.get("zone", -1)) != ZoneMap.Zone.RESIDENTIAL:
		return []
	var poly: PackedVector2Array = lot.get("corners", PackedVector2Array())
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, "side street trees"])
	for side in _straight_sides(poly):
		var a: Vector2 = side[0]
		var e: Vector2 = side[1] - a
		var length := e.length()
		if length < 8.0:
			continue
		var street := _street_beside(a + e * 0.5, e / length, int(lot.get("seg", -1)))
		if street.is_empty():
			continue
		var n := maxi(1, roundi(length / HouseBuilder.STREET_TREE_GAP))
		for k in n:
			# Every draw made whether or not the tree is planted.
			var p := a + e * ((k + 0.5) / n) + e / length * rng.randf_range(-0.8, 0.8)
			var planted := rng.randf() < HouseBuilder.STREET_TREE_ODDS
			var pick := TreeField.pick_street(rng)
			var size := rng.randf_range(0.8, 1.1)
			var c := _nearest_on(p, int(street[0]))
			if not planted or not c.is_finite() or c.distance_to(p) < 1.0:
				continue
			out.append([c + (p - c).normalized() * (float(street[1]) + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5),
				pick[0], pick[1], size])
	return out


## A lot outline's straight sides, [from, to] each: its edges run together
## where they carry straight on (outlines come in short pieces).
static func _straight_sides(poly: PackedVector2Array) -> Array:
	var n := poly.size()
	if n < 3:
		return []
	# Start at a corner, so no side is split where the outline starts.
	var start := 0
	for i in n:
		var d0 := (poly[i] - poly[(i - 1 + n) % n]).normalized()
		var d1 := (poly[(i + 1) % n] - poly[i]).normalized()
		if d0.dot(d1) < 0.995:
			start = i
			break
	var sides := []
	var a := poly[start]
	var dir := Vector2.ZERO
	for k in range(1, n + 1):
		var p := poly[(start + k) % n]
		var prev := poly[(start + k - 1) % n]
		var d := (p - prev).normalized()
		if dir != Vector2.ZERO and d.dot(dir) < 0.995:
			sides.append([a, prev])
			a = prev
		dir = (p - a).normalized()
	sides.append([a, poly[start]])
	return sides


## The street with a parkway whose lot line runs along a lot's edge at
## `mid` (heading `along`), other than the lot's own street: [its segment,
## half width], or [].
func _street_beside(mid: Vector2, along: Vector2, own: int) -> Array:
	var c := Vector2i(floori(mid.x / StreetLights.PIECE_CELL), floori(mid.y / StreetLights.PIECE_CELL))
	var best := []
	var best_off := 1.5
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for piece in _pieces.get(c + Vector2i(dx, dz), []):
				if piece[2] == own or not sim.network.segments.has(piece[2]):
					continue
				var type: int = sim.network.segments[piece[2]].type
				var to_curb := RoadStyle.right_of_way_half(type) - RoadStyle.half_width(type)
				if to_curb < RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH - 0.05:
					continue  # no parkway: a country road, a freeway
				var pa: Vector2 = piece[0]
				var pb: Vector2 = piece[1]
				if pa.distance_to(pb) < 0.5 or absf((pb - pa).normalized().dot(along)) < 0.97:
					continue
				var q := Geometry2D.get_closest_point_to_segment(mid, pa, pb)
				# The lot line is 0.3 m behind the back of the sidewalk (LotPlanner).
				var off := absf(q.distance_to(mid) - RoadStyle.right_of_way_half(type) - 0.3)
				if off < best_off:
					best_off = off
					best = [int(piece[2]), float(piece[3])]
	return best


## The nearest point to `p` on segment `id`'s centre line (near by).
func _nearest_on(p: Vector2, id: int) -> Vector2:
	var c := Vector2i(floori(p.x / StreetLights.PIECE_CELL), floori(p.y / StreetLights.PIECE_CELL))
	var best := Vector2.INF
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for piece in _pieces.get(c + Vector2i(dx, dz), []):
				if piece[2] == id:
					var q := Geometry2D.get_closest_point_to_segment(p, piece[0], piece[1])
					if q.distance_to(p) < best.distance_to(p):
						best = q
	return best


## True when two roads meet at a node running straight on (one street
## drawn in two pieces), not turning a corner.
static func _straight_through(net: RoadNetwork, n: int, segs: Array) -> bool:
	var c: Vector3 = net.nodes[n]
	var dirs := []
	for id in segs:
		var sg: Dictionary = net.segments[id]
		var ctrl: Vector3 = sg.ctrl
		var to: Vector3 = ctrl if ctrl.distance_to(c) > 0.5 else net.nodes[sg.b if sg.a == n else sg.a]
		dirs.append(Vector2(to.x - c.x, to.z - c.z).normalized())
	return dirs[0].dot(dirs[1]) < -0.97


func _keep_clear(p: Vector2, r: float) -> void:
	var lo := Vector2i(floori((p.x - r) / CLEAR_CELL), floori((p.y - r) / CLEAR_CELL))
	var hi := Vector2i(floori((p.x + r) / CLEAR_CELL), floori((p.y + r) / CLEAR_CELL))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			if not _clear.has(c):
				_clear[c] = []
			_clear[c].append([p, r])


## True when a street tree may stand at `q` (this view's frame): clear of
## the keep-clear spots, and its trunk off the corners' curb ramps and
## crosswalks (CurbClaims).
func _parkway_free(q: Vector2) -> bool:
	for e in _clear.get(Vector2i(floori(q.x / CLEAR_CELL), floori(q.y / CLEAR_CELL)), []):
		if q.distance_to(e[0]) < e[1]:
			return false
	return CurbClaims.of(sim).junction_free(q, CurbClaims.TRUNK_HALF)


## Where a home's curbside mailbox stands (CurbClaims.mailbox_at, as
## MailView draws it), or far off.
func _mailbox_at(key: String) -> Vector2:
	return CurbClaims.of(sim).mailbox_at(key)


## Merges a square soon: at once the first time, or when a building
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
	# The ground is read where the square really lies: a neighbour's town is
	# drawn moved over to its place on the land.
	var shift := Terrain.shift_for(self)
	mid.y = minf(_eye.y, Terrain.base_y(mid.x + shift.x, mid.z + shift.y))
	return _eye.distance_to(mid)


## The rings, every frame: which squares are drawn in full, their merges
## and dissolves, the far squares, and the close-up detail.
func _rings(delta: float) -> void:
	var t := Perf.now()
	if not _filling and (_has_eye or not wait_for_eye):
		# With no camera (a test, a tool), everything is drawn in full.
		var reach := _full_from() if _has_eye else INF
		for sq in _by_sq:
			var d := _square_dist(sq) if _has_eye else 0.0
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
	for root in _retire_far.keys():
		if not is_instance_valid(root) or not _far_sq.is_dirty(_retire_far[root]):
			if is_instance_valid(root):
				root.queue_free()
			_retire_far.erase(root)
	if _has_eye:
		var tn := Perf.now()
		_near.update(_eye)
		Perf.add("frame.buildings_near", tn)
	Perf.add("frame.buildings", t)


## A square came near: its buildings' full drawings are fetched again, nearest
## the camera first, and merged once they're all in.
func _open_square(sq: Vector2i) -> void:
	var batch := BatchSquare.new(sq, FAR_CHUNK)
	batch.instant = true
	add_child(batch)
	_batches[sq] = batch
	for key in _by_sq.get(sq, {}):
		if _recs[key].site == null:
			_fill.append(key)
	_asked[sq] = true
	_merge_due[sq] = Time.get_ticks_msec()
	_sort_fill()


## A square went far: it dissolves back into its far versions and its full
## drawings are let go.
func _close_square(sq: Vector2i) -> void:
	var batch: BatchSquare = _batches[sq]
	batch.target = 0.0
	for key in _by_sq.get(sq, {}):
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
	_fill_unsorted = true


func _sort_fill_now() -> void:
	_fill_unsorted = false
	if not _has_eye:
		return
	_fill.sort_custom(func(a, b):
		var pa: Vector3 = _recs[a].centre if _recs.has(a) else Vector3.INF
		var pb: Vector3 = _recs[b].centre if _recs.has(b) else Vector3.INF
		return _eye.distance_squared_to(pa) > _eye.distance_squared_to(pb))


## Whether a square drawn in full still waits for a building's full drawing
## (its arrays were let go after the last merge, or it's new): any it lacks
## are asked for again.
func _waiting(sq: Vector2i) -> bool:
	var batch: BatchSquare = _batches[sq]
	var missing := []
	for key in _by_sq.get(sq, {}):
		if _recs[key].site == null and not batch.parts.has(key):
			missing.append(key)
	if missing.is_empty():
		_asked.erase(sq)
		return false
	if not _asked.has(sq):
		_asked[sq] = true
		_fill.append_array(missing)
		_sort_fill()
	return true


## Merges squares of buildings that are due, one material group a step, within
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
		# Squares close to the camera keep their buildings' arrays, so a
		# house built or changed there merges again without every neighbour
		# being drawn over (review, 2026-10-25); farther ones let them go.
		if not _has_eye or _square_dist(sq) > _full_from() * KEEP_PARTS:
			batch.drop_parts()
		_merging.erase(sq)
		_merge_due.erase(sq)
		for root in _retire.get(sq, []):
			root.queue_free()
		_retire.erase(sq)
		if _merge_again.has(sq):
			_merge_again.erase(sq)
			_merge_due[sq] = now + REMERGE_MS


## The close-up ring's question: a building's walls and roofs, in its square's
## frame, once its square shows it in full.
func _near_parts(key: String) -> Array:
	var rec: Dictionary = _recs.get(key, {})
	if rec.is_empty() or rec.site != null or not _batches.has(rec.sq):
		return []
	var batch: BatchSquare = _batches[rec.sq]
	if batch.fade < 1.0 or not batch.merged.has(key) or not batch.near.has(key):
		return []
	return [rec.sq, batch.kind_parts(key, ["siding", "brick", "roof"])]


## Where building `key` is drawn on the land (its lot's frame, seated on
## the ground), or null before it is drawn (DoorView puts its doors there).
func lot_xf(key: String) -> Variant:
	var rec: Dictionary = _recs.get(key, {})
	return rec.xf if not rec.is_empty() else null

## A building's footprints as drawn (Rect2s in its lot's frame: x across,
## z back from the street edge), or [] before it is drawn.
func masses_of(key: String) -> Array:
	return _recs.get(key, {}).get("masses", [])


## The trees a lot's builder planted, in the world: [[position, species,
## size, room to spread or -1 (a street tree or a non-home's)], ...].
func trees_of(key: String) -> Array:
	if not _planted.has(key):
		return []
	var frame: Transform3D = _planted[key][0]
	var out := []
	for t: Array in _planted[key][1]:
		out.append([frame * (t[0] as Vector3), int(t[1]), float(t[3]), float(t[4]) if t.size() > 4 else -1.0])
	return out


## The buildings finished and in place (for a view set up after some were).
func placed_keys() -> Array:
	return _recs.keys().filter(func(k): return _recs[k].site == null)


## A house's plan as its builder drew it (HouseBuilder.last_info: drive,
## garage, door, porch, front walk), or {} for anything else.
func plan_of(key: String) -> Dictionary:
	return _recs.get(key, {}).get("plan", {})


## True when nothing is waiting to be drawn, merged or grown (for tools and
## tests that take pictures).
func idle() -> bool:
	if not _pending.is_empty() or _filling or not _fill.is_empty() or not _refilter.is_empty():
		return false
	if not _merge_due.is_empty() or not _merging.is_empty() or _far_sq.has_dirty():
		return false
	for sq in _batches:
		if _batches[sq].fade != _batches[sq].target:
			return false
	return _near.caught_up()


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
	# The curbside mailbox (MailView), so street trees keep off it.
	var n: Vector3 = lot.get("normal", Vector3.BACK)
	var mail: Vector3 = lot.get("front", frame.origin) - n * maxf(float(lot.get("to_curb", 4.0)) - 0.5, 0.3) \
		+ (lot.get("dir", Vector3.RIGHT) as Vector3) * float(lot.get("width", 15.0)) * 0.3
	fit.mail_x = (frame.affine_inverse() * Vector3(mail.x, frame.origin.y, mail.z)).x
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
## a slope, as MeshParts ([[material, arrays]], or [] with no masses): just
## under the walls, as a real one is, never a slab across the yard; `depth`
## reaches the lowest ground under them.
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
