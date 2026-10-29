class_name TreeField
extends Node3D
## All the trees in town, drawn as one MultiMesh per kind so a whole city
## of trees costs a handful of draw calls. Benchmark: photos of mature
## Midwestern streets, where big yard and street trees frame every block,
## and Grant County woodlots and fencerows.
##
## A tree here is three facts: its kind (Species, the real Grant County
## trees in TreeKinds and docs/trees.md), a seed (where it stands) and its
## age, from the day it was planted. Yard and street trees go in as
## balled-and-burlapped nursery stock (TreeKinds.NURSERY_HEIGHT, 12 to 14 ft
## for a shade tree) and grow on over the game's years; wild trees come with the age the woods give them.
##
## These are the cheap trees: clusters of leaf cards with a generated leaf
## texture, in the shape of each kind's crown at its real size. Normals
## point out from the canopy centre, so a crown shades like a soft volume,
## and the inside of the crown is darker. Leaves sway a little in the wind.
## Near the camera GrownTrees takes over with trees grown branch by branch
## (TreeGrower); these cards hand over to them with a dither (TreeLook).
## Trees are grouped in square chunks. Each chunk has a full card tree up
## close and a light version (a few big cards, fitted to the same crown)
## far away, so a big city stays cheap for the web build. Each tree hands
## over between the two with a dither at its own distance from the camera
## (TreeLook), not a whole chunk at once; a chunk draws only the versions
## some of its trees need.

enum Species { MAPLE, OAK, LOCUST, SPRUCE, CRABAPPLE, RED_OAK, SILVER_MAPLE, SYCAMORE, WALNUT, HACKBERRY,
	COTTONWOOD, RED_CEDAR }
## How far each species' crown reaches out from the trunk at full size (m),
## so planters can keep crowns off walls.
const SPREAD := {Species.MAPLE: 6.0, Species.OAK: 7.5, Species.LOCUST: 6.0, Species.SPRUCE: 4.0,
	Species.CRABAPPLE: 3.0, Species.RED_OAK: 7.0, Species.SILVER_MAPLE: 6.5, Species.SYCAMORE: 8.5,
	Species.WALNUT: 6.5, Species.HACKBERRY: 6.5, Species.COTTONWOOD: 8.5, Species.RED_CEDAR: 1.8}

## Summer leaf colours (sRGB, as TreeKinds green) and how much each tree can vary from them.
const LEAF := [Color("#46661f"), Color("#3f5c1e"), Color("#627424"), Color("#2c4433"), Color("#4a6326"),
	Color("#3d5a1d"), Color("#56702c"), Color("#5b7330"), Color("#5e7426"), Color("#4f6a28"), Color("#4c6b22"),
	Color("#2f472a")]

## Chunk size, and the distance where the full tree gives way to the light
## one (scaled by the quality tier; TreeLook.card_near).
const CHUNK := 256.0
const NEAR := 380.0
## How far the camera moves before the chunks' versions are looked at again
## (each look allows for the camera moving this far).
const SHOW_MOVE := 24.0
## Trees with a planting date are re-sized this often (a sim day, a month
## of growth: trees grow on pace years, Seasons.pace_year, so a planted
## street fills out within a session): slow things update once a day.
const REGROW_TICKS := Seasons.OLD_TICKS_PER_MONTH
## Milliseconds a frame may spend re-sizing grown-on trees.
const REGROW_MS := 1.5

static var _meshes := {}
static var _leaf_tex: ImageTexture
static var _twig_tex: ImageTexture
## The game's clock (the sim's tick count), set each frame by WildView;
## trees with a planting date grow by it.
static var now_tick := 0
## Labs only: pretend every planted tree went in this many years earlier.
static var extra_years := 0.0
## Bumped whenever any field's trees change, so GrownTrees knows to look again.
static var version := 0
## Every field in the scene, for GrownTrees.
static var fields: Array = []

## True for wild trees: they fade out toward the edge of WildView's reach.
var fades := false

