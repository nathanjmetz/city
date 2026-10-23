class_name ParkingBuilder
extends CivicBuilder
## Public parking from the Roads menu, painted stall for stall from the
## layout Traffic parks cars in (ParkingLots), against photos of real
## small-town lots and garages:
##   - surface lots: asphalt with white 4 in stall lines, blue accessible
##     stalls with hatched access aisles and a sign at each, one-way arrows
##     on 60 degree aisles, a planted strip along the street, shoebox LED
##     lights on 30 ft poles
##   - the downtown lot: shade trees round the edge and a pay station by
##     the driveway, like a Main Street municipal lot
##   - park and ride: a bus shelter by the driveway and the state's sign
##   - the garage: precast concrete decks about 10 ft 6 in apart behind
##     spandrel panels, a glass stair tower and a lit PARKING entrance
## Local space as CivicBuilder: centred, -z faces the road.

const BLUE := Color("#2f5fb3")
const POLE_H := 9.0  # 30 ft light poles
const DECK := 3.2    # floor to floor in a parking garage


static func build_lot(b: Dictionary, seed: int, to_curb: float) -> Array:
	var pb := ParkingBuilder.new()
	pb.rng = RandomNumberGenerator.new()
	pb.rng.seed = seed
	pb._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := Services.size_of(b)
	var lay := Services.parking_layout(b)
	if int(b.kind) == Services.Kind.PARKING_GARAGE:
		pb._parking_garage(size, lay, to_curb)
	else:
		pb._surface(int(b.kind), size, lay, to_curb)
	return [pb._commit_house(), pb._commit_flat(), pb.trees]


func _surface(kind: int, size: Vector2, lay: Dictionary, to_curb: float) -> void:
	var hw := size.x * 0.5
	var front := -size.y * 0.5
	var back := size.y * 0.5
	var e := ParkingLots.EDGE
	_flat_rect("asphalt", -hw + e, hw - e, front + e, back - e, 0.06)
	# The driveway: 24 ft, two-way, across the walk to the street.
	_flat_rect("asphalt", -3.65, 3.65, front - to_curb, front + e, 0.1)
	_stripes(lay, 0.08)
	# Curbed, planted strip along the street either side of the driveway.
	for s in [-1.0, 1.0]:
		var x0 := 4.2 if s > 0 else -hw + 0.3
		var x1 := hw - 0.3 if s > 0 else -4.2
		_flat_rect("mulch", x0, x1, front + 0.2, front + e - 0.1, 0.05)
		for i in int((x1 - x0) / 1.4):
			_shrub(Vector3(x0 + 0.7 + i * 1.4, 0, front + 0.75), rng.randf_range(0.4, 0.55))
	# Shade trees round the edge: the downtown lot and the big lots.
	if kind != Services.Kind.PARKING_SMALL:
		var step := 11.0
		for side in [-1.0, 1.0]:
			var z := front + e + 6.0
			while z < back - 3.0:
				_tree(Vector3(side * (hw - 0.75), 0, z))
				z += step
		var x := -hw + 6.0
		while x < hw - 3.0:
			_tree(Vector3(x, 0, back - 0.75))
			x += step
	_lights(lay, size)
	match kind:
		Services.Kind.PARKING_DOWNTOWN:
			# The pay station by the driveway and the city's blue P sign.
			_box("paint", Vector3(0.5, 1.5, 0.4), Vector3(5.6, 0.75, front + 2.2), Color("#2d3238"))
			_box("paint", Vector3(0.42, 0.3, 0.05), Vector3(5.6, 1.2, front + 1.98), Color("#9fb7c9"))
			_post_sign(Vector3(-5.0, 0, front + 0.6), BLUE, 0.9)
		Services.Kind.PARK_AND_RIDE:
			_shelter(Vector3(9.0, 0, front + 2.6))
			_post_sign(Vector3(-5.0, 0, front + 0.6), Color("#1d6b3a"), 1.4)
		_:
			_post_sign(Vector3(-5.0, 0, front + 0.6), BLUE, 0.7)


