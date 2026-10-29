class_name FactoryBuilder
extends CommercialBuilder
## A factory that looks like the work it does: one design per factory chain
## (Balance.FACTORY_CHAINS), benchmarked against photos of real plants in
## Indiana, Illinois and Iowa:
##   - mill: a country grain elevator and feed mill. Slip-formed concrete
##     silos in a row with the headhouse on top, corrugated steel bins, a
##     drive-through dump shed and a truck scale
##   - sawmill: a hardwood sawmill. Log deck, a long open-sided mill shed,
##     a dry kiln, stickered lumber stacks and a sawdust pile
##   - refinery (plastics plant): a compounding plant. White storage tanks,
##     a pipe rack, a tall blending tower and a tanker loading canopy
##   - metal: a metal fabricator. Long high-bay steel building with a roof
##     monitor, an outdoor gantry crane over a yard of steel coils
##   - general: the metal building with silos or a stack (CommercialBuilder),
##     a tilt-up concrete plant with dock doors, an old multi-storey brick
##     works with a smokestack and a rooftop water tank, a sawtooth-roof
##     brick shop, or a machine shop in a steel Quonset hut
## Same local space and output as HouseBuilder (-z faces the street).

const CONCRETE := Color("#cfcac0")
const STEEL_BIN := Color("#c4c7c6")
const BARK := Color("#5e4632")
const LOG_END := Color("#c9a879")
const LUMBER := Color("#d9c59b")
const SAWDUST := Color("#b8955f")
const TANK_WHITE := Color("#e4e4df")
const PIPE := Color("#8a8f93")
const CRANE := Color("#d9a521")
const COIL := Color("#8f9397")


static func build_chain(chain: String, seed: int, to_curb: float, lot := {}, spec := {}) -> Array:
	var b := FactoryBuilder.new()
	b.sign_spec = spec
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	match chain:
		"mill": b._mill(to_curb)
		"sawmill": b._sawmill(to_curb)
		"refinery": b._plastics(to_curb)
		"metal": b._metal_works(to_curb)
		_:
			match b.rng.randi() % 5:
				0: b._factory(to_curb)
				1: b._tilt_up(to_curb)
				2: b._brick_works(to_curb)
				3: b._sawtooth(to_curb)
				_: b._quonset_shop(to_curb)
	b._expand(chain)
	b._service_yard(true, false, INF)
	b._dress()
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels]


# ------------------------------------------------------------ shared parts

## The plant's front office: a small brick box with windows and a sign,
## its parking in front and the drive in from the street at `dx`.
func _front(zf: float, x0: float, dx: float, to_curb: float) -> void:
	var ow := rng.randf_range(6.0, 8.0)
	var od := 6.0
	var ox := x0 + ow * 0.5
	var brick := Color(_pick(FACADE_BRICK))
	_box("brick", Vector3(ow, 3.4, od), Vector3(ox, 1.7, zf - od * 0.5), brick)
	_box("paint", Vector3(ow + 0.15, 0.12, od + 0.15), Vector3(ox, 3.44, zf - od * 0.5), Color("#cfcbc2"))
	for i in 2:
		_glass(Vector3(ox - ow * 0.25 + i * ow * 0.5, 1.75, zf - od - 0.02), Vector3(-1, 0, 0), ow * 0.4, 1.5, 0.3)
	_sign(Vector3(ox, 2.6, zf - od - 0.05), ow * 0.7, 0.55)
	_flat_rect("asphalt", x0, x0 + ow + 6.0, 0.0, zf - od - 0.5, 0.06)
	var x := x0 + 0.2
	while x <= x0 + ow + 6.0:
		_flat_rect("line", x - 0.06, x + 0.06, 0.0, 5.5, 0.07, LINE)
		x += 2.75
	_curb_cut(dx, 3.6, -to_curb, zf)


## Gravel over the working yard behind the street setback.
func _yard_gravel(z0: float) -> void:
	if depth > z0 + 1.0:
		_flat_rect("gravel", -half + 0.4, half - 0.4, z0, depth - 0.5, 0.04, GRAVEL)


## A metal building with a low gable roof and a darker wainscot.
func _hall(cx: float, cz: float, w: float, d: float, h: float, wall: Color) -> void:
	var band := Color(_pick(WAINSCOT))
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(cx, 0.15, cz), FOUNDATION)
	_box("metal", Vector3(w, h - 0.3, d), Vector3(cx, 0.3 + (h - 0.3) * 0.5, cz), wall)
	_box("metal", Vector3(w + 0.04, 1.1, d + 0.04), Vector3(cx, 0.85, cz), band)
	_metal_roof(cx, cz, h, w, d, wall.darkened(0.1))
	_dr_note(cx, cz, w, d, h, "gable")


## Buildings _dr_note doesn't dress (a quonset): [cx, cz, w, d, h].
var _foot := []


