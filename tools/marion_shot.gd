extends "res://tools/look_shot.gd"
## Marion's backdrop (Brawn, 2026-10-24): looks at the middle of the
## nearest backdrop town from the asked distance, to check the colours and
## that the camera won't come closer than CityCamera.BACKDROP_MIN_DIST.
## MARION_DX / MARION_DZ shift the spot (metres).
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/marion_shot.gd -- out.png yaw pitch dist


func _demo_town() -> void:
	_main.sim.apply({"type": "clear"})
	var la := OS.get_cmdline_user_args()
	var town: Dictionary = Backdrop.nearest(Terrain.view_origin)
	var c: Vector2 = town.centre - Terrain.view_origin
	c += Vector2(float(OS.get_environment("MARION_DX")), float(OS.get_environment("MARION_DZ")))
	for n in _main.get_children():
		if n is CityCamera:
			n.look_at_point(Vector3(c.x, 0, c.y))
			n.set_view(deg_to_rad(float(la[1])), deg_to_rad(float(la[2])), float(la[3]))
		if n is Hud:
			n.close_all()


func _process(delta: float) -> bool:
	if _frames == 150:
		for n in _main.get_children():
			if n is CityCamera:
				print("camera distance ", n._dist, " (asked ", OS.get_cmdline_user_args()[3], ")")
	return super(delta)
