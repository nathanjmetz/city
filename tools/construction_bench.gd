extends SceneTree
## Times Construction.tick in a growing town of a few blocks (total and the
## worst tick), for keeping building sites cheap.
## Run: godot --headless -s tools/construction_bench.gd -- [ticks]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[0]) if args.size() > 0 else 4000
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_county_road", "a": [-400, 0], "b": [-400, -1500], "links": [1]})
	for row in 5:
		var z := row * 80.0
		sim.apply({"type": "build_road", "start": [-400, z], "ctrl": [0, z], "end": [400, z]})
		for x in range(-390, 391, 10):
			sim.apply({"type": "paint_zone", "center": [x, z + 15], "radius": 10,
				"zone": ZoneMap.Zone.COMMERCIAL if x > 250 else ZoneMap.Zone.RESIDENTIAL})
			if row > 0:
				sim.apply({"type": "paint_zone", "center": [x, z - 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in [-400, 0, 400]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 160], "end": [x, 320]})
	Perf.reset()
	var t0 := Time.get_ticks_msec()
	for i in ticks:
		sim.tick()
	var c: Dictionary = Perf.stats.get("sim.construction", {"sum": 0.0, "max": 0.0})
	print("buildings %d sites %d trips %d cars %d" % [sim.buildings.size(), sim.construction.sites.size(),
		sim.construction.trips.size(), sim.traffic.cars.size()])
	print("construction.tick total %.1f ms, worst %.2f ms (whole sim %d ms)" % [c.sum, c.max, Time.get_ticks_msec() - t0])
	quit()
