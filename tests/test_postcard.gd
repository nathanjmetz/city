extends SceneTree
## Run: godot --headless -s tests/test_postcard.gd
## Sending and saving a town quickly: neighbors get a postcard (what they
## draw and trade with, without people, cars, zoning or plans), the region
## keeps the last full copy for its player, and towns pack and save in
## Godot's binary form.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	for i in 30:
		sim.tick()
	var full := sim.to_dict()
	var card := sim.to_dict(true)
	_check(card.get("postcard", false) and not card.has("people") and not card.has("plan") and not card.has("zones"),
		"a postcard leaves out people, plans and zoning")
	_check(full.has("people") and full.has("plan") and not full.has("postcard"), "a full copy has everything")

	# A neighbor loads the postcard: the same buildings, lots, roads and size.
	var back = RegionServer.unpack(RegionServer.pack(card))
	_check(back is Dictionary and back.get("postcard", false), "a postcard packs and unpacks")
	var copy := Region.new_sim()
	copy.from_dict(back)
	_check(copy.buildings.size() == sim.buildings.size() and copy.lots.size() >= sim.buildings.size(),
		"the neighbor's copy has every building on its lot (%d of %d)" % [copy.buildings.size(), sim.buildings.size()])
	_check(copy.network.segments.size() == sim.network.segments.size(), "and every road")
	_check(int(copy.stats.population) == int(sim.stats.population),
		"and the town's size (%d, %d)" % [copy.stats.population, sim.stats.population])
	_check(copy.streets.names.size() == sim.streets.names.size(), "and its street names")

	# The region keeps the full copy for the player while postcards come in.
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.update_city("c1", full)
	r.update_city("c1", card)
	_check(r.city_data("c1").has("people"), "the region keeps the player's last full copy")
	_check(r.postcard_data("c1").get("postcard", false), "and gives neighbors the postcard")
	var for_ann: Dictionary = r.to_dict("c1")
	var for_bob: Dictionary = r.to_dict("")
	_check(for_ann.cities.c1.city.has("people") and not for_bob.cities.c1.city.has("people"),
		"a player gets their own town whole, neighbors get postcards")
	_check(not Region.postcard_of(full).has("people") and full.has("people"), "cutting a postcard leaves the full copy alone")

	# The whole town a few parts at a time: it holds still meanwhile, and
	# comes out the same as all at once.
	var snap := TownSnapshot.new(sim)
	var ticks_before := sim.tick_count
	var road := {"type": "build_road", "start": [400, 400], "ctrl": [450, 400], "end": [500, 400]}
	var roads_before := sim.network.segments.size()
	_check(sim.held and sim.apply(road) and sim.network.segments.size() == roads_before,
		"while it's being saved, the town holds still and a new road waits")
	var frames := 1
	while not snap.step(0.001):
		frames += 1
	_check(frames > 3 and not sim.held, "it's saved over several steps (%d) and then lets go" % frames)
	_check(sim.network.segments.size() > roads_before, "and the road that waited is built")
	var whole = RegionServer.unpack(RegionServer.pack_bytes(snap.bytes()))
	_check(whole is Dictionary and whole.has("people") and int(whole.tick) == ticks_before,
		"the sliced copy unpacks as a whole town")
	var again := CitySim.new()
	again.from_dict(whole)
	_check(again.buildings.size() == sim.buildings.size() and again.people.people.size() == sim.people.people.size(),
		"and loads back whole")

	# Leaving takes it all at once, every part (a player's whole town goes
	# to the region as they leave).
	var last := TownSnapshot.new(sim)
	last.finish()
	var left = RegionServer.unpack(RegionServer.pack_bytes(last.bytes()))
	_check(left is Dictionary and left.keys().size() == sim.to_dict().keys().size() and left.has("roads") and not sim.held,
		"taken all at once on leaving, it's the whole town (%d of %d parts)" % [left.keys().size() if left is Dictionary else 0, sim.to_dict().keys().size()])
	# A cut-short full copy never replaces a town on the server.
	var r2 := Region.new()
	var cid := r2.add_city("p9", "Nine")
	r2.update_city(cid, sim.to_dict())
	r2.update_city(cid, {"version": 2})
	_check(r2.city_data(cid).has("roads"), "a broken full copy doesn't replace the town")

	_saves.call_deferred(sim)


## Saving a town alone: binary, with its name readable on its own (through
## the Session autoload, there once the tree runs).
func _saves(sim: CitySim) -> void:
	var path := "user://test-postcard.city"
	var session = root.get_node("Session")
	var was := [session.current_name, session.save_path]
	session.current_name = "Testville"
	session.save_path = path
	session.save_city(sim, path)
	var meta: Dictionary = session._read_meta(path)
	_check(meta.get("name", "") == "Testville" and int(meta.get("population", -1)) == int(sim.stats.population),
		"a saved town's name and size read without loading it")
	var loaded: Dictionary = session._read(path)
	var again := CitySim.new()
	again.from_dict(loaded)
	_check(again.buildings.size() == sim.buildings.size() and again.people.people.size() == sim.people.people.size(),
		"and the saved town loads back whole")
	session.current_name = was[0]
	session.save_path = was[1]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + what)
	else:
		print("ok: " + what)
