extends SceneTree
## Money keeps to the dollar across a save (review, 2026-10-26): a bank's
## and a farm's books in a loaded copy of the town match the original's
## exactly as both carry on, so copies in a shared region never drift.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	var site := Banks.site_near(sim.network, Vector3(-300, 0, -40))
	sim.apply({"type": "place_bank", "kind": "farm_credit", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	return sim


func _init() -> void:
	var a := _town()
	for i in Farms.DECIDE_EVERY * 120:
		a.tick()
	var b := CitySim.new()
	b.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	b.simulate_traffic = false
	for i in 3 * 24 * CitySim.TICKS_PER_HOUR:
		a.tick()
		b.tick()
	_check(JSON.stringify(a.banks.to_dict()) == JSON.stringify(b.banks.to_dict()), "the bank's books match to the dollar after a save")
	_check(JSON.stringify(a.farms.to_dict()) == JSON.stringify(b.farms.to_dict()), "and so do the farm's")
	var bank: Dictionary = a.banks.banks.values()[0]
	_check(is_equal_approx(fposmod(float(bank.capital), 1.0), 0.0), "kept in whole dollars (%s)" % bank.capital)
	print("money exact: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
