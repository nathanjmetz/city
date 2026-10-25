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
## To open a saved big town instead of building one, add `--playtest-town=path`
## (`&town=file.city` in the browser, fetched from the page's own address;
## tools/scale/make_town_save.gd makes the files): the town then just runs, at
## normal speed and then top speed, with the camera touring it.
## To play in a region instead of alone (neighbors, syncing), add
## `--playtest-region=ws://host:port/CODE` (`&region=` in the browser).
## Several bots in one region each need their own `--playtest-name=`
## (`&name=`) and the PIN the region made for them (`--playtest-pin=`,
## `&pin=`): a region only lets in players it has a PIN for, and
## tools/playtest/make_region.gd makes those. A region bot also keeps
## building while it runs, so its neighbors have something new to sync
## (tools/playtest/soak.sh).

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
var bot_name := "Playtest"
## The PIN the region made for this bot (a region lets in nobody else).
var pin := ""
## A saved town to open and watch instead of building one ("" for a new town).
var town := ""
var _tries := 0
var _net := {"disconnected": 0, "reconnected": 0, "failed": []}
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
var _causes := {}  # biggest stage -> ms of hitches it led
var _step_hitches := 0
var _steps_quality := {}


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
		elif a.begins_with("--playtest-name="):
			bot_name = a.get_slice("=", 1)
		elif a.begins_with("--playtest-pin="):
			pin = a.get_slice("=", 1)
		elif a.begins_with("--playtest-town="):
			town = a.get_slice("=", 1)
		elif a == "--playtest-inline":
			RegionClient.inline_jobs = true  # one core, like the browser
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('region') || ''", true)
		region = str(r) if typeof(r) == TYPE_STRING else ""
		var nm = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('name') || ''", true)
		if typeof(nm) == TYPE_STRING and nm != "":
			bot_name = nm
		var pn = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('pin') || ''", true)
		if typeof(pn) == TYPE_STRING:
			pin = pn
		var tn = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('town') || ''", true)
		if typeof(tn) == TYPE_STRING:
			town = tn
	if region != "":
		# Joins as a player of its own (_join_region).
		Session.profile.name = bot_name
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
	if ms >= HITCH_MS:
		var keys := stages.keys()
		keys.sort_custom(func(a, b): return stages[a] > stages[b])
		# What the hitches spent most on, summed up by their biggest stage
		# (the frame's untimed rest when no stage explains half of it).
		var cause: String = keys[0] if not keys.is_empty() and stages[keys[0]] >= ms * 0.5 else "untimed"
		_causes[cause] = _causes.get(cause, 0.0) + ms
		_step_hitches += 1
		if ms >= FREEZE_MS or _step_hitches <= 12:
			var top := {}
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
	_step_hitches = 0
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
	var over_250 := 0
	for ms in frames:
		if ms >= 250.0:
			over_250 += 1
		if ms >= HITCH_MS:
			hitches += 1
		if ms >= FREEZE_MS:
			freezes += 1
	return {"frames": n, "p50_ms": snappedf(sorted[n / 2], 0.1), "p95_ms": snappedf(sorted[mini(n - 1, n * 95 / 100)], 0.1),
		"p99_ms": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.1), "max_ms": snappedf(sorted[n - 1], 0.1),
		"hitches": hitches, "over_250": over_250, "freezes": freezes}


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


## Joins the region the way the title screen does after a player types
## their PIN (scripts/shell/main_menu.gd), without the typing.
func _join_region() -> void:
	var cut := region.rfind("/")
	var c := Session.join_region(region.left(cut), region.substr(cut + 1), "", false, pin)
	c.joined.connect(func(): Session.enter_region())
	c.failed.connect(func(reason): _finish("couldn't join the region: " + str(reason)))


