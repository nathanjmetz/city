extends SceneTree
## Run: godot --headless -s tests/test_streets.gd

var _failed := false


func _init() -> void:
	var sim := _town()
	var st := sim.streets
	var main_seg := _seg_at(sim, Vector3(-50, 0, 0))
	_check(st.name_of(main_seg) == "Main Street", "the first street is Main Street (%s)" % st.name_of(main_seg))
	_check(st.name_of(_seg_at(sim, Vector3(50, 0, 0))) == "Main Street", "Main runs on through its junctions")
	var cross := st.name_of(_seg_at(sim, Vector3(100, 0, 40)))
	_check(cross.ends_with("Street") and cross[0].is_valid_int(), "a street across Main is numbered (%s)" % cross)
	_check(st.name_of(_seg_at(sim, Vector3(100, 0, -40))) == cross, "and keeps its number across Main")
	var along := st.name_of(_seg_at(sim, Vector3(50, 0, 100)))
	_check(along == "Walnut Street", "a street alongside Main takes an old town name (%s)" % along)
	var ave := st.name_of(_seg_at(sim, Vector3(200, 0, 40)))
	_check(ave.ends_with("Avenue"), "an avenue is an Avenue (%s)" % ave)
	_check(st.name_of(_seg_at(sim, Vector3(-100, 0, 30))) == "", "alleys have no name")

	# A new road cutting across Main leaves both halves Main Street.
	sim.apply({"type": "build_road", "start": [-30, -60], "ctrl": [-30, 0], "end": [-30, 60]})
	_check(st.name_of(_seg_at(sim, Vector3(-60, 0, 0))) == "Main Street"
		and st.name_of(_seg_at(sim, Vector3(-10, 0, 0))) == "Main Street", "cut in two, Main is still Main")
	var names := {}
	for id in sim.network.segments:
		names[id] = st.name_of(id)

	# Every copy agrees, and a save keeps them.
	var twin := _town()
	twin.apply({"type": "build_road", "start": [-30, -60], "ctrl": [-30, 0], "end": [-30, 60]})
	var same := true
	for id in names:
		same = same and twin.streets.name_of(id) == names[id]
	_check(same, "a second copy names every street the same")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	same = true
	for id in names:
		same = same and copy.streets.name_of(id) == names[id]
	_check(same, "a loaded city keeps its street names")

	_check(Streets.county_name(Vector2(-500, -4900), Vector2(500, -4800)) == "County Road 300 N",
		"county roads are numbered on the Indiana grid")
	_check(StreetSignView.short("Walnut Street") == "Walnut St" and StreetSignView.short("3rd Avenue") == "3rd Ave",
		"blades use the MUTCD abbreviations")
	_check(Streets._ordinal(1) == "1st" and Streets._ordinal(12) == "12th" and Streets._ordinal(23) == "23rd", "ordinals")

	var fresh := CitySim.new()
	fresh.build_county_road(Vector2(-800, 0), Vector2(800, 0), [0, 1])
	var hw := fresh.streets.name_of(fresh.network.segments.keys()[0])
	_check(hw.ends_with(" Road") and hw != "Main Street", "the highway a town starts on leads to a real town (%s)" % hw)
	# Lots along Main get addresses: odd on one side, even on the other.
	for x in range(-140, 141, 10):
		for z in [-25, 25]:
			sim.apply({"type": "paint_zone", "center": [x, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 5:
		sim.tick()
	var odd := 0
	var even := 0
	var seen := {}
	for key in sim.lots:
		var a := st.address(sim, key)
		if not a.ends_with("Main Street"):
			continue
		var n := int(a.split(" ")[0])
		_check(n > 0 and not seen.has(a), "each lot has its own address (%s)" % a)
		seen[a] = true
		if n % 2 == 1:
			odd += 1
		else:
			even += 1
	_check(odd > 0 and even > 0, "odd numbers on one side of Main, even on the other (%d, %d)" % [odd, even])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Main Street east-west, two streets crossing it, one alongside, an alley.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = 3
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	sim.apply({"type": "build_road", "start": [100, -100], "ctrl": [100, 0], "end": [100, 100]})
	sim.apply({"type": "build_road", "start": [-150, 100], "ctrl": [0, 100], "end": [150, 100]})
	sim.apply({"type": "build_road", "start": [200, -100], "ctrl": [200, 0], "end": [200, 100], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-100, 30], "end": [-100, 60], "road": RoadStyle.Type.ALLEY})
	return sim


func _seg_at(sim: CitySim, p: Vector3) -> int:
	var hit: Dictionary = sim.network.find_segment_near(p, 6.0)
	return int(hit.get("seg", -1))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
