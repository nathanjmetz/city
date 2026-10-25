extends Node3D
## The close-up ring: within GROW_R of the camera every building is grown in
## code at real size from its facts, brick by brick (or lap by lap, rib by
## rib), with real windows, doors and shingle courses, a few small jobs a
## frame inside BUDGET_MS so it never stutters. It shows within
## Mats.NEAR_A, fading in to NEAR_B as the instanced version fades out, and
## is let go past RELEASE_R.
##
## All of a building's bricks are instances of a handful of shared 16 in
## masonry cells (MultiMesh), so growing a house is filling a few thousand
## transforms, not building its geometry.

const Facts := preload("res://tools/scale/new_drawing/facts.gd")
const Mats := preload("res://tools/scale/new_drawing/mats.gd")
const Meshes := preload("res://tools/scale/new_drawing/meshes.gd")

const GROW_R := 130.0
const RELEASE_R := 160.0
const GRID := 64.0
## Work per frame on growing (ms). The browser gets less (set by the view).
var budget_ms := 3.0

var facts := {}  # the view's
var layer: Node3D  # TownLayer, told when a close-up version shows
var _grid := {}  # Vector2i -> {key: true}
var _grown := {}  # key -> Node3D
var _jobs := {}  # key -> building state under way
var _queue: Array = []  # keys waiting, nearest first
## Measures for the lab: how much of the near ring had its close-up version.
var stats := {"frames": 0, "cover_sum": 0.0, "cover_min": 1.0, "late": 0, "grown": 0, "released": 0, "in_ring": 0}


func index(key: String) -> void:
	var c := _cell(facts[key].centre)
	if not _grid.has(c):
		_grid[c] = {}
	_grid[c][key] = true


func unindex(key: String) -> void:
	for c in _grid:
		_grid[c].erase(key)
	release(key)


func release(key: String) -> void:
	_jobs.erase(key)
	_queue.erase(key)
	if _grown.has(key):
		_grown[key].queue_free()
		_grown.erase(key)
		layer.set_ready(key, false)
		stats.released += 1


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


func update(eye: Vector3) -> void:
	# Who is near.
	var want := {}
	var r := int(ceil(RELEASE_R / GRID))
	var c0 := _cell(eye)
	var in_near := 0
	var shown := 0
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cell: Dictionary = _grid.get(c0 + Vector2i(dx, dz), {})
			for key in cell:
				var d: float = eye.distance_to(facts[key].centre)
				if d < GROW_R:
					want[key] = d
				elif d < RELEASE_R and (_grown.has(key) or _jobs.has(key)):
					want[key] = d
				if d < 100.0:
					in_near += 1
					if _grown.has(key):
						shown += 1
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
	# Grow, nearest first, inside the budget.
	var t := Time.get_ticks_usec()
	var limit := int(budget_ms * 1000.0)
	while not _queue.is_empty() and Time.get_ticks_usec() - t < limit:
		var key: String = _queue[0]
		if not _jobs.has(key):
			_jobs[key] = _start(key)
		var st: Dictionary = _jobs[key]
		_step(st)
		if st.done:
			_jobs.erase(key)
			_queue.pop_front()
			add_child(st.root)
			_grown[key] = st.root
			layer.set_ready(key, true)
			stats.grown += 1
			if want[key] < Mats.NEAR_A + 5.0:
				stats.late += 1
	stats.frames += 1
	stats.in_ring = in_near
	var cover := 1.0 if in_near == 0 else float(shown) / in_near
	stats.cover_sum += cover
	stats.cover_min = minf(stats.cover_min, cover)


func reset_stats() -> void:
	stats = {"frames": 0, "cover_sum": 0.0, "cover_min": 1.0, "late": 0, "grown": 0, "released": 0, "in_ring": 0}


func grown_count() -> int:
	return _grown.size()


# ------------------------------------------------------------------ growing

func _start(key: String) -> Dictionary:
	var f: Dictionary = facts[key]
	var root := Node3D.new()
	root.position = f.centre
	root.basis = f.basis
	var jobs := [["found"]]
	var walls := Facts.walls(f)
	for w in walls:
		jobs.append(["wall", w])
	jobs.append(["open"])
	jobs.append(["roof"])
	jobs.append(["final"])
	return {"f": f, "root": root, "walls": walls, "jobs": jobs, "done": false, "inst": {}, "count": {}, "trim": {},
		"meshes": {}}


