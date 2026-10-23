class_name Inspect
extends RefCounted
## What the player clicked and everything worth knowing about it, like the
## selected-object panel in Cities: Skylines 2: whether it works, what it
## serves or makes, its people, costs and any problem in plain words.
## Plain data, so tests can read it and any interface can show it.


## The thing under a ground point: {type: "service"|"farm"|"lot"|"road", id},
## or {} for open ground. Buildings win over the road they stand on.
static func pick(sim: CitySim, p: Vector3) -> Dictionary:
	if not sim.rail.trains.is_empty():
		var tid := sim.rail.train_at(p)
		if tid != -1:
			return {"type": "train", "id": tid}
	var rid := sim.rail.depot_at(p)
	if rid != -1:
		return {"type": "rail", "id": rid}
	var mid := sim.mail.at(p)
	if mid != -1:
		return {"type": "post_office", "id": mid}
	var hid := sim.hubs.at(p)
	if hid != -1:
		return {"type": "hub", "id": hid}
	var sid := sim.services.at(p)
	var yard := sim.services.water.work_at(sim.services.buildings, p)
	if sid == -1 and not yard.is_empty():
		sid = yard[0]  # a piece of the water utility's yard
	if sid != -1:
		# The water utility is a hub with a leader, so it gets its own panel.
		if sim.services.buildings[sid].kind == Services.Kind.WATER_UTILITY and sim.services.water.utilities.has(sid):
			return {"type": "water", "id": sid}
		return {"type": "service", "id": sid}
	var wid := sim.warehouses.at(p)
	if wid != -1:
		return {"type": "warehouse", "id": wid}
	var pid := sim.parks.at(p)
	if pid != -1:
		return {"type": "park", "id": pid}
	var pwid := sim.power.at(p)
	if pwid != -1:
		return {"type": "power", "id": pwid}
	var iid := sim.industry.site_at(p)
	if iid == -1:
		iid = sim.industry.pad_at(p)
	if iid != -1:
		return {"type": "industry", "id": iid}
	var bid := sim.banks.at(p) if not sim.banks.banks.is_empty() else -1
	if bid != -1:
		return {"type": "bank", "id": bid}
	var cid := sim.education.at(p) if not sim.education.campuses.is_empty() else -1
	if cid != -1:
		return {"type": "campus", "id": cid}
	var tid := sim.telecom.at(p) if not sim.telecom.companies.is_empty() else -1
	if tid != -1:
		return {"type": "telecom", "id": tid}
	var fid := sim.farms.farm_at(p)
	if fid == -1:
		fid = sim.farms.field_at(p)
	if fid != -1:
		return {"type": "farm", "id": fid}
	var q := Vector2(p.x, p.z)
	var keys := sim.lots.keys()
	keys.sort()
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		if not Geometry2D.is_point_in_polygon(q, lot.corners):
			continue
		if sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE:
			return {"type": "lot", "id": key}
	var near := sim.network.find_segment_near(p, 14.0, 4.0)
	if not near.is_empty():
		var hw := RoadStyle.half_width(sim.network.segments[near.seg].type)
		if near.dist <= hw + 1.5:
			return {"type": "road", "id": near.seg}
	return {}


## Where the selection sits, for the marker: [centre, radius], or [] if gone.
static func place(sim: CitySim, sel: Dictionary) -> Array:
	if not exists(sim, sel):
		return []
	match sel.type:
		"service", "water":
			var b: Dictionary = sim.services.buildings[sel.id]
			return [b.pos, Services.size_of(b).length() * 0.5 + 3.0]
		"park":
			var s: Dictionary = sim.parks.sites[sel.id]
			return [s.pos, s.size.length() * 0.5 + 3.0]
		"industry":
			return [sim.industry.sites[sel.id].pos, Industry.HQ_SIZE.length() * 0.5 + 3.0]
		"hub":
			return sim.hubs.extent(sel.id)
		"warehouse":
			var w: Dictionary = sim.warehouses.buildings[sel.id]
			return [Warehouses.center(w), Vector2(Warehouses.site_width(w), Warehouses.site_depth(w)).length() * 0.5 + 3.0]
		"power":
			return [sim.power.sites[sel.id].pos, Power.HQ_SIZE.length() * 0.5 + 3.0]
		"campus":
			return [sim.education.campuses[sel.id].pos, Education.CELL * 0.75]
		"post_office":
			return sim.mail.extent(sel.id)
		"telecom":
			return [sim.telecom.companies[sel.id].pos, Telecom.CELL * 0.75]
		"rail":
			return [sim.rail.depots[sel.id].pos, Rail.YARD_LEN * 0.5 + Rail.LADDER]
		"train":
			var cars := sim.rail.car_poses(sel.id)
			if cars.is_empty():
				return []
			return [(cars[0][1] + cars[-1][2]) * 0.5, maxf(12.0, (cars[0][1] as Vector3).distance_to(cars[-1][2]) * 0.5 + 4.0)]
		"bank":
			return [sim.banks.banks[sel.id].pos, Banks.CELL * 0.75]
		"farm":
			return [sim.farms.farms[sel.id].pos, Farms.FARMHOUSE_SIZE.length() * 0.5 + 3.0]
		"lot":
			return [sim.lots[sel.id].pos, LotPlanner.DEPTH * 0.5 + 2.0]
		"road":
			var c := sim.network.curve_of(sel.id)
			return [RoadNetwork.bezier(c[0], c[1], c[2], 0.5), RoadStyle.half_width(sim.network.segments[sel.id].type) + 4.0]
		"spot":
			return [Vector3(sel.id[0], 0.0, sel.id[1]), 8.0]
	return []


