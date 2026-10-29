class_name FarmBuilder
extends CommercialBuilder
## Builds a Midwestern farmstead with the same realistic parts and materials
## as town houses. Benchmark: photos of Iowa and Illinois farmsteads.
##   - a white two-storey farmhouse with a full front porch and a kitchen ell
##   - a red gambrel barn with white trim, a big sliding door with an X brace,
##     a hayloft door and a cupola, under a grey galvanised roof
##   - corrugated steel grain bins with cone roofs, and a concrete stave silo
##   - a gravel yard, shade trees by the house and a spruce windbreak
## Local space matches FarmView: the farm faces -z, the house sits front left
## and the barn behind it to the right.

const FARM_SIDING := ["#eeede6", "#f2f0e8", "#e4dfcf", "#e9e6da"]
const BARN_RED := ["#7d2a20", "#8a2f22", "#6f2620", "#933a2a"]
const GALV := Color("#9a9fa2")
const BIN := Color("#c3c7c8")
const STAVE := Color("#bdb7aa")
const YARD_GRAVEL := Color("#b5ad9c")  # crushed limestone, pale in the sun


## [house mesh, ground mesh, trees] for a farmstead at growth stage `look`
## (0 house only, 1 barn, 2 grain bins, 3 silo), with what the farmer has
## built (Agency.TREES.farm) in the yard (UpgradeKits).
static func build_farmstead(seed: int, look: int, built := []) -> Array:
	var b := FarmBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._farmstead(maxi(look, 2) if "grain_bins" in built else look)
	b._farm_upgrades(built)
	return [b._commit_house(), b._commit_flat(), b.trees]


## The farm tree's steps, each where it would stand on a real farmstead:
## the bigger bin on the bin row, the dryer and leg between the bins, the
## planter and grain trailer parked by the lane, the dealer sign out front.
func _farm_upgrades(built: Array) -> void:
	if "grain_bins" in built:
		UpgradeKits.big_bin(self, Vector3(-13.6, 0, 2.2))
	if "dryer" in built:
		UpgradeKits.dryer_leg(self, Vector3(-8.0, 0, 16.8), Vector3(-8.25, 0, 13.9),
			[Vector3(-12.0, 9.6, 10.0), Vector3(-4.5, 9.6, 10.0), Vector3(-13.6, 10.4, 2.2)])
	if "precision" in built:
		UpgradeKits.precision(self, Vector3(16.5, 0, 18.0), Vector3(9.0, 0, -17.5),
			Color(_pick(["#a52a1f", "#2f6b2a", "#c46a12"])))
	if "co_op" in built:
		UpgradeKits.grain_trailer(self, Vector3(9.0, 0, -11.0))
	if "seed_dealer" in built:
		UpgradeKits.seed_dealer(self, Vector3(-16.8, 0, -19.4), Vector3(14.5, 0, 9.5))


func _farmstead(look: int) -> void:
	_flat_rect("gravel", -18, 18, -20, 20, 0.08, YARD_GRAVEL)
	_farmhouse(-10.0, -12.0)
	if look >= 1:
		_barn(6.0, 6.0, 14.0, 20.0)
	if look >= 2:
		for i in 2:
			_grain_bin(Vector3(-12.0 + i * 7.5, 0, 10.0), 3.2, 7.0)
	if look >= 3:
		_silo(Vector3(15.5, 0, -6.0), 2.6, 18.0)
	# Shade trees around the house, and a spruce windbreak along the back.
	for p in [Vector3(-17.5, 0, -18.0), Vector3(-2.5, 0, -19.0), Vector3(-19.0, 0, -4.0)]:
		if rng.randf() < 0.8:
			var sp: int = TreeField.Species.MAPLE if rng.randf() < 0.6 else TreeField.Species.OAK
			trees.append([p, sp, _leaf(sp), rng.randf_range(0.95, 1.25)])
	var x := -24.0
	while x < 24.0:
		trees.append([Vector3(x, 0, rng.randf_range(23.0, 25.0)), TreeField.Species.SPRUCE,
			_leaf(TreeField.Species.SPRUCE), rng.randf_range(0.85, 1.1)])
		x += rng.randf_range(4.5, 6.0)


func _leaf(sp: int) -> Color:
	var c: Color = TreeField.LEAF[sp]
	return c.lightened(rng.randf_range(-0.06, 0.08))


## Two storeys, gable roof, full-width porch, a one-storey kitchen ell behind.
func _farmhouse(cx: float, cz: float) -> void:
	var siding := Color(_pick(FARM_SIDING))
	var roof := Color(_pick(ROOF))
	var w := 8.6
	var d := 7.4
	var zf := cz - d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	_box("concrete", Vector3(w + 0.1, 0.6, d + 0.1), Vector3(cx, 0.3, cz), FOUNDATION)
	_box("siding", Vector3(w, 5.8, d), Vector3(cx, 3.5, cz), siding)
	_corners(x0, x1, zf, zf + d, 0.6, 6.4)
	_gable_roof(cx, cz, 6.4, d, rng.randf_range(2.8, 3.4), w, true, roof, siding)
	# Kitchen ell out back.
	var ez := zf + d + 2.6
	_box("concrete", Vector3(5.2, 0.6, 5.2), Vector3(cx + 1.2, 0.3, ez), FOUNDATION)
	_box("siding", Vector3(5.0, 3.0, 5.0), Vector3(cx + 1.2, 2.1, ez), siding)
	_gable_roof(cx + 1.2, ez, 3.6, 5.0, 1.8, 5.0, false, roof, siding)
	# Full front porch.
	var pd := 2.4
	_stoop(cx, zf, w, pd, 0.55)
	for i in 4:
		_box("paint", Vector3(0.2, 2.9, 0.2), Vector3(lerpf(x0 + 0.2, x1 - 0.2, i / 3.0), 2.0, zf - pd + 0.2), TRIM)
	_box("paint", Vector3(w + 0.2, 0.3, 0.24), Vector3(cx, 3.55, zf - pd + 0.2), TRIM)
	_shed_roof(cx, w + 0.4, zf, pd + 0.2, 3.7, 0.5, roof)
	_box("concrete", Vector3(1.8, 0.3, 0.4), Vector3(cx, 0.15, zf - pd - 0.2), FOUNDATION)
	_front_door(cx, zf, 0.6, Color(_pick(DOOR)))
	for i in 3:
		var x := lerpf(x0 + 1.4, x1 - 1.4, i / 2.0)
		_window(Vector3(x, 5.0, zf), Vector3(-1, 0, 0), 0.85, 1.5, true, false, TRIM)
		if i != 1:
			_window(Vector3(x, 2.5, zf), Vector3(-1, 0, 0), 0.85, 1.6, true, false, TRIM)
	for s in [-1.0, 1.0]:
		var sx: float = cx + s * w * 0.5
		var right := Vector3(0, 0, -s)
		_window(Vector3(sx, 2.5, cz), right, 0.85, 1.6, true, false, TRIM)
		_window(Vector3(sx, 5.0, cz), right, 0.85, 1.5, true, false, TRIM)
	_back(x0, x1, zf + d, [5.0], 0.6)
	if rng.randf() < 0.6:
		_box("brick", Vector3(0.9, 3.6, 0.7), Vector3(cx + w * 0.3, 7.6, cz + 0.6), Color(_pick(BRICK)))
	_flat_rect("drive", cx - 0.6, cx + 0.6, zf - 6.0, zf - pd - 0.4, 0.1)
	for i in 4:
		_shrub(Vector3(lerpf(x0 + 0.6, x1 - 0.6, i / 3.0) + rng.randf_range(-0.3, 0.3), 0, zf - pd - 0.9), rng.randf_range(0.5, 0.7))


