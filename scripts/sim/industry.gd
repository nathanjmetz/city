class_name Industry
extends RefCounted
## Resource industry the way Brawn asked, after Cities: Skylines 2's
## specialized industry: open the Oil, Ore or Forest view, place a company's
## main building near the deposit, and over time it puts down wells, pits
## or logging stands wherever the resource is richest around it, as long as
## they pay. Deposits never run out. The player can only reserve land.
##
## Each kind spreads the way the real thing does (see Balance OIL_SPACING_CELLS
## and on): oil pads spaced out and offset across the lease, one quarry that
## widens from the plant, and timber cut a few harvest units at a time, each
## left to regrow before it's cut again.
##
## Every load it produces leaves on a real truck (see Logistics).

const PAD := 80.0               # one well pad, pit or logging stand, square
const MAX_DRIVE := 250.0        # longest access road out to a public road
const MAX_PADS := 60
## How far out (in pads) a new company looks for its first one: 400 m, the
## same reach the placing tool reports.
const SEED_REACH := 5
## The main building's yard.
const HQ_SIZE := Vector2(40, 40)
## What a company's leader builds beside its main yard (Agency.TREES), each
## drawn after a real example by UpgradeKits (Brawn 2026-10-23: every
## upgrade shows). node id -> [width, depth] in metres and the spots it may
## take, [x, z] centres in the company's frame (x to its right, z away from
## its drive), first choice first. It takes the first spot whose ground is
## free; with none free it can't build. Upgrades drawn in place (the tank
## battery, the crusher, the chip mill) need no spot.
const ADDONS := {
	"oil": {
		"gas_plant": [[28, 24], [[-24, 22], [24, 26], [-26, -26]]],
		"pipeline": [[12, 8], [[27, 4], [27, -12], [-28, 4]]],
		"frac_crew": [[22, 20], [[-29, -8], [29, -12], [-28, 28]]],
		"terminal": [[34, 28], [[22, 26], [-22, 26], [0, 26]]],
	},
	"ore": {
		"wash_plant": [[20, 36], [[28, -18], [-29, -18]]],
		"conveyor": [[24, 6], [[28, 6]]],
		"rail_loadout": [[14, 80], [[-33, 0]]],
	},
	"forest": {
		"log_yard": [[14, 40], [[-31, -4], [31, -4]]],
		"dry_kiln": [[16, 36], [[31, -2], [-31, -2]]],
		"pellet_mill": [[36, 16], [[-14, 31], [14, 31], [14, -31]]],
		"replanting": [[8, 18], [[31, 30], [-31, 30], [-31, -30], [31, -30]]],
	},
}
## What the main yard already holds in each company's frame: [x0, z0, x1, z1].
const ADDON_BASE := {
	"oil": [[-16, -23, 21, 12]],
	"ore": [[-16, -23, 0, -4], [-24, -4, 15, 20], [-24, 19, 35, 37]],
	"forest": [[-20, -20, 20, 20]],
}

## Names, the resource each works and its cargo; the numbers are in Balance.
const KINDS := {
	"oil": {"name": "Oil company", "resource": Resources.Kind.OIL, "cargo": "crude oil", "purpose": "fuel",
		"pad": "well pad", "cost": Balance.INDUSTRY["oil"]["cost"]},
	"ore": {"name": "Mining company", "resource": Resources.Kind.ORE, "cargo": "ore", "purpose": "raw",
		"pad": "pit", "cost": Balance.INDUSTRY["ore"]["cost"]},
	"forest": {"name": "Forestry company", "resource": Resources.Kind.FOREST, "cargo": "logs", "purpose": "raw",
		"pad": "logging stand", "cost": Balance.INDUSTRY["forest"]["cost"]},
}
const HAUL_PER_KM := Balance.INDUSTRY_HAUL_PER_KM
const PAD_VALUE := Balance.INDUSTRY_PAD_VALUE
const COMPACT_BONUS := Balance.INDUSTRY_COMPACT_BONUS
const RESERVE_BONUS := Balance.INDUSTRY_RESERVE_BONUS
const MIN_RICHNESS := Balance.INDUSTRY_MIN_RICHNESS
const STOCK_CAP := Balance.INDUSTRY_STOCK_CAP
const DECIDE_EVERY := Balance.INDUSTRY_DECIDE_EVERY

