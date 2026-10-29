class_name SiteMachines
extends RefCounted
## The off-road machines a job site keeps on the lot between their trips
## on a trailer: a compact excavator digging the footings, a skid steer
## moving dirt and stone, a telehandler setting lumber up on the walls and
## an articulating boom lift for the trades on a bigger building. Drawn
## into the site's prop SurfaceTool from boxes and round tyres at their
## real sizes (Bobcat E50 / CAT 305 class mini excavator, a 70 hp vertical
## lift skid steer, a 10,000 lb 55 ft telehandler, a 60 ft articulating
## boom), facing +z at `t`, so a site turns them where it parks them.
##
## Painted in the colours the US rental and dealer fleets wear (dealer
## yellow, rental white with orange, telehandler orange), plain, no names.

## Rental-fleet paint for a machine picked by `k`.
static func paint(k: int) -> Color:
	return [Color("#e0a81a"), Color("#e6e4dc"), Color("#d9661f"), Color("#e0a81a")][k % 4]


## A compact excavator (about 5 t): two rubber tracks and the dozer blade,
## the upper house turned `swing` radians with its counterweight and cab,
## and the boom, stick and bucket reaching down into the trench ahead.
static func excavator(st: SurfaceTool, t: Transform3D, col: Color, swing: float, fine: bool) -> void:
	var dark := Color("#262626")
	for sx in [-1.0, 1.0]:
		_m(st, t, Vector3(0.4, 0.5, 2.5), Vector3(sx * 0.8, 0.25, 0), dark)
		if fine:
			for z in [-1.05, 1.05]:
				_wheel(st, t, Vector3(sx * 0.8, 0.25, z), 0.25, 0.42, dark.lightened(0.05), 10)
			_m(st, t, Vector3(0.06, 0.18, 1.7), Vector3(sx * 1.01, 0.3, 0), col.darkened(0.2))
	_m(st, t, Vector3(1.4, 0.25, 1.6), Vector3(0, 0.55, 0), dark)
	# The dozer blade on its arms.
	_m(st, t, Vector3(1.96, 0.42, 0.12), Vector3(0, 0.3, 1.5), col)
	_m(st, t, Vector3(1.2, 0.1, 0.4), Vector3(0, 0.45, 1.3), col.darkened(0.15))
	# The upper house, swung.
	var up := t * Transform3D(Basis(Vector3.UP, swing), Vector3(0, 0.7, 0))
	_m(st, up, Vector3(1.9, 0.75, 1.9), Vector3(0, 0.38, -0.15), col)
	_m(st, up, Vector3(1.9, 0.6, 0.45), Vector3(0, 0.45, -1.15), col.darkened(0.1))  # counterweight
	_m(st, up, Vector3(0.95, 1.45, 1.25), Vector3(-0.42, 1.48, 0.1), dark)  # cab frame
	for g in [[Vector3(0.9, 1.1, 0.02), Vector3(-0.42, 1.5, 0.73)], [Vector3(0.02, 1.0, 1.0), Vector3(-0.9, 1.5, 0.1)],
			[Vector3(0.02, 1.0, 1.0), Vector3(0.06, 1.5, 0.1)]]:
		_m(st, up, g[0], g[1], Color("#2b3a44"))
	_m(st, up, Vector3(1.0, 0.06, 1.3), Vector3(-0.42, 2.22, 0.1), col)
	if fine:
		_m(st, up, Vector3(0.08, 0.5, 0.08), Vector3(0.6, 1.0, -0.8), dark)  # exhaust
	# Boom up and out, the stick down, the bucket in the dirt.
	var pivot := Vector3(0.25, 0.7, 0.9)
	var elbow := Vector3(0.25, 2.7, 2.6)
	var tip := Vector3(0.25, 0.5, 3.6)
	_strut(st, up, pivot, elbow, Vector2(0.28, 0.4), col)
	_strut(st, up, elbow, tip, Vector2(0.22, 0.32), col)
	if fine:
		_strut(st, up, pivot + Vector3(0, 0.45, 0.1), elbow + Vector3(0, 0.25, -0.35), Vector2(0.1, 0.1), Color("#b8b8b4"))
	_m(st, up, Vector3(0.6, 0.45, 0.55), tip + Vector3(0, -0.12, -0.18), dark, Basis(Vector3.RIGHT, 0.5))


