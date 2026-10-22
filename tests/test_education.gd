extends SceneTree
## Run: godot --headless -s tests/test_education.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 200_000_000
	sim.build_county_road(Vector2(-2000, 0), Vector2(2000, 0), [0, 1])
	# A street of homes north of the highway.
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -150], "end": [-300, -300]})
	for z in range(-290, -10, 10):
		sim.apply({"type": "paint_zone", "center": [-275, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [-325, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 6000:
		sim.tick()
	_check(sim.stats.population > 0, "people live in town (%d)" % sim.stats.population)

	# Placing: beside a street, with open land behind it.
	var site := Education.site_near(sim.network, Vector3(300, 0, 90))
	_check(site.size() == 2, "a campus finds its spot beside the highway")
	_check(Education.site_problem(sim, "high_school", site[0], site[1]) == "", "open ground is fine for a campus")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_campus", "kind": "high_school", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "placing a high school")
	_check(money - sim.economy.money == int(Education.spec("high_school").cost), "the city pays for the first building")
	var id: int = sim.education.campuses.keys()[0]
	var c: Dictionary = sim.education.campuses[id]
	_check(str(c.leader.name) != "" and c.leader.edu >= 0.0, "it hires a principal (%s)" % Education.leader_name(c.leader))
	_check(sim.education.covers(site[0]), "the campus covers its first block")
	_check(not sim.apply({"type": "place_campus", "kind": "college", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "no campus on top of another")

	# A month: students from the homes apply and enroll.
	sim.education.decide(sim)
	_check(c.applicants > 0 and c.enrolled > 0, "teens from town enroll (%d of %d)" % [c.enrolled, c.applicants])
	_check(c.enrolled <= Education.seats(c), "never more students than seats")
	_check(sim.education.monthly_upkeep() == int(Education.spec("high_school").funding), "standard funding")
	sim.update_stats()
	_check(int(sim.economy.budget.education) > 0, "the budget pays for schools")

	# A university across town, packed with students from the region: its
	# president buys the next block, right next door.
	var usite := Education.site_near(sim.network, Vector3(-900, 0, 90))
	_check(sim.apply({"type": "place_campus", "kind": "university", "pos": [usite[0].x, usite[0].z],
		"dir": [usite[1].x, usite[1].z]}), "placing a university")
	var uid: int = sim.education.campuses.keys().max()
	var u: Dictionary = sim.education.campuses[uid]
	_check(u.leader.edu >= 0.7, "a university hires a president with a doctorate")
	for i in 4:
		_grow(sim, u)
	_check(u.blocks.size() >= 3, "a full campus buys land next to it (%d blocks)" % u.blocks.size())
	_check(Education.seats(u) > int(Education.spec("university").seats), "new halls add seats")
	for blk in u.blocks:
		var touching := false
		for other in u.blocks + [{"c": Vector2i.ZERO}]:
			touching = touching or (absi(blk.c.x - other.c.x) + absi(blk.c.y - other.c.y) == 1)
		_check(touching, "block %s touches the campus (no second sites)" % str(blk.c))
		_check(blk.c.y >= 0, "blocks grow back from the street, never across it")
	var corr := RoadWins.corridors(sim.network, 0.0)
	for blk in u.blocks:
		_check(not RoadWins.hits(corr, Education.block_corners(u, blk.c)), "no block on a road")
	# The tree: farm country unlocks an ag college; a town with no clinic can't
	# grow a medical school.
	var facts := Education.town_facts(sim)
	_check(Education.locked_by(sim, u, "ag_extension", facts) != "", "no ag college without farms around")
	_check(Education.locked_by(sim, u, "med_school", facts) != "", "no medical school without a clinic")
	_check(u.built.size() > 0 and u.why != "", "the tree records what it built and why (%s)" % u.why)
	# Neighbours (Agency's region conditions): a farm town that sells grain
	# opens a community college's agribusiness program.
	var csite := Education.site_near(sim.network, Vector3(900, 0, 90))
	_check(sim.apply({"type": "place_campus", "kind": "college", "pos": [csite[0].x, csite[0].z],
		"dir": [csite[1].x, csite[1].z]}), "placing a community college")
	var col: Dictionary = sim.education.campuses[sim.education.campuses.keys().max()]
	col.built = ["classrooms"]
	_check(Education.locked_by(sim, col, "agribusiness", facts) != "", "no agribusiness program without farm neighbours")
	sim.region = {"neighbors": [{"name": "Oakland City", "exports": {"grain": 40.0}}]}
	_check(Education.locked_by(sim, col, "agribusiness", facts) == "", "a neighbouring farm town opens it")
	sim.region = {}
	col.built = []
	var fresh := {"kind": "university", "pos": u.pos, "blocks": [], "built": [], "leader": u.leader,
		"reputation": 0.3, "enrolled": 0, "funding": 2, "savings": 0.0}
	_check(Education.pick_next(sim, fresh, facts, true) == "hall", "a new university builds a hall first")

	# Funding is the player's lever.
	_check(sim.apply({"type": "set_campus_funding", "id": id, "level": 4}), "funding raised")
	_check(Education.monthly_funding(c) == roundi(Education.spec("high_school").funding * 1.5), "funding at 150%")

	# Graduates who stay bring office jobs; the town's leaders get more educated.
	sim.education.locals = {"high_school": 0.0, "associate": 0.0, "degree": 0.0}
	var edu0 := sim.education.leader_education(maxi(sim.stats.workers, 1))
	_check(sim.education.office_jobs() == 0, "no graduates, no office jobs")
	sim.education.locals.degree = 40.0
	_check(sim.education.office_jobs() == 40, "office jobs follow the graduates")
	_check(sim.education.leader_education(maxi(sim.stats.workers, 1)) > edu0, "educated town, educated leaders")
	var jobs0: int = sim.stats.jobs
	sim.update_stats()
	_check(sim.stats.jobs > jobs0, "office and teaching jobs count as jobs")

	# Inspect shows its head and a funding lever.
	var d := Inspect.describe(sim, Inspect.pick(sim, site[0]))
	_check(d.get("title", "") == "High school", "clicking the campus inspects it")
	_check(not d.get("actions", []).is_empty(), "the panel offers funding buttons")

	# The player can clear one block; the head won't buy it straight back.
	if not u.blocks.is_empty():
		var blk: Dictionary = u.blocks[0]
		var p := Education.block_center(u, blk.c)
		_check(sim.apply({"type": "remove_campus_block", "pos": [p.x, p.z]}), "clearing a block")
		_check(not sim.education.covers(p), "the cleared block is free land")
		_grow(sim, u)
		var back := false
		for b2 in u.blocks:
			back = back or b2.c == blk.c
		_check(not back, "it doesn't buy back what the player cleared")

	# Boxed in by homes: an ambitious head asks the player (Permits) to buy
	# the block next door, and builds there once the player says yes.
	_land_request(sim)

	# Saves round-trip, and the same commands give the same campus.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var cc: Dictionary = copy.education.campuses[uid]
	_check(cc.blocks.size() == u.blocks.size() and cc.leader.name == u.leader.name and copy.education.campuses[id].funding == c.funding,
		"save keeps the campus, its head and funding")
	_check(absf(copy.education.locals.degree - sim.education.locals.degree) < 0.001, "save keeps the town's graduates")

	# The road wins: a road through the first building closes it and pays back.
	money = sim.economy.money
	sim.apply({"type": "build_road", "start": [site[0].x - 150, site[0].z], "ctrl": [site[0].x, site[0].z],
		"end": [site[0].x + 150, site[0].z]})
	_check(not sim.education.campuses.has(id), "a road through the school closes it")
	_check(sim.economy.money > money - 200_000, "and the city is paid back")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## A month with this campus packed and flush with savings. decide()
## recounts applicants from the town, so the region draw is turned way up.
func _grow(sim: CitySim, c: Dictionary) -> void:
	sim.education.region = {"population": 50_000_000}
	c.reputation = 1.0
	c.savings = 50_000_000.0
	sim.education.decide(sim)
	sim.education.region = {}


## A packed high school with an ambitious principal, boxed in by homes on
## every side: it files a land request, and builds once the player agrees.
func _land_request(sim: CitySim) -> void:
	var hs := Education.site_near(sim.network, Vector3(1500, 0, 90))
	_check(sim.apply({"type": "place_campus", "kind": "high_school", "pos": [hs[0].x, hs[0].z],
		"dir": [hs[1].x, hs[1].z]}), "placing a high school out east")
	var id: int = sim.education.campuses.keys().max()
	var c: Dictionary = sim.education.campuses[id]
	c.leader.ambition = 0.9
	c.leader.caution = 0.1
	# The player told its principal to grow (the leader guide).
	_check(sim.apply({"type": "guide", "hub": "campus", "hub_id": id, "stance": "grow"}), "telling it to grow")
	# Homes on the three blocks around it (copies of a real home's lot).
	var home := ""
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			home = key
			break
	for cell in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var mid := Education.block_center(c, cell)
		var lot: Dictionary = sim.lots[home].duplicate(true)
		var shift: Vector3 = mid - lot.pos
		lot.pos = mid
		lot.zone_pt = mid
		var corners := PackedVector2Array()
		for p in sim.lots[home].corners:
			corners.append(p + Vector2(shift.x, shift.z))
		lot.corners = corners
		var key := "test_home_%d_%d" % [cell.x, cell.y]
		lot.key = key
		sim.lots[key] = lot
		sim.buildings[key] = sim.buildings[home].duplicate(true)
	c.savings = 50_000_000.0
	c.reputation = 1.0
	sim.education.region = {"population": 50_000_000}
	sim.education.decide(sim)
	_check(c.blocks.is_empty(), "it never builds on homes without asking")
	_check(not c.asking.is_empty(), "a boxed-in high school asks you for the homes next door")
	if c.asking.is_empty():
		sim.education.region = {}
		return
	var req: Dictionary = sim.permits.requests[c.asking.req]
	_check(req.shape == "area" and req.change != "" and req.cost > 0, "a land-use request with a boundary and a price")
	var cell: Vector2i = c.asking.cell
	_check(sim.apply({"type": "permit", "id": req.id, "answer": "approve"}), "you say yes")
	sim.education.decide(sim)
	sim.education.region = {}
	var there := false
	for blk in c.blocks:
		there = there or blk.c == cell
	_check(there, "it builds on the land you gave it")
	_check(c.asking.is_empty() and sim.permits.state_of(req.id) == Permits.State.DONE, "and the request is done")


var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
