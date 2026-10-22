class_name TelecomBuilder
extends CivicBuilder
## The phone company, benchmarked against photos of real rural Midwestern
## telephone co-ops and cell sites:
##   - the central office: a one-storey buff brick exchange with few
##     windows, a small glass-front business office, rooftop units, a
##     standby generator and white fleet vans out front
##   - the 150-ft monopole: a tapered galvanised pole with a triangular
##     antenna platform (three sectors of panel antennas and radios), a
##     second carrier lower down and a lightning rod
##   - the 300-ft self-support lattice tower: three legs and X bracing,
##     sector frames at two heights, and the red obstruction lights the FAA
##     requires on anything over 200 ft
##   - the monopine: a monopole dressed in fake pine branches near homes
##   - every compound: a gravel pad behind 8-ft chain-link with barbed
##     wire, a precast equipment shelter, a generator, an ice bridge to the
##     pole and a gravel drive in from the road
##   - the blocks it buys: a line crew garage with bucket trucks, a cable
##     and reel yard, a phone store, a two-storey operations center and a
##     windowless data center with chillers and generators
## Local space: centred on 0, -z toward the road. `to_curb` is how far the
## curb lies in front of the office block; `drive` how long a tower's drive
## runs out from the front of its compound.

const S := Telecom.CELL * 0.5
const BUFF := ["#c9b48e", "#b8a07a", "#d4c4a0", "#a8775c"]
const SHELTER := Color("#c8c2b4")  # exposed-aggregate precast concrete
const STONE := Color("#8f8a80")    # #53 crushed limestone
const PANEL := Color("#e4e4e0")    # antenna radomes are off-white
const RADIO := Color("#9ea3a6")
const RED_LIGHT := Color("#e0221a")
const BARK := Color("#5a4636")
const NEEDLES := Color("#2c3f26")
const FLEET := Color("#eeeeec")


## [building mesh, ground mesh, trees] for the central office block.
static func build_office(seed: int, to_curb: float) -> Array:
	var b := _start(seed)
	b._office(to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees]


## The same for one block it bought, built up `levels` times.
static func build_block(art: String, levels: int, seed: int) -> Array:
	var b := _start(seed)
	match art:
		"yard": b._reel_yard()
		"store": b._store()
		"office": b._ops_center(levels)
		"data": b._data_center(levels)
		_: b._garage(levels)
	return [b._commit_house(), b._commit_flat(), b.trees]


## A tower with its compound: kind is "monopole", "lattice" or "monopine",
## with "_5g" when it carries 5G radios too.
static func build_tower(kind: String, seed: int, drive: float) -> Array:
	var b := _start(seed)
	var five := kind.ends_with("_5g")
	var k := kind.trim_suffix("_5g")
	b._compound(drive, k == "lattice")
	match k:
		"lattice": b._lattice_tower(Telecom.TOWERS.lattice.height, five)
		"monopine": b._monopine(Telecom.TOWERS.monopine.height)
		_: b._monopole(Telecom.TOWERS.monopole.height, five)
	return [b._commit_house(), b._commit_flat(), b.trees]


static func _start(seed: int) -> TelecomBuilder:
	var b := TelecomBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


# ---------------------------------------------------------------- the office

