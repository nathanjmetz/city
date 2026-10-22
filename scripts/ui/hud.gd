class_name Hud
extends CanvasLayer
## The game's interface, laid out like Cities: Skylines 2:
## - top left: city stats and demand bars
## - top right: date, time and game speed
## - bottom centre: tool categories, which open a drawer of tool cards
## - top centre: a hint for the tool in hand

var road_tool: RoadTool
var zone_tool: ZoneTool
var sim: CitySim
var game: Node  # main.gd: game speed

var _root := Control.new()
var _category := ""
var _category_buttons := {}
var _drawers := {}
var _tool_cards := {}    # RoadTool.Mode -> Button
var _type_cards := {}    # RoadStyle.Type -> Button
var _zone_cards := {}    # ZoneMap.Zone -> Button
var _parallel_card: Button
var _elevation := UiStyle.label("Ground", 15)
var _speed_buttons := []
var _clock := UiStyle.label("", 17)
var _hint := UiStyle.label("", 16)
var _hint_panel := PanelContainer.new()
var _pop := UiStyle.label("0", 20)
var _jobs := UiStyle.label("", 14, UiStyle.MUTED)
var _cars := UiStyle.label("", 14, UiStyle.MUTED)
var _demand_bars := {}
var _help := PanelContainer.new()


func setup(rt: RoadTool, zt: ZoneTool, s: CitySim, g: Node) -> void:
	road_tool = rt
	zone_tool = zt
	sim = s
	game = g


func _ready() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiStyle.theme()
	add_child(_root)

	_build_city_panel()
	_build_clock_panel()
	_build_hint()
	_build_toolbar()
	_build_help()

	road_tool.mode_changed.connect(func(_m): _sync())
	road_tool.options_changed.connect(_sync)
	zone_tool.zone_changed.connect(func(_z): _sync())
	road_tool.hint_changed.connect(_show_hint)
	zone_tool.hint_changed.connect(_show_hint)
	sim.buildings_changed.connect(_update_stats)
	sim.stats_changed.connect(_update_stats)
	game.speed_changed.connect(func(_s): _sync_speed())
	_sync()
	_sync_speed()
	_update_stats()
	road_tool.set_mode(road_tool.mode)  # shows the first hint


func _process(_delta: float) -> void:
	var t := sim.clock()
	var hour: int = t.hour % 12
	_clock.text = "%s, %s %d  ·  %d:%02d %s" % [
		["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][t.weekday],
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][t.month - 1],
		t.day, 12 if hour == 0 else hour, t.minute, "AM" if t.hour < 12 else "PM"]
	_cars.text = "%d cars  ·  traffic flow %d%%" % [sim.traffic.cars.size(), roundi(sim.traffic.flow * 100.0)]


# --- Top left: the city -----------------------------------------------------

func _build_city_panel() -> void:
	var panel := PanelContainer.new()
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	row.add_child(Icon.new("people", 34))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	col.add_child(_pop)
	col.add_child(_jobs)
	col.add_child(_cars)
	row.add_child(VSeparator.new())
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 6)
	row.add_child(bars)
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "H"], [ZoneMap.Zone.COMMERCIAL, "S"], [ZoneMap.Zone.INDUSTRIAL, "I"]]:
		var z: int = entry[0]
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 2)
		var bar := ProgressBar.new()
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(12, 46)
		bar.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = ZoneMap.COLORS[z]
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.tooltip_text = "Demand for " + ["", "homes", "shops", "industry"][z]
		c.add_child(bar)
		var l := UiStyle.label(entry[1], 11, ZoneMap.COLORS[z])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(l)
		bars.add_child(c)
		_demand_bars[z] = bar
	_pin(panel, Control.PRESET_TOP_LEFT, Vector2(14, 14))


# --- Top right: time --------------------------------------------------------

func _build_clock_panel() -> void:
	var panel := PanelContainer.new()
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_clock)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	row.add_child(gap)
	for i in 4:
		var b := _icon_button(["pause", "play", "fast", "faster"][i], 30,
			["Pause (Space)", "Normal speed", "2x speed", "4x speed"][i])
		b.pressed.connect(func(): game.set_speed(i))
		row.add_child(b)
		_speed_buttons.append(b)
	_pin(panel, Control.PRESET_TOP_RIGHT, Vector2(-14, 14))


func _sync_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == game.speed)


# --- Top centre: hint ------------------------------------------------------

func _build_hint() -> void:
	_hint_panel.add_theme_stylebox_override("panel", UiStyle.panel(20))
	_hint_panel.add_child(_hint)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint_panel)
	_pin(_hint_panel, Control.PRESET_CENTER_TOP, Vector2(0, 86))
	_hint_panel.visible = false


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint_panel.visible = text != ""
	_hint_panel.reset_size()
	_pin(_hint_panel, Control.PRESET_CENTER_TOP, Vector2(0, 86))


