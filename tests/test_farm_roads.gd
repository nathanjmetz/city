extends SceneTree
## Farms grow to a real size and then build a road (Brawn, 2026-10-23): a
## farm works one 80-acre block between roads, and when it's full it lays a
## gravel road on the survey line to the next, which becomes a public road.
## A road that would cross the player's things is asked for on the bell.
## Run: godot --headless -s tests/test_farm_roads.gd

var _fails := 0


func _init() -> void:
	_survey()
	_road_to_next_block()
	_asks_before_crossing()
	_county_road_crossing()
	_done()


## The survey lines and blocks in a farm's own frame.
func _survey() -> void:
	_check(Farms.on_line(Vector2i(10, 3)) and Farms.on_line(Vector2i(-11, 3)) and Farms.on_line(Vector2i(31, 0)),
		"road columns every 21 cells")
	_check(Farms.on_line(Vector2i(0, 10)) and Farms.on_line(Vector2i(0, 21)) and not Farms.on_line(Vector2i(0, -1)),
		"road rows behind the farmhouse's block")
	_check(Farms.block_of(Vector2i(-10, 0)) == Vector2i.ZERO and Farms.block_of(Vector2i(9, 9)) == Vector2i.ZERO
		and Farms.block_of(Vector2i(0, -3)) == Vector2i.ZERO, "the farmhouse's block runs out to its road")
	_check(Farms.block_of(Vector2i(11, 0)) == Vector2i(1, 0) and Farms.block_of(Vector2i(0, 11)) == Vector2i(0, 1),
		"the next blocks lie past the lines")
	_check(Farms.forty_of(Vector2i(-10, 0)) != Farms.forty_of(Vector2i(0, 0))
		and Farms.forty_of(Vector2i(-1, 5)) == Farms.forty_of(Vector2i(-10, 0)), "two forties to a block")
	var n := 0
	for i in range(-10, 10):
		for j in 10:
			if Farms.forty_of(Vector2i(i, j)) == Vector2i.ZERO:
				n += 1
	_check(absf(n * Farms.ACRES_PER_CELL - 40.0) < 1.0, "a forty is 40 acres (%.1f)" % (n * Farms.ACRES_PER_CELL))


func _farm(sim: CitySim) -> int:
	sim.apply({"type": "build_road", "start": [-1800, 0], "ctrl": [0, 0], "end": [1800, 0]})
	# The best soil along the road, the way a player would pick it.
	var xs := []
	for x in range(-1200, 1300, 100):
		var soil := 0.0
		for i in range(-400, 400, 80):
			for j in range(0, 400, 80):
				soil += Farms.fertility_at(Vector3(x + i, 0, 180 + j))
		xs.append([soil, x])
	xs.sort_custom(func(a, b): return a[0] > b[0])
	for e in xs:
		var x: float = e[1]
		if sim.apply({"type": "place_farmhouse", "pos": [x, 180], "dir": [0, -1], "crop": "corn"}):
			return sim.farms.farms.keys()[-1]
	return -1


func _fill(sim: CitySim, id: int) -> void:
	var f: Dictionary = sim.farms.farms[id]
	f.barn = true
	sim.farms.price = 1.2
	for _k in 600:
		var c := sim.farms.best_field(id, sim.field_usable)
		if c == Vector2i.MAX:
			break
		f.cells.append(c)


## Every field the farm works is whole: the only cells it skips in it are
## ground it can't work.
func _whole_fields(sim: CitySim, id: int) -> bool:
	var f: Dictionary = sim.farms.farms[id]
	var forties := {}
	for c in f.cells:
		forties[Farms.field_of(c)] = true
	for k in forties:
		for c in Farms.field_cells(f, k):
			if not c in f.cells and sim.farms._free(id, f, c, sim.field_usable):
				print("  hole at ", c, " in field ", k)
				return false
	return true


