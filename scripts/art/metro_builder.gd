class_name MetroBuilder
extends DenseBuilder
## The older, denser housing of big Midwestern cities, and the parking
## garages downtown (Brawn's metro plan). On prewar streets row homes and
## apartments are drawn as:
##   - Chicago two- and three-flats: one building per 25 ft lot with a
##     gangway between neighbours, a raised garden flat, a limestone
##     "greystone" or red brick front with a three-sided bay up its full
##     height, a stoop up to the entry and a cornice (Chicago Greystone
##     Initiative survey; Logan Square, Lawndale)
##   - courtyard buildings on wide lots: three storeys in a U around a
##     landscaped court open to the street, entries off the court
##     (Chicago's 1910s-20s courtyard apartments, Indianapolis's Old
##     Northside flats)
##   - walk-ups: four to six storeys of brick at the sidewalk with a
##     stone-trimmed stoop, a pressed-metal cornice on brackets and iron
##     fire escapes across the front (New York old-law and new-law
##     tenements, Cincinnati's Over-the-Rhine)
## On newer streets a mid-rise is a 2010s five-over-one (_mb_five_over_one).
## Other eras fall back to DenseBuilder's own looks.

const MB_GREYSTONE := ["#bdb5a3", "#c4bcaa", "#b3ab98", "#a9a294"]
const MB_COMMON := Color("#8f5f45")  # the cheap common brick on sides and backs
const MB_IRON := Color("#1e1f20")
const MB_ROOF := Color("#55524d")  # tar and gravel
## Set by the art gallery to draw one kind of row: flats, townhomes,
## mansard or row.
static var force_row := ""


static func _mb_start(seed: int, lot: Dictionary) -> MetroBuilder:
	var b := MetroBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


static func build_apartments(seed: int, to_curb: float, lot: Dictionary, storeys: int) -> Array:
	var b := _mb_start(seed, lot)
	var width := b.half * 2.0
	# Low buildings on postwar and recent streets are mostly garden
	# apartments (their own dice, so other buildings draw as before).
	var garden := absi(hash([seed, "garden"])) % 100 < 65 and storeys <= 3 and width >= 24.0
	if force_row == "garden" or b.era != "prewar" and garden and force_row == "":
		b._th_garden(to_curb, width, storeys, b.era == "recent")
	elif b.era != "prewar":
		if storeys >= 4 and width >= 28.0 and b.depth >= 30.0:
			b._mb_five_over_one(to_curb, width, storeys)
		else:
			# Three postwar walk-up kinds, each a third (their own dice, so
			# the plain brick block keeps its draws): the plain block, the
			# split-entry eight-plex and the 1970s mansard walk-up.
			var kind := absi(hash([seed, "walkup kind"])) % 3
			if force_row == "walkmodern" or force_row == "" and kind > 0 and storeys <= 3 and b.era == "recent":
				# Today's walk-ups aren't split-levels or mansards.
				b._wu_modern(to_curb, width, storeys)
			elif force_row == "split" or force_row == "" and kind == 1 and storeys <= 3:
				b._wu_split(to_curb, width, storeys)
			elif force_row == "walkmansard" or force_row == "" and kind == 2 and storeys <= 3:
				b._wu_mansard(to_curb, width, storeys)
			else:
				b._apartments(to_curb, width, storeys)
	elif storeys >= 4 and width >= 26.0 and absi(hash([seed, "elevator flats"])) % 100 < 55:
		# Five storeys on an old street: about half are a 1920s elevator
		# apartment building (limestone base, brick, canopy to the curb),
		# the walk-up's bigger sibling, as TowerBuilder draws its flats.
		return TowerBuilder.build_tower(seed, to_curb, lot, storeys, {}, "flats", true)
	elif width >= 34.0 and storeys <= 3 and b.depth >= 34.0:
		b._mb_courtyard(to_curb, width, 3)
	else:
		b._mb_walkup(to_curb, width, maxi(storeys, 3))
	return b._done()


static func build_row(seed: int, to_curb: float, lot: Dictionary, units: int, storeys: int) -> Array:
	var b := _mb_start(seed, lot)
	# Each era's own kind of row (its own dice, so other rows draw as before).
	var kind := absi(hash([seed, "row kind"])) % 100
	var prewar := b.rng.randf() < 0.65
	if force_row != "":
		match force_row:
			"flats": b._mb_flats(to_curb, b.half * 2.0, units, storeys)
			"townhomes": b._th_townhomes(to_curb, b.half * 2.0, units, storeys)
			"mansard": b._th_mansard(to_curb, b.half * 2.0, units, storeys)
			"urban": b._th_urban(to_curb, b.half * 2.0, units, storeys)
			"colonial": b._th_colonial(to_curb, b.half * 2.0, units, storeys)
			_: b._row(to_curb, b.half * 2.0, units, storeys)
	elif b.era == "prewar" and prewar:
		b._mb_flats(to_curb, b.half * 2.0, units, storeys)
	elif b.era == "recent" and (kind < 70 or not b.alley) and b.half * 2.0 / units >= 6.0:
		# (With no alley behind, a builder loads the garages from the front.)
		b._th_townhomes(to_curb, b.half * 2.0, units, storeys)
	elif b.era == "recent":
		b._th_urban(to_curb, b.half * 2.0, units, storeys)
	elif b.era == "postwar" and kind < 50:
		b._th_mansard(to_curb, b.half * 2.0, units, storeys)
	elif b.era == "postwar":
		b._th_colonial(to_curb, b.half * 2.0, units, storeys)
	else:
		b._row(to_curb, b.half * 2.0, units, storeys)
	return b._done()


## A precast concrete parking garage of `levels` decks (for downtown lots).
static func build_garage(seed: int, to_curb: float, lot: Dictionary, levels: int, spec := {}) -> Array:
	var b := _mb_start(seed, lot)
	b.sign_spec = spec
	b._mb_garage(to_curb, b.half * 2.0, levels)
	return b._done()


# ---------------------------------------------------------------- two- and three-flats

func _mb_flats(to_curb: float, width: float, units: int, storeys: int) -> void:
	var uw := (width - 1.0) / units
	var zf := rng.randf_range(4.5, 6.0)
	var floor_h := 3.2
	var base := 1.1  # the garden flat is half sunk, so the first floor is up a stoop
	var grey := rng.randf() < 0.6
	var row_seed := rng.seed
	var backs := []
	for i in units:
		# Each building of the row has its own dice, so one drawn a storey
		# taller (the row's next stage) leaves its neighbours as they were;
		# a two-flat grown to the three-flat stage gains a storey, never
		# loses one.
		rng.seed = hash([row_seed, "flat", i])
		var cx := -width * 0.5 + 0.5 + (i + 0.5) * uw
		var bw := uw - 1.0  # a 3 ft gangway down the side
		var d := rng.randf_range(16.0, 19.0)
		var n := storeys if rng.randf() < 0.7 else mini(storeys + 1, 3)
		var top := base + floor_h * n
		var front := Color(_pick(MB_GREYSTONE)) if grey else Color(_pick(FACADE_BRICK))
		var trim := Color(_pick(["#d9d3c3", "#efede6", "#2e2a26"]))
		_box("brick", Vector3(bw, top, d), Vector3(cx, top * 0.5, zf + d * 0.5), MB_COMMON)
		_mb_roof(cx, bw, zf + d * 0.5, d, top)
		_box("brick", Vector3(bw + 0.1, top + 0.6, 0.3), Vector3(cx, (top + 0.6) * 0.5, zf - 0.13), front)  # the front, up to the parapet
		_box("paint", Vector3(bw + 0.5, 0.45, 0.7), Vector3(cx, top + 0.35, zf - 0.4), front.lightened(0.08))  # cornice
		var bay_side := -1.0 if rng.randf() < 0.5 else 1.0
		var bx := cx + bay_side * (bw * 0.5 - 1.75)
		var dx := cx - bay_side * (bw * 0.5 - 1.25)
		_mb_bay(bx, zf - 0.28, 3.0, 1.0, top - 0.2, base, floor_h, n, front, trim)
		# The entry up the stoop, with a window over it on each floor.
		_stoop(dx, zf - 0.28, 1.6, 1.3, base)
		_front_door(dx, zf - 0.28, base, Color(_pick(DOOR)))
		_box("paint", Vector3(1.6, 0.3, 0.3), Vector3(dx, base + 2.45, zf - 0.4), front.lightened(0.1))  # stone hood
		for f in range(1, n):
			_window(Vector3(dx, base + f * floor_h + 1.5, zf - 0.28), Vector3(-1, 0, 0), 1.0, 1.7, false, false, trim)
		# Garden flat windows just above the ground.
		_window(Vector3(dx + bay_side * 0.2, 0.55, zf - 0.28), Vector3(-1, 0, 0), 0.9, 0.7, false, false, trim)
		# Side windows down the gangway, a few per floor.
		for f in n:
			for k in 3:
				var z := zf + 3.0 + k * (d - 5.0) / 2.0
				for s in [-1.0, 1.0]:
					_window(Vector3(cx + s * bw * 0.5, base + f * floor_h + 1.5, z), Vector3(0, 0, -s), 0.9, 1.5, false, false, trim)
		# A wooden back porch up the back, a door onto it from every flat
		# (the Chicago two- and three-flat's), where the yard has room.
		var porch := depth - (zf + d) >= 7.0 and bw >= 4.6
		_rear_wall(cx - bw * 0.5, cx + bw * 0.5, zf + d, base, floor_h, n, trim, porch)
		if porch:
			_mb_porch(cx, minf(bw - 0.4, 5.6), zf + d, base, floor_h, n, hash([rng.seed, "porch"]))
		backs.append([cx, zf + d + (3.2 if porch else 2.8)])
		_flat_rect("drive", dx - 0.6, dx + 0.6, -0.3, zf - 1.6 - 1.4, 0.06)
		_flat_rect("drive", cx + bay_side * (bw * 0.5 + 0.1), cx + bay_side * (bw * 0.5 + 0.9), zf, zf + d, 0.06)  # the gangway walk
		# A low iron fence along the front yard.
		_box("metal", Vector3(uw - 1.6, 0.05, 0.05), Vector3(cx, 0.9, -0.2), MB_IRON)
		_box("metal", Vector3(uw - 1.6, 0.05, 0.05), Vector3(cx, 0.15, -0.2), MB_IRON)
		if rng.randf() < 0.5:
			_shrub(Vector3(bx, 0.0, zf - 1.9), rng.randf_range(0.45, 0.65))
	_mb_yards(width, uw, backs, hash([row_seed, "yards"]))
	if rng.randf() < 0.7:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(rng.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.2), pick[0], pick[1],
			rng.randf_range(0.7, 1.0)])


