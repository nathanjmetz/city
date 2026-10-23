extends SceneTree
## Run: godot --headless -s tests/test_street_age.gd
## Streets wear out (StreetAge): resurfaced about STREET_LIFE_YEARS after
## they're built, on the town's bill; a street split by a new junction keeps
## its age; gravel is never resurfaced; a save keeps the ages.

var _failed := false
const YEAR := 12 * 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.tick_count = 3 * YEAR  # a town a few years along
	sim.street_age.paved[Vector2i(999, 999)] = 0  # not a fresh town
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [200, 0], "end": [400, 0]})
	sim.apply({"type": "build_road", "start": [0, 300], "ctrl": [200, 300], "end": [400, 300], "road": RoadStyle.Type.GRAVEL})
	_check(sim.street_age.month(sim) == 0, "nothing is due on new streets")
	var f: Array = sim.street_age.forecast
	var later := 0
	for y in f.size():
		if y != Balance.STREET_LIFE_YEARS - 1 and y != Balance.STREET_LIFE_YEARS:
			later += int(f[y])
	var expect := StreetAge.repave_cost(400.0 * RoadStyle.TYPES[RoadStyle.Type.STREET].lanes, RoadStyle.Type.STREET)
	var at := int(f[Balance.STREET_LIFE_YEARS - 1]) + int(f[Balance.STREET_LIFE_YEARS])
	print("  forecast at year %d: $%s (about $%s expected)" % [Balance.STREET_LIFE_YEARS, at, expect])
	_check(absi(at - expect) < expect * 0.1 and later == 0, "the new street comes due in about %d years" % Balance.STREET_LIFE_YEARS)

	# Ten years on, a crossing street splits the old one.
	sim.tick_count += 10 * YEAR
	sim.apply({"type": "build_road", "start": [200, -150], "ctrl": [200, 0], "end": [200, 150]})
	_check(sim.street_age.month(sim) == 0, "still nothing due")
	var near := 0
	for y in range(Balance.STREET_LIFE_YEARS - 11, Balance.STREET_LIFE_YEARS - 9):
		near += int(sim.street_age.forecast[y])
	_check(near >= expect * 0.9, "the split street keeps its age: due in about 15 years ($%s)" % near)

	# Fifteen more years: the first street is resurfaced, on the town.
	sim.tick_count += 15 * YEAR + YEAR / 12
	var paid := sim.street_age.month(sim)
	print("  resurfaced after %d years: $%s" % [Balance.STREET_LIFE_YEARS, paid])
	_check(paid >= expect * 0.9 and paid <= expect * 1.3, "the worn-out street is resurfaced")
	_check(sim.street_age.paid_this_year() == paid, "the Economy page sees what was paid")
	_check(sim.street_age.month(sim) == 0, "and then it's good for another %d years" % Balance.STREET_LIFE_YEARS)

	# Through the sim: the town pays it.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy.street_age.to_dict()) == JSON.stringify(sim.street_age.to_dict()), "a save keeps the ages")
	copy.tick_count += 25 * YEAR
	var money: int = copy.economy.money
	var hour := copy.tick_count % (24 * CitySim.TICKS_PER_HOUR)
	copy.tick_count += (20 * CitySim.TICKS_PER_HOUR + 40 - hour + 24 * CitySim.TICKS_PER_HOUR) % (24 * CitySim.TICKS_PER_HOUR) - 1
	copy.tick()
	print("  the town paid $%s" % (money - copy.economy.money))
	_check(money - copy.economy.money >= expect, "the town pays for resurfacing")

	# A fresh town's county roads come due over the years, not all at once.
	var fresh := CitySim.new()
	fresh.build_county_road(Vector2(-4000, 0), Vector2(4000, 0), [0, 1])
	fresh.apply({"type": "build_road", "start": [0, 50], "ctrl": [0, 150], "end": [0, 250]})
	fresh.street_age.month(fresh)
	var mine := 0
	for y in Balance.STREET_FORECAST_YEARS:
		if y < Balance.STREET_LIFE_YEARS - 1:
			continue
		mine += int(fresh.street_age.forecast[y])
	_check(mine > 0, "the player's own first street is new")
	var years := 0
	for v in fresh.street_age.forecast:
		if int(v) > 0:
			years += 1
	_check(years >= 6, "the county roads a town starts on come due over many years (%d)" % years)

	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true
