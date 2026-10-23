class_name EconomyPage
extends PanelContainer
## The Economy page (Brawn, 2026-10-22: money is a limiter, not the game).
## Docked to the left edge like Cities: Skylines 2's panels, it shows the
## town's cash and whether it's up or down each month, then every area of
## town and every hub in it, each with broad Funding and Growth sliders.
## Taxes run at normal rates on their own; there's nothing to fiddle.
##
## The town's sliders set the default; an area follows the town and a hub
## its area until you move its own slider (↺ puts it back).

const GOOD := Brand.POSITIVE
const BAD := Brand.CRITICAL
const WIDTH := 430.0

signal closed

var sim: CitySim

var _cash := UiStyle.label("", 22, UiStyle.TEXT, 700)
var _net := UiStyle.label("", 14, UiStyle.TEXT, 600)
var _short := UiStyle.label("", 12, Brand.WARNING)
var _lines := {}        # budget key -> value Label
var _grant := UiStyle.label("", 11, UiStyle.MUTED)
var _identity := UiStyle.label("", 15, UiStyle.TEXT, 600)
var _sectors := UiStyle.label("", 11, UiStyle.MUTED)
var _town := {}         # slider -> StepSlider
var _areas := VBoxContainer.new()
var _open_areas := {}   # area -> true while expanded
var _area_rows := {}    # area -> {"sliders": {slider: StepSlider}, "sum": Label, "hubs": VBoxContainer, "arrow": Button}
var _hub_rows := {}     # hub key -> {slider: StepSlider}
var _hub_sig := {}      # area -> the hub list it was drawn for
var _wait := 0.0


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.dock(false))
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(Icon.new("money", 22))
	var title := UiStyle.title("Economy", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 14)  # room for the scrollbar
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	gutter.add_child(body)

	# Money: cash, this month up or down, and where it comes from.
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 12)
	body.add_child(money)
	money.add_child(_cash)
	_net.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net.size_flags_vertical = Control.SIZE_SHRINK_END
	money.add_child(_net)
	_short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_short)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 1)
	body.add_child(grid)
	for entry in [["taxes", "Property taxes"], ["fees", "Water and sewer bills"], ["upkeep", "Road upkeep"],
			["services", "Services, parks, garbage, cemeteries"], ["education", "Schools and colleges"],
			["care", "Street care"],
			["support", "Farm and business aid"], ["deals", "Services shared with neighbors"], ["region", "Regional projects"]]:
		var l := UiStyle.label(entry[1], 12, UiStyle.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var v := UiStyle.label("", 12)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		_lines[entry[0]] = v
	var note := UiStyle.label("Taxes run at normal rates on their own. One day settles a month.", 11, UiStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	body.add_child(_grant)

	# What kind of town this is, and what's rising (TownCulture).
	body.add_child(HSeparator.new())
	body.add_child(UiStyle.label("TOWN CHARACTER", 10, UiStyle.MUTED))
	body.add_child(_identity)
	_sectors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_sectors)

	# The whole town: the default every area follows.
	body.add_child(HSeparator.new())
	var town_head := HBoxContainer.new()
	body.add_child(town_head)
	var th := UiStyle.label("WHOLE TOWN", 10, UiStyle.MUTED)
	th.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	town_head.add_child(th)
	var reset := Button.new()
	reset.text = "Everything follows the town"
	reset.flat = true
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_font_size_override("font_size", 11)
	reset.tooltip_text = "Clear every area's and hub's own setting"
	reset.pressed.connect(func(): sim.apply({"type": "policy_reset", "scope": "city"}))
	town_head.add_child(reset)
	for sl in Policies.SLIDERS:
		var row := StepSlider.new(sl, sl.capitalize(),
			"The town's default. Every area follows it unless you set the area's own." , 64.0, false)
		row.picked.connect(func(step): sim.apply({"type": "policy", "scope": "city", "slider": sl,
			"step": maxi(step, 0)}))
		body.add_child(row)
		_town[sl] = row

	body.add_child(HSeparator.new())
	body.add_child(UiStyle.label("AREAS AND HUBS", 10, UiStyle.MUTED))
	_areas.add_theme_constant_override("separation", 4)
	body.add_child(_areas)
	for area in Policies.AREAS:
		_build_area(area)
	sim.policies.changed.connect(_sync_sliders)


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		refresh()


## Brings every number and slider up to date.
func refresh() -> void:
	_wait = 0.5
	if sim == null or _lines.is_empty():
		return
	var e := sim.economy
	_cash.text = "$" + CitySim.money_text(e.money)
	_cash.add_theme_color_override("font_color", UiStyle.TEXT if e.money >= 0 else BAD)
	var net := e.monthly_net()
	_net.text = "%s $%s this month" % ["▲ Up" if net >= 0 else "▼ Down", CitySim.money_text(absi(net))]
	_net.add_theme_color_override("font_color", GOOD if net >= 0 else BAD)
	_short.text = "" if e.money >= 0 else \
		"Money is short. The town can't afford new hubs, and its own hubs won't take more land, until it's back in the black."
	_short.visible = e.money < 0
	var taxes := 0
	for z in e.budget.income:
		taxes += int(e.budget.income[z])
	_money_line("taxes", taxes)
	_money_line("fees", int(e.budget.fees))
	_money_line("upkeep", -int(e.budget.upkeep))
	_money_line("services", -int(e.budget.services))
	_money_line("education", -int(e.budget.get("education", 0)))
	_money_line("care", -int(e.budget.get("care", 0)))
	_money_line("support", -int(e.budget.get("support", 0)))
	_money_line("deals", int(e.budget.get("deals", 0)))
	_money_line("region", int(e.budget.get("region", 0)))
	_grant.text = "" if e.milestone >= Economy.MILESTONES.size() else \
		"Next grant: $%s at %s people" % [CitySim.money_text(Economy.MILESTONES[e.milestone][1]),
		CitySim.money_text(Economy.MILESTONES[e.milestone][0])]
	var who := character(sim.culture)
	_identity.text = who[0]
	_sectors.text = who[1]
	for area in _area_rows:
		_area_rows[area].sum.text = _summary(area)
		if _open_areas.has(area) and _hub_sig.get(area, []) != hubs_in(area):
			_fill_hubs(area)
	_sync_sliders()


## Sector names for the town character breakdown.
const SECTOR_NAMES := {"farm": "Farming", "mining": "Coal and oil", "timber": "Timber",
	"manufacturing": "Manufacturing", "trade": "Shops and trade", "office": "Banks and offices",
	"campus": "Colleges and hospitals", "transport": "Rail and power"}


## [the town's title, a few lines on its strongest trades]: how many times
## the US share of jobs each one has (its location quotient) and whether
## it's rising or fading against what the town is known for.
static func character(c: TownCulture) -> Array:
	if c.shares.is_empty():
		return ["Too small for a reputation yet", "Once a few hundred people work here, the county will know what kind of town this is."]
	var title := c.title() if c.title() != "" else "A town of all trades"
	var ranked: Array = TownCulture.SECTORS.keys()
	ranked.sort_custom(func(a, b): return c.lq(a) > c.lq(b))
	var lines := []
	for k in ranked.slice(0, 3):
		var m := c.momentum(k)
		var trend := "▲ rising" if m > 0.1 else ("▼ fading" if m < -0.1 else "steady")
		lines.append("%s: %.1f× the US share of jobs, %s" % [SECTOR_NAMES.get(k, k), c.lq(k), trend])
	if c.identity != "":
		lines.append("Known for it since year %d." % (c.since / 12 + 1))
	return [title, "\n".join(lines)]


func _money_line(key: String, v: int) -> void:
	_lines[key].text = ("+$" if v > 0 else ("–$" if v < 0 else "$")) + CitySim.money_text(absi(v))
	_lines[key].add_theme_color_override("font_color", GOOD if v > 0 else (UiStyle.TEXT if v == 0 else UiStyle.MUTED))


# --- Areas ---------------------------------------------------------------------

func _build_area(area: String) -> void:
	var a: Dictionary = Policies.AREAS[area]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_areas.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var arrow := Button.new()
	arrow.flat = true
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(20, 20)
	arrow.tooltip_text = "Show each one"
	head.add_child(arrow)
	head.add_child(Icon.new(a.icon, 18))
	var name_label := UiStyle.label(a.name, 13, UiStyle.TEXT, 600)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var sum := UiStyle.label("", 11, UiStyle.MUTED)
	head.add_child(sum)
	var sliders := {}
	for sl in a.sliders:
		var row := StepSlider.new(sl, sl.capitalize(), a[sl], 64.0)
		row.picked.connect(func(step): sim.apply({"type": "policy", "scope": "area:" + area, "slider": sl, "step": step}))
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 26)
		pad.add_child(row)
		box.add_child(pad)
		sliders[sl] = row
	var hubs := VBoxContainer.new()
	hubs.add_theme_constant_override("separation", 2)
	hubs.visible = false
	box.add_child(hubs)
	_area_rows[area] = {"sliders": sliders, "sum": sum, "hubs": hubs, "arrow": arrow}
	arrow.text = "▸"
	arrow.disabled = not _has_hubs(area)
	if arrow.disabled:
		arrow.modulate.a = 0.0
	arrow.pressed.connect(func():
		if _open_areas.has(area):
			_open_areas.erase(area)
		else:
			_open_areas[area] = true
		hubs.visible = _open_areas.has(area)
		arrow.text = "▾" if hubs.visible else "▸"
		if hubs.visible:
			_fill_hubs(area))


