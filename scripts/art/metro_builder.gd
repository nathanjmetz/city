class_name MetroBuilder
extends DenseBuilder
## The older, denser housing of big Midwestern cities, and the parking
## garages downtown (Brawn's metro plan). On prewar streets row homes and
## apartments are drawn as:
##   - Chicago two- and three-flats: one building per 25 ft lot with a
##     gangway between neighbours, a raised garden flat, a limestone
##     "greystone" or red brick front with a three-sided bay up its full
##     height, a stoop up to the entry and a cornice (Chicago Greystone
##     Initiative survey; Logan Square, Lawndale)
##   - courtyard buildings on wide lots: three storeys in a U around a
##     landscaped court open to the street, entries off the court
##     (Chicago's 1910s-20s courtyard apartments, Indianapolis's Old
##     Northside flats)
##   - walk-ups: four to six storeys of brick at the sidewalk with a
##     stone-trimmed stoop, a pressed-metal cornice on brackets and iron
##     fire escapes across the front (New York old-law and new-law
##     tenements, Cincinnati's Over-the-Rhine)
## Other eras fall back to DenseBuilder's own looks.

const MB_GREYSTONE := ["#bdb5a3", "#c4bcaa", "#b3ab98", "#a9a294"]
const MB_COMMON := Color("#8f5f45")  # the cheap common brick on sides and backs
const MB_IRON := Color("#1e1f20")
const MB_ROOF := Color("#55524d")  # tar and gravel


static func _mb_start(seed: int, lot: Dictionary) -> MetroBuilder:
	var b := MetroBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


static func build_apartments(seed: int, to_curb: float, lot: Dictionary, storeys: int) -> Array:
	var b := _mb_start(seed, lot)
	var width := b.half * 2.0
	if b.era != "prewar":
		b._apartments(to_curb, width, storeys)
	elif width >= 34.0 and storeys <= 3 and b.depth >= 34.0:
		b._mb_courtyard(to_curb, width, 3)
	else:
		b._mb_walkup(to_curb, width, maxi(storeys + 1, 3))
	return b._done()


static func build_row(seed: int, to_curb: float, lot: Dictionary, units: int, storeys: int) -> Array:
	var b := _mb_start(seed, lot)
	if b.era == "prewar" and b.rng.randf() < 0.65:
		b._mb_flats(to_curb, b.half * 2.0, units, storeys)
	else:
		b._row(to_curb, b.half * 2.0, units, storeys)
	return b._done()


## A precast concrete parking garage of `levels` decks (for downtown lots).
static func build_garage(seed: int, to_curb: float, lot: Dictionary, levels: int, spec := {}) -> Array:
	var b := _mb_start(seed, lot)
	b.sign_spec = spec
	b._mb_garage(to_curb, b.half * 2.0, levels)
	return b._done()


# ---------------------------------------------------------------- two- and three-flats

