extends SceneTree
## Pictures of the permit bell for checking the look, with a made-up railroad
## request across the starter road (no real hub files one yet).
## Run: godot -s tools/permit_shot.gd -- list|edit|land|guide|deal|homes|projects|plan|engineer out.png
## ("homes" is a real home builder's subdivision, with its choice of sites;
## "projects" is one under way; "plan" is the land use plan tool; "engineer" a city engineer's proposal.)

var _frames := 0
var _mode := "list"
var _out := "permits.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "list"
	_out = args[1] if args.size() > 1 else "permits.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Permit Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [140, 60], "end": [240, 60]})
		for x in range(40, 241, 10):
			sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		for i in 600:
			sim.tick()
		if _mode == "engineer":
			# The city engineer's proposal for a jammed road.
			sim.stats.population = 12000
			for seg in sim.network.segments:
				sim.engineer.counts[seg] = [4, 4, 0]
			sim.engineer.samples = 4
			sim.engineer.month(sim)
			var he: Hud = main.get_children().filter(func(n): return n is Hud)[0]
			he.advisor.settings.welcomed = true
			he.advisor.close_panel()
			he.tour.stop()
			he.permits.open_panel()
			var eid: int = sim.engineer.pending.keys()[0] if not sim.engineer.pending.is_empty() else -1
			print("engineer request ", eid)
			he.permits.call("_select", eid, 0)
			var ce: CityCamera = he.info_view.cam
			ce.set_view(0.7, 0.8, 600.0)
			ce.look_at_point(he.permits.view.center())
			return false
		if _mode == "plan":
			# A land use plan: homes north of the road, shops along it, jobs
			# and farms beyond, and the Plan tool out.
			sim.apply({"type": "paint_plan", "points": [[-200, 80], [500, 80], [500, 500], [-200, 500]], "kind": "homes"})
			sim.apply({"type": "paint_plan", "points": [[-200, 30], [500, 30], [500, 95], [-200, 95]], "kind": "shops"})
			sim.apply({"type": "paint_plan", "points": [[300, -400], [700, -400], [700, -60], [300, -60]], "kind": "jobs"})
			sim.apply({"type": "paint_plan", "points": [[-500, -500], [250, -500], [250, -120], [-500, -120]], "kind": "farms"})
			var hp: Hud = main.get_children().filter(func(n): return n is Hud)[0]
			hp.advisor.settings.welcomed = true
			hp.advisor.close_panel()
			hp.tour.stop()
			hp.farm_tool.plan_kind = "homes"
			hp.farm_tool.set_mode(FarmTool.Mode.PLAN)
			var cp: CityCamera = hp.info_view.cam
			cp.set_view(0.6, 0.8, 1100.0)
			cp.look_at_point(Vector3(100, 0, 0))
			return false
		if _mode == "homes" or _mode == "projects":
			for key in sim.lots:
				if sim.buildings.has(key) or sim.zones.zone_at(sim.lots[key].zone_pt) != ZoneMap.Zone.RESIDENTIAL:
					continue
				sim.buildings[key] = BuildingTypes.make(sim, key, {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": hash(key),
					"built": sim.tick_count, "changed": sim.tick_count, "occ": 2}, "house", 0)
			sim.stats.population = 2500
			sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
			sim.subdivisions.month(sim)
			for h in 48:
				sim.subdivisions.hour(sim)
			if _mode == "projects":
				# Approved: the builder is under way, and the bell lists it.
				sim.apply({"type": "permit", "id": sim.subdivisions.pending.keys()[0], "answer": "approve", "pick": 0})
				sim.subdivisions.carry_out(sim)
			var hud0: Hud = main.get_children().filter(func(n): return n is Hud)[0]
			hud0.advisor.settings.welcomed = true
			hud0.advisor.close_panel()
			hud0.tour.stop()
			hud0.permits.open_panel()
			var id: int = sim.subdivisions.pending.keys()[0] if not sim.subdivisions.pending.is_empty() else -1
			print("subdivision request ", id)
			hud0.permits.call("_select", id, 1)
			var cam0: CityCamera = hud0.info_view.cam
			cam0.set_view(0.7, 0.75, 700.0)
			cam0.look_at_point(hud0.permits.view.center())
			return false
		sim.permits.file(sim, {"hub": "rail", "hub_id": 1, "leader": "Dale Hoffman",
			"title": "Rail spur to the grain elevator", "why": "Grain sits waiting on trucks. A spur would move it by the carload.",
			"route": [[120, -120], [130, 20], [150, 140]], "width": 8.0, "per_m": 900, "budget": 900000})
		if _mode == "land":
			sim.permits.file(sim, {"hub": "bank", "hub_id": 1, "leader": "Ruth Ames",
				"title": "Office park on the Miller farm", "why": "Town's growing a money crowd. We'd like room to build.",
				"change": "Farmland to offices", "area": [[60, -140], [220, -120], [230, 10], [70, 20]],
				"per_m2": 25, "budget": 900000})
		if _mode == "deal":
			# A neighbor's offer, and a deal already signed (Interlocal).
			sim.permits.file(sim, {"hub": "interlocal", "hub_id": 7, "leader": "Fire Chief Gary Brandt (Bobville)",
				"title": "Bobville offers us fire protection",
				"why": "We'd serve your town from Bobville over the county road, for $12,400 a month: your share of our cost, by homes.",
				"route": [[200, 60]], "deal": {"kind": "fire", "fee": 12400, "other": "c2", "pays": true}})
			sim.interlocal.deals["a3"] = {"id": "a3", "kind": "trash", "role": "served", "other": "c2", "other_name": "Bobville",
				"fee": 5600, "link": sim.network.nodes.keys()[0], "offset": 0, "left": -1, "picked": 0.0, "haul": 0.0,
				"homes": 40}
		sim.permits.file(sim, {"hub": "bus", "hub_id": 1, "leader": "Marcy Lindqvist",
			"title": "Bus turnaround on Main", "why": "Riders wait too long at the far end of the line.",
			"route": [[-60, -30], [-20, -10]], "width": 12.0, "per_m": 400, "budget": 120000})
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		var cam: CityCamera = hud.info_view.cam
		cam.set_view(0.6, 0.9, 380.0)
		cam.look_at_point(Vector3(130, 0, 20))
		if _mode == "guide":
			# Any selectable thing stands in for a hub here.
			sim.permits.locators["road"] = func(_s, _id): return Vector2.ZERO
			hud.road_tool.set_mode(RoadTool.Mode.NONE)
			hud.select_tool.select({"type": "road", "id": sim.network.segments.keys()[-1]})
			sim.apply({"type": "guide", "hub": "road", "hub_id": sim.network.segments.keys()[-1], "stance": "grow", "grant": 500})
		else:
			hud.permits.open_panel()
			hud.permits.call("_select", 2 if _mode in ["land", "deal"] else 1)
	if _frames == 30 and _mode == "land":
		var hud: Hud = current_scene.get_children().filter(func(n): return n is Hud)[0]
		hud.permits.set("_editing", true)
		hud.permits.view.set_editing(true)
		hud.permits.view.call("_changed")
	if _frames == 30 and _mode == "edit":
		var hud: Hud = current_scene.get_children().filter(func(n): return n is Hud)[0]
		hud.permits.view.route.insert(1, [60, -40])
		hud.permits.set("_editing", true)
		hud.permits.view.set_editing(true)
		hud.permits.view.call("_changed")
	if _frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
