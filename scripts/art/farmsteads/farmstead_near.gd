class_name FarmsteadNear
extends Node3D
## County farmsteads close to the camera, grown in full from the same plan
## as their far version (FarmsteadPlan, FarmsteadFar): the farmhouse from
## the house builder's plan book, the barn, bins, sheds, silo and windmill
## in the town's own materials (FarmBuilder), the gravel draped over the
## land, and the windbreak and shade trees as real trees (TreeField, so the
## trees code grows them). Detail by distance:
##   - trees within TREE_R of the camera (about 0.9 km on desktop High)
##   - buildings within BUILD_R (about 0.3 km), at most a few farmsteads
## Both radii scale with the quality tier; the browser gets less of each.
## A close-up is built a step a frame within BUDGET_MS, then the far
## version dithers out over FADE_S while the close-up stands in its place
## (same frame, same sizes), so nothing pops and no frame freezes.
##
## The far drawing's shader has FarmsteadFar.SPOTS slots for handed-over
## farmsteads. A close-up always holds a slot (so its far version is hidden);
## when they are all taken, a nearer farmstead takes the farthest one's, and
## that close-up goes the same frame its far version comes back.

const BUILD_R := 220.0
const TREE_R := 650.0
## Farmsteads built close up at once (desktop, browser), and with trees.
const MAX_BUILT := 4
const MAX_BUILT_WEB := 2
const MAX_TREES := 12
const FADE_S := 0.5
const BUDGET_MS := 2.0
## Leave a farmstead's close-up only this much past its radius.
const SLACK := 1.15

## Off: no close-ups at all (the far version everywhere).
static var off := false

var _field: TreeField
var _built := {}  # key -> {"plan", "node", "fade", "want"}
var _trees := {}  # key -> {"plan", "fade", "want"}
var _job := {}  # {"key", "plan", "b": FarmBuilder, "i"}
var _pools := {}  # lamp colour -> ShaderMaterial
static var _pool_shader: Shader
var _origin := Vector2.INF
## Built so far, and the slowest step (ms), for the bench.
var built_count := 0
var worst_step_ms := 0.0
var worst_step := ""


func _ready() -> void:
	_field = TreeField.new()
	add_child(_field)
	# Make the materials now, while the game loads: making a shader takes
	# tens of ms, a stutter if the first close-up did it.
	for m in ["siding", "roof", "glass", "metal", "paint", "brick", "yard", "pasture", "foliage"]:
		HouseMaterials.get_mat(m)
	for lamp in FarmsteadPlan.LAMPS:
		_pool(lamp)
	FarmsteadFar.material()
	FarmsteadFar.glow_material()


## The shared far material outlives this node (it is a static): leave it
## with no farmstead handed over.
func _exit_tree() -> void:
	FarmsteadFar.clear_spots()
	FarmsteadPlan.pinned = {}


## The pool of light a yard lamp throws (StreetLights' pool, in the lamp's
## colour), one shader for all of them.
func _pool(lamp: Color) -> ShaderMaterial:
	var key := lamp.to_html()
	if not _pools.has(key):
		if _pool_shader == null:
			_pool_shader = Shader.new()
			_pool_shader.code = StreetLights.POOL_SHADER
		var m := ShaderMaterial.new()
		m.shader = _pool_shader
		m.set_shader_parameter("lamp", lamp)
		_pools[key] = m
	return _pools[key]


static func reach_scale() -> float:
	var s := clampf(GraphicsQuality.detail, 0.5, 2.0)
	return s * (0.6 if FarmsteadFar.web() else 1.0)


