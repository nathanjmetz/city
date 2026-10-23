extends Node
## Watches how the game gets played, so it can be made better: how many
## clicks and how much mouse travel it takes to find things, where players
## get stuck, which features get used, errors, frame rate and load times.
## An autoload (Telemetry).
##
## Privacy-light, for friends and family: no typed text, no chat, nothing
## sent anywhere but your own region server, over the connection the game
## already has. Events wait in user://telemetry/outbox.json until the
## server says it has them, so nothing is lost while it's down.
## tools/telemetry_report.gd turns the server's files into a ranked fix list.
##
##   Telemetry.event("kind", {...})   # anything else worth knowing

const OUTBOX := "user://telemetry/outbox.json"
## What hasn't gone into the outbox yet, saved every SPILL_EVERY seconds: if
## the game dies, the next launch sends it as the end of that session.
const SPILL := "user://telemetry/last.json"
const SPILL_EVERY := 2.0
## Gathered events go into the outbox this often, in seconds.
const FLUSH_EVERY := 30.0
const PERF_EVERY := 15.0
## A frame longer than this is a hitch (a visible stutter).
const HITCH := 0.1
## A frame this long (seconds) is a freeze the player sees: sent at once.
const STALL := 1.0
## A gap this long (seconds) is the game not running at all (the machine
## slept, the window was hidden or minimized), not a freeze.
const SUSPENDED := 30.0
## The outbox keeps at most this many batches (oldest dropped first).
const OUTBOX_MAX := 300
## Batches sent per flush, and how long to wait for the server to confirm.
const SEND_MAX := 5
const RESEND_AFTER := 60.0

var enabled := true
var session_id := ""
var tracker := TelemetryTracker.new()

var _logger: TelemetryLogger
var _events: Array = []
var _outbox: Array = []
var _sent := {}     # batch id -> when it went out
var _client: RegionClient
var _sim: Object
var _scene := ""
var _flush_time := 0.0
var _perf_time := 0.0
var _frames := 0
var _worst := 0.0
var _last_us := 0
## Shader pipelines compiled so far: at the last frame and the last sample.
var _pipes_frame := 0
var _pipes_sample := 0
## Neighbor towns loaded this perf window (see RegionClient.town_loaded).
var _towns := {}
var _town_at := -1.0
var _frame_ms := PackedFloat32Array()   # this window's frame times
var _quality_hooked := false
var _hitches := 0
var _load_start := -1.0
var _load_status := ""
var _load_steps := {}
var _step_status := ""
var _step_start := 0.0
var _booted := false
var _errors := {}   # signature -> count this flush
var _batch_n := 0
var _spill_time := 0.0


func _ready() -> void:
	# Tests, tools and the region server run headless: nothing to watch.
	enabled = DisplayServer.get_name() != "headless" and OS.get_environment("CITY_TELEMETRY") != "off"
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	session_id = Crypto.new().generate_random_bytes(6).hex_encode()
	_logger = TelemetryLogger.new()
	OS.add_logger(_logger)
	_load_outbox()
	_recover_spill()
	var size := DisplayServer.screen_get_size()
	event("start", {"os": OS.get_name(), "build": build(), "screen": [size.x, size.y],
		"window": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"gpu": RenderingServer.get_video_adapter_name(), "web": _browser(), "cores": OS.get_processor_count(),
		"ram_gb": snappedf(float(OS.get_memory_info().get("physical", 0)) / 1e9, 0.1),
		"renderer": RenderingServer.get_current_rendering_method(), "app": "web" if OS.has_feature("web") else "desktop"})


## Records something worth knowing (a join failure, a slow step, ...).
func event(kind: String, data := {}) -> void:
	if not enabled:
		return
	var e := data.duplicate()
	e["k"] = kind
	e["t"] = snappedf(_now(), 0.01)
	_events.append(e)