## A skid steer with a dirt bucket: four tyres, the body, the cab cage on
## top, the lift arms down each side from the back to the bucket.
static func skid_steer(st: SurfaceTool, t: Transform3D, col: Color, fine: bool) -> void:
	var dark := Color("#232323")
	var segs := 14 if fine else 8
	for sx in [-1.0, 1.0]:
		for z in [-0.55, 0.55]:
			_wheel(st, t, Vector3(sx * 0.78, 0.4, z), 0.4, 0.3, dark, segs)
			if fine:
				_wheel(st, t, Vector3(sx * 0.8, 0.4, z), 0.2, 0.32, Color("#8a8a86"), segs)
	_m(st, t, Vector3(1.24, 0.6, 2.2), Vector3(0, 0.62, -0.05), col)
	_m(st, t, Vector3(1.0, 1.05, 1.15), Vector3(0, 1.45, 0.1), dark)  # cab cage
	_m(st, t, Vector3(0.9, 0.9, 0.02), Vector3(0, 1.45, 0.68), Color("#2b3a44"))
	_m(st, t, Vector3(1.24, 0.5, 0.8), Vector3(0, 1.15, -0.75), col)  # engine cover
	for sx in [-1.0, 1.0]:
		_strut(st, t, Vector3(sx * 0.68, 1.8, -0.95), Vector3(sx * 0.68, 1.1, 0.9), Vector2(0.14, 0.24), col)
		_strut(st, t, Vector3(sx * 0.68, 1.1, 0.9), Vector3(sx * 0.68, 0.55, 1.35), Vector2(0.14, 0.22), col)
	_m(st, t, Vector3(1.85, 0.55, 0.7), Vector3(0, 0.33, 1.6), dark.lightened(0.12))
	if fine:
		_m(st, t, Vector3(1.85, 0.05, 0.12), Vector3(0, 0.08, 1.98), Color("#8a8a86"))  # cutting edge
		_m(st, t, Vector3(0.9, 0.06, 0.06), Vector3(0, 2.0, 0.1), Color("#e8a020"))  # beacon bar


## A telehandler parked with its boom down and forks on the ground: four
## big tyres, the long low frame, the cab on the left, the boom from the
## back along the right to the fork carriage out front.
static func telehandler(st: SurfaceTool, t: Transform3D, col: Color, fine: bool) -> void:
	var dark := Color("#232323")
	var segs := 16 if fine else 8
	for sx in [-1.0, 1.0]:
		for z in [-1.4, 1.4]:
			_wheel(st, t, Vector3(sx * 1.0, 0.62, z), 0.62, 0.5, dark, segs)
			if fine:
				_wheel(st, t, Vector3(sx * 1.02, 0.62, z), 0.3, 0.5, col.darkened(0.1), segs)
	_m(st, t, Vector3(1.3, 0.55, 4.2), Vector3(0, 0.85, 0), col)
	_m(st, t, Vector3(0.95, 1.65, 1.6), Vector3(-0.7, 1.95, 0.0), dark)  # cab
	_m(st, t, Vector3(0.02, 1.2, 1.4), Vector3(-1.18, 2.0, 0.0), Color("#2b3a44"))
	_m(st, t, Vector3(0.85, 1.2, 0.02), Vector3(-0.7, 2.0, 0.81), Color("#2b3a44"))
	_m(st, t, Vector3(1.0, 0.05, 1.7), Vector3(-0.7, 2.8, 0.0), col)
	_m(st, t, Vector3(0.9, 0.9, 1.4), Vector3(0.65, 1.55, -1.5), col)  # engine bay
	# The boom, three nested sections, lowered toward the front.
	_strut(st, t, Vector3(0.35, 2.15, -2.0), Vector3(0.35, 1.3, 2.4), Vector2(0.5, 0.55), col)
	_strut(st, t, Vector3(0.35, 1.3, 2.4), Vector3(0.35, 0.95, 3.4), Vector2(0.38, 0.42), col.darkened(0.08))
	_m(st, t, Vector3(1.4, 0.75, 0.15), Vector3(0.0, 0.6, 3.55), dark)  # carriage
	for sx in [-0.4, 0.4]:
		_m(st, t, Vector3(0.14, 0.06, 1.3), Vector3(sx, 0.1, 4.25), dark)
	if fine:
		_m(st, t, Vector3(0.12, 0.12, 0.6), Vector3(0.35, 1.75, 0.6), Color("#b8b8b4"))  # lift ram
		_m(st, t, Vector3(0.2, 0.1, 0.2), Vector3(-0.7, 2.87, -0.4), Color("#e8a020"))  # beacon