# --- Bottom: tool categories and drawers -----------------------------------

func _build_toolbar() -> void:
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.add_theme_constant_override("separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(stack)

	_drawers["roads"] = _roads_drawer()
	_drawers["zones"] = _zones_drawer()
	for key in _drawers:
		_drawers[key].size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stack.add_child(_drawers[key])

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.panel(18))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	for entry in [["roads", "Roads"], ["zones", "Zoning"], ["bulldoze", "Bulldoze"]]:
		var b := _card(entry[0], entry[1], "", 46)
		b.custom_minimum_size = Vector2(84, 76)
		b.pressed.connect(func(): _open(entry[0]))
		row.add_child(b)
		_category_buttons[entry[0]] = b
		if entry[0] == "zones":
			row.add_child(VSeparator.new())

	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.position.y -= 14


func _roads_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	drawer.add_child(row)

	var tools := _section(row, "Draw")
	for entry in [
		[RoadTool.Mode.STRAIGHT, "road", "Straight", "1"],
		[RoadTool.Mode.CURVED, "curve", "Curve", "2"],
		[RoadTool.Mode.GRID, "grid", "Grid", "3"],
		[RoadTool.Mode.ROUNDABOUT, "roundabout", "Roundabout", "4"],
		[RoadTool.Mode.UPGRADE, "upgrade", "Upgrade", "U"],
	]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], entry[3])
		b.pressed.connect(func(): road_tool.set_mode(m))
		tools.add_child(b)
		_tool_cards[m] = b

	row.add_child(VSeparator.new())
	var types := _section(row, "Road type")
	for t in RoadStyle.TYPES.size():
		var spec: Dictionary = RoadStyle.TYPES[t]
		var sub := "%d lane%s, %d mph" % [spec.lanes, "" if spec.lanes == 1 else "s", spec.mph]
		var b := _card(spec.name.to_lower(), spec.name, sub)
		b.custom_minimum_size.x = 92
		b.pressed.connect(func(): road_tool.set_road_type(t))
		types.add_child(b)
		_type_cards[t] = b

	row.add_child(VSeparator.new())
	var opts := _section(row, "Options")
	_parallel_card = _card("parallel", "Parallel", "P")
	_parallel_card.pressed.connect(func(): road_tool.set_parallel(not road_tool.parallel))
	opts.add_child(_parallel_card)
	var lower := _card("lower", "Lower", "Pg Dn", 40, false)
	lower.pressed.connect(func(): road_tool.change_elevation(-1))
	opts.add_child(lower)
	_elevation.custom_minimum_size = Vector2(64, 0)
	_elevation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elevation.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opts.add_child(_elevation)
	var raise := _card("raise", "Raise", "Pg Up", 40, false)
	raise.pressed.connect(func(): road_tool.change_elevation(1))
	opts.add_child(raise)
	return drawer


func _zones_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	drawer.add_child(row)
	var zones := _section(row, "Paint zones along roads  ·  brush size [ ]")
	for entry in [
		[ZoneMap.Zone.RESIDENTIAL, "homes", "Homes", "5"],
		[ZoneMap.Zone.COMMERCIAL, "shops", "Shops", "6"],
		[ZoneMap.Zone.INDUSTRIAL, "industry", "Industry", "7"],
		[ZoneMap.Zone.NONE, "dezone", "Dezone", "8"],
	]:
		var z: int = entry[0]
		var b := _card(entry[1], entry[2], entry[3])
		if z != ZoneMap.Zone.NONE:
			(b.get_meta("icon") as Icon).accent = ZoneMap.COLORS[z]
		b.pressed.connect(func(): zone_tool.set_zone(z))
		zones.add_child(b)
		_zone_cards[z] = b
	return drawer


