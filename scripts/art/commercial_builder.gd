class_name CommercialBuilder
extends HouseBuilder
## Shops and factories, benchmarked against photos of real Midwestern towns:
##   - the one-storey retail building on its own lot: brick or block front,
##     aluminium storefront, a sign band, parapet with coping, rooftop units
##     and a striped parking lot in front
##   - the two-storey main-street block built up to the sidewalk: brick,
##     storefront below, tall upper windows with stone sills and lintels,
##     a corbelled cornice
##   - the metal industrial building: ribbed panels with a darker wainscot,
##     a low 1:12 roof, overhead doors, a small brick office at the front,
##     and sometimes silos or a stack, with a concrete apron and gravel yard
## Same local space and output as HouseBuilder.

const FACADE_BRICK := ["#8a4a38", "#9b5a42", "#7a4234", "#a8775c", "#b59a7c", "#6e3b2e"]
const BLOCK := ["#b8b2a4", "#a49d8f", "#c9c1ae", "#8f8a80"]
const SIGNS := ["#7a1f1f", "#1f3b6e", "#1d4d2c", "#2a2a2c", "#8a5a12", "#5a2a5e", "#b8b4a8"]
const AWNING := ["#1f3b6e", "#7a1f1f", "#1d4d2c", "#2a2a2c", "#6b5a3a"]
const MULLION := [Color("#3a3530"), Color("#a9acae")]  # dark bronze or clear anodised
const METAL_WALL := ["#c9cbc8", "#b9b4a6", "#d8d6cf", "#8e9aa3", "#a7aba9", "#c2b59b"]
const WAINSCOT := ["#4a4c4f", "#5a2a26", "#2f3b4a", "#6b6458"]
const GRAVEL := Color("#8d877c")
const LINE := Color("#e8e6df")
## Set by the art gallery to draw one kind of shop.
static var force_shop := ""

## The business's sign, from Families.sign_of ({text, style, panel, letter,
## since}); empty paints generic lettering. Every sign band then carries it.
var sign_spec := {}
## Lettering for SignText: [{pos, normal, text, height, width, color, style}].
var labels := []


static func build_shop(seed: int, to_curb: float, lot := {}, spec := {}) -> Array:
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b.sign_spec = spec
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._shop(to_curb, lot)
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels]


## One shop of a kind that fits the lot and the street's era. Main Street
## blocks are left out where the street has its own mixed-use type.
func _shop(to_curb: float, lot: Dictionary, main_street := true) -> void:
	var kind: String = force_shop if force_shop != "" else _shop_kind(lot)
	if kind == "main_street" and not main_street and force_shop == "":
		kind = "retail"
	match kind:
		"main_street": _main_street(to_curb)
		"strip": _strip_center(to_curb)
		"gas": _gas_station(to_curb)
		"diner": _diner(to_curb)
		"bank": _bank(to_curb)
		"church": _church(to_curb)
		_: _retail(to_curb)


## Which kind of shop fits this lot: strip centers need a wide lot, gas
## stations like corners, and main-street blocks the old part of town.
func _shop_kind(lot: Dictionary) -> String:
	var w := half * 2.0
	var picks := ["retail", "retail", "diner", "bank"]
	if era == "prewar":
		picks += ["main_street", "main_street", "main_street", "church"]
	else:
		picks += ["main_street", "retail"]
	if w >= 26.0 and depth >= 36.0:
		picks += ["strip", "strip", "strip"]
	if lot.get("corner", false) and w >= 20.0 and depth >= 30.0:
		picks += ["gas", "gas", "gas"]
	elif w >= 24.0 and depth >= 36.0:
		picks += ["gas"]
	var k: String = _pick(picks)
	if k in ["diner", "bank", "church"] and (w < 18.0 or depth < 30.0):
		k = "retail"
	return k


static func build_factory(seed: int, to_curb: float, lot := {}, spec := {}) -> Array:
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b.sign_spec = spec
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._factory(to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels]


# ---------------------------------------------------------------- shops

