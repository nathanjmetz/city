extends RefCounted
## The small stored facts of a building, for the new drawing style
## (docs/scale-test-2026-10-25.md, "The new drawing style, measured"): its
## outline, height, roof, age and wall material, and the rules that place
## its doors and windows. Every distance's drawing grows from these, so the
## far shapes, the lighter middle version and the close-up brick all agree.
##
## Everything is laid out on the mason's module, as real buildings are:
## brick dimensioning puts walls and openings on a 16 in grid (two modular
## bricks across, six courses up; a concrete block is one cell wide and two
## courses of 8 in). A wall is a grid of these cells.
##
## Measuring prototype: the shapes come from the lot and the building's type
## and seed, not from the art builders the game draws with today.

## Modular brick (ASTM C216 / BIA): 7 5/8 x 2 1/4 x 3 5/8 in, laid so three
## courses rise 8 in.
const BRICK_L := 0.193675
const BRICK_H := 0.05715
const BRICK_D := 0.092075
const HEAD_J := 0.009525          # 3/8 in head joint
const COURSE := 0.0677333         # 8 in / 3
const CELL := 0.4064              # 16 in: two bricks across, six courses up
## Lap siding, 4 in to the weather; asphalt shingles, 5 in.
const LAP := 0.1016
const SHINGLE := 0.127

enum Mat { SIDING, BRICK, BRICK_SHOP, BLOCK_SHOP, METAL, CURTAIN, BLOCK_PLANT }
enum Roof { FLAT, GABLE, HIP }
enum Top { SHINGLE_TOP, MEMBRANE, METAL_TOP }

## Vinyl siding colours seen on Indiana streets, and brick ranges (the
## colour a building's whole brick order leans to: red, brown, buff).
const SIDING := [Color("#e9e6dc"), Color("#d9d2bf"), Color("#b9b8ae"), Color("#9ea79a"), Color("#8f9ba3"),
	Color("#c9b99a"), Color("#f2efe6"), Color("#a59a86")]
const BRICK_TINT := [Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0), Color(0.82, 0.86, 0.9), Color(1.25, 1.18, 1.05),
	Color(0.92, 0.8, 0.72)]
const BRICK_FAR := Color("#8a4434")
const SHINGLES := [Color("#4d4a47"), Color("#5b544c"), Color("#3f4144"), Color("#6a5f55"), Color("#57524f")]
const MEMBRANES := [Color("#c4c2bb"), Color("#d2d0ca"), Color("#a9a7a1")]
const METALS := [Color("#c9c3b2"), Color("#9ea3a6"), Color("#e0e0da"), Color("#7f8f9c"), Color("#b0a58c")]
const BLOCK := [Color("#b8b4aa"), Color("#cdc5b2"), Color("#a7a49c")]
const DOORS := [Color("#7a1f1d"), Color("#1f2a3a"), Color("#1d1d1d"), Color("#2f4a33"), Color("#e9e6dc"), Color("#5a3b26")]


