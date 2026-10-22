class_name CityCamera
extends Node3D
## A Cities: Skylines 2 style camera that orbits a point on the ground.
## Same default keys as CS2:
##   WASD / arrows: move     Q / E: rotate     T / G: tilt     R / F: zoom
##   Hold Shift: move faster
##   Middle mouse drag: rotate and tilt     Right mouse drag: move
##   Scroll / pinch: zoom
## Mac trackpads have no middle button, so Option + drag also rotates and tilts.

const MIN_DIST := 25.0
const MAX_DIST := 1200.0
const MIN_PITCH := deg_to_rad(10.0)
const MAX_PITCH := deg_to_rad(88.0)
const FAST := 3.0
## A right click that moves less than this many pixels is a click, not a drag.
const DRAG_THRESHOLD := 6.0

var camera := Camera3D.new()
## True while the last right button press turned into a drag.
var right_dragged := false

var _target := Vector3.ZERO
var _goal_target := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(50.0)
var _goal_yaw := _yaw
var _goal_pitch := _pitch
var _dist := 260.0
var _goal_dist := 260.0
var _rotating := false
var _panning := false
var _pan_moved := 0.0


func _ready() -> void:
	camera.near = 1.0
	camera.far = 8000.0
	camera.fov = 50.0
	add_child(camera)
	_apply()


# Camera input runs in _input so it works over any tool.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 0.88)
			MOUSE_BUTTON_MIDDLE:
				_rotating = mb.pressed
			MOUSE_BUTTON_LEFT:
				# Option/Alt + drag stands in for the middle button.
				_rotating = mb.pressed and mb.alt_pressed
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				if mb.pressed:
					_pan_moved = 0.0
					right_dragged = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			_goal_yaw -= mm.relative.x * 0.006
			_goal_pitch = clampf(_goal_pitch + mm.relative.y * 0.004, MIN_PITCH, MAX_PITCH)
		elif _panning:
			_pan_moved += mm.relative.length()
			if _pan_moved > DRAG_THRESHOLD:
				right_dragged = true
				# Drag the ground: the map follows the mouse.
				var scale := _dist * 0.0016
				_goal_target -= (_right() * mm.relative.x - _forward() * mm.relative.y) * scale
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor)


func _process(delta: float) -> void:
	# Ignore keys while typing in a text box.
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		var boost := FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if move != Vector2.ZERO:
			var speed := _dist * 1.1 * delta * boost
			_goal_target += (_right() * move.x - _forward() * move.y).normalized() * speed
		if Input.is_key_pressed(KEY_Q):
			_goal_yaw += 1.6 * delta * boost
		if Input.is_key_pressed(KEY_E):
			_goal_yaw -= 1.6 * delta * boost
		if Input.is_key_pressed(KEY_T):
			_goal_pitch = clampf(_goal_pitch + 1.0 * delta * boost, MIN_PITCH, MAX_PITCH)
		if Input.is_key_pressed(KEY_G):
			_goal_pitch = clampf(_goal_pitch - 1.0 * delta * boost, MIN_PITCH, MAX_PITCH)
		if Input.is_key_pressed(KEY_R):
			_zoom(1.0 - 1.5 * delta * boost)
		if Input.is_key_pressed(KEY_F):
			_zoom(1.0 + 1.5 * delta * boost)
	# Ease toward the goal, like CS2's smoothed camera.
	var k := 1.0 - exp(-12.0 * delta)
	_target = _target.lerp(_goal_target, k)
	_yaw = lerpf(_yaw, _goal_yaw, k)
	_pitch = lerpf(_pitch, _goal_pitch, k)
	_dist = lerpf(_dist, _goal_dist, 1.0 - exp(-10.0 * delta))
	_apply()


## Glides over to look at a spot on the ground (a neighbor's city, say).
func fly_to(p: Vector3) -> void:
	_goal_target = Vector3(p.x, 0.0, p.z)
	_goal_dist = maxf(_goal_dist, 420.0)


## Where the mouse ray meets the ground, or null if it points at the sky.
func mouse_ground_point():
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if dir.y > -0.001:
		return null
	var t := -from.y / dir.y
	return from + dir * t


## The point on the ground the camera is looking at.
func focus() -> Vector3:
	return _target


func look_at_point(p: Vector3) -> void:
	_target = Vector3(p.x, 0.0, p.z)
	_goal_target = _target


func set_view(yaw: float, pitch: float, dist: float) -> void:
	_yaw = yaw
	_goal_yaw = yaw
	_pitch = pitch
	_goal_pitch = pitch
	_dist = dist
	_goal_dist = dist


## True while a mouse button is being used to move the camera, so tools
## leave that click alone.
func is_dragging() -> bool:
	return _rotating or right_dragged


func _zoom(f: float) -> void:
	_goal_dist = clampf(_goal_dist * f, MIN_DIST, MAX_DIST)


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _apply() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _dist
	camera.global_position = _target + offset
	camera.look_at(_target, Vector3.UP)
	# Push the near plane out with height: depth precision goes with
	# near / distance², and a 1 m near plane makes the thin ground layers
	# (road paint, sidewalks, drives, fields) z-fight and flicker from high up.
	camera.near = clampf(offset.y * 0.2, 0.5, 40.0)