## Areas made of single hubs (farms, sites...) open up into them. Homes,
## shops and factories are many small buildings, so they set as one.
static func _has_hubs(area: String) -> bool:
	return not area in ["homes", "shops", "factories"]


## The hub keys in an area, sorted, e.g. ["farm:1", "farm:4"].
func hubs_in(area: String) -> Array:
	var out := []
	match area:
		"farms":
			for id in sim.farms.farms:
				out.append("farm:%d" % id)
		"resources":
			for id in sim.industry.sites:
				out.append("industry:%d" % id)
		"utilities", "public", "health":
			for id in sim.services.buildings:
				if Services.area_of(sim.services.buildings[id].kind) == area:
					out.append(sim.services.key_of(id))
		"transit":
			for id in sim.buses.depots:
				if sim.services.buildings.has(id):
					out.append("bus_depot:%d" % id)
		"water":
			for id in sim.services.water.utilities:
				out.append("water:%d" % id)
		"mail":
			for id in sim.mail.offices:
				out.append("post_office:%d" % id)
		"power":
			for id in sim.power.sites:
				out.append("power:%d" % id)
		"warehouses":
			for id in sim.warehouses.buildings:
				out.append("warehouse:%d" % id)
		"taxis":
			for id in sim.taxis.companies:
				if sim.services.buildings.has(id):
					out.append("taxi:%d" % id)
		"telecom":
			for id in sim.telecom.companies:
				out.append("telecom:%d" % id)
		"waste", "cemetery":
			for id in sim.hubs.hubs:
				if CivicHubs.area_of(sim.hubs.hubs[id].kind) == area:
					out.append("hub:%d" % id)
		"parks":
			for id in sim.parks.sites:
				out.append("park:%d" % id)
		"schools":
			for id in sim.education.campuses:
				out.append("campus:%d" % id)
		"banks":
			for id in sim.banks.banks:
				out.append("bank:%d" % id)
	out.sort_custom(func(x, y): return int(x.get_slice(":", 1)) < int(y.get_slice(":", 1)))
	return out


