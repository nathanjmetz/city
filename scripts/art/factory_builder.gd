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
		if chain == "mill":
			# An elevator grows its storage, not halls (_elevator_growth).
			var used_r := _elevator_growth(best, adds)
			if used_r.get_area() <= 0.0:
				break
			box = box.merge(used_r)
			built += used_r.get_area()
			adds += 1
			continue
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


## How a country elevator grows when the co-op prospers, in the order
## Indiana elevators did it: first a big-diameter corrugated steel bin (60
## to 105 ft across, its own leg and a spout to its peak, stiffeners,
## aeration fans and a roof ring), then a second, then for record harvests
## an outdoor ground-pile bunker: concrete push walls round an asphalt pad,
## the grain heaped inside under a white tarp held down by tire lines, and
## aeration tubes along the walls. Draws in `band` and returns what it used
## (empty if the band can't take one).
func _elevator_growth(band: Rect2, k: int) -> Rect2:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "elevator_growth", k])
	var pile := k >= 2 or (k == 1 and g.randf() < 0.4)
	if pile and band.size.x >= 40.0 and band.size.y >= 30.0:
		return _ground_pile(band, g)
	var dia := clampf(minf(band.size.x, band.size.y) - 8.0, 18.0, 32.0)
	if band.size.x < dia + 6.0 or band.size.y < dia + 6.0:
		return Rect2()
	var r := dia * 0.5
	var c := Vector3(band.position.x + 3.0 + r, 0, band.position.y + 3.0 + r)
	var eave := clampf(dia * 0.75, 14.0, 24.0)
	var rise := r * 0.42
	_box("paint", Vector3(dia + 1.0, 0.4, dia + 1.0), c + Vector3(0, 0.2, 0), CONCRETE)
	_cylinder("metal", c + Vector3(0, 0.4, 0), r, eave, STEEL_BIN, 36)
	_cone_top(c + Vector3(0, eave + 0.4, 0), r + 0.25, rise, STEEL_BIN.lightened(0.08), "metal", 36)
	for i in 24:  # vertical stiffeners
		var a := TAU * i / 24.0
		_box("paint", Vector3(0.12, eave * 0.8, 0.12), c + Vector3(cos(a) * (r + 0.05), 0.4 + eave * 0.4, sin(a) * (r + 0.05)),
			STEEL_BIN.darkened(0.12))
	# Roof ring rail, the peak cap and roof vents.
	var top := c + Vector3(0, eave + 0.4 + rise, 0)
	_cylinder("metal", top - Vector3(0, 0.3, 0), 1.4, 1.0, STEEL_BIN.darkened(0.05), 12)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		_box("metal", Vector3(0.7, 0.6, 0.7), c + Vector3(cos(a) * r * 0.6, eave + 0.4 + rise * 0.4 + 0.3, sin(a) * r * 0.6), Color("#d8d9d6"))
	# Its own leg beside it, a spout down to the peak, a stair tower up the side.
	var leg := c + Vector3(-r - 3.0, 0, -r * 0.4)
	var lh := eave + rise + 9.0
	_box("metal", Vector3(1.0, lh, 1.7), leg + Vector3(0, lh * 0.5, 0), Color("#9ea3a4"))
	_box("metal", Vector3(2.0, 2.2, 2.6), leg + Vector3(0, lh + 1.1, 0), Color("#9ea3a4").darkened(0.08))
	UpgradeKits._strut(self, leg + Vector3(0.6, lh - 0.4, 0), top + Vector3(0, 0.6, 0), 0.4, PIPE.lightened(0.1))
	var st := c + Vector3(r + 1.2, 0, 0)
	for e in [[-0.9, -0.9], [0.9, -0.9], [-0.9, 0.9], [0.9, 0.9]]:
		_box("paint", Vector3(0.12, eave + 0.6, 0.12), st + Vector3(e[0], (eave + 0.6) * 0.5, e[1]), PIPE)
	var y := 3.0
	while y < eave:
		_box("paint", Vector3(2.0, 0.08, 2.0), st + Vector3(0, y, 0), PIPE.darkened(0.1))
		y += 3.0
	# Aeration fans at the foot, facing out.
	for a in [PI * 0.75, PI * 1.25]:
		var out := Vector3(cos(a), 0, sin(a))
		var f: Vector3 = c + out * (r + 0.8)
		_box("metal", Vector3(1.6, 1.4, 1.6), f + Vector3(0, 0.7, 0), Color("#d8d9d6"), Basis(Vector3.UP, atan2(out.x, out.z)))
		_cylinder("paint", f + out * 1.0, 0.7, 1.4, Color("#5b6064"), 12)
	return Rect2(c.x - r - 4.5, c.z - r - 1.0, dia + 7.0, dia + 2.0)


