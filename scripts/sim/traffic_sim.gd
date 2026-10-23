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
## Where cars stop for a railroad crossing, metres before the track's centre:
## 15 ft from the nearest rail plus half the gauge.
const XING_STOP := 5.4
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
## Metres before a lot's entrance a car starts its turn into it.
const PARK_LEAD := 9.0
## At most this many drivers look for a better route each tick.
const REPLANS_PER_TICK := 2
## Seconds a driver would rather spend than turn left across traffic into
## or out of a driveway.
const CROSS_PEN := 6.0

## People out walking at once, at most; and walking speed (1.4 m/s, the
## MUTCD design walking speed is 3.5 ft/s for crossings, people stroll faster).
const MAX_WALKERS := 800
const WALK_V := 1.4
## Big towns (Brawn, 2026-10-23): past this many residents, people's own
## cars drive as traffic flows, not one by one: each trip is timed over its
## route with the FHWA's BPR curve, t = t0 (1 + 0.15 (v/c)^4), and loads
## the roads it uses, so jams still build where the player sends too many
## cars. Trucks, buses and service vehicles stay full agents.
const FLOW_FROM := 25000
## Road capacity per lane, vehicles an hour (the HCM's base saturation
## flow, 1,900 for a signalized lane).
const LANE_CAP := 1900.0
## Flow counts are taken over this many ticks (a minute of driving).
const FLOW_WINDOW := 600
## How close a trail must pass a home's sidewalk to be walked to from it.
const TRAIL_ACCESS := 40.0

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
var _waiting_ok := -1  # the road version every waiting route was checked on
## Vehicles at rest: parked in a stall, driveway or at the curb, at a dock, or
## out of sight inside a garage or factory bay. Each is a car with at_place,
## spot, pos, face, hidden, until (tick it heads off, or -1), owner, base.
var parked := []
## People on foot: {id, person, pts, cum, len, d, v, then}.
var walkers := []
## Goes up whenever a vehicle parks or leaves, so views know to redraw.
var parked_version := 0
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
var _tcost := {}  # way -> PackedFloat64Array, _turn_cost for each of _turns[way]
var _wend := {}   # way -> where it ends (x, z), for the route planner's estimate
var _vtop := 1.0  # the fastest limit on any way, m/s
var _wcost := {}  # way -> _way_cost now (_refresh_wcost)
var _cfor := {}   # Vector3i(way, lane, next) -> _conn_for's answer
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
var _xings := {}     # way -> [[s along the way, rail crossing]] (_find_xings)
var _by_vid := {}    # vehicle id -> its record in `parked`
var _due := {}       # tick -> parked vehicles due to head off then (_due_at)
var _pend := {}      # vehicle id -> parked vehicle waiting for a gap to pull out
var _slow := {}      # ways whose _speed is below 1 (or has cars), kept up to date each tick
var _slow_ok := -1   # the lane version _slow was gathered on
var _wstep := 0      # walker steps taken since load: a walker is _wstep - w.t0 steps along
var _wdone := {}     # walker step -> walkers who get where they're going then
## Cars driving as part of a traffic flow (see FLOW_FROM): parked nowhere,
## drawn by the view near the camera, arriving at `flow_end`.
var flowing := []
## Residents past which household trips become flows (a setting, for tests).
var flows_from := FLOW_FROM
var _flow_due := {}   # tick -> flowing cars arriving then
var _flow_in := {}    # tick -> [way ids a flowing car turns onto then]
var _fq := {}         # way -> cars that turned onto it this flow window
var _fshare := {}     # way -> BPR share of the limit from last window's flow
var _pseq := {}      # vehicle id -> its place in `parked` order (for _rest)
var _next_pseq := 0
var _xing_key := []
var _merging := {}   # lane key -> cars pulling out of a driveway into it
var _acc := ACCEL    # acceleration of the vehicle being worked out
var _sim: CitySim
var _places := {}     # place ref -> place (see place())
var _sites := {}      # place ref -> dispatch endpoint, for places off the lots
var _extra := {}      # place ref -> spots added beyond its layout, in order (_add_spot)
## Streets closed to cars (a pedestrian plaza): segment -> who may still
## drive in to deliver: "never", "night" (10 pm to 6 am) or "always".
var closed := {}
var _truck_plan := false  # the route being planned is for a truck (close_segment)
var _walk_lines := {} # segment * 2 + side -> sidewalk line
var _rings := {}      # node -> sidewalk ends around it (_corner_ring)
var _marks := []
var _xbusy := {}      # node -> [[from step, to step, segment, walker]] on its crosswalks
const _NO_XINGS := []      # crosswalks on the walk just planned: [point, node, way in]
var _next_trip := 1
var _next_walker := 1
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
	_sim = sim
	time += DT
	_find_xings()
	_rest()
	_step_flows()
	_spawn(sim, rng)
	_drive(rng)
	_step_walkers()


## Whether household trips drive as flows now (a big town).
func _flows_on() -> bool:
	return _sim != null and _sim.people.people.size() >= flows_from


## A household car joins the traffic flow: it leaves its spot, and its trip
## is timed way by way at today's speeds (BPR-slowed where flows are heavy),
## loading each road as it turns onto it.
func _flow_start(car: Dictionary) -> void:
	_release(car.at_place, car.spot, car.id)
	_unpark(car)
	for k in ["at_place", "spot", "pos", "face", "hidden", "pending"]:
		car.erase(k)
	var t := float(_tick)
	var ins := []
	var route: Array = car.route
	for i in route.size():
		var wid: int = route[i]
		if not ways.has(wid):
			continue
		var w: Dictionary = ways[wid]
		ins.append([int(t), wid])
		var metres: float = w.len
		if i == 0:
			metres = maxf(w.len - car.d, 0.0)
		if i == route.size() - 1:
			metres = minf(metres, car.end_d)
		var secs: float = metres / (minf(w.vmax * car.pref, car.top) * maxf(_speed.get(wid, 1.0), 0.15))
		if i > 0 and _tcost.has(route[i - 1]):
			var k: int = _turns[route[i - 1]].find(wid)
			if k >= 0:
				secs += minf(_tcost[route[i - 1]][k], 30.0)
		t += secs / DT
	car.flow_end = maxi(ceili(t), _tick + 1)
	var metres := 0.0
	for e in ins:
		metres += float(ways[int(e[1])].len)
	car.flow_v = snappedf(metres / maxf((car.flow_end - _tick) * DT, DT), 0.001)
	car.flow_in = ins
	flowing.append(car)
	_file_flow(car)