static func build() -> String:
	if ResourceLoader.exists("res://scripts/build_info.gd"):
		return str(load("res://scripts/build_info.gd").BUILD).get_slice(" ", 0)
	return "dev"


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(e: InputEvent) -> void:
	var now := _now()
	if e is InputEventMouseMotion:
		tracker.motion(e.relative.length() / _diagonal(), e.button_mask != 0, now)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var size := get_viewport().get_visible_rect().size
		var hovered := get_viewport().gui_get_hovered_control()
		var over := ""
		var button: BaseButton = null
		if hovered and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			button = _button_of(hovered)
			over = label_of(button if button else hovered)
		tracker.click(e.position / size, over, button != null, button != null and button.disabled, now,
			_world_at(e.position) if over == "" else Vector2.INF)
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tracker.release(e.position / get_viewport().get_visible_rect().size, now, _world_at(e.position))
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		tracker.scroll(["wheel_up", "wheel_down", "wheel_left", "wheel_right"][e.button_index - MOUSE_BUTTON_WHEEL_UP],
			e.factor if e.factor > 0.0 else 1.0, _camera_height(), now)
	elif e is InputEventPanGesture:
		tracker.scroll("pan", e.delta.length(), _camera_height(), now)
	elif e is InputEventMagnifyGesture:
		tracker.scroll("magnify", absf(e.factor - 1.0), _camera_height(), now)
	elif e is InputEventKey and e.pressed and not e.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return   # typing: never looked at
		var k: InputEventKey = e
		var name := OS.get_keycode_string(k.get_keycode_with_modifiers())
		tracker.key(name, k.keycode == KEY_Z and (k.ctrl_pressed or k.meta_pressed), now)


## A short name for a control, as the player sees it: its text, else its
## tooltip, else its node name. Numbers are blanked so "$1,200" and "$900"
## count as one thing.
static func label_of(c: Control) -> String:
	var s := ""
	if "text" in c and str(c.text).strip_edges() != "":
		s = str(c.text)
	elif c.tooltip_text.strip_edges() != "":
		# "Views: see the map by ..." -> "Views"
		s = c.tooltip_text.get_slice("\n", 0).get_slice(": ", 0)
	else:
		s = _inner_text(c)
		if s == "" and "icon" in c and c.icon and c.icon.resource_path != "":
			s = c.icon.resource_path.get_file().get_basename()
		if s == "":
			s = str(c.name)
			if s.begins_with("@") and c.get_parent() is Control:
				s = "%s/%s" % [str(c.get_parent().name), c.get_class()]
	var re := RegEx.create_from_string("[0-9][0-9,.]*")
	return re.sub(s.strip_edges(), "#", true).left(48)


func _camera_height() -> float:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position.y if cam else 0.0


