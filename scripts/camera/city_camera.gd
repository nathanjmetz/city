class_name CityCamera
extends Node3D
## A Cities: Skylines 2 style camera that orbits a point on the ground.
## Same default keys as CS2:
##   WASD / arrows: move     Q / E: rotate     T / G: tilt     R / F: zoom
##   Hold Shift: move faster
##   Middle mouse drag: rotate and tilt     Right mouse drag: move
##   Scroll / pinch: zoom (a Mac's Magic Mouse and trackpad scroll too)
## Mac trackpads have no middle button, so Option + drag also rotates and tilts.
## Game controllers (Pad): right stick rotates and tilts, LT / RT zoom, and
## the pad cursor moves the map at the screen edge.

## The closest zoom: 40 m (Brawn, 2026-10-24). Nearer than that the cars'
## and people's simple shapes show; from here a car is about 140 pixels
## long on a 1080p screen and a person about 50 tall, so details like
## door handles and hubcap spokes are too small to need drawing.
const MIN_DIST := 40.0
## Far enough out to lay a whole one-mile section grid (1,609 m) with
## room around it, as CS2 lets you see a whole tile.
const MAX_DIST := 3000.0
const MIN_PITCH := deg_to_rad(10.0)
const MAX_PITCH := deg_to_rad(88.0)
const FAST := 3.0
## A right click that moves less than this many pixels is a click, not a drag.
const DRAG_THRESHOLD := 6.0
## Zoom has momentum. Each wheel click pushes a zoom speed (in log distance
## per second) that friction then bleeds off, so the view glides and settles.
## A slow click moves a little (finer than the old fixed step); clicks that
## come in fast build heat, so a hard spin of the wheel runs out quickly.
const ZOOM_KICK := 0.4
const ZOOM_FRICTION := 6.0
const ZOOM_HEAT_ADD := 0.45
const ZOOM_HEAT_DECAY := 4.0
const ZOOM_HEAT_MAX := 4.0
## Top zoom speed: the whole range (40 m to 3 km) in about a second and a
## quarter, so the map never has to redraw faster than that.
const ZOOM_MAX_RATE := 4.5

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
## Height of the land under the orbit point, eased.
var _ground := NAN
var _pad: Gamepad
## True while the camera rides along with a selected vehicle or person; any
## pan by the player lets go.
var following := false
## Seconds left of a slow, cinematic glide (glide_to); any move cuts it short.
var _slow := 0.0
## Zoom speed in log distance per second (+ out), and how hard the wheel has
## been spun lately.
var _zoom_vel := 0.0
var _zoom_heat := 0.0
## Seconds the zoom keys have been held, so a hold eases up to speed.
var _zoom_hold := 0.0


func _ready() -> void:
	_pad = Gamepad.find()
	camera.near = 1.0
	# Out past the far land (TerrainView.FAR_REACH), so from high up the land
	# runs on into the haze rather than stopping at a line.
	camera.far = 24000.0
	camera.fov = 50.0
	add_child(camera)
	_apply()


# Camera input runs in _input so it works over any tool.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# The right stick scrolls lists with wheel clicks; those never zoom.
		if mb.device == Gamepad.DEVICE and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		# The wheel over a list (or the pause menu) scrolls it, like CS2,
		# instead of zooming the map behind it as well.
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and (MenuState.showing or _over_list()):
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					wheel_click(-1.0, mb.factor)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					wheel_click(1.0, mb.factor)
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
				following = false
				# Drag the ground: the map follows the mouse.
				var scale := _dist * 0.0016
				_goal_target -= (_right() * mm.relative.x - _forward() * mm.relative.y) * scale
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		# The desktop app on a Mac: a Magic Mouse or a two-finger trackpad
		# scroll arrives as a pan gesture, not wheel clicks (the browser turns
		# them into wheel events). Scrolling down zooms out, like the wheel.
		# The OS adds its own glide after the fingers lift, so this steps
		# straight to the new distance; a hard swipe sends bigger deltas and
		# goes further per unit, gentle strokes stay fine.
		var d := clampf((event as InputEventPanGesture).delta.y, -4.0, 4.0)
		_zoom(exp(d * 0.17 * (1.0 + absf(d) * 0.3) * _near_scale()))