## A plant on a lot bigger than its first hall (a wide parcel, or one it
## has grown into) builds additions until it covers about a third of the
## land, as Midwest plants do: each a hall of a later era behind or beside
## the first, with dock doors on a shared truck court, trailers backed in
## and a row of trailers dropped along the back fence. Lots the first hall
## already fills are left as they are.
func _expand(chain: String) -> void:
	var halls: Array = _dr_halls + _foot
	# A sawmill grows its log yard instead (_log_yard).
	if halls.is_empty() or chain == "sawmill":
		return
	var area := 2.0 * half * depth
	var built := 0.0
	var box := Rect2()
	for i in halls.size():
		var hl: Array = halls[i]
		var r := Rect2(hl[0] - hl[2] * 0.5, hl[1] - hl[3] * 0.5, hl[2], hl[3])
		box = r if i == 0 else box.merge(r)
		built += hl[2] * hl[3]
	if built >= area * 0.3 or area < 4500.0:
		return
	var zf := box.position.y
	var eave: float = halls[0][4]
	var adds := 0
	while built < area * 0.36 and adds < 3:
		var used := box.grow(8.0)
		# The free bands round what is built: right, left and behind.
		var bands := [Rect2(Vector2(used.end.x, zf), Vector2(half - 2.0 - used.end.x, depth - 3.0 - zf)),
			Rect2(Vector2(-half + 2.0, zf), Vector2(used.position.x - (-half + 2.0), depth - 3.0 - zf)),
			Rect2(Vector2(-half + 2.0, used.end.y), Vector2(2.0 * half - 4.0, depth - 3.0 - used.end.y))]
		var best := Rect2()
		for band in bands:
			if band.size.x >= 20.0 and band.size.y >= 40.0 and band.get_area() > best.get_area():
				best = band
		# On a shallow lot (the 60 m industrial plat) there's no room for a
		# truck court too: a production wing goes up beside the hall, flush
		# with its front and joined by a link, its doors at grade.
		var wing := false
		if best.get_area() <= 0.0:
			for band in bands.slice(0, 2):
				if band.size.x >= 20.0 and band.size.y >= 26.0 and band.get_area() > best.get_area():
					best = band
					wing = true
		if best.get_area() <= 0.0:
			break
		# The hall at the back of its band, a truck court in front of it.
		var court := 0.0 if wing else 22.0
		var w := minf(best.size.x, 90.0 if not wing else 60.0)
		var d := minf(best.size.y - (6.0 if wing else 22.0), 70.0)
		var cx := best.position.x + w * 0.5 if best.position.x > box.end.x - 1.0 else best.end.x - w * 0.5
		if best.position.y >= box.end.y:
			cx = clampf(box.get_center().x, -half + 2.0 + w * 0.5, half - 2.0 - w * 0.5)
		var z0 := best.position.y + court
		var corners := [Vector3(cx - w * 0.5, 0, z0), Vector3(cx + w * 0.5, 0, z0), Vector3(cx - w * 0.5, 0, z0 + d),
			Vector3(cx + w * 0.5, 0, z0 + d)]
		if corners.any(func(c): return not _in_lot(c, 1.0)):
			break
		var h := maxf(eave, 8.0) + rng.randf_range(0.5, 2.5)
		_plant_addition(chain, cx, z0, w, d, h, adds, not wing)
		if wing:
			# The link back to the hall: a low enclosed passage.
			var right := cx > box.get_center().x
			var lx0: float = box.end.x if right else cx + w * 0.5
			var lx1: float = cx - w * 0.5 if right else box.position.x
			_box("paint", Vector3(lx1 - lx0 + 0.6, 5.0, 9.0), Vector3((lx0 + lx1) * 0.5, 2.5, z0 + 9.0), CONCRETE.darkened(0.12))
		var r := Rect2(cx - w * 0.5, z0, w, d)
		box = box.merge(r)
		built += w * d
		adds += 1
	if adds > 0 and depth - box.end.y > 10.0:
		# Trailers dropped along the back fence, waiting for a tractor.
		var n := int((2.0 * half - 12.0) / 4.0)
		for i in mini(n, 12):
			if rng.randf() < 0.65:
				_dr_trailer(Vector3(-half + 6.0 + i * 4.0, 0, depth - 10.5))


## One addition: a tilt-up concrete hall (the 1990s on) or a metal one,
## dock doors with seals across its front on a concrete truck court, some
## with a trailer backed in.
func _plant_addition(chain: String, cx: float, z0: float, w: float, d: float, h: float, k: int, docks_out := true) -> void:
	var cz := z0 + d * 0.5
	if chain == "mill" or (k + rng.randi()) % 2 == 0:
		var panel := CONCRETE.darkened(rng.randf_range(0.0, 0.08))
		_box("paint", Vector3(w, h, d), Vector3(cx, h * 0.5, cz), panel)
		_box("paint", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(cx, h + 0.25, cz), panel.darkened(0.06))
		var x := cx - w * 0.5 + 7.5
		while x < cx + w * 0.5:
			_box("paint", Vector3(0.05, h - 0.2, 0.1), Vector3(x, h * 0.5 - 0.1, z0 - 0.05), panel.darkened(0.25))
			x += 7.5
		_box("paint", Vector3(w + 0.24, 0.6, d + 0.24), Vector3(cx, h - 1.2, cz), Color(_pick(WAINSCOT)))
		_dr_note(cx, cz, w, d, h, "flat", 1.0)
	else:
		_hall(cx, cz, w, d, h, Color(_pick(METAL_WALL)))
	# The truck court and the docks: a door every 4.3 m (12 ft centres).
	# A wing has grade-level doors onto a short apron instead.
	var docks := clampi(int((w - 8.0) / 4.3), 2, 16) if docks_out else 0
	if docks_out:
		_flat_rect("drive", cx - w * 0.5, cx + w * 0.5, z0 - 20.0, z0, 0.08)
	else:
		_flat_rect("drive", cx - w * 0.5, cx + w * 0.5, z0 - 7.0, z0, 0.08)
		for i in 2:
			_door(cx + (i - 0.5) * w * 0.45, z0)
	for i in docks:
		var x := cx - (docks - 1) * 2.15 + i * 4.3
		# The door shows in the dark foam seal that stands out round it.
		_box("paint", Vector3(3.2, 3.4, 0.3), Vector3(x, 2.4, z0 - 0.16), Color("#2a2a2c"))
		_box("siding", Vector3(2.7, 3.0, 0.08), Vector3(x, 2.4, z0 - 0.36), Color(TRIM, 0.0))
		_box("paint", Vector3(2.4, 0.15, 0.6), Vector3(x, 1.2, z0 - 0.4), Color("#d6b13a"))
		if rng.randf() < 0.45:
			_dr_trailer(Vector3(x, 0, z0 - 8.4))
	# Outdoor storage of what this plant makes, along the side.
	var sx := cx + w * 0.5 - 3.0
	match chain:
		"metal":
			for i in 5:
				_tank_coil(Vector3(sx - i * 2.4, 0, z0 - 2.0 - (i % 2) * 2.2))
		"refinery":
			for i in 3:
				_cylinder("metal", Vector3(cx - w * 0.5 + 3.0 + i * 4.2, 0, z0 + d + 3.0), 1.8, h + 6.0, Color("#d8d8d2"), 14)
		"mill":
			for i in 3:
				_cylinder("metal", Vector3(cx - w * 0.5 + 4.0 + i * 6.5, 0, z0 + d + 4.0), 3.0, h + 8.0, Color("#c9cbc8"), 18)
		_:
			for i in 4:
				var p := Vector3(sx - i * 1.4, 0, z0 - 1.2)
				for j in rng.randi_range(2, 5):
					_box("paint", Vector3(1.2, 0.14, 1.0), p + Vector3(0, 0.07 + j * 0.15, 0), Color("#a07c52"))


