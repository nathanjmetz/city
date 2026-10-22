class_name AirportView
extends Node3D
## Draws airports and their planes. A grass strip is a mown turf runway
## with white edge markers, a gravel apron with tie-downs, a T-hangar, a
## small office, a fuel tank and an orange windsock; the paved size adds an
## asphalt runway with real FAA markings (threshold bars, centerline). Planes
## are drawn from their real model's size and colours and flown along the
## sim's flight paths, smoothly between ticks.
##
## Placeholders until the art library has airport pieces: everything for an
## airport is one merged mesh, and each plane one small mesh, so a busy
## airfield costs a handful of draw calls.

const TURF := Color(0.2, 0.3, 0.12)
const MOWN := Color(0.25, 0.36, 0.15)
const GRAVEL := Color(0.46, 0.44, 0.4)
const ASPHALT := Color(0.2, 0.2, 0.21)
const PAINT := Color(0.94, 0.94, 0.92)
const LANE := Color(0.58, 0.47, 0.33)
const METAL := Color(0.58, 0.6, 0.62)
const ROOF := Color(0.45, 0.2, 0.17)

var sim: CitySim
var frac := Callable()  # how far through the current tick, 0 to 1
var _sites := {}   # airport id -> Node3D
var _planes := {}  # plane id -> MeshInstance3D
var _paths := {}   # plane id -> [flight start tick, path]
var _plane_meshes := {}
var _mat: StandardMaterial3D
var _plan := MeshInstance3D.new()
var _plan_id := -1


func setup(s: CitySim, tick_fraction: Callable) -> void:
	sim = s
	frac = tick_fraction
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plan_mat := StandardMaterial3D.new()
	plan_mat.vertex_color_use_as_albedo = true
	plan_mat.vertex_color_is_srgb = true
	plan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plan_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plan_mat.no_depth_test = true
	plan_mat.disable_fog = true
	plan_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plan.material_override = plan_mat
	_plan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plan)
	sim.airports.changed.connect(_rebuild)
	_rebuild()


## Shows the land the selected airport would need at every bigger size
## (green where it's clear today, amber where something is in the way).
func show_plan(sel: Dictionary) -> void:
	_plan_id = int(sel.id) if sel.get("type", "") == "airport" else -1
	_draw_plan()


func _draw_plan() -> void:
	_plan.visible = _plan_id != -1 and sim.airports.sites.has(_plan_id)
	if not _plan.visible:
		return
	var a: Dictionary = sim.airports.sites[_plan_id]
	var corr := RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(Airports.TIERS.size() - 1, a.tier - 1, -1):
		var col := AirportTool.OK
		if t > a.tier:
			col = AirportTool.ROOM if sim.airports.blockers(sim, a, t, corr, _plan_id).is_empty() else AirportTool.BLOCKED
		for poly in Airports.owned(a, t):
			AirportTool._fill(st, poly, Color(col, 0.08), 0.3)
			AirportTool._outline(st, poly, Color(col, 0.85), 0.32, 1.5 + t * 1.5)
		for end in [1, -1]:
			var z := Airports.rpz(a, t, end)
			AirportTool._fill(st, z, Color(col, 0.05), 0.3)
			AirportTool._outline(st, z, Color(col, 0.5), 0.32, 1.0 + t)
	_plan.mesh = Terrain.drape(st.commit(), true, 25.0)


func _rebuild() -> void:
	for id in _sites.keys():
		var a = sim.airports.sites.get(id)
		if a == null or _sites[id].get_meta("key") != _key(a):
			_sites[id].queue_free()
			_sites.erase(id)
	for id in sim.airports.sites:
		if not _sites.has(id):
			_sites[id] = _site(sim.airports.sites[id])
	_draw_plan()


static func _key(a: Dictionary) -> String:
	return "%d:%d" % [a.tier, a.drive.size()]


