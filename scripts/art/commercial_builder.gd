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
## Small parts only the desktop draws; the browser keeps its triangle budget.
static var fine_parts := not OS.has_feature("web")

## The business's sign, from Families.sign_of ({text, style, panel, letter,
## since}); empty paints generic lettering. Every sign band then carries it.
var sign_spec := {}
## Lettering for SignText: [{pos, normal, text, height, width, color, style}].
var labels := []
## Where cars park and people go in, as the art lays it out (SiteLayout
## reads it from a dry run, so cars use the stalls that are painted):
## {"stalls": [[Vector2 centre, Vector2 nose]], "door": Vector2,
## "cut_x": float, "aisle_z": float, "main_street": bool}.
var site := {"stalls": [], "door": Vector2(0.0, 0.4), "cut_x": 0.0, "aisle_z": 0.0, "main_street": true}
## A shop's first stage (BuildingTypes "shop" level 0), which may be drawn
## as a corner store (CornerStore).
var small_store := false
## A shop's second stage (BuildingTypes "shop" level 1): a corner store
## stays one, built on.
var grow_shop := false


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
		"corner": CornerStore.draw(self, to_curb, float(lot.get("side", 0.0)), 0, not small_store)
		"main_street": _main_street(to_curb)
		"strip": _strip_center(to_curb)
		"center": _strip_center(to_curb, true)
		"community": _community_center(to_curb)
		"gas": _shop_gas_station(to_curb)
		"diner": _shop_diner(to_curb)
		"bank": _bank(to_curb)
		"church": _church(to_curb)
		_: _retail(to_curb)


## Which kind of shop fits this lot: strip centers need a wide lot, gas
## stations like corners, and main-street blocks the old part of town.
func _shop_kind(lot: Dictionary) -> String:
	# A corner store's second stage is the same store, built on.
	if (small_store or grow_shop) and CornerStore.wanted(self):
		return "corner"
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
	b._dress()
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
	site.door = Vector2(-sw * 0.5 + (door + 0.5) * sw / bays, zf)
	for i in bays:
		var x := -sw * 0.5 + (i + 0.5) * sw / bays
		var y := 1.55 if i == door else 1.8
		var gh := 2.6 if i == door else 2.1
		shopfront = fine_parts and i != door
		_glass(Vector3(x, y, zf - 0.03), Vector3(-1, 0, 0), sw / bays - 0.08, gh, 0.0 if i == door else rng.randf_range(0.0, 0.15))
		shopfront = false
		_box("paint", Vector3(0.08, 2.7, 0.12), Vector3(x - sw / bays * 0.5, 1.6, zf - 0.06), mull)
	_box("paint", Vector3(0.08, 2.7, 0.12), Vector3(sw * 0.5, 1.6, zf - 0.06), mull)
	_box("paint", Vector3(sw, 0.1, 0.14), Vector3(0, 2.92, zf - 0.07), mull)
	_box("paint", Vector3(sw, 0.5, 0.12), Vector3(0, 0.5, zf - 0.06), mull)
	_retail_front(0.0, w, sw, zf, h + 0.9, wall, mat)
	# Sign band above the storefront.
	_sign(Vector3(0, 3.35, zf - 0.08), sw * rng.randf_range(0.55, 0.85), 0.9)
	if rng.randf() < 0.5:
		_awning(0.0, sw + 0.4, zf, 3.0, Color(_pick(AWNING)))
	# Display windows down each side near the front, as a freestanding
	# store has where a side faces a street or its own lot (a blank side
	# reads as a warehouse).
	for side in [-1.0, 1.0]:
		for k in 2:
			var z := zf + 1.4 + k * 2.2
			if z > zf + d - 1.5:
				break
			_glass(Vector3(side * (w * 0.5 + 0.03), 1.8, z), Vector3(0, 0, -side), 1.7, 2.1, 0.1)
			_box("paint", Vector3(0.12, 0.1, 1.86), Vector3(side * (w * 0.5 + 0.06), 2.9, z), mull)
			_box("paint", Vector3(0.12, 0.5, 1.86), Vector3(side * (w * 0.5 + 0.06), 0.5, z), mull)
	# Rooftop units.
	for i in rng.randi_range(1, 3):
		var p := Vector3(rng.randf_range(-w * 0.3, w * 0.3), h, cz + rng.randf_range(-d * 0.2, d * 0.3))
		_box("metal", Vector3(1.8, 1.1, 1.2), p + Vector3(0, 0.55, 0), Color("#b9bcbc"))
		_box("paint", Vector3(1.0, 0.08, 0.8), p + Vector3(0, 1.14, 0), Color("#3a3c3e"))
	# Back service door.
	_steel_door(Vector3(w * 0.3, 1.35, zf + d + 0.03), 1.0)
	# Parking: a walk along the front, a row of stalls, the aisle and the curb cut.
	_flat_rect("drive", -w * 0.5 - 0.5, w * 0.5 + 0.5, zf - 2.2, zf, 0.08)
	if fine_parts:
		_store_walk(w, zf, -sw * 0.5 + (door + 0.5) * sw / bays, half - 0.6)
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	_flat_rect("asphalt", lot0, lot1, 0.0, zf - 2.2, 0.06)
	_curb_cut(0.0, 3.6, -to_curb, 0.0)
	var stall := 2.75  # 9 ft
	var x := lot0
	while x <= lot1 + 0.01:
		_flat_rect("line", x - 0.06, x + 0.06, zf - 2.2 - 5.5, zf - 2.2, 0.07, LINE)
		x += stall
	_site_row(lot0, lot1, zf - 2.2, 0.0)
	if rng.randf() < 0.6:
		var pick := TreeField.pick(rng)
		var tx := lot0 + 0.8 if rng.randf() < 0.5 else lot1 - 0.8
		trees.append([Vector3(tx, 0, -to_curb + 1.2), pick[0], pick[1], rng.randf_range(0.7, 1.0)])
	# A light pole near the street, always on the same side of the lot, so
	# two shops side by side never stand their poles a metre apart on the
	# line between them: lot lights run about one per 25-30 m, three to four
	# mounting heights apart (IES RP-20 parking lot spacing).
	rng.randf()  # once the pole's side; kept so the rest of the lot stays as it was
	var lx := lot1 - 0.5
	_box("paint", Vector3(0.6, 0.5, 0.6), Vector3(lx, 0.25, 0.8), FOUNDATION)
	_box("paint", Vector3(0.16, 7.5, 0.16), Vector3(lx, 4.0, 0.8), Color("#3a3c3e"))
	_box("paint", Vector3(0.5, 0.18, 0.9), Vector3(lx, 7.7, 0.8 + 0.3), Color("#3a3c3e"))
	if not small_store:
		_rt_grown(w, d, h, zf, site.door.x, sw)


## A freestanding store grown into its second stage (BuildingTypes "shop"
## level 1, "Retail store"): the same store with a stockroom built on the
## back in painted split-face block, a little lower than the store, with
## its own roll-up door, and the front walk dressed as a busy small-town
## store's is (an ice chest, a propane exchange cage, pallets of bagged
## salt or mulch), as Indiana's dollar and hardware stores add on and
## spill out front once trade picks up. Its own dice, so the first stage
## draws as it did.
func _rt_grown(w: float, d: float, h: float, zf: float, door_x: float, sw: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "retail grown"])
	var back := zf + d
	var ad := minf(r.randf_range(6.0, 9.0), depth - back - 5.0)
	if ad >= 3.5:
		var aw := w - r.randf_range(0.0, 2.0)
		var ax := (w - aw) * 0.5 * (1.0 if r.randf() < 0.5 else -1.0)
		var ah := h - r.randf_range(0.4, 0.9)
		var block := Color(BLOCK[r.randi() % BLOCK.size()])
		var cz := back + ad * 0.5
		_box("paint", Vector3(aw + 0.1, 0.3, ad), Vector3(ax, 0.15, cz), FOUNDATION)
		_box("paint", Vector3(aw, ah, ad), Vector3(ax, ah * 0.5, cz), block)
		# Split-face courses read as fine bands up the block wall.
		for k in int(ah / 0.6):
			_box("paint", Vector3(aw + 0.04, 0.04, ad + 0.04), Vector3(ax, 0.6 * (k + 1), cz), block.darkened(0.08))
		var y := ah + 0.02
		_quad("membrane", Vector3(ax - aw * 0.5, y, back), Vector3(ax + aw * 0.5, y, back),
			Vector3(ax + aw * 0.5, y, back + ad), Vector3(ax - aw * 0.5, y, back + ad), Color("#d9d8d2"), [], Vector3.UP)
		_box("paint", Vector3(aw + 0.1, 0.3, 0.25), Vector3(ax, ah + 0.15, back + ad - 0.1), Color("#6e6a63"))
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.25, 0.3, ad), Vector3(ax + s * (aw * 0.5 - 0.1), ah + 0.15, cz), Color("#6e6a63"))
		# A roll-up door for deliveries and a man door beside it.
		var rx := ax + r.randf_range(-aw * 0.2, aw * 0.2)
		_box("metal", Vector3(3.0, 3.0, 0.08), Vector3(rx, 1.5, back + ad + 0.04), Color("#c9c9c4"))
		for k in 10:
			_box("paint", Vector3(3.0, 0.03, 0.1), Vector3(rx, 0.3 * (k + 0.5), back + ad + 0.06), Color("#a9a9a4"))
		_box("paint", Vector3(3.3, 0.35, 0.3), Vector3(rx, 3.2, back + ad + 0.15), Color("#5a5e60"))
		var mx := rx + (2.6 if rx < ax else -2.6)
		if absf(mx - ax) < aw * 0.5 - 0.8:
			_steel_door(Vector3(mx, 1.35, back + ad + 0.03), 1.0)
		_flat_rect("asphalt", rx - 2.0, rx + 2.0, back + ad, minf(back + ad + 6.0, depth - 0.5), 0.07)
	# Out front: an ice chest and a propane cage one side of the door,
	# pallets of bags the other, on the walk against the glass.
	var walk_z := zf - 0.75
	var left := door_x - 1.8
	var right := door_x + 1.8
	var edge := sw * 0.5
	if left - 1.6 > -edge:
		_box("paint", Vector3(1.55, 1.25, 0.8), Vector3(left - 0.8, 0.63, walk_z), Color("#f2f4f5"))
		_box("paint", Vector3(1.4, 0.35, 0.02), Vector3(left - 0.8, 0.9, walk_z - 0.41), Color("#2a6db5"))
		if left - 3.2 > -edge:
			var cx := left - 2.5
			_box("paint", Vector3(1.2, 1.5, 0.7), Vector3(cx, 0.75, walk_z), Color("#c2c5c6"))
			for k in 3:
				_cylinder("metal", Vector3(cx - 0.38 + k * 0.38, 0.05, walk_z - 0.05), 0.15, 0.55, Color("#e9ecee"))
				_cylinder("metal", Vector3(cx - 0.38 + k * 0.38, 0.75, walk_z - 0.05), 0.15, 0.55, Color("#e9ecee"))
	if right + 1.4 < edge:
		var bag := Color(["#7a5a3a", "#3b6e3a", "#d8d4c8"][r.randi() % 3])
		for k in mini(2, int((edge - right) / 1.3)):
			var px := right + 0.65 + k * 1.3
			_box("paint", Vector3(1.1, 0.14, 1.1), Vector3(px, 0.07, walk_z), Color("#a88a5e"))
			var bh := r.randf_range(0.5, 0.9)
			_box("paint", Vector3(1.05, bh, 1.0), Vector3(px, 0.14 + bh * 0.5, walk_z), bag)


## A one-storey wing on the back of a grown shop (the diner's party room,
## the bank's loan offices): as wide as the building or a little less, set
## to one side, windows down its sides, a flat roof behind a band in the
## shop's own colour or a low hip roof. Its own dice.
func _rt_wing(w: float, back: float, h: float, wall: Color, mat: String, band: Color, hip: bool) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "shop wing"])
	var ad := minf(r.randf_range(6.0, 9.0), depth - back - 4.0)
	if ad < 3.5:
		return
	var aw := w - r.randf_range(0.0, 2.5)
	var ax := (w - aw) * 0.5 * (1.0 if r.randf() < 0.5 else -1.0)
	var cz := back + ad * 0.5
	_box("paint", Vector3(aw + 0.1, 0.3, ad), Vector3(ax, 0.15, cz), FOUNDATION)
	_box(mat, Vector3(aw, h, ad), Vector3(ax, h * 0.5, cz), wall)
	if hip:
		_hip_roof(ax, cz, h, aw, ad, minf(aw, ad) * 0.18, Color(ROOF[r.randi() % ROOF.size()]))
		_box("paint", Vector3(aw + 0.2, 0.25, ad + 0.2), Vector3(ax, h - 0.1, cz), band)
	else:
		var y := h + 0.02
		_quad("membrane", Vector3(ax - aw * 0.5, y, back), Vector3(ax + aw * 0.5, y, back),
			Vector3(ax + aw * 0.5, y, back + ad), Vector3(ax - aw * 0.5, y, back + ad), Color("#d9d8d2"), [], Vector3.UP)
		_box("paint", Vector3(aw + 0.1, 0.5, 0.14), Vector3(ax, h + 0.05, back + ad), band)
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.14, 0.5, ad), Vector3(ax + sx * aw * 0.5, h + 0.05, cz), band)
	# Windows down both sides, and a door out the back.
	var n := int((ad - 1.5) / 2.2)
	for sx in [-1.0, 1.0]:
		for k in n:
			_window(Vector3(ax + sx * aw * 0.5, 1.8, back + 1.4 + k * 2.2), Vector3(0, 0, -sx), 1.1, 1.5, true, false, Color("#e9e6dc"))
	_steel_door(Vector3(ax + aw * 0.25, 1.35, back + ad + 0.03), 1.0)
	_box("concrete", Vector3(1.8, 0.15, 1.4), Vector3(ax + aw * 0.25, 0.08, back + ad + 0.7), FOUNDATION)


