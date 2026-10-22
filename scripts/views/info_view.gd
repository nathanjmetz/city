class_name InfoView
extends Node3D
## Map views, like the info views in Cities: Skylines 2: tint the land by
## what it holds (soil fertility, oil, ore, forest) as one smooth, gridless
## wash, and outline the land the player has reserved.

enum Mode { NONE, FERTILITY, OIL, ORE, FOREST }

## Map area covered by one wash, in metres, and its pixels across. Linear
## filtering blends the pixels into a smooth field.
const EXTENT := 4096.0
const RES := 192
## The wash re-centres on the camera after it moves this far.
const RECENTER := 1024.0
const KIND := {Mode.FERTILITY: Resources.Kind.FERTILITY, Mode.OIL: Resources.Kind.OIL,
	Mode.ORE: Resources.Kind.ORE, Mode.FOREST: Resources.Kind.FOREST}
## Low and high colours for each view.
const RAMPS := {
	Mode.FERTILITY: [Color(0.75, 0.38, 0.16, 0.55), Color(0.12, 0.7, 0.1, 0.55)],
	Mode.OIL: [Color(0.2, 0.2, 0.2, 0.08), Color(0.12, 0.08, 0.2, 0.85)],
	Mode.ORE: [Color(0.4, 0.35, 0.3, 0.08), Color(0.85, 0.4, 0.15, 0.85)],
	Mode.FOREST: [Color(0.3, 0.35, 0.25, 0.08), Color(0.08, 0.4, 0.12, 0.85)],
}

signal mode_changed(mode: int)

var sim: CitySim
var cam: CityCamera
var mode := Mode.NONE
## Show reserved land even with no view on (while a reserve tool is out).
var show_reserves := false:
	set(v):
		show_reserves = v
		_draw_reserves()

var _wash := MeshInstance3D.new()
var _wash_mat := StandardMaterial3D.new()
var _reserves := MeshInstance3D.new()
var _center := Vector2(INF, INF)


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera
	sim.lots_changed.connect(_draw_reserves)
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT, EXTENT)
	_wash.mesh = plane
	_wash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wash_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_wash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_wash_mat.disable_fog = true
	_wash.material_override = _wash_mat
	var res_mat := StandardMaterial3D.new()
	res_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	res_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	res_mat.vertex_color_use_as_albedo = true
	res_mat.no_depth_test = true
	res_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	res_mat.disable_fog = true
	_reserves.material_override = res_mat
	for mi in [_wash, _reserves]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)


func set_mode(m: int) -> void:
	mode = m
	_center = Vector2(INF, INF)
	_wash.visible = mode != Mode.NONE
	_draw_reserves()
	mode_changed.emit(mode)


func _process(_delta: float) -> void:
	if mode == Mode.NONE:
		return
	var t := cam.focus()
	if Vector2(t.x, t.z).distance_to(_center) > RECENTER:
		_center = Vector2(roundf(t.x / RECENTER) * RECENTER, roundf(t.z / RECENTER) * RECENTER)
		_paint()


## Samples the resource across the area into a small texture.
func _paint() -> void:
	var kind: int = KIND[mode]
	var ramp: Array = RAMPS[mode]
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var step := EXTENT / RES
	var origin := _center - Vector2(EXTENT, EXTENT) * 0.5
	for y in RES:
		for x in RES:
			var p := Vector3(origin.x + (x + 0.5) * step, 0.0, origin.y + (y + 0.5) * step)
			var v := Resources.at(kind, p)
			if kind == Resources.Kind.FERTILITY:
				v = (v - 0.5) / 0.4
			img.set_pixel(x, y, (ramp[0] as Color).lerp(ramp[1], clampf(v, 0.0, 1.0)))
	_wash_mat.albedo_texture = ImageTexture.create_from_image(img)
	_wash.position = Vector3(_center.x, 0.25, _center.y)


## Reserved land: a tinted fill and a bright border in its industry's colour.
func _draw_reserves() -> void:
	if sim == null:
		return
	_reserves.visible = (mode != Mode.NONE or show_reserves) and not sim.reserves.outlines.is_empty()
	if not _reserves.visible:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for o in sim.reserves.outlines:
		if o.kind == "":
			continue
		var col: Color = Reserves.COLORS[o.kind]
		var fill := Color(col, 0.22)
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
			var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * 1.2
			for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
				st.set_color(Color(col, 0.9))
				st.set_normal(Vector3.UP)
				st.add_vertex(v + Vector3(0, 0.45, 0))
		any = true
	_reserves.visible = any
	if any:
		_reserves.mesh = st.commit()
