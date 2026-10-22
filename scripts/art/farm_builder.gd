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
## (0 house only, 1 barn, 2 grain bins, 3 silo).
static func build_farmstead(seed: int, look: int) -> Array:
	var b := FarmBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._farmstead(look)
	return [b._commit_house(), b._commit_flat(), b.trees]


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


func _cone(base: Vector3, r: float, h: float, col: Color, segs := 20) -> void:
	var apex := base + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var out := ((p0 + p1) * 0.5 - base).normalized() + Vector3(0, 0.6, 0)
		var slant := Vector2(r, h).length()
		_tri("metal", p0, p1, apex, col, [Vector2(r * a0, 0), Vector2(r * a1, 0), Vector2(r * (a0 + a1) * 0.5, slant)], out)
		_tri("paint", p0, p1, apex, col.darkened(0.5), [], -out)
