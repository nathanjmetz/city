class_name RoadTool
extends Node3D
## Lets the player draw and remove roads with the mouse.
##
## Straight: click start, click end (keeps going from the end).
## Curved: click start, click the bend, click end.
## Grid: a rectangle by default, like CS2: click a corner, click the end of
## the first side (it snaps parallel or square to the nearest road), then
## move out and click to set the depth. Tab switches to Any shape: click the
## corners of any shape, then the first corner again (or Enter). Either way
## the grid fits the roads already there (see GridFill). Backspace takes back
## a corner, Shift+Tab turns a free shape's grid, [ and ] set the block length.
## Roundabout: click to place. [ and ] change the size.
## Upgrade: click a road to change it to the chosen road type.
## Bulldoze: click a road to remove it.
## Page Up / Page Down (or the buttons): raise or lower new roads, for
## bridges, overpasses and tunnels.
## P: parallel mode, which draws a second road alongside ([ ] set the gap).
## Straight roads snap to right angles and straight-on with the road they
## start from, and show a guide line and their length while drawing.
## Right click or Esc stops the current road.

signal mode_changed(mode: int)
signal hint_changed(text: String)
## Road type or parallel mode changed.
signal options_changed

enum Mode { NONE, STRAIGHT, CURVED, BULLDOZE, GRID, ROUNDABOUT, UPGRADE }

const SNAP_NODE := 9.0
## A rectangle lines up with a road this close to its first corner.
const RECT_ALIGN_REACH := 250.0
## A rectangle needs both sides at least this long to be built.
const RECT_MIN := 20.0
const SNAP_ROAD := 7.0
## Straight roads snap to 15 degree steps while Shift is held.
const ANGLE_STEP := deg_to_rad(15.0)
## Guide lines catch the mouse within this angle.
const GUIDE_SNAP := deg_to_rad(4.0)
const PARALLEL_MAX := 200.0
const ELEVATION_STEP := 2.5
const ELEVATION_MIN := -20.0
const ELEVATION_MAX := 30.0

var sim: CitySim
var network: RoadNetwork
var cam: CityCamera
var mode := Mode.STRAIGHT
## The last drawing mode picked (straight, curve, grid, roundabout or
## upgrade). Putting the tool away and taking it out again brings it back,
## with the same road type and options, as in CS2 (Brawn's ask).
var last_draw := Mode.STRAIGHT
var grid_block := 120.0
## Spacing of the streets parallel to the first side.
var grid_across := RoadShapes.GRID_ACROSS
## Index into GridFill.PRESETS, or -1 once [ ] has changed the size.
var grid_preset := -1
## Which side of the shape the grid runs square to.
var grid_side := 0
## Any shape instead of a rectangle.
var grid_free := false
var roundabout_radius := 20.0
var road_type := 0
var parallel := false
var parallel_gap := RoadShapes.GRID_ACROSS
## Height new road points are placed at, in metres above the ground.
var elevation := 0.0

var _points: Array[Vector3] = []
var _preview := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
## The ghost road: bright, drawn over trees and hills, and never thinner on
## screen than GHOST_PX however far out the camera is (as in CS2).
var _ok_mat := RoadStyle.material(Color(0.3, 0.85, 1.0, 0.85), true)
var _bad_mat := RoadStyle.material(Color(1.0, 0.3, 0.25, 0.75), true)
var _dot_mat := RoadStyle.material(Color(1.0, 1.0, 1.0, 0.95), true)
const FT := 3.28084  # feet in a metre: the readouts are in US units
const GHOST_PX := 14.0  # least on-screen width of the ghost road
const LINE_PX := 3.0    # least width of outlines and the centre line
const DOT_PX := 9.0     # radius of the clicked-point markers
const CURSOR_PX := 16.0 # radius of the cursor ring
var _dots := MeshInstance3D.new()
var _centre := MeshInstance3D.new()  # the ghost road's centre line
var _px := 0.1  # metres per screen pixel where the cursor is
var _hover_seg := -1
var _hover_service := -1
var _hover_warehouse := -1
var _hover_farm := -1
var _hover_park := -1
var _shown_problem := ""
var _guide := MeshInstance3D.new()
var _label := Label3D.new()
var _guide_mat := RoadStyle.material(Color(1, 1, 1, 0.45), true)
## Angle of the guide the current road snapped to, or NAN.
var _guide_angle := NAN
var _guide_kind := ""
var _left_down := false  # the left button went down on the map, not on a panel
## The last grid plan, kept while the shape and cursor stay put.
var _grid_key := ""
var _grid_plan := []
var _grid_planned_at := -1000


