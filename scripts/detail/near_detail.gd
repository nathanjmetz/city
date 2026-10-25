class_name NearDetail
extends Node3D
## The close-up ring of the new drawing style
## (docs/scale-test-2026-10-25.md, "The new drawing style, measured"):
## within about 100 m of the camera every house is grown at real size over
## its own drawing, brick by brick, lap by lap and course by course, a few
## small jobs a frame so it never stutters. The pieces are laid on the
## house's own walls and roofs, as its builder drew them (the same plan,
## colours and wear), so the close-up and the drawing underneath always
## agree: the detail only adds the relief (laps that throw a shadow line,
## bricks set proud of their mortar, shingle butts).
##
## Every piece is an instance of a handful of shared unit meshes
## (NearMeshes), merged by kind across all the houses in each quarter of a
## 128 m square (one brick batch for 64 m of street, not one per house: small
## enough that a house coming or going re-sends little), so the ring costs a
## few dozen draw calls, the same in the browser.

const SQUARE := 128.0
## Pieces stand this far off the wall: under the windows' glass (2 cm out)
## and trim, over the wall's own face.
const BRICK_OUT := 0.013
const MORTAR_OUT := 0.004
const SHINGLE_OUT := 0.003
## How much growing a frame may take (ms); the browser gets less.
var budget_ms := 2.5
## Shown within near_a, gone by near_b; grown from grow_r, let go past release_r.
var near_a := 90.0
var near_b := 110.0
var grow_r := 130.0
var release_r := 160.0
## Asked for a house's walls and roofs: Callable(key) -> [square, [[kind,
## surface arrays in the square's frame], ...]], or [] while it has none.
var parts_of: Callable

const GRID := 64.0
var _grid := {}  # Vector2i -> {key: true}
var _centre := {}  # key -> Vector3 (the view's frame)
var _grown := {}  # key -> {sq, bufs: {kind: PackedFloat32Array}, counts: {kind: int}}
var _jobs := {}  # key -> growth under way
var _queue: Array = []  # keys waiting, nearest first
var _squares := {}  # Vector3i (square x, z, quarter) -> {kind: MultiMeshInstance3D}
var _dirty := {}  # Vector2i -> true


func _init() -> void:
	set_reach(1.0)


## Scales how far the detail reaches with the graphics tier's detail
## (GraphicsQuality.detail: 0.4 Low to 2.5 Cinematic) and the screen's
## antialiasing (GraphicsQuality.msaa: 0 none, 1 2x, 2 4x): it stays where
## it's a few pixels big, nearer with less antialiasing (NearMats).
func set_reach(detail: float, msaa := 2) -> void:
	# Even with 4x, a big brick wall seen far off or edge on shimmers in
	# rings: past about 9 cm a pixel, the painted pattern takes over.
	var px := Vector2(0.09, 0.14)
	if msaa == 1:
		px = Vector2(0.022, 0.028)
	elif msaa <= 0:
		px = Vector2(0.014, 0.018)
	near_a = 90.0 * clampf(detail, 0.5, 1.2)
	# A pixel is about 1/900 of the distance on a 1080p screen: past where
	# it's px_none wide, nothing would show, so nothing is grown.
	near_a = minf(near_a, px.y * 900.0)
	near_b = near_a * 1.22
	grow_r = near_b + 20.0
	release_r = grow_r + 30.0
	NearMats.set_reach(near_a, near_b, px)


func index(key: String, centre: Vector3) -> void:
	unindex(key)
	_centre[key] = centre
	var c := _cell(centre)
	if not _grid.has(c):
		_grid[c] = {}
	_grid[c][key] = true


func unindex(key: String) -> void:
	release(key)
	if not _centre.has(key):
		return
	var c := _cell(_centre[key])
	if _grid.has(c):
		_grid[c].erase(key)
		if _grid[c].is_empty():
			_grid.erase(c)
	_centre.erase(key)


## Lets a house's detail go (it was drawn again, or left the ring).
func release(key: String) -> void:
	_jobs.erase(key)
	if _grown.has(key):
		_dirty[_grown[key].bucket] = true
		_grown.erase(key)


