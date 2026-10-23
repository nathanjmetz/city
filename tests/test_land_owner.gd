extends SceneTree
## Land has one owner (Brawn, 2026-10-23): a farm never plants on an oil
## company's pads, the working ground around them or its leases, and a
## company never drills on a farm's fields. Both pass the same gate
## (Capital.land_free over CitySim.land_owner).
## Run: godot --headless -s tests/test_land_owner.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			var v := Resources.at(Industry.KINDS["oil"].resource, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z], "end": [best.x + 1800, best.z]})
	var placed := sim.apply({"type": "place_industry", "kind": "oil", "pos": [best.x, best.z + 30], "dir": [0, -1]})
	_check(placed, "an oil company is placed")
	if not placed:
		_done()
		return
	var sid: int = sim.industry.sites.keys()[-1]
	var s: Dictionary = sim.industry.sites[sid]
	s.pads.append_array([Vector2i(2, 2), Vector2i(-2, 3)])
	s.leases = [Vector2i(5, 4)]
	var pad := Industry.pad_center(s, Vector2i(2, 2))
	var edge: Vector3 = pad + (pad - s.pos).normalized() * (Industry.PAD * 0.5 + Balance.INDUSTRY_CLAIM_BUFFER * 0.5)
	_check(sim.land_owner(pad) == "site:%d" % sid, "a pad is the company's land")
	_check(sim.land_owner(Industry.pad_center(s, Vector2i(5, 4))) == "site:%d" % sid, "so is its lease")
	_check(not Capital.land_free(sim, [pad], "farm:1"), "a farm can't take a pad")
	_check(Capital.land_free(sim, [pad], "site:%d" % sid), "the company can use its own land")
	# A farm next door: none of its fields lands on the company's ground.
	var fid := -1
	for dx in [-200, 200, -400, 400, 0, 600, -600]:
		if sim.apply({"type": "place_farmhouse", "pos": [best.x + dx, best.z + 180], "dir": [0, -1], "crop": "corn"}):
			fid = sim.farms.farms.keys()[-1]
			break
	_check(fid != -1, "a farm is placed next to the oil field")
	if fid == -1:
		_done()
		return
	var f: Dictionary = sim.farms.farms[fid]
	f.barn = true
	sim.farms.price = 1.2
	for _k in 150:
		var c := sim.farms.best_field(fid, sim.field_usable)
		if c == Vector2i.MAX:
			break
		f.cells.append(c)
	var over := 0
	var refused := 0
	for x in range(-20, 21):
		for y in range(0, 20):
			var c := Vector2i(x, y)
			var mid := Farms.cell_center(f, c)
			var on_oil := sim.land_owner(mid).begins_with("site:")
			if on_oil and c in f.cells:
				over += 1
			if on_oil and not c in f.cells:
				refused += int(not sim.farms._free(fid, f, c, sim.field_usable))
	_check(over == 0, "no field on the company's land (%d over)" % over)
	_check(refused > 0, "the farm is turned away at the company's line (%d cells)" % refused)
	_check(sim.land_owner(edge) == "site:%d" % sid, "the ground just around a pad is the company's too")
	# The other way: the company can't drill a farm's field.
	if not f.cells.is_empty():
		var field := Farms.cell_center(f, f.cells[0])
		_check(not Capital.land_free(sim, [field], "site:%d" % sid), "a company can't drill a farm's field")
	_done()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
