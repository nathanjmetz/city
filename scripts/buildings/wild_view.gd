class_name WildView
extends Node3D
## Draws the wild trees and brush (Vegetation) around the camera, using the
## art library's TreeField: one TreeField per 256 m chunk, so a change or a
## step of regrowth redraws only its own chunk. Chunks stream in nearest
## first and drop out behind the camera, so an endless map costs the same as
## a small one. Brush uses the small crabapple crown, squat and dull, until
## Art adds proper shrub meshes.

## How far out wild plants are drawn: further when the camera is higher.
const MIN_RADIUS := 700.0
const MAX_RADIUS := 1600.0
## Brush is only drawn this close; past it, it is too small to see.
const DETAIL_RADIUS := 560.0
## Milliseconds a frame may spend laying out new chunks.
const BUDGET_MS := 4
## Land that is growing back is redrawn once a game day (a month of growth).
const REGROW_REDRAW := 24 * 60

var sim: CitySim
var _chunks := {}  # chunk -> TreeField
var _detail := {}  # chunk -> true when drawn with its brush
var _stale := {}  # chunks to redraw
var _shade := []  # fields drawn last frame, whose far trees drop their shadows
var _last_regrow := -1


func setup(s: CitySim) -> void:
	sim = s
	sim.vegetation.changed.connect(func(chunks: Array):
		for c in chunks:
			_stale[c] = true)


func _process(_delta: float) -> void:
	if sim == null:
		return
	# Building while paused still clears the trees right away.
	sim.vegetation.update(sim)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var focus := _ground_focus(cam)
	var radius := clampf(cam.global_position.y * 3.0, MIN_RADIUS, MAX_RADIUS)
	var size := Vegetation.CHUNK
	var day := sim.tick_count / REGROW_REDRAW
	if day != _last_regrow:
		_last_regrow = day
		for c in _chunks:
			if sim.vegetation.growing_in(c, sim.tick_count):
				_stale[c] = true
	# Drop chunks well behind the edge (with some slack so they don't flicker).
	for c in _chunks.keys():
		if _centre(c).distance_to(focus) > radius + size * 1.5:
			_chunks[c].queue_free()
			_chunks.erase(c)
			_detail.erase(c)
			_stale.erase(c)
	var todo := []
	var lo := Vector2i(floori((focus.x - radius) / size), floori((focus.y - radius) / size))
	var hi := Vector2i(floori((focus.x + radius) / size), floori((focus.y + radius) / size))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			var d := _centre(c).distance_to(focus)
			if d > radius + size * 0.7:
				continue
			var near := d < DETAIL_RADIUS
			if not _chunks.has(c) or _stale.has(c) or (near and not _detail.has(c)) or (d > DETAIL_RADIUS + size and _detail.has(c)):
				todo.append(c)
	todo.sort_custom(func(a, b): return _centre(a).distance_squared_to(focus) < _centre(b).distance_squared_to(focus))
	# Distant trees are a few big cards: their shadows would cost more than
	# they show, so only the near trees cast them.
	for field in _shade:
		if is_instance_valid(field):
			for mmi in field.get_children():
				if mmi is GeometryInstance3D and mmi.visibility_range_begin > 0.0:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shade.clear()
	var start := Time.get_ticks_msec()
	for c in todo:
		_draw_chunk(c, _centre(c).distance_to(focus) < DETAIL_RADIUS)
		if Time.get_ticks_msec() - start > BUDGET_MS:
			break


## Lays out one chunk now.
func _draw_chunk(c: Vector2i, detail: bool) -> void:
	_stale.erase(c)
	if detail:
		_detail[c] = true
	else:
		_detail.erase(c)
	var size := Vegetation.CHUNK
	var plants := sim.vegetation.plants_in(Rect2(Vector2(c) * size, Vector2(size, size)), sim.tick_count, detail)
	if not _chunks.has(c):
		var field := TreeField.new()
		add_child(field)
		_chunks[c] = field
	var trees := []
	for p in plants:
		trees.append([placement(p), p.species, p.tint])
	_chunks[c].set_trees("wild", trees)
	_shade.append(_chunks[c])


## Where and how big a plant is drawn.
static func placement(p: Dictionary) -> Transform3D:
	var pos: Vector3 = p.pos
	var s: float = p.size
	var shape := Vector3.ONE * s
	if p.kind == Vegetation.Kind.SHRUB:
		shape = Vector3(0.6, 0.45, 0.6) * s
	elif p.species == TreeField.Species.SPRUCE:
		shape = Vector3(0.55, 0.8, 0.55) * s  # eastern red cedar: a narrow spire
	var yaw := fposmod(pos.x * 7.3 + pos.z * 3.1, TAU)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(shape), pos)


func _centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * Vegetation.CHUNK


## Where the camera's view meets the ground (or below it, looking flat).
func _ground_focus(cam: Camera3D) -> Vector2:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y < -0.05:
		var p := from + dir * (from.y / -dir.y)
		return Vector2(p.x, p.z)
	return Vector2(from.x, from.z)
