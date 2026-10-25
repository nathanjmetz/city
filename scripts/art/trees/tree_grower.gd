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
## generator: the same seed always grows the same tree. The growth maths
## sticks to sums, products, square roots and the generator (plain_exp,
## plain_ln and plain_sin_cos below stand in for exp, log, sin and cos,
## whose last digits differ between computers' maths libraries); see
## docs/trees.md for what is guaranteed.
##
## Growing is done in small slices (step(), and AgeCut for the tree at an
## age), each a few hundred microseconds at most, so the browser can spread
## it over frames with nothing on the main thread for long.

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
# Where the slices have got to.
enum Phase { SHELLS, POINTS, OPEN, PULL, SHOOT, CLAIM, STRAIGHTEN, DONE }
var _phase := Phase.SHELLS
var _cur := 0  # index into the phase's list
var _shells := []  # [age, crown, previous crown, points wanted]
var _total_want := 0.0
var _shell_got := 0
var _shell_n := 0
var _guard := 0
var _steps := 0  # growth steps left this year
var _step := 0.0
var _di := 0.0
var _dk := 0.0
var _pull := {}  # node -> pull this step
var _pull_nodes := []
var _made := PackedInt32Array()
var _cos_lo := 1.0  # cosine of the steer angles, and sine
var _cos_hi := 0.0
var _sin_lo := 0.0
var _sin_hi := 1.0
var _weight := PackedFloat32Array()
var _main := PackedInt32Array()
var _moved := PackedVector3Array()
var _pass := 0

## Work done between clock checks: small enough that one batch stays well
## under the browser's slice.
const BATCH := 48


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
		var sc := plain_sin_cos(ang)
		_lobes.append(Vector3(sc.y * _rng.randf_range(0.45, 0.8), _rng.randf_range(0.3, 0.85), sc.x * _rng.randf_range(0.45, 0.8)))
	if int(k.lobes) > 0:
		_lobes.append(Vector3(0, 0.95, 0))
	_squash = Vector2(_rng.randf_range(0.88, 1.12), _rng.randf_range(0.88, 1.12))
	_lean = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * (0.05 if not k.leader else 0.01)
	var steer: Array = STEER.get(sp, k.angle)
	var lo := plain_sin_cos(deg_to_rad(float(steer[0])))
	var hi := plain_sin_cos(deg_to_rad(float(steer[1])))
	_sin_lo = lo.x
	_cos_lo = lo.y
	_sin_hi = hi.x
	_cos_hi = hi.y


## Plants the seed: the first node, at the foot of the trunk.
func _plant() -> void:
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


## Grows for up to `budget_us` microseconds (always at least one small
## batch of work). Returns true when finished. Slices of any size grow the
## same tree.
func step(budget_us: int) -> bool:
	var start := Time.get_ticks_usec()
	while _phase != Phase.DONE:
		var unit := Time.get_ticks_usec()
		match _phase:
			Phase.SHELLS:
				_shell_slice()
			Phase.POINTS:
				_points_slice()
			Phase.OPEN:
				_open_slice()
			Phase.PULL:
				_pull_slice()
			Phase.SHOOT:
				_shoot_slice()
			Phase.CLAIM:
				_claim_slice()
			Phase.STRAIGHTEN:
				_straighten_slice()
		# Stop when another batch like this one would run past the budget.
		var now := Time.get_ticks_usec()
		if now - start + (now - unit) > budget_us:
			break
	if _phase == Phase.DONE and not done:
		done = true
		_pts = PackedVector3Array()
		_pgrid.clear()
		_ngrid.clear()
		_shells.clear()
		_weight = PackedFloat32Array()
		_main = PackedInt32Array()
		_moved = PackedVector3Array()
	return done


