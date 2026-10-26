class_name RegionPanel
extends PanelContainer
## The region, from the globe in the top bar: the big projects every town
## can chip in to (a new I-69 interchange, the power co-op's station, the
## regional airport), and the services this town shares with its
## neighbors. Only shown in a region (every game is, outside of tests).
##
## Projects: each one's board, the stage being funded (a bar of what's
## pledged against the goal), what that stage will do, what the funded ones
## already do here, this town's share, and Pledge buttons. Pledges are final.
##
## Services: offers this town's leaders want to make (Send or Not now),
## offers from neighbors (Accept or Turn down), offers still waiting on a
## neighbor, and signed deals (Give notice). Answering here answers the same
## request on the permit bell.

signal opened

const WIDTH := 360
## The two pledge buttons, dollars.
const PLEDGES := [100_000, 1_000_000]

var sim: CitySim
var region: Region
var me := ""
## Sends a pledge: (project_id, amount) -> void (RegionClient.pledge).
var pledge_to: Callable

var _button: Button
var _tab := "projects"
var _tabs := {}
var _list := VBoxContainer.new()
var _shown_key := ""
var _wait := 0.0


func setup(s: CitySim, r: Region, my_city: String, pledge: Callable) -> void:
	sim = s
	region = r
	me = my_city
	pledge_to = pledge


