extends SceneTree
## Run: godot --headless -s tests/test_banks.gd

func _init() -> void:
	# Two copies of the same farm town; one gets a Farm Credit office.
	var plain := _farm_town()
	var lent := _farm_town()
	var site := Banks.site_near(lent.network, Vector3(-300, 0, -40))
	_check(site.size() == 2, "a bank finds its spot beside the road")
	_check(Banks.site_problem(lent, "farm_credit", site[0], site[1]) == "", "open ground is fine for a bank")
	var money := lent.economy.money
	_check(lent.apply({"type": "place_bank", "kind": "farm_credit", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "placing a Farm Credit office")
	_check(money - lent.economy.money == int(Banks.spec("farm_credit").cost), "the city pays only for the lot")
	_check(not lent.apply({"type": "place_bank", "kind": "community", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "no bank on top of another")
	var id: int = lent.banks.banks.keys()[0]
	var b: Dictionary = lent.banks.banks[id]
	_check(str(b.leader.name) != "", "it hires a branch manager (%s, %s)" % [b.leader.name, Banks.leader_style(b.leader)])
	_check(lent.banks.covers(site[0]), "the bank covers its first block")
	_check(Inspect.pick(lent, site[0]).get("type", "") == "bank", "clicking it selects the bank")
	_check(not BankInfo.describe(lent, id).rows.is_empty(), "its info panel has rows")
	# A bold manager, so the comparison isn't left to chance.
	b.leader.caution = 0.1
	b.leader.ambition = 0.8
	for i in Farms.DECIDE_EVERY * 60:
		plain.tick()
		lent.tick()
	var f0: int = plain.farms.farms.values()[0].cells.size()
	var f1: int = lent.farms.farms.values()[0].cells.size()
	_check(f1 > f0, "the farm with a lender grows faster (%d fields against %d)" % [f1, f0])
	_check(not b.loans.is_empty() and Banks.loans_total(b) > 0.0, "the farm borrowed ($%d)" % roundi(Banks.loans_total(b)))
	_check(b.made > 0 and b.year.lent + float(b.get("last_year", {}).get("lent", 0.0)) > 0.0, "loans are on the books")
	var who := "farm:%d" % lent.farms.farms.keys()[0]
	_check(lent.banks.coverage(lent, who) >= Banks.dscr_needed(b) or lent.banks.debt(who)
		<= Banks.collateral(lent, who) * Banks.ltv(b) + 1.0, "it borrows against what it earns or what its land is worth")

	# Save and load keep the bank, its manager and its loans.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(lent.to_dict())))
	_check(copy.banks.banks.size() == 1 and copy.banks.banks.values()[0].leader.name == b.leader.name,
		"a saved bank keeps its manager")
	_check(absf(Banks.loans_total(copy.banks.banks.values()[0]) - Banks.loans_total(b)) < 1.0, "and its loans")

	# A bad year: the farm loses money, the stretched loan defaults, and the
	# farm loses the land it bought on credit.
	var fid: int = lent.farms.farms.keys()[0]
	var cells_before: int = lent.farms.farms[fid].cells.size()
	var pledged: int = b.loans[who].cells.size()
	var earlier: int = b.foreclosed
	var foreclosed := false
	for m in 400:
		lent.farms.price = 0.05
		lent.banks.decide(lent)
		if b.foreclosed > earlier:
			foreclosed = true
			break
	_check(foreclosed, "a farm that can't pay is foreclosed on")
	_check(lent.farms.farms[fid].cells.size() <= cells_before - mini(pledged, 1),
		"it loses the fields it pledged (%d of %d left)" % [lent.farms.farms[fid].cells.size(), cells_before])
	_check(not b.loans.has(who), "the loan is written off")

	# Regulators: a bank short of equity stops lending, and if it sinks the
	# FDIC sells it and a careful president comes in.
	b.loans = {"farm:%d" % fid: {"kind": "farm", "balance": 10_000_000.0, "pay": 0.0, "cells": []}}
	b.capital = 400_000.0
	lent.banks.decide(lent)
	_check(Banks.health(b) == "order", "a bank under 6% equity is put under an order")
	_check(lent.banks.appetite(lent, id, "farm") == 0.0, "and makes no new loans")
	var was: String = b.leader.name
	b.capital = 50_000.0
	lent.banks.decide(lent)
	_check(b.status == "sold" and b.leader.caution >= 0.65, "a failed bank is sold, with a careful new president")
	_check(Banks.capital_ratio(b) >= Balance.BANK_WELL_CAPITALIZED * 0.9, "the buyer puts in new equity")
	_check(b.leader.name != was or b.leader.caution >= 0.65, "a new president runs it")
	b.loans.clear()

	# A community bank in a town with homes takes deposits and lends to builders.
	var town := _home_town()
	var spot := Banks.site_near(town.network, Vector3(300, 0, 40))
	_check(town.apply({"type": "place_bank", "kind": "community", "pos": [spot[0].x, spot[0].z],
		"dir": [spot[1].x, spot[1].z]}), "placing a community bank")
	var bid: int = town.banks.banks.keys()[0]
	var cb: Dictionary = town.banks.banks[bid]
	cb.leader.caution = 0.1
	town.banks.decide(town)
	_check(cb.deposits > 0.0, "the town's savings come in ($%d)" % roundi(cb.deposits))
	_check(town.banks.room(town, bid) > 0.0, "so it has money to lend")
	var before := town.buildings.size()
	for i in 4000:
		town.tick()
	var builds := 0
	for w in cb.loans:
		if str(w).begins_with("build:"):
			builds += 1
	_check(builds > 0, "builders borrow to put up homes (%d loans)" % builds)
	_check(town.buildings.size() > before, "and the town grows")
	_check(town.banks.jobs() >= int(Banks.spec("community").staff), "the bank hires tellers")
	town.update_stats()
	_check(town.economy.budget.income[ZoneMap.Zone.COMMERCIAL] > 0, "the bank pays property tax")

	# Its president buys the block next door for its development tree.
	cb.capital = 50_000_000.0
	town.banks.decide(town)
	_check(cb.blocks.size() == 1 and Banks.dev("community", cb.blocks[0].use).has("name"),
		"a sound bank builds out from its tree (%s)" % (cb.blocks[0].use if not cb.blocks.is_empty() else "none"))
	if not cb.blocks.is_empty():
		var p := Banks.block_center(cb, cb.blocks[0].c)
		_check(town.banks.covers(p), "the new block is part of the bank")
		_check(town.apply({"type": "remove_bank_block", "pos": [p.x, p.z]}) and cb.blocks.is_empty(),
			"bulldozing clears one block")
	# Hold off: the leader guide stops it buying more land.
	town.permits.guide(town, {"hub": "bank", "hub_id": bid, "stance": "hold", "grant": 0})
	town.banks.decide(town)
	_check(cb.blocks.is_empty(), "\"hold off\" stops it buying land")

	# The road wins: a road through the bank closes it.
	var front := Banks.block_center(cb, Vector2i.ZERO)
	var right := Vector3(-cb.dir.z, 0.0, cb.dir.x)
	var a := front - right * 80.0
	var e := front + right * 80.0
	town.economy.money = 50_000_000
	town.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [front.x, front.z], "end": [e.x, e.z]})
	_check(town.banks.banks.is_empty(), "a road through the bank closes it")

	print("bank tests done")
	quit(1 if _failed else 0)


## A road, and farmland north of it with one corn farm.
func _farm_town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	return sim


## A county highway and a street of homes.
func _home_town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.build_county_road(Vector2(-2000, 0), Vector2(2000, 0), [0, 1])
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -150], "end": [-300, -300]})
	for z in range(-290, -10, 10):
		sim.apply({"type": "paint_zone", "center": [-275, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [-325, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	return sim


var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
