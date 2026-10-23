class_name PermitPanel
extends PanelContainer
## Permit requests, from the bell in the top bar. Leaders of hubs around
## town (the railroad, the bus company...) ask here before they build
## through anything of yours. Click a request to see its plan on the map,
## then approve it, say no, or redraw the route and send it back: the
## leader re-costs your way and goes ahead if they can afford it.
##
## It never pops up. The bell shows how many are waiting; a request nobody
## answers is shelved after a week, and stays answerable under Shelved.

signal opened

const WIDTH := 340
## What each kind of hub is called on its card.
const HUB_NAMES := {"rail": "Railroad", "bus": "Bus company", "family": "Family business", "developer": "Land developer",
	"interlocal": "Shared service", "heritage": "Historical society", "owner": "Building owner", "farm": "Farm",
	"industry": "Resource company", "subdivision": "Home builder", "engineer": "City engineer"}
## Leader requests (asks of the town) by kind (LeaderAsks, Heritage).
const ASK_NAMES := {"abatement": "Company", "pave": "Farm", "signal": "Business", "festival": "Main Street",
	"district": "Historical society", "demolish": "Building owner"}

var sim: CitySim
var view := PermitView.new()

var _button: Button
var _badge := _Badge.new()
var _list := VBoxContainer.new()
var _selected := -1
## Which of a request's sites is shown (a request with options).
var _site := 0
var _editing := false
var _show_shelved := false
var _shown_key := ""
var _wait := 0.0


func setup(s: CitySim, game: Node, cam: CityCamera) -> void:
	sim = s
	view.setup(s, cam)
	game.add_child.call_deferred(view)
	sim.permits.changed.connect(_rebuild)
	view.route_edited.connect(func(_r, _h): _rebuild(true))


func _ready() -> void:
	add_theme_stylebox_override("panel", _style())
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var ic := Icon.new("permits", 16)
	ic.color = Brand.BRAND_MINT
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var title := UiStyle.label("PERMIT REQUESTS", 11, UiStyle.MUTED)
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
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)
	visible = false


## The bell for the top bar, with how many requests are waiting.
func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Permit requests"
	_button.custom_minimum_size = Vector2(34, 24)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(mid)
	mid.add_child(Icon.new("permits", 16))
	_badge.position = Vector2(20, 0)
	_button.add_child(_badge)
	_button.toggled.connect(func(on): open_panel() if on else close_panel())
	_update_badge()
	return _button


func open_panel() -> void:
	visible = true
	if _button:
		_button.set_pressed_no_signal(true)
	_rebuild()
	opened.emit()


func close_panel() -> void:
	visible = false
	_select(-1)
	if _button:
		_button.set_pressed_no_signal(false)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0
	_update_badge()
	if visible and not _editing:
		_rebuild()  # "shelved in 3 days" keeps counting down


func _update_badge() -> void:
	if sim == null or _button == null:
		return
	var n := sim.permits.listed(Permits.State.OPEN).size()
	_badge.count = n
	_button.tooltip_text = "Permit requests" if n == 0 else \
		"Permit requests: %d waiting on you" % n


func _select(id: int, site := 0) -> void:
	_selected = id
	_site = site
	_editing = false
	var req: Dictionary = sim.permits.requests.get(id, {})
	if req.has("options") and not req.options.is_empty():
		# One of the sites: its land, streets and the ghost of its homes.
		var o: Dictionary = req.options[clampi(_site, 0, req.options.size() - 1)]
		var shown := req.duplicate()
		shown.route = o.outline
		shown.ghost = o.get("ghost", [])
		shown.streets = o.get("streets", [])
		view.show_plan(shown)
		if view.cam:
			view.cam.fly_to(view.center())
	elif req.is_empty():
		_selected = -1
		view.hide_plan()
	elif req.get("shape", "route") == "deal":
		# A service deal has no plan to draw: look at the county road it uses.
		view.hide_plan()
		if view.cam and not req.route.is_empty():
			view.cam.fly_to(Vector3(req.route[0][0], 0.0, req.route[0][1]))
	else:
		view.show_plan(req)
		if view.cam:
			view.cam.fly_to(view.center())
	_rebuild()


