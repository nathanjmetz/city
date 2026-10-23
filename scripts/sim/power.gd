class_name Power
extends RefCounted
## Power companies, Brawn's hub-with-a-leader model (Best of CS pitch #6,
## green-lit 2026-10-22). The regional grid through a substation stays the
## default; instead the player can place a power company's yard (switchyard
## and control building). It hires a leader, and the leader picks how to make
## power from what the land offers:
##   solar farm on open ground, wind farm on windy ridges and bluffs, a gas
##   plant near oil (the field's own gas), a
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

## The development tree (Agency format; Brawn: every hub gets a thick tree
## that depends on its leader, the town and the neighbors). `plants` limits
## a node to some plants; `gate` is a check Agency has no condition for
## (see gate_problem). Costs come out of the company's profit (Agency).
const TREE := [
	{"id": "training", "name": "Training center", "cost": 800_000, "needs": {"education": 0.3},
		"effects": {"jobs+": 4}, "note": "trains the next leader, who starts better schooled"},
	{"id": "scrubbers", "name": "Smokestack scrubbers", "cost": 2_000_000, "plants": ["coal"],
		"needs": {"leader_edu": 0.3}, "effects": {"smoke*": -0.5}, "note": "halves the smoke"},
	{"id": "repower", "name": "Switch to gas", "cost": 6_000_000, "plants": ["coal"], "gate": "oil",
		"needs": {"leader_edu": 0.45}, "effects": {}, "note": "the coal units become gas engines on the oil field's gas"},
	{"id": "battery", "name": "Battery yard", "cost": 1_500_000, "plants": ["solar", "wind"],
		"needs": {"leader_edu": 0.6}, "effects": {"output*": 0.25}, "note": "stores power for the evening"},
	{"id": "steam", "name": "Waste-heat line", "cost": 1_000_000, "plants": ["coal", "gas"], "gate": "industry",
		"needs": {"leader_edu": 0.35}, "effects": {"sales+": Balance.POWER_STEAM_SALES, "jobs+": 3},
		"note": "sells steam to the factories next door"},
	{"id": "blade_yard", "name": "Wind blade service yard", "cost": 1_200_000, "plants": ["wind"], "gate": "turbines",
		"needs": {"leader_edu": 0.5}, "effects": {"sales+": Balance.POWER_BLADE_YARD_SALES, "jobs+": 8},
		"note": "services its turbines and the region's"},
	{"id": "tie_line", "name": "Line to a neighbor", "cost": 3_000_000,
		"needs": {"leader_edu": 0.4, "region_buys:power": 1, "link": 1}, "effects": {"tie+": 1.0},
		"note": "sells spare power straight to a neighbor that's short, at the town price"},
	{"id": "lab", "name": "Grid research lab", "cost": 2_500_000, "requires": ["training"], "gate": "university",
		"needs": {"leader_edu": 0.7}, "effects": {"opex*": -0.1, "jobs+": 6}, "note": "cuts running costs by a tenth"},
]

const FIRST_NAMES := ["Dale", "Linda", "Gary", "Karen", "Ray", "Donna", "Curt", "Janet", "Wayne", "Peggy",
	"Doug", "Sheila", "Lyle", "Marcy", "Arnie", "Joanne", "Earl", "Deb", "Vern", "Lori"]
const LAST_NAMES := ["Kowalski", "Hendricks", "Schroeder", "Lindqvist", "McAllister", "Brandt", "Yoder",
	"Riggs", "Halvorsen", "Pruitt", "Gerber", "Dunlap", "Voss", "Tate", "Becker", "Ostrander"]

