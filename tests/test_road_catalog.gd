extends SceneTree
## Run: godot --headless -s tests/test_road_catalog.gd
## All roads (Nathan 2026-10-29: "a whole screen of roads"; he kept the bar
## and added this card): every road type is on it once, under the right kind;
## the chips and search narrow it; picking a card takes the road just as the
## bar does; arrows, Enter and Esc work; it fits a phone and an ultrawide;
## and the Roads bar keeps to its 1000 px with the All roads card on it.

var _failed := false
var _main: Node
var _frames := 0
var _hud: Hud
var _cat: RoadCatalog


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _frames == 3:
		for c in _main.get_children():
			if c is Hud:
				_hud = c
		_cat = _hud.catalog
		_data()
		_bar()
		_open_and_pick()
		_filters_and_search()
		_keys()
		_tools()
		root.size = Vector2i(390, 844)
		_hud.open_catalog()
		return false
	if _frames == 6:
		_fits("a 390 px phone", true)
		root.size = Vector2i(3440, 1440)
		return false
	if _frames == 9:
		_fits("a 3440 px ultrawide", false)
		_hud.close_all()
		print("FAILED" if _failed else "ALL PASSED")
		quit(1 if _failed else 0)
		return true
	return false


func _data() -> void:
	# Every road a player can pick is in exactly one kind; the roundabout
	# rings (built by the roundabout tool) are not.
	var seen := {}
	for c in RoadCatalog.CATEGORIES:
		for t in RoadCatalog.roads_in(c[0]):
			seen[t] = seen.get(t, 0) + 1
	var pickable := 0
	for t in RoadStyle.TYPES.size():
		if RoadStyle.TYPES[t].get("menu", true):
			pickable += 1
			_check(seen.get(t, 0) == 1, "%s is in one kind (%d)" % [RoadStyle.TYPES[t].name, seen.get(t, 0)])
	_check(not seen.has(RoadStyle.Type.RING) and not seen.has(RoadStyle.Type.RING2), "the roundabout rings aren't")
	_check(RoadCatalog.roads().size() == pickable and pickable >= 30, "%d roads in all" % pickable)
	var want := {
		RoadStyle.Type.STREET: "streets", RoadStyle.Type.ALLEY: "streets", RoadStyle.Type.BRICK: "streets",
		RoadStyle.Type.MAIN_STREET: "streets", RoadStyle.Type.STREET_ONEWAY1: "streets",
		RoadStyle.Type.AVENUE: "avenues", RoadStyle.Type.AVENUE_BUS: "avenues", RoadStyle.Type.AVENUE_TURN: "avenues",
		RoadStyle.Type.BOULEVARD: "big", RoadStyle.Type.STRIP: "big", RoadStyle.Type.PARKWAY: "big",
		RoadStyle.Type.BOULEVARD_ONEWAY: "big",
		RoadStyle.Type.HIGHWAY: "highways", RoadStyle.Type.FREEWAY4: "highways", RoadStyle.Type.RAMP2: "highways",
		RoadStyle.Type.STATE_HWY: "highways", RoadStyle.Type.DIVIDED_HWY: "highways",
		RoadStyle.Type.GRAVEL: "country", RoadStyle.Type.DIRT: "country", RoadStyle.Type.CHIP_SEAL: "country",
		RoadStyle.Type.COUNTY: "country",
	}
	for t in want:
		_check(RoadCatalog.category_of(t) == want[t], "%s is under %s (%s)" % [RoadStyle.TYPES[t].name,
			RoadCatalog.category_title(want[t]), RoadCatalog.category_title(RoadCatalog.category_of(t))])
	# The cross-section adds up to the road's whole width, walks included.
	for t in RoadCatalog.roads():
		var sum := 0.0
		for p in RoadSection.parts(t):
			sum += p[1]
		_check(absf(sum - 2.0 * RoadStyle.right_of_way_half(t)) < 0.05,
			"%s's picture is %.1f m across, as built (%.1f m)" % [RoadStyle.TYPES[t].name, sum, 2.0 * RoadStyle.right_of_way_half(t)])
	var bus := RoadSection.parts(RoadStyle.Type.AVENUE_BUS).filter(func(p): return p[0] == "bus")
	_check(bus.size() == 2 and bus[0][2] == -1 and bus[1][2] == 1, "the bus avenue's picture has a bus lane each way")
	var oneway := RoadSection.parts(RoadStyle.Type.STREET_ONEWAY).filter(func(p): return p[0] == "lane")
	_check(oneway.all(func(p): return p[2] == 1), "a one-way street's lanes all go one way")
	_check(RoadSection.parts(RoadStyle.Type.PARKWAY).any(func(p): return p[0] == "median"), "the parkway has its median")


