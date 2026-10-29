class_name RoadTool
extends Node3D
## Lets the player draw and remove roads with the mouse.
##
## Straight: click start, click end (keeps going from the end).
## Curved: click start, click the bend, click end.
## S-curve: click start, the first bend, the second bend, then the end (CS2's
## complex curve). It is built as two curved roads that meet with no kink.
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

enum Mode { NONE, STRAIGHT, CURVED, BULLDOZE, GRID, ROUNDABOUT, UPGRADE, SCURVE }

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
## A grid's next side snaps square to the last one within this.
const REGULAR_SNAP := deg_to_rad(8.0)
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
## Bridge plans by [curve, type, revisions], kept a few at a time so an
## S-curve's two halves don't push each other out every frame.
var _plan_memo := {}

var _points: Array[Vector3] = []
var _preview := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
## The ghost road: bright, drawn over trees and hills, and never thinner on
## screen than GHOST_PX however far out the camera is (as in CS2).
var _ok_mat := RoadStyle.material(Color(0.3, 0.85, 1.0, 0.85), true)
var _bad_mat := RoadStyle.material(Color(1.0, 0.3, 0.25, 0.75), true)
## A road that would wipe something out (a park, homes, a hub) shows amber,
## says what, and asks again before it's built.
var _warn_mat := RoadStyle.material(Color(1.0, 0.68, 0.15, 0.85), true)
const WARN_TEXT := Color(1.0, 0.78, 0.3)
var _losses := []
var _loss_key := ""
var _loss_at := -1000
## Set by the first click on a road that wipes something out: {p, go}. The
## road holds still at `p`; the next click runs `go`, right click or Esc
## goes back.
var _armed := {}
var _snap_mat := RoadStyle.material(Color(1.0, 0.85, 0.2, 0.95), true)  # on a road
var _snap_kind := "free"  # what the last point snapped to: node, segment, highway, county or free
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
var _guide_mat := RoadStyle.material(Color(1, 1, 1, 0.85), true)
## Angle of the guide the current road snapped to, or NAN.
var _guide_angle := NAN
var _guide_kind := ""
## CS2-style alignment: a point lines up with nearby junctions and road ends,
## along their roads or square to them, shown as dotted lines.
const ALIGN_PX := 10.0  # how near the cursor comes to a guide line to snap onto it
const ALIGN_REACH := 500.0  # junctions this near offer guide lines (more when zoomed out)
const ALIGN_NODES := 16  # the nearest this many junctions only
const ROAD_SQUARE_SNAP := deg_to_rad(12.0)  # a grid corner on a road squares onto it this near
const DASH_PX := 9.0  # dash length on screen
## AASHTO Green Book: roads should cross near 90° and no sharper than about
## 60°, or drivers can't see along the other road.
const SHARP_DEG := 60.0
var _align_lines := []  # [from, to]: the dotted lines the point lined up on
var _angle_labels: Array[Label3D] = [Label3D.new(), Label3D.new()]  # at the start and end
## CS2-style slope readout on the steepest stretch of the road being drawn,
## amber past the road type's AASHTO maximum grade (RoadStyle "grade").
var _grade_label := Label3D.new()
const GRADE_STATION := 30.48  # grades are read over a 100 ft survey station
const GRADE_AMBER := Color(1.0, 0.72, 0.2)
var _left_down := false  # the left button went down on the map, not on a panel
var _press_at := Vector2.ZERO  # where on screen it went down
## The last grid plan, kept while the shape and cursor stay put.
var _grid_key := ""
var _grid_plan := []
var _grid_taken := []  # county road or highway the grid takes over (free)
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
	for l in _angle_labels:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0005
		l.font_size = 34
		l.outline_size = 10
		l.font = Brand.font("ui", 700)
		l.offset = Vector2(80, 0)  # beside the road, clear of it
		l.outline_modulate = Color(0.05, 0.08, 0.1)
		l.no_depth_test = true
		l.visible = false
		add_child(l)
	for prop in ["billboard", "fixed_size", "pixel_size", "outline_size", "font", "outline_modulate", "no_depth_test"]:
		_grade_label.set(prop, _angle_labels[0].get(prop))
	_grade_label.font_size = 30
	_grade_label.offset = Vector2(0, -60)  # under the road, clear of the cursor readout
	_grade_label.visible = false
	add_child(_grade_label)
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
	_armed = {}
	_hover_seg = -1
	mode_changed.emit(mode)
	_update_hint()


