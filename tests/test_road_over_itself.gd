extends SceneTree
## Run: godot --headless -s tests/test_road_over_itself.gd
## A street drawn again along a street already there changes nothing, and
## a command that does change the roads always says so (critic 2026-10-27:
## a street drawn along the town's first road, stopping partway, cut that
## road in two while the game said nothing changed; walkers and services
## kept the piece that was gone, and thousands of script errors followed).

var _failed := false


func _init() -> void:
	var sim := _town()
	_check(sim.buildings.size() > 10, "a small town grew first (%d buildings)" % sim.buildings.size())
	_check(sim.traffic.walkers.size() + sim.traffic.cars.size() > 0,
		"with people about (%d walking, %d driving)" % [sim.traffic.walkers.size(), sim.traffic.cars.size()])
	# A street of the grid, and a street drawn along its middle half.
	var seg := _straight(sim)
	_check(seg != -1, "found a straight street to draw along")
	if seg == -1:
		quit(1)
		return
	var c := sim.network.curve_of(seg)
	var a := RoadNetwork.bezier(c[0], c[1], c[2], 0.25)
	var b := RoadNetwork.bezier(c[0], c[1], c[2], 0.75)
	var segs := sim.network.segments.size()
	var rev := sim.network.revision
	var money := sim.economy.money
	var type := int(sim.network.segments[seg].type)
	var ok := sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [(a.x + b.x) * 0.5, (a.z + b.z) * 0.5],
		"end": [b.x, b.z], "road": type, "join": true})
	_check(not ok, "a street drawn along a street of its own type changes nothing")
	_check(sim.network.segments.size() == segs and sim.network.revision == rev and sim.network.segments.has(seg),
		"and the street isn't cut (%d pieces, were %d)" % [sim.network.segments.size(), segs])
	_check(sim.economy.money == money, "and costs nothing")
	# The town runs on (a script error here fails the test in CI).
	for i in 400:
		sim.tick()
	_check(_lots_on_roads(sim), "every lot still fronts a road that is there")
	# Drawn as a bigger road, that stretch is upgraded: the street is cut
	# where the new road ends, and the command says it changed.
	var big := RoadStyle.Type.AVENUE if type != RoadStyle.Type.AVENUE else RoadStyle.Type.STREET
	segs = sim.network.segments.size()
	ok = sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [(a.x + b.x) * 0.5, (a.z + b.z) * 0.5],
		"end": [b.x, b.z], "road": big, "join": true})
	_check(ok, "drawn as another type, it's accepted")
	_check(sim.network.segments.size() == segs + 2 and not sim.network.segments.has(seg),
		"the old street is cut at both ends of the new road (%d pieces, were %d)" % [sim.network.segments.size(), segs])
	var hit := RoadIndex.segment_near(sim.network, a.lerp(b, 0.5), 2.0, RoadNetwork.SAME_LEVEL)
	_check(not hit.is_empty() and int(sim.network.segments[hit.seg].type) == big, "and the stretch it covers takes the new type")
	for i in 400:
		sim.tick()
	_check(_lots_on_roads(sim), "every lot still fronts a road that is there, after the upgrade")
	_undo_retype(sim)
	_cut_only(sim)
	if _failed:
		print("FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)


## Undone right after a partial retype, the street is whole again, and no
## lot is left on a piece of it before the town runs another tick
## (reviewer 2026-10-27: the undo left that to the next tick).
func _undo_retype(sim: CitySim) -> void:
	var seg := _straight(sim)
	_check(seg != -1, "found another straight street, to upgrade and undo")
	if seg == -1:
		return
	var c := sim.network.curve_of(seg)
	var a := RoadNetwork.bezier(c[0], c[1], c[2], 0.25)
	var b := RoadNetwork.bezier(c[0], c[1], c[2], 0.75)
	var big := _other(int(sim.network.segments[seg].type))
	var before := sim.network.segments.keys()
	var ok := sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [(a.x + b.x) * 0.5, (a.z + b.z) * 0.5],
		"end": [b.x, b.z], "road": big, "join": true})
	_check(ok and not sim.network.segments.has(seg), "a stretch of it drawn as another type cuts it")
	var on_piece := 0
	for key in sim.lots:
		if sim.lots[key].has("seg") and not before.has(int(sim.lots[key].seg)):
			on_piece += 1
	_check(on_piece > 0, "and lots front its new pieces (%d)" % on_piece)
	ok = sim.apply({"type": "undo"})
	_check(ok and sim.network.segments.has(seg) and sim.network.segments.size() == before.size(),
		"undone, the street is whole again")
	_check(_lots_on_roads(sim), "and every lot fronts a road that is there, before another tick")


