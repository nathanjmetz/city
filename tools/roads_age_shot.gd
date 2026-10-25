extends SceneTree
## Roads that age and get repaired, in a real game window: pictures of a new
## street, a 10-year one, a 25-year one, a repaired one, an avenue, a chip
## seal county road, a gravel road, a paved county road and a concrete
## freeway, each close (30 m) and at play height (300 m), in July and in
## early March (potholes); and the cost (frame time and memory, new look
## against the old one).
## Run (a real window):
##   godot -s tools/roads_age_shot.gd -- --shots DIR
##   godot --disable-vsync -s tools/roads_age_shot.gd -- --ab [--town big]
## Add --rendering-method gl_compatibility for the browser's renderer.
## --ab switches back and forth (10 times, 90 frames each) between the new
## road materials and the old ones (Surfaces) over the test town, and
## reports the median frame of each: other programs on the machine slow both
## halves alike, so the difference is the cost.

const GAP := 90.0
const X0 := 400.0
const LEN := 400.0
## [name, road type, years since paved or resurfaced]
const ROADS := [
	["new", RoadStyle.Type.STREET, 0.12],
	["10yr", RoadStyle.Type.STREET, 10.0],
	["25yr", RoadStyle.Type.STREET, 24.8],
	["repaired", RoadStyle.Type.STREET, 17.3],
	["avenue", RoadStyle.Type.AVENUE, 14.0],
	["chipseal", RoadStyle.Type.CHIP_SEAL, 3.4],
	["gravel", RoadStyle.Type.GRAVEL, 8.0],
	["county", RoadStyle.Type.COUNTY, 16.0],
	["freeway", RoadStyle.Type.FREEWAY2, 20.0],
]

var _main: Node
var _cam: CityCamera
var _view: RoadView
var _frames := 0
var _jobs := []  # [frame, Callable]
var _out := ""
var _last_us := 0
var _ab := false
var _half := {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
var _gpu := {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
var _mem := {"new": [], "old": []}
var _rows := []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _arg(name: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_setup()
	for j in _jobs.duplicate():
		if j[0] == _frames:
			j[1].call()
			_jobs.erase(j)
	return false


## Year 30, the given month (0 = January), at 11 in the morning.
func _date(month: float) -> int:
	return int((29.0 * 12.0 + month - Seasons.START_MONTH + 11.0 / 24.0) * Seasons.TICKS_PER_DAY)


func _setup() -> void:
	var sim: CitySim = _main.sim
	_main.set_speed(0)
	DayNight.cycle_on = false
	# After a run that didn't close cleanly the game starts safe at Low; the
	# pictures want the tier asked for (not saved: the player's choice stays).
	var q := GraphicsQuality.current
	var want := ["low", "medium", "high", "ultra", "cinematic"].find(_arg("--quality", "high"))
	if q != null and q.active and want >= 0 and not q.browser:
		q.tier = want
		q.apply()
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Hud:
			c.close_all()
	_view = _main.find_children("*", "RoadView", true, false)[0]
	_ab = OS.get_cmdline_user_args().has("--ab")
	_out = _arg("--shots", "")
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.tick_count = _date(6.5)
	if _ab:
		_setup_ab(sim)
		return
	var ids := {}
	for i in ROADS.size():
		var x := X0 + i * GAP
		var before := sim.network.segments.keys()
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -LEN * 0.5], "end": [x, -LEN],
			"road": ROADS[i][1]})
		for id in sim.network.segments:
			if not id in before:
				ids[id] = i
	sim.street_age.month(sim)
	var year := 12 * Seasons.TICKS_PER_DAY
	for id in ids:
		var age: float = ROADS[ids[id]][2]
		if not sim.network.segments.has(id):
			continue
		if not sim.street_age._cells.has(id):
			sim.street_age._measure(sim, id)
		for k in sim.street_age._cells[id]:
			sim.street_age.paved[k] = sim.tick_count - int(age * year)
		_view._town_ever[id] = true
	_view.rebuild()
	# A few cars down the gravel road, for its dust.
	var gx: float = X0 + ROADS.map(func(r): return r[0]).find("gravel") * GAP
	var f := 40
	for when in [["july", 6.5], ["march", 2.1]]:
		_jobs.append([f, func(): sim.tick_count = _date(when[1])])
		f += 20
		for i in ROADS.size():
			var name: String = ROADS[i][0]
			if when[0] == "march" and not name in ["25yr", "repaired", "avenue", "county", "gravel", "freeway"]:
				continue
			if _arg("--only", name) != name:
				continue
			var x := X0 + i * GAP
			_jobs.append([f, func(): _close(Vector3(x, 0, -170), 30.0)])
			_jobs.append([f + 25, func(): _save("%s_%s_close.png" % [when[0], name])])
			_jobs.append([f + 26, func(): _close(Vector3(x, 0, -200), 300.0)])
			_jobs.append([f + 50, func(): _save("%s_%s_300m.png" % [when[0], name])])
			f += 52
	# Dust: let the cars run on the gravel road in July.
	_jobs.append([f, func():
		sim.tick_count = _date(6.5)
		for k in 8:
			var a := [gx + 4, -30.0] if k % 2 == 0 else [gx - 4, -LEN + 30.0]
			var b := [gx - 4, -LEN + 30.0] if k % 2 == 0 else [gx + 4, -30.0]
			print("dust trip ", sim.traffic.dispatch({"ref": "a%d" % k, "pos": a}, {"ref": "b%d" % k, "pos": b},
				"construction", {}, "car"))
		_main.set_speed(1)])
	_jobs.append([f + 1, func(): _close(Vector3(gx, 0, -200), 70.0, 25.0)])
	for k in 4:
		_jobs.append([f + 590 + k * 300, func():
			var on := []
			var fast := {}
			for c in sim.traffic.cars:
				if c.has("route") and c.get("j") == null and int(sim.traffic.ways[c.route[c.leg]].type) == RoadStyle.Type.GRAVEL:
					on.append(snappedf(c.v, 0.1))
					if fast.is_empty() or c.v > fast.v:
						fast = c
			if not fast.is_empty():
				# Look at the fastest car from the side, its dust trailing behind.
				var at: Vector3 = sim.traffic.car_pose(fast)[0]
				_close(at, 45.0, 22.0)
			print("cars ", sim.traffic.cars.size(), " on gravel ", on, " puffs ", _view._dust._puffs.size())
			var d: GravelDust = _view._dust
			if not d._puffs.is_empty():
				print("dust aabb ", d.multimesh.get_aabb(), " first ", d._puffs[0], " vis ", d.is_visible_in_tree(),
					" cam ", _cam.camera.global_position,)
		])
		_jobs.append([f + 600 + k * 300, func(): _save("july_gravel_dust_%d.png" % k)])
	_jobs.append([f + 1800, func(): quit()])


