class_name RampMerge
extends RefCounted
## Where a ramp meets a highway, draw it the way real interchanges look
## (AASHTO parallel-type ramps, MUTCD Part 3B markings) and the way Cities:
## Skylines 2 joins them: the ramp leaves from the outside lane, an
## auxiliary lane runs alongside, a taper widens or narrows the highway, and
## a painted gore with chevrons separates the ramp from the through lanes.
##
## The road graph is unchanged: the ramp still joins the highway's node, so
## cars route the same way. Only the drawing changes.

## Taper length: about 70 m for an exit (deceleration) and 90 m for an
## entrance (acceleration), AASHTO for 65 mph.
const TAPER_EXIT := 70.0
const TAPER_ENTRANCE := 90.0
const LANE := 3.6
## The ramp's 8 ft right shoulder, carried along the auxiliary lane.
const SHOULDER := 2.4
## The painted gore ends (and grass begins) where the two edge lines are
## this far apart, and never more than GORE_MAX metres down the ramp.
const GORE_NOSE := 6.0
const GORE_MAX := 160.0


## Every ramp joining a highway: [{node, ramp, ramp_out: pts from the node,
## along: highway pts from the node beside the ramp, other: highway pts from
## the node the other way, along_seg, other_seg, sign: +1 if the ramp is to
## the right of `along`, exit: bool}]
static func merges(network: RoadNetwork) -> Array:
	var out := []
	for n in network.nodes:
		var highways := []
		var ramps := []
		for seg in network.segments_at(n):
			var type: int = network.segments[seg].type
			if not RoadStyle.is_freeway(type):
				continue
			match RoadStyle.group(type):
				RoadStyle.Type.HIGHWAY: highways.append(seg)
				RoadStyle.Type.RAMP: ramps.append(seg)
		if highways.size() != 2 or ramps.is_empty():
			continue
		for r in ramps:
			var ramp_pts := _from(network, r, n)
			var rdir := _dir(ramp_pts)
			var a := _from(network, highways[0], n)
			var b := _from(network, highways[1], n)
			var first := _dir(a).dot(rdir) >= _dir(b).dot(rdir)
			var along := a if first else b
			var side := Vector3(-_dir(along).z, 0.0, _dir(along).x)
			var along_seg: int = highways[0] if first else highways[1]
			var sgn := 1.0 if side.dot(rdir) >= 0.0 else -1.0
			# Only ramps on the right, the shoulder side, get the full
			# treatment; a left-hand ramp just meets the highway.
			var forward: bool = network.segments[along_seg].a == n
			if (sgn > 0.0) != forward:
				continue
			out.append({"node": n, "ramp": r, "ramp_out": ramp_pts, "along": along, "other": b if first else a,
				"along_seg": along_seg, "other_seg": highways[1] if first else highways[0], "sign": sgn,
				"exit": network.segments[r].a == n, "hw_type": network.segments[along_seg].type,
				"ramp_type": network.segments[r].type})
	return out


## How far from the highway node a ramp's drawing should start: where its
## lane lines up with the auxiliary lane beside the through lanes, so the
## ramp carries straight on from it. 0 if it isn't a merge.
static func ramp_cut(m: Dictionary) -> float:
	var target := _edge_offset(m) + _ramp_inner(m)
	var pts: PackedVector3Array = m.ramp_out
	var d := 0.0
	for i in pts.size():
		if i > 0:
			d += pts[i].distance_to(pts[i - 1])
		if _lateral(m.along, pts[i]) >= target:
			return d
	return d


## Where the painted gore ends: the ramp distance at which its inner edge
## line is GORE_NOSE metres from the highway's edge line (or GORE_MAX on).
static func nose(m: Dictionary) -> float:
	var edge := _edge_offset(m)
	var length := RoadNetwork.polyline_length(m.ramp_out)
	var s := ramp_cut(m)
	while s < length - 1.0 and s < GORE_MAX:
		if _lateral(m.along, _inner_line(m, s)) - edge >= GORE_NOSE:
			return s
		s += 1.0
	return minf(s, length - 1.0)


## Stretches of concrete barrier to leave out where the ramp opens off the
## highway: {seg: {side: [from, to]}} in each segment's own distances.
static func barrier_gaps(m: Dictionary, network: RoadNetwork) -> Dictionary:
	var sgn: float = m.sign
	var n: int = m.node
	var s_nose := nose(m)
	var gaps := {}
	var hw_gap := _project(m.along, _inner_line(m, s_nose)) + 2.0
	var taper := TAPER_EXIT if m.exit else TAPER_ENTRANCE
	for entry in [[m.along_seg, sgn, hw_gap], [m.other_seg, -sgn, taper], [m.ramp, -sgn, s_nose + 2.0]]:
		var seg: int = entry[0]
		var forward: bool = network.segments[seg].a == n
		var length := RoadNetwork.polyline_length(network.sample_segment(seg))
		var side: float = entry[1] if forward else -entry[1]
		var span: Array = [0.0, entry[2]] if forward else [length - entry[2], length]
		if not gaps.has(seg):
			gaps[seg] = {}
		gaps[seg][side] = span
	return gaps


