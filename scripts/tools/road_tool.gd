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
## Roundabout: pick a real size from the row above the tools, then click to
## place. [ and ] fine-tune the size.
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
## Points snap onto roads and junctions within this many pixels too, so the
## pull is felt zoomed out as well as up close.
const SNAP_PX := 14.0
## A press and release further apart than this on screen is a drag.
const DRAG_PX := 8.0
## Straight roads snap to 15 degree steps while Shift is held.
const ANGLE_STEP := deg_to_rad(15.0)
## Guide lines catch the mouse within this angle.
const GUIDE_SNAP := deg_to_rad(4.0)
## A grid's first side lines up with a road or the compass within this.
const SIDE_SNAP := deg_to_rad(5.0)
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
## Exact: a rectangle grows only in whole blocks of the chosen size, so a
## section is a true mile. Adaptive: blocks flex to fit what was dragged,
## never bigger than the chosen size.
var grid_exact := true
var _exact_next := ""  # how much further to drag for the next whole block
var _exact_past := [false, false]  # the cursor is past the last whole block along, across
## Index into RoadShapes.ROUNDABOUT_SIZES, or -1 once [ ] has changed the
## size. Kept while the tool is away, like the grid size.
var roundabout_preset := 2
var roundabout_lanes := 1
var roundabout_radius := RoadShapes.radius_for_icd(150.0 / FT, RoadStyle.Type.RING)
var road_type := 0
var parallel := false
var parallel_gap := RoadShapes.GRID_ACROSS
## Height new road points are placed at, in metres above the ground.
var elevation := 0.0
var _plan_key := []
var _plan_memo := {}

var _points: Array[Vector3] = []
var _preview := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
## The ghost road: bright, drawn over trees and hills, and never thinner on
## screen than GHOST_PX however far out the camera is (as in CS2).
var _ok_mat := RoadStyle.material(Color(0.3, 0.85, 1.0, 0.85), true)
var _bad_mat := RoadStyle.material(Color(1.0, 0.3, 0.25, 0.75), true)
var _snap_mat := RoadStyle.material(Color(1.0, 0.85, 0.2, 0.95), true)  # on a road
var _snap_kind := "free"  # what the last point snapped to: node, segment, county or free
var _square := false  # Shift squared the third grid point: a rectangle
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
## The scenery county mile under the mouse, to bulldoze (CountyGrid.mile_at).
var _hover_county := {}
var _hover_farm := -1
var _hover_park := -1
var _shown_problem := ""
var _guide := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()  # Exact: the next whole block, faint
var _label := Label3D.new()
var _guide_mat := RoadStyle.material(Color(1, 1, 1, 0.45), true)
## Angle of the guide the current road snapped to, or NAN.
var _guide_angle := NAN
var _guide_kind := ""
var _left_down := false  # the left button went down on the map, not on a panel
var _press_at := Vector2.ZERO  # where on screen it went down
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
	_ghost.material_override = RoadStyle.material(Color(1, 1, 1, 0.85), true)
	_ghost.visible = false
	add_child(_ghost)
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
	if key.keycode == KEY_TAB:
		grid_side += 1
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


## Picks one of the real roundabout sizes (RoadShapes.ROUNDABOUT_SIZES).
func set_roundabout_preset(i: int) -> void:
	var p: Dictionary = RoadShapes.ROUNDABOUT_SIZES[i]
	roundabout_preset = i
	roundabout_lanes = int(p.lanes)
	roundabout_radius = RoadShapes.radius_for_icd(float(p.icd) / FT, _ring())
	if mode != Mode.ROUNDABOUT:
		set_mode(Mode.ROUNDABOUT)
	options_changed.emit()
	_update_hint()


## The ring type the roundabout tool builds.
func _ring() -> int:
	return RoadShapes.ring_for_lanes(roundabout_lanes)


## The ring radius the roundabout tool builds.
func _ring_radius() -> float:
	return RoadShapes.roundabout_radius(roundabout_radius, _ring())


## How the planner fits blocks: whole blocks in Exact, else never bigger
## than the chosen size.
func _fit() -> int:
	return GridFill.FIT_EXACT if grid_exact else GridFill.FIT_AT_MOST