func _fill_hubs(area: String) -> void:
	var box: VBoxContainer = _area_rows[area].hubs
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for k in _hub_rows.keys():
		if sim.hub_area(k) == area or sim.hub_area(k) == "":
			_hub_rows.erase(k)
	var keys := hubs_in(area)
	_hub_sig[area] = keys
	if keys.is_empty():
		var none := UiStyle.label("None built yet.", 11, UiStyle.MUTED)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 26)
		pad.add_child(none)
		box.add_child(pad)
		return
	for key in keys:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 26)
		pad.add_theme_constant_override("margin_top", 2)
		pad.add_child(card)
		box.add_child(pad)
		var title := UiStyle.label(hub_name(key), 12, UiStyle.TEXT, 600)
		card.add_child(title)
		var rows := {}
		for sl in Policies.AREAS[area].sliders:
			# Growth is a word to a leader: a nursing home or daycare has none.
			if sl == "growth" and key.begins_with("service:"):
				continue
			var row := StepSlider.new(sl, sl.capitalize(), Policies.AREAS[area][sl], 56.0)
			row.picked.connect(func(step): sim.apply({"type": "policy", "scope": key, "slider": sl, "step": step}))
			card.add_child(row)
			rows[sl] = row
		_hub_rows[key] = rows
	_sync_sliders()