## Grid keys come before the chat's Enter, while a grid shape is being drawn
## and nobody is typing.
func _input(event: InputEvent) -> void:
	if mode != Mode.GRID or Hud.typing(get_viewport()):
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
	# Shift + a number opens a bottom bar menu instead (Hud.hotkey_category).
	if event is InputEventKey and event.pressed and not event.echo and not (event as InputEventKey).shift_pressed:
		match KeyBinds.action(event as InputEventKey, ["road", "curve", "scurve", "grid", "roundabout", "bulldoze", "upgrade", "parallel",
				"raise", "lower", "smaller", "bigger"]):
			"road": set_mode(Mode.STRAIGHT)
			"curve": set_mode(Mode.CURVED)
			"scurve": set_mode(Mode.SCURVE)
			"grid": set_mode(Mode.GRID)
			"roundabout": set_mode(Mode.ROUNDABOUT)
			"bulldoze": set_mode(Mode.BULLDOZE)
			"upgrade": set_mode(Mode.UPGRADE)
			"parallel": set_parallel(not parallel)
			"raise": change_elevation(1)
			"lower": change_elevation(-1)
			"smaller": _resize(1.0 / 1.2)
			"bigger": _resize(1.2)
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
	_label.modulate = Color(1, 1, 1)
	for l in _angle_labels:
		l.visible = false
	_grade_label.visible = false
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
	var p: Vector3 = _armed.p if not _armed.is_empty() else _snapped(hit)
	if mode == Mode.ROUNDABOUT and _ring_under(hit) != -1:
		# Over a roundabout: snap to its centre, to rebuild it at this size
		# and lane count, not to one of its joints (Nathan, 2026-10-25).
		p = _ring_center(_ring_under(hit))
	_cursor.position = Terrain.lift(p) + Vector3.UP * 0.3
	_show_snap(_snap_kind != "free")
	var curves := []
	var ok := true
	if mode == Mode.ROUNDABOUT:
		curves = RoadShapes.roundabout(p, _ring_radius())
	elif _points.is_empty():
		_draw_guides(Vector3.ZERO)  # where the first point lines up
		return
	elif mode == Mode.GRID:
		_show_grid(p)
		return
	else:
		var drawn := _pending_curves(p)
		var problem := ""
		for curve in drawn:
			var pieces: Array = _plan(curve).pieces
			curves.append_array(pieces if not pieces.is_empty() else [curve])
			if parallel:
				curves.append(RoadShapes.offset(curve, parallel_gap))
			if problem == "":
				problem = _problem(curve)
		if problem == "" and _drawn_cost(drawn) > sim.economy.money:
			# Each half fits the money, but not both.
			problem = "Not enough money: this road costs $%s." % CitySim.money_text(_drawn_cost(drawn))
		_show_length(drawn)
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
	if ok and not _check_losses(curves, _ring() if mode == Mode.ROUNDABOUT else road_type).is_empty():
		_preview.material_override = _warn_mat
		_warn_label()
	_preview.visible = true


func _click() -> void:
	if not _armed.is_empty():
		# The second click: build it anyway.
		var go: Callable = _armed.go
		_armed = {}
		go.call()
		_update_hint()
		return
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
				if RoadStyle.is_ring(network.segments[_hover_seg].type):
					# The whole roundabout goes, and its streets meet again in
					# a plain intersection (Nathan, 2026-10-25).
					sim.apply({"type": "remove_roundabout", "seg": _hover_seg})
				else:
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
			if _hover_seg != -1 and RoadStyle.is_ring(network.segments[_hover_seg].type):
				# A whole roundabout at once: two lanes round for a multi-lane
				# road type, one for a one-lane type.
				var spec: Dictionary = RoadStyle.TYPES[road_type]
				var per_way: int = int(spec.lanes) if spec.oneway else int(spec.lanes) / 2
				var to := RoadStyle.Type.RING2 if per_way >= 2 else RoadStyle.Type.RING
				sim.apply({"type": "resize_roundabout", "seg": _hover_seg, "lanes": 2 if to == RoadStyle.Type.RING2 else 1})
			elif _hover_seg != -1:
				sim.apply({"type": "upgrade_road", "seg": _hover_seg, "road": road_type})
		Mode.STRAIGHT, Mode.CURVED, Mode.SCURVE:
			var p := _snapped(hit)
			var needed: int = {Mode.STRAIGHT: 2, Mode.CURVED: 3, Mode.SCURVE: 4}[mode]
			if _points.size() + 1 < needed:
				_points.append(p)
			else:
				var drawn := _pending_curves(p)
				if _can_build(drawn):
					var curves := drawn.duplicate()
					if parallel:
						for curve in drawn:
							curves.append(RoadShapes.offset(curve, parallel_gap))
					var go := func() -> void:
						# One road drawn is one change: an S-curve's halves go
						# in together or not at all, and undo as one. Parallel's
						# twin is its own change, as for every road.
						if not _build_all(drawn):
							return
						if parallel:
							var twin := []
							for curve in drawn:
								twin.append(RoadShapes.offset(curve, parallel_gap))
							_build_all(twin)
						_points.clear()
						_points.append(drawn[drawn.size() - 1][2])
					_ask_first(p, curves, road_type, go)
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
			var over := _ring_under(hit)
			if over != -1:
				sim.apply({"type": "resize_roundabout", "seg": over, "lanes": roundabout_lanes, "radius": _ring_radius()})
				_update_hint()
				return
			var at := _snapped(hit)
			var cmd := {"type": "build_roundabout", "center": _xz(at),
				"radius": _ring_radius(), "lanes": roundabout_lanes, "road": road_type}
			_ask_first(at, RoadShapes.roundabout(at, _ring_radius()), _ring(), func(): sim.apply(cmd))
	_update_hint()


## Builds the grid inside the shape drawn so far.
func _finish_grid(shape: Array = _points) -> void:
	if not _armed.is_empty():
		_click()  # Enter again: build it anyway
		return
	if shape.size() < 3:
		return
	var pts := []
	for q in shape:
		pts.append(_xz(q))
	var cmd := {"type": "build_grid_shape", "points": pts, "block": grid_block, "across": grid_across,
		"side": grid_side, "road": road_type, "fit": _fit(), "join": true}
	var lines := GridFill.plan(network, shape, grid_block, road_type, grid_side, grid_across, _fit(),
		sim.painted_near(shape))
	var go := func() -> void:
		if sim.apply(cmd):
			_points.clear()
	# Held at the first corner: the shape shows closed while it asks.
	_ask_first(shape[0], lines, road_type, go)
	_update_hint()


