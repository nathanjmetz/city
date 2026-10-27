class_name TownPanel
extends PanelContainer
## The Town panel, from the marker button in the top bar: the town's name and
## the nickname it has earned (and the ones it outgrew), what it is known
## for, its historic districts, its roadside markers, and the timelapse.
## Docked to the right edge under the top bar, like the bell and Advice. It
## never opens by itself.

signal opened
signal watch_timelapse

const WIDTH := 330

var sim: CitySim
var cam: CityCamera

var _button: Button
var _body := VBoxContainer.new()
var _shown_key := ""
var _wait := 0.0


func setup(s: CitySim, c: CityCamera) -> void:
	sim = s
	cam = c


func _ready() -> void:
	add_theme_stylebox_override("panel", _style())
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var ic := Icon.new("town", 16)
	ic.color = Brand.BRAND_MINT
	ic.accent = Brand.SURFACE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var title := UiStyle.label("TOWN", 11, UiStyle.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_panel)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH - 24, 0)
	col.add_child(scroll)
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_body.resized.connect(func():
		var room := get_viewport_rect().size.y - global_position.y - 80.0
		scroll.custom_minimum_size.y = minf(_body.size.y, maxf(room, 200.0)))
	visible = false


func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Town: its nickname, history and markers"
	_button.custom_minimum_size = Vector2(34, 24)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(mid)
	var ic := Icon.new("town", 16)
	ic.accent = Brand.SURFACE
	mid.add_child(ic)
	_button.toggled.connect(func(on): open_panel() if on else close_panel())
	return _button


func open_panel() -> void:
	visible = true
	if _button:
		_button.set_pressed_no_signal(true)
	_shown_key = ""
	_rebuild()
	opened.emit()


func close_panel() -> void:
	visible = false
	if _button:
		_button.set_pressed_no_signal(false)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not visible:
		return
	_wait = 1.0
	_rebuild()


