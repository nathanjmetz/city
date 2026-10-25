extends RefCounted
## The unit meshes every building shares, made once: the far shapes, the
## middle version's pieces, and the close-up pieces (masonry cells, a lap
## board, a shingle course, a metal rib, windows and doors by size). Each
## building is then only instance transforms of these.

const Facts := preload("res://tools/scale/new_drawing/facts.gd")
const Mats := preload("res://tools/scale/new_drawing/mats.gd")

static var _cache := {}


## Collects one surface: positions, normals, UV, UV2, indices (and, for a
## masonry cell, a lighter index list of just the faces).
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var lite := PackedInt32Array()

	## A flat quad a, b, c, d (counter-clockwise seen from its front).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t := Vector2.ZERO, t2 := Vector2.ZERO,
			face := false, t2s := [], nrm := Vector3.ZERO) -> void:
		var geo := (b - a).cross(d - a)
		var pts := [a, b, c, d]
		if nrm != Vector3.ZERO and geo.dot(nrm) < 0.0:
			pts = [a, d, c, b]
			if not t2s.is_empty():
				t2s = [t2s[0], t2s[3], t2s[2], t2s[1]]
		var nn := nrm if nrm != Vector3.ZERO else geo.normalized()
		var base := v.size()
		for i in 4:
			v.append(pts[i])
			n.append(nn)
			uv.append(t)
			uv2.append(t2 if t2s.is_empty() else t2s[i])
		# Godot's front faces wind clockwise as seen from the front.
		for k in [0, 2, 1, 0, 3, 2]:
			idx.append(base + k)
			if face:
				lite.append(base + k)

	func tri(a: Vector3, b: Vector3, c: Vector3, t := Vector2.ZERO, t2 := Vector2.ZERO) -> void:
		var nn := (b - a).cross(c - a).normalized()
		var base := v.size()
		for p in [a, b, c]:
			v.append(p)
			n.append(nn)
			uv.append(t)
			uv2.append(t2)
		for k in [0, 2, 1]:
			idx.append(base + k)

	func commit(mesh: ArrayMesh = null, mat: Material = null, lods := {}) -> ArrayMesh:
		if mesh == null:
			mesh = ArrayMesh.new()
		if v.is_empty():
			return mesh
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], lods)
		if mat != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		return mesh


## A box's faces from lo to hi (no bottom), into `b`.
static func box(b: Builder, lo: Vector3, hi: Vector3, t := Vector2.ZERO, bottom := false) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	b.quad(p[1], p[0], p[4], p[5], t)  # -z
	b.quad(p[3], p[2], p[6], p[7], t)  # +z
	b.quad(p[0], p[3], p[7], p[4], t)  # -x
	b.quad(p[2], p[1], p[5], p[6], t)  # +x
	b.quad(p[4], p[7], p[6], p[5], t)  # top
	if bottom:
		b.quad(p[0], p[1], p[2], p[3], t)


# ------------------------------------------------------------- far shapes

## A unit box, x and z from -0.5 to 0.5, y from 0 to 1. The top is a roof.
static func shape_box() -> ArrayMesh:
	if _cache.has("box"):
		return _cache.box
	var b := Builder.new()
	var p := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var up := Vector3.UP
	for k in 4:
		var a: Vector3 = p[k]
		var c: Vector3 = p[(k + 1) % 4]
		b.quad(c, a, a + up, c + up)
	b.quad(p[0] + up, p[3] + up, p[2] + up, p[1] + up, Vector2(1, 0))
	_cache.box = b.commit()
	return _cache.box


## A unit gable roof: ridge along x at y = 1, eaves at z = +-0.5, y = 0.
## UV.x 1 on the slopes, 0 on the gable triangles.
static func shape_gable() -> ArrayMesh:
	if _cache.has("gable"):
		return _cache.gable
	var b := Builder.new()
	var r0 := Vector3(-0.5, 1, 0)
	var r1 := Vector3(0.5, 1, 0)
	b.quad(Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5), r0, r1, Vector2(1, 0))
	b.quad(Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), r1, r0, Vector2(1, 0))
	b.tri(Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), r0)
	b.tri(Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), r1)
	_cache.gable = b.commit()
	return _cache.gable