## The outdoor ground pile (a bunker): see _elevator_growth.
func _ground_pile(band: Rect2, g: RandomNumberGenerator) -> Rect2:
	var w := minf(band.size.x - 4.0, 90.0)
	var d := minf(band.size.y - 4.0, 40.0)
	var x0 := band.position.x + 2.0
	var z0 := band.position.y + 2.0
	var x1 := x0 + w
	var z1 := z0 + d
	var wall := 3.0
	_flat_rect("drive", x0, x1, z0, z1, 0.07)
	# The push walls: precast panels, open at one end for the trucks.
	for e in [[Vector3(x0, 0, z0), Vector3(x1, 0, z0)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)],
			[Vector3(x0, 0, z0), Vector3(x0, 0, z1)]]:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var n := int(len / 3.0)
		for i in n:
			var m := a + dir * (i + 0.5) * len / n
			_box("paint", Vector3(absf(dir.x) * (len / n - 0.05) + absf(dir.z) * 0.5, wall, absf(dir.z) * (len / n - 0.05) + absf(dir.x) * 0.5),
				m + Vector3(0, wall * 0.5, 0), CONCRETE.darkened(0.04 * (i % 2)))
	# The heap: a long ridge from wall top to crown, hipped at the ends.
	var tarp := Color("#e6e6e0") if g.randf() < 0.7 else Color("#2e3032")
	var crown := wall + d * 0.5 * 0.42
	var zc := (z0 + z1) * 0.5
	var ins := 0.4
	var a0 := Vector3(x0 + ins, wall, z0 + ins)
	var a1 := Vector3(x1 - 6.0, wall, z0 + ins)
	var b0 := Vector3(x0 + ins, wall, z1 - ins)
	var b1 := Vector3(x1 - 6.0, wall, z1 - ins)
	var r0 := Vector3(x0 + d * 0.5, crown, zc)
	var r1 := Vector3(x1 - 6.0 - d * 0.5, crown, zc)
	_quad("paint", a0, a1, r1, r0, tarp, [], Vector3(0, 1, -1))
	_quad("paint", b0, b1, r1, r0, tarp, [], Vector3(0, 1, 1))
	_tri("paint", a0, b0, r0, tarp, [], Vector3(-1, 1, 0))
	# The open end slumps down to the pad.
	var e0 := Vector3(x1 - 1.0, 0.1, z0 + ins)
	var e1 := Vector3(x1 - 1.0, 0.1, z1 - ins)
	_quad("paint", a1, b1, e1, e0, tarp.darkened(0.04), [], Vector3(1, 1, 0))
	_tri("paint", a1, e0, r1, tarp, [], Vector3(0.3, 1, -1))
	_tri("paint", b1, e1, r1, tarp, [], Vector3(0.3, 1, 1))
	_tri("paint", e0, e1, r1, tarp.darkened(0.06), [], Vector3(1, 1, 0))
	# Tire lines across the tarp every 3 m, down both slopes.
	var x := x0 + d * 0.5 + 1.5
	while x < x1 - 6.0 - d * 0.5 - 1.0:
		for side in [-1.0, 1.0]:
			var p: Vector3 = Vector3(x, crown, zc).lerp(Vector3(x, wall, zc + side * (d * 0.5 - ins)), 0.5)
			var len := Vector3(0, crown - wall, d * 0.5).length()
			_box("paint", Vector3(0.5, 0.18, len * 0.95), p + Vector3(0, 0.12, 0), Color("#1c1c1e"),
				Basis(Vector3.RIGHT, side * atan2(crown - wall, d * 0.5 - ins)))
		x += 3.0
	# Aeration tubes and fans along the long walls, outside.
	var t := x0 + 8.0
	while t < x1 - 8.0:
		for z in [z0 - 0.9, z1 + 0.9]:
			_cylinder("paint", Vector3(t, 0, z), 0.45, 0.9, Color("#5b6064"), 10)
		t += 12.0
	return Rect2(x0 - 1.0, z0 - 1.5, w + 2.0, d + 3.0)


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
	var placed := []
	for i in bins:
		var c := Vector3(sx0 + i * 13.0, 0, sz + 15.0)
		if _in_lot(c, 7.0):
			_cylinder("metal", c, 6.0, 11.0, STEEL_BIN, 24)
			_cone_top(c + Vector3(0, 11.0, 0), 6.2, 3.2, STEEL_BIN.lightened(0.08))
			_foot.append([c.x, c.z, 12.0, 12.0, 10.0])
			placed.append(c)
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
	_mill_works(sx0, n, r, sh, sz, placed, dx)