var _trees := {}  # owner key -> Array of [Transform3D, species, tint, facts]
var _multis := {}  # "cx,cz,species,far" -> MultiMeshInstance3D
## Which owners have trees in each chunk, and the chunks whose batches are
## out of date: one lot's trees changing redraws only the chunks they
## stand in, not every tree in town.
var _owners := {}  # Vector2i chunk -> {owner key: true}
var _dirty := {}  # Vector2i chunk -> true
var _growing := {}  # Vector2i chunk -> true: holds trees with a planting date
var _regrow := []  # chunks to re-size, a few a frame
var _last_regrow := -1
var _records := {}  # Vector2i chunk -> [trees, resolved trees (null until asked)], for GrownTrees
var _records_at := []  # [field transform, view origin] the records were worked out for
var _versions := {}  # Vector2i chunk -> [full MultiMeshInstance3Ds, light ones]
var _shown := {}  # Vector2i chunk -> which versions it draws (1 full, 2 light)
var _shown_at := Vector4(INF, INF, INF, INF)  # the camera (local) and reaches they were worked out for


## Replaces the trees that belong to `key` (a lot). Each tree is
## [Transform3D (world), species, tint Color] and, optionally, its facts:
##   {"planted": tick}: planted then as nursery stock, it grows on with the
##     game's clock toward the size in its transform (the size it reaches
##     at TreeKinds.REF_AGE, and it keeps growing after);
##   {"planted": tick, "start": years}: the same, but already this old on
##     that day (a grown yard tree, yard_age), growing on from there;
##   {"age": years}: this old, drawn at the size in its transform;
##   {"shrub": true}: brush, never grown up close.
## Without facts the age comes from the size.
func set_trees(key: String, trees: Array) -> void:
	_unfile(key)
	_trees[key] = trees
	var planted := false
	for t in trees:
		if t.size() > 3 and t[3] is Dictionary and t[3].has("planted"):
			planted = true
			break
	for c in _chunks_of(trees):
		if not _owners.has(c):
			_owners[c] = {}
		_owners[c][key] = true
		_dirty[c] = true
		_records.erase(c)
		if planted:
			_growing[c] = true
	version += 1


func remove(key: String) -> void:
	if _trees.has(key):
		_unfile(key)
		_trees.erase(key)
		version += 1


func _unfile(key: String) -> void:
	for c in _chunks_of(_trees.get(key, [])):
		_owners[c].erase(key)
		_dirty[c] = true
		_records.erase(c)


static func _chunks_of(trees: Array) -> Dictionary:
	var out := {}
	for t in trees:
		var o: Vector3 = t[0].origin
		out[Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))] = true
	return out


func _enter_tree() -> void:
	fields.append(self)
	version += 1


func _exit_tree() -> void:
	fields.erase(self)
	version += 1


func _process(_delta: float) -> void:
	if not _dirty.is_empty():
		_rebuild()
	var cam := get_viewport().get_camera_3d()
	if cam:
		TreeLook.set_eye(cam.global_position)
		_show_versions(global_transform.affine_inverse() * cam.global_position)
	# Once a game day the planted trees grow on, a few chunks a frame.
	var day := now_tick / REGROW_TICKS
	if day != _last_regrow and not _growing.is_empty():
		_last_regrow = day
		_regrow = _growing.keys()
	if not _regrow.is_empty():
		var t := Perf.now()
		while not _regrow.is_empty() and (Perf.now() - t) < REGROW_MS * 1000.0:
			_rebuild_chunk(_regrow.pop_back())
		version += 1
		Perf.add("frame.trees", t)


func _rebuild() -> void:
	var t := Perf.now()
	for c in _dirty:
		_rebuild_chunk(c)
	_dirty.clear()
	Perf.add("frame.trees", t)


## How a tree stands now: [transform scaled to its size today, species,
## tint, age in years, seed, grows up close]. The same for every player:
## from the tree's facts, where it stands in the region and the game's
## clock only. `world` is the field's own transform (a neighbor's city is
## drawn moved over to its place), for the seed.
static func resolve(t: Array, world := Transform3D.IDENTITY) -> Array:
	var xf: Transform3D = t[0]
	var sp: int = t[1]
	var facts: Dictionary = t[3] if t.size() > 3 and t[3] is Dictionary else {}
	var size := xf.basis.get_scale().y
	var age: float
	if facts.has("planted"):
		var start := maxf(float(facts.get("start", 0.0)), TreeKinds.nursery_age(sp))
		age = maxf(start + extra_years + float(now_tick - int(facts.planted)) / float(REGROW_TICKS * 12), start)
		var now := size * TreeKinds.size_at(sp, age)
		xf = Transform3D(xf.basis.scaled(Vector3.ONE * (now / maxf(size, 0.001))), xf.origin)
	elif facts.has("age"):
		age = float(facts.age)
	else:
		age = TreeKinds.age_for_size(sp, size)
	return [xf, sp, t[2], age, seed_of(world * xf.origin), not facts.has("shrub")]


