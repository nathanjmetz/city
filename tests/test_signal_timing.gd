extends SceneTree
## The player sets how long each direction's green lasts at a light (Nathan,
## 2026-10-25), within real limits, and it survives a save.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	var x := CitySim.new()
	x.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.AVENUE})
	x.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200], "road": RoadStyle.Type.AVENUE})
	x.tick()
	var c := x.network.find_node_near(Vector3.ZERO, 1.0)
	var before: Array = x.traffic.greens_at(c)
	_check(before.size() == 2, "two avenues crossing have two phases (%s)" % [before])
	_check(x.apply({"type": "set_green", "node": c, "phase": 0, "seconds": float(before[0]) + 20.0}), "a green time can be set")
	var after: Array = x.traffic.greens_at(c)
	_check(is_equal_approx(float(after[0]), float(before[0]) + 20.0) and is_equal_approx(float(after[1]), float(before[1])),
		"only that direction's green changes (%s)" % [after])
	x.apply({"type": "set_green", "node": c, "phase": 1, "seconds": 2.0})
	_check(is_equal_approx(float(x.traffic.greens_at(c)[1]), TrafficSim.GREEN_MIN), "never shorter than the minimum green")
	x.apply({"type": "set_green", "node": c, "phase": 1, "seconds": 500.0})
	_check(is_equal_approx(float(x.traffic.greens_at(c)[1]), TrafficSim.GREEN_MAX), "never longer than the maximum")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(x.to_dict())))
	copy.tick()
	_check(copy.traffic.greens_at(c) == x.traffic.greens_at(c), "the times survive a save and load")
	x.apply({"type": "set_green", "node": c, "phase": 0, "seconds": 0.0})
	_check(is_equal_approx(float(x.traffic.greens_at(c)[0]), float(before[0])), "0 puts a direction back on the automatic time")
	_check(not x.apply({"type": "set_green", "node": c + 999, "phase": 0, "seconds": 30.0}), "a junction without lights says no")
	# A green wave: two lights 300 m apart on an avenue; the second turns
	# green as cars leaving the first on green arrive at the limit.
	var w := CitySim.new()
	w.apply({"type": "build_road", "start": [-300, 0], "ctrl": [150, 0], "end": [600, 0], "road": RoadStyle.Type.AVENUE})
	w.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200], "road": RoadStyle.Type.AVENUE})
	w.apply({"type": "build_road", "start": [300, -200], "ctrl": [300, 0], "end": [300, 200], "road": RoadStyle.Type.AVENUE})
	w.tick()
	var a := w.network.find_node_near(Vector3.ZERO, 1.0)
	var b := w.network.find_node_near(Vector3(300, 0, 0), 1.0)
	var v := 15.6
	_check(w.apply({"type": "link_wave", "from": a, "to": b, "v": v}), "two lights can be linked in a green wave")
	var ja: Dictionary = w.traffic.junctions[a]
	var jb: Dictionary = w.traffic.junctions[b]
	_check(is_equal_approx(ja.cycle, jb.cycle), "both run one cycle (%.1f, %.1f s)" % [ja.cycle, jb.cycle])
	# When each light's first phase turns green: (time + offset) mod cycle == 0.
	var ga := fposmod(-ja.offset, ja.cycle)
	var gb := fposmod(-jb.offset, jb.cycle)
	var lag := fposmod(gb - ga, ja.cycle)
	var travel := 300.0 / v
	_check(absf(lag - fposmod(travel, ja.cycle)) < 0.5, "the second light turns green %.1f s after the first (the drive takes %.1f s)" % [lag, travel])
	var wc := CitySim.new()
	wc.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	wc.tick()
	_check(is_equal_approx(wc.traffic.junctions[b].offset, jb.offset), "the wave survives a save and load")
	# Smart lights: a lone car on the side street gets a green soon, not after
	# a fixed cycle, and the state survives a save.
	var sm := CitySim.new()
	sm.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": RoadStyle.Type.AVENUE})
	sm.apply({"type": "build_road", "start": [0, -300], "ctrl": [0, 0], "end": [0, 300], "road": RoadStyle.Type.AVENUE})
	sm.tick()
	var sn := sm.network.find_node_near(Vector3.ZERO, 1.0)
	_check(sm.apply({"type": "set_actuated", "node": sn, "on": true}), "a light can be made smart")
	var sj: Dictionary = sm.traffic.junctions[sn]
	var srest: int = int(sm.traffic.actuated[sn].ph)
	for i in 100:
		sm.tick()
	_check(int(sm.traffic.actuated[sn].ph) == srest and int(sm.traffic.actuated[sn].stage) == 0,
		"with no one waiting it rests in green")
	# Rest it on the north-south phase, then send a car east-west: the light
	# must turn for it soon.
	var ew: int = sj.phases[0].ways.keys()[0]
	sm.traffic.actuated[sn] = {"ph": 1, "stage": 0, "t": 0.0}
	_check(sm.traffic.light(sn, ew) == TrafficSim.Light.RED, "east-west starts on red")
	var sid := sm.traffic.dispatch({"ref": "edge", "pos": Vector3(-290, 0, 0)}, {"ref": "edge", "pos": Vector3(290, 0, 0)}, "commute")
	_check(sid != -1, "a car sets off east toward the light")
	var swi := ew
	var sgreen := -1.0
	for i in 900:
		sm.tick()
		if sm.traffic.light(sn, swi) == TrafficSim.Light.GREEN:
			sgreen = i * TrafficSim.DT
			break
	_check(sgreen >= 0.0 and sgreen < 40.0, "the waiting way gets its green soon (%.1f s)" % sgreen)
	var smc := CitySim.new()
	smc.from_dict(JSON.parse_string(JSON.stringify(sm.to_dict())))
	_check(smc.traffic.actuated.has(sn) and int(smc.traffic.actuated[sn].ph) == int(sm.traffic.actuated[sn].ph),
		"a smart light's state survives a save and load")
	print("signal timing: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
