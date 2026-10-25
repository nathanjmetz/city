class_name TreeGrower
extends RefCounted
## Grows a tree's branches the way real trees find their light: by space
## colonization (Runions, Lane and Prusinkiewicz 2007, "Modeling Trees with
## a Space Colonization Algorithm"). Points of open air are scattered
## through the crown a kind fills (TreeKinds: a sugar maple's round dome, a
## white oak's broad spread, a red cedar's spire). Each shoot tip grows a
## step toward the points nearest it, and a point is used up once a twig
## reaches it. Where several points pull on one node it forks.
##
## The crown grows year by year with the tree (its height from the real
## growth curve), so new air opens up around the edge each year and the
## tree reaches into it. A node remembers the year it grew, so one growth
## run gives the same tree at every age: the 10-year-old is the 60-year-old's
## younger self, not a different tree. Low limbs die off as the crown lifts.
##
## Limb thickness follows the pipe model (Shinozaki 1964; da Vinci's rule):
## a limb carries the pipes of every twig beyond it, so its cross-section is
## the sum of theirs (radius^n = sum of child radius^n, n = PIPE_N). The
## trunk is then scaled to the kind's real trunk thickness at that age.
##
## Everything comes from (kind, variant) through a seeded random number
## generator: the same seed always grows the same tree. Growing is done in
## slices (step()) so it can be spread over frames.

const VARIANTS := 3
## Pipe model exponent: 2 is da Vinci's area rule; measured trees run 2 to 3.
const PIPE_N := 2.3
## The thinnest twig the model grows, metres of radius.
const TIP_R := 0.004
## How many points of air a full-grown crown holds (more = finer branching,
## slower to grow).
const POINTS := 2600
## Twig length per growth step, as a share of the tree's height, and its limits.
const STEP_SHARE := 1.0 / 48.0
const STEP_MIN := 0.07
const STEP_MAX := 0.6
## A point pulls on nodes within INFLUENCE steps and is used up within KILL steps.
const INFLUENCE := 12.0
const KILL := 1.6
const CELL := 4.0
## The angle (degrees) a new side shoot is turned to, where it differs from
## the reference angle (TreeKinds angle): limbs bend after they leave (the
## light pulls wide crowns' limbs out and upright ones up), so a few kinds
## start their shoots off further one way to end up at the real angle,
## measured a metre and a half out (tests/test_tree_growth.gd).
const STEER := {1: [70.0, 100.0], 2: [36.0, 52.0], 3: [82.0, 100.0], 6: [10.0, 30.0], 10: [18.0, 38.0]}

var sp := 0
var variant := 0
var done := false

# The skeleton, in growth order (every node's parent comes before it).
var pos := PackedVector3Array()
var parent := PackedInt32Array()
var born := PackedFloat32Array()
var dir := PackedVector3Array()
var nchild := PackedInt32Array()
## 1 for nodes on the leader: the first stem up from the ground.
var leader := PackedByteArray()

var _rng := RandomNumberGenerator.new()
var _pts := PackedVector3Array()
var _appear := PackedFloat32Array()
var _alive := PackedByteArray()
var _closest := PackedInt32Array()
var _cdist := PackedFloat32Array()
var _next_pt := 0
var _pgrid := {}
var _ngrid := {}
var _age := 0.0
var _ages := PackedFloat32Array()
var _age_i := 0
var _lobes := []
var _squash := Vector2.ONE
var _lean := Vector3.ZERO
var _tip := 0  # the leader's highest node


func _init(kind := 0, var_seed := 0) -> void:
	sp = kind
	variant = posmod(var_seed, VARIANTS)
	_rng.seed = hash([sp, variant, 7121])
	# Ages grown: every half year while young, then yearly, then every two.
	var a := 0.5
	while a <= TreeKinds.MAX_AGE:
		_ages.append(a)
		a += 0.5 if a < 12.0 else (1.0 if a < 50.0 else 2.0)
	var k := TreeKinds.kind(sp)
	# The big limbs: lobes of the crown the points gather in, so the crown
	# breaks into a few major limbs with gaps between (real crowns are
	# clumped, never an even ball of twigs).
	for i in int(k.lobes):
		var ang := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(k.lobes)
		_lobes.append(Vector3(cos(ang) * _rng.randf_range(0.45, 0.8), _rng.randf_range(0.3, 0.85), sin(ang) * _rng.randf_range(0.45, 0.8)))
	if int(k.lobes) > 0:
		_lobes.append(Vector3(0, 0.95, 0))
	_squash = Vector2(_rng.randf_range(0.88, 1.12), _rng.randf_range(0.88, 1.12))
	_lean = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * (0.05 if not k.leader else 0.01)


