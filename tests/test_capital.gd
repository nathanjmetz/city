extends SceneTree
## Run: godot --headless -s tests/test_capital.gd
## A hub's own money (Capital): startup cash, kept profit, land prices that
## rise near town, farms that grow over years by renting or buying fields,
## and a family that asks to sell out when the town has grown around it.


func _init() -> void:
	_money()
	_land_price()
	_farm_pace()
	_priced_out()
	_sell_out()
	_save()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _money() -> void:
	var hub := {"leader": {"ambition": 0.5}}
	Capital.start(hub, "farm")
	_check(float(hub.cash) == float(Balance.CAPITAL_START.farm) and float(hub.debt) == 0.0, "a new farm brings startup cash")
	Capital.step(hub, "farm", 24_000.0, 0.0)
	Capital.step(hub, "farm", 24_000.0, 12.0)
	var kept := float(hub.cash) - float(Balance.CAPITAL_START.farm)
	_check(absf(kept - 24_000.0 * Balance.CAPITAL_RETAIN.farm) < 1.0,
		"it keeps part of a year's profit, the family lives off the rest ($%d)" % kept)
	var bold := {"leader": {"ambition": 1.0}}
	Capital.start(bold, "farm")
	Capital.step(bold, "farm", 24_000.0, 0.0)
	Capital.step(bold, "farm", 24_000.0, 12.0)
	_check(float(bold.cash) > float(hub.cash), "an ambitious owner ploughs more back in")
	var price := 200_000.0
	_check(not Capital.can_buy({"cash": 10_000.0, "debt": 0.0}, price, 40_000.0), "no land without the down payment")
	var buyer := {"cash": 80_000.0, "debt": 0.0}
	_check(Capital.can_buy(buyer, price, 40_000.0), "a down payment and steady income buy land")
	Capital.buy(buyer, price, 40_000.0)
	_check(float(buyer.debt) > 0.0 and float(buyer.cash) < 80_000.0, "it pays down and owes the rest")
	_check(Capital.cash_needed({"cash": 0.0, "debt": 0.0}, price, 5_000.0) > Capital.down(price),
		"a thin income has to put more down")
	var owes := {"cash": 0.0, "debt": 100_000.0, "cap_day": 0.0}
	Capital.step(owes, "farm", 0.0, 12.0)
	_check(float(owes.cash) < 0.0 and float(owes.debt) < 100_000.0, "a year's payments come out of cash and pay the loan down")


func _land_price() -> void:
	var sim := CitySim.new()
	var far := Vector3(0, 0, 0)
	_check(Capital.land_price(sim, far) == Balance.CAPITAL_LAND_PER_ACRE, "open country sells at farm value")
	_town(sim, Vector3(0, 0, 0), 400)
	sim.tick_count += 1
	var near := Capital.land_price(sim, Vector3(300, 0, 0))
	var mile := Capital.land_price(sim, Vector3(1200, 0, 0))
	var out := Capital.land_price(sim, Vector3(5000, 0, 0))
	_check(near > mile and mile > out and out == Balance.CAPITAL_LAND_PER_ACRE,
		"land sells for more the nearer town ($%d, $%d, $%d an acre)" % [near, mile, out])
	_check(near <= Balance.CAPITAL_LAND_PER_ACRE * (1.0 + Balance.CAPITAL_URBAN_MAX) + 1.0, "up to a set multiple of farm value")
	_check(Capital.sell_out(sim, Vector3(200, 0, 0)) and not Capital.sell_out(sim, Vector3(5000, 0, 0)),
		"only land the town has grown around tempts an owner to sell")


func _farm_pace() -> void:
	var sim := _farm_sim()
	if sim == null:
		return
	var f: Dictionary = sim.farms.farms.values()[0]
	_check(f.own.size() == 4 and float(f.cash) == float(Balance.CAPITAL_START.farm), "a farm starts owning its first 80 acres, with savings")
	var at := {}
	for i in 48 * 30:
		sim.farms.day = i * 0.25
		sim.farms.price = Farms.price_on(sim.farms.day)
		sim.farms.year = int(sim.farms.day / 12.0) + 1
		if sim.farms.decide(sim.field_usable):
			sim._refresh()
		if i % 48 == 47:
			at[i / 48 + 1] = f.cells.size()
	var block := Farms.BLOCK.x * Farms.BLOCK.y
	_check(at[1] < block, "it takes years to plant even its own land (%d cells after a year)" % at[1])
	_check(at[5] <= block * 1.5, "after five years it has grown little past its start (%d cells)" % at[5])
	_check(at[30] > at[10] and at[10] > at[5], "and keeps growing over decades (%d, %d, %d cells)" % [at[5], at[10], at[30]])
	_check(not f.rent.is_empty() or f.own.size() > 4, "it grows by renting or buying fields")
	var grew := 0
	for y in range(6, 30):
		grew = maxi(grew, at[y + 1] - at[y])
	_check(grew <= 2 * 5 * Farms.BLOCK.y * 2, "never more than a couple of fields a year (%d cells)" % grew)


