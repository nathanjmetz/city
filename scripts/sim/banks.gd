class_name Banks
extends RefCounted
## Banks, the way Brawn asked (2026-10-22, Best of CS pitch #20): a bank is
## a hub that lends to the other hubs. A farm borrows to buy the field next
## door, a company to put down another pad, and builders borrow to put up
## houses, shops and factories on zoned lots. The player places the bank and
## never touches a loan: its president decides.
##
## Benchmarked against real small-town Indiana banking:
##   - a community bank on the square (like the old First National Bank
##     on the square in Marion) takes the town's deposits and lends about
##     80 cents of each dollar back out, keeping 9% equity against its loans
##     (the FDIC's community bank leverage ratio)
##   - a Farm Credit branch office lends only to farms and timber, a little
##     cheaper, on money the Farm Credit System raises with bonds
## A cautious president wants a borrower's profit to cover the payments 1.3
## times over and lends 65% of the price; a bold one lends 85% on the land's
## value alone. Bold lending grows a town fast, until a bad crop year turns
## stretched loans into foreclosures: the farm loses the land it bought on
## credit and the bank takes the loss. A bank whose equity runs out goes
## under a regulator's order (no new loans), and if it keeps sinking the
## FDIC sells it to a healthier bank, which brings in a new president.
##
## It grows like every hub: only onto free land next to it, never a second
## branch, picking each new block from its development tree. Boxed in by
## roads, it fills the rest of its block up to the sidewalk with lawn and
## customer parking, never another building (Nathan, 2026-10-26: "when a hub
## with leader is "trapped" inside a road area, it should nicely fill in
## that area up to the edge (sidewalk) so that it looks like its using its
## space well."): edge pieces, BlockEdges. Numbers live in Balance (BANK*).

## One block of bank premises: a 36 m square, about a third of an acre (a
## brick bank on the square with its drive-up lanes behind fills one).
const CELL := 36.0
const KINDS := {
	"community": {"name": "Community bank", "head": "President", "icon": "bank_co"},
	"farm_credit": {"name": "Farm Credit office", "head": "Branch manager", "icon": "farm_credit"},
}
## Names a small-town bank takes (the common ones across rural Indiana).
const NAMES := ["First National Bank", "Farmers & Merchants Bank", "Peoples State Bank", "Citizens State Bank",
	"First State Bank", "Union Bank & Trust", "Home Savings Bank", "Merchants Bank"]

## The development tree (Agency format, see scripts/sim/agency.gd): each
## block the bank buys becomes one of these, never twice. `art` is how
## BankBuilder draws it. Effects: `deposits+` (more of the town's deposits),
## `rep+`, `farm+` / `company+` / `build+` / `timber+` (more appetite for that
## kind of loan), `overhead+` (share of running costs saved), `losses+`
## (share of default losses avoided), `jobs+`. Needs are Agency conditions
## (leader_edu, population, local:farm, local:forest, link, ...) plus the
## bank's own: shops and factories (zoned buildings in town), loans
## (dollars on its books) and capital (its equity).
const TREE := {
	"community": [
		{"id": "drive_up", "name": "Drive-up teller lanes", "art": "drive_up", "needs": {},
			"effects": {"deposits+": 0.15}},
		{"id": "atm", "name": "ATM vestibule", "art": "atm", "needs": {"population": 300},
			"effects": {"deposits+": 0.05}},
		{"id": "parking", "name": "Customer parking", "art": "parking", "needs": {"population": 600},
			"effects": {"deposits+": 0.05}},
		{"id": "ag_office", "name": "Ag lending office", "art": "office", "needs": {"local:farm": 2},
			"effects": {"farm+": 0.3, "jobs+": 2}},
		{"id": "commercial", "name": "Commercial lending department", "art": "office", "needs": {"factories": 2},
			"effects": {"company+": 0.3, "build+": 0.1, "jobs+": 3}},
		{"id": "mortgage", "name": "Mortgage and construction loan center", "art": "office",
			"needs": {"population": 1500}, "effects": {"build+": 0.3, "jobs+": 3}},
		{"id": "community_room", "name": "Community room", "art": "hall", "needs": {"population": 800},
			"effects": {"rep+": 0.06, "deposits+": 0.05}},
		{"id": "small_business", "name": "Small business lending office", "art": "office",
			"needs": {"shops": 15, "leader_edu": 0.5}, "effects": {"company+": 0.15, "build+": 0.1, "losses+": 0.1, "jobs+": 2}},
		{"id": "trust", "name": "Trust and wealth management", "art": "office",
			"needs": {"leader_edu": 0.6, "population": 2500}, "effects": {"deposits+": 0.2, "rep+": 0.05, "jobs+": 4}},
		{"id": "operations", "name": "Operations center", "art": "operations", "needs": {"loans": 40_000_000},
			"effects": {"overhead+": 0.15, "jobs+": 8}},
		{"id": "headquarters", "name": "Holding company headquarters", "art": "headquarters",
			"requires": ["commercial", "trust"], "needs": {"link": 1, "capital": 12_000_000},
			"effects": {"rep+": 0.08, "deposits+": 0.25, "jobs+": 20}},
	],
	"farm_credit": [
		{"id": "parking", "name": "Customer parking", "art": "parking", "needs": {}, "effects": {}},
		{"id": "appraisal", "name": "Rural appraisal office", "art": "office", "needs": {"leader_edu": 0.45},
			"effects": {"losses+": 0.15, "jobs+": 2}},
		{"id": "crop_insurance", "name": "Crop insurance desk", "art": "office", "needs": {"local:farm": 3},
			"effects": {"losses+": 0.25, "jobs+": 2}},
		{"id": "young_farmers", "name": "Young and beginning farmers program", "art": "hall",
			"needs": {"local:farm": 5}, "effects": {"farm+": 0.3}},
		{"id": "leasing", "name": "Equipment leasing office", "art": "office", "requires": ["appraisal"],
			"needs": {"local:farm": 4}, "effects": {"farm+": 0.15, "jobs+": 3}},
		{"id": "timber", "name": "Timber and agribusiness lending", "art": "office", "needs": {"local:forest": 1},
			"effects": {"timber+": 0.4, "jobs+": 2}},
		{"id": "grain_markets", "name": "Ag economist and grain marketing desk", "art": "office",
			"needs": {"region_makes:grain": 1, "leader_edu": 0.5}, "effects": {"farm+": 0.1, "losses+": 0.1, "jobs+": 1}},
	],
}

