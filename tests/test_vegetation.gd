extends SceneTree
## Run: godot --headless -s tests/test_vegetation.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	var year := Vegetation.TICKS_PER_YEAR
	# A new map is already wooded and brushy, with nothing built.
	var wild := sim.vegetation.plants_in(Rect2(-1000, -1000, 2000, 2000), 0)
	var trees := wild.filter(func(p): return p.kind == Vegetation.Kind.TREE).size()
	var shrubs := wild.size() - trees
	_check(trees > 2000 and shrubs > 2000, "a new map has trees and brush (%d trees, %d shrubs in 4 km²)" % [trees, shrubs])
	_check(JSON.stringify(_flat(wild)) == JSON.stringify(_flat(CitySim.new().vegetation.plants_in(Rect2(-1000, -1000, 2000, 2000), 0))),
		"every player sees the same wild plants")

	# Find a woodlot and run a street through it: the road wins.
	var wood := _woodlot()
	sim.apply({"type": "build_road", "start": [wood.x - 150, wood.z], "ctrl": [wood.x, wood.z], "end": [wood.x + 150, wood.z]})
	sim.tick()
	var strip := Rect2(wood.x - 100, wood.z - 6, 200, 12)
	_check(sim.vegetation.plants_in(strip, sim.tick_count).is_empty(), "no trees or brush on the new street")
	var beside := Rect2(wood.x - 100, wood.z + 50, 200, 100)
	_check(_count(sim, beside, Vegetation.Kind.TREE) > 20, "the woods beside the street stay")

	# A home on a lot clears it.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [wood.x + x, wood.z - 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	var key: String = sim.buildings.keys()[0]
	var lot: Dictionary = sim.lots[key]
	var area := _rect(lot.corners)
	_check(sim.vegetation.plants_in(area, sim.tick_count).is_empty(), "nothing wild grows on a built lot")

	# Take the home away: bare first, brush in a year or two, trees in ten, woods in twenty.
	sim.apply({"type": "paint_zone", "center": [wood.x, wood.z - 25], "radius": 200, "zone": ZoneMap.Zone.NONE})
	_check(sim.buildings.is_empty(), "dezoning removed the homes")
	sim.tick()
	var cleared_at := sim.tick_count
	_check(sim.vegetation.cleared.has(Vegetation.cell_of(lot.pos)), "the empty lot is marked as cleared")
	var inner := area.grow(-4.0)
	_check(sim.vegetation.plants_in(inner, cleared_at + year / 2).is_empty(), "half a year on, still bare")
	var at2 := sim.vegetation.plants_in(inner, cleared_at + year * 2)
	_check(at2.size() > 0 and at2.all(func(p): return p.kind == Vegetation.Kind.SHRUB), "two years on, brush (%d shrubs)" % at2.size())
	var at10 := sim.vegetation.plants_in(inner, cleared_at + year * 10)
	var young := at10.filter(func(p): return p.kind == Vegetation.Kind.TREE)
	_check(young.size() > 0 and young.all(func(p): return p.size < 0.75), "ten years on, young trees (%d)" % young.size())
	var at25 := sim.vegetation.plants_in(inner, cleared_at + year * 25)
	var grown := at25.filter(func(p): return p.kind == Vegetation.Kind.TREE)
	_check(grown.size() >= young.size() and grown.all(func(p): return p.size >= 0.8), "twenty-five years on, full-grown woods (%d)" % grown.size())

	# Saved and loaded, the regrowth carries on the same.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.tick()
	_check(copy.vegetation.cleared.size() == sim.vegetation.cleared.size(), "save keeps the cleared land")
	_check(JSON.stringify(_flat(copy.vegetation.plants_in(inner, cleared_at + year * 3))) \
		== JSON.stringify(_flat(sim.vegetation.plants_in(inner, cleared_at + year * 3))), "loaded city regrows the same")
	sim.tick()
	_check(JSON.stringify(copy.to_dict().vegetation) == JSON.stringify(sim.to_dict().vegetation), "copies stay in sync")

	# Removing the street lets it grow over too; a new city starts wild.
	for id in sim.network.segments.keys():
		sim.apply({"type": "remove_road", "seg": id})
	sim.tick()
	_check(sim.vegetation.plants_in(strip, sim.tick_count + year * 25).size() > 10, "an old road grows over")
	sim.apply({"type": "clear"})
	sim.tick()
	_check(sim.vegetation.cleared.is_empty(), "a new map is all wild again")

	# Cheap enough to stream around the camera on the web.
	var t := Time.get_ticks_usec()
	sim.vegetation.plants_in(Rect2(wood.x - 128, wood.z - 128, 256, 256), 0)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	print("one 256 m chunk of woods: %.1f ms" % ms)
	_check(ms < 60.0, "a chunk lays out quickly (%.1f ms)" % ms)

	# Farm country: nothing wild inside a crop field, only fencerows on its edges.
	Vegetation.cover_source = func(_p: Vector3) -> Array: return [0.1, 0.1, 1.0]
	var farm := CitySim.new().vegetation.plants_in(Rect2(0, 0, 1000, 1000), 0)
	var off_line := farm.filter(_off_fence)
	_check(farm.size() > 200 and off_line.is_empty(),
		"crop fields are clear; trees and brush stand in fencerows (%d plants, %d off the lines)" % [farm.size(), off_line.size()])
	# Open grass: brush gathers in thickets rather than an even scatter.
	Vegetation.cover_source = func(_p: Vector3) -> Array: return [0.05, 0.15, 0.0]
	var grass := CitySim.new().vegetation.plants_in(Rect2(5000, 5000, 1000, 1000), 0)
	var cells := {}
	for p in grass.filter(_off_fence):
		var c := Vector2i(floori(p.pos.x / 50.0), floori(p.pos.z / 50.0))
		cells[c] = cells.get(c, 0) + 1
	_check(cells.size() < 300, "open-ground brush is clumped (%d plants in %d of 400 50 m squares)" % [grass.size(), cells.size()])
	Vegetation.cover_source = Callable()

	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


func _off_fence(p: Dictionary) -> bool:
	var dx := absf(p.pos.x - roundf(p.pos.x / Vegetation.FENCE_GRID) * Vegetation.FENCE_GRID)
	var dz := absf(p.pos.z - roundf(p.pos.z / Vegetation.FENCE_GRID) * Vegetation.FENCE_GRID)
	return minf(dx, dz) > 2.0


func _woodlot() -> Vector3:
	var best := Vector3.ZERO
	var best_v := -1.0
	for x in range(-2000, 2001, 100):
		for z in range(-2000, 2001, 100):
			var v := Resources.at(Resources.Kind.FOREST, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	return best


func _count(sim: CitySim, r: Rect2, kind: int) -> int:
	return sim.vegetation.plants_in(r, sim.tick_count).filter(func(p): return p.kind == kind).size()


func _rect(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	return r


func _flat(plants: Array) -> Array:
	return plants.map(func(p): return [p.pos.x, p.pos.z, p.kind, p.species, snappedf(p.size, 0.001)])


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
