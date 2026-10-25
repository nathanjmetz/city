extends SceneTree
## Every kind of tree grown at 10, 30 and 60 years, side by side on a lawn,
## and a close-up of each kind at 40 years: to check each against how the
## real tree grows (docs/trees.md). A stand-alone scene, not the game.
## Run: godot --resolution 1600x900 -s tools/trees/tree_lineup.gd -- OUT_DIR [MONTH] [LOD] [KINDS]
##   MONTH: months as Seasons counts them (6.5 mid July, 9.6 mid October,
##   0.5 mid January); LOD 0 full, 1 light; KINDS a comma list (all if left out).

const AGES := [10.0, 30.0, 60.0]
const GAP := 34.0

var _out := ""
var _frames := 0
var _cam: Camera3D
var _shots := []
var _kinds := []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else "."
	var month := float(a[1]) if a.size() > 1 else 6.5
	var lod := int(a[2]) if a.size() > 2 else 0
	if a.size() > 3:
		for s in a[3].split(","):
			_kinds.append(int(s))
	else:
		for sp in TreeKinds.count():
			_kinds.append(sp)
	var look := Seasons.look(month)
	RenderingServer.global_shader_parameter_set("season_look", Vector4(look.autumn, look.bare, look.spring, look.dry))
	RenderingServer.global_shader_parameter_set("snow", look.snow)
	TreeLook.set_season(month)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#5d8fc9")
	mat.sky_horizon_color = Color("#b9cde0")
	mat.ground_horizon_color = Color("#9aa58a")
	mat.ground_bottom_color = Color("#4a5a33")
	sky.sky_material = mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#4f6a2c") if look.snow < 0.5 else Color("#e8ecf0")
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	world.add_child(_cam)
	# A row per kind, ages left to right.
	for row in _kinds.size():
		var sp: int = _kinds[row]
		var g := TreeGrower.grown(sp, 1)
		for i in AGES.size():
			var at := Vector3(i * GAP, 0, row * GAP)
			_plant(world, sp, g, AGES[i], lod, at)
		_plant(world, sp, g, 40.0, lod, Vector3(-GAP * 2.0, 0, row * GAP))
	var span := (_kinds.size() - 1) * GAP
	_shots.append(["lineup", Vector3(GAP * 1.0, 60.0 + span * 0.35, span + 70.0), Vector3(GAP * 1.0, 8.0, span * 0.5)])
	for row in _kinds.size():
		var sp: int = _kinds[row]
		var h := TreeKinds.height(sp, 40.0)
		var name: String = TreeKinds.kind(sp).name.replace(" ", "_")
		var at := Vector3(-GAP * 2.0, 0, row * GAP)
		_shots.append(["kind_" + name, at + Vector3(h * 1.4, h * 0.5, h * 2.0), at + Vector3(0, h * 0.48, 0)])


func _plant(world: Node3D, sp: int, g: TreeGrower, age: float, lod: int, at: Vector3) -> void:
	var tree := g.at_age(age)
	var mesh := TreeMesher.mesh(sp, tree, lod, 1)
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(), at))
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, TreeField.custom_of(TreeField.LEAF[sp], sp, true))
	mmi.multimesh = mm
	world.add_child(mmi)


func _process(_delta: float) -> bool:
	_frames += 1
	var i := _frames / 20
	if i >= _shots.size():
		quit()
		return true
	var s: Array = _shots[i]
	if _frames % 20 == 1:
		_cam.look_at_from_position(s[1], s[2])
	if _frames % 20 == 19:
		root.get_texture().get_image().save_png(_out.path_join("%s.png" % s[0]))
	return false