## Banks: id -> {kind, name, pos (centre of the first block), dir (unit,
## toward its road), blocks: [{c, use}], capital, deposits, loans: {who ->
## {kind, balance, pay (principal a month), cells: [[x, y]] pledged land}},
## reputation, leader {name, edu, caution, ambition} (Agency.leader), built
## (tree ids, for Agency), founded, status
## ("" sound, "order", or "sold" the month the FDIC sold it), year (this
## year's {lent, profit, foreclosed, losses}), made (loans so far),
## foreclosed (so far), idle (why it isn't growing, not saved), cleared,
## edge (its edge pieces up to the sidewalk: block -> outline, BlockEdges)}
var banks := {}
var _next_id := 1


static func spec(kind: String) -> Dictionary:
	return Balance.BANKS[kind]


## One development in the tree (empty if unknown, as in an older save).
static func dev(kind: String, use: String) -> Dictionary:
	for node in TREE[kind]:
		if node.id == use:
			return node
	return {}


static func _right(b: Dictionary) -> Vector3:
	return Vector3(-b.dir.z, 0.0, b.dir.x)


## Centre of a block (0,0 is the first building); +y runs away from the road.
static func block_center(b: Dictionary, cell: Vector2i) -> Vector3:
	var p: Vector3 = b.pos + _right(b) * (cell.x * CELL) - b.dir * (cell.y * CELL)
	return Vector3(p.x, 0.0, p.z)


static func block_corners(b: Dictionary, cell: Vector2i) -> PackedVector2Array:
	var mid := block_center(b, cell)
	var r: Vector3 = _right(b) * CELL * 0.5
	var back: Vector3 = -b.dir * CELL * 0.5
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * k.x + back * k.y
		out.append(Vector2(p.x, p.z))
	return out


## Where a bank goes when placed beside the street nearest `hit`: [centre,
## dir toward the street], or [] if no street is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := RoadIndex.segment_near(network, hit, 60.0, 1.0)
	if near.is_empty() or not RoadStyle.TYPES[network.segments[near.seg].type].lots:
		return []
	var c := network.curve_of(near.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	tan.y = 0.0
	tan = tan.normalized()
	var normal := Vector3(-tan.z, 0.0, tan.x)
	var p: Vector3 = near.point
	if (hit - p).dot(normal) < 0.0:
		normal = -normal
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + Services.SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * (front + CELL * 0.5), -normal]


## Why a bank can't go here, or "" if it can.
static func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> String:
	if not KINDS.has(kind):
		return "Unknown bank."
	var poly := block_corners({"pos": pos, "dir": dir}, Vector2i.ZERO)
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for p in _probe_points(pos, poly):
		if sim.banks.covers(p):
			return "Too close to another bank. Banks grow next door, so give it room."
		var why := ground_problem(sim, p)
		if why != "":
			return why
	return ""


## What else owns the ground at a point (or why it can't be built on), or "".
static func ground_problem(sim: CitySim, p: Vector3) -> String:
	if not sim.land_ok(p):
		return "Can't build in the water or on a slope that steep."
	if sim.services.covers(p):
		return "Overlaps a service building."
	var owner := Capital.owner_of(sim, p)
	if owner.begins_with("farm:"):
		return "That ground is farmland."
	if owner.begins_with("site:") or sim.power.covers(p):
		return "That ground belongs to a company."
	if sim.reserves.kind_at(p) != "":
		return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(p)]
	if sim.education.covers(p):
		return "That ground is a campus."
	if sim.hubs.covers(p) or sim.warehouses.covers(p) or sim.parks.covers(p) or sim.mail.covers(p):
		return "Overlaps a landfill, cemetery, warehouse, park or post office."
	if sim.telecom.covers(p):
		return "That ground belongs to the phone company."
	return ""


static func _probe_points(mid: Vector3, poly: PackedVector2Array) -> Array:
	var pts := [mid]
	for q in poly:
		pts.append(mid.lerp(Vector3(q.x, 0.0, q.y), 0.85))
	for i in poly.size():
		var e := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
		pts.append(mid.lerp(Vector3(e.x, 0.0, e.y), 0.85))
	return pts


## Opens a bank and hires its president. `seed` makes the hire the same on
## every copy of the city.
func add(sim: CitySim, kind: String, pos: Vector3, dir: Vector3, seed: int, tick: int) -> int:
	var id := _next_id
	_next_id += 1
	var leader := hire(sim, hash([seed, id, kind, "bank"]))
	banks[id] = {"kind": kind, "name": _pick_name(kind, hash([seed, id])), "pos": pos, "dir": dir, "blocks": [],
		"capital": float(spec(kind).capital), "deposits": 0.0, "loans": {},
		"reputation": Balance.BANK_START_REPUTATION, "leader": leader, "built": [], "founded": tick, "status": "",
		"year": _new_year(), "made": 0, "foreclosed": 0, "idle": "", "cleared": [], "edge": {}}
	return id


## A president or branch manager: the shared leader (Agency.leader, whose
## schooling follows the town's) with a name. A bank also hires among the
## town's college graduates, so the better of the two counts.
static func hire(sim: CitySim, seed: int) -> Dictionary:
	var l := Agency.leader(sim, seed)
	l.edu = maxf(float(l.edu), snappedf(sim.education.leader_education(sim.stats.workers) * 0.8, 0.01))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	l.name = "%s %s" % [Education.FIRST[rng.randi() % Education.FIRST.size()], Education.LAST[rng.randi() % Education.LAST.size()]]
	return l


