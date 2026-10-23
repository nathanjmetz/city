class_name Playtest
extends Node
## Plays the game like a person would, in the real game window with every
## view drawing, and times every frame on the wall clock: opens a new town,
## draws a road, lays a grid, joins a county road, zones the blocks, adds
## power and water, then runs at top speed while the camera tours the town.
##
## It reports the frame times (median, 95th and 99th percentile, worst),
## every freeze with the stages that ran in it, and memory, so CI can catch a
## merge that makes the game stutter or swell (tools/playtest/).
##
## Start it with `--playtest[=seconds]` after `--` on the desktop, or
## `?playtest=seconds` in the browser's address. Results go to the console
## as one line starting with RESULT_TAG, and to `--playtest-out=path`.
## To play in a region instead of alone (neighbors, syncing), add
## `--playtest-region=ws://host:port/CODE` (`&region=` in the browser).

const RESULT_TAG := "PLAYTEST_RESULT "
## A frame over this long is a hitch; over FREEZE_MS a freeze.
const HITCH_MS := 100.0
const FREEZE_MS := 1000.0
## The blocks of the test grid, in metres, and how many each way.
const BLOCK := 120.0
const BLOCKS := 4

var run_seconds := 600.0
var out_path := ""
## "ws://host:port/CODE" to join a region, or "" to play alone.
var region := ""
var _main: Node
var _t0 := 0
var _last := 0
var _frames := PackedFloat32Array()
var _step := ""
var _steps := []
var _step_frames := PackedFloat32Array()
var _step_t0 := 0
var _freezes := []
var _stage_sums := {}
var _mem_peak := 0.0
var _mem_start := 0.0
var _result := {}
var _actions := {}
var _done := false


## Whether this run asked for a play-through, and for how long.
static func wanted() -> float:
	var arg := ""
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('playtest') || ''", true)
		arg = str(q) if typeof(q) == TYPE_STRING else ""
		if arg == "":
			return 0.0
	else:
		for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
			if a == "--playtest":
				arg = "600"
			elif a.begins_with("--playtest="):
				arg = a.get_slice("=", 1)
		if arg == "":
			return 0.0
	return maxf(float(arg), 10.0) if arg.is_valid_float() else 600.0


## Memory the game holds now, in MB: the browser's WebAssembly heap plus its
## JavaScript heap, or the process's resident memory on Linux. 0 elsewhere.
static func memory_mb() -> float:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(function(){var h=0;try{h=engine.rtenv.HEAP8.length}catch(e){}" \
			+ "var j=(performance.memory&&performance.memory.usedJSHeapSize)||0;return (h+j)/1048576})()", true)
		return float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else 0.0
	if OS.get_name() == "Linux":
		var f := FileAccess.open("/proc/self/status", FileAccess.READ)
		if f:
			for line in f.get_as_text().split("\n"):
				if line.begins_with("VmRSS:"):
					return float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return OS.get_static_memory_usage() / 1048576.0


func _ready() -> void:
	process_priority = -1000  # first each frame, so the gap is the whole frame
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--playtest-out="):
			out_path = a.get_slice("=", 1)
		elif a.begins_with("--playtest-region="):
			region = a.get_slice("=", 1)
		elif a == "--playtest-inline":
			RegionClient.inline_jobs = true  # one core, like the browser
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('region') || ''", true)
		region = str(r) if typeof(r) == TYPE_STRING else ""
	if region != "":
		# Joins like an invite link, under a name of its own.
		var cut := region.rfind("/")
		Session.profile.name = "Playtest"
		Session.pending_invite = {"server": region.left(cut), "join": region.substr(cut + 1)}
	_t0 = Time.get_ticks_usec()
	_last = _t0
	_mem_start = memory_mb()
	print("Playtest: %d s at top speed" % run_seconds)
	_play.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	if _step == "":
		return
	_frames.append(ms)
	_step_frames.append(ms)
	var stages := _stage_diff()
	if ms >= FREEZE_MS or (ms >= HITCH_MS and _freezes.size() < 40):
		var top := {}
		var keys := stages.keys()
		keys.sort_custom(func(a, b): return stages[a] > stages[b])
		for k in keys.slice(0, 6):
			top[k] = snappedf(stages[k], 0.1)
		_freezes.append({"ms": snappedf(ms, 0.1), "step": _step, "at_s": snappedf((now - _t0) / 1e6, 0.1), "stages": top})
	if _frames.size() % 30 == 0:
		_mem_peak = maxf(_mem_peak, memory_mb())


