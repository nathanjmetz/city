class_name Farms
extends RefCounted
## Farms the way Brawn asked: open the Fertility view, place a farmhouse
## near good soil, and the farmer does the rest, buying the best fields
## around it as it makes money (and selling them if it struggles). The
## player can only reserve land for farming so nothing else is built on it.
##
## No world grid: each farm lays its fields out square to its own farmhouse
## (which faces its road), the way Midwest fields follow the road they're
## on. A new farm puts up its barn first, then plants the fields next to
## the farmyard and works outward. Every farmhouse gets a winding gravel lane out to its road.
##
## A farm grows to a real size and then builds a road (Brawn, 2026-10-23):
## it works one 80-acre block between roads at a time (see Balance
## FARM_BLOCK_CELLS), and when that is full and paying it lays a gravel road
## along the survey line to the next block, which becomes an ordinary city
## road (see HubRoads). Fields are 40-acre "forties", two to a block.
##
## Soil never wears out: every spot keeps its own fertility forever.
## Prices follow Midwest figures: corn and soybeans, about $10,000 an acre.

const CELL := 40.0                 # one field cell: 40 m square, about 0.4 acre
## The longest farm lane a farmhouse can have out to its road.
const MAX_DRIVE := 250.0
const DRIVE_WIDTH := 4.0           # a one-lane gravel farm lane
const ACRES_PER_CELL := CELL * CELL / 4046.86
const FARMHOUSE_SIZE := Vector2(36, 40)  # house, barn and silo yard
const FARMHOUSE_COST := Balance.FARMHOUSE_COST
const LAND_PER_ACRE := Balance.FARM_LAND_PER_ACRE
## Farmland is taxed on what it produces, not its sale price (US "use value"
## assessment), roughly a quarter of market value.
const AG_ASSESSMENT := Balance.FARM_AG_ASSESSMENT
## Yearly gross per acre at full fertility: corn about 180 bu x $4.50.
const GROSS_PER_ACRE := Balance.FARM_GROSS_PER_ACRE
## Yearly cost per acre (seed, fuel, fertiliser, machinery), plus more the
## farther a field is from the farmhouse (driving the combine out to it).
## USDA operating costs per acre (land already owned): soybeans need no
## nitrogen, so they cost less to grow.
const COST_PER_ACRE := Balance.FARM_COST_PER_ACRE
const COST_PER_ACRE_PER_KM := Balance.FARM_COST_PER_ACRE_PER_KM
## Jobs: the farm family (2) plus a hired hand per this many cells (~40 acres).
const CELLS_PER_WORKER := Balance.FARM_CELLS_PER_WORKER
const MAX_CELLS := Balance.FARM_MAX_CELLS
## How much a field next to more of the farm's own land is preferred, in
## dollars a year per neighbouring field.
const COMPACT_BONUS := Balance.FARM_COMPACT_BONUS
## And land the player reserved for farming, likewise.
const RESERVE_BONUS := Balance.FARM_RESERVE_BONUS
## One crop price cycle, in game days (a game day settles a month: 4 years).
const PRICE_CYCLE_DAYS := Balance.FARM_PRICE_CYCLE_DAYS
## Farms decide to buy or sell land this often, in ticks (6 game hours).
const DECIDE_EVERY := Balance.FARM_DECIDE_EVERY
## One block of land between roads, in cells (along the road, back from it).
const BLOCK := Balance.FARM_BLOCK_CELLS
## The fewest workable cells in a row worth planting (120 m, room to run a
## planter and turn at the ends).
const MIN_ROW_CELLS := 3
## The front rows a new field must pay over to be opened (3 rows, 120 m
## deep: a field of about 15 acres, the smallest worth bringing equipment to).
const OPEN_ROWS := 3
## A farmer would rather make a field it works deeper than open a new one
## (dollars a year per acre-cell of preference).
const EXTEND_BONUS := 60.0

## Land the player has set aside (Reserves): farms stay off land saved for
## other industries and favour land saved for farming.
var reserves: Reserves
## The town's sliders: Funding is support per acre, Growth how eagerly a
## farm buys more fields (see Policies).
var policies: Policies
## Set by the city: what power companies pay a year to lease ground in a
## field outline (wind turbines in the corn). Callable(poly) -> float.
var lease_of := Callable()
## And what they pay farm `id` a year for whole fields it leased out for
## solar panels. Callable(id) -> float.
var rent_of := Callable()
## The town's character: a farm town's farmers buy land more readily.
var culture: TownCulture
## Farmland outlines from older saves, for the city to turn into reserves.
var legacy_outlines: Array = []
## Farms: id -> {pos, dir, crop, cells: Array of Vector2i in the farm's own
## frame, loss_streak, barn: bool, drive: Array of Vector3}
var farms := {}
## Fields a road has trimmed: farm id -> {cell: Array of outlines}. Worked
## out again from the roads after every change (see RoadWins), not saved.
var trim := {}
var _next_id := 1
## Set by the city each time farms decide: the industrial property tax rate
## (percent) the land pays.
var tax_rate := 1.5
## Crop prices against normal (1.0). They rise and fall over the years like
## real commodity cycles, so farms grow in good years and sell in bad ones.
var price := 1.0
## Set by the city: the game day (for each crop's own price swing), the
## year (farms plan their crops each new year), what buyers around town
## want (CropPlan.demand) and the ground's steepness at a point.
var day := 0.0
var year := 0
var demand := {}
var slope_of := Callable()
## Set by the city: farm `id` has filled its open blocks and wants to build a
## road to another. Callable(id) -> bool (true when anything changed).
var expand := Callable()
## What an acre sells for at a point, nearby development included
## (Capital.land_price). Callable(pos) -> float; unset, farm value.
var land_price_of := Callable()
## Set by the city: is all this ground open or already the farm's own?
## Callable(points, "farm:<id>") -> bool (Capital.land_free).
var land_free := Callable()


