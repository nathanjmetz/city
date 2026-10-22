extends SceneTree
## Renders the game with a small demo town and saves a picture.
## Run: godot -s tools/screenshot.gd -- out.png [yaw_deg pitch_deg dist]

var _main: Node
var _frames := 0


func _initialize() -> void:
	# After the Session autoload is up.
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_demo_town()
	if _frames == 40:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "shot.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		# Render cost, to keep an eye on the web build.
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"  primitives: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		quit()
	return false


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000  # a demo town, built in one go
	var args0 := OS.get_cmdline_user_args()
	if args0.size() >= 5 and args0[4] == "highway":
		_demo_interchange(sim)
		return
	if args0.size() >= 5 and args0[4] == "ramp":
		# The Critic's repro: a straight exit ramp off a one-way highway.
		sim.apply({"type": "build_road", "start": [-250, 200], "ctrl": [0, 200], "end": [250, 200], "road": 3})
		sim.apply({"type": "build_road", "start": [0, 200], "ctrl": [45, 225], "end": [90, 250], "road": 4})
		sim.apply({"type": "build_road", "start": [-250, 40], "ctrl": [0, 40], "end": [250, 40], "road": 3})
		sim.apply({"type": "build_road", "start": [-140, 90], "ctrl": [-50, 60], "end": [0, 40], "road": 4})
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "nopower":
		# Brawn's start: streets zoned, a well built, no power yet.
		sim.apply({"type": "build_grid", "a": [-160, -40], "b": [120, -40], "c": [-160, -220], "block": 140})
		for lot in sim.lots.values():
			sim.apply({"type": "paint_zone", "center": [lot.zone_pt.x, lot.zone_pt.z], "radius": 3, "zone": ZoneMap.Zone.RESIDENTIAL})
		var well := Services.site_near(sim.network, Services.Kind.WELL, Vector3(40, 0, -10))
		sim.apply({"type": "place_service", "kind": Services.Kind.WELL, "pos": [well[0].x, well[0].z], "dir": [well[1].x, well[1].z]})
		sim.economy.money = 100_000
		for i in 30:
			sim.tick()
		for c in _main.get_children():
			if c is Hud:
				c.close_all()
				c._open("zones")
			if c is SelectTool:
				for id in sim.services.buildings:
					c.select({"type": "service", "id": id})
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4].begins_with("industry"):
		# A resource company a few days after it opened: industry_oil, _ore or _forest.
		var kind: String = args0[4].substr(9) if args0[4].length() > 9 else "oil"
		var res: int = Industry.KINDS[kind].resource
		var best := Vector3.ZERO
		var best_v := 0.0
		for x in range(-1500, 1501, 100):
			for z in range(-1500, 1501, 100):
				var v := Resources.at(res, Vector3(x, 0, z))
				if v > best_v:
					best_v = v
					best = Vector3(x, 0, z)
		sim.apply({"type": "build_road", "start": [best.x - 600, best.z - 60], "ctrl": [best.x, best.z - 60], "end": [best.x + 600, best.z - 60]})
		sim.apply({"type": "place_industry", "kind": kind, "pos": [best.x, best.z + 20], "dir": [0, -1]})
		for i in 1440 * 4:
			sim.tick()
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(best + Vector3(float(args0[5]) if args0.size() >= 7 else 0.0, 0, float(args0[6]) if args0.size() >= 7 else 120.0))
				c.set_view(deg_to_rad(float(args0[1])), deg_to_rad(float(args0[2])), float(args0[3]))
		if args0.size() >= 8:
			for c in _main.get_children():
				if c is Hud:
					c.close_all()
			for c in _main.get_children():
				if c is SelectTool:
					c.select({"type": "industry", "id": 1})
		return
	if args0.size() >= 5 and args0[4] == "farms":
		_demo_farms(sim)
		return
	# A main road with a roundabout, and a grid neighborhood beside it.
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": 2})
	sim.apply({"type": "build_road", "start": [120, 0], "ctrl": [160, 80], "end": [120, 180], "road": 1})
	sim.apply({"type": "build_roundabout", "center": [120, 0], "radius": 30, "road": 1})
	sim.apply({"type": "build_grid", "a": [-240, -50], "b": [40, -50], "c": [-240, -220], "block": 140})
	sim.apply({"type": "build_road", "start": [-100, -50], "ctrl": [-100, -25], "end": [-100, 0]})
	for lot in sim.lots.values():
		var p: Vector3 = lot.zone_pt
		var zone := ZoneMap.Zone.RESIDENTIAL
		if p.z > -20.0 and p.z < 40.0 and p.x < 100.0:
			zone = ZoneMap.Zone.COMMERCIAL
		elif p.x > 130.0:
			zone = ZoneMap.Zone.INDUSTRIAL
		sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": 3, "zone": zone})
	# Power, water and a few services, placed beside the roads.
	for entry in [[Services.Kind.SUBSTATION, Vector3(-260, 0, 40)], [Services.Kind.WATER_TOWER, Vector3(-215, 0, 40)],
			[Services.Kind.FIRE, Vector3(60, 0, 40)], [Services.Kind.SCHOOL, Vector3(70, 0, -120)],
			[Services.Kind.CLINIC, Vector3(-10, 0, 40)]]:
		var site := Services.site_near(sim.network, entry[0], entry[1])
		if not site.is_empty():
			sim.apply({"type": "place_service", "kind": entry[0], "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z]})
	var args := OS.get_cmdline_user_args()
	var overlay := args.size() >= 5 and args[4] == "zones"
	for i in (60 if overlay else 3000):
		sim.tick()
	if overlay:
		for c in _main.get_children():
			if c is ZoneTool:
				c.set_zone(ZoneMap.Zone.RESIDENTIAL)
	# Leave a few lots empty to show the zone tint.
	sim.apply({"type": "paint_zone", "center": [-150, 15], "radius": 14, "zone": ZoneMap.Zone.NONE})
	sim.apply({"type": "paint_zone", "center": [-150, 15], "radius": 14, "zone": ZoneMap.Zone.COMMERCIAL})
	if args.size() >= 5 and args[4] == "services":
		for c in _main.get_children():
			if c is ServiceTool:
				c.set_kind(Services.Kind.FIRE)
	if args.size() >= 5 and args[4] == "budget":
		for c in _main.find_children("*", "", true, false):
			if c.has_method("_budget_drawer"):
				c._open("budget")
	if args.size() >= 5 and args[4].begins_with("inspect"):
		# Click-to-inspect: the water tower, or a home.
		var sel := {}
		if args[4] == "inspect_home":
			var keys := sim.buildings.keys()
			keys.sort()
			for key in keys:
				if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
					sel = {"type": "lot", "id": key}
					break
		else:
			for id in sim.services.buildings:
				if sim.services.buildings[id].kind == Services.Kind.WATER_TOWER:
					sel = {"type": "service", "id": id}
		for c in _main.get_children():
			if c is Hud:
				c.close_all()  # put the road tool away first
		for c in _main.get_children():
			if c is SelectTool:
				c.select(sel)
	var cam: CityCamera
	for c in _main.get_children():
		if c is CityCamera:
			cam = c
	cam.look_at_point(Vector3(-40, 0, -60) if args.size() < 6 else Vector3(float(args[5]), 0, float(args[6])))
	if args.size() >= 4:
		cam.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


## A diamond interchange: a divided highway under a street bridge, with ramps.
func _demo_interchange(sim: CitySim) -> void:
	var cmds := [
		# Highway, one carriageway each way.
		[[-400, 12], [0, 12], [400, 12], 3],
		[[400, -12], [0, -12], [-400, -12], 3],
		# Street climbing to a bridge over it, and back down.
		[[0, -260], [0, -180], [0, -100, 7.5], 0],
		[[0, -100, 7.5], [0, 0, 7.5], [0, 100, 7.5], 0],
		[[0, 100, 7.5], [0, 180], [0, 260], 0],
		# Ramps: off the highway, up to the street; and back down.
		[[-260, 12], [-120, 30], [-25, 95, 6.75], 4],
		[[25, 95, 6.75], [120, 30], [260, 12], 4],
		[[260, -12], [120, -30], [25, -95, 6.75], 4],
		[[-25, -95, 6.75], [-120, -30], [-260, -12], 4],
		# Short links from the ramp ends onto the bridge street.
		[[-25, 95, 6.75], [-12, 97], [0, 98.6, 7.4], 4],
		[[0, 98.6, 7.4], [12, 97], [25, 95, 6.75], 4],
		[[25, -95, 6.75], [12, -97], [0, -98.6, 7.4], 4],
		[[0, -98.6, 7.4], [-12, -97], [-25, -95, 6.75], 4],
	]
	for c in cmds:
		var ctrl: Array = c[1]
		if ctrl.size() == 2:
			var a: Array = c[0]
			var b: Array = c[2]
			ctrl = [ctrl[0], ctrl[1], ((a[2] if a.size() > 2 else 0.0) + (b[2] if b.size() > 2 else 0.0)) * 0.5]
		var ok := sim.apply({"type": "build_road", "start": c[0], "ctrl": ctrl, "end": c[2], "road": c[3]})
		if not ok:
			print("demo road refused: ", c, " ", sim.road_problem([CitySim._v(c[0]), CitySim._v(ctrl), CitySim._v(c[2])], c[3]))
	for c in _main.get_children():
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3.ZERO)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


func _aim_camera() -> void:
	for c in _main.get_children():
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3.ZERO)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


