class_name RoadMesh
extends RefCounted
## Turns sampled centre lines into flat ribbon meshes.


## Adds a ribbon running alongside pts, from offset `from` to offset `to`
## (negative = left side, positive = right side).
static func add_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float) -> void:
	if pts.size() < 2:
		return
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in pts.size():
		var side := _side(pts, i)
		var p := Vector3(pts[i].x, pts[i].y + y, pts[i].z)
		lefts.append(p + side * from)
		rights.append(p + side * to)
	var dist := 0.0
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		_quad(st, lefts[i], rights[i], lefts[i + 1], rights[i + 1], dist, dist + d)
		dist += d


## A flat disc, used to fill road junctions.
## `uv`: the texture spot the whole disc shows (one spot across a dirt
## road's wheel paths, so a dirt crossing reads as packed earth).
static func add_disc(st: SurfaceTool, center: Vector3, radius: float, y: float, steps := 24, uv := Vector2.ZERO) -> void:
	var c := Vector3(center.x, center.y + y, center.z)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		_tri(st, [c, uv],
			[c + Vector3(cos(a0), 0.0, sin(a0)) * radius, uv],
			[c + Vector3(cos(a1), 0.0, sin(a1)) * radius, uv])


## A complete road of the given type (asphalt, median, markings, curbs and
## sidewalks) as one mesh. `mats` maps a name to a material: asphalt, curb,
## walk, median, yellow, white, and each surface (gravel, concrete, dirt,
## chip seal, brick).
## `gaps` leaves a one-way road's barrier out where a ramp opens off it:
## {side (+1/-1): [from, to] metres along pts}.
## `cuts`: how far from each end (start, end) a town street's painted lines
## stop, at a junction's crosswalk (JunctionMarks.line_cut).
static func street(pts: PackedVector3Array, type: int, mats: Dictionary, gaps := {}, rural := false,
		cuts := Vector2.ZERO, breaks := [], urban := false) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	if RoadStyle.is_freeway(type):
		return _oneway(pts, spec, mats, gaps)
	if urban:
		return _town(pts, type, mats, cuts, true)
	if spec.get("rural", false) or (rural and spec.median == 0.0):
		return _rural(pts, type, mats, breaks)
	return _town(pts, type, mats, cuts)


