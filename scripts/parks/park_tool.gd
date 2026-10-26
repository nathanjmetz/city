class_name ParkTool
extends Node3D
## Places parks and landmarks. Move the mouse beside a road and the site
## turns to face it, like Cities: Skylines 2; click to build. A park starts as
## a lawn and fills in by itself; landmarks are one per town.

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
var kind := ""
## The park size picked (Balance.PARK_SIZES), kept while the tool is away.
var size_class := 0

var _ghost := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _site := []
var _problem := ""


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.35, 0.85, 0.45, 0.4)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.45)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


## Picks a park size and takes out the park tool.
func set_size(i: int) -> void:
	size_class = clampi(i, 0, Balance.PARK_SIZES.size() - 1)
	set_kind("park")


## The size class for the kind in hand (landmarks have one size).
func _class() -> int:
	return size_class if kind == "park" else 0


func set_kind(k: String) -> void:
	kind = k
	_ghost.visible = false
	_problem = ""
	kind_changed.emit(kind)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if kind == "" or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_kind("")
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and not _site.is_empty() \
			and _problem == "":
		sim.apply({"type": "place_park", "kind": kind, "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z],
			"size": _class()})
		# A landmark is one per town: put the tool away once it's built.
		if Parks.KINDS[kind].landmark and sim.parks.has_kind(kind):
			set_kind("")
		else:
			_update_hint()


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	_site = [] if hit == null else Parks.site_near(sim.network, kind, hit, _class())
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or avenue." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.parks.site_problem(sim, kind, _site[0], _site[1], _class())
		if problem == "" and Parks.cost_of(kind, _class()) > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(Parks.cost_of(kind, _class()))
		var size := Parks.size_of(kind, _class())
		var box := BoxMesh.new()
		box.size = Vector3(size.x, 1.0 if kind == "park" else 4.0, size.y)
		_ghost.mesh = box
		_ghost.position = Terrain.lift(_site[0]) + Vector3(0, box.size.y * 0.5, 0)
		_ghost.basis = Basis.looking_at(_site[1], Vector3.UP)
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var a: Dictionary = Balance.AMENITIES[kind]
	var text := ""
	if kind == "park":
		var ps := Parks.park_size(size_class)
		var acres: float = ps.size.x * ps.size.y / 4046.86
		text = "%s park, %s acres: $%s. Starts as a lawn, fills in and grows to %d acres by itself." % [ps.name,
			("%.1f" % acres) if acres < 1.0 else str(roundi(acres)), CitySim.money_text(int(ps.cost)), roundi(float(ps.max_acres))]
	else:
		text = "%s: $%s to build, $%s a day. One per town." % [Parks.KINDS[kind].name,
			CitySim.money_text(Parks.cost_of(kind)), CitySim.money_text(int(a.upkeep))]
		text += " Raises land value up to %d%% and happiness nearby." % roundi(float(a.value) * 100.0)
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
