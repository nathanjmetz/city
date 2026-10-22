extends SceneTree
## Run: godot --headless -s tests/test_mail.gd
## The post office: its postmaster plans routes, carriers and parcel vans
## make real trips and come home, mail makes the town a little better, the
## office grows only next door, and the development tree unlocks from the
## postmaster, the town and the neighbours.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -200], "end": [0, -400]})
	for x in range(-400, 401, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	for z in range(-400, -40, 10):
		sim.apply({"type": "paint_zone", "center": [25, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := CivicHubs.site_near(sim.network, Vector3(300, 0, 60))
	_check(not site.is_empty(), "a post office finds a spot beside the street")
	var money := sim.economy.money
	var place := {"type": "place_post_office", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}
	_check(sim.apply(place), "post office placed")
	_check(sim.economy.money == money - Balance.MAIL_COST, "it costs its price")
	_check(not sim.apply(place), "one post office per town")
	var id: int = sim.mail.offices.keys()[0]
	var h: Dictionary = sim.mail.offices[id]
	_check(str(h.postmaster.name).contains(" "), "a named postmaster runs it (%s)" % h.postmaster.name)
	for key in sim.lots:
		_check(not sim.mail.covers(sim.lots[key].pos), "no lot left on the post office's land")
	_check(Inspect.pick(sim, h.pos - h.dir * 20.0).get("type", "") == "post_office", "clicking it selects it")
	# Run the town for a few days and watch the routes.
	var kinds := {}
	var saw_stop := false
	var cars_seen := true
	for i in 6 * Mail.TICKS_PER_DAY:
		sim.tick()
		for t in sim.mail.trips:
			kinds[sim.mail.trips[t].kind] = true
			saw_stop = saw_stop or sim.mail.trips[t].prev >= 0
		if i % 97 == 0 and not sim.mail.trips.is_empty():
			var ids := (sim.traffic.cars + sim.traffic._waiting).map(func(c): return c.id)
			for t in sim.mail.trips:
				if not t in ids:
					cars_seen = false
	_check(sim.stats.population > 50, "people moved in (%d)" % sim.stats.population)
	_check(kinds.has("carrier") or kinds.has("rural"), "carriers went out on routes (%s)" % str(kinds.keys()))
	_check(kinds.has("van"), "parcel vans went out to the businesses")
	_check(kinds.has("freight_in") or kinds.has("freight_out") or sim.region_links.is_empty(), "the mail truck runs to the region")
	_check(saw_stop, "carriers went from street to street")
	_check(cars_seen, "every mail trip is a real vehicle")
	_check(int(h.get("routes", 0)) >= 1, "the postmaster planned routes (%d)" % int(h.get("routes", 0)))
	_check(sim.mail.home_share > 0.5, "most homes get their mail (%.2f)" % sim.mail.home_share)
	_check(sim.mail.out(id, ["carrier", "rural"]) <= sim.mail.carriers(id), "never more carriers out than it has")
	# Mail makes a place a little better.
	var served_key := ""
	for key in sim.buildings:
		if sim.mail.served(sim, sim.lots[key].seg):
			served_key = key
			break
	_check(served_key != "" and sim.mail.lot_factor(sim, served_key) > 1.0, "served streets are worth a little more")
	_check(sim.mail.demand_shift(ZoneMap.Zone.RESIDENTIAL) > 0.0, "good mail lifts demand for homes")
	# Roads in the plan: a street's routes are deterministic.
	var s1 := sim.mail.plan_routes(sim, id, sim.mail._streets(sim)[0], 40, 5)
	var s2 := sim.mail.plan_routes(sim, id, sim.mail._streets(sim)[0], 40, 5)
	_check(str(s1) == str(s2) and s1.size() >= 2, "small routes split the town the same way every time (%d)" % s1.size())
	var all := {}
	for r in s1:
		for seg in r.stops:
			_check(not all.has(seg), "each street on one route")
			all[seg] = true
	# Busy: carriers short on most rounds, so it buys land next door.
	var before: int = h.cells.size()
	for round in 6:
		h.want = 10
		h.short = 10
		sim.mail._decide(sim)
	_check(h.cells.size() > before, "a short-handed office grows its lot (%d -> %d)" % [before, h.cells.size()])
	_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "every piece touches the rest: one site")
	for c in h.cells:
		_check(c.y >= 0 and not Services.road_clash(sim.network, CivicHubs.cell_poly(h, c, 1.0)), "no piece on a road")
	# The tree: gates read the postmaster, town and region.
	h.postmaster.education = 0.1
	_check(sim.mail.locked(sim, id, "passports") != "", "passports wait for po boxes or schooling")
	h.tree["po_boxes"] = sim.tick_count
	_check(sim.mail.locked(sim, id, "passports").contains("schooling") or sim.stats.population < 1500,
		"an unschooled postmaster can't run passports")
	_check(sim.mail.locked(sim, id, "regional_hub").contains("first"), "the regional hub needs a sorting center first")
	h.tree["sorting_room"] = 1
	h.tree["sorting_center"] = 1
	h.postmaster.education = 0.9
	sim.mail.region = {"towns": 0, "population": 0}
	sim.mail._decide(sim)
	_check(sim.mail.locked(sim, id, "regional_hub").contains("neighboring"), "the regional hub needs neighbor towns")
	sim.mail.region = {"towns": 3, "population": 9000}
	sim.mail._decide(sim)
	_check(sim.mail.locked(sim, id, "regional_hub") == "", "with neighbors around, the regional hub opens up")
	# The postmaster builds from their own fund; a big step takes land.
	h.project = {}
	h.fund = 10_000_000.0
	h.postmaster.ambition = 0.9
	h.postmaster.caution = 0.1
	var cells_before: int = h.cells.size()
	sim.mail._choose(sim, id)
	_check(not h.project.is_empty() and h.project.node == "regional_hub",
		"an ambitious postmaster goes for the regional hub (%s)" % str(h.project))
	_check(h.cells.size() == cells_before + int(Balance.MAIL_TREE.regional_hub.land) or h.boxed,
		"it takes land next door for it")
	h.project.done = sim.tick_count
	sim.mail._decide(sim)
	_check(h.tree.has("regional_hub") and sim.mail.serves_region(), "the regional hub opens and serves the region")
	# Funding is the player's lever.
	var cost := sim.mail.monthly_cost()
	_check(sim.apply({"type": "post_office_funding", "id": id, "level": 3}), "funding raised")
	_check(sim.mail.monthly_cost() > cost, "more funding costs the city more")
	var info := Inspect.describe(sim, {"type": "post_office", "id": id})
	_check(info.title == "Post Office" and info.rows.size() > 8, "the info panel describes it")
	# Save and load keep it.
	var saved := sim.to_dict()
	var sim2 := CitySim.new()
	sim2.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(sim2.mail.offices.size() == 1 and sim2.mail.offices.values()[0].tree.has("regional_hub"), "saves keep the post office and its tree")
	_check(sim2.mail.offices.values()[0].cells.size() == h.cells.size(), "saves keep its land")
	_check(sim2.mail.trips.size() == sim.mail.trips.size(), "saves keep the mail on the road")
	# Roads win: a road through it cuts it back to one piece.
	var cut := CivicHubs.cell_center(h, Vector2i(0, 1))
	var along := CivicHubs.right(h) * 300.0
	sim.apply({"type": "build_road", "start": [cut.x - along.x, cut.z - along.z], "ctrl": [cut.x, cut.z],
		"end": [cut.x + along.x, cut.z + along.z]})
	sim.tick()
	if sim.mail.offices.has(id):
		for c in h.cells:
			_check(not Services.road_clash(sim.network, CivicHubs.cell_poly(h, c, 1.0)), "after the road, no piece on it")
		_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "after the road, still one site")
	_check(sim.apply({"type": "remove_post_office", "id": id}) or not sim.mail.offices.has(id), "demolished")
	_check(sim.mail.offices.is_empty(), "gone")
	for i in 200:
		sim.tick()
	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
