class_name RailModels
extends RefCounted
## Locomotives and cars, built from real measurements (metres): a GP38-2
## road switcher, an SD70, a P42 for passenger trains, a 30,000-gallon tank
## car, an open ore hopper, a centerbeam-style log flat, a covered grain
## hopper and a bilevel coach. Each runs along -Z (its front), centred on
## its length, standing on the rail tops (y = 0). Colours are vertex colours.

## The railroad's own paint: dark green with a safety-yellow nose and stripe.
const PAINT := Color("#2f4a3a")
const YELLOW := Color("#e2b23a")
const TRUCK := Color("#26282a")
const GLASS := Color("#20292e")
const STEEL := Color("#8d9396")
const GAUGE := 1.435

## Liveries for the county's through freights (CountyTrains): a road
## railroad's black and white diesels, and the town line's own green.
const LIVERY := {"road": {"paint": Color("#1c1d1f"), "stripe": Color("#e8e6df")}}

var _st := SurfaceTool.new()
var _paint := PAINT
var _stripe := YELLOW


## A model by kind; "<kind>_road" builds it in the road railroad's livery.
static func build(kind: String) -> ArrayMesh:
	var b := RailModels.new()
	b._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := kind.split("_", true, 1)
	if parts.size() == 2 and LIVERY.has(parts[1]):
		kind = parts[0]
		b._paint = LIVERY[parts[1]].paint
		b._stripe = LIVERY[parts[1]].stripe
	if b.has_method("_" + kind):
		b.call("_" + kind)
	b._st.generate_normals()
	return b._st.commit()


# --- Locomotives ---------------------------------------------------------------

## A hood unit: frame, long hood, cab near the front with a short hood ahead.
func _hood_unit(L: float, hood_h: float, cab_from: float, trucks_at: float, axles: int) -> void:
	var h := L * 0.5
	_trucks(L, trucks_at, axles, 1.0)
	_box(Vector3(0, 1.25, 0), Vector3(3.1, 0.35, L), TRUCK)            # frame and walkways
	_box(Vector3(0, 1.0, 0), Vector3(1.6, 0.5, L * 0.35), TRUCK)       # fuel tank
	var cab_len := 3.4
	var cab_z := -h + cab_from + cab_len * 0.5
	# Short hood ahead of the cab, long hood behind it.
	_box(Vector3(0, 2.25, (-h + 0.6 + cab_z - cab_len * 0.5) * 0.5), Vector3(2.4, 1.65, cab_z - cab_len * 0.5 + h - 0.6), _paint)
	_box(Vector3(0, 1.42 + hood_h * 0.5, (cab_z + cab_len * 0.5 + h - 0.4) * 0.5),
		Vector3(2.5, hood_h, h - 0.4 - cab_z - cab_len * 0.5), _paint)
	_box(Vector3(0, 2.9, cab_z), Vector3(3.0, 2.95, cab_len), _paint)                    # cab
	_box(Vector3(0, 4.45, cab_z), Vector3(3.1, 0.15, cab_len + 0.2), _paint)             # cab roof
	_box(Vector3(0, 3.6, cab_z - cab_len * 0.5 - 0.01), Vector3(2.6, 0.9, 0.04), GLASS)  # windshield
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 1.51, 3.55, cab_z), Vector3(0.04, 0.8, 2.2), GLASS)
	# Yellow nose and a stripe down the side, like real safety striping.
	_box(Vector3(0, 2.25, -h + 0.55), Vector3(2.42, 1.0, 0.06), _stripe)
	_box(Vector3(0, 1.48, 0), Vector3(3.12, 0.12, L - 0.2), _stripe)
	# Exhaust stack and radiator fans on the long hood.
	_box(Vector3(0, 1.42 + hood_h + 0.2, cab_z + cab_len * 0.5 + 3.5), Vector3(0.5, 0.4, 0.9), TRUCK)
	for k in 3:
		_box(Vector3(0, 1.42 + hood_h + 0.06, h - 2.2 - k * 1.6), Vector3(1.4, 0.12, 1.4), TRUCK)
	# Headlight.
	_box(Vector3(0, 3.0, -h + 0.5), Vector3(0.5, 0.3, 0.05), Color("#fff5d0"))


