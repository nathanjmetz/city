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
## drive, walk, garage, porch and building masses are, where cars park and
## drive, and where the public sidewalk runs. `masses`: the building's
## footprints as BuildingView drew them; `plan`: the house's own plan as
## its builder drew it (HouseBuilder.last_info, kept by BuildingView), walk
## and all. Without them (a headless test) the plan is read again from the
## builder (HouseBuilder.plan_info), which can't say which walk was drawn,
## so both are kept clear. `trees`: the trees on and around the lot, as
## BuildingView.trees_of gives them (world positions).
static func yard_of(sim, key: String, masses := [], plan := {}, trees := []) -> Dictionary:
	var b: Dictionary = sim.buildings[key]
	var lot: Dictionary = sim.lots[key]
	var type := BuildingTypes.type_of(b)
	var storeys := BuildingTypes.storeys(b)
	var fit := SiteLayout._fit(lot)
	var tc := float(lot.get("to_curb", 2.0))
	var y := {"kind": kind_of(b), "half": float(fit.half), "depth": float(fit.depth),
		"to_curb": tc, "door": Vector2(0.0, 0.4), "drive_x": 0.0, "drive_w": 0.0,
		"garage_z": -1.0, "front_z": 0.4, "porch": Rect2(), "main_street": false,
		"masses": masses.duplicate(), "keep_out": [], "bays": 0}
	y.trees = trees_in_frame(lot, trees)
	# The public sidewalk (as HouseBuilder._curb_cut lays it).
	var walk1 := -tc + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	y.sidewalk = Vector2(walk1 - RoadStyle.SIDEWALK_WIDTH, walk1)
	var keep: Array = y.keep_out
	if type == "house":
		var h: Dictionary = plan
		if h.is_empty():
			var r := RandomNumberGenerator.new()
			r.seed = int(b.seed)
			h = HouseBuilder.plan_info(r.randi(), fit.get("art", {"width": fit.half * 2.0, "depth": fit.depth}), storeys)
		var dx := float(h.drive_x)
		var dw := float(h.drive_w)
		var gz := float(h.get("garage_z", -1.0))
		var fz := float(h.front_z)
		var door_x := float(h.door_x)
		var walk_z := float(h.get("walk_z", fz - 1.9))
		y.drive_x = dx
		y.drive_w = dw
		y.garage_z = gz
		y.front_z = fz
		y.door = Vector2(door_x, fz)
		y.bays = 1 if dw < 4.5 else (2 if dw < 8.5 else 3)
		# The drive from the curb to the garage (and the apron of a detached
		# garage), where the household's cars park and drive in and out.
		var dz := gz + 0.5 if gz > 0.0 else fz + 6.0
		keep.append(Rect2(dx - dw * 0.5 - 0.25, -tc, dw + 0.5, dz + tc))
		if float(h.get("garage_w", 0.0)) > 0.0:
			var gx := float(h.garage_x)
			var ghw := float(h.garage_w) * 0.5
			var x0 := minf(gx - ghw, dx - dw * 0.5) - 0.25
			keep.append(Rect2(x0, gz - 4.75, maxf(gx + ghw, dx + dw * 0.5) + 0.25 - x0, 5.25))
		# The front walk: straight out to the sidewalk, or across to the drive.
		var walk: Variant = h.get("walk", null)
		if walk is Rect2:
			keep.append((walk as Rect2).grow(0.25))
		else:
			keep.append(Rect2(door_x - 0.6, -0.3, 1.2, walk_z + 0.3).grow(0.25))
			keep.append(Rect2(minf(door_x, dx) - 0.6, walk_z - 1.2, absf(door_x - dx) + 0.6, 1.2).grow(0.25))
		keep.append(Rect2(door_x - 0.85, walk_z - 0.25, 1.7, fz - walk_z + 0.25))  # steps to the door
		if h.get("porch", null) is Rect2:
			y.porch = h.porch
		if y.masses.is_empty() and h.has("x0"):
			y.masses = [Rect2(float(h.x0), fz, float(h.x1) - float(h.x0), 10.0)]
	else:
		# The layout the traffic already keeps for the lot (the stalls its cars
		# park in), read without touching it; else worked out (a dry run of
		# the shop's builder, the costly part of a yard plan).
		var lay: Dictionary = {}
		var ref := "lot:" + key
		var pl: Dictionary = sim.traffic.cached_place(ref) if sim.traffic != null else {}
		if pl.has("lay"):
			lay = pl.lay
		else:
			lay = SiteLayout.for_building(int(b.zone), int(b.seed), lot, storeys, type, int(b.get("level", 0)),
				sim.network, int(b.get("added_from", 0)))
		y.door = lay.door
		y.front_z = float(lay.door.y)
		y.drive_x = float(lay.cut_x)
		y.main_street = bool(lay.main_street)
		var door: Vector2 = lay.door
		y.door_walk = Rect2(door.x - 0.8, -tc, 1.6, door.y + tc)  # the walk in to the door
		keep.append(y.door_walk)
		var aisles := {}
		for s in lay.spots:
			if s.kind != "stall" and s.kind != "drive":
				continue
			var p: Vector2 = s.pos
			keep.append(Rect2(p - Vector2(1.5, 2.9), Vector2(3.0, 5.8)))
			aisles[snappedf(float(s.get("aisle", lay.aisle_z)), 0.5)] = true
		if not lay.main_street and (y.drive_x != 0.0 or not aisles.is_empty()):
			# The entrance drive (two lanes) from the street to the lot's
			# aisles, and each aisle across the lot.
			var top := float(lay.aisle_z)
			for a in aisles:
				top = maxf(top, float(a))
			if kind_of(b) == "home":
				y.drive_w = 3.0
				keep.append(Rect2(y.drive_x - 1.75, -tc, 3.5, maxf(top, 6.0) + tc))
			else:
				keep.append(Rect2(y.drive_x - 3.9, -tc, 7.8, top + 3.9 + tc))
				for a in aisles:
					keep.append(Rect2(-y.half, float(a) - 3.9, y.half * 2.0, 7.8))
	if y.masses.is_empty():
		# Not drawn (a headless test): the building as a block behind its door.
		var d: Vector2 = y.door
		var z0 := maxf(d.y, 0.5)
		y.masses = [Rect2(-y.half + 1.5, z0, y.half * 2.0 - 3.0, maxf(6.0, y.depth - z0 - 3.0))]
	return y