## Yard trees in a new neighbourhood start already grown (Nathan,
## 2026-10-29: "A. Yes, back-yard trees start grown; street trees still
## start small and grow"), at the mixed ages of an established Indiana
## street: about one in seven a young tree (nursery stock to 14 years),
## most 15 to 40 years, and about one in eight a big old one (45 to 75).
## Street trees are the town's and go in as nursery stock.
const YARD_YOUNG := 0.14
const YARD_OLD := 0.88
const YARD_AGES := [14.0, 15.0, 40.0, 45.0, 75.0]


## How old a yard tree of kind `sp` is the day its yard is finished, from
## `seed` (a whole number from the lot's own seed: the same lot always gets
## the same trees). `room`: how big the crown may grow, as a share of the
## size its planter gave it (the size at TreeKinds.REF_AGE): a tree with
## no room to spread past that (a wall, a pool, the next tree or the lot
## line near) is kept young enough to fit. Whole-number maths for the
## pick, so every computer agrees.
static func yard_age(sp: int, seed: int, room := 1.0) -> float:
	var u := float(posmod(seed, 1000003)) / 1000003.0
	var v := float(posmod(seed / 1000003, 997)) / 997.0
	var young := TreeKinds.nursery_age(sp)
	var age: float
	if u < YARD_YOUNG:
		age = lerpf(young, YARD_AGES[0], v)
	elif u < YARD_OLD:
		age = lerpf(YARD_AGES[1], YARD_AGES[2], v)
	else:
		age = lerpf(YARD_AGES[3], YARD_AGES[4], v)
	# No older than the crown has room for.
	if room < TreeKinds.size_at(sp, age):
		age = TreeKinds.age_for_size(sp, room)
	return maxf(age, young)


## A tree's seed: from where it stands in the region (a view position plus
## Terrain.view_origin), so the same spot always grows the same tree for
## every player, wherever their own town sits. Rounded to the metre: two
## players' positions for one tree can differ in their last digits.
static func seed_of(view_pos: Vector3) -> int:
	return seed_at(region_of(view_pos))


static func seed_at(region: Vector2) -> int:
	return hash(Vector2i(roundi(region.x), roundi(region.y)))


## A view position (what's drawn, relative to your own town) in region
## coordinates (Terrain).
static func region_of(view_pos: Vector3) -> Vector2:
	return Vector2(float(view_pos.x) + float(Terrain.view_origin.x), float(view_pos.z) + float(Terrain.view_origin.y))


func _rebuild_chunk(c: Vector2i) -> void:
	_records.erase(c)
	var groups := {}  # species -> Array of resolved trees in this chunk
	for key in _owners.get(c, {}):
		for t in _trees[key]:
			var o: Vector3 = t[0].origin
			if Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK)) != c:
				continue
			var r := resolve(t)
			if not groups.has(r[1]):
				groups[r[1]] = []
			groups[r[1]].append(r)
	if _owners.has(c) and _owners[c].is_empty():
		_owners.erase(c)
		_growing.erase(c)
	var centre := Vector3((c.x + 0.5) * CHUNK, 0, (c.y + 0.5) * CHUNK)
	for sp in Species.size():
		var g := "%d,%d,%d" % [c.x, c.y, sp]
		var list: Array = groups.get(sp, [])
		for far in [false, true]:
			if list.is_empty():
				var key: String = g + ("f" if far else "n")
				if _multis.has(key):
					_multis[key].multimesh.instance_count = 0
				continue
			var multi := _chunk(g, sp, far, centre).multimesh
			multi.instance_count = list.size()
			for i in list.size():
				var xf: Transform3D = list[i][0]
				multi.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
				multi.set_instance_color(i, Color.WHITE)
				# Alpha carries the species (for the season colours) and
				# whether a grown tree takes over up close.
				multi.set_instance_custom_data(i, custom_of(list[i][2], sp, list[i][5]))