## A gas station grown into its second stage: an in-bay automatic car
## wash built on beside the store where the lot is wide enough (most
## Indiana stations that add one do it there, entering from the
## forecourt and leaving out the back), and an air and vacuum stand at
## the lot's edge. Its own dice.
func _rt_gas_grown(sw: float, sd: float, zf: float, cw: float, canopy_z: float, wall: Color, brand: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "gas grown"])
	var side := 1.0 if r.randf() < 0.5 else -1.0
	var bw := 6.0
	var room := half - 0.8 - maxf(sw * 0.5, cw * 0.5)
	if room >= bw + 0.6:
		var bx := side * (maxf(sw * 0.5, cw * 0.5) + 0.6 + bw * 0.5)
		var bd := minf(13.0, depth - 1.5 - (zf - 3.0))
		var z0 := zf + sd - bd
		var cz := z0 + bd * 0.5
		var h := 4.6
		_box("paint", Vector3(bw + 0.1, 0.3, bd + 0.1), Vector3(bx, 0.15, cz), FOUNDATION)
		# Two block walls with the brand band along the top; open at both
		# ends behind tall glass overhead doors.
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, h, bd), Vector3(bx + s * (bw * 0.5 - 0.15), h * 0.5, cz), wall)
		_box("paint", Vector3(bw, 0.6, bd), Vector3(bx, h - 0.3, cz), wall)
		# Its walls are thin, so the bay's footprint is noted by hand.
		_masses.append(Rect2(bx - bw * 0.5, z0, bw, bd))
		_mass_back_z = maxf(_mass_back_z, z0 + bd)
		_box("paint", Vector3(bw + 0.1, 0.6, bd + 0.1), Vector3(bx, h + 0.1, cz), brand)
		var y := h + 0.42
		_quad("membrane", Vector3(bx - bw * 0.5, y, z0), Vector3(bx + bw * 0.5, y, z0),
			Vector3(bx + bw * 0.5, y, z0 + bd), Vector3(bx - bw * 0.5, y, z0 + bd), Color("#d9d8d2"), [], Vector3.UP)
		for ez in [z0, z0 + bd]:
			_glass(Vector3(bx, 2.0, ez - 0.03 if ez == z0 else ez + 0.03), Vector3(-1, 0, 0), bw - 0.8, 3.6, 0.1)
			for k in 4:
				_box("paint", Vector3(bw - 0.7, 0.06, 0.08), Vector3(bx, 0.4 + k * 0.95, ez), Color("#d8dadb"))
		# The wash gantry and brushes seen through the glass.
		_box("metal", Vector3(bw - 1.0, 0.3, 0.6), Vector3(bx, 3.6, cz), Color("#8d9093"))
		for s in [-1.0, 1.0]:
			_cylinder("paint", Vector3(bx + s * (bw * 0.5 - 1.0), 0.3, cz + 1.5), 0.45, 2.6, Color("#2a6db5"), 10)
		_flat_rect("drive", bx - bw * 0.5, bx + bw * 0.5, z0 - 6.0, z0, 0.085)
		_flat_rect("asphalt", bx - bw * 0.5, bx + bw * 0.5, z0 + bd, minf(z0 + bd + 4.0, depth - 0.5), 0.07)
		# The pay station at the bay's entrance.
		_box("paint", Vector3(0.6, 1.5, 0.5), Vector3(bx - side * (bw * 0.5 - 0.4), 0.95, z0 - 4.5), Color("#3a3c3e"))
		_box("paint", Vector3(0.5, 0.3, 0.02), Vector3(bx - side * (bw * 0.5 - 0.4), 1.3, z0 - 4.76), brand)
	# Air and vacuum: a post with a coiled hose and a vacuum can with its
	# boom, at the edge of the forecourt opposite the wash.
	var vx := -side * (half - 1.2)
	var vz := clampf(canopy_z - 2.0, 3.0, zf - 1.0)
	_box("concrete", Vector3(1.4, 0.15, 2.6), Vector3(vx, 0.08, vz), FOUNDATION)
	_box("paint", Vector3(0.5, 1.3, 0.4), Vector3(vx, 0.8, vz - 0.7), Color("#c8102e"))
	_box("paint", Vector3(0.45, 0.45, 0.02), Vector3(vx, 1.15, vz - 0.91), Color("#f2f4f5"))
	_cylinder("metal", Vector3(vx, 0.15, vz + 0.6), 0.35, 1.2, Color("#d9dcdd"), 10)
	_box("paint", Vector3(0.08, 2.4, 0.08), Vector3(vx, 1.35, vz + 0.6), Color("#5a5e60"))
	_box("paint", Vector3(1.2, 0.06, 0.06), Vector3(vx + side * 0.6, 2.55, vz + 0.6), Color("#5a5e60"))


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
		shopfront = fine_parts
		_glass(Vector3(x, 1.85, zf - 0.03), Vector3(-1, 0, 0), sw / bays - 0.12, 2.3, rng.randf_range(0.0, 0.2))
		shopfront = false
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


## A freestanding store's front (1990s-2010s retail in Marion and Kokomo):
## a split-face block wainscot either side of the storefront and a raised
## false front with a cornice over the entrance.
## The walk in front of a freestanding store (Dollar General, Rural King,
## any IGA in Grant County): the curb painted yellow for the fire lane,
## yellow-painted steel pipe bollards either side of the door against
## cars, a trash can by the door, an ice merchandiser or a propane
## exchange cage against the wall, and a cart corral out in the lot.
## Desktop only, with its own random numbers so the builder's don't move.
func _store_walk(w: float, zf: float, dx: float, lot1: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 6203])
	var yellow := Color("#d9b82a")
	_flat_rect("line", -w * 0.5 - 0.5, w * 0.5 + 0.5, zf - 2.2, zf - 2.05, 0.085, yellow)
	for s in [-1.0, 1.0]:
		var bx: float = dx + s * 1.3
		_box("paint", Vector3(0.17, 1.0, 0.17), Vector3(bx, 0.5, zf - 1.75), yellow)
		_box("paint", Vector3(0.17, 0.06, 0.17), Vector3(bx, 1.03, zf - 1.75), yellow.darkened(0.1))
	var out := 1.0 if dx > 0.0 else -1.0
	_box("paint", Vector3(0.55, 0.9, 0.55), Vector3(dx - out * 1.9, 0.53, zf - 1.0), Color("#3a3c3e"))  # trash can
	var ex := dx - out * 3.2
	if absf(ex) < w * 0.5 - 1.0:
		if r.randf() < 0.5:
			# Ice merchandiser: a white chest with the blue band.
			_box("metal", Vector3(1.6, 1.7, 0.8), Vector3(ex, 0.93, zf - 0.6), Color("#eef0f0"))
			_box("paint", Vector3(1.62, 0.3, 0.02), Vector3(ex, 1.3, zf - 1.01), Color("#2a5ea8"))
		else:
			# Propane exchange: a steel mesh cage with the tanks inside.
			_box("metal", Vector3(1.4, 1.8, 0.75), Vector3(ex, 0.98, zf - 0.6), Color("#b9bcbc"))
			for t in 3:
				_box("paint", Vector3(0.3, 0.45, 0.3), Vector3(ex - 0.4 + t * 0.4, 0.4, zf - 0.96), Color("#e8e8e4"))
	# A row of nested carts along the wall the other side of the door
	# (kept off the stalls, which the town's parking counts).
	if r.randf() < 0.7:
		var side := out
		var steel := Color("#a9adb0")
		var n := r.randi_range(3, 7)
		var x0 := dx + side * 2.0
		if absf(x0 + side * n * 0.3) < w * 0.5 - 0.5:
			for k in n:
				var x := x0 + side * k * 0.3
				_box("metal", Vector3(0.85 - k * 0.006, 0.55 - k * 0.006, 0.55 - k * 0.006), Vector3(x, 0.6 + (k % 3) * 0.02, zf - 0.8 - (k % 3) * 0.02), steel.darkened(0.1 + 0.02 * (k % 2)))
				_box("paint", Vector3(0.04, 0.04, 0.6 - k * 0.006), Vector3(x + side * 0.12, 1.0 + (k % 3) * 0.02, zf - 0.8 - (k % 3) * 0.02), Color("#c23a2a"))  # handle


func _retail_front(cx: float, w: float, sw: float, zf: float, top: float, wall: Color, mat: String) -> void:
	var base := Color(["#8b8478", "#a39a8a", "#6f6a62"][absi(hash([rng.seed, 9])) % 3])
	var side := (w - sw) * 0.5 - 0.1
	if side > 0.3:
		for sgn in [-1.0, 1.0]:
			_box("concrete", Vector3(side, 0.9, 0.06), Vector3(cx + sgn * (sw * 0.5 + 0.1 + side * 0.5), 0.75, zf - 0.03), base)
	_raised_front(cx, minf(sw * 0.55, 8.0), zf, top, wall, mat)


## A raised parapet front over an entrance: a wall panel standing above the
## roof line, slightly proud of the wall, with a projecting cornice cap.
func _raised_front(cx: float, fw: float, zf: float, top: float, wall: Color, mat: String) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, snappedf(cx, 0.01), 5])
	var rise := r.randf_range(1.0, 1.8)
	var cap := Color(["#e7e1d2", "#d6cdb8", "#cfcbc2", "#4b4239"][r.randi() % 4])
	_box(mat, Vector3(fw, rise + 0.6, 0.5), Vector3(cx, top + rise * 0.5 - 0.3, zf - 0.2), wall.lightened(0.04))
	_box("paint", Vector3(fw + 0.4, 0.3, 0.8), Vector3(cx, top + rise + 0.1, zf - 0.25), cap)
	_box("paint", Vector3(fw + 0.1, 0.18, 0.6), Vector3(cx, top - 0.35, zf - 0.25), cap)


## A flat-roofed box: walls up to the roof deck, a pale membrane roof, and a
## parapet with coping around it.
func _flat_roofed(mat: String, w: float, d: float, cz: float, deck: float, top: float, wall: Color) -> void:
	_box(mat, Vector3(w, deck, d), Vector3(0, deck * 0.5, cz), wall)
	var y := deck + 0.02
	_quad("membrane", Vector3(-w * 0.5, y, cz - d * 0.5), Vector3(w * 0.5, y, cz - d * 0.5),
		Vector3(w * 0.5, y, cz + d * 0.5), Vector3(-w * 0.5, y, cz + d * 0.5), _low_slope(w, d, cz, mat == "brick"), [], Vector3.UP)
	_roof_bits(0.0, w, d, cz, y, mat == "brick")
	var ph := top - deck
	var t := 0.25
	_box(mat, Vector3(w, ph, t), Vector3(0, deck + ph * 0.5, cz - d * 0.5 + t * 0.5), wall)
	_box(mat, Vector3(w, ph, t), Vector3(0, deck + ph * 0.5, cz + d * 0.5 - t * 0.5), wall)
	_box(mat, Vector3(t, ph, d), Vector3(-w * 0.5 + t * 0.5, deck + ph * 0.5, cz), wall)
	_box(mat, Vector3(t, ph, d), Vector3(w * 0.5 - t * 0.5, deck + ph * 0.5, cz), wall)
	_coping(w, d, cz, top, mat == "brick")


## Paves the lot behind the building, the way a shop's alley side or a
## plant's yard is: asphalt behind newer shops, gravel behind older ones
## and factories, with a front-load dumpster (2 yd, 6 ft wide) by the back
## door of a shop. A shop's lot is paved only as far as it uses it: a row of
## 90-degree stalls and its aisle (5.5 + 6.7 m) and the dumpster pad, about
## 15 m back and a few metres either side of the building, with lawn
## beyond; a plant's yard (`reach` INF) runs out to the lot lines. Runs
## last, so its random draws move nothing else.
func _service_yard(gravel: bool, dumpster := true, reach := 15.0) -> void:
	var pts := outline
	if pts.size() < 3:
		pts = PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(half, depth), Vector2(-half, depth)])
	var z0 := _mass_back_z + 0.4
	if depth - z0 < 2.0:
		return
	var z1 := minf(depth + 1.0, z0 + reach)
	var x0 := -1000.0
	var x1 := 1000.0
	if reach < INF:
		x0 = INF
		x1 = -INF
		for r: Rect2 in _masses:
			x0 = minf(x0, r.position.x - 3.0)
			x1 = maxf(x1, r.end.x + 3.0)
		if x0 > x1:
			return
	var back := PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	var col := Color("#8d877c") if gravel else Color("#4a4a48")
	for poly in Geometry2D.intersect_polygons(pts, back):
		_flat_ground("gravel" if gravel else "asphalt", poly, 0.05, col)  # 1 cm under any parking already drawn
	if dumpster and depth - z0 > 3.0:
		var at := Vector3(rng.randf_range(-half * 0.5, half * 0.5), 0, z0 + 1.2)
		if _in_lot(at, 1.5):
			var bin := Color(_pick(["#2f4a3a", "#2a3a5a", "#4a4e52"]))
			_box("metal", Vector3(1.83, 1.07, 1.07), at + Vector3(0, 0.6, 0), bin)
			_box("paint", Vector3(1.87, 0.06, 1.12), at + Vector3(0, 1.16, 0), Color("#1c1d1f"))


## Flat ground work over a polygon (x, z), as _flat_rect does for a rectangle.
func _flat_ground(kind: String, poly: PackedVector2Array, y: float, col: Color) -> void:
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var tri := [poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]
		# Wound clockwise seen from above, like _flat_rect.
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]) < 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for q in tri:
			_flat.set_normal(Vector3.UP)
			_flat.set_color(col)
			_flat.set_uv(q * 0.25)
			_flat.add_vertex(Vector3(q.x, y, q.y))


## What a flat roof is covered with, picked from the building's seed and
## size so it doesn't move the builder's random sequence. Aerials of Indiana
## Main Street blocks: old masonry blocks are mostly dark (black EPDM,
## modified bitumen, tar and gravel) with some silver-coated and white
## re-roofs; newer strip centres and boxes are mostly white TPO.
func _low_slope(w: float, d: float, cz: float, old := false) -> Color:
	var k := absi(hash([rng.seed, snappedf(w, 0.01), snappedf(d, 0.01), snappedf(cz, 0.01)])) % 20
	if old:
		if k < 6:
			return Color("#3e3e3c")  # modified bitumen
		if k < 10:
			return Color("#4a4a47")  # black EPDM
		if k < 14:
			return Color("#7d786f", 0.5)  # tar and gravel
		if k < 17:
			return Color("#9a9b99")  # aluminium roof coating
		return Color("#b1afa8")
	if k < 10:
		return Color("#b1afa8")
	if k < 13:
		return Color("#8f8e89")
	if k < 17:
		return Color("#4a4a47")
	return Color("#8a847a", 0.5)


## The cap on a parapet: limestone or terra cotta on old brick, prefinished
## metal (bronze, grey or white) on newer walls.
func _coping_color(old: bool) -> Color:
	var k := absi(hash([rng.seed, 7])) % 6
	if old:
		return [Color("#b9b09f"), Color("#a89f8c"), Color("#9c6a4e"), Color("#5a4a3c"), Color("#8e8c86"), Color("#b9b09f")][k]
	return [Color("#cfcbc2"), Color("#4b4239"), Color("#8e8c86"), Color("#cfcbc2"), Color("#d9d6cd"), Color("#4b4239")][k]


## A flat roof's own clutter (Main Street aerials): a roof hatch, plumbing
## vent stacks, a drain scupper's dark stain and, on older blocks, a brick
## chimney at the back. Its own random numbers, so the builder's don't move.
func _roof_bits(cx: float, w: float, d: float, cz: float, y: float, old: bool, services := true) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, snappedf(cx, 0.01), snappedf(cz, 0.01), 3])
	var span := Vector2(maxf(w * 0.5 - 1.2, 0.3), maxf(d * 0.5 - 1.2, 0.3))
	if w * d > 60.0:
		var hp := Vector3(cx + r.randf_range(-span.x, span.x), y, cz + r.randf_range(-span.y, span.y))
		_box("metal", Vector3(0.95, 0.45, 0.95), hp + Vector3(0, 0.22, 0), Color("#8d8f8e"))
	for i in r.randi_range(1, 3):
		var vp := Vector3(cx + r.randf_range(-span.x, span.x), y, cz + r.randf_range(-span.y, span.y))
		_box("paint", Vector3(0.12, 0.45, 0.12), vp + Vector3(0, 0.22, 0), Color("#2e2e2e"))
	if old and d > 8.0 and r.randf() < 0.6:
		var cxp := cx + r.randf_range(-span.x, span.x)
		_box("brick", Vector3(0.9, 1.6, 0.6), Vector3(cxp, y + 0.8, cz + d * 0.5 - 0.6), Color("#8a4b36"))
		_box("paint", Vector3(1.0, 0.08, 0.7), Vector3(cxp, y + 1.64, cz + d * 0.5 - 0.6), Color("#6f6a62"))
	if fine_parts and services and w * d > 120.0:
		_roof_services(r, cx, w, d, cz, y, span)


