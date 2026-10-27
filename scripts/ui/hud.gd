class_name Hud
extends CanvasLayer
## The game's interface: two slim bars docked to the screen edges.
## - top bar: city stats, demand, money; date, game speed, Display (look,
##   music, interface size) and the panels on the right. It always fits:
##   the stats shorten, then clip, before a right-hand button goes missing
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
var _zone_mode_cards := []  # ZoneTool.Mode -> Button
var _brush_size: HBoxContainer   # the brush size meter (brush tool only)
var _brush_slider: HSlider
var _brush_label: Label
var _smart_opts: VBoxContainer  # smart paint: zones to use and how much to plan
var _smart_kind_chips := {}     # ZoneMap.Zone -> Button
var _smart_scope_chips := []    # SmartZoning.Scope -> Button
var _smart_panel := PanelContainer.new()  # a smart plan waiting for approval
var _smart_text := UiStyle.label("", 14)
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
var _parking_row: Control  # the lot kinds, over the tools while placing one
var _parking_card: Button
var _angled_card: Button
var _parking_last: int = Services.Kind.PARKING_SMALL
## Road height: Bridge, Ground (or the height) and Tunnel, top to bottom.
var _elevation_segs: Array[Button] = []
var _snap_segs := {}  # "roads" or "guides" -> its switch
var _speed_buttons := []
var _clock := UiStyle.label("", 14)
var _hint := UiStyle.label("", 13)
var _hint_action := UiStyle.label("", 14, UiStyle.TEXT, 700)
var _hint_panel := PanelContainer.new()
var _hint_text := ""
## The placement hint's widest, and the most it says before the tooltip.
const HINT_WIDTH := 640.0
const HINT_CHARS := 100
var _pop := UiStyle.label("0", 14)
var _jobs := UiStyle.label("", 13, UiStyle.MUTED)
var _cars := UiStyle.label("", 13, UiStyle.MUTED)
var _demand_bars := {}
var _money := UiStyle.label("", 14)
var _net := UiStyle.label("", 12, GOOD, 600)
var _net_chip := PanelContainer.new()
var _warning_box: PanelContainer
## The top bar's stats, in a box that clips rather than push the right-hand
## buttons off the screen; _compact drops their second halves for room.
var _stats_clip: Container
var _stats_row: HBoxContainer
var _compact := false
var _full_need := 0.0
## Each top bar readout's box, by its panel's key, so a stat's panel opens
## under the stat clicked (Duolingo's counters do the same).
var _stat_boxes := {}
## Display: day and night, seasons, weather, music and the interface size.
var _display_button: Button
var _display_panel := PanelContainer.new()
var _display_switches: Array[CheckButton] = []
var _size_chips: Array[Button] = []
## The Economy page (the bottom bar's Economy button) is open.
var _budget_open := false
var economy_page := EconomyPage.new()
var _help := PanelContainer.new()
var _help_keys := VBoxContainer.new()
var _top_bar: PanelContainer
var _town_button: Button  # top bar buttons from elsewhere go just before it
var _views_panel := PanelContainer.new()
var _views_button: Button
var _view_cards := {}  # view key -> Button
var _view := ""
var _help_button: Button
const CLEAR_TEXT := "Start over (clear the map)"
var _clear_button := Button.new()
var _clear_armed := false
var advisor := AdvisorPanel.new()
var permits := PermitPanel.new()
## The region's shared projects and services (only in a region).
var region_panel := RegionPanel.new()
## The town's nickname, history, districts and markers, and its timelapse.
var town := TownPanel.new()
## The celebration when the town reaches a charter step.
var level_up := LevelUpCard.new()
var timelapse := TimelapseView.new()
## What's behind each top bar readout: a chart and its numbers.
var stats_panel := StatsPanel.new()
## The guided first town (FirstTown): plan, streets, power, water, homes.
var tour := FirstTownTour.new()
## Back to your town centre, or to a neighbor's.
var jump: TownJump
var _towns_panel := PanelContainer.new()
var music := MusicPlayer.new()
var _towns_list := VBoxContainer.new()
var _towns_button: Button
## The cards the pad wheel's second ring offers ("tool:<n>" picks one).
var _wheel_tools: Array[Button] = []
## Every card in every drawer: [Button, category], for search and recents.
var _all_cards: Array = []
var _wheel_groups: Array = []  # pad wheel groups, for "group:N" keys
## The last tools picked, newest first (Anno's and Frostpunk's quick row).
var _recent: Array[Button] = []
const RECENT_MAX := 5
var _quick := VBoxContainer.new()  # search, then the recent tools, bottom left
var _search_panel := PanelContainer.new()
var _search := LineEdit.new()
var _results := VBoxContainer.new()
## A building's name (and problem) when the cursor rests on it.
var hover := HoverCard.new()
var pie := PieMenu.new()
## Each menu's pie, slot by slot from straight up, clockwise (N NE E SE S SW W
## NW). A name is that menu's card ("Homes#2" for the second "Homes"); [label,
## name] relabels one; [label, icon, [names]] is a group with its own pie.
## Menus not listed lay out their cards on their own (PieMenu.auto_slots).
const PIES := {
	"roads": ["Straight", "Grid", "Curve", "Roundabout", "Upgrade", "Parking", "Traffic",
		["Road types", "street", ["Street", "Avenue", "Boulevard", "Highway", "Ramp"]]],
	"zones": ["Homes", ["Plan homes", "Homes#2"], "Shops", ["Plan shops", "Shops#2"], "Industry",
		["Plan farms", "Farms"], "Dezone", ["Plan jobs", "Jobs"]],
	"industry": ["Corn", "Soybeans", "Oil", "Mining", "Forestry", "Warehouse", "Reserve",
		["Factories", "factory", ["Ethanol", "Meatpacker", "Furniture", "RV plant"]]],
	"utilities": ["Power co.", "Power line", "Substation", "Phone co.", "Water utility", "Water tower", "Well",
		["Trash", "landfill", ["Landfill", "Recycling"]]],
	"parks": ["Pocket", "Neighborhood", "Community", "Park", "Trails", "Fairgrounds", "Football",
		["Landmarks", "water_tower", ["Water tower", "Elevator"]]],
}


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
	_build_display()
	_build_advisor()
	_build_permits()
	_build_region_panel()
	_build_town()
	_info_panel.setup(sim, select_tool)
	_root.add_child(_info_panel)
	_build_economy()
	_build_stats()
	_build_quick()
	hover.setup(sim, info_view.cam, select_tool, anything_open)
	_root.add_child(hover)
	pie.chosen.connect(press_card)
	_root.add_child(pie)
	tour.setup(sim, self, info_view.cam, game)
	_root.add_child(tour)
	level_up.setup(sim, town._town_name("Your town"))
	_root.add_child(level_up)
	sim.charter.step_reached.connect(func(id: String):
		level_up.town_name = town._town_name("Your town")
		level_up.celebrate(id)
		_sync())

	road_tool.mode_changed.connect(func(_m): _sync())
	road_tool.options_changed.connect(_sync)
	zone_tool.zone_changed.connect(func(_z): _sync())
	zone_tool.mode_changed.connect(func(_m): _sync())
	_build_smart_panel()
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


func _input(event: InputEvent) -> void:
	# Escape while typing in the search box closes it.
	if _search.has_focus() and event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_open_search(false)
		(_quick.get_child(0) as Button).set_pressed_no_signal(false)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and KeyBinds.matches(k, "home"):
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
		var p := KeyBinds.action(k, KeyBinds.PIES)
		if p != "" and not k.shift_pressed:
			open_pie(hotkey_categories()[KeyBinds.PIES.find(p)], k.keycode)
			get_viewport().set_input_as_handled()
			return
		if KeyBinds.matches(k, "search") and not k.shift_pressed:
			var find := _quick.get_child(0) as Button
			find.button_pressed = not find.button_pressed
			get_viewport().set_input_as_handled()
			return
		if KeyBinds.matches(k, "views") and not k.shift_pressed:
			_views_button.button_pressed = not _views_button.button_pressed
			get_viewport().set_input_as_handled()
			return
		if KeyBinds.matches(k, "help") or k.keycode == KEY_SLASH and k.shift_pressed:
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


# --- Search and recent tools (bottom left, above the bar) --------------------

func _build_quick() -> void:
	for cat in _drawers:
		var found := []
		_cards_in(_drawers[cat], found)
		for b in found:
			_all_cards.append([b, cat])
			b.pressed.connect(_remember.bind(b))
	# The Views come up in search too ("smoke", "noise", "traffic").
	for k in _view_cards:
		_all_cards.append([_view_cards[k], "views"])
	_quick.add_theme_constant_override("separation", 2)
	_quick.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_quick)
	var find := _icon_button("search", 22, "Find a building or tool  (/)")
	find.toggle_mode = true
	find.toggled.connect(_open_search)
	_quick.add_child(find)
	_search_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_search_panel.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_search_panel.add_child(col)
	_search.placeholder_text = "Find: school, park, well..."
	_search.custom_minimum_size = Vector2(220, 0)
	_search.text_changed.connect(_find)
	_search.text_submitted.connect(func(_t): _pick_result(0))
	col.add_child(_search)
	col.add_child(_results)
	_root.add_child(_search_panel)