## Switches the grid between exact whole blocks and blocks that flex to fit.
func set_grid_exact(on: bool) -> void:
	grid_exact = on
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
		_press_at = mb.position
		_click()
	elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		# The first side can be dragged out as well as clicked; letting go
		# after an Alt-drag of the camera sets nothing.
		# Only a real drag counts: in Exact a plain click's release would
		# otherwise set a whole first block at once.
		if _left_down and mode == Mode.GRID and _points.size() == 1 and mb.position.distance_to(_press_at) > DRAG_PX:
			_click()
		_left_down = false


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_preview.visible = false
	_preview.transform = Transform3D.IDENTITY
	_guide.visible = false
	_ghost.visible = false
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
	_show_snap(_snap_kind != "free")
	var curves := []
	var ok := true
	if mode == Mode.ROUNDABOUT:
		curves = RoadShapes.roundabout(p, _ring_radius())
	elif _points.is_empty():
		return
	elif mode == Mode.GRID:
		_show_grid(p)
		return
	else:
		var curve := _pending_curve(p)
		curves = _plan(curve).pieces.duplicate()
		if curves.is_empty():
			curves = [curve]
		_show_length(curve)
		if parallel:
			curves.append(RoadShapes.offset(curve, parallel_gap))
		var problem := _problem(curve)
		ok = problem == ""
		if problem != _shown_problem:
			_shown_problem = problem
			_update_hint()
	if curves.is_empty():
		return
	if mode == Mode.ROUNDABOUT:
		var cost := CitySim.shapes_cost(curves, _ring())
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
			elif not _hover_county.is_empty():
				sim.apply({"type": "remove_county", "key": _hover_county.key})
				_hover_county = {}
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
			var raw := _snapped(hit)
			var p := _grid_corner(raw)
			if _points.size() == 1 and _flat_dist(raw, _points[0]) <= RECT_MIN:
				pass  # a second click on the first point (or its release) adds nothing
			elif _points.size() >= 3 and p.distance_to(_points[0]) < 0.01:
				_finish_grid()  # back on the first corner closes the shape
			elif _points.size() == 2 and _square:
				_points.append(p)  # Shift on the third point: a rectangle
				_points.append(_points[0] + p - _points[1])
			# A click without a drag only sets the first corner.
			elif _points.is_empty() or _flat_dist(p, _points[_points.size() - 1]) > RECT_MIN:
				_points.append(p)
		Mode.ROUNDABOUT:
			sim.apply({"type": "build_roundabout", "center": _xz(_snapped(hit)),
				"radius": _ring_radius(), "lanes": roundabout_lanes, "road": road_type})
	_update_hint()


## Builds the grid inside the shape drawn so far.
func _finish_grid(shape: Array = _points) -> void:
	if shape.size() < 3:
		return
	var pts := []
	for q in shape:
		pts.append(_xz(q))
	if sim.apply({"type": "build_grid_shape", "points": pts, "block": grid_block, "across": grid_across,
			"side": grid_side, "road": road_type, "fit": _fit(), "join": true}):
		_points.clear()
	_update_hint()


## Where the next corner of a grid shape goes. An old road or junction
## under the cursor wins, then the first corner (to close the shape), the
## fourth corner of a parallelogram, Shift square off the last side, or a
## side near square with the last one.
func _grid_corner(p: Vector3) -> Vector3:
	_guide_angle = NAN
	_square = false
	_exact_past = [false, false]
	_exact_next = ""
	if _points.is_empty():
		return p
	if _points.size() >= 3 and _flat_dist(p, _points[0]) < _snap_reach(SNAP_NODE):
		return _points[0]
	if _snap_kind != "free":
		return p
	if _points.size() == 1:
		return _side_end(p)
	if _points.size() == 3:
		var q: Vector3 = _points[0] + _points[2] - _points[1]
		if _flat_dist(p, q) < _snap_reach(SNAP_NODE):
			return q
	if Input.is_key_pressed(KEY_SHIFT):
		return _square_off(p)
	var last: Vector3 = _points[_points.size() - 1]
	var prev: Vector3 = _points[_points.size() - 2]
	var d := p - last
	var ref := atan2(last.z - prev.z, last.x - prev.x)
	var ang := atan2(d.z, d.x)
	for k in 4:
		var g: float = ref + k * PI * 0.5
		if absf(angle_difference(ang, g)) < GUIDE_SNAP:
			return last + Vector3(cos(g), 0.0, sin(g)) * Vector2(d.x, d.z).length()
	return p


