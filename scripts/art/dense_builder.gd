class_name DenseBuilder
extends CommercialBuilder
## First-pass looks for the denser building types (the art thread refines
## them against photos). Benchmarked against real Midwestern towns:
##   - row homes: brick, two or three storeys, flat roofs behind a corbelled
##     cornice, a stoop and a small front yard (St. Louis, Cincinnati, Chicago)
##   - walk-up and mid-rise apartments: a brick block with a centre entry and
##     canopy, a regular grid of windows and parking at the side or back
##   - Main Street blocks: storefronts at the sidewalk with flats above, built
##     wall to wall across the whole lot, one shopfront for every 7-8 m
##   - offices: a brick or precast base with ribbon windows and spandrel
##     bands, a glass lobby, a plaza walk and a parking lot
## Same local space and output as HouseBuilder, but sized to the real lot
## width instead of the 20 m standard lot.

const SPANDREL := ["#c9c4b8", "#b8b2a6", "#8f8a80", "#d8d4ca", "#6e6a64"]
const OFFICE_GLASS := Color(0.55, 0.62, 0.66, 0.35)


static func _start(seed: int, lot: Dictionary, spec := {}) -> DenseBuilder:
	var b := DenseBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b.sign_spec = spec
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


func _done() -> Array:
	return [_commit_house(), _commit_flat(), trees, labels]


# ---------------------------------------------------------------- shops

## A shop on its own lot: a store with parking in front, a diner, a bank,
## a gas station on a corner, a strip center on a wide lot or a church,
## picked for the street's era (Main Street blocks are the mixed-use type
## now, chosen by the street rather than by chance).
static func build_retail(seed: int, to_curb: float, lot := {}, spec := {}) -> Array:
	var b := _start(seed, lot, spec)
	b._shop(to_curb, lot, false)
	b._service_yard(b.era == "prewar")
	return b._done()


# ---------------------------------------------------------------- row homes

## `lot` as for HouseBuilder.build (its width sets the size).
static func build_row(seed: int, to_curb: float, lot: Dictionary, units: int, storeys: int) -> Array:
	var b := _start(seed, lot)
	b._row(to_curb, b.half * 2.0, units, storeys)
	return b._done()


func _row(to_curb: float, width: float, units: int, storeys: int) -> void:
	var uw := (width - 1.0) / units
	var zf := rng.randf_range(4.0, 5.5)  # a small front yard
	var d := rng.randf_range(11.0, 13.5)
	var floor_h := 3.1
	# Sided rows are side-by-side duplexes and townhouses under one gable
	# roof with eaves and gutters; flat roofs belong to the brick rows,
	# behind a parapet and cornice (St. Louis, Cincinnati, Chicago).
	var painted := rng.randf() < 0.25
	var base := 0.45 if painted else 0.7  # raised first floor behind a stoop
	var deck := base + floor_h * storeys
	var trim := Color(_pick(["#d9d3c3", "#efede6", "#3a3530", "#cfc8b6"]))
	var siding := Color(_pick(SIDING))
	var door_side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in units:
		var cx := -width * 0.5 + 0.5 + (i + 0.5) * uw
		if painted:
			_box("siding", Vector3(uw, deck, d), Vector3(cx, deck * 0.5, zf + d * 0.5), siding)
		else:
			# Neighbours differ a little, as rows built one by one do.
			var wall := Color(_pick(FACADE_BRICK))
			var top := deck + rng.randf_range(0.5, 0.9)
			_block("brick", cx, uw, d, zf + d * 0.5, deck, top, wall)
			_box("paint", Vector3(uw, 0.35, 0.4), Vector3(cx, top - 0.1, zf - 0.15), trim)
			_box("brick", Vector3(uw, 0.25, 0.25), Vector3(cx, top - 0.45, zf - 0.1), wall.darkened(0.12))
		# The foundation shows below the siding or brick.
		_box("concrete", Vector3(uw, base, 0.08), Vector3(cx, base * 0.5, zf - 0.02), FOUNDATION)
		var side := door_side if i % 2 == 0 else -door_side
		var door_x := cx + side * (uw * 0.5 - 1.1)
		_stoop(door_x, zf - 0.05, 1.5, 1.4, base)
		_front_door(door_x, zf, base, Color(_pick(DOOR)))
		# Windows: one beside the door below, two on each floor above.
		_window(Vector3(cx - side * uw * 0.18, base + 1.45, zf), Vector3(-1, 0, 0), 1.0, 1.7, false, false, trim)
		for f in range(1, storeys):
			for s in [-1.0, 1.0]:
				_window(Vector3(cx + s * uw * 0.22, base + f * floor_h + 1.45, zf), Vector3(-1, 0, 0),
					0.95, 1.65, false, false, trim)
		_back(cx - uw * 0.5, cx + uw * 0.5, zf + d, [base + 1.5], base)
		# Walk to the stoop, a strip of lawn edge and a shrub or two.
		_flat_rect("drive", door_x - 0.6, door_x + 0.6, -0.3, zf - 1.8, 0.06)
		if rng.randf() < 0.6:
			_shrub(Vector3(cx - side * uw * 0.25, 0.0, zf - 0.7), rng.randf_range(0.4, 0.6))
	var x0 := -width * 0.5 + 0.5
	var x1 := width * 0.5 - 0.5
	for e in [x0, x1]:
		_box("concrete", Vector3(0.08, base, d), Vector3(e + signf(e) * 0.02, base * 0.5, zf + d * 0.5), FOUNDATION)
	if painted:
		_gable_roof(0.0, zf + d * 0.5, deck, d, d * 0.5 * rng.randf_range(0.33, 0.5), x1 - x0, true,
			Color(_pick(ROOF)), siding)
	# The alley garage pad at the back.
	if depth - 1.0 > zf + d + 8.0:
		_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, depth - 7.0, depth - 1.0, 0.06)
	if rng.randf() < 0.7:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(rng.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.2), pick[0], pick[1],
			rng.randf_range(0.7, 1.0)])


