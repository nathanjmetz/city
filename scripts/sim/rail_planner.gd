class_name RailPlanner
extends RefCounted
## How a rail leader lays out new track: like a railroad's engineer, it looks
## for the cheapest line that a train can really run on, under US rules.
##
## - Curves no tighter than the line allows (AREMA): 12° (146 m radius) on
##   industry track, 6° (291 m) on the main line.
## - Grades no steeper than 3% on industry track and 1.5% on the main line.
## - Roads are crossed at grade only nearly square (70° or more), never a
##   highway, and not within 30 m (100 ft) of a road junction, so cars
##   waiting at a junction don't queue onto the tracks (FHWA crossing
##   handbook and MUTCD).
## - Never through anything the player built or zoned with a building on it,
##   a service, a farmyard or field, a company's yard or pads, reserved land
##   or another depot. Empty zoned lots can be taken, but only with a permit.
##
## The search is a hybrid A*: it drives a "track-laying car" forward in
## 40 m arcs (straight, or curving at the tightest allowed radius), so every
## line it finds is smooth and buildable. Deterministic.

const CELL := 10.0         # obstacle map cell, metres
const STEP := 40.0         # one arc of new track
const XY := 20.0           # search memory cell
const BINS := 36           # heading buckets (10° each)
const MAX_EXPAND := 40000
## Half the width of ground the track needs (ballast, ditches, clearance).
const CLEAR := 6.0
## Crossings: the angle a road must be crossed at, and how far from a junction.
const MIN_CROSS_ANGLE := 70.0
const JUNCTION_GAP := 30.0
## Curve and grade limits by kind of track (AREMA practice).
const LIMITS := {
	"spur": {"radius": 146.0, "grade": 0.03, "degree": 12},
	"main": {"radius": 291.0, "grade": 0.015, "degree": 6},
}

enum Cell { FREE, BLOCKED, ZONED, TRACK, JUNCTION }

## The deepest cut or highest fill new track may take, metres, and what
## each metre of it costs per metre of track (earthwork).
const MAX_CUT := 8.0
const CUT_PER_M := 250.0
## Track over water goes on a bridge, this many times dearer.
const BRIDGE_FACTOR := 4.0

var sim: CitySim
var kind := "spur"
## Extra cost for each road crossing (the leader's dislike of permits).
var crossing_penalty := 0.0
var cost_per_m := 620.0
var _grid := {}   # Vector2i -> Cell
var _road := {}   # Vector2i -> seg id (road right of way)
var _own := {}    # Vector2i -> true where this depot's own track may be joined


## The level the land is graded to at a point (city coordinates).
func height(p: Vector3) -> float:
	return Terrain.base(p.x + sim.terrain_offset.x, p.z + sim.terrain_offset.y)


func _wet(p: Vector2) -> bool:
	return Terrain.is_water(p.x + sim.terrain_offset.x, p.y + sim.terrain_offset.y)


