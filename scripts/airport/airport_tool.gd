class_name AirportTool
extends Node3D
## Places an airport the way Brawn asked: a grass strip whose manager grows
## it when it pays. While placing, the ground shows the land every size
## would need under FAA rules (the runway's clear area, the building area
## and the protection zone off each end), green where there's room today
## and amber where something is in the way, so a new player can see whether
## this spot could ever become a regional or international airport.
## [ and ] turn the runway in 10 degree steps (runways are numbered by
## heading to the nearest 10 degrees).

signal active_changed(on: bool)
signal hint_changed(text: String)

const OK := Color(0.3, 0.75, 1.0)
const BAD := Color(1.0, 0.3, 0.25)
const ROOM := Color(0.45, 0.85, 0.45)
const BLOCKED := Color(1.0, 0.72, 0.25)

var sim: CitySim
var cam: CityCamera
var active := false

var _mesh := MeshInstance3D.new()
var _lane := MeshInstance3D.new()
var _labels: Array[Label3D] = []
var _turn := 0.0  # extra degrees on top of following the road
var _site := {}
var _ok := false
var _problem := ""
var _status := []  # per tier: blockers Dictionary
var _corr := []
var _corr_dirty := true
var _last_key := ""
var _wait := 0.0


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera
	sim.network.changed.connect(func(): _corr_dirty = true)


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	_lane.material_override = m
	for mi in [_mesh, _lane]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
	for t in Airports.TIERS.size():
		var l := RegionView._label(Color.WHITE, 30)
		l.visible = false
		add_child(l)
		_labels.append(l)


func set_active(on: bool) -> void:
	active = on
	_mesh.visible = false
	_lane.visible = false
	for l in _labels:
		l.visible = false
	_last_key = ""
	active_changed.emit(on)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT:
			_turn = fposmod(_turn + (10.0 if k == KEY_BRACKETRIGHT else -10.0), 180.0)
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_active(false)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and _ok:
		sim.apply({"type": "place_airport", "pos": [_site.pos.x, _site.pos.z], "dir": [_site.dir.x, _site.dir.z],
			"side": _site.side})
		_last_key = ""


func _process(delta: float) -> void:
	if not active:
		return
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	var hover := Vector3(hit.x, 0.0, hit.z)
	# The runway lines up with the nearest road, its hangars on the road side.
	var reach: float = Airports.TIERS[0].rofa * Airports.FT * 0.5 + Airports.TIERS[0].side.y + Airports.MAX_DRIVE
	var near := sim.network.find_segment_near(hover, reach, 1.0)
	var dir := Vector3.RIGHT
	if not near.is_empty():
		var c := sim.network.curve_of(near.seg)
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
		tan.y = 0.0
		if tan.length() > 0.01:
			dir = tan.normalized()
	dir = dir.rotated(Vector3.UP, deg_to_rad(_turn))
	if dir.x < 0.0 or (is_zero_approx(dir.x) and dir.z > 0.0):
		dir = -dir
	var side := 1
	if not near.is_empty():
		var to_road: Vector3 = near.point - hover
		side = 1 if to_road.dot(Vector3(-dir.z, 0.0, dir.x)) >= 0.0 else -1
	_site = {"pos": hover, "dir": dir, "side": side, "tier": 0}
	_wait -= delta
	var key := "%d,%d,%d,%d" % [roundi(hover.x / 4.0), roundi(hover.z / 4.0), roundi(_turn), side]
	if key != _last_key and _wait <= 0.0:
		_last_key = key
		_wait = 0.12
		_check()
		_draw_plan()


## What's in the way of each size here (the slow part, so not every frame).
func _check() -> void:
	if _corr_dirty:
		_corr = RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)
		_corr_dirty = false
	_status = []
	for t in Airports.TIERS.size():
		_status.append(sim.airports.blockers(sim, _site, t, _corr))
	var problem := sim.airports.problem(sim, _site, _corr)
	if problem == "" and Balance.AIRPORT_COST > sim.economy.money:
		problem = "Not enough money: costs $%s." % CitySim.money_text(Balance.AIRPORT_COST)
	_ok = problem == ""
	if problem != _problem or true:
		_problem = problem
		_update_hint()