func _gp38() -> void:  # EMD GP38-2: 59 ft 2 in, four axles
	_hood_unit(18.0, 2.25, 2.4, 4.5, 2)


func _sd40() -> void:  # EMD SD40-2: 68 ft 10 in, six axles, the classic road freight unit
	_hood_unit(21.0, 2.4, 2.3, 5.2, 3)


func _sd70() -> void:  # EMD SD70: 72 ft 4 in, six axles, wide-nose cab
	_hood_unit(22.6, 2.45, 2.2, 5.6, 3)


func _p42() -> void:  # GE P42DC Genesis: 69 ft, a full-width streamlined body
	var L := 21.0
	var h := L * 0.5
	_trucks(L, 5.2, 2, 1.0)
	_box(Vector3(0, 1.2, 0), Vector3(3.0, 0.4, L), TRUCK)
	_box(Vector3(0, 2.95, 0.6), Vector3(3.05, 3.1, L - 1.2), Color("#c9ccce"))
	# A sloped nose: stacked, shrinking boxes.
	for k in 4:
		var t := float(k) / 4.0
		_box(Vector3(0, 1.6 + t * 2.2, -h + 0.3 + t * 0.9), Vector3(3.0, 0.6, 1.2 - t * 0.9 + 0.3), Color("#c9ccce"))
	_box(Vector3(0, 3.7, -h + 1.15), Vector3(2.6, 0.7, 0.05), GLASS)
	_box(Vector3(0, 2.2, 0), Vector3(3.08, 0.35, L - 0.4), Color("#1f4e8c"))  # blue band
	_box(Vector3(0, 2.6, 0), Vector3(3.08, 0.12, L - 0.4), Color("#b0322c"))  # red pinstripe
	_box(Vector3(0, 4.55, 0.6), Vector3(2.4, 0.15, L - 3.0), STEEL)
	_box(Vector3(0, 2.0, -h + 0.2), Vector3(0.6, 0.3, 0.05), Color("#fff5d0"))


# --- Cars ------------------------------------------------------------------

func _tank() -> void:  # 30,000 gal DOT-117 tank car, 59 ft
	var L := 18.0
	_trucks(L, 2.0, 2, 0.0)
	_box(Vector3(0, 1.05, 0), Vector3(1.0, 0.4, L - 0.6), TRUCK)
	_cylinder(Vector3(0, 2.45, 0), 1.5, L - 1.4, Color("#1d1f20"))
	_cylinder(Vector3(0, 2.45, -(L - 1.4) * 0.5), 1.2, 0.3, Color("#1d1f20"))
	_cylinder(Vector3(0, 2.45, (L - 1.4) * 0.5), 1.2, 0.3, Color("#1d1f20"))
	_box(Vector3(0, 4.05, 0), Vector3(1.0, 0.25, 1.2), STEEL)  # top fittings and walkway
	# White hazmat-style placard area.
	_box(Vector3(1.51, 2.6, -L * 0.3), Vector3(0.03, 0.5, 0.5), Color("#e9e6dc"))
	_box(Vector3(-1.51, 2.6, L * 0.3), Vector3(0.03, 0.5, 0.5), Color("#e9e6dc"))


func _hopper() -> void:  # open-top ore hopper (taconite jenny), 54 ft
	var L := 16.5
	var rust := Color("#6e3a26")
	_trucks(L, 2.0, 2, 0.0)
	_box(Vector3(0, 1.05, 0), Vector3(1.0, 0.4, L - 0.6), TRUCK)
	_box(Vector3(0, 2.9, 0), Vector3(3.15, 2.2, L - 1.6), rust)
	_box(Vector3(0, 4.05, 0), Vector3(3.2, 0.12, L - 1.5), rust)      # top chord
	for k in 3:
		# Hopper bays: sloped chutes under the body.
		_box(Vector3(0, 1.45, (k - 1) * (L - 2.6) / 3.0), Vector3(2.3, 0.8, (L - 4.0) / 3.0), rust.darkened(0.2))
	# The ore heaped up inside.
	_box(Vector3(0, 4.05, 0), Vector3(2.9, 0.18, L - 2.0), Color("#3b2f2a"))
	for k in 5:
		_box(Vector3(0, 3.95, (k - 2) * 2.5), Vector3(3.0, 0.08, 0.15), rust.darkened(0.3))  # ribs