static func exists(sim: CitySim, sel: Dictionary) -> bool:
	match sel.get("type", ""):
		"service": return sim.services.buildings.has(sel.id)
		"water": return sim.services.water.utilities.has(sel.id) and sim.services.buildings.has(sel.id)
		"hub": return sim.hubs.hubs.has(sel.id)
		"post_office": return sim.mail.offices.has(sel.id)
		"rail": return sim.rail.depots.has(sel.id)
		"train": return sim.rail.trains.has(sel.id)
		"farm": return sim.farms.farms.has(sel.id)
		"industry": return sim.industry.sites.has(sel.id)
		"campus": return sim.education.campuses.has(sel.id)
		"telecom": return sim.telecom.companies.has(sel.id)
		"bank": return sim.banks.banks.has(sel.id)
		"warehouse": return sim.warehouses.buildings.has(sel.id)
		"park": return sim.parks.sites.has(sel.id)
		"power": return sim.power.sites.has(sel.id)
		"lot": return sim.lots.has(sel.id)
		"road": return sim.network.segments.has(sel.id)
		"spot": return true
	return false


## {title, kind (a line under the title), icon, ok: bool, status, rows:
## [[label, value]], problems: [text]}, and optionally notes: [text] and
## actions (see HubInfo). Pollution is added to everything (PollutionInfo).
static func describe(sim: CitySim, sel: Dictionary) -> Dictionary:
	if not exists(sim, sel):
		return {}
	if sel.type == "spot":
		return PollutionInfo.spot(sim, Vector3(sel.id[0], 0.0, sel.id[1]))
	return PollutionInfo.add(sim, sel, _describe(sim, sel))


static func _describe(sim: CitySim, sel: Dictionary) -> Dictionary:
	match sel.type:
		"service": return _service(sim, sel.id)
		"water": return WaterUtility.describe(sim, sel.id)
		"hub": return HubInfo.describe(sim, sel.id)
		"post_office": return MailInfo.describe(sim, sel.id)
		"rail": return RailInfo.depot(sim, sel.id)
		"train": return RailInfo.train(sim, sel.id)
		"farm": return _farm(sim, sel.id)
		"industry": return _industry(sim, sel.id)
		"campus": return CampusInfo.describe(sim, sel.id)
		"telecom": return TelecomInfo.describe(sim, sel.id)
		"bank": return BankInfo.describe(sim, sel.id)
		"warehouse": return _warehouse(sim, sel.id)
		"park": return _park(sim, sel.id)
		"power": return _power(sim, sel.id)
		"lot": return _lot(sim, sel.id)
		"road": return _road(sim, sel.id)
	return {}