## A short name for a hub on the page.
func hub_name(key: String) -> String:
	var id := int(key.get_slice(":", 1))
	match key.get_slice(":", 0):
		"farm":
			var f: Dictionary = sim.farms.farms[id]
			return "%s farm %d  ·  %d acres" % [str(f.crop).capitalize(), id, roundi(f.cells.size() * Farms.ACRES_PER_CELL)]
		"industry":
			var s: Dictionary = sim.industry.sites[id]
			return "%s %d  ·  %d %ss" % [Industry.KINDS[s.kind].name, id, s.pads.size(), Industry.KINDS[s.kind].pad]
		"service":
			return "%s %d  ·  $%s a month" % [Services.KINDS[sim.services.buildings[id].kind].name, id,
				CitySim.money_text(sim.services.upkeep_of(id))]
		"bus_depot":
			return "Bus depot %d  ·  $%s a month" % [id, CitySim.money_text(int(sim.services.buildings[id].get("subsidy", 0)))]
		"water":
			var u: Dictionary = sim.services.water.utilities[id]
			return "%s Water and Sewer  ·  $%s a month" % [str(u.name).get_slice(" ", 1), CitySim.money_text(int(u.subsidy))]
		"post_office":
			var h: Dictionary = sim.mail.offices[id]
			return "Post office %d  ·  $%s a month" % [id, CitySim.money_text(int(Balance.MAIL_FUNDING[h.funding].monthly))]
		"power":
			var p: Dictionary = sim.power.sites[id]
			var k: Dictionary = Power.PLANTS[p.plant]
			return "%s %d  ·  %d %s%s" % [k.name, id, p.cells.size(), k.unit, "" if p.cells.size() == 1 else "s"]
		"warehouse":
			return "%s %d" % [Warehouses.KINDS[sim.warehouses.buildings[id].kind].name, id]
		"taxi":
			return "Taxi company %d" % id
		"telecom":
			return "Phone company %d  ·  $%s a month" % [id, CitySim.money_text(Telecom.monthly_grant(sim.telecom.companies[id]))]
		"hub":
			return "%s %d  ·  $%s a month" % [CivicHubs.KINDS[sim.hubs.hubs[id].kind].name, id,
				CitySim.money_text(sim.hubs.cost_of(id))]
		"park":
			return "%s  ·  $%s a month" % [sim.parks.sites[id].name, CitySim.money_text(roundi(sim.parks.site_upkeep(id)))]
		"campus":
			var c: Dictionary = sim.education.campuses[id]
			return "%s %d  ·  $%s a month" % [Education.KINDS[c.kind].name, id,
				CitySim.money_text(Education.monthly_funding(c))]
		"hospital":
			var h: Dictionary = sim.healthcare.hubs.get(id, {})
			return "%s  ·  $%s a month" % [h.get("name", "Hospital %d" % id), CitySim.money_text(sim.services.upkeep_of(id))]
		"bank":
			var b: Dictionary = sim.banks.banks[id]
			return "%s %d  ·  %s" % [Banks.KINDS[b.kind].name, id, {"well": "well run", "adequate": "doing all right",
				"order": "under a regulator's order"}.get(Banks.health(b), "")]
	return key