func _bar() -> void:
	_hud.close_all()
	_hud._open("roads")
	var w: float = _hud._drawers["roads"].get_combined_minimum_size().x
	_check(w <= 1000.0, "the Roads menu with All roads is %d px wide (1000 at most)" % roundi(w))
	_check(_hud._all_roads_card != null and _hud._all_roads_card.is_visible_in_tree(), "All roads is on the bar")
	for g in RoadStyle.GROUPS:
		_check(_hud._type_cards[g].is_visible_in_tree(), "%s is still on the bar" % RoadStyle.TYPES[g].name)


func _open_and_pick() -> void:
	_hud.close_all()
	_hud._open("roads")
	var t0 := Time.get_ticks_usec()
	_hud._all_roads_card.pressed.emit()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(_cat.visible and _hud.anything_open(), "the All roads card opens it")
	# The spec's budget: under 50 ms to open (its cards are made with the HUD).
	_check(ms < 50.0, "it opens in %.1f ms" % ms)
	_check(_cat.shown_roads().size() == RoadCatalog.roads().size(), "with every road showing (%d)" % _cat.shown_roads().size())
	var by_card: Button = _cat.road_cards[RoadStyle.Type.STREET]
	_check(by_card.button_pressed, "the road in hand (Street) is marked")
	_cat.road_cards[RoadStyle.Type.BRICK].pressed.emit()
	_check(not _cat.visible, "picking a card closes it")
	_check(_hud.road_tool.road_type == RoadStyle.Type.BRICK, "and takes that road (%d)" % _hud.road_tool.road_type)
	_check(_hud._category == "roads" and _hud.road_tool.mode != RoadTool.Mode.NONE, "with a drawing tool in hand")
	_check(_hud._variant_of.get(RoadStyle.Type.STREET) == RoadStyle.Type.BRICK, "and the Street card on the bar now shows it")
	_check(not _hud._recent.is_empty() and Hud.card_title(_hud._recent[0]) == "Brick street",
		"it lands first in the recent tools")
	# The same as the bar: a road picked from Traffic puts Traffic away.
	_hud.traffic_tool.set_mode(TrafficTool.Mode.VIEW)
	_hud.open_catalog()
	_cat.road_cards[RoadStyle.Type.PARKWAY].pressed.emit()
	_check(_hud.road_tool.road_type == RoadStyle.Type.PARKWAY and _hud.traffic_tool.mode == TrafficTool.Mode.NONE
		and _hud.road_tool.mode != RoadTool.Mode.NONE, "from Traffic, it takes the road and a drawing tool")
	# Upgrade keeps upgrading, to the road picked.
	_hud.road_tool.set_mode(RoadTool.Mode.UPGRADE)
	_hud.open_catalog()
	_cat.road_cards[RoadStyle.Type.AVENUE_BIKE].pressed.emit()
	_check(_hud.road_tool.mode == RoadTool.Mode.UPGRADE and _hud.road_tool.road_type == RoadStyle.Type.AVENUE_BIKE,
		"with Upgrade in hand it upgrades to the road picked")
	# The HUD's search finds every road, and picking one takes it.
	var hits := _hud.search_cards("gravel")
	_check(not hits.is_empty() and Hud.card_title(hits[0]) == "Gravel road", "the HUD's search finds Gravel road")
	_hud.press_card(hits[0])
	_check(_hud.road_tool.road_type == RoadStyle.Type.GRAVEL, "and picking it takes it")
	# Each menu's own road is its bar card already: search lists that one only.
	var streets := _hud.search_cards("street")
	_check(streets.has(_hud._type_cards[RoadStyle.Type.STREET]) and not streets.has(_cat.road_cards[RoadStyle.Type.STREET]),
		"\"street\" lists the bar's Street card, not a second one")
	# Esc and a click outside close it.
	_hud.open_catalog()
	_cat._input(_key(KEY_ESCAPE))
	_check(not _cat.visible, "Esc closes it")
	_hud.open_catalog()
	_hud.close_all()
	_check(not _cat.visible, "putting everything away closes it")


