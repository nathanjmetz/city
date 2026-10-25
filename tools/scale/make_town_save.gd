extends SceneTree
## Builds a grid town of N blocks a side (PerfTown's layout), lets it fill
## until the population stops growing, and saves it as a game save file, so
## the browser can open a big town without building it (tools/playtest/
## web_playtest.mjs serves the file; `?town=` in scripts/perf/playtest.gd).
## Run: godot --headless -s tools/scale/make_town_save.gd -- BLOCKS OUT.city
## The save lands wherever OUT says: never in user://cities (a real town).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var blocks := args[0]
	var out := args[1]
	var sim := CitySim.new()
	var t := Time.get_ticks_msec()
	PerfTown.build(sim, blocks)
	var build_s := (Time.get_ticks_msec() - t) / 1000.0
	t = Time.get_ticks_msec()
	var last := -1
	for i in 6000:
		sim.tick()
		if i % 600 == 599:
			if sim.stats.population <= last * 1.02:
				break
			last = sim.stats.population
	var fill_s := (Time.get_ticks_msec() - t) / 1000.0
	var raw := var_to_bytes(sim.to_dict())
	var meta := {"name": "Measure %s" % blocks, "population": sim.stats.population,
		"money": int(sim.economy.money), "saved": int(Time.get_unix_time_from_system())}
	var f := FileAccess.open(out, FileAccess.WRITE)
	var head := JSON.stringify(meta).to_utf8_buffer()
	f.store_buffer("NBT1".to_ascii_buffer())  # Session.SAVE_MAGIC (not reachable here)
	f.store_32(head.size())
	f.store_buffer(head)
	f.store_32(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	print("TOWNSAVE blocks %s: %d people, %d buildings, built in %.0f s, filled in %.0f s, file %.1f MB (%.1f MB raw)" % [
		blocks, sim.stats.population, sim.buildings.size(), build_s, fill_s,
		FileAccess.get_size(out) / 1048576.0, raw.size() / 1048576.0])
	quit()