func _step(st: Dictionary) -> void:
	var job: Array = st.jobs.pop_front()
	match job[0]:
		"found": _found(st)
		"wall": _wall(st, job[1])
		"open": _open(st)
		"roof": _roof(st)
		"final": _final(st)
	if st.jobs.is_empty():
		st.done = true


func _buf(st: Dictionary, key: String) -> PackedFloat32Array:
	if not st.inst.has(key):
		st.inst[key] = PackedFloat32Array()
		st.count[key] = 0
	return st.inst[key]


func _put(st: Dictionary, key: String, b: Basis, o: Vector3, custom: Color) -> void:
	var buf := _buf(st, key)
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		custom.r, custom.g, custom.b, custom.a])
	st.inst[key] = buf
	st.count[key] += 1


func _trim(st: Dictionary, mat: String) -> Meshes.Builder:
	if not st.trim.has(mat):
		st.trim[mat] = Meshes.Builder.new()
	return st.trim[mat]


## A quad in a wall's plane (wall coordinates u, v at depth z), facing out.
static func _wquad(b: Meshes.Builder, wf: Transform3D, u0: float, v0: float, u1: float, v1: float, z: float) -> void:
	var p := func(u: float, v: float) -> Vector3: return wf * Vector3(u, v, z)
	b.quad(p.call(u0, v0), p.call(u1, v0), p.call(u1, v1), p.call(u0, v1))


## A box in a wall's frame (u, v, z ranges).
static func _wbox(b: Meshes.Builder, wf: Transform3D, lo: Vector3, hi: Vector3) -> void:
	var tmp := Meshes.Builder.new()
	Meshes.box(tmp, lo, hi)
	var base := b.v.size()
	for i in tmp.v.size():
		b.v.append(wf * tmp.v[i])
		b.n.append(wf.basis * tmp.n[i])
		b.uv.append(Vector2.ZERO)
		b.uv2.append(Vector2.ZERO)
	for k in tmp.idx:
		b.idx.append(base + k)


func _found(st: Dictionary) -> void:
	var f: Dictionary = st.f
	var b := _trim(st, "concrete")
	for w in st.walls:
		var wf: Transform3D = Facts.wall_frame(w)
		_wquad(b, wf, -0.02, -1.25, w.len + 0.02, 0.0, 0.02)


func _masonry(f: Dictionary) -> String:
	match int(f.mat):
		Facts.Mat.BRICK, Facts.Mat.BRICK_SHOP, Facts.Mat.CURTAIN: return "brick"
		Facts.Mat.BLOCK_SHOP, Facts.Mat.BLOCK_PLANT: return "block"
	return ""


func _wall(st: Dictionary, w: Dictionary) -> void:
	var f: Dictionary = st.f
	var wf: Transform3D = Facts.wall_frame(w)
	var kind := _masonry(f)
	if kind != "":
		_masonry_wall(st, w, wf, kind)
	elif int(f.mat) == Facts.Mat.METAL:
		_metal_wall(st, w, wf)
	else:
		_siding_wall(st, w, wf)
	if w.gable and int(f.mat) != Facts.Mat.METAL:
		_gable_siding(st, w, wf)


## Cell types: 0 masonry, 1 opening, 2 soldier course, 3 rowlock sill.
func _grid_of(f: Dictionary, w: Dictionary, rows: int, brick: bool) -> PackedByteArray:
	var cols: int = w.cols
	var g := PackedByteArray()
	g.resize(cols * rows)
	for op in w.ops:
		var c0 := clampi(op[0], 0, cols)
		var c1 := clampi(op[0] + op[2], 0, cols)
		var r0 := clampi(op[1], 0, rows)
		var r1 := clampi(op[1] + op[3], 0, rows)
		for r in range(r0, r1):
			for c in range(c0, c1):
				g[r * cols + c] = 1
		if brick:
			if r1 < rows and op[4] != "curtain":
				for c in range(c0, c1):
					if g[r1 * cols + c] == 0:
						g[r1 * cols + c] = 2
			if op[4] == "win" and r0 >= 1:
				for c in range(c0, c1):
					if g[(r0 - 1) * cols + c] == 0:
						g[(r0 - 1) * cols + c] = 3
	return g


