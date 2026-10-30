class_name RoadCatalog
extends Control
## "All roads": every road the game has on one screen over the map, opened
## from the All roads card on the Roads menu's bar (Nathan, 2026-10-29: "a
## whole screen of roads with all kinds of different options and features";
## asked whether it should replace the bar, he picked keeping the bar and
## adding this card; docs/spec-road-treatments.md, "A whole screen of roads").
##
## Left: the kinds (Streets, Avenues, ...), each jumping to its group. Middle:
## a picture card per road, its cross-section drawn from its own numbers
## (RoadSection), its lanes, speed and price. Top: filter chips and a search
## box that works like the HUD's. Picking a card takes that road, just as the
## bar does. Arrows move, Enter picks, Tab jumps kinds, Esc closes.
##
## On a narrow screen (a phone, a tablet standing up) the kinds move up into a
## row of chips and the cards go one or two across.

## A road card was picked (the Hud takes it in hand).
signal road_picked(type: int)
signal closed

## The kinds, in order. Add-ons and paths are tools from other menus.
const CATEGORIES := [["streets", "Streets"], ["avenues", "Avenues"], ["big", "Big roads"],
	["highways", "Highways and ramps"], ["country", "Country"], ["paths", "Paths and trails"], ["addons", "Add-ons"]]
## A line under a kind's cards, for what's coming.
const NOTES := {
	"paths": "Trails you draw yourself come later. Today the town's trails grow out from a trailhead.",
	"addons": "Trees, sound walls and wider walks for any road come later.",
}
## Filter chips: key, words, tooltip. The lane chips widen each other (1-2
## or 3-4 lanes); the rest narrow (one-way and with parking).
const FILTERS := [
	["lanes12", "1-2 lanes", "Roads with one or two lanes"],
	["lanes34", "3-4 lanes", "Roads with three or four lanes (a center turn lane counts)"],
	["lanes5", "5+ lanes", "Roads with five lanes or more (a center turn lane counts)"],
	["oneway", "One-way", "Traffic runs one way, the way you draw it"],
	["parking", "Parking", "Cars can park along the curb"],
	["bike", "Bike lanes", "A bike lane each side"],
	["bus", "Bus lanes", "Curb lanes for buses only"],
	["trees", "Trees", "Trees down the middle"],
	["trucks", "Trucks OK", "Through trucks may use it under the Truck routes law"],
	["country", "Country", "Out in the country: no curbs or sidewalks"],
]
const LANE_FILTERS := ["lanes12", "lanes34", "lanes5"]

## Layout: the panel's largest size, the narrowest it keeps the kinds on the
## left, and a card's least width.
const MAX_SIZE := Vector2(1760, 980)
const NARROW := 700.0
const CARD_MIN := 176.0
const CARD_MIN_NARROW := 150.0
const SEP := 8

var _dim := ColorRect.new()
var _panel := PanelContainer.new()
var _search := LineEdit.new()
var _count := UiStyle.label("", 13, UiStyle.MUTED)
var _header := HBoxContainer.new()
var _search_row := HBoxContainer.new()
var _chip_row := HFlowContainer.new()
var _clear := Button.new()
var _cat_col := VBoxContainer.new()
## Narrow: the chips and the kinds each in one row that slides sideways,
## so the cards keep most of a phone's height.
var _chip_slide := ScrollContainer.new()
var _chip_line := HBoxContainer.new()
var _cat_slide := ScrollContainer.new()
var _cat_row := HBoxContainer.new()
var _cat_sep := VSeparator.new()
var _scroll := ScrollContainer.new()
var _content := VBoxContainer.new()
var _empty := VBoxContainer.new()
var _hint := UiStyle.label("Arrows move  ·  Enter picks  ·  Tab next kind  ·  Esc closes", 12, Brand.INK_FAINT)
var _chips := {}      # filter key -> Button
var _cat_buttons := {}  # kind -> [left-column Button, chip Button]
var _groups := {}     # kind -> {box, grid}
var _entries: Array = []  # {card, button, cat, hay, type (-1 for a tool), addon}
var _shown: Array = []    # the entries showing, in screen order
var _filters := {}    # filter key -> true
var _hi := -1         # the highlighted entry in _shown
var _cols := 1
var _narrow := false
var _laid := false
var _settle := 0  # frames left to keep the road in hand in view while the cards settle
## Road type -> its card's Button, for the Hud's search and recent tools.
var road_cards := {}