func _cards_in(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and c.has_meta("title"):
			out.append(c)
		elif c is Control:
			_cards_in(c, out)


func _open_search(on: bool) -> void:
	_search_panel.visible = on
	if on:
		_search.clear()
		_find("")
		_search.grab_focus()
	else:
		_search.release_focus()


## The cards whose name or tooltip has every word typed, best first.
func search_cards(text: String) -> Array[Button]:
	var out: Array[Button] = []
	var phrase := text.to_lower().strip_edges()
	var words := phrase.split(" ", false)
	if words.is_empty():
		return out
	# Best first: the name itself, a name that starts with it, the whole
	# phrase in the name or tip ("traffic light" finds Lights), every word.
	var ranks: Array = [[], [], [], []]
	for entry in _all_cards:
		var b: Button = entry[0]
		var title := card_title(b).to_lower()
		var hay := title + " " + b.tooltip_text.to_lower() + " " + menu_title(entry[1]).to_lower()
		if not Array(words).all(func(w): return w in hay):
			continue
		var r := 3
		if title == phrase:
			r = 0
		elif title.begins_with(phrase):
			r = 1
		elif phrase in title + " " + b.tooltip_text.to_lower():
			r = 2
		if not b in ranks[r]:
			ranks[r].append(b)
	for r in ranks:
		out.append_array(r)
	return out


## A card's name (drawer cards and View buttons alike).
static func card_title(b: Button) -> String:
	if b.has_meta("title"):
		return (b.get_meta("title") as Label).text
	return b.text.strip_edges()


## The menu a card sits in, as the bottom bar names it.
static func menu_title(cat: String) -> String:
	if cat == "views":
		return "Views"
	for c in CATEGORIES:
		if c[0] == cat:
			return c[1]
	return ""


func _menu_of(b: Button) -> String:
	for entry in _all_cards:
		if entry[0] == b:
			return entry[1]
	return ""


func _find(text: String) -> void:
	for c in _results.get_children():
		c.queue_free()
	var hits := search_cards(text)
	for i in mini(hits.size(), 8):
		var b := hits[i]
		var r := Button.new()
		# The menu it's in, so two cards with one name can be told apart.
		r.text = "%s   ·  %s" % [card_title(b), menu_title(_menu_of(b))]
		r.alignment = HORIZONTAL_ALIGNMENT_LEFT
		r.focus_mode = Control.FOCUS_NONE
		r.pressed.connect(_pick_result.bind(i))
		_results.add_child(r)


func _pick_result(i: int) -> void:
	var hits := search_cards(_search.text)
	if i < hits.size():
		press_card(hits[i])
	_open_search(false)
	(_quick.get_child(0) as Button).set_pressed_no_signal(false)


## Picks a card from anywhere (search, recents): opens its menu, then the tool.
func press_card(b: Button) -> void:
	var cat := _menu_of(b)
	if cat == "views":
		_views_button.button_pressed = true
		if not b.button_pressed:
			b.pressed.emit()
		return
	if cat != "" and cat != _category:
		_open(cat)
	b.pressed.emit()
	_sync()


func _remember(b: Button) -> void:
	_recent.erase(b)
	_recent.push_front(b)
	if _recent.size() > RECENT_MAX:
		_recent.pop_back()
	# Newest at the bottom, nearest the bar; the search button stays on top.
	for i in range(_quick.get_child_count() - 1, 0, -1):
		_quick.get_child(i).queue_free()
	for r in _recent:
		var q := _icon_button((r.get_meta("icon") as Icon).kind, 22, (r.get_meta("title") as Label).text)
		q.pressed.connect(press_card.bind(r))
		_quick.add_child(q)
		_quick.move_child(q, 1)


## Takes back the last road or building placed in the last 30 seconds, with
## a full refund.
func undo_last() -> void:
	var e := sim.undo.last(sim)
	if e.is_empty() or Time.get_ticks_msec() - int(e.at_ms) > UndoLog.WINDOW_MS:
		_show_hint("Nothing to undo.")
		return
	sim.apply({"type": "undo"})
	var was := _hint_text
	var note := "Undone. $%s back." % _thousands(int(e.refund))
	_show_hint(note)
	get_tree().create_timer(3.0).timeout.connect(func(): if _hint_text == note: _show_hint(was))


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
	if i < 0:
		return ""
	var k := KeyBinds.text(KeyBinds.PIES[i])
	return ("hold %s for its pie, Shift+%d" % [k, (i + 1) % 10]) if KeyBinds.key(KeyBinds.PIES[i]) != KEY_NONE else "Shift+%d" % ((i + 1) % 10)


## Hold a number key: that menu's pie opens around the cursor. Economy has no
## tools, so its key just opens the page.
func open_pie(cat: String, key: Key) -> void:
	var items := pie_items(cat)
	if items.is_empty():
		pie.close()
		if cat != _category:
			_open(cat)
		return
	pie.open(menu_title(cat), items, get_viewport().get_mouse_position(), key)


## A menu's pie: its slots, each null or {title, icon, card} or {title, icon,
## group: [...]}. The same layout fills the controller wheel's second ring.
func pie_items(cat: String) -> Array:
	var cards: Array = []
	for e in _all_cards:
		if e[1] == cat:
			cards.append(e[0])
	if cards.is_empty():
		return []
	if not PIES.has(cat):
		return PieMenu.auto_slots(cards.map(_pie_item.bind("")))
	var out := []
	for spec in PIES[cat]:
		if spec is Array and spec.size() == 3:
			var group := []
			for n in spec[2]:
				var b := _named_card(cards, n)
				if b != null:
					group.append(_pie_item(b, ""))
			out.append({"title": spec[0], "icon": spec[1], "group": group} if not group.is_empty() else null)
		else:
			var b := _named_card(cards, spec[1] if spec is Array else spec)
			out.append(_pie_item(b, spec[0] if spec is Array else "") if b != null else null)
	return out


func _pie_item(b: Button, label: String) -> Dictionary:
	return {"title": label if label != "" else card_title(b), "icon": (b.get_meta("icon") as Icon).kind, "card": b}


## "Homes#2" is the second card named Homes.
static func _named_card(cards: Array, n: String) -> Button:
	var parts := n.split("#")
	var want := int(parts[1]) if parts.size() > 1 else 1
	for b in cards:
		if card_title(b) == parts[0]:
			want -= 1
			if want == 0:
				return b
	return null


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
	if key.begins_with("group:"):
		var g: Dictionary = _wheel_groups[int(key.substr(6))]
		return _pad_slots(PieMenu.auto_slots(g.group))
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
	if not _drawers.has(cat) or _category != cat:
		_wheel_tools.clear()
		return []
	return _pad_slots(pie_items(cat))


## Pie slots as wheel items, empty slots kept so every tool sits where the
## keyboard's pie puts it.
func _pad_slots(slots: Array) -> Array:
	_wheel_tools.clear()
	_wheel_groups.clear()
	var items := []
	for it in slots:
		if it == null:
			items.append(null)
		elif it.has("group"):
			_wheel_groups.append(it)
			items.append([it.icon, it.title + " ›", "group:%d" % (_wheel_groups.size() - 1)])
		else:
			_wheel_tools.append(it.card)
			items.append([it.icon, it.title, "tool:%d" % (_wheel_tools.size() - 1)])
	return items


## Which second-ring slot starts lit: the tool already in hand.
func pad_tool_selected(items: Array = []) -> int:
	for i in items.size():
		if items[i] == null or not (items[i][2] as String).begins_with("tool:"):
			continue
		var b: Button = _wheel_tools[int((items[i][2] as String).substr(5))]
		if is_instance_valid(b) and b.button_pressed:
			return i
	for i in items.size():
		if items[i] != null:
			return i
	return 0


## A grid shape or an outline is being drawn, so Enter finishes it (the
## pad's right stick click does the same).
func shape_open() -> bool:
	return road_tool.mode == RoadTool.Mode.GRID and road_tool.is_drawing() or farm_tool.is_drawing() \
		or zone_tool.is_waiting()


## A fresh Enter press (either Enter key).
static func is_enter(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]


## True while a text box has the keys, so Enter belongs to it.
static func typing(vp: Viewport) -> bool:
	var f := vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## How tall the bottom dock is, so the pad's prompts sit just above it.
func pad_bottom_height() -> float:
	return _bottom.size.y


## True while a tool is in hand, a panel or view is open, or something is selected.
func anything_open() -> bool:
	return _budget_open or _view != "" or _views_panel.visible or _display_panel.visible or _help.visible or _search_panel.visible or advisor.visible or permits.visible or region_panel.visible \
		or town.visible or timelapse.visible or stats_panel.visible or _towns_panel.visible or music.visible \
		or not select_tool.selection.is_empty() or road_tool.mode != RoadTool.Mode.NONE \
		or zone_tool.zone != ZoneTool.OFF or service_tool.kind != ServiceTool.OFF \
		or farm_tool.mode != FarmTool.Mode.NONE or traffic_tool.mode != TrafficTool.Mode.NONE \
		or industry_tool.kind != "" or warehouse_tool.kind != "" or park_tool.kind != "" or campus_tool.kind != "" or bank_tool.kind != "" or telecom_tool.kind != "" or move_tool.active \
		or neighborhood_tool.kind != "" or big_tool.kind != ""


## Puts every tool away and closes every panel.
func close_all() -> void:
	_budget_open = false
	pie.close()
	_open_search(false)
	(_quick.get_child(0) as Button).set_pressed_no_signal(false)
	_show_view("")
	_views_panel.visible = false
	_views_button.set_pressed_no_signal(false)
	_show_display(false)
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
	music.close_panel()
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
	var top := _top_bar.size.y
	# The info panel sits beside the Views column or Economy page when open,
	# and never taller than the room between the bars.
	var left := _views_panel.size.x if _views_panel.visible else 0.0
	if economy_page.visible:
		left = economy_page.size.x
	_info_panel.position = Vector2(left, top)
	_info_panel.max_height = _root.size.y - top - _bottom.size.y - 16.0
	var edge := left + (_info_panel.size.x if _info_panel.visible else 0.0)
	# A stat's panel opens under the stat clicked, kept on the screen and
	# clear of the panels docked on the left.
	if stats_panel.visible:
		var box: Control = _stat_boxes.get(stats_panel.key)
		var x: float = box.global_position.x if box != null and box.is_visible_in_tree() else edge
		stats_panel.position = Vector2(clampf(x, edge, maxf(edge, _root.size.x - stats_panel.size.x)), top)
		edge = maxf(edge, stats_panel.position.x + stats_panel.size.x) if stats_panel.position.x <= edge + 1.0 else edge
	if _display_panel.visible:
		_display_panel.reset_size()
		_display_panel.position = Vector2(clampf(_display_button.global_position.x + _display_button.size.x - _display_panel.size.x,
			0.0, _root.size.x - _display_panel.size.x), top)
	# Search and recent tools sit just above the bottom dock, right of any
	# panel docked on the left (they sat on top of the Economy page and the
	# info panel: the critic, 2026-10-26).
	_quick.reset_size()
	_quick.position = Vector2(edge + 6, _root.size.y - _bottom.size.y - _quick.size.y - 6)
	if _search_panel.visible:
		_search_panel.reset_size()
		_search_panel.position = Vector2(_quick.position.x + _quick.size.x + 6, _root.size.y - _bottom.size.y - _search_panel.size.y - 6)
	# Room for the stats: drop their second halves when they'd clip, and
	# bring them back once the bar is wide enough again.
	var need := _stats_row.get_combined_minimum_size().x
	if not _compact and _stats_clip.size.x > 0.0 and need > _stats_clip.size.x + 0.5:
		_full_need = need
		_set_compact(true)
	elif _compact and _stats_clip.size.x >= _full_need:
		_set_compact(false)
	var t := sim.clock()
	# The weekday, month and year, no time of day (Nathan 2026-10-26): the
	# sky shows the time, one day and night a month (Seasons, SkyClock).
	# Calendar years, matching the "since" on business signs.
	_clock.text = "%s · %s %d" % [["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][Seasons.weekday(sim.calendar_tick())],
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][t.month - 1],
		Families.calendar(t.year)]
	_money.text = "$" + _thousands(sim.economy.money)
	_money.add_theme_color_override("font_color", UiStyle.TEXT if sim.economy.money >= 0 else BAD)
	_cars.text = str(sim.traffic.cars.size()) if _compact else \
		"%d  ·  %d%% flow" % [sim.traffic.cars.size(), roundi(sim.traffic.flow * 100.0)]


## Short stats for a narrow bar (or full ones again): jobs without the
## unemployment, cars without the flow, no monthly net, the problem count only.
func _set_compact(on: bool) -> void:
	_compact = on
	_update_stats()


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

	# The bar never runs off the screen (the critic, 2026-10-26: at 1280 px
	# everything right of the music button was gone). The stats sit in a box
	# that may shrink and clip; the date, speed and panel buttons on the
	# right always show. When the stats run short of room they drop their
	# second halves (Hud._compact), which stay in their tooltips and panels.
	_views_button = _icon_button("views", 24, "Views: see the map by fertility, oil, ore, forest, services, traffic and pollution  (V)")
	_views_button.toggled.connect(func(on): _views_panel.visible = on)
	row.add_child(_views_button)
	# Home: back to your town centre (Home key); the arrow lists every town.
	jump = TownJump.new(sim, info_view.cam)
	var home := _icon_button("locate", 24, "Back to your town centre  (Home)")
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
	_stats_clip = _ClipRow.new()
	_stats_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_clip)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_clip.add_child(stats)
	_stats_row = stats
	_stat(stats, "people", _pop, "Population: click for its chart and where people live", "population")
	_stat(stats, "jobs", _jobs, "Jobs and unemployment: click for the chart and where people work", "jobs")
	_stat(stats, "car", _cars, "Cars on the road and how freely traffic flows: click for the chart and the slowest roads", "traffic")
	stats.add_child(VSeparator.new())
	# Demand: a small upright meter per zone with its own glyph (the critic:
	# H, S and I bars 7 px tall read as "off" when empty). A faint track
	# keeps an empty meter reading as "low", not missing.
	var demand_row := HBoxContainer.new()
	demand_row.add_theme_constant_override("separation", 6)
	demand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_clickable(demand_row, "Demand for homes, shops and industry: click for the chart and why", "demand"))
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "homes"], [ZoneMap.Zone.COMMERCIAL, "shops"], [ZoneMap.Zone.INDUSTRIAL, "industry"]]:
		var z: int = entry[0]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 2)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		demand_row.add_child(pair)
		var glyph := Icon.new(entry[1], 14)
		glyph.color = ZoneMap.COLORS[z]
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(glyph)
		var bar_z := ProgressBar.new()
		bar_z.show_percentage = false
		bar_z.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar_z.custom_minimum_size = Vector2(10, 22)
		bar_z.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_z.max_value = 1.0
		var track := StyleBoxFlat.new()
		track.bg_color = Color(ZoneMap.COLORS[z], 0.08)
		track.border_color = Color(ZoneMap.COLORS[z], 0.45)
		track.set_border_width_all(1)
		track.set_corner_radius_all(3)
		bar_z.add_theme_stylebox_override("background", track)
		var fill := StyleBoxFlat.new()
		fill.bg_color = ZoneMap.COLORS[z]
		fill.set_corner_radius_all(3)
		bar_z.add_theme_stylebox_override("fill", fill)
		bar_z.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(bar_z)
		_demand_bars[z] = bar_z
	stats.add_child(VSeparator.new())
	var money_row := _stat(stats, "money", _money, "City funds: click for the chart and today's money in and out", "money")
	# The month's net as a small green or red chip beside the money (Whop's
	# stat cards), in thousands: "+$366K/mo".
	_net_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_chip.add_child(_net)
	money_row.add_child(_net_chip)
	# Problems: a count ("⚠ 3") and, with room, what they are; nothing at all
	# when there are none. The whole story is in its tooltip and panel.
	_warning.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_box = _clickable(_warning, "", "problems")
	stats.add_child(_warning_box)

	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clickable(_clock, "The date: click for the town's years", "date"))
	# Pause and play: one play speed, so the sky's hour can't be skipped.
	for i in 2:
		var b := _icon_button(["pause", "play"][i], 24, ["Pause (Space)", "Play"][i])
		b.pressed.connect(func(): game.set_speed(i))
		row.add_child(b)
		_speed_buttons.append(b)
	row.add_child(VSeparator.new())
	# Display: how the town looks and sounds, in one menu of labeled switches
	# (komoot's "Map content"; Cities: Skylines 2 keeps these in settings).
	# It was four buttons here, and they pushed Help off a 1600 px screen.
	_display_button = _icon_button("daynight", 24, "Display: day and night, seasons, weather, music and interface size")
	_display_button.toggled.connect(_show_display)
	row.add_child(_display_button)
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
			_disarm_clear()
			_fill_help()
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
	_stat_boxes[key] = box
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
	_root.add_child(music)
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