## A steel coil on its side in a cradle, as stacked outside a metal works.
func _tank_coil(p: Vector3) -> void:
	_box("paint", Vector3(1.6, 0.3, 0.6), p + Vector3(0, 0.15, 0), Color("#5a4632"))
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		var c := p + Vector3(0, 0.95, 0)
		var p0 := c + Vector3(cos(a0) * 0.85, sin(a0) * 0.85, 0)
		var p1 := c + Vector3(cos(a1) * 0.85, sin(a1) * 0.85, 0)
		_quad("metal", p0 + Vector3(0, 0, -0.75), p1 + Vector3(0, 0, -0.75), p1 + Vector3(0, 0, 0.75), p0 + Vector3(0, 0, 0.75),
			Color("#8a8f92"), [], (p0 + p1) * 0.5 - c)
		for s in [-0.75, 0.75]:
			_tri("metal", c + Vector3(0, 0, s), p0 + Vector3(0, 0, s), p1 + Vector3(0, 0, s), Color("#6f7476"), [], Vector3(0, 0, signf(s)))


## An overhead door on a wall facing -z at (x, z).
func _door(x: float, z: float, w := 3.7, h := 4.3) -> void:
	_box("siding", Vector3(w, h, 0.08), Vector3(x, 0.3 + h * 0.5, z - 0.03), Color(TRIM, 0.0))


