class_name HubSliders
extends VBoxContainer
## A hub's Funding and Growth sliders, at the bottom of its info panel (the
## same ones as on the Economy page). Growth is also your word to its leader
## (Brawn: the permit idea works both ways): Hold off, Your call, Grow. Hubs
## whose leaders file permits (sim.permits.locators has their kind) also get
## the pre-approve row, so they needn't ask about work near them.

signal open_economy

var sim: CitySim
var hub := ""        # the selection's type: its sliders' key is hub:hub_id
var hub_id := 0
var leader := ""     # its kind in Permits (see hub_of), for its leader's word
var _sliders := {}   # slider -> StepSlider
var _grants := {}    # metres -> Button
var _said := UiStyle.label("", 11, UiStyle.MUTED)


## True if this kind of selection is a hub with sliders.
static func takes(s: CitySim, selection: Dictionary) -> bool:
	if selection.is_empty():
		return false
	var kind := str(selection.get("type", ""))
	return s.hub_area("%s:%d" % [kind, int(selection.get("id", 0))]) != "" or s.permits.locators.has(hub_of(s, selection))


## The Permits hub kind for a selection: its type, except for services that
## run themselves as a hub (a bus depot is a "service" you can select).
static func hub_of(s: CitySim, selection: Dictionary) -> String:
	var type := str(selection.get("type", ""))
	if type == "service" and s.buses.depots.has(int(selection.get("id", -1))):
		return "bus_depot"
	if type == "service" and s.taxis.companies.has(int(selection.get("id", -1))):
		return "taxi"
	return type


func setup(s: CitySim, kind: String, id: int) -> void:
	sim = s
	hub = kind
	hub_id = id
	leader = hub_of(s, {"type": kind, "id": id})
	_sync()


func _key() -> String:
	return "%s:%d" % [hub, hub_id]


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(HSeparator.new())
	var head := HBoxContainer.new()
	add_child(head)
	var title := UiStyle.label("FUNDING AND GROWTH", 10, UiStyle.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var all := Button.new()
	all.text = "Economy page"
	all.flat = true
	all.focus_mode = Control.FOCUS_NONE
	all.add_theme_font_size_override("font_size", 11)
	all.tooltip_text = "See and set every area and hub in one place"
	all.pressed.connect(func(): open_economy.emit())
	head.add_child(all)
	var area := sim.hub_area(_key())
	var sliders: Array = Policies.AREAS[area].sliders.duplicate() if area != "" else []
	if sim.permits.locators.has(leader) and not "growth" in sliders:
		sliders.append("growth")
	for sl in sliders:
		var tip: String = Policies.AREAS[area].get(sl, "Your word to the leader.") if area != "" else "Your word to the leader."
		if sl == "growth" and sim.permits.locators.has(leader):
			tip += " Hold also tells its leader to stop asking for permits."
		var row := StepSlider.new(sl, sl.capitalize(), tip)
		if area == "" or leader != hub and sl == "growth":
			# A leader the Economy page doesn't list on its own: Growth is just their stance.
			row.picked.connect(func(step): sim.apply({"type": "guide", "hub": leader, "hub_id": hub_id,
				"stance": Policies.stance(maxi(step, 0) if step >= 0 else 2),
				"grant": int(sim.permits.guidance(leader, hub_id).grant)}))
		else:
			row.picked.connect(func(step): sim.apply({"type": "policy", "scope": _key(), "slider": sl, "step": step}))
		add_child(row)
		_sliders[sl] = row
	if sim.permits.locators.has(leader):
		add_child(UiStyle.label("PRE-APPROVE PERMITS WITHIN", 10, UiStyle.MUTED))
		var grants := HBoxContainer.new()
		grants.add_theme_constant_override("separation", 4)
		add_child(grants)
		for m in Permits.GRANTS:
			var b := _toggle("None" if m == 0 else "%d m" % m,
				"They ask about everything" if m == 0 else "Requests within %d m of them go straight through" % m)
			b.pressed.connect(func():
				sim.apply({"type": "guide", "hub": leader, "hub_id": hub_id,
					"stance": str(sim.permits.guidance(leader, hub_id).stance), "grant": m})
				_sync())
			grants.add_child(b)
			_grants[m] = b
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_said.custom_minimum_size.x = 230
	add_child(_said)
	sim.permits.changed.connect(_sync)
	sim.policies.changed.connect(_sync)
	_sync()


func _sync() -> void:
	if sim == null or _sliders.is_empty() and _grants.is_empty():
		return
	var key := _key()
	var area := sim.hub_area(key)
	var follows: String = Policies.AREAS[area].name if area != "" else "the town"
	var g := sim.permits.guidance(leader, hub_id)
	for sl in _sliders:
		if area == "" or leader != hub and sl == "growth":
			_sliders[sl].show_step(Policies.growth_for(str(g.stance), Policies.STANDARD), false)
		else:
			_sliders[sl].show_step(sim.policies.step(sl, area, key), sim.policies.own(key, sl) >= 0, follows)
	for m in _grants:
		_grants[m].set_pressed_no_signal(m == int(g.grant))
	_said.text = "" if int(g.set) < 0 else "You told them on day %d." % (int(g.set) / (24 * CitySim.TICKS_PER_HOUR) + 1)


func _toggle(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	return b