## What makes a country elevator read as one, from Indiana co-op
## elevators: the bucket elevator leg climbing from the dump pit past the
## headhouse, the distributor spouts falling from its head to every silo
## and bin, a conveyor gallery out to the steel bins, aeration fans at the
## bins' feet, a caged ladder up the end silo, and a tall column grain
## dryer with its wet bin and burner where there's room.
func _mill_works(sx0: float, n: int, r: float, sh: float, sz: float, bins: Array, dx: float) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "mill_works"])
	var hx := sx0 + (n - 1) * 6.6
	var leg_x := hx + 4.4
	var leg_top := sh + 17.0
	# The leg: a twin casing from the pit to its head above the headhouse.
	var leg := Color("#9ea3a4")
	_box("metal", Vector3(1.0, leg_top, 1.7), Vector3(leg_x, leg_top * 0.5, sz - 2.0), leg)
	_box("metal", Vector3(2.0, 2.4, 2.6), Vector3(leg_x, leg_top + 1.2, sz - 2.0), leg.darkened(0.08))
	_box("paint", Vector3(2.2, 0.15, 2.8), Vector3(leg_x, leg_top + 2.45, sz - 2.0), PIPE.darkened(0.2))
	# A guyed lightning mast on the head.
	UpgradeKits._strut(self, Vector3(leg_x, leg_top + 2.5, sz - 2.0), Vector3(leg_x, leg_top + 6.0, sz - 2.0), 0.08, PIPE)
	# The boot down in the pit under the dump shed, fed by a drag conveyor.
	UpgradeKits._strut(self, Vector3(dx, 0.3, sz - 8.0), Vector3(leg_x, 0.3, sz - 2.0), 0.7, leg.darkened(0.15))
	# Distributor spouts from the head to each silo top and bin roof.
	var head := Vector3(leg_x - 0.8, leg_top - 0.5, sz - 2.0)
	for i in n:
		UpgradeKits._strut(self, head, Vector3(sx0 + i * 6.6, sh + 0.4, sz), 0.32, PIPE.lightened(0.1))
	for c in bins:
		UpgradeKits._strut(self, head, c + Vector3(0, 14.4, 0), 0.32, PIPE.lightened(0.1))
	# A conveyor gallery from the headhouse to the first bin's peak, on a bent.
	if not bins.is_empty():
		var c0: Vector3 = bins[0]
		var a := Vector3(hx, sh + 3.5, sz + 3.0)
		var b := c0 + Vector3(0, 14.6, 0)
		UpgradeKits._strut(self, a, b, 1.3, Color("#b7bbbb"))
		var mid := (a + b) * 0.5
		for e in [-0.6, 0.6]:
			UpgradeKits._strut(self, Vector3(mid.x + e, 0, mid.z), Vector3(mid.x + e, mid.y - 0.7, mid.z), 0.25, PIPE)
	# Aeration fans and roof vents on the bins.
	for c in bins:
		var out := Vector3(-1, 0, 0).rotated(Vector3.UP, g.randf_range(-0.6, 0.6))
		var f: Vector3 = c + out * 6.6
		_box("metal", Vector3(1.4, 1.2, 1.4), f + Vector3(0, 0.6, 0), Color("#d8d9d6"), Basis(Vector3.UP, atan2(out.x, out.z)))
		_cylinder("paint", f + out * 0.9 + Vector3(0, 0.0, 0), 0.6, 1.2, Color("#5b6064"), 12)
		for k in 3:
			var a := g.randf() * TAU
			_box("metal", Vector3(0.6, 0.5, 0.6), c + Vector3(cos(a) * 3.2, 12.8, sin(a) * 3.2), Color("#d8d9d6"))
	# The caged ladder up the end silo.
	var lx := sx0 - r - 0.25
	_box("paint", Vector3(0.08, sh, 0.5), Vector3(lx, sh * 0.5, sz), PIPE)
	var y := 2.4
	while y < sh:
		_box("paint", Vector3(0.7, 0.06, 0.06), Vector3(lx - 0.35, y, sz - 0.35), PIPE)
		_box("paint", Vector3(0.7, 0.06, 0.06), Vector3(lx - 0.35, y, sz + 0.35), PIPE)
		_box("paint", Vector3(0.06, 0.06, 0.76), Vector3(lx - 0.7, y, sz), PIPE)
		y += 1.2
	# The column dryer beside the last bin, if the lot has room.
	var d := Vector3(sx0 + bins.size() * 13.0 + 2.0, 0, sz + 15.0)
	if bins.size() < 3 and _in_lot(d, 6.0):
		var dh := g.randf_range(18.0, 22.0)
		_box("paint", Vector3(5.0, 0.4, 7.0), d + Vector3(0, 0.2, 0), Color("#b9b5ab"))
		_box("metal", Vector3(2.6, dh, 4.4), d + Vector3(0, dh * 0.5 + 0.4, 0), Color("#3e4447"))  # screen columns
		for k in int(dh / 3.0):
			_box("paint", Vector3(2.7, 0.12, 4.5), d + Vector3(0, 1.4 + k * 3.0, 0), Color("#c9cbc8"))
		_box("metal", Vector3(3.0, 2.6, 4.8), d + Vector3(0, dh + 1.7, 0), Color("#c9cbc8"))  # garner bin on top
		_box("metal", Vector3(1.8, 2.2, 2.2), d + Vector3(2.4, 1.5, 1.0), Color("#c9cbc8"))  # fan and burner
		_cylinder("paint", d + Vector3(3.4, 0.4, 1.0), 0.9, 2.2, Color("#5b6064"), 12)
		UpgradeKits._strut(self, head, d + Vector3(0, dh + 3.0, 0), 0.32, PIPE.lightened(0.1))
		# The LP tank that fires it, on two concrete saddles.
		for e in [-2.2, 2.2]:
			_box("paint", Vector3(1.6, 0.6, 0.5), d + Vector3(-5.0, 0.3, e), Color("#b9b5ab"))
		UpgradeKits._drum(self, d + Vector3(-5.0, 1.55, 0), 1.0, 6.4, Color("#efede6"), false)
		_foot.append([d.x - 1.5, d.z, 11.0, 8.0, 22.0])


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
	var hh := rng.randf_range(13.0, 16.0)
	_hall(hx, hz, hw, hd, hh, wall)
	# Roof monitor along the ridge (high-bay daylight and fume vents).
	_box("metal", Vector3(hw * 0.8, 2.0, 3.0), Vector3(hx, 15.5, hz), wall.darkened(0.12))
	for i in 2:
		_door(hx - hw * 0.25 + i * hw * 0.5, hz - hd * 0.5, 5.0, 6.0)
	_fab_shop(hx, hz, hw, hd, hh)
	# Gantry crane over the coil yard behind.
	var yz := hz + hd * 0.5 + 9.0
	if yz + 6.0 < depth:
		_gantry(Vector3(hx, 0, yz), 24.0, 9.6)
		for i in 8:
			for j in 2:
				_cylinder("metal", Vector3(hx - 9.0 + i * 2.5, 0, yz - 2.0 + j * 4.0), 0.9, 1.5, COIL, 12)
				# The coil's eye, stored eye-to-sky on its end.
				_cylinder("paint", Vector3(hx - 9.0 + i * 2.5, 0, yz - 2.0 + j * 4.0), 0.3, 1.52, Color("#3a3c3e"), 8)


