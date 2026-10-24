class_name WaterUtility
extends RefCounted
## The town water and sewer utility, Brawn's hub-with-a-leader model
## (2026-10-22): the player places the utility and sets its subsidy, and its
## superintendent runs it like a small business. They lay water mains and
## sewers under the streets toward zoned lots, drill wells, put up a tower,
## and climb a development tree (filtration, a sewage lagoon then a modern
## plant, smart meters, selling water to the next town, biosolids for farms).
##
## The manager's education follows the town's schools. An educated, funded
## manager keeps everything in good repair and builds the modern options; a
## starved one lets condition slide into boil-water notices and a smelly
## sewer plant that drags down land value nearby.
##
## Works grow only into free land right next to the utility (no second
## sites), and pipes go under existing streets, so it never touches anything
## the player built. Deterministic: no randomness after the manager is hired.

## One piece of the utility's yard (a well, the tower, a plant), square.
const CELL := 40.0
## Most pieces the yard grows to.
const MAX_CELLS := 14
const DECIDE_EVERY := Balance.WATER_DECIDE_EVERY
## Game months per decision (a game day settles a month).
const STEP_MONTHS := float(Balance.WATER_DECIDE_EVERY) / (24.0 * 60.0)
## Pipe locations are kept as points this far apart, hashed to cells this big,
## so mains survive roads being split or rebuilt along the same line.
const PIPE_STEP := 4.0
const PIPE_HASH := 4.0

## Names of everything the utility can put up or take on, and whether it
## takes a piece of the yard. Wells and towers are added as demand grows;
## the rest is the development tree below. Numbers are in Balance.WATER_WORKS.
const NAMES := {
	"well": {"name": "Well and pump house", "yard": true},
	"tower": {"name": "Elevated water tower", "yard": true},
	"filtration": {"name": "Iron filtration plant", "yard": true},
	"intake": {"name": "River intake and treatment plant", "yard": true},
	"lagoon": {"name": "Sewage lagoon", "yard": true},
	"plant": {"name": "Activated sludge plant", "yard": false},
	"nutrient": {"name": "Nutrient removal and UV", "yard": false},
	"meters": {"name": "Smart meters", "yard": false},
	"training": {"name": "Operator training center", "yard": true},
	"industrial_main": {"name": "Big main to industry", "yard": false},
	"wholesale": {"name": "Interconnect with the next town", "yard": true},
	"biosolids": {"name": "Biosolids for farms", "yard": false},
	"reuse": {"name": "Reclaimed water for farms", "yard": true},
}
const W := Balance.WATER_WORKS
## The development tree in the shared Agency format (scripts/sim/agency.gd):
## what each step needs from the manager, the town and its neighbours. Some
## also need things on the ground (two wells, the river, factories on its
## mains); see _locked.
const TREE := [
	{"id": "lagoon", "name": "Sewage lagoon", "cost": W.lagoon.cost, "needs": {},
		"note": "the town's first sewers drain to it"},
	{"id": "filtration", "name": "Iron filtration plant", "cost": W.filtration.cost,
		"needs": {"leader_edu": W.filtration.edu}, "note": "takes the iron out of the well water"},
	{"id": "meters", "name": "Smart meters", "cost": W.meters.cost, "needs": {"leader_edu": W.meters.edu},
		"note": "finds leaks and slow meters"},
	{"id": "industrial_main", "name": "Big main to industry", "cost": W.industrial_main.cost,
		"needs": {"leader_edu": W.industrial_main.edu}, "note": "plants pay a large-meter rate"},
	{"id": "plant", "name": "Activated sludge plant", "cost": W.plant.cost, "requires": ["lagoon"],
		"needs": {"leader_edu": W.plant.edu}, "note": "a modern plant where the lagoon was"},
	{"id": "training", "name": "Operator training center", "cost": W.training.cost,
		"needs": {"leader_edu": W.training.edu, "population": 2_000}, "note": "certified operators, a sharper staff"},
	{"id": "wholesale", "name": "Interconnect with the next town", "cost": W.wholesale.cost,
		"needs": {"leader_edu": W.wholesale.edu, "link": 1}, "note": "buys or sells water with the neighbours"},
	{"id": "biosolids", "name": "Biosolids for farms", "cost": W.biosolids.cost, "requires": ["plant"],
		"needs": {"leader_edu": W.biosolids.edu, "local:farm": 1}, "note": "farms take the sludge as fertilizer"},
	{"id": "nutrient", "name": "Nutrient removal and UV", "cost": W.nutrient.cost, "requires": ["plant"],
		"needs": {"leader_edu": W.nutrient.edu, "education": 0.4}, "note": "clean water back to the river, no smell"},
	{"id": "intake", "name": "River intake and treatment plant", "cost": W.intake.cost, "requires": ["filtration"],
		"needs": {"leader_edu": W.intake.edu, "population": 8_000}, "note": "draws from the White River"},
	{"id": "reuse", "name": "Reclaimed water for farms", "cost": W.reuse.cost, "requires": ["plant"],
		"needs": {"leader_edu": W.reuse.edu, "local:farm": 1}, "note": "treated water sold for irrigation"},
]

const FIRST := ["Ruth", "Dale", "Marcy", "Gene", "Linda", "Wayne", "Deb", "Curtis", "Joyce", "Roger",
	"Pam", "Larry", "Sherry", "Doug", "Carol", "Ron"]
