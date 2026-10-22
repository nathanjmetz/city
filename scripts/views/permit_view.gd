class_name PermitView
extends Node3D
## The plan of the permit request you're looking at, drawn on the map: the
## route as a mint ribbon, roads it crosses ringed in warning yellow, and
## anything of yours it would take outlined in critical pink.
##
## Editing: drag a round handle to move a bend, drag a small one to add a
## bend there, right click a bend to take it out. The ends stay put: one is
## the hub, the other is where it's going.

signal route_edited(route: Array, hits: Dictionary)

## Height above the ground the plan floats at (drawn over everything).
const LIFT := 0.6
## Handles stay about this many pixels across at any zoom.
const HANDLE_PX := 9.0
const PICK_PX := 14.0

var sim: CitySim
var cam: CityCamera
var request := {}
var route := []   # [[x, z], ...], the edited copy
var hits := {}
var editing := false

var _imm := ImmediateMesh.new()
var _mesh := MeshInstance3D.new()
var _drag := -1
var _hover := -1   # handle under the mouse: bends 0..n-1, then midpoints n..


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
	m.disable_fog = true
	m.render_priority = 10
	_mesh.mesh = _imm
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Shows a request's plan (its current route).
func show_plan(req: Dictionary) -> void:
	request = req
	route = req.route.duplicate(true)
	hits = req.hits
	editing = false
	_drag = -1
	visible = true
	_redraw()


func hide_plan() -> void:
	request = {}
	editing = false
	_drag = -1
	visible = false


func set_editing(on: bool) -> void:
	editing = on and not request.is_empty()
	_redraw()


## Puts the route back the way it was shown.
func reset_route() -> void:
	if request.is_empty():
		return
	route = request.route.duplicate(true)
	_changed()


## The middle of the plan, for the camera.
func center() -> Vector3:
	var mid := Vector2.ZERO
	for p in route:
		mid += Vector2(p[0], p[1])
	mid /= maxf(route.size(), 1)
	return Vector3(mid.x, 0.0, mid.y)


func _process(_delta: float) -> void:
	if visible and editing:
		_redraw()  # handles keep their size on screen as the camera moves


func _input(event: InputEvent) -> void:
	if not visible or not editing or cam == null:
		return
	if event is InputEventMouseMotion:
		if _drag >= 0:
			var hit = cam.mouse_ground_point()
			if hit != null:
				route[_drag] = [snappedf(hit.x, 0.01), snappedf(hit.z, 0.01)]
				_changed()
			get_viewport().set_input_as_handled()
		else:
			_hover = _pick((event as InputEventMouseMotion).position)
		return
	var mb := event as InputEventMouseButton
	if mb == null or get_viewport().gui_get_hovered_control() != null:
		if mb != null and not mb.pressed:
			_drag = -1
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var h := _pick(mb.position)
			if h >= route.size():
				# A midpoint: a new bend goes in there.
				var i := h - route.size() + 1
				var a: Array = route[i - 1]
				var b: Array = route[i]
				route.insert(i, [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5])
				h = i
			if h > 0 and h < route.size() - 1:
				_drag = h
		else:
			_drag = -1
		# Clicks on the map belong to the plan while editing (no selecting).
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var h := _pick(mb.position)
		if h > 0 and h < route.size() - 1:
			route.remove_at(h)
			_hover = -1
			_changed()
			get_viewport().set_input_as_handled()


func _changed() -> void:
	hits = sim.permits.check(sim, route, float(request.width))
	_redraw()
	route_edited.emit(route, hits)


## Handle under a screen point: bends are 0..n-1, midpoints n..2n-2; -1 if none.
func _pick(at: Vector2) -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1
	var best := -1
	var best_d := PICK_PX
	var spots := _handles()
	for i in spots.size():
		var p: Vector3 = spots[i]
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


## World positions of every handle: bends, then midpoints.
func _handles() -> Array:
	var out := []
	for p in route:
		out.append(Terrain.lift(Vector3(p[0], LIFT, p[1])))
	for i in range(1, route.size()):
		out.append(Terrain.lift(Vector3((route[i - 1][0] + route[i][0]) * 0.5, LIFT, (route[i - 1][1] + route[i][1]) * 0.5)))
	return out