## Scatters the points and plants the seed: the first slice of growing.
func _sow() -> void:
	_sample_points()
	pos.append(Vector3.ZERO)
	parent.append(-1)
	born.append(0.0)
	dir.append(Vector3.UP)
	nchild.append(0)
	leader.append(1)
	_file_node(0)


## Grows the whole tree at once (tests and tools).
static func grown(kind: int, var_seed: int) -> TreeGrower:
	var g := TreeGrower.new(kind, var_seed)
	while not g.done:
		g.step(1_000_000)
	return g


## Grows for up to `budget_us` microseconds. Returns true when finished.
func step(budget_us: int) -> bool:
	var start := Time.get_ticks_usec()
	if pos.is_empty():
		_sow()
		if Time.get_ticks_usec() - start > budget_us:
			return false
	while _age_i < _ages.size():
		_grow_year(_ages[_age_i], _ages[_age_i - 1] if _age_i > 0 else 0.0)
		_age_i += 1
		if Time.get_ticks_usec() - start > budget_us:
			return false
	_straighten()
	done = true
	_pts = PackedVector3Array()
	_pgrid.clear()
	_ngrid.clear()
	return true


## Real limbs grow in long sweeps, not in the zigzag steps the growth
## takes: each node is eased toward the line between its parent and its
## main child, the more so the more tree it carries (a trunk is straighter
## than a twig).
func _straighten() -> void:
	var n := pos.size()
	var weight := PackedFloat32Array()
	weight.resize(n)
	weight.fill(1.0)
	for i in range(n - 1, 0, -1):
		weight[parent[i]] += weight[i]
	var main := PackedInt32Array()
	main.resize(n)
	main.fill(-1)
	for i in range(1, n):
		var p := parent[i]
		if main[p] < 0 or weight[i] > weight[main[p]]:
			main[p] = i
	for pass_i in 6:
		var moved := pos.duplicate()
		for i in range(1, n):
			var c := main[i]
			if c < 0:
				continue
			var mid := (pos[parent[i]] + pos[c]) * 0.5
			var w := clampf(0.25 + log(weight[i]) * 0.1, 0.25, 0.8)
			moved[i] = pos[i].lerp(mid, w)
		pos = moved


# ------------------------------------------------------------------ crown

## The crown at an age: [top, crown base, radius] in metres.
func _crown(age: float) -> Vector3:
	var h := TreeKinds.height(sp, age)
	# The points reach a little past the crown's edge: twigs stop short of
	# the last points they chase, and the leaves fill the rest.
	var pad := 1.0 if TreeKinds.kind(sp).leader else 1.15
	return Vector3(h * 1.03, TreeKinds.crown_base(sp, age), h * TreeKinds.wide_at(sp, age) * 0.5 * pad)


## How far out the crown reaches at a height share t (0 at the crown base,
## 1 at the top), as a share of its radius.
func profile(t: float) -> float:
	return crown_profile(sp, t)


static func crown_profile(sp: int, t: float) -> float:
	if t < 0.0 or t > 1.0:
		return 0.0
	var k := TreeKinds.kind(sp)
	match int(k.crown):
		TreeKinds.Crown.ROUND:
			var c := 0.45
			var u := (t - c) / ((1.0 - c) if t > c else c)
			return sqrt(maxf(1.0 - u * u, 0.0))
		TreeKinds.Crown.SPREAD:
			# A broad dome: widest low, flat-topped.
			var c := 0.32
			var u := (t - c) / ((1.0 - c) if t > c else c)
			return pow(maxf(1.0 - u * u, 0.0), 0.4)
		TreeKinds.Crown.VASE:
			# Narrow where the limbs leave the trunk, widest high up.
			var c := 0.66
			if t < c:
				return 0.3 + 0.7 * sqrt(t / c)
			var u := (t - c) / (1.0 - c)
			return sqrt(maxf(1.0 - u * u, 0.0))
		TreeKinds.Crown.CONE:
			return minf(1.0, (1.0 - t) * 1.08)
		TreeKinds.Crown.COLUMN:
			# A narrow spire, rounded at the shoulders.
			return pow(maxf(1.0 - t, 0.0), 0.62) * minf(1.0, 0.75 + t * 2.0)
	return 0.0


func inside(p: Vector3, c: Vector3) -> bool:
	if c.x - c.y < 0.05:
		return false
	var t := (p.y - c.y) / (c.x - c.y)
	var r := c.z * profile(t)
	if r <= 0.0:
		return false
	var q := Vector2(p.x / _squash.x, p.z / _squash.y)
	return q.length() <= r


