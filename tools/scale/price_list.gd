extends SceneTree
## The price list's headless half (docs/price-list.md): builds and fills a
## PerfTown grid town of N blocks a side, then times TICKS steps by system
## (mean and worst per Perf key, and what the worst steps spent their time
## on), then measures memory by system.
##
## Memory is measured two ways:
## - "copy": each container a system holds is deep-copied and the growth in
##   memory is read (Strings and packed arrays are shared by a copy, so the
##   walk adds their bytes: 4 per character, the packed array's own size).
##   This is the size of that data even when another system shares it.
## - "release": at the end, each system's containers are emptied in turn and
##   the memory let go is read. These add up to what the town really holds.
## The walk also counts the Dictionaries, Arrays and packed arrays inside.
##
## Run: godot --headless -s tools/scale/price_list.gd -- BLOCKS TICKS OUT.json
## Finer timers inside traffic, people and stats were added by hand for the
## 2026-10-25 price list and not kept (see the doc).
var _report := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var blocks := args[0]
	var ticks := int(args[1])
	var out: String = args[2]
	var m0 := OS.get_static_memory_usage()
	var sim := CitySim.new()
	_report["mem_empty_sim_mb"] = _mb(OS.get_static_memory_usage())
	var t := Time.get_ticks_msec()
	Perf.reset()
	PerfTown.build(sim, blocks)
	_report["build_s"] = (Time.get_ticks_msec() - t) / 1000.0
	_report["build_parts_s"] = _top(_sums(), 12, 1000.0)
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
	_report["fill_s"] = (Time.get_ticks_msec() - t) / 1000.0
	_report["fill_ticks"] = fill_ticks
	_run(sim, ticks)
	_report["blocks"] = int(blocks)
	_report["population"] = sim.stats.population
	_report["jobs"] = sim.stats.jobs
	_report["buildings"] = sim.buildings.size()
	_report["lots"] = sim.lots.size()
	_report["road_segments"] = sim.network.segments.size()
	_report["people_records"] = sim.people.people.size()
	_report["cars_driving"] = sim.traffic.cars.size()
	_report["vehicles_parked"] = sim.traffic.parked.size()
	_report["flowing"] = sim.traffic.flowing.size()
	_report["walkers"] = sim.traffic.walkers.size()
	_report["mem_total_mb"] = _mb(OS.get_static_memory_usage())
	_report["mem_start_mb"] = _mb(m0)
	_memory(sim)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "  ", false))
	f.close()
	print("PRICE ", out, " pop ", _report["population"], " tick_ms ", _report["tick_mean_ms"], " mem_mb ", _report["mem_total_mb"])
	quit()


func _run(sim: CitySim, ticks: int) -> void:
	Perf.reset()
	var worst := []
	var prev := {}
	var sum := 0.0
	var all_ms := []
	for i in ticks:
		var a := Time.get_ticks_usec()
		sim.tick()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		sum += ms
		all_ms.append(ms)
		var now := _sums()
		var d := {}
		for k in now:
			var v: float = now[k] - float(prev.get(k, 0.0))
			if v > 0.5 and k != "sim.tick":
				d[k] = snappedf(v, 0.1)
		prev = now
		worst.append([ms, sim.tick_count, d])
	all_ms.sort()
	_report["ticks"] = ticks
	_report["tick_mean_ms"] = snappedf(sum / ticks, 0.01)
	_report["tick_median_ms"] = snappedf(all_ms[ticks / 2], 0.01)
	_report["tick_p99_ms"] = snappedf(all_ms[int(ticks * 0.99)], 0.1)
	_report["tick_worst_ms"] = snappedf(all_ms[-1], 0.1)
	_report["steps_over_100ms"] = all_ms.filter(func(x): return x > 100.0).size()
	var parts := {}
	for k in Perf.stats:
		var s: Dictionary = Perf.stats[k]
		parts[k] = {"mean_ms": snappedf(float(s.sum) / ticks, 0.001), "max_ms": snappedf(s.max, 0.1), "calls": s.n}
	_report["parts"] = parts
	worst.sort_custom(func(x, y): return x[0] > y[0])
	var w := []
	for x in worst.slice(0, 15):
		w.append({"ms": snappedf(x[0], 0.1), "tick": x[1], "minute_of_day": x[1] % 1440, "parts": x[2]})
	_report["worst_steps"] = w