## Real limbs grow in long sweeps, not in the zigzag steps the growth
## takes: each node is eased toward the line between its parent and its
## main child, the more so the more tree it carries (a trunk is straighter
## than a twig). Six passes, a batch at a time.
func _straighten_slice() -> void:
	var n := pos.size()
	if _weight.is_empty():
		_weight.resize(n)
		_weight.fill(1.0)
		_main.resize(n)
		_main.fill(-1)
		_cur = 0
		_pass = -2  # -2: weights, -1: main children, 0..5: passes
	var end := mini(_cur + BATCH * 4, n)
	if _pass == -2:
		# Reverse order: children before parents.
		for k in range(_cur, end):
			var i := n - 1 - k
			if i > 0:
				_weight[parent[i]] += _weight[i]
	elif _pass == -1:
		for i in range(maxi(_cur, 1), end):
			var p := parent[i]
			if _main[p] < 0 or _weight[i] > _weight[_main[p]]:
				_main[p] = i
	else:
		if _cur == 0:
			_moved = pos.duplicate()
		for i in range(maxi(_cur, 1), end):
			var c := _main[i]
			if c < 0:
				continue
			var mid := (pos[parent[i]] + pos[c]) * 0.5
			var w := clampf(0.25 + plain_ln(_weight[i]) * 0.1, 0.25, 0.8)
			_moved[i] = pos[i].lerp(mid, w)
	_cur = end
	if _cur < n:
		return
	_cur = 0
	if _pass >= 0:
		pos = _moved
	_pass += 1
	if _pass >= 6:
		_phase = Phase.DONE


## Stand-ins for exp, log, sin and cos from sums and products only: the
## same last digit on every computer (the maths libraries' own differ).
## e^-x for x >= 0, to about 1e-7.
static func plain_exp_neg(x: float) -> float:
	var y := maxf(x, 0.0) / 16.0
	var r := 1.0 / (1.0 + y * (1.0 + y * (0.5 + y * (1.0 / 6.0 + y * (1.0 / 24.0 + y / 120.0)))))
	for i in 4:
		r *= r
	return r


## ln(x) for x > 0, to about 1e-6.
static func plain_ln(x: float) -> float:
	var e := 0
	var m := maxf(x, 1e-30)
	while m >= 2.0:
		m *= 0.5
		e += 1
	while m < 1.0:
		m *= 2.0
		e -= 1
	var z := (m - 1.0) / (m + 1.0)
	var z2 := z * z
	return float(e) * 0.6931471805599453 + 2.0 * z * (1.0 + z2 * (1.0 / 3.0 + z2 * (0.2 + z2 * (1.0 / 7.0 + z2 / 9.0))))


## Vector2(sin a, cos a), to about 1e-9, for any angle.
static func plain_sin_cos(a: float) -> Vector2:
	# Into [-pi, pi], then a series on a quarter of it and doubled twice.
	var t := a - TAU * floorf(a / TAU + 0.5)
	var h := t * 0.25
	var h2 := h * h
	var sn := h * (1.0 - h2 / 6.0 * (1.0 - h2 / 20.0 * (1.0 - h2 / 42.0 * (1.0 - h2 / 72.0))))
	var cs := 1.0 - h2 / 2.0 * (1.0 - h2 / 12.0 * (1.0 - h2 / 30.0 * (1.0 - h2 / 56.0 * (1.0 - h2 / 90.0))))
	for i in 2:
		var s2 := 2.0 * sn * cs
		cs = cs * cs - sn * sn
		sn = s2
	return Vector2(sn, cs)


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
## First each year's shell is measured (160 random tries, a batch a
## slice)...
func _shell_slice() -> void:
	var i := _cur
	var a: float = _ages[i]
	var c := _crown(a)
	var prev: Vector3 = _shells[-1][1] if i > 0 else Vector3.ZERO
	var box := Vector3(c.z * 2.0 * 1.15, c.x - c.y, c.z * 2.0 * 1.15)
	var tries := 160
	var end := mini(_guard + 40, tries)
	while _guard < end:
		_guard += 1
		var p := Vector3(_rng.randf_range(-0.5, 0.5) * box.x, c.y + _rng.randf() * box.y, _rng.randf_range(-0.5, 0.5) * box.z)
		if inside(p, c) and (i == 0 or not inside(p, prev)):
			_shell_got += 1
	if _guard < tries:
		return
	var hits := _shell_got
	_guard = 0
	_shell_got = 0
	var vol := box.x * box.y * box.z * float(hits) / tries
	var size := _step_len(a) * 3.2
	# Points per cubic metre for this size of twig.
	var want := vol / (size * size * size)
	_shells.append([a, c, prev, want])
	_total_want += want
	_cur += 1
	if _cur >= _ages.size():
		_phase = Phase.POINTS
		_cur = 0
		_start_shell()


func _start_shell() -> void:
	# Scaled so the whole life holds about POINTS points.
	_shell_n = int(round(float(_shells[_cur][3]) * float(POINTS) / maxf(_total_want, 1.0)))
	_shell_got = 0
	_guard = 0


