class_name BusView
extends Node3D
## Draws what the bus depots run: a sign at every stop (and a shelter where
## many people wait, once its depot has built shelters), and the buses standing still: in their bays, at the
## curb while people get on, or parked at a school. Moving buses are drawn
## by TrafficView like any vehicle. Cabs waiting in their company's lot or
## at the curb are drawn here too.
##
## The Bus view (Views, top left) adds each route as a coloured line, the
## stops sized by riders, and how many people are aboard each bus.

## Riders a day from which a stop gets a shelter and bench.
const SHELTER_RIDERS := 40.0
## Route colours, one per route of a depot.
const ROUTE_COLORS := [Color("#e8604c"), Color("#2a9d8f"), Color("#e9c46a"), Color("#457b9d"),
	Color("#8e5ea2"), Color("#f4a261"), Color("#6a994e"), Color("#d1495b")]
const NEAR := 240.0
const FAR := 2600.0

var sim: CitySim
## The Bus view is on: routes, stops and loads show.
var show_routes := false:
	set(v):
		show_routes = v
		_version = -1

var _stops := MeshInstance3D.new()
var _routes := MeshInstance3D.new()
var _batches := {}  # kind -> [near, far] MultiMeshInstance3D
var _labels := []   # Label3D pool
var _version := -1


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	var mat := VehicleMaterial.get_material()
	for kind in ["city_bus", "school_bus", "taxi"]:
		var pair := []
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.use_colors = true
			mm.mesh = VehicleModels.build(kind, lod)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = mat
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			pair.append(mi)
		_batches[kind] = pair
	var stop_mat := StandardMaterial3D.new()
	stop_mat.vertex_color_use_as_albedo = true
	stop_mat.roughness = 0.7
	stop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stops.material_override = stop_mat
	add_child(_stops)
	var route_mat := StandardMaterial3D.new()
	route_mat.vertex_color_use_as_albedo = true
	route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	route_mat.no_depth_test = true
	route_mat.disable_fog = true
	route_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_routes.material_override = route_mat
	_routes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_routes)


func _process(_delta: float) -> void:
	if sim == null:
		return
	if sim.buses.version != _version:
		_version = sim.buses.version
		_draw_stops()
		_draw_routes()
	_draw_buses()


func _draw_buses() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var lists := {}
	var labels := []
	for entry in sim.buses.standing(sim) + sim.taxis.standing(sim):
		var kind: String = "city_bus" if entry[0] == "coach" else entry[0]  # no coach model yet
		var front: Vector3 = entry[1]
		var dist := front.distance_to(eye)
		if show_routes and entry[3] > 0 and dist < FAR and kind != "taxi":
			labels.append([front - (entry[2] as Vector3) * 6.0 + Vector3(0, 5.0, 0), entry[3]])
		if dist > FAR or entry.size() > 4 and entry[4]:
			continue  # parked on the road: TrafficView draws it
		var lod := 0 if dist < NEAR else 1
		var key := kind + str(lod)
		if not lists.has(key):
			lists[key] = []
		lists[key].append(Transform3D(Basis.looking_at(entry[2], Vector3.UP), front))
	if show_routes:
		# Loads over the buses on the road too.
		var aboard := {}
		for tid in sim.buses.trips:
			var bus: Dictionary = sim.buses.buses.get(sim.buses.trips[tid], {})
			if not bus.is_empty() and bus.load > 0:
				aboard[tid] = bus.load
		if not aboard.is_empty():
			for car in sim.traffic.cars:
				if aboard.has(int(car.get("trip", car.id))):
					var p: Vector3 = sim.traffic.car_pose(car)[0]
					if p.distance_to(eye) < FAR:
						labels.append([p + Vector3(0, 5.0, 0), aboard[int(car.get("trip", car.id))]])
	for kind in _batches:
		for lod in 2:
			var mm: MultiMesh = _batches[kind][lod].multimesh
			var list: Array = lists.get(kind + str(lod), [])
			if list.size() > mm.instance_count:
				mm.instance_count = maxi(list.size() * 2, 8)
			var paint := VehicleTypes.paint(kind, 0)
			for i in list.size():
				mm.set_instance_transform(i, list[i])
				mm.set_instance_custom_data(i, Color(paint.r, paint.g, paint.b, 0.0))
				mm.set_instance_color(i, Color.WHITE)
			mm.visible_instance_count = list.size()
	while _labels.size() < labels.size():
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0012
		l.font_size = 22
		l.outline_size = 6
		l.modulate = Color.WHITE
		l.outline_modulate = Color(0.1, 0.12, 0.14)
		add_child(l)
		_labels.append(l)
	for i in _labels.size():
		var l: Label3D = _labels[i]
		l.visible = i < labels.size()
		if l.visible:
			l.position = labels[i][0]
			l.text = "%d aboard" % labels[i][1]


