extends SceneTree
## A town of about 1,500 people, as a playtester grew one (look check,
## 2026-10-25): traffic keeps moving, the county's ambulances come in ones
## and twos, people walk on sidewalks and shoulders (never stale ones),
## problem badges merge instead of piling up, and two copies of the town
## agree after a save and load.
## Run: godot --headless -s tests/test_town_life.gd

## No vehicle on the road stands still longer than this, in ticks (each is
## 0.1 s of driving: 5 minutes behind the wheel).
const STUCK_TICKS := 3000


var _sim: CitySim
var _frames := 0


func _initialize() -> void:
	_check_walk_offsets()
	_sim = _town()
	_check_stale_walks(_sim)
	_grow(_sim)


## The badge checks need a camera in the running tree, a frame in.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_check_alerts(_sim)
	_check_copies(_sim)
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
	return true


## The playtest town: the county highway, a road in, a 6 x 5 grid of 120 m
## blocks tied to the highway twice, homes and shops, a builder's yard,
## power, water, police and a clinic, but no hospital.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	var b := 120.0
	var g0 := Vector3(40, 0, 60)
	sim.apply({"type": "build_grid", "a": [g0.x, g0.z], "b": [g0.x + 6 * b, g0.z], "c": [g0.x, g0.z + 5 * b],
		"block": b, "join": true})
	sim.apply({"type": "build_road", "start": [g0.x + 2 * b, g0.z], "ctrl": [g0.x + 2 * b, 30], "end": [g0.x + 2 * b, 0],
		"join": true})
	var n := 0
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var c: Array = sim.network.curve_of(id)
		if RoadNetwork.bezier(c[0], c[1], c[2], 0.5).z < 20.0:
			continue
		var zone := ZoneMap.Zone.COMMERCIAL if n % 5 == 0 else ZoneMap.Zone.RESIDENTIAL
		if sim.apply({"type": "zone_frontage", "seg": id, "side": 1, "zone": zone, "both": true}):
			n += 1
	var centre := g0 + Vector3(1.5 * b, 0, 1.5 * b)
	for kind in [Services.Kind.BUILDER_YARD, Services.Kind.SUBSTATION, Services.Kind.WATER_TOWER,
			Services.Kind.SCHOOL, Services.Kind.FIRE, Services.Kind.POLICE, Services.Kind.CLINIC]:
		var site := Services.site_near(sim.network, kind, centre + Vector3(30.0 * kind, 0, 0))
		if not site.is_empty():
			sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	return sim


## People walk beside a road on its sidewalk, or on its shoulder where it
## has none: inside the road's own land, not out on the lawns.
func _check_walk_offsets() -> void:
	var ok := true
	var shoulder_ok := true
	for type in RoadStyle.TYPES.size():
		if RoadStyle.is_freeway(type) or not RoadStyle.TYPES[type].lots:
			continue
		var off := TrafficSim.walk_offset(type)
		var hw := RoadStyle.half_width(type)
		if off <= 0.5 or off > RoadStyle.right_of_way_half(type):
			ok = false
			print("  %s walks %.2f m out (right of way %.2f)" % [RoadStyle.TYPES[type].name, off, RoadStyle.right_of_way_half(type)])
		if not RoadStyle.TYPES[type].get("walk", true) and off > hw + 1.8:
			shoulder_ok = false
	_check(ok, "every street's walkers stay inside its right of way")
	_check(shoulder_ok, "on a road with no sidewalks they walk its shoulder (within the gravel strip)")
	var sh := -1
	for type in RoadStyle.TYPES.size():
		if RoadStyle.TYPES[type].get("shoulder", 0.0) > 0.0 and RoadStyle.TYPES[type].get("lots", false):
			sh = type
	if sh >= 0:
		var hw := RoadStyle.half_width(sh)
		var off := TrafficSim.walk_offset(sh)
		_check(off < hw and off > hw - float(RoadStyle.TYPES[sh].shoulder),
			"along the state highway they walk its paved shoulder (%.1f m out, pavement to %.1f)" % [off, hw])


