class_name BigFactories
extends RefCounted
## Big local factories (Brawn's pitch #16): one-of-a-kind plants that turn
## several goods into one product, after Cities: Skylines 2's unique
## industry buildings, and benchmarked against real ones (see
## docs/big_factories.md):
##   ethanol plant  corn -> fuel ethanol + distillers grains (cattle feed)
##   meatpacker     hogs + feed -> boxed pork for the stores
##   furniture      hardwood logs -> solid-wood furniture for the stores
##   RV plant       steel + wood + parts -> towable RVs for the region
##
## Each is a hub run by its owner (Agency): it buys its inputs from the
## town's farms, companies, factories and warehouses first, then from
## neighbor towns, then from the outside world (Trade), and every load
## rides a real truck (Logistics, ref "big:<id>"). It keeps its own books:
## what it pays and earns is its own money, and the town gets property tax
## and jobs. Its owner builds up its development tree (TREES) with that
## money, builds the plant taller, and when busy buys the land right behind
## it, one bay at a time. Land with the player's buildings on it goes to the
## permit bell first. It never opens a second site.

## Names and what each makes; the numbers are in Balance.BIG_FACTORY.
const KINDS := {
	"ethanol": {"name": "Ethanol plant", "short": "Ethanol", "makes": "fuel ethanol and distillers grains",
		"purpose": "fuel", "to": "edge", "icon": "corn"},
	"meatpacker": {"name": "Meatpacking plant", "short": "Meatpacker", "makes": "boxed pork for the stores",
		"purpose": "food", "to": "shop", "icon": "farms"},
	"furniture": {"name": "Furniture maker", "short": "Furniture", "makes": "solid hardwood furniture",
		"purpose": "goods", "to": "shop", "icon": "forest"},
	"rv": {"name": "RV plant", "short": "RV plant", "makes": "travel trailers and fifth wheels",
		"purpose": "goods", "to": "edge", "icon": "industry"},
}
const ORDER := ["ethanol", "meatpacker", "furniture", "rv"]
## Truck purpose for each input coming in (Vehicles picks the rig).
const IN_PURPOSE := {"corn": "grain", "livestock": "livestock", "feed": "grain", "logs": "raw",
	"steel": "raw", "parts": "goods"}
## Gap between the site's front and the road's right of way.
const SETBACK := 2.0
## Industrial zoning caps (as Warehouses): about 20 acres on one lot.
const MAX_SITE_M2 := 80_000.0
const TICKS_PER_DAY := 24 * CitySim.TICKS_PER_HOUR
## Production steps run with Logistics' shipping rounds.
const STEP := Logistics.EVERY

## Development trees, in Agency's format. Costs come out of the plant's own
## money. Each is a real step such plants take; effects: "output*" more
## batches, "price*" more for what it sells, "input*" less input per batch,
## "process*" cheaper processing, "jobs+", "stock+" months of input kept on
## hand, "contract+" loads of hogs a month raised by contract growers on
## nearby farms, "co2+" loads of CO2 sold a month.
const TREES := {
	"ethanol": [
		{"id": "grain_bins", "name": "Grain bins and a bigger dump pit", "cost": 400_000, "needs": {},
			"effects": {"stock+": 1.0, "jobs+": 2}, "note": "it can buy the harvest when farmers sell"},
		{"id": "fermenter", "name": "Fourth fermenter", "cost": 1_800_000, "requires": ["grain_bins"],
			"needs": {"local:farm": 2}, "effects": {"output*": 0.3, "jobs+": 4}, "note": "corn farms nearby keep it fed"},
		{"id": "corn_oil", "name": "Corn oil extraction", "cost": 900_000, "requires": ["grain_bins"],
			"needs": {"leader_edu": 0.45}, "effects": {"price*": 0.08, "jobs+": 2},
			"note": "distillers corn oil sells to biodiesel makers"},
		{"id": "co2", "name": "CO2 recovery plant", "cost": 1_200_000, "requires": ["fermenter"],
			"needs": {"population": 1_500}, "effects": {"co2+": 4.0, "jobs+": 4},
			"note": "liquid CO2 for soda bottlers, meat plants and dry ice"},
		{"id": "wet_cake", "name": "Wet distillers grains pad", "cost": 300_000, "requires": ["grain_bins"],
			"needs": {"local:farm": 1}, "effects": {"process*": -0.12},
			"note": "sells feed wet to farms nearby and skips the dryer"},
		{"id": "unit_loadout", "name": "Regional tanker terminal", "cost": 2_500_000, "requires": ["fermenter"],
			"needs": {"link": 1, "profit": 150_000}, "effects": {"price*": 0.1, "output*": 0.2, "jobs+": 6},
			"note": "blenders across the region buy straight from the plant"},
	],
	"meatpacker": [
		{"id": "contract", "name": "Contract hog growers", "cost": 500_000, "needs": {"local:farm": 1},
			"effects": {"contract+": 4.0, "jobs+": 4}, "note": "farm families finish hogs in barns for the plant"},
		{"id": "cold_store", "name": "Cold storage", "cost": 800_000, "needs": {},
			"effects": {"stock+": 0.5, "jobs+": 6}},
		{"id": "second_shift", "name": "Second shift", "cost": 1_500_000, "requires": ["cold_store"],
			"needs": {"population": 1_200}, "effects": {"output*": 0.4, "jobs+": 120}},
		{"id": "smokehouse", "name": "Bacon and ham smokehouse", "cost": 1_400_000, "requires": ["cold_store"],
			"needs": {"leader_edu": 0.4}, "effects": {"price*": 0.12, "jobs+": 30}},
		{"id": "more_growers", "name": "More contract growers", "cost": 900_000, "requires": ["contract"],
			"needs": {"local:farm": 3}, "effects": {"contract+": 6.0, "jobs+": 4}},
		{"id": "rendering", "name": "Rendering plant", "cost": 1_100_000, "requires": ["second_shift"],
			"needs": {"profit": 100_000}, "effects": {"process*": -0.15, "jobs+": 15},
			"note": "fat and bone become tallow and meal instead of waste"},
	],
	"furniture": [
		{"id": "dry_kiln", "name": "Dry kilns", "cost": 600_000, "needs": {},
			"effects": {"input*": -0.15, "jobs+": 6}, "note": "dries its own lumber, wasting less wood"},
		{"id": "log_yard", "name": "Log yard and sawmill", "cost": 900_000, "requires": ["dry_kiln"],
			"needs": {"local:forest": 1}, "effects": {"process*": -0.1, "stock+": 1.0, "jobs+": 12},
			"note": "buys logs straight from the woods nearby"},
		{"id": "cnc", "name": "CNC router cell", "cost": 1_200_000, "requires": ["dry_kiln"],
			"needs": {"leader_edu": 0.5, "education": 0.3}, "effects": {"output*": 0.3, "jobs+": 10}},
		{"id": "finishing", "name": "Finishing line", "cost": 800_000, "requires": ["dry_kiln"],
			"needs": {"population": 800}, "effects": {"price*": 0.12, "jobs+": 25}},
		{"id": "office_line", "name": "Office furniture line", "cost": 2_000_000, "requires": ["cnc", "finishing"],
			"needs": {"profit": 120_000, "link": 1}, "effects": {"output*": 0.4, "price*": 0.1, "jobs+": 60},
			"note": "desks and casegoods for offices across the region, Jasper style"},
	],
	"rv": [
		{"id": "chassis", "name": "Frame and chassis shop", "cost": 900_000, "needs": {},
			"effects": {"input*": -0.1, "jobs+": 20}, "note": "welds its own frames"},
		{"id": "second_line", "name": "Second assembly line", "cost": 2_500_000, "requires": ["chassis"],
			"needs": {"population": 1_500}, "effects": {"output*": 0.5, "jobs+": 110}},
		{"id": "fiberglass", "name": "Fiberglass cap shop", "cost": 1_200_000, "requires": ["chassis"],
			"needs": {"leader_edu": 0.45}, "effects": {"price*": 0.1, "jobs+": 30}},
		{"id": "suppliers", "name": "Supplier park", "cost": 1_500_000, "requires": ["chassis"],
			"needs": {"local:metal": 1}, "effects": {"process*": -0.12, "jobs+": 10},
			"note": "a metal works nearby makes its parts"},
		{"id": "motorhome", "name": "Motorhome line", "cost": 4_000_000, "requires": ["second_line", "fiberglass"],
			"needs": {"profit": 250_000, "link": 1, "education": 0.3}, "effects": {"price*": 0.25, "jobs+": 80},
			"note": "the most valuable RVs, sold across the region"},
	],
}