## The stage times (Perf) added since last frame, so a freeze shows where
## its time went.
func _stage_diff() -> Dictionary:
	var out := {}
	for key in Perf.stats:
		var s: float = Perf.stats[key].sum
		var before: float = _stage_sums.get(key, 0.0)
		# Telemetry starts new windows now and then, zeroing the sums.
		var d := s - before if s >= before else s
		if d > 0.05:
			out[key] = d
		_stage_sums[key] = s
	return out


func _begin(step: String) -> void:
	_end_step()
	_step = step
	_step_frames = PackedFloat32Array()
	_step_t0 = Time.get_ticks_usec()


func _end_step() -> void:
	if _step == "":
		return
	var s := _summary(_step_frames)
	s["step"] = _step
	s["seconds"] = snappedf((Time.get_ticks_usec() - _step_t0) / 1e6, 0.01)
	_steps.append(s)


static func _summary(frames: PackedFloat32Array) -> Dictionary:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		return {"frames": 0}
	var hitches := 0
	var freezes := 0
	for ms in frames:
		if ms >= HITCH_MS:
			hitches += 1
		if ms >= FREEZE_MS:
			freezes += 1
	return {"frames": n, "p50_ms": snappedf(sorted[n / 2], 0.1), "p95_ms": snappedf(sorted[mini(n - 1, n * 95 / 100)], 0.1),
		"p99_ms": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.1), "max_ms": snappedf(sorted[n - 1], 0.1),
		"hitches": hitches, "freezes": freezes}


func _frames_wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds_wait(s: float) -> void:
	var end := Time.get_ticks_usec() + int(s * 1e6)
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame


func _act(name: String, cmd: Dictionary) -> bool:
	var ok: bool = _main.sim.apply(cmd)
	_actions[name] = ok
	print("Playtest: %s %s" % [name, "ok" if ok else "REFUSED"])
	return ok


