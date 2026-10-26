class_name GrownTrees
extends Node3D
## The trees near the camera, grown branch by branch (TreeGrower) instead
## of TreeField's leaf-card clumps: the full tree out to TreeLook's NEAR,
## a light one (big limbs, clustered leaves) out to MID, and TreeField's
## cards past that. Every TreeField in the scene is read, so yard, street,
## park and wild trees all grow the same way.
##
## A grown tree's mesh comes from its kind, a variant (from its seed, the
## same for both levels so the handover between them doesn't jump) and its
## age rounded to a bucket (BUCKETS); each mesh is made once and kept (up
## to MAX_MESHES, least recently drawn dropped first). Until a tree's mesh
## is ready its card tree stands in. The exact size between buckets comes
## from scaling, so a tree keeps growing smoothly with the game's clock.
##
## Making a mesh (growing the branches, cutting them to an age, building the
## bark and leaves) runs on worker threads on the desktop, or in slices on
## the main thread (the browser), each slice a few hundred microseconds,
## BUILD_MS a frame in all (less in the browser). Which trees are near is
## looked up a tree at a time (SCAN_MS a frame) as the camera moves; while the
## lookup lags behind the camera the bands trail it a little (zone_point),
## so nothing is ever left undrawn and no tree flips back and forth.

## Ages (years) a mesh is grown at.
const BUCKETS := [2.0, 4.0, 6.0, 9.0, 13.0, 18.0, 25.0, 33.0, 43.0, 56.0, 72.0, 92.0, 120.0]
## How far the camera may move before the trees are looked up again, and
## the slack each looked-up set carries.
const MARGIN := 30.0
const RESCAN := 10.0
## How far the bands' centre may trail the camera behind a lagging lookup.
const ZONE_SLACK := MARGIN - 2.0
## How far ahead of a moving camera a lookup may be aimed (m): where the
## camera will be when it lands.
const LEAD_MAX := 80.0
## The main thread's time a frame for making meshes and for the lookup
## (milliseconds): the desktop's, then the browser's, which is tighter (the
## browser has one thread, and its frames are the ones that can't spare it).
const BUILD_MS := 1.5
const SCAN_MS := 0.75
const BUILD_MS_BROWSER := 1.0
const SCAN_MS_BROWSER := 0.5
## Records looked at between clock checks.
const SCAN_BATCH := 16
const MAX_MESHES := 260
## Meshes drawn in the last lookup (or made since) are kept past
## MAX_MESHES, so a view needing more than that doesn't drop and rebuild
## its own meshes over and over; never past this many.
const HARD_MAX := 520

## Labs and tests can switch the grown trees off (the cheap cards then
## draw everywhere, as before).
static var enabled := true
## Labs can build on the main thread, a slice a frame, as the browser does.
static var threads_ok := true

var _growers := {}  # grower key (sp * 4 + variant) -> TreeGrower (finished or growing)
var _painters := {}  # sp -> TreeLook.LeafPainter
var _meshes := {}  # mesh key -> ArrayMesh
var _used := {}  # mesh key -> frame last drawn (or made)
var _tris := {}  # mesh key -> triangles
var _bytes := {}  # mesh key -> graphics memory, roughly
var _want := {}  # mesh key -> nearest distance it is wanted at
var _groups := {}  # mesh key (>= 0) or card group (< 0) -> MultiMeshInstance3D
var _centre := Vector3(INF, INF, INF)
var _version := -1
var _frame := 0
var _drawn_frame := 0  # the frame the last lookup finished
var _shown := 0
## The main thread's time in the last frame (ms), for the labs.
var last_ms := 0.0
# The main-thread build in hand (the browser).
var _job := -1
var _cut: TreeGrower.AgeCut
var _mesher: TreeMesher
var _part_mesh: ArrayMesh
# The lookup in progress.
var _scan := []  # [field, chunk] pairs still to look at
var _scan_field: TreeField
var _scan_chunk := Vector2i.ZERO
var _scan_n := 0  # trees in the chunk in hand
var _scan_i := 0
var _scan_world := Transform3D.IDENTITY
var _scan_plain := true
var _scan_pos := Vector3.ZERO
var _scan_r := Vector2.ZERO
var _scan_version := -1
var _scanning := false
var _scan_began := 0  # when the lookup in hand began (Time msec)
var _scan_secs := 0.0  # how long the last lookup took
var _last_cp := Vector3(INF, INF, INF)
var _vel := Vector3.ZERO  # the camera's speed, smoothed
var _bufs := {}  # group key -> PackedFloat32Array
var _counts := {}  # group key -> instances
var _threads := false
var _max_tasks := 1
var _grow_tasks := {}  # grower key -> task id
var _mesh_tasks := {}  # mesh key -> {id, parts when done}
var _specks := []
var _speck_frames := 0