func _rebuild() -> void:
	if sim == null:
		return
	var key := "%s|%s|%d|%s|%d|%d|%s" % [sim.nicknames.current, sim.nicknames.past.size(), sim.markers.version,
		sim.heritage.listed(), Seasons.month(sim.calendar_tick()), sim.timelapse.months, sim.charter.reached.keys()]
	if key == _shown_key:
		return
	_shown_key = key
	for c in _body.get_children():
		c.queue_free()
	var town := _town_name("Your town")
	_body.add_child(UiStyle.label(sim.charter.title(town), 18, UiStyle.TEXT, 700))
	var nick: Dictionary = sim.nicknames.current
	if nick.is_empty():
		_body.add_child(_text("No nickname yet. A town earns one from what it becomes: its farms, its mills, its Main Street.",
			UiStyle.MUTED))
	else:
		_body.add_child(_text("“%s”" % nick.text, Brand.BRAND_MINT, 600, 14))
		_body.add_child(_text("Since %d" % int(nick.since), UiStyle.MUTED, 500, 11))
	for p in sim.nicknames.past:
		_body.add_child(_text("Once the %s (%d to %d)" % [p.text, int(p.from), int(p.to)], UiStyle.MUTED, 500, 12))

	# The charter ladder: where the town stands, and the next step in a line.
	_section("CHARTER")
	var reached: Array = Charter.STEPS.filter(func(st): return sim.charter.reached.has(st.id))
	_body.add_child(_text("%s · step %d of %d" % [reached[-1].name, reached.size(), Charter.STEPS.size()],
		UiStyle.TEXT, 600, 13))
	var next: String = sim.charter.next_line(sim)
	if next != "":
		_body.add_child(_text("Next: " + next, UiStyle.MUTED, 500, 12))

	_section("KNOWN FOR")
	var shares: Dictionary = sim.culture.shares
	var sectors: Array = shares.keys()
	sectors.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]) or (shares[a] == shares[b] and a < b))
	for k in sectors:
		if float(shares[k]) >= 0.01:
			_body.add_child(_bar(TownNickname.SECTOR_NAMES.get(k, k), float(shares[k])))
	if shares.is_empty():
		_body.add_child(_text("Nothing yet: too few people work in town.", UiStyle.MUTED, 500, 12))
	_body.add_child(_text("It follows where people work, slowly. Your answers to leaders on the bell lean it too.",
		Brand.INK_FAINT, 500, 11))

	_section("HISTORIC DISTRICTS")
	var ds: Array = sim.heritage.listed()
	if ds.is_empty():
		_body.add_child(_text("None yet. Once a corner of town is mostly buildings %d years old or more, it can be protected." %
			Balance.HERITAGE_AGE_YEARS, UiStyle.MUTED, 500, 12))
	for d in ds:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_body.add_child(row)
		row.add_child(_text(str(d.name), UiStyle.TEXT, 600, 13))
		var st := "Protected since %d" % Families.calendar(Seasons.year(sim.calendar_of(int(d.since)))) if d.state == "protected" \
			else "Eligible, not protected"
		row.add_child(_text("%s · %d buildings" % [st, int(d.buildings)], UiStyle.MUTED, 500, 12))
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.text = "Lift protection" if d.state == "protected" else "Protect it"
		b.tooltip_text = ("Owners may rebuild again." if d.state == "protected" else
			"Nothing there is torn down or built up. Land is worth more, visitors come, and the commission costs $%s a day." %
			CitySim.money_text(Balance.HERITAGE_COMMISSION_MONTHLY))
		var id := int(d.id)
		var on: bool = d.state != "protected"
		b.pressed.connect(func():
			sim.apply({"type": "heritage", "district": id, "protect": on})
			_shown_key = ""
			_rebuild())
		row.add_child(b)

	_section("MARKERS")
	if sim.markers.markers.is_empty():
		_body.add_child(_text("The town's firsts get roadside markers: its first store, first school, first stoplight...",
			UiStyle.MUTED, 500, 12))
	var list: Array = sim.markers.markers.duplicate()
	list.reverse()
	for m in list:
		var mb := Button.new()
		mb.flat = true
		mb.focus_mode = Control.FOCUS_NONE
		mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		mb.add_theme_font_size_override("font_size", 12)
		mb.text = "%s  ·  %d" % [HistoricMarkers.filled(str(m.title), town), int(m.year)]
		mb.tooltip_text = HistoricMarkers.filled(str(m.text), town)
		var at := Vector3(float(m.pos[0]), 0.0, float(m.pos[1]))
		mb.pressed.connect(func():
			if cam:
				cam.fly_to(at))
		_body.add_child(mb)

	_section("TIMELAPSE")
	var tl := Button.new()
	tl.focus_mode = Control.FOCUS_NONE
	tl.text = "Watch the town grow"
	tl.disabled = sim.timelapse.months < 2
	tl.tooltip_text = "Replay the town from its first road to today, drawn like the old Sanborn maps."
	tl.pressed.connect(func(): watch_timelapse.emit())
	_body.add_child(tl)


func _section(title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	_body.add_child(gap)
	_body.add_child(UiStyle.label(title, 10, UiStyle.MUTED, 600))


func _bar(name: String, share: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UiStyle.label(name, 12, UiStyle.TEXT)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = share
	bar.custom_minimum_size = Vector2(110, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Brand.BRAND_TEAL
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return row


func _text(s: String, color := UiStyle.TEXT, weight := 500, px := 13) -> Label:
	var l := UiStyle.label(s, px, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	return l


func _style() -> StyleBoxFlat:
	var b := UiStyle.dock(true)
	b.border_width_left = 1
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 10
	return b


## The town's name (from the Session autoload, looked up at run time so
## tools that load this class before autoloads still compile).
func _town_name(fallback: String) -> String:
	var s := get_node_or_null("/root/Session")
	return str(s.current_name) if s != null and str(s.current_name) != "" else fallback
