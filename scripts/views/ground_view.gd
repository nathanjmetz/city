class_name GroundView
extends Node3D
## The Ground view (Views > Taken ground, or O): every claim in the town's
## ground map (GroundMap) tinted by what it is, and every piece in a clash
## outlined red (Nathan, 2026-10-29: "railroad tracks running right through
## the city like they're just a part of the ground ... I also noticed street
## signs in the middle of driveways."). Off, it draws and costs nothing.
##
## It draws the live layer and what the map's last finished survey found:
## turned on after the town changed, it surveys again (a few milliseconds
## a frame) and says so in its key, showing the last survey meanwhile.
## Drawing is put together a few milliseconds a frame too, when the map
## changed, at most every REDRAW_MS.

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
## Milliseconds a frame for putting the drawing together, and the least
## time between two drawings (a growing town changes all the time).
const BUILD_MS := 3.0
## Corners a surface of the tints' mesh holds.
const CHUNK := 24000
const REDRAW_MS := 2000

var sim: CitySim
var on := false
var _fill := MeshInstance3D.new()
var _lines := MeshInstance3D.new()
var _layer := CanvasLayer.new()
var _title := Button.new()  # "Taken ground (O) · 434 clashes": folds and unfolds the key
var _status := Label.new()
var _rows := VBoxContainer.new()
var _fold = null  # the player's choice (true folded); null: by the screen's width
var _width := -1.0  # the width the key was last laid out for (-1: the window's)
var _drawn := []  # what the drawing was made from (_stamp)
var _drawn_at := -100000
var _maps := []  # the maps being drawn: the live layer, the last survey
var _m := 0
var _at := 0
var _p := -1  # the piece of claim _at drawn next (-1: its first)
var _mesh: ArrayMesh  # the tints' mesh under way
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _lverts := PackedVector3Array()
var _building := false
## Pieces and outlines in the last drawing, and its worst frame (ms).
var pieces_drawn := 0
var outlines_drawn := 0
var max_step_ms := 0.0


func _init() -> void:
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
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -12.0
	panel.offset_top = 64.0
	_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	_title.flat = true
	_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_font_size_override("font_size", 14)
	_title.tooltip_text = "Show or hide the key"
	_title.pressed.connect(func(): _fold = not folded(_width))
	col.add_child(_title)
	_status.add_theme_font_size_override("font_size", 12)
	col.add_child(_status)
	_rows.add_theme_constant_override("separation", 3)
	col.add_child(_rows)
	for k in COLORS:
		var spec: Array = COLORS[k]
		if spec[1] != "":
			var c: Color = spec[0]
			c.a = 1.0
			_rows.add_child(_row(c, false, spec[1]))
	_rows.add_child(_row(CLASH, true, "Clash: two things on ground only one may have"))


## A key row: a SWATCH px square of `colour` (an outline only for a clash)
## and its name.
const SWATCH := 13
func _row(colour: Color, outline: bool, name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(SWATCH, SWATCH)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0) if outline else colour
	box.border_color = colour if outline else colour.darkened(0.3)
	box.set_border_width_all(2 if outline else 1)
	sw.add_theme_stylebox_override("panel", box)
	row.add_child(sw)
	var label := Label.new()
	label.text = name
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	return row


## Below this width the key starts folded to its title line (it covers half
## a phone's screen open); a click on the title folds or unfolds it.
const NARROW := 600.0


## True when the key shows its title line alone, on a screen `width` px
## wide (the window's when not given).
func folded(width := -1.0) -> bool:
	if _fold != null:
		return _fold
	if width < 0.0:
		var vp := get_viewport()
		width = vp.get_visible_rect().size.x if vp != null else NARROW
	return width < NARROW


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
	# The town changed since the last survey: survey it again, showing the
	# last one finished until the new one is in.
	if g.survey_stale() and not g.surveying():
		g.survey_start()
	_key_text(g)
	if not _building and _stamp(g) != _drawn and Time.get_ticks_msec() - _drawn_at >= REDRAW_MS:
		_start(g)
	if _building:
		_build_step(g, BUILD_MS)