## Runs `go` now, unless the road would wipe something out: then the first
## click holds the road still and asks, and the next click runs it.
func _ask_first(p: Vector3, curves: Array, type: int, go: Callable) -> void:
	_loss_key = ""  # look again now, whatever was shown last
	_loss_at = -1000
	if _check_losses(curves, type).is_empty():
		go.call()
		return
	_armed = {"p": p, "go": go}


## What these roads would wipe out (CitySim.road_losses), looked up again at
## most a few times a second while the preview moves.
func _check_losses(curves: Array, type: int) -> Array:
	var key := "%s|%d|%d|%d|%d|%d" % [str(curves), type, sim.network.revision, sim.buildings.size(),
		sim.parks.sites.size(), sim.services.buildings.size()]
	if key != _loss_key and (Time.get_ticks_msec() - _loss_at > 120 or _loss_key == ""):
		_loss_key = key
		_loss_at = Time.get_ticks_msec()
		_losses = sim.road_losses(curves, type)
	return _losses


## The cursor label's warning, and the question once the road is held.
func _warn_label() -> void:
	var what := RoadWins.loss_text(_losses)
	var lead := "Are you sure? It removes %s.\nClick again to build, right click to go back" % what \
		if not _armed.is_empty() else "Removes %s" % what
	_label.text = (_label.text + "\n" if _label.visible and _label.text != "" else "") + lead
	if not _label.visible:
		_label.position = _cursor.position + Vector3(0, 6, 0)
	_label.modulate = WARN_TEXT
	_label.visible = true


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
		if _points.size() >= 2 and _snap_kind == "segment":
			return _square_onto_road(p)
		return p
	if _points.size() == 1:
		return _side_end(p)
	if _points.size() == 3:
		# The fourth corner of a rectangle (or parallelogram) pulls hard.
		var q: Vector3 = _points[0] + _points[2] - _points[1]
		if _flat_dist(p, q) < maxf(_snap_reach(SNAP_NODE, SNAP_PX * 3.0), _flat_dist(_points[1], _points[2]) * 0.12):
			return q
	if _shift():
		return _square_off(p)
	# Brawn: odd shapes are fine, but the grid wants to be regular. A side
	# near square to the last one (or straight on) lines up exactly, and in
	# Exact runs whole blocks: along the first side's blocks, or across.
	var last: Vector3 = _points[_points.size() - 1]
	var prev: Vector3 = _points[_points.size() - 2]
	var d := p - last
	var ref := atan2(last.z - prev.z, last.x - prev.x)
	var first := atan2(_points[1].z - _points[0].z, _points[1].x - _points[0].x)
	var ang := atan2(d.z, d.x)
	for k in 4:
		var g: float = ref + k * PI * 0.5
		if absf(angle_difference(ang, g)) < REGULAR_SNAP:
			_guide_angle = g
			var len := Vector2(d.x, d.z).length()
			if grid_exact:
				var along := absf(cos(angle_difference(g, first))) > 0.7
				len = absf(_whole(len, grid_block if along else grid_across, 0 if along else 1))
				return last + Vector3(cos(g), 0.0, sin(g)) * len
			# Along the square side to where it lines up with a junction.
			return _align(last + Vector3(cos(g), 0.0, sin(g)) * len, last, g)
	return p if grid_exact else _align(p, last)


## Brawn: a corner dragged onto a road lands where the square (or straight
## on) side meets that road, so the shape closes square against it, the way
## a new subdivision's streets meet the road it fronts.
func _square_onto_road(p: Vector3) -> Vector3:
	var s := network.find_segment_near(p, 0.5)
	if s.is_empty():
		return p
	var c := network.curve_of(s.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], s.t)
	var last: Vector3 = _points[_points.size() - 1]
	var prev: Vector3 = _points[_points.size() - 2]
	var ref := atan2(last.z - prev.z, last.x - prev.x)
	var l2 := Vector2(last.x, last.z)
	var p2 := Vector2(p.x, p.z)
	var ang := atan2(p.z - last.z, p.x - last.x)
	var best := INF
	var out := p
	for k in 4:
		var shift := _shift()
		if shift and k % 2 == 0:
			continue  # Shift squares off the last side
		var g: float = ref + k * PI * 0.5
		if not shift and absf(angle_difference(ang, g)) > ROAD_SQUARE_SNAP:
			continue
		var dir := Vector2(cos(g), sin(g))
		var x = Geometry2D.line_intersects_line(l2, dir, p2, Vector2(tan.x, tan.z))
		if x == null or (x - l2).dot(dir) <= 1.0:
			continue
		var d := (x as Vector2).distance_to(p2)
		if d < best and d < maxf(_snap_reach(SNAP_ROAD + 5.0, SNAP_PX) * 3.0, l2.distance_to(p2) * 0.15):
			best = d
			_guide_angle = g
			_square = shift and _points.size() == 2
			out = Vector3(x.x, 0.0, x.y)
	return out