func _play() -> void:
	_begin("load")
	var opened_us := Time.get_ticks_usec()
	if town != "":
		if not await _open_town():
			return
		opened_us = Time.get_ticks_usec()
	elif region == "":
		Session.new_city("Playtest")
	else:
		_join_region()
	# Wait for the game scene to finish drawing the town.
	while true:
		await get_tree().process_frame
		if _done:
			return
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("set_speed") and not scene.loading:
			_main = scene
			break
		# (A saved big town takes minutes to open in the browser.)
		if Time.get_ticks_usec() - _t0 > (1_200_000_000 if town != "" else 300_000_000):
			_finish("the town never finished loading")
			return
	var sim: CitySim = _main.sim
	var cam: CityCamera = _main.find_children("*", "CityCamera", true, false)[0]
	if town != "":
		_result["load_s"] = snappedf((Time.get_ticks_usec() - opened_us) / 1e6, 0.1)
		_result["start_population"] = sim.stats.population
		_result["start_buildings"] = sim.buildings.size()
		await _frames_wait(30)
		await _watch_town(sim, cam)
		return
	sim.economy.money = 50_000_000
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
	_act("road", {"type": "build_road", "start": [g0.x, g0.z], "ctrl": [(g0.x + far.x) * 0.5, (g0.z + far.z) * 0.5], "end": [far.x, far.z], "join": true})
	await _seconds_wait(3.0)

	_begin("grid")
	var a := g0
	var b := g0 + along * BLOCK * BLOCKS
	var c := g0 + out * BLOCK * BLOCKS
	_act("grid", {"type": "build_grid", "a": [a.x, a.z], "b": [b.x, b.z], "c": [c.x, c.z], "block": BLOCK, "join": true})
	await _seconds_wait(3.0)

	_begin("join_county")
	var j := g0 + along * BLOCK * 2.0
	var on_j := on + along * BLOCK * 2.0
	# Like the road tool: a road drawn onto a county road joins that mile.
	var joined := sim.county_joined.size()
	_act("county_road", {"type": "build_road", "start": [j.x, j.z], "ctrl": [(j.x + on_j.x) * 0.5, (j.z + on_j.z) * 0.5],
		"end": [on_j.x, on_j.z], "join": true})
	_actions["join_county"] = sim.county_joined.size() > joined
	print("Playtest: join_county %s" % ("ok" if _actions.join_county else "REFUSED"))
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
	var grow_at := Time.get_ticks_usec() + 60_000_000
	var grown := 0
	_watch_client()
	while Time.get_ticks_usec() < end:
		if region != "" and Time.get_ticks_usec() > grow_at:
			grow_at = Time.get_ticks_usec() + 60_000_000
			for k in 6:  # the first spot may be taken or blocked
				if _grow(sim, g0, along, out, _tries):
					grown += 1
					break
				_tries += 1
			_tries += 1
		var ang := stop * 1.3
		var spot := mid_town + Vector3(cos(ang), 0, sin(ang)) * BLOCK * (1.0 + stop % 3)
		cam.glide_to(spot, [180.0, 450.0, 1100.0][stop % 3])
		stop += 1
		await _seconds_wait(8.0)
	_end_step()
	_step = ""
	_town_numbers(sim)
	if region != "":
		_result["grown"] = grown
		_result["region"] = _region_view()
	_finish("")


func _town_numbers(sim: CitySim) -> void:
	_result["population"] = sim.stats.population
	_result["buildings"] = sim.buildings.size()
	_result["segments"] = sim.network.segments.size()
	_result["vehicles"] = sim.traffic.cars.size()


## Opens the saved town (`town`): in the browser it is fetched from the
## page's own address and put where the game keeps saves; on the desktop it
## is played from where it is. Whether it arrived.
func _open_town() -> bool:
	var path := town
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		var req := HTTPRequest.new()
		add_child(req)
		var t := Time.get_ticks_usec()
		if req.request(origin + "/" + town) != OK:
			_finish("couldn't ask for the town " + town)
			return false
		var got: Array = await req.request_completed
		if got[1] != 200:
			_finish("the town %s came back with code %d" % [town, got[1]])
			return false
		var body: PackedByteArray = got[3]
		_result["download_s"] = snappedf((Time.get_ticks_usec() - t) / 1e6, 0.1)
		_result["save_mb"] = snappedf(body.size() / 1048576.0, 0.1)
		DirAccess.make_dir_recursive_absolute(Session.SAVE_DIR)
		path = Session.SAVE_DIR.path_join("measure.city")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(body)
		f.close()
		req.queue_free()
	Session.play_solo(path)
	return true