## A town street with curbs and sidewalks. Markings follow MUTCD Part 3B:
## a double yellow centre line on multi-lane roads, a solid-and-dashed
## yellow pair each side of a two-way left-turn lane, white dashes between
## lanes going the same way, a solid white bike lane line, and white stall
## marks where parking is metered downtown.
static func _town(pts: PackedVector3Array, type: int, mats: Dictionary, cuts := Vector2.ZERO, urban := false) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw := RoadStyle.half_width(type)
	var cw := RoadStyle.CURB_WIDTH
	var w0 := hw + cw + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var hm: float = spec.median * 0.5
	var lane := 3.6
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var layers := [
		[spec.get("surface", "asphalt"), [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
		["curb", [[-hw - cw, -hw], [hw, hw + cw]], RoadStyle.Y_CURB, ""],
	]
	# Combined concrete curb and gutter (INDOT standard E 605-CCCG): a 2 ft
	# concrete gutter pan along each edge of the pavement, and the curb's
	# face reading as a thin shaded line.
	if mats.has("curb_face"):
		var g := RoadStyle.GUTTER_WIDTH
		layers.append(["curb", [[-hw, -hw + g], [hw - g, hw]], RoadStyle.Y_ASPHALT + 0.004, ""])
		layers.append(["curb_face", [[-hw - 0.07, -hw], [hw, hw + 0.07]], RoadStyle.Y_CURB + 0.003, ""])
	if spec.get("walk", true) or urban:
		layers.append(["walk", [[-w1, -w0], [w0, w1]], RoadStyle.Y_SIDEWALK, ""])
	var dashes := []
	var inner := 0.0  # centre line to the first lane
	var lane_edge := 0.0  # centre line to the outside of the outer lane
	if spec.oneway:
		# One-way street: every lane goes the drawn way, centred.
		lane_edge = lane * spec.lanes * 0.5
		for k in range(1, spec.lanes):
			var off := -lane_edge + lane * k
			dashes.append([off - 0.06, off + 0.06])
	else:
		if RoadStyle.raised_median(type):
			inner = hm + cw
			layers.append(["curb", [[-hm - cw, -hm], [hm, hm + cw]], y_mark + 0.02, "median"])
			layers.append(["median", [[-hm, hm]], y_mark + 0.03, "median"])
		elif spec.get("turn", false):
			inner = hm
			layers.append(["yellow", [[-hm + 0.01, -hm + 0.13], [hm - 0.13, hm - 0.01]], y_mark, ""])
			layers.append(["yellow", [[-hm + 0.25, -hm + 0.37], [hm - 0.37, hm - 0.25]], y_mark, "dashed"])
		elif spec.lanes > 2 or spec.get("bike", false) or spec.get("angle", false) or urban:
			# Double yellow centre line.
			layers.append(["yellow", [[-0.25, -0.12], [0.12, 0.25]], y_mark, ""])
		lane_edge = inner + lane * (spec.lanes / 2)
		for k in range(1, spec.lanes / 2):
			var off := inner + lane * k
			dashes.append([off - 0.06, off + 0.06])
			dashes.append([-off - 0.06, -off + 0.06])
	if not dashes.is_empty():
		layers.append(["white", dashes, y_mark, "dashed"])
	if spec.get("bike", false):
		layers.append(["white", [[-lane_edge - 0.15, -lane_edge], [lane_edge, lane_edge + 0.15]], y_mark, ""])
	if spec.get("bus", false) and mats.has("bus"):
		# Red curb lanes behind a wide solid white line (8 in, MUTCD 3D.02),
		# in place of the dashed line between the two lanes.
		var inside := lane_edge - lane
		layers = layers.filter(func(l): return l[3] != "dashed" or l[0] != "white")
		layers.append(["bus", [[-lane_edge, -inside - 0.2], [inside + 0.2, lane_edge]], y_mark - 0.004, ""])
		layers.append(["white", [[-inside - 0.2, -inside], [inside, inside + 0.2]], y_mark, ""])
	var marks := pts
	if cuts != Vector2.ZERO:
		marks = _between(pts, cuts.x, RoadNetwork.polyline_length(pts) - cuts.y)
	var mesh := _build_layers(pts, layers, trimmed(pts, hw + 2.0), mats, marks)
	# Downtown stall marks: T marks every 22 ft along parallel parking, and
	# 45-degree stall lines 9 ft wide for angled parking.
	var stalls := SurfaceTool.new()
	stalls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var length := RoadNetwork.polyline_length(pts)
	if spec.get("angle", false):
		var step := 2.74 / sin(PI * 0.25)
		for side in [-1.0, 1.0]:
			var at := hw + 4.0
			while at + RoadStyle.ANGLE_STALL < length - hw - 4.0:
				# Cars pull forward into the stall in their direction of travel.
				var s0 := at if side > 0.0 else at + RoadStyle.ANGLE_STALL
				var s1 := at + RoadStyle.ANGLE_STALL if side > 0.0 else at
				_slant(stalls, pts, s0, side * lane_edge, s1, side * (hw - 0.1), y_mark)
				at += step
				any = true
	elif spec.get("parking", 0) > 0 and spec.oneway:
		for side in [-1.0, 1.0]:
			var at := hw + 4.0
			while at < length - hw - 4.0:
				_slant(stalls, pts, at, side * lane_edge, at, side * (lane_edge + 2.1), y_mark)
				at += 6.7
				any = true
		add_strip(stalls, trimmed(pts, hw + 3.0), -lane_edge - 0.1, -lane_edge, y_mark)
		add_strip(stalls, trimmed(pts, hw + 3.0), lane_edge, lane_edge + 0.1, y_mark)
	if spec.oneway:
		# Straight arrows down each lane, pointing the way traffic runs
		# (MUTCD 3B.20), a car length in from each corner and every 60 m.
		var at := hw + 12.0
		while at < length - hw - 12.0:
			for k in spec.lanes:
				_arrow(stalls, pts, at, -lane_edge + lane * (k + 0.5), y_mark)
			at += 60.0
			any = true
	if any:
		stalls.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats.white)
	return mesh


## A white straight-ahead arrow 8 ft long centred on offset `off`, its
## tail `at` metres along the road and its head pointing along pts.
static func _arrow(st: SurfaceTool, pts: PackedVector3Array, at: float, off: float, y: float) -> void:
	var p0: Array = LotPlanner.point_at(pts, at)
	var p1: Array = LotPlanner.point_at(pts, at + 2.4)
	if p0.size() < 2 or p1.size() < 2:
		return
	var dir: Vector3 = p1[0] - p0[0]
	dir.y = 0.0
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var base: Vector3 = p0[0] + side * off + Vector3(0, y, 0)
	var neck := base + dir * 1.5
	var tip := base + dir * 2.4
	var w := 0.08
	_quad(st, base - side * w, base + side * w, neck - side * w, neck + side * w, 0.0, 0.0)
	_tri(st, [neck - side * 0.3, Vector2.ZERO], [neck + side * 0.3, Vector2.ZERO], [tip, Vector2.ZERO])


## A painted line 0.1 m wide from offset o0 at s0 metres along the road to
## offset o1 at s1 (a slanted stall line, or a tick across when s0 == s1).
static func _slant(st: SurfaceTool, pts: PackedVector3Array, s0: float, o0: float, s1: float, o1: float, y: float) -> void:
	var a := LotPlanner.point_at(pts, s0)
	var b := LotPlanner.point_at(pts, s1)
	var pa: Vector3 = a[0] + _flat_side(a) * o0 + Vector3(0, y, 0)
	var pb: Vector3 = b[0] + _flat_side(b) * o1 + Vector3(0, y, 0)
	var dir := pb - pa
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var across := Vector3(-dir.z, 0.0, dir.x).normalized() * 0.05
	_quad(st, pa - across, pa + across, pb - across, pb + across, 0.0, 1.0)


static func _flat_side(at: Array) -> Vector3:
	var dir: Vector3 = at[1] if at.size() > 1 else Vector3.FORWARD
	dir.y = 0.0
	dir = dir.normalized()
	return Vector3(-dir.z, 0.0, dir.x)


## A country road (MUTCD / Indiana county road photos): no curbs or
## sidewalks, solid white edge lines, a yellow centre line (dashed on two
## lanes) and gravel shoulders running off into the grass. A divided
## highway gets a grass median with a yellow left edge line each side.
## Gravel roads and alleys have no lines at all.
## `urban`: a country highway the town has grown along, drawn as a town
## street: curb and gutter, sidewalks, parking where its shoulders were,
## and a double yellow centre line (no passing in town).
## `breaks`: [[side, metres, at start]]: where a side road meets this one
## (Junction's country corners), its edge line and shoulder on that side
## stop that far from the start (or the end) so they don't cross the side
## road (MUTCD 3B.06).
static func _rural(pts: PackedVector3Array, type: int, mats: Dictionary, breaks := []) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw: float = spec.width * 0.5
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var surface: String = spec.get("surface", "asphalt")
	if surface != "asphalt":
		return _build_layers(pts, [[surface, [[-hw, hw]], RoadStyle.Y_ASPHALT, ""]], pts, mats)
	var hm: float = spec.median * 0.5
	var per_side: int = spec.lanes / 2
	var edge: float = hm + 3.6 * per_side
	var layers := [
		["asphalt", [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
	]
	if hm > 0.0:
		var grass := hm - 1.2
		layers.append(["yellow", [[-hm - 0.05, -hm + 0.1], [hm - 0.1, hm + 0.05]], y_mark, ""])
		layers.append(["median", [[-grass, grass]], y_mark + 0.03, "median"])
	elif spec.lanes > 2:
		layers.append(["yellow", [[-0.25, -0.12], [0.12, 0.25]], y_mark, ""])
	else:
		layers.append(["yellow", [[-0.06, 0.06]], y_mark, "dashed"])
	var dashes := []
	for k in range(1, per_side):
		dashes.append([hm + 3.6 * k - 0.06, hm + 3.6 * k + 0.06])
		dashes.append([-hm - 3.6 * k - 0.06, -hm - 3.6 * k + 0.06])
	if not dashes.is_empty():
		layers.append(["white", dashes, y_mark, "dashed"])
	var mesh := _build_layers(pts, layers, trimmed(pts, hw + 2.0), mats)
	# Gravel shoulders (from the pavement out, so the shader can fray their
	# outer edge into the grass) and edge lines, each side broken where a
	# side road comes in.
	var length := RoadNetwork.polyline_length(pts)
	var gravel := SurfaceTool.new()
	var white := SurfaceTool.new()
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var from := 0.0
		var to := length
		for b in breaks:
			if b[0] != side:
				continue
			if b[2]:
				from = maxf(from, b[1])
			else:
				to = minf(to, length - b[1])
		if to - from < 0.5:
			continue
		var run := pts if from <= 0.0 and to >= length else _between(pts, from, to)
		add_strip(gravel, run, side * hw, side * (hw + Junction.SHOULDER), RoadStyle.Y_SIDEWALK)
		add_strip(white, run, side * (edge + 0.05), side * (edge + 0.2), y_mark)
	for part in [[gravel, "shoulder"], [white, "white"]]:
		part[0].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats.get(part[1], mats.get("gravel")))
	return mesh


## Where a road's white edge line ends, out from its centre line (its
## outer edge), or its half width when it has none.
static func edge_line(type: int, country: bool) -> float:
	var spec: Dictionary = RoadStyle.TYPES[type]
	if not country or spec.oneway or spec.get("surface", "asphalt") != "asphalt":
		return RoadStyle.half_width(type)
	return spec.median * 0.5 + 3.6 * (spec.lanes / 2) + 0.2


## A road's solid centre line as spans out from its centre line ([] when
## it has none, or a median): the double yellow, or a single yellow on a
## two-lane country road.
static func centre_line(type: int, country: bool) -> Array:
	var spec: Dictionary = RoadStyle.TYPES[type]
	if spec.oneway or spec.median > 0.0 or spec.get("surface", "asphalt") != "asphalt":
		return []
	if spec.lanes > 2 or (not country and (spec.get("bike", false) or spec.get("angle", false))):
		return [[-0.25, -0.12], [0.12, 0.25]]
	return [[-0.06, 0.06]] if country else []


static func _post(st: SurfaceTool, c: Vector3, size: Vector3, basis: Basis) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	]
	for f in faces:
		var v := []
		for k in f:
			v.append(c + basis * (k * h))
		var n: Vector3 = (v[1] - v[0]).cross(v[3] - v[0]).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.add_vertex(v[i])


## Highways and ramps: shoulders, a yellow line on the left edge, a white
## line on the right, dashed lanes, and a concrete barrier each side.
static func _oneway(pts: PackedVector3Array, spec: Dictionary, mats: Dictionary, gaps := {}) -> ArrayMesh:
	var hw: float = spec.width * 0.5
	var left := -hw + 1.2
	var right: float = left + 3.6 * spec.lanes
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var dashes := []
	for k in range(1, spec.lanes):
		var off := left + 3.6 * k
		dashes.append([off - 0.075, off + 0.075])
	var layers := [
		["asphalt", [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
		["yellow", [[left - 0.15, left]], y_mark, ""],
		["white", [[right, right + 0.15]], y_mark, ""],
	]
	if not dashes.is_empty():
		layers.append(["white", dashes, y_mark, "dashed"])
	var mesh := _build_layers(pts, layers, pts, mats)
	# Concrete barrier each side, broken where a ramp opens off the road.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := RoadNetwork.polyline_length(pts)
	for side in [-1.0, 1.0]:
		var span: Array = gaps.get(side, [length + 1.0, length + 1.0])
		var span_from: float = maxf(span[0], 0.0)
		var span_to: float = minf(span[1], length)
		var from := hw if side > 0.0 else -hw - 0.6
		for piece in [[0.0, span_from], [span_to, length]]:
			if piece[1] - piece[0] > 0.5:
				add_strip(st, _between(pts, piece[0], piece[1]), from, from + 0.6, RoadStyle.Y_ASPHALT + 0.5)
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mats.curb)
	return mesh


## The part of a polyline from `from` to `to` metres along it.
static func _between(pts: PackedVector3Array, from: float, to: float) -> PackedVector3Array:
	if from <= 0.0 and to >= RoadNetwork.polyline_length(pts):
		return pts
	var out := PackedVector3Array()
	var n := maxi(2, int((to - from) / 3.0))
	for k in n + 1:
		out.append(LotPlanner.point_at(pts, lerpf(from, to, float(k) / n))[0])
	return out


static func _build_layers(pts: PackedVector3Array, layers: Array, inner: PackedVector3Array,
		mats: Dictionary, marks := PackedVector3Array()) -> ArrayMesh:
	# Medians stop short of the junctions so turning cars can cross; painted
	# lines stop at the crosswalks (`marks`, when given).
	var mesh := ArrayMesh.new()
	for layer in layers:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var along := pts
		if not marks.is_empty() and layer[0] in ["yellow", "white", "bus"]:
			along = marks
		for span in layer[1]:
			match layer[3]:
				"dashed": add_dashed_strip(st, along, span[0], span[1], layer[2])
				"median": add_strip(st, inner, span[0], span[1], layer[2])
				_: add_strip(st, along, span[0], span[1], layer[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[layer[0]])
	return mesh


## Bridge parts under any part of the road raised above the ground: deck
## sides and underside, and a pier every 30 m. `ground` gives the height of
## the land at a point (flat ground at 0 when not given).
static func bridge(pts: PackedVector3Array, half: float, st: SurfaceTool, ground := Callable()) -> bool:
	var any := false
	var deck := 1.5
	var since := 15.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var ga := 0.0 if not ground.is_valid() else float(ground.call(a.x, a.z))
		var gb := 0.0 if not ground.is_valid() else float(ground.call(b.x, b.z))
		if minf(a.y - ga, b.y - gb) < 1.5:
			since = 15.0
			continue
		any = true
		var side_a := _side(pts, i) * half
		var side_b := _side(pts, i + 1) * half
		var down := Vector3(0, -deck, 0)
		for sgn in [-1.0, 1.0]:
			var ta: Vector3 = a + side_a * sgn
			var tb: Vector3 = b + side_b * sgn
			_wall(st, ta, tb, ta + down, tb + down)
		_wall(st, a - side_a + down, b - side_b + down, a + side_a + down, b + side_b + down)
		since += seg
		if since >= 30.0:
			since = 0.0
			var mid := a.lerp(b, 0.5)
			# Piers stand on the river bed (or the land), a little below it.
			var foot := minf(ga, gb) - 1.0 if ground.is_valid() else 0.0
			var top := mid.y - deck
			add_box(st, Vector3(mid.x, (top + foot) * 0.5, mid.z), Vector3(1.4, top - foot, half * 1.2),
				atan2(b.x - a.x, b.z - a.z))
	return any


## A box standing on its centre, turned `yaw` radians about the vertical.
static func add_box(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var corners := []
	for k in 8:
		var v := Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		corners.append(c + basis * v)
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_wall(st, corners[f[0]], corners[f[1]], corners[f[3]], corners[f[2]])


## A four-sided panel a0-b0 over a1-b1 (any orientation, both faces drawn).
static func _wall(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3) -> void:
	for v in [a0, b0, a1, b0, b1, a1]:
		st.add_vertex(v)


## The polyline with `cut` metres taken off each end.
static func trimmed(pts: PackedVector3Array, cut: float) -> PackedVector3Array:
	var length := RoadNetwork.polyline_length(pts)
	var out := PackedVector3Array()
	if length <= cut * 2.0 + 1.0:
		return out
	var n := maxi(2, pts.size())
	for k in n:
		out.append(LotPlanner.point_at(pts, lerpf(cut, length - cut, float(k) / (n - 1)))[0])
	return out


## Like add_strip, but in 3 m dashes with 9 m gaps (the US standard).
static func add_dashed_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float) -> void:
	var length := RoadNetwork.polyline_length(pts)
	var at := 6.0
	while at + 3.0 < length - 6.0:
		var piece := PackedVector3Array()
		for k in 3:
			piece.append(LotPlanner.point_at(pts, at + k * 1.5)[0])
		add_strip(st, piece, from, to, y)
		at += 12.0


static func _side(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-dir.z, 0.0, dir.x)


static func _quad(st: SurfaceTool, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, v0: float, v1: float) -> void:
	_tri(st, [l0, Vector2(0, v0)], [r0, Vector2(1, v0)], [l1, Vector2(0, v1)])
	_tri(st, [r0, Vector2(1, v0)], [r1, Vector2(1, v1)], [l1, Vector2(0, v1)])


## Adds an upward-facing triangle. Each corner is [position, uv].
## Godot treats clockwise (seen from above) as the front face.
static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var corners := [a, b, c] if (pb - pa).cross(pc - pa).y < 0.0 else [a, c, b]
	for v in corners:
		st.set_normal(Vector3.UP)
		st.set_uv(v[1] * 0.25)
		st.add_vertex(v[0])