static func roads() -> Array:
	var out := []
	for c in CATEGORIES:
		out.append_array(roads_in(c[0]))
	return out


## The road types in one kind, in the game's own order (each menu's own road first).
static func roads_in(cat: String) -> Array:
	var out := []
	for t in RoadStyle.TYPES.size():
		if category_of(t) == cat:
			out.append(t)
	return out


## The kind a road type is shown under, or "" for one a player doesn't pick
## (the roundabout rings).
static func category_of(t: int) -> String:
	var spec: Dictionary = RoadStyle.TYPES[t]
	if not spec.get("menu", true):
		return ""
	match RoadStyle.group(t):
		RoadStyle.Type.HIGHWAY, RoadStyle.Type.RAMP:
			return "highways"
		RoadStyle.Type.BOULEVARD:
			return "big"
		RoadStyle.Type.AVENUE:
			return "avenues"
	# Out in the country: no curbs, homes and farms along it (an alley has
	# no curbs either, but it's a town street).
	if spec.get("rural", false) and spec.lots:
		return "country"
	return "streets"


static func category_title(cat: String) -> String:
	for c in CATEGORIES:
		if c[0] == cat:
			return c[1]
	return ""


## Lanes, counting a shared center turn lane (a five-lane strip has five).
static func lane_count(t: int) -> int:
	var spec: Dictionary = RoadStyle.TYPES[t]
	return int(spec.lanes) + (1 if spec.get("turn", false) else 0)


## Cars can park along its curb (as the road's tooltip says).
static func parks(t: int) -> bool:
	var spec: Dictionary = RoadStyle.TYPES[t]
	return spec.get("angle", false) or spec.get("parking", 0) > 0 or t == RoadStyle.Type.STREET


## What a road has, by filter key.
static func tags(t: int) -> Dictionary:
	var spec: Dictionary = RoadStyle.TYPES[t]
	var n := lane_count(t)
	return {
		"lanes12": n <= 2, "lanes34": n >= 3 and n <= 4, "lanes5": n >= 5,
		"oneway": spec.oneway, "parking": parks(t), "bike": spec.get("bike", false),
		"bus": spec.get("bus", false), "trees": spec.get("trees", false),
		"trucks": not t in TownLaws.LOCAL_STREETS, "country": category_of(t) == "country",
	}


## Whether a road passes the chips switched on in `on` (filter key -> true).
static func passes(t: int, on: Dictionary) -> bool:
	var has := tags(t)
	var lane_on := false
	var lane_ok := false
	for k in on:
		if not on[k]:
			continue
		if k in LANE_FILTERS:
			lane_on = true
			lane_ok = lane_ok or has[k]
		elif not has.get(k, false):
			return false
	return lane_ok or not lane_on


## Every word typed is somewhere in `hay` (the HUD's search does the same).
static func matches(text: String, hay: String) -> bool:
	for w in text.to_lower().strip_edges().split(" ", false):
		if not w in hay:
			return false
	return true


## A road's tooltip: what it is, in plain words, with its lanes, speed and price.
static func tip(t: int) -> String:
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
	elif parks(t):
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


## "2 lanes", "1 lane, one way", "4 lanes and a turn lane".
static func lanes_text(t: int) -> String:
	var spec: Dictionary = RoadStyle.TYPES[t]
	var out := "%d lane%s" % [spec.lanes, "" if spec.lanes == 1 else "s"]
	if spec.get("turn", false):
		out += " + turn lane"
	elif spec.oneway:
		out += ", one way"
	return out


## What 100 m of it costs to build, from the economy's price per metre.
static func cost_text(t: int) -> String:
	return "$%s per 100 m" % CitySim.money_text(int(Economy.BUILD_PER_M[t]) * 100)