func _office(to_curb: float) -> void:
	var brick := Color(_pick(BUFF))
	var front := -S
	# The exchange: a deep one-storey equipment room with high slit windows,
	# and a lower business office stepping out in front of it.
	var zf := front + 12.0
	_slab(-11.5, 15.0, zf, 18.0)
	_flat_roofed_at("brick", -11.5, 15.0, 18.0, zf + 9.0, 5.2, 5.9, brick)
	_window_row(-11.5 - 7.5, zf + 9.0, 14.0, 4.3, 0.5, 4, LIMESTONE_TRIM, Vector3.LEFT)
	_rooftop_units(-11.5, 12.0, zf, 18.0, 5.2, 2)
	_box("brick", Vector3(9.0, 3.6, 5.0), Vector3(-13.0, 1.8, zf - 2.5), brick)
	_box("paint", Vector3(9.4, 0.3, 5.4), Vector3(-13.0, 3.75, zf - 2.5), Color("#cfcbc2"))
	_window_row(-15.5, zf - 5.0, 3.6, 1.6, 1.4, 2, LIMESTONE_TRIM)
	_entry(-10.0, zf - 5.0, LIMESTONE_TRIM)
	_sign(Vector3(-13.0, 3.2, zf - 5.06), 6.0, 0.6)
	# The cable vault: conduits come up out of the street into the building.
	_box("paint", Vector3(1.6, 0.12, 1.2), Vector3(-4.0, 0.06, front + 3.0), CONCRETE)
	# Standby generator on its pad, behind a short screen fence.
	_box("paint", Vector3(4.0, 0.3, 2.2), Vector3(-15.0, 0.15, zf + 21.0), CONCRETE)
	_box("metal", Vector3(3.6, 1.8, 1.6), Vector3(-15.0, 1.2, zf + 21.0), Color("#c5c8c4"))
	_box("paint", Vector3(0.12, 0.9, 0.12), Vector3(-13.5, 2.5, zf + 21.0), DARK)  # exhaust stack
	# Lot out front with the fleet: white splicing vans and a pickup.
	_parking(-19.5, -3.5, front + 1.0, zf - 5.6, to_curb, -6.0)
	for i in 3:
		var x := -18.0 + i * 2.75
		_van(Vector3(x, 0, zf - 8.6), i == 2)
	_bed(-13.0, zf - 6.2, 7.0)
	_tree_row(-17.0, -6.0, zf + 25.5, 7.0)


## A fleet van or pickup, nose toward the building (+z).
func _van(p: Vector3, pickup: bool) -> void:
	if pickup:
		_box("paint", Vector3(2.0, 1.1, 5.8), p + Vector3(0, 0.95, 0), FLEET)
		_box("paint", Vector3(1.9, 0.8, 2.2), p + Vector3(0, 1.9, 0.6), FLEET)
		_box("glass", Vector3(1.92, 0.5, 0.05), p + Vector3(0, 1.95, 1.72), Color(0.2, 0.24, 0.28, 0.0))
	else:
		_box("paint", Vector3(2.05, 2.3, 5.9), p + Vector3(0, 1.45, 0), FLEET)
		_box("glass", Vector3(1.9, 0.6, 0.05), p + Vector3(0, 2.0, 2.96), Color(0.2, 0.24, 0.28, 0.0))
		_box("paint", Vector3(1.6, 0.06, 2.6), p + Vector3(0, 2.64, -0.6), GALV)  # ladder rack
	for e in [-1.0, 1.0]:
		for f in [-1.8, 1.8]:
			_cyl_y(p + Vector3(e * 0.95, 0.38, f), 0.38, 0.25, DARK)


const LIMESTONE_TRIM := Color("#d8cfb8")


func _tree_row(x0: float, x1: float, z: float, step: float) -> void:
	var x := x0
	while x <= x1:
		var pick := TreeField.pick(rng, false)
		trees.append([Vector3(x + rng.randf_range(-1.0, 1.0), 0, z), pick[0], pick[1], rng.randf_range(0.85, 1.1)])
		x += step


# ---------------------------------------------------------------- towers

