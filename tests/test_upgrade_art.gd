extends SceneTree
## Every upgrade a leader builds shows on the ground (Brawn 2026-10-23: an
## oil company's leader was "adding things" and nothing changed at its
## yard). Draws each company and farmstead with and without each step of its
## development tree and checks the drawing changes; then lets a real oil
## company build and checks its add-ons take free ground beside the yard.
## Run: godot --headless -s tests/test_upgrade_art.gd

var _failed := false


func _init() -> void:
	for kind in Agency.TREES:
		var none := _verts(kind, [], {})
		var missing := []
		for node in Agency.TREES[kind]:
			var built := _with_requires(Agency.TREES[kind], node.id)
			var before := _verts(kind, built.filter(func(n): return n != node.id), _spots(kind, built.filter(func(n): return n != node.id)))
			var after := _verts(kind, built, _spots(kind, built))
			if after == before:
				missing.append(node.id)
		_check(missing.is_empty(), "every %s upgrade draws something (%d steps, base %d vertices)%s" % [
			kind, Agency.TREES[kind].size(), none, "" if missing.is_empty() else ": missing " + str(missing)])
	for kind in BigFactories.TREES:
		var missing := []
		for node in BigFactories.TREES[kind]:
			var built := _with_requires(BigFactories.TREES[kind], node.id)
			if _plant_verts(kind, built) == _plant_verts(kind, built.filter(func(n): return n != node.id)):
				missing.append(node.id)
		_check(missing.is_empty(), "every %s plant upgrade draws something%s" % [kind, "" if missing.is_empty() else ": missing " + str(missing)])
	for kind in Industry.ADDONS:
		var bad := []
		for node in Industry.ADDONS[kind]:
			var size: Array = Industry.ADDONS[kind][node][0]
			for at in Industry.ADDONS[kind][node][1]:
				var r := Rect2(at[0] - size[0] * 0.5, at[1] - size[1] * 0.5, size[0], size[1])
				if not Rect2(-40.5, -40.5, 81, 81).encloses(r):
					bad.append(node)
		_check(bad.is_empty(), "%s add-ons stay inside the main building's own 80 m cell %s" % [kind, bad])
	_railroad()
	_services()
	_telecom()
	_warehouse()
	_water()
	_mail()
	_venues()
	_oil_company()
	_done()


## A node and everything it needs before it, in tree order.
func _with_requires(tree: Array, id: String) -> Array:
	var want := {id: true}
	var grew := true
	while grew:
		grew = false
		for n in tree:
			if want.has(n.id):
				for r in n.get("requires", []):
					if not want.has(r):
						want[r] = true
						grew = true
	var out := []
	for n in tree:
		if want.has(n.id):
			out.append(n.id)
	return out


## Add-ons at their first spots that don't overlap.
func _spots(kind: String, built: Array) -> Dictionary:
	var s := {"kind": kind, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "addons": {}}
	var ind := Industry.new()
	ind.sites[1] = s
	for n in built:
		ind.place_addon(1, n, func(_p): return true)
	return s.addons


func _verts(kind: String, built: Array, addons: Dictionary) -> int:
	var parts: Array
	match kind:
		"farm": parts = FarmBuilder.build_farmstead(7, 1, built)
		"forest": parts = ForestryBuilder.mill(7, Industry.HQ_SIZE, built, addons)
		_: parts = IndustryBuilder.build_hq(kind, 7, built, addons)
	var n := 0
	for k in 2:
		var mesh: ArrayMesh = parts[k]
		for i in mesh.get_surface_count():
			n += mesh.surface_get_array_len(i)
	return n


func _plant_verts(kind: String, built: Array) -> int:
	var f := {"kind": kind, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "level": 0, "bays": 0, "built": built}
	var parts := BigFactoryBuilder.build_plant(f, 7, 4.0)
	var n := 0
	for k in 2:
		var mesh: ArrayMesh = parts[k]
		for i in mesh.get_surface_count():
			n += mesh.surface_get_array_len(i)
	return n


