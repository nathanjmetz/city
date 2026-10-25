class_name BatchSquare
extends Node3D
## The full drawing of one 128 m square of town, near enough to the camera
## to need it (BuildingView's middle ring): every finished building in the
## square merged into one mesh per material, so a square of homes is a
## couple of dozen draw calls, not a dozen per house. Each building comes in
## as plain arrays (`parts`); once merged they're let go (drop_parts), but
## for the walls and roofs the close-up detail is laid on, so memory holds
## one copy of the square, on the graphics chip. A building that changes
## means fetching its neighbours' arrays again and merging anew.
##
## It can come in as a short dissolve over the far blocks (FadeMats), and go
## out the same way when the camera leaves; `instant` swaps it at once
## instead, as BuildingView does: the swap is hundreds of metres off, where
## the far blocks are the same walls, roofs and windows, and the dissolve's
## shaders each stall a frame the first time they're needed (most in the
## browser).

const FADE_S := 0.5
var instant := false

var sq := Vector2i.ZERO
## key -> {group: arrays}, each building's surfaces in the square's frame,
## while they wait to be merged.
var parts := {}
## key -> [[kind, arrays], ...]: the walls and roofs the close-up detail is
## laid on (NEAR_KINDS), kept after a merge.
var near := {}
## The buildings in the drawing shown now.
var merged := {}
const NEAR_KINDS := ["siding", "brick", "roof"]
## group -> [Material, casts shadow, lies on the ground, HouseMaterials name]
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
				_groups[g] = [mat, grp[1], grp[2], MeshParts.kind(p)]
			var moved := MeshParts.moved(a, to_sq)
			if mine.has(g):
				MeshParts.append(mine[g], moved)
			else:
				mine[g] = MeshParts.copy(moved)
	parts[key] = mine
	var keep := []
	for g in mine:
		if _groups[g][3] in NEAR_KINDS:
			keep.append([_groups[g][3], mine[g]])
	near[key] = keep
	if _labels.has(key):
		_labels[key].queue_free()
		_labels.erase(key)
	if not labels.is_empty():
		var n := Node3D.new()
		n.transform = to_sq
		SignText.add(n, labels)
		add_child(n)
		_labels[key] = n


## A building's surfaces of the given kinds (HouseMaterials names), in the
## square's frame: [[kind, arrays], ...] (for the close-up detail).
func kind_parts(key: String, kinds: Array) -> Array:
	var out := []
	for kp in near.get(key, []):
		if kp[0] in kinds:
			out.append(kp)
	return out


func remove_building(key: String) -> void:
	parts.erase(key)
	near.erase(key)
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
var _todo: Array = []  # groups left to merge
var _g := ""  # the group being merged
var _keys: Array = []  # buildings left to add to it
var _acc := []  # what's merged of it so far


## Starts a new merge: merge_step adds a building's group at a time, and
## the result shows together (finish), so the square never shows half merged.
func begin() -> void:
	_next.solid = ArrayMesh.new()
	_next.flat = ArrayMesh.new()
	_todo = group_list()
	_g = ""


## Merges until `deadline` (Time.get_ticks_usec()); true when it's all merged.
func merge_step(deadline: int) -> bool:
	while Time.get_ticks_usec() < deadline:
		if _g == "":
			if _todo.is_empty():
				return true
			_g = _todo.pop_back()
			_keys = parts.keys()
			_acc = []
			continue
		if not _keys.is_empty():
			var a = parts[_keys.pop_back()].get(_g)
			if a != null:
				if _acc.is_empty():
					_acc = MeshParts.copy(a)
				else:
					MeshParts.append(_acc, a)
			continue
		if not _acc.is_empty():
			var spec: Array = _groups[_g]
			var mesh: ArrayMesh = _next.solid if spec[1] else _next.flat
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _acc)
			mesh.surface_set_material(mesh.get_surface_count() - 1, spec[0])
		_acc = []
		_g = ""
	return _g == "" and _todo.is_empty()


## Lets the merged buildings' arrays go (the walls and roofs for the
## close-up detail stay). Tests that look at what was merged keep them
## (`keep_parts`): a headless run's renderer keeps no mesh to read back.
func drop_parts() -> void:
	if not keep_parts:
		parts.clear()


static var keep_parts := false


## Shows what was merged since begin(); a square seen for the first time
## starts dissolving in.
func finish() -> void:
	merged.clear()
	for key in parts:
		merged[key] = true
	_end_fade_mats()
	_solid.mesh = _next.solid
	_flat.mesh = _next.flat
	_next = {"solid": null, "flat": null}
	if not shown:
		shown = true
		fade = 1.0 if instant else 0.0
		target = 1.0
	if fade < 1.0:
		_start_fade_mats()


## Fades towards `target` by `delta` seconds; true when it has arrived.
func step_fade(delta: float) -> bool:
	if fade == target:
		return true
	if instant:
		fade = target
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
