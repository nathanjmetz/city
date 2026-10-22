class_name RoadTool
extends Node3D
## Lets the player draw and remove roads with the mouse.
##
## Straight: click start, click end (keeps going from the end).
## Curved: click start, click the bend, click end.
## Grid: click a corner, click to set the first street, click to set how far
## back the grid reaches. [ and ] change the block length.
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
var grid_block := 120.0
var roundabout_radius := 20.0
var road_type := 0
var parallel := false
var parallel_gap := RoadShapes.GRID_ACROSS
## Height new road points are placed at, in metres above the ground.
var elevation := 0.0

var _points: Array[Vector3] = []
var _preview := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
var _ok_mat := RoadStyle.material(Color(0.35, 0.65, 1.0, 0.55), true)
var _bad_mat := RoadStyle.material(Color(1.0, 0.3, 0.25, 0.6), true)
var _hover_seg := -1
var _hover_service := -1
var _shown_problem := ""
var _guide := MeshInstance3D.new()
var _label := Label3D.new()
var _guide_mat := RoadStyle.material(Color(1, 1, 1, 0.45), true)
## Angle of the guide the current road snapped to, or NAN.
var _guide_angle := NAN
var _guide_kind := ""


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
	_guide.material_override = _guide_mat
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 28
	_label.outline_size = 8
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
		set_mode(Mode.STRAIGHT)
	_update_hint()


func set_mode(m: int) -> void:
	mode = m
	_points.clear()
	_hover_seg = -1
	mode_changed.emit(mode)
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
		_click()


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_preview.visible = false
	_preview.transform = Transform3D.IDENTITY
	_guide.visible = false
	_label.visible = false
	_cursor.visible = hit != null and mode != Mode.NONE
	if hit == null or mode == Mode.NONE:
		return
	if mode == Mode.BULLDOZE or mode == Mode.UPGRADE:
		_preview_pick(hit)
		return
	var p := _snapped(hit)
	_cursor.position = p + Vector3.UP * 0.3
	_cursor.material_override = _ok_mat
	var curves := []
	var ok := true
	if mode == Mode.ROUNDABOUT:
		curves = RoadShapes.roundabout(p, RoadShapes.roundabout_radius(roundabout_radius, road_type))
	elif _points.is_empty():
		return
	elif mode == Mode.GRID:
		curves = _pending_grid(p)
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
	if mode == Mode.ROUNDABOUT or (mode == Mode.GRID and _points.size() == 2):
		var cost := CitySim.shapes_cost(curves,
			RoadStyle.ring_type(road_type) if mode == Mode.ROUNDABOUT else road_type)
		ok = cost <= sim.economy.money
		_label.text = "$" + CitySim.money_text(cost) + ("" if ok else "\nNot enough money")
		_label.position = p + Vector3(0, 6, 0)
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
			elif _hover_seg != -1:
				sim.apply({"type": "remove_road", "seg": _hover_seg})
				_hover_seg = -1
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
			var p := _snapped(hit)
			if _points.size() == 1:
				p = _pending_curve(p)[2]  # Shift snaps the first street's angle
			if _points.size() < 2:
				_points.append(p)
			elif sim.apply({"type": "build_grid", "a": _xz(_points[0]), "b": _xz(_points[1]),
					"c": _xz(p), "block": grid_block, "road": road_type}):
				_points.clear()
		Mode.ROUNDABOUT:
			sim.apply({"type": "build_roundabout", "center": _xz(_snapped(hit)),
				"radius": roundabout_radius, "road": road_type})
	_update_hint()


## The grid being placed: one street while picking its end, then the lot.
func _pending_grid(p: Vector3) -> Array:
	if _points.size() == 1:
		return [_pending_curve(p)]
	return RoadShapes.grid(_points[0], _points[1], p, grid_block)


