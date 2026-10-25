class_name WildView
extends Node3D
## Draws the wild trees and brush (Vegetation) around the camera, using the
## art library's TreeField: one TreeField per 256 m chunk, so a change or a
## step of regrowth redraws only its own chunk. Chunks stream in nearest
## first and drop out behind the camera, so an endless map costs the same as
## a small one. Brush uses the small crabapple crown, squat and dull, until
## Art adds proper shrub meshes.
##
## The sim's woods know four broad kinds (oak, maple, locust, cedar); here
## each tree becomes one of the real Grant County kinds (docs/trees.md) by
## where it stands: sycamore, cottonwood, silver maple and hackberry along
## the creeks and rivers; white and red oak, sugar maple, black walnut,
## hackberry and honey locust on the uplands; red cedar in old fields and
## fencerows. Each tree's age comes from its size, so land growing back
## shows young trees that grow on. Near the camera GrownTrees draws them
## grown branch by branch. WildView also keeps the trees' clock and season.

## How far out wild plants are drawn: further when the camera is higher.
const MIN_RADIUS := 700.0
const MAX_RADIUS := 1600.0
## Brush is only drawn this close; past it, it is too small to see.
const DETAIL_RADIUS := 560.0
## Above this height the wild trees are gone (faded out by then): the
## painted canopy carries the woods.
const TREES_OFF := 1750.0
## Milliseconds a frame may spend laying out new chunks.
const BUDGET_MS := 4
## Land that is growing back is redrawn once a game day (a month of growth).
const REGROW_REDRAW := 24 * 60

var sim: CitySim
var _chunks := {}  # chunk -> TreeField
var _detail := {}  # chunk -> true when drawn with its brush
var _stale := {}  # chunks to redraw
var _shade := []  # fields drawn last frame, whose far trees drop their shadows
var _last_regrow := -1
var _season_at := -1.0
var grown: GrownTrees


func setup(s: CitySim) -> void:
	sim = s
	sim.vegetation.changed.connect(func(chunks: Array):
		for c in chunks:
			_stale[c] = true)
	# The grown trees near the camera, for every TreeField in the scene.
	grown = GrownTrees.new()
	add_child(grown)


## Redraws the chunks in a box (view coordinates): the land there was
## regraded, so verges may have been mowed or let go.
func regraded(box: Rect2) -> void:
	var size := Vegetation.CHUNK
	for x in range(floori(box.position.x / size), floori(box.end.x / size) + 1):
		for z in range(floori(box.position.y / size), floori(box.end.y / size) + 1):
			if _chunks.has(Vector2i(x, z)):
				_stale[Vector2i(x, z)] = true


func _process(_delta: float) -> void:
	if sim == null:
		return
	# Building while paused still clears the trees right away.
	sim.vegetation.update(sim)
	# The trees' clock (planted trees grow by it) and each kind's season.
	TreeField.now_tick = sim.tick_count
	var months := Seasons.months(sim.tick_count)
	if absf(months - _season_at) > 0.01:
		_season_at = months
		TreeLook.set_season(months, DayNight.seasons_on)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var height := maxf(cam.global_position.y - Terrain.ground_y(cam.global_position.x, cam.global_position.z), 1.0)
	# Lower graphics tiers draw the woods and their brush less far (the
	# tier's woods share: GraphicsQuality.BUDGETS); the ground's painted
	# canopy carries on past them.
	var woods := float(GraphicsQuality.knob("woods", 1.0))
	var radius := reach(height) * woods
	var brush := DETAIL_RADIUS * woods
	var focus := _ground_focus(cam, radius)
	# Trees thin out and shrink toward the edge (TreeField's shader), where
	# the ground's painted canopy takes over.
	# w is the camera's height: from high up the trees fade out and the
	# ground's painted canopy covers the woods (TreeField and TerrainView).
	RenderingServer.global_shader_parameter_set("tree_fade", Vector4(focus.x, focus.y, radius, height))
	# From high up the trees are faded out, but their chunks stay built
	# (hidden) around the spot the camera looks at, which is where a zoom
	# lands, so zooming back in fast finds them ready instead of popping in.
	visible = height <= TREES_OFF
	if not visible:
		radius = reach(TREES_OFF) * woods
		focus = _look_spot(cam, height)
	var size := Vegetation.CHUNK
	var day := sim.tick_count / REGROW_REDRAW
	if day != _last_regrow:
		_last_regrow = day
		for c in _chunks:
			if sim.vegetation.growing_in(c, sim.tick_count):
				_stale[c] = true
	# Drop chunks well behind the edge (with some slack so they don't flicker).
	for c in _chunks.keys():
		if _centre(c).distance_to(focus) > radius + size * 1.5:
			_chunks[c].queue_free()
			_chunks.erase(c)
			_detail.erase(c)
			_stale.erase(c)
	var todo := []
	var lo := Vector2i(floori((focus.x - radius) / size), floori((focus.y - radius) / size))
	var hi := Vector2i(floori((focus.x + radius) / size), floori((focus.y + radius) / size))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			var d := _centre(c).distance_to(focus)
			if d > radius + size * 0.7:
				continue
			var near := d < brush
			if not _chunks.has(c) or _stale.has(c) or (near and not _detail.has(c)) or (d > brush + size and _detail.has(c)):
				todo.append(c)
	todo.sort_custom(func(a, b): return _centre(a).distance_squared_to(focus) < _centre(b).distance_squared_to(focus))
	# Distant trees are a few big cards: their shadows would cost more than
	# they show, so only the near trees cast them.
	for field in _shade:
		if is_instance_valid(field):
			for mmi in field.get_children():
				if mmi is GeometryInstance3D and mmi.visibility_range_begin > 0.0:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shade.clear()
	# The tier's share of each frame for laying out chunks.
	var grow_ms := float(GraphicsQuality.knob("grow_ms", BUDGET_MS))
	var start := Time.get_ticks_msec()
	for c in todo:
		_draw_chunk(c, _centre(c).distance_to(focus) < brush)
		if Time.get_ticks_msec() - start > grow_ms:
			break


