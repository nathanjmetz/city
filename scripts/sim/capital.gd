class_name Capital
extends RefCounted
## A hub's own money (Brawn, 2026-10-23): every hub with a leader starts
## with startup cash that buys its first footprint, and after that grows
## only from the profit it keeps, weighed against what land costs where it
## wants to grow. Growth takes game years, not minutes. Where the town drives
## land values up, a hub can be priced out of growing, and an owner whose
## land is worth far more to developers than to them may ask to sell out.
##
## Real reference:
##   - Indiana farmland: about $12,000 an acre for average ground in 2025
##     (Purdue Farmland Values and Cash Rents Survey); ground near a growing
##     town sells for more, its price carrying the chance to develop it
##     (urban influence: farmdoc, Choices magazine, USDA ERS).
##   - Farm Credit land loans: 20 to 35% down, 20 to 30 years, about 6.75%.
##   - What a business keeps: a family farm pays its family's living from
##     the farm before anything is saved; a company pays out dividends.
##
## Shared by every hub. A hub plugs in with plain dictionary keys, saved by
## Capital.save / Capital.load:
##   cash     dollars in hand (startup cash, then kept profit)
##   debt     what it still owes on land it bought
##   cap_day  the game day it last stepped
##   avg_profit  its profit over the last few years, for lenders
## and calls, on its own decide cadence:
##   Capital.start(hub, kind)                 when the hub is founded
##   Capital.step(hub, kind, profit, day)     keeps profit, pays its debt
##   Capital.land_price(sim, pos)             $ an acre, development included
##   Capital.can_buy / Capital.buy            down payment from cash, rest owed
##   Capital.sell_out(sim, pos)               land is worth more developed
## Numbers live in Balance (CAPITAL_*). Deterministic: no clocks, no
## randomness; the built-lot grid behind land_price is worked out once a
## tick and kept.

static var _memo := {}


## Startup cash for a new hub of `kind` ("farm", "company", ...).
static func start(hub: Dictionary, kind: String) -> void:
	hub.cash = float(Balance.CAPITAL_START.get(kind, 0.0))
	hub.debt = 0.0
	hub.cap_day = -1.0


## One step on the hub's own cadence: what it keeps of a year's `profit`
## (pro rata since the last step) goes into cash, and the year's payment on
## its debt comes out. Losses come out of cash in full.
static func step(hub: Dictionary, kind: String, profit: float, day: float) -> void:
	if not hub.has("cash"):
		start(hub, kind)
	var last := float(hub.get("cap_day", -1.0))
	hub.cap_day = day
	if last < 0.0 or day <= last:
		return
	# A game day settles a month.
	var years := (day - last) / 12.0
	hub.cash = float(hub.cash) + kept(hub, kind, profit) * years
	# Lenders look at a few years' profit, not one good year's.
	var avg := float(hub.get("avg_profit", profit))
	hub.avg_profit = avg + (profit - avg) * minf(1.0, years / float(Balance.CAPITAL_AVG_YEARS))
	var debt := float(hub.get("debt", 0.0))
	if debt > 0.0:
		var pay := minf(debt * payment_rate() * years, debt * (1.0 + Balance.CAPITAL_RATE * years))
		hub.cash = float(hub.cash) - pay
		hub.debt = maxf(0.0, debt * (1.0 + Balance.CAPITAL_RATE * years) - pay)


## A year's payment on a dollar owed: a level payment over the loan's term.
static func payment_rate() -> float:
	var r := float(Balance.CAPITAL_RATE)
	return r / (1.0 - pow(1.0 + r, -float(Balance.CAPITAL_TERM_YEARS)))


## What the hub pays on its debt a year.
static func service(hub: Dictionary) -> float:
	return float(hub.get("debt", 0.0)) * payment_rate()


## What an acre sells for at pos: farm value plus what nearby development
## adds, up to CAPITAL_URBAN_MAX times more for ground at a growing town's
## edge. Buildings within a mile count, the nearer the more.
static func land_price(sim: CitySim, pos: Vector3) -> float:
	return Balance.CAPITAL_LAND_PER_ACRE * (1.0 + premium(sim, pos))


## The development premium at pos, as a share of farm value (0 out in the
## country, up to CAPITAL_URBAN_MAX).
static func premium(sim: CitySim, pos: Vector3) -> float:
	var grid := _grid(sim)
	var r := float(Balance.CAPITAL_URBAN_REACH)
	var g := float(Balance.CAPITAL_GRID)
	var b := Vector2i(floori(pos.x / g), floori(pos.z / g))
	var span := ceili(r / g)
	var weight := 0.0
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var k := b + Vector2i(dx, dz)
			if not grid.has(k):
				continue
			var mid := Vector3((k.x + 0.5) * g, 0.0, (k.y + 0.5) * g)
			var d := mid.distance_to(Vector3(pos.x, 0.0, pos.z))
			if d < r:
				weight += float(grid[k]) * (1.0 - d / r)
	return float(Balance.CAPITAL_URBAN_MAX) * (1.0 - exp(-weight / float(Balance.CAPITAL_URBAN_SCALE)))