## The facts of the building on lot `key`, or {} when it can't be drawn.
## `centre` is the footprint's middle on the ground (the building's frame:
## x across the lot, z back from the street), `yaw` its turn.
static func of(sim, key: String) -> Dictionary:
	if not sim.buildings.has(key) or not sim.lots.has(key):
		return {}
	var b: Dictionary = sim.buildings[key]
	var lot: Dictionary = sim.lots[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.seed) ^ 0x5eed
	var type := BuildingTypes.type_of(b)
	var lw: float = lot.get("width", 20.0)
	var ld: float = lot.get("depth", 32.0)
	var storeys := BuildingTypes.storeys(b)
	var f := {"key": key, "type": type, "seed": int(b.seed), "look": look(b)}
	# Width and depth in cells, setback in metres, storey heights in cells.
	var wc := 0
	var dc := 0
	var setback := 0.0
	var rows: Array = []
	var parapet := 0
	match type:
		"house":
			if storeys <= 0:
				storeys = 1 if rng.randf() < 0.55 else 2
			wc = cells(clampf(minf(lw - 6.0, rng.randf_range(9.0, 13.5)), 7.0, 14.0))
			dc = cells(rng.randf_range(7.5, 10.0))
			setback = rng.randf_range(7.0, 9.5)
			rows = _repeat(7, storeys)
			f.mat = Mat.BRICK if rng.randf() < 0.38 else Mat.SIDING
			f.roof = Roof.HIP if rng.randf() < 0.3 else Roof.GABLE
			f.pitch = [0.5, 0.5, 0.583, 0.667][rng.randi() % 4]
		"row_home":
			wc = cells(maxf(lw - 1.0, 6.0))
			dc = cells(11.0)
			setback = rng.randf_range(3.0, 5.0)
			rows = _repeat(7, maxi(storeys, 2))
			f.mat = Mat.BRICK if rng.randf() < 0.6 else Mat.SIDING
			f.roof = Roof.GABLE
			f.pitch = 0.5
		"apartments":
			wc = cells(lw * 0.78)
			dc = cells(minf(ld * 0.5, 22.0))
			setback = 6.0
			rows = _repeat(7, maxi(storeys, 2))
			f.mat = Mat.BRICK if rng.randf() < 0.7 else Mat.SIDING
			f.roof = Roof.HIP if storeys <= 3 else Roof.FLAT
			f.pitch = 0.417
			if f.roof == Roof.FLAT:
				parapet = 2
		"mixed_use":
			wc = cells(lw - 0.8)
			dc = cells(ld * 0.6)
			setback = 0.3
			rows = [10] + _repeat(8, maxi(storeys, 2) - 1)
			f.mat = Mat.BRICK_SHOP
			f.roof = Roof.FLAT
			parapet = 2
		"office":
			wc = cells(lw * 0.8)
			dc = cells(ld * 0.6)
			setback = 4.0
			rows = [10] + _repeat(9, maxi(storeys, 1) - 1)
			f.mat = Mat.CURTAIN if storeys >= 6 else Mat.BRICK_SHOP
			f.roof = Roof.FLAT
			parapet = 2
		"shop", "shopping_center":
			wc = cells(clampf(lw * 0.85, 8.0, 60.0))
			dc = cells(clampf(ld * 0.55, 8.0, 30.0))
			setback = rng.randf_range(1.5, 4.0) if type == "shop" else 18.0
			rows = [10]
			f.mat = Mat.BRICK_SHOP if rng.randf() < 0.6 else Mat.BLOCK_SHOP
			f.roof = Roof.FLAT
			parapet = 2
		_:
			wc = cells(clampf(lw * 0.7, 12.0, 70.0))
			dc = cells(clampf(ld * 0.55, 12.0, 50.0))
			setback = 8.0
			rows = [20]
			if rng.randf() < 0.65:
				f.mat = Mat.METAL
				f.roof = Roof.GABLE
				f.pitch = 0.083  # a pre-engineered metal building's 1:12
			else:
				f.mat = Mat.BLOCK_PLANT
				f.roof = Roof.FLAT
				parapet = 1
	if not f.has("pitch"):
		f.pitch = 0.0
	f.w = wc * CELL
	# Masonry side walls run between the front and back walls' backs.
	f.d = dc * CELL + 2.0 * BRICK_D
	f.rows = rows
	f.parapet = parapet
	var eave_rows := 0
	for r in rows:
		eave_rows += r
	f.eave_rows = eave_rows
	f.h = (eave_rows + parapet) * CELL
	f.storeys = rows.size()
	# The ridge runs along the longer side.
	f.ridge_x = f.w >= f.d
	f.top = Top.MEMBRANE if f.roof == Roof.FLAT else (Top.METAL_TOP if f.mat == Mat.METAL else Top.SHINGLE_TOP)
	# Age: the sim's build date, plus a stand-in era from the seed (PerfTown
	# builds everything at tick 0).
	var built := int(b.get("built", 0))
	f.age = maxf(0.0, (sim.tick_count - built) / (CitySim.TICKS_PER_HOUR * 24.0 * 365.0)) + rng.randf_range(0.0, 70.0)
	match int(f.mat):
		Mat.SIDING:
			f.wall = SIDING[rng.randi() % SIDING.size()]
		Mat.BRICK, Mat.BRICK_SHOP:
			f.tint = BRICK_TINT[rng.randi() % BRICK_TINT.size()]
			f.wall = Color(BRICK_FAR.r * f.tint.r, BRICK_FAR.g * f.tint.g, BRICK_FAR.b * f.tint.b)
		Mat.METAL:
			f.wall = METALS[rng.randi() % METALS.size()]
		Mat.CURTAIN:
			f.wall = Color("#4c5a66")
		_:
			f.wall = BLOCK[rng.randi() % BLOCK.size()]
	if not f.has("tint"):
		f.tint = Color.WHITE
	match int(f.top):
		Top.SHINGLE_TOP: f.roof_col = SHINGLES[rng.randi() % SHINGLES.size()]
		Top.METAL_TOP: f.roof_col = METALS[rng.randi() % METALS.size()].darkened(0.1)
		_: f.roof_col = MEMBRANES[rng.randi() % MEMBRANES.size()]
	f.door = DOORS[rng.randi() % DOORS.size()]
	# Placed on the land as BuildingView places a building: the lot's front
	# on the street, turned to face it, the lot graded level with the road.
	var normal: Vector3 = lot.normal
	var front: Vector3 = lot.front
	var mid: Vector3 = front + normal * (setback + f.d * 0.5)
	f.basis = Basis.looking_at(-normal, Vector3.UP)
	f.yaw = f.basis.get_euler().y
	var base := Terrain.base_y(lot.pos.x, lot.pos.z)
	# On a slope, the floor stands on the highest ground under the walls.
	var hi := base
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var p: Vector3 = mid + f.basis * Vector3(c.x * f.w, 0.0, c.y * f.d)
		hi = maxf(hi, Terrain.ground_y(p.x, p.z))
	# The first floor stands a little above the yard on its foundation.
	f.centre = Vector3(mid.x, hi + 0.25, mid.z)
	f.front_z = -f.d * 0.5
	# The drive and walk (or a parking lot), on the lot in front.
	f.setback = setback
	f.to_curb = float(lot.get("to_curb", 4.0))
	f.lot_w = lw
	f.lot_d = ld
	f.drive_x = (1.0 if rng.randf() < 0.5 else -1.0) * (f.w * 0.5 + 1.8)
	return f


