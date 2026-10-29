extends SceneTree
## Run: godot --headless -s tests/test_build_menus.gd
## The bottom bar's menus stay compact (Brawn: Services spread across his
## whole monitor): every service has a card in one of the CS2-style groups,
## no menu is much wider than half a 1920 px screen, and picking a card opens its
## own category.

const MAX_WIDTH := 1000.0

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
	for k in Services.KINDS:
		_check(hud._service_cards.has(k), "%s has a card" % Services.KINDS[k].name)
	for k in CivicHubs.TOOL_KINDS:
		_check(hud._service_cards.has(k), "%s has a card" % CivicHubs.TOOL_KINDS[k])
	for k in [Mail.TOOL_KIND, Rail.TOOL_KIND]:
		_check(hud._service_cards.has(k), "tool %d has a card" % k)
	for key in hud._drawers:
		var w: float = hud._drawers[key].get_combined_minimum_size().x
		_check(w <= MAX_WIDTH, "%s menu is %d px wide" % [key, roundi(w)])
	var bar := 0.0
	for key in hud._category_buttons:
		bar += hud._category_buttons[key].get_combined_minimum_size().x + 4
	_check(bar <= 1280.0, "the bottom bar fits a 1280 px window (%d px)" % roundi(bar))
	# The Traffic row (shown above the road menus while Traffic is open),
	# measured shown: car-free and the turn rules live there, not in Roads.
	var was: bool = hud._traffic_row.visible
	hud._traffic_row.visible = true
	var tw: float = hud._traffic_row.get_combined_minimum_size().x
	hud._traffic_row.visible = was
	_check(tw > 0.0 and tw <= MAX_WIDTH, "the Traffic row is %d px wide" % roundi(tw))
	for cat in Hud.SERVICE_CATEGORIES:
		hud.close_all()
		hud._open(cat)
		_check(hud._category == cat, "%s opens on its own first tool (%s)" % [cat, hud._category])
	for pair in [[Services.Kind.FIRE, "civic"], [Services.Kind.DAYCARE, "education"], [102, "health"],
			[100, "utilities"], [Rail.TOOL_KIND, "transport"]]:
		hud.close_all()
		hud._service_cards[pair[0]].pressed.emit()
		_check(hud._category == pair[1], "card %d files under %s (%s)" % [pair[0], pair[1], hud._category])
	hud.close_all()
	hud._campus_cards["college"].pressed.emit()
	_check(hud._category == "education", "a college is under Education")
	hud.close_all()
	hud._bank_cards["community"].pressed.emit()
	_check(hud._category == "civic", "a bank is under Civic")
	hud.close_all()
	hud._park_cards["courthouse"].pressed.emit()
	_check(hud._category == "civic", "the courthouse is under Civic (%s)" % hud._category)
	hud.close_all()
	# One card for both curves: Curve, then Curve again for an S-curve,
	# and its name says which (Nathan 2026-10-26: CS2's road options).
	hud._open("roads")
	var curve: Button = hud._tool_cards[RoadTool.Mode.CURVED]
	curve.pressed.emit()
	_check(hud.road_tool.mode == RoadTool.Mode.CURVED, "the Curve card draws a curve")
	curve.pressed.emit()
	hud._sync()
	_check(hud.road_tool.mode == RoadTool.Mode.SCURVE and (curve.get_meta("title") as Label).text == "S-curve",
		"clicked again it draws an S-curve, and says so")
	curve.pressed.emit()
	_check(hud.road_tool.mode == RoadTool.Mode.CURVED, "and again, back to a simple curve")
	hud.close_all()
	hud.close_all()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)
	return true


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
