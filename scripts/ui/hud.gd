class_name Hud
extends CanvasLayer
## The game's interface: two slim bars docked to the screen edges.
## - top bar: city stats, demand, money; date, game speed and help on the right
## - bottom bar: tool categories; the open category's tools sit just above it
## - a small hint for the tool in hand under the top bar
## Esc cancels what's being drawn, then puts every tool away.
## All colours and shapes come from UiStyle, so the look can be re-themed.

## Escape was pressed with nothing left to close.
signal nothing_to_close

const GOOD := Color(0.5, 0.85, 0.5)
## The bottom bar's tool categories: [key, title].
const CATEGORIES := [["roads", "Roads"], ["zones", "Zoning"], ["industry", "Industry"], ["services", "Services"],
	["parks", "Parks"], ["bulldoze", "Bulldoze"], ["move", "Move It"], ["budget", "Economy"]]
const BAD := Color(0.95, 0.45, 0.4)

var road_tool: RoadTool
var zone_tool: ZoneTool
var service_tool: ServiceTool
var farm_tool: FarmTool
var industry_tool: IndustryTool
var park_tool: ParkTool
var _park_cards := {}  # Parks kind -> Button
var _industry_cards := {}  # "oil"/"ore"/"forest"/"reserve"/"release" -> Button
var _industry_kind := "oil"  # what the industry Reserve tool saves land for
var warehouse_tool: WarehouseTool
var campus_tool: CampusTool
var bank_tool: BankTool
var neighborhood_tool: NeighborhoodTool
var _bank_cards := {}  # "community"/"farm_credit" -> Button
var _campus_cards := {}  # "high_school"/"college"/"university" -> Button
var telecom_tool: TelecomTool
var _telecom_card: Button
var _warehouse_cards := {}  # Warehouses size -> Button
var traffic_tool: TrafficTool
var move_tool: MoveTool
var info_view: InfoView
var service_view: ServiceView
var bus_view: BusView
var rail_view: RailView
var select_tool: SelectTool
var lot_alerts: LotAlerts
var _info_panel := InfoPanel.new()
var _traffic_cards := {}  # TrafficTool.Mode -> Button
var sim: CitySim
var game: Node  # main.gd: game speed

var _root := Control.new()
var _category := ""
var _category_buttons := {}
var _drawers := {}
var _drawer_dock := PanelContainer.new()
var _bottom := VBoxContainer.new()
var _tool_cards := {}    # RoadTool.Mode -> Button
var _type_cards := {}    # road menu (RoadStyle.GROUPS) -> Button
var _variant_cards := {} # RoadStyle.Type -> Button, in the row above
var _variant_row := HBoxContainer.new()
var _variant_title := UiStyle.label("", 10, UiStyle.MUTED)
var _variant_group := -1  # the menu whose variants the row shows
var _variant_of := {}     # road menu -> the variant last picked in it
var _kinds_open := false  # the road kinds row is up instead of grid sizes
var _traffic_row := HBoxContainer.new()
var _traffic_card: Button
var _neighborhood_card: Button
var _zone_cards := {}    # ZoneMap.Zone -> Button
var _power_card: Button
var _service_cards := {} # Services.Kind -> Button
var _farm_cards := {}    # FarmTool.Mode -> Button
var _warning := UiStyle.label("", 13, Color(1.0, 0.75, 0.3))
var _parallel_card: Button
## Grid only: any shape instead of a rectangle.
var _shape_card: Button
## Grid only: a row of real-world grid sizes above the road tools.
var _grid_sizes: Control
var _grid_size_cards := []
var _elevation := UiStyle.label("Ground", 12)
var _speed_buttons := []
var _clock := UiStyle.label("", 14)
var _hint := UiStyle.label("", 14)
var _hint_panel := PanelContainer.new()
var _pop := UiStyle.label("0", 14)
var _jobs := UiStyle.label("", 13, UiStyle.MUTED)
var _cars := UiStyle.label("", 13, UiStyle.MUTED)
var _demand_bars := {}
var _money := UiStyle.label("", 14)
var _net := UiStyle.label("", 13)
## The Economy page (the bottom bar's Economy button) is open.
var _budget_open := false
var economy_page := EconomyPage.new()
var _help := PanelContainer.new()
var _top_bar: PanelContainer
var _views_panel := PanelContainer.new()
var _views_button: Button
var _view_cards := {}  # view key -> Button
var _view := ""
var _help_button: Button
var advisor := AdvisorPanel.new()
var permits := PermitPanel.new()
## The region's shared projects and services (only in a region).
var region_panel := RegionPanel.new()


func setup(rt: RoadTool, zt: ZoneTool, s: CitySim, g: Node) -> void:
	road_tool = rt
	zone_tool = zt
	sim = s
	game = g


func _ready() -> void:
	add_to_group("pad_hud")
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiStyle.theme()
	add_child(_root)

	_build_top_bar()
	_build_hint()
	_build_bottom_bar()
	_build_help()
	_build_views()
	_build_advisor()
	_build_permits()
	_build_region_panel()
	_info_panel.setup(sim, select_tool)
	_root.add_child(_info_panel)
	_build_economy()

	road_tool.mode_changed.connect(func(_m): _sync())
	road_tool.options_changed.connect(_sync)
	zone_tool.zone_changed.connect(func(_z): _sync())
	road_tool.hint_changed.connect(_show_hint)
	zone_tool.hint_changed.connect(_show_hint)
	service_tool.kind_changed.connect(func(_k): _sync())
	service_tool.hint_changed.connect(_show_hint)
	farm_tool.mode_changed.connect(func(_m): _sync())
	farm_tool.hint_changed.connect(_show_hint)
	industry_tool.kind_changed.connect(func(_k): _sync())
	industry_tool.hint_changed.connect(_show_hint)
	warehouse_tool.kind_changed.connect(func(_k): _sync())
	warehouse_tool.hint_changed.connect(_show_hint)
	campus_tool.kind_changed.connect(func(_k): _sync())
	campus_tool.hint_changed.connect(_show_hint)
	telecom_tool.kind_changed.connect(func(_k): _sync())
	telecom_tool.hint_changed.connect(_show_hint)
	sim.telecom_changed.connect(_sync)
	bank_tool.kind_changed.connect(func(_k): _sync())
	bank_tool.hint_changed.connect(_show_hint)
	neighborhood_tool.kind_changed.connect(func(_k): _sync())
	neighborhood_tool.hint_changed.connect(_show_hint)
	traffic_tool.mode_changed.connect(func(_m): _sync())
	traffic_tool.hint_changed.connect(_show_hint)
	park_tool.kind_changed.connect(func(_k): _sync())
	park_tool.hint_changed.connect(_show_hint)
	sim.parks_changed.connect(_sync)
	move_tool.active_changed.connect(func(_on): _sync())
	move_tool.hint_changed.connect(_show_hint)
	sim.buildings_changed.connect(_update_stats)
	sim.stats_changed.connect(_update_stats)
	game.speed_changed.connect(func(_s): _sync_speed())
	_sync()
	_sync_speed()
	_update_stats()
	road_tool.set_mode(road_tool.mode)  # shows the first hint


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_ESCAPE:
		return
	if road_tool.is_drawing():
		road_tool.cancel()
	elif farm_tool.is_drawing():
		farm_tool.cancel()
	elif move_tool.active and not move_tool.selection.is_empty():
		move_tool.clear_selection()
	elif anything_open():
		close_all()
	else:
		nothing_to_close.emit()  # the pause menu opens
	get_viewport().set_input_as_handled()


