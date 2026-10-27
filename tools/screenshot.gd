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
	# Wait for the game to finish loading its own town first.
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_demo_town()
	if _frames == (int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 40):
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
	if OS.get_environment("SHOT_MONTH") != "":
		# Months from January, e.g. 0.5 for mid-January snow.
		var m := float(OS.get_environment("SHOT_MONTH"))
		sim.set_calendar(Seasons.tick_at(m + (12.0 if m < Seasons.START_MONTH else 0.0)))
	var args0 := OS.get_cmdline_user_args()
	if args0.size() >= 5 and args0[4] == "warehouses":
		# Every warehouse size along an industrial avenue; the big one has grown.
		sim.apply({"type": "build_road", "start": [-420, 0], "ctrl": [0, 0], "end": [420, 0], "road": 1})
		var xs := {"small": -330.0, "medium": -230.0, "large": -70.0, "dc": 170.0}
		for k in Warehouses.ORDER:
			var site := Warehouses.site_near(sim.network, Vector3(xs[k], 0, 40))
			sim.apply({"type": "place_warehouse", "kind": k, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
		var big: Dictionary = sim.warehouses.buildings[3]
		big.level = 2
		big.bays = 2
		# What owners build from their trees, behind the buildings.
		sim.warehouses.buildings[2].built = ["truck_yard", "repair_shop", "fuel_island", "cold_storage", "freezer"]
		big.built = ["truck_yard", "tank_farm", "cross_dock"]
		sim.warehouses.buildings[4].built = ["truck_yard", "cross_dock", "co_packing", "regional_dc"]
		sim.warehouses_changed.emit()
		_aim_camera()
		return
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
	if args0.size() >= 5 and args0[4] == "mail":
		_demo_mail(sim)
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "factories":
		# One factory of each chain along an industrial street.
		sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": 1})
		for id in sim.network.segments.keys():
			for side in [-1, 1]:
				sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.INDUSTRIAL})
		for entry in [[Services.Kind.SUBSTATION, Vector3(-280, 0, 40)], [Services.Kind.WATER_TOWER, Vector3(-250, 0, -40)]]:
			var site := Services.site_near(sim.network, entry[0], entry[1])
			if not site.is_empty():
				sim.apply({"type": "place_service", "kind": entry[0], "pos": [site[0].x, site[0].z],
					"dir": [site[1].x, site[1].z]})
		for key in sim.empty_zoned_lots():
			sim.buildings[key] = {"zone": ZoneMap.Zone.INDUSTRIAL, "seed": hash(key), "built": 0,
				"cap": sim.capacity(ZoneMap.Zone.INDUSTRIAL, hash(key)), "occ": 0}
		var chains := ["mill", "sawmill", "refinery", "metal", "general", "general"]
		var keys := sim.buildings.keys()
		keys.sort()
		for i in keys.size():
			sim.buildings[keys[i]].chain = chains[i % chains.size()]
		sim.buildings_changed.emit()
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "junction":
		# Brawn's junction repro: a crossroads, a T and a sharp Y, zoned so
		# they get curbs and sidewalks.
		sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
		sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, 0], "end": [0, 150]})
		sim.apply({"type": "build_road", "start": [120, 0], "ctrl": [120, 70], "end": [120, 150]})
		sim.apply({"type": "build_road", "start": [-80, 0], "ctrl": [-130, 60], "end": [-180, 120]})
		sim.apply({"type": "build_road", "start": [-80, 0], "ctrl": [-30, 60], "end": [-10, 150], "road": 1})
		for id in sim.network.segments.keys():
			for side in [-1, 1]:
				sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "markings":
		_demo_markings(sim)
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "hubs":
		_demo_hubs(sim)
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "nopower":
		# Brawn's start: streets zoned, a well built, no power yet.
		sim.apply({"type": "build_grid", "a": [-160, -40], "b": [120, -40], "c": [-160, -220], "block": 140})
		for id in sim.network.segments.keys():
			for side in [-1, 1]:
				sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
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
				# Dry ground for the field and for the road and plant beside it.
				if Terrain.is_water(x, z) or Terrain.is_water(x, z - 260) or Terrain.is_water(x, z - 180):
					continue
				if v > best_v:
					best_v = v
					best = Vector3(x, 0, z)
		# The road and plant sit just off the richest ground, so the company
		# works it from its own side of the road.
		sim.apply({"type": "build_road", "start": [best.x - 600, best.z - 260], "ctrl": [best.x, best.z - 260], "end": [best.x + 600, best.z - 260]})
		sim.apply({"type": "place_industry", "kind": kind, "pos": [best.x, best.z - 180], "dir": [0, -1]})
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
	if args0.size() >= 5 and args0[4] in ["farms", "roadwins"]:
		_demo_farms(sim)
		return
	if args0.size() >= 5 and args0[4] == "forest":
		_demo_forest(sim)
		return
	if args0.size() >= 5 and args0[4] == "brawn_grid":
		_demo_brawn_grid(sim)
		return
	if args0.size() >= 5 and args0[4] == "state":
		_demo_state(sim)
		return
	if args0.size() >= 5 and args0[4] == "land":
		# The bare map, as a new town finds it.
		_aim_camera()
		return
	if args0.size() >= 5 and args0[4] == "county":
		_demo_county(sim)
		return
	# A main road with a roundabout, and a grid neighborhood beside it.
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": 2})
	sim.apply({"type": "build_road", "start": [120, 0], "ctrl": [160, 80], "end": [120, 180], "road": 1})
	sim.apply({"type": "build_roundabout", "center": [120, 0], "radius": 30, "road": 1})
	sim.apply({"type": "build_grid", "a": [-240, -50], "b": [40, -50], "c": [-240, -220], "block": 140})
	sim.apply({"type": "build_road", "start": [-100, -50], "ctrl": [-100, -25], "end": [-100, 0]})
	# Zone every street side, by where its middle is.
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			var c := sim.network.curve_of(id)
			var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], 0.5)
			var p: Vector3 = mid + Vector3(-tan.z, 0.0, tan.x).normalized() * float(side) * 15.0
			var zone := ZoneMap.Zone.RESIDENTIAL
			if p.z > -20.0 and p.z < 40.0 and p.x < 100.0:
				zone = ZoneMap.Zone.COMMERCIAL
			elif p.x > 130.0:
				zone = ZoneMap.Zone.INDUSTRIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})
	# Power, water and a few services, placed beside the roads.
	for entry in [[Services.Kind.SUBSTATION, Vector3(-260, 0, 40)], [Services.Kind.WATER_TOWER, Vector3(-215, 0, 40)],
			[Services.Kind.FIRE, Vector3(60, 0, 40)], [Services.Kind.SCHOOL, Vector3(70, 0, -120)],
			[Services.Kind.CLINIC, Vector3(-10, 0, 40)], [Services.Kind.POLICE, Vector3(-60, 0, 40)]]:
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
	if OS.get_cmdline_user_args()[4] == "roadwins":
		# The road wins: a curving county road cut through the corn.
		sim.apply({"type": "paint_reserve", "kind": "", "points": [[-850, 30], [-20, 30], [-20, 700], [-850, 700]]})
		sim.apply({"type": "build_road", "start": [-850, 520], "ctrl": [-350, 200], "end": [-20, 480]})
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