## Shift, but not as part of Cmd+Shift (the Mac screenshot keys) or the
## Windows key's shortcuts.
func _shift() -> bool:
	return Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_META)


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
	if _shift():
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
	_grid_angles(p)
	if _points.size() >= 2:
		# The square side as a dotted line on past the corner, and the
		# junctions the corner lines up with.
		var lines := _align_lines.duplicate()
		if not is_nan(_guide_angle):
			var last: Vector3 = _points[_points.size() - 1]
			lines.append([last, p + Vector3(cos(_guide_angle), 0.0, sin(_guide_angle)) * maxf(150.0, 200.0 * _px)])
		_dashes(lines)
	else:
		_show_guide(_points[0])
	var plan := []
	if shape.size() >= 3:
		var key := "%s|%s|%s|%d|%d|%d|%d" % [str(shape), str(grid_block), str(grid_across), grid_side, road_type,
			sim.network.segments.size(), _fit()]
		# Big towns take a moment to plan, so replan at most a few times a second.
		if key != _grid_key and Time.get_ticks_msec() - _grid_planned_at > 120:
			_grid_key = key
			var painted := sim.painted_near(shape)
			_grid_plan = GridFill.plan(network, shape, grid_block, road_type, grid_side, grid_across, _fit(), painted)
			# The county road or highway the grid takes over shows too.
			_grid_taken = []
			for t in GridFill.taken_over(_grid_plan, painted, shape):
				_grid_taken += t.curves
			_grid_planned_at = Time.get_ticks_msec()
		plan = _grid_plan
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := maxf(RoadStyle.half_width(road_type), GHOST_PX * 0.5 * _px)
	var edge := maxf(0.4, LINE_PX * 0.5 * _px)
	for c in plan + (_grid_taken if shape.size() >= 3 else []):
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
	if ok and not plan.is_empty() and not _check_losses(plan, road_type).is_empty():
		_preview.material_override = _warn_mat
		_warn_label()
	_preview.visible = true
	if not ghost.is_empty():
		_ghost.mesh = Terrain.drape(gst.commit(), true)
		_ghost.visible = true


## Draws the guide line the grid's side snapped to, through `at`.
func _show_guide(at: Vector3) -> void:
	if is_nan(_guide_angle):
		return
	var dir := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
	_dashes([[at - dir * 400.0, at + dir * 400.0]])


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
	elif parallel and mode in [Mode.STRAIGHT, Mode.CURVED, Mode.SCURVE]:
		parallel_gap = clampf(parallel_gap * f, _min_gap(), PARALLEL_MAX)
	else:
		return
	_update_hint()


func _build(curve: Array) -> bool:
	# Drawn onto or across a county road, the town takes over that mile.
	# Raised: the road climbs over the roads and track it crosses.
	return sim.apply({"type": "build_road", "start": _xz(curve[0]), "ctrl": _xz(curve[1]),
		"end": _xz(curve[2]), "road": road_type, "join": true, "over": elevation > 0.0})


## Builds the curves of one drawn road: one curve as a road, an S-curve's
## two halves as one command (CitySim._build_roads).
func _build_all(curves: Array) -> bool:
	if curves.size() == 1:
		return _build(curves[0])
	var roads := []
	for c in curves:
		roads.append([_xz(c[0]), _xz(c[1]), _xz(c[2])])
	return sim.apply({"type": "build_roads", "roads": roads, "road": road_type, "join": true, "over": elevation > 0.0})


## The pieces a raised road is built as (Overpass), worked out once per
## change of the drawn road.
func _plan(curve: Array) -> Dictionary:
	if elevation <= 0.0:
		return {"ok": true, "pieces": [curve], "crossed": 0, "why": ""}
	var key := [curve, road_type, sim.network.revision, sim.rail.version]
	if not _plan_memo.has(key):
		if _plan_memo.size() >= 8:
			_plan_memo.clear()
		_plan_memo[key] = Overpass.plan(sim, curve, road_type)
	return _plan_memo[key]


## The county road (CountyGrid.mile_at) a point is on, or {}: in town too,
## where lots keep off it, so a street drawn to it there snaps on and joins
## (Brawn 2026-10-24: roads drawn to meet county roads in town missed them).
func _county_at(p: Vector3, reach := 0.5) -> Dictionary:
	if absf(p.y) > 0.5:
		return {}
	var o := sim.terrain_offset
	var mile := CountyGrid.mile_at(p.x + o.x, p.z + o.y, reach)
	if mile.is_empty() or sim.county_removed.has(mile.key) or not CountyGrid.clears(mile.on.x, mile.on.y):
		return {}
	return mile


## Where two county roads cross (a section corner) within `reach` of `p`,
## in town coordinates, or (INF, INF): it pulls like a junction does.
func _county_crossing(p: Vector3, reach: float) -> Vector2:
	if absf(p.y) > 0.5:
		return Vector2(INF, INF)
	var o := sim.terrain_offset
	var ns := false
	var ew := false
	for m in CountyGrid.miles_at(p.x + o.x, p.z + o.y, reach):
		if sim.county_removed.has(m.key):
			continue
		ns = ns or m.key.begins_with("ns")
		ew = ew or m.key.begins_with("ew")
	if not (ns and ew):
		return Vector2(INF, INF)
	var c := Vector2(roundf((p.x + o.x) / CountyGrid.SECTION), roundf((p.z + o.y) / CountyGrid.SECTION)) * CountyGrid.SECTION
	if not CountyGrid.clears(c.x, c.y):
		return Vector2(INF, INF)
	return c - Vector2(o.x, o.y)


## The state highway (Highways.near) under `p`, in town or out, if any.
func _highway_at(p: Vector3, reach := 0.5) -> Dictionary:
	if absf(p.y) > 0.5:
		return {}
	var o := sim.terrain_offset
	var hw := Highways.near(p.x + o.x, p.z + o.y, reach)
	if hw.is_empty() or Terrain.water(hw.on.x, hw.on.y) >= 0.1:
		return {}
	return hw


## Closest two roads can run side by side: sidewalk to sidewalk.
func _min_gap() -> float:
	return RoadStyle.right_of_way_half(road_type) * 2.0


static func _xz(v: Vector3) -> Array:
	return [v.x, v.z, v.y]


## True while a road is half drawn.
func is_drawing() -> bool:
	return not _points.is_empty() or not _armed.is_empty()


## Drops the road being drawn (Esc and right click).
func cancel() -> void:
	_cancel()