func _answer(answer: String) -> void:
	var cmd := {"type": "permit", "id": _selected, "answer": answer}
	if sim.permits.requests.get(_selected, {}).has("options"):
		cmd.pick = _site
	if answer == "edit":
		cmd.route = view.route.duplicate(true)
	var id := _selected
	_editing = false
	view.set_editing(false)
	sim.apply(cmd)
	# Still open (too dear): keep showing it. Answered: let it go.
	if sim.permits.state_of(id) in [Permits.State.OPEN]:
		_select(id)
	else:
		_select(-1)


## Rebuilds the list (only when what it says has changed, so it holds still).
func _rebuild(force := false) -> void:
	if sim == null or not visible:
		_update_badge()
		return
	if _selected != -1 and not sim.permits.state_of(_selected) in [Permits.State.OPEN, Permits.State.SHELVED]:
		_selected = -1
		_editing = false
		view.hide_plan()
	var open := sim.permits.listed(Permits.State.OPEN)
	var shelved := sim.permits.listed(Permits.State.SHELVED)
	var key := "%s|%s|%d|%d|%s|%s|%d|%s" % [open.map(_card_key), shelved.map(_card_key), _selected, _site, _editing,
		_show_shelved, int(sim.tick_count / (CitySim.TICKS_PER_HOUR * 6)), str(sim.interlocal.deals)]
	if key == _shown_key and not force:
		return
	_shown_key = key
	for c in _list.get_children():
		c.queue_free()
	if open.is_empty():
		_list.add_child(_text("Nothing waiting on you. Leaders around town ask here before they build through anything of yours.",
			UiStyle.MUTED))
	for req in open:
		_list.add_child(_card(req))
	if not shelved.is_empty():
		var more := Button.new()
		more.flat = true
		more.focus_mode = Control.FOCUS_NONE
		more.text = ("▾ " if _show_shelved else "▸ ") + "Shelved (%d)" % shelved.size()
		more.tooltip_text = "Requests nobody answered in a week. You can still answer them."
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", UiStyle.MUTED)
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.pressed.connect(func():
			_show_shelved = not _show_shelved
			_rebuild())
		_list.add_child(more)
		if _show_shelved:
			for req in shelved:
				_list.add_child(_card(req))
	_agreements()
	_projects()
	_update_badge()


## Signed service deals with neighbor towns, each with a way to end it.
func _agreements() -> void:
	var ids := sim.interlocal.deals.keys()
	if ids.is_empty():
		return
	ids.sort()
	_list.add_child(UiStyle.label("SHARED SERVICES", 11, UiStyle.MUTED))
	for id in ids:
		var d: Dictionary = sim.interlocal.deals[id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_style(false))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var what: String = Interlocal.KINDS[d.kind].name
		var host: bool = d.role == "host"
		var title := ("We give %s %s" % [d.other_name, what]) if host else ("%s gives us %s" % [d.other_name, what])
		col.add_child(_text(title, UiStyle.TEXT, 600))
		var serving := int(d.offset) >= 0
		col.add_child(_fact("money", "%s$%s a month%s" % ["+" if host else "–", CitySim.money_text(int(d.fee)),
			"" if serving else " (on hold: nothing to serve from)"], UiStyle.MUTED, not serving))
		if int(d.left) >= 0:
			col.add_child(_text("Notice given: ends in about %s" % _months(maxi(int(d.left), 1) * 24 * CitySim.TICKS_PER_HOUR),
				Brand.INK_FAINT, 500, 11))
		else:
			var row := HBoxContainer.new()
			col.add_child(row)
			row.add_child(_action("Give notice", false, func(): sim.apply({"type": "end_deal", "id": id})))
			row.tooltip_text = "Ends the deal after %s' notice, as the agreement says." % _months(Balance.INTERLOCAL_NOTICE * 24 * CitySim.TICKS_PER_HOUR)
		_list.add_child(card)


func _card_key(r: Dictionary) -> String:
	return "%d:%d:%d:%d" % [r.id, r.state, r.cost, r.edits]