## id -> {kind, pos (middle of the site's front), dir (toward the road),
## level, bays, leader, built, name, cash, stock {input: loads}, promised
## {input: loads on the way}, due {input: loads bought from the region not
## yet sent for}, out {good: finished loads in the yard}, shipped {good:
## loads that left for the region this month}, local {input: loads from town
## this month}, month {made, revenue, cost}, hist [yearly-ish profits by
## month], busy, loss, progress, boxed, why}
var sites := {}
## Last month's region wants per good: good -> {id: loads}.
var asked := {}
var _next_id := 1
## A plant closed this month (its owner sold out).
var _closed := false


static func spec(f: Dictionary) -> Dictionary:
	return Balance.BIG_FACTORY[f.kind]


func add(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	var stock := {}
	for input in Balance.BIG_FACTORY[kind]["in"]:
		stock[input] = 0.0
	sites[id] = {"kind": kind, "pos": pos, "dir": dir, "level": 0, "bays": 0,
		"leader": Agency.leader(sim, hash([sim.city_seed, "big", kind, id])), "built": [],
		"name": company_name(kind, hash([sim.city_seed, kind, id])),
		"cash": float(Balance.BIG_FACTORY[kind].cash), "stock": stock, "promised": stock.duplicate(),
		"due": stock.duplicate(), "out": {}, "shipped": {}, "local": {}, "month": _blank_month(), "hist": [],
		"busy": 0, "loss": 0, "progress": 0.0, "boxed": false, "why": ""}
	# Its own money (Capital): startup cash builds and runs it at first,
	# then it grows only from what it keeps of its profit.
	var f: Dictionary = sites[id]
	Capital.start(f, "company")
	f.cash = float(Balance.BIG_FACTORY[kind].cash)
	f.cap_day = today(sim)
	f.grown = today(sim)
	return id


## The game day (a month).
static func today(sim: CitySim) -> float:
	return float(sim.tick_count) / TICKS_PER_DAY


## A name like the real ones: a place or family name and the trade.
static func company_name(kind: String, seed: int) -> String:
	var places := ["White River", "Pike County", "Patoka", "Prairie", "Four Rivers", "Hoosier", "Wabash",
		"Petersburg", "Southern Indiana", "Tri-County"]
	var families := ["Kremer", "Hoffman", "Schnell", "Lehmkuhler", "Buechler", "Mehringer", "Seger", "Schuler"]
	var r := absi(seed)
	match kind:
		"ethanol": return "%s Ethanol" % places[r % places.size()]
		"meatpacker": return "%s Pork" % places[r % places.size()]
		"furniture": return "%s Furniture Co." % families[r % families.size()]
		_: return "%s Coach" % places[r % places.size()]


static func _blank_month() -> Dictionary:
	return {"made": 0.0, "revenue": 0.0, "cost": 0.0}


# --- Footprint ----------------------------------------------------------------

static func site_width(f: Dictionary) -> float:
	return float(spec(f).w)


static func site_depth(f: Dictionary) -> float:
	return float(spec(f).d) + Balance.BIG_FACTORY_BAY * int(f.bays)


static func center(f: Dictionary) -> Vector3:
	return f.pos - f.dir * site_depth(f) * 0.5


## The truck gate on the street, where its trucks stop.
static func gate(f: Dictionary) -> Vector3:
	return f.pos + Vector3(-f.dir.z, 0.0, f.dir.x) * site_width(f) * 0.3


static func corners(f: Dictionary) -> PackedVector2Array:
	var side := Vector3(-f.dir.z, 0.0, f.dir.x)
	var hw := site_width(f) * 0.5
	var depth := site_depth(f)
	var out := PackedVector2Array()
	for p in [f.pos - side * hw, f.pos + side * hw, f.pos + side * hw - f.dir * depth, f.pos - side * hw - f.dir * depth]:
		out.append(Vector2(p.x, p.z))
	return out


## The strip of land the next bay would take, right behind the site.
static func next_bay(f: Dictionary) -> PackedVector2Array:
	var side := Vector3(-f.dir.z, 0.0, f.dir.x)
	var hw := site_width(f) * 0.5
	var back: Vector3 = f.pos - f.dir * site_depth(f)
	var out := PackedVector2Array()
	for p in [back - side * hw, back + side * hw, back + side * hw - f.dir * Balance.BIG_FACTORY_BAY,
			back - side * hw - f.dir * Balance.BIG_FACTORY_BAY]:
		out.append(Vector2(p.x, p.z))
	return out


static func can_extend(f: Dictionary) -> bool:
	return site_width(f) * (site_depth(f) + Balance.BIG_FACTORY_BAY) <= MAX_SITE_M2


func at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		if Geometry2D.is_point_in_polygon(q, corners(sites[id])):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1


func overlaps(poly: PackedVector2Array) -> bool:
	for id in sites:
		if not Geometry2D.intersect_polygons(poly, corners(sites[id])).is_empty():
			return true
	return false


func has_kind(kind: String) -> bool:
	for id in sites:
		if sites[id].kind == kind:
			return true
	return false


## Why this plant can't go here, or "": one of each per town, beside a
## street, on clear ground.
func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> String:
	if has_kind(kind):
		return "The town already has its %s. There's one of each." % KINDS[kind].name.to_lower()
	var f := {"kind": kind, "pos": pos, "dir": dir, "bays": 0}
	var poly := corners(f)
	var mid := center(f)
	if sim.reserves.kind_at(mid) != "":
		return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(mid)]
	if Services.road_clash(sim.network, poly):
		return "Too close to a road. A %s needs %d × %d m." % [KINDS[kind].name.to_lower(),
			roundi(site_width(f)), roundi(site_depth(f))]
	if overlaps(poly):
		return "Overlaps another big factory."
	return _ground(sim, poly, -1, true)