# ---------------------------------------------------------------- apartments

static func build_apartments(seed: int, to_curb: float, lot: Dictionary, storeys: int) -> Array:
	var b := _start(seed, lot)
	b._apartments(to_curb, b.half * 2.0, storeys)
	return b._done()


func _apartments(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 4.0, rng.randf_range(24.0, 34.0))
	var d := rng.randf_range(14.0, 17.0)
	var zf := rng.randf_range(6.0, 8.0)
	var floor_h := 3.0
	var deck := 0.5 + floor_h * storeys
	var top := deck + 0.8
	var cz := zf + d * 0.5
	var wall := Color(_pick(FACADE_BRICK))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	_box("paint", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(0, 0.25, cz), FOUNDATION)
	_block("brick", 0.0, w, d, cz, deck, top, wall)
	_coping(w, d, cz, top)
	# Centre entry: a glass door, a flat canopy and a walk to the street.
	_box("paint", Vector3(2.2, 2.4, 0.08), Vector3(0, 1.7, zf - 0.04), trim)
	_glass(Vector3(0, 1.65, zf - 0.09), Vector3(-1, 0, 0), 1.8, 2.2, 0.0)
	_box("paint", Vector3(3.2, 0.2, 1.6), Vector3(0, 3.1, zf - 0.8), Color("#3a3c3e"))
	_stoop(0.0, zf, 3.0, 1.6, 0.5)
	_flat_rect("drive", -0.9, 0.9, -0.3, zf - 1.6, 0.06)
	# Windows in bays either side of the stair, a stone band at each floor.
	var bays := maxi(2, int((w * 0.5 - 2.0) / 3.0))
	for f in storeys:
		var y := 0.5 + f * floor_h + 1.55
		for s in [-1.0, 1.0]:
			for i in bays:
				var x: float = s * (2.4 + (i + 0.5) * (w * 0.5 - 2.6) / bays)
				_window(Vector3(x, y, zf), Vector3(-1, 0, 0), 1.2, 1.5, false, false, trim)
		# Side walls have windows too: the end flats are corner flats.
		var nside := maxi(2, int((d - 3.0) / 3.6))
		for s in [-1.0, 1.0]:
			for i in nside:
				var z := zf + 1.8 + (i + 0.5) * (d - 3.6) / nside
				_window(Vector3(s * w * 0.5, y, z), Vector3(0, 0, -s), 1.1, 1.5, false, false, trim)
		if f > 0:
			# Stair-hall window over the door.
			_glass(Vector3(0, y, zf - 0.02), Vector3(-1, 0, 0), 1.0, 1.6, 0.0)
			_box("paint", Vector3(w, 0.18, 0.12), Vector3(0, 0.5 + f * floor_h - 0.1, zf - 0.06), trim)
	_back(-w * 0.5, w * 0.5, zf + d, [2.0], 0.5)
	# Rooftop units, parking behind.
	for i in rng.randi_range(1, 3):
		_box("metal", Vector3(1.6, 1.0, 1.1), Vector3(rng.randf_range(-w * 0.35, w * 0.35), deck + 0.5, cz),
			Color("#b9bcbc"))
	_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 14.0, width)
	# Foundation shrubs and a street tree.
	var x := -w * 0.5 + 0.6
	while x < w * 0.5 - 0.5:
		if absf(x) > 2.0:
			_shrub(Vector3(x, 0.0, zf - 0.6), rng.randf_range(0.4, 0.6))
		x += rng.randf_range(1.2, 2.0)
	var pick := TreeField.pick(rng)
	trees.append([Vector3(-width * 0.3, 0, -to_curb + 1.2), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- Main Street

static func build_mixed(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}) -> Array:
	var b := _start(seed, lot, spec)
	b._mixed(to_curb, b.half * 2.0, storeys)
	b._service_yard(b.era == "prewar")
	return b._done()


func _mixed(to_curb: float, width: float, storeys: int) -> void:
	var w := width - 0.4  # wall to wall with its neighbours
	var d := rng.randf_range(18.0, 24.0)
	var zf := 0.4
	var cz := zf + d * 0.5
	var shop_h := 4.2
	var floor_h := 3.4
	var deck := shop_h + floor_h * (storeys - 1)
	var top := deck + 0.7
	# Most downtown fronts are red brick; some are buff brick, and some were
	# painted over in the last century.
	var wall := Color(_pick(FACADE_BRICK + FACADE_BRICK + ["#c9b48a", "#d6c39b", "#e6dfcf", "#6f7f86"]))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6", "#3a3530"]))
	# 1870s-1900s Italianate fronts carry a deep bracketed metal cornice and
	# hooded window caps; later commercial-style fronts a plain corbelled top.
	var italianate := rng.randf() < 0.55
	var mull: Color = MULLION[rng.randi() % 2]
	# Picked from the seed, not drawn, so protection moves no random draws.
	var mark := posmod(hash(rng.seed), 1000)
	# Many prewar fronts got a 1960s "modernization": an aluminium slipcover
	# hung over the upper floors and cornice. Restoration takes it off and
	# repaints the woodwork and cornice in period colours (Main Street
	# rehabs in Washington, Jasper or Madison, Indiana).
	var slipcover := not restored and era == "prewar" and storeys >= 2 and mark < 220
	if restored:
		trim = Color(["#3d4a3a", "#5a2626", "#e6dcc0", "#6b5038", "#2f3a4a"][mark % 5])
	_block("brick", 0.0, w, d, cz, deck, top, wall)
	# One storefront every 7-8 m, each with its own sign and maybe an awning.
	var fronts := maxi(1, roundi(w / 7.5))
	var fw := w / fronts
	for k in fronts:
		var fx := -w * 0.5 + (k + 0.5) * fw
		var sw := fw - 1.0
		var bays := 3
		for i in bays:
			var x := fx - sw * 0.5 + (i + 0.5) * sw / bays
			_glass(Vector3(x, 1.85, zf - 0.03), Vector3(-1, 0, 0), sw / bays - 0.12, 2.3, rng.randf_range(0.0, 0.2))
			_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(x - sw / bays * 0.5, 1.75, zf - 0.07), mull)
		_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(fx + sw * 0.5, 1.75, zf - 0.07), mull)
		_box("paint", Vector3(sw + 0.3, 0.6, 0.16), Vector3(fx, 0.4, zf - 0.08), trim)
		_box("paint", Vector3(sw + 0.3, 0.12, 0.18), Vector3(fx, 3.25, zf - 0.09), trim)
		# The lot's own business takes the middle shopfront; its neighbours
		# in the block keep their own painted signs.
		var own := sign_spec
		if k != fronts / 2:
			sign_spec = {}
		_sign(Vector3(fx, 3.4, zf - 0.1), sw * 0.8, 0.7)
		sign_spec = own
		if rng.randf() < 0.5:
			_awning(fx, sw, zf, 3.15, Color(_pick(AWNING)))
		elif restored:
			_awning(fx, sw, zf, 3.15, Color(AWNING[(mark + k) % AWNING.size()]))
		# Brick piers between the shopfronts.
		_box("brick", Vector3(0.6, shop_h, 0.2), Vector3(fx - fw * 0.5 + 0.3, shop_h * 0.5, zf - 0.1), wall.darkened(0.06))
	_box("brick", Vector3(0.6, shop_h, 0.2), Vector3(w * 0.5 - 0.3, shop_h * 0.5, zf - 0.1), wall.darkened(0.06))
	_box("paint", Vector3(w, 0.18, 0.3), Vector3(0, shop_h + 0.1, zf - 0.15), trim)
	if slipcover:
		# Ribbed anodised aluminium from the storefront cornice to the roof.
		var panel := Color("#b8b4a8") if mark % 2 == 0 else Color("#c4b78f")
		var ph := top - shop_h - 0.2
		_box("metal", Vector3(w - 0.2, ph, 0.12), Vector3(0, shop_h + 0.2 + ph * 0.5, zf - 0.12), panel)
		var ribs := maxi(4, int(w / 0.6))
		for i in ribs:
			_box("metal", Vector3(0.05, ph, 0.06), Vector3(lerpf(-w * 0.5 + 0.3, w * 0.5 - 0.3, float(i) / (ribs - 1)),
				shop_h + 0.2 + ph * 0.5, zf - 0.21), panel.darkened(0.12))
	# Flats above: tall windows with sills and lintels.
	var n := maxi(2, int(w / 2.6))
	for f in range(1, storeys if not slipcover else 1):
		var y := shop_h + (f - 1) * floor_h + 1.6
		for i in n:
			var x := lerpf(-w * 0.5 + 1.4, w * 0.5 - 1.4, float(i) / (n - 1))
			var wh := rng.randf_range(1.8, 2.0)
			_glass(Vector3(x, y, zf - 0.02), Vector3(-1, 0, 0), 1.0, wh, rng.randf_range(0.0, 0.7))
			_box("paint", Vector3(1.3, 0.1, 0.16), Vector3(x, y - wh * 0.5 - 0.05, zf - 0.08), trim)
			if italianate:
				# A hood mould: a wider cap with a raised crown.
				_box("paint", Vector3(1.5, 0.3, 0.16), Vector3(x, y + wh * 0.5 + 0.15, zf - 0.08), trim)
				_box("paint", Vector3(0.7, 0.16, 0.18), Vector3(x, y + wh * 0.5 + 0.38, zf - 0.09), trim)
			else:
				_box("paint", Vector3(1.4, 0.26, 0.12), Vector3(x, y + wh * 0.5 + 0.13, zf - 0.06), trim)
	if slipcover:
		pass
	elif italianate:
		# Bracketed cornice: a deep frieze, paired brackets, a projecting crown.
		_box("paint", Vector3(w, 0.7, 0.2), Vector3(0, top - 0.55, zf - 0.1), trim)
		var nb := maxi(3, int(w / 1.3))
		for i in nb:
			var bx := lerpf(-w * 0.5 + 0.3, w * 0.5 - 0.3, float(i) / (nb - 1))
			_box("paint", Vector3(0.22, 0.6, 0.5), Vector3(bx, top - 0.5, zf - 0.25), trim.darkened(0.08))
		_box("paint", Vector3(w + 0.2, 0.25, 0.75), Vector3(0, top - 0.1, zf - 0.33), trim)
	else:
		# Corbelled cornice and coping.
		_box("brick", Vector3(w, 0.3, 0.2), Vector3(0, top - 0.5, zf - 0.1), wall.darkened(0.1))
		_box("paint", Vector3(w + 0.1, 0.25, 0.4), Vector3(0, top - 0.15, zf - 0.15), trim)
	_box("metal", Vector3(1.8, 1.1, 1.2), Vector3(rng.randf_range(-w * 0.3, w * 0.3), deck + 0.55, cz + 2.0),
		Color("#b9bcbc"))
	# The flats' stair door at one end, and the alley at the back.
	var sx := (w * 0.5 - 0.9) * (-1.0 if rng.randf() < 0.5 else 1.0)
	_box("paint", Vector3(1.0, 2.2, 0.06), Vector3(sx, 1.1, zf - 0.05), Color(_pick(DOOR)))
	if restored:
		# A bronze plaque on the end pier by the stair door: the district's listing.
		_box("metal", Vector3(0.45, 0.32, 0.04), Vector3(sx + signf(sx) * 0.62, 1.55, zf - 0.23), Color("#6b5428"))
	if depth > zf + d + 3.0:
		_flat_rect("asphalt", -width * 0.5, width * 0.5, zf + d, minf(depth, zf + d + 10.0), 0.06)
	_downtown_walk(to_curb, width, zf)