func grown_count() -> int:
	return _grown.size()


## True when every house near enough has its detail.
func caught_up() -> bool:
	return _queue.is_empty() and _jobs.is_empty() and _dirty.is_empty()


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


## `eye` in the view's frame.
func update(eye: Vector3) -> void:
	var want := {}
	var r := int(ceil(release_r / GRID))
	var c0 := _cell(eye)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for key in _grid.get(c0 + Vector2i(dx, dz), {}):
				var d: float = eye.distance_to(_centre[key])
				if d < grow_r or (d < release_r and (_grown.has(key) or _jobs.has(key))):
					want[key] = d
	for key in _grown.keys():
		if not want.has(key):
			release(key)
	for key in _jobs.keys():
		if not want.has(key):
			_jobs.erase(key)
	_queue.clear()
	for key in want:
		if not _grown.has(key):
			_queue.append(key)
	_queue.sort_custom(func(a, b): return want[a] < want[b])
	var t := Time.get_ticks_usec()
	var limit := int(budget_ms * 1000.0)
	while not _queue.is_empty() and Time.get_ticks_usec() - t < limit:
		var key: String = _queue[0]
		if not _jobs.has(key):
			var got: Array = parts_of.call(key) if parts_of.is_valid() else []
			if got.is_empty():
				# Its drawing isn't in yet: try again next frame.
				_queue.pop_front()
				continue
			_jobs[key] = _start(got[0], got[1])
		var st: Dictionary = _jobs[key]
		_step(st)
		if st.jobs.is_empty():
			_jobs.erase(key)
			_queue.pop_front()
			var bucket := _bucket(st.sq, _centre[key])
			_grown[key] = {"bucket": bucket, "bufs": st.bufs, "counts": st.counts}
			_dirty[bucket] = true
	for bucket in _dirty:
		_rebuild(bucket)
	_dirty.clear()


# ------------------------------------------------------------------ growing

func _start(sq: Vector2i, parts: Array) -> Dictionary:
	return {"sq": sq, "parts": parts, "jobs": [["group"]], "groups": [], "bufs": {}, "counts": {}}


func _step(st: Dictionary) -> void:
	var job: Array = st.jobs.pop_front()
	if job[0] == "group":
		st.groups = _groups(st.parts)
		for g in st.groups:
			st.jobs.append(["lay", g])
		return
	var g: Dictionary = job[1]
	match String(g.kind):
		"siding": _boards(st, g)
		"brick": _bricks(st, g)
		"roof": _shingles(st, g)


## The house's walls and roofs as flat faces: its triangles grouped by
## kind, plane and colour, each with the face's frame (x along, y up the
## wall or the slope, z out) and every triangle in (u, v) metres.
static func _groups(parts: Array) -> Array:
	var by := {}
	for p in parts:
		var kind: String = p[0]
		var a: Array = p[1]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm = a[Mesh.ARRAY_NORMAL]
		var col = a[Mesh.ARRAY_COLOR]
		var idx = a[Mesh.ARRAY_INDEX]
		var n_tri: int = (idx.size() if idx != null else v.size()) / 3
		for t in n_tri:
			var i0: int = idx[t * 3] if idx != null else t * 3
			var i1: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
			var i2: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
			var p0 := v[i0]
			var p1 := v[i1]
			var p2 := v[i2]
			var cr := (p1 - p0).cross(p2 - p0)
			if cr.length_squared() < 1e-6:
				continue
			var n := cr.normalized()
			if nrm != null and n.dot(nrm[i0]) < 0.0:
				n = -n
			var c: Color = col[i0] if col != null else Color.WHITE
			if kind == "siding" and c.a < 0.5:
				continue  # a garage door's panels, not laps
			if kind == "roof":
				if n.y < 0.15 or n.y > 0.97:
					continue
			elif absf(n.y) > 0.3:
				continue  # the tops of walls and sills
			var d := n.dot(p0)
			var gk := "%s|%d|%d|%d|%d|%s" % [kind, roundi(n.x * 40.0), roundi(n.y * 40.0), roundi(n.z * 40.0),
				roundi(d * 25.0), c.to_html(false)]
			if not by.has(gk):
				var y := Vector3.UP if kind != "roof" else (Vector3.UP - n * n.y).normalized()
				var x := y.cross(n).normalized()
				y = n.cross(x)
				by[gk] = {"kind": kind, "o": p0, "x": x, "y": y, "n": n, "col": c, "tris": [],
					"u0": INF, "u1": -INF, "v0": INF, "v1": -INF, "area": 0.0}
			var g: Dictionary = by[gk]
			var tri := []
			for q in [p0, p1, p2]:
				var rel: Vector3 = q - g.o
				var uv := Vector2(rel.dot(g.x), rel.dot(g.y))
				tri.append(uv)
				g.u0 = minf(g.u0, uv.x)
				g.u1 = maxf(g.u1, uv.x)
				g.v0 = minf(g.v0, uv.y)
				g.v1 = maxf(g.v1, uv.y)
			g.tris.append(tri)
			g.area += cr.length() * 0.5
	return by.values()


