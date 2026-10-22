class_name WarehouseTool
extends Node3D
## Places a warehouse of the chosen size. Move the mouse beside a street and
## it turns to face it, truck court to the road; click to build. From then
## on it runs itself: it fills, builds up and grows back into free land.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
## "" when put away, else a size in Warehouses.KINDS.
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
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and not _site.is_empty() and _problem == "":
		sim.apply({"type": "place_warehouse", "kind": kind, "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z]})
		_update_hint()


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	_site = [] if hit == null else Warehouses.site_near(sim.network, hit)
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or avenue." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.warehouse_problem(kind, _site[0], _site[1])
		var cost: int = Balance.WAREHOUSE[kind].cost
		if problem == "" and cost > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
		var w := {"kind": kind, "pos": _site[0], "dir": _site[1], "bays": 0, "level": 0}
		var h: float = Balance.WAREHOUSE_HEIGHTS[0] + 1.6
		var box := BoxMesh.new()
		box.size = Vector3(Warehouses.site_width(w), h, Warehouses.site_depth(w))
		_ghost.mesh = box
		_ghost.position = Warehouses.center(w) + Vector3(0, h * 0.5, 0)
		_ghost.basis = Basis.looking_at(_site[1], Vector3.UP)
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var k: Dictionary = Warehouses.KINDS[kind]
	var s: Dictionary = Balance.WAREHOUSE[kind]
	var w := {"kind": kind, "bays": 0, "level": 0}
	var text := "%s (%s): $%s. Holds %d truckloads. Stores loads nobody needs yet and sends them on; grows when it stays full." \
		% [k.name, k.area, CitySim.money_text(int(s.cost)), Warehouses.capacity(w)]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
