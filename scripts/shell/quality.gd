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
## frames take: when the drawing struggles it lowers the render scale
## first (upscaled with FSR), then the tier, and when there is plenty of
## room it climbs back. Where it settles is saved for next time, so the
## guess only happens once per machine. The pause menu's Graphics page
## offers Auto (the default) and fixed tiers up to one above the guess.
##
## Each tier is also a detail budget (BUDGETS): how far the woods, cars and
## walkers are drawn and how many at most, crop plants and their shadows,
## close-up cars, how far shadows go. Every view reads its share
## with GraphicsQuality.knob("name"); each kind of machine (MACHINES) has
## its own frame and memory budget.
##
## Steady steps (2026-10-25). The governor judges only what a tier can
## change: the town's thinking (its sim steps) is taken out of the frame
## time, because a busy town is slow at every tier, and blaming the drawing
## for it walked a fast Mac from Cinematic down to Low and then back up in
## quiet moments. After every change it waits for the new look to settle
## (shaders compile, detail rebuilds) before judging again; it climbs only
## with clear room and drops only when the drawing is clearly too slow,
## with a wide gap between the two; and a tier that proved too slow stays
## out of reach for a while (longer each time), remembered across runs.
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
## the tiers that renderer can draw, Low to High, starting at Low with
## fewer pixels on a phone or tablet and climbing while frames have room.
## This only touches drawing, never the simulation, so every computer in a
## region still steps towns the same way.
## `--quality low|medium|high|ultra|cinematic` on the command line pins a
## tier (for screenshots). `--quality auto` runs Auto from this computer's
## hardware guess without reading or writing the saved setting (for
## measuring runs, which must not move the player's own setting).

signal changed

enum { LOW, MEDIUM, HIGH, ULTRA, CINEMATIC }
const NAMES := ["Low", "Medium", "High", "Ultra", "Cinematic"]
const AUTO := -1
const SAVE_PATH := "user://quality.json"
## There while the game runs, removed on a clean exit: found at launch, the
## last run crashed (or was force quit), and the look steps back to safety.
## It holds the running copy's process id and a heartbeat time, so a second
## copy running beside it isn't mistaken for a crash.
const RUNNING_PATH := "user://quality_running"
const HEARTBEAT := 5.0
## Bumped when guess_tier changes, so Auto guesses again on machines that
## were first guessed by an older version.
const GUESS_VERSION := 3

## What each tier turns on. msaa: 0 off, 1 2x, 2 4x (only the hardware
## guess's counts: see msaa()). soft: RenderingServer
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
		"shadow_size": 4096, "soft": 2, "splits": 2, "detail": 0.4, "lod": 2.0, "shadow_reach": 300.0,
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

## The detail budget of each tier, read by every view with knob(). One
## place for "how much may be drawn near the camera", so the views agree.
## Distances are metres from the camera; counts are the most drawn at once.
##   grow_ms: ms of each frame WildView may spend laying out tree chunks.
##   woods: share of the wild woods' full reach (and of their brush) drawn.
##   far_from: share of BuildingView's far-box swap distance.
##   crops / crop_m / crop_shadows: field plants on or off, how far round
##     the look spot, and whether corn casts shadows.
##   cars_m: how far cars and trucks are drawn; car_near_m: inside it the
##     full model, past it the light one; car_detail: the close-up model
##     inside TrafficView.ULTRA_NEAR.
##   cars / people: the most cars or walkers drawn at once. Past that the
##     view pulls its reach in until the count fits (fit_reach()), so the
##     nearest stay drawn. people_m: how far walkers are drawn.
## Values a tier already sets in TIERS (detail, shadow_reach, tree_shadows)
## aren't repeated here: knob() reads them as detail, shadow_m and
## tree_shadows. High is the look the game had before budgets, so a
## full-strength desktop (High and up) is never drawn with less than that.
const BUDGETS := [
	{"grow_ms": 3.0, "woods": 0.6, "far_from": 0.6, "crops": false, "crop_m": 51.0, "crop_shadows": false,
		"cars_m": 1400.0, "car_near_m": 160.0, "car_detail": false, "cars": 600,
		"people_m": 180.0, "people": 400},
	{"grow_ms": 3.0, "woods": 0.7, "far_from": 0.7, "crops": false, "crop_m": 51.0, "crop_shadows": false,
		"cars_m": 1900.0, "car_near_m": 200.0, "car_detail": false, "cars": 1200,
		"people_m": 250.0, "people": 1000},
	{"grow_ms": 4.0, "woods": 1.0, "far_from": 1.2, "crops": true, "crop_m": 60.0, "crop_shadows": false,
		"cars_m": 2600.0, "car_near_m": 240.0, "car_detail": false, "cars": 4000,
		"people_m": 320.0, "people": 4000},
	{"grow_ms": 4.0, "woods": 1.0, "far_from": 1.2, "crops": true, "crop_m": 77.0, "crop_shadows": false,
		"cars_m": 2600.0, "car_near_m": 240.0, "car_detail": true, "cars": 8000,
		"people_m": 320.0, "people": 8000},
	{"grow_ms": 4.0, "woods": 1.0, "far_from": 1.2, "crops": true, "crop_m": 81.0, "crop_shadows": true,
		"cars_m": 2600.0, "car_near_m": 240.0, "car_detail": true, "cars": 16000,
		"people_m": 320.0, "people": 16000},
]
## Headless runs and tests (no Quality autoload, or not active): the views
## keep the look they had before tiers (detail 1.0), with no field plants,
## close-up cars or corn shadows unless a test turns them on itself, and
## no count caps.
const NO_CAP := 1 << 30
const INACTIVE := {"detail": 1.0, "shadow_m": 2000.0, "tree_shadows": true, "grow_ms": 4.0, "woods": 1.0,
	"far_from": 1.0, "crops": false, "crop_m": 51.0, "crop_shadows": false, "cars_m": 2600.0,
	"car_near_m": 240.0, "car_detail": false, "cars": NO_CAP, "people_m": 320.0, "people": NO_CAP}