## How good the soil is at a point (see Resources). Fixed forever.
static func fertility_at(p: Vector3) -> float:
	return Resources.fertility(p)


## Crop price on a given game day: up to 15% above or below normal.
static func price_on(day: float) -> float:
	return 1.0 + 0.15 * sin(TAU * day / PRICE_CYCLE_DAYS)


## The farm's right-hand direction, with its farmhouse facing the road.
static func _right(f: Dictionary) -> Vector3:
	return Vector3(-f.dir.z, 0.0, f.dir.x)


## Centre of field cell c of farm f: cell (0, 0) is the farmyard, j counts
## back from the road and i to the right.
static func cell_center(f: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = f.pos + _right(f) * (c.x * CELL) - f.dir * (c.y * CELL)
	return Vector3(p.x, 0.0, p.z)


## The four corners of a field cell, on the ground plane.
static func cell_corners(f: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := cell_center(f, c)
	var r: Vector3 = _right(f) * CELL * 0.5
	var b: Vector3 = -f.dir * CELL * 0.5
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * s.x + b * s.y
		out.append(Vector2(p.x, p.z))
	return out


## The land survey in the farm's own frame. Blocks are BLOCK.x cells along
## the road by BLOCK.y back, with one cell between them for a road: road
## columns at x = 10, -11, 31... and road rows at y = 10, 21, 32... (the
## farmhouse's own block runs all the way out to its road). True when cell
## c lies on one of those lines, where only a road goes.
static func on_line(c: Vector2i) -> bool:
	if posmod(c.x - BLOCK.x / 2, BLOCK.x + 1) == 0:
		return true
	return c.y >= BLOCK.y and posmod(c.y - BLOCK.y, BLOCK.y + 1) == 0


## Which block cell c is in: (0, 0) is the farmhouse's.
static func block_of(c: Vector2i) -> Vector2i:
	var bx := floori(float(c.x + BLOCK.x / 2 + 1) / (BLOCK.x + 1))
	var by := 0 if c.y < BLOCK.y else floori(float(c.y + 1) / (BLOCK.y + 1))
	return Vector2i(bx, by)


## Which 40-acre field cell c is in: each block holds two, side by side.
static func forty_of(c: Vector2i) -> Vector2i:
	var b := block_of(c)
	var half := 1 if posmod(c.x + BLOCK.x / 2, BLOCK.x + 1) >= BLOCK.x / 2 else 0
	return Vector2i(b.x * 2 + half, b.y)


## Which field cell c is in: the farmer's working unit, half a forty side
## by side (200 m across, the long way back from the road), about 20 acres
## when it runs the forty's full depth. Southern Indiana fields run 20 to 40
## acres, broken up by woods and creeks.
static func field_of(c: Vector2i) -> Vector2i:
	var b := block_of(c)
	var quarter := posmod(c.x + BLOCK.x / 2, BLOCK.x + 1) / (BLOCK.x / 4)
	return Vector2i(b.x * 4 + mini(quarter, 3), b.y)


## The first row of cells on the farm's side of its own road: the road its
## lane comes out on is the front edge of its land.
static func front_row(f: Dictionary) -> int:
	var drive: Array = f.get("drive", [])
	if drive.is_empty():
		return -BLOCK.y
	return ceili(_local(f, drive[-1]).y / CELL + 0.5)


## A point in the farm's frame, in cells (x along, y back), on the ground.
static func local_point(f: Dictionary, u: float, v: float) -> Vector3:
	var p: Vector3 = f.pos + _right(f) * (u * CELL) - f.dir * (v * CELL)
	return Vector3(p.x, 0.0, p.z)


## The road a farm builds to open block `to` from its block `from`, as
## [far end, line direction toward the road network, the rest of the line
## (Vector3 points from the far end)] candidates: a road along the survey
## line between them, joined to the nearest road it can reach.
static func road_lines(f: Dictionary, from: Vector2i, to: Vector2i) -> Array:
	var out := []
	var toward_road: Vector3 = f.dir  # back toward the farm's own road
	var back := float(BLOCK.y + (BLOCK.y + 1) * from.y)  # the row line behind `from`
	if to.y == from.y:
		# Beside it: a road down the column line between them, from the back
		# line out to whatever road it meets.
		var u := float(from.x * (BLOCK.x + 1) + (BLOCK.x / 2 if to.x > from.x else -BLOCK.x / 2 - 1))
		out.append([local_point(f, u, back), toward_road, []])
	elif to.y == from.y + 1 and to.x == from.x:
		# Behind it: a road along the row line, joined at one corner to a road
		# there, or run out along that side's column line to one.
		var u0 := float(from.x * (BLOCK.x + 1) - BLOCK.x / 2 - 1)
		var u1 := float(from.x * (BLOCK.x + 1) + BLOCK.x / 2)
		for ends in [[u0, u1], [u1, u0]]:
			out.append([local_point(f, ends[0], back), toward_road, [local_point(f, ends[1], back)]])
	return out


func add_farm(pos: Vector3, dir: Vector3, crop: String, drive: Array) -> int:
	var id := _next_id
	_next_id += 1
	farms[id] = {"pos": pos, "dir": dir, "crop": crop, "cells": [], "loss_streak": 0,
		"barn": false, "drive": drive, "fields": {}, "plan_year": year, "blocks": [Vector2i.ZERO], "road_wait": 0.0,
		"pending": {}, "why": "", "own": start_fields(), "rent": []}
	# The family starts with its first 80 acres paid for, and some savings
	# toward the next (Capital).
	Capital.start(farms[id], "farm")
	return id


## Acres the town's farms own or rent, planted or not.
func held_acres() -> float:
	var total := 0
	for id in farms:
		var f: Dictionary = farms[id]
		for k in f.get("own", []) + f.get("rent", []):
			total += field_cells(f, k).size()
	return total * ACRES_PER_CELL


## The fields a new farm family owns from the start: its first block, 80
## acres beside the farmyard.
static func start_fields() -> Array:
	var out := []
	for q in 4:
		out.append(Vector2i(q, 0))
	return out


## What field k of farm f would cost to buy: every acre of it, woods and all,
## at what land sells for there.
func field_price(f: Dictionary, k: Vector2i) -> float:
	var cells := field_cells(f, k)
	var mid := Vector3.ZERO
	for c in cells:
		mid += cell_center(f, c)
	mid /= maxi(cells.size(), 1)
	var per_acre: float = land_price_of.call(mid) if land_price_of.is_valid() else Balance.CAPITAL_LAND_PER_ACRE
	return cells.size() * ACRES_PER_CELL * per_acre


## The blocks next to farm f's open ones that it could open with a road.
static func next_blocks(f: Dictionary) -> Array:
	var out := []
	for b in f.blocks:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var n: Vector2i = b + d
			if not n in f.blocks and not n in out:
				out.append([b, n])
	return out


## A winding gravel lane from the farmhouse's front door out to a point on
## its road: a gentle S-bend, different for every farm.
static func make_drive(pos: Vector3, dir: Vector3, road: Vector3) -> Array:
	var start := pos + dir * (FARMHOUSE_SIZE.y * 0.5)
	start.y = 0.0
	var end := Vector3(road.x, 0.0, road.z)
	var span := end - start
	var side := Vector3(-span.z, 0.0, span.x).normalized()
	var bend := (_hash01(Vector2i(roundi(pos.x), roundi(pos.z)), 7) * 2.0 - 1.0)
	bend = signf(bend) * (0.5 + absf(bend) * 0.5) * span.length() * 0.16
	var p1 := start + span / 3.0 + side * bend
	var p2 := start + span * 2.0 / 3.0 - side * bend * 0.8
	var out := []
	var n := maxi(6, int(span.length() / 8.0))
	for k in n + 1:
		var t := float(k) / n
		var u := 1.0 - t
		out.append(start * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + end * t * t * t)
	return out


## The farm whose farmhouse yard or lane holds this point, or -1.
func farm_at(p: Vector3) -> int:
	for id in farms:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _yard(farms[id])):
			return id
		if _near_drive(farms[id], p, DRIVE_WIDTH * 0.5 + 2.0):
			return id
		if farms[id].has("stock") and not farms[id].stock.sites.is_empty():
			# Its livestock barns (Livestock), on ground it took from its fields.
			var f: Dictionary = farms[id]
			var local := _local(f, p)
			var c := Vector2i(roundi(local.x / CELL), roundi(local.y / CELL))
			if c in Livestock.site_cells(f) and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), cell_corners(f, c)):
				return id
	return -1