## A downtown sidewalk: concrete from the shopfronts all the way to the curb
## (no grass strip), a street tree in an iron grate on most fronts and an
## acorn lamp now and then, as on Main Street in Jasper or Washington, Indiana.
func _downtown_walk(to_curb: float, width: float, zf: float) -> void:
	_flat_rect("drive", -width * 0.5, width * 0.5, -to_curb + RoadStyle.CURB_WIDTH, zf, 0.06)
	var tz := -to_curb + RoadStyle.CURB_WIDTH + 0.9
	if rng.randf() < 0.6:
		var tx := rng.randf_range(-width * 0.25, width * 0.25)
		_flat_rect("line", tx - 0.6, tx + 0.6, tz - 0.6, tz + 0.6, 0.07, Color("#2a2a28"))
		# Downtown street trees are mostly thornless honey locust, which
		# tolerates grates and salt, with the odd maple.
		var sp: int = TreeField.Species.LOCUST if rng.randf() < 0.75 else TreeField.Species.MAPLE
		trees.append([Vector3(tx, 0, tz), sp, TreeField.LEAF[sp], rng.randf_range(0.55, 0.75)])
	if rng.randf() < 0.4:
		var lx := (width * 0.5 - 0.4) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var black := Color("#1f2224")
		_box("paint", Vector3(0.45, 0.5, 0.45), Vector3(lx, 0.25, tz), black)
		_box("paint", Vector3(0.14, 3.6, 0.14), Vector3(lx, 2.3, tz), black)
		_box("paint", Vector3(0.42, 0.55, 0.42), Vector3(lx, 4.35, tz), Color("#efe9d8"))  # the acorn globe
		_box("paint", Vector3(0.3, 0.12, 0.3), Vector3(lx, 4.7, tz), black)