func _retail(to_curb: float) -> void:
	var w := rng.randf_range(minf(14.0, half * 2.0 - 3.0), clampf(half * 2.0 - 2.5, 8.0, 17.5 + clampf(half * 2.0 - 22.0, 0.0, 8.0)))
	var d := rng.randf_range(12.0, minf(15.0, maxf(depth - 15.0, 12.0)))
	var h := rng.randf_range(4.8, 5.6)
	var zf := rng.randf_range(12.0, 13.0)  # parking in front
	var cz := zf + d * 0.5
	var brick := rng.randf() < 0.6
	var wall := Color(_pick(FACADE_BRICK)) if brick else Color(_pick(BLOCK))
	var mat := "brick" if brick else "paint"
	var mull: Color = MULLION[rng.randi() % 2]
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_flat_roofed(mat, w, d, cz, h, h + 0.9, wall)
	# Storefront: glass bays between mullions, with a double door.
	var sw := w * rng.randf_range(0.6, 0.8)
	var bays := int(sw / 1.6)
	var door := rng.randi_range(0, bays - 1)
	for i in bays:
		var x := -sw * 0.5 + (i + 0.5) * sw / bays
		var y := 1.55 if i == door else 1.8
		var gh := 2.6 if i == door else 2.1
		_glass(Vector3(x, y, zf - 0.03), Vector3(-1, 0, 0), sw / bays - 0.08, gh, 0.0 if i == door else rng.randf_range(0.0, 0.15))
		_box("paint", Vector3(0.08, 2.7, 0.12), Vector3(x - sw / bays * 0.5, 1.6, zf - 0.06), mull)
	_box("paint", Vector3(0.08, 2.7, 0.12), Vector3(sw * 0.5, 1.6, zf - 0.06), mull)
	_box("paint", Vector3(sw, 0.1, 0.14), Vector3(0, 2.92, zf - 0.07), mull)
	_box("paint", Vector3(sw, 0.5, 0.12), Vector3(0, 0.5, zf - 0.06), mull)
	# Sign band above the storefront.
	_sign(Vector3(0, 3.35, zf - 0.08), sw * rng.randf_range(0.55, 0.85), 0.9)
	if rng.randf() < 0.5:
		_awning(0.0, sw + 0.4, zf, 3.0, Color(_pick(AWNING)))
	# Rooftop units.
	for i in rng.randi_range(1, 3):
		var p := Vector3(rng.randf_range(-w * 0.3, w * 0.3), h, cz + rng.randf_range(-d * 0.2, d * 0.3))
		_box("metal", Vector3(1.8, 1.1, 1.2), p + Vector3(0, 0.55, 0), Color("#b9bcbc"))
		_box("paint", Vector3(1.0, 0.08, 0.8), p + Vector3(0, 1.14, 0), Color("#3a3c3e"))
	# Back service door.
	_box("paint", Vector3(1.0, 2.1, 0.06), Vector3(w * 0.3, 1.35, zf + d + 0.03), Color("#5a5e60"))
	# Parking: a walk along the front, a row of stalls, the aisle and the curb cut.
	_flat_rect("drive", -w * 0.5 - 0.5, w * 0.5 + 0.5, zf - 2.2, zf, 0.08)
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	_flat_rect("asphalt", lot0, lot1, 0.0, zf - 2.2, 0.06)
	_flat_rect("asphalt", -3.6, 3.6, -to_curb, 0.0, 0.1)
	var stall := 2.75  # 9 ft
	var x := lot0
	while x <= lot1 + 0.01:
		_flat_rect("line", x - 0.06, x + 0.06, zf - 2.2 - 5.5, zf - 2.2, 0.07, LINE)
		x += stall
	if rng.randf() < 0.6:
		var pick := TreeField.pick(rng)
		var tx := lot0 + 0.8 if rng.randf() < 0.5 else lot1 - 0.8
		trees.append([Vector3(tx, 0, -to_curb + 1.2), pick[0], pick[1], rng.randf_range(0.7, 1.0)])
	# A light pole near the street.
	var lx := lot1 - 0.5 if rng.randf() < 0.5 else lot0 + 0.5
	_box("paint", Vector3(0.6, 0.5, 0.6), Vector3(lx, 0.25, 0.8), FOUNDATION)
	_box("paint", Vector3(0.16, 7.5, 0.16), Vector3(lx, 4.0, 0.8), Color("#3a3c3e"))
	_box("paint", Vector3(0.5, 0.18, 0.9), Vector3(lx, 7.7, 0.8 + 0.3), Color("#3a3c3e"))