func _pick_name(kind: String, seed: int) -> String:
	if kind == "farm_credit":
		return "Farm Credit Services"
	var used := {}
	for id in banks:
		used[banks[id].name] = true
	for i in NAMES.size():
		var n: String = NAMES[(absi(seed) + i) % NAMES.size()]
		if not used.has(n):
			return n
	return NAMES[absi(seed) % NAMES.size()]


static func _new_year() -> Dictionary:
	return {"lent": 0.0, "profit": 0.0, "foreclosed": 0, "losses": 0.0}


## How the president runs it, in a few words.
static func leader_style(l: Dictionary) -> String:
	if l.caution >= 0.6:
		return "cautious lender" + (", ambitious" if l.ambition >= 0.6 else "")
	if l.caution <= 0.35:
		return "bold lender" + (", ambitious" if l.ambition >= 0.6 else "")
	return "steady lender" + (", ambitious" if l.ambition >= 0.6 else "")


## The sum of one effect over the bank's blocks ("deposits", "farm", ...).
static func effect(b: Dictionary, what: String) -> float:
	return Agency.effect(b, TREE[b.kind], what + "+")


static func loans_total(b: Dictionary) -> float:
	var t := 0.0
	for who in b.loans:
		t += float(b.loans[who].balance)
	return t


## Equity against loans: 9% or more is well capitalized.
static func capital_ratio(b: Dictionary) -> float:
	var l := loans_total(b)
	return 1.0 if l <= 0.0 else float(b.capital) / l


static func health(b: Dictionary) -> String:
	var r := capital_ratio(b)
	if b.status == "order" or r < Balance.BANK_ORDER:
		return "order"
	if r < Balance.BANK_WELL_CAPITALIZED:
		return "adequate"
	return "well"


static func rate(b: Dictionary) -> float:
	return Balance.BANK_FARM_CREDIT_RATE if b.kind == "farm_credit" else Balance.BANK_LOAN_RATE


## Loan to value, coverage wanted and appetite all follow the president's caution.
static func ltv(b: Dictionary) -> float:
	return lerpf(Balance.BANK_LTV[1], Balance.BANK_LTV[0], float(b.leader.caution))


static func dscr_needed(b: Dictionary) -> float:
	return lerpf(Balance.BANK_DSCR[0], Balance.BANK_DSCR[1], float(b.leader.caution))


## Chance it says yes to a borrower who qualifies, this round.
func appetite(sim: CitySim, id: int, what: String) -> float:
	var b: Dictionary = banks[id]
	var h := health(b)
	if h == "order":
		return 0.0
	var a := lerpf(Balance.BANK_APPETITE[0], Balance.BANK_APPETITE[1], float(b.leader.caution)) \
		* (1.0 + effect(b, what)) * (0.5 if h == "adequate" else 1.0)
	match sim.permits.guidance("bank", id).stance:
		"grow": a *= 1.25
		"hold": a *= 0.5
	return clampf(a, 0.0, 1.0)


## Dollars it could still lend: a community bank up to its loan-to-deposit
## target and its capital rule, Farm Credit up to its share of the farmland.
func room(sim: CitySim, id: int) -> float:
	var b: Dictionary = banks[id]
	var lent := loans_total(b)
	var by_capital: float = float(b.capital) / Balance.BANK_WELL_CAPITALIZED * (1.15 if b.leader.caution < 0.35 else 1.0)
	var by_funds: float
	if b.kind == "farm_credit":
		by_funds = farmland_value(sim) * Balance.BANK_FARM_CREDIT_SHARE
	else:
		by_funds = float(b.deposits) * lerpf(Balance.BANK_LTD[1], Balance.BANK_LTD[0], float(b.leader.caution)) \
			+ float(b.capital) * 0.5
	return maxf(0.0, minf(by_funds, by_capital) - lent)


static func farmland_value(sim: CitySim) -> float:
	return maxf(sim.farms.total_acres(), sim.farms.held_acres()) * Farms.LAND_PER_ACRE


static func _years(what: String) -> float:
	return float(Balance.BANK_TERM_YEARS.get(what, 20))


## What this borrower owes all the banks in town, and pays a year on it.
func debt_service(who: String) -> float:
	var total := 0.0
	for id in banks:
		var l: Dictionary = banks[id].loans.get(who, {})
		if not l.is_empty():
			total += float(l.balance) * (rate(banks[id]) + 1.0 / _years(str(l.kind)))
	return total


## Debt service coverage for a borrower: yearly profit over yearly payments
## (with `extra` dollars more borrowed and `extra_profit` more earned).
func coverage(sim: CitySim, who: String, extra := 0.0, extra_profit := 0.0, r := Balance.BANK_LOAN_RATE,
		what := "farm") -> float:
	var profit := _profit(sim, who) + extra_profit
	var service := debt_service(who) + extra * (r + 1.0 / _years(what))
	if service <= 0.0:
		return INF
	return profit / service


func _profit(sim: CitySim, who: String) -> float:
	var parts := who.split(":")
	match parts[0]:
		"farm":
			return sim.farms.yearly_profit(int(parts[1])) if sim.farms.farms.has(int(parts[1])) else 0.0
		"site":
			return sim.industry.yearly_profit(int(parts[1])) if sim.industry.sites.has(int(parts[1])) else 0.0
		"build":
			# A building's rent or sales cover its mortgage while people want
			# to live or shop there; a glut of empty space doesn't.
			var key := who.substr(6)
			if not sim.buildings.has(key):
				return 0.0
			var z: int = sim.buildings[key].zone
			var cover: float = 0.7 + float(sim.demand.get(z, 0.5))
			return cover * debt_service(who)
	return 0.0


