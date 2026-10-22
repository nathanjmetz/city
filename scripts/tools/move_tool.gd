class_name MoveTool
extends Node3D
## Move It, like the Cities: Skylines 1 mod and CS2's built-in tool: click
## something you placed to pick it up (Shift adds more), drag to slide it,
## , and . to turn it, Page Up and Page Down to raise or lower roads, and
## Ctrl+Z to undo. Homes, shops, fields and pads grew on their own and stay
## theirs. Every move goes through CitySim.apply (see MoveIt).

signal active_changed(on: bool)
signal hint_changed(text: String)

const TURN_STEP := 15.0
const FINE_TURN := 1.0
const DRAG_MIN := 0.5
const OK_COLOR := Color(Brand.BRAND_MINT, 0.9)
const BAD_COLOR := Color(Brand.CRITICAL, 0.9)
const HOVER_COLOR := Color(1, 1, 1, 0.55)
const FROM_COLOR := Color(1, 1, 1, 0.3)
## How strongly a picked-up thing is tinted, against its outline.
const FILL := 0.35

var sim: CitySim
var cam: CityCamera
var active := false
## What's picked up: [{type, id}].
var selection: Array = []

var _undo: Array = []
var _hover := {}
var _grown := false  # hovering something that grew on its own
var _drag_from = null  # ground point where a drag began, or null
var _offset := Vector3.ZERO
var _plan := {}
var _problem := ""
var _mesh := ImmediateMesh.new()
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _lines := MeshInstance3D.new()


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	cam = camera


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lines.mesh = _mesh
	_lines.material_override = m
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	selection.clear()
	_drag_from = null
	_mesh.clear_surfaces()
	active_changed.emit(active)
	_update_hint()


func clear_selection() -> void:
	selection.clear()
	_drag_from = null
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.keycode == KEY_M and not k.ctrl_pressed and not k.meta_pressed:
			set_active(not active)
			get_viewport().set_input_as_handled()
			return
		if not active:
			return
		var fine := FINE_TURN if k.shift_pressed else TURN_STEP
		match k.keycode:
			KEY_COMMA: _commit(Vector3.ZERO, -fine, 0.0)
			KEY_PERIOD: _commit(Vector3.ZERO, fine, 0.0)
			KEY_PAGEUP: _commit(Vector3.ZERO, 0.0, RoadTool.ELEVATION_STEP)
			KEY_PAGEDOWN: _commit(Vector3.ZERO, 0.0, -RoadTool.ELEVATION_STEP)
			KEY_Z:
				if k.ctrl_pressed or k.meta_pressed:
					undo()
				else:
					return
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed:
		var hit = cam.mouse_ground_point()
		if mb.pressed and hit != null:
			var item := MoveIt.pick(sim, hit)
			if item.is_empty():
				if not mb.shift_pressed:
					selection.clear()
			elif _index(item) == -1:
				if not mb.shift_pressed:
					selection.clear()
				selection.append(item)
			elif mb.shift_pressed:
				selection.remove_at(_index(item))
				item = {}
			if not item.is_empty():
				_drag_from = hit
				_offset = Vector3.ZERO
				_plan = {}
				_problem = ""
			_update_hint()
		elif not mb.pressed and _drag_from != null:
			_drag_from = null
			if _offset.length() > DRAG_MIN:
				_commit(_offset, 0.0, 0.0)
			_plan = {}
			_problem = ""
			_update_hint()
		get_viewport().set_input_as_handled()
	elif mb != null and mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		if selection.is_empty():
			set_active(false)
		else:
			clear_selection()


## Puts the last move back.
func undo() -> void:
	while not _undo.is_empty():
		var cmd: Dictionary = _undo.pop_back()
		if MoveIt.plan(sim, cmd).problem == "" and sim.apply(cmd):
			_prune()
			return
	_problem = "Nothing to undo."
	_update_hint()


func _commit(offset: Vector3, turn: float, raise: float) -> void:
	_prune()
	if selection.is_empty():
		return
	if raise != 0.0 and not _has_roads():
		_problem = "Only roads go up and down. Buildings stay on the ground."
		_update_hint()
		return
	var cmd := MoveIt.command(selection, MoveIt.centre(sim, selection), offset, turn, raise)
	var plan := MoveIt.plan(sim, cmd)
	_problem = plan.problem
	if _problem == "" and sim.apply(cmd):
		_undo.append(MoveIt.inverse(cmd))
		if _undo.size() > 50:
			_undo.pop_front()
		_prune()
	_update_hint()


func _process(_delta: float) -> void:
	if not active:
		return
	var hit = cam.mouse_ground_point()
	if _drag_from != null and hit != null:
		var off: Vector3 = hit - _drag_from
		off.y = 0.0
		if off.distance_to(_offset) > 0.2:
			_offset = off
			_plan = MoveIt.plan(sim, MoveIt.command(selection, MoveIt.centre(sim, selection), _offset))
			if _problem != _plan.problem:
				_problem = _plan.problem
				_update_hint()
	var hover := {} if hit == null or _drag_from != null else MoveIt.pick(sim, hit)
	var grown := hit != null and hover.is_empty() and _drag_from == null and not Inspect.pick(sim, hit).is_empty()
	if grown != _grown:
		_grown = grown
		_update_hint()
	_hover = hover
	_redraw()


# --- Drawing: outlines on the ground ----------------------------------------