## Companies: id -> {kind, pos, dir, drive, pads: Array of Vector2i in its
## own frame (0,0 is the main building), stock, loss_streak}
var sites := {}
var reserves: Reserves
## The town's sliders: Funding is support per pad, Growth how eagerly a
## company opens more pads (see Policies).
var policies: Policies
## The town's character: a coal town's mines open new cuts more readily.
var culture: TownCulture
## Set by the city: the industrial tax rate (percent) and a price factor.
var tax_rate := 1.5
var price := 1.0
## Game days since the start, set by the city (harvest units regrow).
## True when a public road runs between two points (set by CitySim).
var road_between: Callable
var day := 0.0
## Set by the city: an oil or timber company that has worked out its lease
## builds a gravel lease road to new ground (CitySim._industry_road).
var expand := Callable()
## Set by the city: what an acre sells for at a point (Capital.land_price).
var land_price_of := Callable()
## Set by the city: lays the lease or logging road out to a new pad, paid
## from the company's cash; false when no road can reach it (CitySim._pad_road).
var pad_road := Callable()
## Set by the city: is all this ground open or already the company's own?
## Callable(points, "site:<id>") -> bool (Capital.land_free).
var land_free := Callable()
var _next_id := 1


func add_site(kind: String, pos: Vector3, dir: Vector3, drive: Array) -> int:
	var id := _next_id
	_next_id += 1
	sites[id] = {"kind": kind, "pos": pos, "dir": dir, "drive": drive, "pads": [], "stock": 0.0,
		"loss_streak": 0, "owned": {}}
	# Its startup cash buys its first few pads (Capital).
	Capital.start(sites[id], kind)
	return id


## What opening a pad on cell c costs the company: the ground (leased for
## oil, bought for a quarry or timber it doesn't hold yet) and the work to
## open it (Balance INDUSTRY_PAD_CAPEX).
func pad_price(s: Dictionary, c: Vector2i) -> float:
	var capex := float(Balance.INDUSTRY_PAD_CAPEX[s.kind])
	if s.kind == "oil":
		return capex + Balance.INDUSTRY_OIL_BONUS_PER_ACRE * Balance.INDUSTRY_OIL_UNIT_ACRES
	if s.get("owned", {}).has(c):
		return capex  # its own ground, cut before or worked out
	var acre: float = land_price_of.call(pad_center(s, c)) if land_price_of.is_valid() \
		else Balance.CAPITAL_LAND_PER_ACRE
	return capex + acre * PAD * PAD / 4046.86


## What a lender counts on the company keeping a year: what it already
## produces, not the pad it hasn't opened yet (reserve-based lenders lend on
## proven production), so a new company's first pads are paid in cash.
func _income(id: int, _c: Vector2i) -> float:
	var s: Dictionary = sites[id]
	return Capital.kept(s, "company", Capital.steady(s, yearly_profit(id)))


static func _right(s: Dictionary) -> Vector3:
	return Vector3(-s.dir.z, 0.0, s.dir.x)


