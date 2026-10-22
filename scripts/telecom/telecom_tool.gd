class_name TelecomTool
extends Node3D
## Places the town's phone company beside a road, the way Brawn asked: the
## player picks the spot and the city's grant, and from then on its general
## manager strings fiber and puts up cell towers where they pay off.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
## "" when put away, else "telecom".
var kind := ""

var _ghost := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _site := []
var _problem := ""


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.3, 0.75, 1.0, 0.45)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.45)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3(Telecom.CELL, 6.0, Telecom.CELL)
	_ghost.mesh = box
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
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and _problem == "" \
			and not _site.is_empty():
		if sim.apply({"type": "place_telecom", "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z]}):
			set_kind("")  # one per town
		else:
			_update_hint()


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	_site = Telecom.site_near(sim.network, Vector3(hit.x, 0.0, hit.z))
	var problem := ""
	if _site.is_empty():
		problem = "Move it beside a street."
		_ghost.visible = false
	else:
		problem = Telecom.site_problem(sim, _site[0], _site[1])
		if problem == "" and Balance.TELECOM_COST > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(Balance.TELECOM_COST)
		_ghost.transform = Transform3D(Basis.looking_at(_site[1], Vector3.UP), Terrain.lift(_site[0]) + Vector3(0, 3, 0))
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
		_ghost.visible = true
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var text := "Phone company ($%s, $%s a month grant): place its central office beside a street. Its manager strings fiber and puts up cell towers where they pay off, densest streets first." \
		% [CitySim.money_text(Balance.TELECOM_COST), CitySim.money_text(Balance.TELECOM_GRANT)]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