func _masonry_wall(st: Dictionary, w: Dictionary, wf: Transform3D, kind: String) -> void:
	var f: Dictionary = st.f
	var rows: int = f.eave_rows + f.parapet
	var cols: int = w.cols
	var brick := kind == "brick"
	var g := _grid_of(f, w, rows, brick)
	var P := Facts.CELL
	var bx := wf.basis
	var tint: Color = f.tint if brick else f.wall
	var pre := "m_%s_" % kind
	for r in rows:
		for c in cols:
			var t := g[r * cols + c]
			if t == 1:
				continue
			var key: String
			if t == 2:
				key = pre + "soldier"
			elif t == 3:
				key = pre + "sill"
			else:
				var left := c > 0 and g[r * cols + c - 1] == 0
				var right := c < cols - 1 and g[r * cols + c + 1] == 0
				if left and right:
					key = pre + ("inner2" if brick and ((c * 7 + r * 13) % 5 == 0) else "inner")
				elif right:
					key = pre + "start"
				elif left:
					key = pre + "end"
				else:
					key = pre + "solo"
			var o: Vector3 = wf.origin + bx.x * (w.u0 + c * P) + bx.y * (r * P)
			_put(st, key, bx, o, tint)
	# Mortar behind, set back 8 mm, in runs (it casts the wall's shadow).
	var mortar := _trim(st, "mortar")
	for r in rows:
		var c := 0
		while c < cols:
			if g[r * cols + c] == 1:
				c += 1
				continue
			var c1 := c
			while c1 < cols and g[r * cols + c1] != 1:
				c1 += 1
			var u0: float = w.u0 + c * P
			var u1: float = w.u0 + c1 * P
			if c == 0:
				u0 = 0.0
			if c1 == cols:
				u1 = w.len
			_wquad(mortar, wf, u0, r * P, u1, (r + 1) * P, -0.008)
			c = c1
	# Steel lintels over the openings.
	var dark := _trim(st, "dark")
	for op in w.ops:
		if op[4] == "curtain":
			continue
		var u0: float = w.u0 + op[0] * P
		var top: float = (op[1] + op[3]) * P
		_wbox(dark, wf, Vector3(u0 - 0.1, top - 0.008, -0.1), Vector3(u0 + op[2] * P + 0.1, top, -0.004))
	# A parapet's inside face and its metal coping.
	if f.parapet > 0:
		var roof_y: float = f.eave_rows * P
		var top_y: float = rows * P
		var inner := Transform3D(Basis(-bx.x, bx.y, -bx.z), wf.origin + bx.x * w.len - bx.z * Facts.BRICK_D)
		_wquad(mortar, inner, 0.0, roof_y, w.len, top_y, 0.0)
		_wbox(_trim(st, "coping"), wf, Vector3(0.0, top_y, -Facts.BRICK_D - 0.03), Vector3(w.len, top_y + 0.05, 0.03))


