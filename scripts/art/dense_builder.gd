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
## Small parts only the desktop draws (door pulls, bulkhead panels, transom
## muntins, sash frames); the browser keeps its triangle budget.
static var fine := not OS.has_feature("web")


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
static func build_retail(seed: int, to_curb: float, lot := {}, spec := {}, level := 1) -> Array:
	var b := _start(seed, lot, spec)
	b.small_store = level == 0
	b._shop(to_curb, lot, false)
	b._service_yard(b.era == "prewar")
	return b._done()


## The parking and entrance of the shop DenseBuilder.build_retail draws for
## this seed and lot (or the strip center a shopping center forces), from a
## dry run that draws nothing: see `site`.
static func site_plan(seed: int, lot: Dictionary, strip := false, level := 1) -> Dictionary:
	var b := DenseBuilder._start(seed, lot)
	b._dry = true
	b.small_store = level == 0 and not strip
	if strip:
		force_shop = "strip"
	b._shop(3.9, lot, false)
	force_shop = ""
	return b.site


## The same for an office (build_office), whose lot is out back.
static func office_plan(seed: int, lot: Dictionary, storeys: int) -> Dictionary:
	var b := DenseBuilder._start(seed, lot)
	# An old street's office block is at the sidewalk with no lot of its
	# own (build_office): its people park at the curb.
	if b.era == "prewar":
		return b.site
	b._dry = true
	b._office(3.9, b.half * 2.0, storeys)
	return b.site


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
		_rear_wall(cx - uw * 0.5, cx + uw * 0.5, zf + d, base, floor_h, storeys, trim)
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
	_coping(w, d, cz, top, true)
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
	_rear_wall(-w * 0.5, w * 0.5, zf + d, 0.5, floor_h, storeys, trim)
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
		var bw := sw / bays
		# The classic 1880s-1920s Indiana storefront (Fairmount, Wabash,
		# Huntington): paneled bulkheads, tall display windows, a glass
		# entry door in the middle bay and a band of transom lights above,
		# under the sign board.
		for i in bays:
			var x := fx - sw * 0.5 + (i + 0.5) * bw
			if i == bays / 2 and bw > 1.5:
				_shop_door(x, bw, zf, mull)
			else:
				shopfront = fine
				_glass(Vector3(x, 1.65, zf - 0.03), Vector3(-1, 0, 0), bw - 0.12, 1.9, rng.randf_range(0.0, 0.2))
				shopfront = false
				_box("paint", Vector3(bw - 0.02, 0.6, 0.16), Vector3(x, 0.4, zf - 0.08), trim)
				if fine:
					# Raised panels on the bulkhead.
					_box("paint", Vector3(bw * 0.38, 0.32, 0.04), Vector3(x - bw * 0.22, 0.4, zf - 0.17), trim.darkened(0.1))
					_box("paint", Vector3(bw * 0.38, 0.32, 0.04), Vector3(x + bw * 0.22, 0.4, zf - 0.17), trim.darkened(0.1))
			# Transom lights, divided into small panes.
			_glass(Vector3(x, 2.93, zf - 0.03), Vector3(-1, 0, 0), bw - 0.12, 0.46, 0.0)
			if fine:
				var panes := maxi(2, roundi(bw / 0.45))
				for q in range(1, panes):
					_box("paint", Vector3(0.04, 0.46, 0.05), Vector3(x - bw * 0.5 + q * bw / panes, 2.93, zf - 0.06), mull)
			_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(x - bw * 0.5, 1.75, zf - 0.07), mull)
		_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(fx + sw * 0.5, 1.75, zf - 0.07), mull)
		_box("paint", Vector3(sw + 0.3, 0.08, 0.15), Vector3(fx, 2.66, zf - 0.08), mull)  # transom bar
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
			if fine:
				_sash(x, y, 1.0, wh, zf, trim)
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
	_alley_side(w, zf + d, fronts, fw, storeys, shop_h, floor_h, wall)
	if fine and storeys >= 2:
		_party_wall(w, d, zf, shop_h, floor_h, storeys, wall)
	if fine:
		_front_signs(w, zf, fronts, fw, shop_h, storeys)
	if depth > zf + d + 3.0:
		_flat_rect("asphalt", -width * 0.5, width * 0.5, zf + d, minf(depth, zf + d + 10.0), 0.06)
	_downtown_walk(to_curb, width, zf)


