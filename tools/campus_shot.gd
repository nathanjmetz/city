extends SceneTree
## Renders a grown high school and university and saves a picture.
## Run: godot -s tools/campus_shot.gd -- out.png yaw_deg pitch_deg dist x z

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_demo()
	if _frames == 50:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "campus.png")
		quit()
	return false


func _demo() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.build_county_road(Vector2(-2000, 0), Vector2(2000, 0), [0, 1])
	for c in [["high_school", Vector3(-400, 0, 90)], ["university", Vector3(400, 0, 90)]]:
		var site := Education.site_near(sim.network, c[1])
		sim.apply({"type": "place_campus", "kind": c[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	sim.education.region = {"population": 2_000_000, "farms": 6, "industry": 5}
	for id in sim.education.campuses:
		var c: Dictionary = sim.education.campuses[id]
		c.leader.education = 0.9
		c.leader.ambition = 0.8
	for i in 9:
		for id in sim.education.campuses:
			var c: Dictionary = sim.education.campuses[id]
			c.savings = 100_000_000.0
			c.reputation = 0.7
		sim.education.decide(sim)
	sim.education_changed.emit()
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(float(args[4]), 0, float(args[5])) if args.size() >= 6 else Vector3(0, 0, 200))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
