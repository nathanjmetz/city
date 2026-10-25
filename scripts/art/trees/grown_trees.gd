class_name GrownTrees
extends Node3D
## The trees near the camera, grown branch by branch (TreeGrower) instead
## of TreeField's leaf-card clumps: the full tree out to TreeLook's NEAR,
## a light one (big limbs, clustered leaves) out to MID, and TreeField's
## cards past that. Every TreeField in the scene is read, so yard, street,
## park and wild trees all grow the same way.
##
## A grown tree's mesh comes from its kind, a variant (from its seed) and
## its age rounded to a bucket (BUCKETS); each mesh is made once, a slice
## per frame (BUILD_MS), and kept (up to MAX_MESHES, least recently used
## dropped first). Until a tree's mesh is ready its card tree stands in.
## The exact size between buckets comes from scaling, so a tree keeps
## growing smoothly with the game's clock.
##
## Which trees are near is looked up a little at a time (SCAN_MS) as the
## camera moves; the bands shrink while the lookup lags behind the camera,
## so nothing is ever left undrawn.

## Ages (years) a mesh is grown at.
const BUCKETS := [2.0, 4.0, 6.0, 9.0, 13.0, 18.0, 25.0, 33.0, 43.0, 56.0, 72.0, 92.0, 120.0]
## How far the camera may move before the trees are looked up again, and
## the slack each looked-up set carries.
const MARGIN := 30.0
const RESCAN := 10.0
const BUILD_MS := 2.5
const SCAN_MS := 1.5
const MAX_MESHES := 260
## The light trees use fewer variants: at that distance two look as varied
## as three.
const LIGHT_VARIANTS := 2

## Labs and tests can switch the grown trees off (the cheap cards then
## draw everywhere, as before).
static var enabled := true

var _growers := {}  # "sp,variant" -> TreeGrower (finished or growing)
var _painters := {}  # sp -> TreeLook.LeafPainter
var _meshes := {}  # mesh key -> ArrayMesh
var _used := {}  # mesh key -> frame last drawn
var _want := {}  # mesh key -> nearest distance it is wanted at
var _job := ""  # mesh key being built
var _mesher: TreeMesher
var _groups := {}  # mesh key -> MultiMeshInstance3D
var _fallback := {}  # species -> MultiMeshInstance3D (cards inside the zone)
var _centre := Vector3(INF, INF, INF)
var _version := -1
var _frame := 0
var _shown := 0
# The lookup in progress.
var _scan := []  # [field, chunk] pairs still to look at
var _scan_pos := Vector3.ZERO
var _scan_r := Vector2.ZERO
var _scan_version := -1
var _scanning := false
var _bufs := {}  # group key -> PackedFloat32Array
var _counts := {}  # group key -> instances
var _threads := false
var _max_tasks := 1
var _tasks := {}  # mesh key (or "g" + grower key) -> {id, parts when done}


func _ready() -> void:
	top_level = true
	_threads = not OS.has_feature("web") and OS.get_processor_count() > 2
	_max_tasks = clampi(OS.get_processor_count() / 3, 1, 4)
	# The growth curves are worked out once here, before any thread reads them.
	for sp in TreeKinds.count():
		TreeKinds.height(sp, 1.0)


func _exit_tree() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key].id)
	_tasks.clear()
	TreeLook.set_zone(Vector3.ZERO, 0.0, 0.0, false)