## A gambrel-roofed dairy barn, gable end to the yard (-z).
func _barn(cx: float, cz: float, w: float, d: float, paint := Color(0, 0, 0, 0), eave := 5.0, roof := GALV) -> void:
	var red := Color(_pick(BARN_RED)) if paint.a == 0.0 else paint
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	var hw := w * 0.5
	# Gambrel profile across the barn: steep lower slope, shallow upper one.
	var prof := [Vector2(-hw, eave), Vector2(-hw * 0.6, eave + 3.2), Vector2(0, eave + 4.6),
		Vector2(hw * 0.6, eave + 3.2), Vector2(hw, eave)]
	_box("concrete", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(cx, 0.25, cz), FOUNDATION)
	_box("metal", Vector3(w, eave - 0.5, d), Vector3(cx, (eave + 0.5) * 0.5, cz), red)
	# Gable ends above the eaves, in the same boards.
	for end in [-1.0, 1.0]:
		var z: float = cz + end * d * 0.5
		for i in prof.size() - 1:
			var a: Vector2 = prof[i]
			var b: Vector2 = prof[i + 1]
			_tri("metal", Vector3(cx + a.x, a.y, z), Vector3(cx + b.x, b.y, z), Vector3(cx, eave, z), red, [], Vector3(0, 0, end))
		# Rake trim following the roof line.
		for i in prof.size() - 1:
			var a: Vector2 = prof[i]
			var b: Vector2 = prof[i + 1]
			var mid := Vector3(cx + (a.x + b.x) * 0.5, (a.y + b.y) * 0.5 + 0.1, z + end * 0.06)
			var along := Vector3(b.x - a.x, b.y - a.y, 0)
			var bas := Basis(along.normalized(), Vector3(0, 0, 1).cross(along.normalized()), Vector3(0, 0, 1))
			_box("paint", Vector3(along.length() + 0.25, 0.22, 0.08), mid, TRIM, bas)
	# Roof: four slopes of galvanised metal, ribs running down the slope.
	var over := 0.5
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		if i == 0:
			a = a + (a - b).normalized() * over
		if i == prof.size() - 2:
			b = b + (b - a).normalized() * over
		var up := Vector3(0, 0.1, 0)
		var pa0 := Vector3(cx + a.x, a.y, z0 - 0.4) + up
		var pa1 := Vector3(cx + a.x, a.y, z1 + 0.4) + up
		var pb0 := Vector3(cx + b.x, b.y, z0 - 0.4) + up
		var pb1 := Vector3(cx + b.x, b.y, z1 + 0.4) + up
		var slope := (b - a).length()
		_quad("metal", pa0, pa1, pb1, pb0, roof, [Vector2(z0, 0), Vector2(z1, 0), Vector2(z1, slope), Vector2(z0, slope)], Vector3.UP)
		_quad("paint", pa0 - up, pa1 - up, pb1 - up, pb0 - up, red.darkened(0.5), [], Vector3.DOWN)
	_corners(cx - hw, cx + hw, z0, z1, 0.5, eave)
	# Big sliding door with a white frame and X brace, and a hayloft door.
	var face := z0 - 0.05
	var dw := 4.8
	var dh := 4.2
	_box("metal", Vector3(dw, dh, 0.08), Vector3(cx, 0.5 + dh * 0.5, face), red.darkened(0.08))
	_frame(Vector3(cx, 0.5 + dh * 0.5, face - 0.05), dw, dh)
	_box("paint", Vector3(dw + 0.8, 0.14, 0.14), Vector3(cx, 0.5 + dh + 0.25, face - 0.08), Color("#3a3a3a"))  # door track
	_frame(Vector3(cx, eave + 1.5, face - 0.05), 1.8, 1.8)
	_box("metal", Vector3(1.8, 1.8, 0.06), Vector3(cx, eave + 1.5, face), red.darkened(0.08))
	# Side windows: small white-framed squares down each long wall.
	for s in [-1.0, 1.0]:
		var n := 5
		for i in n:
			var z := lerpf(z0 + 2.5, z1 - 2.5, float(i) / (n - 1))
			_window(Vector3(cx + s * hw, 2.6, z), Vector3(0, 0, -s), 0.9, 0.9, false, false, TRIM)
	# Cupola on the ridge.
	var ry := eave + 4.6
	_box("paint", Vector3(1.6, 1.4, 1.6), Vector3(cx, ry + 0.5, cz), TRIM)
	_hip_roof(cx, cz, ry + 1.2, 1.6, 1.6, 0.9, GALV)
	# Concrete apron in front of the door.
	_flat_rect("drive", cx - 3.5, cx + 3.5, z0 - 5.0, z0, 0.1)


## A square white frame with an X brace, as on barn doors.
func _frame(c: Vector3, w: float, h: float) -> void:
	var t := 0.16
	_box("paint", Vector3(w + t, t, 0.08), c + Vector3(0, h * 0.5, 0), TRIM)
	_box("paint", Vector3(w + t, t, 0.08), c - Vector3(0, h * 0.5, 0), TRIM)
	_box("paint", Vector3(t, h, 0.08), c + Vector3(w * 0.5, 0, 0), TRIM)
	_box("paint", Vector3(t, h, 0.08), c - Vector3(w * 0.5, 0, 0), TRIM)
	var diag := Vector2(w, h).length()
	for s in [-1.0, 1.0]:
		var bas := Basis(Vector3(0, 0, 1), s * atan2(h, w))
		_box("paint", Vector3(diag - 0.1, t * 0.8, 0.06), c, TRIM, bas)