func _process(delta: float) -> void:
	# Ignore keys while typing in a text box or with the pause menu up.
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit or MenuState.showing):
		var boost := FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var move := Vector2.ZERO
		if KeyBinds.held("move_forward") or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if KeyBinds.held("move_back") or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if KeyBinds.held("move_left") or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if KeyBinds.held("move_right") or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if move != Vector2.ZERO:
			following = false
			_slow = 0.0
			var speed := _dist * 1.1 * delta * boost
			_goal_target += (_right() * move.x - _forward() * move.y).normalized() * speed
		if KeyBinds.held("rotate_left"):
			_goal_yaw += 1.6 * delta * boost
		if KeyBinds.held("rotate_right"):
			_goal_yaw -= 1.6 * delta * boost
		if KeyBinds.held("tilt_up"):
			_goal_pitch = clampf(_goal_pitch + 1.0 * delta * boost, MIN_PITCH, MAX_PITCH)
		if KeyBinds.held("tilt_down"):
			_goal_pitch = clampf(_goal_pitch - 1.0 * delta * boost, MIN_PITCH, MAX_PITCH)
		var keys := (1.0 if KeyBinds.held("zoom_out") else 0.0) - (1.0 if KeyBinds.held("zoom_in") else 0.0)
		if keys != 0.0:
			# A tap nudges; holding eases up to full speed over most of a second.
			_zoom_hold += delta
			var rate := lerpf(0.7, 2.2, clampf(_zoom_hold / 0.8, 0.0, 1.0)) * minf(boost, 1.5)
			_zoom_rate(keys * rate, delta)
		else:
			_zoom_hold = 0.0
	if _pad != null and not MenuState.showing:
		_pad_input(delta)
	_zoom_glide(delta)
	# Ease toward the goal, like CS2's smoothed camera.
	var rate := 12.0
	if _slow > 0.0:
		_slow -= delta
		rate = 2.2
	var k := 1.0 - exp(-rate * delta)
	_target = _target.lerp(_goal_target, k)
	_yaw = lerpf(_yaw, _goal_yaw, k)
	_pitch = lerpf(_pitch, _goal_pitch, k)
	_dist = lerpf(_dist, _goal_dist, 1.0 - exp(-rate * 0.85 * delta))
	_apply()


## Glides over to look at a spot on the ground (a neighbor's city, say).
func fly_to(p: Vector3) -> void:
	_goal_target = Vector3(p.x, 0.0, p.z)
	_goal_dist = maxf(_goal_dist, 420.0)


## A slow glide over to a spot, ending `dist` metres away (the guided first
## town takes the camera to each step this way).
func glide_to(p: Vector3, dist: float) -> void:
	following = false
	_goal_target = Vector3(p.x, 0.0, p.z)
	_goal_dist = maxf(dist, MIN_DIST)
	_zoom_vel = 0.0
	_slow = 2.5