## An articulating boom lift, stowed: four tyres, the low chassis and
## turntable with its counterweight, the folded riser and boom laid back,
## the jib and the railed platform out front at knee height.
static func boom_lift(st: SurfaceTool, t: Transform3D, col: Color, fine: bool) -> void:
	var dark := Color("#232323")
	var segs := 14 if fine else 8
	for sx in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_wheel(st, t, Vector3(sx * 1.0, 0.45, z), 0.45, 0.4, dark, segs)
	_m(st, t, Vector3(1.8, 0.5, 2.6), Vector3(0, 0.6, 0), col.darkened(0.15))
	_m(st, t, Vector3(1.9, 1.0, 1.8), Vector3(0, 1.35, -0.4), col)  # turntable + counterweight
	_strut(st, t, Vector3(0, 1.9, -1.1), Vector3(0, 2.3, 1.6), Vector2(0.35, 0.35), col)
	_strut(st, t, Vector3(0, 2.3, 1.6), Vector3(0, 1.4, 3.0), Vector2(0.25, 0.25), col)
	var p := Vector3(0, 1.2, 3.6)
	_m(st, t, Vector3(2.2, 0.12, 0.9), p, dark)
	var rail := Color("#d9d6cc") if col.v < 0.6 else col.darkened(0.3)
	for r in [[Vector3(2.2, 0.05, 0.05), Vector3(0, 1.1, 0.42)], [Vector3(2.2, 0.05, 0.05), Vector3(0, 1.1, -0.42)],
			[Vector3(0.05, 0.05, 0.9), Vector3(1.08, 1.1, 0)], [Vector3(0.05, 0.05, 0.9), Vector3(-1.08, 1.1, 0)]]:
		_m(st, t, r[0], p + r[1] - Vector3(0, 0.0, 0), rail)
	if fine:
		for c in [Vector3(1.08, 0.55, 0.42), Vector3(-1.08, 0.55, 0.42), Vector3(1.08, 0.55, -0.42), Vector3(-1.08, 0.55, -0.42)]:
			_m(st, t, Vector3(0.05, 1.1, 0.05), p + c, rail)
		_m(st, t, Vector3(0.5, 0.4, 0.15), p + Vector3(0.5, 0.75, -0.4), dark)  # control box