## Where a car in a traffic flow is by now, on its route's right lane:
## [position, direction]. `ahead` is metres on, for smooth drawing.
func flow_pose(car: Dictionary, ahead := 0.0) -> Array:
	var ins: Array = car.flow_in
	if ins.is_empty():
		return [Vector3.ZERO, Vector3.FORWARD]
	var i := 0
	while i + 1 < ins.size() and int(ins[i + 1][0]) <= _tick:
		i += 1
	var wid: int = ins[i][1]
	if not ways.has(wid):
		return [Vector3.ZERO, Vector3.FORWARD]
	var w: Dictionary = ways[wid]
	var t0: float = ins[i][0]
	var t1: float = ins[i + 1][0] if i + 1 < ins.size() else float(car.flow_end)
	var d0: float = car.d if i == 0 else 0.0
	var d1: float = car.end_d if i == ins.size() - 1 else w.len
	var f := clampf((_tick - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	var d := minf(lerpf(d0, d1, f) + ahead, w.len)
	return _way_pose(w, w.lanes - 1, d)


func _file_flow(car: Dictionary) -> void:
	var at: int = car.flow_end
	if not _flow_due.has(at):
		_flow_due[at] = []
	_flow_due[at].append(car)
	for e in car.flow_in:
		if int(e[0]) >= _tick:
			if not _flow_in.has(int(e[0])):
				_flow_in[int(e[0])] = []
			_flow_in[int(e[0])].append(int(e[1]))


## Flows on: cars turning onto roads are counted, each window's count sets
## the roads' BPR speeds, and cars whose trip is done park.
func _step_flows() -> void:
	for wid in _flow_in.get(_tick, []):
		_fq[wid] = int(_fq.get(wid, 0)) + 1
	_flow_in.erase(_tick)
	if _tick % FLOW_WINDOW == 0 and (not _fq.is_empty() or not _fshare.is_empty()):
		var next := {}
		for wid in _fq:
			if not ways.has(wid):
				continue
			var w: Dictionary = ways[wid]
			var vph: float = float(_fq[wid]) * 3600.0 / (FLOW_WINDOW * DT)
			var x: float = vph / (LANE_CAP * maxi(int(w.lanes), 1))
			var share := snappedf(1.0 / (1.0 + 0.15 * pow(x, 4.0)), 0.000001)
			if share < 0.9999:
				next[wid] = share
		_fshare = next
		_fq.clear()
	var due: Array = _flow_due.get(_tick, [])
	_flow_due.erase(_tick)
	for car in due:
		flowing.erase(car)
		car.erase("flow_end")
		car.erase("flow_in")
		car.erase("flow_v")
		if car.get("retire", false):
			_release(car.get("to_place", ""), car.get("to_spot", -1), car.id)
		elif place(car.get("to_place", "")).is_empty():
			# Where it was going was cleared away on the way: it goes home
			# instead (vehicles never vanish).
			var home := place(str(car.get("base", "")))
			var spot := -1 if home.is_empty() else _reserve(home, car.id, car.len > 6.5)
			if spot >= 0:
				car.to_place = home.ref
				car.to_ref = home.ref
				car.to_spot = spot
				var drv: int = car.get("after", {}).get("driver", -1)
				car.after = {"report": false} if drv == -1 else {"report": false, "driver": drv, "stay": -1}
		_arrive(car)


## Where the railroad crosses each way, refreshed when track or roads change.
func _find_xings() -> void:
	var rail: Rail = _sim.rail
	if rail.crossings.is_empty():
		_xings = {}
		return
	var key := [rail.version, version, rail.crossings.size()]
	if key == _xing_key:
		return
	_xing_key = key
	_xings = {}
	for c in rail.crossings:
		for wid in [int(c.seg) * 2, int(c.seg) * 2 + 1]:
			if not ways.has(wid):
				continue
			var w: Dictionary = ways[wid]
			var at := Vector2(c.pos.x, c.pos.z)
			var best := INF
			var bs := 0.0
			for k in w.pts.size() - 1:
				var a := Vector2(w.pts[k].x, w.pts[k].z)
				var b := Vector2(w.pts[k + 1].x, w.pts[k + 1].z)
				var q := Geometry2D.get_closest_point_to_segment(at, a, b)
				if q.distance_to(at) < best:
					best = q.distance_to(at)
					bs = float(w.cum[k]) + a.distance_to(q)
			if best < 10.0:
				if not _xings.has(wid):
					_xings[wid] = []
				_xings[wid].append([bs, c])


# --- Public helpers -----------------------------------------------------------

## Where a car's front bumper is and which way it faces: [position,
## direction]. `ahead` moves it on by that many metres, for smooth drawing
## between ticks.
func car_pose(car: Dictionary, ahead := 0.0) -> Array:
	if _dirty:
		_rebuild()  # a loaded city that hasn't run yet (a neighbor's, say)
	if car.has("flow_end"):
		return flow_pose(car, ahead)
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
	if c.has("rev"):
		return _poly_pose(c, jd)
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
## and cargo on its way is never lost or doubled. Stored as Godot's binary
## format in base64, since JSON (and even Godot's text format) round the
## numbers.
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
		"gave_up": gave_up, "speed": _speed, "dirty": _dirty, "arrivals": arrivals, "failed": failed,
		"parked": parked, "walkers": _walkers_saved(), "next_trip": _next_trip, "next_walker": _next_walker,
		"sites": _sites, "extra": _extra, "closed": closed, "flowing": flowing, "fq": _fq, "fshare": _fshare}
	# Binary, so every float comes back exactly and copies stay in step
	# (var_to_str rounds to 15 digits).
	return {"bin": Marshalls.variant_to_base64(state)}


func from_dict(d: Dictionary) -> void:
	cars.clear()
	_waiting.clear()
	parked.clear()
	_by_vid.clear()
	_due.clear()
	_pend.clear()
	_pseq.clear()
	walkers.clear()
	_wdone.clear()
	_sites.clear()
	_extra.clear()
	closed.clear()
	flowing.clear()
	_flow_due.clear()
	_flow_in.clear()
	_fq.clear()
	_fshare.clear()
	_places.clear()
	parked_version += 1
	_dirty = true
	if not d.has("state") and not d.has("bin"):
		return
	var state = _unpack(d)
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
	_slow_ok = -1
	arrivals = state.arrivals
	failed = state.failed
	parked = state.get("parked", [])
	_index_parked()
	walkers = state.get("walkers", [])
	_wstep = 0
	_wdone.clear()
	_xbusy.clear()
	for w in walkers:
		w.t0 = -int(w.get("t", 0))
		_file_walker(w)
		if w.has("xings"):
			_note_xings(w)
	_next_trip = state.get("next_trip", _next_id)
	_next_walker = state.get("next_walker", 1)
	_sites = state.get("sites", {})
	_extra = state.get("extra", {})
	closed = state.get("closed", {})
	flowing = state.get("flowing", [])
	_fq = state.get("fq", {})
	_fshare = state.get("fshare", {})
	for car in flowing:
		_file_flow(car)
	_places.clear()
	parked_version += 1
	# Junction paths are rebuilt from the roads; keep every car's plan as it
	# was unless the saved city still had road changes to take in.
	_restoring = true
	_keep_routes = not state.dirty


## A saved state: binary (now) or Godot's text format (older saves).
static func _unpack(d: Dictionary):
	if d.has("bin"):
		return Marshalls.base64_to_variant(str(d.bin))
	return str_to_var(str(d.get("state", "")))


## A junction or driveway path as plain data for saving.
static func _conn_key(c):
	if c == null or c is Array or c.has("drive") or c.has("poly"):
		return c  # still saved form (loaded, roads not rebuilt yet)
	if c.id >= 0:
		return [c.wi, c.li, c.wo, c.lo]
	if c.has("rev"):
		return {"poly": c.pts, "rev": c.rev, "wi": c.wi, "li": c.li, "wo": c.wo, "lo": c.lo,
			"exit_d": c.exit_d, "vt": c.vt}
	return {"drive": [c.pts[0], c.ctrl, c.pts[c.pts.size() - 1]], "wo": c.wo, "lo": c.lo,
		"exit_d": c.exit_d, "vt": c.vt}


func _from_key(k):
	if k == null:
		return null
	if k is Array:
		if not ways.has(k[0]) or not ways.has(k[2]):
			return null
		return _connector(k[0], k[1], k[2], k[3])
	if k.has("poly"):
		return _poly_path({"node": -1, "wi": k.wi, "li": k.li, "wo": k.wo, "lo": k.lo, "turn": Turn.RIGHT,
			"vt": k.vt, "exit_d": k.exit_d}, k.poly, k.rev)
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
	_places.clear()
	_walk_lines.clear()
	_rings.clear()
	junctions.clear()
	_in.clear()
	_out.clear()
	_turns.clear()
	_arrows.clear()
	_kind.clear()
	_conns.clear()
	_cfor.clear()
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
	_tcost.clear()
	for wi in _turns:
		var tc := PackedFloat64Array()
		for wo in _turns[wi]:
			tc.append(_turn_cost(wi, wo))
		_tcost[wi] = tc
	_refresh_wcost()
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
## Seconds to drive each way at its current speed (_way_cost, kept for
## every way so route planning doesn't call a function per road).
func _refresh_wcost() -> void:
	_wcost.clear()
	_wend.clear()
	_vtop = 1.0
	for wid in ways:
		var w: Dictionary = ways[wid]
		_wcost[wid] = w.len / (w.vmax * maxf(_speed.get(wid, 1.0), 0.15))
		var e: Vector3 = w.pts[w.pts.size() - 1]
		_wend[wid] = Vector2(e.x, e.z)
		_vtop = maxf(_vtop, w.vmax)


func _plan(starts: Array, targets: Dictionary, lane := -1, pen := {}) -> Array:
	if _wcost.size() != ways.size():
		_refresh_wcost()
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
	# A*: the estimate is the straight line from the end of a way to the
	# nearest target at the fastest limit in town, which no real route
	# beats, so the route found is still the fastest.
	var goals := PackedVector2Array()
	for t in targets:
		if ways.has(t):
			var p0: Vector3 = ways[t].pts[0]
			goals.append(Vector2(p0.x, p0.z))
	var inv_v := 1.0 / _vtop
	var hcache := {}
	# A binary heap of (cost + estimate, way) in two packed arrays, kept
	# inline: ties go to the lower way id, so every copy picks the same route.
	var hg := PackedFloat64Array()
	var hu := PackedInt32Array()
	for s in starts:
		var w: Dictionary = ways[s[0]]
		var g: float = maxf(w.len - s[1], 0.0) / w.vmax + (s[2] if s.size() > 2 else 0.0)
		if g < dist.get(s[0], INF):
			dist[s[0]] = g
			_hpush(hg, hu, g + _h_est(s[0], goals, inv_v, hcache), s[0])
	var end := -1
	var end_prev := -1
	var first := lane >= 0
	var none := PackedFloat64Array()
	while not hg.is_empty():
		var f: float = hg[0]
		var u: int = hu[0]
		_hpop(hg, hu)
		var g: float = dist[u]
		if f > g + hcache[u] + 0.0001:
			continue
		if f >= best:
			break
		var outs: Array = _turns.get(u, [])
		var tc: PackedFloat64Array = _tcost.get(u, none)
		for k in outs.size():
			var nx: int = outs[k]
			if first and not _arrows[u][nx].has(lane):
				continue
			if not closed.is_empty() and not may_enter(nx >> 1, _truck_plan):
				continue
			var e: float = g + tc[k]
			if targets.has(nx):
				var cand: float = e + targets[nx] / ways[nx].vmax + pen.get(nx, 0.0)
				if cand < best:
					best = cand
					end = nx
					end_prev = u
					best_route = []
			var ng: float = e + _wcost.get(nx, INF)
			if ng < dist.get(nx, INF):
				dist[nx] = ng
				prev[nx] = u
				_hpush(hg, hu, ng + _h_est(nx, goals, inv_v, hcache), nx)
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


## The planner's estimate of seconds left from the end of way `u`.
func _h_est(u: int, goals: PackedVector2Array, inv_v: float, hcache: Dictionary) -> float:
	if hcache.has(u):
		return hcache[u]
	var e: Vector2 = _wend.get(u, Vector2.ZERO)
	var best := INF
	for q in goals:
		best = minf(best, e.distance_to(q))
	var h := 0.0 if best == INF else best * inv_v
	hcache[u] = h
	return h


static func _hpush(hg: PackedFloat64Array, hu: PackedInt32Array, g: float, u: int) -> void:
	hg.append(g)
	hu.append(u)
	var i := hg.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hg[p] < g or (hg[p] == g and hu[p] <= u):
			break
		hg[i] = hg[p]
		hu[i] = hu[p]
		i = p
	hg[i] = g
	hu[i] = u


static func _hpop(hg: PackedFloat64Array, hu: PackedInt32Array) -> void:
	var n := hg.size() - 1
	var g: float = hg[n]
	var u: int = hu[n]
	hg.resize(n)
	hu.resize(n)
	if n == 0:
		return
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var m := l
		if l + 1 < n and (hg[l + 1] < hg[l] or (hg[l + 1] == hg[l] and hu[l + 1] < hu[l])):
			m = l + 1
		if g < hg[m] or (g == hg[m] and u <= hu[m]):
			break
		hg[i] = hg[m]
		hu[i] = hu[m]
		i = m
	hg[i] = g
	hu[i] = u


## Where on each way of a road piece a car would stop for a lot.
func _targets(goal: Dictionary) -> Dictionary:
	var out := {}
	for fwd in [true, false]:
		var wid: int = goal.seg * 2 + (1 if fwd else 0)
		if ways.has(wid):
			var len: float = ways[wid].len
			out[wid] = goal.frac * len if fwd else len - goal.frac * len
	return out


## How far along its road a lot or stop sits, to a micron: a saved city
## keeps fewer digits, and a loaded copy must drive exactly the same.
static func _frac(stop: Dictionary) -> float:
	return float(roundi(float(stop.at_frac) * 1.0e6)) / 1.0e6


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
		if ways.has(wid) and from.get("only_way", wid) == wid:
			var len: float = ways[wid].len
			starts.append([wid, _frac(from) * len if fwd else len - _frac(from) * len, out_pen[wid]])
	var goal := {"seg": to.seg, "frac": _frac(to), "side": to.get("side", 1)}
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
	_truck_plan = car.len > 6.5
	var route := _plan([[wid, car.d]], targets, lane, _side_pen(car.goal.seg, car.goal.get("side", 1)))
	_truck_plan = false
	if route.is_empty():
		return false
	car.route = route
	car.leg = 0
	car.end_d = targets[route[route.size() - 1]]
	_fix_end(car, false)
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
		into.append({"id": car.get("trip", car.id), "vid": car.id, "purpose": car.purpose, "cargo": car.cargo,
			"from": str(car.from_ref).get_slice("@", 0), "to": str(car.to_ref).get_slice("@", 0)})


## After the roads change, every car finds its way again (or gives up).
func _reroute_all() -> void:
	# Spots added out front were for the old roads: curb cars find new ones.
	_extra.clear()
	_places.clear()
	var kept := []
	for car in cars:
		var wid: int = car.route[car.leg]
		if car.j != null and car.j.wo < 0:
			if car.has("to_place"):
				_arrive(car)
			else:
				_report(car, arrivals)
			continue  # was parking: it has arrived
		var out_ok: bool = car.j != null and car.j.node == -1 and ways.has(car.j.wo) \
			and car.j.exit_d <= ways[car.j.wo].len \
			and _lane_point(ways[car.j.wo], mini(car.j.lo, ways[car.j.wo].lanes - 1), car.j.exit_d).distance_to(
				car.j.pts[car.j.pts.size() - 1]) < 1.0
		if out_ok:
			# Still pulling out onto a road that's still there: finish doing so.
			wid = car.j.wo
			car.route = [wid]
			car.leg = 0
			car.d = car.j.exit_d
		elif car.j != null or not ways.has(wid):
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
	# Vehicles on a lot that was cleared away go with it.
	for car in parked.duplicate():
		if place(car.at_place).is_empty():
			_unpark(car)
			_report(car, failed)
	# Cars parked at a curb that was rebuilt move to the new curb.
	for car in parked:
		var pl := place(car.at_place)
		var ok: bool = car.spot >= 0 and car.spot < pl.spots.size()
		if ok:
			var s: Dictionary = pl.spots[car.spot]
			ok = (s.pos + s.face * car.len * 0.5).distance_to(car.pos) < 0.5
		if ok:
			continue
		var curb := _curb_spots(pl.stop, 3)
		for c in curb:
			_add_spot(pl, c)
		var at := _reserve(pl, car.id, car.len > 6.5)
		if at >= 0:
			var s: Dictionary = pl.spots[at]
			car.spot = at
			car.pos = s.pos + s.face * car.len * 0.5
			car.face = s.face
			car.hidden = s.hidden
			parked_version += 1
	# Vehicles about to pull out plan again on the new roads.
	for car in parked:
		if car.get("pending", false) and not _replan_start(car, place(car.at_place).get("stop", {})):
			_cancel(car)
	for car in _waiting.duplicate():
		if not _replan_start(car, car.get("start_stop", {})):
			_waiting.erase(car)
			_report(car, failed)


## Plans a not-yet-started trip again from its start; false if it can't go.
func _replan_start(car: Dictionary, from_stop: Dictionary) -> bool:
	if from_stop.is_empty() or car.get("to_stop", {}).is_empty() or not car.has("to_place"):
		return car.has("route") and ways.has(car.route[0])
	if car.to_place != "edge":
		var pl := place(car.to_place)
		if pl.is_empty():
			return false
		car.to_stop = pl.stop
	_truck_plan = car.len > 6.5
	var trip := _route(from_stop, car.to_stop)
	_truck_plan = false
	if trip.is_empty():
		return false
	car.merge(trip, true)
	_fix_end(car)
	return true


## A parked vehicle that can't make its trip after all stays where it is.
func _cancel(car: Dictionary) -> void:
	_release(car.get("to_place", ""), car.get("to_spot", -1), car.id)
	_report(car, failed)
	car.erase("pending")
	_pend.erase(car.id)
	for k in ["route", "leg", "d", "end_d", "goal", "dest", "park", "home", "to_place", "to_spot", "lane",
			"to_stop", "after"]:
		car.erase(k)
	var pid: int = car.get("driver", -1)
	car.driver = -1
	if pid != -1 and _sim != null and _sim.people.people.has(pid):
		var p: Dictionary = _sim.people.people[pid]
		p.at = "" if car.at_place == "lot:" + p.home else car.at_place
		_sim.people.set_until(p, -1 if p.at == "" else _tick + 30)


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
	var homes: Array = sim.zone_keys(ZoneMap.Zone.RESIDENTIAL)
	var shops: Array = sim.zone_keys(ZoneMap.Zone.COMMERCIAL)
	var plants: Array = sim.zone_keys(ZoneMap.Zone.INDUSTRIAL)
	if background_freight and hour >= 6 and hour < 20 and not shops.is_empty() and not plants.is_empty() \
			and rng.randf() < 0.12:
		add_trip(sim.lots[plants[rng.randi() % plants.size()]], sim.lots[shops[rng.randi() % shops.size()]],
			rng, "", "goods")
		return
	if not sim.people.people.is_empty():
		return  # real people make the trips (People.plan)
	var dests := shops + plants
	if homes.is_empty() or dests.is_empty():
		return
	var home_key: String = homes[rng.randi() % homes.size()]
	var a: Dictionary = sim.lots[home_key]
	var dest_key: String = dests[rng.randi() % dests.size()]
	var b: Dictionary = sim.lots[dest_key]
	# Short trips near the trails and bike lanes often go on foot instead.
	if sim.parks.trails.on_foot(sim, home_key, dest_key, rng):
		return
	var purpose := "shopping" if sim.buildings[dest_key].zone == ZoneMap.Zone.COMMERCIAL else "commute"
	if hour >= 15:
		var t := a
		a = b
		b = t
	add_trip(a, b, rng, "", purpose)


## Sends a vehicle from one lot to another and back: it pulls out of a spot
## on the first lot, parks on the other a while, then drives home and parks
## again. Returns false if there's no route.
func add_trip(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator, kind := "",
		purpose := "", cargo := {}) -> bool:
	if cars.size() >= MAX_CARS:
		return false
	if purpose == "":
		purpose = "commute"
	var any_kind := kind == ""
	if any_kind:
		kind = VehicleTypes.for_purpose(purpose, rng, cargo)
	var ra := _ref_of(a)
	var rb := _ref_of(b)
	if ra == "" or rb == "" or place(rb).is_empty():
		return false
	var after := {"stay": 20 + rng.randi() % 60, "back": ra}
	var vid := new_vehicle(kind, ra, -1)
	if vid != -1:
		if _send(_vehicle_parked(vid), rb, purpose, cargo, after):
			return true
		retire_vehicle(vid)
		return false
	# No room on the lot it leaves from: it pulls away from the curb.
	var car := _make_vehicle(kind, -1, ra)
	car.from_stop = a
	return _send(car, rb, purpose, cargo, after)


func _ref_of(lot: Dictionary) -> String:
	if lot.has("ref") and str(lot.ref) != "":
		return str(lot.ref)
	if lot.has("key"):
		return "lot:" + str(lot.key)
	return ""


func _make_vehicle(kind: String, owner: int, base: String) -> Dictionary:
	var id := _next_id
	_next_id += 1
	var spec := VehicleTypes.spec(kind)
	return {"id": id, "kind": kind, "len": float(spec.len), "acc": float(spec.acc),
		"top": float(spec.top_speed), "pref": float(roundi(float(spec.pref) * (90 + hash([id, kind]) % 21))) / 100.0,  # exact in saves
		"color": hash(id) % 8, "owner": owner, "base": base, "driver": -1, "trip": -1, "purpose": "",
		"cargo": {}, "from_ref": "", "to_ref": "", "until": -1}


## Sends a vehicle with a job: goods, a delivery, a service call. `from` and
## `to` are {"ref": any id the caller wants back, "pos": [x, z]}, plus
## "drive": [[x, z], ...] for a place reached up its own lane (building end
## first). The vehicle leaves from `from` (a truck from its depot, or off
## the map edge), unloads at `to`, shows up in `arrivals` (or `failed`), and
## then drives back and parks where it came from. Returns the trip id, or -1
## if no road leads there. `kind` picks the vehicle (blank: one fitting the
## purpose).
func dispatch(from: Dictionary, to: Dictionary, purpose: String, cargo := {}, kind := "") -> int:
	if _dirty:
		_rebuild()
	var rf := _register(from)
	var rt := _register(to)
	if rf == "" or rt == "":
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_next_trip, purpose, "dispatch"])
	var any_kind := kind == ""
	if any_kind:
		kind = VehicleTypes.for_purpose(purpose, rng, cargo)
	var id := _next_trip
	var edge_to := {} if rt != "edge" else _endpoint(to)
	# Trucks head home soon after unloading; a car waits most of a day for
	# its trip back (school, work), and anything is picked up sooner if the
	# next job starts where it is.
	var stay := 15 + rng.randi() % 20 if VehicleTypes.spec(kind).len > 6.5 else 600
	if rf == "edge":
		# Imports come in off the map and head back out after unloading.
		var stop := _endpoint(from)
		if stop.is_empty():
			return -1
		var car := _make_vehicle(kind, -1, "edge")
		car.from_stop = stop
		return id if _send(car, rt, purpose, cargo, {"stay": stay, "back": "edge", "back_stop": stop},
			edge_to) else -1
	# A vehicle already parked here that nobody owns (a depot's truck, or one
	# that just finished the last leg of its round) takes the job.
	var car := {}
	for p in parked:
		if p.at_place == rf and p.owner == -1 and not p.get("pending", false) and p.get("driver", -1) == -1 \
				and (p.kind == kind or any_kind and p.get("job", "") == purpose):
			car = p
			break
	if car.is_empty():
		# A new one, based where vehicles are kept: a lot or yard with room
		# for them, else wherever this trip ends.
		var base := rf
		var pl := place(rf)
		if pl.lot.is_empty() and pl.drive.is_empty() and rt != "edge":
			base = rt
		var vid := new_vehicle(kind, rf, -1, base)
		if vid != -1:
			car = _vehicle_parked(vid)
		else:
			car = _make_vehicle(kind, -1, base)
			car.from_stop = pl.stop
	car.job = purpose
	# After unloading it heads back to its base, unless that's where it is.
	var after := {"stay": stay, "back": car.base}
	if car.base == rt or rt == "edge":
		after = {}
	return id if _send(car, rt, purpose, cargo, after, edge_to) else -1