func _siding_wall(st: Dictionary, w: Dictionary, wf: Transform3D) -> void:
	var f: Dictionary = st.f
	var rows: int = f.eave_rows + f.parapet
	var cols: int = w.cols
	var g := _grid_of(f, w, rows, false)
	var P := Facts.CELL
	var bx := wf.basis
	var col: Color = f.wall
	var wrap := _trim(st, "wrap")
	var trim := _trim(st, "trim")
	var casing := 0.09
	for r in rows:
		var c := 0
		while c < cols:
			if g[r * cols + c] == 1:
				c += 1
				continue
			var c1 := c
			while c1 < cols and g[r * cols + c1] != 1:
				c1 += 1
			var u0: float = 0.0 if c == 0 else w.u0 + c * P + casing
			var u1: float = w.len if c1 == cols else w.u0 + c1 * P - casing
			_wquad(wrap, wf, 0.0 if c == 0 else w.u0 + c * P, r * P, w.len if c1 == cols else w.u0 + c1 * P, (r + 1) * P, -0.004)
			if u1 > u0 + 0.01:
				for k in 4:
					var o := wf.origin + bx.x * u0 + bx.y * (r * P + k * Facts.LAP)
					_put(st, "board", Basis(bx.x * (u1 - u0), bx.y, bx.z), o, col)
			c = c1
	# Casing round each opening, a sill under each window.
	for op in w.ops:
		var u0: float = w.u0 + op[0] * P
		var u1: float = u0 + op[2] * P
		var v0: float = op[1] * P
		var v1: float = (op[1] + op[3]) * P
		_wbox(trim, wf, Vector3(u0 - casing, v1, 0.0), Vector3(u1 + casing, v1 + 0.11, 0.026))
		_wbox(trim, wf, Vector3(u0 - casing, v0, 0.0), Vector3(u0, v1, 0.024))
		_wbox(trim, wf, Vector3(u1, v0, 0.0), Vector3(u1 + casing, v1, 0.024))
		if op[4] == "win":
			_wbox(trim, wf, Vector3(u0 - 0.12, v0 - 0.045, 0.0), Vector3(u1 + 0.12, v0, 0.055))
	# Corner boards.
	var h: float = rows * P
	_wbox(trim, wf, Vector3(-0.02, 0.0, 0.0), Vector3(0.1, h, 0.028))
	_wbox(trim, wf, Vector3(w.len - 0.1, 0.0, 0.0), Vector3(w.len + 0.02, h, 0.028))


## Lap siding up a gable end, each course shorter under the rakes.
func _gable_siding(st: Dictionary, w: Dictionary, wf: Transform3D) -> void:
	var f: Dictionary = st.f
	var g := Facts.gable_h(f)
	if g < 0.2:
		return
	var y0: float = f.eave_rows * Facts.CELL
	var bx := wf.basis
	var col: Color = f.wall if int(f.mat) == Facts.Mat.SIDING else Color("#e9e6dc")
	var t := 0.0
	while t < g - 0.06:
		var width: float = w.len * (1.0 - (t + Facts.LAP * 0.5) / g)
		var u0: float = (w.len - width) * 0.5
		_put(st, "board", Basis(bx.x * width, bx.y, bx.z), wf.origin + bx.x * u0 + bx.y * (y0 + t), col)
		t += Facts.LAP
	var wrap := _trim(st, "wrap")
	wrap.tri(wf * Vector3(0, y0, -0.004), wf * Vector3(w.len, y0, -0.004), wf * Vector3(w.len * 0.5, y0 + g, -0.004))


## A metal building's wall: 12 in ribbed panels, cut round its openings,
## up into the low gable.
func _metal_wall(st: Dictionary, w: Dictionary, wf: Transform3D) -> void:
	var f: Dictionary = st.f
	var P := Facts.CELL
	var h: float = f.eave_rows * P
	var bx := wf.basis
	var g := Facts.gable_h(f) if w.gable else 0.0
	var n := int(ceil(w.len / 0.3048))
	var spans := []
	for op in w.ops:
		spans.append([w.u0 + op[0] * P, w.u0 + (op[0] + op[2]) * P, op[1] * P, (op[1] + op[3]) * P])
	for k in n:
		var u := k * 0.3048
		var top := h
		if g > 0.0:
			top = h + g * (1.0 - absf(u + 0.15 - w.len * 0.5) / (w.len * 0.5))
		var cuts := []
		for s in spans:
			if u + 0.3048 > s[0] and u < s[1]:
				cuts.append([s[2], s[3]])
		cuts.sort_custom(func(a, b): return a[0] < b[0])
		var y := 0.2
		for cut in cuts:
			if cut[0] > y + 0.05:
				_put(st, "rib", Basis(bx.x, bx.y * (cut[0] - y), bx.z), wf.origin + bx.x * u + bx.y * y, f.wall)
			y = maxf(y, cut[1])
		if top > y + 0.05:
			_put(st, "rib", Basis(bx.x, bx.y * (top - y), bx.z), wf.origin + bx.x * u + bx.y * y, f.wall)
	var wrap := _trim(st, "wrap")
	_wquad(wrap, wf, 0.0, 0.0, w.len, h, -0.01)
	if g > 0.0:
		wrap.tri(wf * Vector3(0, h, -0.01), wf * Vector3(w.len, h, -0.01), wf * Vector3(w.len * 0.5, h + g, -0.01))
	# A concrete curb at the base, and flashing round the openings.
	_wbox(_trim(st, "concrete"), wf, Vector3(0.0, -0.1, 0.0), Vector3(w.len, 0.2, 0.05))
	var dark := _trim(st, "coping")
	for s in spans:
		_wbox(dark, wf, Vector3(s[0] - 0.06, s[3], 0.0), Vector3(s[1] + 0.06, s[3] + 0.08, 0.06))
		_wbox(dark, wf, Vector3(s[0] - 0.06, s[2], 0.0), Vector3(s[0], s[3], 0.05))
		_wbox(dark, wf, Vector3(s[1], s[2], 0.0), Vector3(s[1] + 0.06, s[3], 0.05))


