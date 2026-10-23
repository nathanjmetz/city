class_name TrafficSim
extends RefCounted
## Cars driving between homes, jobs and shops, stepped with the city's ticks.
##
## Works the way Cities: Skylines does in spirit, and fixes its best known
## weakness: cars plan a route, but keep thinking while they drive.
##
## - Every road carries real lanes (3.6 m, the AASHTO lane) each way.
## - Junctions get lane arrows: left lanes turn left, right lanes turn right.
## - Cars cross junctions on curved lane-to-lane paths, not through a point.
## - Cars follow each other with the Intelligent Driver Model (real gaps,
##   real braking), and each driver likes a slightly different speed.
## - Cars change lanes when they must (to reach a turn) and when it pays
##   (to pass a slow car or skip a queue), checking the gap first.
## - Every so often, and when they miss their lane, cars re-plan the rest of
##   the trip with live travel times, so they drive around jams.
## - Junctions have real US control: traffic lights where two big roads
##   meet, stop signs on side streets, all-way stops between equal streets,
##   and yield on entry at roundabouts and on-ramps.
##
## Seeded by the city, so every copy of the simulation moves the same cars.

const MAX_CARS := 400
## Real seconds of driving per tick, so cars move at true speeds on screen.
const DT := 0.1
const CAR_LEN := 4.6
const LANE_W := 3.6
## Trips that may drive in bus lanes, and how far before a corner or
## driveway other traffic may cross into one (about a block's last third).
const BUS_PURPOSES := ["transit", "school"]
const BUS_LANE_ENTRY := 60.0
## Intelligent Driver Model: bumper gap when stopped, time gap at speed,
## gentle acceleration and comfortable braking (AASHTO uses 3.4 m/s^2).
const JAM_GAP := 2.0
const HEADWAY := 1.4
const ACCEL := 2.0
const BRAKE := 3.0
const MAX_BRAKE := 8.0
## Seconds a lane change takes.
const LC_TIME := 2.5
## A car that hasn't moved for this long gives up (like CS1 despawning).
const STUCK_LIMIT := 150.0
## How far ahead a car looks for its next junction, in metres.
const LOOK := 150.0

enum Rule { NONE, SIGNAL, ALL_STOP, PRIORITY }
enum Turn { STRAIGHT, RIGHT, LEFT, UTURN }
enum Light { GREEN, YELLOW, RED }

## Metres along the street a car takes to swing into or out of a driveway.
const DRIVEWAY_LEAD := 6.0
## Seconds a driver would rather spend than turn left across traffic into
## or out of a driveway.
const CROSS_PEN := 6.0

## Turning speeds: about 15 mph for a right, 20 mph for a left.
const TURN_V := [0.0, 6.7, 9.0, 4.0]

var network: RoadNetwork
## Every car: {id, route: [way ids], leg, lane, d (metres along the way),
## v (m/s), end_d, goal: {seg, frac}, dest, pref (share of the limit the
## driver likes), j (junction path while crossing one, else null), jd,
## commit, conn, arrive, stuck, lc_from, lc_t, lc_cool, color, a}
var cars := []
## Traffic flow, 0 to 1, like CS: the share of cars moving freely, with cars
## stuck behind others counted by how close to the limit they manage.
var flow := 1.0
## Cars that gave up stuck in traffic.
var gave_up := 0
## Trips with a job that got there, and ones that couldn't, since the
## caller last cleared these: [{id, purpose, cargo, from, to}].
var arrivals := []
var failed := []
var _waiting := []  # vehicles with a job waiting to pull out
## Stand-in deliveries from factories to shops, until the economy sends real
## shipments with dispatch(); switch off then.
var background_freight := true
## Seconds of driving so far.
var time := 0.0
## Goes up each time the lanes are rebuilt, so views know to redraw.
var version := 0

## A way is one direction of one road piece: id = seg * 2 + (1 forward, 0 back).
## {id, seg, fwd, from, to, type, pts, cum, len, lanes, offs, vmax, s0, s1}
## s0 and s1 are where the lanes start and stop short of the junctions.
var ways := {}
## Node -> {control, pos, major: {way: true}, sign ("stop"/"yield"),
## phases: [{ways, g_end, y_end, end}], cycle, offset}
var junctions := {}
## Player choices that replace the automatic junction control: node -> Rule.
var overrides := {}

var _in := {}     # node -> [way ids arriving]
var _out := {}    # node -> [way ids leaving]
var _turns := {}  # way -> [ways it may turn into]
var _arrows := {} # way -> {next way: [lanes that may take it]}
var _kind := {}   # Vector2i(way, next) -> Turn
var _conns := {}  # Vector4i(way, lane, next, lane) -> junction path
var _conflict := {}
var _next_conn := 1
var _speed := {}  # way -> smoothed share of the limit cars manage there
var _dirty := true
var _next_id := 1
var _tick := 0

# Rebuilt every tick.
var _lanes := {}     # way * 8 + lane -> cars, front first
var _box := {}       # node -> cars crossing it
var _committed := {} # node -> cars about to cross it
var _approach := {}  # node -> [{car, conn, ds}] for the first car in each lane
var _merging := {}   # lane key -> cars pulling out of a driveway into it
var _acc := ACCEL    # acceleration of the vehicle being worked out
var _restoring := false   # just loaded: junction paths still saved as keys
var _keep_routes := false


func _init(net: RoadNetwork) -> void:
	network = net
	# A road change before a loaded city has run a tick drops the saved plans.
	network.changed.connect(func():
		_dirty = true
		_keep_routes = false)


func step(sim: CitySim, rng: RandomNumberGenerator) -> void:
	if _dirty:
		_rebuild()
	_tick = sim.tick_count
	time += DT
	_spawn(sim, rng)
	_drive(rng)


# --- Public helpers -----------------------------------------------------------

## Where a car's front bumper is and which way it faces: [position,
## direction]. `ahead` moves it on by that many metres, for smooth drawing
## between ticks.
func car_pose(car: Dictionary, ahead := 0.0) -> Array:
	if _dirty:
		_rebuild()  # a loaded city that hasn't run yet (a neighbor's, say)
	if car.j != null:
		return _conn_pose(car.j, minf(car.jd + ahead, car.j.len))
	var w: Dictionary = ways[car.route[car.leg]]
	var d := minf(car.d + ahead, w.len)
	var pose := _way_pose(w, car.lane, d)
	if car.lc_t < 1.0:
		# Mid lane change: slide across, angled into the new lane.
		var fwd: Vector3 = pose[1]
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var s := smoothstep(0.0, 1.0, car.lc_t)
		var lat: float = lerpf(car.lc_from, w.offs[car.lane], s) - w.offs[car.lane]
		var slide: float = (w.offs[car.lane] - car.lc_from) * 6.0 * car.lc_t * (1.0 - car.lc_t) / LC_TIME
		pose = [pose[0] + right * lat, (fwd + right * slide / maxf(car.v, 2.0)).normalized()]
	return pose


## The point `m` metres behind a car's front bumper along the path it came
## by, back through junctions and driveways: [position, direction]. For
## trailers and long vehicles that have to follow the turns.
func car_pose_behind(car: Dictionary, m: float) -> Array:
	if car.j != null:
		var c: Dictionary = car.j
		if car.jd - m >= 0.0:
			return _conn_pose(c, car.jd - m)
		return _before_conn(c, m - car.jd)
	var w: Dictionary = ways[car.route[car.leg]]
	var dd: float = car.d - m
	var pj = car.get("pj")
	if pj != null and pj.wo == w.id and dd < pj.exit_d:
		var back: float = pj.exit_d - dd
		if back <= pj.len:
			return _conn_pose(pj, pj.len - back)
		return _before_conn(pj, back - pj.len)
	return _way_pose(w, car.lane, maxf(dd, 0.0))


func _before_conn(c: Dictionary, back: float) -> Array:
	if c.wi >= 0 and ways.has(c.wi):
		var w: Dictionary = ways[c.wi]
		return _way_pose(w, mini(c.li, w.lanes - 1), maxf(w.s1 - back, 0.0))
	return [c.pts[0], c.d0]


