class_name VehicleScans
extends RefCounted
## Real photo-scanned cars, trucks and buses (Sketchfab, CC-BY 4.0, credited
## in art/assets/CREDITS.md), cleaned by tools/vehicles/bake_vehicle.py: true
## size, scanned ground cut away, dark glass behind torn windshields, and three
## tiers in one file (meshes "ultra", "near", "far").
##
## They come through the free asset library (AssetLib), so only the desktop
## app has them. Ids are veh_<kind>_<model>, e.g. veh_sedan_fusion_2016; a kind
## with ENOUGH scans on this machine draws only scans, and the code-built bodies stay
## the fallback (the browser, or before the art pack has downloaded).

const PREFIX := "veh_"
const TIER := {VehicleModels.LOD_NEAR: "near", VehicleModels.LOD_FAR: "far", VehicleModels.LOD_ULTRA: "ultra"}

## Scans a kind needs before its code-built bodies drop out of the mix.
const ENOUGH := 4

static var _by_kind = null
static var _meshes := {}
static var _mats := {}


static func is_scan(key: String) -> bool:
	return key.begins_with(PREFIX)


## The scans of one vehicle kind on this machine, sorted (so a car's id picks
## the same one on every computer that has the same pack).
static func of(kind: String) -> Array:
	if _by_kind == null:
		_by_kind = {}
		# NO_SCANS=1 draws the code-built ones, for A/B benchmarks.
		if AssetLib.available() and OS.get_environment("NO_SCANS") != "1":
			for id in AssetLib.ids("models", "vehicles"):
				var k := kind_of(id)
				if k != "":
					if not _by_kind.has(k):
						_by_kind[k] = []
					_by_kind[k].append(id)
	return _by_kind.get(kind, [])


## veh_sedan_fusion_2016 -> "sedan"; kinds with an underscore (box_truck)
## are matched against VehicleTypes.
static func kind_of(id: String) -> String:
	if not is_scan(id):
		return ""
	var rest := id.trim_prefix(PREFIX)
	var best := ""
	for k in VehicleTypes.kinds():
		if rest.begins_with(str(k) + "_") and str(k).length() > best.length():
			best = k
	return best


## One tier of a scan as an ArrayMesh in VehicleModels' frame (front bumper
## at z = 0, body running +z), or null when the file isn't here.
static func mesh(id: String, lod: int) -> ArrayMesh:
	var key := "%s/%d" % [id, lod]
	if _meshes.has(key):
		return _meshes[key]
	var src := AssetLib.mesh(id, [TIER.get(lod, "near")])
	var out: ArrayMesh = null
	if src:
		# AssetLib centres a picked part; put the front bumper back on z = 0.
		var box := src.get_aabb()
		var shift := Transform3D(Basis(), Vector3(0, 0, -box.position.z))
		out = ArrayMesh.new()
		for s in src.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(src, s, shift)
			st.commit(out)
			var m := src.surface_get_material(s)
			if m is BaseMaterial3D and m.albedo_texture:
				_mats[key] = m
	_meshes[key] = out
	return out


## The material one tier of a scan draws with: the shared vehicle shader
## reading that tier's photo for the body. Null for a code-built model.
static func material(id: String, lod: int) -> Material:
	if not is_scan(id):
		return null
	var key := "%s|%d" % [id, lod]
	if _mats.has(key):
		return _mats[key]
	mesh(id, lod)
	var tex: Texture2D = null
	var m = _mats.get("%s/%d" % [id, lod])
	if m is BaseMaterial3D:
		tex = m.albedo_texture
	var out: ShaderMaterial = VehicleMaterial.get_material(lod == VehicleModels.LOD_ULTRA).duplicate()
	out.set_shader_parameter("scan", tex != null)
	out.set_shader_parameter("scan_tex", tex)
	var me := mesh(id, lod)
	if me:
		out.set_shader_parameter("scan_len", me.get_aabb().end.z)
	_mats[key] = out
	return out
