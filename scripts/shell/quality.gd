class_name GraphicsQuality
extends Node
## How good the game looks on this computer, picked silently. An autoload
## (Quality). Benchmark: how PC games do it (Cities: Skylines 2, Forza
## Horizon): presets from Low to a top tier, a guess from the hardware on
## first run, dynamic resolution, and a Graphics setting that defaults to
## Auto.
##
## The first time the desktop app runs it guesses a tier from the graphics
## chip, cores and memory. In Auto, while you play it watches how long
## frames take: when the computer struggles it lowers the render scale
## first (upscaled with FSR), then the tier, and when there is plenty of
## room it climbs back. Where it settles is saved for next time, so the
## guess only happens once per machine. The pause menu's Graphics page
## offers Auto (the default) and fixed tiers up to one above the guess.
##
## Cinematic is as close to real life as the engine gets: global
## illumination (SDFGI), volumetric light in the air, screen-space
## reflections, the biggest shadow maps and the longest detail. Ultra and
## below drop those one by one.
##
## Every device scales to what it can do (Brawn, 2026-10-23): the desktop
## app goes as high as the machine allows, up to Cinematic, and is never
## held back for the browser. The browser (and a desktop whose graphics
## chip only runs the Compatibility renderer) gets the same governor over
## the tiers that renderer can draw, Low and Medium, starting at Low with
## fewer pixels on a phone or tablet. This only touches drawing, never the
## simulation, so every computer in a region still steps towns the same way.
## `--quality low|medium|high|ultra|cinematic` on the command line pins a
## tier (for screenshots).

signal changed

enum { LOW, MEDIUM, HIGH, ULTRA, CINEMATIC }
const NAMES := ["Low", "Medium", "High", "Ultra", "Cinematic"]
const AUTO := -1
const SAVE_PATH := "user://quality.json"
## Bumped when guess_tier changes, so Auto guesses again on machines that
## were first guessed by an older version.
const GUESS_VERSION := 2

## What each tier turns on. msaa: 0 off, 1 2x, 2 4x. soft: RenderingServer
## shadow filter quality (2 low, 3 medium, 4 high, 5 ultra). detail scales
## how far full trees and close-up detail reach; lod is the mesh LOD
## threshold in pixels (lower keeps more detail); shadow_reach caps how far
## from the camera shadows are drawn, in metres. tree_shadows: whether the
## wild woods cast sun shadows (thousands of trees, drawn again for every
## shadow split: the biggest single cost in a wooded town). ssao: ambient occlusion,
## ssil: bounced light between nearby surfaces, ssr: reflections in water
## and glass, sdfgi: sunlight bouncing around the whole town, fog: light
## shafts and haze in the air (volumetric fog).
const TIERS := [
	{"msaa": 0, "fxaa": true, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "fog": false,
		"shadow_size": 2048, "soft": 2, "splits": 2, "detail": 0.4, "lod": 2.0, "shadow_reach": 300.0,
		"tree_shadows": false},
	{"msaa": 1, "fxaa": false, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "fog": false,
		"shadow_size": 4096, "soft": 3, "splits": 2, "detail": 0.7, "lod": 1.0, "shadow_reach": 700.0,
		"tree_shadows": false},
	{"msaa": 2, "fxaa": false, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "fog": false,
		"shadow_size": 4096, "soft": 4, "splits": 4, "detail": 1.4, "lod": 1.0, "shadow_reach": 2000.0,
		"tree_shadows": true},
	{"msaa": 2, "fxaa": false, "ssao": true, "ssil": true, "ssr": true, "sdfgi": false, "fog": false,
		"shadow_size": 8192, "soft": 5, "splits": 4, "detail": 1.8, "lod": 0.5, "shadow_reach": 2000.0,
		"tree_shadows": true},
	{"msaa": 2, "fxaa": false, "ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "fog": true,
		"shadow_size": 8192, "soft": 5, "splits": 4, "detail": 2.5, "lod": 0.25, "shadow_reach": 2000.0,
		"tree_shadows": true},
]

## Frame times are judged over windows of this many seconds.
const WINDOW := 3.0
## Slower than this on average (about 45 fps) counts against the tier.
const SLOW_MS := 22.0
## Room to spare: frames keep up with a 60 Hz screen and the graphics chip
## and the game's own work each take under half a frame.
const ROOM_FRAME_MS := 18.0
const ROOM_PART_MS := 8.0
const MIN_SCALE := 0.7
## A single frame longer than this is a stall (a town loading, a shader
## compiling), not drawing load: it's left out rather than lowering the look.
const STALL_MS := 250.0