## Two farms on a county road in July, grown for a few years.
func _demo_farms(sim: CitySim) -> void:
	sim.tick_count = 190 * 1440  # mid July
	sim.apply({"type": "build_road", "start": [-900, 0], "ctrl": [0, 0], "end": [900, 0]})
	sim.apply({"type": "build_road", "start": [0, -700], "ctrl": [0, 0], "end": [0, 700]})
	sim.apply({"type": "paint_farmland", "points": [[-800, 30], [-30, 30], [-30, 650], [-800, 650]]})
	sim.apply({"type": "paint_farmland", "points": [[30, -650], [800, -650], [800, -30], [30, -30]]})
	sim.apply({"type": "paint_farmland", "points": [[-800, -30], [-30, -30], [-30, -500], [-800, -500]]})
	sim.apply({"type": "place_farmhouse", "pos": [-300, 180], "dir": [0, -1], "crop": "corn"})
	sim.apply({"type": "place_farmhouse", "pos": [300, -150], "dir": [0, 1], "crop": "soybeans"})
	sim.apply({"type": "place_farmhouse", "pos": [-200, -260], "dir": [1, 0], "crop": "corn"})
	# A farm on a road that runs off at an angle, with farmland painted to match.
	sim.apply({"type": "build_road", "start": [60, 60], "ctrl": [400, 260], "end": [800, 500]})
	sim.apply({"type": "paint_farmland", "points": [[120, 200], [700, 560], [560, 760], [60, 420]]})
	sim.apply({"type": "place_farmhouse", "pos": [380, 420], "dir": [0.5, -0.866], "crop": "soybeans"})
	sim.farms.price = 1.1
	for i in 60:
		sim.farms.decide(sim.field_usable)
	sim.farms_changed.emit()
	for c in _main.get_children():
		if c is CityCamera:
			var la := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(float(la[5]), 0, float(la[6])) if la.size() >= 7 else Vector3.ZERO)
			var args := OS.get_cmdline_user_args()
			if args.size() >= 4:
				c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
	# An eighth argument opens a map view (fertility, oil, ore, forest...);
	# otherwise a look point shows the farm tool with its reserves.
	var va := OS.get_cmdline_user_args()
	for c in _main.get_children():
		if va.size() >= 8 and c is Hud:
			c._show_view(va[7])
			c._views_button.button_pressed = true
		elif va.size() >= 6 and va.size() < 8 and c is FarmTool:
			c.set_mode(FarmTool.Mode.RESERVE)