## What the drawing depends on, to know when a building changed.
static func look(b: Dictionary) -> Array:
	return [BuildingTypes.type_of(b), int(b.get("level", 0)), int(b.get("units", 1)), int(b.seed)]


static func cells(m: float) -> int:
	return maxi(4, int(round(m / CELL)))


static func _repeat(v: int, n: int) -> Array:
	var out := []
	for i in maxi(n, 1):
		out.append(v)
	return out


## The four walls, counter-clockwise seen from above, each seen from outside
## left to right: {p0, p1 (local x, z), len, u0 (where its cell grid starts),
## cols, gable (a gable end under a pitched roof), ops (openings: [col, row,
## cols, rows, kind])}. Front first.
static func walls(f: Dictionary) -> Array:
	var hw: float = f.w * 0.5
	var hd: float = f.d * 0.5
	var ends := [[Vector2(hw, -hd), Vector2(-hw, -hd)], [Vector2(-hw, -hd), Vector2(-hw, hd)],
		[Vector2(-hw, hd), Vector2(hw, hd)], [Vector2(hw, hd), Vector2(hw, -hd)]]
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.seed) ^ 0x0be7
	for i in 4:
		var p0: Vector2 = ends[i][0]
		var p1: Vector2 = ends[i][1]
		var length := p0.distance_to(p1)
		var side := i % 2 == 1
		# Side walls stand between the front and back walls.
		var u0 := BRICK_D if side else 0.0
		var cols := int(round((length - 2.0 * u0) / CELL))
		var gable: bool = f.roof == Roof.GABLE and (side == bool(f.ridge_x))
		out.append({"i": i, "p0": p0, "p1": p1, "len": length, "u0": u0, "cols": cols, "gable": gable,
			"ops": _openings(f, i, cols, rng)})
	return out