## The fenced gravel compound, its equipment shelter and the drive in.
func _compound(drive: float, big: bool) -> void:
	var h := Balance.TELECOM_COMPOUND * 0.5
	_flat_rect("gravel", -h, h, -h, h, 0.05, STONE)
	if drive > 0.5:
		_flat_rect("gravel", -2.0, 2.0, -h - drive - 1.0, -h, 0.08, STONE)
	_fence(Vector2(-h + 0.5, -h + 0.5), Vector2(h - 0.5, h - 0.5), 2.4, true)
	# Double swing gate on the front, shown as its frame.
	_box("paint", Vector3(4.2, 0.08, 0.08), Vector3(0, 2.3, -h + 0.5), GALV)
	# Precast shelter on its pad, with a door and a wall-mount AC unit.
	var c := Vector3(-h + 5.0, 0, h - 4.5)
	_box("paint", Vector3(4.2, 0.3, 6.6), c + Vector3(0, 0.15, 0), CONCRETE)
	_box("paint", Vector3(3.6, 3.0, 6.0), c + Vector3(0, 1.8, 0), SHELTER)
	_box("paint", Vector3(3.8, 0.15, 6.2), c + Vector3(0, 3.35, 0), Color("#b9b5ab"))
	_box("paint", Vector3(0.06, 2.1, 1.0), c + Vector3(1.83, 1.35, -1.6), Color("#7a7d7f"))
	_box("metal", Vector3(0.5, 0.9, 1.2), c + Vector3(1.9, 1.6, 1.4), Color("#c5c8c4"))
	# Standby generator and its fuel tank.
	var g := Vector3(-h + 4.5, 0, -h + 4.0)
	_box("paint", Vector3(3.4, 0.25, 1.8), g + Vector3(0, 0.12, 0), CONCRETE)
	_box("metal", Vector3(3.0, 1.6, 1.4), g + Vector3(0, 1.05, 0), Color("#d2d4cf"))
	# Utility meter rack by the gate and the telco demarc cabinet.
	_box("paint", Vector3(0.1, 1.8, 0.1), Vector3(3.5, 0.9, -h + 1.4), GALV)
	_box("metal", Vector3(0.9, 1.1, 0.5), Vector3(3.5, 1.5, -h + 1.6), Color("#a8aca9"))
	# Ice bridge: a cable tray on posts from the shelter to the tower base.
	var from := c + Vector3(1.8, 2.7, 0)
	var to := Vector3(-1.2, 2.7, 0.8 if not big else 1.4)
	_strut(from, to, 0.35, GALV)
	for t in [0.33, 0.66]:
		var q: Vector3 = from.lerp(to, t)
		_box("paint", Vector3(0.1, 2.7, 0.1), Vector3(q.x, 1.35, q.z), GALV)


## A 12-sided tapered galvanised pole on its foundation.
func _monopole(height: float, five: bool) -> void:
	_box("paint", Vector3(2.6, 0.5, 2.6), Vector3(0, 0.25, 0), CONCRETE)
	_lathe(Vector3.ZERO, [Vector2(0.85, 0.4), Vector2(0.62, height * 0.5), Vector2(0.38, height)], GALV, 12)
	# Top carrier: a triangular platform, three sectors of three panels.
	_sector_platform(height - 1.6, 2.4, 3, true)
	# A second carrier lower down on a smaller ring mount.
	_sector_platform(height - 8.0, 1.6, 2, false)
	if five:
		_mimo(height - 13.0, 1.2)
	_box("paint", Vector3(0.05, 3.0, 0.05), Vector3(0, height + 1.5, 0), GALV)  # lightning rod


## A three-legged self-support lattice tower with X bracing.
func _lattice_tower(height: float, five: bool) -> void:
	var base_r := 4.3
	var top_r := 0.9
	var legs := []
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		legs.append(Vector2(cos(a), sin(a)))
	for l in legs:
		_box("paint", Vector3(1.4, 0.6, 1.4), Vector3(l.x * base_r, 0.3, l.y * base_r), CONCRETE)
	var panels := 14
	var at := func(i: int, y: float) -> Vector3:
		var r := lerpf(base_r, top_r, y / height)
		return Vector3(legs[i].x * r, y, legs[i].y * r)
	for i in 3:
		_strut(at.call(i, 0.0), at.call(i, height), 0.22, GALV)
	for k in panels:
		var y0 := height * k / panels
		var y1 := height * (k + 1) / panels
		for i in 3:
			var j := (i + 1) % 3
			_strut(at.call(i, y0), at.call(j, y1), 0.08, GALV)
			_strut(at.call(j, y0), at.call(i, y1), 0.08, GALV)
			_strut(at.call(i, y1), at.call(j, y1), 0.08, GALV)
	# A climbing ladder and the waveguide run up one face.
	_strut(at.call(0, 0.0).lerp(at.call(1, 0.0), 0.5), at.call(0, height).lerp(at.call(1, height), 0.5), 0.12, DARK)
	_sector_platform(height - 2.0, 2.6, 3, true)
	_sector_platform(height * 0.62, 2.2 + base_r * 0.38 - 0.4, 3, false)
	if five:
		_mimo(height * 0.5, base_r * 0.5 + 0.8)
	# FAA obstruction lights (L-864 red): one at the top, one at mid height.
	_box("paint", Vector3(0.45, 0.6, 0.45), Vector3(0, height + 0.3, 0), RED_LIGHT)
	_box("paint", Vector3(0.05, 3.0, 0.05), Vector3(0, height + 2.1, 0), GALV)
	for i in 3:
		var p: Vector3 = at.call(i, height * 0.5)
		_box("paint", Vector3(0.3, 0.4, 0.3), p + Vector3(0, 0.3, 0), RED_LIGHT)