## A titled group of cards inside a drawer; returns the row to fill.
func _section(parent: Container, title: String) -> HBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	col.add_child(UiStyle.label(title.to_upper(), 11, UiStyle.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	return row


## A tool card: icon over a name, with a small line (key or detail) below.
func _card(icon: String, title: String, sub: String, icon_px := 40, toggle := true) -> Button:
	var b := Button.new()
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(78, 84)
	b.tooltip_text = title + ("  (%s)" % sub if sub.length() <= 5 and sub != "" else "")
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var ic := Icon.new(icon, icon_px)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var t := UiStyle.label(title, 13)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if sub != "":
		var s := UiStyle.label(sub, 10, UiStyle.MUTED)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	b.set_meta("icon", ic)
	return b


func _icon_button(icon: String, px: int, tip: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px + 10, px + 6)
	b.tooltip_text = tip
	var ic := Icon.new(icon, px * 0.7)
	ic.custom_minimum_size = Vector2.ZERO
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 7
	ic.offset_top = 7
	ic.offset_right = -7
	ic.offset_bottom = -7
	b.add_child(ic)
	return b


## Opens a tool category (or closes it if it's already open).
func _open(cat: String) -> void:
	if cat == _category and cat != "bulldoze":
		road_tool.set_mode(RoadTool.Mode.NONE)
		zone_tool.set_zone(ZoneTool.OFF)
		_category = ""
		_sync()
		return
	match cat:
		"roads":
			if road_tool.mode in [RoadTool.Mode.NONE, RoadTool.Mode.BULLDOZE]:
				road_tool.set_mode(RoadTool.Mode.STRAIGHT)
		"zones":
			if zone_tool.zone == ZoneTool.OFF:
				zone_tool.set_zone(ZoneMap.Zone.RESIDENTIAL)
		"bulldoze":
			road_tool.set_mode(RoadTool.Mode.BULLDOZE)


## Brings every button in line with the tools (keys change them too).
func _sync() -> void:
	if zone_tool.zone != ZoneTool.OFF:
		_category = "zones"
	elif road_tool.mode == RoadTool.Mode.BULLDOZE:
		_category = "bulldoze"
	elif road_tool.mode != RoadTool.Mode.NONE:
		_category = "roads"
	else:
		_category = ""
	for key in _category_buttons:
		_category_buttons[key].set_pressed_no_signal(key == _category)
	for key in _drawers:
		_drawers[key].visible = key == _category
	for m in _tool_cards:
		_tool_cards[m].set_pressed_no_signal(m == road_tool.mode)
	for t in _type_cards:
		_type_cards[t].set_pressed_no_signal(t == road_tool.road_type)
	for z in _zone_cards:
		_zone_cards[z].set_pressed_no_signal(z == zone_tool.zone)
	_parallel_card.set_pressed_no_signal(road_tool.parallel)
	_elevation.text = "Ground" if road_tool.elevation == 0.0 else "%+.1f m" % road_tool.elevation
	if _category == "":
		_show_hint("")


func _update_stats() -> void:
	var s := sim.stats
	var unemployed: float = 0.0 if s.workers == 0 else 100.0 * (s.workers - s.employed) / s.workers
	_pop.text = "%s people" % _thousands(s.population)
	_jobs.text = "%s jobs  ·  %d%% unemployed" % [_thousands(s.jobs), roundi(unemployed)]
	for z in _demand_bars:
		_demand_bars[z].value = sim.demand[z]


# --- Bottom corners: help and build ---------------------------------------

func _build_help() -> void:
	var help_button := _icon_button("help", 36, "Controls")
	help_button.toggled.connect(func(on): _help.visible = on)
	_root.add_child(help_button)
	_pin(help_button, Control.PRESET_BOTTOM_LEFT, Vector2(14, -14))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_help.add_child(col)
	col.add_child(UiStyle.label("CAMERA", 11, UiStyle.MUTED))
	for line in ["W A S D  move  (Shift: faster)", "Q / E  rotate", "T / G  tilt", "R / F or scroll  zoom",
			"Right drag  move the map", "Middle drag or Option + drag  rotate", "Space  pause"]:
		col.add_child(UiStyle.label(line, 13))
	col.add_child(UiStyle.label("TOOLS", 11, UiStyle.MUTED))
	for line in ["1 2 3 4  road, curve, grid, roundabout", "U upgrade   P parallel   B bulldoze",
			"Page Up / Down  bridge or tunnel", "5 6 7 8  homes, shops, industry, dezone",
			"Right click or Esc  stop"]:
		col.add_child(UiStyle.label(line, 13))
	var clear := Button.new()
	clear.text = "Start over (clear the map)"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func(): sim.apply({"type": "clear"}))
	col.add_child(clear)
	_help.visible = false
	_root.add_child(_help)
	_pin(_help, Control.PRESET_BOTTOM_LEFT, Vector2(14, -62))

	var build := UiStyle.label("Build " + _build_name(), 11, Color(UiStyle.MUTED, 0.7))
	_root.add_child(build)
	_pin(build, Control.PRESET_BOTTOM_RIGHT, Vector2(-12, -6))


## The build stamp written by the web preview workflow, or "dev" locally.
static func _build_name() -> String:
	if ResourceLoader.exists("res://scripts/build_info.gd"):
		return load("res://scripts/build_info.gd").BUILD
	return "dev"


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Pins a control to a corner of the screen, `offset` pixels in from it,
## growing away from the corner as its content changes.
static func _pin(c: Control, corner: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0 else \
		(Control.GROW_DIRECTION_BOTH if offset.x == 0 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0 else Control.GROW_DIRECTION_END
	c.position += offset