## Each chunk draws only the versions some of its trees are drawn at: the
## full cards while any tree in it is nearer than TreeLook.card_near, the
## light ones while any is farther than the hand-over (the shaders choose
## tree by tree). A wild chunk past WildView's reach draws neither: the far
## woods have it. `eye` is the camera in this field's space.
func _show_versions(eye: Vector3) -> void:
	var near_d := TreeLook.card_near()
	var reach := TreeLook.wild_fade.z if fades and TreeLook.wild_fade.z > 0.0 else INF
	var at := Vector4(eye.x, eye.y, eye.z, near_d + reach * 0.001)
	var moved := Vector3(at.x, at.y, at.z).distance_to(Vector3(_shown_at.x, _shown_at.y, _shown_at.z))
	if moved < SHOW_MOVE and is_equal_approx(at.w, _shown_at.w) and _shown.size() == _versions.size():
		return
	_shown_at = at
	var e := Vector2(eye.x, eye.z)
	var inv := global_transform.affine_inverse()
	var fc3 := inv * Vector3(TreeLook.wild_fade.x, 0.0, TreeLook.wild_fade.y)
	for c in _versions:
		var mask := chunk_versions(c, e, eye.y, near_d, Vector2(fc3.x, fc3.z), reach)
		if int(_shown.get(c, -1)) == mask:
			continue
		_shown[c] = mask
		for mmi in _versions[c][0]:
			mmi.visible = (mask & 1) != 0
		for mmi in _versions[c][1]:
			mmi.visible = (mask & 2) != 0


## Which versions chunk `c` draws (1 full, 2 light) for a camera at `e`
## (across the ground) and `eye_y` high: see _show_versions. Trees stand
## within a few tens of metres of the ground's middle height, so the
## camera's height plus that slack bounds how far off a tree can be.
static func chunk_versions(c: Vector2i, e: Vector2, eye_y: float, near_d: float, fade_centre: Vector2, reach: float) -> int:
	var lo := Vector2(c) * CHUNK
	var hi := lo + Vector2(CHUNK, CHUNK)
	var dmin := e.distance_to(e.clamp(lo, hi))
	var corner := Vector2(maxf(absf(e.x - lo.x), absf(e.x - hi.x)), maxf(absf(e.y - lo.y), absf(e.y - hi.y)))
	var dmax := sqrt(corner.length_squared() + pow(absf(eye_y) + 120.0, 2.0))
	var mask := 0
	if dmin < near_d + SHOW_MOVE + 1.0:
		mask |= 1
	if dmax > near_d - TreeLook.LIGHT_BAND - SHOW_MOVE - 1.0:
		mask |= 2
	# The cards hand over to the far woods by 0.97 of the reach, each tree
	# up to 0.15 of it sooner or later (TreeLook's KEEP_GLSL).
	if reach < INF and fade_centre.distance_to(fade_centre.clamp(lo, hi)) > reach * 1.12 + SHOW_MOVE + 1.0:
		mask = 0
	return mask


## Instance custom data: rgb the leaf tint, alpha the species and whether
## the tree grows up close (see TreeLook's shaders).
static func custom_of(tint: Color, sp: int, grows: bool) -> Color:
	var c := tint
	c.a = (float(sp + (0 if grows else 16)) + 0.5) / 32.0
	return c


## The chunks holding trees within `r` (across the ground) of a point in
## world space.
func chunks_near(p: Vector3, r: float) -> Array:
	var out := []
	if _owners.is_empty():
		return out
	var lp := global_transform.affine_inverse() * p
	var lo := Vector2i(floori((lp.x - r) / CHUNK), floori((lp.z - r) / CHUNK))
	var hi := Vector2i(floori((lp.x + r) / CHUNK), floori((lp.z + r) / CHUNK))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			if _owners.has(Vector2i(x, z)):
				out.append(Vector2i(x, z))
	return out


## Every tree standing in a chunk, as set, in this field's space. Worked
## out when first asked and kept until the chunk changes.
func chunk_trees(c: Vector2i) -> Array:
	_check_records()
	if _records.has(c):
		return _records[c][0]
	var out := []
	for key in _owners.get(c, {}):
		for t in _trees[key]:
			var o: Vector3 = t[0].origin
			if Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK)) == c:
				out.append(t)
	var resolved := []
	resolved.resize(out.size())
	_records[c] = [out, resolved]
	return out