## What each system holds: [object path, object]. CitySim's own containers
## (lots, buildings and its caches) are "sim".
func _systems(sim: CitySim) -> Array:
	var out := [["sim", sim]]
	var seen := {sim.get_instance_id(): true}
	var i := 0
	while i < out.size():
		var obj: Object = out[i][1]
		for pr in obj.get_property_list():
			if not (int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v = obj.get(pr.name)
			if v is Object and v != null and v is RefCounted and not seen.has(v.get_instance_id()) and v.get_script() != null:
				seen[v.get_instance_id()] = true
				out.append([str(out[i][0]) + "." + pr.name if i > 0 else pr.name, v])
		i += 1
	return out


func _memory(sim: CitySim) -> void:
	var systems := _systems(sim)
	var rows := []
	for s in systems:
		var obj: Object = s[1]
		for pr in obj.get_property_list():
			if not (int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v = obj.get(pr.name)
			var ty := typeof(v)
			if ty != TYPE_DICTIONARY and ty != TYPE_ARRAY and ty < TYPE_PACKED_BYTE_ARRAY:
				continue
			var c := {"dicts": 0, "arrays": 0, "packed": 0, "packed_bytes": 0, "str_bytes": 0, "items": 0}
			_walk(v, c, 0)
			var copy_b := 0
			if ty == TYPE_DICTIONARY or ty == TYPE_ARRAY:
				var before := OS.get_static_memory_usage()
				var dup = v.duplicate(true)
				copy_b = OS.get_static_memory_usage() - before
				dup = null
			rows.append({"sys": s[0], "prop": pr.name, "copy_kb": snappedf((copy_b + c.packed_bytes + c.str_bytes) / 1024.0, 0.1),
				"dicts": c.dicts, "arrays": c.arrays, "packed": c.packed, "items": c.items, "packed_kb": snappedf(c.packed_bytes / 1024.0, 0.1),
				"str_kb": snappedf(c.str_bytes / 1024.0, 0.1)})
	rows.sort_custom(func(a, b): return a.copy_kb > b.copy_kb)
	_report["mem_by_container"] = rows.slice(0, 80)
	var by_sys := {}
	for r in rows:
		var top: String = str(r.sys).split(".")[0]
		if top == "sim":
			top = "sim." + str(r.prop)
		if not by_sys.has(top):
			by_sys[top] = {"copy_kb": 0.0, "dicts": 0, "arrays": 0, "items": 0}
		by_sys[top].copy_kb += r.copy_kb
		by_sys[top].dicts += r.dicts
		by_sys[top].arrays += r.arrays
		by_sys[top].items += r.items
	_report["mem_by_system_copy"] = by_sys
	# One of each record, copied 2,000 times.
	_report["record_bytes"] = {
		"person": _rec_bytes(sim.people.people.values().slice(0, 2000)),
		"building": _rec_bytes(sim.buildings.values().slice(0, 2000)),
		"lot": _rec_bytes(sim.lots.values().slice(0, 2000)),
		"parked_vehicle": _rec_bytes(sim.traffic.parked.slice(0, 2000)),
		"driving_car": _rec_bytes(sim.traffic.cars.slice(0, 2000)),
		"walker": _rec_bytes(sim.traffic.walkers.slice(0, 2000)),
	}
	if not sim.people.people.is_empty():
		_report["person_example"] = sim.people.people.values()[0]
	if not sim.buildings.is_empty():
		_report["building_example_keys"] = sim.buildings.values()[0].keys()
	if not sim.lots.is_empty():
		_report["lot_example_keys"] = sim.lots.values()[0].keys()
	if not sim.traffic.parked.is_empty():
		_report["parked_example_keys"] = sim.traffic.parked[0].keys()
	# Release, system by system, biggest first by the copy measure.
	var order := by_sys.keys()
	order.sort_custom(func(a, b): return by_sys[a].copy_kb > by_sys[b].copy_kb)
	var rel := {}
	var total_before := OS.get_static_memory_usage()
	for top in order:
		var before := OS.get_static_memory_usage()
		for s in systems:
			var sys_top: String = str(s[0]).split(".")[0]
			var obj: Object = s[1]
			for pr in obj.get_property_list():
				if not (int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
					continue
				var name: String = pr.name
				var key := ("sim." + name) if sys_top == "sim" else sys_top
				if key != top:
					continue
				var v = obj.get(name)
				var ty := typeof(v)
				if ty == TYPE_DICTIONARY:
					obj.set(name, {})
				elif ty == TYPE_ARRAY:
					if v.is_typed():
						v.clear()
					else:
						obj.set(name, [])
				elif ty >= TYPE_PACKED_BYTE_ARRAY:
					v = null
					obj.set(name, type_convert(null, ty))
		rel[top] = snappedf((before - OS.get_static_memory_usage()) / 1024.0, 0.1)
	_report["mem_release_kb"] = rel
	_report["mem_released_total_mb"] = _mb(total_before - OS.get_static_memory_usage())
	_report["mem_left_after_release_mb"] = _mb(OS.get_static_memory_usage())


func _rec_bytes(recs: Array) -> int:
	if recs.is_empty():
		return 0
	var c := {"dicts": 0, "arrays": 0, "packed": 0, "packed_bytes": 0, "str_bytes": 0, "items": 0}
	_walk(recs, c, 0)
	var before := OS.get_static_memory_usage()
	var dup := recs.duplicate(true)
	var b := OS.get_static_memory_usage() - before
	dup.clear()
	return int((b + c.packed_bytes + c.str_bytes) / recs.size())


func _walk(v, c: Dictionary, depth: int) -> void:
	var ty := typeof(v)
	if ty == TYPE_DICTIONARY:
		c.dicts += 1
		c.items += v.size()
		if depth < 12:
			for k in v:
				_walk(k, c, depth + 1)
				_walk(v[k], c, depth + 1)
	elif ty == TYPE_ARRAY:
		c.arrays += 1
		c.items += v.size()
		if depth < 12:
			for x in v:
				_walk(x, c, depth + 1)
	elif ty == TYPE_STRING:
		c.str_bytes += 4 * v.length() + 16
	elif ty >= TYPE_PACKED_BYTE_ARRAY:
		c.packed += 1
		c.items += v.size()
		var esz: int = {TYPE_PACKED_BYTE_ARRAY: 1, TYPE_PACKED_INT32_ARRAY: 4, TYPE_PACKED_INT64_ARRAY: 8,
			TYPE_PACKED_FLOAT32_ARRAY: 4, TYPE_PACKED_FLOAT64_ARRAY: 8, TYPE_PACKED_STRING_ARRAY: 24,
			TYPE_PACKED_VECTOR2_ARRAY: 8, TYPE_PACKED_VECTOR3_ARRAY: 12, TYPE_PACKED_COLOR_ARRAY: 16,
			TYPE_PACKED_VECTOR4_ARRAY: 16}.get(ty, 8)
		c.packed_bytes += esz * v.size()


func _mb(b: int) -> float:
	return snappedf(b / 1048576.0, 0.1)


func _sums() -> Dictionary:
	var r := {}
	for k in Perf.stats:
		r[k] = float(Perf.stats[k].sum)
	return r


func _top(d: Dictionary, n: int, div := 1.0) -> Dictionary:
	var keys := d.keys()
	keys.sort_custom(func(x, y): return d[x] > d[y])
	var out := {}
	for k in keys.slice(0, n):
		out[k] = snappedf(float(d[k]) / div, 0.01)
	return out