func setup(s: CitySim, camera: CityCamera) -> void:
	sim = s
	network = s.network
	cam = camera


func _ready() -> void:
	add_child(_preview)
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 3.0
	ring.rings = 24
	_cursor.mesh = ring
	_cursor.material_override = _ok_mat
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)
	_dot_mat.render_priority = 1  # over the ghost road
	_centre.material_override = _dot_mat
	_centre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_centre)
	_dots.material_override = _dot_mat
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	_guide.material_override = _guide_mat
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	# Small and compact beside the cursor, like CS2's tool readout.
	_label.pixel_size = 0.0005
	_label.font_size = 30
	_label.outline_size = 10
	_label.font = Brand.font("ui", 600)
	_label.offset = Vector2(0, 90)  # just above the cursor ring
	_label.no_depth_test = true
	add_child(_label)
	set_mode(mode)


func change_elevation(steps: int) -> void:
	elevation = clampf(elevation + steps * ELEVATION_STEP, ELEVATION_MIN, ELEVATION_MAX)
	options_changed.emit()
	_update_hint()


func set_parallel(on: bool) -> void:
	parallel = on
	parallel_gap = maxf(parallel_gap, _min_gap())
	options_changed.emit()
	_update_hint()


func set_road_type(t: int) -> void:
	road_type = t
	options_changed.emit()
	if mode == Mode.NONE or mode == Mode.BULLDOZE:
		set_mode(last_draw)
	_update_hint()


func set_mode(m: int) -> void:
	mode = m
	if m != Mode.NONE and m != Mode.BULLDOZE:
		last_draw = m
	_points.clear()
	_hover_seg = -1
	mode_changed.emit(mode)
	_update_hint()


## Grid keys come before the chat's Enter, while a grid shape is being drawn
## and nobody is typing.
func _input(event: InputEvent) -> void:
	if mode != Mode.GRID or get_viewport().gui_get_focus_owner() != null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_TAB and key.shift_pressed:
		grid_side += 1
	elif key.keycode == KEY_TAB:
		set_grid_free(not grid_free)
	elif _points.is_empty():
		return
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_finish_grid()
	elif key.keycode == KEY_BACKSPACE:
		_points.pop_back()
		_update_hint()
	else:
		return
	get_viewport().set_input_as_handled()


## Picks one of the real-world grid sizes (GridFill.PRESETS).
func set_grid_preset(i: int) -> void:
	grid_preset = i
	grid_block = GridFill.PRESETS[i].block
	grid_across = GridFill.PRESETS[i].across
	if mode != Mode.GRID:
		set_mode(Mode.GRID)
	options_changed.emit()
	_update_hint()


