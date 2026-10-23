class_name ZoneTool
extends Node3D
## Zones street frontage, the way real towns zone: click a street side to
## zone that whole block face (Shift: both sides), or drag along streets to
## zone each side you pass. The game then surveys the lots itself.
## Tab switches to a round brush for odd spots; [ and ] change its size.

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
## true: the round brush; false: whole street sides.
var brush := false

var _painting := false
var _last_paint := Vector3.INF
var _hover := []      # [seg, side] under the mouse, or []
var _done := {}       # street sides zoned in this drag
var _held := false    # this drag sent zoning whose lots wait for its end
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
	_stop()
	zone_view.show_all = zone != OFF
	zone_view.preview_zone = maxi(zone, 0)
	if zone == OFF:
		_hover = []
		zone_view.preview = []
	_update_ring()
	zone_changed.emit(zone)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	# Shift + a number opens a bottom bar menu instead (Hud.hotkey_category).
	if event is InputEventKey and event.pressed and not event.echo and not (event as InputEventKey).shift_pressed:
		match (event as InputEventKey).keycode:
			KEY_5: set_zone(ZoneMap.Zone.RESIDENTIAL)
			KEY_6: set_zone(ZoneMap.Zone.COMMERCIAL)
			KEY_7: set_zone(ZoneMap.Zone.INDUSTRIAL)
			KEY_8: set_zone(ZoneMap.Zone.NONE)
			KEY_TAB: if zone != OFF:
				brush = not brush
				zone_view.preview = []
				_update_hint()
			KEY_BRACKETLEFT: if zone != OFF: _resize(1.0 / 1.25)
			KEY_BRACKETRIGHT: if zone != OFF: _resize(1.25)
	if zone == OFF:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_stop()
		_painting = event.pressed and not (event as InputEventMouseButton).alt_pressed
		_last_paint = Vector3.INF
		_done.clear()
		if _painting:
			_paint()
	elif event is InputEventMouseButton and not event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not cam.right_dragged:
		set_zone(OFF)


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_ring.visible = zone != OFF and hit != null and brush
	if zone != OFF and not brush:
		_update_hover(hit)
	if zone == OFF or hit == null:
		return
	_ring.position = Vector3(hit.x, Terrain.ground_y(hit.x, hit.z) + 0.4, hit.z)
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop()
	if _painting:
		_paint()


## The street side under the mouse, with its whole block face shown.
func _update_hover(hit) -> void:
	var h := []
	if hit != null:
		var near := sim.network.find_segment_near(Vector3(hit.x, 0.0, hit.z), 40.0, 1.0)
		if not near.is_empty() and RoadStyle.TYPES[sim.network.segments[near.seg].type].lots:
			var c := sim.network.curve_of(near.seg)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
			var to_mouse := Vector2(hit.x - near.point.x, hit.z - near.point.z)
			var side := 1 if Vector2(-tan.z, tan.x).dot(to_mouse) >= 0.0 else -1
			h = [near.seg, side]
	if h == _hover:
		return
	_hover = h
	if h.is_empty():
		zone_view.preview = []
		return
	var parts := sim.frontage_chain(h[0], h[1])
	if Input.is_key_pressed(KEY_SHIFT):
		parts.append_array(sim.frontage_chain(h[0], -h[1]))
	zone_view.preview = parts


func _paint() -> void:
	if not brush:
		if _hover.is_empty() or _done.has(str(_hover)):
			return
		_done[str(_hover)] = true
		_held = sim.apply({"type": "zone_frontage", "seg": _hover[0], "side": _hover[1], "zone": zone,
			"both": Input.is_key_pressed(KEY_SHIFT), "hold": true}) or _held
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	var p := Vector3(hit.x, 0.0, hit.z)
	if _last_paint != Vector3.INF and p.distance_to(_last_paint) < radius * 0.25:
		return
	_last_paint = p
	_held = sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": radius, "zone": zone,
		"hold": true}) or _held


## Ends a drag: its streets' lots are cut now, once (see CitySim "hold").
func _stop() -> void:
	_painting = false
	if _held:
		_held = false
		sim.apply({"type": "zone_done"})


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
	var verb: String = "Dezone" if zone == ZoneMap.Zone.NONE else "Zone " + ZoneMap.NAMES[zone]
	if brush:
		hint_changed.emit("%s with the brush: drag over the street edge.  Brush %d m  [ ]   Tab: street sides   Right click to stop." \
			% [verb, int(radius)])
	else:
		hint_changed.emit("%s: click a street side, or drag along streets.  Shift: both sides   Tab: brush   Right click to stop." \
			% verb)