## Three clicks: the first corner, then the end of the first side, which
## sets the grid's direction and length. Near a road's direction at the
## corner, the nearest road's or the compass's (or square to one) it lines up
## exactly; Shift steps it by 15 degrees. In Exact it is whole blocks long.
func _side_end(p: Vector3) -> Vector3:
	var a: Vector3 = _points[0]
	var d := p - a
	var ang := atan2(d.z, d.x)
	var len := Vector2(d.x, d.z).length()
	_guide_kind = ""
	_exact_past = [false, false]
	var snapped := false
	if Input.is_key_pressed(KEY_SHIFT):
		ang = snappedf(ang, ANGLE_STEP)
		snapped = true
	else:
		for g in _side_angles(a):
			for k in 4:
				var s: float = g + k * PI * 0.5
				if not snapped and absf(angle_difference(ang, s)) < SIDE_SNAP:
					ang = s
					snapped = true
	if snapped:
		_guide_angle = ang
	var u := Vector3(cos(ang), 0.0, sin(ang))
	if grid_exact:
		_exact_next = ""
		return a + u * absf(_whole(len, grid_block, 0))
	var n := network.find_node_near(a + u * len, SNAP_NODE)
	if n != -1 and not snapped:
		return network.nodes[n]  # an old junction wins
	if n != -1 and absf((network.nodes[n] - a).dot(Vector3(-u.z, 0.0, u.x))) < 1.0:
		len = (network.nodes[n] - a).dot(u)
	return a + u * len


## The directions a first side can line up with at `a`: the roads there, or
## else the nearest road, and the compass.
func _side_angles(a: Vector3) -> Array:
	var refs := _reference_angles(a)
	if refs.is_empty():
		var near := network.find_segment_near(a, RECT_ALIGN_REACH, RoadNetwork.SAME_LEVEL)
		if not near.is_empty():
			var c := network.curve_of(near.seg)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
			refs.append(atan2(tan.z, tan.x))
	refs.append(0.0)
	return refs


## Shift: the next point square off the end of the last side. On the third
## point it makes a rectangle, whole blocks deep in Exact.
func _square_off(p: Vector3) -> Vector3:
	var last: Vector3 = _points[_points.size() - 1]
	var prev: Vector3 = _points[_points.size() - 2]
	var u := Vector3(last.x - prev.x, 0.0, last.z - prev.z).normalized()
	var v := Vector3(-u.z, 0.0, u.x)
	var dv := (p - last).dot(v)
	if _points.size() == 2:
		_square = true
		if grid_exact:
			dv = _whole(dv, grid_across, 1)
	return last + v * dv


## The shape drawn so far with `p` as its next point (a rectangle's fourth
## corner too, when Shift squares the third).
func _pending_shape(p: Vector3) -> Array:
	var shape: Array = _points.duplicate()
	if shape.size() >= 3 and p.distance_to(shape[0]) < 0.01:
		return shape
	shape.append(p)
	if _square and _points.size() == 2:
		shape.append(_points[0] + p - _points[1])
	return shape


## Exact mode: `d` cut back to whole blocks of `size` (none until the
## cursor has gone a whole block, so a click never jumps a block away),
## noting how much further the cursor must go for the next block.
func _whole(d: float, size: float, axis: int) -> float:
	var n := floori(absf(d) / size + 0.001)
	var more := (n + 1) * size - absf(d)
	_exact_past[axis] = n > 0 and more < size * 0.999
	if more < size * 0.999:
		var txt := "%s more for the %s block %s" % [_distance_text(more), "next" if n > 0 else "first",
			"along" if axis == 0 else "across"]
		_exact_next = txt if _exact_next == "" else _exact_next + "\n" + txt
	return (1.0 if d >= 0.0 else -1.0) * n * size


## A distance in US units: miles past a quarter mile, else feet.
static func _distance_text(m: float) -> String:
	var ft := m * FT
	if ft >= 1320.0:
		return "%s mi" % String.num(ft / 5280.0, 2).trim_suffix("0").trim_suffix(".")
	return "%s ft" % CitySim.money_text(roundi(ft))


