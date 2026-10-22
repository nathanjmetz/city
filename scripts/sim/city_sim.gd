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
signal zones_changed
## Population, jobs or demand changed (at most every MOVE_EVERY ticks).
signal stats_changed
## Farmland or a farm's fields changed.
signal farms_changed

const TICKS_PER_SECOND := 10
## A new building can start every this many ticks.
const GROW_EVERY := 4
## People move in and stats update every this many ticks.
const MOVE_EVERY := 10
## Game minutes per tick: at normal speed a day takes 2.4 real minutes.
const MINUTES_PER_TICK := 1
## Tick 0 is 6:00 AM on Monday, January 4, 2027.
const START_UNIX := 1799042400
## Share of residents who work (US labour force is about half of everyone).
const WORKER_SHARE := 0.5
const TICKS_PER_HOUR := 60 / MINUTES_PER_TICK

var network := RoadNetwork.new()
var zones := ZoneMap.new()
var traffic := TrafficSim.new(network)
var economy := Economy.new()
var services := Services.new()
var farms := Farms.new()
## Buildings only grow and fill with power and water, as in Cities: Skylines.
## The game turns this on; tests about other things can leave it off.
var require_utilities := false
var lots := {}       # lot key -> lot Dictionary (from LotPlanner)
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

var _lots_dirty := true
var _usable_cache := {}  # field cell -> bool, cleared when roads or lots change


func _init() -> void:
	network.changed.connect(func(): _lots_dirty = true)


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
		"build_grid":
			var lines := RoadShapes.grid(_v(cmd.a), _v(cmd.b), _v(cmd.c), float(cmd.block))
			if not _can_afford(lines, _road(cmd)):
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
			if cost > economy.money or services.site_problem(network, kind, pos, dir) != "":
				return false
			services.add(kind, pos, dir)
			economy.money -= cost
			_lots_dirty = true
			ok = true
		"paint_farmland":
			var pts := []
			for p in cmd.points:
				pts.append(_v(p))
			ok = farms.paint_polygon(pts, bool(cmd.get("on", true)))
			if ok:
				_lots_dirty = true
				farms_changed.emit()
		"place_farmhouse":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if farmhouse_problem(pos, dir) != "" or Farms.FARMHOUSE_COST > economy.money:
				return false
			farms.add_farm(pos, dir, str(cmd.get("crop", "corn")), farm_drive(pos, dir))
			economy.money -= Farms.FARMHOUSE_COST
			_lots_dirty = true
			farms_changed.emit()
			ok = true
		"remove_farm":
			ok = farms.farms.has(int(cmd.id))
			farms.farms.erase(int(cmd.id))
			_lots_dirty = true
			farms_changed.emit()
		"remove_service":
			ok = services.buildings.has(int(cmd.id))
			services.buildings.erase(int(cmd.id))
			_lots_dirty = true
		"set_tax":
			if economy.set_tax(int(cmd.zone), float(cmd.rate)):
				update_stats()
			return true
		"remove_road":
			ok = network.segments.has(int(cmd.seg))
			network.remove_segment(int(cmd.seg))
		"paint_zone":
			zones.paint(_v(cmd.center), float(cmd.radius), int(cmd.zone))
			_usable_cache.clear()
			ok = true
		"set_junction":
			# Traffic lights, stop signs or none at a junction (-1 = automatic).
			ok = traffic.set_rule(int(cmd.node), int(cmd.rule))
		"clear":
			traffic.overrides.clear()
			network.clear()
			zones.cells.clear()
			economy = Economy.new()
			services = Services.new()
			farms = Farms.new()
			farms_changed.emit()
			ok = true
	if ok:
		_refresh()
		zones_changed.emit()
	return ok


func tick() -> void:
	tick_count += 1
	_refresh()
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
	# Taxes come in and upkeep goes out every game hour, a day settling a month.
	if tick_count % TICKS_PER_HOUR == 0:
		economy.money += roundi(economy.monthly_net() / 24.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count, "traffic"])
	traffic.step(self, rng)


## Game time as a Dictionary (year, month, day, weekday, hour, minute).
func clock() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(START_UNIX + tick_count * MINUTES_PER_TICK * 60)


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
	factory_jobs += farms.jobs()
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
	var on_land := farms.is_farmland(pos)
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Farms.FARMHOUSE_SIZE.x * 0.5 * sgn.x + dir * Farms.FARMHOUSE_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
		on_land = on_land or farms.is_farmland(p)
	if not on_land:
		return "Place the farmhouse on farmland. Outline farmland first."
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
	return ""


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
			if services.covers(p) or farms.covers(p):
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


func _refresh() -> void:
	if _lots_dirty:
		_lots_dirty = false
		lots.clear()
		for lot in LotPlanner.plan(network):
			# No lots under a service building.
			var blocked := false
			for p in [lot.pos, lot.front, lot.zone_pt]:
				blocked = blocked or services.covers(p) or farms.covers(p) or farms.field_at(p) != -1
			if not blocked:
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
		buildings_changed.emit()
		return


## People a home holds, or jobs a shop or factory offers.
static func capacity(zone: int, bseed: int) -> int:
	var r := absi(bseed)
	match zone:
		ZoneMap.Zone.RESIDENTIAL: return 2 + r % 3
		ZoneMap.Zone.COMMERCIAL: return 6 + r % 9
		_: return 18 + r % 19


# --- Saving (also the future network format) --------------------------------

func to_dict() -> Dictionary:
	return {
		"version": 2,
		"tick": tick_count,
		"seed": city_seed,
		"roads": network.to_dict(),
		"zones": zones.to_dict(),
		"buildings": buildings,
		"economy": economy.to_dict(),
		"services": services.to_dict(),
		"farms": farms.to_dict(),
		"junctions": traffic.rules_to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	if d.has("roads"):
		network.from_dict(d.roads)
		zones.from_dict(d.get("zones", {}))
	else:
		# Version 1 saves were just roads, with houses on every lot.
		network.from_dict(d)
		_refresh()
		for key in lots:
			zones.paint(lots[key].zone_pt, 3.0, ZoneMap.Zone.RESIDENTIAL)
	_upgrade_old_rings()
	economy.from_dict(d.get("economy", {}))
	services.from_dict(d.get("services", {}))
	farms.from_dict(d.get("farms", {}))
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		if f.drive.is_empty():
			f.drive = farm_drive(f.pos, f.dir)
	traffic.rules_from_dict(d.get("junctions", {}))
	tick_count = int(d.get("tick", 0))
	city_seed = int(d.get("seed", 1))
	buildings.clear()
	for key in d.get("buildings", {}):
		var b: Dictionary = d.buildings[key]
		var z := int(b.zone)
		var cap := int(b.get("cap", capacity(z, int(b.seed))))
		# Older saves had no residents yet: assume the homes were full.
		buildings[key] = {"zone": z, "seed": int(b.seed), "built": int(b.built), "cap": cap,
			"occ": int(b.get("occ", cap if z == ZoneMap.Zone.RESIDENTIAL else 0))}
	_lots_dirty = true
	_refresh()
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
