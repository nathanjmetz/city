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
## Gathered events go into the outbox this often, in seconds.
const FLUSH_EVERY := 30.0
const PERF_EVERY := 15.0
## A frame longer than this is a hitch (a visible stutter).
const HITCH := 0.1
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
var _hitches := 0
var _load_start := -1.0
var _load_status := ""
var _booted := false
var _errors := {}   # signature -> count this flush
var _batch_n := 0


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
	var size := DisplayServer.screen_get_size()
	event("start", {"os": OS.get_name(), "build": build(), "screen": [size.x, size.y],
		"window": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"gpu": RenderingServer.get_video_adapter_name(), "web": _browser(), "cores": OS.get_processor_count()})


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
		tracker.click(e.position / size, over, button != null, button != null and button.disabled, now)
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
		s = str(c.name)
	var re := RegEx.create_from_string("[0-9][0-9,.]*")
	return re.sub(s.strip_edges(), "#", true).left(48)


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
	_watch_scene()
	_watch_loading(now)
	_watch_client()
	for err in _logger.take() if _logger else []:
		_error(err)
	_frames += 1
	if not LoadingScreen.is_open():
		_worst = maxf(_worst, delta)
		if delta > HITCH:
			_hitches += 1
	_perf_time += delta
	if _perf_time >= PERF_EVERY:
		_perf_sample()
	tracker.tick(now)
	_flush_time += delta
	if _flush_time >= FLUSH_EVERY:
		flush()


func _perf_sample() -> void:
	var e := {"fps": snappedf(_frames / _perf_time, 0.1), "worst_ms": int(_worst * 1000.0), "hitches": _hitches,
		"mem_mb": int(OS.get_static_memory_usage() / 1048576.0),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "scene": _scene}
	_perf_systems(e)
	if _sim and is_instance_valid(_sim) and "stats" in _sim:
		e["pop"] = int(_sim.stats.population)
		e["money"] = int(_sim.economy.money)
	event("perf", e)
	_perf_time = 0.0
	_frames = 0
	_worst = 0.0
	_hitches = 0


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
	Perf.reset_window()


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
		_sim.command_applied.connect(func(cmd: Dictionary): tracker.command(str(cmd.get("type", "")), true, _now()))
		_sim.command_refused.connect(func(cmd: Dictionary): tracker.command(str(cmd.get("type", "")), false, _now()))


func _watch_loading(now: float) -> void:
	var open := LoadingScreen.is_open()
	if open and _load_start < 0.0:
		_load_start = now
		_load_status = LoadingScreen.current._status
	elif not open and _load_start >= 0.0:
		event("load", {"what": _load_status, "s": snappedf(now - _load_start, 0.01)})
		_load_start = -1.0


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
	_send()


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