func _conn_pose(c: Dictionary, jd: float) -> Array:
	var p := _poly_point(c.pts, c.cum, jd)
	var pts: PackedVector3Array = c.pts
	# Heading follows the path's own tangent (exact for the curve).
	var tan: Vector3 = RoadNetwork.bezier_tangent(pts[0], c.ctrl, pts[pts.size() - 1], jd / c.len)
	tan.y = 0.0
	if tan.length() < 0.2:
		tan = c.d0.slerp(c.d1, jd / c.len)
	return [p, _flat_dir(tan)]


func _way_pose(w: Dictionary, lane: int, d: float) -> Array:
	var fwd := _way_dir(w, d)
	return [_poly_point(w.pts, w.cum, d) + Vector3(-fwd.z, 0.0, fwd.x) * w.offs[lane], fwd]


## Sets how a junction is controlled (a Rule, or -1 for automatic).
func set_rule(node: int, rule: int) -> bool:
	if not network.nodes.has(node) or network.segments_at(node).size() < 3:
		return false
	if rule < 0:
		if not overrides.has(node):
			return false
		overrides.erase(node)
	else:
		if overrides.get(node, -1) == rule:
			return false
		overrides[node] = clampi(rule, 0, Rule.PRIORITY)
	_rebuild()
	return true


func rules_to_dict() -> Dictionary:
	var out := {}
	for n in overrides:
		out[str(n)] = overrides[n]
	return out


func rules_from_dict(d: Dictionary) -> void:
	overrides.clear()
	for k in d:
		overrides[int(k)] = int(d[k])
	_dirty = true


## Whether a light shows green, yellow or red to cars arriving on a way.
func light(node: int, way: int) -> int:
	var j: Dictionary = junctions[node]
	if j.control != Rule.SIGNAL:
		return Light.GREEN
	var t := fposmod(time + j.offset, j.cycle)
	var start := 0.0
	for ph in j.phases:
		if ph.ways.has(way):
			if t >= start and t < ph.g_end:
				return Light.GREEN
			if t >= ph.g_end and t < ph.y_end:
				return Light.YELLOW
			return Light.RED
		start = ph.end
	return Light.RED


## The stop line where a way meets a junction: {pos, dir, right, curb}
## (curb = metres from the road's centre line to its right edge).
func stop_line(way: int) -> Dictionary:
	var w: Dictionary = ways[way]
	var fwd := _way_dir(w, w.s1)
	var spec: Dictionary = RoadStyle.TYPES[w.type]
	return {"pos": _poly_point(w.pts, w.cum, w.s1), "dir": fwd,
		"right": Vector3(-fwd.z, 0.0, fwd.x),
		"curb": maxf(w.offs[w.lanes - 1] + LANE_W * 0.5 + 0.6, spec.width * 0.5 + 0.6),
		"mid": (w.offs[0] + w.offs[w.lanes - 1]) * 0.5}


## Ways arriving at a junction.
func ways_into(node: int) -> Array:
	return _in.get(node, [])


## Lanes on a way that may turn into `next` (its lane arrows).
func lanes_for(way: int, next: int) -> Array:
	return _arrows.get(way, {}).get(next, [])


## Share of the speed limit cars manage on a way, 0 to 1 (1 if empty).
func way_speed(way: int) -> float:
	return _speed.get(way, 1.0)


func seg_length(seg: int) -> float:
	for wid in [seg * 2 + 1, seg * 2]:
		if ways.has(wid):
			return ways[wid].len
	return 0.0


static func limit(type: int) -> float:
	return RoadStyle.TYPES[type].mph * RoadStyle.MPH


## Lanes each way, and how far right of the centre line each lane runs
## (lane 0 is the leftmost in the direction of travel).
static func lane_offsets(type: int, oneway_flag: bool) -> PackedFloat32Array:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var offs := PackedFloat32Array()
	if RoadStyle.is_freeway(type):
		# Highways and ramps: 4 ft shoulder on the left.
		for k in spec.lanes:
			offs.append(-spec.width * 0.5 + 1.2 + LANE_W * (k + 0.5))
	elif oneway_flag or spec.oneway:
		# A one-way street (a roundabout ring): every lane goes one way.
		for k in spec.lanes:
			offs.append(-LANE_W * spec.lanes * 0.5 + LANE_W * (k + 0.5))
	else:
		var inner: float = spec.median * 0.5 + (RoadStyle.CURB_WIDTH if RoadStyle.raised_median(type) else 0.0)
		# Gravel roads and alleys have no lane lines: cars share what width
		# there is and squeeze by each other.
		var lane: float = LANE_W if spec.get("surface", "asphalt") == "asphalt" else minf(LANE_W, spec.width * 0.5 - inner)
		for k in spec.lanes / 2:
			offs.append(inner + lane * (k + 0.5))
	return offs


# --- Saving -------------------------------------------------------------------

## Every vehicle exactly as it is, mid-trip and mid-junction, so a loaded
## city (or a player joining a region) carries on tick for tick the same,
## and cargo on its way is never lost or doubled. Stored as Godot's exact
## text format, since JSON would round the numbers.
func to_dict() -> Dictionary:
	var list := []
	for car in cars + _waiting:
		var e: Dictionary = car.duplicate()
		for k in ["j", "conn", "pj"]:
			e[k] = _conn_key(car.get(k))
		e.erase("at")
		e.erase("facing")
		list.append(e)
	var state := {"cars": list, "waiting": _waiting.size(), "next_id": _next_id, "time": time,
		"gave_up": gave_up, "speed": _speed, "dirty": _dirty, "arrivals": arrivals, "failed": failed}
	return {"state": var_to_str(state)}


func from_dict(d: Dictionary) -> void:
	cars.clear()
	_waiting.clear()
	_dirty = true
	if not d.has("state"):
		return
	var state = str_to_var(str(d.state))
	if typeof(state) != TYPE_DICTIONARY:
		return
	var list: Array = state.cars
	var n_waiting: int = state.waiting
	for i in list.size():
		if i < list.size() - n_waiting:
			cars.append(list[i])
		else:
			_waiting.append(list[i])
	_next_id = state.next_id
	time = state.time
	gave_up = state.gave_up
	_speed = state.speed
	arrivals = state.arrivals
	failed = state.failed
	# Junction paths are rebuilt from the roads; keep every car's plan as it
	# was unless the saved city still had road changes to take in.
	_restoring = true
	_keep_routes = not state.dirty


## A junction or driveway path as plain data for saving.
static func _conn_key(c):
	if c == null or c is Array or c.has("drive"):
		return c  # still saved form (loaded, roads not rebuilt yet)
	if c.id >= 0:
		return [c.wi, c.li, c.wo, c.lo]
	return {"drive": [c.pts[0], c.ctrl, c.pts[c.pts.size() - 1]], "wo": c.wo, "lo": c.lo,
		"exit_d": c.exit_d, "vt": c.vt}


func _from_key(k):
	if k == null:
		return null
	if k is Array:
		if not ways.has(k[0]) or not ways.has(k[2]):
			return null
		return _connector(k[0], k[1], k[2], k[3])
	return _path({"node": -1, "wi": -1, "li": -1, "wo": k.wo, "lo": k.lo, "turn": Turn.RIGHT,
		"vt": k.vt, "exit_d": k.exit_d}, k.drive[0], k.drive[1], k.drive[2])