## The back porch of a two- or three-flat (Chicago's wooden porches, built
## to the city's 2003 porch rules): a deck off each flat's back door, one
## over another on 6x6 posts, and switchback stairs down the outer side
## from landing to landing to the yard, each deck guarded by a 42 in rail
## on balusters, the top one often roofed. `w` wide, against the back wall
## at z = `zb`; decks 1.8 m deep, the stairs 1.2 m beyond.
func _mb_porch(cx: float, w: float, zb: float, base: float, floor_h: float, floors: int, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var wood := Color(["#8d7b5f", "#7d7f7c", "#a8977a", "#d8d4c8"][r.randi() % 4])
	var post := wood.darkened(0.12)
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var dz := 1.8
	var sz := 1.2
	var zs := zb + dz + sz * 0.5  # the stairs' middle
	var levels := [0.0]
	for f in floors:
		levels.append(base + f * floor_h)
	var top: float = levels[-1]
	var roofed := r.randf() < 0.55
	var post_h := top + (2.5 if roofed else 1.07)
	for px in [x0 + 0.08, cx, x1 - 0.08]:
		for pz in [zb + dz, zb + dz + sz - 0.08]:
			_box("paint", Vector3(0.14, post_h, 0.14), Vector3(px, post_h * 0.5, pz), post)
	for px in [x0 + 0.08, x1 - 0.08]:
		_box("paint", Vector3(0.14, post_h, 0.14), Vector3(px, post_h * 0.5, zb + 0.1), post)
	if roofed:
		_box("paint", Vector3(w + 0.3, 0.12, dz + sz + 0.3), Vector3(cx, post_h + 0.06, zb + (dz + sz) * 0.5), wood.darkened(0.3))
	# The decks, and at each a landing at the stairs' turn.
	var land := 1.1
	var end := 1.0 if r.randf() < 0.5 else -1.0  # where the first flight tops out
	for k in range(1, levels.size()):
		var y: float = levels[k]
		_box("paint", Vector3(w, 0.06, dz), Vector3(cx, y - 0.03, zb + dz * 0.5), wood)
		_box("paint", Vector3(w - 0.1, 0.24, 0.1), Vector3(cx, y - 0.18, zb + dz - 0.05), post)  # the beam
		var e := end if k % 2 == 1 else -end
		var lx := cx + e * (w * 0.5 - land * 0.5)
		_box("paint", Vector3(land, 0.06, sz), Vector3(lx, y - 0.03, zs), wood)
		# The flight up to here from the landing below (or the yard).
		var ya: float = levels[k - 1]
		var xb := cx + e * (w * 0.5 - land)
		var xa := cx - e * (w * 0.5 - (land if k > 1 else 0.0))
		if k == 1:
			xa = xb - e * minf(w - land - 0.2, (y / 0.19) * 0.27)
		_mb_flight(Vector3(xa, ya, zs), Vector3(xb, y, zs), sz - 0.1, wood, post)
		# The guard: a rail around the deck's open ends and its outer edge
		# past the stairs, with balusters.
		if y < 0.76:
			continue
		var ry := y + 1.07
		_mb_rail(Vector3(x0 + 0.06, ry, zb + 0.1), Vector3(x0 + 0.06, ry, zb + dz + sz - 0.06), y, wood)
		_mb_rail(Vector3(x1 - 0.06, ry, zb + 0.1), Vector3(x1 - 0.06, ry, zb + dz + sz - 0.06), y, wood)
		_mb_rail(Vector3(x0 + 0.06, ry, zb + dz + sz - 0.06), Vector3(x1 - 0.06, ry, zb + dz + sz - 0.06), y, wood)
		# Things people keep on the porch: a chair, a grill, a plant.
		var thing := r.randf()
		var tx := cx - e * (w * 0.5 - 0.6)
		if thing < 0.35:
			_box("paint", Vector3(0.5, 0.45, 0.5), Vector3(tx, y + 0.22, zb + 1.0), Color("#2f5a3a"))
			_box("paint", Vector3(0.5, 0.45, 0.06), Vector3(tx, y + 0.65, zb + 1.25), Color("#2f5a3a"))
		elif thing < 0.55:
			_box("metal", Vector3(0.5, 0.85, 0.4), Vector3(tx, y + 0.42, zb + 1.2), Color("#262728"))
		elif thing < 0.75:
			_box("paint", Vector3(0.35, 0.35, 0.35), Vector3(tx, y + 0.17, zb + 0.5), Color("#9c5a3c"))
			_shrub(Vector3(tx, y + 0.3, zb + 0.5), 0.3)


## One stair flight from `a` (bottom) to `b` (top), running along x: open
## treads on two stringers and a handrail on the outer side.
func _mb_flight(a: Vector3, b: Vector3, sw: float, wood: Color, post: Color) -> void:
	var rise := b.y - a.y
	var run := b.x - a.x
	var length := Vector2(run, rise).length()
	var tilt := Basis(Vector3(0, 0, 1), atan2(rise, run))
	var mid := (a + b) * 0.5
	if not fine:
		# The browser: the flight as one sloped run, stringers and all.
		_box("paint", Vector3(length, 0.2, sw), mid + Vector3(0, -0.05, 0), wood, tilt)
		_box("paint", Vector3(length, 0.05, 0.05), mid + Vector3(0, 0.9, sw * 0.5 - 0.02), wood, tilt)
		return
	var n := maxi(2, ceili(rise / 0.2))
	for j in range(1, n):
		var t := float(j) / n
		_box("paint", Vector3(0.3, 0.04, sw), Vector3(lerpf(a.x, b.x, t), a.y + rise * t, a.z), wood)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(length, 0.24, 0.05), mid + Vector3(0, -0.1, s * (sw * 0.5 - 0.02)), post, tilt)
	_box("paint", Vector3(length, 0.05, 0.05), mid + Vector3(0, 0.9, sw * 0.5 - 0.02), wood, tilt)