## One of those trees resolved (see resolve), kept likewise. GrownTrees
## reads them one at a time, so a big chunk never stalls a frame.
func chunk_record(c: Vector2i, i: int) -> Array:
	_check_records()
	if not _records.has(c):
		chunk_trees(c)
	var r: Array = _records[c][1]
	if i >= r.size():
		return []  # the chunk changed under the reader; it looks again
	if r[i] == null:
		r[i] = resolve(_records[c][0][i], global_transform)
	return r[i]


## The kept records carry seeds from where the field stands in the region:
## if it moves (or the view's origin does), they are worked out again.
func _check_records() -> void:
	var at := [global_transform, Terrain.view_origin]
	if at != _records_at:
		_records_at = at
		_records.clear()


## The MultiMesh for one species in one chunk, near or far. The node sits at
## the chunk centre so its visibility range is measured from there.
func _chunk(g: String, sp: int, far: bool, centre: Vector3) -> MultiMeshInstance3D:
	var key := g + ("f" if far else "n")
	if _multis.has(key):
		return _multis[key]
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# White instance colours: the browser's renderer multiplies vertex COLOR
	# by the instance colour even without use_colors, and that is black.
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = tree_mesh(sp, far, fades)
	mmi.multimesh = mm
	mmi.position = centre
	add_child(mmi)
	_multis[key] = mmi
	var c := Vector2i(floori(centre.x / CHUNK), floori(centre.z / CHUNK))
	if not _versions.has(c):
		_versions[c] = [[], []]
	_versions[c][1 if far else 0].append(mmi)
	_shown.erase(c)
	_fit(key, mmi)
	return mmi


func _ready() -> void:
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(func():
			for key in _multis:
				_fit(key, _multis[key]))


