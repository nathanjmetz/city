class_name SiteLayout
extends RefCounted
## Where cars park and people walk on a lot: parking stalls, loading docks,
## driveways and front doors, in the lot's own frame. The building art draws
## the same lots, so this replays the first few random draws the art makes
## (in scripts/art) to land on the very stalls and doors it paints.
##
## Lot frame (as the building view uses): origin at the lot's street edge
## (lot.front), +Z runs back into the lot, local -Z faces the street.
## Each spot is {"pos": Vector2(x, z), "face": Vector2 (nose direction),
## "kind": "stall"|"drive"|"garage"|"dock"|"bay"}; "garage" and "bay" are
## inside a building, so a vehicle there is out of sight.

const STALL := 2.75     # 9 ft stall, as painted
const STALL_DEPTH := 5.5
const LOT_HALF := 10.0  # HouseBuilder.LOT_HALF
## Middle of the sidewalk, just in front of the lot.
const WALK_Z := -1.05


## Layout of a built lot: {"spots": [...], "door": Vector2, "cut_x": float,
## "aisle_z": float (z of the lane inside the lot cars drive along),
## "walk_z": float (front walk), "main_street": bool}. `lot` is the sim's
## lot, which the builders are fitted to (width, depth, outline).
static func for_building(zone: int, bseed: int, lot := {}) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = bseed
	var art_seed := r.randi()  # BuildingView passes this to the builder
	var fit := _fit(lot)
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			return house(art_seed, fit)
		ZoneMap.Zone.COMMERCIAL:
			return shop(art_seed, fit)
		ZoneMap.Zone.INDUSTRIAL:
			return factory(art_seed, fit)
	return empty_lot()


## The lot as the builders see it (HouseBuilder._fit, with the outline that
## BuildingView._local_lot gives them): half its width and how deep it runs.
static func _fit(lot: Dictionary) -> Dictionary:
	var half := float(lot.get("width", LOT_HALF * 2.0)) * 0.5
	var depth := float(lot.get("depth", 32.0)) - float(lot.get("pad", 0.0))
	var corners: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if corners.size() >= 3 and lot.has("front"):
		var inv := frame(lot).affine_inverse()
		depth = -INF
		for c in corners:
			depth = maxf(depth, (inv * Vector3(c.x, 0.0, c.y)).z)
	return {"half": half, "depth": depth}


## A lot with nothing built: room to pull onto it at the front.
static func empty_lot() -> Dictionary:
	return {"spots": [{"pos": Vector2(0.0, 6.0), "face": Vector2(0, 1), "kind": "drive"}],
		"door": Vector2(0.0, 10.0), "cut_x": 0.0, "aisle_z": 1.0, "walk_z": 1.0, "main_street": false}