## A bus stop sign on a pole in the grass strip at each stop, and at busy
## stops a three-sided shelter with a bench (the usual US small-town kit).
func _draw_stops() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for sid in sim.buses.stops:
		var s: Dictionary = sim.buses.stops[sid]
		if not s.has("pos") or s.get("depot", -1) == -1:
			continue
		any = true
		var along: Vector3 = s.dir
		var out: Vector3 = Vector3(-along.z, 0.0, along.x) * s.side
		var base: Vector3 = s.pos + out * (RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
		var frame := Transform3D(Basis(along, Vector3.UP, -out), base)
		# Pole and sign (white with a blue band, facing the street).
		_box(st, frame, Vector3(0, 1.4, 0), Vector3(0.08, 2.8, 0.08), Color("#9aa0a2"))
		_box(st, frame, Vector3(0, 2.5, 0.06), Vector3(0.46, 0.6, 0.04), Color("#f2f2ee"))
		_box(st, frame, Vector3(0, 2.62, 0.09), Vector3(0.47, 0.18, 0.02), Color("#1f5fa8"))
		var kit: Array = sim.buses.depots.get(s.depot, {}).get("built", [])
		if "shelters" in kit and (float(s.get("riders", 0.0)) >= SHELTER_RIDERS or s.res + s.jobs >= 600.0):
			# On the sidewalk's far side: roof, back and end panels, bench.
			var sh := frame * Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.0, -(RoadStyle.PARKWAY_WIDTH * 0.5 + RoadStyle.SIDEWALK_WIDTH + 0.9)))
			_box(st, sh, Vector3(0, 2.35, 0), Vector3(3.6, 0.1, 1.6), Color("#4a5357"))
			_box(st, sh, Vector3(0, 1.2, -0.75), Vector3(3.5, 2.2, 0.05), Color(0.72, 0.8, 0.84))
			for e in [-1.0, 1.0]:
				_box(st, sh, Vector3(e * 1.75, 1.2, 0), Vector3(0.05, 2.2, 1.5), Color(0.72, 0.8, 0.84))
				_box(st, sh, Vector3(e * 1.75, 1.2, 0.78), Vector3(0.08, 2.3, 0.08), Color("#4a5357"))
			_box(st, sh, Vector3(0, 0.45, -0.45), Vector3(2.4, 0.06, 0.45), Color("#6b5a48"))
	_stops.visible = any
	if any:
		_stops.mesh = st.commit()


func _draw_routes() -> void:
	_routes.visible = show_routes
	if not show_routes:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.buses.routes:
		var list: Array = sim.buses.routes[id]
		for r in list.size():
			var route: Dictionary = list[r]
			var col: Color = ROUTE_COLORS[r % ROUTE_COLORS.size()]
			if route.buses <= 0:
				col = Color(col, 0.35)  # planned, waiting for a bus
			# Side by side where routes share a road.
			var off := (r - (list.size() - 1) * 0.5) * 1.6
			_ribbon(st, route.pts, off, 1.4, col)
			any = any or route.pts.size() > 1
	# Stops: a white disc, wider where more people get on.
	for sid in sim.buses.stops:
		var s: Dictionary = sim.buses.stops[sid]
		if s.get("depot", -1) == -1:
			continue
		var r := clampf(3.0 + sqrt(float(s.get("riders", 0.0))) * 0.6, 3.0, 9.0)
		_disc(st, s.pos, r, Color(1, 1, 1, 0.9))
		_disc(st, s.pos, r * 0.6, Color(0.12, 0.15, 0.17, 0.9))
		any = true
	_routes.visible = any
	if any:
		_routes.mesh = st.commit()


static func _ribbon(st: SurfaceTool, pts: PackedVector3Array, off: float, half: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		d.y = 0.0
		if d.length() < 0.01:
			continue
		var n := Vector3(-d.z, 0.0, d.x).normalized()
		var y := Vector3(0, 0.9, 0)
		var v := [a + n * (off - half) + y, a + n * (off + half) + y, b + n * (off + half) + y, b + n * (off - half) + y]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(v[k])


static func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var n := 16
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for p in [c, c + Vector3(cos(a1), 0, sin(a1)) * r, c + Vector3(cos(a0), 0, sin(a0)) * r]:
			st.set_color(col)
			st.add_vertex(p + Vector3(0, 1.0, 0))


static func _box(st: SurfaceTool, frame: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var uu := u * h
		var vv := v * h
		var q := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(frame.basis * n)
			st.add_vertex(frame * (q[k] as Vector3))