## A unit hip roof; its ridge ends (UV2.x 1) move in by the shader so every
## side keeps the same pitch.
static func shape_hip() -> ArrayMesh:
	if _cache.has("hip"):
		return _cache.hip
	var b := Builder.new()
	var r0 := Vector3(-0.25, 1, 0)
	var r1 := Vector3(0.25, 1, 0)
	var e := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var f := Vector2(1, 0)
	var rr := Vector2(1, 0)
	b.quad(e[1], e[0], r0, r1, f, Vector2.ZERO, false, [Vector2.ZERO, Vector2.ZERO, rr, rr])
	b.quad(e[3], e[2], r1, r0, f, Vector2.ZERO, false, [Vector2.ZERO, Vector2.ZERO, rr, rr])
	# Hip ends: triangles (a degenerate quad keeps the anchors simple).
	b.quad(e[0], e[3], r0, r0, f, Vector2.ZERO, false, [Vector2.ZERO, Vector2.ZERO, rr, rr])
	b.quad(e[2], e[1], r1, r1, f, Vector2.ZERO, false, [Vector2.ZERO, Vector2.ZERO, rr, rr])
	_cache.hip = b.commit()
	return _cache.hip


## A unit ground quad (paving).
static func pave() -> ArrayMesh:
	if _cache.has("pave"):
		return _cache.pave
	var b := Builder.new()
	b.quad(Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5))
	_cache.pave = b.commit()
	return _cache.pave


# ---------------------------------------------------------- middle pieces

## A middle-version opening on a wall: unit [0,1] x [0,1] in the wall plane
## (x right, y up, z out). Frame width stays fw metres (UV2 offsets).
## kind: "win" (frame, sash rail, sill, glass), "door" (frame and slab),
## "store" (dark frame, glass, a door), "bay" (an overhead door).
static func extra(kind: String) -> ArrayMesh:
	var key := "x_" + kind
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var fw := 0.07
	var z := 0.04
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var inward := [Vector2(fw, fw), Vector2(-fw, fw), Vector2(-fw, -fw), Vector2(fw, -fw)]
	var fill := 1.0 if kind in ["win", "store"] else 2.0
	# The infill (glass or a slab), set back.
	b.quad(Vector3(0, 0, 0.0), Vector3(1, 0, 0.0), Vector3(1, 1, 0.0), Vector3(0, 1, 0.0), Vector2(fill, 0),
		Vector2.ZERO, false, inward, Vector3(0, 0, 1))
	# The frame ring, proud of the wall.
	for k in 4:
		var a: Vector2 = corners[k]
		var c: Vector2 = corners[(k + 1) % 4]
		b.quad(Vector3(a.x, a.y, z), Vector3(c.x, c.y, z), Vector3(c.x, c.y, z), Vector3(a.x, a.y, z), Vector2.ZERO,
			Vector2.ZERO, false, [Vector2.ZERO, Vector2.ZERO, inward[(k + 1) % 4], inward[k]], Vector3(0, 0, 1))
	if kind == "win":
		# The meeting rail across the middle, and a sill.
		b.quad(Vector3(0, 0.5, z), Vector3(1, 0.5, z), Vector3(1, 0.5, z), Vector3(0, 0.5, z), Vector2.ZERO, Vector2.ZERO,
			false, [Vector2(0, -0.025), Vector2(0, -0.025), Vector2(0, 0.025), Vector2(0, 0.025)], Vector3(0, 0, 1))
		b.quad(Vector3(0, 0, 0.09), Vector3(1, 0, 0.09), Vector3(1, 0, 0.0), Vector3(0, 0, 0.0), Vector2.ZERO, Vector2.ZERO,
			false, [Vector2(-0.05, 0), Vector2(0.05, 0), Vector2(0.05, 0), Vector2(-0.05, 0)], Vector3(0, 1, 0))
	elif kind == "store":
		# A transom bar and a door's stiles in the middle.
		b.quad(Vector3(0, 0.78, z), Vector3(1, 0.78, z), Vector3(1, 0.78, z), Vector3(0, 0.78, z), Vector2.ZERO, Vector2.ZERO,
			false, [Vector2(0, -0.03), Vector2(0, -0.03), Vector2(0, 0.03), Vector2(0, 0.03)], Vector3(0, 0, 1))
		for x in [0.42, 0.58]:
			b.quad(Vector3(x, 0, z), Vector3(x, 0, z), Vector3(x, 0.78, z), Vector3(x, 0.78, z), Vector2.ZERO, Vector2.ZERO,
				false, [Vector2(-0.03, 0), Vector2(0.03, 0), Vector2(0.03, 0), Vector2(-0.03, 0)], Vector3(0, 0, 1))
	elif kind == "bay":
		for k in range(1, 5):
			var y := k / 5.0
			b.quad(Vector3(0, y, 0.02), Vector3(1, y, 0.02), Vector3(1, y, 0.02), Vector3(0, y, 0.02), Vector2(2, 0),
				Vector2.ZERO, false, [Vector2(0, -0.02), Vector2(0, -0.02), Vector2(0, 0.02), Vector2(0, 0.02)], Vector3(0, 0, 1))
	_cache[key] = b.commit()
	return _cache[key]


