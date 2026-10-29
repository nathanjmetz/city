extends SceneTree
## AmbientLife's scenes side by side on a row of bare lots (no town loaded),
## for judging the people in them: who's a child, a teenager or grown, a
## man's or a woman's figure, sitting or standing.
## Run (in a window): godot -s tools/ambient_lab_shot.gd -- out.png
## KINDS=porch,lemonade,... (default a mix); MONTH=1-12; PARK=picnic,bench...;
## LOOK=park to look at the park scenes instead (LOOK=street the sidewalk); DIST camera distance.
var _frames := 0
var _al: AmbientLife


func _init() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 40, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var kinds := (OS.get_environment("KINDS") if OS.get_environment("KINDS") != "" \
		else "porch,lemonade,garden,hoops,talk,costumes").split(",")
	var parks := (OS.get_environment("PARK") if OS.get_environment("PARK") != "" else "picnic,bench").split(",")
	var sim := CitySim.new()
	var wv := WalkerView.new()
	wv._ready()
	_al = AmbientLife.new()
	root.add_child(_al)
	_al._wait = 1e9  # the scenes are set here, not picked from a town
	_al.setup(sim, (wv.get_child(0) as MultiMeshInstance3D).material_override)
	_al._month = int(OS.get_environment("MONTH")) if OS.get_environment("MONTH") != "" else 7
	var width := 18.0
	_slab(Vector3(0, 0, 10), Vector3(200, 0.02, 80), Color(0.36, 0.5, 0.24), -0.03)
	_slab(Vector3(0, 0, -6), Vector3(200, 0.02, 9), Color(0.2, 0.2, 0.21), 0.0)
	_slab(Vector3(0, 0, -0.6), Vector3(200, 0.02, 1.5), Color(0.62, 0.61, 0.58), 0.0)
	for i in kinds.size():
		var x := (i - (kinds.size() - 1) * 0.5) * width
		var lot := {"normal": Vector3(0, 0, 1), "dir": Vector3(1, 0, 0), "front": Vector3(x, 0, 0.6),
			"depth": 36.0, "width": width}
		_al._scenes.append({"kind": kinds[i], "lot": lot, "seed": hash([i, "lab"])})
		_slab(Vector3(x, 3.0, 13.0), Vector3(10, 6, 9), Color(0.82, 0.8, 0.74), 0.0)
	for i in parks.size():
		var pk := {"pos": Vector3((i - (parks.size() - 1) * 0.5) * 14.0, 0, -28.0), "size": Vector2(10, 10),
			"dir": Vector3(0, 0, 1)}
		_al._scenes.append({"kind": parks[i], "park": pk, "seed": 7 + i})
	_slab(Vector3(0, 0, -28), Vector3(40, 0.02, 14), Color(0.4, 0.55, 0.28), -0.02)
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	var at := Terrain.stand(Vector3(0, 0, 4))
	var look: Vector3 = {"park": Vector3(0, 0, -28), "street": Vector3(0, 0, 0)}.get(OS.get_environment("LOOK"), Vector3(0, 0, 6))
	at = Terrain.stand(look)
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 16.0
	cam.look_at_from_position(at + Vector3(0, dist * 0.45, -dist), at + Vector3(0, 0.8, 0), Vector3.UP)


func _slab(c: Vector3, size: Vector3, col: Color, dy: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = Vector3(c.x, Terrain.stand(c).y + dy + c.y, c.z)
	root.add_child(mi)


func _process(_d: float) -> bool:
	_frames += 1
	_al._draw()
	if _frames == 30:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "ambient_lab.png")
		quit()
	return false