## True when a point is on a farmyard or farm lane (no lots there).
func covers(p: Vector3) -> bool:
	return farm_at(p) != -1


## The farm whose field holds this point, or -1.
func field_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in farms:
		var f: Dictionary = farms[id]
		var local := _local(f, p)
		var c := Vector2i(roundi(local.x / CELL), roundi(local.y / CELL))
		if c in f.cells and Geometry2D.is_point_in_polygon(q, cell_corners(f, c)):
			return id
	return -1


## Acres farmed in the whole town.
func total_acres() -> float:
	var n := 0.0
	for id in farms:
		for c in farms[id].cells:
			n += share(id, c)
	return n * ACRES_PER_CELL


## How much of a field cell is left to farm (1 unless a road trimmed it).
func share(id: int, c: Vector2i) -> float:
	if not trim.has(id) or not trim[id].has(c):
		return 1.0
	var a := 0.0
	for piece in trim[id][c]:
		a += RoadWins.area(piece)
	return a / (CELL * CELL)


func jobs() -> int:
	var total := 0
	for id in farms:
		total += 2 + farms[id].cells.size() / CELLS_PER_WORKER + Livestock.jobs(farms[id])
	return total


## A farm's yearly profit from its fields as they stand.
func yearly_profit(id: int) -> float:
	var f: Dictionary = farms[id]
	var total := 0.0
	for c in f.cells:
		total += field_profit(f, c)
	if rent_of.is_valid():
		total += rent_of.call(id)
	# Hog, dairy or turkey barns, manure included (Livestock).
	total += Livestock.yearly(f, day)
	return total + f.cells.size() * support(id)


## What the town pays a farm per field a year (a fee when negative).
func support(id: int) -> float:
	if policies == null:
		return 0.0
	return policies.pick(Balance.POLICY_SUPPORT_PER_ACRE, "funding", "farms", "farm:%d" % id) * ACRES_PER_CELL


## The yearly profit a new field must clear before farm `id` buys it (INF: none).
func buy_margin(id: int) -> float:
	if policies == null:
		return 0.0
	var m: float = policies.pick(Balance.POLICY_BUY_MARGIN_PER_ACRE, "growth", "farms", "farm:%d" % id)
	if culture != null and m < INF:
		m -= culture.pull("farm") * Balance.CULTURE_MARGIN_PER_ACRE
	return m * ACRES_PER_CELL


