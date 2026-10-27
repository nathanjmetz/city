extends SceneTree
## Taking away a crosswalk, like CS2's remove crosswalk (Nathan 2026-10-26:
## "i want all the same street and road options as CS2"). One leg at a
## time: people on foot stop crossing that road at that corner and go round
## by another, its paint goes, and it survives a save.
## Run: godot --headless -s tests/test_crosswalks.gd

var _failed := false


func _init() -> void:
	# Two streets crossing at the origin.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200]})
	sim.tick()
	var t := sim.traffic
	var c := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var west: int = sim.network.find_segment_near(Vector3(-50, 0, 0), 1.0).seg
	var north: int = sim.network.find_segment_near(Vector3(0, 0, -50), 1.0).seg
	_check(t.has_crosswalk(c, west), "every leg starts with a crosswalk")

	# From one side of the west street to the other, near the corner.
	var a := {"seg": west, "side": 1, "at_frac": 0.9 if sim.network.segments[west].b == c else 0.1}
	var b := {"seg": west, "side": -1, "at_frac": a.at_frac}
	t._marks = []
	var before := RoadNetwork.polyline_length(t._sidewalks(a, b))
	_check(_crosses(t, c, west), "with the crosswalk they cross the street at the corner")

	_check(sim.apply({"type": "crosswalk", "node": c, "seg": west, "on": false}), "the crosswalk is taken away")
	_check(not t.has_crosswalk(c, west) and t.has_crosswalk(c, north), "just that leg's")
	t._marks = []
	var after := RoadNetwork.polyline_length(t._sidewalks(a, b))
	_check(not _crosses(t, c, west), "nobody crosses there now")
	_check(after > before + 10.0, "they go round by the other crosswalks (%d m, was %d m)" % [after, before])
	_check(not sim.apply({"type": "crosswalk", "node": c, "seg": west, "on": false}), "taking it away twice does nothing")

	# The paint: one leg fewer.
	var plans := Junction.plan(sim.network)
	var plan: Dictionary = plans.get(c, {})
	if JunctionMarks.marked(plan):
		var all := SurfaceTool.new()
		all.begin(Mesh.PRIMITIVE_TRIANGLES)
		JunctionMarks.paint(plan, {}, all, 0.0)
		var less := SurfaceTool.new()
		less.begin(Mesh.PRIMITIVE_TRIANGLES)
		JunctionMarks.paint(plan, {}, less, 0.0, t.no_crosswalks[c])
		_check(_verts(less) < _verts(all), "its crosswalk isn't painted (%d of %d)" % [_verts(less), _verts(all)])
	else:
		_check(false, "the crossing is a painted town junction")

	# It survives a save; a town saved before this loads with every crosswalk.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.tick()
	_check(not copy.traffic.has_crosswalk(c, west), "still gone after a load")
	var old := sim.to_dict()
	old.erase("no_crosswalks")
	var older := CitySim.new()
	older.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(older.traffic.no_crosswalks.is_empty(), "an older town loads with every crosswalk")

	# A road joining the west street further out cuts it: the piece at the
	# corner keeps the missing crosswalk.
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-100, 50], "end": [-100, 100]})
	sim.tick()
	var near_piece: int = sim.network.find_segment_near(Vector3(-30, 0, 0), 1.0).seg
	_check(near_piece != west and not t.has_crosswalk(c, near_piece), "the corner piece keeps it after a cut")
	_check(not t.no_crosswalks[c].has(west), "and the old id is gone")

	# Put back.
	_check(sim.apply({"type": "crosswalk", "node": c, "seg": near_piece, "on": true}), "the crosswalk is put back")
	_check(t.no_crosswalks.is_empty(), "every crosswalk is back")
	_check(not sim.apply({"type": "crosswalk", "node": c, "seg": north + 999, "on": false}), "only a road that meets the junction")
	_undo_keeps_it()
	quit(1 if _failed else 0)


## Second reader (2026-10-26): a road that cut the leg, undone, leaves the
## leg's crosswalk still taken away.
func _undo_keeps_it() -> void:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200]})
	sim.tick()
	var c := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var west: int = sim.network.find_segment_near(Vector3(-50, 0, 0), 1.0).seg
	sim.apply({"type": "crosswalk", "node": c, "seg": west, "on": false})
	sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": true})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-100, 50], "end": [-100, 100]})
	_check(not sim.traffic.has_crosswalk(c, sim.network.find_segment_near(Vector3(-30, 0, 0), 1.0).seg), "cut: the corner piece has it")
	_check(sim.apply({"type": "undo"}), "the cutting road is undone")
	_check(sim.network.segments.has(west) and not sim.traffic.has_crosswalk(c, west), "undone: the leg's crosswalk is still taken away")
	_check(sim.traffic.turn_bans.get(c, {}).has("left"), "and the no left turn sign is still up")
	# Two legs gone: no junction, no settings.
	var north: int = sim.network.find_segment_near(Vector3(0, 0, -50), 1.0).seg
	var south: int = sim.network.find_segment_near(Vector3(0, 0, 50), 1.0).seg
	sim.apply({"type": "remove_road", "seg": north})
	sim.apply({"type": "remove_road", "seg": south})
	sim.tick()
	_check(sim.traffic.turn_bans.is_empty() and sim.traffic.no_crosswalks.is_empty(), "a plain bend keeps no settings once two legs go")


## Whether the walk just planned crossed road `seg` at junction `n`.
func _crosses(t: TrafficSim, n: int, seg: int) -> bool:
	for m in t._marks:
		if int(m[1]) == n and int(m[2]) >> 1 == seg:
			return true
	return false


func _verts(st: SurfaceTool) -> int:
	var arrays := st.commit_to_arrays()
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arrays[Mesh.ARRAY_VERTEX] != null else 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