## Desktop: what a commercial flat roof really carries, seen from above.
## Packaged rooftop units sized to the floor area (about one per 120 m2,
## as a shop or office needs roughly a ton of cooling per 30 m2), each fed
## by yellow-painted gas pipe on rubber blocks from the back parapet, with
## a walkway pad of pavers to it; cast-iron roof drains, and on a big roof
## domed skylights in rows.
func _roof_services(r: RandomNumberGenerator, cx: float, w: float, d: float, cz: float, y: float, span: Vector2) -> void:
	var units := clampi(int(w * d / 120.0), 1, 8)
	var gas := Color("#e3bd2a")
	var back := cz + d * 0.5 - 0.7
	var main_x := cx + r.randf_range(-span.x, span.x) * 0.8
	# The main gas line along the back, on blocks every 2.5 m.
	var placed: Array[Vector3] = []
	for i in units:
		var p := Vector3(cx + r.randf_range(-span.x, span.x) * 0.85, y, cz + r.randf_range(-span.y, span.y) * 0.7)
		var clash := false
		for q in placed:
			if absf(q.x - p.x) < 3.0 and absf(q.z - p.z) < 2.4:
				clash = true
		if clash:
			continue
		placed.append(p)
		var big := r.randf() < 0.4
		var sz := Vector3(2.6, 1.3, 1.5) if big else Vector3(2.0, 1.1, 1.25)
		_box("concrete", Vector3(sz.x + 0.3, 0.2, sz.z + 0.3), p + Vector3(0, 0.1, 0), Color("#9a9790"))  # curb
		_box("metal", sz, p + Vector3(0, 0.2 + sz.y * 0.5 + 0.01, 0), Color("#c4c6c4"))
		var fans := 2 if big else 1
		for f in fans:
			var fx := p.x + (f - (fans - 1) * 0.5) * sz.x * 0.45
			_box("paint", Vector3(0.75, 0.04, 0.75), Vector3(fx, y + 0.2 + sz.y + 0.03, p.z + sz.z * 0.15), Color("#2f3132"))
		# Its gas drop: up from the line, across, down into the unit.
		var gz := back - 0.3 * i
		# (It runs 5 cm into the cabinet, so no end face lies on the cabinet's.)
		_box("paint", Vector3(0.06, 0.06, absf(gz - p.z) - sz.z * 0.5 + 0.05), Vector3(p.x + sz.x * 0.35, y + 0.28, (gz + p.z + sz.z * 0.5 - 0.05) * 0.5), gas)
		_box("paint", Vector3(absf(p.x + sz.x * 0.35 - main_x) + 0.06, 0.06, 0.06), Vector3((p.x + sz.x * 0.35 + main_x) * 0.5, y + 0.28, gz), gas)
		var k := minf(main_x, p.x + sz.x * 0.35)
		while k < maxf(main_x, p.x + sz.x * 0.35):
			_box("paint", Vector3(0.2, 0.22, 0.2), Vector3(k, y + 0.11, gz), Color("#3a3a3a"))
			k += 2.5
		# Walk pads (concrete pavers) from the hatch side to the unit.
		var wz := p.z - sz.z * 0.5 - 0.8
		_box("paint", Vector3(0.6, 0.04, 0.6), Vector3(p.x - 0.5, y + 0.02, wz), Color("#b3b0a8"))
		_box("paint", Vector3(0.6, 0.04, 0.6), Vector3(p.x + 0.3, y + 0.02, wz - 0.03), Color("#aeaba3"))
	# Gas meter riser where the line comes up the back wall.
	_box("paint", Vector3(0.08, 0.6, 0.08), Vector3(main_x, y + 0.3, back), gas)
	# Roof drains in the low spots, with their strainer domes.
	for i in clampi(int(w * d / 200.0), 1, 4):
		var dp := Vector3(cx + r.randf_range(-span.x, span.x) * 0.6, y, cz + r.randf_range(-span.y, span.y) * 0.6)
		_box("paint", Vector3(0.45, 0.03, 0.45), dp + Vector3(0, 0.015, 0), Color("#4a4846"))
		_box("paint", Vector3(0.2, 0.1, 0.2), dp + Vector3(0, 0.05, 0), Color("#2a2a2a"))
	# Domed acrylic skylights over a big sales floor.
	if w * d > 700.0 and r.randf() < 0.7:
		var cols := maxi(2, int(w / 9.0))
		var rows := maxi(1, int(d / 12.0))
		for i in cols:
			for j in rows:
				var sx := cx - span.x * 0.7 + (i + 0.5) * span.x * 1.4 / cols
				var sz2 := cz - span.y * 0.5 + (j + 0.5) * span.y / rows
				_box("paint", Vector3(1.4, 0.3, 1.4), Vector3(sx, y + 0.15, sz2), Color("#d9d6cf"))
				_box("paint", Vector3(1.1, 0.16, 1.1), Vector3(sx, y + 0.38, sz2), Color("#e9eef2"))


func _coping(w: float, d: float, cz: float, top: float, old := false) -> void:
	var col := _coping_color(old)
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(0, top, cz - d * 0.5), col)
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(0, top, cz + d * 0.5), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(-w * 0.5, top, cz), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(w * 0.5, top, cz), col)


func _sign(c: Vector3, w: float, h: float) -> void:
	var col := Color(_pick(SIGNS))
	col.a = minf(w / 60.0, 0.49)
	if not sign_spec.is_empty():
		# The business's own name in its family's colours; alpha 0 tells the
		# sign shader there's real lettering, so it paints no stand-in.
		col = sign_spec.panel
		col.a = 0.0
		labels.append_array(SignText.on_panel(sign_spec, c + Vector3(0, 0, -0.01), w, h, Vector3.FORWARD, true))
	var r := Vector3(-w * 0.5, 0, 0)
	var u := Vector3(0, h, 0)
	# Faces the street (-z); x runs right to left as seen from the street.
	_quad("sign", c + r, c - r, c - r + u, c + r + u, col,
		[Vector2(0, 0), Vector2(w, 0), Vector2(w, 1), Vector2(0, 1)], Vector3.FORWARD)
	_box("paint", Vector3(w + 0.1, h + 0.1, 0.06), c + Vector3(0, h * 0.5, 0.04), col.darkened(0.3))


## Desktop: a strip tenant's name in channel letters, the way strip-centre
## leases require them: separate lit letters about 13 cm deep on a raceway
## along the fascia, red most often, then white, blue or green; they glow
## after dark (sign alpha 1). Takes the same one draw from rng as _sign.
func _channel_letters(c: Vector3, w: float, h: float) -> void:
	_pick(SIGNS)  # the same one draw as _sign
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 37, snappedf(c.x, 0.1)])
	var tints := [Color("#e0262e"), Color("#e0262e"), Color("#f4f1ea"), Color("#1f5fbf"), Color("#1f8a4a"), Color("#f2b632")]
	var col: Color = tints[r.randi() % tints.size()]
	col.a = 1.0
	var lh := h * r.randf_range(0.7, 0.95)
	var lw := lh * 0.62
	var gap := lh * 0.14
	var n := maxi(3, int(w / (lw + gap)))
	var x0 := c.x - (n * (lw + gap) - gap) * 0.5
	var y0 := c.y + (h - lh) * 0.5
	var z := c.z - 0.08
	# The raceway the letters hang on, painted to match the fascia.
	_box("paint", Vector3(n * (lw + gap), 0.12, 0.1), Vector3(c.x, y0 + lh * 0.45, c.z - 0.03), Color("#5b5d5f"))
	var t := lh * 0.18
	for i in n:
		if r.randf() < 0.1 and i > 0 and i < n - 1:
			continue  # a space between words
		var lx := x0 + i * (lw + gap) + lw * 0.5
		# A block letter from a few strokes: stems, then bars across.
		var stems := r.randi_range(1, 2)
		if stems == 1:
			_box("sign", Vector3(t, lh, 0.13), Vector3(lx + r.randf_range(-0.3, 0.3) * lw, y0 + lh * 0.5, z), col)
		else:
			for sx in [-1.0, 1.0]:
				_box("sign", Vector3(t, lh, 0.13), Vector3(lx + sx * (lw - t) * 0.5, y0 + lh * 0.5, z), col)
		for k in 3:
			if r.randf() < 0.55:
				_box("sign", Vector3(lw, t, 0.13), Vector3(lx, y0 + t * 0.5 + k * (lh - t) * 0.5, z - 0.005), col)


func _awning(cx: float, w: float, zf: float, y: float, col: Color) -> void:
	var a := Vector3(cx - w * 0.5, y + 0.6, zf)
	var b := Vector3(cx + w * 0.5, y + 0.6, zf)
	var c := Vector3(cx + w * 0.5, y, zf - 1.3)
	var d := Vector3(cx - w * 0.5, y, zf - 1.3)
	_quad("paint", d, c, b, a, col, [], Vector3.UP)
	if not fine_parts:
		_quad("paint", d, c, c + Vector3(0, -0.3, 0), d + Vector3(0, -0.3, 0), col.darkened(0.15), [], Vector3.FORWARD)
		return
	# Desktop: a fixed canvas awning as Main Street sign shops make them,
	# closed at the ends, either the shop's name lettered on the valance
	# or the canvas in wide stripes.
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 31, snappedf(cx, 0.1)])
	for e in [a, b]:
		_tri("paint", e, Vector3(e.x, y, zf - 1.3), Vector3(e.x, y, zf - 0.01), col.darkened(0.08), [], Vector3(signf(e.x - cx), 0, 0))
	var drop := Vector3(0, -0.3, 0)
	var pick := r.randf()
	if pick < 0.45:
		# Painted letters (sign alpha 0.5-0.99: unlit, width (a - 0.5) * 60).
		var v := col.darkened(0.15)
		v.a = 0.5 + w / 60.0
		_quad("sign", d, c, c + drop, d + drop, v, [Vector2(0, 1), Vector2(w, 1), Vector2(w, 0), Vector2(0, 0)], Vector3.FORWARD)
	else:
		_quad("paint", d, c, c + drop, d + drop, col.darkened(0.15), [], Vector3.FORWARD)
	if pick > 0.7:
		var stripe := Color("#efe9da") if r.randf() < 0.75 else Color("#c9a43a")
		var n := Vector3(0, 1.3, 0.6).normalized() * 0.012
		var sw := 0.16
		var x := cx - w * 0.5 + sw
		while x + sw < cx + w * 0.5:
			_quad("paint", Vector3(x, y, zf - 1.3) + n, Vector3(x + sw, y, zf - 1.3) + n,
				Vector3(x + sw, y + 0.6, zf) + n, Vector3(x, y + 0.6, zf) + n, stripe, [], Vector3.UP)
			_quad("paint", Vector3(x, y, zf - 1.312), Vector3(x + sw, y, zf - 1.312),
				Vector3(x + sw, y - 0.3, zf - 1.312), Vector3(x, y - 0.3, zf - 1.312), stripe.darkened(0.1), [], Vector3.FORWARD)
			x += sw * 2.0


# ---------------------------------------------------------------- more shops

## A strip center, 1960s-now: one long flat-roofed building split into three
## to five tenants, each its own storefront and sign, under a continuous
## canopy on square columns, with a parking field in front.
func _strip_center(to_curb: float, anchor := false) -> void:
	var w := half * 2.0 - 2.0
	var d := rng.randf_range(14.0, minf(18.0, maxf(depth - 18.0, 14.0)))
	var h := rng.randf_range(5.2, 6.0)
	var zf := rng.randf_range(16.0, 18.0)
	var cz := zf + d * 0.5
	var wall := Color(_pick(BLOCK + ["#c9b79a", "#b8a58a"]))
	var mull: Color = MULLION[rng.randi() % 2]
	# Its front as built in its decade (own random numbers, so the builder's
	# don't move): the 1960s flat canopy on square columns; the 1970s-80s
	# mansard, a steep shingled slope over the walk on a brown brick front;
	# or the 1990s-2010s front of tenant towers in EIFS, each a different
	# height with its own cornice, on stone-veneer piers.
	var sr := RandomNumberGenerator.new()
	sr.seed = hash([rng.seed, "strip style"])
	var style: String = ["flat", "flat", "mansard", "mansard", "towers"][sr.randi() % 5]
	if era == "recent":
		style = ["mansard", "towers", "towers"][sr.randi() % 3]
	var mat := "paint"
	if style == "mansard":
		wall = Color(FACADE_BRICK[sr.randi() % FACADE_BRICK.size()])
		mat = "brick"
	elif style == "towers":
		wall = Color(["#d8c9a8", "#cdbb98", "#e0d4ba", "#c4b391"][sr.randi() % 4])
	# A neighborhood center: a supermarket anchors the +x end.
	var aw := clampf(w * 0.4, 32.0, 56.0) if anchor and w >= 70.0 else 0.0
	var ax0 := w * 0.5 - aw
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(0, 0.15, cz), FOUNDATION)
	_flat_roofed(mat, w, d, cz, h, h + 1.2, wall)
	var n := clampi(int(w / 7.0), 3, 14)
	var bay := w / n
	site.door = Vector2(-w * 0.5 + bay * 0.5, zf)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * bay
		if aw > 0.0 and x > ax0:
			continue
		var sw := bay - 1.4
		shopfront = fine_parts
		_glass(Vector3(x - 0.4, 1.7, zf - 0.03), Vector3(-1, 0, 0), sw - 1.4, 2.3, rng.randf_range(0.0, 0.2))
		shopfront = false
		_glass(Vector3(x + sw * 0.5 - 0.5, 1.45, zf - 0.03), Vector3(-1, 0, 0), 0.95, 2.4, 0.0)
		_box("paint", Vector3(sw, 0.1, 0.12), Vector3(x, 2.9, zf - 0.06), mull)
		_box("paint", Vector3(sw, 0.35, 0.12), Vector3(x, 0.47, zf - 0.06), mull)
		_box("paint", Vector3(0.5, 3.0, 0.2), Vector3(x - bay * 0.5, 1.8, zf - 0.1), wall.darkened(0.1))
		# The owner's own store takes the first bay; the other tenants' signs
		# are their own businesses, drawn as stand-in lettering.
		var spec := sign_spec
		if i > 0:
			sign_spec = {}
		var sgw := sw * rng.randf_range(0.5, 0.8)
		if fine_parts and sign_spec.is_empty():
			_channel_letters(Vector3(x, 3.9, zf - 2.55), sgw, 0.7)
		else:
			_sign(Vector3(x, 3.9, zf - 2.55), sgw, 0.7)
		sign_spec = spec
	# Canopy over the walk on square columns (a mansard's slope instead).
	var x1 := w * 0.5 - aw if style == "mansard" and aw > 0.0 else w * 0.5
	if style == "mansard":
		_strip_mansard(-w * 0.5 - 0.2, x1 + 0.2, zf, h + 1.2, Color(["#4a3f36", "#3e3e3c", "#5a4a3c", "#6b5a45"][sr.randi() % 4]))
	else:
		_box("paint", Vector3(w + 0.4, 0.5, 2.6), Vector3(0, 3.65, zf - 1.3), wall.lightened(0.1))
		_quad("paint", Vector3(-w * 0.5 - 0.2, 3.39, zf - 2.6), Vector3(w * 0.5 + 0.2, 3.39, zf - 2.6),
			Vector3(w * 0.5 + 0.2, 3.39, zf), Vector3(-w * 0.5 - 0.2, 3.39, zf), SOFFIT, [], Vector3.DOWN)
	var pier := Color(["#9c8f7a", "#b3a58c", "#8a7f70"][sr.randi() % 3])
	var x := -w * 0.5
	while x <= x1 + 0.01:
		var px := clampf(x, -w * 0.5 + 0.3, w * 0.5 - 0.3)
		_box(mat, Vector3(0.45, 3.0, 0.45), Vector3(px, 1.9, zf - 2.3), wall.lightened(0.1) if mat == "paint" else wall)
		if style == "towers":
			_box("paint", Vector3(0.65, 1.1, 0.65), Vector3(px, 0.55, zf - 2.3), pier)  # cultured stone
		x += bay
	if aw > 0.0:
		_grocery_anchor(ax0, w * 0.5, zf, cz, d, wall, mull)
	_rooftop(w, d, cz, h, n)
	if style == "towers":
		_strip_towers(w, bay, n, ax0 if aw > 0.0 else INF, zf, h + 1.2, wall, sr)
	elif style == "flat":
		# A raised false front over the end store, and over the middle on a
		# long centre: what a strip centre's parapet does to break up its length.
		_raised_front(-w * 0.5 + bay * 0.5, bay, zf, h + 1.2, wall, "paint")
		if n >= 5:
			_raised_front(-w * 0.5 + (n / 2 + 0.5) * bay, bay, zf, h + 1.2, wall, "paint")
	_shop_parking(to_curb, w, zf - 2.6, 0.0)
	if fine_parts:
		_strip_lot_dress(to_curb, zf - 4.6, n, wall)


## A 1970s-80s strip's mansard: a steep slope of asphalt shingles from the
## canopy's edge over the walk up to the parapet, closed at the ends, a
## fascia at its foot and the walk's soffit under it.
func _strip_mansard(x0: float, x1: float, zf: float, top: float, col: Color) -> void:
	var zo := zf - 2.6
	var y0 := 3.35
	var zt := zf - 1.4
	_quad("roof", Vector3(x0, y0, zo), Vector3(x1, y0, zo), Vector3(x1, top, zt), Vector3(x0, top, zt), col, [],
		Vector3(0, zt - zo, -(top - y0)).normalized())
	_quad("paint", Vector3(x0, top, zt), Vector3(x1, top, zt), Vector3(x1, top, zf), Vector3(x0, top, zf), col.darkened(0.2), [], Vector3.UP)
	for e in [x0, x1]:
		_quad("roof", Vector3(e, y0, zo), Vector3(e, top, zt), Vector3(e, top, zf), Vector3(e, y0, zf), col.darkened(0.08), [],
			Vector3(signf(e), 0, 0))
	_box("paint", Vector3(x1 - x0 + 0.05, 0.3, 0.12), Vector3((x0 + x1) * 0.5, y0 + 0.1, zo - 0.04), Color("#3a3430"))
	_quad("paint", Vector3(x0, y0 - 0.01, zo), Vector3(x1, y0 - 0.01, zo), Vector3(x1, y0 - 0.01, zf), Vector3(x0, y0 - 0.01, zf), SOFFIT, [], Vector3.DOWN)


