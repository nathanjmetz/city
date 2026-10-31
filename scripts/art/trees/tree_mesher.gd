class_name TreeMesher
extends RefCounted
## Turns a grown tree (TreeGrower.at_age) into a mesh: bark tubes round
## every limb thick enough to see, and leaf cards where the twigs are.
## Built a slice at a time (step()), each slice a few hundred microseconds
## at most, so it can be spread over frames.
##
## Two levels of detail from the same branches:
##   FULL: limbs down to about 2.5 cm across (thinner is under a pixel
##     from the closest camera, 40 m), a leaf card at each twig.
##   LIGHT: only the big limbs (about 9 cm and up, or a share of the
##     trunk), with one big card standing in for each cluster of twigs,
##     for the middle distance (and the browser).
## Bark: arrays of position, normal, UV (around in metres, along in
## metres), colour (r radius / 0.5 m, g height share). Leaves: one quad per
## card, colours as TreeField's cards (r inner, g top, b hue, a 1 near / 0.5
## big card), normals out from the crown's middle so it shades as a volume.

enum Lod { FULL, LIGHT }

const CUT := [0.0125, 0.045]
## A light card stands for a cluster of about this many twig tips.
const CLUSTER := 4
## Leaf card size (m) for a full-grown crown; saplings get smaller cards.
const CARD := [1.5, 2.8]


## A broadleaf's leaf card size (m) at a level for a tree this tall.
static func card_size(lod: int, height: float) -> float:
	return CARD[lod] * clampf(sqrt(height / 16.0), 0.3, 1.0)
## Rings along a nearly straight limb are left out (up to this many in a row).
const SKIP_BEND := 12.0
const SKIP_RUN := 2

var sp := 0
var lod := 0
var done := false
## [bark arrays, leaf arrays] when done (either may be empty).
var parts := []

var _tree: Dictionary
var _rng := RandomNumberGenerator.new()
var _cut := 0.0
var _height := 1.0
var _i := 1
enum Phase { BARK, MIDDLES, SPOTS, CARDS }
var _phase := Phase.BARK
var _mid := PackedVector3Array()
var _spots := PackedInt32Array()
var _centre := Vector3.ZERO
var _radii := Vector3.ONE
var _size := 1.0
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _uvs := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _ring_at := {}
var _run := {}
var _along := PackedFloat32Array()


func _init(kind: int, tree: Dictionary, level: int, seed_value: int) -> void:
	sp = kind
	lod = level
	_tree = tree
	_rng.seed = hash([kind, seed_value, level, 3307])
	_height = maxf(float(tree.height), 0.3)
	var rad: PackedFloat32Array = tree.radius
	# A sapling's bark still shows at its own small scale.
	_cut = CUT[lod] * clampf(_height / 14.0, 0.25, 1.0)
	if lod == Lod.LIGHT:
		_cut = maxf(_cut, rad[0] * 0.14)
	_along.resize(rad.size())
	_along.fill(0.0)


## Builds the whole mesh at once (tests and tools).
static func build(kind: int, tree: Dictionary, level: int, seed_value: int) -> Array:
	var m := TreeMesher.new(kind, tree, level, seed_value)
	while not m.step(1_000_000_000):
		pass
	return m.parts


## A finished mesh with its two surfaces (bark first) and materials.
static func mesh(kind: int, tree: Dictionary, level: int, seed_value: int) -> ArrayMesh:
	return to_mesh(kind, level, build(kind, tree, level, seed_value))