## Game controllers (Pad): the tool wheel holds the bottom bar's categories
## and the Views.
func pad_wheel_items() -> Array:
	return CATEGORIES + [["views", "Views"]]


func pad_wheel_pick(key: String) -> void:
	if key == "views":
		_views_button.button_pressed = not _views_button.button_pressed
	elif key != _category or key == "bulldoze":
		_open(key)


## How tall the bottom dock is, so the pad's prompts sit just above it.
func pad_bottom_height() -> float:
	return _bottom.size.y


## True while a tool is in hand, a panel or view is open, or something is selected.
func anything_open() -> bool:
	return _budget_open or _view != "" or _views_panel.visible or _help.visible or advisor.visible or permits.visible or region_panel.visible \
		or not select_tool.selection.is_empty() or road_tool.mode != RoadTool.Mode.NONE \
		or zone_tool.zone != ZoneTool.OFF or service_tool.kind != ServiceTool.OFF \
		or farm_tool.mode != FarmTool.Mode.NONE or traffic_tool.mode != TrafficTool.Mode.NONE \
		or industry_tool.kind != "" or warehouse_tool.kind != "" or park_tool.kind != "" or campus_tool.kind != "" or bank_tool.kind != "" or telecom_tool.kind != "" or move_tool.active \
		or neighborhood_tool.kind != ""


## Puts every tool away and closes every panel.
func close_all() -> void:
	_budget_open = false
	_show_view("")
	_views_panel.visible = false
	_views_button.set_pressed_no_signal(false)
	select_tool.select({})
	_help.visible = false
	_help_button.set_pressed_no_signal(false)
	advisor.close_panel()
	permits.close_panel()
	region_panel.close_panel()
	road_tool.set_mode(RoadTool.Mode.NONE)
	zone_tool.set_zone(ZoneTool.OFF)
	service_tool.set_kind(ServiceTool.OFF)
	farm_tool.set_mode(FarmTool.Mode.NONE)
	industry_tool.set_kind("")
	warehouse_tool.set_kind("")
	campus_tool.set_kind("")
	telecom_tool.set_kind("")
	bank_tool.set_kind("")
	traffic_tool.set_mode(TrafficTool.Mode.NONE)
	park_tool.set_kind("")
	move_tool.set_active(false)
	neighborhood_tool.set_kind("")
	_sync()


func _process(_delta: float) -> void:
	_views_panel.position = Vector2(0, _top_bar.size.y)
	# The Economy page fills the left edge between the bars.
	economy_page.position = Vector2(0, _top_bar.size.y)
	economy_page.size = Vector2(EconomyPage.WIDTH, _root.size.y - _top_bar.size.y - _bottom.size.y)
	# The info panel sits beside the Views column or Economy page when open.
	var left := _views_panel.size.x if _views_panel.visible else 0.0
	if economy_page.visible:
		left = economy_page.size.x
	_info_panel.position = Vector2(left, _top_bar.size.y)
	var t := sim.clock()
	var hour: int = t.hour % 12
	# A game day is a month (see Seasons), so the date is month and year.
	# Calendar years, matching the "since" on business signs.
	_clock.text = "%s %d  %d:%02d %s" % [
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][t.month - 1],
		Families.calendar(t.year), 12 if hour == 0 else hour, t.minute, "AM" if t.hour < 12 else "PM"]
	_money.text = "$" + _thousands(sim.economy.money)
	_money.add_theme_color_override("font_color", UiStyle.TEXT if sim.economy.money >= 0 else BAD)
	_cars.text = "%d  ·  %d%% flow" % [sim.traffic.cars.size(), roundi(sim.traffic.flow * 100.0)]


# --- Views (Cities: Skylines 2's info views) ---------------------------------

const VIEWS := [
	["fertility", "fertility", "Fertility", "Where the soil is richest for farms"],
	["oil", "oil", "Oil", "Oil underground. It never runs out."],
	["ore", "ore", "Ore", "Ore deposits. They never run out."],
	["forest", "forest", "Forest", "Woodland for forestry. It grows back."],
	["fire", "fire", "Fire", "Roads a fire station reaches"],
	["police", "police", "Police", "Roads police patrol"],
	["health", "health", "Health", "Roads a clinic reaches"],
	["school", "school", "Schools", "Roads within reach of a school"],
	["traffic", "flow", "Traffic", "How freely traffic moves"],
	["bus", "bus", "Buses", "Bus routes and stops the depots planned, and how full the buses are"],
	["network", "tower", "Cell and fiber", "Cell signal across the map, and the streets with fiber"],
	["rail", "train", "Rail", "Rail lines, what they carry, and new track waiting on your permit"],
	["smoke", "smoke", "Smoke", "Where smoke drifts and who makes it. Click anywhere to see who pollutes it."],
	["noise", "noise", "Noise", "How loud it is and what's making the noise. Click anywhere to see the sources."],
	["ground", "ground", "Dirty ground", "Dirty ground and groundwater, and where it comes from. Click anywhere to trace it."],
]


func views_open() -> bool:
	return _views_panel.visible


