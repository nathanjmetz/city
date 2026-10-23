extends SceneTree
## The performance benchmark: builds the big test town (PerfTown), plays it
## and reports how long each system takes per simulation tick, against the
## budgets in PerfBudget.
## Run: godot --headless -s tools/perf_run.gd -- [size] [ticks] [out.json]
## The render half lives in tools/perf_render.gd.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size: String = args[0] if args.size() > 0 else "big"
	var ticks := int(args[1]) if args.size() > 1 else 1440
	var out: String = args[2] if args.size() > 2 else ""
	var sim := CitySim.new()
	var t := Time.get_ticks_msec()
	PerfTown.build(sim, size)
	var build_s := (Time.get_ticks_msec() - t) / 1000.0
	# Let traffic fill the streets before measuring.
	for i in 600:
		sim.tick()
	Perf.reset()
	t = Time.get_ticks_msec()
	for i in ticks:
		sim.tick()
	var run_s := (Time.get_ticks_msec() - t) / 1000.0
	var report := {"size": size, "ticks": ticks, "build_s": build_s, "run_s": run_s,
		"population": sim.stats.population, "buildings": sim.buildings.size(),
		"segments": sim.network.segments.size(), "vehicles": sim.traffic.cars.size(),
		"memory_mb": OS.get_static_memory_usage() / 1048576.0, "systems": {}}
	for key in Perf.stats:
		var s: Dictionary = Perf.stats[key]
		# Per tick: total time over every tick, so rare work counts in full.
		report.systems[key] = {"per_tick": s.sum / ticks, "max": s.max, "runs": s.n}
	print(PerfBudget.sim_table(report))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
	quit()