## A monopole in fake pine bark and branches, its antennas painted green
## inside the boughs.
func _monopine(height: float) -> void:
	_box("paint", Vector3(2.4, 0.5, 2.4), Vector3(0, 0.25, 0), CONCRETE)
	_lathe(Vector3.ZERO, [Vector2(0.75, 0.4), Vector2(0.5, height * 0.5), Vector2(0.3, height)], BARK, 12)
	# Tiers of boughs from about a third of the way up, widest low.
	var y := height * 0.32
	var tier := 0
	while y < height + 2.0:
		var t := (y - height * 0.32) / (height * 0.7)
		var r := lerpf(5.2, 1.2, t) * rng.randf_range(0.9, 1.1)
		_lathe(Vector3(0, y, 0), [Vector2(r, 0.0), Vector2(r * 0.55, 1.4), Vector2(0.4, 2.6)],
			NEEDLES.lightened(0.04 * (tier % 3)), 9)
		y += 2.3
		tier += 1
	_sector_platform(height - 4.0, 1.4, 3, false, NEEDLES.lightened(0.1))
	# Real pines around the compound help it blend in.
	for p in [Vector3(-9.0, 0, -9.0), Vector3(9.5, 0, 8.0), Vector3(-10.0, 0, 3.0)]:
		var pick := TreeField.pick(rng, false)
		trees.append([p + Vector3(0, 0, -6.0), pick[0], pick[1], rng.randf_range(0.9, 1.15)])


## Three sector frames at `y`, `r` out from the pole, with `n` panel
## antennas each and a remote radio behind every panel.
func _sector_platform(y: float, r: float, n: int, rails: bool, col := PANEL) -> void:
	for s in 3:
		var a := TAU * s / 3.0 - PI * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var mid := out * r
		# The face pipe and its arms back to the pole.
		_strut(Vector3(0, y - 0.6, 0), Vector3(mid.x, y - 0.6, mid.z), 0.1, GALV)
		_strut(mid + side * (n * 0.45) + Vector3(0, y - 0.6, 0), mid - side * (n * 0.45) + Vector3(0, y - 0.6, 0), 0.08, GALV)
		if rails:
			_strut(mid + side * (n * 0.45) + Vector3(0, y + 0.9, 0), mid - side * (n * 0.45) + Vector3(0, y + 0.9, 0), 0.06, GALV)
		var yaw := Basis(Vector3.UP, atan2(out.x, out.z))
		for k in n:
			var at := mid + side * ((k - (n - 1) * 0.5) * 0.85) + out * 0.25
			_box("paint", Vector3(0.32, 2.4, 0.14), at + Vector3(0, y, 0), col, yaw)
			_box("paint", Vector3(0.3, 0.55, 0.18), at - out * 0.35 + Vector3(0, y - 0.6, 0), RADIO, yaw)
	# The triangle joining the three faces.
	for s in 3:
		var a0 := TAU * s / 3.0 - PI * 0.5
		var a1 := TAU * (s + 1) / 3.0 - PI * 0.5
		_strut(Vector3(cos(a0) * r, y - 0.6, sin(a0) * r), Vector3(cos(a1) * r, y - 0.6, sin(a1) * r), 0.08, GALV)


## 5G massive-MIMO panels: wide, squat boxes on short arms.
func _mimo(y: float, r: float) -> void:
	for s in 3:
		var a := TAU * s / 3.0 - PI * 0.5 + PI / 3.0
		var out := Vector3(cos(a), 0, sin(a))
		var yaw := Basis(Vector3.UP, atan2(out.x, out.z))
		_strut(Vector3(0, y, 0), Vector3(out.x * r, y, out.z * r), 0.08, GALV)
		_box("paint", Vector3(0.5, 0.85, 0.16), out * (r + 0.15) + Vector3(0, y, 0), PANEL, yaw)