func _main_street(to_curb: float) -> void:
	var w := 2.0 * half - 0.4  # wall to wall with its neighbours
	var d := rng.randf_range(16.0, minf(22.0, maxf(depth - 6.0, 16.0)))
	var zf := 0.4
	var cz := zf + d * 0.5
	var floor_h := 4.2
	var h := floor_h + 3.6
	var wall := Color(_pick(FACADE_BRICK))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6", "#3a3530"]))
	var mull: Color = MULLION[rng.randi() % 2]
	_flat_roofed("brick", w, d, cz, h - 0.6, h, wall)
	# Storefront with a recessed centre door and a sign band.
	var sw := w - 1.6
	var bays := 4
	for i in bays:
		var x := -sw * 0.5 + (i + 0.5) * sw / bays
		_glass(Vector3(x, 1.85, zf - 0.03), Vector3(-1, 0, 0), sw / bays - 0.12, 2.3, rng.randf_range(0.0, 0.2))
		_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(x - sw / bays * 0.5, 1.75, zf - 0.07), mull)
	_box("paint", Vector3(0.1, 3.0, 0.14), Vector3(sw * 0.5, 1.75, zf - 0.07), mull)
	_box("paint", Vector3(sw + 0.3, 0.6, 0.16), Vector3(0, 0.4, zf - 0.08), trim)
	_box("paint", Vector3(sw + 0.3, 0.12, 0.18), Vector3(0, 3.25, zf - 0.09), trim)
	_sign(Vector3(0, 3.4, zf - 0.1), sw * 0.8, 0.7)
	_box("paint", Vector3(w, 0.18, 0.3), Vector3(0, floor_h + 0.1, zf - 0.15), trim)
	if rng.randf() < 0.5:
		_awning(0.0, sw, zf, 3.15, Color(_pick(AWNING)))
	# Upper floor: tall windows with sills and lintels.
	var n := rng.randi_range(4, 6)
	for i in n:
		var x := lerpf(-w * 0.5 + 1.6, w * 0.5 - 1.6, float(i) / (n - 1))
		var wh := rng.randf_range(1.8, 2.1)
		var y := floor_h + 1.6
		_glass(Vector3(x, y, zf - 0.02), Vector3(-1, 0, 0), 1.0, wh, rng.randf_range(0.0, 0.7))
		_box("paint", Vector3(1.3, 0.1, 0.16), Vector3(x, y - wh * 0.5 - 0.05, zf - 0.08), trim)
		_box("paint", Vector3(1.4, 0.26, 0.1), Vector3(x, y + wh * 0.5 + 0.13, zf - 0.05), trim)
	# Corbelled cornice and coping.
	_box("brick", Vector3(w, 0.3, 0.2), Vector3(0, h - 0.5, zf - 0.1), wall.darkened(0.1))
	_box("paint", Vector3(w + 0.1, 0.25, 0.4), Vector3(0, h - 0.15, zf - 0.15), trim)
	# Rooftop unit and an alley drive at the back.
	_box("metal", Vector3(1.8, 1.1, 1.2), Vector3(rng.randf_range(-4.0, 4.0), h - 0.6 + 0.55, cz + 2.0), Color("#b9bcbc"))
	if depth > zf + d + 1.0:
		_flat_rect("asphalt", -half, half, zf + d, depth, 0.06)


## A flat-roofed box: walls up to the roof deck, a pale membrane roof, and a
## parapet with coping around it.
func _flat_roofed(mat: String, w: float, d: float, cz: float, deck: float, top: float, wall: Color) -> void:
	_box(mat, Vector3(w, deck, d), Vector3(0, deck * 0.5, cz), wall)
	var y := deck + 0.02
	_quad("paint", Vector3(-w * 0.5, y, cz - d * 0.5), Vector3(w * 0.5, y, cz - d * 0.5),
		Vector3(w * 0.5, y, cz + d * 0.5), Vector3(-w * 0.5, y, cz + d * 0.5), Color("#bdbbb4"), [], Vector3.UP)
	var ph := top - deck
	var t := 0.25
	_box(mat, Vector3(w, ph, t), Vector3(0, deck + ph * 0.5, cz - d * 0.5 + t * 0.5), wall)
	_box(mat, Vector3(w, ph, t), Vector3(0, deck + ph * 0.5, cz + d * 0.5 - t * 0.5), wall)
	_box(mat, Vector3(t, ph, d), Vector3(-w * 0.5 + t * 0.5, deck + ph * 0.5, cz), wall)
	_box(mat, Vector3(t, ph, d), Vector3(w * 0.5 - t * 0.5, deck + ph * 0.5, cz), wall)
	_coping(w, d, cz, top)


func _coping(w: float, d: float, cz: float, top: float) -> void:
	var col := Color("#cfcbc2")
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(0, top, cz - d * 0.5), col)
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(0, top, cz + d * 0.5), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(-w * 0.5, top, cz), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(w * 0.5, top, cz), col)


func _sign(c: Vector3, w: float, h: float) -> void:
	var col := Color(_pick(SIGNS))
	col.a = w / 30.0
	if not sign_spec.is_empty():
		# The business's own name in its family's colours; alpha 0 tells the
		# sign shader there's real lettering, so it paints no stand-in.
		col = sign_spec.panel
		col.a = 0.0
		labels.append_array(SignText.on_panel(sign_spec, c + Vector3(0, 0, -0.01), w, h, Vector3.FORWARD))
	var r := Vector3(-w * 0.5, 0, 0)
	var u := Vector3(0, h, 0)
	# Faces the street (-z); x runs right to left as seen from the street.
	_quad("sign", c + r, c - r, c - r + u, c + r + u, col,
		[Vector2(0, 0), Vector2(w, 0), Vector2(w, 1), Vector2(0, 1)], Vector3.FORWARD)
	_box("paint", Vector3(w + 0.1, h + 0.1, 0.06), c + Vector3(0, h * 0.5, 0.04), col.darkened(0.3))