## The wild woods' full trees cast shadows only on tiers that afford them;
## their distant light trees never (their shadows would cost more than they
## show). Which version draws where is the shaders' (TreeLook).
func _fit(key: String, mmi: MultiMeshInstance3D) -> void:
	_shown_at = Vector4(INF, INF, INF, INF)
	if not fades:
		return
	if key.ends_with("f"):
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GraphicsQuality.tree_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Picks a species and colour for a yard tree: mostly maples (sugar and
## the fast silver maple of 1950s to 70s yards), white and red oaks, honey
## locust, spruce, and crabapples by the house. One random draw for the
## kind, so planters' random sequences stay the same.
static func pick(rng: RandomNumberGenerator, front := false) -> Array:
	var r := rng.randf()
	var sp: int
	if front and r < 0.2:
		sp = Species.CRABAPPLE
	elif r < 0.42:
		sp = Species.MAPLE
	elif r < 0.55:
		sp = Species.SILVER_MAPLE
	elif r < 0.63:
		sp = Species.OAK
	elif r < 0.72:
		sp = Species.RED_OAK
	elif r < 0.86:
		sp = Species.LOCUST
	else:
		sp = Species.SPRUCE
	var tint: Color = LEAF[sp]
	tint = tint.lightened(rng.randf_range(-0.08, 0.1)) if rng.randf() < 0.5 else tint.darkened(rng.randf_range(0.0, 0.12))
	return [sp, tint]


## Picks a species and colour for a street tree in the parkway: the shade
## trees Indiana towns plant along their streets (Purdue's and the Indiana
## DNR's street tree lists): sugar maple, honey locust, red and white oak,
## and a few of the old fast silver maples. No spruce or crabapple, which
## block drivers' view or stay too small. Only kinds the yards already
## grow, so a block's trees still cost the same few draw calls. The same
## number of draws as pick().
static func pick_street(rng: RandomNumberGenerator) -> Array:
	var r := rng.randf()
	var sp: int
	if r < 0.32:
		sp = Species.MAPLE
	elif r < 0.43:
		sp = Species.SILVER_MAPLE
	elif r < 0.69:
		sp = Species.LOCUST
	elif r < 0.88:
		sp = Species.RED_OAK
	else:
		sp = Species.OAK
	var tint: Color = LEAF[sp]
	tint = tint.lightened(rng.randf_range(-0.08, 0.1)) if rng.randf() < 0.5 else tint.darkened(rng.randf_range(0.0, 0.12))
	return [sp, tint]


# ---------------------------------------------------------------- meshes

## The mesh for a species; `far` is the light version for distant chunks.
## `mode` is the distance band (TreeLook): 0 the usual cheap tree, 4 or 5
## one standing in near the camera for a grown tree that isn't built yet.
static func tree_mesh(sp: int, far := false, fades := false, mode := 0) -> ArrayMesh:
	var key := "%d,%s,%s,%d" % [sp, far, fades, mode]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + sp
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	if TreeKinds.kind(sp).evergreen:
		_conifer(sp, rng, leaves, wood, far)
	else:
		_broadleaf(sp, rng, leaves, wood, far)
	var mesh := ArrayMesh.new()
	if far:
		# The light version's few big cards spill wider than the full
		# crown: fitted to the full one's box, so the hand-over between them
		# doesn't swell or shrink the tree.
		leaves = _fitted(leaves, crown_bounds(sp), _leaf_bounds(leaves))
		# Far off a trunk is a few pixels of grey-brown: it rides in the
		# leaf surface (marked by UV.x < 0, drawn plain by the leaf shader),
		# so a distant chunk of woods costs one draw call per species, not two.
		var bark: Array = wood.commit_to_arrays()
		var v: PackedVector3Array = bark[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = bark[Mesh.ARRAY_NORMAL]
		for i in v.size():
			leaves.set_color(Color(0.5, 0.2, 0.0))
			leaves.set_uv(Vector2(-1.0, -1.0))
			leaves.set_normal(n[i] if i < n.size() else Vector3.UP)
			leaves.add_vertex(v[i])
	leaves.commit(mesh)
	mesh.surface_set_material(0, _leaf_material(fades, mode, far))
	if not far:
		wood.commit(mesh)
		mesh.surface_set_material(1, _bark_material(fades, mode))
	_meshes[key] = mesh
	return mesh


static var _crowns := {}


## The box round a kind's full card crown (its leaves, at full size: the
## size at TreeKinds.REF_AGE), which its light version and FarWoods'
## stand-in are fitted to.
static func crown_bounds(sp: int) -> AABB:
	if not _crowns.has(sp):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + sp
		var leaves := SurfaceTool.new()
		leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wood := SurfaceTool.new()
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)
		if TreeKinds.kind(sp).evergreen:
			_conifer(sp, rng, leaves, wood, false)
		else:
			_broadleaf(sp, rng, leaves, wood, false)
		_crowns[sp] = _leaf_bounds(leaves)
	return _crowns[sp]


static func _leaf_bounds(st: SurfaceTool) -> AABB:
	var v: PackedVector3Array = st.commit_to_arrays()[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## The leaves moved and scaled from box `from` into box `to` (across the
## ground about the trunk, up and down between top and bottom).
static func _fitted(st: SurfaceTool, to: AABB, from: AABB) -> SurfaceTool:
	var a: Array = st.commit_to_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var half_to := maxf(maxf(absf(to.position.x), absf(to.end.x)), maxf(absf(to.position.z), absf(to.end.z)))
	var half_from := maxf(maxf(absf(from.position.x), absf(from.end.x)), maxf(absf(from.position.z), absf(from.end.z)))
	var k := half_to / maxf(half_from, 0.01)
	var ky := to.size.y / maxf(from.size.y, 0.01)
	var out := SurfaceTool.new()
	out.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		out.set_color(col[i])
		out.set_uv(uv[i])
		out.set_normal(n[i])
		out.add_vertex(Vector3(v[i].x * k, to.position.y + (v[i].y - from.position.y) * ky, v[i].z * k))
	return out


## A broadleaf crown: clusters of cards filling the kind's crown shape
## (TreeGrower.crown_profile) at its real size at TreeKinds.REF_AGE, on a
## trunk forking into a few big limbs where the crown begins.
static func _broadleaf(sp: int, rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool, far := false) -> void:
	var age := TreeKinds.REF_AGE
	var h := TreeKinds.height(sp, age)
	var base := TreeKinds.crown_base(sp, age)
	var r := h * TreeKinds.wide_at(sp, age) * 0.5
	var center := Vector3(0, (base + h) * 0.5, 0)
	var rad := Vector3(r, (h - base) * 0.5, r)
	var clusters := clampi(int(r * (h - base) / 4.5), 8, 18)
	var card := clampf(r * 0.5, 1.8, 3.4)
	var trunk := TreeKinds.dbh(sp, age) * 0.006
	var fork := minf(base + (h - base) * 0.15, base + 2.0)
	_limb(wood, Vector3.ZERO, Vector3(0, fork, 0), trunk, trunk * 0.8)
	var cards_per := 6 if TreeKinds.kind(sp).leaf == TreeKinds.Leaf.COMPOUND else 7
	if far:
		# A few big cards keep the crown's outline and colour at a distance.
		clusters = maxi(clusters / 2, 5)
		cards_per = 3
		card *= 1.9
	var made := 0
	var guard := 0
	while made < clusters and guard < 400:
		guard += 1
		var p := Vector3(rng.randf_range(-1, 1) * r, rng.randf_range(base, h), rng.randf_range(-1, 1) * r)
		var t := (p.y - base) / maxf(h - base, 0.1)
		if Vector2(p.x, p.z).length() > r * TreeGrower.crown_profile(sp, t) * 0.8:
			continue
		var cc := p.lerp(center, 0.15)
		if not far and made % 3 == 0:
			_limb(wood, Vector3(0, fork, 0), cc.lerp(center, 0.3), trunk * 0.6, trunk * 0.2)
		made += 1
		var hue := rng.randf()
		for i in cards_per:
			var q := cc + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.7), rng.randf_range(-1, 1)) * card * 0.6
			_card(leaves, rng, q, center, rad, card * rng.randf_range(0.8, 1.2), hue, Vector2(base, h), far)