## The browser caps how long a frame may spend growing detail (its one
## thread also runs the town).
const BROWSER_GROW_MS := 3.0

## Each kind of machine's budget: the frame it aims for (slow_ms: drawing
## slower than this counts against the tier; room_ms: the whole frame under
## this is room to climb) and the graphics memory Auto won't climb past
## (video_mb; 0 is no limit). The tiers it may use come from auto_top().
## Brawn's machines: the browser; the 8 GB Mac mini ("small": an Apple chip
## or built-in graphics with under 15 GB); a 16 to 30 GB Apple chip or
## laptop ("shared"); the Mac Studio and Windows PCs with a graphics card
## ("full": never held back).
const MACHINES := {
	"browser": {"slow_ms": 34.0, "room_ms": 20.0, "video_mb": 1500},
	"small": {"slow_ms": 22.0, "room_ms": 18.0, "video_mb": 2500},
	"shared": {"slow_ms": 22.0, "room_ms": 18.0, "video_mb": 6000},
	"full": {"slow_ms": 22.0, "room_ms": 18.0, "video_mb": 0},
}

## Frame times are judged over windows of this many seconds.
const WINDOW := 3.0
## After a change (and when watching starts), this many windows go by
## before judging: shaders compile and detail is rebuilt for the new tier,
## and those slow frames are the change settling, not the tier's cost.
const SETTLE_WINDOWS := 2
## The machine's slow_ms (MACHINES: about 45 fps on the desktop with the
## town's thinking taken out, 30 fps in the browser) counts against the
## tier; twice it steps down at once. Room to spare: the whole frame under
## room_ms (it keeps up with a 60 Hz screen) and, on the desktop, the
## graphics chip and the drawing's own CPU work each under ROOM_PART_MS.
## A tier step costs well under the gap up to slow_ms, so a climb doesn't
## land straight on "too slow".
const ROOM_PART_MS := 8.0
## Windows in a row needed to step down (slow) or up (room).
const SLOW_WINDOWS := 2
const ROOM_WINDOWS := 4
const MIN_SCALE := 0.7
## Each step of sharpness (render scale) down or up.
const SCALE_STEP := 0.15
## The browser (Compatibility renderer) climbs as far as High: its longer
## detail, trees and shadows draw there; SSAO and the rest are desktop only.
## It judges against 30 fps (its budget, PerfBudget.RENDER) and can't time
## the graphics chip, so whole-frame times decide there.
const BROWSER_TOP := HIGH
## A single frame longer than this is a stall (a town loading, a shader
## compiling), not drawing load: it's left out rather than lowering the look.
const STALL_MS := 250.0
## Once a tier proved too slow, Auto waits this many minutes of play before
## trying it again, doubling each time it fails (up to PATIENCE_MAX).
const PATIENCE_MIN := 5.0
const PATIENCE_MAX := 80.0
const HOLD_MIN := 10.0
## A step down has to make the drawing at least this much faster (the
## first window judged after it, against the window that set it off), or
## the slowness wasn't the tier's or the pixels': a town still building
## its detail, a view's own work. Measured 2026-10-25 on the M5 Max: a new
## 12-block town walked the desktop from Cinematic to Low in 43 s while it
## was still being built (55, 68, 72 ms at Ultra, High, Medium: steps that
## didn't help), and the four failures then held it at Low for 40 minutes.
## Now a step that didn't help is taken back from the record (no failure,
## the ceiling restored, so it climbs back once there's room) and no
## further step down is tried for DOWN_HOLD windows, doubling each time
## in a row. A sharpness step that didn't help only rules out pixels: the
## next step down is a tier.
const HELPED := 0.88
const DOWN_HOLD := 20
const DOWN_HOLD_MAX := 320
## Shared memory (Apple chips, integrated graphics): the least memory (GB)
## each tier needs, so Auto never climbs an 8 GB Mac mini into a tier that
## runs it out of memory. Discrete graphics have their own memory.
const SHARED_GB := [0.0, 7.0, 15.0, 15.0, 30.0]

