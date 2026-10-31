class_name RoadMesh
extends RefCounted
## Turns sampled centre lines into flat ribbon meshes.

## Curbs stand up off the street (RoadView sets this from the graphics
## tier: the desktop's High and up). Otherwise a curb is a flat band.
static var raised_curbs := false
## A 4 in rolled curb, the usual curb of an Indiana subdivision street
## (INDOT E 605 combined concrete curb and gutter, roll type): its face
## rises over about 6 in from the gutter's edge to a rounded top.
const CURB_RISE := 0.1
const CURB_ROLL := 0.15
## Where a curb ramp meets the street the curb drops flush with it (ADA),
## from RAMP_FROM to RAMP_TO metres in from each end of a street, eased
## over RAMP_EASE.
const RAMP_FROM := 0.3
const RAMP_TO := 2.7
const RAMP_EASE := 0.3


## Adds a ribbon running alongside pts, from offset `from` to offset `to`
## (negative = left side, positive = right side). UV.y * 4 is the distance
## along it, counted from `start`.
static func add_strip(st: SurfaceTool, pts: PackedVector3Array, from: float, to: float, y: float,
		start := 0.0) -> void:
	if pts.size() < 2:
		return
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in pts.size():
		var side := _side(pts, i)
		var p := Vector3(pts[i].x, pts[i].y + y, pts[i].z)
		lefts.append(p + side * from)
		rights.append(p + side * to)
	var dist := start
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
## `treat`: the road's treatment (RoadTreatments.look): {"left", "right",
## "mid"}, each "factory", "main" or "" (today's look); town streets only.
static func street(pts: PackedVector3Array, type: int, mats: Dictionary, gaps := {}, rural := false,
		cuts := Vector2.ZERO, breaks := [], urban := false, dips := Vector2.ONE, treat := {}) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	if RoadStyle.is_freeway(type):
		return _oneway(pts, spec, mats, gaps)
	if urban:
		return _town(pts, type, mats, cuts, true, dips, treat)
	if spec.get("rural", false) or (rural and spec.median == 0.0):
		return _rural(pts, type, mats, breaks)
	return _town(pts, type, mats, cuts, false, dips, treat)


