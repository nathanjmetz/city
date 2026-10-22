class_name FarmTool
extends Node3D
## Farming tools. The Fertility view opens with them, so you can see where
## the soil is rich:
## - Farmhouse (corn or soybeans): place it near good soil, within reach of
##   a road; the farmer picks and buys the best fields around it.
## - Reserve: click to drop nodes around land to save for farming; click the
##   first node (or press Enter) to close it. Roads and zoning stay off it.
## - Clear reserve: the same, to release land.

signal mode_changed(mode: int)
signal hint_changed(text: String)

enum Mode { NONE, RESERVE, CLEAR, CORN, SOYBEANS }

const CLOSE_DIST := 14.0

var sim: CitySim
var cam: CityCamera
var info: InfoView
## What the Reserve tool saves land for.
var reserve_kind := "farm"
var _opened_view := false
var mode := Mode.NONE

var _nodes: Array[Vector3] = []
var _outline := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _line_mat := StandardMaterial3D.new()
var _ghost_ok := false
var _ghost_dir := Vector3.FORWARD
var _hover := Vector3.ZERO
var _problem := ""


func setup(s: CitySim, camera: CityCamera, v: InfoView) -> void:
	sim = s
	cam = camera
	info = v


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.3, 0.75, 1.0, 0.45)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.45)],
			[_line_mat, Color(1.0, 0.9, 0.4, 0.9)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
	_outline.material_override = _line_mat
	for mi in [_outline, _ghost]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)


func set_mode(m: int) -> void:
	mode = m
	_nodes.clear()
	if mode != Mode.NONE and info.mode == InfoView.Mode.NONE:
		info.set_mode(InfoView.Mode.FERTILITY)
		_opened_view = true
	elif mode == Mode.NONE and _opened_view:
		_opened_view = false
		if info.mode == InfoView.Mode.FERTILITY:
			info.set_mode(InfoView.Mode.NONE)
	info.show_reserves = mode != Mode.NONE
	_outline.visible = false
	_ghost.visible = false
	mode_changed.emit(mode)
	_update_hint()


func is_drawing() -> bool:
	return not _nodes.is_empty()


func cancel() -> void:
	_nodes.clear()
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_close()
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		if is_drawing():
			cancel()
		else:
			set_mode(Mode.NONE)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed:
		_click()


func _click() -> void:
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	if mode == Mode.CORN or mode == Mode.SOYBEANS:
		if _ghost_ok:
			sim.apply({"type": "place_farmhouse", "pos": [_hover.x, _hover.z],
				"dir": [_ghost_dir.x, _ghost_dir.z], "crop": "corn" if mode == Mode.CORN else "soybeans"})
		return
	var p := Vector3(hit.x, 0.0, hit.z)
	if _nodes.size() >= 3 and p.distance_to(_nodes[0]) < CLOSE_DIST:
		_close()
	else:
		_nodes.append(p)
	_update_hint()


func _close() -> void:
	if _nodes.size() >= 3:
		var pts := []
		for n in _nodes:
			pts.append([n.x, n.z])
		sim.apply({"type": "paint_reserve", "points": pts, "kind": reserve_kind if mode == Mode.RESERVE else ""})
	_nodes.clear()
	_update_hint()


func _process(_delta: float) -> void:
	if mode == Mode.NONE:
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	_hover = Vector3(hit.x, 0.0, hit.z)
	if mode == Mode.CORN or mode == Mode.SOYBEANS:
		_place_ghost()
	else:
		_draw_outline()
	var fert := "Soil here: %d%% fertile." % roundi(Farms.fertility_at(_hover) * 100.0)
	if fert != _problem and _nodes.is_empty() and mode != Mode.CORN and mode != Mode.SOYBEANS:
		_problem = fert
		_update_hint()


func _draw_outline() -> void:
	_outline.visible = not _nodes.is_empty()
	if _nodes.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var line := PackedVector3Array(_nodes)
	line.append(_hover)
	if _nodes.size() >= 2:
		line.append(_nodes[0])
	for i in line.size() - 1:
		RoadMesh.add_strip(st, PackedVector3Array([line[i], line[i + 1]]), -0.8, 0.8, 0.5)
	for n in _nodes:
		RoadMesh.add_disc(st, n, 3.0 if n == _nodes[0] else 2.0, 0.55, 12)
	_outline.mesh = st.commit()


## The farmhouse faces the nearest road, like a real farmstead lane.
func _place_ghost() -> void:
	var near := sim.network.find_segment_near(_hover, 200.0, 1.0)
	_ghost_dir = Vector3.FORWARD
	if not near.is_empty():
		var to_road: Vector3 = near.point - _hover
		to_road.y = 0.0
		if to_road.length() > 0.1:
			_ghost_dir = to_road.normalized()
	var problem := sim.farmhouse_problem(_hover, _ghost_dir)
	# Preview the farm lane out to the road.
	_outline.visible = not near.is_empty()
	if not near.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		RoadMesh.add_strip(st, PackedVector3Array(Farms.make_drive(_hover, _ghost_dir, near.point)),
			-Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.4)
		_outline.mesh = st.commit()
	if problem == "" and Farms.FARMHOUSE_COST > sim.economy.money:
		problem = "Not enough money: costs $%s." % CitySim.money_text(Farms.FARMHOUSE_COST)
	_ghost_ok = problem == ""
	var box := BoxMesh.new()
	box.size = Vector3(Farms.FARMHOUSE_SIZE.x, 6.0, Farms.FARMHOUSE_SIZE.y)
	_ghost.mesh = box
	_ghost.transform = Transform3D(Basis.looking_at(_ghost_dir, Vector3.UP), _hover + Vector3(0, 3, 0))
	_ghost.material_override = _ok_mat if _ghost_ok else _bad_mat
	_ghost.visible = true
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	var text := ""
	match mode:
		Mode.NONE:
			return
		Mode.RESERVE, Mode.CLEAR:
			var verb := "land to save for farming (no roads or zoning)" if mode == Mode.RESERVE \
				else "reserved land to release"
			if _nodes.is_empty():
				text = "Click to start outlining %s. %s" % [verb, _problem]
			elif _nodes.size() < 3:
				text = "Click to add corners."
			else:
				text = "Click to add corners. Click the first corner or press Enter to finish."
		Mode.CORN, Mode.SOYBEANS:
			text = "Farmhouse ($%s): place it near rich (green) soil and a road. The farmer builds a barn, then picks the best fields around it." \
				% CitySim.money_text(Farms.FARMHOUSE_COST)
			if _problem != "":
				text += "\n" + _problem
	hint_changed.emit(text)