## What a working fabrication shop shows outside, from Indiana steel
## fabricators' and stamping plants' photos: a band of translucent wall
## panels under the eave lighting the high bay, big louvered exhaust fans
## pulling weld smoke out of the side walls, the cartridge dust collector
## ducted through the wall, the welding-gas supplier's cryogenic bulk tank
## (argon or oxygen) with its finned vaporizers behind a fence, and
## self-dumping hoppers and a roll-off of scrap and turnings by a door.
func _fab_shop(hx: float, hz: float, hw: float, hd: float, h: float) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "fab_shop"])
	var panel := Color("#e4e2d2")
	var y := h - 2.2
	# The translucent band, front, back and both ends.
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(hw - 1.0, 1.2, 0.05), Vector3(hx, y, hz + s * (hd * 0.5 + 0.03)), panel)
		_box("paint", Vector3(0.05, 1.2, hd - 1.0), Vector3(hx + s * (hw * 0.5 + 0.03), y, hz), panel)
	# Exhaust fans high on each end wall.
	for s in [-1.0, 1.0]:
		var x: float = hx + s * (hw * 0.5 + 0.12)
		for k in 3:
			var z := hz - hd * 0.3 + k * hd * 0.3
			_box("paint", Vector3(0.2, 1.7, 1.7), Vector3(x, h - 5.0, z), Color("#6f7476"))
			for l in 4:
				_box("paint", Vector3(0.06, 0.08, 1.5), Vector3(x + s * 0.1, h - 5.6 + l * 0.38, z), Color("#4a4e52"))
			_box("paint", Vector3(0.5, 0.25, 1.9), Vector3(x + s * 0.2, h - 4.05, z), Color("#8e9496"))  # rain hood
	# The dust collector on the left end, its duct into the wall.
	var dc := Vector3(hx - hw * 0.5 - 2.6, 0, hz + hd * 0.2)
	if _in_lot(dc, 1.8):
		for e in [[-0.9, -0.9], [0.9, -0.9], [-0.9, 0.9], [0.9, 0.9]]:
			_box("paint", Vector3(0.15, 2.6, 0.15), dc + Vector3(e[0], 1.3, e[1]), Color("#4a6a8a"))
		_cone_top(dc + Vector3(0, 2.6, 0), 1.1, -1.0, Color("#4a6a8a"), "paint", 10)
		_box("metal", Vector3(2.2, 3.6, 2.2), dc + Vector3(0, 4.4, 0), Color("#4a6a8a"))
		_box("paint", Vector3(0.3, 1.0, 0.6), dc + Vector3(0, 6.7, 0.6), Color("#3a3c3e"))  # pulse valves
		UpgradeKits._strut(self, dc + Vector3(1.1, 5.6, 0), Vector3(hx - hw * 0.5, 5.6, dc.z), 0.6, Color("#b8bcbe"))
		_drum_bin(dc + Vector3(0, 0, -1.6))
	# The bulk gas tank on the right end, fenced, with its vaporizers.
	var t := Vector3(hx + hw * 0.5 + 4.0, 0, hz - hd * 0.15)
	if _in_lot(t, 3.0):
		_box("paint", Vector3(5.0, 0.3, 4.0), t + Vector3(0.6, 0.15, 0), Color("#b9b5ab"))
		_cylinder("metal", t + Vector3(0, 0.3, -0.6), 1.05, 7.5, Color("#f0efe9"), 16)
		_cone_top(t + Vector3(0, 7.8, -0.6), 1.05, 0.5, Color("#f0efe9"), "metal", 16)
		for k in 2:
			var v := t + Vector3(1.6 + k * 1.1, 0.3, 1.0)
			_box("paint", Vector3(0.7, 4.0, 0.7), v + Vector3(0, 2.0, 0), Color("#c9cdd0"))
			for f in 4:
				_box("paint", Vector3(0.05, 3.8, 0.9), v + Vector3(-0.3 + f * 0.2, 2.0, 0), Color("#d8dcde"))
		_box("paint", Vector3(0.6, 0.4, 0.04), t + Vector3(0, 2.2, -1.68), Color("#2f6a3a"))  # supplier plate
	# Scrap: two self-dumping hoppers by the front door, a roll-off of turnings.
	for k in 2:
		var p := Vector3(hx + hw * 0.25 + 4.0 + k * 2.4, 0, hz - hd * 0.5 - 2.2)
		var col: Color = [Color("#2f5d8a"), Color("#e0b81e")][k]
		_box("paint", Vector3(1.6, 0.25, 1.4), p + Vector3(0, 0.25, 0), Color("#3a3c3e"))
		_box("metal", Vector3(1.7, 1.0, 1.6), p + Vector3(0, 0.95, 0), col)
		_box("paint", Vector3(1.5, 0.12, 1.4), p + Vector3(0, 1.4, 0), Color("#7c8084"))
	var ro := Vector3(hx + hw * 0.5 - 4.0, 0, hz + hd * 0.5 + 4.0)
	if _in_lot(ro, 3.6):
		_box("metal", Vector3(6.8, 1.6, 2.4), ro + Vector3(0, 0.95, 0), Color("#8a3b2c"))
		for k in 9:
			_box("paint", Vector3(g.randf_range(0.4, 1.2), 0.25, g.randf_range(0.3, 0.9)),
				ro + Vector3(g.randf_range(-2.8, 2.8), 1.75 + g.randf_range(0.0, 0.2), g.randf_range(-0.8, 0.8)),
				Color("#8e9296").darkened(g.randf_range(0.0, 0.3)), Basis(Vector3.UP, g.randf() * TAU))


