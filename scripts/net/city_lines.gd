class_name CityLines
extends MultiMeshInstance3D
## The city line between neighbors: a cream dashed line on the ground,
## drawn halfway between the two towns' nearest buildings and streets, like
## the gaps in the Neighbors logo.
##
## It's traced, not gridded: start at a spot halfway between the two towns,
## then walk sideways, pulling each step back onto the spot that is equally
## far from both, until it is far from both or a third town is nearer.
## Drawing only; who may build where is a later rule (Region.land_problem).
##
## It never holds up a frame: the work is done a little each frame (at most
## BUDGET_MS), only for towns whose outline moved and the lines near them,
## and the new lines replace the old ones when they're all traced. (It used
## to be redone all at once, every pair of towns against every other town,
## and froze games in a region of four grown towns for seconds to minutes.)

const STEP := 10.0          # metres between traced points, near the towns
## Out where the line is far from both towns it takes longer steps, this
## share of the distance (up to STEP_MAX): the line is smooth out there.
const STEP_SHARE := 0.08
const STEP_MAX := 120.0
const DASH := 6.0           # dash length, metres (a gap of STEP - DASH follows)
## Width on the ground up close; it widens as the camera pulls back so the
## line stays visible from far away, like a map overlay.
const WIDTH := 1.5
const BUCKET := 64.0        # spatial hash cell for nearest-point lookups
## Coarser cells over the fine ones, so a lookup from kilometres away checks
## a few dozen cells, not thousands (towns sit miles apart).
const COARSE := 1024.0
## Lines are drawn between towns whose nearest points are this close.
const MAX_GAP := 12000.0
## How often the lines are looked at again while towns change, seconds.
## They follow the outermost buildings, which move slowly.
const REFRESH := 15.0
## Main-thread time the lines may take a frame, milliseconds.
const BUDGET_MS := 2.0
## Points a town's outline is gathered in at a time.
const CHUNK := 400

var client: RegionClient
## Region coordinates -> this world.
var to_world: Callable

var _dirty := true
var _wait := 0.0
var _lines := []        # traced lines, region coordinates
var _width := WIDTH
var _changed := {}      # town ids whose buildings or roads changed
var _sets := {}         # town id -> PointSet of its newest outline
var _sig := {}          # town id -> PointSet.edge_sig of that outline
var _pairs := {}        # "a|b" -> lines between those two towns
var _stops := {}        # "a|b" -> [[town id, spot]] where their line stopped at a third town
var _job: Rebuild


func setup(c: RegionClient, world: Callable) -> void:
	client = c
	to_world = world


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.06, DASH)
	mm.mesh = box
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Brand.CITY_LINE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for id in client.region.cities:
		_watch(id)
	client.city_added.connect(func(id):
		_watch(id)
		_dirty = true)


func _watch(id: String) -> void:
	_changed[id] = true
	var sim: CitySim = client.region.cities[id].sim
	sim.buildings_changed.connect(func():
		_changed[id] = true
		_dirty = true)
	sim.network.changed.connect(func():
		_changed[id] = true
		_dirty = true)


func _process(delta: float) -> void:
	_wait -= delta
	if _job == null and _dirty and _wait <= 0.0:
		_dirty = false
		_wait = REFRESH
		_job = Rebuild.new(self, _changed.keys())
		_changed = {}
	if _job != null:
		var t := Perf.now()
		if _job.step(BUDGET_MS):
			_job = null
			_lines = []
			var keys := _pairs.keys()
			keys.sort()
			for k in keys:
				_lines.append_array(_pairs[k])
			_place()
		Perf.add("frame.city_lines", t)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var w := maxf(WIDTH, cam.global_position.y * 0.004)
		if absf(w - _width) > _width * 0.15:
			_width = w
			_place()


func _place() -> void:
	var dashes := []
	for line in _lines:
		dashes.append_array(_dashes(line))
	multimesh.instance_count = dashes.size()
	for n in dashes.size():
		multimesh.set_instance_transform(n, dashes[n])


## Lines traced so far, by pair of towns (for the tools).
func lines() -> Array:
	return _lines


## True while a rebuild is under way.
func busy() -> bool:
	return _job != null