## Where the mouse (or the pad cursor) ray meets the ground, or null if it
## points at the sky.
## The point comes back on the map (y = 0, the sim's ground level), wherever
## the hills put it on screen.
func mouse_ground_point():
	var mouse := _pad.pointer(get_viewport()) if _pad != null else get_viewport().get_mouse_position()
	var hit = Terrain.ray_hit(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return null
	return Vector3(hit.x, 0.0, hit.z)


## The point on the ground the camera is looking at.
## Keeps the view centred on a moving point (call each frame while following).
func follow_point(p: Vector3) -> void:
	_goal_target = Vector3(p.x, 0.0, p.z)
	_goal_dist = minf(_goal_dist, 140.0)


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
	_zoom_vel = 0.0


## True while a mouse button is being used to move the camera, so tools
## leave that click alone.
func is_dragging() -> bool:
	return _rotating or right_dragged


## Game controller: the cursor pushing on a screen edge moves the map, the
## right stick rotates and tilts, the triggers zoom.
func _pad_input(delta: float) -> void:
	if _pad.pan != Vector2.ZERO:
		following = false
		var speed := _dist * 1.1 * delta
		_goal_target += (_right() * _pad.pan.x - _forward() * _pad.pan.y) * speed
	if _pad.turn != Vector2.ZERO:
		_goal_yaw -= _pad.turn.x * 1.8 * delta
		_goal_pitch = clampf(_goal_pitch + _pad.turn.y * 1.1 * delta, MIN_PITCH, MAX_PITCH)
	if _pad.zoom != 0.0:
		# A light squeeze creeps, a full pull races: speed grows with the
		# cube of the trigger, so the slow end has plenty of travel.
		var z := absf(_pad.zoom)
		_zoom_rate(-signf(_pad.zoom) * (0.6 * z + 1.7 * z * z * z), delta)


## True when the mouse is over a scrolling list in a panel.
func _over_list() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	while c != null:
		if c is ScrollContainer or c is RichTextLabel or c is ItemList or c is TextEdit:
			return true
		c = c.get_parent() as Control
	return false


func _zoom(f: float) -> void:
	_slow = 0.0
	_goal_dist = clampf(_goal_dist * f, MIN_DIST, MAX_DIST)


## One wheel click: dir -1 zooms in, +1 out. factor is the size of the click
## (1 for a mouse wheel, less for the browser's fine trackpad steps).
func wheel_click(dir: float, factor := 1.0) -> void:
	_slow = 0.0
	if factor <= 0.0:
		factor = 1.0
	# Turning the wheel the other way stops the glide dead, so it is easy
	# to catch the view where you want it.
	if _zoom_vel * dir < 0.0:
		_zoom_vel = 0.0
		_zoom_heat = 0.0
		return
	_zoom_heat = minf(_zoom_heat + ZOOM_HEAT_ADD * minf(factor, 1.0), ZOOM_HEAT_MAX)
	_zoom_vel += dir * ZOOM_KICK * minf(factor, 2.0) * (1.0 + _zoom_heat) * _near_scale()
	_zoom_vel = clampf(_zoom_vel, -ZOOM_MAX_RATE, ZOOM_MAX_RATE)


## Held zoom (keys, triggers): rate in log distance per second, + out.
func _zoom_rate(rate: float, delta: float) -> void:
	_zoom(exp(clampf(rate * _near_scale(), -ZOOM_MAX_RATE, ZOOM_MAX_RATE) * delta))


## Runs the wheel's zoom glide each frame and lets it coast to a stop.
func _zoom_glide(delta: float) -> void:
	_zoom_heat = maxf(_zoom_heat - ZOOM_HEAT_DECAY * _zoom_heat * delta, 0.0)
	if _zoom_vel == 0.0:
		return
	_goal_dist = clampf(_goal_dist * exp(_zoom_vel * delta), MIN_DIST, MAX_DIST)
	_zoom_vel *= exp(-ZOOM_FRICTION * delta)
	if absf(_zoom_vel) < 0.01 or (_zoom_vel < 0.0 and _goal_dist <= MIN_DIST) or (_zoom_vel > 0.0 and _goal_dist >= MAX_DIST):
		_zoom_vel = 0.0


## Up close each click moves less: about half speed at street level, full
## speed from 400 m up, so the last few metres are easy to judge.
func _near_scale() -> float:
	return lerpf(0.5, 1.0, clampf(log(_goal_dist / MIN_DIST) / log(400.0 / MIN_DIST), 0.0, 1.0))


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _apply() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _dist
	# Orbit the spot on the land itself, following the hills smoothly.
	var ground := Terrain.ground_y(_target.x, _target.z)
	_ground = ground if is_nan(_ground) else lerpf(_ground, ground, 0.2)
	var aim := Vector3(_target.x, _ground, _target.z)
	var pos := aim + offset
	# Never dip into a hillside.
	pos.y = maxf(pos.y, Terrain.ground_y(pos.x, pos.z) + 6.0)
	camera.global_position = pos
	camera.look_at(aim, Vector3.UP)
	# Push the near plane out with height: depth precision goes with
	# near / distance², and a 1 m near plane makes the thin ground layers
	# (road paint, sidewalks, drives, fields) z-fight and flicker from high up.
	camera.near = clampf((pos.y - ground) * 0.2, 0.5, 40.0)