## A saved town just running: the camera tours it at normal speed, then at
## top speed (the run's seconds split between the two).
func _watch_town(sim: CitySim, cam: CityCamera) -> void:
	for n in _main.find_children("*", "FirstTownTour", true, false):
		n.stop()
	var half := run_seconds / 2.0
	var mid_town := Vector3.ZERO
	var stop := 0
	for pass_name in ["run_1x", "run_4x"]:
		_begin(pass_name)
		_main.set_speed(1 if pass_name == "run_1x" else _main.SPEEDS.size() - 1)
		var end := Time.get_ticks_usec() + int(half * 1e6)
		while Time.get_ticks_usec() < end:
			var ang := stop * 1.3
			var spot := mid_town + Vector3(cos(ang), 0, sin(ang)) * BLOCK * (1.0 + stop % 3)
			cam.glide_to(spot, [180.0, 450.0, 1100.0][stop % 3])
			stop += 1
			await _seconds_wait(8.0)
		_steps_quality[pass_name] = GraphicsQuality.current.describe() if GraphicsQuality.current != null else ""
	_end_step()
	_step = ""
	_town_numbers(sim)
	_result["quality_after"] = _steps_quality
	_finish("")


## A player adding to the town now and then: a street off the far side of
## the grid, zoned for homes.
func _grow(sim: CitySim, g0: Vector3, along: Vector3, out: Vector3, n: int) -> bool:
	# Streets off the far side, then the near ends, longer each time round.
	var side: Vector3 = [out, along, -along][(n / (BLOCKS + 1)) % 3]
	var edge: Vector3 = g0 + out * BLOCK * BLOCKS if side == out else (g0 + along * BLOCK * BLOCKS if side == along else g0)
	var across: Vector3 = along if side == out else out
	var from := edge + across * BLOCK * float(n % (BLOCKS + 1))
	var to := from + side * (BLOCK * (1 + n / (3 * (BLOCKS + 1))))
	var before := sim.network.segments.size()
	if not _act("grow", {"type": "build_road", "start": [from.x, from.z], "ctrl": [(from.x + to.x) * 0.5, (from.z + to.z) * 0.5],
			"end": [to.x, to.z], "join": true}):
		return false
	for id in sim.network.segments.keys().slice(before):
		sim.apply({"type": "zone_frontage", "seg": id, "side": 1, "zone": ZoneMap.Zone.RESIDENTIAL, "both": true})
	return true


func _watch_client() -> void:
	var c: RegionClient = Session.client
	if c == null:
		return
	c.disconnected.connect(func(): _net.disconnected += 1)
	c.reconnected.connect(func(): _net.reconnected += 1)
	c.failed.connect(func(why): _net.failed.append(why))


## What this player sees of the region at the end: its own town and each
## neighbor's copy, to compare with what their owners have
## (tools/playtest/soak_check.py).
func _region_view() -> Dictionary:
	var c: RegionClient = Session.client
	if c == null:
		return {"error": "no region client"}
	var towns := {}
	for id in c.region.cities:
		var s: CitySim = c.region.cities[id].sim
		towns[id] = {"name": c.region.cities[id].name, "buildings": s.buildings.size(), "segments": s.network.segments.size()}
	return {"me": c.my_city, "joined": c.is_joined, "players": c.players.size(), "towns": towns, "net": _net}


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
			# Not one the town's own highway already runs along.
			var at := Vector3(mile.on.x - o.x, 0.0, mile.on.y - o.y)
			if not sim.network.find_segment_near(at, 40.0, 1.0).is_empty():
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
		"run_seconds": run_seconds, "online": region != "", "total": all, "steps": _steps, "freezes": _freezes, "hitch_causes": _causes,
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
		# Closes like a player closing the window (a region gets the town).
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		get_tree().quit(0 if error == "" else 1)
