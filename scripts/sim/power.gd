class_name Power
extends RefCounted
## Power companies, Brawn's hub-with-a-leader model (Best of CS pitch #6,
## green-lit 2026-10-22). The regional grid through a substation stays the
## default; instead the player can place a power company's yard (switchyard
## and control building). It hires a leader, and the leader picks how to make
## power from what the land offers:
##   solar farm on open ground, wind farm where it's windy (the ridges once
##   the real terrain lands), a gas plant near oil (the field's own gas), a
##   run-of-river dam on the White River, or an old coal plant bought cheap.
## How far ahead the leader plans comes from their education, which comes
## from the town's schools: a well-educated leader builds the plant that is
## cheapest over 20+ years (clean), a poorly educated one the one cheapest to
## start (an old, dirty coal plant that smokes up land values around it).
##
## The plant then grows unit by unit into land right next to it (never a
## second site) while another unit pays: first to cover the town's load,
## then to sell the extra to the region out the county highway.
## Numbers are in Balance (POWER_*). Deterministic, like everything in CitySim.

const CELL := 80.0              # one block of panels, a gas or coal unit, a dam bay
const MAX_DRIVE := 250.0        # longest access road out to a public road
## The yard: switchyard and the control building.
const HQ_SIZE := Vector2(50, 40)
## How far out (in cells) a new plant may open its first unit.
const SEED_REACH := 3
const PLANTS := Balance.POWER_PLANTS
const DECIDE_EVERY := Balance.POWER_DECIDE_EVERY

const FIRST_NAMES := ["Dale", "Linda", "Gary", "Karen", "Ray", "Donna", "Curt", "Janet", "Wayne", "Peggy",
	"Doug", "Sheila", "Lyle", "Marcy", "Arnie", "Joanne", "Earl", "Deb", "Vern", "Lori"]
const LAST_NAMES := ["Kowalski", "Hendricks", "Schroeder", "Lindqvist", "McAllister", "Brandt", "Yoder",
	"Riggs", "Halvorsen", "Pruitt", "Gerber", "Dunlap", "Voss", "Tate", "Becker", "Ostrander"]

## Companies: id -> {plant, pos, dir, drive, cells: Array of Vector2i in its
## own frame (0,0 is the yard), leader: {name, education}, why, loss_streak,
## savings ($), upgrades: Array of Balance.POWER_UPGRADES keys, hired (game
## day the leader took over)}
var sites := {}
## Set by the city: the industrial tax rate (percent).
var tax_rate := 1.5
## Flow of the river at a point, 0 (dry land) to 1 (the main channel). The
## terrain thread's White River plugs in here; until then there's no river
## and no leader picks hydro.
var river := Callable()
## Last decide step's sales, per company id: {"town": homes, "export": homes,
## "profit": $ a year}. Shown in the panel; worked out again each step.
var sales := {}
var _next_id := 1


# --- Where power comes from ---------------------------------------------------

## How windy a spot is, 0 to 1. Stand-in for ridge exposure until the real
## terrain lands: smooth, gridless, the same for every player.
static func wind_at(p: Vector3) -> float:
	var n := Resources._fbm(Vector2(p.x, p.z) / 900.0, 53)
	return smoothstep(0.3, 0.75, n)


func river_at(p: Vector3) -> float:
	return 0.0 if not river.is_valid() else clampf(float(river.call(p)), 0.0, 1.0)


## How well a plant of this kind works at a point, 0 to 1 (0 = can't).
func quality(plant: String, p: Vector3) -> float:
	match plant:
		"solar":
			# Open ground. Woods have to be cleared and shade the panels.
			return 1.0 - 0.5 * Resources.at(Resources.Kind.FOREST, p)
		"wind":
			return wind_at(p)
		"hydro":
			return river_at(p)
	return 1.0


## Best quality within reach of a yard (a plant spreads a few hundred metres).
func reach_quality(plant: String, pos: Vector3) -> float:
	if plant == "gas":
		return gas_supply(pos)
	if plant == "coal":
		return 1.0
	var best := 0.0
	for r in [0.0, 120.0, 240.0, 360.0]:
		for i in (1 if r == 0.0 else 12):
			var a := TAU * i / 12.0
			best = maxf(best, quality(plant, pos + Vector3(cos(a), 0.0, sin(a)) * r))
	return best