# ---------------------------------------------------------------- blocks

## A pre-engineered metal line crew garage with three overhead doors, and
## bucket trucks in the yard.
func _garage(levels: int) -> void:
	var wall := Color(_pick(METAL_WALL))
	var zf := -S + 9.0
	var h := 5.5 + 1.5 * (levels - 1)
	_slab(0.0, 30.0, zf, 15.0)
	_box("siding", Vector3(30.0, h, 15.0), Vector3(0, h * 0.5 + 0.3, zf + 7.5), wall)
	_metal_roof(0.0, zf + 7.5, h + 0.3, 30.0, 15.0, Color(_pick(["#7a7874", "#3e5a48", "#5a2a26", "#2f3b4a"])))
	for i in 3:
		_overhead_door(-9.0 + i * 9.0, zf, 3.7, 4.3, wall.lightened(0.15))
	_flat_rect("drive", -15.0, 15.0, -S + 1.0, zf, 0.05)
	for x in [-9.0, 9.0]:
		_bucket_truck(Vector3(x, 0, -S + 4.0))
	_flat_rect("gravel", -18.0, 18.0, zf + 15.5, S - 1.0, 0.04, STONE)


## A white bucket truck (an aerial lift on a medium-duty chassis), boom
## stowed, facing +z.
func _bucket_truck(p: Vector3) -> void:
	_box("paint", Vector3(2.4, 1.9, 2.3), p + Vector3(0, 1.4, 3.0), FLEET)  # cab
	_box("glass", Vector3(2.2, 0.7, 0.05), p + Vector3(0, 1.85, 4.16), Color(0.2, 0.24, 0.28, 0.0))
	_box("paint", Vector3(2.5, 1.2, 5.2), p + Vector3(0, 1.3, -0.9), FLEET)  # utility body
	_box("paint", Vector3(0.6, 0.6, 0.6), p + Vector3(0, 2.2, -2.8), Color("#d9d9d4"))  # turntable
	_strut(p + Vector3(0, 2.5, -2.8), p + Vector3(0, 3.0, 2.2), 0.35, Color("#e2e2dd"))  # boom over the cab
	_box("paint", Vector3(0.9, 1.0, 0.9), p + Vector3(0, 3.1, 2.6), Color("#e6d04a"))  # bucket
	for f in [-2.6, 0.2, 3.0]:
		for e in [-1.0, 1.0]:
			_cyl_y(p + Vector3(e * 1.1, 0.48, f), 0.48, 0.3, DARK)


## Fiber and copper reels stored flat on the gravel, a stack of new
## poles, and a reel trailer.
func _reel_yard() -> void:
	var h := S - 1.5
	_flat_rect("gravel", -h, h, -h, h, 0.05, STONE)
	_fence(Vector2(-h, -h), Vector2(h, h), 2.4)
	for i in 4:
		for j in 3:
			var c := Vector3(-12.0 + i * 5.0, 0, -8.0 + j * 5.0)
			var r := rng.randf_range(1.0, 1.3)
			_cylinder("paint", c, r, 0.08, Color("#9c7a50"), 12)                # bottom flange
			_cylinder("paint", c + Vector3(0, 0.08, 0), r * 0.85, 0.95, Color(_pick(["#3a3c3e", "#e1a032", "#2f4a8a"])), 12)
			_cylinder("paint", c + Vector3(0, 1.03, 0), r, 0.08, Color("#9c7a50"), 12)  # top flange
	for k in 6:
		_box("paint", Vector3(0.32, 0.32, 13.7), Vector3(10.0 + (k % 3) * 0.36, 0.2 + (k / 3) * 0.33, 0.0), POLE)
	_box("paint", Vector3(2.4, 0.2, 4.0), Vector3(12.0, 0.7, 12.0), Color("#3a3c3e"))
	_cylinder("paint", Vector3(12.0, 0.8, 12.0), 1.1, 0.9, Color("#e1a032"), 12)