## False in headless runs (servers, tests): the look stays as the project sets it.
var active := false
## Running on the Compatibility renderer (the browser, or an old graphics
## chip): Low to High, upscaled bilinearly.
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
## The current tier's detail budget (see BUDGETS and knob()).
static var budget := INACTIVE.duplicate()
## The autoload, for class scripts (null in tests and tools).
static var current: GraphicsQuality
var adapter := ""
## Why the last change happened, and the window that set it off (for the
## log, telemetry and tools/scale/quality_lab.gd).
var last_reason := ""
var last_window := {}

var _rid: RID
var _time := 0.0
var _last_us := 0
var _frames := 0
var _gpu := 0.0
var _cpu := 0.0
var _process_ms := 0.0
var _sim := 0.0
var _settle := SETTLE_WINDOWS
var _slow := 0
var _room := 0
## The highest tier Auto may use for now. A tier that proved too slow sets
## it one lower, until _patience minutes of play have gone by.
var _ceiling := CINEMATIC
var _waited := 0.0
## How many times a tier proved too slow here (sets patience()); one is
## forgiven for every HOLD_MIN minutes the look holds with nothing held
## back (no ceiling below auto_top()) and no step down. Waiting out a
## ceiling doesn't count: before (2026-10-25) it did, so the wait never
## grew past 10 minutes and a tier that was too slow came back every 10
## minutes all session, a stutter each time.
var _fails := 0
var _held := 0.0
## The sharpest render scale Auto may use for now, the same way: a scale
## that proved too slow is the cap until patience() has gone by (else the
## scale could step down and back up for ever on a machine right at the
## edge). A lower tier draws less, so a tier step down lifts the cap.
var _scale_top := 1.0
var _scale_waited := 0.0
var _scale_fails := 0
## The graphics memory in use (MB), read each window: Auto doesn't climb
## past the machine's video_mb.
var _video_mb := 0.0
## The last step down, waiting to be checked against the first window
## after it: {"tier": the tier left, "scale": the scale left, "draw": the
## draw_ms that set it off, "pixels": true for a sharpness step}. Empty
## when nothing waits.
var _check := {}
## Windows left before another step down may be tried, after one that
## didn't help; and how many in a row didn't (doubles the hold).
var _down_hold := 0
var _no_help := 0
## Fewer pixels didn't make the drawing faster here: step tiers instead,
## until there's room again.
var _pixels_no_help := false
## The hardware guess (guess_tier) for this computer.
var _guess := HIGH
var _memory_gb := 0.0
## `--quality auto` (measuring runs): don't read or write the saved setting
## or the crash marker, and judge even when the window isn't focused.
var _lab := false
## Pinned on the command line (screenshots, tests): no crash marker either.
var _pinned := false
var _beat := 0.0


func _ready() -> void:
	current = self
	adapter = RenderingServer.get_video_adapter_name()
	active = DisplayServer.get_name() != "headless"
	if not active:
		return
	browser = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	process_priority = 1000  # after the frame's own work
	_memory_gb = float(OS.get_memory_info().get("physical", 0)) / 1e9
	var cores := OS.get_processor_count()
	var want := _cmdline_tier()
	_lab = want == AUTO
	_pinned = want >= LOW
	# A measuring run can stand in for another computer's guess:
	# `--quality auto --quality-as "Apple M2,8,8"` (chip name, cores, GB).
	var stand_in := _arg("--quality-as").split(",")
	if _lab and stand_in.size() == 3:
		adapter = stand_in[0]
		cores = int(stand_in[1])
		_memory_gb = float(stand_in[2])
	var real := web_gpu_name()
	if real != "":
		adapter = real
	_guess = browser_first(adapter, is_handheld()) if browser \
		else guess_tier(adapter, RenderingServer.get_video_adapter_type(), cores, _memory_gb)
	_ceiling = auto_top()
	var saved := {} if _lab else _read()
	mode = clampi(int(saved.get("mode", AUTO)), AUTO, auto_top())
	# A tier this computer can't carry (picked by an older menu that only
	# cycled upward) goes back to Auto rather than crash it again.
	if mode > top():
		mode = AUTO
	if mode != AUTO:
		tier = mode
		scale = clampf(float(saved.get("scale", 1.0)), min_scale(), 1.0)
	elif str(saved.get("adapter", "")) == adapter and saved.has("tier") \
			and int(saved.get("guess", 1)) == GUESS_VERSION:
		_ceiling = clampi(int(saved.get("ceiling", auto_top())), LOW, auto_top())
		_fails = maxi(int(saved.get("fails", 0)), 0)
		_waited = maxf(float(saved.get("waited", 0.0)), 0.0)
		tier = clampi(int(saved.tier), LOW, _ceiling)
		scale = clampf(float(saved.get("scale", 1.0)), min_scale(), 1.0)
	else:
		_first_guess()
		_save()
	if not _lab and not _pinned:
		if FileAccess.file_exists(RUNNING_PATH) and not _other_copy_running():
			_after_crash(int(saved.get("tier", tier)))
		_heartbeat()
	if _pinned:
		mode = mini(want, BROWSER_TOP if browser else CINEMATIC)
		tier = mode
		scale = 1.0
	_rid = get_tree().root.get_viewport_rid()
	if not browser:
		RenderingServer.viewport_set_measure_render_time(_rid, true)
	apply()
	print("Graphics: ", describe())