# --- Building the lanes -----------------------------------------------------# --- Building the lanes -----------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	version += 1
	# Remember where every car is, so it can carry on from the same spot
	# on whatever roads replace the old ones.
	for car in ([] if _restoring else cars):
		if car.j != null or ways.has(car.route[car.leg]):
			var pose := car_pose(car)
			car.at = pose[0]
			car.facing = pose[1]
	ways.clear()
	junctions.clear()
	_in.clear()
	_out.clear()
	_turns.clear()
	_arrows.clear()
	_kind.clear()
	_conns.clear()
	_conflict.clear()
	var seg_ids := network.segments.keys()
	seg_ids.sort()
	var at_node := {}
	for id in seg_ids:
		var s: Dictionary = network.segments[id]
		for n in [s.a, s.b]:
			if not at_node.has(n):
				at_node[n] = []
			at_node[n].append(id)
		var pts := network.sample_segment(id, 32)
		var c := network.curve_of(id)
		var r := RoadNetwork.min_radius(c[0], c[1], c[2])
		var curve_v := INF if r > 400.0 else RoadStyle.safe_speed_mph(r) * RoadStyle.MPH
		var one := network.is_oneway(id)
		var offs := lane_offsets(s.type, one)
		for fwd in [true, false]:
			if not fwd and one:
				continue
			var p := pts.duplicate()
			if not fwd:
				p.reverse()
			var cum := PackedFloat32Array([0.0])
			for i in range(1, p.size()):
				cum.append(cum[i - 1] + p[i].distance_to(p[i - 1]))
			var wid: int = id * 2 + (1 if fwd else 0)
			ways[wid] = {"id": wid, "seg": id, "fwd": fwd, "from": s.a if fwd else s.b,
				"to": s.b if fwd else s.a, "type": s.type, "pts": p, "cum": cum,
				"len": cum[cum.size() - 1], "lanes": offs.size(), "offs": offs,
				"vmax": maxf(minf(limit(s.type), curve_v), 4.0), "s0": 0.0, "s1": cum[cum.size() - 1]}
			if not _out.has(ways[wid].from):
				_out[ways[wid].from] = []
			_out[ways[wid].from].append(wid)
			if not _in.has(ways[wid].to):
				_in[ways[wid].to] = []
			_in[ways[wid].to].append(wid)
	var node_ids := at_node.keys()
	node_ids.sort()
	var setback := {}
	for n in node_ids:
		var segs: Array = at_node[n]
		var sb := 0.0
		if segs.size() >= 3:
			for id in segs:
				sb = maxf(sb, RoadStyle.half_width(network.segments[id].type) + 1.5)
		elif segs.size() == 2:
			var s1: Dictionary = network.segments[segs[0]]
			var s2: Dictionary = network.segments[segs[1]]
			if s1.type != s2.type or network.is_oneway(segs[0]) != network.is_oneway(segs[1]):
				sb = 5.0
		setback[n] = sb
	for wid in ways:
		var w: Dictionary = ways[wid]
		w.s0 = minf(setback[w.from], w.len * 0.4)
		w.s1 = maxf(w.len - setback[w.to], w.len * 0.6)
	for n in overrides.keys():
		if not at_node.has(n) or at_node[n].size() < 3:
			overrides.erase(n)
	for n in node_ids:
		_build_turns(n)
		_build_control(n, at_node[n])
	for wid in ways:
		if not _speed.has(wid):
			_speed[wid] = 1.0
	if _restoring:
		_restoring = false
		for car in cars + _waiting:
			for k in ["j", "conn", "pj"]:
				car[k] = _from_key(car[k])
		if _keep_routes:
			return
	_reroute_all()


## Which ways each arriving way may turn into, and from which lanes.
func _build_turns(n: int) -> void:
	for wi in _in.get(n, []):
		var w: Dictionary = ways[wi]
		var din := _way_dir(w, w.len)
		var outs := []
		var uturn := -1
		for wo in _out.get(n, []):
			var o: Dictionary = ways[wo]
			if o.seg == w.seg:
				uturn = wo
				continue
			var dout := _way_dir(o, 0.0)
			var ang := atan2(din.x * dout.z - din.z * dout.x, din.dot(dout))
			outs.append([ang, wo])
		if outs.is_empty() and uturn != -1:
			outs.append([PI, uturn])  # dead end: turn around
		outs.sort()
		var m := outs.size()
		var nl: int = w.lanes
		_turns[wi] = []
		_arrows[wi] = {}
		for j in m:
			var wo: int = outs[j][1]
			var ang: float = outs[j][0]
			var kind := Turn.STRAIGHT
			if wo == uturn:
				kind = Turn.UTURN
			elif ang > deg_to_rad(35.0):
				kind = Turn.RIGHT
			elif ang < deg_to_rad(-35.0):
				kind = Turn.LEFT
			_kind[Vector2i(wi, wo)] = kind
			# Lanes share the turns left to right, like auto lane arrows.
			var lanes := []
			for i in nl:
				if float(i + 1) / nl > float(j) / m + 0.0001 and float(i) / nl < float(j + 1) / m - 0.0001:
					lanes.append(i)
			_turns[wi].append(wo)
			_arrows[wi][wo] = lanes


## The lane a car lands in after a turn: lefts keep left, rights keep right,
## straight lines up from the right (so on-ramps join the right lane).
func _out_lane(wi: int, lane: int, wo: int) -> int:
	var allowed: Array = _arrows[wi][wo]
	var k: int = ways[wo].lanes
	match _kind[Vector2i(wi, wo)]:
		Turn.LEFT, Turn.UTURN:
			return clampi(lane - int(allowed[0]), 0, k - 1)
		Turn.RIGHT:
			return clampi(k - 1 - (int(allowed[allowed.size() - 1]) - lane), 0, k - 1)
	return clampi(k - 1 - (ways[wi].lanes - 1 - lane), 0, k - 1)


## Picks the junction control the way US traffic engineers would: lights
## where two big roads meet, stop signs on side streets, all-way stops
## between equal streets, yield on entry at roundabouts and merges.
func _build_control(n: int, segs: Array) -> void:
	var j := {"control": Rule.NONE, "pos": network.nodes[n], "major": {}, "sign": "stop",
		"phases": [], "cycle": 1.0, "offset": 0.0}
	junctions[n] = j
	if segs.size() < 3:
		return
	# Pair up roads that run straight through the junction.
	var dirs := {}
	var all_oneway := true
	for id in segs:
		var s: Dictionary = network.segments[id]
		var pts := network.sample_segment(id, 8)
		dirs[id] = _flat_dir(pts[1] - pts[0]) if s.a == n else _flat_dir(pts[7] - pts[8])
		if not RoadStyle.TYPES[s.type].oneway:
			all_oneway = false
	var pairs := []
	for i in segs.size():
		for k in range(i + 1, segs.size()):
			var dot: float = dirs[segs[i]].dot(dirs[segs[k]])
			if dot < -0.8:
				pairs.append([dot, segs[i], segs[k]])
	pairs.sort()
	var used := {}
	var groups := []  # [rank, is_through, [segs]]
	for p in pairs:
		if used.has(p[1]) or used.has(p[2]):
			continue
		used[p[1]] = true
		used[p[2]] = true
		groups.append([maxi(_rank(p[1]), _rank(p[2])), 1, [p[1], p[2]]])
	for id in segs:
		if not used.has(id):
			groups.append([_rank(id), 0, [id]])
	groups.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] > y[1]))
	var big := 0
	for g in groups:
		if g[0] >= 1:
			big += 1
	var ring := []
	for id in segs:
		if _is_ring(id):
			ring.append(id)
	var control := Rule.ALL_STOP
	if not ring.is_empty():
		# Roundabout: cars on the ring go first, entering cars yield.
		groups.push_front([9, 1, ring])
		control = Rule.PRIORITY
		j.sign = "yield"
	elif all_oneway:
		control = Rule.PRIORITY if groups[0][1] == 1 else Rule.NONE
		j.sign = "yield"
	elif big >= 2 and not _curvy(groups[0][2]):
		control = Rule.SIGNAL
	elif groups.size() > 1 and (groups[0][0] > groups[1][0] or groups[0][1] > groups[1][1]):
		control = Rule.PRIORITY
		# Roundabout rings are curved: entering cars yield instead of stopping.
		j.sign = "yield" if _curvy(groups[0][2]) else "stop"
	if overrides.has(n):
		control = overrides[n]
	j.control = control
	for wi in _in.get(n, []):
		if groups[0][2].has(ways[wi].seg):
			j.major[wi] = true
	if control == Rule.SIGNAL:
		var t := 0.0
		for g in groups:
			var ph_ways := {}
			var v := 0.0
			for wi in _in.get(n, []):
				if g[2].has(ways[wi].seg):
					ph_ways[wi] = true
					v = maxf(v, limit(ways[wi].type))
			if ph_ways.is_empty():
				continue
			# Yellow by the ITE formula: 1 s to react, then brake at 10 ft/s^2.
			var yellow := clampf(1.0 + v / (2.0 * 3.05), 3.0, 6.0)
			var green: float = 16.0 + 6.0 * g[0]
			j.phases.append({"ways": ph_ways, "g_end": t + green, "y_end": t + green + yellow,
				"end": t + green + yellow + 1.5})
			t += green + yellow + 1.5
		j.cycle = maxf(t, 1.0)
		j.offset = fposmod(n * 37.0, j.cycle)