## A porch guard from `a` to `b` (at rail height), on a deck at `floor_y`:
## top rail, bottom rail and balusters about every 4 in, drawn every 30 cm
## (desktop).
func _mb_rail(a: Vector3, b: Vector3, floor_y: float, wood: Color) -> void:
	var span := a.distance_to(b)
	var along := (b - a) / span
	var basis := Basis(along.cross(Vector3.UP), Vector3.UP, along)
	var mid := (a + b) * 0.5
	_box("paint", Vector3(0.12, 0.05, span), mid, wood, basis)
	if fine:
		_box("paint", Vector3(0.06, 0.05, span), Vector3(mid.x, floor_y + 0.1, mid.z), wood, basis)
	# The browser keeps its triangle budget: a post every 1.2 m, no balusters.
	var n := maxi(1, int(span / (0.3 if fine else 1.2)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		_box("paint", Vector3(0.04, a.y - floor_y - 0.1, 0.04), Vector3(p.x, (a.y + floor_y + 0.1) * 0.5, p.z), wood)


## The yards behind a row of flats: each fenced on its side lines and
## along the alley (4 ft chain-link mostly, some 6 ft wood), a gate and a
## walk out to the alley, and the trash and recycling carts by the gate.
## `backs` holds each building's [middle x, where its yard starts].
func _mb_yards(width: float, uw: float, backs: Array, seed: int) -> void:
	if backs.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var kind := "chain" if r.randf() < 0.75 else "wood"
	var zr := depth - 0.4
	var lines := []
	for i in backs.size() + 1:
		var z0 := 0.0
		if i > 0:
			z0 = maxf(z0, backs[i - 1][1])
		if i < backs.size():
			z0 = maxf(z0, backs[i][1])
		lines.append([-width * 0.5 + 0.5 + i * uw, z0])
	for l in lines:
		if zr - l[1] > 1.5:
			_lot_fence(Vector2(l[0], l[1]), Vector2(l[0], zr), kind)
	for i in backs.size():
		var cx: float = backs[i][0]
		var z0: float = backs[i][1]
		if zr - z0 < 3.0:
			continue
		var a: float = lines[i][0]
		var b: float = lines[i + 1][0]
		# The alley fence with a 3 ft gate in the middle.
		_lot_fence(Vector2(a, zr), Vector2(cx - 0.5, zr), kind)
		_lot_fence(Vector2(cx + 0.5, zr), Vector2(b, zr), kind)
		_flat_rect("drive", cx - 0.45, cx + 0.45, z0 - 0.4, zr, 0.05)
		if r.randf() < 0.85:
			for k in 2:
				var c := Vector3(cx + 1.0 + k * 0.82, 0.0, zr - 0.6)
				var body := Color(["#2a2b2c", "#2f4f8a"][k])
				_box("paint", Vector3(0.66, 1.0, 0.72), c + Vector3(0, 0.5, 0), body.darkened(0.08))
				_box("paint", Vector3(0.72, 0.06, 0.8), c + Vector3(0, 1.04, -0.02), body)


## A three-sided bay up the front: a face `fw` wide at the back narrowing
## to the front face `depth_out` out from the wall, with a window on each
## face of every floor and a cap on top.
func _mb_bay(bx: float, zw: float, fw: float, depth_out: float, h: float, base: float, floor_h: float, n: int,
		col: Color, trim: Color) -> void:
	var front_w := fw - depth_out * 1.2
	var pts := [Vector2(bx - fw * 0.5, zw), Vector2(bx - front_w * 0.5, zw - depth_out),
		Vector2(bx + front_w * 0.5, zw - depth_out), Vector2(bx + fw * 0.5, zw)]
	for k in 3:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var e := (b - a)
		var nrm := Vector3(e.y, 0, -e.x).normalized()  # out of the bay
		_quad("brick", Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), col,
			[Vector2(0, 0), Vector2(e.length(), 0), Vector2(e.length(), h), Vector2(0, h)], nrm)
		var mid := (a + b) * 0.5
		var right := Vector3(nrm.z, 0, -nrm.x)
		var ww := minf(e.length() - 0.4, 1.2)
		for f in n:
			_window(Vector3(mid.x, base + f * floor_h + 1.5, mid.y), right, ww, 1.7, false, false, trim)
		_window(Vector3(mid.x, 0.55, mid.y), right, ww * 0.8, 0.7, false, false, trim)
	_quad("paint", Vector3(pts[0].x, h, pts[0].y), Vector3(pts[1].x, h, pts[1].y), Vector3(pts[2].x, h, pts[2].y),
		Vector3(pts[3].x, h, pts[3].y), col.lightened(0.1), [], Vector3.UP)


# ---------------------------------------------------------------- courtyard buildings

func _mb_courtyard(to_curb: float, width: float, storeys: int) -> void:
	var W := minf(width - 2.0, 46.0)
	var D := minf(depth - 8.0, rng.randf_range(34.0, 42.0))
	var ww := rng.randf_range(10.0, 12.0)  # wing depth: flats either side of a stair
	var zf := rng.randf_range(3.0, 4.5)
	var floor_h := 3.2
	var base := 0.9
	var top := base + floor_h * storeys
	var wall := Color(_pick(FACADE_BRICK + ["#c9b48a", "#b89b72"]))
	var stone := Color(_pick(MB_GREYSTONE))
	var trim := Color(_pick(["#d9d3c3", "#efede6"]))
	var court_z := zf + D - ww  # where the back bar starts
	var parts := [
		[Vector3(ww, top, D), Vector3(-W * 0.5 + ww * 0.5, top * 0.5, zf + D * 0.5)],
		[Vector3(ww, top, D), Vector3(W * 0.5 - ww * 0.5, top * 0.5, zf + D * 0.5)],
		[Vector3(W - ww * 2.0, top, ww), Vector3(0, top * 0.5, court_z + ww * 0.5)],
	]
	for p in parts:
		_box("brick", p[0], p[1], wall)
		_box("paint", Vector3(p[0].x + 0.3, 0.35, p[0].z + 0.3), Vector3(p[1].x, top + 0.2, p[1].z), MB_ROOF)  # tar and gravel
		_box("paint", Vector3(p[0].x + 0.4, 0.3, 0.5), Vector3(p[1].x, top + 0.3, p[1].z - p[0].z * 0.5), stone)  # stone coping on the street end
		_box("paint", Vector3(p[0].x + 0.1, 0.25, p[0].z + 0.1), Vector3(p[1].x, base + floor_h - 0.1, p[1].z), stone)  # belt course
	# Windows on every face that looks out: the street ends of the wings,
	# the court, and the outer sides.
	var faces := [
		[Vector3(-W * 0.5 + ww * 0.5, 0, zf), Vector3(-1, 0, 0), ww],
		[Vector3(W * 0.5 - ww * 0.5, 0, zf), Vector3(-1, 0, 0), ww],
		[Vector3(-W * 0.5 + ww, 0, (zf + court_z) * 0.5), Vector3(0, 0, -1), court_z - zf],
		[Vector3(W * 0.5 - ww, 0, (zf + court_z) * 0.5), Vector3(0, 0, 1), court_z - zf],
		[Vector3(0, 0, court_z), Vector3(-1, 0, 0), W - ww * 2.0],
		[Vector3(-W * 0.5, 0, zf + D * 0.5), Vector3(0, 0, 1), D],
		[Vector3(W * 0.5, 0, zf + D * 0.5), Vector3(0, 0, -1), D],
	]
	for fc in faces:
		var nwin := maxi(2, int(fc[2] / 3.0))
		for f in storeys:
			for i in nwin:
				var c: Vector3 = fc[0] + fc[1] * (-fc[2] * 0.5 + (i + 0.5) * fc[2] / nwin)
				c.y = base + f * floor_h + 1.5
				_window(c, fc[1], 1.1, 1.6, false, false, trim)
	# Entries off the court, each under a stone surround with a stoop.
	var court_w := W - ww * 2.0
	for e in [[Vector3(-court_w * 0.5, 0, zf + (court_z - zf) * 0.5), Vector3(0, 0, -1)],
			[Vector3(court_w * 0.5, 0, zf + (court_z - zf) * 0.5), Vector3(0, 0, 1)],
			[Vector3(0, 0, court_z), Vector3(-1, 0, 0)]]:
		var at: Vector3 = e[0]
		var r: Vector3 = e[1]
		var out := r.cross(Vector3.UP)
		# The side entries are at grade, a step down to the stair hall; the
		# back one is up the stoop.
		var sill := base if r.z == 0.0 else 0.1
		_box("paint", Vector3(2.4, 3.2, 0.3), at + Vector3(0, sill + 1.6, 0) + out * 0.15, stone, Basis(Vector3.UP, atan2(-r.z, -r.x)))
		_glass(at + Vector3(0, sill + 1.2, 0) + out * 0.32, r, 1.4, 2.3, 0.0)
	_stoop(0.0, court_z, 3.0, 1.4, base)
	# The court: a centre walk to the back entry, lawn and shrubs, and an
	# iron fence and gate across its open end.
	_flat_rect("drive", -1.0, 1.0, -0.3, court_z - 1.4 - 1.5, 0.06)
	for s in [-1.0, 1.0]:
		var x: float = s * (court_w * 0.5 - 1.0)
		var z := zf + 1.0
		while z < court_z - 1.0:
			_shrub(Vector3(x, 0.0, z), rng.randf_range(0.4, 0.6))
			z += rng.randf_range(1.6, 2.4)
		_box("metal", Vector3(court_w * 0.5 - 1.4, 0.05, 0.05), Vector3(s * (court_w * 0.25 + 0.7), 1.1, zf + 0.3), MB_IRON)
		_box("metal", Vector3(court_w * 0.5 - 1.4, 0.05, 0.05), Vector3(s * (court_w * 0.25 + 0.7), 0.15, zf + 0.3), MB_IRON)
	if rng.randf() < 0.6:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(rng.randf_range(-court_w * 0.2, court_w * 0.2), 0, zf + (court_z - zf) * 0.55), pick[0], pick[1], rng.randf_range(0.7, 0.9)])
	var pick2 := TreeField.pick(rng)
	trees.append([Vector3(-width * 0.3, 0, -to_curb + 1.2), pick2[0], pick2[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- walk-ups

func _mb_walkup(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 1.0, rng.randf_range(16.0, 26.0))
	var d := minf(depth - 6.0, rng.randf_range(18.0, 24.0))
	var zf := rng.randf_range(1.8, 3.0)
	var cz := zf + d * 0.5
	var floor_h := 3.1
	var base := 0.9
	var top := base + floor_h * storeys
	# Common red, dark brown, buff, cream and the orange-red of local
	# kilns: the brick of old Midwestern walk-ups (Indianapolis, Fort Wayne).
	var wall := Color(_pick(FACADE_BRICK + ["#c9b48a", "#d8c9a3", "#5a3328", "#a4553a"]))
	var stone := Color(_pick(MB_GREYSTONE))
	var trim := Color(_pick(["#d9d3c3", "#efede6", "#2e2a26"]))
	_downtown_walk(to_curb, width, zf)
	_box("brick", Vector3(w, top, d), Vector3(0, top * 0.5, cz), wall)
	_mb_roof(0.0, w, cz, d, top)
	_box("brick", Vector3(w + 0.1, base, 0.12), Vector3(0, base * 0.5, zf - 0.04), stone)  # stone water table
	# A pressed-metal cornice on brackets.
	_box("paint", Vector3(w + 0.4, 0.7, 0.9), Vector3(0, top - 0.1, zf - 0.45), trim)
	var nb := maxi(4, int(w / 1.6))
	for i in nb + 1:
		_box("paint", Vector3(0.2, 0.6, 0.6), Vector3(-w * 0.5 + i * w / nb, top - 0.75, zf - 0.3), trim.darkened(0.1))
	# Windows: an even grid, the entry bay in the middle.
	var cols := maxi(4, int(w / 2.4))
	if cols % 2 == 0:
		cols += 1
	var cw := w / cols
	for f in storeys:
		var y := base + f * floor_h + 1.5
		for i in cols:
			var x := -w * 0.5 + (i + 0.5) * cw
			if f == 0 and i == cols / 2:
				continue
			_window(Vector3(x, y, zf), Vector3(-1, 0, 0), 1.0, 1.6, false, false, trim)
			_box("paint", Vector3(1.3, 0.22, 0.12), Vector3(x, y + 0.95, zf - 0.06), stone)  # stone lintel
		# Side walls: a window in every bay down the depth (the flats run
		# front to back, each room with its own window).
		var nside := maxi(3, int((d - 2.0) / 3.4))
		for s in [-1.0, 1.0]:
			for k in nside:
				_window(Vector3(s * w * 0.5, y, zf + 1.0 + (k + 0.5) * (d - 2.0) / nside), Vector3(0, 0, -s), 0.9, 1.5, false, false, trim)
	# The entry: a stone surround up a stoop.
	_box("paint", Vector3(2.0, 3.0, 0.2), Vector3(0, base + 1.5, zf - 0.1), stone)
	_front_door(0.0, zf - 0.2, base, Color(_pick(DOOR)))
	_stoop(0.0, zf - 0.2, 1.8, 1.2, base)
	# Iron fire escapes on the front: a balcony at each floor over two
	# windows, with drop ladders between them.
	var runs := [[-w * 0.5 + cw, cw * 2.0]] if cols < 7 else [[-w * 0.5 + cw, cw * 2.0], [w * 0.5 - cw, cw * 2.0]]
	for r in runs:
		for f in range(1, storeys):
			var y := base + f * floor_h + 0.05
			_box("metal", Vector3(r[1], 0.06, 1.1), Vector3(r[0], y, zf - 0.6), MB_IRON)
			_box("metal", Vector3(r[1], 0.05, 0.05), Vector3(r[0], y + 0.95, zf - 1.12), MB_IRON)
			_box("metal", Vector3(r[1], 0.05, 0.05), Vector3(r[0], y + 0.5, zf - 1.12), MB_IRON)
			if f < storeys - 1:
				var tilt := Basis(Vector3.FORWARD, 0.95)
				_box("metal", Vector3(floor_h * 1.25, 0.05, 0.45), Vector3(r[0] + (0.3 if f % 2 == 0 else -0.3), y + floor_h * 0.5, zf - 0.85), MB_IRON, tilt if f % 2 == 0 else tilt.inverse())
	# The back porch the flats share, as on the two-flats (wood only up to
	# three storeys, as Chicago's code allows), and the yard to the alley.
	var porch := storeys <= 3 and depth - (zf + d) >= 7.0
	_rear_wall(-w * 0.5, w * 0.5, zf + d, base, floor_h, storeys, trim, porch)
	if porch:
		_mb_porch(0.0, minf(w - 2.0, 6.0), zf + d, base, floor_h, storeys, hash([rng.seed, "walkup porch"]))
		_mb_yards(width, width - 1.0, [[0.0, zf + d + 3.2]], hash([rng.seed, "walkup yard"]))
	_box("metal", Vector3(2.0, 1.0, 1.2), Vector3(rng.randf_range(-w * 0.3, w * 0.3), top + 0.5, cz + d * 0.2), Color("#b9bcbc"))


## A flat tar-and-gravel roof just above a block's top.
func _mb_roof(cx: float, w: float, cz: float, d: float, y: float) -> void:
	var roof := MB_ROOF
	roof.a = 0.5  # gravel ballast in the membrane shader
	_quad("membrane", Vector3(cx - w * 0.5, y + 0.03, cz - d * 0.5), Vector3(cx + w * 0.5, y + 0.03, cz - d * 0.5),
		Vector3(cx + w * 0.5, y + 0.03, cz + d * 0.5), Vector3(cx - w * 0.5, y + 0.03, cz + d * 0.5), roof, [], Vector3.UP)


# ---------------------------------------------------------------- 5-over-1 mid-rise

const MB_PANEL := ["#3b3d40", "#e6e3dc", "#9a7b5c", "#7d8a8f", "#b4a48a", "#5b6b5e"]  # fibre-cement: charcoal, white, cedar-look, slate, khaki, sage


## A 2010s-20s "five-over-one" mid-rise (Carmel City Center, Indiana;
## Indianapolis's Mass Ave and Fort Wayne's riverfront apartments): four
## wood-frame floors (IBC Type V-A) over a one-storey concrete podium of
## shops, a lobby and amenity room, built near the sidewalk. The front is
## broken into bays of fibre-cement panel in two or three colours, every
## other one stepped out, with a brick-veneered corner bay that rises above
## the parapet, Juliet and stacked metal balconies, and a flat roof with
## condensers.
func _mb_five_over_one(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 2.0, rng.randf_range(30.0, 70.0))
	var d := minf(depth - 8.0, rng.randf_range(18.0, 22.0))
	var zf := rng.randf_range(1.5, 3.5)
	var cz := zf + d * 0.5
	var ground_h := 4.6
	var floor_h := 3.05
	var top := ground_h + floor_h * (storeys - 1)
	var podium := Color(_pick(["#8d8a84", "#5a5753", "#b3ada2"]))
	var cols := [Color(_pick(MB_PANEL)), Color(_pick(MB_PANEL)), Color(_pick(MB_PANEL))]
	var brick := Color(_pick(FACADE_BRICK))
	var frame := Color("#2a2b2c") if rng.randf() < 0.7 else Color("#efede6")
	var corner := 1.0 if rng.randf() < 0.5 else -1.0
	_downtown_walk(to_curb, width, zf)
	# The podium: storefronts and the lobby under a steel canopy.
	_box("concrete", Vector3(w, ground_h, d), Vector3(0, ground_h * 0.5, cz), podium)
	var shops := maxi(2, roundi(w / 8.0))
	for i in shops:
		var x := -w * 0.5 + (i + 0.5) * w / shops
		_glass(Vector3(x, 2.2, zf - 0.03), Vector3(-1, 0, 0), w / shops - 1.0, 3.4, rng.randf_range(0.0, 0.2))
	_box("metal", Vector3(w * 0.5, 0.2, 1.6), Vector3(-corner * w * 0.2, ground_h - 0.5, zf - 0.8), frame)
	_sign(Vector3(-corner * w * 0.2, ground_h - 0.25, zf - 1.62), 4.0, 0.5)
	if fine_parts:
		_mb_storefronts(w, zf, ground_h, shops, frame, podium, corner)
	# The wood floors: bays of panel, every other one stepped out.
	var bays := maxi(3, roundi(w / 7.5))
	var bw := w / bays
	_bay_tops = []
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * bw
		var is_corner := (corner > 0.0 and i == bays - 1) or (corner < 0.0 and i == 0)
		var out := 0.6 if i % 2 == 1 else 0.0
		var col: Color = brick if is_corner else cols[i % 2 if bays > 3 else 0]
		if i % 4 == 3 and not is_corner:
			col = cols[2]
		var bt := top + (2.0 if is_corner else (0.6 if i % 2 == 1 else 0.0))
		_box("brick" if is_corner else "siding", Vector3(bw, bt - ground_h, d + out * 2.0), Vector3(x, (ground_h + bt) * 0.5, cz), col)
		_box("paint", Vector3(bw + 0.05, 0.25, d + out * 2.0 + 0.1), Vector3(x, bt + 0.12, cz), col.darkened(0.2))  # parapet cap
		_bay_tops.append(bt + 0.25)
		if bt > top:
			# The raised bay's own roof inside its parapet cap.
			var rc := MB_ROOF
			rc.a = 0.5
			var hx := bw * 0.5 - 0.3
			var hz := d * 0.5 + out - 0.3
			_quad("membrane", Vector3(x - hx, bt + 0.26, cz - hz), Vector3(x + hx, bt + 0.26, cz - hz),
				Vector3(x + hx, bt + 0.26, cz + hz), Vector3(x - hx, bt + 0.26, cz + hz), rc, [], Vector3.UP)
		var face_z := zf - out
		for f in range(1, storeys):
			var y := ground_h + floor_h * (f - 1) + 1.55
			var balcony := not is_corner and i % 2 == 0 and i % 4 != 0
			for k in [-1.0, 1.0]:
				var wx: float = x + k * bw * 0.24
				if balcony and k > 0.0:
					# A sliding door out to a stacked metal balcony.
					_glass(Vector3(wx, y - 0.25, face_z - 0.03), Vector3(-1, 0, 0), 1.8, 2.2, rng.randf_range(0.1, 0.6))
					_box("metal", Vector3(2.6, 0.12, 1.5), Vector3(wx, y - 1.4, face_z - 0.75), frame)
					_box("metal", Vector3(2.6, 1.0, 0.04), Vector3(wx, y - 0.85, face_z - 1.48), frame)
				else:
					_window(Vector3(wx, y, face_z), Vector3(-1, 0, 0), 1.3 if is_corner else 1.6, 1.6, false, false, frame)
					if fine and rng.randf() < 0.25:
						_box("metal", Vector3(1.6, 0.04, 0.04), Vector3(wx, y - 0.25, face_z - 0.18), frame)  # Juliet rail
		# Side windows on the end bays.
		if i == 0 or i == bays - 1:
			var s := -1.0 if i == 0 else 1.0
			var nside := maxi(3, int(d / 3.4))
			for f in range(1, storeys):
				var y := ground_h + floor_h * (f - 1) + 1.55
				for k in nside:
					_window(Vector3(s * w * 0.5, y, zf + (k + 0.5) * d / nside), Vector3(0, 0, -s), 1.2, 1.5, false, false, frame)
	# The back over the parking lot: each bay's windows sit on its own face
	# (stepped-out bays stand proud at the back too), with stacked balconies
	# on some bays like the front.
	var br := RandomNumberGenerator.new()
	br.seed = hash([rng.seed, "five over one back"])
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * bw
		var back_z := zf + d + (0.6 if i % 2 == 1 else 0.0)
		var balcony := i % 2 == 0 and br.randf() < 0.5
		for f in range(1, storeys):
			var y := ground_h + floor_h * (f - 1) + 1.55
			for k in [-1.0, 1.0]:
				var wx: float = x + k * bw * 0.24
				if balcony and k < 0.0:
					_glass(Vector3(wx, y - 0.25, back_z + 0.03), Vector3(1, 0, 0), 1.8, 2.2, br.randf_range(0.1, 0.6))
					_box("metal", Vector3(2.6, 0.12, 1.5), Vector3(wx, y - 1.4, back_z + 0.75), frame)
					_box("metal", Vector3(2.6, 1.0, 0.04), Vector3(wx, y - 0.85, back_z + 1.48), frame)
				else:
					_window(Vector3(wx, y, back_z), Vector3(1, 0, 0), 1.3, 1.5, false, false, frame)
	# The podium's back: the residents' rear lobby door under a canopy off
	# the lot, the trash room's roll-up door, and the amenity room's windows.
	var lx := br.randf_range(-w * 0.25, w * 0.25)
	_glass(Vector3(lx, 1.4, zf + d + 0.03), Vector3(1, 0, 0), 3.0, 2.8, 0.2)
	_box("metal", Vector3(4.2, 0.2, 1.8), Vector3(lx, 3.3, zf + d + 0.9), frame)
	if depth - (zf + d) > 12.0:
		_flat_rect("drive", -w * 0.5, w * 0.5, zf + d, zf + d + 2.0, 0.06)  # walk along the back to the lot
	var rx := (w * 0.5 - 4.0) * (1.0 if lx < 0.0 else -1.0)
	_box("metal", Vector3(3.0, 3.0, 0.08), Vector3(rx, 1.5, zf + d + 0.04), Color("#9a9c9e"))
	if fine_parts:
		for j in 6:
			_box("metal", Vector3(3.0, 0.03, 0.05), Vector3(rx, 0.3 + j * 0.5, zf + d + 0.09), Color("#86888a"))
		_box("metal", Vector3(1.2, 0.9, 0.25), Vector3(rx + (2.6 if rx < 0.0 else -2.6), 1.3, zf + d + 0.13), Color("#7d8184"))  # meter bank
	for j in 3:
		var ax := lx + (j + 1) * 4.5 * (1.0 if lx < 0.0 else -1.0)
		if absf(ax) < w * 0.5 - 2.0 and absf(ax - rx) > 3.5:
			_glass(Vector3(ax, 2.0, zf + d + 0.03), Vector3(1, 0, 0), 3.2, 2.0, br.randf_range(0.0, 0.3))
	_mb_roof(0.0, w, cz, d, top)
	for i in rng.randi_range(4, 8):
		_box("metal", Vector3(1.0, 0.9, 1.0), Vector3(rng.randf_range(-w * 0.4, w * 0.4), top + 0.45, cz + rng.randf_range(-d * 0.3, d * 0.3)), Color("#c4c6c4"))
	if fine_parts:
		_mb_condensers(w, d, cz, top, storeys - 1)
	if depth - (zf + d) > 12.0:
		_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 2.0, depth - 1.0, width)


## Up close, a five-over-one's ground floor as the aluminium storefront
## systems of any 2010s-20s mixed-use block build it (Carmel's City
## Center, Indianapolis's Mass Ave): veneer piers between the shops, a
## dark bulkhead under the glass, mullions about every 1.5 m, a transom
## bar, a glass door with its pull in each shop, a blade sign on some; the
## residents' lobby at the end with its own canopy and address; and a row
## of bike racks on the walk.
func _mb_storefronts(w: float, zf: float, ground_h: float, shops: int, frame: Color, podium: Color, corner: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "storefronts"])
	var sw := w / shops
	var gw := sw - 1.0
	var pier := podium.darkened(0.25) if r.randf() < 0.5 else Color(_pick(FACADE_BRICK))
	for i in shops + 1:
		var px := -w * 0.5 + i * sw
		px = clampf(px, -w * 0.5 + 0.45, w * 0.5 - 0.45)
		_box("brick", Vector3(0.9, ground_h, 0.25), Vector3(px, ground_h * 0.5, zf - 0.1), pier)
	for i in shops:
		var x := -w * 0.5 + (i + 0.5) * sw
		_box("paint", Vector3(gw, 0.5, 0.1), Vector3(x, 0.25, zf - 0.06), podium.darkened(0.4))  # bulkhead
		_box("metal", Vector3(gw, 0.1, 0.1), Vector3(x, 3.0, zf - 0.07), frame)  # transom bar
		_box("metal", Vector3(gw, 0.08, 0.1), Vector3(x, 3.88, zf - 0.07), frame)  # head
		var n := maxi(2, int(gw / 1.5))
		for k in range(1, n):
			_box("metal", Vector3(0.07, 3.4, 0.1), Vector3(x - gw * 0.5 + k * gw / n, 2.2, zf - 0.07), frame)
		# The door in one end bay: a darker leaf with its pull.
		var lobby := (corner > 0.0 and i == shops - 1) or (corner < 0.0 and i == 0)
		var dx := x + (gw * 0.5 - gw / n * 0.5) * (1.0 if i % 2 == 0 else -1.0)
		_box("paint", Vector3(gw / n - 0.15, 2.3, 0.06), Vector3(dx, 1.15, zf - 0.09), Color("#25282a"))
		_box("metal", Vector3(0.05, 0.9, 0.08), Vector3(dx + 0.3, 1.1, zf - 0.16), Color("#c9cbcc"))
		if lobby:
			# The residents' lobby: its own canopy and the address over it.
			_box("metal", Vector3(3.2, 0.18, 1.4), Vector3(dx, 3.15, zf - 0.75), frame)
			for j in 3:
				_box("paint", Vector3(0.22, 0.32, 0.04), Vector3(dx - 0.35 + j * 0.35, 3.55, zf - 0.13), Color("#e9e6dc"))
		elif r.randf() < 0.45:
			# A blade sign on a bracket out over the walk.
			_box("metal", Vector3(0.05, 0.05, 1.1), Vector3(x - gw * 0.35, 4.1, zf - 0.6), frame)
			_box("paint", Vector3(0.06, 0.8, 0.8), Vector3(x - gw * 0.35, 3.6, zf - 0.75), Color(["#7a2e2a", "#2e4a6b", "#2f5a3a", "#d8b45a"][r.randi() % 4]))
	# Bike racks on the walk (inverted U's).
	var bx := -corner * (w * 0.5 - 3.0)
	for k in 3:
		var x2 := bx + corner * k * 0.9
		for e in [-0.35, 0.35]:
			_box("metal", Vector3(0.05, 0.85, 0.05), Vector3(x2, 0.42, zf - 2.2 + e), Color("#3b3e40"))
		_box("metal", Vector3(0.05, 0.05, 0.75), Vector3(x2, 0.85, zf - 2.2), Color("#3b3e40"))


## A wood-frame apartment block's roof as seen from above: every home has
## its own split-system condenser, so the roof carries rows of them, one a
## home (about one per 85 m² of each floor), set on rails either side of a
## walkway pad down the middle over the corridor (any 2010s five-over-one).
var _bay_tops := []


func _mb_condensers(w: float, d: float, cz: float, top: float, floors: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "condensers"])
	var n := clampi(roundi(w * d / 85.0) * floors, 8, 90)
	var per_row := maxi(4, int((w - 4.0) / 1.3))
	var rows := mini(ceili(float(n) / per_row), maxi(2, int((d - 4.0) / 2.6)))
	var unit := Color("#c9cbc8")
	_box("paint", Vector3(w - 3.0, 0.06, 1.0), Vector3(0, top + 0.06, cz), Color("#9a978f"))  # walkway pad (under raised bays)
	var left := n
	for row in rows:
		var side := -1.0 if row % 2 == 0 else 1.0
		var z := cz + side * (1.4 + floori(row / 2.0) * 2.6)
		var k := mini(per_row, left)
		left -= k
		for i in k:
			var x := -(k - 1) * 0.65 + i * 1.3 + r.randf_range(-0.08, 0.08)
			# On whatever the bay under it tops out at (a raised bay's roof).
			var y := top
			if not _bay_tops.is_empty():
				y = maxf(top, float(_bay_tops[clampi(int((x + w * 0.5) / w * _bay_tops.size()), 0, _bay_tops.size() - 1)]))
			_box("metal", Vector3(0.85, 0.8, 0.85), Vector3(x, y + 0.45, z), unit.darkened(r.randf_range(0.0, 0.12)))
			_box("paint", Vector3(0.6, 0.02, 0.6), Vector3(x, y + 0.86, z), Color("#2e3032"))  # fan grille
			_box("metal", Vector3(1.3, 0.12, 0.12), Vector3(x, y + 0.06, z), Color("#6f7275"))  # rail
		if left <= 0:
			break