func _ready() -> void:
	top_level = true
	_threads = threads_ok and not OS.has_feature("web") and OS.get_processor_count() > 2
	_max_tasks = clampi(OS.get_processor_count() / 3, 1, 4)
	# The growth curves and tables are worked out once here, before any
	# thread reads them.
	for sp in TreeKinds.count():
		TreeKinds.height(sp, 1.0)
		TreeKinds.age_for_size(sp, 1.0)
	bucket(1.0)
	_warm_shaders()


## The bark and leaf shaders are made ready now, behind the loading screen,
## rather than the first time a grown tree comes into view (a stall of a
## few hundred milliseconds): a speck of each, drawn the way the grown
## trees are, just in front of the camera for the first few frames.
func _warm_shaders() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for lod in 2:
		var m := speck_mesh(0, lod)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Not under this node, which hides while no grown trees are drawn.
		get_tree().root.add_child.call_deferred(mmi)
		_specks.append(mmi)


## A speck of a mesh (one tiny triangle of bark, one of leaf) with the
## materials of a grown tree of this kind and level: making it gets the
## shaders and materials ready.
static func speck_mesh(sp: int, lod: int) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(0.01, 0, 0), Vector3(0, 0.01, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	TreeMesher.add_part(m, sp, lod, [arrays, arrays], 0)
	TreeMesher.add_part(m, sp, lod, [arrays, arrays], 1)
	return m


## Keeps the specks in front of the camera (too small to see) until they
## have been drawn for a second or so, then lets them go.
func _place_specks(cam: Camera3D) -> void:
	_speck_frames += 1
	for s in _specks:
		if _speck_frames > 60:
			s.queue_free()
		elif cam and s.is_inside_tree():
			# Just past the near plane, and a tenth of a pixel across.
			var d := cam.near * 1.5 + 0.1
			s.global_transform = Transform3D(cam.global_basis.scaled(Vector3.ONE * d * 0.02), cam.global_position - cam.global_basis.z * d)
	if _speck_frames > 60:
		_specks.clear()


func _exit_tree() -> void:
	for gk in _grow_tasks:
		WorkerThreadPool.wait_for_task_completion(_grow_tasks[gk])
	for key in _mesh_tasks:
		WorkerThreadPool.wait_for_task_completion(_mesh_tasks[key].id)
	_grow_tasks.clear()
	_mesh_tasks.clear()
	for s in _specks:
		if is_instance_valid(s):
			s.queue_free()
	_specks.clear()
	TreeLook.set_zone(Vector3.ZERO, 0.0, 0.0, false)


func _process(delta: float) -> void:
	var t := Perf.now()
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	if not _specks.is_empty():
		_place_specks(cam)
	var r := TreeLook.radii()
	# Nothing to see without a screen (servers, tests).
	if DisplayServer.get_name() == "headless":
		r = Vector2.ZERO
	if not enabled or cam == null or r.y <= 0.0:
		if visible:
			visible = false
			TreeLook.set_zone(Vector3.ZERO, 0.0, 0.0, false)
		last_ms = 0.0
		return
	visible = true
	var cp := cam.global_position
	# The camera's speed, for aiming lookups (a jump across the map is not
	# a speed).
	if _last_cp.x < INF and delta > 0.0 and cp.distance_to(_last_cp) < 300.0:
		_vel = _vel.lerp((cp - _last_cp) / delta, 0.25)
	else:
		_vel = Vector3.ZERO
	_last_cp = cp
	if not _scanning and (cp.distance_to(_centre) > RESCAN or TreeField.version != _version or r != _scan_r):
		_start_scan(scan_point(cp, _vel, _scan_secs), r)
	var budgets := budgets_for(TreeLook.browser())
	if _scanning:
		_scan_some(budgets.y)
	# The bands are measured from a point that follows the camera but stays
	# within reach of where the trees were last looked up (each lookup files
	# MARGIN of slack round its bands), so every tree in a band is filed
	# there however far the lookup lags behind a fast camera: the hand-over
	# rings trail the camera a little instead of every grown tree turning
	# back into a card until the lookup catches up (they flickered between
	# the two while the camera moved).
	if _centre.x == INF:
		TreeLook.set_zone(cp, 0.0, 0.0, false)
	else:
		TreeLook.set_zone(zone_point(cp, _centre), _scan_r.x, _scan_r.y, true)
	_build_some(budgets.x)
	Perf.add("frame.trees.grown", t)
	Perf.counts["trees.grown"] = _shown
	last_ms = (Perf.now() - t) / 1000.0


## Where a lookup is centred: where the moving camera will be when it lands
## (it takes about as long as the last one), so the bands can stay on the
## camera instead of trailing it and catching up in jumps.
static func scan_point(cam: Vector3, vel: Vector3, secs: float) -> Vector3:
	return cam + (vel * secs).limit_length(LEAD_MAX)


## Where the bands are measured from: the camera, or as near it as stays
## within ZONE_SLACK of the last lookup's centre (every tree in a band
## measured from there is filed: a lookup files MARGIN round its bands).
static func zone_point(cam: Vector3, centre: Vector3) -> Vector3:
	if cam.distance_to(centre) <= ZONE_SLACK:
		return cam
	return centre + (cam - centre).normalized() * ZONE_SLACK


## True when the trees round the camera are looked up and every grown mesh
## they need is made (nothing to wait for without a screen).
func is_drawn() -> bool:
	if not enabled or DisplayServer.get_name() == "headless" or TreeLook.radii().y <= 0.0:
		return true
	return _frame > 1 and not _scanning and _want.is_empty() and _version == TreeField.version and _centre.x < INF


## [build, lookup] milliseconds a frame the grown trees may use on the main
## thread: tighter in the browser.
static func budgets_for(browser: bool) -> Vector2:
	if LoadGate.loading:
		return Vector2(LoadGate.ms(0.0), LoadGate.ms(0.0))
	return Vector2(BUILD_MS_BROWSER, SCAN_MS_BROWSER) if browser else Vector2(BUILD_MS, SCAN_MS)


# ------------------------------------------------------------------ lookup

func _start_scan(cp: Vector3, r: Vector2) -> void:
	_scanning = true
	_scan_began = Time.get_ticks_msec()
	_scan_pos = cp
	_scan_r = r
	_scan_version = TreeField.version
	_scan = []
	_scan_field = null
	_scan_n = 0
	_scan_i = 0
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


## Looks at the trees near the camera, a batch of trees at a time, for up
## to `ms` milliseconds; picks up where it left off next frame.
func _scan_some(ms: float) -> void:
	var start := Perf.now()
	var budget := int(ms * 1000.0)
	var near_hi := _scan_r.x + MARGIN
	var near_lo := _scan_r.x - MARGIN - TreeLook.BAND
	var reach := _scan_r.y + MARGIN
	while true:
		if _scan_field == null or not is_instance_valid(_scan_field) or _scan_i >= _scan_n:
			_scan_field = null
			if _scan.is_empty():
				break
			var job: Array = _scan.pop_back()
			# Its chunk of woods may have been dropped since the lookup began.
			if not is_instance_valid(job[0]):
				continue
			_scan_field = job[0]
			_scan_chunk = job[1]
			_scan_world = _scan_field.global_transform
			_scan_plain = _scan_world.is_equal_approx(Transform3D.IDENTITY)
			_scan_n = _scan_field.chunk_trees(_scan_chunk).size()
			_scan_i = 0
		else:
			var end := mini(_scan_i + SCAN_BATCH, _scan_n)
			while _scan_i < end:
				var rec := _scan_field.chunk_record(_scan_chunk, _scan_i)
				_scan_i += 1
				if rec.is_empty() or not rec[5]:
					continue  # brush stays a card
				var xf: Transform3D = rec[0]
				if not _scan_plain:
					xf = _scan_world * xf
				var d := xf.origin.distance_to(_scan_pos)
				if d > reach:
					continue
				if d < near_hi and _scan_r.x > 0.0:
					_file(rec, xf, d, TreeMesher.Lod.FULL)
				if d > near_lo:
					_file(rec, xf, d, TreeMesher.Lod.LIGHT)
		if Perf.now() - start > budget:
			return
	# New groups are made first, one at a time (a kind's first card mesh
	# takes a moment to build); then every group changes in the same frame.
	for group in _bufs:
		if not _groups.has(group) and (group < 0 or _meshes.has(group)):
			_group(group)
			if Perf.now() - start > budget:
				return
	_finish_scan()


## Files one tree into its group: its grown mesh if made, else (asking for
## it to be made) its card standing in.
func _file(rec: Array, xf: Transform3D, d: float, lod: int) -> void:
	var sp: int = rec[1]
	var b := bucket(rec[3])
	var key := mesh_key(sp, posmod(int(rec[4]), TreeGrower.VARIANTS), b, lod)
	var size := xf.basis.get_scale().y
	var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
	var group := key
	var basis: Basis
	if _meshes.has(key):
		var s := size / bucket_size(sp, b)
		basis = Basis(Vector3.UP, -yaw).scaled(Vector3.ONE * s)
	else:
		# Its card stands in, in this band only, until the mesh is made.
		_want[key] = minf(_want.get(key, INF), d)
		group = card_group(sp, lod)
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
	_scan_secs = (Time.get_ticks_msec() - _scan_began) / 1000.0
	_scan_field = null
	_centre = _scan_pos
	_version = _scan_version
	_drawn_frame = _frame
	var shown := 0
	for key in _groups:
		if not _bufs.has(key):
			_groups[key].multimesh.instance_count = 0
	for group in _bufs:
		if group >= 0 and not _meshes.has(group):
			continue  # dropped from the cache while this lookup ran
		var mmi := _group(group)
		var n: int = _counts[group]
		mmi.multimesh.instance_count = n
		mmi.multimesh.buffer = _bufs[group]
		if group >= 0:
			_used[group] = _frame
			shown += n
	_shown = shown
	_bufs = {}


func _group(group: int) -> MultiMeshInstance3D:
	if _groups.has(group):
		return _groups[group]
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	if group < 0:
		var g := -1 - group
		mm.mesh = TreeField.tree_mesh(g >> 1, false, false, 4 if (g & 1) == TreeMesher.Lod.FULL else 5)
	else:
		mm.mesh = _meshes[group]
	_groups[group] = mmi
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GraphicsQuality.tree_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static var _bounds := PackedFloat64Array()
static var _bucket_sizes := PackedFloat64Array()


## The bucket an age rounds to: the nearest grown age, judged by ratio
## (5 years is nearer 6 than 4). Looked up against the middles between
## buckets, worked out once.
static func bucket(age: float) -> int:
	if _bounds.is_empty():
		for i in BUCKETS.size() - 1:
			_bounds.append(sqrt(float(BUCKETS[i]) * float(BUCKETS[i + 1])))
	return _bounds.bsearch(maxf(age, 0.5))


## A kind's size (TreeKinds.size_at) at a bucket's age, worked out once.
static func bucket_size(sp: int, b: int) -> float:
	if _bucket_sizes.is_empty():
		for k in TreeKinds.count():
			for i in BUCKETS.size():
				_bucket_sizes.append(TreeKinds.size_at(k, BUCKETS[i]))
	return _bucket_sizes[sp * BUCKETS.size() + b]


## A mesh's key: kind, variant, age bucket and level packed in one number.
static func mesh_key(sp: int, variant: int, b: int, lod: int) -> int:
	return (sp << 7) | (variant << 5) | (b << 1) | lod


## The group of card trees standing in for one kind at one level (below 0,
## so it never meets a mesh key).
static func card_group(sp: int, lod: int) -> int:
	return -1 - (sp * 2 + lod)


static func _key_sp(key: int) -> int:
	return key >> 7


static func _key_variant(key: int) -> int:
	return (key >> 5) & 3


static func _key_bucket(key: int) -> int:
	return (key >> 1) & 15


static func _key_lod(key: int) -> int:
	return key & 1


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
		if _job < 0:
			var best := _nearest_wanted()
			if best < 0:
				break
			_job = best
			_cut = null
			_mesher = null
			_part_mesh = null
		var left := budget - (Perf.now() - start)
		if _step_job(_job, left):
			_want.erase(_job)
			_job = -1
			made = true
	if made:
		_trim()
		_version = -1  # look again, to draw the new meshes


func _nearest_wanted() -> int:
	var best := -1
	for key in _want.keys():
		if _meshes.has(key):
			_want.erase(key)
		elif best < 0 or _want[key] < _want[best]:
			best = key
	return best


## Worker threads grow the branches and build the meshes; the main thread
## only paints leaf textures (a slice at a time) and hands finished meshes
## to the graphics card, within the frame's budget.
func _build_threaded(ms: float) -> void:
	var start := Perf.now()
	var budget := int(ms * 1000.0)
	var made := false
	for gk in _grow_tasks.keys():
		if WorkerThreadPool.is_task_completed(_grow_tasks[gk]):
			WorkerThreadPool.wait_for_task_completion(_grow_tasks[gk])
			_grow_tasks.erase(gk)
	for key in _mesh_tasks.keys():
		if Perf.now() - start > budget:
			break
		var t: Dictionary = _mesh_tasks[key]
		if not WorkerThreadPool.is_task_completed(t.id):
			continue
		WorkerThreadPool.wait_for_task_completion(t.id)
		_mesh_tasks.erase(key)
		if t.has("parts"):
			_store(key, TreeMesher.to_mesh(_key_sp(key), _key_lod(key), t.parts), t.parts)
			_want.erase(key)
			made = true
	if _tasks() < _task_cap() and not _want.is_empty():
		var keys := _want.keys()
		keys.sort_custom(func(a, b): return _want[a] < _want[b])
		for key in keys:
			if _tasks() >= _task_cap() or (Perf.now() - start) > budget:
				break
			if _meshes.has(key) or _mesh_tasks.has(key):
				continue
			var sp := _key_sp(key)
			if not TreeLook.has_texture(sp):
				if not _painters.has(sp):
					_painters[sp] = TreeLook.LeafPainter.new(sp)
				if _painters[sp].step(budget - (Perf.now() - start)):
					_painters.erase(sp)
				break
			var variant := _key_variant(key)
			var gk := sp * 4 + variant
			if not _growers.has(gk):
				var g := TreeGrower.new(sp, variant)
				_growers[gk] = g
				_grow_tasks[gk] = WorkerThreadPool.add_task(func(): g.step(1_000_000_000), false, "grow tree")
				continue
			var grower: TreeGrower = _growers[gk]
			if not grower.done or _grow_tasks.has(gk):
				continue
			var job := {}
			var age: float = BUCKETS[_key_bucket(key)]
			var lod := _key_lod(key)
			job.id = WorkerThreadPool.add_task(func():
				job.parts = TreeMesher.build(sp, grower.at_age(age), lod, variant), false, "tree mesh")
			_mesh_tasks[key] = job
	if made:
		_trim()
		_version = -1  # look again, to draw the new meshes


## Worker tasks at once: nearly every core while the loading screen is up.
func _task_cap() -> int:
	return clampi(OS.get_processor_count() - 1, _max_tasks, 8) if LoadGate.loading else _max_tasks


func _tasks() -> int:
	return _grow_tasks.size() + _mesh_tasks.size()


## One slice of the job. True when its mesh is made. Each step here is
## small: the leaf texture, the branches over the kind's whole life, the
## tree at this age, its bark and leaves, then the two halves of the mesh
## handed to the graphics card one at a time.
func _step_job(key: int, budget_us: int) -> bool:
	var sp := _key_sp(key)
	var variant := _key_variant(key)
	var lod := _key_lod(key)
	if not TreeLook.has_texture(sp):
		if not _painters.has(sp):
			_painters[sp] = TreeLook.LeafPainter.new(sp)
		if _painters[sp].step(budget_us):
			_painters.erase(sp)
		return false
	var gk := sp * 4 + variant
	if not _growers.has(gk):
		_growers[gk] = TreeGrower.new(sp, variant)
		return false
	var g: TreeGrower = _growers[gk]
	if not g.done:
		g.step(budget_us)
		return false
	if _cut == null:
		_cut = TreeGrower.AgeCut.new(g, BUCKETS[_key_bucket(key)])
		return false
	if _mesher == null:
		if _cut.step(budget_us):
			_mesher = TreeMesher.new(sp, _cut.tree, lod, variant)
		return false
	if not _mesher.done:
		_mesher.step(budget_us)
		return false
	if _part_mesh == null:
		_part_mesh = ArrayMesh.new()
		TreeMesher.add_part(_part_mesh, sp, lod, _mesher.parts, 0)
		return false
	TreeMesher.add_part(_part_mesh, sp, lod, _mesher.parts, 1)
	_store(key, _part_mesh, _mesher.parts)
	_cut = null
	_mesher = null
	_part_mesh = null
	return true


## Keeps a made mesh, as just used (so the cache doesn't drop it before it
## is ever drawn), with its size for the labs.
func _store(key: int, mesh: ArrayMesh, parts: Array) -> void:
	_meshes[key] = mesh
	_used[key] = _frame
	var tris := 0
	var bytes := 0
	for s in parts:
		if s.is_empty():
			continue
		var verts := (s[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var idx := (s[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		tris += idx / 3
		# Compressed vertices (16-bit position, normal and UV, 8-bit
		# colour: about 20 bytes) and 4-byte indices.
		bytes += verts * 20 + idx * 4
	_tris[key] = tris
	_bytes[key] = bytes


## Keeps the cache to MAX_MESHES: the meshes drawn longest ago go first.
## Ones the last lookup drew, or made since, stay (up to HARD_MAX).
func _trim() -> void:
	if _meshes.size() <= MAX_MESHES:
		return
	var keys := _meshes.keys()
	keys.sort_custom(func(a, b): return int(_used.get(a, 0)) < int(_used.get(b, 0)))
	var drop := _meshes.size() - MAX_MESHES
	var must := _meshes.size() - HARD_MAX
	for key in keys:
		if drop <= 0:
			break
		if int(_used.get(key, 0)) >= _drawn_frame and must <= 0:
			break  # in view: keep it
		if _groups.has(key):
			_groups[key].queue_free()
			_groups.erase(key)
		_meshes.erase(key)
		_used.erase(key)
		_tris.erase(key)
		_bytes.erase(key)
		drop -= 1
		must -= 1


## For the labs: how many meshes are kept, how many trees are drawn grown,
## from numbers kept as the meshes were made (nothing read back from the
## graphics card).
func stats() -> Dictionary:
	var tris := 0
	for key in _groups:
		if key < 0:
			continue
		tris += int(_tris.get(key, 0)) * (_groups[key] as MultiMeshInstance3D).multimesh.instance_count
	var bytes := 0
	for key in _bytes:
		bytes += int(_bytes[key])
	var nodes := 0
	for gk in _growers:
		nodes += (_growers[gk] as TreeGrower).pos.size()
	return {"meshes": _meshes.size(), "grown": _shown, "pending": _want.size(), "tris": tris,
		"groups": _groups.size(), "skeletons": _growers.size(), "mesh_mb": snappedf(bytes / 1048576.0, 0.1),
		"skeleton_kb": nodes * 41 / 1024}