func _cancel() -> void:
	if not _armed.is_empty():
		# Back to drawing: the road stays as it was.
		_armed = {}
		_update_hint()
		return
	_points.clear()
	_update_hint()


## The roads being drawn, ending at p: one curve, or the two halves of an
## S-curve once both its bends are placed.
func _pending_curves(p: Vector3) -> Array:
	if mode == Mode.SCURVE and _points.size() >= 3:
		return RoadShapes.s_curve(_points[0], _points[1], _points[2], p)
	return [_pending_curve(p)]


## Start, control point and end of the road being drawn, ending at p.
func _pending_curve(p: Vector3) -> Array:
	var a: Vector3 = _points[0]
	if _curvy() and _points.size() >= 2:
		var bend: Vector3 = _points[1]
		bend.y = lerpf(a.y, p.y, 0.5)
		return [a, bend, p]
	var d := p - a
	_guide_angle = NAN
	if not _curvy() and _shift():
		var ang := snappedf(atan2(d.z, d.x), ANGLE_STEP)
		p = a + Vector3(cos(ang), 0.0, sin(ang)) * d.length()
		if _snap_kind == "free":
			p = _align(p, a, ang)
	elif not _curvy() and d.length() > 2.0:
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
		if not is_nan(_guide_angle) and _snap_kind == "free":
			p = _align(p, a, _guide_angle)  # along the guide, to where it lines up
	return [a, a.lerp(p, 0.5), p]


## Curve or S-curve: their bends float free, with no angle snapping.
func _curvy() -> bool:
	return mode == Mode.CURVED or mode == Mode.SCURVE


## The point being placed is a bend, not an end.
func _placing_bend() -> bool:
	return (mode == Mode.CURVED and _points.size() == 1) or (mode == Mode.SCURVE and _points.size() in [1, 2])


## Directions of the roads at a point, for guide lines.
func _reference_angles(at: Vector3) -> Array:
	var n := network.find_node_near(at, 0.5)
	if n != -1:
		return _node_angles(n)
	var out := []
	var s := network.find_segment_near(at, 0.5)
	if not s.is_empty():
		var c := network.curve_of(s.seg)
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], s.t)
		out.append(atan2(tan.z, tan.x))
	return out


## Directions the roads leave a junction in.
func _node_angles(n: int) -> Array:
	var out := []
	for id in network.segments_at(n):
		var c := network.curve_of(id)
		var t := 0.0 if network.segments[id].a == n else 1.0
		var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
		if network.segments[id].a != n:
			tan = -tan
		out.append(atan2(tan.z, tan.x))
	return out


## Guide rays from the nearest junctions and road ends, the way CS2 offers
## them: straight on down a road's centreline past its end or junction, out
## where no road goes yet, and square to the road at the one junction nearest
## the cursor. [origin, angle] pairs; a ray only runs one way.
func _align_guides(near: Vector3, skip: Vector3) -> Array:
	var reach := maxf(ALIGN_REACH, 400.0 * _px)
	var found := []
	for id in network.nodes:
		var q: Vector3 = network.nodes[id]
		var d := Vector2(q.x - near.x, q.z - near.z).length()
		if d < reach and Vector2(q.x - skip.x, q.z - skip.z).length() > 0.5:
			found.append([d, id])
	found.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	for i in mini(found.size(), ALIGN_NODES):
		var n: int = found[i][1]
		var q: Vector3 = network.nodes[n]
		var roads := _node_angles(n)
		var rays := []
		for ang in roads:
			rays.append(ang + PI)
			if i == 0:
				rays.append(ang + PI * 0.5)
				rays.append(ang - PI * 0.5)
		for r in rays:
			var open := true
			for ang in roads:
				if absf(angle_difference(r, ang)) < deg_to_rad(20.0):
					open = false  # a road already goes that way
					break
			if open:
				out.append([q, r])
	return out


## True when the straight line from `a` to `b` crosses a road away from `a`:
## such a guide runs through the town instead of out into open ground.
func _guide_blocked(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var box := Rect2(a2, Vector2.ZERO).expand(b2).grow(1.0)
	for id in network.segments:
		var c := network.curve_of(id)
		var cb := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)).expand(Vector2(c[2].x, c[2].z))
		if not box.intersects(cb, true):
			continue
		var pts := network.sample_segment(id, 12)
		for j in pts.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(a2, b2, Vector2(pts[j].x, pts[j].z), Vector2(pts[j + 1].x, pts[j + 1].z))
			if hit != null and (hit as Vector2).distance_to(a2) > 2.0 and (hit as Vector2).distance_to(b2) > 2.0:
				return true
	return false