const LAST := ["Hollis", "Brenner", "Kemper", "Stoltz", "Ashby", "Mullins", "Fenwick", "Gaither",
	"Ralston", "Yoder", "Tilford", "Hessler", "McCurdy", "Purcell", "Lindquist", "Overby"]

## Utilities by their service building id: {name, leader (Agency.leader:
## edu, caution, ambition), built (tree node ids, Agency), subsidy, cash,
## cond, works: [[key, Vector2i]] (yard pieces: wells, towers, plants),
## mains, sewers (Arrays of PackedVector2Array), boil, odor, last, returned}
var utilities := {}
## Worked out by Services.update, not saved: id -> {mains: {seg: true},
## sewers: {seg: true}, load, sewer_load, fees, water_cap, sewer_cap, homes}
var live := {}
var _hash := {}  # id -> {"w": {Vector2i: true}, "s": {...}}


## Hires a manager and opens the utility at service building `id`, with a
## main under its own street.
func found(sim: CitySim, id: int) -> void:
	var b: Dictionary = sim.services.buildings[id]
	var network := sim.network
	var h := absi(hash([sim.city_seed, id, "water"]))
	utilities[id] = {"name": "%s %s" % [FIRST[h % FIRST.size()], LAST[(h / 16) % LAST.size()]],
		"leader": Agency.leader(sim, h), "built": [], "subsidy": Balance.WATER_SUBSIDY.start,
		"cash": float(Balance.WATER_UTILITY.start_cash), "cond": 1.0, "works": [["well", Vector2i.ZERO]],
		"mains": [], "sewers": [], "boil": false, "odor": 0.0, "last": "Opened with its first well", "returned": 0,
		"taps": 0, "sewer_taps": 0, "rate": 1.0}
	var near := network.find_segment_near(b.pos + b.dir * Services.KINDS[b.kind].size.y * 0.5, 80.0, 1.0)
	if not near.is_empty():
		_lay(id, "mains", network, near.seg)


func has_work(id: int, key: String) -> bool:
	if key in utilities[id].built:
		return true
	for w in utilities[id].works:
		if w[0] == key:
			return true
	return false


func count_work(id: int, key: String) -> int:
	var n := 0
	for w in utilities[id].works:
		if w[0] == key:
			n += 1
	return n


## Homes' worth of water the utility can deliver: its wells (or intake),
## held back by storage until it has a tower.
func water_capacity(id: int) -> int:
	var w: Dictionary = Balance.WATER_WORKS
	var supply: int = count_work(id, "well") * int(w.well.capacity) + count_work(id, "intake") * int(w.intake.capacity)
	var storage: int = Balance.WATER_STORAGE_NO_TOWER + count_work(id, "tower") * int(w.tower.capacity)
	return mini(supply, storage)


func sewer_capacity(id: int) -> int:
	if "plant" in utilities[id].built:
		return int(Balance.WATER_WORKS.plant.capacity)
	return int(Balance.WATER_WORKS.lagoon.capacity) if "lagoon" in utilities[id].built else 0


## Running costs a month: staff, every piece of the tree, and the pipes.
func monthly_cost(id: int) -> float:
	var u: Dictionary = utilities[id]
	var total: float = Balance.WATER_STAFF.base + Balance.WATER_STAFF.per_home * float(live.get(id, {}).get("load", 0))
	for w in u.works:
		if w[0] in ["well", "tower"]:
			total += float(Balance.WATER_WORKS[w[0]].upkeep)
	for key in u.built:
		total += float(Balance.WATER_WORKS[key].upkeep)
	total += (_length(u.mains) + _length(u.sewers)) * Balance.WATER_PIPE_UPKEEP_PER_M
	return total


## What the city pays every utility, a month.
func monthly_subsidy() -> int:
	var total := 0
	for id in utilities:
		total += int(utilities[id].subsidy)
	return total


func set_subsidy(id: int, amount: int) -> bool:
	if not utilities.has(id):
		return false
	amount = clampi(amount, 0, int(Balance.WATER_SUBSIDY.max))
	if amount == int(utilities[id].subsidy):
		return false
	utilities[id].subsidy = amount
	return true


# --- Pipes ---------------------------------------------------------------------

## Which utility's main runs under this road segment, or -1. Call refresh()
## after roads change.
func main_owner(seg: int) -> int:
	for id in _sorted_ids():
		if live.has(id) and live[id].mains.has(seg):
			return id
	return -1


## Works out which street segments carry each utility's mains and sewers.
func refresh(network: RoadNetwork) -> void:
	for id in _sorted_ids():
		if not _hash.has(id):
			_rehash(id)
		var l: Dictionary = live.get(id, {})
		l.mains = {}
		l.sewers = {}
		for seg in network.segments:
			var pts := network.sample_segment(seg, 8)
			if _on(_hash[id].w, pts):
				l.mains[seg] = true
				if _on(_hash[id].s, pts):
					l.sewers[seg] = true
		for k in ["load", "sewer_load", "fees", "homes", "homes_eq", "bought"]:
			if not l.has(k):
				l[k] = 0
		live[id] = l


static func _on(cells: Dictionary, pts: PackedVector3Array) -> bool:
	if cells.is_empty():
		return false
	for i in [2, 4, 6]:
		var c := Vector2i(floori(pts[i].x / PIPE_HASH), floori(pts[i].z / PIPE_HASH))
		var hit := false
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				hit = hit or cells.has(c + Vector2i(dx, dz))
		if not hit:
			return false
	return true