## A 55-gallon drum on the ground.
func _drum_bin(p: Vector3) -> void:
	_cylinder("paint", p, 0.29, 0.88, Color("#3a3c3e"), 10)


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
	_tilt_up_face(cx, cz, w, d, h, zf, panel, docks)


## What a 1990s tilt-up plant shows, from Midwest industrial-park photos:
## two reveals cut across every panel, a ribbon of high clerestory glass on
## the street face, the glazed entry with its aluminium storefront under a
## steel canopy and an accent-painted panel round it, rows of skylights on
## the roof, and at each dock the black rubber bumpers, a dock light on its
## arm and a yellow bollard pair; a man door with a concrete stoop.
func _tilt_up_face(cx: float, cz: float, w: float, d: float, h: float, zf: float, panel: Color, docks: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "tilt_up_face"])
	var reveal := panel.darkened(0.3)
	for y in [h * 0.3, h * 0.62]:
		_box("paint", Vector3(w + 0.02, 0.06, 0.05), Vector3(cx, y, zf - 0.04), reveal)
		_box("paint", Vector3(0.05, 0.06, d + 0.02), Vector3(cx - w * 0.5 - 0.04, y, cz), reveal)
	# Clerestory glass high on the street face, between the panel joints.
	var x := cx - w * 0.5 + 1.5
	while x < cx + w * 0.5 - 2.0:
		_glass(Vector3(x + 2.25, h - 2.6, zf - 0.04), Vector3(-1, 0, 0), 4.2, 0.9, 0.0)
		x += 7.5
	# The entry: accent panel, storefront glass and a canopy, at one end.
	var ex := cx - w * 0.5 + 5.0 if g.randf() < 0.5 else cx + w * 0.5 - 5.0
	var accent := Color(["#2f5d8a", "#7a1f2b", "#3f6d4a", "#4a4e52"][g.randi() % 4])
	_box("paint", Vector3(7.4, h - 0.6, 0.06), Vector3(ex, (h - 0.6) * 0.5, zf - 0.05), accent)
	_glass(Vector3(ex, 1.6, zf - 0.1), Vector3(-1, 0, 0), 5.0, 2.8, 0.0)
	for k in 5:
		_box("paint", Vector3(0.08, 2.9, 0.08), Vector3(ex - 2.5 + k * 1.25, 1.55, zf - 0.13), MULLION[0])
	_box("paint", Vector3(7.0, 0.25, 2.4), Vector3(ex, 3.4, zf - 1.2), Color("#3a3c3e"))
	for e in [-1.0, 1.0]:  # the canopy's tie rods back to the wall
		UpgradeKits._strut(self, Vector3(ex + e * 3.2, 3.5, zf - 2.3), Vector3(ex + e * 3.2, 5.2, zf - 0.1), 0.05, Color("#3a3c3e"))
	_box("paint", Vector3(7.2, 0.15, 3.0), Vector3(ex, 0.08, zf - 1.5), CONCRETE)
	# Skylights in rows on the roof.
	for row in 2:
		var z := cz - d * 0.2 + row * d * 0.4
		var sx := cx - w * 0.5 + 6.0
		while sx < cx + w * 0.5 - 4.0:
			_box("paint", Vector3(1.4, 0.35, 2.2), Vector3(sx, h + 0.2, z), Color("#dfe4e4"))
			sx += 7.5
	# At each dock: bumpers, a light on its arm, a pair of bollards.
	var wx := cx + w * 0.5
	for i in docks:
		var z := zf + 3.0 + i * (d - 6.0) / maxf(docks - 1, 1)
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 0.6, 0.3), Vector3(wx + 0.35, 1.1, z + e * 1.1), Color("#1c1c1e"))
		_box("paint", Vector3(0.9, 0.08, 0.08), Vector3(wx + 0.45, 4.4, z - 1.9), Color("#3a3c3e"))
		_box("paint", Vector3(0.25, 0.25, 0.3), Vector3(wx + 0.9, 4.3, z - 1.9), Color("#d8d9d6"))
	# A man door near the docks with its stoop and a light.
	var mz := zf + d - 1.5
	_box("paint", Vector3(0.06, 2.1, 0.95), Vector3(wx + 0.04, 1.05, mz), Color("#6a6e70"))
	_box("paint", Vector3(1.6, 0.15, 1.6), Vector3(wx + 0.8, 0.08, mz), CONCRETE)
	_box("paint", Vector3(0.25, 0.25, 0.3), Vector3(wx + 0.15, 2.7, mz), Color("#3a3c3e"))


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
	_box("paint", Vector3(w - 0.4, 0.1, d - 0.4), Vector3(0, h + 0.2, cz), Color("#3a3a3c"))  # tar roof inside the parapet
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
	_brick_works_life(w, d, h, zf, floors, fh, brick, sx)
	_yard_gravel(zf + d)


