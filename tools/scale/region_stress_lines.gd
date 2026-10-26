extends SceneTree
## Times the city lines (scripts/net/city_lines.gd, the cream dashed line
## between neighbors) on the towns of a stress region, for 2, 3, ... towns,
## exactly as a player's game does it, with no window: a CityLines rebuild,
## run CityLines.BUDGET_MS a frame. Reports the whole work, how many frames
## it was spread over, and the most it took in any one frame (what a player
## would feel), then the same again after one town changes.
##
## Run: godot --headless -s tools/scale/region_stress_lines.gd -- region.json [most towns]
## Prints one line per count, and writes region.json.lines.json.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var most := int(args[1]) if args.size() > 1 else 4
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var region := Region.new()
	region.from_dict(d)
	region.load_stale()
	var ids: Array = region.cities.keys()
	ids.sort()
	var results := []
	for n in range(2, mini(most, ids.size()) + 1):
		var client := RegionClient.new()
		for k in n:
			client.region.cities[ids[k]] = region.cities[ids[k]]
		var lines := CityLines.new()
		lines.client = client
		var row := {"towns": n}
		row.merge(_run(lines, ids.slice(0, n), "all_"))
		row.pairs = lines._pairs.size()
		var drawn := 0
		for k in lines._pairs:
			drawn += lines._pairs[k].size()
		row.lines = drawn
		# Laying the dashes on the ground (done once a rebuild is finished).
		lines.to_world = func(q: Vector2): return Vector3(q.x, 0.0, q.y)
		var t := Time.get_ticks_usec()
		var dashes := 0
		for k in lines._pairs:
			for line in lines._pairs[k]:
				dashes += lines._dashes(line).size()
		row.dashes = dashes
		row.dashes_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1)
		# One town changed (its player built): only what's near it again.
		row.merge(_run(lines, [ids[0]], "one_changed_"))
		results.append(row)
		print(JSON.stringify(row))
		lines.free()
		client.free()
	var f := FileAccess.open(path + ".lines.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	quit()


func _run(lines: CityLines, changed: Array, prefix: String) -> Dictionary:
	# A changed town counts as moved even if its outline came out the same.
	for id in changed:
		lines._sig.erase(id)
	var job := CityLines.Rebuild.new(lines, changed)
	var frames := 0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var done := false
	while not done:
		var t := Time.get_ticks_usec()
		done = job.step(CityLines.BUDGET_MS)
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
		frames += 1
	return {prefix + "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 1), prefix + "frames": frames,
		prefix + "worst_frame_ms": snappedf(worst, 0.1)}
