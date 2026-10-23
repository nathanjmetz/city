class_name KeyBinds
## The keyboard keys for the game's actions, changeable on the pause menu's
## Controls page (CS2's key bindings). Defaults follow Cities: Skylines 2's
## camera keys and our own tool keys. The arrow keys always move the camera
## too, and the controller sends whatever key an action is bound to, so a
## change reaches the pad as well. Saved in user://keys.json.

const PATH := "user://keys.json"

## [action, label, default key], in the order the Controls page lists them.
const ACTIONS := [
	["move_forward", "Move forward", KEY_W], ["move_back", "Move back", KEY_S],
	["move_left", "Move left", KEY_A], ["move_right", "Move right", KEY_D],
	["rotate_left", "Rotate left", KEY_Q], ["rotate_right", "Rotate right", KEY_E],
	["tilt_up", "Tilt up", KEY_T], ["tilt_down", "Tilt down", KEY_G],
	["zoom_in", "Zoom in", KEY_R], ["zoom_out", "Zoom out", KEY_F],
	["home", "Back to your town", KEY_HOME],
	["road", "Road", KEY_1], ["curve", "Curve", KEY_2], ["grid", "Grid", KEY_3], ["roundabout", "Roundabout", KEY_4],
	["upgrade", "Upgrade road", KEY_U], ["parallel", "Parallel road", KEY_P], ["bulldoze", "Bulldoze", KEY_B],
	["raise", "Raise (bridge)", KEY_PAGEUP], ["lower", "Lower (tunnel)", KEY_PAGEDOWN],
	["smaller", "Smaller", KEY_BRACKETLEFT], ["bigger", "Bigger", KEY_BRACKETRIGHT],
	["homes", "Zone homes", KEY_5], ["shops", "Zone shops", KEY_6], ["industry", "Zone industry", KEY_7],
	["dezone", "Dezone", KEY_8], ["brush", "Brush or fill", KEY_TAB],
	["move_it", "Move It", KEY_M], ["turn_left", "Turn left (Move It)", KEY_COMMA],
	["turn_right", "Turn right (Move It)", KEY_PERIOD],
	["traffic", "Traffic view", KEY_J], ["views", "Views", KEY_V], ["search", "Find a tool", KEY_SLASH],
	["help", "Controls list", KEY_F1], ["pause", "Pause", KEY_SPACE], ["flag_sound", "Flag a bad sound", KEY_N],
]

static var _keys := {}  # action -> Key, once loaded


## The key an action is on now.
static func key(action: String) -> Key:
	_load()
	return _keys.get(action, KEY_NONE)


static func held(action: String) -> bool:
	var k := key(action)
	return k != KEY_NONE and Input.is_key_pressed(k)


## The first of these actions bound to the event's key, or "".
static func action(event: InputEventKey, among: Array) -> String:
	_load()
	var code := event.keycode
	for a in among:
		if _keys.get(a, KEY_NONE) == code:
			return a
	return ""


static func matches(event: InputEventKey, a: String) -> bool:
	return action(event, [a]) != ""


## The key's name for menus and tooltips ("Page Up", "[").
static func text(action: String) -> String:
	var k := key(action)
	return "—" if k == KEY_NONE else OS.get_keycode_string(k)


## Puts an action on a key. An action already on that key gives it up and
## is returned, so the page can say what moved.
static func bind(a: String, k: Key) -> String:
	_load()
	var bumped := ""
	for other in _keys:
		if other != a and _keys[other] == k:
			_keys[other] = KEY_NONE
			bumped = other
	_keys[a] = k
	_save()
	return bumped


static func reset() -> void:
	_keys.clear()
	for row in ACTIONS:
		_keys[row[0]] = row[2]
	_save()


static func label(a: String) -> String:
	for row in ACTIONS:
		if row[0] == a:
			return row[1]
	return a


static func _load() -> void:
	if not _keys.is_empty():
		return
	for row in ACTIONS:
		_keys[row[0]] = row[2]
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for a in d:
			if _keys.has(a):
				_keys[a] = int(d[a])


## Only the changed keys are kept, so new defaults still reach old saves.
static func _save() -> void:
	var changed := {}
	for row in ACTIONS:
		if _keys.get(row[0], row[2]) != row[2]:
			changed[row[0]] = _keys[row[0]]
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(changed))