## Scatters the points of air with the year each opens up: points of a
## young crown first, then shells around it as it grows. Denser where the
## tree is small, so a sapling has twigs at its own scale.
func _sample_points() -> void:
	var k := TreeKinds.kind(sp)
	var raw := []
	var prev := Vector3.ZERO
	var total_vol := 0.0
	var shells := []
	for i in _ages.size():
		var a: float = _ages[i]
		var c := _crown(a)
		var box := Vector3(c.z * 2.0 * 1.15, c.x - c.y, c.z * 2.0 * 1.15)
		var tries := 160
		var hits := 0
		var cand := []
		for j in tries:
			var p := Vector3(_rng.randf_range(-0.5, 0.5) * box.x, c.y + _rng.randf() * box.y, _rng.randf_range(-0.5, 0.5) * box.z)
			if inside(p, c) and (i == 0 or not inside(p, prev)):
				hits += 1
				cand.append(p)
		var vol := box.x * box.y * box.z * float(hits) / tries
		var step := _step_len(a)
		# Points per cubic metre for this size of twig.
		var want := vol / pow(step * 3.2, 3.0)
		shells.append([a, c, prev, want])
		total_vol += want
		prev = c
	# Scale so the whole life holds about POINTS points.
	var scale := float(POINTS) / maxf(total_vol, 1.0)
	for s in shells:
		var a: float = s[0]
		var c: Vector3 = s[1]
		var pc: Vector3 = s[2]
		var n := int(round(float(s[3]) * scale))
		var box := Vector3(c.z * 2.0 * 1.15, c.x - c.y, c.z * 2.0 * 1.15)
		var got := 0
		var guard := 0
		while got < n and guard < n * 60 + 200:
			guard += 1
			var p := Vector3(_rng.randf_range(-0.5, 0.5) * box.x, c.y + _rng.randf() * box.y, _rng.randf_range(-0.5, 0.5) * box.z)
			if not inside(p, c) or (a > _ages[0] and inside(p, pc)):
				continue
			if not _clumped(p, c):
				continue
			raw.append([a, p])
			got += 1
	for r in raw:
		_appear.append(r[0])
		_pts.append(r[1])
	_alive.resize(_pts.size())
	_alive.fill(0)
	_closest.resize(_pts.size())
	_closest.fill(-1)
	_cdist.resize(_pts.size())
	_cdist.fill(1e9)


## Whether a point is kept: near one of the crown's lobes, or now and then
## in between (the gaps between big limbs).
func _clumped(p: Vector3, c: Vector3) -> bool:
	if _lobes.is_empty():
		return true
	var u := Vector3(p.x / maxf(c.z, 0.01), (p.y - c.y) / maxf(c.x - c.y, 0.01), p.z / maxf(c.z, 0.01))
	var best := 0.0
	for l in _lobes:
		best = maxf(best, exp(-u.distance_squared_to(l) / 0.16))
	return _rng.randf() < 0.18 + 0.82 * best


func _step_len(age: float) -> float:
	return clampf(TreeKinds.height(sp, age) * STEP_SHARE, STEP_MIN, STEP_MAX)


# ----------------------------------------------------------------- growth

func _grow_year(age: float, last: float) -> void:
	_age = age
	var step := _step_len(age)
	var di := step * INFLUENCE
	var dk := step * KILL
	# Points opening up this year.
	while _next_pt < _pts.size() and _appear[_next_pt] <= age:
		var i := _next_pt
		_next_pt += 1
		_alive[i] = 1
		_file_point(i)
		var near := _nearest_node(_pts[i], di)
		if near >= 0:
			var d := _pts[i].distance_to(pos[near])
			if d < dk:
				_alive[i] = 0
			else:
				_closest[i] = near
				_cdist[i] = d
	# Grow as many steps as the tree gains in height this year.
	var gain := TreeKinds.height(sp, age) - TreeKinds.height(sp, last)
	var steps := clampi(int(ceil(gain / step)), 1, 6)
	for s in steps:
		if not _iterate(step, di, dk):
			_reach_up(step)


