class_name Hud
extends CanvasLayer
## Toolbar along the bottom, tips and town stats in the corners.

var road_tool: RoadTool
var zone_tool: ZoneTool
var sim: CitySim

var _road_buttons := {}
var _zone_buttons := {}
var _type_buttons := {}
var _parallel_button: Button
var _hint := Label.new()
var _stats := Label.new()


func setup(rt: RoadTool, zt: ZoneTool, s: CitySim) -> void:
	road_tool = rt
	zone_tool = zt
	sim = s


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 16
	root.add_child(bar)
	var rows := VBoxContainer.new()
	bar.add_child(rows)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 6)
	rows.add_child(options)
	for t in RoadStyle.TYPES.size():
		var spec: Dictionary = RoadStyle.TYPES[t]
		var label := "%s  %d lanes" % [spec.name, spec.lanes]
		_type_buttons[t] = _button(options, label, Color.WHITE, func(): road_tool.set_road_type(t))
	options.add_child(VSeparator.new())
	_road_buttons[RoadTool.Mode.UPGRADE] = _button(options, "Upgrade  U", Color.WHITE,
		func(): road_tool.set_mode(RoadTool.Mode.UPGRADE))
	_parallel_button = _button(options, "Parallel  P", Color.WHITE,
		func(): road_tool.set_parallel(not road_tool.parallel))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	rows.add_child(row)
	for entry in [
		[RoadTool.Mode.STRAIGHT, "Road  1"],
		[RoadTool.Mode.CURVED, "Curve  2"],
		[RoadTool.Mode.GRID, "Grid  3"],
		[RoadTool.Mode.ROUNDABOUT, "Roundabout  4"],
		[RoadTool.Mode.BULLDOZE, "Bulldoze  B"],
	]:
		var m: int = entry[0]
		_road_buttons[m] = _button(row, entry[1], Color.WHITE, func(): road_tool.set_mode(m))
	row.add_child(VSeparator.new())
	for entry in [
		[ZoneMap.Zone.RESIDENTIAL, "Homes  5"],
		[ZoneMap.Zone.COMMERCIAL, "Shops  6"],
		[ZoneMap.Zone.INDUSTRIAL, "Industry  7"],
		[ZoneMap.Zone.NONE, "Dezone  8"],
	]:
		var z: int = entry[0]
		var tint: Color = ZoneMap.COLORS[z] if z != ZoneMap.Zone.NONE else Color(1, 0.6, 0.55)
		_zone_buttons[z] = _button(row, entry[1], tint, func(): zone_tool.set_zone(z))
	row.add_child(VSeparator.new())
	_button(row, "Clear map", Color.WHITE, func(): sim.apply({"type": "clear"}), false)

	var tips := Label.new()
	tips.text = "WASD move   Q/E rotate   T/G tilt   R/F zoom   Shift faster   Middle or Option drag: rotate   Right drag: move"
	tips.position = Vector2(16, 12)
	_style(tips)
	root.add_child(tips)

	_hint.position = Vector2(16, 40)
	_style(_hint)
	_hint.add_theme_font_size_override("font_size", 20)
	root.add_child(_hint)

	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats.position = Vector2(-16, 12)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_stats)
	root.add_child(_stats)

	road_tool.mode_changed.connect(func(_m): _sync_buttons())
	road_tool.options_changed.connect(_sync_buttons)
	zone_tool.zone_changed.connect(func(_z): _sync_buttons())
	road_tool.hint_changed.connect(func(text): _hint.text = text)
	zone_tool.hint_changed.connect(func(text): _hint.text = text)
	sim.buildings_changed.connect(_update_stats)
	sim.lots_changed.connect(_update_stats)
	_sync_buttons()
	_update_stats()


func _button(row: HBoxContainer, text: String, tint: Color, action: Callable, toggle := true) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104, 40)
	if tint != Color.WHITE:
		b.add_theme_color_override("font_color", tint)
		b.add_theme_color_override("font_pressed_color", tint.lightened(0.4))
	b.pressed.connect(action)
	row.add_child(b)
	return b


func _sync_buttons() -> void:
	for m in _road_buttons:
		_road_buttons[m].set_pressed_no_signal(m == road_tool.mode)
	for t in _type_buttons:
		_type_buttons[t].set_pressed_no_signal(t == road_tool.road_type)
	_parallel_button.set_pressed_no_signal(road_tool.parallel)
	for z in _zone_buttons:
		_zone_buttons[z].set_pressed_no_signal(z == zone_tool.zone)


func _update_stats() -> void:
	var homes := sim.count_buildings(ZoneMap.Zone.RESIDENTIAL)
	_stats.text = "Roads: %.2f km\nHomes: %d   Shops: %d   Industry: %d\nEmpty zoned lots: %d" % [
		sim.network.total_length() / 1000.0, homes,
		sim.count_buildings(ZoneMap.Zone.COMMERCIAL), sim.count_buildings(ZoneMap.Zone.INDUSTRIAL),
		sim.empty_zoned_lots().size()]


static func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
