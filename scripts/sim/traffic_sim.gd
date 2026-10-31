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
## Ticks between drivers' decisions (see _drive).
const THINK_EVERY := 3
## A car leaving a home's garage never waits for its door: the door starts
## up while its driver walks out to it, timed to be most of the way up
## (DOOR_SHARE) as the driver gets in. door_t is the tick it starts up and
## door_n the ticks it takes to go all the way: DOOR_TICKS (10 s of driving,
## a real opener's 10 to 12 s), or less after a short walk (no less than
## DOOR_MIN), so it is still up in time. Kept on the car's record (already
## saved; an older save has none and its door simply stays shut).
## DoorEvents reads them; the trip's timing never changes.
const DOOR_TICKS := 100
const DOOR_SHARE := 0.8
const DOOR_MIN := 30
## Warehouse docks (docs/spec-working-doors.md, step 2). A box truck or a
## van trailer bound for a warehouse backs up to one of its dock doors (a
## spot of kind "dock" with "rear": its back bumper against the dock, the
## spots added to the end of the place's list, so saved spot numbers keep
## their meaning), and sits there DOCK_DWELL ticks before it heads off:
## 30 s of play at normal speed (10 ticks a second). Nathan, 2026-10-29,
## asked how long a truck should sit at an open dock: "A" (about 30
## seconds). The load counts as the truck reaches the dock, before it backs
## in, as it did at the curb, so the wait changes no money; the truck is
## busy longer. Rigs that load from the top or the side (hoppers, log and
## ore trucks, tankers, flatbeds) still stop out front. DOCK_GAP: metres
## from the dock face to the parked truck's back bumper (the dock bumpers).
const DOCK_DWELL := 300
const DOCK_KINDS := ["box_truck", "semi", "mail_semi", "delivery_van"]
const DOCK_GAP := 0.35
## A truck leaving a factory's bay waits BAY_WAIT ticks inside while the
## overhead door rolls up (8 s of play), then pulls out. Nathan,
## 2026-10-30, asked whether it should wait for its door ("A. Wait about 8
## seconds"), answered: "A". bay_t is the tick its door started up, kept on
## the truck's record (already saved); a save from before has none and the
## truck leaves at once. The load still counts when it gets where it is
## going; the truck is simply on the road 8 s later.
const BAY_WAIT := 80
## The court's lane runs at least this far in from the site's front.
const DOCK_LANE_MIN := 1.5
## From the end of a curb return to where cars stop: the crosswalk (0.3 to
## 2.7 m past the return, in line with the curb ramps), then 4 ft and the
## 2 ft stop bar (MUTCD 3B.16).
const STOP_PAST_RETURN := 4.5
## The crosswalk's middle, ahead of the stop line (junction_view paints it there).
const CROSSWALK_AHEAD := 3.0
## Curb spaces: a 23 ft parallel stall; kept this far from a driveway's
## centre; how many places along the kerb to try.
const CURB_STALL := 7.0
const CURB_APRON := 5.0
const CURB_TRIES := 25
const PARK_WALK := 250.0  # how far a driver walks from a stall to a full destination
const CURB_SPACE := 6.7   # a parallel parking space at the curb, 22 ft (MUTCD 3B.19)
## How far a road's running speed eases each decision: 5% (with cars on it)
## and 2% (empty) a tenth of a second.
const EASE_BUSY := 1.0 - 0.95 * 0.95 * 0.95
const EASE_QUIET := 1.0 - 0.98 * 0.98 * 0.98
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
## How far back (m) a driver on a green commits to going through.
const GREEN_REACH := 25.0
## Seconds of a car's pull-away counted as room ahead on the far side.
const ROOM_AHEAD_S := 2.0
## Seconds ahead a driver reads a faster car in front pulling away (_idm).
const ANTICIPATE_S := 1.0
## Seconds at the line that count as a full stop (stop signs, all-way
## stops, right on red): drivers stop for about half a second to a second.
const FULL_STOP_S := 0.5
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

## Metres along the new street a long vehicle takes to ease back into its
## own lane after swinging wide round a corner.
const WIDE_BLEND := 15.0
## Metres between a lane's centre and a wide-turning truck's path that a
## waiting car needs: half a truck, half a car and a little room.
const SWEEP_CLEAR := 2.8
## Metres before its stop line a long vehicle claims the corner it will
## swing across, so oncoming drivers wait back for it.
const SWEEP_CALL := 40.0

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
## Comfortable walking pace by age against a grown adult's 1.4 m/s
## (Bohannon 1997; children 6-12 about 1.2 m/s): [up to age, share].
const WALK_PACE := [[4, 0.7], [12, 0.86], [59, 1.0], [69, 0.94], [79, 0.84], [200, 0.72]]
## Metres right of the walk's middle that walkers keep to (a sidewalk is
## 1.5 m wide): see walker_pose.
const WALK_LANES := [0.15, 0.4, 0.62]
## The limits a view can lower (the title screen's town on a weak computer):
## no new trips start past them. The simulation never changes them itself.
var max_cars := MAX_CARS
var max_walkers := MAX_WALKERS
## Share (percent) of short trips walked by people with a car at home:
## about one in eight in a small Midwestern town, half the national quarter
## (NHTS: under-a-mile trips walked, lower outside cities). Nathan,
## 2026-10-25: "the streets were flooded with pedestrians".
const SHORT_WALK_PCT := 12
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
var _cfor := {}   # Vector4i(way, lane, next, wide radius) -> _conn_for's answer
var _conns := {}  # Vector4i(way, lane, next, lane) -> junction path
var _wide := {}   # [way, lane, next, lane, radius] -> a long vehicle's wide turn
var _hold := {}   # way * 8 + lane -> [where its front car waits, the truck swinging wide]
var _conflict := {}
var _next_conn := 1
var _speed := {}  # way -> smoothed share of the limit cars manage there
var _dirty := true
var _next_id := 1
var _tick := 0

# Rebuilt every tick.
var _lanes := {}     # way * 8 + lane -> cars, front first
var _box := {}       # node -> cars crossing it
var _tails := {}     # node -> paths a vehicle's back end is still on, its front out
var _committed := {} # node -> cars about to cross it
var _approach := {}  # node -> [{car, conn, ds}] for the first car in each lane
var _xings := {}     # way -> [[s along the way, rail crossing]] (_find_xings)
var _by_vid := {}    # vehicle id -> its record in `parked`
## The parked vehicles at each place (by at_place), in `parked` order, and
## the parked ones holding a spot somewhere else (a to_place), so a place
## laid out afresh finds who holds its spots without looking through every
## parked car in town (_claim_spots). Kept by _park and _unpark.
var _parked_at := {}  # place ref -> [vehicles]
var _parked_to := {}  # vehicle id -> parked vehicle with a to_place
var _due := {}       # tick -> parked vehicles due to head off then (_due_at)
var _outs := {}      # vehicle id -> [key, path out of its spot] while it waits to pull out
var _due_done := -1  # the last tick _rest took its due vehicles for (-1: look through all)
var _pend := {}      # vehicle id -> parked vehicle waiting for a gap to pull out
var _doored := {}    # vehicle id -> parked vehicle whose garage door is going up (door_t)
var _slow := {}      # ways whose _speed is below 1 (or has cars), kept up to date each tick
var _slow_ok := -1   # the lane version _slow was gathered on
var _groups := {}    # [home, where to] -> pace of who set off from there this step (_pace)
var _group_step := -1
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
var _ep_cache := {}   # Vector2 position -> its road stop (_endpoint), until the roads change
var _ep_rev := -1
var _ep_ver := -1
var _seg_lots := {}   # road piece -> lot ids along it (_aprons)
var _walk_back := {}  # node -> metres from its centre to the middle of its crosswalks
var _walk_arm := {}  # [node, seg] -> the same for one leg, where its corner sets it
var _seg_lots_key := []
var _lot_cells := {}  # 250 m cell -> lot ids whose fronts lie in it (_parking_near)
var _lot_cells_key := []
var _extra := {}      # place ref -> spots added beyond its layout, in order (_add_spot)
## Streets closed to cars (a pedestrian plaza): segment -> who may still
## drive in to deliver: "never", "night" (10 pm to 6 am) or "always".
var closed := {}
var _truck_plan := false  # the route being planned is for a truck (close_segment)
## The town's truck routes law (TownLaws): a truck passing through counts a
## neighborhood street as Balance.LAW_TRUCK_STREET_MULT times its drive.
var truck_routes := false
var _tpen := {}       # way -> extra seconds for a truck under truck_routes
var _tpen_key := []
## Road treatments (RoadTreatments) hand their rules in here: road piece ->
## its lower speed limit (mph), road pieces that are truck routes (no extra
## for trucks under truck_routes), and curbs (seg * 2, +1 the right-hand
## side) with no car parking or no driveway cuts.
var treat_mph := {}
var treat_trucks := {}
## How much of the law's extra a truck route still costs a through truck:
## a preference, not a free road. Free, every through truck in town took
## the factory streets and they jammed at their one link to the county
## road (road treatments, 2026-10-29).
var truck_route_share := TRUCK_ROUTE_SHARE
const TRUCK_ROUTE_SHARE := 0.5
var no_parking := {}
var no_aprons := {}
## The route being planned is for a golf cart (TownLaws golf_carts): roads
## faster than Balance.CART_MAX_MPH count Balance.CART_FAST_MULT times
## their drive, so carts keep to town streets and only cross the highway.
var _cart_plan := false
var _cpen := {}
var _cpen_key := []
var _walk_lines := {} # segment * 2 + side -> sidewalk line
var _rings := {}      # node -> sidewalk ends around it (_corner_ring)
var _marks := []      # crosswalks on the walk just planned: [point, node, way in]
var _xbusy := {}      # node -> [[from step, to step, segment, walker]] on its crosswalks
const _NO_XINGS := []
const _NO_PEND := {}
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
	_step_actuated()
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
	for k in ["at_place", "spot", "pos", "face", "hidden", "pending", "door_t", "door_n"]:
		car.erase(k)
	_doored.erase(car.id)
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
		if not car.get("retire", false) and place(car.get("to_place", "")).is_empty():
			# Where it was going was cleared away on the way: it goes home
			# instead (vehicles never vanish).
			var home := place(str(car.get("base", "")))
			var spot := -1 if home.is_empty() else _reserve(home, car.id, car.len > 6.5, _is_cart(car))
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
	var county: Array = _sim.county_trains.crossings if _sim.county_rail else []
	if rail.crossings.is_empty() and county.is_empty():
		_xings = {}
		return
	var key := [rail.version, version, rail.crossings.size(), _sim.county_trains.version, county.size()]
	if key == _xing_key:
		return
	_xing_key = key
	_xings = {}
	for c in rail.crossings + county:
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
	if car.get("j") != null:
		return _conn_pose(car.j, minf(car.jd + ahead, car.j.len))
	if not car.has("route"):
		# Parked since the caller last looked (a view holding on to it
		# between frames): it stands where it stopped.
		return parked_pose(car) if car.has("pos") else [Vector3.ZERO, Vector3.FORWARD]
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
		# Angled in no more than a driver steers for a lane change (about
		# 20 degrees), even edging over from a standstill.
		pose = [pose[0] + right * lat, (fwd + right * clampf(slide / maxf(car.v, 2.0), -0.36, 0.36)).normalized()]
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


## Green times the player set at a light (Nathan, 2026-10-25: "set one
## direction to be longer than the other one"): node -> {phase index:
## seconds}. Phases follow the junction's road groups, busiest first.
var greens := {}
const GREEN_MIN := 7.0   # MUTCD 4D.26 / ITE: a minimum green of 7 s or so
const GREEN_MAX := 90.0


## Sets how long one phase of a light stays green (0 or less: back to the
## automatic time). Returns false for a junction without lights.
func set_green(node: int, phase: int, seconds: float) -> bool:
	if not junctions.has(node) or junctions[node].control != Rule.SIGNAL:
		return false
	if phase < 0 or phase >= junctions[node].phases.size():
		return false
	if seconds <= 0.0:
		if greens.has(node):
			greens[node].erase(phase)
			if greens[node].is_empty():
				greens.erase(node)
	else:
		if not greens.has(node):
			greens[node] = {}
		greens[node][phase] = clampf(roundf(seconds), GREEN_MIN, GREEN_MAX)
	_rebuild()
	return true


## The player's turn rules at a junction approach, like TM:PE's lane arrows
## and junction restrictions: "node:seg" (the road arriving there) ->
## {no_left: a No Left Turn sign (MUTCD R3-2), no_right: a No Right Turn
## sign (R3-1), lanes: lane-use arrows for each lane, left to right, as
## ARROW_* bits (MUTCD 3B.20), or [] for the game's own}. Kept in a table of
## their own, apart from `overrides`. Saves from before No Right load
## without it.
var lane_rules := {}
const ARROW_L := 1
const ARROW_S := 2
const ARROW_R := 4


static func lane_key(node: int, seg: int) -> String:
	return "%d:%d" % [node, seg]


func lane_rule(node: int, seg: int) -> Dictionary:
	return lane_rules.get(lane_key(node, seg), {})


## Sets the turn rules for road `seg` arriving at junction `node`: No Left
## and No Right Turn signs, and lane arrows (one ARROW_* mask per lane, left
## to right, or [] for the game's own). All off clears the approach. No
## turn signs on a roundabout's ring (see takes_turn_signs).
func set_lane_rule(node: int, seg: int, no_left: bool, lanes: Array, no_right := false) -> bool:
	if not network.nodes.has(node) or network.segments_at(node).size() < 3 \
			or not network.segments_at(node).has(seg):
		return false
	if (no_left or no_right) and not takes_turn_signs(seg):
		return false
	var masks := []
	for m in lanes:
		masks.append(clampi(int(m), 1, ARROW_L | ARROW_S | ARROW_R))
	var key := lane_key(node, seg)
	var rule := {"no_left": no_left, "no_right": no_right, "lanes": masks}
	if not no_left and not no_right and masks.is_empty():
		if not lane_rules.has(key):
			return false
		lane_rules.erase(key)
	else:
		if lane_rules.get(key, {}) == rule:
			return false
		lane_rules[key] = rule
	_rebuild()
	return true


## Whether a road can take No Left or No Right Turn signs: not a
## roundabout's ring (or another one-way loop piece). Its traffic only goes
## one way round, so closing the turn off it into an exit would leave
## everyone on that exit's street, fire trucks too, no way in (reviewer
## 2026-10-29).
func takes_turn_signs(seg: int) -> bool:
	return network.segments.has(seg) and not _is_ring(seg)


## Drops turn rules at junctions that are gone, or lost the road they were
## for, at once rather than at the next rebuild. UndoLog calls it after
## putting roads back: undo hands out junction and road ids again, and a new
## junction mustn't start with an undone one's signs (second reader on the
## turn-ban branch, 2026-10-26).
func prune_lane_rules() -> void:
	for k in lane_rules.keys():
		var n := int(k.get_slice(":", 0))
		if not network.nodes.has(n) or network.segments_at(n).size() < 3 \
				or not network.segments_at(n).has(int(k.get_slice(":", 1))):
			lane_rules.erase(k)


## The arrows each lane of a way into a junction shows now, left to right
## (ARROW_* bits): the player's, or the game's own lanes.
func lane_masks(way: int) -> Array:
	var out := []
	if not ways.has(way):
		return out
	out.resize(ways[way].lanes)
	out.fill(0)
	for wo in _turns.get(way, []):
		var bit := ARROW_S
		match _kind.get(Vector2i(way, wo), Turn.STRAIGHT):
			Turn.LEFT, Turn.UTURN: bit = ARROW_L
			Turn.RIGHT: bit = ARROW_R
		for i in _arrows[way][wo]:
			out[i] |= bit
	return out


func lane_rules_to_dict() -> Dictionary:
	var out := {}
	var keys := lane_rules.keys()
	keys.sort()
	for k in keys:
		out[k] = {"no_left": lane_rules[k].no_left, "no_right": lane_rules[k].no_right,
			"lanes": lane_rules[k].lanes.duplicate()}
	return out


func lane_rules_from_dict(d: Dictionary) -> void:
	lane_rules.clear()
	for k in d:
		var lanes := []
		for m in d[k].get("lanes", []):
			lanes.append(int(m))
		lane_rules[str(k)] = {"no_left": bool(d[k].get("no_left", false)),
			"no_right": bool(d[k].get("no_right", false)), "lanes": lanes}
	_dirty = true


## The green time each phase of a light has now, in seconds.
func greens_at(node: int) -> Array:
	var out := []
	if not junctions.has(node):
		return out
	var start := 0.0
	for ph in junctions[node].phases:
		out.append(ph.g_end - start)
		start = ph.end
	return out


## Where in its cycle a light starts, set by the player to make a green wave
## along a street (node -> seconds). Without one a light starts at a
## spread-out time of its own.
var offsets := {}


func set_offset(node: int, seconds: float) -> bool:
	if not junctions.has(node) or junctions[node].control != Rule.SIGNAL:
		return false
	if seconds < 0.0:
		offsets.erase(node)
	else:
		offsets[node] = snappedf(seconds, 0.1)
	_rebuild()
	return true


## Links light `to` behind light `from` in a green wave: it takes `from`'s
## green times (so both run one cycle) and starts its green just as cars
## leaving `from` on a green arrive at the speed limit `v` (m/s).
func link_wave(from: int, to: int, v: float) -> bool:
	if from == to or not junctions.has(from) or not junctions.has(to):
		return false
	var a: Dictionary = junctions[from]
	var b: Dictionary = junctions[to]
	if a.control != Rule.SIGNAL or b.control != Rule.SIGNAL or a.phases.size() != b.phases.size():
		return false
	var g := greens_at(from)
	greens[to] = {}
	for i in g.size():
		greens[to][i] = float(g[i])
		# A wave is the player's own timing at both ends, so the traffic
		# engineers don't retime one end out of step with the other.
		if not greens.has(from):
			greens[from] = {}
		greens[from][i] = float(g[i])
	var travel: float = Vector2(a.pos.x - b.pos.x, a.pos.z - b.pos.z).length() / maxf(v, 1.0)
	offsets[to] = snappedf(fposmod(a.offset - travel, maxf(a.cycle, 1.0)), 0.1)
	_rebuild()
	return true