func _road_to_next_block() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	var id := _farm(sim)
	_check(id != -1, "a farm is placed")
	if id == -1:
		return
	var f: Dictionary = sim.farms.farms[id]
	_check(sim.farms.wants_road(id) == false, "a new farm doesn't want a road")
	_fill(sim, id)
	_check(_whole_fields(sim, id), "it farms whole rectangular fields, not soil-chasing scraps")
	# Its block is full: the next field it would buy lies past a survey line.
	var left := sim.farms.best_field(id, sim.field_usable)
	_check(left == Vector2i.MAX, "a full block has no more fields to buy (%s)" % str(left))
	sim.farms.price = 1.2
	_check(sim.farms.wants_road(id), "a full, paying farm wants a road (%d cells, $%d a year)" % [f.cells.size(), sim.farms.yearly_profit(id)])
	var segs := sim.network.segments.size()
	var money := sim.economy.money
	var built := sim._farm_road(id)
	_check(built, "it builds a road to the next block: %s" % f.why)
	_check(sim.network.segments.size() > segs, "the road is in the city's network")
	_check(sim.economy.money == money, "the farm pays for it, not the town")
	var gravel := false
	for s in sim.network.segments.values():
		if s.type == RoadStyle.Type.GRAVEL:
			gravel = true
	_check(gravel, "it starts as a gravel road")
	_check(f.blocks.size() == 2, "a second block is open: %s" % str(f.blocks))
	sim._refresh()
	var next := Vector2i.MAX
	for _k in 60:
		next = sim.farms.best_field(id, sim.field_usable)
		if next == Vector2i.MAX:
			break
		f.cells.append(next)
	var beyond := 0
	for c in f.cells:
		if Farms.block_of(c) != Vector2i.ZERO:
			beyond += 1
	_check(beyond > 0, "it farms past its road (%d fields, blocks %s, %d cells)" % [beyond, str(f.blocks), f.cells.size()])
	# Saved and loaded, it remembers its blocks.
	var copy := Farms.new()
	copy.from_dict(sim.farms.to_dict())
	_check(copy.farms[id].blocks.size() == 2, "blocks survive a save")
	# The player can remove the farm's road like any other.
	var gseg := -1
	for sid in sim.network.segments:
		if sim.network.segments[sid].type == RoadStyle.Type.GRAVEL:
			gseg = sid
	_check(sim.apply({"type": "remove_road", "seg": gseg}), "the player can remove it")


func _asks_before_crossing() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	var id := _farm(sim)
	if id == -1:
		return
	var f: Dictionary = sim.farms.farms[id]
	# A road the player drew across the farm's back line.
	var a := Farms.local_point(f, 3.0, 8.0)
	var b := Farms.local_point(f, 3.0, 13.0)
	sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [(a.x + b.x) * 0.5, (a.z + b.z) * 0.5], "end": [b.x, b.z]})
	var start := HubRoads.reach(sim, Farms.local_point(f, -11.0, 10.0), f.dir, 1000.0)
	_check(start != Vector3.INF, "the survey line reaches the farm's road")
	var plan := HubRoads.check(sim, [start, Farms.local_point(f, -11.0, 10.0), Farms.local_point(f, 10.0, 10.0)], "farm:%d" % id)
	_check(plan.ok and plan.permit, "a road across the player's road needs a permit")
	var segs := sim.network.segments.size()
	_check(plan.ok and not HubRoads.check(sim, [start, Farms.local_point(f, -11.0, 10.0)], "farm:%d" % id).permit,
		"joining a road needs none")
	# Filed and approved, the farm builds it.
	f.barn = true
	f.pending = {"req": sim.permits.file(sim, {"hub": "farm", "hub_id": id, "title": "Road", "route": HubRoads.flat(plan.route),
		"width": 12.0, "per_m": 100}), "block": [0, 1]}
	_check(int(f.pending.req) != -1, "the request is on the bell")
	sim.apply({"type": "permit", "id": int(f.pending.req), "answer": "approve"})
	sim.farms.price = 1.2
	_check(sim._farm_road(id) and sim.network.segments.size() > segs and Vector2i(0, 1) in f.blocks,
		"approved, it builds the road and opens the block behind")


## A county road the town hasn't built runs through farm country: fields
## stop at its right of way, never across it (Brawn, 2026-10-24).
func _county_road_crossing() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 20_000_000
	var id := _farm(sim)
	if id == -1:
		_check(false, "a farm is placed")
		return
	var f: Dictionary = sim.farms.farms[id]
	var c := Vector2i(3, 5)
	var m := Farms.cell_center(f, c)
	# Shift the map so a county road's mile runs right through cell c.
	var sec := CountyGrid.SECTION
	var key := ""
	for k in range(-20, 20):
		for seg in range(-20, 20):
			if key == "" and CountyGrid.has_mile(k, seg):
				sim.terrain_offset = Vector2(k * sec - m.x, (seg + 0.5) * sec - m.z)
				key = "ns:%d:%d" % [k, seg]
	for x in range(0, 7):
		for y in range(2, 9):
			if not Vector2i(x, y) in f.cells:
				f.cells.append(Vector2i(x, y))
	sim._usable_cache.clear()
	_check(not sim.field_usable(m, Farms.cell_corners(f, c)), "a farmer can't plant across a county road")
	_check(sim.field_usable(m + Vector3(300, 0, 0), PackedVector2Array()) or not sim._on_painted_road(m + Vector3(300, 0, 0), 40.0),
		"but can a field's width away from it")
	sim._road_wins()
	_check(not c in f.cells or (sim.farms.trim.has(id) and sim.farms.trim[id].has(c)),
		"a field already across it is cut back to the road's edge")
	_check(not sim.farms.trim.get(id, {}).has(Vector2i(0, 5)) or absf(Farms.cell_center(f, Vector2i(0, 5)).x - m.x) < 70.0,
		"fields away from the road are left whole")
	sim.county_removed[key] = true
	_check(not sim._on_painted_road(m, 30.0), "a bulldozed mile frees the ground again")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