## Companies: id -> {plant, pos, dir, drive, cells: Array of Vector2i in its
## own frame (0,0 is the yard), leader: Agency.leader plus a name and
## "education" (= edu), reason (why this plant), why (Agency's last move),
## loss_streak, built: Array of TREE ids (Agency),
## hired (game day the leader took over)}
var sites := {}
## Set by the city: the industrial tax rate (percent).
var tax_rate := 1.5
## Where the city sits in the region (CitySim.terrain_offset): the real
## land is read there.
var offset := Vector2.ZERO
## Override for the river's flow at a point (tests); by default the real
## White River and its water from Terrain.
var river := Callable()
## Last decide step's sales, per company id: {"town": homes, "export": homes,
## "profit": $ a year}. Shown in the panel; worked out again each step.
var sales := {}
## Set by the city: true when a point is in a farmer's field. Wind pads
## may stand there on a lease (pad_usable), paying POWER_WIND_LEASE a year.
var on_farm := Callable()
var pad_usable := Callable()
## Line crews out on the road: trip id -> {"site", "home"} (home: on the
## way back to the yard).
var crews := {}
var _next_id := 1
## The Economy page's sliders: a company on Growth Hold adds no units or
## buildings beyond its first unit (set by CitySim).
var policies: Policies


## True if the player has told company `id` to hold off growing.
func on_hold(id: int) -> bool:
	return policies != null and policies.step("growth", "power", "power:%d" % id) == 0


# --- Where power comes from ---------------------------------------------------

## How windy a spot is, 0 to 1: open ridges and bluffs above the land
## around them (the real terrain), with a little smooth variation, the
## same for every player. Valley floors are calm.
func wind_at(p: Vector3) -> float:
	var x := p.x + offset.x
	var z := p.z + offset.y
	var h := Terrain.height(x, z)
	var around := 0.0
	for k in 8:
		var a := TAU * k / 8.0
		around += Terrain.height(x + cos(a) * 500.0, z + sin(a) * 500.0)
	var exposure := smoothstep(-2.0, 14.0, h - around / 8.0)
	var n := Resources.value_noise(Vector2(x, z) / 900.0, 53)
	return clampf(0.75 * exposure + 0.35 * n, 0.0, 1.0)


## The river at a point: 0 on dry land, 1 in the channel.
func river_at(p: Vector3) -> float:
	if river.is_valid():
		return clampf(float(river.call(p)), 0.0, 1.0)
	return clampf(Terrain.water(p.x + offset.x, p.z + offset.y), 0.0, 1.0)


## Where a dam at `p` spans the river: [one bank, the other bank], across
## the flow (the flow runs along the longest stretch of water through p).
## Empty when p isn't on the water.
func dam_span(p: Vector3) -> Array:
	if river_at(p) < 0.5:
		return []
	var best := Vector3.RIGHT
	var best_run := -1.0
	for k in 12:
		var a := PI * k / 12.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var run := _wet_run(p, d, 400.0) + _wet_run(p, -d, 400.0)
		if run > best_run:
			best_run = run
			best = d
	var across := Vector3(-best.z, 0.0, best.x)
	return [p - across * _wet_run(p, -across, 300.0), p + across * _wet_run(p, across, 300.0)]


## How far the water reaches from p along d, up to `most` metres.
func _wet_run(p: Vector3, d: Vector3, most: float) -> float:
	var t := 0.0
	while t < most and river_at(p + d * (t + 6.0)) >= 0.5:
		t += 6.0
	return t


## How well a plant of this kind works at a point, 0 to 1 (0 = can't).
func quality(plant: String, p: Vector3) -> float:
	match plant:
		"solar":
			# Open ground. Woods have to be cleared and shade the panels.
			return 1.0 - 0.5 * Resources.at(Resources.Kind.FOREST, p, offset)
		"wind":
			return wind_at(p)
		"hydro":
			return river_at(p)
	return 1.0


