class_name CountyTrains
extends RefCounted
## Freight trains on the county's real railroads (CountyRail): the through
## freights that cross Grant County on its main lines whether or not a town
## has a depot. Each is a real train on a real trip: it comes in at the
## county line, runs the whole line at track speed and leaves at the far
## county line, never vanishing on the map. Its consist is real: two or
## three road diesels (GP38-2s and SD40-2s) and covered grain hoppers, tank
## cars, open hoppers and boxcars, each car carrying a load.
##
## The timetable is a pure function of the town's own clock and the county's
## lines, so nothing is saved and every copy of a town sees the same trains.
## Where the town's roads cross a line at grade, the gates come down 25
## seconds before a train (FRA, 49 CFR 234.225) and stay down until its last
## car clears; traffic stops short of them as at the town's own crossings.
##
## Real references: Indiana's rail lines carry from a handful to a few dozen
## freights a day (INDOT State Rail Plan); class 3 track allows 40 mph for
## freight (49 CFR 213.9); a manifest freight runs 50 to 100 cars of about
## 60 ft, a unit grain train about 100 covered hoppers.

## The county's timetable seed: the same lines run the same trains in
## every town (each on its own clock).
const SEED := 1869
## Track speed, m/s (40 mph, as Rail.SPEED.main).
const SPEED := 17.9
## Two lines' ends this near (metres) are one junction.
const JOIN := 12.0
## A train turns from one line onto another only this sharply (a junction's
## turnout, not a reverse move): degrees.
const MAX_TURN := 75.0
## The longest stretch missing from the mapped lines that a train runs
## across (metres), where two ends point at each other within GAP_AIM
## degrees.
const GAP := 300.0
const GAP_AIM := 35.0
## Steps shorter than this (joins between lines, scraps of the mapped
## line) don't turn the train: the mapped corners there aren't the track's.
const SHORT := 40.0
## A through run gets at least this far from where it came in, for its
## length: a run doubling back through a junction is no train's route.
const STRAIGHT := 0.55
## A line within this many metres of the map's edge leaves the county there.
const EDGE := 30.0
## A corridor shorter than this isn't a through line (a yard lead, a spur).
const MIN_CORRIDOR := 12_000.0
## Corridors share no more track than this (metres): trains on one never
## meet trains on another.
const SAME := 1500.0
## The most corridors kept, longest first.
const MAX_CORRIDORS := 6
## Trains in a fleet one way, ticks between them (TrafficSim ticks of
## 0.1 s: ten minutes, about ten kilometres at track speed), and ticks the
## line stands clear before the fleet the other way.
const FLEET := 3
const HEADWAY := 6000
const CLEAR := 600
## Gate warning (s) and the gap kept around the train (m), as Rail.
const GATE_WARNING := Rail.GATE_WARNING
const GATE_PAD := 6.0
## A car's coupled length, metres, and how many cars a train takes.
const CAR_LEN := {"covered": 18.0, "tank": 18.0, "hopper": 16.5, "boxcar": 16.8}
const LOCO_LEN := {"gp38": 18.0, "sd40": 21.0}
const CARS := Vector2i(40, 90)
## Space between coupled cars (knuckles and slack), metres.
const GAP_CARS := 0.6


static func stock_len(kind: String) -> float:
	return float(LOCO_LEN.get(kind, CAR_LEN.get(kind, 18.0)))


## What the county's through freights carry, by train kind: [weight, cars
## by kind with weights]. Grain to the Gulf and the East, ethanol and
## chemicals in tank trains, stone and sand in open hoppers, and mixed
## manifest freight.
const KINDS := {
	"grain": {"w": 3, "cars": {"covered": 1.0}, "cargo": {"covered": "grain"}},
	"tank": {"w": 2, "cars": {"tank": 1.0}, "cargo": {"tank": "ethanol"}},
	"manifest": {"w": 4, "cars": {"boxcar": 0.4, "covered": 0.25, "tank": 0.2, "hopper": 0.15},
		"cargo": {"boxcar": "goods", "covered": "grain", "tank": "chemicals", "hopper": "stone"}},
	"stone": {"w": 1, "cars": {"hopper": 1.0}, "cargo": {"hopper": "stone"}},
}

## Corridors through the county: [{pts: PackedVector2Array (region), cum:
## PackedFloat32Array, length}]. Built once from CountyRail.
static var _corridors: Array = []
static var _built := false

## Grade crossings with this town's roads: [{seg, pos (local Vector3),
## corridor, s, closed}]. TrafficSim stops cars at closed ones.
var crossings := []
## Bumps when the crossings change (roads or the town's place).
var version := 0
var _xing_key := []


## The county's through corridors (see _corridors).
static func corridors() -> Array:
	if not _built:
		_built = true
		_corridors = _build()
	return _corridors