## A 1990s-2010s strip's front: a tower over every other tenant, each its
## own height and its own cornice (some with a standing-seam hip cap), in
## EIFS a shade off the wall, and gooseneck lamps over the signs.
func _strip_towers(w: float, bay: float, n: int, stop: float, zf: float, top: float, wall: Color, sr: RandomNumberGenerator) -> void:
	var cap := Color(["#e7e1d2", "#d6cdb8", "#5a5048"][sr.randi() % 3])
	var seam := Color(["#3f5a4a", "#6b3a2e", "#3a4250", "#4a4038"][sr.randi() % 4])
	for i in n:
		var cx := -w * 0.5 + (i + 0.5) * bay
		if cx + bay * 0.5 > stop + 0.01:
			break
		if fine_parts:
			for s in [-1.0, 1.0]:
				_box("paint", Vector3(0.06, 0.06, 0.6), Vector3(cx + s * bay * 0.3, 4.75, zf - 2.85), Color("#2a2c2e"))
				_box("paint", Vector3(0.25, 0.12, 0.25), Vector3(cx + s * bay * 0.3, 4.68, zf - 3.1), Color("#2a2c2e"))
		if i % 2 == 1 and i != 0:
			continue
		var fw := bay * sr.randf_range(0.55, 0.85)
		var rise := sr.randf_range(1.4, 3.2)
		var tint := wall.lightened(sr.randf_range(-0.08, 0.1))
		_box("paint", Vector3(fw, rise + 0.6, 1.0), Vector3(cx, top + rise * 0.5 - 0.3, zf - 0.4), tint)
		_box("paint", Vector3(fw + 0.5, 0.35, 1.4), Vector3(cx, top + rise + 0.12, zf - 0.4), cap)
		_box("paint", Vector3(fw + 0.2, 0.2, 1.15), Vector3(cx, top + rise - 0.6, zf - 0.4), cap)
		if sr.randf() < 0.4:
			var y := top + rise + 0.3
			var hx := fw * 0.5 + 0.2
			var a := Vector3(cx - hx, y, zf - 1.1)
			var b := Vector3(cx + hx, y, zf - 1.1)
			var c := Vector3(cx + hx, y, zf + 0.3)
			var d := Vector3(cx - hx, y, zf + 0.3)
			var p := Vector3(cx, y + minf(fw, 1.4) * 0.5, zf - 0.4)
			_tri("roof", a, b, p, seam, [], Vector3(0, 1, -1))
			_tri("roof", b, c, p, seam, [], Vector3(1, 1, 0))
			_tri("roof", c, d, p, seam, [], Vector3(0, 1, 1))
			_tri("roof", d, a, p, seam, [], Vector3(-1, 1, 0))


## A community shopping center (ICSC: 125,000 to 400,000 sq ft on 10 to 30
## acres, anchored by a discount department store and a supermarket),
## scaled to the 5-acre site the game allows: the small-town kind Indiana
## got in the 1980s-90s, when discount chains built 40,000-90,000 sq ft
## stores in towns of 5,000-25,000 (Kmart, Walmart, Pamida). A discount
## store with its fenced garden center at one end, a supermarket at the
## other, a line of shops between, and in front a parking field of
## double-loaded rows (ULI: 18.3 m modules, 4-5 stalls per 1,000 sq ft)
## off one main drive, with a pad building by the road (a bank or a burger
## place, as every such center leases its outparcel) and a truck court
## behind. Its own random numbers, so the builder's don't move.
func _community_center(to_curb: float) -> void:
	var cr := RandomNumberGenerator.new()
	cr.seed = hash([rng.seed, "community"])
	var w := half * 2.0 - 2.0
	var back := clampf(depth - 70.0, 6.0, 18.0)  # truck court behind
	var dd := clampf(depth - back - 32.0, 22.0, 50.0)
	var zf := maxf(depth - back - dd, 20.0)
	dd = minf(dd, depth - zf - 4.0)
	var wd := clampf(w * 0.5, 34.0, 66.0)
	var wg := clampf(w * 0.22, 22.0, 32.0)
	if w - wd - wg < 14.0:
		wd = maxf(w - wg - 14.0, 24.0)
	var xd0 := -w * 0.5
	var xd1 := xd0 + wd
	var xg0 := w * 0.5 - wg
	var mull: Color = MULLION[cr.randi() % 2]
	var wall := Color(["#b8b2a4", "#c9c1ae", "#a49d8f", "#d2c8b2"][cr.randi() % 4])
	var band := Color(["#1f4e8a", "#b0262b", "#2f6a3e", "#5a5e62"][cr.randi() % 4])
	# The discount store: a long block box with an EIFS band and a stripe in
	# the chain's colour, two entries (in and out) under a raised front.
	var gw := 13.0  # garden center along its outer end
	var hd := cr.randf_range(8.4, 9.4)
	var sx0 := xd0 + gw
	# The 2000s supercenter front (own random numbers): tan EIFS over a
	# stone wainscot, a tower over each of its two entries (grocery at one,
	# general merchandise at the other) and the name on the wall between.
	var sp := RandomNumberGenerator.new()
	sp.seed = hash([rng.seed, "supercenter"])
	var sup := sp.randf() < (0.7 if era == "recent" else 0.25)
	if sup:
		wall = Color(["#d6c4a0", "#cdb894", "#e0d2b4"][sp.randi() % 3])
	_cc_box("paint", sx0, xd1, zf, zf + dd, hd, hd + 0.9, wall)
	_box("paint", Vector3(xd1 - sx0 + 0.1, 1.5, 0.3), Vector3((sx0 + xd1) * 0.5, hd - 0.4, zf - 0.12), wall.lightened(0.1))
	_box("paint", Vector3(xd1 - sx0 + 0.12, 0.45, 0.34), Vector3((sx0 + xd1) * 0.5, hd - 1.35, zf - 0.13), band)
	# Split-face block wainscot a shade darker, as the chains built them.
	_box("paint", Vector3(xd1 - sx0 + 0.08, 1.3, 0.2), Vector3((sx0 + xd1) * 0.5, 0.65, zf - 0.08),
		Color("#8a7d6b") if sup else wall.darkened(0.22))
	var ex := (sx0 + xd1) * 0.5
	var ew := minf((xd1 - sx0) * 0.5, 22.0)
	var eh := hd + 2.4
	var spec := sign_spec
	var vxs := [ex - ew * 0.3, ex + ew * 0.3]
	if sup:
		vxs = [ex - ew * 0.55, ex + ew * 0.55]
		for vx in vxs:
			var th := hd + 3.6
			_box("paint", Vector3(10.0, th, 1.6), Vector3(vx, th * 0.5, zf - 0.8), wall.lightened(0.08))
			_box("paint", Vector3(10.6, 0.5, 2.0), Vector3(vx, th + 0.1, zf - 0.8), band)  # cornice
			_box("paint", Vector3(10.2, 0.9, 1.7), Vector3(vx, 0.45, zf - 0.8), Color("#8a7d6b"))  # stone base
			sign_spec = {}
			_sign(Vector3(vx, th - 2.4, zf - 1.62), 6.5, 1.0)  # "Grocery" / "Home & Pharmacy"
		sign_spec = spec
		_sign(Vector3(ex, hd - 2.6, zf - 0.33), minf(ew * 0.7, 16.0), 1.8)
	else:
		_box("paint", Vector3(ew, eh, 1.4), Vector3(ex, eh * 0.5, zf - 0.7), wall.lightened(0.06))
		_box("paint", Vector3(ew + 0.4, 0.4, 1.7), Vector3(ex, eh + 0.2, zf - 0.7), band)
		_sign(Vector3(ex, eh - 2.3, zf - 1.42), ew * 0.75, 1.7)
	sign_spec = {}
	for vx: float in vxs:
		_box("paint", Vector3(5.0, 3.4, 3.0), Vector3(vx, 1.7, zf - 2.9), wall.lightened(0.03))  # vestibule
		_box("paint", Vector3(5.4, 0.3, 3.4), Vector3(vx, 3.5, zf - 2.9), band)
		_glass(Vector3(vx, 1.35, zf - 4.42), Vector3(-1, 0, 0), 4.2, 2.5, 0.0)
		_box("paint", Vector3(2.4, 2.2, 0.06), Vector3(vx, 1.1, zf - 4.46), Color("#2b2d2f"))
	# The garden center: a fenced yard in front of the end wall (black
	# picket panels on a block knee wall), a shade roof over its back half.
	var gz1 := zf + minf(dd * 0.6, 24.0)
	var gz0 := zf - 6.0
	var fence := Color("#2a2c2e")
	_flat_rect("drive", xd0 + 0.3, sx0, gz0, gz1, 0.08)
	for e in [[Vector2(xd0 + 0.3, gz0), Vector2(sx0, gz0)], [Vector2(xd0 + 0.3, gz0), Vector2(xd0 + 0.3, gz1)],
			[Vector2(xd0 + 0.3, gz1), Vector2(sx0, gz1)], [Vector2(sx0, gz0), Vector2(sx0, zf)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var mid := (a + b) * 0.5
		var size := Vector3(maxf(absf(b.x - a.x), 0.2), 0.0, maxf(absf(b.y - a.y), 0.2))
		_box("paint", Vector3(size.x, 0.8, size.z), Vector3(mid.x, 0.4, mid.y), wall.darkened(0.1))
		_box("metal", Vector3(size.x if size.x > 0.2 else 0.06, 2.6, size.z if size.z > 0.2 else 0.06), Vector3(mid.x, 2.1, mid.y), fence)
	_box("paint", Vector3(gw - 0.4, 0.25, gz1 - zf - 4.0), Vector3(xd0 + gw * 0.5 + 0.1, 4.6, (zf + 4.0 + gz1) * 0.5), Color("#e9e6dc"))
	for i in 3:
		_box("metal", Vector3(0.15, 4.5, 0.15), Vector3(xd0 + 1.0 + i * (gw - 2.0) * 0.5, 2.25, zf + 4.2), fence)
	if fine_parts:
		for i in 6:  # nursery tables and pallets of mulch
			_box("paint", Vector3(gw - 4.0, 0.9, 1.2), Vector3(xd0 + gw * 0.5, 0.45, gz0 + 2.0 + i * 2.6), Color("#5c6b3a") if i % 2 == 0 else Color("#6a4a32"))
	# The supermarket at the other end, the shops between.
	var hs := cr.randf_range(5.3, 6.0)
	var ds := minf(18.0, dd)
	var x0s := xd1
	var x1s := xg0
	_cc_box("paint", x0s, x1s, zf, zf + ds, hs, hs + 1.0, wall.darkened(0.04))
	var n := maxi(2, int((x1s - x0s) / 7.5))
	var bay := (x1s - x0s) / n
	for i in n:
		var x := x0s + (i + 0.5) * bay
		shopfront = fine_parts
		_glass(Vector3(x - 0.4, 1.7, zf - 0.03), Vector3(-1, 0, 0), bay - 2.8, 2.3, cr.randf_range(0.0, 0.2))
		shopfront = false
		_glass(Vector3(x + (bay - 1.4) * 0.5 - 0.5, 1.45, zf - 0.03), Vector3(-1, 0, 0), 0.95, 2.4, 0.0)
		_box("paint", Vector3(0.5, 3.0, 0.2), Vector3(x - bay * 0.5, 1.8, zf - 0.1), wall.darkened(0.12))
		if fine_parts:
			_channel_letters(Vector3(x, 4.0, zf - 2.55), (bay - 1.4) * 0.65, 0.7)
		else:
			_sign(Vector3(x, 4.0, zf - 2.55), (bay - 1.4) * 0.65, 0.7)
	_box("paint", Vector3(x1s - x0s, 0.5, 2.6), Vector3((x0s + x1s) * 0.5, 3.65, zf - 1.3), wall.lightened(0.1))
	var px := x0s
	while px <= x1s + 0.01:
		_box("paint", Vector3(0.45, 3.0, 0.45), Vector3(clampf(px, x0s + 0.3, x1s - 0.3), 1.9, zf - 2.3), wall.lightened(0.1))
		px += bay
	_grocery_anchor(xg0, w * 0.5, zf, zf + ds * 0.5, ds, wall, mull)
	sign_spec = spec
	site.door = Vector2(vxs[0], zf - 4.5)
	# The truck court: the discount store's docks and trailers at the back.
	var dz := zf + dd
	if depth - dz > 5.0:
		_flat_rect("asphalt", -half + 0.6, half - 0.6, dz, depth - 0.6, 0.06)
		for k in 3:
			var kx := xd1 - 6.0 - k * 5.0
			_box("paint", Vector3(3.0, 3.2, 0.1), Vector3(kx, 1.6, dz + 0.06), Color("#5a5c5e"))
			_box("paint", Vector3(3.4, 1.2, 0.5), Vector3(kx, 1.2, dz + 0.3), Color("#1e1f20"))
			if k < 2 and depth - dz > 15.0:  # a trailer backed in
				_box("paint", Vector3(2.6, 2.4, 14.6), Vector3(kx, 2.4, dz + 7.9), Color("#e6e4de"))
				_box("paint", Vector3(2.6, 0.5, 14.6), Vector3(kx, 3.85, dz + 7.9), Color("#e6e4de"))
				_box("paint", Vector3(2.4, 1.0, 0.4), Vector3(kx, 0.6, dz + 13.5), Color("#2a2a2a"))
		_box("paint", Vector3(2.4, 2.2, 5.0), Vector3(sx0 + 4.0, 1.1, dz + 2.8), Color("#3d5a7a"))  # baler/compactor
	_rooftop(w * 0.8, dd * 0.6, zf + dd * 0.5, hd, 6)
	_cc_parking(to_curb, w, zf - 2.6, xg0, cr)


## A flat-roofed box between x0 and x1: walls, a membrane roof, a parapet
## and coping (_flat_roofed, off centre).
func _cc_box(mat: String, x0: float, x1: float, z0: float, z1: float, deck: float, top: float, wall: Color) -> void:
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	_box(mat, Vector3(w + 0.1, 0.3, d + 0.1), Vector3(cx, 0.15, cz), FOUNDATION)
	_box(mat, Vector3(w, deck, d), Vector3(cx, deck * 0.5, cz), wall)
	var y := deck + 0.02
	_quad("membrane", Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
		_low_slope(w, d, cz), [], Vector3.UP)
	_roof_bits(cx, w, d, cz, y, false)
	var ph := top - deck
	var t := 0.25
	var col := _coping_color(false)
	for s in [-1.0, 1.0]:
		_box(mat, Vector3(w, ph, t), Vector3(cx, deck + ph * 0.5, cz + s * (d * 0.5 - t * 0.5)), wall)
		_box(mat, Vector3(t, ph, d), Vector3(cx + s * (w * 0.5 - t * 0.5), deck + ph * 0.5, cz), wall)
		_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(cx, top, cz + s * d * 0.5), col)
		_box("paint", Vector3(0.35, 0.1, d), Vector3(cx + s * w * 0.5, top, cz), col)


## The community center's parking field: a walk and fire lane along the
## stores, then double-loaded rows (5.5 m stalls either side of a 7.3 m
## aisle, head to head between modules) down to the street, off a main
## drive from the curb cut; the pad building in the front corner by the
## supermarket. Notes every stall with the aisle it's reached from.
func _cc_parking(to_curb: float, w: float, zw: float, xg0: float, cr: RandomNumberGenerator) -> void:
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	_flat_rect("drive", -w * 0.5 - 0.5, w * 0.5 + 0.5, zw - 2.0, zw, 0.08)
	_flat_rect("asphalt", lot0, lot1, 0.0, zw - 2.0, 0.06)
	var cut_x := clampf((-w * 0.5 + xg0) * 0.5, lot0 + 6.0, lot1 - 26.0)
	_curb_cut(cut_x, 4.2, -to_curb, 0.0)
	site.cut_x = cut_x
	site.main_street = false
	# The pad: a small brick box by the road with its drive-through lane.
	var pad := Rect2(lot1 - 20.0, 2.0, 19.0, 15.0)
	var pc := pad.get_center()
	var brick := Color(FACADE_BRICK[cr.randi() % FACADE_BRICK.size()])
	# EIFS over a brick wainscot, the 1990s pad restaurant's dress (painted,
	# so its far version takes the center's own wall colour).
	_box("paint", Vector3(12.0, 4.2, 9.0), Vector3(pc.x, 2.1, pc.y + 1.0), Color(["#d9c7a6", "#cbb894", "#e2d6bd"][cr.randi() % 3]))
	_box("paint", Vector3(12.06, 1.1, 9.06), Vector3(pc.x, 0.55, pc.y + 1.0), brick)
	_quad("membrane", Vector3(pc.x - 6.0, 4.22, pc.y - 3.5), Vector3(pc.x + 6.0, 4.22, pc.y - 3.5),
		Vector3(pc.x + 6.0, 4.22, pc.y + 5.5), Vector3(pc.x - 6.0, 4.22, pc.y + 5.5), Color("#9a9790"), [], Vector3.UP)
	var accent := Color(AWNING[cr.randi() % AWNING.size()])
	_box("paint", Vector3(12.3, 0.55, 9.3), Vector3(pc.x, 4.45, pc.y + 1.0), accent)
	_glass(Vector3(pc.x, 1.6, pc.y - 3.53), Vector3(-1, 0, 0), 8.0, 2.0, 0.1)
	_sign(Vector3(pc.x, 3.0, pc.y - 3.6), 5.0, 0.8)
	# The drive-through: a 3.5 m lane down the east side, cars heading for
	# the road with the building on the driver's side; the pickup window
	# under a slim canopy, and behind the building the menu board and
	# order speaker (any McDonald's, Wendy's or Taco Bell pad).
	_box("paint", Vector3(1.6, 0.3, 4.5), Vector3(pc.x + 6.8, 3.3, pc.y + 1.0), accent.darkened(0.2))  # pickup window canopy
	_glass(Vector3(pc.x + 6.03, 1.5, pc.y + 1.0), Vector3(0, 0, -1), 1.6, 1.2, 0.0)
	_box("paint", Vector3(0.1, 0.12, 1.9), Vector3(pc.x + 6.1, 0.85, pc.y + 1.0), Color("#8f9396"))  # sill
	_flat_rect("line", pc.x + 9.5, pc.x + 9.62, pc.y - 3.5, pc.y + 7.4, 0.07, Color("#e9e6da"))
	if fine_parts:
		var dark := Color("#2a2c2e")
		_box("paint", Vector3(0.3, 1.8, 2.6), Vector3(pc.x + 6.4, 1.8, pc.y + 6.6), dark)  # menu board
		_box("paint", Vector3(0.04, 1.5, 2.3), Vector3(pc.x + 6.56, 1.85, pc.y + 6.6), Color("#e8ddc4"))
		for k in 3:
			_box("paint", Vector3(0.05, 0.3, 0.6), Vector3(pc.x + 6.6, 2.3 - k * 0.45, pc.y + 5.9 + k * 0.35), accent)
		_box("paint", Vector3(0.25, 0.9, 0.12), Vector3(pc.x + 6.4, 0.45, pc.y + 6.6), dark)
		_box("paint", Vector3(0.35, 1.3, 0.35), Vector3(pc.x + 6.5, 0.65, pc.y + 5.4), dark)  # order speaker
		_box("paint", Vector3(0.45, 0.6, 0.6), Vector3(pc.x + 6.5, 1.15, pc.y + 5.1), accent)  # its little canopy
	_flat_rect("mulch", pad.position.x + 0.6, pad.position.x + 9.4, pad.position.y - 0.2, pad.position.y + 1.6, 0.075)  # their bed
	for i in 3:
		_shrub(Vector3(pad.position.x + 2.0 + i * 3.0, 0, pad.position.y + 0.6), 0.7)
	# Rows: the fire lane is the first aisle, then 18.3 m modules.
	var stall := 2.75
	var rows := []  # [z of the stall's middle, face z, aisle z]
	var az := zw - 2.0 - 3.65
	while true:
		var zb := az - 3.65
		if zb - 5.5 < 1.0:
			break
		rows.append([zb - 2.75, -1.0, az])
		var az2 := az - 18.3
		if az2 - 3.65 < 1.0:
			break
		rows.append([az2 + 3.65 + 2.75, 1.0, az2])
		az = az2
	for row in rows:
		var zc: float = row[0]
		var x := lot0 + 2.0
		while x + stall <= lot1 - 2.0 + 0.01:
			var mx := x + stall * 0.5
			x += stall
			if absf(mx - cut_x) < 7.0 or pad.grow(1.0).has_point(Vector2(mx, zc)):
				continue
			_flat_rect("line", mx - stall * 0.5 - 0.06, mx - stall * 0.5 + 0.06, zc - 2.75, zc + 2.75, 0.07, LINE)
			site.stalls.append([Vector2(mx, zc), Vector2(0, row[1]), row[2]])
	site.aisle_z = zw - 2.0 - 3.65
	if not fine_parts:
		return
	# Light poles on the head-to-head seams, cart corrals, islands' trees.
	for row in rows:
		if float(row[1]) > 0.0:
			var sz: float = float(row[0]) - 2.75
			var x := lot0 + 14.0
			while x < lot1 - 8.0:
				if absf(x - cut_x) > 7.0 and not pad.grow(2.0).has_point(Vector2(x, sz)):
					_box("concrete", Vector3(0.6, 0.9, 0.6), Vector3(x, 0.45, sz), FOUNDATION)
					_box("paint", Vector3(0.16, 10.0, 0.16), Vector3(x, 5.9, sz), Color("#2e3032"))
					_box("paint", Vector3(0.6, 0.18, 0.8), Vector3(x, 10.9, sz), Color("#2e3032"))
					_light_pool(Vector3(x, 0.13, sz), 26.0, 26.0, Color(0.95, 0.96, 1.0))
				x += 30.0
	for k in [-1.0, 1.0]:
		var p := Vector3(cut_x + k * 4.4, 0, 1.2)
		var pick := TreeField.pick(cr, true)
		trees.append([p, pick[0], pick[1], cr.randf_range(0.9, 1.1)])
	# Planted islands at the ends of the rows and either side of the main
	# drive (a shade tree in each, as Indiana towns' parking codes ask).
	for row in rows:
		var zc: float = row[0]
		for x in [lot0 + 1.0, lot1 - 1.0, cut_x - 5.4, cut_x + 5.4]:
			if pad.grow(1.5).has_point(Vector2(x, zc)):
				continue
			_flat_rect("mulch", x - 0.9, x + 0.9, zc - 2.5, zc + 2.5, 0.09)
			var pick := TreeField.pick(cr, true)
			trees.append([Vector3(x, 0, zc), pick[0], pick[1], cr.randf_range(0.7, 0.95)])


## The supermarket that anchors a neighborhood center (ICSC: 30,000 to
## 125,000 sq ft with a grocer; Kroger, Marsh and Aldi in Indiana's 1990s-
## 2010s centers): a taller, deeper box than the shops, its front a raised
## entry tower with the store's name, a wide glass vestibule with in and
## out doors, cart corrals in the lot, and a truck well at the back.
func _grocery_anchor(x0: float, x1: float, zf: float, cz: float, d: float, wall: Color, mull: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "grocer"])
	var aw := x1 - x0
	var ax := (x0 + x1) * 0.5
	var ad := minf(depth - zf - 2.0, maxf(d, r.randf_range(26.0, 34.0)))
	var h := r.randf_range(7.8, 8.8)
	var face := wall.lightened(0.12) if r.randf() < 0.5 else Color(_pick(["#d8cfbd", "#b9a68a", "#8f8a80"]))
	var accent := Color(_pick(["#2b4a7a", "#7a2b2b", "#2f5a3a", "#3a3c3e"]))
	var zfa := zf - 0.25
	_box("paint", Vector3(aw, h, ad), Vector3(ax, h * 0.5, zfa + ad * 0.5), face)
	_quad("membrane", Vector3(x0, h + 0.02, zfa), Vector3(x1, h + 0.02, zfa), Vector3(x1, h + 0.02, zfa + ad),
		Vector3(x0, h + 0.02, zfa + ad), Color("#9a9790"), [], Vector3.UP)
	_box("paint", Vector3(aw + 0.1, 0.5, 0.4), Vector3(ax, h + 0.25, zfa - 0.05), accent)  # cap band
	# The entry tower: a raised front with a gable or a barrel over it.
	var tx := ax + r.randf_range(-aw * 0.15, aw * 0.15)
	var tw := minf(aw * 0.4, 16.0)
	var th := h + 3.5
	_box("paint", Vector3(tw, th, 1.2), Vector3(tx, th * 0.5, zfa - 0.6), face.lightened(0.05))
	if r.randf() < 0.5:
		_tri("roof", Vector3(tx - tw * 0.5 - 0.3, th, zfa - 1.25), Vector3(tx + tw * 0.5 + 0.3, th, zfa - 1.25),
			Vector3(tx, th + tw * 0.22, zfa - 1.25), accent, [], Vector3(0, 0, -1))
		_quad("roof", Vector3(tx - tw * 0.5 - 0.3, th, zfa - 1.25), Vector3(tx, th + tw * 0.22, zfa - 1.25),
			Vector3(tx, th + tw * 0.22, zfa + 0.05), Vector3(tx - tw * 0.5 - 0.3, th, zfa + 0.05), accent, [], Vector3(-1, 1, 0))
		_quad("roof", Vector3(tx, th + tw * 0.22, zfa - 1.25), Vector3(tx + tw * 0.5 + 0.3, th, zfa - 1.25),
			Vector3(tx + tw * 0.5 + 0.3, th, zfa + 0.05), Vector3(tx, th + tw * 0.22, zfa + 0.05), accent, [], Vector3(1, 1, 0))
	else:
		_box("paint", Vector3(tw + 0.4, 0.6, 1.5), Vector3(tx, th + 0.3, zfa - 0.6), accent)
	var spec := sign_spec
	sign_spec = {}
	_sign(Vector3(tx, th - 2.2, zfa - 1.25), tw * 0.8, 1.6)
	sign_spec = spec
	# The vestibule: glass across the tower's foot, in and out doors.
	_glass(Vector3(tx, 1.7, zfa - 1.23), Vector3(-1, 0, 0), tw - 1.2, 3.0, 0.0)
	for k in [-1.0, 1.0]:
		_box("paint", Vector3(2.0, 2.3, 0.06), Vector3(tx + k * tw * 0.22, 1.15, zfa - 1.28), Color("#2b2d2f"))
	_box("paint", Vector3(tw + 1.0, 0.25, 2.6), Vector3(tx, 3.6, zfa - 2.4), accent)  # entry canopy
	# Windows along the front either side, high, with the store's banners.
	for sx in [-1.0, 1.0]:
		var fx0: float = tx + sx * (tw * 0.5 + 1.0)
		var fx1: float = x0 + 1.0 if sx < 0.0 else x1 - 1.0
		var len := absf(fx1 - fx0)
		if len > 3.0:
			_glass(Vector3((fx0 + fx1) * 0.5, 2.0, zfa - 0.03), Vector3(-1, 0, 0), len, 2.6, r.randf_range(0.2, 0.5))
			_box("paint", Vector3(len, 0.12, 0.1), Vector3((fx0 + fx1) * 0.5, 3.35, zfa - 0.06), mull)
	# Cart corrals in the lot, and the truck well at the back.
	for k in 2:
		var cx := lerpf(x0 + 4.0, x1 - 4.0, 0.25 + k * 0.5)
		var czz := zf - 12.0 - k * 2.0
		if czz < 2.0:
			continue
		for s in [-1.0, 1.0]:
			_box("metal", Vector3(0.06, 1.1, 4.0), Vector3(cx + s * 0.8, 0.55, czz), Color("#a9adb0"))
		_box("metal", Vector3(1.66, 0.06, 4.0), Vector3(cx, 1.1, czz), Color("#a9adb0"))
		for c in 4:
			_box("metal", Vector3(0.55, 0.6, 0.9), Vector3(cx, 0.5, czz - 1.4 + c * 0.75), Color("#c7c9c8"))
	var dock_z := zfa + ad
	if depth - dock_z > 6.0:
		_flat_rect("asphalt", x0 + 2.0, x0 + 18.0, dock_z, minf(depth - 0.5, dock_z + 16.0), 0.07)
		for k in 2:
			_box("paint", Vector3(3.2, 3.4, 0.1), Vector3(x0 + 6.0 + k * 6.0, 1.7, dock_z + 0.06), Color("#5a5c5e"))  # dock doors
			_box("paint", Vector3(3.6, 1.2, 0.5), Vector3(x0 + 6.0 + k * 6.0, 1.2, dock_z + 0.3), Color("#1e1f20"))  # seals


