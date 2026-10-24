extends SceneTree
## Run: godot --headless -s tests/test_road_warning.gd
## A road that would wipe out a park, homes or a hub says so on its preview
## and is built only on a second click (Brawn 2026-10-24: a grid drawn over
## a park that had grown for years took it with no warning).

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-300, 301, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	var site := Parks.site_near(sim.network, "park", Vector3(0, 0, 40))
	sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var park: Dictionary = sim.parks.sites.values()[0]
	var homes := sim.buildings.size()
	_check(homes > 0, "homes built north of the road (%d)" % homes)

	# Through the park, and through the homes.
	var p: Vector3 = park.pos
	var across := [[p + Vector3(-80, 0, 0), p, p + Vector3(80, 0, 0)]]
	var losses := sim.road_losses(across, RoadStyle.Type.STREET)
	_check(losses.any(func(l): return l.what == park.name), "a road through the park names it (%s)" % RoadWins.loss_text(losses))
	var north := [[Vector3(-200, 0, -25), Vector3(0, 0, -25), Vector3(200, 0, -25)]]
	var lost := sim.road_losses(north, RoadStyle.Type.STREET)
	_check(lost.any(func(l): return l.what == "Home"), "a road down the block counts its homes (%s)" % RoadWins.loss_text(lost))
	# Clear ground: no warning.
	var far := [[Vector3(-200, 0, 600), Vector3(0, 0, 600), Vector3(200, 0, 600)]]
	_check(sim.road_losses(far, RoadStyle.Type.STREET).is_empty(), "open ground warns about nothing")
	_check(RoadWins.loss_text([{"what": "Lincoln Park", "named": true}, {"what": "Home"}, {"what": "Home"},
		{"what": "Farmhouse"}]) == "Lincoln Park, 2 homes and a farmhouse", "the warning reads plainly")

	# The tool asks first, then builds on the second click; right click backs out.
	var tool := RoadTool.new()
	tool.sim = sim
	tool.network = sim.network
	var built := [0]
	var go := func() -> void: built[0] += 1
	tool._ask_first(p, across, RoadStyle.Type.STREET, go)
	_check(built[0] == 0 and tool.is_drawing(), "the first click only asks")
	tool._cancel()
	_check(built[0] == 0 and not tool.is_drawing(), "right click goes back without building")
	tool._ask_first(p, across, RoadStyle.Type.STREET, go)
	tool._click()
	_check(built[0] == 1, "the second click builds it")
	tool._ask_first(p, far, RoadStyle.Type.STREET, go)
	_check(built[0] == 2, "a road that takes nothing builds at once")
	tool.free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