## A small phone store with a glass front and a payment drop.
func _store() -> void:
	var brick := Color(_pick(FACADE_BRICK))
	var zf := -S + 16.0
	_slab(0.0, 16.0, zf, 12.0)
	_flat_roofed_at("brick", 0.0, 16.0, 12.0, zf + 6.0, 4.4, 5.0, brick)
	for i in 6:
		_glass(Vector3(-5.0 + i * 2.0, 1.7, zf - 0.04), Vector3(-1, 0, 0), 1.9, 2.6, 0.0)
	_box("paint", Vector3(16.4, 0.5, 0.2), Vector3(0, 3.4, zf - 0.1), Color(_pick(AWNING)))
	_sign(Vector3(0, 4.0, zf - 0.22), 9.0, 0.8)
	_parking(-18.0, 18.0, -S + 1.0, zf - 1.0, 0.0, 0.0)
	_box("metal", Vector3(0.6, 1.1, 0.5), Vector3(8.5, 0.85, zf - 1.6), Color("#2f4a8a"))  # drop box


## A two-storey brick operations center (taller when built up).
func _ops_center(levels: int) -> void:
	var brick := Color(_pick(BUFF))
	var floors := 1 + levels
	var zf := -S + 12.0
	var h := floors * 4.0 + 0.4
	_slab(0.0, 28.0, zf, 16.0)
	_flat_roofed_at("brick", 0.0, 28.0, 16.0, zf + 8.0, h, h + 0.7, brick)
	for f in floors:
		_window_row(0.0, zf, 25.0, f * 4.0 + 2.2, 1.5, 7, LIMESTONE_TRIM)
		_window_row(0.0, zf + 16.0, 25.0, f * 4.0 + 2.2, 1.5, 7, LIMESTONE_TRIM, Vector3.BACK)
	_entry(0.0, zf, LIMESTONE_TRIM)
	_rooftop_units(0.0, 22.0, zf, 16.0, h, 3)
	_box("paint", Vector3(0.1, 4.0, 0.1), Vector3(10.0, h + 2.0, zf + 10.0), GALV)  # roof antenna mast
	_cylinder("paint", Vector3(6.0, h, zf + 12.0), 0.9, 0.2, PANEL, 12)              # satellite dish base
	_parking(-18.0, 18.0, -S + 1.0, zf - 1.0, 0.0, -12.0)


## A windowless precast data hall with rooftop chillers, generators with
## belly tanks, and a security fence.
func _data_center(levels: int) -> void:
	var wall := Color(_pick(["#d6d3cb", "#c4c1b8", "#b8b6b0"]))
	var h := 7.5 + 4.0 * (levels - 1)
	var zf := -S + 6.0
	_slab(0.0, 30.0, zf, 24.0)
	_flat_roofed_at("paint", 0.0, 30.0, 24.0, zf + 12.0, h, h + 0.8, wall)
	for i in 5:
		_box("paint", Vector3(0.25, h, 0.06), Vector3(-12.0 + i * 6.0, h * 0.5, zf - 0.04), wall.darkened(0.08))
	_box("paint", Vector3(1.1, 2.3, 0.06), Vector3(10.0, 1.45, zf - 0.05), Color("#5a5e60"))
	for i in 4:
		var p := Vector3(-10.5 + i * 7.0, h, zf + 17.0)
		_box("metal", Vector3(5.0, 1.8, 2.4), p + Vector3(0, 0.9, 0), Color("#c5c8c4"))
		for k in 3:
			_cylinder("paint", p + Vector3(-1.6 + k * 1.6, 1.8, 0), 0.65, 0.12, DARK, 10)  # fans
	for x in [-12.0, -4.0, 4.0, 12.0]:
		_box("paint", Vector3(6.0, 0.4, 2.6), Vector3(x, 0.2, zf + 26.5), CONCRETE)
		_box("metal", Vector3(5.6, 2.4, 2.2), Vector3(x, 1.6, zf + 26.5), Color("#d2d4cf"))
	_fence(Vector2(-S + 1.0, -S + 1.0), Vector2(S - 1.0, S - 1.0), 2.4, true)