## A slim column docked under the top bar, flush to the left edge.
func _build_views() -> void:
	_views_panel.add_theme_stylebox_override("panel", UiStyle.dock(false))
	_views_panel.visible = false
	_root.add_child(_views_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_views_panel.add_child(col)
	col.add_child(UiStyle.label("VIEWS", 11, UiStyle.MUTED))
	for v in VIEWS:
		var key: String = v[0]
		var b := Button.new()
		b.toggle_mode = true
		b.text = "  " + v[2]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = v[3]
		b.custom_minimum_size = Vector2(132, 28)
		var ic := Icon.new(v[1], 20)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = Vector2(6, 4)
		ic.size = Vector2(20, 20)
		b.add_child(ic)
		b.text = "       " + v[2]
		b.pressed.connect(func(): _show_view("" if _view == key else key))
		col.add_child(b)
		_view_cards[key] = b


## Turns one view on (or all off with "").
func _show_view(key: String) -> void:
	_view = key
	var resource := {"fertility": InfoView.Mode.FERTILITY, "oil": InfoView.Mode.OIL,
		"ore": InfoView.Mode.ORE, "forest": InfoView.Mode.FOREST, "network": InfoView.Mode.NETWORK,
		"smoke": InfoView.Mode.SMOKE, "noise": InfoView.Mode.NOISE, "ground": InfoView.Mode.GROUND}
	info_view.set_mode(resource.get(key, InfoView.Mode.NONE))
	# In a pollution view any click on the map says who pollutes that spot.
	select_tool.spot_clicks = key in ["smoke", "noise", "ground"]
	var sel_type: String = select_tool.selection.get("type", "")
	if select_tool.spot_clicks and sel_type in ["", "spot", "pollution"]:
		# The town's worst sources for this view, until a click picks a spot.
		select_tool.select({"type": "pollution", "id": key})
	elif not select_tool.spot_clicks and sel_type in ["spot", "pollution"]:
		select_tool.select({})
	var cover := {"fire": Services.Kind.FIRE, "police": Services.Kind.POLICE,
		"health": Services.Kind.CLINIC, "school": Services.Kind.SCHOOL}
	if cover.has(key):
		service_view.show_kind = cover[key]
	elif service_tool.kind == ServiceTool.OFF:
		service_view.show_kind = -1
	if bus_view:
		bus_view.show_routes = key == "bus"
	if rail_view:
		rail_view.show_lines = key == "rail"
	if key == "traffic":
		traffic_tool.set_mode(TrafficTool.Mode.VIEW)
	elif traffic_tool.mode == TrafficTool.Mode.VIEW:
		traffic_tool.set_mode(TrafficTool.Mode.NONE)
	for k in _view_cards:
		_view_cards[k].set_pressed_no_signal(k == _view)


# --- Top bar ----------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.dock(true))
	_root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	_top_bar = bar
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	_views_button = _icon_button("views", 24, "Views: see the map by fertility, oil, ore, forest, services, traffic and pollution")
	_views_button.toggled.connect(func(on): _views_panel.visible = on)
	row.add_child(_views_button)
	row.add_child(VSeparator.new())
	_stat(row, "people", _pop, "Population")
	_stat(row, "jobs", _jobs, "Jobs and unemployment")
	_stat(row, "car", _cars, "Cars on the road and how freely traffic flows")
	row.add_child(VSeparator.new())
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "H"], [ZoneMap.Zone.COMMERCIAL, "S"], [ZoneMap.Zone.INDUSTRIAL, "I"]]:
		var z: int = entry[0]
		var l := UiStyle.label(entry[1], 11, ZoneMap.COLORS[z])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var bar_z := ProgressBar.new()
		bar_z.show_percentage = false
		bar_z.custom_minimum_size = Vector2(34, 7)
		bar_z.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_z.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = ZoneMap.COLORS[z]
		fill.set_corner_radius_all(3)
		bar_z.add_theme_stylebox_override("fill", fill)
		bar_z.tooltip_text = "Demand for " + ["", "homes", "shops", "industry"][z]
		row.add_child(bar_z)
		_demand_bars[z] = bar_z
	row.add_child(VSeparator.new())
	_stat(row, "money", _money, "City funds")
	_net.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_net)
	_warning.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_warning.mouse_filter = Control.MOUSE_FILTER_PASS
	# Never push the clock and speed buttons off the bar.
	_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning.clip_text = true
	_warning.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_warning.tooltip_text = "Buildings need power and water to grow and fill. Click a lot or building to see what it lacks."
	row.add_child(_warning)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock)
	for i in 4:
		var b := _icon_button(["pause", "play", "fast", "faster"][i], 24,
			["Pause (Space)", "Normal speed", "2x speed", "4x speed"][i])
		b.pressed.connect(func(): game.set_speed(i))
		row.add_child(b)
		_speed_buttons.append(b)
	row.add_child(VSeparator.new())
	# How the town looks (Cities: Skylines 2 keeps these in its settings):
	# the day/night cycle (off: always late morning) and seasons (off:
	# always summer). Each player picks for themselves.
	DayNight.load_settings()
	var cycle := _icon_button("daynight", 24, "Day and night: let the sun set and the streetlights come on")
	cycle.set_pressed_no_signal(DayNight.cycle_on)
	cycle.toggled.connect(DayNight.set_cycle)
	row.add_child(cycle)
	var seasons := _icon_button("seasons", 24, "Seasons: spring, summer, fall colour and winter snow (no weather)")
	seasons.set_pressed_no_signal(DayNight.seasons_on)
	seasons.toggled.connect(DayNight.set_seasons)
	row.add_child(seasons)
	row.add_child(VSeparator.new())
	# (The Session autoload by path: tools and tests load the HUD before it exists.)
	var session := get_node_or_null("/root/Session")
	if session and session.online():
		var c: RegionClient = session.client
		region_panel.setup(sim, c.region, c.my_city, c.pledge)
		row.add_child(region_panel.make_button())
	permits.setup(sim, game, info_view.cam)
	row.add_child(permits.make_button())
	advisor.setup(sim, func(): return _advisor_key() if _category != "" or _view == "" else "view_" + _view)
	row.add_child(advisor.make_button())
	_help_button = _icon_button("help", 24, "Controls")
	_help_button.toggled.connect(func(on):
		_help.visible = on
		if on:
			advisor.close_panel()
			permits.close_panel()
			region_panel.close_panel())
	row.add_child(_help_button)


## An icon and a value, side by side.
func _stat(row: HBoxContainer, icon: String, value: Label, tip: String) -> void:
	var ic := Icon.new(icon, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tooltip_text = tip
	row.add_child(ic)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.tooltip_text = tip
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(value)


func _sync_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == game.speed)


# --- Hint under the top bar ------------------------------------------------

func _build_hint() -> void:
	_hint_panel.add_theme_stylebox_override("panel", UiStyle.panel(12))
	_hint_panel.add_child(_hint)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint_panel)
	_hint_panel.visible = false


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint_panel.visible = text != ""
	_hint_panel.reset_size()
	_pin(_hint_panel, Control.PRESET_CENTER_TOP, Vector2(0, 44))


# --- Bottom bar: categories, with the open one's tools above ---------------

