extends SceneTree
## A ready-made person walking (vertex animation texture), four copies at
## different points of the stride. Run (in a window):
##   godot --path . -s tools/people_walk_shot.gd -- out.png person.glb person_walk.exr [dist]
var _frames := 0
const FRAMES := 16

const SHADER := """
shader_type spatial;
uniform sampler2D vat : filter_nearest;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float phase = 0.0;
uniform float frames = 16.0;
void vertex() {
	float f = floor(mod(phase * frames, frames));
	vec3 p = texture(vat, UV2 + vec2(0.0, f / frames)).rgb;
	VERTEX = vec3(p.x, p.z, -p.y);
}
void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.75;
	if (c.a < 0.4) { discard; }
}
"""

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dist := float(a[3]) if a.size() > 3 else 6.0
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.5, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	var vat := ImageTexture.create_from_image(Image.load_from_file(a[2]))
	var shader := Shader.new()
	shader.code = SHADER
	for k in 4:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_file(a[1], state)
		var node := doc.generate_scene(state) as Node3D
		node.position = Vector3((k - 1.5) * 1.2, 0, 0)
		node.rotation.y = PI * 0.5  # walking across the view
		root.add_child(node)
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var src := m.get_active_material(si) as BaseMaterial3D
				var sm := ShaderMaterial.new()
				sm.shader = shader
				sm.set_shader_parameter("vat", vat)
				sm.set_shader_parameter("phase", k / 4.0)
				sm.set_shader_parameter("frames", float(FRAMES))
				if src:
					sm.set_shader_parameter("albedo_tex", src.albedo_texture)
					sm.set_shader_parameter("albedo_col", src.albedo_color)
				m.set_surface_override_material(si, sm)
			m.extra_cull_margin = 2.0
	var cam := Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	var dir := Vector3(0, 0.25, 1).normalized()
	cam.look_at_from_position(Vector3(0, 0.9, 0) + dir * dist, Vector3(0, 0.9, 0), Vector3.UP)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 20:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0])
		quit()
	return false
