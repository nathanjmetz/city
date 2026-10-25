extends SceneTree
## Where the time goes, step by step, in a PerfTown grid town: the build and
## fill split, each part's mean and worst, and what the worst steps spent
## their time on (and at what time of day).
## Run: godot --headless -s tools/scale/scale_profile.gd -- BLOCKS TICKS [SAVE.json]
## With SAVE.json, a filled town is saved there, and loaded from there next
## time instead of built again (quicker for looking at the running town).
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var blocks := args[0]
	var ticks := int(args[1])
	var save: String = args[2] if args.size() > 2 else ""
	var sim := CitySim.new()
	var t := Time.get_ticks_msec()
	if save != "" and FileAccess.file_exists(save):
		sim.from_dict(JSON.parse_string(FileAccess.get_file_as_string(save)))
		print("load_s ", (Time.get_ticks_msec() - t) / 1000.0)
		# Caches a loaded town builds again as it goes (places, routes).
		for i in 300:
			sim.tick()
		_run(sim, ticks)
		return
	Perf.reset()
	PerfTown.build(sim, blocks)
	print("build_s ", (Time.get_ticks_msec() - t) / 1000.0, " ", _top(_sums(), 10))
	Perf.reset()
	t = Time.get_ticks_msec()
	var last := -1
	var fill_ticks := 0
	for i in 6000:
		sim.tick()
		fill_ticks += 1
		if i % 600 == 599:
			if sim.stats.population <= last * 1.02:
				break
			last = sim.stats.population
	print("fill_s ", (Time.get_ticks_msec() - t) / 1000.0, " ticks ", fill_ticks, " ", _top(_sums(), 10))
	if save != "":
		var f := FileAccess.open(save, FileAccess.WRITE)
		f.store_string(JSON.stringify(sim.to_dict(), "", false, true))
		f.close()
	_run(sim, ticks)


func _run(sim: CitySim, ticks: int) -> void:
	Perf.reset()
	var worst := []  # [ms, tick, {key: ms}]
	var prev := {}
	var sum := 0.0
	for i in ticks:
		var a := Time.get_ticks_usec()
		sim.tick()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		sum += ms
		var now := _sums()
		var d := {}
		for k in now:
			var v: float = now[k] - float(prev.get(k, 0.0))
			if v > 0.5 and k != "sim.tick":
				d[k] = snappedf(v, 0.1)
		prev = now
		worst.append([ms, sim.tick_count, d])
	worst.sort_custom(func(x, y): return x[0] > y[0])
	print("pop ", sim.stats.population, " buildings ", sim.buildings.size(), " mean_ms ", snappedf(sum / ticks, 0.01),
		" mem_mb ", OS.get_static_memory_usage() / 1048576)
	print("mean ", _top(_sums(), 16, ticks))
	var maxes := {}
	for k in Perf.stats:
		maxes[k] = snappedf(Perf.stats[k].max, 0.1)
	print("max ", _top(maxes, 16))
	for w in worst.slice(0, 12):
		var tc: int = w[1]
		print("worst ", snappedf(w[0], 0.1), " tick ", tc, " minute_of_day ", tc % 1440, " ", _top(w[2], 6))
	quit()


func _sums() -> Dictionary:
	var r := {}
	for k in Perf.stats:
		r[k] = float(Perf.stats[k].sum)
	return r


func _top(d: Dictionary, n: int, div := 1) -> String:
	var keys := d.keys()
	keys.sort_custom(func(x, y): return d[x] > d[y])
	var out := []
	for k in keys.slice(0, n):
		out.append("%s=%s" % [k, snappedf(float(d[k]) / div, 0.01)])
	return ", ".join(out)