## One request: who's asking, what for, what it costs, what it touches.
func _card(req: Dictionary) -> Control:
	var picked: bool = req.id == _selected
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(picked))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not picked:
			_select(req.id))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 6)
	col.add_child(who)
	var name := UiStyle.label(req.leader if req.leader != "" else "A leader in town", 13, UiStyle.TEXT, 600)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(name)
	var ask := str(req.get("ask", ""))
	who.add_child(UiStyle.label(ASK_NAMES.get(ask, "Leader") if ask != "" else HUB_NAMES.get(req.hub, str(req.hub).capitalize()),
		11, UiStyle.MUTED))
	col.add_child(_text(req.title, UiStyle.TEXT, 600))
	if req.why != "" and (picked or req.state == Permits.State.OPEN):
		col.add_child(_text(req.why, UiStyle.MUTED, 500, 12))
	if ask != "":
		# An ask of the town: what a yes and a no each bring.
		col.add_child(_fact("check", "If yes: " + str(req.yes), UiStyle.TEXT, false))
		col.add_child(_fact("close", "If no: " + str(req.no), UiStyle.MUTED, false))
		if req.state == Permits.State.OPEN:
			var wait := Permits.SHELVE_AFTER - (sim.tick_count - int(req.filed))
			col.add_child(_text("Shelved in " + _days(wait) + " if you don't answer", Brand.INK_FAINT, 500, 11))
		if picked:
			var yes_no := HBoxContainer.new()
			yes_no.add_theme_constant_override("separation", 6)
			col.add_child(yes_no)
			yes_no.add_child(_action("Yes", true, func(): _answer("approve")))
			yes_no.add_child(_action("No", false, func(): _answer("deny")))
		return card

	if req.has("options"):
		_sites(col, req, picked)
		return card

	var hits: Dictionary = view.hits if picked and _editing else req.hits
	var cost: int = sim.permits.cost_of(sim, req, view.route, hits) if picked and _editing else req.cost
	var deal: Dictionary = req.get("deal", {})
	if not deal.is_empty():
		# A service deal: what it costs or brings in each month, and nothing built.
		col.add_child(_fact("money", ("Costs us $%s a month" if deal.get("pays", false) else "Brings in $%s a month")
			% CitySim.money_text(int(deal.fee)), UiStyle.MUTED, false))
		col.add_child(_fact("check", "Builds nothing. Either town can end it with %s' notice" % _months(Balance.INTERLOCAL_NOTICE * 24 * CitySim.TICKS_PER_HOUR),
			Brand.POSITIVE, false))
		if req.state == Permits.State.OPEN:
			var left := Permits.SHELVE_AFTER - (sim.tick_count - int(req.filed))
			col.add_child(_text("Both towns must approve. Shelved in " + _days(left) + " if you don't answer",
				Brand.INK_FAINT, 500, 11))
		if picked:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			col.add_child(row)
			row.add_child(_action("Approve", true, func(): _answer("approve")))
			row.add_child(_action("Deny", false, func(): _answer("deny")))
		return card
	var money := "%s$%s" % ["New cost " if picked and _editing else "Cost ", CitySim.money_text(cost)]
	if req.budget > 0:
		money += "  ·  they can spend $" + CitySim.money_text(req.budget)
	var over: bool = req.budget > 0 and cost > req.budget
	col.add_child(_fact("money", money, Brand.WARNING if over else UiStyle.MUTED, over))
	if req.get("shape", "route") == "area":
		var acres := Permits.area_of(view.route if picked and _editing else req.route) / 4046.86
		var what: String = req.change if req.change != "" else "Land"
		col.add_child(_fact("zones", "%s, %s acres" % [what, _acres(acres)], UiStyle.TEXT, false))
	var roads: int = hits.get("roads", []).size()
	if roads > 0:
		var verb := "Takes in" if req.get("shape", "route") == "area" else "Crosses"
		col.add_child(_fact("road", "%s %d of your road%s" % [verb, roads, "" if roads == 1 else "s"], Brand.WARNING, true))
	var gone: Array = hits.get("buildings", [])
	if not gone.is_empty():
		col.add_child(_fact("bulldoze", "Removes your " + _names(gone), Brand.CRITICAL, true))
	if roads == 0 and gone.is_empty():
		col.add_child(_fact("check", "Touches nothing of yours", Brand.POSITIVE, false))
	if req.note != "":
		col.add_child(_text(req.note, Brand.BRAND_MINT, 500, 12))
	if req.state == Permits.State.OPEN and not _editing:
		var left := Permits.SHELVE_AFTER - (sim.tick_count - int(req.filed))
		col.add_child(_text("Shelved in " + _days(left) + " if you don't answer", Brand.INK_FAINT, 500, 11))

	if not picked:
		return card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	if _editing:
		col.move_child(row, col.get_child_count() - 1)
		col.add_child(_text(("Drag a corner of the land on the map. Drag a small dot to add a corner; right click one to take it out."
			if req.get("shape", "route") == "area" else
			"Drag a bend on the map. Drag a small dot to add one; right click a bend to take it out."),
			UiStyle.MUTED, 500, 11))
		var first := str(req.leader).get_slice(" ", 0)
		row.add_child(_action("Send to " + (first if first != "" else "them"), true, func(): _answer("edit")))
		row.add_child(_action("Reset", false, func(): view.reset_route()))
		row.add_child(_action("Cancel", false, func():
			_editing = false
			view.reset_route()
			view.set_editing(false)
			_rebuild(true)))
	else:
		row.add_child(_action("Approve", true, func(): _answer("approve")))
		row.add_child(_action("Edit area" if req.get("shape", "route") == "area" else "Edit route", false, func():
			_editing = true
			view.set_editing(true)
			_rebuild(true)))
		row.add_child(_action("Deny", false, func(): _answer("deny")))
	return card


