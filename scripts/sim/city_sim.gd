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

const TICKS_PER_SECOND := 10
## A new building can start every this many ticks.
const GROW_EVERY := 4

var network := RoadNetwork.new()
var zones := ZoneMap.new()
var lots := {}       # lot key -> lot Dictionary (from LotPlanner)
var buildings := {}  # lot key -> {"zone", "seed", "built"}
var tick_count := 0
var city_seed := 1

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
			if RoadNetwork.min_radius(c[0], c[1], c[2]) >= RoadStyle.MIN_CURVE_RADIUS:
				ok = network.build_road(c[0], c[1], c[2])
		"build_grid":
			var lines := RoadShapes.grid(_v(cmd.a), _v(cmd.b), _v(cmd.c), float(cmd.block))
			network.begin_batch()
			for l in lines:
				ok = network.build_road(l[0], l[1], l[2]) or ok
			network.end_batch()
		"build_roundabout":
			ok = _build_roundabout(_v(cmd.center), float(cmd.radius))
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
	if tick_count % GROW_EVERY == 0:
		_grow_one()


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


## Builds the ring, joining every road it crosses, then clears the roads
## left inside it.
func _build_roundabout(center: Vector3, radius: float) -> bool:
	radius = clampf(radius, RoadShapes.ROUNDABOUT_MIN, RoadShapes.ROUNDABOUT_MAX)
	network.begin_batch()
	var ok := false
	for arc in RoadShapes.roundabout(center, radius):
		ok = network.build_road(arc[0], arc[1], arc[2]) or ok
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
	var key: String = empty[rng.randi() % empty.size()]
	buildings[key] = {
		"zone": zones.zone_at(lots[key].zone_pt),
		"seed": rng.randi(),
		"built": tick_count,
	}
	buildings_changed.emit()


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
		buildings[key] = {"zone": int(b.zone), "seed": int(b.seed), "built": int(b.built)}
	_lots_dirty = true
	_refresh()
	buildings_changed.emit()


static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), 0.0, float(a[1]))