func _awning(cx: float, w: float, zf: float, y: float, col: Color) -> void:
	var a := Vector3(cx - w * 0.5, y + 0.6, zf)
	var b := Vector3(cx + w * 0.5, y + 0.6, zf)
	var c := Vector3(cx + w * 0.5, y, zf - 1.3)
	var d := Vector3(cx - w * 0.5, y, zf - 1.3)
	_quad("paint", d, c, b, a, col, [], Vector3.UP)
	_quad("paint", d, c, c + Vector3(0, -0.3, 0), d + Vector3(0, -0.3, 0), col.darkened(0.15), [], Vector3.FORWARD)


# ---------------------------------------------------------------- more shops

## A strip center, 1960s-now: one long flat-roofed building split into three
## to five tenants, each its own storefront and sign, under a continuous
## canopy on square columns, with a parking field in front.
func _strip_center(to_curb: float) -> void:
	var w := half * 2.0 - 2.0
	var d := rng.randf_range(14.0, minf(18.0, maxf(depth - 18.0, 14.0)))
	var h := rng.randf_range(5.2, 6.0)
	var zf := rng.randf_range(16.0, 18.0)
	var cz := zf + d * 0.5
	var wall := Color(_pick(BLOCK + ["#c9b79a", "#b8a58a"]))
	var mull: Color = MULLION[rng.randi() % 2]
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_flat_roofed("paint", w, d, cz, h, h + 1.2, wall)
	var n := clampi(int(w / 7.0), 3, 5)
	var bay := w / n
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * bay
		var sw := bay - 1.4
		_glass(Vector3(x - 0.4, 1.7, zf - 0.03), Vector3(-1, 0, 0), sw - 1.4, 2.3, rng.randf_range(0.0, 0.2))
		_glass(Vector3(x + sw * 0.5 - 0.5, 1.45, zf - 0.03), Vector3(-1, 0, 0), 0.95, 2.4, 0.0)
		_box("paint", Vector3(sw, 0.1, 0.12), Vector3(x, 2.9, zf - 0.06), mull)
		_box("paint", Vector3(sw, 0.35, 0.12), Vector3(x, 0.47, zf - 0.06), mull)
		_box("paint", Vector3(0.5, 3.0, 0.2), Vector3(x - bay * 0.5, 1.8, zf - 0.1), wall.darkened(0.1))
		_sign(Vector3(x, 3.9, zf - 2.55), sw * rng.randf_range(0.5, 0.8), 0.7)
	# Canopy over the walk on square columns.
	_box("paint", Vector3(w + 0.4, 0.5, 2.6), Vector3(0, 3.65, zf - 1.3), wall.lightened(0.1))
	_quad("paint", Vector3(-w * 0.5 - 0.2, 3.39, zf - 2.6), Vector3(w * 0.5 + 0.2, 3.39, zf - 2.6),
		Vector3(w * 0.5 + 0.2, 3.39, zf), Vector3(-w * 0.5 - 0.2, 3.39, zf), SOFFIT, [], Vector3.DOWN)
	var x := -w * 0.5
	while x <= w * 0.5 + 0.01:
		_box("paint", Vector3(0.45, 3.0, 0.45), Vector3(clampf(x, -w * 0.5 + 0.3, w * 0.5 - 0.3), 1.9, zf - 2.3), wall.lightened(0.1))
		x += bay
	_rooftop(w, d, cz, h, n)
	_shop_parking(to_curb, w, zf - 2.6, 0.0)