## Ramp points with the part over the highway cut away.
static func trim_ramp(pts: PackedVector3Array, cut: float, at_start: bool) -> PackedVector3Array:
	if cut <= 0.0:
		return pts
	var length := RoadNetwork.polyline_length(pts)
	if cut >= length - 1.0:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var n := maxi(2, pts.size())
	var from := cut if at_start else 0.0
	var to := length if at_start else length - cut
	for k in n:
		out.append(LotPlanner.point_at(pts, lerpf(from, to, float(k) / (n - 1)))[0])
	return out


## Adds the auxiliary lane, taper, re-drawn edge lines and barriers, and the
## paved gore with its chevrons.
static func draw(m: Dictionary, asphalt: SurfaceTool, white: SurfaceTool, cover: SurfaceTool,
		barrier: SurfaceTool) -> void:
	var sgn: float = m.sign
	var edge := _edge_offset(m)
	var hw := RoadStyle.half_width(m.hw_type)
	var outer := edge + LANE + SHOULDER  # the auxiliary lane's paved edge
	var y_road := RoadStyle.Y_ASPHALT + 0.004
	var y_mark := RoadStyle.Y_ASPHALT + 0.02
	var y_wall := RoadStyle.Y_ASPHALT + 0.5
	var cut := ramp_cut(m)
	var along: PackedVector3Array = m.along
	var other: PackedVector3Array = m.other
	# Where along the highway the ramp peels off.
	var peel := _project(along, LotPlanner.point_at(m.ramp_out, cut)[0])
	var aux := _cut_to(along, peel)
	# The auxiliary lane beside the through lanes, up to the gore.
	_strip(asphalt, aux, sgn, hw - 0.5, outer, y_road)
	_strip(cover, aux, sgn, edge - 0.1, edge + 0.3, y_road + 0.01)  # hide the old edge line
	RoadMesh.add_dashed_strip(white, _signed(aux, sgn), edge, edge + 0.3, y_mark)  # wide dotted lane line
	_strip(white, aux, sgn, edge + LANE, edge + LANE + 0.15, y_mark)
	_strip(barrier, aux, sgn, outer, outer + 0.6, y_wall)
	# The taper on the far side of the node: the lane narrows into the
	# highway (entrance) or opens out of it (exit). Its paved edge never
	# comes inside the highway's own shoulder.
	var taper := _cut_to(other, TAPER_EXIT if m.exit else TAPER_ENTRANCE)
	var osgn := -sgn  # `other` runs the opposite way, so its sides flip
	var tl := RoadNetwork.polyline_length(taper)
	var in_edge := PackedVector3Array()
	var out_edge := PackedVector3Array()
	var line := PackedVector3Array()
	var wall := PackedVector3Array()
	var d := 0.0
	for i in taper.size():
		if i > 0:
			d += taper[i].distance_to(taper[i - 1])
		var f := 1.0 - d / tl
		var side := _side_at(taper, i) * osgn
		var paved := maxf(hw, edge + (LANE + SHOULDER) * f)
		in_edge.append(taper[i] + side * (hw - 0.5))
		out_edge.append(taper[i] + side * paved)
		line.append(taper[i] + side * (edge + 0.07 + LANE * f))
		wall.append(taper[i] + side * (paved + 0.3))
	_fill(asphalt, in_edge, out_edge, y_road)
	if line.size() >= 2:
		RoadMesh.add_strip(white, line, -0.08, 0.08, y_mark)
		RoadMesh.add_strip(barrier, wall, -0.3, 0.3, y_wall)
	# The gore: paved from the tip, where the ramp leaves the auxiliary
	# lane, out to the nose, with chevrons between the two edge lines
	# (MUTCD 3B.05).
	var s_nose := nose(m)
	var rhw := RoadStyle.half_width(m.ramp_type)
	var hw_side := PackedVector3Array()
	var ramp_side := PackedVector3Array()
	var steps := maxi(2, int((s_nose - cut) / 2.0))
	for k in steps + 1:
		var s := lerpf(cut, s_nose, float(k) / steps)
		var q := LotPlanner.point_at(m.ramp_out, s)
		var rp: Vector3 = q[0] + _inward(m, q[1]) * rhw
		var h := LotPlanner.point_at(along, _project(along, rp))
		hw_side.append(h[0] + _side(h[1]) * sgn * (edge - 0.2))
		ramp_side.append(rp)
	_fill(asphalt, hw_side, ramp_side, y_road)
	var chevrons := maxi(2, int((s_nose - cut) / 9.0))
	for k in chevrons:
		var s := lerpf(cut, s_nose, (k + 1.0) / (chevrons + 1.0))
		var rp := _inner_line(m, s)
		var h := LotPlanner.point_at(along, _project(along, rp))
		var hp: Vector3 = h[0] + _side(h[1]) * sgn * (edge + 0.3)
		if hp.distance_to(rp) < 1.0:
			continue
		var back := (_dir(along) * (-1.0 if m.exit else 1.0)) * 4.0
		var mid := (hp + rp) * 0.5 + back
		RoadMesh.add_strip(white, PackedVector3Array([hp, mid]), -0.2, 0.2, y_mark - hp.y)
		RoadMesh.add_strip(white, PackedVector3Array([mid, rp]), -0.2, 0.2, y_mark - hp.y)