## Which way a rectangle from `a` toward `p` lines up. At a junction it
## lines up with the road that lets its sides run along roads there, rather
## than one that would cut across it from the corner.
func _rect_angle(a: Vector3, p: Vector3) -> float:
	var refs := _reference_angles(a)
	var n := network.find_node_near(a, 0.5)
	if refs.size() > 1 and n != -1 and grid_side == 0:
		var outs := []  # the ways roads leave the corner
		for id in network.segments_at(n):
			var c := network.curve_of(id)
			var at_a: bool = network.segments[id].a == n
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], 0.0 if at_a else 1.0)
			outs.append(Vector2(tan.x, tan.z).normalized() * (1.0 if at_a else -1.0))
		var d := Vector2(p.x - a.x, p.z - a.z)
		var best := -INF
		var pick: float = refs[0]
		for g in refs:
			var u := Vector2(cos(g), sin(g))
			var v := Vector2(-u.y, u.x)
			var su := u * signf(d.dot(u))
			var sv := v * signf(d.dot(v))
			# A rectangle squeezed thin along a road is not what was dragged.
			var du := absf(d.dot(u))
			var dv := absf(d.dot(v))
			var score := minf(du, dv) / maxf(maxf(du, dv), 1.0) * 0.5
			if minf(du, dv) < minf(grid_block, grid_across) * 0.5:
				score -= 1.0
			for o in outs:
				if o.dot(su) > 0.999 or o.dot(sv) > 0.999:
					score += 1.0  # a side runs along it
				elif o.dot(su) > 0.0 and o.dot(sv) > 0.0:
					score -= 1.0  # it would cut across the grid
			if score > best:
				best = score
				pick = g
		return pick
	if refs.is_empty():
		var near := network.find_segment_near(a, RECT_ALIGN_REACH, RoadNetwork.SAME_LEVEL)
		if not near.is_empty():
			var c := network.curve_of(near.seg)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
			refs.append(atan2(tan.z, tan.x))
	if refs.is_empty():
		return 0.0  # out in the open, line up with the compass
	return refs[grid_side % refs.size()]  # Shift+Tab: line up with the next road here


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Shows the shape being drawn and the streets it would get, with the price.
func _show_grid(p: Vector3) -> void:
	p = _grid_corner(p)
	_cursor.position = Terrain.lift(p) + Vector3.UP * 0.3
	var shape := _pending_shape(p)
	_show_snap(_snap_kind != "free" or (_points.size() >= 3 and p.distance_to(_points[0]) < 0.01))
	_show_guide(_points[0])
	var plan := []
	if shape.size() >= 3:
		var key := "%s|%s|%s|%d|%d|%d|%d" % [str(shape), str(grid_block), str(grid_across), grid_side, road_type,
			sim.network.segments.size(), _fit()]
		# Big towns take a moment to plan, so replan at most a few times a second.
		if key != _grid_key and Time.get_ticks_msec() - _grid_planned_at > 120:
			_grid_key = key
			_grid_plan = GridFill.plan(network, shape, grid_block, road_type, grid_side, grid_across, _fit())
			_grid_planned_at = Time.get_ticks_msec()
		plan = _grid_plan
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := maxf(RoadStyle.half_width(road_type), GHOST_PX * 0.5 * _px)
	var edge := maxf(0.4, LINE_PX * 0.5 * _px)
	for c in plan:
		RoadMesh.add_strip(st, Terrain.densify(RoadNetwork.sample_curve(c[0], c[1], c[2], 2), 6.0), -hw, hw, 0.2)
	if shape.size() == 2:  # the first side is a street of its own
		RoadMesh.add_strip(st, Terrain.densify(PackedVector3Array([shape[0], shape[1]]), 6.0), -hw, hw, 0.2)
	for c in GridFill.outline(shape, shape.size() >= 3):
		RoadMesh.add_strip(st, Terrain.densify(RoadNetwork.sample_curve(c[0], c[1], c[2], 2), 6.0), -edge, edge, 0.35)
	var ghost := []  # Exact: where the next whole block would reach
	if grid_exact and shape.size() == 2 and _exact_past[0]:
		var r0: Vector3 = shape[0]
		var r1: Vector3 = shape[1]
		ghost.append([r1, r1 + (r1 - r0).normalized() * grid_block])
	if grid_exact and _square and shape.size() == 4:
		var r: Array = shape
		for axis in 2:
			if _exact_past[axis]:
				var from: Vector3 = r[1] if axis == 0 else r[3]
				var r0: Vector3 = r[0]
				var step: Vector3 = (from - r0).normalized() * (grid_block if axis == 0 else grid_across)
				var x: Vector3 = r[2] + step
				ghost.append([from, from + step])
				ghost.append([r[2], x])
				ghost.append([from + step, x])
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in ghost:
		RoadMesh.add_strip(gst, Terrain.densify(PackedVector3Array([g[0], g[1]]), 6.0), -hw * 0.6, hw * 0.6, 0.35)
	var cost := CitySim.shapes_cost(plan, road_type)
	var ok := cost <= sim.economy.money
	var dims := ""
	if shape.size() >= 2:
		dims = "%s ft" % CitySim.money_text(roundi(_flat_dist(shape[0], shape[1]) * FT))
	if shape.size() == 2 and grid_exact:
		dims = "Exact: %d blocks, %s" % [roundi(_flat_dist(shape[0], shape[1]) / grid_block),
			_distance_text(_flat_dist(shape[0], shape[1]))]
		if _exact_next != "":
			dims += "\n" + _exact_next
	if shape.size() == 3:
		dims = "Triangle, %s side  (Shift for a rectangle)" % _distance_text(_flat_dist(shape[0], shape[1]))
	if _square and shape.size() == 4:
		dims += " × %s ft" % CitySim.money_text(roundi(_flat_dist(shape[1], shape[2]) * FT))
		if grid_exact:
			dims = "Exact: %d × %d blocks, %s × %s" % [roundi(_flat_dist(shape[0], shape[1]) / grid_block),
				roundi(_flat_dist(shape[1], shape[2]) / grid_across), _distance_text(_flat_dist(shape[0], shape[1])),
				_distance_text(_flat_dist(shape[1], shape[2]))]
			if _exact_next != "":
				dims += "\n" + _exact_next
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
	if not ghost.is_empty():
		_ghost.mesh = Terrain.drape(gst.commit(), true)
		_ghost.visible = true


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
		roundabout_radius = RoadShapes.roundabout_radius(_ring_radius() * f, _ring())
		roundabout_preset = -1
		options_changed.emit()
	elif parallel and (mode == Mode.STRAIGHT or mode == Mode.CURVED):
		parallel_gap = clampf(parallel_gap * f, _min_gap(), PARALLEL_MAX)
	else:
		return
	_update_hint()