## What the town pays all its farms a year (negative: what it collects).
func yearly_support() -> float:
	var total := 0.0
	for id in farms:
		total += farms[id].cells.size() * support(id)
	return total


## One field's yearly profit: what it grows, less farming costs and the
## property tax on the land. A family with modern machinery works a farm
## this size, so it doesn't wait on hired hands.
func field_profit(f: Dictionary, c: Vector2i, crop := "") -> float:
	var mid := cell_center(f, c)
	var km := mid.distance_to(Vector3(f.pos.x, 0.0, f.pos.z)) / 1000.0
	# This year's crop on the field, after last year's (CropPlan), or the
	# crop a farmer weighing new ground would plant there.
	var fl := CropPlan.field(f, c) if crop == "" else {"crop": crop, "prev": "", "health": 0.5}
	var net := CropPlan.net_per_acre(fl.crop, fl.prev, fl.health, fertility_at(mid),
		price * CropPlan.relative_price(fl.crop, day),
		Agency.effect(f, Agency.TREES.farm, "output*") * Agency.effect(f, Agency.TREES.farm, "price*"))
	var tax := LAND_PER_ACRE * AG_ASSESSMENT * tax_rate / 100.0
	var lease := 0.0
	if lease_of.is_valid():
		lease = lease_of.call(cell_corners(f, c))
	var crop_net := (net - COST_PER_ACRE_PER_KM * km - tax) * ACRES_PER_CELL
	# Rented ground: the landowner takes a share of what it makes.
	if crop_net > 0.0 and f.has("rent") and field_of(c) in f.rent:
		crop_net *= 1.0 - Balance.CAPITAL_RENT_SHARE
	return crop_net + lease


## The best a new farm here could make a year from a field beside its yard,
## over every crop it could grow ($; 0 or less means no field would pay, as
## on poor, wooded ground nobody farms).
func start_profit(pos: Vector3, dir: Vector3) -> float:
	var best := -INF
	for crop in CropPlan.CROPS:
		var f := {"pos": pos, "dir": dir, "crop": crop, "cells": []}
		# Either field beside the farmyard, opened the way best_field opens
		# one: its front rows, planted whole.
		for k in _next_fields(f, {}):
			var total := 0.0
			for y in OPEN_ROWS:
				for c in row_cells(f, k, y):
					total += field_profit(f, c)
			best = maxf(best, total / (OPEN_ROWS * BLOCK.x / 4))
	return best


## Every farm takes its next step. A new farm puts up its barn first. Then
## it buys the best field next to its land (if that field would pay and the
## farm is making money) or sells its worst one (if it keeps losing money).
## Farms finance land like real ones do, so profit, not cash in hand,
## decides. `usable(centre, corners)` says if the city leaves the ground
## free (no road, lot or building).
func decide(usable: Callable) -> bool:
	var changed := false
	var ids := farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = farms[id]
		if not f.barn:
			f.barn = true
			changed = true
			continue
		# Each new year the leader picks every field's crop (CropPlan).
		if year > int(f.get("plan_year", 0)):
			f.plan_year = year
			if not f.cells.is_empty():
				CropPlan.plan(f, demand, price, day, func(c): return fertility_at(cell_center(f, c)),
					func(c): return slope_of.call(cell_center(f, c)) if slope_of.is_valid() else 0.0)
				changed = true
		var profit := yearly_profit(id)
		# The farm's own money: it keeps part of the year's profit and pays
		# on the land it bought (Capital).
		Capital.step(f, "farm", profit, day)
		var sup := support(id)
		var margin := buy_margin(id)
		# A field part way through planting is finished first.
		var planting := _planting(id, f, _rows(f), usable) if f.cells.size() < MAX_CELLS else Vector2i.MAX
		if planting != Vector2i.MAX:
			f.cells.append(planting)
			changed = true
			continue
		var best := best_field(id, usable)
		# A field is judged as a whole, poor spots and all. When one loses
		# money, the poorer of its front and back rows goes, so what's left
		# stays rectangular.
		var worst := []
		var worst_avg := INF
		var rows := _rows(f)
		var each := {}
		var sums := {}
		for c in f.cells:
			var k := field_of(c)
			each[c] = field_profit(f, c)
			if not sums.has(k):
				sums[k] = [0.0, 0]
			sums[k][0] += each[c]
			sums[k][1] += 1
		for k in rows:
			# A field that would pay in another crop isn't sold: the leader
			# switches crops at the new year instead.
			var avg: float = sums[k][0] / sums[k][1]
			if avg < 0.0:
				for crop in CropPlan.CROPS:
					var total := 0.0
					for c in f.cells:
						if field_of(c) == k:
							total += field_profit(f, c, crop)
					avg = maxf(avg, total / sums[k][1])
			if avg >= worst_avg:
				continue
			var low := INF
			for y in [rows[k].min(), rows[k].max()]:
				var total := 0.0
				var n := 0
				for c in row_cells(f, k, y):
					if each.has(c):
						total += each[c]
						n += 1
				if n > 0 and total / n < low:
					low = total / n
					worst = [k, y]
			worst_avg = avg
		# A farm told to expand keeps thin fields a little longer.
		if not worst.is_empty() and worst_avg + sup < minf(margin, 0.0):
			# A field that loses money through a whole season (or that the
			# farm can't carry, its savings gone) is cut back: farmers ride
			# out a bad price year rather than give up ground.
			f.loss_streak += 1
			if f.loss_streak >= Balance.FARM_SELL_LOOKS or (f.loss_streak >= 4 and float(f.get("cash", 0.0)) < 0.0):
				# A field cut back to less than its opening depth isn't worth
				# working: it goes whole.
				var gone: Array = row_cells(f, worst[0], worst[1]) \
					if rows[worst[0]].size() > OPEN_ROWS else field_cells(f, worst[0])
				f.cells = f.cells.filter(func(c): return not c in gone)
				f.loss_streak = 0
				changed = true
				# Rented ground it no longer works goes back to its owner.
				if f.has("rent") and worst[0] in f.rent and not f.cells.any(func(c): return field_of(c) == worst[0]):
					f.rent.erase(worst[0])
		elif best != Vector2i.MAX and (f.cells.is_empty() or profit >= 0.0):
			# Ground it doesn't own yet is bought first, out of savings.
			if _buy(f, field_of(best), profit):
				f.cells.append(best)
				f.loss_streak = 0
				changed = true
		elif not f.get("rent", []).is_empty() and _buy_out(f, profit):
			changed = true
		elif best == Vector2i.MAX and expand.is_valid() and wants_road(id):
			# Its block is full and paying: time for a road to the next one.
			if expand.call(id):
				changed = true
	return changed


