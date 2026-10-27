extends SceneTree
## Every parking space stays held by the vehicles a loaded copy would say
## hold it (a loaded copy works it out from the saved vehicles) when a road
## is bulldozed or built: cars that can't find their way to a lot any more
## let go of the stalls held for them there, and a vehicle that has nowhere
## to move to when its lot is laid out afresh keeps the stall it is in.
## Run: godot --headless -s tests/test_parking_holds.gd

const TownLife := preload("res://tests/test_town_life.gd")

## The spur out to the lot, west of the grid: in from the grid's corner
## road, a long piece, and a short last piece the lot fronts (too short
## to park along).
const SPUR := [[-280.0, -280.0], [-400.0, -280.0], [-540.0, -280.0], [-560.0, -280.0]]


func _init() -> void:
	var sim := CitySim.new()
	# On dry, open farmland south of Sweetser, as in test_parking.
	sim.terrain_offset = Vector2(0, 1500)
	PerfTown.build(sim, "small")
	for i in 200:
		sim.tick()
	var lot := _spur_lot(sim)
	_check(lot != "", "a small lot at the end of a dead-end spur")
	if lot != "":
		_cut_off(sim, lot)
		_stuck_in_place(sim, lot)
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Builds the spur and a small lot on its last piece. Returns its ref.
func _spur_lot(sim: CitySim) -> String:
	for i in SPUR.size() - 1:
		var a: Array = SPUR[i]
		var b: Array = SPUR[i + 1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})
	var t: TrafficSim = sim.traffic
	t._rebuild()
	for at in [Vector3(-550, 0, -260), Vector3(-550, 0, -300), Vector3(-555, 0, -260), Vector3(-555, 0, -300)]:
		var site := Services.site_near(sim.network, Services.Kind.PARKING_SMALL, at)
		if site.is_empty():
			continue
		if sim.apply({"type": "place_service", "kind": Services.Kind.PARKING_SMALL, "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z]}):
			var id: int = sim.services.buildings.keys().max()
			sim.construction.sites.erase("svc:%d" % id)
			if t.place("svc:%d" % id).get("stop", {}).get("seg", -1) == _spur_seg(sim, SPUR.size() - 2):
				return "svc:%d" % id
	return ""


## The road segment under the spur's piece `k` (0: in from the grid).
func _spur_seg(sim: CitySim, k: int) -> int:
	var a: Array = SPUR[k]
	var b: Array = SPUR[k + 1]
	var mid := Vector3((a[0] + b[0]) * 0.5, 0, (a[1] + b[1]) * 0.5)
	var near := RoadIndex.segment_near(sim.network, mid, 5.0)
	return -1 if near.is_empty() else int(near.seg)


## Cars on their way to the lot when the only road to it is bulldozed: one
## already past the cut drives on to it, and the ones behind it give up and
## let go of the stalls held for them. Found 2026-10-27 (review of #623):
## they kept them, live, while a loaded copy, without those cars, had them
## free.
func _cut_off(sim: CitySim, lot: String) -> void:
	var t: TrafficSim = sim.traffic
	var sent := 0
	for car in t.parked.duplicate():
		if sent >= 14 or car.len > 6.5 or car.has("pending") or not str(car.at_place).begins_with("lot:"):
			continue
		if t._send(car, lot, "shopping", {}, {"stay": 3000}):
			sent += 1
	var spur := []
	for k in SPUR.size() - 1:
		spur.append(_spur_seg(sim, k))
	# Until one car is out on the spur past where it will be cut and others
	# are still in town (each holding a stall at the lot).
	var ready := false
	for i in 3000:
		sim.tick()
		var past := 0
		var behind := 0
		for car in t.cars:
			if car.get("to_place", "") != lot or car.j != null:
				continue
			var sg: int = t.ways[car.route[car.leg]].seg
			if sg == spur[1] or sg == spur[2]:
				past += 1
			elif sg != spur[0]:
				behind += 1
		if past > 0 and behind > 0:
			ready = true
			break
	_check(ready, "a car is past the cut while others are still on their way (%d sent)" % sent)
	if not ready:
		return
	var before := t.failed.size()
	_check(sim.apply({"type": "remove_road", "seg": spur[0]}), "the road in to the lot is bulldozed")
	t._rebuild()
	_check(t.failed.size() > before, "the cars cut off give up (%d)" % (t.failed.size() - before))
	_holds(t, "after the only road in to a lot is bulldozed")


## A vehicle in a stall that no longer lines up with it (as if its lot were
## laid out afresh under it, the way a shop's dock can turn into a stall),
## with no other space for it and no kerb to move to: when a road is built
## it stays put and keeps the stall. Found 2026-10-27 (review of #623): it
## let go of the stall first, so the live town had it free and a loaded
## copy had it held.
func _stuck_in_place(sim: CitySim, lot: String) -> void:
	var t: TrafficSim = sim.traffic
	var pl := t.place(lot)
	_check(t._curb_line(pl.stop).is_empty(), "the lot's piece of road is too short to park along")
	# A box truck in one of its stalls, a metre off it.
	var truck := t._make_vehicle("box_truck", -1, lot)
	var k := t._reserve(pl, truck.id, false)
	_check(truck.len > 6.5 and k >= 0, "a box truck has a stall in the lot (%d)" % k)
	if k < 0:
		return
	t._park(truck, pl, k)
	truck.pos += Vector3(-truck.face.z, 0.0, truck.face.x) * 1.0
	var pos: Vector3 = truck.pos
	_check(sim.apply({"type": "build_road", "start": [280, 280], "ctrl": [330, 280], "end": [380, 280]}),
		"a road is built across town")
	t._rebuild()
	_check(truck.spot == k and truck.pos == pos, "the truck stays where it is (stall %d, it was %d)" % [truck.spot, k])
	_holds(t, "after a road is built")


func _holds(t: TrafficSim, when: String) -> void:
	var bad: Array = TownLife.hold_gaps(t)
	_check(not t._places.is_empty() and bad.is_empty(),
		"%s every parking space is held as a loaded copy would hold it (%d of %d places differ%s)" % [
			when, bad.size(), t._places.size(), (": " + bad[0]) if not bad.is_empty() else ""])


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