## A corrugated steel grain bin (GSI, Sukup, Brock): the wall in its rings
## on a concrete pad, a 30 degree ribbed roof with an eave ring and a peak
## collar and cap where the fill spout comes in, a caged ladder up the side
## and the roof ladder up to the peak.
func _grain_bin(base: Vector3, r: float, h: float) -> void:
	var segs := 28 if r > 4.0 else 22
	_box("concrete", Vector3(r * 2.1, 0.3, r * 2.1), base + Vector3(0, 0.15, 0), FOUNDATION)
	_cylinder("bin", base + Vector3(0, 0.3, 0), r, h, BIN, segs)
	var eave := base + Vector3(0, 0.3 + h, 0)
	var rise := r * 0.58  # 30 degrees
	_cone(eave, r + 0.15, rise, BIN.darkened(0.04), segs, "bin")
	_cylinder("bin", eave - Vector3(0, 0.12, 0), r + 0.17, 0.14, BIN.darkened(0.12), segs)  # eave ring
	var peak := eave + Vector3(0, rise * (1.0 - 0.6 / (r + 0.15)), 0)
	_cylinder("bin", peak, 0.55, 0.35, BIN.darkened(0.06), 10)
	_cone(peak + Vector3(0, 0.35, 0), 0.7, 0.3, BIN.darkened(0.1), 10, "bin")
	# The ladder up the road side, in its safety cage, then up the roof.
	var lz := -r - 0.22
	for sx in [-0.22, 0.22]:
		_box("paint", Vector3(0.05, h - 1.8, 0.05), base + Vector3(sx, 2.1 + (h - 1.8) * 0.5, lz), Color("#8a8d8f"))
	var y := 2.6
	while y < h + 0.3:
		_box("paint", Vector3(0.62, 0.05, 0.05), base + Vector3(0, y, lz - 0.38), Color("#8a8d8f"))
		for sx in [-0.31, 0.31]:
			_box("paint", Vector3(0.04, 0.04, 0.4), base + Vector3(sx, y, lz - 0.2), Color("#8a8d8f"))
		y += 1.2
	for sx in [-0.3, 0.0, 0.3]:
		_box("paint", Vector3(0.04, h - 2.6, 0.04), base + Vector3(sx, 2.6 + (h - 2.6) * 0.5, lz - 0.38), Color("#8a8d8f"))
	var a := eave + Vector3(0, 0.12, -r - 0.05)
	var b := peak + Vector3(0, 0.05, -0.55)
	var d := b - a
	var axis := d.normalized()
	_box("paint", Vector3(0.4, d.length(), 0.05), (a + b) * 0.5, Color("#8a8d8f"),
		Basis(Vector3.RIGHT, axis, Vector3.RIGHT.cross(axis)))


## A concrete stave silo with a dome.
func _silo(base: Vector3, r: float, h: float) -> void:
	_cylinder("paint", base, r, h, STAVE, 18)
	_cone(base + Vector3(0, h, 0), r + 0.1, r * 0.8, GALV)
	_box("paint", Vector3(0.6, h - 1.0, 0.5), base + Vector3(0, (h - 1.0) * 0.5, -r - 0.2), STAVE.darkened(0.1))  # chute


func _cone(base: Vector3, r: float, h: float, col: Color, segs := 20, mat := "metal") -> void:
	var apex := base + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var out := ((p0 + p1) * 0.5 - base).normalized() + Vector3(0, 0.6, 0)
		var slant := Vector2(r, h).length()
		_tri(mat, p0, p1, apex, col, [Vector2(r * a0, 0), Vector2(r * a1, 0), Vector2(r * (a0 + a1) * 0.5, slant)], out)


# --- Livestock barns (Livestock) -------------------------------------------------
# One barn group on its 80 x 40 m pad beside the farmyard, in the same local
# frame as the farmstead (-z toward the road, +x along it). Benchmarks:
# photos of contract finishing barns and turkey barns around Dubois County,
# Indiana, and freestall dairies in northern Indiana.
const BARN_WHITE := Color("#e9e9e4")
const CURTAIN := Color("#e3dcc2")      # woven poly side curtains
const FAN_BLACK := Color("#2a2b2c")
const LAGOON := Color("#4a4632")


## [barn mesh, ground mesh, trees] for a barn group of this kind.
static func build_barns(kind: String, seed: int) -> Array:
	var b := FarmBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"hogs": b._hog_site()
		"turkeys": b._turkey_site()
		"dairy": b._dairy_site()
	return [b._commit_house(), b._commit_flat(), b.trees]


## Two 1,200-head tunnel-ventilated finishing barns (41 x 204 ft): a low
## concrete wall over the manure pit, side curtains, white steel above, a
## shallow galvanised roof, the big tunnel fans on one end and bulk feed
## bins by the other.
func _hog_site() -> void:
	_flat_rect("gravel", -40, 40, -20, -14, 0.06, YARD_GRAVEL)
	_flat_rect("gravel", -40, -33, -14, 20, 0.06, YARD_GRAVEL)
	for z in [-6.5, 9.5]:
		_livestock_barn(Vector3(1.0, 0, z), 62.0, 12.5, 2.9, 2.1, 1.0, true)
		for i in 2:
			_feed_bin(Vector3(-35.5, 0, z - 3.0 + i * 6.0), 1.5, 5.5)


## Two 50 x 500 ft turkey barns, shortened to the pad: curtain sides nearly
## the full wall height, a ridge vent and feed bins at the end.
func _turkey_site() -> void:
	_flat_rect("gravel", -40, 40, -20, -15, 0.06, YARD_GRAVEL)
	for z in [-7.0, 10.0]:
		_livestock_barn(Vector3(2.0, 0, z), 70.0, 13.5, 3.0, 2.4, 0.6, false)
		_feed_bin(Vector3(-36.5, 0, z), 1.6, 6.0)


## A 500-cow freestall barn (open sides with curtains, a tall roof with a
## ridge vent), the milking parlor and milk house, a silage bunker under
## black plastic and tyres, and the manure lagoon.
func _dairy_site() -> void:
	_flat_rect("gravel", -40, 40, -20, -14, 0.06, YARD_GRAVEL)
	_flat_rect("drive", 16, 40, -14, 3, 0.07)
	_livestock_barn(Vector3(-10.0, 0, -2.0), 54.0, 24.0, 4.2, 3.6, 0.9, false)
	# Parlor and milk house, white steel with a gable roof, by the barn's end.
	_box("concrete", Vector3(16.2, 0.4, 10.2), Vector3(28.0, 0.2, -6.0), FOUNDATION)
	_box("metal", Vector3(16.0, 3.4, 10.0), Vector3(28.0, 2.1, -6.0), BARN_WHITE)
	_gable_roof(28.0, -6.0, 3.8, 10.0, 1.6, 16.0, true, GALV, BARN_WHITE, false)
	_box("paint", Vector3(2.4, 2.6, 0.1), Vector3(32.0, 1.7, -11.05), Color("#7d8082"))  # tanker bay door
	# Bunker silo: two concrete walls, silage under black plastic held by tyres.
	for s in [-1.0, 1.0]:
		_box("concrete", Vector3(18.0, 2.6, 0.5), Vector3(28.0, 1.3, 10.0 + s * 4.5), FOUNDATION)
	_box("paint", Vector3(17.6, 1.9, 8.5), Vector3(28.5, 0.95, 10.0), Color("#1e1f1e"))
	# The lagoon: a shallow earthen basin of dark liquid behind the barn.
	_box("paint", Vector3(30.0, 0.12, 6.0), Vector3(-12.0, 0.04, 16.5), LAGOON)
	_box("paint", Vector3(31.0, 0.4, 0.8), Vector3(-12.0, 0.2, 13.2), Color("#6c6a45"))  # berm