## A storefront's entry in the middle bay: a wood or aluminium door with a
## tall glass light and a kick panel, narrow sidelights either side, and a
## low step (fronts in Fairmount and Wabash, Indiana).
func _shop_door(x: float, bw: float, zf: float, mull: Color) -> void:
	var dw := 1.0
	var side := (bw - dw - 0.12) * 0.5
	for sgn in [-1.0, 1.0]:
		var sx: float = x + sgn * (dw + side) * 0.5
		shopfront = fine
		_glass(Vector3(sx, 1.65, zf - 0.03), Vector3(-1, 0, 0), side, 1.9, 0.0)
		shopfront = false
		_box("paint", Vector3(side, 0.6, 0.16), Vector3(sx, 0.4, zf - 0.08), mull)
	var col := Color(_pick(["#3a2a1e", "#1c1d1f", "#5a3a22"])) if fine else mull
	_box("paint", Vector3(dw + 0.12, 2.62, 0.08), Vector3(x, 1.31, zf - 0.02), col)  # frame, kick panel and head
	_glass(Vector3(x, 1.5, zf - 0.07), Vector3(-1, 0, 0), dw - 0.24, 1.5, 0.0)
	if fine:
		_box("metal", Vector3(0.03, 0.3, 0.05), Vector3(x + dw * 0.36, 1.1, zf - 0.11), Color("#8a8478"))  # pull
	_box("paint", Vector3(dw + 0.5, 0.15, 0.4), Vector3(x, 0.075, zf - 0.2), FOUNDATION)  # step


## A double-hung window's frame and sashes: side and head casing, and the
## meeting rail where the two sashes cross, in the trim colour.
func _sash(x: float, y: float, w: float, h: float, zf: float, trim: Color) -> void:
	_box("paint", Vector3(0.07, h, 0.06), Vector3(x - w * 0.5 + 0.035, y, zf - 0.05), trim)
	_box("paint", Vector3(0.07, h, 0.06), Vector3(x + w * 0.5 - 0.035, y, zf - 0.05), trim)
	_box("paint", Vector3(w, 0.07, 0.06), Vector3(x, y + h * 0.5 - 0.035, zf - 0.05), trim)
	_box("paint", Vector3(w, 0.05, 0.05), Vector3(x, y + 0.04, zf - 0.05), trim)


## The back of a Main Street block, on the alley: a steel service door and
## a small barred window for each shop, and plain double-hungs upstairs under
## brick segmental arches with stone sills, fewer than on the front (rear
## elevations of 1880s-1910s blocks in Jasper, Washington or Madison,
## Indiana; the back was never meant to be seen).
func _alley_side(w: float, zb: float, fronts: int, fw: float, storeys: int, shop_h: float, floor_h: float,
		wall: Color) -> void:
	var arch := wall.darkened(0.12)
	for k in fronts:
		var fx := -w * 0.5 + (k + 0.5) * fw
		var side := -1.0 if k % 2 == 0 else 1.0
		var dx := fx + fw * 0.2 * side
		_steel_door(Vector3(dx, 1.05, zb), 1.0)
		var wx := dx - side * 2.0
		_glass(Vector3(wx, 2.3, zb + 0.03), Vector3(1, 0, 0), 0.9, 0.9, 0.0)
		for b in 3:
			_box("metal", Vector3(0.025, 0.9, 0.025), Vector3(wx - 0.3 + b * 0.3, 2.3, zb + 0.08), Color("#2a2b2c"))
		_box("paint", Vector3(1.0, 0.08, 0.14), Vector3(wx, 1.81, zb + 0.07), FOUNDATION)
	var n := maxi(2, int(w / 3.6))
	for f in range(1, storeys):
		var y := shop_h + (f - 1) * floor_h + 1.6
		for i in n:
			var x := lerpf(-w * 0.5 + 1.8, w * 0.5 - 1.8, float(i) / (n - 1))
			var wh := 1.7
			_glass(Vector3(x, y, zb + 0.03), Vector3(1, 0, 0), 0.9, wh, rng.randf_range(0.0, 0.8))
			_box("brick", Vector3(1.25, 0.3, 0.1), Vector3(x, y + wh * 0.5 + 0.15, zb + 0.05), arch)
			_box("paint", Vector3(1.1, 0.08, 0.14), Vector3(x, y - wh * 0.5 - 0.04, zb + 0.07), FOUNDATION)
	if fine:
		_alley_services(w, zb, fronts, fw, storeys, shop_h, floor_h, n)


