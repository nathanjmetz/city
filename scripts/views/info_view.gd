class_name InfoView
extends Node3D
## Map views, like the info views in Cities: Skylines 2: tint the land by
## what it holds (soil fertility, oil, ore, forest) as one smooth, gridless
## wash, and outline the land the player has reserved.
##
## The pollution views (smoke, noise, dirty ground) wash the map the same way
## and pin every source's name over it, so each plume and ring shows where it
## comes from.

enum Mode { NONE, FERTILITY, OIL, ORE, FOREST, NETWORK, SMOKE, NOISE, GROUND }
const POLLUTION := {Mode.SMOKE: "smoke", Mode.NOISE: "noise", Mode.GROUND: "ground"}
## Pollution washes: pixels across (each about 32 m; linear filtering
## smooths them), and the levels where the colour starts and peaks.
const POLLUTION_RES := 128
const POLLUTION_SCALE := {Mode.SMOKE: [1.0, 35.0], Mode.NOISE: [52.0, 80.0], Mode.GROUND: [0.03, 0.7]}
## Milliseconds a frame spent painting a pollution wash.
const PAINT_BUDGET_USEC := 5000
## Source names closer than this to a bigger one's (metres) show just a dot.
const PIN_SPACING := 260.0

## Map area covered by one wash, in metres, and its pixels across. Linear
## filtering blends the pixels into a smooth field.
const EXTENT := 4096.0
const RES := 192
## The wash re-centres on the camera after it moves this far.
const RECENTER := 1024.0
const KIND := {Mode.FERTILITY: Resources.Kind.FERTILITY, Mode.OIL: Resources.Kind.OIL,
	Mode.ORE: Resources.Kind.ORE, Mode.FOREST: Resources.Kind.FOREST}
## Resource views step from poor to rich in flat bands, after CS2: a
## smooth ramp reads as one colour, a step change does not.
const BANDS := 5
## Soil from just farmable (straw) to river-bottom loam (deep green).
const FERTILITY_BANDS := [Color(0.98, 0.88, 0.4, 0.72), Color(0.74, 0.86, 0.3, 0.74),
	Color(0.44, 0.76, 0.22, 0.76), Color(0.18, 0.6, 0.16, 0.8), Color(0.03, 0.4, 0.1, 0.85)]
## Soil too poor for a farm to pay: muted, like the greyed-out map in CS2.
const POOR_SOIL := Color(0.6, 0.52, 0.46, 0.5)
## The line where ground starts to pay.
const LINE_COLOR := Color(0.12, 0.08, 0.04, 0.95)
## Low and high colours for each view.
const RAMPS := {
	Mode.FERTILITY: [POOR_SOIL, FERTILITY_BANDS[BANDS - 1]],
	# Resource views, after CS2: the map greys out and the deposit shows in a
	# strong tint, with a clear step where the ground starts to pay.
	Mode.OIL: [Color(0.82, 0.82, 0.8, 0.5), Color(0.62, 0.38, 0.95, 0.8), Color(0.14, 0.03, 0.3, 0.94)],
	Mode.ORE: [Color(0.82, 0.82, 0.8, 0.5), Color(1.0, 0.64, 0.2, 0.8), Color(0.62, 0.18, 0.04, 0.94)],
	Mode.FOREST: [Color(0.82, 0.82, 0.8, 0.5), Color(0.42, 0.85, 0.32, 0.8), Color(0.02, 0.3, 0.08, 0.94)],
	# Cell signal, like CS2's network quality view: grey where there's none,
	# through amber (one bar) to a strong blue; fiber streets glow cyan.
	Mode.NETWORK: [Color(0.8, 0.8, 0.78, 0.5), Color(0.95, 0.66, 0.2, 0.7), Color(0.12, 0.38, 0.9, 0.85)],
	# Pollution: the map greys out, clean air stays grey, and the pollution
	# shows from a light tint to a strong one.
	Mode.SMOKE: [Color(0.82, 0.82, 0.8, 0.42), Color(0.95, 0.78, 0.35, 0.7), Color(0.45, 0.22, 0.1, 0.92)],
	Mode.NOISE: [Color(0.82, 0.82, 0.8, 0.42), Color(0.98, 0.85, 0.3, 0.72), Color(0.85, 0.1, 0.35, 0.92)],
	Mode.GROUND: [Color(0.82, 0.82, 0.8, 0.42), Color(0.7, 0.68, 0.3, 0.72), Color(0.3, 0.22, 0.08, 0.94)],
}
const FIBER_COLOR := Color(0.2, 0.95, 0.95, 0.95)