## A forestry company placed on the richest forest land near the origin,
## grown until it has opened several logging stands.
func _demo_forest(sim: CitySim) -> void:
	var best := Vector3.ZERO
	var rich := -1.0
	for i in 61:
		for j in 61:
			var p := Vector3(-1500 + i * 50, 0, -1500 + j * 50)
			var r := Resources.at(Resources.Kind.FOREST, p)
			if r > rich:
				rich = r
				best = p
	print("forest at ", best, " richness ", rich)
	sim.apply({"type": "build_road", "start": [best.x - 600, best.z - 160], "ctrl": [best.x, best.z - 160], "end": [best.x + 600, best.z - 160]})
	var ok := sim.apply({"type": "place_industry", "kind": "forest", "pos": [best.x, best.z - 60], "dir": [0, -1]})
	print("placed ", ok, " ", sim.industry_problem("forest", Vector3(best.x, 0, best.z - 60), Vector3(0, 0, -1)))
	for i in 40:
		sim.industry.decide(sim.field_usable)
	sim.industry_changed.emit()
	for c in _main.get_children():
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(best + (Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3.ZERO))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


## A street drawn out to a county road, which joins that mile to town; the
## camera looks at the join.
func _demo_county(sim: CitySim) -> void:
	for line in range(1, 4):
		var x := line * CountyGrid.SECTION
		for seg in range(-2, 2):
			var z := (seg + 0.5) * CountyGrid.SECTION
			if not CountyGrid.clears(x, z):
				continue
			sim.apply({"type": "build_road", "start": [x - 300, z], "ctrl": [x - 150, z], "end": [x, z], "road": 1,
				"join": true})
			print("joined ", sim.county_joined.keys())
			for c in _main.get_children():
				if c is CityCamera:
					var args := OS.get_cmdline_user_args()
					c.look_at_point(Vector3(x, 0, z))
					c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
			return


