extends SceneTree
## The worst hitch: the camera jumps straight into dense woods it has never
## seen, so every grown tree there has to be grown, meshed and looked up from
## nothing. Jumps to six far-apart woodlots in turn, grown trees on for the
## odd ones and off (the cards only) for the even ones, and reports each
## jump's worst frame. Run in a window:
##   godot --resolution 1600x900 -s tools/trees/jump_lab.gd -- [THREADS] [FIRST]
## THREADS 0 builds the meshes on the main thread, a slice a frame, as the
## browser does. FIRST "off" starts with the cards only (so the first,
## coldest jump is the cards' own). Add --rendering-method gl_compatibility
## for the browser's renderer (it is set to High, the browser's top tier;
## the desktop to Ultra).

const SETTLE := 240
const TIME := 420
const JUMPS := 6

var _main: Node
var _cam: CityCamera
var _frames := 0
var _spots := []
var _jump := -1
var _jf := 0
var _ms := []
var _last := 0
var _res := []
var _parity := 0
var _grown: GrownTrees
var _grown_max := 0.0
var _pc := Vector4i.ZERO


## Pipelines compiled so far: [mesh loads, surface loads, at draw time, specialisations].
func _compiles() -> Vector4i:
	return Vector4i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	# (Through the script, so this lab also runs on versions without the knob.)
	if a.size() > 0 and a[0] == "0":
		load("res://scripts/art/trees/grown_trees.gd").set("threads_ok", false)
	if a.size() > 1 and a[1] == "off":
		_parity = 1
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_main.set_speed(0)
		var q := GraphicsQuality.current
		if q:
			# The same tier every run (the browser's top, High; Ultra on the
			# desktop), without touching the saved setting.
			q.mode = GraphicsQuality.HIGH if q.browser else GraphicsQuality.ULTRA
			q.tier = q.mode
			q.apply()
		_spots = _woods()
		for n in _main.find_children("*", "GrownTrees", true, false):
			_grown = n
		_cam.set_view(deg_to_rad(200.0), deg_to_rad(35.0), 700.0)
		return false
	if _frames < SETTLE:
		return false
	if _jump < 0 or _jf >= TIME:
		if _jump >= 0:
			_report()
		_jump += 1
		if _jump >= _spots.size():
			print("JUMP_LAB ", JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
				"threads": load("res://scripts/art/trees/grown_trees.gd").get("threads_ok"), "detail": GraphicsQuality.detail, "jumps": _res}))
			quit()
			return false
		GrownTrees.enabled = (_jump + _parity) % 2 == 0
		_jf = 0
		_ms.clear()
		_grown_max = 0.0
		# Straight in, no glide: 60 m out over the woods, low.
		_cam.look_at_point(_spots[_jump])
		_cam.set_view(deg_to_rad(200.0 + 40.0 * _jump), deg_to_rad(14.0), 60.0)
		return false
	_jf += 1
	_ms.append(ms)
	var pc := _compiles()
	if ms > 100.0:
		print("JUMP_LAB stall: jump %d frame %d %.0f ms, pipelines compiled %s, grown main %.2f ms" % [_jump, _jf, ms,
			str((pc - _pc) if pc is Vector4i else pc), _grown.get("last_ms") if _grown and _grown.get("last_ms") != null else -1.0])
	_pc = pc
	if _grown and _grown.get("last_ms") != null:
		_grown_max = maxf(_grown_max, _grown.get("last_ms"))
	return false


func _report() -> void:
	var sorted := _ms.duplicate()
	sorted.sort()
	var over := 0
	for m in _ms:
		if m > 33.3:
			over += 1
	var g := _grown
	_res.append({"spot": [snappedf(_spots[_jump].x, 1), snappedf(_spots[_jump].z, 1)], "grown": GrownTrees.enabled,
		"worst_ms": snappedf(sorted[-1], 0.1), "p99_ms": snappedf(sorted[int(sorted.size() * 0.99)], 0.1),
		"median_ms": snappedf(sorted[sorted.size() / 2], 0.1), "frames_over_33ms": over,
		"grown_main_max_ms": snappedf(_grown_max, 0.01), "stats": g.stats() if g else {}})


## Far-apart spots of dense woods, from the land's own cover.
func _woods() -> Array:
	var cands := []
	for x in range(-4000, 4001, 250):
		for z in range(-4000, 4001, 250):
			var p := Vector3(x, 0, z)
			if p.length() < 1200.0:
				continue
			cands.append([float(Vegetation.natural_cover(p)[0]), p])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for c in cands:
		var ok := true
		for o in out:
			ok = ok and (o as Vector3).distance_to(c[1]) > 1500.0
		if ok:
			out.append(c[1])
		if out.size() >= JUMPS:
			break
	return out
