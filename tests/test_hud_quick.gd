extends SceneTree
## Run: godot --headless -s tests/test_hud_quick.gd
## The real HUD: search finds tools, picking one opens its menu and lands in
## the recent row, the pad wheel's second ring lists a menu's tools, and
## Shift + a number opens a menu.

var _failed := false
var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var hud: Hud
	for c in _main.get_children():
		if c is Hud:
			hud = c

	# Search.
	var wells := hud.search_cards("well")
	_check(not wells.is_empty() and (wells[0].get_meta("title") as Label).text == "Well", "\"well\" finds the Well first")
	_check(not hud.search_cards("school").is_empty(), "\"school\" finds the schools")
	_check(hud.search_cards("zzzz").is_empty(), "nonsense finds nothing")
	# What players hunted longest for (telemetry, 2026-10-23).
	var first := func(w: String) -> String:
		var h := hud.search_cards(w)
		return Hud.card_title(h[0]) if not h.is_empty() else ""
	_check(first.call("police") == "Police", "\"police\" finds Police first")
	_check(first.call("traffic light") == "Lights", "\"traffic light\" finds Lights first (%s)" % first.call("traffic light"))
	_check(first.call("signal") == "Lights", "\"signal\" finds Lights")
	_check(first.call("town") == "Town", "\"town\" finds the Town grid size first")
	_check(first.call("forestry") == "Forestry", "\"forestry\" finds Forestry")
	_check(first.call("smoke") == "Smoke", "\"smoke\" finds the Smoke view (%s)" % first.call("smoke"))
	# Start over needs a second click.
	var people_before = hud.sim.people
	hud._clear_button.pressed.emit()
	_check(hud.sim.people == people_before, "one click on Start over clears nothing")
	_check(hud._clear_button.text.begins_with("Click again"), "it asks for a second click")
	hud._clear_button.pressed.emit()
	_check(hud.sim.people != people_before, "the second click clears the map")
	_check(hud._clear_button.disabled and hud._clear_button.text == "Map cleared", "and says so, resting a moment")
	hud.press_card(hud.search_cards("smoke")[0])
	_check(hud._view == "smoke" and hud.views_open(), "picking it opens Views on Smoke")
	hud.close_all()
	hud.press_card(wells[0])
	_check(hud.service_tool.kind == Services.Kind.WELL, "picking it from search takes the well in hand")
	_check(hud._category == "utilities", "and opens Utilities (%s)" % hud._category)
	_check(not hud._recent.is_empty() and hud._recent[0] == wells[0], "it lands first in the recent tools")
	var n := hud._recent.size()
	hud.press_card(wells[0])
	_check(hud._recent.size() == n and hud._recent.count(wells[0]) == 1, "picking it again doesn't repeat it")
	hud.close_all()

	# The pad wheel's second ring.
	var tools: Array = hud.pad_wheel_pick("roads")
	_check(tools.size() >= 5, "the Roads ring lists its tools (%d)" % tools.size())
	_check(hud.pad_wheel_pick("tool:2").is_empty() and hud.road_tool.mode == RoadTool.Mode.GRID,
		"picking the third tool takes the grid (%d)" % hud.road_tool.mode)
	hud.close_all()
	_check(hud.pad_wheel_pick("bulldoze").is_empty(), "Bulldoze has no second ring")
	hud.close_all()

	# Shift + 2 opens Zoning.
	var e := InputEventKey.new()
	e.keycode = KEY_2
	e.physical_keycode = KEY_2
	e.shift_pressed = true
	e.pressed = true
	hud._unhandled_key_input(e)
	_check(hud._category == "zones", "Shift+2 opens Zoning (%s)" % hud._category)
	hud.close_all()

	# Changing a key: Road onto 9 takes it from nobody; Bulldoze onto 9 bumps Road.
	KeyBinds.reset()
	_check(KeyBinds.bind("road", KEY_9) == "", "Road moves onto 9")
	var nine := InputEventKey.new()
	nine.keycode = KEY_9
	nine.pressed = true
	hud.road_tool._unhandled_input(nine)
	_check(hud.road_tool.mode == RoadTool.Mode.STRAIGHT, "9 now takes the road tool")
	hud.close_all()
	var one := InputEventKey.new()
	one.keycode = KEY_1
	one.pressed = true
	hud.road_tool._unhandled_input(one)
	_check(hud.road_tool.mode == RoadTool.Mode.NONE, "1 no longer does")
	_check(KeyBinds.bind("bulldoze", KEY_9) == "road" and KeyBinds.key("road") == KEY_NONE, "a key taken by another action bumps it")
	KeyBinds.reset()
	_check(KeyBinds.key("road") == KEY_1 and KeyBinds.key("bulldoze") == KEY_B, "reset puts every key back")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
	return true


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
