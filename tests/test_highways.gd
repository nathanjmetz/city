extends SceneTree
## The state highways around Marion (Highways): scenery until a town joins
## one, then a STATE_HWY road of the town's own where it runs. I-69 is
## painted but can't be joined.

var _failed := 0
## Open farmland miles from any state road.
const FAR := Vector2(-6000.0, -12000.0)


func _init() -> void:
	_check(Highways.all().size() >= 8, "Grant County's state roads, US 35 and I-69 are laid out (%d routes)" % Highways.all().size())
	_check(Highways.texture() != null, "the ground has the highways' distance field to paint")
	var names := {}
	for r in Highways.all():
		names[r.name] = true
	_check(names.has("State Road 18") and names.has("State Road 9") and names.has("U.S. Route 35")
		and names.has("Interstate 69"), "named the Indiana way (%s)" % str(names.keys()))
	# I-69 has no crossings at grade: nothing finds it to join.
	var interstate := -1
	for i in Highways.all().size():
		if Highways.all()[i].limited:
			interstate = i
	var mid := Highways.point(interstate, Highways.length(interstate) * 0.5) if interstate >= 0 else Vector2.ZERO
	var found := Highways.near(mid.x, mid.y, 5.0)
	_check(interstate >= 0 and Highways.distance(mid.x, mid.y) < 2.0
		and (found.is_empty() or Highways.all()[found.route].limited == false),
		"I-69 is painted, but towns can't join it")
	# The field agrees with the routes it was made from.
	var worst := 0.0
	for i in Highways.all().size():
		for k in range(1, 20):
			var p := Highways.point(i, Highways.length(i) * k / 20.0)
			if absf(p.x - Terrain.CENTRE.x) < 18000.0 and absf(p.y - Terrain.CENTRE.y) < 18000.0:
				worst = maxf(worst, Highways.distance(p.x, p.y))
	_check(worst < 1.5, "the painted road runs down its route (off by %.2f m at worst)" % worst)
	_check(Highways.distance(FAR.x, FAR.y) > 100.0, "and nowhere else")
	var spot := _dry_spot()
	_check(not spot.is_empty(), "found a stretch of highway on dry land")
	if spot.is_empty():
		_finish()
		return
	var route: int = spot.route
	var along: float = spot.along
	var sim := CitySim.new()
	var o := sim.terrain_offset
	var on := Highways.point(route, along) - o
	var t := (Highways.point(route, along + 10.0) - Highways.point(route, along - 10.0)).normalized()
	var side := Vector2(-t.y, t.x)
	_check(Highways.clears(on.x + o.x, on.y + o.y) and not Highways.clears(on.x + o.x + side.x * 40.0, on.y + o.y + side.y * 40.0),
		"trees keep off the road and its right of way, not the field beside it")

	# A street drawn across the highway joins it to town.
	var money := sim.economy.money
	var a := on + side * 150.0
	var b := on - side * 150.0
	var ok := sim.apply({"type": "build_road", "start": [a.x, a.y], "ctrl": [on.x, on.y], "end": [b.x, b.y],
		"road": RoadStyle.Type.STREET, "join": true})
	_check(ok, "a street can be drawn across the highway")
	var hw := _highway(sim)
	var length := 0.0
	var off := 0.0
	for c in hw:
		length += c[0].distance_to(c[2])
		for q in [c[0], c[2]]:
			off = maxf(off, Highways.distance(q.x + o.x, q.z + o.y))
	_check(length > 2000.0, "the town takes on a mile of state highway each way (%d m)" % length)
	_check(off < 2.0, "laid right where the highway runs (off by %.2f m)" % off)
	var named := false
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.STATE_HWY:
			named = named or sim.streets.name_of(id) == Highways.all()[route].name
	_check(named, "it keeps its name, %s" % Highways.all()[route].name)
	var street := Economy.road_cost([Vector3(a.x, 0, a.y), Vector3(on.x, 0, on.y), Vector3(b.x, 0, b.y)],
		RoadStyle.Type.STREET)
	_check(absf(money - street - sim.economy.money) < 1.0, "the state hands it over free")
	var node := sim.network.find_node_near(Vector3(on.x, 0, on.y), 3.0)
	var types := {}
	for id in sim.network.segments_at(node):
		types[sim.network.segments[id].type] = true
	_check(types.has(RoadStyle.Type.STATE_HWY) and types.has(RoadStyle.Type.STREET),
		"the street meets the highway at a crossroads")

	# Another street across the joined stretch lays nothing more.
	var on2 := Highways.point(route, along + 300.0) - o
	var t2 := (Highways.point(route, along + 310.0) - Highways.point(route, along + 290.0)).normalized()
	var s2 := Vector2(-t2.y, t2.x)
	var a2 := on2 + s2 * 120.0
	var b2 := on2 - s2 * 120.0
	sim.apply({"type": "build_road", "start": [a2.x, a2.y], "ctrl": [on2.x, on2.y], "end": [b2.x, b2.y],
		"road": RoadStyle.Type.STREET, "join": true})
	var again := 0.0
	for c in _highway(sim):
		again += c[0].distance_to(c[2])
	_check(absf(again - length) < 30.0, "a highway is never laid twice (%d m, was %d m)" % [again, length])

	# A street ending just short of the highway is taken on to it.
	var lone := CitySim.new()
	var near := on + side * 10.0
	var far := on + side * 200.0
	lone.apply({"type": "build_road", "start": [far.x, far.y], "ctrl": [(far.x + near.x) * 0.5, (far.y + near.y) * 0.5],
		"end": [near.x, near.y], "road": RoadStyle.Type.STREET, "join": true})
	_check(not _highway(lone).is_empty(), "a street ending 10 m short still joins the highway")
	var plain := CitySim.new()
	plain.apply({"type": "build_road", "start": [a.x, a.y], "ctrl": [on.x, on.y], "end": [b.x, b.y],
		"road": RoadStyle.Type.STREET})
	_check(_highway(plain).is_empty(), "building a road alone never joins one (the road tool asks)")
	# Zoned along a street that crosses it, no lot is platted on the highway.
	for id in plain.network.segments:
		for sd in [-1, 1]:
			plain.apply({"type": "zone_frontage", "seg": id, "side": sd, "zone": ZoneMap.Zone.RESIDENTIAL})
	plain._refresh()
	var nearest := INF
	for key in plain.lots:
		var lp: Vector3 = plain.lots[key].pos
		nearest = minf(nearest, Highways.distance(lp.x + o.x, lp.z + o.y))
	_check(not plain.lots.is_empty() and nearest >= Highways.HALF_CLEAR,
		"lots stay off the highway's right of way (%d lots, nearest %.0f m)" % [plain.lots.size(), nearest])
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(_highway(copy).size() == _highway(sim).size(), "the joined highway is saved with the town")
	_shared_street()
	_finish()