## Local gas for a gas plant: the oil field's own gas, 0 to 1. A gas plant
## only goes near oil.
static func gas_supply(pos: Vector3) -> float:
	var best := 0.0
	for r in [0.0, 200.0, 400.0]:
		for i in (1 if r == 0.0 else 12):
			var a := TAU * i / 12.0
			best = maxf(best, Resources.at(Resources.Kind.OIL, pos + Vector3(cos(a), 0.0, sin(a)) * r))
	return 0.0 if best < Balance.INDUSTRY_MIN_RICHNESS else best


## Homes-equivalent one unit makes on average, at a quality.
static func unit_homes(plant: String, q: float) -> float:
	var k: Dictionary = PLANTS[plant]
	return k.homes * (q if plant in ["solar", "wind"] else (0.5 + q if plant == "hydro" else 1.0))


## Running cost per MWh (fuel and upkeep). Gas is cheaper with local gas.
static func opex(plant: String, gas := 0.0) -> float:
	var k: Dictionary = PLANTS[plant]
	if plant == "gas":
		return lerpf(k.opex, Balance.POWER_GAS_LOCAL_OPEX, gas)
	return k.opex


# --- The leader ---------------------------------------------------------------

## A leader for a new company, from the town's education (0 to 1) and a
## little luck. Deterministic from the city seed and the company id.
static func hire(town_education: float, city_seed: int, id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, id, "power leader"])
	var name := "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	var edu := clampf(town_education + rng.randf_range(-1.0, 1.0) * Balance.POWER_LEADER_SPREAD, 0.0, 1.0)
	return {"name": name, "education": snappedf(edu, 0.01)}


## Years ahead a leader plans: a payback-in-three-years owner to a 25-year
## planner, as their education rises.
static func horizon(leader: Dictionary) -> float:
	return lerpf(Balance.POWER_HORIZON_MIN, Balance.POWER_HORIZON_MAX, float(leader.education))


static func schooling(leader: Dictionary) -> String:
	var e := float(leader.education)
	return "an engineering degree" if e >= 0.7 else ("a college degree" if e >= 0.45 else "a high school diploma")


## What a leader thinks each kind of plant is worth here, per MWh a year it
## makes over their horizon: margin over the years they plan for (less the
## carbon risk they see), less what it costs to build, less how much they
## mind the smoke. -INF if it can't go
## here. Returns {plant: score}.
func scores(leader: Dictionary, pos: Vector3) -> Dictionary:
	var h := horizon(leader)
	var gas := gas_supply(pos)
	var out := {}
	for plant in PLANTS:
		var k: Dictionary = PLANTS[plant]
		var q := reach_quality(plant, pos)
		if q < Balance.POWER_MIN_QUALITY:
			out[plant] = -INF
			continue
		var mwh := unit_homes(plant, q) * Balance.POWER_MWH_PER_HOME
		var margin: float = Balance.POWER_TOWN_PRICE - opex(plant, gas) + (Balance.POWER_FIRM_BONUS if k.firm else 0.0) \
			- float(leader.education) * Balance.POWER_CARBON_PRICE * float(k.carbon)
		out[plant] = h * margin - float(k.capex) / mwh + float(leader.education) * k.smoke_weight * k.value
	return out


## The plant a leader picks here, and why in plain words: [plant, why].
func choose(leader: Dictionary, pos: Vector3) -> Array:
	var sc := scores(leader, pos)
	var best := ""
	for plant in Balance.POWER_PLANT_ORDER:
		if sc[plant] > -INF and (best == "" or sc[plant] > sc[best]):
			best = plant
	var h := roundi(horizon(leader))
	var why := "%s has %s and plans %d years ahead: " % [leader.name, schooling(leader), h]
	match best:
		"coal":
			why += "an old coal plant was cheapest to get running."
		"gas":
			why += "the oil field's own gas makes cheap, steady power."
		"solar":
			why += "solar is the cheapest power over the long run."
		"wind":
			why += "the wind here makes turbines the cheapest power."
		"hydro":
			why += "the river turns turbines for free for decades."
	return [best, why]


# --- Sites --------------------------------------------------------------------

