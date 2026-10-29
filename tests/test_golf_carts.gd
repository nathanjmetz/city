extends SceneTree
## Run: godot --headless -s tests/test_golf_carts.gd
## Golf carts on town streets (TownLaws golf_carts): once the town allows
## them some older residents buy one, take it on short hops round town, keep
## it off the highway, and sell it if the law is repealed.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-280, 281, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-80, 81, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	for i in 1500:
		sim.tick()
	var older := 0
	for id in sim.people.people:
		if int(sim.people.people[id].age) >= Balance.CART_OWNER_AGE:
			older += 1
	_check(older >= 5, "the town has older residents (%d of %d)" % [older, sim.people.people.size()])
	_check(VehicleModels.build("golf_cart").get_surface_count() > 0, "a golf cart has a model")
	_check(VehicleModels.build("golf_cart", VehicleModels.LOD_FAR).get_surface_count() > 0, "and a far one")
	# A settlement can't pass it; a town can.
	_check(not sim.apply({"type": "law", "law": "golf_carts", "on": true}), "a settlement has no council")
	sim.charter.reached["town"] = sim.tick_count
	_check(sim.apply({"type": "law", "law": "golf_carts", "on": true}), "a town allows golf carts")
	for m in 12:
		sim.laws.carts(sim)
	var owners := []
	for id in sim.people.people:
		if int(sim.people.people[id].get("cart", -1)) != -1:
			owners.append(id)
	_check(not owners.is_empty(), "some homes buy a cart (%d)" % owners.size())
	for id in owners:
		_check(int(sim.people.people[id].age) >= Balance.CART_OWNER_AGE, "owners are older residents")
	var homes := {}
	for id in owners:
		homes[sim.people.people[id].home] = true
	_check(homes.size() == owners.size(), "one cart a home")
	_check(owners.size() <= ceili(sim.buildings.size() * Balance.CART_SHARE) + Balance.CART_PER_MONTH,
		"only some homes have one (%d)" % owners.size())
	# A short hop to the shops goes by cart.
	if not owners.is_empty():
		var pid: int = owners[0]
		var p: Dictionary = sim.people.people[pid]
		var shop := ""
		for key in sim.buildings:
			if int(sim.buildings[key].zone) == ZoneMap.Zone.COMMERCIAL:
				shop = key
		if p.at != "":
			p.at = ""
		var ok: bool = sim.traffic.go(pid, "lot:" + shop, "shopping", 60)
		var rode := false
		for w in sim.traffic.walkers:
			if int(w.person) == pid and int(w.then.get("drive", -1)) == int(p.cart):
				rode = true
		_check(ok and rode, "a short trip to the shops is by cart (went %s)" % ok)
	# Repealed: the carts are sold.
	_check(sim.apply({"type": "law", "law": "golf_carts", "on": false}), "the law can be repealed")
	var left := 0
	for id in sim.people.people:
		if int(sim.people.people[id].get("cart", -1)) != -1:
			left += 1
	_check(left == 0, "and the carts are gone (%d left)" % left)

	# A cart crossing town keeps to the streets, not the highway.
	var r := CitySim.new()
	for c in [[[-300, 0], [-200, 0], RoadStyle.Type.STREET], [[200, 0], [300, 0], RoadStyle.Type.STREET],
			[[-200, 0], [200, 0], RoadStyle.Type.STATE_HWY],
			[[-200, 0], [-200, 200], RoadStyle.Type.STREET], [[-200, 200], [200, 200], RoadStyle.Type.STREET],
			[[200, 200], [200, 0], RoadStyle.Type.STREET]]:
		var a: Array = c[0]
		var b: Array = c[1]
		r.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b, "road": c[2]})
	var t: TrafficSim = r.traffic
	t.drive_ticks({"ref": "edge", "pos": [-280, 0]}, {"ref": "edge", "pos": [280, 0]})
	var from: Dictionary = t._endpoint({"ref": "edge", "pos": [-280, 0]})
	var to: Dictionary = t._endpoint({"ref": "edge", "pos": [280, 0]})
	var car_route: Dictionary = t._route(from, to)
	t._cart_plan = true
	var cart_route: Dictionary = t._route(from, to)
	t._cart_plan = false
	_check(not car_route.is_empty() and not cart_route.is_empty(), "both find a way")
	if not car_route.is_empty() and not cart_route.is_empty():
		_check(_on_type(r, car_route.route, RoadStyle.Type.STATE_HWY), "a car takes the highway")
		_check(not _on_type(r, cart_route.route, RoadStyle.Type.STATE_HWY), "a cart goes round by the streets")
	print("FAIL" if _failed else "PASS", " test_golf_carts")
	quit(1 if _failed else 0)


static func _on_type(sim: CitySim, route: Array, type: int) -> bool:
	for wid in route:
		var seg: int = int(wid) >> 1
		if sim.network.segments.has(seg) and int(sim.network.segments[seg].type) == type:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
