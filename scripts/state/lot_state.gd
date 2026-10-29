class_name LotState
extends RefCounted
## The state layer's yard props (docs/spec-state-layer.md, step 1; Nathan,
## 2026-10-29: "as an area improves, its "state layer" makes it look
## better. as an area gets worse, its state items degrade. a state item
## might be a car on cinder blocks in the front yard. or it might be an
## overflowing dumpster."): which things stand in a lot's yard, at its curb
## and by its door, and where, from how well the lot is kept (PropertyCare).
##
## Pure: the same lot, building, condition and town seed always give the
## same items in the same spots, on every copy of the town, with no random
## draws. Each lot rolls each item once from a hash of the town seed, the lot
## key, the building's seed and the item's name; an item shows when its roll
## is under its odds, which grow the further the lot sits into its tier. So
## as a street slips, items appear in the same order and stay put (the car
## that showed up last month is still there), and as it recovers they go
## the same way back.
##
## Only the town's service decides condition (PropertyCare's needs: power,
## water, services, the street, Funding and upkeep), never who lives there.
## Nothing here makes fun of anyone: a car on blocks is somebody's stalled
## repair, drawn plainly.
##
## Lot frame (SiteLayout's): x across the lot, z back from its street edge
## (lot.front), the street at -z. Each item is {"item", "at": Vector2 (x, z),
## "yaw" (radians about up; 0 faces the street), "y" (metres up, for things
## hung on a wall), "col": Color (paint or fabric, sRGB), "v": variant}.

## The items of step 1 (the spec's priority-1 lot items 1 to 4, 8, 19, 20
## and 22): the tiers each shows at, the buildings it shows on, and its odds
## at the far end of its tier (it starts at ODDS_FLOOR of that at the tier's
## line). The real thing each one is, in Marion:
##   car_blocks: a stalled repair on the drive or the side yard, wheels off.
##   cans: garbage day missed, the carts left out at the curb, lids up on
##     the bags (also on any street where trash has piled up uncollected).
##   couch: bulk pickup that never came: an old couch (or a mattress
##     leaned on it) at the curb.
##   dumpster: missed pickups behind a strip center: a 4-yard steel
##     dumpster, a lid propped open on the bags, more bags beside it.
##   lease: an empty storefront's "FOR LEASE" banner across its front.
##   beds: fresh mulch flower beds in front of the house (annuals from May
##     to the first frost).
##   flag: a 3 x 5 ft flag on a porch bracket, common on kept-up Grant
##     County porches.
##   planters: big planters flanking a shop door, planted each May.
const ITEMS := {
	"car_blocks": {"tiers": [-2, -1], "on": ["home"], "odds": 0.38},
	"cans": {"tiers": [-2, -1], "on": ["home"], "odds": 0.9},
	"couch": {"tiers": [-2, -1], "on": ["home", "apartments"], "odds": 0.42},
	"dumpster": {"tiers": [-2, -1], "on": ["shop", "apartments"], "odds": 0.95},
	"lease": {"tiers": [-2], "on": ["shop"], "odds": 0.9},
	"beds": {"tiers": [1, 2], "on": ["home"], "odds": 0.95},
	"flag": {"tiers": [1, 2], "on": ["home"], "odds": 0.6},
	"planters": {"tiers": [1, 2], "on": ["shop"], "odds": 0.95},
}
## An item's odds right at its tier's line, as a share of its full odds.
const ODDS_FLOOR := 0.4
## Carts left out on a street where trash has piled up, at any tier.
const PILED_ODDS := 0.8
## The building types each kind of lot covers (BuildingTypes).
const KINDS := {"house": "home", "duplex": "home", "row_home": "home", "apartments": "apartments",
	"shop": "shop", "mixed_use": "shop", "commercial_block": "shop", "shopping_center": "shop"}
