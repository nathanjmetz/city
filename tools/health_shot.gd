extends SceneTree
## Renders a town with a grown hospital, a nursing home and a daycare.
## Run: godot -s tools/health_shot.gd -- out.png [yaw pitch dist] [level 0-2]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_town()
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "health.png")
		quit()
	return false


func _town() -> void:
	var args := OS.get_cmdline_user_args()
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	for x in range(-380, 381, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for kind in [Services.Kind.POWER_FEED, Services.Kind.WELL]:
		var s := Services.site_near(sim.network, kind, Vector3(-250 if kind == Services.Kind.WELL else -300, 0, 40))
		sim.apply({"type": "place_service", "kind": kind, "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
	for entry in [[Services.Kind.HOSPITAL, 0.0], [Services.Kind.NURSING_HOME, 110.0], [Services.Kind.DAYCARE, -80.0]]:
		var s := Services.site_near(sim.network, entry[0], Vector3(entry[1], 0, 40))
		sim.apply({"type": "place_service", "kind": entry[0], "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
	for i in 800:
		sim.tick()
	var level := int(args[4]) if args.size() > 4 else 2
	var hc := sim.healthcare
	hc.region_pop = 40000
	for key in sim.buildings:
		sim.buildings[key].cap = 120
		sim.buildings[key].occ = 120
	sim.update_stats()
	for id in hc.hubs:
		var h: Dictionary = hc.hubs[id]
		h.leader.edu = 0.9
		h.leader.ambition = 0.5
		for i in 20:
			if int(h.level) >= level and (level < 2 or h.pieces.size() >= 9):
				break
			h.savings = 1e9
			hc.decide(sim)
		print(h.pieces.map(func(p): return p.key), " level ", h.level)
	for i in 4:
		sim.tick()
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(0, 0, 90))
			c.set_view(deg_to_rad(float(args[1]) if args.size() > 1 else 200.0),
				deg_to_rad(float(args[2]) if args.size() > 2 else 40.0), float(args[3]) if args.size() > 3 else 260.0)
