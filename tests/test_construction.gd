extends SceneTree
## Buildings go up in real stages, with real crews and deliveries.
## Run: godot --headless -s tests/test_construction.gd


func _init() -> void:
	# Stages follow from the start tick alone, in order, and then it's done.
	var len := Construction.duration("house")
	_check(len == 28 * Balance.BUILD_TICKS_PER_WEEK, "a house takes 28 real weeks (%d ticks)" % len)
	var last := -1
	var ordered := true
	for t in range(0, len, 7):
		var st := Construction.state_at("house", 100, 100 + t)
		ordered = ordered and int(st.stage) >= last
		last = int(st.stage)
	_check(ordered and last == Construction.STAGES.size() - 1, "stages go in order, ending with landscaping")
	_check(Construction.state_at("house", 100, 100 + len).is_empty(), "then it's finished")
	_check(Construction.duration("barn") < Construction.duration("house")
		and Construction.duration("house") < Construction.duration("civic"), "a pole barn is quicker than a house, a fire station slower")

	# Vehicles drive in real time and a house goes up in under a minute and a
	# half: a crew that can't get there before it's done isn't sent, so a
	# street of new homes never jams the town (Brawn, 2026-10-24).
	var far := CitySim.new()
	far.apply({"type": "build_county_road", "a": [-200, 0], "b": [-200, -900], "links": [1]})
	far.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-190, 191, 10):
		far.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	var most := 0
	for i in 400:
		far.tick()
		most = maxi(most, far.construction.trips.size())
	_check(far.construction.sites.size() > 5 and most == 0,
		"no crew is sent to a house it would reach after it's built (%d sites, %d trips)" % [far.construction.sites.size(), most])
	# A town on the county highway, near the edge of the map: homes go up,
	# crews come, people move in when they're done.
	var sim := CitySim.new()
	sim.apply({"type": "build_county_road", "a": [-200, 0], "b": [-200, -300], "links": [1]})
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-190, 191, 10):
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	most = 0
	for i in 200:
		sim.tick()
		var coming := 0
		for t in sim.construction.trips.values():
			coming += 1 if t.inbound else 0
		most = maxi(most, coming)
	_check(most <= Construction.MAX_ON_ROAD, "never more than %d site trips heading in (%d)" % [Construction.MAX_ON_ROAD, most])
	_check(sim.buildings.size() > 0 and sim.construction.sites.size() == sim.buildings.size(),
		"every new home is a building site (%d of %d)" % [sim.construction.sites.size(), sim.buildings.size()])
	var occupied := 0
	for key in sim.buildings:
		occupied += sim.buildings[key].occ
	_check(occupied == 0, "nobody lives in a house that's still going up")
	var trucks := 0
	for id in sim.construction.trips:
		trucks += 1
	_check(trucks > 0, "crews and deliveries are on the road (%d)" % trucks)
	var kinds := {}
	for car in sim.traffic.cars:
		if car.purpose == "construction":
			kinds[car.kind] = true
	_check(kinds.has("work_pickup"), "the crew comes in a work pickup (%s)" % str(kinds.keys()))
	# Copies stay in step, and a save keeps every site where it was.
	# As the region server does: it and every player reload the same snapshot.
	var snapshot = JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true))
	var sites := sim.construction.sites.size()
	sim = CitySim.new()
	sim.from_dict(snapshot)
	var copy := CitySim.new()
	copy.from_dict(snapshot)
	_check(copy.construction.sites.size() == sites, "a save keeps the building sites")
	for i in 30:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.construction.to_dict()) == JSON.stringify(sim.construction.to_dict()),
		"copies of the city agree on every site")
	for i in len + 200:
		sim.tick()
	occupied = 0
	for key in sim.buildings:
		occupied += sim.buildings[key].occ
	_check(occupied > 0, "finished homes fill (%d people)" % occupied)
	var key: String = sim.buildings.keys()[0]
	_check(sim.construction.is_done("lot:" + key, sim.tick_count), "the first homes are finished")
	var parked := 0
	for s in sim.construction.sites.values():
		parked += s.parked.size()
	# A finished site stays listed only while its trucks are still coming or
	# haven't driven off yet: they never just vanish.
	var lingering := 0
	for ref in sim.construction.sites:
		if sim.construction.is_done(ref, sim.tick_count) and sim.construction.sites[ref].parked.is_empty() \
				and not sim.construction._inbound(ref):
			lingering += 1
	_check(lingering == 0, "finished sites are cleared once their trucks have gone (%d left)" % lingering)
	var info := Inspect.describe(sim, {"type": "lot", "id": sim.buildings.keys()[-1]})
	_check(info.has("status"), "the info panel still works on a building site")

	# The frame comes from the finished building's own shape.
	var house: Array = HouseBuilder.build(7, 3.9)
	var frame := FrameBuilder.build(house[0], "wood")
	var tris := 0
	for m in frame:
		tris += (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_check(frame.size() == FrameBuilder.CHUNKS and tris > 2000, "a house frames in %d pieces (%d triangles)" % [frame.size(), tris])
	var box: AABB = frame[0].get_aabb()
	for m in frame:
		box = box.merge(m.get_aabb())
	var hb: AABB = house[0].get_aabb()
	_check(box.size.y > hb.size.y * 0.6 and box.size.x <= hb.size.x + 1.0,
		"the frame fills the house's shape (%s vs %s)" % [box.size, hb.size])
	_check(FrameBuilder.slab_top(house[0], 0.3) > 0.1, "the slab's top is found from the house itself")
	for kind in ["steel", "pole", "tilt_up"]:
		var f := FrameBuilder.build(CommercialBuilder.build_factory(3, 3.9)[0], kind)
		_check(not f.is_empty(), "a %s frame builds" % kind)

	# Dried in, the windows are set in the wrap: the glass is drawn dark,
	# never wrapped over (critic round: blocks of blank white boxes).
	var built := HouseBuilder.build(5, 6.0, {"width": 18.0, "depth": 36.0}, 0)
	var holder := Node3D.new()
	root.add_child(holder)
	var dry := {"name": "dry_in", "t": 0.9, "frame": "wood", "found": 0.3}
	var site := ConstructionSite.add_to(holder, built, "house", func(): return dry, func(): pass)
	var glass := HouseMaterials.get_mat("glass")
	var dark := 0
	var wrapped := 0
	for i in site._shell.mesh.get_surface_count():
		var m: ShaderMaterial = site._shell.get_surface_override_material(i)
		if site._shell.mesh.surface_get_material(i) == glass:
			dark += 1 if m.get_shader_parameter("glazing") else 0
		else:
			wrapped += 1 if m.get_shader_parameter("wall_color") == ConstructionSite.SHELL.house[0] else 0
	_check(dark == 1 and wrapped > 0, "a dried-in house shows its windows in the wrap (%d glass, %d wrapped)" % [dark, wrapped])
	holder.free()

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