func _redraw() -> void:
	_prune()
	_mesh.clear_surfaces()
	_verts.clear()
	_cols.clear()
	var any := false
	var dragging := _drag_from != null and _offset.length() > DRAG_MIN
	if not _hover.is_empty() and _index(_hover) == -1:
		any = _outline(_hover, HOVER_COLOR, Vector3.ZERO) or any
	for item in selection:
		if dragging:
			any = _outline(item, FROM_COLOR, Vector3.ZERO) or any
		else:
			any = _outline(item, OK_COLOR, Vector3.ZERO) or any
	if dragging:
		var col := OK_COLOR if _problem == "" else BAD_COLOR
		if _problem == "" and _plan.has("curves"):
			# Every road the move reshapes, and anything shifted out of the way.
			for id in _plan.curves:
				var c: Array = _plan.curves[id]
				_road_band(c, RoadStyle.half_width(sim.network.segments[id].type), col)
				any = true
			for t in MoveIt.BUILDINGS:
				var group: Dictionary = _plan[MoveIt._group(t)]
				for id in group:
					_poly(MoveIt.footprint(t, MoveIt._kind(sim, t, id), group[id][0], group[id][1]), col)
					any = true
		else:
			for item in selection:
				any = _outline(item, col, _offset) or any
	if not any or _verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _verts.size():
		_mesh.surface_set_color(_cols[i])
		_mesh.surface_add_vertex(_verts[i])
	_mesh.surface_end()


## Outlines one thing, slid by `offset`.
func _outline(item: Dictionary, col: Color, offset: Vector3) -> bool:
	if not MoveIt.exists(sim, item):
		return false
	match item.type:
		"road":
			var c := sim.network.curve_of(item.id)
			_road_band([c[0] + offset, c[1] + offset, c[2] + offset],
				RoadStyle.half_width(sim.network.segments[item.id].type), col)
		"node":
			var p: Vector3 = sim.network.nodes[item.id] + offset
			var r := RoadStyle.half_width(sim.network.widest_at(item.id)) + 1.0
			var ring := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				ring.append(Vector2(p.x + cos(a) * r, p.z + sin(a) * r))
			_poly(ring, col, p.y)
		"service":
			var b: Dictionary = sim.services.buildings[item.id]
			_poly(MoveIt.footprint("service", b.kind, b.pos + offset, b.dir), col)
		"warehouse":
			var w: Dictionary = sim.warehouses.buildings[item.id]
			_poly(MoveIt.footprint("warehouse", w, w.pos + offset, w.dir), col)
		"hub":
			var h: Dictionary = sim.hubs.hubs[item.id]
			_poly(MoveIt.footprint("hub", h, h.pos + offset, h.dir), col)
		"farm":
			var f: Dictionary = sim.farms.farms[item.id]
			_poly(MoveIt.footprint("farm", null, f.pos + offset, f.dir), col)
		"industry":
			var s: Dictionary = sim.industry.sites[item.id]
			_poly(MoveIt.footprint("industry", null, s.pos + offset, s.dir), col)
	return true


func _road_band(c: Array, hw: float, col: Color) -> void:
	var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], 24)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in pts.size():
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], float(i) / (pts.size() - 1))
		tan.y = 0.0
		var n := Vector3(-tan.z, 0.0, tan.x).normalized() * hw
		left.append(pts[i] - n)
		right.append(pts[i] + n)
	var fill := Color(col, col.a * FILL)
	for i in pts.size() - 1:
		for v in [left[i], right[i], right[i + 1], left[i], right[i + 1], left[i + 1]]:
			_add(v, fill)
	_ribbon(left, col)
	_ribbon(right, col)


func _poly(poly: PackedVector2Array, col: Color, y := 0.0) -> void:
	var fill := Color(col, col.a * FILL)
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in tris:
		_add(Vector3(poly[i].x, y, poly[i].y), fill)
	var pts := PackedVector3Array()
	for q in poly:
		pts.append(Vector3(q.x, y, q.y))
	pts.append(pts[0])
	_ribbon(pts, col)


## A flat line, lifted just off the ground, wider as the camera pulls back.
func _ribbon(pts: PackedVector3Array, col: Color) -> void:
	var w := clampf(cam.camera.global_position.y * 0.0035, 0.35, 3.0)
	for i in pts.size() - 1:
		var a := pts[i] + Vector3(0, 0.6, 0)
		var b := pts[i + 1] + Vector3(0, 0.6, 0)
		var d := b - a
		d.y = 0.0
		if d.length() < 0.001:
			continue
		var n := Vector3(-d.z, 0.0, d.x).normalized() * w
		for v in [a - n, a + n, b + n, a - n, b + n, b - n]:
			_verts.append(v)
			_cols.append(col)


func _add(v: Vector3, col: Color) -> void:
	_verts.append(v + Vector3(0, 0.5, 0))
	_cols.append(col)


# --- Helpers ----------------------------------------------------------------

func _index(item: Dictionary) -> int:
	for i in selection.size():
		if selection[i].type == item.type and selection[i].id == item.id:
			return i
	return -1


func _has_roads() -> bool:
	for it in selection:
		if it.type in ["road", "node"]:
			return true
	return false


## Drops things that are gone (a road rebuilt to meet another gets a new id).
func _prune() -> void:
	selection = selection.filter(func(it): return MoveIt.exists(sim, it))


func _update_hint() -> void:
	if not active:
		hint_changed.emit("")
		return
	var text := "Move It: click a road, junction or building you placed to pick it up (Shift adds more)."
	if not selection.is_empty():
		text = "Drag to slide   ,  .  turn (Shift: 1°)   Page Up/Down raise roads   Ctrl+Z undo"
	if _grown:
		text += "\nHomes, shops, fields and pads grew on their own, so they stay put."
	if _problem != "":
		text += "\n" + _problem
	hint_changed.emit(text)