## Builds the map of what new track must avoid. `allow` is a list of
## polygons the line may enter anyway (its own depot yard, its target).
func setup(s: CitySim, rail_kind: String, allow: Array) -> void:
	sim = s
	kind = rail_kind
	_grid.clear()
	_road.clear()
	_own.clear()
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if sim.buildings.has(key):
			_fill(lot.corners, Cell.BLOCKED)
		elif sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE:
			_fill(lot.corners, Cell.ZONED)
	for id in sim.services.buildings:
		_fill(sim.services.footprint(id), Cell.BLOCKED)
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		_fill(sim.farms._yard(f), Cell.BLOCKED)
		for c in f.cells:
			_fill(Farms.cell_corners(f, c), Cell.BLOCKED)
	for id in sim.industry.sites:
		var st: Dictionary = sim.industry.sites[id]
		_fill(sim.industry._yard(st), Cell.BLOCKED)
		for c in st.pads:
			_fill(Industry.pad_corners(st, c), Cell.BLOCKED)
	for o in sim.reserves.outlines:
		if o.kind != "":
			_fill(o.points, Cell.BLOCKED)
	for id in sim.rail.depots:
		_fill(sim.rail.yard_poly(id), Cell.BLOCKED)
	for pid in sim.rail.pieces:
		var pc: Dictionary = sim.rail.pieces[pid]
		for p in pc.pts:
			_mark(p, Cell.TRACK)
	for poly in allow:
		for c in _cells_in(poly):
			_grid.erase(c)
	# Roads: their right of way, and no-go circles around junctions.
	for seg in sim.network.segments:
		var rs: Dictionary = sim.network.segments[seg]
		var hw := RoadStyle.right_of_way_half(rs.type)
		var c := sim.network.curve_of(seg)
		var n := maxi(8, ceili(c[0].distance_to(c[1]) + c[1].distance_to(c[2])) / 5)
		var pts := sim.network.sample_segment(seg, n)
		for i in pts.size():
			var p: Vector3 = pts[i]
			if absf(p.y) > 4.0:
				continue  # a bridge: track passes under it
			var t: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
			var tan := Vector2(t.x, t.z).normalized()
			var r := ceili(hw / CELL)
			var c0 := _cell(p)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var cc := c0 + Vector2i(dx, dy)
					if Vector2((cc.x + 0.5) * CELL - p.x, (cc.y + 0.5) * CELL - p.z).length() <= hw:
						_road[cc] = [seg, tan, rs.type]
	for n in sim.network.nodes:
		if sim.network.segments_at(n).size() >= 3:
			var p: Vector3 = sim.network.nodes[n]
			var r := ceili(JUNCTION_GAP / CELL)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var c := _cell(p) + Vector2i(dx, dy)
					if Vector2((c.x + 0.5) * CELL - p.x, (c.y + 0.5) * CELL - p.z).length() <= JUNCTION_GAP:
						_grid[c] = Cell.JUNCTION


## Finds a line from one of `starts` ({pos, heading, cost}) to `goal`
## ({pos, tol, heading (optional, a Vector2 the line must end along)}).
## Returns {pts (every ~10 m), crossings: [{seg, pos}], zoned (lots taken),
## length, cost, start (index into starts)} or {} if there is none.
func plan(starts: Array, goal: Dictionary) -> Dictionary:
	var R: float = LIMITS[kind].radius
	var turn := STEP / R
	var gpos: Vector2 = goal.pos
	var tol: float = goal.get("tol", STEP)
	var ghead = goal.get("heading", null)
	var states := []  # [pos, heading, g, parent, crossings, zoned, start, curv, z]
	var heap := []
	var closed := {}
	var budget := 0.0
	for i in starts.size():
		var s: Dictionary = starts[i]
		budget = maxf(budget, s.pos.distance_to(gpos))
		states.append([s.pos, float(s.heading), float(s.get("cost", 0.0)), -1, [], 0, i, 0.0, height(_v3(s.pos))])
		_push(heap, [_h(s.pos, gpos), states.size() - 1])
	budget += 2500.0
	var found := -1
	var n := 0
	while not heap.is_empty() and n < MAX_EXPAND:
		var top: Array = _pop(heap)
		var idx: int = top[1]
		var st: Array = states[idx]
		var key := Vector3i(floori(st[0].x / XY), floori(st[0].y / XY), posmod(roundi(st[1] / TAU * BINS), BINS))
		if closed.has(key):
			continue
		closed[key] = true
		n += 1
		if st[0].distance_to(gpos) <= tol and (ghead == null or Vector2.from_angle(st[1]).dot(ghead) > 0.9):
			found = idx
			break
		for k in [0.0, -1.0, 1.0]:
			var step := _arc(st[0], st[1], k / R)
			var end: Vector2 = step[0]
			var head: float = st[1] + k * turn
			if end.distance_to(starts[st[6]].pos) + end.distance_to(gpos) > budget:
				continue
			var check := _check(st, step[1], step[2])
			if check.is_empty():
				continue
			# The track keeps to its grade, cutting into rises and filling hollows.
			var ground := height(_v3(end))
			var rise: float = LIMITS[kind].grade * STEP
			var z := clampf(ground, float(st[8]) - rise, float(st[8]) + rise)
			var dz := absf(z - ground)
			if dz > MAX_CUT:
				continue
			var g: float = st[2] + STEP * cost_per_m * (1.04 if k != 0.0 else 1.0) + check.cost + dz * STEP * CUT_PER_M
			if _wet(end):
				g += STEP * cost_per_m * (BRIDGE_FACTOR - 1.0)
			# Reversing a curve straight away makes an S that trains hate.
			if k != 0.0 and st[7] == -k:
				g += STEP * cost_per_m * 0.5
			var crossings: Array = st[4] + check.crossings
			states.append([end, head, g, idx, crossings, int(st[5]) + check.zoned, st[6], k, z])
			_push(heap, [g + _h(end, gpos) * 1.8, states.size() - 1])
	if found == -1:
		return {}
	# Walk back up the chain and draw each arc.
	var chain := []
	var i := found
	while i != -1:
		chain.push_front(i)
		i = states[i][3]
	var pts := []
	var first: Array = states[chain[0]]
	pts.append(_v3(first[0]))
	for j in range(1, chain.size()):
		var prev: Array = states[chain[j - 1]]
		var cur: Array = states[chain[j]]
		var arc := _arc(prev[0], prev[1], float(cur[7]) / R)
		for p in arc[1]:
			pts.append(_v3(p))
	var last: Array = states[found]
	var seen := {}
	var crossings := []
	for c in last[4]:
		if not seen.has(c.seg):
			seen[c.seg] = true
			crossings.append(c)
	var length := (chain.size() - 1) * STEP
	return {"pts": pts, "crossings": crossings, "zoned": last[5], "length": length,
		"cost": roundi(length * cost_per_m) + crossings.size() * Balance.RAIL_CROSSING_COST,
		"start": last[6]}


