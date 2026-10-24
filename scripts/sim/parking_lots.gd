class_name ParkingLots
extends RefCounted
## Parking lots and the parking garage the player builds from the Roads menu,
## laid out to real US design standards:
##   - stalls 9 x 18 ft (ULI / ITE "Parking" design tables), on 24 ft two-way
##     aisles at 90 degrees, or on 16 ft one-way aisles at 60 degrees
##   - accessible stalls by the 2010 ADA Standards, table 208.2 (1 per 25 up
##     to 100, then 1 per 50...), 8 ft wide with a 5 ft access aisle, and one
##     in six (at least one) van-accessible with an 8 ft aisle, nearest the
##     way out to the street
##   - a two-way drive along the front from the one driveway, planted edges,
##     and (at 60 degrees) a drive along the back so the one-way aisles loop
##   - a 5 ft concrete walk from the accessible stalls, over a marked
##     crossing of the front drive, through the planted strip to the public
##     sidewalk: the accessible route ADA 206.2.1 asks for, and the way
##     every driver walks out to where they're going
## Traffic parks cars in exactly these stalls and the art paints them.
##
## Local space: centred on the site, -z faces the road; the site runs from
## -size.y / 2 (front) to +size.y / 2, as for every service building.

const STALL_W := 2.75    # 9 ft
const STALL_L := 5.5     # 18 ft
const AISLE_90 := 7.3    # 24 ft, two-way
const AISLE_60 := 4.9    # 16 ft, one-way
const ADA_W := 2.45      # 8 ft accessible stall
const ADA_AISLE := 1.55  # 5 ft access aisle
const VAN_AISLE := 2.45  # 8 ft van access aisle
const EDGE := 1.5        # planted strip round the sides and back
const CROSS := 7.3       # the drive along the front (and back)
const SIN60 := 0.8660254
const COS60 := 0.5
## Decks in the garage: the ground floor and three above.
const LEVELS := 4
## The walk out to the sidewalk: 5 ft wide (ADA 403.5.1 asks 36 in; 5 ft
## lets two pass), clear of the 24 ft driveway.
const WALK_W := 1.5
const DRIVE_HALF := 3.65


## Accessible stalls a lot of `total` stalls must have (ADA 2010, 208.2).
static func ada_count(total: int) -> int:
	if total <= 0:
		return 0
	for row in [[25, 1], [50, 2], [75, 3], [100, 4], [150, 5], [200, 6], [300, 7], [400, 8], [500, 9]]:
		if total <= row[0]:
			return row[1]
	if total <= 1000:
		return ceili(total * 0.02)
	return 20 + ceili((total - 1000) / 100.0)


## True when a lot this wide has room for a pair of one-way 60 degree aisles.
static func fits_angled(size: Vector2) -> bool:
	return int((size.x - EDGE * 2.0) / _module(true)) >= 2


static func _module(angled: bool) -> float:
	return (STALL_L * SIN60 + STALL_W * COS60) * 2.0 + AISLE_60 if angled else STALL_L * 2.0 + AISLE_90


## The lot: {"spots": [{pos, face, ada, van, via, out, back_pad, level}],
## "aisles": [[x, flow]], "angled", "front_z" (middle of the front drive),
## "back_z", "row0", "row1", "gate": Vector2, "levels"}.
## Each spot's `pos` is the middle of the parked car and `face` the way its
## nose points; `via` runs from the driveway to the stall's mouth and `out`
## from the aisle beside it back to the driveway (one-way aisles loop round).
static func layout(size: Vector2, angled: bool, garage := false) -> Dictionary:
	if garage or (angled and not fits_angled(size)):
		angled = false
	var front := -size.y * 0.5
	var back := size.y * 0.5
	var zc := front + EDGE + CROSS * 0.5
	# The drive along the back only carries the one-way loop.
	var zb := back - EDGE - AISLE_60 * 0.5
	var row0 := zc + CROSS * 0.5
	var row1 := (zb - AISLE_60 * 0.5) if angled else back - EDGE
	var module := _module(angled)
	var aisle := AISLE_60 if angled else AISLE_90
	var n := int((size.x - EDGE * 2.0) / module)
	if angled:
		n -= n % 2
	var aisles := []
	for k in n:
		# At 60 degrees the aisles go in pairs: in down one, back up the next.
		aisles.append([-n * module * 0.5 + module * (k + 0.5), (1 if k % 2 == 0 else -1) if angled else 0])
	# Rows nearest the driveway first: the accessible stalls go there.
	var rows := []
	var order := range(n)
	order.sort_custom(func(a, b): return _nearer(aisles[a][0], aisles[b][0]))
	for k in order:
		for side in [-1, 1]:
			rows.append([k, side])
	var plain := _fill(rows, aisles, angled, aisle, row0, row1, 0, zc, zb).size()
	var spots := _fill(rows, aisles, angled, aisle, row0, row1, ada_count(plain * (LEVELS if garage else 1)),
		zc, zb)
	if garage:
		# The decks above repeat the ground floor; their cars are out of sight.
		var ground := spots.duplicate()
		for lv in range(1, LEVELS):
			for s in ground:
				var up: Dictionary = s.duplicate()
				up.level = lv
				up.ada = false
				up.van = false
				spots.append(up)
	return {"spots": spots, "aisles": aisles, "angled": angled, "front_z": zc, "back_z": zb, "row0": row0,
		"row1": row1, "gate": Vector2(0.0, front), "aisle": aisle, "levels": LEVELS if garage else 1,
		"walk_x": _walk_x(spots, size)}