## A cut alone is a change: with no money for the retype, drawing over the
## middle of a street still cuts it at both ends, and the roads say they
## changed, so everything on them catches up (reviewer 2026-10-27: the cut
## never moved `revision` or fired `changed`, so lots kept the gone piece).
## Play can't reach this today (road_problem wants the whole road's money).
func _cut_only(sim: CitySim) -> void:
	var seg := _straight(sim)
	_check(seg != -1, "found a third straight street, to cut")
	if seg == -1:
		return
	var c := sim.network.curve_of(seg)
	var a := RoadNetwork.bezier(c[0], c[1], c[2], 0.25)
	var b := RoadNetwork.bezier(c[0], c[1], c[2], 0.75)
	var big := _other(int(sim.network.segments[seg].type))
	# The town has caught up with everything before, so what's checked
	# below comes from the cut alone.
	sim.tick()
	_check(not sim._roads_moved and not sim._lots_light, "the town has caught up first")
	var segs := sim.network.segments.size()
	var rev := sim.network.revision
	var fired := [0]
	var count := func(): fired[0] += 1
	sim.network.changed.connect(count)
	var money := sim.economy.money
	sim.economy.money = 0
	var ok := sim._build_over([a, a.lerp(b, 0.5), b], big)
	sim.economy.money = money
	sim.network.changed.disconnect(count)
	_check(ok and sim.network.segments.size() == segs + 2 and not sim.network.segments.has(seg),
		"with no money, the street is still cut in three (%d pieces, were %d)" % [sim.network.segments.size(), segs])
	_check(sim.network.revision != rev, "and the roads' revision moves")
	_check(fired[0] == 1, "and `changed` fires once (%d)" % fired[0])
	_check(sim._roads_moved, "so the world will make way for the cut roads")
	sim._refresh()
	_check(_lots_on_roads(sim), "and after the refresh every lot fronts a road that is there")


## A type to draw over a street of this type.
func _other(type: int) -> int:
	return RoadStyle.Type.AVENUE if type != RoadStyle.Type.AVENUE else RoadStyle.Type.STREET


## A grid of streets, zoned, with power and water, grown for a while.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = 11
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [480, 0], "c": [0, 360], "block": 120.0})
	var n := 0
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var zone := ZoneMap.Zone.COMMERCIAL if n % 5 == 0 else ZoneMap.Zone.RESIDENTIAL
		sim.apply({"type": "zone_frontage", "seg": id, "side": 1, "zone": zone, "both": true})
		n += 1
	for kind in [Services.Kind.SUBSTATION, Services.Kind.WATER_TOWER]:
		for k in 8:
			var site := Services.site_near(sim.network, kind, Vector3(60.0 + 120.0 * k, 0, 60.0 + 30.0 * k))
			if not site.is_empty() and sim.apply({"type": "place_service", "kind": kind,
					"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
				break
	for i in 1500:
		sim.tick()
	return sim


## A straight street of the grid at least 100 m long, or -1.
func _straight(sim: CitySim) -> int:
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var c := sim.network.curve_of(id)
		var len: float = c[0].distance_to(c[2])
		var mid: Vector3 = (c[0] + c[2]) * 0.5
		if len >= 100.0 and (c[1] as Vector3).distance_to(mid) < 0.5 and not RoadStyle.is_ring(int(sim.network.segments[id].type)):
			return id
	return -1


func _lots_on_roads(sim: CitySim) -> bool:
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.has("seg") and not sim.network.segments.has(int(lot.seg)):
			print("  lot ", key, " on gone road ", lot.seg)
			return false
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
	else:
		print("  ok: ", what)