func _filters_and_search() -> void:
	_hud.open_catalog()
	_cat.set_filter("bike", true)
	var bike := _cat.shown_roads()
	_check(bike.size() >= 2 and bike.all(func(t): return RoadStyle.TYPES[t].get("bike", false)),
		"Bike lanes shows only roads with bike lanes (%d)" % bike.size())
	_check(not _cat.shown_titles().has("No left turn"), "and hides the tools, which have none")
	_cat.set_filter("lanes34", true)
	_check(_cat.shown_roads() == [RoadStyle.Type.AVENUE_BIKE], "with 3-4 lanes: the avenue with bike lanes")
	_cat.clear_filters()
	_cat.set_filter("lanes12", true)
	_cat.set_filter("lanes5", true)
	var wide := _cat.shown_roads()
	_check(wide.has(RoadStyle.Type.STREET) and wide.has(RoadStyle.Type.BOULEVARD) and wide.has(RoadStyle.Type.STRIP)
		and not wide.has(RoadStyle.Type.AVENUE), "1-2 and 5+ lanes widen each other (no 4-lane Avenue)")
	_cat.clear_filters()
	_cat.set_filter("oneway", true)
	_cat.set_filter("parking", true)
	var op := _cat.shown_roads()
	_check(op.size() >= 3 and op.all(func(t): return RoadStyle.TYPES[t].oneway and RoadCatalog.parks(t)),
		"one-way and parking narrow each other (%d)" % op.size())
	_cat.clear_filters()
	_cat.set_filter("trucks", true)
	_check(not _cat.shown_roads().has(RoadStyle.Type.STREET) and _cat.shown_roads().has(RoadStyle.Type.AVENUE),
		"Trucks OK leaves out neighborhood streets (the Truck routes law)")
	_cat.clear_filters()
	_cat.set_filter("country", true)
	_check(_cat.shown_roads().all(func(t): return RoadCatalog.category_of(t) == "country") and _cat.shown_roads().size() == 4,
		"Country shows the four country roads")
	_cat.clear_filters()
	_cat.set_filter("trees", true)
	_check(_cat.shown_roads().has(RoadStyle.Type.PARKWAY) and not _cat.shown_roads().has(RoadStyle.Type.AVENUE), "Trees")
	_cat.clear_filters()
	_cat.set_filter("bus", true)
	_check(_cat.shown_roads() == [RoadStyle.Type.AVENUE_BUS], "Bus lanes")
	_cat.clear_filters()
	_cat.search("brick")
	_check(_cat.shown_roads() == [RoadStyle.Type.BRICK], "\"brick\" finds the brick street")
	_cat.search("one way avenue")
	_check(_cat.shown_roads() == [RoadStyle.Type.AVENUE_ONEWAY], "\"one way avenue\" finds the one-way avenue (%s)" % str(_cat.shown_roads()))
	_cat.search("gravel")
	_check(_cat.shown_roads().has(RoadStyle.Type.GRAVEL) and _cat.shown_roads().size() <= 2, "\"gravel\"")
	_cat.search("no right")
	_check(_cat.shown_titles() == ["No right turn"], "\"no right\" finds the No Right Turn tool (%s)" % str(_cat.shown_titles()))
	_cat.search("zzzz")
	_check(_cat.shown_titles().is_empty() and _cat._empty.visible, "nonsense finds nothing, and says so")
	_cat.clear_filters()
	_check(_cat.shown_roads().size() == RoadCatalog.roads().size(), "Clear brings every road back")
	_hud.close_all()


