extends SceneTree
## Run: godot --headless -s tests/test_worn_paths.gd
## People walking a road with no sidewalk wear a dirt path beside it; it
## grows back once they stop, and goes when the road gets sidewalks.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0], "road": RoadStyle.Type.COUNTY})
	var county := -1
	for seg in sim.network.segments:
		if not RoadStyle.TYPES[sim.network.segments[seg].type].get("walk", true):
			county = int(seg)
	_check(county >= 0, "the county road has no sidewalks")
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 60], "end": [0, 120]})
	var street := -1
	for seg in sim.network.segments:
		if int(sim.network.segments[seg].type) == RoadStyle.Type.STREET:
			street = int(seg)
	for seg in sim.network.segments:
		if not RoadStyle.TYPES[sim.network.segments[seg].type].get("walk", true):
			county = int(seg)
	# Walks on a street with sidewalks don't wear anything.
	for i in 50:
		sim.worn.note(sim.network, street, 1)
	_check(sim.worn.foot.is_empty(), "walking a sidewalk wears no path")
	# A handful of walks a day along the county road do.
	var key := county * 2 + 1
	for i in 2:
		sim.worn.note(sim.network, county, 1)
	sim.worn.month(sim)
	_check(sim.worn.level(key) == 0.0, "a couple of walks a day don't show yet (%.0f)" % sim.worn.wear.get(key, 0.0))
	for m in 6:
		for i in 10:
			sim.worn.note(sim.network, county, 1)
		sim.worn.month(sim)
	var lv := sim.worn.level(key)
	_check(lv > 0.9, "ten walks a day wear it bare in a few months (%.2f)" % lv)
	_check(sim.worn.level(county * 2) == 0.0, "only on the side people walk")
	_check(WornPathView.build(sim) != null, "and it's drawn")
	_check(WornPaths.offset(sim.network.segments[county].type) > RoadStyle.half_width(sim.network.segments[county].type) + Junction.SHOULDER,
		"in the grass past the gravel shoulder")
	# Saved and loaded.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(absf(copy.worn.level(key) - lv) < 0.01, "the path is saved")
	# Left alone, the grass grows back.
	for m in 8:
		sim.worn.month(sim)
	_check(sim.worn.level(key) == 0.0, "unwalked, it grows back (%.0f)" % sim.worn.wear.get(key, 0.0))
	# Sidewalks put an end to it.
	for i in 20:
		sim.worn.note(sim.network, county, 1)
	sim.worn.month(sim)
	sim.network.set_type(county, RoadStyle.Type.STREET)
	sim.worn.month(sim)
	_check(sim.worn.wear.is_empty(), "with sidewalks the path is gone")

	# The traffic sim notes real walks along a road with no sidewalk.
	var town := CitySim.new()
	town.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0], "road": RoadStyle.Type.COUNTY})
	town.apply({"type": "build_road", "start": [-600, 0], "ctrl": [-900, 0], "end": [-1200, 0], "road": RoadStyle.Type.COUNTY})
	for x in range(-300, 301, 10):
		town.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-60, 61, 10):
		town.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	for i in 2400:
		town.tick()
	var walked := 0
	for k in town.worn.foot:
		walked += int(town.worn.foot[k])
	for k in town.worn.wear:
		walked += 1
	print("  walks noted on the county road: %d (%d people)" % [walked, town.people.people.size()])
	_check(walked > 0 or town.people.people.size() < 20, "people walking the county road are counted")
	print("FAIL" if _failed else "PASS", " test_worn_paths")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
