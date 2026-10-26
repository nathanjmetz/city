class_name UiScale
extends RefCounted
## How big the interface draws. The game is laid out for a 1600 x 900
## window; on a bigger or sharper screen Auto draws everything larger
## (2560 x 1440 at 160%, a 3440 x 1440 ultrawide at 160% with room to
## spare), and never below 100%, so a 1280 laptop keeps full-size text and
## the top bar makes room instead (Hud). Nathan, 2026-10-09: "We can't just
## build things for one monitor size." The critic (2026-10-26) found nothing
## grew on a 2560 or 3440 monitor and the top bar fell off a 1280 one.
## The player can pick a fixed size in the top bar's Display menu; it's
## saved with the other look settings (user://look.json, see DayNight).
## Set on the window at run time (Window.content_scale_factor): 2D and the
## interface scale, the 3D town still draws at the screen's own sharpness.

const AUTO := 0.0
## Auto, then the fixed sizes Display offers.
const SIZES := [AUTO, 0.9, 1.0, 1.25, 1.5, 2.0]
## The window the interface was laid out for, by height; and the narrowest
## the layout may get before Auto stops growing it.
const BASE_HEIGHT := 900.0
const MIN_WIDTH := 1280.0
const MAX_AUTO := 2.0

## What the player picked: AUTO or a size from SIZES.
static var choice := AUTO
static var _loaded := false
static var _window: Window


## The scale for a window `px` big: the player's pick, or Auto's.
static func factor_for(px: Vector2i, pick := choice) -> float:
	if pick != AUTO:
		return pick
	if px.x <= 0 or px.y <= 0:
		return 1.0
	var f := minf(px.y / BASE_HEIGHT, px.x / MIN_WIDTH)
	return clampf(snappedf(f, 0.05), 1.0, MAX_AUTO)


## Follows the game's window: scales it now and whenever it's resized.
static func watch(w: Window) -> void:
	load_settings()
	_window = w
	if not w.size_changed.is_connected(apply):
		w.size_changed.connect(apply)
	apply()


## Puts the scale on the window (after a resize or a new pick).
static func apply() -> void:
	if _window == null or not is_instance_valid(_window):
		return
	var f := factor_for(_window.size)
	if not is_equal_approx(_window.content_scale_factor, f):
		_window.content_scale_factor = f


## The scale the window draws at now.
static func current() -> float:
	return _window.content_scale_factor if _window != null and is_instance_valid(_window) else 1.0


static func set_choice(f: float) -> void:
	choice = f
	_save()
	apply()


## "Auto" or "125%".
static func text(f: float) -> String:
	return "Auto" if f == AUTO else "%d%%" % roundi(f * 100.0)


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var data = _read()
	var f := float(data.get("ui_size", AUTO))
	choice = f if SIZES.has(f) else AUTO


static func _save() -> void:
	var data := _read()
	data["ui_size"] = choice
	var f := FileAccess.open(DayNight.SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## The look settings file, or {} (it's shared with DayNight).
static func _read() -> Dictionary:
	if not FileAccess.file_exists(DayNight.SETTINGS_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DayNight.SETTINGS_PATH))
	return data if data is Dictionary else {}