## A cone roof (bins, piles) from a base circle up to a point.
func _cone_top(base: Vector3, r: float, rise: float, col: Color, mat := "metal", segs := 16) -> void:
	var top := base + Vector3(0, rise, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		_tri(mat, p0, p1, top, col, [], ((p0 + p1) * 0.5 - base).normalized() + Vector3.UP)


## How far back the lot goes, capped to keep a plant to a sensible size.
func _yard_back(zmin: float) -> float:
	return clampf(depth - 2.0, zmin, 140.0)


# ------------------------------------------------------------ the designs

## Country elevator and feed mill.
func _mill(to_curb: float) -> void:
	var zf := rng.randf_range(10.0, 12.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	# The silo row along the side of the lot, headhouse on top.
	var n := clampi(int((half * 2.0 - 30.0) / 7.0), 2, 6)
	var r := 3.2
	var sh := rng.randf_range(26.0, 34.0)
	var sx0 := half - 2.0 - r - (n - 1) * 6.6
	var sz := zf + 14.0
	for i in n:
		_cylinder("paint", Vector3(sx0 + i * 6.6, 0, sz), r, sh, CONCRETE, 18)
	# Silos stand touching; the gaps between them are concrete too.
	_box("paint", Vector3((n - 1) * 6.6, sh - 0.3, 3.4), Vector3(sx0 + (n - 1) * 3.3, (sh - 0.3) * 0.5, sz), CONCRETE.darkened(0.04))
	_box("paint", Vector3(6.0, 9.0, 6.0), Vector3(sx0 + (n - 1) * 6.6, sh + 4.55, sz), CONCRETE.darkened(0.02))
	_box("metal", Vector3(6.4, 0.4, 6.4), Vector3(sx0 + (n - 1) * 6.6, sh + 9.3, sz), Color("#8e9aa3"))
	# What stands on the ground, so later additions keep clear of it.
	_foot.append([sx0 + (n - 1) * 3.3, sz - 4.0, (n - 1) * 6.6 + 2.0 * r, 2.0 * r + 8.0, 10.0])
	# Steel bins behind, cone roofs.
	var bins := rng.randi_range(1, 3)
	for i in bins:
		var c := Vector3(sx0 + i * 13.0, 0, sz + 15.0)
		if _in_lot(c, 7.0):
			_cylinder("metal", c, 6.0, 11.0, STEEL_BIN, 24)
			_cone_top(c + Vector3(0, 11.0, 0), 6.2, 3.2, STEEL_BIN.lightened(0.08))
			_foot.append([c.x, c.z, 12.0, 12.0, 10.0])
	# The mill building beside the silos, the dump shed in front of them.
	var mw := rng.randf_range(16.0, 20.0)
	_hall(sx0 - r - 3.0 - mw * 0.5, sz + 2.0, mw, 18.0, 10.0, Color(_pick(METAL_WALL)))
	_door(sx0 - r - 3.0 - mw * 0.5, sz - 7.0)
	var dx := sx0 + (n - 1) * 3.3
	for p in [Vector3(-4.5, 0, -3.0), Vector3(4.5, 0, -3.0), Vector3(-4.5, 0, 3.0), Vector3(4.5, 0, 3.0)]:
		_box("paint", Vector3(0.3, 6.0, 0.3), Vector3(dx, 3.0, sz - 8.0) + p, PIPE)
	_box("metal", Vector3(10.0, 0.3, 7.0), Vector3(dx, 6.1, sz - 8.0), STEEL_BIN.darkened(0.15))
	# Truck scale on the way in.
	_flat_rect("drive", dx - 1.8, dx + 1.8, zf - 2.0, zf + 20.0 - 14.0, 0.09)


## Hardwood sawmill.
func _sawmill(to_curb: float) -> void:
	var zf := rng.randf_range(10.0, 12.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var back := _yard_back(zf + 40.0)
	# The open-sided mill shed across the lot: roof on posts.
	var sw := clampf(half * 2.0 - 30.0, 24.0, 48.0)
	var sx := half - 2.0 - sw * 0.5
	var sz := zf + 16.0
	var roof := Color(_pick(METAL_WALL)).darkened(0.1)
	var x := sx - sw * 0.5
	while x <= sx + sw * 0.5 + 0.1:
		for z in [sz - 6.5, sz + 6.5]:
			_box("paint", Vector3(0.3, 7.0, 0.3), Vector3(x, 3.5, z), PIPE)
		x += 6.0
	_metal_roof(sx, sz, 7.0, sw, 13.0, roof)
	_box("metal", Vector3(sw * 0.3, 5.0, 12.0), Vector3(sx + sw * 0.32, 2.8, sz), Color(_pick(METAL_WALL)))  # the saw house
	# Log deck behind: logs lying in long stacks.
	for row in 3:
		var z: float = sz + 12.0 + row * 4.0
		if z > back:
			break
		for layer in 3 - row % 2:
			for k in 6 - layer:
				var lx := sx - sw * 0.5 + 2.0 + k * 1.2 + layer * 0.6
				_box("paint", Vector3(0.9, 0.9, 7.5), Vector3(lx, 0.45 + layer * 0.8, z), BARK)
				_box("paint", Vector3(0.75, 0.75, 0.05), Vector3(lx, 0.45 + layer * 0.8, z - 3.81), LOG_END)
	# Stickered lumber stacks on the other side, a dry kiln and the sawdust pile.
	for k in 4:
		var c := Vector3(sx - sw * 0.5 + 4.0 + k * 3.6, 0, sz - 12.0)
		if _in_lot(c, 2.5):
			for layer in 4:
				_box("paint", Vector3(2.4, 0.42, 4.8), c + Vector3(0, 0.25 + layer * 0.5, 0), LUMBER)
				_box("paint", Vector3(2.5, 0.08, 4.9), c + Vector3(0, 0.5 + layer * 0.5, 0), LUMBER.darkened(0.35))
	var kx := sx + sw * 0.5 - 6.0
	var kz := minf(sz + 18.0, back - 6.0)
	_hall(kx, kz, 10.0, 12.0, 6.5, Color("#c9cbc8"))
	_door(kx - 2.2, kz - 6.0, 4.0, 4.6)
	_door(kx + 2.2, kz - 6.0, 4.0, 4.6)
	_cone_top(Vector3(sx + sw * 0.5 + 6.0, 0.0, sz), 5.0, 4.0, SAWDUST, "paint", 14)
	_log_yard(sx - sw * 0.5 - 4.0, zf + 4.0, back)


## A grown sawmill's log yard: on a wide lot the logs bought ahead for the
## winter (when the woods are too wet to log, mills stock months of logs)
## lie in long decks across the yard, a loader's lane between rows, and
## more stickered lumber air-drying by the shed. Hardwood mills in
## southern Indiana keep 5-10 acre yards.
func _log_yard(x1: float, z0: float, back: float) -> void:
	var x0 := -half + 3.0
	if x1 - x0 < 18.0:
		return
	var z := z0
	var row := 0
	while z + 7.5 <= back:
		var x := x1 - 9.0
		while x - 8.0 >= x0:
			if (row + int(x)) % 7 != 0:
				_log_deck(Vector3(x, 0, z + 3.75), rng.randi_range(2, 4))
			x -= 18.0
		z += 13.0
		row += 1
	# Lumber air-drying under tin, nearest the mill.
	for k in 3:
		var c := Vector3(x1 - 4.0 - k * 3.4, 0, back - 4.0)
		if _in_lot(c, 3.0):
			for layer in 5:
				_box("paint", Vector3(2.4, 0.42, 4.8), c + Vector3(0, 0.25 + layer * 0.5, 0), LUMBER)
				_box("paint", Vector3(2.5, 0.08, 4.9), c + Vector3(0, 0.5 + layer * 0.5, 0), LUMBER.darkened(0.35))
			_box("metal", Vector3(2.9, 0.05, 5.2), c + Vector3(0, 2.85, 0), Color("#8a8f92"))


## One deck of logs 7.5 m long, `high` layers, 16 m along the row: the pile
## as one bark mass with log ends showing on its face.
func _log_deck(c: Vector3, high: int) -> void:
	var hgt := high * 0.8
	_box("paint", Vector3(15.0, hgt, 7.4), c + Vector3(0, hgt * 0.5, 0), BARK)
	for layer in high:
		var y := 0.45 + layer * 0.8
		var k := -7.0 + (layer % 2) * 0.5
		while k < 7.0:
			_box("paint", Vector3(0.72, 0.72, 0.05), c + Vector3(k, y, -3.75), LOG_END)
			k += 1.6


## Plastics compounding plant.
func _plastics(to_curb: float) -> void:
	var zf := rng.randf_range(10.0, 12.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var hw := clampf(half * 2.0 - 34.0, 20.0, 40.0)
	var hx := x0 + 16.0 + hw * 0.5
	var hz := zf + 12.0
	_hall(hx, hz, hw, 22.0, 11.0, Color(_pick(METAL_WALL)))
	_door(hx + hw * 0.25, hz - 11.0)
	# The blending tower rising out of the hall.
	_box("metal", Vector3(6.0, 22.0, 6.0), Vector3(hx - hw * 0.3, 11.0, hz + 4.0), Color("#d8d6cf"))
	_box("metal", Vector3(6.4, 0.3, 6.4), Vector3(hx - hw * 0.3, 22.1, hz + 4.0), Color("#8e9aa3"))
	# Tank farm beside it, joined by a pipe rack.
	var tx := minf(hx + hw * 0.5 + 8.0, half - 6.0)
	var tanks := rng.randi_range(3, 5)
	for i in tanks:
		var c := Vector3(tx, 0, hz - 6.0 + i * 8.5)
		if _in_lot(c, 4.0):
			var h := rng.randf_range(8.0, 12.0)
			_cylinder("paint", c, 3.4, h, TANK_WHITE, 18)
			_cone_top(c + Vector3(0, h, 0), 3.5, 0.6, TANK_WHITE.darkened(0.06), "paint")
	var rz := hz - 6.0
	var rx0 := hx + hw * 0.5
	for k in 3:
		var px := rx0 + k * (tx - 4.0 - rx0) / 2.0
		_box("paint", Vector3(0.3, 5.0, 0.3), Vector3(px, 2.5, rz - 1.0), PIPE)
		_box("paint", Vector3(0.3, 5.0, 0.3), Vector3(px, 2.5, rz + 1.0), PIPE)
	for p in 3:
		_box("paint", Vector3(tx - 4.0 - rx0, 0.35, 0.35), Vector3((rx0 + tx - 4.0) * 0.5, 5.2, rz - 0.7 + p * 0.7), PIPE.lightened(0.1))
	# Tanker loading canopy out front of the tanks.
	_box("metal", Vector3(8.0, 0.3, 6.0), Vector3(tx, 6.0, hz - 16.0), Color("#c9cbc8"))
	for p in [Vector3(-3.6, 0, -2.6), Vector3(3.6, 0, -2.6), Vector3(-3.6, 0, 2.6), Vector3(3.6, 0, 2.6)]:
		_box("paint", Vector3(0.3, 6.0, 0.3), Vector3(tx, 3.0, hz - 16.0) + p, PIPE)
	_resin_yard(hx, hz + 11.0, hw)


## Behind a compounding plant: the resin silos (slender aluminium bins on
## legs with cone bottoms, filled from bulk trucks and railcars by
## pneumatic lines run up their sides and over to the hall), a baghouse
## dust collector, and a small cooling tower for the strand water baths.
func _resin_yard(hx: float, zb: float, hw: float) -> void:
	var r := RandomNumberGenerator.new()  # its own, so the builder's draws don't move
	r.seed = hash([rng.seed, "resin yard"])
	var alu := Color("#c9ccce")
	var z := zb + 6.0
	if not _in_lot(Vector3(hx, 0, z + 3.0), 2.0):
		return
	var n := clampi(int(hw / 6.0), 2, 5)
	var x0 := hx - (n - 1) * 3.0
	var tall := r.randf_range(13.0, 17.0)
	for i in n:
		var c := Vector3(x0 + i * 6.0, 0, z)
		var rad := 1.8
		var leg := 4.5
		for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_box("paint", Vector3(0.25, leg, 0.25), c + Vector3(e.x * 1.25, leg * 0.5, e.y * 1.25), PIPE)
		_cylinder("metal", c + Vector3(0, leg, 0), rad, tall, alu, 16)
		_cone_top(c + Vector3(0, leg + tall, 0), rad + 0.05, 0.7, alu.darkened(0.05))
		var segs := 12
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := c + Vector3(cos(a0) * rad, leg, sin(a0) * rad)
			var p1 := c + Vector3(cos(a1) * rad, leg, sin(a1) * rad)
			_tri("metal", p0, p1, c + Vector3(0, leg - 2.2, 0), alu.darkened(0.12), [],
				Vector3(cos((a0 + a1) * 0.5), -0.8, sin((a0 + a1) * 0.5)))
		# Fill line up the side and the rotary valve under the cone.
		_box("paint", Vector3(0.14, tall, 0.14), c + Vector3(rad + 0.2, leg + tall * 0.5, 0), PIPE.lightened(0.1))
		_box("paint", Vector3(0.5, 0.5, 0.5), c + Vector3(0, leg - 2.4, 0), Color("#3d5a7a"))
		# Ladder cage to the roof walkway.
		_box("paint", Vector3(0.5, tall, 0.05), c + Vector3(0, leg + tall * 0.5, -rad - 0.3), PIPE)
	# The roof catwalk across the silos, and the conveying line to the hall.
	var top := 4.5 + tall + 0.3
	_box("paint", Vector3((n - 1) * 6.0 + 2.0, 0.12, 0.9), Vector3(hx, top, z), PIPE)
	_box("paint", Vector3(0.18, 0.18, 7.0), Vector3(hx, top - 1.0, z - 3.5 - 1.0), PIPE.lightened(0.1))
	# Baghouse dust collector: a box on legs with a hopper, a fan and stack.
	var bx: float = x0 - 6.0
	if _in_lot(Vector3(bx, 0, z), 2.5):
		_box("paint", Vector3(0.2, 3.0, 0.2), Vector3(bx - 1.0, 1.5, z - 1.0), PIPE)
		_box("paint", Vector3(0.2, 3.0, 0.2), Vector3(bx + 1.0, 1.5, z + 1.0), PIPE)
		_box("metal", Vector3(2.6, 4.0, 2.6), Vector3(bx, 5.0, z), Color("#9aa3a8"))
		_box("metal", Vector3(1.6, 1.2, 1.6), Vector3(bx, 2.6, z), Color("#8a9399"))
		_cylinder("metal", Vector3(bx + 1.6, 0, z), 0.25, 9.0, PIPE, 8)
	# A small induced-draft cooling tower on a basin.
	var cx: float = x0 + n * 6.0
	if _in_lot(Vector3(cx, 0, z), 3.0):
		_box("paint", Vector3(4.2, 0.6, 4.2), Vector3(cx, 0.3, z), CONCRETE)
		_box("metal", Vector3(3.6, 3.4, 3.6), Vector3(cx, 2.3, z), Color("#5f7f8f"))
		_cylinder("metal", Vector3(cx, 4.0, z), 1.3, 0.9, Color("#5f7f8f").darkened(0.15), 12)


## Metal fabricator.
func _metal_works(to_curb: float) -> void:
	var zf := rng.randf_range(10.0, 12.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var hw := clampf(half * 2.0 - 22.0, 22.0, 70.0)
	var hd := clampf(depth - zf - 22.0, 20.0, 36.0)
	var hx := x0 + 10.0 + hw * 0.5
	var hz := zf + hd * 0.5
	var wall := Color(_pick(["#8e9aa3", "#a7aba9", "#6f7b86", "#b9b4a6"]))
	_hall(hx, hz, hw, hd, rng.randf_range(13.0, 16.0), wall)
	# Roof monitor along the ridge (high-bay daylight and fume vents).
	_box("metal", Vector3(hw * 0.8, 2.0, 3.0), Vector3(hx, 15.5, hz), wall.darkened(0.12))
	for i in 2:
		_door(hx - hw * 0.25 + i * hw * 0.5, hz - hd * 0.5, 5.0, 6.0)
	# Gantry crane over the coil yard behind.
	var yz := hz + hd * 0.5 + 9.0
	if yz + 6.0 < depth:
		_gantry(Vector3(hx, 0, yz), 24.0, 9.6)
		for i in 8:
			for j in 2:
				_cylinder("metal", Vector3(hx - 9.0 + i * 2.5, 0, yz - 2.0 + j * 4.0), 0.9, 1.5, COIL, 12)
				# The coil's eye, stored eye-to-sky on its end.
				_cylinder("paint", Vector3(hx - 9.0 + i * 2.5, 0, yz - 2.0 + j * 4.0), 0.3, 1.52, Color("#3a3c3e"), 8)


## An outdoor single-girder gantry crane (a 10-15 ton yard crane, as at
## steel service centres): an A-frame of two raked legs at each end on a
## sill beam with wheel trucks running on rails, an I-beam girder across,
## and the hoist trolley under it with its hook block. `c` is the middle
## at ground level, `span` the leg spacing, `h` the girder's underside.
func _gantry(c: Vector3, span: float, h: float) -> void:
	var dark := Color("#2b2f33")
	var r := RandomNumberGenerator.new()  # its own, so the builder's draws don't move
	r.seed = hash([rng.seed, "gantry"])
	for side in [-1.0, 1.0]:
		var x: float = c.x + side * span * 0.5
		# The rails it travels on, along the yard.
		_box("paint", Vector3(0.12, 0.14, 16.0), Vector3(x, 0.07, c.z), Color("#6f7476"))
		_box("paint", Vector3(0.7, 0.7, 11.0), Vector3(x, 0.75, c.z), CRANE)
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.9, 0.9, 1.2), Vector3(x, 0.45, c.z + e * 5.2), dark)  # wheel truck
			UpgradeKits._strut(self, Vector3(x, 1.1, c.z + e * 4.6), Vector3(x, h - 0.2, c.z + e * 0.5), 0.55, CRANE)
		UpgradeKits._strut(self, Vector3(x, h * 0.45, c.z - 2.6), Vector3(x, h * 0.45, c.z + 2.6), 0.3, CRANE)
		_box("paint", Vector3(1.2, 0.8, 1.6), Vector3(x, h - 0.1, c.z), CRANE)  # end truck
	# The girder: a deep I-beam (flanges and web), bumpers at the ends.
	var gl := span + 1.6
	_box("paint", Vector3(gl, 0.08, 0.6), Vector3(c.x, h + 1.3, c.z), CRANE)
	_box("paint", Vector3(gl, 1.2, 0.14), Vector3(c.x, h + 0.66, c.z), CRANE)
	_box("paint", Vector3(gl, 0.08, 0.6), Vector3(c.x, h + 0.04, c.z), CRANE)
	# The hoist trolley on the bottom flange, its ropes and hook block.
	var tx: float = c.x + r.randf_range(-span * 0.3, span * 0.3)
	_box("paint", Vector3(1.4, 0.9, 1.0), Vector3(tx, h - 0.45, c.z), Color("#3d5a7a"))
	_box("paint", Vector3(0.5, 0.5, 0.9), Vector3(tx + 0.9, h - 0.4, c.z), dark)  # motor
	var drop := r.randf_range(2.5, h - 3.0)
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(0.03, drop, 0.03), Vector3(tx + e * 0.18, h - 0.9 - drop * 0.5, c.z), dark)
	_box("paint", Vector3(0.6, 0.5, 0.35), Vector3(tx, h - 1.15 - drop, c.z), CRANE)
	_box("paint", Vector3(0.12, 0.45, 0.12), Vector3(tx, h - 1.6 - drop, c.z), dark)  # hook
	# A pendant control hanging to the ground for the operator.
	_box("paint", Vector3(0.015, h - 1.6, 0.015), Vector3(tx - 0.6, h * 0.5 + 0.4, c.z), dark)
	_box("paint", Vector3(0.12, 0.3, 0.1), Vector3(tx - 0.6, 1.4, c.z), Color("#d9a92a"))


## Tilt-up concrete plant: flat roof behind a parapet, panel joints, dock doors.
func _tilt_up(to_curb: float) -> void:
	var zf := rng.randf_range(10.0, 12.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var w := clampf(half * 2.0 - 20.0, 18.0, 60.0)
	var d := clampf(depth - zf - 18.0, 16.0, 40.0)
	var h := rng.randf_range(8.5, 10.5)
	var cx := x0 + 9.0 + w * 0.5
	var cz := zf + d * 0.5
	var panel := CONCRETE.darkened(rng.randf_range(0.0, 0.08))
	_box("paint", Vector3(w, h, d), Vector3(cx, h * 0.5, cz), panel)
	_box("paint", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(cx, h + 0.25, cz), panel.darkened(0.06))
	# Panel joints every 7.5 m on the street face, and a painted band.
	var x := cx - w * 0.5 + 7.5
	while x < cx + w * 0.5:
		_box("paint", Vector3(0.05, h - 0.2, 0.12), Vector3(x, h * 0.5 - 0.1, zf - 0.06), panel.darkened(0.25))
		x += 7.5
	_box("paint", Vector3(w + 0.24, 0.6, d + 0.24), Vector3(cx, h - 1.2, cz), Color(_pick(WAINSCOT)))
	_dr_note(cx, cz, w, d, h, "flat", 1.0)
	# Dock doors with dark seals down the side.
	var docks := clampi(int(d / 5.0), 2, 6)
	for i in docks:
		var z := zf + 3.0 + i * (d - 6.0) / maxf(docks - 1, 1)
		_box("siding", Vector3(0.08, 3.0, 2.8), Vector3(cx + w * 0.5 + 0.36, 2.4, z), Color(TRIM, 0.0))
		_box("paint", Vector3(0.3, 3.4, 3.2), Vector3(cx + w * 0.5 + 0.16, 2.4, z), Color("#2a2a2c"))
	_flat_rect("drive", cx + w * 0.5, minf(cx + w * 0.5 + 20.0, half - 0.5), zf, zf + d, 0.08)


## The old brick works near the tracks: three or four storeys of red brick,
## rows of tall windows, a corbelled parapet, a round brick stack and a
## wooden water tank on the roof (1900s-1920s Midwest factory towns).
func _brick_works(to_curb: float) -> void:
	var zf := rng.randf_range(6.0, 9.0)
	var w := clampf(half * 2.0 - 8.0, 18.0, 48.0)
	var d := clampf(depth - zf - 14.0, 14.0, 22.0)
	var floors := rng.randi_range(3, 4)
	var fh := 4.2
	var h := floors * fh
	var brick := Color(_pick(FACADE_BRICK))
	var cz := zf + d * 0.5
	_box("brick", Vector3(w, h, d), Vector3(0, h * 0.5, cz), brick)
	_box("paint", Vector3(w + 0.3, 0.5, d + 0.3), Vector3(0, h + 0.25, cz), brick.darkened(0.2))
	_box("paint", Vector3(w - 0.4, 0.1, d - 0.4), Vector3(0, h + 0.05, cz), Color("#3a3a3c"))  # tar roof inside the parapet
	_dr_note(0.0, cz, w, d, h + 0.1, "flat")
	var n := int(w / 3.2)
	for f in floors:
		for i in n:
			var x := -w * 0.5 + 1.6 + i * (w - 3.2) / maxf(n - 1, 1)
			_glass(Vector3(x, 0.9 + f * fh + 1.3, zf - 0.06), Vector3(-1, 0, 0), 1.6, 2.6, 0.2)
			_box("paint", Vector3(1.9, 0.18, 0.2), Vector3(x, 0.9 + f * fh - 0.05, zf - 0.1), Color("#c9c1ae"))
	_flat_rect("drive", -3.0, 3.0, -to_curb, zf, 0.1)
	# The stack and the water tank on its steel legs.
	var sx := w * 0.5 - 3.0
	if _in_lot(Vector3(sx, 0, zf + d + 4.0), 2.0):
		_cylinder("brick", Vector3(sx, 0, zf + d + 4.0), 1.3, h + 14.0, brick.darkened(0.1), 12)
	var tx := -w * 0.25
	for p in [Vector3(-1.4, 0, -1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, 1.4)]:
		_box("paint", Vector3(0.2, 4.0, 0.2), Vector3(tx, h + 2.1, cz) + p, PIPE.darkened(0.3))
	_cylinder("siding", Vector3(tx, h + 4.1, cz), 2.2, 3.6, Color("#7a5a3c"), 14)
	_cone_top(Vector3(tx, h + 7.7, cz), 2.4, 1.6, Color("#5a5e60"))
	_yard_gravel(zf + d)


## A sawtooth-roof shop: one tall storey of brick with north-facing roof
## glazing in a row of saw teeth (Midwest machine and assembly plants).
func _sawtooth(to_curb: float) -> void:
	var zf := rng.randf_range(9.0, 11.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var w := clampf(half * 2.0 - 22.0, 18.0, 56.0)
	var d := clampf(depth - zf - 16.0, 16.0, 36.0)
	var h := 6.5
	var cx := x0 + 10.0 + w * 0.5
	var cz := zf + d * 0.5
	var brick := Color(_pick(FACADE_BRICK))
	_box("brick", Vector3(w, h, d), Vector3(cx, h * 0.5, cz), brick)
	_box("paint", Vector3(w + 0.2, 0.4, d + 0.2), Vector3(cx, h + 0.2, cz), brick.darkened(0.2))
	_dr_note(cx, cz, w, d, h, "none")
	var teeth := int(d / 6.0)
	var roof := Color("#5a5e60")
	for t in teeth:
		var z0 := zf + t * d / teeth
		var z1 := z0 + d / teeth
		var top := h + 0.4 + 2.6
		# Glazed upright face toward the street side, sloping roof back.
		_quad("glass", Vector3(cx - w * 0.5, h + 0.4, z0 + 0.05), Vector3(cx + w * 0.5, h + 0.4, z0 + 0.05),
			Vector3(cx + w * 0.5, top, z0 + 0.05), Vector3(cx - w * 0.5, top, z0 + 0.05), Color(0.55, 0.6, 0.62, 0.3), [], Vector3(0, 0, -1))
		_quad("metal", Vector3(cx - w * 0.5, top + 0.05, z0), Vector3(cx + w * 0.5, top + 0.05, z0),
			Vector3(cx + w * 0.5, h + 0.45, z1), Vector3(cx - w * 0.5, h + 0.45, z1), roof, [], Vector3(0, 1, 0.4))
		# Each tooth's brick end walls (the saw profile on the side walls),
		# the steel mullions across its glazing and the valley gutter.
		for e in [-1.0, 1.0]:
			var ex: float = cx + e * w * 0.5
			_tri("brick", Vector3(ex, h + 0.4, z0), Vector3(ex, top, z0), Vector3(ex, h + 0.4, z1), brick.darkened(0.05), [],
				Vector3(e, 0, 0))
		var m := cx - w * 0.5 + 1.5
		while m < cx + w * 0.5 - 0.5:
			_box("paint", Vector3(0.08, top - h - 0.4, 0.08), Vector3(m, (top + h + 0.4) * 0.5, z0 + 0.02), Color("#2b2f33"))
			m += 1.5
		_box("paint", Vector3(w, 0.06, 0.08), Vector3(cx, (top + h + 0.4) * 0.5, z0 + 0.02), Color("#2b2f33"))
		_box("metal", Vector3(w, 0.18, 0.3), Vector3(cx, h + 0.5, z0 + 0.15), roof.darkened(0.15))
	for i in 2:
		_door(cx - w * 0.25 + i * w * 0.5, zf)


## A machine shop in a steel Quonset hut with a block end wall and a
## lean-to office (post-war farm-town shops).
func _quonset_shop(to_curb: float) -> void:
	var zf := rng.randf_range(9.0, 11.0)
	var x0 := -half + 1.0
	_front(zf, x0, x0 + 12.0, to_curb)
	_yard_gravel(zf)
	var r := rng.randf_range(6.0, 8.0)
	var len := clampf(depth - zf - 14.0, 16.0, 36.0)
	var cx := x0 + 12.0 + r
	var steel := Color("#a7aba9")
	var segs := 10
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(cx + cos(a0) * r, sin(a0) * r, zf)
		var p1 := Vector3(cx + cos(a1) * r, sin(a1) * r, zf)
		_quad("metal", p0, p1, p1 + Vector3(0, 0, len), p0 + Vector3(0, 0, len), steel.darkened(0.03 * (i % 2)),
			[], Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))
		# Block end wall facing the street.
		_tri("paint", Vector3(cx, 0, zf - 0.06), p0 - Vector3(0, 0, 0.06), p1 - Vector3(0, 0, 0.06), Color(_pick(BLOCK)), [], Vector3(0, 0, -1))
	_door(cx, zf - 0.08, 4.0, 4.4)
	_foot.append([cx, zf + len * 0.5, 2.0 * r, len, r])
