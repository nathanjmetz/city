class_name FadeMats
extends RefCounted
## Fading versions of the buildings' materials, so a square of town changes
## from its far blocks to its full drawing (and back) as a short dissolve,
## never a pop. Each pixel has a fixed threshold (an interleaved-gradient
## dither on the screen position); a fading-in material draws the pixels
## under its `fade`, the far blocks draw the rest, so the two always cover
## the picture exactly between them, in both renderers and in shadows too.
##
## A fading copy is used only while a square fades (about half a second):
## then the square goes back to the shared materials, so the town's usual
## drawing never pays for the dither.

const DITHER := """
uniform float fade = 1.0;
float fade_dith(vec2 fc) { return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715)))); }
"""

static var _shaders := {}  # Shader -> its fading version


## A fading copy of `mat` (its own, so each square fades on its own), or
## null for a material that isn't a shader (it simply appears).
static func fading(mat: Material) -> ShaderMaterial:
	if not mat is ShaderMaterial or (mat as ShaderMaterial).shader == null:
		return null
	var sh: Shader = (mat as ShaderMaterial).shader
	if not _shaders.has(sh):
		_shaders[sh] = _fade_shader(sh)
	var fs: Shader = _shaders[sh]
	if fs == null:
		return null
	var out: ShaderMaterial = mat.duplicate()
	out.shader = fs
	out.set_shader_parameter("fade", 0.0)
	return out


static func _fade_shader(sh: Shader) -> Shader:
	var code := sh.code
	var at := code.find("void fragment()")
	if at < 0:
		return null
	var brace := code.find("{", at)
	code = code.substr(0, brace + 1) + "\n\tif (fade_dith(FRAGCOORD.xy) >= fade) { discard; }" + code.substr(brace + 1)
	code = _declare(code, DITHER)
	var out := Shader.new()
	out.code = code
	return out


## Puts `decl` right after the shader's first lines (shader_type and
## render_mode), before any function.
static func _declare(code: String, decl: String) -> String:
	var lines := code.split("\n")
	var i := 0
	while i < lines.size() and (lines[i].strip_edges() == "" or lines[i].begins_with("shader_type") \
			or lines[i].begins_with("render_mode")):
		i += 1
	var head := "\n".join(lines.slice(0, i))
	var tail := "\n".join(lines.slice(i))
	return head + "\n" + decl + "\n" + tail


static var _far_shader: Shader


## The far blocks' material for one square of far blocks: the shared "far"
## look, with each quarter of the square (UV2.x: 0 to 3) hidden by `hide`
## (0 shown, 1 gone) where its full drawing has faded in.
static func far_square() -> ShaderMaterial:
	var base: ShaderMaterial = HouseMaterials.get_mat("far")
	if _far_shader == null:
		var code := base.shader.code
		var v := code.find("void vertex()")
		var vb := code.find("{", v)
		code = code.substr(0, vb + 1) + "\n\tfar_hide = hide[clamp(int(UV2.x + 0.5), 0, 3)];" \
			+ "\n\tif (far_hide >= 0.999) { VERTEX = vec3(0.0); }" + code.substr(vb + 1)
		var f := code.find("void fragment()")
		var fb := code.find("{", f)
		code = code.substr(0, fb + 1) + "\n\tif (far_hide > 0.0 && fade_dith(FRAGCOORD.xy) < far_hide) { discard; }" \
			+ code.substr(fb + 1)
		code = _declare(code, DITHER + "uniform vec4 hide = vec4(0.0);\nvarying float far_hide;\n")
		_far_shader = Shader.new()
		_far_shader.code = code
	var out: ShaderMaterial = base.duplicate()
	out.shader = _far_shader
	return out