## The traffic engineers (stage 4 of docs/spec-traffic-control.md, a
## Traffic Management Center; Nathan, 2026-10-25: "they would fine-tune all
## of that for me"). While the town has one, every car that enters a
## signalled junction is counted by the way it came (detector counts), and
## every RETUNE_EVERY the engineers share each light's green out by demand:
## Webster's rule, green in proportion to each phase's busiest lane, eased
## half way there each time as SCATS-style systems step their splits. The
## counts fade by half at each retiming, so they follow the last few
## periods (a game hour is only six seconds of traffic, under one cycle). A
## quiet light (night) goes back to its standard timing. Lights the player
## timed by hand are left alone; with no center, these timings go and the
## player's own (or the standard ones) come back.
var engineers := false
## node -> {way id: cars counted, fading}. Saved.
var demand := {}
## The engineers' green times: node -> {phase index: seconds}. Saved.
var tuned := {}
## When the engineers last changed a light: node -> game tick. Saved.
var retimed := {}
## Game ticks between retimings (CitySim): three game hours, 18 s of traffic.
const RETUNE_EVERY := 180
## Fewer cars than this counted at a light and it runs standard timing.
const TUNE_MIN_CARS := 6


## One retiming (CitySim, every RETUNE_EVERY). `tick` is the game tick,
## for the light's panel.
func retune(tick: int) -> void:
	var nodes := demand.keys()
	for n in tuned:
		if not n in nodes:
			nodes.append(n)
	nodes.sort()
	for n in nodes:
		# The player's own lights (timed, started at a set time, or in a
		# green wave) and smart lights (sensors set their own greens) are
		# left alone.
		if not junctions.has(n) or junctions[n].control != Rule.SIGNAL or greens.has(n) \
				or offsets.has(n) or actuated.has(n):
			if tuned.erase(n):
				_retime(n)
			continue
		var j: Dictionary = junctions[n]
		if tuned.has(n) and tuned[n].size() != j.phases.size():
			tuned.erase(n)  # its roads changed: start again from the counts
		# Cars still waiting count too, so a way kept short of green shows
		# its queue, not only the few it let through.
		var seen: Dictionary = demand.get(n, {}).duplicate()
		for ph in j.phases:
			for wi in ph.ways:
				for lane in int(ways[wi].lanes):
					for car in _lanes.get(int(wi) * 8 + lane, []):
						if not car.get("commit", false):
							seen[wi] = int(seen.get(wi, 0)) + 1
		var total := 0
		var y := []
		for ph in j.phases:
			var crit := 0.0
			for wi in ph.ways:
				total += int(seen.get(wi, 0))
				crit = maxf(crit, float(seen.get(wi, 0)) / maxi(int(ways[wi].lanes), 1))
			y.append(crit)
		var had := tuned.has(n)
		if total < TUNE_MIN_CARS:
			tuned.erase(n)
		else:
			var sum_y := 0.0
			var sum_g := 0.0
			for i in j.phases.size():
				sum_y += y[i]
				sum_g += float(j.phases[i].g0)
			var now := greens_at(n)
			var out := {}
			for i in j.phases.size():
				var want := sum_g * float(y[i]) / maxf(sum_y, 0.001)
				var g := clampf(roundf(0.5 * float(now[i]) + 0.5 * want), GREEN_MIN, GREEN_MAX)
				out[i] = g
			tuned[n] = out
		if had or tuned.has(n):
			if _retime(n):
				retimed[n] = tick
	for n in retimed.keys():
		if not tuned.has(n):
			retimed.erase(n)
	for n in demand.keys():
		var seen: Dictionary = demand[n]
		for wi in seen.keys():
			seen[wi] = int(seen[wi]) / 2
			if seen[wi] == 0:
				seen.erase(wi)
		if seen.is_empty():
			demand.erase(n)


## The engineers leave: every light they timed goes back.
func engineers_gone() -> void:
	engineers = false
	var nodes := tuned.keys()
	tuned.clear()
	demand.clear()
	retimed.clear()
	for n in nodes:
		_retime(n)


## Puts a light's green times (the player's, else the engineers', else the
## standard ones) into its phases in place, without rebuilding the roads.
## True if anything changed.
func _retime(n: int) -> bool:
	if not junctions.has(n) or junctions[n].control != Rule.SIGNAL:
		return false
	var j: Dictionary = junctions[n]
	var set_at: Dictionary = greens.get(n, tuned.get(n, {}))
	# The same sums as _build_control, so a light retimed here and one
	# rebuilt in a loaded copy agree to the last bit.
	var t := 0.0
	var changed := false
	for i in j.phases.size():
		var ph: Dictionary = j.phases[i]
		var start := 0.0 if i == 0 else float(j.phases[i - 1].end)
		var yellow: float = ph.yl
		var green: float = float(set_at.get(i, ph.g0))
		if absf(green - (ph.g_end - start)) > 0.01:
			changed = true
		ph.g_end = t + green
		ph.y_end = t + green + yellow
		ph.end = t + green + yellow + 1.5
		t += green + yellow + 1.5
	j.cycle = maxf(t, 1.0)
	j.offset = fposmod(float(offsets[n]) if offsets.has(n) else n * 37.0, j.cycle)
	return changed


func engineers_to_dict() -> Dictionary:
	var out := {"on": engineers, "demand": {}, "tuned": {}, "retimed": {}}
	for n in demand:
		var d := {}
		for wi in demand[n]:
			d[str(wi)] = demand[n][wi]
		out.demand[str(n)] = d
	for n in tuned:
		var d := {}
		for ph in tuned[n]:
			d[str(ph)] = tuned[n][ph]
		out.tuned[str(n)] = d
	for n in retimed:
		out.retimed[str(n)] = retimed[n]
	return out


func engineers_from_dict(d: Dictionary) -> void:
	demand.clear()
	tuned.clear()
	retimed.clear()
	engineers = bool(d.get("on", false))
	for k in d.get("demand", {}):
		var m := {}
		for wi in d.demand[k]:
			m[int(wi)] = int(d.demand[k][wi])
		demand[int(k)] = m
	for k in d.get("tuned", {}):
		var m := {}
		for ph in d.tuned[k]:
			m[int(ph)] = float(d.tuned[k][ph])
		tuned[int(k)] = m
	for k in d.get("retimed", {}):
		retimed[int(k)] = int(d.retimed[k])
	_dirty = true


## Smart lights (actuated signals, stage 3 of docs/spec-traffic-control.md):
## sensors in the road. A light holds a green while cars keep coming (up to
## ACT_MAX_G), changes once another way has someone waiting (after
## ACT_MIN_G), and skips ways with no one there. node -> {ph, stage, t};
## stage is 0 green, 1 yellow, 2 all-red. Saved, so copies stay in step.
var actuated := {}
const ACT_MIN_G := 7.0
const ACT_MAX_G := 50.0
const ACT_GAP_M := 45.0   # a car this close to the line still wants the green
const ACT_CALL_M := 60.0  # a car this close on another way calls for it


func set_actuated(node: int, on: bool) -> bool:
	if not junctions.has(node) or junctions[node].control != Rule.SIGNAL:
		return false
	if on:
		if not actuated.has(node):
			actuated[node] = {"ph": 0, "stage": 0, "t": 0.0}
	else:
		actuated.erase(node)
	return true


func _waiting_on(node: int, ph: int, reach: float) -> bool:
	var ways: Dictionary = junctions[node].phases[ph].ways
	for ap in _approach.get(node, []):
		if ways.has(int(ap.conn.wi)) and float(ap.ds) < reach:
			return true
	return false


## One step of every smart light.
func _step_actuated() -> void:
	for n in actuated.keys():
		if not junctions.has(n) or junctions[n].control != Rule.SIGNAL or junctions[n].phases.is_empty():
			actuated.erase(n)
			continue
		var j: Dictionary = junctions[n]
		var a: Dictionary = actuated[n]
		var count: int = j.phases.size()
		a.ph = int(a.ph) % count
		a.t = float(a.t) + DT
		var ph: Dictionary = j.phases[a.ph]
		var start := 0.0 if a.ph == 0 else float(j.phases[a.ph - 1].end)
		var yellow: float = ph.y_end - ph.g_end
		match int(a.stage):
			0:
				var others := false
				for k in range(1, count):
					if _waiting_on(n, (a.ph + k) % count, ACT_CALL_M):
						others = true
						break
				var mine := _waiting_on(n, a.ph, ACT_GAP_M)
				if others and a.t >= ACT_MIN_G and (not mine or a.t >= ACT_MAX_G):
					a.stage = 1
					a.t = 0.0
			1:
				if a.t >= yellow:
					a.stage = 2
					a.t = 0.0
			_:
				if a.t >= 1.5:
					# On to the next way with someone waiting (or the next one).
					var nxt: int = (a.ph + 1) % count
					for k in range(1, count + 1):
						if _waiting_on(n, (a.ph + k) % count, ACT_CALL_M):
							nxt = (a.ph + k) % count
							break
					a.ph = nxt
					a.stage = 0
					a.t = 0.0


func actuated_to_dict() -> Dictionary:
	var out := {}
	for n in actuated:
		out[str(n)] = {"ph": int(actuated[n].ph), "stage": int(actuated[n].stage), "t": snappedf(float(actuated[n].t), 0.01)}
	return out


func actuated_from_dict(d: Dictionary) -> void:
	actuated.clear()
	for k in d:
		actuated[int(k)] = {"ph": int(d[k].ph), "stage": int(d[k].stage), "t": float(d[k].t)}


func offsets_to_dict() -> Dictionary:
	var out := {}
	for n in offsets:
		out[str(n)] = offsets[n]
	return out


func offsets_from_dict(d: Dictionary) -> void:
	offsets.clear()
	for k in d:
		offsets[int(k)] = float(d[k])
	_dirty = true


func greens_to_dict() -> Dictionary:
	var out := {}
	for n in greens:
		var d := {}
		for ph in greens[n]:
			d[str(ph)] = greens[n][ph]
		out[str(n)] = d
	return out


func greens_from_dict(d: Dictionary) -> void:
	greens.clear()
	for k in d:
		var g := {}
		for ph in d[k]:
			g[int(ph)] = float(d[k][ph])
		greens[int(k)] = g
	_dirty = true


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
	if actuated.has(node) and not j.phases.is_empty():
		var a: Dictionary = actuated[node]
		if not j.phases[int(a.ph) % j.phases.size()].ways.has(way):
			return Light.RED
		return [Light.GREEN, Light.YELLOW, Light.RED][clampi(int(a.stage), 0, 2)]
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


## A vehicle's trip on the roads for the route view (Cities: Skylines'
## "show routes"): {came: the way it came from where it set off, ahead: the
## rest of its route}, each [way, from d, to d] runs. A driving car keeps
## only the route ahead, so where it came from is planned again from its
## start, the way it would have driven. `came` is left out when `ahead_only`.
func trip_runs(car: Dictionary, ahead_only := false) -> Dictionary:
	var out := {"came": [], "ahead": []}
	if car.has("flow_in"):
		var ins: Array = car.flow_in
		for i in ins.size():
			var wid: int = ins[i][1]
			if not ways.has(wid):
				continue
			var run := [wid, float(car.d) if i == 0 else 0.0,
				float(car.end_d) if i == ins.size() - 1 else float(ways[wid].len)]
			var now := i + 1 >= ins.size() or int(ins[i + 1][0]) > _tick
			(out.ahead if now or not out.ahead.is_empty() else out.came).append(run)
		return out
	var route: Array = car.get("route", [])
	var leg: int = car.get("leg", 0)
	if leg >= route.size() or not ways.has(route[leg]):
		return out
	var d: float = car.d
	if car.j != null and int(car.j.get("wo", -1)) == int(route[leg]):
		d = 0.0
	for i in range(leg, route.size()):
		var wid: int = route[i]
		if not ways.has(wid):
			break
		out.ahead.append([wid, d if i == leg else 0.0,
			float(car.end_d) if i == route.size() - 1 else float(ways[wid].len)])
	if ahead_only or _dirty:
		return out  # a view never rebuilds the roads between ticks
	var start = car.get("from_stop")
	var from_ref: String = car.get("from_ref", "")
	if from_ref != "" and from_ref != "edge" and place(from_ref).get("stop") is Dictionary:
		start = place(from_ref).stop
	if not start is Dictionary or not start.has("seg"):
		return out
	var w: Dictionary = ways[route[leg]]
	var fwd: bool = w.fwd
	var here := {"seg": w.seg, "at_frac": d / w.len if fwd else 1.0 - d / w.len, "side": 1 if fwd else -1}
	var back := _route(start, here)
	if back.is_empty():
		return out
	var r: Array = back.route
	for i in r.size():
		out.came.append([r[i], float(back.d) if i == 0 else 0.0,
			float(back.end_d) if i == r.size() - 1 else float(ways[r[i]].len)])
	return out


## Points down the middle of a way's lanes from `d0` to `d1` metres along.
func way_line(wid: int, d0: float, d1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ways.has(wid):
		return out
	var w: Dictionary = ways[wid]
	var mid: float = (w.offs[0] + w.offs[w.lanes - 1]) * 0.5
	d0 = clampf(d0, 0.0, w.len)
	d1 = clampf(d1, d0, w.len)
	var at := [d0]
	for c in w.cum:
		if c > d0 + 0.5 and c < d1 - 0.5:
			at.append(c)
	at.append(d1)
	for d in at:
		var f := _way_dir(w, d)
		out.append(_poly_point(w.pts, w.cum, d) + Vector3(-f.z, 0.0, f.x) * mid)
	return out


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


## A road piece's speed limit, m/s, with its treatment's.
func seg_limit(seg: int, type: int) -> float:
	var v := limit(type)
	if treat_mph.has(seg):
		v = minf(v, float(treat_mph[seg]) * RoadStyle.MPH)
	return v


## A road treatment's rules for one road piece (RoadTreatments.push):
## `mph` 0 for its own limit, `truck` a truck route, and the sides (-1, 1)
## with no car parking and with no driveway cuts. A new limit is put on its
## ways at once, as a rebuild would.
func set_treatment(seg: int, mph: int, truck: bool, park_off: Array, aprons_off: Array) -> void:
	var was: int = int(treat_mph.get(seg, 0))
	if mph > 0:
		treat_mph[seg] = mph
	else:
		treat_mph.erase(seg)
	if truck != treat_trucks.has(seg):
		if truck:
			treat_trucks[seg] = true
		else:
			treat_trucks.erase(seg)
		_tpen_key = []
	for side in [0, 1]:
		var k: int = seg * 2 + side
		var s := 1 if side == 1 else -1
		if s in park_off:
			no_parking[k] = true
		else:
			no_parking.erase(k)
		if s in aprons_off:
			no_aprons[k] = true
		else:
			no_aprons.erase(k)
	if was == mph or not network.segments.has(seg):
		return
	var c := network.curve_of(seg)
	var r := RoadNetwork.min_radius(c[0], c[1], c[2])
	var curve_v := INF if r > 400.0 else RoadStyle.safe_speed_mph(r) * RoadStyle.MPH
	var any := false
	for wid in [seg * 2, seg * 2 + 1]:
		if ways.has(wid):
			ways[wid].vmax = maxf(minf(seg_limit(seg, ways[wid].type), curve_v), 4.0)
			any = true
	if any:
		_wcost.clear()  # worked out again, every way as after a rebuild
		_tpen_key = []  # the law's extra for trucks and carts is per second
		_cpen_key = []


## Rules for road pieces that are gone (removed, cut in two, undone).
func forget_gone_treatments() -> void:
	for seg in treat_mph.keys():
		if not network.segments.has(int(seg)):
			treat_mph.erase(seg)
	for seg in treat_trucks.keys():
		if not network.segments.has(int(seg)):
			treat_trucks.erase(seg)
			_tpen_key = []
	for d in [no_parking, no_aprons]:
		for k in d.keys():
			if not network.segments.has(int(k) >> 1):
				d.erase(k)


func clear_treatments() -> void:
	for seg in treat_mph.keys():
		set_treatment(seg, 0, false, [], [])
	treat_trucks.clear()
	no_parking.clear()
	no_aprons.clear()
	_tpen_key = []


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
	_outs.clear()
	_waiting.clear()
	parked.clear()
	_by_vid.clear()
	_parked_at.clear()
	_parked_to.clear()
	_due.clear()
	_due_done = -1
	_pend.clear()
	_doored.clear()
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
		return [c.wi, c.li, c.wo, c.lo, c.wide] if c.has("wide") else [c.wi, c.li, c.wo, c.lo]
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
		if k.size() > 4:
			return _wide_connector(k[0], k[1], k[2], k[3], k[4])
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
	_wide.clear()
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
				"vmax": maxf(minf(seg_limit(id, s.type), curve_v), 4.0), "s0": 0.0, "s1": cum[cum.size() - 1]}
			if not _out.has(ways[wid].from):
				_out[ways[wid].from] = []
			_out[ways[wid].from].append(wid)
			if not _in.has(ways[wid].to):
				_in[ways[wid].to] = []
			_in[ways[wid].to].append(wid)
	var node_ids := at_node.keys()
	node_ids.sort()
	var setback := {}
	_walk_back.clear()
	_walk_arm.clear()
	var arm_back := {}  # [node, seg] -> metres, where a shaped corner sets each leg's stop line
	for n in node_ids:
		var segs: Array = at_node[n]
		var sb := 0.0
		if segs.size() >= 3:
			sb = _stop_back(segs)
			if sb > _stop_back_plain(segs):
				# Stop at the painted stop line, which follows each leg's own
				# curb return (skewed and Y legs reach further out).
				var plan := Junction.plan_node(network, n)
				for id in segs:
					var back := JunctionMarks.stop_back(plan, id)
					if back > 0.0:
						arm_back[[n, id]] = back
						_walk_arm[[n, id]] = back - CROSSWALK_AHEAD
		elif segs.size() == 2:
			var s1: Dictionary = network.segments[segs[0]]
			var s2: Dictionary = network.segments[segs[1]]
			if s1.type != s2.type or network.is_oneway(segs[0]) != network.is_oneway(segs[1]):
				sb = 5.0
			elif _bend(n, segs) > deg_to_rad(35.0):
				# A street turning a corner: traffic rounds the curb rather
				# than pivoting on the spot, and a truck has room to swing.
				sb = _stop_back_plain(segs)
		setback[n] = sb
		# People cross at the crosswalk, just ahead of the stop bar.
		_walk_back[n] = sb - CROSSWALK_AHEAD if sb > CROSSWALK_AHEAD + 1.0 and segs.size() >= 3 \
			and sb > _stop_back_plain(segs) else sb
	for wid in ways:
		var w: Dictionary = ways[wid]
		w.s0 = minf(arm_back.get([w.from, w.seg], setback[w.from]), w.len * 0.4)
		w.s1 = maxf(w.len - arm_back.get([w.to, w.seg], setback[w.to]), w.len * 0.6)
	for n in overrides.keys():
		if not at_node.has(n) or at_node[n].size() < 3:
			overrides.erase(n)
	for k in lane_rules.keys():
		var n := int(k.get_slice(":", 0))
		if not at_node.has(n) or at_node[n].size() < 3 or not at_node[n].has(int(k.get_slice(":", 1))):
			lane_rules.erase(k)
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
		var kinds := []
		for o in outs:
			var kind := Turn.STRAIGHT
			if o[1] == uturn:
				kind = Turn.UTURN
			elif o[0] > deg_to_rad(35.0):
				kind = Turn.RIGHT
			elif o[0] < deg_to_rad(-35.0):
				kind = Turn.LEFT
			kinds.append(kind)
		var rule: Dictionary = lane_rules.get(lane_key(n, w.seg), {})
		var banned := []
		# A ring keeps every turn, even under a sign from an older save.
		if takes_turn_signs(w.seg):
			if rule.get("no_left", false):
				banned.append(Turn.LEFT)
			if rule.get("no_right", false):
				banned.append(Turn.RIGHT)
		var open_way := false
		for j in outs.size():
			# A turn into a car-free street doesn't count: cars can't take
			# it (the turn-ban branch's second reader, 2026-10-26).
			if not kinds[j] in banned and may_enter(ways[outs[j][1]].seg, false):
				open_way = true
		if not banned.is_empty() and open_way:
			# No Left and No Right Turn signs: those turns go, unless they
			# are the only ways on.
			for j in range(outs.size() - 1, -1, -1):
				if kinds[j] in banned:
					outs.remove_at(j)
					kinds.remove_at(j)
		var m := outs.size()
		var nl: int = w.lanes
		var auto := []
		for j in m:
			# Lanes share the turns left to right, like auto lane arrows.
			var lanes := []
			for i in nl:
				if float(i + 1) / nl > float(j) / m + 0.0001 and float(i) / nl < float(j + 1) / m - 0.0001:
					lanes.append(i)
			auto.append(lanes)
		var marked := _marked_lanes(rule.get("lanes", []), nl, kinds, auto)
		_turns[wi] = []
		_arrows[wi] = {}
		for j in m:
			if marked[j].is_empty():
				continue  # no lane is marked for it: that turn is closed
			_kind[Vector2i(wi, outs[j][1])] = kinds[j]
			_turns[wi].append(outs[j][1])
			_arrows[wi][outs[j][1]] = marked[j]


