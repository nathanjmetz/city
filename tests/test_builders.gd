extends SceneTree
## The town's home builder (Builders) and its yard.
## Run: godot --headless -s tests/test_builders.gd

var _failed := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 5_000_000
	sim.apply({"type": "build_county_road", "a": [-200, 0], "b": [-200, -900], "links": [1]})
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [200, 0], "ctrl": [200, 100], "end": [200, 200]})
	_check(sim.services.cost_of(Services.Kind.BUILDER_YARD) == 0, "a town's first builder's yard is free")
	var site := Services.site_near(sim.network, Services.Kind.BUILDER_YARD, Vector3(150, 0, 60))
	var money := sim.economy.money
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.BUILDER_YARD, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}) and sim.economy.money == money, "it's placed beside a street, free")
	var yid := sim.services.yard()
	_check(yid != -1 and sim.construction.is_done("svc:%d" % yid, sim.tick_count), "the yard is ready at once")
	var other := Services.site_near(sim.network, Services.Kind.BUILDER_YARD, Vector3(-120, 0, -40))
	_check(sim.services.site_problem(sim.network, Services.Kind.BUILDER_YARD, other[0], other[1]) != ""
		and sim.services.cost_of(Services.Kind.BUILDER_YARD) > 0, "one per town")
	var co: Dictionary = sim.builders.companies[yid]
	_check(str(co.name).ends_with("Builders") and str(co.owner) != "" and co.leader.has("caution"),
		"it has an owner and a name (%s, %s)" % [co.name, co.owner])
	_check(sim.builders.owned(yid, "work_pickup") > 0 and sim.builders.owned(yid, "concrete_mixer") > 0,
		"it starts with crews in pickups and a concrete truck")
	_check(sim.builders.standing(sim).size() == sim.builders.owned(yid, "work_pickup") + sim.builders.owned(yid, "concrete_mixer"),
		"its trucks stand in the yard while there's no work")
	var reach := sim.services.reach_from(sim.network, Builders.gate(sim.services.buildings[yid]))
	_check(reach.size() > 2, "its reach along the roads shows while it's placed")

	# Homes: crews come from the yard, and the town grows as it would anyway.
	for x in range(-190, 191, 10):
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	var from_yard := 0
	var heading := 0
	var cash0 := int(co.cash)
	for i in 1800:
		sim.tick()
		var coming := 0
		for t in sim.construction.trips.values():
			if t.inbound:
				coming += 1
				if int(t.get("yard", -1)) == yid and t.kind == "work_pickup":
					from_yard += 1
		heading = maxi(heading, coming)
	var done := 0
	for key in sim.buildings:
		done += 1 if sim.construction.is_done("lot:" + key, sim.tick_count) else 0
	_check(from_yard > 0, "crews drive out of the yard to the new houses")
	_check(heading <= Construction.MAX_ON_ROAD, "never more than %d site trips heading in (%d)" % [Construction.MAX_ON_ROAD, heading])
	_check(done == sim.buildings.size() and done > 5, "the homes go up on time (%d of %d)" % [done, sim.buildings.size()])
	_check(int(co.done) > 0, "the company is paid for the houses it built (%d)" % int(co.done))
	_check(sim.builders.owned(yid, "work_pickup") > Balance.BUILDER_START_FLEET.work_pickup or int(co.cash) != cash0,
		"its owner buys trucks and keeps books as the town grows")
	var info := Inspect.describe(sim, {"type": "service", "id": yid})
	_check(str(info.get("title", "")) == str(co.name) and info.rows.size() >= 4, "clicking the yard shows its company")

	# Saves and copies.
	var snapshot = JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true))
	var a := CitySim.new()
	a.from_dict(snapshot)
	var b := CitySim.new()
	b.from_dict(snapshot)
	_check(a.builders.companies.has(yid) and a.builders.owned(yid, "work_pickup") == sim.builders.owned(yid, "work_pickup")
		and int(a.builders.companies[yid].cash) == int(co.cash), "a save keeps the company, its trucks and its money")
	for i in 120:
		sim.tick()
		a.tick()
		b.tick()
	_check(JSON.stringify(a.builders.to_dict()) == JSON.stringify(b.builders.to_dict())
		and JSON.stringify(a.construction.to_dict()) == JSON.stringify(b.construction.to_dict()),
		"two copies of the town agree on the builder (multiplayer)")
	var sa = JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true))
	var aa = JSON.parse_string(JSON.stringify(a.to_dict(), "", false, true))
	_check(JSON.stringify(sa.builders) == JSON.stringify(aa.builders)
		and JSON.stringify(sa.construction) == JSON.stringify(aa.construction),
		"and the town that kept running agrees with its copy loaded from a save")

	# A town from before the builder's yard is told it can have one.
	var old := CitySim.new()
	old.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in [-200, -100, 100, 200]:
		old.apply({"type": "build_road", "start": [x, -150], "ctrl": [x, 0], "end": [x, 150]})
	var said := false
	for t in Advisor.tips(old):
		said = said or t.id == "builder_yard"
	_check(said, "a town without a builder's yard hears it can place one free")

	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