func _ready() -> void:
	add_theme_stylebox_override("panel", _style())
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var ic := Icon.new("region", 16)
	ic.color = Brand.BRAND_MINT
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var title := UiStyle.label("REGION", 11, UiStyle.MUTED)
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	for t in [["projects", "Projects"], ["services", "Services"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(b)
		_tabs[t[0]] = b
	_list.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 420
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	show_tab("projects")
	visible = false


## The globe for the top bar.
func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Region: shared projects and services with your neighbors"
	_button.custom_minimum_size = Vector2(34, 24)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(mid)
	mid.add_child(Icon.new("region", 16))
	_button.toggled.connect(func(on): open_panel() if on else close_panel())
	return _button


func open_panel() -> void:
	visible = true
	if _button:
		_button.set_pressed_no_signal(true)
	_rebuild(true)
	opened.emit()


func close_panel() -> void:
	visible = false
	if _button:
		_button.set_pressed_no_signal(false)


func show_tab(t: String) -> void:
	_tab = t
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == t)
	_rebuild(true)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not visible:
		return
	_wait = 1.0
	_rebuild()


## Rebuilds the list only when what it says has changed, so it holds still.
func _rebuild(force := false) -> void:
	if sim == null or region == null or not visible:
		return
	var key := "%s|%s|%s|%s|%d|%s" % [_tab, str(region.ledger.to_dict()), str(sim.interlocal.deals),
		str(sim.permits.listed(Permits.State.OPEN).map(func(q): return q.id)), int(sim.economy.money / 100_000), str(region.ledger.metro)]
	if key == _shown_key and not force:
		return
	_shown_key = key
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _tab == "projects":
		_projects()
	else:
		_services()


# --- Projects --------------------------------------------------------------

func _projects() -> void:
	_list.add_child(_metro())
	_list.add_child(_text("Big things no town can build alone. Every town that chips in gets more back, and nearer towns get more.",
		UiStyle.MUTED, 500, 12))
	for seed in Balance.REGION_PROJECTS:
		if region.ledger.projects.has(seed.id):
			_list.add_child(_project(seed, region.ledger.projects[seed.id]))


## Grow the metro: the road-linked towns' name, size and the next real
## metro to pass (the region's ledger works it out).
func _metro() -> Control:
	var card := _plain_card()
	var col: VBoxContainer = card.get_child(0)
	col.add_child(UiStyle.label("GROW THE METRO", 11, UiStyle.MUTED))
	var line := region.ledger.metro_line()
	col.add_child(_text(line if line != "" else "Join a neighbor by road to start a metro.", UiStyle.TEXT, 600, 12))
	var m: Dictionary = region.ledger.metro
	if int(m.get("rank", 0)) > 0:
		col.add_child(UiStyle.label("Ranked %d of %d US metros and micropolitan areas" % [int(m.rank), int(m.of)], 11, UiStyle.MUTED))
	return card


func _project(seed: Dictionary, p: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var name := UiStyle.label(p.name, 13, UiStyle.TEXT, 600)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var done := Ledger.stages_done(p)
	top.add_child(UiStyle.label("%d of %d stages" % [done, p.stages.size()], 11, UiStyle.MUTED))
	col.add_child(UiStyle.label(p.board, 11, UiStyle.MUTED))

	var st := Ledger.open_stage(p)
	if st.is_empty():
		col.add_child(_fact("check", "Finished", Brand.BRAND_MINT))
	else:
		var i := 0
		while i < p.stages.size() and p.stages[i].status != "open":
			i += 1
		col.add_child(_text("Stage %d: %s" % [i + 1, st.name], UiStyle.TEXT, 600, 12))
		var goal := float(st.goal.get("money", 0.0))
		var got := float(st.pledged.get("money", 0.0))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = maxf(goal, 1.0)
		bar.value = got
		var fill := StyleBoxFlat.new()
		fill.bg_color = Brand.BRAND_TEAL
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		col.add_child(bar)
		col.add_child(UiStyle.label("%s of %s pledged" % [short_money(got), short_money(goal)], 11, UiStyle.MUTED))
		var does := _does(seed, i)
		if does != "":
			col.add_child(_text("When funded: " + does, UiStyle.MUTED, 500, 12))
	for line in sim.regional.effects(seed.id):
		col.add_child(_fact("check", line, UiStyle.TEXT))

	var share := region.ledger.share(seed.id, me)
	var here := float(sim.regional.projects.get(seed.id, {}).get("benefit", 0.0))
	col.add_child(UiStyle.label("Your share %d%%  ·  Benefit here %d%%" % [roundi(share * 100.0), roundi(here * 100.0)],
		11, Brand.BRAND_CORAL if share > 0.0 else UiStyle.MUTED))
	if not region.ledger.is_unlocked(seed.id) and not st.is_empty():
		col.add_child(_fact("people", "Opens when the metro reaches %s people" % CitySim.money_text(Ledger.gate(seed.id)),
			UiStyle.MUTED))
	elif not st.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		for amount in PLEDGES:
			var b := _action("Pledge " + short_money(amount), amount == PLEDGES[-1], func(): _pledge(seed.id, amount))
			b.disabled = sim.economy.money < amount or not pledge_to.is_valid()
			b.tooltip_text = "Pledges are final. Your town pays only what the stage still needs."
			row.add_child(b)
	return card


func _pledge(id: String, amount: int) -> void:
	if pledge_to.is_valid() and sim.economy.money >= amount:
		pledge_to.call(id, float(amount))


static func _does(seed: Dictionary, i: int) -> String:
	return str(seed.stages[i].get("does", "")) if i >= 0 and i < seed.stages.size() else ""


## $100k, $1.2M.
static func short_money(v: float) -> String:
	if v >= 1_000_000.0:
		var m := v / 1_000_000.0
		return "$%sM" % (str(roundi(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m)
	if v >= 1000.0:
		return "$%dk" % roundi(v / 1000.0)
	return "$%d" % roundi(v)


# --- Services --------------------------------------------------------------

func _services() -> void:
	var asks := []
	var offers := []
	for q in sim.permits.listed(Permits.State.OPEN) + sim.permits.listed(Permits.State.SHELVED):
		if q.hub != "interlocal":
			continue
		if q.get("deal", {}).has("agreement"):
			offers.append(q)
		elif q.get("deal", {}).has("key"):
			asks.append(q)
	var waiting := region.ledger.agreements.values().filter(func(a):
		return a.status == "offered" and a.host == me and Interlocal.KINDS.has(a.service))
	var any := false
	if not offers.is_empty():
		any = true
		_list.add_child(UiStyle.label("OFFERS TO YOU", 11, UiStyle.MUTED))
		for q in offers:
			_list.add_child(_request(q, "Accept", "Turn down"))
	if not asks.is_empty():
		any = true
		_list.add_child(UiStyle.label("YOUR LEADERS WANT TO OFFER", 11, UiStyle.MUTED))
		for q in asks:
			_list.add_child(_request(q, "Send offer", "Not now"))
	if not waiting.is_empty():
		any = true
		_list.add_child(UiStyle.label("WAITING ON A NEIGHBOR", 11, UiStyle.MUTED))
		for a in waiting:
			var card := _plain_card()
			card.get_child(0).add_child(_text("%s for %s" % [Interlocal.KINDS[a.service].name.capitalize(), _town(a.client)],
				UiStyle.TEXT, 600))
			card.get_child(0).add_child(_fact("money", "+$%s a day if they accept" % CitySim.money_text(roundi(a.price_per_month)),
				UiStyle.MUTED))
			_list.add_child(card)
	if not sim.interlocal.deals.is_empty():
		any = true
		_list.add_child(UiStyle.label("SIGNED", 11, UiStyle.MUTED))
		var ids := sim.interlocal.deals.keys()
		ids.sort()
		for id in ids:
			_list.add_child(_deal(sim.interlocal.deals[id]))
	if not any:
		_list.add_child(_text("No shared services yet. When a neighbor joined by county road lacks a landfill, fire station, police or school you have, your leaders will offer to serve it, and neighbors can offer you theirs.",
			UiStyle.MUTED, 500, 12))


func _request(q: Dictionary, yes: String, no: String) -> Control:
	var card := _plain_card()
	var col: VBoxContainer = card.get_child(0)
	col.add_child(UiStyle.label(q.leader, 11, UiStyle.MUTED))
	col.add_child(_text(q.title, UiStyle.TEXT, 600))
	var pays: bool = q.deal.get("pays", false)
	col.add_child(_fact("money", ("Costs us $%s a day" if pays else "Brings in $%s a day") % CitySim.money_text(int(q.deal.fee)),
		UiStyle.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	row.add_child(_action(yes, true, func(): sim.apply({"type": "permit", "id": q.id, "answer": "approve"})))
	row.add_child(_action(no, false, func(): sim.apply({"type": "permit", "id": q.id, "answer": "deny"})))
	return card


func _deal(d: Dictionary) -> Control:
	var card := _plain_card()
	var col: VBoxContainer = card.get_child(0)
	var what: String = Interlocal.KINDS[d.kind].name
	var host: bool = d.role == "host"
	col.add_child(_text(("We give %s %s" % [d.other_name, what]) if host else ("%s gives us %s" % [d.other_name, what]),
		UiStyle.TEXT, 600))
	col.add_child(_fact("money", "%s$%s a day" % ["+" if host else "–", CitySim.money_text(int(d.fee))], UiStyle.MUTED))
	if int(d.left) >= 0:
		col.add_child(_text("Notice given: ends in about %d day%s" % [maxi(int(d.left), 1), "" if int(d.left) <= 1 else "s"],
			Brand.INK_FAINT, 500, 11))
	else:
		var b := _action("Give notice", false, func(): sim.apply({"type": "end_deal", "id": d.id}))
		b.tooltip_text = "Ends the deal after %d days' notice, as the agreement says." % Balance.INTERLOCAL_NOTICE
		col.add_child(b)
	return card


func _town(id: String) -> String:
	return str(region.cities[id].name) if region.cities.has(id) else "a neighbor"


# --- Look ------------------------------------------------------------------

func _plain_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	return card


func _fact(icon: String, s: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ic := Icon.new(icon, 14)
	ic.color = color
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := UiStyle.label(s, 12, UiStyle.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _action(label: String, primary: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	if primary:
		# The one primary action: coral, with dark text on it.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Brand.BRAND_CORAL.lightened(0.08 if state == "hover" else 0.0)
			if state == "disabled":
				box.bg_color = Color(Brand.BRAND_CORAL, 0.35)
			box.set_corner_radius_all(UiStyle.RADIUS_SM)
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			b.add_theme_stylebox_override(state, box)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(c, Brand.ON_CORAL)
	b.pressed.connect(on_press)
	return b


func _text(s: String, color := UiStyle.TEXT, weight := 500, px := 13) -> Label:
	var l := UiStyle.label(s, px, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 52
	return l


func _card_style() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(Brand.SURFACE_RAISED, 0.5)
	b.set_corner_radius_all(UiStyle.RADIUS_SM)
	b.border_color = Brand.LINE
	b.set_border_width_all(1)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


## Docked flush to the right edge: square, hairlines on the open sides.
func _style() -> StyleBoxFlat:
	var b := UiStyle.dock(true)
	b.border_width_left = 1
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 10
	return b