## AUTO for `--quality auto`, a tier for `--quality low` and so on, or -2.
static func _cmdline_tier() -> int:
	var want := _arg("--quality").to_lower()
	if want == "auto":
		return AUTO
	var t := NAMES.map(func(n): return n.to_lower()).find(want)
	return t if t >= 0 else -2


## A command-line value, `--name value` or `--name=value` ("" if absent).
static func _arg(name: String) -> String:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
		var a: String = args[i]
		if a.begins_with(name + "="):
			return a.trim_prefix(name + "=")
		if a == name and i + 1 < args.size():
			return args[i + 1]
	return ""


## A phone or tablet: a small, touch-first screen in the browser.
static func is_handheld() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available() and not OS.has_feature("web_macos") \
			and not OS.has_feature("web_windows") and not OS.has_feature("web_linuxbsd"))


func min_scale() -> float:
	# 1.0, 0.85, 0.7, 0.55: whole steps, so the last one is as big as the
	# rest (a smaller last step looked like a step that didn't help).
	return 0.55 if browser else MIN_SCALE


func _first_guess() -> void:
	_ceiling = auto_top()
	_fails = 0
	_waited = 0.0
	_scale_top = 1.0
	_scale_waited = 0.0
	tier = _guess
	# Phones and tablets also start with fewer pixels.
	scale = 0.75 if browser and is_handheld() else 1.0


## The browser's first tier, from the graphics chip WebGL names (for
## example "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 ...)" or "ANGLE (Apple,
## ANGLE Metal Renderer: Apple M5 Max ...)"; see web_gpu_name()). A strong
## chip starts on the browser's top tier and steps down only when frames
## are measured slow (playtest 2026-10-25: Chrome on the M5 Max started
## on Low, with jagged shadows, and Nathan said it "feels more like I'm
## playing the old game"). A mid chip starts on Medium. A phone or tablet,
## a small chip, or a chip the browser hides starts on Low and climbs. The
## browser can't tell the computer's memory, so the chip alone decides.
static func browser_first(name: String, handheld: bool) -> int:
	if handheld:
		return LOW
	var n := name.to_lower()
	var at := n.find("apple m")
	if at >= 0:
		n = n.substr(at)
		# A Max or Ultra chip, or a Pro: the Mac Studio, the big MacBook Pro.
		# A base chip may be the 8 GB Mac mini.
		return BROWSER_TOP if "max" in n or "ultra" in n or "pro" in n else LOW
	var pc := pc_gpu_tier(n)
	if pc >= ULTRA:
		return BROWSER_TOP
	return MEDIUM if pc == HIGH else LOW


## The graphics chip's real name in the browser. Chrome's WebGL reports
## only "WebKit WebGL" as its renderer; the real name comes from the
## WEBGL_debug_renderer_info extension. "" outside the browser or when the
## browser hides it.
static func web_gpu_name() -> String:
	if not OS.has_feature("web"):
		return ""
	var got = JavaScriptBridge.eval("""(() => { try {
		const gl = document.createElement('canvas').getContext('webgl2') || document.createElement('canvas').getContext('webgl');
		const ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
		return ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : '';
	} catch (e) { return ''; } })()""", true)
	return str(got) if got != null else ""

## A first guess from the hardware alone; in Auto the governor corrects it
## in play. Apple chips share memory with the GPU, so memory says a lot.
## Windows and Linux PCs are judged by the graphics chip's name (NVIDIA
## GeForce, AMD Radeon, Intel Arc, UHD and Iris), then by type, cores and
## memory when the name is unknown.
static func guess_tier(name: String, type: int, cores: int, memory_gb: float) -> int:
	var n := name.to_lower()
	if type == RenderingDevice.DEVICE_TYPE_CPU or "llvmpipe" in n or "swiftshader" in n \
			or "microsoft basic render" in n:
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
	var by_name := pc_gpu_tier(n)
	if by_name >= LOW:
		# A big graphics card in a computer with little memory: the town
		# itself needs room, so Cinematic waits for 16 GB and more.
		if memory_gb < 15.0:
			by_name = mini(by_name, ULTRA if memory_gb >= 7.0 else HIGH)
		return by_name
	if type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		# An unknown graphics card: the governor climbs from here if it can.
		return ULTRA if cores >= 8 and memory_gb >= 15.0 else HIGH
	# Integrated graphics (Intel, AMD laptop chips) and anything unknown.
	return MEDIUM if cores >= 8 and memory_gb >= 15.0 else LOW