func _rank(seg: int) -> int:
	var type: int = network.segments[seg].type
	return [0, 1, 2, 3, 1, 1, 1][mini(type if RoadStyle.is_ring(type) else RoadStyle.group(type), 6)]


## Roundabout ring pieces: one-way roads that aren't highways or ramps.
func _is_ring(seg: int) -> bool:
	var s: Dictionary = network.segments[seg]
	return RoadStyle.is_ring(s.type) or (network.is_oneway(seg) and not RoadStyle.TYPES[s.type].oneway)


func _curvy(segs: Array) -> bool:
	for id in segs:
		var c := network.curve_of(id)
		if RoadNetwork.min_radius(c[0], c[1], c[2]) < 70.0:
			return true
	return false


## The curved path a car takes across a junction from one lane to another.
func _connector(wi: int, li: int, wo: int, lo: int) -> Dictionary:
	var key := Vector4i(wi, li, wo, lo)
	if _conns.has(key):
		return _conns[key]
	var a: Dictionary = ways[wi]
	var b: Dictionary = ways[wo]
	var da := _way_dir(a, a.s1)
	var db := _way_dir(b, b.s0)
	var p0: Vector3 = _poly_point(a.pts, a.cum, a.s1) + Vector3(-da.z, 0.0, da.x) * a.offs[li]
	var p2: Vector3 = _poly_point(b.pts, b.cum, b.s0) + Vector3(-db.z, 0.0, db.x) * b.offs[lo]
	var kind: int = _kind[Vector2i(wi, wo)]
	var chord := p0.distance_to(p2)
	var ctrl := (p0 + p2) * 0.5
	if kind == Turn.UTURN:
		ctrl += da * (chord + 4.0)
	else:
		# Where the two lane lines would meet.
		var den := da.x * db.z - da.z * db.x
		if absf(den) > 0.05:
			var t := ((p2.x - p0.x) * db.z - (p2.z - p0.z) * db.x) / den
			if t > 0.0 and t < chord * 1.5:
				ctrl = Vector3(p0.x + da.x * t, (p0.y + p2.y) * 0.5, p0.z + da.z * t)
	if chord < 1.0:
		ctrl = (p0 + p2) * 0.5  # lanes line up: no bend to draw
	var pts := RoadNetwork.sample_curve(p0, ctrl, p2, 10)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var vt: float = TURN_V[kind]
	if kind == Turn.STRAIGHT:
		vt = minf(a.vmax, b.vmax)
	var c := {"id": _next_conn, "node": a.to, "wi": wi, "li": li, "wo": wo, "lo": lo,
		"turn": kind, "pts": pts, "cum": cum, "len": maxf(cum[cum.size() - 1], 0.5), "vt": vt,
		"exit_d": b.s0, "ctrl": ctrl, "d0": da, "d1": db}
	_next_conn += 1
	_conns[key] = c
	return c


## Whether two junction paths cross or merge.
func _conflicts(c1: Dictionary, c2: Dictionary) -> bool:
	if c1.wi == c2.wi and c1.li == c2.li:
		return false  # same lane: they just follow each other
	if c1.wo == c2.wo and c1.lo == c2.lo:
		return true   # merging into one lane
	var key := Vector2i(mini(c1.id, c2.id), maxi(c1.id, c2.id))
	if _conflict.has(key):
		return _conflict[key]
	var hit := false
	var p: PackedVector3Array = c1.pts
	var q: PackedVector3Array = c2.pts
	for i in p.size() - 1:
		for k in q.size() - 1:
			var cp := Geometry2D.get_closest_points_between_segments(
				Vector2(p[i].x, p[i].z), Vector2(p[i + 1].x, p[i + 1].z),
				Vector2(q[k].x, q[k].z), Vector2(q[k + 1].x, q[k + 1].z))
			if cp[0].distance_to(cp[1]) < 2.4:
				hit = true
				break
		if hit:
			break
	_conflict[key] = hit
	return hit


# --- Route planning ---------------------------------------------------------

## Expected seconds to drive a whole way, from live speeds there.
func _way_cost(wid: int) -> float:
	if not ways.has(wid):
		return INF  # the road was rebuilt under this route
	var w: Dictionary = ways[wid]
	return w.len / (w.vmax * maxf(_speed.get(wid, 1.0), 0.15))


## Expected seconds lost turning from one way into another.
func _turn_cost(wi: int, wo: int) -> float:
	if not ways.has(wi) or not _kind.has(Vector2i(wi, wo)):
		return INF  # the road was rebuilt under this route
	var j: Dictionary = junctions[ways[wi].to]
	var cost := 0.0
	match j.control:
		Rule.SIGNAL: cost = 10.0
		Rule.ALL_STOP: cost = 5.0
		Rule.PRIORITY: cost = 0.0 if j.major.has(wi) else 4.0
	match _kind[Vector2i(wi, wo)]:
		Turn.LEFT: cost += 3.0
		Turn.RIGHT: cost += 1.0
		Turn.UTURN: cost += 20.0
	return cost


## Fastest route from any start [way, d] to any target way (value: where on
## it to stop). Returns the ways in order, or [] if none. `lane` >= 0 limits
## the first turn to ones that lane is allowed to make.
func _plan(starts: Array, targets: Dictionary, lane := -1, pen := {}) -> Array:
	var best := INF
	var best_route := []
	for s in starts:
		if targets.has(s[0]) and targets[s[0]] > s[1] + 1.0:
			var cost: float = (targets[s[0]] - s[1]) / ways[s[0]].vmax + pen.get(s[0], 0.0) \
				+ (s[2] if s.size() > 2 else 0.0)
			if cost < best:
				best = cost
				best_route = [s[0]]
	var dist := {}
	var prev := {}
	var heap := []
	for s in starts:
		var w: Dictionary = ways[s[0]]
		var g: float = maxf(w.len - s[1], 0.0) / w.vmax + (s[2] if s.size() > 2 else 0.0)
		if g < dist.get(s[0], INF):
			dist[s[0]] = g
			_push(heap, [g, s[0]])
	var end := -1
	var end_prev := -1
	var first := lane >= 0
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var g: float = top[0]
		var u: int = top[1]
		if g > dist[u] + 0.0001:
			continue
		if g >= best:
			break
		for nx in _turns.get(u, []):
			if first and not _arrows[u][nx].has(lane):
				continue
			var e: float = g + _turn_cost(u, nx)
			if targets.has(nx):
				var cand: float = e + targets[nx] / ways[nx].vmax + pen.get(nx, 0.0)
				if cand < best:
					best = cand
					end = nx
					end_prev = u
					best_route = []
			var ng := e + _way_cost(nx)
			if ng < dist.get(nx, INF):
				dist[nx] = ng
				prev[nx] = u
				_push(heap, [ng, nx])
		first = false
	if best_route.is_empty() and end != -1:
		var route := [end]
		var x := end_prev
		var guard := 0
		while guard < 10000:
			route.push_front(x)
			if not prev.has(x):
				break
			x = prev[x]
			guard += 1
		return route
	return best_route


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _less(heap[i], heap[p]):
			var t = heap[i]
			heap[i] = heap[p]
			heap[p] = t
			i = p
		else:
			break


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < heap.size() and _less(heap[l], heap[m]):
				m = l
			if r < heap.size() and _less(heap[r], heap[m]):
				m = r
			if m == i:
				break
			var t = heap[i]
			heap[i] = heap[m]
			heap[m] = t
			i = m
	return top


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


## Where on each way of a road piece a car would stop for a lot.
func _targets(goal: Dictionary) -> Dictionary:
	var out := {}
	for fwd in [true, false]:
		var wid: int = goal.seg * 2 + (1 if fwd else 0)
		if ways.has(wid):
			var len: float = ways[wid].len
			out[wid] = goal.frac * len if fwd else len - goal.frac * len
	return out


## Seconds added for reaching a lot on the far side of the road (a left turn
## across oncoming traffic), so drivers prefer to arrive with it on the right.
func _side_pen(seg: int, side: int) -> Dictionary:
	var out := {}
	for fwd in [true, false]:
		var on_right: bool = (side > 0) == fwd
		out[seg * 2 + (1 if fwd else 0)] = 0.0 if on_right else CROSS_PEN
	return out