## Checks a line someone drew (an edited permit): every bend at least the
## minimum radius, nothing in the way, roads crossed nearly square. Returns
## "" if it is buildable, or what's wrong in plain words.
func problem(pts: Array) -> String:
	var R: float = LIMITS[kind].radius
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i] - pts[i - 1]
		var b: Vector3 = pts[i + 1] - pts[i]
		var ang := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		var s := minf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length())
		if absf(ang) > 0.0001 and s / (2.0 * sin(absf(ang) * 0.5)) < R - 1.0:
			return "A curve is too tight: %s track needs at least %d m (%d°), AREMA." % [
				"Industry" if kind == "spur" else "Main line", int(R), LIMITS[kind].degree]
		var reach: float = pts[i + 1].distance_to(pts[0])
		if absf(height(pts[i + 1]) - height(pts[0])) > reach * LIMITS[kind].grade + MAX_CUT * 2.0:
			return "Too steep for trains: %s track climbs at most %.1f%%." % [
				"industry" if kind == "spur" else "main line", LIMITS[kind].grade * 100.0]
	for i in range(1, pts.size()):
		var p: Vector3 = pts[i]
		var c := _cell(p)
		match int(_grid.get(c, Cell.FREE)):
			Cell.BLOCKED:
				return "It runs through something already built there."
			Cell.JUNCTION:
				return "It crosses a road too close to a junction (keep 30 m, 100 ft)."
		if _road.has(c):
			var d: Vector3 = p - pts[i - 1]
			var why := _cross_problem(_road[c], atan2(d.z, d.x))
			if why != "":
				return why
	return ""


## The road crossings and empty zoned lots along a line.
func survey(pts: Array) -> Dictionary:
	var crossings := []
	var seen := {}
	var zoned := {}
	for p in pts:
		var c := _cell(p)
		if _road.has(c) and not seen.has(_road[c][0]):
			seen[_road[c][0]] = true
			crossings.append({"seg": _road[c][0], "pos": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]})
		if int(_grid.get(c, Cell.FREE)) == Cell.ZONED:
			zoned[c] = true
	return {"crossings": crossings, "zoned": zoned.size() / 6}