## One long low livestock barn along x: concrete stem wall, side curtains
## from `curtain_y` up, white steel to the eave, a gable roof, and tunnel
## fans on the +x end when `tunnel`.
func _livestock_barn(c: Vector3, l: float, w: float, eave: float, rise: float, curtain_y: float, tunnel: bool) -> void:
	var top := eave - 0.45
	_box("concrete", Vector3(l + 0.2, 0.3, w + 0.2), c + Vector3(0, 0.15, 0), FOUNDATION)
	_box("concrete", Vector3(l, curtain_y, w), c + Vector3(0, curtain_y * 0.5, 0), FOUNDATION.lightened(0.05))
	_box("paint", Vector3(l - 0.2, top - curtain_y, w - 0.1), c + Vector3(0, (curtain_y + top) * 0.5, 0), CURTAIN)
	_box("metal", Vector3(l, eave - top, w), c + Vector3(0, (top + eave) * 0.5, 0), BARN_WHITE)
	# Solid steel end walls.
	for s in [-1.0, 1.0]:
		_box("metal", Vector3(0.2, eave - curtain_y, w), c + Vector3(s * l * 0.5, (curtain_y + eave) * 0.5, 0), BARN_WHITE)
	_gable_roof(c.x, c.z, eave, w, rise, l, true, GALV, BARN_WHITE, false)
	# A ridge vent cap along the top.
	_box("metal", Vector3(l - 2.0, 0.35, 1.0), c + Vector3(0, eave + rise + 0.25, 0), GALV.darkened(0.08))
	if tunnel:
		var n := maxi(2, int(w / 3.0))
		for i in n:
			var z := lerpf(-w * 0.5 + 1.6, w * 0.5 - 1.6, float(i) / (n - 1))
			_box("paint", Vector3(0.7, 1.5, 1.5), c + Vector3(l * 0.5 + 0.4, 1.3, z), FAN_BLACK)
			_box("paint", Vector3(0.12, 1.3, 1.3), c + Vector3(l * 0.5 + 0.8, 1.3, z), Color("#4b4d4f"))
	# A walk-in door and a load-out chute on the front side.
	_box("paint", Vector3(1.0, 2.1, 0.1), c + Vector3(-l * 0.5 + 3.0, 1.05, -w * 0.5 - 0.06), BARN_WHITE.darkened(0.12))
	_box("concrete", Vector3(2.4, 0.9, 3.0), c + Vector3(-l * 0.5 + 8.0, 0.45, -w * 0.5 - 1.5), FOUNDATION)


## A galvanised bulk feed bin on legs with a hopper bottom and cone top.
func _feed_bin(base: Vector3, r: float, h: float) -> void:
	var lift := 2.2
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_box("metal", Vector3(0.18, lift + 0.6, 0.18), base + Vector3(s.x * r * 0.7, (lift + 0.6) * 0.5, s.y * r * 0.7), GALV.darkened(0.1))
	_cylinder("metal", base + Vector3(0, lift, 0), r * 0.45, 0.8, BIN.darkened(0.06), 12)  # hopper
	_cylinder("metal", base + Vector3(0, lift + 0.8, 0), r, h, BIN, 16)
	_cone(base + Vector3(0, lift + 0.8 + h, 0), r + 0.1, r * 0.6, BIN.darkened(0.04))


# --- County farmsteads close up (FarmsteadNear) ----------------------------------
# The close-up of a county farmstead, grown from its FarmsteadPlan in the
# plan's own frame (x along the road, -z toward it, the farmhouse's front
# wall at z = 0), the same frame the far version (FarmsteadFar) draws in.
# Built a step a frame (the house, the yard, then each building), so no
# frame freezes. Each building stands on its own ground: the land under a
# farmstead falls 2 m on a typical one (6 m on one in ten), so every part is
# lifted to the ground under it, and the gravel is draped over the land.

## Set while a part is drawn: moves (and, for a sagging barn, leans) it.
var part_xf := Transform3D.IDENTITY
var _xf_on := false
var _county := {}
var _county_base := 0.0
var _lawn := SurfaceTool.new()
var _gravel := SurfaceTool.new()  # the county farmstead's gravel ("farm_gravel")
const POLE_BROWN := Color("#4a3f33")
const STONE := Color("#8d887c")


func _box(mat: String, size: Vector3, center: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	if _xf_on:
		center = part_xf * center
		basis = part_xf.basis * basis
	super(mat, size, center, col, basis)


func _quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uvs := [],
		want := Vector3.ZERO) -> void:
	if _xf_on:
		a = part_xf * a
		b = part_xf * b
		c = part_xf * c
		d = part_xf * d
		want = part_xf.basis * want
	super(mat, a, b, c, d, col, uvs, want)


func _tri(mat: String, a: Vector3, b: Vector3, c: Vector3, col: Color, uvs := [],
		want := Vector3.ZERO) -> void:
	if _xf_on:
		a = part_xf * a
		b = part_xf * b
		c = part_xf * c
		want = part_xf.basis * want
	super(mat, a, b, c, col, uvs, want)


## A builder for a county farmstead's close-up: call step(i) for i in
## steps(), then commit().
static func county(p: Dictionary) -> FarmBuilder:
	var b := FarmBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = CropCalendar.hash32(int(p.at.x), int(p.at.y), p.seed + 977)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._county = p
	b._county_base = Terrain.height(p.at.x, p.at.y)
	return b


func steps() -> int:
	return 3 + (_county.parts as Array).size()


## The ground under a local point, as a lift above the farmstead's base.
func lift_at(q: Vector2) -> float:
	var r := FarmsteadPlan.to_region(_county, q)
	return Terrain.height(r.x, r.y) - _county_base


func _stand(c: Vector2, half_size := Vector2.ZERO, lean := 0.0) -> void:
	var lo := lift_at(c)
	if half_size != Vector2.ZERO:
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			lo = minf(lo, lift_at(c + half_size * d))
	var basis := Basis.IDENTITY
	if lean != 0.0:
		basis = Basis(Vector3(1, 0, 0), Vector3(lean, 1, 0), Vector3(0, 0, 1))
	part_xf = Transform3D(basis, Vector3(0, lo, 0))
	_xf_on = true