## A labeled on/off switch, the one the Advice panel uses.
static func _switch(title: String, tip: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = title
	cb.tooltip_text = tip
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		cb.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return cb


## The Display menu, dropped under its top bar button: how the town looks
## (each player picks for themselves), the music, and the interface size.
func _build_display() -> void:
	var box := UiStyle.dock(true)
	box.border_width_left = 1
	box.border_width_right = 1
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 10
	_display_panel.add_theme_stylebox_override("panel", box)
	_display_panel.visible = false
	_root.add_child(_display_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_display_panel.add_child(col)
	col.add_child(UiStyle.label("DISPLAY", 11, UiStyle.MUTED))
	# The day/night cycle (off: always late morning), seasons (off: always
	# summer) and weather (off: always fair).
	DayNight.load_settings()
	for entry in [["Day and night", "One day and night each month, about an hour: a 50-minute day, then a 10-minute night (off: always late morning)", DayNight.set_cycle],
			["Seasons", "Spring, summer, fall colour and winter snow (off: always summer)", DayNight.set_seasons],
			["Weather", "Overcast days and rain, by Indiana's odds for the month (off: always fair)", DayNight.set_weather]]:
		var sw := _switch(entry[0], entry[1])
		sw.toggled.connect(entry[2])
		col.add_child(sw)
		_display_switches.append(sw)
	# The music player: the song playing, and a list to skip or pick one.
	var tunes := HBoxContainer.new()
	var words := UiStyle.label("Music", 13)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tunes.add_child(words)
	var tune := music.make_button()
	tune.toggled.connect(func(on):
		if on:
			var x := _display_button.global_position.x + _display_button.size.x - music.size.x
			_show_display(false)
			music.position = Vector2(clampf(x, 0.0, _root.size.x - music.size.x), _top_bar.size.y))
	tunes.add_child(tune)
	col.add_child(tunes)
	col.add_child(HSeparator.new())
	col.add_child(UiStyle.label("INTERFACE SIZE", 11, UiStyle.MUTED))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 2)
	col.add_child(sizes)
	for f in UiScale.SIZES:
		var c := _chip(UiScale.text(f), "Auto: larger on big or sharp screens, never smaller than 100%" if f == UiScale.AUTO
			else "Draw the interface at %s" % UiScale.text(f))
		c.custom_minimum_size.x = 44
		var pick: float = f
		c.pressed.connect(func():
			UiScale.set_choice(pick)
			_sync_display())
		sizes.add_child(c)
		_size_chips.append(c)


## Opens or closes the Display menu.
func _show_display(on: bool) -> void:
	_display_panel.visible = on
	if _display_button:
		_display_button.set_pressed_no_signal(on)
	if on:
		_sync_display()


func _sync_display() -> void:
	var now := [DayNight.cycle_on, DayNight.seasons_on, Weather.on]
	for i in _display_switches.size():
		_display_switches[i].set_pressed_no_signal(now[i])
	for i in _size_chips.size():
		_size_chips[i].set_pressed_no_signal(UiScale.SIZES[i] == UiScale.choice)
	_size_chips[0].text = "Auto" if UiScale.choice != UiScale.AUTO else "Auto · %d%%" % roundi(UiScale.current() * 100.0)


func _sync_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == game.speed)


