class_name Inspect
extends RefCounted
## What the player clicked and everything worth knowing about it, like the
## selected-object panel in Cities: Skylines 2: whether it works, what it
## serves or makes, its people, costs and any problem in plain words.
## Plain data, so tests can read it and any interface can show it.


## The thing under a ground point: {type: "service"|"farm"|"lot"|"road", id},
## or {} for open ground. Buildings win over the road they stand on.
static func pick(sim: CitySim, p: Vector3) -> Dictionary:
	var hid := sim.hubs.at(p)
	if hid != -1:
		return {"type": "hub", "id": hid}
	var sid := sim.services.at(p)
	if sid != -1:
		return {"type": "service", "id": sid}
	var wid := sim.warehouses.at(p)
	if wid != -1:
		return {"type": "warehouse", "id": wid}
	var iid := sim.industry.site_at(p)
	if iid == -1:
		iid = sim.industry.pad_at(p)
	if iid != -1:
		return {"type": "industry", "id": iid}
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
		"service":
			var b: Dictionary = sim.services.buildings[sel.id]
			return [b.pos, Services.KINDS[b.kind].size.length() * 0.5 + 3.0]
		"industry":
			return [sim.industry.sites[sel.id].pos, Industry.HQ_SIZE.length() * 0.5 + 3.0]
		"hub":
			return sim.hubs.extent(sel.id)
		"warehouse":
			var w: Dictionary = sim.warehouses.buildings[sel.id]
			return [Warehouses.center(w), Vector2(Warehouses.site_width(w), Warehouses.site_depth(w)).length() * 0.5 + 3.0]
		"farm":
			return [sim.farms.farms[sel.id].pos, Farms.FARMHOUSE_SIZE.length() * 0.5 + 3.0]
		"lot":
			return [sim.lots[sel.id].pos, LotPlanner.DEPTH * 0.5 + 2.0]
		"road":
			var c := sim.network.curve_of(sel.id)
			return [RoadNetwork.bezier(c[0], c[1], c[2], 0.5), RoadStyle.half_width(sim.network.segments[sel.id].type) + 4.0]
	return []


static func exists(sim: CitySim, sel: Dictionary) -> bool:
	match sel.get("type", ""):
		"service": return sim.services.buildings.has(sel.id)
		"hub": return sim.hubs.hubs.has(sel.id)
		"farm": return sim.farms.farms.has(sel.id)
		"industry": return sim.industry.sites.has(sel.id)
		"warehouse": return sim.warehouses.buildings.has(sel.id)
		"lot": return sim.lots.has(sel.id)
		"road": return sim.network.segments.has(sel.id)
	return false


## {title, kind (a line under the title), icon, ok: bool, status, rows:
## [[label, value]], problems: [text]}.
static func describe(sim: CitySim, sel: Dictionary) -> Dictionary:
	if not exists(sim, sel):
		return {}
	match sel.type:
		"service": return _service(sim, sel.id)
		"hub": return HubInfo.describe(sim, sel.id)
		"farm": return _farm(sim, sel.id)
		"industry": return _industry(sim, sel.id)
		"warehouse": return _warehouse(sim, sel.id)
		"lot": return _lot(sim, sel.id)
		"road": return _road(sim, sel.id)
	return {}