func _mb_flats(to_curb: float, width: float, units: int, storeys: int) -> void:
	var uw := (width - 1.0) / units
	var zf := rng.randf_range(4.5, 6.0)
	var floor_h := 3.2
	var base := 1.1  # the garden flat is half sunk, so the first floor is up a stoop
	var grey := rng.randf() < 0.6
	for i in units:
		var cx := -width * 0.5 + 0.5 + (i + 0.5) * uw
		var bw := uw - 1.0  # a 3 ft gangway down the side
		var d := rng.randf_range(16.0, 19.0)
		var n := storeys if rng.randf() < 0.7 else clampi(storeys + (1 if storeys == 2 else -1), 2, 3)
		var top := base + floor_h * n
		var front := Color(_pick(MB_GREYSTONE)) if grey else Color(_pick(FACADE_BRICK))
		var trim := Color(_pick(["#d9d3c3", "#efede6", "#2e2a26"]))
		_box("brick", Vector3(bw, top, d), Vector3(cx, top * 0.5, zf + d * 0.5), MB_COMMON)
		_mb_roof(cx, bw, zf + d * 0.5, d, top)
		_box("brick", Vector3(bw + 0.1, top + 0.6, 0.3), Vector3(cx, (top + 0.6) * 0.5, zf - 0.13), front)  # the front, up to the parapet
		_box("paint", Vector3(bw + 0.5, 0.45, 0.7), Vector3(cx, top + 0.35, zf - 0.4), front.lightened(0.08))  # cornice
		var bay_side := -1.0 if rng.randf() < 0.5 else 1.0
		var bx := cx + bay_side * (bw * 0.5 - 1.75)
		var dx := cx - bay_side * (bw * 0.5 - 1.25)
		_mb_bay(bx, zf - 0.28, 3.0, 1.0, top - 0.2, base, floor_h, n, front, trim)
		# The entry up the stoop, with a window over it on each floor.
		_stoop(dx, zf - 0.28, 1.6, 1.3, base)
		_front_door(dx, zf - 0.28, base, Color(_pick(DOOR)))
		_box("paint", Vector3(1.6, 0.3, 0.3), Vector3(dx, base + 2.45, zf - 0.4), front.lightened(0.1))  # stone hood
		for f in range(1, n):
			_window(Vector3(dx, base + f * floor_h + 1.5, zf - 0.28), Vector3(-1, 0, 0), 1.0, 1.7, false, false, trim)
		# Garden flat windows just above the ground.
		_window(Vector3(dx + bay_side * 0.2, 0.55, zf - 0.28), Vector3(-1, 0, 0), 0.9, 0.7, false, false, trim)
		# Side windows down the gangway, a few per floor.
		for f in n:
			for k in 3:
				var z := zf + 3.0 + k * (d - 5.0) / 2.0
				for s in [-1.0, 1.0]:
					_window(Vector3(cx + s * bw * 0.5, base + f * floor_h + 1.5, z), Vector3(0, 0, -s), 0.9, 1.5, false, false, trim)
		_rear_wall(cx - bw * 0.5, cx + bw * 0.5, zf + d, base, floor_h, n, trim)
		_flat_rect("drive", dx - 0.6, dx + 0.6, -0.3, zf - 1.6 - 1.4, 0.06)
		_flat_rect("drive", cx + bay_side * (bw * 0.5 + 0.1), cx + bay_side * (bw * 0.5 + 0.9), zf, zf + d, 0.06)  # the gangway walk
		# A low iron fence along the front yard.
		_box("metal", Vector3(uw - 1.6, 0.05, 0.05), Vector3(cx, 0.9, -0.2), MB_IRON)
		_box("metal", Vector3(uw - 1.6, 0.05, 0.05), Vector3(cx, 0.15, -0.2), MB_IRON)
		if rng.randf() < 0.5:
			_shrub(Vector3(bx, 0.0, zf - 1.9), rng.randf_range(0.45, 0.65))
	if rng.randf() < 0.7:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(rng.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.2), pick[0], pick[1],
			rng.randf_range(0.7, 1.0)])


## A three-sided bay up the front: a face `fw` wide at the back narrowing
## to the front face `depth_out` out from the wall, with a window on each
## face of every floor and a cap on top.
func _mb_bay(bx: float, zw: float, fw: float, depth_out: float, h: float, base: float, floor_h: float, n: int,
		col: Color, trim: Color) -> void:
	var front_w := fw - depth_out * 1.2
	var pts := [Vector2(bx - fw * 0.5, zw), Vector2(bx - front_w * 0.5, zw - depth_out),
		Vector2(bx + front_w * 0.5, zw - depth_out), Vector2(bx + fw * 0.5, zw)]
	for k in 3:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var e := (b - a)
		var nrm := Vector3(e.y, 0, -e.x).normalized()  # out of the bay
		_quad("brick", Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), col,
			[Vector2(0, 0), Vector2(e.length(), 0), Vector2(e.length(), h), Vector2(0, h)], nrm)
		var mid := (a + b) * 0.5
		var right := Vector3(nrm.z, 0, -nrm.x)
		var ww := minf(e.length() - 0.4, 1.2)
		for f in n:
			_window(Vector3(mid.x, base + f * floor_h + 1.5, mid.y), right, ww, 1.7, false, false, trim)
		_window(Vector3(mid.x, 0.55, mid.y), right, ww * 0.8, 0.7, false, false, trim)
	_quad("paint", Vector3(pts[0].x, h, pts[0].y), Vector3(pts[1].x, h, pts[1].y), Vector3(pts[2].x, h, pts[2].y),
		Vector3(pts[3].x, h, pts[3].y), col.lightened(0.1), [], Vector3.UP)


# ---------------------------------------------------------------- courtyard buildings