## One pass over the towns: their outlines gathered again where they
## changed, then the lines of every pair near a change traced, all a little
## at a time (step). Kept apart from the drawing so a tool can time it.
class Rebuild:
	var owner: CityLines
	var _todo := []      # town ids whose outline to gather again
	var _gather: Gather
	var _moved := {}     # town ids whose outline did move
	var _queue := []     # [a, b] (or [a, b, seeds]) pairs left to trace
	var _blocked := []   # [a, b] pairs a third town stands between
	var _tracer: Tracer
	var _pair := []
	var _stage := 0

	func _init(o: CityLines, changed: Array) -> void:
		owner = o
		_todo = changed.filter(func(id): return owner.client.region.cities.has(id))
		_todo.sort()
		# Towns gone from the region: their outlines go (and _plan drops
		# their lines).
		for id in owner._sets.keys():
			if not owner.client.region.cities.has(id):
				owner._sets.erase(id)
				owner._sig.erase(id)

	## Works until `budget_ms` is used up; true once it's all done.
	func step(budget_ms: float) -> bool:
		var end := Time.get_ticks_usec() + int(budget_ms * 1000.0)
		while Time.get_ticks_usec() < end:
			if _stage == 0:
				if _gather == null:
					if _todo.is_empty():
						_stage = 1
						_plan()
						continue
					var id: String = _todo.pop_front()
					_gather = Gather.new(owner.client.region.cities[id], id)
				if _gather.step():
					_took(_gather)
					_gather = null
			elif _stage == 1:
				if _tracer == null:
					if _queue.is_empty():
						if _blocked.is_empty():
							return true
						_seeded()
						if _queue.is_empty():
							return true
					_pair = _queue.pop_front()
					var others := []
					for k in owner._sets:
						if k != _pair[0] and k != _pair[1] and _near(owner._sets[k], owner._sets[_pair[0]], 2.0) \
								and _near(owner._sets[k], owner._sets[_pair[1]], 2.0):
							others.append(owner._sets[k])
					_tracer = Tracer.new(owner._sets[_pair[0]], owner._sets[_pair[1]], others,
						_pair[2] if _pair.size() > 2 else [])
				if _tracer.step():
					var key := _key(_pair[0], _pair[1])
					owner._pairs[key] = _tracer.lines
					# Where its walks stopped at a third town, by that town.
					var stops := []
					for st in _tracer.stops:
						for k in owner._sets:
							if owner._sets[k] == st[0]:
								stops.append([k, st[1]])
					owner._stops[key] = stops
					if _tracer.blocked and _pair.size() == 2:
						_blocked.append([_pair[0], _pair[1]])
					_tracer = null
		return false

	## The blocked pairs again, each from the spots where the lines of one
	## of the pair and the town in the way stopped (three towns meet there).
	func _seeded() -> void:
		for ab in _blocked:
			var seeds := []
			for key in owner._stops:
				var xy: PackedStringArray = key.split("|")
				for st in owner._stops[key]:
					# A line of a (or b) that stopped at b (or a).
					if (st[0] == ab[1] and ab[0] in xy) or (st[0] == ab[0] and ab[1] in xy):
						seeds.append(st[1])
			if not seeds.is_empty():
				_queue.append([ab[0], ab[1], seeds])
		_blocked = []

	func _took(g: Gather) -> void:
		var id: String = g.city_id
		# Only its edge counts: a town that built inside itself keeps its lines.
		var sig := g.edge_sig
		if g.points.is_empty():
			owner._sets.erase(id)
			owner._sig.erase(id)
			_moved[id] = true
		elif owner._sig.get(id, 0) != sig or not owner._sets.has(id):
			owner._sets[id] = g.set_of
			owner._sig[id] = sig
			_moved[id] = true

	## The pairs to trace: those near each other, where one of them or a
	## town near both of them moved. Pairs of towns gone are dropped.
	func _plan() -> void:
		for k in owner._pairs.keys():
			var ab: PackedStringArray = k.split("|")
			if not owner._sets.has(ab[0]) or not owner._sets.has(ab[1]):
				owner._pairs.erase(k)
				owner._stops.erase(k)
		var ids := owner._sets.keys()
		ids.sort()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: String = ids[i]
				var b: String = ids[j]
				if not _near(owner._sets[a], owner._sets[b]):
					owner._pairs.erase(_key(a, b))
					owner._stops.erase(_key(a, b))
					continue
				var again := _moved.has(a) or _moved.has(b) or not owner._pairs.has(_key(a, b))
				for m in _moved:
					if again:
						break
					if owner._sets.has(m) and _near(owner._sets[m], owner._sets[a]) and _near(owner._sets[m], owner._sets[b]):
						again = true
				if again:
					_queue.append([a, b])

	static func _key(a: String, b: String) -> String:
		return a + "|" + b

	## Whether two towns' outlines come within `times` MAX_GAP of each other.
	static func _near(a: PointSet, b: PointSet, times := 1.0) -> bool:
		return a.box.grow(MAX_GAP * times).intersects(b.box)


