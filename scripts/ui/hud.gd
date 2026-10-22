class_name Hud
extends CanvasLayer
## Toolbar along the bottom, tips and town stats in the corners.

var road_tool: RoadTool
var zone_tool: ZoneTool
var sim: CitySim
var game: Node  # main.gd: game speed

var _road_buttons := {}
var _zone_buttons := {}
var _type_buttons := {}
var _parallel_button: Button
var _elevation := Label.new()
var _clock := Label.new()
var _speed_buttons := []
var _demand_bars := {}
var _hint := Label.new()
var _stats := Label.new()


func setup(rt: RoadTool, zt: ZoneTool, s: CitySim, g: Node) -> void:
	road_tool = rt
	zone_tool = zt
	sim = s
	game = g


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
		var label := "%s  %d lane%s" % [spec.name, spec.lanes, "" if spec.lanes == 1 else "s"]
		_type_buttons[t] = _button(options, label, Color.WHITE, func(): road_tool.set_road_type(t))
	options.add_child(VSeparator.new())
	_road_buttons[RoadTool.Mode.UPGRADE] = _button(options, "Upgrade  U", Color.WHITE,
		func(): road_tool.set_mode(RoadTool.Mode.UPGRADE))
	_parallel_button = _button(options, "Parallel  P", Color.WHITE,
		func(): road_tool.set_parallel(not road_tool.parallel))
	options.add_child(VSeparator.new())
	_button(options, "Lower", Color.WHITE, func(): road_tool.change_elevation(-1), false)
	_elevation.custom_minimum_size = Vector2(70, 0)
	_elevation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options.add_child(_elevation)
	_button(options, "Raise", Color.WHITE, func(): road_tool.change_elevation(1), false)
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

	_build_top_bar(root)
	_build_demand(root)

	var tips := Label.new()
	tips.text = "WASD move   Q/E rotate   T/G tilt   R/F zoom   Shift faster   Middle or Option drag: rotate   Right drag: move"
	_style(tips)
	tips.add_theme_font_size_override("font_size", 13)
	root.add_child(tips)
	_pin(tips, Control.PRESET_BOTTOM_LEFT, Vector2(16, -160))

	_hint.position = Vector2(16, 12)
	_style(_hint)
	_hint.add_theme_font_size_override("font_size", 20)
	root.add_child(_hint)

	var build := Label.new()
	build.text = "Build " + _build_name()
	_style(build)
	build.add_theme_font_size_override("font_size", 12)
	root.add_child(build)
	_pin(build, Control.PRESET_BOTTOM_RIGHT, Vector2(-12, -6))

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
	sim.stats_changed.connect(_update_stats)
	game.speed_changed.connect(func(_s): _sync_speed())
	_sync_speed()
	sim.lots_changed.connect(_update_stats)
	_sync_buttons()
	_update_stats()


## Date, time, game speed and population, centred along the top.
func _build_top_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 8
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	_clock.custom_minimum_size = Vector2(230, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_clock)
	for i in 4:
		var b := _button(row, ["Pause", "1x", "2x", "4x"][i], Color.WHITE, func(): game.set_speed(i))
		b.custom_minimum_size = Vector2(54, 32)
		_speed_buttons.append(b)


## Cities: Skylines style demand bars for homes, shops and industry.
func _build_demand(root: Control) -> void:
	var panel := PanelContainer.new()
	root.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := Label.new()
	title.text = "Demand"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "H"], [ZoneMap.Zone.COMMERCIAL, "S"], [ZoneMap.Zone.INDUSTRIAL, "I"]]:
		var z: int = entry[0]
		var c := VBoxContainer.new()
		var bar := ProgressBar.new()
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(22, 90)
		bar.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = ZoneMap.COLORS[z]
		bar.add_theme_stylebox_override("fill", fill)
		c.add_child(bar)
		var l := Label.new()
		l.text = entry[1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", ZoneMap.COLORS[z])
		c.add_child(l)
		row.add_child(c)
		_demand_bars[z] = bar
	_pin(panel, Control.PRESET_BOTTOM_LEFT, Vector2(16, -16))


## Pins a control to a corner of the screen, `offset` pixels in from it,
## growing away from the corner as its content changes.
static func _pin(c: Control, corner: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0 else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0 else Control.GROW_DIRECTION_END
	c.position += offset


func _sync_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == game.speed)


func _process(_delta: float) -> void:
	var t := sim.clock()
	var hour: int = t.hour % 12
	_clock.text = "%s %s %d, %d   %d:%02d %s" % [
		["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][t.weekday],
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][t.month - 1],
		t.day, t.year, 12 if hour == 0 else hour, t.minute, "AM" if t.hour < 12 else "PM"]


func _button(row: HBoxContainer, text: String, tint: Color, action: Callable, toggle := true) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 40)
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
	_elevation.text = "Ground" if road_tool.elevation == 0.0 else "%+.1f m" % road_tool.elevation
	for z in _zone_buttons:
		_zone_buttons[z].set_pressed_no_signal(z == zone_tool.zone)


func _update_stats() -> void:
	var s := sim.stats
	var unemployed: float = 0.0 if s.workers == 0 else 100.0 * (s.workers - s.employed) / s.workers
	_stats.text = "Population: %d\nJobs: %d   Unemployment: %d%%\nHomes: %d   Shops: %d   Industry: %d\nRoads: %.2f km   Cars: %d   Traffic flow: %d%%" % [
		s.population, s.jobs, roundi(unemployed),
		sim.count_buildings(ZoneMap.Zone.RESIDENTIAL), sim.count_buildings(ZoneMap.Zone.COMMERCIAL),
		sim.count_buildings(ZoneMap.Zone.INDUSTRIAL), sim.network.total_length() / 1000.0,
		sim.traffic.cars.size(), roundi(sim.traffic.flow * 100.0)]
	for z in _demand_bars:
		_demand_bars[z].value = sim.demand[z]


## The build stamp written by the web preview workflow, or "dev" locally.
static func _build_name() -> String:
	if ResourceLoader.exists("res://scripts/build_info.gd"):
		return load("res://scripts/build_info.gd").BUILD
	return "dev"


static func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
