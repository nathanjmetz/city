extends SceneTree
## Run: godot --headless -s tests/test_stats.gd
## The top bar's charts: the town's numbers kept over time (StatHistory),
## saved with the town, and the way back to a town centre (TownJump).

var _failed := false
const HOUR := CitySim.TICKS_PER_HOUR
const DAY := 24 * HOUR


func _init() -> void:
	var sim := CitySim.new()
	sim.city_seed = 5
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	for x in range(-150, 151, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in DAY + 5 * HOUR:
		sim.tick()

	# --- A sample every game hour, and one a game month.
	var h := sim.history
	_check(h.hourly.size() == 29, "a sample every game hour (%d)" % h.hourly.size())
	_check(h.monthly.size() == 2, "and one a game month (%d)" % h.monthly.size())
	var month := h.rows(sim, "month")
	_check(month.size() in [24, 25], "the month span is the last 24 hours and now (%d)" % month.size())
	_check(int(month[-1][0]) == sim.tick_count, "ending with the town as it is now")
	var c := StatHistory.col("pop")
	_check(int(month[-1][c]) == int(sim.stats.population), "with today's population (%d)" % int(month[-1][c]))
	_check(int(month[-1][StatHistory.col("money")]) == sim.economy.money, "and money")
	_check(sim.stats.population > 0 and float(h.hourly[0][c]) <= float(h.hourly[-1][c]), "the town grew over the samples")
	_check(h.value_ago(sim, "pop", DAY) != null, "a value from a game month ago")
	_check(h.rows(sim, "all").size() == 3, "the whole-life span is monthly (%d)" % h.rows(sim, "all").size())

	# --- Only the last game year of hours is kept.
	for i in StatHistory.HOURS_KEPT + 10:
		sim.tick_count += HOUR
		h.hour(sim)
	_check(h.hourly.size() == StatHistory.HOURS_KEPT, "hours are kept for a game year (%d)" % h.hourly.size())

	# --- Saved with the town.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.history.hourly.size() == h.hourly.size() and copy.history.monthly.size() == h.monthly.size(),
		"history comes back on load")
	_check(copy.history.hourly[-1] == h.hourly[-1], "the same numbers (%s)" % str(copy.history.hourly[-1]))
	var old := CitySim.new()
	var d := sim.to_dict()
	d.erase("history")
	old.from_dict(d)
	_check(old.history.hourly.is_empty() and old.history.rows(old, "year").size() == 1,
		"an older save starts its history from today")

	# --- Home: the middle of Main Street, or where the town was founded.
	_check(TownJump.centre_of(null, Vector3(5, 0, 7)) == Vector3(5, 0, 7), "a town with no streets: its origin")
	sim.streets.main_at = Vector2(40, -12)
	_check(TownJump.centre_of(sim, Vector3(1000, 0, 0)) == Vector3(1040, 0, -12), "a neighbor's Main Street, where it sits")
	var j := TownJump.new(sim, null)
	var towns := j.towns()
	_check(towns.size() == 1 and towns[0].mine and towns[0].at == Vector3(40, 0, -12), "offline, the list is just your town")

	print("stats tests ", "FAILED" if _failed else "passed")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