## Lays out one chunk now.
func _draw_chunk(c: Vector2i, detail: bool) -> void:
	_stale.erase(c)
	if detail:
		_detail[c] = true
	else:
		_detail.erase(c)
	var size := Vegetation.CHUNK
	var plants := sim.vegetation.plants_in(Rect2(Vector2(c) * size, Vector2(size, size)), sim.tick_count, detail)
	if not _chunks.has(c):
		var field := TreeField.new()
		field.fades = true
		add_child(field)
		_chunks[c] = field
	# Roads the town doesn't own (a neighbor's, the county highways out to
	# the horizon) keep their mowed verges clear too.
	var mowed := Terrain.any_mowed(Rect2(Vector2(c) * size, Vector2(size, size)))
	var trees := []
	var o := Terrain.view_origin
	var in_town := Backdrop.overlaps(Rect2(Vector2(c) * size + Vector2(o.x, o.y), Vector2(size, size)))
	var yards := FarmsteadPlan.solids_in(Rect2(Vector2(c) * size + Vector2(o.x, o.y), Vector2(size, size)))
	var wet := wet_lattice(c)
	for p in plants:
		if mowed and Terrain.mow_weight(p.pos.x, p.pos.z) > 0.5:
			continue
		# Nor on a county farmstead's buildings and gravel (FarmsteadPlan).
		if not yards.is_empty() and FarmsteadPlan.on_solid(yards, Vector2(p.pos.x + o.x, p.pos.z + o.y)):
			continue
		# Nor on the county roads out in the country (in town, lots win)...
		if CountyGrid.clears(p.pos.x + o.x, p.pos.z + o.y, CountyGrid.TREE_CLEAR) \
				and Terrain.flat_weight(p.pos.x, p.pos.z) < 0.5:
			continue
		# ...nor on the state highways, in town or out (no lots are platted
		# on them).
		if Highways.clears(p.pos.x + o.x, p.pos.z + o.y, Highways.TREE_CLEAR):
			continue
		# ...nor inside Marion and the other backdrop towns, whose streets
		# and buildings BackdropView draws.
		if in_town and Backdrop.inside(Vector2(p.pos.x + o.x, p.pos.z + o.y)):
			continue
		trees.append(facts(p, bottomland(wet, p.pos)))
	_chunks[c].set_trees("wild", trees)
	_shade.append(_chunks[c])


## A wild plant as TreeField draws it: [placement, kind, tint, facts]. The
## sim's broad kind becomes a real Grant County kind by where it stands in
## the region (the same spot always the same kind, for every player), and
## its age comes from its size.
static func facts(p: Dictionary, on_bottomland: bool) -> Array:
	var xf := placement(p)
	if p.kind == Vegetation.Kind.SHRUB:
		return [xf, p.species, p.tint, {"shrub": true}]
	var sp := grant_county_kind(p.species, TreeField.region_of(p.pos), on_bottomland)
	# Keep the plant's own lighter or darker shade on its kind's green.
	var was: Color = TreeField.LEAF[p.species]
	var green: Color = TreeField.LEAF[sp]
	var shade: float = (p.tint as Color).v / maxf(was.v, 0.01)
	var tint := Color(green.r * shade, green.g * shade, green.b * shade)
	return [xf, sp, tint, {"age": snappedf(TreeKinds.age_for_size(sp, p.size), 0.01)}]