## A railroad depot draws each step of its tree (Rail.TREE) in its yard.
func _railroad() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var site := Rail.site_near(sim.network, Vector3(0, 0, 60))
	sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z],
		"axis": [site[2].x, site[2].z]})
	var d: Dictionary = sim.rail.depots.values()[0]
	var view := RailView.new()
	view.sim = sim
	var missing := []
	for node in Rail.TREE:
		var built := _with_requires(Rail.TREE, node.id)
		d.built = built.filter(func(n): return n != node.id)
		view._draw_yards()
		var before: int = view._yard.mesh.surface_get_array_len(0)
		d.built = built
		view._draw_yards()
		if view._yard.mesh.surface_get_array_len(0) == before:
			missing.append(node.id)
	view.free()
	_check(missing.is_empty(), "every railroad upgrade draws something%s" % ["" if missing.is_empty() else ": missing " + str(missing)])


## Bus depots and cab companies draw their trees at their own sites; the few
## steps that show elsewhere are checked where they show.
func _services() -> void:
	var elsewhere := ["shelters", "transfer_center", "park_ride", "hybrids"]
	for pair in [[Services.Kind.BUS_DEPOT, BusNet.TREE], [Services.Kind.TAXI_COMPANY, TaxiCo.TREE]]:
		var size: Vector2 = Services.KINDS[pair[0]].size
		var missing := []
		for node in pair[1]:
			if node.id in elsewhere:
				continue
			var built := _with_requires(pair[1], node.id)
			if _svc_verts(pair[0], size, built) == _svc_verts(pair[0], size, built.filter(func(n): return n != node.id)):
				missing.append(node.id)
		_check(missing.is_empty(), "every %s upgrade draws something%s" % [Services.KINDS[pair[0]].name,
			"" if missing.is_empty() else ": missing " + str(missing)])
	# Hybrids: the company's cabs change from old Crown Victorias.
	var taxis := TaxiCo.new()
	taxis.companies[5] = {"built": ["radio"]}
	var old := taxis.cab_kind(5)
	taxis.companies[5].built.append("hybrids")
	_check(old == "taxi_old" and taxis.cab_kind(5) == "taxi" and VehicleTypes.SPECS.has("taxi_old")
		and VehicleModels.build("taxi_old").get_surface_count() > 0, "hybrid cabs replace the old sedans")
	# At the stops: the transfer center downtown, park-and-ride out of town.
	var sim := CitySim.new()
	sim.services.buildings[9] = {"kind": Services.Kind.BUS_DEPOT, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1)}
	sim.buses.depots[9] = {"built": []}
	for k in 3:
		sim.buses.stops[k + 1] = {"id": k + 1, "pos": Vector3(100.0 + k * 300.0, 0, 0), "dir": Vector3(1, 0, 0),
			"side": 1.0, "depot": 9, "riders": 0.0, "res": 300.0 - k * 100.0, "jobs": 0.0}
	var view := BusView.new()
	view.sim = sim
	var counts := []
	for built in [["shelters"], ["shelters", "transfer_center"], ["shelters", "transfer_center", "park_ride"]]:
		sim.buses.depots[9].built = built
		view._draw_stops()
		counts.append(view._stops.mesh.surface_get_array_len(0))
	view.free()
	_check(counts[1] > counts[0] and counts[2] > counts[1], "the transfer center and park-and-ride show at the stops %s" % [counts])