## A road built while people are setting off splits a street: nobody plans
## a walk on sidewalks that are gone (the desktop playtest hit "Out of
## bounds get index" in TrafficSim._seg_node three times).
func _check_stale_walks(sim: CitySim) -> void:
	for i in 2500:
		sim.tick()
	var walked := sim.traffic.walkers.size()
	# A new street across the middle of a block, joined to the grid, every
	# few ticks, as a player drawing roads at speed does.
	var splits := 0
	for k in 6:
		var x := 40.0 + 60.0 + 120.0 * k
		var before := sim.network.segments.size()
		if sim.apply({"type": "build_road", "start": [x, 60.0], "ctrl": [x, 120.0], "end": [x, 180.0], "join": true}):
			splits += 1
		_check_rings(sim, before)
		for t in 3:
			sim.tick()
	_check(walked > 0 and splits > 0, "people were out walking when new streets split the blocks (%d walkers, %d streets)" % [walked, splits])
	var bad := 0
	for n in sim.traffic._rings:
		for e in sim.traffic._rings[n]:
			if int(e[0]) >= 0 and not sim.network.segments.has(int(e[0])):
				bad += 1
	_check(bad == 0, "every sidewalk corner the walkers know is on a street that's there (%d gone)" % bad)


func _check_rings(sim: CitySim, _before: int) -> void:
	# Plan a walk straight away, before the traffic has ticked: it must see
	# the new streets.
	var homes := []
	for pid in sim.people.people:
		if sim.people.people[pid].at == "":
			homes.append(pid)
	homes.sort()
	var tried := 0
	for pid in homes.slice(0, 20):
		var p: Dictionary = sim.people.people[pid]
		for ref in ["lot:" + str(sim.lots.keys()[(pid * 7) % sim.lots.size()])]:
			if ref != "lot:" + p.home and sim.traffic.place(ref).size() > 0:
				sim.traffic.go(pid, ref, "visit", 30)
				tried += 1
	_tried += tried
	for n in sim.traffic._rings:
		for e in sim.traffic._rings[n]:
			if int(e[0]) >= 0 and not sim.network.segments.has(int(e[0])):
				_stale += 1


var _tried := 0
var _stale := 0


## Grows the town to about 1,500 people and watches the roads.
func _grow(sim: CitySim) -> void:
	var still := {}  # car id -> [position, ticks it hasn't moved]
	var worst := 0
	var worst_car := ""
	var most_amb := 0
	var flows := []
	for i in 33000:
		sim.tick()
		if i % 100 != 0:
			continue
		var amb := 0
		for car in sim.traffic.cars:
			var at: Vector3 = sim.traffic.car_pose(car)[0]
			var s = still.get(car.id)
			if s != null and (s[0] as Vector3).distance_to(at) < 1.0:
				s[1] += 100
				if s[1] > worst:
					worst = s[1]
					worst_car = "%s on a %s trip at %s" % [TrafficSim.vehicle_kind(car), car.purpose, str(at)]
			else:
				still[car.id] = [at, 0]
			if car.purpose == "medical" and car.kind == "ambulance":
				amb += 1
		most_amb = maxi(most_amb, amb)
		if i >= 23000:
			flows.append(sim.traffic.flow)
	var pop: int = sim.stats.population
	_check(pop >= 1400, "the town grows to about 1,500 people (%d)" % pop)
	_check(worst < STUCK_TICKS, "no vehicle stands still for 5 minutes (longest %d ticks: %s)" % [worst, worst_car])
	_check(sim.healthcare.county_calls > 0, "the county ambulance answers calls (%d)" % sim.healthcare.county_calls)
	_check(most_amb <= Balance.EMS_COUNTY_RIGS,
		"with no hospital, at most the county's %d rigs are out at once (%d; there were 80 nose to tail)" % [Balance.EMS_COUNTY_RIGS, most_amb])
	_check(sim.healthcare.mutual_aid > 0, "calls while they're out go to the next county (%d)" % sim.healthcare.mutual_aid)
	var avg := 0.0
	for f in flows:
		avg += f
	avg /= maxf(flows.size(), 1.0)
	_check(avg >= 0.92, "traffic flows freely in a town this size (%d%% flow; it was 79-89%%)" % roundi(avg * 100.0))
	_check(_tried > 0 and _stale == 0, "walks planned right after each new street use the new sidewalks (%d walks, %d stale corners)" % [_tried, _stale])