## What a real strip centre's lot has that a bare one doesn't (Marion's
## Eastbrook and Gas City strips, any Indiana US-route centre): two
## accessible stalls painted blue with the wheelchair symbol, a hatched
## access aisle and the R7-8 sign at their heads, by the centre door (ADA
## 208: 1 per 25 stalls); twin-head shoebox lights on 9 m poles along the
## front of the lot about every 28 m; and a multi-tenant pylon sign by the
## curb cut, a panel per tenant on a masonry base. Desktop only, with its
## own random numbers so the builder's don't move.
func _strip_lot_dress(to_curb: float, back: float, n: int, wall: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 9127])
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	if back > 6.0:
		# Stalls run every 2.75 m from lot0: take the pair nearest the middle.
		var k := int((0.0 - lot0) / 2.75)
		var blue := Color("#2457a6")
		for j in 2:
			var x := lot0 + (k + j) * 2.75
			if j == 0:
				_flat_rect("line", x + 0.07, x + 2.68, back - 5.4, back - 0.1, 0.065, blue)
				_flat_rect("line", x + 1.05, x + 1.7, back - 3.1, back - 2.4, 0.075, LINE)  # the symbol
				_box("metal", Vector3(0.06, 2.3, 0.06), Vector3(x + 1.375, 1.15, back + 0.4), Color("#7d8184"))
				_box("paint", Vector3(0.3, 0.45, 0.03), Vector3(x + 1.375, 2.05, back + 0.36), Color("#f2f2ee"))
				_box("paint", Vector3(0.2, 0.2, 0.01), Vector3(x + 1.375, 2.12, back + 0.34), blue)
			else:
				# The hatched aisle beside it.
				for h in 7:
					var z := back - 5.2 + h * 0.75
					_flat_rect("line", x + 0.2, x + 2.55, z, z + 0.12, 0.072, LINE)
	# Lot lights along the front of the lot.
	var poles := maxi(1, int((lot1 - lot0) / 28.0))
	var dark := Color("#2e3032")
	for i in poles:
		var px := lerpf(lot0, lot1, (i + 0.5) / poles)
		if absf(px) < 4.5:
			px += 6.0  # clear of the curb cut
		_box("concrete", Vector3(0.6, 0.6, 0.6), Vector3(px, 0.3, 0.7), FOUNDATION)
		_box("paint", Vector3(0.15, 8.6, 0.15), Vector3(px, 4.9, 0.7), dark)
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.08, 0.08, 0.7), Vector3(px, 9.1, 0.7 + s * 0.35), dark)
			_box("paint", Vector3(0.55, 0.16, 0.75), Vector3(px, 9.1, 0.7 + s * 1.0), dark)
			# 4000 K LED lens, lit after dark.
			_box("sign", Vector3(0.45, 0.02, 0.6), Vector3(px, 9.01, 0.7 + s * 1.0), Color(0.95, 0.96, 1.0, 1.0))
		# Its light on the lot (kept inside the lot's lines).
		var pw := minf(24.0, 2.0 * (half - absf(px)) + 8.0)
		_light_pool(Vector3(px, 0.13, 0.7 + 10.0), pw, 22.0, Color(0.95, 0.96, 1.0))
	# Pylon sign at the curb cut's side, set back from the right of way.
	var sx := 6.5 if r.randf() < 0.5 else -6.5
	var sz := -to_curb + 3.0
	if sz > -0.8:
		return
	var tenants := clampi(n - 1, 2, 5)
	var ph := 0.55
	var base := 1.2
	var cab_h := tenants * ph + 1.0
	var caps := ["#2c3e5c", "#5b2a2a", "#3a3c3e"]
	var cap := Color(caps[r.randi() % caps.size()])
	for s in [-1.0, 1.0]:
		_box("brick", Vector3(0.6, base + cab_h + 0.4, 0.6), Vector3(sx + s * 1.5, (base + cab_h + 0.4) * 0.5, sz), wall.darkened(0.25))
	_box("paint", Vector3(2.5, cab_h, 0.4), Vector3(sx, base + cab_h * 0.5, sz), Color("#d9d6cc"))
	_box("paint", Vector3(2.5, 1.0, 0.44), Vector3(sx, base + cab_h - 0.5, sz), cap)  # the centre's name
	for side in [-1.0, 1.0]:
		_box("paint", Vector3(1.6, 0.18, 0.02), Vector3(sx, base + cab_h - 0.5, sz + side * 0.23), Color("#f2efe4"))
		for t in tenants:
			var y := base + 0.3 + t * ph
			var col := Color(AWNING[r.randi() % AWNING.size()]).lightened(r.randf_range(0.0, 0.15))
			# Backlit tenant panels, as on a real centre's pylon.
			col.a = 2.3 / 60.0
			var pz: float = sz + side * 0.215
			_quad("sign", Vector3(sx - 1.15, y - ph * 0.5 + 0.04, pz), Vector3(sx + 1.15, y - ph * 0.5 + 0.04, pz),
				Vector3(sx + 1.15, y + ph * 0.5 - 0.04, pz), Vector3(sx - 1.15, y + ph * 0.5 - 0.04, pz), col,
				[Vector2(0, 0), Vector2(2.3, 0), Vector2(2.3, 1), Vector2(0, 1)], Vector3(0, 0, side))
	_box("concrete", Vector3(4.2, 0.25, 1.2), Vector3(sx, 0.125, sz), FOUNDATION)