## Holds the camera still, nearer than the game's 40 m closest zoom if asked.
func _close(at: Vector3, dist: float, pitch := -1.0) -> void:
	_cam.set_process(false)
	_cam._target = Vector3(at.x, 0, at.z)
	_cam._goal_target = _cam._target
	_cam._yaw = deg_to_rad(20.0)
	_cam._pitch = deg_to_rad(pitch if pitch > 0.0 else (35.0 if dist < 100.0 else 50.0))
	_cam._dist = dist
	_cam._apply()


func _save(name: String) -> void:
	if _out == "":
		return
	var p := _out.path_join(name)
	root.get_viewport().get_texture().get_image().save_png(p)
	print("saved ", p)


# --- A/B cost -----------------------------------------------------------------

const AB_VIEWS := [["street", 30.0, 35.0], ["play", 300.0, 50.0], ["high", 1200.0, 55.0]]
const ROUNDS := 10
const SETTLE := 40
const SAMPLE := 90

var _new_mats := {}
var _old_mats := {}
var _ab_view := 0
var _ab_round := 0
var _ab_frame := 0
var _ab_state := "new"


func _setup_ab(sim: CitySim) -> void:
	PerfTown.build(sim, _arg("--town", "big"))
	sim.street_age.month(sim)  # every street an age, spread over 25 years
	_main.set_speed(3)  # let the town grow a while, then hold it still to measure
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_new_mats = _view._mats.duplicate()
	_old_mats = _view._mats.duplicate()
	for k in _old_mats.keys():
		if str(k).begins_with("pave ") or k == "_pave":
			_old_mats.erase(k)
	_old_mats.asphalt = Surfaces.asphalt()
	_old_mats.yellow = Surfaces.paint(RoadStyle.MARKING_YELLOW)
	_old_mats.white = Surfaces.paint(RoadStyle.MARKING_WHITE)
	_old_mats.bus = Surfaces.paint(Color(0.56, 0.17, 0.14))
	_old_mats["chip seal"] = Surfaces.chip_seal()
	_old_mats["gravel road"] = Surfaces.gravel()
	_jobs.append([200, func(): _ab_start()])


func _ab_start() -> void:
	_new_mats = _view._mats.duplicate()  # with the pave materials made by now
	_main.set_speed(0)
	var paved: Dictionary = _main.sim.street_age.paved
	var t := Time.get_ticks_usec()
	for k in 5:
		_view._surface.rebuild_map(paved)
	var built := RoadWear.map_image(paved)
	print("wear map: %d squares noted, %s map, %.2f ms to rebuild" % [paved.size(), built.get("rect", "no"),
		(Time.get_ticks_usec() - t) / 5000.0])
	_ab_view = 0
	_ab_next_view()
	process_frame.connect(_ab_tick)


func _ab_next_view() -> void:
	var v: Array = AB_VIEWS[_ab_view]
	_close(Vector3(3, 0, 60), v[1], v[2])
	_half = {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
	_gpu = {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
	_ab_round = 0
	_ab_set("new")


func _ab_set(state: String) -> void:
	_ab_state = state
	_ab_frame = 0
	_view._mats = _new_mats if state == "new" else _old_mats
	_view._street_cache.clear()
	_view._junction_cache.clear()
	_view.rebuild()


func _ab_tick() -> void:
	var now := Time.get_ticks_usec()
	_ab_frame += 1
	if _ab_frame > SETTLE and _ab_frame <= SETTLE + SAMPLE:
		_half[_ab_state].append((now - _last_us) / 1000.0)
		_gpu[_ab_state].append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	if _ab_frame == SETTLE + SAMPLE:
		_mem[_ab_state] = [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
		if _ab_state == "new":
			_ab_set("old")
		else:
			_ab_round += 1
			if _ab_round < ROUNDS:
				_ab_set("new")
			else:
				var row := [AB_VIEWS[_ab_view][0], _median(_half.new), _median(_half.old), _mem.new, _mem.old,
					_median(_gpu.new), _median(_gpu.old)]
				_rows.append(row)
				print("AB %s: frame new %.2f ms old %.2f ms, graphics card new %.2f ms old %.2f ms, graphics memory new %.1f MB old %.1f MB, RAM new %.1f MB old %.1f MB"
					% [row[0], row[1], row[2], row[5], row[6], row[3][0], row[4][0], row[3][1], row[4][1]])
				_ab_view += 1
				if _ab_view >= AB_VIEWS.size():
					quit()
					return
				_ab_next_view()
	_last_us = now


static func _median(a: PackedFloat32Array) -> float:
	var s := Array(a)
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else 0.0
