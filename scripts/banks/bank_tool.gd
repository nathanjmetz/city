class_name BankTool
extends Node3D
## Places a community bank or a Farm Credit office beside a street. From
## then on its president decides every loan and grows it next door.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
## "" when put away, else "community" or "farm_credit".
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
	box.size = Vector3(Banks.CELL, 8.0, Banks.CELL)
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
		sim.apply({"type": "place_bank", "kind": kind, "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z]})
		_update_hint()


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	_site = Banks.site_near(sim.network, Vector3(hit.x, 0.0, hit.z))
	var problem := ""
	if _site.is_empty():
		problem = "Move it beside a street."
		_ghost.visible = false
	else:
		problem = Banks.site_problem(sim, kind, _site[0], _site[1])
		var cost: int = Banks.spec(kind).cost
		if problem == "" and cost > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
		_ghost.transform = Transform3D(Basis.looking_at(_site[1], Vector3.UP), Terrain.lift(_site[0]) + Vector3(0, 5, 0))
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
		_ghost.visible = true
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var k: Dictionary = Banks.KINDS[kind]
	var text := "%s ($%s for the lot; local investors put up the rest): place it on a street with open land behind it. Its %s decides every loan to %s." \
		% [k.name, CitySim.money_text(int(Banks.spec(kind).cost)), k.head.to_lower(),
			"farms, companies and builders" if kind == "community" else "farms and timber companies"]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