func step(i: int) -> void:
	var p := _county
	owner_care = 0
	match i:
		0: _county_house(p.house)
		1: _county_ground(p)
		_ when i - 2 >= (p.parts as Array).size(): _county_yard_things(p)
		_:
			var part: Dictionary = p.parts[i - 2]
			match part.kind:
				"barn": _county_barn(part)
				"shed": _county_shed(part)
				"quonset": _county_quonset(part)
				"bin":
					_stand(part.pos, Vector2.ONE * part.r)
					_grain_bin(Vector3(part.pos.x, 0, part.pos.y), part.r, part.h)
					# The aeration fan and transition at the foot.
					_box("paint", Vector3(0.9, 0.9, 1.2), Vector3(part.pos.x, 0.75, part.pos.y - part.r - 0.5), Color("#5a5e60"))
				"dryer": _county_dryer(part)
				"silo": _county_silo(part)
				"windmill": _county_windmill(part)
				"hog_barn":
					_stand(part.pos, Vector2(part.l, part.w) * 0.5)
					_livestock_barn(Vector3(part.pos.x, 0, part.pos.y), part.l, part.w, 2.9, 2.1, 1.0, true)
				"feed_bin":
					_stand(part.pos)
					_feed_bin(Vector3(part.pos.x, 0, part.pos.y), part.r, part.h)
				"milk_house":
					_stand(part.pos, Vector2(part.w, part.l) * 0.5)
					var c := Vector3(part.pos.x, 0, part.pos.y)
					_box("concrete", Vector3(part.w + 0.2, 0.4, part.l + 0.2), c + Vector3(0, 0.2, 0), FOUNDATION)
					_box("metal", Vector3(part.w, 3.0, part.l), c + Vector3(0, 1.9, 0), BARN_WHITE)
					_gable_roof(c.x, c.z, 3.4, part.l, 1.0, part.w, false, GALV, BARN_WHITE, false)
	_xf_on = false
	owner_care = 0


## [buildings mesh, ground mesh, grass mesh].
func commit() -> Array:
	owner_care = 0
	_xf_on = false
	var grass := _lawn.commit()
	if grass.get_surface_count() > 0:
		grass.surface_set_material(0, HouseMaterials.get_mat("pasture"))
	var house := _commit_house()
	var flat := _commit_flat()
	if not _county.is_empty():
		var g := _gravel.commit_to_arrays()
		if not g.is_empty() and g[Mesh.ARRAY_VERTEX] != null and not (g[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g)
			flat.surface_set_material(flat.get_surface_count() - 1, HouseMaterials.get_mat("farm_gravel"))
	return [house, flat, grass]


## The farmhouse: the house builder's own plan of its type and era (an
## I-house, gabled-ell farmhouse, foursquare, ranch or two-storey), moved
## to the plan's spot. An empty house is boarded up and weathered.
func _county_house(h: Dictionary) -> void:
	var was_kind := HouseBuilder.force_kind
	HouseBuilder.force_kind = h.type
	era = h.era
	half = 15.0
	depth = 30.0
	_cell_seed = CropCalendar.hash32(int(_county.at.x), int(_county.at.y), 31)
	owner_care = -2 if h.vacant else 0
	var body := _plan(0)
	HouseBuilder.force_kind = was_kind
	var info: Dictionary = body.info
	var lift := lift_at(Vector2(h.x, h.d * 0.5))
	for d in [Vector2(-h.w, 0), Vector2(h.w, 0), Vector2(0, h.d)]:
		lift = minf(lift, lift_at(Vector2(h.x, 0) + d * 0.5))
	var xf := Transform3D(Basis.IDENTITY, Vector3(h.x - (float(info.x0) + float(info.x1)) * 0.5, lift, -float(info.front_z)))
	var arrays := {}
	for mat in body.arrays:
		var a: Array = (body.arrays[mat] as Array).duplicate()
		a[Mesh.ARRAY_VERTEX] = xf * (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		arrays[mat] = a
	_body = arrays
	if h.vacant:
		_board_up(arrays.get("glass", []))
	# Foundation carried down to the lowest ground along the front.
	part_xf = Transform3D(Basis.IDENTITY, Vector3(0, lift, 0))
	_xf_on = true
	_box("concrete", Vector3(float(info.x1) - float(info.x0), 1.2, 0.3), Vector3(h.x, -0.45, 0.1), FOUNDATION)
	_xf_on = false
	owner_care = 0


## The small things about the house: the propane tank that heats it
## (nearly every Indiana farmhouse past the gas mains has one), on two
## concrete blocks off the side of the house away from the drive, 10 ft or
## more from the wall (NFPA 58); 1,000 gal on a farm, 500 at a country
## home. A grain farm with a dryer has a bigger one by the dryer.
func _county_yard_things(p: Dictionary) -> void:
	var h: Dictionary = p.house
	var s: float = p.side
	if not h.vacant:
		var c := Vector2(h.x - s * (h.w * 0.5 + 4.2), h.d * 0.55)
		_lp_tank(c, 1000 if p.kind != "home" else 500)
	for part in p.parts:
		if part.kind == "dryer":
			var at: Vector2 = part.dryer_at
			_lp_tank(at + Vector2(-s * 7.0, 6.0), 2000)


## A white propane tank lying along z at `c`: 500 gal is 37 in by 10 ft,
## 1,000 gal 41 in by 16 ft, 2,000 gal 46 in by 20 ft, with rounded heads,
## the dome over the valves on top, on two concrete piers.
func _lp_tank(c: Vector2, gal: int) -> void:
	var dims := {500: Vector2(0.94, 3.05), 1000: Vector2(1.04, 4.9), 2000: Vector2(1.17, 6.1)}
	var d: Vector2 = dims[gal]
	var r := d.x * 0.5
	var l := d.y - d.x  # the barrel between the heads
	_stand(c, Vector2(r, d.y * 0.5))
	var lift := part_xf.origin.y
	var y := 0.35 + r
	for k in [-1.0, 1.0]:
		_box("concrete", Vector3(0.6, 0.4, 0.4), Vector3(c.x, 0.2, c.y + k * l * 0.3), FOUNDATION)
	var white := Color("#eeeeea")
	part_xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, lift + y, c.y - l * 0.5))
	_cylinder("paint", Vector3.ZERO, r, l, white, 14)
	_cone(Vector3(0, l, 0), r, r * 0.55, white, 14, "paint")
	part_xf = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(c.x, lift + y, c.y - l * 0.5))
	_cone(Vector3.ZERO, r, r * 0.55, white, 14, "paint")
	part_xf = Transform3D(Basis.IDENTITY, Vector3(0, lift, 0))
	_cylinder("paint", Vector3(c.x, y + r - 0.05, c.y), 0.22, 0.22, white.darkened(0.04), 10)
	_box("paint", Vector3(0.12, 0.12, 0.25), Vector3(c.x + r * 0.6, y + 0.1, c.y), Color("#8a8d8f"))  # regulator
	_xf_on = false


