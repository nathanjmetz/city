extends SceneTree
## County farmsteads in a real game window: pictures from high over the
## county and close to a few farmsteads, and what they cost. In each view
## the farmsteads are switched off and on in turns (8 times, 90 frames
## each) and the median frame of each half is reported, because other
## programs on the machine slow both halves alike; the difference is the
## farmsteads' cost. Works on older code too (it only hides FarmsteadView),
## so the same run on main gives the "before".
## Run (desktop renderer, a real window):
##   godot --rendering-driver vulkan -s tools/farmsteads/farmstead_bench.gd -- --tier high --shots DIR [--views county,low,farm1,farm2,farm3,night]
## with --disable-vsync --max-fps 0 so frame times are the machine's. Vulkan
## reports the graphics card's time; Metal (the default) reports none here.
## --spots x,z,x,z,x,z: the farmsteads to visit (view metres); without it
## the tool picks a grain farm with a dryer, an old farm with a barn and
## silo or windmill, and a hog farm or home near the start.

var _main: Node
var _cam: CityCamera
var _fv: Node
var _frames := 0
var _steps := []  # [name, yaw, pitch, dist, look, night]
var _step := -1
var _step_frames := 0
var _last_us := 0
var _half := {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
## Graphics time and the game's own time (process plus the renderer's CPU side), ms.
var _gpu := {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
var _cpu := {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
var _mem := {"on": [], "off": []}
var _rows := []
var _night_tick := 0
var _day_tick := 0
var _dir := ""
var _ready_frames := 0
var _load_start := 0
var _frame_max := {"on": 0.0, "off": 0.0}

const SETTLE := 240
const SWITCHES := 8
const HALF := 90
const HALF_SETTLE := 40


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
	if _frames <= 2:
		return false
	var now := Time.get_ticks_usec()
	if _step < 0:
		# Wait for every block of farmsteads to be built.
		var q: Array = _fv.get("_queue")
		var job = _fv.get("_job")
		if q.is_empty() and (job == null or (job as Dictionary).is_empty()):
			_ready_frames += 1
		if _ready_frames > 60:
			print("farmsteads built in %.1f s" % ((now - _load_start) / 1e6))
			_next()
		_last_us = now
		return false
	_step_frames += 1
	_frame()
	_last_us = now
	return false


func _setup() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	_main.set_speed(0)
	DayNight.seasons_on = false
	DayNight.cycle_on = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Hud:
			c.close_all()
		if c.get_class() == "Node3D" and c.get_script() != null and c.get_script().get_global_name() == "FarmsteadView":
			_fv = c
	_dir = _arg("--shots", "")
	# Pin the tier without saving it (another game on this machine may have
	# left the "didn't close cleanly" mark, which would start us at Low).
	var q := root.get_node_or_null("Quality")
	var want := ["low", "medium", "high", "ultra", "cinematic"].find(_arg("--tier", "high"))
	if q != null and want >= 0:
		q._ceiling = GraphicsQuality.CINEMATIC
		q.mode = want
		q.tier = want
		q.apply()
		print("tier pinned: ", q.describe())
	_load_start = Time.get_ticks_usec()
	# 10 pm and noon, for the yard lights.
	var t := 0
	while ((CitySim.START_UNIX + t * 60) / 3600) % 24 != 22:
		t += 10
	_night_tick = t
	while ((CitySim.START_UNIX + t * 60) / 3600) % 24 != 12:
		t += 10
	_day_tick = t
	var spots := _pick_spots()
	var views := _arg("--views", "county,low,farm1,farm2,farm3,night").split(",")
	var county := Vector3(-3000, 0, 1260)
	for v in views:
		match v:
			"county": _steps.append(["county", 30.0, 52.0, 2600.0, county, false])
			"low": _steps.append(["low", 200.0, 14.0, 1400.0, county, false])
			"night": _steps.append(["night", 30.0, 40.0, 2600.0, county, true])
			"farm1": _steps.append(["farm1", 215.0, 22.0, 110.0, spots[0], false])
			"farm2": _steps.append(["farm2", 140.0, 20.0, 90.0, spots[1], false])
			"farm3": _steps.append(["farm3", 60.0, 26.0, 120.0, spots[2], false])
			"farm1n": _steps.append(["farm1n", 215.0, 22.0, 110.0, spots[0], true])
			"farm3n": _steps.append(["farm3n", 60.0, 26.0, 120.0, spots[2], true])
	_cam.look_at_point(county)
	_cam.set_view(deg_to_rad(30.0), deg_to_rad(52.0), 2600.0)


## Farmsteads to visit: near the start, of different kinds.
func _pick_spots() -> Array:
	var given := _arg("--spots", "")
	if given != "":
		var a := given.split(",")
		return [Vector3(float(a[0]), 0, float(a[1])), Vector3(float(a[2]), 0, float(a[3])), Vector3(float(a[4]), 0, float(a[5]))]
	var out := [Vector3(-3000, 0, 1260), Vector3(-3000, 0, 1260), Vector3(-3000, 0, 1260)]
	if not ResourceLoader.exists("res://scripts/art/farmsteads/farmstead_plan.gd"):
		return out
	var plan_script: GDScript = load("res://scripts/art/farmsteads/farmstead_plan.gd")
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	var n := data.decode_u32(4)
	var best := [INF, INF, INF]
	for i in n:
		var at := 8 + i * 7
		var p := Vector2(data.decode_s16(at), data.decode_s16(at + 2))
		var farm := data.decode_u8(at + 4) == 1
		var d := (p - Terrain.view_origin).length()
		if d < 1500.0 or d > 6000.0:
			continue
		var plan: Dictionary = plan_script.grow(p, farm, data.decode_u8(at + 5) / 256.0 * TAU, data.decode_u8(at + 6))
		var kinds: Array = plan.parts.map(func(q): return q.kind)
		var slot := -1
		if plan.kind == "grain" and "dryer" in kinds:
			slot = 0
		elif plan.old and ("silo" in kinds or "windmill" in kinds) and "barn" in kinds:
			slot = 1
		elif plan.kind == "hog":
			slot = 2
		if slot >= 0 and d < best[slot]:
			best[slot] = d
			# Look at the work yard, 30 m behind the house.
			var yard: Vector2 = plan_script.to_region(plan, Vector2(0, 30)) - Terrain.view_origin
			out[slot] = Vector3(yard.x, 0, yard.y)
			print("spot %d: %s %s at %s (%s)" % [slot, plan.kind, plan.house.type, p, kinds])
	print("spots: %d,%d,%d,%d,%d,%d" % [out[0].x, out[0].z, out[1].x, out[1].z, out[2].x, out[2].z])
	return out


func _next() -> void:
	_step += 1
	_step_frames = 0
	_half = {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
	_gpu = {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
	_cpu = {"on": PackedFloat32Array(), "off": PackedFloat32Array()}
	_mem = {"on": [], "off": []}
	_frame_max = {"on": 0.0, "off": 0.0}
	if _step >= _steps.size():
		_report()
		return
	var s: Array = _steps[_step]
	var sim: CitySim = _main.sim
	DayNight.cycle_on = s[5]
	sim.tick_count = _night_tick if s[5] else _day_tick
	_cam.look_at_point(s[4])
	_cam.set_view(deg_to_rad(s[1]), deg_to_rad(s[2]), s[3])
	_fv.visible = true
	if "time_ms" in _fv:
		_fv.time_ms = 0.0
		_fv.frames = 0


func _frame() -> void:
	var f := _step_frames - SETTLE
	if f < 0:
		return
	var half := f / HALF
	var within := f % HALF
	if half >= SWITCHES * 2:
		_finish()
		return
	var which := "on" if half % 2 == 0 else "off"
	if within == 0:
		_fv.visible = which == "on"
	elif within > HALF_SETTLE:
		var ms := (Time.get_ticks_usec() - _last_us) / 1000.0
		_half[which].append(ms)
		var vp := root.get_viewport_rid()
		_gpu[which].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu[which].append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_frame_max[which] = maxf(_frame_max[which], ms)
	if within == HALF - 1:
		_mem[which].append([Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		if half == 0 and _dir != "":
			root.get_texture().get_image().save_png(_dir.path_join("%s.png" % _steps[_step][0]))


static func _median(a: PackedFloat32Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2] if not b.is_empty() else 0.0


func _finish() -> void:
	var s: Array = _steps[_step]
	var row := {"view": s[0]}
	for which in ["on", "off"]:
		var b: PackedFloat32Array = _half[which]
		var sorted := b.duplicate()
		sorted.sort()
		var m: Array = _mem[which][-1]
		row[which] = {"median_ms": _median(b), "gpu_ms": _median(_gpu[which]), "cpu_ms": _median(_cpu[which]), "p99_ms": sorted[int(sorted.size() * 0.99)], "max_ms": _frame_max[which],
			"video_mb": m[0], "ram_mb": m[1], "tris": m[2], "draws": m[3], "buffer_mb": m[4], "texture_mb": m[5]}
	_rows.append(row)
	var extra := ""
	if "worst_frame_ms" in _fv:
		extra = "  view's mean %.3f ms a frame, worst frame" % (_fv.time_ms / maxf(_fv.frames, 1))
		extra += " %.2f ms, worst block %.2f ms" % [_fv.worst_frame_ms, _fv.worst_block_ms]
		var near = _fv.get("_near")
		if near != null:
			extra += ", close-ups built %d, worst step %.2f ms (%s)" % [near.built_count, near.worst_step_ms, near.get("worst_step")]
	print("AB %-6s gpu on %5.2f off %5.2f | cpu on %5.2f off %5.2f | buffers %5.0f MB textures %5.0f MB" % [row.view, row.on.gpu_ms, row.off.gpu_ms,
		row.on.cpu_ms, row.off.cpu_ms, row.on.buffer_mb, row.on.texture_mb])
	print("AB %-6s on: %6.2f ms (p99 %6.2f, max %6.2f) video %5.0f MB ram %5.0f MB tris %8d draws %5d | off: %6.2f ms (p99 %6.2f, max %6.2f) video %5.0f MB ram %5.0f MB tris %8d draws %5d%s" % [
		row.view, row.on.median_ms, row.on.p99_ms, row.on.max_ms, row.on.video_mb, row.on.ram_mb, row.on.tris, row.on.draws,
		row.off.median_ms, row.off.p99_ms, row.off.max_ms, row.off.video_mb, row.off.ram_mb, row.off.tris, row.off.draws, extra])
	_next()


func _report() -> void:
	print("RESULT ", JSON.stringify(_rows))
	quit()