## One growth step for every node some point pulls on. False when nothing grew.
func _iterate(step: float, di: float, dk: float) -> bool:
	var k := TreeKinds.kind(sp)
	var pull := {}
	for i in _next_pt:
		if _alive[i] == 0 or _closest[i] < 0:
			continue
		var n := _closest[i]
		if _cdist[i] > di:
			continue
		var v := (_pts[i] - pos[n]) / maxf(_cdist[i], 0.001)
		pull[n] = pull.get(n, Vector3.ZERO) + v
	if pull.is_empty():
		return false
	var up := Vector3(0, float(k.up), 0)
	var steer: Array = STEER.get(sp, k.angle)
	var amin := deg_to_rad(float(steer[0]))
	var amax := deg_to_rad(float(steer[1]))
	var made := PackedInt32Array()
	var nodes: Array = pull.keys()
	nodes.sort()
	for n in nodes:
		var v: Vector3 = pull[n]
		if v.length() < 0.05:
			continue
		var d := (v.normalized() + up + _lean).normalized()
		if nchild[n] > 0:
			d = _clamp_angle(dir[n], d, amin, amax)
			# Each node puts out a few shoots at most (a bud per leaf).
			if nchild[n] >= 3:
				continue
		elif leader[n] == 1:
			# Leader: a conifer's central stem keeps heading for the sky.
			if k.leader:
				d = (d + Vector3.UP * 2.5).normalized()
		var p := pos[n] + d * step
		if _too_close(n, p, step):
			continue
		made.append(_add(n, p, d))
	# New nodes claim the points near them, and use up the ones they reach.
	for id in made:
		for i in _points_near(pos[id], di):
			if _alive[i] == 0:
				continue
			var d := _pts[i].distance_to(pos[id])
			if d < dk:
				_alive[i] = 0
			elif d < _cdist[i]:
				_closest[i] = id
				_cdist[i] = d
	return not made.is_empty()


## No point in reach yet (a sapling's stem below its first leaves, or a
## conifer outgrowing its crown): the leader grows straight up.
func _reach_up(step: float) -> void:
	var top := _tip
	if pos[top].y >= TreeKinds.height(sp, _age) - step * 0.5:
		return
	var d := (Vector3.UP + _lean).normalized()
	var id := _add(top, pos[top] + d * step, d)
	for i in _points_near(pos[id], step * INFLUENCE):
		if _alive[i] == 0:
			continue
		var dd := _pts[i].distance_to(pos[id])
		if dd < step * KILL:
			_alive[i] = 0
		elif dd < _cdist[i]:
			_closest[i] = id
			_cdist[i] = dd


func _add(n: int, p: Vector3, d: Vector3) -> int:
	var id := pos.size()
	pos.append(p)
	parent.append(n)
	born.append(_age)
	dir.append(d)
	leader.append(1 if leader[n] == 1 and nchild[n] == 0 else 0)
	nchild.append(0)
	nchild[n] += 1
	if leader[id] == 1:
		_tip = id
	_file_node(id)
	return id


