extends SceneTree
## Run: godot --headless -s tests/test_lot_cars.gd
##
## Lot cars (TrafficView._update_lot_cars, look critic round 3, 2026-10-30:
## shop lots stood about a tenth full at mid-morning). The view parks
## stand-ins in the free stalls of shop, office, hotel and plant lots by the
## hour. Checked here, on a real town:
##   - the day's shares match a real strip lot (30 to 60% full late in the
##     morning with the staff, fuller at noon, empty at night);
##   - a stall the simulation has never shows a stand-in, and one it lets go
##     stays empty for LOT_HOLD seconds (its car backing out);
##   - a lot whose simulation layout is out of date, or that is gone, shows
##     none;
##   - the simulation is the same with lot cars on and off;
##   - only the desktop's Medium tier and up draw them, with their own cap.

var _failed := false


func _init() -> void:
	_shares()
	_tiers()
	_stalls()
	_same_sim()
	quit(1 if _failed else 0)


func _shares() -> void:
	var shop: Array = TrafficView.LOT_CUSTOMERS["shop"]
	var staff := float(TrafficView.LOT_STAFF["shop"])
	var morning := staff + (1.0 - staff) * TrafficView._eased(shop, 10.5)
	_check(morning >= 0.3 and morning <= 0.6, "a shop lot is 30-60%% full at 10:30 (%.2f)" % morning)
	_check(TrafficView._eased(shop, 12.5) > TrafficView._eased(shop, 10.5), "fuller at noon than mid-morning")
	_check(TrafficView._eased(shop, 3.0) == 0.0 and TrafficView._eased(shop, 20.0) == 0.0, "no customers at night")
	_check(TrafficView._eased(TrafficView.LOT_CUSTOMERS["evening"], 19.0) > TrafficView._eased(shop, 19.0),
		"a restaurant or tavern is busier in the evening than a day shop")
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


func _tiers() -> void:
	_check(int(GraphicsQuality.INACTIVE.get("lot_cars", 1)) == 0, "off in headless runs and tests")
	_check(int(GraphicsQuality.BUDGETS[GraphicsQuality.LOW].lot_cars) == 0, "off on Low")
	for t in [GraphicsQuality.MEDIUM, GraphicsQuality.HIGH, GraphicsQuality.ULTRA, GraphicsQuality.CINEMATIC]:
		_check(int(GraphicsQuality.budget_for(t).lot_cars) > 0, "on for the desktop's %s" % GraphicsQuality.NAMES[t])
		_check(int(GraphicsQuality.budget_for(t, true).lot_cars) == 0, "never in the browser (%s)" % GraphicsQuality.NAMES[t])


