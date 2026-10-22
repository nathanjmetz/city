class_name CitySim
extends RefCounted
## The whole city as plain data, stepped in fixed ticks.
##
## Every player action is a command Dictionary passed to apply(), and the
## simulation only changes inside apply() and tick(). Given the same commands
## in the same order, every copy ends up in the same state, so a headless
## server can run this exact class later and send commands to players.

signal buildings_changed
signal lots_changed
## Buildings removed because a road now runs through their lot (for refunds).
signal parcels_lost(keys: Array)
signal zones_changed
## Population, jobs or demand changed (at most every MOVE_EVERY ticks).
signal stats_changed
## Farmland or a farm's fields changed.
signal farms_changed
## A resource company opened, closed, or added or dropped a pad.
signal industry_changed
## A warehouse was built, grew, shrank or went away.
signal warehouses_changed
## A park or landmark was placed, filled in, grew, changed tier or went away.
signal parks_changed
## A player command went through (sounds and other feedback listen to this).
signal command_applied(cmd: Dictionary)

const TICKS_PER_SECOND := 10
## A new building can start every this many ticks.
const GROW_EVERY := Balance.GROW_EVERY
## People move in and stats update every this many ticks.
const MOVE_EVERY := Balance.MOVE_EVERY
## Game minutes per tick: at normal speed a day takes 2.4 real minutes.
const MINUTES_PER_TICK := 1
## Tick 0 is 6:00 AM on Monday, January 4, 2027.
const START_UNIX := 1799042400
## Share of residents who work (US labour force is about half of everyone).
const WORKER_SHARE := Balance.WORKER_SHARE
const TICKS_PER_HOUR := 60 / MINUTES_PER_TICK

var network := RoadNetwork.new()
var zones := ZoneMap.new()
var traffic := TrafficSim.new(network)
var economy := Economy.new()
var services := Services.new()
var farms := Farms.new()
## Oil, mining and forestry companies (Brawn's model: a main building whose
## pads spread to where the resource is).
var industry := Industry.new()
## Warehouses that buffer loads between them (hubs that grow in place).
var warehouses := Warehouses.new()
## The trucks that carry every load (grain, crude, ore, logs, goods).
var logistics := Logistics.new()
## Land saved for farming or an industry: no roads or zoning on it.
var reserves := Reserves.new()
## Requests from hub leaders for big moves (track through town, crossing
## your roads), answered from the bell up top. See Permits.
var permits := Permits.new()
## Wild trees and brush, and how far cleared land has grown back.
var vegetation := Vegetation.new()
## Landfills, recycling and cemeteries, and the garbage trucks' rounds.
var hubs := CivicHubs.new()
## Parks (hubs that fill in by themselves) and one-per-town landmarks.
var parks := Parks.new()
## Buildings only grow and fill with power and water, as in Cities: Skylines.
## The game turns this on; tests about other things can leave it off.
var require_utilities := false
## The balance harness turns cars off to play years of a city in seconds
## (traffic doesn't touch the budget yet).
var simulate_traffic := true
var lots := {}       # lot key -> lot Dictionary (from LotPlanner)
## Surveys lots from the roads and zones; lots with buildings are saved
## parcels that stay put.
var planner := LotPlanner.new()
var buildings := {}  # lot key -> {"zone", "seed", "built", "cap", "occ"}
var tick_count := 0
var city_seed := 1

## Latest totals, worked out from the buildings.
var stats := {"population": 0, "workers": 0, "jobs": 0, "employed": 0, "homes_free": 0}
## How much each zone wants to grow, 0 to 1, like the CS demand bars.
var demand := {ZoneMap.Zone.RESIDENTIAL: 0.6, ZoneMap.Zone.COMMERCIAL: 0.0, ZoneMap.Zone.INDUSTRIAL: 0.1}

## In a shared region, your commands go to the server instead and come back
## in a tick, so every player applies them at the same moment.
var send_command := Callable()

## Road ends that lead on to the rest of the region (there's no map edge):
## the county highway's far ends. Trade, imports and through traffic come
## and go here, and nowhere else. Node ids.
var region_links: Array = []
## Goods and services bought from and sold to neighbors and the outside.
var trade := Trade.new()
## True in a shared region, which settles trade for every city at once.
var in_region := false

var _lots_dirty := true
## Roads changed since the world last made way for them (see RoadWins).
var _roads_moved := false
var _usable_cache := {}  # field cell -> bool, cleared when roads or lots change


func _init() -> void:
	planner.wealth = wealth_at
	farms.reserves = reserves
	industry.reserves = reserves
	network.changed.connect(func():
		_lots_dirty = true
		_roads_moved = true)
	vegetation.watch(self)


## Applies one player command. Returns true if anything changed (online:
## true once it's sent).
func apply(cmd: Dictionary) -> bool:
	if send_command.is_valid():
		send_command.call(cmd)
		return true
	return apply_now(cmd)


