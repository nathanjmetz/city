class_name StateView
extends Node3D
## Draws the state layer's yard props (LotState) on the lots near the
## camera: the cars on blocks, overflowing carts and dumpsters, couches at
## the curb and "FOR LEASE" banners where the town has let a street slip;
## flower beds, porch flags and shop planters where it is kept up
## (docs/spec-state-layer.md, step 1).
##
## Desktop only (the browser draws none of it): within the graphics tier's
## state_m of the camera (GraphicsQuality: 150 m from High up, a lighter
## 100 m with no shadows on Medium, none on Low), each prop dissolving out
## over the last 20 m (StateMats) so the ring's edge never pops. One
## MultiMesh per kind of prop for the whole ring (eight draw calls, and the
## shadows of the two biggest). Each frame does one small job: looks round
## the ring, refills the MultiMeshes, or places a few lots' props (nearest
## first, within PLACE_MS, working out at most one new yard plan, at the
## frame's start), so no frame carries more than about a millisecond. Lots
## are filed in its grid one at a time as BuildingView finishes drawing a
## building or lets one go (building_placed / building_removed), the way
## NearDetail is kept, never by going over the whole town.
##
## Drawn only, never in the town's thinking: what stands on a lot comes
## from its condition and seeds alone (LotState), so every copy of the
## town shows the same yards, and nothing is saved.

## Kinds of prop, each one MultiMesh. The car is drawn in the cars' own
## material, the rest in the town's plain paint.
const KINDS := ["car_blocks", "cans", "couch", "dumpster", "lease", "beds", "flag", "planters"]
## Kinds that throw a shadow (the two biggest), from High up: each one costs
## a draw call per shadow split it falls in.
const SHADOWS := ["car_blocks", "dumpster"]
const GRID := 64.0
## Seconds between looks round the ring with a still camera.
const LOOK_EVERY := 0.5
## Most ms a frame may spend placing lots' props.
const PLACE_MS := 0.4
## A new yard plan is only worked out this early in a frame (ms): it is the
## costly step (a shop's site plan, read from its builder), so it never
## lands on top of other work.
const YARD_BY_MS := 0.05
## Seconds between checks of every lot in the ring for a change (a new
## condition, trash piling up or picked up), when nothing says so sooner.
const RECHECK := 3.0
## Most seconds the MultiMeshes wait for the queue to empty before they are
## refilled anyway (so the nearest props show while the rest are placed).
const REFILL_WAIT := 0.3
## Yard plans kept for lots that left the ring (so panning back costs nothing).
const YARDS_KEPT := 3000
## The dissolve at the ring's edge, metres.
const FADE := 20.0

var sim: CitySim
## The buildings' view, for each building's footprints as drawn.
var buildings: BuildingView
## How far props are drawn (0: none).
var reach := 0.0

var _mm := {}           # kind -> MultiMeshInstance3D
var _grid := {}         # Vector2i -> {key: Vector3 (the lot on the land)}
var _filed := {}        # key -> its cell in _grid
## Lots filed in and dropped from the grid so far (for tests).
var filed_count := 0
var dropped_count := 0
var _lots := {}         # key -> {"sig", "props": [[kind, Transform3D, Color]]}
var _yards := {}        # key -> [sig, yard] (the yard plan, which needs the drawing)
var _want := {}         # key -> distance, the lots in the ring
var _queue := []        # keys to place, nearest first
var _dirty := false
var _look := 0.0
var _last_eye := Vector3.INF
var _bloom := true
var _place_ms_max := 0.0
var _job_max := {}
var _stale := true      # every lot in the ring to be checked at the next look
var _recheck := 0.0
var _unfilled := 0.0    # seconds the MultiMeshes have been out of date


func setup(s: CitySim, view: BuildingView) -> void:
	sim = s
	buildings = view
	# Any change may be a new condition or trash piling up: the lots in the
	# ring are checked at the next look.
	sim.buildings_changed.connect(func(): _stale = true)
	if view != null:
		view.building_placed.connect(_file)
		view.building_removed.connect(_unfile)
		for key in view.placed_keys():
			_file(key)


func _ready() -> void:
	_set_reach()
	if GraphicsQuality.current != null:
		GraphicsQuality.current.changed.connect(_set_reach)


## The MultiMeshes, made the first time a tier draws props (never on Low).
func _make_meshes() -> void:
	for kind in KINDS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = StateMeshes.of(kind)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = StateMats.car() if kind == "car_blocks" else StateMats.props()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_mm[kind] = mi


