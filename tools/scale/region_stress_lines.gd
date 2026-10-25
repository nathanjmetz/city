extends SceneTree
## Times the city-line rebuild (scripts/net/city_lines.gd, the cream dashed
## line between neighbors) on the towns of a stress region, for 2, 3, ...
## towns, exactly as CityLines._rebuild does it, but with no window. Each
## player's game does this on its main thread whenever a neighbor's town
## changes (at most every 15 s), so the time here is a freeze.
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
		var t0 := Time.get_ticks_usec()
		var sets := {}
		var points := 0
		for k in n:
			var pts := CityLines.city_points(region.cities[ids[k]])
			points += pts.size()
			sets[ids[k]] = CityLines.PointSet.new(pts)
		var t1 := Time.get_ticks_usec()
		var lines := 0
		var pairs := 0
		var keys: Array = sets.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var others := []
				for k in keys:
					if k != keys[i] and k != keys[j]:
						others.append(sets[k])
				lines += CityLines.trace(sets[keys[i]], sets[keys[j]], others).size()
				pairs += 1
		var t2 := Time.get_ticks_usec()
		var row := {"towns": n, "pairs": pairs, "points": points, "lines": lines,
			"points_ms": snappedf((t1 - t0) / 1000.0, 1), "trace_ms": snappedf((t2 - t1) / 1000.0, 1)}
		results.append(row)
		print(JSON.stringify(row))
	var f := FileAccess.open(path + ".lines.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	quit()