## A one-line count and money figure for an area's header.
func _summary(area: String) -> String:
	var e := sim.economy
	match area:
		"homes", "shops", "factories":
			var zone: int = Economy.ZONE_AREA.find_key(area)
			return "%d  ·  $%s taxes" % [sim.count_buildings(zone), CitySim.money_text(int(e.budget.income.get(zone, 0)))]
		"farms":
			return "%d  ·  %s" % [sim.farms.farms.size(), _aid(sim.farms.yearly_support() / 12.0)]
		"resources":
			return "%d  ·  %s" % [sim.industry.sites.size(), _aid(sim.industry.yearly_support() / 12.0)]
		"utilities", "public":
			var n := 0
			var cost := 0
			for id in sim.services.buildings:
				if Services.area_of(sim.services.buildings[id].kind) == area:
					n += 1
					cost += sim.services.upkeep_of(id)
			return "%d  ·  $%s upkeep" % [n, CitySim.money_text(cost)]
		"transit":
			var cost := 0
			for key in hubs_in(area):
				cost += int(sim.services.buildings[int(key.get_slice(":", 1))].get("subsidy", 0))
			return "%d  ·  $%s subsidy" % [hubs_in(area).size(), CitySim.money_text(cost)]
		"water":
			return "%d  ·  $%s subsidy" % [sim.services.water.utilities.size(), CitySim.money_text(sim.services.water.monthly_subsidy())]
		"mail":
			var cost := 0
			for id in sim.mail.offices:
				cost += int(Balance.MAIL_FUNDING[sim.mail.offices[id].funding].monthly)
			return "%d  ·  $%s funding" % [sim.mail.offices.size(), CitySim.money_text(cost)]
		"power":
			return "%d companies" % sim.power.sites.size() if sim.power.sites.size() != 1 else "1 company"
		"warehouses":
			return "%d" % sim.warehouses.buildings.size()
		"taxis":
			return "%d" % hubs_in(area).size()
		"telecom":
			var grant := 0
			for id in sim.telecom.companies:
				grant += Telecom.monthly_grant(sim.telecom.companies[id])
			return "%d  ·  $%s grant" % [sim.telecom.companies.size(), CitySim.money_text(grant)]
		"waste", "cemetery":
			var n := 0
			var cost := 0
			for id in sim.hubs.hubs:
				if CivicHubs.area_of(sim.hubs.hubs[id].kind) == area:
					n += 1
					cost += sim.hubs.cost_of(id)
			return "%d  ·  $%s upkeep" % [n, CitySim.money_text(cost)]
		"parks":
			return "%d  ·  $%s upkeep" % [sim.parks.sites.size(), CitySim.money_text(sim.parks.monthly_upkeep())]
		"schools":
			return "%d  ·  $%s funding" % [sim.education.campuses.size(), CitySim.money_text(sim.education.monthly_upkeep())]
		"banks":
			var b := sim.banks.summary()
			return "%d  ·  $%s lent" % [int(b.get("banks", 0)), CitySim.money_text(roundi(float(b.get("loans", 0))))]
	return ""


static func _aid(monthly: float) -> String:
	var v := roundi(monthly)
	if v == 0:
		return "no aid"
	return ("$%s aid" if v > 0 else "$%s in fees") % CitySim.money_text(absi(v))


func _sync_sliders() -> void:
	if sim == null:
		return
	var p := sim.policies
	for sl in _town:
		_town[sl].show_step(p.step(sl, ""), true)
	for area in _area_rows:
		for sl in _area_rows[area].sliders:
			_area_rows[area].sliders[sl].show_step(p.step(sl, area), p.own("area:" + area, sl) >= 0, "the town")
		_area_rows[area].arrow.disabled = not _has_hubs(area)
	for key in _hub_rows:
		var area := sim.hub_area(key)
		if area == "":
			continue
		for sl in _hub_rows[key]:
			_hub_rows[key][sl].show_step(p.step(sl, area, key), p.own(key, sl) >= 0, Policies.AREAS[area].name)