## Builds the screen. `tools` holds the cards from other menus that belong
## here: kind -> [{title, icon, where, tip, pick: Callable, on: Callable}].
func setup(tools: Dictionary) -> void:
	# Sized to the window itself: the HUD's root grows past a phone's width
	# to fit the bars, and this must not.
	top_level = true
	theme = UiStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_dim)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	# Title, count, search and close.
	_header.add_theme_constant_override("separation", 10)
	col.add_child(_header)
	var title := UiStyle.title("All roads", 20)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(title)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.clip_text = true
	_header.add_child(_count)
	_search.placeholder_text = "Find: brick, bike, one-way..."
	_search.custom_minimum_size = Vector2(240, 32)
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _refilter(true))
	_header.add_child(_search)
	var x := Button.new()
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(32, 32)
	x.tooltip_text = "Close  (Esc)"
	var xi := Icon.new("close", 18)
	xi.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	xi.offset_left = -9
	xi.offset_top = -9
	xi.offset_right = 9
	xi.offset_bottom = 9
	x.add_child(xi)
	x.pressed.connect(close)
	_header.add_child(x)
	_search_row.visible = false
	col.add_child(_search_row)

	# Filter chips.
	_chip_row.add_theme_constant_override("h_separation", 6)
	_chip_row.add_theme_constant_override("v_separation", 6)
	col.add_child(_chip_row)
	for f in FILTERS:
		var c := _chip(f[1], f[2])
		var key: String = f[0]
		c.toggled.connect(func(on: bool):
			_filters[key] = on
			_refilter(true))
		_chip_row.add_child(c)
		_chips[key] = c
	_clear.text = "Clear"
	_clear.flat = true
	_clear.focus_mode = Control.FOCUS_NONE
	_clear.add_theme_font_size_override("font_size", 12)
	_clear.add_theme_color_override("font_color", Brand.BRAND_MINT)
	_clear.custom_minimum_size = Vector2(0, 28)
	_clear.tooltip_text = "Clear the filters and the search"
	_clear.pressed.connect(clear_filters)
	_chip_row.add_child(_clear)

	# The kinds as chips, for narrow screens.
	for slide in [_chip_slide, _cat_slide]:
		slide.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# No bar under the chips: a finger slides them, and the chip cut off
		# at the edge shows there's more.
		slide.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		slide.visible = false
		col.add_child(slide)
	_chip_line.add_theme_constant_override("separation", 6)
	_chip_slide.add_child(_chip_line)
	_cat_row.add_theme_constant_override("separation", 6)
	_cat_slide.add_child(_cat_row)
	var go := UiStyle.label("GO TO", 12, UiStyle.MUTED)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cat_row.add_child(go)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_cat_col.add_theme_constant_override("separation", 2)
	_cat_col.custom_minimum_size = Vector2(190, 0)
	body.add_child(_cat_col)
	body.add_child(_cat_sep)
	var group := ButtonGroup.new()
	for c in CATEGORIES:
		var cat: String = c[0]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_jump.bind(cat))
		_cat_col.add_child(b)
		var chip := _chip(c[1], "")
		chip.toggle_mode = false
		chip.pressed.connect(_jump.bind(cat))
		_cat_row.add_child(chip)
		_cat_buttons[cat] = [b, chip]

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.resized.connect(_fit_columns)
	body.add_child(_scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	_scroll.add_child(_content)
	for c in CATEGORIES:
		var cat: String = c[0]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		_content.add_child(box)
		box.add_child(UiStyle.label(String(c[1]).to_upper(), 12, Brand.BRAND_MINT))
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", SEP)
		grid.add_theme_constant_override("v_separation", SEP)
		box.add_child(grid)
		if NOTES.has(cat):
			var note := UiStyle.label(NOTES[cat], 12, UiStyle.MUTED)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(note)
		_groups[cat] = {"box": box, "grid": grid}
		for t in roads_in(cat):
			_add_road(cat, t)
		for a in tools.get(cat, []):
			_add_tool(cat, a)
	# Nothing matches.
	_empty.visible = false
	_empty.add_theme_constant_override("separation", 8)
	var none := UiStyle.label("No roads match. Try another word, or clear the filters.", 14, UiStyle.MUTED)
	none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(none)
	var again := Button.new()
	again.text = "Clear filters and search"
	again.focus_mode = Control.FOCUS_NONE
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	again.pressed.connect(clear_filters)
	_empty.add_child(again)
	_content.add_child(_empty)
	col.add_child(_hint)
	_refilter(false)


func _chip(title: String, tip_text: String) -> Button:
	var c := Button.new()
	c.toggle_mode = true
	c.focus_mode = Control.FOCUS_NONE
	c.text = title
	c.tooltip_text = tip_text
	c.add_theme_font_size_override("font_size", 12)
	c.custom_minimum_size = Vector2(0, 28)
	return c


func _add_road(cat: String, t: int) -> void:
	var spec: Dictionary = RoadStyle.TYPES[t]
	var card := _Card.new()
	card.picture.add_child(RoadSection.new(t))
	card.fill(spec.name, "%s  ·  %d mph" % [lanes_text(t), spec.mph], cost_text(t))
	var b := card.button
	b.tooltip_text = tip(t)
	# For the Hud's search and recent tools: its name, and a road icon.
	b.set_meta("title", card.title)
	var ic := Icon.new("road:%d" % t, 16)
	ic.visible = false
	card.add_child(ic)
	b.set_meta("icon", ic)
	b.pressed.connect(_pick_road.bind(t))
	road_cards[t] = b
	_add(cat, card, {"type": t, "hay": (tip(t) + " " + category_title(cat)).to_lower()})


func _add_tool(cat: String, a: Dictionary) -> void:
	var card := _Card.new()
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", UiStyle._box(Brand.SURFACE_SUNKEN, UiStyle.RADIUS_SM))
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(a.icon, 40)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.add_child(ic)
	card.picture.add_child(well)
	card.fill(a.title, a.where, "")
	card.button.tooltip_text = a.tip
	card.button.pressed.connect(func():
		close()
		(a.pick as Callable).call())
	_add(cat, card, {"type": -1, "addon": a,
		"hay": ("%s %s %s %s" % [a.title, a.where, a.tip, category_title(cat)]).to_lower()})


func _add(cat: String, card: _Card, e: Dictionary) -> void:
	e.card = card
	e.button = card.button
	e.cat = cat
	_groups[cat].grid.add_child(card)
	card.button.mouse_entered.connect(func():
		var i := _shown.find(e)
		if i >= 0:
			_set_hi(i, false))
	_entries.append(e)


## Opens the screen with `current` (a road type) shown as the road in hand.
func open(current: int) -> void:
	for e in _entries:
		var on: bool = e.type == current if e.type >= 0 else bool((e.addon.on as Callable).call())
		(e.button as Button).set_pressed_no_signal(on)
	_search.text = ""
	visible = true
	MenuState.covering = true
	set_process(true)
	if not get_viewport().size_changed.is_connected(_layout):
		get_viewport().size_changed.connect(_layout)
	_layout()
	_refilter(false)
	var at := -1
	for i in _shown.size():
		if _shown[i].type == current:
			at = i
	_set_hi(maxi(at, 0), false)
	_scroll.scroll_vertical = 0
	# The cards take a few frames to find their columns and heights; keep
	# the road in hand in view while they do.
	_settle = 4
	if not soft_keyboard():
		_search.grab_focus()


## A phone or tablet, where focusing the search box pops up the screen
## keyboard over the cards. A touchscreen laptop has real keys, so its
## search box takes the typing as a desktop's does.
static func soft_keyboard() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func close() -> void:
	if not visible:
		return
	visible = false
	MenuState.covering = false
	set_process(false)
	_search.release_focus()
	closed.emit()


func clear_filters() -> void:
	_filters.clear()
	for k in _chips:
		_chips[k].set_pressed_no_signal(false)
	_search.text = ""
	_refilter(true)


## Types a search, as a player would (the tests use it too).
func search(text: String) -> void:
	_search.text = text
	_refilter(true)


## Switches a filter chip, as a click would.
func set_filter(key: String, on: bool) -> void:
	_chips[key].button_pressed = on


## The road types showing now, in screen order.
func shown_roads() -> Array:
	var out := []
	for e in _shown:
		if e.type >= 0:
			out.append(e.type)
	return out


## The titles of the cards showing now (roads and tools), in screen order.
func shown_titles() -> Array:
	return _shown.map(func(e): return (e.card as _Card).title.text)


func _pick_road(t: int) -> void:
	close()
	road_picked.emit(t)


func _refilter(reset_hi: bool) -> void:
	var text := _search.text
	var any_filter := _filters.values().has(true)
	_shown.clear()
	var roads_shown := 0
	for c in CATEGORIES:
		var cat: String = c[0]
		var n := 0
		for e in _entries:
			if e.cat != cat:
				continue
			var ok := matches(text, e.hay) and (passes(e.type, _filters) if e.type >= 0 else not any_filter)
			(e.card as Control).visible = ok
			if ok:
				n += 1
				_shown.append(e)
				if e.type >= 0:
					roads_shown += 1
		_groups[cat].box.visible = n > 0
		var b: Button = _cat_buttons[cat][0]
		b.text = "%s   %d" % [c[1], n]
		b.disabled = n == 0
		_cat_buttons[cat][1].visible = n > 0
	_empty.visible = _shown.is_empty()
	_clear.visible = any_filter or text.strip_edges() != ""
	var total := roads().size()
	_count.text = "%d roads" % total if roads_shown == total else "%d of %d roads" % [roads_shown, total]
	if reset_hi:
		_settle = 0
		_scroll.scroll_vertical = 0
		_set_hi(0 if not _shown.is_empty() else -1, false)
	elif _hi >= _shown.size():
		_set_hi(_shown.size() - 1, false)


func _jump(cat: String) -> void:
	var box: Control = _groups[cat].box
	if not box.visible:
		return
	_settle = 0
	_scroll.scroll_vertical = int(box.position.y)
	for i in _shown.size():
		if _shown[i].cat == cat:
			_set_hi(i, false)
			break
	if not soft_keyboard():
		_search.grab_focus()


func _set_hi(i: int, reveal := true) -> void:
	if _hi >= 0 and _hi < _shown.size():
		(_shown[_hi].card as _Card).set_highlight(false)
	_hi = i
	if _hi >= 0 and _hi < _shown.size():
		(_shown[_hi].card as _Card).set_highlight(true)
		if reveal:
			_reveal()


func _reveal() -> void:
	if _hi < 0 or _hi >= _shown.size():
		return
	var e: Dictionary = _shown[_hi]
	_scroll.ensure_control_visible(e.card)
	# A card in its kind's first row brings the kind's name into view too.
	var box: Control = _groups[e.cat].box
	if (e.card as Control).position.y < 1.0:
		_scroll.ensure_control_visible(box.get_child(0))


## The highlighted card (the one Enter picks), or null.
func highlighted() -> Button:
	return _shown[_hi].button if _hi >= 0 and _hi < _shown.size() else null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k != null and k.pressed:
		var used := true
		match k.keycode:
			KEY_ESCAPE:
				close()
			KEY_UP:
				move(Vector2i(0, -1))
			KEY_DOWN:
				move(Vector2i(0, 1))
			KEY_LEFT:
				move(Vector2i(-1, 0))
			KEY_RIGHT:
				move(Vector2i(1, 0))
			KEY_ENTER, KEY_KP_ENTER:
				var b := highlighted()
				if b != null:
					b.pressed.emit()
			KEY_TAB:
				_next_kind(-1 if k.shift_pressed else 1)
			_:
				used = false
				# A key typed anywhere goes into the search box (and never to
				# the town's own keys behind the panel).
				if k.unicode > 31 and not _search.has_focus():
					_search.grab_focus()
		if used:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and not soft_keyboard():
		# Keys keep going to the search box (and not to the camera).
		_search.grab_focus.call_deferred()


## Moves the highlight: left and right along the cards, up and down a row,
## crossing into the kind above or below.
func move(d: Vector2i) -> void:
	if _shown.is_empty():
		return
	if _hi < 0:
		_set_hi(0)
		return
	if d.x != 0:
		_set_hi(clampi(_hi + d.x, 0, _shown.size() - 1))
		return
	var rows := []  # each kind's showing entries, as indices into _shown
	var g := -1
	var at := 0
	for i in _shown.size():
		if rows.is_empty() or _shown[i].cat != _shown[rows[-1][0]].cat:
			rows.append([])
		rows[-1].append(i)
		if i == _hi:
			g = rows.size() - 1
			at = rows[-1].size() - 1
	var col := at % _cols
	var to := _hi
	var mine: Array = rows[g]
	if d.y > 0:
		if at + _cols < mine.size():
			to = mine[at + _cols]
		elif at / _cols < (mine.size() - 1) / _cols:
			to = mine[-1]
		elif g + 1 < rows.size():
			to = rows[g + 1][mini(col, rows[g + 1].size() - 1)]
	elif d.y < 0:
		if at - _cols >= 0:
			to = mine[at - _cols]
		elif g > 0:
			var prev: Array = rows[g - 1]
			to = prev[mini((prev.size() - 1) / _cols * _cols + col, prev.size() - 1)]
	_set_hi(to)


func _next_kind(step: int) -> void:
	var cats := []
	for c in CATEGORIES:
		if _groups[c[0]].box.visible:
			cats.append(c[0])
	if cats.is_empty():
		return
	var now: String = _shown[_hi].cat if _hi >= 0 and _hi < _shown.size() else cats[0]
	_jump(cats[posmod(cats.find(now) + step, cats.size())])


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()
	elif what == NOTIFICATION_EXIT_TREE and visible:
		MenuState.covering = false  # leaving town with it open


## Fits the panel to the screen: the whole screen less a margin, up to
## MAX_SIZE, and the kinds on the left or (narrow) in a row on top.
func _layout() -> void:
	if not visible:
		return
	var screen := get_viewport_rect().size
	position = Vector2.ZERO
	size = screen
	var w := screen.x
	var h := screen.y
	if w <= 0.0 or h <= 0.0:
		return
	var m := 10.0 if w < 600.0 else 24.0
	var ps := Vector2(minf(w - 2.0 * m, MAX_SIZE.x), minf(h - 2.0 * m, MAX_SIZE.y))
	_panel.size = ps
	_panel.position = ((screen - ps) * 0.5).floor()
	var narrow := ps.x < NARROW
	if narrow == _narrow and _laid:
		return
	_laid = true
	_narrow = narrow
	_cat_col.visible = not narrow
	_cat_sep.visible = not narrow
	_cat_slide.visible = narrow
	_chip_slide.visible = narrow
	_chip_row.visible = not narrow
	var from: Container = _chip_line if not narrow else _chip_row
	var to: Container = _chip_row if not narrow else _chip_line
	for c in from.get_children():
		from.remove_child(c)
		to.add_child(c)
	_hint.visible = not narrow and not soft_keyboard()
	# Narrow: the search box gets its own row under the title.
	if narrow and _search.get_parent() == _header:
		_header.remove_child(_search)
		_search_row.add_child(_search)
	elif not narrow and _search.get_parent() == _search_row:
		_search_row.remove_child(_search)
		_header.add_child(_search)
		_header.move_child(_search, 2)
	_search_row.visible = narrow
	_search.custom_minimum_size.x = 0.0 if narrow else 240.0


## As many cards across as fit, each at least CARD_MIN wide.
func _fit_columns() -> void:
	var least := CARD_MIN_NARROW if _narrow else CARD_MIN
	var room := _scroll.size.x - 14.0  # the scroll bar
	_cols = clampi(int((room + SEP) / (least + SEP)), 1, 12)
	for cat in _groups:
		(_groups[cat].grid as GridContainer).columns = _cols


func _process(_delta: float) -> void:
	if _settle > 0:
		_settle -= 1
		_reveal()
	# The kind on the left follows what's scrolled into view.
	var y := float(_scroll.scroll_vertical) + 8.0
	var now := ""
	for c in CATEGORIES:
		var box: Control = _groups[c[0]].box
		if box.visible and (now == "" or box.position.y <= y):
			now = c[0]
	if now != "":
		var b: Button = _cat_buttons[now][0]
		if not b.button_pressed:
			b.set_pressed_no_signal(true)
			for c in CATEGORIES:
				if c[0] != now:
					_cat_buttons[c[0]][0].set_pressed_no_signal(false)


## A picture card: the picture on top, then the name and two lines of
## detail. A Button behind gives the tool card look (a coral ring for the
## road in hand) and takes the clicks; the words sit over it.
class _Card extends Container:
	const PAD := 6.0
	var button := Button.new()
	var body := VBoxContainer.new()
	var picture := MarginContainer.new()
	var title := UiStyle.label("", 14, UiStyle.TEXT, 600)
	var detail := UiStyle.label("", 12, UiStyle.MUTED)
	var cost := UiStyle.label("", 12, UiStyle.MUTED)
	static var _ring: StyleBoxFlat

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ToolCard"
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		add_child(button)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 2)
		add_child(body)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.custom_minimum_size = Vector2(0, 96)
		body.add_child(picture)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 3)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(gap)
		for l in [title, detail, cost]:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(l)

	func fill(name_text: String, detail_text: String, cost_text_: String) -> void:
		title.text = name_text
		detail.text = detail_text
		cost.text = cost_text_
		cost.visible = cost_text_ != ""

	## The keyboard's place: a mint ring (the theme's focus colour).
	func set_highlight(on: bool) -> void:
		if _ring == null:
			_ring = UiStyle._box(Brand.SURFACE_RAISED, UiStyle.RADIUS_SM, Brand.FOCUS)
		for state in ["normal", "hover"]:
			if on:
				button.add_theme_stylebox_override(state, _ring)
			else:
				button.remove_theme_stylebox_override(state)

	func _get_minimum_size() -> Vector2:
		var m := body.get_combined_minimum_size()
		return Vector2(m.x + 2.0 * PAD, m.y + 2.0 * PAD)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			fit_child_in_rect(button, Rect2(Vector2.ZERO, size))
			fit_child_in_rect(body, Rect2(Vector2(PAD, PAD), size - Vector2(2.0 * PAD, 2.0 * PAD)))
			for c in get_children():
				if c is Icon:
					c.size = Vector2.ZERO