## The gravel yard, lane and drive, draped over the land; the mailbox at
## the road and the yard light's pole.
func _county_ground(p: Dictionary) -> void:
	# The grounds' mown grass (no crop grows inside the windbreak), then
	# the gravel over it.
	_lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	_drape(p.grounds, Color("#4f6a2e") if not p.house.vacant else Color("#727a40"), _lawn, FarmsteadPlan.LAWN_LIFT, 12.0)
	_gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in p.gravel.size():
		# Each piece a little over the last, so the yard lies over its drive.
		_drape(p.gravel[i], YARD_GRAVEL, _gravel, FarmsteadPlan.GRAVEL_LIFT + i * 0.01, 8.0, true)
	# The mailbox: a 4 x 4 post, a standard rural box (about 19 x 6.5 x 9 in)
	# 42 in up, its door to the road, the red flag down.
	var mb: Vector2 = p.mailbox
	_stand(mb)
	_box("paint", Vector3(0.09, 1.1, 0.09), Vector3(mb.x, 0.55, mb.y), Color("#6b5a45"))
	_box("paint", Vector3(0.2, 0.06, 0.5), Vector3(mb.x, 1.0, mb.y - 0.1), Color("#6b5a45"))
	_box("metal", Vector3(0.17, 0.2, 0.48), Vector3(mb.x, 1.13, mb.y - 0.1), Color("#2b2c2e") if rng.randf() < 0.6 else Color("#d8d6cf"))
	_box("paint", Vector3(0.02, 0.2, 0.05), Vector3(mb.x + 0.1, 1.15, mb.y + 0.05), Color("#b3261e"))
	_xf_on = false
	if not p.light.is_empty():
		# A wooden utility pole, the lamp on a short arm about 25 ft up.
		var at: Vector2 = p.light.pos
		var h: float = p.light.h
		_stand(at)
		_cylinder("paint", Vector3(at.x, -0.3, at.y), 0.14, h + 1.3, POLE_BROWN, 8)
		_box("paint", Vector3(0.08, 0.08, 1.4), Vector3(at.x, h + 0.2, at.y - 0.7), Color("#8d8f8c"))
		_box("paint", Vector3(0.35, 0.18, 0.6), Vector3(at.x, h, at.y - 1.4), Color("#9a9c98"))
		_xf_on = false


## A flat rectangle of ground work draped over the land in `step` m
## pieces, `above` metres over it, into `st`.
## `local` UVs are metres inside the piece and UV2 its size (the gravel
## shader's edges and lanes), else metres / 4 over the land.
func _drape(r: Rect2, col: Color, st: SurfaceTool, above: float, step_m := 8.0, local := false) -> void:
	var nx := clampi(ceili(r.size.x / step_m), 1, 32)
	var nz := clampi(ceili(r.size.y / step_m), 1, 64)
	col.a = 1.0
	var hs := []
	for i in nx + 1:
		var row := []
		for j in nz + 1:
			var q := r.position + r.size * Vector2(float(i) / nx, float(j) / nz)
			row.append(Vector3(q.x, lift_at(q) + above, q.y))
		hs.append(row)
	for i in nx:
		for j in nz:
			var a: Vector3 = hs[i][j]
			var b: Vector3 = hs[i + 1][j]
			var c: Vector3 = hs[i + 1][j + 1]
			var d: Vector3 = hs[i][j + 1]
			for v in [a, b, c, a, c, d]:  # clockwise seen from above
				st.set_normal(Vector3.UP)
				st.set_color(col)
				if local:
					st.set_uv(Vector2(v.x, v.z) - r.position)
					st.set_uv2(r.size)
				else:
					st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)


## The barn as its plan says: a gambrel hay barn or a gable bank barn, in
## its paint, weathered by its upkeep, a sagging one leaning, a fallen one
## a heap with one gable end standing.
func _county_barn(b: Dictionary) -> void:
	var c: Vector2 = b.pos
	var cond: String = b.cond
	var lean := 0.0
	match cond:
		"weathered": owner_care = -1
		"sagging":
			owner_care = -2
			lean = float(b.lean) * 0.035
		"fallen": owner_care = -2
	_stand(c, Vector2(b.w, b.l) * 0.5, lean)
	var roof := GALV if cond == "kept" else Color("#7d6450")
	if cond == "fallen":
		_fallen_barn(c, b.w, b.l, b.paint)
	elif b.style == "gambrel":
		_barn(c.x, c.y, b.w, b.l, b.paint, b.eave, roof)
	else:
		_bank_barn(c.x, c.y, b.w, b.l, b.paint, b.eave, roof)


## A bank barn: a fieldstone lower storey for the stock, frame walls of
## vertical boards above, a gable roof along its length, and an earthen
## bank up to the big threshing-floor doors on the long side away from the
## yard (built 1850-1910 across Indiana).
func _bank_barn(cx: float, cz: float, w: float, d: float, paint: Color, eave: float, roof: Color) -> void:
	var hw := w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	var rise := hw * 0.75
	var ramp := -float(_county.side)  # the bank side, away from the yard
	_box("concrete", Vector3(w + 0.3, 2.6, d + 0.3), Vector3(cx, 1.0, cz), STONE)
	_box("metal", Vector3(w, eave - 2.3, d), Vector3(cx, 2.3 + (eave - 2.3) * 0.5, cz), paint)
	# Gable ends in the same boards, and the roof.
	for e in [-1.0, 1.0]:
		var z: float = cz + e * d * 0.5
		_tri("metal", Vector3(cx - hw, eave, z), Vector3(cx + hw, eave, z), Vector3(cx, eave + rise, z), paint, [], Vector3(0, 0, e))
	var over := 0.5
	for s in [-1.0, 1.0]:
		var e0 := Vector3(cx + s * (hw + over), eave - over * 0.75, z0 - 0.4)
		var e1 := Vector3(cx + s * (hw + over), eave - over * 0.75, z1 + 0.4)
		var r0 := Vector3(cx, eave + rise + 0.05, z0 - 0.4)
		var r1 := Vector3(cx, eave + rise + 0.05, z1 + 0.4)
		var slope := Vector2(hw + over, rise).length()
		_quad("metal", e0, e1, r1, r0, roof, [Vector2(z0, 0), Vector2(z1, 0), Vector2(z1, slope), Vector2(z0, slope)], Vector3(s, 1, 0))
		_quad("paint", e0 - Vector3(0, 0.08, 0), e1 - Vector3(0, 0.08, 0), r1 - Vector3(0, 0.08, 0), r0 - Vector3(0, 0.08, 0),
			paint.darkened(0.5), [], Vector3.DOWN)
	_corners(cx - hw, cx + hw, z0, z1, 2.3, eave)
	# The bank and its doors: a grassed ramp up to two big doors.
	var bx := cx + ramp * hw
	_box("metal", Vector3(0.1, 3.8, 4.4), Vector3(bx + ramp * 0.05, 2.3 + 1.9, cz), paint.darkened(0.12))
	_frame_side(Vector3(bx + ramp * 0.1, 2.3 + 1.9, cz), 4.4, 3.8, ramp)
	var bank := Color("#5f6b3a")
	_quad("paint", Vector3(bx, 2.3, cz - 3.0), Vector3(bx, 2.3, cz + 3.0), Vector3(bx + ramp * 7.0, 0.0, cz + 3.5),
		Vector3(bx + ramp * 7.0, 0.0, cz - 3.5), bank, [], Vector3(ramp, 1, 0))
	for e in [-1.0, 1.0]:
		_tri("paint", Vector3(bx, 2.3, cz + e * 3.0), Vector3(bx + ramp * 7.0, 0.0, cz + e * 3.5), Vector3(bx, 0.0, cz + e * 3.0),
			bank.darkened(0.15), [], Vector3(0, 0, e))
	# Stable doors in the stone along the yard side, a loft door in the gable.
	for i in 3:
		var z := lerpf(z0 + 3.0, z1 - 3.0, i / 2.0)
		_box("paint", Vector3(0.1, 2.0, 1.4), Vector3(cx - ramp * (hw + 0.12), 1.0, z), Color("#4a3a2c"))
	_frame(Vector3(cx, eave * 0.55 + 1.0, z0 - 0.1), 1.6, 1.6)
	_box("metal", Vector3(1.6, 1.6, 0.06), Vector3(cx, eave * 0.55 + 1.0, z0 - 0.05), paint.darkened(0.1))