## The side walls of a Main Street block, which show wherever the
## neighbour is lower or gone (Marion, Wabash, Anderson): windows bricked
## up in a slightly different brick, and on a tall block now and then a
## faded painted advertisement, a "ghost sign" for a flour, tobacco or soft
## drink brand, its lettering worn to pale bands. Desktop only, with its own
## random numbers so the builder's don't move.
## Main Street signs that stick out over the walk, desktop only: double-faced
## blade signs on wrought-iron brackets between the shopfronts (a few of them
## outlined in neon, the 1940s way) and gooseneck lamps that light the flat
## sign boards, as on restored fronts in Wabash, Madison or Marion.
func _front_signs(w: float, zf: float, fronts: int, fw: float, shop_h: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 23])
	var iron := Color("#1e1e20")
	for k in fronts:
		var fx := -w * 0.5 + (k + 0.5) * fw
		var sw := fw - 1.0
		# Goosenecks over the board: barn-style shades on curved arms.
		if r.randf() < 0.45:
			var lamps := 2 if sw < 6.0 else 3
			# Their light washing down the board.
			_light_pool(Vector3(fx, 3.85, zf - 0.16), sw * 0.95, 1.4, Color(1.0, 0.86, 0.6), Vector3.FORWARD)
			for q in lamps:
				var lx := fx + (float(q) - (lamps - 1) * 0.5) * sw * 0.8 / lamps
				_box("paint", Vector3(0.04, 0.04, 0.42), Vector3(lx, 4.45, zf - 0.52), iron)
				_box("paint", Vector3(0.04, 0.22, 0.04), Vector3(lx, 4.35, zf - 0.71), iron)
				_box("paint", Vector3(0.22, 0.08, 0.22), Vector3(lx, 4.22, zf - 0.71), Color("#2c3e2f"))
				# The lamp's lens, facing down at the sign; it glows after dark.
				_quad("sign", Vector3(lx - 0.09, 4.175, zf - 0.8), Vector3(lx + 0.09, 4.175, zf - 0.8),
					Vector3(lx + 0.09, 4.175, zf - 0.62), Vector3(lx - 0.09, 4.175, zf - 0.62),
					Color(1.0, 0.86, 0.6, 1.0), [], Vector3.DOWN)
		# Blade signs hang over the walk from the upper floor's pier.
		if storeys < 2 or r.randf() > 0.4:
			continue
		var bx := fx - fw * 0.5 + 0.3 if k > 0 else fx + sw * 0.5 + 0.1
		# Boards about 1 m out; some stand tall, the old vertical kind.
		var bl := r.randf_range(0.8, 1.2)
		var bh := r.randf_range(0.7, 1.1) if r.randf() < 0.65 or storeys == 2 else r.randf_range(1.6, 2.4)
		var y0 := shop_h + 0.45
		var z0 := zf - 0.45
		var col := Color(CommercialBuilder.SIGNS[r.randi() % CommercialBuilder.SIGNS.size()])
		col.a = bl / 60.0
		for s in [-1.0, 1.0]:
			var x: float = bx + s * 0.035
			_quad("sign", Vector3(x, y0, z0), Vector3(x, y0, z0 - bl), Vector3(x, y0 + bh, z0 - bl), Vector3(x, y0 + bh, z0),
				col, [Vector2(0, 0), Vector2(bl, 0), Vector2(bl, 1), Vector2(0, 1)], Vector3(s, 0, 0))
		var frame := col.darkened(0.45)
		frame.a = 1.0
		_box("paint", Vector3(0.05, bh + 0.08, bl + 0.08), Vector3(bx, y0 + bh * 0.5, z0 - bl * 0.5), frame)
		# The bracket: an arm off the wall, a diagonal brace and two hangers.
		var arm_y := y0 + bh + 0.22
		_box("paint", Vector3(0.05, 0.05, bl + 0.5), Vector3(bx, arm_y, zf - 0.02 - (bl + 0.5) * 0.5), iron)
		var brace := Vector3(0, 0.5, -0.5)
		_box("paint", Vector3(0.04, 0.04, brace.length()), Vector3(bx, arm_y - 0.25, zf - 0.27),
			iron, Basis.looking_at(brace.normalized(), Vector3.RIGHT))
		for t in [0.15, bl - 0.15]:
			_box("paint", Vector3(0.025, 0.2, 0.025), Vector3(bx, y0 + bh + 0.12, z0 - t), iron)
		if r.randf() < 0.3:
			# Neon tubing around the board, both faces: lit after dark.
			var neon := Color(["#ff3b6b", "#ff5a2a", "#4ad0ff", "#ffd23a", "#7dff6a"][r.randi() % 5])
			neon.a = 1.0
			for s in [-1.0, 1.0]:
				var x: float = bx + s * 0.07
				for e in [[Vector3(0.03, 0.03, bl - 0.14), Vector3(x, y0 + 0.07, z0 - bl * 0.5)],
						[Vector3(0.03, 0.03, bl - 0.14), Vector3(x, y0 + bh - 0.07, z0 - bl * 0.5)],
						[Vector3(0.03, bh - 0.17, 0.03), Vector3(x, y0 + bh * 0.5, z0 - 0.07)],
						[Vector3(0.03, bh - 0.17, 0.03), Vector3(x, y0 + bh * 0.5, z0 - bl + 0.07)]]:
					_box("sign", e[0], e[1], neon)