# --- Hint under the top bar ------------------------------------------------

func _build_hint() -> void:
	_hint_panel.add_theme_stylebox_override("panel", UiStyle.panel(12))
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # for its tooltip
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(col)
	for l in [_hint_action, _hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	_root.add_child(_hint_panel)
	_hint_panel.visible = false


## A smart paint plan waiting: what it will do, Paint it or Cancel.
func _build_smart_panel() -> void:
	_smart_panel.add_theme_stylebox_override("panel", UiStyle.panel(12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_smart_panel.add_child(row)
	_smart_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_smart_text.custom_minimum_size = Vector2(420, 0)
	row.add_child(_smart_text)
	var go := Button.new()
	go.text = "Paint it  (Enter)"
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func(): zone_tool.approve_smart())
	row.add_child(go)
	var no := Button.new()
	no.text = "Cancel"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(func(): zone_tool.cancel_smart())
	row.add_child(no)
	_root.add_child(_smart_panel)
	_smart_panel.visible = false
	zone_tool.smart_plan_changed.connect(func(text: String):
		_smart_text.text = text
		_smart_panel.visible = text != ""
		_smart_panel.reset_size()
		_pin(_smart_panel, Control.PRESET_CENTER_TOP, Vector2(0, 96)))


## A small text toggle for a tool's options.
func _chip(title: String, tip: String) -> Button:
	var c := Button.new()
	c.toggle_mode = true
	c.focus_mode = Control.FOCUS_NONE
	c.text = title
	c.tooltip_text = tip
	c.add_theme_font_size_override("font_size", 11)
	c.custom_minimum_size = Vector2(0, 22)
	return c


## The hint for the tool in hand: what to do now first, in bold (a tool's
## last line, like "Move next to a street or avenue."), then the hint's first
## sentence; the whole story is in its tooltip. A narrow card that wraps, at
## most HINT_WIDTH wide (the critic, 2026-10-26: the builder's yard hint was
## one line running off both sides of the screen; Deel's and Navattic's tips
## are narrow cards of a few short lines).
func _show_hint(text: String) -> void:
	_hint_text = text
	var lines := text.split("\n", false)
	var action := lines[-1] if lines.size() > 1 else ""
	var story := "\n".join(lines.slice(0, -1)) if lines.size() > 1 else text
	var short := story if story.length() <= HINT_CHARS else _first_sentence(story, HINT_CHARS)
	_hint_action.text = action
	_hint_action.visible = action != ""
	_hint.text = short
	_hint.visible = short != ""
	_hint_panel.tooltip_text = text if short != story else ""
	_hint_panel.visible = text != ""
	# Wrap at the card's width, but let a short hint stay snug.
	var room := minf(HINT_WIDTH, _root.size.x - 80.0)
	for l in [_hint_action, _hint]:
		var w := 0.0
		for line in (l as Label).text.split("\n"):
			w = maxf(w, l.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
				l.get_theme_font_size("font_size")).x)
		l.custom_minimum_size.x = minf(ceilf(w) + 2.0, room)
	_place_hint()
	# Again once the labels have their new width: a wrapping label's height
	# follows its width, and the card only grows on its own, never shrinks.
	_place_hint.call_deferred()


func _place_hint() -> void:
	_hint_panel.size = Vector2.ZERO
	_hint_panel.reset_size()
	_pin(_hint_panel, Control.PRESET_CENTER_TOP, Vector2(0, 44))


## The first sentence of `text`, cut at a word under `most` characters.
static func _first_sentence(text: String, most: int) -> String:
	var end := text.find(". ")
	var s := text.substr(0, end + 1) if end > 0 else text
	if s.length() <= most:
		return s
	var cut := s.substr(0, most).rfind(" ")
	return s.substr(0, cut if cut > 0 else most).rstrip(",;:") + "…"


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
	var b := _Pill.new()
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
	# (Measured from the font: a label outside the tree measures at the default size.)
	b.custom_minimum_size.x = maxf(64.0, ceilf(Brand.ui(500).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 20 + 5 + 22)
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
	# Parking: the lots and the garage, in the same one row of options.
	var park_row := HBoxContainer.new()
	park_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(park_row)
	var lots := _section(park_row, "Parking  ·  9 × 18 ft stalls, accessible stalls by the street")
	for k in Services.PARKING:
		var ks: Dictionary = Services.KINDS[k]
		var n: int = ParkingLots.layout(ks.size, false, k == Services.Kind.PARKING_GARAGE).spots.size()
		var short := {Services.Kind.PARKING_SMALL: "Small lot", Services.Kind.PARKING_DOWNTOWN: "Downtown",
			Services.Kind.PARKING_LARGE: "Large lot", Services.Kind.PARK_AND_RIDE: "Park & ride",
			Services.Kind.PARKING_GARAGE: "Garage"}
		var b := _card(ks.icon, short[k], "%d stalls" % n)
		b.tooltip_text = "%s: %d stalls, $%s to build, $%s a day" % [ks.name, n, CitySim.money_text(ks.cost),
			CitySim.money_text(ks.upkeep)]
		b.pressed.connect(func():
			_parking_last = k
			service_tool.set_kind(k))
		lots.add_child(b)
		_service_cards[k] = b
		_service_cat[k] = "roads"
	park_row.add_child(VSeparator.new())
	var stalls := _section(park_row, "Stalls")
	_angled_card = _card("parking", "60° angled", "")
	_angled_card.tooltip_text = "60° angled stalls on one-way aisles: easier to pull into, about a quarter fewer stalls. 90° stalls on two-way aisles hold the most. Lots too narrow for a pair of one-way aisles stay at 90°."
	_angled_card.pressed.connect(func(): service_tool.set_angled(not service_tool.angled))
	stalls.add_child(_angled_card)
	_parking_row = park_row

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
	row.add_theme_constant_override("separation", 6)
	stack.add_child(row)

	var tools := _section(row, "Draw")
	for entry in [
		[RoadTool.Mode.STRAIGHT, "road", "Straight", _key_hint("road")],
		[RoadTool.Mode.CURVED, "curve", "Curve", _key_hint("curve")],
		[RoadTool.Mode.GRID, "grid", "Grid", _key_hint("grid")],
		[RoadTool.Mode.ROUNDABOUT, "roundabout", "Roundabout", _key_hint("roundabout")],
		[RoadTool.Mode.UPGRADE, "upgrade", "Upgrade", "U"],
	]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], entry[3])
		b.pressed.connect(func():
			_kinds_open = false
			# Curve again: an S-curve (and back). One card for both keeps
			# the Roads menu in its 1000 px (tests/test_build_menus.gd).
			if m == RoadTool.Mode.CURVED and road_tool.mode == RoadTool.Mode.CURVED:
				road_tool.set_mode(RoadTool.Mode.SCURVE)
			else:
				road_tool.set_mode(m))
		tools.add_child(b)
		_tool_cards[m] = b
	_tool_cards[RoadTool.Mode.CURVED].tooltip_text = "Curve; click again for an S-curve, which bends one way and back"

	var types := _section(row, "Road type  ·  click one for its kinds")
	for g in RoadStyle.GROUPS:
		var spec: Dictionary = RoadStyle.TYPES[g]
		var b := _card(spec.name.to_lower(), spec.name, "%d kinds" % RoadStyle.variants(g).size())
		b.pressed.connect(func():
			# One row above the tools at a time: the kinds open over the grid sizes.
			_kinds_open = not (_kinds_open and RoadStyle.group(road_tool.road_type) == g)
			_pick_road(_variant_of.get(g, g)))
		types.add_child(b)
		_type_cards[g] = b

	var opts := _section(row, "Options")
	# Height: a three-way pill, Bridge over Ground over Tunnel, in one card's
	# space (it was a word between two arrows, which looked broken). Bridge
	# and Tunnel step up or down; the middle shows the height and resets it.
	var elev := VBoxContainer.new()
	elev.add_theme_constant_override("separation", 1)
	elev.custom_minimum_size = Vector2(60, 50)
	opts.add_child(elev)
	for entry in [["Bridge", 1, "Raise it: a bridge, a step higher each click  (Page Up)"],
			["Ground", 0, "Back down to the ground"],
			["Tunnel", -1, "Lower it: a tunnel, a step deeper each click  (Page Down)"]]:
		var seg := _segment(60)
		seg.text = entry[0]
		seg.tooltip_text = entry[2]
		var dir: int = entry[1]
		seg.pressed.connect(func():
			road_tool.change_elevation(dir if dir != 0 else -roundi(road_tool.elevation / RoadTool.ELEVATION_STEP)))
		elev.add_child(seg)
		_elevation_segs.append(seg)

	# Parallel and the snap switches (CS2's snapping options), three pills
	# in one card's space like the height ones, so the Roads menu keeps to
	# its 1000 px (tests/test_build_menus.gd).
	var snap := VBoxContainer.new()
	snap.add_theme_constant_override("separation", 1)
	snap.custom_minimum_size = Vector2(60, 50)
	opts.add_child(snap)
	_parallel_card = _segment(60)
	_parallel_card.text = "Parallel"
	_parallel_card.tooltip_text = "Parallel: a second road alongside, [ ] set the gap  (P)"
	_parallel_card.toggled.connect(func(on: bool): road_tool.set_parallel(on))
	snap.add_child(_parallel_card)
	for entry in [["roads", "Snap roads", "Snap onto roads and junctions. Off: points go just where you click"],
			["guides", "Guides", "Guide lines, right angles and straight on. Off: draw at any angle"]]:
		var seg := _segment(60)
		seg.text = entry[1]
		seg.tooltip_text = entry[2]
		var kind: String = entry[0]
		seg.toggled.connect(func(on: bool): road_tool.set_snap(kind, on))
		snap.add_child(seg)
		_snap_segs[kind] = seg

	var traffic := _section(row, "Town tools  ·  traffic, parking and new neighborhoods")
	_traffic_card = _card("traffic", "Traffic", "")
	_traffic_card.tooltip_text = "Traffic flow, lights and stop signs  (J)"
	_traffic_card.pressed.connect(func():
		if traffic_tool.mode == TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.VIEW)
		else:
			road_tool.set_mode(road_tool.last_draw))
	traffic.add_child(_traffic_card)
	_parking_card = _card("parking", "Parking", "")
	_parking_card.tooltip_text = "Parking lots and a garage for the town: drivers who can't park at their own stop walk from the nearest one"
	_parking_card.pressed.connect(func():
		if service_tool.kind in Services.PARKING:
			road_tool.set_mode(road_tool.last_draw)
		else:
			service_tool.set_kind(_parking_last))
	traffic.add_child(_parking_card)

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
	var zones := _section(row, "Zones  ·  street sides; Shift zones both sides")
	for entry in [
		[ZoneMap.Zone.RESIDENTIAL, "homes", "Homes", _key_hint("homes")],
		[ZoneMap.Zone.COMMERCIAL, "shops", "Shops", _key_hint("shops")],
		[ZoneMap.Zone.INDUSTRIAL, "industry", "Industry", _key_hint("industry")],
		[ZoneMap.Zone.NONE, "dezone", "Dezone", _key_hint("dezone")],
	]:
		var z: int = entry[0]
		var b := _card(entry[1], entry[2], entry[3])
		if z != ZoneMap.Zone.NONE:
			(b.get_meta("icon") as Icon).accent = ZoneMap.COLORS[z]
		b.pressed.connect(func():
			zone_tool.set_zone(z)
			if zone_tool.mode == ZoneTool.Mode.SMART:
				zone_tool.set_mode(ZoneTool.Mode.STREET))
		zones.add_child(b)
		_zone_cards[z] = b
	# How it paints (CS2's tool types), and the brush's size, in the same row.
	row.add_child(VSeparator.new())
	var how := _section(row, "Tool  ·  Tab")
	for entry in [
		[ZoneTool.Mode.STREET, "zone_street", "Street", "click a block face, or drag along a street for a stretch"],
		[ZoneTool.Mode.BRUSH, "zone_brush", "Brush", "a round brush for odd spots, sized with the meter or [ ]"],
		[ZoneTool.Mode.SMART, "zone_smart", "Smart", "plans a street or a neighborhood the way a town planner would, with the zones you tick, and paints it when you approve"],
	]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], entry[3])
		b.pressed.connect(func():
			if zone_tool.zone == ZoneTool.OFF:
				zone_tool.set_zone(ZoneMap.Zone.RESIDENTIAL)
			zone_tool.set_mode(m))
		how.add_child(b)
		_zone_mode_cards.append(b)
	_brush_size = HBoxContainer.new()
	_brush_size.add_theme_constant_override("separation", 4)
	var size_col := VBoxContainer.new()
	size_col.alignment = BoxContainer.ALIGNMENT_CENTER
	size_col.add_child(UiStyle.label("SIZE", 10, UiStyle.MUTED))
	_brush_slider = HSlider.new()
	_brush_slider.min_value = ZoneTool.MIN_RADIUS
	_brush_slider.max_value = ZoneTool.MAX_RADIUS
	_brush_slider.step = 1.0
	_brush_slider.custom_minimum_size = Vector2(110, 20)
	_brush_slider.focus_mode = Control.FOCUS_NONE
	_brush_slider.tooltip_text = "Brush size  ([ ] also work)"
	_brush_slider.value_changed.connect(func(v): zone_tool.set_radius(v))
	size_col.add_child(_brush_slider)
	_brush_label = UiStyle.label("", 11, UiStyle.MUTED)
	_brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_col.add_child(_brush_label)
	_brush_size.add_child(size_col)
	how.add_child(_brush_size)
	# Smart paint's options in the same spot: the zones it may use, then how
	# much to plan (one street, a neighborhood, or a wider one).
	_smart_opts = VBoxContainer.new()
	_smart_opts.alignment = BoxContainer.ALIGNMENT_CENTER
	_smart_opts.add_theme_constant_override("separation", 3)
	var kinds_row := HBoxContainer.new()
	kinds_row.add_theme_constant_override("separation", 2)
	for entry in [[ZoneMap.Zone.RESIDENTIAL, "Homes"], [ZoneMap.Zone.COMMERCIAL, "Shops"], [ZoneMap.Zone.INDUSTRIAL, "Industry"]]:
		var z: int = entry[0]
		var c := _chip(entry[1], "Let smart paint use %s" % entry[1].to_lower())
		c.pressed.connect(func(): zone_tool.toggle_smart_kind(z))
		kinds_row.add_child(c)
		_smart_kind_chips[z] = c
	_smart_opts.add_child(kinds_row)
	var scope_row := HBoxContainer.new()
	scope_row.add_theme_constant_override("separation", 2)
	var scope_tips := ["Plan one street, straight on through its crossings",
		"Plan the neighborhood: streets about two blocks around, up to the busy roads",
		"Plan the wider neighborhood: about a quarter mile around (a neighborhood unit), up to the busy roads"]
	for i in SmartZoning.SCOPE_NAMES.size():
		var c := _chip(SmartZoning.SCOPE_NAMES[i], scope_tips[i])
		c.pressed.connect(func(): zone_tool.set_smart_scope(i))
		scope_row.add_child(c)
		_smart_scope_chips.append(c)
	_smart_opts.add_child(scope_row)
	how.add_child(_smart_opts)
	# The future land use map: big soft areas, not zoning (LandPlan).
	row.add_child(VSeparator.new())
	var plan := _section(row, "Land plan  ·  outline big areas for homes, shops, jobs or farms")
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
		Services.Kind.TAXI_COMPANY: "Taxis", Services.Kind.NURSING_HOME: "Nursing home", Services.Kind.BUS_DEPOT: "Bus depot",
		Services.Kind.BUILDER_YARD: "Builder", Services.Kind.TRAFFIC_CENTER: "Traffic center"}
	var b := _card(s.icon, short.get(k, s.name.split(" ")[0]), "")
	b.tooltip_text = "%s: $%s to build, $%s a day" % [s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)]
	if k == Services.Kind.BUS_DEPOT:
		b.tooltip_text = "%s: $%s to build, with two buses. It plans its own stops, routes and fare; you set its funding." % [s.name, CitySim.money_text(s.cost)]
	elif k == Services.Kind.BUILDER_YARD:
		b.tooltip_text = "%s: free. Its crews and concrete trucks build the houses; its owner buys more trucks as the town grows. One per town." % s.name
	elif k == Services.Kind.TRAFFIC_CENTER:
		b.tooltip_text = "%s: $%s to build, $%s a day. Its engineers count the cars at every light and retime them through the day by the traffic. Lights you time by hand stay yours. One per town." % [
			s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)]
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
	b.tooltip_text = "%s: $%s to build, $%s a day. Never fills up." % [title, CitySim.money_text(int(w.cost)),
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
	_power_card = _card("power_co", "Power co.", "")
	_power_card.tooltip_text = "Power company: $%s. Its leader picks solar, wind, gas, a dam or an old coal plant, and grows it" \
		% CitySim.money_text(Balance.POWER_YARD_COST)
	_power_card.pressed.connect(func(): industry_tool.set_kind("power"))
	# The phone company: placed once, then it builds its own network.
	_telecom_card = _card("phone_co", "Phone co.", "")
	_telecom_card.tooltip_text = "Phone company: $%s to build, $%s a day grant. Its manager strings fiber and puts up cell towers where they pay off. One per town." % [
		CitySim.money_text(Balance.TELECOM_COST), CitySim.money_text(Balance.TELECOM_GRANT)]
	_telecom_card.pressed.connect(func(): telecom_tool.set_kind("telecom"))
	return _service_drawer(cat, [
		["Builder", [_service_card(Services.Kind.BUILDER_YARD, cat)]],
		["Power", [_service_card(Services.Kind.POWER_FEED, cat), _service_card(Services.Kind.SUBSTATION, cat), _power_card]],
		["Water  ·  water and sewer", [_service_card(Services.Kind.WELL, cat), _service_card(Services.Kind.WATER_TOWER, cat),
			_service_card(Services.Kind.WATER_UTILITY, cat)]],
		["Trash", [_hub_card(100, cat), _hub_card(101, cat)]],
		["Phone  ·  phone and internet", [_telecom_card]]])


## Civic: fire and police (CS2's Fire & Rescue, Police & Administration),
## the post office and the banks.
func _civic_drawer() -> PanelContainer:
	var cat := "civic"
	# The post office: its postmaster plans the routes.
	var pb := _card("post_office", "Post office", "")
	pb.tooltip_text = "Post office: $%s to build, $%s a day. Its postmaster plans the routes." % [
		CitySim.money_text(Balance.MAIL_COST), CitySim.money_text(Balance.MAIL_UPKEEP)]
	pb.pressed.connect(func(): service_tool.set_kind(Mail.TOOL_KIND))
	_service_cards[Mail.TOOL_KIND] = pb
	_service_cat[Mail.TOOL_KIND] = cat
	# Banks lend to the farms, companies and builders (Brawn's hub model).
	var banks := []
	for k in ["community", "farm_credit"]:
		var b := _card(Banks.KINDS[k].icon, {"community": "Bank", "farm_credit": "Farm Credit"}[k], "")
		b.tooltip_text = "%s: $%s for the lot. Its %s lends to %s, and buys the land next door as it grows." % [
			Banks.KINDS[k].name, CitySim.money_text(int(Banks.spec(k).cost)), Banks.KINDS[k].head.to_lower(),
			{"community": "farms, companies and builders", "farm_credit": "farms and timber"}[k]]
		b.pressed.connect(func(): bank_tool.set_kind(k))
		_bank_cards[k] = b
		banks.append(b)
	# The county courthouse and its square (Brawn: a courthouse is civic).
	return _service_drawer(cat, [
		["Safety", [_service_card(Services.Kind.FIRE, cat), _service_card(Services.Kind.POLICE, cat)]],
		["Traffic", [_service_card(Services.Kind.TRAFFIC_CENTER, cat)]],
		["Government", [_park_card("courthouse")]],
		["Mail", [pb]],
		["Banks", banks]])


## Education, from daycare to the university (CS2's Education & Research).
## Campuses grow on their own once placed (Brawn's hub model).
func _education_drawer() -> PanelContainer:
	var cat := "education"
	var campus := []
	for k in ["high_school", "college", "university"]:
		var e: Dictionary = Education.spec(k)
		var b := _card(k, {"high_school": "High school", "college": "College", "university": "University"}[k], "")
		b.tooltip_text = "%s: $%s to build, $%s a day. Its %s buys the free land next to it as it fills." % [
			Education.KINDS[k].name, CitySim.money_text(e.cost), CitySim.money_text(e.funding), Education.KINDS[k].head.to_lower()]
		b.pressed.connect(func(): campus_tool.set_kind(k))
		_campus_cards[k] = b
		campus.append(b)
	return _service_drawer(cat, [
		["Schools", [_service_card(Services.Kind.SCHOOL, cat), _service_card(Services.Kind.DAYCARE, cat)]],
		["Colleges  ·  high school and college", campus]])


## Health and care, with the cemetery (CS2's Healthcare & Deathcare).
func _health_drawer() -> PanelContainer:
	var cat := "health"
	return _service_drawer(cat, [
		["Health  ·  health and care", [_service_card(Services.Kind.CLINIC, cat), _service_card(Services.Kind.HOSPITAL, cat),
			_service_card(Services.Kind.NURSING_HOME, cat)]],
		["Cemetery", [_hub_card(102, cat)]]])


## Transport: buses, cabs and the railroad (CS2's Transportation).
func _transport_drawer() -> PanelContainer:
	var cat := "transport"
	# The railroad: its leader plans the track and asks before building.
	var rb := _card("rail_depot", "Rail depot", "")
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	drawer.add_child(row)
	var parks := _section(row, "Park  ·  fills in and grows by itself")
	parks.add_child(_park_card("park"))
	# The park's size beside its card: a three-way pill, one to three trees
	# for Pocket, Neighborhood and Community (NRPA's park classes). It was a
	# second drawer stacked on the first, with the same tree for every size.
	_park_sizes = VBoxContainer.new()
	_park_sizes.add_theme_constant_override("separation", 1)
	parks.add_child(_park_sizes)
	for i in Balance.PARK_SIZES.size():
		var ps: Dictionary = Balance.PARK_SIZES[i]
		var b := _segment(128)
		b.tooltip_text = "%s park: %s acres, $%s. %s" % [ps.name, _acres_text(ps.size.x * ps.size.y / 4046.86),
			CitySim.money_text(int(ps.cost)), ps.about]
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 6
		b.add_child(inner)
		for t in i + 1:
			var tree := Icon.new("park", 12)
			tree.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			inner.add_child(tree)
			if t == 0:
				b.set_meta("icon", tree)  # the pie, search and recent tools show it
		var gap := Control.new()
		gap.custom_minimum_size.x = 4 + (2 - i) * 12
		inner.add_child(gap)
		var t := UiStyle.label(ps.name, 11)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(t)
		b.set_meta("title", t)
		b.pressed.connect(func():
			park_tool.set_kind("park")
			park_tool.set_size(i))
		_park_sizes.add_child(b)
		_park_size_cards.append(b)
	var marks := _section(row, "Landmarks  ·  one per town")
	for k in Parks.KINDS:
		if Parks.KINDS[k].get("auto", false) or k == "courthouse" or k == "park":
			continue
		(marks if Parks.KINDS[k].landmark else parks).add_child(_park_card(k))
	return drawer


## One part of a stacked segmented pill (park size, road height): a slim
## button a third of a card tall, `w` wide; selected shows as a filled pill.
static func _segment(w: float) -> Button:
	var seg := _Pill.new()
	seg.toggle_mode = true
	seg.focus_mode = Control.FOCUS_NONE
	seg.add_theme_font_size_override("font_size", 11)
	seg.custom_minimum_size = Vector2(w, 16)
	seg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for state in [["normal", Color(Brand.SURFACE_RAISED, 0.55)], ["hover", Brand.SURFACE_RAISED],
			["pressed", Brand.SURFACE_RAISED.lightened(0.12)], ["hover_pressed", Brand.SURFACE_RAISED.lightened(0.18)]]:
		var sb := UiStyle._box(state[1], 4)
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		seg.add_theme_stylebox_override(state[0], sb)
	return seg


## A card that places a Parks site (the courthouse's sits under Civic).
func _park_card(k: String) -> Button:
	var spec: Dictionary = Parks.KINDS[k]
	var a: Dictionary = Balance.AMENITIES[k]
	var short := {"park": "Park", "courthouse": "Courthouse", "water_tower": "Water tower",
		"grain_elevator": "Elevator", "football": "Football", "fairgrounds": "Fairgrounds", "trailhead": "Trails"}
	var tip := "%s: $%s" % [spec.name, CitySim.money_text(int(a.cost))]
	if spec.landmark:
		tip += ", $%s a day" % CitySim.money_text(int(a.upkeep))
	var b := _card(spec.icon, short[k], tip)
	b.tooltip_text = tip + ". Raises land value and happiness nearby."
	b.pressed.connect(func(): park_tool.set_kind(k))
	_park_cards[k] = b
	return b


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
	var farms := _section(row, "Farms  ·  a farmhouse, near green soil")
	for entry in [[FarmTool.Mode.CORN, "farm_corn", "Corn", "Corn farm: more income on rich soil"],
			[FarmTool.Mode.SOYBEANS, "farm_soy", "Soybeans", "Soybean farm: steadier on poorer soil"]]:
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
	var hq := _section(row, "Resources  ·  a company's main building, near the resource")
	var area := _section(row, "Save land")
	var stores := _section(row, "Storage")
	_warehouse_card = _card("warehouse_co", "Warehouse", "")
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
		var b := _card("warehouse_co", ["Small", "Medium", "Large", "Distrib."][Warehouses.ORDER.find(k)], "")
		b.tooltip_text = "%s, %s ($%s): stores raw loads and goods until a factory or shop needs them" \
			% [Warehouses.KINDS[k].name, Warehouses.KINDS[k].area, CitySim.money_text(int(spec.cost))]
		b.pressed.connect(func(): warehouse_tool.set_kind(k))
		sizes.add_child(b)
		_warehouse_cards[k] = b
	for entry in [["oil", "oil_co", "Oil", "Oil company: pumpjacks spread over the oil field"],
			["ore", "mine_co", "Mining", "Mining company: pits open where the ore is"],
			["forest", "forestry_co", "Forestry", "Forestry company: logging stands in the woods"]]:
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
			[TrafficTool.Mode.SIGNAL, "signal", "Lights", "Traffic lights (signals)", junctions],
			[TrafficTool.Mode.ALL_STOP, "allstop", "All-way", "All-way stop: first to stop goes first", junctions],
			[TrafficTool.Mode.STOP, "stop", "Stop signs", "Stop signs on the smaller road only", junctions],
			[TrafficTool.Mode.NO_CONTROL, "nocontrol", "None", "No signs or lights", junctions],
			[TrafficTool.Mode.SMART, "signal", "Smart", "Smart lights: sensors hold the green while cars keep coming and skip a way with no one waiting", junctions],
			[TrafficTool.Mode.TIMING, "signal", "Timing", "How long each direction's green lasts at a light: click near a direction for 5 s more, Shift-click for 5 s less", junctions]]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[3]
		b.pressed.connect(func(): traffic_tool.set_mode(m))
		(entry[4] as HBoxContainer).add_child(b)
		_traffic_cards[m] = b
	# No-turn signs (CS2's turn rules): click a junction to put one up.
	var turns := _section(row, "Turns  ·  click a junction to ban a turn there, or a road at a junction for its crosswalk")
	for entry in [[TrafficTool.Mode.NO_LEFT, "noleft", "No left", "No left turns at a junction (click again to allow them)"],
			[TrafficTool.Mode.NO_RIGHT, "noright", "No right", "No right turns at a junction (click again to allow them)"],
			[TrafficTool.Mode.CROSSWALK, "nocrosswalk", "Crosswalk", "Take away a crosswalk: click a road where it meets a junction (click again to put it back)"]]:
		var m: int = entry[0]
		var b := _card(entry[1], entry[2], "")
		b.tooltip_text = entry[3]
		b.pressed.connect(func(): traffic_tool.set_mode(m))
		turns.add_child(b)
		_traffic_cards[m] = b
	# Street rules (CS2's pedestrian streets): click a town street to make
	# it car-free. Here with the junction rules, so the Roads menu keeps to
	# its 1000 px (tests/test_build_menus.gd).
	var rules := _section(row, "Streets  ·  click a town street")
	var car_free := _card("people", "Car-free", "")
	car_free.tooltip_text = "Close a town street to cars: a walking plaza where trucks still deliver at night. Click it again to open it."
	car_free.pressed.connect(func(): traffic_tool.set_mode(TrafficTool.Mode.CAR_FREE))
	rules.add_child(car_free)
	_traffic_cards[TrafficTool.Mode.CAR_FREE] = car_free