# ---------------------------------------------------------------- parking garages

func _mb_garage(to_curb: float, width: float, levels: int) -> void:
	var w := minf(width - 1.0, 40.0)
	var d := minf(depth - 4.0, rng.randf_range(36.0, 55.0))
	var zf := 1.5
	var cz := zf + d * 0.5
	var lh := 3.2  # floor to floor
	var concrete := Color(_pick(["#bdb9b0", "#c9c5bb", "#aeaaa1"]))
	var h := lh * levels
	_downtown_walk(to_curb, width, zf)
	# The shadowed decks seen through the open sides.
	_box("paint", Vector3(w - 0.8, h, d - 0.8), Vector3(0, h * 0.5, cz), Color("#2c2d2e"))
	for k in levels + 1:
		var y := k * lh
		# Deck edge and a 1.1 m precast spandrel (the car barrier) round it.
		if k > 0:
			_box("concrete", Vector3(w, 1.1, 0.3), Vector3(0, y + 0.55 - 0.3, zf + 0.15), concrete)
			_box("concrete", Vector3(w, 1.1, 0.3), Vector3(0, y + 0.55 - 0.3, zf + d - 0.15), concrete)
			_box("concrete", Vector3(0.3, 1.1, d), Vector3(-w * 0.5 + 0.15, y + 0.55 - 0.3, cz), concrete)
			_box("concrete", Vector3(0.3, 1.1, d), Vector3(w * 0.5 - 0.15, y + 0.55 - 0.3, cz), concrete)
	# Columns on an 18 m long-span grid.
	var nx := maxi(2, roundi(w / 18.0))
	for i in nx + 1:
		for zz in [zf + 0.3, zf + d - 0.3]:
			_box("concrete", Vector3(0.6, h, 0.6), Vector3(-w * 0.5 + 0.3 + i * (w - 0.6) / nx, h * 0.5, zz), concrete.darkened(0.05))
	# The roof deck with light poles, and a glass stair tower at a corner.
	_quad("paint", Vector3(-w * 0.5, h + 0.31, zf), Vector3(w * 0.5, h + 0.31, zf), Vector3(w * 0.5, h + 0.31, zf + d),
		Vector3(-w * 0.5, h + 0.31, zf + d), Color("#8d8a84"), [], Vector3.UP)
	for i in 3:
		var at := Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.3, zf + d * (0.25 + i * 0.25))
		_box("metal", Vector3(0.18, 7.0, 0.18), at + Vector3(0, 3.5, 0), Color("#5f6266"))
		_box("metal", Vector3(1.2, 0.25, 0.5), at + Vector3(0, 7.0, 0), Color("#5f6266"))
	var sx := -w * 0.5 - 2.2
	_box("concrete", Vector3(4.4, h + 3.0, 5.0), Vector3(sx + 0.0, (h + 3.0) * 0.5, zf + 2.5), concrete)
	_glass(Vector3(sx, (h + 3.0) * 0.5, zf - 0.03), Vector3(-1, 0, 0), 3.0, h + 2.0, 0.0)
	# The entrance lane with its gate arm and the sign.
	_flat_rect("asphalt", w * 0.5 - 8.0, w * 0.5 - 1.5, -to_curb + RoadStyle.CURB_WIDTH, zf + 1.0, 0.07)
	_box("paint", Vector3(0.5, 1.1, 0.5), Vector3(w * 0.5 - 2.2, 0.55, zf - 0.6), Color("#d2a22a"))
	_box("paint", Vector3(3.6, 0.08, 0.08), Vector3(w * 0.5 - 4.0, 1.05, zf - 0.6), Color("#efe9d8"))
	_sign(Vector3(w * 0.5 - 4.75, lh + 0.4, zf - 0.1), 5.0, 1.0)


