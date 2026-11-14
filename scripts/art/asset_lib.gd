class_name AssetLib
extends RefCounted
## The free asset library: real photo-scanned props, tiling photo surfaces
## and skies, all CC0 or CC-BY 4.0 (free for any use, forever). The list is
## tools/assets/catalog.json; tools/assets/fetch.py downloads them into
## art/assets/ (not in git) and writes art/assets/index.json, which this
## reads. Credits: art/assets/CREDITS.md.
##
## Desktop only. The browser never has them, and a desktop app gets them as a
## separate download (assets pack, see GameUpdater), so every caller must
## keep its code-built version as the fallback:
##     var hydrant := AssetLib.instance("fire_hydrant")
##     if hydrant == null:
##         hydrant = _code_built_hydrant()
## How to add one and which visual loop owns what: tools/assets/README.md.

const INDEX := "res://art/assets/index.json"
const KINDS := ["models", "textures", "hdris"]

static var _index = null
static var _scenes := {}
static var _meshes := {}
static var _materials := {}
static var _skies := {}


## Whether this machine has the library at all (false in the browser).
static func available() -> bool:
	return not index().models.is_empty() or not index().textures.is_empty()


## {"models": {id: info}, "textures": {...}, "hdris": {...}}. Each info has
## author, licence, page, loop, use, real, and for models path, size_m
## (wide, tall, deep in metres) and tris; for textures dir and size_m (the
## real width and height one tile of the photo covers).
static func index() -> Dictionary:
	if _index == null:
		_index = {"models": {}, "textures": {}, "hdris": {}}
		if not OS.has_feature("web") and FileAccess.file_exists(INDEX):
			var d = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
			if typeof(d) == TYPE_DICTIONARY:
				for k in KINDS:
					_index[k] = d.get(k, {})
	return _index


## The ids of one kind ("models", "textures", "hdris"), optionally only the
## ones a visual loop owns ("roads", "houses", "downtown", "countryside",
## "lighting", "civic"), and only those whose files are on this machine.
static func ids(kind: String, loop := "") -> Array:
	var out := []
	for id in index().get(kind, {}):
		if (loop == "" or str(index()[kind][id].get("loop", "")) == loop) and has(id):
			out.append(id)
	out.sort()
	return out


static func info(id: String) -> Dictionary:
	for k in KINDS:
		if index()[k].has(id):
			return index()[k][id]
	return {}


## Whether an asset is listed and its files are here.
static func has(id: String) -> bool:
	var i := info(id)
	if i.is_empty():
		return false
	if i.has("dir"):
		return ResourceLoader.exists(str(i.dir).path_join("albedo.jpg"))
	return ResourceLoader.exists(str(i.get("path", "")))


## A scanned model as a scene (metres, Y up, standing on y = 0), or null.
static func scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		_scenes[id] = null
		if has(id) and index().models.has(id):
			_register_uids(str(info(id).path).get_base_dir())
			_scenes[id] = load(info(id).path)
	return _scenes[id]


