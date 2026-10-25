extends SceneTree
## Checks that the graphics card works out each field the same way
## CropCalendar does on the CPU, so the close-up plants grow the crop the
## ground is painted with and every player sees the same crop:
##   county: crop_field and crop_slot (the 32-bit hash) at 65,536 points,
##     from near the town out to 120 km across the region, at whole-metre
##     + 0.5 points (exact in 32-bit floats, half a metre from any field
##     edge, so the CPU's 64-bit sums and the card's 32-bit ones agree);
##   farm: every table slot (128 rows x 32 columns) encoded in a vertex
##     colour as FarmView does (CropFields.color), decoded as the farm field
##     shader does, and the table read back at that slot;
##   table: the whole table read back through texelFetch.
## Every one must match: no mismatches allowed. Needs a real renderer (not
## --headless); run with the desktop renderer and again with
## --rendering-method gl_compatibility (the browser's).
## Run: godot -s tools/crop_hash_check.gd [--rendering-method gl_compatibility]

const N := 256
const BAND := 64  # rows per band of distances
## Metres between points in each band: near the town, the town's
## surroundings, the region, and far out.
const STEP := [7, 97, 389, 937]

var _county: SubViewport
var _farm: SubViewport
var _table: SubViewport
var _frames := 0


## The region point for pixel (x, y), whole numbers + 0.5 (the same sum
## the shader does).
static func point(x: int, y: int) -> Vector2:
	var band := y / BAND
	var s: int = STEP[band]
	return Vector2(x * s - 128 * s + band * 13, (y % BAND) * s * 4 - 128 * s - band * 29) + Vector2(0.5, 0.5)


func _initialize() -> void:
	# A table with farm rows in use and a few the county lends (all farm
	# rows taken), on a date with every stage showing somewhere.
	CropCalendar.set_date(8.6, 3)
	CropCalendar.texture()
	var crops := ["corn", "soybeans", "wheat", "hay", "pasture"]
	var i := 0
	while CropCalendar.farm_rows_used() < CropCalendar.ROWS - CropCalendar.COUNTY_ROWS:
		CropCalendar.farm_row(crops[i % 5], crops[(i / 5) % 5], i % 4, i % 7 == 0, i % 11 == 0)
		i += 1
	CropCalendar.refresh(true)

	_county = _view(Vector2i(N, N), """
void fragment() {
	ivec2 px = ivec2(floor(FRAGCOORD.xy));
	int band = px.y / 64;
	int s = band == 0 ? 7 : (band == 1 ? 97 : (band == 2 ? 389 : 937));
	highp vec2 r = vec2(float(px.x * s - 128 * s + band * 13), float((px.y % 64) * s * 4 - 128 * s - band * 29)) + 0.5;
	ivec3 f = crop_field(r);
	ivec2 slot = crop_slot(f.xy);
	COLOR = vec4(float(slot.x) / 255.0, float(slot.y) / 255.0, float(f.z), 1.0);
}
""", null)

	# Every slot as a one-pixel quad with its vertex colour.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in CropCalendar.ROWS:
		for col in CropCalendar.COLS:
			var c := CropFields.color(row, col, false, 0.96 if (row + col) % 2 == 0 else 1.0)
			var a := Vector3(col, row, 0)
			for v in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]:
				st.set_color(c)
				st.add_vertex(a + v)
	var mesh := MeshInstance2D.new()
	mesh.mesh = st.commit()
	_farm = _view(Vector2i(CropCalendar.COLS, CropCalendar.ROWS), """
void fragment() {
	// As CropFields' shader decodes it.
	vec4 vc = COLOR;
	ivec2 slot = ivec2(int(floor(vc.r * 255.0 + 0.5)), int(floor(vc.g * 255.0 + 0.5)));
	COLOR = vec4(float(slot.x) / 255.0, float(slot.y) / 255.0, crop_texel(slot, 0).r, 1.0);
}
""", mesh)

	_table = _view(Vector2i(CropCalendar.COLS * CropCalendar.TEXELS, CropCalendar.ROWS), """
void fragment() {
	COLOR = texelFetch(crop_table, ivec2(floor(FRAGCOORD.xy)), 0);
}
""", null)


## A viewport drawing `node` (a full-size ColorRect when null) with this
## canvas shader and the crop table.
func _view(size: Vector2i, code: String, node: CanvasItem) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if node == null:
		var rect := ColorRect.new()
		rect.size = Vector2(size)
		node = rect
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode blend_disabled;\n" + CropCalendar.GLSL + code
	mat.shader = sh
	mat.set_shader_parameter("crop_table", CropCalendar.texture())
	node.material = mat
	vp.add_child(node)
	root.add_child(vp)
	return vp


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var method := RenderingServer.get_current_rendering_method()
	# County fields.
	var img := _county.get_texture().get_image()
	var bad := 0
	var far := 0.0
	for y in N:
		for x in N:
			var r := point(x, y)
			far = maxf(far, maxf(absf(r.x), absf(r.y)))
			var f := CropCalendar.county_field(r)
			var slot := CropCalendar.county_slot(Vector2i(f.x, f.y))
			var c := img.get_pixel(x, y)
			if roundi(c.r * 255.0) != slot.x or roundi(c.g * 255.0) != slot.y or roundi(c.b) != f.z:
				if bad < 5:
					print("  county %s: card %d,%d,%d  cpu %d,%d,%d" % [r, roundi(c.r * 255.0), roundi(c.g * 255.0),
						roundi(c.b), slot.x, slot.y, f.z])
				bad += 1
	print("%s county: %d of %d points differ (out to %.0f km)" % [method, bad, N * N, far / 1000.0])
	# Farm field slots.
	var src := CropCalendar.texture().get_image()
	var fimg := _farm.get_texture().get_image()
	var fbad := 0
	for row in CropCalendar.ROWS:
		for col in CropCalendar.COLS:
			var c := fimg.get_pixel(col, row)
			var want := src.get_pixel(col * CropCalendar.TEXELS, row).r
			if roundi(c.r * 255.0) != row or roundi(c.g * 255.0) != col or roundi(c.b * 255.0) != roundi(want * 255.0):
				if fbad < 5:
					print("  farm slot %d,%d: card %d,%d texel %d  cpu texel %d" % [row, col, roundi(c.r * 255.0),
						roundi(c.g * 255.0), roundi(c.b * 255.0), roundi(want * 255.0)])
				fbad += 1
	print("%s farm: %d of %d slots differ" % [method, fbad, CropCalendar.ROWS * CropCalendar.COLS])
	# The table.
	var timg := _table.get_texture().get_image()
	var tbad := 0
	for y in src.get_height():
		for x in src.get_width():
			var a := timg.get_pixel(x, y)
			var b := src.get_pixel(x, y)
			for k in 4:
				if roundi(a[k] * 255.0) != roundi(b[k] * 255.0):
					tbad += 1
					break
	print("%s table: %d of %d texels differ" % [method, tbad, src.get_width() * src.get_height()])
	var ok := bad == 0 and fbad == 0 and tbad == 0
	print("HASH OK" if ok else "HASH MISMATCH")
	quit(0 if ok else 1)
	return false
