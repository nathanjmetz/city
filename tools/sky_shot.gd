extends SceneTree
## The sky alone over a flat field with a few boxes, to judge the sky,
## clouds, sun and haze fast (no town to load).
## Run: xvfb-run godot --rendering-driver vulkan --resolution 1600x900 -s tools/sky_shot.gd -- out.png [pitch_deg] [cover] [hour]

var _sky: SkyLight
var _frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_sky = SkyLight.new()
	root.add_child(_sky)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.42, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	for i in 12:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(10, 7 + i % 3 * 3, 12)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = [Color(0.8, 0.8, 0.78), Color(0.55, 0.25, 0.2), Color(0.6, 0.65, 0.7)][i % 3]
		b.material_override = m
		b.position = Vector3((i % 4) * 25 - 40, bm.size.y / 2, (i / 4) * 30 - 120)
		root.add_child(b)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 30, 20)
	cam.rotation_degrees = Vector3(float(a[1]) if a.size() > 1 else 5.0, 0, 0)
	cam.far = 30000
	root.add_child(cam)
	cam.make_current()


func _process(_d: float) -> bool:
	_frames += 1
	var a := OS.get_cmdline_user_args()
	if _frames == 2:
		_sky.set_cover(float(a[2]) if a.size() > 2 else 0.3)
		if a.size() > 3:
			_sky.set_time(float(a[3]), 6.5)
	if _frames == 12:
		root.get_viewport().get_texture().get_image().save_png(a[0])
		quit()
	return false