## A door frame with an X brace on a wall facing x (`out` its side).
func _frame_side(c: Vector3, w: float, h: float, out: float) -> void:
	var t := 0.16
	var x := c.x + out * 0.05
	for dz in [-w * 0.5, w * 0.5]:
		_box("paint", Vector3(0.08, h, t), Vector3(x, c.y, c.z + dz), TRIM)
	for dy in [-h * 0.5, h * 0.5]:
		_box("paint", Vector3(0.08, t, w + t), Vector3(x, c.y + dy, c.z), TRIM)
	var diag := Vector2(w, h).length()
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.06, t * 0.8, diag - 0.1), Vector3(x, c.y, c.z), TRIM, Basis(Vector3(1, 0, 0), s * atan2(h, w)))


## A barn fallen in: the roof steel down in a heap of boards, one gable
## end and a corner post still standing.
func _fallen_barn(c: Vector2, w: float, l: float, paint: Color) -> void:
	_box("concrete", Vector3(w + 0.2, 0.5, l + 0.2), Vector3(c.x, 0.1, c.y), STONE)
	for i in 6:
		var a := rng.randf_range(-0.5, 0.5)
		var t := rng.randf_range(0.2, 0.45)
		var at := Vector3(c.x + rng.randf_range(-w, w) * 0.3, 0.9 + i * 0.25, c.y + rng.randf_range(-l, l) * 0.35)
		_box("metal", Vector3(w * rng.randf_range(0.4, 0.7), 0.06, l * rng.randf_range(0.25, 0.4)), at,
			Color("#7d6450") if i % 2 == 0 else paint, Basis(Vector3.UP, a) * Basis(Vector3(1, 0, 0), t))
	var z := c.y + l * 0.5
	_box("metal", Vector3(w, 4.5, 0.2), Vector3(c.x, 2.4, z), paint)
	_tri("metal", Vector3(c.x - w * 0.5, 4.65, z), Vector3(c.x + w * 0.5, 4.65, z), Vector3(c.x, 4.65 + w * 0.4, z), paint, [], Vector3(0, 0, 1))
	_box("paint", Vector3(0.25, 5.0, 0.25), Vector3(c.x - w * 0.5, 2.5, c.y - l * 0.5), Color("#5d5145"))


## A post-frame machine shed: steel walls and roof (4 in 12), a wainscot
## band, a big sliding or overhead door and a walk door on the yard side.
## A home's detached garage is the small one in the house's own siding.
func _county_shed(s: Dictionary) -> void:
	var c: Vector2 = s.pos
	var l: float = s.l
	var w: float = s.w
	var eave: float = s.eave
	_stand(c, Vector2(l, w) * 0.5)
	var wall: Color = s.wall
	var roof: Color = s.roof
	var cx := c.x
	var cz := c.y
	_box("concrete", Vector3(l + 0.2, 0.5, w + 0.2), Vector3(cx, 0.0, cz), FOUNDATION)
	if s.get("garage", false):
		_box("siding", Vector3(l, eave, w), Vector3(cx, eave * 0.5 + 0.2, cz), wall)
		_gable_roof(cx, cz, eave + 0.2, w, 1.6, l, true, roof, wall, false)
		_box("paint", Vector3(4.8, 2.2, 0.08), Vector3(cx, 1.3, cz - w * 0.5 - 0.04), TRIM)
		return
	_box("metal", Vector3(l, eave, w), Vector3(cx, eave * 0.5 + 0.2, cz), wall)
	_box("metal", Vector3(l + 0.06, 0.9, w + 0.06), Vector3(cx, 0.65, cz), wall.darkened(0.35))
	var rise := w * 0.5 * 4.0 / 12.0
	var over := 0.35
	var top := eave + 0.2
	for sd in [-1.0, 1.0]:
		var e0 := Vector3(cx - l * 0.5 - 0.25, top - over / 3.0, cz + sd * (w * 0.5 + over))
		var e1 := Vector3(cx + l * 0.5 + 0.25, top - over / 3.0, cz + sd * (w * 0.5 + over))
		var r0 := Vector3(cx - l * 0.5 - 0.25, top + rise, cz)
		var r1 := Vector3(cx + l * 0.5 + 0.25, top + rise, cz)
		var slope := Vector2(w * 0.5 + over, rise).length()
		_quad("metal", e0, e1, r1, r0, roof, [Vector2(e0.x, 0), Vector2(e1.x, 0), Vector2(e1.x, slope), Vector2(e0.x, slope)], Vector3(0, 1, sd))
		_quad("paint", e0 - Vector3(0, 0.06, 0), e1 - Vector3(0, 0.06, 0), r1 - Vector3(0, 0.06, 0), r0 - Vector3(0, 0.06, 0),
			SOFFIT.darkened(0.3), [], Vector3.DOWN)
	for e in [-1.0, 1.0]:
		var x: float = cx + e * l * 0.5
		_tri("metal", Vector3(x, top, cz - w * 0.5), Vector3(x, top, cz + w * 0.5), Vector3(x, top + rise, cz), wall, [], Vector3(e, 0, 0))
	# Corner trim in the roof colour.
	for e in [-1.0, 1.0]:
		for sd in [-1.0, 1.0]:
			_box("paint", Vector3(0.12, eave, 0.12), Vector3(cx + e * l * 0.5, top * 0.5, cz + sd * w * 0.5), roof)
	# Doors on the yard side (-z): a big door (sliding on an older shed,
	# overhead or bi-fold on a newer one) and a walk door.
	var face := cz - w * 0.5 - 0.05
	var dw := minf(l * 0.45, 9.0 + (3.0 if s.year > 1995 else 0.0))
	var dh := minf(eave - 0.6, 4.9)
	var dx := cx - l * 0.18
	_box("metal", Vector3(dw, dh, 0.08), Vector3(dx, 0.2 + dh * 0.5, face), wall.darkened(0.12) if s.year < 1995 else Color("#e8e6df"))
	_box("paint", Vector3(dw + 0.6, 0.12, 0.12), Vector3(dx, 0.3 + dh, face - 0.05), Color("#3a3a3a"))
	_box("paint", Vector3(0.95, 2.1, 0.08), Vector3(cx + l * 0.3, 1.25, face), Color("#e8e6df"))


