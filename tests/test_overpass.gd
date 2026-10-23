extends SceneTree
## A raised road drawn across a road climbs over it (Brawn, 2026-10-23):
## real clearance over the road it crosses, approaches within the road's
## grade, no junction with the road below, and a road at ground level still
## meets what it crosses in a junction.
## Run: godot --headless -s tests/test_overpass.gd

var _fails := 0


func _init() -> void:
	_over_a_street()
	_too_short()
	_ground_still_joins()
	_done()


func _sim() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	# A street running north-south through the middle.
	sim.apply({"type": "build_road", "start": [0, -400], "ctrl": [0, 0], "end": [0, 400], "road": 0})
	return sim


func _over_a_street() -> void:
	var sim := _sim()
	var nodes := sim.network.nodes.size()
	# An avenue from ground to ground, east-west, raised.
	var ok := sim.apply({"type": "build_road", "start": [-300, 0, 0], "ctrl": [0, 0, 0], "end": [300, 0, 0],
		"road": 1, "over": true, "join": true})
	_check(ok, "a raised avenue across the street is built")
	var top := 0.0
	var steep := 0.0
	var grade := float(RoadStyle.TYPES[1].grade)
	for id in sim.network.segments:
		var c: Array = sim.network.curve_of(id)
		if absf(c[0].x) < 0.5 and absf(c[2].x) < 0.5:
			continue  # the street below
		var flat := Vector2(c[2].x - c[0].x, c[2].z - c[0].z).length()
		steep = maxf(steep, absf(c[2].y - c[0].y) / flat)
		for p in RoadNetwork.sample_curve(c[0], c[1], c[2], 16):
			if absf(p.x) < 6.0:
				top = maxf(top, p.y)
	_check(top >= RoadNetwork.CLEARANCE - 0.01, "the deck clears the street by 16.5 ft plus the deck (%.1f m)" % top)
	_check(steep <= grade + 0.001, "the approaches climb within the avenue's grade (%.3f of %.2f)" % [steep, grade])
	var pieces := 0
	for id in sim.network.segments:
		var c: Array = sim.network.curve_of(id)
		if absf(c[0].x) < 0.5 and absf(c[2].x) < 0.5:
			pieces += 1
	_check(pieces == 1, "no junction with the street below (it is still one piece)")
	var mid := sim.network.find_node_near(Vector3(0, 0, 0), 3.0, RoadNetwork.SAME_LEVEL)
	_check(mid == -1, "no node where the roads cross at ground level")
	_check(sim.network.nodes.size() > nodes + 2, "the overpass is built in pieces (ramp, deck, ramp)")
	# Nothing to cross: one piece, as drawn.
	var before := sim.network.segments.size()
	sim.apply({"type": "build_road", "start": [-300, 0, 600], "ctrl": [0, 0, 600], "end": [300, 0, 600],
		"road": 1, "over": true})
	_check(sim.network.segments.size() == before + 1, "with nothing to cross a raised road is one piece")
	# Saved and loaded, it stays the same.
	var copy := CitySim.new()
	copy.simulate_traffic = false
	copy.from_dict(sim.to_dict())
	_check(copy.network.to_dict() == sim.network.to_dict(), "the overpass saves and loads")


func _too_short() -> void:
	var sim := _sim()
	var plan := Overpass.plan(sim, [Vector3(-30, 0, 0), Vector3(0, 0, 0), Vector3(30, 0, 0)], 1)
	_check(not plan.ok and plan.why.begins_with("Too short"), "too short to climb over says so: " + str(plan.why))
	var before := sim.network.segments.size()
	sim.apply({"type": "build_road", "start": [-30, 0, 0], "ctrl": [0, 0, 0], "end": [30, 0, 0], "road": 1, "over": true})
	_check(sim.network.segments.size() == before, "and isn't built")


func _ground_still_joins() -> void:
	var sim := _sim()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": 1, "join": true})
	var mid := sim.network.find_node_near(Vector3(0, 0, 0), 3.0, RoadNetwork.SAME_LEVEL)
	_check(mid != -1 and sim.network.segments_at(mid).size() == 4, "at ground level the crossing is a junction")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