## The lender a borrower goes to for a loan of this kind: the cheapest bank
## in town with room that lends for it. -1 if none.
func lender_for(sim: CitySim, what: String, amount: float) -> int:
	var best := -1
	var best_rate := INF
	var ids := banks.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = banks[id]
		if not what in spec(b.kind).lends or health(b) == "order":
			continue
		if room(sim, id) < amount:
			continue
		if rate(b) < best_rate - 0.00001:
			best_rate = rate(b)
			best = id
	return best


## A random number 0..1, the same on every copy of the city.
static func _roll(sim: CitySim, salt: Array) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, sim.tick_count] + salt)
	return rng.randf()


## One lending round, run with the farms' and companies' own step: every
## farm and company that has land worth buying next door asks for a loan to
## buy one more, and each bank says yes or no. Returns
## {"farms": bool, "industry": bool}: who bought land on credit.
func lend(sim: CitySim) -> Dictionary:
	var out := {"farms": false, "industry": false}
	if banks.is_empty():
		return out
	var ids := sim.farms.farms.keys()
	ids.sort()
	for fid in ids:
		var f: Dictionary = sim.farms.farms[fid]
		if not f.barn:
			continue
		var c := sim.farms.best_field(fid, sim.field_usable)
		if c == Vector2i.MAX:
			continue
		# A farm borrows for ground it wants but can't take on out of its
		# own savings (Capital): an operating loan for the equipment and
		# inputs to rent it, or, where land near town isn't rented out, a
		# land loan for the bank's share of the price.
		var k := Farms.field_of(c)
		if not f.has("own"):
			f.own = Farms.start_fields()
		if not f.has("rent"):
			f.rent = []
		if k in f.own or k in f.rent:
			continue
		var price := sim.farms.field_price(f, k)
		var acres := Farms.field_cells(f, k).size() * Farms.ACRES_PER_CELL
		var rentable := price / acres <= Balance.CAPITAL_LAND_PER_ACRE * (1.0 + Balance.CAPITAL_RENT_MAX_PREMIUM)
		var start := acres * Balance.CAPITAL_OPEN_PER_ACRE
		var cash := float(f.get("cash", 0.0))
		var who := "farm:%d" % fid
		var gain := sim.farms.field_gain(f, k)
		if rentable:
			if cash >= start:
				continue
			if _approve(sim, who, "farm", start, gain, c):
				f.cash = cash + _last_amount - start
				f.rent.append(k)
				f.cells.append(c)
				f.why = "It rented %d more acres from a neighbour, with an operating loan from the bank for the equipment and inputs." % roundi(acres)
				out.farms = true
			continue
		var profit := sim.farms.yearly_profit(fid)
		if Capital.can_buy(f, price, Capital.kept(f, "farm", Capital.steady(f, profit) + gain)) \
				or cash < price * (1.0 - Balance.BANK_LTV[1]):
			continue
		if _approve(sim, who, "farm", price, gain, c):
			f.cash = cash - (price - _last_amount)
			f.own.append(k)
			f.cells.append(c)
			f.why = "It bought %d more acres with a loan from the bank." % roundi(acres)
			out.farms = true
	ids = sim.industry.sites.keys()
	ids.sort()
	for sid in ids:
		var s: Dictionary = sim.industry.sites[sid]
		if s.pads.is_empty():
			continue
		var what := "timber" if s.kind == "forest" else "company"
		var who := "site:%d" % sid
		var c := sim.industry.best_pad(sid, sim.field_usable)
		if c == Vector2i.MAX:
			continue
		var value := float(Balance.INDUSTRY_PAD_VALUE)
		if _approve(sim, who, what, value, sim.industry.pad_profit(s, c), c) \
				or (what == "timber" and _approve(sim, who, "company", value, sim.industry.pad_profit(s, c), c)):
			sim.industry.sites[sid].pads.append(c)
			out.industry = true
	return out


## A builder asks for a construction loan for one more building this round.
## True when a bank in town says yes (the city then builds on a zoned lot
## and calls financed() with it).
func builds_more(sim: CitySim) -> bool:
	if banks.is_empty():
		return false
	var amount: float = Balance.BANK_BUILD_VALUE[ZoneMap.Zone.RESIDENTIAL] * 0.75
	var id := lender_for(sim, "build", amount)
	if id == -1:
		return false
	return _roll(sim, [id, "build"]) < appetite(sim, id, "build") * Balance.BANK_BUILD_CHANCE


## Books the construction loan for a building the city just put up on credit.
func financed(sim: CitySim, key: String) -> void:
	if not sim.buildings.has(key):
		return
	var z: int = sim.buildings[key].zone
	var value: float = Balance.BANK_BUILD_VALUE.get(z, 260_000)
	var id := lender_for(sim, "build", value * Balance.BANK_LTV[0])
	if id == -1:
		return
	_book(id, "build:" + key, "build", value * ltv(banks[id]), Vector2i.MAX)


## The loan decision for buying one field or pad: the cheapest bank with
## room, its LTV, the coverage its president wants, and its appetite.
## What the last approved loan lent.
var _last_amount := 0.0


func _approve(sim: CitySim, who: String, what: String, value: float, new_profit: float, cell: Vector2i) -> bool:
	var id := lender_for(sim, what, value * Balance.BANK_LTV[0])
	if id == -1:
		return false
	var b: Dictionary = banks[id]
	var amount := value * ltv(b)
	# Profit that covers the payments, or else enough equity in the land:
	# a bold president lends on the land's value (as banks did in the 1970s
	# farm boom), a cautious one hardly at all.
	if coverage(sim, who, amount, new_profit, rate(b), what) < dscr_needed(b) \
			and debt(who) + amount > (collateral(sim, who) + value) * ltv(b) * (1.0 - float(b.leader.caution)):
		return false
	if _roll(sim, [id, who]) >= appetite(sim, id, what):
		return false
	_book(id, who, what, amount, cell)
	_last_amount = amount
	return true


