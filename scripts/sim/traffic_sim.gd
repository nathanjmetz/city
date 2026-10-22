class_name TrafficSim
extends RefCounted
## Cars driving between homes, jobs and shops, stepped with the city's ticks.
##
## Each car follows a route of road pieces found with A* over the road graph
## (one-way roads only one way), keeps to the right, drives at the speed
## limit or slower on curves, and queues behind the car in front. Seeded by
## the city, so every copy of the simulation moves the same cars.

const MAX_CARS := 400
## Real seconds of driving per tick, so cars move at true speeds on screen.
const DT := 0.1  # one tick at 10 ticks a second
## Bumper to bumper gap when stopped, plus about one car length.
const STOP_GAP := 7.5
## Seconds of following distance at speed (the "two second rule").
const HEADWAY := 1.5
const ACCEL := 2.5   # m/s^2
const BRAKE := 6.0   # m/s^2

var network: RoadNetwork
## Every car: {id, route: [[seg, forward]], leg, d (metres into the leg),
## end_d (where to stop on the last leg), v (m/s), color}
var cars := []
## Share of the speed limit cars are managing, 0 to 1 (like CS traffic flow).
var flow := 1.0

var _astar := AStar3D.new()
var _lines := {}    # seg -> PackedVector3Array
var _cum := {}      # seg -> PackedFloat32Array of distance at each point
var _curve_v := {}  # seg -> safe speed on its tightest bend, m/s
var _dirty := true
var _next_id := 1