## Applies a command right away, even online (the region does this).
func apply_now(cmd: Dictionary) -> bool:
	var ok := false
	match cmd.get("type", ""):
		"build_road":
			var c := [_v(cmd.start), _v(cmd.ctrl), _v(cmd.end)]
			# The server checks real road rules too, not just the player's screen.
			if road_problem(c, _road(cmd)) == "":
				ok = network.build_road(c[0], c[1], c[2], _road(cmd))
				if ok:
					economy.money -= Economy.road_cost(c, _road(cmd))
		"build_grid", "build_grid_shape":
			# Old three-click grids are a rectangle; new ones any shape.
			var shape: Array = GridFill.rect(_v(cmd.a), _v(cmd.b), _v(cmd.c)) if cmd.type == "build_grid" \
				else cmd.points.map(_v)
			var lines := GridFill.plan(network, shape, float(cmd.block), _road(cmd), int(cmd.get("side", 0)))
			if shape.size() == 2:
				lines = [[shape[0], shape[0].lerp(shape[1], 0.5), shape[1]]]
			if lines.is_empty() or not _can_afford(lines, _road(cmd)):
				return false
			network.begin_batch()
			for l in lines:
				ok = network.build_road(l[0], l[1], l[2], _road(cmd)) or ok
			network.end_batch()
			if ok:
				economy.money -= shapes_cost(lines, _road(cmd))
		"build_roundabout":
			var ring := RoadStyle.ring_type(_road(cmd))
			var radius := RoadShapes.roundabout_radius(float(cmd.radius), _road(cmd))
			var arcs := RoadShapes.roundabout(_v(cmd.center), radius)
			if not _can_afford(arcs, ring):
				return false
			ok = _build_roundabout(_v(cmd.center), radius, ring)
			if ok:
				economy.money -= shapes_cost(arcs, ring)
		"upgrade_road":
			var cost := upgrade_cost(int(cmd.seg), _road(cmd))
			if network.segments.has(int(cmd.seg)) and (RoadStyle.is_ring(network.segments[int(cmd.seg)].type)
					or RoadStyle.is_ring(_road(cmd))):
				return false  # rings change only by rebuilding the roundabout
			if cost < 0 or cost > economy.money:
				return false
			ok = network.set_type(int(cmd.seg), _road(cmd))
			if ok:
				economy.money -= cost
		"place_service":
			var kind := int(cmd.kind)
			if not Services.KINDS.has(kind):
				return false
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			var cost: int = Services.KINDS[kind].cost
			if cost > economy.money or services.site_problem(network, kind, pos, dir) != "" \
					or _on_warehouse(Services.corners(kind, pos, dir)) \
					or parks.overlaps(Services.corners(kind, pos, dir).map(func(q): return Vector2(q.x, q.z))):
				return false
			var sid := services.add(kind, pos, dir)
			economy.money -= cost
			_clear_zones_under(services.footprint(sid))
			_lots_dirty = true
			ok = true
		"paint_reserve", "paint_farmland":
			# Older clients sent paint_farmland {points, on}.
			var pts := []
			for p in cmd.points:
				pts.append(_v(p))
			var kind := str(cmd.get("kind", "farm" if bool(cmd.get("on", true)) else ""))
			ok = reserves.paint(pts, kind)
			if ok:
				_lots_dirty = true
				_usable_cache.clear()
				_clear_reserved_zones()
				zones_changed.emit()
				farms_changed.emit()
				farms_changed.emit()
		"place_farmhouse":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if dir.length() < 0.5 or farmhouse_problem(pos, dir) != "" or Farms.FARMHOUSE_COST > economy.money:
				return false
			farms.add_farm(pos, dir, str(cmd.get("crop", "corn")), farm_drive(pos, dir))
			economy.money -= Farms.FARMHOUSE_COST
			_lots_dirty = true
			farms_changed.emit()
			ok = true
		"place_industry":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Industry.KINDS.has(kind) or dir.length() < 0.5 or industry_problem(kind, pos, dir) != "" \
					or int(Industry.KINDS[kind].cost) > economy.money:
				return false
			industry.add_site(kind, pos, dir, industry_drive(pos, dir))
			economy.money -= int(Industry.KINDS[kind].cost)
			_lots_dirty = true
			industry_changed.emit()
			ok = true
		"place_warehouse":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Warehouses.KINDS.has(kind) or dir.length() < 0.5 or warehouse_problem(kind, pos, dir) != "" \
					or int(Balance.WAREHOUSE[kind].cost) > economy.money:
				return false
			var wid := warehouses.add(kind, pos, dir)
			economy.money -= int(Balance.WAREHOUSE[kind].cost)
			_clear_zones_under(warehouses.footprint(wid))
			_lots_dirty = true
			warehouses_changed.emit()
			ok = true
		"remove_warehouse":
			ok = warehouses.buildings.has(int(cmd.id))
			warehouses.buildings.erase(int(cmd.id))
			_lots_dirty = true
			warehouses_changed.emit()
		"remove_industry":
			ok = industry.sites.has(int(cmd.id))
			industry.sites.erase(int(cmd.id))
			_lots_dirty = true
			industry_changed.emit()
		"remove_farm":
			ok = farms.farms.has(int(cmd.id))
			farms.farms.erase(int(cmd.id))
			_lots_dirty = true
			farms_changed.emit()
		"place_park":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Parks.KINDS.has(kind) or dir.length() < 0.5 or Parks.cost_of(kind) > economy.money \
					or parks.site_problem(self, kind, pos, dir) != "":
				return false
			var pid := parks.add(self, kind, pos, dir)
			economy.money -= Parks.cost_of(kind)
			_clear_zones_under(parks.footprint(pid))
			_lots_dirty = true
			parks_changed.emit()
			ok = true
		"remove_park":
			ok = parks.sites.has(int(cmd.id))
			parks.sites.erase(int(cmd.id))
			_lots_dirty = true
			parks_changed.emit()
		"remove_service":
			ok = services.buildings.has(int(cmd.id))
			services.buildings.erase(int(cmd.id))
			_lots_dirty = true
		"place_hub", "upgrade_hub", "remove_hub", "develop_hub":
			ok = _hub_command(cmd)
		"set_difficulty":
			# A city that hasn't started yet also gets that difficulty's start money.
			ok = economy.set_difficulty(str(cmd.difficulty), tick_count == 0 and network.segments.size() <= 2)
			if ok:
				update_stats()
			return ok
		"set_tax":
			if economy.set_tax(int(cmd.zone), float(cmd.rate)):
				update_stats()
			return true
		"build_county_road":
			ok = not _county_road(Vector2(cmd.a[0], cmd.a[1]), Vector2(cmd.b[0], cmd.b[1]), cmd.get("links", [])).has(-1)
		"remove_road":
			ok = network.segments.has(int(cmd.seg)) and not is_link_segment(int(cmd.seg))
			if ok:
				network.remove_segment(int(cmd.seg))
		"paint_zone":
			zones.paint(_v(cmd.center), float(cmd.radius), int(cmd.zone))
			_clear_reserved_zones(_v(cmd.center), float(cmd.radius) + ZoneMap.CELL)
			_usable_cache.clear()
			_lots_dirty = true
			ok = true
		"zone_frontage":
			# Zones a whole block face: one side of a street from junction to
			# junction ("both" does the other side too).
			if not network.segments.has(int(cmd.seg)):
				return false
			planner.update(network)
			var sides := [int(cmd.side)]
			if bool(cmd.get("both", false)):
				sides.append(-int(cmd.side))
			for side in sides:
				for part in frontage_chain(int(cmd.seg), side):
					_paint_frontage(part[0], part[1], int(cmd.zone))
			_clear_reserved_zones()
			_usable_cache.clear()
			_lots_dirty = true
			ok = true
		"permit":
			ok = permits.answer(self, cmd)
		"guide":
			# The player's word to a hub's leader (grow, hold off, pre-approve).
			ok = permits.guide(self, cmd)
		"set_junction":
			# Traffic lights, stop signs or none at a junction (-1 = automatic).
			ok = traffic.set_rule(int(cmd.node), int(cmd.rule))
		"clear":
			region_links.clear()
			trade = Trade.new()
			traffic.overrides.clear()
			network.clear()
			zones.cells.clear()
			planner = LotPlanner.new()
			planner.wealth = wealth_at
			var diff := economy.difficulty
			economy = Economy.new()
			economy.set_difficulty(diff, true)
			services = Services.new()
			farms = Farms.new()
			industry = Industry.new()
			logistics = Logistics.new()
			warehouses = Warehouses.new()
			reserves = Reserves.new()
			permits.from_dict({})
			hubs = CivicHubs.new()
			parks = Parks.new()
			parks_changed.emit()
			farms.reserves = reserves
			industry.reserves = reserves
			vegetation.reset()
			farms_changed.emit()
			industry_changed.emit()
			warehouses_changed.emit()
			ok = true
	if ok:
		if _roads_moved:
			_road_wins()
		_refresh()
		zones_changed.emit()
		command_applied.emit(cmd)
	return ok


