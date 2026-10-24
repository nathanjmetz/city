extends SceneTree
## Run: godot --headless -s tests/test_market.gd
## The market a developer sees (Market): a town's own people plus its
## neighbors' within commuting reach. What gets built waits on it: a remote
## hamlet gets no apartments, a new town beside a big one gets them early,
## and the developers' asks and home builders follow the same rule.

var _failed := false


func _init() -> void:
	# Reach: full close by, fading to nothing at the edge of a commute.
	_check(Market.weight(5000.0) == 1.0, "a town 5 km away counts in full")
	_check(Market.weight(Balance.MARKET_REACH + 1.0) == 0.0, "past a 45-minute drive, nothing")
	var mid := Market.weight((Balance.MARKET_FULL + Balance.MARKET_REACH) * 0.5)
	_check(is_equal_approx(mid, 0.5), "halfway out, half (%.2f)" % mid)

	# Each type and stage waits for a market of its size, rare at first.
	_check(not Market.supports(677, "apartments"), "677 people support no apartments")
	_check(Market.supports(677, "house") and Market.supports(677, "mixed_use"), "houses and a Main Street need no market")
	_check(Market.ramp(12_000, "apartments") > 0.0 and Market.ramp(12_000, "apartments") < 0.5,
		"a county-seat market: a few walk-ups (%.2f)" % Market.ramp(12_000, "apartments"))
	_check(Market.ramp(30_000, "apartments") == 1.0, "a small city's market: walk-ups as common as anywhere")
	_check(not Market.supports(30_000, "apartments", 2) and not Market.supports(30_000, "row_home"),
		"a small city's market: no mid-rise or row homes yet")
	var tiers_rise := true
	for type in Balance.MARKET_MIN:
		var mins: Array = Balance.MARKET_MIN[type]
		for i in range(1, mins.size()):
			tiers_rise = tiers_rise and int(mins[i]) >= int(mins[i - 1])
		tiers_rise = tiers_rise and mins.size() == BuildingTypes.TYPES[type].stages.size()
	_check(tiers_rise, "every type has a market for each stage, rising stage by stage")

	# In a region: a hamlet next to a thriving town sees its people.
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	var ann: CitySim = r.cities.c1.sim
	r.ledger.set_population("c2", 40_000)
	ann.market.sync(r, "c1", ann)
	var d: float = r.cities.c1.origin.distance_to(r.cities.c2.origin)
	_check(ann.market.regional == roundi(40_000 * Market.weight(d)) and ann.market.towns == 1,
		"Bob's 40,000 people count toward Ann's market (%d at %.1f km)" % [ann.market.regional, d / 1000.0])
	r.ledger.set_population("c2", 300)
	ann.market.sync(r, "c1", ann)
	_check(ann.market.regional == roundi(300 * Market.weight(d)), "a neighbor hamlet adds little (%d)" % ann.market.regional)

	# Saved with the town, so a reloaded copy decides the same way.
	ann.market.regional = 25_000
	ann.market.towns = 2
	var copy := CitySim.new()
	copy.from_dict(ann.to_dict())
	_check(copy.market.regional == 25_000 and copy.market.towns == 2, "the market is saved")

	# Builders follow it: a small new town beside a city draws a regional
	# developer, the same town alone only a local builder.
	var sim := CitySim.new()
	sim.stats.population = 400
	sim.market.regional = 0
	_check(str(Subdivisions._tier(sim).get("who", "")) == "a local builder", "a lone hamlet gets a local builder")
	sim.market.regional = 30_000
	_check(str(Subdivisions._tier(sim).get("who", "")) == "a master-planned community builder",
		"beside a city, a bigger builder comes early (%s)" % str(Subdivisions._tier(sim).get("who", "")))

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + what)
	else:
		print("PASS " + what)