## A tool's own key for its tooltip, or "" when it has none (the pies reach it).
static func _key_hint(action: String) -> String:
	return KeyBinds.text(action) if KeyBinds.key(action) != KEY_NONE else ""


## A titled group of cards inside a drawer; returns the row to fill. Every
## drawer uses it, so they all look alike (the critic, 2026-10-26: Industry
## had no dividers and its headers floated over the wrong cards): a short
## mint heading, the cards, and a hairline between groups in a row. A title
## like "Grid size  ·  largest to smallest" shows its first part (two words
## at most, in a player's words) and keeps the rest for the tooltip.
func _section(parent: Container, title: String) -> HBoxContainer:
	if parent.get_child_count() > 0 and not parent.get_child(-1) is VSeparator:
		parent.add_child(VSeparator.new())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	parent.add_child(col)
	var parts := title.split("  ·  ")
	var head := UiStyle.label(parts[0].to_upper(), 11, Brand.BRAND_MINT)
	if parts.size() > 1:
		head.tooltip_text = parts[0] + ": " + "; ".join(parts.slice(1))
		head.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	col.add_child(row)
	return row


## A compact tool card: icon over a name. The key or detail is in the tooltip.
## The icon is 28 px (the critic: building icons at 20 to 24 px were mush);
## that makes the card taller, never wider, so the Roads menu keeps its width.
func _card(icon: String, title: String, detail: String, toggle := true) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ToolCard"
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 56)
	b.tooltip_text = "%s  (%s)" % [title, detail] if detail != "" else title
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var ic := Icon.new(icon, 28)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var t := UiStyle.label(title, 11)
	# A card's name stays at 11 px, under the 12 px floor, so the Roads
	# menu keeps to its 1000 px (tests/test_build_menus.gd); the interface
	# scale draws it larger on big screens.
	t.add_theme_font_size_override("font_size", 11)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	# Wide enough for its name ("Water utility" ran into its neighbour).
	# (Measured from the font: a label outside the tree doesn't know its size yet.)
	var w := Brand.ui(500).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	b.custom_minimum_size.x = maxf(58.0, ceilf(w) + 8.0)
	b.set_meta("icon", ic)
	b.set_meta("title", t)
	return b