## Saves from before region links: trucks used to leave by the dead end
## farthest from the middle of town, so a county highway now runs on from
## there 2 km toward the region, and its far end is the town's way out.
func _guess_link() -> void:
	if network.nodes.is_empty():
		return
	var mid := Vector3.ZERO
	for n in network.nodes:
		mid += network.nodes[n]
	mid /= network.nodes.size()
	var best := -1
	var best_d := -1.0
	var ids := network.nodes.keys()
	ids.sort()
	for n in ids:
		if network.segments_at(n).size() == 1 and network.nodes[n].distance_to(mid) > best_d + 0.01:
			best_d = network.nodes[n].distance_to(mid)
			best = n
	if best == -1:
		return
	var seg: Dictionary = network.segments[network.segments_at(best)[0]]
	var end: Vector3 = network.nodes[best]
	var out: Vector3 = end - seg.ctrl
	out.y = 0.0
	if out.length() < 0.1:
		out = end - mid
	out = out.normalized() * 2000.0
	_county_road(Vector2(end.x, end.z), Vector2(end.x + out.x, end.z + out.z), [1])


## The road wins (Brawn): whatever a new road runs through makes way for it.
## Buildings the player paid for are bulldozed and paid back, fields are
## trimmed to the road's edge, cut lanes find the nearest road again, and
## pads that are hit close (the company reopens them elsewhere).
func _road_wins() -> void:
	_roads_moved = false
	_usable_cache.clear()
	var corr := RoadWins.corridors(network, RoadWins.BUILDING_SLACK)
	var field_corr := RoadWins.corridors(network, RoadWins.VERGE)
	var ids := services.buildings.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, services.footprint(id)):
			economy.money += int(Services.KINDS[services.buildings[id].kind].cost)
			services.buildings.erase(id)
			_lots_dirty = true
	var lane_end := RoadStyle.right_of_way_half(RoadStyle.Type.BOULEVARD) + RoadWins.VERGE + 4.0
	ids = farms.farms.keys()
	ids.sort()
	farms.trim.clear()
	for id in ids:
		var f: Dictionary = farms.farms[id]
		if RoadWins.hits(corr, farms._yard(f)):
			economy.money += Farms.FARMHOUSE_COST
			farms.farms.erase(id)
			continue
		for c in f.cells.duplicate():
			var cell := Farms.cell_corners(f, c)
			if not RoadWins.hits(field_corr, cell):
				continue
			var left := RoadWins.clip(field_corr, cell)
			var kept := 0.0
			for piece in left:
				kept += RoadWins.area(piece)
			if kept < RoadWins.MIN_FIELD_SHARE * Farms.CELL * Farms.CELL:
				f.cells.erase(c)
			else:
				if not farms.trim.has(id):
					farms.trim[id] = {}
				farms.trim[id][c] = left
		if RoadWins.cuts(corr, f.drive, lane_end):
			var lane := farm_drive(f.pos, f.dir)
			if not lane.is_empty():
				f.drive = lane
	ids = industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = industry.sites[id]
		if RoadWins.hits(corr, industry._yard(s)):
			economy.money += int(Industry.KINDS[s.kind].cost)
			industry.sites.erase(id)
			continue
		for c in s.pads.duplicate():
			if RoadWins.hits(corr, Industry.pad_corners(s, c)):
				s.pads.erase(c)
		if RoadWins.cuts(corr, s.drive, lane_end):
			var lane := industry_drive(s.pos, s.dir)
			if not lane.is_empty():
				s.drive = lane
	ids = warehouses.buildings.keys()
	ids.sort()
	for id in ids:
		if not Warehouses.is_store(warehouses.buildings[id]) and RoadWins.hits(corr, warehouses.footprint(id)):
			economy.money += int(Balance.WAREHOUSE[warehouses.buildings[id].kind].cost)
			warehouses.buildings.erase(id)
			_lots_dirty = true
	if parks.road_wins(self, corr):
		_lots_dirty = true
		parks_changed.emit()
	farms_changed.emit()
	industry_changed.emit()
	warehouses_changed.emit()


func tick() -> void:
	tick_count += 1
	_refresh()
	vegetation.update(self)
	if tick_count % MOVE_EVERY == 0:
		_move_in()
		update_stats()
	if tick_count % GROW_EVERY == 0:
		_grow_one()
	if tick_count % Farms.DECIDE_EVERY == 0 and not farms.farms.is_empty():
		farms.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
		farms.price = Farms.price_on(tick_count / (24.0 * TICKS_PER_HOUR))
		if farms.decide(field_usable):
			_lots_dirty = true  # lots under new fields go away
			farms_changed.emit()
	if tick_count % Industry.DECIDE_EVERY == 0 and not industry.sites.is_empty():
		industry.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
		if industry.decide(field_usable):
			_lots_dirty = true
			industry_changed.emit()
	if tick_count % Balance.WAREHOUSE_DECIDE_EVERY == 0 and not warehouses.buildings.is_empty():
		if warehouses.decide(warehouse_ground_ok):
			_lots_dirty = true
			warehouses_changed.emit()
	permits.tick(self)
	if tick_count % Balance.PARK_DECIDE_EVERY == 0 and not parks.sites.is_empty():
		var sizes := parks.sites.values().map(func(s): return s.size)
		if parks.decide(self):
			if parks.sites.values().map(func(s): return s.size) != sizes:
				# A park bought land: lots and zoning under it go away.
				for id in parks.sites:
					_clear_zones_under(parks.footprint(id))
				_lots_dirty = true
				zones_changed.emit()
			parks_changed.emit()
	# Taxes come in and upkeep goes out every game hour, a day settling a month.
	if tick_count % TICKS_PER_HOUR == 0:
		economy.money += roundi(economy.monthly_net() / 24.0)
	# Before logistics, which clears Traffic's arrivals.
	hubs.tick(self)
	if not in_region and tick_count % (24 * TICKS_PER_HOUR) == 0:
		Trade.settle({"me": self}, {})
	if not simulate_traffic:
		return
	logistics.tick(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count, "traffic"])
	traffic.step(self, rng)