func _process(_delta: float) -> void:
	var t := Perf.now()
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var r := TreeLook.radii()
	# Nothing to see without a screen (servers, tests).
	if DisplayServer.get_name() == "headless":
		r = Vector2.ZERO
	if not enabled or cam == null or r.y <= 0.0:
		if visible:
			visible = false
			TreeLook.set_zone(Vector3.ZERO, 0.0, 0.0, false)
		return
	visible = true
	var cp := cam.global_position
	if not _scanning and (cp.distance_to(_centre) > RESCAN or TreeField.version != _version or r != _scan_r):
		_start_scan(cp, r)
	if _scanning:
		_scan_some(SCAN_MS)
	# While the looked-up trees lag behind the camera the bands shrink, so
	# the cards keep drawing anything not looked up yet.
	var lag := cp.distance_to(_centre)
	if lag >= MARGIN or _centre.x == INF:
		TreeLook.set_zone(cp, 0.0, 0.0, false)
	else:
		var near_r := clampf(_scan_r.x, maxf(_scan_r.x - MARGIN + lag, 0.0), _scan_r.x + MARGIN - lag) if _scan_r.x > 0.0 else 0.0
		TreeLook.set_zone(cp, near_r, minf(_scan_r.y, _scan_r.y + MARGIN - lag), true)
	_build_some(BUILD_MS)
	Perf.add("frame.trees.grown", t)
	Perf.counts["trees.grown"] = _shown


# ------------------------------------------------------------------ lookup

func _start_scan(cp: Vector3, r: Vector2) -> void:
	_scanning = true
	_scan_pos = cp
	_scan_r = r
	_scan_version = TreeField.version
	_scan = []
	_bufs = {}
	_counts = {}
	_want = {}
	var reach := r.y + MARGIN
	for f in TreeField.fields:
		var field: TreeField = f
		if not is_instance_valid(field) or not field.is_visible_in_tree():
			continue
		for c in field.chunks_near(cp, reach):
			_scan.append([field, c])


func _scan_some(ms: float) -> void:
	var start := Perf.now()
	var near_hi := _scan_r.x + MARGIN
	var near_lo := _scan_r.x - MARGIN - TreeLook.BAND
	var reach := _scan_r.y + MARGIN
	while not _scan.is_empty():
		var job: Array = _scan.pop_back()
		var field: TreeField = job[0]
		if not is_instance_valid(field):
			continue
		var world := field.global_transform
		var plain := world.is_equal_approx(Transform3D.IDENTITY)
		for rec in field.chunk_records(job[1]):
			if not rec[5]:
				continue  # brush stays a card
			var xf: Transform3D = rec[0]
			if not plain:
				xf = world * xf
			var d := xf.origin.distance_to(_scan_pos)
			if d > reach:
				continue
			if d < near_hi and _scan_r.x > 0.0:
				_file(rec, xf, d, TreeMesher.Lod.FULL)
			if d > near_lo:
				_file(rec, xf, d, TreeMesher.Lod.LIGHT)
		if (Perf.now() - start) > ms * 1000.0:
			return
	_finish_scan()


## Files one tree into its group: its grown mesh if made, else (asking for
## it to be made) its card standing in.
func _file(rec: Array, xf: Transform3D, d: float, lod: int) -> void:
	var sp: int = rec[1]
	var age: float = rec[3]
	var b := bucket(age)
	var variant: int = posmod(int(rec[4]), TreeGrower.VARIANTS if lod == TreeMesher.Lod.FULL else LIGHT_VARIANTS)
	var key := mesh_key(sp, variant, b, lod)
	var size := xf.basis.get_scale().y
	var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
	var group := key
	var basis: Basis
	if _meshes.has(key):
		var s := size / TreeKinds.size_at(sp, BUCKETS[b])
		basis = Basis(Vector3.UP, -yaw).scaled(Vector3.ONE * s)
	else:
		# Its card stands in, in this band only, until the mesh is made.
		_want[key] = minf(_want.get(key, INF), d)
		group = "f%d,%d" % [sp, 4 if lod == TreeMesher.Lod.FULL else 5]
		basis = xf.basis
	var buf: PackedFloat32Array = _bufs.get(group, PackedFloat32Array())
	var custom := TreeField.custom_of(rec[2], sp, true)
	var o := xf.origin
	buf.append_array([basis.x.x, basis.y.x, basis.z.x, o.x, basis.x.y, basis.y.y, basis.z.y, o.y,
		basis.x.z, basis.y.z, basis.z.z, o.z, 1.0, 1.0, 1.0, 1.0, custom.r, custom.g, custom.b, custom.a])
	_bufs[group] = buf
	_counts[group] = int(_counts.get(group, 0)) + 1