## Switches the grid between a rectangle and any shape.
func set_grid_free(on: bool) -> void:
	grid_free = on
	_points.clear()
	options_changed.emit()
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: set_mode(Mode.STRAIGHT)
			KEY_2: set_mode(Mode.CURVED)
			KEY_3: set_mode(Mode.GRID)
			KEY_4: set_mode(Mode.ROUNDABOUT)
			KEY_B: set_mode(Mode.BULLDOZE)
			KEY_U: set_mode(Mode.UPGRADE)
			KEY_P: set_parallel(not parallel)
			KEY_PAGEUP: change_elevation(1)
			KEY_PAGEDOWN: change_elevation(-1)
			KEY_BRACKETLEFT: _resize(1.0 / 1.2)
			KEY_BRACKETRIGHT: _resize(1.2)
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	# Right click cancels on release, unless it was a drag to move the camera.
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		_cancel()
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed:
		_left_down = true
		_click()
	elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		# A rectangle can be dragged out, corner to corner, as well as clicked;
		# letting go after an Alt-drag of the camera builds nothing.
		if _left_down and mode == Mode.GRID and not grid_free and _points.size() == 1:
			_click()
		_left_down = false


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_preview.visible = false
	_preview.transform = Transform3D.IDENTITY
	_guide.visible = false
	_label.visible = false
	_dots.visible = false
	_centre.visible = false
	_cursor.visible = hit != null and mode != Mode.NONE
	if hit == null or mode == Mode.NONE:
		return
	_px = _metres_per_px(Terrain.lift(hit))
	_cursor.scale = Vector3.ONE * maxf(1.0, CURSOR_PX * _px / 3.0)
	_show_dots()
	if mode == Mode.BULLDOZE or mode == Mode.UPGRADE:
		_preview_pick(hit)
		return
	var p := _snapped(hit)
	_cursor.position = Terrain.lift(p) + Vector3.UP * 0.3
	_cursor.material_override = _ok_mat
	var curves := []
	var ok := true
	if mode == Mode.ROUNDABOUT:
		curves = RoadShapes.roundabout(p, RoadShapes.roundabout_radius(roundabout_radius, road_type))
	elif _points.is_empty():
		return
	elif mode == Mode.GRID:
		_show_grid(p)
		return
	else:
		curves = [_pending_curve(p)]
		_show_length(curves[0])
		if parallel:
			curves.append(RoadShapes.offset(curves[0], parallel_gap))
		var problem := _problem(curves[0])
		ok = problem == ""
		if problem != _shown_problem:
			_shown_problem = problem
			_update_hint()
	if curves.is_empty():
		return
	if mode == Mode.ROUNDABOUT:
		var cost := CitySim.shapes_cost(curves, RoadStyle.ring_type(road_type))
		ok = cost <= sim.economy.money
		_label.text = "$" + CitySim.money_text(cost) + ("" if ok else "\nNot enough money")
		_label.position = Terrain.lift(p) + Vector3(0, 6, 0)
		_label.visible = true
	_preview.mesh = _preview_mesh(curves)
	_preview.material_override = _ok_mat if ok else _bad_mat
	_preview.visible = true


func _click() -> void:
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	match mode:
		Mode.BULLDOZE:
			if _hover_service != -1:
				sim.apply({"type": "remove_service", "id": _hover_service})
				_hover_service = -1
			elif _hover_warehouse != -1:
				sim.apply({"type": "remove_warehouse", "id": _hover_warehouse})
				_hover_warehouse = -1
			elif _hover_farm != -1:
				sim.apply({"type": "remove_farm", "id": _hover_farm})
				_hover_farm = -1
			elif _hover_park != -1:
				sim.apply({"type": "remove_park", "id": _hover_park})
				_hover_park = -1
			elif _hover_seg != -1:
				sim.apply({"type": "remove_road", "seg": _hover_seg})
				_hover_seg = -1
			elif sim.banks.covers(hit):
				# One block of the bank at a time (its first building closes it).
				sim.apply({"type": "remove_bank_block", "pos": [hit.x, hit.z]})
			elif sim.education.covers(hit):
				# One campus building at a time (its first building closes it).
				sim.apply({"type": "remove_campus_block", "pos": [hit.x, hit.z]})
			elif sim.telecom.covers(hit):
				# One tower or block at a time (its office closes the company).
				sim.apply({"type": "remove_telecom_at", "pos": [hit.x, hit.z]})
		Mode.UPGRADE:
			if _hover_seg != -1:
				sim.apply({"type": "upgrade_road", "seg": _hover_seg, "road": road_type})
		Mode.STRAIGHT, Mode.CURVED:
			var p := _snapped(hit)
			var needed := 2 if mode == Mode.STRAIGHT else 3
			if _points.size() + 1 < needed:
				_points.append(p)
			else:
				var curve := _pending_curve(p)
				if _is_valid(curve) and _build(curve):
					if parallel:
						_build(RoadShapes.offset(curve, parallel_gap))
					_points.clear()
					_points.append(curve[2])
		Mode.GRID:
			var p := _grid_corner(_snapped(hit))
			if not grid_free and _points.size() == 1:
				var r := _rect(p)
				# A click without a drag only sets the first corner.
				if _flat_dist(r[0], r[1]) > RECT_MIN and _flat_dist(r[1], r[2]) > RECT_MIN:
					_finish_grid(r)
			elif not grid_free:
				_points.append(p)
			elif _points.size() >= 3 and p.distance_to(_points[0]) < 0.01:
				_finish_grid()
			elif _points.is_empty() or p.distance_to(_points[_points.size() - 1]) > 1.0:
				_points.append(p)
		Mode.ROUNDABOUT:
			sim.apply({"type": "build_roundabout", "center": _xz(_snapped(hit)),
				"radius": roundabout_radius, "road": road_type})
	_update_hint()


