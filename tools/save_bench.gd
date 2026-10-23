extends SceneTree
## How long sending and saving a town takes on the main thread, on the big
## test town (PerfTown): the full copy, the neighbors' postcard, and loading
## each as a neighbor does.
## Run: godot --headless -s tools/save_bench.gd -- [size] [ticks]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size: String = args[0] if args.size() > 0 else "big"
	var ticks := int(args[1]) if args.size() > 1 else 60
	var sim := CitySim.new()
	PerfTown.build(sim, size)
	for i in ticks:
		sim.tick()
	print("population %d, buildings %d" % [sim.stats.population, sim.buildings.size()])
	sim.to_dict(true)  # as a town that has sent before
	for postcard in [false, true]:
		var what := "postcard" if postcard else "full copy"
		var t := Time.get_ticks_usec()
		var d := sim.to_dict(postcard)
		var t_dict := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var raw := var_to_bytes(d)
		var t_bytes := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var z := RegionServer.pack_bytes(raw)
		var t_pack := Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var back: Dictionary = RegionServer.unpack(z)
		var t_unpack := Time.get_ticks_usec() - t
		var copy := Region.new_sim()
		t = Time.get_ticks_usec()
		copy.from_dict(back)
		var t_load := Time.get_ticks_usec() - t
		print("%s: to_dict %.0f ms, to bytes %.0f ms, pack %.0f ms (%.2f MB sent), unpack %.0f ms, load %.0f ms" % [
			what, t_dict / 1000.0, t_bytes / 1000.0, t_pack / 1000.0, z.length() / 1e6, t_unpack / 1000.0, t_load / 1000.0])
		print("  loaded copy: %d buildings, %d lots, population %d" % [copy.buildings.size(), copy.lots.size(), copy.stats.population])
	var t0 := Time.get_ticks_usec()
	var old := JSON.stringify(sim.to_dict())
	print("before: JSON full copy %.0f ms (%.1f MB)" % [(Time.get_ticks_usec() - t0) / 1000.0, old.length() / 1e6])
	quit()