## A downloaded art pack isn't in the game's list of resource ids, so a model
## would find its textures by path after a warning each; tell the engine
## their ids first (read from the .import files in the pack).
static func _register_uids(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import"):
			for line in FileAccess.get_file_as_string(dir.path_join(f)).split("\n"):
				if line.begins_with("uid="):
					var uid := ResourceUID.text_to_id(line.trim_prefix("uid=").trim_prefix("\"").trim_suffix("\""))
					if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
						ResourceUID.add_id(uid, dir.path_join(f.trim_suffix(".import")))
					break
	for d in DirAccess.get_directories_at(dir):
		_register_uids(dir.path_join(d))


## A new copy of a scanned model, or null when this machine doesn't have it.
static func instance(id: String) -> Node3D:
	var s := scene(id)
	return s.instantiate() as Node3D if s else null


## The model as one mesh (its materials kept, with distance LODs), for
## MultiMeshes and the builders' mesh lists. Null when missing. Cached:
## every caller shares one copy.
## Many scans are kits or come in clean and worn versions side by side
## (catalog "parts" says which): parts picks pieces by node name, with *
## wildcards, and skip leaves some out, e.g. the clean hydrant is
## mesh("fire_hydrant", ["fire_hydrant*"], ["*aged"]). A picked part is moved
## to stand on y = 0, centred on x and z.
static func mesh(id: String, parts: Array = [], skip: Array = []) -> Mesh:
	var key := "%s|%s|%s" % [id, ",".join(parts), ",".join(skip)]
	if _meshes.has(key):
		return _meshes[key]
	var root := instance(id)
	var out: Mesh = null
	if root:
		var found: Array = []
		_collect(root, Transform3D.IDENTITY, found)
		found = found.filter(func(f): return _picked(str(f[0].name), parts, skip))
		if not parts.is_empty() and not found.is_empty():
			var box: AABB = found[0][1] * found[0][0].mesh.get_aabb()
			for f in found:
				box = box.merge(f[1] * f[0].mesh.get_aabb())
			var shift := Transform3D(Basis(), -Vector3(box.get_center().x, box.position.y, box.get_center().z))
			for f in found:
				f[1] = shift * f[1]
		if found.size() == 1 and found[0][1].is_equal_approx(Transform3D.IDENTITY):
			out = found[0][0].mesh
		elif not found.is_empty():
			out = _merge(found)
		root.free()
	_meshes[key] = out
	return out


static func _picked(name: String, parts: Array, skip: Array) -> bool:
	for p in skip:
		if name.match(p):
			return false
	if parts.is_empty():
		return true
	for p in parts:
		if name.match(p):
			return true
	return false


static func _collect(n: Node, xf: Transform3D, parts: Array) -> void:
	var here: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and n.mesh:
		parts.append([n, here])
	for c in n.get_children():
		_collect(c, here, parts)


static func _merge(parts: Array) -> Mesh:
	var im := ImporterMesh.new()
	for p in parts:
		var mi: MeshInstance3D = p[0]
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, p[1])
			var mat: Material = mi.get_active_material(s)
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mat)
	im.generate_lods(60.0, 0.0, [])
	return im.get_mesh()


## A tiling photo surface (albedo, normal and packed AO/rough/metal) as a
## material. UVs are in metres by default (uv_metres): one tile spans the
## photo's real size, so bricks and boards come out life size. triplanar
## maps it by world position instead, for meshes without UVs. tint
## multiplies the colour (paint a barn red, age a wall).
static func material(id: String, tint := Color.WHITE, triplanar := false, uv_metres := true) -> ORMMaterial3D:
	var key := "%s|%s|%s|%s" % [id, tint.to_html(), triplanar, uv_metres]
	if _materials.has(key):
		return _materials[key]
	var i := info(id)
	var m: ORMMaterial3D = null
	if has(id) and i.has("dir"):
		m = ORMMaterial3D.new()
		m.albedo_texture = load(str(i.dir).path_join("albedo.jpg"))
		m.albedo_color = tint
		m.normal_enabled = true
		m.normal_texture = load(str(i.dir).path_join("normal.jpg"))
		m.orm_texture = load(str(i.dir).path_join("arm.jpg"))
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var size: Array = i.get("size_m", [1.0, 1.0])
		var scale := Vector3(1.0 / maxf(float(size[0]), 0.01), 1.0 / maxf(float(size[1]), 0.01), 1.0)
		if triplanar:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(scale.x, scale.x, scale.x)
		elif uv_metres:
			m.uv1_scale = scale
	_materials[key] = m
	return m


## A photographed sky (an HDRI) for a WorldEnvironment's sky, reflections
## and ambient light, or null.
static func sky(id: String) -> Sky:
	if _skies.has(id):
		return _skies[id]
	var s: Sky = null
	if has(id) and index().hdris.has(id):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(info(id).path)
		s = Sky.new()
		s.sky_material = pm
	_skies[id] = s
	return s


## For tests: forget everything loaded.
static func reset() -> void:
	_index = null
	_scenes.clear()
	_meshes.clear()
	_materials.clear()
	_skies.clear()