## A request with a choice of sites (a home builder's subdivision): a tab
## for each site, what it is, what it costs the builder, and what a yes
## means for the town. Approving builds the site shown.
func _sites(col: VBoxContainer, req: Dictionary, picked: bool) -> void:
	var opts: Array = req.options
	var i := clampi(_site if picked else 0, 0, opts.size() - 1)
	var o: Dictionary = opts[i]
	if picked and opts.size() > 1:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 4)
		col.add_child(tabs)
		for k in opts.size():
			var b := Button.new()
			b.text = ("Option " if req.hub == CityEngineer.HUB else "Site ") + str(opts[k].get("letter", k + 1))
			b.toggle_mode = true
			b.button_pressed = k == i
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = str(opts[k].get("name", ""))
			b.pressed.connect(func(): _select(int(req.id), k))
			tabs.add_child(b)
	if req.hub == CityEngineer.HUB:
		_fix(col, req, o, i, picked)
		return
	var e: Dictionary = o.get("effects", {})
	col.add_child(_text("%s: %d homes in %d phases, about %s years" % [o.get("name", "Site"), int(o.homes), int(o.phases),
		_num(float(e.get("years", 0)))], UiStyle.TEXT, 600, 12))
	col.add_child(_fact("money", "The builder pays $%s for %s acres and the streets" % [CitySim.money_text(int(o.cost)),
		_acres(float(e.get("acres", 0)))], UiStyle.MUTED, false))
	if bool(o.get("planned", false)):
		col.add_child(_fact("homes", "Inside your land use plan for homes: each phase is approved faster", Brand.POSITIVE, false))
	elif not sim.land_plan.outlines.is_empty():
		col.add_child(_fact("views", "Not in your land use plan", UiStyle.MUTED, false))
	effects(col, e)
	# (Water and power are in the lines above.)
	needs(col, o.get("needs", {}), "EACH PHASE NEEDS", ["water", "power"])
	if req.state == Permits.State.OPEN:
		var left := Permits.SHELVE_AFTER - (sim.tick_count - int(req.filed))
		col.add_child(_text("Shelved in " + _days(left) + " if you don't answer", Brand.INK_FAINT, 500, 11))
	if not picked:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	row.add_child(_action("Build site " + str(o.get("letter", i + 1)), true, func(): _answer("approve")))
	row.add_child(_action("Say no", false, func(): _answer("deny")))