## A top bar button: an icon at three quarters of `px` (18 px for 24) in a
## 34 x 30 button (the critic: 14 px icons in 30 x 24 buttons were hard to read).
func _icon_button(icon: String, px: int, tip: String) -> Button:
	var b := _Pill.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px + 10, px + 6)
	b.tooltip_text = tip
	var ic := Icon.new(icon, px * 0.75)
	ic.custom_minimum_size = Vector2.ZERO
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ic.offset_left = -px * 0.375
	ic.offset_top = -px * 0.375
	ic.offset_right = px * 0.375
	ic.offset_bottom = px * 0.375
	b.add_child(ic)
	return b


## A row that may be narrower than what's in it: it clips instead of
## pushing the rest of the top bar off the screen.
class _ClipRow extends Container:
	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var h := 0.0
		for c in get_children():
			if c is Control and c.visible:
				h = maxf(h, c.get_combined_minimum_size().y)
		return Vector2(0, h)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					fit_child_in_rect(c, Rect2(0, 0, maxf(c.get_combined_minimum_size().x, size.x), size.y))


## A button that's selected or switched on shows it with a soft filled
## pill and mint words and icon (UiStyle: coral is only the tool in hand).
class _Pill extends Button:
	func _draw() -> void:
		var c: Color = Brand.BRAND_MINT if button_pressed else Brand.INK
		for n in get_children(true):
			_tint(n, c)

	func _tint(n: Node, c: Color) -> void:
		if n is Icon:
			if (n as Icon).color != c:
				(n as Icon).color = c
		elif n is Label:
			if (n as Label).get_theme_color("font_color") != c:
				n.add_theme_color_override("font_color", c)
		for k in n.get_children():
			_tint(k, c)


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
			# The first tool the charter allows (buses wait for a city).
			var card: Button = _first_card[cat]
			var k = _service_cards.find_key(card)
			if k != null and sim.charter.locked(k) != "":
				for o in _service_cards:
					if _service_cat.get(o) == cat and sim.charter.locked(o) == "":
						card = _service_cards[o]
						break
			card.pressed.emit()
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
		_category = "civic" if park_tool.kind == "courthouse" else "parks"
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
	# The Curve card stands for the S-curve too, and says which it is.
	var s_curve := road_tool.mode == RoadTool.Mode.SCURVE
	var curve_card: Button = _tool_cards[RoadTool.Mode.CURVED]
	if s_curve:
		curve_card.set_pressed_no_signal(true)
	(curve_card.get_meta("icon") as Icon).kind = "scurve" if s_curve else "curve"
	(curve_card.get_meta("title") as Label).text = "S-curve" if s_curve else "Curve"
	var menu := RoadStyle.group(road_tool.road_type)
	_variant_of[menu] = road_tool.road_type
	var in_traffic := traffic_tool.mode != TrafficTool.Mode.NONE
	var placing_lot: bool = service_tool.kind in Services.PARKING
	for g in _type_cards:
		_type_cards[g].set_pressed_no_signal(g == menu and not in_traffic and not placing_lot)
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
		_zone_cards[z].set_pressed_no_signal(z == zone_tool.zone and zone_tool.mode != ZoneTool.Mode.SMART)
	for m in _zone_mode_cards.size():
		_zone_mode_cards[m].set_pressed_no_signal(zone_tool.zone != ZoneTool.OFF and m == zone_tool.mode)
	_brush_size.visible = zone_tool.brush
	_smart_opts.visible = zone_tool.zone != ZoneTool.OFF and zone_tool.mode == ZoneTool.Mode.SMART
	for z in _smart_kind_chips:
		_smart_kind_chips[z].set_pressed_no_signal(zone_tool.smart_kinds.get(z, false))
	for i in _smart_scope_chips.size():
		_smart_scope_chips[i].set_pressed_no_signal(i == zone_tool.smart_scope)
	_brush_slider.set_value_no_signal(zone_tool.radius)
	_brush_label.text = "%d ft across" % roundi(zone_tool.radius * 2.0 * 3.28084)
	for k in _plan_cards:
		_plan_cards[k].set_pressed_no_signal((farm_tool.mode == FarmTool.Mode.PLAN and k == farm_tool.plan_kind)
			or (farm_tool.mode == FarmTool.Mode.UNPLAN and k == ""))
	for k in _service_cards:
		_service_cards[k].set_pressed_no_signal(k == service_tool.kind)
		# Charter locks: the card stays, greyed, and says when it opens.
		var why := sim.charter.locked(k)
		var card: Button = _service_cards[k]
		if not card.has_meta("about"):
			card.set_meta("about", card.tooltip_text)
		card.disabled = why != ""
		card.tooltip_text = str(card.get_meta("about")) + ("\n" + why if why != "" else "")
		if why != "" and service_tool.kind == k:
			service_tool.set_kind(ServiceTool.OFF)
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
	var parking: bool = service_tool.kind in Services.PARKING
	_parking_row.visible = parking
	_parking_card.set_pressed_no_signal(parking)
	_angled_card.set_pressed_no_signal(service_tool.angled)
	(_angled_card.get_meta("title") as Label).text = "60° angled" if service_tool.angled else "90° stalls"
	if parking:
		_grid_sizes.visible = false
		_ring_sizes.visible = false
		_variant_row.get_parent().visible = false
	for i in _ring_size_cards.size():
		_ring_size_cards[i].set_pressed_no_signal(i == road_tool.roundabout_preset)
	var h := road_tool.elevation
	for i in _elevation_segs.size():
		_elevation_segs[i].set_pressed_no_signal([h > 0.0, h == 0.0, h < 0.0][i])
	_elevation_segs[1].text = "Ground" if h == 0.0 else "%+d ft" % roundi(h * RoadTool.FT)
	_snap_segs.roads.set_pressed_no_signal(road_tool.snap_roads)
	_snap_segs.guides.set_pressed_no_signal(road_tool.snap_guides)
	if _category == "" or _category == "budget":
		_show_hint("")