func add_site(pos: Vector3, dir: Vector3, drive: Array, town_education: float, city_seed: int, day := 0.0) -> int:
	var id := _next_id
	_next_id += 1
	var leader := hire(town_education, city_seed, id)
	var pick := choose(leader, pos)
	sites[id] = {"plant": pick[0], "pos": pos, "dir": dir, "drive": drive, "cells": [], "leader": leader,
		"why": pick[1], "loss_streak": 0, "savings": Balance.POWER_START_SAVINGS, "upgrades": [], "hired": day}
	return id


static func _right(s: Dictionary) -> Vector3:
	return Vector3(-s.dir.z, 0.0, s.dir.x)


static func spacing(s: Dictionary) -> float:
	return float(PLANTS[s.plant].spacing)


static func cell_center(s: Dictionary, c: Vector2i) -> Vector3:
	var sp := spacing(s)
	var p: Vector3 = s.pos + _right(s) * (c.x * sp) - s.dir * (c.y * sp)
	return Vector3(p.x, 0.0, p.z)


## The ground a unit takes: a full cell for panels or a power house, just
## the turbine pad for wind (the farm between turbines stays farmed).
static func cell_corners(s: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := cell_center(s, c)
	var half := float(PLANTS[s.plant].footprint) * 0.5
	var r: Vector3 = _right(s) * half
	var b: Vector3 = -s.dir * half
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * k.x + b * k.y
		out.append(Vector2(p.x, p.z))
	return out


func cell_homes(s: Dictionary, c: Vector2i) -> float:
	return unit_homes(s.plant, quality(s.plant, cell_center(s, c))) * _boost(s)


## A battery yard lets panels and turbines cover more homes.
static func _boost(s: Dictionary) -> float:
	return 1.25 if "battery" in s.upgrades else 1.0


## A company's running cost per MWh, with its research lab.
static func site_opex(s: Dictionary) -> float:
	return opex(s.plant, gas_supply(s.pos)) * (0.9 if "lab" in s.upgrades else 1.0)


## Homes-equivalent the company makes on average.
func capacity(id: int) -> int:
	var s: Dictionary = sites[id]
	var total := 0.0
	for c in s.cells:
		total += cell_homes(s, c)
	return roundi(total)


func total_capacity() -> int:
	var total := 0
	for id in sites:
		total += capacity(id)
	return total


## Where each plant feeds the town's lines: its yard's gate on the road.
## [{"front": Vector3, "capacity": int}], for Services.
func sources() -> Array:
	var out := []
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sites[id]
		if not s.cells.is_empty():
			# The access road's end, where the yard's lines meet the town's.
			var gate: Vector3 = s.drive[-1] if not s.drive.is_empty() else s.pos + s.dir * HQ_SIZE.y * 0.5
			out.append({"front": gate, "capacity": capacity(id)})
	return out


## Yearly profit of a company selling `town` homes-equivalent to the town
## and `export` to the region: sales less running costs, debt on what it
## built (over Balance.POWER_LOAN_YEARS) and property tax.
func _profit(s: Dictionary, town: float, export: float, neighbor := 0.0) -> float:
	var k: Dictionary = PLANTS[s.plant]
	var op := site_opex(s)
	var mwh_t := (town + neighbor) * Balance.POWER_MWH_PER_HOME
	var mwh_x := export * Balance.POWER_MWH_PER_HOME
	var built: float = float(k.capex) * s.cells.size()
	var extra := 0.0
	if "steam" in s.upgrades:
		extra += Balance.POWER_STEAM_SALES
	if "blade_yard" in s.upgrades:
		extra += Balance.POWER_BLADE_YARD_SALES
	return mwh_t * (Balance.POWER_TOWN_PRICE - op) + mwh_x * (Balance.POWER_EXPORT_PRICE - op) + extra \
		- built / Balance.POWER_LOAN_YEARS - (built + Balance.POWER_YARD_VALUE) * tax_rate / 100.0


## Every company takes a step. `load` is the town's whole power draw in
## homes-equivalent; companies serve it in order, the rest is sold out the
## county highway when `can_export` (the town has a road out to the region)
## and the export price beats running costs. A company adds a unit next to
## what it has while one pays over its leader's horizon, and mothballs its
## newest after two losing steps (never its last: it keeps the lights on).
## Then the leader looks over the development tree (see grow_tree).
## `ctx` is what the leader can see around it: {day, education (the
## town's), school, university, neighbor_short (homes a neighbor lacks),
## industry_near: Callable(pos) -> bool}.
func decide(usable: Callable, load: float, can_export: bool, ctx := {}) -> bool:
	var changed := false
	var ids := sites.keys()
	ids.sort()
	var left := load
	var short := float(ctx.get("neighbor_short", 0.0))
	sales.clear()
	for id in ids:
		var s: Dictionary = sites[id]
		var k: Dictionary = PLANTS[s.plant]
		var op := site_opex(s)
		var cap := float(capacity(id))
		var town := minf(cap, left)
		var neighbor := 0.0
		if "tie_line" in s.upgrades:
			neighbor = minf(cap - town, short)
			short -= neighbor
		var export := 0.0
		if can_export and Balance.POWER_EXPORT_PRICE > op:
			export = cap - town - neighbor
		var profit := _profit(s, town, export, neighbor)
		sales[id] = {"town": roundi(town), "export": roundi(export), "neighbor": roundi(neighbor), "profit": profit}
		s.savings += profit * DECIDE_EVERY / float(CitySim.TICKS_PER_HOUR * 24 * 12)
		if grow_tree(id, ctx):
			changed = true
		# What one more unit would earn over the leader's horizon, per year.
		var best := Vector2i.MAX
		var best_q := 0.0
		var idle := ""
		if s.cells.size() < int(k.max_cells):
			var cands: Array = _frontier(s) if not s.cells.is_empty() else _seeds()
			for c in cands:
				var q := quality(s.plant, cell_center(s, c))
				if q < Balance.POWER_MIN_QUALITY or q <= best_q:
					continue
				if not _free(id, s, c, usable):
					continue
				best = c
				best_q = q
		if best != Vector2i.MAX:
			var add := unit_homes(s.plant, best_q) * _boost(s)
			var to_town := clampf(left - cap, 0.0, add)
			var to_region := (add - to_town) if export > 0.0 or (can_export and Balance.POWER_EXPORT_PRICE > op) else 0.0
			var gain := (to_town * (Balance.POWER_TOWN_PRICE - op) + to_region * (Balance.POWER_EXPORT_PRICE - op)) \
				* Balance.POWER_MWH_PER_HOME - float(k.capex) / horizon(s.leader) \
				- float(k.capex) * tax_rate / 100.0
			# A new company always opens its first unit: the player paid for it.
			if s.cells.is_empty() or gain > 0.0:
				s.cells.append(best)
				s.loss_streak = 0
				changed = true
				best = Vector2i.MAX
		elif s.cells.is_empty():
			idle = "No room for a first %s next to the yard." % k.unit
		if best != Vector2i.MAX or s.cells.size() >= int(k.max_cells):
			# Not growing: watch the books.
			if profit < 0.0 and s.cells.size() > 1:
				s.loss_streak += 1
				if s.loss_streak >= 2:
					s.cells.pop_back()
					s.loss_streak = 0
					changed = true
			else:
				s.loss_streak = 0
		left = maxf(0.0, left - float(capacity(id)))
		if s.get("idle", "") != idle:
			s.idle = idle
			changed = true
	return changed


## The leader looks over the development tree: a successor takes over when
## the term is up (better schooled with a training center), and the leader
## builds the first add-on it can, has the money for and that pays. Returns
## true if anything changed.
func grow_tree(id: int, ctx: Dictionary) -> bool:
	var s: Dictionary = sites[id]
	var changed := false
	var day := float(ctx.get("day", 0.0))
	if day - float(s.hired) >= Balance.POWER_LEADER_TERM_DAYS:
		var edu := float(ctx.get("education", s.leader.education))
		if "training" in s.upgrades:
			edu += Balance.POWER_TRAINING_LIFT
		var successor := hire(edu, int(s.leader.name.hash()), id + int(day))
		s.leader = successor
		s.hired = day
		changed = true
	for key in Balance.POWER_UPGRADE_ORDER:
		if key in s.upgrades or unlock_problem(id, key, ctx) != "":
			continue
		var u: Dictionary = Balance.POWER_UPGRADES[key]
		if s.savings < float(u.cost):
			continue
		s.savings -= float(u.cost)
		s.upgrades.append(key)
		if key == "repower":
			s.plant = "gas"
			while s.cells.size() > int(PLANTS.gas.max_cells):
				s.cells.pop_back()
			s.upgrades.erase("scrubbers")
			s.why = "%s switched the old coal units to gas from the oil field next door." % s.leader.name
		return true
	return changed


## Why the leader can't build an add-on yet, in plain words, or "" if it can
## (money aside). Shown in the company's panel as its development tree.
func unlock_problem(id: int, key: String, ctx: Dictionary) -> String:
	var s: Dictionary = sites[id]
	var u: Dictionary = Balance.POWER_UPGRADES[key]
	if not u.plants.is_empty() and not s.plant in u.plants:
		return "Only for a %s." % " or ".join(u.plants.map(func(p): return PLANTS[p].name.to_lower()))
	if float(s.leader.education) < float(u.edu):
		return "Needs a leader with %s." % schooling({"education": u.edu})
	match str(u.needs):
		"oil":
			if gas_supply(s.pos) <= 0.0:
				return "Needs an oil field nearby."
		"school":
			if not ctx.get("school", false):
				return "Needs a school in town."
		"university":
			if not ctx.get("university", false):
				return "Needs a university in town or next door."
		"industry":
			var near: Callable = ctx.get("industry_near", Callable())
			if not near.is_valid() or not near.call(s.pos):
				return "Needs factories next door."
		"turbines":
			if s.cells.size() < 6:
				return "Needs 6 turbines."
		"neighbor_short":
			if float(ctx.get("neighbor_short", 0.0)) <= 0.0:
				return "Needs a neighbor town short of power."
	if "repower" == key and s.cells.is_empty():
		return "Needs a running plant."
	return ""


## How a company is doing, in a word or two, for its panel.
func status(id: int) -> String:
	var s: Dictionary = sites[id]
	if s.cells.is_empty():
		return "Getting started"
	var p: float = sales.get(id, {}).get("profit", 0.0)
	if p < 0.0:
		return "Struggling"
	return "Doing well" if p > Balance.POWER_THRIVING_PROFIT else "Getting by"


## How much a point's land value drops from smoke and noise, 0 to about
## -0.3 (-0.2 = 20% lower). An old coal plant smokes up the land around it,
## a gas plant a little; solar, wind and hydro leave it be.
func land_value_effect(p: Vector3) -> float:
	var total := 0.0
	for id in sites:
		var s: Dictionary = sites[id]
		var k: Dictionary = PLANTS[s.plant]
		if float(k.value) >= 0.0 or s.cells.is_empty():
			continue
		var d := INF
		for c in s.cells:
			d = minf(d, cell_center(s, c).distance_to(Vector3(p.x, 0.0, p.z)))
		if d < float(k.reach):
			total += float(k.value) * (1.0 - d / float(k.reach)) * minf(1.0, s.cells.size() / 2.0 + 0.5) \
				* (0.5 if "scrubbers" in s.upgrades else 1.0)
	return maxf(total, Balance.POWER_SMOKE_FLOOR)


## The smokiest plant near a point, for the lot panel: id or -1.
func smoke_from(p: Vector3) -> int:
	var worst := -1
	var worst_v := 0.0
	for id in sites:
		var s: Dictionary = sites[id]
		var k: Dictionary = PLANTS[s.plant]
		if float(k.value) >= 0.0:
			continue
		for c in s.cells:
			var d := cell_center(s, c).distance_to(Vector3(p.x, 0.0, p.z))
			var v := float(k.value) * (1.0 - d / float(k.reach))
			if d < float(k.reach) and v < worst_v:
				worst = id
				worst_v = v
	return worst


## Cells a new company may open its first unit on.
static func _seeds() -> Array:
	var out := []
	for y in range(-SEED_REACH, SEED_REACH + 1):
		for x in range(-SEED_REACH, SEED_REACH + 1):
			var c := Vector2i(x, y)
			if c != Vector2i.ZERO and c.length_squared() <= SEED_REACH * SEED_REACH:
				out.append(c)
	out.sort_custom(func(a, b): return a.length_squared() < b.length_squared() \
		or (a.length_squared() == b.length_squared() and Industry._less(a, b)))
	return out


## Free cells right next to the yard or a unit (8 neighbours): a plant only
## grows into land it touches.
func _frontier(s: Dictionary) -> Array:
	var out := []
	var seen := {Vector2i.ZERO: true}
	for c in s.cells:
		seen[c] = true
	var from: Array = s.cells.duplicate()
	from.append(Vector2i.ZERO)
	for c in from:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n):
				seen[n] = true
				out.append(n)
	out.sort_custom(Industry._less)
	return out