## What makes an old mill read as one: windows on every wall under
## segmental brick arches, a stepped corbel under a hollow parapet (the tar
## roof shows), a stair and freight-elevator tower that pokes above the roof,
## a stone-trimmed front door, a rear loading dock under a shed canopy, a
## faded painted wall sign and a banded stack (Indiana mill buildings of
## 1890-1925: Marion's Malleable Iron and Anderson's Remy plant).
func _brick_works_life(w: float, d: float, h: float, zf: float, floors: int, fh: float, brick: Color, sx: float) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "brick_works"])
	var zb := zf + d
	var cz := zf + d * 0.5
	var dark := brick.darkened(0.22)
	var stone := Color("#c9c1ae")
	# Hollow parapet over a corbel band, so the tar roof reads from above.
	for side in [-1.0, 1.0]:
		_box("paint", Vector3(w + 0.3, 0.9, 0.35), Vector3(0, h + 0.45, cz + side * (d * 0.5 - 0.02)), dark)
		_box("paint", Vector3(0.35, 0.9, d + 0.3), Vector3(side * (w * 0.5 - 0.02), h + 0.45, cz), dark)
		_box("paint", Vector3(w + 0.5, 0.12, 0.55), Vector3(0, h + 0.94, cz + side * (d * 0.5 - 0.02)), stone)  # stone coping
		_box("paint", Vector3(0.55, 0.12, d + 0.5), Vector3(side * (w * 0.5 - 0.02), h + 0.94, cz), stone)
	_box("paint", Vector3(w + 0.5, 0.35, d + 0.5), Vector3(0, h - 0.6, cz), dark)
	# Floor lines: a thin soldier course at each floor.
	for f in range(1, floors):
		_box("paint", Vector3(w + 0.16, 0.18, d + 0.16), Vector3(0, f * fh + 0.35, cz), dark)
	# Arches over the front windows; windows and arches on the rear and side walls.
	var n := int(w / 3.2)
	var nd := int(d / 3.2)
	for f in floors:
		var y := 0.9 + f * fh + 1.3
		for i in n:
			var x := -w * 0.5 + 1.6 + i * (w - 3.2) / maxf(n - 1, 1)
			_box("paint", Vector3(1.9, 0.3, 0.12), Vector3(x, y + 1.45, zf - 0.08), dark)
			if f == 0 and absf(x) < 3.0:
				continue  # the loading dock door goes here at the back
			_glass(Vector3(x, y, zb + 0.06), Vector3(1, 0, 0), 1.6, 2.6, 0.2)
			_box("paint", Vector3(1.9, 0.3, 0.12), Vector3(x, y + 1.45, zb + 0.08), dark)
			_box("paint", Vector3(1.9, 0.18, 0.2), Vector3(x, y - 1.35, zb + 0.1), stone)
		for i in nd:
			var z := zf + 1.6 + i * (d - 3.2) / maxf(nd - 1, 1)
			for side in [-1.0, 1.0]:
				var x: float = side * (w * 0.5 + 0.06)
				if side < 0.0 and f == floors - 1 and absf(z - cz) < d * 0.38:
					continue  # blank brick behind the painted sign
				_glass(Vector3(x, y, z), Vector3(0, 0, -side), 1.6, 2.6, 0.2)
				_box("paint", Vector3(0.12, 0.3, 1.9), Vector3(x + side * 0.02, y + 1.45, z), dark)
				_box("paint", Vector3(0.2, 0.18, 1.9), Vector3(x + side * 0.04, y - 1.35, z), stone)
	# Stair and freight-elevator tower on the back wall, one storey proud.
	var tw := 5.0
	var th := h + fh
	var tx := w * 0.5 - tw * 0.5 - 1.0
	var tz := zb + 2.2
	if _in_lot(Vector3(tx, 0, tz + 2.2), 0.5):
		_box("brick", Vector3(tw, th, 4.6), Vector3(tx, th * 0.5, tz), brick.darkened(0.04))
		_box("paint", Vector3(tw + 0.3, 0.6, 4.9), Vector3(tx, th + 0.3, tz), dark)
		_box("paint", Vector3(tw + 0.4, 0.12, 5.0), Vector3(tx, th + 0.66, tz), stone)
		for f in floors + 1:
			_glass(Vector3(tx, 1.4 + f * fh + 0.6, tz + 2.36), Vector3(1, 0, 0), 1.0, 1.8, 0.1)
		_box("paint", Vector3(1.0, 2.2, 0.08), Vector3(tx, 1.1, tz + 2.34), Color("#5a5048"))
	# Front door: stone surround, transom and a date stone.
	_box("paint", Vector3(3.0, 3.6, 0.25), Vector3(0, 1.8, zf - 0.1), stone)
	_box("paint", Vector3(2.0, 2.5, 0.08), Vector3(0, 1.25, zf - 0.24), Color("#4a3a2c"))
	_glass(Vector3(0, 3.0, zf - 0.26), Vector3(-1, 0, 0), 2.0, 0.6, 0.0)
	_box("paint", Vector3(1.6, 0.6, 0.1), Vector3(0, h - 1.4, zf - 0.08), stone)
	_box("paint", Vector3(3.6, 0.3, 1.8), Vector3(0, 0.15, zf - 0.9), CONCRETE)
	# A faded painted wall sign high on the street side wall.
	var ghost := Color(stone, 1.0).lerp(brick, 0.45)
	_box("paint", Vector3(0.04, fh * 0.9, d * 0.7), Vector3(-w * 0.5 - 0.08, h - fh * 0.6, cz), ghost)
	_box("paint", Vector3(0.04, 0.35, d * 0.55), Vector3(-w * 0.5 - 0.1, h - fh * 0.45, cz), brick.darkened(0.35))
	_box("paint", Vector3(0.04, 0.3, d * 0.45), Vector3(-w * 0.5 - 0.1, h - fh * 0.8, cz), brick.darkened(0.35))
	# Rear loading dock: a raised concrete platform under a shed canopy on
	# steel brackets, two freight doors, bumpers and a step.
	var dw := minf(w * 0.5, 14.0)
	if _in_lot(Vector3(0, 0, zb + 3.0), 1.0):
		_box("paint", Vector3(dw, 1.2, 2.6), Vector3(0, 0.6, zb + 1.3), CONCRETE)
		_box("paint", Vector3(dw + 1.0, 0.18, 3.6), Vector3(0, 4.6, zb + 1.8), Color("#5c6266"), Basis(Vector3.RIGHT, -0.12))
		for bx in [-dw * 0.5 + 0.3, 0.0, dw * 0.5 - 0.3]:
			UpgradeKits._strut(self, Vector3(bx, 3.2, zb + 0.05), Vector3(bx, 4.45, zb + 3.2), 0.12, PIPE.darkened(0.3))
		for dx in [-dw * 0.22, dw * 0.22]:
			_box("paint", Vector3(2.8, 3.0, 0.08), Vector3(dx, 2.7, zb + 0.06), Color("#7a6a52") if g.randf() < 0.5 else Color("#6c7072"))
			for bx in [-1.0, 1.0]:
				_box("paint", Vector3(0.3, 0.45, 0.15), Vector3(dx + bx * 1.0, 0.85, zb + 2.68), Color("#1e1e1e"))
		_box("paint", Vector3(1.2, 0.4, 0.8), Vector3(dw * 0.5 + 0.6, 0.2, zb + 1.8), CONCRETE)
	# The stack gets a plinth, iron bands and a corbelled cap.
	if _in_lot(Vector3(sx, 0, zb + 4.0), 2.0):
		var sp := Vector3(sx, 0, zb + 4.0)
		_box("brick", Vector3(3.4, 2.4, 3.4), sp + Vector3(0, 1.2, 0), dark)
		for k in 4:
			_cylinder("paint", sp + Vector3(0, 5.0 + k * (h + 6.0) / 4.0, 0), 1.34, 0.18, Color("#2c2c2c"), 12)
		_cylinder("paint", sp + Vector3(0, h + 13.2, 0), 1.55, 0.8, dark, 12)


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
	_quonset_life(cx, zf, r, len, steel)