## Puts the whole drawing together now (tests).
func build_now() -> void:
	var g := GroundMap.of(sim)
	_start(g)
	_build_step(g, 0.0)


## What the drawing was made from: the live layer's and the survey's versions.
func _stamp(g: GroundMap) -> Array:
	return [g.version, g.survey.version if g.survey != null else -1, g.survey]


func _start(g: GroundMap) -> void:
	_drawn = _stamp(g)
	_drawn_at = Time.get_ticks_msec()
	_maps = [g] if g.survey == null else [g, g.survey]
	_m = 0
	_at = 0
	_p = -1
	_mesh = ArrayMesh.new()
	_verts = PackedVector3Array()
	_cols = PackedColorArray()
	_lverts = PackedVector3Array()
	pieces_drawn = 0
	outlines_drawn = 0
	_building = true
	max_step_ms = 0.0


## Draws claims for about `ms` milliseconds (all of them when 0): the live
## layer's, then the last survey's (each map's claims in the order filed),
## then the clashes the survey found with the live layer.
func _build_step(g: GroundMap, ms: float) -> void:
	var t0 := Time.get_ticks_usec()
	while _m < _maps.size():
		var map: GroundMap = _maps[_m]
		var clashes: Dictionary = g.survey.clash_pieces if g.survey != null and map == g.survey else {}
		while _at < map._owner.size():
			var id := _at
			if map._alive[id] == 0:
				_at += 1
				_p = -1
				continue
			var kind := map.kind_of(id)
			var spec: Array = COLORS.get(kind.get_slice(":", 0), [OTHER, ""])
			var col: Color = spec[0]
			if col.a > 0.99:
				col.a = ALPHA
			var lift := 0.12 + 0.004 * float(GroundMap.rank_of(kind))
			if _p < 0:
				_p = map._first[id]
			# A piece at a time, so a long road or railroad is drawn over a
			# few frames.
			while _p < map._first[id] + map._pieces[id]:
				var p := _p
				_p += 1
				var poly := map.piece_poly(p)
				for i in Geometry2D.triangulate_polygon(poly):
					_verts.append(_at_ground(poly[i], lift))
					_cols.append(col)
				pieces_drawn += 1
				if _verts.size() >= CHUNK:
					_flush()
				if clashes.has(p):
					_outline(poly, lift + 0.08)
					outlines_drawn += 1
				if ms > 0.0 and Time.get_ticks_usec() - t0 > ms * 1000.0:
					max_step_ms = maxf(max_step_ms, (Time.get_ticks_usec() - t0) / 1000.0)
					return
			_at += 1
			_p = -1
		_m += 1
		_at = 0
	if g.survey != null:
		for poly in g.survey.live_clashes:
			_outline(poly, 0.12 + 0.004 * 20.0 + 0.08)
			outlines_drawn += 1
	_building = false
	_commit()
	max_step_ms = maxf(max_step_ms, (Time.get_ticks_usec() - t0) / 1000.0)


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


## The tints drawn so far handed to the mesh under way as one more surface
## (a big town's drawing goes in a few dozen, a frame's worth at a time).
func _flush() -> void:
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_verts = PackedVector3Array()
	_cols = PackedColorArray()


func _commit() -> void:
	_flush()
	_fill.mesh = _mesh
	_mesh = null
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
	_maps = []


func _key_text(g: GroundMap, width := -1.0) -> void:
	_width = width
	var fold := folded(width)
	var t := "%s Taken ground (%s)" % ["▸" if fold else "▾", KeyBinds.text("ground_view")]
	var status := ""
	if g.survey != null:
		t += " · %d clashes" % g.survey.clash_pairs
	if g.surveying():
		status = ("Surveying the town again... %d%%" if g.survey != null else "Surveying the town... %d%%") \
			% roundi(g.survey_share() * 100.0)
		if g.survey == null:
			t += " · surveying"
	elif _building:
		status = "Drawing..."
	if _title.text != t:
		_title.text = t
	if _status.text != status:
		_status.text = status
	_status.visible = not fold and status != ""
	_rows.visible = not fold