## Game time as a Dictionary (year, month, day, weekday, hour, minute).
## A game day settles a month, so the month and year follow Seasons.
func clock() -> Dictionary:
	var t := Time.get_datetime_dict_from_unix_time(START_UNIX + tick_count * MINUTES_PER_TICK * 60)
	t.month = Seasons.month(tick_count)
	t.year = Seasons.year(tick_count)
	return t


## Recounts people and jobs, then works out demand the way Cities: Skylines
## does in spirit: homes are wanted while there are jobs, jobs while people
## need work, and shops while residents need somewhere to shop.
func update_stats() -> void:
	var pop := 0
	var home_cap := 0
	var shop_jobs := 0
	var factory_jobs := 0
	for key in buildings:
		var b: Dictionary = buildings[key]
		match int(b.zone):
			ZoneMap.Zone.RESIDENTIAL:
				pop += b.occ
				home_cap += b.cap
			ZoneMap.Zone.COMMERCIAL:
				if _utilities_ok(key):  # closed without power or water
					shop_jobs += b.cap
			ZoneMap.Zone.INDUSTRIAL:
				if _utilities_ok(key):
					factory_jobs += b.cap
	services.update(network, lots, buildings)
	parks.update_effects(self)
	factory_jobs += farms.jobs() + industry.jobs() + warehouses.jobs()
	economy.reach_milestones(pop)
	var workers := int(pop * WORKER_SHARE)
	var jobs := shop_jobs + factory_jobs
	var free := home_cap - pop
	stats = {"population": pop, "workers": workers, "jobs": jobs,
		"employed": mini(workers, jobs), "homes_free": free}
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
		0.6 + 0.6 * float(jobs - workers) / maxf(workers, 40.0) - float(free) / maxf(home_cap, 30.0), 0.0, 1.0)
	demand[ZoneMap.Zone.COMMERCIAL] = clampf(
		0.05 + (pop * 0.12 - shop_jobs) / maxf(shop_jobs, 12.0), 0.0, 1.0)
	demand[ZoneMap.Zone.INDUSTRIAL] = clampf(
		0.1 + float(workers - jobs) / maxf(workers, 40.0)
		+ 0.4 * (shop_jobs * 0.8 - factory_jobs) / maxf(factory_jobs, 20.0), 0.0, 1.0)
	for z in demand:
		demand[z] = clampf(demand[z] + economy.demand_shift(z), 0.0, 1.0)
	# Past village size, people want fire, police, a clinic and a school nearby.
	if pop > 300:
		demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
			demand[ZoneMap.Zone.RESIDENTIAL] + 0.3 * (service_coverage() - 0.5), 0.0, 1.0)
	# Parks and landmarks make a town nicer to live in.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
		+ Balance.AMENITY_DEMAND * parks.average_happiness(self), 0.0, 1.0)
	economy.update_budget(self)
	stats_changed.emit()


## New residents move into homes with room, faster when homes are in demand.
func _move_in() -> void:
	# Without power or water, people move away (one household at a time).
	if require_utilities:
		for key in buildings:
			var home: Dictionary = buildings[key]
			if home.zone == ZoneMap.Zone.RESIDENTIAL and home.occ > 0 and not _utilities_ok(key):
				home.occ -= 1
	var arrivals := 1 + int(demand[ZoneMap.Zone.RESIDENTIAL] * 4.0)
	if demand[ZoneMap.Zone.RESIDENTIAL] <= 0.05:
		return
	var keys := buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
		if b.zone == ZoneMap.Zone.RESIDENTIAL and b.occ < b.cap and _utilities_ok(key):
			b.occ += 1
			arrivals -= 1
			if arrivals == 0:
				return


## Lots that are zoned but have nothing on them yet.
func empty_zoned_lots() -> Array:
	var out := []
	for key in lots:
		if not buildings.has(key) and zones.zone_at(lots[key].zone_pt) != ZoneMap.Zone.NONE \
				and _utilities_ok(key):
			out.append(key)
	out.sort()
	return out


## Why a farmhouse can't go here, or "" if it can: it needs farmland, clear
## ground and a road near enough for its lane.
func farmhouse_problem(pos: Vector3, dir: Vector3) -> String:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Farms.FARMHOUSE_SIZE.x * 0.5 * sgn.x + dir * Farms.FARMHOUSE_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
	if not farms.reserved_ok(pos):
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(pos)]
	if farm_drive(pos, dir).is_empty():
		return "Needs a road within %d m for its farm lane." % int(Farms.MAX_DRIVE)
	if Services.road_clash(network, poly):
		return "Too close to a road."
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for id in farms.farms:
		if farms.farms[id].pos.distance_to(pos) < Farms.FARMHOUSE_SIZE.length():
			return "Too close to another farm."
	for p in [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y)):
		if industry.covers(p):
			return "That ground belongs to a company."
	if _on_warehouse(Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y))):
		return "Overlaps a warehouse."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## Why a company's main building can't go here, or "" if it can: it needs
## the resource underground, clear ground and a road near enough for its lane.
func industry_problem(kind: String, pos: Vector3, dir: Vector3) -> String:
	var spec: Dictionary = Industry.KINDS[kind]
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Industry.HQ_SIZE.x * 0.5 * sgn.x + dir * Industry.HQ_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
	if not industry.reserved_ok(kind, pos):
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(pos)]
	if industry_reach(kind, pos) < Industry.MIN_RICHNESS:
		return "No %s near here. Open the %s view and build where it shows." % [spec.cargo,
			{"oil": "Oil", "ore": "Ore", "forest": "Forest"}[kind]]
	if industry_drive(pos, dir).is_empty():
		return "Needs a road within %d m for its access road." % int(Industry.MAX_DRIVE)
	if Services.road_clash(network, poly):
		return "Too close to a road."
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for p in [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y)):
		if farms.covers(p) or farms.field_at(p) != -1:
			return "That ground is farmland."
		if industry.covers(p):
			return "Too close to another company."
	if _on_warehouse(Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y))):
		return "Overlaps a warehouse."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## Why a warehouse can't go here, or "" if it can: it needs clear ground