## What's on a piece of ground: "" when it's clear (empty unzoned roadside
## lots can be bought), else why not. With `lots_ok` false, zoned or built
## lots also block it; with true they're reported as "lots".
func _ground(sim: CitySim, poly: PackedVector2Array, id: int, place := false) -> String:
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for sid in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(sid)).is_empty():
			return "Overlaps a service building."
	for wid in sim.warehouses.buildings:
		if not Warehouses.is_store(sim.warehouses.buildings[wid]) \
				and not Geometry2D.intersect_polygons(poly, sim.warehouses.footprint(wid)).is_empty():
			return "Overlaps a warehouse."
	for other in sites:
		if other != id and not Geometry2D.intersect_polygons(poly, corners(sites[other])).is_empty():
			return "Overlaps another big factory."
	if sim.parks.overlaps(Array(poly)):
		return "That ground is a park."
	for p in CitySim._grid_in(poly):
		if not sim.land_ok(p):
			return "Can't build in the water or on a slope that steep."
		if sim.education.covers(p):
			return "That ground is a campus."
		if sim.mail.covers(p):
			return "That ground is a post office."
		if sim.power.covers(p):
			return "That ground belongs to a power company."
		if sim.banks.covers(p):
			return "That ground is a bank."
		if sim.rail.covers(p):
			return "That ground belongs to the railroad."
		if sim.telecom.covers(p):
			return "That ground belongs to the phone company."
		var owner := Capital.owner_of(sim, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:"):
			return "That ground belongs to a company."
		if sim.hubs.covers(p):
			return "Overlaps a landfill, recycling center or cemetery."
		if not place and sim.reserves.kind_at(p) != "":
			return "That land is reserved."
	if place:
		return ""
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue
		if not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			return "lots"
	return ""


# --- The month -------------------------------------------------------------------

## Batches a month the plant can run now.
func capacity(f: Dictionary) -> float:
	var s := spec(f)
	var size := 1.0 + Balance.BIG_FACTORY_LEVEL_LIFT * int(f.level) + Balance.BIG_FACTORY_BAY_LIFT * int(f.bays)
	return float(s.batches) * size * Agency.effect(f, TREES[f.kind], "output*")


## Loads of one input a batch takes.
func per_batch(f: Dictionary, input: String) -> float:
	return float(spec(f)["in"][input]) * maxf(0.3, Agency.effect(f, TREES[f.kind], "input*"))


## Loads of an input it wants more of: enough for STOCK_MONTHS of full
## running, less what it has and what is on the way.
func short(f: Dictionary, input: String) -> float:
	var months := Balance.BIG_FACTORY_STOCK_MONTHS + Agency.effect(f, TREES[f.kind], "stock+")
	var target := per_batch(f, input) * capacity(f) * months
	return target - float(f.stock[input]) - float(f.promised[input]) - float(f.due[input])


## The input of this plant a load of `good` counts as, or "".
static func input_for(kind: String, good: String) -> String:
	for input in Balance.BIG_FACTORY[kind]["in"]:
		if good in Balance.BIG_FACTORY_ACCEPTS[input]:
			return input
	return ""


## A plant that will buy this load: the nearest that still wants it.
## Promises the room ("big:<id>" is the truck's stop), or returns {}.
func claim(good: String, from: Vector3) -> Dictionary:
	var best := -1
	var best_d := INF
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sites[id]
		var input := input_for(f.kind, good)
		if input == "" or short(f, input) < 1.0:
			continue
		var d: float = gate(f).distance_to(from)
		if d < best_d:
			best_d = d
			best = id
	if best == -1:
		return {}
	var f: Dictionary = sites[best]
	f.promised[input_for(f.kind, good)] += 1.0
	return {"ref": "big:%d" % best, "pos": Logistics._xz(gate(f))}


## A promised load that won't come after all.
func unpromise(id: int, good: String) -> void:
	if not sites.has(id):
		return
	var f: Dictionary = sites[id]
	var input := input_for(f.kind, good)
	if input != "":
		f.promised[input] = maxf(0.0, float(f.promised[input]) - 1.0)


## Every tick: production in step with the shipping rounds, the month's
## books and trade once a day (a game day is a month).
func tick(sim: CitySim) -> void:
	if sites.is_empty():
		return
	if not sim.permits.locators.has("big"):
		# Lets the player guide each owner from its panel, and pre-approve land.
		sim.permits.locators["big"] = func(s: CitySim, id: int) -> Vector2:
			var at: Vector3 = BigFactories.center(s.big.sites[id]) if s.big.sites.has(id) else Vector3.ZERO
			return Vector2(at.x, at.z)
	if sim.tick_count % STEP == 0:
		_produce(float(STEP) / TICKS_PER_DAY)
	if sim.tick_count % TICKS_PER_DAY == 0:
		_month(sim)


## Runs batches while it has the inputs and room in the yard.
func _produce(share: float) -> void:
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sites[id]
		var s := spec(f)
		f.progress = minf(float(f.progress) + capacity(f) * share, 2.0)
		while float(f.progress) >= 1.0:
			if float(f.out.get(s.out, 0.0)) >= Balance.BIG_FACTORY_YARD:
				break
			var ok := true
			for input in s["in"]:
				ok = ok and float(f.stock[input]) >= per_batch(f, input) - 0.001
			if not ok:
				break
			for input in s["in"]:
				f.stock[input] = maxf(0.0, float(f.stock[input]) - per_batch(f, input))
			f.out[s.out] = float(f.out.get(s.out, 0.0)) + 1.0
			for good in s.by:
				f.out[good] = float(f.out.get(good, 0.0)) + float(s.by[good])
			f.progress -= 1.0
			f.month.made += 1.0
			_spend(f, float(s.process) * maxf(0.3, Agency.effect(f, TREES[f.kind], "process*")))


func _spend(f: Dictionary, dollars: float) -> void:
	f.cash -= dollars
	f.month.cost += dollars


func _earn(f: Dictionary, dollars: float) -> void:
	f.cash += dollars
	f.month.revenue += dollars


## What a load of its product (or byproduct) fetches.
func price_of(f: Dictionary, good: String) -> float:
	return Trade.base_price(good) * Agency.effect(f, TREES[f.kind], "price*")


## Once a month: settle last month's trade, close the books, then the owner
## decides: develop, build up or out, or cut back. Then it tells the region
## what it needs and what it has to sell for this month.
func _month(sim: CitySim) -> void:
	_settle_trade(sim)
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sites[id]
		var s := spec(f)
		_spend(f, float(s.fixed))
		# Contract growers raise hogs on farms nearby for a fee, and truck them in.
		var contract := Agency.effect(f, TREES[f.kind], "contract+")
		if contract > 0.0:
			f.due["livestock"] += contract
			f["contract_due"] = float(f.get("contract_due", 0.0)) + contract
		var util := float(f.month.made) / maxf(capacity(f), 0.001)
		var profit := float(f.month.revenue) - float(f.month.cost)
		f.hist.append(roundi(profit))
		if f.hist.size() > 12:
			f.hist.pop_front()
		f.last = {"made": f.month.made, "revenue": roundi(f.month.revenue), "cost": roundi(f.month.cost),
			"util": snappedf(util, 0.01)}
		f.month = _blank_month()
		# The month's books already went through its cash: Capital keeps the
		# owner's share of a profit (the rest is paid out), takes losses in
		# full, and pays the loan on land it bought.
		f.cash = float(f.cash) - profit
		Capital.step(f, "company", profit * 12.0, today(sim))
		_decide(sim, id, util, profit)
		if not sites.has(id):
			continue
	_ask_region(sim)


## The owner's moves for the month (the player's word comes first).
## Growth comes from its own money, over years: it builds up with savings,
## and buys the land behind it with a down payment and a loan its profit
## can carry, at what land sells for there. Where the town has driven land
## prices up past what the plant earns on it, an owner losing money may ask
## to sell out instead (Brawn, 2026-10-23).
func _decide(sim: CitySim, id: int, util: float, profit: float) -> void:
	var f: Dictionary = sites[id]
	var stance: String = sim.permits.guidance("big", id).stance
	f.busy = int(f.busy) + 1 if util >= Balance.BIG_FACTORY_BUSY * (0.7 if stance == "grow" else 1.0) else 0
	f.loss = int(f.loss) + 1 if profit < 0.0 else 0
	if _selling(sim, id):
		return
	var income := Capital.steady(f, yearly_profit(f))
	# Land the player said yes to: buy it, clear it and build on it.
	for req in sim.permits.approved("big", id):
		if str(req.get("ask", "")) != "":
			continue
		if Capital.can_buy(f, float(req.cost), income):
			# The land as the player left it, and the bay itself.
			var area := PackedVector2Array()
			for q in req.route:
				area.append(Vector2(float(q[0]), float(q[1])))
			if area.size() >= 3:
				_clear_for(sim, area)
			_clear_for(sim, next_bay(f))
			Capital.buy(f, float(req.cost), income)
			f.bays = int(f.bays) + 1
			f.grown = today(sim)
			sim.permits.done(req.id)
			f.why = "Bought the land behind it, with your permit."
			f.changed = true
	if stance == "hold":
		return
	if float(f.cash) > 0.0:
		# Agency spends the plant's own savings (it has Capital).
		var node := Agency.develop(sim, f, TREES[f.kind], center(f), yearly_profit(f))
		if not node.is_empty():
			f.why = str(f.get("why", ""))
			f.changed = true
	var grow_cost := float(spec(f).value) * Balance.BIG_FACTORY_GROW_COST
	var years := (today(sim) - float(f.get("grown", 0.0))) / 12.0
	var wait := Balance.BIG_FACTORY_GROW_YEARS * (0.5 if stance == "grow" else 1.0)
	if int(f.busy) >= Balance.BIG_FACTORY_BUSY_MONTHS and income > 0.0 and years >= wait:
		var lead: Dictionary = f.leader
		var cushion := Balance.CAPITAL_RESERVE * (0.5 + float(lead.get("caution", 0.5)))
		if int(f.level) < Balance.BIG_FACTORY_LEVELS - 1:
			# Building up needs no land: savings pay for the new line.
			if float(f.cash) - cushion >= grow_cost:
				f.cash = float(f.cash) - grow_cost
				f.level = int(f.level) + 1
				f.busy = 0
				f.boxed = false
				f.grown = today(sim)
				f.why = "Busy for months, so it saved up and built %s." % ["a second line", "a third line"][int(f.level) - 1]
				f.changed = true
			else:
				f.why = "Busy, and saving up for another line."
		elif not can_extend(f):
			f.boxed = true
			f.why = "It's as big as industrial zoning allows."
		else:
			var poly := next_bay(f)
			var price := bay_price(sim, f) + grow_cost
			var ground := _ground(sim, poly, id)
			if ground != "" and ground != "lots":
				f.boxed = true
				f.why = "No free land behind it to grow into."
			elif not Capital.can_buy(f, price, income):
				f.why = "Busy, but the land behind it costs about $%s an acre, more than its profit can pay for yet." \
					% CitySim.money_text(roundi(Capital.land_price(sim, _mid(poly))))
			elif ground == "":
				Capital.buy(f, price, income)
				f.bays = int(f.bays) + 1
				f.busy = 0
				f.boxed = false
				f.grown = today(sim)
				f.why = "Busy for months, so it bought the land right behind it (part on a loan)."
				f.changed = true
			else:
				_ask_permit(sim, id, poly, price)
	elif int(f.loss) >= Balance.BIG_FACTORY_LOSS_STREAK:
		f.loss = 0
		if int(f.bays) > 0:
			f.bays = int(f.bays) - 1
			# The land goes back on the market and pays down the loan.
			var back := bay_price(sim, f)
			var owed := minf(float(f.get("debt", 0.0)), back)
			f.debt = float(f.get("debt", 0.0)) - owed
			f.cash = float(f.cash) + back - owed
			f.why = "Losing money, so it sold the back bay."
			f.changed = true
		elif int(f.level) > 0:
			f.level = int(f.level) - 1
			f.why = "Losing money, so it shut a line."
			f.changed = true


## What the next bay of land behind the site sells for.
func bay_price(sim: CitySim, f: Dictionary) -> float:
	var poly := next_bay(f)
	var m2 := absf(_area(poly))
	return m2 / M2_PER_ACRE * Capital.land_price(sim, _mid(poly))


## What the site's own ground would fetch.
func site_land_value(sim: CitySim, f: Dictionary) -> float:
	var poly := corners(f)
	return absf(_area(poly)) / M2_PER_ACRE * Capital.land_price(sim, center(f))


const M2_PER_ACRE := 4046.86


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _mid(poly: PackedVector2Array) -> Vector3:
	var m := Vector2.ZERO
	for q in poly:
		m += q
	m /= maxf(1.0, float(poly.size()))
	return Vector3(m.x, 0.0, m.y)


## Selling out: a plant that keeps losing money on ground the town has made
## worth far more to developers asks on the bell to sell. Yes: it closes and
## its land is open for the town. No: it carries on and won't ask again for
## a few years. True when it is waiting on the answer or just closed.
func _selling(sim: CitySim, id: int) -> bool:
	var f: Dictionary = sites[id]
	var sale: Dictionary = f.get("sale", {})
	if not sale.is_empty():
		var state := sim.permits.state_of(int(sale.req))
		if state == Permits.State.OPEN:
			return true
		f.sale = {}
		if state == Permits.State.APPROVED:
			sim.permits.done(int(sale.req))
			sites.erase(id)
			_closed = true
			return true
		f.sale_day = today(sim) + Balance.CAPITAL_SELL_WAIT_YEARS * 12.0
		f.why = "Its owner turned down the developers and kept the plant running."
		return false
	if today(sim) < float(f.get("sale_day", 0.0)) or yearly_profit(f) >= 0.0 or int(f.loss) < 2:
		return false
	var at := center(f)
	if not Capital.sell_out(sim, at):
		return false
	var per_acre := Capital.land_price(sim, at)
	var area := []
	for q in corners(f):
		area.append([q.x, q.y])
	var req: int = sim.permits.file(sim, {"hub": "big", "hub_id": id, "leader": leader_name(f), "ask": "sell_plant",
		"title": "%s wants to sell the plant" % f.name,
		"why": "It has been losing money, and developers offer about $%s an acre for its ground, %.1f times what it's worth as industrial land." % [
			CitySim.money_text(roundi(per_acre)), per_acre / Balance.CAPITAL_LAND_PER_ACRE],
		"area": area, "change": "Plant sold",
		"yes": "The owner sells. The plant closes, its jobs go, and its land is open for the town.",
		"no": "The plant keeps running and won't ask again for %d years." % Balance.CAPITAL_SELL_WAIT_YEARS})
	f.sale_day = today(sim) + 12.0
	if req != -1:
		f.sale = {"req": req}
		f.why = "Its owner asked you about selling the plant (see the bell)."
		return true
	return false


## The player's homes or shops stand on the land it wants: ask first,
## with the outline of the land (the player can drag its corners).
func _ask_permit(sim: CitySim, id: int, poly: PackedVector2Array, grow_cost: float) -> void:
	var f: Dictionary = sites[id]
	var lots := 0
	for key in sim.buildings:
		if sim.lots.has(key) and not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			lots += 1
	var area := []
	for q in poly:
		area.append([q.x, q.y])
	var rid: int = sim.permits.file(sim, {"hub": "big", "hub_id": id, "leader": leader_name(f),
		"title": "%s wants the land behind it" % f.name,
		"why": "The plant is running flat out and wants to grow onto the %d lot%s behind it, buying them out at a fair price." \
			% [lots, "" if lots == 1 else "s"],
		"area": area, "change": "Homes and shops to factory", "per_m2": Balance.BIG_FACTORY_LAND_PER_M2,
		"base": roundi(grow_cost), "budget": roundi(float(f.cash))})
	f.why = "Asked you for the lots behind it (the bell up top)." if rid != -1 else "Waiting to ask for the land behind it."


## Buildings and zoning on approved land go (bought out at a fair price).
func _clear_for(sim: CitySim, poly: PackedVector2Array) -> void:
	for key in sim.buildings.keys():
		if sim.lots.has(key) and not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			sim.buildings.erase(key)
	sim._clear_zones_under(poly)


static func leader_name(f: Dictionary) -> String:
	var firsts := ["Dale", "Karen", "Jim", "Linda", "Mark", "Deb", "Tom", "Brenda", "Rick", "Lisa", "Greg", "Julie"]
	var lasts := ["Kremer", "Hoffman", "Schnell", "Mehringer", "Seger", "Buechler", "Wagner", "Meyer"]
	var r := absi(hash([f.kind, f.pos.x, f.pos.z]))
	return "%s %s" % [firsts[r % firsts.size()], lasts[(r / 7) % lasts.size()]]


func yearly_profit(f: Dictionary) -> float:
	var total := 0.0
	for p in f.hist:
		total += float(p)
	return total * 12.0 / maxf(1.0, float(f.hist.size()))


# --- Trade with the region ---------------------------------------------------

## Last month's deals for its goods. What it bought comes in by truck from
## the region link; the plant pays, not the town, so the town's books get
## the money back. Products sold to the region were paid for when their
## trucks reached the highway (at the market price), so their deals only
## record who bought them.
func _settle_trade(sim: CitySim) -> void:
	for d in sim.trade.last_deals:
		var good: String = d.good
		var money := roundi(float(d.amount) * float(d.price))
		if asked.has(good) and _is_buyer(sim, d):
			var total := 0.0
			for id in asked[good]:
				total += float(asked[good][id])
			for id in asked[good]:
				if not sites.has(id) or total <= 0.0:
					continue
				var share := float(asked[good][id]) / total
				var f: Dictionary = sites[id]
				var input := input_for(f.kind, good)
				if input != "":
					f.due[input] += float(d.amount) * share
				_spend(f, money * share)
			sim.economy.money += money
			sim.trade.net += money
		elif _sells(good) and not _is_buyer(sim, d):
			sim.economy.money -= money
			sim.trade.net -= money
	asked.clear()


## True when this town was the buyer in a deal (the other side is the
## outside world or a neighbor).
func _is_buyer(sim: CitySim, d: Dictionary) -> bool:
	if str(d.seller) == "outside":
		return true
	if str(d.buyer) == "outside":
		return false
	return sim.trade.bought.has(d.good) and not sim.trade.sold_last.has(d.good)


func _sells(good: String) -> bool:
	for id in sites:
		var s := spec(sites[id])
		if s.out == good or s.by.has(good):
			return true
	return good == "co2" and not sites.is_empty()


## This month's asks: inputs the town can't cover, and products for sale.
func _ask_region(sim: CitySim) -> void:
	var wants := {}
	var offers := {}
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sites[id]
		var s := spec(f)
		for input in s["in"]:
			# What the town brought last month is expected again.
			var gap := floorf(short(f, input) - float(f.local.get(input, 0.0)))
			if gap >= 1.0:
				var good: String = Balance.BIG_FACTORY_TRADE_AS[input]
				wants[good] = float(wants.get(good, 0.0)) + gap
				if not asked.has(good):
					asked[good] = {}
				asked[good][id] = gap
		for good in f.shipped:
			offers[good] = float(offers.get(good, 0.0)) + float(f.shipped[good])
		var co2 := Agency.effect(f, TREES[f.kind], "co2+")
		if co2 > 0.0:
			offers["co2"] = float(offers.get("co2", 0.0)) + co2
			_earn(f, co2 * Trade.base_price("co2"))
		f.shipped = {}
		f.local = {}
	for good in Balance.BIG_FACTORY_TRADE_AS.values() + ["ethanol", "distillers grains", "pork", "furniture", "rv", "co2"]:
		if wants.has(good) or (sim.trade.wants.has(good) and _ours_want(good)):
			sim.trade.want(good, float(wants.get(good, 0.0)))
		if offers.has(good) or (sim.trade.offers.has(good) and _sells(good)):
			sim.trade.offer(good, float(offers.get(good, 0.0)))


func _ours_want(good: String) -> bool:
	return good in Balance.BIG_FACTORY_TRADE_AS.values()


# --- Trucks ------------------------------------------------------------------------

## Called by Logistics each shipping round: finished loads leave, and
## inputs come from warehouses, contract farms and the region link.
## Returns the round's truck count.
func ship(sim: CitySim, lg: Logistics, sent: int) -> int:
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		if sent >= Logistics.MAX_PER_ROUND:
			break
		var f: Dictionary = sites[id]
		var ref := "big:%d" % id
		var here := {"ref": ref, "pos": Logistics._xz(gate(f))}
		# Finished loads, the main product first.
		var goods: Array = f.out.keys()
		goods.sort()
		goods.erase(spec(f).out)
		goods.push_front(spec(f).out)
		for good in goods:
			if float(f.out.get(good, 0.0)) < 1.0 or lg._left.has(ref):
				continue
			var to := _destination(sim, lg, f, good)
			var purpose: String = KINDS[f.kind].purpose if good == spec(f).out else "grain"
			if not to.is_empty() and lg._send(sim, here, to, purpose, {"good": good, "amount": 1}, "big_out"):
				f.out[good] -= 1.0
				sent += 1
			break
		# Inputs: from a warehouse that holds one, else what the region sold it.
		for input in spec(f)["in"]:
			if sent >= Logistics.MAX_PER_ROUND:
				break
			if short(f, input) >= 1.0 and _from_warehouse(sim, lg, id, input):
				sent += 1
			elif float(f.due[input]) >= 1.0:
				var from := _contract_farm(sim, f) if input == "livestock" and float(f.get("contract_due", 0.0)) >= 1.0 else {}
				var kind := "contract" if not from.is_empty() else "import"
				if from.is_empty():
					from = lg._edge(sim, gate(f))
				var good: String = Balance.BIG_FACTORY_TRADE_AS[input]
				if not from.is_empty() and lg._send(sim, from, here, IN_PURPOSE[input], {"good": good, "amount": 1}, kind):
					f.due[input] -= 1.0
					f.promised[input] += 1.0
					if kind == "contract":
						f.contract_due -= 1.0
					sent += 1
	return sent


## Where a finished load goes: pork and furniture to the nearest store,
## distillers grains to a plant that feeds animals or a warehouse, the rest
## out to the region.
func _destination(sim: CitySim, lg: Logistics, f: Dictionary, good: String) -> Dictionary:
	if good != spec(f).out:
		var c := claim(good, gate(f))
		if not c.is_empty():
			return c
		var wid := sim.warehouses.take_room(gate(f), good)
		if wid != -1:
			return {"ref": "wh:%d" % wid, "pos": Logistics._xz(sim.warehouses.buildings[wid].pos)}
		return lg._edge(sim, gate(f))
	if KINDS[f.kind].to == "shop":
		return lg._buyer(sim, gate(f), "shop")
	return lg._edge(sim, gate(f))


## The farm nearest the plant, where its contract hogs come from.
func _contract_farm(sim: CitySim, f: Dictionary) -> Dictionary:
	var best := -1
	var best_d := Balance.FACTORY_CHAIN_REACH
	var ids := sim.farms.farms.keys()
	ids.sort()
	for fid in ids:
		var farm: Dictionary = sim.farms.farms[fid]
		var d: float = farm.pos.distance_to(gate(f))
		if d < best_d and not farm.drive.is_empty() and not sim.logistics._left.has("farm:%d" % fid):
			best_d = d
			best = fid
	if best == -1:
		return {}
	var farm: Dictionary = sim.farms.farms[best]
	return {"ref": "farm:%d" % best, "pos": Logistics._xz(farm.drive[-1]), "drive": Logistics._lane(farm.drive)}


## One load of an input from the nearest warehouse holding it.
func _from_warehouse(sim: CitySim, lg: Logistics, id: int, input: String) -> bool:
	var f: Dictionary = sites[id]
	var best := -1
	var best_good := ""
	var best_d := INF
	var wids := sim.warehouses.buildings.keys()
	wids.sort()
	for wid in wids:
		if lg._left.has("wh:%d" % wid):
			continue
		var w: Dictionary = sim.warehouses.buildings[wid]
		for cat in [Warehouses.RAW, Warehouses.GOODS]:
			for good in Balance.BIG_FACTORY_ACCEPTS[input]:
				if int(w.stock[cat].get(good, 0)) > 0 and w.pos.distance_to(gate(f)) < best_d:
					best_d = w.pos.distance_to(gate(f))
					best = wid
					best_good = good
	if best == -1:
		return false
	var w: Dictionary = sim.warehouses.buildings[best]
	var cat := Warehouses.RAW if int(w.stock[Warehouses.RAW].get(best_good, 0)) > 0 else Warehouses.GOODS
	w.stock[cat][best_good] = int(w.stock[cat][best_good]) - 1
	if int(w.stock[cat][best_good]) <= 0:
		w.stock[cat].erase(best_good)
	w.handled += 1
	var cargo := {"good": best_good, "amount": w.units.get(best_good, 1)}
	if lg._send(sim, {"ref": "wh:%d" % best, "pos": Logistics._xz(w.pos)}, {"ref": "big:%d" % id, "pos": Logistics._xz(gate(f))},
			IN_PURPOSE[input], cargo, "big_in"):
		f.promised[input] += 1.0
		return true
	sim.warehouses.put_back(best, cargo, cat)
	return false


## A truck to or from a plant arrived (Logistics passes them all here).
func arrive(sim: CitySim, t: Dictionary) -> void:
	var to: String = t.to.ref
	var from: String = t.from.ref
	var good := str(t.cargo.get("good", ""))
	if to.begins_with("big:"):
		var id := int(to.substr(4))
		if sites.has(id):
			var f: Dictionary = sites[id]
			var input := input_for(f.kind, good)
			if input != "":
				f.promised[input] = maxf(0.0, float(f.promised[input]) - 1.0)
				f.stock[input] += 1.0
				# Loads from town are paid for at the market price; contract
				# hogs at the growers' fee. Region loads were paid at settling.
				if t.kind in ["site", "farm", "factory", "wh", "big_in", "big_out"]:
					f.local[input] = float(f.local.get(input, 0.0)) + 1.0
					_spend(f, Trade.base_price(good))
				elif t.kind == "contract":
					f.local[input] = float(f.local.get(input, 0.0)) + 1.0
					_spend(f, Trade.base_price(good) * Balance.BIG_FACTORY_CONTRACT_SHARE)
		if from.begins_with("big:") and sites.has(int(from.substr(4))):
			_earn(sites[int(from.substr(4))], price_of(sites[int(from.substr(4))], good))
	elif from.begins_with("big:"):
		var id := int(from.substr(4))
		if to.begins_with("wh:"):
			sim.warehouses.receive(int(to.substr(3)), t.cargo, Warehouses.RAW)
		if sites.has(id):
			var f: Dictionary = sites[id]
			_earn(f, price_of(f, good))
			if to == "edge":
				f.shipped[good] = float(f.shipped.get(good, 0.0)) + 1.0


## A truck found no way through: the load goes back where it came from.
func returned(sim: CitySim, t: Dictionary) -> void:
	var to: String = t.to.ref
	var from: String = t.from.ref
	var good := str(t.cargo.get("good", ""))
	if from.begins_with("big:") and sites.has(int(from.substr(4))):
		var f: Dictionary = sites[int(from.substr(4))]
		f.out[good] = float(f.out.get(good, 0.0)) + 1.0
		if to.begins_with("big:"):
			unpromise(int(to.substr(4)), good)
		return
	if to.begins_with("big:") and sites.has(int(to.substr(4))):
		var f: Dictionary = sites[int(to.substr(4))]
		var input := input_for(f.kind, good)
		if input == "":
			return
		f.promised[input] = maxf(0.0, float(f.promised[input]) - 1.0)
		if from.begins_with("wh:"):
			sim.warehouses.put_back(int(from.substr(3)), t.cargo,
				Warehouses.GOODS if good == "goods" else Warehouses.RAW)
		if t.kind in ["import", "contract"]:
			f.due[input] += 1.0  # bought already: it tries again
			if t.kind == "contract":
				f.contract_due = float(f.get("contract_due", 0.0)) + 1.0


# --- City hooks ------------------------------------------------------------------

## Plants a new road runs through are bulldozed and paid back.
func road_wins(sim: CitySim, corr: Array) -> bool:
	var hit := false
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, corners(sites[id])):
			sim.economy.money += int(spec(sites[id]).cost)
			sites.erase(id)
			hit = true
	return hit