## Every trip that's under way: driving, waiting to pull out, or just
## arrived or given up (handled by its caller next tick).
func trip_ids() -> Array:
	var out := []
	for c in cars + _waiting:
		out.append(c.get("trip", c.id))
	for p in parked:
		if p.get("pending", false):
			out.append(p.trip)
	for r in arrivals + failed:
		out.append(r.id)
	return out


## Sends a vehicle that's parked somewhere on one more leg, with no trip
## back: a bus going stop to stop, a truck on a round of calls. `to` is a
## dispatch endpoint. Returns the trip id (it shows up in `arrivals` with
## this vehicle's "vid"), or -1 if the vehicle isn't parked or can't get there.
func move(vid: int, to: Dictionary, purpose: String, cargo := {}) -> int:
	if _dirty:
		_rebuild()
	var car := _vehicle_parked(vid)
	if car.is_empty() or car.get("pending", false):
		return -1
	var rt := _register(to)
	if rt == "":
		return -1
	var id := _next_trip
	return id if _send(car, rt, purpose, cargo, {}, {} if rt != "edge" else _endpoint(to)) else -1


## Remembers a dispatch endpoint as a place; returns its ref ("" if no road).
## Closes a road piece to cars without removing it, as for a pedestrian
## plaza (or opens it again). The lots along it keep their frontage; cars
## route around it and park nearby, and trucks may still drive in to
## deliver: `deliveries` is "never", "night" (10 pm to 6 am) or "always".
func close_segment(seg: int, on: bool, deliveries := "night") -> void:
	if on:
		closed[seg] = deliveries
	else:
		closed.erase(seg)
	_dirty = true  # every car on the road finds its way again


## Whether a vehicle may drive on a road piece now (see close_segment).
func may_enter(seg: int, truck: bool) -> bool:
	if not closed.has(seg):
		return true
	if not truck:
		return false
	match str(closed[seg]):
		"always":
			return true
		"night":
			var hour: int = _sim.clock().hour if _sim != null else 12
			return hour >= 22 or hour < 6
	return false


## Makes a dispatch endpoint {"ref", "pos"} a place vehicles can be based
## at and driven to (a bus stop, a yard). Returns its place ref, or "" if
## no road is near.
func register(e: Dictionary) -> String:
	if _dirty:
		_rebuild()
	return _register(e)


func _register(e: Dictionary) -> String:
	var ref := str(e.get("ref", ""))
	if ref == "edge":
		return ref if not _endpoint(e).is_empty() else ""
	if ref.begins_with("home:"):
		ref = "lot:" + ref.substr(5)  # a home is its lot
	if ref.begins_with("lot:") and not place(ref).is_empty():
		return ref
	# One caller ref can name many spots (a bus going stop to stop), so a
	# site is also keyed by where it is; reports drop the "@x,z" again.
	ref = "%s@%d,%d" % [ref if ref != "" else "at", roundi(float(e.pos[0])), roundi(float(e.pos[1]))]
	if _sites.has(ref) and _places.has(ref):
		return ref
	var site := e.duplicate()
	site.ref = ref
	_sites[ref] = site
	_places.erase(ref)
	return ref if not place(ref).is_empty() else ""


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
## `lanes` (from _lane_add) lists where the moving cars are by lane, so a
## tick with many vehicles waiting doesn't look through every car for each.
func _launch(car: Dictionary, lanes := {}) -> bool:
	var w: Dictionary = ways[car.route[0]]
	var last: bool = car.route.size() == 1
	var limit: float = car.end_d - 4.0 if last else w.s1 - 0.5
	var exit_d := minf(car.d + DRIVEWAY_LEAD + 2.0, limit)
	var out := {}
	var from_pl: Dictionary = _places.get(car.get("from_place", ""), {})
	if not from_pl.is_empty() and car.get("from_spot", -1) >= 0 and car.from_spot < from_pl.spots.size():
		out = _out_path(car, from_pl, car.from_spot, w, car.lane, car.d)
		exit_d = out.exit_d
	elif exit_d <= car.d + 1.0 and last:
		return false  # next door: walk
	# Pull out only when there's a gap in the traffic.
	if lanes.is_empty():
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
	else:
		for od in lanes.get(Vector2i(car.route[0], car.lane), []):
			if od > car.d - 30.0 and od < exit_d + 12.0:
				return false
	if not out.is_empty():
		car.j = out
		car.jd = 0.0
		car.d = exit_d
		car.from_spot = -1
	elif car.get("home") != null:
		car.j = _driveway_out(car, exit_d)
	else:
		car.d = exit_d
	cars.append(car)
	return true


## Files a moving car under the lane it's in (or turning into), at the
## distance along it _launch compares.
func _lane_add(lanes: Dictionary, other: Dictionary) -> void:
	var at := Vector2i(other.route[other.leg], other.lane) if other.j == null else Vector2i(other.j.wo, other.j.lo)
	var od: float = other.d if other.j == null else other.j.exit_d
	if not lanes.has(at):
		lanes[at] = []
	lanes[at].append(od)


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


# --- Places, parking and people on foot --------------------------------------
#
# No vehicle simply disappears (Brawn's rule, and what CS2 does): every trip
# ends parked in a stall or driveway, at a loading dock, or inside a building
# (a garage or a factory bay), and later the vehicle drives back out. Only
# trips off the edge of the map end out of sight. People get out and walk
# to the door, and walk back to their car when it is time to go.

## The place a ref stands for: a lot ("lot:12:1:3"), a site reached by its
## own lane (registered by dispatch), or the map edge. {} if it's gone.
## {ref, stop (lot-like stop on the road, for routing), spots: [{pos, face,
## kind, hidden, local}], taken: [vehicle id or -1], door, lot, lay, drive}
func place(ref: String) -> Dictionary:
	if _places.has(ref):
		var pl: Dictionary = _places[ref]
		if not pl.has("seed") or _place_seed(ref) == pl.seed:
			return pl
		_places.erase(ref)  # rebuilt with a different building
	var pl := {}
	if ref.begins_with("lot:"):
		pl = _lot_place(ref)
	elif _sites.has(ref):
		pl = _site_place(_sites[ref])
	if pl.is_empty():
		return {}
	for e in _extra.get(ref, []):
		pl.spots.append(e)
		pl.taken.append(-1)
	_places[ref] = pl
	_claim_spots(pl)
	return pl


func _place_seed(ref: String) -> int:
	if _sim == null or not ref.begins_with("lot:"):
		return 0
	var b = _sim.buildings.get(ref.substr(4))
	return 0 if b == null else int(b.seed) + 7 * int(b.zone)


func _lot_place(ref: String) -> Dictionary:
	if _sim == null or not _sim.lots.has(ref.substr(4)):
		return {}
	var lot: Dictionary = _sim.lots[ref.substr(4)]
	var b = _sim.buildings.get(ref.substr(4))
	var lay := SiteLayout.empty_lot() if b == null else SiteLayout.for_building(int(b.zone), int(b.seed), lot)
	var spots := []
	for s in lay.spots:
		spots.append({"pos": SiteLayout.world(lot, s.pos), "face": SiteLayout.world_dir(lot, s.face),
			"kind": s.kind, "hidden": s.kind == "garage" or s.kind == "bay", "local": s.pos})
	var stop := lot.duplicate()
	stop.ref = ref
	return {"ref": ref, "stop": stop, "lot": lot, "lay": lay, "spots": spots, "taken": _fill(spots.size()),
		"door": SiteLayout.world(lot, lay.door), "seed": _place_seed(ref), "drive": PackedVector3Array(),
		"zone": -1 if b == null else int(b.zone)}