## beside a street for its truck court and building.
func warehouse_problem(kind: String, pos: Vector3, dir: Vector3) -> String:
	var w := {"kind": kind, "pos": pos, "dir": dir, "bays": 0}
	var poly := Warehouses.corners(w)
	if reserves.kind_at(Warehouses.center(w)) != "":
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(Warehouses.center(w))]
	if Services.road_clash(network, poly):
		return "Too close to a road. A %s needs %d × %d m." % [Warehouses.KINDS[kind].name.to_lower(),
			roundi(Warehouses.site_width(w)), roundi(Warehouses.site_depth(w))]
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for id in warehouses.buildings:
		if not Geometry2D.intersect_polygons(poly, warehouses.footprint(id)).is_empty():
			return "Overlaps another warehouse."
	for p in _grid_in(poly):
		if farms.covers(p) or farms.field_at(p) != -1:
			return "That ground is farmland."
		if industry.covers(p):
			return "That ground belongs to a company."
		if hubs.covers(p):
			return "Overlaps a landfill, recycling center or cemetery."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## True when new ground for warehouse `id` is free: no road, building,
## farm, company, other warehouse, reserve, or zoned or built lot on it.
func warehouse_ground_ok(poly: PackedVector2Array, id: int) -> bool:
	if Services.road_clash(network, poly):
		return false
	for sid in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(sid)).is_empty():
			return false
	for wid in warehouses.buildings:
		if wid != id and not Geometry2D.intersect_polygons(poly, warehouses.footprint(wid)).is_empty():
			return false
	for p in _grid_in(poly):
		if farms.covers(p) or farms.field_at(p) != -1 or industry.covers(p) or reserves.kind_at(p) != "" \
				or hubs.covers(p):
			return false
	for key in lots:
		if not buildings.has(key) and zones.zone_at(lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue  # an empty, unzoned roadside lot can be bought
		if not Geometry2D.intersect_polygons(poly, lots[key].corners).is_empty():
			return false
	return true


## True when any of these points (or the area between them) is on a warehouse.
func _on_warehouse(pts: Array) -> bool:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x, p.z))
	for id in warehouses.buildings:
		if not Geometry2D.intersect_polygons(poly, warehouses.footprint(id)).is_empty():
			return true
	return false


## Sample points over a polygon, about every 10 m (corners and middle too).
static func _grid_in(poly: PackedVector2Array) -> Array:
	var out := []
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
		out.append(Vector3(q.x, 0.0, q.y))
	var step := 10.0
	var y := box.position.y + step * 0.5
	while y < box.end.y:
		var x := box.position.x + step * 0.5
		while x < box.end.x:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				out.append(Vector3(x, 0.0, y))
			x += step
		y += step
	return out


## The best the resource gets within reach of a main building (its pads
## spread up to about 400 m out).
func industry_reach(kind: String, pos: Vector3) -> float:
	var best := 0.0
	for r in [0.0, 120.0, 240.0, 360.0]:
		for i in (1 if r == 0.0 else 12):
			var a := TAU * i / 12.0
			best = maxf(best, Resources.at(Industry.KINDS[kind].resource, pos + Vector3(cos(a), 0.0, sin(a)) * r))
	return best