## A PC graphics chip's tier from its name (lower case), or -1 if the name
## isn't one we know. Rough classes by family and model number, from
## public benchmarks: a mid card of today (RTX 4060, RX 7600) is Ultra; the
## cards above it Cinematic; a few years older or a laptop's, a step or two
## lower. Laptop chips ("Laptop GPU", Max-Q, an "M" Radeon) are a step down.
static func pc_gpu_tier(n: String) -> int:
	var t := -1
	var num := func(pattern: String) -> int:
		var re := RegEx.create_from_string(pattern)
		var m := re.search(n)
		return int(m.get_string(1)) if m else -1
	var rtx: int = num.call("rtx\\s*(\\d{4})")
	var gtx: int = num.call("gtx\\s*(\\d{3,4})")
	var rx: int = num.call("rx\\s*(\\d{3,4})")
	var arc: int = num.call("arc\\(?t?m?\\)?\\s*[ab](\\d{3})")
	if rtx > 0:
		var gen := rtx / 1000
		var cls := (rtx % 100) / 10  # 4070 is 7, 3060 is 6
		if cls == 0:
			t = ULTRA  # workstation cards (RTX 4000 Ada)
		elif cls >= 7:
			t = CINEMATIC if gen >= 3 else ULTRA
		elif cls >= 6:
			t = ULTRA if gen >= 3 else HIGH
		else:
			t = HIGH
	elif "rtx a" in n or "quadro" in n:
		t = HIGH
	elif gtx > 0:
		if gtx >= 1660 or gtx == 1070 or gtx == 1080:
			t = HIGH
		elif gtx >= 960:
			t = MEDIUM
		else:
			t = LOW
	elif "geforce mx" in n or "geforce gt " in n or "geforce 9" in n:
		t = LOW
	elif rx > 0:
		if rx >= 9000:
			t = CINEMATIC if (rx % 100) / 10 >= 7 else ULTRA  # RX 9070, 9060
		elif rx >= 5000:
			var gen := rx / 1000
			var cls := (rx % 1000) / 100
			if gen >= 6 and cls >= 7:
				t = CINEMATIC
			elif gen >= 6 and cls == 6:
				t = ULTRA
			elif cls >= 6:
				t = HIGH  # RX 5600, 5700
			else:
				t = MEDIUM  # RX 5500, 6500, 6400
		elif rx >= 470:
			t = MEDIUM  # RX 470 to 590
		else:
			t = LOW
	elif "vega 56" in n or "vega 64" in n or "radeon vii" in n:
		t = HIGH
	elif "8060s" in n or "8050s" in n:
		t = HIGH  # big AMD laptop chips with a strong built-in GPU
	elif arc >= 500:
		t = HIGH  # Intel Arc A580 to A770, B570, B580
	elif arc > 0:
		t = MEDIUM  # Arc A310 to A380
	if t < LOW:
		return -1
	if "laptop" in n or "max-q" in n or RegEx.create_from_string("rx\\s*\\d{4}m").search(n) != null:
		t = maxi(t - 1, LOW)
	return t


func settings() -> Dictionary:
	return TIERS[tier]


## The current tier's share of a detail budget item (see BUDGETS), for any
## view. Headless runs and tests get INACTIVE's values.
static func knob(key: String, fallback: Variant = null) -> Variant:
	return budget.get(key, fallback)


## A count budget (cars, people) kept without sorting by distance: a view
## draws what's inside `reach`, then calls this with how many it drew.
## Over the cap, the reach shrinks to about where the cap's worth would
## have been (things spread over the ground, so the count goes with the
## square of the reach); under it, the reach grows back slowly towards
## `full`. The nearest stay drawn and the count settles under the cap.
static func fit_reach(reach: float, drawn: int, cap: int, full: float) -> float:
	if drawn > cap and drawn > 0:
		return maxf(reach * sqrt(float(cap) / drawn) * 0.95, full * 0.1)
	if drawn < cap * 0.8:
		return minf(full, reach * 1.02 + 1.0)
	return minf(full, reach)


## This kind of machine (a key of MACHINES).
func machine() -> String:
	if browser:
		return "browser"
	if _shares_memory():
		if _memory_gb < 15.0:
			return "small"
		if _memory_gb < SHARED_GB[CINEMATIC]:
			return "shared"
	return "full"