## A place reached from the road by its own lane, like a farmyard or a mine:
## trucks drive up the lane to the dock at its end.
func _site_place(e: Dictionary) -> Dictionary:
	var ref: String = str(e.get("ref", ""))
	var drive := PackedVector3Array()
	for p in e.get("drive", []):
		drive.append(Vector3(float(p[0]), 0.0, float(p[1])))
	var road_end := Vector3(float(e.pos[0]), 0.0, float(e.pos[1]))
	if drive.size() >= 2:
		road_end = drive[drive.size() - 1]
	var stop := _endpoint({"ref": ref, "pos": [road_end.x, road_end.z]})
	if stop.is_empty():
		return {}
	var spots := []
	var door := road_end
	if drive.size() >= 2:
		var t := _flat_dir(drive[0] - drive[1])
		var side := Vector3(-t.z, 0.0, t.x)
		door = drive[0] + t * 2.0
		# Inside the building (where its own trucks are kept), then two docks
		# in front of it, side by side.
		spots.append({"pos": drive[0] + t * 9.0, "face": t, "kind": "bay", "hidden": true, "local": Vector2.ZERO})
		spots.append({"pos": drive[0] - t * 4.0, "face": t, "kind": "dock", "hidden": false, "local": Vector2.ZERO})
		spots.append({"pos": drive[0] - t * 5.0 + side * 4.5, "face": t, "kind": "dock", "hidden": false,
			"local": Vector2.ZERO})
	else:
		spots = _curb_spots(stop, 1)
	return {"ref": ref, "stop": stop, "lot": {}, "lay": {}, "spots": spots, "taken": _fill(spots.size()),
		"door": door, "drive": drive, "zone": -1}


## A car at the curb pulls away the way it faces.
func _curb_start(s: Dictionary, stop: Dictionary) -> Dictionary:
	var a := stop.duplicate()
	for fwd in [true, false]:
		var wid: int = stop.seg * 2 + (1 if fwd else 0)
		if not ways.has(wid):
			continue
		var w: Dictionary = ways[wid]
		var d := _nearest_d(w, s.pos)
		if _way_dir(w, d).dot(s.face) > 0.0:
			a.only_way = wid
			a.at_frac = (d if fwd else w.len - d) / maxf(w.len, 0.001)
	return a


## A driveway near a corner: the car leaves by the side of the street where
## it has room before the junction, backing out (a home's driveway) or
## pulling forward (a lot or yard), and doesn't back or drive into the junction.
func _out_way(pl: Dictionary, spot: int, stop: Dictionary) -> Dictionary:
	var backs: bool = pl.spots[spot].kind in ["drive", "garage"]
	var e := _entrance(pl, spot)
	var ok := []
	for fwd in [true, false]:
		var wid: int = stop.seg * 2 + (1 if fwd else 0)
		if not ways.has(wid):
			continue
		var w: Dictionary = ways[wid]
		var de := _nearest_d(w, e)
		if (de - 8.0 >= w.s0 + 0.5) if backs else (de + DRIVEWAY_LEAD + 2.0 <= w.s1 - 0.5):
			ok.append(wid)
	if ok.size() != 1:
		return stop
	var a := stop.duplicate()
	a.only_way = ok[0]
	return a


## Places at the side of the road in front of a stop, as on a main street.
func _curb_spots(stop: Dictionary, n: int) -> Array:
	var out := []
	var wid: int = stop.seg * 2 + 1
	if not ways.has(wid):
		wid = stop.seg * 2
	if not ways.has(wid):
		return out
	var w: Dictionary = ways[wid]
	if w.s1 - w.s0 < 24.0:
		return out  # too short a piece of road to park along
	var mid: float = _frac(stop) * w.len if w.fwd else w.len - _frac(stop) * w.len
	var face := 1.0 if (stop.side > 0) == w.fwd else -1.0
	var edge := RoadStyle.half_width(w.type) - 1.1
	for k in n:
		# Clear of the junctions at both ends, with room to pull away.
		var d := clampf(mid + (k - (n - 1) * 0.5) * 7.0, w.s0 + 12.0, w.s1 - 12.0)
		var dir := _way_dir(w, d) * face
		var right := Vector3(-dir.z, 0.0, dir.x)
		var p := _poly_point(w.pts, w.cum, d) + right * edge
		out.append({"pos": p, "face": dir, "kind": "curb", "hidden": false, "local": Vector2.ZERO})
	return out


static func _fill(n: int) -> Array:
	var a := []
	a.resize(n)
	a.fill(-1)
	return a


## Marks the spots of a freshly built place that vehicles already hold.
## Adds a spot to a place beyond its own layout (a curb space out front, or
## the very spot a car turned into before its lot was rebuilt). Remembered
## and saved, so a loaded copy has the same spots in the same order.
func _add_spot(pl: Dictionary, s: Dictionary, vid := -1) -> int:
	pl.spots.append(s)
	pl.taken.append(vid)
	if not _extra.has(pl.ref):
		_extra[pl.ref] = []
	_extra[pl.ref].append(s)
	return pl.spots.size() - 1


func _claim_spots(pl: Dictionary) -> void:
	for car in parked:
		if car.at_place == pl.ref and car.spot >= 0 and car.spot < pl.taken.size():
			pl.taken[car.spot] = car.id
	for car in cars + _waiting:
		if car.get("to_place", "") == pl.ref and car.get("to_spot", -1) >= 0 and car.to_spot < pl.taken.size():
			pl.taken[car.to_spot] = car.id


## A free spot for a vehicle: trucks take docks and bays first, cars their
## garage or driveway, then a stall. -1 if the place is full.
func _reserve(pl: Dictionary, vid: int, truck: bool) -> int:
	var order := ["dock", "bay", "stall", "drive", "curb"] if truck else ["garage", "drive", "stall", "curb"]
	for kind in order:
		for i in pl.spots.size():
			if pl.taken[i] == -1 and pl.spots[i].kind == kind:
				pl.taken[i] = vid
				return i
	return -1


func _release(ref: String, i: int, vid: int) -> void:
	if not _places.has(ref):
		return
	var pl: Dictionary = _places[ref]
	if i >= 0 and i < pl.taken.size() and pl.taken[i] == vid:
		pl.taken[i] = -1


## Where a car parks when its own destination is full: the nearest lot with
## a free stall within a short walk, like CS2 drivers looking for parking.
func _parking_near(pl: Dictionary, vid: int) -> Array:
	if _sim == null:
		return []
	var best := []
	var best_d := 250.0
	var keys := _sim.buildings.keys()
	keys.sort()
	for key in keys:
		if _sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL or not _sim.lots.has(key):
			continue
		var d: float = _sim.lots[key].front.distance_to(pl.door)
		if d >= best_d:
			continue
		var other := place("lot:" + key)
		if other.is_empty() or other.ref == pl.ref or closed.has(int(other.stop.get("seg", -1))):
			continue
		for i in other.spots.size():
			if other.taken[i] == -1 and other.spots[i].kind == "stall":
				best = [other.ref, i]
				best_d = d
				break
	if not best.is_empty():
		_places[best[0]].taken[best[1]] = vid
	return best


## A new vehicle at rest in a place (a household car in its driveway, a
## truck in its depot). Returns its id, or -1 if there's no room there.
func new_vehicle(kind: String, at_ref: String, owner: int, owner_place := "") -> int:
	var pl := place(at_ref)
	if pl.is_empty():
		return -1
	var spot := _reserve(pl, _next_id, VehicleTypes.spec(kind).len > 6.5)
	if spot < 0:
		return -1
	var car := _make_vehicle(kind, owner, owner_place if owner_place != "" else at_ref)
	_park(car, pl, spot)
	return car.id


## Takes a vehicle out of the town for good: it was sold, or its owner left.
func retire_vehicle(vid: int) -> void:
	for car in parked:
		if car.id == vid:
			_release(car.at_place, car.spot, vid)
			_unpark(car)
			return
	for car in cars + _waiting + flowing:
		if car.id == vid:
			car.owner = -1
			car.retire = true  # gone once it gets where it's going
			return


## Someone left town: they stop walking and nobody waits for them.
func forget_person(pid: int) -> void:
	for w in walkers.duplicate():
		if w.person == pid:
			w.gone = true
			walkers.erase(w)
	for car in parked:
		if car.get("driver", -1) == pid:
			car.driver = -1


func _vehicle_parked(vid: int) -> Dictionary:
	return _by_vid.get(vid, {})


## A parked vehicle is due to head off at `tick`.
func _due_at(car: Dictionary, tick: int) -> void:
	car.until = tick
	if not _due.has(tick):
		_due[tick] = []
	_due[tick].append(car)


## Rebuilds the due list from the parked vehicles (after a load).
func _index_parked() -> void:
	_by_vid.clear()
	_due.clear()
	_pend.clear()
	_pseq.clear()
	_next_pseq = 0
	for car in parked:
		_by_vid[car.id] = car
		_pseq[car.id] = _next_pseq
		_next_pseq += 1
		if car.has("pending"):
			_pend[car.id] = car
		if car.until >= 0:
			_due_at(car, car.until)


func _unpark(car: Dictionary) -> void:
	parked.erase(car)
	_by_vid.erase(car.id)
	_pend.erase(car.id)
	_pseq.erase(car.id)
	parked_version += 1


## Puts a vehicle at rest in a spot.
func _park(car: Dictionary, pl: Dictionary, spot: int) -> void:
	var s: Dictionary = pl.spots[spot]
	car.at_place = pl.ref
	car.spot = spot
	car.pos = s.pos + s.face * car.len * 0.5  # front bumper, as when driving
	car.face = s.face
	car.hidden = s.hidden
	car.v = 0.0
	car.a = 0.0
	car.j = null
	car.conn = null
	car.pj = null
	for k in ["route", "leg", "d", "end_d", "goal", "dest", "park", "home", "to_place", "to_spot", "lane",
			"commit", "arrive", "stuck", "lc_from", "lc_t", "lc_cool", "held", "jd", "at", "facing", "pulled_over"]:
		car.erase(k)
	if not car.has("until"):
		car.until = -1
	parked.append(car)
	_by_vid[car.id] = car
	_pseq[car.id] = _next_pseq
	_next_pseq += 1
	parked_version += 1


## Sends a resting vehicle to another place, to park there and then do
## `after` ({"stay": ticks, "back": ref to return to, "driver": person}).
## Returns false if there's no road there.
func _send(car: Dictionary, to_ref: String, purpose: String, cargo: Dictionary, after: Dictionary,
		edge_stop := {}) -> bool:
	var to_pl := place(to_ref) if to_ref != "edge" else {"ref": "edge", "edge": true, "stop": edge_stop}
	if to_ref == "edge" and edge_stop.is_empty():
		return false
	var from_pl := place(car.at_place) if car.has("at_place") else {}
	if to_pl.is_empty():
		return false
	var a: Dictionary = from_pl.stop if not from_pl.is_empty() else car.get("from_stop", {})
	if a.is_empty():
		return false
	if not from_pl.is_empty() and car.spot < from_pl.spots.size():
		if from_pl.spots[car.spot].kind == "curb":
			a = _curb_start(from_pl.spots[car.spot], a)
		else:
			a = _out_way(from_pl, car.spot, a)
	# A place on a street closed to cars (a plaza): drivers park nearby and
	# walk; trucks drive in only when deliveries are allowed.
	var truck: bool = car.len > 6.5
	var shut: bool = not to_pl.get("edge", false) and to_pl.stop.has("seg") \
		and not may_enter(int(to_pl.stop.seg), truck)
	if shut and after.get("driver", -1) == -1:
		return false
	_truck_plan = truck
	var trip := {} if shut else _route(a, to_pl.stop)
	_truck_plan = false
	if trip.is_empty() and not shut:
		return false
	var spot := -1
	var park_ref: String = to_pl.ref
	if not to_pl.get("edge", false):
		spot = -1 if shut else _reserve(to_pl, car.id, truck)
		if spot < 0 and after.get("driver", -1) != -1:
			var alt := _parking_near(to_pl, car.id)
			if not alt.is_empty():
				_truck_plan = truck
				var alt_trip := _route(a, place(alt[0]).stop)
				_truck_plan = false
				if not alt_trip.is_empty():
					park_ref = alt[0]
					spot = alt[1]
					trip = alt_trip
				else:
					_release(alt[0], alt[1], car.id)
		if shut and trip.is_empty():
			return false
		if spot < 0:
			# Nowhere to park: double-park at the curb out front, as delivery
			# trucks do, or (for a car) take a curb space anyway.
			var curb := _curb_spots(to_pl.stop, 1)
			if curb.is_empty():
				return false
			spot = _add_spot(to_pl, curb[0], car.id)
	car.merge(trip, true)
	car.to_stop = to_pl.stop
	if not car.has("at_place"):
		car.start_stop = a
	car.merge({"trip": _next_trip, "purpose": purpose, "cargo": cargo,
		"from_ref": car.get("at_place", ""), "to_ref": to_ref, "to_place": park_ref, "to_spot": spot,
		"after": after, "pj": null, "j": null, "jd": 0.0, "commit": false, "conn": null, "arrive": -1.0,
		"stuck": 0.0, "lc_from": 0.0, "lc_t": 1.0, "lc_cool": 2.0, "a": 0.0, "held": false,
		"from_place": car.get("at_place", ""), "from_spot": car.get("spot", -1), "until": -1}, true)
	_next_trip += 1
	if car.has("at_place") and after.get("driver", -1) != -1 and _flows_on():
		_flow_start(car)
		return true
	_fix_end(car)
	if car.has("at_place"):
		car.pending = true  # pulls out as soon as there's a gap
		_pend[car.id] = car
		_try_launch(car)
	elif not _launch(car):
		_waiting.append(car)
	return true