## The access road from a main building to the nearest public road, or [].
func industry_drive(pos: Vector3, dir: Vector3) -> Array:
	var near := network.find_segment_near(pos, Industry.MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	return Farms.make_drive(pos, dir, near.point)


## Places, upgrades or removes a landfill, recycling centre or cemetery.
func _hub_command(cmd: Dictionary) -> bool:
	if cmd.type == "place_hub":
		var kind := str(cmd.get("kind", ""))
		var pos := _v(cmd.pos)
		var dir := _v(cmd.dir).normalized()
		# Recycling starts as a drop-off yard; the bigger plants are upgrades.
		if not kind in CivicHubs.TOOL_KINDS.values() or dir.length() < 0.5:
			return false
		var cost := int(Balance.WASTE_SITES[kind].cost)
		if cost > economy.money or hubs.site_problem(self, kind, pos, dir) != "":
			return false
		var id := hubs.add(kind, pos, dir, tick_count)
		economy.money -= cost
		for c in hubs.hubs[id].cells:
			_clear_zones_under(CivicHubs.cell_poly(hubs.hubs[id], c))
	elif cmd.type == "upgrade_hub":
		var id := int(cmd.id)
		if not hubs.hubs.has(id):
			return false
		var cost := CivicHubs.upgrade_cost(hubs.hubs[id].kind)
		if cost <= 0 or cost > economy.money or not hubs.upgrade(id):
			return false
		economy.money -= cost
	elif cmd.type == "develop_hub":
		# Adds a building or option from the hub's development tree.
		return hubs.develop(self, int(cmd.id), str(cmd.get("dev", "")))
	else:
		if not hubs.remove(int(cmd.id)):
			return false
	_lots_dirty = true
	return true


## Zoning under a new building goes away, as in Cities: Skylines 2.
func _clear_zones_under(poly: PackedVector2Array) -> void:
	for c in zones.cells.keys():
		if Geometry2D.is_point_in_polygon(Vector2((c.x + 0.5) * ZoneMap.CELL, (c.y + 0.5) * ZoneMap.CELL), poly):
			zones.erase_cell(c)


## Zoning never stays on reserved land.
func _clear_reserved_zones(near := Vector3.INF, reach := 0.0) -> void:
	if reserves.outlines.is_empty():
		return
	for c in zones.cells.keys():
		if near != Vector3.INF and Vector2((c.x + 0.5) * ZoneMap.CELL - near.x, (c.y + 0.5) * ZoneMap.CELL - near.z).length() > reach:
			continue
		if reserves.kind_at(Vector3((c.x + 0.5) * ZoneMap.CELL, 0.0, (c.y + 0.5) * ZoneMap.CELL)) != "":
			zones.erase_cell(c)


## The gravel lane from a farmhouse to the nearest road, or [] if no road is
## near enough.
func farm_drive(pos: Vector3, dir: Vector3) -> Array:
	var near := network.find_segment_near(pos, Farms.MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	return Farms.make_drive(pos, dir, near.point)


## True when ground for a field is clear: no road, lot, service or farmyard.
func field_usable(mid: Vector3, corners: PackedVector2Array) -> bool:
	var key := Vector2i(roundi(mid.x), roundi(mid.z))
	if _usable_cache.has(key):
		return _usable_cache[key]
	var ok := network.find_segment_near(mid, Farms.CELL * 0.6 + RoadStyle.right_of_way_half(RoadStyle.Type.AVENUE), 2.0).is_empty()
	var pts := [mid]
	for c in corners:
		pts.append(mid.lerp(Vector3(c.x, 0.0, c.y), 0.8))
	if ok:
		for p in pts:
			if services.covers(p) or farms.covers(p) or industry.covers(p) or farms.field_at(p) != -1 \
					or hubs.covers(p) or warehouses.covers(p) or parks.covers(p):
				ok = false
	if ok:
		for key2 in lots:
			# Fields can take empty roadside lots, but not zoned or built ones.
			if not buildings.has(key2) and zones.zone_at(lots[key2].zone_pt) == ZoneMap.Zone.NONE:
				continue
			if lots[key2].pos.distance_to(mid) < Farms.CELL * 0.71 + 16.0:
				ok = false
				break
	_usable_cache[key] = ok
	return ok


## Average share of fire, police, health and school cover across homes.
func service_coverage() -> float:
	var total := 0.0
	var n := 0
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			total += services.coverage(key)
			n += 1
	return 0.0 if n == 0 else total / n


## What keeps the town from growing for want of power or water, in plain
## words (what's missing, why, and what to build), or "" if nothing does.
func utility_problem() -> String:
	return _utility_report()[1]


## The same, short enough for the top bar: "No power ($20,366 short)" or
## "74 lots: no power · 71: no water".
func utility_summary() -> String:
	return _utility_report()[0]


func _utility_report() -> Array:
	var zoned := []
	for key in lots:
		if zones.zone_at(lots[key].zone_pt) != ZoneMap.Zone.NONE:
			zoned.append(key)
	if zoned.is_empty():
		return ["", ""]
	for u in ["power", "water"]:
		var has_source := false
		for id in services.buildings:
			has_source = has_source or services.buildings[id].kind in Services.UTILITIES[u]
		if not has_source:
			var starter: int = Services.Kind.POWER_FEED if u == "power" else Services.Kind.WELL
			var cost: int = Services.KINDS[starter].cost
			var full := "No %s: build a %s in Services ($%s)" % [u, Services.KINDS[starter].name, money_text(cost)]
			var short := "No %s" % u
			if cost > economy.money:
				full += ". You need $%s more" % money_text(cost - economy.money)
				short += " ($%s short)" % money_text(cost - economy.money)
			return [short, full]
	# Count zoned lots each utility misses, and why.
	var missing := {"power": 0, "water": 0}
	var unlinked := {"power": 0, "water": 0}
	for key in zoned:
		var s: Dictionary = services.served.get(key, {})
		for u in missing:
			if not s.get(u, false):
				missing[u] += 1
				if not s.get(u + "_linked", false):
					unlinked[u] += 1
	var shorts := []
	var fulls := []
	for u in ["power", "water"]:
		if missing[u] == 0:
			continue
		shorts.append("%d lots: no %s" % [missing[u], u] if shorts.is_empty() else "%d: no %s" % [missing[u], u])
		var text := "%d zoned lots have no %s" % [missing[u], u]
		if unlinked[u] > 0:
			text += ": their streets aren't joined by road to a %s" % ("power line" if u == "power" else "water source")
		else:
			var use: Array = services.utility_use[u]
			text += ": %s is full (%s of %s homes), build a %s" % [u, money_text(use[0]), money_text(use[1]),
				"Substation" if u == "power" else "Water tower"]
		fulls.append(text)
	return [" · ".join(shorts), ". ".join(fulls)]


## Buildings on zoned lots that lack power or water.
func unserved_count() -> int:
	var n := 0
	for key in buildings:
		if not services.has_utilities(key):
			n += 1
	return n


func utilities_ok(key: String) -> bool:
	return _utilities_ok(key)


func _utilities_ok(key: String) -> bool:
	return not require_utilities or services.has_utilities(key)


func count_buildings(zone: int) -> int:
	var n := 0
	for key in buildings:
		if buildings[key].zone == zone:
			n += 1
	return n


## The street sides that make one block face with this one: the same side,
## followed through bends where only two roads meet, up to real junctions.
## Returns [[seg, side], ...].
func frontage_chain(seg: int, side: int) -> Array:
	var out := [[seg, side]]
	var seen := {seg: true}
	for from_b in [true, false]:
		var cur := seg
		var cur_side := side
		var at_b: bool = from_b
		while true:
			var node: int = network.segments[cur].b if at_b else network.segments[cur].a
			var here := network.segments_at(node)
			if here.size() != 2:
				break
			var nxt: int = here[0] if here[1] == cur else here[1]
			if seen.has(nxt) or not RoadStyle.TYPES[network.segments[nxt].type].lots:
				break
			seen[nxt] = true
			# Sides are left or right of a road's a-to-b direction, so they
			# swap when the next road runs the other way.
			var same_way: bool = (network.segments[nxt].a == node) == at_b
			cur_side = cur_side if same_way else -cur_side
			at_b = network.segments[nxt].a == node
			cur = nxt
			out.append([cur, cur_side])
	return out


## Paints a zone along one street side's frontage, where its lots read it.
func _paint_frontage(seg: int, side: int, zone: int) -> void:
	var s := planner.side_survey(network, seg, side)
	if s.is_empty():
		return
	# A strip from the sidewalk back about 17 m, so the zone stays when the
	# street is widened later (a Street to a Boulevard moves lots 8.5 m).
	for r in s.rays:
		if r[3] >= 3.0:
			var p: Vector2 = (r[1] as Vector2) + (r[2] as Vector2) * LotPlanner.ZONE_PROBE
			zones.paint(Vector3(p.x, 0.0, p.y), 4.5, zone)
		if r[3] >= 18.0:
			var q: Vector2 = (r[1] as Vector2) + (r[2] as Vector2) * 12.0
			zones.paint(Vector3(q.x, 0.0, q.y), 5.5, zone)


## How well-off the neighbourhood at a point is, 0 to 1. Lot platting reads
## it (wealthier streets get wider lots). Neutral until land value and
## neighbourhood success are simulated.
func wealth_at(_p: Vector2) -> float:
	return 0.5


func _lot_blocked(lot: Dictionary) -> bool:
	for p in [lot.pos, lot.front, lot.zone_pt]:
		if services.covers(p) or farms.covers(p) or farms.field_at(p) != -1 or industry.covers(p) \
				or reserves.kind_at(p) != "" or hubs.covers(p) or warehouses.covers(p) or parks.covers(p):
			return true
	return false


func _refresh() -> void:
	if _lots_dirty:
		_lots_dirty = false
		planner.update(network)
		# Lots with buildings are parcels: they stay as they are unless a road
		# now runs through them.
		var frozen := {}
		var lost := []
		var keys := buildings.keys()
		keys.sort()
		for key in keys:
			if lots.has(key):
				var lot := planner.revalidate(network, lots[key])
				if not lot.is_empty() and not _lot_blocked(lot):
					frozen[key] = lot
				else:
					lost.append(key)
		lots = frozen.duplicate()
		if not lost.is_empty():
			parcels_lost.emit(lost)
		for lot in planner.plan(network, zones, frozen):
			# No lots under a service building.
			if not _lot_blocked(lot):
				lots[lot.key] = lot
		_usable_cache.clear()
		services.update(network, lots, buildings)
		lots_changed.emit()
	# Buildings go away when their lot disappears or its zone changes.
	var removed := false
	for key in buildings.keys():
		if not lots.has(key) or zones.zone_at(lots[key].zone_pt) != buildings[key].zone:
			buildings.erase(key)
			removed = true
	if removed:
		buildings_changed.emit()


## Why a road can't be built under real US road rules, or "" if it can.
func road_problem(c: Array, type: int) -> String:
	var flat := Vector2(c[2].x - c[0].x, c[2].z - c[0].z).length()
	if flat < RoadNetwork.MIN_LENGTH:
		return "Too short."
	var r := RoadNetwork.min_radius(c[0], c[1], c[2])
	if r < RoadStyle.MIN_CURVE_RADIUS:
		return "Bend too tight: %d m. Roads need at least %d m (42 ft) so trucks can turn (AASHTO)." \
			% [int(r), int(RoadStyle.MIN_CURVE_RADIUS)]
	var spec: Dictionary = RoadStyle.TYPES[type]
	var grade := absf(c[2].y - c[0].y) / flat
	if grade > spec.grade + 0.0001:
		return "Too steep: %d%% grade. A %s can climb at most %d%% (AASHTO)." \
			% [roundi(grade * 100.0), spec.name, roundi(spec.grade * 100.0)]
	var problem := network.crossing_problem(c[0], c[1], c[2])
	var saved := reserves.crosses(RoadNetwork.sample_curve(c[0], c[1], c[2], 24))
	if problem == "" and saved != "":
		problem = "That land is reserved for %s. Clear the reserve first." % Reserves.KINDS[saved]
	if problem == "" and Economy.road_cost(c, type) > economy.money:
		return "Not enough money: this road costs $%s." % money_text(Economy.road_cost(c, type))
	return problem


## What it costs to build these road pieces.
static func shapes_cost(curves: Array, type: int) -> int:
	var total := 0
	for c in curves:
		total += Economy.road_cost(c, type)
	return total


## What upgrading a road costs: the difference in build price, nothing to
## downgrade. -1 if there is no such road.
func upgrade_cost(seg: int, type: int) -> int:
	if not network.segments.has(seg):
		return -1
	var c := network.curve_of(seg)
	return maxi(0, Economy.road_cost(c, type) - Economy.road_cost(c, network.segments[seg].type))


func _can_afford(curves: Array, type: int) -> bool:
	return shapes_cost(curves, type) <= economy.money


## Dollars with thousands separators: 1234567 -> "1,234,567".
static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Builds the ring, joining every road it crosses, then clears the roads
## left inside it.
func _build_roundabout(center: Vector3, radius: float, type: int) -> bool:
	network.begin_batch()
	var ok := false
	for arc in RoadShapes.roundabout(center, radius):
		ok = network.build_road(arc[0], arc[1], arc[2], type, true) or ok
	for id in network.segments.keys():
		var c := network.curve_of(id)
		var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		if mid.distance_to(center) < radius - 2.0:
			network.remove_segment(id)
	network.end_batch()
	return ok


func _grow_one() -> void:
	var empty := empty_zoned_lots()
	if empty.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count])
	# Each zone gets a chance to build in proportion to its demand.
	var by_zone := {}
	for key in empty:
		var z := zones.zone_at(lots[key].zone_pt)
		if not by_zone.has(z):
			by_zone[z] = []
		by_zone[z].append(key)
	var zone_order := by_zone.keys()
	zone_order.sort()
	for z in zone_order:
		if rng.randf() >= demand[z]:
			continue
		var list: Array = by_zone[z]
		var key: String = list[rng.randi() % list.size()]
		var bseed := rng.randi()
		buildings[key] = {"zone": z, "seed": bseed, "built": tick_count,
			"cap": capacity(z, bseed), "occ": 0}
		if z == ZoneMap.Zone.INDUSTRIAL:
			buildings[key].chain = factory_chain(lots[key].pos)
		buildings_changed.emit()
		return