## Problem badges merge on screen: one per area from far off, one per
## house up close, never more than MAX_BADGES.
func _check_alerts(_s: CitySim) -> void:
	# 300 homes with no water over a square kilometre.
	var alerts := []
	for i in 300:
		alerts.append([Vector3(float(i % 20) * 50.0, LotAlerts.HEIGHT, float(i / 20) * 66.0), "water" if i % 7 else "power"])
	_check(LotAlerts.group(alerts, null, Vector2(1600, 900)).size() <= LotAlerts.MAX_BADGES,
		"at most %d badges show" % LotAlerts.MAX_BADGES)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var size := root.get_visible_rect().size
	var mid := Vector3(475.0, 0.0, 495.0)
	# The county view, 3 km out.
	cam.look_at_from_position(mid + Vector3(0, 2600, 1500), mid)
	var far := LotAlerts.group(alerts, cam, size)
	var total := 0
	for g in far:
		total += g[2]
	_check(far.size() <= 8 and total == 300, "from 3 km the town is a handful of badges (%d, standing for %d homes)" % [far.size(), total])
	var any_power := false
	for g in far:
		any_power = any_power or g[1] == "power"
	_check(any_power, "a group shows power if any home in it lacks power")
	# Up close over one block: every house its own badge.
	cam.look_at_from_position(Vector3(100, 90, 160), Vector3(100, 0, 100))
	var near := LotAlerts.group(alerts, cam, size)
	var singles := 0
	for g in near:
		singles += 1 if g[2] == 1 else 0
	_check(near.size() >= 4 and singles * 2 >= near.size(), "up close each house has its own (%d badges, %d single)" % [near.size(), singles])
	# Low over the street toward the horizon: the far ones merge, no smear.
	cam.look_at_from_position(Vector3(-60, 30, 500), Vector3(1000, 0, 500))
	var low := LotAlerts.group(alerts, cam, size)
	var overlap := 0
	for i in low.size():
		for j in range(i + 1, low.size()):
			var a := cam.unproject_position(low[i][0])
			var b := cam.unproject_position(low[j][0])
			if a.distance_to(b) < LotAlerts.MERGE_PX * size.y / 900.0 * 0.5:
				overlap += 1
	_check(overlap <= 2 and low.size() <= LotAlerts.MAX_BADGES, "low over a street the badges don't pile into a smear (%d, %d overlapping)" % [low.size(), overlap])
	cam.queue_free()


## Two copies of the town, saved and loaded, agree tick for tick, walkers,
## ambulances and all.
func _check_copies(sim: CitySim) -> void:
	var snapshot = JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true))
	var a := CitySim.new()
	a.from_dict(snapshot)
	var b := CitySim.new()
	b.from_dict(snapshot)
	for i in 600:
		a.tick()
		b.tick()
		if i == 200:
			# A road built in both, mid-run, with people setting off.
			for c in [a, b]:
				c.apply({"type": "build_road", "start": [400.0, 300.0], "ctrl": [430.0, 330.0], "end": [460.0, 360.0], "join": true})
	var ta := JSON.stringify(a.traffic.to_dict())
	var tb := JSON.stringify(b.traffic.to_dict())
	_check(ta == tb, "the copies' traffic and walkers agree after a save and load")
	_check(JSON.stringify(a.healthcare.to_dict()) == JSON.stringify(b.healthcare.to_dict()), "and their ambulance calls")
	_check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "and the whole town")


var _failed := false


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