# ---------------------------------------------------------- close-up pieces

## A masonry cell, 16 x 16 in: brick (two across, six courses) or concrete
## block (one across, two courses), in running bond. variant: "inner" (its
## B courses reach half a unit into the cell to the left), "start" (cut
## at its left: an opening or the wall's start), "end" (filled to its
## right edge), "solo" (both); for brick also "inner2" (other chips),
## "soldier" (a soldier course on its lower half, over an opening) and
## "sill" (a rowlock sill on its top, under a window). Front face at z = 0,
## back into the wall (-z). UV2 is each unit's middle, for its colour.
static func masonry(kind: String, variant: String) -> ArrayMesh:
	var key := "m_%s_%s" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var P := Facts.CELL
	var block := kind == "block"
	var unit_h := 0.193675 if block else Facts.BRICK_H
	var course := 0.2032 if block else Facts.COURSE
	var unit_l := P if block else P * 0.5  # module along the course
	var j := Facts.HEAD_J
	var depth := 0.1937 if block else Facts.BRICK_D
	var n_courses := 2 if block else 6
	var start := variant in ["start", "solo", "soldier", "sill"]
	var fill_end := variant in ["end", "solo", "soldier", "sill"]
	var first := 0
	var last := n_courses
	if variant == "soldier":
		first = 3
		var sw := P / 6.0
		for k in 6:
			_unit(b, rng, Vector3(k * sw, 0.0, 0.0), Vector3(sw - j, 3.0 * course - (course - unit_h), depth), 0.0)
	if variant == "sill":
		last = 4
		var sw := P / 6.0
		var y0 := 4.0 * course
		for k in 6:
			_unit(b, rng, Vector3(k * sw, y0, 0.03), Vector3(sw - j, P - y0 - 0.006, depth * 0.9), -0.25)
	for r in range(first, last):
		var y := r * course
		var odd := r % 2 == 1
		var xs := []  # [x0, x1]
		if not odd:
			var x := 0.0
			while x < P - 0.001:
				var x1 := x + unit_l - j
				if fill_end and x + unit_l >= P - 0.001:
					x1 = P
				xs.append([x, x1])
				x += unit_l
		else:
			var x := -unit_l * 0.5
			if start:
				xs.append([0.0, unit_l * 0.5 - j])
				x = unit_l * 0.5
			while x < P - unit_l * 0.5 - 0.001:
				xs.append([x, x + unit_l - j])
				x += unit_l
			if fill_end:
				xs.append([P - unit_l * 0.5, P])
		for s in xs:
			_unit(b, rng, Vector3(s[0], y, 0.0), Vector3(s[1] - s[0], unit_h, depth), 0.0)
	# Front faces only, past where the joints' shadows show.
	var lite := b.lite
	var mesh := b.commit(null, null, {0.012: lite})
	_cache[key] = mesh
	return mesh


## One brick or block: a beveled unit a hair off square, a corner chipped
## now and then (as in the brick lab, 2026-10-25).
static func _unit(b: Builder, rng: RandomNumberGenerator, at: Vector3, size: Vector3, lean: float) -> void:
	var j := Vector3(rng.randf_range(-0.0012, 0.0012), rng.randf_range(-0.0008, 0.0008), rng.randf_range(-0.0015, 0.001))
	var s := size + Vector3(rng.randf_range(-0.002, 0.0015), rng.randf_range(-0.001, 0.001), 0)
	var o := at + j
	var bv := 0.003
	var f := [Vector3(o.x + bv, o.y + bv, o.z), Vector3(o.x + s.x - bv, o.y + bv, o.z), Vector3(o.x + s.x - bv, o.y + s.y - bv, o.z),
		Vector3(o.x + bv, o.y + s.y - bv, o.z)]
	var e := [Vector3(o.x, o.y, o.z - bv), Vector3(o.x + s.x, o.y, o.z - bv), Vector3(o.x + s.x, o.y + s.y, o.z - bv),
		Vector3(o.x, o.y + s.y, o.z - bv)]
	var k := [Vector3(o.x, o.y, o.z - s.z), Vector3(o.x + s.x, o.y, o.z - s.z), Vector3(o.x + s.x, o.y + s.y, o.z - s.z),
		Vector3(o.x, o.y + s.y, o.z - s.z)]
	for i in 4:
		if rng.randf() < 0.18:
			f[i] = f[i].lerp(e[i], 0.9) + Vector3(0, 0, -rng.randf_range(0.001, 0.004))
	for i in 4:
		f[i].z += rng.randf_range(-0.0007, 0.0007)
	if lean != 0.0:
		for arr in [f, e, k]:
			for i in 4:
				var p: Vector3 = arr[i]
				arr[i] = Vector3(p.x, p.y + (p.z - o.z) * lean, p.z + (p.y - o.y) * lean * 0.3)
	var mid := Vector2(o.x + s.x * 0.5, o.y + s.y * 0.5)
	b.quad(f[0], f[1], f[2], f[3], Vector2.ZERO, mid, true)
	for i in 4:
		var nx := (i + 1) % 4
		b.quad(e[i], e[nx], f[nx], f[i], Vector2.ZERO, mid)
		b.quad(k[i], k[nx], e[nx], e[i], Vector2.ZERO, mid)


