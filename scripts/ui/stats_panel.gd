class_name StatsPanel
extends PanelContainer
## What's behind each top bar readout (Brawn, 2026-10-23: every button opens
## a chart or a display with its own data). Click population, jobs, traffic,
## demand, money, the date or the problem chip and this opens, docked flush
## to the left edge under the top bar, the way Cities: Skylines 2's info
## panels open from its top bar.
##
## Each one has a chart over time (this month, this year, ten years or the
## town's whole life; hover for the values, click the legend to hide a line),
## the numbers that make it up, and links that take you there: the busiest
## road, a building without power, the Economy page, the zone brush.
## Esc closes it, like the other panels.

signal closed
## The HUD shows a map view ("traffic", ...), opens the Economy page or picks
## up a zone brush.
signal show_view(key: String)
signal open_economy
signal pick_zone(zone: int)

const WIDTH := 380
const HOUR := CitySim.TICKS_PER_HOUR
const YEAR := 12 * 24 * CitySim.TICKS_PER_HOUR
const KEYS := ["population", "jobs", "traffic", "demand", "money", "date", "problems"]
## On the calendar (a day is 2 real minutes, a month about an hour), the
## spans StatHistory keeps: a day, two weeks and five months.
const SPANS := [["month", "Day"], ["year", "2 weeks"], ["decade", "5 months"], ["all", "All"]]
const TITLES := {"population": "POPULATION", "jobs": "JOBS AND WORK", "traffic": "TRAFFIC",
	"demand": "DEMAND", "money": "MONEY", "date": "CALENDAR", "problems": "PROBLEMS"}
const ICONS := {"population": "people", "jobs": "jobs", "traffic": "car", "demand": "zones",
	"money": "money", "date": "seasons", "problems": "warning"}
const ZONE_WORD := {ZoneMap.Zone.RESIDENTIAL: "Homes", ZoneMap.Zone.COMMERCIAL: "Shops",
	ZoneMap.Zone.INDUSTRIAL: "Industry"}

var sim: CitySim
var cam: CityCamera
## Selects something on the map (SelectTool.select).
var select: Callable

## Which stat is open ("" while closed).
var key := ""
var span := "year"
var metric := 0
var _off := {}  # series names hidden from the chart

var _icon := Icon.new("people", 16)
var _title := UiStyle.label("", 11, UiStyle.MUTED)
var _value := UiStyle.label("", 22, UiStyle.TEXT, 700)
var _change := UiStyle.label("", 12, UiStyle.MUTED)
var _spans := HBoxContainer.new()
var _tabs := HBoxContainer.new()
var _chart := StatChart.new()
var _legend := HBoxContainer.new()
var _details := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _wait := 0.0
var _shown := ""


func setup(s: CitySim, c: CityCamera, sel: Callable) -> void:
	sim = s
	cam = c
	select = sel


func _ready() -> void:
	var box := UiStyle.dock(true)
	box.border_width_right = 1
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 10
	add_theme_stylebox_override("panel", box)
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	_icon.color = Brand.BRAND_MINT
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_icon)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_panel)
	head.add_child(close)
	var big := VBoxContainer.new()
	big.add_theme_constant_override("separation", 0)
	col.add_child(big)
	big.add_child(_value)
	_change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_change.custom_minimum_size.x = WIDTH - 40
	big.add_child(_change)
	_tabs.add_theme_constant_override("separation", 4)
	col.add_child(_tabs)
	_spans.add_theme_constant_override("separation", 4)
	col.add_child(_spans)
	for s in SPANS:
		var b := _chip(s[1], "Show " + {"month": "the last day", "year": "the last two weeks",
			"decade": "the last five months", "all": "the town's whole life"}[s[0]])
		var which: String = s[0]
		b.pressed.connect(func():
			span = which
			_refresh(true))
		b.set_meta("span", which)
		_spans.add_child(b)
	col.add_child(_chart)
	_legend.add_theme_constant_override("separation", 4)
	col.add_child(_legend)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_details.add_theme_constant_override("separation", 4)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_details)
	visible = false