## Builds the grid inside the shape drawn so far.
func _finish_grid(shape: Array = _points) -> void:
	if shape.size() < 3:
		return
	var pts := []
	for q in shape:
		pts.append(_xz(q))
	if sim.apply({"type": "build_grid_shape", "points": pts, "block": grid_block, "across": grid_across,
			"side": 0 if not grid_free else grid_side, "road": road_type}):
		_points.clear()
	_update_hint()


## Where the next corner of a grid shape goes: back on the first corner to
## close the shape, the fourth corner of a rectangle, square with the last
## side, or Shift for 15 degree steps.
func _grid_corner(p: Vector3) -> Vector3:
	_guide_angle = NAN
	if _points.is_empty():
		return p
	if not grid_free:
		return _rect_corner(p)
	if _points.size() >= 3 and _flat_dist(p, _points[0]) < SNAP_NODE:
		return _points[0]
	if _points.size() == 3:
		var q: Vector3 = _points[0] + _points[2] - _points[1]
		if _flat_dist(p, q) < SNAP_NODE:
			return q
	if network.find_node_near(p, 0.5) != -1:
		return p  # an old junction wins
	var last: Vector3 = _points[_points.size() - 1]
	var d := p - last
	if Input.is_key_pressed(KEY_SHIFT):
		var ang := snappedf(atan2(d.z, d.x), ANGLE_STEP)
		return last + Vector3(cos(ang), 0.0, sin(ang)) * Vector2(d.x, d.z).length()
	if _points.size() == 1:
		return _pending_curve(p)[2]  # square with the road it starts on
	var prev: Vector3 = _points[_points.size() - 2]
	var ref := atan2(last.z - prev.z, last.x - prev.x)
	var ang := atan2(d.z, d.x)
	for k in 4:
		var g: float = ref + k * PI * 0.5
		if absf(angle_difference(ang, g)) < GUIDE_SNAP:
			return last + Vector3(cos(g), 0.0, sin(g)) * Vector2(d.x, d.z).length()
	return p


## Rectangle mode: the grid is dragged out corner to corner, in any
## direction, with its sides parallel and square to the road it starts on,
## or else the nearest road, or else the compass. A side that ends near a
## junction on its line stops exactly on it.
func _rect_corner(p: Vector3) -> Vector3:
	var a: Vector3 = _points[0]
	var g := _rect_angle(a)
	_guide_angle = g
	_guide_kind = ""
	var u := Vector3(cos(g), 0.0, sin(g))
	var v := Vector3(-u.z, 0.0, u.x)
	var du := (p - a).dot(u)
	var dv := (p - a).dot(v)
	var n := network.find_node_near(a + u * du, SNAP_NODE)
	if n != -1 and absf((network.nodes[n] - a).dot(v)) < 1.0:
		du = (network.nodes[n] - a).dot(u)
	n = network.find_node_near(a + v * dv, SNAP_NODE)
	if n != -1 and absf((network.nodes[n] - a).dot(u)) < 1.0:
		dv = (network.nodes[n] - a).dot(v)
	return a + u * du + v * dv


## Which way a rectangle starting at `a` lines up.
func _rect_angle(a: Vector3) -> float:
	var refs := _reference_angles(a)
	if refs.is_empty():
		var near := network.find_segment_near(a, RECT_ALIGN_REACH, RoadNetwork.SAME_LEVEL)
		if not near.is_empty():
			var c := network.curve_of(near.seg)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
			refs.append(atan2(tan.z, tan.x))
	if refs.is_empty():
		return 0.0  # out in the open, line up with the compass
	return refs[grid_side % refs.size()]  # Shift+Tab: line up with the next road here