## A lattice-boom crawler crane (a 200 t class, like those that stand
## tilt-up warehouse panels in Indiana) working from the slab: two crawler
## tracks, the carbody and upper house with its stacked counterweight and
## cab, a 45 m lattice boom up at 65 degrees with its pendants back to the
## gantry, and the hook block and spreader hanging from the tip.
static func crawler_crane(st: SurfaceTool, t: Transform3D, col: Color, fine: bool) -> void:
	var dark := Color("#262626")
	for sx in [-1.0, 1.0]:
		_m(st, t, Vector3(1.2, 1.3, 8.6), Vector3(sx * 2.9, 0.65, 0), dark)
		if fine:
			for z in [-3.9, 3.9]:
				_wheel(st, t, Vector3(sx * 2.9, 0.65, z), 0.65, 1.16, dark.lightened(0.04), 12)
	_m(st, t, Vector3(4.6, 1.0, 4.0), Vector3(0, 1.6, 0), dark.lightened(0.08))
	var up := t * Transform3D(Basis.IDENTITY, Vector3(0, 2.1, 0))
	_m(st, up, Vector3(4.8, 2.6, 7.0), Vector3(0, 1.3, -1.2), col)
	_m(st, up, Vector3(4.8, 2.4, 1.8), Vector3(0, 1.0, -5.4), Color("#4a4a48"))  # counterweight
	_m(st, up, Vector3(1.3, 2.2, 2.0), Vector3(-2.9, 1.3, 1.6), col.darkened(0.08))  # cab
	_m(st, up, Vector3(0.04, 1.4, 1.6), Vector3(-3.56, 1.5, 1.6), Color("#2b3a44"))
	_m(st, up, Vector3(1.2, 1.4, 0.04), Vector3(-2.9, 1.5, 2.62), Color("#2b3a44"))
	# The boom: four chords of a 1.8 m box lattice.
	var a := deg_to_rad(65.0)
	var dir := Vector3(0, sin(a), cos(a))
	var foot := Vector3(0, 1.6, 2.0)
	var len := 45.0
	var tip := foot + dir * len
	var side := Vector3.RIGHT
	var nrm := side.cross(dir).normalized()  # across the boom's depth
	for sx in [-0.9, 0.9]:
		for sy in [-0.9, 0.9]:
			var o: Vector3 = side * sx + nrm * sy
			_strut(st, up, foot + o * 0.3, tip + o * 0.45, Vector2(0.14, 0.14), col if col.v > 0.5 else Color("#e8e6e0"))
	if fine:
		var d := 2.5
		while d < len - 1.0:
			var p := foot + dir * d
			var w := lerpf(0.3, 0.45, d / len) * 2.0
			_m(st, up, Vector3(w * 0.9, 0.08, 0.08), p + nrm * w * 0.45, col, Basis(Vector3.RIGHT, -a + PI * 0.5))
			_m(st, up, Vector3(w * 0.9, 0.08, 0.08), p - nrm * w * 0.45, col, Basis(Vector3.RIGHT, -a + PI * 0.5))
			_strut(st, up, p + side * w * 0.45, p - side * w * 0.45 + dir * 2.4, Vector2(0.06, 0.06), col)
			d += 2.5
	# The gantry and the pendants holding the boom.
	var gantry := Vector3(0, 6.5, -3.0)
	_strut(st, up, Vector3(0, 2.6, -2.0), gantry, Vector2(0.4, 0.4), col)
	for sx in [-0.4, 0.4]:
		_strut(st, up, gantry + side * sx, tip + side * sx * 0.5, Vector2(0.05, 0.05), Color("#2a2a2a"))
	_m(st, up, Vector3(1.4, 1.2, 1.4), tip + Vector3(0, 0.2, 0.4), col.darkened(0.15))  # sheaves
	# Hoist line, hook block and the spreader for a panel.
	var drop := tip.y - 14.0
	_m(st, up, Vector3(0.05, drop, 0.05), tip + Vector3(0, -drop * 0.5, 0.6), Color("#1e1e1e"))
	_m(st, up, Vector3(0.7, 1.4, 0.5), tip + Vector3(0, -drop - 0.4, 0.6), Color("#e0a81a"))
	_m(st, up, Vector3(6.0, 0.35, 0.35), tip + Vector3(0, -drop - 3.2, 0.6), Color("#e0a81a"))
	for sx in [-2.8, 2.8]:
		_strut(st, up, tip + Vector3(0, -drop - 1.0, 0.6), tip + Vector3(sx, -drop - 3.0, 0.6), Vector2(0.04, 0.04), Color("#1e1e1e"))


## A box at `c` (machine space) turned by `b`, placed by `t`.
static func _m(st: SurfaceTool, t: Transform3D, size: Vector3, c: Vector3, col: Color, b := Basis.IDENTITY) -> void:
	ConstructionSite._prop(st, size, t * c, col, t.basis * b)


## A beam of section `sec` (width, depth) from `a` to `b`, machine space.
static func _strut(st: SurfaceTool, t: Transform3D, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var dir := d.normalized()
	var side := Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD
	var up := dir.cross(side).normalized()
	var x := up.cross(dir).normalized()
	_m(st, t, Vector3(sec.x, sec.y, d.length()), (a + b) * 0.5, col, Basis(x, up, dir))


## A tyre (or hub): a short round drum across x, `r` in radius.
static func _wheel(st: SurfaceTool, t: Transform3D, c: Vector3, r: float, w: float, col: Color, segs: int) -> void:
	st.set_color(col)
	var hw := w * 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		var n := t.basis * ((p0 + p1) * 0.5).normalized()
		var q := [t * (c + p0 + Vector3(-hw, 0, 0)), t * (c + p1 + Vector3(-hw, 0, 0)),
			t * (c + p1 + Vector3(hw, 0, 0)), t * (c + p0 + Vector3(hw, 0, 0))]
		st.set_normal(n)
		for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(v)
		for sx in [-1.0, 1.0]:
			st.set_normal(t.basis * Vector3(sx, 0, 0))
			var e0: Vector3 = t * (c + p0 + Vector3(sx * hw, 0, 0))
			var e1: Vector3 = t * (c + p1 + Vector3(sx * hw, 0, 0))
			var m: Vector3 = t * (c + Vector3(sx * hw, 0, 0))
			for v in ([m, e0, e1] if sx > 0.0 else [m, e1, e0]):
				st.add_vertex(v)
