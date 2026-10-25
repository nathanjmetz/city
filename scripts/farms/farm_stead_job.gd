class_name FarmSteadJob
extends RefCounted
## Builds one farmstead (house, yard, trees) or one livestock barn group in
## three steps of a few milliseconds, so a farm that grows never freezes a
## frame (FarmView runs one step a frame at most). Nothing shows until the
## last step, which puts the new one in the scene; FarmView then removes
## the old one in the same frame, so there is never a gap.
##   1. the buildings' meshes (FarmBuilder), 2. the yard laid on the land
##   (Terrain.drape_local), 3. into the scene, with the farmhouse's
##   construction stages (ConstructionSite) and its trees.

enum Stage { BUILD, DRAPE, PLACE, DONE }

## The slowest of each step so far (ms), for tools: "home place" -> 5.2.
static var worst := {}

var kind := "home"  # "home" or "barn"
var key: Variant  # a farm's id, or a barn group's key ("id:x:y:kind")
var root: Node3D  # null if the farm went before it was done
var stage := Stage.BUILD

var _parent: Node3D
var _trees: TreeField
var _sim: CitySim
var _id: Variant
var _site := Vector2i.ZERO
var _barn_kind := ""
var _built: Array = []
var _look := 0


## `arg` is the barn group's [farm id, site, kind]; unused for a home.
func _init(parent: Node3D, trees: TreeField, sim: CitySim, what: String, which: Variant, arg := []) -> void:
	_parent = parent
	_trees = trees
	_sim = sim
	kind = what
	key = which
	if kind == "home":
		_id = which
	else:
		_id = arg[0]
		_site = arg[1]
		_barn_kind = arg[2]


## True when the farm is gone, so the job has nothing to build.
func cancelled() -> bool:
	return not _sim.farms.farms.has(_id)


## Does one step (each is 2 to 6 ms, so never two in a frame); true when DONE.
func step() -> bool:
	if cancelled():
		# The farm went while this was being built: nothing to show.
		if root != null and not root.is_inside_tree():
			root.free()
		root = null
		stage = Stage.DONE
		return true
	var t0 := Perf.now()
	var was := stage
	match stage:
		Stage.BUILD:
			_build()
		Stage.DRAPE:
			_built[1] = Terrain.drape_local(_built[1], root.transform)
		Stage.PLACE:
			_place()
	stage = (stage + 1) as Stage
	var ms := (Perf.now() - t0) / 1000.0
	Perf.record("farm_stead.%s" % Stage.keys()[was].to_lower(), ms)
	worst[kind + " " + Stage.keys()[was].to_lower()] = maxf(worst.get(kind + " " + Stage.keys()[was].to_lower(), 0.0), ms)
	return stage == Stage.DONE


func _build() -> void:
	var f: Dictionary = _sim.farms.farms[_id]
	root = Node3D.new()
	var cube := BoxMesh.new()
	if kind == "home":
		_look = FarmView._look(f)
		root.set_meta("look", _look)
		root.set_meta("built", f.get("built", []).size())
		root.position = Vector3(f.pos.x, Terrain.ground_y(f.pos.x, f.pos.z), f.pos.z)
		_built = FarmBuilder.build_farmstead(hash(str(_id)), _look, f.get("built", []))
		cube.size = Vector3(34, 3.0, 38)  # a footing under the yard, for farmsteads on a slope
	else:
		var mid := Livestock.site_center(f, _site)
		root.position = Vector3(mid.x, Terrain.ground_y(mid.x, mid.z), mid.z)
		_built = FarmBuilder.build_barns(_barn_kind, hash(key))
		cube.size = Vector3(78, 3.0, 38)
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	var footing := MeshInstance3D.new()
	footing.mesh = cube
	footing.position = Vector3(0, -1.55, 0)
	footing.material_override = FarmView._footing_mat()
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(footing)


func _place() -> void:
	_parent.add_child(root)
	if kind == "barn":
		var barns := MeshInstance3D.new()
		barns.mesh = _built[0]
		root.add_child(barns)
		var ground := MeshInstance3D.new()
		ground.mesh = _built[1]
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ground)
		return
	var f: Dictionary = _sim.farms.farms[_id]
	# The farmhouse goes up stage by stage (ConstructionSite).
	var ref := "farm:%s" % str(_id)
	var sim := _sim
	ConstructionSite.add_to(root, _built, "house", func(): return sim.construction.state(ref, sim.tick_count),
		func(): pass)
	var xf := Transform3D(root.basis, root.position)
	var planted := []
	for t in _built[2]:
		var at := xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		planted.append([at, t[1], t[2]])
	# Shade trees along the lane, alternating sides, the same every time.
	var drive: Array = f.drive
	var k := 0
	for i in range(2, drive.size() - 2, maxi(2, drive.size() / 4)):
		var a: Vector3 = drive[i]
		var b: Vector3 = drive[i + 1]
		var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * (5.5 if k % 2 == 0 else -5.5)
		var h := Farms._hash01(Vector2i(roundi(a.x), roundi(a.z)), 3)
		var sp: int = TreeField.Species.OAK if h < 0.5 else TreeField.Species.MAPLE
		var size := 0.9 + 0.35 * h
		var spot := a + side
		spot.y = Terrain.ground_y(spot.x, spot.z)
		planted.append([Transform3D(Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * size), spot), sp, TreeField.LEAF[sp]])
		k += 1
	_trees.set_trees(str(_id), planted)
