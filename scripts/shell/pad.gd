class_name Gamepad
extends Node
## Game controllers: Xbox, PlayStation, Switch Pro and most others, wired or
## wireless, in the browser and in the desktop builds. Benchmark: the console
## editions of Cities: Skylines. The left stick drives an on-screen cursor
## (push it against the screen edge to move the map), so every button,
## panel and tool works just as it does with a mouse:
##   Left stick: cursor            Right stick: rotate and tilt (scrolls lists)
##   LT / RT: zoom out / in        A: click (hold to drag or paint)
##   B: back (like Esc)            X: cancel (like a right click)
##   Y: tool wheel                 LB / RB: smaller / bigger (like [ and ])
##   D-pad up / down: raise / lower new roads
##   D-pad left / right: slower / faster
##   Click the left stick: hold for Shift (snap angles)
##   Click the right stick: finish a shape (like Enter), else fly home
##   Menu (Start): pause menu      View (Back): pause the clock
## Mouse and keyboard keep working: moving the mouse puts the pad cursor away.
## An autoload (Pad); other scripts reach it with Gamepad.find().

## Mouse and key events made from the pad carry this device id, so they can
## be told apart from the real mouse.
const DEVICE := 77
const DEADZONE := 0.2
## Cursor speed with the stick all the way over, in screen heights a second.
const CURSOR_SPEED := 0.9
## How close to the screen edge, in pixels, the cursor starts moving the map.
const EDGE := 3.0
## The right stick scrolls a list this often, in seconds.
const SCROLL_EVERY := 0.06

## True while the controller is in use (the pad cursor is up).
var active := false
## The pad cursor, in screen pixels.
var cursor := Vector2.ZERO
## Which button labels to show.
var style := PadPrompts.Style.XBOX
## This frame's camera input. pan: the cursor pushing on a screen edge
## (-1 to 1, y up is -). turn: the right stick (x rotates, y tilts).
## zoom: the triggers (+ zooms in).
var pan := Vector2.ZERO
var turn := Vector2.ZERO
var zoom := 0.0

var _device := -1
var _a_down := false
var _scroll_wait := 0.0
var _layer := CanvasLayer.new()
var _pointer := _Pointer.new()
var _prompts := PadPrompts.new()
var _wheel := PadWheel.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.layer = 120
	add_child(_layer)
	_prompts.visible = false
	_layer.add_child(_prompts)
	_wheel.visible = false
	_wheel.picked.connect(_wheel_picked)
	_layer.add_child(_wheel)
	_pointer.visible = false
	_layer.add_child(_pointer)
	Input.joy_connection_changed.connect(func(_d, _c): _pick_device())
	_pick_device()


## The autoload, or null when it isn't running (headless tools).
static func find() -> Gamepad:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Pad") as Gamepad if tree != null else null


## Which controller look a pad's name points to (labels and colours).
static func style_for(joy_name: String) -> PadPrompts.Style:
	var n := joy_name.to_lower()
	if "xbox" in n or "045e" in n:
		return PadPrompts.Style.XBOX
	for k in ["playstation", "dualsense", "dualshock", "sony", "ps3", "ps4", "ps5", "054c", "wireless controller"]:
		if k in n:
			return PadPrompts.Style.PLAYSTATION
	for k in ["nintendo", "pro controller", "switch", "joy-con", "057e"]:
		if k in n:
			return PadPrompts.Style.NINTENDO
	return PadPrompts.Style.XBOX


## A stick's position with the dead zone taken out, eased so small pushes
## give fine control and full tilt gives full speed.
static func shape_stick(v: Vector2) -> Vector2:
	var len := v.length()
	if len < DEADZONE:
		return Vector2.ZERO
	var t := minf((len - DEADZONE) / (1.0 - DEADZONE), 1.0)
	return v / len * t * t