func _priced_out() -> void:
	var sim := _farm_sim()
	if sim == null:
		return
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	f.cash = 60_000.0
	sim.farms.land_price_of = func(_p): return Balance.CAPITAL_LAND_PER_ACRE * 2.5
	var k := Vector2i(4, 0)
	_check(not sim.farms._buy(f, k, 20_000.0), "next to town, a farm can't rent or buy more land")
	_check(str(f.why).contains("won't rent"), "and says why (%s)" % f.why)
	sim.farms.land_price_of = func(_p): return Balance.CAPITAL_LAND_PER_ACRE
	_check(sim.farms._buy(f, k, 20_000.0) and k in f.rent, "out in the country it rents the field (%s)" % f.why)
	_check(float(f.cash) < 60_000.0, "and puts its savings into equipment and inputs")


func _sell_out() -> void:
	var sim := _farm_sim()
	if sim == null:
		return
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	f.barn = true
	f.cells.append(Vector2i(1, 1))
	_town(sim, f.pos + Vector3(0, 0, 300), 400)
	sim.tick_count += 1
	sim.farms.year = 3
	sim._farm_sell_outs()
	var sale: Dictionary = f.get("sale", {})
	_check(not sale.is_empty(), "with the town grown around it, the family asks to sell the farm")
	if sale.is_empty():
		return
	var req: Dictionary = sim.permits.requests[int(sale.req)]
	_check(str(req.get("ask", "")) == "sell_farm" and str(req.why).contains("an acre"), "the bell says what developers offer (%s)" % req.why)
	sim.apply({"type": "permit", "id": int(sale.req), "answer": "deny"})
	sim._farm_sell_outs()
	_check(sim.farms.farms.has(id) and f.get("sale", {}).is_empty() and int(f.sale_year) > sim.farms.year,
		"told no, the family farms on and waits years to ask again")
	sim.farms.year = int(f.sale_year) + 1
	sim.tick_count += Permits.DENY_WAIT + 1
	_town(sim, f.pos + Vector3(0, 0, 300), 400)
	sim._farm_sell_outs()
	sale = f.get("sale", {})
	_check(not sale.is_empty(), "years later it asks again")
	if sale.is_empty():
		return
	sim.apply({"type": "permit", "id": int(sale.req), "answer": "approve"})
	sim._farm_sell_outs()
	_check(not sim.farms.farms.has(id), "told yes, the farm closes and its land opens up")


func _save() -> void:
	var sim := _farm_sim()
	if sim == null:
		return
	var f: Dictionary = sim.farms.farms.values()[0]
	f.cash = 12_345.0
	f.debt = 67_890.0
	f.rent = [Vector2i(4, 0)]
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var g: Dictionary = copy.farms.farms.values()[0]
	_check(is_equal_approx(float(g.cash), 12_345.0) and is_equal_approx(float(g.debt), 67_890.0)
		and g.rent == [Vector2i(4, 0)] and g.own.size() == 4, "a save keeps the farm's money and what it rents")


## Good soil on a county road, the way a player picks it, with one farm.
func _farm_sim() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 20_000_000
	var at := Vector3(0, 0, 180)
	var rich := -1.0
	for x in range(-1200, 1300, 100):
		var soil := 0.0
		for i in range(-400, 400, 80):
			for j in range(0, 400, 80):
				soil += Farms.fertility_at(Vector3(x + i, 0, 180 + j))
		if soil > rich:
			rich = soil
			at.x = x
	sim.apply({"type": "build_road", "start": [at.x - 1500, 0], "ctrl": [at.x, 0], "end": [at.x + 1500, 0]})
	var ok := sim.apply({"type": "place_farmhouse", "pos": [at.x, at.z], "dir": [0, -1], "crop": "corn"})
	_check(ok, "a farm is placed")
	return sim if ok else null


## A town's worth of built lots around pos (n of them), for land prices.
func _town(sim: CitySim, pos: Vector3, n: int) -> void:
	for i in n:
		var key := "town%d" % i
		var p := pos + Vector3((i % 20 - 10) * 25.0, 0.0, (i / 20 - 10) * 25.0)
		sim.lots[key] = {"pos": p, "zone_pt": p, "corners": PackedVector2Array()}
		sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL, "occ": 0, "cap": 4}


var _failed := false


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		_failed = true