func _party_wall(w: float, d: float, zf: float, shop_h: float, floor_h: float, storeys: int, wall: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 4421])
	for s in [-1.0, 1.0]:
		var x: float = s * (w * 0.5 + 0.012)
		var n := int((d - 4.0) / 4.5)
		for f in range(1, storeys):
			var y := shop_h + (f - 1) * floor_h + 1.6
			for i in n:
				if r.randf() < 0.5:
					var z := zf + 2.5 + i * 4.5
					var infill := wall.darkened(r.randf_range(0.04, 0.12)).lerp(Color("#8a5a44"), 0.15)
					_box("brick", Vector3(0.02, 1.7, 0.95), Vector3(x, y, z), infill)
					_box("paint", Vector3(0.03, 0.08, 1.05), Vector3(x + s * 0.005, y - 0.9, z), Color("#b9b2a2"))  # the old sill
		if storeys >= 3 and r.randf() < 0.55:
			var y0 := shop_h + 0.8
			var y1 := shop_h + (storeys - 1) * floor_h - 0.6
			var len := minf(d - 4.0, r.randf_range(8.0, 14.0))
			var zc := zf + 2.0 + len * 0.5
			var grounds := [Color("#7a3a30"), Color("#2f4a6a"), Color("#e2d6b4"), Color("#3c4a36")]
			var ground: Color = grounds[r.randi() % grounds.size()].lerp(wall, 0.45)
			# Painted straight on the brick, so the bricks still show through.
			_box("brick", Vector3(0.02, y1 - y0, len), Vector3(x + s * 0.008, (y0 + y1) * 0.5, zc), ground)
			var ink := Color("#efe6cc").lerp(wall, 0.35)
			var rows := 2 + r.randi() % 2
			for k in rows:
				var ry := lerpf(y1 - 0.9, y0 + 0.7, float(k) / (rows - 1))
				var rh := 0.9 if k == 0 else 0.5
				var rl := len * r.randf_range(0.55, 0.85)
				# Words: runs of letters with gaps between them, a few worn away.
				var words := 1 + r.randi() % 3
				var gap := 0.6
				var wl := (rl - gap * (words - 1)) / words
				for q in words:
					var wz := zc - rl * 0.5 + q * (wl + gap) + wl * 0.5
					var letters := maxi(2, int(wl / (rh * 0.8)))
					var lw := wl / letters
					for c in letters:
						if r.randf() < 0.15:
							continue
						var lz := wz - wl * 0.5 + (c + 0.5) * lw
						_box("brick", Vector3(0.02, rh * r.randf_range(0.8, 1.0), lw * 0.72), Vector3(x + s * 0.02, ry, lz),
							ink.lerp(wall, r.randf_range(0.0, 0.3)))