## Where on the ground (x, z in town meters) a screen point is, or INF.
## One ray-plane test, only on clicks.
func _world_at(screen: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.INF
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	return Vector2(hit.x, hit.z) if hit != null else Vector2.INF


## A command's settings in a few words for replays: plain values as they
## are, points as their count and first point.
static func brief(cmd: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cmd:
		if k == "type":
			continue
		var v = cmd[k]
		match typeof(v):
			TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
				parts.append("%s=%s" % [k, str(v).left(24)])
			TYPE_FLOAT:
				parts.append("%s=%s" % [k, snappedf(v, 0.1)])
			TYPE_VECTOR2, TYPE_VECTOR3:
				parts.append("%s=%s" % [k, str(v.snapped(Vector3.ONE * 0.1) if v is Vector3 else v.snapped(Vector2.ONE * 0.1))])
			TYPE_ARRAY:
				parts.append("%s=[%d]" % [k, v.size()])
	return " ".join(parts).left(200)


## The first text shown inside a control (a card's caption).
static func _inner_text(n: Node, depth := 0) -> String:
	for ch in n.get_children():
		if (ch is Label or ch is RichTextLabel) and str(ch.text).strip_edges() != "":
			return str(ch.text).get_slice("\n", 0)
		if depth < 2:
			var t := _inner_text(ch, depth + 1)
			if t != "":
				return t
	return ""


static func _button_of(c: Control) -> BaseButton:
	var n: Node = c
	for i in 4:
		if n is BaseButton:
			return n
		n = n.get_parent()
		if n == null or not n is Control:
			break
	return null


func _diagonal() -> float:
	return maxf(get_viewport().get_visible_rect().size.length(), 1.0)


func _process(delta: float) -> void:
	var now := _now()
	if not _booted:
		_booted = true
		var boot := {"engine_ms": Time.get_ticks_msec(), "page_ms": _page_ms()}
		boot.merge(_web_load())
		event("boot", boot)
		_hook_quality()
	_watch_scene()
	_watch_loading(now)
	_watch_client()
	for err in _logger.take() if _logger else []:
		_error(err)
	# The engine caps delta at a few physics steps (about 150 ms), so a long
	# freeze would hide inside it: time frames on the wall clock instead.
	var us := Time.get_ticks_usec()
	var dt := delta if _last_us == 0 else (us - _last_us) / 1000000.0
	_last_us = us
	var pipes := _pipelines()
	var compiled := pipes - _pipes_frame
	_pipes_frame = pipes
	if dt > SUSPENDED:
		event("suspended", {"s": snappedf(dt, 0.1)})
		dt = delta
	_frames += 1
	if not LoadingScreen.is_open():
		_worst = maxf(_worst, dt)
		_frame_ms.append(dt * 1000.0)
		if dt > HITCH:
			_hitches += 1
		if dt > STALL:
			_stall(dt, compiled)
	_perf_time += dt
	if _perf_time >= PERF_EVERY:
		_perf_sample()
	tracker.tick(now, _camera_height())
	_flush_time += dt
	_spill_time += dt
	if _flush_time >= FLUSH_EVERY:
		flush()
	elif _spill_time >= SPILL_EVERY:
		_spill()


func _perf_sample() -> void:
	var e := {"fps": snappedf(_frames / _perf_time, 0.1), "worst_ms": int(_worst * 1000.0), "hitches": _hitches,
		"mem_mb": int(Playtest.memory_mb()),
		"vram_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"free_mb": int(OS.get_memory_info().get("available", 0) / 1048576.0),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "scene": _scene}
	if not _frame_ms.is_empty():
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		e["p50_ms"] = snappedf(sorted[sorted.size() / 2], 0.1)
		e["p95_ms"] = snappedf(sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], 0.1)
	_frame_ms.clear()
	e.merge(_quality_now())
	_perf_systems(e)
	e["pipelines"] = _pipes_frame - _pipes_sample
	_pipes_sample = _pipes_frame
	if not _towns.is_empty():
		e["towns"] = _towns
		_towns = {}
	if _sim and is_instance_valid(_sim) and "stats" in _sim:
		e["pop"] = int(_sim.stats.population)
		e["money"] = int(_sim.economy.money)
	event("perf", e)
	_perf_time = 0.0
	_frames = 0
	_worst = 0.0
	_hitches = 0


## A freeze: how long, where the player was, and the Perf stages with the
## longest single run since the last sample (the freeze is among them when
## the code that froze is timed). Flushed at once in case it happens again.
func _stall(dt: float, compiled: int) -> void:
	var stages := []
	for key in Perf.stats:
		if (key.begins_with("frame.") or key.begins_with("sim.")) and Perf.stats[key].n > 0:
			stages.append([key, Perf.stats[key].max])
	stages.sort_custom(func(a, b): return a[1] > b[1])
	var top := {}
	for st in stages.slice(0, 5):
		top[st[0]] = snappedf(st[1], 0.1)
	var e := {"ms": int(dt * 1000.0), "scene": _scene, "ctx": tracker.context, "stages": top,
		"pipelines": compiled}
	# Whether a neighbor's town had just been loaded (seconds before the freeze ended).
	if _town_at >= 0.0:
		e["since_town_s"] = snappedf(_now() - _town_at, 0.1)
	event("stall", e)
	flush()


## Shader pipelines compiled since start (first use of a material, a light
## or a graphics tier): compiling stalls the frame, on Metal for seconds.
static func _pipelines() -> int:
	var n := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(info)
	return n


## Per-system timings from Perf for this window: the sim tick (mean and
## worst), the worst frame.sim, and the three costliest sim.* systems.
func _perf_systems(e: Dictionary) -> void:
	var tick: Dictionary = Perf.stats.get("sim.tick", {})
	if not tick.is_empty() and tick.n > 0:
		e["tick_ms"] = snappedf(tick.sum / tick.n, 0.01)
		e["tick_max_ms"] = snappedf(tick.max, 0.01)
	var frame_sim: Dictionary = Perf.stats.get("frame.sim", {})
	if not frame_sim.is_empty() and frame_sim.n > 0:
		e["frame_sim_max_ms"] = snappedf(frame_sim.max, 0.01)
	var systems := []
	for key in Perf.stats:
		if key.begins_with("sim.") and key != "sim.tick" and Perf.stats[key].n > 0:
			systems.append([key, Perf.stats[key].sum / Perf.stats[key].n])
	systems.sort_custom(func(a, b): return a[1] > b[1])
	var top := {}
	for s in systems.slice(0, 3):
		top[s[0]] = snappedf(s[1], 0.01)
	if not top.is_empty():
		e["top_sim"] = top
	# The frame.* stages with the worst single frame: what a hitch was doing.
	var stages := []
	for key in Perf.stats:
		if key.begins_with("frame.") and Perf.stats[key].n > 0:
			stages.append([key, Perf.stats[key].max])
	stages.sort_custom(func(a, b): return a[1] > b[1])
	var worst := {}
	for s in stages.slice(0, 3):
		worst[s[0]] = snappedf(s[1], 0.1)
	if not worst.is_empty():
		e["worst_frame"] = worst
	Perf.reset_window()


## The graphics tier, render scale and what the graphics chip and the CPU
## spend on the last frame (desktop; the browser can't time the chip).
func _quality_now() -> Dictionary:
	var q := get_node_or_null("/root/Quality")
	if q == null or not q.active:
		return {}
	var out := {"tier": GraphicsQuality.NAMES[q.tier], "auto": q.mode == GraphicsQuality.AUTO, "scale": snappedf(q.scale, 0.01)}
	var vp := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	if gpu > 0.0:
		out["gpu_ms"] = snappedf(gpu, 0.1)
	# Always sent: some drivers (Metal) give no chip timing, and then the
	# CPU side is what tells a slow sim or view from a slow chip.
	out["cpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp), 0.1)
	out["process_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1)
	return out


func _hook_quality() -> void:
	var q := get_node_or_null("/root/Quality")
	if q == null or _quality_hooked:
		return
	_quality_hooked = true
	# Send a tier change at once: if the new tier stalls the machine, the
	# report still shows what it was switched to.
	q.changed.connect(func():
		event("quality", _quality_now())
		flush())
	event("quality", _quality_now())


func _error(err: Dictionary) -> void:
	var sig := "%s:%d %s" % [err.file, err.line, err.msg.left(80)]
	var n := int(_errors.get(sig, 0))
	_errors[sig] = n + 1
	if n == 0:
		err["sig"] = sig
		err["ctx"] = tracker.context
		event("error", err)


func _watch_scene() -> void:
	var s := get_tree().current_scene
	var name := str(s.scene_file_path.get_file().get_basename()) if s else ""
	if name == _scene:
		return
	_scene = name
	_sim = null
	event("scene", {"name": name})
	if s and "sim" in s and s.sim is CitySim:
		_sim = s.sim
		_sim.command_applied.connect(func(cmd: Dictionary): tracker.command(str(cmd.get("type", "")), true, _now(), brief(cmd)))
		_sim.command_refused.connect(func(cmd: Dictionary): tracker.command(str(cmd.get("type", "")), false, _now(), brief(cmd)))
		# What each tool tells the player (its hint line), for replays.
		for n in s.get_children():
			if n.has_signal("hint_changed"):
				n.hint_changed.connect(func(text): tracker.hint(str(text), _now()))


func _watch_loading(now: float) -> void:
	var open := LoadingScreen.is_open()
	if open and _load_start < 0.0:
		_load_start = now
		_load_status = LoadingScreen.current._status
		_load_steps = {}
		_step_status = _load_status
		_step_start = now
	elif open and LoadingScreen.current._status != _step_status:
		_end_step(now)
		_step_status = LoadingScreen.current._status
	elif not open and _load_start >= 0.0:
		_end_step(now)
		var e := {"what": _load_status, "s": snappedf(now - _load_start, 0.01), "steps": _load_steps}
		# Joining a region: how long the link took to open, and the welcome
		# to arrive and be unpacked.
		if Session.client and not Session.client.join_marks.is_empty():
			e["net"] = Session.client.join_marks.duplicate()
		event("load", e)
		_load_start = -1.0


## Each status the loading screen showed, and how long it showed it.
func _end_step(now: float) -> void:
	if _step_status != "":
		_load_steps[_step_status] = snappedf(float(_load_steps.get(_step_status, 0.0)) + now - _step_start, 0.01)
	_step_start = now


## Follows the region connection: join failures, drops, and the server's
## receipts for sent batches.
func _watch_client() -> void:
	var c: RegionClient = Session.client
	if c == _client:
		return
	_client = c
	_sent.clear()
	if c == null:
		return
	var started := _now()
	c.failed.connect(func(reason: String): event("join_fail", {"reason": reason, "s": snappedf(_now() - started, 0.01)}))
	c.joined.connect(func():
		event("joined", {"s": snappedf(_now() - started, 0.01)})
		_send())
	c.disconnected.connect(func(): event("dropped"))
	c.telemetry_acked.connect(_acked)
	c.town_loaded.connect(_town_loaded)


func _town_loaded(id: String, bytes: int, unpack_ms: float, load_ms: float) -> void:
	_town_at = _now()
	var key := id if id != "" else "region"
	_towns["n"] = int(_towns.get("n", 0)) + 1
	_towns["kb"] = int(_towns.get("kb", 0)) + bytes / 1024
	_towns["unpack_max_ms"] = snappedf(maxf(float(_towns.get("unpack_max_ms", 0.0)), unpack_ms), 0.1)
	_towns["load_max_ms"] = snappedf(maxf(float(_towns.get("load_max_ms", 0.0)), load_ms), 0.1)
	_towns["load_ms"] = snappedf(float(_towns.get("load_ms", 0.0)) + unpack_ms + load_ms, 0.1)
	var from: Dictionary = _towns.get("from", {})
	from[key] = int(from.get(key, 0)) + 1
	_towns["from"] = from


## Moves what's gathered into the outbox, saves it, and sends what it can.
func flush() -> void:
	if not enabled:
		return
	_flush_time = 0.0
	var events := _events
	_events = []
	events.append_array(tracker.take(_now()))
	for sig in _errors:
		if _errors[sig] > 1:
			events.append({"k": "error_count", "t": snappedf(_now(), 0.01), "sig": sig, "n": _errors[sig]})
	_errors = {}
	if not events.is_empty():
		_batch_n += 1
		_outbox.append({"id": "%s-%d" % [session_id, _batch_n], "session": session_id, "build": build(),
			"player": _player_id(), "events": events})
		while _outbox.size() > OUTBOX_MAX:
			_outbox.pop_front()
		_save_outbox()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SPILL))
	_send()


## Saves what's gathered since the last flush (and the recent actions), so a
## crash or a force quit loses at most SPILL_EVERY seconds.
func _spill() -> void:
	_spill_time = 0.0
	var events := _events.duplicate()
	if not tracker.actions.is_empty():
		events.append({"k": "actions", "t": snappedf(_now(), 0.01), "a": tracker.actions.duplicate()})
	if events.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(SPILL.get_base_dir())
	var f := FileAccess.open(SPILL, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"session": session_id, "build": build(), "player": _player_id(),
			"t": snappedf(_now(), 0.01), "events": events}))


