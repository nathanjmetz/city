class_name BigFactoryTool
extends Node3D
## Places one of the big local factories. Move the mouse beside a street and
## it turns to face it, office and truck gate to the road; click to build.
## From then on its owner runs it: buys inputs, ships, builds and grows.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
## "" when put away, else a key of BigFactories.KINDS.
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
		sim.apply({"type": "place_big_factory", "kind": kind, "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z]})
		set_kind("")


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	_site = [] if hit == null else Warehouses.site_near(sim.network, hit)
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or avenue." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.big.site_problem(sim, kind, _site[0], _site[1])
		var cost: int = Balance.BIG_FACTORY[kind].cost
		if problem == "" and cost > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
		var f := {"kind": kind, "pos": _site[0], "dir": _site[1], "bays": 0}
		var box := BoxMesh.new()
		box.size = Vector3(BigFactories.site_width(f), 12.0, BigFactories.site_depth(f))
		_ghost.mesh = box
		_ghost.position = Terrain.lift(BigFactories.center(f)) + Vector3(0, 6.0, 0)
		_ghost.basis = Basis.looking_at(_site[1], Vector3.UP)
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var k: Dictionary = BigFactories.KINDS[kind]
	var s: Dictionary = Balance.BIG_FACTORY[kind]
	var ins := []
	for input in s["in"]:
		ins.append(input)
	var text := "%s: $%s for the site. Makes %s from %s, bought from your farms and companies first, then neighbors. One per town; its owner runs it and grows it." \
		% [k.name, CitySim.money_text(int(s.cost)), k.makes, " and ".join(ins)]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