## Where a tool or click lands: the pad cursor while the pad is in use,
## otherwise the mouse.
func pointer(viewport: Viewport) -> Vector2:
	return cursor if active else viewport.get_mouse_position()


func connected() -> bool:
	return _device >= 0


func _pick_device() -> void:
	var pads := Input.get_connected_joypads()
	if not pads.has(_device):
		_device = pads[0] if not pads.is_empty() else -1
	if _device >= 0:
		style = style_for(Input.get_joy_name(_device))
	elif active:
		_set_active(false)


func _input(event: InputEvent) -> void:
	if event.device == DEVICE:
		return  # one of ours
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.device != _device:
			_device = event.device
			style = style_for(Input.get_joy_name(_device))
		# The pad's own buttons never reach menus as ui_accept / ui_left:
		# it works through the cursor instead.
		get_viewport().set_input_as_handled()
		if event is InputEventJoypadButton:
			var jb := event as InputEventJoypadButton
			_on_button(jb.button_index, jb.pressed)
		return
	# The real mouse takes over again.
	if active and (event is InputEventMouseButton
			or event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0):
		_set_active(false)


func _on_button(b: int, pressed: bool) -> void:
	if _wheel.visible:
		if pressed and b in [JOY_BUTTON_A, JOY_BUTTON_Y]:
			_wheel.pick()
		elif pressed and b == JOY_BUTTON_B:
			_wheel.close()
			_pointer.visible = active
		return
	match b:
		JOY_BUTTON_A:
			if pressed or _a_down:
				_set_active(true)
				_a_down = pressed
				_click(MOUSE_BUTTON_LEFT, pressed)
		JOY_BUTTON_X:
			if pressed:
				_set_active(true)
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_RIGHT, false)
		JOY_BUTTON_B:
			if pressed:
				_tap(KEY_ESCAPE)
		JOY_BUTTON_Y:
			if pressed and not MenuState.showing:
				_open_wheel()
		JOY_BUTTON_LEFT_SHOULDER:
			if pressed:
				_tap(KEY_BRACKETLEFT)
		JOY_BUTTON_RIGHT_SHOULDER:
			if pressed:
				_tap(KEY_BRACKETRIGHT)
		JOY_BUTTON_DPAD_UP:
			if pressed:
				_tap(KEY_PAGEUP)
		JOY_BUTTON_DPAD_DOWN:
			if pressed:
				_tap(KEY_PAGEDOWN)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			var game := get_tree().current_scene
			if pressed and game != null and game.has_method("set_speed") and not MenuState.showing:
				game.set_speed(game.speed + (1 if b == JOY_BUTTON_DPAD_RIGHT else -1))
		JOY_BUTTON_LEFT_STICK:
			_key(KEY_SHIFT, pressed)
		JOY_BUTTON_RIGHT_STICK:
			if pressed and not MenuState.showing:
				var hud := _hud()
				_tap(KEY_ENTER if hud != null and hud.shape_open() else KEY_HOME)
		JOY_BUTTON_START:
			if pressed:
				_toggle_menu()
		JOY_BUTTON_BACK:
			var game := get_tree().current_scene
			if pressed and game != null and game.has_method("toggle_pause") and not MenuState.showing:
				game.toggle_pause()