## What a new factory here would make (a key of Balance.FACTORY_CHAINS):
## the chain with the most output nearby, counting closer supply more, or
## "general" when nothing local is near enough (Brawn: factories follow the
## town's industry).
func factory_chain(at: Vector3) -> String:
	var score := {"mill": 0.0, "sawmill": 0.0, "refinery": 0.0, "metal": 0.0}
	var reach := Balance.FACTORY_CHAIN_REACH
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		var d: float = f.pos.distance_to(at)
		if d < reach:
			# A 1,000-bushel truck a month for about every 15 acres of corn.
			score.mill += f.cells.size() * Farms.ACRES_PER_CELL / 15.0 * (1.0 - d / reach)
	var by_kind := {"forest": "sawmill", "oil": "refinery", "ore": "metal"}
	for id in industry.sites:
		var s: Dictionary = industry.sites[id]
		var d: float = s.pos.distance_to(at)
		if d < reach:
			score[by_kind[s.kind]] += Balance.INDUSTRY[s.kind].loads * s.pads.size() * (1.0 - d / reach)
	var best := "general"
	var best_v := Balance.FACTORY_CHAIN_MIN
	for k in ["mill", "sawmill", "refinery", "metal"]:
		if score[k] > best_v:
			best_v = score[k]
			best = k
	return best


## People a home holds, or jobs a shop or factory offers.
static func capacity(zone: int, bseed: int) -> int:
	var r := absi(bseed)
	match zone:
		ZoneMap.Zone.RESIDENTIAL: return 2 + r % 3
		ZoneMap.Zone.COMMERCIAL: return 6 + r % 9
		_: return 18 + r % 19


# --- Saving (also the future network format) --------------------------------

## True for the piece of county highway that runs off to the region: it
## can't be bulldozed, or the town would lose its way out.
func is_link_segment(seg_id: int) -> bool:
	var s: Dictionary = network.segments.get(seg_id, {})
	return not s.is_empty() and (s.a in region_links or s.b in region_links)


## The county highway a new city starts on (no map edge): a two-lane road
## from a to b (metres, city-local) in pieces of about 400 m, free of charge.
## The ends listed in link_ends (0 for a, 1 for b) lead on to the region.
## Returns the node ids at a and b. A command, so every copy builds it.
func build_county_road(a: Vector2, b: Vector2, link_ends: Array) -> Array:
	apply_now({"type": "build_county_road", "a": [a.x, a.y], "b": [b.x, b.y], "links": link_ends})
	return [network.find_node_near(Vector3(a.x, 0, a.y), 1.0), network.find_node_near(Vector3(b.x, 0, b.y), 1.0)]