func _flat() -> void:  # centerbeam flat with logs, 73 ft (logs carried on bulkheads)
	var L := 22.0
	_trucks(L, 2.2, 2, 0.0)
	_box(Vector3(0, 1.25, 0), Vector3(2.9, 0.3, L), Color("#5a5c5e"))
	for e: float in [-1.0, 1.0]:
		_box(Vector3(0, 2.8, e * (L * 0.5 - 0.3)), Vector3(2.9, 2.9, 0.25), Color("#5a5c5e"))
	_box(Vector3(0, 2.8, 0), Vector3(0.25, 2.9, L - 0.6), Color("#5a5c5e"))   # centre beam
	# Logs stacked on both sides of the beam.
	for side: float in [-1.0, 1.0]:
		for row in 3:
			for k in 3:
				var x: float = side * (0.42 + k * 0.38 + (row % 2) * 0.19)
				if absf(x) > 1.4:
					continue
				_cylinder(Vector3(x, 1.6 + row * 0.36, 0), 0.19, L - 1.0, Color("#7a5a3a").lerp(Color("#a07a4e"), float((k + row) % 3) / 2.0))


func _covered() -> void:  # 4,750 cu ft covered grain hopper, 59 ft
	var L := 18.0
	var gray := Color("#a9adab")
	_trucks(L, 2.0, 2, 0.0)
	_box(Vector3(0, 1.05, 0), Vector3(1.0, 0.4, L - 0.6), TRUCK)
	_box(Vector3(0, 3.0, 0), Vector3(3.2, 2.9, L - 1.4), gray)
	_cylinder(Vector3(0, 4.25, 0), 1.45, L - 1.4, gray, true)            # rounded roof
	_box(Vector3(0, 4.6, 0), Vector3(0.7, 0.2, L - 2.0), gray.darkened(0.15))  # roof hatches
	for k in 3:
		_box(Vector3(0, 1.3, (k - 1) * (L - 3.0) / 3.0), Vector3(2.4, 0.7, (L - 4.5) / 3.0), gray.darkened(0.12))
	for k in 7:
		_box(Vector3(0, 3.0, (k - 3) * 2.3), Vector3(3.24, 2.6, 0.12), gray.darkened(0.08))  # side posts


func _boxcar() -> void:  # 50 ft high-cube boxcar, 55 ft over the couplers
	var L := 16.8
	var red := Color("#6b2b22")
	_trucks(L, 2.0, 2, 0.0)
	_box(Vector3(0, 1.05, 0), Vector3(1.0, 0.4, L - 0.6), TRUCK)
	_box(Vector3(0, 3.0, 0), Vector3(3.2, 3.5, L - 0.8), red)
	_box(Vector3(0, 4.82, 0), Vector3(3.24, 0.14, L - 0.7), red.darkened(0.15))      # roof
	for side: float in [-1.0, 1.0]:
		# A plug door and its tracks, and the side's ribs.
		_box(Vector3(side * 1.62, 2.9, 0.6), Vector3(0.06, 3.1, 3.6), red.darkened(0.1))
		_box(Vector3(side * 1.64, 4.5, 0.6), Vector3(0.05, 0.1, 7.6), STEEL.darkened(0.3))
		_box(Vector3(side * 1.64, 1.35, 0.6), Vector3(0.05, 0.1, 7.6), STEEL.darkened(0.3))
		for k in 8:
			var z := -L * 0.5 + 1.0 + k * (L - 2.0) / 7.0
			if absf(z - 0.6) > 2.0:
				_box(Vector3(side * 1.62, 3.0, z), Vector3(0.04, 3.4, 0.1), red.darkened(0.2))
		_box(Vector3(side * 1.63, 4.0, -L * 0.3), Vector3(0.03, 0.35, 2.4), Color("#d8d4c8"))  # reporting marks
	for e: float in [-1.0, 1.0]:
		_box(Vector3(0, 3.0, e * (L * 0.5 - 0.35)), Vector3(3.0, 3.4, 0.08), red.darkened(0.25))  # ends


