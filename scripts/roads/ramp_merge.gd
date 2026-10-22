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
## How far the gore's painted chevrons run past the gore tip.
const GORE_LENGTH := 45.0
const LANE := 3.6


## Every ramp joining a highway: [{node, ramp, ramp_out: pts from the node,
## along: highway pts from the node beside the ramp, other: highway pts from
## the node the other way, sign: +1 if the ramp is to the right of `along`,
## exit: bool}]
static func merges(network: RoadNetwork) -> Array:
	var out := []
	for n in network.nodes:
		var highways := []
		var ramps := []
		for seg in network.segments_at(n):
			match int(network.segments[seg].type):
				RoadStyle.Type.HIGHWAY: highways.append(seg)
				RoadStyle.Type.RAMP: ramps.append(seg)
		if highways.size() != 2 or ramps.is_empty():
			continue
		for r in ramps:
			var ramp_pts := _from(network, r, n)
			var rdir := _dir(ramp_pts)
			var a := _from(network, highways[0], n)
			var b := _from(network, highways[1], n)
			var along := a if _dir(a).dot(rdir) >= _dir(b).dot(rdir) else b
			var other := b if along == a else a
			var side := Vector3(-_dir(along).z, 0.0, _dir(along).x)
			out.append({"node": n, "ramp": r, "ramp_out": ramp_pts, "along": along, "other": other,
				"sign": 1.0 if side.dot(rdir) >= 0.0 else -1.0,
				"exit": network.segments[r].a == n})
	return out


## How far from the highway node a ramp's drawing should start: where its
## inner edge clears the highway's outside edge line. 0 if it isn't a merge.
static func ramp_cut(m: Dictionary) -> float:
	var edge := _edge_offset()
	var hw := RoadStyle.half_width(RoadStyle.Type.RAMP)
	var pts: PackedVector3Array = m.ramp_out
	var d := 0.0
	for i in pts.size():
		if i > 0:
			d += pts[i].distance_to(pts[i - 1])
		if _lateral(m.along, pts[i]) >= edge + LANE * 0.5 + hw - 1.2:
			return d
	return d


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