func _build(curve: Array) -> bool:
	# Drawn onto or across a county road, the town takes over that mile.
	# Raised: the road climbs over the roads and track it crosses.
	return sim.apply({"type": "build_road", "start": _xz(curve[0]), "ctrl": _xz(curve[1]),
		"end": _xz(curve[2]), "road": road_type, "join": true, "over": elevation > 0.0})


## The pieces a raised road is built as (Overpass), worked out once per
## change of the drawn road.
func _plan(curve: Array) -> Dictionary:
	if elevation <= 0.0:
		return {"ok": true, "pieces": [curve], "crossed": 0, "why": ""}
	var key := [curve, road_type, sim.network.revision, sim.rail.version]
	if _plan_key != key:
		_plan_key = key
		_plan_memo = Overpass.plan(sim, curve, road_type)
	return _plan_memo


## The county road (CountyGrid.mile_at) a point is on, out in the country
## and not joined yet, or {}. In town the lots and streets have its place.
func _county_at(p: Vector3, reach := 0.5) -> Dictionary:
	if absf(p.y) > 0.5 or Terrain.flat_weight(p.x, p.z) > 0.3 or Terrain.mow_weight(p.x, p.z) > 0.3:
		return {}
	var o := sim.terrain_offset
	var mile := CountyGrid.mile_at(p.x + o.x, p.z + o.y, reach)
	if mile.is_empty() or sim.county_removed.has(mile.key) or not CountyGrid.clears(mile.on.x, mile.on.y):
		return {}
	return mile


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
		CitySim.money_text(CitySim.shapes_cost(_plan(curve).pieces if _plan(curve).ok else [curve], road_type)
			* (2 if parallel else 1))]
	var r := RoadNetwork.min_radius(curve[0], curve[1], curve[2])
	if r < 2000.0:
		_label.text += "\nCurve safe at %d mph" % RoadStyle.safe_speed_mph(r)
	if absf(curve[2].y) > 0.1 or absf(curve[0].y) > 0.1:
		var flat := Vector2(curve[2].x - curve[0].x, curve[2].z - curve[0].z).length()
		_label.text += "\nHeight %+d ft, grade %d%%" % [roundi(curve[2].y * FT),
			roundi(absf(curve[2].y - curve[0].y) / maxf(flat, 0.1) * 100.0)]
	var plan := _plan(curve)
	if plan.ok and plan.crossed > 0:
		var top := 0.0
		for q in plan.pieces:
			top = maxf(top, maxf(q[0].y, q[2].y))
		_label.text += "\nOverpass: clears %d crossing%s, deck %d ft up" \
			% [plan.crossed, "" if plan.crossed == 1 else "s", roundi(top * FT)]
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
	var plan := _plan(curve)
	if not plan.ok:
		return plan.why
	return sim.pieces_problem(plan.pieces, road_type)