static func _service(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
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
		rows.append(["This building serves", "%s homes" % CitySim.money_text(int(k.capacity))])
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
		rows.append(["Reach by road", "%.1f miles" % (float(k.reach) / 1609.0)])
		rows.append(["Homes covered", "%d of %d" % [covered, homes]])
		if not linked:
			problems.append("Not beside a road, so it can't respond.")
		status = "Working: covering %d homes" % covered if ok else "Not working"
	rows.append(["Upkeep", "$%s / month" % CitySim.money_text(int(k.upkeep))])
	rows.append(["Built for", "$%s" % CitySim.money_text(int(k.cost))])
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
	return {"title": "Farm", "kind": "Farming", "icon": "farms", "ok": problems.is_empty() and profit >= 0.0,
		"status": status, "rows": rows, "problems": problems}


static func _industry(sim: CitySim, id: int) -> Dictionary:
	var s: Dictionary = sim.industry.sites[id]
	var k: Dictionary = Industry.KINDS[s.kind]
	var b: Dictionary = Balance.INDUSTRY[s.kind]
	var rate := 0.0
	for c in s.pads:
		rate += b.loads * Industry.richness(s, c)
	var profit := sim.industry.yearly_profit(id)
	var ref := "site:%d" % id
	var rows := [
		["%s%ss" % [k.pad.substr(0, 1).to_upper(), k.pad.substr(1)], str(s.pads.size())],
		["Output", "%.1f truckloads of %s / month" % [rate, k.cargo]],
		["Waiting in the yard", "%d loads" % floori(s.stock)],
		["Trucks on the road", str(sim.logistics.trucks_for(ref))],
		["Jobs", str(b.jobs_hq + b.jobs_pad * s.pads.size())],
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
	if s.stock >= Industry.STOCK_CAP:
		problems.append("The yard is full, so it has stopped producing.")
	return {"title": k.name, "kind": "Resource industry", "icon": s.kind, "ok": problems.is_empty(),
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
		["Jobs", str(roundi(float(Warehouses.spec(w).jobs) * Warehouses.building_depth(w) / float(Warehouses.spec(w).d)))],
		["Property tax to town", "$%s / month" % CitySim.money_text(roundi(Warehouses.value(w)
			* sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))],
	]
	var problems := []
	var status := "Storing loads until a factory or shop needs them"
	if Warehouses.stored(w) == 0 and int(w.incoming) == 0:
		status = "Waiting for its first load"
	elif Warehouses.fill(w) >= Balance.WAREHOUSE_BUSY:
		status = "Nearly full: it will build up or out"
		if w.get("why", "") != "":
			status = "Full, and can't grow"
			problems.append(w.why)
	if int(w.bays) > 0:
		status += " · grown %d bay%s" % [w.bays, "" if int(w.bays) == 1 else "s"]
	if sim.logistics.stuck.has(ref):
		problems.append("Its trucks can't reach a buyer. Connect its road to the rest of town.")
	return {"title": k.name, "kind": "Warehouse  ·  " + k.area, "icon": "warehouse", "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}


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
	if not water:
		problems.append("No water. " + ("The water system is full." if s.get("water_linked", false)
			else "Build a Well on a connected street."))
	rows.append(["Power", "Yes" if power else "No"])
	rows.append(["Water", "Yes" if water else "No"])
	var names := {ZoneMap.Zone.RESIDENTIAL: "Home", ZoneMap.Zone.COMMERCIAL: "Shop", ZoneMap.Zone.INDUSTRIAL: "Factory"}
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
			rows.append(["Raw loads in the yard", "%d" % floori(sim.logistics.stock.get(key, 0.0))])
		rows.append(["Trucks on the road", str(sim.logistics.trucks_for("lot:" + key))])
		status = "Open for business" if problems.is_empty() else "Closed: no power or water"
	var staffed := float(sim.stats.employed) / maxf(sim.stats.jobs, 1.0)
	var land := sim.hubs.lot_factor(sim, key)
	if absf(land - 1.0) >= 0.005:
		rows.append(["Land value nearby", "%+d%%" % roundi((land - 1.0) * 100.0)])
	rows.append(["Property tax", "$%s / month" % CitySim.money_text(roundi(sim.economy.building_tax(b, staffed) * land / 12.0))])
	var trash := sim.hubs.lot_problem(sim, key)
	if trash != "":
		problems.append(trash)
	var icons := {ZoneMap.Zone.RESIDENTIAL: "homes", ZoneMap.Zone.COMMERCIAL: "shops", ZoneMap.Zone.INDUSTRIAL: "industry"}
	return {"title": names[z], "kind": ZoneMap.NAMES[z], "icon": icons[z], "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}


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
	return {"title": spec.name, "kind": "Road", "icon": "road", "ok": problems.is_empty(),
		"status": "Flowing freely" if flow >= 0.8 else ("Busy" if flow >= 0.5 else "Jammed"),
		"rows": rows, "problems": problems}