## What hangs on a real alley wall downtown (Marion, Wabash, Muncie): each
## shop's electric meter with its conduit up to the weatherhead and a gas
## meter on its riser by the back door; on blocks of three storeys or more a
## black (or rusting) steel fire escape with landings under two upstairs
## windows, switchback stairs and a drop ladder that stops 2.4 m off the
## pavement; and a window air conditioner in some flats. Desktop only, with
## its own random numbers so the builder's don't move.
func _alley_services(w: float, zb: float, fronts: int, fw: float, storeys: int, shop_h: float, floor_h: float,
		n: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 7341])
	var grey := Color("#8d9092")
	var conduit := Color("#9a9c9e")
	for k in fronts:
		var fx := -w * 0.5 + (k + 0.5) * fw
		var side := -1.0 if k % 2 == 0 else 1.0
		var dx := fx + fw * 0.2 * side
		# Electric meter on the far side of the door from the barred window.
		var mx := dx + side * 0.95
		_box("metal", Vector3(0.3, 0.45, 0.14), Vector3(mx, 1.6, zb + 0.09), grey)
		_box("metal", Vector3(0.16, 0.16, 0.06), Vector3(mx, 1.66, zb + 0.18), Color("#c9cdcf"))  # the glass dome
		_box("metal", Vector3(0.05, shop_h + 1.0 - 1.83, 0.05), Vector3(mx, (shop_h + 1.0 + 1.83) * 0.5, zb + 0.06), conduit)
		_box("metal", Vector3(0.12, 0.1, 0.12), Vector3(mx, shop_h + 1.05, zb + 0.1), Color("#2a2b2c"))  # weatherhead
		# Gas meter on its riser, low beside the meter.
		if r.randf() < 0.7:
			var gx := mx + side * 0.55
			_box("metal", Vector3(0.05, 1.0, 0.05), Vector3(gx, 0.5, zb + 0.06), Color("#c9b23a"))
			_box("metal", Vector3(0.32, 0.36, 0.24), Vector3(gx, 0.78, zb + 0.18), Color("#b4b6b3"))
			_box("metal", Vector3(0.14, 0.1, 0.1), Vector3(gx, 1.08, zb + 0.14), Color("#5a5f63"))  # regulator
	var esc_lo := -1
	if storeys >= 3 and n >= 3:
		esc_lo = 0 if r.randf() < 0.5 else n - 2
		var steel := Color("#1d1e1f") if r.randf() < 0.7 else Color("#4a3226")
		var xa := lerpf(-w * 0.5 + 1.8, w * 0.5 - 1.8, float(esc_lo) / (n - 1)) - 0.8
		var xb := lerpf(-w * 0.5 + 1.8, w * 0.5 - 1.8, float(esc_lo + 1) / (n - 1)) + 0.8
		var dep := 1.25
		var zc := zb + 0.06 + dep * 0.5
		var levels: Array[float] = []
		for f in range(1, storeys):
			levels.append(shop_h + (f - 1) * floor_h + 0.6)
		for li in levels.size():
			var ly: float = levels[li]
			_box("metal", Vector3(xb - xa, 0.05, dep), Vector3((xa + xb) * 0.5, ly, zc), steel)  # grating
			_box("metal", Vector3(xb - xa, 0.05, 0.05), Vector3((xa + xb) * 0.5, ly + 1.0, zb + 0.06 + dep), steel)  # top rail
			_box("metal", Vector3(xb - xa, 0.03, 0.03), Vector3((xa + xb) * 0.5, ly + 0.5, zb + 0.06 + dep), steel)
			for e in [xa, xb]:
				_box("metal", Vector3(0.05, 1.0, dep), Vector3(e, ly + 0.5, zc), steel.lightened(0.02))  # end rail
			var posts := int((xb - xa) / 1.2)
			for p in posts + 1:
				_box("metal", Vector3(0.04, 1.0, 0.04), Vector3(lerpf(xa, xb, float(p) / posts), ly + 0.5, zb + 0.06 + dep), steel)
			for p in 2:
				_box("metal", Vector3(0.06, 0.06, dep), Vector3(lerpf(xa + 0.3, xb - 0.3, p), ly - 0.12, zc), steel)  # bracket
			# Switchback flight up to the next landing, on the outer half.
			if li + 1 < levels.size():
				var rise: float = levels[li + 1] - ly
				var steps := ceili(rise / 0.2)
				var run := 0.24
				var dir := 1.0 if li % 2 == 0 else -1.0
				var x0 := (xa + 0.35) if dir > 0 else (xb - 0.35)
				var sz := zb + 0.06 + dep - 0.35
				for s in steps:
					_box("metal", Vector3(run, 0.04, 0.6), Vector3(x0 + dir * (s + 0.5) * run, ly + (s + 1) * rise / steps, sz), steel)
				for s in steps:  # the stringer, as a stepped side plate
					_box("metal", Vector3(run, rise / steps, 0.03), Vector3(x0 + dir * (s + 0.5) * run, ly + (s + 0.5) * rise / steps, sz + 0.32), steel)
		# Drop ladder from the bottom landing, hung 2.4 m off the pavement.
		var lx := xb - 0.5 if esc_lo == 0 else xa + 0.5
		var lz := zb + 0.06 + dep - 0.2
		var top: float = levels[0]
		for s in [-0.22, 0.22]:
			_box("metal", Vector3(0.04, top - 2.4, 0.04), Vector3(lx + s, (top + 2.4) * 0.5, lz), steel)
		var rungs := int((top - 2.4) / 0.3)
		for i in rungs:
			_box("metal", Vector3(0.44, 0.025, 0.025), Vector3(lx, 2.55 + i * 0.3, lz), steel)
	# Window air conditioners in some of the flats upstairs.
	for f in range(1, storeys):
		var y := shop_h + (f - 1) * floor_h + 1.6
		for i in n:
			if esc_lo >= 0 and (i == esc_lo or i == esc_lo + 1):
				continue
			if r.randf() < 0.22:
				var x := lerpf(-w * 0.5 + 1.8, w * 0.5 - 1.8, float(i) / (n - 1))
				_box("metal", Vector3(0.62, 0.4, 0.5), Vector3(x, y - 0.6, zb + 0.3), Color("#d2cdc2"))
				_box("metal", Vector3(0.5, 0.26, 0.02), Vector3(x, y - 0.6, zb + 0.56), Color("#8f8b84"))  # back grille


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
	_street_furniture(width, tz)


