extends SceneTree
## A school's crossing guard (AmbientLife) at the corner nearest its doors,
## on a plain grid with the roads laid as flat strips, without loading a
## whole town. Run (in a window): godot -s tools/guard_shot.gd -- OUT_DIR
## Saves guard_wait.png (at the corner) and guard_out.png (in the street).
var _frames := 0
var _al: AmbientLife
var _sim: CitySim


func _init() -> void:
	_sim = CitySim.new()
	_sim.charter.reached.merge({"town": 0, "city": 0})
	for z in [0, 200]:
		_sim.apply({"type": "build_road", "start": [-300, z], "ctrl": [0, z], "end": [300, z]})
	for x in [-250, 0, 250]:
		_sim.apply({"type": "build_road", "start": [x, -200], "ctrl": [x, 100], "end": [x, 400]})
	_sim.economy.money = 50_000_000
	var site := Services.site_near(_sim.network, Services.Kind.SCHOOL, Vector3(-125, 0, 40))
	_sim.apply({"type": "place_service", "kind": Services.Kind.SCHOOL, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]})
	_sim.set_calendar(Seasons.tick_at(SkyClock.at(9, 7.3)))
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
	var c := Vector3(0, 0, 100)
	_slab(c, Vector3(800, 0.02, 800), Color(0.36, 0.5, 0.24), -0.03)
	for sid in _sim.network.segments:
		var cv := _sim.network.curve_of(sid)
		var a: Vector3 = cv[0]
		var b: Vector3 = cv[2]
		var hw := RoadStyle.half_width(_sim.network.segments[sid].type)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var mi := _slab(mid, Vector3(hw * 2.0, 0.02, len), Color(0.2, 0.2, 0.21), 0.0)
		mi.look_at(mi.position + (b - a).normalized(), Vector3.UP)
		var walk := _slab(mid, Vector3(hw * 2.0 + 9.0, 0.02, len), Color(0.62, 0.61, 0.58), -0.01)
		walk.look_at(walk.position + (b - a).normalized(), Vector3.UP)
	var sb: Dictionary = _sim.services.buildings.values()[0]
	_slab(sb.pos + Vector3(0, 4, 0), Vector3(60, 8, 60), Color(0.62, 0.36, 0.28), 0.0)
	var wv := WalkerView.new()
	wv._ready()
	_al = AmbientLife.new()
	root.add_child(_al)
	_al.setup(_sim, (wv.get_child(0) as MultiMeshInstance3D).material_override)
	var spot := _al._guard_spot(int(_sim.services.buildings.keys()[0]), sb)
	var cam := Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	var at: Vector3 = Terrain.stand(spot.at)
	var face: Vector3 = spot.face
	var side := face.cross(Vector3.UP)
	cam.look_at_from_position(at + face * 9.0 + side * 6.0 + Vector3(0, 3.0, 0), at + face * 2.0 + Vector3(0, 1.0, 0), Vector3.UP)


func _slab(c: Vector3, size: Vector3, col: Color, dy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = Vector3(c.x, Terrain.stand(c).y + dy + c.y, c.z)
	root.add_child(mi)
	return mi


func _process(_d: float) -> bool:
	_frames += 1
	var a := OS.get_cmdline_user_args()
	var dir: String = a[0] if a.size() > 0 else "."
	if _frames == 20:
		_al._clock = 5.0 - float(hash([int(_sim.services.buildings.keys()[0]), "guard"]) % 31)
	if _frames == 30:
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("guard_wait.png"))
		_al._clock = 23.0 - float(hash([int(_sim.services.buildings.keys()[0]), "guard"]) % 31)
	if _frames == 40:
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("guard_out.png"))
		quit()
	return false
