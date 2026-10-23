extends SceneTree
## How long naming and the monthly family step take in a big town (about
## 1,900 buildings and 1,200 businesses), and how big the save gets.
## Run: godot --headless -s tools/families_bench.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 900_000_000
	sim.apply({"type": "build_grid", "a": [-600, -600], "b": [600, -600], "c": [-600, 600], "block": 120})
	var ids := sim.network.segments.keys()
	for i in ids.size():
		for side in [-1, 1]:
			var z: int = [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL][(i + side + 3) % 3]
			sim.apply({"type": "zone_frontage", "seg": ids[i], "side": side, "zone": z})
	sim.tick()
	var t0 := Time.get_ticks_usec()
	var keys: Array = sim.lots.keys()
	keys.sort()
	for key in keys:
		var z: int = sim.zones.zone_at(sim.lots[key].zone_pt)
		if z != ZoneMap.Zone.NONE:
			sim.buildings[key] = {"zone": z, "seed": hash(key), "built": 0, "cap": 8, "occ": 0}
	print("buildings ", sim.buildings.size())
	t0 = Time.get_ticks_usec()
	sim.families.sync(sim)
	print("first naming of ", sim.families.owned.size(), " businesses: ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
	t0 = Time.get_ticks_usec()
	sim.families.sync(sim)
	print("sync with nothing new: ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
	for f in sim.families.families.values():
		f.cash = 3_000_000
	var worst := 0.0
	for m in 60:
		sim.tick_count += 1440
		t0 = Time.get_ticks_usec()
		sim.families.month(sim)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		for r in sim.permits.listed(Permits.State.OPEN):
			sim.apply({"type": "permit", "id": r.id, "answer": "approve"})
	print("month step, worst of 60: ", worst, " ms; families ", sim.families.families.size())
	var save := JSON.stringify(sim.families.to_dict())
	print("save size ", save.length() / 1024, " KB")
	quit()