func _finish_scan() -> void:
	_scanning = false
	_centre = _scan_pos
	_version = _scan_version
	var shown := 0
	for key in _groups:
		if not _bufs.has(key):
			_groups[key].multimesh.instance_count = 0
	for key in _fallback:
		if not _bufs.has(key):
			_fallback[key].multimesh.instance_count = 0
	for group in _bufs:
		if not group.begins_with("f") and not _meshes.has(group):
			continue  # dropped from the cache while this lookup ran
		var mmi := _group(group)
		var n: int = _counts[group]
		mmi.multimesh.instance_count = n
		mmi.multimesh.buffer = _bufs[group]
		if not group.begins_with("f"):
			_used[group] = _frame
			shown += n
	_shown = shown
	_bufs = {}


func _group(group: String) -> MultiMeshInstance3D:
	var fallback := group.begins_with("f")
	if fallback and _fallback.has(group):
		return _fallback[group]
	if not fallback and _groups.has(group):
		return _groups[group]
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	if fallback:
		var p := group.substr(1).split(",")
		mm.mesh = TreeField.tree_mesh(int(p[0]), false, false, int(p[1]))
		_fallback[group] = mmi
	else:
		mm.mesh = _meshes[group]
		_groups[group] = mmi
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GraphicsQuality.tree_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static func bucket(age: float) -> int:
	var best := 0
	for i in BUCKETS.size():
		if absf(log(maxf(age, 0.5) / BUCKETS[i])) < absf(log(maxf(age, 0.5) / BUCKETS[best])):
			best = i
	return best


static func mesh_key(sp: int, variant: int, b: int, lod: int) -> String:
	return "%d,%d,%d,%d" % [sp, variant, b, lod]


# ---------------------------------------------------------------- building

## Makes the meshes wanted, nearest first: on worker threads where the
## machine has them (the desktop), else a slice at a time on the main
## thread (the browser).
func _build_some(ms: float) -> void:
	if _threads:
		_build_threaded(ms)
		return
	var start := Perf.now()
	var budget := int(ms * 1000.0)
	var made := false
	while (Perf.now() - start) < budget:
		if _job == "":
			if _want.is_empty():
				break
			var best := ""
			for key in _want:
				if not _meshes.has(key) and (best == "" or _want[key] < _want[best]):
					best = key
			if best == "":
				_want.clear()
				break
			_job = best
			_mesher = null
		var left := budget - (Perf.now() - start)
		if _step_job(_job, left):
			_want.erase(_job)
			_job = ""
			made = true
	if made:
		_trim()
		_version = -1  # look again, to draw the new meshes


## Worker threads grow the branches and build the meshes; the main thread
## only paints leaf textures (a slice at a time) and hands finished meshes
## to the graphics card.
func _build_threaded(ms: float) -> void:
	var start := Perf.now()
	var made := false
	for key in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(t.id):
			continue
		WorkerThreadPool.wait_for_task_completion(t.id)
		_tasks.erase(key)
		if t.has("parts"):
			var p: PackedStringArray = key.split(",")
			_meshes[key] = TreeMesher.to_mesh(int(p[0]), int(p[3]), t.parts)
			_want.erase(key)
			made = true
	if _tasks.size() < _max_tasks and not _want.is_empty():
		var keys := _want.keys()
		keys.sort_custom(func(a, b): return _want[a] < _want[b])
		for key in keys:
			if _tasks.size() >= _max_tasks or (Perf.now() - start) > ms * 1000.0:
				break
			if _meshes.has(key) or _tasks.has(key):
				continue
			var p: PackedStringArray = key.split(",")
			var sp := int(p[0])
			if not TreeLook.has_texture(sp):
				if not _painters.has(sp):
					_painters[sp] = TreeLook.LeafPainter.new(sp)
				if _painters[sp].step(int(ms * 1000.0) - (Perf.now() - start)):
					_painters.erase(sp)
				break
			var gk := "%d,%d" % [sp, int(p[1])]
			if not _growers.has(gk):
				var g := TreeGrower.new(sp, int(p[1]))
				_growers[gk] = g
				_tasks["g" + gk] = {"id": WorkerThreadPool.add_task(func(): g.step(1_000_000_000), false, "grow tree")}
				continue
			var grower: TreeGrower = _growers[gk]
			if not grower.done or _tasks.has("g" + gk):
				continue
			var job := {}
			var age: float = BUCKETS[int(p[2])]
			var lod := int(p[3])
			var variant := int(p[1])
			job.id = WorkerThreadPool.add_task(func():
				job.parts = TreeMesher.build(sp, grower.at_age(age), lod, variant), false, "tree mesh")
			_tasks[key] = job
	if made:
		_trim()
		_version = -1  # look again, to draw the new meshes


