extends SceneTree
## Run: godot --headless -s tests/test_clusters.gd
## Like businesses gather: restaurants into a row, doctors by the hospital,
## garages and car lots on the fast road. A business among its own kind is
## worth more, new owners lean toward the cluster, and zoning shops there
## says so.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.simulate_traffic = false
	# A county road (55 mph) through town, shops along both sides.
	sim.build_county_road(Vector2(-600, 0), Vector2(600, 0), [0, 1])
	for x in range(-560, 561, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 600:
		sim.tick()
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	for key in empty:
		if sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.COMMERCIAL:
			sim.found_business(key, ZoneMap.Zone.COMMERCIAL)
	for i in 300:
		sim.tick()
	var shops := []
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.COMMERCIAL and sim.families.owned.has("lot:" + key):
			shops.append(key)
	shops.sort_custom(func(a, b): return sim.lots[a].pos.x < sim.lots[b].pos.x)
	_check(shops.size() >= 8, "shops opened along the road (%d)" % shops.size())
	if shops.size() < 8:
		_finish()
		return

	# Nothing like them nearby: no lift.
	for k in shops:
		sim.families.owned["lot:" + k].what = "hardware"
	sim.clusters._key = []
	_check(sim.clusters.land(sim, shops[0]) == 1.0, "a business with none of its kind nearby gets no lift")

	# Four restaurants side by side: a restaurant row.
	for k in shops.slice(0, 4):
		sim.families.owned["lot:" + k].what = "restaurant"
	sim.clusters._key = []
	var lift: float = sim.clusters.land(sim, shops[1])
	_check(lift > 1.0, "a restaurant among restaurants is worth more (%.3f)" % lift)
	_check(sim.clusters.land(sim, shops[6]) == 1.0, "the hardware store down the road isn't")
	_check(sim.land_factor(shops[1]) > sim.land_factor(shops[6]) * 1.0001 or sim.land_factor(shops[6]) == 0.0,
		"and it shows in the land value")
	var at: Vector3 = sim.lots[shops[1]].pos
	var line := Clusters.hint(sim, at, int(sim.lots[shops[1]].seg))
	_check(line.begins_with("Restaurant row"), "zoning shops there says so: %s" % line)
	_check(Clusters.hint(sim, Vector3(5000, 0, 5000)) == "", "and nothing far from any cluster")
	# A new owner there leans toward a place to eat about half the time.
	var pulled := 0
	for s in 40:
		var t := Clusters.pull(sim, shops[2], s, false)
		if t != "":
			_check(t in Clusters.KINDS.dining.trades, "the pull is toward the row's own kind (%s)" % t)
			pulled += 1
	_check(pulled > 8 and pulled < 32, "about half lean in (%d of 40)" % pulled)

	# Garages on the avenue out of town: an auto row, but no car lots until
	# the market can carry a dealer.
	for k in shops.slice(0, 4):
		sim.families.owned["lot:" + k].what = "auto"
	sim.clusters._key = []
	var sg := int(sim.lots[shops[1]].seg)
	_check(not Clusters.fast_road(sim, sg), "a town street is too slow for an auto row")
	# Zoned, the county road became a town street; make it the avenue out of town.
	sim.network.set_type(sg, RoadStyle.Type.AVENUE)
	_check(Clusters.fast_road(sim, sg), "the avenue is fast enough for an auto row (%s)" % [sim.network.segments.get(sg, {}).get("type", "none")])
	_check(Clusters.hint(sim, at, int(sim.lots[shops[1]].seg)).begins_with("Auto row"), "it's an auto row")
	for s in 40:
		_check(Clusters.pull(sim, shops[2], s, false) != "dealer", "no car lot in a town too small for one")

	# A hospital anchors doctors' offices, even before the first opens.
	var site := Services.site_near(sim.network, Services.Kind.HOSPITAL, Vector3(300, 0, -70))
	_check(not site.is_empty(), "a hospital fits by the shops")
	if not site.is_empty():
		_check(sim.apply({"type": "place_service", "kind": Services.Kind.HOSPITAL, "pos": [site[0].x, site[0].z],
			"dir": [site[1].x, site[1].z]}), "the player places a hospital")
		var near := ""
		for k in shops:
			if sim.lots.has(k) and sim.lots[k].pos.distance_to(site[0]) < Balance.CLUSTER_ANCHOR_REACH and sim.families.owned.get("lot:" + k, {}).get("what", "auto") != "auto":
				near = k
		_check(near != "", "a shop stands near the hospital")
		if near != "":
			var got := {}
			for s in 40:
				got[Clusters.pull(sim, near, s, true)] = true
			_check(got.has("doctor") or got.has("dentist"), "doctors and dentists lean toward the hospital (%s)" % [got.keys()])
			_check(Clusters.hint(sim, sim.lots[near].pos).begins_with("Medical offices by the hospital"),
				"and zoning there says so")
	# Cluster-only trades never open by chance elsewhere.
	for s in 500:
		_check(not Names.trade(s).get("cluster", false), "a car lot or doctor only opens in its cluster")
	_finish()


func _finish() -> void:
	print("FAIL" if _failed else "PASS", " test_clusters")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