## True when farm `id` has filled what its open blocks hold, makes good money
## and would keep growing: then it builds a road to more land.
func wants_road(id: int) -> bool:
	var f: Dictionary = farms[id]
	if f.cells.size() >= MAX_CELLS or buy_margin(id) == INF or day < float(f.get("road_wait", 0.0)):
		return false
	if not f.get("pending", {}).is_empty():
		return true  # a road it asked the player for
	var profit := yearly_profit(id)
	if profit < Balance.FARM_ROAD_MIN_PROFIT:
		return false
	# It only opens more land when it has saved enough to take on a field.
	if float(f.get("cash", 0.0)) < BLOCK.x / 4 * BLOCK.y * ACRES_PER_CELL * Balance.CAPITAL_OPEN_PER_ACRE:
		return false
	# Full: most of its open blocks are planted (woods, creeks and the
	# farmyard leave the rest).
	var room := 0
	for b in f.blocks:
		room += BLOCK.x * BLOCK.y
	return f.cells.size() >= room * 0.5


## Farm f works field k: one it owns or rents, or one it takes on now out
## of its savings (Capital). Most Indiana farms grow by renting ground
## (about half the state's cropland is rented); a farm buys when its savings
## and income can carry the loan. Either way taking on a field costs the
## equipment and a season's inputs for it up front. Ground near town whose
## owner is holding it for developers isn't rented out, and selling it costs
## its development price, so a growing town can price a farm out. False,
## saying why, when it can't.
func _buy(f: Dictionary, k: Vector2i, profit: float) -> bool:
	if not f.has("own"):
		f.own = start_fields()
	if not f.has("rent"):
		f.rent = []
	if k in f.own or k in f.rent:
		return true
	var price := field_price(f, k)
	var acres := field_cells(f, k).size() * ACRES_PER_CELL
	var per_acre := price / acres
	var start := acres * Balance.CAPITAL_OPEN_PER_ACRE
	var cash := float(f.get("cash", 0.0))
	var income := Capital.kept(f, "farm", Capital.steady(f, profit) + field_gain(f, k))
	if cash >= Capital.cash_needed(f, price, income) + start + Balance.CAPITAL_RESERVE:
		var put := Capital.cash_needed(f, price, income)
		Capital.buy(f, price, income)
		f.cash = float(f.cash) - start
		f.own.append(k)
		f.why = "It bought %d more acres for $%s ($%s an acre), $%s down out of its savings." % [roundi(acres),
			CitySim.money_text(roundi(price)), CitySim.money_text(roundi(per_acre)), CitySim.money_text(roundi(put))]
		return true
	if per_acre > Balance.CAPITAL_LAND_PER_ACRE * (1.0 + Balance.CAPITAL_RENT_MAX_PREMIUM):
		f.why = "Land next door sells for $%s an acre with the town so close: its owner won't rent it out, and the farm can't afford to buy it." % \
			CitySim.money_text(roundi(per_acre))
		return false
	if cash < start:
		f.why = "It's saving to rent the next %d acres: $%s for equipment and a season's seed and fertiliser (it has $%s)." % [
			roundi(acres), CitySim.money_text(roundi(start)), CitySim.money_text(roundi(maxf(cash, 0.0)))]
		return false
	f.cash = cash - start
	f.rent.append(k)
	f.why = "It rented %d more acres from a neighbour and put $%s of its savings into equipment and inputs for them." % [
		roundi(acres), CitySim.money_text(roundi(start))]
	return true


## A farm with savings to spare buys a field it rents from its landowner
## (Capital), and keeps all it makes there after. True when it bought.
func _buy_out(f: Dictionary, profit: float) -> bool:
	for k in f.get("rent", []):
		var price := field_price(f, k)
		var income := Capital.kept(f, "farm", Capital.steady(f, profit) + field_gain(f, k) * Balance.CAPITAL_RENT_SHARE)
		if float(f.get("cash", 0.0)) < Capital.cash_needed(f, price, income) + Balance.CAPITAL_RESERVE:
			continue
		var acres := field_cells(f, k).size() * ACRES_PER_CELL
		Capital.buy(f, price, income)
		f.rent.erase(k)
		f.own.append(k)
		f.why = "It bought the %d acres it rented, for $%s ($%s an acre)." % [roundi(acres),
			CitySim.money_text(roundi(price)), CitySim.money_text(roundi(price / acres))]
		return true
	return false