## The full rectangle from its first corner to the opposite one.
func _rect(p: Vector3) -> Array:
	var a: Vector3 = _points[0]
	var u := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
	var b := a + u * (p - a).dot(u)
	return [a, b, p, a + (p - b)]


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Shows the shape being drawn and the streets it would get, with the price.
func _show_grid(p: Vector3) -> void:
	p = _grid_corner(p)
	_cursor.position = Terrain.lift(p) + Vector3.UP * 0.3
	var shape: Array = _points.duplicate()
	var closing := shape.size() >= 3 and p.distance_to(shape[0]) < 0.01
	if not grid_free:
		shape = _rect(p)
	elif not closing:
		shape.append(p)
	_show_guide(_points[0])
	var plan := []
	if shape.size() >= 3:
		var key := "%s|%s|%s|%d|%d|%d" % [str(shape), str(grid_block), str(grid_across), grid_side, road_type,
			sim.network.segments.size()]
		# Big towns take a moment to plan, so replan at most a few times a second.
		if key != _grid_key and Time.get_ticks_msec() - _grid_planned_at > 120:
			_grid_key = key
			_grid_plan = GridFill.plan(network, shape, grid_block, road_type, grid_side if grid_free else 0, grid_across)
			_grid_planned_at = Time.get_ticks_msec()
		plan = _grid_plan
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := maxf(RoadStyle.half_width(road_type), GHOST_PX * 0.5 * _px)
	var edge := maxf(0.4, LINE_PX * 0.5 * _px)
	for c in plan:
		RoadMesh.add_strip(st, Terrain.densify(RoadNetwork.sample_curve(c[0], c[1], c[2], 2), 6.0), -hw, hw, 0.2)
	for c in GridFill.outline(shape, shape.size() >= 3):
		RoadMesh.add_strip(st, Terrain.densify(RoadNetwork.sample_curve(c[0], c[1], c[2], 2), 6.0), -edge, edge, 0.35)
	var cost := CitySim.shapes_cost(plan, road_type)
	var ok := cost <= sim.economy.money
	var dims := ""
	if shape.size() >= 2:
		dims = "%s ft" % CitySim.money_text(roundi(_flat_dist(shape[0], shape[1]) * FT))
	if not grid_free and shape.size() == 4:
		dims += " × %s ft" % CitySim.money_text(roundi(_flat_dist(shape[1], shape[2]) * FT))
	if not is_nan(_guide_angle):
		dims += "  " + _guide_kind
	if not plan.is_empty() or dims != "":
		_label.text = dims
		if not plan.is_empty():
			_label.text += "\n%d streets  $%s" % [plan.size(), CitySim.money_text(cost)] \
				+ ("" if ok else "\nNot enough money")
		_label.position = Terrain.lift(p) + Vector3(0, 6, 0)
		_label.visible = true
	_preview.mesh = Terrain.drape(st.commit())
	_preview.material_override = _ok_mat if ok else _bad_mat
	_preview.visible = true


## Draws the guide line the grid's side snapped to, through `at`.
func _show_guide(at: Vector3) -> void:
	if is_nan(_guide_angle):
		return
	var dir := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.add_strip(st, Terrain.densify(PackedVector3Array([at - dir * 400.0, at + dir * 400.0]), 6.0), -0.25, 0.25, 0.3)
	_guide.mesh = Terrain.drape(st.commit(), true)
	_guide.visible = true


func _resize(f: float) -> void:
	if mode == Mode.GRID:
		grid_block = clampf(grid_block * f, GridFill.BLOCK_MIN, GridFill.BLOCK_MAX)
		grid_across = clampf(grid_across * f, GridFill.ACROSS_MIN, GridFill.BLOCK_MAX)
		grid_preset = -1
		options_changed.emit()
	elif mode == Mode.ROUNDABOUT:
		roundabout_radius = clampf(roundabout_radius * f, RoadShapes.ROUNDABOUT_MIN, RoadShapes.ROUNDABOUT_MAX)
	elif parallel and (mode == Mode.STRAIGHT or mode == Mode.CURVED):
		parallel_gap = clampf(parallel_gap * f, _min_gap(), PARALLEL_MAX)
	else:
		return
	_update_hint()


