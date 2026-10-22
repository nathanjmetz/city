class_name CityCamera
extends Node3D
## A Cities: Skylines style camera that orbits a point on the ground.
##
## WASD / arrows: move. Q / E: rotate. R / F: tilt. Scroll: zoom.
## Middle mouse drag: rotate and tilt. Trackpad pinch: zoom.

const MIN_DIST := 25.0
const MAX_DIST := 1200.0
const MIN_PITCH := deg_to_rad(15.0)
const MAX_PITCH := deg_to_rad(85.0)

var camera := Camera3D.new()

var _target := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(50.0)
var _dist := 260.0
var _goal_dist := 260.0
var _rotating := false


func _ready() -> void:
	camera.near = 1.0
	camera.far = 8000.0
	camera.fov = 50.0
	add_child(camera)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_goal_dist = clampf(_goal_dist * 0.88, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_goal_dist = clampf(_goal_dist / 0.88, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
	elif event is InputEventMouseMotion and _rotating:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.004, MIN_PITCH, MAX_PITCH)
	elif event is InputEventMagnifyGesture:
		_goal_dist = clampf(_goal_dist / (event as InputEventMagnifyGesture).factor, MIN_DIST, MAX_DIST)


func _process(delta: float) -> void:
	# Ignore keys while typing in a text box.
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
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
			var speed := _dist * 1.1 * delta
			var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			_target += (right * move.x - fwd * move.y).normalized() * speed
		if Input.is_key_pressed(KEY_Q):
			_yaw += 1.6 * delta
		if Input.is_key_pressed(KEY_E):
			_yaw -= 1.6 * delta
		if Input.is_key_pressed(KEY_R):
			_pitch = clampf(_pitch + 1.0 * delta, MIN_PITCH, MAX_PITCH)
		if Input.is_key_pressed(KEY_F):
			_pitch = clampf(_pitch - 1.0 * delta, MIN_PITCH, MAX_PITCH)
	_dist = lerpf(_dist, _goal_dist, 1.0 - exp(-10.0 * delta))
	_apply()


## Where the mouse ray meets the ground, or null if it points at the sky.
func mouse_ground_point():
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if dir.y > -0.001:
		return null
	var t := -from.y / dir.y
	return from + dir * t


func look_at_point(p: Vector3) -> void:
	_target = Vector3(p.x, 0.0, p.z)


func _apply() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _dist
	camera.global_position = _target + offset
	camera.look_at(_target, Vector3.UP)