## The last session didn't close: it crashed, hung and was force quit, or the
## machine went down. Its saved tail goes out as that session's last batch,
## marked so the report counts it.
func _recover_spill() -> void:
	if not FileAccess.file_exists(SPILL):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SPILL))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SPILL))
	if typeof(d) != TYPE_DICTIONARY or not d.get("events") is Array:
		return
	var events: Array = d.events
	var last := []
	for e in events:
		if e is Dictionary and e.get("k") == "actions" and e.get("a") is Array:
			last = e.a
	events.append({"k": "crashed", "t": d.get("t", 0.0), "replay": last.slice(-TelemetryTracker.REPLAY_MAX)})
	_outbox.append({"id": "%s-end" % str(d.get("session", "")), "session": str(d.get("session", "")),
		"build": str(d.get("build", "")), "player": str(d.get("player", "")), "events": events})
	_save_outbox()


func _player_id() -> String:
	var session := get_node_or_null("/root/Session")
	return str(session.profile.get("id", "")) if session else ""


func _send() -> void:
	var session := get_node_or_null("/root/Session")
	if session == null or not session.online():
		return
	var n := 0
	for b in _outbox:
		if n >= SEND_MAX:
			break
		if _sent.has(b.id) and _now() - float(_sent[b.id]) < RESEND_AFTER:
			continue
		Session.client.send_telemetry(b)
		_sent[b.id] = _now()
		n += 1


