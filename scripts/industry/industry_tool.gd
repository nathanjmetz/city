class_name IndustryTool
extends Node3D
## Places a resource company's main building (oil, mining or forestry), as
## Brawn asked: the matching view opens, you put the building near the
## resource and within reach of a road, and over the years it opens wells,
## pits or logging stands wherever the resource is richest around it.
## Saving land for it is the Reserve tool (FarmTool with that kind).

signal kind_changed(kind: String)
signal hint_changed(text: String)

var sim: CitySim
var cam: CityCamera
var info: InfoView
## "" when put away, else "oil", "ore" or "forest".
var kind := ""

var _ghost := MeshInstance3D.new()
var _lane := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _lane_mat := StandardMaterial3D.new()
var _hover := Vector3.ZERO
var _dir := Vector3.FORWARD
var _ok := false
var _problem := ""
var _opened_view := false


func setup(s: CitySim, camera: CityCamera, v: InfoView) -> void:
	sim = s
	cam = camera
	info = v


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.3, 0.75, 1.0, 0.45)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.45)],
			[_lane_mat, Color(1.0, 0.9, 0.4, 0.9)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
	_lane.material_override = _lane_mat
	for mi in [_ghost, _lane]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)


static func view_for(k: String) -> int:
	return {"oil": InfoView.Mode.OIL, "ore": InfoView.Mode.ORE, "forest": InfoView.Mode.FOREST}.get(k, InfoView.Mode.NONE)


func set_kind(k: String) -> void:
	kind = k
	if kind != "":
		info.set_mode(view_for(kind))
		_opened_view = true
	elif _opened_view:
		_opened_view = false
		info.set_mode(InfoView.Mode.NONE)
	_ghost.visible = false
	_lane.visible = false
	kind_changed.emit(kind)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if kind == "" or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_kind("")
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and _ok:
		sim.apply({"type": "place_industry", "kind": kind, "pos": [_hover.x, _hover.z], "dir": [_dir.x, _dir.z]})
		_update_hint()


func _process(_delta: float) -> void:
	if kind == "":
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	_hover = Vector3(hit.x, 0.0, hit.z)
	# The main building faces the nearest road, its access road running out to it.
	var near := sim.network.find_segment_near(_hover, Industry.MAX_DRIVE, 1.0)
	_dir = Vector3.FORWARD
	if not near.is_empty():
		var to_road: Vector3 = near.point - _hover
		to_road.y = 0.0
		if to_road.length() > 0.1:
			_dir = to_road.normalized()
	var problem := sim.industry_problem(kind, _hover, _dir)
	var cost: int = Industry.KINDS[kind].cost
	if problem == "" and cost > sim.economy.money:
		problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
	_ok = problem == ""
	_lane.visible = not near.is_empty()
	if _lane.visible:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		RoadMesh.add_strip(st, PackedVector3Array(Farms.make_drive(_hover, _dir, near.point)),
			-Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.4)
		_lane.mesh = Terrain.drape(st.commit(), true, 8.0)
	var box := BoxMesh.new()
	box.size = Vector3(Industry.HQ_SIZE.x, 8.0, Industry.HQ_SIZE.y)
	_ghost.mesh = box
	_ghost.transform = Transform3D(Basis.looking_at(_dir, Vector3.UP), Vector3(_hover.x, Terrain.ground_y(_hover.x, _hover.z) + 4.0, _hover.z))
	_ghost.material_override = _ok_mat if _ok else _bad_mat
	_ghost.visible = true
	var here := "%s within reach: %d%%." % [Industry.KINDS[kind].cargo.capitalize(),
		roundi(sim.industry_reach(kind, _hover) * 100.0)]
	problem = here if problem == "" else here + " " + problem
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == "":
		return
	var k: Dictionary = Industry.KINDS[kind]
	var text := "%s ($%s): place it near rich ground and a road. Its %ss spread over time to where the %s is." \
		% [k.name, CitySim.money_text(int(k.cost)), k.pad, k.cargo]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