## Which real kind a wild tree is, from where it stands in the region.
## Bottomlands (by creeks and rivers): sycamore, silver maple, cottonwood,
## hackberry. Uplands: oaks split white and red; maples are mostly sugar
## maple with hackberry and black walnut; the sim's locusts are honey
## locust, black walnut and hackberry; cedars are eastern red cedar.
static func grant_county_kind(broad: int, region: Vector2, on_bottomland: bool) -> int:
	# Rounded to the metre: two players' positions for one tree can differ
	# in their last digits.
	var h := Resources.hash01(Vector2i(roundi(region.x), roundi(region.y)), 977)
	if broad == TreeField.Species.SPRUCE:
		return TreeField.Species.RED_CEDAR
	if on_bottomland:
		if h < 0.3:
			return TreeField.Species.SYCAMORE
		if h < 0.6:
			return TreeField.Species.SILVER_MAPLE
		return TreeField.Species.COTTONWOOD if h < 0.8 else TreeField.Species.HACKBERRY
	match broad:
		TreeField.Species.OAK:
			return TreeField.Species.OAK if h < 0.5 else TreeField.Species.RED_OAK
		TreeField.Species.MAPLE:
			if h < 0.6:
				return TreeField.Species.MAPLE
			return TreeField.Species.HACKBERRY if h < 0.8 else TreeField.Species.WALNUT
		TreeField.Species.LOCUST:
			if h < 0.45:
				return TreeField.Species.LOCUST
			return TreeField.Species.WALNUT if h < 0.75 else TreeField.Species.HACKBERRY
	return broad


const WET_STEP := 32.0


## Where water is, on a 32 m lattice laid on the region (the same lattice
## for every player) over a chunk of the view and a few cells beyond, so
## each tree can ask whether it stands on a bottomland cheaply.
static func wet_lattice(c: Vector2i) -> Dictionary:
	var out := {}
	var o := Terrain.view_origin
	var size := Vegetation.CHUNK
	var lo := Vector2i(floori((c.x * size + o.x) / WET_STEP) - 2, floori((c.y * size + o.y) / WET_STEP) - 2)
	var hi := Vector2i(floori(((c.x + 1) * size + o.x) / WET_STEP) + 3, floori(((c.y + 1) * size + o.y) / WET_STEP) + 3)
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			if Terrain.water(i * WET_STEP, j * WET_STEP) > 0.05:
				out[Vector2i(i, j)] = true
	return out


## On a bottomland: water within about 50 m of a view position.
static func bottomland(wet: Dictionary, view_pos: Vector3) -> bool:
	if wet.is_empty():
		return false
	var r := TreeField.region_of(view_pos)
	var cell := Vector2i(floori(r.x / WET_STEP), floori(r.y / WET_STEP))
	for dx in range(-1, 3):
		for dz in range(-1, 3):
			if wet.has(cell + Vector2i(dx, dz)):
				return true
	return false


## How far out wild plants are drawn for a camera this high.
static func reach(height: float) -> float:
	return clampf(height * 3.0, MIN_RADIUS, MAX_RADIUS)


## Where and how big a plant is drawn: standing on the land.
static func placement(p: Dictionary) -> Transform3D:
	var pos: Vector3 = p.pos
	pos.y += Terrain.ground_y(pos.x, pos.z)
	var s: float = p.size
	var shape := Vector3.ONE * s
	if p.kind == Vegetation.Kind.SHRUB:
		shape = Vector3(0.6, 0.45, 0.6) * s
	# Turned by where it stands in the region, so every player sees it the
	# same way round.
	var r := TreeField.region_of(pos)
	var yaw := fposmod(roundf(r.x) * 7.3 + roundf(r.y) * 3.1, TAU)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(shape), pos)


func _centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * Vegetation.CHUNK


## Where the camera's line of sight meets the ground (roughly).
func _look_spot(cam: Camera3D, height: float) -> Vector2:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y > -0.05:
		return _ground_focus(cam, reach(TREES_OFF))
	return Vector2(from.x, from.z) + Vector2(dir.x, dir.z) * (height / -dir.y)


## The centre of the trees drawn: from the camera toward where it looks, but
## never more than part of the reach ahead, so a low, flat view doesn't
## swing it far off (and reload everything) with each small move.
func _ground_focus(cam: Camera3D, radius: float) -> Vector2:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.001:
		return Vector2(from.x, from.z)
	var height := maxf(from.y - Terrain.ground_y(from.x, from.z), 1.0)
	var ahead := radius * 0.45
	if dir.y < -0.05:
		ahead = minf(height / -dir.y * flat.length(), ahead)
	return Vector2(from.x, from.z) + flat.normalized() * ahead