## A gas station: a lit canopy over two or three pump islands, a
## convenience store behind it, a price sign on a pole by the street.
func _shop_gas_station(to_curb: float) -> void:
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
	# Canopy: a deep flat roof on columns. Its fascia is in the brand colour,
	# or white with a brand stripe (Speedway, Marathon and Casey's canopies on
	# Indiana highways), with recessed lights in the white soffit.
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 21])
	var cw := minf(sw + 2.0, half * 2.0 - 2.0)
	var cd := 10.0
	var ccz := zf - 4.0 - cd * 0.5
	var white_fascia := r.randf() < 0.55
	_box("paint", Vector3(cw, 0.9, cd), Vector3(0, 5.25, ccz), Color("#f1efe8") if white_fascia else brand)
	if white_fascia:
		# Desktop: the brand band is lit from inside after dark.
		_box("sign" if fine_parts else "paint", Vector3(cw + 0.04, 0.3, cd + 0.04), Vector3(0, 5.2, ccz), Color(brand, 0.0))
	_quad("paint", Vector3(-cw * 0.5, 4.79, ccz - cd * 0.5), Vector3(cw * 0.5, 4.79, ccz - cd * 0.5),
		Vector3(cw * 0.5, 4.79, ccz + cd * 0.5), Vector3(-cw * 0.5, 4.79, ccz + cd * 0.5), Color("#e8e6df"), [], Vector3.DOWN)
	if fine_parts:
		var lx := -cw * 0.5 + 1.5
		while lx < cw * 0.5 - 1.0:
			for lz in [-cd * 0.3, 0.0, cd * 0.3]:
				_box("sign", Vector3(0.6, 0.04, 0.6), Vector3(lx, 4.77, ccz + lz), Color(1.0, 0.99, 0.95, 1.0))
			lx += 3.0
		# Canopies are the brightest thing on a highway at night: the
		# forecourt washed in white light, spilling past the edges.
		for k in 2:
			_light_pool(Vector3(0, 0.2 + k * 0.01, ccz), cw + 10.0 - k * 6.0, cd + 10.0 - k * 6.0, Color(1.0, 0.99, 0.95))
	var islands := 2 if cw < 16.0 else 3
	for i in islands:
		var x := (i - (islands - 1) * 0.5) * cw / islands
		_box("concrete", Vector3(1.2, 0.2, 5.5), Vector3(x, 0.1, ccz), FOUNDATION)
		_box("paint", Vector3(0.4, 4.6, 0.4), Vector3(x, 2.5, ccz), Color("#d8d6cf"))
		for s in [-1.0, 1.0]:
			_dispenser(Vector3(x, 0.2, ccz + s * 1.5), brand)
			# Concrete-filled steel bollards guard each end of the island.
			_box("paint", Vector3(0.16, 1.1, 0.16), Vector3(x, 0.75, ccz + s * 2.9), Color("#f2c200"))
		if fine_parts:
			# A trash can and squeegee bucket by the column.
			_box("paint", Vector3(0.5, 0.9, 0.5), Vector3(x + 0.4, 0.65, ccz), Color("#2d3f2e"))
	# Price sign on a pole near the street: the brand panel on top, then a
	# black LED board with a row for each grade (red digits, Indiana law
	# posts the per-gallon price to the tenth of a cent).
	var px := -half + 1.5
	_box("paint", Vector3(0.3, 6.0, 0.3), Vector3(px, 3.0, 1.0), Color("#5a5e60"))
	_box("sign" if fine_parts else "paint", Vector3(2.2, 1.4, 0.3), Vector3(px, 6.3, 1.0), Color(brand, 0.0))  # lit from inside
	_box("paint", Vector3(2.0, 1.6, 0.32), Vector3(px, 4.7, 1.0), Color("#1d1d1d"))
	var reg := 0
	for row in 3:
		var ry := 5.25 - row * 0.5
		# Seen from the street (-z), +x is on the reader's left: digits there.
		_box("paint", Vector3(0.7, 0.28, 0.34), Vector3(px - 0.55, ry, 1.0), Color("#f1efe8"))
		if fine_parts:
			_box("paint", Vector3(0.5, 0.07, 0.02), Vector3(px - 0.55, ry, 1.0 - 0.18), Color("#1d2a44"))  # the grade's name
		var digit := Color("#ff3b1f") if row < 2 else Color("#38d04a")
		# $3.xx9: a price in the range Indiana pumps showed in 2024-25.
		# Regular, then mid-grade about 40 cents more, then diesel (green).
		if row == 0:
			reg = r.randi_range(0, 4)
		var dimes := reg if row == 0 else (mini(reg + 4, 9) if row == 1 else r.randi_range(5, 9))
		var price := [3, dimes, r.randi_range(0, 9), 9]
		for k in 4:
			var dx := px + 0.71 - k * 0.22
			if fine_parts:
				# The tenth of a cent is a small raised 9, after a decimal point.
				var small := k == 3
				_seven_seg(price[k], Vector3(dx + (0.03 if small else 0.0), ry + (0.05 if small else 0.0), 1.0 - 0.17), digit,
					0.55 if small else 1.0)
				if k == 0:
					_box("paint", Vector3(0.035, 0.035, 0.02), Vector3(dx - 0.11, ry - 0.13, 1.0 - 0.17), digit)
			else:
				_box("paint", Vector3(0.17, 0.3, 0.34), Vector3(dx, ry, 1.0), digit)
	# Concrete under the canopy, asphalt round it, two curb cuts.
	_flat_rect("drive", -cw * 0.5 - 1.0, cw * 0.5 + 1.0, ccz - cd * 0.5 - 1.0, ccz + cd * 0.5 + 1.0, 0.09)
	_flat_rect("asphalt", -half + 0.6, half - 0.6, 0.0, zf, 0.06)
	for x in [-half * 0.55, half * 0.55]:
		_curb_cut(x, 3.6, -to_curb, 0.0)
	_steel_door(Vector3(sw * 0.3, 1.35, zf + sd + 0.03), 1.0)
	# By the front door: the ice chest and the propane exchange cage.
	_box("paint", Vector3(1.8, 1.7, 0.8), Vector3(sw * 0.5 - 1.4, 1.15, zf - 0.6), Color("#eef2f4"))
	_box("paint", Vector3(1.82, 0.35, 0.82), Vector3(sw * 0.5 - 1.4, 1.75, zf - 0.6), Color("#1e5aa8"))
	_box("metal", Vector3(1.5, 1.6, 0.8), Vector3(sw * 0.5 - 3.4, 1.1, zf - 0.6), Color("#8d9093"))
	# Cars pull up beside the pumps, one each side of an island, and the
	# driver walks in to pay.
	if not small_store:
		_rt_gas_grown(sw, sd, zf, cw, ccz - cd * 0.5, wall, brand)
	site.main_street = false
	site.door = Vector2(-sw * 0.3 + 2.4, zf)
	site.cut_x = -half * 0.55
	site.aisle_z = clampf(ccz - cd * 0.5 - 1.5, 1.0, ccz - 4.0)
	for i in islands:
		var x := (i - (islands - 1) * 0.5) * cw / islands
		for s in [-1.0, 1.0]:
			site.stalls.append([Vector2(x + s * 2.0, ccz), Vector2(0, 1)])


## A mansard band round a flat-roofed box from `y0` up to `y1`, sloping in
## from `out` beyond the walls: four shingled faces meeting at the corners.
func _mansard(w: float, d: float, cz: float, zf: float, y0: float, y1: float, out: float, col: Color) -> void:
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	var lo := [Vector3(x0 - out, y0, z0 - out), Vector3(x1 + out, y0, z0 - out), Vector3(x1 + out, y0, z1 + out), Vector3(x0 - out, y0, z1 + out)]
	var hi := [Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = (lo[i] + lo[j]) * 0.5
		var outward := Vector3(mid.x - 0.0, 0.0, mid.z - cz).normalized() + Vector3(0, 1.2, 0)
		_quad("roof", lo[i], lo[j], hi[j], hi[i], col, [], outward)
	# The soffit under the overhang.
	_quad("paint", lo[0], lo[1], lo[2], lo[3], SOFFIT, [], Vector3.DOWN)


## One LED digit on a price board, as seven segments in a 0.15 x 0.28 m cell,
## drawn on the face toward the street (-z).
const SEGS := [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]
func _seven_seg(n: int, c: Vector3, col: Color, scale := 1.0) -> void:
	var m: int = SEGS[n]
	var w := 0.13 * scale
	var h := 0.13 * scale
	var t := 0.03 * scale
	# a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle
	var bars := [[0, h, true], [w * 0.5, h * 0.5, false], [w * 0.5, -h * 0.5, false], [0, -h, true],
		[-w * 0.5, -h * 0.5, false], [-w * 0.5, h * 0.5, false], [0, 0, true]]
	for i in 7:
		if m & (1 << i):
			var b: Array = bars[i]
			var size := Vector3(w, t, 0.02) if b[2] else Vector3(t, h, 0.02)
			# Desktop: lit LEDs after dark (sign alpha 1).
			_box("sign" if fine_parts else "paint", size, c + Vector3(-b[0], b[1], 0), Color(col, 1.0))  # mirrored: read from -z


## A fuel dispenser (Gilbarco Encore / Wayne Ovation shape): a plinth, a
## pale body with a dark screen and nozzle bay on each face, and a valance
## in the brand colour on top.
func _dispenser(at: Vector3, brand: Color) -> void:
	_box("paint", Vector3(0.9, 0.2, 0.6), at + Vector3(0, 0.1, 0), Color("#6f6a62"))
	_box("paint", Vector3(0.8, 1.45, 0.5), at + Vector3(0, 0.92, 0), Color("#e8e6df"))
	_box("paint", Vector3(0.82, 0.32, 0.52), at + Vector3(0, 1.8, 0), brand)
	for f in [-1.0, 1.0]:
		_box("paint", Vector3(0.6, 0.32, 0.03), at + Vector3(0, 1.3, f * 0.26), Color("#1b1e22"))
		if fine_parts:
			_box("paint", Vector3(0.18, 0.35, 0.06), at + Vector3(-0.22, 0.8, f * 0.27), Color("#2b2b2b"))
			_box("paint", Vector3(0.18, 0.35, 0.06), at + Vector3(0.22, 0.8, f * 0.27), Color("#2b2b2b"))


## A diner or family restaurant: one storey, a long band of windows with a
## stainless or coloured band above and below, a big pole sign.
func _shop_diner(to_curb: float) -> void:
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
	site.door = Vector2(-w * 0.5 + 1.0, zf - 2.0)
	_box("paint", Vector3(2.6, 3.0, 2.0), Vector3(-w * 0.5 + 1.0, 1.8, zf - 1.0), band)
	_glass(Vector3(-w * 0.5 + 1.0, 1.4, zf - 2.02), Vector3(-1, 0, 0), 1.6, 2.2, 0.0)
	# Half of them wear the 1970s family-restaurant mansard: a shingled
	# slope all the way round the top of the walls (Frisch's, Ponderosa and
	# the local diners built off US 35 and SR 9 in Marion).
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, 31])
	if r.randf() < 0.5:
		_mansard(w, d, cz, zf, 3.0, 4.75, 0.9, Color(["#4a3b30", "#3a3a3c", "#5b4636", "#7a3a2a"][r.randi() % 4]))
	# Pole sign, with a changeable-letter reader board under it.
	var px := half - 2.0
	_box("paint", Vector3(0.35, 7.5, 0.35), Vector3(px, 3.75, 1.5), Color("#5a5e60"))
	_sign(Vector3(px, 6.8, 1.3), 3.4, 1.6)
	_box("paint", Vector3(3.0, 1.1, 0.3), Vector3(px, 5.3, 1.5), Color("#f4f2ea"))
	_box("paint", Vector3(3.1, 0.08, 0.32), Vector3(px, 5.88, 1.5), Color("#2b2b2b"))
	_box("paint", Vector3(3.1, 0.08, 0.32), Vector3(px, 4.72, 1.5), Color("#2b2b2b"))
	if fine_parts:
		for line in 3:
			var lw := r.randf_range(1.2, 2.6)
			_box("paint", Vector3(lw * 0.8, 0.1, 0.02), Vector3(px + r.randf_range(-0.2, 0.2), 5.6 - line * 0.3, 1.34), Color("#2a2622"))
	_rooftop(w, d, cz, 4.0, 2)
	_shop_parking(to_curb, w, zf, 0.0)
	# Grown (shop level 1): a party room on the back, as family restaurants
	# add one for Rotary lunches and rehearsal dinners.
	if not small_store:
		_rt_wing(w, zf + d, 3.6, wall, "paint", band, false)


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
		# A square plinth and a capital, as on every Colonial Revival bank.
		_box("paint", Vector3(0.75, 0.3, 0.75), Vector3(-2.4 + k * 1.6, 0.77, zf - 2.5), stone)
		_box("paint", Vector3(0.72, 0.22, 0.72), Vector3(-2.4 + k * 1.6, 5.86, zf - 2.5), stone)
	_box("paint", Vector3(6.4, 0.8, 3.2), Vector3(0, 6.4, zf - 1.5), stone)
	# The cornice under the pediment, projecting past the frieze.
	_box("paint", Vector3(6.8, 0.18, 3.5), Vector3(0, 6.86, zf - 1.6), stone.lightened(0.05))
	if fine_parts:
		var nd := 22
		for k in nd:
			_box("paint", Vector3(0.12, 0.12, 0.1), Vector3(-3.15 + k * 6.3 / (nd - 1), 6.68, zf - 3.12), stone)  # dentils
		# Stone quoins up the front corners.
		for sx in [-1.0, 1.0]:
			for q in 9:
				var qw := 0.7 if q % 2 == 0 else 0.45
				_box("paint", Vector3(qw, 0.32, 0.08), Vector3(sx * (w * 0.5 - qw * 0.5 + 0.02), 1.0 + q * 0.68, zf - 0.05), stone)
	_tri("paint", Vector3(-3.2, 6.8, zf - 3.1), Vector3(3.2, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), stone, [], Vector3.FORWARD)
	_quad("roof", Vector3(-3.3, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), Vector3(0, 8.0, zf), Vector3(-3.3, 6.8, zf), Color(ROOF[0]), [], Vector3(-1, 3, 0))
	_quad("roof", Vector3(3.3, 6.8, zf - 3.1), Vector3(0, 8.0, zf - 3.1), Vector3(0, 8.0, zf), Vector3(3.3, 6.8, zf), Color(ROOF[0]), [], Vector3(1, 3, 0))
	# The front doors: a stone surround with a cornice, a pair of glass and
	# bronze doors and a transom light over them.
	_box("paint", Vector3(2.6, 3.5, 0.12), Vector3(0, 2.35, zf - 0.075), stone)
	_box("paint", Vector3(3.0, 0.25, 0.3), Vector3(0, 4.2, zf - 0.15), stone)
	_box("paint", Vector3(1.9, 2.95, 0.06), Vector3(0, 2.07, zf - 0.13), Color("#3a3530"))
	for sx in [-0.45, 0.45]:
		_glass(Vector3(sx, 1.9, zf - 0.17), Vector3(-1, 0, 0), 0.7, 2.0, 0.0)
	_glass(Vector3(0, 3.2, zf - 0.17), Vector3(-1, 0, 0), 1.7, 0.55, 0.0)
	site.door = Vector2(0.0, zf - 3.0)
	_sign(Vector3(0, 4.3, zf - 0.08), 4.0, 0.5)
	# Drive-up lane and canopy beside the building.
	var lx := w * 0.5 + 3.0
	_box("paint", Vector3(4.0, 0.6, 7.0), Vector3(lx, 4.3, cz), stone)
	for s in [-1.0, 1.0]:
		_box("brick", Vector3(0.5, 4.0, 0.5), Vector3(lx + 1.7, 2.0, cz + s * 3.0), brick)
	_box("metal", Vector3(0.8, 1.4, 0.8), Vector3(lx - 1.2, 0.7, cz), Color("#b9bcbc"))
	_flat_rect("asphalt", lx - 2.2, lx + 2.2, 0.0, depth - 1.0, 0.07)
	_shop_parking(to_curb, w, zf - 3.2, -3.0)
	# Grown (shop level 1): a one-storey wing on the back for the loan
	# offices, under a hip roof of its own, as Indiana's town banks built on
	# in the 1960s-80s.
	if not small_store:
		_rt_wing(w, zf + d, 3.8, brick, "brick", stone, true)


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
			_window(Vector3(s * w * 0.5, 3.8, z), Vector3(0, 0, -s), 1.1, 3.2, false, false, TRIM)
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
		if fine_parts:
			continue  # the desktop's _roof_services places the units, piped
		_box("metal", Vector3(1.8, 1.1, 1.2), p + Vector3(0, 0.55, 0), Color("#b9bcbc"))
		_box("paint", Vector3(1.0, 0.08, 0.8), p + Vector3(0, 1.14, 0), Color("#3a3c3e"))