## Where the line v = `at` crosses the face: merged runs [u0, u1].
static func _runs(g: Dictionary, at: float) -> Array:
	if g.area >= (g.u1 - g.u0) * (g.v1 - g.v0) * 0.98:
		return [[g.u0, g.u1]]  # a plain rectangle, most walls
	var spans := []
	for tri in g.tris:
		var lo := INF
		var hi := -INF
		for k in 3:
			var a: Vector2 = tri[k]
			var b: Vector2 = tri[(k + 1) % 3]
			if (a.y - at) * (b.y - at) > 0.0 or is_equal_approx(a.y, b.y):
				continue
			var u := lerpf(a.x, b.x, (at - a.y) / (b.y - a.y))
			lo = minf(lo, u)
			hi = maxf(hi, u)
		if hi > lo:
			spans.append([lo, hi])
	if spans.size() < 2:
		return spans
	spans.sort_custom(func(p, q): return p[0] < q[0])
	var out := [spans[0]]
	for s in spans.slice(1):
		if s[0] <= out[-1][1] + 0.02:
			out[-1][1] = maxf(out[-1][1], s[1])
		else:
			out.append(s)
	return out


## Where two lists of runs overlap.
static func _both(a: Array, b: Array) -> Array:
	var out := []
	for p in a:
		for q in b:
			var lo := maxf(p[0], q[0])
			var hi := minf(p[1], q[1])
			if hi > lo:
				out.append([lo, hi])
	return out


func _put(st: Dictionary, kind: String, b: Basis, o: Vector3, custom: Color) -> void:
	if not st.bufs.has(kind):
		st.bufs[kind] = PackedFloat32Array()
		st.counts[kind] = 0
	st.bufs[kind].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		custom.r, custom.g, custom.b, custom.a])
	st.counts[kind] += 1


## Lap siding, 8 in panels of two 4 in laps, from the wall's foot to its
## top (up a gable, each course shorter under the rakes).
func _boards(st: Dictionary, g: Dictionary) -> void:
	var lap := NearMeshes.LAP * 2.0
	var v: float = g.v0
	while v < g.v1 - 0.03:
		# Cut to the face at both its edges, so a course up a gable stops
		# under the rake instead of stepping past it.
		for run in _both(_runs(g, v + 0.01), _runs(g, minf(v + lap, g.v1) - 0.01)):
			var length: float = run[1] - run[0]
			if length < 0.05:
				continue
			var col: Color = g.col
			col.a = v - g.v0
			_put(st, "board", Basis(g.x * length, g.y, g.n), g.o + g.x * run[0] + g.y * v, col)
		v += lap