func _build_bottom_bar() -> void:
	var dock := _bottom
	dock.add_theme_constant_override("separation", 0)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dock)

	_drawer_dock.add_theme_stylebox_override("panel", UiStyle.dock(false, true))
	dock.add_child(_drawer_dock)
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_drawer_dock.add_child(holder)
	_drawers["roads"] = _roads_drawer()
	_drawers["zones"] = _zones_drawer()
	_drawers["services"] = _services_drawer()
	_drawers["parks"] = _parks_drawer()
	_drawers["industry"] = _industry_drawer()
	for key in _drawers:
		_drawers[key].add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		holder.add_child(_drawers[key])

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.dock(false))
	dock.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	# Traffic lives under Roads and Farming under Industry, as in CS2.
	for entry in CATEGORIES:
		var b := _category_button(entry[0], entry[1])
		b.pressed.connect(func(): _open(entry[0]))
		row.add_child(b)
		_category_buttons[entry[0]] = b

	dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fit_bottom()


## Keeps the bottom dock flush with the screen edge as its height changes.
func _fit_bottom() -> void:
	_bottom.offset_left = 0
	_bottom.offset_right = 0
	_bottom.offset_bottom = 0
	_bottom.offset_top = 0


func _category_button(icon: String, title: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104, 36)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(row)
	var ic := Icon.new(icon, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var t := UiStyle.label(title, 14)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	return b


## Roads: draw tools, the five road menus, options and Traffic along the
## bottom; above them, a row with the open menu's road variants (CS2 shows
## each road category's assets the same way), or the traffic controls.
func _roads_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	drawer.add_child(stack)
	var sizes_row := HBoxContainer.new()
	sizes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(sizes_row)
	var sizes := _section(sizes_row, "Grid size  ·  largest to smallest  ·  [ ] fine-tune")
	for i in GridFill.PRESETS.size():
		var p: Dictionary = GridFill.PRESETS[i]
		var b := _card("grid", p.name, "%s, %d × %d ft" % [p.about, roundi(p.block * RoadTool.FT), roundi(p.across * RoadTool.FT)])
		b.pressed.connect(func(): road_tool.set_grid_preset(i))
		sizes.add_child(b)
		_grid_size_cards.append(b)
	_grid_sizes = sizes_row

	var upper := VBoxContainer.new()
	upper.add_theme_constant_override("separation", 2)
	stack.add_child(upper)
	_variant_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upper.add_child(_variant_title)
	_variant_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_variant_row.add_theme_constant_override("separation", 3)
	upper.add_child(_variant_row)
	_traffic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_traffic_row.add_theme_constant_override("separation", 10)
	stack.add_child(_traffic_row)
	_fill_traffic_row(_traffic_row)
	stack.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	stack.add_child(row)

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
		b.pressed.connect(func():
			_kinds_open = false
			road_tool.set_mode(m))
		tools.add_child(b)
		_tool_cards[m] = b

	row.add_child(VSeparator.new())
	var types := _section(row, "Road type  ·  click for its kinds")
	for g in RoadStyle.GROUPS:
		var spec: Dictionary = RoadStyle.TYPES[g]
		var b := _card(spec.name.to_lower(), spec.name, "%d kinds" % RoadStyle.variants(g).size())
		b.pressed.connect(func():
			# One row above the tools at a time: the kinds open over the grid sizes.
			_kinds_open = not (_kinds_open and RoadStyle.group(road_tool.road_type) == g)
			_pick_road(_variant_of.get(g, g)))
		types.add_child(b)
		_type_cards[g] = b

	row.add_child(VSeparator.new())
	var opts := _section(row, "Options")
	_parallel_card = _card("parallel", "Parallel", "P")
	_parallel_card.pressed.connect(func(): road_tool.set_parallel(not road_tool.parallel))
	opts.add_child(_parallel_card)
	_shape_card = _card("grid", "Any shape", "Tab: rectangle or any shape")
	_shape_card.pressed.connect(func(): road_tool.set_grid_free(not road_tool.grid_free))
	opts.add_child(_shape_card)
	var lower := _card("lower", "Lower", "Page Down", false)
	lower.pressed.connect(func(): road_tool.change_elevation(-1))
	opts.add_child(lower)
	_elevation.custom_minimum_size = Vector2(48, 0)
	_elevation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elevation.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opts.add_child(_elevation)
	var raise := _card("raise", "Raise", "Page Up", false)
	raise.pressed.connect(func(): road_tool.change_elevation(1))
	opts.add_child(raise)

	row.add_child(VSeparator.new())
	var traffic := _section(row, "Traffic")
	_traffic_card = _card("traffic", "Traffic", "J")
	_traffic_card.tooltip_text = "Traffic flow, lights and stop signs  (J)"
	_traffic_card.pressed.connect(func():
		if traffic_tool.mode == TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.VIEW)
		else:
			road_tool.set_mode(road_tool.last_draw))
	traffic.add_child(_traffic_card)

	# A town hemmed in by its neighbors starts a new neighborhood on open land.
	row.add_child(VSeparator.new())
	var town := _section(row, "Town")
	_neighborhood_card = _card("homes", "Neighborhood", "")
	_neighborhood_card.tooltip_text = "New neighborhood: start part of your town out on open land, linked by a free county road. You earn one per town stage."
	_neighborhood_card.pressed.connect(func():
		neighborhood_tool.set_kind("" if neighborhood_tool.kind != "" else "found"))
	town.add_child(_neighborhood_card)
	return drawer


## Picks a road type, and remembers it as its menu's choice.
func _pick_road(t: int) -> void:
	_variant_of[RoadStyle.group(t)] = t
	road_tool.set_road_type(t)


## Fills the row above the road menus with the open menu's variants.
func _show_variants(menu: int) -> void:
	if menu == _variant_group:
		return
	_variant_group = menu
	for c in _variant_row.get_children():
		c.queue_free()
	_variant_cards.clear()
	_variant_title.text = ("%s  ·  %d kinds" % [RoadStyle.TYPES[menu].name, RoadStyle.variants(menu).size()]).to_upper()
	for t in RoadStyle.variants(menu):
		var spec: Dictionary = RoadStyle.TYPES[t]
		var b := _card("road:%d" % t, spec.get("short", "Standard" if t == menu else spec.name), "")
		b.custom_minimum_size = Vector2(72, 50)
		b.tooltip_text = _road_tip(t)
		b.pressed.connect(func():
			_kinds_open = false
			_pick_road(t))
		_variant_row.add_child(b)
		_variant_cards[t] = b


