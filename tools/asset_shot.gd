extends SceneTree
## Renders the free asset library as a line-up for checking each asset
## against real photos (the real-world rule) and for picking what to use.
## A red 1.75 m post (a person's height) stands beside each model for scale.
## Run: xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 -s tools/asset_shot.gd -- OUT_DIR [models|textures|hdris] [loop|id,id,...]
## Writes one OUT_DIR/<id>.png per asset; python3 tools/assets/sheet.py OUT_DIR sheet.png lays them out with names.
## Fetch first: python3 tools/assets/fetch.py && godot --headless --import

const TILE := 400
const GAP := 60.0

var _frames := 0
var _out := "assets"
var _views: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "assets"
	var kind := args[1] if args.size() > 1 else "models"
	var pick := args[2] if args.size() > 2 else ""
	var ids: Array = AssetLib.ids(kind)
	if pick.contains(","):
		ids = Array(pick.split(",")).filter(func(i): return AssetLib.has(i))
	elif pick != "":
		ids = AssetLib.ids(kind, pick) if not AssetLib.has(pick) else [pick]
	print("drawing ", ids.size(), " ", kind)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.ground_bottom_color = Color(0.3, 0.3, 0.28)
	psm.ground_horizon_color = Color(0.6, 0.62, 0.6)
	env.sky.sky_material = psm
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.light_energy = 0.85
	world.add_child(sun)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.5, 0.47)
	for n in ids.size():
		var id: String = ids[n]
		var at := Vector3(n * GAP, 0, 0)
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(GAP, GAP)
		ground.mesh = plane
		ground.material_override = gm
		ground.position = at
		world.add_child(ground)
		var box := AABB(at + Vector3(-0.5, 0, -0.5), Vector3(1, 1.75, 1))
		match kind:
			"models":
				var node := AssetLib.instance(id)
				if node:
					node.position = at
					world.add_child(node)
					box = _bounds(node, Transform3D(Basis(), at))
				# A person's height (1.75 m) beside it, for scale.
				var post := MeshInstance3D.new()
				var pb := BoxMesh.new()
				pb.size = Vector3(0.1, 1.75, 0.1)
				post.mesh = pb
				var pm := StandardMaterial3D.new()
				pm.albedo_color = Color(0.95, 0.3, 0.2)
				post.material_override = pm
				post.position = Vector3(box.position.x - 0.4, 0.875, box.get_center().z)
				world.add_child(post)
				box = box.merge(AABB(post.position - Vector3(0.05, 0.875, 0.05), Vector3(0.1, 1.75, 0.1)))
			"textures":
				var wall := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(3, 3)
				wall.mesh = q
				wall.material_override = AssetLib.material(id, Color.WHITE, true)
				wall.position = at + Vector3(0, 1.5, 0)
				world.add_child(wall)
				box = AABB(at + Vector3(-1.5, 0, 0), Vector3(3, 3, 0.01))
			"hdris":
				var ball := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 1.0
				sm.height = 2.0
				ball.mesh = sm
				var chrome := StandardMaterial3D.new()
				chrome.metallic = 1.0
				chrome.roughness = 0.05
				ball.material_override = chrome
				ball.position = at + Vector3(0, 1.0, 0)
				world.add_child(ball)
				box = AABB(at - Vector3(1, 0, 1), Vector3(2, 2, 2))
		var vp := SubViewport.new()
		vp.size = Vector2i(TILE, TILE)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if kind == "hdris":
			vp.own_world_3d = true
			var w2 := WorldEnvironment.new()
			var e2 := env.duplicate()
			e2.sky = AssetLib.sky(id)
			w2.environment = e2
			vp.add_child(w2)
			vp.add_child(world.duplicate())
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 35
		vp.add_child(cam)
		var c := box.get_center()
		var r := maxf(box.size.length() * 0.5, 0.5)
		var dir := Vector3(0.55, 0.45, 1.0).normalized() if kind != "textures" else Vector3(0, 0.05, 1).normalized()
		cam.look_at_from_position(c + dir * r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05, c)
		cam.current = true
		_views.append([id, vp])


static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var stack := [[n, xf]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var t: Transform3D = it[1]
		if node is MeshInstance3D and node.mesh:
			var b: AABB = t * node.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for ch in node.get_children():
			stack.append([ch, t * ((ch as Node3D).transform if ch is Node3D else Transform3D.IDENTITY)])
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		for v in _views:
			v[1].get_texture().get_image().save_png(_out.path_join(v[0] + ".png"))
		print("saved ", _views.size(), " tiles in ", _out)
		return true
	return false