## Footprints (metres across x, deep along z, before turning) for the
## free-spot check.
const SIZE := {"car_blocks": Vector2(2.0, 5.0), "cans": Vector2(2.5, 1.0), "couch": Vector2(2.4, 1.2),
	"dumpster": Vector2(3.0, 1.6), "planter": Vector2(0.85, 0.85)}
## Faded 1990s paint: oxidized red, chalky maroon, sun-bleached blue,
## faded green, dull champagne, grey primer.
const OLD_PAINT := [Color("#8a4a40"), Color("#5e3236"), Color("#6f7f93"), Color("#5f6f5c"),
	Color("#a89a82"), Color("#7b7d7c")]
## Couch fabric: brown plaid-ish, olive, faded blue, beige, rust.
const FABRIC := [Color("#6b5443"), Color("#6a6a45"), Color("#55627a"), Color("#9b8d74"), Color("#87543a")]
## Dumpster steel: hauler green, blue, brown, grey.
const STEEL := [Color("#2f4a36"), Color("#2a4366"), Color("#5a4632"), Color("#55595c")]
## Cart bodies: municipal black, green and grey.
const CARTS := [Color("#2a2b2c"), Color("#2f4a35"), Color("#3a3d40")]
## Annuals: red geraniums, pink petunias, yellow marigolds, purple salvia,
## white impatiens, orange zinnias.
const FLOWERS := [Color("#c4222b"), Color("#e06aa0"), Color("#f0c020"), Color("#6a3c9c"), Color("#f2f0ea"),
	Color("#e8742a")]


## The kind of lot a building makes ("home", "apartments", "shop"), or ""
## for one with no step-1 items (offices, hotels, factories).
static func kind_of(b: Dictionary) -> String:
	return KINDS.get(BuildingTypes.type_of(b), "")


## A roll from 0 to 1 for one thing on one lot.
static func roll(city_seed: int, key: String, bseed: int, what: String) -> float:
	return float(posmod(hash([city_seed, key, bseed, what]), 100003)) / 100003.0


## How far into its tier a condition sits: 0 at the tier's line, 1 at the
## far end (0 or 1). 0 for a kept-up lot.
static func depth_in(tier: int, cond: float) -> float:
	var at: Array = Balance.CARE_TIERS
	if tier < 0:
		return clampf((float(at[1]) - cond) / float(at[1]), 0.0, 1.0)
	if tier > 0:
		return clampf((cond - float(at[2])) / (1.0 - float(at[2])), 0.0, 1.0)
	return 0.0


## Which items show on a lot: names, in a fixed order. `piled`: trash has
## piled up uncollected on the lot's street (CivicHubs.trash).
static func shown(city_seed: int, key: String, bseed: int, kind: String, tier: int, cond: float, piled := false) -> Array:
	var out := []
	var d := depth_in(tier, cond)
	for name in ITEMS:
		var it: Dictionary = ITEMS[name]
		if not kind in it.on:
			continue
		var r := roll(city_seed, key, bseed, name)
		if tier in it.tiers and r < float(it.odds) * lerpf(ODDS_FLOOR, 1.0, d):
			out.append(name)
		elif name == "cans" and piled and r < PILED_ODDS:
			out.append(name)
	return out