## A town's outline (city_points), gathered a few hundred points at a time.
class Gather:
	var city_id := ""
	var points := PackedVector2Array()
	var set_of: PointSet
	var _sim: CitySim
	var _o := Vector2.ZERO
	var _keys := []
	var _segs := []
	var _out := {}   # segment ids of the country roads out of town
	var _i := 0
	var _stage := 0
	var _cells := []
	## PointSet.edge_sig of the outline, once it's all in.
	var edge_sig := 0

	func _init(city: Dictionary, id := "") -> void:
		_sim = city.sim
		_o = city.origin
		city_id = id
		_keys = _sim.buildings.keys()
		_segs = _sim.network.segments.keys()

	## Gathers some more; true once the town's outline is all in.
	func step() -> bool:
		match _stage:
			0:
				var stop := mini(_i + CHUNK * 4, _keys.size())
				for n in range(_i, stop):
					var key = _keys[n]
					if _sim.lots.has(key) and _sim.buildings.has(key):
						var p: Vector3 = _sim.lots[key].pos
						points.append(_o + Vector2(p.x, p.z))
				_i = stop
				if _i >= _keys.size():
					_stage = 1
					_out = CityLines.country_roads(_sim)
					_i = 0
			1:
				var stop := mini(_i + CHUNK, _segs.size())
				var keep_out := points.is_empty() and _out.size() >= _segs.size()
				for n in range(_i, stop):
					var seg = _segs[n]
					if not _sim.network.segments.has(seg) or (_out.has(seg) and not keep_out):
						continue
					for p in _sim.network.sample_segment(seg, 6):
						points.append(_o + Vector2(p.x, p.z))
				_i = stop
				if _i >= _segs.size():
					_stage = 2
					_i = 0
			2:
				if set_of == null:
					set_of = PointSet.new(PackedVector2Array())
				var stop := mini(_i + CHUNK * 4, points.size())
				set_of.add(points, _i, stop)
				_i = stop
				if _i >= points.size():
					_stage = 3
					_i = 0
					_cells = set_of.cells.keys()
			3:
				# Its edge's number (PointSet.edge_sig), a few cells at a time.
				var stop := mini(_i + CHUNK, _cells.size())
				for n in range(_i, stop):
					edge_sig = set_of.add_edge_sig(edge_sig, _cells[n])
				_i = stop
				if _i >= _cells.size():
					return true
		return false


## Where a town has built, in region coordinates: its buildings and its
## streets, but not the county roads running out of town to its neighbors
## (they meet the neighbors' halfway, which would put the line right at the
## town's edge). A brand-new town, all county road, is its roads.
static func city_points(city: Dictionary) -> PackedVector2Array:
	var g := Gather.new(city)
	while not g.step():
		pass
	return g.points


## The segments of the county roads out of a town: from each of its region
## links, along the road for as long as no other road joins it.
static func country_roads(sim: CitySim) -> Dictionary:
	var at := {}  # node -> [segment ids]
	for id in sim.network.segments:
		var s: Dictionary = sim.network.segments[id]
		for n in [s.a, s.b]:
			if not at.has(n):
				at[n] = []
			at[n].append(id)
	var out := {}
	for link in sim.region_links:
		var node: int = link
		var came := -1
		for guard in 1000:
			var segs: Array = at.get(node, [])
			var next := -1
			for s in segs:
				if s != came and not out.has(s):
					next = s
			# On along the road only while it's just the road (two ends; one
			# at the link itself).
			if next == -1 or segs.size() > (1 if came == -1 else 2):
				break
			out[next] = true
			var seg: Dictionary = sim.network.segments[next]
			node = seg.b if seg.a == node else seg.a
			came = next
	return out


## The city lines between two towns, as lists of points (region coordinates).
static func trace(a: PointSet, b: PointSet, others: Array) -> Array:
	var t := Tracer.new(a, b, others)
	while not t.step():
		pass
	return t.lines


