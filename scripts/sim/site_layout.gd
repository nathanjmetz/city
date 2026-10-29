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
## inside a building, so a vehicle there is out of sight. A stall in a lot
## of several rows also has "aisle": the z of the aisle it is reached from
## (otherwise the layout's one aisle_z).

const STALL := 2.75     # 9 ft stall, as painted
const STALL_DEPTH := 5.5
const LOT_HALF := 10.0  # HouseBuilder.LOT_HALF
## Middle of the sidewalk, just in front of the lot.
const WALK_Z := -1.05


## Layout of a built lot: {"spots": [...], "door": Vector2, "cut_x": float,
## "aisle_z": float (z of the lane inside the lot cars drive along),
## "walk_z": float (front walk), "main_street": bool}. `lot` is the sim's
## lot, which the builders are fitted to (width, depth, outline).
static func for_building(zone: int, bseed: int, lot := {}, storeys := 0, type := "", level := 0,
		net: RoadNetwork = null) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = bseed
	var art_seed := r.randi()  # BuildingView passes this to the builder
	var fit := _fit(lot)
	if zone == ZoneMap.Zone.COMMERCIAL and fit.has("art") and fit.art.corner:
		fit.art.side = corner_side(net, lot)  # as BuildingView._spawn adds it
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			if type == "duplex":
				var p := DuplexBuilder.plan_info(art_seed, fit.get("art", {"width": fit.half * 2.0, "depth": fit.depth}), level)
				return {"spots": p.spots, "door": Vector2(p.doors[0], p.front_z), "cut_x": p.drives[0][0], "aisle_z": 0.0,
					"walk_z": p.walk_z, "main_street": false}
			if type in ["row_home", "apartments"]:
				# MetroBuilder's flats, courtyards and walkups draw no drive:
				# like a real city block of them, residents park on the street.
				return main_street()
			return house(art_seed, fit, storeys)
		ZoneMap.Zone.COMMERCIAL:
			if type == "office" and storeys < 8:
				return office(art_seed, fit, storeys)
			if type == "office_park":
				return office_park(art_seed, fit, level)
			if type in ["mixed_use", "commercial_block", "office"]:
				return main_street()  # built to the sidewalk; its lot (if any) is out back
			return shop(art_seed, fit, type == "shopping_center", level if type in ["shop", "shopping_center"] else 1)
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


## The shop DenseBuilder.build_retail draws for the lot (a store, diner,
## bank, gas station, strip center or church): its own painted stalls,
## pumps, curb cut and door, read from a dry run of the very same builder
## (DenseBuilder.site_plan), so cars never park where nothing is painted.
static func shop(art_seed: int, fit := {"half": LOT_HALF, "depth": 32.0}, strip := false, level := 1) -> Dictionary:
	var plan := DenseBuilder.site_plan(art_seed, fit.get("art", {"width": float(fit.half) * 2.0, "depth": fit.depth}),
		strip, level)
	if plan.main_street and plan.stalls.is_empty():
		var out := main_street()
		out.door = plan.door
		return out
	var spots := []
	for st in plan.stalls:
		var spot := {"pos": st[0], "face": st[1], "kind": "stall"}
		if st.size() > 2:
			spot.aisle = st[2]  # a big lot's own aisle for this row
		spots.append(spot)
	var door: Vector2 = plan.door
	return {"spots": spots, "door": door, "cut_x": plan.cut_x, "aisle_z": plan.aisle_z,
		"walk_z": door.y - 1.1, "main_street": false}


## DenseBuilder.build_office: the stalls behind it, the drive down its side.
static func office(art_seed: int, fit: Dictionary, storeys: int) -> Dictionary:
	var plan := DenseBuilder.office_plan(art_seed, fit.get("art", {"width": float(fit.half) * 2.0, "depth": fit.depth}),
		storeys)
	if plan.stalls.is_empty():
		var out := main_street()
		out.door = plan.door
		return out
	var spots := []
	for st in plan.stalls:
		spots.append({"pos": st[0], "face": st[1], "kind": "stall"})
	return {"spots": spots, "door": plan.door, "cut_x": plan.cut_x, "aisle_z": plan.aisle_z,
		"walk_z": plan.door.y - 1.1, "main_street": false}


## DenseBuilder.build_office_park: the stalls of its shared lot, its drive.
static func office_park(art_seed: int, fit: Dictionary, level: int) -> Dictionary:
	var plan := DenseBuilder.office_park_plan(art_seed, fit.get("art", {"width": float(fit.half) * 2.0, "depth": fit.depth}), level)
	var spots := []
	for st in plan.stalls:
		var spot := {"pos": st[0], "face": st[1], "kind": "stall"}
		if st.size() > 2:
			spot.aisle = st[2]  # a campus's rows out front have their own aisles
		spots.append(spot)
	# A corporate campus's parking deck: cars drive in and are out of sight.
	for st in plan.get("deck", []):
		spots.append({"pos": st[0], "face": st[1], "kind": "garage"})
	return {"spots": spots, "door": plan.door, "cut_x": plan.cut_x, "aisle_z": plan.aisle_z,
		"walk_z": plan.door.y - 1.1, "main_street": false}


## A building up to the sidewalk with no parking of its own: its people
## park at the curb or in a town lot.
static func main_street() -> Dictionary:
	return {"spots": [], "door": Vector2(0.0, 0.4), "cut_x": 0.0, "aisle_z": 0.0, "walk_z": 0.0,
		"main_street": true}


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
## Which way (the lot's local x, +1 or -1) a corner lot's side street
## lies: the street, not its own, beside one of its side lot lines. 0 when
## it is not a corner lot or no network is given.
static func corner_side(net: RoadNetwork, lot: Dictionary) -> float:
	if net == null or not lot.get("corner", false) or not lot.has("front") or not lot.has("normal"):
		return 0.0
	var half := float(lot.get("width", LOT_HALF * 2.0)) * 0.5
	# Far enough back that the lot's own street is out of reach.
	var z := maxf(float(lot.get("depth", 32.0)) * 0.5, 14.0)
	var best := 0.0
	var best_d := INF
	for s in [-1.0, 1.0]:
		var hit := net.find_segment_near(world(lot, Vector2(s * half, z)), 13.0)
		if not hit.is_empty() and int(hit.seg) != int(lot.get("seg", -1)) and float(hit.dist) < best_d:
			best_d = float(hit.dist)
			best = s
	return best


static func frame(lot: Dictionary) -> Transform3D:
	return Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), lot.front)


static func world(lot: Dictionary, p: Vector2) -> Vector3:
	return frame(lot) * Vector3(p.x, 0.0, p.y)


static func world_dir(lot: Dictionary, d: Vector2) -> Vector3:
	return (frame(lot).basis * Vector3(d.x, 0.0, d.y)).normalized()
