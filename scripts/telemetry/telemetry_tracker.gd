class_name TelemetryTracker
extends RefCounted
## Turns raw input into play events: how long and how many clicks it takes
## to find a tool or menu item (a "hunt"), stuck moments (rage clicks,
## Escape spam, undo streaks, the game saying no again and again), and how
## often each feature is used. Pure logic with no engine input, so tests can
## drive it; Telemetry (the autoload) feeds it.
##
## Times are seconds since the session started. Click positions are
## fractions of the screen (0..1), mouse travel is in screen diagonals, so
## numbers compare across screen sizes. Typed text is never seen here.

## A hunt with no click for this long is over (the player wandered off).
const HUNT_IDLE := 30.0
## Rage click: this many clicks, this close together in time and space.
const RAGE_CLICKS := 4
const RAGE_SECONDS := 1.5
const RAGE_SPREAD := 0.03
## Escape pressed this many times this fast: trying to get out of something.
const ESC_SPAM := 3
const ESC_SECONDS := 2.0
## Undo this many times this fast: something went wrong.
const UNDO_STREAK := 3
const UNDO_SECONDS := 10.0
## The game turned down this many actions this fast.
const REFUSED_STREAK := 3
const REFUSED_SECONDS := 20.0
## Most labels kept in one hunt's path.
const PATH_MAX := 10
## Build something, then tear the same kind of thing down this soon: a redo.
const REDO_SECONDS := 30.0
## Redos this many times this fast: the tool keeps doing the wrong thing.
const REDO_STREAK := 2
const REDO_WINDOW := 120.0
## Pick a tool and back out without doing anything, this many times this fast.
const CANCEL_STREAK := 3
const CANCEL_SECONDS := 90.0
## This many clicks on the map with a tool in hand and nothing built.
const NO_PROGRESS_CLICKS := 15
## A flagged moment carries the actions of the last this-many seconds...
const REPLAY_SECONDS := 90.0
const REPLAY_MAX := 120
## ...and moments are kept at most this often.
const REPLAY_GAP := 20.0
## Most actions kept between take()s (the oldest go first).
const ACTIONS_MAX := 4000

## Finished events, oldest first. Telemetry takes them with take().
var events: Array = []
## Feature use since the last take(): label -> presses.
var buttons := {}
## Keyboard shortcuts since the last take(): key name -> presses.
var keys := {}
## Game commands since the last take(): type -> [done, refused].
var commands := {}
## Clicks on disabled buttons and on bare panels since the last take():
## label -> clicks. Both mean "I expected this to do something".
var disabled := {}
var dead := {}
## The last button pressed: the tool or menu the player is in, as context.
var context := ""
## Everything the player did, in order, for replays: [time, kind, ...].
## kinds: "b" button (label), "c" map click (screen x, y, world x, z),
## "d" map drag (from x, z, to x, z), "k" key, "x" command (type, ok, brief),
## "h" what the tool's hint said, "s" a burst of scrolling or a gesture
## (kind, events, total amount, camera height before, after).
var actions: Array = []

var _hunt := {}
## When the player started looking (first mouse move after the last world
## click), and the clicks and travel since then.
var _look_start := -1.0
var _clicks := 0
var _travel := 0.0
var _recent_clicks: Array = []   # [time, Vector2]
var _rage_until := -1.0
var _escapes: Array = []
var _undos: Array = []
var _refusals: Array = []
var _recent: Array = []      # actions of the last REPLAY_SECONDS
var _last_replay := -1000.0
var _builds: Array = []      # [time, type] of recent builds and placements
var _redos: Array = []
var _cancels: Array = []     # [time, tool]
var _tool_done := true       # the tool in hand has done something
var _idle_clicks := 0        # map clicks since the last command that went through
var _press := {}             # where the last map press was
var _last_hint := ""
var _scroll := {}            # the scroll burst going on
## Scroll events this close together are one burst.
const SCROLL_GAP := 0.4
## This many scroll bursts that didn't move the camera, this fast.
const DEAD_SCROLLS := 3
const DEAD_SCROLL_SECONDS := 30.0
var _dead_scrolls: Array = []
## A tool is in hand (its hint line is showing). Before any hint arrives
## (tests, scenes without tools) a picked button counts as a tool.
var _tool_on := true


## Mouse moved by rel (screen diagonals). Drags (a button held) are camera
## moves or drawing, not looking around, so they don't count as travel.
func motion(rel: float, held: bool, now: float) -> void:
	if held:
		return
	if _look_start < 0.0:
		_look_start = now
	_travel += rel