## Brawn's county road report (2026-10-24): a grid of blocks beside the
## county highway he started on, with a section line just past its end.
func _demo_brawn_grid(sim: CitySim) -> void:
	var o: Vector2 = sim.terrain_offset
	# The first north-south section line east of the town's middle.
	var line := ceilf((o.x + 200.0) / CountyGrid.SECTION) * CountyGrid.SECTION - o.x
	var z0 := -340.0 + 40.0
	var b := line - 50.0
	var args0 := OS.get_cmdline_user_args()
	if args0.size() >= 6 and args0[5] == "end":
		# Joined gravel ending at a mile's corner, the painted road going on,
		# and an unjoined link road crossing a painted line.
		for k in [1, -1, 2, -2, 3, -3]:
			var lx: float = (roundf(o.x / CountyGrid.SECTION) + k) * CountyGrid.SECTION - o.x
			var ok := true
			for zz in range(-900, 900, 20):
				ok = ok and CountyGrid.clears(lx + o.x, zz + o.y)
			if ok:
				line = lx
				break
		var zc := roundf(o.y / CountyGrid.SECTION) * CountyGrid.SECTION - o.y + CountyGrid.SECTION * 0.5
		sim.apply({"type": "build_road", "start": [line - 250, zc], "ctrl": [line - 125, zc], "end": [line, zc], "road": 0,
			"join": true})
		var corner := zc + CountyGrid.SECTION * 0.5
		sim.network.build_road(Vector3(line - 300, 0, corner - 200), Vector3(line, 0, corner - 200),
			Vector3(line + 300, 0, corner - 200), RoadStyle.Type.STREET)
		for i in 300:
			sim.tick()
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(Vector3(line, 0, corner - 100))
				c.set_view(deg_to_rad(float(args0[1])), deg_to_rad(float(args0[2])), float(args0[3]))
		return
	if args0.size() >= 6 and args0[5] == "town":
		# A zoned street crossing a county road it hasn't joined: the lots
		# keep off the gravel and the paint runs on through.
		for k in [1, -1, 2, -2, 3, -3]:
			var lx: float = (roundf(o.x / CountyGrid.SECTION) + k) * CountyGrid.SECTION - o.x
			var ok := true
			for zz in range(-200, 900, 20):
				ok = ok and CountyGrid.clears(lx + o.x, z0 + zz + o.y)
			if ok:
				line = lx
				break
		var zc := z0 + 300.0
		sim.apply({"type": "build_road", "start": [line - 250, zc], "ctrl": [line, zc], "end": [line + 250, zc], "road": 0})
		for id in sim.network.segments.keys():
			if not sim.is_link_segment(id):
				for side in [-1, 1]:
					sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
		for i in 300:
			sim.tick()
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(Vector3(line, 0, zc))
				c.set_view(deg_to_rad(float(args0[1])), deg_to_rad(float(args0[2])), float(args0[3]))
		return
	if args0.size() >= 6 and args0[5] == "over":
		# His later shot: the grid's east side on gravel the town had
		# already joined from the south, on a dry stretch of line.
		for k in [1, -1, 2, -2, 3, -3]:
			var lx: float = (roundf(o.x / CountyGrid.SECTION) + k) * CountyGrid.SECTION - o.x
			var ok := true
			for zz in range(-200, 900, 20):
				ok = ok and CountyGrid.clears(lx + o.x, z0 + zz + o.y)
			if ok:
				line = lx
				break
		sim.apply({"type": "build_road", "start": [line - 200, z0 + 700], "ctrl": [line - 100, z0 + 700],
			"end": [line, z0 + 700], "road": 0, "join": true})
		b = line + 3.0
	var a := b - 480.0
	print("line x ", line, " grid ", a, "..", b)
	sim.apply({"type": "build_grid", "a": [a, z0], "b": [b, z0], "c": [a, z0 + 240.0], "block": 120.0, "join": true})
	print("joined ", sim.county_joined.keys())
	var args := OS.get_cmdline_user_args()
	if args.size() >= 6 and (args[5] == "street" or args[5] == "over"):
		# Zoned like Brawn's town, the county highway's frontage too.
		for id in sim.network.segments.keys():
			if sim.network.segments.has(id) and not sim.is_link_segment(id):
				for side in [-1, 1]:
					sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
		if args[5] == "street":
			sim.apply({"type": "build_road", "start": [b, z0 + 120.0], "ctrl": [(b + line) * 0.5, z0 + 120.0],
				"end": [line, z0 + 120.0], "road": 0, "join": true})
		for i in 300:
			sim.tick()
		print("joined after street ", sim.county_joined.keys())
	var gravel := 0
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.GRAVEL:
			gravel += 1
			print("gravel ", sim.network.curve_of(id)[0], sim.network.curve_of(id)[2])
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(line - 60.0, 0, z0 + 240.0))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


