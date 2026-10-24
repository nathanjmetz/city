extends SceneTree
## The game with a subdivision's first phase at one stage of its site work,
## for checking SubdivisionWorksView against photos of real ones.
## Run: godot -s tools/subdivision_shot.gd -- out.png [stage 0-6, 7 = phase 1
##      done and phase 2 laying pipe] [yaw pitch dist]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		sim.traffic.cars.clear()
		sim.traffic._waiting.clear()
		sim.economy.money = 20_000_000
		sim.require_utilities = false
		sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
		var stage := int(args[1]) if args.size() > 1 else 2
		var hw := RoadStyle.right_of_way_half(RoadStyle.Type.STREET)
		var site := {"o": [240.0, 0.0], "t": [1.0, 0.0], "n": [0.0, -1.0], "hw": hw, "phases": 3, "homes": 50}
		var subs: Subdivisions = sim.subdivisions
		subs.active[1] = {"site": site, "phase": 0, "opened": 0, "builder": "a local builder", "name": "Test Acres",
			"needs": {}, "extra": 0, "slow": 0.0}
		subs.next_id = 2
		subs._build_phase(sim, 1)
		var weeks: Array = Construction.PROFILES[Subdivisions.WORKS].weeks
		var at := 0
		for j in mini(stage, 7):
			at += int(weeks[j])
		sim.tick_count += at * Balance.BUILD_TICKS_PER_WEEK + Balance.BUILD_TICKS_PER_WEEK / 2
		subs.works(sim)
		if stage >= 7:
			sim.tick_count += Construction.duration(Subdivisions.WORKS)
			subs.works(sim)
			subs._build_phase(sim, 1)
			sim.tick_count += (int(weeks[0]) + int(weeks[1]) + 2) * Balance.BUILD_TICKS_PER_WEEK
			subs.works(sim)
		subs.changed.emit()
		sim.vegetation.update(sim)
		print("stage ", Subdivisions.works_stage(subs.active[1], sim.tick_count), " phase ", subs.active[1].phase,
			" roads ", sim.network.segments.size())
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(Vector3(240, 0, -90))
				if args.size() > 4:
					c.set_view(deg_to_rad(float(args[2])), deg_to_rad(float(args[3])), float(args[4]))
	if _frames == 60:
		var out := args[0] if args.size() > 0 else "subdivision.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
