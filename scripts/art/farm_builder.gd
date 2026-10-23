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
func _barn(cx: float, cz: float, w: float, d: float) -> void:
	var red := Color(_pick(BARN_RED))
	var eave := 5.0
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
		_quad("metal", pa0, pa1, pb1, pb0, GALV, [Vector2(z0, 0), Vector2(z1, 0), Vector2(z1, slope), Vector2(z0, slope)], Vector3.UP)
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


## A corrugated steel grain bin with a cone roof.
func _grain_bin(base: Vector3, r: float, h: float) -> void:
	_box("concrete", Vector3(r * 2.1, 0.3, r * 2.1), base + Vector3(0, 0.15, 0), FOUNDATION)
	_cylinder("metal", base + Vector3(0, 0.3, 0), r, h, BIN, 20)
	_cone(base + Vector3(0, 0.3 + h, 0), r + 0.15, r * 0.7, BIN.darkened(0.04))
	# Hoops every so often, and a ladder up the side.
	_box("paint", Vector3(0.45, h, 0.08), base + Vector3(0, 0.3 + h * 0.5, -r - 0.05), Color("#7d8082"))


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