## A conifer: tiers of cards round a straight stem, wide at the bottom
## (spruce cone, red cedar's narrow spire).
static func _conifer(sp: int, rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool, far := false) -> void:
	var age := TreeKinds.REF_AGE
	var h := TreeKinds.height(sp, age)
	var base_r := h * TreeKinds.wide_at(sp, age) * 0.5
	var low := TreeKinds.crown_base(sp, age)
	_limb(wood, Vector3.ZERO, Vector3(0, h, 0), TreeKinds.dbh(sp, age) * 0.006, 0.04)
	var tiers := 6 if far else 11
	for t in tiers:
		var f := float(t) / tiers
		var y := low + 0.6 + f * (h - low - 1.0)
		var r := base_r * TreeGrower.crown_profile(sp, f) + 0.3
		var n := int(3 + r * (1.0 if far else 2.0))
		var hue := rng.randf() * 0.4
		for i in n:
			var a := TAU * (i + rng.randf()) / n
			var p := Vector3(cos(a) * r * rng.randf_range(0.45, 0.8), y, sin(a) * r * rng.randf_range(0.45, 0.8))
			var size := (1.6 + r * 0.45) * (1.5 if far else 1.0)
			_card(leaves, rng, p, Vector3(0, y + 0.8, 0), Vector3(r + 0.5, 1.5, r + 0.5), size, hue, Vector2(low, h), far)


## One leaf card, randomly turned, with normals out from the crown centre.
## Its colour carries what the leaf shader shades it by, as a grown tree's
## cards do (TreeMesher): how far out in the crown (r), how high up the
## crown, `span` its bottom and top (g), and the cluster's own hue (b), so
## the cards and the grown tree at the same spot are lit alike.
static func _card(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, center: Vector3, rad: Vector3, size: float, hue: float,
		span: Vector2, far := false) -> void:
	var basis := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
	var u := basis.x * size * 0.5
	var v := basis.y * size * 0.5
	var corners := [p - u - v, p + u - v, p + u + v, p - u + v]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = corners[i]
		var rel := (q - center) / rad
		var out := (rel + Vector3(0, 0.35, 0)).normalized()
		st.set_normal(out)
		# How far out in the crown: inner leaves are shaded by outer ones.
		var up := clampf((q.y - span.x) / maxf(span.y - span.x, 0.1), 0.0, 1.0)
		st.set_color(Color(clampf(rel.length(), 0.0, 1.0), up, hue, 0.5 if far else 1.0))
		st.set_uv(uvs[i])
		st.add_vertex(q)