static func _service(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	if b.kind == Services.Kind.BUS_DEPOT:
		return sim.buses.describe(sim, id)
	if b.kind == Services.Kind.TAXI_COMPANY:
		return sim.taxis.describe(sim, id)
	var k: Dictionary = Services.KINDS[b.kind]
	var rows := []
	var problems := []
	var linked := not sim.network.find_segment_near(b.pos + b.dir * k.size.y * 0.5, 80.0, 1.0).is_empty()
	var ok := linked
	var status := ""
	if k.has("utility"):
		var u: String = k.utility
		var use: Array = sim.services.utility_use[u]
		var reached := 0
		for key in sim.services.served:
			if sim.services.served[key].get(u + "_linked", false):
				reached += 1
		rows.append(["This building serves", "%s homes" % CitySim.money_text(
			roundi(int(k.capacity) * sim.services.funding(id, Balance.POLICY_EFFECT)))])
		rows.append(["Town %s in use" % u, "%s of %s homes" % [CitySim.money_text(use[0]), CitySim.money_text(use[1])]])
		rows.append(["Lots it reaches by road", str(reached)])
		if not linked:
			problems.append("Not beside a road, so its %s goes nowhere." % u)
		elif reached == 0:
			ok = false
			problems.append("No lots along its roads yet. Zone the streets it's on.")
		elif use[0] >= use[1]:
			problems.append("At capacity: build more %s." % u)
		status = "Working: supplying %s" % u if ok else "Not supplying anything"
		# The town also needs the other utility before anything grows.
		var other := "water" if u == "power" else "power"
		if sim.services.utility_use[other][1] == 0:
			problems.append("The town has no %s yet, so no buildings can grow. Build a %s." % [other,
				Services.KINDS[Services.Kind.WELL if other == "water" else Services.Kind.POWER_FEED].name])
	else:
		var homes := 0
		var covered := 0
		for key in sim.buildings:
			if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
				homes += 1
				if sim.services.served.get(key, {}).get(b.kind, false):
					covered += 1
		rows.append(["Reach by road", "%.1f miles" % (float(k.reach) * sim.services.funding(id, Balance.POLICY_EFFECT) / 1609.0)])
		rows.append(["Homes covered", "%d of %d" % [covered, homes]])
		if not linked:
			problems.append("Not beside a road, so it can't respond.")
		status = "Working: covering %d homes" % covered if ok else "Not working"
		rows.append_array(sim.buses.school_rows(id))
	rows.append(["Upkeep", "$%s / month" % CitySim.money_text(sim.services.upkeep_of(id))])
	rows.append(["Built for", "$%s" % CitySim.money_text(int(k.cost))])
	var going_up := sim.construction.describe("svc:%d" % id, sim.tick_count)
	if going_up != "":
		rows.append(["Building", going_up.trim_prefix("Under construction: ")])
	return {"title": k.name, "kind": "Utility" if k.has("utility") else "City service", "icon": k.icon,
		"ok": ok and problems.is_empty(), "status": status, "rows": rows, "problems": problems}


static func _farm(sim: CitySim, id: int) -> Dictionary:
	var f: Dictionary = sim.farms.farms[id]
	var acres: float = f.cells.size() * Farms.ACRES_PER_CELL
	var profit := sim.farms.yearly_profit(id)
	var rows := [
		["Crop", str(f.crop).capitalize()],
		["Fields", "%d (%.0f acres)" % [f.cells.size(), acres]],
		["Jobs", str(2 + f.cells.size() / Farms.CELLS_PER_WORKER)],
		["Profit", "%s$%s / year" % ["" if profit >= 0.0 else "-", CitySim.money_text(absi(roundi(profit)))]],
		["Property tax to town", "$%s / month" % CitySim.money_text(roundi(acres * Farms.LAND_PER_ACRE
			* Farms.AG_ASSESSMENT * sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))],
	]
	var problems := []
	var status := "Growing: buying land where the soil pays"
	if not f.barn:
		status = "Putting up the barn"
	elif f.cells.is_empty():
		status = "Looking for good soil nearby"
		problems.append("No fertile free land near the farmhouse yet. Check the Fertility view.")
	elif profit < 0.0:
		status = "Losing money: will sell its worst field"
	rows.append_array(_development(sim, f, Agency.TREES.farm, f.pos, profit))
	rows.append_array(sim.families.rows(sim, "farm:%d" % id))
	return {"title": _named(sim, "farm:%d" % id, "Farm"), "kind": "Farming", "icon": "farms", "ok": problems.is_empty() and profit >= 0.0,
		"status": status, "rows": rows, "problems": problems}


static func _industry(sim: CitySim, id: int) -> Dictionary:
	var s: Dictionary = sim.industry.sites[id]
	var k: Dictionary = Industry.KINDS[s.kind]
	var b: Dictionary = Balance.INDUSTRY[s.kind]
	var rate := 0.0
	for c in s.pads:
		rate += b.loads * Industry.richness(s, c)
	rate *= Agency.effect(s, Agency.TREES[s.kind], "output*")
	var profit := sim.industry.yearly_profit(id)
	var ref := "site:%d" % id
	var rows := [
		["%s%ss" % [k.pad.substr(0, 1).to_upper(), k.pad.substr(1)], str(s.pads.size())],
		["Output", "%.1f truckloads of %s / month" % [rate, k.cargo]],
		["Waiting in the yard", "%d loads" % floori(s.stock)],
		["Trucks on the road", str(sim.logistics.trucks_for(ref))],
		["Jobs", str(b.jobs_hq + b.jobs_pad * s.pads.size() + int(Agency.effect(s, Agency.TREES[s.kind], "jobs+")))],
		["Profit", "%s$%s / year" % ["" if profit >= 0.0 else "-", CitySim.money_text(absi(roundi(profit)))]],
		["Property tax to town", "$%s / month" % CitySim.money_text(roundi((float(k.cost) + Industry.PAD_VALUE * s.pads.size())
			* sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))],
	]
	var problems := []
	var status := "Working: opens %ss where the ground is richest" % k.pad
	if s.pads.is_empty():
		status = "Surveying for its first %s" % k.pad
		if s.get("idle", "") != "":
			status = "Idle: no ground worth a %s" % k.pad
			problems.append(s.idle)
	if sim.logistics.stuck.has(ref):
		problems.append("Its trucks can't reach a buyer or the highway. Connect its road to the rest of town.")
	rows.append_array(_development(sim, s, Agency.TREES[s.kind], s.pos, profit))
	if s.stock >= Industry.stock_cap(s):
		problems.append("The yard is full, so it has stopped producing.")
	rows.append_array(sim.families.rows(sim, ref))
	return {"title": _named(sim, ref, k.name), "kind": k.name if sim.families.owned.has(ref) else "Resource industry", "icon": s.kind, "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}


static func _warehouse(sim: CitySim, id: int) -> Dictionary:
	var w: Dictionary = sim.warehouses.buildings[id]
	var k: Dictionary = Warehouses.KINDS[w.kind]
	var cap := Warehouses.capacity(w)
	var ref := "wh:%d" % id
	var held := []
	for cat in [Warehouses.RAW, Warehouses.GOODS]:
		var goods: Array = w.stock[cat].keys()
		goods.sort()
		for good in goods:
			held.append("%d %s" % [int(w.stock[cat][good]), good])
	var sqft := roundi(float(Warehouses.spec(w).w) * Warehouses.building_depth(w) * 10.764 / 1000.0)
	var rows := [
		["Size", "%s,000 sq ft, %d ft clear" % [sqft, roundi(Balance.WAREHOUSE_HEIGHTS[int(w.level)] * 3.281)]],
		["Stored", "%d of %d truckloads" % [Warehouses.stored(w), cap]],
		["In stock", ", ".join(held) if not held.is_empty() else "Empty"],
		["On the way in", "%d loads" % int(w.incoming)],
		["Trucks on the road", str(sim.logistics.trucks_for(ref))],
		["Dock doors", str(int(Warehouses.spec(w).docks))],
		["Jobs", str(Warehouses.job_count(w))],
		["Profit", "$%s / year" % CitySim.money_text(roundi(Warehouses.yearly_profit(w)))],
		["Property tax to town", "$%s / month" % CitySim.money_text(roundi(Warehouses.value(w)
			* sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))],
	]
	rows.append_array(_development(sim, w, Warehouses.TREE, w.pos, Warehouses.yearly_profit(w)))
	var problems := []
	var status := "Storing loads until a factory or shop needs them"
	if Warehouses.stored(w) == 0 and int(w.incoming) == 0:
		status = "Waiting for its first load"
	elif Warehouses.fill(w) >= Balance.WAREHOUSE_BUSY:
		status = "Nearly full: it will build up or out"
		if w.get("boxed", "") != "":
			status = "Full, and can't grow"
			problems.append(w.boxed)
	if int(w.bays) > 0:
		status += " · grown %d bay%s" % [w.bays, "" if int(w.bays) == 1 else "s"]
	if sim.logistics.stuck.has(ref):
		problems.append("Its trucks can't reach a buyer. Connect its road to the rest of town.")
	return {"title": k.name, "kind": "Warehouse  ·  " + k.area, "icon": "warehouse", "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}


static func _park(sim: CitySim, id: int) -> Dictionary:
	var s: Dictionary = sim.parks.sites[id]
	var k: Dictionary = Parks.KINDS[s.kind]
	var a: Dictionary = Balance.AMENITIES[s.kind]
	var tier: Dictionary = Neighborhood.TIERS[maxi(s.tier, 0)]
	var q := sim.parks.quality(id)
	var rows := [["Neighborhood", "%s (%d%%)" % [tier.name, roundi(s.score * 100.0)]]]
	var status := "A town landmark"
	if s.kind == "park":
		var names := Parks.FEATURE_NAMES
		var has := []
		for f in s.features:
			if names.has(f.type):
				has.append(names[f.type])
		var next := ""
		for f in sim.parks.wanted_features(id):
			if not sim.parks.has_feature(id, f.type):
				next = names.get(f.type, f.type)
				break
		rows.append(["Size", "%.1f acres" % sim.parks.acres(id)])
		rows.append(["Has", ", ".join(has) if not has.is_empty() else "Just lawn and trees so far"])
		status = ("Filling in: %s next" % next) if next != "" else "Filled in"
		status += {"struggling": ", worn and patchy", "working": ", plain and tidy", "comfortable": ", well kept",
			"thriving": ", lovingly curated"}.get(tier.key, "")
		var l: Dictionary = s.leader
		rows.append(["Park board", "chaired by %s, %s" % [l.name, Education.leader_style(l)]])
		if str(s.get("why", "")) != "":
			rows.append(["Last move", s.why])
		# Its development tree, a branch a row.
		rows.append_array(sim.parks.tree_status(sim, id))
	var biz := Tourism.business(s.kind)
	if not biz.is_empty():
		return {"title": s.name, "kind": k.name, "icon": k.icon, "ok": true,
			"status": "Opened for the visitors to town's events", "rows": [["Jobs", str(biz.jobs)],
				["Assessed value", "$%s" % CitySim.money_text(int(biz.value))],
				["Visitors from out of town", "%s a year" % CitySim.money_text(roundi(sim.parks.tourism.outside_year()))]],
			"problems": []}
	if sim.parks.tourism.venues.has(id):
		status = _venue(sim, id, rows)
	if s.kind == "trailhead":
		status = _trails(sim, id, rows)
	rows.append(["Land value nearby", "up to +%d%%" % roundi((float(a.value) * q + sim.parks.tree_lift(id, "value")) * 100.0)])
	rows.append(["Happiness nearby", "up to +%d%%" % roundi((float(a.happy) * q + sim.parks.tree_lift(id, "happy")) * 100.0)])
	rows.append(["Upkeep", "$%s / month" % CitySim.money_text(roundi(sim.parks.site_upkeep(id)))])
	return {"title": s.name, "kind": "Park" if s.kind == "park" else "Landmark  ·  " + k.name, "icon": k.icon,
		"ok": true, "status": status, "rows": rows, "problems": []}


## A venue's rows (who runs it, its events and crowds, its gate money and
## its development tree). Returns its status line.
static func _venue(sim: CitySim, id: int, rows: Array) -> String:
	var t := sim.parks.tourism
	var v: Dictionary = t.venues[id]
	var s: Dictionary = sim.parks.sites[id]
	var who := "Fair board" if v.kind == "fairgrounds" else "Boosters"
	rows.append([who, "led by %s, %s" % [v.leader.name, Education.leader_style(v.leader)]])
	var events := []
	for m in range(1, 13):
		var ev := t.event_in(id, m)
		if not ev.is_empty():
			events.append("%s (%s)" % [ev.name, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
				"Nov", "Dec"][m - 1]])
	rows.append(["Events", ", ".join(events)])
	rows.append(["Visitors this year", "%s (%s from out of town)" % [CitySim.money_text(roundi(v.visitors)),
		CitySim.money_text(roundi(v.outside))]])
	if float(v.visitors_last) > 0.0:
		rows.append(["Last year", "%s visitors" % CitySim.money_text(roundi(v.visitors_last))])
	rows.append(["Gate money saved", "$%s" % CitySim.money_text(roundi(v.savings))])
	# The tree rows, without the "Run by ... owner" line (shown above).
	var h := v.duplicate()
	h.erase("leader")
	rows.append_array(_development(sim, h, Balance.VENUE_TREES[v.kind], s.pos, v.profit))
	if not v.crowd.is_empty():
		return "%s on now: %s people" % [v.crowd.name, CitySim.money_text(int(v.crowd.visitors))]
	return "Between events"


## The trailhead's rows: its director, the trails and bike lanes so far,
## the trips they take off the road, and the tree. Returns its status line.
static func _trails(sim: CitySim, id: int, rows: Array) -> String:
	var t := sim.parks.trails
	if t.hub.is_empty() or int(t.hub.id) != id:
		return "Where the town's trails start"
	rows.append(["Parks and trails", "director %s, %s" % [t.hub.leader.name, Education.leader_style(t.hub.leader)]])
	var connectors := t.paths.filter(func(p): return p.kind == "connector").size()
	var miles := t.length() / 1609.34
	rows.append(["Trails", "%.1f mi%s" % [miles, (", %d to parks" % connectors) if connectors > 0 else ""]])
	if not t.lanes.is_empty() or "bike_lanes" in t.hub.built:
		rows.append(["Bike lanes", "%d streets%s" % [t.lanes.size(), ", one waiting on you" if not t.asked.is_empty() else ""]])
	if t.walked_last > 0 or t.walked > 0:
		rows.append(["Trips on foot or by bike", "%s last month" % CitySim.money_text(maxi(t.walked_last, t.walked))])
	if str(t.hub.why) != "":
		rows.append(["Last move", t.hub.why])
	rows.append_array(t.status(sim))
	if miles < 0.05:
		return "Planning the first trail"
	return "%.1f miles of trail" % miles


## A power company: its leader and why they built what they did, what it
## makes and sells, and its development tree (built, saving up, or what it
## still needs).
static func _power(sim: CitySim, id: int) -> Dictionary:
	var s: Dictionary = sim.power.sites[id]
	var k: Dictionary = Power.PLANTS[s.plant]
	var sold: Dictionary = sim.power.sales.get(id, {})
	var profit: float = sold.get("profit", 0.0)
	var rows := [
		["Leader", "%s (%s)" % [s.leader.name, Power.schooling(s.leader)]],
		["%s%ss" % [k.unit.substr(0, 1).to_upper(), k.unit.substr(1)], "%d of %d" % [s.cells.size(), int(k.max_cells)]],
		["Makes", "power for %s homes" % CitySim.money_text(sim.power.capacity(id))],
		["Sold in town", "%s homes" % CitySim.money_text(int(sold.get("town", 0)))],
		["Sold to the region", "%s homes" % CitySim.money_text(int(sold.get("export", 0)) + int(sold.get("neighbor", 0)))],
		["Jobs", str(roundi(Balance.POWER_YARD_JOBS + float(k.jobs) * s.cells.size()))],
		["Profit", "%s$%s / year" % ["" if profit >= 0.0 else "-", CitySim.money_text(absi(roundi(profit)))]],
	]
	var ctx := sim.power_context()
	rows += _development(sim, s, sim.power.tree_for(id, ctx), s.pos, profit)
	# What the tree still needs that the town or land can't give yet.
	for node in Power.TREE:
		var why := sim.power.gate_problem(id, node, ctx)
		if not node.id in s.built and why != "" and not why.begins_with("Only for"):
			rows.append([node.name, why])
	var problems := []
	if s.get("idle", "") != "":
		problems.append(s.idle)
	if float(k.value) < 0.0:
		problems.append("Its smoke lowers land value up to %d m away." % int(k.reach))
	var title: String = "%s %s" % [s.leader.name.split(" ")[-1], k.name.to_lower()]
	return {"title": title, "kind": "Power company: " + sim.power.status(id), "icon": "power",
		"ok": s.get("idle", "") == "", "status": s.reason, "rows": rows, "problems": problems}


## Rows on a hub's leader and development tree: who runs it, what they've
## built, why they made their last move, and what's open to them next.
static func _development(sim: CitySim, hub: Dictionary, tree: Array, at: Vector3, profit: float) -> Array:
	var rows := []
	var lead: Dictionary = hub.get("leader", {})
	if not lead.is_empty():
		var school := "college" if float(lead.edu) >= 0.6 else ("some college" if float(lead.edu) >= 0.4 else "high school")
		var style := "careful" if float(lead.caution) > 0.6 else ("ambitious" if float(lead.ambition) > 0.6 else "steady")
		rows.append(["Run by", "a %s owner, %s" % [style, school]])
	var built := []
	for node in tree:
		if node.id in hub.get("built", []):
			built.append(node.name)
	rows.append(["Built", ", ".join(built) if not built.is_empty() else "Nothing extra yet"])
	if str(hub.get("why", "")) != "":
		rows.append(["Last move", hub.why])
	var next := []
	for node in Agency.open(sim, hub, tree, at, profit):
		next.append(node.name)
	rows.append(["Could build next", ", ".join(next) if not next.is_empty() else "Nothing yet: needs more profit, schooling or neighbours"])
	return rows


static func _lot(sim: CitySim, key: String) -> Dictionary:
	var lot: Dictionary = sim.lots[key]
	var zone := sim.zones.zone_at(lot.zone_pt)
	var s: Dictionary = sim.services.served.get(key, {})
	var power: bool = s.get("power", false)
	var water: bool = s.get("water", false)
	var rows := []
	var problems := []
	if not power:
		problems.append("No power. " + ("The power line can't carry more homes." if s.get("power_linked", false)
			else "Build a Power line feed on a connected street."))
	var by: int = s.get("water_by", -1)
	if not water:
		problems.append("No water. " + ("The water system is full." if s.get("water_linked", false)
			else "The water utility hasn't laid a main under this street yet." if not sim.services.water.utilities.is_empty()
			else "Build a Well on a connected street."))
	rows.append(["Power", "Yes" if power else "No"])
	var smoke := sim.power.smoke_from(lot.pos)
	if smoke != -1:
		rows.append(["Land value", "%d%% (smoke from the %s)" % [roundi(sim.power.land_value_effect(lot.pos) * 100.0),
			Power.PLANTS[sim.power.sites[smoke].plant].name.to_lower()]])
	rows.append(["Water", "Yes" if water else "No"])
	if by != -1 and sim.services.water.utilities.has(by):
		rows.append(["Sewer", "Yes" if s.get("sewer", false) else "Septic tank"])
		if sim.services.water.utilities[by].boil and water:
			problems.append("Boil-water notice: the water utility's pipes are in poor repair.")
	var smell := sim.services.water.odor_at(sim.services.buildings, lot.pos)
	if smell > 0.1:
		problems.append("The sewer plant smells here, so the land is worth %d%% less." % roundi(
			100.0 * (1.0 - sim.services.water.land_value_factor(sim.services.buildings, lot.pos))))
	if not sim.buildings.has(key):
		var status := "Empty lot, waiting to be built"
		if not problems.is_empty():
			var lacks := []
			if not power:
				lacks.append("power")
			if not water:
				lacks.append("water")
			status = "Can't be built: no " + " or ".join(lacks)
		elif sim.demand.get(zone, 0.0) < 0.05:
			status = "Empty: no demand for %s right now" % ZoneMap.NAMES[zone].to_lower()
		return {"title": "Empty lot", "kind": "Zoned " + ZoneMap.NAMES[zone].to_lower(), "icon": "zones",
			"ok": problems.is_empty(), "status": status, "rows": rows, "problems": problems}
	var b: Dictionary = sim.buildings[key]
	var z := int(b.zone)
	var status := ""
	if z == ZoneMap.Zone.RESIDENTIAL:
		rows.push_front(["Residents", "%d of %d" % [b.occ, b.cap]])
		status = "Lived in" if b.occ > 0 else "Waiting for residents"
		if problems.size() > 0:
			status = "People are moving out" if b.occ > 0 else "Nobody can move in"
		var cover := []
		for kind in Services.COVERAGE:
			if s.get(kind, false):
				cover.append(Services.KINDS[kind].name.split(" ")[0])
		rows.append(["Services nearby", ", ".join(cover) if not cover.is_empty() else "None"])
	else:
		rows.push_front(["Jobs", str(b.cap)])
		if z == ZoneMap.Zone.INDUSTRIAL:
			var chain: Dictionary = Balance.FACTORY_CHAINS[b.get("chain", "general")]
			rows.push_front(["Makes", "%s from %s" % [chain.makes.capitalize(), chain.input]])
			rows.append(["%s in the yard" % chain.input.capitalize(), "%d loads" % floori(sim.logistics.stock.get(key, 0.0))])
		rows.append(["Trucks on the road", str(sim.logistics.trucks_for("lot:" + key))])
		status = "Open for business" if problems.is_empty() else "Closed: no power or water"
	if int(b.get("flats", 0)) > 0:
		rows.insert(1, ["Flats upstairs", "%d of %d residents" % [int(b.focc), int(b.flats)]])
	if BuildingTypes.storeys(b) > 0:
		rows.insert(0, ["Storeys", str(BuildingTypes.storeys(b))])
	var address := sim.streets.address(sim, key)
	if address != "":
		rows.insert(0, ["Address", address])
	if str(b.get("why", "")) != "":
		rows.append(["Why this", b.why])
	var next := []
	for o in BuildingTypes.options(sim, key):
		next.append(BuildingTypes.TYPES[o[0]].stages[o[1]].name)
	rows.append(["Can grow into", ", ".join(next) if not next.is_empty() else "Nothing yet"])
	var going_up := sim.construction.describe("lot:" + key, sim.tick_count)
	if going_up != "":
		status = going_up
	var staffed := float(sim.stats.employed) / maxf(sim.stats.jobs, 1.0)
	var lift: float = sim.parks.lot_value.get(key, 0.0)
	var land := sim.land_factor(key) * sim.mail.lot_factor(sim, key) * (1.0 + lift)
	if absf(land - 1.0) >= 0.005:
		rows.append(["Land value nearby", "%+d%%" % roundi((land - 1.0) * 100.0)])
	if lift > 0.005:
		rows.append(["From parks and landmarks", "+%d%%" % roundi(lift * 100.0)])
	if not sim.mail.offices.is_empty():
		rows.append(["Mail", "Delivered" if sim.mail.served(sim, sim.lots[key].seg) else "Not lately"])
	rows.append(["Property tax", "$%s / month" % CitySim.money_text(roundi(sim.economy.building_tax(b, staffed, lift)
		* sim.land_factor(key) * sim.mail.lot_factor(sim, key) / 12.0))])
	var mail := sim.mail.lot_problem(sim, key)
	if mail != "":
		problems.append(mail)
	var trash := sim.hubs.lot_problem(sim, key)
	if trash != "":
		problems.append(trash)
	var icons := {ZoneMap.Zone.RESIDENTIAL: "homes", ZoneMap.Zone.COMMERCIAL: "shops", ZoneMap.Zone.INDUSTRIAL: "industry"}
	var title: String = BuildingTypes.name_of(b)
	var kind: String = BuildingTypes.TYPES[BuildingTypes.type_of(b)].name
	if z == ZoneMap.Zone.INDUSTRIAL:
		title = Balance.FACTORY_CHAINS[b.get("chain", "general")].name
	var ref := "lot:" + key
	if sim.families.owned.has(ref):
		rows.insert(0, ["Building", title])
		kind = Names.trade_word(sim.families.owned[ref].what).capitalize() if z == ZoneMap.Zone.COMMERCIAL else title
		title = sim.families.name_of(ref)
		rows.append_array(sim.families.rows(sim, ref))
	elif z == ZoneMap.Zone.RESIDENTIAL:
		rows.insert(0, ["Building", title])
		title = Families.home_name(b)
	return {"title": title, "kind": kind, "icon": icons[z], "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}


## A business's own name if it has one ("Miller Farms"), else `plain`.
static func _named(sim: CitySim, ref: String, plain: String) -> String:
	var n := sim.families.name_of(ref)
	return n if n != "" else plain


static func _road(sim: CitySim, seg: int) -> Dictionary:
	var s: Dictionary = sim.network.segments[seg]
	var spec: Dictionary = RoadStyle.TYPES[s.type]
	var c := sim.network.curve_of(seg)
	var m := RoadNetwork.polyline_length(RoadNetwork.sample_curve(c[0], c[1], c[2]))
	var cars := 0
	var speed := 0.0
	var n := 0
	for wid in [seg * 2, seg * 2 + 1]:
		if sim.traffic.ways.has(wid):
			speed += sim.traffic.way_speed(wid)
			n += 1
	for car in sim.traffic.cars:
		if car.j == null and int(car.route[car.leg]) / 2 == seg:
			cars += 1
	var flow := 1.0 if n == 0 else speed / n
	var rows := [
		["Length", "%d m (%.2f mi)" % [roundi(m), m / 1609.0]],
		["Lanes", "%d%s" % [spec.lanes, ", one way" if s.oneway else ""]],
		["Speed limit", "%d mph" % spec.mph],
		["Cars on it now", str(cars)],
		["Traffic flow", "%d%%" % roundi(flow * 100.0)],
		["Upkeep", "$%s / month" % CitySim.money_text(roundi(Economy.road_upkeep(c, s.type)))],
	]
	var problems := []
	if flow < 0.5:
		problems.append("Congested: cars manage under half the speed limit.")
	var street := sim.streets.name_of(seg)
	return {"title": street if street != "" else spec.name, "kind": spec.name if street != "" else "Road", "icon": "road", "ok": problems.is_empty(),
		"status": "Flowing freely" if flow >= 0.8 else ("Busy" if flow >= 0.5 else "Jammed"),
		"rows": rows, "problems": problems}