static func pad_center(s: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = s.pos + _right(s) * (c.x * PAD) - s.dir * (c.y * PAD)
	if s.kind != "ore" and c != Vector2i.ZERO:
		# Wells and harvest units sit where the ground suits, not on a grid.
		var h := hash([c.x, c.y, roundi(s.pos.x), roundi(s.pos.z)])
		p += _right(s) * float(h % 25 - 12) - s.dir * float((h / 25) % 25 - 12)
	return Vector3(p.x, 0.0, p.z)


## The pad a pad's track runs to: the neighbour nearer the main building.
static func track_to(s: Dictionary, c: Vector2i) -> Vector2i:
	var home := pad_center(s, Vector2i.ZERO)
	var mine := pad_center(s, c)
	var best := Vector2i.ZERO
	var best_d := mine.distance_to(home)
	for o in s.pads:
		var p := pad_center(s, o)
		var d := mine.distance_to(p)
		if o != c and p.distance_to(home) < mine.distance_to(home) - 1.0 and d < best_d:
			best_d = d
			best = o
	return best


## A pad's track in world space. Well pads and pits get a straight lease
## road. Logging roads bend: real ones (US Forest Service and Indiana DNR
## forestry road guides) follow the contour and swing around wet ground
## and big trees, so each one leaves its stand straight past the landing
## and bows to one side on its way to the next.
static func track(s: Dictionary, c: Vector2i) -> PackedVector3Array:
	var a := pad_center(s, c)
	var b := pad_center(s, track_to(s, c))
	if s.kind != "forest":
		return PackedVector3Array([a, b])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([roundi(s.pos.x), roundi(s.pos.z), c])
	var dir := (b - a).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * rng.randf_range(10.0, 20.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var length := a.distance_to(b)
	var p1 := a + dir * length * 0.3
	var p2 := b - dir * length * 0.3 + side
	var wiggle := rng.randf_range(1.0, 2.5)
	var pts := PackedVector3Array()
	for i in 17:
		var t := i / 16.0
		var u := 1.0 - t
		var p := a * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + b * t * t * t
		pts.append(p + side.normalized() * sin(t * TAU) * wiggle * sin(t * PI))
	return pts


static func pad_corners(s: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := pad_center(s, c)
	# A producing well pad is about an acre of gravel (64 m square).
	var half := 32.0 if s.kind == "oil" else PAD * 0.5
	var r: Vector3 = _right(s) * half
	var b: Vector3 = -s.dir * half
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * k.x + b * k.y
		out.append(Vector2(p.x, p.z))
	return out


## How rich the deposit is under a pad.
static func richness(s: Dictionary, c: Vector2i) -> float:
	return Resources.at(KINDS[s.kind].resource, pad_center(s, c))


## One pad's yearly profit: what it produces, less running it, hauling to
## the main building and property tax.
func pad_profit(s: Dictionary, c: Vector2i) -> float:
	var k: Dictionary = Balance.INDUSTRY[s.kind]
	var km := pad_center(s, c).distance_to(Vector3(s.pos.x, 0.0, s.pos.z)) / 1000.0
	var tree: Array = Agency.TREES[s.kind]
	var gross: float = 12.0 * k.loads * k.price * richness(s, c) * price \
		* Agency.effect(s, tree, "output*") * Agency.effect(s, tree, "price*")
	return gross - k.pad_cost - HAUL_PER_KM * km * Agency.effect(s, tree, "haul*") - PAD_VALUE * tax_rate / 100.0


func yearly_profit(id: int) -> float:
	var total := 0.0
	for c in sites[id].pads:
		total += pad_profit(sites[id], c)
	return total + sites[id].pads.size() * support(id)


## What the town pays a company per pad a year (a fee when negative).
func support(id: int) -> float:
	if policies == null:
		return 0.0
	return policies.pick(Balance.POLICY_SUPPORT_PER_PAD, "funding", "resources", "industry:%d" % id)


## The yearly profit a new pad must clear before company `id` opens it (INF: none).
func buy_margin(id: int) -> float:
	if policies == null:
		return 0.0
	var m: float = policies.pick(Balance.POLICY_BUY_MARGIN_PER_PAD, "growth", "resources", "industry:%d" % id)
	if culture != null and m < INF and sites.has(id):
		m -= culture.pull(TownCulture.sector_of_kind(sites[id].kind)) * Balance.CULTURE_MARGIN_PER_PAD
	return m


## What the town pays all its companies a year (negative: what it collects).
func yearly_support() -> float:
	var total := 0.0
	for id in sites:
		total += sites[id].pads.size() * support(id)
	return total


## Every company takes a step: it adds the best paying pad next to what it
## has (on rich enough ground the city leaves free), or closes its worst
## if that keeps losing money. A new company opens its first pad on the best
## ground within reach, with a haul track back, and grows out from there.
## `usable(centre, corners)` comes from the city. When a new company finds
## nothing, `idle` on the site says why (not saved; set again each step).
func decide(usable: Callable) -> bool:
	var changed := false
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sites[id]
		var sup := support(id)
		var margin := buy_margin(id)
		var best := Vector2i.MAX
		var best_score := -INF
		var ranked := []  # [score, cell] of every pad it could open
		# What stopped a new company, for its panel: 0 nothing rich, 1 nothing pays, 2 all taken.
		var why := 0
		if s.kind == "forest":
			changed = _rotate(s) or changed
		# Its own money: kept profit in, land loan payments out (Capital).
		Capital.step(s, "company", yearly_profit(id), day)
		if s.pads.size() < _max_pads(s) and margin < INF:
			for c in _candidates(s):
				if richness(s, c) < MIN_RICHNESS:
					continue
				var p := pad_profit(s, c) + sup
				# A new company's first pad has to pay, whatever it's told.
				if p <= (maxf(margin, 0.0) if s.pads.is_empty() else margin):
					why = maxi(why, 1)
					continue
				if not _free(id, s, c, usable):
					why = 2
					continue
				var score := p + (COMPACT_BONUS * _neighbors(s, c) if s.kind == "ore" else 0.0)
				if reserves != null and reserves.kind_at(pad_center(s, c)) == s.kind:
					score += RESERVE_BONUS
				ranked.append([score, c])
				if score > best_score or (score == best_score and best != Vector2i.MAX and _less(c, best)):
					best = c
					best_score = score
		var worst := Vector2i.MAX
		for c in s.pads:
			if worst == Vector2i.MAX or pad_profit(s, c) < pad_profit(s, worst):
				worst = c
		if worst != Vector2i.MAX and pad_profit(s, worst) + sup < minf(margin, 0.0):
			s.loss_streak += 1
			if s.loss_streak >= 2:
				s.pads.erase(worst)
				s.loss_streak = 0
				changed = true
		elif best != Vector2i.MAX:
			# The best few it can reach with a road, paid for from its own
			# cash and a land loan, never the town's money. Short of cash it
			# saves up: growth comes from what it keeps.
			ranked.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and _less(a[1], b[1])))
			for e in ranked.slice(0, 6):
				var c: Vector2i = e[1]
				var price := pad_price(s, c)
				if not Capital.can_buy(s, price, _income(id, c)):
					break
				if pad_road.is_valid() and not pad_road.call(id, c, float(s.cash) - Capital.cash_needed(s, price, _income(id, c))):
					continue
				Capital.buy(s, price, _income(id, c))
				if not s.has("owned"):
					s.owned = {}
				s.owned[c] = day
				s.pads.append(c)
				s.loss_streak = 0
				changed = true
				break
		elif expand.is_valid() and wants_road(id, usable):
			changed = expand.call(id) or changed
		var idle := ""
		if s.pads.is_empty():
			var k: Dictionary = KINDS[s.kind]
			idle = ["No %s rich enough within 400 m. Move it closer to the dark ground in the view.",
				"The %s within 400 m is too thin to pay for a pad yet.",
				"Every rich spot within 400 m is built on, farmed or reserved for something else."][why]
			if why < 2:
				idle = idle % k.cargo
			if best != Vector2i.MAX and s.pads.is_empty():
				idle = "Saving up for its first %s ($%s)." % [k.pad, CitySim.money_text(roundi(pad_price(s, best)))]
			if margin == INF:
				idle = "On hold: it opens no pads until its Growth is raised."
		if s.get("idle", "") != idle:
			s.idle = idle
			changed = true
	return changed


## The pad a company would put down next: the best paying free one next to
## what it has, or Vector2i.MAX.
func best_pad(id: int, usable: Callable) -> Vector2i:
	if not sites.has(id) or sites[id].pads.is_empty() or sites[id].pads.size() >= _max_pads(sites[id]):
		return Vector2i.MAX
	var s: Dictionary = sites[id]
	var best := Vector2i.MAX
	var best_score := 0.0
	for c in _candidates(s):
		if richness(s, c) < MIN_RICHNESS:
			continue
		var p := pad_profit(s, c)
		if p <= 0.0 or not _free(id, s, c, usable):
			continue
		var score := p + (COMPACT_BONUS * _neighbors(s, c) if s.kind == "ore" else 0.0)
		if reserves != null and reserves.kind_at(pad_center(s, c)) == s.kind:
			score += RESERVE_BONUS
		if score > best_score or (score == best_score and best != Vector2i.MAX and _less(c, best)):
			best = c
			best_score = score
	return best


## Where a company may open its next pad. Oil: anywhere on its lease at
## least the well spacing from its other pads. Ore: the first bench beside
## the plant, then only cells touching the quarry, so it grows as one pit.
## Forest: any timber on its land that isn't being cut or regrowing.
func _candidates(s: Dictionary) -> Array:
	if s.kind == "ore":
		# An area strip mine opens beside its plant, on its own side of any
		# road, and advances one way, cut after cut, never back past the plant.
		if s.pads.is_empty():
			return _seeds().filter(func(c): return c.y != 0 and not (road_between.is_valid()
				and road_between.call(s.pos, pad_center(s, c))))
		var first: Vector2i = s.pads[0]
		var way := signi(first.y) if first.y != 0 else 1
		return _frontier(s).filter(func(c): return c.y * way >= first.y * way)
	var out := []
	var r := Balance.LEASE_REACH_CELLS if not s.pads.is_empty() else SEED_REACH
	var resting: Dictionary = s.get("regrow", {})
	var seen := {}
	# Its first lease around the main building, then any tracts it has
	# bought since, each reached by its own lease road.
	for o in [Vector2i.ZERO] + s.get("leases", []):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var c: Vector2i = o + Vector2i(x, y)
				if seen.has(c) or c == Vector2i.ZERO or (c - o).length_squared() > r * r or c in s.pads \
						or resting.has(c):
					continue
				seen[c] = true
				if s.kind == "oil" and not _spaced(s, c):
					continue
				if not s.pads.is_empty() and not _beside_worked(s, c):
					continue
				out.append(c)
	return out


## True when cell c grows the company's ground from what it already works:
## an offset to a well it has, or the woods next to units it has cut.
static func _beside_worked(s: Dictionary, c: Vector2i) -> bool:
	var reach: int = Balance.OIL_OFFSET_CELLS if s.kind == "oil" else Balance.FOREST_NEXT_CELLS
	var worked: Array = [Vector2i.ZERO] + s.pads + s.get("leases", []) + s.get("cut", {}).keys() \
		+ s.get("regrow", {}).keys()
	for o in worked:
		if maxi(absi(o.x - c.x), absi(o.y - c.y)) <= reach:
			return true
	return false


## True when company `id` has worked out its lease and should take on new
## ground with a road (Brawn: hubs grow to a real size, then build a road).
## Real reference: Illinois Basin operators lease the next tract and run a
## gravel lease road to it from the county road; timber companies buy
## stumpage on the next woods and cut a logging road in. Quarries don't: a
## pit keeps widening from its plant.
func wants_road(id: int, usable: Callable) -> bool:
	var s: Dictionary = sites[id]
	if s.kind == "ore" or s.pads.is_empty() or buy_margin(id) == INF or day < float(s.get("road_wait", 0.0)):
		return false
	if not s.get("pending", {}).is_empty():
		return true  # a road it asked the player for
	if s.get("leases", []).size() >= Balance.INDUSTRY_MAX_LEASES \
			or yearly_profit(id) < Balance.INDUSTRY_ROAD_MIN_PROFIT:
		return false
	# Worked out: nothing left on its leases that pays and is free.
	var sup := support(id)
	var margin := buy_margin(id)
	for c in _candidates(s):
		if richness(s, c) >= MIN_RICHNESS and pad_profit(s, c) + sup > margin and _free(id, s, c, usable):
			return false
	return true


## The centre cell of the next tract company `id` would lease: the best
## paying free ground just past its leases, or Vector2i.MAX.
func next_lease(id: int, usable: Callable) -> Vector2i:
	var s: Dictionary = sites[id]
	var r := Balance.LEASE_REACH_CELLS
	var centres: Array = [Vector2i.ZERO] + s.get("leases", [])
	var sup := support(id)
	var margin := maxf(buy_margin(id), 0.0)
	var best := Vector2i.MAX
	var best_score := -INF
	for o in centres:
		for y in range(-r * 2, r * 2 + 1, 2):
			for x in range(-r * 2, r * 2 + 1, 2):
				var c: Vector2i = o + Vector2i(x, y)
				var near := INF
				for q in centres:
					near = minf(near, (c - q).length())
				# Past what it holds, but next to it: tracts touch.
				if near <= r * 0.75 or near > r * 1.25:
					continue
				if richness(s, c) < MIN_RICHNESS or (s.kind == "oil" and not _spaced(s, c)):
					continue
				var p := pad_profit(s, c) + sup
				if p <= margin or not _free(id, s, c, usable):
					continue
				var score := p - near * 100.0
				if score > best_score or (score == best_score and _less(c, best)):
					best = c
					best_score = score
	return best


## True when a new well pad here keeps the spacing from the company's others.
static func _spaced(s: Dictionary, c: Vector2i) -> bool:
	for o in s.pads:
		if maxi(absi(o.x - c.x), absi(o.y - c.y)) < Balance.OIL_SPACING_CELLS:
			return false
	return true


static func _max_pads(s: Dictionary) -> int:
	return Balance.FOREST_ACTIVE_UNITS if s.kind == "forest" else MAX_PADS


## Harvest units cut long enough are left to regrow, and regrown ones open
## again. True when anything changed.
func _rotate(s: Dictionary) -> bool:
	if not s.has("cut"):
		s.cut = {}
	if not s.has("regrow"):
		s.regrow = {}
	var changed := false
	for c in s.pads.duplicate():
		if not s.cut.has(c):
			s.cut[c] = day
		elif day - float(s.cut[c]) >= Balance.FOREST_CUT_DAYS:
			s.pads.erase(c)
			s.cut.erase(c)
			s.regrow[c] = day
			changed = true
	for c in s.regrow.keys():
		if day - float(s.regrow[c]) >= Balance.FOREST_REGROW_DAYS:
			s.regrow.erase(c)
			changed = true
	return changed


## How grown back a resting harvest unit is, 0 (just cut) to 1 (mature).
static func regrowth(s: Dictionary, c: Vector2i, now: float) -> float:
	if not s.get("regrow", {}).has(c):
		return 1.0
	return clampf((now - float(s.regrow[c])) / Balance.FOREST_REGROW_DAYS, 0.0, 1.0)


## Cells a new company may open its first pad on.
static func _seeds() -> Array:
	var out := []
	for y in range(-SEED_REACH, SEED_REACH + 1):
		for x in range(-SEED_REACH, SEED_REACH + 1):
			var c := Vector2i(x, y)
			if c != Vector2i.ZERO and c.length_squared() <= SEED_REACH * SEED_REACH:
				out.append(c)
	return out


## Loads produced over `hours` of game time (a game day is a month).
func produce(hours: float) -> void:
	for id in sites:
		var s: Dictionary = sites[id]
		var cap := stock_cap(s)
		if s.stock >= cap:
			continue
		var k: Dictionary = Balance.INDUSTRY[s.kind]
		var rate := 0.0
		for c in s.pads:
			rate += k.loads * richness(s, c)
		rate *= Agency.effect(s, Agency.TREES[s.kind], "output*")
		s.stock = minf(cap, s.stock + rate * hours / 24.0)


## Loads the yard holds (more with a tank battery or log yard).
static func stock_cap(s: Dictionary) -> float:
	return STOCK_CAP + Agency.effect(s, Agency.TREES[s.kind], "stock+")


## The company whose main building yard or access road holds this point.
func site_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		var s: Dictionary = sites[id]
		if Geometry2D.is_point_in_polygon(q, _yard(s)):
			return id
		if Farms._near_drive(s, p, Farms.DRIVE_WIDTH * 0.5 + 3.0):
			return id
		if not s.get("addons", {}).is_empty() and _in_addon(s, p):
			return id
	return -1


## True when p is on ground one of the company's add-ons stands on.
static func _in_addon(s: Dictionary, p: Vector3) -> bool:
	var d: Vector3 = p - s.pos
	var local := Vector2(d.dot(_right(s)), -d.dot(s.dir))
	for node in s.addons:
		if addon_rect(s, node).grow(2.0).has_point(local):
			return true
	return false


## The ground an add-on stands on, in the company's frame (x, z).
static func addon_rect(s: Dictionary, node: String) -> Rect2:
	var at: Array = s.addons[node]
	var size: Array = ADDONS[s.kind][node][0]
	return Rect2(float(at[0]) - size[0] * 0.5, float(at[1]) - size[1] * 0.5, size[0], size[1])


## Finds ground for what the leader just built (`node`) and records it in
## s.addons. False when every spot is taken (a road, homes, another hub or
## land that won't build): the company then can't build it. `free` is
## Callable(world point) -> bool for ground the company may use.
func place_addon(id: int, node: String, free: Callable) -> bool:
	var s: Dictionary = sites[id]
	if not ADDONS.get(s.kind, {}).has(node):
		return true  # drawn in its yard
	if not s.has("addons"):
		s.addons = {}
	var spec: Array = ADDONS[s.kind][node]
	for at in spec[1]:
		s.addons[node] = [float(at[0]), float(at[1])]
		var r := addon_rect(s, node)
		var ok := true
		for b in ADDON_BASE[s.kind]:
			ok = ok and not r.intersects(Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1]))
		for other in s.addons:
			ok = ok and (other == node or not r.intersects(addon_rect(s, other)))
		if ok:
			# Ground under it: its corners, edges and middle.
			for fx in [0.05, 0.5, 0.95]:
				for fz in [0.05, 0.5, 0.95]:
					var q := r.position + r.size * Vector2(fx, fz)
					ok = ok and free.call(s.pos + _right(s) * q.x - s.dir * q.y)
		if ok:
			return true
	s.addons.erase(node)
	return false


