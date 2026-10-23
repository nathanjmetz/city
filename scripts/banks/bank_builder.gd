class_name BankBuilder
extends CivicBuilder
## Bank buildings, benchmarked against photos of real small-town Indiana banks:
##   - the community bank on the square: a two-storey brick building with an
##     Indiana limestone front of four columns under a cornice, bronze doors
##     and the bank's name cut in the frieze (the 1900s to 1920s "temple
##     bank"), a clock over the corner and a night deposit box
##   - the Farm Credit office: a low brick office with a standing-seam metal
##     roof, a glass entry and a big lot for pickups, a flag out front
##   - later blocks: drive-up teller lanes under a canopy with a pneumatic
##     tube island per lane, an ATM kiosk, a parking lot, brick office
##     wings, a community room, a flat-roofed operations center, a four-storey
##     holding company headquarters, and an equipment leasing yard
## Local space: one Banks.CELL block centred on 0, -z toward the street.
## `to_curb` is how far the curb lies in front of the first building.

const S := Banks.CELL * 0.5
const LIMESTONE := Color("#d8cfb8")
const BRONZE := Color("#5a4630")
const METAL_ROOF := [Color("#5d6a62"), Color("#7a3b32"), Color("#46505a")]


static func build_main(kind: String, seed: int, to_curb: float) -> Array:
	var b := _start(seed)
	if kind == "farm_credit":
		b._farm_credit(to_curb)
	else:
		b._temple_bank(to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees]


static func build_block(art: String, seed: int) -> Array:
	var b := _start(seed)
	match art:
		"drive_up": b._drive_up()
		"atm": b._atm()
		"parking": b._parking(-S + 1.0, S - 1.0, -S + 2.0, S - 2.0, 0.0, 0.0)
		"hall": b._community_room()
		"operations": b._operations()
		"headquarters": b._headquarters()
		"yard": b._leasing_yard()
		_: b._office_wing()
	return [b._commit_house(), b._commit_flat(), b.trees]


static func _start(seed: int) -> BankBuilder:
	var b := BankBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


## Flat ground pieces in tiles of at most 6 m, so the terrain drape (which
## moves only vertices) bends them over the real ground instead of letting
## a rise poke through a big paved square.
func _flat_rect(kind: String, x0: float, x1: float, z0: float, z1: float, y: float, col := MULCH) -> void:
	var nx := maxi(1, ceili((x1 - x0) / 6.0))
	var nz := maxi(1, ceili((z1 - z0) / 6.0))
	for i in nx:
		for j in nz:
			super._flat_rect(kind, lerpf(x0, x1, float(i) / nx), lerpf(x0, x1, float(i + 1) / nx),
				lerpf(z0, z1, float(j) / nz), lerpf(z0, z1, float(j + 1) / nz), y, col)


func _brick() -> Color:
	return Color(_pick(["#8a4a38", "#9b5a42", "#7a4234", "#a8775c"]))