func _mb_courtyard(to_curb: float, width: float, storeys: int) -> void:
	var W := minf(width - 2.0, 46.0)
	var D := minf(depth - 8.0, rng.randf_range(34.0, 42.0))
	var ww := rng.randf_range(10.0, 12.0)  # wing depth: flats either side of a stair
	var zf := rng.randf_range(3.0, 4.5)
	var floor_h := 3.2
	var base := 0.9
	var top := base + floor_h * storeys
	var wall := Color(_pick(FACADE_BRICK + ["#c9b48a", "#b89b72"]))
	var stone := Color(_pick(MB_GREYSTONE))
	var trim := Color(_pick(["#d9d3c3", "#efede6"]))
	var court_z := zf + D - ww  # where the back bar starts
	var parts := [
		[Vector3(ww, top, D), Vector3(-W * 0.5 + ww * 0.5, top * 0.5, zf + D * 0.5)],
		[Vector3(ww, top, D), Vector3(W * 0.5 - ww * 0.5, top * 0.5, zf + D * 0.5)],
		[Vector3(W - ww * 2.0, top, ww), Vector3(0, top * 0.5, court_z + ww * 0.5)],
	]
	for p in parts:
		_box("brick", p[0], p[1], wall)
		_box("paint", Vector3(p[0].x + 0.3, 0.35, p[0].z + 0.3), Vector3(p[1].x, top + 0.2, p[1].z), MB_ROOF)  # tar and gravel
		_box("paint", Vector3(p[0].x + 0.4, 0.3, 0.5), Vector3(p[1].x, top + 0.3, p[1].z - p[0].z * 0.5), stone)  # stone coping on the street end
		_box("paint", Vector3(p[0].x + 0.1, 0.25, p[0].z + 0.1), Vector3(p[1].x, base + floor_h - 0.1, p[1].z), stone)  # belt course
	# Windows on every face that looks out: the street ends of the wings,
	# the court, and the outer sides.
	var faces := [
		[Vector3(-W * 0.5 + ww * 0.5, 0, zf), Vector3(-1, 0, 0), ww],
		[Vector3(W * 0.5 - ww * 0.5, 0, zf), Vector3(-1, 0, 0), ww],
		[Vector3(-W * 0.5 + ww, 0, (zf + court_z) * 0.5), Vector3(0, 0, -1), court_z - zf],
		[Vector3(W * 0.5 - ww, 0, (zf + court_z) * 0.5), Vector3(0, 0, 1), court_z - zf],
		[Vector3(0, 0, court_z), Vector3(-1, 0, 0), W - ww * 2.0],
		[Vector3(-W * 0.5, 0, zf + D * 0.5), Vector3(0, 0, 1), D],
		[Vector3(W * 0.5, 0, zf + D * 0.5), Vector3(0, 0, -1), D],
	]
	for fc in faces:
		var nwin := maxi(2, int(fc[2] / 3.0))
		for f in storeys:
			for i in nwin:
				var c: Vector3 = fc[0] + fc[1] * (-fc[2] * 0.5 + (i + 0.5) * fc[2] / nwin)
				c.y = base + f * floor_h + 1.5
				_window(c, fc[1], 1.1, 1.6, false, false, trim)
	# Entries off the court, each under a stone surround with a stoop.
	var court_w := W - ww * 2.0
	for e in [[Vector3(-court_w * 0.5, 0, zf + (court_z - zf) * 0.5), Vector3(0, 0, -1)],
			[Vector3(court_w * 0.5, 0, zf + (court_z - zf) * 0.5), Vector3(0, 0, 1)],
			[Vector3(0, 0, court_z), Vector3(-1, 0, 0)]]:
		var at: Vector3 = e[0]
		var r: Vector3 = e[1]
		var out := r.cross(Vector3.UP)
		# The side entries are at grade, a step down to the stair hall; the
		# back one is up the stoop.
		var sill := base if r.z == 0.0 else 0.1
		_box("paint", Vector3(2.4, 3.2, 0.3), at + Vector3(0, sill + 1.6, 0) + out * 0.15, stone, Basis(Vector3.UP, atan2(-r.z, -r.x)))
		_glass(at + Vector3(0, sill + 1.2, 0) + out * 0.32, r, 1.4, 2.3, 0.0)
	_stoop(0.0, court_z, 3.0, 1.4, base)
	# The court: a centre walk to the back entry, lawn and shrubs, and an
	# iron fence and gate across its open end.
	_flat_rect("drive", -1.0, 1.0, -0.3, court_z - 1.4 - 1.5, 0.06)
	for s in [-1.0, 1.0]:
		var x: float = s * (court_w * 0.5 - 1.0)
		var z := zf + 1.0
		while z < court_z - 1.0:
			_shrub(Vector3(x, 0.0, z), rng.randf_range(0.4, 0.6))
			z += rng.randf_range(1.6, 2.4)
		_box("metal", Vector3(court_w * 0.5 - 1.4, 0.05, 0.05), Vector3(s * (court_w * 0.25 + 0.7), 1.1, zf + 0.3), MB_IRON)
		_box("metal", Vector3(court_w * 0.5 - 1.4, 0.05, 0.05), Vector3(s * (court_w * 0.25 + 0.7), 0.15, zf + 0.3), MB_IRON)
	if rng.randf() < 0.6:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(rng.randf_range(-court_w * 0.2, court_w * 0.2), 0, zf + (court_z - zf) * 0.55), pick[0], pick[1], rng.randf_range(0.7, 0.9)])
	var pick2 := TreeField.pick(rng)
	trees.append([Vector3(-width * 0.3, 0, -to_curb + 1.2), pick2[0], pick2[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- walk-ups

func _mb_walkup(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 1.0, rng.randf_range(16.0, 26.0))
	var d := minf(depth - 6.0, rng.randf_range(18.0, 24.0))
	var zf := rng.randf_range(1.8, 3.0)
	var cz := zf + d * 0.5
	var floor_h := 3.1
	var base := 0.9
	var top := base + floor_h * storeys
	var wall := Color(_pick(FACADE_BRICK + ["#c9b48a", "#6e3b2e"]))
	var stone := Color(_pick(MB_GREYSTONE))
	var trim := Color(_pick(["#d9d3c3", "#efede6", "#2e2a26"]))
	_downtown_walk(to_curb, width, zf)
	_box("brick", Vector3(w, top, d), Vector3(0, top * 0.5, cz), wall)
	_mb_roof(0.0, w, cz, d, top)
	_box("brick", Vector3(w + 0.1, base, 0.12), Vector3(0, base * 0.5, zf - 0.04), stone)  # stone water table
	# A pressed-metal cornice on brackets.
	_box("paint", Vector3(w + 0.4, 0.7, 0.9), Vector3(0, top - 0.1, zf - 0.45), trim)
	var nb := maxi(4, int(w / 1.6))
	for i in nb + 1:
		_box("paint", Vector3(0.2, 0.6, 0.6), Vector3(-w * 0.5 + i * w / nb, top - 0.75, zf - 0.3), trim.darkened(0.1))
	# Windows: an even grid, the entry bay in the middle.
	var cols := maxi(4, int(w / 2.4))
	if cols % 2 == 0:
		cols += 1
	var cw := w / cols
	for f in storeys:
		var y := base + f * floor_h + 1.5
		for i in cols:
			var x := -w * 0.5 + (i + 0.5) * cw
			if f == 0 and i == cols / 2:
				continue
			_window(Vector3(x, y, zf), Vector3(-1, 0, 0), 1.0, 1.6, false, false, trim)
			_box("paint", Vector3(1.3, 0.22, 0.12), Vector3(x, y + 0.95, zf - 0.06), stone)  # stone lintel
		# Side walls: a window in every bay down the depth (the flats run
		# front to back, each room with its own window).
		var nside := maxi(3, int((d - 2.0) / 3.4))
		for s in [-1.0, 1.0]:
			for k in nside:
				_window(Vector3(s * w * 0.5, y, zf + 1.0 + (k + 0.5) * (d - 2.0) / nside), Vector3(0, 0, -s), 0.9, 1.5, false, false, trim)
	# The entry: a stone surround up a stoop.
	_box("paint", Vector3(2.0, 3.0, 0.2), Vector3(0, base + 1.5, zf - 0.1), stone)
	_front_door(0.0, zf - 0.2, base, Color(_pick(DOOR)))
	_stoop(0.0, zf - 0.2, 1.8, 1.2, base)
	# Iron fire escapes on the front: a balcony at each floor over two
	# windows, with drop ladders between them.
	var runs := [[-w * 0.5 + cw, cw * 2.0]] if cols < 7 else [[-w * 0.5 + cw, cw * 2.0], [w * 0.5 - cw, cw * 2.0]]
	for r in runs:
		for f in range(1, storeys):
			var y := base + f * floor_h + 0.05
			_box("metal", Vector3(r[1], 0.06, 1.1), Vector3(r[0], y, zf - 0.6), MB_IRON)
			_box("metal", Vector3(r[1], 0.05, 0.05), Vector3(r[0], y + 0.95, zf - 1.12), MB_IRON)
			_box("metal", Vector3(r[1], 0.05, 0.05), Vector3(r[0], y + 0.5, zf - 1.12), MB_IRON)
			if f < storeys - 1:
				var tilt := Basis(Vector3.FORWARD, 0.95)
				_box("metal", Vector3(floor_h * 1.25, 0.05, 0.45), Vector3(r[0] + (0.3 if f % 2 == 0 else -0.3), y + floor_h * 0.5, zf - 0.85), MB_IRON, tilt if f % 2 == 0 else tilt.inverse())
	_rear_wall(-w * 0.5, w * 0.5, zf + d, base, floor_h, storeys, trim)
	_box("metal", Vector3(2.0, 1.0, 1.2), Vector3(rng.randf_range(-w * 0.3, w * 0.3), top + 0.5, cz + d * 0.2), Color("#b9bcbc"))


## A flat tar-and-gravel roof just above a block's top.
func _mb_roof(cx: float, w: float, cz: float, d: float, y: float) -> void:
	_quad("paint", Vector3(cx - w * 0.5, y + 0.03, cz - d * 0.5), Vector3(cx + w * 0.5, y + 0.03, cz - d * 0.5),
		Vector3(cx + w * 0.5, y + 0.03, cz + d * 0.5), Vector3(cx - w * 0.5, y + 0.03, cz + d * 0.5), MB_ROOF, [], Vector3.UP)


# ---------------------------------------------------------------- parking garages

func _mb_garage(to_curb: float, width: float, levels: int) -> void:
	var w := minf(width - 1.0, 40.0)
	var d := minf(depth - 4.0, rng.randf_range(36.0, 55.0))
	var zf := 1.5
	var cz := zf + d * 0.5
	var lh := 3.2  # floor to floor
	var concrete := Color(_pick(["#bdb9b0", "#c9c5bb", "#aeaaa1"]))
	var h := lh * levels
	_downtown_walk(to_curb, width, zf)
	# The shadowed decks seen through the open sides.
	_box("paint", Vector3(w - 0.8, h, d - 0.8), Vector3(0, h * 0.5, cz), Color("#2c2d2e"))
	for k in levels + 1:
		var y := k * lh
		# Deck edge and a 1.1 m precast spandrel (the car barrier) round it.
		if k > 0:
			_box("concrete", Vector3(w, 1.1, 0.3), Vector3(0, y + 0.55 - 0.3, zf + 0.15), concrete)
			_box("concrete", Vector3(w, 1.1, 0.3), Vector3(0, y + 0.55 - 0.3, zf + d - 0.15), concrete)
			_box("concrete", Vector3(0.3, 1.1, d), Vector3(-w * 0.5 + 0.15, y + 0.55 - 0.3, cz), concrete)
			_box("concrete", Vector3(0.3, 1.1, d), Vector3(w * 0.5 - 0.15, y + 0.55 - 0.3, cz), concrete)
	# Columns on an 18 m long-span grid.
	var nx := maxi(2, roundi(w / 18.0))
	for i in nx + 1:
		for zz in [zf + 0.3, zf + d - 0.3]:
			_box("concrete", Vector3(0.6, h, 0.6), Vector3(-w * 0.5 + 0.3 + i * (w - 0.6) / nx, h * 0.5, zz), concrete.darkened(0.05))
	# The roof deck with light poles, and a glass stair tower at a corner.
	_quad("paint", Vector3(-w * 0.5, h + 0.31, zf), Vector3(w * 0.5, h + 0.31, zf), Vector3(w * 0.5, h + 0.31, zf + d),
		Vector3(-w * 0.5, h + 0.31, zf + d), Color("#8d8a84"), [], Vector3.UP)
	for i in 3:
		var at := Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.3, zf + d * (0.25 + i * 0.25))
		_box("metal", Vector3(0.18, 7.0, 0.18), at + Vector3(0, 3.5, 0), Color("#5f6266"))
		_box("metal", Vector3(1.2, 0.25, 0.5), at + Vector3(0, 7.0, 0), Color("#5f6266"))
	var sx := -w * 0.5 - 2.2
	_box("concrete", Vector3(4.4, h + 3.0, 5.0), Vector3(sx + 0.0, (h + 3.0) * 0.5, zf + 2.5), concrete)
	_glass(Vector3(sx, (h + 3.0) * 0.5, zf - 0.03), Vector3(-1, 0, 0), 3.0, h + 2.0, 0.0)
	# The entrance lane with its gate arm and the sign.
	_flat_rect("asphalt", w * 0.5 - 8.0, w * 0.5 - 1.5, -to_curb + RoadStyle.CURB_WIDTH, zf + 1.0, 0.07)
	_box("paint", Vector3(0.5, 1.1, 0.5), Vector3(w * 0.5 - 2.2, 0.55, zf - 0.6), Color("#d2a22a"))
	_box("paint", Vector3(3.6, 0.08, 0.08), Vector3(w * 0.5 - 4.0, 1.05, zf - 0.6), Color("#efe9d8"))
	_sign(Vector3(w * 0.5 - 4.75, lh + 0.4, zf - 0.1), 5.0, 1.0)
