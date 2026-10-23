extends SceneTree
## Pictures of the Region panel for checking the look, with a made-up
## region (this town plus a neighbor) and some pledges.
## Run: godot -s tools/region_shot.gd -- projects|services out.png

var _frames := 0
var _mode := "projects"
var _out := "region.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "projects"
	_out = args[1] if args.size() > 1 else "region.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Region Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		var r := Region.new()
		r.add_city("p1", "Ann")
		r.add_city("p2", "Bob")
		r.cities.c1.name = "Petersburg"
		r.cities.c2.name = "Oakland City"
		r.cities.c1.sim = sim
		sim.stats.population = 41_200
		r.cities.c2.sim.stats.population = 12_600
		sim.economy.money = 6_000_000
		r.ledger.set_population("c1", 41_200)
		r.ledger.set_population("c2", 12_600)
		r.update_metro()
		for i in 3:
			r.ledger.pledge("c1", "power", "money", 3_000_000.0 if i == 0 else 2_500_000.0)
		r.ledger.pledge("c2", "power", "money", 1_000_000.0)
		r.ledger.pledge("c1", "i69", "money", 1_500_000.0)
		r.ledger.pledge("c2", "i69", "money", 700_000.0)
		var fire := r.ledger.offer("c2", "c1", "fire", 12_400.0, 300.0)
		sim.regional.sync(r, "c1")
		sim.interlocal.sync(r, "c1", sim)
		sim.interlocal.deals["a9"] = {"id": "a9", "kind": "trash", "role": "host", "other": "c2", "other_name": "Oakland City",
			"fee": 5_600, "link": sim.network.nodes.keys()[0] if not sim.network.nodes.is_empty() else -1, "offset": 0,
			"left": -1, "picked": 0.0, "haul": 0.0, "homes": 40}
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		hud.region_panel.setup(sim, r, "c1", func(_id, _a): pass)
		hud.region_panel.open_panel()
		hud.region_panel.show_tab(_mode)
		assert(fire != "")
	if _frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