func _keys() -> void:
	_hud.open_catalog()
	_cat._cols = 3
	var first := _cat.highlighted()
	_cat._input(_key(KEY_RIGHT))
	var second := _cat.highlighted()
	_check(first != null and second != null and first != second, "Right moves to the next card")
	_cat._input(_key(KEY_LEFT))
	_check(_cat.highlighted() == first, "Left moves back")
	_cat._set_hi(0)
	_cat._input(_key(KEY_DOWN))
	_check(_cat._hi == 3, "Down moves a row down (%d)" % _cat._hi)
	_cat._input(_key(KEY_UP))
	_check(_cat._hi == 0, "Up moves back up")
	_cat._input(_key(KEY_TAB))
	_check(_cat._shown[_cat._hi].cat == "avenues", "Tab jumps to the next kind (%s)" % _cat._shown[_cat._hi].cat)
	var b := _cat.highlighted()
	var t: int = RoadCatalog.roads_in("avenues")[0]
	_cat._input(_key(KEY_ENTER))
	_check(not _cat.visible and _hud.road_tool.road_type == t and b == _cat.road_cards[t], "Enter picks it")
	_hud.close_all()


func _tools() -> void:
	# The road options in other menus are here too, under the kind they belong to.
	_hud.close_all()
	_hud.open_catalog()
	var titles := _cat.shown_titles()
	for n in ["Car-free street", "Trailhead", "S-curve", "Snap to roads", "No right turn", "No left turn", "Bridge"]:
		_check(titles.has(n), "%s is in All roads" % n)
	_pick("No right turn")
	_check(_hud.traffic_tool.mode == TrafficTool.Mode.NO_RIGHT and not _cat.visible, "No right turn takes that tool")
	_hud.open_catalog()
	_pick("S-curve")
	_check(_hud.road_tool.mode == RoadTool.Mode.SCURVE and _hud.traffic_tool.mode == TrafficTool.Mode.NONE, "S-curve draws an S-curve")
	var was: bool = _hud.road_tool.snap_roads
	_hud.open_catalog()
	_pick("Snap to roads")
	_check(_hud.road_tool.snap_roads == not was, "Snap to roads switches road snapping")
	_hud.road_tool.set_snap("roads", true)
	_hud.open_catalog()
	_pick("Car-free street")
	_check(_hud.traffic_tool.mode == TrafficTool.Mode.CAR_FREE, "Car-free street takes the car-free tool")
	_hud.close_all()


func _pick(title: String) -> void:
	for e in _cat._entries:
		if e.card.title.text == title:
			(e.button as Button).pressed.emit()
			return
	_check(false, "a card called %s" % title)


## The panel sits inside the window, and nothing in it pokes out.
func _fits(what: String, narrow: bool) -> void:
	var screen := Rect2(Vector2.ZERO, _cat.size)
	var panel := _cat._panel.get_global_rect()
	_check(screen.encloses(panel), "on %s the panel fits the screen (%s in %s)" % [what, panel, screen])
	_check(_cat._narrow == narrow, "on %s the kinds are %s" % [what, "a row on top" if narrow else "down the left"])
	var inner := _cat._panel.get_child(0) as Control
	_check(inner.get_combined_minimum_size().x <= panel.size.x + 0.5, "on %s nothing is wider than the panel (%d of %d px)"
		% [what, roundi(inner.get_combined_minimum_size().x), roundi(panel.size.x)])
	_check(_cat._cols >= (1 if narrow else 4), "on %s %d cards across" % [what, _cat._cols])


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