## A town street with curbs and sidewalks. Markings follow MUTCD Part 3B:
## a double yellow centre line on multi-lane roads, a solid-and-dashed
## yellow pair each side of a two-way left-turn lane, white dashes between
## lanes going the same way, a solid white bike lane line, and white stall
## marks where parking is metered downtown.
## `dips`: 0 at an end whose corners have a diagonal ramp instead of ramps
## in line with the crosswalk (Junction.pair_ramps), where the curb stays up.
static func _town(pts: PackedVector3Array, type: int, mats: Dictionary, cuts := Vector2.ZERO, urban := false,
		dips := Vector2.ONE, treat := {}) -> ArrayMesh:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw := RoadStyle.half_width(type)
	var cw := RoadStyle.CURB_WIDTH
	var w0 := hw + cw + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var hm: float = spec.median * 0.5
	var lane := 3.6
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var surface: String = spec.get("surface", "asphalt")
	var factory_mid: bool = treat.get("mid", "") == RoadTreatments.FACTORY and surface == "asphalt" \
		and mats.has("concrete")
	if factory_mid:
		surface = "concrete"  # jointed concrete, built for trucks
	var layers := [
		[surface, [[-hw, hw]], RoadStyle.Y_ASPHALT, ""],
	]
	if not raised_curbs:
		layers.append(["curb", [[-hw - cw, -hw], [hw, hw + cw]], RoadStyle.Y_CURB, ""])
	# Combined concrete curb and gutter (INDOT standard E 605-CCCG): a 2 ft
	# concrete gutter pan along each edge of the pavement, and the curb's
	# face reading as a thin shaded line.
	if mats.has("curb_face") and not raised_curbs:
		var g := RoadStyle.GUTTER_WIDTH
		layers.append(["curb", [[-hw, -hw + g], [hw - g, hw]], RoadStyle.Y_ASPHALT + 0.004, ""])
		layers.append(["curb_face", [[-hw - 0.07, -hw], [hw, hw + 0.07]], RoadStyle.Y_CURB + 0.003, ""])
	if spec.get("walk", true) or urban:
		if treat.is_empty():
			layers.append(["walk", [[-w1, -w0], [w0, w1]], RoadStyle.Y_SIDEWALK, ""])
		else:
			layers.append_array(treated_walks(treat, hw, cw, w0, w1))
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
	if raised_curbs:
		var g := RoadStyle.GUTTER_WIDTH
		var pan := SurfaceTool.new()
		pan.begin(Mesh.PRIMITIVE_TRIANGLES)
		add_strip(pan, pts, -hw, -hw + g, RoadStyle.Y_ASPHALT + 0.004)
		add_strip(pan, pts, hw - g, hw, RoadStyle.Y_ASPHALT + 0.004)
		var length := RoadNetwork.polyline_length(pts)
		for side in [-1.0, 1.0]:
			var edge := PackedVector3Array()
			var back := PackedVector3Array()
			var rises := PackedFloat32Array()
			for d in _curb_stations(length):
				var at: Array = LotPlanner.point_at(pts, d)
				var n: Vector3 = Vector3(-at[1].z, 0.0, at[1].x).normalized() * side
				edge.append(at[0] + n * hw)
				back.append(at[0] + n * (hw + cw))
				rises.append(_ramp_rise(d, length, dips))
			add_curb(pan, edge, back, rises)
		if not spec.get("angle", false) and not (spec.get("parking", 0) > 0 and spec.oneway):
			# A main street side's stalls: a 23 ft parallel stall between
			# ticks out from the gutter (MUTCD 3B.19), laid with the gutter
			# pan so they cost no draw of their own.
			for side in [-1.0, 1.0]:
				if treat.get("right" if side > 0.0 else "left", "") != RoadTreatments.MAIN:
					continue
				var at := hw + 6.0
				while at < length - hw - 6.0:
					_slant(pan, pts, at, side * (hw - 2.2), at, side * (hw - g), RoadStyle.Y_ASPHALT + 0.006)
					at += 7.0
		pan.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats.curb)
		if mats.has("iron"):
			# A factory middle's jointed concrete: contraction joints sawn
			# across the slab every 15 ft (INDOT jointed plain concrete
			# pavement), dark with their sealant, laid with the iron's dark.
			var joints := []
			if factory_mid:
				var j := hw + 2.0
				var mlen := RoadNetwork.polyline_length(marks)
				while j < mlen - 2.0:
					joints.append(j)
					j += 4.6
			_castings(mesh, pts, length, hw, lane_edge, mats, marks, joints)
		if mats.has("wear"):
			var centres := []
			if spec.oneway:
				for k in spec.lanes:
					centres.append(-lane_edge + lane * (k + 0.5))
			else:
				for k in spec.lanes / 2:
					centres.append(inner + lane * (k + 0.5))
					centres.append(-inner - lane * (k + 0.5))
			var wear := SurfaceTool.new()
			wear.begin(Mesh.PRIMITIVE_TRIANGLES)
			for c: float in centres:
				add_strip(wear, marks, c - 1.5, c + 1.5, RoadStyle.Y_ASPHALT + 0.005)
			wear.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats.wear)
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


## A treated road's walks, side by side (RoadTreatments): a factory side
## gets a narrow 4 ft walk at the back with a wider mowed strip; a main
## street side is paved from the curb to the storefronts. Both are the
## walk's own layer, so a treated road draws no more than a plain one.
static func treated_walks(treat: Dictionary, hw: float, cw: float, w0: float, w1: float) -> Array:
	var walk := []
	for side in [-1.0, 1.0]:
		var span := [w0, w1]
		match treat.get("right" if side > 0.0 else "left", ""):
			RoadTreatments.FACTORY:
				span = [w1 - 1.2, w1]
			RoadTreatments.MAIN:
				span = [hw + cw, w1]
		walk.append([side * span[0], side * span[1]] if side > 0.0 else [side * span[1], side * span[0]])
	return [["walk", walk, RoadStyle.Y_SIDEWALK, ""]]