## What a borrower owes every bank in town.
func debt(who: String) -> float:
	var total := 0.0
	for id in banks:
		total += float(banks[id].loans.get(who, {}).get("balance", 0.0))
	return total


## What a borrower's land is worth: a farm's fields, a company's pads.
static func collateral(sim: CitySim, who: String) -> float:
	var parts := who.split(":")
	match parts[0]:
		"farm":
			if sim.farms.farms.has(int(parts[1])):
				return sim.farms.farms[int(parts[1])].cells.size() * Farms.LAND_PER_ACRE * Farms.ACRES_PER_CELL
		"site":
			if sim.industry.sites.has(int(parts[1])):
				return sim.industry.sites[int(parts[1])].pads.size() * Balance.INDUSTRY_PAD_VALUE
	return 0.0


func _book(id: int, who: String, what: String, amount: float, cell: Vector2i) -> void:
	var b: Dictionary = banks[id]
	if not b.loans.has(who):
		b.loans[who] = {"kind": what, "balance": 0.0, "pay": 0.0, "cells": []}
	var l: Dictionary = b.loans[who]
	# Money in whole dollars: a dollar is nothing to a bank, and a whole
	# number comes back from a save exactly, so a loaded copy of the town
	# keeps the same books to the cent (fractions drifted in the last
	# digits after a reload; review, 2026-10-26).
	l.balance = roundf(float(l.balance) + amount)
	l.pay = roundf(float(l.pay) + amount / (_years(what) * 12.0))
	if cell != Vector2i.MAX:
		l.cells.append([cell.x, cell.y])
	b.year.lent = roundf(float(b.year.lent) + amount)
	b.made += 1


## Every bank closes its month: deposits come in, interest and payments
## settle, borrowers who can't pay default (and lose the land they pledged),
## regulators step in on a bank short of equity, and its president decides
## whether to buy the next block of premises. Returns
## {"banks", "farms", "industry"}: what changed.
func decide(sim: CitySim) -> Dictionary:
	var out := {"banks": false, "farms": false, "industry": false}
	if banks.is_empty():
		return out
	var ids := banks.keys()
	ids.sort()
	_share_deposits(sim, ids)
	var facts := town_facts(sim)
	var new_year: bool = sim.clock().month == 1
	for id in ids:
		var b: Dictionary = banks[id]
		var s: Dictionary = spec(b.kind)
		var r := rate(b)
		var income := 0.0
		var losses := 0.0
		var whos: Array = b.loans.keys()
		whos.sort()
		for who in whos:
			var l: Dictionary = b.loans[who]
			if not _still_there(sim, who):
				# Paid off: the farm, company or building was sold or cleared.
				b.loans.erase(who)
				continue
			income += float(l.balance) * r / 12.0
			l.balance = roundf(float(l.balance) - float(l.pay))
			if l.balance <= 1.0:
				b.loans.erase(who)
				continue
			var cov := coverage(sim, who)
			var p := Balance.BANK_DEFAULT_BASE + Balance.BANK_DEFAULT_STRESS * maxf(0.0, 1.0 - cov)
			if _roll(sim, [id, who, "default"]) < p:
				var loss: float = float(l.balance) * (1.0 - Balance.BANK_RECOVERY) * (1.0 - minf(0.8, effect(b, "losses")))
				losses += loss
				var hit := _foreclose(sim, who, l)
				out.farms = out.farms or hit == "farm"
				out.industry = out.industry or hit == "site"
				b.loans.erase(who)
				b.foreclosed += 1
				b.year.foreclosed += 1
		var lent := loans_total(b)
		var funding := lent * Balance.BANK_FARM_CREDIT_FUNDING if b.kind == "farm_credit" \
			else float(b.deposits) * Balance.BANK_DEPOSIT_RATE
		var costs: float = funding / 12.0 + staff(b) * Balance.BANK_SALARY / 12.0 \
			+ (1 + b.blocks.size()) * Balance.BANK_PREMISES_COST / 12.0 * (1.0 - effect(b, "overhead"))
		losses = roundf(losses)
		var profit: float = roundf(income - costs - losses)
		b.year.profit = float(b.year.profit) + profit
		b.year.losses = float(b.year.losses) + losses
		# Shareholders take a share of a good month; a bad one comes out of equity.
		b.capital = float(b.capital) + (roundf(profit * (1.0 - Balance.BANK_DIVIDEND)) if profit > 0.0 else profit)
		_regulate(sim, id, b)
		var target: float = 0.25 + 0.25 * float(b.leader.edu) + 0.2 * (1.0 if health(b) == "well" else 0.0) \
			+ 0.05 * b.blocks.size() + effect(b, "rep") - 0.1 * minf(1.0, b.year.foreclosed / 5.0)
		b.reputation = clampf(b.reputation + (target - b.reputation) * Balance.BANK_REPUTATION_PULL, 0.0, 1.0)
		var idle := _grow(sim, id, b, facts)
		if idle == "changed":
			out.banks = true
			idle = ""
		# Boxed in by roads: lawn and parking up to the sidewalk.
		if BlockEdges.due(sim.tick_count, Balance.BANK_DECIDE_EVERY, id) \
				and sim.permits.guidance("bank", id).stance != "hold" and take_edges(sim, id):
			out.banks = true
		if b.idle != idle:
			b.idle = idle
			out.banks = true
		if new_year:
			b.last_year = b.year
			b.year = _new_year()
	return out