## Where the walk out to the sidewalk runs: in line with the first
## accessible stall's access aisle, beside the driveway, inside the lot.
static func _walk_x(spots: Array, size: Vector2) -> float:
	var x := DRIVE_HALF + 1.6
	for s in spots:
		if s.ada:
			x = s.pos.x + s.aisle_off.x
			break
	var lo := DRIVE_HALF + 0.6 + WALK_W * 0.5
	var hi := size.x * 0.5 - EDGE - WALK_W * 0.5
	return signf(x if x != 0.0 else 1.0) * clampf(absf(x), lo, maxf(hi, lo))


## True when an aisle at `a` is nearer the driveway (x = 0) than one at
## `b`, the left first on a tie.
static func _nearer(a: float, b: float) -> bool:
	if absf(absf(a) - absf(b)) > 0.01:
		return absf(a) < absf(b)
	return a < b


static func _fill(rows: Array, aisles: Array, angled: bool, aisle: float, row0: float, row1: float, ada: int,
		zc: float, zb: float) -> Array:
	var spots := []
	var placed_ada := 0
	for r in rows:
		var ax: float = aisles[r[0]][0]
		var flow: int = aisles[r[0]][1]
		var side: int = r[1]
		var face := Vector2(side * SIN60, flow * COS60) if angled else Vector2(side, 0)
		var pitch := STALL_W / SIN60 if angled else STALL_W
		# At 60 degrees a stall leans on along the aisle by its own length.
		var lean := STALL_L * COS60 if angled else 0.0
		var z0 := row0 + (lean if flow < 0 else 0.0)
		var z1 := row1 - (lean if flow > 0 else 0.0)
		var z := z0
		while true:
			# Two accessible stalls to a row at most, so they stay up front.
			var is_ada := _ada_here(rows, r, placed_ada, ada)
			var van := is_ada and placed_ada % 6 == 0
			var w := (ADA_W + (VAN_AISLE if van else ADA_AISLE)) if is_ada else STALL_W
			var along := w / SIN60 if angled else w
			if z + along > z1 + 0.01:
				break
			var mz := z + along * 0.5
			var mouth := Vector2(ax + side * aisle * 0.5, mz)
			var aisle_off := Vector2.ZERO
			if is_ada:
				# The car sits on its 8 ft stall, beside the striped aisle;
				# neighbouring accessible stalls share the side they face.
				var sgn := 1.0 if placed_ada % 2 == 0 else -1.0
				mouth.y += (along - ADA_W / (SIN60 if angled else 1.0)) * 0.5 * sgn
				var perp := Vector2(-face.y, face.x)
				if perp.y * sgn > 0.0:
					perp = -perp
				aisle_off = perp * (w * 0.5)
			var pos := mouth + face * STALL_L * 0.5
			spots.append({"pos": pos, "face": face, "ada": is_ada, "van": van, "level": 0,
				"back_pad": 0.3 if angled else 1.5, "w": w, "aisle_off": aisle_off,
				"via": _via(aisles, r[0], mouth, face, zc, zb),
				"out": _out(aisles, r[0], mz, zc, zb)})
			if is_ada:
				placed_ada += 1
			z += along
	return spots


## Whether the next accessible stall goes in this row: the rows nearest the
## driveway take them in turn, two to a row.
static func _ada_here(rows: Array, r: Array, placed: int, ada: int) -> bool:
	if placed >= ada:
		return false
	var per := 2
	return rows.find(r) == mini(placed / per, rows.size() - 1)


## From the gate along the front drive and down the aisle to the stall.
static func _via(aisles: Array, k: int, mouth: Vector2, face: Vector2, zc: float, zb: float) -> Array:
	var ax: float = aisles[k][0]
	var flow: int = aisles[k][1]
	var pts := [Vector2(0.0, zc - CROSS * 0.5 - EDGE), Vector2(0.0, zc)]
	if flow < 0:
		# Up a one-way aisle: in down its pair, along the back, then up.
		var px: float = aisles[k - 1][0]
		pts.append_array([Vector2(px, zc), Vector2(px, zb), Vector2(ax, zb)])
	else:
		pts.append(Vector2(ax, zc))
	if flow == 0:
		pts.append(Vector2(ax, mouth.y))
	else:
		pts.append(Vector2(ax, mouth.y - flow * 3.0))
	pts.append(mouth - face * 0.3)
	return pts


## From the aisle by the stall back out to the gate.
static func _out(aisles: Array, k: int, mz: float, zc: float, zb: float) -> Array:
	var ax: float = aisles[k][0]
	var flow: int = aisles[k][1]
	var pts := []
	if flow > 0:
		var nx: float = aisles[k + 1][0]
		pts.append_array([Vector2(ax, minf(mz + 4.0, zb - 1.0)), Vector2(ax, zb), Vector2(nx, zb),
			Vector2(nx, zc)])
	else:
		pts.append_array([Vector2(ax, maxf(mz - 4.0, zc + 1.0)), Vector2(ax, zc)])
	pts.append_array([Vector2(0.0, zc), Vector2(0.0, zc - CROSS * 0.5 - EDGE)])
	return pts