# ---------------------------------------------------------------- offices

static func build_office(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}) -> Array:
	var b := _start(seed, lot, spec)
	b._office(to_curb, b.half * 2.0, storeys)
	b._service_yard(false)
	return b._done()


func _office(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 6.0, rng.randf_range(22.0, 32.0))
	var d := rng.randf_range(16.0, 22.0)
	var zf := rng.randf_range(8.0, 11.0)
	var cz := zf + d * 0.5
	var floor_h := 3.9
	var deck := floor_h * storeys + 0.3
	var top := deck + 1.2
	var brick := rng.randf() < 0.5
	var wall := Color(_pick(FACADE_BRICK)) if brick else Color(_pick(SPANDREL))
	var mat := "brick" if brick else "paint"
	var band := Color(_pick(SPANDREL))
	_block(mat, 0.0, w, d, cz, deck, top, wall)
	_coping(w, d, cz, top)
	# Ribbon windows on every floor, wrapping the front and the sides.
	for f in storeys:
		var y := f * floor_h + 0.3 + (2.0 if f == 0 else 1.9)
		var gh := 2.9 if f == 0 else 1.7
		_glass(Vector3(0, y, zf - 0.03), Vector3(-1, 0, 0), w - 1.6, gh, 0.0 if f == 0 else rng.randf_range(0.05, 0.3))
		for s in [-1.0, 1.0]:
			_glass(Vector3(s * (w * 0.5 + 0.03), y, cz), Vector3(0, 0, -s), d - 1.6, gh, rng.randf_range(0.05, 0.3))
		if f > 0:
			_box("paint", Vector3(w + 0.06, 0.9, 0.08), Vector3(0, f * floor_h + 0.3 + 0.45, zf - 0.04), band)
		# Mullions every 1.5 m.
		var x := -w * 0.5 + 0.8
		while x <= w * 0.5 - 0.7:
			_box("paint", Vector3(0.08, gh, 0.1), Vector3(x, y, zf - 0.06), MULLION[0])
			x += 1.5
	# Entrance canopy, a plaza walk with planters, and a parking lot at the side.
	_box("paint", Vector3(6.0, 0.3, 2.4), Vector3(0, 3.6, zf - 1.2), Color("#3a3c3e"))
	_flat_rect("drive", -4.0, 4.0, -0.3, zf, 0.07)
	for s in [-1.0, 1.0]:
		_box("concrete", Vector3(1.4, 0.6, 1.4), Vector3(s * 3.2, 0.3, zf - 3.0), FOUNDATION)
		_shrub(Vector3(s * 3.2, 0.6, zf - 3.0), 0.5)
	_sign(Vector3(0, 0.3, zf - 5.0), 3.2, 0.7)
	for i in rng.randi_range(2, 4):
		_box("metal", Vector3(2.2, 1.4, 1.6), Vector3(rng.randf_range(-w * 0.3, w * 0.3), deck + 0.7,
			cz + rng.randf_range(-d * 0.2, d * 0.2)), Color("#b9bcbc"))
	_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 18.0, width)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (w * 0.5 + 1.5), 0, zf - 2.0), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- parts