## The temple bank: brick box, limestone front with columns and a frieze.
func _temple_bank(to_curb: float) -> void:
	var brick := _brick()
	var w := 18.0
	var d := 20.0
	var zf := -S + 7.0
	var h := 9.0
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, zf + d * 0.5, h, h + 0.9, brick)
	# The limestone front: a full-height face, four columns, frieze, cornice.
	_box("paint", Vector3(w + 0.4, h + 1.2, 0.6), Vector3(0, (h + 1.2) * 0.5, zf - 0.3), LIMESTONE)
	_box("paint", Vector3(w + 1.0, 0.5, 1.4), Vector3(0, h + 1.35, zf - 0.5), LIMESTONE.lightened(0.05))
	_box("paint", Vector3(w - 1.0, 1.0, 0.1), Vector3(0, h - 0.2, zf - 0.65), LIMESTONE.darkened(0.08))
	for i in 4:
		var x := -6.0 + i * 4.0
		_cyl_y(Vector3(x, h * 0.5 - 0.6, zf - 2.0), 0.45, h - 1.6, LIMESTONE)
		_box("paint", Vector3(1.2, 0.4, 1.2), Vector3(x, 0.5, zf - 2.0), LIMESTONE.darkened(0.05))
		_box("paint", Vector3(1.2, 0.4, 1.2), Vector3(x, h - 1.2, zf - 2.0), LIMESTONE.darkened(0.05))
	# Portico roof over the columns, steps up to the bronze doors.
	_box("paint", Vector3(w - 2.0, 0.8, 3.0), Vector3(0, h - 0.6, zf - 1.5), LIMESTONE)
	for st in 3:
		_box("paint", Vector3(14.0 - st * 0.6, 0.18, 4.0 - st * 0.5), Vector3(0, 0.09 + st * 0.18, zf - 2.0 + st * 0.25),
			CONCRETE)
	_box("paint", Vector3(2.4, 3.6, 0.15), Vector3(0, 2.3, zf - 0.68), BRONZE)
	_glass(Vector3(0, 5.6, zf - 0.68), Vector3(-1, 0, 0), 2.2, 2.0, 0.0)
	for s in [-1.0, 1.0]:
		_glass(Vector3(s * 4.0, 3.2, zf - 0.68), Vector3(-1, 0, 0), 2.0, 4.4, 0.0)
	_sign(Vector3(0, h - 0.2, zf - 0.72), 10.0, 0.7)
	# A clock on a bracket at the corner, and a night deposit box.
	_box("paint", Vector3(0.2, 0.2, 1.4), Vector3(w * 0.5 + 0.1, 6.0, zf - 0.6), BRONZE)
	_box("paint", Vector3(1.2, 1.2, 0.3), Vector3(w * 0.5 + 0.1, 6.0, zf - 1.3), Color("#efede6"))
	_box("metal", Vector3(0.6, 0.6, 0.3), Vector3(-w * 0.5 + 1.5, 1.2, zf - 0.75), Color("#7c7f80"))
	for s in [-1.0, 1.0]:
		for f in 2:
			_window_row(s * w * 0.5, zf + d * 0.5, d - 4.0, f * 4.0 + 2.4, 2.2, 4, LIMESTONE, Vector3(s, 0, 0))
	_window_row(0.0, zf + d, w - 3.0, 6.4, 1.8, 4, LIMESTONE, Vector3.BACK)
	_rooftop_units(0.0, w * 0.6, zf, d, h, 1)
	# A walk out to the street and beds either side of the steps.
	_flat_rect("drive", -2.0, 2.0, -S - to_curb, zf - 4.0, 0.08)
	_bed(-6.0, zf - 5.0, 4.0)
	_bed(6.0, zf - 5.0, 4.0)
	_flagpole(Vector3(-w * 0.5 + 0.5, 0, zf - 5.5))


## Farm Credit: a low brick office with a metal gable roof and its lot.
func _farm_credit(to_curb: float) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38"]))
	var w := 22.0
	var d := 13.0
	var zf := -S + 15.0
	_slab(0.0, w, zf, d)
	_box("brick", Vector3(w, 3.8, d), Vector3(0, 1.9, zf + d * 0.5), brick)
	_gable_roof(0.0, zf + d * 0.5, 3.8, d + 0.6, 2.6, w + 0.8, true, _pick(METAL_ROOF), brick)
	_vestibule(-4.0, zf, 4.0, 2.5, 3.2)
	_sign(Vector3(5.0, 3.0, zf - 0.06), 7.0, 0.6)
	_window_row(5.0, zf, 9.0, 1.7, 1.5, 3, LIMESTONE)
	_window_row(-9.0, zf, 3.0, 1.7, 1.5, 1, LIMESTONE)
	for s in [-1.0, 1.0]:
		_window_row(s * w * 0.5, zf + d * 0.5, d - 3.0, 1.7, 1.4, 3, LIMESTONE, Vector3(s, 0, 0))
	_parking(-S + 1.0, S - 1.0, -S + 0.5, zf - 3.0, to_curb, 12.0)
	_flagpole(Vector3(-14.0, 0, zf - 1.5))
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(14.0, 0, zf + d + 3.0), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


