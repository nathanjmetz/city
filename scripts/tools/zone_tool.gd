class_name ZoneTool
extends Node3D
## Zones street frontage, the way real towns zone: click a street side to
## zone that whole block face (Shift: both sides), or drag along a street to
## zone just the stretch you drag over (a few shops, not a whole block), at
## least a lot long. The game then surveys the lots itself.
## Tab switches to a round brush for odd spots; [ and ] change its size.

signal zone_changed(zone: int)
signal hint_changed(text: String)

const OFF := -1
const MIN_RADIUS := 4.0
const MAX_RADIUS := 48.0
## A drag zones at least one lot's frontage, and runs on to the corner when
## it stops this near one.
const MIN_RUN := 20.0
const SNAP_END := 12.0
## How far (pixels) the mouse moves before a click becomes a drag.
const DRAG_PX := 8.0

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
var _press := Vector2.ZERO  # where the button went down
var _dragging := false
var _spans := {}      # "seg:side" -> [seg, side, from, to] dragged over
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
	if event is InputEventKey and event.pressed and not event.echo:
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
			_release()
			_stop()
		_painting = event.pressed and not (event as InputEventMouseButton).alt_pressed
		_last_paint = Vector3.INF
		_spans.clear()
		_dragging = false
		_press = (event as InputEventMouseButton).position
		if _painting and brush:
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
		_release()
		_stop()
	if _painting and brush:
		_paint()
	elif _painting:
		if not _dragging and get_viewport().get_mouse_position().distance_to(_press) > DRAG_PX:
			_dragging = true
		if _dragging:
			_extend(hit)


## A drag along a street: the stretch under the mouse joins this drag's.
func _extend(hit) -> void:
	if _hover.is_empty() or hit == null:
		return
	var s := sim.planner.side_survey(sim.network, _hover[0], _hover[1])
	if s.is_empty():
		return
	var p := Vector2(hit.x, hit.z)
	var at := -1.0
	var best := INF
	for f in s.fronts:
		var d := (f[1] as Vector2).distance_to(p)
		if d < best:
			best = d
			at = f[0]
	var key := "%d:%d" % [_hover[0], _hover[1]]
	var span: Array = _spans.get(key, [_hover[0], _hover[1], at, at])
	span[2] = minf(span[2], at)
	span[3] = maxf(span[3], at)
	_spans[key] = span
	var parts := _runs()
	var shown := parts.duplicate()
	if Input.is_key_pressed(KEY_SHIFT):
		for r in parts:
			shown.append([r[0], -r[1], r[2], r[3]])
	zone_view.preview = shown
	var metres := 0.0
	for r in parts:
		metres += r[3] - r[2]
	var verb: String = "Dezone" if zone == ZoneMap.Zone.NONE else "Zone " + ZoneMap.NAMES[zone]
	hint_changed.emit("%s: %d ft (%d m) of street. Let go to zone it." % [verb, roundi(metres * 3.28084), roundi(metres)])


## The dragged stretches as they'll be zoned: at least a lot long, and on to
## the corner when they stop near one. [[seg, side, from, to], ...]
func _runs() -> Array:
	var out := []
	var keys := _spans.keys()
	keys.sort()
	for key in keys:
		var r: Array = _spans[key]
		var s := sim.planner.side_survey(sim.network, r[0], r[1])
		if s.is_empty():
			continue
		var length: float = s.len
		var a0: float = r[2]
		var a1: float = r[3]
		if a1 - a0 < MIN_RUN:
			var mid := clampf((a0 + a1) * 0.5, MIN_RUN * 0.5, maxf(length - MIN_RUN * 0.5, MIN_RUN * 0.5))
			a0 = mid - MIN_RUN * 0.5
			a1 = mid + MIN_RUN * 0.5
		if a0 < SNAP_END:
			a0 = 0.0
		if a1 > length - SNAP_END:
			a1 = length
		out.append([r[0], r[1], a0, a1])
	return out


## The button came up: a click zones the whole block face, a drag the
## stretches it went over.
func _release() -> void:
	if not _painting or brush:
		return
	var both := Input.is_key_pressed(KEY_SHIFT)
	if _dragging:
		for r in _runs():
			_held = sim.apply({"type": "zone_frontage", "seg": r[0], "side": r[1], "zone": zone,
				"span": [r[2], r[3]], "both": both, "hold": true}) or _held
		_spans.clear()
		_dragging = false
		_hover = []  # shows the block face under the mouse again
		_update_hint()
	elif not _hover.is_empty():
		sim.apply({"type": "zone_frontage", "seg": _hover[0], "side": _hover[1], "zone": zone, "both": both})


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
	if _dragging:
		return  # the dragged stretch is shown instead
	if h.is_empty():
		zone_view.preview = []
		return
	var parts := sim.frontage_chain(h[0], h[1])
	if Input.is_key_pressed(KEY_SHIFT):
		parts.append_array(sim.frontage_chain(h[0], -h[1]))
	zone_view.preview = parts


## The round brush.
func _paint() -> void:
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
		hint_changed.emit("%s: click a street side for its whole block, or drag along it for just that stretch.  Shift: both sides   Tab: brush   Right click to stop." \
			% verb)