## A gas station: a lit canopy over two or three pump islands, a
## convenience store behind it, a price sign on a pole by the street.
func _gas_station(to_curb: float) -> void:
	var sw := minf(16.0, half * 2.0 - 4.0)
	var sd := 10.0
	var zf := minf(24.0, depth - sd - 2.0)
	var cz := zf + sd * 0.5
	var brand := Color(_pick(["#c8102e", "#00529b", "#007a33", "#f2a900", "#1d1d1d"]))
	var wall := Color(_pick(BLOCK + ["#d8d2c2"]))
	_box("paint", Vector3(sw + 0.1, 0.3, sd + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_flat_roofed("paint", sw, sd, cz, 4.2, 4.8, wall)
	_box("paint", Vector3(sw + 0.1, 0.7, 0.2), Vector3(0, 4.45, zf - 0.1), brand)
	for i in 4:
		_glass(Vector3(-sw * 0.3 + i * 1.6, 1.7, zf - 0.03), Vector3(-1, 0, 0), 1.5, 2.3, 0.0)
	_box("paint", Vector3(6.6, 0.1, 0.12), Vector3(-sw * 0.3 + 2.4, 2.9, zf - 0.06), MULLION[1])
	# Canopy: a deep flat roof on columns, its fascia in the brand colour.
	var cw := minf(sw + 2.0, half * 2.0 - 2.0)
	var cd := 10.0
	var ccz := zf - 4.0 - cd * 0.5
	_box("paint", Vector3(cw, 0.9, cd), Vector3(0, 5.25, ccz), brand)
	_quad("paint", Vector3(-cw * 0.5, 4.79, ccz - cd * 0.5), Vector3(cw * 0.5, 4.79, ccz - cd * 0.5),
		Vector3(cw * 0.5, 4.79, ccz + cd * 0.5), Vector3(-cw * 0.5, 4.79, ccz + cd * 0.5), Color("#e8e6df"), [], Vector3.DOWN)
	var islands := 2 if cw < 16.0 else 3
	for i in islands:
		var x := (i - (islands - 1) * 0.5) * cw / islands
		_box("concrete", Vector3(1.2, 0.2, 5.5), Vector3(x, 0.1, ccz), FOUNDATION)
		_box("paint", Vector3(0.4, 4.6, 0.4), Vector3(x, 2.5, ccz), Color("#d8d6cf"))
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.8, 1.6, 0.55), Vector3(x, 1.0, ccz + s * 1.5), Color("#e8e6df"))
			_box("paint", Vector3(0.82, 0.3, 0.57), Vector3(x, 1.65, ccz + s * 1.5), brand)
	# Price sign on a pole near the street.
	var px := -half + 1.5
	_box("paint", Vector3(0.3, 6.0, 0.3), Vector3(px, 3.0, 1.0), Color("#5a5e60"))
	_box("paint", Vector3(2.2, 1.4, 0.3), Vector3(px, 6.3, 1.0), brand)
	_box("paint", Vector3(2.0, 1.6, 0.32), Vector3(px, 4.7, 1.0), Color("#1d1d1d"))
	# Concrete under the canopy, asphalt round it, two curb cuts.
	_flat_rect("drive", -cw * 0.5 - 1.0, cw * 0.5 + 1.0, ccz - cd * 0.5 - 1.0, ccz + cd * 0.5 + 1.0, 0.09)
	_flat_rect("asphalt", -half + 0.6, half - 0.6, 0.0, zf, 0.06)
	for x in [-half * 0.55, half * 0.55]:
		_flat_rect("asphalt", x - 3.6, x + 3.6, -to_curb, 0.0, 0.1)
	_box("paint", Vector3(1.0, 2.1, 0.06), Vector3(sw * 0.3, 1.35, zf + sd + 0.03), Color("#5a5e60"))


## A diner or family restaurant: one storey, a long band of windows with a
## stainless or coloured band above and below, a big pole sign.
func _diner(to_curb: float) -> void:
	var w := minf(rng.randf_range(14.0, 18.0), half * 2.0 - 4.0)
	var d := 11.0
	var zf := rng.randf_range(13.0, 15.0)
	var cz := zf + d * 0.5
	var band := Color(_pick(["#c8102e", "#1f3b6e", "#2a7a6e", "#d8d6cf"]))
	var wall := Color(_pick(["#e9e6dc", "#d8d2c2", "#a8775c"]))
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_flat_roofed("paint", w, d, cz, 4.0, 4.6, wall)
	_box("metal", Vector3(w + 0.1, 0.45, 0.12), Vector3(0, 1.0, zf - 0.06), Color("#c9cbc8"))
	_box("paint", Vector3(w + 0.1, 0.55, 0.14), Vector3(0, 3.3, zf - 0.07), band)
	var n := int((w - 3.0) / 1.5)
	for i in n:
		_glass(Vector3(-w * 0.5 + 2.6 + i * 1.5, 2.15, zf - 0.03), Vector3(-1, 0, 0), 1.4, 1.6, 0.05)
	# Entry vestibule.
	_box("paint", Vector3(2.6, 3.0, 2.0), Vector3(-w * 0.5 + 1.0, 1.8, zf - 1.0), band)
	_glass(Vector3(-w * 0.5 + 1.0, 1.4, zf - 2.02), Vector3(-1, 0, 0), 1.6, 2.2, 0.0)
	# Pole sign.
	var px := half - 2.0
	_box("paint", Vector3(0.35, 7.5, 0.35), Vector3(px, 3.75, 1.5), Color("#5a5e60"))
	_sign(Vector3(px, 6.8, 1.3), 3.4, 1.6)
	_rooftop(w, d, cz, 4.0, 2)
	_shop_parking(to_curb, w, zf, 0.0)