## The phone company: middle-mile hut at the office, fixed wireless on the
## towers, small cells along its downtown fiber. (Stealth re-dresses poles
## near homes as monopines in TelecomView.)
func _telecom() -> void:
	var off := _mesh_verts(TelecomBuilder.build_office(7, 3.9, []))
	var on := _mesh_verts(TelecomBuilder.build_office(7, 3.9, ["middle_mile"]))
	var bare := _mesh_verts(TelecomBuilder.build_tower("monopole", 7, 10.0))
	var fw := _mesh_verts(TelecomBuilder.build_tower("monopole", 7, 10.0, true))
	var c := {"pos": Vector3.ZERO, "fiber": [{"seg": 1, "pts": [[0.0, 0.0], [2000.0, 0.0]]}]}
	var cells := TelecomView.small_cells(c)
	_check(on > off and fw > bare and cells.size() >= 2 and cells.size() <= 8
		and _mesh_verts(TelecomBuilder.build_small_cell(7)) > 0,
		"the phone company's middle mile, fixed wireless and small cells show (%d cells)" % cells.size())


## A warehouse's inside-the-walls steps show from outside.
func _warehouse() -> void:
	var missing := []
	for id in ["sortation", "robotics", "fulfillment"]:
		var built := _with_requires(Warehouses.TREE, id)
		var w := {"kind": Warehouses.KINDS.keys()[0], "level": 1, "bays": 1, "pos": Vector3.ZERO, "dir": Vector3.FORWARD}
		w.built = built.filter(func(n): return n != id)
		var before := _mesh_verts(WarehouseBuilder.build_warehouse(w, 7, 3.9))
		w.built = built
		if _mesh_verts(WarehouseBuilder.build_warehouse(w, 7, 3.9)) == before:
			missing.append(id)
	_check(missing.is_empty(), "a warehouse's automation shows%s" % ["" if missing.is_empty() else ": missing " + str(missing)])


## The water utility's meters and big main at the tower, nutrient removal
## and biosolids at the plant.
func _water() -> void:
	var view := WaterView.new()
	var b := {"pos": Vector3(500, 0, 500), "dir": Vector3(0, 0, -1)}
	var missing := []
	for pair in [["tower", "meters"], ["tower", "industrial_main"], ["plant", "nutrient"], ["plant", "biosolids"]]:
		var bare := view._spawn(b, pair[0], Vector2i(1, 0), [])
		var with := view._spawn(b, pair[0], Vector2i(1, 0), [pair[1]])
		if with.get_child_count() <= bare.get_child_count():
			missing.append(pair[1])
	view.free()
	_check(missing.is_empty(), "the water utility's upgrades show%s" % ["" if missing.is_empty() else ": missing " + str(missing)])


## The post office's counter steps, electric fleet and air mail show at the
## office; cluster mailboxes replace curb boxes on the longer streets.
func _mail() -> void:
	var missing := []
	var lands := {"more_vans": [Vector2i(2, 0)], "regional_hub": [Vector2i(-2, 0)]}
	for node in ["po_boxes", "passports", "kiosk", "mural", "electric_fleet", "air_mail"]:
		var h := Mail.draft(Vector3.ZERO, Vector3(0, 0, -1))
		h.merge({"built": ["po_boxes", "passports", "more_vans", "regional_hub"], "project": {}, "lands": lands})
		var before := _mesh_verts(PostOfficeBuilder.build_office(h, 7, 3.9))
		if not node in h.built:
			h.built.append(node)
		else:
			h.built.erase(node)
			before = _mesh_verts(PostOfficeBuilder.build_office(h, 7, 3.9))
			h.built.append(node)
		if _mesh_verts(PostOfficeBuilder.build_office(h, 7, 3.9)) == before:
			missing.append(node)
	_check(missing.is_empty(), "the post office's upgrades show%s" % ["" if missing.is_empty() else ": missing " + str(missing)])
	var sim := CitySim.new()
	for i in 20:
		var key := "1:0:%d" % i
		sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL}
		sim.lots[key] = {"pos": Vector3(i * 15.0, 0, 20), "front": Vector3(i * 15.0, 0, 10), "normal": Vector3(0, 0, 1),
			"dir": Vector3(1, 0, 0), "width": 15.0, "seg": 1, "side": 0}
	var h := Mail.draft(Vector3(0, 0, -200), Vector3(0, 0, -1))
	h.merge({"built": [], "project": {}, "lands": {}})
	sim.mail.offices[1] = h
	var view := MailView.new()
	view.setup(sim)
	view._mailboxes()
	var curb := view._boxes.multimesh.instance_count
	h.built.append("cluster_boxes")
	view._mailboxes()
	_check(curb == 20 and view._boxes.multimesh.instance_count == 0 and view._cbus.multimesh.instance_count == 2,
		"cluster mailboxes replace the curb boxes on a long street")
	view.free()