## Each frame: `places` are [plan, anchor (view Vector3)] near the camera.
func update(cam: Vector3, places: Array, origin: Vector2, delta: float) -> void:
	if origin != _origin:
		_origin = origin
		_drop_all()
	var scale := reach_scale()
	var build_r := BUILD_R * scale
	var tree_r := TREE_R * scale
	var max_built := MAX_BUILT_WEB if FarmsteadFar.web() else MAX_BUILT
	var near := []
	for pl in places:
		var d := cam.distance_to(pl[1])
		if d < tree_r * SLACK:
			near.append([d, pl[0], pl[1]])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in _trees:
		_trees[k].want = false
	for k in _built:
		_built[k].want = false
	var n_trees := 0
	var n_built := 0
	for e in near:
		var p: Dictionary = e[1]
		var key := Vector2i(int(p.at.x), int(p.at.y))
		var d: float = e[0]
		var have_t := _trees.has(key)
		var have_b := _built.has(key)
		var want_t := n_trees < MAX_TREES and (d < tree_r or (have_t and d < tree_r * SLACK))
		var want_b := not off and n_built < max_built and (d < build_r or (have_b and d < build_r * SLACK))
		if not (want_t or want_b):
			continue
		if not (have_t or have_b) and not _make_room(cam, Vector2(cam.x, cam.z).distance_to(p.at - _origin)):
			continue
		if want_t:
			n_trees += 1
			if not have_t:
				_add_trees(key, p)
			_trees[key].want = true
		if want_b:
			n_built += 1
			if have_b:
				_built[key].want = true
			elif _job.is_empty():
				_job = {"key": key, "plan": p, "b": FarmBuilder.county(p), "i": 0}
	# A job for a farmstead no longer wanted is dropped.
	if not _job.is_empty():
		var still := false
		for e in near:
			if e[0] < build_r * SLACK and Vector2i(int(e[1].at.x), int(e[1].at.y)) == _job.key:
				still = true
		if not still or off:
			_job = {}
	_work()
	var step := delta / FADE_S
	for k in _trees.keys():
		var t: Dictionary = _trees[k]
		t.fade = clampf(t.fade + (step if t.want else -step), 0.0, 1.0)
		if not t.want and t.fade <= 0.0:
			_field.remove(str(k))
			_trees.erase(k)
	for k in _built.keys():
		var b: Dictionary = _built[k]
		b.fade = clampf(b.fade + (step if b.want else -step), 0.0, 1.0)
		if not b.want and b.fade <= 0.0:
			b.node.queue_free()
			_built.erase(k)
	# A close-up finished this frame may have gone past the slots there are.
	while _slots() > FarmsteadFar.SPOTS:
		_drop(_farthest(cam))
	_publish()


## The farmsteads with a close-up of any kind (each holds one of the far
## shader's slots).
func _keys() -> Dictionary:
	var keys := {}
	for k in _built:
		keys[k] = true
	for k in _trees:
		keys[k] = true
	return keys


func _slots() -> int:
	return _keys().size()


func _plan_of(k: Vector2i) -> Dictionary:
	return (_built[k] if _built.has(k) else _trees[k]).plan


## Metres on the ground from the camera to a farmstead with a close-up.
func _dist(cam: Vector3, k: Vector2i) -> float:
	return Vector2(cam.x, cam.z).distance_to(_plan_of(k).at - _origin)


func _farthest(cam: Vector3) -> Vector2i:
	var far_k := Vector2i.ZERO
	var far_d := -1.0
	for k in _keys():
		var d := _dist(cam, k)
		if d > far_d:
			far_d = d
			far_k = k
	return far_k


## Frees a slot for a farmstead `d` metres from the camera, if some close-up
## is farther; returns whether one is free.
func _make_room(cam: Vector3, d: float) -> bool:
	if _slots() < FarmsteadFar.SPOTS:
		return true
	var k := _farthest(cam)
	if _dist(cam, k) <= d:
		return false
	_drop(k)
	return true


## Removes a farmstead's close-up at once (its far version is back this frame).
func _drop(k: Vector2i) -> void:
	if _trees.has(k):
		_field.remove(str(k))
		_trees.erase(k)
	if _built.has(k):
		_built[k].node.queue_free()
		_built.erase(k)
	if not _job.is_empty() and _job.key == k:
		_job = {}


## Builds the current close-up a step at a time, within the frame's budget.
func _work() -> void:
	if _job.is_empty():
		return
	var start := Time.get_ticks_usec()
	var b: FarmBuilder = _job.b
	var n := b.steps()
	while _job.i <= n:
		var t := Time.get_ticks_usec()
		if _job.i < n:
			b.step(_job.i)
		else:
			_finish(_job.key, _job.plan, b.commit())
		var took := (Time.get_ticks_usec() - t) / 1000.0
		if took > worst_step_ms:
			worst_step_ms = took
			worst_step = "commit" if _job.i >= n else ("house" if _job.i == 0 else ("ground" if _job.i == 1 else
				str(_job.plan.parts[_job.i - 2].kind)))
		_job.i += 1
		if (Time.get_ticks_usec() - start) / 1000.0 > BUDGET_MS:
			break
	if _job.i > n:
		_job = {}