## Lines a free point up with nearby junctions, the way CS2 does: onto a
## guide ray, or where two guide rays cross. With `ray` (an angle) the point
## stays on the line from `from` in that direction and slides to where it
## meets a guide. A guide that would run through another road is skipped.
func _align(p: Vector3, from: Vector3, ray := NAN) -> Vector3:
	_align_lines = []
	var reach := ALIGN_PX * _px
	var p2 := Vector2(p.x, p.z)
	var near := []  # [offset, origin2, dir2, origin3]
	for g in _align_guides(p, from):
		var o := Vector2(g[0].x, g[0].z)
		var u := Vector2(cos(g[1]), sin(g[1]))
		if (p2 - o).dot(u) <= 0.0:
			continue  # behind the ray
		var off := absf((p2 - o).cross(u))
		if off < reach * (3.0 if not is_nan(ray) else 1.0):
			near.append([off, o, u, g[0]])
	near.sort_custom(func(x, y): return x[0] < y[0])
	if not is_nan(ray):
		var r := Vector2(from.x, from.z)
		var w := Vector2(cos(ray), sin(ray))
		for g in near:
			var x = Geometry2D.line_intersects_line(r, w, g[1], g[2])
			if x == null or (x as Vector2).distance_to(p2) >= reach * 1.5 or (x - r).dot(w) <= 0.0 or (x - g[1]).dot(g[2]) <= 0.0:
				continue
			var at := Vector3(x.x, p.y, x.y)
			if _guide_blocked(g[3], at):
				continue
			_align_lines = [[g[3], at]]
			return at
		return p
	var open := []
	for g in near:
		var q: Vector2 = g[1] + g[2] * (p2 - g[1]).dot(g[2])
		if not _guide_blocked(g[3], Vector3(q.x, p.y, q.y)):
			open.append(g)
	if open.is_empty():
		return p
	var a = open[0]
	var q: Vector2 = a[1] + a[2] * (p2 - a[1]).dot(a[2])
	for b in open.slice(1):
		if absf((a[2] as Vector2).cross(b[2])) < 0.2 or (b[1] as Vector2).distance_to(a[1]) < 0.5:
			continue  # parallel lines, or the same junction
		var x = Geometry2D.line_intersects_line(a[1], a[2], b[1], b[2])
		if x != null and (x as Vector2).distance_to(p2) < reach * 1.5 and (x - b[1]).dot(b[2]) > 0.0 and (x - a[1]).dot(a[2]) > 0.0:
			var at := Vector3(x.x, p.y, x.y)
			if _guide_blocked(a[3], at) or _guide_blocked(b[3], at):
				continue
			_align_lines = [[a[3], at], [b[3], at]]
			return at
	_align_lines = [[a[3], Vector3(q.x, p.y, q.y)]]
	return Vector3(q.x, p.y, q.y)


## Dotted guide lines: the start's straight-on or square guide, and the
## lines to junctions the point lined up with.
func _draw_guides(start: Vector3) -> void:
	var lines := _align_lines.duplicate()
	if not is_nan(_guide_angle) and mode != Mode.GRID:
		var dir := Vector3(cos(_guide_angle), 0.0, sin(_guide_angle))
		lines.append([start, start + dir * maxf(400.0, 600.0 * _px)])
	_dashes(lines)


## Draws [from, to] lines dotted, the same on screen at any zoom.
func _dashes(lines: Array) -> void:
	if lines.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := maxf(0.25, LINE_PX * 0.5 * _px)
	var dash := maxf(2.0, DASH_PX * _px)
	for l in lines:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var len := Vector2(b.x - a.x, b.z - a.z).length()
		var k := 0.0
		while k < len:
			var e := minf(k + dash, len)
			RoadMesh.add_strip(st, PackedVector3Array([a.lerp(b, k / len), a.lerp(b, e / len)]), -g, g, 0.3)
			k += dash * 2.0
	_guide.mesh = Terrain.drape(st.commit(), true, 8.0)
	_guide.visible = true


## The road's steepest grade, on the ground as the road is draped on it plus
## any bridge or overpass height, read over a 100 ft station the way road
## profiles are (AASHTO). Hidden on level ground (under 1%).
func _show_grade(pieces: Array) -> void:
	var g := steepest_grade(pieces, func(p: Vector3) -> float: return Terrain.base_y(p.x, p.z))
	if g.grade < 0.005:
		return
	var steep: bool = g.grade > float(RoadStyle.TYPES[road_type].grade) + 0.0005
	_grade_label.text = "%d%% grade" % roundi(g.grade * 100.0)
	_grade_label.modulate = GRADE_AMBER if steep else Color(1, 1, 1)
	_grade_label.position = Terrain.lift(g.at) + Vector3(0, 2, 0)
	_grade_label.visible = true


