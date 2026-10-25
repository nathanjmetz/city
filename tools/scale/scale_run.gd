extends SceneTree
## Builds a grid town of N blocks a side (PerfTown's layout), fills it, and
## times a day of play: population, build time, ms per tick (mean, worst),
## where the time goes, and memory.
## Run: godot --headless -s tools/scale/scale_run.gd -- BLOCKS TICKS OUT.json
## Results of 2026-10-25: docs/scale-test-2026-10-25.md.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var blocks := args[0]
	var ticks := int(args[1])
	var town = PerfTown
	var sim := CitySim.new()
	var t := Time.get_ticks_msec()
	town.build(sim, blocks)
	var build_s := (Time.get_ticks_msec() - t) / 1000.0
	# Fill: run until the population stops growing much (capped).
	t = Time.get_ticks_msec()
	var last := -1
	for i in 6000:
		sim.tick()
		if i % 600 == 599:
			if sim.stats.population <= last * 1.02:
				break
			last = sim.stats.population
	var fill_s := (Time.get_ticks_msec() - t) / 1000.0
	Perf.reset()
	var worst := 0.0
	var sum := 0.0
	for i in ticks:
		var a := Time.get_ticks_usec()
		sim.tick()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		sum += ms
		worst = maxf(worst, ms)
	var parts := {}
	for k in Perf.stats:
		if k.begins_with("sim."):
			parts[k] = snappedf(float(Perf.stats[k].sum) / ticks, 0.01)
	var keys := parts.keys()
	keys.sort_custom(func(x, y): return parts[x] > parts[y])
	var top := {}
	for k in keys.slice(0, 8):
		top[k] = parts[k]
	var r := {"blocks": int(blocks), "population": sim.stats.population, "jobs": sim.stats.jobs, "buildings": sim.buildings.size(),
		"cars": sim.traffic.cars.size(), "walkers": sim.traffic.walkers.size(), "build_s": build_s, "fill_s": fill_s,
		"tick_ms": snappedf(sum / ticks, 0.01), "worst_ms": snappedf(worst, 0.1), "mem_mb": OS.get_static_memory_usage() / 1048576, "top": top}
	print("SCALE ", JSON.stringify(r))
	var f := FileAccess.open(args[2], FileAccess.WRITE)
	f.store_string(JSON.stringify(r, "  "))
	quit()