## Asphalt shingles from the eave up, each course's tab slots staggered.
func _shingles(st: Dictionary, g: Dictionary) -> void:
	var step := NearMeshes.SHINGLE
	var v: float = g.v0
	var k := 0
	while v < g.v1 - step * 0.6:
		for run in _both(_runs(g, v + 0.005), _runs(g, minf(v + step, g.v1) - 0.005)):
			var length: float = run[1] - run[0]
			if length < 0.05:
				continue
			var col: Color = g.col
			col.a = 0.5 * (k % 2) + 0.17 * ((k / 2) % 3)
			_put(st, "shingle", Basis(g.x * length, g.y, g.n), g.o + g.x * run[0] + g.y * v + g.n * SHINGLE_OUT, col)
		v += step
		k += 1


## Brick in running bond on a rectangular wall, in 16 in cells (two bricks
## across, six courses up) stretched a little to fit the wall exactly, the
## mortar set back behind them. Odd shapes keep their painted brick.
func _bricks(st: Dictionary, g: Dictionary) -> void:
	var w: float = g.u1 - g.u0
	var h: float = g.v1 - g.v0
	if w < 0.25 or h < 0.25 or g.area < w * h * 0.97:
		return
	var P := NearMeshes.CELL
	var cols := maxi(1, roundi(w / P))
	var rows := maxi(1, roundi(h / P))
	var sx := w / (cols * P)
	var sy := h / (rows * P)
	var bx := Basis(g.x * sx, g.y * sy, g.n)
	var base: Vector3 = g.o + g.x * g.u0 + g.y * g.v0
	for r in rows:
		for c in cols:
			var variant := "inner"
			if cols == 1:
				variant = "solo"
			elif c == 0:
				variant = "start"
			elif c == cols - 1:
				variant = "end"
			elif (c * 7 + r * 13) % 5 == 0:
				variant = "inner2"
			_put(st, "brick_" + variant, bx, base + g.x * (c * P * sx) + g.y * (r * P * sy) + g.n * BRICK_OUT, g.col)
	_put(st, "mortar", Basis(g.x * w, g.y * h, g.n), base + g.n * MORTAR_OUT, Color.WHITE)


# ------------------------------------------------------------------ drawing

## Which quarter of its square a house is drawn with.
static func _bucket(sq: Vector2i, centre: Vector3) -> Vector3i:
	var q := posmod(floori(centre.x / (SQUARE * 0.5)), 2) + 2 * posmod(floori(centre.z / (SQUARE * 0.5)), 2)
	return Vector3i(sq.x, sq.y, q)


## One quarter square's pieces, merged by kind across its grown houses (in
## the square's frame, as the houses' walls and roofs come).
func _rebuild(bucket: Vector3i) -> void:
	var bufs := {}
	var counts := {}
	for key in _grown:
		var gr: Dictionary = _grown[key]
		if gr.bucket != bucket:
			continue
		for kind in gr.bufs:
			if not bufs.has(kind):
				bufs[kind] = PackedFloat32Array()
				counts[kind] = 0
			bufs[kind].append_array(gr.bufs[kind])
			counts[kind] += gr.counts[kind]
	var have: Dictionary = _squares.get(bucket, {})
	for kind in have.keys():
		if not bufs.has(kind):
			have[kind].queue_free()
			have.erase(kind)
	for kind in bufs:
		var mmi: MultiMeshInstance3D = have.get(kind)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = NearMeshes.of(kind)
			mmi.multimesh = mm
			mmi.material_override = NearMats.get_mat(kind)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.position = Vector3((bucket.x + 0.5) * SQUARE, 0.0, (bucket.y + 0.5) * SQUARE)
			add_child(mmi)
			have[kind] = mmi
		mmi.multimesh.instance_count = counts[kind]
		mmi.multimesh.buffer = bufs[kind]
	if have.is_empty():
		_squares.erase(bucket)
	else:
		_squares[bucket] = have


## For tests and tools: instances of each kind drawn, all squares together.
func instance_counts() -> Dictionary:
	var out := {}
	for sq in _squares:
		for kind in _squares[sq]:
			out[kind] = out.get(kind, 0) + _squares[sq][kind].multimesh.instance_count
	return out