## Steepest grade along road pieces ([p0, p1, p2] curves) and where it is:
## {grade (rise over run), at}. `height` gives the ground (road base) height
## under a point; a point's own y is its height above that (a bridge).
static func steepest_grade(pieces: Array, height: Callable) -> Dictionary:
	var pts: Array[Vector3] = []
	var raw: Array[Vector3] = []
	for q in pieces:
		var line := RoadNetwork.sample_curve(q[0], q[1], q[2], 32)
		for p in line:
			if pts.is_empty() or Vector2(p.x - pts[-1].x, p.z - pts[-1].z).length() > 0.5:
				pts.append(Vector3(p.x, p.y + float(height.call(p)), p.z))
				raw.append(p)
	var best := {"grade": 0.0, "at": raw[0] if not raw.is_empty() else Vector3.ZERO}
	if pts.size() < 2:
		return best
	var along := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		along.append(along[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
	var station := minf(GRADE_STATION, along[-1])
	if station < 1.0:
		return best
	var j := 0
	for i in pts.size():
		while j < pts.size() - 1 and along[j] - along[i] < station:
			j += 1
		var run := along[j] - along[i]
		if run < station - 0.01:
			break
		var g := absf(pts[j].y - pts[i].y) / run
		if g > best.grade:
			best = {"grade": g, "at": raw[i].lerp(raw[j], 0.5)}
	return best


## The angle a new road makes with the roads where it starts and ends, the
## smaller side, flagged when sharper than AASHTO's 60°.
func _show_angles(curve: Array, last: Array = []) -> void:
	for i in 2:
		if i == 1 and not last.is_empty():
			curve = last  # an S-curve's far end is on its second half
		var at: Vector3 = curve[0] if i == 0 else curve[2]
		var refs := _reference_angles(Vector3(at.x, at.y, at.z))
		if refs.is_empty():
			continue
		var n := network.find_node_near(at, 0.5)
		var t: Vector3 = (curve[1] - curve[0]) if i == 0 else (curve[1] - curve[2])
		if t.length() < 0.01:
			t = (curve[2] - curve[0]) * (1.0 if i == 0 else -1.0)
		var ang := atan2(t.z, t.x)
		var best := 180.0
		for r in refs:
			var d := rad_to_deg(absf(angle_difference(ang, r)))
			best = minf(best, d if n != -1 else minf(d, 180.0 - d))
		if best < 1.0:
			continue  # along the road itself, not across it
		var l := _angle_labels[i]
		l.text = "%d°" % roundi(best)
		var sharp := best < SHARP_DEG - 0.5
		if sharp:
			l.text += " sharp"
		l.modulate = Color(1.0, 0.45, 0.35) if sharp else Color(1, 1, 1)
		# A little way along the new road, beside it, where the angle opens.
		l.position = Terrain.lift(at + Vector3(t.x, 0.0, t.z).normalized() * 45.0 * _px) + Vector3(0, 2, 0)
		l.visible = true


## Brawn: the angle at each corner of a grid as it's drawn: with the road
## at the first corner, between the sides at the last one, and where the
## shape closes back to the first.
func _grid_angles(p: Vector3) -> void:
	if _points.size() == 1:
		_show_angles([_points[0], _points[0].lerp(p, 0.5), p])
		return
	var last: Vector3 = _points[_points.size() - 1]
	_corner_angle(0, last, _points[_points.size() - 2], p)
	if _points.size() >= 3 and p.distance_to(_points[0]) > 0.01:
		_corner_angle(1, _points[0], _points[1], p)


func _corner_angle(i: int, at: Vector3, a: Vector3, b: Vector3) -> void:
	var u := Vector2(a.x - at.x, a.z - at.z)
	var v := Vector2(b.x - at.x, b.z - at.z)
	if u.length() < 1.0 or v.length() < 1.0:
		return
	var deg := rad_to_deg(absf(u.angle_to(v)))
	var l := _angle_labels[i]
	l.text = "%d°" % roundi(deg)
	var sharp := deg < SHARP_DEG - 0.5
	if sharp:
		l.text += " sharp"
	l.modulate = Color(1.0, 0.45, 0.35) if sharp else Color(1, 1, 1)
	var mid := (u.normalized() + v.normalized())
	if mid.length() < 0.01:
		mid = Vector2(-u.y, u.x)
	mid = mid.normalized() * 45.0 * _px
	l.position = Terrain.lift(at + Vector3(mid.x, 0.0, mid.y)) + Vector3(0, 2, 0)
	l.visible = true


## Whether the whole road being drawn can be built: all of it or none,
## never half an S-curve for want of money.
func _can_build(drawn: Array) -> bool:
	return drawn.all(_is_valid) and _drawn_cost(drawn) <= sim.economy.money


## What the road being drawn costs in all: every curve (both halves of an
## S-curve), as built (bridged where it's raised), twice with Parallel on.
func _drawn_cost(curves: Array) -> int:
	var cost := 0
	for curve in curves:
		var plan := _plan(curve)
		cost += CitySim.shapes_cost(plan.pieces if plan.ok else [curve], road_type)
	return cost * (2 if parallel else 1)


## Shows the road's length by the cursor, and the guide line it snapped to.
## `curves` is the road being drawn: one curve, or an S-curve's two halves.
func _show_length(curves: Array) -> void:
	var first: Array = curves[0]
	var last: Array = curves[curves.size() - 1]
	var m := 0.0
	var r := INF
	for curve in curves:
		m += RoadNetwork.polyline_length(RoadNetwork.sample_curve(curve[0], curve[1], curve[2]))
		r = minf(r, RoadNetwork.min_radius(curve[0], curve[1], curve[2]))
	_label.text = "%s ft  ·  $%s" % [CitySim.money_text(roundi(m * FT)),
		CitySim.money_text(_drawn_cost(curves))]
	if r < 2000.0:
		_label.text += "\nCurve safe at %d mph" % RoadStyle.safe_speed_mph(r)
	if absf(last[2].y) > 0.1 or absf(first[0].y) > 0.1:
		_label.text += "\nHeight %+d ft" % roundi(last[2].y * FT)
	var crossed := 0
	var top := 0.0
	var graded: Array = []  # every built piece, both halves of an S-curve, for the grade readout
	for curve in curves:
		var plan := _plan(curve)
		graded.append_array(plan.pieces if plan.ok else [curve])
		if plan.ok and plan.crossed > 0:
			crossed += plan.crossed
			for q in plan.pieces:
				top = maxf(top, maxf(q[0].y, q[2].y))
	_show_grade(graded)
	if crossed > 0:
		_label.text += "\nOverpass: clears %d crossing%s, deck %d ft up" \
			% [crossed, "" if crossed == 1 else "s", roundi(top * FT)]
	if not _align_lines.is_empty():
		_label.text += "\nLined up with %s" % ("two junctions" if _align_lines.size() > 1 else "a junction")
	if _snap_kind == "node":
		_label.text += "\nJoins the junction"
	_draw_guides(first[0])
	_show_angles(first, last)
	_label.position = Terrain.lift(last[2]) + Vector3(0, 6, 0)
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
	if _placing_bend():
		return Vector3(hit.x, 0.0, hit.z)  # the bend points float freely
	_align_lines = []
	# Junctions pull from further than the road between them, so a point
	# near one lands on it, not just beside it on the road.
	var snap := network.snap(hit, _snap_reach(SNAP_NODE + 3.0, SNAP_PX * 2.0), _snap_reach(SNAP_ROAD + 5.0, SNAP_PX))
	_snap_kind = snap.kind
	if snap.kind == "free":
		# Onto a state highway or county road out in the country, which
		# joins it to town.
		var hw := _highway_at(Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z),
			_snap_reach(SNAP_ROAD + 5.0, SNAP_PX))
		if not hw.is_empty():
			_snap_kind = "highway"
			return Vector3(hw.on.x - sim.terrain_offset.x, 0.0, hw.on.y - sim.terrain_offset.y)
		var cross := _county_crossing(Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z),
			_snap_reach(SNAP_NODE + 3.0, SNAP_PX * 2.0))
		if cross.x != INF:
			_snap_kind = "county"
			return Vector3(cross.x, 0.0 if mode == Mode.GRID else elevation, cross.y)
		var mile := _county_at(Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z),
			_snap_reach(SNAP_ROAD + 5.0, SNAP_PX))
		if not mile.is_empty():
			_snap_kind = "county"
			var o := sim.terrain_offset
			return Vector3(mile.on.x - o.x, 0.0, mile.on.y - o.y)
		var free := Vector3(hit.x, 0.0 if mode == Mode.GRID else elevation, hit.z)
		if mode == Mode.STRAIGHT or (_curvy() and not _placing_bend()):
			free = _align(free, _points[0] if not _points.is_empty() else Vector3(INF, 0, INF))
		return free
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
	_cursor.scale = Vector3.ONE * maxf(1.0, CURSOR_PX * _px / 3.0) \
		* (1.8 if _snap_kind == "node" else 1.4 if on_road else 1.0)


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
## The ring pieces of the roundabout that `seg` is part of.
func _ring_segs(seg: int) -> Array:
	var out := [seg]
	var todo := [seg]
	while not todo.is_empty():
		var s: Dictionary = network.segments[todo.pop_back()]
		for n in [s.a, s.b]:
			for other in network.segments_at(n):
				if not other in out and RoadStyle.is_ring(network.segments[other].type):
					out.append(other)
					todo.append(other)
	return out