func _redraw() -> void:
	_imm.clear_surfaces()
	if request.is_empty() or route.size() < 2:
		return
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var line := PackedVector2Array()
	for p in route:
		line.append(Vector2(p[0], p[1]))
	var w := float(request.width)
	# The ground it would take, then a solid centre line.
	for poly in Geometry2D.offset_polyline(line, w * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
		_fill(poly, Color(Brand.BRAND_MINT, 0.32))
	for i in range(1, line.size()):
		_bar(line[i - 1], line[i], maxf(w * 0.18, 1.2), Color(Brand.BRAND_MINT, 0.95))
	# Roads it crosses.
	for seg in hits.get("roads", []):
		if sim.network.segments.has(seg):
			var at := _crossing(seg, line, w)
			if at.x != INF:
				_ring(at, w * 0.5 + 6.0, 1.6, Color(Brand.WARNING, 0.95))
	# Anything of yours it would take.
	for b in hits.get("buildings", []):
		var poly := _footprint(b)
		if poly.size() >= 3:
			_fill(poly, Color(Brand.CRITICAL, 0.35))
			for i in poly.size():
				_bar(poly[i], poly[(i + 1) % poly.size()], 1.2, Color(Brand.CRITICAL, 0.95))
	if editing:
		var camera := get_viewport().get_camera_3d()
		var spots := _handles()
		for i in spots.size():
			var p: Vector3 = spots[i]
			var scale := 0.5
			if camera:
				scale = camera.global_position.distance_to(p) * tan(deg_to_rad(camera.fov * 0.5)) * 2.0 \
					/ maxf(get_viewport().get_visible_rect().size.y, 1.0)
			var bend := i < route.size()
			var end := i == 0 or i == route.size() - 1
			var r := HANDLE_PX * scale * (1.0 if bend else 0.6)
			if i == _hover or i == _drag:
				r *= 1.3
			var c := Brand.INK_FAINT if end else (Brand.BRAND_CREAM if bend else Brand.BRAND_MINT)
			_disc(Vector2(p.x, p.z), r + 1.5 * scale, Brand.BRAND_INK)
			_disc(Vector2(p.x, p.z), r, c)
	_imm.surface_end()


## Where a road meets the route: the middle of its samples inside the corridor.
func _crossing(seg: int, line: PackedVector2Array, w: float) -> Vector2:
	var corr := Geometry2D.offset_polyline(line, w * 0.5 + 1.0, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	var sum := Vector2.ZERO
	var n := 0
	for p in sim.network.sample_segment(seg, 64):
		var q := Vector2(p.x, p.z)
		for c in corr:
			if Geometry2D.is_point_in_polygon(q, c):
				sum += q
				n += 1
				break
	return sum / n if n > 0 else Vector2(INF, INF)


func _footprint(b: Dictionary) -> PackedVector2Array:
	match str(b.what):
		"service":
			if sim.services.buildings.has(b.id):
				return sim.services.footprint(b.id)
		"farm":
			if sim.farms.farms.has(b.id):
				return sim.farms._yard(sim.farms.farms[b.id])
		"industry":
			if sim.industry.sites.has(b.id):
				return sim.industry._yard(sim.industry.sites[b.id])
		"lot":
			if sim.lots.has(b.id):
				return sim.lots[b.id].corners
	return PackedVector2Array()


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	for p in [a, b, c]:
		_imm.surface_set_color(col)
		_imm.surface_add_vertex(Vector3(p.x, LIFT + Terrain.ground_y(p.x, p.y), p.y))


func _fill(poly: PackedVector2Array, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		_tri(poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]], col)


func _bar(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	_tri(a - n, a + n, b + n, col)
	_tri(a - n, b + n, b - n, col)


func _disc(c: Vector2, r: float, col: Color) -> void:
	var steps := 20
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		_tri(c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, col)


func _ring(c: Vector2, r: float, width: float, col: Color) -> void:
	var steps := 40
	for i in steps:
		var a0 := Vector2(cos(TAU * i / steps), sin(TAU * i / steps))
		var a1 := Vector2(cos(TAU * (i + 1) / steps), sin(TAU * (i + 1) / steps))
		_tri(c + a0 * r, c + a0 * (r + width), c + a1 * (r + width), col)
		_tri(c + a0 * r, c + a1 * (r + width), c + a1 * r, col)