## ...then filled with points, a batch of tries a slice.
func _points_slice() -> void:
	var sh: Array = _shells[_cur]
	var a: float = sh[0]
	var c: Vector3 = sh[1]
	var pc: Vector3 = sh[2]
	var box := Vector3(c.z * 2.0 * 1.15, c.x - c.y, c.z * 2.0 * 1.15)
	var tries := 0
	while _shell_got < _shell_n and _guard < _shell_n * 60 + 200 and tries < BATCH:
		_guard += 1
		tries += 1
		var p := Vector3(_rng.randf_range(-0.5, 0.5) * box.x, c.y + _rng.randf() * box.y, _rng.randf_range(-0.5, 0.5) * box.z)
		if not inside(p, c) or (a > _ages[0] and inside(p, pc)):
			continue
		if not _clumped(p, c):
			continue
		_appear.append(a)
		_pts.append(p)
		_shell_got += 1
	if _shell_got < _shell_n and _guard < _shell_n * 60 + 200:
		return
	_cur += 1
	if _cur < _shells.size():
		_start_shell()
		return
	_alive.resize(_pts.size())
	_alive.fill(0)
	_closest.resize(_pts.size())
	_closest.fill(-1)
	_cdist.resize(_pts.size())
	_cdist.fill(1e9)
	_plant()
	_begin_year()


## Whether a point is kept: near one of the crown's lobes, or now and then
## in between (the gaps between big limbs).
func _clumped(p: Vector3, c: Vector3) -> bool:
	if _lobes.is_empty():
		return true
	var u := Vector3(p.x / maxf(c.z, 0.01), (p.y - c.y) / maxf(c.x - c.y, 0.01), p.z / maxf(c.z, 0.01))
	var nearest := INF
	for l in _lobes:
		nearest = minf(nearest, u.distance_squared_to(l))
	return _rng.randf() < 0.18 + 0.82 * plain_exp_neg(nearest / 0.16)


func _step_len(age: float) -> float:
	return clampf(TreeKinds.height(sp, age) * STEP_SHARE, STEP_MIN, STEP_MAX)


# ----------------------------------------------------------------- growth

## A year of growth: the points opening up this year, then as many growth
## steps as the tree gains in height. Each step is three passes (the pull
## of the points, the new shoots, the points they reach), each in batches.
func _begin_year() -> void:
	var age: float = _ages[_age_i]
	var last: float = _ages[_age_i - 1] if _age_i > 0 else 0.0
	_age = age
	_step = _step_len(age)
	_di = _step * INFLUENCE
	_dk = _step * KILL
	var gain := TreeKinds.height(sp, age) - TreeKinds.height(sp, last)
	_steps = clampi(int(ceil(gain / _step)), 1, 6)
	_phase = Phase.OPEN


## Points opening up this year.
func _open_slice() -> void:
	var n := 0
	while _next_pt < _pts.size() and _appear[_next_pt] <= _age and n < 4:
		var i := _next_pt
		_next_pt += 1
		n += 1
		_alive[i] = 1
		_file_point(i)
		var near := _nearest_node(_pts[i], _di)
		if near >= 0:
			var d := _pts[i].distance_to(pos[near])
			if d < _dk:
				_alive[i] = 0
			else:
				_closest[i] = near
				_cdist[i] = d
	if _next_pt < _pts.size() and _appear[_next_pt] <= _age:
		return
	_start_step()


func _start_step() -> void:
	_pull = {}
	_cur = 0
	_phase = Phase.PULL


## Each point pulls on the node nearest it.
func _pull_slice() -> void:
	var end := mini(_cur + BATCH * 16, _next_pt)
	for i in range(_cur, end):
		if _alive[i] == 0 or _closest[i] < 0:
			continue
		var n := _closest[i]
		if _cdist[i] > _di:
			continue
		var v := (_pts[i] - pos[n]) / maxf(_cdist[i], 0.001)
		_pull[n] = _pull.get(n, Vector3.ZERO) + v
	_cur = end
	if _cur < _next_pt:
		return
	if _pull.is_empty():
		_reach_up(_step)
		_end_step()
		return
	_pull_nodes = _pull.keys()
	_pull_nodes.sort()
	_made = PackedInt32Array()
	_cur = 0
	_phase = Phase.SHOOT


