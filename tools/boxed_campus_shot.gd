extends "res://tools/screenshot.gd"
## A bank, a high school or the phone company boxed in by four streets,
## filled in up to the sidewalk, and saves a picture. "before" leaves out
## its edge pieces (how it looked until 2026-10-26), "after" keeps them.
## Run: godot --resolution 1600x900 -s tools/boxed_campus_shot.gd -- out.png yaw_deg pitch_deg dist
## before|after bank|telecom|campus [look_x look_z (from the block's middle)]

const KINDS := {
	"bank": {"cell": Banks.CELL, "side": 14.0, "back": 20.0},
	"telecom": {"cell": Telecom.CELL, "side": 15.0, "back": 22.0},
	"campus": {"cell": Education.CELL, "side": 30.0, "back": 45.0},
}


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.simulate_traffic = false
	var args := OS.get_cmdline_user_args()
	var before := args.size() > 4 and args[4] == "before"
	var kind: String = args[5] if args.size() > 5 else "bank"
	var k: Dictionary = KINDS[kind]
	var row := RoadStyle.right_of_way_half(RoadStyle.Type.STREET) + CivicHubs.SETBACK
	var x: float = k.cell * 0.5 + k.side + row
	var d: float = row + k.cell + k.back + row
	# Clear of the starter town's roads: the block's front street runs along
	# z = OZ, the block behind it.
	var oz := 700.0
	var ring := [[[-x, oz], [x, oz]], [[x, oz], [x, oz - d]], [[x, oz - d], [-x, oz - d]], [[-x, oz - d], [-x, oz]]]
	# Streets running on out of the block, with houses along them.
	var out := [[[x, oz], [x + 250, oz]], [[x, oz], [x, oz + 160]], [[-x, oz], [-x, oz + 160]], [[-x - 250, oz], [-x, oz]],
		[[x, oz - d], [x + 250, oz - d]], [[-x - 250, oz - d], [-x, oz - d]]]
	for r in ring + out:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})
	for p in [Vector3(x + 120, 0, oz + 25), Vector3(x + 25, 0, oz + 80), Vector3(-x - 25, 0, oz + 80),
			Vector3(-x - 120, 0, oz + 25), Vector3(0, 0, oz + 25), Vector3(x + 120, 0, oz - 40), Vector3(-x - 120, 0, oz - 40)]:
		for r in range(-100, 101, 15):
			var q: Vector3 = p + (Vector3(r, 0, 0) if absf(p.z - oz - 80) > 1.0 else Vector3(0, 0, r * 0.6))
			sim.apply({"type": "paint_zone", "center": [q.x, q.z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var hit := Vector3(0, 0, oz - 20)
	var hubs: Dictionary
	match kind:
		"bank":
			var s := Banks.site_near(sim.network, hit)
			sim.apply({"type": "place_bank", "kind": "community", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			hubs = sim.banks.banks
		"telecom":
			var s := Telecom.site_near(sim.network, hit)
			sim.apply({"type": "place_telecom", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			hubs = sim.telecom.companies
		_:
			var s := Education.site_near(sim.network, hit)
			sim.apply({"type": "place_campus", "kind": "high_school", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			hubs = sim.education.campuses
	var id: int = hubs.keys()[0]
	var hub: Dictionary = hubs[id]
	sim.require_utilities = false
	for i in 900:
		sim.tick()
	# Its leader's round: boxed in, it takes its edge pieces.
	match kind:
		"bank": sim.banks.take_edges(sim, id)
		"telecom": sim.telecom.take_edges(sim, id)
		_: sim.education.take_edges(sim, id)
	if before:
		hub.edge = {}
	sim.banks_changed.emit()
	sim.telecom_changed.emit()
	sim.education_changed.emit()
	sim.zones_changed.emit()
	# Midday in summer, clear of the morning fog (as the parks' picture); no
	# tour moving the camera.
	sim.tick_count = 1860
	_main.set_speed(0)
	for n in _main.find_children("*", "FirstTownTour", true, false):
		n.stop()
	print("%s: %d blocks, %d edge pieces %s" % [kind, hub.blocks.size(), hub.edge.size(), str(hub.edge.keys())])
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var off := Vector3(float(args[6]), 0, float(args[7])) if args.size() >= 8 else Vector3.ZERO
			c.look_at_point(Vector3(0, 0, oz - d * 0.5) + off)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