## A street drawn out to the nearest state highway, which joins it to town.
func _demo_state(sim: CitySim) -> void:
	var o: Vector2 = sim.terrain_offset
	var hit := {}
	for reach in [1000.0, 2000.0, 4000.0, 8000.0]:
		hit = Highways.near(o.x, o.y, reach)
		if not hit.is_empty():
			break
	var at: Vector2 = hit.on - o
	var mode := OS.get_cmdline_user_args()[5] if OS.get_cmdline_user_args().size() >= 6 else ""
	var join := mode != "plain" and mode != "cross"
	if mode == "cross":
		# Where one of the town's roads crosses a highway, unjoined.
		for id in sim.network.segments:
			var pts := sim.network.sample_segment(id)
			for i in pts.size() - 1:
				var x := Highways.crossing(Vector2(pts[i].x, pts[i].z) + o, Vector2(pts[i + 1].x, pts[i + 1].z) + o)
				if not x.is_empty():
					at = x.on - o
		print("crossing at ", at)
	if join:
		var r: Dictionary = Highways.all()[hit.route]
		var t: Vector2 = (Highways.point(hit.route, hit.along + 20.0) - Highways.point(hit.route, hit.along - 20.0)).normalized()
		var side := Vector2(-t.y, t.x)
		var a := at + side * 300.0
		sim.apply({"type": "build_road", "start": [a.x, a.y], "ctrl": [(a.x + at.x) * 0.5, (a.y + at.y) * 0.5],
			"end": [at.x, at.y], "road": 1, "join": true})
		print("joined ", r.name, " ", sim.get("highways_joined"))
	for c in _main.get_children():
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(at.x, 0, at.y))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))


