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
static func for_building(zone: int, bseed: int, lot := {}, storeys := 0) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = bseed
	var art_seed := r.randi()  # BuildingView passes this to the builder
	var fit := _fit(lot)
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			return house(art_seed, fit, storeys)
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
	var out := {"half": half, "depth": depth}
	if lot.has("front") and lot.has("normal"):
		# The lot exactly as BuildingView._local_lot hands it to the builders.
		var art := {"width": lot.get("width", LOT_HALF * 2.0), "depth": lot.get("depth", 32.0),
			"pad": lot.get("pad", 0.0), "at": Vector2(lot.front.x, lot.front.z), "corner": lot.get("corner", false)}
		if corners.size() >= 3:
			var inv := frame(lot).affine_inverse()
			var local := PackedVector2Array()
			for c in corners:
				var q := inv * Vector3(c.x, 0.0, c.y)
				local.append(Vector2(q.x, q.z))
			art.outline = local
		out.art = art
	return out


## A lot with nothing built: room to pull onto it at the front.
static func empty_lot() -> Dictionary:
	return {"spots": [{"pos": Vector2(0.0, 6.0), "face": Vector2(0, 1), "kind": "drive"}],
		"door": Vector2(0.0, 10.0), "cut_x": 0.0, "aisle_z": 1.0, "walk_z": 1.0, "main_street": false}


## HouseBuilder._house: garage, driveway and front door, read from the
## plan the art draws for the lot (HouseBuilder.plan_info), so cars use
## the drive that is painted.
static func house(art_seed: int, fit := {"half": LOT_HALF, "depth": 32.0}, storeys := 0) -> Dictionary:
	var h := HouseBuilder.plan_info(art_seed, fit.get("art", {"width": fit.half * 2.0, "depth": fit.depth}), storeys)
	var drive_x: float = h.drive_x
	var gz: float = h.garage_z
	# One car per garage bay (a 9 ft door each), and on a two- or three-car
	# drive one more parks out front beside, in front of the last bay, so
	# the car in the garage can back out past it, as on a real wide drive.
	var bays := 1 if h.drive_w < 4.5 else (2 if h.drive_w < 8.5 else 3)
	var bay: float = h.drive_w / bays
	var spots := []
	for i in maxi(bays - 1, 1):
		spots.append({"pos": Vector2(drive_x + (i - (bays - 1) * 0.5) * bay, gz + 3.0), "face": Vector2(0, 1),
			"kind": "garage"})
	if bays > 1 and gz - 3.2 >= 2.6:
		spots.append({"pos": Vector2(drive_x + (bays - 1) * 0.5 * bay, gz - 3.2), "face": Vector2(0, 1),
			"kind": "drive"})
	return {"spots": spots, "door": Vector2(h.door_x, h.front_z), "cut_x": drive_x, "aisle_z": 0.0,
		"walk_z": h.walk_z, "main_street": false}


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