## What field k would add to farm f's yearly profit, planted whole in the
## crop it pays best in.
func field_gain(f: Dictionary, k: Vector2i) -> float:
	var best := 0.0
	for crop in CropPlan.CROPS:
		var total := 0.0
		for c in field_cells(f, k):
			total += field_profit(f, c, crop)
		best = maxf(best, total)
	return best


## The field a farm would buy next: the best paying free one next to its
## land, or Vector2i.MAX if none pays or it has all it will ever farm.
func best_field(id: int, usable: Callable) -> Vector2i:
	var f: Dictionary = farms[id]
	# Town aid or fees count, and Growth sets how much a field must pay.
	var sup := support(id)
	var margin := buy_margin(id)
	if f.cells.size() >= MAX_CELLS or margin == INF:
		return Vector2i.MAX
	# Farmers keep fields rectangular (Brawn: odd shapes are hard to work
	# with big equipment, so they only happen where they have to). A field
	# is half a forty (200 m across, square to the farm's road, about 20
	# acres) worked in whole rows: the farmer plants a row end to end, poor
	# spots and all, skipping only ground it can't work (woods, water,
	# steep banks, its lane, roads), and makes a field deeper a whole row
	# at a time. Soil only decides whether a field pays as a whole.
	var rows := _rows(f)
	var keys := rows.keys()
	keys.sort_custom(_less)
	var owned := {}
	for c in f.cells:
		owned[c] = true
	# Finish planting the field it has started first.
	var started := _planting(id, f, rows, usable)
	if started != Vector2i.MAX:
		return started
	var best := Vector2i.MAX
	var best_score := -INF
	# Then one more row across a field it works, front or back, while the
	# field as a whole still pays with it (poor spots and all) ...
	for k in keys:
		var lo: int = rows[k].min()
		var hi: int = rows[k].max()
		for y in [lo - 1, hi + 1]:
			if not y in forty_rows(f, k):
				continue
			var plan := _field_plan(id, f, k, [y], owned, usable)
			if plan.next.size() < MIN_ROW_CELLS or plan.avg + sup <= margin:
				continue
			var score: float = plan.avg + EXTEND_BONUS + (RESERVE_BONUS if plan.reserved else 0.0)
			if score > best_score:
				best_score = score
				best = _nearest(plan.next)
	# ... or a new field beside its land, started at its front, the rows
	# nearest the farmyard's road (past any ground it can't work), when
	# those first rows would pay as one field.
	for k in _next_fields(f, rows):
		var ys := []
		for y in forty_rows(f, k):
			if row_cells(f, k, y).filter(func(c): return _free(id, f, c, usable)).size() >= MIN_ROW_CELLS:
				ys.append(y)
				if ys.size() == OPEN_ROWS:
					break
		if ys.is_empty():
			continue
		var plan := _field_plan(id, f, k, ys, owned, usable)
		# A new farm's first field has to pay, whatever it's told.
		if plan.avg + sup <= (maxf(margin, 0.0) if f.cells.is_empty() else margin):
			continue
		var score: float = plan.avg + (RESERVE_BONUS if plan.reserved else 0.0)
		if score > best_score:
			best_score = score
			best = _nearest(row_cells(f, k, ys[0]).filter(func(c): return _free(id, f, c, usable)))
	return best


## The next cell of a field farm f is part way through planting (a started
## row, or the rows a new field was opened on), or Vector2i.MAX. A farmer
## plants a field through once it starts, whatever the year looks like.
func _planting(id: int, f: Dictionary, rows: Dictionary, usable: Callable) -> Vector2i:
	var keys := rows.keys()
	keys.sort_custom(_less)
	var owned := {}
	for c in f.cells:
		owned[c] = true
	for k in keys:
		for y in rows[k]:
			var left := []
			for c in row_cells(f, k, y):
				if not owned.has(c) and _free(id, f, c, usable):
					left.append(c)
			if not left.is_empty():
				return _nearest(left)
		# A new field is planted to its opening depth as one, the rows it
		# was judged on, before anything else.
		if rows[k].size() < OPEN_ROWS:
			for y in forty_rows(f, k):
				if y <= rows[k].max():
					continue
				var left := row_cells(f, k, y).filter(func(c): return _free(id, f, c, usable))
				if left.size() >= MIN_ROW_CELLS:
					return _nearest(left)
	return Vector2i.MAX


## Of a row's cells, the one nearest the farmyard's side: a farmer plants a
## row from the end nearest the barn.
static func _nearest(cells: Array) -> Vector2i:
	var out: Vector2i = cells[0]
	for c in cells:
		if absi(c.x) < absi(out.x):
			out = c
	return out


## The rows each field of farm f has planted: field -> sorted rows.
static func _rows(f: Dictionary) -> Dictionary:
	var out := {}
	for c in f.cells:
		var k := field_of(c)
		if not out.has(k):
			out[k] = []
		if not c.y in out[k]:
			out[k].append(c.y)
	for k in out:
		out[k].sort()
	return out


