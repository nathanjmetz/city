extends SceneTree
## How many people are out walking in a small town over a day, for checking
## the walking share. Run: godot --headless -s tools/walker_count.gd -- [blocks]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sim := CitySim.new()
	PerfTown.build(sim, a[0] if a.size() > 0 else "3")
	var most := 0
	var cars := 0
	for i in 1440 * 2:
		sim.tick()
		if i > 1440 and i % 10 == 0:
			most = maxi(most, sim.traffic.walkers.size())
			cars = maxi(cars, sim.traffic.cars.size())
	print("WALKERS people=%d most_walking=%d most_cars=%d" % [sim.stats.population, most, cars])
	quit()
