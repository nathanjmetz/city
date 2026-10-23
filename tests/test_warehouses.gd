extends SceneTree
## Warehouses: they store loads nobody needs yet, hand them on by real
## truck, and grow up and then out into the land behind them.
## Run: godot --headless -s tests/test_warehouses.gd

var _failed := 0


func _init() -> void:
	# Crude with no refinery in town goes into a warehouse, not the highway.
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-2000, 2001, 100):
		for z in range(-2000, 2001, 100):
			var v := Resources.at(Resources.Kind.OIL, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [best.x - 400, best.z - 60], "ctrl": [best.x, best.z - 60], "end": [best.x + 400, best.z - 60]})
	sim.build_county_road(Vector2(best.x + 400, best.z - 60), Vector2(best.x + 2000, best.z - 60), [1])
	var site := Warehouses.site_near(sim.network, Vector3(best.x + 250, 0, best.z - 120))
	_check(site.size() == 3 and site[0].z < best.z - 60.0 and site[1].z > 0.5, "a warehouse faces the road from the side it's placed on")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_warehouse", "kind": "medium", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"a warehouse goes up beside the road")
	_check(sim.economy.money == money - int(Balance.WAREHOUSE.medium.cost), "it costs what it says")
	_check(not sim.apply({"type": "place_warehouse", "kind": "small", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"two warehouses can't stand on the same ground")
	var w: Dictionary = sim.warehouses.buildings[1]
	_check(Warehouses.capacity(w) == int(50.0 * 60.0 / Balance.WAREHOUSE_M2_PER_LOAD), "it holds %d loads" % Warehouses.capacity(w))
	var front_lot := ""
	for key in sim.lots:
		if Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), sim.warehouses.footprint(1)):
			front_lot = key
	_check(front_lot == "", "no lots are left under it")
	sim.apply({"type": "place_industry", "kind": "oil", "pos": [best.x, best.z + 20], "dir": [0, -1]})
	var twin := CitySim.new()
	twin.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var to_wh := 0
	for i in 1440 * 3:
		sim.tick()
		twin.tick()
		for id in sim.logistics.trips:
			if sim.logistics.trips[id].to.ref == "wh:1":
				to_wh += 1
	_check(to_wh > 0, "tankers drove crude to the warehouse")
	_check(Warehouses.stored(w, Warehouses.RAW) > 0 and w.stock.raw.has("crude oil"),
		"the crude is in stock (%s)" % str(w.stock))
	_check(sim.logistics.exported == 0, "none of it left town while the warehouse had room")
	_check(twin.warehouses.buildings[1].stock == w.stock, "two copies store the same loads (multiplayer)")
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(back.warehouses.buildings[1].stock == w.stock and back.warehouses.buildings[1].incoming == w.incoming,
		"a save keeps its stock and the loads on the way")
	var sel := Inspect.pick(sim, Warehouses.center(w))
	var info := Inspect.describe(sim, sel)
	_check(sel.get("type") == "warehouse" and info.get("title") == "Warehouse", "clicking it opens its panel")
	_check(sim.stats.jobs >= int(Balance.WAREHOUSE.medium.jobs), "its jobs count")

	# A factory in need takes from the warehouse before importing.
	var town := CitySim.new()
	town.economy.money = 50_000_000
	town.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	town.build_county_road(Vector2(300, 0), Vector2(2000, 0), [1])
	var ws := Warehouses.site_near(town.network, Vector3(-200, 0, -60))
	town.apply({"type": "place_warehouse", "kind": "small", "pos": [ws[0].x, ws[0].z], "dir": [ws[1].x, ws[1].z]})
	var store: Dictionary = town.warehouses.buildings[1]
	store.stock.raw["logs"] = 10
	for x in range(0, 281, 10):
		town.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	var from_wh := 0
	for i in 1440 * 2:
		town.tick()
		for id in town.logistics.trips:
			if town.logistics.trips[id].from.ref == "wh:1" and town.logistics.trips[id].to.ref.begins_with("lot:"):
				from_wh += 1
	_check(town.count_buildings(ZoneMap.Zone.INDUSTRIAL) > 0, "factories grew")
	_check(from_wh > 0, "log trucks drove from the warehouse to the factories")
	_check(int(store.stock.raw.get("logs", 0)) < 10, "the warehouse's logs went down (%d left)" % int(store.stock.raw.get("logs", 0)))

	# Full twice: it builds up first, then out into free land behind it.
	var grow := CitySim.new()
	grow.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	var gs := Warehouses.site_near(grow.network, Vector3(0, 0, 60))
	grow.apply({"type": "place_warehouse", "kind": "small", "pos": [gs[0].x, gs[0].z], "dir": [gs[1].x, gs[1].z]})
	var g: Dictionary = grow.warehouses.buildings[1]
	var levels := []
	for round in 8:
		g.stock.goods["goods"] = Warehouses.capacity(g)
		grow.warehouses.decide(grow)
		levels.append([g.level, g.bays])
	_check(levels[1] == [1, 0] and levels[3] == [2, 0], "it builds up to taller racks before it buys land (%s)" % str(levels))
	_check(g.bays >= 1, "then it adds bays at the back (%s)" % str(levels))
	var before: int = g.bays
	var behind: float = g.pos.z + Warehouses.site_depth(g) + 12.0
	_check(grow.apply({"type": "build_road", "start": [-300, behind], "ctrl": [0, behind], "end": [300, behind]})
		and grow.warehouses.buildings.has(1), "a road can run just behind it")
	for round in 6:
		g.stock.goods["goods"] = Warehouses.capacity(g)
		grow.warehouses.decide(grow)
	_check(g.bays <= before + 1 and g.get("boxed", "") != "", "a road behind it stops it growing that way: %s" % g.get("boxed", ""))
	g.stock.goods.clear()
	var bays_full: int = g.bays
	for round in Balance.WAREHOUSE_IDLE_STREAK * 2:
		grow.warehouses.decide(grow)
	_check(g.bays < bays_full, "an empty warehouse gives bays back")
	# The road wins: a road through it bulldozes it and pays it back.
	var c := Warehouses.center(g)
	money = grow.economy.money
	grow.apply({"type": "build_road", "start": [c.x - 100, c.z - 1], "ctrl": [c.x, c.z], "end": [c.x + 100, c.z + 1]})
	_check(grow.warehouses.buildings.is_empty() and grow.economy.money > money, "a road through it bulldozes it and pays it back")
	# Its owner develops it from its tree with its own profit: a truck yard
	# first, on free land behind it, unless you've told them to hold off.
	var dev := CitySim.new()
	dev.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	var ds := Warehouses.site_near(dev.network, Vector3(0, 0, 60))
	dev.apply({"type": "place_warehouse", "kind": "medium", "pos": [ds[0].x, ds[0].z], "dir": [ds[1].x, ds[1].z]})
	var d: Dictionary = dev.warehouses.buildings[1]
	_check(dev.apply({"type": "guide", "hub": "warehouse", "hub_id": 1, "stance": "hold", "grant": 0}),
		"you can give its owner your word")
	d.flow = 60.0
	d.handled = 60
	var depth0 := Warehouses.site_depth(d)
	dev.warehouses.decide(dev)
	_check(d.has("leader") and not "truck_yard" in d.get("built", []), "held off, it buys no land for a truck yard")
	dev.apply({"type": "guide", "hub": "warehouse", "hub_id": 1, "stance": "steady", "grant": 0})
	var jobs0 := Warehouses.job_count(d)
	d.handled = 60
	dev.warehouses.decide(dev)
	_check(Warehouses.yearly_profit(d) > 0.0 and "truck_yard" in d.get("built", []),
		"a profitable owner builds a truck yard (%s, $%d/yr)" % [str(d.get("built", [])), int(Warehouses.yearly_profit(d))])
	_check(is_equal_approx(Warehouses.site_depth(d), depth0 + 20.0) and Warehouses.job_count(d) == jobs0 + 4,
		"the yard takes 20 m behind it and adds 4 jobs")
	_check(str(d.get("why", "")).contains("truck yard"), "its panel says why: %s" % d.get("why", ""))
	var dsave := CitySim.new()
	dsave.from_dict(JSON.parse_string(JSON.stringify(dev.to_dict())))
	var d2: Dictionary = dsave.warehouses.buildings[1]
	# (Compared as saved text: a snapped float like 0.35 isn't exact in binary.)
	_check(d2.built == d.built and JSON.stringify(d2.leader, "", true) == JSON.stringify(d.leader, "", true) and is_equal_approx(Warehouses.site_depth(d2), Warehouses.site_depth(d)),
		"a save keeps its owner and what they built")
	var rows: Array = Inspect.describe(dev, {"type": "warehouse", "id": 1}).rows
	_check(rows.any(func(r): return r[0] == "Built" and str(r[1]).contains("Truck yard")), "the panel lists what it has built")
	_check(dev.permits.locators.has("warehouse"), "its info panel offers your word to the owner")
	# A regional DC trucks what neighbouring towns bought out to the county
	# road; a fulfillment center sends trailers of parcels to the post office.
	var hub := CitySim.new()
	hub.economy.money = 50_000_000
	hub.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	hub.build_county_road(Vector2(300, 0), Vector2(2000, 0), [1])
	var hs := Warehouses.site_near(hub.network, Vector3(-150, 0, 60))
	hub.apply({"type": "place_warehouse", "kind": "large", "pos": [hs[0].x, hs[0].z], "dir": [hs[1].x, hs[1].z]})
	var ps := CivicHubs.site_near(hub.network, Vector3(200, 0, -60))
	_check(hub.apply({"type": "place_post_office", "pos": [ps[0].x, ps[0].z], "dir": [ps[1].x, ps[1].z]}), "a post office down the street")
	var r: Dictionary = hub.warehouses.buildings[1]
	r.built = ["truck_yard", "cross_dock", "regional_dc", "sortation", "fulfillment"]
	r.stock.goods["goods"] = 6
	hub.trade.sold_last["goods"] = 3.0
	hub.warehouses.decide(hub)
	_check(int(r.get("owed", 0)) == 3 and hub.trade.offers.has("goods"),
		"it owes the neighbours 3 loads and offers them more (%s)" % str(hub.trade.offers.get("goods")))
	r.parcels = Balance.WAREHOUSE_PARCEL_TRUCK
	var to_edge := 0
	var to_post := 0
	for i in 1440:
		hub.tick()
		for id in hub.logistics.trips:
			var t: Dictionary = hub.logistics.trips[id]
			if t.from.ref == "wh:1" and t.to.ref == "edge" and t.kind == "regional":
				to_edge += 1
			if t.from.ref == "wh:1" and str(t.to.ref).begins_with("mail:"):
				to_post += 1
	_check(to_edge > 0 and int(r.get("owed", 0)) < 3, "trucks took the neighbours' goods out of town (%d owed)" % int(r.get("owed", 0)))
	_check(to_post > 0, "a trailer of parcels drove to the post office")
	# Another thread's building (a grain elevator) can store loads too.
	var region := CitySim.new()
	region.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	var elevator := region.warehouses.add_store(Vector3(0, 0, 14), 40, ["corn", "soybeans"])
	_check(region.warehouses.take_room(Vector3.ZERO, "logs") == -1, "a grain elevator won't take logs")
	_check(region.warehouses.take_room(Vector3.ZERO, "corn") == elevator, "it takes corn")
	var saved := CitySim.new()
	saved.from_dict(JSON.parse_string(JSON.stringify(region.to_dict())))
	var st: Dictionary = saved.warehouses.buildings[elevator]
	_check(Warehouses.capacity(st) == 40 and st.accepts == ["corn", "soybeans"] and st.incoming == 1,
		"a save keeps what it takes and its size")
	_check(region.warehouses.at(Vector3(0, 0, 14)) == -1 and region.warehouses.decide(region) == false,
		"it isn't drawn, picked or grown as a warehouse")
	if _failed == 0:
		print("ALL TESTS PASSED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1