## The whole detail budget of tier t, as knob() reads it, on this kind of
## device (the browser grows detail in at most BROWSER_GROW_MS a frame and
## draws no field plants).
static func budget_for(t: int, on_browser := false) -> Dictionary:
	var b: Dictionary = BUDGETS[t].duplicate()
	var r: Dictionary = TIERS[t]
	b["detail"] = r.detail
	b["shadow_m"] = r.shadow_reach
	b["tree_shadows"] = r.tree_shadows
	if on_browser:
		b["grow_ms"] = minf(b.grow_ms, BROWSER_GROW_MS)
		b["crops"] = false
		b["crop_shadows"] = false
		b["car_detail"] = false
	return b


func describe() -> String:
	if not active:
		return "fixed (%s)" % RenderingServer.get_current_rendering_method()
	var s := "%s %s, %d%% scale" % ["Auto:" if mode == AUTO else "Fixed:", NAMES[tier], roundi(scale * 100.0)]
	if browser:
		s += " (browser)"
	if mode == AUTO and _ceiling < auto_top():
		s += ", up to %s for now" % NAMES[_ceiling]
	return s


## The Graphics setting's label, e.g. "Auto (High)" or "Cinematic".
func label() -> String:
	return "Auto (%s)" % NAMES[tier] if mode == AUTO else NAMES[mode]


## The highest tier the Graphics menu offers here: one above the hardware
## guess, so a small computer can try a step up but is never handed a tier
## that's far beyond it (Cinematic on an 8 GB Mac mini runs it out of
## memory). The browser climbs as far as High (see BROWSER_TOP).
func top() -> int:
	return BROWSER_TOP if browser else mini(_guess + 1, CINEMATIC)


## The highest tier Auto ever climbs to here: High in the browser; on the
## desktop, Cinematic, unless the graphics share too little memory with
## the town (SHARED_GB). A full-strength desktop is never held back.
func auto_top() -> int:
	if browser:
		return BROWSER_TOP
	if _shares_memory():
		var t := CINEMATIC
		while t > LOW and _memory_gb < SHARED_GB[t]:
			t -= 1
		return maxi(t, _guess)
	return CINEMATIC


func _shares_memory() -> bool:
	return adapter.to_lower().begins_with("apple") \
		or RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU


## What the Graphics menu picked: AUTO, or a fixed tier up to top().
func choose(m: int) -> void:
	m = clampi(m, AUTO, top())
	mode = m
	if mode == AUTO:
		_first_guess()
	else:
		tier = mode
	_change("picked in the Graphics menu")


## The Graphics menu's sharpness: the 3D render scale, for a fixed tier
## (Auto sets its own).
func set_scale(s: float) -> void:
	scale = clampf(s, min_scale(), 1.0)
	_change("sharpness picked in the Graphics menu")


## Pushes the tier and scale to the screen. Views listen to `changed` for
## the parts they own (SkyLight: ambient occlusion, shadow splits and reach).
func apply() -> void:
	var t: Dictionary = TIERS[tier]
	detail = t.detail
	tree_shadows = t.tree_shadows
	budget = budget_for(tier, browser)
	if not is_inside_tree():
		changed.emit()  # the governor on its own, in tests
		return
	var vp := get_tree().root
	# Antialiasing stays as this machine started (msaa()): a change of MSAA
	# recompiles every pipeline, a freeze each time the tier moved.
	var m := msaa()
	vp.msaa_3d = m
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if m == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = t.lod
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 and _fsr_ok() else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	# Low draws its shadows on a 4096 map too: on 2048 a house's shadow was a
	# staircase (playtest, Chrome on the M5 Max, 2026-10-25). A phone or
	# tablet keeps 2048 (a quarter of the memory).
	RenderingServer.directional_shadow_atlas_set_size(mini(t.shadow_size, 2048) if is_handheld() else t.shadow_size, true)
	# A faint dither before the colours are rounded to 8 bits: without it
	# the sky and the snow showed bands (same playtest). Costs next to nothing.
	vp.use_debanding = true
	RenderingServer.directional_soft_shadow_filter_set_quality(t.soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(t.soft)
	changed.emit()


func _process(delta: float) -> void:
	if active and not _lab and not _pinned and not OS.has_feature("web"):
		_beat += delta
		if _beat >= HEARTBEAT:
			_beat = 0.0
			_heartbeat()
	if not active or mode != AUTO or not _watching():
		_reset()
		_settle = SETTLE_WINDOWS
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
	# The town's thinking this frame (Main's sim steps): no tier changes it.
	var sim := minf(float(Perf.last.get("frame.sim", 0.0)), dt * 1000.0)
	_time += dt
	_frames += 1
	_sim += sim
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	# The drawing's CPU side is the renderer's own time. The engine's
	# TIME_PROCESS is logged (process_ms) but not judged: in a real window on
	# the M5 Max (2026-10-25) it read about 100 ms in 27 ms frames, so
	# counted in, the desktop never saw room and never climbed back.
	var process := maxf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 - sim, 0.0)
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid)
	_process_ms += process
	if _time < WINDOW:
		Perf.add("frame.quality", t0)
		return
	var w := {"frame_ms": snappedf(_time * 1000.0 / _frames, 0.1), "sim_ms": snappedf(_sim / _frames, 0.1),
		"gpu_ms": snappedf(_gpu / _frames, 0.1), "cpu_ms": snappedf(_cpu / _frames, 0.1),
		"process_ms": snappedf(_process_ms / _frames, 0.1)}
	w["draw_ms"] = snappedf(maxf(w.frame_ms - w.sim_ms, 0.0), 0.1)
	w["video_mb"] = roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	if _lab:
		print("Graphics window: ", NAMES[tier], " ", JSON.stringify(w))
	var played := _time
	_reset()
	_judge(w, played)
	Perf.add("frame.quality", t0)