func _open(st: Dictionary) -> void:
	var f: Dictionary = st.f
	var P := Facts.CELL
	var masonry := _masonry(f) != ""
	var res := String(f.type) in ["house", "row_home", "apartments"]
	for w in st.walls:
		var wf: Transform3D = Facts.wall_frame(w)
		var bx := wf.basis
		for op in w.ops:
			var kind: String = op[4]
			if kind == "win" and not res:
				kind = "comm"
			var ow: float = op[2] * P
			var oh: float = op[3] * P
			var key := "o_%s_%.2f_%.2f" % [kind, ow, oh]
			st.meshes[key] = [kind, ow, oh]
			var z := -0.03 if masonry else 0.02
			if int(f.mat) == Facts.Mat.METAL:
				z = 0.03
			var o: Vector3 = wf.origin + bx.x * (w.u0 + op[0] * P) + bx.y * (op[1] * P) + bx.z * z
			var col: Color = f.door if kind == "door" else Color("#c9c6bd")
			_put(st, key, bx, o, col)


func _roof(st: Dictionary) -> void:
	var f: Dictionary = st.f
	var h: float = f.eave_rows * Facts.CELL
	if int(f.roof) == Facts.Roof.FLAT:
		var mem := _trim(st, "membrane")
		var hw: float = f.w * 0.5 - Facts.BRICK_D
		var hd: float = f.d * 0.5 - Facts.BRICK_D
		mem.quad(Vector3(-hw, h, hd), Vector3(hw, h, hd), Vector3(hw, h, -hd), Vector3(-hw, h, -hd))
		# Rooftop units on a commercial roof.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(f.seed)
		var hv := _trim(st, "hvac")
		for i in rng.randi_range(1, 3):
			var x := rng.randf_range(-hw + 2.0, hw - 2.0)
			var z := rng.randf_range(-hd + 2.0, hd - 2.0)
			Meshes.box(hv, Vector3(x - 0.8, h, z - 0.6), Vector3(x + 0.8, h + 1.1, z + 0.6))
		return
	var long_x: bool = f.ridge_x
	var a := Vector3.RIGHT if long_x else Vector3.BACK
	var b := Vector3.BACK if long_x else Vector3.RIGHT
	var lx: float = f.w if long_x else f.d
	var lz: float = f.d if long_x else f.w
	var p: float = f.pitch
	var oh := 0.3
	var rake := 0.2
	var metal := int(f.top) == Facts.Top.METAL_TOP
	var hip := int(f.roof) == Facts.Roof.HIP
	var run := lz * 0.5 + oh
	var slope_len := run * sqrt(1.0 + p * p)
	var eave_y := h - oh * p
	var cosa := 1.0 / sqrt(1.0 + p * p)
	var deck := _trim(st, "deck")
	var trim := _trim(st, "trim" if not metal else "coping")
	var planes := []
	# [eave edge middle, outward dir, length along the eave, ridge length (hip), along dir]
	for sgn in [-1.0, 1.0]:
		planes.append([b * sgn * run, b * sgn, lx + (2.0 * oh if hip else 2.0 * rake), a])
	if hip:
		for sgn in [-1.0, 1.0]:
			planes.append([a * sgn * (lx * 0.5 + oh), a * sgn, lz + 2.0 * oh, b])
	for pi in planes.size():
		var pl: Array = planes[pi]
		var e: Vector3 = pl[0] + Vector3.UP * eave_y
		var out: Vector3 = pl[1]
		var up := (-out + Vector3.UP * p).normalized()
		var nrm := (out * p + Vector3.UP).normalized()
		var x := up.cross(nrm)
		var base_len: float = pl[2]
		var k := 0
		var s := 0.0
		var step := 0.3048 if metal else Facts.SHINGLE
		if metal:
			var n := int(base_len / step)
			for i in n:
				var o := e - x * (base_len * 0.5) + x * (i * step) + nrm * 0.01
				_put(st, "rib", Basis(x, up * slope_len, nrm), o, f.roof_col)
		else:
			while s < slope_len - 0.04:
				var inset := s * cosa if hip else 0.0
				var length := base_len - 2.0 * inset
				if length <= 0.05:
					break
				var o := e - x * (length * 0.5) + up * s + nrm * 0.012
				var cd: Color = f.roof_col
				cd.a = 0.5 * (k % 2) + 0.17 * ((k / 2) % 3)
				_put(st, "shingle", Basis(x * length, up, nrm), o, cd)
				s += Facts.SHINGLE
				k += 1
			# A cap course along the ridge.
			if pi < 2 and (not hip or lx > lz):
				var cl: float = (lx - lz if hip else base_len)
				if cl > 0.05:
					var o := e - x * (cl * 0.5) + up * (slope_len - 0.12) + nrm * 0.02
					_put(st, "shingle", Basis(x * cl, up, nrm), o, f.roof_col)
		# The deck under it (it casts the roof's shadow).
		var top_len := maxf(base_len - 2.0 * run, 0.0) if hip else base_len
		var r := e + up * slope_len
		deck.quad(e - x * (base_len * 0.5), e + x * (base_len * 0.5), r + x * (top_len * 0.5), r - x * (top_len * 0.5))
		# Fascia along the eave and the soffit under the overhang.
		var fl := e - x * (base_len * 0.5)
		var fr := e + x * (base_len * 0.5)
		trim.quad(fl - Vector3.UP * 0.18, fr - Vector3.UP * 0.18, fr, fl, Vector2.ZERO, Vector2.ZERO, false, [], out)
		var wl := fl - out * oh
		var wr := fr - out * oh
		wl.y = h - 0.18
		wr.y = h - 0.18
		trim.quad(fl - Vector3.UP * 0.18, wl, wr, fr - Vector3.UP * 0.18, Vector2.ZERO, Vector2.ZERO, false, [], Vector3.DOWN)
	# Rake boards along the gable ends.
	if not hip:
		for end in [-1.0, 1.0]:
			var ex: Vector3 = a * end * (lx * 0.5 + rake)
			var ridge := ex + Vector3.UP * (h + (lz * 0.5) * p)
			for sgn in [-1.0, 1.0]:
				var ee: Vector3 = ex + b * sgn * run + Vector3.UP * eave_y
				trim.quad(ee - Vector3.UP * 0.16, ridge - Vector3.UP * 0.16, ridge, ee, Vector2.ZERO, Vector2.ZERO, false, [],
					a * end)


func _final(st: Dictionary) -> void:
	var root: Node3D = st.root
	for key in st.inst:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var mat := ""
		if key.begins_with("m_"):
			var parts: PackedStringArray = key.split("_")
			mm.mesh = Meshes.masonry(parts[1], parts[2])
			mat = parts[1]
		elif key == "board":
			mm.mesh = Meshes.board()
			mat = "siding"
		elif key == "shingle":
			mm.mesh = Meshes.shingle()
			mat = "shingle"
		elif key == "rib":
			mm.mesh = Meshes.rib()
			mat = "metal_wall"
		else:
			var m: Array = st.meshes[key]
			mm.mesh = Meshes.opening(m[0], m[1], m[2])
		mm.instance_count = st.count[key]
		mm.buffer = st.inst[key]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if mat != "":
			mmi.material_override = Mats.get_mat(mat)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	var mesh := ArrayMesh.new()
	for mat in st.trim:
		var b: Meshes.Builder = st.trim[mat]
		b.commit(mesh, Mats.get_mat(mat))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