## The company with a pad on this point.
func pad_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		var s: Dictionary = sites[id]
		var d: Vector3 = p - s.pos
		var near := Vector2i(roundi(d.dot(_right(s)) / PAD), roundi(-d.dot(s.dir) / PAD))
		# Pads sit off the grid a little, so look at the cells around too.
		for dx in [0, -1, 1]:
			for dy in [0, -1, 1]:
				var c: Vector2i = near + Vector2i(dx, dy)
				if c in s.pads and Geometry2D.is_point_in_polygon(q, pad_corners(s, c)):
					return id
	return -1


func covers(p: Vector3) -> bool:
	return site_at(p) != -1 or pad_at(p) != -1


## The company that owns the land at p (Brawn, 2026-10-23: land has one
## owner): its yard and road in, each pad with the working ground around it
## (Balance.INDUSTRY_CLAIM_BUFFER), and the tracts it has leased. -1 if none.
func claim_at(p: Vector3) -> int:
	var id := site_at(p)
	if id != -1:
		return id
	var q := Vector2(p.x, p.z)
	var buffer := float(Balance.INDUSTRY_CLAIM_BUFFER)
	for sid in sites:
		var s: Dictionary = sites[sid]
		var d: Vector3 = p - s.pos
		var near := Vector2i(roundi(d.dot(_right(s)) / PAD), roundi(-d.dot(s.dir) / PAD))
		for dx in [0, -1, 1]:
			for dy in [0, -1, 1]:
				var c: Vector2i = near + Vector2i(dx, dy)
				# Its pads, leases and land bought, and woods cut and growing back.
				if not (c in s.pads or c in s.get("leases", []) or s.get("owned", {}).has(c)
						or s.get("cut", {}).has(c) or s.get("regrow", {}).has(c)):
					continue
				var poly := pad_corners(s, c)
				if Geometry2D.is_point_in_polygon(q, poly):
					return sid
				# The working ground around the pad.
				for i in poly.size():
					var a: Vector2 = poly[i]
					var b: Vector2 = poly[(i + 1) % poly.size()]
					if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < buffer:
						return sid
	return -1