## The lanes for each way out under the player's lane arrows (`masks`, one
## per lane, left to right): a lane takes the turns its arrows show. With
## no arrows, or arrows for another number of lanes, or arrows that would
## close every way out, the game's own lanes (`auto`). A lane whose arrows
## match no way out here keeps the game's turns for it, so no lane leads
## nowhere.
static func _marked_lanes(masks: Array, nl: int, kinds: Array, auto: Array) -> Array:
	if masks.size() != nl or nl == 0:
		return auto
	var out := []
	var used := {}
	for j in kinds.size():
		var bit := ARROW_S
		match kinds[j]:
			Turn.LEFT, Turn.UTURN: bit = ARROW_L
			Turn.RIGHT: bit = ARROW_R
		var lanes := []
		for i in nl:
			if int(masks[i]) & bit:
				lanes.append(i)
				used[i] = true
		out.append(lanes)
	if used.is_empty():
		return auto
	for i in nl:
		if not used.has(i):
			for j in kinds.size():
				if auto[j].has(i) and not out[j].has(i):
					out[j].append(i)
					out[j].sort()
	return out


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
			var set_at: Dictionary = greens.get(n, tuned.get(n, {}))
			if set_at.has(j.phases.size()):
				green = float(set_at[j.phases.size()])
			j.phases.append({"ways": ph_ways, "g_end": t + green, "y_end": t + green + yellow,
				"end": t + green + yellow + 1.5, "g0": 16.0 + 6.0 * g[0], "yl": yellow})
			t += green + yellow + 1.5
		j.cycle = maxf(t, 1.0)
		j.offset = fposmod(float(offsets[n]) if offsets.has(n) else n * 37.0, j.cycle)


## How far before a junction's centre traffic stops, at the stop bar. Town
## streets meet in rounded curb returns (Junction.RETURN_RADIUS); the
## crosswalk runs just past the end of the return, and the stop bar is 4 ft
## behind it, so turning cars sweep a real curve: about 9 m at the centre
## line turning right on a local street corner and 11 m turning left, more
## on avenues, against AASHTO's 6.4 m for a passenger car. Country roads, highways and
## roundabouts have no returns: traffic stops at the edge of the cross road.
func _stop_back(segs: Array) -> float:
	var hw := 0.0
	var curbed := true
	var r := 0.0
	for id in segs:
		var type: int = network.segments[id].type
		var spec: Dictionary = RoadStyle.TYPES[type]
		hw = maxf(hw, RoadStyle.half_width(type))
		if spec.oneway or spec.get("rural", false) or RoadStyle.is_ring(type) or network.is_oneway(id):
			curbed = false
		r = maxf(r, Junction.RETURN_RADIUS.get(RoadStyle.group(type), 6.0))
	if not curbed:
		return _stop_back_plain(segs)
	return hw + r + STOP_PAST_RETURN


## How sharply the road turns at a node where two segments meet (0 when
## one runs straight on into the other).
func _bend(n: int, segs: Array) -> float:
	var outs := []
	for id in segs:
		var cv: Array = network.curve_of(id)
		var at_a: bool = network.segments[id].a == n
		var d: Vector3 = (cv[1] - cv[0]) if at_a else (cv[1] - cv[2])
		if Vector2(d.x, d.z).length() < 0.01:
			d = (cv[2] - cv[0]) if at_a else (cv[0] - cv[2])
		outs.append(Vector2(d.x, d.z).normalized())
	return PI - absf(outs[0].angle_to(outs[1]))


func _stop_back_plain(segs: Array) -> float:
	var hw := 0.0
	for id in segs:
		hw = maxf(hw, RoadStyle.half_width(network.segments[id].type))
	return hw + 1.5


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


## Long vehicles can't turn right inside a town corner: AASHTO's design
## turning radius is 42 ft for a single-unit truck or bus (SU-30) and 45 ft
## for a tractor-trailer (WB-67), against about 15 ft for a town curb. So
## they pull well into the junction, swing out across the far lane of the
## street they turn into and ease back into their own lane (FHWA truck
## turning templates). Metres, for the path of the vehicle's front.
static func wide_radius(vlen: float) -> float:
	if vlen >= 15.0:
		return 13.0
	if vlen >= 9.0:
		return 12.0
	return 0.0


## The wide right turn a long vehicle takes, or the usual path where the
## corner is roomy enough. It carries "sweep": for each lane coming into
## the junction that the swing crosses short of its stop line, where cars
## there must hold back while the truck turns.
func _wide_connector(wi: int, li: int, wo: int, lo: int, r: float) -> Dictionary:
	var c0 := _connector(wi, li, wo, lo)
	if c0.turn != Turn.RIGHT or r <= 0.0:
		return c0
	var key := [wi, li, wo, lo, int(r)]
	if _wide.has(key):
		return _wide[key]
	var a: Dictionary = ways[wi]
	var b: Dictionary = ways[wo]
	var da: Vector3 = c0.d0
	var db: Vector3 = c0.d1
	var p0: Vector3 = c0.pts[0]
	var p2: Vector3 = c0.pts[c0.pts.size() - 1]
	var ang := atan2(da.x * db.z - da.z * db.x, da.dot(db))
	var th := absf(ang)
	var half := tan(th * 0.5)
	var out := Vector3(da.x, 0.0, da.z) - db * da.dot(db)  # along the old heading, across the new road
	if half < 0.05 or out.length() < 0.2:
		_wide[key] = c0
		return c0
	out = out.normalized()
	# One lane over: the next lane, or on a two-way street the oncoming one.
	var lat := 3.6
	if b.lanes > 1:
		lat = absf(float(b.offs[1]) - float(b.offs[0]))
	elif absf(float(b.offs[lo])) > 0.5:
		lat = absf(float(b.offs[lo])) * 2.0
	# Where the old lane line meets the new one, shifted a lane over.
	var shifted := p2 + out * lat
	var den := da.x * db.z - da.z * db.x
	var t := ((shifted.x - p0.x) * db.z - (shifted.z - p0.z) * db.x) / den
	var t_nat := ((p2.x - p0.x) * db.z - (p2.z - p0.z) * db.x) / den
	if t_nat / half >= r or t <= 0.0:
		_wide[key] = c0  # a roomy corner: the usual turn will do
		return c0
	var rr := minf(r, t / half)  # as wide as one lane over allows
	var tl := rr * half
	var corner := p0 + da * t
	var a0 := corner - da * tl
	var a1 := corner + db * tl
	var d_a1: float = b.s0 + (a1 - p2).dot(db)
	var d_end := minf(d_a1 + WIDE_BLEND, b.s1 - 1.0)
	if d_end - d_a1 < 4.0:
		_wide[key] = c0  # too short a street to straighten out on
		return c0
	var pts := PackedVector3Array([p0])
	if a0.distance_to(p0) > 0.5:
		pts.append(a0)
	var nrm := Vector3(-da.z, 0.0, da.x) * signf(ang)
	var centre := a0 + nrm * rr
	var rel := a0 - centre
	for i in range(1, 11):
		var phi := ang * i / 10.0
		pts.append(centre + Vector3(rel.x * cos(phi) - rel.z * sin(phi), 0.0, rel.x * sin(phi) + rel.z * cos(phi)))
	var f0 := _way_dir(b, d_a1)
	var side := signf(out.dot(Vector3(-f0.z, 0.0, f0.x)))
	for i in range(1, 7):
		var d := lerpf(d_a1, d_end, i / 6.0)
		var f := _way_dir(b, d)
		pts.append(_lane_point(b, lo, d) + Vector3(-f.z, 0.0, f.x) * side * lat * (1.0 - smoothstep(0.0, 1.0, i / 6.0)))
	for i in pts.size():
		pts[i].y = lerpf(p0.y, p2.y, clampf(float(i) / (pts.size() - 1), 0.0, 1.0))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var c := {"id": _next_conn, "node": a.to, "wi": wi, "li": li, "wo": wo, "lo": lo, "wide": int(r),
		"turn": Turn.RIGHT, "pts": pts, "cum": cum, "len": cum[cum.size() - 1], "vt": c0.vt,
		"exit_d": d_end, "ctrl": corner, "d0": da, "d1": _way_dir(b, d_end), "rev": 0.0,
		"sweep": _sweep(a.to, wi, pts)}
	_next_conn += 1
	_wide[key] = c
	return c


## Lanes into node `n` (other than `wi`) that a path crosses before their
## stop line: way * 8 + lane -> where a car there must stop short of it.
func _sweep(n: int, wi: int, pts: PackedVector3Array) -> Dictionary:
	var out := {}
	for wk in _in.get(n, []):
		if wk == wi:
			continue
		var w: Dictionary = ways[wk]
		for l in w.lanes:
			var hold := INF
			var d: float = w.s1 - 0.5
			while d > maxf(w.s1 - 30.0, 0.0):
				var p := _lane_point(w, l, d)
				var near := false
				for i in pts.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z),
						Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z))
					if q.distance_to(Vector2(p.x, p.z)) < SWEEP_CLEAR:
						near = true
						break
				if near:
					hold = d - 1.0
				d -= 0.5
			if hold < INF:
				out[wk * 8 + l] = maxf(hold, 0.0)
	return out


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
	# Costs so far, the way each came from and the estimates, by way id in
	# packed arrays (INF, -1 and -1 when not reached yet): the same numbers
	# the search kept in dictionaries, read faster. The arrays are kept
	# between searches (packed arrays are shared, not copied, so these
	# names write into them), and only the entries the last search reached
	# are set back, not every way in town.
	var n := _way_count()
	if _pl_dist.size() != n:
		_pl_dist.resize(n)
		_pl_dist.fill(INF)
		_pl_prev.resize(n)
		_pl_prev.fill(-1)
		_pl_h.resize(n)
		_pl_h.fill(-1.0)
		_pl_seen.clear()
	else:
		for i in _pl_seen:
			_pl_dist[i] = INF
			_pl_prev[i] = -1
			_pl_h[i] = -1.0
		_pl_seen.clear()
	var dist := _pl_dist
	var prev := _pl_prev
	# A*: the estimate is the straight line from the end of a way to the
	# nearest target at the fastest limit in town, which no real route
	# beats, so the route found is still the fastest.
	var goals := PackedVector2Array()
	for t in targets:
		if ways.has(t):
			var p0: Vector3 = ways[t].pts[0]
			goals.append(Vector2(p0.x, p0.z))
	var inv_v := 1.0 / _vtop
	var hcache := _pl_h
	# A binary heap of (cost + estimate, way) in two packed arrays, kept
	# inline: ties go to the lower way id, so every copy picks the same route.
	var hg := PackedFloat64Array()
	var hu := PackedInt32Array()
	for s in starts:
		var w: Dictionary = ways[s[0]]
		var g: float = maxf(w.len - s[1], 0.0) / w.vmax + (s[2] if s.size() > 2 else 0.0)
		if g < dist[s[0]]:
			if dist[s[0]] == INF:
				_pl_seen.append(s[0])
			dist[s[0]] = g
			_hpush(hg, hu, g + _h_at(s[0], goals, inv_v, hcache), s[0])
	var end := -1
	var end_prev := -1
	var first := lane >= 0
	var none := PackedFloat64Array()
	var tpen: Dictionary = _truck_pen() if _truck_plan and truck_routes else ({} if not _cart_plan else _cart_pen())
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
			if not tpen.is_empty():
				ng += tpen.get(nx, 0.0)
			if ng < dist[nx]:
				if dist[nx] == INF:
					_pl_seen.append(nx)
				dist[nx] = ng
				prev[nx] = u
				_hpush(hg, hu, ng + _h_at(nx, goals, inv_v, hcache), nx)
		first = false
	if best_route.is_empty() and end != -1:
		var route := [end]
		var x := end_prev
		var guard := 0
		while guard < 10000:
			route.push_front(x)
			if prev[x] == -1:
				break
			x = prev[x]
			guard += 1
		return route
	return best_route


## The extra a golf cart pays on each way faster than it should be on.
func _cart_pen() -> Dictionary:
	if _cpen_key != [version, ways.size()]:
		_cpen_key = [version, ways.size()]
		_cpen.clear()
		for wid in ways:
			var seg: int = int(wid) >> 1
			if network.segments.has(seg) and int(RoadStyle.TYPES[network.segments[seg].type].get("mph", 25)) > Balance.CART_MAX_MPH:
				var w: Dictionary = ways[wid]
				_cpen[wid] = w.len / w.vmax * (Balance.CART_FAST_MULT - 1.0)
	return _cpen


static func _is_cart(car: Dictionary) -> bool:
	return str(car.get("kind", "")) == "golf_cart"


## The extra a truck passing through pays on each neighborhood street way
## (truck_routes), kept until the ways are rebuilt.
func _truck_pen() -> Dictionary:
	if _tpen_key != [version, ways.size()]:
		_tpen_key = [version, ways.size()]
		_tpen.clear()
		for wid in ways:
			var seg: int = int(wid) >> 1
			if network.segments.has(seg) and int(network.segments[seg].type) in TownLaws.LOCAL_STREETS:
				var w: Dictionary = ways[wid]
				var extra := Balance.LAW_TRUCK_STREET_MULT - 1.0
				if treat_trucks.has(seg):
					extra *= truck_route_share
				_tpen[wid] = w.len / w.vmax * extra
	return _tpen


## One more than the highest way id, kept until the ways are rebuilt.
func _way_count() -> int:
	if _way_n_key != [version, ways.size()]:
		_way_n_key = [version, ways.size()]
		_way_n = 0
		for id in ways:
			_way_n = maxi(_way_n, int(id) + 1)
		for id in _turns:
			_way_n = maxi(_way_n, int(id) + 1)
			for nx in _turns[id]:
				_way_n = maxi(_way_n, int(nx) + 1)
	return _way_n


var _way_n := 0
var _way_n_key := []
## _plan's search arrays, by way id (see there), and the ids it reached.
var _pl_dist := PackedFloat64Array()
var _pl_prev := PackedInt32Array()
var _pl_h := PackedFloat64Array()
var _pl_seen := PackedInt32Array()


## _h_est with its answers kept by way id in a packed array (-1: not yet).
func _h_at(u: int, goals: PackedVector2Array, inv_v: float, hcache: PackedFloat64Array) -> float:
	var h: float = hcache[u]
	if h >= 0.0:
		return h
	var e: Vector2 = _wend.get(u, Vector2.ZERO)
	var best := INF
	for q in goals:
		best = minf(best, e.distance_to(q))
	h = 0.0 if best == INF else best * inv_v
	hcache[u] = h
	return h


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
	_cart_plan = _is_cart(car)
	var route := _plan([[wid, car.d]], targets, lane, _side_pen(car.goal.seg, car.goal.get("side", 1)))
	_truck_plan = false
	_cart_plan = false
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
	var near := RoadIndex.segment_near(network, at, 25.0, 3.0)
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
	# Each lets go of its old space's number first, as the numbers are given
	# out again: a car parked in curb space 12 kept its 12 once a newcomer
	# was given the new 12, so two held one space, and a loaded copy (which
	# works out who holds what from the saved vehicles) gave it to the other
	# one, and the copies parked their next shoppers apart (2026-10-27).
	var kerb := _let_go_of_extras()
	_extra.clear()
	_places.clear()
	var kept := []
	var pulled_in := {}  # car id -> true, for the cars that finished parking
	for car in cars:
		var wid: int = car.route[car.leg]
		if car.j != null and car.j.wo < 0:
			pulled_in[car.id] = true
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
			var near := RoadIndex.segment_near(network, car.dest, 60.0)
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
		# One that parked has arrived. (Parking clears its turn in, so it
		# can't be told by that: it was reported as failed too, 2026-10-27.)
		if not kept.has(car) and not pulled_in.has(car.id):
			_drop_hold(car)
			_report(car, failed)
	cars = kept
	# Vehicles on a lot that was cleared away go with it.
	for car in parked.duplicate():
		if place(car.at_place).is_empty():
			_unpark(car)
			_report(car, failed)
	# Trucks backed up to a warehouse's dock keep their own dock, laid out
	# again, before anything else is given a space there.
	for car in parked:
		if not kerb.has(car.id) or not kerb[car.id].get("rear", false):
			continue
		var pl := place(car.at_place)
		for i in pl.get("spots", []).size():
			if pl.taken[i] == -1 and pl.spots[i].get("rear", false) and pl.spots[i].pos.distance_to(kerb[car.id].pos) < 0.5:
				pl.taken[i] = car.id
				car.spot = i
				if car.get("pending", false):
					car.from_spot = i
				break
	# Cars parked at a curb that was rebuilt move to the new curb.
	for car in parked:
		var pl := place(car.at_place)
		var ok: bool = car.spot >= 0 and car.spot < pl.spots.size()
		if ok:
			var s: Dictionary = pl.spots[car.spot]
			ok = _nose(s, car.len).distance_to(car.pos) < 0.5
		if ok:
			continue
		# It gives up the space it was counted in (a garage its house laid
		# out afresh around it), or it held two and a loaded copy held one.
		var held: bool = car.spot >= 0 and car.spot < pl.taken.size() and pl.taken[car.spot] == car.id
		_release(pl.ref, car.spot, car.id)
		var at := _reserve(pl, car.id, car.len > 6.5, _is_cart(car))
		if at < 0:
			at = _new_curb(pl, pl.stop, car.id, car.len)
		if at < 0 and kerb.has(car.id):
			# No kerb to move to: it stays in the space it's in, kept for it.
			at = _add_spot(pl, kerb[car.id], car.id)
		if at < 0 and held:
			# Nowhere to move to at all: it stays put and keeps the space it
			# is counted in, as a loaded copy (which only sees its number)
			# keeps it for it. Freed, it was free here and held there: a box
			# truck in a dock laid out again as a stall, on a street with no
			# kerb (2026-10-27).
			pl.taken[car.spot] = car.id
		if at >= 0:
			var s: Dictionary = pl.spots[at]
			car.spot = at
			car.pos = _nose(s, car.len)
			car.face = s.face
			car.hidden = s.hidden
			if car.get("pending", false):
				car.from_spot = at  # it pulls out of the space it's in now
			if car.has("door_t") and not _behind_door(pl, at):
				_shut_door(car)  # no door in front of its new space
			parked_version += 1
	# Vehicles about to pull out plan again on the new roads.
	for car in parked:
		if car.get("pending", false) and not _replan_start(car, place(car.at_place).get("stop", {})):
			_cancel(car)
	for car in _waiting.duplicate():
		if not _replan_start(car, car.get("start_stop", {})):
			_waiting.erase(car)
			_drop_hold(car)
			_report(car, failed)


