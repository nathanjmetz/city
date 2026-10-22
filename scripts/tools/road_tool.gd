class_name RoadTool
extends Node3D
## Lets the player draw and remove roads with the mouse.
##
## Straight: click start, click end (keeps going from the end).
## Curved: click start, click the bend, click end.
## Bulldoze: click a road to remove it.
## Right click or Esc stops the current road.

signal mode_changed(mode: int)
signal hint_changed(text: String)

enum Mode { NONE, STRAIGHT, CURVED, BULLDOZE }

const SNAP_NODE := 9.0
const SNAP_ROAD := 7.0
## Straight roads snap to 15 degree steps while Shift is held.
const ANGLE_STEP := deg_to_rad(15.0)

var sim: CitySim
var network: RoadNetwork
var cam: CityCamera
var mode := Mode.STRAIGHT

var _points: Array[Vector3] = []
var _preview := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
var _ok_mat := RoadStyle.material(Color(0.35, 0.65, 1.0, 0.55), true)
var _bad_mat := RoadStyle.material(Color(1.0, 0.3, 0.25, 0.6), true)
var _hover_seg := -1


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	network = s.network
	cam = camera


func _ready() -> void:
	add_child(_preview)
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 3.0
	ring.rings = 24
	_cursor.mesh = ring
	_cursor.material_override = _ok_mat
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)
	set_mode(mode)


func set_mode(m: int) -> void:
	mode = m
	_points.clear()
	_hover_seg = -1
	mode_changed.emit(mode)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: set_mode(Mode.STRAIGHT)
			KEY_2: set_mode(Mode.CURVED)
			KEY_3: set_mode(Mode.BULLDOZE)
			KEY_ESCAPE: _cancel()
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		_click()


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_preview.visible = false
	_cursor.visible = hit != null and mode != Mode.NONE
	if hit == null or mode == Mode.NONE:
		return
	if mode == Mode.BULLDOZE:
		_preview_bulldoze(hit)
		return
	var p := _snapped(hit)
	_cursor.position = p + Vector3.UP * 0.3
	_cursor.material_override = _ok_mat
	if _points.is_empty():
		return
	var curve := _pending_curve(p)
	var ok := _is_valid(curve)
	_preview.mesh = _preview_mesh(curve)
	_preview.material_override = _ok_mat if ok else _bad_mat
	_preview.visible = true


func _click() -> void:
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	match mode:
		Mode.BULLDOZE:
			if _hover_seg != -1:
				sim.apply({"type": "remove_road", "seg": _hover_seg})
				_hover_seg = -1
		Mode.STRAIGHT, Mode.CURVED:
			var p := _snapped(hit)
			var needed := 2 if mode == Mode.STRAIGHT else 3
			if _points.size() + 1 < needed:
				_points.append(p)
			else:
				var curve := _pending_curve(p)
				if _is_valid(curve) and sim.apply({"type": "build_road",
						"start": _xz(curve[0]), "ctrl": _xz(curve[1]), "end": _xz(curve[2])}):
					_points.clear()
					_points.append(curve[2])
	_update_hint()


static func _xz(v: Vector3) -> Array:
	return [v.x, v.z]


func _cancel() -> void:
	_points.clear()
	_update_hint()


## Start, control point and end of the road being drawn, ending at p.
func _pending_curve(p: Vector3) -> Array:
	var a: Vector3 = _points[0]
	if mode == Mode.CURVED and _points.size() >= 2:
		return [a, _points[1], p]
	if mode == Mode.STRAIGHT and Input.is_key_pressed(KEY_SHIFT):
		var d := p - a
		var ang := snappedf(atan2(d.z, d.x), ANGLE_STEP)
		p = a + Vector3(cos(ang), 0.0, sin(ang)) * d.length()
	return [a, a.lerp(p, 0.5), p]


func _is_valid(curve: Array) -> bool:
	if curve[0].distance_to(curve[2]) < RoadNetwork.MIN_LENGTH:
		return false
	# Very sharp bends make the road fold over itself.
	var t0: Vector3 = curve[1] - curve[0]
	var t1: Vector3 = curve[2] - curve[1]
	return t0.length() < 0.5 or t1.length() < 0.5 or t0.angle_to(t1) < deg_to_rad(120.0)


func _snapped(hit: Vector3) -> Vector3:
	if mode == Mode.CURVED and _points.size() == 1:
		return Vector3(hit.x, 0.0, hit.z)  # bend point floats freely
	return network.snap(hit, SNAP_NODE, SNAP_ROAD).pos


func _preview_mesh(curve: Array) -> ArrayMesh:
	var pts := RoadNetwork.sample_curve(curve[0], curve[1], curve[2])
	for i in pts.size():
		pts[i].y = 0.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.add_strip(st, pts, -RoadStyle.half_width(), RoadStyle.half_width(), 0.2)
	return st.commit()


func _preview_bulldoze(hit: Vector3) -> void:
	var near := network.find_segment_near(hit, RoadStyle.half_width() + 2.0)
	_hover_seg = near.seg if not near.is_empty() else -1
	_cursor.position = hit + Vector3.UP * 0.3
	_cursor.material_override = _bad_mat
	if _hover_seg == -1:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.add_strip(st, network.sample_segment(_hover_seg), -RoadStyle.half_width() - 0.5,
		RoadStyle.half_width() + 0.5, 0.2)
	_preview.mesh = st.commit()
	_preview.material_override = _bad_mat
	_preview.visible = true


func _update_hint() -> void:
	if mode == Mode.NONE:
		return
	var text := ""
	match mode:
		Mode.STRAIGHT:
			text = "Click to start a road." if _points.is_empty() \
				else "Click to finish. Hold Shift to snap angles. Right click to stop."
		Mode.CURVED:
			if _points.is_empty():
				text = "Click to start a curved road."
			elif _points.size() == 1:
				text = "Click where the road should bend."
			else:
				text = "Click to finish. Right click to stop."
		Mode.BULLDOZE:
			text = "Click a road to remove it."
	hint_changed.emit(text)
