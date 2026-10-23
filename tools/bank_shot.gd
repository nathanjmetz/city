extends SceneTree
## Renders a grown community bank and a Farm Credit office and saves a picture.
## Run: godot -s tools/bank_shot.gd -- out.png yaw_deg pitch_deg dist x z

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_demo()
	if _frames == 90:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "bank.png")
		quit()
	return false


func _demo() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.build_county_road(Vector2(-2000, 0), Vector2(2000, 0), [0, 1])
	for c in [["community", Vector3(-120, 0, 30)], ["farm_credit", Vector3(60, 0, 30)]]:
		var site := Banks.site_near(sim.network, c[1])
		sim.apply({"type": "place_bank", "kind": c[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	# A grown-up bank: every block its tree allows, laid out next door.
	for id in sim.banks.banks:
		var b: Dictionary = sim.banks.banks[id]
		var uses := ["drive_up", "commercial", "trust"] if b.kind == "community" else ["parking", "leasing"]
		for i in uses.size():
			b.blocks.append({"c": [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(-1, 1)][i], "use": uses[i]})
			b.built.append(uses[i])
	sim.banks_changed.emit()
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			var mid := Vector3.ZERO
			for id in sim.banks.banks:
				mid += sim.banks.banks[id].pos / sim.banks.banks.size()
			c.look_at_point(mid + (Vector3(float(args[4]), 0, float(args[5])) if args.size() >= 6 else Vector3.ZERO))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
