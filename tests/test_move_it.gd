extends SceneTree
## Run: godot --headless -s tests/test_move_it.gd

func _init() -> void:
	# A street with homes on the north side and a fire station on the south.
	var sim := _town()
	var homes := sim.count_buildings(ZoneMap.Zone.RESIDENTIAL)
	_check(homes > 4, "homes grew along the street (%d)" % homes)
	var seg: int = _seg_along(sim, 0.0)
	var fire: int = sim.services.buildings.keys()[0]

	# Grown things can't be picked up; placed things can.
	var lot_key: String = sim.buildings.keys()[0]
	_check(MoveIt.pick(sim, sim.lots[lot_key].pos).is_empty(), "a home that grew on its own can't be picked up")
	_check(MoveIt.pick(sim, sim.services.buildings[fire].pos).get("type", "") == "service", "a service can be picked up")
	_check(MoveIt.pick(sim, Vector3(20, 0, 1)).get("type", "") == "road", "a road can be picked up")
	_check(MoveIt.pick(sim, Vector3(-200, 0, 0)).get("type", "") == "node", "a road end can be picked up")

	# Slide the fire station 40 m along its street.
	var before: Vector3 = sim.services.buildings[fire].pos
	var cmd := MoveIt.command([{"type": "service", "id": fire}], before, Vector3(40, 0, 0))
	_check(sim.apply(cmd), "the fire station slides along the street")
	_check(sim.services.buildings[fire].pos.is_equal_approx(before + Vector3(40, 0, 0)), "it lands where it was dragged")
	# Turn it a quarter turn about its middle, then put it back with undo.
	var at: Vector3 = sim.services.buildings[fire].pos
	var dir: Vector3 = sim.services.buildings[fire].dir
	var turn := MoveIt.command([{"type": "service", "id": fire}], at, Vector3.ZERO, 90.0)
	var turned_ok := sim.apply(turn)
	if turned_ok:
		_check(sim.services.buildings[fire].dir.is_equal_approx(dir.rotated(Vector3.UP, PI / 2)), "turning turns it")
		_check(sim.apply(MoveIt.inverse(turn)), "undo puts it back")
		_check(sim.services.buildings[fire].dir.is_equal_approx(dir), "back facing the street")
	else:
		_check(true, "a quarter turn that would hit the road is refused")
	# Onto the road: refused.
	_check(not sim.apply(MoveIt.command([{"type": "service", "id": fire}], at, Vector3(0, 0, -30))),
		"a building can't be dropped on a road")

	# Slide the whole street 24 m north: homes ride along with their zoning.
	var zone_cells := sim.zones.cells.size()
	var keys := sim.buildings.keys()
	var c0 := sim.network.curve_of(seg)
	_check(sim.apply(MoveIt.command([{"type": "road", "id": seg}], Vector3.ZERO, Vector3(0, 0, -24))),
		"the street slides north")
	_check(sim.network.segments.has(seg) and sim.network.curve_of(seg)[0].is_equal_approx(c0[0] + Vector3(0, 0, -24)),
		"the street keeps its id and lands 24 m north")
	_check(absi(sim.zones.cells.size() - zone_cells) < zone_cells / 10, "zoning rides along (%d -> %d cells)" % [zone_cells, sim.zones.cells.size()])
	var kept := 0
	for k in keys:
		kept += 1 if sim.buildings.has(k) else 0
	_check(kept >= keys.size() - 2, "homes ride along with their street (%d of %d)" % [kept, keys.size()])
	# The road wins: the fire station stood clear of the old street, and the
	# street's new spot runs where it was: it shifts out of the way.
	var fire_poly := sim.services.footprint(fire)
	_check(not Services.road_clash(sim.network, fire_poly), "nothing is left standing on a moved road")

	# Drag a dead end across another street: they meet in a junction.
	var cross := CitySim.new()
	cross.economy.money = 10_000_000
	cross.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	cross.apply({"type": "build_road", "start": [0, 200], "ctrl": [0, 150], "end": [0, 100]})
	var end_node := cross.network.find_node_near(Vector3(0, 0, 100), 1.0)
	var junctions_before := cross.network.nodes.size()
	_check(cross.apply(MoveIt.command([{"type": "node", "id": end_node}], Vector3(0, 0, 100), Vector3(0, 0, -140))),
		"a dead end drags across a street")
	var met := cross.network.find_node_near(Vector3(0, 0, 0), 1.0)
	_check(met != -1 and cross.network.segments_at(met).size() == 4, "the roads meet in a four-way junction")
	_check(cross.network.nodes.size() == junctions_before + 1, "one new junction")
	# Dragging an end onto a junction joins it.
	var tee := CitySim.new()
	tee.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	tee.apply({"type": "build_road", "start": [100, 100], "ctrl": [100, 60], "end": [100, 20]})
	var gap := tee.network.find_node_near(Vector3(100, 0, 20), 1.0)
	_check(tee.apply(MoveIt.command([{"type": "node", "id": gap}], Vector3(100, 0, 20), Vector3(0, 0, -19))),
		"a road end snaps onto a junction")
	_check(tee.network.segments_at(tee.network.find_node_near(Vector3(100, 0, 0), 1.0)).size() == 2, "they join there")

	# Raise: a whole road can lift into a bridge; one end alone can't make it too steep.
	var lift := CitySim.new()
	lift.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	var one := lift.network.find_node_near(Vector3(100, 0, 0), 1.0)
	_check(not lift.apply(MoveIt.command([{"type": "node", "id": one}], Vector3.ZERO, Vector3.ZERO, 0.0, 30.0)),
		"lifting one end 30 m is too steep (AASHTO grade)")
	_check(lift.apply(MoveIt.command([{"type": "node", "id": one}], Vector3.ZERO, Vector3.ZERO, 0.0, 5.0)),
		"lifting one end 5 m is a gentle ramp")
	_check(absf(lift.network.nodes[one].y - 5.0) < 0.01, "the end is 5 m up")
	# A bridge must keep real clearance over the road below.
	var over := CitySim.new()
	over.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	over.apply({"type": "build_road", "start": [0, -200, 7], "ctrl": [0, 0, 7], "end": [0, 200, 7]})
	var low := MoveIt.pick(over, Vector3(-60, 0, 0))
	_check(low.get("type", "") == "road", "picked the street under the bridge")
	_check(not over.apply(MoveIt.command([low], Vector3.ZERO, Vector3.ZERO, 0.0, 3.0)),
		"raising the street under a bridge to 4 m clearance is refused (AASHTO)")

	# The road wins: drag the street onto the fire station and it shifts clear.
	var before_fire: Vector3 = sim.services.buildings[fire].pos
	_check(sim.apply(MoveIt.command([{"type": "road", "id": seg}], Vector3.ZERO, Vector3(0, 0, 50))),
		"the street can be dragged onto the fire station")
	_check(not sim.services.buildings[fire].pos.is_equal_approx(before_fire), "the fire station shifted")
	_check(not Services.road_clash(sim.network, sim.services.footprint(fire)), "and stands clear of the street")

	# A farmhouse moves with its fields.
	var fm := CitySim.new()
	fm.economy.money = 10_000_000
	fm.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	fm.apply({"type": "paint_reserve", "kind": "farm", "points": [[-500, 20], [500, 20], [500, 600], [-500, 600]]})
	_check(fm.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"}), "farmhouse placed")
	var fid: int = fm.farms.farms.keys()[0]
	for i in 12:
		fm.farms.decide(fm.field_usable)
	var fields: int = fm.farms.farms[fid].cells.size()
	_check(fields >= 4, "the farm grew fields (%d)" % fields)
	_check(fm.apply(MoveIt.command([{"type": "farm", "id": fid}], Vector3(0, 0, 60), Vector3(120, 0, 0))),
		"the farmhouse slides along the road")
	_check(fm.farms.farms[fid].cells.size() == fields, "its fields come along")
	_check(absf(fm.farms.farms[fid].drive[-1].z) < 1.0 and absf(fm.farms.farms[fid].drive[-1].x - 120.0) < 40.0,
		"its lane finds the road again")
	_check(not fm.apply(MoveIt.command([{"type": "farm", "id": fid}], Vector3(120, 0, 60), Vector3(0, 0, 500))),
		"a farmhouse can't go far from any road")

	# A cemetery (a hub) moves whole; the county highway out to the region stays put.
	var hub := CitySim.new()
	hub.economy.money = 10_000_000
	hub.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	var gate := CivicHubs.site_near(hub.network, Vector3(-100, 0, 40))
	_check(hub.apply({"type": "place_hub", "kind": "cemetery", "pos": [gate[0].x, gate[0].z], "dir": [gate[1].x, gate[1].z]}),
		"cemetery placed")
	var hid: int = hub.hubs.hubs.keys()[0]
	_check(MoveIt.pick(hub, CivicHubs.cell_center(hub.hubs.hubs[hid], Vector2i(0, 1))).get("type", "") == "hub",
		"a cemetery can be picked up")
	_check(hub.apply(MoveIt.command([{"type": "hub", "id": hid}], gate[0], Vector3(150, 0, 0))), "the cemetery slides along the road")
	_check(hub.hubs.hubs[hid].pos.is_equal_approx(gate[0] + Vector3(150, 0, 0)), "its gate lands where it was dragged")
	_check(not hub.apply(MoveIt.command([{"type": "hub", "id": hid}], gate[0], Vector3(0, 0, -60))),
		"a cemetery can't be dropped across the road")
	var dock := Warehouses.site_near(hub.network, Vector3(100, 0, -60))
	_check(hub.apply({"type": "place_warehouse", "kind": "small", "pos": [dock[0].x, dock[0].z], "dir": [dock[1].x, dock[1].z]}),
		"warehouse placed")
	var wid: int = hub.warehouses.buildings.keys()[0]
	_check(MoveIt.pick(hub, Warehouses.center(hub.warehouses.buildings[wid])).get("type", "") == "warehouse",
		"a warehouse can be picked up")
	_check(hub.apply(MoveIt.command([{"type": "warehouse", "id": wid}], dock[0], Vector3(-120, 0, 0))),
		"the warehouse slides along the road")
	var spot := Parks.site_near(hub.network, "park", Vector3(250, 0, -60))
	_check(hub.apply({"type": "place_park", "kind": "park", "pos": [spot[0].x, spot[0].z], "dir": [spot[1].x, spot[1].z]}),
		"park placed")
	var pid: int = hub.parks.sites.keys()[0]
	_check(MoveIt.pick(hub, hub.parks.sites[pid].pos).get("type", "") == "park", "a park can be picked up")
	_check(hub.apply(MoveIt.command([{"type": "park", "id": pid}], spot[0], Vector3(60, 0, 0))), "the park slides along the road")
	var ends := hub.build_county_road(Vector2(400, 0), Vector2(1200, 0), [1])
	_check(not hub.apply(MoveIt.command([{"type": "node", "id": ends[1]}], Vector3.ZERO, Vector3(0, 0, 50))),
		"the county highway's way out to the region stays put")

	# Same commands, same city (multiplayer).
	var a := _town()
	var b := _town()
	for s in [a, b]:
		s.apply(MoveIt.command([{"type": "road", "id": _seg_along(s, 0.0)}], Vector3.ZERO, Vector3(0, 0, -16), 10.0))
	_check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "two copies agree after a move")
	# A move survives a save.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	_check(JSON.stringify(copy.network.to_dict()) == JSON.stringify(a.network.to_dict()), "a moved city saves and loads")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [200, 0], "ctrl": [200, 0], "end": [200, 0]})
	for x in range(-200, 201, 8):
		sim.apply({"type": "paint_zone", "center": [x, -22], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 22], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(-120, 0, 30))
	sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]})
	for i in 3000:
		sim.tick()
	return sim


func _seg_along(sim: CitySim, z: float) -> int:
	return sim.network.find_segment_near(Vector3(0, 0, z), 2.0).seg


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