## The middle of the roundabout `seg` is part of.
func _ring_center(seg: int) -> Vector3:
	var mid := Vector3.ZERO
	var ends := []
	for id in _ring_segs(seg):
		for n in [network.segments[id].a, network.segments[id].b]:
			if not n in ends:
				ends.append(n)
				mid += network.nodes[n]
	return mid / maxf(ends.size(), 1.0)


## A ring piece of the roundabout whose circle `hit` is on or inside, or -1.
func _ring_under(hit: Vector3) -> int:
	var seen := {}
	for id in network.segments:
		if seen.has(id) or not RoadStyle.is_ring(network.segments[id].type):
			continue
		var ring := _ring_segs(id)
		var mid := Vector3.ZERO
		var ends := []
		for seg in ring:
			seen[seg] = true
			for n in [network.segments[seg].a, network.segments[seg].b]:
				if not n in ends:
					ends.append(n)
					mid += network.nodes[n]
		mid /= maxf(ends.size(), 1.0)
		var r := 0.0
		for n in ends:
			r = maxf(r, Vector2(network.nodes[n].x - mid.x, network.nodes[n].z - mid.z).length())
		if Vector2(hit.x - mid.x, hit.z - mid.z).length() <= r + RoadStyle.half_width(network.segments[id].type) + 2.0:
			return id
	return -1


func _preview_pick(hit: Vector3) -> void:
	var near := network.find_segment_near(hit, RoadStyle.half_width(RoadStyle.Type.BOULEVARD))
	_hover_seg = -1
	if not near.is_empty() and near.dist <= RoadStyle.half_width(network.segments[near.seg].type) + 2.0:
		_hover_seg = near.seg
	if mode == Mode.UPGRADE and (_hover_seg == -1 or not RoadStyle.is_ring(network.segments[_hover_seg].type)):
		# Anywhere on or inside a roundabout picks the roundabout itself, not
		# the streets joining it (Nathan, 2026-10-25).
		var ring := _ring_under(hit)
		if ring != -1:
			_hover_seg = ring
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
				text = "Click to start a curved road. Click Curve again for an S-curve."
			elif _points.size() == 1:
				text = "Click where the road should bend."
			else:
				text = "Click to finish. Right click to stop."
			if _points.size() == 2 and _shown_problem != "":
				text = _shown_problem
		Mode.SCURVE:
			match _points.size():
				0: text = "Click to start an S-curve. Click it again for a simple curve."
				1: text = "Click where the road should first bend."
				2: text = "Click where it should bend back the other way."
				_: text = "Click to finish. Right click to stop."
			if _points.size() == 3 and _shown_problem != "":
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
			text = "Click a road to make it %s." % Words.a(Words.mid(RoadStyle.TYPES[road_type].name))
	if elevation != 0.0 and mode != Mode.BULLDOZE and mode != Mode.UPGRADE:
		text += "\n%s: new roads at %+d ft  (Page Up / Page Down)" \
			% ["Bridge" if elevation > 0.0 else "Tunnel", roundi(elevation * FT)]
		if elevation > 0.0:
			text += "\nRoads and track it crosses: it climbs over them, piers and all."
	if parallel and mode in [Mode.STRAIGHT, Mode.CURVED, Mode.SCURVE]:
		text += "\nParallel on (P): second road %d ft away  [ ]" % roundi(parallel_gap * FT)
	if not _armed.is_empty():
		text = "This road removes %s. Click again to build it anyway, or right click to go back." \
			% RoadWins.loss_text(_losses)
	hint_changed.emit(text)