## Joins the county's lines into a graph and keeps the longest through
## runs from one county line to another a train could take.
static func _build() -> Array:
	var routes := CountyRail.all()
	if routes.is_empty():
		return []
	# A line that ends on the side of another (a junction away from that
	# line's own points) gets a point there to join.
	var lines := []
	for r in routes:
		lines.append(Array(r.pts))
	for ri in routes.size():
		var p: PackedVector2Array = routes[ri].pts
		for end in [p[0], p[p.size() - 1]]:
			var best := JOIN
			var at := []
			for rj in routes.size():
				if rj == ri:
					continue
				var q: Array = lines[rj]
				for i in q.size() - 1:
					var on := Geometry2D.get_closest_point_to_segment(end, q[i], q[i + 1])
					var d := on.distance_to(end)
					if d < best and on.distance_to(q[i]) > 1.0 and on.distance_to(q[i + 1]) > 1.0:
						best = d
						at = [rj, i, on]
			if not at.is_empty():
				lines[at[0]].insert(at[1] + 1, at[2])
	# Vertices: every point of every line; ends within JOIN of another
	# line's point are joined to it.
	var pts := PackedVector2Array()
	var adj := []  # vertex -> [vertex]
	var first := []  # line -> its first vertex
	for line in lines:
		first.append(pts.size())
		for i in line.size():
			pts.append(line[i])
			adj.append([])
			if i > 0:
				adj[pts.size() - 1].append(pts.size() - 2)
				adj[pts.size() - 2].append(pts.size() - 1)
	var grid := {}
	for v in pts.size():
		var k := Vector2i((pts[v] / JOIN).floor())
		if not grid.has(k):
			grid[k] = []
		grid[k].append(v)
	for ri in lines.size():
		var n: int = lines[ri].size()
		for v in [first[ri], first[ri] + n - 1]:
			var k := Vector2i((pts[v] / JOIN).floor())
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for u in grid.get(k + Vector2i(dx, dz), []):
						if u != v and pts[u].distance_to(pts[v]) <= JOIN and not u in adj[v]:
							adj[v].append(u)
							adj[u].append(v)
	# A short stretch missing from the mapped data (a few hundred metres,
	# where a line's end points straight at another's): the track runs on.
	var ends := []  # [vertex, outward direction]
	for ri in lines.size():
		var n: int = lines[ri].size()
		var a: int = first[ri]
		var b: int = first[ri] + n - 1
		ends.append([a, (pts[a] - pts[a + 1]).normalized()])
		ends.append([b, (pts[b] - pts[b - 1]).normalized()])
	var cos_gap := cos(deg_to_rad(GAP_AIM))
	for i in ends.size():
		for j in range(i + 1, ends.size()):
			var u: int = ends[i][0]
			var v: int = ends[j][0]
			var gap := pts[v] - pts[u]
			if gap.length() <= JOIN or gap.length() > GAP or u in adj[v]:
				continue
			var dir := gap.normalized()
			if (ends[i][1] as Vector2).dot(dir) >= cos_gap and (ends[j][1] as Vector2).dot(-dir) >= cos_gap:
				adj[u].append(v)
				adj[v].append(u)
	# Where lines leave the map.
	var lo := Terrain.CENTRE - Vector2.ONE * Terrain.SIZE * 0.5
	var hi := lo + Vector2.ONE * Terrain.SIZE
	var edges := []
	for ri in lines.size():
		for v in [first[ri], first[ri] + lines[ri].size() - 1]:
			var p := pts[v]
			if p.x - lo.x < EDGE or hi.x - p.x < EDGE or p.y - lo.y < EDGE or hi.y - p.y < EDGE:
				edges.append(v)
	# From each edge, the longest-reaching run to another edge with no sharp
	# turns (Dijkstra over directed steps, shortest to each far edge).
	var found := []
	for e in edges:
		for path in _runs_from(e, pts, adj, edges):
			found.append(path)
	found.sort_custom(func(a, b): return a.length > b.length)
	var out := []
	for c in found:
		if c.length < MIN_CORRIDOR:
			break
		if c.pts[0].distance_to(c.pts[c.pts.size() - 1]) < STRAIGHT * c.length:
			continue  # doubles back through a junction: not a train's run
		var dup := false
		for o in out:
			if _shared(c, o) > SAME:
				dup = true
				break
		if not dup:
			out.append(c)
		if out.size() >= MAX_CORRIDORS:
			break
	return out