# ---------------------------------------------------------------- townhomes

## Stone veneer and board-and-batten a recent townhome row mixes with lap
## siding, unit by unit (Fishers, Carmel, Westfield townhome communities).
const TH_STONE := ["#a39a8a", "#b5ab98", "#8f8778", "#c2b8a4"]
const TH_SIDING := ["#e4e1d6", "#c9c3b3", "#6f7f8c", "#8c8f8a", "#d8d2c2", "#5e666b", "#9aa3a8", "#b8a98c"]


## A row of recent townhomes, as Indiana's suburbs build them: each home
## 6-7.5 m wide with a one-car garage under it, its door beside the garage
## under a little gabled portico, two (or three) storeys, a front gable on
## every other home over one long side-gabled roof, siding colours and
## stone veneer bases changing home to home. A short concrete apron per
## garage out to the street.
func _th_townhomes(to_curb: float, width: float, units: int, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "townhomes"])
	var uw := (width - 1.0) / units
	var zf := r.randf_range(6.2, 7.0)  # room for a car on the apron
	var d := r.randf_range(11.5, 13.0)
	var floor_h := 3.0
	var base := 0.3
	var top := base + floor_h * storeys
	var roof := Color(TH_SIDING[0]).darkened(0.6) if r.randf() < 0.3 else Color(ROOF[r.randi() % ROOF.size()])
	var x0 := -width * 0.5 + 0.5
	var x1 := width * 0.5 - 0.5
	var cz := zf + d * 0.5
	var stone := Color(TH_STONE[r.randi() % TH_STONE.size()])
	var first := r.randi() % TH_SIDING.size()
	for i in units:
		var cx := x0 + (i + 0.5) * uw
		var siding := Color(TH_SIDING[(first + i * 3) % TH_SIDING.size()])
		# Ends and middles step forward and back a little, as the plans do.
		var step := 0.0 if i % 2 == 0 else 0.6
		var zu := zf + step
		var du := d - step
		_box("concrete", Vector3(uw, base, du), Vector3(cx, base * 0.5, zu + du * 0.5), FOUNDATION)
		_box("siding", Vector3(uw, top - base, du), Vector3(cx, (base + top) * 0.5, zu + du * 0.5), siding)
		if i % 3 != 1:
			_box("brick", Vector3(uw + 0.02, 1.1, 0.12), Vector3(cx, base + 0.55, zu - 0.05), stone)
		# The garage on one side, the door on the other, mirrored in pairs.
		var side := 1.0 if i % 2 == 0 else -1.0
		var gw := minf(3.0, uw - 2.4)
		var gx := cx + side * (uw * 0.5 - gw * 0.5 - 0.3)
		var dx := cx - side * (uw * 0.5 - 0.95)
		_garage(gx, zu - 0.08, gw + 0.3, 2.2)
		_front_door(dx, zu - 0.12, base, Color(DOOR[(first + i) % DOOR.size()]))
		_stoop(dx, zu - 0.12, 1.4, 1.2, base)
		_gable_roof(dx, zu - 0.65, base + 2.6, 1.6, 0.55, 1.1, false, roof, TRIM, false)
		_flat_rect("drive", gx - gw * 0.5 - 0.2, gx + gw * 0.5 + 0.2, -to_curb, zu, 0.1)
		_flat_rect("drive", dx - 0.55, dx + 0.55, zu - 2.2, zu - 1.2, 0.06)
		_flat_rect("drive", minf(dx, gx) - 0.55, maxf(dx, gx), zu - 2.2, zu - 1.2, 0.06)
		# Windows: a pair over the garage and one over the door each floor.
		for f in range(1, storeys):
			var y := base + f * floor_h + 1.5
			_window(Vector3(gx - 0.6, y, zu), Vector3(-1, 0, 0), 0.8, 1.45, true, false, TRIM)
			_window(Vector3(gx + 0.6, y, zu), Vector3(-1, 0, 0), 0.8, 1.45, true, false, TRIM)
			_window(Vector3(dx, y, zu), Vector3(-1, 0, 0), 0.8, 1.45, true, false, TRIM)
		_window(Vector3(dx, base + 1.5, zu + du), Vector3(1, 0, 0), 0.9, 1.35, true, false, TRIM)
		_box("paint", Vector3(1.95, 2.25, 0.04), Vector3(gx, base + 1.1, zu + du), TRIM)
		_glass(Vector3(gx, base + 1.05, zu + du + 0.03), Vector3(1, 0, 0), 1.8, 2.1, r.randf_range(0.0, 0.3))
		for f in range(1, storeys):
			_window(Vector3(cx, base + f * floor_h + 1.5, zu + du), Vector3(1, 0, 0), 0.9, 1.35, true, false, TRIM)
		# A front gable on every other home, standing on the long roof.
		if i % 2 == 1:
			_gable_roof(cx, zu + 1.6, top, uw - 0.2, uw * 0.33, 3.6, false, roof, siding)
		# A patio out back behind a privacy panel.
		_box("concrete", Vector3(uw - 0.4, 0.1, 3.0), Vector3(cx, 0.05, zf + d + 1.5), FOUNDATION.lightened(0.05))
		if i > 0:
			_box("paint", Vector3(0.06, 1.8, 3.0), Vector3(x0 + i * uw, 0.9, zf + d + 1.5), Color("#e4e3dd"))
	_gable_roof(0.0, cz + 0.3, top, d - 0.6, (d - 0.6) * 0.5 * r.randf_range(0.36, 0.46), x1 - x0, true, roof,
		Color(TH_SIDING[first]))
	if r.randf() < 0.7:
		var pick := TreeField.pick(r)
		trees.append([Vector3(r.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.0), pick[0], pick[1],
			r.randf_range(0.7, 1.0)])


## A 1970s townhouse row: brick ground floor, the upper storey wrapped in a
## steep shingled mansard with dormers, recessed entries between wing
## walls, a flat roof above (the condo and co-op rows of every Midwestern
## city's 1970s edge: Indianapolis's Castleton, Columbus OH, Fort Wayne).
func _th_mansard(to_curb: float, width: float, units: int, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "mansard"])
	var uw := (width - 1.0) / units
	var zf := r.randf_range(5.0, 6.5)
	var d := r.randf_range(10.5, 12.0)
	var floor_h := 2.9
	var base := 0.35
	var brick_top := base + floor_h * (storeys - 1)
	var top := base + floor_h * storeys
	var brick := Color(FACADE_BRICK[r.randi() % FACADE_BRICK.size()])
	var shingle := Color(["#5b4d42", "#45464a", "#655547", "#3d3e41"][r.randi() % 4])
	var x0 := -width * 0.5 + 0.5
	var x1 := width * 0.5 - 0.5
	var cz := zf + d * 0.5
	var inset := 0.9
	_box("concrete", Vector3(x1 - x0, base, d), Vector3(0, base * 0.5, cz), FOUNDATION)
	_box("brick", Vector3(x1 - x0, brick_top - base, d), Vector3(0, (base + brick_top) * 0.5, cz), brick)
	# The upper storey sits back inside the mansard.
	_box("siding", Vector3(x1 - x0 - inset * 2.0, top - brick_top, d - inset * 2.0), Vector3(0, (brick_top + top) * 0.5, cz),
		Color("#d8d2c2"))
	_th_mansard_roof(x0, x1, zf, zf + d, brick_top, top - brick_top + 0.2, inset, shingle)
	for i in units:
		var cx := x0 + (i + 0.5) * uw
		var side := 1.0 if i % 2 == 0 else -1.0
		var dx := cx + side * (uw * 0.5 - 1.2)
		# A recessed entry between short wing walls.
		_box("paint", Vector3(1.6, 2.4, 0.9), Vector3(dx, base + 1.2, zf + 0.4), Color("#3a3530"))
		_front_door(dx, zf + 0.82, base, Color(DOOR[(i * 3 + r.randi()) % DOOR.size()]))
		_box("brick", Vector3(0.3, 1.8, 2.0), Vector3(dx - side * 1.0, 0.9, zf - 1.0), brick)
		_stoop(dx, zf, 1.4, 1.0, base)
		_flat_rect("drive", dx - 0.55, dx + 0.55, -0.3, zf - 1.0, 0.06)
		for f in range(storeys - 1):
			_window(Vector3(cx - side * uw * 0.15, base + f * floor_h + 1.45, zf), Vector3(-1, 0, 0), 1.6, 1.3, false, false, TRIM)
		# A dormer through the mansard for each home's upper storey.
		var dy := brick_top + 0.4
		_box("siding", Vector3(1.4, 1.9, inset + 0.3), Vector3(cx - side * uw * 0.15, dy + 0.95, zf + inset * 0.5 + 0.15), Color("#d8d2c2"))
		_box("roof", Vector3(1.6, 0.12, inset + 0.5), Vector3(cx - side * uw * 0.15, dy + 1.96, zf + inset * 0.5 + 0.1), shingle)
		_window(Vector3(cx - side * uw * 0.15, dy + 0.95, zf), Vector3(-1, 0, 0), 1.0, 1.3, false, false, TRIM)
		if i > 0:
			_box("brick", Vector3(0.3, 1.0, 0.3), Vector3(x0 + i * uw, top + 0.6, cz), brick)  # party wall chimney cap
	_rear_wall(x0, x1, zf + d, base, floor_h, storeys - 1, TRIM)
	# A shared lot out back, off the alley or a drive.
	_rl_back(x0, x1, zf + d + 1.5, zf + d + 14.0, width)
	if r.randf() < 0.6:
		var pick := TreeField.pick(r)
		trees.append([Vector3(r.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.0), pick[0], pick[1],
			r.randf_range(0.7, 1.0)])


## A mansard: steep shingled sides from `y` up `h`, leaning in `inset` on
## every side of the block x0..x1, z0..z1, and a flat roof on top.
func _th_mansard_roof(x0: float, x1: float, z0: float, z1: float, y: float, h: float, inset: float, col: Color) -> void:
	var o := 0.15  # the eave stands proud of the brick
	var a0 := Vector3(x0 - o, y, z0 - o)
	var a1 := Vector3(x1 + o, y, z0 - o)
	var a2 := Vector3(x1 + o, y, z1 + o)
	var a3 := Vector3(x0 - o, y, z1 + o)
	var b0 := Vector3(x0 + inset, y + h, z0 + inset)
	var b1 := Vector3(x1 - inset, y + h, z0 + inset)
	var b2 := Vector3(x1 - inset, y + h, z1 - inset)
	var b3 := Vector3(x0 + inset, y + h, z1 - inset)
	_quad("roof", a0, a1, b1, b0, col, [], Vector3(0, inset, -h))
	_quad("roof", a1, a2, b2, b1, col, [], Vector3(h, inset, 0))
	_quad("roof", a2, a3, b3, b2, col, [], Vector3(0, inset, h))
	_quad("roof", a3, a0, b0, b3, col, [], Vector3(-h, inset, 0))
	_quad("membrane", b0, b1, b2, b3, Color("#55524d"), [], Vector3.UP)
	_box("paint", Vector3(x1 - x0 + o * 2.0, 0.2, 0.08), Vector3((x0 + x1) * 0.5, y - 0.05, z0 - o), TRIM)