## Rows `ys` of field k, planted with what farm f already works there: the
## cells it can still plant in those rows, the average yearly profit per
## cell over the lot, and whether the player reserved it for farming.
func _field_plan(id: int, f: Dictionary, k: Vector2i, ys: Array, owned: Dictionary, usable: Callable) -> Dictionary:
	var out := {"next": [], "avg": -INF, "reserved": false}
	var mine := []
	for c in f.cells:
		if field_of(c) == k:
			mine.append(c)
	for y in ys:
		for c in row_cells(f, k, y):
			if not owned.has(c) and _free(id, f, c, usable):
				out.next.append(c)
	var n: int = mine.size() + out.next.size()
	if n > 0:
		var kept := 0.0
		for c in mine:
			kept += field_profit(f, c)
		# New ground is judged on the grain that would pay best there (the
		# leader picks the crops each year, CropPlan).
		for crop in CropPlan.CROPS:
			var total := kept
			for c in out.next:
				total += field_profit(f, c, crop)
			out.avg = maxf(out.avg, total / n)
		if reserves != null and not out.next.is_empty():
			out.reserved = reserves.kind_at(cell_center(f, out.next[0])) == "farm"
	return out


## The rows of field k in farm f's frame: the half of its block it
## lies in, on the farm's side of its road.
static func forty_rows(f: Dictionary, k: Vector2i) -> Array:
	if k.y == 0:
		return range(front_row(f), BLOCK.y)
	return range(k.y * (BLOCK.y + 1), k.y * (BLOCK.y + 1) + BLOCK.y)


## The cells of one row across field k.
static func row_cells(f: Dictionary, k: Vector2i, y: int) -> Array:
	var bx := floori(k.x / 4.0)
	var x0 := bx * (BLOCK.x + 1) - BLOCK.x / 2 + (k.x - bx * 4) * (BLOCK.x / 4)
	var out := []
	for x in range(x0, x0 + BLOCK.x / 4):
		if Vector2i(x, y) != Vector2i.ZERO:
			out.append(Vector2i(x, y))
	return out


## Every cell of field k, front row first.
static func field_cells(f: Dictionary, k: Vector2i) -> Array:
	var out := []
	for y in forty_rows(f, k):
		out.append_array(row_cells(f, k, y))
	return out


## Fields next to the ones a farm works (or its farmyard's), in blocks it
## has opened, that it hasn't started.
static func _next_fields(f: Dictionary, started: Dictionary) -> Array:
	var blocks: Array = f.get("blocks", [Vector2i.ZERO])
	var out := []
	if started.is_empty():
		return [field_of(Vector2i(-1, 0)), field_of(Vector2i.ZERO)]
	var from := started.keys()
	for k in from:
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if n.y < 0 or started.has(n) or n in out:
				continue
			if Vector2i(floori(n.x / 4.0), n.y) in blocks:
				out.append(n)
	out.sort_custom(_less)
	return out


## Can farm `id` plant cell c: farmland, clear of its lane, other farms and
## anything the city has built?
func _free(id: int, f: Dictionary, c: Vector2i, usable: Callable) -> bool:
	# Its own livestock barns stand there (Livestock).
	if f.has("stock") and c in Livestock.site_cells(f):
		return false
	var mid := cell_center(f, c)
	# Land has one owner (Brawn): not on a company's pads, the ground around
	# them or its leases.
	if land_free.is_valid():
		var probe := [mid]
		for q in cell_corners(f, c):
			probe.append(mid.lerp(Vector3(q.x, 0.0, q.y), 0.9))
		if not land_free.call(probe, "farm:%d" % id):
			return false
	if not reserved_ok(mid):
		return false
	var corners := cell_corners(f, c)
	if _drive_crosses(f, corners):
		return false
	for other in farms:
		if other == id:
			continue
		var o: Dictionary = farms[other]
		if o.pos.distance_to(mid) > CELL * (sqrt(float(o.cells.size())) * 2.0 + 4.0) + MAX_DRIVE:
			continue
		var inset := PackedVector2Array()
		for p in corners:
			inset.append(Vector2(mid.x, mid.z).lerp(p, 0.8))
		inset.append(Vector2(mid.x, mid.z))
		for q in inset:
			var pt := Vector3(q.x, 0.0, q.y)
			if field_at(pt) == other or farm_at(pt) == other:
				return false
	return usable.call(mid, corners)


## False on land the player saved for another industry.
func reserved_ok(p: Vector3) -> bool:
	return reserves == null or reserves.kind_at(p) in ["", "farm"]


