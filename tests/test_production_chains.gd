extends SceneTree
## The production chain page (Brawn's pick #15): every load that arrives is
## counted on its link, a year is kept, and the links group into chains
## that read from where a good starts to where it goes.
## Run: godot --headless -s tests/test_production_chains.gd


func _init() -> void:
	var pc := ProductionChains.new()
	var cal := 0
	pc.count(cal, "farm", "mill", "corn")
	pc.count(cal, "farm", "mill", "corn")
	pc.count(cal, "mill", "shop", "goods")
	pc.count(cal, "farm", "region", "soybeans")
	pc.count(cal, "forest", "sawmill", "logs")
	pc.count(cal, "sawmill", "build", "posts and trusses")
	pc.count(cal, "ore", "build", "ready-mix concrete")
	pc.count(cal, "region", "general", "materials")
	pc.count(cal, "farm", "farm", "corn")  # not a link
	var links := pc.links()
	_check(links.size() == 7 and links[0].from == "farm" and links[0].to == "mill" and links[0].loads == 2,
		"loads add up on their link, biggest first (%s)" % str(links[0]))
	var chains := pc.chains()
	var names := chains.map(func(c): return c.name)
	_check(names == ["Grain", "Timber", "Stone and gravel", "Brought in"], "chains in order (%s)" % str(names))
	var grain: Array = chains[0].links.map(func(l): return "%s>%s" % [l.from, l.to])
	_check("mill>shop" in grain and "farm>region" in grain, "grain follows on through the mill to the stores (%s)" % str(grain))
	_check(chains[1].links.size() == 2, "timber runs woods to sawmill to job sites")

	# A year is kept: months older than twelve drop off.
	for m in 14:
		pc.count(Seasons.tick_at(Seasons.months(0) + m + 1), "oil", "refinery", "crude oil")
	_check(pc.months.size() == ProductionChains.KEEP, "twelve months kept (%d)" % pc.months.size())
	_check(pc.links().filter(func(l): return l.from == "farm").is_empty(), "the oldest month dropped off")

	# Saved and loaded.
	var copy := ProductionChains.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(pc.to_dict())))
	_check(copy.links() == pc.links(), "the tally is saved")

	# A real truck arriving counts.
	var sim := CitySim.new()
	sim.logistics._arrive(sim, {"from": {"ref": "farm:1", "pos": [0, 0]}, "to": {"ref": "edge", "pos": [0, 0]},
		"purpose": "grain", "cargo": {"good": "corn", "amount": 900}, "kind": "farm"})
	var l: Array = sim.chains.links()
	_check(l.size() == 1 and l[0].from == "farm" and l[0].to == "region" and l[0].good == "corn",
		"a grain truck reaching the highway counts on farms to region (%s)" % str(l))
	_check(sim.to_dict().has("chains"), "the town saves it")

	# The page draws.
	var view := ProductionView.new()
	view.setup(sim)
	root.add_child(view)
	view.refresh()
	_check(view._rows.get_child_count() > 0 and not view._empty.visible, "the page lists the chain")
	view.queue_free()

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
