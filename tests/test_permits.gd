extends SceneTree
## Run: godot --headless -s tests/test_permits.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [300, -200], "ctrl": [300, 0], "end": [300, 200]})
	var p := sim.permits
	var across := [[0, -150], [0, 150]]
	var hits := p.check(sim, across, 8.0)
	_check(Permits.needs(hits) and hits.roads.size() == 1, "track across a road needs a permit (%s)" % str(hits))
	_check(not Permits.needs(p.check(sim, [[-100, -100], [100, -100]], 8.0)), "track on empty land needs none")

	var plan := {"hub": "rail", "hub_id": 1, "leader": "Dale Hoffman", "title": "Track to the elevator",
		"why": "Grain waits on trucks.", "route": across, "width": 8.0, "per_m": 1000, "budget": 1000000}
	var id := p.file(sim, plan)
	_check(id > 0 and p.state_of(id) == Permits.State.OPEN, "a hub files a request")
	_check(p.requests[id].cost == 300 * 1000 + Permits.PER_CROSSING, "the leader prices it (%d)" % p.requests[id].cost)
	_check(p.file(sim, plan) == -1, "one open request per hub")
	for i in range(2, 5):
		var other := plan.duplicate()
		other.hub_id = i
		var got := p.file(sim, other)
		_check((got > 0) == (i < Permits.MAX_OPEN + 1), "only %d open at once (hub %d)" % [Permits.MAX_OPEN, i])

	# The player answers through apply, like every command.
	_check(sim.apply({"type": "permit", "id": id, "answer": "approve"}), "approve goes through")
	_check(p.approved("rail", 1).size() == 1, "the hub sees its approval")
	_check(not sim.apply({"type": "permit", "id": id, "answer": "deny"}), "an answered request stays answered")
	p.done(id)
	_check(p.state_of(id) == Permits.State.DONE, "the hub marks it built")

	# Deny: the hub waits before asking again.
	var two: int = p.listed(Permits.State.OPEN)[0].id
	sim.apply({"type": "permit", "id": two, "answer": "deny"})
	var again := plan.duplicate()
	again.hub_id = p.requests[two].hub_id
	_check(p.file(sim, again) == -1, "a hub told no waits before asking again")

	# Edit: the route bends around; the ends stay put and it's re-costed.
	var three: int = p.listed(Permits.State.OPEN)[0].id
	var bent := [[9, 9], [250, -150], [250, 150], [0, 150]]
	_check(sim.apply({"type": "permit", "id": three, "answer": "edit", "route": bent}), "an edit goes through")
	var r: Dictionary = p.requests[three]
	_check(r.route[0] == [0.0, -150.0], "the start stays where the hub is")
	_check(r.hits.roads.is_empty() and r.state == Permits.State.APPROVED, "around the road's end it crosses nothing, and within budget the leader goes ahead")
	_check(r.cost > 300 * 1000, "the longer way costs more (%d)" % r.cost)

	# Too dear: it comes back open with a note.
	var cheap := plan.duplicate()
	cheap.hub_id = 9
	cheap.budget = 400000
	var four := p.file(sim, cheap)
	sim.apply({"type": "permit", "id": four, "answer": "edit", "route": [[0, -150], [600, -150], [600, 150], [0, 150]]})
	_check(p.requests[four].state == Permits.State.OPEN and p.requests[four].note != "", "over budget: back to the player")

	# Ignored requests are shelved, never forced.
	for i in Permits.SHELVE_AFTER + Permits.CHECK_EVERY:
		sim.tick_count += 1
		p.tick(sim)
	_check(p.state_of(four) == Permits.State.SHELVED, "an ignored request is shelved")
	_check(sim.apply({"type": "permit", "id": four, "answer": "approve"}), "a shelved one can still be approved")

	# Saves and every copy of the city agree.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy.permits.to_dict()) == JSON.stringify(p.to_dict()), "save round trip keeps permits")
	var five := p.file(sim, {"hub": "bus", "hub_id": 1, "leader": "Jo", "title": "t", "why": "w",
		"route": across, "per_m": 10})
	var five_copy := copy.permits.file(copy, {"hub": "bus", "hub_id": 1, "leader": "Jo", "title": "t", "why": "w",
		"route": across, "per_m": 10})
	_check(five == five_copy, "copies give the same ids")
	_check(JSON.stringify(copy.permits.to_dict()) == JSON.stringify(p.to_dict()), "copies stay in sync")
	# Guidance, the other way round: the player tells a leader what to do.
	_check(p.guidance("airport", 1).stance == "steady", "leaders use their own judgment by default")
	_check(not sim.apply({"type": "guide", "hub": "airport", "hub_id": 1, "stance": "panic"}), "only real stances")
	sim.apply({"type": "guide", "hub": "airport", "hub_id": 1, "stance": "grow"})
	_check(p.guidance("airport", 1).stance == "grow", "the airport is told to grow")
	p.locators["airport"] = func(_s, _id): return Vector2(0, -150)
	sim.apply({"type": "guide", "hub": "airport", "hub_id": 1, "stance": "grow", "grant": 500})
	var free := p.file(sim, {"hub": "airport", "hub_id": 1, "leader": "Pat", "title": "Longer runway", "why": "w",
		"route": across, "per_m": 10})
	_check(p.state_of(free) == Permits.State.APPROVED, "inside the pre-approved area a request goes straight through")
	sim.apply({"type": "guide", "hub": "airport", "hub_id": 1, "stance": "hold"})
	_check(not p.can_file(sim, "airport", 1), "told to hold off, a leader doesn't ask")
	var g := CitySim.new()
	g.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(g.permits.guidance("airport", 1).stance == "hold", "guidance is saved")
	sim.apply({"type": "clear"})
	_check(sim.permits.requests.is_empty(), "clearing the map clears requests")

	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