func jobs() -> int:
	var total := 0
	for id in sites:
		var k: Dictionary = Balance.INDUSTRY[sites[id].kind]
		total += k.jobs_hq + k.jobs_pad * sites[id].pads.size() \
			+ int(Agency.effect(sites[id], Agency.TREES[sites[id].kind], "jobs+"))
	return total


## Property value the city taxes (main buildings and pads).
func taxable_value() -> float:
	var total := 0.0
	for id in sites:
		total += float(KINDS[sites[id].kind].cost) + PAD_VALUE * sites[id].pads.size()
	return total


func reserved_ok(kind: String, p: Vector3) -> bool:
	return reserves == null or reserves.kind_at(p) in ["", kind]


func _free(id: int, s: Dictionary, c: Vector2i, usable: Callable) -> bool:
	var mid := pad_center(s, c)
	if not reserved_ok(s.kind, mid):
		return false
	var corners := pad_corners(s, c)
	if Farms._drive_crosses(s, corners):
		return false
	var pts := [mid]
	for p in corners:
		pts.append(mid.lerp(Vector3(p.x, 0.0, p.y), 0.8))
	for p in pts:
		var other := pad_at(p)
		if (other != -1 and other != id) or (site_at(p) != -1 and site_at(p) != id):
			return false
	# Nobody else's land: a farm's fields, another company's ground.
	if land_free.is_valid() and not land_free.call(pts, "site:%d" % id):
		return false
	return usable.call(mid, corners)