## Every node a point pulls on puts out a shoot toward them.
func _shoot_slice() -> void:
	var k := TreeKinds.kind(sp)
	var up := Vector3(0, float(k.up), 0)
	var end := mini(_cur + 16, _pull_nodes.size())
	for j in range(_cur, end):
		var n: int = _pull_nodes[j]
		var v: Vector3 = _pull[n]
		if v.length() < 0.05:
			continue
		var d := (v.normalized() + up + _lean).normalized()
		if nchild[n] > 0:
			d = _clamp_angle(dir[n], d, _cos_lo, _sin_lo, _cos_hi, _sin_hi)
			# Each node puts out a few shoots at most (a bud per leaf).
			if nchild[n] >= 3:
				continue
		elif leader[n] == 1:
			# Leader: a conifer's central stem keeps heading for the sky.
			if k.leader:
				d = (d + Vector3.UP * 2.5).normalized()
		var p := pos[n] + d * _step
		if _too_close(n, p, _step):
			continue
		_made.append(_add(n, p, d))
	_cur = end
	if _cur < _pull_nodes.size():
		return
	_cur = 0
	if _made.is_empty():
		# Nothing grew.
		_reach_up(_step)
		_end_step()
	else:
		_phase = Phase.CLAIM


## New nodes claim the points near them, and use up the ones they reach.
func _claim_slice() -> void:
	var end := mini(_cur + 2, _made.size())
	for j in range(_cur, end):
		var id := _made[j]
		for i in _points_near(pos[id], _di):
			if _alive[i] == 0:
				continue
			var d := _pts[i].distance_to(pos[id])
			if d < _dk:
				_alive[i] = 0
			elif d < _cdist[i]:
				_closest[i] = id
				_cdist[i] = d
	_cur = end
	if _cur < _made.size():
		return
	_end_step()


func _end_step() -> void:
	_steps -= 1
	if _steps > 0:
		_start_step()
		return
	_age_i += 1
	if _age_i < _ages.size():
		_begin_year()
	else:
		_cur = 0
		_phase = Phase.STRAIGHTEN


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


