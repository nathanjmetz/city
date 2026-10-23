extends SceneTree
## Run: godot --headless -s tests/test_first_town.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.require_utilities = true
	sim.simulate_traffic = false
	# A new town, as main.gd starts one: the county highway and a road in.
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	_check(FirstTown.current(sim) == "streets", "a new town starts on streets (%s)" % FirstTown.current(sim))
	_check(FirstTown.plan().size() == 5, "the plan has five goals")

	# The suggested grid is two town blocks each way, off the road's end.
	var spot := FirstTown.grid_spot(sim)
	_check(spot.size() == 2, "there's a spot for the first grid")
	_check(spot[0].distance_to(Vector3(40, 0, 60)) < 1.0, "it starts at the end of the road in (%s)" % str(spot[0]))
	var p: Dictionary = GridFill.PRESETS[FirstTown.GRID_PRESET]
	_check(p.name == "Town", "the tour's grid size is the Midwest town plat")
	var ok := sim.apply({"type": "build_grid_shape", "points": [[spot[0].x, spot[0].z], [spot[1].x, spot[0].z],
		[spot[1].x, spot[1].z], [spot[0].x, spot[1].z]],
		"block": p.block, "across": p.across, "side": 0, "road": RoadStyle.Type.STREET})
	_check(ok, "the suggested grid builds")
	_check(FirstTown.junctions(sim) >= FirstTown.JUNCTIONS, "the grid makes crossings (%d)" % FirstTown.junctions(sim))
	_check(FirstTown.current(sim) == "power", "then power (%s)" % FirstTown.current(sim))

	# Power: the suggested spot is one the tool takes, and the line takes a
	# real few weeks to go in before it supplies anything.
	var at := FirstTown.site_spot(sim, "power")
	_check(at != Vector3.INF, "there's a spot for the power line")
	var site := Services.site_near(sim.network, Services.Kind.POWER_FEED, at)
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.POWER_FEED, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "the power line goes in there")
	sim.update_stats()
	_check(FirstTown.current(sim) == "power_wait", "then the line crew works (%s)" % FirstTown.current(sim))
	_check(sim.services.utility_use.power[1] == 0, "no power until it's energized")
	var crew := FirstTown.crew(sim, "power_wait")
	_check(not crew.is_empty() and crew.total < 0.1, "the crew's progress shows")
	_check(sim.utilities_going_up().size() == 1, "the city knows it's going in")
	var dur := Construction.duration("power_feed")
	_check(dur > 0 and dur <= 300, "a power line goes in within half a minute at normal speed (%d ticks)" % dur)
	for i in dur + 20:
		sim.tick()
	_check(sim.services.utility_use.power[1] > 0, "power's on once it's energized")
	_check(FirstTown.current(sim) == "water", "then water (%s)" % FirstTown.current(sim))

	# Water: a well, drilled and tested before it goes on line.
	at = FirstTown.site_spot(sim, "water")
	_check(at != Vector3.INF, "there's a spot for the well")
	site = Services.site_near(sim.network, Services.Kind.WELL, at)
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.WELL, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "the well goes in there")
	sim.update_stats()
	_check(FirstTown.current(sim) == "water_wait", "then the driller works (%s)" % FirstTown.current(sim))
	_check(FirstTown.crew(sim, "water_wait").words != "", "says what the driller is doing")
	for i in Construction.duration("well") + 20:
		sim.tick()
	_check(FirstTown.current(sim) == "homes", "then homes (%s)" % FirstTown.current(sim))

	# Homes: zoned along the grid's streets, then builders, then people.
	var mid: Vector3 = (spot[0] + spot[1]) * 0.5
	for dx in range(-120, 121, 10):
		for dz in [-100, -10, 10, 100]:
			sim.apply({"type": "paint_zone", "center": [mid.x + dx, mid.z + dz], "radius": 14, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(FirstTown.current(sim) == "builders", "then the builders (%s)" % FirstTown.current(sim))
	var saw_house := false
	for i in 4000:
		sim.tick()
		if not saw_house and not FirstTown.crew(sim, "builders").is_empty():
			saw_house = true
		if FirstTown.current(sim) == "done":
			break
	_check(saw_house, "a house going up shows its progress")
	_check(FirstTown.current(sim) == "done", "and the first family moves in (%s, %d people)" % [FirstTown.current(sim), sim.stats.population])
	print("first town: all checks passed" if _failed == 0 else "first town: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)


var _failed := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		print("FAIL: ", what)