func _build(curve: Array) -> bool:
	return sim.apply({"type": "build_road", "start": _xz(curve[0]), "ctrl": _xz(curve[1]),
		"end": _xz(curve[2]), "road": road_type})


## Closest two roads can run side by side: sidewalk to sidewalk.
func _min_gap() -> float:
	return RoadStyle.right_of_way_half(road_type) * 2.0


static func _xz(v: Vector3) -> Array:
	return [v.x, v.z, v.y]


## True while a road is half drawn.
func is_drawing() -> bool:
	return not _points.is_empty()


## Drops the road being drawn (Esc and right click).
func cancel() -> void:
	_cancel()


func _cancel() -> void:
	_points.clear()
	_update_hint()


## Start, control point and end of the road being drawn, ending at p.
func _pending_curve(p: Vector3) -> Array:
	var a: Vector3 = _points[0]
	if mode == Mode.CURVED and _points.size() >= 2:
		var bend: Vector3 = _points[1]
		bend.y = lerpf(a.y, p.y, 0.5)
		return [a, bend, p]
	var d := p - a
	_guide_angle = NAN
	if mode != Mode.CURVED and Input.is_key_pressed(KEY_SHIFT):
		var ang := snappedf(atan2(d.z, d.x), ANGLE_STEP)
		p = a + Vector3(cos(ang), 0.0, sin(ang)) * d.length()
	elif mode != Mode.CURVED and d.length() > 2.0:
		# Snap to straight on or square with the road we start from.
		var ang := atan2(d.z, d.x)
		for ref in _reference_angles(a):
			for k in 4:
				var g: float = ref + k * PI * 0.5
				if absf(angle_difference(ang, g)) < GUIDE_SNAP:
					_guide_angle = g
					_guide_kind = "straight on" if k % 2 == 0 else "90°"
					p = a + Vector3(cos(g), 0.0, sin(g)) * d.length()
					break
			if not is_nan(_guide_angle):
				break
	return [a, a.lerp(p, 0.5), p]


## Directions of the roads at a point, for guide lines.
func _reference_angles(at: Vector3) -> Array:
	var out := []
	var n := network.find_node_near(at, 0.5)
	if n != -1:
		for id in network.segments_at(n):
			var c := network.curve_of(id)
			var t := 0.0 if network.segments[id].a == n else 1.0
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
			out.append(atan2(tan.z, tan.x))
		return out
	var s := network.find_segment_near(at, 0.5)
	if not s.is_empty():
		var c := network.curve_of(s.seg)
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], s.t)
		out.append(atan2(tan.z, tan.x))
	return out


## Shows the road's length by the cursor, and the guide line it snapped to.
func _show_length(curve: Array) -> void:
	var pts := RoadNetwork.sample_curve(curve[0], curve[1], curve[2])
	var m := RoadNetwork.polyline_length(pts)
	_label.text = "%s ft  ·  $%s" % [CitySim.money_text(roundi(m * FT)),
		CitySim.money_text(Economy.road_cost(curve, road_type) * (2 if parallel else 1))]
	var r := RoadNetwork.min_radius(curve[0], curve[1], curve[2])
	if r < 2000.0:
		_label.text += "\nCurve safe at %d mph" % RoadStyle.safe_speed_mph(r)
	if absf(curve[2].y) > 0.1 or absf(curve[0].y) > 0.1:
		var flat := Vector2(curve[2].x - curve[0].x, curve[2].z - curve[0].z).length()
		_label.text += "\nHeight %+d ft, grade %d%%" % [roundi(curve[2].y * FT),
			roundi(absf(curve[2].y - curve[0].y) / maxf(flat, 0.1) * 100.0)]
	if not is_nan(_guide_angle):
		_label.text += "\n" + _guide_kind
		var dir := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var line := PackedVector3Array([curve[0] - dir * 400.0, curve[0] + dir * 400.0])
		var g := maxf(0.25, LINE_PX * 0.5 * _px)
		RoadMesh.add_strip(st, line, -g, g, 0.3)
		_guide.mesh = Terrain.drape(st.commit(), true, 8.0)
		_guide.visible = true
	_label.position = Terrain.lift(curve[2]) + Vector3(0, 6, 0)
	_label.visible = true