## What a Main Street streetscape grant puts along the curb (Fairmount,
## Wabash and Huntington, Indiana): black steel benches facing the shops,
## a trash can, a flower planter and the odd bike hoop, never more than a
## couple per storefront. Its own random numbers, so the builder's don't move.
func _street_furniture(width: float, tz: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 41])
	var black := Color("#1f2224")
	var slots := [-width * 0.35, width * 0.05, width * 0.38]
	for x in slots:
		var pick := r.randf()
		if pick < 0.3:
			# A bench, its back to the street.
			_box("paint", Vector3(1.8, 0.06, 0.45), Vector3(x, 0.45, tz - 0.1), black)
			_box("paint", Vector3(1.8, 0.45, 0.06), Vector3(x, 0.72, tz - 0.32), black)
			for sx in [-0.8, 0.8]:
				_box("paint", Vector3(0.06, 0.45, 0.5), Vector3(x + sx, 0.22, tz - 0.1), black)
		elif pick < 0.5:
			_box("paint", Vector3(0.6, 0.9, 0.6), Vector3(x, 0.45, tz), black)  # trash can
			_box("paint", Vector3(0.64, 0.06, 0.64), Vector3(x, 0.93, tz), black)
		elif pick < 0.7:
			# A planter of annuals.
			_box("concrete", Vector3(1.0, 0.6, 1.0), Vector3(x, 0.3, tz), Color("#b9b3a6"))
			_shrub(Vector3(x, 0.6, tz), 0.45)
		elif pick < 0.8 and fine:
			for k in 2:
				_box("paint", Vector3(0.05, 0.85, 0.6), Vector3(x + k * 0.8, 0.42, tz), black)  # bike hoops


# ---------------------------------------------------------------- offices

static func build_office(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}) -> Array:
	var b := _start(seed, lot, spec)
	# On an old street an office is a Chicago School commercial block at the
	# sidewalk from the start (the 1900s-20s office blocks of Indianapolis
	# and Marion), the same look its tower grows into.
	if b.era == "prewar":
		return TowerBuilder.build_tower(seed, to_curb, lot, storeys, spec, "chicago")
	b._office(to_curb, b.half * 2.0, storeys)
	b._service_yard(false)
	return b._done()


func _office(to_curb: float, width: float, storeys: int) -> void:
	# Room down one side for the drive to the lot out back.
	var w := minf(width - 10.0, rng.randf_range(22.0, 32.0))
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
	_coping(w, d, cz, top, mat == "brick")
	# Ribbon windows on every floor, wrapping the front and the sides.
	for f in storeys:
		var y := f * floor_h + 0.3 + (2.0 if f == 0 else 1.9)
		var gh := 2.9 if f == 0 else 1.7
		_glass(Vector3(0, y, zf - 0.03), Vector3(-1, 0, 0), w - 1.6, gh, 0.0 if f == 0 else rng.randf_range(0.05, 0.3))
		for s in [-1.0, 1.0]:
			_glass(Vector3(s * (w * 0.5 + 0.03), y, cz), Vector3(0, 0, -s), d - 1.6, gh, rng.randf_range(0.05, 0.3))
		# And the back, over the lot: offices have windows all round.
		_glass(Vector3(0, y if f > 0 else 1.9, zf + d + 0.03), Vector3(1, 0, 0), w - 1.6, 1.7, 0.2)
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
	_office_roof(w, d, cz, deck, wall, mat, storeys)
	if fine:
		_office_front(w, zf, storeys, floor_h, band)
	_office_lot(to_curb, w, zf, zf + d, width)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		# The one on the drive side stands in the front lawn, off the drive.
		var at := Vector3(-w * 0.5 - 1.5, 0, zf - 2.0) if s < 0.0 else Vector3(w * 0.5 - 2.5, 0, zf - 4.5)
		trees.append([at, pick[0], pick[1], rng.randf_range(0.8, 1.0)])