func _snapped(hit: Vector3) -> Vector3:
	_snap_kind = "free"
	if mode == Mode.CURVED and _points.size() == 1:
		return Vector3(hit.x, 0.0, hit.z)  # the bend point floats freely
	var snap := network.snap(hit, _snap_reach(SNAP_NODE, SNAP_PX * 1.3), _snap_reach(SNAP_ROAD + 5.0, SNAP_PX))
	_snap_kind = snap.kind
	if snap.kind == "free":
		# Onto a county road out in the country, which joins it to town.
		var mile := _county_at(Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z),
			_snap_reach(SNAP_ROAD + 5.0, SNAP_PX))
		if not mile.is_empty():
			_snap_kind = "county"
			var o := sim.terrain_offset
			return Vector3(mile.on.x - o.x, 0.0, mile.on.y - o.y)
		return Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z)
	if mode == Mode.GRID:
		return Vector3(snap.pos.x, 0.0, snap.pos.z)  # grids are built on the ground
	return snap.pos


## How far a point reaches to snap: `m` metres, or `px` pixels when zoomed
## out.
func _snap_reach(m: float, px := SNAP_PX) -> float:
	return maxf(m, px * _px)


## The cursor turns gold on a road or junction it has snapped to.
func _show_snap(on_road: bool) -> void:
	_cursor.material_override = _snap_mat if on_road else _ok_mat
	_cursor.scale = Vector3.ONE * maxf(1.0, CURSOR_PX * _px / 3.0) * (1.4 if on_road else 1.0)


func _preview_mesh(curves: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := RoadStyle.half_width(_ring() if mode == Mode.ROUNDABOUT else road_type)
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
	_hover_county = _county_at(hit, 6.0) if mode == Mode.BULLDOZE and _hover_seg == -1 else {}
	if not _hover_county.is_empty():
		# A county road out in the country: the whole mile goes.
		var o := sim.terrain_offset
		var a: Vector2 = _hover_county.a - o
		var b: Vector2 = _hover_county.b - o
		var cst := SurfaceTool.new()
		cst.begin(Mesh.PRIMITIVE_TRIANGLES)
		RoadMesh.add_strip(cst, Terrain.densify(PackedVector3Array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y)]), 6.0),
			-CountyGrid.HALF_WIDTH - 0.5, CountyGrid.HALF_WIDTH + 0.5, 0.2)
		_preview.mesh = Terrain.drape(cst.commit())
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
			var size := "Blocks %s × %s  [ ]" % [_distance_text(grid_block), _distance_text(grid_across)]
			if grid_preset >= 0:
				size = "%s, %s" % [GridFill.PRESETS[grid_preset].name, size]
			size = ("Exact, whole blocks only. " if grid_exact else "Adaptive, blocks up to ") + size
			match _points.size():
				0: text = "Click where the grid starts. Points snap onto roads.  " + size
				1: text = "Click the end of the first side; it sets the grid's direction. Shift steps 15°.  " + size
				2: text = "Click the next point, or hold Shift for a rectangle. Backspace undoes.  " + size
				_: text = "Press Enter to build, or keep clicking points for any shape. Tab turns the grid.  " + size
		Mode.ROUNDABOUT:
			var size := "%d ft across, %d %s" % [roundi(RoadShapes.icd_of(_ring_radius(), _ring()) * FT),
				roundabout_lanes, "lane" if roundabout_lanes == 1 else "lanes"]
			if roundabout_preset >= 0:
				size = "%s, %s" % [RoadShapes.ROUNDABOUT_SIZES[roundabout_preset].name, size]
			text = "Click to place a roundabout. Roads it crosses join it.  %s  [ ]" % size
		Mode.BULLDOZE:
			text = "Click a road, service building or farmhouse to remove it."
		Mode.UPGRADE:
			text = "Click a road to make it a %s." % RoadStyle.TYPES[road_type].name
	if elevation != 0.0 and mode != Mode.BULLDOZE and mode != Mode.UPGRADE:
		text += "\n%s: new roads at %+d ft  (Page Up / Page Down)" \
			% ["Bridge" if elevation > 0.0 else "Tunnel", roundi(elevation * FT)]
		if elevation > 0.0:
			text += "\nRoads and track it crosses: it climbs over them, piers and all."
	if parallel and (mode == Mode.STRAIGHT or mode == Mode.CURVED):
		text += "\nParallel on (P): second road %d ft away  [ ]" % roundi(parallel_gap * FT)
	hint_changed.emit(text)