## The lot's yard as the builders drew it, in the lot frame: where its door,
## drive, garage, porch and building masses are, and where cars park.
## `masses`: the building's footprints (Rect2s, x and z) as BuildingView
## drew them; without them the plan's own house outline stands in.
static func yard_of(sim, key: String, masses := []) -> Dictionary:
	var b: Dictionary = sim.buildings[key]
	var lot: Dictionary = sim.lots[key]
	var type := BuildingTypes.type_of(b)
	var storeys := BuildingTypes.storeys(b)
	var fit := SiteLayout._fit(lot)
	var y := {"kind": kind_of(b), "half": float(fit.half), "depth": float(fit.depth),
		"to_curb": float(lot.get("to_curb", 2.0)), "door": Vector2(0.0, 0.4), "drive_x": 0.0, "drive_w": 0.0,
		"garage_z": -1.0, "front_z": 0.4, "porch": Rect2(), "main_street": false,
		"masses": masses.duplicate(), "stalls": [], "bays": 0}
	if type == "house":
		# The plan the art draws (HouseBuilder.plan_info), read once: the
		# same one SiteLayout.house reads for the traffic's drive stall.
		var r := RandomNumberGenerator.new()
		r.seed = int(b.seed)
		var h := HouseBuilder.plan_info(r.randi(), fit.get("art", {"width": fit.half * 2.0, "depth": fit.depth}), storeys)
		y.drive_x = float(h.drive_x)
		y.drive_w = float(h.drive_w)
		y.garage_z = float(h.get("garage_z", -1.0))
		y.front_z = float(h.front_z)
		y.door = Vector2(float(h.door_x), float(h.front_z))
		y.bays = 1 if y.drive_w < 4.5 else (2 if y.drive_w < 8.5 else 3)
		var bay: float = y.drive_w / y.bays
		if y.bays > 1 and y.garage_z - 3.2 >= 2.6:
			y.stalls.append(Vector2(y.drive_x + (y.bays - 1) * 0.5 * bay, y.garage_z - 3.2))
		if h.get("porch", null) is Rect2:
			y.porch = h.porch
		if y.masses.is_empty() and h.has("x0"):
			y.masses = [Rect2(float(h.x0), float(h.front_z), float(h.x1) - float(h.x0), 10.0)]
	else:
		var lay := SiteLayout.for_building(int(b.zone), int(b.seed), lot, storeys, type, int(b.get("level", 0)),
			sim.network, int(b.get("added_from", 0)))
		y.door = lay.door
		y.front_z = float(lay.door.y)
		y.drive_x = float(lay.cut_x)
		y.main_street = bool(lay.main_street)
		for s in lay.spots:
			if s.kind == "stall" or s.kind == "drive":
				y.stalls.append(s.pos)
		if y.drive_x != 0.0 or not y.stalls.is_empty():
			y.drive_w = 3.0 if kind_of(b) == "home" else 0.0
	if y.masses.is_empty():
		# Not drawn (a headless test): the building as a block behind its door.
		var d: Vector2 = y.door
		var z0 := maxf(d.y, 0.5)
		y.masses = [Rect2(-y.half + 1.5, z0, y.half * 2.0 - 3.0, maxf(6.0, y.depth - z0 - 3.0))]
	return y


## Every item on a lot, placed: the items shown() picks, each in the first
## free spot of its own (tried in an order from the lot's hash), or left
## out when the yard has no room for it. Every item the lot could show at
## its tier is given its spot, shown or not, so one that comes later never
## moves one already there.
static func items(city_seed: int, key: String, bseed: int, tier: int, cond: float, yard: Dictionary, piled := false) -> Array:
	var show := shown(city_seed, key, bseed, String(yard.kind), tier, cond, piled)
	if show.is_empty():
		return []
	var out := []
	var taken: Array = []  # Rect2s already used on this lot
	for name in ITEMS:
		var it: Dictionary = ITEMS[name]
		if not String(yard.kind) in it.on or not (tier in it.tiers or name == "cans" and piled):
			continue
		var h := hash([city_seed, key, bseed, name, "spot"])
		match name:
			"car_blocks": _car(out, taken, yard, h)
			"cans": _cans(out, taken, yard, h)
			"couch": _couch(out, taken, yard, h)
			"dumpster": _dumpster(out, taken, yard, h)
			"lease": _lease(out, yard, h)
			"beds": _beds(out, taken, yard, h)
			"flag": _flag(out, yard, h)
			"planters": _planters(out, taken, yard, h)
	return out.filter(func(e): return e.item in show)


# ------------------------------------------------------------------ spots