## The football stadium and the fairgrounds draw each step of their trees.
func _venues() -> void:
	for kind in Balance.VENUE_TREES:
		var missing := []
		for node in Balance.VENUE_TREES[kind]:
			var built := _with_requires(Balance.VENUE_TREES[kind], node.id)
			var site := {"kind": kind, "tier": 2, "size": Balance.AMENITIES[kind].size, "name": "Grant County",
				"venue_built": built.filter(func(n): return n != node.id)}
			var before := _all_verts(ParkBuilder.build_site(site, 7, 3.9, "Petersburg"))
			site.venue_built = built
			if _all_verts(ParkBuilder.build_site(site, 7, 3.9, "Petersburg")) == before:
				missing.append(node.id)
		_check(missing.is_empty(), "every %s upgrade draws something%s" % [kind, "" if missing.is_empty() else ": missing " + str(missing)])


func _all_verts(parts: Array) -> int:
	var n := 0
	for p in parts:
		if p is ArrayMesh:
			for i in p.get_surface_count():
				n += p.surface_get_array_len(i)
	return n


func _mesh_verts(parts: Array) -> int:
	var n := 0
	for k in 2:
		var mesh: ArrayMesh = parts[k]
		for i in mesh.get_surface_count():
			n += mesh.surface_get_array_len(i)
	return n


func _svc_verts(kind: int, size: Vector2, built: Array) -> int:
	var parts := CivicBuilder.build_service(kind, 7, size, 3.9, built)
	var n := 0
	for k in 2:
		var mesh: ArrayMesh = parts[k]
		for i in mesh.get_surface_count():
			n += mesh.surface_get_array_len(i)
	return n


func _oil_company() -> void:
	var sim := CitySim.new()
	sim.require_utilities = false
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			var v := Resources.at(Resources.Kind.OIL, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z], "end": [best.x + 1800, best.z]})
	var id := -1
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": "oil", "pos": [best.x + dx, best.z + 30], "dir": [0, -1]}):
			id = sim.industry.sites.keys()[-1]
			break
	_check(id >= 0, "an oil company opens")
	if id < 0:
		return
	var s: Dictionary = sim.industry.sites[id]
	# Its leader has built up the whole tree (as an old save has, from before
	# add-ons took ground): the next round finds each one its ground.
	s.built = Agency.TREES.oil.map(func(n): return n.id)
	sim._develop_hubs()
	var built: Array = s.get("built", [])
	var placed: Dictionary = s.get("addons", {})
	var want := []
	for n in built:
		if Industry.ADDONS.oil.has(n):
			want.append(n)
	_check(built.size() >= 3 and want.size() >= 1, "the leader builds up its tree %s" % [built])
	var all_placed := true
	for n in want:
		all_placed = all_placed and placed.has(n)
	_check(all_placed, "each add-on it built has ground beside the yard %s" % [placed])
	var held := true
	for n in placed:
		var c := Industry.addon_rect(s, n).get_center()
		var p: Vector3 = s.pos + Vector3(-s.dir.z, 0, s.dir.x) * c.x - s.dir * c.y
		held = held and sim.industry.site_at(p) == id
	_check(held, "the company holds the ground its add-ons stand on")
	# A copy loaded from a save draws the same add-ons in the same places.
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(copy.industry.sites[id].get("addons", {}) == placed, "add-ons survive a save")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)


func _done() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