func jobs() -> int:
	var total := 0
	for id in sites:
		total += jobs_at(sites[id])
	return total


func jobs_at(f: Dictionary) -> int:
	var size := 1.0 + 0.35 * int(f.level) + 0.15 * int(f.bays)
	return roundi(float(spec(f).jobs) * size + Agency.effect(f, TREES[f.kind], "jobs+"))


func taxable_value() -> float:
	var total := 0.0
	for id in sites:
		total += value(sites[id])
	return total


static func value(f: Dictionary) -> float:
	return float(spec(f).value) * (1.0 + 0.3 * int(f.level) + 0.1 * int(f.bays) + 0.05 * f.built.size())


## True once, after a plant changed shape or built something (for drawing).
func take_changed() -> bool:
	var any := _closed
	_closed = false
	for id in sites:
		if sites[id].get("changed", false):
			sites[id].erase("changed")
			any = true
	return any


func to_dict() -> Dictionary:
	var out := {}
	for id in sites:
		var f: Dictionary = sites[id].duplicate(true)
		f.erase("changed")
		f.pos = [f.pos.x, f.pos.z]
		f.dir = [f.dir.x, f.dir.z]
		out[str(id)] = f
	var a := {}
	for good in asked:
		a[good] = {}
		for id in asked[good]:
			a[good][str(id)] = asked[good][id]
	return {"sites": out, "next_id": _next_id, "asked": a}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	for k in d.get("sites", {}):
		var s: Dictionary = d.sites[k].duplicate(true)
		if not Balance.BIG_FACTORY.has(str(s.get("kind", ""))):
			continue
		var f := s
		f.kind = str(s.kind)
		f.pos = Vector3(float(s.pos[0]), 0.0, float(s.pos[1]))
		f.dir = Vector3(float(s.dir[0]), 0.0, float(s.dir[1])).normalized()
		f.level = int(s.get("level", 0))
		f.bays = int(s.get("bays", 0))
		f.busy = int(s.get("busy", 0))
		f.loss = int(s.get("loss", 0))
		f.built = Array(s.get("built", [])).map(func(x): return str(x))
		f.hist = Array(s.get("hist", [])).map(func(x): return int(x))
		for key in ["stock", "promised", "due"]:
			var m := {}
			for input in Balance.BIG_FACTORY[f.kind]["in"]:
				m[input] = float(s.get(key, {}).get(input, 0.0))
			f[key] = m
		for key in ["out", "shipped", "local"]:
			var m := {}
			for g in s.get(key, {}):
				m[str(g)] = float(s[key][g])
			f[key] = m
		f.month = {"made": float(s.get("month", {}).get("made", 0.0)), "revenue": float(s.get("month", {}).get("revenue", 0.0)),
			"cost": float(s.get("month", {}).get("cost", 0.0))}
		sites[int(k)] = f
	asked.clear()
	for good in d.get("asked", {}):
		asked[str(good)] = {}
		for id in d.asked[good]:
			asked[str(good)][int(id)] = float(d.asked[good][id])
	_next_id = int(d.get("next_id", 1))