## The oldest a yard tree comes in (TreeField.YARD_PICKS): its crown is
## kept off things at the size it has then, or less if its room says so.
const CROWN_AGE := 56.0
## What a street tree's trunk (and its tree grate or mulch ring) keeps clear.
const TRUNK_CLEAR := 0.7


## How far a tree's crown reaches, at most, from its trunk (m): a home's
## yard tree (one with room to spread, HouseBuilder._yard_room) as far as
## its room lets it grow by the oldest age a grown yard comes in with
## (TreeField.yard_age), another (a street tree, still growing) only its
## trunk's clearance.
static func crown_reach(sp: int, size: float, room: float) -> float:
	if room < 0.0:
		return TRUNK_CLEAR
	return maxf(TreeField.SPREAD[sp] * size * minf(room, TreeKinds.size_at(sp, CROWN_AGE)), TRUNK_CLEAR)


## Trees (BuildingView.trees_of's world entries) as [Vector2 in the lot's
## frame, how far its crown keeps things off].
static func trees_in_frame(lot: Dictionary, trees: Array) -> Array:
	var inv := SiteLayout.frame(lot).affine_inverse()
	var out := []
	for t: Array in trees:
		var q := inv * (t[0] as Vector3)
		out.append([Vector2(q.x, q.z), crown_reach(int(t[1]), float(t[2]), float(t[3]))])
	return out


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

## Where a prop reaches on the ground at `at`, turned by `yaw`: its mesh's
## whole footprint (the wheel lying by the car, the mattress behind the
## couch, the lid flung open behind the dumpster), as an upright rectangle.
static func footprint(name: String, at: Vector2, yaw: float) -> Rect2:
	var box := StateMeshes.of(name).get_aabb()
	var b := Basis(Vector3.UP, yaw)
	var r := Rect2()
	for k in 4:
		var c := b * Vector3(box.position.x + (box.size.x if k & 1 else 0.0), 0.0,
			box.position.z + (box.size.z if k & 2 else 0.0))
		var p := at + Vector2(c.x, c.z)
		r = Rect2(p, Vector2.ZERO) if k == 0 else r.expand(p)
	return r


