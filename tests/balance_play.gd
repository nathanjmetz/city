class_name BalancePlay
extends RefCounted
## Plays a city headless by a fixed script, like a player would, and records
## its money, people and milestones day by day. The balance harness
## (tools/balance_run.gd) and its test (tests/test_balance.gd) run these.
##
## Patterns:
## - "planner": a careful player. One street, power and water, zoning, then
##   a new street whenever the zoned lots fill and there is money to spare.
## - "grid_rush": what new players do first: a big street grid and a farm,
##   then power and water with whatever money is left.
## - "idle": builds nothing, to check money doesn't drain on its own.

const DAY := 24 * CitySim.TICKS_PER_HOUR
const ROW := 82.0         # RoadShapes.GRID_ACROSS: two lots deep each side
const ROW_HALF := 200.0   # each street runs 400 m
const LOT_OFFSET := 26.0  # road centre to the middle of its lots
## Kept back for upkeep before the planner builds anything optional.
const RESERVE := 60_000

var pattern := ""
var difficulty := ""
var sim := CitySim.new()
## One row a game day: {day, money, net, pop, jobs, homes, milestone}.
var days := []
## First game day each thing happened: "power", "water", "pop100", ...
var events := {}
var min_money := 0
var start_money := 0
var rows := 0
var _wants_services := [Services.Kind.FIRE, Services.Kind.POLICE, Services.Kind.CLINIC, Services.Kind.SCHOOL]


func _init(p: String, diff := "") -> void:
	pattern = p
	difficulty = diff
	sim.require_utilities = true
	sim.simulate_traffic = false
	if diff != "":
		sim.apply({"type": "set_difficulty", "difficulty": diff})
	min_money = sim.economy.money
	start_money = sim.economy.money


## Plays `n` game days.
func play(n: int) -> BalancePlay:
	match pattern:
		"planner":
			_add_row()
		"grid_rush":
			_grid_rush()
	for d in n:
		for h in 24:
			for t in CitySim.TICKS_PER_HOUR:
				sim.tick()
				min_money = mini(min_money, sim.economy.money)
			if pattern != "idle":
				_decide()
		_record(d + 1)
	return self


func day_of(event: String) -> int:
	return int(events.get(event, -1))


## A short summary line for the harness report.
func summary() -> Dictionary:
	var last: Dictionary = days[-1] if not days.is_empty() else {}
	return {"pattern": pattern, "difficulty": difficulty if difficulty != "" else "normal",
		"start": start_money,
		"min_money": min_money, "end_money": last.get("money", 0), "end_net": last.get("net", 0),
		"pop": last.get("pop", 0), "power_day": day_of("power"), "water_day": day_of("water"),
		"pop100_day": day_of("pop100"), "pop500_day": day_of("pop500"), "pop1000_day": day_of("pop1000"),
		"positive_day": day_of("positive"), "stuck": is_stuck(), "broke": min_money < 0}


## Stuck: no people and not enough money left to give the town power and water.
func is_stuck() -> bool:
	return sim.stats.population == 0 and not (_has("power") and _has("water"))


func _record(day: int) -> void:
	var pop: int = sim.stats.population
	days.append({"day": day, "money": sim.economy.money, "net": sim.economy.monthly_net(),
		"pop": pop, "jobs": sim.stats.jobs, "homes": sim.count_buildings(ZoneMap.Zone.RESIDENTIAL),
		"milestone": sim.economy.milestone, "free": sim.empty_zoned_lots().size(),
		"dem": "%.2f/%.2f/%.2f" % [sim.demand[ZoneMap.Zone.RESIDENTIAL], sim.demand[ZoneMap.Zone.COMMERCIAL],
			sim.demand[ZoneMap.Zone.INDUSTRIAL]]})
	for n in [100, 250, 500, 1000, 2500]:
		if pop >= n and not events.has("pop%d" % n):
			events["pop%d" % n] = day
	if sim.economy.monthly_net() > 0 and pop > 0 and not events.has("positive"):
		events["positive"] = day


# --- What the scripted player does ------------------------------------------

## Checked every game hour: utilities first, then services, then growth.
func _decide() -> void:
	_utility("power", Services.Kind.POWER_FEED, Services.Kind.SUBSTATION)
	_utility("water", Services.Kind.WELL, Services.Kind.WATER_TOWER)
	if not (_has("power") and _has("water")):
		return
	var pop: int = sim.stats.population
	if pop > 300 and not _wants_services.is_empty():
		var kind: int = _wants_services[0]
		var need := 1500 if kind == Services.Kind.SCHOOL else 300
		if pop > need and sim.economy.money > int(Services.KINDS[kind].cost) + RESERVE * 2:
			if _place(kind, rows):
				_wants_services.pop_front()
	var free := 0
	for key in sim.empty_zoned_lots():
		if sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.RESIDENTIAL:
			free += 1
	if free < 4 and sim.economy.money > _row_cost() + RESERVE:
		_add_row()