func _resize(f: float) -> void:
	if mode == Mode.GRID:
		grid_block = clampf(grid_block * f, RoadShapes.GRID_BLOCK_MIN, RoadShapes.GRID_BLOCK_MAX)
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
	_label.text = "%d m  (%d ft)" % [roundi(m), roundi(m * 3.28084)]
	var cost := Economy.road_cost(curve, road_type) * (2 if parallel else 1)
	_label.text += "\n$" + CitySim.money_text(cost)
	var r := RoadNetwork.min_radius(curve[0], curve[1], curve[2])
	if r < 2000.0:
		_label.text += "\nCurve safe at %d mph" % RoadStyle.safe_speed_mph(r)
	if absf(curve[2].y) > 0.1 or absf(curve[0].y) > 0.1:
		var flat := Vector2(curve[2].x - curve[0].x, curve[2].z - curve[0].z).length()
		_label.text += "\nHeight %+.1f m, grade %d%%" % [curve[2].y,
			roundi(absf(curve[2].y - curve[0].y) / maxf(flat, 0.1) * 100.0)]
	if not is_nan(_guide_angle):
		_label.text += "\n" + _guide_kind
		var dir := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var line := PackedVector3Array([curve[0] - dir * 400.0, curve[0] + dir * 400.0])
		RoadMesh.add_strip(st, line, -0.25, 0.25, 0.3)
		_guide.mesh = st.commit()
		_guide.visible = true
	_label.position = curve[2] + Vector3(0, 6, 0)
	_label.visible = true


func _is_valid(curve: Array) -> bool:
	return _problem(curve) == ""


## Why a road can't be built, or "" if it can (the simulation's own rules).
func _problem(curve: Array) -> String:
	return sim.road_problem(curve, road_type)


func _snapped(hit: Vector3) -> Vector3:
	if (mode == Mode.CURVED and _points.size() == 1) or (mode == Mode.GRID and _points.size() == 2):
		return Vector3(hit.x, 0.0, hit.z)  # bend point and grid depth float freely
	var snap := network.snap(hit, SNAP_NODE, SNAP_ROAD)
	if snap.kind == "free":
		return Vector3(hit.x, elevation, hit.z)
	return snap.pos


func _preview_mesh(curves: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := RoadStyle.half_width(RoadStyle.ring_type(road_type) if mode == Mode.ROUNDABOUT else road_type)
	for curve in curves:
		var pts := RoadNetwork.sample_curve(curve[0], curve[1], curve[2])
		RoadMesh.add_strip(st, pts, -hw, hw, 0.2)
	return st.commit()


## Highlights the road under the mouse: red to bulldoze, blue to upgrade.
func _preview_pick(hit: Vector3) -> void:
	var near := network.find_segment_near(hit, RoadStyle.half_width(RoadStyle.Type.BOULEVARD))
	_hover_seg = -1
	if not near.is_empty() and near.dist <= RoadStyle.half_width(network.segments[near.seg].type) + 2.0:
		_hover_seg = near.seg
	var mat := _bad_mat if mode == Mode.BULLDOZE else _ok_mat
	_cursor.position = hit + Vector3.UP * 0.3
	_cursor.material_override = mat
	# Service buildings can be bulldozed too.
	_hover_service = sim.services.at(hit) if mode == Mode.BULLDOZE and _hover_seg == -1 else -1
	if _hover_service != -1:
		var b: Dictionary = sim.services.buildings[_hover_service]
		var size: Vector2 = Services.KINDS[b.kind].size
		var box := BoxMesh.new()
		box.size = Vector3(size.x + 1.0, 6.0, size.y + 1.0)
		_preview.mesh = box
		_preview.transform = Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos + Vector3(0, 3, 0))
		_preview.material_override = mat
		_preview.visible = true
		return
	if _hover_seg == -1:
		return
	var w := RoadStyle.half_width(road_type if mode == Mode.UPGRADE else network.segments[_hover_seg].type)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.add_strip(st, network.sample_segment(_hover_seg), -w - 0.5, w + 0.5, 0.2)
	_preview.mesh = st.commit()
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
			var size := "Blocks %d m long  [ ]" % int(grid_block)
			match _points.size():
				0: text = "Click a corner of the new neighborhood.  " + size
				1: text = "Click to set the first street. Hold Shift to snap angles.  " + size
				_: text = "Move out to size the grid, then click to build.  " + size
		Mode.ROUNDABOUT:
			text = "Click to place a roundabout. Roads it crosses join it.  Size %d m  [ ]" \
				% int(RoadShapes.roundabout_radius(roundabout_radius, road_type) * 2.0)
		Mode.BULLDOZE:
			text = "Click a road or service building to remove it."
		Mode.UPGRADE:
			text = "Click a road to make it a %s." % RoadStyle.TYPES[road_type].name
	if elevation != 0.0 and mode != Mode.BULLDOZE and mode != Mode.UPGRADE:
		text += "\n%s: new roads at %+.1f m  (Page Up / Page Down)" \
			% ["Bridge" if elevation > 0.0 else "Tunnel", elevation]
	if parallel and (mode == Mode.STRAIGHT or mode == Mode.CURVED):
		text += "\nParallel on (P): second road %d m away  [ ]" % int(parallel_gap)
	hint_changed.emit(text)