## Iron in the street, as the desktop's raised curbs draw it: a curb inlet
## in the gutter pan at each corner, just short of the curb ramp, where the
## water runs to (INDOT standard E 720 type J: a cast grate with its bars
## along the gutter, 2 by 3 ft), and a sanitary manhole cover down the
## middle of a lane every block or so (Neenah R-1642 style, 27 in round).
static func _castings(mesh: ArrayMesh, pts: PackedVector3Array, length: float, hw: float, lane_edge: float,
		mats: Dictionary, marks := PackedVector3Array(), joints := []) -> void:
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slots := SurfaceTool.new()
	slots.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := RoadStyle.Y_ASPHALT + 0.006
	var gw := 0.6
	var gl := 0.9
	if length > 2.0 * (RAMP_TO + RAMP_EASE + gl + 4.0):
		for side in [-1.0, 1.0]:
			for end in [0, 1]:
				var d0 := RAMP_TO + RAMP_EASE + 0.8
				var d := d0 if end == 0 else length - d0 - gl
				var a0 := hw - gw - 0.02
				var a1 := hw - 0.02
				_patch(iron, pts, d, d + gl, side, a0, a1, y)
				# Bars along the flow, with the dark between.
				var k := 0
				while k < 5:
					var b0 := a0 + 0.07 + k * 0.1
					_patch(slots, pts, d + 0.06, d + gl - 0.06, side, b0, b0 + 0.05, y + 0.002)
					k += 1
	# Manholes: down the sewer under the middle of the right-hand lane,
	# mid-block and every 90 m on a long street (Ten States Standards
	# space them no more than 400 ft apart).
	var lane_mid := maxf(lane_edge - 1.8, 1.2)
	var n := maxi(1, int(length / 90.0))
	for i in n:
		var d := length * (i + 0.5) / n
		if d < hw + 6.0 or d > length - hw - 6.0:
			continue
		var at: Array = LotPlanner.point_at(pts, d)
		var side := 1.0 if i % 2 == 0 else -1.0
		var c: Vector3 = at[0] + Vector3(-at[1].z, 0.0, at[1].x).normalized() * lane_mid * side
		add_disc(slots, c, 0.43, RoadStyle.Y_ASPHALT + 0.005, 20)
		add_disc(iron, c, 0.37, RoadStyle.Y_ASPHALT + 0.007, 20)
	for at: float in joints:
		_slant(slots, marks, at, -hw + 0.05, at, hw - 0.05, RoadStyle.Y_ASPHALT + 0.004)
	iron.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mats.iron)
	slots.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mats.drain)


## A flat patch from `d0` to `d1` metres along, `a0` to `a1` out on `side`.
static func _patch(st: SurfaceTool, pts: PackedVector3Array, d0: float, d1: float, side: float,
		a0: float, a1: float, y: float) -> void:
	var p0: Array = LotPlanner.point_at(pts, d0)
	var p1: Array = LotPlanner.point_at(pts, d1)
	var n0: Vector3 = Vector3(-p0[1].z, 0.0, p0[1].x).normalized() * side
	var n1: Vector3 = Vector3(-p1[1].z, 0.0, p1[1].x).normalized() * side
	var up := Vector3(0.0, y, 0.0)
	var q := [p0[0] + n0 * a0 + up, p0[0] + n0 * a1 + up, p1[0] + n1 * a1 + up, p1[0] + n1 * a0 + up]
	_tri(st, [q[0], Vector2.ZERO], [q[1], Vector2(0.25, 0.0)], [q[2], Vector2(0.25, 0.25)])
	_tri(st, [q[0], Vector2.ZERO], [q[2], Vector2(0.25, 0.25)], [q[3], Vector2(0.0, 0.25)])