## Drive-up lanes: a canopy on columns over three lanes, each with a
## pneumatic tube island, and the teller window on a small brick booth.
func _drive_up() -> void:
	var brick := _brick()
	_flat_rect("asphalt", -S + 1.0, S - 1.0, -S + 1.0, S - 1.0, 0.06)
	var lanes := 3
	var x0 := -9.0
	_box("brick", Vector3(4.0, 3.6, 10.0), Vector3(x0 - 4.0, 1.8, 0.0), brick)
	_glass(Vector3(x0 - 1.98, 1.8, 0.0), Vector3(0, 0, 1), 2.4, 1.2, 0.0)
	_box("paint", Vector3(lanes * 4.2 + 4.0, 0.6, 9.0), Vector3(x0 - 2.0 + (lanes * 4.2 + 4.0) * 0.5 - 2.0, 4.6, 0.0), LIMESTONE)
	_box("paint", Vector3(lanes * 4.2 + 3.8, 0.04, 8.8), Vector3(x0 - 2.0 + (lanes * 4.2 + 4.0) * 0.5 - 2.0, 4.29, 0.0), SOFFIT)
	for i in lanes:
		var x := x0 + 2.1 + i * 4.2
		_flat_rect("line", x + 1.9, x + 2.0, -S + 2.0, S - 2.0, 0.07, LINE)
		if i > 0:
			_box("paint", Vector3(0.9, 0.2, 3.6), Vector3(x - 2.0, 0.1, 0.0), CONCRETE)
			_box("metal", Vector3(0.5, 1.5, 0.5), Vector3(x - 2.0, 0.95, 0.0), Color("#c9c4b4"))
			_cyl_y(Vector3(x - 2.0, 3.0, 0.0), 0.08, 2.6, Color("#9a9a96"))
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.5, 4.3, 0.5), Vector3(x + 2.0, 2.15, s * 4.0), LIMESTONE)
	_bed(10.0, 14.0, 6.0)


func _atm() -> void:
	_flat_rect("asphalt", -S + 1.0, S - 1.0, -S + 1.0, S - 1.0, 0.06)
	_box("paint", Vector3(3.0, 0.2, 3.0), Vector3(0, 0.1, 0), CONCRETE)
	_box("metal", Vector3(1.6, 2.4, 1.2), Vector3(0, 1.3, 0), Color("#3e4a52"))
	_glass(Vector3(0, 1.6, -0.62), Vector3(-1, 0, 0), 0.6, 0.4, 0.0)
	_box("paint", Vector3(2.6, 0.3, 2.2), Vector3(0, 2.9, 0), LIMESTONE)
	_parking(-S + 1.0, S - 1.0, -S + 2.0, -4.0, 0.0, 0.0)
	_bed(8.0, 10.0, 6.0)
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(-10.0, 0, 10.0), pick[0], pick[1], rng.randf_range(0.7, 0.9)])


## A one- or two-storey brick office wing (lending, trust, mortgages).
func _office_wing() -> void:
	var brick := _brick()
	var floors := 1 + int(rng.randf() < 0.5)
	var w := 24.0
	var d := 16.0
	var zf := -d * 0.5
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, 0.0, floors * 4.0 + 0.4, floors * 4.0 + 1.0, brick)
	for f in floors:
		_window_row(0.0, zf, w - 3.0, f * 4.0 + 2.2, 1.6, 6, LIMESTONE)
		_window_row(0.0, zf + d, w - 3.0, f * 4.0 + 2.2, 1.6, 6, LIMESTONE, Vector3.BACK)
		_box("paint", Vector3(w + 0.1, 0.25, 0.12), Vector3(0, f * 4.0 + 0.3, zf - 0.06), LIMESTONE)
	_entry(-w * 0.25, zf, LIMESTONE)
	_flat_rect("drive", -S + 1.0, S - 1.0, -S + 1.0, zf - 2.0, 0.07)
	_rooftop_units(0.0, w * 0.7, zf, d, floors * 4.0 + 0.4, 1)


