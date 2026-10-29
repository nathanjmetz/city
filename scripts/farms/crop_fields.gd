class_name CropFields
extends RefCounted
## The material for the town's farm fields (FarmView): each field reads its
## look for today from the crop table (CropCalendar), so the fields grow,
## ripen, get cut and tilled day by day without the mesh being rebuilt.
##
## Vertex colour: r and g the field's row and timing column in the table
## (n / 255), b a brightness (the headlands a shade darker), a 0 for the
## grassy fencerow verge and 1 for the crop. UV is metres across and back
## from the farmhouse, / 16 (rows run along v, 30 in apart).

## Encodes a table slot and brightness for a vertex.
static func color(row: int, col: int, verge := false, shade := 1.0) -> Color:
	return Color(row / 255.0, col / 255.0, shade, 0.0 if verge else 1.0)


static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = Surfaces.FIELD_COMMON + CropCalendar.GLSL + PhotoGround.glsl() + SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("noise_soft", Ground.noise(512, 0.012, 4, 41))
		_mat.set_shader_parameter("noise_grain", Ground.noise(256, 0.09, 2, 57))
		_mat.set_shader_parameter("crop_table", CropCalendar.texture())
		PhotoGround.apply(_mat)
	return _mat


const SHADER := """
global uniform float snow;
global uniform vec4 season_look;
void fragment() {
	vec2 p = world_pos.xz;
	vec2 m = UV * 16.0;
	// Raw: the slot is data, not a colour (no sRGB conversion either way).
	vec4 vc = COLOR;
	ivec2 slot = ivec2(int(floor(vc.r * 255.0 + 0.5)), int(floor(vc.g * 255.0 + 0.5)));
	float patch = texture(noise_soft, p / 160.0).r;
	float mid = texture(noise_soft, turn(p, 1.1) / 38.0).r;
	float grain = texture(noise_grain, p / 1.7).r;
	vec3 to_eye = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float tilt = length(to_eye.xz) / max(abs(to_eye.y), 0.05);
	float bare;
	vec3 crop = crop_look_bare(slot, p, m.x, fwidth(m.x), tilt, patch, bare);
	crop *= 0.9 + patch * 0.2 + (mid - 0.5) * 0.12;
	// A faint sprayer tramline every 36 m.
	float t = abs(mod(m.x, 36.0) - 18.0);
	float tram = (1.0 - smoothstep(0.25, 0.45, t)) * clamp(0.5 / max(fwidth(m.x), 0.001), 0.0, 1.0);
	// Soil shows through the crop the way it does from the air: thinner,
	// yellower growth on eroded knobs and darker, lusher crop down the swales.
	float knob = smoothstep(0.55, 0.85, texture(noise_soft, turn(p, 0.4) / 95.0 + 0.17).r);
	float swale = smoothstep(0.6, 0.9, texture(noise_soft, turn(p, 2.0) / 140.0 + 0.71).r);
	float growing = crop_texel(slot, 0).a;
	crop = mix(crop, crop * vec3(1.2, 1.1, 0.82), knob * 0.5 * growing);
	crop *= 1.0 - swale * 0.16;
	crop *= 1.0 - tram * 0.1 * growing;
	crop *= (0.96 + grain * 0.08) * vc.b;
	// Fencerow verge: rough grass with brushy darker clumps, tan when dormant.
	vec3 verge = mix(vec3(0.15, 0.21, 0.07), vec3(0.21, 0.22, 0.1), mid);
	verge = mix(verge, vec3(0.30, 0.26, 0.16), clamp(season_look.w, 0.0, 1.0) * 0.8);
	verge *= 0.85 + grain * 0.3;
	vec3 col = mix(verge, crop, vc.a);
	// The desktop's photographed ground (PhotoGround): worked soil between
	// the rows, leaves over it, rough grass on the verge.
	float pk = ph_on(length(VERTEX));
	if (pk > 0.0) {
		vec3 pr = mix(ph_grass(p), mix(ph_grass(p * 1.6), ph_soil(p), bare), vc.a);
		vec2 ps = mix(ph_grass_s(p), mix(ph_grass_s(p * 1.6) * 0.7, ph_soil_s(p) * 0.35, bare), vc.a);
		col *= mix(vec3(1.0), pr, pk);
		NORMAL = normalize((VIEW_MATRIX * vec4(ph_lean((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, ps, pk * 0.9), 0.0)).xyz);
	}
	// Snow, with the stalks and clods of the stubble poking through.
	float lies = smoothstep(0.05, 0.45, snow * (1.15 - (mid - 0.5) * 0.5 - (patch - 0.5) * 0.3));
	vec3 snowy = vec3(0.80, 0.83, 0.88) * (0.94 + patch * 0.08);
	vec4 g = crop_texel(slot, 1);
	snowy = mix(snowy, crop_lin(g.rgb), (0.12 + 0.25 * g.a) * vc.a * (0.6 + 0.8 * grain));
	col = mix(col, snowy, lies);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, lies);
	SPECULAR = 0.25;
}
"""