func _has(utility: String) -> bool:
	return int(sim.services.utility_use[utility][1]) > 0


## Builds the starter source, then a bigger one (or another starter) when
## use passes 80% of what's built.
func _utility(utility: String, small: int, big: int) -> void:
	if sim.utilities_going_up().any(func(g): return g.utility == utility):
		return  # one's already going in: wait for the crew
	var use: Array = sim.services.utility_use[utility]
	if int(use[1]) > 0 and float(use[0]) < 0.8 * float(use[1]):
		return
	var kind := small
	if int(use[1]) > 0 and sim.economy.money > int(Services.KINDS[big].cost) + RESERVE:
		kind = big
	if sim.economy.money < int(Services.KINDS[kind].cost):
		return
	if _place(kind, 0) and not events.has(utility):
		events[utility] = days.size()


## Places a service beside street `row`, walking along it for a free spot.
func _place(kind: int, row: int) -> bool:
	var z := row * ROW
	for x in range(-180, 181, 30):
		for side in [-1.0, 1.0]:
			var site := Services.site_near(sim.network, kind, Vector3(x, 0, z + side * 30.0))
			if site.is_empty():
				continue
			if sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z],
					"dir": [site[1].x, site[1].z]}):
				return true
	return false


func _row_cost() -> int:
	return roundi((ROW_HALF * 2.0 + ROW * 3.0) * Economy.BUILD_PER_M[RoadStyle.Type.STREET])


## A new 400 m street north of the last, joined by three cross streets, and
## zoned the way demand asks (homes on one side, the most wanted on the other).
func _add_row() -> void:
	var z := rows * ROW
	_road(Vector3(-ROW_HALF, 0, z), Vector3(ROW_HALF, 0, z))
	if rows > 0:
		for x in [-ROW_HALF, 0.0, ROW_HALF]:
			_road(Vector3(x, 0, z - ROW), Vector3(x, 0, z))
	var other := ZoneMap.Zone.RESIDENTIAL
	if maxf(sim.demand[ZoneMap.Zone.COMMERCIAL], sim.demand[ZoneMap.Zone.INDUSTRIAL]) > 0.3:
		other = ZoneMap.Zone.COMMERCIAL
		if sim.demand[ZoneMap.Zone.INDUSTRIAL] > sim.demand[ZoneMap.Zone.COMMERCIAL]:
			other = ZoneMap.Zone.INDUSTRIAL
	_zone(z, -1.0, ZoneMap.Zone.RESIDENTIAL if rows == 0 else other)
	_zone(z, 1.0, ZoneMap.Zone.RESIDENTIAL if rows > 0 else ZoneMap.Zone.INDUSTRIAL)
	rows += 1


## Lays out the user's first move: a 400 x 246 m grid with 100 m blocks and
## a farm, zoned throughout, before thinking about power and water.
func _grid_rush() -> void:
	sim.apply({"type": "build_grid", "a": [-ROW_HALF, 0], "b": [ROW_HALF, 0], "c": [-ROW_HALF, ROW * 3.0],
		"block": 100.0})
	rows = 4
	for r in rows:
		_zone(r * ROW, -1.0, ZoneMap.Zone.RESIDENTIAL)
		_zone(r * ROW, 1.0, ZoneMap.Zone.RESIDENTIAL if r % 2 == 0 else ZoneMap.Zone.COMMERCIAL)
	for spot in [Vector3(ROW_HALF + 120, 0, 60), Vector3(-ROW_HALF - 120, 0, 60), Vector3(0, 0, -150)]:
		var dir := Vector3(0, 0, 1) if spot.z < 0 else Vector3(-signf(spot.x), 0, 0)
		if sim.apply({"type": "place_farmhouse", "pos": [spot.x, spot.z], "dir": [dir.x, dir.z], "crop": "corn"}):
			break


func _road(a: Vector3, b: Vector3) -> void:
	var m := (a + b) * 0.5
	sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [m.x, m.z], "end": [b.x, b.z]})


## Zones one side of the street at z, the way a player does: a click per
## block face.
func _zone(z: float, side: float, zone: int) -> void:
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var c := sim.network.curve_of(id)
		if absf(c[0].z - z) > 1.0 or absf(c[2].z - z) > 1.0:
			continue
		# A street side is left (+1) of its a-to-b direction.
		var dx: float = c[2].x - c[0].x
		var s := 1 if (dx > 0.0) == (side > 0.0) else -1
		# Just this street: the scripted player zones street by street.
		sim.apply({"type": "zone_frontage", "seg": id, "side": s, "zone": zone, "single": true})