## Openings on one wall, in cells: [col, row, cols, rows, kind]. Kinds:
## "win" (a double-hung or commercial window), "door", "store" (a
## storefront), "bay" (an overhead door), "curtain" (a glass curtain wall).
static func _openings(f: Dictionary, wall: int, cols: int, rng: RandomNumberGenerator) -> Array:
	var ops := []
	var type: String = f.type
	var rows: Array = f.rows
	var front := wall == 0
	var back := wall == 2
	if int(f.mat) == Mat.CURTAIN:
		# Glass between the floors, all round, above a storefront base.
		var r0: int = rows[0]
		ops.append([1, 1, cols - 2, r0 - 3, "store" if front else "win"])
		for s in range(1, rows.size()):
			var base := _row_of(rows, s)
			ops.append([0, base + 1, cols, rows[s] - 2, "curtain"])
		return ops
	if type in ["factory"] or int(f.mat) in [Mat.METAL, Mat.BLOCK_PLANT]:
		if front:
			var bw := mini(8, cols - 4)
			ops.append([2, 0, bw, 10, "bay"])
			ops.append([cols - 4, 0, 2, 5, "door"])
		# A band of clerestory windows high up, all round.
		var n := maxi(1, cols / 8)
		for k in n:
			var c := int(round((k + 0.5) * cols / float(n))) - 1
			if front and c < 12:
				continue
			ops.append([c, 14, 3, 2, "win"])
		return ops
	var ground_shop := type in ["shop", "shopping_center", "mixed_use", "office"]
	for s in rows.size():
		var base := _row_of(rows, s)
		var tall: int = rows[s]
		if s == 0 and ground_shop:
			if front:
				ops.append([1, 1, cols - 2, tall - 3, "store"])
			elif back:
				ops.append([cols / 2 - 1, 0, 2, 5, "door"])
			continue
		# Windows: two cells wide, sill two cells up (32 in), head at 80 in.
		var wr := 3 if tall <= 7 else 4
		var spacing := 6 if type == "house" else 5
		if wall % 2 == 1:
			spacing = 8 if type == "house" else 6
		var n := maxi(1, int(cols / spacing))
		var door_c := -100
		if s == 0 and (front or back):
			door_c = int(cols * (0.5 if front else 0.7)) - 1
			if type == "house" and front:
				door_c = int(cols * rng.randf_range(0.35, 0.6)) - 1
			ops.append([door_c, 0, 2, 5, "door"])
		for k in n:
			var c := int(round((k + 0.5) * cols / float(n))) - 1
			c = clampi(c, 1, cols - 3)
			if absi(c - door_c) < 4:
				continue
			ops.append([c, base + 2, 2, wr, "win"])
	return ops


static func _row_of(rows: Array, storey: int) -> int:
	var r := 0
	for i in storey:
		r += rows[i]
	return r


## The wall's frame in the building's frame: x along the wall (left to right
## seen from outside), y up, z out of the wall.
static func wall_frame(w: Dictionary) -> Transform3D:
	var p0: Vector2 = w.p0
	var p1: Vector2 = w.p1
	var dir := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y).normalized()
	var out := dir.cross(Vector3.UP)
	return Transform3D(Basis(dir, Vector3.UP, out), Vector3(p0.x, 0.0, p0.y))


## The gable's rise over a gable-end wall.
static func gable_h(f: Dictionary) -> float:
	var span: float = f.d if f.ridge_x else f.w
	return span * 0.5 * float(f.pitch)