## Shortest smooth runs from edge vertex `e` to every other edge vertex:
## [{pts, cum, length}].
static func _runs_from(e: int, pts: PackedVector2Array, adj: Array, edges: Array) -> Array:
	var cos_max := cos(deg_to_rad(MAX_TURN))
	# State: [prev, at] as a key; distance and back pointer.
	var dist := {}
	var back := {}
	var heading := {}  # state -> the direction the train faces there
	var open := []  # [dist, prev, at]
	for u in adj[e]:
		var d := pts[e].distance_to(pts[u])
		dist[Vector2i(e, u)] = d
		heading[Vector2i(e, u)] = (pts[u] - pts[e]).normalized()
		open.append([d, e, u])
	var best := {}  # far edge -> state
	while not open.is_empty():
		# The nearest open state (the lists are short: a few thousand).
		var bi := 0
		for i in open.size():
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: Array = open[bi]
		open.remove_at(bi)
		var st := Vector2i(cur[1], cur[2])
		if cur[0] > dist.get(st, INF):
			continue
		var at: int = cur[2]
		if at != e and at in edges and not best.has(at):
			best[at] = st
		var dir: Vector2 = heading[st]
		for nx in adj[at]:
			if nx == cur[1]:
				continue
			var step := pts[nx] - pts[at]
			var ndir := dir
			if step.length() > SHORT:
				# A join, or a scrap of line shorter than a turnout, carries on
				# the way the train faced.
				ndir = step.normalized()
				if dir != Vector2.ZERO and dir.dot(ndir) < cos_max:
					continue
			var nd: float = cur[0] + step.length()
			var ns := Vector2i(at, nx)
			if nd < dist.get(ns, INF):
				dist[ns] = nd
				back[ns] = st
				heading[ns] = ndir
				open.append([nd, at, nx])
	var out := []
	for far in best:
		var chain := PackedVector2Array()
		var st: Vector2i = best[far]
		chain.append(pts[st.y])
		while true:
			chain.append(pts[st.x])
			if not back.has(st):
				break
			st = back[st]
		chain.reverse()
		var cum := PackedFloat32Array([0.0])
		for i in range(1, chain.size()):
			cum.append(cum[i - 1] + chain[i - 1].distance_to(chain[i]))
		out.append({"pts": chain, "cum": cum, "length": cum[cum.size() - 1]})
	return out


## Metres of corridor `a` that run along corridor `b` (within JOIN), out
## where the track is drawn.
static func _shared(a: Dictionary, b: Dictionary) -> float:
	var n := 0.0
	var s := 0.0
	while s < a.length:
		var p := _at(a, s)
		if _dist_to(b, p) < JOIN * 2.0 and not _hidden(p):
			n += 100.0
		s += 100.0
	return n


## True inside a backdrop town, where the county's track isn't drawn (and
## its trains run unseen).
static func _hidden(p: Vector2) -> bool:
	var n := CountyRail.near(p.x, p.y, 40.0)
	return not n.is_empty() and CountyRail.kind_at(n.route, n.along) == 3


static func _dist_to(c: Dictionary, p: Vector2) -> float:
	var best := INF
	var pts: PackedVector2Array = c.pts
	for i in pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


## The point `s` metres along corridor c (region coordinates).
static func _at(c: Dictionary, s: float) -> Vector2:
	var pts: PackedVector2Array = c.pts
	var cum: PackedFloat32Array = c.cum
	s = clampf(s, 0.0, c.length)
	var i := clampi(cum.bsearch(s) - 1, 0, pts.size() - 2)
	var span := cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], (s - cum[i]) / span if span > 0.0 else 0.0)


## The point and heading `s` metres along corridor `ci` (region coordinates).
static func pose(ci: int, s: float) -> Array:
	var c: Dictionary = corridors()[ci]
	var a := _at(c, s - 2.0)
	var b := _at(c, s + 2.0)
	return [_at(c, s), (b - a).normalized()]


# --- The timetable ----------------------------------------------------------

## Trains on the county's lines at tick `tick`: [{id, corridor, dir (1 runs
## the corridor from its start, -1 from its end), s (the lead engine's
## metres along the corridor), kind, consist: [[stock, cargo]], length}].
## A train is listed from the tick it enters the map until its last car
## has left it.
##
## The lines are single track, so trains run in fleets the way dispatchers
## run them: FLEET trains one way, HEADWAY apart at the same speed (so none
## catches the one ahead), then, once the last has cleared, FLEET the
## other way. No two trains ever meet.
static func trains_at(tick: int, seed: int) -> Array:
	var out := []
	var cs := corridors()
	for ci in cs.size():
		var c: Dictionary = cs[ci]
		var run := run_ticks(ci)
		var half := (FLEET - 1) * HEADWAY + run + CLEAR
		var cycle := 2 * half
		var t0 := tick - posmod(hash([seed, "county_offset", ci]), cycle)
		for k in range(floori(float(t0) / cycle) - 1, floori(float(t0) / cycle) + 1):
			for phase in 2:
				for j in FLEET:
					var start := k * cycle + phase * half + j * HEADWAY
					if start > t0 or t0 - start > run:
						continue
					var t := train(seed, ci, (k * 2 + phase) * FLEET + j)
					t.dir = 1 if phase == 0 else -1
					var gone := float(t0 - start) * SPEED * TrafficSim.DT
					t.s = gone if t.dir > 0 else c.length - gone
					out.append(t)
	return out