func _site(a: Dictionary) -> Node3D:
	# Flat pieces bend over the land; solid ones stand on it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := Airports.tier(a.tier)
	var half := Airports.half_len(a.tier)
	var hw: float = k.width * Airports.FT * 0.5
	var basis := Basis.looking_at(a.dir, Vector3.UP)
	var flat := func(u0: float, u1: float, v0: float, v1: float, y: float, col: Color):
		st.set_color(col)
		var q := [Airports.at(a, u0, v0), Airports.at(a, u1, v0), Airports.at(a, u1, v1), Airports.at(a, u0, v1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(q[i] + Vector3(0, y, 0))
	# The cleared field around the runway, mown short.
	var rofa: float = k.rofa * Airports.FT * 0.5
	flat.call(-half - k.beyond * Airports.FT, half + k.beyond * Airports.FT, -rofa, rofa, 0.05, TURF)
	if k.surface == "turf":
		flat.call(-half, half, -hw, hw, 0.07, MOWN)
		# Mowing stripes down the strip.
		for i in 4:
			var v0 := -hw + i * hw * 0.5
			flat.call(-half, half, v0, v0 + hw * 0.25, 0.075, MOWN.lightened(0.06))
		# White edge markers every 200 ft, and an L at each corner.
		var n := int(k.runway / 200.0)
		for i in n + 1:
			var u := -half + i * (half * 2.0 / n)
			for s in [-1.0, 1.0]:
				_box(solid, Transform3D(basis, Airports.at(a, u, s * (hw + 1.0)) + Vector3(0, 0.25, 0)),
					Vector3(0.6, 0.5, 1.4), PAINT)
	else:
		flat.call(-half, half, -hw, hw, 0.08, ASPHALT)
		# Threshold bars, a dashed centerline and side stripes (FAA AC 150/5340-1).
		for e in [-1.0, 1.0]:
			for i in 8:
				var v := -hw + 2.0 + i * (hw * 2.0 - 4.0) / 7.0
				flat.call(e * (half - 6.0) - 45.0 * maxf(e, 0.0), e * (half - 6.0) + 45.0 * maxf(-e, 0.0),
					v - 0.9, v + 0.9, 0.09, PAINT)
		var dash := 120.0 * Airports.FT
		var u := -half + 70.0
		while u + dash < half - 70.0:
			flat.call(u, u + dash, -0.45, 0.45, 0.09, PAINT)
			u += dash * 2.0
		for s in [-1.0, 1.0]:
			flat.call(-half, half, s * hw - 0.9 * s - 0.45, s * hw - 0.9 * s + 0.45, 0.09, PAINT)
	# Building area: gravel apron, T-hangar, office, fuel tank.
	var side: Vector2 = k.side
	var v_in: float = rofa * a.side
	var v_out: float = (rofa + side.y) * a.side
	flat.call(-side.x * 0.5, side.x * 0.5, minf(v_in, v_out), maxf(v_in, v_out), 0.06, GRAVEL)
	var hangar_v: float = (rofa + side.y - 14.0) * a.side
	var bays := 6 if a.tier == 0 else 12
	var hangar_len := bays * 13.0
	var face := Basis.looking_at(right(a) * -a.side, Vector3.UP)
	var hpos := Airports.at(a, side.x * 0.5 - hangar_len * 0.5 - 6.0, hangar_v)
	_box(solid, Transform3D(face, hpos + Vector3(0, 2.6, 0)), Vector3(hangar_len, 5.2, 18.0), METAL)
	_box(solid, Transform3D(face, hpos + Vector3(0, 5.5, 0)), Vector3(hangar_len + 0.6, 0.6, 18.6), METAL.darkened(0.25))
	for i in bays:  # a door per bay, facing the runway
		var du := -hangar_len * 0.5 + 6.5 + i * 13.0
		_box(solid, Transform3D(face, hpos + face.x * du + face.z * -9.05 + Vector3(0, 2.0, 0)),
			Vector3(11.0, 4.0, 0.2), METAL.darkened(0.12))
	var office := Airports.at(a, -side.x * 0.5 + 14.0, (rofa + side.y - 12.0) * a.side)
	_box(solid, Transform3D(face, office + Vector3(0, 1.6, 0)), Vector3(12.0, 3.2, 8.0), Color(0.86, 0.84, 0.78))
	_box(solid, Transform3D(face, office + Vector3(0, 3.5, 0)), Vector3(13.0, 0.6, 9.0), ROOF)
	var tank := Airports.at(a, -side.x * 0.5 + 30.0, (rofa + side.y - 10.0) * a.side)
	_box(solid, Transform3D(basis, tank + Vector3(0, 0.8, 0)), Vector3(1.6, 1.6, 4.0), Color(0.3, 0.3, 0.3))
	_box(solid, Transform3D(basis, tank + Vector3(0, 2.2, 0)), Vector3(2.4, 1.8, 6.0), Color(0.92, 0.92, 0.9))
	# Windsock beside the runway's middle, on the building side.
	var sock := Airports.at(a, 0.0, (hw + 25.0) * a.side)
	_box(solid, Transform3D(Basis.IDENTITY, sock + Vector3(0, 3.0, 0)), Vector3(0.15, 6.0, 0.15), PAINT)
	var wind := Airports.bearing_dir(Airports.WIND_FROM + 180.0)
	var sb := Basis.looking_at(wind, Vector3.UP)
	_box(solid, Transform3D(sb, sock + Vector3(0, 5.6, 0) + wind * 1.2), Vector3(0.7, 0.7, 2.4), Color(1.0, 0.45, 0.1))
	# Access road out to the public road.
	if a.drive.size() >= 2:
		st.set_color(LANE)
		for i in a.drive.size() - 1:
			var p0: Vector3 = a.drive[i]
			var p1: Vector3 = a.drive[i + 1]
			var n := Vector3(-(p1 - p0).z, 0.0, (p1 - p0).x).normalized() * Farms.DRIVE_WIDTH * 0.5
			var q := [p0 - n, p1 - n, p1 + n, p0 + n]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.add_vertex(q[j] + Vector3(0, 0.12, 0))
	var root := Node3D.new()
	root.set_meta("key", _key(a))
	add_child(root)
	for entry in [[st, 8.0], [solid, 0.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape((entry[0] as SurfaceTool).commit(), true, entry[1])
		mi.material_override = _mat
		root.add_child(mi)
	return root


static func right(a: Dictionary) -> Vector3:
	return Airports.right(a)


## A box with flat normals, in the transform's frame.
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	st.set_color(col)
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dw := w * h
		var q := [c - du - dw, c - du + dw, c + du + dw, c + du - dw]
		var wn := (xf.basis * n).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(wn)
			st.add_vertex(xf * (q[i] as Vector3))


## A plane of a type, nose toward -Z, wheels at y = 0.
func _plane_mesh(type: String) -> ArrayMesh:
	if _plane_meshes.has(type):
		return _plane_meshes[type]
	var p: Dictionary = Airports.PLANES[type]
	var span: float = p.span
	var length: float = p.length
	var body: Color = p.color
	var trim: Color = p.trim
	var high := type in ["cessna", "cub"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var I := Basis.IDENTITY
	var y := 1.3
	_box(st, Transform3D(I, Vector3(0, y, 0)), Vector3(1.2, 1.3, length * 0.62), body)
	_box(st, Transform3D(I, Vector3(0, y + 0.1, length * 0.38)), Vector3(0.6, 0.8, length * 0.32), body)
	_box(st, Transform3D(I, Vector3(0, y, -length * 0.36)), Vector3(1.0, 1.0, length * 0.14), trim)  # cowling
	_box(st, Transform3D(I, Vector3(0, y, -length * 0.45)), Vector3(2.0, 0.15, 0.1), Color(0.1, 0.1, 0.1))  # prop
	_box(st, Transform3D(I, Vector3(0, y + 0.35, -length * 0.1)), Vector3(1.1, 0.6, 1.4), Color(0.25, 0.32, 0.4))  # windows
	var wy := y + (0.75 if high else -0.45)
	_box(st, Transform3D(I, Vector3(0, wy, -length * 0.08)), Vector3(span, 0.16, 1.5), body)
	for s in [-1.0, 1.0]:
		_box(st, Transform3D(I, Vector3(s * span * 0.42, wy + 0.01, -length * 0.08)), Vector3(span * 0.16, 0.17, 1.52), trim)
	_box(st, Transform3D(I, Vector3(0, y + 0.3, length * 0.5)), Vector3(span * 0.32, 0.12, 0.9), body)  # tailplane
	_box(st, Transform3D(I, Vector3(0, y + 1.0, length * 0.5)), Vector3(0.12, 1.6, 1.1), trim)  # fin
	_box(st, Transform3D(I, Vector3(0, y - 0.15, 0)), Vector3(1.22, 0.18, length * 0.6), trim)  # stripe
	for s in [-1.0, 1.0]:
		_box(st, Transform3D(I, Vector3(s * 1.1, 0.35, -length * 0.08)), Vector3(0.2, 0.7, 0.5), Color(0.1, 0.1, 0.1))
	if type == "duster":
		_box(st, Transform3D(I, Vector3(0, wy - 0.2, -length * 0.02)), Vector3(span * 0.9, 0.06, 0.06), Color(0.3, 0.3, 0.3))  # spray boom
	var mesh := st.commit()
	_plane_meshes[type] = mesh
	return mesh


func _process(_delta: float) -> void:
	var t: float = float(sim.tick_count) + (float(frac.call()) if frac.is_valid() else 0.0)
	for pid in _planes.keys():
		if not sim.airports.planes.has(pid):
			_planes[pid].queue_free()
			_planes.erase(pid)
			_paths.erase(pid)
	for pid in sim.airports.planes:
		var p: Dictionary = sim.airports.planes[pid]
		if not sim.airports.sites.has(p.ap):
			continue
		var a: Dictionary = sim.airports.sites[p.ap]
		if not _planes.has(pid):
			var mi := MeshInstance3D.new()
			mi.mesh = _plane_mesh(p.type)
			mi.material_override = _mat
			add_child(mi)
			_planes[pid] = mi
		var path := []
		if p.state == "flying":
			var cached: Array = _paths.get(pid, [])
			if cached.is_empty() or cached[0] != p.flight.start:
				cached = [p.flight.start, Airports.flight_path(a, p, p.flight)]
				_paths[pid] = cached
			path = cached[1]
		var pose := Airports.pose(a, p, path, t)
		var mi: MeshInstance3D = _planes[pid]
		mi.visible = not pose.is_empty()
		if pose.is_empty():
			continue
		var fwd: Vector3 = pose[1]
		var flat := Vector3(fwd.x, 0.0, fwd.z)
		if flat.length() < 0.01:
			flat = a.dir
		var b := Basis.looking_at(flat.normalized(), Vector3.UP)
		# Nose up in a climb, down on the glide path.
		b = b.rotated(b.x, clampf(asin(clampf(fwd.y, -1.0, 1.0)), -0.35, 0.35))
		var at: Vector3 = pose[0]
		mi.transform = Transform3D(b, at + Vector3(0, Terrain.ground_y(at.x, at.z), 0))