## How far the props reach on this tier and device.
static func reach_for(on_browser: bool, knob: float) -> float:
	return 0.0 if on_browser else knob


func _set_reach() -> void:
	reach = reach_for(OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility",
		float(GraphicsQuality.knob("state_m", 0.0)))
	if reach > 0.0 and _mm.is_empty():
		_make_meshes()
	var shadows := reach > 120.0
	for kind in _mm:
		_mm[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and kind in SHADOWS \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _mm.is_empty():
		StateMats.set_reach(maxf(reach - FADE, 0.0), maxf(reach, 1.0), _bloom)
	_last_eye = Vector3.INF
	if reach <= 0.0:
		_lots.clear()
		_queue.clear()
		_want.clear()
		_dirty = true


## True when every lot in the ring has its props placed (tools wait on it).
func idle() -> bool:
	return reach <= 0.0 or (_queue.is_empty() and not _dirty and _last_eye != Vector3.INF)


## Instances drawn of each kind (for tests and tools).
func counts() -> Dictionary:
	var out := {}
	for kind in KINDS:
		out[kind] = 0
	for kind in _mm:
		out[kind] = _mm[kind].multimesh.instance_count
	return out


## The slowest frame's work so far, ms (for the cost check).
func place_ms_max() -> float:
	return _place_ms_max


## The slowest frame of each job so far, ms: {index, look, refill, place}.
func job_ms_max() -> Dictionary:
	return _job_max


func _process(delta: float) -> void:
	if sim == null:
		return
	if reach <= 0.0:
		if _dirty:
			_rebuild()
		return
	var t := Time.get_ticks_usec()
	var job := _job(delta, t)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_place_ms_max = maxf(_place_ms_max, ms)
	_job_max[job] = maxf(float(_job_max.get(job, 0.0)), ms)
	Perf.add("frame.state", t)


## This frame's one job; returns its name.
func _job(delta: float, t: int) -> String:
	_look -= delta
	_recheck -= delta
	if _dirty:
		_unfilled += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null and not _grid.is_empty():
		var eye := to_local(cam.global_position)
		if eye.distance_to(_last_eye) > 4.0 or _look <= 0.0:
			_look = LOOK_EVERY
			_last_eye = eye
			if _recheck <= 0.0:
				_recheck = RECHECK
				_stale = true
			_ring(eye)
			return "look"
	if _dirty and (_queue.is_empty() or _unfilled > REFILL_WAIT):
		_rebuild()
		return "refill"
	if not _queue.is_empty():
		_place(t)
		return "place"
	return "idle"


## Files a drawn building's lot in the grid (BuildingView.building_placed).
func _file(key: String) -> void:
	if not sim.lots.has(key) or not sim.buildings.has(key) or LotState.kind_of(sim.buildings[key]) == "":
		return
	var p: Vector3 = sim.lots[key].pos
	var c := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	if not _grid.has(c):
		_grid[c] = {}
	_grid[c][key] = Vector3(p.x, Terrain.base_y(p.x, p.z), p.z)
	_filed[key] = c
	filed_count += 1
	_look = minf(_look, 0.1)  # look round again soon


## Drops a lot whose building was let go (BuildingView.building_removed).
func _unfile(key: String) -> void:
	if not _filed.has(key):
		return
	var c: Vector2i = _filed[key]
	_filed.erase(key)
	if _grid.has(c):
		_grid[c].erase(key)
		if _grid[c].is_empty():
			_grid.erase(c)
	_yards.erase(key)
	dropped_count += 1
	_look = minf(_look, 0.1)


## Which lots are in the ring, and which of them need their props placed
## again (their building, condition or street's trash changed).
func _ring(eye: Vector3) -> void:
	var bloom := _in_bloom()
	if bloom != _bloom:
		_bloom = bloom
		StateMats.set_reach(maxf(reach - FADE, 0.0), reach, _bloom)
	var r := reach + 10.0
	_want = {}
	var c0 := Vector2i(floori(eye.x / GRID), floori(eye.z / GRID))
	var n := int(ceil(r / GRID))
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var cell: Dictionary = _grid.get(c0 + Vector2i(dx, dz), {})
			for key in cell:
				var d := eye.distance_to(cell[key])
				if d < r and sim.buildings.has(key) and sim.lots.has(key):
					_want[key] = d
	for key in _lots.keys():
		if not _want.has(key):
			_lots.erase(key)
			_dirty = true
	if _yards.size() > YARDS_KEPT:
		for key in _yards.keys():
			if not _want.has(key):
				_yards.erase(key)
	_queue.clear()
	for key in _want:
		if not _lots.has(key) or _stale and _lots[key].sig != _sig(key):
			_queue.append(key)
	_stale = false
	_queue.sort_custom(func(a, b): return _want[a] < _want[b])


## What a lot's props depend on.
func _sig(key: String) -> Array:
	var b: Dictionary = sim.buildings[key]
	return [int(b.seed), BuildingTypes.type_of(b), int(b.get("level", 0)), sim.care.tier_of(key),
		sim.care.cond_of(key), _piled(key), sim.construction.is_done("lot:" + key, sim.tick_count)]


func _piled(key: String) -> bool:
	return float(sim.hubs.trash.get(int(sim.lots[key].seg), 0.0)) >= Balance.GARBAGE_PILE_LB


## Annuals bloom from May to the first frost in October.
func _in_bloom() -> bool:
	var m := DayNight.visible_month(sim)
	return m >= 5 and m <= 10


## Places queued lots' props, nearest first, until PLACE_MS is spent. A
## lot whose yard plan isn't worked out yet waits for the start of a frame.
func _place(t0: int) -> void:
	var limit := int(PLACE_MS * 1000.0)
	var skipped := []
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < limit:
		var key: String = _queue.pop_front()
		if not sim.buildings.has(key) or not sim.lots.has(key):
			continue
		var sig := _sig(key)
		if not sig[6]:
			# Still going up: a building site has no yard yet.
			_lots[key] = {"sig": sig, "props": []}
			_dirty = true
			continue
		var masses: Array = buildings.masses_of(key) if buildings != null else []
		if masses.is_empty() and buildings != null:
			skipped.append(key)  # not drawn yet: try again at the next look
			continue
		var plan: Dictionary = buildings.plan_of(key) if buildings != null else {}
		var ysig := [sig[0], sig[1], sig[2], masses.hash(), plan.hash()]
		var yard: Dictionary
		if _yards.has(key) and _yards[key][0] == ysig:
			yard = _yards[key][1]
		else:
			if Time.get_ticks_usec() - t0 > int(YARD_BY_MS * 1000.0):
				_queue.push_front(key)
				break
			yard = LotState.yard_of(sim, key, masses, plan)
			_yards[key] = [ysig, yard]
		var b: Dictionary = sim.buildings[key]
		var items := LotState.items(sim.city_seed, key, int(b.seed), int(sig[3]), float(sig[4]), yard, bool(sig[5]))
		_lots[key] = {"sig": sig, "props": _world(sim.lots[key], items)}
		_dirty = true
	if not skipped.is_empty():
		_look = minf(_look, 0.25)


## A lot's items in the world: [kind, transform, custom data].
static func _world(lot: Dictionary, items: Array) -> Array:
	var frame := SiteLayout.frame(lot)
	var out := []
	for it in items:
		var at: Vector2 = it.at
		var p := frame * Vector3(at.x, 0.0, at.y)
		p = Terrain.stand(p) + Vector3(0.0, float(it.y), 0.0)
		var basis := frame.basis * Basis(Vector3.UP, float(it.yaw))
		var col: Color = it.col
		var flags := 0.0
		if it.item == "car_blocks":
			flags = 4.0  # parked, engine off: no lamps lit (VehicleMaterial)
		elif it.item == "couch":
			flags = float(int(it.v) & 1)
		out.append([String(it.item), Transform3D(basis, p), Color(col.r, col.g, col.b, flags)])
	return out


## Every kind's MultiMesh refilled from the lots in the ring.
func _rebuild() -> void:
	_dirty = false
	_unfilled = 0.0
	if _mm.is_empty():
		return
	var bufs := {}
	var counts := {}
	for kind in KINDS:
		bufs[kind] = PackedFloat32Array()
		counts[kind] = 0
	for key in _lots:
		for pr in _lots[key].props:
			var x: Transform3D = pr[1]
			var c: Color = pr[2]
			var b := x.basis
			var o := x.origin
			bufs[pr[0]].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
				c.r, c.g, c.b, c.a])
			counts[pr[0]] += 1
	for kind in KINDS:
		var mm: MultiMesh = _mm[kind].multimesh
		mm.instance_count = counts[kind]
		if counts[kind] > 0:
			mm.buffer = bufs[kind]
		_mm[kind].visible = counts[kind] > 0
