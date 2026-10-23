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
## Above this height the wild trees are gone (faded out by then): the
## painted canopy carries the woods.
const TREES_OFF := 1750.0
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


## Redraws the chunks in a box (view coordinates): the land there was
## regraded, so verges may have been mowed or let go.
func regraded(box: Rect2) -> void:
	var size := Vegetation.CHUNK
	for x in range(floori(box.position.x / size), floori(box.end.x / size) + 1):
		for z in range(floori(box.position.y / size), floori(box.end.y / size) + 1):
			if _chunks.has(Vector2i(x, z)):
				_stale[Vector2i(x, z)] = true


func _process(_delta: float) -> void:
	if sim == null:
		return
	# Building while paused still clears the trees right away.
	sim.vegetation.update(sim)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var height := maxf(cam.global_position.y - Terrain.ground_y(cam.global_position.x, cam.global_position.z), 1.0)
	# Lower graphics tiers draw the woods less far; the ground's painted
	# canopy carries on past them.
	var radius := reach(height) * clampf(GraphicsQuality.detail, 0.6, 1.0)
	var focus := _ground_focus(cam, radius)
	# Trees thin out and shrink toward the edge (TreeField's shader), where
	# the ground's painted canopy takes over.
	# w is the camera's height: from high up the trees fade out and the
	# ground's painted canopy covers the woods (TreeField and TerrainView).
	RenderingServer.global_shader_parameter_set("tree_fade", Vector4(focus.x, focus.y, radius, height))
	if height > TREES_OFF:
		for c in _chunks:
			_chunks[c].queue_free()
		_chunks.clear()
		_detail.clear()
		_stale.clear()
		return
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
		field.fades = true
		add_child(field)
		_chunks[c] = field
	# Roads the town doesn't own (a neighbor's, the county highways out to
	# the horizon) keep their mowed verges clear too.
	var mowed := Terrain.any_mowed(Rect2(Vector2(c) * size, Vector2(size, size)))
	var trees := []
	for p in plants:
		if mowed and Terrain.mow_weight(p.pos.x, p.pos.z) > 0.5:
			continue
		trees.append([placement(p), p.species, p.tint])
	_chunks[c].set_trees("wild", trees)
	_shade.append(_chunks[c])


## How far out wild plants are drawn for a camera this high.
static func reach(height: float) -> float:
	return clampf(height * 3.0, MIN_RADIUS, MAX_RADIUS)


## Where and how big a plant is drawn: standing on the land.
static func placement(p: Dictionary) -> Transform3D:
	var pos: Vector3 = p.pos
	pos.y += Terrain.ground_y(pos.x, pos.z)
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


## The centre of the trees drawn: from the camera toward where it looks, but
## never more than part of the reach ahead, so a low, flat view doesn't
## swing it far off (and reload everything) with each small move.
func _ground_focus(cam: Camera3D, radius: float) -> Vector2:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.001:
		return Vector2(from.x, from.z)
	var height := maxf(from.y - Terrain.ground_y(from.x, from.z), 1.0)
	var ahead := radius * 0.45
	if dir.y < -0.05:
		ahead = minf(height / -dir.y * flat.length(), ahead)
	return Vector2(from.x, from.z) + flat.normalized() * ahead
