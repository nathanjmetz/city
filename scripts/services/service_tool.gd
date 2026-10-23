class_name ServiceTool
extends Node3D
## Places service buildings. Move the mouse beside a road and the building
## turns to face it, like Cities: Skylines 2; click to build. Also places
## landfills, recycling centres and cemeteries (CivicHubs.TOOL_KINDS), and the
## post office (Mail.TOOL_KIND) and rail depots (Rail.TOOL_KIND).

signal kind_changed(kind: int)
signal hint_changed(text: String)

const OFF := -1

var sim: CitySim
var cam: CityCamera
var view: ServiceView
var kind := OFF

var _ghost := MeshInstance3D.new()
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _site := []
var _problem := ""


func setup(s: CitySim, camera: CityCamera, v: ServiceView) -> void:
	sim = s
	cam = camera
	view = v


func _ready() -> void:
	for entry in [[_ok_mat, Color(0.3, 0.75, 1.0, 0.45)], [_bad_mat, Color(1.0, 0.3, 0.25, 0.45)]]:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = entry[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func set_kind(k: int) -> void:
	kind = k
	view.show_kind = k
	_ghost.visible = false
	kind_changed.emit(kind)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if kind == OFF or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_kind(OFF)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and not _site.is_empty():
		if kind == Rail.TOOL_KIND:
			sim.apply({"type": "place_rail_depot", "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z],
				"axis": [_site[2].x, _site[2].z]})
		elif kind == Mail.TOOL_KIND:
			sim.apply({"type": "place_post_office", "pos": [_site[0].x, _site[0].z], "dir": [_site[1].x, _site[1].z]})
		elif CivicHubs.TOOL_KINDS.has(kind):
			sim.apply({"type": "place_hub", "kind": CivicHubs.TOOL_KINDS[kind], "pos": [_site[0].x, _site[0].z],
				"dir": [_site[1].x, _site[1].z]})
		elif sim.apply({"type": "place_service", "kind": kind, "pos": [_site[0].x, _site[0].z],
				"dir": [_site[1].x, _site[1].z]}):
			view.show_kind = kind  # refresh the coverage shown
		_update_hint()


func _process(_delta: float) -> void:
	if kind == OFF:
		return
	var hit = cam.mouse_ground_point()
	if kind == Rail.TOOL_KIND:
		_rail_ghost(hit)
		return
	if CivicHubs.TOOL_KINDS.has(kind) or kind == Mail.TOOL_KIND:
		_hub_ghost(hit)
		return
	_site = [] if hit == null else Services.site_near(sim.network, kind, hit)
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or avenue." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.services.site_problem(sim.network, kind, _site[0], _site[1])
		var cost: int = Services.KINDS[kind].cost
		if problem == "" and cost > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
		var size: Vector2 = Services.KINDS[kind].size
		var box := BoxMesh.new()
		box.size = Vector3(size.x, 4.0, size.y)
		_ghost.mesh = box
		_ghost.position = Terrain.lift(_site[0]) + Vector3(0, 2.0, 0)
		_ghost.basis = Basis.looking_at(_site[1], Vector3.UP)
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


## The ghost of a landfill, recycling centre or cemetery: its first six
## pieces of land behind the street.
func _hub_ghost(hit) -> void:
	var post := kind == Mail.TOOL_KIND
	var hk: String = "" if post else CivicHubs.TOOL_KINDS[kind]
	_site = [] if hit == null else CivicHubs.site_near(sim.network, hit)
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or avenue." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.mail.site_problem(sim, _site[0], _site[1]) if post \
			else sim.hubs.site_problem(sim, hk, _site[0], _site[1])
		var cost := Balance.MAIL_COST if post else int(Balance.WASTE_SITES[hk].cost)
		if problem == "" and cost > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(cost)
		var cell: float = Mail.CELL if post else CivicHubs.KINDS[hk].cell
		var box := BoxMesh.new()
		box.size = Vector3(cell * 3.0, 3.0, cell * 2.0)
		_ghost.mesh = box
		_ghost.position = Terrain.lift(_site[0] - _site[1] * cell) + Vector3(0, 1.5, 0)
		_ghost.basis = Basis.looking_at(_site[1], Vector3.UP)
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


## The ghost of a rail yard: its tracks' whole length beside the road.
func _rail_ghost(hit) -> void:
	_site = [] if hit == null else Rail.site_near(sim.network, hit)
	_ghost.visible = not _site.is_empty()
	var problem := "Move next to a street or road." if _site.is_empty() else ""
	if not _site.is_empty():
		problem = sim.rail.site_problem(sim, _site[0], _site[1], _site[2])
		if problem == "" and Balance.RAIL_DEPOT_COST > sim.economy.money:
			problem = "Not enough money: costs $%s." % CitySim.money_text(Balance.RAIL_DEPOT_COST)
		var box := BoxMesh.new()
		box.size = Vector3(Rail.YARD_LEN + Rail.LADDER * 2.0, 2.0, Rail.YARD_DEPTH)
		_ghost.mesh = box
		_ghost.position = Terrain.lift(_site[0]) + Vector3(0, 1.0, 0)
		_ghost.basis = Basis(_site[2], Vector3.UP, -_site[1])
		_ghost.material_override = _ok_mat if problem == "" else _bad_mat
	if problem != _problem:
		_problem = problem
		_update_hint()


func _update_hint() -> void:
	if kind == OFF:
		return
	if kind == Rail.TOOL_KIND:
		var rt := "Rail depot: $%s. A railroad with its own money and leader: it plans track to the region and to" \
			% CitySim.money_text(Balance.RAIL_DEPOT_COST)
		rt += " the companies that ship by rail, and asks your permission (the bell) before it builds. Needs %d m of" \
			% int(Rail.YARD_LEN + Rail.LADDER * 2.0)
		rt += " fairly straight road frontage."
		if _problem != "":
			rt += "\n" + _problem
		hint_changed.emit(rt)
		return
	if kind == Mail.TOOL_KIND:
		var pt := "Post office: $%s to build, $%s a month. " % [CitySim.money_text(Balance.MAIL_COST),
			CitySim.money_text(Balance.MAIL_UPKEEP)]
		pt += "Its postmaster plans the routes and sends carriers to every street's mailboxes. Good mail makes" \
			+ " homes and shops a little happier, and the office grows next door as the town gets busy."
		if _problem != "":
			pt += "\n" + _problem
		hint_changed.emit(pt)
		return
	if CivicHubs.TOOL_KINDS.has(kind):
		var hk: String = CivicHubs.TOOL_KINDS[kind]
		var w: Dictionary = Balance.WASTE_SITES[hk]
		var t := "%s: $%s to build, $%s a month. " % [CivicHubs.KINDS[hk].name, CitySim.money_text(int(w.cost)),
			CitySim.money_text(int(w.upkeep))]
		t += {"landfill": "Never fills up. Its trucks collect the town's trash. Land within half a mile is worth up to 15% less.",
			"recycling_1": "Never fills up. Its trucks collect the town's trash; it hurts land value far less than a landfill.",
			"cemetery": "Never fills up. Land around it is worth a little more."}[hk]
		t += " It grows into free land next door as it's needed."
		if _problem != "":
			t += "\n" + _problem
		hint_changed.emit(t)
		return
	var s: Dictionary = Services.KINDS[kind]
	var text := "%s: $%s to build, $%s a month." % [s.name, CitySim.money_text(s.cost), CitySim.money_text(s.upkeep)]
	if s.has("transit"):
		text = "%s: $%s to build, with two buses. You set how much the city funds it (click it); it plans its own stops, routes, fleet and fare, and buys the land next door as it grows." % [s.name, CitySim.money_text(s.cost)]
	elif s.get("hub", false):
		text += " Its superintendent lays mains and sewers, drills wells and builds plants on their own. You set its subsidy."
	elif s.has("reach"):
		text += " Covers homes within %.1f road miles (green)." % (s.reach / 1609.0)
	else:
		text += " Serves about %s homes along connected roads." % CitySim.money_text(s.capacity)
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