## Best quality within reach of a yard (a plant spreads a few hundred metres).
func reach_quality(plant: String, pos: Vector3) -> float:
	if plant == "gas":
		return gas(pos)
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
func gas(pos: Vector3) -> float:
	var best := 0.0
	for r in [0.0, 200.0, 400.0]:
		for i in (1 if r == 0.0 else 12):
			var a := TAU * i / 12.0
			best = maxf(best, Resources.at(Resources.Kind.OIL, pos + Vector3(cos(a), 0.0, sin(a)) * r, offset))
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
## Shaped like Agency.leader ({edu, caution, ambition}) with a name, and
## "education" kept equal to edu for the plant choice.
static func hire(town_education: float, city_seed: int, id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, id, "power leader"])
	var name := "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	var edu := snappedf(clampf(town_education + rng.randf_range(-1.0, 1.0) * Balance.POWER_LEADER_SPREAD, 0.0, 1.0), 0.01)
	return {"name": name, "education": edu, "edu": edu, "caution": snappedf(rng.randf(), 0.01),
		"ambition": snappedf(rng.randf(), 0.01)}


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
	var gas_here := gas(pos)
	var out := {}
	for plant in PLANTS:
		var k: Dictionary = PLANTS[plant]
		var q := reach_quality(plant, pos)
		if q < Balance.POWER_MIN_QUALITY:
			out[plant] = -INF
			continue
		var mwh := unit_homes(plant, q) * Balance.POWER_MWH_PER_HOME
		var margin: float = Balance.POWER_TOWN_PRICE - opex(plant, gas_here) + (Balance.POWER_FIRM_BONUS if k.firm else 0.0) \
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
		"reason": pick[1], "why": "", "loss_streak": 0, "built": [], "hired": day}
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
	return Agency.effect(s, TREE, "output*")


## A company's running cost per MWh, with its research lab.
func site_opex(s: Dictionary) -> float:
	return opex(s.plant, gas(s.pos)) * Agency.effect(s, TREE, "opex*")


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
	var extra := Agency.effect(s, TREE, "sales+") - leased(s) * Balance.POWER_WIND_LEASE \
		- _acres_leased(s) * Balance.POWER_SOLAR_LEASE_PER_ACRE
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
		if Agency.effect(s, TREE, "tie+") > 0.0:
			neighbor = minf(cap - town, short)
			short -= neighbor
		var export := 0.0
		if can_export and Balance.POWER_EXPORT_PRICE > op:
			export = cap - town - neighbor
		var profit := _profit(s, town, export, neighbor)
		sales[id] = {"town": roundi(town), "export": roundi(export), "neighbor": roundi(neighbor), "profit": profit}
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
		# A solar company boxed in by cornfields remembers which ones it
		# could lease; it asks the player before turning farmland to panels.
		var want := []
		if best == Vector2i.MAX and s.plant == "solar" and not s.cells.is_empty() \
				and s.cells.size() < int(k.max_cells) and pad_usable.is_valid() and on_farm.is_valid():
			for c in _frontier(s):
				var mid := cell_center(s, c)
				if quality(s.plant, mid) >= Balance.POWER_MIN_QUALITY and on_farm.call(mid) \
						and _free(id, s, c, pad_usable):
					want.append(c)
		s.farm_want = want
		if best != Vector2i.MAX:
			var add := unit_homes(s.plant, best_q) * _boost(s)
			var to_town := clampf(left - cap, 0.0, add)
			var to_region := (add - to_town) if export > 0.0 or (can_export and Balance.POWER_EXPORT_PRICE > op) else 0.0
			var gain := (to_town * (Balance.POWER_TOWN_PRICE - op) + to_region * (Balance.POWER_EXPORT_PRICE - op)) \
				* Balance.POWER_MWH_PER_HOME - float(k.capex) / horizon(s.leader) \
				- float(k.capex) * tax_rate / 100.0
			# A new company always opens its first unit: the player paid for it.
			if s.cells.is_empty() or gain > 0.0 and not on_hold(id):
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


