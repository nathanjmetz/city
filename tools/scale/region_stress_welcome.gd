extends SceneTree
## Measures what a region server sends a player who joins (the "welcome":
## their own town in full and every neighbor as a postcard), for the towns of
## a stress region: how big it is packed, how long packing takes on the
## server's main thread, and whether it fits the WebSocket buffer
## (RegionServer.BUFFER_BYTES). It then says how many players like these
## would fit.
##
## Run: godot --headless -s tools/scale/region_stress_welcome.gd -- region.json
## Prints the numbers and writes region.json.welcome.json.

func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var region := Region.new()
	region.from_dict(d)
	var ids: Array = region.cities.keys()
	ids.sort()
	var out := {"buffer_bytes": RegionServer.BUFFER_BYTES, "towns": ids.size()}
	var full_sizes := []
	var card_sizes := []
	for id in ids:
		var t0 := Time.get_ticks_usec()
		var full := RegionServer.pack(region.city_data(id)).length()
		var t1 := Time.get_ticks_usec()
		var card := RegionServer.pack(region.postcard_data(id)).length()
		var t2 := Time.get_ticks_usec()
		full_sizes.append(full)
		card_sizes.append(card)
		print("%s: full copy %.2f MB packed in %.0f ms, postcard %.2f MB in %.0f ms" % [id, full / 1e6, (t1 - t0) / 1000.0, card / 1e6, (t2 - t1) / 1000.0])
	var t0 := Time.get_ticks_usec()
	var welcome := RegionServer.pack(region.to_dict(ids[0]))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("welcome for a player of %d towns: %.2f MB, to_dict and pack %.0f ms (the limit is %.1f MB)" % [ids.size(), welcome.length() / 1e6, ms, RegionServer.BUFFER_BYTES / 1e6])
	out["welcome_bytes"] = welcome.length()
	out["welcome_ms"] = ms
	out["full_bytes_avg"] = full_sizes.reduce(func(a, b): return a + b, 0) / full_sizes.size()
	out["postcard_bytes_avg"] = card_sizes.reduce(func(a, b): return a + b, 0) / card_sizes.size()
	# One player's own town in full, and a postcard for each neighbor.
	var fits := 1
	while out.full_bytes_avg + fits * out.postcard_bytes_avg < RegionServer.BUFFER_BYTES:
		fits += 1
	out["players_that_fit"] = fits
	print("so a welcome fits up to %d players with towns like these" % fits)
	var f := FileAccess.open(path + ".welcome.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	quit()