## A footprint `size` (x, z before turning) centred at `at`, turned by yaw.
static func _rect(at: Vector2, size: Vector2, yaw: float) -> Rect2:
	var s := size if absf(sin(yaw)) < 0.7 else Vector2(size.y, size.x)
	return Rect2(at - s * 0.5, s)


## Whether a footprint is clear: on the lot (or its curb strip, for things
## put out at the curb), off the building, the drive (unless allowed), the
## parking stalls, the walk to the door and anything already placed.
static func _free(r: Rect2, yard: Dictionary, taken: Array, curb := false, on_drive := false) -> bool:
	var half: float = yard.half
	var front := -float(yard.to_curb) + 0.35 if curb else 0.3
	if r.position.x < -half + 0.2 or r.end.x > half - 0.2 or r.position.y < front or r.end.y > float(yard.depth) - 0.3:
		return false
	for m: Rect2 in yard.masses:
		if m.grow(0.35).intersects(r):
			return false
	var porch: Rect2 = yard.porch
	if porch.has_area() and porch.grow(0.3).intersects(r):
		return false
	if not on_drive and float(yard.drive_w) > 0.0:
		var dw: float = yard.drive_w
		var dz: float = float(yard.garage_z) if float(yard.garage_z) > 0.0 else float(yard.depth) * 0.5
		if Rect2(float(yard.drive_x) - dw * 0.5 - 0.2, -float(yard.to_curb), dw + 0.4, dz + float(yard.to_curb)).intersects(r):
			return false
	for s: Vector2 in yard.stalls:
		if Rect2(s - Vector2(1.5, 2.9), Vector2(3.0, 5.8)).intersects(r):
			return false
	var door: Vector2 = yard.door
	if Rect2(door.x - 0.8, -float(yard.to_curb), 1.6, door.y + float(yard.to_curb)).intersects(r):
		return false
	for t: Rect2 in taken:
		if t.intersects(r):
			return false
	return true


## Tries spots [at, yaw, may stand on the drive] in turn; places the first
## free one.
static func _first(out: Array, taken: Array, yard: Dictionary, name: String, spots: Array, h: int, col: Color,
		curb := false) -> bool:
	for s: Array in spots:
		var r := _rect(s[0], SIZE[name], s[1])
		if _free(r, yard, taken, curb, s.size() > 2 and bool(s[2])):
			taken.append(r)
			out.append({"item": name, "at": s[0], "yaw": s[1], "y": 0.0, "col": col, "v": posmod(h >> 8, 7)})
			return true
	return false


## Which way is out from the drive toward the lot's edge (1 or -1).
static func _outward(yard: Dictionary) -> float:
	var dx: float = yard.drive_x
	return 1.0 if dx >= 0.0 else -1.0


## Where carts and couches go at the curb: on the grass strip between the
## sidewalk and the curb where there is one, else just inside the lot.
static func _curb_z(yard: Dictionary) -> float:
	var tc: float = yard.to_curb
	return -tc + 0.95 if tc - 1.9 >= 1.2 else 0.85


