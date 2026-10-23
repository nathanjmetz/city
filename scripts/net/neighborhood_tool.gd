class_name NeighborhoodTool
extends Node3D
## Starts one of the town's other neighborhoods out on open land (see
## Neighborhoods): click a spot a mile or more from other towns, and a free
## county road links it to the nearest road in town. The ring shows the
## ground that has to see a building within NEIGHBORHOOD_USE_DAYS.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
## "" when put away, "found" in hand.
var kind := ""

var _ghost := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _spot := Vector2.ZERO
var _problem := ""


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.3, 0.75, 1.0, 0.3)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.3)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := CylinderMesh.new()
	disc.top_radius = Balance.NEIGHBORHOOD_USE_RADIUS
	disc.bottom_radius = Balance.NEIGHBORHOOD_USE_RADIUS
	disc.height = 1.0
	disc.radial_segments = 48
	_ghost.mesh = disc
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func set_kind(k: String) -> void:
	kind = k
	_ghost.visible = false
	kind_changed.emit(kind)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if kind == "" or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_kind("")
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and _problem == "":
		sim.apply({"type": "found_neighborhood", "pos": [_spot.x, _spot.y]})
		set_kind("")


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	_spot = Vector2(hit.x, hit.z)
	var problem := sim.neighborhood_problem(_spot)
	_ghost.position = Terrain.lift(Vector3(hit.x, 0.0, hit.z)) + Vector3(0, 0.5, 0)
	_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	_ghost.visible = true
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var n := sim.neighborhoods
	var text := "New neighborhood ($%s; %d of %d earned): click open land a mile or more from other towns. A free county road links it to town. Build there within %d game days or the site is let go." \
		% [CitySim.money_text(n.fee()), n.slots_free(int(sim.stats.population)),
			Neighborhoods.slots_for(int(sim.stats.population)), Balance.NEIGHBORHOOD_USE_DAYS]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