func _is_valid(curve: Array) -> bool:
	return _problem(curve) == ""


## Why a road can't be built, or "" if it can (the simulation's own rules).
func _problem(curve: Array) -> String:
	return sim.road_problem(curve, road_type)


func _snapped(hit: Vector3) -> Vector3:
	if mode == Mode.CURVED and _points.size() == 1:
		return Vector3(hit.x, 0.0, hit.z)  # the bend point floats freely
	if mode == Mode.GRID:
		var snap := network.snap(hit, SNAP_NODE, SNAP_ROAD)
		return Vector3(snap.pos.x, 0.0, snap.pos.z)  # grids are built on the ground
	var snap := network.snap(hit, SNAP_NODE, SNAP_ROAD)
	if snap.kind == "free":
		return Vector3(hit.x, elevation, hit.z)
	return snap.pos


func _preview_mesh(curves: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := RoadStyle.half_width(RoadStyle.ring_type(road_type) if mode == Mode.ROUNDABOUT else road_type)
	hw = maxf(hw, GHOST_PX * 0.5 * _px)
	var line := LINE_PX * 0.5 * _px
	for curve in curves:
		var pts := Terrain.densify(RoadNetwork.sample_curve(curve[0], curve[1], curve[2]), 6.0)
		RoadMesh.add_strip(st, pts, -hw, hw, 0.2)
	# A white centre line on top, so the ghost reads over light ground too.
	var centre := SurfaceTool.new()
	centre.begin(Mesh.PRIMITIVE_TRIANGLES)
	for curve in curves:
		var pts := Terrain.densify(RoadNetwork.sample_curve(curve[0], curve[1], curve[2]), 6.0)
		RoadMesh.add_strip(centre, pts, -line, line, 0.3)
	_centre.mesh = Terrain.drape(centre.commit())
	_centre.visible = true
	return Terrain.drape(st.commit())


## Metres covered by one screen pixel at a point, so markers can keep their
## size on screen at any zoom.
func _metres_per_px(at: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.1
	var dist := camera.global_position.distance_to(at)
	return 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) / maxf(get_viewport().get_visible_rect().size.y, 1.0)


## A white dot on every point already clicked (the road's start, a curve's
## bend, the grid's corners), the same size on screen at any zoom.
func _show_dots() -> void:
	if _points.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in _points:
		var at := Terrain.lift(Vector3(q.x, 0.0, q.z))
		RoadMesh.add_disc(st, Vector3(at.x, at.y + q.y, at.z), DOT_PX * _metres_per_px(at), 0.5, 20)
	_dots.mesh = st.commit()
	_dots.visible = true


## Highlights the road under the mouse: red to bulldoze, blue to upgrade.
func _preview_pick(hit: Vector3) -> void:
	var near := network.find_segment_near(hit, RoadStyle.half_width(RoadStyle.Type.BOULEVARD))
	_hover_seg = -1
	if not near.is_empty() and near.dist <= RoadStyle.half_width(network.segments[near.seg].type) + 2.0:
		_hover_seg = near.seg
	var mat := _bad_mat if mode == Mode.BULLDOZE else _ok_mat
	_cursor.position = Terrain.lift(hit) + Vector3.UP * 0.3
	_cursor.material_override = mat
	# Service buildings can be bulldozed too.
	_hover_service = sim.services.at(hit) if mode == Mode.BULLDOZE and _hover_seg == -1 else -1
	_hover_farm = sim.farms.farm_at(hit) if mode == Mode.BULLDOZE and _hover_seg == -1 and _hover_service == -1 else -1
	_hover_park = sim.parks.at(hit) if mode == Mode.BULLDOZE and _hover_seg == -1 and _hover_service == -1 \
		and _hover_farm == -1 else -1
	_hover_warehouse = sim.warehouses.at(hit) if mode == Mode.BULLDOZE and _hover_seg == -1 and _hover_service == -1 \
		and _hover_farm == -1 else -1
	if _hover_warehouse != -1:
		var w: Dictionary = sim.warehouses.buildings[_hover_warehouse]
		var wbox := BoxMesh.new()
		wbox.size = Vector3(Warehouses.site_width(w) + 1.0, 6.0, Warehouses.site_depth(w) + 1.0)
		_preview.mesh = wbox
		_preview.transform = Transform3D(Basis.looking_at(w.dir, Vector3.UP), Warehouses.center(w) + Vector3(0, 3, 0))
		_preview.material_override = mat
		_preview.visible = true
		return
	if _hover_service != -1 or _hover_farm != -1 or _hover_park != -1:
		var b: Dictionary = sim.services.buildings[_hover_service] if _hover_service != -1 \
			else (sim.farms.farms[_hover_farm] if _hover_farm != -1 else sim.parks.sites[_hover_park])
		var size: Vector2 = Services.size_of(b) if _hover_service != -1 \
			else (Farms.FARMHOUSE_SIZE if _hover_farm != -1 else b.size)
		var box := BoxMesh.new()
		box.size = Vector3(size.x + 1.0, 6.0, size.y + 1.0)
		_preview.mesh = box
		_preview.transform = Transform3D(Basis.looking_at(b.dir, Vector3.UP), Terrain.lift(b.pos) + Vector3(0, 3, 0))
		_preview.material_override = mat
		_preview.visible = true
		return
	if _hover_seg == -1:
		return
	var w := RoadStyle.half_width(road_type if mode == Mode.UPGRADE else network.segments[_hover_seg].type)
	w = maxf(w, GHOST_PX * 0.5 * _px)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.add_strip(st, Terrain.densify(network.sample_segment(_hover_seg), 6.0), -w - 0.5, w + 0.5, 0.2)
	_preview.mesh = Terrain.drape(st.commit())
	_preview.material_override = mat
	_preview.visible = true


func _update_hint() -> void:
	if mode == Mode.NONE:
		return
	var text := ""
	match mode:
		Mode.STRAIGHT:
			text = "Click to start a road." if _points.is_empty() \
				else "Click to finish. Hold Shift to snap angles. Right click to stop."
			if not _points.is_empty() and _shown_problem != "":
				text = _shown_problem
		Mode.CURVED:
			if _points.is_empty():
				text = "Click to start a curved road."
			elif _points.size() == 1:
				text = "Click where the road should bend."
			else:
				text = "Click to finish. Right click to stop."
			if _points.size() == 2 and _shown_problem != "":
				text = _shown_problem
		Mode.GRID:
			var size := "Blocks %d × %d ft  [ ]" % [roundi(grid_block * FT), roundi(grid_across * FT)]
			if grid_preset >= 0:
				size = "%s, %s" % [GridFill.PRESETS[grid_preset].name, size]
			if not grid_free:
				match _points.size():
					0: text = "Rectangle: drag from one corner to the other. Tab for any shape.  " + size
					_: text = "Drag or click the opposite corner, any direction. Sides line up with the road.  " + size
			else:
				match _points.size():
					0: text = "Any shape: click the first corner. Tab for a rectangle.  " + size
					1, 2: text = "Click the next corner. Shift snaps angles, Backspace undoes.  " + size
					_: text = "Click the first corner or press Enter to build. Shift+Tab turns the grid.  " + size
		Mode.ROUNDABOUT:
			text = "Click to place a roundabout. Roads it crosses join it.  Size %d ft  [ ]" \
				% roundi(RoadShapes.roundabout_radius(roundabout_radius, road_type) * 2.0 * FT)
		Mode.BULLDOZE:
			text = "Click a road, service building or farmhouse to remove it."
		Mode.UPGRADE:
			text = "Click a road to make it a %s." % RoadStyle.TYPES[road_type].name
	if elevation != 0.0 and mode != Mode.BULLDOZE and mode != Mode.UPGRADE:
		text += "\n%s: new roads at %+d ft  (Page Up / Page Down)" \
			% ["Bridge" if elevation > 0.0 else "Tunnel", roundi(elevation * FT)]
	if parallel and (mode == Mode.STRAIGHT or mode == Mode.CURVED):
		text += "\nParallel on (P): second road %d ft away  [ ]" % roundi(parallel_gap * FT)
	hint_changed.emit(text)