## One of the city engineer's fixes: what it does and what the town pays.
func _fix(col: VBoxContainer, req: Dictionary, o: Dictionary, i: int, picked: bool) -> void:
	col.add_child(_text(str(o.get("name", "")), UiStyle.TEXT, 600, 12))
	col.add_child(_fact("money", "The town pays $%s" % CitySim.money_text(int(o.cost)), UiStyle.TEXT, int(o.cost) > sim.economy.money))
	for l in o.get("lines", []):
		col.add_child(_fact("road", str(l), UiStyle.MUTED, false))
	if req.state == Permits.State.OPEN:
		var left := Permits.SHELVE_AFTER - (sim.tick_count - int(req.filed))
		col.add_child(_text("Shelved in " + _days(left) + " if you don't answer", Brand.INK_FAINT, 500, 11))
	if not picked:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var label := "Do it" if req.options.size() == 1 else "Do " + str(o.get("letter", i + 1))
	row.add_child(_action(label, true, func(): _answer("approve")))
	row.add_child(_action("Say no", false, func(): _answer("deny")))


## "If yes": what a request means for the town, from its effects (any
## request can carry them; see Subdivisions.effects_of).
func effects(col: VBoxContainer, e: Dictionary) -> void:
	if e.is_empty():
		return
	col.add_child(UiStyle.label("IF YOU SAY YES", 10, UiStyle.MUTED))
	if e.has("people"):
		col.add_child(_fact("people", "About %s new residents, %s school-age kids" % [_count(int(e.people)), _count(int(e.get("kids", 0)))],
			UiStyle.TEXT, false))
	if e.has("trips"):
		col.add_child(_fact("car", "%s more car trips a day, about %s at rush hour" % [_count(int(e.trips)), _count(int(e.get("peak", 0)))],
			UiStyle.TEXT, false))
	for u in ["water", "power"]:
		if e.has(u):
			var pct := int(e[u])
			if pct < 0:
				col.add_child(_fact(u, "No %s service out there yet: homes won't fill until you bring it" % u, Brand.WARNING, true))
			else:
				var over := pct > 100
				col.add_child(_fact(u, "%s use goes to %d%% of what the town has%s" % [u.capitalize(), pct, " (more than you have)" if over else ""],
					Brand.WARNING if over else UiStyle.TEXT, over))
	if e.has("upkeep"):
		col.add_child(_fact("road", "The town takes over the streets: $%s a year to keep up" % CitySim.money_text(int(e.upkeep)),
			UiStyle.TEXT, false))
	if e.has("repave"):
		col.add_child(_fact("road", "In about %d years they wear out: $%s to resurface them, on the town" % [Balance.STREET_LIFE_YEARS,
			CitySim.money_text(int(e.repave))], UiStyle.TEXT, false))
	if e.has("taxes"):
		col.add_child(_fact("money", "About $%s a year in property tax once it's built out" % CitySim.money_text(int(e.taxes)),
			Brand.POSITIVE, false))


## What a project needs from the town's other leaders, each line marked
## fine, slower and dearer, or stopped (see ProjectNeeds), leaving out the
## lines for `skip` (icons) and the sum when `total` is false.
func needs(col: VBoxContainer, n: Dictionary, heading: String, skip := [], total := true) -> void:
	if n.is_empty():
		return
	col.add_child(UiStyle.label(heading, 10, UiStyle.MUTED))
	for l in n.lines:
		if str(l[1]) in skip:
			continue
		var st := int(l[0])
		var color: Color = UiStyle.TEXT if st == ProjectNeeds.State.OK else (Brand.WARNING if st == ProjectNeeds.State.SLOW else Brand.CRITICAL)
		col.add_child(_fact(str(l[1]), str(l[2]), color, st != ProjectNeeds.State.OK))
	if total and (int(n.extra) > 0 or float(n.slow) > 0.0):
		col.add_child(_text("The builder pays $%s more and it takes about %d%% longer. Not the town's money." % [
			CitySim.money_text(int(n.extra)), roundi(100.0 * float(n.slow))], Brand.INK_FAINT, 500, 11))