func _bilevel() -> void:  # bilevel coach (Bombardier/Pullman style), 85 ft
	var L := 25.9
	var body := Color("#c9ccce")
	_trucks(L, 3.0, 2, 0.0)
	_box(Vector3(0, 1.1, 0), Vector3(2.9, 0.4, L - 0.4), TRUCK)
	_box(Vector3(0, 3.1, 0), Vector3(3.0, 3.6, L - 0.4), body)
	_cylinder(Vector3(0, 4.55, 0), 1.45, L - 0.4, body, true)
	for side: float in [-1.0, 1.0]:
		for deck in 2:
			_box(Vector3(side * 1.51, 2.2 + deck * 1.65, 0), Vector3(0.04, 0.75, L - 4.0), GLASS)
		_box(Vector3(side * 1.52, 1.55, 0), Vector3(0.04, 0.3, L - 1.0), Color("#1f4e8c"))
		for e: float in [-1.0, 1.0]:
			_box(Vector3(side * 1.51, 2.4, e * (L * 0.5 - 1.4)), Vector3(0.05, 2.3, 1.3), Color("#7c8285"))  # doors


# --- Parts -----------------------------------------------------------------

## Two trucks (bogies) `inset` metres from each end with their wheels, and
## couplers at both ends. `pilot` adds a loco's plow-like pilot sheet.
func _trucks(L: float, inset: float, axles: int, pilot: float) -> void:
	var h := L * 0.5
	for e: float in [-1.0, 1.0]:
		var zc: float = e * (h - inset)
		var span := 1.8 * (axles - 1)
		_box(Vector3(0, 0.75, zc), Vector3(2.5, 0.45, span + 1.4), TRUCK)
		for a in axles:
			var z: float = zc - span * 0.5 + a * 1.8
			for side: float in [-1.0, 1.0]:
				_cylinder_x(Vector3(side * (GAUGE * 0.5 + 0.04), 0.46, z), 0.46, 0.13, Color("#3a3634"))
		_box(Vector3(0, 0.95, e * (h - 0.05)), Vector3(0.35, 0.3, 0.6), TRUCK)  # coupler
		if pilot > 0.0:
			_box(Vector3(0, 0.75, e * (h - 0.15)), Vector3(3.0, 0.7, 0.12), _stripe if e < 0.0 else TRUCK)


func _box(c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1] * h
		var v: Vector3 = f[2] * h
		var o: Vector3 = c + n * h
		var q := [o - u - v, o + u - v, o + u + v, o - u + v]
		for k in [0, 2, 1, 0, 3, 2]:
			_st.set_color(col)
			_st.add_vertex(q[k])


## A cylinder along Z (a tank, a log, a round roof). `top_only` draws just
## the upper half, for roofs.
func _cylinder(c: Vector3, r: float, length: float, col: Color, top_only := false) -> void:
	var n := 12
	var z0 := c.z - length * 0.5
	var z1 := c.z + length * 0.5
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		if top_only and (sin(a0) < -0.01 or sin(a1) < -0.01):
			continue
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0) + Vector3(c.x, c.y, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0) + Vector3(c.x, c.y, 0)
		var q := [Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1)]
		for k in [0, 1, 2, 0, 2, 3]:
			_st.set_color(col)
			_st.add_vertex(q[k])
		if not top_only:
			for z in [z0, z1]:
				var tri := [Vector3(c.x, c.y, z), Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z)]
				if z == z1:
					tri = [tri[0], tri[2], tri[1]]
				for p in tri:
					_st.set_color(col)
					_st.add_vertex(p)


## A wheel: a short cylinder across the track (along X).
func _cylinder_x(c: Vector3, r: float, width: float, col: Color) -> void:
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r, cos(a1) * r)
		var x0 := Vector3(c.x - width * 0.5, c.y, c.z)
		var x1 := Vector3(c.x + width * 0.5, c.y, c.z)
		var q := [x0 + p0, x0 + p1, x1 + p1, x1 + p0]
		for k in [0, 2, 1, 0, 3, 2]:
			_st.set_color(col)
			_st.add_vertex(q[k])
		for side in [[x0, false], [x1, true]]:
			var tri := [side[0], side[0] + p0, side[0] + p1]
			if side[1]:
				tri = [tri[0], tri[2], tri[1]]
			for p in tri:
				_st.set_color(col)
				_st.add_vertex(p)