## Splits the town's deposits among its community banks by reputation and
## premises (a drive-up and a trust department pull deposits in).
func _share_deposits(sim: CitySim, ids: Array) -> void:
	var pool: float = (sim.stats.population * Balance.BANK_DEPOSITS_PER_RESIDENT
		+ sim.stats.jobs * Balance.BANK_DEPOSITS_PER_JOB) * Balance.BANK_LOCAL_SHARE
	var weights := {}
	var total := 0.0
	for id in ids:
		if banks[id].kind != "community":
			continue
		var w: float = maxf(0.05, banks[id].reputation) * (1.0 + effect(banks[id], "deposits"))
		weights[id] = w
		total += w
	for id in ids:
		if weights.has(id):
			# One bank alone doesn't get every local dollar: some go to the
			# nearest bigger town's banks until it has a drive-up and a name.
			var alone := 0.6 + 0.4 * minf(1.0, banks[id].reputation + effect(banks[id], "deposits"))
			banks[id].deposits = pool * weights[id] / total * (alone if weights.size() == 1 else 1.0)


static func staff(b: Dictionary) -> int:
	return int(spec(b.kind).staff) + floori(loans_total(b) / Balance.BANK_LOANS_PER_STAFF) + int(effect(b, "staff"))


func _still_there(sim: CitySim, who: String) -> bool:
	var parts := who.split(":")
	match parts[0]:
		"farm": return sim.farms.farms.has(int(parts[1]))
		"site": return sim.industry.sites.has(int(parts[1]))
		"build": return sim.buildings.has(who.substr(6))
	return false


## A borrower who can't pay loses what they pledged: the fields or pads
## bought with the loan go back up for sale. A building just changes hands.
## Returns "farm", "site" or "".
func _foreclose(sim: CitySim, who: String, l: Dictionary) -> String:
	var parts := who.split(":")
	var lost := false
	match parts[0]:
		"farm":
			var f: Dictionary = sim.farms.farms[int(parts[1])]
			for c in l.cells:
				var cell := Vector2i(int(c[0]), int(c[1]))
				if cell in f.cells:
					f.cells.erase(cell)
					lost = true
			return "farm" if lost else ""
		"site":
			var s: Dictionary = sim.industry.sites[int(parts[1])]
			for c in l.cells:
				var cell := Vector2i(int(c[0]), int(c[1]))
				if cell in s.pads:
					s.pads.erase(cell)
					lost = true
			return "site" if lost else ""
	return ""


## Regulators: a bank under 6% equity is put under an order and stops
## lending until it is back over 9%; under 2% the FDIC closes it and sells it
## to a healthier bank, which puts in equity and a new, careful president.
func _regulate(sim: CitySim, id: int, b: Dictionary) -> void:
	var r := capital_ratio(b)
	if b.status == "sold":
		b.status = ""
	if r < Balance.BANK_FAILED or b.capital < 0.0:
		b.capital = roundf(loans_total(b) * Balance.BANK_WELL_CAPITALIZED)
		var l := hire(sim, hash([sim.city_seed, id, sim.tick_count, "fdic"]))
		l.caution = maxf(float(l.caution), 0.65)
		b.leader = l
		b.reputation *= 0.5
		b.status = "sold"
		b.failures = int(b.get("failures", 0)) + 1
	elif r < Balance.BANK_ORDER:
		b.status = "order"
	elif b.status == "order" and r >= Balance.BANK_WELL_CAPITALIZED:
		b.status = ""


## Counts the bank's own tree conditions need: zoned shops and factories.
static func town_facts(sim: CitySim) -> Dictionary:
	var f := {"shops": 0, "factories": 0}
	for key in sim.buildings:
		match int(sim.buildings[key].zone):
			ZoneMap.Zone.COMMERCIAL: f.shops += 1
			ZoneMap.Zone.INDUSTRIAL: f.factories += 1
	return f


## True when one tree condition holds for this bank.
static func holds(sim: CitySim, b: Dictionary, facts: Dictionary, cond: String, value) -> bool:
	match cond:
		"shops": return facts.shops >= int(value)
		"factories": return facts.factories >= int(value)
		"loans": return loans_total(b) >= float(value)
		"capital": return float(b.capital) >= float(value)
	return Agency.holds(sim, b, b.pos, float(b.year.profit) * 12.0, cond, value)


## Why a development isn't open to this bank yet, or "" if it is.
static func locked_by(sim: CitySim, b: Dictionary, use: String, facts: Dictionary) -> String:
	var d := dev(b.kind, use)
	if use in b.get("built", []):
		return "built"
	for r in d.get("requires", []):
		if not r in b.get("built", []):
			return "needs a %s first" % dev(b.kind, r).name.to_lower()
	var n: Dictionary = d.get("needs", {})
	for cond in n:
		if holds(sim, b, facts, cond, n[cond]):
			continue
		var v = n[cond]
		match cond:
			"leader_edu": return "needs a %s with a %s" % [KINDS[b.kind].head.to_lower(), Education.degree_name(float(v))]
			"population": return "needs a town of %s" % CitySim.money_text(int(v))
			"local:farm": return "needs %d farms nearby" % int(v)
			"local:forest": return "needs a forestry company nearby"
			"factories": return "needs %d factories in town" % int(v)
			"shops": return "needs %d shops in town" % int(v)
			"loans": return "needs $%s in loans" % CitySim.money_text(int(v))
			"capital": return "needs $%s of equity" % CitySim.money_text(int(v))
			"link": return "needs a road out to the region"
		if str(cond).begins_with("region_makes:"):
			return "needs a neighboring town that sells %s" % str(cond).substr(13)
		return "not yet"
	return ""


## Which open development its president builds next: what brings in the
## loans and deposits the town calls for, weighed by ambition. "" if none.
static func pick_next(sim: CitySim, b: Dictionary, facts: Dictionary) -> String:
	var l: Dictionary = b.leader
	var best := ""
	var best_score := -INF
	for d in TREE[b.kind]:
		if locked_by(sim, b, d.id, facts) != "":
			continue
		var e: Dictionary = d.get("effects", {})
		var score: float = float(e.get("deposits+", 0.0)) * 4.0 \
			+ (float(e.get("farm+", 0.0)) + float(e.get("company+", 0.0)) + float(e.get("build+", 0.0))
				+ float(e.get("timber+", 0.0))) * 3.0 * (0.5 + l.ambition) \
			+ float(e.get("rep+", 0.0)) * 10.0 * (0.5 + l.ambition) \
			+ (float(e.get("losses+", 0.0)) + float(e.get("overhead+", 0.0))) * 3.0 * (0.5 + l.caution) + 0.01
		if score > best_score + 0.0001 or (absf(score - best_score) <= 0.0001 and str(d.id) < best):
			best_score = score
			best = d.id
	return best