## One slice of the job. True when its mesh is made.
func _step_job(key: String, budget_us: int) -> bool:
	var p := key.split(",")
	var sp := int(p[0])
	var variant := int(p[1])
	var b := int(p[2])
	var lod := int(p[3])
	# The kind's leaves first, then its branches over its whole life...
	if not TreeLook.has_texture(sp):
		if not _painters.has(sp):
			_painters[sp] = TreeLook.LeafPainter.new(sp)
		if not _painters[sp].step(budget_us):
			return false
		_painters.erase(sp)
		return false
	var gk := "%d,%d" % [sp, variant]
	if not _growers.has(gk):
		_growers[gk] = TreeGrower.new(sp, variant)
		return false
	var g: TreeGrower = _growers[gk]
	if not g.done:
		g.step(budget_us)
		return false
	# ...then the tree at this age, and its mesh.
	if _mesher == null:
		_mesher = TreeMesher.new(sp, g.at_age(BUCKETS[b]), lod, variant)
		return false
	if not _mesher.step(budget_us):
		return false
	_meshes[key] = TreeMesher.to_mesh(sp, lod, _mesher.parts)
	_mesher = null
	return true


## Keeps the cache to MAX_MESHES: the meshes drawn longest ago go first.
func _trim() -> void:
	if _meshes.size() <= MAX_MESHES:
		return
	var keys := _meshes.keys()
	keys.sort_custom(func(a, b): return int(_used.get(a, 0)) < int(_used.get(b, 0)))
	for key in keys.slice(0, _meshes.size() - MAX_MESHES):
		if _groups.has(key):
			_groups[key].queue_free()
			_groups.erase(key)
		_meshes.erase(key)
		_used.erase(key)


## For the labs: how many meshes are kept, how many trees are drawn grown.
func stats() -> Dictionary:
	var tris := 0
	for key in _groups:
		var mmi: MultiMeshInstance3D = _groups[key]
		if mmi.multimesh.instance_count == 0:
			continue
		var m: Mesh = mmi.multimesh.mesh
		var t := 0
		for s in m.get_surface_count():
			t += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += t * mmi.multimesh.instance_count
	# What the kept meshes take on the graphics card: compressed vertices
	# (16-bit position, normal and UV, 8-bit colour: about 20 bytes) and
	# 4-byte indices.
	var bytes := 0
	for key in _meshes:
		var m: ArrayMesh = _meshes[key]
		for s in m.get_surface_count():
			bytes += m.surface_get_array_len(s) * 20 + m.surface_get_array_index_len(s) * 4
	var nodes := 0
	for gk in _growers:
		nodes += (_growers[gk] as TreeGrower).pos.size()
	return {"meshes": _meshes.size(), "grown": _shown, "pending": _want.size(), "tris": tris,
		"groups": _groups.size(), "skeletons": _growers.size(), "mesh_mb": snappedf(bytes / 1048576.0, 0.1),
		"skeleton_kb": nodes * 41 / 1024}