## Today's urban townhomes, the rest of a recent street's rows: rear-loaded
## (garages off the alley, so the front is all door, glass and stoop), as
## built in Carmel's Old Town, Fishers' Nickel Plate district and Fall
## Creek Place in Indianapolis since 2005: units alternating brick and dark
## fibre-cement panels, each with its own parapet height, tall paired
## windows with a Juliet rail, a steel canopy over a raised stoop, and a
## rooftop terrace behind a black rail with a stair penthouse.
func _th_urban(to_curb: float, width: float, units: int, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "urban townhomes"])
	var uw := (width - 1.0) / units
	var zf := r.randf_range(3.5, 4.5)
	var d := r.randf_range(12.0, 14.0)
	var floor_h := 3.0
	var base := 0.6
	var deck := base + floor_h * storeys
	var cz := zf + d * 0.5
	var black := Color("#1f2224")
	var brick := Color(["#7a4234", "#5a3a32", "#8a4a38", "#4a4440", "#9b5a42"][r.randi() % 5])
	var panel := Color(["#3b3f42", "#55606a", "#6b6f70", "#e4e1d6", "#b9b4a8"][r.randi() % 5])
	var first := r.randi() % 2
	for i in units:
		var cx := -width * 0.5 + 0.5 + (i + 0.5) * uw
		var is_brick := (i + first) % 2 == 0
		var wall := brick if is_brick else panel
		var top := deck + (0.5 if is_brick else 0.9)
		_block("brick" if is_brick else "siding", cx, uw, d, cz, deck, top, wall)
		_box("metal", Vector3(uw + 0.02, 0.12, 0.3), Vector3(cx, top, zf - 0.05), black if is_brick else wall.darkened(0.3))
		_box("concrete", Vector3(uw, base, 0.08), Vector3(cx, base * 0.5, zf - 0.02), FOUNDATION)
		var side := 1.0 if i % 2 == 0 else -1.0
		var door_x := cx + side * (uw * 0.5 - 1.0)
		# The stoop, black-railed, under a flat steel canopy.
		_stoop(door_x, zf - 0.05, 1.4, 1.6, base)
		for e in [-1.0, 1.0]:
			_box("metal", Vector3(0.04, 0.9, 1.6), Vector3(door_x + e * 0.68, base + 0.45, zf - 0.85), black)
		_box("paint", Vector3(1.0, 2.2, 0.06), Vector3(door_x, base + 1.1, zf - 0.03), black if r.randf() < 0.5 else Color("#6b4a2e"))
		_glass(Vector3(door_x, base + 2.5, zf - 0.04), Vector3(-1, 0, 0), 0.9, 0.45, 0.0)
		_box("metal", Vector3(1.7, 0.1, 1.1), Vector3(door_x, base + 2.95, zf - 0.55), black)
		# A tall window beside the door, a window pair on each floor above.
		var wx := cx - side * uw * 0.12
		_glass(Vector3(wx, base + 1.35, zf - 0.03), Vector3(-1, 0, 0), uw * 0.4, 2.1, r.randf_range(0.0, 0.4))
		_box("metal", Vector3(uw * 0.4 + 0.1, 2.2, 0.04), Vector3(wx, base + 1.35, zf - 0.01), black)
		for f in range(1, storeys):
			var y := base + f * floor_h + 1.3
			var gw := minf(uw - 1.6, 2.6)
			_box("metal", Vector3(gw + 0.12, 2.15, 0.04), Vector3(cx, y, zf - 0.01), black)
			for e in [-0.5, 0.5]:
				_glass(Vector3(cx + e * gw * 0.5, y, zf - 0.03), Vector3(-1, 0, 0), gw * 0.5 - 0.06, 2.0, r.randf_range(0.0, 0.6))
			if f == 1:
				_box("metal", Vector3(gw + 0.2, 0.05, 0.05), Vector3(cx, y - 0.1, zf - 0.3), black)
				for q in 7:
					_box("metal", Vector3(0.025, 0.85, 0.025), Vector3(cx - gw * 0.5 + q * gw / 6.0, y - 0.52, zf - 0.3), black)
		# The roof terrace: a rail set back from the front, the stair up.
		var rz := zf + 1.5
		_box("metal", Vector3(uw - 0.6, 0.05, 0.05), Vector3(cx, top + 1.0, rz), black)
		for q in maxi(4, int(uw / 0.4)):
			_box("metal", Vector3(0.025, 1.0, 0.025), Vector3(lerpf(cx - uw * 0.5 + 0.3, cx + uw * 0.5 - 0.3, q / float(maxi(3, int(uw / 0.4) - 1))), top + 0.5, rz), black)
		_box("siding", Vector3(2.2, 2.5, 2.8), Vector3(cx + side * (uw * 0.5 - 1.4), deck + 1.25, zf + d - 2.2), wall.darkened(0.1))
		# Rear-loaded: a garage door on the alley side of each unit; with no
		# alley, a sliding door onto a patio behind a privacy screen.
		var gd := Color("#e8e4d8") if r.randf() < 0.6 else black
		if alley:
			_box("paint", Vector3(minf(uw - 1.2, 4.9), 2.2, 0.06), Vector3(cx, 1.1, zf + d + 0.03), gd)
		else:
			_glass(Vector3(cx, base + 1.05, zf + d + 0.03), Vector3(1, 0, 0), 1.8, 2.1, 0.2)
			_flat_rect("drive", cx - uw * 0.5 + 0.2, cx + uw * 0.5 - 0.2, zf + d, zf + d + 3.2, 0.06)
			if i > 0:
				_box("paint", Vector3(0.08, 1.8, 3.0), Vector3(cx - uw * 0.5, 0.9, zf + d + 1.5), Color("#6f6a62"))
		for f in range(1, storeys):
			for e in [-1.0, 1.0]:
				_window(Vector3(cx + e * uw * 0.25, base + f * floor_h + 1.4, zf + d), Vector3(1, 0, 0), 1.0, 1.5, false, false, black)
		# A small deck over the garage, off the kitchen.
		_box("paint", Vector3(minf(uw - 1.0, 4.0), 0.15, 1.6), Vector3(cx, base + floor_h - 0.1, zf + d + 0.8), Color("#8d7b5f"))
		_box("metal", Vector3(minf(uw - 1.0, 4.0), 0.05, 0.05), Vector3(cx, base + floor_h + 0.9, zf + d + 1.6), black)
		for q in 9:
			_box("metal", Vector3(0.025, 0.95, 0.025), Vector3(cx - minf(uw - 1.0, 4.0) * 0.5 + q * minf(uw - 1.0, 4.0) / 8.0,
				base + floor_h + 0.45, zf + d + 1.6), black)
		_flat_rect("drive", door_x - 0.6, door_x + 0.6, -0.3, zf - 1.6, 0.06)
		if r.randf() < 0.7:
			_box("concrete", Vector3(uw * 0.4, 0.45, 0.5), Vector3(wx, 0.22, zf - 0.6), Color("#8f8b84"))
			_shrub(Vector3(wx, 0.4, zf - 0.6), r.randf_range(0.3, 0.45))
	for e in [-width * 0.5 + 0.5, width * 0.5 - 0.5]:
		_box("concrete", Vector3(0.08, base, d), Vector3(e + signf(e) * 0.02, base * 0.5, cz), FOUNDATION)
	# Each garage's apron (the alley runs behind; deeper lots keep a yard).
	if alley:
		_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, zf + d, minf(depth - 1.0, zf + d + 6.5), 0.06)
	var pick := TreeField.pick(r)
	trees.append([Vector3(r.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.6, 0.9)])


## The 1960s-70s colonial townhouse row, the rest of a postwar street's
## rows (Indianapolis's Eagle Creek and Castleton co-ops, Fort Wayne's and
## Muncie's townhouse courts): two storeys under one long side-gabled
## roof, brick fire walls rising through the shingles between the units,
## units alternating brick and painted siding, black shutters, a little
## pediment over each door and a brick-walled patio out back.
func _th_colonial(to_curb: float, width: float, units: int, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "colonial townhouses"])
	var uw := (width - 1.0) / units
	var zf := r.randf_range(5.5, 7.0)
	var d := r.randf_range(9.5, 11.0)
	var floor_h := 2.8
	var base := 0.3
	var deck := base + floor_h * storeys
	var cz := zf + d * 0.5
	var x0 := -width * 0.5 + 0.5
	var x1 := width * 0.5 - 0.5
	var brick := Color(FACADE_BRICK[r.randi() % FACADE_BRICK.size()])
	var sidings := ["#e8e4d8", "#d8d0bc", "#9aa3a8", "#c9c3b3", "#b8a98c", "#6f7f8c"]
	var roof := Color(ROOF[r.randi() % ROOF.size()])
	var shutter := Color(["#1c1d1f", "#2f4632", "#3a2c22", "#1f2d3d"][r.randi() % 4])
	var rise := d * 0.5 * r.randf_range(0.42, 0.55)
	_box("concrete", Vector3(x1 - x0, base, d), Vector3(0, base * 0.5, cz), FOUNDATION)
	for i in units:
		var cx := x0 + (i + 0.5) * uw
		var is_brick := (i % 3 == 0) or r.randf() < 0.3
		var wall := brick if is_brick else Color(sidings[r.randi() % sidings.size()])
		_box("brick" if is_brick else "siding", Vector3(uw, deck - base, d), Vector3(cx, (base + deck) * 0.5, cz), wall)
		var side := 1.0 if i % 2 == 0 else -1.0
		var door_x := cx + side * (uw * 0.5 - 1.1)
		_stoop(door_x, zf - 0.05, 1.5, 1.2, base)
		_front_door(door_x, zf, base, Color(DOOR[r.randi() % DOOR.size()]))
		_gable_roof(door_x, zf - 0.35, base + 2.35, 1.7, 0.45, 0.7, false, TRIM, TRIM, false)
		_window(Vector3(cx - side * uw * 0.15, base + 1.45, zf), Vector3(-1, 0, 0), 1.4, 1.5, true, true, shutter)
		for f in range(1, storeys):
			for e in [-1.0, 1.0]:
				_window(Vector3(cx + e * uw * 0.22, base + f * floor_h + 1.4, zf), Vector3(-1, 0, 0), 0.9, 1.35, true, true, shutter)
		# Out back: a sliding door onto a brick-walled patio.
		_glass(Vector3(cx, base + 1.05, zf + d + 0.03), Vector3(1, 0, 0), 1.8, 2.0, r.randf_range(0.0, 0.4))
		for f in range(1, storeys):
			_window(Vector3(cx, base + f * floor_h + 1.4, zf + d), Vector3(1, 0, 0), 1.0, 1.35, false, false, TRIM)
		var pw := uw - 0.4
		_box("concrete", Vector3(pw, 0.08, 3.6), Vector3(cx, 0.04, zf + d + 1.8), FOUNDATION.lightened(0.05))
		for e in [-1.0, 1.0]:
			_box("brick", Vector3(0.2, 1.6, 3.6), Vector3(cx + e * pw * 0.5, 0.8, zf + d + 1.8), brick)
		_box("brick", Vector3(pw * 0.35, 1.6, 0.2), Vector3(cx - pw * 0.32, 0.8, zf + d + 3.6), brick)
		_flat_rect("drive", door_x - 0.6, door_x + 0.6, -0.3, zf - 1.2, 0.06)
		if r.randf() < 0.75:
			_shrub(Vector3(cx - side * uw * 0.15, 0.0, zf - 0.7), r.randf_range(0.4, 0.6))
	_gable_roof(0.0, cz, deck, d, rise, x1 - x0, true, roof, brick)
	# Brick fire walls through the roof at every party wall and both ends.
	var slope := atan2(rise, d * 0.5)
	var run := sqrt(rise * rise + d * d * 0.25) + 0.3
	for i in units + 1:
		var fx := x0 + i * uw
		if i == 0 or i == units:
			fx += -0.1 if i == 0 else 0.1
		for e in [-1.0, 1.0]:
			var mid := Vector3(fx, deck + rise * 0.5 + 0.22, cz + e * d * 0.25)
			_box("brick", Vector3(0.35, 0.3, run), mid, brick.darkened(0.05), Basis(Vector3.RIGHT, e * slope))
	# Parking in a court behind, as the co-ops built it.
	_rl_back(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 5.0, zf + d + 18.0, width)
	var pick := TreeField.pick(r)
	trees.append([Vector3(r.randf_range(-width * 0.3, width * 0.3), 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.7, 1.0)])