## A lap siding board, 1 m long (scaled to its run), 4 in to the weather:
## its face leans out to a 1/2 in butt at the bottom.
static func board() -> ArrayMesh:
	if _cache.has("board"):
		return _cache.board
	var b := Builder.new()
	var t := 0.012
	var top := Facts.LAP + 0.006
	b.quad(Vector3(0, 0, t), Vector3(1, 0, t), Vector3(1, top, 0.001), Vector3(0, top, 0.001))
	b.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, t), Vector3(0, 0, t))
	_cache.board = b.commit()
	return _cache.board


## A course of shingles, 1 m long (scaled), laid up the slope (+y) on the
## roof (+z out): the exposed 5 in and the butt edge.
static func shingle() -> ArrayMesh:
	if _cache.has("shingle"):
		return _cache.shingle
	var b := Builder.new()
	var t := 0.007
	var top := Facts.SHINGLE + 0.02
	b.quad(Vector3(0, 0, t), Vector3(1, 0, t), Vector3(1, top, 0.0), Vector3(0, top, 0.0))
	b.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, t), Vector3(0, 0, t))
	_cache.shingle = b.commit()
	return _cache.shingle


## One rib module of a metal building's wall or roof panel, 12 in across
## and 1 m long (scaled): a flat pan and a trapezoid rib.
static func rib() -> ArrayMesh:
	if _cache.has("rib"):
		return _cache.rib
	var b := Builder.new()
	var w := 0.3048
	var h := 0.032
	var pts := [Vector2(0, 0), Vector2(0.19, 0), Vector2(0.215, h), Vector2(0.27, h), Vector2(0.295, 0), Vector2(w, 0)]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		b.quad(Vector3(a.x, 0, a.y), Vector3(c.x, 0, c.y), Vector3(c.x, 1, c.y), Vector3(a.x, 1, a.y))
	_cache.rib = b.commit()
	return _cache.rib