func _county_road(a: Vector2, b: Vector2, link_ends: Array) -> Array:
	var money := economy.money
	var n := maxi(1, ceili(a.distance_to(b) / 400.0))
	var pts := []
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		pts.append(Vector3(p.x, 0.0, p.y))
	network.begin_batch()
	for i in n:
		network.build_road(pts[i], (pts[i] + pts[i + 1]) * 0.5, pts[i + 1], RoadStyle.Type.STREET)
	network.end_batch()
	economy.money = money
	var ends := [network.find_node_near(pts[0], 1.0), network.find_node_near(pts[-1], 1.0)]
	for i in link_ends:
		if ends[int(i)] != -1 and not ends[int(i)] in region_links:
			region_links.append(ends[int(i)])
	return ends


func _parcels_to_save() -> Dictionary:
	var out := {}
	var keys := buildings.keys()
	keys.sort()
	for key in keys:
		if lots.has(key):
			out[key] = LotPlanner.lot_to_save(lots[key])
	return out


func to_dict() -> Dictionary:
	vegetation.update(self)  # land cleared since the last tick counts
	return {
		"version": 2,
		"links": region_links,
		"trade": trade.to_dict(),
		"tick": tick_count,
		"seed": city_seed,
		"roads": network.to_dict(),
		"zones": zones.to_dict(),
		"buildings": buildings,
		"parcels": _parcels_to_save(),
		"economy": economy.to_dict(),
		"services": services.to_dict(),
		"farms": farms.to_dict(),
		"industry": industry.to_dict(),
		"logistics": logistics.to_dict(),
		"warehouses": warehouses.to_dict(),
		"reserves": reserves.to_dict(),
		"permits": permits.to_dict(),
		"hubs": hubs.to_dict(),
		"parks": parks.to_dict(),
		"junctions": traffic.rules_to_dict(),
		"traffic": traffic.to_dict(),
		"vegetation": vegetation.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	vegetation.from_dict(d.get("vegetation", {}))
	planner = LotPlanner.new()
	planner.wealth = wealth_at
	if d.has("roads"):
		network.from_dict(d.roads)
		zones.from_dict(d.get("zones", {}))
		region_links.clear()
		if d.has("links"):
			for n in d.links:
				region_links.append(int(n))
		else:
			_guess_link()
		trade.from_dict(d.get("trade", {}))
	else:
		# Version 1 saves were just roads, with houses on every lot.
		network.from_dict(d)
		planner.update(network)
		for id in network.segments:
			for side in [-1, 1]:
				_paint_frontage(id, side, ZoneMap.Zone.RESIDENTIAL)
	_upgrade_old_rings()
	economy.from_dict(d.get("economy", {}))
	services.from_dict(d.get("services", {}))
	farms.from_dict(d.get("farms", {}))
	industry.from_dict(d.get("industry", {}))
	logistics.from_dict(d.get("logistics", {}))
	warehouses.from_dict(d.get("warehouses", {}))
	reserves.from_list(d.get("reserves", []))
	permits.from_dict(d.get("permits", {}))
	hubs.from_dict(d.get("hubs", {}))
	parks.from_dict(d.get("parks", {}))
	for legacy in farms.legacy_outlines:
		reserves.paint(legacy[0], legacy[1])
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		if f.drive.is_empty():
			f.drive = farm_drive(f.pos, f.dir)
	traffic.rules_from_dict(d.get("junctions", {}))
	traffic.from_dict(d.get("traffic", {}))
	tick_count = int(d.get("tick", 0))
	city_seed = int(d.get("seed", 1))
	# Parcels: the lots buildings stand on.
	planner.update(network)
	lots.clear()
	var parcels: Dictionary = d.get("parcels", {})
	for key in parcels:
		lots[key] = LotPlanner.lot_from_save(parcels[key])
	if not d.has("parcels"):
		# Saves from before natural lots: their buildings keep the old lots.
		for lot in LotPlanner.legacy_plan(network):
			lot.sig = planner.sig_of(lot.seg)
			lots[lot.key] = lot
	buildings.clear()
	for key in d.get("buildings", {}):
		var b: Dictionary = d.buildings[key]
		var z := int(b.zone)
		var cap := int(b.get("cap", capacity(z, int(b.seed))))
		# Older saves had no residents yet: assume the homes were full.
		buildings[key] = {"zone": z, "seed": int(b.seed), "built": int(b.built), "cap": cap,
			"occ": int(b.get("occ", cap if z == ZoneMap.Zone.RESIDENTIAL else 0))}
		if z == ZoneMap.Zone.INDUSTRIAL and b.has("chain"):
			buildings[key].chain = str(b.chain)
	_road_wins()
	_lots_dirty = true
	_refresh()
	# Factories from before industry chains take up the local one.
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and not buildings[key].has("chain"):
			buildings[key].chain = factory_chain(lots[key].pos) if lots.has(key) else "general"
	update_stats()
	buildings_changed.emit()


## Saves from before real roundabouts drew rings as two-way roads of the
## chosen type. Turn those into one-way counter-clockwise rings.
func _upgrade_old_rings() -> void:
	var groups := {}  # rounded centre -> [seg ids]
	for id in network.segments:
		var s: Dictionary = network.segments[id]
		if RoadStyle.is_ring(s.type) or RoadStyle.TYPES[s.type].oneway:
			continue
		var c := network.curve_of(id)
		var circle := RoadShapes.arc_circle(c)
		if circle.is_empty() or circle[1] < RoadShapes.ROUNDABOUT_MIN - 1.0 or circle[1] > RoadShapes.ROUNDABOUT_MAX + 1.0:
			continue
		var key := Vector2i(roundi(circle[0].x / 2.0), roundi(circle[0].z / 2.0))
		if not groups.has(key):
			groups[key] = []
		groups[key].append([id, circle[0]])
	for key in groups:
		if groups[key].size() < 6:
			continue
		for entry in groups[key]:
			var id: int = entry[0]
			var s: Dictionary = network.segments[id]
			var c := network.curve_of(id)
			# Counter-clockwise seen from above: the centre is on the driver's left.
			var fwd: Vector3 = c[2] - c[0]
			var to_centre: Vector3 = entry[1] - c[0]
			if fwd.cross(to_centre).y < 0.0:
				var a: int = s.a
				s.a = s.b
				s.b = a
			s.type = RoadStyle.ring_type(s.type)
			s.oneway = true


## The road type a command asks for (Street if it doesn't say).
static func _road(cmd: Dictionary) -> int:
	return clampi(int(cmd.get("road", 0)), 0, RoadStyle.TYPES.size() - 1)


## A point from a command: [x, z] or [x, z, height].
static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[2]) if a.size() > 2 else 0.0, float(a[1]))