func _acked(id: String) -> void:
	_sent.erase(id)
	for i in _outbox.size():
		if _outbox[i].id == id:
			_outbox.remove_at(i)
			_save_outbox()
			return


func _load_outbox() -> void:
	if not FileAccess.file_exists(OUTBOX):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(OUTBOX))
	if typeof(d) == TYPE_ARRAY:
		_outbox = d


func _save_outbox() -> void:
	DirAccess.make_dir_recursive_absolute(OUTBOX.get_base_dir())
	var f := FileAccess.open(OUTBOX, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_outbox))


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
		_logger = null
	flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


## Web only: the browser and how long the page took to reach the first
## frame (the download included).
func _browser() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("navigator.userAgent", true)).left(200)
	return ""


## Web only: download time (until the last byte), start time (from then
## until the engine was up) and the download size, from web/shell.html.
func _web_load() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var d = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.nbLoad || {})", true)))
	if typeof(d) != TYPE_DICTIONARY or float(d.get("start", 0)) <= 0.0:
		return {}
	var out := {"bytes": int(d.get("bytes", 0))}
	if float(d.downloaded) > 0.0:
		out["download_ms"] = int(float(d.downloaded) - float(d.start))
		if float(d.started) > 0.0:
			out["start_ms"] = int(float(d.started) - float(d.downloaded))
	return out


func _page_ms() -> int:
	if OS.has_feature("web"):
		return int(JavaScriptBridge.eval("Math.round(performance.now())", true))
	return 0