func _play() -> void:
	_begin("load")
	# In a region the title screen joins from the invite set up in _ready.
	if region == "":
		Session.new_city("Playtest")
	# Wait for the game scene to finish drawing the town.
	while true:
		await get_tree().process_frame
		if _done:
			return
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("set_speed") and not scene.loading:
			_main = scene
			break
		if Time.get_ticks_usec() - _t0 > 300_000_000:
			_finish("the town never finished loading")
			return
	var sim: CitySim = _main.sim
	sim.economy.money = 50_000_000
	var cam: CityCamera = _main.find_children("*", "CityCamera", true, false)[0]
	await _frames_wait(30)

	# A county road mile near town, and the grid laid out beside it.
	var mile := _find_mile(sim)
	var along := Vector3.RIGHT if mile.key.begins_with("ew") else Vector3.BACK
	var out := Vector3.BACK if mile.key.begins_with("ew") else Vector3.RIGHT
	var on := Vector3(mile.on.x - sim.terrain_offset.x, 0.0, mile.on.y - sim.terrain_offset.y)
	if out.dot(-on) < 0.0:
		out = -out  # build on the town's side of the county road
	var g0 := on + out * 150.0
	cam.glide_to(g0 + out * BLOCK * BLOCKS * 0.5, 600.0)
	await _seconds_wait(2.0)

	_begin("road")
	var far := g0 + out * (BLOCK * BLOCKS + 300.0)
	_act("road", {"type": "build_road", "start": [g0.x, g0.z], "ctrl": [(g0.x + far.x) * 0.5, (g0.z + far.z) * 0.5], "end": [far.x, far.z]})
	await _seconds_wait(3.0)

	_begin("grid")
	var a := g0
	var b := g0 + along * BLOCK * BLOCKS
	var c := g0 + out * BLOCK * BLOCKS
	_act("grid", {"type": "build_grid", "a": [a.x, a.z], "b": [b.x, b.z], "c": [c.x, c.z], "block": BLOCK})
	await _seconds_wait(3.0)

	_begin("join_county")
	var j := g0 + along * BLOCK * 2.0
	var on_j := on + along * BLOCK * 2.0
	if _act("county_road", {"type": "build_road", "start": [j.x, j.z], "ctrl": [(j.x + on_j.x) * 0.5, (j.z + on_j.z) * 0.5], "end": [on_j.x, on_j.z]}):
		_act("join_county", {"type": "join_county", "at": [on_j.x, on_j.z]})
	await _seconds_wait(3.0)

	_begin("zone")
	var n := 0
	for id in sim.network.segments.keys():
		var seg_c: Array = sim.network.curve_of(id)
		var mid: Vector3 = RoadNetwork.bezier(seg_c[0], seg_c[1], seg_c[2], 0.5)
		if (mid - (g0 + (along + out) * BLOCK * BLOCKS * 0.5)).length() > BLOCK * BLOCKS:
			continue
		var zone := ZoneMap.Zone.COMMERCIAL if n % 5 == 0 else ZoneMap.Zone.RESIDENTIAL
		if sim.apply({"type": "zone_frontage", "seg": id, "side": 1, "zone": zone, "both": true}):
			n += 1
		# A player zones one block face at a time.
		await _frames_wait(3)
	_actions["zone_faces"] = n
	await _seconds_wait(3.0)

	_begin("utilities")
	var centre := g0 + (along + out) * BLOCK * 1.5
	for kind in [Services.Kind.SUBSTATION, Services.Kind.WATER_TOWER, Services.Kind.SCHOOL, Services.Kind.FIRE]:
		var site := Services.site_near(sim.network, kind, centre + along * 30.0 * kind)
		if not site.is_empty():
			_act("service_%d" % kind, {"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	await _seconds_wait(3.0)

	# Top speed with the camera touring the town, like a player watching it grow.
	_begin("run")
	_main.set_speed(_main.SPEEDS.size() - 1)
	var end := Time.get_ticks_usec() + int(run_seconds * 1e6)
	var stop := 0
	var mid_town := g0 + (along + out) * BLOCK * BLOCKS * 0.5
	while Time.get_ticks_usec() < end:
		var ang := stop * 1.3
		var spot := mid_town + Vector3(cos(ang), 0, sin(ang)) * BLOCK * (1.0 + stop % 3)
		cam.glide_to(spot, [180.0, 450.0, 1100.0][stop % 3])
		stop += 1
		await _seconds_wait(8.0)
	_end_step()
	_step = ""
	_result["population"] = sim.stats.population
	_result["buildings"] = sim.buildings.size()
	_result["segments"] = sim.network.segments.size()
	_result["vehicles"] = sim.traffic.cars.size()
	_finish("")


## The nearest county road mile to town that can be joined.
func _find_mile(sim: CitySim) -> Dictionary:
	var o := sim.terrain_offset
	var best := {}
	var best_d := INF
	for r in range(400, 3200, 200):
		for i in 16:
			var ang := TAU * i / 16.0
			var p := Vector2(cos(ang), sin(ang)) * r
			var mile := CountyGrid.mile_at(p.x + o.x, p.y + o.y, 60.0)
			if mile.is_empty() or sim.county_joined.has(mile.key) or not CountyGrid.clears(mile.on.x, mile.on.y):
				continue
			var d: float = (mile.on - o).length()
			if d < best_d and d > 500.0:
				best_d = d
				best = mile
		if not best.is_empty():
			return best
	return {"key": "ew:none", "on": o + Vector2(0, 900)}


func _finish(error: String) -> void:
	if _done:
		return
	_done = true
	_end_step()
	_step = ""
	var all := _summary(_frames)
	_mem_peak = maxf(_mem_peak, memory_mb())
	_result.merge({"ok": error == "", "error": error, "platform": OS.get_name(),
		"renderer": str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")),
		"tier": GraphicsQuality.NAMES[GraphicsQuality.current.tier] if GraphicsQuality.current != null else "",
		"run_seconds": run_seconds, "online": region != "", "total": all, "steps": _steps, "freezes": _freezes,
		"actions": _actions, "memory_start_mb": snappedf(_mem_start, 0.1),
		"memory_peak_mb": snappedf(_mem_peak, 0.1), "memory_end_mb": snappedf(memory_mb(), 0.1),
		"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	var text := JSON.stringify(_result)
	print(RESULT_TAG + text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_result, "  "))
			f.close()
	if not OS.has_feature("web"):
		get_tree().quit(0 if error == "" else 1)