# --- Inside the search ------------------------------------------------------

## One arc of track: [end point, samples every 10 m (not the start), the
## heading at each sample].
static func _arc(p: Vector2, heading: float, curv: float) -> Array:
	var out := []
	var heads := []
	var steps := int(STEP / 10.0)
	var end := p
	for i in range(1, steps + 1):
		var s := STEP * i / steps
		var q: Vector2
		if curv == 0.0:
			q = p + Vector2.from_angle(heading) * s
		else:
			var r := 1.0 / curv
			var h2 := heading + s * curv
			q = p + Vector2(sin(h2) - sin(heading), -cos(h2) + cos(heading)) * r
		out.append(q)
		heads.append(heading + s * curv)
		end = q
	return [end, out, heads]


## Cost and crossings of one arc, or {} if it can't be built.
func _check(st: Array, samples: Array, heads: Array) -> Dictionary:
	var cost := 0.0
	var zoned := 0
	var crossings := []
	var prev_road := -1
	var c_prev := _cell(_v3(st[0]))
	if _road.has(c_prev):
		prev_road = int(_road[c_prev][0])
	for si in samples.size():
		var q: Vector2 = samples[si]
		var heading: float = heads[si]
		var side := Vector2.from_angle(heading).orthogonal()
		for off in [0.0, -CLEAR, CLEAR]:
			var p: Vector2 = q + side * off
			var c := _cell(_v3(p))
			match int(_grid.get(c, Cell.FREE)):
				Cell.BLOCKED:
					return {}
				Cell.ZONED:
					zoned += 1
					cost += 20_000.0
				Cell.TRACK:
					cost += 4_000.0  # running alongside track: allowed at a turnout, but not for long
				Cell.JUNCTION:
					if off == 0.0:
						return {}
		var c0 := _cell(_v3(q))
		if _road.has(c0):
			var seg := int(_road[c0][0])
			if _cross_problem(_road[c0], heading) != "":
				return {}
			if seg != prev_road:
				crossings.append({"seg": seg, "pos": [snappedf(q.x, 0.1), snappedf(q.y, 0.1)]})
				cost += Balance.RAIL_CROSSING_COST + crossing_penalty
			prev_road = seg
		else:
			prev_road = -1
	return {"cost": cost, "zoned": zoned / 6, "crossings": crossings}


## Why track can't cross a road (as cached for a cell) at this heading, or "".
static func _cross_problem(road: Array, heading: float) -> String:
	if road[2] in [RoadStyle.Type.HIGHWAY, RoadStyle.Type.RAMP]:
		return "Highways can't be crossed at grade; it needs a bridge."
	var cosang := absf((road[1] as Vector2).dot(Vector2.from_angle(heading)))
	if rad_to_deg(acos(clampf(cosang, 0.0, 1.0))) < MIN_CROSS_ANGLE:
		return "Roads are crossed nearly square (at least 70°), as US crossing rules ask."
	return ""


func _h(p: Vector2, g: Vector2) -> float:
	return p.distance_to(g) * cost_per_m


func _fill(poly: PackedVector2Array, code: int) -> void:
	for c in _cells_in(poly):
		if int(_grid.get(c, Cell.FREE)) != Cell.BLOCKED:
			_grid[c] = code


func _mark(p: Vector3, code: int) -> void:
	var c := _cell(p)
	if not _grid.has(c):
		_grid[c] = code


static func _cells_in(poly: PackedVector2Array) -> Array:
	var out := []
	if poly.is_empty():
		return out
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL), poly):
				out.append(Vector2i(x, y))
	return out


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= item[0]:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var r := l + 1
		var m := r if r < n and heap[r][0] < heap[l][0] else l
		if heap[m][0] >= last[0]:
			break
		heap[i] = heap[m]
		i = m
	heap[i] = last
	return top