## Opens a stat's panel; the same one again closes it.
func toggle(k: String) -> void:
	if visible and key == k:
		close_panel()
	else:
		open_panel(k)


func open_panel(k: String) -> void:
	if key != k:
		metric = 0
		_off.clear()
	key = k
	visible = true
	_icon.kind = ICONS.get(k, "people")
	_title.text = TITLES.get(k, k.to_upper())
	_refresh(true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	key = ""
	closed.emit()


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_wait -= delta
	if _wait <= 0.0:
		_refresh(false)


## Redraws the chart and numbers (once a second while open); `full` also
## rebuilds the tabs and legend.
func _refresh(full: bool) -> void:
	_wait = 1.0
	var metrics := _metrics()
	metric = clampi(metric, 0, metrics.size() - 1)
	var m: Dictionary = metrics[metric]
	if full:
		for c in _tabs.get_children():
			c.queue_free()
		_tabs.visible = metrics.size() > 1
		for i in metrics.size():
			var b := _chip(metrics[i].name, metrics[i].get("tip", ""))
			b.button_pressed = i == metric
			var at := i
			b.pressed.connect(func():
				metric = at
				_off.clear()
				_refresh(true))
			_tabs.add_child(b)
	_spans.visible = not m.get("bars", false)
	for b in _spans.get_children():
		b.set_pressed_no_signal(b.get_meta("span") == span)
	var head: Array = _headline()
	_value.text = head[0]
	_change.text = head[1]
	# The chart.
	var rows: Array = sim.history.rows(sim, "all" if m.get("bars", false) else span)
	var series := []
	for s in m.series:
		var pts := []
		if m.get("bars", false):
			pts = _by_year(rows, s.f)
		else:
			for r in rows:
				pts.append([int(r[0]), float(s.f.call(r))])
		series.append({"name": s.name, "color": s.color, "pts": pts, "on": not _off.has(s.name)})
	_chart.fmt = m.fmt
	# Finer grid labels when the plain ones would repeat ($1.485M, $1.490M).
	var plain := str(m.fmt.call(1.0))
	var unit := "pct" if plain.ends_with("%") else ("money" if plain.contains("$") else "count")
	_chart.fine = func(v: float, st: float) -> String:
		match unit:
			"pct":
				return "%.1f%%" % v
			"money":
				return ("–$" if v < 0 else "$") + _short(absf(v), st)
		return _short(v, st)
	_chart.bars = m.get("bars", false)
	_chart.hourly = span in ["month", "year"] and not _chart.bars
	_chart.calendar_of = sim.calendar_of
	_chart.from_zero = m.get("from_zero", true)
	_chart.set_series(series)
	if full:
		for c in _legend.get_children():
			c.queue_free()
		_legend.visible = series.size() > 1
		# A filled dot while the line shows, a hollow one when it's hidden
		# (not the chosen-pill look: these are switches), and each line's
		# latest value, so lines drawn on top of each other still read.
		for s in series:
			var b := _chip(s.name, "Click to hide or show this line")
			b.flat = true
			b.button_pressed = s.on
			var nm: String = s.name
			var col: Color = s.color
			b.icon = _dot(col) if s.on else _ring(col)
			b.toggled.connect(func(on):
				b.icon = _dot(col) if on else _ring(col)
				if on:
					_off.erase(nm)
				else:
					_off[nm] = true
				_refresh(false))
			b.set_meta("series", nm)
			_legend.add_child(b)
	for b in _legend.get_children():
		for s in series:
			if b.get_meta("series", "") == s.name:
				b.text = "%s  %s" % [s.name, m.fmt.call(float(s.pts[-1][1]))] if not s.pts.is_empty() else s.name
	# The details, only when they change (so a click on one isn't lost).
	var sig := _details_key()
	if full or sig != _shown:
		_shown = sig
		for c in _details.get_children():
			c.queue_free()
		call("_details_" + key)
	_fit.call_deferred()


## Shrinks or grows the panel to its details (after freed rows are gone),
## scrolling past the bottom of the screen.
func _fit() -> void:
	var room := get_viewport_rect().size.y - global_position.y - (_scroll.position.y + 60.0)
	_scroll.custom_minimum_size = Vector2(WIDTH - 24, clampf(_details.get_combined_minimum_size().y, 40.0, maxf(room, 120.0)))
	reset_size()


# --- What each stat charts --------------------------------------------------

func _metrics() -> Array:
	var c := func(f: String) -> int: return StatHistory.col(f)
	var count := func(v: float) -> String: return _short(v)
	var pct := func(v: float) -> String: return "%d%%" % roundi(v)
	var dollars := func(v: float) -> String: return ("–$" if v < 0 else "$") + _short(absf(v))
	match key:
		"population":
			return [{"name": "People", "fmt": count, "series": [
				{"name": "People", "color": Brand.ZONE_RES_LOW, "f": func(r): return r[c.call("pop")]}]}]
		"jobs":
			return [
				{"name": "Jobs and workers", "fmt": count, "series": [
					{"name": "Jobs", "color": Brand.BRAND_TEAL, "f": func(r): return r[c.call("jobs")]},
					{"name": "Workers", "color": Brand.ZONE_RES_LOW, "f": func(r): return r[c.call("workers")]},
					{"name": "Employed", "color": Brand.BRAND_MINT, "f": func(r): return r[c.call("employed")]}]},
				{"name": "Unemployment", "fmt": pct, "series": [
					{"name": "Unemployed", "color": Brand.BRAND_CORAL, "f": func(r):
						var w := float(r[c.call("workers")])
						return 0.0 if w <= 0.0 else 100.0 * (w - float(r[c.call("employed")])) / w}]}]
		"traffic":
			return [
				{"name": "Flow", "fmt": pct, "tip": "The share of cars moving freely, as in Cities: Skylines", "series": [
					{"name": "Flow", "color": Brand.TRAFFIC_FREE, "f": func(r): return 100.0 * float(r[c.call("flow")])}]},
				{"name": "Cars", "fmt": count, "series": [
					{"name": "Cars on the road", "color": Brand.BRAND_MINT, "f": func(r): return r[c.call("cars")]}]}]
		"demand":
			return [{"name": "Demand", "fmt": pct, "series": [
				{"name": "Homes", "color": ZoneMap.COLORS[ZoneMap.Zone.RESIDENTIAL], "f": func(r): return 100.0 * float(r[c.call("dem_h")])},
				{"name": "Shops", "color": ZoneMap.COLORS[ZoneMap.Zone.COMMERCIAL], "f": func(r): return 100.0 * float(r[c.call("dem_s")])},
				{"name": "Industry", "color": ZoneMap.COLORS[ZoneMap.Zone.INDUSTRIAL], "f": func(r): return 100.0 * float(r[c.call("dem_i")])}]}]
		"money":
			return [
				{"name": "Cash", "fmt": dollars, "from_zero": false, "series": [
					{"name": "Cash", "color": Brand.POSITIVE, "f": func(r): return r[c.call("money")]}]},
				{"name": "Each day", "fmt": dollars, "from_zero": false, "tip": "What the town takes in less what it spends, a day", "series": [
					{"name": "Up or down a day", "color": Brand.BRAND_MINT, "f": func(r): return r[c.call("net")]}]}]
		"date":
			return [{"name": "Month by month" if _age_months() < 36 else "Year by year", "fmt": count, "bars": true, "series": [
				{"name": "People", "color": Brand.ZONE_RES_LOW, "f": func(r): return r[c.call("pop")]},
				{"name": "Jobs", "color": Brand.BRAND_TEAL, "f": func(r): return r[c.call("jobs")]}]}]
	# "problems": buildings without power or water.
	return [{"name": "Without power or water", "fmt": count, "series": [
		{"name": "Buildings", "color": Brand.WARNING, "f": func(r): return r[c.call("unserved")]}]}]


## The big number at the top and what changed.
func _headline() -> Array:
	var s := sim.stats
	match key:
		"population":
			return [_thousands(s.population), _since("pop", s.population, YEAR, "in 2 weeks")]
		"jobs":
			var w := int(s.workers)
			var un := 0.0 if w == 0 else 100.0 * (w - int(s.employed)) / w
			return [_thousands(s.jobs) + " jobs", "%d%% unemployed  ·  %s workers" % [roundi(un), _thousands(w)]]
		"traffic":
			return ["%d%% flow" % roundi(sim.traffic.flow * 100.0), "%s cars on the road" % _thousands(sim.traffic.cars.size())]
		"demand":
			var top := ZoneMap.Zone.RESIDENTIAL
			for z in [ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL]:
				if sim.demand[z] > sim.demand[top]:
					top = z
			return ["%s most wanted" % ZONE_WORD[top] if sim.demand[top] >= 0.1 else "Little demand", "Homes %d%%  ·  Shops %d%%  ·  Industry %d%%" % [roundi(100.0 * sim.demand[ZoneMap.Zone.RESIDENTIAL]),
				roundi(100.0 * sim.demand[ZoneMap.Zone.COMMERCIAL]), roundi(100.0 * sim.demand[ZoneMap.Zone.INDUSTRIAL])]]
		"money":
			var net := sim.economy.monthly_net()
			return [("–$" if sim.economy.money < 0 else "$") + _thousands(absi(sim.economy.money)),
				"%s$%s a day" % ["+" if net >= 0 else "–", _thousands(absi(net))]]
		"date":
			var t := sim.clock()
			return ["%s %d" % [["January", "February", "March", "April", "May", "June", "July", "August", "September",
				"October", "November", "December"][t.month - 1], Families.calendar(t.year)],
				["Winter", "Spring", "Summer", "Fall"][Seasons.season(Seasons.months(sim.calendar_tick()))]]
	var n := _unserved().size()
	return ["%d buildings" % n if n > 0 else "All clear", "without power or water" if n > 0 else "Everything has power and water"]


func _since(field: String, now: int, ticks: int, words: String) -> String:
	var then = sim.history.value_ago(sim, field, ticks)
	if then == null:
		return ""
	var d := now - int(then)
	return "%s%s %s" % ["+" if d >= 0 else "–", _thousands(absi(d)), words]


## The last sample of each year, for the bar charts: [[tick, value, "2031"], ...]
## (month by month until the town is three years old).
func _by_year(rows: Array, f: Callable) -> Array:
	var months := _age_months() < 36
	var last := {}
	var order := []
	for r in rows:
		var t := int(r[0])
		var c := sim.calendar_of(t)
		var k := Seasons.year(c) * 12 + Seasons.month(c) if months else Seasons.year(c)
		if not last.has(k):
			order.append(k)
		last[k] = r
	var out := []
	for k in order.slice(maxi(order.size() - (12 if months else 20), 0)):
		var t := int(last[k][0])
		out.append([t, float(f.call(last[k])), StatChart.when(sim.calendar_of(t)) if months else str(Families.calendar(k))])
	return out


# --- The details under each chart -------------------------------------------

## Changes when the details would; they're only rebuilt then.
func _details_key() -> String:
	match key:
		"population", "jobs":
			return "%d|%d|%d" % [sim.buildings.size(), sim.stats.population, sim.stats.jobs]
		"traffic":
			return str(sim.tick_count / (HOUR / 4))
		"demand":
			return "%d|%d" % [sim.stats.population, sim.stats.jobs]
		"money":
			return str(sim.economy.budget.hash())
		"date":
			return str(Seasons.month(sim.calendar_tick()))
	return str(_unserved().size())


func _details_population() -> void:
	var by := {}
	var flats := 0
	for k in sim.buildings:
		var b: Dictionary = sim.buildings[k]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			var t: String = BuildingTypes.TYPES[BuildingTypes.type_of(b)].name
			var e: Array = by.get(t, [0, 0])
			by[t] = [e[0] + 1, e[1] + int(b.occ)]
		elif int(b.zone) == ZoneMap.Zone.COMMERCIAL:
			flats += int(b.get("focc", 0))
	if flats > 0:
		by["Flats over shops"] = [0, flats]
	_section("WHERE PEOPLE LIVE")
	var total := maxi(sim.stats.population, 1)
	var names := by.keys()
	names.sort_custom(func(a, b): return by[a][1] > by[b][1])
	for t in names:
		var e: Array = by[t]
		_bar(t, float(e[1]) / total, "%s people%s" % [_thousands(e[1]), "" if e[0] == 0 else " in %d" % e[0]], Brand.ZONE_RES_LOW)
	if names.is_empty():
		_note("Nobody yet. Zone homes along a road with power and water.")
	_section("ROOM")
	_line("Empty homes", _thousands(maxi(int(sim.stats.homes_free), 0)))
	_line("Grown in the last day", _since("pop", sim.stats.population, 24 * HOUR, "").strip_edges())
	_link("Zone more homes", "Pick up the homes brush", func(): pick_zone.emit(ZoneMap.Zone.RESIDENTIAL))


func _details_jobs() -> void:
	var by := TownCulture.jobs_by_sector(sim)
	var total := 0
	for k in by:
		total += int(by[k])
	_section("WHERE PEOPLE WORK")
	var names := by.keys().filter(func(k): return int(by[k]) > 0)
	names.sort_custom(func(a, b): return by[a] > by[b])
	for k in names:
		_bar(TownNickname.SECTOR_NAMES.get(k, k), float(by[k]) / maxi(total, 1), _thousands(by[k]), Brand.BRAND_TEAL)
	if names.is_empty():
		_note("No jobs yet. Zone shops and industry, or place a farm.")
	_section("WORKERS")
	var w := int(sim.stats.workers)
	_line("Working age", _thousands(w))
	var away := int(sim.stats.get("commuting", 0))
	_line("With a job in town", _thousands(sim.stats.employed))
	if away > 0:
		_line("Driving to Marion", _thousands(away))
	_line("Looking for work", _thousands(maxi(w - int(sim.stats.employed) - away, 0)))
	_line("Jobs nobody fills", _thousands(maxi(int(sim.stats.jobs) - int(sim.stats.employed), 0)))
	_note("About half of everyone works, as in the US labour force. Spare jobs draw new families; people out of work want industry.")


func _details_traffic() -> void:
	_link("Show traffic on the map", "The Traffic view: green moves freely, red is stuck", func(): show_view.emit("traffic"))
	# What the cars on the road are doing.
	var by := {}
	for car in sim.traffic.cars:
		var p := str(car.get("purpose", ""))
		p = {"": "Other", "return": "Heading back", "raw": "Raw materials", "commute": "To work"}.get(p, p.replace("_", " ").capitalize())
		by[p] = int(by.get(p, 0)) + 1
	_section("WHY THEY'RE DRIVING")
	var n := maxi(sim.traffic.cars.size(), 1)
	var names := by.keys()
	names.sort_custom(func(a, b): return by[a] > by[b])
	for p in names.slice(0, 6):
		_bar(p, float(by[p]) / n, _thousands(by[p]), Brand.BRAND_MINT)
	if names.is_empty():
		_note("Nobody's on the road right now.")
	# The slowest roads, worst first: click to go there.
	var worst := {}
	for wid in sim.traffic.ways:
		var seg: int = sim.traffic.ways[wid].seg
		var v := sim.traffic.way_speed(wid)
		if v < 0.85 and (not worst.has(seg) or v < worst[seg]):
			worst[seg] = v
	_section("SLOWEST ROADS")
	var segs := worst.keys()
	segs.sort_custom(func(a, b): return worst[a] < worst[b])
	for seg in segs.slice(0, 6):
		if not sim.network.segments.has(seg):
			continue
		var nm := sim.streets.name_of(seg)
		var c: Array = sim.network.curve_of(seg)
		var mid: Vector3 = c[1] if c.size() > 2 else (c[0] + c[-1]) * 0.5
		var s: int = seg
		_go("%s  ·  %d%% speed" % [nm if nm != "" else "A road", roundi(worst[seg] * 100.0)], "Go there", func():
			cam.fly_to(mid)
			if select.is_valid():
				select.call({"type": "road", "id": s}))
	if segs.is_empty():
		_note("Every road is moving freely.")


func _details_demand() -> void:
	var s := sim.stats
	var w := int(s.workers)
	var looking := maxi(w - int(s.employed), 0)
	var why := {
		ZoneMap.Zone.RESIDENTIAL: "%s jobs for %s workers, %s empty homes. Spare jobs, good services, parks and internet draw families." %
			[_thousands(s.jobs), _thousands(w), _thousands(maxi(int(s.homes_free), 0))],
		ZoneMap.Zone.COMMERCIAL: "%s people to shop. Shops want about one job for every eight residents, and visitors spend here too." %
			_thousands(s.population),
		ZoneMap.Zone.INDUSTRIAL: "%s people looking for work. Factories also follow what the shops need to sell." % _thousands(looking),
	}
	for z in [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL]:
		_section(ZONE_WORD[z].to_upper())
		_bar("Demand", float(sim.demand[z]), "%d%%" % roundi(100.0 * sim.demand[z]), ZoneMap.COLORS[z])
		_note(why[z])
		var zz: int = z
		_link("Zone " + ZONE_WORD[z].to_lower(), "Pick up the %s brush" % ZONE_WORD[z].to_lower(), func(): pick_zone.emit(zz))


func _details_money() -> void:
	_link("Open the Economy page", "Funding and growth for the town, its areas and hubs", func(): open_economy.emit())
	var b: Dictionary = sim.economy.budget
	_section("TODAY IN")
	var inc: Dictionary = b.get("income", {})
	for z in [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL]:
		_line(ZONE_WORD[z] + " taxes", "$" + _thousands(int(inc.get(z, 0))), Brand.POSITIVE)
	for k in [["fees", "Fees and fares"], ["deals", "Deals with neighbors"], ["region", "Region projects"]]:
		if int(b.get(k[0], 0)) > 0:
			_line(k[1], "$" + _thousands(int(b[k[0]])), Brand.POSITIVE)
	_section("TODAY OUT")
	for k in [["upkeep", "Roads"], ["services", "Services"], ["education", "Schools and colleges"],
			["care", "Street care"], ["support", "Farm and company aid"], ["telecom", "Phone and internet"]]:
		var v := int(b.get(k[0], 0))
		if v != 0:
			_line(k[1], ("–$" if v > 0 else "+$") + _thousands(absi(v)), Brand.CRITICAL if v > 0 else Brand.POSITIVE)
	if int(b.get("deals", 0)) < 0:
		_line("Deals with neighbors", "–$" + _thousands(absi(int(b.deals))), Brand.CRITICAL)
	var net := sim.economy.monthly_net()
	_line("Up or down a day", "%s$%s" % ["+" if net >= 0 else "–", _thousands(absi(net))], Brand.POSITIVE if net >= 0 else Brand.CRITICAL)


func _details_date() -> void:
	var founded := Families.calendar(Seasons.year(sim.calendar_of(0)))
	var months := _age_months()
	_line("Founded", str(founded))
	_line("Town age", "%d years, %d months" % [months / 12, months % 12])
	_line("Season", ["Winter", "Spring", "Summer", "Fall"][Seasons.season(Seasons.months(sim.calendar_tick()))])
	_line("A day passes in", "about 2 minutes")
	_line("A month passes in", "about an hour: one day and night in the sky")
	_note("Each bar is the end of a month (a year once the town is three), the last one so far. Hover for the numbers.")


## Whole calendar months since the town began.
func _age_months() -> int:
	return int(Seasons.months(sim.calendar_tick()) - Seasons.months(sim.calendar_of(0)))


func _details_problems() -> void:
	var full := sim.utility_problem()
	if full != "":
		_note(full + ".")
	var keys := _unserved()
	_section("WITHOUT POWER OR WATER")
	for k in keys.slice(0, 10):
		var lot: Dictionary = sim.lots.get(k, {})
		if lot.is_empty():
			continue
		var b: Dictionary = sim.buildings[k]
		var addr := sim.streets.address(sim, k)
		var at: Vector3 = lot.pos
		var kk: String = k
		_go("%s  ·  %s" % [BuildingTypes.name_of(b), addr if addr != "" else "no address yet"], "Go there", func():
			cam.fly_to(at)
			if select.is_valid():
				select.call({"type": "lot", "id": kk}))
	if keys.size() > 10:
		_note("And %d more." % (keys.size() - 10))
	if keys.is_empty():
		_note("Every building has power and water.")


func _unserved() -> Array:
	var out := []
	for k in sim.buildings:
		if not sim.services.has_utilities(k):
			out.append(k)
	out.sort()
	return out


# --- Bits -------------------------------------------------------------------

func _section(t: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	_details.add_child(gap)
	_details.add_child(UiStyle.label(t, 10, UiStyle.MUTED, 600))


func _line(name: String, value: String, col := UiStyle.TEXT) -> void:
	var row := HBoxContainer.new()
	var l := UiStyle.label(name, 12, UiStyle.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UiStyle.label(value, 12, col, 600))
	_details.add_child(row)


func _bar(name: String, share: float, value: String, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UiStyle.label(name, 12, UiStyle.TEXT)
	l.custom_minimum_size.x = 150
	l.clip_text = true
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = clampf(share, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(90, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var v := UiStyle.label(value, 12, UiStyle.MUTED)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	_details.add_child(row)


func _note(t: String) -> void:
	var l := UiStyle.label(t, 11, Brand.INK_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	_details.add_child(l)


## A button that does something (opens a view, a page, a brush).
func _link(text: String, tip: String, f: Callable) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(f)
	_details.add_child(b)


## A flat row that takes you somewhere on the map.
func _go(text: String, tip: String, f: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "→  " + text
	b.tooltip_text = tip
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(f)
	_details.add_child(b)


func _chip(text: String, tip: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 11)
	return b


static func _dot(col: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x + 0.5 - 4.0, y + 0.5 - 4.0).length()
			img.set_pixel(x, y, Color(col, clampf(4.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A hollow circle: a chart line that's hidden.
static func _ring(col: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x + 0.5 - 4.0, y + 0.5 - 4.0).length()
			img.set_pixel(x, y, Color(col, clampf(4.0 - d, 0.0, 1.0) * clampf(d - 2.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _thousands(n: int) -> String:
	return CitySim.money_text(n)


## 1,234 -> "1,234"; 52,300 -> "52.3k"; 1,250,000 -> "1.25M". With a
## chart's grid `step`, enough decimals that a step shows (1.485M, 1.490M).
static func _short(v: float, step := 0.0) -> String:
	var a := absf(v)
	var s := ""
	if a >= 1000000.0:
		var d := 2 if step <= 0.0 else clampi(ceili(-log(step / 1000000.0) / log(10.0)), 2, 4)
		s = ("%." + str(d) + "fM") % (a / 1000000.0)
	elif a >= 10000.0:
		var d := 1 if step <= 0.0 else clampi(ceili(-log(step / 1000.0) / log(10.0)), 1, 3)
		s = ("%." + str(d) + "fk") % (a / 1000.0)
	else:
		s = CitySim.money_text(roundi(a))
	return ("-" if v < 0 else "") + s