## A car driving from one lot's driveway to another's, or {} if no route.
func _route(from: Dictionary, to: Dictionary) -> Dictionary:
	if _dirty:
		_rebuild()
	var starts := []
	var out_pen := _side_pen(from.seg, from.get("side", 1))
	for fwd in [true, false]:
		var wid: int = from.seg * 2 + (1 if fwd else 0)
		if ways.has(wid):
			var len: float = ways[wid].len
			starts.append([wid, from.at_frac * len if fwd else len - from.at_frac * len, out_pen[wid]])
	var goal := {"seg": to.seg, "frac": to.at_frac, "side": to.get("side", 1)}
	var targets := _targets(goal)
	if starts.is_empty() or targets.is_empty():
		return {}
	var route := _plan(starts, targets, -1, _side_pen(goal.seg, goal.side))
	if route.is_empty():
		return {}
	var d := 0.0
	for s in starts:
		if s[0] == route[0]:
			d = s[1]
	var w0: Dictionary = ways[route[0]]
	if route.size() > 1:
		d = minf(d, w0.s1 - 0.5)
	return {"route": route, "leg": 0, "d": d, "end_d": targets[route[route.size() - 1]],
		"goal": goal, "dest": to.get("front", Vector3.ZERO), "lane": w0.lanes - 1, "v": 0.0,
		"park": _park_point(to), "home": _park_point(from)}


## Where a car parks on a lot: up its driveway, off the street.
static func _park_point(lot: Dictionary):
	if lot.has("park_pt"):
		return lot.park_pt
	if not lot.has("front") or not lot.has("normal"):
		return null
	return lot.front + lot.normal * 7.0


## Re-plans the rest of a car's trip from where it is now.
func _replan(car: Dictionary, lane := -1) -> bool:
	var targets := _targets(car.goal)
	if targets.is_empty():
		return false
	var wid: int = car.route[car.leg]
	var route := _plan([[wid, car.d]], targets, lane, _side_pen(car.goal.seg, car.goal.get("side", 1)))
	if route.is_empty():
		return false
	car.route = route
	car.leg = 0
	car.end_d = targets[route[route.size() - 1]]
	return true


## The way under a point that runs the way a car is facing: [way, d], or [].
func _locate(at, facing: Vector3) -> Array:
	if at == null:
		return []
	var near := network.find_segment_near(at, 25.0, 3.0)
	if near.is_empty():
		return []
	var best := []
	var best_dot := -2.0
	for fwd in [true, false]:
		var wid: int = near.seg * 2 + (1 if fwd else 0)
		if not ways.has(wid):
			continue
		var d := _nearest_d(ways[wid], at)
		var dot := _way_dir(ways[wid], d).dot(facing)
		if dot > best_dot:
			best_dot = dot
			best = [wid, d]
	return best


## How far along a way the point nearest `p` is.
func _nearest_d(w: Dictionary, p: Vector3) -> float:
	var pts: PackedVector3Array = w.pts
	var best := 0.0
	var best_dist := INF
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
		var dist := q.distance_to(Vector2(p.x, p.z))
		if dist < best_dist:
			best_dist = dist
			best = w.cum[i] + a.distance_to(q)
	return best


## Tells whoever sent a vehicle with a job how it went.
static func _report(car: Dictionary, into: Array) -> void:
	if car.get("to_ref", "") != "":
		into.append({"id": car.id, "purpose": car.purpose, "cargo": car.cargo,
			"from": car.from_ref, "to": car.to_ref})


## After the roads change, every car finds its way again (or gives up).
func _reroute_all() -> void:
	var kept := []
	for car in cars:
		var wid: int = car.route[car.leg]
		if car.j != null and car.j.wo < 0:
			_report(car, arrivals)
			continue  # was parking: it has arrived
		if car.j != null or not ways.has(wid):
			# Its road was split or replaced: find the new piece under it.
			var found := _locate(car.get("at", null), car.get("facing", Vector3.ZERO))
			if found.is_empty():
				continue
			wid = found[0]
			car.route = [wid]
			car.leg = 0
			car.d = found[1]
			car.j = null
			car.lc_t = 1.0
		var w: Dictionary = ways[wid]
		car.lane = mini(car.lane, w.lanes - 1)
		car.pj = null
		car.commit = false
		car.conn = null
		car.lc_t = 1.0
		car.d = clampf(car.d, 0.0, w.len)
		if not network.segments.has(car.goal.seg):
			var near := network.find_segment_near(car.dest, 60.0)
			if near.is_empty():
				continue
			var fw: int = near.seg * 2 + 1
			var frac: float = near.t
			if ways.has(fw):
				frac = _nearest_d(ways[fw], near.point) / maxf(ways[fw].len, 0.001)
			car.goal = {"seg": near.seg, "frac": frac, "side": car.goal.get("side", 1)}
		if not _replan(car):
			continue
		kept.append(car)
	for car in cars:
		if not kept.has(car) and not (car.j != null and car.j.wo < 0):
			_report(car, failed)
	cars = kept


# --- Trips ------------------------------------------------------------------

## Trips follow the time of day: to work in the morning, home in the evening,
## to the shops in between. Factories send box trucks to the shops by day.
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
	var by_zone := {ZoneMap.Zone.RESIDENTIAL: [], ZoneMap.Zone.COMMERCIAL: [], ZoneMap.Zone.INDUSTRIAL: []}
	for key in sim.buildings:
		if sim.lots.has(key) and by_zone.has(sim.buildings[key].zone):
			by_zone[sim.buildings[key].zone].append(key)
	for z in by_zone:
		by_zone[z].sort()
	var homes: Array = by_zone[ZoneMap.Zone.RESIDENTIAL]
	var shops: Array = by_zone[ZoneMap.Zone.COMMERCIAL]
	var plants: Array = by_zone[ZoneMap.Zone.INDUSTRIAL]
	if background_freight and hour >= 6 and hour < 20 and not shops.is_empty() and not plants.is_empty() \
			and rng.randf() < 0.12:
		add_trip(sim.lots[plants[rng.randi() % plants.size()]], sim.lots[shops[rng.randi() % shops.size()]],
			rng, "", "goods")
		return
	var dests := shops + plants
	if homes.is_empty() or dests.is_empty():
		return
	var a: Dictionary = sim.lots[homes[rng.randi() % homes.size()]]
	var dest_key: String = dests[rng.randi() % dests.size()]
	var b: Dictionary = sim.lots[dest_key]
	var purpose := "shopping" if sim.buildings[dest_key].zone == ZoneMap.Zone.COMMERCIAL else "commute"
	if hour >= 15:
		var t := a
		a = b
		b = t
	add_trip(a, b, rng, "", purpose)


## Sends a vehicle from one lot to another: it backs out of the driveway,
## drives, and pulls into the other lot's driveway. Returns false if there's
## no route or no gap in traffic to pull out into.
func add_trip(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator, kind := "",
		purpose := "", cargo := {}) -> bool:
	if cars.size() >= MAX_CARS:
		return false
	var car := _route(a, b)
	if car.is_empty():
		return false
	if purpose == "":
		purpose = "commute"
	if kind == "":
		kind = VehicleTypes.for_purpose(purpose, rng)
	var spec := VehicleTypes.spec(kind)
	car.merge({"id": _next_id, "kind": kind, "len": float(spec.len), "acc": float(spec.acc),
		"top": float(spec.top_speed), "pj": null,
		"color": rng.randi() % 8, "pref": float(spec.pref) * (0.9 + rng.randf() * 0.2),
		"purpose": purpose, "cargo": cargo, "from_ref": a.get("ref", ""), "to_ref": b.get("ref", ""),
		"j": null, "jd": 0.0, "commit": false, "conn": null, "arrive": -1.0, "stuck": 0.0,
		"lc_from": 0.0, "lc_t": 1.0, "lc_cool": 2.0, "a": 0.0, "held": false})
	_next_id += 1
	if not _launch(car):
		if car.to_ref == "":
			return false
		_waiting.append(car)  # goods always go: wait for a gap
	return true