## A small rural welding and machine shop in a quonset, from Indiana
## examples: the arch's seams standing out every few feet, a closed back
## wall, a man door and light beside the big door, turbine vents on top, a
## lean-to down one side over a cantilever rack of bar stock and pipe, a
## 500-gallon propane tank on blocks, and a dumpster and scrap pile out back.
func _quonset_life(cx: float, zf: float, r: float, len: float, steel: Color) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.seed, "quonset_life"])
	var segs := 16
	# Arch seams.
	var z := zf + 1.8
	while z < zf + len - 0.5:
		for i in segs:
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			var p0 := Vector3(cx + cos(a0) * (r + 0.03), sin(a0) * (r + 0.03), z)
			var p1 := Vector3(cx + cos(a1) * (r + 0.03), sin(a1) * (r + 0.03), z)
			UpgradeKits._strut(self, p0, p1, 0.06, steel.darkened(0.18))
		z += 1.8
	# The back wall.
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		_tri("metal", Vector3(cx, 0, zf + len + 0.04), Vector3(cx + cos(a0) * r, sin(a0) * r, zf + len + 0.04),
			Vector3(cx + cos(a1) * r, sin(a1) * r, zf + len + 0.04), steel.darkened(0.08), [], Vector3(0, 0, 1))
	# Man door, wall light, a small window in the front wall.
	var md := cx + 3.4
	_box("paint", Vector3(0.95, 2.1, 0.06), Vector3(md, 1.05, zf - 0.1), Color("#6a6e70"))
	_box("paint", Vector3(0.3, 0.25, 0.25), Vector3(cx, 5.0, zf - 0.2), Color("#3a3c3e"))
	_glass(Vector3(cx - 3.4, 1.7, zf - 0.1), Vector3(-1, 0, 0), 1.2, 0.9, 0.0)
	# Turbine vents along the crown.
	for k in 2:
		var v := Vector3(cx, r + 0.1, zf + len * (0.3 + k * 0.4))
		_cylinder("paint", v, 0.15, 0.35, steel, 8)
		_cylinder("metal", v + Vector3(0, 0.35, 0), 0.35, 0.45, Color("#c9cbc8"), 10)
	# The lean-to and its rack.
	var lx := cx + r
	var lw := 4.5
	if _in_lot(Vector3(lx + lw + 0.5, 0, zf + len * 0.5), 0.5):
		var z0 := zf + 3.0
		var z1 := zf + len - 2.0
		var hi := r * 0.55
		var x := z0
		while x <= z1 + 0.1:
			_box("paint", Vector3(0.15, 2.6, 0.15), Vector3(lx + lw, 1.3, x), PIPE)
			x += 4.0
		var a := Vector3(lx - 0.3, hi, z0)
		var b := Vector3(lx + lw + 0.3, 2.7, z0)
		_quad("metal", a, b, b + Vector3(0, 0, z1 - z0), a + Vector3(0, 0, z1 - z0), steel.darkened(0.1), [], Vector3(0.3, 1, 0))
		# Cantilever rack: uprights with arms, bar stock and pipe on them.
		var rz := z0 + 1.0
		while rz < z1 - 1.0:
			_box("paint", Vector3(0.2, 2.2, 0.2), Vector3(lx + 1.2, 1.1, rz), Color("#2f5d8a"))
			for lvl in 3:
				_box("paint", Vector3(1.6, 0.08, 0.12), Vector3(lx + 2.0, 0.5 + lvl * 0.7, rz), Color("#2f5d8a"))
			rz += 3.0
		for lvl in 3:
			for k in 4:
				var col := Color("#6b6e70").darkened(g.randf_range(0.0, 0.3))
				_box("paint", Vector3(0.08, 0.08, z1 - z0 - 2.0), Vector3(lx + 1.5 + k * 0.25, 0.6 + lvl * 0.7, (z0 + z1) * 0.5), col)
	# Propane on blocks, the meter and regulator.
	var t := Vector3(cx - r - 2.6, 0, zf + len * 0.5)
	if _in_lot(t, 1.2):
		for e in [-0.9, 0.9]:
			_box("paint", Vector3(0.6, 0.4, 0.4), t + Vector3(0, 0.2, e), CONCRETE)
		UpgradeKits._drum(self, t + Vector3(0, 0.95, 0), 0.5, 2.9, Color("#efede6"), false)
		_box("paint", Vector3(0.3, 0.25, 0.3), t + Vector3(0, 1.55, 0), Color("#b8bcbe"))
	# A dumpster and a scrap pile behind.
	var d := Vector3(cx + r - 1.5, 0, zf + len + 3.0)
	if _in_lot(d, 2.0):
		_box("metal", Vector3(2.0, 1.4, 1.6), d + Vector3(0, 0.7, 0), Color("#2f5a3a"))
		for k in 8:
			_box("paint", Vector3(g.randf_range(0.3, 2.4), 0.12, g.randf_range(0.1, 0.4)),
				d + Vector3(-4.0 + g.randf_range(-1.0, 1.0), 0.1 + k * 0.08, g.randf_range(-0.8, 0.8)),
				Color("#6f6a62").darkened(g.randf_range(0.0, 0.4)), Basis(Vector3.UP, g.randf() * TAU))