static func _owned_neighbors(f: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if (c + d) in f.cells or c + d == Vector2i.ZERO:
			n += 1
	return n


static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## A point in the farm's own frame: x to the right, y back from the road.
static func _local(f: Dictionary, p: Vector3) -> Vector2:
	var d: Vector3 = p - f.pos
	return Vector2(d.dot(_right(f)), -d.dot(f.dir))


func _yard(f: Dictionary) -> PackedVector2Array:
	var side := _right(f)
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = f.pos + side * FARMHOUSE_SIZE.x * 0.5 * s.x + f.dir * FARMHOUSE_SIZE.y * 0.5 * s.y
		out.append(Vector2(p.x, p.z))
	return out


static func _near_drive(f: Dictionary, p: Vector3, reach: float) -> bool:
	var drive: Array = f.drive
	var q := Vector2(p.x, p.z)
	for i in drive.size() - 1:
		var a := Vector2(drive[i].x, drive[i].z)
		var b := Vector2(drive[i + 1].x, drive[i + 1].z)
		if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < reach:
			return true
	return false


## True when the farm's lane runs through (or right beside) a field cell.
static func _drive_crosses(f: Dictionary, corners: PackedVector2Array) -> bool:
	var grown := PackedVector2Array()
	var mid := (corners[0] + corners[2]) * 0.5
	for p in corners:
		grown.append(mid + (p - mid) * (1.0 + (DRIVE_WIDTH + 2.0) / CELL))
	var drive: Array = f.drive
	for i in drive.size():
		if Geometry2D.is_point_in_polygon(Vector2(drive[i].x, drive[i].z), grown):
			return true
	return false


static func _hash01(i: Vector2i, salt: int) -> float:
	return Resources.hash01(i, salt)


func to_dict() -> Dictionary:
	var fs := {}
	for id in farms:
		var f: Dictionary = farms[id]
		var owned := []
		for c in f.cells:
			owned.append([c.x, c.y])
		var lane := []
		for p in f.drive:
			lane.append([p.x, p.z])
		fs[str(id)] = {"pos": [f.pos.x, f.pos.z], "dir": [f.dir.x, f.dir.z], "crop": f.crop,
			"cells": owned, "loss": f.loss_streak, "barn": f.barn, "drive": lane, "frame": 2,
			"leader": f.get("leader", {}), "built": f.get("built", []), "why": f.get("why", ""),
			"blocks": f.get("blocks", [Vector2i.ZERO]).map(func(b): return [b.x, b.y]),
			"road_wait": f.get("road_wait", 0.0), "pending": f.get("pending", {}),
			"plan_year": f.get("plan_year", 0), "fields": _fields_out(f), "stock": Livestock.to_save(f),
			"own": f.get("own", start_fields()).map(func(k): return [k.x, k.y]),
			"rent": f.get("rent", []).map(func(k): return [k.x, k.y]), "capital": Capital.save(f),
			"sale": f.get("sale", {}), "sale_year": f.get("sale_year", 0)}
	return {"farms": fs, "next_id": _next_id}


## Each field's crop record as [x, y, crop, prev, years, health, cover, cover_prev, why].
static func _fields_out(f: Dictionary) -> Array:
	var out := []
	var keys: Array = f.get("fields", {}).keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = f.fields[k]
		out.append([k.x, k.y, r.crop, r.prev, r.years, r.health, r.cover, r.cover_prev, r.why])
	return out


func from_dict(d: Dictionary) -> void:
	farms.clear()
	# Older saves painted farmland: it becomes land reserved for farming.
	legacy_outlines.clear()
	for a in d.get("outlines", []):
		var pts := []
		for p in a.points:
			pts.append(Vector3(p[0], 0.0, p[1]))
		legacy_outlines.append([pts, "farm" if a.on else ""])
	for c in d.get("area", []):
		var x := float(c[0]) * CELL
		var z := float(c[1]) * CELL
		legacy_outlines.append([[Vector3(x, 0, z), Vector3(x + CELL, 0, z), Vector3(x + CELL, 0, z + CELL),
			Vector3(x, 0, z + CELL)], "farm"])
	for k in d.get("farms", {}):
		var f: Dictionary = d.farms[k]
		var owned := []
		# Fields from before farms had their own frame start over.
		if int(f.get("frame", 1)) == 2:
			for c in f.cells:
				owned.append(Vector2i(int(c[0]), int(c[1])))
		var lane := []
		for p in f.get("drive", []):
			lane.append(Vector3(p[0], 0.0, p[1]))
		farms[int(k)] = {"pos": Vector3(f.pos[0], 0.0, f.pos[1]),
			"dir": Vector3(f.dir[0], 0.0, f.dir[1]).normalized(), "crop": str(f.crop),
			"cells": owned, "loss_streak": int(f.get("loss", 0)), "barn": bool(f.get("barn", true)),
			"drive": lane, "built": Array(f.get("built", [])), "why": str(f.get("why", "")),
			"road_wait": float(f.get("road_wait", 0.0)), "pending": Dictionary(f.get("pending", {})),
			"plan_year": int(f.get("plan_year", 0)), "fields": {}}
		for r in f.get("fields", []):
			farms[int(k)].fields[Vector2i(int(r[0]), int(r[1]))] = {"crop": str(r[2]), "prev": str(r[3]),
				"years": int(r[4]), "health": float(r[5]), "cover": bool(r[6]), "cover_prev": bool(r[7]), "why": str(r[8])}
		# Farms from before blocks keep every field they had.
		var blocks := [Vector2i.ZERO]
		for b in f.get("blocks", []):
			if not Vector2i(int(b[0]), int(b[1])) in blocks:
				blocks.append(Vector2i(int(b[0]), int(b[1])))
		for c in owned:
			if not block_of(c) in blocks:
				blocks.append(block_of(c))
		farms[int(k)].blocks = blocks
		if not f.get("leader", {}).is_empty():
			farms[int(k)].leader = f.leader
		if not f.get("stock", {}).is_empty():
			farms[int(k)].stock = Livestock.from_save(f.stock)
		# Older saves: the farm owns what it works, and starts saving now.
		var own := start_fields()
		for o in f.get("own", []):
			if not Vector2i(int(o[0]), int(o[1])) in own:
				own.append(Vector2i(int(o[0]), int(o[1])))
		for c in owned:
			if not field_of(c) in own:
				own.append(field_of(c))
		farms[int(k)].own = own
		farms[int(k)].rent = Array(f.get("rent", [])).map(func(r): return Vector2i(int(r[0]), int(r[1])))
		for r in farms[int(k)].rent:
			own.erase(r)
		farms[int(k)].sale = Dictionary(f.get("sale", {}))
		farms[int(k)].sale_year = int(f.get("sale_year", 0))
		if f.has("capital"):
			Capital.load(farms[int(k)], f.capital)
		else:
			Capital.start(farms[int(k)], "farm")
	_next_id = int(d.get("next_id", 1))