## A close-up window, door or storefront for an opening `w` x `h` metres,
## its face at z = 0 (set into the opening): kind "win" (white vinyl
## double-hung), "comm" (dark aluminium, fixed), "store", "door" (a
## six-panel door, its slab in the instance's colour), "bay" (a sectional
## overhead door), "curtain" (glass between mullions).
static func opening(kind: String, w: float, h: float) -> ArrayMesh:
	var key := "o_%s_%.2f_%.2f" % [kind, w, h]
	if _cache.has(key):
		return _cache[key]
	var frame := Builder.new()
	var glass := Builder.new()
	var slab := Builder.new()
	var fw := 0.06
	var fd := 0.1
	match kind:
		"win", "comm":
			# Frame.
			box(frame, Vector3(0, 0, -fd), Vector3(fw, h, 0))
			box(frame, Vector3(w - fw, 0, -fd), Vector3(w, h, 0))
			box(frame, Vector3(fw, h - fw, -fd), Vector3(w - fw, h, 0))
			box(frame, Vector3(fw, 0, -fd), Vector3(w - fw, fw, 0.01))
			if kind == "win":
				# Two sashes: the lower in front of the upper, a meeting rail.
				var sw := 0.045
				for s in 2:
					var y0 := fw + s * (h - 2 * fw) * 0.5
					var y1 := y0 + (h - 2 * fw) * 0.5
					var z := -0.03 - s * 0.035
					box(frame, Vector3(fw, y0, z - 0.03), Vector3(fw + sw, y1, z))
					box(frame, Vector3(w - fw - sw, y0, z - 0.03), Vector3(w - fw, y1, z))
					box(frame, Vector3(fw + sw, y0, z - 0.03), Vector3(w - fw - sw, y0 + sw, z))
					box(frame, Vector3(fw + sw, y1 - sw, z - 0.03), Vector3(w - fw - sw, y1, z))
					glass.quad(Vector3(fw + sw, y0 + sw, z - 0.02), Vector3(w - fw - sw, y0 + sw, z - 0.02),
						Vector3(w - fw - sw, y1 - sw, z - 0.02), Vector3(fw + sw, y1 - sw, z - 0.02))
			else:
				glass.quad(Vector3(fw, fw, -0.05), Vector3(w - fw, fw, -0.05), Vector3(w - fw, h - fw, -0.05), Vector3(fw, h - fw, -0.05))
		"store", "curtain":
			var bar := 0.05
			var n := maxi(1, int(round(w / (1.5 if kind == "curtain" else 1.8))))
			box(frame, Vector3(0, 0, -fd), Vector3(bar, h, 0))
			box(frame, Vector3(w - bar, 0, -fd), Vector3(w, h, 0))
			box(frame, Vector3(0, h - bar, -fd), Vector3(w, h, 0))
			box(frame, Vector3(0, 0, -fd), Vector3(w, bar, 0))
			for i in range(1, n):
				var x := w * i / n
				box(frame, Vector3(x - bar * 0.5, 0, -fd), Vector3(x + bar * 0.5, h, 0))
			var transom := h - 0.6 if kind == "store" and h > 2.6 else -1.0
			if transom > 0.0:
				box(frame, Vector3(0, transom, -fd), Vector3(w, transom + bar, 0))
			if kind == "store":
				# A door in the middle bay, with a push bar.
				var dx := w * 0.5 - 0.46
				box(frame, Vector3(dx - 0.05, 0, -0.02), Vector3(dx, 2.13, 0.01))
				box(frame, Vector3(dx + 0.92, 0, -0.02), Vector3(dx + 0.97, 2.13, 0.01))
				box(frame, Vector3(dx, 2.08, -0.02), Vector3(dx + 0.92, 2.13, 0.01))
				box(frame, Vector3(dx, 0.95, -0.01), Vector3(dx + 0.92, 1.0, 0.02))
			glass.quad(Vector3(0, 0, -0.06), Vector3(w, 0, -0.06), Vector3(w, h, -0.06), Vector3(0, h, -0.06))
		"door":
			box(frame, Vector3(0, 0, -fd), Vector3(fw, h, 0.005))
			box(frame, Vector3(w - fw, 0, -fd), Vector3(w, h, 0.005))
			box(frame, Vector3(fw, h - fw, -fd), Vector3(w - fw, h, 0.005))
			var z := -0.05
			slab.quad(Vector3(fw, 0, z), Vector3(w - fw, 0, z), Vector3(w - fw, h - fw, z), Vector3(fw, h - fw, z))
			# Six raised panels.
			var pw := (w - 2 * fw - 0.3) * 0.5
			var ys := [[0.15, 0.8], [0.95, 1.6], [1.72, h - fw - 0.12]]
			for row in ys:
				for c in 2:
					var x0 := fw + 0.1 + c * (pw + 0.1)
					box(slab, Vector3(x0, row[0], z), Vector3(x0 + pw, row[1], z + 0.012))
			# The knob.
			box(frame, Vector3(w - fw - 0.12, 0.95, z), Vector3(w - fw - 0.08, 1.0, z + 0.06))
		"bay":
			box(frame, Vector3(0, 0, -fd), Vector3(0.08, h, 0.0))
			box(frame, Vector3(w - 0.08, 0, -fd), Vector3(w, h, 0.0))
			box(frame, Vector3(0, h - 0.1, -fd), Vector3(w, h, 0.0))
			var sec := 0.53
			var y := 0.0
			while y < h - 0.1:
				var y1 := minf(y + sec, h - 0.1)
				slab.quad(Vector3(0.08, y, -0.06), Vector3(w - 0.08, y, -0.06), Vector3(w - 0.08, y1 - 0.01, -0.04),
					Vector3(0.08, y1 - 0.01, -0.04))
				slab.quad(Vector3(0.08, y1 - 0.01, -0.04), Vector3(w - 0.08, y1 - 0.01, -0.04), Vector3(w - 0.08, y1, -0.06),
					Vector3(0.08, y1, -0.06))
				y = y1
	var mesh := ArrayMesh.new()
	var frame_mat := "vinyl" if kind in ["win", "door"] else ("dark" if kind == "bay" else "alum")
	frame.commit(mesh, Mats.get_mat(frame_mat))
	glass.commit(mesh, Mats.get_mat("glass"))
	slab.commit(mesh, Mats.get_mat("door" if kind == "door" else "metal_wall"))
	_cache[key] = mesh
	return mesh
