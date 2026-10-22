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

var network := RoadNetwork.new()
var zones := ZoneMap.new()
var traffic := TrafficSim.new(network)
var lots := {}       # lot key -> lot Dictionary (from LotPlanner)
var buildings := {}  # lot key -> {"zone", "seed", "built", "cap", "occ"}
var tick_count := 0
var city_seed := 1

## Latest totals, worked out from the buildings.
var stats := {"population": 0, "workers": 0, "jobs": 0, "employed": 0, "homes_free": 0}
## How much each zone wants to grow, 0 to 1, like the CS demand bars.
var demand := {ZoneMap.Zone.RESIDENTIAL: 0.6, ZoneMap.Zone.COMMERCIAL: 0.0, ZoneMap.Zone.INDUSTRIAL: 0.1}

var _lots_dirty := true


func _init() -> void:
	network.changed.connect(func(): _lots_dirty = true)


## Applies one player command. Returns true if anything changed.
func apply(cmd: Dictionary) -> bool:
	var ok := false
	match cmd.get("type", ""):
		"build_road":
			var c := [_v(cmd.start), _v(cmd.ctrl), _v(cmd.end)]
			# The server checks real road rules too, not just the player's screen.
			if road_problem(c, _road(cmd)) == "":
				ok = network.build_road(c[0], c[1], c[2], _road(cmd))
		"build_grid":
			var lines := RoadShapes.grid(_v(cmd.a), _v(cmd.b), _v(cmd.c), float(cmd.block))
			network.begin_batch()
			for l in lines:
				ok = network.build_road(l[0], l[1], l[2], _road(cmd)) or ok
			network.end_batch()
		"build_roundabout":
			ok = _build_roundabout(_v(cmd.center), float(cmd.radius), _road(cmd))
		"upgrade_road":
			ok = network.set_type(int(cmd.seg), _road(cmd))
		"remove_road":
			ok = network.segments.has(int(cmd.seg))
			network.remove_segment(int(cmd.seg))
		"paint_zone":
			zones.paint(_v(cmd.center), float(cmd.radius), int(cmd.zone))
			ok = true
		"clear":
			network.clear()
			zones.cells.clear()
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
				shop_jobs += b.cap
			ZoneMap.Zone.INDUSTRIAL:
				factory_jobs += b.cap
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
	stats_changed.emit()


## New residents move into homes with room, faster when homes are in demand.
func _move_in() -> void:
	var arrivals := 1 + int(demand[ZoneMap.Zone.RESIDENTIAL] * 4.0)
	if demand[ZoneMap.Zone.RESIDENTIAL] <= 0.05:
		return
	var keys := buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
		if b.zone == ZoneMap.Zone.RESIDENTIAL and b.occ < b.cap:
			b.occ += 1
			arrivals -= 1
			if arrivals == 0:
				return


## Lots that are zoned but have nothing on them yet.
func empty_zoned_lots() -> Array:
	var out := []
	for key in lots:
		if not buildings.has(key) and zones.zone_at(lots[key].zone_pt) != ZoneMap.Zone.NONE:
			out.append(key)
	out.sort()
	return out


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
			lots[lot.key] = lot
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
	return network.crossing_problem(c[0], c[1], c[2])


## Builds the ring, joining every road it crosses, then clears the roads
## left inside it.
func _build_roundabout(center: Vector3, radius: float, type: int) -> bool:
	radius = clampf(radius, RoadShapes.ROUNDABOUT_MIN, RoadShapes.ROUNDABOUT_MAX)
	network.begin_batch()
	var ok := false
	for arc in RoadShapes.roundabout(center, radius):
		ok = network.build_road(arc[0], arc[1], arc[2], type) or ok
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


## The road type a command asks for (Street if it doesn't say).
static func _road(cmd: Dictionary) -> int:
	return clampi(int(cmd.get("road", 0)), 0, RoadStyle.TYPES.size() - 1)


## A point from a command: [x, z] or [x, z, height].
static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[2]) if a.size() > 2 else 0.0, float(a[1]))