func _lay(id: int, kind: String, network: RoadNetwork, seg: int) -> void:
	var line := PackedVector2Array()
	var pts := network.sample_segment(seg, 16)
	var total := RoadNetwork.polyline_length(pts)
	var n := maxi(2, ceili(total / PIPE_STEP) + 1)
	var walked := 0.0
	var i := 0
	for k in n:
		var want := total * k / (n - 1)
		while i < pts.size() - 2 and walked + pts[i].distance_to(pts[i + 1]) < want:
			walked += pts[i].distance_to(pts[i + 1])
			i += 1
		var seg_len := maxf(pts[i].distance_to(pts[i + 1]), 0.001)
		var p := pts[i].lerp(pts[i + 1], clampf((want - walked) / seg_len, 0.0, 1.0))
		line.append(Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))
	utilities[id][kind].append(line)
	_add_hash(id, "w" if kind == "mains" else "s", line)
	if not live.has(id):
		live[id] = {"mains": {}, "sewers": {}, "load": 0, "sewer_load": 0, "fees": 0, "homes": 0, "homes_eq": 0, "bought": 0}
	live[id][kind][seg] = true


func _rehash(id: int) -> void:
	_hash[id] = {"w": {}, "s": {}}
	for line in utilities[id].mains:
		_add_hash(id, "w", line)
	for line in utilities[id].sewers:
		_add_hash(id, "s", line)


func _add_hash(id: int, k: String, line: PackedVector2Array) -> void:
	if not _hash.has(id):
		_hash[id] = {"w": {}, "s": {}}
	for p in line:
		_hash[id][k][Vector2i(floori(p.x / PIPE_HASH), floori(p.y / PIPE_HASH))] = true


static func _length(lines: Array) -> float:
	var total := 0.0
	for line in lines:
		for i in line.size() - 1:
			total += line[i].distance_to(line[i + 1])
	return total


# --- The yard --------------------------------------------------------------------

static func _right(b: Dictionary) -> Vector3:
	return Vector3(-b.dir.z, 0.0, b.dir.x)