## Sends a vehicle with a job: goods, a delivery, a service call. `from` and
## `to` are {"ref": any id the caller wants back, "pos": [x, z]}; the vehicle
## leaves from the road nearest `from`, parks at `to`, and its trip shows up
## in `arrivals` when it gets there (or in `failed` if it can't). Returns the
## trip id, or -1 if no road leads there. `kind` picks the vehicle (blank:
## one fitting the purpose).
func dispatch(from: Dictionary, to: Dictionary, purpose: String, cargo := {}, kind := "") -> int:
	if _dirty:
		_rebuild()
	var a := _endpoint(from)
	var b := _endpoint(to)
	if a.is_empty() or b.is_empty():
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_next_id, purpose, "dispatch"])
	var id := _next_id
	if not add_trip(a, b, rng, kind, purpose, cargo):
		return -1
	return id


## A place given as {"ref", "pos": [x, z]}, as a lot-like stop on the nearest road.
func _endpoint(e: Dictionary) -> Dictionary:
	var pos := Vector3(float(e.pos[0]), 0.0, float(e.pos[1]))
	var near := network.find_segment_near(pos, 80.0)
	if near.is_empty():
		return {}
	var wid: int = near.seg * 2 + 1
	if not ways.has(wid):
		wid = near.seg * 2
	if not ways.has(wid):
		return {}
	var w: Dictionary = ways[wid]
	var d := _nearest_d(w, pos)
	var dir := _way_dir(w, d)
	var off := pos - _poly_point(w.pts, w.cum, d)
	var side := 1 if off.dot(Vector3(-dir.z, 0.0, dir.x)) >= 0.0 else -1
	if not w.fwd:
		side = -side
	var frac := d / maxf(w.len, 0.001)
	if not w.fwd:
		frac = 1.0 - frac
	return {"ref": e.get("ref", ""), "seg": near.seg, "at_frac": frac, "side": side, "front": pos,
		"park_pt": pos}


## Puts a new vehicle on the road if there's a gap. Returns false if not.
func _launch(car: Dictionary) -> bool:
	var w: Dictionary = ways[car.route[0]]
	var last: bool = car.route.size() == 1
	var limit: float = car.end_d - 4.0 if last else w.s1 - 0.5
	var exit_d := minf(car.d + DRIVEWAY_LEAD + 2.0, limit)
	if exit_d <= car.d + 1.0 and last:
		return false  # next door: walk
	# Pull out only when there's a gap in the traffic.
	for other in cars:
		var lane_way: int = other.route[other.leg]
		if other.j != null:
			if other.j.wo != car.route[0] or other.j.lo != car.lane:
				continue
			lane_way = car.route[0]
		elif lane_way != car.route[0] or other.lane != car.lane:
			continue
		var od: float = other.d if other.j == null else other.j.exit_d
		if od > car.d - 30.0 and od < exit_d + 12.0:
			return false
	if car.home != null:
		car.j = _driveway_out(car, exit_d)
	else:
		car.d = exit_d
	cars.append(car)
	return true


## The path out of a driveway into the nearest lane.
func _driveway_out(car: Dictionary, exit_d: float) -> Dictionary:
	var w: Dictionary = ways[car.route[0]]
	# A drive right by the end of the street can't swing forward its usual
	# distance: it swings back a little, so the car still meets the lane
	# heading the lane's way.
	var corner := _lane_point(w, car.lane, maxf(minf(car.d, exit_d - 3.0), 0.0))
	var p2 := _lane_point(w, car.lane, exit_d)
	return _path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": car.lane, "turn": Turn.RIGHT,
		"vt": 5.0, "exit_d": exit_d}, car.home, corner, p2)


## The path from the lane into the parking spot up a driveway.
func _driveway_in(car: Dictionary) -> Dictionary:
	var w: Dictionary = ways[car.route[car.leg]]
	var p0 := _lane_point(w, car.lane, car.d)
	var ahead := _lane_point(w, car.lane, minf(maxf(car.end_d, car.d + 2.0), w.len))
	return _path({"node": -1, "wi": -1, "li": -1, "wo": -1, "lo": -1, "turn": Turn.RIGHT,
		"vt": 4.0, "exit_d": 0.0}, p0, ahead, car.park)


func _path(c: Dictionary, p0: Vector3, ctrl: Vector3, p2: Vector3) -> Dictionary:
	var pts := RoadNetwork.sample_curve(p0, ctrl, p2, 10)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	c.merge({"id": -1, "pts": pts, "cum": cum, "len": maxf(cum[cum.size() - 1], 0.5), "ctrl": ctrl,
		"d0": _flat_dir(ctrl - p0), "d1": _flat_dir(p2 - ctrl)})
	return c


func _lane_point(w: Dictionary, lane: int, d: float) -> Vector3:
	var f := _way_dir(w, d)
	return _poly_point(w.pts, w.cum, d) + Vector3(-f.z, 0.0, f.x) * w.offs[lane]


# --- Driving ----------------------------------------------------------------

func _drive(_rng: RandomNumberGenerator) -> void:
	# Vehicles with a job that were waiting for a gap to pull out.
	for car in _waiting.duplicate():
		if not ways.has(car.route[0]) or car.route.any(func(w): return not ways.has(w)) and not _replan(car):
			# Its road went, or was rebuilt and there's no way through now.
			_waiting.erase(car)
			_report(car, failed)
		elif cars.size() < MAX_CARS and _launch(car):
			_waiting.erase(car)
	_snapshot()
	for key in _lanes:
		var list: Array = _lanes[key]
		for i in list.size():
			list[i].a = _accel_on_way(list[i], list, i)
	for n in _box:
		for car in _box[n]:
			car.a = _accel_in_box(car)
	_lane_changes()
	_replan_some()
	var done := []
	var speed_sum := 0.0
	var limit_sum := 0.0
	var way_sum := {}
	for car in cars:
		car.v = maxf(car.v + car.a * DT, 0.0)
		if car.lc_t < 1.0:
			car.lc_t = minf(car.lc_t + DT / LC_TIME, 1.0)
		car.lc_cool -= DT
		car.stuck = car.stuck + DT if car.v < 0.3 else 0.0
		if car.stuck > STUCK_LIMIT:
			gave_up += 1
			done.append(car)
			_report(car, failed)
			continue
		if car.j != null:
			car.jd += car.v * DT
			speed_sum += 1.0
			limit_sum += 1.0
			if car.jd >= car.j.len:
				if car.j.wo < 0:
					done.append(car)  # parked
					_report(car, arrivals)
				else:
					car.d = car.j.exit_d + car.jd - car.j.len
					car.pj = car.j  # remembered for trailers
					car.j = null
			continue
		var w: Dictionary = ways[car.route[car.leg]]
		car.d += car.v * DT
		var share: float = minf(car.v / w.vmax, 1.0) if car.get("held", false) else 1.0
		speed_sum += share
		limit_sum += 1.0
		if not way_sum.has(w.id):
			way_sum[w.id] = [0.0, 0]
		way_sum[w.id][0] += share
		way_sum[w.id][1] += 1
		if car.leg == car.route.size() - 1:
			# Start turning in a few metres early, so the driveway is a smooth arc.
			if car.d >= car.end_d - (1.0 if car.park == null else DRIVEWAY_LEAD):
				if car.park == null or car_pose(car)[0].distance_to(car.park) < 9.0:
					done.append(car)  # no room for a driveway turn: just stop here
					_report(car, arrivals)
				else:
					car.j = _driveway_in(car)
					car.jd = 0.0
		elif car.d >= w.s1:
			if car.commit:
				# Into the junction, on the curved path to the next lane.
				var c: Dictionary = car.conn
				car.j = c
				car.jd = car.d - w.s1
				car.leg += 1
				car.lane = c.lo
				car.commit = false
				car.conn = null
				car.arrive = -1.0
				car.lc_t = 1.0
			else:
				car.d = w.s1
				car.v = 0.0
	for car in done:
		cars.erase(car)
	# Snapped so the value survives a save and load exactly (saves and region
	# snapshots must give the same city).
	for wid in _speed:
		if way_sum.has(wid):
			_speed[wid] = snappedf(lerpf(_speed[wid], way_sum[wid][0] / way_sum[wid][1], 0.05), 0.000001)
		else:
			_speed[wid] = snappedf(lerpf(_speed[wid], 1.0, 0.02), 0.000001)
	flow = 1.0 if limit_sum == 0.0 else clampf(speed_sum / limit_sum, 0.0, 1.0)