## A landfill, a recycling plant and a cemetery that have grown for a while.
## The post office on a street of homes, grown a sorting room, a sorting
## center and more carrier lot.
func _demo_mail(sim: CitySim) -> void:
	sim.economy.money = 60_000_000
	sim.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0]})
	for id in sim.network.segments.keys():
		sim.apply({"type": "zone_frontage", "seg": id, "side": -1, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := CivicHubs.site_near(sim.network, Vector3(0, 0, 60))
	sim.apply({"type": "place_post_office", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var id: int = sim.mail.offices.keys()[0]
	var h: Dictionary = sim.mail.offices[id]
	for node in ["sorting_room", "sorting_center", "more_vans"]:
		var pieces := []
		for k in int(Balance.MAIL_TREE[node].land):
			var c: Vector2i = sim.mail._best_piece(sim, id, pieces)
			if c != Vector2i.MAX:
				pieces.append(c)
		h.cells.append_array(pieces)
		h.lands[node] = pieces
		h.built.append(node)
	var c2: Vector2i = sim.mail._best_piece(sim, id)
	if c2 != Vector2i.MAX:
		h.cells.append(c2)
	sim.mail._touch(h)
	sim.simulate_traffic = false
	sim.require_utilities = false
	for i in 1500:
		sim.tick()
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
	for c in _main.get_children():
		if c is SelectTool:
			c.select({"type": "post_office", "id": id})


func _demo_hubs(sim: CitySim) -> void:
	sim.economy.money = 60_000_000
	sim.apply({"type": "build_road", "start": [-700, 0], "ctrl": [0, 0], "end": [700, 0]})
	var spots := [["landfill", Vector3(-300, 0, -60), 16], ["recycling_1", Vector3(250, 0, -60), 9],
		["cemetery", Vector3(0, 0, 60), 12]]
	for spot in spots:
		var site := CivicHubs.site_near(sim.network, spot[1])
		sim.apply({"type": "place_hub", "kind": spot[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var ids := sim.hubs.hubs.keys()
	ids.sort()
	for i in ids.size():
		var h: Dictionary = sim.hubs.hubs[ids[i]]
		h.received = 3.0e7
		while h.cells.size() < spots[i][2]:
			if h.kind == "cemetery":
				sim.stats.population = 100_000
			else:
				h.want = 4
				h.short = 4
			var n: int = h.cells.size()
			sim.hubs._decide(sim)
			if h.cells.size() == n:
				break
	sim.apply({"type": "upgrade_hub", "id": ids[1]})
	sim.apply({"type": "upgrade_hub", "id": ids[1]})
	# Every branch of each development tree, to see them all.
	for i in ids.size():
		var h: Dictionary = sim.hubs.hubs[ids[i]]
		h.built = CivicHubs.tree(h).map(func(n): return n.id)
		sim.hubs._touch(h)
	sim.tick()
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
	for c in _main.get_children():
		if c is SelectTool:
			c.select({"type": "hub", "id": ids[0]})


## Brawn's junction paint report (2026-10-24): skewed, Y, T, offset and
## five-leg junctions, a street crossing an avenue, two avenues under
## lights and a street with a gentle bend, zoned so they get curbs.
## North of the starting highway; look at about (0, -250).
func _demo_markings(sim: CitySim) -> void:
	var before := sim.network.segments.keys()
	var roads := [
		[[-350, -180], [350, -180], 0],  # main street
		[[-200, -180], [20, -460], 0],  # Y off it
		[[-200, -180], [-200, -20], 0],  # five legs with the two above
		[[-200, -180], [-330, -380], 0],
		[[-120, -20], [-25, -320], 0],  # skewed crossing
		[[150, -180], [150, -20], 0],  # offset T's
		[[195, -180], [195, -340], 0],
		[[270, -20], [270, -480], 1],  # avenue crossing the street
		[[50, -420], [370, -420], 1],  # avenue meeting it under lights
	]
	for r in roads:
		var a: Array = r[0]
		var b: Array = r[1]
		var c := [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
		if not sim.apply({"type": "build_road", "start": a, "ctrl": c, "end": b, "road": r[2]}):
			print("refused ", r, " ", sim.road_problem([CitySim._v(a), CitySim._v(c), CitySim._v(b)], r[2]))
	# A street with a slight bend at a node.
	sim.apply({"type": "build_road", "start": [-350, -80], "ctrl": [-300, -80], "end": [-250, -80]})
	sim.apply({"type": "build_road", "start": [-250, -80], "ctrl": [-202, -90], "end": [-154, -100]})
	for id in sim.network.segments.keys():
		if not before.has(id):
			for side in [-1, 1]:
				if not sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL}):
					print("refused zoning ", id, " ", sim.network.curve_of(id)[0])
	for i in 5:
		sim.tick()
	# Lots take a while to be platted out here; draw every new street as a
	# town street at once.
	for c in _main.find_children("*", "RoadView", true, false):
		if OS.get_environment("MARKINGS_RURAL") == "1":
			break  # leave them country roads
		for id in sim.network.segments:
			if not before.has(id):
				c._town_ever[id] = true
		c.rebuild()