## A road's tooltip: what it is, in plain words, with its lanes, speed and price.
static func _road_tip(t: int) -> String:
	var spec: Dictionary = RoadStyle.TYPES[t]
	var bits := ["%d lane%s%s" % [spec.lanes, "" if spec.lanes == 1 else "s", ", one way" if spec.oneway else ""]]
	if spec.get("turn", false):
		bits.append("center turn lane")
	elif spec.get("trees", false):
		bits.append("tree median")
	elif spec.median > 0.0:
		bits.append("median")
	if spec.get("angle", false):
		bits.append("angled parking")
	elif spec.get("parking", 0) > 0 or t == RoadStyle.Type.STREET:
		bits.append("parking")
	if spec.get("bike", false):
		bits.append("bike lanes")
	if spec.get("bus", false):
		bits.append("curb lanes for buses only")
	if spec.get("surface", "asphalt") != "asphalt":
		bits.append(spec.surface)
	if not spec.lots:
		bits.append("no driveways")
	bits.append("%d mph" % spec.mph)
	return "%s: %s. $%s a metre." % [spec.name, ", ".join(bits), CitySim.money_text(int(Economy.BUILD_PER_M[t]))]


func _zones_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	drawer.add_child(row)
	var zones := _section(row, "Zone street sides  ·  Shift both sides  ·  Tab brush")
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


func _services_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	drawer.add_child(row)
	for group in [["Utilities", [Services.Kind.POWER_FEED, Services.Kind.WELL, Services.Kind.SUBSTATION,
				Services.Kind.WATER_TOWER, Services.Kind.WATER_UTILITY]],
			["Safety and schools", [Services.Kind.FIRE, Services.Kind.POLICE, Services.Kind.SCHOOL]],
			["Health and care", [Services.Kind.CLINIC, Services.Kind.HOSPITAL, Services.Kind.NURSING_HOME,
				Services.Kind.DAYCARE]],
			["Transit", [Services.Kind.BUS_DEPOT, Services.Kind.TAXI_COMPANY]]]:
		if row.get_child_count() > 0:
			row.add_child(VSeparator.new())
		var cards := _section(row, group[0])
		for k in group[1]:
			var s: Dictionary = Services.KINDS[k]
			var short := {Services.Kind.WATER_TOWER: "Water tower", Services.Kind.POWER_FEED: "Power line",
				Services.Kind.WELL: "Well", Services.Kind.SCHOOL: "School", Services.Kind.WATER_UTILITY: "Water utility",
				Services.Kind.TAXI_COMPANY: "Taxis"}
			var b := _card(s.icon, short.get(k, s.name.split(" ")[0]),
				"%s: $%s, $%s a month" % [s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)])
			b.tooltip_text = "%s: $%s to build, $%s a month" % [s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)]
			if k == Services.Kind.BUS_DEPOT:
				b.tooltip_text = "%s: $%s to build, with two buses. It plans its own stops, routes and fare; you set its funding." % [s.name, CitySim.money_text(s.cost)]
			elif k == Services.Kind.TAXI_COMPANY:
				b.tooltip_text = "%s: $%s to bring one to town, with two cabs. Its owner runs it on fares: the fleet, the meter and the lot." % [s.name, CitySim.money_text(s.cost)]
			b.pressed.connect(func(): service_tool.set_kind(k))
			cards.add_child(b)
			_service_cards[k] = b
		if group[0] == "Utilities":
			# Brawn's hub model: a company whose leader picks and grows the plant.
			var pc := _card("power", "Power co.", "")
			pc.tooltip_text = "Power company: $%s. Its leader picks solar, wind, gas, a dam or an old coal plant, and grows it" \
				% CitySim.money_text(Balance.POWER_YARD_COST)
			pc.pressed.connect(func(): industry_tool.set_kind("power"))
			cards.add_child(pc)
			_power_card = pc
	# Landfill, recycling and cemetery: hubs that grow on their own.
	row.add_child(VSeparator.new())
	var hubs := _section(row, "Trash and cemeteries")
	for k in CivicHubs.TOOL_KINDS:
		var hk: String = CivicHubs.TOOL_KINDS[k]
		var w: Dictionary = Balance.WASTE_SITES[hk]
		var title: String = CivicHubs.KINDS[hk].name
		var b := _card(CivicHubs.KINDS[hk].icon, {"recycling_1": "Recycling"}.get(hk, title),
			"%s: $%s, $%s a month" % [title, CitySim.money_text(int(w.cost)), CitySim.money_text(int(w.upkeep))])
		b.tooltip_text = "%s: $%s to build, $%s a month. Never fills up." % [title, CitySim.money_text(int(w.cost)),
			CitySim.money_text(int(w.upkeep))]
		b.pressed.connect(func(): service_tool.set_kind(k))
		hubs.add_child(b)
		_service_cards[k] = b
	# Campuses grow on their own once placed (Brawn's hub model).
	row.add_child(VSeparator.new())
	var campus := _section(row, "High school and college")
	for k in ["high_school", "college", "university"]:
		var e: Dictionary = Education.spec(k)
		var b := _card("school", {"high_school": "High school", "college": "College", "university": "University"}[k], "")
		b.tooltip_text = "%s: $%s to build, $%s a month. Its %s buys the free land next to it as it fills." % [
			Education.KINDS[k].name, CitySim.money_text(e.cost), CitySim.money_text(e.funding), Education.KINDS[k].head.to_lower()]
		b.pressed.connect(func(): campus_tool.set_kind(k))
		campus.add_child(b)
		_campus_cards[k] = b
	# The post office: its postmaster plans the routes.
	row.add_child(VSeparator.new())
	var mail := _section(row, "Mail")
	var pb := _card("mail", "Post office", "Post office: $%s, $%s a month" % [CitySim.money_text(Balance.MAIL_COST),
		CitySim.money_text(Balance.MAIL_UPKEEP)])
	pb.tooltip_text = "Post office: $%s to build, $%s a month. Its postmaster plans the routes." % [
		CitySim.money_text(Balance.MAIL_COST), CitySim.money_text(Balance.MAIL_UPKEEP)]
	pb.pressed.connect(func(): service_tool.set_kind(Mail.TOOL_KIND))
	mail.add_child(pb)
	_service_cards[Mail.TOOL_KIND] = pb
	# The phone company: placed once, then it builds its own network.
	row.add_child(VSeparator.new())
	var phone := _section(row, "Phone and internet")
	_telecom_card = _card("tower", "Phone co.", "")
	_telecom_card.tooltip_text = "Phone company: $%s to build, $%s a month grant. Its manager strings fiber and puts up cell towers where they pay off. One per town." % [
		CitySim.money_text(Balance.TELECOM_COST), CitySim.money_text(Balance.TELECOM_GRANT)]
	_telecom_card.pressed.connect(func(): telecom_tool.set_kind("telecom"))
	phone.add_child(_telecom_card)
	# The railroad: its leader plans the track and asks before building.
	row.add_child(VSeparator.new())
	var rail := _section(row, "Rail")
	var rb := _card("train", "Rail depot", "")
	rb.tooltip_text = "Rail depot: $%s. Its leader lays track to the region and to industry, by your permit." % \
		CitySim.money_text(Balance.RAIL_DEPOT_COST)
	rb.pressed.connect(func(): service_tool.set_kind(Rail.TOOL_KIND))
	rail.add_child(rb)
	_service_cards[Rail.TOOL_KIND] = rb
	# Banks lend to the farms, companies and builders (Brawn's hub model).
	row.add_child(VSeparator.new())
	var bank := _section(row, "Banks")
	for k in ["community", "farm_credit"]:
		var b := _card("bank", {"community": "Bank", "farm_credit": "Farm Credit"}[k], "")
		b.tooltip_text = "%s: $%s for the lot. Its %s lends to %s, and buys the land next door as it grows." % [
			Banks.KINDS[k].name, CitySim.money_text(int(Banks.spec(k).cost)), Banks.KINDS[k].head.to_lower(),
			{"community": "farms, companies and builders", "farm_credit": "farms and timber"}[k]]
		b.pressed.connect(func(): bank_tool.set_kind(k))
		bank.add_child(b)
		_bank_cards[k] = b
	return drawer


func _parks_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	drawer.add_child(row)
	var parks := _section(row, "Park  ·  fills in by itself")
	var marks := _section(row, "Landmarks  ·  one per town")
	for k in Parks.KINDS:
		var spec: Dictionary = Parks.KINDS[k]
		if spec.get("auto", false):
			continue
		var a: Dictionary = Balance.AMENITIES[k]
		var short := {"park": "Park", "courthouse": "Courthouse", "water_tower": "Water tower",
			"grain_elevator": "Elevator", "football": "Football", "fairgrounds": "Fairgrounds", "trailhead": "Trails"}
		var tip := "%s: $%s" % [spec.name, CitySim.money_text(int(a.cost))]
		if spec.landmark:
			tip += ", $%s a month" % CitySim.money_text(int(a.upkeep))
		var b := _card(spec.icon, short[k], tip)
		b.tooltip_text = tip + ". Raises land value and happiness nearby."
		b.pressed.connect(func(): park_tool.set_kind(k))
		(marks if spec.landmark else parks).add_child(b)
		_park_cards[k] = b
	return drawer


## Resource industry (Brawn's model): place a company's main building near
## the resource; its pads spread on their own. Reserve saves land for it.
func _industry_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	drawer.add_child(row)
	var farms := _section(row, "Farmhouse  ·  near green soil")
	for entry in [[FarmTool.Mode.CORN, "corn", "Corn", "Corn farm: more income on rich soil"],
			[FarmTool.Mode.SOYBEANS, "soybeans", "Soybeans", "Soybean farm: steadier on poorer soil"]]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[3]
		b.pressed.connect(func():
			_industry_kind = "farm"
			farm_tool.set_mode(m))
		farms.add_child(b)
		_farm_cards[m] = b
	var hq := _section(row, "Main building  ·  near the resource")
	var area := _section(row, "Save land")
	var stores := _section(row, "Warehouses  ·  beside a street")
	for k in Warehouses.ORDER:
		var spec: Dictionary = Balance.WAREHOUSE[k]
		var b := _card("warehouse", ["Small", "Medium", "Large", "Distrib."][Warehouses.ORDER.find(k)], "")
		b.tooltip_text = "%s, %s ($%s): stores raw loads and goods until a factory or shop needs them" \
			% [Warehouses.KINDS[k].name, Warehouses.KINDS[k].area, CitySim.money_text(int(spec.cost))]
		b.pressed.connect(func(): warehouse_tool.set_kind(k))
		stores.add_child(b)
		_warehouse_cards[k] = b
	for entry in [["oil", "oil", "Oil", "Oil company: pumpjacks spread over the oil field"],
			["ore", "ore", "Mining", "Mining company: pits open where the ore is"],
			["forest", "forest", "Forestry", "Forestry company: logging stands in the woods"]]:
		var k: String = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = "%s ($%s)" % [entry[3], CitySim.money_text(int(Industry.KINDS[k].cost))]
		b.pressed.connect(func():
			_industry_kind = k
			industry_tool.set_kind(k))
		hq.add_child(b)
		_industry_cards[k] = b
	for entry in [["reserve", "reserve", "Reserve", FarmTool.Mode.RESERVE, "Outline land to save for this industry: no roads or zoning there"],
			["release", "dezone", "Release", FarmTool.Mode.CLEAR, "Release reserved land"]]:
		var m: int = entry[3]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[4]
		b.pressed.connect(func():
			farm_tool.reserve_kind = _industry_kind
			farm_tool.set_mode(m))
		b.tooltip_text = entry[4].replace("this industry", "the farm or company you last picked")
		area.add_child(b)
		_industry_cards[entry[0]] = b
	return drawer


## The traffic controls, shown above the road menus while Traffic is open.
func _fill_traffic_row(row: HBoxContainer) -> void:
	var view := _section(row, "View")
	var junctions := _section(row, "Junctions  ·  click one to set it")
	for entry in [[TrafficTool.Mode.VIEW, "flow", "Flow", "Roads coloured by traffic flow  (J)", view],
			[TrafficTool.Mode.AUTO, "auto", "Auto", "Let the game choose, by US rules", junctions],
			[TrafficTool.Mode.SIGNAL, "signal", "Lights", "Traffic lights", junctions],
			[TrafficTool.Mode.ALL_STOP, "allstop", "All-way", "All-way stop: first to stop goes first", junctions],
			[TrafficTool.Mode.STOP, "stop", "Stop signs", "Stop signs on the smaller road only", junctions],
			[TrafficTool.Mode.NO_CONTROL, "nocontrol", "None", "No signs or lights", junctions]]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[3]
		b.pressed.connect(func(): traffic_tool.set_mode(m))
		(entry[4] as HBoxContainer).add_child(b)
		_traffic_cards[m] = b


## A titled group of cards inside a drawer; returns the row to fill.
func _section(parent: Container, title: String) -> HBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	col.add_child(UiStyle.label(title.to_upper(), 10, UiStyle.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	col.add_child(row)
	return row


## A compact tool card: icon over a name. The key or detail is in the tooltip.
func _card(icon: String, title: String, detail: String, toggle := true) -> Button:
	var b := Button.new()
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 50)
	b.tooltip_text = "%s  (%s)" % [title, detail]
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var ic := Icon.new(icon, 24)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var t := UiStyle.label(title, 11)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	b.set_meta("icon", ic)
	return b


func _icon_button(icon: String, px: int, tip: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px + 6, px)
	b.tooltip_text = tip
	var ic := Icon.new(icon, px * 0.6)
	ic.custom_minimum_size = Vector2.ZERO
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 6
	ic.offset_top = 5
	ic.offset_right = -6
	ic.offset_bottom = -5
	b.add_child(ic)
	return b


## Opens a tool category (or closes it if it's already open).
func _open(cat: String) -> void:
	_budget_open = false
	if cat == _category and cat != "bulldoze":
		close_all()
		return
	match cat:
		"roads":
			if road_tool.mode in [RoadTool.Mode.NONE, RoadTool.Mode.BULLDOZE]:
				road_tool.set_mode(road_tool.last_draw)
		"zones":
			if zone_tool.zone == ZoneTool.OFF:
				zone_tool.set_zone(ZoneMap.Zone.RESIDENTIAL)
		"bulldoze":
			road_tool.set_mode(RoadTool.Mode.BULLDOZE)
		"move":
			move_tool.set_active(true)
		"industry":
			if industry_tool.kind == "" and farm_tool.mode == FarmTool.Mode.NONE:
				if _industry_kind == "farm":
					farm_tool.set_mode(FarmTool.Mode.CORN)
				else:
					industry_tool.set_kind(_industry_kind)
		"services":
			if service_tool.kind == ServiceTool.OFF:
				service_tool.set_kind(Services.Kind.POWER_FEED)
		"parks":
			if park_tool.kind == "":
				park_tool.set_kind("park")
		"budget":
			road_tool.set_mode(RoadTool.Mode.NONE)
			zone_tool.set_zone(ZoneTool.OFF)
			service_tool.set_kind(ServiceTool.OFF)
			farm_tool.set_mode(FarmTool.Mode.NONE)
			industry_tool.set_kind("")
			warehouse_tool.set_kind("")
			campus_tool.set_kind("")
			telecom_tool.set_kind("")
			bank_tool.set_kind("")
			traffic_tool.set_mode(TrafficTool.Mode.NONE)
			park_tool.set_kind("")
			move_tool.set_active(false)
			# Docked on the left, like the Views column and the info panel.
			_show_view("")
			_views_panel.visible = false
			_views_button.set_pressed_no_signal(false)
			select_tool.select({})
			_budget_open = true
			economy_page.refresh()
			_sync()


## The advisor's notes follow the tool in hand, so Farming and Traffic keep
## their own tips inside Industry and Roads.
func _advisor_key() -> String:
	if traffic_tool.mode != TrafficTool.Mode.NONE:
		return "traffic"
	if farm_tool.mode in [FarmTool.Mode.CORN, FarmTool.Mode.SOYBEANS] or (farm_tool.mode != FarmTool.Mode.NONE
			and farm_tool.reserve_kind == "farm"):
		return "farms"
	return _category


## Brings every button in line with the tools (keys change them too).
func _sync() -> void:
	if zone_tool.zone != ZoneTool.OFF:
		_category = "zones"
	elif service_tool.kind != ServiceTool.OFF or campus_tool.kind != "" or industry_tool.kind == "power" \
			or bank_tool.kind != "" or telecom_tool.kind != "":
		_category = "services"
	elif park_tool.kind != "":
		_category = "parks"
	elif industry_tool.kind != "" or warehouse_tool.kind != "" or farm_tool.mode != FarmTool.Mode.NONE:
		_category = "industry"
	elif traffic_tool.mode != TrafficTool.Mode.NONE or neighborhood_tool.kind != "":
		_category = "roads"
	elif move_tool.active:
		_category = "move"
	elif road_tool.mode == RoadTool.Mode.BULLDOZE:
		_category = "bulldoze"
	elif road_tool.mode != RoadTool.Mode.NONE:
		_category = "roads"
	else:
		_category = "budget" if _budget_open else ""
	_budget_open = _category == "budget"
	economy_page.visible = _budget_open
	for key in _category_buttons:
		_category_buttons[key].set_pressed_no_signal(key == _category)
	for key in _drawers:
		_drawers[key].visible = key == _category
	_drawer_dock.visible = _drawers.has(_category)
	lot_alerts.show_empty = _category in ["zones", "services"]
	_fit_bottom.call_deferred()
	for m in _tool_cards:
		_tool_cards[m].set_pressed_no_signal(m == road_tool.mode)
	var menu := RoadStyle.group(road_tool.road_type)
	_variant_of[menu] = road_tool.road_type
	var in_traffic := traffic_tool.mode != TrafficTool.Mode.NONE
	for g in _type_cards:
		_type_cards[g].set_pressed_no_signal(g == menu and not in_traffic)
		# The menu card shows the kind picked in it.
		(_type_cards[g].get_meta("icon") as Icon).kind = \
			RoadStyle.TYPES[g].name.to_lower() if _variant_of.get(g, g) == g else "road:%d" % _variant_of[g]
	_show_variants(menu)
	for t in _variant_cards:
		_variant_cards[t].set_pressed_no_signal(t == road_tool.road_type and not in_traffic)
	_variant_row.get_parent().visible = not in_traffic and _kinds_open
	_traffic_row.visible = in_traffic
	_traffic_card.set_pressed_no_signal(in_traffic)
	_neighborhood_card.set_pressed_no_signal(neighborhood_tool.kind != "")
	for z in _zone_cards:
		_zone_cards[z].set_pressed_no_signal(z == zone_tool.zone)
	for k in _service_cards:
		_service_cards[k].set_pressed_no_signal(k == service_tool.kind)
	for k in _park_cards:
		_park_cards[k].set_pressed_no_signal(k == park_tool.kind)
		_park_cards[k].disabled = Parks.KINDS[k].landmark and sim.parks.has_kind(k)
	if _power_card != null:
		_power_card.set_pressed_no_signal(industry_tool.kind == "power")
	for k in _campus_cards:
		_campus_cards[k].set_pressed_no_signal(k == campus_tool.kind)
	if _telecom_card != null:
		_telecom_card.set_pressed_no_signal(telecom_tool.kind != "")
		_telecom_card.disabled = not sim.telecom.companies.is_empty()
	for k in _bank_cards:
		_bank_cards[k].set_pressed_no_signal(k == bank_tool.kind)
	for m in _farm_cards:
		_farm_cards[m].set_pressed_no_signal(m == farm_tool.mode)
	for k in _industry_cards:
		var on: bool = k == industry_tool.kind
		if k == "reserve":
			on = _category == "industry" and farm_tool.mode == FarmTool.Mode.RESERVE
		elif k == "release":
			on = _category == "industry" and farm_tool.mode == FarmTool.Mode.CLEAR
		_industry_cards[k].set_pressed_no_signal(on)
	for k in _warehouse_cards:
		_warehouse_cards[k].set_pressed_no_signal(k == warehouse_tool.kind)
	for m in _traffic_cards:
		_traffic_cards[m].set_pressed_no_signal(m == traffic_tool.mode)
	_parallel_card.set_pressed_no_signal(road_tool.parallel)
	_shape_card.set_pressed_no_signal(road_tool.grid_free)
	_shape_card.visible = road_tool.mode == RoadTool.Mode.GRID
	_grid_sizes.visible = road_tool.mode == RoadTool.Mode.GRID and not _kinds_open and not in_traffic
	for i in _grid_size_cards.size():
		_grid_size_cards[i].set_pressed_no_signal(i == road_tool.grid_preset)
	_elevation.text = "Ground" if road_tool.elevation == 0.0 else "%+d ft" % roundi(road_tool.elevation * RoadTool.FT)
	if _category == "" or _category == "budget":
		_show_hint("")


func _update_stats() -> void:
	var s := sim.stats
	var unemployed: float = 0.0 if s.workers == 0 else 100.0 * (s.workers - s.employed) / s.workers
	_pop.text = _thousands(s.population)
	_jobs.text = "%s  ·  %d%% unemployed" % [_thousands(s.jobs), roundi(unemployed)]
	for z in _demand_bars:
		_demand_bars[z].value = sim.demand[z]
	var e := sim.economy
	var net := e.monthly_net()
	_net.text = "%s$%s/mo" % ["+" if net >= 0 else "–", _thousands(absi(net))]
	_net.add_theme_color_override("font_color", GOOD if net >= 0 else BAD)
	var unserved := sim.unserved_count()
	# A short chip, like CS2's problem counter; the full story is in its tooltip.
	var short := sim.utility_summary()
	var full := sim.utility_problem()
	if unserved > 0:
		short = ("%s · %d leaving" % [short, unserved]) if short != "" else "%d buildings losing people" % unserved
		full = ("%s. People are leaving %d buildings" % [full, unserved]) if full != "" else \
			"%d buildings without power or water: people are leaving" % unserved
	_warning.text = ("⚠ " + short) if short != "" else ""
	_warning.tooltip_text = full + ". Click a lot or building to see what it lacks." if full != "" else ""


# --- Economy page (the bottom bar's Economy button) ------------------------

func _build_economy() -> void:
	economy_page.setup(sim)
	_root.add_child(economy_page)
	economy_page.closed.connect(func():
		_budget_open = false
		_sync())
	_info_panel.open_economy.connect(func():
		if not _budget_open:
			var sel := select_tool.selection.duplicate()
			_open("budget")
			select_tool.select(sel))


# --- Advisor (from the top bar) --------------------------------------------

## Docked flush to the right edge, just under the top bar.
func _build_advisor() -> void:
	_root.add_child(advisor)
	advisor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	advisor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var place := func():
		advisor.offset_right = 0
		advisor.offset_left = 0
		advisor.offset_top = _top_bar.size.y
	_top_bar.resized.connect(place)
	place.call_deferred()
	advisor.opened.connect(func():
		permits.close_panel()
		region_panel.close_panel()
		_help.visible = false
		_help_button.set_pressed_no_signal(false))


## Permit requests: the bell's panel, docked where the advisor's is.
func _build_permits() -> void:
	_root.add_child(permits)
	permits.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	permits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var place := func():
		permits.offset_right = 0
		permits.offset_left = 0
		permits.offset_top = _top_bar.size.y
	_top_bar.resized.connect(place)
	place.call_deferred()
	permits.opened.connect(func():
		advisor.close_panel()
		region_panel.close_panel()
		_help.visible = false
		_help_button.set_pressed_no_signal(false))



## The region panel: docked where the bell's is.
func _build_region_panel() -> void:
	_root.add_child(region_panel)
	region_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	region_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var place := func():
		region_panel.offset_right = 0
		region_panel.offset_left = 0
		region_panel.offset_top = _top_bar.size.y
	_top_bar.resized.connect(place)
	place.call_deferred()
	region_panel.opened.connect(func():
		advisor.close_panel()
		permits.close_panel()
		_help.visible = false
		_help_button.set_pressed_no_signal(false))


# --- Help (from the top bar) -----------------------------------------------

func _build_help() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_help.add_child(col)
	col.add_child(UiStyle.label("CAMERA", 10, UiStyle.MUTED))
	for line in ["W A S D  move  (Shift: faster)", "Q / E  rotate", "T / G  tilt", "R / F or scroll  zoom",
			"Right drag  move the map", "Middle drag or Option + drag  rotate", "Space  pause"]:
		col.add_child(UiStyle.label(line, 12))
	col.add_child(UiStyle.label("TOOLS", 10, UiStyle.MUTED))
	for line in ["1 2 3 4  road, curve, grid, roundabout", "U upgrade   P parallel   B bulldoze",
			"Page Up / Down  bridge or tunnel", "5 6 7 8  homes, shops, industry, dezone",
			"Services: place beside a road; green roads show coverage",
			"J  traffic view; Traffic: set lights or stop signs",
			"Right click  stop drawing", "Esc  stop drawing, then close everything"]:
		col.add_child(UiStyle.label(line, 12))
	var clear := Button.new()
	clear.text = "Start over (clear the map)"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func(): sim.apply({"type": "clear"}))
	col.add_child(clear)
	col.add_child(UiStyle.label("Build " + _build_name(), 10, UiStyle.MUTED))
	_help.visible = false
	_root.add_child(_help)
	_pin(_help, Control.PRESET_TOP_RIGHT, Vector2(-6, 42))


## The build stamp written by the web preview workflow, or "dev" locally:
## the commit and when it was built, in the player's own time zone.
static func _build_name() -> String:
	if not ResourceLoader.exists("res://scripts/build_info.gd"):
		return "dev"
	var info: Script = load("res://scripts/build_info.gd")
	var consts := info.get_script_constant_map()
	if not consts.has("BUILT_AT"):
		return str(consts.get("BUILD", "dev"))
	return "%s  %s" % [consts.BUILD, local_time_text(int(consts.BUILT_AT))]


## A moment as the player's clock shows it, e.g. "Oct 22, 9:06 PM".
static func local_time_text(unix: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var h: int = int(t.hour) % 12
	return "%s %d, %d:%02d %s" % [months[int(t.month) - 1], int(t.day), 12 if h == 0 else h, int(t.minute),
		"PM" if int(t.hour) >= 12 else "AM"]


static func _thousands(n: int) -> String:
	return CitySim.money_text(n)


## Pins a control to a corner of the screen, `offset` pixels in from it,
## growing away from the corner as its content changes.
static func _pin(c: Control, corner: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0 else \
		(Control.GROW_DIRECTION_BOTH if offset.x == 0 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0 else Control.GROW_DIRECTION_END
	c.position += offset