## Subdivisions still building: where each one is and what it's waiting on.
func _projects() -> void:
	var ids := sim.subdivisions.active.keys()
	ids.sort()
	var going := ids.filter(func(id): return int(sim.subdivisions.active[id].phase) < int(sim.subdivisions.active[id].site.phases))
	if going.is_empty():
		return
	_list.add_child(UiStyle.label("PROJECTS", 11, UiStyle.MUTED))
	for id in going:
		var a: Dictionary = sim.subdivisions.active[id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_style(false))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		col.add_child(_text("%s: phase %d of %d" % [a.name, int(a.phase), int(a.site.phases)], UiStyle.TEXT, 600))
		var n: Dictionary = a.get("needs", {})
		if not n.is_empty() and n.hold:
			col.add_child(_fact("seasons", "Waiting: " + str(n.hold_why), Brand.WARNING, true))
		elif int(a.phase) > 0:
			var fill: Vector2i = sim.subdivisions.sold(sim, id)
			col.add_child(_fact("homes", "%d of %d lots built; the next phase starts at %d%%" % [fill.x, fill.y,
				roundi(Balance.SUBDIV_NEXT_PHASE_FILL * 100)], UiStyle.MUTED, false))
		needs(col, n, "LAST CHECK WITH YOUR LEADERS", [], false)
		if int(a.get("extra", 0)) > 0:
			col.add_child(_text("Shortages have cost the builder $%s so far" % CitySim.money_text(int(a.extra)), Brand.INK_FAINT, 500, 11))
		_list.add_child(card)


static func _count(n: int) -> String:
	return CitySim.money_text(n)


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


## "home", "2 homes and a farmhouse"...
static func _names(list: Array) -> String:
	var counts := {}
	var order := []
	for b in list:
		if not counts.has(b.name):
			counts[b.name] = 0
			order.append(b.name)
		counts[b.name] += 1
	var parts := order.map(func(n): return n if counts[n] == 1 else "%d %ss" % [counts[n], n])
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, -1)) + " and " + parts[-1]


static func _acres(a: float) -> String:
	return "%.1f" % a if a < 10.0 else str(roundi(a))


## Game months (a game day settles a month), for terms like notice.
static func _months(ticks: int) -> String:
	var m := roundi(float(ticks) / (24 * CitySim.TICKS_PER_HOUR))
	return "%d month%s" % [m, "" if m == 1 else "s"]


static func _days(ticks: int) -> String:
	var hours := maxi(ticks, 0) / CitySim.TICKS_PER_HOUR
	if hours < 24:
		return "%d hour%s" % [maxi(hours, 1), "" if hours <= 1 else "s"]
	var days := roundi(hours / 24.0)
	return "%d day%s" % [days, "" if days == 1 else "s"]


## A small fact line; warnings get the warning icon as the brand asks.
func _fact(icon: String, s: String, color: Color, warn: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ic := Icon.new("warning" if warn else icon, 14)
	ic.color = color
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := UiStyle.label(s, 12, color if warn else UiStyle.TEXT)
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
		for state in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Brand.BRAND_CORAL.lightened(0.08 if state == "hover" else 0.0)
			box.set_corner_radius_all(UiStyle.RADIUS_SM)
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			b.add_theme_stylebox_override(state, box)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, Brand.ON_CORAL)
	b.pressed.connect(on_press)
	return b


func _text(s: String, color := UiStyle.TEXT, weight := 500, px := 13) -> Label:
	var l := UiStyle.label(s, px, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 52
	return l


func _card_style(picked: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Brand.SURFACE_RAISED if picked else Color(Brand.SURFACE_RAISED, 0.5)
	b.set_corner_radius_all(UiStyle.RADIUS_SM)
	b.border_color = Brand.BRAND_MINT if picked else Brand.LINE
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


## How many requests wait: a small mint pill on the bell. Never coral
## (coral is you) and never red (nothing is wrong).
class _Badge extends Control:
	var count := 0:
		set(v):
			count = v
			visible = v > 0
			queue_redraw()

	func _init() -> void:
		size = Vector2(13, 13)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		draw_circle(size * 0.5, 6.5, Brand.BRAND_MINT, true, -1.0, true)
		var f := Brand.ui(700)
		var s := str(count) if count < 10 else "9+"
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2((size.x - w) * 0.5, 10.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Brand.ON_CORAL)