signal mode_changed(mode: int)

var sim: CitySim
var cam: CityCamera
var mode := Mode.NONE
## Show reserved land even with no view on (while a reserve tool is out).
var show_reserves := false:
	set(v):
		show_reserves = v
		_draw_reserves()

## Show the future land use map (while a plan tool is out).
var show_plan := false:
	set(v):
		show_plan = v
		_draw_plan()

var _wash := MeshInstance3D.new()
var _wash_mat := StandardMaterial3D.new()
## Resource views: flat bands and the "pays from here" line drawn per pixel
## from the filtered reading, like CS2's smooth resource maps.
const BAND_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D values : filter_linear, repeat_disable;
uniform float line = 0.5;
uniform vec4 poor : source_color;
uniform vec4 b0 : source_color;
uniform vec4 b1 : source_color;
uniform vec4 b2 : source_color;
uniform vec4 b3 : source_color;
uniform vec4 b4 : source_color;
uniform vec4 line_color : source_color;
vec4 band(int i) {
	return i <= 0 ? b0 : i == 1 ? b1 : i == 2 ? b2 : i == 3 ? b3 : b4;
}
void fragment() {
	vec2 r = texture(values, UV).rg;
	float t = (r.x - line) / max(1.0 - line, 0.01) * 5.0;
	// Each step's edge blends over about a pixel around the nearest step,
	// so it reads crisp but not jagged.
	float k = clamp(round(t), 1.0, 4.0);
	float aa = max(fwidth(t), 1e-4);
	vec4 col = mix(band(int(k) - 1), band(int(k)), clamp((t - k) / aa + 0.5, 0.0, 1.0));
	float d = r.x - line;
	float w = max(fwidth(d), 1e-5);
	col = mix(poor, col, clamp(d / w + 0.5, 0.0, 1.0));
	// The line: about two pixels wide on the paying side of the threshold.
	col = mix(col, line_color, 1.0 - smoothstep(1.0, 2.5, abs(d / w - 1.0)));
	col.a *= 1.0 - smoothstep(0.4, 0.6, r.y);
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""
var _band_mat := ShaderMaterial.new()
var _reserves := MeshInstance3D.new()
var _plan := MeshInstance3D.new()
var _center := Vector2(INF, INF)
var _fiber := MeshInstance3D.new()
## Name pins over each pollution source.
var _pins := Node3D.new()
## A pollution wash being painted a few rows a frame: {mode, version, center,
## acc, clean, refs, i, row, box}.
var _job := {}
var _painted_version := -1


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera
	sim.lots_changed.connect(_draw_reserves)
	sim.plan_changed.connect(_draw_plan)
	_wash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wash_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_wash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_wash_mat.disable_fog = true
	_wash.material_override = _wash_mat
	var band_shader := Shader.new()
	band_shader.code = BAND_SHADER
	_band_mat.shader = band_shader
	_band_mat.set_shader_parameter("line_color", LINE_COLOR)
	var res_mat := StandardMaterial3D.new()
	res_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	res_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	res_mat.vertex_color_use_as_albedo = true
	res_mat.no_depth_test = true
	res_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	res_mat.disable_fog = true
	_reserves.material_override = res_mat
	_fiber.material_override = res_mat
	_plan.material_override = res_mat
	for mi in [_wash, _reserves, _fiber, _plan]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
	sim.telecom_changed.connect(func():
		if mode == Mode.NETWORK:
			_center = Vector2(INF, INF))
	add_child(_pins)


func set_mode(m: int) -> void:
	mode = m
	_center = Vector2(INF, INF)
	_fiber.visible = false
	_job = {}
	_painted_version = -1
	# Resource washes show once painted, so a new view never flashes the
	# last one's colours.
	_wash.visible = mode == Mode.NETWORK
	_wash.material_override = _wash_mat
	_draw_pins()
	_draw_reserves()
	mode_changed.emit(mode)


func _process(_delta: float) -> void:
	if mode == Mode.NONE:
		return
	var t := cam.focus()
	var moved := Vector2(t.x, t.z).distance_to(_center) > RECENTER
	if moved:
		_center = Vector2(roundf(t.x / RECENTER) * RECENTER, roundf(t.z / RECENTER) * RECENTER)
	if not POLLUTION.has(mode):
		if moved and mode == Mode.NETWORK:
			_paint_network()
		elif moved:
			var vals := PackedFloat32Array()
			vals.resize(RES * RES)
			_job = {"mode": mode, "center": _center, "line": threshold(KIND[mode], sim),
				"vals": vals, "row": 0, "img": null}
		if not _job.is_empty():
			_paint()
		return
	var pol := sim.pollution
	if pol.sources.is_empty() and pol.version == 0:
		pol.rebuild(sim)
	if _job.is_empty() and (moved or pol.version != _painted_version):
		_start_pollution()
	if not _job.is_empty():
		_paint_pollution()


## Samples the resource a few rows a frame, then colours it in the same
## way, so opening a view or panning never stalls a slow machine.
func _paint() -> void:
	var j := _job
	var kind: int = KIND[j.mode]
	var line: float = j.line
	var vals: PackedFloat32Array = j.vals
	var step := EXTENT / RES
	var origin: Vector2 = j.center - Vector2(EXTENT, EXTENT) * 0.5
	var start := Time.get_ticks_usec()
	while j.row < RES:
		var y: int = j.row
		for x in RES:
			var p := Vector3(origin.x + (x + 0.5) * step, 0.0, origin.y + (y + 0.5) * step)
			vals[y * RES + x] = Resources.at(kind, p, Terrain.view_origin)
		j.row += 1
		if Time.get_ticks_usec() - start > PAINT_BUDGET_USEC:
			j.vals = vals
			return
	j.vals = vals
	if j.img == null:
		j.img = Image.create(RES, RES, false, Image.FORMAT_RGH)
	var img: Image = j.img
	while j.row < RES * 2:
		var y: int = j.row - RES
		for x in RES:
			# The raw reading (half floats: 8 bits made the steps stair-step)
			# goes to the GPU, which draws the bands and the
			# line between texels (BAND_SHADER), so edges come out smooth
			# instead of 21 m stair steps. Rivers (no soil) take their banks'
			# reading and are cleared there, so no line runs along the water.
			var v := vals[y * RES + x]
			var water := kind == Resources.Kind.FERTILITY and v <= 0.0
			if water:
				v = maxf(maxf(_at(vals, x - 1, y), _at(vals, x + 1, y)), maxf(_at(vals, x, y - 1), _at(vals, x, y + 1)))
			img.set_pixel(x, y, Color(v, 1.0 if water else 0.0, 0.0))
		j.row += 1
		if Time.get_ticks_usec() - start > PAINT_BUDGET_USEC:
			return
	_band_mat.set_shader_parameter("values", ImageTexture.create_from_image(img))
	_band_mat.set_shader_parameter("line", line)
	var cols: Array = FERTILITY_BANDS if j.mode == Mode.FERTILITY else []
	if cols.is_empty():
		for b in BANDS:
			cols.append(band_color(j.mode, line + (b + 0.5) / BANDS * (1.0 - line), line))
	for b in BANDS:
		_band_mat.set_shader_parameter("b%d" % b, cols[b])
	_band_mat.set_shader_parameter("poor", band_color(j.mode, line - 0.01, line))
	_wash.material_override = _band_mat
	_wash.mesh = _land_sheet(j.center)
	_wash.visible = true
	_job = {}


static func _at(vals: PackedFloat32Array, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= RES or y >= RES:
		return 0.0
	return vals[y * RES + x]


## Where ground starts to pay: the soil a new farm breaks even on today
## (Farms.break_even_fertility), or the richness a company needs.
static func threshold(kind: int, s: CitySim) -> float:
	if kind != Resources.Kind.FERTILITY:
		return Industry.MIN_RICHNESS
	return s.farms.break_even_fertility() if s else 0.5


## Which step from poor to rich `v` is in, counted up from the line.
static func band(v: float, line: float) -> int:
	if v < line:
		return -1
	return clampi(floori((v - line) / maxf(1.0 - line, 0.01) * BANDS), 0, BANDS - 1)


## The flat colour for a resource reading: greyed out below the line, then
## one of BANDS steps, so 20 points of difference is a different colour.
static func band_color(m: int, v: float, line: float) -> Color:
	var b := band(v, line)
	if m == Mode.FERTILITY:
		if v <= 0.0:
			return Color(0, 0, 0, 0)
		return POOR_SOIL if b < 0 else FERTILITY_BANDS[b]
	var ramp: Array = RAMPS[m]
	if b < 0:
		return ramp[0]
	return (ramp[1] as Color).lerp(ramp[2], float(b) / (BANDS - 1))


## Cell signal across the area, and every fiber street as a bright line.
func _paint_network() -> void:
	var ramp: Array = RAMPS[Mode.NETWORK]
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var step := EXTENT / RES
	var origin := _center - Vector2(EXTENT, EXTENT) * 0.5
	for y in RES:
		for x in RES:
			var v := sim.telecom.signal_at(Vector3(origin.x + (x + 0.5) * step, 0.0, origin.y + (y + 0.5) * step))
			var col: Color = (ramp[0] as Color).lerp(ramp[1], clampf(v / Balance.TELECOM_GOOD_SIGNAL, 0.0, 1.0)) \
				if v < Balance.TELECOM_GOOD_SIGNAL else (ramp[1] as Color).lerp(ramp[2],
					clampf((v - Balance.TELECOM_GOOD_SIGNAL) / (1.0 - Balance.TELECOM_GOOD_SIGNAL), 0.0, 1.0))
			img.set_pixel(x, y, col)
	_wash_mat.albedo_texture = ImageTexture.create_from_image(img)
	_wash.mesh = _land_sheet(_center)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.telecom.companies:
		for f in sim.telecom.companies[id].fiber:
			var pts: Array = f.pts
			for i in range(1, pts.size()):
				var a := Vector3(pts[i - 1][0], 0.0, pts[i - 1][1])
				var b := Vector3(pts[i][0], 0.0, pts[i][1])
				if a.distance_to(b) < 0.01:
					continue
				var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * 2.2
				for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
					st.set_color(FIBER_COLOR)
					st.set_normal(Vector3.UP)
					st.add_vertex(v + Vector3(0, 1.6, 0))
				any = true
	_fiber.visible = any
	if any:
		_fiber.mesh = Terrain.drape(st.commit(), true, 12.0)


## A sheet over the land around `center`, a little above the ground and
## following its hills, with UVs across the whole wash.
static func _land_sheet(center: Vector2) -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT, EXTENT)
	plane.subdivide_width = int(EXTENT / 16.0)
	plane.subdivide_depth = int(EXTENT / 16.0)
	var arrays := plane.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i] + Vector3(center.x, 0.0, center.y)
		verts[i] = Vector3(v.x, Terrain.ground_y(v.x, v.z) + 1.2, v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Pollution ------------------------------------------------------------------

func _start_pollution() -> void:
	var pol := sim.pollution
	var n := POLLUTION_RES * POLLUTION_RES
	var acc := PackedFloat32Array()
	acc.resize(n)
	var clean := PackedFloat32Array()
	clean.resize(n)
	clean.fill(1.0)
	var kind: String = POLLUTION[mode]
	var refs := []
	var keys := pol.sources.keys()
	keys.sort()
	for ref in keys:
		if pol.sources[ref].boxes.has(kind):
			refs.append(ref)
	_job = {"mode": mode, "kind": kind, "version": pol.version, "center": _center, "acc": acc, "clean": clean,
		"refs": refs, "i": 0, "row": -1, "rows": Vector2i.ZERO, "cols": Vector2i.ZERO}


## Paints the wash source by source, a few rows a frame, then shows it.
func _paint_pollution() -> void:
	var pol := sim.pollution
	var j := _job
	var step := EXTENT / POLLUTION_RES
	var origin: Vector2 = j.center - Vector2(EXTENT, EXTENT) * 0.5
	var start := Time.get_ticks_usec()
	var acc: PackedFloat32Array = j.acc
	var clean: PackedFloat32Array = j.clean
	while j.i < j.refs.size():
		if not pol.sources.has(j.refs[j.i]):
			j.i += 1
			j.row = -1
			continue
		var s: Dictionary = pol.sources[j.refs[j.i]]
		if j.row < 0:
			var box: Rect2 = s.boxes[j.kind]
			j.cols = Vector2i(clampi(floori((box.position.x - origin.x) / step), 0, POLLUTION_RES),
				clampi(ceili((box.end.x - origin.x) / step), 0, POLLUTION_RES))
			j.rows = Vector2i(clampi(floori((box.position.y - origin.y) / step), 0, POLLUTION_RES),
				clampi(ceili((box.end.y - origin.y) / step), 0, POLLUTION_RES))
			j.row = j.rows.x
		while j.row < j.rows.y:
			var y: int = j.row
			for x in range(j.cols.x, j.cols.y):
				var p := Vector3(origin.x + (x + 0.5) * step, 0.0, origin.y + (y + 0.5) * step)
				var v := pol.source_at(s, p, j.kind)
				var k := y * POLLUTION_RES + x
				match j.kind:
					"smoke": acc[k] += v.x
					"noise": acc[k] += v.y
					_: clean[k] *= 1.0 - v.z
			j.row += 1
			if Time.get_ticks_usec() - start > PAINT_BUDGET_USEC:
				j.acc = acc
				j.clean = clean
				return
		j.i += 1
		j.row = -1
	# Done: colour it in.
	var ramp: Array = RAMPS[j.mode]
	var scale: Array = POLLUTION_SCALE[j.mode]
	var img := Image.create(POLLUTION_RES, POLLUTION_RES, false, Image.FORMAT_RGBA8)
	for y in POLLUTION_RES:
		for x in POLLUTION_RES:
			var k := y * POLLUTION_RES + x
			var v: float
			match j.kind:
				"smoke": v = acc[k]
				"noise": v = Pollution.db(acc[k])
				_: v = 1.0 - clean[k]
			var t := clampf((v - float(scale[0])) / (float(scale[1]) - float(scale[0])), 0.0, 1.0)
			# Grey where it's clean, fading into the tint as it climbs, so
			# ordinary town sound and faint haze stay out of the way.
			var col: Color = (ramp[1] as Color).lerp(ramp[2], sqrt(t))
			col = (ramp[0] as Color).lerp(col, smoothstep(0.0, 0.3, t))
			img.set_pixel(x, y, col)
	_wash_mat.albedo_texture = ImageTexture.create_from_image(img)
	_wash.mesh = _land_sheet(j.center)
	_wash.visible = true
	_painted_version = j.version
	_job = {}
	_draw_pins()


## A floating name over each source of this view's pollution, so every
## plume and ring is labelled with what makes it.
func _draw_pins() -> void:
	for c in _pins.get_children():
		_pins.remove_child(c)
		c.queue_free()
	if not POLLUTION.has(mode) or sim == null:
		return
	var kind: String = POLLUTION[mode]
	var pol := sim.pollution
	var keys := pol.sources.keys()
	keys.sort()
	var tint: Color = RAMPS[mode][2]
	# Strongest sources get their names first; one close to a named one
	# keeps just its dot, so a row of factories stays readable.
	var pins := []
	for ref in keys:
		var s: Dictionary = pol.sources[ref]
		if not s.boxes.has(kind):
			continue
		var at: Vector3 = s.center
		if not s.lines.is_empty():
			# Roads: pin the middle piece of the road, not the open middle of a loop.
			var l: Array = s.lines[s.lines.size() / 2]
			at = (l[0] as Vector3).lerp(l[1], 0.5)
		var strength: float = {"smoke": s.smoke, "noise": s.noise, "ground": s.ground}[kind]
		for l in s.lines:
			strength = maxf(strength, l[3] if kind == "smoke" else (l[2] if kind == "noise" else 0.0))
		pins.append([strength, ref, at])
	pins.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var named := []
	for pin in pins:
		var s: Dictionary = pol.sources[pin[1]]
		var at: Vector3 = pin[2]
		var crowded := false
		for p in named:
			crowded = crowded or Vector2(p.x - at.x, p.z - at.z).length() < PIN_SPACING
		var ground := Terrain.ground_y(at.x, at.z)
		_add_dot(at, ground, tint)
		if crowded:
			continue
		named.append(at)
		var label := Label3D.new()
		label.text = s.name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0009
		label.font_size = 26
		label.outline_size = 10
		label.modulate = Color.WHITE
		label.outline_modulate = Color(tint, 0.95)
		label.render_priority = 20
		label.outline_render_priority = 19
		label.position = Vector3(at.x, ground + 22.0, at.z)
		_pins.add_child(label)


func _add_dot(at: Vector3, ground: float, tint: Color) -> void:
	var dot := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 4.0
	m.height = 8.0
	dot.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.no_depth_test = true
	mat.render_priority = 18
	dot.material_override = mat
	dot.position = Vector3(at.x, ground + 6.0, at.z)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pins.add_child(dot)


## Reserved land: a tinted fill and a bright border in its industry's colour.
func _draw_reserves() -> void:
	if sim == null:
		return
	_reserves.visible = (mode != Mode.NONE or show_reserves) and not sim.reserves.outlines.is_empty()
	if not _reserves.visible:
		return
	var m := _outlines_mesh(sim.reserves.outlines, Reserves.COLORS)
	_reserves.visible = m != null
	if m != null:
		_reserves.mesh = m


## The land use plan: each area tinted in its colour with a bright border.
func _draw_plan() -> void:
	if sim == null:
		return
	_plan.visible = show_plan and not sim.land_plan.outlines.is_empty()
	if not _plan.visible:
		return
	# Big areas seen from high up: bolder than reserves.
	var m := _outlines_mesh(sim.land_plan.outlines, LandPlan.COLORS, 0.34, 3.0)
	_plan.visible = m != null
	if m != null:
		_plan.mesh = m


## Outlines ({points, kind}) as a tinted fill and a bright border, draped on
## the ground; null when there are none to show.
func _outlines_mesh(outlines: Array, colors: Dictionary, alpha := 0.22, border := 1.2) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for o in outlines:
		if o.kind == "":
			continue
		var col: Color = colors[o.kind]
		var fill := Color(col, alpha)
		var poly: PackedVector2Array = o.points
		var tris := Geometry2D.triangulate_polygon(poly)
		for k in tris:
			st.set_color(fill)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(poly[k].x, 0.4, poly[k].y))
		var ring := PackedVector3Array()
		for p in poly:
			ring.append(Vector3(p.x, 0.0, p.y))
		ring.append(ring[0])
		for i in ring.size() - 1:
			var a := ring[i]
			var b := ring[i + 1]
			var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * border
			for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
				st.set_color(Color(col, 0.9))
				st.set_normal(Vector3.UP)
				st.add_vertex(v + Vector3(0, 0.45, 0))
		any = true
	return Terrain.drape(st.commit(), true, 12.0) if any else null
