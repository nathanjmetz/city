extends SceneTree
## Run: godot --headless -s tests/test_advisor.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.require_utilities = true
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [-250, 0], "end": [-100, 0]})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	_check(Advisor.is_new_city(sim), "a fresh town counts as new")
	var first := Advisor.first_ideas(sim)
	_check(first.size() == 3, "three first steps for a new town (%d)" % first.size())
	_check(_ids(Advisor.tips(sim)).has("first_streets"), "a new town gets nudged toward streets")
	_check(not _kinds(Advisor.tips(sim)).has(Advisor.Kind.PROBLEM), "nothing's wrong with a new town")

	# Zoned without utilities: flagged as a problem, first in line.
	sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [140, 60], "end": [240, 60]})
	for x in range(40, 241, 10):
		sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.update_stats()
	var tips := Advisor.tips(sim)
	_check(not Advisor.is_new_city(sim), "a zoned town isn't new")
	_check(tips[0].id == "no_utilities", "no power or water is the top worry (got %s)" % tips[0].id)
	_check("power or water" in tips[0].text, "names both missing utilities")

	sim.economy.money = 1000
	_check(Advisor.tips(sim).any(func(t): return t.id == "no_utilities" and "short" in t.text), "says when the town can't afford power and water")
	sim.economy.money = Economy.START_MONEY

	# The tool in hand gets a note, right after the problems.
	tips = Advisor.tips(sim, "roads")
	_check(tips[1].kind == Advisor.Kind.TOOL and tips[1].id.begins_with("tool_roads"), "road tool note after problems")
	_check(not _kinds(Advisor.tips(sim, "")).has(Advisor.Kind.TOOL), "no tool note with no tool out")

	# Money trouble.
	sim.economy.money = -5
	_check(_ids(Advisor.tips(sim)).has("broke"), "in the red is flagged")
	sim.economy.money = Economy.START_MONEY

	# Traffic jams only count with real traffic.
	sim.traffic.flow = 0.3
	_check(not _ids(Advisor.tips(sim)).has("traffic"), "no traffic worry without cars")

	# Industry: stuck trucks are a problem; the tool gets its own notes.
	sim.logistics.stuck["site:1"] = true
	_check(_ids(Advisor.tips(sim)).has("trucks_stuck"), "stuck trucks are flagged")
	sim.logistics.stuck.clear()
	_check(_ids(Advisor.tips(sim, "industry")).any(func(i): return i.begins_with("tool_industry")), "industry tool note")

	# Every line is short enough to read at a glance and never empty.
	for t in Advisor.tips(sim, "farms"):
		_check(t.text.length() > 10 and t.text.length() <= 170, "tip %s reads short (%d chars)" % [t.id, t.text.length()])
	for cat in Advisor.TOOL_NOTES:
		for note in Advisor.TOOL_NOTES[cat]:
			_check(note.length() <= 170, "tool note reads short")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _ids(tips: Array) -> Array:
	return tips.map(func(t): return t.id)


func _kinds(tips: Array) -> Array:
	return tips.map(func(t): return t.kind)


var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