# ---------------------------------------------------------------- postwar walk-ups

## The split-entry walk-up, the 1960s-70s four- and eight-plex on every
## Midwestern town's side streets: the lower flats half sunk, their wide
## short windows in steel window wells, the front door at grade on the
## landing between the two floors (stairs half a flight down, half a
## flight up), a tall stair-hall window over it under a front gable, brick
## to the upper sills and siding above, and a low side-gabled roof.
func _wu_split(to_curb: float, width: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "split walkup"])
	var w := minf(width - 4.0, r.randf_range(22.0, 30.0))
	var d := r.randf_range(13.0, 15.0)
	var zf := r.randf_range(6.0, 8.0)
	var floor_h := 2.8
	var sunk := 1.2  # the lower floor sits this far below grade
	var top := floor_h * storeys - sunk + 0.2
	var cz := zf + d * 0.5
	var brick := Color(FACADE_BRICK[r.randi() % FACADE_BRICK.size()])
	var siding := Color(TH_SIDING[r.randi() % TH_SIDING.size()])
	var roof := Color(ROOF[r.randi() % ROOF.size()])
	var trim := Color(["#efede6", "#d9d3c3", "#3b3a36"][r.randi() % 3])
	var sill := floor_h - sunk + 0.9  # top of the brick: the upper floor's sills
	_box("concrete", Vector3(w + 0.1, 0.25, d + 0.1), Vector3(0, 0.12, cz), FOUNDATION)
	_box("brick", Vector3(w, sill, d), Vector3(0, sill * 0.5, cz), brick)
	_box("siding", Vector3(w - 0.02, top - sill, d - 0.02), Vector3(0, (sill + top) * 0.5, cz), siding)
	_box("paint", Vector3(w + 0.06, 0.1, d + 0.06), Vector3(0, sill, cz), trim)
	# The entry: a recessed door at grade, the stair-hall glass above it.
	var hw := 2.6
	_box("paint", Vector3(hw, top - 0.3, 0.3), Vector3(0, (top - 0.3) * 0.5 + 0.1, zf + 0.1), siding.darkened(0.1))
	_box("paint", Vector3(1.4, 2.25, 0.06), Vector3(0, 1.22, zf - 0.08), Color("#5a3b2a") if r.randf() < 0.5 else trim)
	_glass(Vector3(0, 1.3, zf - 0.12), Vector3(-1, 0, 0), 0.5, 1.6, 0.0)
	for k in storeys - 1:
		var y := 2.6 + k * floor_h + floor_h * 0.5
		_glass(Vector3(0, y, zf - 0.08), Vector3(-1, 0, 0), 1.6, 1.8, 0.0)
	_box("concrete", Vector3(hw + 0.8, 0.15, 1.8), Vector3(0, 0.08, zf - 0.9), FOUNDATION.lightened(0.05))
	_flat_rect("drive", -0.8, 0.8, -0.3, zf - 1.8, 0.06)
	_gable_roof(0.0, zf + 1.4, top, hw + 2.0, (hw + 2.0) * 0.5 * 0.55, 3.2, false, roof, siding)
	# Coach lamps either side of the door.
	for s in [-1.0, 1.0]:
		_box("metal", Vector3(0.18, 0.32, 0.14), Vector3(s * 1.0, 2.1, zf - 0.2), Color("#1e1e1e"))
	# Flats either side: a wide low window in a well downstairs, a pair upstairs.
	var n := maxi(1, roundi((w * 0.5 - hw * 0.5) / 6.5))
	for s in [-1.0, 1.0]:
		var a := hw * 0.5 + 0.4
		var b := w * 0.5 - 0.4
		for u in n:
			var x: float = s * lerpf(a, b, (u + 0.5) / n)
			_window(Vector3(x, 0.55, zf), Vector3(-1, 0, 0), 1.8, 0.75, false, false, trim)
			_box("metal", Vector3(2.1, 0.5, 0.06), Vector3(x, 0.0, zf - 0.75), Color("#7d8082"))
			for e in [-1.0, 1.0]:
				_box("metal", Vector3(0.06, 0.5, 0.72), Vector3(x + e * 1.05, 0.0, zf - 0.39), Color("#7d8082"))
			_box("concrete", Vector3(2.0, 0.04, 0.68), Vector3(x, -0.2, zf - 0.39), Color("#7a6a52"))
			for f in range(1, storeys):
				var y := f * floor_h - sunk + 1.55
				for e in [-1.0, 1.0]:
					_window(Vector3(x + e * 0.85, y, zf), Vector3(-1, 0, 0), 1.0, 1.4, false, r.randf() < 0.5, Color("#2f3a32"))
		# A window on each floor of the end walls too.
		for f in storeys:
			var y := 0.55 if f == 0 else f * floor_h - sunk + 1.55
			_window(Vector3(s * w * 0.5, y, cz), Vector3(0, 0, -s), 1.0, 0.75 if f == 0 else 1.4, false, false, trim)
	_gable_roof(0.0, cz, top, d, d * 0.5 * 0.33, w, true, roof, siding)
	_rear_wall(-w * 0.5, w * 0.5, zf + d, 0.0, floor_h, storeys, trim)
	_rl_back(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 14.0, width)
	var x := -w * 0.5 + 0.5
	while x < w * 0.5 - 0.4:
		if absf(x) > hw * 0.5 + 0.5:
			_shrub(Vector3(x, 0.0, zf - 1.1), r.randf_range(0.35, 0.55))
		x += r.randf_range(1.4, 2.2)
	var pick := TreeField.pick(r)
	trees.append([Vector3(width * 0.3, 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.8, 1.0)])


## Today's small walk-up apartment building, as Indiana towns have built
## them since 2010 (Westfield, Greenwood, Lafayette's infill): three
## storeys under a flat roof, a brick base and two tones of fibre-cement
## panel above, a glazed stair tower at the entry rising past the parapet,
## stacked balconies with black rails set into the wall, and parking
## behind.
func _wu_modern(to_curb: float, width: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "modern walkup"])
	var w := minf(width - 4.0, r.randf_range(24.0, 32.0))
	var d := r.randf_range(15.0, 17.0)
	var zf := r.randf_range(6.0, 8.0)
	var base := 0.3
	var floor_h := 3.0
	var deck := base + floor_h * storeys
	var top := deck + 0.7
	var cz := zf + d * 0.5
	var black := Color("#1f2224")
	var brick := Color(["#7a4234", "#5a3a32", "#4a4440", "#8a4a38"][r.randi() % 4])
	var light := Color(["#e4e1d6", "#d8d2c2", "#b9b4a8"][r.randi() % 3])
	var dark := Color(["#3b3f42", "#55606a", "#6b5a48", "#2f3a4a"][r.randi() % 4])
	_block("siding", 0.0, w, d, cz, deck, top, light)
	_box("brick", Vector3(w + 0.04, base + floor_h, d + 0.04), Vector3(0, (base + floor_h) * 0.5, cz), brick)
	_box("concrete", Vector3(w + 0.1, base, d + 0.1), Vector3(0, base * 0.5, cz), FOUNDATION)
	# Dark panel wings at both ends, a shade proud of the light middle.
	for e in [-1.0, 1.0]:
		_box("siding", Vector3(5.2, top - base - floor_h + 0.4, 0.2), Vector3(e * (w * 0.5 - 2.6), (base + floor_h + top + 0.4) * 0.5, zf - 0.1), dark)
	_box("metal", Vector3(w + 0.1, 0.15, 0.4), Vector3(0, top, zf - 0.1), black)
	# The stair tower: glass from the door to above the roof.
	var tw := 3.4
	_box("siding", Vector3(tw + 0.6, top + 1.4, 1.0), Vector3(0, (top + 1.4) * 0.5, zf - 0.3), dark)
	_glass(Vector3(0, (top + 1.0) * 0.5 + 0.2, zf - 0.82), Vector3(-1, 0, 0), tw - 0.4, top + 0.6, 0.0)
	for f in storeys + 1:
		_box("metal", Vector3(tw - 0.3, 0.08, 0.06), Vector3(0, base + f * floor_h, zf - 0.84), black)
	_box("metal", Vector3(tw + 1.4, 0.15, 1.8), Vector3(0, 3.0, zf - 1.5), black)
	_box("paint", Vector3(1.8, 2.3, 0.05), Vector3(0, 1.4, zf - 0.83), black)
	_stoop(0.0, zf - 0.8, 3.0, 1.2, base)
	_flat_rect("drive", -0.9, 0.9, -0.3, zf - 2.0, 0.06)
	# Flats either side: a window and a recessed balcony each floor.
	var n := maxi(1, roundi((w * 0.5 - tw * 0.5 - 0.6) / 6.0))
	for s in [-1.0, 1.0]:
		for u in n:
			var a := tw * 0.5 + 0.8
			var x: float = s * lerpf(a, w * 0.5 - 0.6, (u + 0.5) / n)
			for f in storeys:
				var y := base + f * floor_h
				_glass(Vector3(x - s * 1.3, y + 1.55, zf - 0.22 if absf(x - s * 1.3) > w * 0.5 - 5.2 else zf - 0.02), Vector3(-1, 0, 0), 1.2, 1.6, r.randf_range(0.0, 0.6))
				var bx: float = x + s * 0.9
				_box("paint", Vector3(2.4, 2.2, 0.06), Vector3(bx, y + 1.1, zf - 0.02), dark.darkened(0.2))
				_glass(Vector3(bx, y + 1.08, zf - 0.06), Vector3(-1, 0, 0), 2.0, 2.0, r.randf_range(0.0, 0.5))
				if f == 0:
					_box("concrete", Vector3(2.6, 0.1, 1.6), Vector3(bx, 0.05, zf - 0.8), FOUNDATION.lightened(0.05))
					continue
				_box("paint", Vector3(2.6, 0.16, 1.3), Vector3(bx, y - 0.05, zf - 0.65), Color("#8d7b5f"))
				_box("metal", Vector3(2.6, 0.05, 0.05), Vector3(bx, y + 1.0, zf - 1.28), black)
				for q in 11:
					_box("metal", Vector3(0.025, 1.0, 0.025), Vector3(bx - 1.3 + q * 0.26, y + 0.5, zf - 1.28), black)
	for f in storeys:
		for e in [-1.0, 1.0]:
			_window(Vector3(e * w * 0.5, base + f * floor_h + 1.55, cz), Vector3(0, 0, -e), 1.2, 1.6, false, false, black)
	_rear_wall(-w * 0.5, w * 0.5, zf + d, base, floor_h, storeys, black)
	for i in r.randi_range(2, 4):
		_box("metal", Vector3(1.2, 0.8, 0.9), Vector3(r.randf_range(-w * 0.4, w * 0.4), deck + 0.4, cz + r.randf_range(-3.0, 3.0)), Color("#b9bcbc"))
	_rl_back(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 16.0, width)
	var x := -w * 0.5 + 0.6
	while x < w * 0.5 - 0.5:
		if absf(x) > tw * 0.5 + 1.0:
			_shrub(Vector3(x, 0.0, zf - 1.9), r.randf_range(0.35, 0.5), 1)
		x += r.randf_range(1.0, 1.6)
	var pick := TreeField.pick(r)
	trees.append([Vector3(width * 0.3, 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.7, 0.9)])


