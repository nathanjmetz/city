class_name LoadGate
extends RefCounted
## Keeps the loading screen up until the views that stream in (land,
## streets, buildings, trees, fields, farmsteads) have drawn everything the
## starting camera can see, so the game opens whole instead of filling in
## while you watch. Each view offers a cheap `is_drawn() -> bool`; main.gd
## watches them and waits here. Far, haze-distance things may keep
## streaming afterward.
##
## While waiting nobody is playing, so views draw with a bigger budget
## per frame (LoadGate.ms()). A time cap reveals the game anyway, so a slow
## computer never hangs, and logs which views were not ready.

## Most seconds to wait: desktop, browser.
const CAP_S := 20.0
const CAP_S_WEB := 30.0
## Milliseconds a view may spend per frame while the screen is up.
const FRAME_MS := 20.0
## Frames in a row everything must read ready (a view may need a frame to
## pick up what the one before it did).
const CALM_FRAMES := 2

## True while a gate is waiting; views widen their budgets.
static var loading := false
## How long the last wait took (ms), whether it ended ready or on the cap, and
## the names of the views still not ready then (for tests and the log).
static var last_ms := 0
static var last_missing: Array = []

var _watched: Array = []  # [name, Callable]


## `ms` for a view's per-frame budget: the bigger share while loading
## (`boosted` for a view with a lot to draw, such as the buildings).
static func ms(normal: float, boosted := FRAME_MS) -> float:
	return maxf(normal, boosted) if loading else normal


## Adds a view's readiness check (a Callable returning bool).
func watch(view_name: String, check: Callable) -> void:
	if check.is_valid():
		_watched.append([view_name, check])


## Names of the views not yet drawn.
func missing() -> Array:
	var out := []
	for w in _watched:
		if not w[1].call():
			out.append(w[0])
	return out


## Waits (a coroutine) until every watched view is drawn, or the cap runs out.
## `progress` is called with 0..1 and a status line as views finish.
func wait(tree: SceneTree, progress: Callable) -> void:
	loading = true
	var start := Time.get_ticks_msec()
	var cap_ms := int((CAP_S_WEB if OS.has_feature("web") else CAP_S) * 1000.0)
	var calm := 0
	var left := _watched.duplicate()
	var when := {}  # view -> ms it was first seen drawn (for the log)
	while true:
		await tree.process_frame
		left = _watched.filter(func(w): return not w[1].call())
		for w in _watched:
			if not when.has(w[0]) and not left.any(func(l): return l[0] == w[0]):
				when[w[0]] = Time.get_ticks_msec() - start
		var share := 1.0 - float(left.size()) / float(maxi(_watched.size(), 1))
		if progress.is_valid():
			progress.call(share, "Drawing your town…" if left.is_empty() or left.size() > 1 \
				else "Drawing your town… (%s)" % left[0][0])
		calm = calm + 1 if left.is_empty() else 0
		if calm >= CALM_FRAMES:
			break
		if Time.get_ticks_msec() - start > cap_ms:
			break
	loading = false
	last_ms = Time.get_ticks_msec() - start
	last_missing = left.map(func(w): return w[0])
	if last_missing.is_empty():
		print("LoadGate: drawn after %d ms (%s)" % [last_ms, ", ".join(when.keys().map(func(k): return "%s %d" % [k, when[k]]))])
	else:
		print("LoadGate: capped after %d ms; not drawn: %s" % [last_ms, ", ".join(last_missing)])
