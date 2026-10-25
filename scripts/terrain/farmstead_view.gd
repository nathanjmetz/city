class_name FarmsteadView
extends Node3D
## The farmsteads and country homes out in the county, where the real land
## cover shows them (terrain/grant_in/farmsteads.bin, from
## tools/terrain/build_roads.py). Scenery like the backdrop towns: nothing in
## them is simulated, and the town's own land clears them, as a farmstead
## is bought out when a town grows over it.
##
## Each place is grown from its few facts into a plan (FarmsteadPlan: the
## farm's kind, size and age, its house, barn, bins, sheds, windbreak, lane,
## yard light and mailbox, by rules from real east-central Indiana
## farmsteads; docs/farmsteads.md). Detail by distance:
##   - far (the whole county): FarmsteadFar, a few hundred triangles a
##     farmstead, one mesh per 2 km block, built a few blocks a frame and
##     rebuilt only where the town's land changes
##   - near the camera: FarmsteadNear, the windbreak as real trees and the
##     buildings in full, grown from the same plan

## Side of a block, metres: one mesh each.
const BLOCK := 2048.0
## Time to spend building blocks each frame, ms.
const BUDGET_MS := 3.0
## Past this the haze has them anyway, metres.
const DRAW_TO := 9000.0

var sim: CitySim
## Block -> Array of [x, z, farm, facing radians, seed] (region metres).
var _places := {}
var _origin := Vector2.INF
var _queue: Array = []
var _meshes := {}  # block -> MeshInstance3D
## Block -> the places drawn in it, with each anchor (view metres), for the close-ups.
var _shown := {}
var _near: FarmsteadNear
## The block being built: {b, i (next place), far (FarmsteadFar), shown, t (ms so far)}.
var _job := {}
## Blocks built so far, and the most time one took in all (ms, over its frames), for the bench.
var blocks_built := 0
var worst_block_ms := 0.0
## The most time this view took in one frame (ms), and its time and frames
## so far (for the mean), for the bench.
var worst_frame_ms := 0.0
var time_ms := 0.0
var frames := 0


func setup(s: CitySim) -> void:
	sim = s
	_near = FarmsteadNear.new()
	add_child(_near)
	_load()
	# Crops and wild trees ask where the yards are; load the places now,
	# while the game loads.
	FarmsteadPlan.covers(Vector2.ZERO)
	# The town's land changed: redraw the blocks it touched.
	if sim != null:
		sim.vegetation.changed.connect(func(chunks: Array) -> void:
			var o := Terrain.view_origin
			for c in chunks:
				var p: Vector2 = (Vector2(c) + Vector2(0.5, 0.5)) * Vegetation.CHUNK + o
				var b := _block(p)
				if _places.has(b) and not b in _queue:
					_queue.append(b)
				if not _job.is_empty() and _job.b == b:
					_job = {})


func _load() -> void:
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "FST1":
		return
	var n := data.decode_u32(4)
	var at := 8
	for i in n:
		var p := Vector2(data.decode_s16(at), data.decode_s16(at + 2))
		var b := _block(p)
		if not _places.has(b):
			_places[b] = []
		_places[b].append([p.x, p.y, data.decode_u8(at + 4) == 1, data.decode_u8(at + 5) / 256.0 * TAU, data.decode_u8(at + 6)])
		at += 7


static func _block(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BLOCK), floori(p.y / BLOCK))


func _process(delta: float) -> void:
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for b in _meshes:
			_meshes[b].queue_free()
		_meshes.clear()
		_shown.clear()
		_job = {}
		_queue = _places.keys()
		# Nearest blocks first, so the land round the camera fills in first.
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var c := Vector2(cam.global_position.x, cam.global_position.z) + _origin
			_queue.sort_custom(func(a, b): return _dist(a, c) > _dist(b, c))
	var start := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - start) / 1000.0 < BUDGET_MS:
		if _job.is_empty():
			if _queue.is_empty():
				break
			_job = {"b": _queue.pop_back(), "i": 0, "t": 0.0}
			_job.far = FarmsteadFar.new(OS.has_feature("web"))
			_job.shown = []
		var t := Time.get_ticks_usec()
		_step_block()
		if not _job.is_empty():
			_job.t += (Time.get_ticks_usec() - t) / 1000.0
	_update_near(delta)
	var spent := (Time.get_ticks_usec() - start) / 1000.0
	worst_frame_ms = maxf(worst_frame_ms, spent)
	time_ms += spent
	frames += 1


static func _dist(b: Vector2i, c: Vector2) -> float:
	return ((Vector2(b) + Vector2(0.5, 0.5)) * BLOCK).distance_squared_to(c)


## The close-ups: the farmsteads drawn in the blocks round the camera.
func _update_near(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _near == null:
		return
	var p := cam.global_position
	var b0 := _block(Vector2(p.x, p.z) + _origin)
	var reach := FarmsteadNear.TREE_R * FarmsteadNear.reach_scale() * FarmsteadNear.SLACK
	var places := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for s in _shown.get(b0 + Vector2i(dx, dz), []):
				if p.distance_to(s[1]) < reach:
					var f: Array = s[0]
					places.append([FarmsteadPlan.of(Vector2(f[0], f[1]), f[2], f[3], f[4]), s[1]])
	_near.update(p, places, _origin, delta)


## Whether the town has built on, or cleared, the land round a place.
func _taken(at: Vector2) -> bool:
	if sim == null:
		return false
	var veg: Vegetation = sim.vegetation
	for d in [Vector2.ZERO, Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
		var c := Vegetation.cell_of(Vector3(at.x + d.x, 0.0, at.y + d.y))
		if veg.is_occupied(c) or veg.cleared.has(c):
			return true
	return false


## Adds the next farmstead of the block being built; draws the block once
## all are in (a block is about 15 farmsteads, a fraction of a ms each).
func _step_block() -> void:
	var b: Vector2i = _job.b
	var list: Array = _places[b]
	var o := _origin
	var centre2 := (Vector2(b) + Vector2(0.5, 0.5)) * BLOCK - o
	var centre := Vector3(centre2.x, 0.0, centre2.y)
	if _job.i < list.size():
		var f: Array = list[_job.i]
		_job.i += 1
		var at := Vector2(f[0], f[1])
		if _taken(at - o):
			return
		var plan := FarmsteadPlan.of(at, f[2], f[3], f[4])
		if FarmsteadPlan.wet(plan):
			return
		_job.far.add(plan, o, centre)
		var a: Vector2 = at - o
		_job.shown.append([f, Vector3(a.x, Terrain.height(at.x, at.y), a.y)])
		return
	if _meshes.has(b):
		_meshes[b].queue_free()
		_meshes.erase(b)
	_shown[b] = _job.shown
	blocks_built += 1
	worst_block_ms = maxf(worst_block_ms, _job.t)
	var mesh: ArrayMesh = _job.far.commit()
	_job = {}
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = centre
	mi.visibility_range_end = DRAW_TO
	add_child(mi)
	_meshes[b] = mi
