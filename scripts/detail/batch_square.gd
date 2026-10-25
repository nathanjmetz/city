class_name BatchSquare
extends Node3D
## The full drawing of one 128 m square of town, near enough to the camera
## to need it (BuildingView's middle ring): every finished building in the
## square merged into one mesh per material, so a square of homes is a
## couple of dozen draw calls, not a dozen per house. Kept as plain arrays
## per building while the square is held, so a building that changes is
## swapped in by merging again, without drawing its neighbours again.
##
## It comes in as a short dissolve over the far blocks (FadeMats), and goes
## out the same way when the camera leaves.

const FADE_S := 0.5

var sq := Vector2i.ZERO
## key -> {group: arrays}, each building's surfaces in the square's frame.
var parts := {}
## group -> [Material, casts shadow, lies on the ground]
var _groups := {}
var _labels := {}  # key -> Node3D
var _solid := MeshInstance3D.new()  # walls and roofs: casts shadows
var _flat := MeshInstance3D.new()  # drives, walks, beds, footings: no shadow
## 0 hidden .. 1 shown; where it is heading.
var fade := 0.0
var target := 0.0
var shown := false  # merged at least once
var _fading_mats := []  # [MeshInstance3D, surface, ShaderMaterial] while dissolving


func _init(at: Vector2i, size: float) -> void:
	sq = at
	position = Vector3((at.x + 0.5) * size, 0.0, (at.y + 0.5) * size)
	_solid.mesh = ArrayMesh.new()
	_flat.mesh = ArrayMesh.new()
	_flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_solid)
	add_child(_flat)


## Sets a building's drawing: `solid` (walls and roofs), `flat` (the lot's
## flat work, laid on the land) and `footing` are MeshParts in the
## building's frame, `xf` places that frame in the view, `labels` its
## lettered signs (SignText).
func set_building(key: String, xf: Transform3D, solid: Array, flat: Array, footing: Array, labels: Array) -> void:
	var to_sq := Transform3D(Basis.IDENTITY, -position) * xf
	var mine := {}
	for grp in [[solid, true, false], [flat, false, true], [footing, false, false]]:
		for p in grp[0]:
			var a: Array = p[1]
			if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				continue
			var mat := MeshParts.material(p)
			var g := "%d|%d|%d%d" % [mat.get_instance_id() if mat else 0, MeshParts.format_of(a), int(grp[1]), int(grp[2])]
			if not _groups.has(g):
				_groups[g] = [mat, grp[1], grp[2]]
			var moved := MeshParts.moved(a, to_sq)
			if mine.has(g):
				MeshParts.append(mine[g], moved)
			else:
				mine[g] = MeshParts.copy(moved)
	parts[key] = mine
	if _labels.has(key):
		_labels[key].queue_free()
		_labels.erase(key)
	if not labels.is_empty():
		var n := Node3D.new()
		n.transform = to_sq
		SignText.add(n, labels)
		add_child(n)
		_labels[key] = n


func remove_building(key: String) -> void:
	parts.erase(key)
	if _labels.has(key):
		_labels[key].queue_free()
		_labels.erase(key)


## The groups to merge, for the view to merge one a job.
func group_list() -> Array:
	var used := {}
	for key in parts:
		for g in parts[key]:
			used[g] = true
	return used.keys()


var _next := {"solid": null, "flat": null}


## Starts a new merge: groups are merged one a call (merge_group), and
## the result shown together (finish), so the square never shows half merged.
func begin() -> void:
	_next.solid = ArrayMesh.new()
	_next.flat = ArrayMesh.new()


func merge_group(g: String) -> void:
	var merged := []
	for key in parts:
		var a = parts[key].get(g)
		if a == null:
			continue
		if merged.is_empty():
			merged = MeshParts.copy(a)
		else:
			MeshParts.append(merged, a)
	if merged.is_empty():
		return
	var spec: Array = _groups[g]
	var mesh: ArrayMesh = _next.solid if spec[1] else _next.flat
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	mesh.surface_set_material(mesh.get_surface_count() - 1, spec[0])


## Shows what was merged since begin(); a square seen for the first time
## starts dissolving in.
func finish() -> void:
	_end_fade_mats()
	_solid.mesh = _next.solid
	_flat.mesh = _next.flat
	_next = {"solid": null, "flat": null}
	if not shown:
		shown = true
		fade = 0.0
		target = 1.0
	if fade < 1.0:
		_start_fade_mats()


## Fades towards `target` by `delta` seconds; true when it has arrived.
func step_fade(delta: float) -> bool:
	if fade == target:
		return true
	if _fading_mats.is_empty():
		_start_fade_mats()
	fade = move_toward(fade, target, delta / FADE_S)
	for f in _fading_mats:
		f[2].set_shader_parameter("fade", fade)
	for key in _labels:
		_labels[key].visible = fade > 0.5
	if fade == target:
		if fade >= 1.0:
			_end_fade_mats()
		return true
	return false


func _start_fade_mats() -> void:
	for mi: MeshInstance3D in [_solid, _flat]:
		for i in mi.mesh.get_surface_count():
			var m := FadeMats.fading(mi.mesh.surface_get_material(i))
			if m == null:
				continue
			m.set_shader_parameter("fade", fade)
			mi.set_surface_override_material(i, m)
			_fading_mats.append([mi, i, m])
	for key in _labels:
		_labels[key].visible = fade > 0.5


func _end_fade_mats() -> void:
	for f in _fading_mats:
		if is_instance_valid(f[0]) and f[1] < f[0].get_surface_override_material_count():
			f[0].set_surface_override_material(f[1], null)
	_fading_mats.clear()
	for key in _labels:
		_labels[key].visible = true


## Every vertex of the flat work, in the view's frame (for tests).
func flat_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for key in parts:
		for g in parts[key]:
			if not _groups[g][2]:
				continue
			out.append_array(transform * (parts[key][g][Mesh.ARRAY_VERTEX] as PackedVector3Array))
	return out