func _free(id: int, s: Dictionary, c: Vector2i, usable: Callable) -> bool:
	var mid := cell_center(s, c)
	var corners := cell_corners(s, c)
	if Farms._drive_crosses(s, corners):
		return false
	var pts := [mid]
	for p in corners:
		pts.append(mid.lerp(Vector3(p.x, 0.0, p.y), 0.8))
	for p in pts:
		var other := at(p)
		if other != -1 and other != id:
			return false
		if site_at(p) == id:
			return false
	return usable.call(mid, corners)


## The company whose yard or access road holds this point.
func site_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		var s: Dictionary = sites[id]
		if Geometry2D.is_point_in_polygon(q, yard(s)):
			return id
		if Farms._near_drive(s, p, Farms.DRIVE_WIDTH * 0.5 + 3.0):
			return id
	return -1


## The company with a unit on this point.
func cell_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		var s: Dictionary = sites[id]
		var d: Vector3 = p - s.pos
		var sp := spacing(s)
		var c := Vector2i(roundi(d.dot(_right(s)) / sp), roundi(-d.dot(s.dir) / sp))
		if c in s.cells and Geometry2D.is_point_in_polygon(q, cell_corners(s, c)):
			return id
	return -1


func at(p: Vector3) -> int:
	var id := site_at(p)
	return id if id != -1 else cell_at(p)