## A small-town bank: brick, two storeys of tall windows, a stone portico
## with columns over the door, a drive-up lane with a canopy at the side.
func _bank(to_curb: float) -> void:
	var w := minf(rng.randf_range(12.0, 15.0), half * 2.0 - 8.0)
	var d := 14.0
	var zf := rng.randf_range(9.0, 11.0)
	var cz := zf + d * 0.5
	var brick := Color(_pick(FACADE_BRICK))
	var stone := Color("#d8d2c2")
	_box("paint", Vector3(w + 0.1, 0.6, d + 0.1), Vector3(0, 0.3, cz), stone)
	_box("brick", Vector3(w, 6.6, d), Vector3(0, 3.9, cz), brick)
	_hip_roof(0.0, cz, 7.2, w, d, 2.0, Color(_pick(ROOF)))
	_box("paint", Vector3(w + 0.2, 0.3, d + 0.2), Vector3(0, 7.1, cz), stone)
	for i in 4:
		var x := lerpf(-w * 0.5 + 1.6, w * 0.5 - 1.6, i / 3.0)
		if i == 1 or i == 2:
			continue
		for y in [2.3, 5.2]:
			_window(Vector3(x, y, zf), Vector3(-1, 0, 0), 1.2, 1.9, true, false, stone)
	# Portico: four columns, an entablature and a pediment.
	_stoop(0.0, zf, 6.0, 3.0, 0.6)
	for k in 4:
		_cylinder("paint", Vector3(-2.4 + k * 1.6, 0.6, zf - 2.5), 0.28, 5.4, stone, 10)
	_box("paint", Vector3(6.4, 0.8, 3.2), Vector3(0, 6.4, zf - 1.5), stone)
	_tri("paint", Vector3(-3.2, 6.8, zf - 3.1), Vector3(3.2, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), stone, [], Vector3.FORWARD)
	_quad("roof", Vector3(-3.3, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), Vector3(0, 8.0, zf), Vector3(-3.3, 6.8, zf), Color(ROOF[0]), [], Vector3(-1, 3, 0))
	_quad("roof", Vector3(3.3, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), Vector3(0, 8.0, zf), Vector3(3.3, 6.8, zf), Color(ROOF[0]), [], Vector3(1, 3, 0))
	_box("paint", Vector3(1.8, 2.8, 0.08), Vector3(0, 2.0, zf - 0.04), Color("#3a3530"))
	_sign(Vector3(0, 4.3, zf - 0.08), 4.0, 0.5)
	# Drive-up lane and canopy beside the building.
	var lx := w * 0.5 + 3.0
	_box("paint", Vector3(4.0, 0.6, 7.0), Vector3(lx, 4.3, cz), stone)
	for s in [-1.0, 1.0]:
		_box("brick", Vector3(0.5, 4.0, 0.5), Vector3(lx + 1.7, 2.0, cz + s * 3.0), brick)
	_box("metal", Vector3(0.8, 1.4, 0.8), Vector3(lx - 1.2, 0.7, cz), Color("#b9bcbc"))
	_flat_rect("asphalt", lx - 2.2, lx + 2.2, 0.0, depth - 1.0, 0.07)
	_shop_parking(to_curb, w, zf - 3.2, -3.0)


## A small brick church on the main street: a steep gable to the street,
## tall arched-looking windows down the sides, a square bell tower with a
## spire over the front doors.
func _church(to_curb: float) -> void:
	var w := minf(rng.randf_range(10.0, 12.0), half * 2.0 - 4.0)
	var d := rng.randf_range(20.0, minf(26.0, maxf(depth - 12.0, 20.0)))
	var zf := rng.randf_range(7.0, 9.0)
	var cz := zf + d * 0.5
	var white := rng.randf() < 0.35
	var wall := CLAPBOARD_WHITE if white else Color(_pick(FACADE_BRICK))
	var mat := "siding" if white else "brick"
	var roof := Color(_pick(ROOF))
	_box("paint", Vector3(w + 0.1, 0.8, d + 0.1), Vector3(0, 0.4, cz), FOUNDATION)
	_box(mat, Vector3(w, 6.2, d), Vector3(0, 3.9, cz), wall)
	_gable_roof(0.0, cz, 7.0, w, w * 0.5 * 1.1, d, false, roof, wall)
	for s in [-1.0, 1.0]:
		for i in 4:
			var z := zf + 4.0 + i * (d - 6.0) / 3.0
			_window(Vector3(s * w * 0.5, 3.8, z), Vector3(0, 0, s), 1.1, 3.2, false, false, TRIM)
	# Tower and spire, centred on the front.
	var tw := 3.6
	var tz := zf - tw * 0.5 + 0.5
	_box(mat, Vector3(tw, 11.0, tw), Vector3(0, 5.5 + 0.4, tz), wall)
	_box("paint", Vector3(tw + 0.3, 0.3, tw + 0.3), Vector3(0, 11.55, tz), TRIM)
	for k in 4:
		var dir := Vector3(sin(k * PI * 0.5), 0, -cos(k * PI * 0.5))
		_box("paint", Vector3(1.0, 1.6, 0.08), Vector3(0, 10.0, tz) + dir * (tw * 0.5 + 0.03), Color("#2a2a2c"), Basis(Vector3.UP, -k * PI * 0.5))
	var sh := rng.randf_range(7.0, 10.0)
	var b := 11.7
	var r := tw * 0.5
	var c := [Vector3(-r, b, tz - r), Vector3(r, b, tz - r), Vector3(r, b, tz + r), Vector3(-r, b, tz + r)]
	for k in 4:
		var p: Vector3 = c[k]
		var q: Vector3 = c[(k + 1) % 4]
		_tri("roof", p, q, Vector3(0, b + sh, tz), roof, [], (p + q) * 0.5 - Vector3(0, b, tz))
	_box("paint", Vector3(1.8, 3.0, 0.12), Vector3(0, 2.3, tz - tw * 0.5 - 0.02), Color("#5a2a1a"))
	_box("paint", Vector3(2.2, 0.2, 0.15), Vector3(0, 3.9, tz - tw * 0.5 - 0.07), TRIM)
	_stoop(0.0, tz - tw * 0.5, 4.0, 2.0, 0.8)
	_window(Vector3(0, 6.5, tz - tw * 0.5), Vector3(-1, 0, 0), 1.2, 1.6, false, false, TRIM)
	_flat_rect("drive", -1.5, 1.5, -0.3, tz - tw * 0.5 - 2.0, 0.06)
	if depth > zf + d + 6.0:
		_flat_rect("asphalt", -half + 0.6, half - 0.6, zf + d + 1.0, depth - 0.6, 0.06)
	for i in 2:
		var pick := TreeField.pick(rng, true)
		var p := Vector3((i * 2 - 1) * (half - 2.5), 0, rng.randf_range(2.0, zf))
		if _in_lot(p):
			trees.append([p, pick[0], pick[1], rng.randf_range(0.9, 1.15)])