## A paved band between two matching edge polylines, always facing up.
static func _fill(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array, y: float) -> void:
	var lift := Vector3(0, y, 0)
	for i in mini(a.size(), b.size()) - 1:
		for tri in [[a[i], b[i], a[i + 1]], [b[i], b[i + 1], a[i + 1]]]:
			var p0: Vector3 = tri[0] + lift
			var p1: Vector3 = tri[1] + lift
			var p2: Vector3 = tri[2] + lift
			if (p1 - p0).cross(p2 - p0).y > 0.0:
				var t := p1
				p1 = p2
				p2 = t
			for v in [p0, p1, p2]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)


## Toward the highway, seen from the ramp.
static func _inward(m: Dictionary, ramp_dir: Vector3) -> Vector3:
	return -_side(ramp_dir) * float(m.sign)


## A point on the ramp's inner edge line (its 4 ft left shoulder side).
static func _inner_line(m: Dictionary, s: float) -> Vector3:
	var q := LotPlanner.point_at(m.ramp_out, s)
	return q[0] + _inward(m, q[1]) * _ramp_inner(m)


## Ramp centre to its inner edge line.
static func _ramp_inner(m: Dictionary) -> float:
	return RoadStyle.half_width(m.ramp_type) - 1.2


static func _edge_offset(m: Dictionary) -> float:
	# Right edge line of the one-way highway, measured from its centre.
	return -RoadStyle.half_width(m.hw_type) + 1.2 + LANE * RoadStyle.TYPES[m.hw_type].lanes


## A strip `from` to `to` metres out on the ramp's side.
static func _strip(st: SurfaceTool, pts: PackedVector3Array, sgn: float, from: float, to: float, y: float) -> void:
	if pts.size() < 2:
		return
	if sgn > 0.0:
		RoadMesh.add_strip(st, pts, from, to, y)
	else:
		RoadMesh.add_strip(st, pts, -to, -from, y)


static func _signed(pts: PackedVector3Array, sgn: float) -> PackedVector3Array:
	if sgn > 0.0:
		return pts
	var out := pts.duplicate()
	out.reverse()
	return out


## Segment points starting at `node`.
static func _from(network: RoadNetwork, seg: int, node: int) -> PackedVector3Array:
	var pts := network.sample_segment(seg, 32)
	if network.segments[seg].b == node:
		pts.reverse()
	return pts


static func _dir(pts: PackedVector3Array) -> Vector3:
	var i := mini(3, pts.size() - 1)
	var d := pts[i] - pts[0]
	d.y = 0.0
	return d.normalized()


static func _side(dir: Vector3) -> Vector3:
	return Vector3(-dir.z, 0.0, dir.x)


static func _side_at(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-dir.z, 0.0, dir.x)


## Distance from a point to a polyline, on the ground.
static func _lateral(pts: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var q := Vector3(p.x, 0.0, p.z)
	for i in pts.size() - 1:
		var a := Vector3(pts[i].x, 0.0, pts[i].z)
		var b := Vector3(pts[i + 1].x, 0.0, pts[i + 1].z)
		best = minf(best, Geometry3D.get_closest_point_to_segment(q, a, b).distance_to(q))
	return best


## How far along a polyline the point nearest `p` lies.
static func _project(pts: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var at := 0.0
	var d := 0.0
	for i in pts.size() - 1:
		var c := Geometry3D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		if c.distance_to(p) < best:
			best = c.distance_to(p)
			at = d + pts[i].distance_to(c)
		d += pts[i].distance_to(pts[i + 1])
	return at


## The first `length` metres of a polyline.
static func _cut_to(pts: PackedVector3Array, length: float) -> PackedVector3Array:
	var total := RoadNetwork.polyline_length(pts)
	length = minf(length, total)
	if length < 1.0:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var n := maxi(4, int(length / 4.0))
	for k in n + 1:
		out.append(LotPlanner.point_at(pts, length * k / n)[0])
	return out


## A polyline from `from` metres on.
static func _after(pts: PackedVector3Array, from: float) -> PackedVector3Array:
	var total := RoadNetwork.polyline_length(pts)
	if from >= total - 1.0:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var n := maxi(4, int((total - from) / 4.0))
	for k in n + 1:
		out.append(LotPlanner.point_at(pts, lerpf(from, total, float(k) / n))[0])
	return out
