extends SceneTree
## Checks that the graphics card works out each county field the same way
## CropCalendar does on the CPU (crop_field and crop_slot in its GLSL), so
## the close-up plants grow the crop the ground is painted with. Needs a
## real renderer (not --headless); run with the desktop renderer and again
## with --rendering-driver opengl3 for the browser's.
## Run: godot -s tools/crop_hash_check.gd

const N := 128

var _vp: SubViewport
var _table: SubViewport
var _frames := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(N, N)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(N, N)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n" + CropCalendar.GLSL + """
void fragment() {
	vec2 px = floor(UV * 128.0);
	vec2 r = vec2(px.x * 97.3 - 6000.0, px.y * 101.1 - 6000.0);
	ivec3 f = crop_field(r);
	ivec2 slot = crop_slot(f.xy);
	COLOR = vec4(float(slot.x) / 255.0, float(slot.y) / 255.0, float(f.z), 1.0);
}
"""
	mat.shader = sh
	rect.material = mat
	_vp.add_child(rect)
	root.add_child(_vp)
	# The table itself, read back through texelFetch.
	_table = SubViewport.new()
	_table.size = Vector2i(CropCalendar.COLS * CropCalendar.TEXELS, CropCalendar.ROWS)
	_table.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var t := ColorRect.new()
	t.size = Vector2(_table.size)
	var tm := ShaderMaterial.new()
	var ts := Shader.new()
	ts.code = "shader_type canvas_item;\n" + CropCalendar.GLSL + """
void fragment() {
	COLOR = vec4(texelFetch(crop_table, ivec2(floor(FRAGCOORD.xy)), 0).rgb, 1.0);
}
"""
	tm.shader = ts
	tm.set_shader_parameter("crop_table", CropCalendar.texture())
	t.material = tm
	_table.add_child(t)
	root.add_child(_table)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var img := _vp.get_texture().get_image()
	var bad := 0
	for y in N:
		for x in N:
			var r := Vector2(x * 97.3 - 6000.0, y * 101.1 - 6000.0)
			var f := CropCalendar.county_field(r)
			var slot := CropCalendar.county_slot(Vector2i(f.x, f.y))
			var c := img.get_pixel(x, y)
			if roundi(c.r * 255.0) != slot.x or roundi(c.g * 255.0) != slot.y or roundi(c.b) != f.z:
				bad += 1
	print("%s: %d of %d county points differ between the graphics card and the CPU" % [
		RenderingServer.get_current_rendering_method(), bad, N * N])
	print("HASH OK" if bad <= N * N / 1000 else "HASH MISMATCH")
	var timg := _table.get_texture().get_image()
	var src := CropCalendar.texture().get_image()
	var worst := 0.0
	for y in 4:
		for x in 16:
			var a := timg.get_pixel(x, y)
			var b := src.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
			if x < 2 and y < 2:
				print("  texel %d,%d table %s  read %s" % [x, y, b, a])
	print("table reads back within %.3f" % worst)
	quit(0 if bad <= N * N / 1000 else 1)
	return false