## A left click. over: label of the control under the mouse ("" over the
## world); button: it's a button; off: that button is disabled.
func click(pos: Vector2, over: String, button: bool, off: bool, now: float, world := Vector2.INF) -> void:
	_check_idle(now)
	_rage(pos, over, now)
	if over == "":
		_act(now, ["c", _r(pos.x), _r(pos.y)] + _xz(world))
		_press = {"t": now, "pos": pos, "world": world}
		if context != "" and _tool_on:
			_idle_clicks += 1
			if _idle_clicks == NO_PROGRESS_CLICKS:
				_flag({"k": "no_progress", "n": NO_PROGRESS_CLICKS, "ctx": context}, now)
		_world_click(now)
		return
	_clicks += 1
	if not button:
		_bump(dead, over)
		return
	if off:
		_bump(disabled, over)
		return
	_bump(buttons, over)
	_act(now, ["b", over])
	_tool_done = false
	context = over
	if _hunt.is_empty():
		_hunt = {"start": _look_start if _look_start >= 0.0 else now, "path": []}
	if _hunt.path.size() < PATH_MAX:
		_hunt.path.append(over)
	_hunt["last"] = now


## A key press that isn't typing. undo: Ctrl/Cmd+Z.
func key(name: String, undo: bool, now: float) -> void:
	_check_idle(now)
	_act(now, ["k", name])
	if name == "Escape":
		_escape(now)
		return
	_bump(keys, name)
	if undo:
		_undos = _streak(_undos, now, UNDO_SECONDS)
		if _undos.size() == UNDO_STREAK:
			_flag({"k": "undo_streak", "n": UNDO_STREAK, "ctx": context}, now)


## The player's action reached the game; ok is false when it was refused.
## brief: the command's settings, short (see Telemetry.brief).
func command(type: String, ok: bool, now: float, brief := "") -> void:
	if not commands.has(type):
		commands[type] = [0, 0]
	commands[type][0 if ok else 1] += 1
	_act(now, ["x", type, ok, brief])
	if ok:
		_refusals.clear()
		_tool_done = true
		_idle_clicks = 0
		_redo_check(type, now)
		return
	_refusals = _streak(_refusals, now, REFUSED_SECONDS)
	if _refusals.size() == REFUSED_STREAK:
		_flag({"k": "refused_streak", "n": REFUSED_STREAK, "cmd": type, "ctx": context}, now)


## A wheel notch, a trackpad or Magic Mouse pan, or a pinch. Bursts become
## one action with the camera height before and after, so a scroll that
## didn't zoom shows up.
func scroll(kind: String, amount: float, height: float, now: float) -> void:
	if not _scroll.is_empty() and (_scroll.kind != kind or now - float(_scroll.last) > SCROLL_GAP):
		_end_scroll(now)
	if _scroll.is_empty():
		_scroll = {"start": now, "kind": kind, "n": 0, "sum": 0.0, "from": height}
		_bump(keys, kind)
	_scroll.n += 1
	_scroll.sum += amount
	_scroll.last = now
	_scroll.to = height


func _end_scroll(now: float) -> void:
	var b := _scroll
	_scroll = {}
	_act(float(b.start), ["s", b.kind, b.n, _r(b.sum), snappedf(b.from, 0.1), snappedf(b.to, 0.1)])
	# Scrolling again and again with the camera staying put: zoom isn't
	# answering this mouse.
	if b.n >= 2 and absf(float(b.from) - float(b.to)) < 0.5 and float(b.from) > 0.0:
		_dead_scrolls = _streak(_dead_scrolls, now, DEAD_SCROLL_SECONDS)
		if _dead_scrolls.size() == DEAD_SCROLLS:
			_flag({"k": "scroll_dead", "n": DEAD_SCROLLS, "kind": b.kind, "ctx": context}, now)
	else:
		_dead_scrolls.clear()


## The left button came up. A press that moved on the map was a drag.
func release(pos: Vector2, now: float, world := Vector2.INF) -> void:
	if _press.is_empty():
		return
	if pos.distance_to(_press.pos) > 0.01:
		_act(now, ["d"] + _xz(_press.world) + _xz(world))
	_press = {}


## The tool's hint line changed: what the game is telling the player.
## Numbers are blanked, so a size readout changing isn't a new hint.
func hint(text: String, now: float) -> void:
	var on := text.strip_edges() != ""
	if _tool_on and not on:
		_cancel(now)   # the tool was put down (Escape, right click)
	_tool_on = on
	if not on:
		_last_hint = ""
	var t := RegEx.create_from_string("[0-9][0-9,.]*").sub(text.strip_edges(), "#", true).left(120)
	if t == _last_hint or t == "":
		return
	_last_hint = t
	_act(now, ["h", t])