## The 1970s mansard walk-up, Indiana's apartment look of the oil-crisis
## years: a brick block whose top floor hides inside a steep shingled
## mansard, its windows in boxed dormers through the shingles, a little
## balcony with a black iron rail for each upper flat on the brick floors,
## and a double-door entry under a mansard hood.
func _wu_mansard(to_curb: float, width: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "mansard walkup"])
	var w := minf(width - 4.0, r.randf_range(24.0, 32.0))
	var d := r.randf_range(14.0, 16.0)
	var zf := r.randf_range(6.0, 8.0)
	var base := 0.4
	var floor_h := 2.9
	var deck := base + floor_h * (storeys - 1)  # where the mansard starts
	var top := deck + floor_h + 0.3
	var cz := zf + d * 0.5
	var out := 0.7
	var brick := Color(FACADE_BRICK[r.randi() % FACADE_BRICK.size()])
	var shingle := Color(["#4a3b30", "#3a3a3c", "#5b4636", "#6b5a48"][r.randi() % 4])
	var trim := Color(["#d9d3c3", "#cfc8b6", "#efede6"][r.randi() % 3])
	var iron := Color("#1f2021")
	_box("concrete", Vector3(w + 0.1, base, d + 0.1), Vector3(0, base * 0.5, cz), FOUNDATION)
	_block("brick", 0.0, w, d, cz, top - 0.05, top, brick)
	_mansard(w, d, cz, zf, deck, top - 0.05, out, shingle)
	_box("paint", Vector3(w + out * 2.0 + 0.1, 0.12, d + out * 2.0 + 0.1), Vector3(0, deck, cz), trim)
	# The entry: double glass doors under a small mansard hood.
	_box("paint", Vector3(2.4, 2.4, 0.06), Vector3(0, base + 1.2, zf - 0.04), Color("#3a2c22"))
	for s in [-1.0, 1.0]:
		_glass(Vector3(s * 0.55, base + 1.15, zf - 0.08), Vector3(-1, 0, 0), 0.9, 2.1, 0.0)
	var hood_y := base + 2.6
	_box("roof", Vector3(3.4, 0.5, 1.4), Vector3(0, hood_y + 0.25, zf - 0.7), shingle)
	_box("paint", Vector3(3.5, 0.08, 1.5), Vector3(0, hood_y, zf - 0.72), trim)
	_stoop(0.0, zf, 3.0, 1.6, base)
	_flat_rect("drive", -0.9, 0.9, -0.3, zf - 1.6, 0.06)
	# Stair-hall windows over the door on the brick floors.
	for f in range(1, storeys - 1):
		_glass(Vector3(0, base + f * floor_h + 1.5, zf - 0.02), Vector3(-1, 0, 0), 1.0, 1.5, 0.0)
	var n := maxi(1, roundi((w * 0.5 - 2.0) / 6.0))
	for s in [-1.0, 1.0]:
		for u in n:
			var x: float = s * lerpf(2.2, w * 0.5 - 0.6, (u + 0.5) / n)
			for f in storeys - 1:
				var y := base + f * floor_h
				_window(Vector3(x - s * 1.1, y + 1.5, zf), Vector3(-1, 0, 0), 1.2, 1.4, false, false, trim)
				# A sliding patio door, with a balcony above the ground floor.
				var bx: float = x + s * 0.8
				_box("paint", Vector3(1.9, 2.15, 0.05), Vector3(bx, y + 1.1, zf - 0.02), trim)
				_glass(Vector3(bx, y + 1.08, zf - 0.05), Vector3(-1, 0, 0), 1.7, 1.95, r.randf_range(0.0, 0.5))
				if f == 0:
					_box("concrete", Vector3(2.4, 0.1, 1.6), Vector3(bx, 0.05, zf - 0.8), FOUNDATION.lightened(0.05))
					continue
				_box("concrete", Vector3(2.4, 0.16, 1.2), Vector3(bx, y - 0.05, zf - 0.6), FOUNDATION)
				_box("paint", Vector3(2.4, 0.05, 0.05), Vector3(bx, y + 0.95, zf - 1.18), iron)
				for e in [-1.0, 1.0]:
					_box("paint", Vector3(0.05, 0.05, 1.2), Vector3(bx + e * 1.17, y + 0.95, zf - 0.6), iron)
				for k in 11:
					_box("paint", Vector3(0.025, 0.9, 0.025), Vector3(bx - 1.17 + k * 2.34 / 10.0, y + 0.5, zf - 1.18), iron)
			# The top floor's window in a boxed dormer through the mansard.
			var dy := deck + floor_h * 0.55
			_box("siding", Vector3(1.7, 1.9, out + 0.1), Vector3(x, dy, zf - (out + 0.1) * 0.5), trim)
			_box("roof", Vector3(1.9, 0.12, out + 0.3), Vector3(x, dy + 1.0, zf - (out + 0.1) * 0.5 - 0.1), shingle)
			_window(Vector3(x, dy, zf - out - 0.1), Vector3(-1, 0, 0), 1.2, 1.4, false, false, trim)
	# End walls: a window each brick floor.
	for f in storeys - 1:
		for s in [-1.0, 1.0]:
			_window(Vector3(s * w * 0.5, base + f * floor_h + 1.5, cz), Vector3(0, 0, -s), 1.0, 1.4, false, false, trim)
	_rear_wall(-w * 0.5, w * 0.5, zf + d, base, floor_h, storeys - 1, trim)
	for i in r.randi_range(1, 2):
		_box("metal", Vector3(1.4, 0.9, 1.0), Vector3(r.randf_range(-w * 0.3, w * 0.3), top + 0.45, cz), Color("#b9bcbc"))
	_rl_back(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 14.0, width)
	var x := -w * 0.5 + 0.6
	while x < w * 0.5 - 0.5:
		if absf(x) > 2.0:
			_shrub(Vector3(x, 0.0, zf - 1.9), r.randf_range(0.4, 0.6))
		x += r.randf_range(1.3, 2.1)
	var pick := TreeField.pick(r)
	trees.append([Vector3(-width * 0.3, 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- garden apartments

## A garden apartment building, the walk-up of every Midwestern town's
## edge: two or three storeys of flats round open breezeway stairs, a
## balcony or patio for each flat, parking behind. `modern` draws today's
## (lap siding over a stone base, a gabled front over each breezeway,
## white-railed balconies: Indiana's 2010s garden communities); otherwise
## the 1960s-70s kind (brick, a low hip roof, steel-railed concrete
## balconies, the breezeway a dark slot through the building).
func _th_garden(to_curb: float, width: float, storeys: int, modern: bool) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "garden"])
	var w := minf(width - 4.0, r.randf_range(26.0, 40.0))
	var d := r.randf_range(13.0, 15.0)
	var zf := r.randf_range(6.0, 8.0)
	var base := 0.4
	var floor_h := 2.9
	var top := base + floor_h * storeys
	var cz := zf + d * 0.5
	var wall := Color(TH_SIDING[r.randi() % TH_SIDING.size()]) if modern else Color(FACADE_BRICK[r.randi() % FACADE_BRICK.size()])
	var stone := Color(TH_STONE[r.randi() % TH_STONE.size()])
	var roof := Color(ROOF[r.randi() % ROOF.size()])
	var trim := TRIM if modern else Color(["#d9d3c3", "#cfc8b6", "#efede6"][r.randi() % 3])
	_box("concrete", Vector3(w + 0.1, base, d + 0.1), Vector3(0, base * 0.5, cz), FOUNDATION)
	_box("siding" if modern else "brick", Vector3(w, top - base, d), Vector3(0, (base + top) * 0.5, cz), wall)
	if modern:
		_box("brick", Vector3(w + 0.03, 1.2, 0.12), Vector3(0, base + 0.6, zf - 0.05), stone)
	# Breezeways: one in the middle, or two on a long building.
	var halls := [0.0] if w < 32.0 else [-w * 0.25, w * 0.25]
	var hw := 3.2
	for hx: float in halls:
		_box("paint", Vector3(hw, top - base - 0.1, 0.5), Vector3(hx, (base + top) * 0.5, zf + 0.2), Color("#2c2b29"))
		# Stair flights rising inside, catching the light.
		for f in storeys - 1:
			for k in 2:
				var y0 := base + f * floor_h + k * floor_h * 0.5
				_box("concrete", Vector3(1.2, 0.18, 2.6), Vector3(hx + (k * 2 - 1) * 0.7, y0 + floor_h * 0.25, zf + 0.6),
					FOUNDATION, Basis(Vector3.RIGHT, -0.5))
		_stoop(hx, zf, hw, 1.4, base)
		_flat_rect("drive", hx - 0.8, hx + 0.8, -0.3, zf - 1.4, 0.06)
		if modern:
			_gable_roof(hx, zf + 1.5, top, hw + 2.4, (hw + 2.4) * 0.4, 3.6, false, roof, wall)
	# Flats either side of each breezeway: windows and a balcony each.
	var spans := []
	var edges := [-w * 0.5] + halls.map(func(h): return h - hw * 0.5)
	var ends := halls.map(func(h): return h + hw * 0.5) + [w * 0.5]
	for i in edges.size():
		spans.append([edges[i] + 0.4 if i == 0 else ends[i - 1] + 0.4, (halls[i] - hw * 0.5 if i < halls.size() else w * 0.5) - 0.4])
	for sp in spans:
		var a: float = sp[0]
		var b: float = sp[1]
		var n := maxi(1, roundi((b - a) / 7.5))
		var fw := (b - a) / n
		for u in n:
			var fx := a + (u + 0.5) * fw
			for f in storeys:
				var y := base + f * floor_h
				_window(Vector3(fx - fw * 0.28, y + 1.5, zf), Vector3(-1, 0, 0), 1.0, 1.4, modern, false, trim)
				# A patio door onto the balcony (or a ground-floor patio).
				var bx := fx + fw * 0.15
				_box("paint", Vector3(1.9, 2.2, 0.05), Vector3(bx, y + 1.1, zf - 0.02), trim)
				_glass(Vector3(bx, y + 1.08, zf - 0.05), Vector3(-1, 0, 0), 1.7, 2.0, r.randf_range(0.0, 0.4))
				if f == 0:
					_box("concrete", Vector3(2.6, 0.12, 1.8), Vector3(bx, 0.06, zf - 0.9), FOUNDATION.lightened(0.05))
					continue
				var rail := trim if modern else Color("#2a2b2c")
				_box("concrete" if not modern else "paint", Vector3(2.6, 0.18, 1.5), Vector3(bx, y - 0.05, zf - 0.75),
					FOUNDATION if not modern else Color("#8d7b5f"))
				_box("paint", Vector3(2.6, 0.06, 0.06), Vector3(bx, y + 1.0, zf - 1.47), rail)
				for s in [-1.0, 1.0]:
					_box("paint", Vector3(0.06, 0.06, 1.5), Vector3(bx + s * 1.27, y + 1.0, zf - 0.75), rail)
				var m := 12
				for k in m + 1:
					_box("paint", Vector3(0.03, 0.95, 0.03), Vector3(bx - 1.27 + k * 2.54 / m, y + 0.55, zf - 1.47), rail)
	for f in storeys:
		for s in [-1.0, 1.0]:
			_window(Vector3(s * w * 0.5, base + f * floor_h + 1.5, cz), Vector3(0, 0, -s), 1.0, 1.4, modern, false, trim)
	if modern:
		_gable_roof(0.0, cz, top, d, d * 0.5 * 0.42, w, true, roof, wall)
	else:
		_hip_roof(0.0, cz, top, w, d, r.randf_range(1.3, 1.8), roof)
	_rear_wall(-w * 0.5, w * 0.5, zf + d, base, floor_h, storeys, trim)
	_rl_back(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 1.5, zf + d + 16.0, width)
	var x := -w * 0.5 + 0.6
	while x < w * 0.5 - 0.5:
		var clear := true
		for hx: float in halls:
			clear = clear and absf(x - hx) > hw * 0.5 + 0.5
		if clear:
			_shrub(Vector3(x, 0.0, zf - 0.5), r.randf_range(0.4, 0.6))
		x += r.randf_range(1.6, 2.6)
	var pick := TreeField.pick(r)
	trees.append([Vector3(-width * 0.3, 0, -to_curb + 1.2), pick[0], pick[1], r.randf_range(0.8, 1.0)])
