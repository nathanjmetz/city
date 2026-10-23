class_name TimelapseView
extends Control
## The growth timelapse (Brawn, 2026-10-23): the town from its first road to
## today, played from the record Timelapse keeps.
##
## Drawn like a Sanborn fire insurance map, the block-by-block maps of
## American towns that historians lay side by side to watch a town grow:
## cream paper, streets left blank between ruled edges, and buildings coloured
## by what they're built of in Sanborn's key: yellow for wood frame (houses),
## pink for brick (Main Street, shops, apartments), blue for stone and
## fireproof (taller offices), grey for iron-clad (factories). Fields, which
## Sanborn sheets left off, get a pale wash so farm country shows.
##
## Covers the screen; Escape (the HUD's close-all) or Close ends it. It only draws when
## the month on screen changes.

signal closed

## Sanborn's colours, as printed (faded a little, as the real sheets are).
const PAPER := Color("#efe6cf")
const PAPER_EDGE := Color("#d9ccaa")
const INK := Color("#3b3225")
const FRAME := Color("#e8c95a")    # yellow: wood frame
const BRICK := Color("#e59a8c")    # pink: brick
const STONE := Color("#8fb3cf")    # blue: stone, fireproof
const IRON := Color("#a5a39b")     # grey: iron-clad
const FIELD := Color("#c9d39a")
## The whole history plays in about this many seconds.
const PLAY_SECONDS := 24.0

var sim: CitySim
var month := 0.0
var playing := true

var _bounds := Rect2()
var _slider := HSlider.new()
var _when := Label.new()
var _nick := Label.new()
var _play := Button.new()
var _drawn := -1
var _snap := {}


func open(s: CitySim) -> void:
	sim = s
	_bounds = _extent()
	month = 0.0
	playing = true
	_slider.max_value = maxf(sim.timelapse.months - 1, 1)
	_drawn = -1
	visible = true
	_refresh()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.dock(false))
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_play.focus_mode = Control.FOCUS_NONE
	_play.custom_minimum_size = Vector2(70, 0)
	_play.pressed.connect(func():
		if month >= _slider.max_value:
			month = 0.0
		playing = not playing
		_refresh())
	row.add_child(_play)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.step = 1.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(v):
		if absf(v - month) >= 1.0:
			month = v
			playing = false
			_refresh())
	row.add_child(_slider)
	var words := VBoxContainer.new()
	words.custom_minimum_size.x = 300
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	for l in [_when, _nick]:
		l.add_theme_font_override("font", Brand.ui(600))
		words.add_child(l)
	_when.add_theme_font_size_override("font_size", 15)
	_nick.add_theme_font_size_override("font_size", 12)
	_nick.add_theme_color_override("font_color", Brand.BRAND_MINT)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_view)
	row.add_child(close)


## Jumps to a month and holds there.
func show_month(m: float) -> void:
	month = clampf(m, 0.0, _slider.max_value)
	playing = false
	_refresh()


func close_view() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	if playing:
		month = minf(month + delta * maxf(sim.timelapse.months, 1) / PLAY_SECONDS, _slider.max_value)
		if month >= _slider.max_value:
			playing = false
		_refresh()


func _refresh() -> void:
	var m := int(month)
	_slider.set_value_no_signal(month)
	_play.text = "Pause" if playing else "Play"
	if m == _drawn:
		return
	_drawn = m
	_snap = sim.timelapse.at(m)
	var tick := m * 24 * CitySim.TICKS_PER_HOUR
	var names := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
		"October", "November", "December"]
	_when.text = "%s %d  ·  %s people" % [names[Seasons.month(tick) - 1], Families.calendar(Seasons.year(tick)),
		CitySim.money_text(int(_snap.pop))]
	_nick.text = ("“%s”" % _snap.nick) if str(_snap.nick) != "" else ""
	queue_redraw()


## Everything the town has ever built (buildings and fields), so the frame
## holds still while it grows. Roads only frame it before anything is built:
## a county highway runs on for miles and would shrink the town to a dot.
func _extent() -> Rect2:
	var pts := []
	for b in sim.timelapse.buildings:
		pts.append_array(b.corners)
	for f in sim.timelapse.fields:
		pts.append(f.c)
	if pts.is_empty():
		for id in sim.timelapse.roads:
			pts.append_array(sim.timelapse.roads[id].pts)
	if pts.is_empty():
		return Rect2(-200, -200, 400, 400)
	var r := Rect2(Vector2(float(pts[0][0]), float(pts[0][1])), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(float(p[0]), float(p[1])))
	return r.grow(maxf(80.0, maxf(r.size.x, r.size.y) * 0.15))


func _draw() -> void:
	if sim == null:
		return
	var area := Rect2(Vector2.ZERO, size - Vector2(0, 52))
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var scale := minf(area.size.x / maxf(_bounds.size.x, 1.0), area.size.y / maxf(_bounds.size.y, 1.0))
	var off := area.get_center() - _bounds.get_center() * scale
	var to := func(x: float, z: float) -> Vector2: return off + Vector2(x, z) * scale
	# Fields first, under everything.
	var cell := Farms.CELL * scale
	for f in _snap.get("fields", []):
		var c: Vector2 = to.call(float(f.c[0]), float(f.c[1]))
		var a := float(f.get("a", 0.0))
		var u := Vector2(cos(a), sin(a)) * cell * 0.48
		var v := Vector2(-u.y, u.x)
		draw_colored_polygon(PackedVector2Array([c - u - v, c + u - v, c + u + v, c - u + v]), FIELD)
	# Streets: ruled edges with the paper left blank between them.
	for r in _snap.get("roads", []):
		var line := PackedVector2Array()
		for p in r.pts:
			line.append(to.call(float(p[0]), float(p[1])))
		var w := maxf(RoadStyle.TYPES[clampi(int(r.type), 0, RoadStyle.TYPES.size() - 1)].width * scale, 2.0)
		draw_polyline(line, INK, w + 2.0, true)
	for r in _snap.get("roads", []):
		var line := PackedVector2Array()
		for p in r.pts:
			line.append(to.call(float(p[0]), float(p[1])))
		var w := maxf(RoadStyle.TYPES[clampi(int(r.type), 0, RoadStyle.TYPES.size() - 1)].width * scale, 2.0)
		draw_polyline(line, PAPER, w, true)
	# Buildings in Sanborn's colours, outlined in ink.
	for b in _snap.get("buildings", []):
		var poly := PackedVector2Array()
		for p in b.corners:
			poly.append(to.call(float(p[0]), float(p[1])))
		if poly.size() < 3:
			continue
		draw_colored_polygon(poly, _colour(b))
		poly.append(poly[0])
		draw_polyline(poly, INK, 1.0, true)
	# A title in the corner, as the sheets have.
	var f := Brand.ui(700)
	var town := _town_name("Your town")
	draw_string(f, Vector2(24, 40), town.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(Brand.ui(500), Vector2(24, 62), "Insurance map of the town, after Sanborn", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(INK, 0.7))
	draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 72)), PAPER_EDGE, false, 2.0)


static func _colour(b: Dictionary) -> Color:
	match str(b.type):
		"house", "row_home": return FRAME
		"factory": return IRON
		"office": return STONE if int(b.storeys) >= 5 else BRICK
	return BRICK


## The town's name (from the Session autoload, looked up at run time so
## tools that load this class before autoloads still compile).
func _town_name(fallback: String) -> String:
	var s := get_node_or_null("/root/Session")
	return str(s.current_name) if s != null and str(s.current_name) != "" else fallback