## The middle of a yard piece; (0, 0) is the office and first well, +y runs
## away from the street.
static func cell_center(b: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = b.pos + _right(b) * (c.x * CELL) - b.dir * (c.y * CELL)
	return Vector3(p.x, 0.0, p.z)


static func cell_corners(b: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := cell_center(b, c)
	var r: Vector3 = _right(b) * CELL * 0.5
	var k: Vector3 = -b.dir * CELL * 0.5
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * s.x + k * s.y
		out.append(Vector2(p.x, p.z))
	return out


## The yard piece under a point: [utility id, index in works], or [].
func work_at(buildings: Dictionary, p: Vector3) -> Array:
	var q := Vector2(p.x, p.z)
	for id in _sorted_ids():
		if not buildings.has(id):
			continue
		var works: Array = utilities[id].works
		for i in works.size():
			var c: Vector2i = works[i][1]
			if c != Vector2i.ZERO and c.x > -99 and Geometry2D.is_point_in_polygon(q, cell_corners(buildings[id], c)):
				return [id, i]
	return []


## Free yard cells right next to what the utility has, nearest the office first.
func _frontier(id: int) -> Array:
	var have := {}
	for w in utilities[id].works:
		if w[1].x > -99:
			have[w[1]] = true
	have[Vector2i.ZERO] = true
	var out := {}
	for c in have:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if n.y >= 0 and not have.has(n):
				out[n] = true
	var list := out.keys()
	list.sort_custom(func(a, b):
		var da: int = a.y * 3 + absi(a.x) * 2
		var db: int = b.y * 3 + absi(b.x) * 2
		return da < db if da != db else (a.x < b.x if a.x != b.x else a.y < b.y))
	return list


func _yard_count(id: int) -> int:
	var n := 0
	for w in utilities[id].works:
		if w[1].x > -99:
			n += 1
	return n


# --- The manager's step -----------------------------------------------------------

## Each utility collects its bills and subsidy, pays its running costs and
## repairs, then takes on at most one piece of the tree and lays pipe with
## what it can spare. `usable(corners)` says whether yard land is free.
## Returns [changed, money back to the city].
func decide(sim: CitySim, usable: Callable) -> Array:
	var changed := false
	var returned := 0
	var buildings: Dictionary = sim.services.buildings
	var edu_town := town_education(sim)
	for id in _sorted_ids():
		if not buildings.has(id) or not live.has(id):
			continue
		var u: Dictionary = utilities[id]
		var l: Dictionary = live[id]
		var b: Dictionary = buildings[id]
		# A road the player built through the yard takes that piece with it.
		for i in range(u.works.size() - 1, -1, -1):
			var c: Vector2i = u.works[i][1]
			if c != Vector2i.ZERO and c.x > -99 and Services.road_clash(sim.network, cell_corners(b, c)):
				u.works.remove_at(i)
				changed = true
		# The manager's schooling follows the leaders the town can hire.
		var target: float = edu_town
		if has_work(id, "training"):
			target += Balance.WATER_EDU.training
		u.leader.edu = clampf(float(u.leader.edu) + (target - float(u.leader.edu)) * Balance.WATER_EDU.drift, 0.0, 1.0)
		# The player's word to the manager (Permits guidance): grow, their own
		# call, or hold off building.
		var stance := str(sim.permits.guidance("water", id).stance)
		var ambition: float = clampf(u.leader.ambition + (0.5 if stance == "grow" else 0.0), 0.0, 1.0)
		# Tap fees: each new hookup pays once for its share of the system.
		var taps := int(l.homes_eq)
		var sewer_taps := int(l.sewer_load)
		if taps > int(u.taps):
			u.cash += (taps - int(u.taps)) * Balance.WATER_TAP_FEE
		if sewer_taps > int(u.sewer_taps):
			u.cash += (sewer_taps - int(u.sewer_taps)) * Balance.SEWER_TAP_FEE
		u.taps = maxi(int(u.taps), taps)
		u.sewer_taps = maxi(int(u.sewer_taps), sewer_taps)
		# Water traded with the neighbours last month. The region books it to
		# the city's account, so the utility settles up with the city.
		var traded := trade_money(sim)
		u.cash += traded * STEP_MONTHS
		returned -= roundi(traded * STEP_MONTHS)
		# Money in and out.
		var cost := monthly_cost(id)
		var income := float(l.fees) + float(u.subsidy) + other_income(sim, id)
		if u.cash < 0.0:
			cost += -u.cash * Balance.WATER_INTEREST
		u.cash += (income - cost) * STEP_MONTHS
		# The manager sets the rate to cover costs, like a rate case.
		var r: Dictionary = Balance.WATER_RATE
		if income < cost * (1.0 + Balance.WATER_MAINT.share) and u.cash < 0.0:
			u.rate = minf(r.max, float(u.rate) + r.step)
		elif u.cash > cost * Balance.WATER_SURPLUS_MONTHS * 0.5:
			u.rate = maxf(r.min, float(u.rate) - r.step)
		u.rate = snappedf(u.rate, 0.01)
		# Repairs: what it pays decides how good a shape it can keep things in.
		var floor_cash := cash_floor(id)
		var need: float = Balance.WATER_MAINT.share * cost * STEP_MONTHS * (1.5 - 0.5 * u.leader.edu)
		var pay := clampf(u.cash - floor_cash, 0.0, need)
		u.cash -= pay
		var paid := pay / maxf(need, 1.0)
		var keep: float = paid * lerpf(Balance.WATER_MAINT.low, 1.0, u.leader.edu)
		if l.load > water_capacity(id):
			keep -= 0.2
		if has_work(id, "filtration") or has_work(id, "intake"):
			keep += 0.05
		u.cond = clampf(u.cond + (clampf(keep, 0.0, 1.0) - u.cond) * Balance.WATER_MAINT.speed, 0.0, 1.0)
		var was_boil: bool = u.boil
		u.boil = u.cond < Balance.WATER_BOIL_AT or l.load > water_capacity(id) * 1.05
		var odor := 0.0
		if has_work(id, "lagoon") or has_work(id, "plant"):
			odor = (0.35 if not has_work(id, "plant") else 0.0) * (1.0 - u.cond) + maxf(0.0, 0.6 - u.cond)
			if l.sewer_load > sewer_capacity(id):
				odor += 0.4
			if has_work(id, "nutrient"):
				odor *= 0.2
		changed = changed or was_boil != u.boil or absf(odor - u.odor) > 0.05
		u.odor = snappedf(clampf(odor, 0.0, 1.0), 0.001)
		u.cond = snappedf(u.cond, 0.0001)
		u.leader.edu = snappedf(u.leader.edu, 0.0001)
		# One project from the tree, if it can afford it.
		var reserve: float = cost * (Balance.WATER_RESERVE_MONTHS + 2.0 * u.leader.caution)
		var project := next_project(sim, id) if stance != "hold" else ""
		if project != "":
			var price := project_cost(project)
			if affords(id, price, cost):
				if _build(sim, id, project, usable):
					u.cash -= price
					var note: String = _node(project).get("note", "")
					u.last = "%s built %s%s" % ["Its manager" if float(u.leader.edu) < 0.5 else "Its college-trained manager",
						NAMES[project].name.to_lower(), (": " + note) if note != "" else ""]
					changed = true
		# Pipe toward zoned lots with whatever is left over.
		if stance != "hold":
			changed = _extend(sim, id, floor_cash + reserve * 0.5, ambition) or changed
		_post_trade(sim, id)
		# A healthy surplus goes back to the town (a transfer to the general fund).
		var surplus: float = u.cash - cost * Balance.WATER_SURPLUS_MONTHS - 500_000.0
		if surplus > 0.0 and project == "":
			var give := roundi(surplus * 0.5)
			u.cash -= give
			u.returned += give
			returned += give
		u.cash = roundf(u.cash)
	return [changed, returned]


## True when the utility can pay `price` from its own money and keep its
## reserve (the manager's own rule for building). `monthly`: its costs a
## month, interest included (worked out when left out).
func affords(id: int, price: float, monthly := -1.0) -> bool:
	var u: Dictionary = utilities[id]
	if monthly < 0.0:
		monthly = monthly_cost(id) + maxf(0.0, -float(u.cash)) * Balance.WATER_INTEREST
	var reserve: float = monthly * (Balance.WATER_RESERVE_MONTHS + 2.0 * u.leader.caution)
	return u.cash - price >= cash_floor(id) + reserve * 0.5


## The utility's next step to deliver more water (a well, the river intake,
## or a tower), whatever it can afford; "" when it can't grow at all.
func supply_step(sim: CitySim, id: int) -> String:
	var ok := func(key: String) -> bool:
		return (key in ["well", "tower"] or not key in utilities[id].built) and _locked(sim, id, key) == ""
	var supply := count_work(id, "well") * int(Balance.WATER_WORKS.well.capacity) + count_work(id, "intake") * int(Balance.WATER_WORKS.intake.capacity)
	if supply > water_capacity(id) and ok.call("tower"):
		return "tower"
	for key in ["well", "intake", "tower"]:
		if ok.call(key):
			return key
	return ""


## What a step costs the utility after grants.
static func project_cost(key: String) -> float:
	var price := float(Balance.WATER_WORKS[key].cost)
	if key in ["lagoon", "plant", "nutrient", "filtration", "intake"]:
		price *= 1.0 - Balance.WATER_GRANT_SHARE
	return price


## The deepest it can go into debt to build (revenue bonds and state
## revolving fund loans, repaid from bills): educated managers borrow more.
func cash_floor(id: int) -> float:
	var u: Dictionary = utilities[id]
	var monthly := float(live.get(id, {}).get("fees", 0)) + float(u.subsidy)
	return -float(Balance.WATER_BOND_MONTHS) * monthly * (0.3 + 0.7 * u.leader.edu)


## Money from the farms' side of the tree, a month.
func other_income(sim: CitySim, id: int) -> float:
	var total := 0.0
	if has_work(id, "reuse"):
		total += farms_near(sim, id) * Balance.WATER_REUSE_PER_FARM
	return total


## Homes' worth of spare water it offers the region through its
## interconnect (half its spare capacity, up to a cap).
func wholesale_homes(id: int) -> int:
	if not has_work(id, "wholesale"):
		return 0
	var spare := water_capacity(id) - int(live.get(id, {}).get("load", 0)) + int(live.get(id, {}).get("bought", 0))
	return clampi(spare / 2, 0, Balance.WATER_WHOLESALE_MAX)


## Homes' worth of water it needs from the region: what it can't make itself.
func shortfall(id: int) -> int:
	if not has_work(id, "wholesale"):
		return 0
	return maxi(0, int(live.get(id, {}).get("load", 0)) - int(live.get(id, {}).get("bought", 0)) - water_capacity(id))


## Tells the region what water the town's utilities can spare or need, in
## thousand gallons a month. The region settles it monthly.
## Only the net is posted, so the town is either selling or buying.
func _post_trade(sim: CitySim, _id: int) -> void:
	var net := 0
	var first := -1
	for id in _sorted_ids():
		net += wholesale_homes(id) - shortfall(id)
		if first == -1 and has_work(id, "wholesale"):
			first = id
	var kgal: float = Balance.WATER_KGAL_PER_HOME
	sim.trade.offer("water", net * kgal)
	sim.trade.want("water", -net * kgal)
	# What came in last month counts as supply for the utility that asked.
	if first != -1:
		live[first].bought = floori(sim.trade.got("water") / kgal)


## Last month's water sales less purchases, dollars (the region books them
## to the city's account).
static func trade_money(sim: CitySim) -> float:
	var total := 0.0
	for d in sim.trade.last_deals:
		if d.good == "water":
			total += float(d.amount) * float(d.price)
	return total if sim.trade.sold("water") > 0.0 else -total


func farms_near(sim: CitySim, id: int) -> int:
	var b: Dictionary = sim.services.buildings[id]
	var n := 0
	for fid in sim.farms.farms:
		if sim.farms.farms[fid].pos.distance_to(b.pos) <= Balance.WATER_FARM_REACH:
			n += 1
	return n


## How educated a manager the town can hire, 0 to 1 (its local graduates;
## see Education.leader_education).
static func town_education(sim: CitySim) -> float:
	return sim.education.leader_education(int(sim.stats.workers))


## True when the river (or a lake) is close enough for an intake.
func river_near(sim: CitySim, id: int) -> bool:
	var b: Dictionary = sim.services.buildings[id]
	var off: Vector2 = sim.terrain_offset
	for r in [150.0, 400.0, 800.0, 1200.0]:
		for i in 12:
			var a := TAU * i / 12.0
			if Terrain.is_water(b.pos.x + off.x + cos(a) * r, b.pos.z + off.y + sin(a) * r):
				return true
	return false


## What the tree offers this manager now, and why each locked step is
## locked: [[key, "" or reason]], wells and tower first, then the tree.
func options(sim: CitySim, id: int) -> Array:
	var out := [["well", _locked(sim, id, "well")], ["tower", _locked(sim, id, "tower")]]
	for node in TREE:
		out.append([node.id, _locked(sim, id, node.id)])
	return out


func _node(key: String) -> Dictionary:
	for node in TREE:
		if node.id == key:
			return node
	return {}


## The hub as the shared Agency code sees it.
func agency_hub(id: int) -> Dictionary:
	return {"leader": utilities[id].leader, "built": utilities[id].built}


## Why this manager can't take a step yet ("" when they can).
func _locked(sim: CitySim, id: int, key: String) -> String:
	var u: Dictionary = utilities[id]
	match key:
		"well":
			return "the wellfield is full" if count_work(id, "well") >= Balance.WATER_MAX_WELLS else ""
		"tower":
			return "has two towers" if count_work(id, "tower") >= 2 else ""
	var node := _node(key)
	for r in node.get("requires", []):
		if not r in u.built:
			return "needs the %s first" % NAMES[r].name.to_lower()
	var at: Vector3 = sim.services.buildings[id].pos
	var hub := agency_hub(id)
	for c in node.get("needs", {}):
		if Agency.holds(sim, hub, at, 0.0, c, node.needs[c]):
			continue
		match c:
			"leader_edu": return "needs a better-schooled manager"
			"education": return "needs better schools in town"
			"population": return "needs a town of %s" % CitySim.money_text(int(node.needs[c]))
			"link": return "needs a road to a neighbouring town"
			"local:farm": return "needs farms nearby"
		return "not yet"
	# Things on the ground.
	match key:
		"filtration":
			if count_work(id, "well") < 2:
				return "needs two wells"
		"intake":
			if count_work(id, "well") < Balance.WATER_MAX_WELLS:
				return "needs a full wellfield first"
			if not river_near(sim, id):
				return "needs the river nearby"
		"industrial_main":
			if _industry_on_mains(sim, id) < 2:
				return "needs factories along its mains"
	return ""


## The step the manager wants next, most pressing first, or "".
func next_project(sim: CitySim, id: int) -> String:
	var u: Dictionary = utilities[id]
	var lead: Dictionary = u.leader
	var l: Dictionary = live[id]
	var ok := func(key: String) -> bool:
		return (key in ["well", "tower"] or not key in u.built) and _locked(sim, id, key) == ""
	# Water first: ambitious managers build ahead of demand.
	var want: float = float(l.load) * (1.15 + 0.3 * float(lead.ambition)) + 50.0
	if want > water_capacity(id):
		var supply := count_work(id, "well") * int(Balance.WATER_WORKS.well.capacity) + count_work(id, "intake") * int(Balance.WATER_WORKS.intake.capacity)
		if supply > water_capacity(id) and ok.call("tower"):
			return "tower"
		if ok.call("well"):
			return "well"
		if ok.call("intake"):
			return "intake"
		if ok.call("tower"):
			return "tower"
	if ok.call("lagoon") and int(l.load) >= Balance.WATER_SEWER_START:
		return "lagoon"
	if ok.call("plant") and (l.sewer_load > sewer_capacity(id) * 0.8 or float(lead.edu) >= 0.7):
		return "plant"
	# Then the rest of the tree, as the manager's schooling and the town and
	# its neighbours allow (lagoon, plant and intake only when needed).
	for node in TREE:
		if not node.id in ["lagoon", "plant", "intake"] and ok.call(node.id):
			return node.id
	return ""


func _industry_on_mains(sim: CitySim, id: int) -> int:
	var n := 0
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and sim.services.served.get(key, {}).get("water_by", -1) == id:
			n += 1
	return n


func _build(sim: CitySim, id: int, key: String, usable: Callable) -> bool:
	var u: Dictionary = utilities[id]
	var tree := not key in ["well", "tower"]
	if key == "plant":
		# The modern plant goes up where the lagoon was.
		for w in u.works:
			if w[0] == "lagoon":
				w[0] = "plant"
		u.built.append(key)
		return true
	if not NAMES[key].yard:
		u.built.append(key)
		return true
	if _yard_count(id) >= MAX_CELLS:
		u.last = "Boxed in: its yard is as big as it gets"
		return false
	var b: Dictionary = sim.services.buildings[id]
	for c in _frontier(id):
		if usable.call(cell_corners(b, c)):
			u.works.append([key, c])
			if tree:
				u.built.append(key)
			return true
	u.last = "Boxed in: no free land next to its yard for a %s" % NAMES[key].name.to_lower()
	return false


## Lays water mains, then sewers, along the streets next to what it has,
## best payback first (most zoned lots per dollar).
func _extend(sim: CitySim, id: int, keep: float, ambition: float) -> bool:
	var u: Dictionary = utilities[id]
	var l: Dictionary = live[id]
	var lots_on := {}
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE:
			lots_on[lot.seg] = int(lots_on.get(lot.seg, 0)) + 1
	var changed := false
	for kind in ["mains", "sewers"]:
		if kind == "sewers" and sewer_capacity(id) == 0:
			break
		var per_m: float = Balance.WATER_MAIN_PER_M if kind == "mains" else Balance.SEWER_PER_M * (1.0 - Balance.WATER_GRANT_SHARE)
		for _i in 1 + roundi(2.0 * ambition):
			var best := -1
			var best_score := 0.0
			var best_cost := 0.0
			for seg in _candidates(sim.network, id, kind):
				# A street with no lots of its own (the side of corner lots)
				# still carries the main on to the next block's lots.
				var n: float = lots_on.get(seg, 0)
				var s: Dictionary = sim.network.segments[seg]
				for node in [s.a, s.b]:
					for other in sim.network.segments_at(node):
						if other != seg and not l[kind].has(other):
							n += 0.5 * int(lots_on.get(other, 0))
				if n == 0.0:
					continue
				var cost := RoadNetwork.polyline_length(sim.network.sample_segment(seg, 16)) * per_m
				var score := n / maxf(cost, 1.0)
				if score > best_score:
					best = seg
					best_score = score
					best_cost = cost
			if best == -1 or u.cash - best_cost < keep:
				break
			_lay(id, kind, sim.network, best)
			u.cash -= best_cost
			u.last = "Laid a %s under a street" % ("water main" if kind == "mains" else "sewer")
			changed = true
	return changed


## Unpiped street segments touching its pipes (sewers follow the mains).
func _candidates(network: RoadNetwork, id: int, kind: String) -> Array:
	var l: Dictionary = live[id]
	var out := []
	if kind == "sewers":
		# The first sewer starts at the utility's own street.
		var has: Dictionary = l.sewers
		for seg in l.mains:
			if has.has(seg):
				continue
			var s: Dictionary = network.segments[seg]
			var touches := has.is_empty()
			for n in [s.a, s.b]:
				for other in network.segments_at(n):
					touches = touches or has.has(other)
			if touches:
				out.append(seg)
	else:
		var ends := {}
		for seg in l.mains:
			ends[network.segments[seg].a] = true
			ends[network.segments[seg].b] = true
		for n in ends:
			for seg in network.segments_at(n):
				if not l.mains.has(seg) and main_owner(seg) == -1 and not seg in out:
					out.append(seg)
	out.sort()
	return out


# --- Effects on the town ---------------------------------------------------------

## How much a sewer plant's smell lowers land value here, 0 to 1.
func odor_at(buildings: Dictionary, p: Vector3) -> float:
	return odor_from(odor_sources(buildings), p)


## The lagoons and sewer plants that smell: [[centre, odor], ...]. Worked
## out once for a whole pass over the town's lots (see Economy).
func odor_sources(buildings: Dictionary) -> Array:
	var out := []
	for id in utilities:
		var u: Dictionary = utilities[id]
		if u.odor <= 0.0 or not buildings.has(id):
			continue
		for w in u.works:
			if w[0] in ["lagoon", "plant"]:
				out.append([cell_center(buildings[id], w[1]), float(u.odor)])
	return out


static func odor_from(sources: Array, p: Vector3) -> float:
	var worst := 0.0
	for src in sources:
		var d: float = src[0].distance_to(Vector3(p.x, 0.0, p.z))
		worst = maxf(worst, src[1] * clampf(1.0 - d / Balance.WATER_ODOR_REACH, 0.0, 1.0))
	return worst


## Land value here as a share of normal (1.0 = no smell).
func land_value_factor(buildings: Dictionary, p: Vector3) -> float:
	return value_from(odor_sources(buildings), p)


static func value_from(sources: Array, p: Vector3) -> float:
	return 1.0 - Balance.WATER_ODOR_VALUE * odor_from(sources, p)


## How much the utilities' water rates above the usual bill put people off
## moving in (0 at or below the usual bill), weighted by homes served.
func rate_penalty(sim: CitySim) -> float:
	var homes := 0
	var weighted := 0.0
	for id in _sorted_ids():
		var n := int(live.get(id, {}).get("homes", 0))
		homes += n
		weighted += n * maxf(0.0, float(utilities[id].rate) - 1.0)
	return 0.0 if homes == 0 else Balance.WATER_RATE.demand * weighted / homes


## Share of the town's homes under a boil-water notice.
func boil_share(sim: CitySim) -> float:
	var homes := 0
	var boiling := 0
	for key in sim.buildings:
		if sim.buildings[key].zone != ZoneMap.Zone.RESIDENTIAL:
			continue
		homes += 1
		if boils(sim.services.served.get(key, {})):
			boiling += 1
	return 0.0 if homes == 0 else float(boiling) / homes


## True when the lot (its row in Services.served) is under a boil notice.
func boils(s: Dictionary) -> bool:
	var by: int = s.get("water_by", -1)
	return by != -1 and utilities.has(by) and utilities[by].boil


## True when a point is on a yard piece (lots there go away).
func covers(buildings: Dictionary, p: Vector3) -> bool:
	return not work_at(buildings, p).is_empty()


## Drops utilities whose building is gone.
func prune(buildings: Dictionary) -> void:
	for id in utilities.keys():
		if not buildings.has(id):
			utilities.erase(id)
			live.erase(id)
			_hash.erase(id)


func _sorted_ids() -> Array:
	var ids := utilities.keys()
	ids.sort()
	return ids


# --- Saving ------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id in utilities:
		var u: Dictionary = utilities[id]
		var works := []
		for w in u.works:
			works.append([w[0], w[1].x, w[1].y])
		var pipes := {}
		for kind in ["mains", "sewers"]:
			pipes[kind] = []
			for line in u[kind]:
				var flat := []
				for p in line:
					flat.append(p.x)
					flat.append(p.y)
				pipes[kind].append(flat)
		out[str(id)] = {"name": u.name, "leader": u.leader, "built": u.built,
			"subsidy": u.subsidy, "cash": u.cash, "cond": u.cond, "works": works, "mains": pipes.mains,
			"sewers": pipes.sewers, "boil": u.boil, "odor": u.odor, "last": u.last, "returned": u.returned,
			"taps": u.taps, "sewer_taps": u.sewer_taps, "rate": u.rate}
	return out


func from_dict(d: Dictionary) -> void:
	utilities.clear()
	live.clear()
	_hash.clear()
	for k in d:
		var s: Dictionary = d[k]
		var works := []
		for w in s.get("works", []):
			works.append([str(w[0]), Vector2i(int(w[1]), int(w[2]))])
		var lead: Dictionary = s.get("leader", {})
		var built := []
		for k2 in s.get("built", []):
			built.append(str(k2))
		var u := {"name": str(s.get("name", "")), "leader": {"edu": float(lead.get("edu", 0.25)),
			"caution": float(lead.get("caution", 0.5)), "ambition": float(lead.get("ambition", 0.5))},
			"built": built, "subsidy": int(s.get("subsidy", 0)), "cash": float(s.get("cash", 0.0)),
			"cond": float(s.get("cond", 1.0)), "works": works, "mains": [], "sewers": [], "boil": bool(s.get("boil", false)),
			"odor": float(s.get("odor", 0.0)), "last": str(s.get("last", "")), "returned": int(s.get("returned", 0)),
			"taps": int(s.get("taps", 0)), "sewer_taps": int(s.get("sewer_taps", 0)), "rate": float(s.get("rate", 1.0))}
		for kind in ["mains", "sewers"]:
			for flat in s.get(kind, []):
				var line := PackedVector2Array()
				for i in range(0, flat.size() - 1, 2):
					line.append(Vector2(float(flat[i]), float(flat[i + 1])))
				u[kind].append(line)
		utilities[int(k)] = u


# --- The info panel ------------------------------------------------------------------

## What the panel shows for a utility: its manager, money, condition, what it
## did last, the tree, and the subsidy buttons.
static func describe(sim: CitySim, id: int) -> Dictionary:
	var w: WaterUtility = sim.services.water
	var u: Dictionary = w.utilities[id]
	var l: Dictionary = w.live.get(id, {})
	var cost := w.monthly_cost(id)
	var income := float(l.get("fees", 0)) + float(u.subsidy) + w.other_income(sim, id)
	var rows := [
		["Superintendent", "%s (schooling %d%%)" % [u.name, roundi(u.leader.edu * 100.0)]],
		["Homes on its water", "%s of %s" % [CitySim.money_text(int(l.get("load", 0))), CitySim.money_text(w.water_capacity(id))]],
		["Sewage", "%s of %s" % [CitySim.money_text(int(l.get("sewer_load", 0))), CitySim.money_text(w.sewer_capacity(id))]
			if w.sewer_capacity(id) > 0 else "Septic tanks (no plant yet)"],
		["Pipe laid", "%.1f km main, %.1f km sewer" % [_length(u.mains) / 1000.0, _length(u.sewers) / 1000.0]],
		["Condition", "%d%%" % roundi(u.cond * 100.0)],
		["Water bill", "$%s a month a home (%d%% of usual)" % [CitySim.money_text(roundi(Services.WATER_FEE[ZoneMap.Zone.RESIDENTIAL] * float(u.rate))), roundi(float(u.rate) * 100.0)]],
		["Bills collected", "$%s / month" % CitySim.money_text(int(l.get("fees", 0)))],
		["Running costs", "$%s / month" % CitySim.money_text(roundi(cost))],
		["Cash", "%s$%s" % ["" if u.cash >= 0.0 else "-", CitySim.money_text(absi(roundi(u.cash)))]],
	]
	var sold := sim.trade.sold("water")
	var got := sim.trade.got("water")
	if sold > 0.0:
		rows.append(["Sold to the region", "%s homes' worth a month" % CitySim.money_text(roundi(sold / Balance.WATER_KGAL_PER_HOME))])
	elif got > 0.0:
		rows.append(["Bought from the region", "%s homes' worth a month" % CitySim.money_text(roundi(got / Balance.WATER_KGAL_PER_HOME))])
	if int(u.returned) > 0:
		rows.append(["Paid back to the town", "$%s" % CitySim.money_text(int(u.returned))])
	var problems := []
	if u.boil:
		problems.append("Boil-water notice: pipes and plant are in poor repair. More subsidy or better schools help.")
	if u.odor > 0.1:
		problems.append("The sewer plant smells, lowering land value nearby.")
	if income < cost and u.cash <= w.cash_floor(id) + 1.0:
		problems.append("Out of money: it can't keep up repairs. Raise its subsidy.")
	if str(u.last).begins_with("Boxed in"):
		problems.append(u.last)
	# The tree: what's built, what's open to this manager, what's still locked.
	var built := []
	var open := []
	var locked := []
	for entry in w.options(sim, id):
		var key: String = entry[0]
		var n := w.count_work(id, key)
		if n == 0 and key in u.built:
			n = 1
		if n > 0:
			built.append(NAMES[key].name + (" x%d" % n if n > 1 else ""))
		elif entry[1] == "":
			open.append(NAMES[key].name)
		else:
			locked.append("%s (%s)" % [NAMES[key].name, entry[1]])
	var tree := [["Built", ", ".join(built)]]
	if not open.is_empty():
		tree.append(["Next up", ", ".join(open)])
	if not locked.is_empty():
		tree.append(["Locked", "; ".join(locked)])
	# Set by the utility's Funding slider (Economy page).
	rows.append(["City subsidy", "$%s / month" % CitySim.money_text(int(u.subsidy))])
	var status := "Working: %s" % str(u.last).to_lower() if u.last != "" else "Working"
	if u.boil:
		status = "Boil-water notice in effect"
	return {"title": "%s Water and Sewer" % str(u.name).get_slice(" ", 1), "kind": "Utility hub", "icon": "water_utility",
		"ok": problems.is_empty(), "status": status, "rows": rows, "problems": problems, "tree": tree}