func covers(p: Vector3) -> bool:
	return at(p) != -1


func jobs() -> int:
	var total := 0.0
	for id in sites:
		var k: Dictionary = PLANTS[sites[id].plant]
		total += Balance.POWER_YARD_JOBS + float(k.jobs) * sites[id].cells.size()
	return roundi(total)


## Property value the city taxes (yards and units).
func taxable_value() -> float:
	var total := 0.0
	for id in sites:
		total += Balance.POWER_YARD_VALUE + float(PLANTS[sites[id].plant].capex) * sites[id].cells.size()
	return total


func yard(s: Dictionary) -> PackedVector2Array:
	var side := _right(s)
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = s.pos + side * HQ_SIZE.x * 0.5 * k.x + s.dir * HQ_SIZE.y * 0.5 * k.y
		out.append(Vector2(p.x, p.z))
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id in sites:
		var s: Dictionary = sites[id]
		var cells := []
		for c in s.cells:
			cells.append([c.x, c.y])
		var lane := []
		for p in s.drive:
			lane.append([p.x, p.z])
		out[str(id)] = {"plant": s.plant, "pos": [s.pos.x, s.pos.z], "dir": [s.dir.x, s.dir.z],
			"drive": lane, "cells": cells, "leader": s.leader, "why": s.why, "loss": s.loss_streak,
			"savings": s.savings, "upgrades": s.upgrades, "hired": s.hired}
	return {"sites": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	sales.clear()
	for k in d.get("sites", {}):
		var s: Dictionary = d.sites[k]
		var cells := []
		for c in s.cells:
			cells.append(Vector2i(int(c[0]), int(c[1])))
		var lane := []
		for p in s.drive:
			lane.append(Vector3(p[0], 0.0, p[1]))
		var leader: Dictionary = s.get("leader", {"name": "", "education": 0.5})
		sites[int(k)] = {"plant": str(s.plant), "pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": Vector3(s.dir[0], 0.0, s.dir[1]).normalized(), "drive": lane, "cells": cells,
			"leader": {"name": str(leader.name), "education": float(leader.education)},
			"why": str(s.get("why", "")), "loss_streak": int(s.get("loss", 0)),
			"savings": float(s.get("savings", 0.0)), "upgrades": Array(s.get("upgrades", [])).map(func(u): return str(u)),
			"hired": float(s.get("hired", 0.0))}
	_next_id = int(d.get("next_id", 1))