## Its president buys the next block when the bank is sound, busy and has
## the equity to spare. Returns "changed", or why it isn't growing ("").
func _grow(sim: CitySim, id: int, b: Dictionary, facts: Dictionary) -> String:
	var s: Dictionary = spec(b.kind)
	if health(b) == "order":
		return "Under a regulator's order: no new loans until its equity is back over 9%."
	if sim.permits.guidance("bank", id).stance == "hold":
		return ""
	if b.blocks.size() >= int(s.max_blocks):
		return ""
	var use := pick_next(sim, b, facts)
	if use == "":
		return ""
	# Equity to spare: what the capital rule needs for today's loans, plus
	# the block, plus a cushion that a cautious president keeps bigger.
	var spare := float(b.capital) - loans_total(b) * Balance.BANK_WELL_CAPITALIZED * (1.0 + float(b.leader.caution))
	if spare < float(s.block_cost) * (1.5 - float(b.leader.ambition)):
		return ""
	var cell := _best_block(sim, id, b)
	if cell == Vector2i.MAX:
		return "Boxed in: no free land next to it for its %s." % dev(b.kind, use).name.to_lower()
	b.blocks.append({"c": cell, "use": use})
	# An edge piece a road has since let go of becomes a whole block.
	b.get("edge", {}).erase(cell)
	b.built.append(use)
	b.why = "%s built %s." % [str(b.leader.name), dev(b.kind, use).name.to_lower()]
	b.capital -= float(s.block_cost)
	return "changed"


func _best_block(sim: CitySim, id: int, b: Dictionary) -> Vector2i:
	var corr := RoadWins.corridors(sim.network, 2.0)
	var best := Vector2i.MAX
	var best_score := -INF
	for cell in _frontier(b):
		if not usable(sim, id, b, cell, corr):
			continue
		# Along the street first (a second storefront), then behind.
		var score: float = 2.0 * _neighbors(b, cell) - Vector2(cell).length() - 0.5 * cell.y
		if score > best_score + 0.001:
			best_score = score
			best = cell
	return best


## True when a block is free to buy: no road, building, zoned lot, farm,
## company, campus or reserve on it (what the player built stays theirs).
func usable(sim: CitySim, id: int, b: Dictionary, cell: Vector2i, corr: Array) -> bool:
	var poly := block_corners(b, cell)
	if RoadWins.hits(corr, poly):
		return false
	var mid := block_center(b, cell)
	for p in _probe_points(mid, poly):
		var other := at(p)
		if other != -1 and other != id:
			return false
		if ground_problem(sim, p) != "":
			return false
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), poly) \
				or sim.lots[key].pos.distance_to(mid) < CELL * 0.5:
			return false
	return true


static func _frontier(b: Dictionary) -> Array:
	var have := {Vector2i.ZERO: true}
	for blk in b.blocks:
		have[blk.c] = true
	var out := []
	var seen := {}
	for cell in b.get("cleared", []):
		seen[cell] = true
	var keys := have.keys()
	keys.sort()
	for h in keys:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = h + d
			if not have.has(n) and not seen.has(n) and n.y >= 0:
				seen[n] = true
				out.append(n)
	return out