## The community room: a single-storey hall with a gable roof and a porch.
func _community_room() -> void:
	var brick := _brick()
	var w := 20.0
	var d := 14.0
	var zf := -d * 0.5
	_slab(0.0, w, zf, d)
	_box("brick", Vector3(w, 4.2, d), Vector3(0, 2.1, 0.0), brick)
	_gable_roof(0.0, 0.0, 4.2, d + 0.6, 3.0, w + 0.8, true, Color("#4b4d50"), brick)
	_window_row(0.0, zf, w - 4.0, 2.0, 2.0, 5, LIMESTONE)
	_entry(0.0, zf, LIMESTONE)
	_bed(-6.0, zf - 2.5, 5.0)
	_bed(6.0, zf - 2.5, 5.0)
	for i in 2:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3((i * 2 - 1) * 13.0, 0, 12.0), pick[0], pick[1], rng.randf_range(0.7, 0.95)])


## The operations center: a plain two-storey flat-roofed block with few windows.
func _operations() -> void:
	var w := 30.0
	var d := 22.0
	var zf := -d * 0.5
	var wall := Color(_pick(["#b8b2a4", "#c9c1ae", "#a8a39a"]))
	_slab(0.0, w, zf, d)
	_flat_roofed_at("paint", 0.0, w, d, 0.0, 8.4, 9.2, wall)
	_window_row(0.0, zf, w - 6.0, 6.2, 1.2, 8, wall.darkened(0.2))
	_entry(w * 0.3, zf, wall.darkened(0.2))
	_rooftop_units(0.0, w * 0.8, zf, d, 8.4, 3)
	_box("metal", Vector3(2.6, 2.2, 5.0), Vector3(-w * 0.5 - 2.0, 1.1, 4.0), Color("#8e9294"))  # standby generator
	_flat_rect("drive", -S + 1.0, S - 1.0, -S + 1.0, zf - 1.0, 0.07)


## The holding company headquarters: four storeys of brick and limestone.
func _headquarters() -> void:
	var brick := _brick()
	var w := 28.0
	var d := 20.0
	var zf := -d * 0.5
	var floors := 4
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, 0.0, floors * 4.0 + 0.4, floors * 4.0 + 1.2, brick)
	_box("paint", Vector3(w + 0.3, 1.0, d + 0.3), Vector3(0, 0.8, 0.0), LIMESTONE)
	_box("paint", Vector3(w + 0.5, 0.6, d + 0.5), Vector3(0, floors * 4.0 + 1.0, 0.0), LIMESTONE)
	for f in floors:
		_window_row(0.0, zf, w - 4.0, f * 4.0 + 2.4, 2.0, 9, LIMESTONE)
		_window_row(0.0, zf + d, w - 4.0, f * 4.0 + 2.4, 2.0, 9, LIMESTONE, Vector3.BACK)
		for s in [-1.0, 1.0]:
			_window_row(s * w * 0.5, 0.0, d - 4.0, f * 4.0 + 2.4, 2.0, 6, LIMESTONE, Vector3(s, 0, 0))
	_vestibule(0.0, zf, 6.0, 3.0, 4.0)
	_sign(Vector3(0.0, floors * 4.0 - 0.6, zf - 0.08), 12.0, 0.9)
	_rooftop_units(0.0, w * 0.7, zf, d, floors * 4.0 + 0.4, 2)
	_flagpole(Vector3(-w * 0.5 + 1.0, 0, zf - 4.0))


## Farm Credit's equipment leasing yard: gravel with tractors and a planter.
func _leasing_yard() -> void:
	_flat_rect("gravel", -S + 1.0, S - 1.0, -S + 1.0, S - 1.0, 0.06, DIRT)
	var green := Color("#2f6b34")
	var red := Color("#a3352b")
	for i in 3:
		var col: Color = green if rng.randf() < 0.6 else red
		var x := -10.0 + i * 10.0
		_box("metal", Vector3(2.6, 1.6, 4.2), Vector3(x, 1.5, -6.0), col)
		_box("metal", Vector3(1.6, 1.4, 1.6), Vector3(x, 3.0, -5.0), Color("#2a2c2e"))
		for s in [-1.0, 1.0]:
			_cyl_y(Vector3(x + s * 1.5, 0.9, -4.6), 0.9, 0.6, Color("#1e1f20"))
	_box("metal", Vector3(12.0, 1.0, 2.0), Vector3(0, 0.9, 8.0), Color("#c9a227"))  # a planter bar
	_fence(Vector2(-S + 1.0, -S + 1.0), Vector2(S - 1.0, -S + 1.0), 1.8)