## Brawn (2026-10-24): state roads that leave another in town start on it,
## as SR 61 and SR 56 leave SR 57 in Petersburg, not as spurs ending beside
## it that the town joins as two roads kinking into each other.
func _shared_street() -> void:
	var loose := 0
	for i in Highways.all().size():
		for along in [0.0, Highways.length(i)]:
			var p := Highways.point(i, along)
			if absf(p.x) > 15000.0 or absf(p.y) > 15000.0:
				continue  # off the map: a region link
			var on := false
			for k in Highways.all().size():
				on = on or (k != i and not Highways.near(p.x, p.y, 2.0, k).is_empty())
			if not on:
				loose += 1
				print("  loose end of ", Highways.all()[i].name, " at ", p)
	_check(loose == 0, "every state road on the map starts and ends on another or off the map")


## A point along a highway, near the middle of the map, with dry land a
## mile each way: {route, along}, or {}.
func _dry_spot() -> Dictionary:
	for i in Highways.all().size():
		if Highways.all()[i].limited:
			continue
		var total := Highways.length(i)
		var s := 2000.0
		while s < total - 2000.0:
			var dry := true
			for k in range(-12, 13):
				var p := Highways.point(i, s + k * 120.0)
				dry = dry and absf(p.x) < 9000.0 and absf(p.y) < 9000.0 and Terrain.water(p.x, p.y) < 0.02 \
					and not Backdrop.inside(p, 300.0)
			if dry:
				return {"route": i, "along": s}
			s += 500.0
	return {}


func _highway(sim: CitySim) -> Array:
	var out := []
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.STATE_HWY:
			out.append(sim.network.curve_of(id))
	return out


func _finish() -> void:
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
