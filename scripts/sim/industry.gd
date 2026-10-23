class_name Industry
extends RefCounted
## Resource industry the way Brawn asked, after Cities: Skylines 2's
## specialized industry: open the Oil, Ore or Forest view, place a company's
## main building near the deposit, and over time it puts down wells, pits
## or logging stands wherever the resource is richest around it, as long as
## they pay. Deposits never run out. The player can only reserve land.
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
## Set by the city: the industrial tax rate (percent) and a price factor.
var tax_rate := 1.5
var price := 1.0
var _next_id := 1


func add_site(kind: String, pos: Vector3, dir: Vector3, drive: Array) -> int:
	var id := _next_id
	_next_id += 1
	sites[id] = {"kind": kind, "pos": pos, "dir": dir, "drive": drive, "pads": [], "stock": 0.0,
		"loss_streak": 0}
	return id


static func _right(s: Dictionary) -> Vector3:
	return Vector3(-s.dir.z, 0.0, s.dir.x)


static func pad_center(s: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = s.pos + _right(s) * (c.x * PAD) - s.dir * (c.y * PAD)
	return Vector3(p.x, 0.0, p.z)


static func pad_corners(s: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := pad_center(s, c)
	var r: Vector3 = _right(s) * PAD * 0.5
	var b: Vector3 = -s.dir * PAD * 0.5
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
	return policies.pick(Balance.POLICY_BUY_MARGIN_PER_PAD, "growth", "resources", "industry:%d" % id)


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
		# What stopped a new company, for its panel: 0 nothing rich, 1 nothing pays, 2 all taken.
		var why := 0
		if s.pads.size() < MAX_PADS and margin < INF:
			for c in (_frontier(s) if not s.pads.is_empty() else _seeds()):
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
				var score := p + COMPACT_BONUS * _neighbors(s, c)
				if reserves != null and reserves.kind_at(pad_center(s, c)) == s.kind:
					score += RESERVE_BONUS
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
			s.pads.append(best)
			s.loss_streak = 0
			changed = true
		var idle := ""
		if s.pads.is_empty():
			var k: Dictionary = KINDS[s.kind]
			idle = ["No %s rich enough within 400 m. Move it closer to the dark ground in the view.",
				"The %s within 400 m is too thin to pay for a pad yet.",
				"Every rich spot within 400 m is built on, farmed or reserved for something else."][why]
			if why < 2:
				idle = idle % k.cargo
			if margin == INF:
				idle = "On hold: it opens no pads until its Growth is raised."
		if s.get("idle", "") != idle:
			s.idle = idle
			changed = true
	return changed


## The pad a company would put down next: the best paying free one next to
## what it has, or Vector2i.MAX.
func best_pad(id: int, usable: Callable) -> Vector2i:
	if not sites.has(id) or sites[id].pads.is_empty() or sites[id].pads.size() >= MAX_PADS:
		return Vector2i.MAX
	var s: Dictionary = sites[id]
	var best := Vector2i.MAX
	var best_score := 0.0
	for c in _frontier(s):
		if richness(s, c) < MIN_RICHNESS:
			continue
		var p := pad_profit(s, c)
		if p <= 0.0 or not _free(id, s, c, usable):
			continue
		var score := p + COMPACT_BONUS * _neighbors(s, c)
		if reserves != null and reserves.kind_at(pad_center(s, c)) == s.kind:
			score += RESERVE_BONUS
		if score > best_score or (score == best_score and best != Vector2i.MAX and _less(c, best)):
			best = c
			best_score = score
	return best


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
	return -1


## The company with a pad on this point.
func pad_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in sites:
		var s: Dictionary = sites[id]
		var d: Vector3 = p - s.pos
		var c := Vector2i(roundi(d.dot(_right(s)) / PAD), roundi(-d.dot(s.dir) / PAD))
		if c in s.pads and Geometry2D.is_point_in_polygon(q, pad_corners(s, c)):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return site_at(p) != -1 or pad_at(p) != -1


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
	return usable.call(mid, corners)


func _frontier(s: Dictionary) -> Array:
	var out := []
	var seen := {Vector2i.ZERO: true}
	for c in s.pads:
		seen[c] = true
	var from: Array = s.pads.duplicate()
	from.append(Vector2i.ZERO)
	for c in from:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n):
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
			"leader": s.get("leader", {}), "built": s.get("built", []), "why": s.get("why", "")}
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
	_next_id = int(d.get("next_id", 1))