static func to_mesh(kind: int, level: int, built: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	add_part(m, kind, level, built, 0)
	add_part(m, kind, level, built, 1)
	return m


## Hands one part of a built tree (0 bark, 1 leaves) to the graphics card
## as a surface of `m`, so the two can go in different frames.
static func add_part(m: ArrayMesh, kind: int, level: int, built: Array, part: int) -> void:
	if built[part].is_empty():
		return
	# 16-bit positions, normals and UVs: about half the graphics memory,
	# well under a millimetre off on a 30 m tree.
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built[part], [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	m.surface_set_material(m.get_surface_count() - 1,
		TreeLook.bark_material(level) if part == 0 else TreeLook.leaf_material(kind, level))


## Works for up to `budget_us` microseconds (always at least one small
## batch). True when finished. Slices of any size give the same mesh.
func step(budget_us: int) -> bool:
	var start := Time.get_ticks_usec()
	var n: int = (_tree.pos as PackedVector3Array).size()
	while not done:
		var unit := Time.get_ticks_usec()
		match _phase:
			Phase.BARK:
				var end := mini(_i + 8, n)
				while _i < end:
					_bark_node(_i)
					_i += 1
				if _i >= n:
					var bark := []
					if not _idx.is_empty():
						bark.resize(Mesh.ARRAY_MAX)
						bark[Mesh.ARRAY_VERTEX] = _verts
						bark[Mesh.ARRAY_NORMAL] = _norms
						bark[Mesh.ARRAY_TEX_UV] = _uvs
						bark[Mesh.ARRAY_COLOR] = _cols
						bark[Mesh.ARRAY_INDEX] = _idx
					parts = [bark]
					_verts = PackedVector3Array()
					_norms = PackedVector3Array()
					_uvs = PackedVector2Array()
					_cols = PackedColorArray()
					_idx = PackedInt32Array()
					_ring_at.clear()
					_run.clear()
					_mid.resize(n)
					_mid.fill(Vector3.ZERO)
					_i = n - 1
					_phase = Phase.MIDDLES
			Phase.MIDDLES:
				_middles_slice()
			Phase.SPOTS:
				_spots_slice(n)
			Phase.CARDS:
				_cards_slice()
		# Stop when another batch like this one would run past the budget.
		var now := Time.get_ticks_usec()
		if now - start + (now - unit) > budget_us:
			break
	return done


func _bark_node(i: int) -> void:
	var p: PackedVector3Array = _tree.pos
	var par: PackedInt32Array = _tree.parent
	var rad: PackedFloat32Array = _tree.radius
	var main: PackedInt32Array = _tree.main
	if rad[i] <= 0.0 or rad[i] < _cut:
		return
	var pi := par[i]
	if pi < 0:
		return
	_along[i] = _along[pi] + p[i].distance_to(p[pi])
	var axis := (p[i] - p[pi]).normalized()
	var next := main[i]
	var tangent := axis
	var straight := false
	if next >= 0 and rad[next] >= _cut:
		var out := (p[next] - p[i]).normalized()
		tangent = (axis + out).normalized()
		straight = rad_to_deg(axis.angle_to(out)) < SKIP_BEND
	var sides := _sides(rad[i])
	var start: Array = _ring_at.get(pi, [])
	var continues := not start.is_empty() and main[pi] == i and int(start[1]) == sides
	# Along a nearly straight stretch of limb the ring here is left out:
	# the tube runs on to the next one.
	if continues and straight and int(_run.get(pi, 0)) < SKIP_RUN and _sides(rad[next]) == sides:
		_ring_at[i] = start
		_run[i] = int(_run.get(pi, 0)) + 1
		return
	var side_vec: Vector3
	if not continues:
		# A side limb (or a change in sides): a ring of its own at the
		# parent, a little inside the bigger limb it grows from.
		side_vec = _perp(axis, start[2] if not start.is_empty() else Vector3.RIGHT)
		var base_r := minf(rad[i] * 1.05, rad[pi])
		if pi == 0:
			base_r = rad[i] * 1.35  # the trunk flares where it meets the roots
		start = _ring(p[pi] + axis * minf(rad[pi] * 0.3, 0.05) * (0.0 if pi == 0 else 1.0), axis, side_vec, base_r, sides,
			_along[pi])
	side_vec = _perp(tangent, start[2])
	var end := _ring(p[i], tangent, side_vec, rad[i], sides, _along[i])
	_ring_at[i] = end
	_run[i] = 0
	var a0: int = start[0]
	var b0: int = end[0]
	for s in sides:
		_idx.append_array([a0 + s, b0 + s, a0 + s + 1, a0 + s + 1, b0 + s, b0 + s + 1])


func _sides(r: float) -> int:
	if lod == Lod.LIGHT:
		return 5 if r > 0.2 else (4 if r > 0.08 else 3)
	return 8 if r > 0.18 else (6 if r > 0.07 else (4 if r > 0.03 else 3))


static func _perp(axis: Vector3, hint: Vector3) -> Vector3:
	var s := hint - axis * hint.dot(axis)
	if s.length() < 0.01:
		s = axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP)
	return s.normalized()


## One ring of `sides` + 1 vertices (the last repeats the first, for the
## bark's UV seam). Returns [first vertex, sides, side vector].
func _ring(at: Vector3, axis: Vector3, side: Vector3, r: float, sides: int, along: float) -> Array:
	var first := _verts.size()
	var up := axis.cross(side)
	var round_m := TAU * maxf(r, 0.01)
	var col := Color(clampf(r / 0.5, 0.0, 1.0), clampf(at.y / _height, 0.0, 1.0), 0.0, 1.0)
	for s in sides + 1:
		var a := TAU * float(s) / float(sides)
		var d := side * cos(a) + up * sin(a)
		_verts.append(at + d * r)
		_norms.append(d)
		_uvs.append(Vector2(float(s) / float(sides) * round_m, along))
		_cols.append(col)
	return [first, sides, side]


## Leaf cards: full detail at the twigs; the light version one big card per
## cluster of about CLUSTER twig tips, at the middle of its tips. In three
## passes, a batch at a time: the middle of each node's twig tips...
func _middles_slice() -> void:
	var p: PackedVector3Array = _tree.pos
	var par: PackedInt32Array = _tree.parent
	var rad: PackedFloat32Array = _tree.radius
	var tips: PackedInt32Array = _tree.tips
	var end := maxi(_i - 512, 0)
	while _i > end:
		var i := _i
		_i -= 1
		if rad[i] <= 0.0:
			continue
		if tips[i] == 1:
			_mid[i] = p[i]
		_mid[par[i]] += _mid[i]
	if _i <= 0:
		_i = 1
		_phase = Phase.SPOTS


## ...where the leaves go...
func _spots_slice(n: int) -> void:
	var conifer: bool = TreeKinds.kind(sp).evergreen
	var par: PackedInt32Array = _tree.parent
	var rad: PackedFloat32Array = _tree.radius
	var tips: PackedInt32Array = _tree.tips
	var end := mini(_i + 512, n)
	while _i < end:
		var i := _i
		_i += 1
		if rad[i] <= 0.0:
			continue
		if lod == Lod.FULL:
			# Leaves crowd the twig tips and clothe the thin shoots behind
			# them (a crown is a shell of foliage a metre or two deep).
			if tips[i] == 1 or (tips[i] <= (4 if conifer else 2) and _rng.randf() < (0.7 if conifer else 0.45)):
				_spots.append(i)
		elif tips[i] <= CLUSTER and tips[par[i]] > CLUSTER:
			_spots.append(i)
	if _i < n:
		return
	# The crown's middle and size, for leaf shading.
	var lo: Vector3 = _tree.lo
	var hi: Vector3 = _tree.hi
	var base := TreeKinds.crown_base(sp, 60.0) * _height / maxf(TreeKinds.height(sp, 60.0), 0.1)
	_centre = Vector3((lo.x + hi.x) * 0.5, (maxf(base, lo.y) + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
	_radii = Vector3(maxf((hi.x - lo.x) * 0.5, 0.3), maxf((hi.y - maxf(base, lo.y)) * 0.5, 0.3), maxf((hi.z - lo.z) * 0.5, 0.3))
	_size = card_size(lod, _height) * (0.8 if conifer else 1.0)
	_i = 0
	_phase = Phase.CARDS


## ...and the cards themselves.
func _cards_slice() -> void:
	var k := TreeKinds.kind(sp)
	var conifer: bool = k.evergreen
	var p: PackedVector3Array = _tree.pos
	var tips: PackedInt32Array = _tree.tips
	var far := 0.5 if lod == Lod.LIGHT else 1.0
	var end := mini(_i + 24, _spots.size())
	while _i < end:
		var i := _spots[_i]
		_i += 1
		var at := p[i]
		var card := _size
		var cards := 1
		if lod == Lod.LIGHT:
			at = _mid[i] / float(tips[i])
			card = _size * clampf(sqrt(float(tips[i]) / CLUSTER), 0.7, 1.4)
			cards = 3
		elif not conifer and k.leaf != TreeKinds.Leaf.COMPOUND:
			cards = 2 if _rng.randf() < 0.5 else 1
		# Each cluster's hue drift, as TreeField's cards draw it: a conifer's
		# only toward blue-green.
		var hue := _rng.randf() * (0.4 if conifer else 1.0)
		for c in cards:
			var q := at + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * card * 0.3
			_card(_verts, _norms, _uvs, _cols, _idx, q, _centre, _radii, card * _rng.randf_range(0.8, 1.2), hue, far)
	if _i < _spots.size():
		return
	var leaves := []
	if not _idx.is_empty():
		leaves.resize(Mesh.ARRAY_MAX)
		leaves[Mesh.ARRAY_VERTEX] = _verts
		leaves[Mesh.ARRAY_NORMAL] = _norms
		leaves[Mesh.ARRAY_TEX_UV] = _uvs
		leaves[Mesh.ARRAY_COLOR] = _cols
		leaves[Mesh.ARRAY_INDEX] = _idx
	parts.append(leaves)
	_mid = PackedVector3Array()
	_spots = PackedInt32Array()
	done = true


func _card(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, p: Vector3, center: Vector3, rad: Vector3, size: float, hue: float, far: float) -> void:
	var basis := Basis.from_euler(Vector3(_rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI)))
	var u := basis.x * size * 0.5
	var v := basis.y * size * 0.5
	var first := verts.size()
	var corners := [p - u - v, p + u - v, p + u + v, p - u + v]
	var tex := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in 4:
		var q: Vector3 = corners[i]
		var rel := (q - center) / rad
		verts.append(q)
		norms.append((rel + Vector3(0, 0.35, 0)).normalized())
		uvs.append(tex[i])
		cols.append(Color(clampf(rel.length(), 0.0, 1.0), clampf(rel.y * 0.5 + 0.5, 0.0, 1.0), hue, far))
	idx.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