## A side shoot leaves its parent at the kind's branch angle: turned in
## toward the angle range when it falls outside it (compared by cosines,
## so no angle is ever worked out).
static func _clamp_angle(ref: Vector3, d: Vector3, cos_lo: float, sin_lo: float, cos_hi: float, sin_hi: float) -> Vector3:
	var c := ref.dot(d)
	if c <= cos_lo and c >= cos_hi:
		return d
	var side := d - ref * c
	if side.length() < 0.001:
		side = ref.cross(Vector3.RIGHT if absf(ref.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	if c > cos_lo:
		return (ref * cos_lo + side * sin_lo).normalized()
	return (ref * cos_hi + side * sin_hi).normalized()


func _too_close(_n: int, p: Vector3, step: float) -> bool:
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
## main stem)}. All at once; AgeCut does the same a slice at a time.
func at_age(age: float) -> Dictionary:
	var cut := AgeCut.new(self, age)
	while not cut.step(1_000_000_000):
		pass
	return cut.tree


## Works out the tree at an age (see at_age) in slices: each pass over the
## nodes goes a batch at a time, checking the clock between batches.
class AgeCut:
	const CHUNK := 512
	const PASSES := 10
	var tree := {}
	var _g: TreeGrower
	var _age := 0.0
	var _n := 0
	var _pass := 0
	var _cur := 0
	var _keep := PackedByteArray()
	var _weight := PackedFloat32Array()
	var _main := PackedInt32Array()
	var _rn := PackedFloat32Array()
	var _radius := PackedFloat32Array()
	var _tips := PackedInt32Array()
	var _on_trunk := PackedByteArray()
	var _lift := 0.0
	var _top := 0.0
	var _lo := Vector3(1e9, 1e9, 1e9)
	var _hi := -Vector3(1e9, 1e9, 1e9)
	var _scale := 1.0

	func _init(g: TreeGrower, age: float) -> void:
		_g = g
		_age = age
		_n = g.pos.size()

	## True when `tree` is ready.
	func step(budget_us: int) -> bool:
		var start := Time.get_ticks_usec()
		while _pass < PASSES:
			var unit := Time.get_ticks_usec()
			var end := mini(_cur + CHUNK, _n)
			_run(_cur, end)
			_cur = end
			if _cur >= _n:
				_finish_pass()
				_pass += 1
				_cur = 0
			var now := Time.get_ticks_usec()
			if now - start + (now - unit) > budget_us:
				break
		return _pass >= PASSES

	func _run(from: int, end: int) -> void:
		var n := _n
		var parent := _g.parent
		match _pass:
			0:
				if from == 0:
					_keep.resize(n)
					_weight.resize(n)
					_weight.fill(0.0)
					_main.resize(n)
					_main.fill(-1)
				var born := _g.born
				for i in range(from, end):
					_keep[i] = 1 if born[i] <= _age + 0.001 else 0
			1:
				# Heaviest child of each node (most twigs beyond it): the
				# main stem. Children before parents.
				for k in range(from, end):
					var i := n - 1 - k
					if _keep[i] == 0:
						continue
					_weight[i] += 1.0
					if parent[i] >= 0:
						_weight[parent[i]] += _weight[i]
			2:
				for i in range(maxi(from, 1), end):
					if _keep[i] == 0:
						continue
					var p := parent[i]
					if _main[p] < 0 or _weight[i] > _weight[_main[p]]:
						_main[p] = i
			3:
				# The crown lifts: side limbs off the trunk below the crown
				# base have died in the shade or been cut, with everything
				# beyond them.
				var pos := _g.pos
				for i in range(maxi(from, 1), end):
					if _keep[i] == 0:
						continue
					var p := parent[i]
					if _keep[p] == 0:
						_keep[i] = 0
					elif _on_trunk[p] == 1 and _on_trunk[i] == 0 and pos[p].y < _lift * 0.92:
						_keep[i] = 0
			4:
				# Pipe model: each node's cross-section carries all the twigs
				# beyond it.
				if from == 0:
					_rn.resize(n)
					_rn.fill(0.0)
				var tip := pow(TIP_R, PIPE_N)
				for k in range(from, end):
					var i := n - 1 - k
					if _keep[i] == 0:
						continue
					if _rn[i] == 0.0:
						_rn[i] = tip
					if parent[i] >= 0:
						_rn[parent[i]] += _rn[i]
			5:
				if from == 0:
					_radius.resize(n)
				for i in range(from, end):
					_radius[i] = pow(_rn[i], 1.0 / PIPE_N) if _keep[i] == 1 else 0.0
			6:
				# How many twig tips each node carries (1 for a tip).
				if from == 0:
					_tips.resize(n)
					_tips.fill(0)
				for k in range(from, end):
					var i := n - 1 - k
					if _keep[i] == 0:
						continue
					if _tips[i] == 0:
						_tips[i] = 1
					if parent[i] >= 0:
						_tips[parent[i]] += _tips[i]
			7:
				# The main stem again, among the kept nodes.
				if from == 0:
					_main.fill(-1)
				for i in range(maxi(from, 1), end):
					if _keep[i] == 0:
						continue
					var p := parent[i]
					if _main[p] < 0 or _radius[i] > _radius[_main[p]]:
						_main[p] = i
			8:
				# How far the kept tree reaches.
				var pos := _g.pos
				for i in range(from, end):
					if _keep[i] == 1:
						_top = maxf(_top, pos[i].y)
						_lo = _lo.min(pos[i])
						_hi = _hi.max(pos[i])
			9:
				# Scaled to the kind's real trunk thickness (worked out at
				# the end of the pass before).
				for i in range(from, end):
					_radius[i] *= _scale

	func _finish_pass() -> void:
		match _pass:
			2:
				_lift = TreeKinds.crown_base(_g.sp, _age)
				_on_trunk.resize(_n)
				_on_trunk.fill(0)
				for t in _trunk():
					_on_trunk[t] = 1
			8:
				# The kind's real trunk thickness at chest height (1.37 m).
				var at_chest := _radius[0]
				for t in _trunk():
					if _g.pos[t].y >= 1.37:
						at_chest = _radius[t]
						break
				var want := TreeKinds.dbh(_g.sp, _age) * 0.005
				if want <= 0.0:
					# Under chest height: a whip a finger or two thick.
					want = maxf(_top * 0.012, 0.006)
					at_chest = _radius[0]
				_scale = want / maxf(at_chest, 1e-6)
			9:
				tree = {"pos": _g.pos, "parent": _g.parent, "radius": _radius, "main": _main, "height": _top,
					"trunk": _trunk(), "lo": _lo, "hi": _hi, "keep": _keep, "tips": _tips}
				_weight = PackedFloat32Array()
				_rn = PackedFloat32Array()
				_on_trunk = PackedByteArray()

	func _trunk() -> PackedInt32Array:
		var trunk := PackedInt32Array([0])
		while _main[trunk[-1]] >= 0:
			trunk.append(_main[trunk[-1]])
		return trunk


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