func _finish(key: Vector2i, p: Dictionary, meshes: Array) -> void:
	var node := Node3D.new()
	node.transform = FarmsteadPlan.frame(p, _origin, Terrain.height(p.at.x, p.at.y))
	for i in meshes.size():
		var mesh: ArrayMesh = meshes[i]
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if i > 0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # the ground work
		node.add_child(mi)
	if not p.light.is_empty():
		_lamp(node, p)
	var base := Terrain.height(p.at.x, p.at.y)
	FarmsteadParked.add_to(node, p, FarmsteadParked.month, func(q: Vector2) -> float:
		var r := FarmsteadPlan.to_region(p, q)
		return Terrain.height(r.x, r.y) - base)
	add_child(node)
	_built[key] = {"plan": p, "node": node, "fade": 0.0, "want": true}
	built_count += 1


## The yard light at night: the lamp's glow and its pool on the yard.
func _lamp(node: Node3D, p: Dictionary) -> void:
	var at: Vector2 = p.light.pos
	var lift := Terrain.height(FarmsteadPlan.to_region(p, at).x, FarmsteadPlan.to_region(p, at).y) - Terrain.height(p.at.x, p.at.y)
	var lamp: Color = p.light.col
	var head := Vector3(at.x, lift + float(p.light.h) - 0.15, at.y - 1.4)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for k in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
		v.append(head)
		c.append(lamp)
		uv.append(k)
		uv2.append(Vector2(1e8, 1e8))  # never handed over
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	var glow := ArrayMesh.new()
	glow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	glow.surface_set_material(0, FarmsteadFar.glow_material())
	glow.custom_aabb = AABB(head - Vector3.ONE, Vector3.ONE * 2.0)
	var gi := MeshInstance3D.new()
	gi.mesh = glow
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(gi)
	var quad := QuadMesh.new()
	quad.size = Vector2(22.0, 22.0)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _pool(lamp)
	var pool := MeshInstance3D.new()
	pool.mesh = quad
	pool.position = Vector3(at.x, lift + 0.3, at.y - 1.4)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(pool)


## The windbreak and shade trees as real trees.
func _add_trees(key: Vector2i, p: Dictionary) -> void:
	var list := []
	for t in p.trees:
		var r := FarmsteadPlan.to_region(p, t[0])
		var pos := Vector3(r.x - _origin.x, Terrain.height(r.x, r.y), r.y - _origin.y)
		var sp: int = t[1]
		var s: float = t[2]
		var shape := Vector3.ONE * s
		if sp == FarmsteadPlan.species("RED_CEDAR", -1):
			shape = Vector3(0.55, 0.8, 0.55) * s
		# Turned and tinted from the tree's place in the farmstead (its local
		# point), as the far stand-in is, so the two match at the handover and
		# the same tree looks the same whichever way the view's origin shifts.
		var yaw := FarmsteadPlan.tree_turn(t[0])
		var tint: Color = TreeField.LEAF[sp] if sp < TreeField.LEAF.size() else TreeField.LEAF[0]
		tint = FarmsteadPlan.tree_tint(tint, t[0])
		list.append([Transform3D(Basis(Vector3.UP, yaw).scaled(shape), pos), sp, tint, {"age": t[3]}])
	_field.set_trees(str(key), list)
	_trees[key] = {"plan": p, "fade": 0.0, "want": true}


## Tells the far drawing which farmsteads have handed over, and how far,
## and the plan cache which plans are in use.
func _publish() -> void:
	var spots := []
	var pins := {}
	for k in _keys():
		var p := _plan_of(k)
		var a: Vector2 = p.at - _origin
		var fb: float = _built[k].fade if _built.has(k) else 0.0
		var ft: float = _trees[k].fade if _trees.has(k) else 0.0
		spots.append(Vector4(a.x, a.y, fb, ft))
		pins[FarmsteadPlan.key_of(p)] = true
	if not _job.is_empty():
		pins[FarmsteadPlan.key_of(_job.plan)] = true
	FarmsteadPlan.pinned = pins
	FarmsteadFar.set_spots(spots)


func _drop_all() -> void:
	for k in _built:
		_built[k].node.queue_free()
	for k in _trees:
		_field.remove(str(k))
	_built.clear()
	_trees.clear()
	_job = {}
	FarmsteadFar.clear_spots()
	FarmsteadPlan.pinned = {}
