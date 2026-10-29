extends SceneTree
## Run: godot --headless -s tests/test_patrols.gd
## Police patrol beats (Brawn, 2026-10-29, after Caesar III): a station
## keeps cruisers out each shift on real trips down the streets that have
## gone longest without a car; a street counts as patrolled for a day.

var _failed := false


func _init() -> void:
	var sim := _town()
	sim.simulate_traffic = true
	var sid := _station(sim)
	_check(sid != -1, "a police station")
	_check(Patrols.cars(sim, sid) == Balance.PATROL_CARS, "two cars a shift at Standard")
	# A new station sends its cars out on the hour.
	for i in 240:
		sim.tick()
	_check(sim.patrols.out(sid) == Balance.PATROL_CARS, "both cruisers are out (%d)" % sim.patrols.out(sid))
	var police := 0
	for c in sim.traffic.cars + sim.traffic.flowing:
		if c.get("purpose", "") == "police":
			police += 1
	_check(police >= 1, "on the road as police cars (%d)" % police)
	for i in 900:
		sim.tick()
	_check(not sim.patrols.beats.is_empty(), "streets get patrolled (%d)" % sim.patrols.beats.size())
	var seg: int = sim.patrols.beats.keys()[0] if not sim.patrols.beats.is_empty() else -1
	_check(sim.patrols.patrolled(sim, seg) and sim.patrols.freshness(sim, seg) > 0.5, "a street just driven is fresh")
	# Saved and loaded, the beat carries on.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.patrols.beats.size() == sim.patrols.beats.size() and copy.patrols.trips.size() == sim.patrols.trips.size(),
		"patrols save and load")
	# Lean funding keeps one car out.
	sim.apply({"type": "policy", "scope": "service:%d" % sid, "slider": "funding", "step": 0})
	_check(Patrols.cars(sim, sid) == 1, "Lean: one car")
	_check(Patrols.cars(sim, sid) <= Balance.PATROL_CARS, "never more than Standard when Lean")

	# With cars switched off, each shift still covers its beat.
	var off := _town()
	off.simulate_traffic = false
	_station(off)
	while (Mail.minute_of_day(off.tick_count) - Balance.PATROL_FIRST_SHIFT * 60) % (Balance.PATROL_SHIFT_HOURS * 60) != 0 \
			or off.tick_count == 0:
		off.tick()
	_check(not off.patrols.beats.is_empty(), "offstage: the shift's streets are patrolled (%d)" % off.patrols.beats.size())
	off.tick_count += Balance.PATROL_FRESH_TICKS + 5
	var any_seg: int = off.patrols.beats.keys()[0] if not off.patrols.beats.is_empty() else -1
	_check(not off.patrols.patrolled(off, any_seg), "a week later with nobody by, it isn't")

	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## A main street lined with homes, 1.2 km long.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.charter.reached["town"] = 0
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -300], "end": [0, -600]})
	for x in range(-550, 551, 20):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for z in range(-550, -40, 20):
		sim.apply({"type": "paint_zone", "center": [25, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	return sim


func _station(sim: CitySim) -> int:
	var site := Services.site_near(sim.network, Services.Kind.POLICE, Vector3(-300, 0, -40))
	if site.is_empty() or not sim.apply({"type": "place_service", "kind": Services.Kind.POLICE,
			"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
		return -1
	var sid: int = sim.services.buildings.keys()[0]
	sim.construction.sites.erase("svc:%d" % sid)  # built
	sim.update_stats()
	return sid


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