## Traces the lines between two towns a little at a time: first a starting
## spot halfway between them that no third town is nearer, then a walk each
## way from it along the line.
##
## The start is looked for where the towns come nearest each other. If a
## third town stands in the way all along there, the pair is "blocked": a
## line between them, if there is one, runs round the side of that town,
## and starts where one of that town's own lines stopped (three towns meet
## there). Such spots are handed in as `seeds`.
class Tracer:
	var a: PointSet
	var b: PointSet
	var others: Array
	var lines := []
	## True when no start was found where the towns come nearest.
	var blocked := false
	## Where a walk stopped because a third town was nearer: [that town's
	## PointSet, the last spot on the line] (a seed for the lines it has).
	var stops := []
	var _seeds := []
	var _stage := 0
	var _coarse := []     # [lower bound, coarse key] of a's coarse cells, nearest first
	var _keys := []       # a's coarse keys still to bound
	var _ci := 0
	var _fine := []       # fine cell keys of the coarse cell being looked through
	var _fi := 0
	var _tried := 0       # cells looked at without finding a start
	var _best := INF
	var _pa := Vector2.ZERO
	var _pb := Vector2.ZERO
	var _start := Vector2.ZERO
	var _side := Vector2.ZERO
	var _reach := 0.0
	var _halves := []
	var _pts := PackedVector2Array()
	var _p := Vector2.ZERO
	var _heading := Vector2.ZERO
	var _step := STEP
	var _n := 0

	## Cells looked at, nearest first, before a pair counts as blocked.
	const TRIES := 48

	func _init(pa: PointSet, pb: PointSet, o: Array, seeds := []) -> void:
		a = pa
		b = pb
		others = o
		_seeds = seeds.duplicate()
		_keys = a.coarse.keys()
		if not _seeds.is_empty():
			_stage = 4

	## Does a bit more; true once the lines are traced.
	func step() -> bool:
		match _stage:
			0:
				# a's coarse cells, nearest b first, one a step.
				if _keys.is_empty():
					_coarse.sort_custom(func(x, y): return x[0] < y[0])
					_stage = 1
				else:
					var k: Vector2i = _keys.pop_back()
					var centre := (Vector2(k) + Vector2(0.5, 0.5)) * COARSE
					_coarse.append([centre.distance_to(b.nearest(centre)) - COARSE * 0.7072, k])
			1:
				_scan()
			2:
				_walk()
			4:
				_from_seed()
			_:
				return true
		return _stage == 3

	## The nearest pair of points (a cell's point nearest b, and b's point
	## nearest that) whose halfway spot no third town is nearer: one fine
	## cell of a a step, the coarse cells nearest b first, done once no cell
	## can hold a nearer pair (or, blocked, after TRIES cells in a row).
	func _scan() -> void:
		var limit := minf(_best, MAX_GAP)
		if _best == INF and _tried >= TRIES:
			blocked = true
			_stage = 3
			return
		if _fi >= _fine.size():
			if _ci >= _coarse.size() or _coarse[_ci][0] >= limit:
				blocked = _best == INF and _tried > 0
				_begin()
				return
			_fine = a.coarse[_coarse[_ci][1]]
			_ci += 1
			_fi = 0
			return
		var c: Vector2i = _fine[_fi]
		_fi += 1
		var centre := (Vector2(c) + Vector2(0.5, 0.5)) * BUCKET
		var toward := b.nearest(centre)
		if centre.distance_to(toward) - BUCKET * 0.7072 >= limit:
			return
		# The cell's point nearest b's point nearest the cell, then b's
		# point nearest that.
		var p := Vector2.ZERO
		var pd := INF
		var pts: PackedVector2Array = a.cells[c]
		for q in pts:
			var d := q.distance_squared_to(toward)
			if d < pd:
				pd = d
				p = q
		var q := b.nearest(p)
		var d := p.distance_to(q)
		if d < _best:
			if CityLines._is_ours((p + q) * 0.5, d * 0.5, others):
				_best = d
				_pa = p
				_pb = q
			elif _best == INF:
				_tried += 1

	func _begin() -> void:
		var gap := _pa.distance_to(_pb)
		if _best == INF or gap > MAX_GAP or gap < 0.01:
			_stage = 3
			return
		_go((_pa + _pb) * 0.5, (_pb - _pa).normalized().orthogonal(), gap)

	func _go(start: Vector2, side: Vector2, gap: float) -> void:
		_start = start
		_side = side
		# Far from both towns, the line has done its job.
		_reach = gap + 300.0
		_halves = []
		_new_half(_side)
		_stage = 2

	## Starts from a spot where three towns meet: a step off it along the
	## line between these two, on the side away from the third.
	func _from_seed() -> void:
		if _seeds.is_empty():
			_stage = 3
			return
		var seed: Vector2 = _seeds.pop_front()
		var at := CityLines._settle(a, b, seed)
		var na := a.nearest(at)
		var nb := b.nearest(at)
		var gap := na.distance_to(nb)
		if gap > MAX_GAP or gap < 0.01:
			return
		# The walk that stopped took long steps out there: the spot where the
		# three meet can be a step or two on.
		var side := (nb - na).normalized().orthogonal()
		for far in [2.0, 6.0, 15.0, 40.0]:
			for dir in [side, -side]:
				var q := CityLines._settle(a, b, at + dir * STEP * far)
				if CityLines._is_ours(q, a.nearest_distance(q), others):
					_go(q, dir, gap)
					return

	func _new_half(dir: Vector2) -> void:
		_pts = PackedVector2Array([_start])
		_p = _start
		_heading = dir
		_step = STEP
		_n = 0

	## One step along the line.
	func _walk() -> void:
		var q := CityLines._settle(a, b, _p + _heading * _step)
		var da := a.nearest_distance(q)
		_n += 1
		var ours := CityLines._is_ours(q, da, others)
		if _n > 1500 or da > _reach or not ours or q.distance_to(_p) < _step * 0.3:
			if not ours:
				for o in others:
					if (o as PointSet).has_within(q, da):
						stops.append([o, _p])
						break
			_halves.append(_pts)
			if _halves.size() == 1:
				_new_half(-_side)
				return
			var line := PackedVector2Array()
			var back: PackedVector2Array = _halves[1]
			for i in range(back.size() - 1, 0, -1):
				line.append(back[i])
			line.append_array(_halves[0])
			lines = [line] if line.size() > 1 else []
			_stage = 3
			return
		_step = clampf(da * STEP_SHARE, STEP, STEP_MAX)
		_heading = (q - _p).normalized()
		_pts.append(q)
		_p = q