static func _car(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := _outward(yard)
	var gz: float = yard.garage_z
	var fz: float = yard.front_z
	var tilt := (float(posmod(h, 17)) / 16.0 - 0.5) * 0.12
	# Beside the drive (on the side yard out toward the lot line, or the
	# front lawn next to it), nose to the house.
	var up := clampf(minf(gz if gz > 0.0 else fz, fz + 6.0) - 3.2, 3.0, 30.0)
	var spots := [[Vector2(dx + s * (dw * 0.5 + 1.45), up), PI + tilt]]
	for k in 4:
		spots.append([Vector2(dx - s * (dw * 0.5 + 1.45 + k * 1.1), 3.3), PI + tilt])
	if posmod(h, 3) == 0:
		spots.reverse()
	# On the drive in front of the garage: a one-car drive's apron, or the
	# bay of a wider one away from where the second car parks (the traffic
	# sim's drive stall, which _free keeps clear).
	if gz >= 6.0:
		var bays := int(yard.bays)
		var bay := dw / maxf(bays, 1)
		spots.append([Vector2(dx, gz - 3.1), PI + tilt * 0.3, true])
		if bays > 1:
			spots.append([Vector2(dx - (bays - 1) * 0.5 * bay, gz - 3.1), PI + tilt * 0.3, true])
	_first(out, taken, yard, "car_blocks", spots, h, OLD_PAINT[posmod(h, OLD_PAINT.size())])


static func _cans(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var z := _curb_z(yard)
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	var door: Vector2 = yard.door
	var spots := [
		[Vector2(dx + s * (dw * 0.5 + 1.5), z), 0.0],
		[Vector2(dx - s * (dw * 0.5 + 1.5), z), 0.0],
		[Vector2(door.x + s * 2.1, z), 0.0],
		[Vector2(door.x - s * 2.1, z), 0.0],
	]
	_first(out, taken, yard, "cans", spots, h, CARTS[posmod(h >> 3, CARTS.size())], true)


static func _couch(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var z := _curb_z(yard) + 0.05
	var door: Vector2 = yard.door
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	var tilt := (float(posmod(h, 13)) / 12.0 - 0.5) * 0.3
	var spots := [
		[Vector2(door.x + s * 3.2, z), tilt],
		[Vector2(door.x - s * 3.2, z), tilt],
		[Vector2(dx - s * (dw * 0.5 + 3.4), z), tilt],
		[Vector2(dx + s * (dw * 0.5 + 3.4), z), tilt],
	]
	if _first(out, taken, yard, "couch", spots, h, FABRIC[posmod(h >> 2, FABRIC.size())], true):
		# A third of them have the mattress out too, leaned on the couch's back.
		out[-1].v = 1 if posmod(h >> 5, 3) == 0 else 0


static func _dumpster(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var half: float = yard.half
	var depth: float = yard.depth
	var back := 0.0
	var front := INF
	for m: Rect2 in yard.masses:
		back = maxf(back, m.end.y)
		front = minf(front, m.position.y)
	var door: Vector2 = yard.door
	var spots := []
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	# Beside the building, back to the lot line and in sight of the street
	# where there is room; else at the edge of the lot out front, or behind
	# the building at a back corner.
	for side in [s, -s]:
		spots.append([Vector2(side * (half - 1.1), minf(front, depth) + 2.0), side * PI * 0.5])
		spots.append([Vector2(side * (half - 1.1), minf(front, depth) + 5.0), side * PI * 0.5])
	for side in [s, -s]:
		spots.append([Vector2(side * (half - 1.1), maxf(door.y - 3.0, 1.5)), side * PI * 0.5])
	for side in [s, -s]:
		spots.append([Vector2(side * (half - 1.1), minf(back + 1.8, depth - 1.8)), side * PI * 0.5])
		spots.append([Vector2(side * (half - 1.6), depth - 1.1), 0.0])
	_first(out, taken, yard, "dumpster", spots, h, STEEL[posmod(h >> 4, STEEL.size())])


## The mass whose front the door is in (or the nearest to it).
static func _front_mass(yard: Dictionary) -> Rect2:
	var door: Vector2 = yard.door
	var best := Rect2()
	var bd := INF
	for m: Rect2 in yard.masses:
		var dx := maxf(0.0, maxf(m.position.x - door.x, door.x - m.end.x))
		var d := dx + absf(m.position.y - door.y)
		if d < bd:
			bd = d
			best = m
	return best


static func _lease(out: Array, yard: Dictionary, h: int) -> void:
	var m := _front_mass(yard)
	if m.size.x < 3.6:
		return
	var door: Vector2 = yard.door
	# Across the boarded window beside the door, under the store's sign.
	# On the wider side of the door, off the glass and boards (which stand
	# a little proud of the building's footprint).
	var side := 1.0 if m.get_center().x >= door.x else -1.0
	var x := clampf(door.x + side * 2.65, m.position.x + 1.6, m.end.x - 1.6)
	out.append({"item": "lease", "at": Vector2(x, m.position.y - 0.22), "yaw": 0.0, "y": 0.0,
		"col": Color("#b3262d") if posmod(h >> 3, 3) != 0 else Color("#1f3d8a"), "v": 0})


## Flower beds: 1 m pieces of fresh mulch and annuals in front of the house's
## foundation bed, clear of the drive, the walk and the porch.
static func _beds(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var m := _front_mass(yard)
	if not m.has_area():
		return
	var fz: float = minf(float(yard.front_z), m.position.y)
	var porch: Rect2 = yard.porch
	var z := fz - 1.4 - 0.4
	var door: Vector2 = yard.door
	var dx: float = yard.drive_x
	var dw: float = yard.drive_w
	var col: Color = FLOWERS[posmod(h, FLOWERS.size())]
	var x := m.position.x + 0.6
	var n := 0
	while x < m.end.x - 0.5 and n < 10:
		var zz := z
		if porch.has_area() and x > porch.position.x - 0.6 and x < porch.end.x + 0.6:
			zz = minf(z, porch.position.y - 0.45)
		var r := Rect2(x - 0.5, zz - 0.35, 1.0, 0.7)
		var clear := absf(x - door.x) > 1.25 and (dw <= 0.0 or absf(x - dx) > dw * 0.5 + 0.8) and zz > 0.8
		if clear and _free(r, {"half": yard.half, "depth": yard.depth, "to_curb": yard.to_curb, "masses": yard.masses,
				"porch": Rect2(), "drive_w": 0.0, "stalls": [], "door": Vector2(9999, 0)}, taken):
			out.append({"item": "beds", "at": Vector2(x, zz), "yaw": 0.0, "y": 0.0, "col": col, "v": n})
			n += 1
		x += 1.0
	if n > 0:
		taken.append(Rect2(m.position.x, z - 0.4, m.size.x, 0.8))


## The flag on its bracket: on the porch's corner post where there is a
## porch, else on the wall beside the door.
static func _flag(out: Array, yard: Dictionary, h: int) -> void:
	var door: Vector2 = yard.door
	var porch: Rect2 = yard.porch
	var dx: float = yard.drive_x
	var away := -1.0 if dx >= door.x else 1.0  # the side of the door away from the drive
	var at := Vector2(door.x + away * 1.15, minf(float(yard.front_z), door.y) - 0.06)
	if porch.has_area():
		at = Vector2(porch.position.x + 0.2 if away < 0.0 else porch.end.x - 0.2, porch.position.y - 0.05)
	out.append({"item": "flag", "at": at, "yaw": away * 0.35, "y": 0.0, "col": Color.WHITE, "v": posmod(h, 2)})


static func _planters(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var door: Vector2 = yard.door
	var m := _front_mass(yard)
	var z := (m.position.y if m.has_area() else door.y) - 0.8
	var col: Color = FLOWERS[posmod(h, FLOWERS.size())]
	var free := {"half": yard.half, "depth": yard.depth, "to_curb": yard.to_curb, "masses": yard.masses,
		"porch": Rect2(), "drive_w": 0.0, "stalls": yard.stalls, "door": Vector2(9999, 0)}
	for s in [-1.0, 1.0]:
		var at := Vector2(door.x + s * 1.3, z)
		var r := _rect(at, SIZE.planter, 0.0)
		if yard.main_street:
			# Built to the sidewalk: the planters stand on the walk at the wall.
			free.to_curb = 3.0
			if _free(r, free, taken, true):
				taken.append(r)
				out.append({"item": "planters", "at": at, "yaw": 0.0, "y": 0.0, "col": col, "v": int(s > 0.0)})
		elif _free(r, free, taken):
			taken.append(r)
			out.append({"item": "planters", "at": at, "yaw": 0.0, "y": 0.0, "col": col, "v": int(s > 0.0)})
