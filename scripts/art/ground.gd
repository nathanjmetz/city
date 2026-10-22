class_name Ground
extends MeshInstance3D
## The open ground: grass that looks like real Midwestern turf from above.
## What aerial photos show, and what this copies:
##   - big soft patches of greener and drier, yellower grass (tens of metres)
##   - darker clumps and mottling at a few metres
##   - a fine blade grain up close that fades out with distance
##   - no visible repeat: each layer is sampled at an unrelated scale and angle
## Everything is world-space, so the ground can grow forever without seams.

const SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
uniform vec4 lush : source_color = vec4(0.29, 0.38, 0.17, 1.0);
uniform vec4 dry : source_color = vec4(0.46, 0.46, 0.27, 1.0);
uniform vec4 dark : source_color = vec4(0.20, 0.28, 0.12, 1.0);
uniform vec4 soil : source_color = vec4(0.46, 0.40, 0.29, 1.0);

varying vec3 world_pos;

vec2 turn(vec2 p, float a) {
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(noise_soft, p / 900.0).r;
	float mid = texture(noise_soft, turn(p, 1.1) / 210.0 + 0.31).r;
	float clump = texture(noise_soft, turn(p, 2.3) / 19.0 + 0.62).r;
	float grain = texture(noise_grain, turn(p, 0.7) / 3.1).r;
	float blades = texture(noise_grain, turn(p, 2.9) / 0.6 + 0.5).r;

	float dryness = smoothstep(0.42, 0.78, big * 0.55 + mid * 0.45);
	vec3 col = mix(lush.rgb, dry.rgb, dryness * 0.75);
	col = mix(col, dark.rgb, smoothstep(0.35, 0.9, clump) * 0.35);
	// The odd bare, worn spot where the grass is driest.
	col = mix(col, soil.rgb, smoothstep(0.80, 0.95, mid * 0.6 + clump * 0.4) * 0.35);
	// Blade grain fades with distance so far fields don't shimmer.
	float fade = clamp(1.0 - length(VERTEX) / 180.0, 0.0, 1.0);
	col *= 1.0 + (grain - 0.5) * 0.4 * fade + (blades - 0.5) * 0.3 * fade * fade;

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
"""


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000, 8000)
	mesh = plane

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	mat.shader = shader
	mat.set_shader_parameter("noise_soft", _noise(512, 0.012, 4, 11))
	mat.set_shader_parameter("noise_grain", _noise(256, 0.09, 2, 23))
	material_override = mat


func _noise(size: int, freq: float, octaves: int, seed: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.seamless = true
	tex.width = size
	tex.height = size
	tex.generate_mipmaps = true
	return tex