## Ticks from a train's head entering a corridor to its last car leaving.
static func run_ticks(ci: int) -> int:
	return int((float(corridors()[ci].length) + _max_len()) / (SPEED * TrafficSim.DT)) + 1


## Train `n` on corridor `ci`: its kind and its consist (a copy; trains_at
## sets which way it runs and where it is).
static func train(seed: int, ci: int, n: int) -> Dictionary:
	var key := Vector3i(seed, ci, n)
	if not _made.has(key):
		if _made.size() > 256:
			_made.clear()
		_made[key] = _make(seed, ci, n)
	return _made[key].duplicate()


static var _made := {}


static func _make(seed: int, ci: int, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "county_train", ci, n])
	var total := 0
	for k in KINDS:
		total += int(KINDS[k].w)
	var pick := rng.randi() % total
	var kind := ""
	for k in KINDS:
		pick -= int(KINDS[k].w)
		if pick < 0:
			kind = k
			break
	var spec: Dictionary = KINDS[kind]
	var consist := []
	var locos := 2 if rng.randf() < 0.6 else 3
	for i in locos:
		consist.append(["sd40" if rng.randf() < 0.55 else "gp38", ""])
	var cars := rng.randi_range(CARS.x, CARS.y)
	for i in cars:
		var r := rng.randf()
		var stock := ""
		for s in spec.cars:
			r -= float(spec.cars[s])
			if r < 0.0:
				stock = s
				break
		if stock == "":
			stock = spec.cars.keys()[0]
		consist.append([stock, str(spec.cargo[stock])])
	var length := 0.0
	for c in consist:
		length += stock_len(c[0]) + GAP_CARS
	return {"id": hash([ci, n]), "corridor": ci, "dir": 1, "kind": kind, "consist": consist, "length": length}


## The longest a train can be, metres.
static func _max_len() -> float:
	return 3.0 * (LOCO_LEN.sd40 + GAP_CARS) + CARS.y * (18.0 + GAP_CARS)


# --- Crossings with the town's roads -------------------------------------------

## Each tick: finds where the town's roads cross the county's lines (when
## roads change) and sets each crossing's gates.
func tick(sim) -> void:
	var cs := corridors()
	if cs.is_empty():
		return
	var key := [sim.network.revision, sim.terrain_offset]
	if key != _xing_key:
		_xing_key = key
		_find(sim)
	if crossings.is_empty():
		return
	var trains := trains_at(sim.tick_count, SEED)
	for c in crossings:
		var down := false
		for t in trains:
			if int(t.corridor) != int(c.corridor):
				continue
			# The train covers from its head (plus the warning ahead of it) back
			# to its last car.
			var ahead: float = SPEED * GATE_WARNING
			var head: float = t.s
			var lo: float = head - (t.length if t.dir > 0 else -ahead)
			var hi: float = head + (ahead if t.dir > 0 else t.length)
			if c.s >= lo - GATE_PAD and c.s <= hi + GATE_PAD:
				down = true
				break
		c.closed = down


func _find(sim) -> void:
	crossings = []
	version += 1
	var off: Vector2 = sim.terrain_offset
	var cs := corridors()
	for sid in sim.network.segments:
		var pts: PackedVector3Array = sim.network.sample_segment(sid, 24)
		for k in pts.size() - 1:
			var a := Vector2(pts[k].x, pts[k].z) + off
			var b := Vector2(pts[k + 1].x, pts[k + 1].z) + off
			for ci in cs.size():
				var hit := _cross(cs[ci], a, b)
				if hit.is_empty():
					continue
				var p: Vector2 = hit.at - off
				crossings.append({"seg": sid, "pos": Vector3(p.x, 0.0, p.y), "corridor": ci, "s": hit.s, "closed": false,
					"county": true})


## Where segment a-b crosses corridor c: {at, s} or {}.
static func _cross(c: Dictionary, a: Vector2, b: Vector2) -> Dictionary:
	var pts: PackedVector2Array = c.pts
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(1.0)
	for i in pts.size() - 1:
		if not box.intersects(Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(1.0)):
			continue
		var hit = Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1])
		if hit != null:
			return {"at": hit, "s": c.cum[i] + pts[i].distance_to(hit)}
	return {}