## Built then torn down: building or placing something, then removing
## the same kind of thing soon after.
func _redo_check(type: String, now: float) -> void:
	if type.begins_with("build_") or type.begins_with("place_") or type.begins_with("paint_") or type == "zone_frontage":
		_builds.append([now, type])
		_builds = _builds.filter(func(b): return now - b[0] <= REDO_SECONDS)
		return
	if not (type.begins_with("remove_") or type == "clear" or type.begins_with("bulldoze")):
		return
	var built := _builds.filter(func(b): return now - b[0] <= REDO_SECONDS)
	if built.is_empty():
		return
	_builds.clear()
	_redos = _streak(_redos, now, REDO_WINDOW)
	if _redos.size() == REDO_STREAK:
		_flag({"k": "redo_loop", "n": REDO_STREAK, "cmd": built.back()[1], "ctx": context}, now)


## Called now and then so a hunt left hanging gets closed.
## height: the camera's height now, so a scroll burst ends with where the
## camera settled (it glides to its zoom).
func tick(now: float, height := 0.0) -> void:
	_check_idle(now)
	if not _scroll.is_empty() and now - float(_scroll.last) > SCROLL_GAP:
		_scroll.to = height
		_end_scroll(now)


## Hands over everything gathered so far, with a feature-use summary.
func take(now: float) -> Array:
	var out := events
	events = []
	if not actions.is_empty():
		out.append({"k": "actions", "t": _r(now), "a": actions})
		actions = []
	if not (buttons.is_empty() and keys.is_empty() and commands.is_empty() and disabled.is_empty() and dead.is_empty()):
		out.append({"k": "use", "t": _r(now), "buttons": buttons, "keys": keys, "cmds": commands,
			"disabled": disabled, "dead": dead})
		buttons = {}
		keys = {}
		commands = {}
		disabled = {}
		dead = {}
	return out


func _world_click(now: float) -> void:
	_end_hunt("used", now)


func _escape(now: float) -> void:
	_end_hunt("escape", now)
	_escapes = _streak(_escapes, now, ESC_SECONDS)
	if _escapes.size() == ESC_SPAM:
		_flag({"k": "esc_spam", "n": ESC_SPAM, "ctx": context}, now)
	_cancel(now)


## The tool in hand was put down; with nothing done, that's a cancel.
func _cancel(now: float) -> void:
	if context != "" and not _tool_done:
		_cancels.append([now, context])
		_cancels = _cancels.filter(func(c): return now - c[0] <= CANCEL_SECONDS and c[1] == context)
		if _cancels.size() == CANCEL_STREAK:
			_flag({"k": "cancel_loop", "n": CANCEL_STREAK, "ctx": context}, now)
			_cancels.clear()
	_tool_done = true
	_idle_clicks = 0


func _check_idle(now: float) -> void:
	if not _hunt.is_empty() and now - float(_hunt.last) > HUNT_IDLE:
		_end_hunt("idle", float(_hunt.last))


## A hunt ends when the player uses what they found (clicks in the world),
## backs out (Escape), or wanders off. The target is the last thing pressed.
func _end_hunt(how: String, now: float) -> void:
	if not _hunt.is_empty():
		var end: float = now if how != "used" else float(_hunt.last)
		events.append({"k": "hunt", "t": _r(_hunt.start), "target": _hunt.path.back(), "path": _hunt.path,
			"s": _r(maxf(end - float(_hunt.start), 0.0)), "clicks": _clicks, "travel": _r(_travel), "end": how})
	_hunt = {}
	_look_start = -1.0
	_clicks = 0
	_travel = 0.0


func _rage(pos: Vector2, over: String, now: float) -> void:
	var keep: Array = []
	for c in _recent_clicks:
		if now - c[0] <= RAGE_SECONDS and c[1].distance_to(pos) <= RAGE_SPREAD:
			keep.append(c)
	keep.append([now, pos])
	_recent_clicks = keep
	if keep.size() >= RAGE_CLICKS and now > _rage_until:
		_flag({"k": "rage", "at": [_r(pos.x), _r(pos.y)], "over": over, "ctx": context}, now)
		_rage_until = now + RAGE_SECONDS
		_recent_clicks = []


## A stuck moment: the event, with the last REPLAY_SECONDS of actions
## attached (unless one was kept moments ago).
func _flag(e: Dictionary, now: float) -> void:
	e["t"] = _r(now)
	if now - _last_replay >= REPLAY_GAP:
		_last_replay = now
		e["replay"] = _recent.slice(maxi(_recent.size() - REPLAY_MAX, 0))
	events.append(e)


func _act(now: float, a: Array) -> void:
	a.insert(0, _r(now))
	if actions.size() < ACTIONS_MAX:
		actions.append(a)
	_recent.append(a)
	while not _recent.is_empty() and now - float(_recent[0][0]) > REPLAY_SECONDS:
		_recent.pop_front()


static func _xz(p: Vector2) -> Array:
	return [] if p == Vector2.INF else [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]


static func _streak(times: Array, now: float, window: float) -> Array:
	var out := times.filter(func(t): return now - t <= window)
	out.append(now)
	return out


static func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


static func _r(x: float) -> float:
	return snappedf(x, 0.01)