## White stall lines, blue accessible stalls with hatched aisles, and
## arrows down one-way aisles.
func _stripes(lay: Dictionary, y: float) -> void:
	for s in lay.spots:
		if int(s.level) > 0:
			continue
		var f := Vector3(s.face.x, 0, s.face.y)
		var r := Vector3(-f.z, 0, f.x)
		var c := Vector3(s.pos.x, 0, s.pos.y)
		var col := BLUE if s.ada else LINE
		if s.ada:
			# The car's 8 ft and the striped access aisle beside it.
			var aw: float = float(s.w) - ParkingLots.ADA_W
			var ac := c + Vector3(s.aisle_off.x, 0, s.aisle_off.y)
			_line(ac - r * aw * 0.5, ac + r * aw * 0.5, f, col, y)
			var k := 0.0
			while k < ParkingLots.STALL_L - 0.6:
				var a := ac - f * (ParkingLots.STALL_L * 0.5 - k - 0.3)
				_bar(a - r * aw * 0.45, a + r * aw * 0.45 + f * 0.6, 0.1, col, y)
				k += 0.9
			_line(c - r * ParkingLots.ADA_W * 0.5, c + r * ParkingLots.ADA_W * 0.5, f, col, y)
			# The blue sign at the head of the stall.
			_post_sign(c + f * (ParkingLots.STALL_L * 0.5 + 0.4), BLUE, 0.45, true)
		else:
			_line(c - r * float(s.w) * 0.5, c + r * float(s.w) * 0.5, f, col, y)
	if lay.angled:
		for a in lay.aisles:
			var x: float = a[0]
			var dir: float = a[1]
			var z := float(lay.row0) + 4.0
			while z < float(lay.row1) - 4.0:
				var p := Vector3(x, 0, z)
				_bar(p - Vector3(0, 0, 1.2 * dir), p + Vector3(0, 0, 0.6 * dir), 0.18, LINE, y)
				_flat_quad([p + Vector3(-0.55, 0, 0.6 * dir), p + Vector3(0.55, 0, 0.6 * dir), p + Vector3(0, 0, 1.6 * dir),
					p + Vector3(0, 0, 1.6 * dir)], y, LINE)
				z += 18.0


## Two stall lines, one at each of `a` and `b`, the stall's length along `f`.
func _line(a: Vector3, b: Vector3, f: Vector3, col: Color, y: float) -> void:
	for p in [a, b]:
		_bar(p - f * ParkingLots.STALL_L * 0.5, p + f * ParkingLots.STALL_L * 0.5, 0.1, col, y)


## A painted bar from `a` to `b`, `w` wide.
func _bar(a: Vector3, b: Vector3, w: float, col: Color, y: float) -> void:
	var d := b - a
	d.y = 0.0
	if d.length() < 0.01:
		return
	var r := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	_flat_quad([a - r, a + r, b + r, b - r], y, col)


## A flat painted quad (lines, arrows) on the yard surface.
func _flat_quad(pts: Array, y: float, col: Color) -> void:
	col.a = 0.72  # painted line (see HouseBuilder._flat_rect)
	var p := pts.map(func(q): return Vector3(q.x, y, q.z))
	var tris := [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]
	for t in tris:
		if (t[1] - t[0]).cross(t[2] - t[0]).y > 0.0:
			t = [t[0], t[2], t[1]]
		for q in t:
			_flat.set_normal(Vector3.UP)
			_flat.set_color(col)
			_flat.set_uv(Vector2(q.x, q.z) * 0.25)
			_flat.add_vertex(q)


## Shoebox LED lights on 30 ft poles down the middle of the aisles, about
## every 100 ft, each with a concrete base against bumpers.
func _lights(lay: Dictionary, size: Vector2) -> void:
	var xs := []
	for a in lay.aisles:
		xs.append(a[0])
	if xs.is_empty():
		return
	var z := float(lay.row0) + 6.0
	var col := Color("#55595d")
	while z < float(lay.row1) - 3.0:
		for x in xs:
			var side: float = ParkingLots.AISLE_60 * 0.5 + 6.0 if lay.angled else ParkingLots.AISLE_90 * 0.5 + 5.6
			var p := Vector3(float(x) - side, 0, z)
			if absf(p.x) > size.x * 0.5 - 1.0:
				p.x = float(x) + side
			_cyl_y(p + Vector3(0, 0.4, 0), 0.3, 0.8, CONCRETE)
			_cyl_y(p + Vector3(0, POLE_H * 0.5, 0), 0.08, POLE_H, col)
			_box("paint", Vector3(0.7, 0.14, 0.5), p + Vector3(0, POLE_H, 0), col)
		z += 30.0


func _tree(p: Vector3) -> void:
	var pick := TreeField.pick(rng, true)
	trees.append([p, pick[0], pick[1], rng.randf_range(0.7, 0.95)])


## A sign on a post: the blue P, a state park-and-ride sign, or (small) the
## accessible stall's sign.
func _post_sign(p: Vector3, col: Color, w: float, small := false) -> void:
	var h := 2.1 if small else 2.6
	_box("paint", Vector3(0.07, h, 0.07), p + Vector3(0, h * 0.5, 0), Color("#8d9193"))
	_box("paint", Vector3(w, w * (1.3 if small else 1.0), 0.04), p + Vector3(0, h - w * 0.4, -0.05), col)
	if not small:
		_box("paint", Vector3(w * 0.5, w * 0.6, 0.02), p + Vector3(0, h - w * 0.4, -0.08), Color("#f2f0ea"))


