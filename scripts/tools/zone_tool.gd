class_name ZoneTool
extends Node3D
## Paints zones with a round brush: hold the left mouse button and drag over
## the lots along a road. [ and ] change the brush size.

signal zone_changed(zone: int)
signal hint_changed(text: String)

const OFF := -1
const MIN_RADIUS := 4.0
const MAX_RADIUS := 48.0

var sim: CitySim
var cam: CityCamera
var zone_view: ZoneView
var zone := OFF
var radius := 14.0

var _painting := false
var _last_paint := Vector3.INF
var _ring := MeshInstance3D.new()
var _ring_mat := StandardMaterial3D.new()


func setup(s: CitySim, camera: CityCamera, view: ZoneView) -> void:
	sim = s
	cam = camera
	zone_view = view


func _ready() -> void:
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.no_depth_test = true
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_update_ring()


func set_zone(z: int) -> void:
	zone = z
	_painting = false
	zone_view.show_all = zone != OFF
	_update_ring()
	zone_changed.emit(zone)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_4: set_zone(ZoneMap.Zone.RESIDENTIAL)
			KEY_5: set_zone(ZoneMap.Zone.COMMERCIAL)
			KEY_6: set_zone(ZoneMap.Zone.INDUSTRIAL)
			KEY_7: set_zone(ZoneMap.Zone.NONE)
			KEY_BRACKETLEFT: if zone != OFF: _resize(1.0 / 1.25)
			KEY_BRACKETRIGHT: if zone != OFF: _resize(1.25)
	if zone == OFF:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed
		_last_paint = Vector3.INF
		if _painting:
			_paint()
	elif event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		set_zone(OFF)


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_ring.visible = zone != OFF and hit != null
	if not _ring.visible:
		return
	_ring.position = Vector3(hit.x, 0.4, hit.z)
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_painting = false
	if _painting:
		_paint()


func _paint() -> void:
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	var p := Vector3(hit.x, 0.0, hit.z)
	if _last_paint != Vector3.INF and p.distance_to(_last_paint) < radius * 0.25:
		return
	_last_paint = p
	sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": radius, "zone": zone})


func _resize(f: float) -> void:
	radius = clampf(radius * f, MIN_RADIUS, MAX_RADIUS)
	_update_ring()
	_update_hint()


func _update_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.6
	torus.outer_radius = radius
	torus.rings = 48
	_ring.mesh = torus
	var c: Color = ZoneMap.COLORS[maxi(zone, 0)] if zone != ZoneMap.Zone.NONE else Color(1, 0.35, 0.3)
	_ring_mat.albedo_color = Color(c, 0.9)


func _update_hint() -> void:
	if zone == OFF:
		return
	var verb: String = "Erase zones" if zone == ZoneMap.Zone.NONE else "Paint " + ZoneMap.NAMES[zone]
	hint_changed.emit("%s: hold left mouse and drag over lots.  Brush %d m  [ ]  Right click to stop." \
		% [verb, int(radius)])