## Adds the auxiliary lane, taper, re-drawn edge lines and the gore.
static func draw(m: Dictionary, asphalt: SurfaceTool, white: SurfaceTool, cover: SurfaceTool) -> void:
	var sgn: float = m.sign
	var edge := _edge_offset()
	var y_road := RoadStyle.Y_ASPHALT + 0.004
	var y_mark := RoadStyle.Y_ASPHALT + 0.02
	var cut := ramp_cut(m)
	var along: PackedVector3Array = m.along
	var other: PackedVector3Array = m.other
	# Where along the highway the ramp peels off.
	var peel := _project(along, LotPlanner.point_at(m.ramp_out, cut)[0])
	var aux := _cut_to(along, peel)
	# The auxiliary lane beside the through lanes, up to the gore.
	var hw := RoadStyle.half_width(RoadStyle.Type.HIGHWAY)
	_strip(asphalt, aux, sgn, hw - 0.5, edge + LANE + 1.0, y_road)
	_strip(cover, aux, sgn, edge - 0.1, edge + 0.3, y_road + 0.01)  # hide the old edge line
	RoadMesh.add_dashed_strip(white, _signed(aux, sgn), edge, edge + 0.3, y_mark)  # wide dotted lane line
	_strip(white, aux, sgn, edge + LANE, edge + LANE + 0.15, y_mark)
	# The taper on the far side of the node: the lane narrows into the
	# highway (entrance) or opens out of it (exit).
	var taper := _cut_to(other, TAPER_EXIT if m.exit else TAPER_ENTRANCE)
	var osgn := -sgn  # `other` runs the opposite way, so its sides flip
	_taper(asphalt, taper, osgn, hw - 0.5, edge, LANE + 1.0, y_road)
	# The edge line swings out along the taper to meet the auxiliary lane.
	var line := PackedVector3Array()
	var tl := RoadNetwork.polyline_length(taper)
	var d := 0.0
	for i in taper.size():
		if i > 0:
			d += taper[i].distance_to(taper[i - 1])
		line.append(taper[i] + _side_at(taper, i) * osgn * (edge + 0.07 + LANE * (1.0 - d / tl)))
	if line.size() >= 2:
		RoadMesh.add_strip(white, line, -0.08, 0.08, y_mark)
	# Gore: from the tip where ramp and highway part, chevrons between the
	# highway edge line and the ramp's inner edge.
	var gore_hw := _cut_to(_after(along, peel), GORE_LENGTH)
	var ramp_after := _cut_to(_after(m.ramp_out, cut), GORE_LENGTH * 1.2)
	if gore_hw.size() < 2 or ramp_after.size() < 2:
		return
	var rhw := RoadStyle.half_width(RoadStyle.Type.RAMP) - 1.2
	for k in 6:
		var f := (k + 1) / 7.0
		var p := LotPlanner.point_at(gore_hw, f * RoadNetwork.polyline_length(gore_hw))
		var hp: Vector3 = p[0] + _side(p[1]) * sgn * (edge + 0.3)
		var q := LotPlanner.point_at(ramp_after, f * RoadNetwork.polyline_length(ramp_after))
		var rp: Vector3 = q[0] - _side(q[1]) * sgn * rhw * (1.0 if m.exit else -1.0)
		if hp.distance_to(rp) < 1.0:
			continue
		var back := (_dir(gore_hw) * (-1.0 if m.exit else 1.0)) * 4.0
		RoadMesh.add_strip(white, PackedVector3Array([hp, (hp + rp) * 0.5 + back]), -0.2, 0.2, y_mark - p[0].y)
		RoadMesh.add_strip(white, PackedVector3Array([(hp + rp) * 0.5 + back, rp]), -0.2, 0.2, y_mark - p[0].y)


static func _edge_offset() -> float:
	# Right edge line of the one-way highway, measured from its centre.
	return -RoadStyle.half_width(RoadStyle.Type.HIGHWAY) + 1.2 + LANE * RoadStyle.TYPES[RoadStyle.Type.HIGHWAY].lanes


## A strip `from` to `to` metres out on the ramp's side.
static func _strip(st: SurfaceTool, pts: PackedVector3Array, sgn: float, from: float, to: float, y: float) -> void:
	if pts.size() < 2:
		return
	if sgn > 0.0:
		RoadMesh.add_strip(st, pts, from, to, y)
	else:
		RoadMesh.add_strip(st, pts, -to, -from, y)


## A strip whose outer edge narrows from `width` to 0 over its length.
static func _taper(st: SurfaceTool, pts: PackedVector3Array, sgn: float, inner: float, base: float,
		width: float, y: float, line := false) -> void:
	if pts.size() < 2:
		return
	var length := RoadNetwork.polyline_length(pts)
	var d := 0.0
	for i in pts.size() - 1:
		var d1 := d + pts[i].distance_to(pts[i + 1])
		var w0 := width * (1.0 - d / length)
		var w1 := width * (1.0 - d1 / length)
		var s0 := _side_at(pts, i) * sgn
		var s1 := _side_at(pts, i + 1) * sgn
		var lift := Vector3(0, y, 0)
		var o0: float = base + (LANE * (1.0 - d / length) if line else w0)
		var o1: float = base + (LANE * (1.0 - d1 / length) if line else w1)
		var i0: float = o0 - 0.15 if line else inner
		var i1: float = o1 - 0.15 if line else inner
		var a := pts[i] + lift + s0 * i0
		var b := pts[i] + lift + s0 * o0
		var c := pts[i + 1] + lift + s1 * i1
		var e := pts[i + 1] + lift + s1 * o1
		for v in ([a, b, c, b, e, c] if sgn > 0.0 else [a, c, b, b, c, e]):
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v)
		d = d1


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