## The close-up front of a suburban office (1980s-2000s Indianapolis,
## Fort Wayne and Carmel office buildings): a glass entry vestibule with
## two pairs of aluminium doors under the canopy, downlights in the canopy
## soffit, a drip reveal under each precast spandrel band, a dark stone
## water table along the base, and clipped yews in a mulch bed along the
## front. Desktop only, with its own random numbers so the builder's don't move.
func _office_front(w: float, zf: float, storeys: int, floor_h: float, band: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 5113])
	var frame := Color("#2b2a28") if r.randf() < 0.6 else Color("#a7aaac")
	# Vestibule: 4.4 m wide, 1.8 m out, 2.9 m tall, glass all round.
	var vw := 4.4
	var vd := 1.8
	var vh := 2.9
	var vz := zf - 0.06 - vd * 0.5
	_glass(Vector3(0, vh * 0.5 + 0.02, zf - 0.06 - vd), Vector3(-1, 0, 0), vw - 0.1, vh - 0.1, 0.0)
	for s in [-1.0, 1.0]:
		_glass(Vector3(s * vw * 0.5, vh * 0.5 + 0.02, vz), Vector3(0, 0, -s), vd - 0.1, vh - 0.1, 0.0)
		for zz in [zf - 0.06 - vd, zf - 0.08]:
			_box("metal", Vector3(0.1, vh, 0.1), Vector3(s * vw * 0.5, vh * 0.5, zz), frame)  # corner posts
		# A pair of doors either side of the centre mullion, with pulls.
		var dx: float = s * 0.95
		_box("metal", Vector3(0.08, 2.2, 0.08), Vector3(dx + s * 0.9, 1.1, zf - 0.08 - vd), frame)
		for p in [-0.08, 0.08]:
			_box("metal", Vector3(0.05, 0.9, 0.05), Vector3(dx + p, 1.05, zf - 0.16 - vd), Color("#b7b9ba"))
	_box("metal", Vector3(0.1, vh, 0.1), Vector3(0, vh * 0.5, zf - 0.06 - vd), frame)  # centre mullion
	_box("metal", Vector3(vw, 0.1, 0.1), Vector3(0, 2.25, zf - 0.06 - vd), frame)  # door head / transom bar
	_box("metal", Vector3(vw + 0.1, 0.18, vd + 0.04), Vector3(0, vh + 0.08, vz), frame)  # roof fascia
	_box("concrete", Vector3(vw + 0.6, 0.06, vd + 0.6), Vector3(0, 0.03, vz - 0.2), FOUNDATION.lightened(0.05))  # landing
	# Downlights in the canopy soffit (canopy underside at 3.45).
	for x in [-2.0, 0.0, 2.0]:
		for z in [zf - 0.6, zf - 1.8]:
			_box("paint", Vector3(0.22, 0.03, 0.22), Vector3(x, 3.43, z), Color("#f2efe4"))
	# Drip reveal under each spandrel band, and a dark stone water table.
	for f in range(1, storeys):
		_box("paint", Vector3(w + 0.1, 0.05, 0.1), Vector3(0, f * floor_h + 0.33, zf - 0.09), band.darkened(0.35))
	_box("concrete", Vector3(w + 0.1, 0.55, 0.12), Vector3(0, 0.275, zf - 0.08), Color("#4a4744"))
	# Mulch bed and clipped yews either side of the entry.
	var keep := rng
	rng = r
	for s in [-1.0, 1.0]:
		var x0: float = s * (vw * 0.5 + 1.9)
		var x1: float = s * (w * 0.5 - 0.6)
		_flat_rect("line", minf(x0, x1), maxf(x0, x1), zf - 1.6, zf - 0.15, 0.065, Color("#4a3426"))
		var n := int(absf(x1 - x0) / 1.3)
		for i in n:
			_shrub(Vector3(lerpf(x0, x1, (i + 0.5) / n), 0.0, zf - 0.85), r.randf_range(0.42, 0.55), 2 if i % 3 == 1 else 0)
	rng = keep


## An office's roof (aerials of suburban Indianapolis and Fort Wayne
## offices): the elevator overrun as a small penthouse in the wall material,
## and on three storeys or more a louvred metal screen hiding the units.
## Its own random numbers, so the builder's don't move.
func _office_roof(w: float, d: float, cz: float, deck: float, wall: Color, mat: String, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 11])
	if storeys >= 2:
		var px := r.randf_range(-w * 0.25, w * 0.25)
		_box(mat, Vector3(3.0, 3.4, 4.2), Vector3(px, deck + 1.7, cz + d * 0.15), wall)
		_box("paint", Vector3(3.2, 0.12, 4.4), Vector3(px, deck + 3.46, cz + d * 0.15), Color("#8e8c86"))
	if storeys >= 3:
		var sw := minf(w * 0.5, 14.0)
		var sd := minf(d * 0.45, 8.0)
		var sx := r.randf_range(-w * 0.2, w * 0.2)
		var screen := Color(_pick(["#8f9294", "#b9b6ad", "#5f6266"]))
		for sgn in [-1.0, 1.0]:
			_box("metal", Vector3(sw, 2.0, 0.1), Vector3(sx, deck + 1.0, cz + sgn * sd * 0.5), screen)
			_box("metal", Vector3(0.1, 2.0, sd), Vector3(sx + sgn * sw * 0.5, deck + 1.0, cz), screen)
		if fine:
			# Louvres: horizontal blades on the long sides.
			for k in 6:
				for sgn in [-1.0, 1.0]:
					_box("paint", Vector3(sw, 0.04, 0.06), Vector3(sx, deck + 0.2 + k * 0.32, cz + sgn * (sd * 0.5 + 0.07)), screen.darkened(0.25))


