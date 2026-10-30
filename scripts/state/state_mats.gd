class_name StateMats
extends RefCounted
## The state layer's two materials (StateView): the town's own shaders, so
## the props are lit, darkened at night and snowed on like everything round
## them, with three things added:
##   - each prop dissolves out by its own distance from the camera between
##     fade_a and fade_b (a dither, on screen and in shadows alike, as
##     NearMats does), so the ring's edge never pops;
##   - "props" (HouseMaterials' plain paint) takes a colour per prop from its
##     instance (MultiMesh custom data, sRGB) on the parts marked for it, so
##     one mesh serves every couch, cart and dumpster in its own colour;
##   - parts can be switched per prop (custom alpha bit 1: the mattress
##     leaned on a couch) or by the season (bloom: annuals in flower).
## Vertex alpha codes in the props meshes (StateMeshes): 1 a fixed colour,
## 0.9 a fixed colour shown only with bit 1, 0.65 the instance's colour,
## 0.4 fixed-colour foliage, 0.25 flowers in the instance's colour and 0.15
## flowers in their own, both shown only in bloom. The car keeps
## VehicleMaterial's codes and custom data.

const DECL := """
uniform float fade_a = 130.0;
uniform float fade_b = 150.0;
uniform float bloom = 1.0;
varying float state_w;
float state_dith(vec2 fc) { return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715)))); }
"""
const FADE_VERTEX := """
	state_w = 1.0 - smoothstep(fade_a, fade_b, distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz));
	bool state_hide = state_w <= 0.0;
"""
const PARTS_VERTEX := """
	int state_flags = int(INSTANCE_CUSTOM.a + 0.5);
	if (COLOR.a > 0.85 && COLOR.a < 0.95) {
		state_hide = state_hide || (state_flags & 1) == 0;
		COLOR.a = 1.0;
	} else if (COLOR.a > 0.6 && COLOR.a < 0.7) {
		COLOR.rgb = INSTANCE_CUSTOM.rgb;
		COLOR.a = 1.0;
	} else if (COLOR.a > 0.2 && COLOR.a < 0.3) {
		COLOR.rgb = INSTANCE_CUSTOM.rgb;
		COLOR.a = 0.0;
		state_hide = state_hide || bloom < 0.5;
	} else if (COLOR.a > 0.1 && COLOR.a < 0.2) {
		COLOR.a = 0.0;
		state_hide = state_hide || bloom < 0.5;
	}
"""
const HIDE_VERTEX := """
	if (state_hide) {
		VERTEX = vec3(0.0);
	}
"""
const FADE_FRAGMENT := """
	if (state_w < 1.0 && state_dith(FRAGCOORD.xy) >= state_w) {
		discard;
	}
"""

static var _props: ShaderMaterial
static var _car: ShaderMaterial


## The plain paint every prop but the car is drawn in.
static func props() -> ShaderMaterial:
	if _props == null:
		var base: ShaderMaterial = HouseMaterials.get_mat("paint")
		_props = base.duplicate()
		_props.shader = _inject(base.shader.code, FADE_VERTEX + PARTS_VERTEX + HIDE_VERTEX)
	return _props


## The cars' own material (the car on blocks).
static func car() -> ShaderMaterial:
	if _car == null:
		var base := VehicleMaterial.get_material()
		_car = base.duplicate()
		_car.shader = _inject(base.shader.code, FADE_VERTEX + HIDE_VERTEX)
	return _car


## Where both fade, and whether the annuals are in bloom.
static func set_reach(a: float, b: float, in_bloom: bool) -> void:
	for m in [props(), car()]:
		m.set_shader_parameter("fade_a", a)
		m.set_shader_parameter("fade_b", b)
	props().set_shader_parameter("bloom", 1.0 if in_bloom else 0.0)


static func _inject(code: String, vertex: String) -> Shader:
	var v := code.find("void vertex()")
	var vb := code.find("{", v)
	code = code.substr(0, vb + 1) + vertex + code.substr(vb + 1)
	var f := code.find("void fragment()")
	var fb := code.find("{", f)
	code = code.substr(0, fb + 1) + FADE_FRAGMENT + code.substr(fb + 1)
	var sh := Shader.new()
	sh.code = FadeMats._declare(code, DECL)
	return sh