## False in headless runs (servers, tests): the look stays as the project sets it.
var active := false
## Running on the Compatibility renderer (the browser, or an old graphics
## chip): only Low and Medium, upscaled bilinearly.
var browser := false
var tier := HIGH
## AUTO, or the tier the player picked (the governor then leaves it alone).
var mode := AUTO
## 3D render scale (1.0 = native pixels). Below 1 is upscaled with FSR.
var scale := 1.0
## Multiplier for how far detail reaches (Views read it as
## GraphicsQuality.detail, since class scripts compile before autoloads
## exist in tests). 1.0 when inactive.
static var detail := 1.0
## Whether the wild woods cast shadows (the tier's tree_shadows). True when
## inactive.
static var tree_shadows := true
## The autoload, for class scripts (null in tests and tools).
static var current: GraphicsQuality
var adapter := ""

var _rid: RID
var _time := 0.0
var _last_us := 0
var _frames := 0
var _gpu := 0.0
var _cpu := 0.0
var _slow := 0
var _room := 0
## No climbing back to a tier this session once it proved too slow.
var _ceiling := CINEMATIC
## The hardware guess (guess_tier) for this computer.
var _guess := HIGH


func _ready() -> void:
	current = self
	adapter = RenderingServer.get_video_adapter_name()
	active = DisplayServer.get_name() != "headless"
	if not active:
		return
	browser = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if browser:
		_ceiling = MEDIUM
	process_priority = 1000  # after the frame's own work
	_guess = MEDIUM if browser else guess_tier(adapter, RenderingServer.get_video_adapter_type(),
		OS.get_processor_count(), float(OS.get_memory_info().get("physical", 0)) / 1e9)
	var saved := _read()
	mode = clampi(int(saved.get("mode", AUTO)), AUTO, _ceiling)
	# A tier this computer can't carry (picked by an older menu that only
	# cycled upward) goes back to Auto rather than crash it again.
	if mode > top():
		mode = AUTO
	if mode != AUTO:
		tier = mode
		scale = clampf(float(saved.get("scale", 1.0)), min_scale(), 1.0)
	elif str(saved.get("adapter", "")) == adapter and saved.has("tier") \
			and int(saved.get("guess", 1)) == GUESS_VERSION:
		tier = clampi(int(saved.tier), LOW, _ceiling)
		scale = clampf(float(saved.get("scale", 1.0)), min_scale(), 1.0)
	else:
		_first_guess()
		_save()
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
		var a: String = args[i]
		var want := ""
		if a.begins_with("--quality="):
			want = a.trim_prefix("--quality=")
		elif a == "--quality" and i + 1 < args.size():
			want = args[i + 1]
		var t := NAMES.map(func(n): return n.to_lower()).find(want.to_lower())
		if t >= 0:
			mode = mini(t, _ceiling)
			tier = mode
			scale = 1.0
	_rid = get_tree().root.get_viewport_rid()
	if not browser:
		RenderingServer.viewport_set_measure_render_time(_rid, true)
	apply()
	print("Graphics: ", describe())


## A phone or tablet: a small, touch-first screen in the browser.
static func is_handheld() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available() and not OS.has_feature("web_macos") \
			and not OS.has_feature("web_windows") and not OS.has_feature("web_linuxbsd"))


func min_scale() -> float:
	return 0.5 if browser else MIN_SCALE


func _first_guess() -> void:
	if browser:
		# Every browser starts on Low (a fresh town's woods alone are
		# millions of triangles on Medium's old look) and climbs when there's
		# room; phones also start with fewer pixels.
		tier = LOW
		scale = 0.75 if is_handheld() else 1.0
	else:
		tier = _guess
		scale = 1.0


## A first guess from the hardware alone; in Auto the governor corrects it
## in play. Apple chips share memory with the GPU, so memory says a lot.
static func guess_tier(name: String, type: int, cores: int, memory_gb: float) -> int:
	var n := name.to_lower()
	if type == RenderingDevice.DEVICE_TYPE_CPU or "llvmpipe" in n or "swiftshader" in n:
		return LOW
	if n.begins_with("apple"):
		# Max and Ultra chips have big GPUs (Mac Studio, big MacBook Pro).
		if "ultra" in n or "max" in n:
			return CINEMATIC if memory_gb >= 30.0 else ULTRA
		if "pro" in n:
			return HIGH
		# A base chip: an 8 GB Mac mini starts on Low (Brawn's mini struggled
		# on Medium in a fresh town) and climbs if there's room.
		return MEDIUM if memory_gb >= 15.0 else LOW
	if type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		if cores >= 8 and memory_gb >= 30.0:
			return CINEMATIC
		return ULTRA if cores >= 8 and memory_gb >= 15.0 else HIGH
	# Integrated graphics (Intel, AMD laptop chips) and anything unknown.
	return MEDIUM if cores >= 8 and memory_gb >= 15.0 else LOW


func settings() -> Dictionary:
	return TIERS[tier]


func describe() -> String:
	if not active:
		return "fixed (%s)" % RenderingServer.get_current_rendering_method()
	if browser:
		return "%s %s, %d%% scale (browser)" % ["Auto:" if mode == AUTO else "Fixed:", NAMES[tier], roundi(scale * 100.0)]
	return "%s %s, %d%% scale" % ["Auto:" if mode == AUTO else "Fixed:", NAMES[tier], roundi(scale * 100.0)]


## The Graphics setting's label, e.g. "Auto (High)" or "Cinematic".
func label() -> String:
	return "Auto (%s)" % NAMES[tier] if mode == AUTO else NAMES[mode]


## The highest tier the Graphics menu offers here: one above the hardware
## guess, so a small computer can try a step up but is never handed a tier
## that's far beyond it (Cinematic on an 8 GB Mac mini runs it out of
## memory). The browser draws Low and Medium only.
func top() -> int:
	return MEDIUM if browser else mini(_guess + 1, CINEMATIC)


## What the Graphics menu picked: AUTO, or a fixed tier up to top().
func choose(m: int) -> void:
	m = clampi(m, AUTO, top())
	mode = m
	_ceiling = MEDIUM if browser else CINEMATIC
	if mode == AUTO:
		_first_guess()
	else:
		tier = mode
	_reset()
	apply()
	_save()


## The Graphics menu's sharpness: the 3D render scale, for a fixed tier
## (Auto sets its own).
func set_scale(s: float) -> void:
	scale = clampf(s, min_scale(), 1.0)
	apply()
	_save()


## Pushes the tier and scale to the screen. Views listen to `changed` for
## the parts they own (SkyLight: ambient occlusion, shadow splits and reach).
func apply() -> void:
	var t: Dictionary = TIERS[tier]
	var vp := get_tree().root
	# The browser's Medium keeps the 4x MSAA it has always had.
	vp.msaa_3d = 2 if browser and tier == MEDIUM else t.msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if t.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = t.lod
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 and not browser else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	RenderingServer.directional_shadow_atlas_set_size(t.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(t.soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(t.soft)
	detail = t.detail
	tree_shadows = t.tree_shadows
	changed.emit()


func _process(_delta: float) -> void:
	if not active or mode != AUTO or not _watching():
		_reset()
		_last_us = 0
		return
	var t0 := Perf.now()
	# Real time between frames: the engine's delta is capped, so a long
	# freeze would hide in it. A stall is skipped, not counted.
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1e6 if _last_us > 0 else -1.0
	_last_us = now
	if dt < 0.0 or dt * 1000.0 > STALL_MS:
		Perf.add("frame.quality", t0)
		return
	_time += dt
	_frames += 1
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid) \
		+ Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _time < WINDOW:
		Perf.add("frame.quality", t0)
		return
	var frame_ms := _time * 1000.0 / _frames
	# The browser judges against 30 fps (its budget, PerfBudget.RENDER) and
	# can't time the graphics chip, so frame time alone decides there.
	var slow_ms := 34.0 if browser else SLOW_MS
	var gpu_ms := _gpu / _frames
	var cpu_ms := _cpu / _frames
	_reset()
	if frame_ms > slow_ms:
		_room = 0
		_slow += 1
		# Far too slow steps down at once; just slow waits for a second window.
		if _slow >= 2 or frame_ms > slow_ms * 2.0:
			_slow = 0
			_step_down(gpu_ms > cpu_ms)
	elif frame_ms < ROOM_FRAME_MS and gpu_ms < ROOM_PART_MS and cpu_ms < ROOM_PART_MS:
		_slow = 0
		_room += 1
		if _room >= 4:
			_room = 0
			_step_up()
	else:
		_slow = 0
		_room = 0
	Perf.add("frame.quality", t0)


## Only in a town that has finished loading, in a window you're looking at.
func _watching() -> bool:
	var w := get_window()
	if not w.has_focus() or w.mode == Window.MODE_MINIMIZED:
		return false
	var scene := get_tree().current_scene
	return scene != null and "loading" in scene and not scene.loading


func _reset() -> void:
	_time = 0.0
	_frames = 0
	_gpu = 0.0
	_cpu = 0.0


## The graphics chip is the bottleneck: fewer pixels first. Otherwise (or
## once pixels are as low as they go) a lower tier draws less.
func _step_down(gpu_bound: bool) -> void:
	if (gpu_bound or browser) and scale > min_scale() + 0.01:
		scale = maxf(min_scale(), scale - 0.15)
	elif tier > LOW:
		_ceiling = tier - 1
		tier -= 1
	else:
		return
	apply()
	_save()


func _step_up() -> void:
	if scale < 0.99:
		scale = minf(1.0, scale + 0.15)
	elif tier < _ceiling:
		tier += 1
	else:
		return
	apply()
	_save()


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "tier": tier, "scale": scale, "adapter": adapter,
			"guess": GUESS_VERSION}))


static func _read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}