## Once a month the leader looks over the development tree (Agency): a
## successor takes over when the term is up (better schooled with a
## training center), then the leader builds what it values most of what's
## open, paid from profit. `ctx` as in decide. Returns true if anything
## changed.
func develop(sim: CitySim, id: int, ctx: Dictionary) -> bool:
	var s: Dictionary = sites[id]
	var changed := false
	var day := float(ctx.get("day", 0.0))
	if day - float(s.hired) >= Balance.POWER_LEADER_TERM_DAYS:
		var edu := float(ctx.get("education", s.leader.education))
		if "training" in s.built:
			edu += Balance.POWER_TRAINING_LIFT
		s.leader = hire(edu, int(s.leader.name.hash()), id + int(day))
		s.hired = day
		changed = true
	if on_hold(id):
		return changed
	var built := Agency.develop(sim, s, tree_for(id, ctx), s.pos, float(sales.get(id, {}).get("profit", 0.0)))
	if built.is_empty():
		return changed
	if built.id == "repower":
		s.plant = "gas"
		while s.cells.size() > int(PLANTS.gas.max_cells):
			s.cells.pop_back()
		s.built.erase("scrubbers")
		s.reason = "%s switched the old coal units to gas from the oil field next door." % s.leader.name
	return true


## The tree as this company sees it: only nodes for its plant whose own
## checks (gate_problem) pass, so Agency weighs the rest.
func tree_for(id: int, ctx: Dictionary) -> Array:
	return TREE.filter(func(n): return gate_problem(id, n, ctx) == "")


## Why a node is closed to this company for reasons Agency has no condition
## for (its plant, oil nearby, factories nearby, turbines, a university), or
## "".
func gate_problem(id: int, node: Dictionary, ctx: Dictionary) -> String:
	var s: Dictionary = sites[id]
	var plants: Array = node.get("plants", [])
	if not plants.is_empty() and not s.plant in plants:
		return "Only for a %s." % " or ".join(plants.map(func(p): return PLANTS[p].name.to_lower()))
	match str(node.get("gate", "")):
		"oil":
			if gas(s.pos) <= 0.0 or s.cells.is_empty():
				return "Needs an oil field nearby."
		"university":
			if not ctx.get("university", false):
				return "Needs a university in town."
		"industry":
			var near: Callable = ctx.get("industry_near", Callable())
			if not near.is_valid() or not near.call(s.pos):
				return "Needs factories next door."
		"turbines":
			if s.cells.size() < 6:
				return "Needs 6 turbines."
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
	# A dam bay stands in the river itself, where nothing else can go.
	if s.plant == "wind" and pad_usable.is_valid():
		return pad_usable.call(mid, corners)
	return s.plant == "hydro" or usable.call(mid, corners)


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
		total += Balance.POWER_YARD_JOBS + float(k.jobs) * sites[id].cells.size() + Agency.effect(sites[id], TREE, "jobs+")
	return roundi(total)


## Property value the city taxes (yards and units).
func taxable_value() -> float:
	var total := 0.0
	for id in sites:
		total += Balance.POWER_YARD_VALUE + float(PLANTS[sites[id].plant].capex) * sites[id].cells.size()
	return total


## The service lanes between units: each unit hooks to the one next to it
## on the way back to the yard (cell 0,0 is the yard itself).
static func lanes(s: Dictionary) -> Array:
	var out := []
	for c in s.cells:
		var to := Vector2i.ZERO
		for d in [Vector2i(-signi(c.x), 0), Vector2i(0, -signi(c.y))]:
			if d != Vector2i.ZERO and (c + d == Vector2i.ZERO or (c + d) in s.cells):
				to = c + d
				break
		out.append([cell_center(s, c), cell_center(s, to)])
	return out