## A vehicle that gives up its trip lets go of the space held for it at the
## other end and forgets its number, so a place built afresh before it is
## gone doesn't count it again. A loaded copy, without the vehicle, holds
## nothing there: cars that couldn't find their way after a road was
## bulldozed kept their stalls at the lot they were bound for, live, until
## the next road change (2026-10-27).
func _drop_hold(car: Dictionary) -> void:
	_release(car.get("to_place", ""), car.get("to_spot", -1), car.id)
	if car.has("to_spot"):
		car.to_spot = -1


## Before the spots added beyond the places' layouts are cleared: every
## vehicle heading for one forgets it (it picks again when it plans or
## arrives), and every one parked in one is left without a number, to be
## given a new space. Returns vehicle id -> the space it is parked in, for
## one that finds no new space to stay put in.
func _let_go_of_extras() -> Dictionary:
	var first := {}  # place ref -> the number of its first added spot
	for ref in _extra:
		first[ref] = place(ref).get("spots", []).size() - _extra[ref].size()
	var kerb := {}
	for car in cars + _waiting + flowing + parked:
		if first.has(car.get("to_place", "")) and car.get("to_spot", -1) >= int(first[car.to_place]):
			car.to_spot = -1
		if first.has(car.get("at_place", "")) and car.get("spot", -1) >= int(first[car.at_place]):
			var spots: Array = place(car.at_place).get("spots", [])
			if car.spot < spots.size():
				kerb[car.id] = spots[car.spot]
				car.spot = -1
	return kerb


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
	_cart_plan = _is_cart(car)
	var trip := _route(from_stop, car.to_stop)
	_truck_plan = false
	_cart_plan = false
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
	car.erase("bay_t")  # (no wait left over for its next trip)
	_shut_door(car)
	_pend.erase(car.id)
	for k in ["route", "leg", "d", "end_d", "goal", "dest", "park", "home", "to_place", "to_spot", "lane",
			"to_stop", "after"]:
		car.erase(k)
	_parked_to.erase(car.id)
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
	if cars.size() >= max_cars or sim.stats.population == 0:
		return
	var hour: int = int(sim.sky_hour())  # what the sky shows (SkyClock)
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
	if cars.size() >= max_cars:
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
	# that just finished the last leg of its round) takes the job; not a
	# truck still being unloaded at a warehouse dock (DOCK_DWELL).
	var car := {}
	for p in parked:
		if p.at_place == rf and p.owner == -1 and not p.get("pending", false) and p.get("driver", -1) == -1 \
				and (p.kind == kind or any_kind and p.get("job", "") == purpose) \
				and not (p.has("dock_t") and int(p.until) > _tick):
			car = p
			break
	if car.is_empty():
		# A new one, based where vehicles are kept: a lot or yard with room
		# for them, else wherever this trip ends. A warehouse keeps its own
		# trucks: they come back to it empty and wait at its curb for the
		# next load (based at the shop they delivered to, each stayed there
		# for good and the warehouse made a new one for every load).
		var base := rf
		var pl := place(rf)
		if pl.lot.is_empty() and pl.drive.is_empty() and rt != "edge" and not rf.begins_with("wh:"):
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


## About how many ticks a trip between two dispatch endpoints takes on empty
## roads at the limit (INF with no route), for callers deciding whether a
## trip is worth sending. Live speeds are left out, so every copy of the
## town gets the same answer.
func drive_ticks(from: Dictionary, to: Dictionary, truck := false) -> float:
	if _dirty:
		_rebuild()
	var rf := _register(from)
	var rt := _register(to)
	if rf == "" or rt == "":
		return INF
	var a: Dictionary = _endpoint(from) if rf == "edge" else place(rf).get("stop", {})
	var b: Dictionary = _endpoint(to) if rt == "edge" else place(rt).get("stop", {})
	if a.is_empty() or b.is_empty():
		return INF
	_truck_plan = truck
	var r := _route(a, b)
	_truck_plan = false
	if r.is_empty():
		return INF
	var secs := 0.0
	for wid in r.route:
		secs += ways[wid].len / ways[wid].vmax
	return secs / DT


## Every trip that's under way: driving, waiting to pull out, or just
## arrived or given up (handled by its caller next tick).
func trip_ids() -> Array:
	var out := []
	for c in cars + _waiting + flowing:
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
			var hour: int = _sim.clock().hour if _sim != null else 12  # a rule on the sim clock
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
	if _sites.has(ref) and not place(ref).is_empty():
		return ref
	var site := e.duplicate()
	site.ref = ref
	_sites[ref] = site
	_places.erase(ref)
	return ref if not place(ref).is_empty() else ""


## A place given as {"ref", "pos": [x, z]}, as a lot-like stop on the nearest road.
func _endpoint(e: Dictionary) -> Dictionary:
	# The same few places (region links, depots) are asked for again and
	# again: the answer depends only on the roads, so it's kept until they
	# change.
	if _ep_rev != network.revision or _ep_ver != version:
		_ep_cache.clear()
		_ep_rev = network.revision
		_ep_ver = version
	var at := Vector2(float(e.pos[0]), float(e.pos[1]))
	if not _ep_cache.has(at):
		_ep_cache[at] = _endpoint_x(at)
	var out: Dictionary = _ep_cache[at].duplicate()
	if not out.is_empty():
		out.ref = e.get("ref", "")
	return out


func _endpoint_x(at: Vector2) -> Dictionary:
	var e := {"ref": ""}
	var pos := Vector3(at.x, 0.0, at.y)
	var near := RoadIndex.segment_near(network, pos, 80.0)
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
	# place(), not the cache: a loaded copy builds it on first use, and must
	# pull out the same way as the city it was saved from.
	var from_ref: String = car.get("from_place", "")
	var from_pl: Dictionary = place(from_ref) if from_ref != "" else {}
	if not from_pl.is_empty() and car.get("from_spot", -1) >= 0 and car.from_spot < from_pl.spots.size():
		# The way out only changes with the roads or the place, so a car
		# waiting for a gap works it out once (not saved: it's rebuilt the same).
		var key := [version, from_pl.get("seed", 0), from_ref, car.from_spot, w.id, car.lane, car.d]
		var kept: Array = _outs.get(car.id, [])
		if not kept.is_empty() and kept[0] == key:
			out = kept[1]
		else:
			out = _out_path(car, from_pl, car.from_spot, w, car.lane, car.d)
			if _outs.size() > 4000:
				_outs.clear()  # (cars that left town while waiting)
			_outs[car.id] = [key, out]
		exit_d = out.exit_d
	elif exit_d <= car.d + 1.0 and last:
		return false  # next door: walk
	# Nor while another car is backing out of or turning into the same lot:
	# drivers wait for the one already moving in the aisle. Out of a home's
	# drive or garage, the second car waits for the first to back out (two
	# cars of one household pulled out at once, through each other,
	# 2026-10-27). (Not docks and bays: buses and trucks leave their bays and
	# depots in turn. Nor the curb, where each car pulls out of its own space.)
	var kind: String = from_pl.spots[car.from_spot].kind if not from_pl.is_empty() \
			and car.get("from_spot", -1) >= 0 and car.from_spot < from_pl.spots.size() else ""
	if from_ref != "" and kind in ["stall", "drive", "garage"]:
		for other in cars:
			if other.j == null or int(other.j.get("node", 0)) != -1 or other.id == car.id:
				continue
			var leaving: bool = int(other.j.wi) == -1 and other.get("from_place", "") == from_ref
			var arriving: bool = kind == "stall" and int(other.j.wo) == -1 and other.get("to_place", "") == from_ref
			if leaving or arriving:
				return false
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
	_outs.erase(car.id)
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
	elif ref.begins_with("svc:"):
		pl = _park_place(ref)
		# Any other service is a stop on the street out front (crews and
		# deliveries while it goes up), as for any site.
		if pl.is_empty() and _sites.has(ref):
			pl = _site_place(_sites[ref])
	elif _sites.has(ref):
		pl = _site_place(_sites[ref])
	if pl.is_empty():
		return {}
	for e in _extra.get(ref, []):
		pl.spots.append(e)
		pl.taken.append(-1)
	_places[ref] = pl
	if ref.begins_with("wh:") and not pl.spots.any(func(s): return s.get("rear", false)):
		_add_docks(pl)
	_claim_spots(pl)
	return pl


## The place a ref stands for if it is already worked out and still holds
## for what stands there now, else {}; never works one out or claims its
## spots (for views that only read, like StateView). Treat it as read-only.
func cached_place(ref: String) -> Dictionary:
	var pl: Dictionary = _places.get(ref, {})
	if pl.is_empty() or pl.has("seed") and _place_seed(ref) != pl.seed:
		return {}
	return pl


## A warehouse's dock doors as spots trucks back up to, one per door its
## drawing has (Warehouses.dock_xs: plain math from its spec). Added like a
## curb space out front (_add_spot): on the end of its list and saved with
## it, so an older save's spot numbers mean what they did, and a loaded copy
## has them in the same order. Each spot is the back bumper's place against
## the dock, facing the road, with the court's frame for the way in
## (_dock_way): its origin (the site's front middle), across and inward
## unit vectors, the gate's x, the curb's z and the half width to keep in.
func _add_docks(pl: Dictionary) -> void:
	if _sim == null:
		return
	var w = _sim.warehouses.buildings.get(int(str(pl.ref).substr(3).get_slice("@", 0)))
	if w == null or Warehouses.is_store(w):
		return
	var b := Basis.looking_at(w.dir, Vector3.UP)
	var bx := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var bz := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var o := Vector3(w.pos.x, 0.0, w.pos.z)
	var zb := float(Warehouses.spec(w).court) - DOCK_GAP
	var to_curb := Warehouses.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	# One lane across the court for every truck, clear of the longest rig
	# that docks here (its nose and a turn's radius out from the dock), so
	# trucks running along it or pulling off a dock never pass through one
	# backed in. Rigs longer than that stop out front.
	var lmax := 0.0
	for k in DOCK_KINDS:
		var vl := float(VehicleTypes.spec(k).len)
		if zb - vl - _dock_r(vl) >= DOCK_LANE_MIN:
			lmax = maxf(lmax, vl)
	if lmax <= 0.0:
		return  # a court too short for any of them: trucks stop out front
	var xs := Warehouses.dock_xs(w)
	for i in xs.size():
		var x: float = xs[i]
		_add_spot(pl, {"pos": o + bx * x + bz * zb, "face": -bz, "kind": "dock", "hidden": false,
			"local": Vector2(x, zb), "rear": true, "door": i, "o": o, "bx": bx, "bz": bz,
			"gx": Warehouses.gate_x(w), "zc": -to_curb, "half": Warehouses.site_width(w) * 0.5 - 1.5,
			"zl": zb - lmax - _dock_r(lmax), "lmax": lmax})


## The radius a truck `vlen` long backs round into a dock.
static func _dock_r(vlen: float) -> float:
	return maxf(6.0, vlen * 0.3)


## A dock spot's court point at local (x, z), flat.
static func _dock_pt(s: Dictionary, x: float, z: float) -> Vector3:
	return s.o + s.bx * x + s.bz * z


## Where a vehicle parked in spot `s` has its front bumper: half its length
## out from the spot's middle, or its whole length out from a dock's
## (backed in, its back bumper at the dock).
static func _nose(s: Dictionary, vlen: float) -> Vector3:
	return s.pos + s.face * (vlen if s.get("rear", false) else vlen * 0.5)


## The way a truck `vlen` long backs into dock spot `s`, in two moves as a
## driver does it in a truck court (an "alley dock"): in at the gate, a
## turn to run along the docks on the court's lane (zl), a stop past its
## door with the cab straight, then back round a turn of radius r into
## the door. {"approach": world
## points from the gate to where it stops, "r": the turn's radius}, or {}
## when the court is too short for it (a 53 ft trailer at a small
## warehouse) or no side has the room: it stops out front instead.
static func _dock_way(s: Dictionary, vlen: float) -> Dictionary:
	if vlen > float(s.get("lmax", 0.0)) + 0.01:
		return {}
	var r := _dock_r(vlen)
	var x: float = s.local.x
	var z_line: float = s.zl
	var gx: float = s.gx
	var a := vlen + r
	var first := 1.0 if x >= gx else -1.0
	for sd in [first, -first]:
		var px: float = x + float(sd) * a
		if absf(px) > float(s.half) or (px - gx) * sd < r:
			continue
		var pts := [_dock_pt(s, gx, float(s.zc)), _dock_pt(s, gx, z_line)]
		var mx: float = px - float(sd) * vlen
		if (mx - gx) * sd > 2.0:
			pts.append(_dock_pt(s, mx, z_line))
		pts.append(_dock_pt(s, px, z_line))
		return {"approach": pts, "r": r}
	return {}


## A vehicle of `kind` that backs up to a dock door: a box or van body,
## loaded from the back.
static func _docks(kind: String) -> bool:
	return kind in DOCK_KINDS


## The kind _reserve is given for `car` carrying `cargo`: its own when it
## brings a load (it may back up to a warehouse dock), else none (an empty
## truck coming home, or one just made, waits at the curb or in a lot).
static func _dock_kind(car: Dictionary, cargo) -> String:
	return str(car.get("kind", "")) if VehicleTypes.is_loaded(cargo) else ""


## A copy of `d` with its keys as plain strings in sorted order: a lot in
## the running town has some keys as StringNames, in the order they were
## added, and one loaded from a save has them sorted, so a car that carries
## its stop must carry the same bytes either way (copies stay in step).
static func _canon(d: Dictionary) -> Dictionary:
	var keys := []
	for k in d:
		keys.append(str(k))
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out


func _place_seed(ref: String) -> int:
	if _sim != null and ref.begins_with("svc:"):
		# A parking lot moved, re-striped or gone is laid out afresh.
		var s = _sim.services.buildings.get(int(ref.substr(4)))
		return 0 if s == null else hash([s.kind, s.pos, s.dir, Services.size_of(s), s.get("angled", false)])
	if _sim == null or not ref.begins_with("lot:"):
		return 0
	var b = _sim.buildings.get(ref.substr(4))
	# The layout depends on the storeys too (a house that grows a storey
	# lays its drive out again), so a copy loaded after it grew agrees; and
	# a corner store grown into a retail store has a lot of its own.
	if b == null:
		return 0
	var sig := [int(b.seed), int(b.zone), BuildingTypes.storeys(b), BuildingTypes.type_of(b)]
	if sig[3] == "shop":
		sig.append(mini(int(b.get("level", 0)), 1))
	return hash(sig)


func _lot_place(ref: String) -> Dictionary:
	if _sim == null or not _sim.lots.has(ref.substr(4)):
		return {}
	var lot: Dictionary = _sim.lots[ref.substr(4)]
	var b = _sim.buildings.get(ref.substr(4))
	var lay := SiteLayout.empty_lot() if b == null else SiteLayout.for_lot(_sim, ref.substr(4))
	var spots := []
	for s in lay.spots:
		spots.append({"pos": SiteLayout.world(lot, s.pos), "face": SiteLayout.world_dir(lot, s.face),
			"kind": s.kind, "hidden": s.kind == "garage" or s.kind == "bay", "local": s.pos,
			"aisle": float(s.get("aisle", lay.aisle_z))})
	var stop := _canon(lot)
	stop["ref"] = ref
	return {"ref": ref, "stop": stop, "lot": lot, "lay": lay, "spots": spots, "taken": _fill(spots.size()),
		"door": SiteLayout.world(lot, lay.door), "seed": _place_seed(ref), "drive": PackedVector3Array(),
		"zone": -1 if b == null else int(b.zone)}