## One window's verdict. draw_ms is the frame with the town's thinking
## taken out: what a tier can change. Judged against this kind of
## machine's budget (MACHINES).
func _judge(w: Dictionary, played: float) -> void:
	if _ceiling < auto_top():
		_waited += played
	else:
		_held += played
	if _scale_top < 0.99:
		_scale_waited += played
	if _fails > 0 and _held >= HOLD_MIN * 60.0:
		_fails -= 1
		_held = 0.0
	if _settle > 0:
		_settle -= 1
		return
	if not _check.is_empty() and _verify(w):
		return
	if _down_hold > 0:
		_down_hold -= 1
	var m: Dictionary = MACHINES[machine()]
	var slow_ms: float = m.slow_ms
	var room: bool = w.frame_ms < m.room_ms \
		and (browser or (w.gpu_ms < ROOM_PART_MS and w.cpu_ms < ROOM_PART_MS))
	# Graphics memory near the machine's budget: hold rather than climb.
	# It doesn't step down for memory: today most of it is the town's
	# buildings, which no tier changes, so a step down wouldn't free it.
	_video_mb = float(w.get("video_mb", 0.0))
	if m.video_mb > 0 and _video_mb > m.video_mb * 0.85:
		room = false
	if w.draw_ms > slow_ms:
		_room = 0
		_slow += 1
		# Far too slow steps down at once; just slow waits for another window.
		if _down_hold == 0 and (_slow >= SLOW_WINDOWS or w.draw_ms > slow_ms * 2.0):
			_slow = 0
			_step_down(w.gpu_ms > w.cpu_ms, w)
	elif room:
		_slow = 0
		_room += 1
		if _room >= ROOM_WINDOWS:
			_room = 0
			_step_up(w)
	else:
		# Between the two (or slow only from the town's thinking): hold.
		_slow = 0
		_room = 0


## Only in a town that has finished loading, in a window you're looking at.
func _watching() -> bool:
	var w := get_window()
	if (not w.has_focus() and not _lab) or w.mode == Window.MODE_MINIMIZED:
		return false
	var scene := get_tree().current_scene
	return scene != null and "loading" in scene and not scene.loading


func _reset() -> void:
	_time = 0.0
	_frames = 0
	_gpu = 0.0
	_cpu = 0.0
	_process_ms = 0.0
	_sim = 0.0


## Minutes of play before a tier that proved too slow is tried again.
func patience() -> float:
	return minf(PATIENCE_MIN * pow(2.0, maxi(_fails - 1, 0)), PATIENCE_MAX)


## Minutes before a sharpness that proved too slow is tried again: the
## same doubling, counted on its own (a scale step isn't a tier failing).
func scale_patience() -> float:
	return minf(PATIENCE_MIN * pow(2.0, maxi(_scale_fails - 1, 0)), PATIENCE_MAX)


## The graphics chip is the bottleneck: fewer pixels first. Otherwise (or
## once pixels are as low as they go) a lower tier draws less, and the tier
## it left is out of reach until patience() has gone by.
func _step_down(gpu_bound: bool, w: Dictionary) -> void:
	var left := {"tier": tier, "scale": scale, "draw": w.draw_ms, "pixels": false}
	if (gpu_bound or browser) and not _pixels_no_help and scale > min_scale() + 0.01:
		scale = maxf(min_scale(), scale - SCALE_STEP)
		_scale_top = scale
		_scale_waited = 0.0
		_scale_fails += 1
		left.pixels = true
	elif tier > LOW:
		_fails += 1
		_waited = 0.0
		_held = 0.0
		_ceiling = tier - 1
		tier -= 1
		# The lower tier draws less: its sharpness may climb back to full.
		_scale_top = 1.0
		_scale_waited = 0.0
	else:
		return
	_check = left
	last_window = w
	_change("drawing too slow (%.1f ms a frame without the town's thinking)" % w.draw_ms)