func _process(delta: float) -> void:
	pan = Vector2.ZERO
	turn = Vector2.ZERO
	zoom = 0.0
	if _device < 0:
		return
	var ls := shape_stick(Vector2(Input.get_joy_axis(_device, JOY_AXIS_LEFT_X), Input.get_joy_axis(_device, JOY_AXIS_LEFT_Y)))
	var rs := shape_stick(Vector2(Input.get_joy_axis(_device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(_device, JOY_AXIS_RIGHT_Y)))
	var lt := shape_stick(Vector2(Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_LEFT), 0.0)).x
	var rt := shape_stick(Vector2(Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_RIGHT), 0.0)).x
	if _wheel.visible:
		_wheel.aim(ls)
		return
	zoom = rt - lt
	if ls != Vector2.ZERO:
		_set_active(true)
		var size := get_viewport().get_visible_rect().size
		var was := cursor
		cursor = (cursor + ls * size.y * CURSOR_SPEED * delta).clamp(Vector2.ZERO, size - Vector2.ONE)
		# Pushing against an edge moves the map, like edge scrolling.
		if cursor.x <= EDGE and ls.x < 0.0 or cursor.x >= size.x - 1.0 - EDGE and ls.x > 0.0:
			pan.x = ls.x
		if cursor.y <= EDGE and ls.y < 0.0 or cursor.y >= size.y - 1.0 - EDGE and ls.y > 0.0:
			pan.y = ls.y
		if cursor != was:
			_move(cursor - was)
	# Over a list, the right stick scrolls it; anywhere else it turns the view.
	_scroll_wait -= delta
	if active and rs.y != 0.0 and _over_scroll_list():
		if _scroll_wait <= 0.0:
			_scroll_wait = SCROLL_EVERY / absf(rs.y)
			_click(MOUSE_BUTTON_WHEEL_DOWN if rs.y > 0.0 else MOUSE_BUTTON_WHEEL_UP, true)
			_click(MOUSE_BUTTON_WHEEL_DOWN if rs.y > 0.0 else MOUSE_BUTTON_WHEEL_UP, false)
	else:
		turn = rs
	if _prompts.visible:
		_prompts.refresh(_hud(), style)


func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		var vp := get_viewport()
		var size := vp.get_visible_rect().size
		cursor = vp.get_mouse_position().clamp(Vector2.ZERO, size - Vector2.ONE)
		if cursor == Vector2.ZERO:
			cursor = size * 0.5
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_move(Vector2.ZERO)
	else:
		if _a_down:
			_a_down = false
			_click(MOUSE_BUTTON_LEFT, false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_wheel.close()
	_pointer.visible = on
	_prompts.visible = on
	if on:
		_prompts.refresh(_hud(), style)


func _hud() -> Node:
	return get_tree().get_first_node_in_group("pad_hud")


func _over_scroll_list() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	while c != null:
		if c is ScrollContainer:
			return true
		c = c.get_parent() as Control
	return false


func _toggle_menu() -> void:
	var game := get_tree().current_scene
	if game != null:
		for c in game.get_children():
			if c is CanvasLayer and c.has_method("toggle"):  # GameMenu
				c.toggle()
				return
	_tap(KEY_ESCAPE)


func _open_wheel() -> void:
	var hud := _hud()
	if hud == null:
		return
	if _a_down:
		_a_down = false
		_click(MOUSE_BUTTON_LEFT, false)
	_wheel.open(hud.pad_wheel_items(), style)
	_pointer.visible = false


func _wheel_picked(key: String) -> void:
	_pointer.visible = active
	var hud := _hud()
	if hud != null:
		hud.pad_wheel_pick(key)


# --- Mouse and keys made from the pad --------------------------------------

func _move(rel: Vector2) -> void:
	_pointer.position = cursor
	var e := InputEventMouseMotion.new()
	e.device = DEVICE
	e.position = cursor
	e.global_position = cursor
	e.relative = rel
	e.screen_relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down else 0
	Input.parse_input_event(e)


func _click(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.device = DEVICE
	e.position = cursor
	e.global_position = cursor
	e.button_index = button
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down else 0
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.device = DEVICE
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


## The pad cursor: an arrow in the brand's cream with a dark outline.
class _Pointer extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 21), Vector2(5.5, 16), Vector2(9.5, 24.5),
			Vector2(13, 23), Vector2(9, 14.5), Vector2(16, 14.5)])
		var outline := arrow.duplicate()
		outline.append(arrow[0])
		draw_colored_polygon(arrow, Brand.BRAND_CREAM)
		draw_polyline(outline, Brand.SURFACE, 2.0, true)