## Slides a point onto the spot equally far from both towns.
static func _settle(a: PointSet, b: PointSet, p: Vector2) -> Vector2:
	for i in 6:
		var na := a.nearest(p)
		var nb := b.nearest(p)
		var da := p.distance_to(na)
		var db := p.distance_to(nb)
		var diff := da - db
		if absf(diff) < 0.5:
			break
		var grad := (p - na) / maxf(da, 0.001) - (p - nb) / maxf(db, 0.001)
		var g2 := grad.length_squared()
		if g2 < 0.0001:
			break
		p -= grad * (diff / g2)
	return p


## True while no third town is nearer than these two.
static func _is_ours(p: Vector2, d: float, others: Array) -> bool:
	for o in others:
		if (o as PointSet).has_within(p, d):
			return false
	return true


## Dashes laid along a line, flat on the ground.
func _dashes(line: PackedVector2Array) -> Array:
	# One dash every STEP metres, the long steps out in the country split up.
	var even := PackedVector2Array()
	for i in line.size() - 1:
		var n := maxi(1, roundi(line[i].distance_to(line[i + 1]) / STEP))
		for k in n:
			even.append(line[i].lerp(line[i + 1], float(k) / n))
	if not line.is_empty():
		even.append(line[line.size() - 1])
	var out := []
	for i in even.size() - 1:
		var p0: Vector3 = to_world.call(even[i])
		var p1: Vector3 = to_world.call(even[i + 1])
		p0.y = Terrain.ground_y(p0.x, p0.z)
		p1.y = Terrain.ground_y(p1.x, p1.z)
		var mid := (p0 + p1) * 0.5 + Vector3(0, 0.3, 0)
		var basis := Basis.looking_at((p1 - p0).normalized(), Vector3.UP) if p0.distance_to(p1) > 0.01 else Basis()
		out.append(Transform3D(basis.scaled_local(Vector3(_width, 1, 1)), mid))
	return out


