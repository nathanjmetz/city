extends SceneTree
## Measures what a region server sends a player who joins, for the towns of
## a stress region. Since 2026-10-25 that's the "welcome" (the region
## without its towns, and the player's own town in full) and then each
## neighbor on its own as a picture (Region.picture_of). Before, the welcome
## held every neighbor as a postcard in one message, and for eight grown
## towns it outgrew the WebSocket buffer (RegionServer.BUFFER_BYTES) and the
## player waited for ever. Prints how big each is, how long the server takes
## to make the welcome (its main thread), how many parts it goes in
## (NetLink), and how long the game takes to read them.
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
	var pic_sizes := []
	var pic_ms := []
	for id in ids:
		var full := RegionServer.pack(region.city_data(id)).length()
		var card := RegionServer.pack(region.postcard_data(id)).length()
		var t := Time.get_ticks_usec()
		var pic := region.packed_card(id).length()
		pic_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		full_sizes.append(full)
		card_sizes.append(card)
		pic_sizes.append(pic)
		print("%s: full copy %.2f MB, postcard %.2f MB, picture %.2f MB (made in %.0f ms, on another core on the server)"
			% [id, full / 1e6, card / 1e6, pic / 1e6, pic_ms[-1]])
	var server := RegionServer.new()
	server.region = region
	region.pack_all()
	# The old welcome, for comparison: every town in one message.
	var old := {"t": "welcome", "z": RegionServer.pack(region.to_dict("", false)), "towns": {}}
	for id in ids:
		old.towns[id] = region.packed_full(id) if id == ids[0] else RegionServer.pack(region.postcard_data(id))
	out["old_welcome_bytes"] = JSON.stringify(old, "", false, true).length()
	# The welcome now, as the server makes it on its main thread.
	var t0 := Time.get_ticks_usec()
	var msg := server._region_msg("welcome", [ids[0]], ids[0])
	var bytes := JSON.stringify(msg, "", false, true).to_utf8_buffer()
	var parts := NetLink.split(bytes)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var neighbors := 0
	for id in ids.slice(1):
		neighbors += JSON.stringify({"t": "city", "id": id, "z": region.packed_card(id), "land": region.land_flat(id)}).length()
	print("welcome for a player of %d towns: %.2f MB in %d parts, made in %.0f ms; then %d neighbors, %.2f MB in all (before: %.2f MB in one message)"
		% [ids.size(), bytes.size() / 1e6, parts.size(), ms, ids.size() - 1, neighbors / 1e6, out.old_welcome_bytes / 1e6])
	out["welcome_bytes"] = bytes.size()
	out["welcome_ms"] = ms
	out["welcome_parts"] = parts.size()
	out["neighbors_bytes"] = neighbors
	out["full_bytes_avg"] = full_sizes.reduce(func(a, b): return a + b, 0) / full_sizes.size()
	out["postcard_bytes_avg"] = card_sizes.reduce(func(a, b): return a + b, 0) / card_sizes.size()
	out["picture_bytes_avg"] = pic_sizes.reduce(func(a, b): return a + b, 0) / pic_sizes.size()
	out["picture_make_ms_avg"] = pic_ms.reduce(func(a, b): return a + b, 0.0) / pic_ms.size()
	# The game's side: reading the welcome (on the loading screen), and a
	# neighbor's picture (on another core) and loading it (main thread).
	t0 = Time.get_ticks_usec()
	var back = RegionClient._region_of(JSON.parse_string(bytes.get_string_from_utf8()))
	out["client_welcome_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["client_reads_it"] = back is Dictionary and back.cities.size() == ids.size() and back.cities[ids[0]].has("city")
	t0 = Time.get_ticks_usec()
	var pic = Region.from_picture(RegionServer.unpack(region.packed_card(ids[1])))
	out["client_picture_unpack_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var sim := Region.new_sim()
	sim.from_dict(pic)
	out["client_picture_load_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	print("the game reads the welcome in %.0f ms (%s); a neighbor's picture unpacks in %.0f ms and loads in %.0f ms (%d buildings)"
		% [out.client_welcome_ms, out.client_reads_it, out.client_picture_unpack_ms, out.client_picture_load_ms, sim.buildings.size()])
	server.free()
	var f := FileAccess.open(path + ".welcome.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	quit()
