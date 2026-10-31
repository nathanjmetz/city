extends SceneTree
## Run: godot --headless -s tests/test_lot_cars.gd
##
## Lot cars (TrafficView._update_lot_cars, look critic round 3, 2026-10-30:
## shop lots stood about a tenth full at mid-morning). The view parks
## stand-ins in the free stalls of shop, office, hotel and plant lots by the
## hour. Checked here: the day's shares match a real strip lot (30 to 60%
## full late in the morning with the staff, fuller at noon, empty at
## night), a lot near the camera changes one car at a time, and only the
## desktop's Medium tier and up draw them (never the browser, Low, or a
## headless run).

var _failed := false


func _init() -> void:
	var shop: Array = TrafficView.LOT_CUSTOMERS["shop"]
	var staff := float(TrafficView.LOT_STAFF["shop"])
	var morning := staff + (1.0 - staff) * TrafficView._eased(shop, 10.5)
	_check(morning >= 0.3 and morning <= 0.6, "a shop lot is 30-60%% full at 10:30 (%.2f)" % morning)
	_check(TrafficView._eased(shop, 12.5) > TrafficView._eased(shop, 10.5), "fuller at noon than mid-morning")
	_check(TrafficView._eased(shop, 3.0) == 0.0 and TrafficView._eased(shop, 20.0) == 0.0, "no customers at night")
	_check(TrafficView._eased(TrafficView.LOT_CUSTOMERS["evening"], 19.0) > TrafficView._eased(shop, 19.0),
		"a restaurant or tavern is busier in the evening than a day shop")
	# Eased between points, flat outside them.
	_check(is_equal_approx(TrafficView._eased([[1.0, 0.2], [3.0, 0.6]], 2.0), 0.4), "eased halfway")
	_check(TrafficView._eased([[1.0, 0.2], [3.0, 0.6]], 0.0) == 0.2 and TrafficView._eased([[1.0, 0.2], [3.0, 0.6]], 9.0) == 0.6,
		"flat before the first point and after the last")
	for kind in TrafficView.LOT_CUSTOMERS:
		var pts: Array = TrafficView.LOT_CUSTOMERS[kind]
		var ok := true
		for i in range(1, pts.size()):
			ok = ok and float(pts[i][0]) > float(pts[i - 1][0])
		for p in pts:
			ok = ok and float(p[1]) >= 0.0 and float(p[1]) <= 1.0
		_check(ok, "%s: hours rise and shares are 0-1" % kind)
	# Near the camera: one car in or out a step, goers first.
	_check(TrafficView._lot_step([1, 2, 3], [2, 3, 4], 0) == [2, 3], "a step takes one car away first")
	_check(TrafficView._lot_step([2, 3], [2, 3, 4], 0) == [2, 3, 4], "then one pulls in")
	_check(TrafficView._lot_step([], [5], 7) == [5], "one into an empty lot")
	# Where they're drawn.
	_check(not bool(GraphicsQuality.INACTIVE.get("lot_cars", true)), "off in headless runs and tests")
	_check(not bool(GraphicsQuality.BUDGETS[GraphicsQuality.LOW].lot_cars), "off on Low")
	for t in [GraphicsQuality.MEDIUM, GraphicsQuality.HIGH, GraphicsQuality.ULTRA, GraphicsQuality.CINEMATIC]:
		_check(bool(GraphicsQuality.budget_for(t).lot_cars), "on for the desktop's %s" % GraphicsQuality.NAMES[t])
		_check(not bool(GraphicsQuality.budget_for(t, true).lot_cars), "never in the browser (%s)" % GraphicsQuality.NAMES[t])
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
