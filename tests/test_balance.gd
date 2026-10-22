extends SceneTree
## Pacing checks from the balance harness: a new city can always get going.
## Run: godot --headless -s tests/test_balance.gd
## (For the full day-by-day report: godot --headless -s tools/balance_run.gd)

const DAYS := 6


func _init() -> void:
	# The user's first move: a big grid and a farm, then power and water.
	var rush := BalancePlay.new("grid_rush").play(DAYS)
	_check(rush.day_of("power") >= 0 and rush.day_of("water") >= 0,
		"after a big starter grid there is still money for power and water (%s)" % str(rush.summary()))
	_check(not rush.summary().broke, "the big starter grid never goes broke (low $%d)" % rush.min_money)
	_check(rush.day_of("pop100") >= 0 and rush.day_of("pop100") <= 8,
		"the big starter grid reaches 100 people in 8 game days (day %d)" % rush.day_of("pop100"))
	# A careful start pays for itself almost at once, like a CS2 opening.
	for diff in Economy.DIFFICULTIES:
		var plan := BalancePlay.new("planner", diff).play(DAYS)
		var s := plan.summary()
		_check(not s.broke, "%s: a careful start never goes broke (low $%d)" % [diff, plan.min_money])
		_check(s.positive_day >= 0 and s.positive_day <= 3,
			"%s: a careful start earns more than it spends by day 3 (day %d)" % [diff, s.positive_day])
		_check(s.pop100_day >= 0 and s.pop100_day <= 5, "%s: 100 people by day 5 (day %d)" % [diff, s.pop100_day])
		_check(s.end_net > 0, "%s: still earning at the end ($%d a month)" % [diff, s.end_net])
	# Nothing built, nothing spent.
	var idle := BalancePlay.new("idle").play(3)
	_check(idle.sim.economy.money == Economy.START_MONEY, "an empty city keeps its money")
	# Difficulty is saved with the city.
	var hard := CitySim.new()
	hard.apply({"type": "set_difficulty", "difficulty": "hard"})
	_check(hard.economy.money == Economy.start_money("hard"), "hard starts with less money")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(hard.to_dict())))
	_check(copy.economy.difficulty == "hard", "difficulty is saved")
	print("balance tests passed" if _failures == 0 else "%d balance checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)
	else:
		print("ok  ", what)
