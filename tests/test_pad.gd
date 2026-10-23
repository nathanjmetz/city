extends SceneTree
## Run: godot --headless -s tests/test_pad.gd
## Game controllers: the right labels for each pad, the stick dead zone, the
## tool wheel's aim, and pad buttons clicking real buttons through the cursor.

var _keys: Array = []
var Pad: Gamepad


func _initialize() -> void:
	Pad = Gamepad.find()
	# Labels follow the pad in hand.
	_check(Gamepad.style_for("Xbox Wireless Controller") == PadPrompts.Style.XBOX, "Xbox pad gets Xbox letters")
	_check(Gamepad.style_for("Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)") == PadPrompts.Style.PLAYSTATION,
		"a DualSense in the browser gets PlayStation shapes")
	_check(Gamepad.style_for("PS5 Controller") == PadPrompts.Style.PLAYSTATION, "PS5 controller on the desktop")
	_check(Gamepad.style_for("Nintendo Switch Pro Controller") == PadPrompts.Style.NINTENDO, "Switch Pro gets Nintendo letters")
	_check(Gamepad.style_for("8BitDo SN30 Pro") == PadPrompts.Style.XBOX, "unknown pads fall back to Xbox letters")

	# Sticks: a resting stick does nothing, full tilt is full speed.
	_check(Gamepad.shape_stick(Vector2(0.1, -0.12)) == Vector2.ZERO, "a resting stick inside the dead zone is still")
	_check(is_equal_approx(Gamepad.shape_stick(Vector2(1, 0)).x, 1.0), "full tilt is full speed")
	var half := Gamepad.shape_stick(Vector2(0.6, 0)).x
	_check(half > 0.0 and half < 0.4, "a small push moves slowly for fine aim (%.2f)" % half)

	# Tool wheel: slot 0 is up, then clockwise.
	_check(PadWheel.slot_for(Vector2(0, -1), 9) == 0, "stick up picks the top slot")
	_check(PadWheel.slot_for(Vector2(1, 0), 8) == 2, "stick right picks the slot at 3 o'clock")
	_check(PadWheel.slot_for(Vector2(-0.05, -1), 8) == 0, "just left of up still picks the top")
	_check(PadWheel.slot_for(Vector2(-1, 0), 8) == 6, "stick left picks the slot at 9 o'clock")

	# The A button clicks whatever is under the pad cursor.
	var button := Button.new()
	# A headless window is only 64 px square.
	button.position = Vector2(4, 4)
	button.size = Vector2(40, 30)
	root.add_child(button)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	var listener := _KeyListener.new()
	listener.keys = _keys
	root.add_child(listener)
	await process_frame
	Pad.active = true
	Pad.cursor = Vector2(20, 15)
	Pad._move(Vector2.ZERO)
	_press(JOY_BUTTON_A, true)
	_press(JOY_BUTTON_A, false)
	await process_frame
	await process_frame
	_check(clicks[0] == 1, "A clicks the button under the pad cursor (%d)" % clicks[0])
	_check(Pad.active, "the pad cursor stays up after a click")

	# B is Esc, LB / RB are [ and ].
	_press(JOY_BUTTON_B, true)
	_press(JOY_BUTTON_LEFT_SHOULDER, true)
	_press(JOY_BUTTON_RIGHT_SHOULDER, true)
	await process_frame
	await process_frame
	_check(_keys.has(KEY_ESCAPE), "B backs out like Esc")
	_check(_keys.has(KEY_BRACKETLEFT) and _keys.has(KEY_BRACKETRIGHT), "LB / RB size tools like [ ]")

	# Moving the real mouse hands control back to it.
	var m := InputEventMouseMotion.new()
	m.position = Vector2(50, 50)
	m.relative = Vector2(30, 0)
	Input.parse_input_event(m)
	Input.flush_buffered_events()
	await process_frame
	_check(not Pad.active, "moving the mouse puts the pad cursor away")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _press(b: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


class _KeyListener extends Node:
	var keys: Array

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append((event as InputEventKey).keycode)


var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