## A parked vehicle with a trip pulls out if there's a gap in traffic.
func _try_launch(car: Dictionary) -> bool:
	if cars.size() >= MAX_CARS or not _launch(car):
		return false
	_release(car.at_place, car.spot, car.id)
	_unpark(car)
	for k in ["at_place", "spot", "pos", "face", "hidden", "pending"]:
		car.erase(k)
	return true


## The place a car is heading for, making sure it still holds a spot there
## (places are rebuilt when roads or buildings change). {} if it's gone.
func _dest(car: Dictionary) -> Dictionary:
	if car.get("to_place", "") == "" or car.to_place == "edge":
		return {}
	var pl := place(car.to_place)
	if pl.is_empty():
		return {}
	var i: int = car.get("to_spot", -1)
	if i < 0 or i >= pl.spots.size() or (pl.taken[i] != car.id and pl.taken[i] != -1):
		i = _reserve(pl, car.id, car.len > 6.5)
		if i < 0:
			var curb := _curb_spots(pl.stop, 1)
			if curb.is_empty():
				return {}
			i = _add_spot(pl, curb[0], car.id)
		car.to_spot = i
	pl.taken[i] = car.id
	return pl


## Points a car's trip end at the entrance it will turn in at.
## If the place has moved off this road (its lots were redrawn), the car
## heads for where it is now.
func _fix_end(car: Dictionary, may_replan := true) -> void:
	if car.get("pulled_over", false):
		return
	var pl := _dest(car)
	if pl.is_empty():
		return
	var w: Dictionary = ways[car.route[car.route.size() - 1]]
	var e := _entrance(pl, car.to_spot)
	var d := _nearest_d(w, e)
	if d < w.s0 and car.route.size() >= 2 and car.leg < car.route.size() - 1:
		# The driveway opens off the junction just before this road (a lot on
		# a roundabout, say): turn in from the road before it instead.
		var pw: Dictionary = ways[car.route[car.route.size() - 2]]
		var dp := _nearest_d(pw, e)
		if dp > pw.s1 - PARK_LEAD and _lane_point(pw, 0, dp).distance_to(e) < 30.0:
			car.route.pop_back()
			car.end_d = clampf(dp, 0.5, pw.len - 0.5)
			return
	var stop: Dictionary = pl.get("stop", {})
	if may_replan and not car.get("pulled_over", false) and _lane_point(w, 0, d).distance_to(e) > 30.0 \
			and stop.has("seg"):
		car.goal = {"seg": stop.seg, "frac": _frac(stop), "side": stop.get("side", 1)}
		car.to_stop = stop
		if _replan(car):
			return
	car.end_d = clampf(d, 0.5, w.len - 0.5)


## A driver who can't get there from this lane parks at the curb just
## ahead and walks the rest of the way, rather than stopping in the road.
func _pull_over(car: Dictionary, w: Dictionary) -> void:
	var pl := place(car.to_place)
	if pl.is_empty():
		return
	var at := clampf(car.d + 14.0, 0.0, w.len)
	var frac: float = at / w.len if w.fwd else 1.0 - at / w.len
	var curb := _curb_spots({"seg": w.seg, "at_frac": frac, "side": 1 if w.fwd else -1}, 1)
	if curb.is_empty():
		return
	_release(pl.ref, car.get("to_spot", -1), car.id)
	car.to_spot = _add_spot(pl, curb[0], car.id)
	car.pulled_over = true
	car.end_d = clampf(_nearest_d(w, _entrance(pl, car.to_spot)), car.d + PARK_LEAD, w.len - 0.5)


## Where cars leave the road for a spot: the curb cut, the lane's road end,
## or the curb space itself.
func _entrance(pl: Dictionary, spot: int) -> Vector3:
	var s: Dictionary = pl.spots[spot]
	if s.kind == "curb":
		return s.pos - s.face * 9.0
	if not pl.drive.is_empty():
		return pl.drive[pl.drive.size() - 1]
	return SiteLayout.world(pl.lot, Vector2(pl.lay.cut_x, -pl.lot.to_curb))


## The way in, from the edge of the road to the spot, in local steps.
func _approach_pts(pl: Dictionary, spot: int, car_len: float) -> Array:
	var s: Dictionary = pl.spots[spot]
	var front: Vector3 = s.pos + s.face * car_len * 0.5
	if s.kind == "curb":
		return [s.pos - s.face * (car_len * 0.5 + 1.0), front]
	if not pl.drive.is_empty():
		var out := []
		for i in range(pl.drive.size() - 1, 0, -1):
			out.append(pl.drive[i])
		out.append(front)
		return out
	var lot: Dictionary = pl.lot
	var lay: Dictionary = pl.lay
	var cut: float = lay.cut_x
	var sp: Vector2 = s.local
	var pts := [Vector2(cut, -lot.to_curb)]
	match s.kind:
		"stall":
			pts.append(Vector2(cut, lay.aisle_z))
			pts.append(Vector2(sp.x, lay.aisle_z))
		"bay":
			pts.append(Vector2(cut, sp.y - 13.0))
			pts.append(Vector2(sp.x, sp.y - 9.0))
	var out := []
	for p in pts:
		out.append(SiteLayout.world(lot, p))
	out.append(front)
	return out


## Path from the lane into a spot, starting where the car is now.
func _in_path(car: Dictionary) -> Dictionary:
	var pl := _dest(car)
	if pl.is_empty():
		var here := car_pose(car)
		return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": -1, "lo": -1, "turn": Turn.RIGHT,
			"vt": 4.0, "exit_d": 0.0}, _smooth([here[0], here[0] + here[1] * 3.0]), 0.0)
	car.spot_geo = pl.spots[car.to_spot].duplicate()  # where this path ends
	var w: Dictionary = ways[car.route[car.leg]]
	# Start along the car's own heading, so the turn in begins smoothly.
	var here := car_pose(car)
	var wps := [here[0], here[0] + here[1] * 2.0,
		_lane_point(w, car.lane, clampf(car.end_d - 1.0, car.d + 2.5, w.len))]
	wps.append_array(_approach_pts(pl, car.to_spot, car.len))
	return _poly_path({"node": -1, "wi": w.id, "li": car.lane, "wo": -1, "lo": -1, "turn": Turn.RIGHT,
		"vt": 4.0, "exit_d": 0.0}, _smooth(wps), 0.0)


## Path out of a spot into lane `lane` of way `w`, starting at road position
## `d`: backing out of the stall or driveway first, as drivers do.
func _out_path(car: Dictionary, pl: Dictionary, spot: int, w: Dictionary, lane: int, d: float) -> Dictionary:
	var s: Dictionary = pl.spots[spot]
	var top: float = maxf(w.s1 - 0.5, 1.0)  # back in the lane before the junction
	var bot: float = minf(w.s0 + 0.5, top)  # and clear of the one behind
	var front: Vector3 = s.pos + s.face * car.len * 0.5
	var entry := _entrance(pl, spot)
	var de := _nearest_d(w, entry)
	if s.kind == "curb":
		# Pull away from the curb into the lane.
		var df := _nearest_d(w, front)
		var go := clampf(df + 7.0, bot, top)
		var pts := _smooth([front, front + s.face * 2.0] + _lane_run(w, lane, minf(clampf(df + 4.0, bot, top), go - 3.0), go))
		return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
			"vt": 4.0, "exit_d": go}, pts, 0.0)
	if s.kind == "drive" or s.kind == "garage":
		# Straight back down the driveway and out into the street, ending up
		# pointed the way the car is going.
		# (A driveway at a corner backs out along the street, clear of the junction.)
		de = clampf(de, minf(bot + 8.0, top), top)
		var back_d := clampf(de - 8.0, bot, top)
		var rev := [front, entry]
		rev.append_array(_lane_run(w, lane, de, back_d))
		var pts := _smooth(rev)
		return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
			"vt": 4.0, "exit_d": back_d}, pts, _polylen(pts))
	# Back out of the stall or dock, turning to face the way out, then drive
	# forward to the street.
	var side := Vector3(-s.face.z, 0.0, s.face.x)
	var swing := side if side.dot(entry - s.pos) < 0.0 else -side
	var back: float = car.len + (7.0 if s.kind == "bay" else 1.5)
	var mid: Vector3 = front - s.face * back
	var rev_pts := _smooth([front, mid, mid + swing * 4.5])
	var fwd := [rev_pts[rev_pts.size() - 1], mid]
	if not pl.drive.is_empty():
		for i in range(1, pl.drive.size()):
			fwd.append(pl.drive[i])
	elif not pl.lay.is_empty():
		if s.kind == "stall":
			fwd.append(SiteLayout.world(pl.lot, Vector2(pl.lay.cut_x, pl.lay.aisle_z)))
		fwd.append(entry)
	de = minf(de, maxf(top - DRIVEWAY_LEAD - 2.0, bot))
	var exit_d := clampf(de + DRIVEWAY_LEAD + 2.0, bot, top)
	# The last few metres run along the lane, so it joins the traffic straight.
	fwd.append_array(_lane_run(w, lane, minf(clampf(de + 2.0, bot, top), exit_d - 3.0), exit_d))
	var fwd_pts := _smooth(fwd)
	var all := rev_pts.duplicate()
	for i in range(1, fwd_pts.size()):
		all.append(fwd_pts[i])
	return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
		"vt": 4.0, "exit_d": exit_d}, all, _polylen(rev_pts))


## A path through these points with the corners rounded off.
## Points along a lane from `a` to `b` (either way), close enough to follow
## a curved street, and ending pointed along it.
func _lane_run(w: Dictionary, lane: int, a: float, b: float) -> Array:
	var out := []
	var n := maxi(1, ceili(absf(b - a) / 3.0))
	for k in n:
		out.append(_lane_point(w, lane, lerpf(a, b, float(k) / n)))
	if absf(b - a) > 1.6:
		out.append(_lane_point(w, lane, b - signf(b - a) * 0.8))
	out.append(_lane_point(w, lane, b))
	return out


static func _smooth(wps: Array) -> PackedVector3Array:
	var p := []
	for q in wps:
		if p.is_empty() or Vector2(q.x - p[-1].x, q.z - p[-1].z).length() > 0.5:
			p.append(Vector3(q.x, 0.0, q.z))
	var out := PackedVector3Array([p[0]])
	if p.size() == 1:
		out.append(p[0] + Vector3(0, 0, 0.01))
		return out
	if p.size() == 2:
		var n := maxi(2, int(p[0].distance_to(p[1]) / 0.8))
		for k in range(1, n + 1):
			out.append(p[0].lerp(p[1], float(k) / n))
		return out
	for i in range(1, p.size() - 1):
		var a: Vector3 = p[0] if i == 1 else (p[i - 1] + p[i]) * 0.5
		var b: Vector3 = p[p.size() - 1] if i == p.size() - 2 else (p[i] + p[i + 1]) * 0.5
		if i > 1:
			pass  # the straight run to `a` is the previous curve's end
		var n := maxi(6, int((a.distance_to(p[i]) + p[i].distance_to(b)) / 0.3))
		for k in range(1, n + 1):
			out.append(RoadNetwork.bezier(a, p[i], b, float(k) / n))
	return out