## A tapered six-sided branch from a to b.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var up := side.cross(axis)
	var n := 6
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var quad := [[a + d0 * r0, d0, Vector2(float(i) / n, 0)], [a + d1 * r0, d1, Vector2(float(i + 1) / n, 0)],
			[b + d1 * r1, d1, Vector2(float(i + 1) / n, 1)], [b + d0 * r1, d0, Vector2(float(i) / n, 1)]]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


static var _leaf_mats := {}
static var _bark_mats := {}


static func _leaf_material(fades := false, mode := 0, light := false) -> ShaderMaterial:
	var key := "%s,%d,%s" % [fades, mode, light]
	if not _leaf_mats.has(key):
		_leaf_mats[key] = TreeLook.card_material(TreeLook.LEAF_SHADER, mode, fades, leaf_texture(), twig_texture(), light)
	return _leaf_mats[key]


static func _bark_material(fades := false, mode := 0) -> ShaderMaterial:
	var key := "%s,%d" % [fades, mode]
	if not _bark_mats.has(key):
		_bark_mats[key] = TreeLook.card_material(TreeLook.CARD_BARK_SHADER, mode, fades, null, null)
	return _bark_mats[key]


## A square of overlapping leaves on transparency, drawn once at start-up.
static func leaf_texture() -> ImageTexture:
	if _leaf_tex:
		return _leaf_tex
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Leaves thin out toward the edge, so a card's outline is ragged.
	for k in 380:
		var c := Vector2(rng.randf_range(10, size - 10), rng.randf_range(10, size - 10))
		if (c - Vector2(size, size) * 0.5).length() > size * rng.randf_range(0.3, 0.52):
			continue
		var ang := rng.randf_range(0, TAU)
		var len := rng.randf_range(8.0, 13.0)
		var wid := len * rng.randf_range(0.45, 0.6)
		var shade := rng.randf_range(0.62, 1.0)
		var dir := Vector2(cos(ang), sin(ang))
		for y in range(int(c.y - len), int(c.y + len) + 1):
			for x in range(int(c.x - len), int(c.x + len) + 1):
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var d := Vector2(x, y) - c
				var along := d.dot(dir) / len
				var across := d.dot(Vector2(-dir.y, dir.x)) / wid
				if along * along + across * across <= 1.0:
					# Lighter toward the tip on the sunny side, a faint midrib.
					var l := shade * (0.88 + 0.12 * along) * (0.9 if absf(across) < 0.08 else 1.0)
					img.set_pixel(x, y, Color(l, l, l, 1.0))
	img.generate_mipmaps()
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex


## Bare winter twigs on transparency: a few limbs branch outward from near
## the middle, forking and thinning to fine twigs at the edge.
static func twig_texture() -> ImageTexture:
	if _twig_tex:
		return _twig_tex
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var stack := []
	for k in 7:
		var a := rng.randf_range(0, TAU)
		var start := Vector2(size, size) * 0.5 + Vector2(cos(a), sin(a)) * rng.randf_range(0, 30)
		stack.append([start, a + rng.randf_range(-0.4, 0.4), 34.0, 2.4])
	while not stack.is_empty():
		var br: Array = stack.pop_back()
		var p: Vector2 = br[0]
		var ang: float = br[1]
		var len: float = br[2]
		var w: float = br[3]
		var e := p + Vector2(cos(ang), sin(ang)) * len
		var steps := int(len * 2.0)
		for i in steps + 1:
			var q := p.lerp(e, float(i) / steps)
			var r := int(ceil(w))
			for y in range(int(q.y) - r, int(q.y) + r + 1):
				for x in range(int(q.x) - r, int(q.x) + r + 1):
					if x < 0 or y < 0 or x >= size or y >= size:
						continue
					if Vector2(x, y).distance_to(q) <= w * 0.5 + 0.35:
						var l := rng.randf_range(0.8, 1.0)
						img.set_pixel(x, y, Color(l, l * 0.97, l * 0.94, 1.0))
		if len > 6.0 and (e - Vector2(size, size) * 0.5).length() < size * 0.48:
			for f in 2 + (1 if rng.randf() < 0.4 else 0):
				stack.append([e, ang + rng.randf_range(-0.75, 0.75), len * rng.randf_range(0.6, 0.78), maxf(w * 0.7, 1.0)])
	img.generate_mipmaps()
	_twig_tex = ImageTexture.create_from_image(img)
	return _twig_tex