func _update_stats() -> void:
	var s := sim.stats
	var unemployed: float = 0.0 if s.workers == 0 else 100.0 * (s.workers - s.employed - int(s.get("commuting", 0))) / s.workers
	_pop.text = _thousands(s.population)
	_jobs.text = _thousands(s.jobs) if _compact else "%s  ·  %d%% unemployed" % [_thousands(s.jobs), roundi(unemployed)]
	for z in _demand_bars:
		_demand_bars[z].value = sim.demand[z]
	var e := sim.economy
	var net := e.monthly_net()
	_net.text = "%s$%s/day" % ["+" if net >= 0 else "–", short_money(absi(net))]
	var tone: Color = GOOD if net >= 0 else BAD
	_net.add_theme_color_override("font_color", tone)
	var chip := UiStyle._box(Color(tone, 0.16), 9)
	chip.content_margin_left = 7
	chip.content_margin_right = 7
	chip.content_margin_top = 1
	chip.content_margin_bottom = 1
	_net_chip.add_theme_stylebox_override("panel", chip)
	_net_chip.visible = not _compact
	_net_chip.tooltip_text = "Today: $%s in, less what the town spends" % _thousands(net)
	var unserved := sim.unserved_count()
	# A problem counter, like CS2's; the full story is in its tooltip.
	var short := sim.utility_summary()
	var full := sim.utility_problem()
	if unserved > 0:
		short = ("%s · %d leaving" % [short, unserved]) if short != "" else "%d buildings losing people" % unserved
		full = ("%s. People are leaving %d buildings" % [full, unserved]) if full != "" else \
			"%d buildings without power or water: people are leaving" % unserved
	var count := short.split(" · ").size() if short != "" else 0
	_warning.text = "" if count == 0 else ("⚠ %d" % count if _compact else "⚠ %d  %s" % [count, short])
	_warning_box.visible = count > 0
	_warning_box.tooltip_text = full + ". Click for the list, or click a lot or building to see what it lacks." if full != "" else ""