static func _polylen(pts: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(1, pts.size()):
		s += pts[i].distance_to(pts[i - 1])
	return s


func _poly_path(c: Dictionary, pts: PackedVector3Array, rev: float) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var d0 := _flat_dir(pts[mini(1, pts.size() - 1)] - pts[0])
	c.merge({"id": -1, "pts": pts, "cum": cum, "len": maxf(cum[cum.size() - 1], 0.5), "rev": rev,
		"ctrl": pts[0], "d0": -d0 if rev > 0.0 else d0, "d1": _flat_dir(pts[pts.size() - 1] - pts[maxi(pts.size() - 2, 0)])})
	return c


## Heading along a poly path: its own direction, reversed while backing up.
func _poly_pose(c: Dictionary, jd: float) -> Array:
	var p := _poly_point(c.pts, c.cum, jd)
	# Heading from a short chord around the point, so it turns smoothly; the
	# chord stays on one side of where a car stops backing up.
	var lo := 0.0 if jd >= c.rev else 0.0
	var hi: float = c.len
	if c.rev > 0.0:
		if jd < c.rev:
			hi = c.rev
		else:
			lo = c.rev
	var a := _poly_point(c.pts, c.cum, maxf(jd - 0.5, lo))
	var b := _poly_point(c.pts, c.cum, minf(jd + 0.5, hi))
	var dir := _flat_dir(b - a)
	if b.distance_to(a) < 0.05:
		dir = c.d1 if jd >= c.rev else -c.d0
	if jd < c.rev:
		dir = -dir
	return [p, dir]


## A car pulled in: it parks, its trip is reported, and the people in it
## get out and walk in.
func _arrive(car: Dictionary) -> void:
	if car.get("to_ref", "") != "" and car.get("trip", -1) >= 0 and car.get("after", {}).get("report", true):
		_report(car, arrivals)
	if car.get("retire", false) or car.to_place == "edge":
		return  # off the map, or gone for good
	var pl := place(car.to_place)
	if pl.is_empty():
		return
	# Park in the very spot the car drove into, even if the lot has been
	# rebuilt around it since it turned in.
	var geo: Dictionary = car.get("spot_geo", {})
	car.erase("spot_geo")
	if not geo.is_empty():
		var at := -1
		for i in pl.spots.size():
			if pl.spots[i].pos.distance_to(geo.pos) < 1.0 and (pl.taken[i] == -1 or pl.taken[i] == car.id):
				at = i
				break
		if at == -1:
			at = _add_spot(pl, geo, car.id)
		_release(pl.ref, car.to_spot, car.id)
		pl.taken[at] = car.id
		car.to_spot = at
	elif _dest(car).is_empty():
		return
	var after: Dictionary = car.get("after", {})
	var dest: String = car.to_ref
	_park(car, pl, car.get("to_spot", 0))
	var stay: int = after.get("stay", -1)
	var driver: int = after.get("driver", -1)
	car.after = {}
	car.cargo = {} if after.has("back") else car.cargo
	if driver != -1:
		# The driver gets out and walks to the door; the car waits for them.
		car.driver = driver
		car.until = -1
		_walk(driver, _walk_from_car(car, dest), {"enter": dest, "stay": stay})
	elif after.has("back"):
		_due_at(car, _tick + maxi(stay, 1))
		car.next = after.back
		if after.has("back_stop"):
			car.next_stop = after.back_stop
	else:
		car.until = -1


## Vehicles whose time is up head off again.
func _rest() -> void:
	# Most parked vehicles are just parked: pick out the few with somewhere
	# to be first, without copying the whole list.
	# Each is filed under the tick it's due; entries a vehicle has since
	# outgrown (it left, or its time changed) are dropped. Taken in the
	# order they parked, as a loaded town would.
	var due := []
	var ticks := []
	for t in _due:
		if t <= _tick:
			ticks.append(t)
	for t in ticks:
		for car in _due[t]:
			if car.until == t and is_same(_by_vid.get(car.id), car):
				due.append(car)
		_due.erase(t)
	for vid in _pend:
		var car: Dictionary = _pend[vid]
		if car.has("pending") and is_same(_by_vid.get(vid), car):
			due.append(car)
	if due.is_empty():
		return
	due.sort_custom(func(a, b): return _pseq[a.id] < _pseq[b.id])
	var last := -1
	for car in due:
		if car.id == last:
			continue
		last = car.id
		if car.get("pending", false):
			if _try_launch(car):
				_pend.erase(car.id)
			continue
		var back: String = car.get("next", "")
		var stop: Dictionary = car.get("next_stop", {})
		car.until = -1
		car.erase("next")
		car.erase("next_stop")
		if back == "":
			continue
		if cars.size() >= MAX_CARS or not _send(car, back, "return", {}, {"report": false}, stop):
			_due_at(car, _tick + 20)  # try again shortly
			car.next = back
			car.next_stop = stop




# --- People -------------------------------------------------------------------

## Sends a person somewhere: on foot if it's close or their car isn't here,
## otherwise a walk to the car and a drive. False if they can't go now.
func go(pid: int, to_ref: String, purpose: String, stay: int) -> bool:
	if _sim == null or not _sim.people.people.has(pid):
		return false
	var p: Dictionary = _sim.people.people[pid]
	var home_ref: String = "lot:" + p.home
	var from_ref: String = home_ref if p.at == "" else p.at
	if from_ref == to_ref or p.at == "travel":
		return false
	var from_pl := place(from_ref)
	var to_pl := place(to_ref)
	if from_pl.is_empty() or to_pl.is_empty():
		return false
	var car := _vehicle_parked(p.car)
	var far: bool = from_pl.door.distance_to(to_pl.door) > People.WALK_MAX
	if not car.is_empty() and (far or car.at_place != from_ref) and cars.size() < MAX_CARS:
		var path := _walk_to_car(from_pl, car)
		if path.is_empty():
			return false
		car.driver = pid
		_walk(pid, path, {"drive": car.id, "to": to_ref, "purpose": purpose, "stay": stay})
	else:
		var path := _walk_between(from_pl, to_pl)
		if path.is_empty() or walkers.size() >= MAX_WALKERS:
			return false
		_walk(pid, path, {"enter": to_ref, "stay": stay})
	p.at = "travel"
	_sim.people.set_until(p, -1)
	return true


func _walk(pid: int, pts: PackedVector3Array, then: Dictionary) -> void:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var w := {"id": _next_walker, "person": pid, "pts": pts, "cum": cum, "len": cum[cum.size() - 1],
		"d": 0.0, "t": 0, "then": then, "t0": _wstep,
		# Walking pace in whole cm/s, and distance worked out from the ticks
		# walked, so a saved and loaded walker is exactly where it was.
		"v": float(roundi(WALK_V * (85 + hash([pid, _next_walker]) % 31))) / 100.0}
	# At a signal, people wait at the kerb until the cars on the road they
	# cross have a red (MUTCD Walk / Don't Walk with the parallel green):
	# worked out now, since the lights run on a fixed cycle.
	var holds := []
	var xings := []
	var waited := 0
	for m in _marks:
		var i := pts.find(m[0])
		if i < 0 or i + 1 >= pts.size() or not junctions.has(int(m[1])):
			continue
		var steps: float = cum[i] / (w.v * DT) + waited
		var wait := _red_wait(int(m[1]), int(m[2]), time + steps * DT)
		if wait > 0.0:
			var ws := ceili(wait / DT)
			holds.append([cum[i], ws])
			waited += ws
		# When they're out on the crosswalk, in steps from setting off.
		var on: float = cum[i] / (w.v * DT) + waited
		xings.append([floori(on), ceili(on + (cum[i + 1] - cum[i]) / (w.v * DT)), int(m[1]), int(m[2]) >> 1])
	_marks.clear()
	if not holds.is_empty():
		w.holds = holds
	if not xings.is_empty():
		w.xings = xings
		_note_xings(w)
	walkers.append(w)
	_file_walker(w)
	_next_walker += 1


## Files a walker under the step they arrive: the first whole step count t
## with t * v * DT >= len.
func _file_walker(w: Dictionary) -> void:
	var t := maxi(ceili(w.len / (w.v * DT)), 1)
	while t > 1 and (t - 1) * w.v * DT >= w.len:
		t -= 1
	while t * w.v * DT < w.len:
		t += 1
	for h in w.get("holds", []):
		t += int(h[1])
	var at: int = int(w.t0) + t
	if not _wdone.has(at):
		_wdone[at] = []
	_wdone[at].append(w)


## Metres a walker has gone (worked out from the steps, not stored).
func _walker_d(w: Dictionary) -> float:
	var steps := float(_wstep - int(w.t0))
	if not w.has("holds"):
		return steps * w.v * DT
	var step_m: float = w.v * DT
	var d := 0.0
	for h in w.holds:
		var to_h: float = (float(h[0]) - d) / step_m
		if steps <= to_h:
			return d + steps * step_m
		steps -= to_h
		d = h[0]
		if steps <= float(h[1]):
			return d  # waiting at the kerb
		steps -= float(h[1])
	return minf(d + steps * step_m, w.len)


## Puts a walker's crosswalk crossings on the junctions' lists.
func _note_xings(w: Dictionary) -> void:
	for x in w.xings:
		var n: int = x[2]
		if not _xbusy.has(n):
			_xbusy[n] = []
		_xbusy[n].append([int(w.t0) + int(x[0]), int(w.t0) + int(x[1]), int(x[3]), w])


## Whether someone is out on the crosswalk over road `seg` at junction `n`
## right now: turning cars wait for them (pedestrians have the right of way
## in a crosswalk, as every US state's code has it).
func crosswalk_busy(n: int, seg: int) -> bool:
	var list: Array = _xbusy.get(n, _NO_XINGS)
	if list.is_empty():
		return false
	var busy := false
	var keep := []
	for e in list:
		if int(e[1]) < _wstep or e[3].has("gone"):
			continue
		keep.append(e)
		if int(e[2]) == seg and int(e[0]) <= _wstep:
			busy = true
	if keep.size() != list.size():
		if keep.is_empty():
			_xbusy.erase(n)
		else:
			_xbusy[n] = keep
	return busy


## Seconds until the cars coming in on `way` get a red at a signal, from
## driving time `t` (0 if they already have one, or there's no signal).
func _red_wait(node: int, way: int, t: float) -> float:
	var j: Dictionary = junctions[node]
	if j.control != Rule.SIGNAL:
		return 0.0
	var tt := fposmod(t + j.offset, j.cycle)
	var start := 0.0
	for ph in j.phases:
		if ph.ways.has(way):
			if tt >= start and tt < ph.y_end:
				return ph.y_end - tt
			return 0.0
		start = ph.end
	return 0.0


## Walkers as saved: with how far they've got, and without the step they
## set off on (that counts from the load).
func _walkers_saved() -> Array:
	var out := []
	for w in walkers:
		var e: Dictionary = w.duplicate()
		e.t = _wstep - int(w.t0)
		e.d = _walker_d(w)
		e.erase("t0")
		out.append(e)
	return out


## Moves everyone on foot along, and lets them do what they set out to.
func _step_walkers() -> void:
	# Only the ones arriving this step are touched; where the rest are is
	# worked out from the step count when it's wanted.
	_wstep += 1
	if _wstep % 600 == 0:
		for n in _xbusy.keys():
			crosswalk_busy(n, -1)  # drops crossings that are over
	var done: Array = _wdone.get(_wstep, [])
	_wdone.erase(_wstep)
	if done.is_empty():
		return
	done.sort_custom(func(a, b): return a.id < b.id)
	for w in done:
		if w.has("gone"):
			continue  # stopped walking (left town)
		walkers.erase(w)
		w.t = _wstep - int(w.t0)
		w.d = w.len
		_walked(w)


func _walked(w: Dictionary) -> void:
	if _sim == null or not _sim.people.people.has(w.person):
		return
	var p: Dictionary = _sim.people.people[w.person]
	var then: Dictionary = w.then
	if then.has("enter"):
		var home_ref: String = "lot:" + p.home
		p.at = "" if then.enter == home_ref else then.enter
		_sim.people.set_until(p, -1 if then.enter == home_ref else _tick + maxi(int(then.get("stay", 30)), 1))
	elif then.has("drive"):
		var car := _vehicle_parked(int(then.drive))
		if car.is_empty() or not _send(car, then.to, then.purpose, {}, {"driver": w.person, "stay": then.stay}):
			# Can't get there: back inside.
			if not car.is_empty():
				car.driver = -1
			p.at = "" if car.is_empty() or car.at_place == "lot:" + p.home else car.at_place
			_sim.people.set_until(p, _tick + 30 if p.at != "" else -1)
			return


## From a place's door to a parked car (in this lot, or a short walk away).
func _walk_to_car(from_pl: Dictionary, car: Dictionary) -> PackedVector3Array:
	var car_pl := place(car.at_place)
	if car_pl.is_empty():
		return PackedVector3Array()
	var out := PackedVector3Array()
	if car_pl.ref != from_pl.ref:
		out = _walk_between(from_pl, car_pl)
		if out.is_empty():
			return out
		out.remove_at(out.size() - 1)  # not to the door: to the car
	else:
		out = _door_out(from_pl)
	var side := _car_side(car)
	out.append(side)
	return out


## From a parked car to the door of the place its people are going to.
func _walk_from_car(car: Dictionary, dest: String) -> PackedVector3Array:
	var car_pl := place(car.at_place)
	var dest_pl := place(dest)
	var out := PackedVector3Array([_car_side(car)])
	if dest_pl.is_empty() or car_pl.is_empty():
		return out
	if dest_pl.ref == car_pl.ref:
		var inward := _door_out(car_pl)
		inward.reverse()
		out.append_array(inward)
		return out
	var path := _walk_between(car_pl, dest_pl)
	if path.size() > 1:
		path.remove_at(0)
	out.append_array(path)
	return out


## Beside the driver's door of a parked car.
func _car_side(car: Dictionary) -> Vector3:
	var back: Vector3 = car.pos - car.face * car.len * 0.55
	return back + Vector3(car.face.z, 0.0, -car.face.x) * 1.4


## From a place's door out along its front walk to the sidewalk.
func _door_out(pl: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array([pl.door])
	if pl.lay.is_empty():
		return out
	var door: Vector2 = pl.lay.door
	out.append(SiteLayout.world(pl.lot, Vector2(door.x, pl.lay.walk_z)))
	return out


## A walk on the town's trail from home and back, like neighbours on an
## Indiana greenway (the Monon, a small-town riverwalk): out the front, along
## the sidewalk to where the trail meets the street, along the trail for a
## stretch and back the same way. False if the trail doesn't come by.
func stroll(pid: int) -> bool:
	if _sim == null or not _sim.people.people.has(pid) or walkers.size() >= MAX_WALKERS:
		return false
	var p: Dictionary = _sim.people.people[pid]
	if p.at != "":
		return false
	var trails: Array = _sim.parks.trails.paths
	if trails.is_empty():
		return false
	var pl := place("lot:" + p.home)
	if pl.is_empty() or pl.lay.is_empty() or pl.lot.is_empty() or not network.segments.has(int(pl.lot.seg)):
		return false
	# Where the trail comes closest to this side of the street: it crosses
	# or runs beside it within a few metres of the sidewalk.
	var line := _walk_line(int(pl.lot.seg), int(pl.lot.side))
	var best := TRAIL_ACCESS
	var line_i := -1
	var path_i := -1
	var seg_i := 0
	var hit := Vector2.ZERO
	for li in line.size():
		var at := Vector2(line[li].x, line[li].z)
		for i in trails.size():
			var pts: Array = trails[i].pts
			for k in pts.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(at,
					Vector2(float(pts[k][0]), float(pts[k][1])), Vector2(float(pts[k + 1][0]), float(pts[k + 1][1])))
				if q.distance_to(at) < best:
					best = q.distance_to(at)
					line_i = li
					path_i = i
					seg_i = k
					hit = q
	if path_i < 0:
		return false
	# Along it for 400 to 1,200 m (a 15 to 30 minute walk there and back),
	# whichever way has more trail.
	var pts: Array = trails[path_i].pts
	var want := 400.0 + float(hash([pid, _tick]) % 800)
	var legs := []
	for dir in [1, -1]:
		var leg := [hit]
		var left := want
		var cur := hit
		var k := seg_i + 1 if dir > 0 else seg_i
		while k >= 0 and k < pts.size() and left > 0.0:
			var q := Vector2(float(pts[k][0]), float(pts[k][1]))
			var d := cur.distance_to(q)
			if d >= left:
				leg.append(cur + (q - cur) / maxf(d, 0.001) * left)
				left = 0.0
			else:
				left -= d
				leg.append(q)
				cur = q
			k += dir
		legs.append([left, leg])
	var leg: Array = legs[0][1] if legs[0][0] <= legs[1][0] else legs[1][1]
	if leg.size() < 2:
		return false
	var there := _door_out(pl)
	_append_span(there, line, _frac(pl.lot), float(line_i) / (line.size() - 1))
	for q in leg:
		there.append(Vector3(q.x, 0.0, q.y))
	var home := there.duplicate()
	home.reverse()
	there.append_array(home.slice(1))
	_walk(pid, there, {"enter": "lot:" + p.home, "stroll": true})
	_sim.parks.trails.walked += 1
	p.at = "travel"
	_sim.people.set_until(p, -1)
	return true


## On foot from one place's door to another's, along the sidewalks and
## across at the corners.
func _walk_between(a: Dictionary, b: Dictionary) -> PackedVector3Array:
	var out := _door_out(a)
	if a.lot.is_empty() or b.lot.is_empty():
		return PackedVector3Array()
	var sa := SiteLayout.world(a.lot, Vector2(a.lay.door.x, SiteLayout.WALK_Z))
	var sb := SiteLayout.world(b.lot, Vector2(b.lay.door.x, SiteLayout.WALK_Z))
	out.append(sa)
	var mid := _sidewalks(a.lot, b.lot)
	if mid.is_empty() and a.lot.seg != b.lot.seg:
		return PackedVector3Array()
	out.append_array(mid)
	out.append(sb)
	var inward := _door_out(b)
	inward.reverse()
	out.append_array(inward)
	return out


## Sidewalk points between two lots' fronts (not including either end).
func _sidewalks(la: Dictionary, lb: Dictionary) -> PackedVector3Array:
	_marks.clear()
	var out := PackedVector3Array()
	if la.seg == lb.seg and la.side == lb.side:
		var line := _walk_line(la.seg, la.side)
		_append_span(out, line, _frac(la), _frac(lb))
		return out
	# Shortest way over the sidewalks: along the blocks, around corners and
	# over the crosswalks at junctions (never mid-block), with a wait for
	# the light at signals.
	if not network.segments.has(la.seg) or not network.segments.has(lb.seg):
		return out
	var start_f := _frac(la)
	var goal_f := _frac(lb)
	var dist := {}
	var prev := {}
	var open := []
	for end in [0, 1]:
		var st := Vector3i(_seg_node(la.seg, end), la.seg, la.side)
		var f := _walk_end(la.seg, end)
		dist[st] = absf(f - start_f) * _seg_len(la.seg)
		prev[st] = null
		open.append(st)
	var seen := {}
	var best := People.WALK_MAX * 2.0
	var best_end = null
	while not open.is_empty():
		var u: Vector3i = open[0]
		for m in open:
			if dist[m] < dist[u] or (dist[m] == dist[u] and (m.x < u.x or m.x == u.x and (m.y < u.y or m.y == u.y and m.z < u.z))):
				u = m
		open.erase(u)
		if seen.has(u):
			continue
		seen[u] = true
		var du: float = dist[u]
		if du > best:
			break
		if u.y == lb.seg and u.z == lb.side:
			var e := 0 if u.x == _seg_node(u.y, 0) else 1
			var total := du + absf(_walk_end(u.y, e) - goal_f) * _seg_len(u.y)
			if total < best:
				best = total
				best_end = u
		for step in _walk_steps(u):
			var v: Vector3i = step[0]
			var nd: float = du + step[1]
			if nd < dist.get(v, INF):
				dist[v] = nd
				prev[v] = [u, step[2]]
				open.append(v)
	if best_end == null:
		return out
	var chain := []
	var x = best_end
	while prev[x] != null:
		chain.push_front([prev[x][0], x, prev[x][1]])
		x = prev[x][0]
	var first: Vector3i = x
	_append_span(out, _walk_line(la.seg, la.side), start_f, _walk_end(first.y, 0 if first.x == _seg_node(first.y, 0) else 1))
	for c in chain:
		var from: Vector3i = c[0]
		var to: Vector3i = c[1]
		var f0 := _walk_end(from.y, 0 if from.x == _seg_node(from.y, 0) else 1)
		var f1 := _walk_end(to.y, 0 if to.x == _seg_node(to.y, 0) else 1)
		match c[2]:
			"along":
				_append_span(out, _walk_line(to.y, to.z), f0, f1)
			"cross":
				# Wait at the kerb for the light, then over.
				var at := _line_at(_walk_line(from.y, from.z), f0 * (_walk_line(from.y, from.z).size() - 1))
				out.append(at)
				var way_in: int = from.y * 2 + (1 if from.x == _seg_node(from.y, 1) else 0)
				_marks.append([at, from.x, way_in])
				out.append(_line_at(_walk_line(to.y, to.z), f1 * (_walk_line(to.y, to.z).size() - 1)))
			_:
				out.append(_line_at(_walk_line(to.y, to.z), f1 * (_walk_line(to.y, to.z).size() - 1)))
	var last: Vector3i = best_end
	_append_span(out, _walk_line(lb.seg, lb.side), _walk_end(last.y, 0 if last.x == _seg_node(last.y, 0) else 1), goal_f)
	return out


## A segment's node at one end (0: a, 1: b).
func _seg_node(sid: int, end: int) -> int:
	var sg: Dictionary = network.segments[sid]
	return sg.a if end == 0 else sg.b


## Where a sidewalk stops short of the junction at one end of a segment, as
## a share of its length: at the stop line, where the crosswalk is.
func _walk_end(sid: int, end: int) -> float:
	var w: Dictionary = ways.get(sid * 2 + 1, ways.get(sid * 2, {}))
	if w.is_empty():
		return 0.0 if end == 0 else 1.0
	var fwd: bool = w.fwd
	var s0: float = w.s0 if fwd else w.len - w.s1
	var s1: float = w.s1 if fwd else w.len - w.s0
	return clampf((s0 if end == 0 else s1) / maxf(w.len, 0.1), 0.0, 1.0)


## From the end of one sidewalk at a junction: along it to the far end,
## around the corner to the next sidewalk, or over the crosswalk to the
## other side of the same road. [[state, metres, kind]].
func _walk_steps(u: Vector3i) -> Array:
	var outs := []
	var sid := u.y
	var n := u.x
	var other := _seg_node(sid, 1) if n == _seg_node(sid, 0) else _seg_node(sid, 0)
	var e_here := 0 if n == _seg_node(sid, 0) else 1
	outs.append([Vector3i(other, sid, u.z), absf(_walk_end(sid, 1) - _walk_end(sid, 0)) * _seg_len(sid), "along"])
	var ring := _corner_ring(n)
	var k := -1
	for i in ring.size():
		if ring[i][0] == sid and ring[i][1] == u.z:
			k = i
	if k < 0:
		return outs
	for dk in [-1, 1]:
		var nb: Array = ring[(k + dk + ring.size()) % ring.size()]
		if nb[0] < 0:
			continue  # a road with no sidewalks between
		var here: Vector3 = ring[k][2]
		var d: float = here.distance_to(nb[2])
		if nb[0] == sid:
			outs.append([Vector3i(n, sid, nb[1]), d + 10.0, "cross"])
		else:
			outs.append([Vector3i(n, nb[0], nb[1]), d, "corner"])
	return outs


## The sidewalk ends around a junction, leg by leg in order of the roads'
## headings, each leg's two ends in turn: [segment, side, point]. A road
## without sidewalks is [-1, 0, point] and nobody walks past it.
func _corner_ring(n: int) -> Array:
	if _rings.has(n):
		return _rings[n]
	var c: Vector3 = network.nodes[n]
	var legs := []
	for sid in network.segments_at(n):
		var e := 0 if n == _seg_node(sid, 0) else 1
		var samp := network.sample_segment(sid, 8)
		var toward: Vector3 = samp[1] if e == 0 else samp[samp.size() - 2]
		var ang := atan2(toward.z - c.z, toward.x - c.x)
		var ends := []
		if not RoadStyle.TYPES[network.segments[sid].type].lots:
			ends.append([0.0, [-1, 0, toward]])
		else:
			for side in [1, -1]:
				var line := _walk_line(sid, side)
				var pt := _line_at(line, _walk_end(sid, e) * (line.size() - 1))
				ends.append([wrapf(atan2(pt.z - c.z, pt.x - c.x) - ang, -PI, PI), [sid, side, pt]])
			ends.sort_custom(func(p, q): return p[0] < q[0])
		legs.append([ang, sid, ends])
	legs.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
	var ring := []
	for leg in legs:
		for e in leg[2]:
			ring.append(e[1])
	_rings[n] = ring
	return ring


func _seg_len(sid: int) -> float:
	return ways[sid * 2 + 1].len if ways.has(sid * 2 + 1) else (ways[sid * 2].len if ways.has(sid * 2) else 1.0)


## The middle of the sidewalk along a road, on one side (seen from a to b).
func _walk_line(sid: int, side: int) -> PackedVector3Array:
	var key := sid * 2 + (1 if side > 0 else 0)
	if _walk_lines.has(key):
		return _walk_lines[key]
	var pts := network.sample_segment(sid, 16)
	var off := RoadStyle.half_width(network.segments[sid].type) + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH \
		+ RoadStyle.SIDEWALK_WIDTH * 0.5
	var out := PackedVector3Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := _flat_dir(b - a)
		out.append(Vector3(pts[i].x, 0.0, pts[i].z) + Vector3(-dir.z, 0.0, dir.x) * off * side)
	_walk_lines[key] = out
	return out


## The part of a line between two shares of its length, in that order.
static func _append_span(out: PackedVector3Array, line: PackedVector3Array, f0: float, f1: float) -> void:
	var n := line.size() - 1
	var i0 := f0 * n
	var i1 := f1 * n
	out.append(_line_at(line, i0))
	if i1 > i0:
		for i in range(int(floor(i0)) + 1, int(ceil(i1))):
			out.append(line[i])
	else:
		for i in range(int(ceil(i0)) - 1, int(floor(i1)), -1):
			out.append(line[i])
	out.append(_line_at(line, i1))


static func _line_at(line: PackedVector3Array, f: float) -> Vector3:
	var i := clampi(int(floor(f)), 0, line.size() - 2)
	return line[i].lerp(line[i + 1], clampf(f - i, 0.0, 1.0))


## Where a person on foot is and which way they face.
func walker_pose(w: Dictionary, ahead := 0.0) -> Array:
	var d := minf(_walker_d(w) + ahead, w.len)
	var p := _poly_point(w.pts, w.cum, d)
	var q := _poly_point(w.pts, w.cum, minf(d + 0.5, w.len))
	if q.distance_to(p) < 0.01:
		q = p + _flat_dir(w.pts[w.pts.size() - 1] - w.pts[maxi(w.pts.size() - 2, 0)]) * 0.5
	return [p, _flat_dir(q - p)]


## A vehicle by id, wherever it is: {"car", "state": "driving"|"waiting"|
## "parked"}, or {} if it's gone.
func find_vehicle(vid: int) -> Dictionary:
	for car in cars:
		if car.id == vid:
			return {"car": car, "state": "driving"}
	for car in parked:
		if car.id == vid:
			return {"car": car, "state": "parked"}
	for car in _waiting:
		if car.id == vid:
			return {"car": car, "state": "waiting"}
	for car in flowing:
		if car.id == vid:
			return {"car": car, "state": "flowing"}
	return {}


## The middle of a vehicle, for picking and following it.
func vehicle_centre(car: Dictionary, parked_now: bool) -> Vector3:
	var pose := parked_pose(car) if parked_now else car_pose(car)
	return pose[0] - pose[1] * car.len * 0.5


## The vehicle under a ground point (one in sight, not inside a building),
## or -1.
func vehicle_at(p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for list in [cars, parked]:
		for car in list:
			if list == parked and car.get("hidden", false):
				continue
			var pose := parked_pose(car) if list == parked else car_pose(car)
			var dir: Vector3 = pose[1]
			var rel: Vector3 = p - pose[0]
			var along := -rel.dot(dir)  # metres back from the front bumper
			var side := absf(rel.dot(Vector3(-dir.z, 0.0, dir.x)))
			if along < -1.0 or along > car.len + 1.0 or side > 2.2:
				continue
			var d := absf(along - car.len * 0.5) + side
			if d < best_d:
				best_d = d
				best = car.id
	return best


## The person walking at a ground point, or -1.
func walker_at(p: Vector3) -> int:
	var best := -1
	var best_d := 1.6
	for w in walkers:
		var d: float = Vector2(p.x, p.z).distance_to(Vector2(walker_pose(w)[0].x, walker_pose(w)[0].z))
		if d < best_d:
			best_d = d
			best = w.person
	return best


func walker_of(pid: int) -> Dictionary:
	for w in walkers:
		if w.person == pid:
			return w
	return {}


## The vehicle type a car is drawn and listed as. Kinds from before vehicle
## types existed: a plain "car" becomes a household vehicle from the real
## fleet mix, fixed by its id.
static func vehicle_kind(car: Dictionary) -> String:
	var kind: String = car.get("kind", "car")
	if kind == "car":
		kind = VehicleTypes.household(car.id)
	if kind == "truck":
		kind = "box_truck"
	if not VehicleTypes.SPECS.has(kind):
		kind = "sedan"
	return kind


## Where a parked vehicle is: [front bumper, facing].
static func parked_pose(car: Dictionary) -> Array:
	return [car.pos, car.face]


# --- Driving ----------------------------------------------------------------

func _drive(_rng: RandomNumberGenerator) -> void:
	# Vehicles with a job that were waiting for a gap to pull out. Routes
	# only break when the roads are rebuilt, so they're checked once a version.
	var lanes := {}
	for car in _waiting.duplicate():
		if _waiting_ok != version and (not ways.has(car.route[0])
				or car.route.any(func(w): return not ways.has(w)) and not _replan(car)):
			# Its road went, or was rebuilt and there's no way through now.
			_waiting.erase(car)
			_report(car, failed)
		elif cars.size() < MAX_CARS:
			if lanes.is_empty():
				for other in cars:
					_lane_add(lanes, other)
			if _launch(car, lanes):
				_waiting.erase(car)
				_lane_add(lanes, car)
	_waiting_ok = version
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
			if car.jd >= car.j.len - (0.3 if car.j.wo < 0 else 0.0):
				if car.j.wo < 0:
					done.append(car)  # parked
					if car.has("to_place"):
						_arrive(car)
					else:
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
			if car.has("to_place") and car.d >= car.end_d - 40.0 and car.to_place != "edge" \
					and car.get("end_fixed", -1) != car.leg:
				car.end_fixed = car.leg
				_fix_end(car)  # the lot may have been built on since the trip began
			if car.has("to_place") and car.d >= car.end_d - PARK_LEAD:
				if car.to_place == "edge":
					done.append(car)  # off the edge of the map
					_arrive(car)
				elif not car.get("pulled_over", false) and not _dest(car).is_empty() \
						and _entrance(_dest(car), car.to_spot).distance_to(car_pose(car)[0]) > 40.0:
					_pull_over(car, w)  # the place isn't on this road any more
				else:
					car.j = _in_path(car)
					car.jd = 0.0
			elif car.has("to_place"):
				pass
			elif car.d >= car.end_d - (1.0 if car.park == null else DRIVEWAY_LEAD):
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
	# Only roads with cars on them or still recovering from a jam change;
	# the rest are at the limit already.
	if _slow_ok != version:
		_slow_ok = version
		_slow.clear()
		for wid in _speed:
			if _speed[wid] < 1.0:
				_slow[wid] = true
	for wid in way_sum:
		if _speed.has(wid):
			_slow[wid] = true
	for wid in _fshare:
		if _speed.has(wid):
			_slow[wid] = true
	for wid in _slow.keys():
		var sp: float
		var fs: float = _fshare.get(wid, 1.0)
		if way_sum.has(wid):
			sp = snappedf(lerpf(_speed[wid], minf(way_sum[wid][0] / way_sum[wid][1], fs), 0.05), 0.000001)
		else:
			sp = snappedf(lerpf(_speed[wid], fs, 0.02), 0.000001)
		if sp > 0.9999 and fs >= 1.0:
			sp = 1.0  # all but recovered (snapping would leave it just short)
			_slow.erase(wid)
		_speed[wid] = sp
		if ways.has(wid):
			var sw: Dictionary = ways[wid]
			_wcost[wid] = sw.len / (sw.vmax * maxf(sp, 0.15))
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
		# Front car first. Cars rarely pass within a lane and `cars` keeps
		# last tick's order, so an insertion sort is nearly a single pass.
		var l: Array = _lanes[key]
		for i in range(1, l.size()):
			var c: Dictionary = l[i]
			var k := i - 1
			while k >= 0 and (l[k].d < c.d or (l[k].d == c.d and l[k].id > c.id)):
				l[k + 1] = l[k]
				k -= 1
			l[k + 1] = c
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
	var key := Vector3i(wi, car.lane, wo)
	var c = _cfor.get(key)
	if c == null:
		c = {} if not lanes_for(wi, wo).has(car.lane) else _connector(wi, car.lane, wo, _out_lane(wi, car.lane, wo))
		_cfor[key] = c
	return c


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
	# Railroad crossing with the gates down: stop at the line, which the
	# MUTCD and the Uniform Vehicle Code put 15 to 50 ft short of the
	# nearest rail. A car too close to stop at a hard brake goes on through.
	for x in _xings.get(w.id, []):
		if not x[1].closed:
			continue
		var line: float = x[0] - XING_STOP
		if car.d > line + 1.5 or car.v * car.v / (2.0 * MAX_BRAKE) > line + 1.5 - car.d:
			continue
		if line - car.d < gap:
			gap = maxf(line - car.d, 0.0)
			vl = 0.0
	if car.leg == car.route.size() - 1:
		# Slow to turn into the driveway (by where the turn starts).
		var turn_at: float = car.end_d - (PARK_LEAD if car.has("to_place") else 0.0)
		return minf(_idm(car.v, v0, gap, vl), _idm(car.v, v0, turn_at - car.d + JAM_GAP + 4.0 * HEADWAY, 3.5))
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
					if car.has("to_place") and car.to_place != "edge":
						_pull_over(car, w)
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
	if car.jd < c.get("rev", 0.0):
		# Backing out: slowly, easing to a stop where it changes direction.
		var want := clampf(sqrt(2.0 * (c.rev - car.jd)), 0.4, 1.6)
		return clampf((want - car.v) * 2.0, -BRAKE, 1.0)
	var lead := _through_leader(c, -car.jd, car)
	var acc := _idm(car.v, c.vt, lead[0], lead[1])
	if c.wo < 0:
		acc = minf(acc, _idm(car.v, c.vt, c.len - car.jd + JAM_GAP - 0.2, 0.0))  # stop in the spot
		acc = maxf(acc, (0.5 - car.v) * 2.0) if c.len - car.jd > 0.4 else acc
	if c.has("rev"):
		# Slow for tight turns into and out of lots, as drivers do.
		var h0: Vector3 = _poly_pose(c, car.jd)[1]
		var bend := 0.0
		for ahead in [1.5, 3.0, 4.5]:
			bend = maxf(bend, absf(h0.signed_angle_to(_poly_pose(c, minf(car.jd + ahead, c.len))[1], Vector3.UP)) / ahead)
		if bend > 0.01:
			var safe := maxf(2.5 / bend, 1.2)  # about 15 degrees a tenth of a second at most
			if car.v > safe:
				acc = minf(acc, (safe - car.v) / DT)
	return acc


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
		if list[k].id != me.id and list[k].d > mine:
			best = list[k].d
			bv = list[k].v
			blen = list[k].len
			break
	for b in _box.get(c.node, []):
		if b.id == me.id or b.j.wo != c.wo or b.j.lo != c.lo:
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
		if b.id != car.id and bc.wo == c.wo and bc.lo == c.lo:
			queued += 1
	var list: Array = _lanes.get(c.wo * 8 + c.lo, [])
	if not list.is_empty():
		var room: float = list[list.size() - 1].d - ways[c.wo].s0
		if room < (queued + 1) * (car.len + JAM_GAP):
			return false
	# Someone on the crosswalk over the road we're turning onto.
	if c.wo >= 0 and crosswalk_busy(n, c.wo >> 1):
		return false
	# Nothing crossing our path in the junction.
	for b in occupants:
		if b.id == car.id:
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
				if ap.car.id == car.id or ap.conn.wi == c.wi or light(n, ap.conn.wi) != Light.GREEN:
					continue
				var theirs_minor: bool = ap.conn.turn == Turn.LEFT or ap.conn.turn == Turn.UTURN
				if (on_red or (mine_minor_turn and not theirs_minor)) and _soon(ap) and _conflicts(c, ap.conn):
					return false
		Rule.ALL_STOP:
			if not stopped:
				return false
			for ap in _approach.get(n, []):
				if ap.car.id != car.id and ap.conn.wi != c.wi and _first(ap.car, car) and _conflicts(c, ap.conn):
					return false
		Rule.PRIORITY:
			if not j.major.has(c.wi):
				if j.sign == "stop" and not stopped:
					return false
				for ap in _approach.get(n, []):
					if ap.car.id == car.id or ap.conn.wi == c.wi:
						continue
					if j.major.has(ap.conn.wi):
						if _soon(ap) and _conflicts(c, ap.conn):
							return false
					elif _first(ap.car, car) and _conflicts(c, ap.conn):
						return false
			elif mine_minor_turn:
				for ap in _approach.get(n, []):
					if ap.car.id == car.id or ap.conn.wi == c.wi or not j.major.has(ap.conn.wi):
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
	var budget := REPLANS_PER_TICK  # route plans are the costly part of a tick
	for car in cars:
		if budget == 0:
			return
		if (car.id * 7 + _tick) % 300 != 0 or car.j != null or car.commit:
			continue
		if car.leg >= car.route.size() - 1:
			continue
		var w: Dictionary = ways[car.route[car.leg]]
		if w.s1 - car.d < 30.0:
			continue
		budget -= 1
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
