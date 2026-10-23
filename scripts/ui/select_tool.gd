class_name SelectTool
extends Node3D
## Click anything with no tool in hand to select it, like Cities: Skylines 2:
## a building, lot, farm or road. A ring marks it, and the info panel shows
## what it's doing. Esc or a click on open ground clears the selection.
## A selected vehicle or person can be followed with the camera.

signal selected(sel: Dictionary)

var sim: CitySim
var cam: CityCamera
## Returns true while a tool is in hand (clicks belong to the tool then).
var busy := Callable()
var selection := {}
## While a pollution view is on, a click on open ground shows the pollution
## there and who makes it.
var spot_clicks := false

var _ring := MeshInstance3D.new()
## Arcs to where a selected home's people work, or a workplace's staff live.
var _lines := ConnectionLines.new()
var _press := Vector2(-1, -1)


func setup(s: CitySim, camera: CityCamera, tool_in_hand: Callable) -> void:
	sim = s
	cam = camera
	busy = tool_in_hand


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	_ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(Brand.BRAND_MINT, 0.95)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	add_child(_lines)


func select(sel: Dictionary) -> void:
	if sel != selection:
		cam.following = false
	selection = sel
	_ring.visible = false
	_lines.sim = sim
	_lines.show_for(sel)
	selected.emit(sel)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if busy.is_valid() and busy.call():
		_press = Vector2(-1, -1)
		return
	if mb.pressed:
		_press = mb.position
	elif _press.x >= 0.0 and mb.position.distance_to(_press) < 6.0:
		_press = Vector2(-1, -1)
		var hit = cam.mouse_ground_point()
		var sel := {} if hit == null else Inspect.pick(sim, hit)
		if sel.is_empty() and hit != null and spot_clicks:
			sel = {"type": "spot", "id": [snappedf(hit.x, 0.1), snappedf(hit.z, 0.1)]}
		select(sel)


func _process(_delta: float) -> void:
	if selection.is_empty():
		return
	if busy.is_valid() and busy.call():
		select({})
		return
	var at := Inspect.place(sim, selection)
	if at.is_empty():
		select({})
		return
	if cam.following:
		cam.follow_point(at[0])
	var r: float = at[1]
	_ring.visible = r > 0.0
	_ring.position = Vector3(at[0].x, Terrain.ground_y(at[0].x, at[0].z) + 0.4, at[0].z)
	_ring.scale = Vector3(r, 0.6, r)


## Rides along with the selection (a vehicle or a person out walking).
func follow(on := true) -> void:
	cam.following = on and not selection.is_empty()
