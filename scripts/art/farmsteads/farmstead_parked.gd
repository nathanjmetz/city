class_name FarmsteadParked
extends RefCounted
## What stands parked in a county farmstead's yard close up (FarmsteadNear),
## by the month, the way east-central Indiana grain farms work through the
## year (USDA NASS Indiana crop progress: planting late April to May,
## harvest late September to early November):
##   - the pickup by the house, every month, on every farmstead
##   - a grain farm's tractor out in front of its machine shed from spring
##     planting through fall, and the wagon behind it at harvest
##   - at harvest, the combine out of the shed and a hopper-bottom grain
##     trailer at the bins
##   - in winter everything else is shut in the sheds
##   - a hog or dairy farm's tractor out all year (chores every day)
## The farm sticks to one make for its tractor, combine and wagon, as farms
## do. Drawn with the traffic's own models and paint (VehicleModels), engines
## off. Picked from the plan's own facts, never its dice, so the plan and the
## far version are unchanged and every player sees the same yard.

## Kinds that are two models hitched (VehicleModels.ARTIC).
const ARTIC := VehicleModels.ARTIC
static var _meshes := {}  # model kind -> Mesh
## The month the town shows (FarmsteadView keeps it; July with seasons off).
static var month := 7


## [{kind, at (local x, z of the front bumper), yaw, col}] for `month` 1-12.
static func of(p: Dictionary, month: int) -> Array:
	var out := []
	var h := CropCalendar.hash32(int(p.at.x), int(p.at.y), p.seed + 6151)
	var s: float = p.side
	var house: Dictionary = p.house
	# The pickup, nose to the road, on the drive beside the house.
	var front_z: float = house.d + 1.0 if p.kind != "home" else house.d + 3.0 - 6.4
	var pickups: Array = VehicleModels.VARIANTS.pickup
	var truck: String = pickups[h % pickups.size()] if p.kind != "home" or h % 3 != 0 else "suv"
	if not house.vacant:
		out.append({"kind": truck, "at": Vector2(p.get("drive_x", s * 8.0), front_z), "yaw": 0.0,
			"col": VehicleTypes.paint("pickup" if truck != "suv" else "suv", h)})
	if p.kind in ["home", "retired"]:
		return out
	var brand := VehicleTypes.paint("tractor", h >> 3)
	var sheds: Array = p.parts.filter(func(q): return q.kind == "shed" or q.kind == "quonset")
	var harvest := month >= 9 and month <= 11
	var growing := month >= 4 and month <= 8
	var stock: bool = p.kind == "hog" or p.kind == "dairy"
	if sheds.is_empty():
		return out
	var shed: Dictionary = sheds[0]
	var shed_front: float = shed.pos.y - shed.w * 0.5
	# Doors are along the shed's long side, facing the yard.
	var solid := []
	for q in p.parts:
		solid.append(FarmsteadPlan._extent(q).grow(0.8))
	if growing or harvest or stock:
		# With the wagon behind at harvest, standing farther out.
		var kind := "tractor_wagon" if harvest else "tractor"
		_park(out, solid, {"kind": kind, "at": Vector2(shed.pos.x - s * shed.l * 0.25, shed_front - (15.0 if harvest else 9.0)),
			"yaw": 0.0, "col": brand}, s)
	if harvest and p.kind == "grain":
		var other: Dictionary = sheds[1] if sheds.size() > 1 else shed
		var x: float = other.pos.x + s * other.l * (0.2 if other != shed else 0.3)
		_park(out, solid, {"kind": "combine", "at": Vector2(x, other.pos.y - other.w * 0.5 - 11.5), "yaw": 0.0, "col": brand}, s)
		# The grain trailer along the front of the bins, nose toward the house.
		var bins: Array = p.parts.filter(func(q): return q.kind == "bin")
		if not bins.is_empty():
			var first: Dictionary = bins[0]
			# Or along the front of the yard, if the leg and dryer are in the way.
			for z in [22.0, 19.6]:
				if _park(out, solid, {"kind": "grain_truck", "at": Vector2(first.pos.x - s * first.r * 0.5, z),
						"yaw": s * PI * 0.5, "col": VehicleTypes.paint("grain_truck", h >> 5)}, s):
					break
	return out


## Parks `v` where it fits clear of the buildings and what's parked
## already, sliding along the yard 5 m at a time if it doesn't; left in the
## shed if it can't (false).
static func _park(out: Array, solid: Array, v: Dictionary, s: float) -> bool:
	for slide in [0.0, 5.0, -5.0, 10.0, -10.0]:
		var at: Vector2 = v.at + Vector2(s * slide, 0.0)
		var r := footprint(str(v.kind), at, float(v.yaw))
		if not solid.any(func(b: Rect2): return b.intersects(r)):
			v.at = at
			out.append(v)
			solid.append(r.grow(1.0))
			return true
	return false


## The ground a vehicle standing at `at` (its front bumper), turned `yaw`,
## covers (the body runs back from the bumper).
static func footprint(kind: String, at: Vector2, yaw: float) -> Rect2:
	var sp := VehicleTypes.spec(kind)
	var back := Vector2(sin(yaw), cos(yaw))  # where +Z goes after turning
	var side := Vector2(back.y, -back.x) * float(sp.width) * 0.5
	var tail := at + back * float(sp.len)
	return Rect2(at - side, Vector2.ZERO).expand(at + side).expand(tail - side).expand(tail + side)


## Adds the parked machines to `node` (the farmstead's frame), each on the
## ground under it: `lift` takes a local point to its height there.
static func add_to(node: Node3D, p: Dictionary, month: int, lift: Callable) -> void:
	var by := {}  # model -> [[Transform3D, colour]]
	for v in of(p, month):
		var base := Transform3D(Basis(Vector3.UP, float(v.yaw)), Vector3(v.at.x, 0.0, v.at.y))
		var parts := [[str(v.kind), base]]
		if ARTIC.has(v.kind):
			var a: Dictionary = ARTIC[v.kind]
			# Straight behind: the trailer's front `hitch - pin` metres back.
			parts = [[a.cab, base], [a.trailer, base * Transform3D(Basis.IDENTITY, Vector3(0, 0, float(a.hitch) - float(a.pin)))]]
		for part in parts:
			var xf: Transform3D = part[1]
			var mid := xf * Vector3(0, 0, 2.5)
			xf.origin.y = float(lift.call(Vector2(mid.x, mid.z)))
			if not by.has(part[0]):
				by[part[0]] = []
			by[part[0]].append([xf, v.col])
	for kind in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _mesh(kind)
		mm.instance_count = by[kind].size()
		for i in by[kind].size():
			mm.set_instance_transform(i, by[kind][i][0])
			var c: Color = by[kind][i][1]
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, VehicleMaterial.OFF))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = VehicleMaterial.get_material()
		node.add_child(mi)


static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		_meshes[kind] = VehicleModels.build(kind)
	return _meshes[kind]