## The first window after a step down: did it make the drawing faster? If
## not, the step is taken back from the record (see HELPED). Fewer pixels
## that didn't help are given back at once; a lower tier stays until
## there's room to climb back. True when the look changed.
func _verify(w: Dictionary) -> bool:
	var c := _check
	_check = {}
	if w.draw_ms < float(c.draw) * HELPED:
		_no_help = 0
		return false
	var why := "didn't help (%.1f ms a frame, %.1f before)" % [w.draw_ms, c.draw]
	if c.pixels:
		_scale_fails = maxi(_scale_fails - 1, 0)
		_scale_top = maxf(_scale_top, float(c.scale))
		_pixels_no_help = true
		scale = float(c.scale)
		last_window = w
		_change("fewer pixels " + why)
		return true
	_fails = maxi(_fails - 1, 0)
	_ceiling = maxi(_ceiling, int(c.tier))
	_no_help += 1
	_down_hold = mini(DOWN_HOLD * (1 << (_no_help - 1)), DOWN_HOLD_MAX)
	last_reason = "a lower tier " + why
	print("Graphics: ", describe(), " (", last_reason, ")")
	_save()
	return false


func _step_up(w: Dictionary) -> void:
	_pixels_no_help = false
	if scale < _scale_top - 0.01:
		scale = minf(_scale_top, scale + SCALE_STEP)
	elif scale < 0.99 and _scale_waited >= scale_patience() * 60.0:
		# Long enough just below: try the sharpness that was too slow again.
		scale = minf(1.0, scale + SCALE_STEP)
		_scale_top = scale
		_scale_waited = 0.0
	elif scale < 0.99:
		return  # sharper first, once the wait is over; the tier waits too
	elif tier < _ceiling:
		tier += 1
	elif _ceiling < auto_top() and _waited >= patience() * 60.0:
		# Long enough at the tier below: try the one that was too slow again
		# (the town or the game may have got lighter since).
		_ceiling += 1
		_waited = 0.0
		tier += 1
	else:
		return
	last_window = w
	_change("room to spare (%.1f ms a frame)" % w.frame_ms)


func _change(why: String) -> void:
	last_reason = why
	_slow = 0
	_room = 0
	_settle = SETTLE_WINDOWS
	_reset()
	print("Graphics: ", describe(), " (", why, ")")
	apply()
	_save()


## MSAA for this machine, fixed whatever the tier (Performance, 2026-10-23:
## each MSAA change set off a storm of 120+ pipeline compiles on the Macs).
## The desktop takes it from its hardware guess; a computer's browser 2x;
## a phone none, with FXAA instead.
func msaa() -> int:
	if browser:
		return 0 if is_handheld() else 1
	return TIERS[_guess].msaa


## FSR upscaling, for fewer pixels than the screen. Not in the browser, and
## not on the Mac's Metal driver: Brawn's Mac Studio crashed within seconds
## each time it drew below 100% there (2026-10-23), so a Mac upscales
## plainly instead.
func _fsr_ok() -> bool:
	return not browser and RenderingServer.get_current_rendering_driver_name() != "metal"


## The last run ended without a clean exit. Whatever the cause, start this
## one safe: Auto, full pixels, one tier below where it died, and no higher
## for a while (the governor climbs back once patience() has gone by).
func _after_crash(died_on: int) -> void:
	mode = AUTO
	scale = 1.0
	tier = clampi(mini(died_on - 1, _guess), LOW, auto_top())
	_ceiling = maxi(tier, LOW)
	_fails += 1
	_waited = 0.0
	_save()
	print("Graphics: the last run didn't close cleanly; starting safe at ", NAMES[tier])
	# Telemetry comes up after this autoload.
	(func():
		var t := get_node_or_null("/root/Telemetry")
		if t:
			t.event("gfx_after_crash", {"died_on": NAMES[clampi(died_on, LOW, CINEMATIC)], "now": NAMES[tier]})
	).call_deferred()


## Another copy of the game is running right now (its heartbeat is fresh
## and, on the desktop, its process is alive): its marker is not a crash.
## Before this, a second copy (a test window beside the game) read as a
## crash and started the game a tier lower, held there all session.
func _other_copy_running() -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(RUNNING_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	# The browser has one tab: a reload after a crash must still count.
	if OS.has_feature("web"):
		return false
	var age := Time.get_unix_time_from_system() - float(d.get("beat", 0.0))
	if age > HEARTBEAT * 3.0:
		return false
	var pid := int(d.get("pid", 0))
	if pid <= 0 or pid == OS.get_process_id():
		return false
	var out := []
	if OS.has_feature("windows"):
		OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH"], out)
		return out.size() > 0 and str(pid) in str(out[0])
	return OS.execute("kill", ["-0", str(pid)], out) == 0


func _heartbeat() -> void:
	var f := FileAccess.open(RUNNING_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"pid": OS.get_process_id(), "beat": Time.get_unix_time_from_system()}))
		f.close()


func _exit_tree() -> void:
	if active and not _lab and not _pinned:
		DirAccess.remove_absolute(RUNNING_PATH)


func _save() -> void:
	if _lab:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "tier": tier, "scale": scale, "adapter": adapter,
			"guess": GUESS_VERSION, "ceiling": _ceiling, "fails": _fails, "waited": snappedf(_waited, 1.0)}))


static func _read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}