## A three-sided bus shelter: glass walls and a flat roof.
func _shelter(p: Vector3) -> void:
	var w := 4.2
	var d := 1.6
	_box("paint", Vector3(w + 0.6, 0.15, d + 0.6), p + Vector3(0, 0.075, 0), CONCRETE)
	_box("paint", Vector3(w + 0.3, 0.12, d + 0.3), p + Vector3(0, 2.5, 0), Color("#3c4044"))
	_glass(p + Vector3(0, 1.3, d * 0.5), Vector3(1, 0, 0), w, 2.2, 0.0)
	for s in [-1.0, 1.0]:
		_glass(p + Vector3(s * w * 0.5, 1.3, 0), Vector3(0, 0, -s), d, 2.2, 0.0)
		_box("paint", Vector3(0.08, 2.5, 0.08), p + Vector3(s * w * 0.5, 1.25, -d * 0.5), Color("#3c4044"))
	_box("paint", Vector3(w * 0.7, 0.12, 0.4), p + Vector3(0, 0.45, d * 0.3), Color("#7a5a3a"))


## The precast garage: a deck at each level behind spandrel panels, columns
## at the bays, the ramp's slope showing at the side, a glass stair tower at
## the front corner and a lit entrance at the driveway.
func _parking_garage(size: Vector2, lay: Dictionary, to_curb: float) -> void:
	var w := size.x - 1.0
	var d := size.y - 1.0
	var front := -size.y * 0.5
	var levels: int = lay.levels
	var conc := Color("#c9c5bb")
	_flat_rect("asphalt", -3.65, 3.65, front - to_curb, front + 0.5, 0.1)
	_slab(0.0, w, front + 0.5, d)
	for lv in range(1, levels):
		var y := lv * DECK
		_box("concrete", Vector3(w, 0.35, d), Vector3(0, y, 0), conc)
	# Spandrels: the waist-high precast band round each deck (and the roof).
	for lv in levels:
		var band := 1.1
		var by := lv * DECK + 0.35 + band * 0.5
		var c := conc.darkened(0.04)
		if lv == 0:
			# The entrance: a gap in the ground floor's band at the driveway.
			for e in [-1.0, 1.0]:
				_box("concrete", Vector3(w * 0.5 - 4.0, band, 0.25), Vector3(e * (w * 0.25 + 2.0), by, -d * 0.5), c)
		else:
			_box("concrete", Vector3(w + 0.3, band, 0.25), Vector3(0, by, -d * 0.5), c)
		_box("concrete", Vector3(w + 0.3, band, 0.25), Vector3(0, by, d * 0.5), c)
		_box("concrete", Vector3(0.25, band, d), Vector3(-w * 0.5, by, 0), c)
		_box("concrete", Vector3(0.25, band, d), Vector3(w * 0.5, by, 0), c)
	# Columns on a 30 ft grid along the faces.
	var top := (levels - 1) * DECK
	var nx := maxi(int(w / 9.0), 1)
	var nz := maxi(int(d / 9.0), 1)
	for i in nx + 1:
		var x := -w * 0.5 + w * i / nx
		for z in [-d * 0.5, d * 0.5]:
			_box("concrete", Vector3(0.6, top, 0.6), Vector3(x, top * 0.5, z), conc)
	for i in range(1, nz):
		var z := -d * 0.5 + d * i / nz
		for x in [-w * 0.5, w * 0.5]:
			_box("concrete", Vector3(0.6, top, 0.6), Vector3(x, top * 0.5, z), conc)
	# A lit sign over the entrance.
	_box("paint", Vector3(7.6, 0.6, 0.12), Vector3(0, DECK - 0.5, -d * 0.5 - 0.2), Color("#1f3f7a"))
	_box("paint", Vector3(5.0, 0.35, 0.05), Vector3(0, DECK - 0.5, -d * 0.5 - 0.27), Color("#f2f0ea"))
	# The stair and elevator tower at the front corner, glass on the street.
	var tx := -w * 0.5 + 3.0
	var th := top + 4.0
	_box("concrete", Vector3(5.0, th, 5.0), Vector3(tx, th * 0.5, -d * 0.5 + 2.0), conc.darkened(0.08))
	_glass(Vector3(tx, th * 0.5, -d * 0.5 - 0.52), Vector3(-1, 0, 0), 3.8, th - 1.5, 0.0)
	# Light poles on the roof deck.
	for x in [-w * 0.25, w * 0.25]:
		for z in [-d * 0.25, d * 0.25]:
			_cyl_y(Vector3(x, top + 3.0, z), 0.08, 6.0, Color("#55595d"))
			_box("paint", Vector3(0.7, 0.14, 0.5), Vector3(x, top + 6.0, z), Color("#55595d"))
	for s in [-1.0, 1.0]:
		_flat_rect("mulch", s * 4.2 if s > 0 else -size.x * 0.5 + 0.3, size.x * 0.5 - 0.3 if s > 0 else -4.2,
			front + 0.1, front + 0.45, 0.05)