## The line to the neighbors, once its leader has built one: a 69 kV
## wood-pole line from the yard that follows the county roads (as rural
## co-op lines do, in the road right of way) to the nearest road out of
## town. Empty when there's no line or no road out.
func tie_route(net: RoadNetwork, links: Array, s: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	if Agency.effect(s, TREE, "tie+") <= 0.0 or links.is_empty() or s.drive.is_empty() or net.segments.is_empty():
		return out
	var gate: Vector3 = s.drive[-1]
	var hit := net.find_segment_near(gate, 60.0)
	if hit.is_empty():
		return out
	# Shortest way along the roads to any road out of town, starting both
	# ways from the yard's gate.
	var first: Dictionary = net.segments[hit.seg]
	var c0 := net.curve_of(hit.seg)
	var whole: float = c0[0].distance_to(c0[1]) + c0[1].distance_to(c0[2])
	var dist := {first.a: whole * hit.t, first.b: whole * (1.0 - hit.t)}
	var came := {first.a: [-1, hit.seg], first.b: [-1, hit.seg]}
	var open := [first.a, first.b]
	var goal := -1
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var n: int = open[bi]
		open.remove_at(bi)
		if n in links:
			goal = n
			break
		for sid in net.segments_at(n):
			var seg: Dictionary = net.segments[sid]
			var m: int = seg.b if seg.a == n else seg.a
			var c := net.curve_of(sid)
			var d: float = dist[n] + c[0].distance_to(c[1]) + c[1].distance_to(c[2])
			if d < dist.get(m, INF):
				dist[m] = d
				came[m] = [n, sid]
				if not m in open:
					open.append(m)
	if goal == -1:
		return out
	# Each leg: [segment, node it starts from (-1: the gate), node it ends at].
	var legs := []
	var n := goal
	while true:
		legs.push_front([came[n][1], came[n][0], n])
		if came[n][0] == -1:
			break
		n = came[n][0]
	out.append(s.pos)
	out.append(gate)
	for leg in legs:
		var sid: int = leg[0]
		var seg: Dictionary = net.segments[sid]
		var pts := net.sample_segment(sid, 16)
		if leg[1] == -1:
			# Only the part of the gate's road from the gate onward.
			var k := clampi(roundi(hit.t * 16.0), 0, 16)
			pts = pts.slice(k) if leg[2] == seg.b else pts.slice(0, k + 1)
		if seg.b != leg[2]:
			pts.reverse()
		# Poles stand just outside the right of way, on the right-hand side.
		var off := RoadStyle.right_of_way_half(seg.type) + Balance.POWER_TIE_SETBACK
		for i in pts.size():
			var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
			t.y = 0.0
			if t.length() < 0.01:
				continue
			t = t.normalized()
			var q := pts[i] + Vector3(-t.z, 0.0, t.x) * off
			out.append(Vector3(q.x, 0.0, q.z))
	return out


## Pole spots along a line, about one span apart, ends included.
static func poles(route: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if route.size() < 2:
		return out
	out.append(route[0])
	var since := 0.0
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var len := a.distance_to(b)
		var at := 0.0
		while since + (len - at) >= Balance.POWER_TIE_SPAN:
			at += Balance.POWER_TIE_SPAN - since
			since = 0.0
			out.append(a.lerp(b, at / len))
		since += len - at
	if out[-1].distance_to(route[-1]) > 5.0:
		out.append(route[-1])
	return out


## Line crews: every morning each company sends a bucket truck out to
## check its units, and one along its line to the neighbors, trimming trees
## and fixing what the weather broke (as co-op line crews do). A crew parks
## at the job, then drives back to the yard.
func crew_tick(sim: Object) -> void:
	for a in sim.traffic.arrivals:
		if crews.has(a.id):
			var c: Dictionary = crews[a.id]
			crews.erase(a.id)
			if not c.home and sites.has(c.site):
				var s: Dictionary = sites[c.site]
				_send(sim, c.site, c.at, s.drive[-1], true)
	for f in sim.traffic.failed:
		crews.erase(f.id)
	if sim.tick_count % (CitySim.TICKS_PER_HOUR * 24) != CitySim.TICKS_PER_HOUR * 7:
		return
	var ids := sites.keys()
	ids.sort()
	var day := int(sim.tick_count / (CitySim.TICKS_PER_HOUR * 24))
	for id in ids:
		var s: Dictionary = sites[id]
		if s.drive.is_empty() or s.cells.is_empty():
			continue
		var jobs := []
		var c: Vector2i = s.cells[absi(hash([id, day])) % s.cells.size()]
		jobs.append(cell_center(s, c))
		var line := tie_route(sim.network, sim.region_links, s)
		if line.size() > 2:
			jobs.append(line[2 + absi(hash([id, day, "line"])) % (line.size() - 2)])
		for at in jobs:
			_send(sim, id, s.drive[-1], at, false)


func _send(sim: Object, id: int, from: Vector3, to: Vector3, home: bool) -> void:
	var trip: int = sim.traffic.dispatch({"ref": "power:%d" % id, "pos": [from.x, from.z]},
		{"ref": "power:%d" % id if home else "line:%d" % id, "pos": [to.x, to.z]}, "power_line")
	if trip != -1:
		crews[trip] = {"site": id, "home": home, "at": to}


## Acres of former cropland a solar company rents from farmers.
static func _acres_leased(s: Dictionary) -> float:
	var total := 0.0
	for fid in s.get("leases", {}):
		total += float(s.leases[fid])
	return total


## What the solar companies pay farm `fid` a year for land it leased them.
func farm_rent(fid: int) -> float:
	var total := 0.0
	for id in sites:
		total += float(sites[id].get("leases", {}).get(str(fid), 0.0)) * Balance.POWER_SOLAR_LEASE_PER_ACRE
	return total


## Solar on farmland, through a land-use permit (it changes what the town
## is: cropland to panels). Once a month: carry out what the player
## approved (the outline may have been redrawn), or, when the company is
## boxed in by fields it would pay to lease, ask. True if anything changed.
func farmland(sim: CitySim, id: int) -> bool:
	var s: Dictionary = sites[id]
	var did := false
	for req in sim.permits.approved("power", id):
		did = _lease_fields(sim, id, req.route) or did
		sim.permits.done(int(req.id))
	var want: Array = s.get("farm_want", [])
	if want.is_empty() or on_hold(id) or not sim.permits.can_file(sim, "power", id):
		return did
	# Ask for a block of up to 2 x 2 cells around the best one, all fields.
	want.sort_custom(func(a, b): return quality(s.plant, cell_center(s, a)) > quality(s.plant, cell_center(s, b)))
	var c0: Vector2i = want[0]
	var block := [c0]
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		if block.size() >= 4:
			break
		if (c0 + d) in want:
			block.append(c0 + d)
	var lo := c0
	var hi := c0
	for c in block:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var sp := spacing(s)
	var half := float(PLANTS[s.plant].footprint) * 0.5
	var outline := []
	for corner in [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]:
		var sx := -1.0 if corner.x == lo.x else 1.0
		var sy := -1.0 if corner.y == lo.y else 1.0
		var p: Vector3 = s.pos + _right(s) * (corner.x * sp + sx * half) - s.dir * (corner.y * sp + sy * half)
		outline.append([p.x, p.z])
	var acres := float((hi.x - lo.x + 1) * (hi.y - lo.y + 1)) * sp * sp / 4046.86
	var farm_id: int = sim.farms.field_at(cell_center(s, c0))
	var owner: String = sim.families.name_of("farm:%d" % farm_id) if farm_id != -1 else ""
	sim.permits.file(sim, {"hub": "power", "hub_id": id, "leader": s.leader.name,
		"title": "Solar panels on %d acres of farmland" % roundi(acres),
		"why": "%s has run out of open ground next to the panels. %s would lease the field for $%s an acre a year instead of growing %s." % [
			s.leader.name, owner if owner != "" else "The farmer", CitySim.money_text(roundi(Balance.POWER_SOLAR_LEASE_PER_ACRE)),
			str(sim.farms.farms[farm_id].crop) if farm_id != -1 else "crops"],
		"change": "Farmland to solar panels", "area": outline, "per_m2": 0,
		"base": int(PLANTS[s.plant].capex) * block.size()})
	return true


## The farmers hand over their fields inside `route` (an outline) and the
## company fills the ground with panel rows.
func _lease_fields(sim: CitySim, id: int, route: Array) -> bool:
	var s: Dictionary = sites[id]
	var poly := PackedVector2Array()
	for p in route:
		poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() < 3:
		return false
	if not s.has("leases"):
		s.leases = {}
	var took := false
	var fids: Array = sim.farms.farms.keys()
	fids.sort()
	for fid in fids:
		var f: Dictionary = sim.farms.farms[fid]
		for c in f.cells.duplicate():
			var m: Vector3 = Farms.cell_center(f, c)
			if Geometry2D.is_point_in_polygon(Vector2(m.x, m.z), poly):
				f.cells.erase(c)
				s.leases[str(fid)] = float(s.leases.get(str(fid), 0.0)) + Farms.ACRES_PER_CELL
				took = true
	if took:
		sim.farms_changed.emit()
		sim.clear_usable_cache()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in poly:
		var d: Vector3 = Vector3(q.x, 0.0, q.y) - s.pos
		var g := Vector2(d.dot(_right(s)), -d.dot(s.dir)) / spacing(s)
		lo = lo.min(g)
		hi = hi.max(g)
	var added := false
	for y in range(floori(lo.y), ceili(hi.y) + 1):
		for x in range(floori(lo.x), ceili(hi.x) + 1):
			var c := Vector2i(x, y)
			var m := cell_center(s, c)
			if c in s.cells or c == Vector2i.ZERO or s.cells.size() >= int(PLANTS[s.plant].max_cells):
				continue
			if not Geometry2D.is_point_in_polygon(Vector2(m.x, m.z), poly) or not _free(id, s, c, pad_usable):
				continue
			s.cells.append(c)
			added = true
	if added:
		s.reason = "%s leased farmland for more panels, with your permit." % s.leader.name
	return took or added


## How many of a company's turbines stand on leased farmland.
func leased(s: Dictionary) -> int:
	if s.plant != "wind" or not on_farm.is_valid():
		return 0
	var n := 0
	for c in s.cells:
		if on_farm.call(cell_center(s, c)):
			n += 1
	return n


## What the power companies pay a year in leases for turbines inside this
## field outline (for the farm that owns it).
func lease_in(poly: PackedVector2Array) -> float:
	var total := 0.0
	for id in sites:
		var s: Dictionary = sites[id]
		if s.plant != "wind":
			continue
		for c in s.cells:
			var p := cell_center(s, c)
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
				total += Balance.POWER_WIND_LEASE
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
			"drive": lane, "cells": cells, "leader": s.leader, "reason": s.reason, "why": s.get("why", ""), "loss": s.loss_streak,
			"built": s.built, "hired": s.hired, "leases": s.get("leases", {})}
	return {"sites": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	crews.clear()
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
		var edu := float(leader.get("edu", leader.get("education", 0.5)))
		sites[int(k)] = {"plant": str(s.plant), "pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": Vector3(s.dir[0], 0.0, s.dir[1]).normalized(), "drive": lane, "cells": cells,
			"leader": {"name": str(leader.name), "education": edu, "edu": edu,
				"caution": float(leader.get("caution", 0.5)), "ambition": float(leader.get("ambition", 0.5))},
			"reason": str(s.get("reason", "")), "why": str(s.get("why", "")), "loss_streak": int(s.get("loss", 0)),
			"built": Array(s.get("built", [])).map(func(u): return str(u)),
			"hired": float(s.get("hired", 0.0))}
		var leases := {}
		for fid in s.get("leases", {}):
			leases[str(fid)] = float(s.leases[fid])
		sites[int(k)].leases = leases
	_next_id = int(d.get("next_id", 1))
