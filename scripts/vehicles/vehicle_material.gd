class_name VehicleMaterial
extends RefCounted
## One shader for every vehicle. Vertex alpha picks the surface (see
## VehicleModels); per-instance custom data carries the body colour (sRGB) in
## rgb and, in alpha, 1 while braking plus 2 while running emergency lights.
## Cheap enough for the Compatibility renderer.

const SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec4 v_custom;
varying float v_side;
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_side = VERTEX.x;
}
void fragment() {
	float code = COLOR.a;
	vec3 col = lin(COLOR.rgb);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	if (code < 0.05) {          // body paint
		col = lin(v_custom.rgb);
		rough = 0.28;
		metal = 0.12;
		spec = 0.6;
	} else if (code < 0.15) {   // glass
		rough = 0.04;
		spec = 0.9;
	} else if (code < 0.25) {   // chrome, steel
		rough = 0.28;
		metal = 0.85;
	} else if (code < 0.35) {   // black plastic, rubber
		rough = 0.85;
		spec = 0.25;
	} else if (code < 0.45) {   // fixed colours (decals, liveries)
		rough = 0.45;
	} else if (code < 0.55) {   // headlights
		rough = 0.1;
		emit = col * 0.35;
	} else if (code < 0.65) {   // tail lights, bright when braking
		float brake = mod(v_custom.a, 2.0);
		rough = 0.2;
		emit = vec3(1.0, 0.04, 0.02) * (0.15 + brake * 2.5);
	} else if (code < 0.75) {   // red and blue emergency lights
		float on = step(1.5, v_custom.a);
		float flash = step(0.5, fract(TIME * 1.6 + (v_side > 0.0 ? 0.5 : 0.0)));
		col *= 0.5;
		emit = lin(COLOR.rgb) * on * flash * 4.0;
	} else {                    // amber beacons always turn
		float flash = step(0.55, fract(TIME * 1.1));
		col *= 0.6;
		emit = lin(COLOR.rgb) * flash * 3.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
"""

static var _mat: ShaderMaterial


static func get_material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat
