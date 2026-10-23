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
## The town's services are split up like CS2's toolbar groups, so no
## menu spreads across the screen.
const CATEGORIES := [["roads", "Roads"], ["zones", "Zoning"], ["industry", "Industry"],
	["utilities", "Utilities", "power"], ["civic", "Civic", "police"], ["education", "Education", "school"],
	["health", "Health", "health"], ["transport", "Transport", "bus"],
	["parks", "Parks"], ["bulldoze", "Bulldoze"], ["move", "Move It"], ["budget", "Economy"]]
## The bottom bar categories that hold the town's services.
const SERVICE_CATEGORIES := ["utilities", "civic", "education", "health", "transport"]
const BAD := Color(0.95, 0.45, 0.4)

var road_tool: RoadTool
var zone_tool: ZoneTool
var service_tool: ServiceTool
var farm_tool: FarmTool
var industry_tool: IndustryTool
var park_tool: ParkTool
var _park_cards := {}  # Parks kind -> Button
var _park_sizes: Control
var _park_size_cards := []
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
var _warehouse_cards := {}  # Warehouses size -> Button, in the size row
var _warehouse_card: Button
var _warehouse_sizes: Control
var _warehouse_last: String = Warehouses.ORDER[0]  # the size the Warehouse card picks
var big_tool: BigFactoryTool
var _big_cards := {}  # BigFactories kind -> Button
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
var _plan_cards := {}    # LandPlan kind ("" erases) -> Button
var _power_card: Button
var _service_cards := {} # Services.Kind -> Button
var _service_cat := {}   # Services.Kind -> its bottom bar category
var _first_card := {}    # service category -> the card it opens on
var _farm_cards := {}    # FarmTool.Mode -> Button
var _warning := UiStyle.label("", 13, Color(1.0, 0.75, 0.3))
var _parallel_card: Button
## Grid only: any shape instead of a rectangle.
var _exact_card: Button
## Grid only: a row of real-world grid sizes above the road tools.
var _grid_sizes: Control
var _grid_size_cards := []
var _ring_sizes: Control
var _ring_size_cards := []
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
var _warning_box: PanelContainer
## The Economy page (the bottom bar's Economy button) is open.
var _budget_open := false
var economy_page := EconomyPage.new()
var _help := PanelContainer.new()
var _top_bar: PanelContainer
var _town_button: Button  # top bar buttons from elsewhere go just before it
var _views_panel := PanelContainer.new()
var _views_button: Button
var _view_cards := {}  # view key -> Button
var _view := ""
var _help_button: Button
var advisor := AdvisorPanel.new()
var permits := PermitPanel.new()
## The region's shared projects and services (only in a region).
var region_panel := RegionPanel.new()
## The town's nickname, history, districts and markers, and its timelapse.
var town := TownPanel.new()
var timelapse := TimelapseView.new()
## What's behind each top bar readout: a chart and its numbers.
var stats_panel := StatsPanel.new()
## The guided first town (FirstTown): plan, streets, power, water, homes.
var tour := FirstTownTour.new()
## Back to your town centre, or to a neighbor's.
var jump: TownJump
var _towns_panel := PanelContainer.new()
var _towns_list := VBoxContainer.new()
var _towns_button: Button
## The cards the pad wheel's second ring offers ("tool:<n>" picks one).
var _wheel_tools: Array[Button] = []


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
	_build_town()
	_info_panel.setup(sim, select_tool)
	_root.add_child(_info_panel)
	_build_economy()
	_build_stats()
	tour.setup(sim, self, info_view.cam, game)
	_root.add_child(tour)

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
	big_tool.kind_changed.connect(func(_k): _sync())
	big_tool.hint_changed.connect(_show_hint)
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
	if k != null and k.pressed and not k.echo and k.keycode == KEY_HOME:
		jump.go_home()
		get_viewport().set_input_as_handled()
		return
	# Ctrl+Z (Cmd+Z on a Mac; View + X on a controller): undo the last build.
	# Move It keeps its own undo while it's in hand.
	if k != null and k.pressed and not k.echo and k.keycode == KEY_Z and (k.ctrl_pressed or k.meta_pressed) \
			and not move_tool.active:
		undo_last()
		get_viewport().set_input_as_handled()
		return
	if k != null and k.pressed and not k.echo and not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed):
		var cat := hotkey_category(k)
		if cat != "":
			_open(cat)
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_V and not k.shift_pressed:
			_views_button.button_pressed = not _views_button.button_pressed
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_F1 or k.keycode == KEY_SLASH and k.shift_pressed:
			_help_button.button_pressed = not _help_button.button_pressed
			get_viewport().set_input_as_handled()
			return
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


## Takes back the last road or building placed in the last 30 seconds, with
## a full refund.
func undo_last() -> void:
	var e := sim.undo.last(sim)
	if e.is_empty() or Time.get_ticks_msec() - int(e.at_ms) > UndoLog.WINDOW_MS:
		_show_hint("Nothing to undo.")
		return
	sim.apply({"type": "undo"})
	var was := _hint.text
	var note := "Undone. $%s back." % _thousands(int(e.refund))
	_show_hint(note)
	get_tree().create_timer(3.0).timeout.connect(func(): if _hint.text == note: _show_hint(was))


## The bottom bar menus Shift + 1 to 0 open, in bar order (Bulldoze and
## Move It keep their own B and M).
static func hotkey_categories() -> Array:
	var keys := []
	for entry in CATEGORIES:
		if not entry[0] in ["bulldoze", "move"]:
			keys.append(entry[0])
	return keys.slice(0, 10)


## The menu a key opens: Shift + a number key, or "".
static func hotkey_category(k: InputEventKey) -> String:
	if not k.shift_pressed:
		return ""
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code < KEY_0 or code > KEY_9:
		return ""
	var i := 9 if code == KEY_0 else code - KEY_1
	var cats := hotkey_categories()
	return cats[i] if i < cats.size() else ""


## The key that opens a menu, for its tooltip.
static func hotkey_text(cat: String) -> String:
	if cat == "bulldoze":
		return "B"
	if cat == "move":
		return "M"
	var i := hotkey_categories().find(cat)
	return "" if i < 0 else "Shift+%d" % ((i + 1) % 10)


## Game controllers (Pad): the tool wheel holds the bottom bar's categories
## and the Views.
func pad_wheel_items() -> Array:
	var items := []
	for entry in CATEGORIES:
		items.append([entry[2] if entry.size() > 2 else entry[0], entry[1], entry[0]])
	return items + [["views", "Views", "views"]]


## Which first-ring slot starts lit: the open menu.
func pad_category_index() -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i][0] == _category:
			return i
	return 0


## Opens what the wheel picked. A menu with tools answers with its tools for
## the second ring (like the console editions' radial sub-menus); picking
## one of those presses its card. Empty means the wheel stays closed.
func pad_wheel_pick(key: String) -> Array:
	if key.begins_with("tool:"):
		var i := int(key.substr(5))
		if i < _wheel_tools.size() and is_instance_valid(_wheel_tools[i]) and not _wheel_tools[i].disabled:
			_wheel_tools[i].pressed.emit()
			if _wheel_tools[i].toggle_mode:
				_sync()
		return []
	if key == "views":
		_views_button.button_pressed = not _views_button.button_pressed
		return []
	if key != _category or key == "bulldoze":
		_open(key)
	return pad_tool_items(key)


## The cards in a menu's drawer, for the wheel's second ring.
func pad_tool_items(cat: String) -> Array:
	_wheel_tools.clear()
	var items := []
	if not _drawers.has(cat) or _category != cat:
		return items
	_collect_cards(_drawers[cat], items)
	return items


## Which second-ring slot starts lit: the tool already in hand.
func pad_tool_selected() -> int:
	for i in _wheel_tools.size():
		if is_instance_valid(_wheel_tools[i]) and _wheel_tools[i].button_pressed:
			return i
	return 0


func _collect_cards(n: Node, items: Array) -> void:
	for c in n.get_children():
		if c is Button and c.has_meta("title") and (c as Button).is_visible_in_tree():
			var b := c as Button
			_wheel_tools.append(b)
			items.append([(b.get_meta("icon") as Icon).kind, (b.get_meta("title") as Label).text, "tool:%d" % (_wheel_tools.size() - 1)])
		elif c is Control:
			_collect_cards(c, items)


## A grid shape or an outline is being drawn, so Enter finishes it (the
## pad's right stick click does the same).
func shape_open() -> bool:
	return road_tool.mode == RoadTool.Mode.GRID and road_tool.is_drawing() or farm_tool.is_drawing()


## How tall the bottom dock is, so the pad's prompts sit just above it.
func pad_bottom_height() -> float:
	return _bottom.size.y


## True while a tool is in hand, a panel or view is open, or something is selected.
func anything_open() -> bool:
	return _budget_open or _view != "" or _views_panel.visible or _help.visible or advisor.visible or permits.visible or region_panel.visible \
		or town.visible or timelapse.visible or stats_panel.visible or _towns_panel.visible \
		or not select_tool.selection.is_empty() or road_tool.mode != RoadTool.Mode.NONE \
		or zone_tool.zone != ZoneTool.OFF or service_tool.kind != ServiceTool.OFF \
		or farm_tool.mode != FarmTool.Mode.NONE or traffic_tool.mode != TrafficTool.Mode.NONE \
		or industry_tool.kind != "" or warehouse_tool.kind != "" or park_tool.kind != "" or campus_tool.kind != "" or bank_tool.kind != "" or telecom_tool.kind != "" or move_tool.active \
		or neighborhood_tool.kind != "" or big_tool.kind != ""


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
	town.close_panel()
	timelapse.close_view()
	stats_panel.close_panel()
	_show_towns(false)
	road_tool.set_mode(RoadTool.Mode.NONE)
	zone_tool.set_zone(ZoneTool.OFF)
	service_tool.set_kind(ServiceTool.OFF)
	farm_tool.set_mode(FarmTool.Mode.NONE)
	industry_tool.set_kind("")
	warehouse_tool.set_kind("")
	big_tool.set_kind("")
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
	# A stat's panel sits beside the Views column, the info panel beside it.
	stats_panel.position = Vector2(left, _top_bar.size.y)
	if stats_panel.visible:
		left += stats_panel.size.x
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

	_views_button = _icon_button("views", 24, "Views: see the map by fertility, oil, ore, forest, services, traffic and pollution  (V)")
	_views_button.toggled.connect(func(on): _views_panel.visible = on)
	row.add_child(_views_button)
	# Home: back to your town centre (Home key); the arrow lists every town.
	jump = TownJump.new(sim, info_view.cam)
	var home := _icon_button("homes", 24, "Back to your town centre  (Home)")
	home.toggle_mode = false
	home.pressed.connect(func():
		_show_towns(false)
		jump.go_home())
	row.add_child(home)
	_towns_button = Button.new()
	_towns_button.text = "▾"
	_towns_button.toggle_mode = true
	_towns_button.focus_mode = Control.FOCUS_NONE
	_towns_button.custom_minimum_size = Vector2(18, 24)
	_towns_button.tooltip_text = "Go to a town: yours or a neighbor's"
	_towns_button.toggled.connect(_show_towns)
	row.add_child(_towns_button)
	row.add_child(VSeparator.new())
	_stat(row, "people", _pop, "Population: click for its chart and where people live", "population")
	_stat(row, "jobs", _jobs, "Jobs and unemployment: click for the chart and where people work", "jobs")
	_stat(row, "car", _cars, "Cars on the road and how freely traffic flows: click for the chart and the slowest roads", "traffic")
	row.add_child(VSeparator.new())
	var demand_row := HBoxContainer.new()
	demand_row.add_theme_constant_override("separation", 8)
	demand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_clickable(demand_row, "Demand for homes, shops and industry: click for the chart and why", "demand"))
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "H"], [ZoneMap.Zone.COMMERCIAL, "S"], [ZoneMap.Zone.INDUSTRIAL, "I"]]:
		var z: int = entry[0]
		var l := UiStyle.label(entry[1], 11, ZoneMap.COLORS[z])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		demand_row.add_child(l)
		var bar_z := ProgressBar.new()
		bar_z.show_percentage = false
		bar_z.custom_minimum_size = Vector2(34, 7)
		bar_z.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_z.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = ZoneMap.COLORS[z]
		fill.set_corner_radius_all(3)
		bar_z.add_theme_stylebox_override("fill", fill)
		bar_z.mouse_filter = Control.MOUSE_FILTER_IGNORE
		demand_row.add_child(bar_z)
		_demand_bars[z] = bar_z
	row.add_child(VSeparator.new())
	var money_row := _stat(row, "money", _money, "City funds: click for the chart and this month's money in and out", "money")
	_net.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_row.add_child(_net)
	_warning.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Never push the clock and speed buttons off the bar.
	_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning.clip_text = true
	_warning.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_warning_box = _clickable(_warning, "", "problems")
	_warning_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_warning_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clickable(_clock, "The date: click for the town's years", "date"))
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
	town.setup(sim, info_view.cam)
	_town_button = town.make_button()
	row.add_child(_town_button)
	permits.setup(sim, game, info_view.cam)
	row.add_child(permits.make_button())
	advisor.setup(sim, func(): return _advisor_key() if _category != "" or _view == "" else "view_" + _view)
	row.add_child(advisor.make_button())
	_help_button = _icon_button("help", 24, "Controls  (F1)")
	_help_button.toggled.connect(func(on):
		_help.visible = on
		if on:
			advisor.close_panel()
			permits.close_panel()
			town.close_panel()
			region_panel.close_panel())
	row.add_child(_help_button)


## Puts a button from outside the HUD (the region chat's) in the top bar,
## with the other panel buttons.
func add_top_button(b: Control) -> void:
	var row := _town_button.get_parent()
	row.add_child(b)
	row.move_child(b, _town_button.get_index())


## An icon and a value, side by side; a click opens the stat's panel.
## Returns the row, so more can go in it.
func _stat(row: HBoxContainer, icon: String, value: Label, tip: String, key: String) -> HBoxContainer:
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(icon, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(ic)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(value)
	row.add_child(_clickable(inner, tip, key))
	return inner


## Wraps a top bar readout so it lights up under the mouse and a click opens
## its panel in StatsPanel (Cities: Skylines 2's top bar works the same way).
func _clickable(content: Control, tip: String, key: String) -> PanelContainer:
	var box := PanelContainer.new()
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color.TRANSPARENT
	idle.set_corner_radius_all(UiStyle.RADIUS_SM)
	idle.content_margin_left = 4
	idle.content_margin_right = 4
	var lit := idle.duplicate() as StyleBoxFlat
	lit.bg_color = Color(Brand.SURFACE_RAISED, 0.9)
	box.add_theme_stylebox_override("panel", idle)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.tooltip_text = tip
	box.mouse_entered.connect(func(): box.add_theme_stylebox_override("panel", lit))
	box.mouse_exited.connect(func(): box.add_theme_stylebox_override("panel", idle))
	box.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			open_stat(key)
			box.accept_event())
	box.add_child(content)
	return box


## Opens (or closes) a top bar stat's panel: "population", "jobs", "traffic",
## "demand", "money", "date" or "problems".
func open_stat(key: String) -> void:
	if _budget_open:
		_budget_open = false
		_sync()
	_show_towns(false)
	stats_panel.toggle(key)


func _build_stats() -> void:
	stats_panel.setup(sim, info_view.cam, select_tool.select)
	_root.add_child(stats_panel)
	stats_panel.show_view.connect(func(k: String):
		_views_button.button_pressed = true
		_show_view(k))
	stats_panel.open_economy.connect(func():
		stats_panel.close_panel()
		if not _budget_open:
			_open("budget"))
	stats_panel.pick_zone.connect(func(z: int):
		if _category != "zones":
			_open("zones")
		zone_tool.set_zone(z))
	# The list of towns drops down under its arrow.
	_towns_panel.add_theme_stylebox_override("panel", UiStyle.dock(true))
	_towns_panel.visible = false
	_towns_list.add_theme_constant_override("separation", 2)
	_towns_panel.add_child(_towns_list)
	_root.add_child(_towns_panel)


## Shows or hides the list of towns to go to, under the top bar's arrow.
func _show_towns(on: bool) -> void:
	_towns_panel.visible = on
	if _towns_button:
		_towns_button.set_pressed_no_signal(on)
	if not on:
		return
	for c in _towns_list.get_children():
		c.queue_free()
	_towns_list.add_child(UiStyle.label("GO TO A TOWN", 10, UiStyle.MUTED, 600))
	for t in jump.towns():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.text = "%s%s  ·  %s people%s" % [t.name, ("" if t.name == "Your town" else "  (yours)") if t.mine else ("  ·  " + t.player if t.player != "" else ""),
			_thousands(t.people), "" if t.online else "  ·  away"]
		b.add_theme_color_override("font_color", Brand.CORAL_TEXT if t.mine else (Brand.INK if t.online else Brand.INK_FAINT))
		b.tooltip_text = "Fly to the middle of " + t.name + ("  (Home)" if t.mine else "")
		var at: Vector3 = t.at
		b.pressed.connect(func():
			_show_towns(false)
			jump.go(at))
		_towns_list.add_child(b)
	_towns_panel.position = Vector2(_towns_button.global_position.x - 40.0, _top_bar.size.y)


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
	_drawers["utilities"] = _utilities_drawer()
	_drawers["civic"] = _civic_drawer()
	_drawers["education"] = _education_drawer()
	_drawers["health"] = _health_drawer()
	_drawers["transport"] = _transport_drawer()
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
		var b := _category_button(entry[2] if entry.size() > 2 else entry[0], entry[1])
		b.tooltip_text = "%s  (%s)" % [entry[1], hotkey_text(entry[0])]
		b.pressed.connect(func(): _open(entry[0]))
		row.add_child(b)
		_category_buttons[entry[0]] = b

	dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fit_bottom()


## Acres for a card: "3/4" under one, whole acres above.
static func _acres_text(acres: float) -> String:
	return "3/4" if acres < 1.0 else str(roundi(acres))


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
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(row)
	var ic := Icon.new(icon, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var t := UiStyle.label(title, 13)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	# Snug to its title, so twelve categories still sit in a compact row.
	b.custom_minimum_size.x = maxf(64.0, ceilf(t.get_minimum_size().x) + 20 + 5 + 16)
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
	# Every grid control sits in this one row: the sizes, then how blocks fit.
	sizes_row.add_child(VSeparator.new())
	var fit := _section(sizes_row, "Blocks")
	_exact_card = _card("grid", "Exact", "Exact: whole blocks of the chosen size only (a section is a true mile).\nAdaptive: blocks flex to fit the shape, never bigger than the chosen size.")
	_exact_card.pressed.connect(func(): road_tool.set_grid_exact(not road_tool.grid_exact))
	fit.add_child(_exact_card)
	_grid_sizes = sizes_row
	# Roundabout sizes share the same spot: only one row of options at a time.
	var rings_row := HBoxContainer.new()
	rings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(rings_row)
	var rings := _section(rings_row, "Roundabout size  ·  FHWA sizes, curb to curb  ·  [ ] fine-tune")
	for i in RoadShapes.ROUNDABOUT_SIZES.size():
		var p: Dictionary = RoadShapes.ROUNDABOUT_SIZES[i]
		var b := _card("roundabout", p.name, "%d ft, %d %s" % [roundi(p.icd), p.lanes, "lane" if p.lanes == 1 else "lanes"])
		b.tooltip_text = p.about
		b.pressed.connect(func(): road_tool.set_roundabout_preset(i))
		rings.add_child(b)
		_ring_size_cards.append(b)
	_ring_sizes = rings_row

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
	# Raise over the height over Lower, in one card's space.
	var elev := VBoxContainer.new()
	elev.add_theme_constant_override("separation", 0)
	elev.custom_minimum_size = Vector2(56, 50)
	opts.add_child(elev)
	var raise := _step_button("raise", "Raise: bridge  (Page Up)")
	raise.pressed.connect(func(): road_tool.change_elevation(1))
	elev.add_child(raise)
	_elevation.add_theme_font_size_override("font_size", 11)
	_elevation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elevation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_elevation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	elev.add_child(_elevation)
	var lower := _step_button("lower", "Lower: tunnel  (Page Down)")
	lower.pressed.connect(func(): road_tool.change_elevation(-1))
	elev.add_child(lower)

	row.add_child(VSeparator.new())
	var traffic := _section(row, "Traffic and town")
	_traffic_card = _card("traffic", "Traffic", "J")
	_traffic_card.tooltip_text = "Traffic flow, lights and stop signs  (J)"
	_traffic_card.pressed.connect(func():
		if traffic_tool.mode == TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.VIEW)
		else:
			road_tool.set_mode(road_tool.last_draw))
	traffic.add_child(_traffic_card)

	# A town hemmed in by its neighbors starts a new neighborhood on open land.
	var town := traffic
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
	# The future land use map: big soft areas, not zoning (LandPlan).
	row.add_child(VSeparator.new())
	var plan := _section(row, "Land use plan  ·  outline big areas")
	for entry in [["homes", "homes", "Homes"], ["shops", "shops", "Shops"], ["jobs", "industry", "Jobs"],
			["farms", "farms", "Farms"], ["", "dezone", "Erase"]]:
		var k: String = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = ("Plan this area for %s: builders look here first, and plans that match move faster. Nothing is blocked." \
			% LandPlan.KINDS[k]) if k != "" else "Take land out of your land use plan"
		if k != "":
			(b.get_meta("icon") as Icon).accent = LandPlan.COLORS[k]
		b.pressed.connect(func():
			if k != "":
				farm_tool.plan_kind = k
			farm_tool.set_mode(FarmTool.Mode.PLAN if k != "" else FarmTool.Mode.UNPLAN))
		plan.add_child(b)
		_plan_cards[k] = b
	return drawer


## A card for a Services kind, filed under its bottom bar category.
func _service_card(k: int, cat: String) -> Button:
	var s: Dictionary = Services.KINDS[k]
	var short := {Services.Kind.WATER_TOWER: "Water tower", Services.Kind.POWER_FEED: "Power line",
		Services.Kind.WELL: "Well", Services.Kind.SCHOOL: "Elementary", Services.Kind.WATER_UTILITY: "Water utility",
		Services.Kind.TAXI_COMPANY: "Taxis", Services.Kind.NURSING_HOME: "Nursing home", Services.Kind.BUS_DEPOT: "Bus depot"}
	var b := _card(s.icon, short.get(k, s.name.split(" ")[0]), "")
	b.tooltip_text = "%s: $%s to build, $%s a month" % [s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)]
	if k == Services.Kind.BUS_DEPOT:
		b.tooltip_text = "%s: $%s to build, with two buses. It plans its own stops, routes and fare; you set its funding." % [s.name, CitySim.money_text(s.cost)]
	elif k == Services.Kind.TAXI_COMPANY:
		b.tooltip_text = "%s: $%s to bring one to town, with two cabs. Its owner runs it on fares: the fleet, the meter and the lot." % [s.name, CitySim.money_text(s.cost)]
	b.pressed.connect(func(): service_tool.set_kind(k))
	_service_cards[k] = b
	_service_cat[k] = cat
	return b


## A card for a landfill, recycling center or cemetery: hubs that grow on their own.
func _hub_card(k: int, cat: String) -> Button:
	var hk: String = CivicHubs.TOOL_KINDS[k]
	var w: Dictionary = Balance.WASTE_SITES[hk]
	var title: String = CivicHubs.KINDS[hk].name
	var b := _card(CivicHubs.KINDS[hk].icon, {"recycling_1": "Recycling"}.get(hk, title), "")
	b.tooltip_text = "%s: $%s to build, $%s a month. Never fills up." % [title, CitySim.money_text(int(w.cost)),
		CitySim.money_text(int(w.upkeep))]
	b.pressed.connect(func(): service_tool.set_kind(k))
	_service_cards[k] = b
	_service_cat[k] = cat
	return b


## A drawer with one row of titled sections, as the service menus use.
func _service_drawer(cat: String, sections: Array) -> PanelContainer:
	var drawer := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	drawer.add_child(row)
	for sec in sections:
		if row.get_child_count() > 0:
			row.add_child(VSeparator.new())
		var cards := _section(row, sec[0])
		for b in sec[1]:
			cards.add_child(b)
			if not _first_card.has(cat):
				_first_card[cat] = b
	return drawer


## Utilities, like CS2's Electricity, Water & Sewage, Garbage and
## Communications menus: what every home and shop is hooked up to.
func _utilities_drawer() -> PanelContainer:
	var cat := "utilities"
	# Brawn's hub model: a company whose leader picks and grows the plant.
	_power_card = _card("power", "Power co.", "")
	_power_card.tooltip_text = "Power company: $%s. Its leader picks solar, wind, gas, a dam or an old coal plant, and grows it" \
		% CitySim.money_text(Balance.POWER_YARD_COST)
	_power_card.pressed.connect(func(): industry_tool.set_kind("power"))
	# The phone company: placed once, then it builds its own network.
	_telecom_card = _card("tower", "Phone co.", "")
	_telecom_card.tooltip_text = "Phone company: $%s to build, $%s a month grant. Its manager strings fiber and puts up cell towers where they pay off. One per town." % [
		CitySim.money_text(Balance.TELECOM_COST), CitySim.money_text(Balance.TELECOM_GRANT)]
	_telecom_card.pressed.connect(func(): telecom_tool.set_kind("telecom"))
	return _service_drawer(cat, [
		["Power", [_service_card(Services.Kind.POWER_FEED, cat), _service_card(Services.Kind.SUBSTATION, cat), _power_card]],
		["Water and sewer", [_service_card(Services.Kind.WELL, cat), _service_card(Services.Kind.WATER_TOWER, cat),
			_service_card(Services.Kind.WATER_UTILITY, cat)]],
		["Trash", [_hub_card(100, cat), _hub_card(101, cat)]],
		["Phone and internet", [_telecom_card]]])


## Civic: fire and police (CS2's Fire & Rescue, Police & Administration),
## the post office and the banks.
func _civic_drawer() -> PanelContainer:
	var cat := "civic"
	# The post office: its postmaster plans the routes.
	var pb := _card("mail", "Post office", "")
	pb.tooltip_text = "Post office: $%s to build, $%s a month. Its postmaster plans the routes." % [
		CitySim.money_text(Balance.MAIL_COST), CitySim.money_text(Balance.MAIL_UPKEEP)]
	pb.pressed.connect(func(): service_tool.set_kind(Mail.TOOL_KIND))
	_service_cards[Mail.TOOL_KIND] = pb
	_service_cat[Mail.TOOL_KIND] = cat
	# Banks lend to the farms, companies and builders (Brawn's hub model).
	var banks := []
	for k in ["community", "farm_credit"]:
		var b := _card("bank", {"community": "Bank", "farm_credit": "Farm Credit"}[k], "")
		b.tooltip_text = "%s: $%s for the lot. Its %s lends to %s, and buys the land next door as it grows." % [
			Banks.KINDS[k].name, CitySim.money_text(int(Banks.spec(k).cost)), Banks.KINDS[k].head.to_lower(),
			{"community": "farms, companies and builders", "farm_credit": "farms and timber"}[k]]
		b.pressed.connect(func(): bank_tool.set_kind(k))
		_bank_cards[k] = b
		banks.append(b)
	return _service_drawer(cat, [
		["Safety", [_service_card(Services.Kind.FIRE, cat), _service_card(Services.Kind.POLICE, cat)]],
		["Mail", [pb]],
		["Banks", banks]])


## Education, from daycare to the university (CS2's Education & Research).
## Campuses grow on their own once placed (Brawn's hub model).
func _education_drawer() -> PanelContainer:
	var cat := "education"
	var campus := []
	for k in ["high_school", "college", "university"]:
		var e: Dictionary = Education.spec(k)
		var b := _card("school", {"high_school": "High school", "college": "College", "university": "University"}[k], "")
		b.tooltip_text = "%s: $%s to build, $%s a month. Its %s buys the free land next to it as it fills." % [
			Education.KINDS[k].name, CitySim.money_text(e.cost), CitySim.money_text(e.funding), Education.KINDS[k].head.to_lower()]
		b.pressed.connect(func(): campus_tool.set_kind(k))
		_campus_cards[k] = b
		campus.append(b)
	return _service_drawer(cat, [
		["Schools", [_service_card(Services.Kind.SCHOOL, cat), _service_card(Services.Kind.DAYCARE, cat)]],
		["High school and college", campus]])


## Health and care, with the cemetery (CS2's Healthcare & Deathcare).
func _health_drawer() -> PanelContainer:
	var cat := "health"
	return _service_drawer(cat, [
		["Health and care", [_service_card(Services.Kind.CLINIC, cat), _service_card(Services.Kind.HOSPITAL, cat),
			_service_card(Services.Kind.NURSING_HOME, cat)]],
		["Cemetery", [_hub_card(102, cat)]]])


## Transport: buses, cabs and the railroad (CS2's Transportation).
func _transport_drawer() -> PanelContainer:
	var cat := "transport"
	# The railroad: its leader plans the track and asks before building.
	var rb := _card("train", "Rail depot", "")
	rb.tooltip_text = "Rail depot: $%s. Its leader lays track to the region and to industry, by your permit." % \
		CitySim.money_text(Balance.RAIL_DEPOT_COST)
	rb.pressed.connect(func(): service_tool.set_kind(Rail.TOOL_KIND))
	_service_cards[Rail.TOOL_KIND] = rb
	_service_cat[Rail.TOOL_KIND] = cat
	return _service_drawer(cat, [
		["Transit", [_service_card(Services.Kind.BUS_DEPOT, cat), _service_card(Services.Kind.TAXI_COMPANY, cat)]],
		["Rail", [rb]]])


func _parks_drawer() -> PanelContainer:
	var drawer := PanelContainer.new()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	drawer.add_child(stack)
	# The park size, in the one row above the tools while a park is in hand.
	_park_sizes = HBoxContainer.new()
	_park_sizes.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(_park_sizes)
	var sizes := _section(_park_sizes, "Park size  ·  NRPA park classes  ·  grows by itself")
	for i in Balance.PARK_SIZES.size():
		var ps: Dictionary = Balance.PARK_SIZES[i]
		var b := _card("park", ps.name, "%s acres, $%s" % [_acres_text(ps.size.x * ps.size.y / 4046.86), CitySim.money_text(int(ps.cost))])
		b.tooltip_text = ps.about
		b.custom_minimum_size.x = 96
		b.pressed.connect(func(): park_tool.set_size(i))
		sizes.add_child(b)
		_park_size_cards.append(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	stack.add_child(row)
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
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	drawer.add_child(stack)
	# Warehouse sizes, in the one row above the tools while a warehouse is in
	# hand (like the park sizes), so the menu stays one compact row.
	_warehouse_sizes = HBoxContainer.new()
	_warehouse_sizes.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(_warehouse_sizes)
	var sizes := _section(_warehouse_sizes, "Warehouse size  ·  beside a street")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	stack.add_child(row)
	var farms := _section(row, "Farmhouse  ·  near green soil")
	for entry in [[FarmTool.Mode.CORN, "corn", "Corn", "Corn farm: more income on rich soil"],
			[FarmTool.Mode.SOYBEANS, "soybeans", "Soybeans", "Soybean farm: steadier on poorer soil"]]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[3]
		b.pressed.connect(func():
			_industry_kind = "farm"
			farm_tool.set_mode(m)
			# As in CS2: placing a farm shows where the soil is good.
			_show_view("fertility"))
		farms.add_child(b)
		_farm_cards[m] = b
	var hq := _section(row, "Main building  ·  near the resource")
	var area := _section(row, "Save land")
	var stores := _section(row, "Storage")
	_warehouse_card = _card("warehouse", "Warehouse", "")
	_warehouse_card.tooltip_text = "Warehouses store raw loads and goods until a factory or shop needs them. Pick a size above."
	_warehouse_card.pressed.connect(func(): warehouse_tool.set_kind(_warehouse_last))
	stores.add_child(_warehouse_card)
	var plants := _section(row, "Big factories  ·  one per town")
	for k in BigFactories.ORDER:
		var kk: Dictionary = BigFactories.KINDS[k]
		var b := _card(kk.icon, kk.short, "")
		b.tooltip_text = "%s ($%s): makes %s from what your farms and companies bring in" \
			% [kk.name, CitySim.money_text(int(Balance.BIG_FACTORY[k].cost)), kk.makes]
		b.pressed.connect(func(): big_tool.set_kind(k))
		plants.add_child(b)
		_big_cards[k] = b
	for k in Warehouses.ORDER:
		var spec: Dictionary = Balance.WAREHOUSE[k]
		var b := _card("warehouse", ["Small", "Medium", "Large", "Distrib."][Warehouses.ORDER.find(k)], "")
		b.tooltip_text = "%s, %s ($%s): stores raw loads and goods until a factory or shop needs them" \
			% [Warehouses.KINDS[k].name, Warehouses.KINDS[k].area, CitySim.money_text(int(spec.cost))]
		b.pressed.connect(func(): warehouse_tool.set_kind(k))
		sizes.add_child(b)
		_warehouse_cards[k] = b
	for entry in [["oil", "oil", "Oil", "Oil company: pumpjacks spread over the oil field"],
			["ore", "ore", "Mining", "Mining company: pits open where the ore is"],
			["forest", "forest", "Forestry", "Forestry company: logging stands in the woods"]]:
		var k: String = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = "%s ($%s)" % [entry[3], CitySim.money_text(int(Industry.KINDS[k].cost))]
		b.pressed.connect(func():
			_industry_kind = k
			industry_tool.set_kind(k)
			_show_view(k))
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
	b.set_meta("title", t)
	return b


## A slim arrow button, a third of a card tall (road height up and down).
func _step_button(icon: String, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56, 16)
	b.tooltip_text = tip
	var ic := Icon.new(icon, 14)
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ic.position -= Vector2(7, 7)
	b.add_child(ic)
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


## A button the guided first town points at, or null: "cat:roads",
## "road:grid", "grid:5" (a GridFill preset), "svc:6" (a Services kind),
## "zone:1" (a ZoneMap zone).
func tour_target(key: String) -> Control:
	var i := key.find(":")
	var what := key.substr(0, i)
	var arg := key.substr(i + 1)
	match what:
		"cat":
			return _category_buttons.get(arg)
		"road":
			return _tool_cards.get(RoadTool.Mode.GRID) if arg == "grid" else null
		"grid":
			return _grid_size_cards[int(arg)] if int(arg) < _grid_size_cards.size() else null
		"svc":
			return _service_cards.get(int(arg))
		"zone":
			return _zone_cards.get(int(arg))
	return null


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
			if zone_tool.zone == ZoneTool.OFF and not farm_tool.mode in [FarmTool.Mode.PLAN, FarmTool.Mode.UNPLAN]:
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
		"utilities", "civic", "education", "health", "transport":
			_first_card[cat].pressed.emit()
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
			big_tool.set_kind("")
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
			stats_panel.close_panel()
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
	return "services" if _category in SERVICE_CATEGORIES else _category


## Brings every button in line with the tools (keys change them too).
func _sync() -> void:
	if zone_tool.zone != ZoneTool.OFF or farm_tool.mode in [FarmTool.Mode.PLAN, FarmTool.Mode.UNPLAN]:
		_category = "zones"
	elif service_tool.kind != ServiceTool.OFF:
		_category = _service_cat.get(service_tool.kind, "utilities")
	elif industry_tool.kind == "power" or telecom_tool.kind != "":
		_category = "utilities"
	elif campus_tool.kind != "":
		_category = "education"
	elif bank_tool.kind != "":
		_category = "civic"
	elif park_tool.kind != "":
		_category = "parks"
	elif industry_tool.kind != "" or warehouse_tool.kind != "" or big_tool.kind != "" or farm_tool.mode != FarmTool.Mode.NONE:
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
	lot_alerts.show_empty = _category == "zones" or _category in SERVICE_CATEGORIES
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
	for k in _plan_cards:
		_plan_cards[k].set_pressed_no_signal((farm_tool.mode == FarmTool.Mode.PLAN and k == farm_tool.plan_kind)
			or (farm_tool.mode == FarmTool.Mode.UNPLAN and k == ""))
	for k in _service_cards:
		_service_cards[k].set_pressed_no_signal(k == service_tool.kind)
	_park_sizes.visible = park_tool.kind == "park"
	for i in _park_size_cards.size():
		_park_size_cards[i].set_pressed_no_signal(park_tool.kind == "park" and i == park_tool.size_class)
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
	if warehouse_tool.kind != "":
		_warehouse_last = warehouse_tool.kind
	_warehouse_card.set_pressed_no_signal(warehouse_tool.kind != "")
	_warehouse_sizes.visible = warehouse_tool.kind != ""
	for k in _warehouse_cards:
		_warehouse_cards[k].set_pressed_no_signal(k == warehouse_tool.kind)
	for k in _big_cards:
		_big_cards[k].set_pressed_no_signal(k == big_tool.kind)
	for m in _traffic_cards:
		_traffic_cards[m].set_pressed_no_signal(m == traffic_tool.mode)
	_parallel_card.set_pressed_no_signal(road_tool.parallel)
	_exact_card.set_pressed_no_signal(road_tool.grid_exact)
	(_exact_card.get_meta("title") as Label).text = "Exact" if road_tool.grid_exact else "Adaptive"
	_grid_sizes.visible = road_tool.mode == RoadTool.Mode.GRID and not _kinds_open and not in_traffic
	for i in _grid_size_cards.size():
		_grid_size_cards[i].set_pressed_no_signal(i == road_tool.grid_preset)
	_ring_sizes.visible = road_tool.mode == RoadTool.Mode.ROUNDABOUT and not _kinds_open and not in_traffic
	for i in _ring_size_cards.size():
		_ring_size_cards[i].set_pressed_no_signal(i == road_tool.roundabout_preset)
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
	# Only clickable while there's a problem to show.
	_warning_box.mouse_filter = Control.MOUSE_FILTER_STOP if short != "" else Control.MOUSE_FILTER_IGNORE
	_warning_box.tooltip_text = full + ". Click for the list, or click a lot or building to see what it lacks." if full != "" else ""


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
	# The guided first town says hello instead, the first time.
	tour._load_settings()
	advisor.hold_welcome = not tour.settings.finished
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
		town.close_panel()
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
		town.close_panel()
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
		town.close_panel()
		_help.visible = false
		_help_button.set_pressed_no_signal(false))


## The Town panel, docked where the bell's is, and the timelapse over it all.
func _build_town() -> void:
	_root.add_child(town)
	town.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	town.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var place := func():
		town.offset_right = 0
		town.offset_left = 0
		town.offset_top = _top_bar.size.y
	_top_bar.resized.connect(place)
	place.call_deferred()
	town.opened.connect(func():
		advisor.close_panel()
		permits.close_panel()
		region_panel.close_panel()
		_help.visible = false
		_help_button.set_pressed_no_signal(false))
	_root.add_child(timelapse)
	town.watch_timelapse.connect(func():
		town.close_panel()
		timelapse.open(sim))


# --- Help (from the top bar) -----------------------------------------------

func _build_help() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_help.add_child(col)
	col.add_child(UiStyle.label("CAMERA", 10, UiStyle.MUTED))
	for line in ["W A S D  move  (Shift: faster)", "Q / E  rotate", "T / G  tilt", "R / F or scroll  zoom",
			"Right drag  move the map", "Middle drag or Option + drag  rotate", "Home  back to your town"]:
		col.add_child(UiStyle.label(line, 12))
	col.add_child(UiStyle.label("TOOLS", 10, UiStyle.MUTED))
	for line in ["Shift + 1 to 0  open a menu (shown on each button)   V  views",
			"1 2 3 4  road, curve, grid, roundabout", "U upgrade   P parallel   B bulldoze   M move it",
			"[ ]  size   Page Up / Down  bridge or tunnel", "Grid: Enter builds the shape, Tab turns it",
			"5 6 7 8  homes, shops, industry, dezone   Tab  brush",
			"J  traffic view   Ctrl+Z  undo a move",
			"Right click  stop drawing", "Esc  stop drawing, then close everything"]:
		col.add_child(UiStyle.label(line, 12))
	col.add_child(UiStyle.label("GAME", 10, UiStyle.MUTED))
	for line in ["Space  pause", "Enter  chat (in a region)", "N  flag the sound you just heard"]:
		col.add_child(UiStyle.label(line, 12))
	col.add_child(UiStyle.label("CONTROLLER", 10, UiStyle.MUTED))
	for line in ["Left stick  cursor (push the edge to move)", "Right stick  turn and tilt   LT / RT  zoom",
			"A  use   X  cancel   B  back   Y  tool wheel, then its tools",
			"LB / RB  size or turn   D-pad  height, speed; steps between buttons over a menu",
			"Click right stick  finish a shape, or go home", "Menu  pause menu   View  pause   View + X  undo"]:
		col.add_child(UiStyle.label(line, 12))
	var guide := Button.new()
	guide.text = "Guided tour (first town)"
	guide.focus_mode = Control.FOCUS_NONE
	guide.pressed.connect(func(): tour.start())
	col.add_child(guide)
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