## A Quonset hut: corrugated steel arches on a slab, end walls of steel.
func _county_quonset(s: Dictionary) -> void:
	var c: Vector2 = s.pos
	var l: float = s.l
	var r: float = s.w * 0.5
	_stand(c, Vector2(l * 0.5, r))
	var steel := Color("#a3a59f")
	_box("concrete", Vector3(l + 0.2, 0.4, r * 2.0 + 0.2), Vector3(c.x, 0.0, c.y), FOUNDATION)
	var n := 14
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var p0 := Vector2(-cos(a0) * r, sin(a0) * r)
		var p1 := Vector2(-cos(a1) * r, sin(a1) * r)
		_quad("metal", Vector3(c.x - l * 0.5, p0.y + 0.2, c.y + p0.x), Vector3(c.x + l * 0.5, p0.y + 0.2, c.y + p0.x),
			Vector3(c.x + l * 0.5, p1.y + 0.2, c.y + p1.x), Vector3(c.x - l * 0.5, p1.y + 0.2, c.y + p1.x), steel,
			[Vector2(-l * 0.5, a0 * r), Vector2(l * 0.5, a0 * r), Vector2(l * 0.5, a1 * r), Vector2(-l * 0.5, a1 * r)],
			Vector3(0, sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5)))
		for e in [-1.0, 1.0]:
			_tri("metal", Vector3(c.x + e * l * 0.5, 0.2, c.y), Vector3(c.x + e * l * 0.5, p0.y + 0.2, c.y + p0.x),
				Vector3(c.x + e * l * 0.5, p1.y + 0.2, c.y + p1.x), steel.darkened(0.08), [], Vector3(e, 0, 0))
	_box("metal", Vector3(0.08, r * 1.1, r * 1.2), Vector3(c.x - l * 0.5 - 0.05, r * 0.55 + 0.2, c.y), steel.darkened(0.25))


## The dryer and bucket elevator leg (UpgradeKits), with spouts to each bin.
func _county_dryer(d: Dictionary) -> void:
	var leg: Vector2 = d.pos
	var at: Vector2 = d.dryer_at
	_stand(leg)
	var base := part_xf.origin.y
	var tops := []
	for b in d.bins:
		var bp: Vector2 = b.pos
		tops.append(Vector3(bp.x, b.h + 0.3 + b.r * 0.7 + lift_at(bp) - base, bp.y))
	UpgradeKits.dryer_leg(self, Vector3(at.x, 0, at.y), Vector3(leg.x, 0, leg.y), tops)


## A concrete stave silo: hooped staves, a chute up its side, a dome (or
## open to the sky on one long unused); a dairy's blue Harvestore.
func _county_silo(s: Dictionary) -> void:
	var c: Vector2 = s.pos
	var r: float = s.r
	var h: float = s.h
	_stand(c, Vector2.ONE * r)
	var base := Vector3(c.x, 0, c.y)
	if s.harvestore:
		var blue := Color("#2f4f7a")
		_cylinder("metal", base, r + 0.6, h + 3.0, blue, 18)
		_cone(base + Vector3(0, h + 3.0, 0), r + 0.7, (r + 0.7) * 0.45, blue)
		return
	var stave := FarmsteadPlan.STAVE if s.used else FarmsteadPlan.STAVE.darkened(0.12)
	_cylinder("paint", base, r, h, stave, 18)
	# Steel hoops round the staves, closer together toward the foot.
	var y := 0.6
	while y < h:
		_cylinder("paint", base + Vector3(0, y, 0), r + 0.03, 0.05, Color("#5d5a54"), 12)
		y += 0.6 + y * 0.03
	if s.dome:
		_cone(base + Vector3(0, h, 0), r + 0.1, r * 0.8, GALV if s.used else Color("#8a7a68"))
	_box("paint", Vector3(0.7, h - 1.0, 0.6), base + Vector3(0, (h - 1.0) * 0.5, -r - 0.25), stave.darkened(0.1))


## An old farm windmill: a galvanised four-legged tower, girts between the
## legs, the wheel of 18 steel blades facing the wind with its tail vane
## behind, the pump rod down to the well.
func _county_windmill(w: Dictionary) -> void:
	var c: Vector2 = w.pos
	_stand(c)
	var h: float = w.h
	var steel := Color("#9a9c98")
	var foot := h * 0.09
	var head := 0.35
	var top := Vector3(c.x, h, c.y)
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for d: Vector2 in corners:
		UpgradeKits._strut(self, Vector3(c.x + d.x * foot, 0.0, c.y + d.y * foot), top + Vector3(d.x, 0, d.y) * head, 0.07, steel)
	var y := 2.5
	while y < h - 1.0:
		var k := lerpf(foot, head, y / h)
		for i in 4:
			var a: Vector2 = corners[i] * k
			var b: Vector2 = corners[(i + 1) % 4] * k
			UpgradeKits._strut(self, Vector3(c.x + a.x, y, c.y + a.y), Vector3(c.x + b.x, y, c.y + b.y), 0.04, steel)
		y += 2.6
	_box("paint", Vector3(1.2, 0.08, 1.2), top + Vector3(0, -0.4, 0), steel.darkened(0.2))  # platform
	var ax := Vector3(cos(w.yaw), 0, sin(w.yaw))
	var side := Vector3.UP.cross(ax).normalized()
	var hub := top + Vector3(0, 0.5, 0) + ax * 0.6
	var r: float = w.wheel * 0.5
	_box("paint", Vector3(0.5, 0.5, 0.5), top + Vector3(0, 0.45, 0), steel.darkened(0.15))  # gearbox
	for i in 18:
		if w.broken and (i % 4 == 1 or i % 7 == 3):
			continue
		var a := TAU * i / 18.0
		var dir := side * cos(a) + Vector3.UP * sin(a)
		var mid := hub + dir * r * 0.62
		_box("metal", Vector3(0.22, r * 0.72, 0.02), mid, steel, Basis(dir.cross(ax).normalized(), dir, ax) * Basis(Vector3.UP, 0.35))
	UpgradeKits._strut(self, top + Vector3(0, 0.45, 0), top + Vector3(0, 0.55, 0) - ax * 2.0, 0.06, steel)
	_box("metal", Vector3(0.02, 1.0, 1.6), top + Vector3(0, 0.8, 0) - ax * 2.6, steel, Basis(side, Vector3.UP, -ax.cross(side)).orthonormalized())
	_box("paint", Vector3(0.05, h, 0.05), Vector3(c.x, h * 0.5, c.y), steel.darkened(0.3))  # pump rod
	_box("concrete", Vector3(1.4, 0.3, 1.4), Vector3(c.x, 0.1, c.y), FOUNDATION)