## A place reached from the road by its own lane, like a farmyard or a mine:
## trucks drive up the lane to the dock at its end.
## A parking lot or garage the player built (Services.PARKING): every
## stall of its ParkingLots layout, reached by its one driveway.
func _park_place(ref: String) -> Dictionary:
	var b = _sim.services.buildings.get(int(ref.substr(4))) if _sim != null else null
	if b == null or not int(b.kind) in Services.PARKING:
		return {}
	var lay := Services.parking_layout(b)
	var xf := Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos)
	var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var gate: Vector2 = lay.gate
	var road_end := xf * Vector3(gate.x, 0.0, gate.y - to_curb)
	var stop := _endpoint({"ref": ref, "pos": [road_end.x, road_end.z]})
	if stop.is_empty():
		return {}
	var hidden: bool = int(lay.levels) > 1
	# People on foot leave by the walk beside the driveway: across the front
	# drive, through the planted strip and out to the public sidewalk.
	var wx: float = lay.walk_x
	var zc: float = lay.front_z
	var door := xf * Vector3(wx, 0.0, gate.y + ParkingLots.EDGE)
	var at_walk := _walk_stop(xf * Vector3(wx, 0.0, gate.y - to_curb * 0.5))
	var walk_out := PackedVector3Array([door, xf * Vector3(wx, 0.0, gate.y)])
	if not at_walk.is_empty():
		walk_out.append(at_walk.walk_pt)
	var spots := []
	for s in lay.spots:
		var via := []
		for q in s.via:
			via.append(xf * Vector3(q.x, 0.0, q.y))
		var out := []
		for q in s.out:
			out.append(xf * Vector3(q.x, 0.0, q.y))
		# From behind the car out into the aisle, up it to the front drive and
		# along to the walk.
		var behind: Vector2 = s.pos - s.face * (ParkingLots.STALL_L * 0.5 + 1.0)
		var walk := PackedVector3Array([xf * Vector3(behind.x, 0.0, behind.y), xf * Vector3(behind.x, 0.0, zc),
			xf * Vector3(wx, 0.0, zc)])
		spots.append({"pos": xf * Vector3(s.pos.x, 0.0, s.pos.y), "face": (xf.basis * Vector3(s.face.x, 0.0,
			s.face.y)).normalized(), "kind": "stall", "hidden": hidden, "local": s.pos, "ada": s.ada,
			"via": via, "out": out, "back_pad": s.back_pad, "walk": walk})
	var pl := {"ref": ref, "stop": stop, "lot": {}, "lay": {}, "spots": spots, "taken": _fill(spots.size()),
		"door": door, "drive": PackedVector3Array([xf * Vector3(gate.x, 0.0,
		gate.y + 1.0), road_end]), "zone": -1, "seed": _place_seed(ref), "parking": true}
	if not at_walk.is_empty():
		pl.walk_lot = at_walk
		pl.walk_out = walk_out
	return pl


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
	var pl := {"ref": ref, "stop": stop, "lot": {}, "lay": {}, "spots": spots, "taken": _fill(spots.size()),
		"door": door, "drive": drive, "zone": -1}
	# A site people walk to (a school's front doors): out its front walk to
	# the sidewalk.
	if e.get("on_foot", false):
		var at_walk := _walk_stop(door)
		if not at_walk.is_empty():
			pl.foot_lot = at_walk
			pl.foot_out = PackedVector3Array([door, at_walk.walk_pt])
	return pl


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
	var line := _curb_line(stop)
	for k in (n if not line.is_empty() else 0):
		out.append(_curb_at(line, line[1] + (k - (n - 1) * 0.5) * CURB_STALL))
	return out


## The kerb a stop's curb spaces line: [way, where the stop is along it,
## facing, offset from the centre line]. [] if there's no room to park.
func _curb_line(stop: Dictionary) -> Array:
	var wid: int = stop.seg * 2 + 1
	if not ways.has(wid):
		wid = stop.seg * 2
	if not ways.has(wid):
		return []
	var w: Dictionary = ways[wid]
	if w.s1 - w.s0 < 24.0:
		return []  # too short a piece of road to park along
	var mid: float = _frac(stop) * w.len if w.fwd else w.len - _frac(stop) * w.len
	var face := 1.0 if (stop.side > 0) == w.fwd else -1.0
	return [w, mid, face, RoadStyle.half_width(w.type) - 1.1]


func _curb_at(line: Array, d: float) -> Dictionary:
	var w: Dictionary = line[0]
	# Clear of the junctions at both ends, with room to pull away.
	d = clampf(d, w.s0 + 12.0, w.s1 - 12.0)
	var dir := _way_dir(w, d) * float(line[2])
	var right := Vector3(-dir.z, 0.0, dir.x)
	var p := _poly_point(w.pts, w.cum, d) + right * float(line[3])
	return {"pos": p, "face": dir, "kind": "curb", "hidden": false, "local": Vector2.ZERO}


## A new curb space for a full place, saved with it: the nearest one to the
## stop along the kerb that's clear of the curb spaces already marked there
## (a 23 ft parallel stall, as painted downtown) and of driveway aprons (no
## parking across a driveway: UVC 11-1003), tried every half stall out to
## about 40 m each way. With none free that close the vehicle double-parks
## out front, as delivery trucks do. -1 if the road has no kerb to park on.
## The space is only somewhere to stop: no new vehicle is based in it, as it
## may face away from where that vehicle's trips go (a truck there would
## have to drive on to find room to turn round).
## `held` is the list _curb_taken gives, for a caller placing many at once
## (it is added to); with none, the curb spaces are looked over afresh.
func _new_curb(pl: Dictionary, stop: Dictionary, vid := -1, vlen := 4.8, held = null) -> int:
	if vlen <= 6.5 and _no_car_parking(stop) and str(pl.get("ref", "")).begins_with("lot:"):
		# A factory side (RoadTreatments): NO PARKING (MUTCD R7-1), so a car
		# bound for a building parks across the street and its driver walks
		# over. Trucks may still stand there to load, as the sign allows,
		# and police and other crews at work stop where they must.
		stop = stop.duplicate()
		stop.side = -int(stop.get("side", 1))
		if _no_car_parking(stop):
			return -1
	var line := _curb_line(stop)
	if line.is_empty():
		return -1
	var w: Dictionary = line[0]
	var tries := mini(int((w.s1 - w.s0 - 24.0) / (CURB_STALL * 0.5)) * 2 + 1, CURB_TRIES)
	# Only the spaces near enough to be in the way (the tries reach about
	# tries / 4 stalls each way; a semi's gap is under 30 m).
	var mid_pos: Vector3 = _curb_at(line, float(line[1])).pos
	var reach := tries * CURB_STALL * 0.25 + 40.0
	var taken := []
	for q in (_curb_taken() if held == null else held):
		if mid_pos.distance_squared_to(q[0]) < reach * reach:
			taken.append(q)
	# A main street side has no driveway cuts: the curb is all stalls.
	var aprons := [] if no_aprons.has(int(stop.seg) * 2 + (1 if int(stop.get("side", 1)) > 0 else 0)) else _aprons(stop)
	for k in tries:
		var off := ceilf(k * 0.5) * (1.0 if k % 2 == 1 else -1.0) * CURB_STALL * 0.5
		var c := _curb_at(line, float(line[1]) + off)
		var ok := true
		for q in taken:
			# A truck takes as much kerb as it is long (a box truck two
			# spaces, a semi three or four), as a loading zone is marked.
			var gap := maxf(CURB_STALL - 0.5, (vlen + float(q[1])) * 0.5 + 1.0)
			if c.pos.distance_squared_to(q[0]) < gap * gap:
				ok = false
				break
		for q in aprons if ok else []:
			if c.pos.distance_squared_to(q) < CURB_APRON * CURB_APRON:
				ok = false
				break
		if ok:
			c.stop_only = true
			c.len = vlen
			if held != null:
				held.append([c.pos, vlen])
			return _add_spot(pl, c, vid)
	var last := _curb_at(line, float(line[1]))
	last.stop_only = true
	last.len = vlen
	if held != null:
		held.append([last.pos, vlen])
	return _add_spot(pl, last, vid)


func _no_car_parking(stop: Dictionary) -> bool:
	return not no_parking.is_empty() and stop.has("seg") \
		and no_parking.has(int(stop.seg) * 2 + (1 if int(stop.get("side", 1)) > 0 else 0))


## Shared by a run of arrive_now calls: the curb spaces taken (added to as
## cars park) and the lots found full, so each isn't looked over again.
func arrive_batch() -> Dictionary:
	return {"curbs": _curb_taken(), "full": {}}


## Curb spaces with a vehicle in them or on its way, [position, length]
## (a free one marked earlier is just kerb again).
func _curb_taken() -> Array:
	var taken := []
	for ref in _extra:
		var other := place(ref)
		var list: Array = _extra[ref]
		var first: int = other.get("spots", []).size() - list.size()
		for k in list.size():
			if list[k].get("kind", "") == "curb" and (first < 0 or other.taken[first + k] != -1):
				taken.append([list[k].pos, float(list[k].get("len", 4.8))])
	return taken


## Where the driveways of the built lots on a stop's side of its street meet
## the road.
func _aprons(stop: Dictionary) -> Array:
	var out := []
	if _sim == null:
		return out
	# Lots by the road piece they front, kept until lots are planned again.
	var key := [_sim.zones.revision, network.revision, _sim.lots.size()]
	if key != _seg_lots_key:
		_seg_lots_key = key
		_seg_lots.clear()
		for id in _sim.lots:
			var sg: int = _sim.lots[id].get("seg", -1)
			if not _seg_lots.has(sg):
				_seg_lots[sg] = []
			_seg_lots[sg].append(id)
	for id in _seg_lots.get(stop.seg, []):
		var lot: Dictionary = _sim.lots.get(id, {})
		if lot.get("seg", -1) != stop.seg or lot.get("side", 0) != stop.side or not _sim.buildings.has(id):
			continue
		var lp := place("lot:" + id)
		if not lp.is_empty() and lp.lay.has("cut_x"):
			out.append(SiteLayout.world(lot, Vector2(lp.lay.cut_x, -float(lot.get("to_curb", 0.0)))))
	return out


## A house lot with somewhere to park (a golf cart's home).
func _home_lot(pl: Dictionary) -> bool:
	if _sim == null or pl.spots.is_empty() or not str(pl.ref).begins_with("lot:"):
		return false
	var b = _sim.buildings.get(str(pl.ref).substr(4))
	return b != null and int(b.zone) == ZoneMap.Zone.RESIDENTIAL


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


## Files a vehicle just parked (or found parked on a load) for _claim_spots.
func _file_parked(car: Dictionary) -> void:
	if car.has("door_t"):
		_doored[car.id] = car
	var at: String = car.at_place
	if not _parked_at.has(at):
		_parked_at[at] = []
	_parked_at[at].append(car)
	if car.has("to_place"):
		_parked_to[car.id] = car


func _claim_spots(pl: Dictionary) -> void:
	for car in _parked_at.get(pl.ref, []):
		if car.at_place == pl.ref and car.spot >= 0 and car.spot < pl.taken.size():
			pl.taken[car.spot] = car.id
	# Where vehicles are headed, whether driving already or parked waiting
	# for a gap to pull out with a spot held at the other end (the parked
	# ones in `parked` order, as if looking through them all).
	var holding := []
	for vid in _parked_to:
		var car: Dictionary = _parked_to[vid]
		if car.get("to_place", "") == pl.ref:
			holding.append(car)
	if holding.size() > 1:
		holding.sort_custom(func(a, b): return _pseq[a.id] < _pseq[b.id])
	for list in [holding, cars, _waiting, flowing]:
		for car in list:
			if car.get("to_place", "") == pl.ref and car.get("to_spot", -1) >= 0 and car.to_spot < pl.taken.size():
				pl.taken[car.to_spot] = car.id


## A free spot for a vehicle: trucks take docks and bays first, cars their
## garage or driveway, then a stall. -1 if the place is full.
## `vkind` (the vehicle's): only a box or van body backs up to a warehouse
## dock (DOCK_KINDS), and only where its court has room for it.
func _reserve(pl: Dictionary, vid: int, truck: bool, cart := false, vkind := "") -> int:
	# A truck never squeezes into a car's 9 x 18 ft stall or a driveway: it
	# backs into a dock or bay, or stands at the kerb out front as delivery
	# trucks do.
	var order := ["dock", "bay", "curb"] if truck else (["cart", "drive", "stall", "curb"] if cart else ["garage", "drive", "stall", "curb"])
	if cart and _home_lot(pl) and pl.spots.all(func(s): return s.kind != "cart"):
		# A golf cart's corner of the garage or carport (TownLaws golf_carts),
		# added last when a cart first needs it so the other spots keep their
		# numbers. No car parks there.
		var c: Dictionary = pl.spots[0].duplicate()
		c.kind = "cart"
		c.hidden = true
		pl.spots.append(c)
		pl.taken.append(-1)
	for kind in order:
		for i in pl.spots.size():
			if pl.taken[i] == -1 and pl.spots[i].kind == kind and not pl.spots[i].get("stop_only", false):
				if pl.spots[i].get("rear", false) and (not _docks(vkind) \
						or _dock_way(pl.spots[i], float(VehicleTypes.spec(vkind).len)).is_empty()):
					continue
				pl.taken[i] = vid
				return i
	return -1


func _release(ref: String, i: int, vid: int) -> void:
	if not _places.has(ref):
		return
	var pl: Dictionary = _places[ref]
	if i >= 0 and i < pl.taken.size() and pl.taken[i] == vid:
		pl.taken[i] = -1


## Lots by the 250 m cell their front lies in, kept until lots are planned
## again, so a search reads the nine cells round a door, not every lot.
func _index_lots() -> void:
	var key := [_sim.zones.revision, network.revision, _sim.lots.size()]
	if key == _lot_cells_key:
		return
	_lot_cells_key = key
	_lot_cells.clear()
	for id in _sim.lots:
		var c := _cell(_sim.lots[id].front)
		if not _lot_cells.has(c):
			_lot_cells[c] = []
		_lot_cells[c].append(id)


## How short of parking the businesses within a walk of `at` are at their
## busiest: {"places": how many, "stalls": how many stalls short}. Peak
## demand after ITE Parking Generation (5th ed.): a shop or diner fills
## about 1.3 stalls for each worker (staff plus customers, about 3 per
## 1,000 sq ft of a small store), an office or plant about 0.9 per worker
## (ITE 710 and 110). Against that go its own stalls and the curb along its
## front (a 22 ft parallel space each, MUTCD 3B.19). Homes park in their
## own driveways and at the curb.
## Reads the layouts only (no places are made), so the tool can ask freely.
func parking_need(at: Vector3) -> Dictionary:
	var out := {"places": 0, "stalls": 0}
	if _sim == null:
		return out
	_index_lots()
	var c := _cell(at)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for id in _lot_cells.get(c + Vector2i(dx, dz), []):
				var b = _sim.buildings.get(id)
				if b == null or int(b.zone) == ZoneMap.Zone.RESIDENTIAL or not _sim.lots.has(id):
					continue
				var lot: Dictionary = _sim.lots[id]
				if lot.front.distance_to(at) >= PARK_WALK:
					continue
				var rate := 1.3 if int(b.zone) == ZoneMap.Zone.COMMERCIAL else 0.9
				var need := ceili(float(b.get("cap", 0)) * rate)
				var own := int(float(lot.get("width", 0.0)) / CURB_SPACE)
				for sp in SiteLayout.for_building(int(b.zone), int(b.seed), lot, BuildingTypes.storeys(b),
						BuildingTypes.type_of(b), int(b.get("level", 0)), _sim.network, int(b.get("added_from", 0))).spots:
					if sp.kind == "stall":
						own += 1
				if need > own:
					out.places += 1
					out.stalls += need - own
	return out


## Where a car parks when its own destination is full: the nearest lot with
## a free stall within a short walk, like CS2 drivers looking for parking.
## `full` (for a batch of arrivals) skips places found full earlier in it
## and notes the ones found full now.
func _parking_near(pl: Dictionary, vid: int, full = null) -> Array:
	if _sim == null:
		return []
	_index_lots()
	# Nearest first, ties by name, as a sorted walk over every lot would.
	var near := []
	var at := _cell(pl.door)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for id in _lot_cells.get(at + Vector2i(dx, dz), []):
				if not _sim.buildings.has(id) or _sim.buildings[id].zone == ZoneMap.Zone.RESIDENTIAL:
					continue
				var d: float = _sim.lots[id].front.distance_to(pl.door)
				if d < PARK_WALK:
					near.append([d, "lot:" + id])
	# The town's own lots and garages, once they're built.
	for sid in _sim.services.buildings:
		var b: Dictionary = _sim.services.buildings[sid]
		if not int(b.kind) in Services.PARKING or not _sim.construction.is_done("svc:%d" % sid, _sim.tick_count):
			continue
		var d: float = (b.pos + b.dir * Services.size_of(b).y * 0.5).distance_to(pl.door)
		if d < PARK_WALK:
			near.append([d, "svc:%d" % sid])
	# The town's public lots first: a shop's own lot is for its customers
	# ("customer parking only"), so drivers try those only when there's no
	# public stall within the walk. Then nearest first, ties by name.
	near.sort_custom(func(a, b): return _park_before(a, b))
	var placard := has_placard(vid)
	for n in near:
		if full != null and full.has(n[1]):
			continue
		var other := place(n[1])
		if other.is_empty() or other.ref == pl.ref or closed.has(int(other.stop.get("seg", -1))):
			continue
		var any_ada := false
		for i in other.spots.size():
			if other.taken[i] == -1 and other.spots[i].kind == "stall":
				if placard or not other.spots[i].get("ada", false):
					other.taken[i] = vid
					return [other.ref, i]
				any_ada = true
		if full != null and not any_ada:
			full[n[1]] = true
	return []


static func _park_before(a: Array, b: Array) -> bool:
	var pa: bool = str(a[1]).begins_with("svc:")
	var pb: bool = str(b[1]).begins_with("svc:")
	if pa != pb:
		return pa
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


## True for the drivers with a disability placard, who may use accessible
## stalls: about one in sixteen (state DMV counts run 5 to 8% of drivers).
static func has_placard(vid: int) -> bool:
	return vid % 16 == 0


static func _cell(p) -> Vector2i:
	return Vector2i(floori(p.x / PARK_WALK), floori((p.z if p is Vector3 else p.y) / PARK_WALK))


## A new vehicle at rest in a place (a household car in its driveway, a
## truck in its depot). Returns its id, or -1 if there's no room there.
func new_vehicle(kind: String, at_ref: String, owner: int, owner_place := "") -> int:
	var pl := place(at_ref)
	if pl.is_empty():
		return -1
	var spot := _reserve(pl, _next_id, VehicleTypes.spec(kind).len > 6.5, kind == "golf_cart")
	if spot < 0:
		return -1
	var car := _make_vehicle(kind, owner, owner_place if owner_place != "" else at_ref)
	_park(car, pl, spot)
	return car.id


## Takes a vehicle out of the town for good: it was sold, or its owner left.
func retire_vehicle(vid: int) -> void:
	# (_by_vid is every parked vehicle, by id.)
	if _by_vid.has(vid):
		var car: Dictionary = _by_vid[vid]
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
	if tick <= _due_done:
		_due_done = -1  # filed in the past: the next tick looks through every bucket
	if not _due.has(tick):
		_due[tick] = []
	_due[tick].append(car)


## Rebuilds the due list from the parked vehicles (after a load).
func _index_parked() -> void:
	_by_vid.clear()
	_parked_at.clear()
	_parked_to.clear()
	_due.clear()
	_due_done = -1
	_pend.clear()
	_doored.clear()
	_pseq.clear()
	_next_pseq = 0
	for car in parked:
		_by_vid[car.id] = car
		_file_parked(car)
		_pseq[car.id] = _next_pseq
		_next_pseq += 1
		if car.has("pending"):
			_pend[car.id] = car
		if car.until >= 0:
			_due_at(car, car.until)