## A flat-roofed block centred on x = cx (CommercialBuilder's is centred on 0).
func _block(mat: String, cx: float, w: float, d: float, cz: float, deck: float, top: float, wall: Color) -> void:
	_box(mat, Vector3(w, deck, d), Vector3(cx, deck * 0.5, cz), wall)
	var y := deck + 0.02
	_quad("paint", Vector3(cx - w * 0.5, y, cz - d * 0.5), Vector3(cx + w * 0.5, y, cz - d * 0.5),
		Vector3(cx + w * 0.5, y, cz + d * 0.5), Vector3(cx - w * 0.5, y, cz + d * 0.5), Color("#bdbbb4"), [], Vector3.UP)
	var ph := top - deck
	var t := 0.25
	_box(mat, Vector3(w, ph, t), Vector3(cx, deck + ph * 0.5, cz - d * 0.5 + t * 0.5), wall)
	_box(mat, Vector3(w, ph, t), Vector3(cx, deck + ph * 0.5, cz + d * 0.5 - t * 0.5), wall)
	_box(mat, Vector3(t, ph, d), Vector3(cx - w * 0.5 + t * 0.5, deck + ph * 0.5, cz), wall)
	_box(mat, Vector3(t, ph, d), Vector3(cx + w * 0.5 - t * 0.5, deck + ph * 0.5, cz), wall)


## An asphalt lot with 9 ft stalls along both long edges, cut short at the
## back of the lot (none at all if there is no room).
func _parking(x0: float, x1: float, z0: float, z1: float, _width: float) -> void:
	z1 = minf(z1, depth - 0.5)
	if z1 - z0 < 6.0:
		return
	_flat_rect("asphalt", x0, x1, z0, z1, 0.06)
	var x := x0
	while x <= x1 + 0.01:
		_flat_rect("line", x - 0.06, x + 0.06, z0, z0 + 5.5, 0.07, LINE)
		if z1 - z0 > 16.0:
			_flat_rect("line", x - 0.06, x + 0.06, z1 - 5.5, z1, 0.07, LINE)
		x += 2.75
