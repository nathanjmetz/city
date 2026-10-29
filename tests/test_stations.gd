extends SceneTree
## Fire and police stations grow with their town (Stations): pieces come as
## the town passes each need, paid from the department's fund; a piece that
## needs land grows the lot back from the street onto free land only; the
## pieces lengthen the station's reach and survive a save.

var failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [200, 0], "end": [400, 0]})
	# A street of homes behind, its back lots reaching toward the station.
	sim.apply({"type": "build_road", "start": [0, 105], "ctrl": [200, 105], "end": [400, 105]})
	var back: int = sim.network.find_segment_near(Vector3(200, 0, 105), 5.0).seg
	for side in [-1, 1]:
		sim.apply({"type": "zone_frontage", "seg": back, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.tick()
	var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(120, 0, 30))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a fire station goes in")
	var id: int = sim.services.buildings.keys()[-1]
	var depth0: float = Services.size_of(sim.services.buildings[id]).y
	var front0: Vector3 = sim.services.buildings[id].pos + sim.services.buildings[id].dir * depth0 * 0.5
	# A hamlet: the fund fills, but nothing is needed yet.
	sim.stats.population = 600
	_days(sim, 60)
	_check(sim.stations.built_of(id).is_empty(), "a hamlet's firehouse stays as it is")
	# A town of 2,500: a drill tower behind the station, its lot reaching back.
	sim.stats.population = 2500
	_days(sim, 400)
	var b: Dictionary = sim.services.buildings[id]
	var size: Vector2 = Services.size_of(b)
	_check("drill_tower" in sim.stations.built_of(id), "a growing town's department builds a drill tower (%s)"
		% str(sim.stations.built_of(id)))
	_check(size.y > depth0 + 10.0 and (b.pos + b.dir * size.y * 0.5).distance_to(front0) < 0.01,
		"its lot reaches further back, the front where it was (%.0f to %.0f m deep)" % [depth0, size.y])
	_check(float(sim.services.boosts.get(id, 1.0)) > 1.0, "and the station reaches further (x%.2f)"
		% float(sim.services.boosts.get(id, 1.0)))
	_check(not "quarters" in sim.stations.built_of(id), "no paid crew in a town of 2,500")
	# A home behind the station: it waits rather than take it.
	sim.stats.population = 6000
	var behind: Vector3 = b.pos - b.dir * (size.y * 0.5 + 6.0)
	var poly := PackedVector2Array()
	for p in Services.corners(Services.Kind.FIRE, behind, b.dir, Vector2(20, 10)):
		poly.append(Vector2(p.x, p.z))
	var fake := _home_under(sim, poly)
	_days(sim, 400)
	_check(not "quarters" in sim.stations.built_of(id) or fake == "",
		"a home behind the station isn't taken for crew quarters (%s)" % fake)
	if fake != "":
		# The chief asks through the bell; a no leaves the home standing.
		var ask: Dictionary = sim.stations.depts[id].ask
		_check(not ask.is_empty() and sim.permits.state_of(int(ask.req)) == Permits.State.OPEN,
			"the chief asks to buy the home behind the station")
		if not ask.is_empty():
			sim.apply({"type": "permit", "id": int(ask.req), "answer": "deny"})
			_days(sim, 2)
			_check(sim.buildings.has(fake) and not "quarters" in sim.stations.built_of(id),
				"a no leaves the home where it is")
			# Asked again later, a yes buys it out and the quarters go up.
			var asked := false
			for i in 80:
				_days(sim, 1)
				var again: Dictionary = sim.stations.depts[id].ask
				if not again.is_empty() and sim.permits.state_of(int(again.req)) == Permits.State.OPEN:
					sim.apply({"type": "permit", "id": int(again.req), "answer": "approve"})
					asked = true
					break
			_check(asked, "the chief asks again after a while")
			_days(sim, 2)
			_check(not sim.buildings.has(fake), "a yes buys the home out")
	_check("quarters" in sim.stations.built_of(id), "and a paid crew moves in (%s)"
		% str(sim.stations.built_of(id)))
	# A save keeps what it built and how far it reaches.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.stations.built_of(id) == sim.stations.built_of(id), "a save keeps the station's pieces")
	_check(is_equal_approx(float(copy.services.boosts.get(id, 1.0)), float(sim.services.boosts.get(id, 1.0))),
		"and its reach")
	_check(Services.size_of(copy.services.buildings[id]).is_equal_approx(Services.size_of(sim.services.buildings[id])),
		"and its lot")
	# Every piece has a real reference's numbers and draws.
	for kind in [Services.Kind.FIRE, Services.Kind.POLICE, Services.Kind.CLINIC, Services.Kind.SCHOOL,
		Services.Kind.NURSING_HOME, Services.Kind.DAYCARE]:
		var all := []
		var full: Vector2 = Services.KINDS[kind].size
		for n in Stations.tree(kind):
			all.append(n.id)
			full.y += float(n.get("grow", 0.0))
		var art := HealthBuilder.build_care(kind, 7, full, 6.0, {}, all) \
			if kind in [Services.Kind.NURSING_HOME, Services.Kind.DAYCARE] else CivicBuilder.build_service(kind, 7, full, 6.0, all)
		_check(art[0] != null and art[0].get_surface_count() > 0, "%s with every piece draws"
			% Services.KINDS[kind].name)
	print("ALL TESTS PASSED" if not failed else "SOME TESTS FAILED")
	quit(1 if failed else 0)


func _days(sim: CitySim, n: int) -> void:
	for i in n:
		sim.tick_count += Stations.DECIDE_EVERY - (sim.tick_count % Stations.DECIDE_EVERY)
		for id in sim.stations.tick(sim):
			sim._clear_zones_under(sim.services.footprint(id))


## A stand-in home on a lot under `poly`, if one is there.
func _home_under(sim: CitySim, poly: PackedVector2Array) -> String:
	for key in sim.lots:
		if sim.parcel_under(key, poly):
			sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": 1, "built": 0, "cap": 3, "occ": 3}
			return key
	return ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	failed = failed or not ok