## Money in thousands or millions for a chip: 950 -> "950", 1,428 -> "1.4K",
## 366,363 -> "366K", 2,450,000 -> "2.45M".
static func short_money(n: int) -> String:
	var a := absi(n)
	var s := ""
	if a >= 1_000_000:
		s = ("%.2fM" if a < 10_000_000 else "%.1fM") % (a / 1_000_000.0)
	elif a >= 100_000:
		s = "%dK" % roundi(a / 1000.0)
	elif a >= 1000:
		s = "%.1fK" % (a / 1000.0)
	else:
		s = str(a)
	return ("-" if n < 0 else "") + s


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
	advisor.go.connect(func(key: String):
		var card := tour_target(key) as Button
		if card != null and not card.disabled:
			advisor.close_panel()
			press_card(card))
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
	_help_keys.add_theme_constant_override("separation", 2)
	col.add_child(_help_keys)
	_fill_help()
	var guide := Button.new()
	guide.text = "Guided tour (first town)"
	guide.focus_mode = Control.FOCUS_NONE
	guide.pressed.connect(func(): tour.start())
	col.add_child(guide)
	_clear_button.text = CLEAR_TEXT
	_clear_button.focus_mode = Control.FOCUS_NONE
	_clear_button.pressed.connect(_press_clear)
	col.add_child(_clear_button)
	col.add_child(UiStyle.label("Build " + _build_name(), 10, UiStyle.MUTED))
	_help.visible = false
	_root.add_child(_help)
	_pin(_help, Control.PRESET_TOP_RIGHT, Vector2(-6, 42))


## Start over takes a second click: one stray click (or clicks queued
## behind a freeze) used to wipe a whole town with no way back.
func _press_clear() -> void:
	if not _clear_armed:
		_clear_armed = true
		var pop := int(sim.stats.get("population", 0))
		_clear_button.text = "Click again to clear it all" + (" (%s people)" % _thousands(pop) if pop > 0 else "")
		_clear_button.add_theme_color_override("font_color", BAD)
		get_tree().create_timer(4.0).timeout.connect(_disarm_clear)
		return
	_disarm_clear()
	sim.apply({"type": "clear"})
	# Say it happened, and rest the button a moment so repeat clicks don't pile up.
	_clear_button.text = "Map cleared"
	_clear_button.disabled = true
	get_tree().create_timer(3.0).timeout.connect(func():
		_clear_button.disabled = false
		_clear_button.text = CLEAR_TEXT)


func _disarm_clear() -> void:
	if _clear_armed:
		_clear_armed = false
		_clear_button.text = CLEAR_TEXT
		_clear_button.remove_theme_color_override("font_color")


## The key list follows the Controls page, so it's refilled each time it opens.
func _fill_help() -> void:
	for c in _help_keys.get_children():
		c.queue_free()
	var k := func(a: String) -> String: return KeyBinds.text(a)
	var lines := [
		"CAMERA",
		"%s %s %s %s  move  (Shift: faster)" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")],
		"%s / %s  rotate   %s / %s  tilt" % [k.call("rotate_left"), k.call("rotate_right"), k.call("tilt_up"), k.call("tilt_down")],
		"%s / %s or scroll  zoom" % [k.call("zoom_in"), k.call("zoom_out")],
		"Right drag  move the map", "Middle drag or Option + drag  rotate", "%s  back to your town" % k.call("home"),
		"TOOLS",
		"Hold 1 to 0  a menu's pie: flick to a tool, let go (tap: click one)",
		"Shift + 1 to 0  open a menu   %s  views   %s  find" % [k.call("views"), k.call("search")],
		"%s upgrade   %s parallel   %s bulldoze   %s move it" % [k.call("upgrade"), k.call("parallel"), k.call("bulldoze"), k.call("move_it")],
		"%s %s  size   %s / %s  bridge or tunnel" % [k.call("smaller"), k.call("bigger"), k.call("raise"), k.call("lower")],
		"Grid: Enter builds the shape, Tab turns it",
		"%s  zoning tool: street, brush or smart" % k.call("brush"),
		"%s  traffic view   Ctrl+Z  undo the last build" % k.call("traffic"),
		"Right click  stop drawing", "Esc  stop drawing, then close everything",
		"GAME",
		"%s  pause   Enter  chat (in a region)   %s  flag a bad sound" % [k.call("pause"), k.call("flag_sound")],
		"Change keys: pause menu, Controls",
		"CONTROLLER",
		"Left stick  cursor (push the edge to move)", "Right stick  turn and tilt   LT / RT  zoom",
		"A  use   X  cancel   B  back   Y  tool wheel, then its tools",
		"LB / RB  size or turn   D-pad  height, speed; steps between buttons over a menu",
		"Click right stick  finish a shape, or go home", "Menu  pause menu   View  pause   View + X  undo"]
	for line in lines:
		if line == line.to_upper():
			_help_keys.add_child(UiStyle.label(line, 10, UiStyle.MUTED))
		else:
			_help_keys.add_child(UiStyle.label(line, 12))


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
