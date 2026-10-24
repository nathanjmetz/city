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

	# The number keys' pies: hold 1, flick up and right, let go: Grid.
	var roads: Array = hud.pie_items("roads")
	_check(roads.size() == 8 and roads[1].title == "Grid", "Roads' pie has Grid up and to the right")
	_check(roads[7].has("group") and roads[7].group.size() == 5, "and the road types as a group up and to the left")
	hud.open_pie("roads", KEY_1)
	var o: Vector2 = hud.pie._origin
	_check(hud.pie.is_open(), "holding 1 opens the Roads pie")
	hud.pie._input(_motion(o + Vector2(60, -60)))
	_check(hud.pie._sel == 1, "a flick up and right points at Grid (%d)" % hud.pie._sel)
	hud.pie._input(_key(KEY_1, false))
	_check(not hud.pie.is_open() and hud.road_tool.mode == RoadTool.Mode.GRID, "letting go takes the grid (%d)" % hud.road_tool.mode)
	_check(hud._category == "roads", "and opens Roads for its sizes")
	hud.close_all()
	# A tap leaves it open to click.
	hud.open_pie("roads", KEY_1)
	o = hud.pie._origin
	hud.pie._input(_key(KEY_1, false))
	_check(hud.pie.is_open(), "a tap leaves the pie open")
	hud.pie._input(_click(o + Vector2(0, -90)))
	_check(not hud.pie.is_open() and hud.road_tool.mode == RoadTool.Mode.STRAIGHT, "a click on the top slot takes Straight")
	hud.close_all()
	# Pushing on into a group opens its pie where the cursor is.
	hud.open_pie("roads", KEY_1)
	o = hud.pie._origin
	hud.pie._input(_motion(o + Vector2(-150, -150)))
	_check(hud.pie._title == "Road types", "pushing past the ring opens Road types (%s)" % hud.pie._title)
	hud.pie._input(_motion(hud.pie._origin + Vector2(70, 0)))
	hud.pie._input(_key(KEY_1, false))
	_check(not hud._recent.is_empty() and Hud.card_title(hud._recent[0]) == "Avenue", "a flick right in it takes Avenue")
	hud.close_all()
	# A long hold let go in the middle picks nothing.
	hud.open_pie("zones", KEY_2)
	hud.pie._since -= 1000
	hud.pie._input(_key(KEY_2, false))
	_check(not hud.pie.is_open() and hud.zone_tool.zone == ZoneTool.OFF, "letting go in the middle closes it")
	hud.close_all()
	# Every menu's pie finds its cards; Economy has none and just opens.
	for cat in Hud.hotkey_categories():
		if cat == "budget":
			continue
		var slots: Array = hud.pie_items(cat)
		var named := 0
		for it in slots:
			if it != null:
				named += 1
		_check(slots.size() in [4, 8] and named >= mini(3, slots.size()), "the %s pie fills its slots (%d)" % [cat, named])
	hud.open_pie("budget", KEY_0)
	_check(hud._budget_open and not hud.pie.is_open(), "0 opens Economy")
	hud.close_all()

	# The pad wheel's second ring: the same slots as the pie.
	var tools: Array = hud.pad_wheel_pick("roads")
	_check(tools.size() == 8 and tools[1][1] == "Grid", "the Roads ring matches the pie (%d)" % tools.size())
	_check(hud.pad_wheel_pick(tools[1][2]).is_empty() and hud.road_tool.mode == RoadTool.Mode.GRID,
		"picking its Grid takes the grid (%d)" % hud.road_tool.mode)
	_check(hud.pad_wheel_pick(tools[7][2]).size() == 8, "its Road types open a third ring")
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

	# Changing a key: Road onto K takes it from nobody; Bulldoze onto K bumps Road.
	KeyBinds.reset()
	_check(KeyBinds.bind("road", KEY_K) == "", "Road moves onto K")
	var kk := InputEventKey.new()
	kk.keycode = KEY_K
	kk.pressed = true
	hud.road_tool._unhandled_input(kk)
	_check(hud.road_tool.mode == RoadTool.Mode.STRAIGHT, "K now takes the road tool")
	hud.close_all()
	_check(KeyBinds.bind("bulldoze", KEY_K) == "road" and KeyBinds.key("road") == KEY_NONE, "a key taken by another action bumps it")
	_check(KeyBinds.bind("road", KEY_1) == "pie_1", "putting Road on 1 takes it from the Roads pie")
	KeyBinds.reset()
	_check(KeyBinds.key("pie_1") == KEY_1 and KeyBinds.key("bulldoze") == KEY_B, "reset puts every key back")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
	return true


func _motion(p: Vector2) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.position = p
	return m


func _key(k: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	return e


func _click(p: Vector2) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.position = p
	return b


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