## A town, and one of its shop lots with a few stalls, looked at from far
## off (so it is set as it should be at once, not a car at a time).
func _stalls() -> void:
	var sim := _town()
	GraphicsQuality.budget["lot_cars"] = 5000
	var view := TrafficView.new()
	view.setup(sim.traffic, func(): return 0.0, sim)
	view._lot_hour = 12.5
	var key := ""
	for k in sim.buildings:
		if view._lot_kind(k) != "shop" or sim.care.tier_of(k) <= -2:
			continue
		var stalls: Array = SiteLayout.for_lot(sim, k).spots.filter(func(s): return s.kind == "stall" and not s.get("ada", false))
		if stalls.size() >= 6 and sim.traffic.cached_place("lot:" + k).is_empty() and not sim.traffic._places.has("lot:" + k):
			key = k
			break
	_check(key != "", "the town has a shop lot with stalls nobody has parked in yet")
	if key == "":
		return
	var at := SiteLayout.world(sim.lots[key], Vector2.ZERO)
	var eye := at + Vector3(1000.0, 0.0, 0.0)
	view._lot_look(key, at, eye, 99.0)
	_check(not view._lot_shown.has(key), "a lot the simulation hasn't laid out yet shows none")
	# A car comes (the simulation lays the lot out): stand-ins on its layout.
	var pl := sim.traffic.place("lot:" + key)
	view._lot_look(key, at, eye, 100.0)
	var spots := _drawn(view, key)
	_check(spots.size() >= 2, "at 12:30 it has lot cars (%d)" % spots.size())
	if spots.is_empty():
		return
	_check(spots.all(func(s): return pl.spots[s].kind == "stall" and not pl.spots[s].get("ada", false)),
		"every one in a stall of the simulation's own layout, none in an accessible one")
	# The simulation takes one of those stalls.
	var i: int = spots[0]
	pl.taken[i] = 987654
	view._lot_look(key, at, eye, 101.0)
	_check(not _drawn(view, key).has(i), "a stall the simulation has shows no stand-in")
	_check(_drawn(view, key).size() == spots.size() - 1, "the others stay")
	# And lets it go (its car backing out): empty for the hold, then free.
	pl.taken[i] = -1
	view._lot_look(key, at, eye, 102.0)
	_check(not _drawn(view, key).has(i), "a stall just let go stays empty")
	view._lot_look(key, at, eye, 101.0 + TrafficView.LOT_HOLD - 0.5)
	_check(not _drawn(view, key).has(i), "... for the hold (%.0f s)" % TrafficView.LOT_HOLD)
	view._lot_look(key, at, eye, 101.0 + TrafficView.LOT_HOLD + 0.5)
	_check(_drawn(view, key).has(i), "... and has its stand-in back after it")
	# Near the camera too: a held stall never shows one.
	pl.taken[i] = 987654
	view._lot_look(key, at, at, 200.0)
	_check(not _drawn(view, key).has(i), "near the camera, a stall the simulation has shows none")
	pl.taken[i] = -1
	# The building changes, so the simulation's place for it is out of date.
	var b: Dictionary = sim.buildings[key]
	var seed := int(b.seed)
	b.seed = seed + 1
	var r := view._lot_look(key, at, eye, 300.0)
	_check(r == TrafficView.LOOK_CHANGED and not view._lot_shown.has(key),
		"a lot whose simulation layout is out of date shows none")
	b.seed = seed
	view._lot_look(key, at, eye, 400.0)
	_check(not _drawn(view, key).is_empty(), "back once it matches again")
	# Out of reach: none, and nothing worked out.
	view._lot_look(key, at, at + Vector3(view._reach_far + TrafficView.LOT_MARGIN + 50.0, 0.0, 0.0), 500.0)
	_check(not view._lot_shown.has(key), "a lot past the cars' reach shows none")
	# The building goes: its cars go.
	view._lot_look(key, at, eye, 600.0)
	sim.buildings.erase(key)
	r = view._lot_look(key, at, eye, 601.0)
	_check(r == TrafficView.LOOK_CHANGED and not view._lot_shown.has(key), "a lot that's gone shows none")
	view.free()
	GraphicsQuality.budget["lot_cars"] = 0


## The simulation steps the same with lot cars on as off: money, cars and
## where every parked car stands.
func _same_sim() -> void:
	var off := _town()
	var on := _town()
	GraphicsQuality.budget["lot_cars"] = 5000
	var view := TrafficView.new()
	view.setup(on.traffic, func(): return 0.0, on)
	for i in 600:
		off.tick()
		on.tick()
		view._lot_pass_t = -INF  # a pass every tick, not every real second
		view._update_lot_cars(Vector3(0.0, 300.0, 0.0), -1.0)
	_check(view._lot_shown.size() > 0, "lot cars were drawn while it ran (%d lots)" % view._lot_shown.size())
	_check(_state(off) == _state(on), "the simulation is the same with lot cars on and off")
	view.free()
	GraphicsQuality.budget["lot_cars"] = 0


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.terrain_offset = Vector2(0, 1500)
	PerfTown.build(sim, "small")
	for i in 200:
		sim.tick()
	return sim


func _state(sim: CitySim) -> Array:
	var where := []
	for car in sim.traffic.parked:
		where.append([car.id, car.get("at_place", ""), car.get("spot", -1)])
	where.sort()
	return [sim.economy.money, sim.tick_count, sim.traffic.cars.size(), hash(where)]


## The simulation's stall numbers lot `key` draws stand-ins in.
func _drawn(view: TrafficView, key: String) -> Array:
	var shown: Array = view._lot_shown.get(key, [])
	if shown.is_empty():
		return []
	return shown[0].map(func(k): return int(shown[3][k][0]))


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