func _unpark(car: Dictionary) -> void:
	parked.erase(car)
	_by_vid.erase(car.id)
	var here: Array = _parked_at.get(car.get("at_place", ""), [])
	for i in here.size():
		if is_same(here[i], car):
			here.remove_at(i)
			break
	if here.is_empty():
		_parked_at.erase(car.get("at_place", ""))
	_parked_to.erase(car.id)
	_pend.erase(car.id)
	_doored.erase(car.id)
	_pseq.erase(car.id)
	parked_version += 1


## True for a spot behind a garage door that opens: a home's garage with
## a door the art logged in front of it (not a parking deck or a factory's
## bay, whose doors come later).
static func _behind_door(pl: Dictionary, spot: int) -> bool:
	return spot >= 0 and spot < pl.get("spots", []).size() and pl.spots[spot].kind == "garage" \
		and int(pl.get("zone", -1)) == ZoneMap.Zone.RESIDENTIAL and DoorEvents.door_for(pl, spot) >= 0


## True for a spot inside a factory's bay (an industrial lot's "bay"),
## whose overhead door a truck waits for (BAY_WAIT).
static func in_bay(pl: Dictionary, spot: int) -> bool:
	return spot >= 0 and spot < pl.get("spots", []).size() and pl.spots[spot].kind == "bay" \
		and int(pl.get("zone", -1)) == ZoneMap.Zone.INDUSTRIAL


## A car whose driver sets out on a `walk` ticks long to it: its garage
## door starts up so it is DOOR_SHARE of the way up as they get there.
func _open_door(car: Dictionary, walk: int) -> void:
	_shut_door(car)
	if not car.has("at_place") or not _behind_door(place(car.at_place), int(car.get("spot", -1))):
		return
	var lead := int(DOOR_TICKS * DOOR_SHARE)
	car.door_t = _tick + maxi(walk - lead, 0)
	car.door_n = clampi(roundi(float(_tick + walk - int(car.door_t)) / DOOR_SHARE), DOOR_MIN, DOOR_TICKS)
	_doored[car.id] = car


## Forgets a car's garage door (it closes, as far as DoorEvents knows).
func _shut_door(car: Dictionary) -> void:
	car.erase("door_t")
	car.erase("door_n")
	_doored.erase(car.id)


## Puts a vehicle at rest in a spot.
func _park(car: Dictionary, pl: Dictionary, spot: int) -> void:
	var s: Dictionary = pl.spots[spot]
	car.at_place = pl.ref
	car.spot = spot
	car.pos = _nose(s, car.len)  # front bumper, as when driving
	car.face = s.face
	car.hidden = s.hidden
	car.v = 0.0
	car.a = 0.0
	car.j = null
	car.conn = null
	car.pj = null
	for k in ["route", "leg", "d", "end_d", "goal", "dest", "park", "home", "to_place", "to_spot", "lane",
			"commit", "arrive", "stuck", "lc_from", "lc_t", "lc_cool", "held", "jd", "at", "facing", "pulled_over",
			"door_t", "door_n", "backing", "dock_t", "bay_t"]:
		car.erase(k)
	if not car.has("until"):
		car.until = -1
	parked.append(car)
	_by_vid[car.id] = car
	_file_parked(car)
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
	_cart_plan = _is_cart(car)
	var trip := {} if shut else _route(a, to_pl.stop)
	_truck_plan = false
	_cart_plan = false
	if trip.is_empty() and not shut:
		return false
	var spot := -1
	var park_ref: String = to_pl.ref
	if not to_pl.get("edge", false):
		spot = -1 if shut else _reserve(to_pl, car.id, truck, _is_cart(car), _dock_kind(car, cargo))
		# A full driveway at home: the extra car goes on the street out front,
		# as in any real neighbourhood; a town lot is for shoppers, workers
		# and visitors (many towns, Marion among them, ban overnight parking
		# in municipal lots for snow plowing).
		if spot < 0 and after.get("driver", -1) != -1 and int(to_pl.get("zone", -1)) != ZoneMap.Zone.RESIDENTIAL:
			var alt := _parking_near(to_pl, car.id)
			if not alt.is_empty():
				_truck_plan = truck
				_cart_plan = _is_cart(car)
				var alt_trip := _route(a, place(alt[0]).stop)
				_truck_plan = false
				_cart_plan = false
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
			spot = _new_curb(to_pl, to_pl.stop, car.id, car.len)
			if spot < 0:
				return false
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
	if car.has("at_place") and is_same(_by_vid.get(car.id), car):
		_parked_to[car.id] = car
	if car.has("at_place") and after.get("driver", -1) != -1 and _flows_on():
		_flow_start(car)
		return true
	_fix_end(car)
	if car.has("at_place") and in_bay(from_pl, int(car.get("spot", -1))):
		car.bay_t = _tick  # its door starts up: it waits inside (BAY_WAIT)
	if car.has("at_place"):
		car.pending = true  # pulls out as soon as there's a gap
		_pend[car.id] = car
		_try_launch(car)
	elif not _launch(car):
		_waiting.append(car)
	return true


## A parked vehicle with a trip pulls out if there's a gap in traffic.
func _try_launch(car: Dictionary, lanes := {}) -> bool:
	if car.has("bay_t") and _tick < int(car.bay_t) + BAY_WAIT:
		return false  # its factory door is still going up
	if cars.size() >= max_cars or not _launch(car, lanes):
		return false
	if not lanes.is_empty():
		_lane_add(lanes, car)
	_release(car.at_place, car.spot, car.id)
	_unpark(car)
	for k in ["at_place", "spot", "pos", "face", "hidden", "pending", "bay_t"]:
		car.erase(k)
	_doored.erase(car.id)  # (door_t rides on while it backs out: DoorEvents)
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
		i = _reserve(pl, car.id, car.len > 6.5, _is_cart(car), _dock_kind(car, car.get("cargo", {})))
		if i < 0:
			i = _new_curb(pl, pl.stop, car.id, car.len)
			if i < 0:
				return {}
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
	var e := _entrance(pl, car.to_spot, car.len)
	var d := _nearest_d(w, e)
	var s: Dictionary = pl.spots[car.to_spot]
	if s.kind == "curb" and car.len > 6.5 and s.face.dot(_way_dir(w, clampf(d, 0.0, w.len))) < 0.0:
		# A truck can't swing a U-turn across a two-lane road to the far
		# curb (a WB-67 needs a 45 ft radius): it stops at the curb on its
		# own side, across from the place, as delivery drivers do.
		var frac: float = d / w.len if w.fwd else 1.0 - d / w.len
		var ci := _new_curb(pl, {"seg": w.seg, "at_frac": frac, "side": 1 if w.fwd else -1}, car.id, car.len)
		if ci >= 0:
			_release(pl.ref, car.to_spot, car.id)
			car.to_spot = ci
			e = _entrance(pl, ci, car.len)
			d = _nearest_d(w, e)
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
	# Far enough on that the way in (Entrance, 9 m back of the space) is
	# still ahead when the car gets to it, so it pulls straight in.
	var at := clampf(car.d + PARK_LEAD + 16.0, 0.0, w.len)
	var frac: float = at / w.len if w.fwd else 1.0 - at / w.len
	var stop := {"seg": w.seg, "at_frac": frac, "side": 1 if w.fwd else -1}
	var ci := _new_curb(pl, stop, car.id, car.len)
	if ci < 0:
		return
	_release(pl.ref, car.get("to_spot", -1), car.id)
	car.to_spot = ci
	car.pulled_over = true
	car.end_d = clampf(_nearest_d(w, _entrance(pl, car.to_spot, car.len)), car.d + PARK_LEAD, w.len - 0.5)


## Where cars leave the road for a spot: the curb cut, the lane's road end,
## or the curb space itself.
func _entrance(pl: Dictionary, spot: int, car_len := 0.0) -> Vector3:
	var s: Dictionary = pl.spots[spot]
	if s.kind == "curb":
		# Far enough back that a long rig's tail is behind it as it pulls in
		# straight, rather than looping back on itself to line up.
		return s.pos - s.face * maxf(9.0, car_len * 0.5 + 2.5)
	if s.get("rear", false):
		return _dock_pt(s, s.gx, s.zc)  # a warehouse's gate
	if not pl.drive.is_empty():
		return pl.drive[pl.drive.size() - 1]
	return SiteLayout.world(pl.lot, Vector2(pl.lay.cut_x, -pl.lot.to_curb))


## The way in, from the edge of the road to the spot, in local steps.
func _approach_pts(pl: Dictionary, spot: int, car_len: float) -> Array:
	var s: Dictionary = pl.spots[spot]
	var front: Vector3 = _nose(s, car_len)
	if s.kind == "curb":
		return [s.pos - s.face * (car_len * 0.5 + 1.0), front]
	if s.get("rear", false):
		# To where it stops before backing in (_back_in); a rig the court
		# has no room for (given this dock on a reroute) pulls up to it.
		var way := _dock_way(s, car_len)
		return way.approach if not way.is_empty() else [_dock_pt(s, s.gx, s.zc), front]
	if s.has("via"):
		# A parking lot: in at the driveway, along its aisles to the stall.
		return [pl.drive[pl.drive.size() - 1]] + s.via + [front]
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
			var az: float = s.get("aisle", lay.aisle_z)
			pts.append(Vector2(cut, az))
			pts.append(Vector2(sp.x, az))
			# Square to the stall at its mouth, then straight in, clear of
			# the cars either side.
			var mouth := sp - Vector2(s.face.dot(SiteLayout.world_dir(lot, Vector2(1, 0))),
				s.face.dot(SiteLayout.world_dir(lot, Vector2(0, 1)))) * (SiteLayout.STALL_DEPTH * 0.5 + 0.3)
			if mouth.distance_to(Vector2(sp.x, az)) > 1.0:
				pts.append(mouth)
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
	var back := PackedVector3Array()
	if car.end_d < car.d + 6.0:
		# Too close to its way in to make the turn, or past it (it came onto
		# the street right by it, or the place moved): back up along the lane
		# to short of it, then turn in as usual, as a driver who overshot
		# does, rather than swinging round on the spot.
		var to_d := clampf(car.end_d - 8.0, 0.5, car.d)
		back.append(here[0])
		for q in _lane_run(w, car.lane, car.d, to_d).slice(1):
			back.append(Vector3(q.x, 0.0, q.z))
		here = [back[back.size() - 1], _way_dir(w, to_d)]
	var ld := clampf(car.end_d - 1.0, _nearest_d(w, here[0]) + 2.5, w.len)
	var wps := [here[0], here[0] + here[1] * 2.0, _lane_point(w, car.lane, ld)]
	var s: Dictionary = pl.spots[car.to_spot]
	var dir := _way_dir(w, ld)
	if s.kind == "curb" and s.face.dot(dir) < 0.0:
		# A curb space across the street: a U-turn over to it, as a driver
		# swings round on a quiet street, rather than cutting straight back.
		# It swings round no tighter than a car turns (about 3.5 m), from a
		# few metres on up the lane.
		wps[2] = _lane_point(w, car.lane, clampf(maxf(ld, car.d + 6.0), 0.0, w.len))
		var lat: Vector3 = s.pos - wps[2]
		lat -= dir * lat.dot(dir)
		lat.y = 0.0
		var r := maxf(lat.length(), 7.0) * 0.5
		var side := lat.normalized() if lat.length() > 0.1 else Vector3(dir.z, 0.0, -dir.x)
		for k in range(1, 13):
			var ang := PI * k / 12.0
			wps.append(wps[2] + dir * (r * sin(ang)) + side * (r - r * cos(ang)))
		wps.append(s.pos + s.face * car.len * 0.5)
	else:
		wps.append_array(_approach_pts(pl, car.to_spot, car.len))
	var pts := _smooth(wps)
	var rev := 0.0
	if back.size() >= 2:
		rev = _polylen(back)
		back.append_array(pts.slice(1))
		pts = back
	return _poly_path({"node": -1, "wi": w.id, "li": car.lane, "wo": -1, "lo": -1, "turn": Turn.RIGHT,
		"vt": 4.0, "exit_d": 0.0}, pts, rev)


## Path out of a spot into lane `lane` of way `w`, starting at road position
## `d`: backing out of the stall or driveway first, as drivers do.
func _out_path(car: Dictionary, pl: Dictionary, spot: int, w: Dictionary, lane: int, d: float) -> Dictionary:
	var s: Dictionary = pl.spots[spot]
	var top: float = maxf(w.s1 - 0.5, 1.0)  # back in the lane before the junction
	var bot: float = minf(w.s0 + 0.5, top)  # and clear of the one behind
	var front: Vector3 = _nose(s, car.len)
	var entry := _entrance(pl, spot)
	var de := _nearest_d(w, entry)
	if s.kind == "curb":
		# Pull away from the curb into the lane.
		var df := _nearest_d(w, front)
		if s.face.dot(_way_dir(w, df)) < 0.0:
			# Parked facing the other way (double-parked across the street):
			# a U-turn out into the lane, as drivers do on a quiet street.
			var lat := _lane_point(w, lane, df) - front
			lat -= s.face * lat.dot(s.face)
			lat.y = 0.0
			var ld := lat.normalized() if lat.length() > 0.1 else Vector3(-s.face.z, 0.0, s.face.x)
			var r := maxf(lat.length(), 3.0) * 0.5
			var u := PackedVector3Array()
			for k in 13:
				var ang := PI * k / 12.0
				u.append(front + ld * (r - r * cos(ang)) + s.face * (r * sin(ang)))
			var du := _nearest_d(w, u[u.size() - 1])
			var go_u := clampf(du + 6.0, bot, top)
			for q in _lane_run(w, lane, minf(du + 1.5, go_u - 0.5), go_u):
				u.append(Vector3(q.x, 0.0, q.z))
			return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
				"vt": 4.0, "exit_d": go_u}, u, 0.0)
		if df > top - 3.0:
			# No room ahead (the road was rebuilt short of the spot): back out
			# into the lane, then pull forward to where it joins traffic.
			var back_to := clampf(minf(df, top) - 9.0, bot, top)
			var rp := _smooth([front, _lane_point(w, lane, back_to)])
			var rev := _polylen(rp)
			for q in _lane_run(w, lane, back_to, top).slice(1):
				rp.append(Vector3(q.x, 0.0, q.z))
			return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
				"vt": 4.0, "exit_d": top}, rp, rev)
		var go := clampf(df + 7.0, bot, top)
		var pts := _smooth([front, front + s.face * 2.0] + _lane_run(w, lane, minf(clampf(df + 4.0, bot, top), go - 3.0), go))
		return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
			"vt": 4.0, "exit_d": go}, pts, 0.0)
	if s.get("rear", false):
		# Backed in at a warehouse dock: it pulls straight off the dock out
		# to the court's lane, along it to the gate and out into the
		# street, clear of the trucks backed in beside it.
		var pull := _pull_pts(s, car.len)
		de = minf(de, maxf(top - DRIVEWAY_LEAD - 2.0, bot))
		var out_d := clampf(de + DRIVEWAY_LEAD + 2.0, bot, top)
		pull.append_array(_lane_run(w, lane, minf(clampf(de + 2.0, bot, top), out_d - 3.0), out_d))
		return _poly_path({"node": -1, "wi": -1, "li": -1, "wo": w.id, "lo": lane, "turn": Turn.RIGHT,
			"vt": 4.0, "exit_d": out_d}, _smooth(pull), 0.0)
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
	# Backing round to face the way out: the driveway, or (in a parking lot)
	# on along its aisle.
	var toward: Vector3 = s.out[0] if s.has("out") else entry
	var swing := side if side.dot(toward - s.pos) < 0.0 else -side
	var back: float = car.len + (7.0 if s.kind == "bay" else float(s.get("back_pad", 1.5)))
	var mid: Vector3 = front - s.face * back
	# Straight back until the nose is out of the row, then turn: turning any
	# sooner swings the front into the car parked alongside.
	var clear: Vector3 = front - s.face * minf(SiteLayout.STALL_DEPTH, back - 1.0)
	var rev_pts := _smooth([front, clear, mid, mid + swing * 4.5])
	var fwd := [rev_pts[rev_pts.size() - 1], mid]
	if s.has("out"):
		fwd.append_array(s.out)
	if not pl.drive.is_empty():
		for i in range(1, pl.drive.size()):
			fwd.append(pl.drive[i])
	elif not pl.lay.is_empty():
		if s.kind == "stall":
			fwd.append(SiteLayout.world(pl.lot, Vector2(pl.lay.cut_x, float(s.get("aisle", pl.lay.aisle_z)))))
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
	var a := _poly_point(c.pts, c.cum, maxf(jd - 1.5, lo))
	var b := _poly_point(c.pts, c.cum, minf(jd + 1.5, hi))
	# The chord runs on back along the way the car came and on along the
	# way it leaves, so it doesn't snap round as it starts or ends.
	if jd - 1.5 < 0.0:
		# d0 is the way the car faces at the start: backwards when it backs.
		a += c.d0 * (1.5 - jd) if c.rev > 0.0 else -c.d0 * (1.5 - jd)
	if jd >= c.rev and jd + 1.5 > c.len:
		b += c.d1 * (jd + 1.5 - c.len)
	var dir := _flat_dir(b - a)
	if b.distance_to(a) < 0.05:
		dir = c.d1 if jd >= c.rev else -c.d0
	if jd < c.rev:
		dir = -dir
	return [p, dir]


## The way a truck `vlen` long stopped at `p`, heading `h`, backs into dock
## spot `s`: straight back along the lane, round the turn, up to the dock
## (points for _smooth, in the order its front bumper goes), or [] when it
## stands in line with the door already.
static func _back_pts(s: Dictionary, p: Vector3, h: Vector3, vlen: float) -> Array:
	var nf := _nose(s, vlen)
	var k := p + h * (nf - p).dot(h)
	var run := (p - k).dot(h)
	if run < 3.0 or nf.distance_to(k) < 1.0:
		return []
	# The turn is kept tight round the corner (straight runs either side
	# of it), so the truck stays in its lane and its door's column.
	var r := minf(_dock_r(vlen), minf(run, nf.distance_to(k)) * 0.5)
	return [p, k + h * r, k, k + (nf - k).normalized() * r, nf]


## The way a truck `vlen` long pulls off dock spot `s`, to the road's edge
## at the gate (points for _smooth; _out_path runs it on along the lane).
static func _pull_pts(s: Dictionary, vlen: float) -> Array:
	var x: float = s.local.x
	var gx: float = s.gx
	var pull := [_nose(s, vlen)]
	if s.has("zl"):
		# Straight off the dock to the lane, a tight turn onto it (clear of
		# the trucks either side), along it and out at the gate.
		var zl: float = s.zl
		var zn: float = (_nose(s, vlen) - s.o).dot(s.bz)
		var r := minf(_dock_r(vlen), minf(zn - zl, absf(gx - x)) * 0.5)
		if r > 0.5:
			var sd := signf(gx - x)
			pull.append_array([_dock_pt(s, x, zl + r), _dock_pt(s, x, zl), _dock_pt(s, x + sd * r, zl)])
		pull.append(_dock_pt(s, gx, zl))
	pull.append(_dock_pt(s, gx, s.zc))
	return pull