## A side shoot leaves its parent at the kind's branch angle.
static func _clamp_angle(ref: Vector3, d: Vector3, amin: float, amax: float) -> Vector3:
	var a := ref.angle_to(d)
	if a >= amin and a <= amax:
		return d
	var side := d - ref * d.dot(ref)
	if side.length() < 0.001:
		side = ref.cross(Vector3.RIGHT if absf(ref.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var t := clampf(a, amin, amax)
	return (ref * cos(t) + side * sin(t)).normalized()


func _too_close(n: int, p: Vector3, step: float) -> bool:
	for i in _nodes_near(p, step * 0.45):
		if pos[i].distance_to(p) < step * 0.45:
			return true
	return false


# ------------------------------------------------------------ spatial grids

static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


func _file_point(i: int) -> void:
	var c := _cell(_pts[i])
	if not _pgrid.has(c):
		_pgrid[c] = PackedInt32Array()
	_pgrid[c].append(i)


func _file_node(i: int) -> void:
	var c := _cell(pos[i])
	if not _ngrid.has(c):
		_ngrid[c] = PackedInt32Array()
	_ngrid[c].append(i)


func _points_near(p: Vector3, r: float) -> PackedInt32Array:
	return _near(_pgrid, p, r)


func _nodes_near(p: Vector3, r: float) -> PackedInt32Array:
	return _near(_ngrid, p, r)


static func _near(grid: Dictionary, p: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := _cell(p - Vector3.ONE * r)
	var hi := _cell(p + Vector3.ONE * r)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var c := Vector3i(x, y, z)
				if grid.has(c):
					out.append_array(grid[c])
	return out


func _nearest_node(p: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i in _nodes_near(p, r):
		var d := pos[i].distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


# --------------------------------------------------------- the tree at an age

## The tree at an age: which nodes it has, how thick each is, and its trunk.
## {pos, parent, radius (per node; 0 = not there), main (heaviest child per
## node, -1 none), height, crown (centre, radii), trunk (node ids up the
## main stem)}.
func at_age(age: float) -> Dictionary:
	var n := pos.size()
	var keep := PackedByteArray()
	keep.resize(n)
	for i in n:
		keep[i] = 1 if born[i] <= age + 0.001 else 0
	# Heaviest child of each node (most twigs beyond it): the main stem.
	var weight := PackedFloat32Array()
	weight.resize(n)
	weight.fill(0.0)
	for i in range(n - 1, -1, -1):
		if keep[i] == 0:
			continue
		weight[i] += 1.0
		if parent[i] >= 0:
			weight[parent[i]] += weight[i]
	var main := PackedInt32Array()
	main.resize(n)
	main.fill(-1)
	for i in range(1, n):
		if keep[i] == 0:
			continue
		var p := parent[i]
		if main[p] < 0 or weight[i] > weight[main[p]]:
			main[p] = i
	var trunk := PackedInt32Array([0])
	while main[trunk[-1]] >= 0:
		trunk.append(main[trunk[-1]])
	# The crown lifts: side limbs off the trunk below the crown base have
	# died in the shade or been cut, with everything beyond them.
	var lift := TreeKinds.crown_base(sp, age)
	var on_trunk := {}
	for t in trunk:
		on_trunk[t] = true
	for i in range(1, n):
		if keep[i] == 0:
			continue
		var p := parent[i]
		if keep[p] == 0:
			keep[i] = 0
		elif on_trunk.has(p) and not on_trunk.has(i) and pos[p].y < lift * 0.92:
			keep[i] = 0
	# Pipe model: each node's cross-section carries all the twigs beyond it.
	var rn := PackedFloat32Array()
	rn.resize(n)
	rn.fill(0.0)
	for i in range(n - 1, -1, -1):
		if keep[i] == 0:
			continue
		if rn[i] == 0.0:
			rn[i] = pow(TIP_R, PIPE_N)
		if parent[i] >= 0:
			rn[parent[i]] += rn[i]
	var radius := PackedFloat32Array()
	radius.resize(n)
	for i in n:
		radius[i] = pow(rn[i], 1.0 / PIPE_N) if keep[i] == 1 else 0.0
	# How many twig tips each node carries (1 for a tip).
	var tips := PackedInt32Array()
	tips.resize(n)
	tips.fill(0)
	for i in range(n - 1, -1, -1):
		if keep[i] == 0:
			continue
		if tips[i] == 0:
			tips[i] = 1
		if parent[i] >= 0:
			tips[parent[i]] += tips[i]
	# Recompute the main stem among the kept nodes.
	main.fill(-1)
	for i in range(1, n):
		if keep[i] == 0:
			continue
		var p := parent[i]
		if main[p] < 0 or radius[i] > radius[main[p]]:
			main[p] = i
	trunk = PackedInt32Array([0])
	while main[trunk[-1]] >= 0:
		trunk.append(main[trunk[-1]])
	# Scale to the kind's real trunk thickness at chest height (1.37 m).
	var at_chest := radius[0]
	for t in trunk:
		if pos[t].y >= 1.37:
			at_chest = radius[t]
			break
	var want := TreeKinds.dbh(sp, age) * 0.005
	var top := 0.0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for i in n:
		if keep[i] == 1:
			top = maxf(top, pos[i].y)
			lo = lo.min(pos[i])
			hi = hi.max(pos[i])
	if want <= 0.0:
		# Under chest height: a whip a finger or two thick.
		want = maxf(top * 0.012, 0.006)
		at_chest = radius[0]
	var s := want / maxf(at_chest, 1e-6)
	for i in n:
		radius[i] *= s
	return {"pos": pos, "parent": parent, "radius": radius, "main": main, "height": top, "trunk": trunk,
		"lo": lo, "hi": hi, "keep": keep, "tips": tips}


## Crown width (widest spread of the branches across) and height of the tree at an age.
static func measure(tree: Dictionary) -> Dictionary:
	var lo: Vector3 = tree.lo
	var hi: Vector3 = tree.hi
	return {"height": hi.y, "width": maxf(hi.x - lo.x, hi.z - lo.z), "dbh_cm": _dbh_of(tree) * 200.0}


static func _dbh_of(tree: Dictionary) -> float:
	var p: PackedVector3Array = tree.pos
	var r: PackedFloat32Array = tree.radius
	for t in tree.trunk:
		if p[t].y >= 1.37:
			return r[t]
	return 0.0
