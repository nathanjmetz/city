extends SceneTree
## Run: godot --headless -s tests/test_lane_rules.gd
## Lane arrows and No Left Turn signs (Brawn's pick, TM:PE style, MUTCD
## 3B.20 lane-use arrows and R3-2): the player marks a junction approach and
## traffic follows it; a banned left never strands a car; rules save.

func _init() -> void:
	# Two avenues crossing (two lanes each way).
	var sim := CitySim.new()
	for a in [[-300, 0], [300, 0], [0, -300], [0, 300]]:
		sim.apply({"type": "build_road", "start": a, "ctrl": [a[0] * 0.5, a[1] * 0.5], "end": [0, 0], "road": 1})
	var t := sim.traffic
	t._rebuild()
	var node := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var west := _seg_toward(sim, node, Vector3(-1, 0, 0))
	var wi := _way_in(t, node, west)
	_check(wi != -1 and t.ways[wi].lanes == 2, "the avenue arrives with two lanes")
	var turns := _turns_by_kind(t, wi)
	_check(turns.size() == 3, "left, straight and right out of the west leg")
	_check(t.lanes_for(wi, turns[TrafficSim.Turn.LEFT]) == [0], "on its own the left lane takes the left")
	_check(t.lanes_for(wi, turns[TrafficSim.Turn.STRAIGHT]) == [0, 1], "and both lanes go straight")

	# The Lanes tool finds the lane under the cursor a little back from the line.
	var sl := t.stop_line(wi)
	var pick := TrafficTool.approach_near(t, sl.pos - sl.dir * 8.0 + sl.right * float(t.ways[wi].offs[1]))
	_check(pick == [wi, 1], "clicking the right lane picks it (%s)" % str(pick))
	pick = TrafficTool.approach_near(t, sl.pos - sl.dir * 8.0 + sl.right * float(t.ways[wi].offs[0]))
	_check(pick == [wi, 0], "and the left lane")
	_check(TrafficTool.next_arrows(TrafficSim.ARROW_L) == TrafficSim.ARROW_L | TrafficSim.ARROW_S
		and TrafficTool.next_arrows(TrafficSim.ARROW_L | TrafficSim.ARROW_S | TrafficSim.ARROW_R) == TrafficSim.ARROW_L,
		"each click steps a lane's arrows round")
	_check(t.lane_masks(wi) == [TrafficSim.ARROW_L | TrafficSim.ARROW_S, TrafficSim.ARROW_S | TrafficSim.ARROW_R],
		"the game's own arrows: left or straight, straight or right")

	# Lane arrows: left lane left only, right lane straight or right.
	_check(sim.apply({"type": "set_lanes", "node": node, "seg": west, "lanes": [TrafficSim.ARROW_L, TrafficSim.ARROW_S | TrafficSim.ARROW_R]}),
		"lane arrows are set")
	_check(t.lanes_for(wi, turns[TrafficSim.Turn.LEFT]) == [0], "left arrow: the left lane turns left")
	_check(t.lanes_for(wi, turns[TrafficSim.Turn.STRAIGHT]) == [1], "straight only from the right lane now")
	_check(t.lanes_for(wi, turns[TrafficSim.Turn.RIGHT]) == [1], "right from the right lane")
	_check(not sim.apply({"type": "set_lanes", "node": node, "seg": west, "lanes": [TrafficSim.ARROW_L, TrafficSim.ARROW_S | TrafficSim.ARROW_R]}),
		"setting the same arrows again changes nothing")
	# Arrows that leave out a turn close it.
	sim.apply({"type": "set_lanes", "node": node, "seg": west, "lanes": [TrafficSim.ARROW_S, TrafficSim.ARROW_S]})
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.LEFT]) and not t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]),
		"straight arrows in every lane: no turns from here")

	# No Left Turn.
	sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": true, "lanes": []})
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.LEFT]), "a No Left Turn sign closes the left")
	_check(t._turns[wi].has(turns[TrafficSim.Turn.STRAIGHT]) and t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]),
		"straight and right stay open")
	var other := _way_in(t, node, _seg_toward(sim, node, Vector3(1, 0, 0)))
	_check(_turns_by_kind(t, other).has(TrafficSim.Turn.LEFT), "the sign is for its own approach only")

	# Saved and loaded.
	var d := t.lane_rules_to_dict()
	t.lane_rules_from_dict({})
	t._rebuild()
	_check(t._turns[wi].has(turns[TrafficSim.Turn.LEFT]), "without the rule the left is back")
	t.lane_rules_from_dict(JSON.parse_string(JSON.stringify(d)))
	t._rebuild()
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.LEFT]), "the sign comes back from a save")
	_check(sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": false, "lanes": []}), "cleared")
	_check(t.lane_rules.is_empty(), "nothing left in the table")

	# A banned left where the only way on is round a dead end: the car still
	# gets there (turns at the dead end and comes back), never stuck.
	var tt := CitySim.new()
	tt.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-150, 0], "end": [0, 0]})
	tt.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	tt.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -100], "end": [0, -250]})
	tt.traffic._rebuild()
	var tn := tt.network.find_node_near(Vector3.ZERO, 1.0)
	var tw := _seg_toward(tt, tn, Vector3(-1, 0, 0))
	var twi := _way_in(tt.traffic, tn, tw)
	var north := _turns_by_kind(tt.traffic, twi)
	_check(north.has(TrafficSim.Turn.LEFT), "from the west, north is a left")
	tt.apply({"type": "set_lanes", "node": tn, "seg": tw, "no_left": true, "lanes": []})
	_check(not tt.traffic._turns[twi].has(north[TrafficSim.Turn.LEFT]), "and it's banned")
	var vid := tt.traffic.dispatch({"ref": "yard", "pos": [-280, 10]}, {"ref": "site", "pos": [10, -230]}, "construction", {}, "pickup")
	_check(vid != -1, "a pickup is sent north")
	var left_turns := 0
	var arrived := false
	for i in 6000:
		tt.tick()
		var f := tt.traffic.find_vehicle(vid)
		if f.is_empty() or f.state == "parked":
			arrived = true
			break
		var j = f.car.get("j")
		if j is Dictionary and int(j.get("wi", -1)) == twi and int(j.get("wo", -1)) == north[TrafficSim.Turn.LEFT]:
			left_turns += 1
	_check(arrived, "it gets there anyway")
	_check(left_turns == 0, "without turning left at the sign")

	# A road gone takes its rule with it.
	sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": true, "lanes": []})
	sim.apply({"type": "remove_road", "seg": _seg_toward(sim, node, Vector3(0, 0, 1))})
	sim.apply({"type": "remove_road", "seg": _seg_toward(sim, node, Vector3(0, 0, -1))})
	t._rebuild()
	_check(t.lane_rules.is_empty(), "a junction that's gone drops its rules")
	quit(1 if _failed else 0)


func _seg_toward(sim: CitySim, node: int, dir: Vector3) -> int:
	var best := -1
	var best_d := -INF
	for seg in sim.network.segments_at(node):
		var c := sim.network.curve_of(seg)
		var far: Vector3 = c[2] if (c[0] as Vector3).distance_to(sim.network.nodes[node]) < 1.0 else c[0]
		var d: float = (far - sim.network.nodes[node]).normalized().dot(dir)
		if d > best_d:
			best_d = d
			best = seg
	return best


func _way_in(t: TrafficSim, node: int, seg: int) -> int:
	for wid in t.ways_into(node):
		if t.ways[wid].seg == seg:
			return wid
	return -1


## Turn kind -> the way out it leads to, for ways out of `wi`.
func _turns_by_kind(t: TrafficSim, wi: int) -> Dictionary:
	var out := {}
	for wo in t._turns.get(wi, []):
		out[t._kind[Vector2i(wi, wo)]] = wo
	return out


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