## Built lots counted on a coarse grid, once a tick.
static func _grid(sim: CitySim) -> Dictionary:
	var at := [sim.get_instance_id(), sim.tick_count, sim.buildings.size()]
	if _memo.get("_at", []) == at:
		return _memo.grid
	var g := float(Balance.CAPITAL_GRID)
	var grid := {}
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var k := Vector2i(floori(p.x / g), floori(p.z / g))
		grid[k] = int(grid.get(k, 0)) + 1
	_memo = {"_at": at, "grid": grid}
	return grid


## The least a purchase needs down (a lender's minimum).
static func down(price: float) -> float:
	return price * float(Balance.CAPITAL_DOWN)


## The most a lender would let the hub owe in all, given a year's `income`
## (profit before the owner's draw, with what the new land would add): the
## payments must stay within income over CAPITAL_COVERAGE.
static func loan_room(hub: Dictionary, income: float) -> float:
	if income <= 0.0:
		return 0.0
	return maxf(0.0, income / float(Balance.CAPITAL_COVERAGE) / payment_rate() - float(hub.get("debt", 0.0)))


## Cash a purchase at `price` takes: the lender's minimum down, or more
## when the loan would be more than the hub's income can carry.
static func cash_needed(hub: Dictionary, price: float, income: float) -> float:
	return maxf(down(price), price - loan_room(hub, income))


## Can the hub buy land at `price` with what it has saved?
static func can_buy(hub: Dictionary, price: float, income: float) -> bool:
	return float(hub.get("cash", 0.0)) >= cash_needed(hub, price, income)


## Buys land at `price`: what it must put down from cash, the rest owed.
static func buy(hub: Dictionary, price: float, income: float) -> void:
	var put := cash_needed(hub, price, income)
	hub.cash = float(hub.get("cash", 0.0)) - put
	hub.debt = float(hub.get("debt", 0.0)) + price - put


## The profit a lender would count on: the hub's average over the last
## few years (CAPITAL_AVG_YEARS), or this year's if it's new.
static func steady(hub: Dictionary, profit: float) -> float:
	return minf(profit, float(hub.get("avg_profit", profit)))


## What the hub keeps of a year's `profit` before its debt (see step).
static func kept(hub: Dictionary, kind: String, profit: float) -> float:
	if profit <= 0.0:
		return profit
	var lead: Dictionary = hub.get("leader", {})
	# An ambitious owner ploughs more back in; others take more out.
	return profit * clampf(float(Balance.CAPITAL_RETAIN.get(kind, 0.5))
		* (0.75 + 0.5 * float(lead.get("ambition", 0.5))), 0.0, 1.0)


## True when every point is open land or already `who`'s own ("farm:3",
## "site:5"): the one gate a hub passes before it builds on or plants
## ground (Brawn, 2026-10-23: land has one owner, and a hub buys a parcel
## before it builds there). Owners come from CitySim.land_owner.
static func land_free(sim, pts: Array, who: String) -> bool:
	for p in pts:
		var owner: String = sim.land_owner(p)
		if owner != "" and owner != who:
			return false
	return true


## True when land at pos is worth so much more developed that an owner
## would think of selling out (land price at least CAPITAL_SELL_RATIO times
## farm value: Purdue's "transition land").
static func sell_out(sim: CitySim, pos: Vector3) -> bool:
	return land_price(sim, pos) >= Balance.CAPITAL_LAND_PER_ACRE * float(Balance.CAPITAL_SELL_RATIO)


static func save(hub: Dictionary) -> Dictionary:
	var out := {"cash": float(hub.get("cash", 0.0)), "debt": float(hub.get("debt", 0.0)),
		"cap_day": float(hub.get("cap_day", -1.0))}
	# Only once it has one: a copy loaded before its first step must not
	# start from an average of 0 (lenders would count on nothing).
	if hub.has("avg_profit"):
		out.avg = float(hub.avg_profit)
	return out


static func load(hub: Dictionary, d: Dictionary) -> void:
	hub.cash = float(d.get("cash", 0.0))
	hub.debt = float(d.get("debt", 0.0))
	hub.cap_day = float(d.get("cap_day", -1.0))
	if d.has("avg"):
		hub.avg_profit = float(d.avg)