## Distances along a street to sample its curb at: every 3 m or closer,
## and at each edge of the curb ramps' dips.
static func _curb_stations(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var marks := []
	for e: float in [RAMP_FROM - RAMP_EASE, RAMP_FROM, RAMP_TO, RAMP_TO + RAMP_EASE]:
		marks.append(e)
		marks.append(length - e)
	marks.append(0.0)
	marks.append(length)
	var n := maxi(1, ceili(length / 3.0))
	for k in n + 1:
		marks.append(length * k / n)
	marks.sort()
	for m: float in marks:
		if m >= 0.0 and m <= length and (out.is_empty() or m - out[out.size() - 1] > 0.05):
			out.append(m)
	return out


## The curb's rise `d` metres along a street `length` long: full, but
## dropped flush where a curb ramp meets the street near each end.
static func _ramp_rise(d: float, length: float, dips := Vector2.ONE) -> float:
	if (dips.x if d < length * 0.5 else dips.y) <= 0.0:
		return CURB_RISE
	var e := minf(d, length - d)
	var t := clampf(minf(e - RAMP_FROM + RAMP_EASE, RAMP_TO + RAMP_EASE - e) / RAMP_EASE, 0.0, 1.0)
	return lerpf(CURB_RISE, -0.03, t)


## A raised curb between the street's edge (`inner`) and the curb's back
## (`outer`), point by point: the rolled face up from the gutter, the top,
## and the back down into the grass. `rises` is each point's height above
## the pavement (CURB_RISE, or less where a ramp dips it).
static func add_curb(st: SurfaceTool, inner: PackedVector3Array, outer: PackedVector3Array,
		rises := PackedFloat32Array()) -> void:
	var profiles := []
	var ya := RoadStyle.Y_ASPHALT
	for i in inner.size():
		var across := outer[i] - inner[i]
		across.y = 0.0
		var w := across.length()
		var dir := across / maxf(w, 0.001)
		var rise: float = rises[i] if i < rises.size() else CURB_RISE
		var up := Vector3.UP
		profiles.append([inner[i] + up * (ya + 0.004), inner[i] + dir * minf(CURB_ROLL, w * 0.5) + up * (ya + rise),
			outer[i] + up * (ya + rise), outer[i] + up * -0.05, dir])
	var along := 0.0
	for i in range(profiles.size() - 1):
		var p0: Array = profiles[i]
		var p1: Array = profiles[i + 1]
		var step := (inner[i + 1] - inner[i]).length()
		for k in 3:
			# Face and top look up (and out over the street); the back looks
			# away from it.
			var want: Vector3 = Vector3.UP if k < 2 else p0[4]
			_wall_quad(st, p0[k], p0[k + 1], p1[k], p1[k + 1], want, along, along + step)
		along += step


static func _wall_quad(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, want: Vector3,
		v0: float, v1: float) -> void:
	var n := (b0 - a0).cross(a1 - a0)
	if n.length_squared() < 1e-10:
		n = (b1 - a1).cross(a1 - a0)
	n = n.normalized()
	if n.dot(want) < 0.0:
		n = -n
	for v in [[a0, 0.0, v0], [b0, 1.0, v0], [a1, 0.0, v1], [b0, 1.0, v0], [b1, 1.0, v1], [a1, 0.0, v1]]:
		st.set_normal(n)
		st.set_uv(Vector2(v[1], v[2]) * 0.25)
		st.add_vertex(v[0])


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
		for k in layer[1].size():
			var span: Array = layer[1][k]
			match layer[3]:
				"dashed": add_dashed_strip(st, along, span[0], span[1], layer[2])
				"median": add_strip(st, inner, span[0], span[1], layer[2])
				_: add_strip(st, along, span[0], span[1], layer[2], slab_start(pts, k) if layer[0] == "walk" else 0.0)
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[layer[0]])
	return mesh


## Where a walk's slabs start counting: a whole number of slabs, so the
## joints stay where they are, but its own for each side of each street, so
## the newer and patched slabs (Surfaces.CONCRETE) don't face each other
## across the street or repeat from block to block. The same every run.
static func slab_start(pts: PackedVector3Array, side: int) -> float:
	if pts.is_empty():
		return 0.0
	var h := hash([snappedf(pts[0].x, 0.1), snappedf(pts[0].z, 0.1), side])
	return float(h % 500) * Surfaces.SLAB


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