static func _neighbors(b: Dictionary, cell: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if cell + d == Vector2i.ZERO:
			n += 1
		for blk in b.blocks:
			if blk.c == cell + d:
				n += 1
	return n


## The bank with a block or an edge piece on this point, or -1.
func at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in banks:
		var b: Dictionary = banks[id]
		var d: Vector3 = p - b.pos
		var cell := Vector2i(roundi(d.dot(_right(b)) / CELL), roundi(-d.dot(b.dir) / CELL))
		if cell != Vector2i.ZERO:
			var found := false
			for blk in b.blocks:
				found = found or blk.c == cell
			if not found:
				# An edge piece (looked up by its block first: a quick no).
				if b.edge.has(cell) and BlockEdges.on_edge(b, CELL, p):
					return id
				continue
		if Geometry2D.is_point_in_polygon(q, block_corners(b, cell)):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return not banks.is_empty() and at(p) != -1


## All the ground a bank holds, as outlines (x, z): its first building's
## block, each block it bought, then each edge piece.
static func land_polys(b: Dictionary) -> Array:
	var out := [block_corners(b, Vector2i.ZERO)]
	for blk in b.blocks:
		out.append(block_corners(b, blk.c))
	return out + BlockEdges.edge_polys(b, CELL)


## Takes the edge pieces that fit round bank `id`, up to the sidewalk.
func take_edges(sim: CitySim, id: int) -> bool:
	return BlockEdges.take(sim, banks[id], CELL, func(world: PackedVector2Array) -> String:
		return BlockEdges.ground_problem(sim, world, CELL * 0.2))


## Edge pieces cut back to the roads as they are now, and any no longer
## joined to a bank's blocks gone (after a road, or a block cleared or sold).
func prune_edges(sim: CitySim) -> bool:
	var changed := false
	var ids := banks.keys()
	ids.sort()
	for id in ids:
		changed = BlockEdges.prune(sim, banks[id], CELL) or changed
	return changed


## The player clears one block (or an edge piece); clearing the first
## building closes the bank (its loans are sold to an out-of-town bank and
## stay with the borrowers).
func remove_at(p: Vector3) -> bool:
	var id := at(p)
	if id == -1:
		return false
	var b: Dictionary = banks[id]
	if BlockEdges.clear_at(b, CELL, p):
		return true
	var d: Vector3 = p - b.pos
	var cell := Vector2i(roundi(d.dot(_right(b)) / CELL), roundi(-d.dot(b.dir) / CELL))
	if cell == Vector2i.ZERO:
		banks.erase(id)
		return true
	for blk in b.blocks:
		if blk.c == cell:
			b.blocks.erase(blk)
			b.built.erase(blk.use)
			b.cleared.append(cell)
			return true
	return false


## The road wins: a road through the first building closes the bank and
## pays the city back its cost; through a block, takes that block.
func make_way(corr: Array) -> int:
	var back := 0
	var ids := banks.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = banks[id]
		if RoadWins.hits(corr, block_corners(b, Vector2i.ZERO)):
			back += int(spec(b.kind).cost)
			banks.erase(id)
			continue
		for blk in b.blocks.duplicate():
			if RoadWins.hits(corr, block_corners(b, blk.c)):
				b.blocks.erase(blk)
				b.built.erase(blk.use)
	return back


## Tellers, loan officers and back office.
func jobs() -> int:
	var n := 0
	for id in banks:
		n += staff(banks[id])
	return n


## Bank premises pay commercial property tax.
func taxable_value() -> float:
	var v := 0.0
	for id in banks:
		v += (1 + banks[id].blocks.size()) * Balance.BANK_PREMISES_VALUE
	return v


## For other hubs' development trees (Agency): dollars a local bank would
## lend this borrower toward a project costing `cost`, or 0. Doesn't book it.
func credit_for(sim: CitySim, who: String, what: String, cost: float, extra_profit := 0.0) -> float:
	var id := lender_for(sim, what, cost * Balance.BANK_LTV[0])
	if id == -1:
		return 0.0
	var b: Dictionary = banks[id]
	var amount := cost * ltv(b)
	if coverage(sim, who, amount, extra_profit, rate(b), what) < dscr_needed(b):
		return 0.0
	return amount


## The town's lending in one line, for the Economy page and the advisor.
func summary() -> Dictionary:
	var out := {"banks": banks.size(), "loans": 0.0, "deposits": 0.0, "healthy": 0}
	for id in banks:
		out.loans += loans_total(banks[id])
		out.deposits += float(banks[id].deposits)
		if health(banks[id]) == "well":
			out.healthy += 1
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id in banks:
		var b: Dictionary = banks[id]
		var blocks := []
		for blk in b.blocks:
			blocks.append([blk.c.x, blk.c.y, blk.use])
		out[str(id)] = {"kind": b.kind, "name": b.name, "pos": [b.pos.x, b.pos.z], "dir": [b.dir.x, b.dir.z],
			"blocks": blocks, "capital": b.capital, "deposits": b.deposits, "loans": b.loans,
			"reputation": b.reputation, "leader": b.leader, "founded": b.founded, "status": b.status,
			"year": b.year, "last_year": b.get("last_year", {}), "made": b.made, "foreclosed": b.foreclosed,
			"failures": b.get("failures", 0), "cleared": b.cleared.map(func(v): return [v.x, v.y])}
		if not b.get("edge", {}).is_empty():
			out[str(id)].edge = CivicHubs.edge_to_save(b.edge)
	return {"banks": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	banks.clear()
	for k in d.get("banks", {}):
		var s: Dictionary = d.banks[k]
		var blocks := []
		for blk in s.get("blocks", []):
			blocks.append({"c": Vector2i(int(blk[0]), int(blk[1])), "use": str(blk[2])})
		var loans := {}
		var raw: Dictionary = s.get("loans", {})
		for who in raw:
			var l: Dictionary = raw[who]
			loans[str(who)] = {"kind": str(l.get("kind", "farm")), "balance": float(l.get("balance", 0.0)),
				"pay": float(l.get("pay", 0.0)), "cells": Array(l.get("cells", []))}
		var l2: Dictionary = s.get("leader", {})
		var y: Dictionary = s.get("year", {})
		banks[int(k)] = {"kind": str(s.kind), "name": str(s.get("name", "First State Bank")),
			"pos": Vector3(s.pos[0], 0.0, s.pos[1]), "dir": BlockEdges.unit(Vector3(s.dir[0], 0.0, s.dir[1])),
			"blocks": blocks, "capital": float(s.get("capital", 0.0)), "deposits": float(s.get("deposits", 0.0)),
			"loans": loans, "reputation": float(s.get("reputation", Balance.BANK_START_REPUTATION)),
			"leader": {"name": str(l2.get("name", "Pat Lee")), "edu": float(l2.get("edu", 0.5)),
				"caution": float(l2.get("caution", 0.5)), "ambition": float(l2.get("ambition", 0.5))},
			"founded": int(s.get("founded", 0)), "status": str(s.get("status", "")),
			"year": {"lent": float(y.get("lent", 0.0)), "profit": float(y.get("profit", 0.0)),
				"foreclosed": int(y.get("foreclosed", 0)), "losses": float(y.get("losses", 0.0))},
			"made": int(s.get("made", 0)), "foreclosed": int(s.get("foreclosed", 0)),
			"failures": int(s.get("failures", 0)), "idle": "",
			"cleared": s.get("cleared", []).map(func(v): return Vector2i(int(v[0]), int(v[1])))}
		var bk: Dictionary = banks[int(k)]
		bk.edge = BlockEdges.from_save(s.get("edge", []), blocks)
		bk.built = bk.blocks.map(func(blk): return blk.use)
		var ly: Dictionary = s.get("last_year", {})
		if not ly.is_empty():
			# As `year`: counts back as whole numbers, so a loaded copy saves
			# byte for byte the same.
			bk.last_year = {"lent": float(ly.get("lent", 0.0)), "profit": float(ly.get("profit", 0.0)),
				"foreclosed": int(ly.get("foreclosed", 0)), "losses": float(ly.get("losses", 0.0))}
	_next_id = int(d.get("next_id", 1))
