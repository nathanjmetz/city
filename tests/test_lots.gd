extends SceneTree
## Run: godot --headless -s tests/test_lots.gd
## Natural lots: zoned frontage is surveyed into real-world lots that fill
## the block, with corner lots, curves and flag lots.

var failed := false


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var sim := CitySim.new()
	# One 120 x 160 m block, like a Midwestern town block.
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [240, 0], "c": [240, 160], "block": 120.0})
	print("roads: %d  (%d ms)" % [sim.network.segments.size(), Time.get_ticks_msec() - t0])
	_check(sim.lots.is_empty(), "no lots before zoning (got %d)" % sim.lots.size())
	t0 = Time.get_ticks_msec()
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	print("zoned all: %d lots (%d ms)" % [sim.lots.size(), Time.get_ticks_msec() - t0])
	var area := 0.0
	var widths := {}
	var corners := 0
	var flags := 0
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.pos.x > 0.0 and lot.pos.x < 240.0 and lot.pos.z > 0.0 and lot.pos.z < 160.0:
			area += lot.area
		widths[snappedf(lot.width, 0.5)] = true
		corners += 1 if lot.corner else 0
		flags += 1 if lot.flag else 0
	print("widths: %s corners %d flags %d" % [str(widths.keys()), corners, flags])
	_check(widths.size() > 3, "lot widths vary")
	_check(corners > 0, "corner lots")
	var overlaps := _overlaps(sim)
	_check(overlaps == 0, "lots don't overlap (%d)" % overlaps)
	# The block is filled: little land is left between the lots.
	var block := (120.0 - 2 * 8.4) * (80.0 - 2 * 8.4)
	var filled := area / (block * 4.0)
	_check(filled > 0.9, "blocks are filled with lots, no wasted land (%.0f%%)" % (filled * 100.0))
	# Built lots become parcels: they survive a save and stay put when the
	# zoning around them changes.
	sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	for i in 3000:
		sim.tick()
	_check(sim.buildings.size() > 10, "homes grew (%d)" % sim.buildings.size())
	var built: String = sim.buildings.keys()[0]
	var shape: PackedVector2Array = sim.lots[built].corners
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.lots.has(built) and copy.lots[built].corners == shape, "save keeps a parcel's exact shape")
	_check(copy.buildings.size() == sim.buildings.size(), "save keeps every building")
	for i in 30:
		sim.tick()
		copy.tick()
	var da := copy.to_dict()
	var db := sim.to_dict()
	var diff := []
	for k in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			diff.append(k)
	_check(diff.is_empty(), "copies stay in sync %s" % str(diff))
	# Merge two neighbours, then split them again (business agency).
	var face := LotPlanner.block_face(sim, built)
	_check(face.size() >= 2, "block face lists the street's lots (%d)" % face.size())
	var plant := CitySim.new()
	plant.apply({"type": "build_road", "start": [0, 0], "ctrl": [200, 0], "end": [400, 0]})
	plant.apply({"type": "zone_frontage", "seg": plant.network.segments.keys()[0], "side": 1, "zone": ZoneMap.Zone.INDUSTRIAL})
	var row := LotPlanner.block_face(plant, plant.lots.keys()[0])
	_check(row.size() >= 4, "a row of plant lots (%d)" % row.size())
	_check(LotPlanner.can_merge(plant, row[0], row[1]), "two neighbouring plants can merge")
	_check(not LotPlanner.can_merge(plant, row[0], row[2]), "lots that don't touch can't merge")
	var before: float = plant.lots[row[0]].area + plant.lots[row[1]].area
	_check(LotPlanner.merge_lots(plant, row[0], row[1]) == row[0], "merge keeps the first key")
	_check(not plant.lots.has(row[1]) and absf(plant.lots[row[0]].area - before) < before * 0.05,
		"merged lot covers both (%.0f of %.0f m²)" % [plant.lots[row[0]].area, before])
	var halves := LotPlanner.split_lot(plant, row[0])
	_check(halves.size() == 2 and plant.lots.has(row[0] + "/1"), "a merged lot splits back in two")
	# Homes stay within real lot sizes: three wide lots can't become one estate.
	var big := 0.0
	for k in face:
		big += sim.lots[k].width
	_check(face.size() < 3 or not LotPlanner.can_merge(sim, face[0], face[1]) or big > 46.0, "home lots have a size cap")
	# A new road through a built block re-cuts or drops the parcels it hits.
	var lost := []
	sim.parcels_lost.connect(func(keys): lost.append_array(keys))
	var victim := ""
	for key in sim.buildings:
		var l: Dictionary = sim.lots[key]
		if absf(l.normal.z) > 0.9 and l.pos.x > 20.0 and l.pos.x < 220.0 and l.pos.z > 10.0 and l.pos.z < 150.0 and absf(fmod(l.pos.x, 120.0) - 60.0) < 40.0:
			victim = key
			break
	_check(victim != "", "a built home to run a road through")
	if victim != "":
		var x: float = sim.lots[victim].pos.x
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 80], "end": [x, 160]})
		sim.tick()
		for key in sim.lots:
			var c: PackedVector2Array = sim.lots[key].corners
			_check(not Geometry2D.is_point_in_polygon(Vector2(x, 40), c) and not Geometry2D.is_point_in_polygon(Vector2(x, 120), c),
				"no lot left under the new road (%s)" % key)
		_check(lost.has(victim) and not sim.buildings.has(victim), "the home it ran through is gone and reported for a refund")
	# Curves: lots fan out radially and never overlap.
	var curve := CitySim.new()
	curve.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, -90], "end": [300, 0]})
	for side in [-1, 1]:
		curve.apply({"type": "zone_frontage", "seg": curve.network.segments.keys()[0], "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(curve.lots.size() >= 20, "lots along a curve (%d)" % curve.lots.size())
	_check(_overlaps(curve) == 0, "curve lots don't overlap")
	if failed:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if failed else 0)


func _overlaps(sim: CitySim) -> int:
	var keys := sim.lots.keys()
	var n := 0
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Dictionary = sim.lots[keys[i]]
			var b: Dictionary = sim.lots[keys[j]]
			if (a.pos as Vector3).distance_to(b.pos) > 120.0:
				continue
			for p in Geometry2D.intersect_polygons(a.corners, b.corners):
				if absf(LotPlanner._area(p)) > 4.0:
					n += 1
	return n


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL: " + what)