func _rooftop(w: float, d: float, cz: float, h: float, n: int) -> void:
	for i in n:
		var p := Vector3(rng.randf_range(-w * 0.35, w * 0.35), h, cz + rng.randf_range(-d * 0.2, d * 0.3))
		_box("metal", Vector3(1.8, 1.1, 1.2), p + Vector3(0, 0.55, 0), Color("#b9bcbc"))
		_box("paint", Vector3(1.0, 0.08, 0.8), p + Vector3(0, 1.14, 0), Color("#3a3c3e"))


## Front parking: a walk along the building, striped stalls and a curb cut.
func _shop_parking(to_curb: float, w: float, zw: float, cut_x: float) -> void:
	_flat_rect("drive", -w * 0.5 - 0.5, w * 0.5 + 0.5, zw - 2.0, zw, 0.08)
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	_flat_rect("asphalt", lot0, lot1, 0.0, zw - 2.0, 0.06)
	_flat_rect("asphalt", cut_x - 3.6, cut_x + 3.6, -to_curb, 0.0, 0.1)
	if zw - 2.0 > 6.0:
		var x := lot0
		while x <= lot1 + 0.01:
			_flat_rect("line", x - 0.06, x + 0.06, zw - 2.0 - 5.5, zw - 2.0, 0.07, LINE)
			x += 2.75


# ---------------------------------------------------------------- factories