func _init(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(func(): _dirty = true)


func step(sim: CitySim, rng: RandomNumberGenerator) -> void:
	if _dirty:
		_rebuild()
	_spawn(sim, rng)
	_drive()


## Where a car is and which way it faces: [position, direction]. `ahead`
## moves it on by that many metres, for smooth drawing between ticks.
func car_pose(car: Dictionary, ahead := 0.0) -> Array:
	var leg: Array = car.route[car.leg]
	var seg: int = leg[0]
	var length := seg_length(seg)
	var along := minf(car.d + ahead, length)
	var d: float = along if leg[1] else length - along
	var p := _point(seg, d)
	var next := _point(seg, clampf(d + (1.0 if leg[1] else -1.0), 0.0, length))
	var dir := next - p
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	return [p + right * lane_offset(network.segments[seg].type), dir]


func seg_length(seg: int) -> float:
	var c: PackedFloat32Array = _cum[seg]
	return c[c.size() - 1]


## How far right of the centre line a car drives.
static func lane_offset(type: int) -> float:
	var spec: Dictionary = RoadStyle.TYPES[type]
	if spec.oneway:
		return -spec.width * 0.5 + 1.2 + 3.6 * spec.lanes * 0.5
	return spec.median * 0.5 + 1.8


static func limit(type: int) -> float:
	return RoadStyle.TYPES[type].mph * RoadStyle.MPH


func _rebuild() -> void:
	_dirty = false
	_astar.clear()
	_lines.clear()
	_cum.clear()
	_curve_v.clear()
	for id in network.nodes:
		_astar.add_point(id, network.nodes[id])
	for id in network.segments:
		var s: Dictionary = network.segments[id]
		var pts := network.sample_segment(id, 32)
		_lines[id] = pts
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		_cum[id] = cum
		var c := network.curve_of(id)
		var r := RoadNetwork.min_radius(c[0], c[1], c[2])
		_curve_v[id] = INF if r > 400.0 else RoadStyle.safe_speed_mph(r) * RoadStyle.MPH
		if not _astar.are_points_connected(s.a, s.b):
			_astar.connect_points(s.a, s.b, not RoadStyle.TYPES[s.type].oneway)
	# Cars whose road was removed or changed vanish.
	var kept := []
	for car in cars:
		var ok := true
		for leg in car.route:
			if not network.segments.has(leg[0]):
				ok = false
				break
		if ok:
			kept.append(car)
	cars = kept


## Trips follow the time of day: to work in the morning, home in the evening,
## to the shops in between.
func _spawn(sim: CitySim, rng: RandomNumberGenerator) -> void:
	if cars.size() >= MAX_CARS or sim.stats.population == 0:
		return
	var hour: int = sim.clock().hour
	var rate := 0.15
	if hour >= 6 and hour < 9 or hour >= 16 and hour < 19:
		rate = 0.6
	elif hour >= 22 or hour < 5:
		rate = 0.03
	# At rush hour, about one trip a second for every 200 people.
	if rng.randf() > rate * sim.stats.population / 1200.0:
		return
	var homes := []
	var dests := []
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			homes.append(key)
		else:
			dests.append(key)
	if homes.is_empty() or dests.is_empty():
		return
	homes.sort()
	dests.sort()
	var a: Dictionary = sim.lots[homes[rng.randi() % homes.size()]]
	var b: Dictionary = sim.lots[dests[rng.randi() % dests.size()]]
	if hour >= 15:
		var t := a
		a = b
		b = t
	var car := _route(a, b)
	if car.is_empty():
		return
	# Pull out only when there's a gap in the traffic.
	var key := _lane_key(car.route[0])
	for other in cars:
		if _lane_key(other.route[other.leg]) == key and absf(other.d - car.d) < STOP_GAP * 2.0:
			return
	car.id = _next_id
	_next_id += 1
	car.color = rng.randi() % 8
	cars.append(car)


## A car driving from one lot's driveway to another's, or {} if no route.
func _route(from: Dictionary, to: Dictionary) -> Dictionary:
	if not (_cum.has(from.seg) and _cum.has(to.seg)):
		return {}
	var start_d: float = from.at_frac * seg_length(from.seg)
	var end_d: float = to.at_frac * seg_length(to.seg)
	var fs: Dictionary = network.segments[from.seg]
	var ts: Dictionary = network.segments[to.seg]
	var best := []
	var best_len := INF
	# Try leaving each way and arriving each way; keep the shortest.
	for out_fwd in [true, false]:
		if not out_fwd and RoadStyle.TYPES[fs.type].oneway:
			continue
		var exit_node: int = fs.b if out_fwd else fs.a
		var first_len: float = (seg_length(from.seg) - start_d) if out_fwd else start_d
		for in_fwd in [true, false]:
			if not in_fwd and RoadStyle.TYPES[ts.type].oneway:
				continue
			var entry_node: int = ts.a if in_fwd else ts.b
			var last_len: float = end_d if in_fwd else seg_length(to.seg) - end_d
			if from.seg == to.seg and out_fwd == in_fwd and (end_d > start_d) == out_fwd:
				var direct := absf(end_d - start_d)
				if direct < best_len:
					best_len = direct
					best = [[from.seg, out_fwd]]
				continue
			var nodes := _astar.get_id_path(exit_node, entry_node)
			if nodes.is_empty():
				continue
			var legs := [[from.seg, out_fwd]]
			var total := first_len + last_len
			for i in range(nodes.size() - 1):
				var leg := _leg_between(nodes[i], nodes[i + 1])
				if leg.is_empty():
					legs = []
					break
				legs.append(leg)
				total += seg_length(leg[0])
			if legs.is_empty():
				continue
			legs.append([to.seg, in_fwd])
			if total < best_len:
				best_len = total
				best = legs
	if best.is_empty():
		return {}
	var last: Array = best[best.size() - 1]
	return {
		"route": best, "leg": 0,
		"d": start_d if best[0][1] else seg_length(from.seg) - start_d,
		"end_d": end_d if last[1] else seg_length(to.seg) - end_d,
		"v": 0.0,
	}


## The road piece that runs from node a to node b, as [seg, forward].
func _leg_between(a: int, b: int) -> Array:
	var best := []
	var best_len := INF
	for id in network.segments_at(a):
		var s: Dictionary = network.segments[id]
		var fwd: bool = s.a == a and s.b == b
		var back: bool = s.b == a and s.a == b and not RoadStyle.TYPES[s.type].oneway
		if (fwd or back) and seg_length(id) < best_len:
			best_len = seg_length(id)
			best = [id, fwd]
	return best


func _drive() -> void:
	# Group cars by the road piece and direction they are on, nearest the
	# end first, so each can see the car ahead of it.
	var lanes := {}
	for car in cars:
		var key: Vector2i = _lane_key(car.route[car.leg])
		if not lanes.has(key):
			lanes[key] = []
		lanes[key].append(car)
	for key in lanes:
		lanes[key].sort_custom(func(x, y): return x.d > y.d)
	var done := []
	var speed_sum := 0.0
	var limit_sum := 0.0
	for key in lanes:
		var list: Array = lanes[key]
		for i in list.size():
			var car: Dictionary = list[i]
			var leg: Array = car.route[car.leg]
			var seg: int = leg[0]
			var type: int = network.segments[seg].type
			var vmax := minf(limit(type), _curve_v[seg])
			var last_leg: bool = car.leg == car.route.size() - 1
			var room := INF
			if i > 0:
				room = list[i - 1].d - car.d - STOP_GAP
			if last_leg:
				room = minf(room, car.end_d - car.d + STOP_GAP * 0.5)
			elif seg_length(seg) - car.d < 40.0:
				# Look into the next road for a queue at its start.
				room = minf(room, seg_length(seg) - car.d + _space_at_start(car.route[car.leg + 1], lanes))
			# Brake to stop within the room left, else speed up to the limit.
			var safe := sqrt(maxf(0.0, 2.0 * BRAKE * maxf(room - car.v * HEADWAY * 0.5, 0.0)))
			var target := minf(vmax, safe)
			car.v = minf(car.v + ACCEL * DT, target) if target > car.v else maxf(car.v - BRAKE * DT, target)
			car.v = maxf(car.v, 0.0)
			car.d += car.v * DT
			speed_sum += car.v
			limit_sum += vmax
			if last_leg and car.d >= car.end_d - 0.5:
				done.append(car)
			elif not last_leg and car.d >= seg_length(seg):
				var next: Array = car.route[car.leg + 1]
				var over: float = car.d - seg_length(seg)
				if _space_at_start(next, lanes) < over:
					# Another car just took the gap: wait at the junction.
					car.d = seg_length(seg)
					car.v = 0.0
				else:
					car.d = over
					car.leg += 1
					var nkey := _lane_key(next)
					if not lanes.has(nkey):
						lanes[nkey] = []
					lanes[nkey].append(car)
	for car in done:
		cars.erase(car)
	flow = 1.0 if limit_sum == 0.0 else clampf(speed_sum / limit_sum, 0.0, 1.0)


## Gap free at the start of a road piece before the last car queued there.
func _space_at_start(leg: Array, lanes: Dictionary) -> float:
	var key := _lane_key(leg)
	if not lanes.has(key) or lanes[key].is_empty():
		return INF
	var last: Dictionary = lanes[key][lanes[key].size() - 1]
	return last.d - STOP_GAP


static func _lane_key(leg: Array) -> Vector2i:
	return Vector2i(leg[0], 1 if leg[1] else 0)


func _point(seg: int, d: float) -> Vector3:
	var pts: PackedVector3Array = _lines[seg]
	var cum: PackedFloat32Array = _cum[seg]
	var i := cum.bsearch(d)
	if i <= 0:
		return pts[0]
	if i >= pts.size():
		return pts[pts.size() - 1]
	var f := (d - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.0001)
	return pts[i - 1].lerp(pts[i], f)