func _snapshot() -> void:
	_lanes.clear()
	_box.clear()
	_committed.clear()
	_approach.clear()
	_merging.clear()
	for car in cars:
		if car.j != null:
			if car.j.node == -1 and car.j.wo >= 0:
				var mk: int = car.j.wo * 8 + car.j.lo
				if not _merging.has(mk):
					_merging[mk] = []
				_merging[mk].append(car)
			if not _box.has(car.j.node):
				_box[car.j.node] = []
			_box[car.j.node].append(car)
			continue
		var key: int = car.route[car.leg] * 8 + car.lane
		if not _lanes.has(key):
			_lanes[key] = []
		_lanes[key].append(car)
		if car.commit:
			if not _committed.has(car.conn.node):
				_committed[car.conn.node] = []
			_committed[car.conn.node].append(car)
	for key in _lanes:
		_lanes[key].sort_custom(func(x, y): return x.d > y.d or (x.d == y.d and x.id < y.id))
		# Cars held up by the car in front count against traffic flow; a car
		# slowing on an open road for a turn, sign or light does not.
		var list: Array = _lanes[key]
		list[0].held = false
		for i in range(1, list.size()):
			list[i].held = list[i - 1].d - list[i].d - list[i - 1].len < 12.0 + list[i].v * 2.0
		var front: Dictionary = _lanes[key][0]
		if front.leg == front.route.size() - 1:
			continue
		var w: Dictionary = ways[front.route[front.leg]]
		var ds: float = w.s1 - front.d
		if ds > 80.0:
			continue
		var c := _conn_for(front)
		if c.is_empty():
			continue
		if not _approach.has(c.node):
			_approach[c.node] = []
		_approach[c.node].append({"car": front, "conn": c, "ds": ds})


## The junction path a car will take at the end of its way, or {} if its
## lane can't make the turn it planned.
func _conn_for(car: Dictionary) -> Dictionary:
	var wi: int = car.route[car.leg]
	var wo: int = car.route[car.leg + 1]
	if not lanes_for(wi, wo).has(car.lane):
		return {}
	return _connector(wi, car.lane, wo, _out_lane(wi, car.lane, wo))


## Intelligent Driver Model: acceleration for speed v wanting v0, with a gap
## to the car (or stop line) ahead that is moving at vl.
func _idm(v: float, v0: float, gap: float, vl: float, acc := -1.0) -> float:
	if acc < 0.0:
		acc = _acc
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	if gap == INF:
		return clampf(acc * free, -MAX_BRAKE, acc)
	var s_star := JAM_GAP + maxf(0.0, v * HEADWAY + v * (v - vl) / (2.0 * sqrt(acc * BRAKE)))
	var a := acc * (free - pow(s_star / maxf(gap, 0.1), 2.0))
	return clampf(a, -MAX_BRAKE, acc)


func _accel_on_way(car: Dictionary, list: Array, i: int) -> float:
	_acc = car.acc
	var w: Dictionary = ways[car.route[car.leg]]
	var v0: float = minf(w.vmax * car.pref, car.top)
	var gap := INF
	var vl := 0.0
	if i > 0:
		gap = list[i - 1].d - car.d - list[i - 1].len
		vl = list[i - 1].v
	# A car pulling out of a driveway ahead counts as a leader once it has
	# started its turn, so the lane makes room as it merges (CS2 yields the
	# same way). Its place is measured along the lane, like a junction exit.
	for m in _merging.get(w.id * 8 + car.lane, []):
		var pos: float = m.j.exit_d - (m.j.len - m.jd)
		if pos > car.d and pos - car.d - m.len < gap:
			gap = pos - car.d - m.len
			vl = m.v
	if car.leg == car.route.size() - 1:
		# Slow to turn into the driveway.
		return minf(_idm(car.v, v0, gap, vl), _idm(car.v, v0, car.end_d - car.d + JAM_GAP + 4.0 * HEADWAY, 4.0))
	var ds: float = w.s1 - car.d
	var wo: int = car.route[car.leg + 1]
	if not lanes_for(w.id, wo).has(car.lane):
		# Wrong lane for the turn: slow down to find a gap, and if the car
		# reaches the line still stuck in it, take what this lane allows.
		if ds < 100.0:
			v0 = minf(v0, 5.0 + ds * 0.15)
		var acc := _idm(car.v, v0, gap, vl)
		if i == 0:
			acc = minf(acc, _idm(car.v, v0, ds - 0.5, 0.0))
			if ds < 4.0 and car.v < 1.0:
				if not _replan(car, car.lane):
					car.end_d = car.d + 1.0  # nowhere to go: pull over here
					car.route = [w.id]
					car.leg = 0
		return acc
	var acc := _idm(car.v, v0, gap, vl)
	if i > 0 or ds > LOOK:
		return acc
	var c := _conn_for(car)
	if not car.commit:
		if ds < 4.0 and car.v < 0.5 and car.arrive < 0.0:
			car.arrive = time
		if _may_enter(car, c, ds) and ds <= car.v * car.v / (2.0 * BRAKE) + 4.0:
			car.commit = true
			car.conn = c
			if not _committed.has(c.node):
				_committed[c.node] = []
			_committed[c.node].append(car)
	if car.commit:
		var lead := _through_leader(c, ds, car)
		acc = minf(acc, _idm(car.v, v0, lead[0], lead[1]))
		# Ease off for the turn.
		var vt: float = c.vt
		if vt < car.v:
			acc = minf(acc, _idm(car.v, v0, ds + JAM_GAP + vt * HEADWAY, vt))
	else:
		acc = minf(acc, _idm(car.v, v0, ds - 0.5, 0.0))
	return acc


func _accel_in_box(car: Dictionary) -> float:
	_acc = car.acc
	var c: Dictionary = car.j
	var lead := _through_leader(c, -car.jd, car)
	return _idm(car.v, c.vt, lead[0], lead[1])


## The nearest car ahead once across the junction: [gap, its speed].
## Positions are measured along the lane being turned into, so cars still
## on the junction path count as just behind its start.
func _through_leader(c: Dictionary, ds: float, me: Dictionary) -> Array:
	if c.wo < 0:
		return [INF, 0.0]  # into a driveway
	var mine: float = c.exit_d - c.len - ds
	var best := INF
	var bv := 0.0
	var blen := CAR_LEN
	var list: Array = _lanes.get(c.wo * 8 + c.lo, [])
	for k in range(list.size() - 1, -1, -1):
		if list[k] != me and list[k].d > mine:
			best = list[k].d
			bv = list[k].v
			blen = list[k].len
			break
	for b in _box.get(c.node, []):
		if b == me or b.j.wo != c.wo or b.j.lo != c.lo:
			continue
		var pos: float = b.j.exit_d - (b.j.len - b.jd)
		if pos > mine and pos < best:
			best = pos
			bv = b.v
			blen = b.len
	if best == INF:
		return [INF, 0.0]
	return [best - mine - blen, bv]


