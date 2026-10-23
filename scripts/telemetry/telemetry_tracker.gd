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
func click(pos: Vector2, over: String, button: bool, off: bool, now: float) -> void:
	_check_idle(now)
	_rage(pos, over, now)
	if over == "":
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
	context = over
	if _hunt.is_empty():
		_hunt = {"start": _look_start if _look_start >= 0.0 else now, "path": []}
	if _hunt.path.size() < PATH_MAX:
		_hunt.path.append(over)
	_hunt["last"] = now


## A key press that isn't typing. undo: Ctrl/Cmd+Z.
func key(name: String, undo: bool, now: float) -> void:
	_check_idle(now)
	if name == "Escape":
		_escape(now)
		return
	_bump(keys, name)
	if undo:
		_undos = _streak(_undos, now, UNDO_SECONDS)
		if _undos.size() == UNDO_STREAK:
			events.append({"k": "undo_streak", "t": _r(now), "n": UNDO_STREAK, "ctx": context})


## The player's action reached the game; ok is false when it was refused.
func command(type: String, ok: bool, now: float) -> void:
	if not commands.has(type):
		commands[type] = [0, 0]
	commands[type][0 if ok else 1] += 1
	if ok:
		_refusals.clear()
		return
	_refusals = _streak(_refusals, now, REFUSED_SECONDS)
	if _refusals.size() == REFUSED_STREAK:
		events.append({"k": "refused_streak", "t": _r(now), "n": REFUSED_STREAK, "cmd": type, "ctx": context})


## Called now and then so a hunt left hanging gets closed.
func tick(now: float) -> void:
	_check_idle(now)


## Hands over everything gathered so far, with a feature-use summary.
func take(now: float) -> Array:
	var out := events
	events = []
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
		events.append({"k": "esc_spam", "t": _r(now), "n": ESC_SPAM, "ctx": context})


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
		events.append({"k": "rage", "t": _r(now), "at": [_r(pos.x), _r(pos.y)], "over": over, "ctx": context})
		_rage_until = now + RAGE_SECONDS
		_recent_clicks = []


static func _streak(times: Array, now: float, window: float) -> Array:
	var out := times.filter(func(t): return now - t <= window)
	out.append(now)
	return out


static func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


static func _r(x: float) -> float:
	return snappedf(x, 0.01)