## Front parking: a walk along the building, striped stalls and a curb cut.
func _shop_parking(to_curb: float, w: float, zw: float, cut_x: float) -> void:
	_flat_rect("drive", -w * 0.5 - 0.5, w * 0.5 + 0.5, zw - 2.0, zw, 0.08)
	var lot0 := -half + 0.6
	var lot1 := half - 0.6
	_flat_rect("asphalt", lot0, lot1, 0.0, zw - 2.0, 0.06)
	_curb_cut(cut_x, 3.6, -to_curb, 0.0)
	site.cut_x = cut_x
	site.main_street = false
	if zw - 2.0 > 6.0:
		var x := lot0
		while x <= lot1 + 0.01:
			_flat_rect("line", x - 0.06, x + 0.06, zw - 2.0 - 5.5, zw - 2.0, 0.07, LINE)
			x += 2.75
		_site_row(lot0, lot1, zw - 2.0, cut_x)
	else:
		site.aisle_z = (zw - 2.0) * 0.5


## Notes the row of 90 degree stalls painted between lines every 9 ft from
## `x0` to `x1`, noses in to `back`, reached along an aisle in front of them
## from the curb cut at `cut_x`.
func _site_row(x0: float, x1: float, back: float, cut_x: float) -> void:
	site.main_street = false
	site.cut_x = cut_x
	site.aisle_z = (back - 5.5) * 0.5
	var x := x0
	while x + 2.75 <= x1 + 0.01:
		site.stalls.append([Vector2(x + 1.375, back - 2.75), Vector2(0, 1)])
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
	_dr_note(0.0, cz, w, d, h, "gable")
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
	_curb_cut(w * 0.12, 3.6, -to_curb, zf - 6.0)
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


# ------------------------------------------------------------ plant dressing

## The working details every real plant and public building carries, after
## photos of Indiana industrial parks (Marion, Anderson, Kokomo, Muncie) and
## Butler / Varco Pruden metal building catalogs:
##   - gutters with downspouts and splash blocks, or scuppers with conductor
##     heads on a flat roof
##   - bronze LED wall packs about 6 m up, a steel man door with a light at
##     each end wall, translucent wall-light panels under a metal eave
##   - round gravity ridge ventilators and translucent skylight panels in
##     a metal roof; packaged rooftop units, mushroom exhaust fans and a roof
##     hatch on a flat one
##   - the utility corner: the meter bank and disconnects with conduit up
##     the wall, a gas meter on its yellow riser, and the utility's green
##     pad-mount transformer with yellow bollards (ANSI C57.12.34)
##   - the fire department connection and a Knox box by the front door
##   - the yard: pallet stacks, a forklift propane cage, a roll-off
##     container, a parked 53 ft trailer, and a 6 ft chain-link fence with
##     barbed wire round the back
## It draws from its own random sequence, so the building it dresses comes
## out the same as before. Each building calls _dr_note for each hall.
var _dr_halls := []  # [cx, cz, w, d, h, roof, busy end] with roof "gable", "flat" or "none"
var _dr_main := -1  # the hall that takes the utility corner (-1: the biggest)


## Notes a hall to dress: centre, width along x, depth along z, eave height.
## `busy` is an end wall (-1 or 1 along x) already taken by docks or doors.
func _dr_note(cx: float, cz: float, w: float, d: float, h: float, roof: String, busy := 0.0, mat := "", wall := Color.WHITE) -> void:
	_dr_halls.append([cx, cz, w, d, h, roof, busy, mat, wall])


## Dresses every noted hall, then the site's yard (`yard` false: no fence,
## trailer or pallets, for public buildings).
func _dress(yard := true, civic := false) -> void:
	if _dry or _dr_halls.is_empty():
		return
	var main := rng
	rng = RandomNumberGenerator.new()
	rng.seed = main.seed * 31 + 7
	var big: Array = _dr_halls[0]
	for hall in _dr_halls:
		if hall[2] * hall[3] > big[2] * big[3]:
			big = hall
		_dr_walls(hall, civic)
		if civic and hall[7] == "brick":
			_dr_brick(hall)
		if hall[5] == "gable":
			_dr_roof_gable(hall)
		elif hall[5] == "flat":
			_dr_roof_flat(hall)
	if _dr_main >= 0 and _dr_main < _dr_halls.size():
		big = _dr_halls[_dr_main]
	if big[2] * big[3] > 120.0:
		_dr_utility(big, civic)
	if yard:
		_dr_yard(big)
	rng = main


func _dr_walls(hall: Array, civic := false) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var h: float = hall[4]
	var flat: bool = hall[5] != "gable"
	var spout := Color("#d9d6cc") if rng.randf() < 0.6 else Color("#6b6f72")
	# Downspouts: at the corners of the eave walls (front and back on a
	# gable), every 12 m along the back, and on the end walls of a flat roof.
	for side in [-1.0, 1.0]:
		var z: float = cz + side * (d * 0.5 + 0.1)
		var xs := [cx - w * 0.5 + 0.4, cx + w * 0.5 - 0.4]
		if side > 0.0:
			var x := cx - w * 0.5 + 12.0
			while x < cx + w * 0.5 - 6.0:
				xs.append(x)
				x += 12.0
		for x in xs:
			if _dr_free(Vector3(x, 0, z + side * 0.3)):
				_dr_spout(Vector3(x, 0, z), h, spout, Vector3(0, 0, side), flat)
	if flat and d > 20.0:
		for end in [-1.0, 1.0]:
			if _dr_free(Vector3(cx + end * (w * 0.5 + 0.4), 0, cz + d * 0.2)):
				_dr_spout(Vector3(cx + end * (w * 0.5 + 0.1), 0, cz + d * 0.2), h, spout, Vector3(end, 0, 0), true)
	# Wall packs along the back and both ends, about every 15 m.
	var y := minf(h - 0.8, 6.0)
	var n := maxi(1, int(w / 15.0))
	for i in n:
		var p := Vector3(cx - w * 0.5 + (i + 0.5) * w / n, y, cz + d * 0.5 + 0.18)
		if _dr_free(p + Vector3(0, 0, 0.2)):
			_dr_wallpack(p, Vector3(0, 0, 1))
	for end in [-1.0, 1.0]:
		if end == hall[6]:
			continue
		var m := maxi(1, int(d / 15.0))
		for i in m:
			var p := Vector3(cx + end * (w * 0.5 + 0.18), y, cz - d * 0.5 + (i + 0.5) * d / m)
			if _dr_free(p + Vector3(end * 0.2, 0, 0)):
				_dr_wallpack(p, Vector3(end, 0, 0))
		# A man door near the front of each end wall (near the back on a
		# public building, clear of its windows), its light over it.
		var dz := cz + d * 0.5 - 1.6 if civic else cz - d * 0.5 + 3.0
		if d > 8.0 and _dr_free(Vector3(cx + end * (w * 0.5 + 0.6), 0, dz), 0.7):
			_dr_side_door(Vector3(cx + end * (w * 0.5 + 0.03), 1.05, dz), end)
	# Translucent wall lights under a metal eave, along the back.
	if not flat and h > 6.0:
		_box("paint", Vector3(w - 1.0, 0.9, 0.04), Vector3(cx, h - 0.9, cz + d * 0.5 + 0.12), Color("#dfe0d6"))


## Brick detail on a public building's walls, after Indiana schools,
## courthouses' annexes and hospitals of the 1950s-70s: a limestone water
## table at the foot, a precast band a metre under the coping, and on long blank
## stretches (gyms, stair towers, hospital ends) brick pilasters every
## 4.5 m and a high aluminium louvre. Everything keeps off windows and
## doors (_glass_log).
func _dr_brick(hall: Array) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var h: float = hall[4]
	var brick: Color = hall[8]
	var stone := Color(_pick(["#cfc6b0", "#d8d0bc", "#bdb6a6"]))
	# Each wall: a point at its left end (seen from outside), the way along
	# it, its outward normal and its length.
	var walls := [
		[Vector3(cx + w * 0.5, 0, cz - d * 0.5), Vector3(-1, 0, 0), Vector3(0, 0, -1), w],
		[Vector3(cx - w * 0.5, 0, cz + d * 0.5), Vector3(1, 0, 0), Vector3(0, 0, 1), w],
		[Vector3(cx - w * 0.5, 0, cz - d * 0.5), Vector3(0, 0, 1), Vector3(-1, 0, 0), d],
		[Vector3(cx + w * 0.5, 0, cz + d * 0.5), Vector3(0, 0, -1), Vector3(1, 0, 0), d],
	]
	for wall in walls:
		var p0: Vector3 = wall[0]
		var along: Vector3 = wall[1]
		var n: Vector3 = wall[2]
		var len: float = wall[3]
		var seg := 1.0
		var count := int(len / seg)
		if count < 2:
			continue
		var step := len / count
		var low := []  # blank at the foot (water table)
		var high := []  # blank under the coping
		var tall := []  # blank all the way up
		for i in count:
			var t0 := i * step
			var t1 := t0 + step
			var mid := p0 + along * (t0 + step * 0.5) + n * 0.4
			var outside := _dr_free(mid, 0.05)
			low.append(outside and _dr_blank(p0, along, n, t0, t1, 0.0, 0.62))
			high.append(outside and _dr_blank(p0, along, n, t0, t1, h - 1.1, h - 0.6))
			tall.append(outside and _dr_blank(p0, along, n, t0 - 0.4, t1 + 0.4, 0.0, h))
		var a2 := Basis(along, Vector3.UP, n)
		# Runs of blank segments become one band each.
		for band in [[low, 0.33, 0.62, 0.07, 0.02], [high, h - 1.0, h - 0.72, 0.06, 0.045]]:
			var flags: Array = band[0]
			var i := 0
			while i < count:
				if not flags[i]:
					i += 1
					continue
				var j := i
				while j < count and flags[j]:
					j += 1
				# Wrap 14 cm round an open corner (past the other wall's band);
				# stop 10 cm short of a window or the building next door.
				var t0 := i * step + 0.1
				var t1 := j * step - 0.1
				if i == 0 and _dr_free(p0 - along * 0.3 + n * 0.3, 0.05) and _dr_free(p0 - along * 0.3 - n * 0.3, 0.05):
					t0 = -0.14
				if j == count and _dr_free(p0 + along * (len + 0.3) + n * 0.3, 0.05) and _dr_free(p0 + along * (len + 0.3) - n * 0.3, 0.05):
					t1 = len + 0.14
				var y0: float = band[1]
				var y1: float = band[2]
				# Held off the wall (and clear of any stucco band) so no face lies in
				# another's plane.
				var c: Vector3 = p0 + along * ((t0 + t1) * 0.5) + n * (float(band[3]) * 0.5 + float(band[4])) + Vector3(0, (y0 + y1) * 0.5, 0)
				_box("concrete", Vector3(t1 - t0, y1 - y0, float(band[3])), c, stone, a2)
				i = j
		# Pilasters and a louvre on long blank stretches.
		if h < 5.0:
			continue
		var i := 0
		while i < count:
			if not tall[i]:
				i += 1
				continue
			var j := i
			while j < count and tall[j]:
				j += 1
			var run := (j - i) * step
			if run >= 9.0:
				var k := maxi(1, int(run / 4.5))
				for q in k + 1:
					var t := i * step + 0.5 + q * (run - 1.0) / k
					var c := p0 + along * t + n * 0.115 + Vector3(0, h * 0.5, 0)
					_box("brick", Vector3(0.6, h - 0.05, 0.16), c, brick.darkened(0.05), a2)
					_box("concrete", Vector3(0.72, 0.18, 0.24), p0 + along * t + n * 0.18 + Vector3(0, h - 0.35, 0), stone, a2)
				if run >= 12.0:
					var lc := p0 + along * (i * step + run * 0.5 + 2.25) + n * 0.06 + Vector3(0, h - 1.9, 0)
					_box("metal", Vector3(1.5, 1.2, 0.06), lc, Color("#9ea2a2"), a2)
					for r in 5:
						_box("metal", Vector3(1.44, 0.04, 0.06), lc + n * 0.02 + Vector3(0, -0.48 + r * 0.24, 0), Color("#7f8484"), a2)
			i = j


## Whether a stretch of wall (t0..t1 along it from p0, y0..y1 up) is clear of
## every logged window and door on that wall.
func _dr_blank(p0: Vector3, along: Vector3, n: Vector3, t0: float, t1: float, y0: float, y1: float) -> bool:
	for g in _glass_log:
		var c: Vector3 = g[0]
		if absf((c - p0).dot(n)) > 0.45:
			continue
		var right: Vector3 = g[1]
		if absf(right.normalized().dot(along)) < 0.7:
			continue  # a pane at right angles to this wall (a vestibule side)
		var t := (c - p0).dot(along)
		var hw: float = g[2] * 0.5 + 0.25
		var hh: float = g[3] * 0.5 + 0.2
		if t + hw > t0 and t - hw < t1 and c.y + hh > y0 and c.y - hh < y1:
			return false
	return true


func _dr_spout(foot: Vector3, h: float, col: Color, out: Vector3, scupper: bool) -> void:
	var o := out * 0.2  # clear of trim bands on the wall
	_box("paint", Vector3(0.12, h, 0.12), foot + o + Vector3(0, h * 0.5, 0), col)
	if scupper:
		# The conductor head under its scupper.
		_box("paint", Vector3(0.36, 0.42, 0.3), foot + o * 1.6 + Vector3(0, h - 0.5, 0), col)
	# The shoe and splash block at the foot.
	_box("paint", Vector3(0.14, 0.14, 0.14) + out.abs() * 0.22, foot + out * 0.38 + Vector3(0, 0.12, 0), col)
	_box("concrete", Vector3(0.36, 0.05, 0.36) + out.abs() * 0.3, foot + out * 0.65 + Vector3(0, 0.11, 0), FOUNDATION)


