class_name GroundView
extends Node3D
## The Ground view (Views > Taken ground, or O): every claim in the town's
## ground map (GroundMap) tinted by what it is, and every piece in a clash
## outlined red (Nathan, 2026-10-29: "railroad tracks running right through
## the city like they're just a part of the ground ... I also noticed street
## signs in the middle of driveways."). Off, it draws and costs nothing.
##
## It draws what the map's survey last found: turned on after the town
## changed, it surveys again (a few milliseconds a frame) and says so in its
## key. Drawing is put together a few milliseconds a frame too, and only
## when the map changed.

## Kind group -> [colour, name in the key]. Kinds not listed draw grey.
const COLORS := {
	"rail_bed": [Color("#8b5a2b"), "Railroad"],
	"rail_row": [Color(0.78, 0.64, 0.48, 0.25), "Railroad's land"],
	"road": [Color("#4c525c"), "Streets"],
	"sidewalk_line": [Color("#c9ccd1"), "Sidewalks"],
	"curb_ramp": [Color("#ffd23f"), "Curb ramps, crosswalks, curb zones"],
	"crosswalk": [Color("#ffd23f"), ""],
	"curb_zone": [Color("#ffd23f"), ""],
	"public_site": [Color("#9b59b6"), "Public sites"],
	"lot": [Color("#5dbb63"), "Lots"],
	"building": [Color("#e67e22"), "Buildings"],
	"drive": [Color("#d2b48c"), "Drives, curb cuts, walks, parking"],
	"curb_cut": [Color("#d2b48c"), ""],
	"front_walk": [Color("#d2b48c"), ""],
	"parking_stall": [Color("#d2b48c"), ""],
	"garage_apron": [Color("#d2b48c"), ""],
	"dock": [Color("#d2b48c"), ""],
	"post": [Color("#2e86de"), "Signs, poles, lamps, mailboxes"],
	"tree_trunk": [Color("#1e6b34"), "Tree trunks"],
	"prop": [Color("#ff6fb5"), "Yard things"],
	"drive_car": [Color("#22d3ee"), "Cars on drives"],
}
const OTHER := Color("#888888")
const CLASH := Color("#ff2a2a")
## How see-through the tints are, and how wide a clash's outline is (m).
const ALPHA := 0.45
const LINE := 0.25
## Milliseconds a frame for putting the drawing together.
const BUILD_MS := 4.0

var sim: CitySim
var on := false
var _fill := MeshInstance3D.new()
var _lines := MeshInstance3D.new()
var _layer := CanvasLayer.new()
var _key := RichTextLabel.new()
var _drawn := -1  # the map's version drawn
var _todo := []  # claims still to draw
var _at := 0
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _lverts := PackedVector3Array()
var _building := false
## Pieces and outlines in the last drawing (tests).
var pieces_drawn := 0
var outlines_drawn := 0


func _ready() -> void:
	visible = false
	for m in [_fill, _lines]:
		add_child(m)
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.vertex_color_use_as_albedo = true
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.no_depth_test = false
	fill.render_priority = 2
	_fill.material_override = fill
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.albedo_color = CLASH
	line.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.render_priority = 3
	_lines.material_override = line
	for m in [_fill, _lines]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layer.layer = 4
	_layer.visible = false
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.dock(false))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-292, 64)
	panel.custom_minimum_size = Vector2(280, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)
	_key.bbcode_enabled = true
	_key.fit_content = true
	_key.scroll_active = false
	_key.custom_minimum_size = Vector2(264, 0)
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.add_theme_font_size_override("normal_font_size", 13)
	panel.add_child(_key)


## Turns the view on or off. On, a town changed since its last survey is
## surveyed again.
func set_on(value: bool) -> void:
	on = value
	visible = value
	_layer.visible = value
	if value and sim != null:
		var g := GroundMap.of(sim)
		if g.survey_stale() and not g.surveying():
			g.survey_start()
		_key_text(g)


func _process(_delta: float) -> void:
	if not on or sim == null:
		return
	var g := GroundMap.of(sim)
	if g.survey_stale() and not g.surveying():
		g.survey_start()
	_key_text(g)
	if g.surveying():
		return
	if not _building and g.version != _drawn:
		_start(g)
	if _building:
		_build_step(g, BUILD_MS)


## Puts the whole drawing together now (tests).
func build_now() -> void:
	var g := GroundMap.of(sim)
	_start(g)
	_build_step(g, 0.0)


func _start(g: GroundMap) -> void:
	_drawn = g.version
	_todo = g.all_claims()
	_at = 0
	_verts = PackedVector3Array()
	_cols = PackedColorArray()
	_lverts = PackedVector3Array()
	pieces_drawn = 0
	outlines_drawn = 0
	_building = true


## Draws claims for about `ms` milliseconds (all of them when 0).
func _build_step(g: GroundMap, ms: float) -> void:
	var t0 := Time.get_ticks_usec()
	while _at < _todo.size():
		var id: int = _todo[_at]
		_at += 1
		var kind := g.kind_of(id)
		var spec: Array = COLORS.get(kind.get_slice(":", 0), [OTHER, ""])
		var col: Color = spec[0]
		if col.a > 0.99:
			col.a = ALPHA
		var lift := 0.12 + 0.004 * float(GroundMap.rank_of(kind))
		for p in range(g._first[id], g._first[id] + g._pieces[id]):
			var poly := g.piece_poly(p)
			var tris := Geometry2D.triangulate_polygon(poly)
			for i in tris:
				var q: Vector2 = poly[i]
				_verts.append(_at_ground(q, lift))
				_cols.append(col)
			pieces_drawn += 1
			if g.clash_pieces.has(p):
				_outline(poly, lift + 0.08)
				outlines_drawn += 1
		if ms > 0.0 and Time.get_ticks_usec() - t0 > ms * 1000.0:
			return
	_building = false
	_commit()


## A red ribbon LINE wide round an outline.
func _outline(poly: PackedVector2Array, lift: float) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if a.distance_to(b) < 0.01:
			continue
		var n := (b - a).normalized().orthogonal() * LINE * 0.5
		var q := [a - n, b - n, b + n, a + n]
		for k in [0, 1, 2, 0, 2, 3]:
			_lverts.append(_at_ground(q[k], lift))


func _at_ground(q: Vector2, lift: float) -> Vector3:
	return Terrain.lift(Vector3(q.x, lift, q.y))


func _commit() -> void:
	var mesh := ArrayMesh.new()
	if not _verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_COLOR] = _cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fill.mesh = mesh
	var lines := ArrayMesh.new()
	if not _lverts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _lverts
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_lines.mesh = lines
	_verts = PackedVector3Array()
	_cols = PackedColorArray()
	_lverts = PackedVector3Array()
	_todo = []


func _key_text(g: GroundMap) -> void:
	var t := "[b]Taken ground[/b]  (%s)\n" % KeyBinds.text("ground_view")
	if g.surveying():
		t += "Surveying the town... %d%%\n" % roundi(g.survey_share() * 100.0)
	elif _building:
		t += "Drawing... %d%%\n" % roundi(100.0 * _at / maxf(_todo.size(), 1.0))
	else:
		t += "%d clashes outlined in red\n" % g.clash_pairs
	for k in COLORS:
		var spec: Array = COLORS[k]
		if spec[1] != "":
			var c: Color = spec[0]
			c.a = 1.0
			t += "[color=#%s]■[/color] %s\n" % [c.to_html(false), spec[1]]
	t += "[color=#%s]□[/color] Clash: two things on ground only one may have" % CLASH.to_html(false)
	if _key.text != t:
		_key.text = t