## Points with a spatial hash, for quick nearest-point lookups: fine cells
## for nearby points and coarse cells over them for faraway ones.
class PointSet:
	var cells := {}  # Vector2i -> PackedVector2Array (fine, BUCKET)
	var coarse := {}  # Vector2i -> Array of fine cell keys (COARSE)
	## The box around every point.
	var box := Rect2()
	var _empty := true

	func _init(pts: PackedVector2Array) -> void:
		add(pts, 0, pts.size())

	## Takes in points from..to of `pts`.
	func add(pts: PackedVector2Array, from: int, to: int) -> void:
		var per := int(COARSE / BUCKET)
		for i in range(from, to):
			var p := pts[i]
			if _empty:
				box = Rect2(p, Vector2.ZERO)
				_empty = false
			else:
				box = box.expand(p)
			var c := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
			if not cells.has(c):
				cells[c] = PackedVector2Array()
				var k := Vector2i(floori(float(c.x) / per), floori(float(c.y) / per))
				if not coarse.has(k):
					coarse[k] = []
				coarse[k].append(c)
			cells[c].append(p)

	## A number for the points along the edge (in cells with an empty cell
	## beside them): it changes when the edge moves, not when the town builds
	## inside itself. The same whatever order the points came in.
	func edge_sig() -> int:
		var sig := 0
		for c: Vector2i in cells:
			sig = add_edge_sig(sig, c)
		return sig

	## edge_sig with cell `c` added in.
	func add_edge_sig(sig: int, c: Vector2i) -> int:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if not cells.has(c + Vector2i(dx, dy)):
					for q in cells[c]:
						sig = (sig + hash(q)) & 0x7fffffffffff
					return sig
		return sig

	func nearest(p: Vector2) -> Vector2:
		return _find(p, INF, false)

	func nearest_distance(p: Vector2) -> float:
		return p.distance_to(nearest(p))

	## Whether any point is nearer p than r (stops at the first one).
	func has_within(p: Vector2, r: float) -> bool:
		if r <= 0.0:
			return false
		var q := _find(p, r * r, true)
		return q.distance_squared_to(p) < r * r and _found

	var _found := false

	## The nearest point no further than sqrt(limit2) (p itself, with
	## _found false, if none); with `first`, any point that near.
	func _find(p: Vector2, limit2: float, first: bool) -> Vector2:
		var best := limit2
		var out := p
		_found = false
		# Nearby first: the fine cells around the point.
		var c := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
		for ring in 3:
			for x in range(c.x - ring, c.x + ring + 1):
				for y in range(c.y - ring, c.y + ring + 1):
					if ring > 0 and absi(x - c.x) != ring and absi(y - c.y) != ring:
						continue
					var cell: PackedVector2Array = cells.get(Vector2i(x, y), PackedVector2Array())
					for q in cell:
						var d := p.distance_squared_to(q)
						if d < best:
							best = d
							out = q
							_found = true
							if first:
								return out
			# Cells further out are at least `ring` cells away.
			if best < INF and ring * BUCKET >= sqrt(best):
				return out
		# Far away: rings of coarse cells, skipping any cell (coarse or
		# fine) that can't hold anything nearer than the best so far; the
		# fine cells of a ring nearest first.
		var k := Vector2i(floori(p.x / COARSE), floori(p.y / COARSE))
		for ring in 64:
			if best < INF and (ring - 1) * COARSE >= sqrt(best):
				break
			var near := []
			for x in range(k.x - ring, k.x + ring + 1):
				for y in range(k.y - ring, k.y + ring + 1):
					if ring > 0 and absi(x - k.x) != ring and absi(y - k.y) != ring:
						continue
					var fine: Array = coarse.get(Vector2i(x, y), [])
					if fine.is_empty() or _box_d2(p, Vector2(x, y) * COARSE, COARSE) >= best:
						continue
					for f: Vector2i in fine:
						var bd := _box_d2(p, Vector2(f) * BUCKET, BUCKET)
						if bd < best:
							near.append([bd, f])
			near.sort_custom(func(u, v): return u[0] < v[0])
			for e in near:
				if e[0] >= best:
					break
				var pts: PackedVector2Array = cells[e[1]]
				for q in pts:
					var d := p.distance_squared_to(q)
					if d < best:
						best = d
						out = q
						_found = true
						if first:
							return out
		return out

	## Squared distance from p to the square at `corner` with side `size`.
	static func _box_d2(p: Vector2, corner: Vector2, size: float) -> float:
		var dx := maxf(maxf(corner.x - p.x, 0.0), p.x - corner.x - size)
		var dy := maxf(maxf(corner.y - p.y, 0.0), p.y - corner.y - size)
		return dx * dx + dy * dy