## Whether a footprint is clear: on the lot (or, for things put out at the
## curb, on the grass strip between the curb and the sidewalk), never on the
## public sidewalk, off the building, the porch, the drive, the walk, the
## parking and its lanes, and anything already placed.
static func _free(r: Rect2, yard: Dictionary, taken: Array, curb := false, on_sidewalk := false) -> bool:
	var half: float = yard.half
	var front := -float(yard.to_curb) + RoadStyle.CURB_WIDTH + 0.1 if curb else 0.3
	if r.position.x < -half + 0.2 or r.end.x > half - 0.2 or r.position.y < front or r.end.y > float(yard.depth) - 0.3:
		return false
	var sw: Vector2 = yard.sidewalk
	if not on_sidewalk and r.end.y > sw.x - 0.05 and r.position.y < sw.y + 0.05:
		return false
	for m: Rect2 in yard.masses:
		if m.grow(0.35).intersects(r):
			return false
	var porch: Rect2 = yard.porch
	if porch.has_area() and porch.grow(0.3).intersects(r):
		return false
	for k: Rect2 in yard.keep_out:
		if k.intersects(r):
			return false
	# Not under a yard tree's crown, nor up against a street tree's trunk.
	for t: Array in yard.get("trees", []):
		var c: Vector2 = t[0]
		if c.distance_to(c.clamp(r.position, r.end)) < float(t[1]):
			return false
	for t: Rect2 in taken:
		if t.intersects(r):
			return false
	return true


## Tries spots [at, yaw] in turn; places the first free one.
static func _first(out: Array, taken: Array, yard: Dictionary, name: String, spots: Array, h: int, col: Color,
		curb := false) -> bool:
	for s: Array in spots:
		var r := footprint(name, s[0], s[1])
		if _free(r, yard, taken, curb):
			taken.append(r)
			out.append({"item": name, "at": s[0], "yaw": s[1], "y": 0.0, "col": col, "v": posmod(h >> 8, 7)})
			return true
	return false


## Which way is out from the drive toward the lot's edge (1 or -1).
static func _outward(yard: Dictionary) -> float:
	var dx: float = yard.drive_x
	return 1.0 if dx >= 0.0 else -1.0


## Where something put out at the curb stands, z of its middle: on the grass
## strip between the curb and the sidewalk if it fits there, else on the lawn
## just behind the sidewalk.
static func _curb_spot(yard: Dictionary, name: String, yaw: float) -> Array:
	var f := footprint(name, Vector2.ZERO, yaw)
	var tc: float = yard.to_curb
	var sw: Vector2 = yard.sidewalk
	var out := []
	var strip0 := -tc + RoadStyle.CURB_WIDTH + 0.15
	if sw.x - 0.1 - strip0 >= f.size.y:
		out.append(strip0 - f.position.y)
	out.append(maxf(sw.y + 0.15, 0.35) - f.position.y)
	return out


