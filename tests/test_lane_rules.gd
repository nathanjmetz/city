extends SceneTree
## Run: godot --headless -s tests/test_lane_rules.gd
## Lane arrows and No Left and No Right Turn signs (Brawn's pick, TM:PE
## style, MUTCD 3B.20 lane-use arrows, R3-2 and R3-1): the player marks a
## junction approach and traffic follows it; a banned turn never strands a
## car; rules save, and keep through an undo.

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

	# No Right Turn, the same way.
	_check(sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_right": true, "lanes": []}),
		"a No Right Turn sign goes up")
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]), "a No Right Turn sign closes the right")
	_check(t._turns[wi].has(turns[TrafficSim.Turn.STRAIGHT]) and t._turns[wi].has(turns[TrafficSim.Turn.LEFT]),
		"straight and left are open again (the No Left sign came down)")
	_check(_turns_by_kind(t, other).has(TrafficSim.Turn.RIGHT), "No Right is for its own approach only")
	_check(sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": true, "no_right": true, "lanes": []}),
		"both signs on one approach")
	_check(t._turns[wi] == [turns[TrafficSim.Turn.STRAIGHT]], "straight on is the only way now")
	_check(t.lane_masks(wi) == [TrafficSim.ARROW_S, TrafficSim.ARROW_S], "and both lanes go straight")
	_check(not sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": true, "no_right": true, "lanes": []}),
		"putting up the same signs again changes nothing")

	# Saved and loaded.
	var d := t.lane_rules_to_dict()
	t.lane_rules_from_dict({})
	t._rebuild()
	_check(t._turns[wi].has(turns[TrafficSim.Turn.LEFT]), "without the rule the left is back")
	t.lane_rules_from_dict(JSON.parse_string(JSON.stringify(d)))
	t._rebuild()
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.LEFT]), "the sign comes back from a save")
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]), "and so does No Right")
	# A town saved before No Right had only no_left and lanes: it loads with
	# no No Right signs.
	t.lane_rules_from_dict({TrafficSim.lane_key(node, west): {"no_left": true, "lanes": []}})
	t._rebuild()
	_check(not t._turns[wi].has(turns[TrafficSim.Turn.LEFT]) and t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]),
		"an older save loads with its No Left and no No Right")
	_check(t.lane_rules_to_dict()[TrafficSim.lane_key(node, west)].no_right == false, "and saves no_right off")
	_check(sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_left": false, "lanes": []}), "cleared")
	_check(t.lane_rules.is_empty(), "nothing left in the table")

	# Undo: a road built and undone elsewhere keeps the sign; a junction the
	# undo takes away takes its sign with it.
	sim.economy.money = 10_000_000
	sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_right": true, "lanes": []})
	var far := sim.network.find_node_near(Vector3(-300, 0, 0), 1.0)
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -100], "end": [-300, -200]})
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, 100], "end": [-300, 200]})
	t._rebuild()
	_check(sim.network.segments_at(far).size() == 3, "two streets make a junction at the avenue's far end")
	_check(sim.apply({"type": "set_lanes", "node": far, "seg": west, "no_right": true, "lanes": []}),
		"a No Right sign there too")
	_check(sim.apply({"type": "undo"}), "the last street is undone")
	t._rebuild()
	_check(not t.lane_rules.has(TrafficSim.lane_key(far, west)), "the sign at the junction undone goes with it")
	_check(t.lane_rule(node, west).get("no_right", false) and not t._turns[wi].has(turns[TrafficSim.Turn.RIGHT]),
		"the sign at the crossing stays, and its right is still closed")
	# Undo hands the ids out again: the same street built straight after
	# makes a new junction with the same ids. It starts bare.
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, 100], "end": [-300, 200]})
	_check(sim.apply({"type": "set_lanes", "node": far, "seg": west, "no_right": true, "lanes": []}),
		"(the street and its sign are back)")
	sim.apply({"type": "undo"})
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, 100], "end": [-300, 200]})
	_check(sim.network.segments_at(far).size() == 3, "(built again, on the same junction id)")
	_check(not t.lane_rules.has(TrafficSim.lane_key(far, west)), "a junction made again after an undo has no old sign")
	sim.apply({"type": "set_lanes", "node": node, "seg": west, "no_right": false, "lanes": []})

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

	# The same with No Right: south is a right from the west, banned, so a
	# car for the south goes on east, turns at the dead end and comes back.
	var rt := CitySim.new()
	rt.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-150, 0], "end": [0, 0]})
	rt.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	rt.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 250]})
	rt.traffic._rebuild()
	var rn := rt.network.find_node_near(Vector3.ZERO, 1.0)
	var rw := _seg_toward(rt, rn, Vector3(-1, 0, 0))
	var rwi := _way_in(rt.traffic, rn, rw)
	var south := _turns_by_kind(rt.traffic, rwi)
	_check(south.has(TrafficSim.Turn.RIGHT), "from the west, south is a right")
	rt.apply({"type": "set_lanes", "node": rn, "seg": rw, "no_right": true, "lanes": []})
	_check(not rt.traffic._turns[rwi].has(south[TrafficSim.Turn.RIGHT]), "and it's banned")
	var rvid := rt.traffic.dispatch({"ref": "yard", "pos": [-280, 10]}, {"ref": "site", "pos": [10, 230]}, "construction", {}, "pickup")
	_check(rvid != -1, "a pickup is sent south")
	var right_turns := 0
	var went_east := false
	arrived = false
	for i in 6000:
		rt.tick()
		var f := rt.traffic.find_vehicle(rvid)
		if f.is_empty() or f.state == "parked":
			arrived = true
			break
		var j = f.car.get("j")
		if j is Dictionary and int(j.get("wi", -1)) == rwi:
			if int(j.get("wo", -1)) == south[TrafficSim.Turn.RIGHT]:
				right_turns += 1
			elif int(j.get("wo", -1)) == south.get(TrafficSim.Turn.STRAIGHT, -2):
				went_east = true
	_check(arrived, "it gets there by another way")
	_check(right_turns == 0 and went_east, "going on east, not right at the sign")
	# At the foot of a T, where left and right are the only ways on, both
	# signs can't strand a car: the turns stay.
	var stem := _way_in(rt.traffic, rn, _seg_toward(rt, rn, Vector3(0, 0, 1)))
	var both := _turns_by_kind(rt.traffic, stem)
	rt.apply({"type": "set_lanes", "node": rn, "seg": rt.traffic.ways[stem].seg, "no_left": true, "no_right": true, "lanes": []})
	_check(rt.traffic._turns[stem].size() == 2 and both.has(TrafficSim.Turn.LEFT) and both.has(TrafficSim.Turn.RIGHT),
		"both signs at the foot of a T leave its turns open")
	rt.apply({"type": "set_lanes", "node": rn, "seg": rt.traffic.ways[stem].seg, "no_right": true, "lanes": []})
	_check(_turns_by_kind(rt.traffic, stem).keys() == [TrafficSim.Turn.LEFT], "No Right alone there leaves the left")
	# A sign never leaves only a car-free street: with the way on east
	# closed to cars, the banned right from the west opens again.
	_check(not rt.traffic._turns[rwi].has(south[TrafficSim.Turn.RIGHT]), "(the west's right is still banned)")
	rt.traffic.close_segment(_seg_toward(rt, rn, Vector3(1, 0, 0)), true)
	rt.traffic._rebuild()
	_check(rt.traffic._turns[rwi].has(south[TrafficSim.Turn.RIGHT]),
		"with only a car-free street left, the banned right stays open")

	# No turn signs on a roundabout's ring (reviewer 2026-10-29): leaving
	# for a side street counts as a right off the ring, and the ring only
	# goes one way, so No Right there would leave that street with no way in.
	var rb := CitySim.new()
	rb.economy.money = 1.0e9
	rb.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.AVENUE})
	rb.apply({"type": "build_roundabout", "center": [0, 0], "radius": 24, "road": RoadStyle.Type.AVENUE})
	rb.traffic._rebuild()
	var ring_way := -1
	var entry_way := -1
	for wid in rb.traffic.ways:
		var rw2: Dictionary = rb.traffic.ways[wid]
		if rb.network.segments_at(rw2.to).size() < 3:
			continue
		if RoadStyle.is_ring(rw2.type):
			ring_way = wid
		else:
			entry_way = wid
	_check(ring_way != -1 and entry_way != -1, "a ring lane and an entry road meet at a roundabout corner")
	var rnode: int = rb.traffic.ways[ring_way].to
	var rseg: int = rb.traffic.ways[ring_way].seg
	var ring_turns: Array = rb.traffic._turns[ring_way].duplicate()
	_check(not rb.traffic.takes_turn_signs(rseg), "the ring can't take turn signs")
	_check(not rb.apply({"type": "set_lanes", "node": rnode, "seg": rseg, "no_right": true, "lanes": []}),
		"No Right on the ring is refused")
	_check(not rb.apply({"type": "set_lanes", "node": rnode, "seg": rseg, "no_left": true, "lanes": []}),
		"and so is No Left")
	_check(rb.traffic.lane_rules.is_empty() and rb.traffic._turns[ring_way] == ring_turns, "the ring keeps every exit")
	# A No Left from an older save, on the ring: ignored, every exit stays.
	rb.traffic.lane_rules_from_dict({TrafficSim.lane_key(rnode, rseg): {"no_left": true, "no_right": true, "lanes": []}})
	rb.traffic._rebuild()
	_check(rb.traffic._turns[ring_way] == ring_turns, "signs on the ring from an older save close nothing")
	rb.traffic.lane_rules_from_dict({})
	rb.traffic._rebuild()
	_check(rb.traffic.takes_turn_signs(rb.traffic.ways[entry_way].seg), "a road coming into the roundabout still can")
	# The tool says why on hover.
	var tool := TrafficTool.new()
	tool.sim = rb
	tool.mode = TrafficTool.Mode.NO_RIGHT
	tool._approach = ring_way
	tool._update_hint()
	_check(tool._hint.contains("roundabout can't take turn signs"), "hovering the ring says why (%s)" % tool._hint)
	tool._approach = entry_way
	tool._update_hint()
	_check(tool._hint.contains("can turn right"), "hovering the entry offers the sign")
	tool.free()

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