## HouseBuilder._house: garage, driveway and front door.
static func house(art_seed: int, fit := {"half": LOT_HALF, "depth": 32.0}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = art_seed
	var avail: float = fit.half * 2.0 - 3.0
	for i in 6:
		rng.randi()  # siding, roof, shutter, door, brick style, brick colours
	var gs := -1.0 if rng.randf() < 0.5 else 1.0
	var gw := 6.6 if rng.randf() < 0.85 else 3.8
	if avail < 16.0:
		gw = 3.8
	elif avail >= 22.0 and rng.randf() < 0.4:
		gw = 9.8
	var zf := rng.randf_range(7.0, 9.5)
	if fit.depth < 30.0:
		zf = clampf(fit.depth * 0.22, 4.5, zf)
	var kind := rng.randf()
	var room := avail - gw
	var drive_x: float
	var gz := zf - 0.35  # colonial garages sit about here
	var door_x: float
	var walk_z := zf - 1.9
	if kind < 0.38:
		var w := rng.randf_range(minf(9.0, room), clampf(room, 7.2, 11.5 + clampf(room - 12.0, 0.0, 2.5)))
		drive_x = gs * w * 0.5
		door_x = -gs * gw * 0.5
	elif kind < 0.58 and avail >= 15.0:
		# Split-level: a tuck-under garage in the two-storey block.
		var tw := rng.randf_range(7.0, 8.2)
		var ww := rng.randf_range(7.6, minf(9.2, avail - tw))
		drive_x = gs * ww * 0.5
		gz = zf
		door_x = -gs * tw * 0.5 + gs * (ww * 0.5 - 1.1)
		walk_z = zf - 2.6
		gw = 3.8
	else:
		var w := rng.randf_range(minf(10.0, room), clampf(room, 7.0, 13.0 + clampf(room - 14.0, 0.0, 3.0)))
		rng.randf_range(8.4, 9.6)  # depth
		gz = zf - rng.randf_range(0.0, 1.5)
		drive_x = gs * w * 0.5
		door_x = -gs * gw * 0.5 + gs * 1.75
	var spots := [{"pos": Vector2(drive_x, gz + 3.0), "face": Vector2(0, 1), "kind": "garage"}]
	if gw > 9.0:
		spots.append({"pos": Vector2(drive_x + 3.0, gz + 3.0), "face": Vector2(0, 1), "kind": "garage"})
	if gw > 5.0 and gz - 3.2 >= 2.6:
		spots.append({"pos": Vector2(drive_x, gz - 3.2), "face": Vector2(0, 1), "kind": "drive"})
	return {"spots": spots, "door": Vector2(door_x, zf), "cut_x": drive_x, "aisle_z": 0.0,
		"walk_z": walk_z, "main_street": false}


## CommercialBuilder.build_shop: a retail lot with a row of stalls in front,
## or a main-street block with no lot of its own.
static func shop(art_seed: int, fit := {"half": LOT_HALF, "depth": 32.0}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = art_seed
	if rng.randf() < 0.4:
		return {"spots": [], "door": Vector2(0.0, 0.4), "cut_x": 0.0, "aisle_z": 0.0, "walk_z": 0.0,
			"main_street": true}
	var half: float = fit.half
	var w := rng.randf_range(minf(14.0, half * 2.0 - 3.0),
		clampf(half * 2.0 - 2.5, 8.0, 17.5 + clampf(half * 2.0 - 22.0, 0.0, 8.0)))
	rng.randf_range(12.0, minf(15.0, maxf(fit.depth - 15.0, 12.0)))  # depth
	rng.randf_range(4.8, 5.6)    # height
	var zf := rng.randf_range(12.0, 13.0)
	rng.randf()  # brick or block
	rng.randi()  # wall colour
	rng.randi()  # mullions
	var sw := w * rng.randf_range(0.6, 0.8)
	var bays := maxi(int(sw / 1.6), 1)
	var door := rng.randi_range(0, bays - 1)
	var door_x := -sw * 0.5 + (door + 0.5) * sw / bays
	var spots := []
	var row_back := zf - 2.2
	var x := -half + 0.6
	while x + STALL <= half - 0.6 + 0.01:
		spots.append({"pos": Vector2(x + STALL * 0.5, row_back - STALL_DEPTH * 0.5), "face": Vector2(0, 1),
			"kind": "stall"})
		x += STALL
	return {"spots": spots, "door": Vector2(door_x, zf), "cut_x": 0.0,
		"aisle_z": (row_back - STALL_DEPTH) * 0.5, "walk_z": zf - 1.1, "main_street": false}


## CommercialBuilder.build_factory: staff stalls by the office, overhead
## doors trucks drive into.
static func factory(art_seed: int, fit := {"half": LOT_HALF, "depth": 32.0}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = art_seed
	var half: float = fit.half
	var w := rng.randf_range(minf(15.0, half * 2.0 - 2.0),
		clampf(half * 2.0 - 1.5, 8.0, 18.5 + clampf(half * 2.0 - 22.0, 0.0, 12.0)))
	rng.randf_range(16.0, minf(21.0, maxf(fit.depth - 14.0, 16.0)))  # depth
	rng.randf_range(6.0, 8.0)    # height
	var zf := rng.randf_range(8.0, 9.5)
	rng.randi()  # wall
	rng.randi()  # wainscot
	rng.randf()  # roof colour
	var ow := rng.randf_range(5.5, 7.0)
	var ox := -w * 0.5 + ow * 0.5
	var spots := []
	var n := 1 if w < 16.5 else 2
	for i in n:
		var dx := (i - (n - 1) * 0.5) * 5.0 + w * 0.12
		spots.append({"pos": Vector2(dx, zf + 5.0), "face": Vector2(0, 1), "kind": "bay"})
	var x := -half + 0.6
	while x + STALL <= -w * 0.5 + ow + 0.51:
		spots.append({"pos": Vector2(x + STALL * 0.5, 2.75), "face": Vector2(0, 1), "kind": "stall"})
		x += STALL
	return {"spots": spots, "door": Vector2(ox, zf - 5.0), "cut_x": w * 0.12, "aisle_z": -0.6,
		"walk_z": zf - 5.6, "main_street": false}


## The lot's frame in the world, as BuildingView places a building.
static func frame(lot: Dictionary) -> Transform3D:
	return Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), lot.front)


static func world(lot: Dictionary, p: Vector2) -> Vector3:
	return frame(lot) * Vector3(p.x, 0.0, p.y)


static func world_dir(lot: Dictionary, d: Vector2) -> Vector3:
	return (frame(lot).basis * Vector3(d.x, 0.0, d.y)).normalized()
