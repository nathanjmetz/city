extends SceneTree
## Run: godot --headless -s tests/test_health.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.build_county_road(Vector2(-600, 0), Vector2(600, 0), [0, 1])
	for x in range(-560, 561, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-560, -100, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	var site := Services.site_near(sim.network, Services.Kind.HOSPITAL, Vector3(150, 0, 60))
	_check(not site.is_empty(), "a hospital fits beside the highway")
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.HOSPITAL, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "the player places a county hospital")
	for i in 1200:
		sim.tick()
	var id: int = sim.services.buildings.keys()[0]
	var hc := sim.healthcare
	_check(hc.hubs.has(id), "the hospital has a hub")
	var h: Dictionary = hc.hubs[id]
	_check(str(h.leader.name).length() > 4 and h.leader.has("edu"), "an administrator runs it (%s, %s)" % [h.leader.name, h.leader.title])
	_check(Inspect.describe(sim, {"type": "service", "id": id}).title.ends_with("County Hospital"), "it's a county hospital to start")
	# Its reach counts as a clinic's for the homes.
	var any_home := ""
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			any_home = key
			break
	_check(any_home != "" and sim.services.served[any_home][Services.Kind.CLINIC], "the hospital's homes count as near a clinic")
	_check(hc.jobs(sim) > 0, "the hospital employs people (%d)" % hc.jobs(sim))
	# A big town: lots of people per home, so calls come often.
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			sim.buildings[key].cap = 60
			sim.buildings[key].occ = 60
	sim.update_stats()
	var saw_ambulance := false
	for i in 6000:
		sim.tick()
		for car in sim.traffic.cars:
			if car.purpose == "medical" and car.kind == "ambulance":
				saw_ambulance = true
	_check(saw_ambulance, "an ambulance drives out on a call")
	_check(int(h.calls) > 0 and int(h.treated) > 0, "calls answered and patients brought in (%d calls, %d treated)" % [h.calls, h.treated])
	# The tree: an administrator who saved up opens the next building on
	# land right next to the hospital.
	var first := Services.KINDS[Services.Kind.HOSPITAL].size
	var before := PackedVector2Array()
	for p in Services.corners(Services.Kind.HOSPITAL, h.front - h.dir * first.y * 0.5, h.dir):
		before.append(Vector2(p.x, p.z))
	var before_size := first
	h.savings = 1e9
	h.leader.ambition = 0.0  # starts small
	hc.decide(sim)
	_check(h.pieces.size() >= 1 and h.pieces[0].key == "er", "it opens the ER first (%s)" % str(h.pieces))
	var after_size := Services.size_of(sim.services.buildings[id])
	_check(after_size.x * after_size.y > before_size.x * before_size.y + 1000.0, "the campus grows (%s -> %s)" % [before_size, after_size])
	_check(not Geometry2D.intersect_polygons(before, sim.services.footprint(id)).is_empty(), "it grows next to itself, not somewhere else")
	sim.tick()
	for key in sim.lots:
		_check(not sim.services.covers(sim.lots[key].pos), "no lot left under the new wing")
	_check(hc.unmet(sim, id, "maternity").contains("daycare"), "the maternity ward needs a daycare in town")
	_check(hc.unmet(sim, id, "garage") != "", "no parking garage while there's still land")
	_check(hc.unmet(sim, id, "heart").contains("regional"), "the heart center needs a regional medical center")
	# A daycare and a nursing home: jobs, care and the branches they open.
	var jobs_before := hc.jobs(sim)
	var care_before := hc.care(sim)
	for kind in [Services.Kind.DAYCARE, Services.Kind.NURSING_HOME]:
		for x in [-300.0, -420.0, -200.0, 300.0, 420.0]:
			var s := Services.site_near(sim.network, kind, Vector3(x, 0, 60))
			if not s.is_empty() and sim.apply({"type": "place_service", "kind": kind, "pos": [s[0].x, s[0].z],
					"dir": [s[1].x, s[1].z]}):
				break
	sim.update_stats()
	_check(hc.jobs(sim) == jobs_before + Balance.DAYCARE_JOBS + Balance.NURSING_HOME_JOBS, "the daycare and nursing home hire staff")
	_check(hc.care(sim) > care_before, "care improves (%.2f -> %.2f)" % [care_before, hc.care(sim)])
	_check(hc.demand_shift(sim) > 0.0, "good care lifts the want for homes")
	_check(hc.unmet(sim, id, "maternity") == "", "with a daycare, the maternity ward opens up")
	# Up a level: the community hospital tower, for a bold administrator the
	# town has told to grow.
	h.leader.ambition = 1.0
	sim.apply({"type": "guide", "hub": Healthcare.PERMIT_KIND, "hub_id": id, "stance": "grow", "grant": 0})
	for i in 6:
		hc.decide(sim)
	_check(int(h.level) >= 1, "it grows into a community hospital (level %d, %s)" % [h.level, str(h.pieces.map(func(p): return p.key))])
	_check(Inspect.describe(sim, {"type": "service", "id": id}).title.contains("Community Hospital") or int(h.level) == 2,
		"its name follows its size")
	# Saves and two copies agree.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true)))
	_check(copy.healthcare.hubs.has(id) and copy.healthcare.hubs[id].pieces.size() == h.pieces.size(), "a save keeps the hospital's buildings")
	_check(Services.size_of(copy.services.buildings[id]) == Services.size_of(sim.services.buildings[id]), "a save keeps its campus size")
	for i in 400:
		sim.tick()
		copy.tick()
	var da := sim.to_dict()
	var db := copy.to_dict()
	for k in ["healthcare", "services", "buildings", "economy"]:
		var sa := JSON.stringify(da[k], "", false, true)
		var sb := JSON.stringify(db[k], "", false, true)
		if sa != sb:
			for i in mini(sa.length(), sb.length()):
				if sa[i] != sb[i]:
					print(k, ": ", sa.substr(maxi(0, i - 150), 250), "\n vs ", sb.substr(maxi(0, i - 150), 250))
					break
	_check(JSON.stringify(da.healthcare, "", false, true) == JSON.stringify(db.healthcare, "", false, true)
		and JSON.stringify(da.services, "", false, true) == JSON.stringify(db.services, "", false, true)
		and JSON.stringify(da.economy, "", false, true) == JSON.stringify(db.economy, "", false, true), "copies stay in sync")
	# A new administrator after ten years, schooled by today's town.
	var old_name: String = h.leader.name
	h.leader.hired = sim.tick_count - Balance.HOSPITAL_TENURE_DAYS * Healthcare.TICKS_PER_MONTH - 1
	hc.decide(sim)
	_check(str(h.note).contains("retired") and str(h.note).contains(old_name), "the administrator retires (%s)" % h.note)
	# Too big for its town: the newest building closes.
	var n: int = h.pieces.size()
	for key in sim.buildings:
		sim.buildings[key].occ = 0
	sim.update_stats()
	h.savings = -1.0
	hc.region_pop = 0
	for i in 6:
		hc.decide(sim)
	_check(h.pieces.size() < n, "a hospital that can't pay its way closes its newest building (%d -> %d)" % [n, h.pieces.size()])
	# Neighbors: the region's people count toward regional branches.
	hc.region_pop = 40000
	_check(hc.regional_pop(sim) >= 40000, "neighboring towns count toward the hospital's region")
	_check(h.built.size() == h.pieces.size() and h.leader.has("caution"), "the tree is kept the shared Agency way")
	# The Economy page: Funding is the levy, Growth is the word to the administrator.
	var hkey := "hospital:%d" % id
	_check(sim.hub_area(hkey) == "health", "the hospital sits under Health and care on the Economy page")
	var levy := sim.services.upkeep_of(id)
	_check(sim.apply({"type": "policy", "scope": hkey, "slider": "funding", "step": 4}) and sim.services.upkeep_of(id) > levy,
		"a generous hospital levy costs more (%d -> %d)" % [levy, sim.services.upkeep_of(id)])
	_check(sim.apply({"type": "policy", "scope": hkey, "slider": "growth", "step": 0})
		and sim.permits.guidance(Healthcare.PERMIT_KIND, id).stance == "hold", "Growth on Hold tells the administrator to hold off")
	sim.apply({"type": "guide", "hub": Healthcare.PERMIT_KIND, "hub_id": id, "stance": "grow", "grant": 0})
	_check(sim.policies.step("growth", "health", hkey) >= 3, "Grow from the administrator's row moves the slider too")
	sim.apply({"type": "policy_reset", "scope": "city"})
	# Homes all around: the administrator asks before buying them out.
	var t := CitySim.new()
	t.economy.money = 500_000_000
	t.build_county_road(Vector2(-400, 0), Vector2(400, 0), [0, 1])
	# The next street back far enough that its back yards meet the hospital's
	# rear wall rather than run under it.
	t.apply({"type": "build_road", "start": [-300, 145], "ctrl": [0, 145], "end": [300, 145]})
	var hs := Services.site_near(t.network, Services.Kind.HOSPITAL, Vector3(0, 0, 60))
	t.apply({"type": "place_service", "kind": Services.Kind.HOSPITAL, "pos": [hs[0].x, hs[0].z], "dir": [hs[1].x, hs[1].z]})
	for x in range(-280, 281, 10):
		for z in [25, 120]:
			t.apply({"type": "paint_zone", "center": [x, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 1500:
		t.tick()
	var tid: int = t.services.buildings.keys()[0]
	var th: Dictionary = t.healthcare.hubs[tid]
	for key in t.buildings:
		t.buildings[key].cap = 60
		t.buildings[key].occ = 60
	t.update_stats()
	th.leader.ambition = 0.0
	th.savings = 1e9
	var homes := t.count_buildings(ZoneMap.Zone.RESIDENTIAL)
	t.healthcare.decide(t)
	_check(not th.permit.is_empty() and th.pieces.is_empty(), "with homes in the way, it files a permit request first (%s)" % th.note)
	_check(t.count_buildings(ZoneMap.Zone.RESIDENTIAL) == homes, "no home is touched before the player answers")
	_check(Inspect.describe(t, {"type": "service", "id": tid}).problems[0].contains("permits bell"), "its panel says it's waiting on you")
	t.apply({"type": "permit", "id": int(th.permit.req), "answer": "approve"})
	t.healthcare.decide(t)
	t.tick()
	_check(th.pieces.size() == 1 and th.permit.is_empty(), "once approved, it buys the land and builds")
	_check(t.count_buildings(ZoneMap.Zone.RESIDENTIAL) < homes, "the homes it bought make way")
	# No hospital: the county ambulance comes in from the highway.
	var far := CitySim.new()
	far.build_county_road(Vector2(-400, 0), Vector2(400, 0), [0])
	for x in range(-380, 381, 10):
		far.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 600:
		far.tick()
	for key in far.buildings:
		far.buildings[key].cap = 80
		far.buildings[key].occ = 80
	far.update_stats()
	for i in 3000:
		far.tick()
	_check(far.healthcare.county_calls > 0, "with no hospital, the county's ambulance answers (%d calls)" % far.healthcare.county_calls)
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	elif not what.begins_with("no lot left"):
		print("PASS " + what)