func _frontier(s: Dictionary) -> Array:
	var out := []
	var seen := {Vector2i.ZERO: true}
	for c in s.pads:
		seen[c] = true
	for c in s.pads:
		# Edge neighbours only: the quarry widens, it doesn't skip across.
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			# A mine stays on its own side of a public road; it never jumps it.
			if road_between.is_valid() and road_between.call(pad_center(s, c), pad_center(s, n)):
				continue
			seen[n] = true
			out.append(n)
	return out


static func _neighbors(s: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if (c + d) in s.pads or c + d == Vector2i.ZERO:
			n += 1
	return n


static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func _yard(s: Dictionary) -> PackedVector2Array:
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
		var pads := []
		for c in s.pads:
			pads.append([c.x, c.y])
		var lane := []
		for p in s.drive:
			lane.append([p.x, p.z])
		out[str(id)] = {"kind": s.kind, "pos": [s.pos.x, s.pos.z], "dir": [s.dir.x, s.dir.z],
			"drive": lane, "pads": pads, "stock": s.stock, "loss": s.loss_streak,
			"leader": s.get("leader", {}), "built": s.get("built", []), "why": s.get("why", ""),
			"cut": _cells_out(s.get("cut", {})), "regrow": _cells_out(s.get("regrow", {})),
			"leases": s.get("leases", []).map(func(c): return [c.x, c.y]),
			"owned": _cells_out(s.get("owned", {})), "capital": Capital.save(s),
			"road_wait": s.get("road_wait", 0.0), "pending": s.get("pending", {}), "addons": s.get("addons", {})}
	return {"sites": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	for k in d.get("sites", {}):
		var s: Dictionary = d.sites[k]
		var pads := []
		for c in s.pads:
			pads.append(Vector2i(int(c[0]), int(c[1])))
		var lane := []
		for p in s.drive:
			lane.append(Vector3(p[0], 0.0, p[1]))
		sites[int(k)] = {"kind": str(s.kind), "pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": Vector3(s.dir[0], 0.0, s.dir[1]).normalized(), "drive": lane, "pads": pads,
			"stock": float(s.get("stock", 0.0)), "loss_streak": int(s.get("loss", 0))}
		if not s.get("leader", {}).is_empty():
			sites[int(k)].leader = s.leader
		sites[int(k)].built = Array(s.get("built", []))
		sites[int(k)].why = str(s.get("why", ""))
		sites[int(k)].cut = _cells_in(s.get("cut", []))
		sites[int(k)].regrow = _cells_in(s.get("regrow", []))
		sites[int(k)].leases = s.get("leases", []).map(func(c): return Vector2i(int(c[0]), int(c[1])))
		sites[int(k)].owned = _cells_in(s.get("owned", []))
		if s.has("capital"):
			Capital.load(sites[int(k)], s.capital)
		else:
			Capital.start(sites[int(k)], str(s.kind))
		sites[int(k)].road_wait = float(s.get("road_wait", 0.0))
		sites[int(k)].pending = Dictionary(s.get("pending", {}))
		var addons := {}
		var saved_addons: Dictionary = s.get("addons", {})
		for node in saved_addons:
			addons[str(node)] = [float(saved_addons[node][0]), float(saved_addons[node][1])]
		if not addons.is_empty():
			sites[int(k)].addons = addons
	_next_id = int(d.get("next_id", 1))


static func _cells_out(d: Dictionary) -> Array:
	var out := []
	for c in d:
		out.append([c.x, c.y, d[c]])
	return out


static func _cells_in(a: Array) -> Dictionary:
	var out := {}
	for e in a:
		out[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	return out