static func _car(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := _outward(yard)
	var gz: float = yard.garage_z
	var fz: float = yard.front_z
	var tilt := (float(posmod(h, 17)) / 16.0 - 0.5) * 0.12
	# Never on the drive (the household's cars park and drive there): on the
	# side yard beside it out toward the lot line, up by the garage or
	# alongside it, or out on the front lawn clear of the walk.
	var up := clampf(minf(gz if gz > 0.0 else fz, fz + 6.0) - 3.2, 3.0, 30.0)
	var spots := []
	var places := [Vector2(dx + s * (dw * 0.5 + 1.6), up), Vector2(dx + s * (dw * 0.5 + 1.6), up + 3.5)]
	if gz > 0.0:
		places.append(Vector2(dx + s * (dw * 0.5 + 1.6), gz + 2.5))
	# Else somewhere on the front lawn, short of the walk across it.
	var lawn := 0.35 + 2.5
	var half: float = yard.half
	var x := -half + 1.8
	var lawn_spots := []
	while x < half - 1.8:
		lawn_spots.append(Vector2(x, lawn))
		x += 1.0
	if not lawn_spots.is_empty():
		var k0 := posmod(h >> 4, lawn_spots.size())
		places.append_array(lawn_spots.slice(k0) + lawn_spots.slice(0, k0))
	for p in places:
		# Nose to the house or to the street, whichever leaves the loose
		# wheel on the grass.
		spots.append([p, PI + tilt])
		spots.append([p, tilt])
	_first(out, taken, yard, "car_blocks", spots, h, OLD_PAINT[posmod(h, OLD_PAINT.size())])


static func _cans(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	var door: Vector2 = yard.door
	var spots := []
	for z in _curb_spot(yard, "cans", 0.0):
		for x in [dx + s * (dw * 0.5 + 1.6), dx - s * (dw * 0.5 + 1.6), door.x + s * 2.3, door.x - s * 2.3]:
			spots.append([Vector2(x, z), 0.0])
	_first(out, taken, yard, "cans", spots, h, CARTS[posmod(h >> 3, CARTS.size())], true)


static func _couch(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var door: Vector2 = yard.door
	var dx: float = yard.drive_x
	var dw: float = maxf(float(yard.drive_w), 2.8)
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	var tilt := (float(posmod(h, 13)) / 12.0 - 0.5) * 0.3
	var spots := []
	# Its footprint counts the mattress leaned on its back whether or not
	# this one has it out, so a couch never moves when one turns up.
	for z in _curb_spot(yard, "couch", tilt):
		for x in [door.x + s * 3.4, door.x - s * 3.4, dx - s * (dw * 0.5 + 3.6), dx + s * (dw * 0.5 + 3.6)]:
			spots.append([Vector2(x, z), tilt])
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
	front = minf(front, depth)
	var spots := []
	var s := 1.0 if posmod(h, 2) == 0 else -1.0
	# On a pad beside the building, back to the side lot line, or behind it
	# at a back corner; never out front, on the drive or the parking.
	for side in [s, -s]:
		var yaw: float = side * PI * 0.5
		var w := footprint("dumpster", Vector2.ZERO, yaw)
		var x: float = side * (half - 0.3) - (w.end.x if side > 0.0 else w.position.x)
		for z in [front + 2.0, front + 5.0, (front + back) * 0.5, back - 1.5]:
			spots.append([Vector2(x, z), yaw])
	for side in [s, -s]:
		var w := footprint("dumpster", Vector2.ZERO, 0.0)
		spots.append([Vector2(side * (half - 0.3) - (w.end.x if side > 0.0 else w.position.x), depth - 0.4 - w.end.y), 0.0])
		var yaw: float = side * PI * 0.5
		var w2 := footprint("dumpster", Vector2.ZERO, yaw)
		spots.append([Vector2(side * (half - 0.3) - (w2.end.x if side > 0.0 else w2.position.x), minf(back + 1.8, depth - 1.8)), yaw])
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
	# Across the boarded window beside the door, under the store's sign, on
	# the wider side of the door, off the glass and boards (which stand a
	# little proud of the building's footprint).
	var side := 1.0 if m.get_center().x >= door.x else -1.0
	var x := clampf(door.x + side * 2.65, m.position.x + 1.6, m.end.x - 1.6)
	out.append({"item": "lease", "at": Vector2(x, m.position.y - 0.22), "yaw": 0.0, "y": 0.0,
		"col": Color("#b3262d") if posmod(h >> 3, 3) != 0 else Color("#1f3d8a"), "v": 0})


## Flower beds: 1 m pieces of fresh mulch and annuals in front of the house's
## foundation bed, clear of the drive, the walk, the steps and the porch.
static func _beds(out: Array, taken: Array, yard: Dictionary, h: int) -> void:
	var m := _front_mass(yard)
	if not m.has_area():
		return
	var fz: float = minf(float(yard.front_z), m.position.y)
	var porch: Rect2 = yard.porch
	var z := fz - 1.4 - 0.45
	var col: Color = FLOWERS[posmod(h, FLOWERS.size())]
	var x := m.position.x + 0.6
	var n := 0
	var placed := []
	while x < m.end.x - 0.5 and n < 10:
		var zz := z
		if porch.has_area() and x > porch.position.x - 0.6 and x < porch.end.x + 0.6:
			zz = minf(z, porch.position.y - 0.5)
		var at := Vector2(x, zz)
		var r := footprint("beds", at, 0.0)
		if zz > 0.8 and _free(r, yard, taken):
			out.append({"item": "beds", "at": at, "yaw": 0.0, "y": 0.0, "col": col, "v": n})
			placed.append(r)
			n += 1
		x += 1.0
	taken.append_array(placed)


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
	var col: Color = FLOWERS[posmod(h, FLOWERS.size())]
	var f := footprint("planters", Vector2.ZERO, 0.0)
	var z := (m.position.y if m.has_area() else door.y) - 0.4 - f.end.y
	# The walk in to the door stays open between them.
	var free: Dictionary = yard.duplicate()
	var walk: Rect2 = yard.get("door_walk", Rect2())
	free.keep_out = (yard.keep_out as Array).filter(func(k: Rect2): return k != walk)
	for s in [-1.0, 1.0]:
		var at := Vector2(door.x + s * 1.35, z)
		var r := footprint("planters", at, 0.0)
		# A shop built to the sidewalk has them on the walk, at its wall.
		if _free(r, free, taken, yard.main_street, yard.main_street):
			taken.append(r)
			out.append({"item": "planters", "at": at, "yaw": 0.0, "y": 0.0, "col": col, "v": int(s > 0.0)})