## A bronze LED wall pack on a wall facing `out`.
func _dr_wallpack(c: Vector3, out: Vector3) -> void:
	var across := Vector3(absf(out.z), 0, absf(out.x))
	_box("metal", across * 0.36 + out.abs() * 0.2 + Vector3(0, 0.3, 0), c + out * 0.04, Color("#3a3128"))
	_box("paint", across * 0.3 + out.abs() * 0.14 + Vector3(0, 0.04, 0), c + out * 0.08 + Vector3(0, -0.16, 0), Color("#f1eedf"))


## A steel man door on an end wall facing `end` along x, with its light.
func _dr_side_door(c: Vector3, end: float) -> void:
	var col := Color(_pick(["#5a5e60", "#6b6f72", "#7a2a24", "#2f3b4a"]))
	# Each layer 5 cm proud of the one behind (two-sided materials flicker).
	_box("paint", Vector3(0.06, 2.2, 1.12), c + Vector3(end * 0.07, 0.05, 0), col.darkened(0.3))
	_box("paint", Vector3(0.06, 2.1, 0.92), c + Vector3(end * 0.15, 0, 0), col)
	_box("metal", Vector3(0.05, 0.03, 0.14), c + Vector3(end * 0.21, -0.08, 0.3), Color("#a9acae"))
	_dr_wallpack(c + Vector3(end * 0.15, 1.55, 0), Vector3(end, 0, 0))
	# A concrete stoop.
	_box("concrete", Vector3(1.2, 0.12, 1.5), c + Vector3(end * 0.62, -1.0, 0), FOUNDATION)


## Gravity ridge ventilators and translucent skylight panels in a metal
## roof drawn by _metal_roof (ridge along x, rise d / 24).
func _dr_roof_gable(hall: Array) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var h: float = hall[4]
	var rise := d * 0.5 / 12.0
	var vent := Color("#b9bcbc")
	var x := cx - w * 0.5 + 4.0
	while x < cx + w * 0.5 - 3.0:
		var top := Vector3(x, h + rise + 0.05, cz)
		_cylinder("metal", top, 0.32, 0.55, vent, 10)
		_cylinder("metal", top + Vector3(0, 0.55, 0), 0.62, 0.22, vent.lightened(0.05), 12)
		x += rng.randf_range(6.0, 9.0)
	# Skylight panels, two to a bay, on both slopes.
	if d < 10.0:
		return
	var hd := d * 0.5 + 0.3
	var drop := rise * 0.3 / (d * 0.5)
	var lite := Color("#e2e4d8")
	for side in [-1.0, 1.0]:
		var e := Vector3(0, h - drop, cz + side * hd)
		var r := Vector3(0, h + rise, cz)
		var a: Vector3 = e.lerp(r, 0.25) + Vector3(0, 0.13, 0)
		var b: Vector3 = e.lerp(r, 0.7) + Vector3(0, 0.13, 0)
		x = cx - w * 0.5 + 3.0
		while x < cx + w * 0.5 - 2.0:
			_quad("paint", Vector3(x, a.y, a.z), Vector3(x + 1.0, a.y, a.z), Vector3(x + 1.0, b.y, b.z), Vector3(x, b.y, b.z),
				lite, [], Vector3(0, 1, side * 0.1))
			x += 7.5


## Rooftop units, exhaust fans and a hatch on a flat roof.
func _dr_roof_flat(hall: Array) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var h: float = hall[4]
	var area := w * d
	var unit := Color("#c3c5c2")
	var units := clampi(int(area / 260.0), 1, 10)
	for i in units:
		var p := Vector3(cx + rng.randf_range(-w * 0.38, w * 0.38), h, cz + rng.randf_range(-d * 0.3, d * 0.35))
		_box("metal", Vector3(2.6, 0.25, 1.7), p + Vector3(0, 0.13, 0), Color("#8a8c8a"))  # curb
		_box("metal", Vector3(2.4, 1.15, 1.5), p + Vector3(0, 0.82, 0), unit)
		_cylinder("paint", p + Vector3(0.6, 1.4, 0), 0.42, 0.06, Color("#2c2e30"), 12)
		_box("metal", Vector3(0.8, 0.4, 0.06), p + Vector3(-0.6, 0.8, 0.77), unit.darkened(0.2))  # its louvres
	for i in clampi(int(area / 320.0), 1, 8):
		var p := Vector3(cx + rng.randf_range(-w * 0.42, w * 0.42), h, cz + rng.randf_range(-d * 0.42, d * 0.42))
		_cylinder("metal", p, 0.3, 0.55, Color("#aeb1b0"), 10)
		_cylinder("metal", p + Vector3(0, 0.55, 0), 0.55, 0.28, Color("#b9bcbc"), 12)
	_box("metal", Vector3(0.95, 0.35, 0.95), Vector3(cx + w * 0.5 - 2.0, h + 0.18, cz + d * 0.5 - 2.0), Color("#9fa3a2"))
	# Plumbing vents.
	for i in 3:
		_cylinder("paint", Vector3(cx + rng.randf_range(-w * 0.4, w * 0.4), h, cz + rng.randf_range(-d * 0.4, d * 0.4)),
			0.06, 0.45, Color("#2c2e30"), 6)


## The meters, disconnects, gas riser and transformer, on whichever end wall
## has more room, and the FDC and Knox box by the front.
func _dr_utility(hall: Array, civic := false) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var h: float = hall[4]
	var end := 1.0 if half - (cx + w * 0.5) >= (cx - w * 0.5) + half else -1.0
	if end == hall[6]:
		end = -end
	# The service wall: the roomier end wall of a plant, or the back wall
	# near that end on a public building (its end walls have windows).
	# `out` points away from the wall, `along` runs along it.
	var base := Vector3(cx + end * (w * 0.5 + 0.1), 0, cz + d * 0.5 - 3.0)
	var out := Vector3(end, 0, 0)
	var along := Vector3(0, 0, -1)
	if civic:
		# Out on a galvanised strut rack clear of the back windows, as
		# switchgear often stands at schools and offices.
		base = Vector3(cx + end * (w * 0.5 - 2.5), 0, cz + d * 0.5 + 1.4)
		out = Vector3(0, 0, 1)
		along = Vector3(-end, 0, 0)
		if _dr_free(base, 0.6):
			for k in [-0.65, 2.35]:
				_box("metal", Vector3(0.1, 2.4, 0.1), base + along * k + Vector3(0, 1.2, 0), Color("#a9acae"))
			for y in [0.9, 2.1]:
				_box("metal", out.abs() * 0.08 + along.abs() * 3.2 + Vector3(0, 0.08, 0), base + along * 0.85 + Vector3(0, y, 0), Color("#a9acae"))
			base -= out * 0.12
	var pa := out.abs()
	var la := along.abs()
	if _dr_free(base + out * 0.4):
		var panel := Color("#b5b8b6")
		for k in 3:
			_box("metal", pa * 0.22 + la * 0.7 + Vector3(0, 0.9 if k else 1.4, 0), base + out * 0.16 + along * (k * 0.85) + Vector3(0, 1.5, 0),
				panel.darkened(0.04 * k))
		var up := 0.4 if civic else h - 2.0
		_box("metal", pa * 0.08 + la * 0.1 + Vector3(0, up, 0), base + out * 0.12 + Vector3(0, 1.9 + up * 0.5, 0), panel.darkened(0.1))  # conduit
		_box("metal", pa * 0.06 + la * 2.2 + Vector3(0, 0.06, 0), base + out * 0.12 + along * 0.9 + Vector3(0, 0.6, 0), panel.darkened(0.1))
		# The gas meter on its riser.
		var g := base + along * 3.4
		if _dr_free(g + out * 0.4):
			_box("paint", Vector3(0.08, 1.0, 0.08), g + out * 0.15 + Vector3(0, 0.5, 0), Color("#d7b42a"))
			_box("paint", pa * 0.08 + la * 0.3 + Vector3(0, 0.08, 0), g + out * 0.15 - along * 0.15 + Vector3(0, 0.95, 0), Color("#d7b42a"))
			_box("metal", pa * 0.3 + la * 0.32 + Vector3(0, 0.4, 0), g + out * 0.22 - along * 0.35 + Vector3(0, 0.9, 0), Color("#9ea2a0"))
		# The pad-mount transformer out from the wall, with bollards.
		var t := base + out * 3.2 + along * 1.2
		if _in_lot(t, 1.6) and _dr_free(t, 1.8):
			_box("concrete", Vector3(2.4, 0.15, 2.6), t + Vector3(0, 0.08, 0), FOUNDATION)
			_box("metal", Vector3(1.8, 1.45, 1.9), t + Vector3(0, 0.88, 0), Color("#55704f"))
			_box("metal", Vector3(1.9, 0.06, 2.0), t + Vector3(0, 1.62, 0), Color("#4b6446"))
			for q in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)]:
				_dr_bollard(t + q)
	# The FDC (brass Siamese on a red plate) and the Knox box by the front corner.
	var fx := cx - end * (w * 0.5 - 1.2)
	var fz := cz - d * 0.5 - 0.06
	for r: Rect2 in _masses:
		if r.grow(0.3).has_point(Vector2(fx, fz - 0.3)):
			fx = cx + end * (w * 0.5 - 2.2)  # an office in front: the other corner
	if _dr_free(Vector3(fx, 0, fz - 0.3)):
		_box("paint", Vector3(0.45, 0.35, 0.05), Vector3(fx, 0.6, fz - 0.12), Color("#a42a22"))
		_box("metal", Vector3(0.32, 0.14, 0.16), Vector3(fx, 0.6, fz - 0.22), Color("#b8952e"))
		_box("metal", Vector3(0.2, 0.25, 0.1), Vector3(fx + 0.8, 1.8, fz - 0.12), Color("#1f2224"))


## Whether a point (on the ground plan) is clear of every noted hall, so a
## wall detail never ends up inside the building next door.
func _dr_free(p: Vector3, margin := 0.05) -> bool:
	for hall in _dr_halls:
		var r := Rect2(hall[0] - hall[2] * 0.5, hall[1] - hall[3] * 0.5, hall[2], hall[3]).grow(margin)
		if r.has_point(Vector2(p.x, p.z)):
			return false
	return true


func _dr_bollard(p: Vector3) -> void:
	_cylinder("paint", p, 0.11, 1.1, Color("#e0b81e"), 8)


## Pallets, a propane cage, a roll-off and a trailer behind the main hall,
## and a chain-link fence round the back of the lot.
func _dr_yard(hall: Array) -> void:
	var cx: float = hall[0]
	var cz: float = hall[1]
	var w: float = hall[2]
	var d: float = hall[3]
	var back := cz + d * 0.5
	var room := depth - back
	# Pallet stacks along the back wall.
	var wood := Color("#9c8463")
	var stacks := rng.randi_range(2, 5)
	for i in stacks:
		var p := Vector3(cx - w * 0.5 + 2.0 + i * 1.6, 0, back + 1.4)
		if not _in_lot(p, 1.0) or room < 3.0:
			break
		var n := rng.randi_range(4, 14)
		for k in n:
			_box("paint", Vector3(1.2, 0.13, 1.0), p + Vector3(0, 0.07 + k * 0.145, 0), wood.darkened(0.06 * (k % 2)))
	# The forklift propane cage: steel mesh round racked 33 lb cylinders.
	var pc := Vector3(cx + w * 0.5 - 2.5, 0, back + 1.1)
	if _in_lot(pc, 1.0) and room > 2.5:
		_box("chain", Vector3(1.6, 1.8, 0.9), pc + Vector3(0, 0.9, 0), Color("#a9acae"))
		_box("metal", Vector3(1.66, 0.05, 0.96), pc + Vector3(0, 1.82, 0), Color("#8a8c8e"))
		for k in 4:
			_cylinder("paint", pc + Vector3(-0.55 + k * 0.37, 0.2 + (k % 2) * 0.85, 0), 0.16, 0.7, Color("#d0d2d0"), 8)
	# A roll-off container.
	if room > 6.0:
		var ro := Vector3(cx + rng.randf_range(-w * 0.2, w * 0.2), 0, minf(back + 4.5, depth - 2.0))
		if _in_lot(ro, 3.6):
			var col := Color(_pick(["#2a3a5a", "#2f4a3a", "#7a2a24", "#5a5e60"]))
			_box("metal", Vector3(6.6, 1.7, 2.4), ro + Vector3(0, 1.0, 0), col)
			_box("metal", Vector3(6.7, 0.12, 2.5), ro + Vector3(0, 1.88, 0), col.darkened(0.2))
			for s in [-1.0, 1.0]:
				_box("metal", Vector3(6.6, 0.15, 0.12), ro + Vector3(0, 0.12, s * 1.0), Color("#2a2b2c"))
	# A 53 ft trailer parked down the widest side yard.
	var left := (cx - w * 0.5) + half
	var right := half - (cx + w * 0.5)
	var side := 1.0 if right >= left else -1.0
	if side == hall[6]:
		side = -side
	if maxf(left, right) > 5.0 and d > 17.0:
		var tx := cx + side * (w * 0.5 + 2.6)
		var tz := cz + 0.5
		if _in_lot(Vector3(tx, 0, tz), 1.5):
			_dr_trailer(Vector3(tx, 0, tz))
	# 6 ft chain link with barbed wire from the hall back round the yard.
	if room > 4.0:
		var z0 := cz - d * 0.5 + 2.0
		var zb := depth - 0.6
		_dr_fence(Vector2(-half + 0.4, z0), Vector2(-half + 0.4, zb))
		_dr_fence(Vector2(-half + 0.4, zb), Vector2(half - 0.4, zb))
		_dr_fence(Vector2(half - 0.4, zb), Vector2(half - 0.4, z0))


## A 53 ft dry van (16.2 x 2.6 x 4.1 m) standing on its landing gear, its
## length along z, nose to the street.
func _dr_trailer(at: Vector3) -> void:
	var body := Color(_pick(["#eeeeea", "#e6e6e0", "#d9dcdc", "#c8ccd0"]))
	# In two lifts, so it isn't taken for a building mass (_box).
	for k in 2:
		_box("metal", Vector3(2.6, 1.375, 16.2), at + Vector3(0, 1.32 + 0.6875 + k * 1.375, 0), body)
	_box("metal", Vector3(2.62, 0.12, 16.22), at + Vector3(0, 4.12, 0), body.darkened(0.08))
	# Rear doors, the bogie and the landing gear.
	_box("metal", Vector3(2.5, 2.6, 0.06), at + Vector3(0, 2.7, 8.16), body.darkened(0.12))
	for z in [5.6, 6.9]:
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.62, 1.0, 1.0), at + Vector3(s * 0.95, 0.5, z), Color("#1c1d1f"))
	for s in [-1.0, 1.0]:
		_box("metal", Vector3(0.12, 1.25, 0.12), at + Vector3(s * 0.9, 0.62, -4.8), Color("#3a3c3e"))
	_box("paint", Vector3(2.4, 0.3, 14.0), at + Vector3(0, 1.17, 0.6), Color("#2a2b2c"))  # frame rails


func _dr_fence(a: Vector2, b: Vector2) -> void:
	var p := Vector3(a.x, 0, a.y)
	var q := Vector3(b.x, 0, b.y)
	var len := p.distance_to(q)
	if len < 0.5:
		return
	var dir := (q - p) / len
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var galv := Color("#a9acae")
	var n := maxi(1, int(len / 3.0))
	for k in n + 1:
		_box("metal", Vector3(0.06, 2.1, 0.06), p + dir * (len * k / n) + Vector3(0, 1.05, 0), galv)
	_box("metal", Vector3(0.045, 0.045, len), (p + q) * 0.5 + Vector3(0, 1.85, 0), galv, yaw)
	# The fabric hangs on the outside of the posts, clear of them.
	var out := Vector3(dir.z, 0, -dir.x) * 0.06
	_box("chain", Vector3(0.006, 1.8, len), (p + q) * 0.5 + out + Vector3(0, 0.95, 0), galv, yaw)
	for k in 3:
		_box("metal", Vector3(0.015, 0.015, len), (p + q) * 0.5 - out * 0.5 + Vector3(0, 1.95 + k * 0.1, 0), Color("#55585a"), yaw)