## Whether a car at the stop line may go now.
func _may_enter(car: Dictionary, c: Dictionary, ds: float) -> bool:
	var n: int = c.node
	var j: Dictionary = junctions[n]
	var occupants: Array = _box.get(n, []) + _committed.get(n, [])
	# Don't block the box: there must be room on the far side.
	var queued := 0
	for b in occupants:
		var bc: Dictionary = b.j if b.j != null else b.conn
		if b != car and bc.wo == c.wo and bc.lo == c.lo:
			queued += 1
	var list: Array = _lanes.get(c.wo * 8 + c.lo, [])
	if not list.is_empty():
		var room: float = list[list.size() - 1].d - ways[c.wo].s0
		if room < (queued + 1) * (car.len + JAM_GAP):
			return false
	# Nothing crossing our path in the junction.
	for b in occupants:
		if b == car:
			continue
		var bc: Dictionary = b.j if b.j != null else b.conn
		if _conflicts(c, bc):
			return false
	var stopped: bool = car.arrive >= 0.0 and time - car.arrive >= 1.0
	var mine_minor_turn: bool = c.turn == Turn.LEFT or c.turn == Turn.UTURN
	match j.control:
		Rule.SIGNAL:
			var st := light(n, c.wi)
			var on_red := false
			if st == Light.RED:
				# Right on red after a full stop (allowed across the US).
				if c.turn == Turn.RIGHT and stopped:
					on_red = true
				else:
					return false
			elif st == Light.YELLOW and car.v * car.v / (2.0 * BRAKE) < ds - 1.0:
				return false
			for ap in _approach.get(n, []):
				if ap.car == car or ap.conn.wi == c.wi or light(n, ap.conn.wi) != Light.GREEN:
					continue
				var theirs_minor: bool = ap.conn.turn == Turn.LEFT or ap.conn.turn == Turn.UTURN
				if (on_red or (mine_minor_turn and not theirs_minor)) and _soon(ap) and _conflicts(c, ap.conn):
					return false
		Rule.ALL_STOP:
			if not stopped:
				return false
			for ap in _approach.get(n, []):
				if ap.car != car and ap.conn.wi != c.wi and _first(ap.car, car) and _conflicts(c, ap.conn):
					return false
		Rule.PRIORITY:
			if not j.major.has(c.wi):
				if j.sign == "stop" and not stopped:
					return false
				for ap in _approach.get(n, []):
					if ap.car == car or ap.conn.wi == c.wi:
						continue
					if j.major.has(ap.conn.wi):
						if _soon(ap) and _conflicts(c, ap.conn):
							return false
					elif _first(ap.car, car) and _conflicts(c, ap.conn):
						return false
			elif mine_minor_turn:
				for ap in _approach.get(n, []):
					if ap.car == car or ap.conn.wi == c.wi or not j.major.has(ap.conn.wi):
						continue
					var theirs_minor: bool = ap.conn.turn == Turn.LEFT or ap.conn.turn == Turn.UTURN
					if not theirs_minor and _soon(ap) and _conflicts(c, ap.conn):
						return false
	return true


## A car that will reach its stop line within a few seconds.
func _soon(ap: Dictionary) -> bool:
	return ap.car.commit or ap.ds / maxf(ap.car.v, 1.0) < 5.0


## Whether `a` stopped at its line before `b` (first come, first served).
static func _first(a: Dictionary, b: Dictionary) -> bool:
	if a.arrive < 0.0:
		return false
	if b.arrive < 0.0:
		return true
	return a.arrive < b.arrive or (a.arrive == b.arrive and a.id < b.id)


## Lane changes: needed ones to reach the next turn, and ones that pay off,
## like passing a slow car or leaving a long queue. Left on one tick, right
## on the next, so two cars never swap into the same gap.
func _lane_changes() -> void:
	var side := -1 if _tick % 2 == 0 else 1
	var claims := {}
	for key in _lanes:
		var list: Array = _lanes[key]
		for i in list.size():
			var car: Dictionary = list[i]
			if car.lc_t < 1.0 or car.lc_cool > 0.0 or car.commit:
				continue
			var w: Dictionary = ways[car.route[car.leg]]
			var t: int = car.lane + side
			if w.lanes < 2 or t < 0 or t >= w.lanes:
				continue
			var last: bool = car.leg == car.route.size() - 1
			var ds: float = (car.end_d if last else w.s1) - car.d
			# No lane change it can't finish before turning into its driveway.
			if ds < 8.0 + (DRIVEWAY_LEAD if last else 0.0):
				continue
			var desired := []
			if last:
				desired = [w.lanes - 1] if ds < 80.0 else range(w.lanes)
			else:
				desired = lanes_for(w.id, car.route[car.leg + 1])
			# Bus lanes: other traffic keeps out of them, except to turn
			# right at the next corner or reach a driveway close ahead.
			var bus := RoadStyle.bus_lane(w.type)
			if bus != -1 and not car.purpose in BUS_PURPOSES:
				var others: Array = desired.filter(func(l): return l != bus)
				if not others.is_empty():
					desired = others
				elif ds > BUS_LANE_ENTRY:
					desired = [bus - 1]
				if t == bus and not desired.has(bus):
					continue
			var must := false
			if not desired.has(car.lane):
				if _lane_dist(t, desired) >= _lane_dist(car.lane, desired):
					continue
				must = true
			elif not desired.has(t) or ds < 40.0:
				continue
			var blocked := false
			for cd in claims.get(w.id * 8 + t, []):
				if absf(cd - car.d) < car.len + CAR_LEN * 2.0:
					blocked = true
			if blocked:
				continue
			var other: Array = _lanes.get(w.id * 8 + t, [])
			var lead = null
			var foll = null
			for o in other:
				if o.d > car.d:
					lead = o
				else:
					foll = o
					break
			var gl: float = INF if lead == null else lead.d - car.d - lead.len
			var gf: float = INF if foll == null else car.d - foll.d - car.len
			if gl < 1.5 or gf < 1.5:
				continue
			_acc = car.acc
			var v0: float = minf(w.vmax * car.pref, car.top)
			var line := INF if last else ds - 0.5
			var a_new := _idm(car.v, v0, minf(gl, line), 0.0 if lead == null or gl > line else lead.v)
			var a_follow := 0.0
			if foll != null:
				a_follow = _idm(foll.v, minf(w.vmax * foll.pref, foll.top), gf, car.v, foll.acc)
			if must:
				if a_follow < -4.0 or a_new < -MAX_BRAKE * 0.6:
					continue
			else:
				var a_old := _idm(car.v, v0, minf(list[i - 1].d - car.d - list[i - 1].len, line) if i > 0 else line,
					list[i - 1].v if i > 0 and list[i - 1].d - car.d - list[i - 1].len < line else 0.0)
				# MOBIL: go if I gain more than I cost the car behind me.
				var gain := a_new - a_old - 0.3 * maxf(-a_follow, 0.0) + (0.1 if side > 0 else 0.0)
				if a_follow < -2.0 or gain < 0.5:
					continue
			car.lc_from = w.offs[car.lane]
			car.lane = t
			car.lc_t = 0.0
			car.lc_cool = 1.0 if must else 5.0
			if not claims.has(w.id * 8 + t):
				claims[w.id * 8 + t] = []
			claims[w.id * 8 + t].append(car.d)


static func _lane_dist(lane: int, desired: Array) -> int:
	var best := 99
	for l in desired:
		best = mini(best, absi(int(l) - lane))
	return best


## A few cars each tick look again at the rest of their trip with live
## travel times, and switch if another way is clearly faster.
func _replan_some() -> void:
	for car in cars:
		if (car.id * 7 + _tick) % 300 != 0 or car.j != null or car.commit:
			continue
		if car.leg >= car.route.size() - 1:
			continue
		var w: Dictionary = ways[car.route[car.leg]]
		if w.s1 - car.d < 30.0:
			continue
		var old_cost := _route_cost(car)
		var keep := {"route": car.route, "leg": car.leg, "end_d": car.end_d}
		if _replan(car) and _route_cost(car) > old_cost * 0.9:
			car.merge(keep, true)


## Expected seconds left on a car's planned route.
func _route_cost(car: Dictionary) -> float:
	var r: Array = car.route
	var w: Dictionary = ways[r[car.leg]]
	var cost: float = (w.len - car.d) / (w.vmax * maxf(_speed[w.id], 0.15))
	for k in range(car.leg + 1, r.size()):
		cost += _turn_cost(r[k - 1], r[k]) + _way_cost(r[k])
	return cost


# --- Geometry ---------------------------------------------------------------

func _way_dir(w: Dictionary, d: float) -> Vector3:
	var a := _poly_point(w.pts, w.cum, clampf(d - 0.5, 0.0, w.len))
	var b := _poly_point(w.pts, w.cum, clampf(d + 0.5, 0.0, w.len))
	return _flat_dir(b - a)


static func _poly_point(pts: PackedVector3Array, cum: PackedFloat32Array, d: float) -> Vector3:
	var i := cum.bsearch(d)
	if i <= 0:
		return pts[0]
	if i >= pts.size():
		return pts[pts.size() - 1]
	var f := (d - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.0001)
	return pts[i - 1].lerp(pts[i], f)


static func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length() < 0.0001:
		return Vector3.FORWARD
	return v.normalized()