## A truck stopped in a warehouse's court past its dock (_dock_way) backs
## round into it: straight back with the cab in line, then round the turn
## and square up to the door. Its load counts now, as it did pulling up at
## the curb out front (so the backing in and the wait at the dock change no
## money); it parks, and its door goes up, once it is against the dock.
## False for any other vehicle, or one already backing in.
func _back_in(car: Dictionary) -> bool:
	if car.get("backing", false) or not car.has("to_place"):
		return false
	var pl := place(car.to_place)
	var i: int = car.get("to_spot", -1)
	if pl.is_empty() or i < 0 or i >= pl.spots.size() or not pl.spots[i].get("rear", false):
		return false
	var back := _back_pts(pl.spots[i], car.j.pts[car.j.pts.size() - 1], _flat_dir(car.j.d1), car.len)
	if back.is_empty():
		return false  # it pulled straight up to the dock: it parks as it is
	var pts := _smooth(back)
	if car.get("to_ref", "") != "" and car.get("trip", -1) >= 0 and car.get("after", {}).get("report", true):
		_report(car, arrivals)
		if not car.has("after"):
			car.after = {}
		car.after["report"] = false
	car.j = _poly_path({"node": -1, "wi": car.j.wi, "li": car.j.li, "wo": -1, "lo": -1, "turn": Turn.RIGHT,
		"vt": 4.0, "exit_d": 0.0}, pts, _polylen(pts))
	car.jd = 0.0
	car.v = 0.0
	car.backing = true
	return true


## A car pulled in: it parks, its trip is reported, and the people in it
## get out and walk in.
func _arrive(car: Dictionary) -> void:
	if car.get("to_ref", "") != "" and car.get("trip", -1) >= 0 and car.get("after", {}).get("report", true):
		_report(car, arrivals)
	if car.get("retire", false):
		# Gone for good, it lets go of the space held for it: a loaded copy,
		# without the car, has it free. It kept it, so the next shopper
		# parked in different stalls in the two (2026-10-27).
		_drop_hold(car)
		return
	if car.to_place == "edge":
		return  # off the map
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
	if pl.spots[car.spot].get("rear", false):
		# Backed up to a warehouse's dock: its door goes up now (DoorEvents),
		# and it sits there being unloaded before it heads off.
		car.dock_t = _tick
		stay = maxi(stay, DOCK_DWELL)
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
	if _due_done >= 0 and _due_done == _tick - 1:
		if _due.has(_tick):
			ticks.append(_tick)  # the usual case: only this tick's bucket is new
	else:
		for t in _due:
			if t <= _tick:
				ticks.append(t)
	_due_done = _tick
	for t in ticks:
		for car in _due[t]:
			if car.until == t and is_same(_by_vid.get(car.id), car):
				due.append(car)
		_due.erase(t)
	# Cars waiting for a gap to pull out look when drivers decide (_drive).
	for vid in (_pend if _tick % THINK_EVERY == 0 else _NO_PEND):
		var car: Dictionary = _pend[vid]
		if car.has("pending") and is_same(_by_vid.get(vid), car):
			due.append(car)
	if due.is_empty():
		return
	due.sort_custom(func(a, b): return _pseq[a.id] < _pseq[b.id])
	var last := -1
	var lanes := {}  # where the moving cars are, filed once for every pull-out
	for car in due:
		if car.id == last:
			continue
		last = car.id
		if car.get("pending", false):
			if lanes.is_empty():
				lanes[Vector2i(-1, -1)] = []  # (so it isn't filed again when empty)
				for other in cars:
					_lane_add(lanes, other)
			if _try_launch(car, lanes):
				_pend.erase(car.id)
			continue
		var back: String = car.get("next", "")
		var stop: Dictionary = car.get("next_stop", {})
		car.until = -1
		car.erase("next")
		car.erase("next_stop")
		if back == "":
			continue
		if cars.size() >= max_cars or not _send(car, back, "return", {}, {"report": false}, stop):
			_due_at(car, _tick + 20)  # try again shortly
			car.next = back
			car.next_stop = stop




# --- People -------------------------------------------------------------------

## Sends a person somewhere: on foot if it's close or their car isn't here,
## otherwise a walk to the car and a drive (always on foot when `on_foot`,
## as walking the children to school). False if they can't go now.
func go(pid: int, to_ref: String, purpose: String, stay: int, on_foot := false) -> bool:
	if _sim == null or not _sim.people.people.has(pid):
		return false
	if _dirty:
		_rebuild()  # a road built this tick: walks must not follow the old sidewalks
	var p: Dictionary = _sim.people.people[pid]
	var home_ref: String = "lot:" + p.home
	var from_ref: String = home_ref if p.at == "" else p.at
	if from_ref == to_ref or p.at == "travel":
		return false
	var from_pl := place(from_ref)
	var to_pl := place(to_ref)
	if from_pl.is_empty() or to_pl.is_empty():
		return false
	var car: Dictionary = {} if on_foot else _vehicle_parked(p.car)
	var far: bool = from_pl.door.distance_to(to_pl.door) > People.WALK_MAX and not on_foot
	# A golf cart (TownLaws golf_carts) takes its owner on short hops round
	# town, and home again from wherever it was left.
	var cart: Dictionary = {} if on_foot else _vehicle_parked(int(p.get("cart", -1)))
	var by_cart := false
	if not cart.is_empty() and cart.at_place == from_ref and cars.size() < max_cars \
			and (from_ref != home_ref or from_pl.door.distance_to(to_pl.door) <= Balance.CART_TRIP_MAX):
		car = cart
		by_cart = true
	# A car left in a lot down the street is fetched to drive somewhere far,
	# or to bring it home; a short hop is walked and the car stays put (it
	# would only circle the block and park in the same lot again).
	var away: bool = not car.is_empty() and car.at_place != from_ref
	var fetch: bool = away and to_ref == home_ref
	if away and not fetch and not place(car.at_place).is_empty() \
			and place(car.at_place).door.distance_to(to_pl.door) < PARK_WALK:
		far = false  # the car is already parked by the destination: walk on past it
	# Most Americans with a car at home drive even short hops: about a
	# quarter of trips under a mile are walked (NHTS), fewer in small towns.
	if not far and not away and not car.is_empty() \
			and hash([pid, _sim.tick_count]) % 100 >= SHORT_WALK_PCT:
		far = true
	if by_cart:
		far = true  # out on the cart, however short the hop
	if not car.is_empty() and (far or fetch) and cars.size() < max_cars:
		var path := _walk_to_car(from_pl, car)
		if path.is_empty() or walkers.size() >= max_walkers:
			return false
		car.driver = pid
		_open_door(car, _walk(pid, path, {"drive": car.id, "to": to_ref, "purpose": purpose, "stay": stay}))
	else:
		var path := _walk_between(from_pl, to_pl)
		if path.is_empty() or walkers.size() >= max_walkers:
			return false
		_walk(pid, path, {"enter": to_ref, "stay": stay})
	p.at = "travel"
	_sim.people.set_until(p, -1)
	return true


## Puts someone straight where a trip to `to_ref` would have left them, with
## their car parked where that drive would have ended (the place's own lot,
## a public lot within a walk or the curb out front, as _send picks). For a
## clock that jumps, like the title screen opening at Marion's real hour:
## the town shows the hour's parked cars at once, not a downtown that sits
## empty while the morning's commute plays out. False if they can't go.
## `batch` (from arrive_batch) carries what a run of calls learns.
func arrive_now(sim: CitySim, pid: int, to_ref: String, stay: int, batch := {}) -> bool:
	_sim = sim
	_tick = sim.tick_count
	if _dirty:
		_rebuild()
	if not sim.people.people.has(pid):
		return false
	var p: Dictionary = sim.people.people[pid]
	var home_ref: String = "lot:" + p.home
	if p.at != "" or to_ref == home_ref:
		return false
	var home_pl := place(home_ref)
	var to_pl := place(to_ref)
	if home_pl.is_empty() or to_pl.is_empty():
		return false
	var car := _vehicle_parked(p.car)
	# Drives as go() would: anything past a walk, and most short hops too.
	var drive: bool = not car.is_empty() and car.at_place == home_ref \
		and (home_pl.door.distance_to(to_pl.door) > People.WALK_MAX or absi(hash([pid, "arrive"])) % 100 >= SHORT_WALK_PCT)
	if drive and to_pl.stop.has("seg") and not may_enter(int(to_pl.stop.seg), false):
		drive = false  # a plaza: walked from home instead
	if drive:
		var park_ref: String = to_pl.ref
		var spot := _reserve(to_pl, car.id, false)
		if spot < 0 and int(to_pl.get("zone", -1)) != ZoneMap.Zone.RESIDENTIAL:
			var alt := _parking_near(to_pl, car.id, batch.get("full", null))
			if not alt.is_empty():
				park_ref = alt[0]
				spot = alt[1]
		if spot < 0:
			# Lots full: a space at the curb out front.
			spot = _new_curb(to_pl, to_pl.stop, car.id, car.len, batch.get("curbs", null))
		if spot < 0:
			return false
		_release(car.at_place, car.spot, car.id)
		_unpark(car)
		_park(car, place(park_ref), spot)
		car.until = -1
		car.driver = pid  # waits for them, as after a real drive
	p.at = to_ref
	sim.people.set_until(p, _tick + maxi(stay, 1))
	return true


## Returns the ticks the walk takes.
func _walk(pid: int, pts: PackedVector3Array, then: Dictionary) -> int:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var w := {"id": _next_walker, "person": pid, "pts": pts, "cum": cum, "len": cum[cum.size() - 1],
		"d": 0.0, "t": 0, "then": then, "t0": _wstep,
		# Walking pace in whole cm/s, and distance worked out from the ticks
		# walked, so a saved and loaded walker is exactly where it was.
		"v": _pace(pid, pts)}
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
	var ticks := _file_walker(w)
	_next_walker += 1
	return ticks


## A walker's pace in whole cm/s: their own, slower when young or old,
## or, setting off together from home for the same place (a family walking
## to school, a parent with the little ones), the first one's, so they keep
## together.
func _pace(pid: int, pts: PackedVector3Array) -> float:
	var p: Dictionary = _sim.people.people.get(pid, {}) if _sim != null else {}
	var group := []
	if p.has("home") and pts.size() > 1:
		if _group_step != _wstep:
			_groups.clear()
			_group_step = _wstep
		group = [p.home, pts[pts.size() - 1].snapped(Vector3.ONE)]
		if _groups.has(group):
			return _groups[group]
	var share := 1.0
	for a in WALK_PACE:
		if int(p.get("age", 30)) <= int(a[0]):
			share = a[1]
			break
	var v := float(roundi(WALK_V * share * (85 + hash([pid, _next_walker]) % 31))) / 100.0
	if not group.is_empty():
		_groups[group] = v
	return v


## Files a walker under the step they arrive: the first whole step count t
## with t * v * DT >= len.
## Files a walker under the step it gets there; returns how many steps on.
func _file_walker(w: Dictionary) -> int:
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
	return t


## Metres a walker has gone (worked out from the steps, not stored).
func _walker_d(w: Dictionary, frac := 0.0) -> float:
	var steps := float(_wstep - int(w.t0)) + frac
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
				_shut_door(car)
			p.at = "" if car.is_empty() or car.at_place == "lot:" + p.home else car.at_place
			_sim.people.set_until(p, _tick + 30 if p.at != "" else -1)
			return


## From a place's door to a parked car (in this lot, or a short walk away).
func _walk_to_car(from_pl: Dictionary, car: Dictionary) -> PackedVector3Array:
	var car_pl := place(car.at_place)
	if car_pl.is_empty():
		return PackedVector3Array()
	var kerb := _kerb_stop(car.pos)
	if not kerb.is_empty() and not from_pl.lot.is_empty() and not from_pl.lay.is_empty():
		# Parked on the street: along the sidewalks (over at the crosswalks)
		# to the car, then off the kerb beside it.
		var walk := _door_out(from_pl)
		walk.append(SiteLayout.world(from_pl.lot, Vector2(from_pl.lay.door.x, SiteLayout.WALK_Z)))
		var mid := _sidewalks(from_pl.lot, kerb)
		if not mid.is_empty() or (from_pl.lot.seg == kerb.seg and from_pl.lot.side == kerb.side):
			walk.append_array(mid)
			walk.append(kerb.walk_pt)
			walk.append(_car_side(car))
			return walk
	var out := PackedVector3Array()
	if car_pl.ref != from_pl.ref:
		out = _walk_between(from_pl, car_pl)
		if out.is_empty():
			return out
		if car_pl.has("walk_lot") and car.spot < car_pl.spots.size():
			# Into a parking lot by its walk, and down the aisle to the car.
			var aisle: PackedVector3Array = car_pl.spots[car.spot].walk.duplicate()
			aisle.reverse()
			out.append_array(aisle)
		else:
			out.remove_at(out.size() - 1)  # not to the door: to the car
	else:
		out = _door_out(from_pl)
		var gap := _stall_gap(car, car_pl, from_pl.door)
		if gap != Vector3.INF:
			out.append(gap)
	var side := _car_side(car)
	out.append(side)
	return out


## Out of a stall in a shop's own lot, a driver walks up the gap beside the
## car to its nose (or tail, whichever is toward `toward`) before heading
## across, as people do, never through the cars parked alongside.
## Vector3.INF when the car isn't in a stall.
func _stall_gap(car: Dictionary, pl: Dictionary, toward: Vector3) -> Vector3:
	if car.spot < 0 or car.spot >= pl.spots.size() or pl.spots[car.spot].kind != "stall":
		return Vector3.INF
	var side := Vector3(car.face.z, 0.0, -car.face.x) * 1.4
	if (toward - car.pos).dot(car.face) > 0.0:
		return car.pos + car.face * 0.9 + side
	return car.pos - car.face * (car.len + 0.9) + side


## From a parked car to the door of the place its people are going to.
func _walk_from_car(car: Dictionary, dest: String) -> PackedVector3Array:
	var car_pl := place(car.at_place)
	var dest_pl := place(dest)
	var out := PackedVector3Array([_car_side(car)])
	if dest_pl.is_empty() or car_pl.is_empty():
		return out
	var kerb := _kerb_stop(car.pos)
	if not kerb.is_empty() and not dest_pl.lot.is_empty() and not dest_pl.lay.is_empty():
		# Parked on the street: up onto the sidewalk beside the car, along it
		# (over at the crosswalks, never mid-block) and up the front walk.
		var mid := _sidewalks(kerb, dest_pl.lot)
		if not mid.is_empty() or (dest_pl.lot.seg == kerb.seg and dest_pl.lot.side == kerb.side):
			out.append(kerb.walk_pt)
			out.append_array(mid)
			out.append(SiteLayout.world(dest_pl.lot, Vector2(dest_pl.lay.door.x, SiteLayout.WALK_Z)))
			var inward_k := _door_out(dest_pl)
			inward_k.reverse()
			out.append_array(inward_k)
			return out
	if dest_pl.ref == car_pl.ref:
		var inward := _door_out(car_pl)
		inward.reverse()
		var gap := _stall_gap(car, car_pl, car_pl.door)
		if gap != Vector3.INF:
			out.append(gap)
		out.append_array(inward)
		return out
	var path := _walk_between(car_pl, dest_pl)
	if path.is_empty():
		return out
	if car_pl.has("walk_lot") and car.spot < car_pl.spots.size():
		# Out of a parking lot: up the aisle to its walk, then the sidewalks.
		out.append_array(car_pl.spots[car.spot].walk)
	elif path.size() > 1:
		path.remove_at(0)
	out.append_array(path)
	return out


## Where a car parked on the street meets the sidewalk: {seg, side, at_frac,
## walk_pt}, lot-like for _sidewalks, or {} if it isn't on a street.
func _kerb_stop(pos: Vector3) -> Dictionary:
	return _walk_stop(pos, true)


## Where the sidewalk beside `pos` is: {seg, side, at_frac, walk_pt}, or {}
## if no street with sidewalks runs by. With `kerb`, only for a spot out on
## the street itself (a car parked at the kerb).
func _walk_stop(pos: Vector3, kerb := false) -> Dictionary:
	var near := RoadIndex.segment_near(network, pos, 20.0 if kerb else 40.0)
	if near.is_empty():
		return {}
	var seg: int = near.seg
	var type: int = network.segments[seg].type
	# A road with lots but no sidewalks (a county road, the state highway) is
	# walked along its shoulder (_walk_line); one with no lots at all is not.
	if RoadStyle.is_freeway(type) or not RoadStyle.TYPES[type].lots \
			or kerb and float(near.dist) > RoadStyle.half_width(type) + RoadStyle.CURB_WIDTH:
		return {}  # in a lot or driveway, or a road with no sidewalks
	var c := network.curve_of(seg)
	var t: float = near.t
	var dir := _flat_dir(RoadNetwork.bezier(c[0], c[1], c[2], minf(t + 0.01, 1.0))
		- RoadNetwork.bezier(c[0], c[1], c[2], maxf(t - 0.01, 0.0)))
	var side := 1 if (pos - near.point).dot(Vector3(-dir.z, 0.0, dir.x)) >= 0.0 else -1
	var stop := {"seg": seg, "side": side, "at_frac": t}
	var line := _walk_line(seg, side)
	stop.walk_pt = _line_at(line, _frac(stop) * (line.size() - 1))
	return stop


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
	if _sim == null or not _sim.people.people.has(pid) or walkers.size() >= max_walkers:
		return false
	var p: Dictionary = _sim.people.people[pid]
	if p.at != "":
		return false
	if _dirty:
		_rebuild()
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
	var fa := _front_walk(a)
	var fb := _front_walk(b)
	if fa.is_empty() or fb.is_empty():
		return PackedVector3Array()
	var out: PackedVector3Array = fa.path.duplicate()
	var mid := _sidewalks(fa.lot, fb.lot)
	if mid.is_empty() and fa.lot.seg != fb.lot.seg:
		return PackedVector3Array()
	out.append_array(mid)
	var inward: PackedVector3Array = fb.path.duplicate()
	inward.reverse()
	out.append_array(inward)
	return out


## How a place meets the sidewalk on foot: {"lot": where on the street
## (seg, side, at_frac), "path": from its door out to the sidewalk}, or {}.
## A town parking lot goes out by its own walk (_park_place).
func _front_walk(pl: Dictionary) -> Dictionary:
	if pl.has("walk_lot"):
		return {"lot": pl.walk_lot, "path": pl.walk_out}
	if pl.has("foot_lot"):
		return {"lot": pl.foot_lot, "path": pl.foot_out}
	if pl.lot.is_empty() or pl.lay.is_empty():
		return {}
	var path := _door_out(pl)
	path.append(SiteLayout.world(pl.lot, Vector2(pl.lay.door.x, SiteLayout.WALK_Z)))
	return {"lot": pl.lot, "path": path}


