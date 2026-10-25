extends SceneTree
## Measures what a region server sends a player who joins (the "welcome":
## their own town in full and every neighbor as a postcard), for the towns of
## a stress region: how big it is packed, how long making it takes on the
## server's main thread, how many parts it goes in (NetLink; since
## 2026-10-25 there's no size limit, where before it had to fit the
## WebSocket buffer, RegionServer.BUFFER_BYTES, and eight big towns didn't),
## and how long the game takes to read it back.
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
	# The welcome as the server sends it now: the region packed small and
	# each town as it was kept, packed (RegionServer._region_msg), made into
	# text and cut into parts (NetLink). This is the server's main-thread time.
	var server := RegionServer.new()
	server.region = region
	region.pack_all()
	var t0 := Time.get_ticks_usec()
	var msg := server._region_msg("welcome", ids, ids[0])
	var bytes := JSON.stringify(msg, "", false, true).to_utf8_buffer()
	var parts := NetLink.split(bytes)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("welcome for a player of %d towns: %.2f MB in %d parts, made in %.0f ms (no size limit now; a part is %.1f MB)"
		% [ids.size(), bytes.size() / 1e6, parts.size(), ms, NetLink.PART_BYTES / 1e6])
	out["welcome_bytes"] = bytes.size()
	out["welcome_ms"] = ms
	out["welcome_parts"] = parts.size()
	out["full_bytes_avg"] = full_sizes.reduce(func(a, b): return a + b, 0) / full_sizes.size()
	out["postcard_bytes_avg"] = card_sizes.reduce(func(a, b): return a + b, 0) / card_sizes.size()
	# The client's side: unpacking it all (on the loading screen).
	t0 = Time.get_ticks_usec()
	var back = RegionClient._region_of(JSON.parse_string(bytes.get_string_from_utf8()))
	out["client_unpack_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["client_reads_it"] = back is Dictionary and back.cities.size() == ids.size()
	print("the game reads it back in %.0f ms: %s" % [out.client_unpack_ms, out.client_reads_it])
	server.free()
	var f := FileAccess.open(path + ".welcome.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	quit()