func _factory(to_curb: float) -> void:
	var w := rng.randf_range(minf(15.0, half * 2.0 - 2.0), clampf(half * 2.0 - 1.5, 8.0, 18.5 + clampf(half * 2.0 - 22.0, 0.0, 12.0)))
	var d := rng.randf_range(16.0, minf(21.0, maxf(depth - 14.0, 16.0)))
	var h := rng.randf_range(6.0, 8.0)
	var zf := rng.randf_range(8.0, 9.5)
	var cz := zf + d * 0.5
	var wall := Color(_pick(METAL_WALL))
	var band := Color(_pick(WAINSCOT))
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_box("metal", Vector3(w, h - 0.3, d), Vector3(0, 0.3 + (h - 0.3) * 0.5, cz), wall)
	_box("metal", Vector3(w + 0.04, 1.1, d + 0.04), Vector3(0, 0.85, cz), band)
	_metal_roof(0.0, cz, h, w, d, band if rng.randf() < 0.4 else wall.darkened(0.08))
	# Overhead doors on the front, a man door, and a concrete apron.
	var n := 1 if w < 16.5 else 2
	for i in n:
		var x := (i - (n - 1) * 0.5) * 5.0 + w * 0.12
		_box("siding", Vector3(3.7, 4.3, 0.08), Vector3(x, 0.3 + 2.15, zf - 0.03), Color(TRIM, 0.0))
		_box("paint", Vector3(3.9, 0.15, 0.1), Vector3(x, 0.3 + 4.37, zf - 0.05), band)
		_flat_rect("drive", x - 2.4, x + 2.4, zf - 6.0, zf, 0.08)
	# Front office: a small brick box with storefront windows.
	var ow := rng.randf_range(5.5, 7.0)
	var ox := -w * 0.5 + ow * 0.5
	var od := 5.0
	var brick := Color(_pick(FACADE_BRICK))
	_box("brick", Vector3(ow, 3.4, od), Vector3(ox, 1.7, zf - od * 0.5 + 0.01), brick)
	_box("paint", Vector3(ow + 0.15, 0.12, od + 0.15), Vector3(ox, 3.44, zf - od * 0.5), Color("#cfcbc2"))
	for i in 2:
		_glass(Vector3(ox - ow * 0.25 + i * ow * 0.5, 1.75, zf - od - 0.02), Vector3(-1, 0, 0), ow * 0.4, 1.5, 0.3)
	_box("paint", Vector3(1.0, 2.2, 0.06), Vector3(ox + ow * 0.5 + 0.9, 1.4, zf - 0.03), Color("#5a5e60"))
	_sign(Vector3(ox, 2.6, zf - od - 0.05), ow * 0.7, 0.55)
	# Silos or a stack out back.
	var extra := rng.randf()
	if extra < 0.35:
		for i in rng.randi_range(1, 3):
			_cylinder("metal", Vector3(w * 0.5 - 2.0 - i * 3.2, 0, zf + d + 2.2), 1.4, h + rng.randf_range(2.0, 5.0), Color("#c9cbc8"))
	elif extra < 0.6:
		_cylinder("brick", Vector3(w * 0.3, 0, cz + d * 0.3), 0.7, h + 7.0, brick, 10)
	for i in rng.randi_range(0, 3):
		var pick := TreeField.pick(rng)
		var p := Vector3(rng.randf_range(-half + 1.0, half - 1.0), 0, rng.randf_range(zf + d + 3.0, maxf(depth - 1.0, zf + d + 3.0)))
		if _in_lot(p):
			trees.append([p, pick[0], pick[1], rng.randf_range(0.8, 1.1)])
	# Parking along the front, gravel yard, the drive.
	_flat_rect("asphalt", -half + 0.6, -w * 0.5 + ow + 0.5, 0.0, zf - od - 0.5, 0.06)
	if depth > zf + d + 1.0:
		_flat_rect("gravel", -half + 0.4, half - 0.4, zf + d, depth - 0.5, 0.04, GRAVEL)
	_flat_rect("asphalt", w * 0.12 - 3.6, w * 0.12 + 3.6, -to_curb, zf - 6.0, 0.1)
	var x := -half + 0.6
	while x <= -w * 0.5 + ow + 0.51:
		_flat_rect("line", x - 0.06, x + 0.06, 0.0, 5.5, 0.07, LINE)
		x += 2.75


## Low-slope gable roof of ribbed metal, ridge along x.
func _metal_roof(cx: float, cz: float, base: float, w: float, d: float, col: Color) -> void:
	var rise := d * 0.5 / 12.0
	var hw := w * 0.5 + 0.25
	var hd := d * 0.5 + 0.3
	var drop := rise * 0.3 / (d * 0.5)
	var slope := Vector2(hd, rise + drop).length()
	for side in [-1.0, 1.0]:
		var e0 := Vector3(cx - hw, base - drop, cz + side * hd)
		var e1 := Vector3(cx + hw, base - drop, cz + side * hd)
		var r0 := Vector3(cx - hw, base + rise, cz)
		var r1 := Vector3(cx + hw, base + rise, cz)
		# Sheeting on purlins a hand above the ceiling, not in its plane.
		var up := Vector3(0, 0.1, 0)
		_quad("metal", e0 + up, e1 + up, r1 + up, r0 + up, col, [Vector2(-hw, 0), Vector2(hw, 0), Vector2(hw, slope), Vector2(-hw, slope)], Vector3.UP)
		_quad("paint", e0, e1, r1, r0, SOFFIT.darkened(0.3), [], Vector3.DOWN)
		_quad("metal", e0, e1, e1 + up, e0 + up, col.darkened(0.15), [], Vector3(0, 0, side))
	for end in [-1.0, 1.0]:
		var x: float = cx + end * w * 0.5
		_tri("metal", Vector3(x, base, cz - d * 0.5), Vector3(x, base, cz + d * 0.5), Vector3(x, base + rise, cz), col.lightened(0.1), [], Vector3(end, 0, 0))
		# Rake trim closing the gap at the gable ends.
		var xe: float = cx + end * hw
		for side in [-1.0, 1.0]:
			var e := Vector3(xe, base - drop, cz + side * hd)
			var r := Vector3(xe, base + rise, cz)
			_quad("metal", e, r, r + Vector3(0, 0.1, 0), e + Vector3(0, 0.1, 0), col.darkened(0.15), [], Vector3(end, 0, 0))


func _cylinder(mat: String, base: Vector3, r: float, h: float, col: Color, segs := 14) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var u0 := r * a0
		var u1 := r * a1
		_quad(mat, p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), col,
			[Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, h), Vector2(u0, h)], (p0 + p1) * 0.5 - base)
		_tri("paint", base + Vector3(0, h, 0), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), col.darkened(0.15), [], Vector3.UP)