func _draw_plan() -> void:
	if _status.size() != Airports.TIERS.size():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Biggest first, so the smaller ones draw on top.
	for t in range(Airports.TIERS.size() - 1, -1, -1):
		var col: Color = (OK if _ok else BAD) if t == 0 else (ROOM if _status[t].is_empty() else BLOCKED)
		var y := 0.3 + (3 - t) * 0.05
		var fill := 0.35 if t == 0 else 0.12
		for poly in Airports.owned(_site, t):
			_fill(st, poly, Color(col, fill), y)
			_outline(st, poly, Color(col, 0.95), y + 0.02, 2.0 + t * 3.0)
		for end in [1, -1]:
			var z := Airports.rpz(_site, t, end)
			_fill(st, z, Color(col, fill * 0.5), y)
			_outline(st, z, Color(col, 0.7), y + 0.02, 1.5 + t * 2.0)
		var tip := Airports.at(_site, Airports.half_len(t) + Airports.TIERS[t].beyond * Airports.FT, 0.0)
		var l := _labels[t]
		l.position = tip + Vector3(0, 6.0 + Terrain.ground_y(tip.x, tip.z), 0)
		l.modulate = col
		l.text = "%s · %s ft%s" % [Airports.TIERS[t].name, CitySim.money_text(int(Airports.TIERS[t].runway)),
			"" if t == 0 else (" · room" if _status[t].is_empty() else " · blocked")]
		l.visible = true
	# The runway itself.
	var k: Dictionary = Airports.TIERS[0]
	var hw: float = k.width * Airports.FT * 0.5
	_fill(st, Airports._rect(_site, -Airports.half_len(0), Airports.half_len(0), -hw, hw),
		Color(0.35, 0.75, 0.3, 0.75) if _ok else Color(BAD, 0.6), 0.6)
	_mesh.mesh = Terrain.drape(st.commit(), true, 25.0)
	_mesh.visible = true
	var drive := Airports.make_drive(sim.network, _site, 0)
	_lane.visible = drive.size() >= 2
	if _lane.visible:
		var ls := SurfaceTool.new()
		ls.begin(Mesh.PRIMITIVE_TRIANGLES)
		ls.set_color(Color(1.0, 0.9, 0.4, 0.9))
		RoadMesh.add_strip(ls, PackedVector3Array(drive), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.7)
		_lane.mesh = Terrain.drape(ls.commit(), true, 8.0)


static func _fill(st: SurfaceTool, poly: PackedVector2Array, col: Color, y: float) -> void:
	st.set_color(col)
	for i in range(1, poly.size() - 1):
		for q in [poly[0], poly[i], poly[i + 1]]:
			st.add_vertex(Vector3(q.x, y, q.y))


static func _outline(st: SurfaceTool, poly: PackedVector2Array, col: Color, y: float, w: float) -> void:
	st.set_color(col)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := (b - a).orthogonal().normalized() * w * 0.5
		var quad := [a - n, b - n, b + n, a + n]
		for j in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(Vector3(quad[j].x, y, quad[j].y))


func _update_hint() -> void:
	if not active:
		return
	var text := "Airport ($%s): a grass strip for crop dusters and private planes. Its manager paves it and grows it when it pays and the land is clear. [ ] turn the runway." \
		% CitySim.money_text(Balance.AIRPORT_COST)
	if not _site.is_empty() and _status.size() == Airports.TIERS.size():
		var room := []
		for t in range(1, Airports.TIERS.size()):
			var b: Dictionary = _status[t]
			room.append("%s: %s" % [Airports.TIERS[t].name, "room" if b.is_empty() else Airports.describe_blockers(b)])
		text += "\nRunway %s. Room to grow: %s." % [Airports.runway_name(_site), " · ".join(room)]
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