## The office's lot out back, reached by a drive down the side from a curb
## cut: a 5 ft walk along the back wall, then 9 x 18 ft stalls nosed in
## toward it, a 24 ft two-way aisle and, with room, a second row along the
## back line (ITE / ULI parking dimensions). Recorded in `site` for the
## traffic sim.
func _office_lot(to_curb: float, w: float, zf: float, zb: float, width: float) -> void:
	var x0 := -width * 0.5 + 0.6
	var x1 := width * 0.5 - 0.6
	var z0 := zb + 1.5
	var rows := 2 if depth - 0.5 - z0 >= 18.3 else (1 if depth - 0.5 - z0 >= 12.8 else 0)
	if rows == 0:
		return
	var z1 := z0 + (18.3 if rows == 2 else 12.8)
	var dhw := minf(2.2, (x1 - w * 0.5 - 0.5) * 0.5)
	var dx := x1 - dhw
	# The curb cut and apron, the drive down the side and the walk out back.
	_flat_rect("drive", dx - dhw - 0.9, dx + dhw + 0.9, -to_curb, 0.0, 0.08)
	_flat_rect("asphalt", dx - dhw, dx + dhw, 0.0, z0, 0.06)
	_flat_rect("drive", -w * 0.5, w * 0.5, zb, z0, 0.07)
	_flat_rect("asphalt", x0, x1, z0, z1, 0.06)
	site.main_street = false
	site.cut_x = dx
	site.aisle_z = z0 + 5.5 + 3.65
	site.door = Vector2(0.0, zf)
	for r in rows:
		var a := z0 if r == 0 else z1 - 5.5
		var x := x0
		while x + 2.75 <= x1 + 0.01:
			# The front row leaves the drive clear where it comes in.
			if r == 1 or x + 2.75 <= dx - dhw - 0.3:
				_flat_rect("line", x - 0.06, x + 0.06, a, a + 5.5, 0.07, LINE)
				_flat_rect("line", x + 2.69, x + 2.81, a, a + 5.5, 0.07, LINE)
				site.stalls.append([Vector2(x + 1.375, a + 2.75), Vector2(0, -1) if r == 0 else Vector2(0, 1)])
			x += 2.75


# ---------------------------------------------------------------- parts

## The back of a flat or apartment block (zb, facing +z): windows in even
## bays on every floor, as real walk-ups and two-flats have (bedrooms and
## kitchens look out back), and the stair hall's back door at the middle,
## down concrete steps to the yard. The steps stand on a footing that runs
## below grade, so on a lot that falls away behind they still reach the
## ground instead of hanging in the air.
func _rear_wall(x0: float, x1: float, zb: float, base: float, floor_h: float, storeys: int, trim: Color) -> void:
	var n := maxi(2, int((x1 - x0) / 3.2))
	var door_x := (x0 + x1) * 0.5
	for f in storeys:
		var y := base + f * floor_h + 1.5
		for i in n:
			var x := lerpf(x0, x1, (i + 0.5) / n)
			if f == 0 and absf(x - door_x) < 1.4:
				continue
			_window(Vector3(x, y, zb), Vector3(1, 0, 0), 1.0, 1.5, false, false, trim)
	_box("paint", Vector3(0.95, 2.1, 0.06), Vector3(door_x, base + 1.05, zb + 0.03), Color("#4d5254"))
	_box("paint", Vector3(1.25, 0.14, 0.1), Vector3(door_x, base + 2.17, zb + 0.05), trim)
	var footing := 1.6  # below grade: hidden on level ground, showing where the yard falls away
	_box("concrete", Vector3(1.6, base + footing, 1.2), Vector3(door_x, (base - footing) * 0.5, zb + 0.6), FOUNDATION)
	var steps := ceili(base / 0.19)
	for k in range(1, steps):
		var top := base - k * base / steps
		_box("concrete", Vector3(1.2, top + footing, 0.28), Vector3(door_x, (top - footing) * 0.5, zb + 1.2 + (k - 0.5) * 0.28),
			FOUNDATION.lightened(0.04))


## A flat-roofed block centred on x = cx (CommercialBuilder's is centred on 0).
func _block(mat: String, cx: float, w: float, d: float, cz: float, deck: float, top: float, wall: Color) -> void:
	_box(mat, Vector3(w, deck, d), Vector3(cx, deck * 0.5, cz), wall)
	var y := deck + 0.02
	_quad("membrane", Vector3(cx - w * 0.5, y, cz - d * 0.5), Vector3(cx + w * 0.5, y, cz - d * 0.5),
		Vector3(cx + w * 0.5, y, cz + d * 0.5), Vector3(cx - w * 0.5, y, cz + d * 0.5), _low_slope(w, d, cx + cz, mat == "brick"), [], Vector3.UP)
	_roof_bits(cx, w, d, cz, y, mat == "brick")
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
