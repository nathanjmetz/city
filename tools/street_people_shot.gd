extends SceneTree
## People walking a town street, drawn by the game's own WalkerView and (on
## the desktop) NearPeople, without loading a whole town: for judging how
## people look and walk at play distance against street photos.
## Run (in a window): godot -s tools/street_people_shot.gd -- OUT_DIR
## DISTS=40,25,12 camera distances; MONTH=1-12; N walkers (default 60).
## People stand on the county's real ground (Terrain), so the street is
## laid on it too.


## The walkers' traffic: straight walks up and down the two sidewalks, so
## WalkerView and NearPeople draw them exactly as in a town.
class StreetWalks extends TrafficSim:
	var t := 0.0

	func walker_pose(w: Dictionary, _frac := 0.0) -> Array:
		var d: float = fposmod(float(w.start) + t * float(w.v), 120.0)
		var dir := Vector3(0, 0, -1.0 if w.side > 0 else 1.0)
		return [Vector3(float(w.x), 0.0, 60.0 - d if w.side > 0 else d - 60.0), dir, d]


var _traffic: StreetWalks
var _cam: Camera3D
var _dists := []
var _frames := 0
var _spot := 0


func _init() -> void:
	var month := int(OS.get_environment("MONTH")) if OS.get_environment("MONTH") != "" else 7
	for d in (OS.get_environment("DISTS") if OS.get_environment("DISTS") != "" else "40,25,12").split(","):
		_dists.append(float(d))
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
	sun.directional_shadow_max_distance = 120.0
	root.add_child(sun)
	# A residential street: 10 m of asphalt, curbs, grass strips, sidewalks
	# and lawns (a typical Indiana town street, about 18 m right of way).
	_slab(Vector3(0, -0.01, 0), Vector3(200, 0.02, 200), Color(0.36, 0.5, 0.24))
	_slab(Vector3(0, 0.0, 0), Vector3(10, 0.02, 200), Color(0.2, 0.2, 0.21))
	for side in [-1.0, 1.0]:
		_slab(Vector3(side * 6.2, 0.05, 0), Vector3(1.5, 0.1, 200), Color(0.36, 0.5, 0.24))
		_slab(Vector3(side * 7.6, 0.06, 0), Vector3(1.5, 0.12, 200), Color(0.62, 0.61, 0.58))
		for k in 8:
			_slab(Vector3(side * 16.0, 3.0, -56.0 + k * 16.0), Vector3(9, 6, 11), [Color(0.85, 0.83, 0.77), Color(0.55, 0.62, 0.68), Color(0.7, 0.5, 0.4)][k % 3])
	_traffic = StreetWalks.new(RoadNetwork.new())
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 60
	for i in n:
		var side := 1 if i % 2 == 0 else -1
		_traffic.walkers.append({"id": i + 1, "person": 1000 + i * 7919, "side": side,
			"x": side * (7.35 + 0.5 * float(i % 3 == 0)), "start": float(i) * 120.0 / n * 2.3,
			"v": 1.15 + 0.35 * float((i * 37) % 11) / 10.0})
	var frac := func() -> float: return 0.0
	var wv := WalkerView.new()
	wv.setup(_traffic, frac)
	root.add_child(wv)
	if NearPeople.available() and OS.get_environment("NONEAR") == "":
		var np := NearPeople.new()
		np.setup(_traffic, frac)
		root.add_child(np)
	DayNight.seasons_on = true
	_month = month
	_cam = Camera3D.new()
	_cam.fov = 50
	root.add_child(_cam)


var _month := 7


func _slab(c: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	mi.material_override = m
	mi.position = c + Vector3(0, Terrain.stand(Vector3(c.x, 0, c.z)).y, 0)
	root.add_child(mi)


func _process(delta: float) -> bool:
	_frames += 1
	_traffic.t += 1.0 / 30.0
	WalkerView.month_override = _month
	if _frames == 1 or _frames % 40 == 1:
		var d: float = _dists[_spot]
		# From across the street, looking along the near sidewalk.
		var pitch := deg_to_rad(clampf(d * 0.75, 10.0, 32.0))
		var yaw := deg_to_rad(-55.0)
		var at := Terrain.stand(Vector3(7.3, 0.9, 0.0))
		_cam.look_at_from_position(at + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d, at, Vector3.UP)
	if _frames % 40 == 0:
		var a := OS.get_cmdline_user_args()
		var out: String = (a[0] if a.size() > 0 else ".").path_join("street_%d.png" % int(_dists[_spot]))
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		_spot += 1
		if _spot >= _dists.size():
			quit()
	return false