## Sidewalk points between two lots' fronts (not including either end).
func _sidewalks(la: Dictionary, lb: Dictionary) -> PackedVector3Array:
	_marks.clear()
	var out := PackedVector3Array()
	if la.seg == lb.seg and la.side == lb.side:
		var line := _walk_line(la.seg, la.side)
		_append_span(out, line, _frac(la), _frac(lb))
		_worn(la.seg, la.side)
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
	var starts := []
	for end in [0, 1]:
		var st := Vector3i(_seg_node(la.seg, end), la.seg, la.side)
		var f := _walk_end(la.seg, end)
		dist[st] = absf(f - start_f) * _seg_len(la.seg)
		prev[st] = null
		starts.append(st)
	# The nearest open corner next, ties to the lowest (x, y, z): a heap of
	# [distance when filed, corner]. A corner filed again nearer comes out
	# first; its older, farther filings come out later and are passed over.
	var hd := PackedFloat64Array()
	var hn := []
	for st in starts:
		_wpush(hd, hn, dist[st], st)
	var seen := {}
	var best := People.WALK_MAX * 2.0
	var best_end = null
	while not hd.is_empty():
		var u: Vector3i = hn[0]
		_wpop(hd, hn)
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
				_wpush(hd, hn, nd, v)
	if best_end == null:
		return out
	var chain := []
	var x = best_end
	while prev[x] != null:
		chain.push_front([prev[x][0], x, prev[x][1]])
		x = prev[x][0]
	var first: Vector3i = x
	_append_span(out, _walk_line(la.seg, la.side), start_f, _walk_end(first.y, 0 if first.x == _seg_node(first.y, 0) else 1))
	_worn(la.seg, la.side)
	for c in chain:
		var from: Vector3i = c[0]
		var to: Vector3i = c[1]
		var f0 := _walk_end(from.y, 0 if from.x == _seg_node(from.y, 0) else 1)
		var f1 := _walk_end(to.y, 0 if to.x == _seg_node(to.y, 0) else 1)
		match c[2]:
			"along":
				_append_span(out, _walk_line(to.y, to.z), f0, f1)
				_worn(to.y, to.z)
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
	if lb.seg != la.seg or lb.side != la.side:
		_worn(lb.seg, lb.side)
	return out


## A walk along one side of a road, for the paths it wears where there's
## no sidewalk (WornPaths).
func _worn(seg: int, side: int) -> void:
	if _sim != null:
		_sim.worn.note(network, seg, side)


## (_sidewalks' heap) True when [d, a] comes out before [e, b].
static func _wless(d: float, a: Vector3i, e: float, b: Vector3i) -> bool:
	return d < e or (d == e and (a.x < b.x or a.x == b.x and (a.y < b.y or a.y == b.y and a.z < b.z)))


static func _wpush(hd: PackedFloat64Array, hn: Array, d: float, n: Vector3i) -> void:
	hd.append(d)
	hn.append(n)
	var i := hd.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if not _wless(d, n, hd[p], hn[p]):
			break
		hd[i] = hd[p]
		hn[i] = hn[p]
		i = p
	hd[i] = d
	hn[i] = n


static func _wpop(hd: PackedFloat64Array, hn: Array) -> void:
	var last := hd.size() - 1
	var d: float = hd[last]
	var n: Vector3i = hn[last]
	hd.resize(last)
	hn.resize(last)
	if last == 0:
		return
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= last:
			break
		var m := l
		if l + 1 < last and _wless(hd[l + 1], hn[l + 1], hd[l], hn[l]):
			m = l + 1
		if not _wless(hd[m], hn[m], d, n):
			break
		hd[i] = hd[m]
		hn[i] = hn[m]
		i = m
	hd[i] = d
	hn[i] = n


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
	# The crosswalk is a little ahead of where the cars stop.
	var n0: int = w.from if fwd else w.to
	var n1: int = w.to if fwd else w.from
	if _walk_back.has(n0):
		s0 = minf(s0, minf(_walk_arm.get([n0, sid], _walk_back[n0]), w.len * 0.4))
	if _walk_back.has(n1):
		s1 = maxf(s1, maxf(w.len - _walk_arm.get([n1, sid], _walk_back[n1]), w.len * 0.6))
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
## A country road has none: people walk its shoulder (FHWA: on the
## shoulder, where there's no sidewalk), never out in the lawns beside it.
func _walk_line(sid: int, side: int) -> PackedVector3Array:
	var key := sid * 2 + (1 if side > 0 else 0)
	if _walk_lines.has(key):
		return _walk_lines[key]
	var pts := network.sample_segment(sid, 16)
	var off := walk_offset(network.segments[sid].type)
	var out := PackedVector3Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := _flat_dir(b - a)
		out.append(Vector3(pts[i].x, 0.0, pts[i].z) + Vector3(-dir.z, 0.0, dir.x) * off * side)
	_walk_lines[key] = out
	return out


## How far from a road's centre line people walk beside it: the middle of
## the sidewalk; on a road without sidewalks the middle of a paved shoulder
## (the state highway's 8 ft), the gravel shoulder of a paved county road,
## or the edge of a gravel or dirt road itself.
static func walk_offset(type: int) -> float:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw := RoadStyle.half_width(type)
	if spec.get("walk", true):
		return hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
	var shoulder: float = spec.get("shoulder", 0.0)
	if shoulder > 0.0:
		return hw - shoulder * 0.5
	if spec.get("surface", "asphalt") == "asphalt":
		return hw + 0.9  # the gravel strip RoadMesh lays along a country road
	return maxf(hw - 0.6, 1.2)


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


## Where a person on foot is, which way they face and how far they've
## walked, `frac` of a step after the last one (a kerb wait holds them).
func walker_pose(w: Dictionary, frac := 0.0) -> Array:
	var d := minf(_walker_d(w, frac), w.len)
	var p := _poly_point(w.pts, w.cum, d)
	var q := _poly_point(w.pts, w.cum, minf(d + 0.5, w.len))
	if q.distance_to(p) < 0.01:
		q = p + _flat_dir(w.pts[w.pts.size() - 1] - w.pts[maxi(w.pts.size() - 2, 0)]) * 0.5
	var dir := _flat_dir(q - p)
	# Each keeps to the right of the walk (as Americans do), in a lane of
	# their own across it: two coming the other way pass each other, and a
	# household out together (people ids run in a row) walks side by side.
	# Drawn only: the sim's walkers stay on the line.
	var lane: float = WALK_LANES[posmod(int(w.person), WALK_LANES.size())]
	return [p + dir.cross(Vector3.UP) * lane, dir, d]


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
	# Drivers look and decide every THINK_EVERY ticks (a 0.2 s reaction, well
	# under a real driver's ~1 s, AASHTO); cars move every tick on what they
	# decided, so stop lines and parking stay exact.
	var think := _tick % THINK_EVERY == 0
	if not think:
		_drive_move(false)
		_keep_gaps()
		return
	# Vehicles with a job that were waiting for a gap to pull out. Routes
	# only break when the roads are rebuilt, so they're checked once a version.
	var lanes := {}
	for car in _waiting.duplicate():
		if _waiting_ok != version and (not ways.has(car.route[0])
				or car.route.any(func(w): return not ways.has(w)) and not _replan(car)):
			# Its road went, or was rebuilt and there's no way through now.
			_waiting.erase(car)
			_drop_hold(car)
			_report(car, failed)
		elif cars.size() < max_cars:
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
	_replan_some(THINK_EVERY)
	_drive_move(true)


## Between decisions nobody runs into the car ahead: a follower closing in
## on a braking leader stops short at the jam gap, as it would have braked.
func _keep_gaps() -> void:
	for key in _lanes:
		var list: Array = _lanes[key]
		for i in range(1, list.size()):
			var car: Dictionary = list[i]
			var lead: Dictionary = list[i - 1]
			# (Either may have parked since the lanes were filed.)
			if not car.has("route") or not lead.has("route") or lead.has("at_place") or car.get("j") != null or lead.get("j") != null \
					or car.route[car.leg] != lead.route[lead.leg] \
					or car.lane != lead.lane:
				continue
			var room: float = lead.d - lead.len - 1.0
			if car.d > room:
				car.d = maxf(room, car.d - car.v * DT)
				car.v = minf(car.v, lead.v)


## Moves every car on by its speed and does what it reached: a junction,
## its spot, the end of its road.
## `tally`: also measure how fast each road is going (on decision ticks).
func _drive_move(tally: bool) -> void:
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
			_drop_hold(car)
			_report(car, failed)
			continue
		if car.j != null:
			car.jd += car.v * DT
			speed_sum += 1.0
			limit_sum += 1.0
			if car.jd >= car.j.len - (0.3 if car.j.wo < 0 else 0.0):
				if car.j.wo < 0 and _back_in(car):
					continue  # at a warehouse dock: now it backs up to the door
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
		if tally:
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
	if tally:
		_tally_speeds(way_sum, speed_sum, limit_sum)


## Each road's running speed (a share of its limit), eased toward what the
## cars on it are doing; it feeds route costs and the flow figure.
func _tally_speeds(way_sum: Dictionary, speed_sum: float, limit_sum: float) -> void:
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
			sp = snappedf(lerpf(_speed[wid], minf(way_sum[wid][0] / way_sum[wid][1], fs), EASE_BUSY), 0.000001)
		else:
			sp = snappedf(lerpf(_speed[wid], fs, EASE_QUIET), 0.000001)
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
	_tails.clear()
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
		# Out of the junction at the front but not yet at the back: a semi's
		# trailer still sweeps the box for a good 20 m after its cab leaves.
		var pj = car.get("pj")
		if pj != null and pj is Dictionary and pj.get("node", -1) >= 0 and pj.wo == car.route[car.leg] \
				and car.d - car.len < pj.exit_d:
			if not _tails.has(pj.node):
				_tails[pj.node] = []
			_tails[pj.node].append(pj)
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
	# Oncoming drivers wait back where a long vehicle is about to swing
	# across their lane, or is swinging across it now (and only while it
	# can go: not for one stuck in a queue itself).
	_hold.clear()
	for car in cars:
		var c = car.j if car.j != null else (car.conn if car.commit else null)
		if c != null and c.has("sweep") and not (car.j != null and car.jd > c.len - WIDE_BLEND):
			_claim_sweep(car, c.sweep)
	for n in _approach:
		for ap in _approach[n]:
			if ap.conn.has("sweep") and not ap.car.commit and ap.ds < SWEEP_CALL and _room_past(ap.car, ap.conn):
				_claim_sweep(ap.car, ap.conn.sweep)


func _claim_sweep(car: Dictionary, sweep: Dictionary) -> void:
	for key in sweep:
		var hd: float = sweep[key]
		if not _hold.has(key) or hd < _hold[key][0]:
			_hold[key] = [hd, car.id]


## The junction path a car will take at the end of its way, or {} if its
## lane can't make the turn it planned.
func _conn_for(car: Dictionary) -> Dictionary:
	var wi: int = car.route[car.leg]
	var wo: int = car.route[car.leg + 1]
	var r := wide_radius(car.len)
	var key := Vector4i(wi, car.lane, wo, int(r))
	var c = _cfor.get(key)
	if c == null:
		if not lanes_for(wi, wo).has(car.lane):
			c = {}
		elif r > 0.0:
			c = _wide_connector(wi, car.lane, wo, _out_lane(wi, car.lane, wo), r)
		else:
			c = _connector(wi, car.lane, wo, _out_lane(wi, car.lane, wo))
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
	# Drivers see a car ahead pulling away and go with it: the gap it opens
	# in the next ANTICIPATE_S counts already. Only while it's faster, so
	# steady following keeps its distance. Without it a queue at a green
	# set off one timid car at a time (HCM: about 2 s a car, not 3).
	# (Once it's clearly moving: a driver reacts a moment after the car
	# ahead sets off, so a queue starts in a ripple.)
	if vl > 1.5:
		gap += maxf(0.0, vl - v) * ANTICIPATE_S
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
			acc = minf(acc, _idm(car.v, v0, ds + JAM_GAP - 0.5, 0.0))
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
	var hold = _hold.get(w.id * 8 + car.lane)
	if hold != null and (hold[1] == car.id or car.d > hold[0] + 0.5):
		hold = null
	if hold != null and car.commit and car.d + car.v * car.v / (2.0 * BRAKE) <= hold[0]:
		# A truck has started to swing across this lane: think again.
		car.commit = false
		car.conn = null
		_committed.get(c.node, []).erase(car)
	if not car.commit:
		if ds < 4.0 and car.v < 1.0 and car.arrive < 0.0:
			car.arrive = time
		# On a green, drivers carry on through rather than creeping up to
		# the line as if it were red: they decide from well back (HCM
		# saturation flow, about 2 s a car).
		# Decide before the line starts to brake them: the car-following
		# model feels a closed line from its safe gap ahead (jam gap, time
		# gap and braking room), so deciding only at the braking distance
		# meant slowing for every clear junction and never reaching the
		# limit between them (55 mph roads driven at about 20).
		var reach: float = maxf(car.v * car.v / (2.0 * BRAKE) + 4.0,
			JAM_GAP + car.v * HEADWAY + car.v * car.v / (2.0 * sqrt(car.acc * BRAKE)) + 4.0)
		if junctions[c.node].control == Rule.SIGNAL and light(c.node, c.wi) == Light.GREEN:
			reach = maxf(reach, GREEN_REACH)
		if ds <= reach and hold == null and _may_enter(car, c, ds):
			car.commit = true
			car.conn = c
			if not _committed.has(c.node):
				_committed[c.node] = []
			_committed[c.node].append(car)
			if engineers and junctions[c.node].control == Rule.SIGNAL:
				var seen: Dictionary = demand.get(c.node, {})
				seen[c.wi] = int(seen.get(c.wi, 0)) + 1
				demand[c.node] = seen
	if car.commit:
		var lead := _through_leader(c, ds, car)
		acc = minf(acc, _idm(car.v, v0, lead[0], lead[1]))
		# Ease off for the turn.
		var vt: float = c.vt
		if vt < car.v:
			acc = minf(acc, _idm(car.v, v0, ds + JAM_GAP + vt * HEADWAY, vt))
	else:
		# Stop with the nose at the line: the line is not a car ahead, so
		# no jam gap behind it (it left cars about 2.5 m short).
		acc = minf(acc, _idm(car.v, v0, ds + JAM_GAP - 0.5, 0.0))
		# A truck swinging wide across this lane: wait back out of its way
		# (unless already past that point).
		if hold != null:
			acc = minf(acc, _idm(car.v, v0, hold[0] - car.d + JAM_GAP - 0.5, 0.0))
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
		if b.j == null and b.get("conn") == null:
			continue  # parked earlier this tick, right after committing
		var bc: Dictionary = b.j if b.j != null else b.conn
		if b.id != car.id and bc.wo == c.wo and bc.lo == c.lo:
			queued += 1
	var list: Array = _lanes.get(c.wo * 8 + c.lo, [])
	if not list.is_empty():
		# A car pulling away is making room: count where it will be in the
		# couple of seconds this one takes to get there, as drivers do, or
		# each car in a queue waits for a full length to open before moving.
		var last: Dictionary = list[list.size() - 1]
		var room: float = last.d - ways[c.wo].s0
		# ...only while it's really getting away: not braking for a queue
		# ahead of it, or the box fills behind it (review, 2026-10-26).
		if float(last.v) > 1.0 and float(last.get("a", 0.0)) > -0.5:
			room += float(last.v) * ROOM_AHEAD_S
		if room < (queued + 1) * (car.len + JAM_GAP):
			return false
	# Someone on the crosswalk over the road we're turning onto.
	if c.wo >= 0 and crosswalk_busy(n, c.wo >> 1):
		return false
	# A long vehicle swinging wide needs the oncoming lanes it crosses
	# clear, short of their stop lines, and no one there unable to stop.
	for key in c.get("sweep", {}):
		var lane: Array = _lanes.get(key, [])
		if not lane.is_empty():
			var o: Dictionary = lane[0]
			if o.d > c.sweep[key] - 0.5 or o.d + o.v * o.v / (2.0 * BRAKE) > c.sweep[key] + 0.5:
				return false
	# Nothing crossing our path in the junction.
	for b in occupants:
		if b.id == car.id or b.j == null and b.get("conn") == null:
			continue
		var bc: Dictionary = b.j if b.j != null else b.conn
		if _conflicts(c, bc):
			return false
	for tail in _tails.get(n, []):
		if _conflicts(c, tail):
			return false
	var stopped: bool = car.arrive >= 0.0 and time - car.arrive >= FULL_STOP_S
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
				# First come, first served, but not behind someone who can't go
				# yet for a full street beyond: drivers wave each other on.
				if ap.car.id != car.id and ap.conn.wi != c.wi and _first(ap.car, car) and _conflicts(c, ap.conn) \
						and _room_past(ap.car, ap.conn) and not _in_sweep(car, ap.conn):
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
					elif _first(ap.car, car) and _conflicts(c, ap.conn) and _room_past(ap.car, ap.conn) \
							and not _in_sweep(car, ap.conn):
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
	# A car standing at its line (waiting on a gap itself) isn't about to
	# come through: only moving ones within 5 s are (HCM ch. 20 critical gap).
	return ap.car.commit or ap.car.v > 0.5 and ap.ds / ap.car.v < 5.0


## Whether there's a car's length of room for `car` on the far side of
## the junction (if not, it isn't going anywhere yet).
func _room_past(car: Dictionary, c: Dictionary) -> bool:
	if c.wo < 0:
		return true
	var list: Array = _lanes.get(c.wo * 8 + c.lo, [])
	return list.is_empty() or list[list.size() - 1].d - ways[c.wo].s0 >= car.len + JAM_GAP


## Whether `car` stands where path `c` swings wide: that truck can't go
## until it does, so it doesn't wait its turn behind the truck.
func _in_sweep(car: Dictionary, c: Dictionary) -> bool:
	if not c.has("sweep") or car.j != null:
		return false
	var key: int = car.route[car.leg] * 8 + car.lane
	return c.sweep.has(key) and car.d > c.sweep[key] - 0.5


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
			var line := INF if last else ds + JAM_GAP - 0.5  # as the car brakes for the line
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
func _replan_some(every := 1) -> void:
	var budget := REPLANS_PER_TICK * every  # route plans are the costly part of a tick
	var round := _tick / every
	for car in cars:
		if budget == 0:
			return
		if (car.id * 7 + round) % (300 / every) != 0 or car.j != null or car.commit:
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
