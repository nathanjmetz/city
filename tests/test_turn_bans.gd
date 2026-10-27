extends SceneTree
## No left turn and no right turn signs at a junction, like CS2's turn
## rules (Nathan 2026-10-26: "i want all the same street and road options
## as CS2"). Drivers don't take a banned turn, a ban never leaves a car
## nowhere to go, and the signs survive a save.
## Run: godot --headless -s tests/test_turn_bans.gd

var _failed := false


func _init() -> void:
	# Two streets crossing at the origin.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200]})
	sim.tick()
	var c := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var t := sim.traffic
	_check(_count(t, c, TrafficSim.Turn.LEFT) == 4 and _count(t, c, TrafficSim.Turn.RIGHT) == 4,
		"at first every approach can turn left and right")

	_check(sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": true}), "a no left turn sign goes up")
	_check(_count(t, c, TrafficSim.Turn.LEFT) == 0, "nobody turns left there (%d left turns)" % _count(t, c, TrafficSim.Turn.LEFT))
	_check(_count(t, c, TrafficSim.Turn.RIGHT) == 4 and _count(t, c, TrafficSim.Turn.STRAIGHT) == 4,
		"right turns and straight on are still allowed")
	var into: Array = t.ways_into(c)
	_check(into.all(func(w): return t.banned_from(w) == ["left"]), "each approach knows it lost its left turn (for the signs)")
	for wi in into:
		var lanes := {}
		for wo in t._turns[wi]:
			for l in t._arrows[wi][wo]:
				lanes[l] = true
		_check(lanes.size() == t.ways[wi].lanes, "every lane still has somewhere to go")
	_check(not sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": true}), "putting the same sign up twice does nothing")

	# Drivers who wanted to turn left go another way, or can't get there
	# from here, but never through the banned turn.
	var west := -1
	var north_out := -1
	for wi in into:
		if t.ways[wi].pts[0].x < -1.0:
			west = wi
	sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": false})
	for wo in t._turns[west]:
		if t._kind[Vector2i(west, wo)] == TrafficSim.Turn.LEFT:
			north_out = wo
	_check(north_out != -1, "from the west there's a left turn when no sign is up")
	sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": true})
	var r: Array = t._route({"seg": t.ways[west].seg, "at_frac": 0.5}, {"seg": t.ways[north_out].seg, "at_frac": 0.5}).get("route", [])
	var through := false
	for i in range(1, r.size()):
		if int(r[i - 1]) == west and int(r[i]) == north_out:
			through = true
	_check(not through, "no route turns left through the sign")

	# Both signs at once still leave straight on.
	_check(sim.apply({"type": "turn_ban", "node": c, "turn": "right", "on": true}), "a no right turn sign goes up too")
	_check(_count(t, c, TrafficSim.Turn.RIGHT) == 0 and _count(t, c, TrafficSim.Turn.STRAIGHT) == 4, "straight on only")

	# It survives a save.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.tick()
	_check(copy.traffic.turn_bans.get(c, {}).has("left") and copy.traffic.turn_bans.get(c, {}).has("right"),
		"both signs are still up after a load")
	_check(_count(copy.traffic, c, TrafficSim.Turn.LEFT) == 0, "and still nobody turns left")
	# A town saved before signs existed loads with none.
	var old := sim.to_dict()
	old.erase("turn_bans")
	var older := CitySim.new()
	older.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(older.traffic.turn_bans.is_empty(), "an older town loads with no signs")

	# Taking them down brings the turns back.
	sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": false})
	sim.apply({"type": "turn_ban", "node": c, "turn": "right", "on": false})
	_check(_count(t, c, TrafficSim.Turn.LEFT) == 4 and not t.turn_bans.has(c), "signs down: left turns are back")
	_check(not sim.apply({"type": "turn_ban", "node": c, "turn": "uturn", "on": true}), "only left or right signs")

	# A T: from the stem a car can only turn left or right, so banning
	# both would trap it. The signs leave its turns alone there.
	var tee := CitySim.new()
	tee.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	tee.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200]})
	tee.tick()
	var tn := tee.network.find_node_near(Vector3.ZERO, 1.0)
	var stem := -1
	for wi in tee.traffic.ways_into(tn):
		if tee.traffic.ways[wi].pts[0].z > 1.0:
			stem = wi
	tee.apply({"type": "turn_ban", "node": tn, "turn": "left", "on": true})
	_check(tee.traffic._turns[stem].size() == 1, "from the stem with no left turns, only right")
	tee.apply({"type": "turn_ban", "node": tn, "turn": "right", "on": true})
	_check(tee.traffic._turns[stem].size() == 2 and tee.traffic.banned_from(stem).is_empty(),
		"both banned would trap it, so the stem keeps both turns and shows no sign")
	_check(not sim.apply({"type": "turn_ban", "node": sim.network.find_node_near(Vector3(-200, 0, 0), 1.0), "turn": "left", "on": true}),
		"no sign at a road end")
	_second_reader()
	quit(1 if _failed else 0)


## Cases the second reader found (2026-10-26).
func _second_reader() -> void:
	# A T whose crossbar's right arm is car-free: no left turn from the stem
	# would leave only the turn into the plaza, so the sign doesn't apply.
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200]})
	sim.tick()
	var tn := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var stem := -1
	for wi in sim.traffic.ways_into(tn):
		if sim.traffic.ways[wi].pts[0].z > 1.0:
			stem = wi
	var turns_before: Array = sim.traffic._turns[stem].duplicate()
	for wo in turns_before:
		if sim.traffic._kind[Vector2i(stem, wo)] == TrafficSim.Turn.RIGHT:
			sim.apply({"type": "car_free", "seg": sim.traffic.ways[wo].seg, "on": true})
	sim.apply({"type": "turn_ban", "node": tn, "turn": "left", "on": true})
	sim.tick()
	_check(sim.traffic._turns[stem].size() == 2 and sim.traffic.banned_from(stem).is_empty(),
		"a sign that would leave only a car-free street keeps both turns")

	# A sign at a junction that an undo took away is gone at once, so a
	# new junction given the same id doesn't start with it.
	var u := CitySim.new()
	u.economy.money = 10_000_000
	u.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	u.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200]})
	var j := u.network.find_node_near(Vector3.ZERO, 1.0)
	_check(u.apply({"type": "turn_ban", "node": j, "turn": "left", "on": true}), "a sign at the new T")
	_check(u.apply({"type": "undo"}), "the side street is undone")
	_check(u.traffic.turn_bans.is_empty(), "and its sign goes with it, before any tick")
	u.apply({"type": "build_road", "start": [100, 0], "ctrl": [100, -100], "end": [100, -200]})
	_check(u.traffic.turn_bans.is_empty(), "a new junction starts with no sign")


## How many turns of one kind cars may take at a junction.
func _count(t: TrafficSim, n: int, kind: int) -> int:
	var k := 0
	for wi in t.ways_into(n):
		for wo in t._turns[wi]:
			if t._kind[Vector2i(wi, wo)] == kind:
				k += 1
	return k


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
