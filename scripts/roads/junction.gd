class_name Junction
extends RefCounted
## Real street corners (AASHTO Green Book, ADA/PROWAG): where town streets
## meet, each road stops at the junction, the pavement between them is one
## piece, and every corner between two roads is a rounded curb return. The
## curb, grass strip and sidewalk wrap around that curve, and a concrete
## curb ramp with a detectable-warning pad crosses the grass to the street
## where people cross. Sharp Y junctions get the same long, clean return
## instead of ragged overlapping strips.
##
## Country junctions (paved two-way roads with gravel shoulders, the way
## Indiana county roads meet each other and a state highway) are shaped
## too, with no curbs: the side road flares out to the through road on a
## wide radius (AASHTO rural intersections, 25-50 ft), its gravel shoulder
## wraps round that radius, and the through road runs on unbroken except
## its edge line and shoulder on the side road's side, which stop where the
## radius starts (MUTCD 3B.06: edge lines don't cross the side road). Where
## neither road carries on through (a crossroads of equal roads) every road
## stops at its radius. A country road turning a corner gets the same
## radius inside and its lines follow it round. No round pad anywhere.
##
## Ramps, one-ways, roundabouts, alleys and gravel or dirt roads keep a
## plain join.

## Curb return radius by the larger road at the corner, in metres
## (Green Book: 15-25 ft on local streets, 25-40 ft where trucks turn).
const RETURN_RADIUS := {RoadStyle.Type.STREET: 6.0, RoadStyle.Type.AVENUE: 9.0, RoadStyle.Type.BOULEVARD: 12.0}
## Country corners: wider, for farm trucks and 55 mph roads (AASHTO Green
## Book rural intersections; INDOT Design Manual ch. 46: 30 ft at county
## roads, 40-50 ft where a state highway is met).
const COUNTRY_RADIUS := {RoadStyle.Type.STREET: 9.0, RoadStyle.Type.AVENUE: 10.5, RoadStyle.Type.BOULEVARD: 12.0,
	RoadStyle.Type.HIGHWAY: 12.0}
## Gravel shoulder width on a country road, out from the pavement edge.
## (Drawn a little wider than the 6 ft of stone, which the shader frays
## into the grass along its outer edge.)
const SHOULDER := 2.4
## Two roads meeting at least this straight (dot of their directions) carry
## one on through the other.
const THROUGH_DOT := -0.97
## Corners wider than this (radians) are a road bending, not a corner.
const STRAIGHT := deg_to_rad(160.0)
## A return never takes more than this share of a road's length.
const MAX_SHARE := 0.45
## Curb ramp width along the street, and how far it sits past the junction
## (ADA: 4 ft minimum ramp; 2 ft deep detectable warnings at the curb).
const RAMP_WIDTH := 2.4
const RAMP_GAP := 0.3
const DOMES_DEPTH := 0.6
const DOMES_COLOR := Color(0.55, 0.22, 0.16)


## Every shaped junction: node id -> {"trim": {seg id: metres}, "arms",
## "corners"}. Roads stop `trim` metres short of the node; the junction
## draws the rest. Nodes not in here keep the plain disc.
## `urban`: country highways drawn as town streets (RoadView), whose
## junctions get curbs but no crosswalks.
static func plan(net: RoadNetwork, rural: Dictionary = {}, urban: Dictionary = {}) -> Dictionary:
	var out := {}
	var ids := net.nodes.keys()
	ids.sort()
	for node in ids:
		var j := plan_node(net, node, rural, urban)
		if not j.is_empty():
			out[node] = j
	return out


## How far a road stops short of a node (0 when the node isn't shaped).
static func trim(plans: Dictionary, node: int, seg: int) -> float:
	return plans.get(node, {}).get("trim", {}).get(seg, 0.0)


## One node's plan ({} when it isn't shaped). A street bending at a node
## with no corner tight enough for a curb return gets a "bend" plan: the
## road keeps its full length and only the outside of the bend is filled,
## so the curb and sidewalk run on without a notch.
static func plan_node(net: RoadNetwork, node: int, rural: Dictionary = {}, urban: Dictionary = {}) -> Dictionary:
	var segs := net.segments_at(node)
	var center: Vector3 = net.nodes[node]
	if segs.size() < 2 or center.y < -1.0:
		return {}
	var country := false
	for id in segs:
		var sg: Dictionary = net.segments[id]
		var type: int = sg.type
		var spec: Dictionary = RoadStyle.TYPES[type]
		# One-ways, rings and alleys meet in a plain join.
		if spec.oneway or RoadStyle.is_ring(type) or sg.a == sg.b or type == RoadStyle.Type.ALLEY:
			return {}
		if _is_country(spec, id, rural, urban):
			country = true
	var arms := arms_at(net, node, rural, urban)
	for arm in arms:
		if arm.pts[arm.pts.size() / 2].y < -1.0:
			return {}
	if country:
		return _country(center, arms)
	# Each corner: arm i and the next arm round (counter-clockwise).
	var corners := _corners(arms, false)
	if not corners.any(func(c): return c.fillet):
		if arms.size() == 2 and corners.any(func(c): return c.theta > PI + 0.01):
			# A road bending at a node: the plain disc fills the pavement,
			# the outside of the bend gets its curb and sidewalk.
			return {"center": center, "arms": arms, "corners": corners, "trim": {}, "bend": true}
		return {}
	var trims := {}
	for arm in arms:
		trims[arm.seg] = arm.d
	var j := {"center": center, "arms": arms, "corners": corners, "trim": trims}
	if arms.any(func(a): return urban.has(a.seg)):
		# A town street meeting the highway through town: curbs, but traffic
		# stops at its edge, so it is marked like a country junction.
		j.unmarked = true
	j.poly = _outline(j)
	j.tris = Geometry2D.triangulate_polygon(j.poly)
	if j.tris.is_empty():
		return {}  # roads crowding each other: the plain disc covers it
	return j


## The junction's pavement, about the node: round each road's end, then the
## corner to the next road.
static func _outline(j: Dictionary) -> PackedVector2Array:
	var arms: Array = j.arms
	var poly := PackedVector2Array()
	for c in j.corners:
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		poly.append(a.u * a.d - a.n * a.hw)
		poly.append(a.u * a.d + a.n * a.hw)
		if c.fillet:
			poly.append_array(_arc(c, a, b, c.r))
		elif c.has("meet"):
			poly.append(c.meet)
		elif c.theta > PI:
			# The outside of a bend: round it off about the node.
			var a0: float = (a.n as Vector2).angle()
			var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
			for k in 9:
				poly.append(Vector2.from_angle(a0 + sweep * k / 8.0) * lerpf(a.hw, b.hw, k / 8.0))
	return poly


## Every road at a node as an arm leaving it: its direction u and left
## normal n there (+n faces the next arm round, counter-clockwise), half
## width, type, points out from the node, length, whether it is drawn as a
## country road, and d (how far it stops short, set by the corners).
static func arms_at(net: RoadNetwork, node: int, rural: Dictionary = {}, urban: Dictionary = {}) -> Array:
	var center: Vector3 = net.nodes[node]
	var arms := []
	for id in net.segments_at(node):
		var sg: Dictionary = net.segments[id]
		var type: int = sg.type
		var spec: Dictionary = RoadStyle.TYPES[type]
		var pts := net.sample_segment(id)
		if sg.b == node:
			pts.reverse()
		var length := RoadNetwork.polyline_length(pts)
		var ahead: Vector3 = LotPlanner.point_at(pts, minf(3.0, length * 0.5))[0]
		var u := Vector2(ahead.x - center.x, ahead.z - center.z).normalized()
		arms.append({"seg": id, "u": u, "n": Vector2(-u.y, u.x), "hw": RoadStyle.half_width(type),
			"type": type, "pts": pts, "length": length, "d": 0.0,
			"country": _is_country(spec, id, rural, urban)})
	arms.sort_custom(func(a, b): return a.u.angle() < b.u.angle())
	return arms


## True for a road drawn as a country road (no curbs).
static func _is_country(spec: Dictionary, id: int, rural: Dictionary, urban: Dictionary) -> bool:
	if urban.has(id):
		return false
	return spec.get("rural", false) or not spec.get("walk", true) or (rural.has(id) and spec.median == 0.0)


## The radius of the corner between two roads: a curb return in town, a
## wider radius in the country.
static func corner_radius(t1: int, t2: int, country := false) -> float:
	var g := maxi(RoadStyle.group(t1), RoadStyle.group(t2))
	if country:
		return COUNTRY_RADIUS.get(g, 9.0)
	return RETURN_RADIUS.get(g, 6.0)


## Each corner between an arm and the next one round, its radius fitted
## where it is tight enough for one; each arm's d is set to where its
## corners start.
static func _corners(arms: Array, country: bool) -> Array:
	var corners := []
	for i in arms.size():
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % arms.size()]
		var theta := fposmod(b.u.angle() - a.u.angle(), TAU)
		var c := {"a": i, "b": (i + 1) % arms.size(), "theta": theta, "fillet": false}
		if theta < STRAIGHT and theta > 0.01:
			_fillet(c, a, b, theta, country)
		corners.append(c)
	for c in corners:
		if c.fillet:
			arms[c.a].d = maxf(arms[c.a].d, c.ta)
			arms[c.b].d = maxf(arms[c.b].d, c.tb)
	return corners


## A country junction's plan, or {} when no corner is tight enough for a
## radius (a road running nearly straight on through a node).
static func _country(center: Vector3, arms: Array) -> Dictionary:
	var corners := _corners(arms, true)
	if not corners.any(func(c): return c.fillet):
		return {}
	# A corner too open for a radius (the obtuse side of a skewed or Y
	# junction): the two edges simply meet.
	for c in corners:
		if c.fillet or c.theta <= 0.01 or c.theta >= PI - 0.01:
			continue
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		var hit = Geometry2D.line_intersects_line(a.n * a.hw, a.u, -b.n * b.hw, b.u)
		if hit == null:
			continue
		c.meet = hit
		c.ta = (hit as Vector2).dot(a.u)
		c.tb = (hit as Vector2).dot(b.u)
		# (Past the node along one road is fine: a Y's wide side, where the
		# branch's edge leaves the through road just beyond the node.)
		if absf(c.ta) > a.length * MAX_SHARE or absf(c.tb) > b.length * MAX_SHARE:
			c.erase("meet")
			continue
		a.d = maxf(a.d, c.ta)
		b.d = maxf(b.d, c.tb)
	var through := _through(arms)
	var breaks := {}  # seg -> [[side, metres]]: its edge line and shoulder stop there
	if not through.is_empty():
		for c in corners:
			if not (c.fillet or c.has("meet")):
				continue
			if c.a in through:
				breaks[arms[c.a].seg] = breaks.get(arms[c.a].seg, []) + [[1.0, c.ta]]
			if c.b in through:
				breaks[arms[c.b].seg] = breaks.get(arms[c.b].seg, []) + [[-1.0, c.tb]]
		for i in through:
			arms[i].d = 0.0
	var trims := {}
	for arm in arms:
		trims[arm.seg] = arm.d
	var j := {"center": center, "arms": arms, "corners": corners, "trim": trims, "country": true,
		"through": through, "breaks": breaks}
	var polys := []
	if through.is_empty():
		polys.append(_outline(j))
	else:
		polys = _side_outlines(j)
		if polys.is_empty():
			return {}
	var tris := []
	for i in polys.size():
		polys[i] = _clean(polys[i])
		var poly: PackedVector2Array = polys[i]
		var t := Geometry2D.triangulate_polygon(poly)
		if t.is_empty():
			return {}  # roads crowding each other: the plain disc covers it
		tris.append(t)
	j.polys = polys
	j.country_tris = tris
	j.poly = polys[0]
	j.tris = tris[0]
	return j


## The pair of arms that carry one road on through a country junction:
## the straightest pair, if it is at least as wide as every other road
## there and no other pair is as straight and as wide (a crossroads of
## equal roads has no through road). [] when none.
static func _through(arms: Array) -> Array:
	var pairs := []
	for i in arms.size():
		for k in range(i + 1, arms.size()):
			if (arms[i].u as Vector2).dot(arms[k].u) < THROUGH_DOT:
				pairs.append([i, k])
	if pairs.is_empty() or arms.size() < 3:
		return []
	var width := func(p: Array) -> float: return minf(arms[p[0]].hw, arms[p[1]].hw)
	pairs.sort_custom(func(p, q): return width.call(p) > width.call(q))
	var best: Array = pairs[0]
	var w: float = width.call(best)
	if pairs.size() > 1 and width.call(pairs[1]) > w - 0.01:
		return []
	for i in arms.size():
		if not i in best and arms[i].hw > w + 0.01:
			return []
	# A curbed road (the highway through town) can't run on past a side
	# road: its curb would cross the side road's mouth.
	if not (_shouldered(arms[best[0]]) and _shouldered(arms[best[1]])):
		return []
	return best


## How far into the through road the side outlines reach, under its
## pavement, so no gap shows along its edge.
const INSET := 0.4


## With a through road: one outline on each side that has side roads,
## from the through road's edge round each radius and side road's end and
## back, closed along just inside the through road's edge.
static func _side_outlines(j: Dictionary) -> Array:
	var arms: Array = j.arms
	var through: Array = j.through
	var out := []
	for t in through:
		# Arms round from this through arm until the other one.
		var poly := PackedVector2Array()
		var k: int = t
		var first := true
		for guard in arms.size():
			var c: Dictionary = j.corners[k]
			var a: Dictionary = arms[c.a]
			var b: Dictionary = arms[c.b]
			if first:
				if c.b in through:
					break  # no side road on this side
				if not (c.fillet or c.has("meet")):
					return []
				poly.append(a.u * c.ta + a.n * (a.hw - INSET))
				first = false
			else:
				poly.append(a.u * a.d - a.n * a.hw)
				poly.append(a.u * a.d + a.n * a.hw)
			if c.fillet:
				poly.append_array(_arc(c, a, b, c.r))
			elif c.has("meet"):
				poly.append(c.meet)
			if c.b in through:
				if not (c.fillet or c.has("meet")):
					return []
				poly.append(b.u * c.tb - b.n * (b.hw - INSET))
				break
			k = c.b
		if poly.size() >= 3:
			out.append(poly)
	return out


## An outline without repeated points (the triangulator gives up on them).
static func _clean(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 0.02:
			out.append(q)
	while out.size() > 2 and out[0].distance_to(out[out.size() - 1]) <= 0.02:
		out.remove_at(out.size() - 1)
	return out


## A curb return between arm a's left edge and arm b's right edge: the
## circle of radius R touching both curb lines, shrunk if the roads are too
## short to fit it.
static func _fillet(c: Dictionary, a: Dictionary, b: Dictionary, theta: float, country := false) -> void:
	var r := corner_radius(a.type, b.type, country)
	while true:
		# The centre sits hw + r off both centre lines, inside the corner.
		var p1: Vector2 = a.n * (a.hw + r)
		var p2: Vector2 = -b.n * (b.hw + r)
		var hit = Geometry2D.line_intersects_line(p1, a.u, p2, b.u)
		if hit == null:
			return
		var ctr: Vector2 = hit
		var ta: float = ctr.dot(a.u)
		var tb: float = ctr.dot(b.u)
		if (ta <= a.length * MAX_SHARE and tb <= b.length * MAX_SHARE) or r <= 0.5:
			if ta < 0.0 or tb < 0.0:
				return
			c.fillet = true
			c.r = r
			c.ctr = ctr
			c.ta = minf(ta, a.length * MAX_SHARE)
			c.tb = minf(tb, b.length * MAX_SHARE)
			return
		r *= 0.6


## Points around a corner's curb return at radius `rad` from its centre,
## from arm a's side to arm b's (relative to the node).
static func _arc(c: Dictionary, a: Dictionary, b: Dictionary, rad: float, steps := 10) -> PackedVector2Array:
	var a0: float = (-a.n as Vector2).angle()
	var a1: float = (b.n as Vector2).angle()
	var sweep := wrapf(a1 - a0, -PI, PI)
	var out := PackedVector2Array()
	for k in steps + 1:
		out.append(c.ctr + Vector2.from_angle(a0 + sweep * k / steps) * rad)
	return out


## Draws every shaped junction: pavement into `asphalt`, curbs into `curb`,
## sidewalks and curb ramps into `walk`, warning pads into `domes`.
## A country junction draws into `extra` too: "shoulder" (gravel round its
## radii), "white" and "yellow" (lines that follow a corner round, and side
## roads' centre lines on to their stop lines).
static func draw(plans: Dictionary, asphalt: SurfaceTool, curb: SurfaceTool, walk: SurfaceTool,
		domes: SurfaceTool, extra := {}) -> void:
	for node in plans:
		if plans[node].get("country", false):
			_draw_country(plans[node], asphalt, extra, curb, walk)
		else:
			_draw_node(plans[node], asphalt, curb, walk, domes)


## Country pavement sits just under the roads' own (their edges overlap it).
const Y_COUNTRY := RoadStyle.Y_ASPHALT - 0.01


static func _draw_country(j: Dictionary, asphalt: SurfaceTool, extra: Dictionary, curb: SurfaceTool = null,
		walk: SurfaceTool = null) -> void:
	var arms: Array = j.arms
	var center: Vector3 = j.center
	# Paved if any road there is (the county paves a gravel road's apron
	# where it meets a paved one); gravel where only gravel and dirt meet.
	var paved := arms.any(func(a): return not RoadStyle.unpaved(a.type))
	var pave: SurfaceTool = asphalt if paved or extra.get("gravel road") == null else extra.get("gravel road")
	for i in j.polys.size():
		var poly: PackedVector2Array = j.polys[i]
		var tris: PackedInt32Array = j.country_tris[i]
		for k in range(0, tris.size(), 3):
			_tri(pave, center, [poly[tris[k]], poly[tris[k + 1]], poly[tris[k + 2]]], Y_COUNTRY)
	var gravel: SurfaceTool = extra.get("shoulder")
	var white: SurfaceTool = extra.get("white")
	var yellow: SurfaceTool = extra.get("yellow")
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var corner := arms.size() == 2  # one road turning a corner: its lines follow it round
	var through: Array = j.through
	for c in j.corners:
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		if c.fillet and curb != null and not a.country and not b.country:
			# Two curbed streets (the highway through town and a town street):
			# their curbs and sidewalks wrap the corner, as in town.
			var back := RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
			_ring(curb, center, c, a, b, c.r - RoadStyle.CURB_WIDTH, c.r, RoadStyle.Y_CURB)
			_ring(walk, center, c, a, b, c.r - back - RoadStyle.SIDEWALK_WIDTH, c.r - back, RoadStyle.Y_SIDEWALK)
			_side(curb, walk, center, a, 1.0, c.ta, a.d)
			_side(curb, walk, center, b, -1.0, c.tb, b.d)
		if c.fillet:
			if gravel != null and (_shouldered(a) or _shouldered(b)):
				_shoulder_arc(gravel, center, c, a, b)
			if corner and white != null:
				# The inside edge line, concentric with the radius.
				var e := RoadMesh.edge_line(a.type, true)
				if e < a.hw:
					_line_arc(white, center, c, a, b, c.r + a.hw - e, c.r + a.hw - e + 0.15, y_mark)
			if corner and yellow != null and not RoadMesh.centre_line(a.type, true).is_empty():
				var mid: float = c.r + (a.hw + b.hw) * 0.5
				_line_arc(yellow, center, c, a, b, mid - 0.06, mid + 0.06, y_mark)
		elif not (c.a in through and c.b in through):
			# A straight or outside corner with no radius: the shoulder (and on
			# a corner, the edge line) runs along each road's edge back to the
			# node and round it.
			if gravel != null and (_shouldered(a) or _shouldered(b)):
				_shoulder_band(gravel, center, a, 1.0, a.hw, 0.0, a.d)
				_shoulder_band(gravel, center, b, -1.0, b.hw, 0.0, b.d)
				if c.theta > PI:
					_shoulder_bend(gravel, center, a, b)
			if corner and white != null:
				var e := RoadMesh.edge_line(a.type, true)
				if e < a.hw:
					_band(white, center, a, 1.0, e - 0.15, e, 0.0, a.d, y_mark)
					_band(white, center, b, -1.0, e - 0.15, e, 0.0, b.d, y_mark)
					if c.theta > PI:
						_bend(white, center, a, b, e - 0.15, e, y_mark)
	if yellow == null:
		return
	# Side roads' centre lines carry on to their stop lines.
	for arm in arms:
		if arm.d <= 0.0 or corner:
			continue
		var stop := JunctionMarks.country_near(j, arm) + JunctionMarks.BAR
		if stop >= arm.d:
			continue
		for span in RoadMesh.centre_line(arm.type, arm.country):
			_band(yellow, center, arm, 1.0, span[0], span[1], stop, arm.d, y_mark)


## True for a paved country road, which has gravel shoulders.
static func _shouldered(arm: Dictionary) -> bool:
	return arm.get("country", false) and RoadStyle.TYPES[arm.type].get("surface", "asphalt") == "asphalt" \
		and not RoadStyle.TYPES[arm.type].oneway


## Gravel round a country corner's radius: from the pavement's edge into
## the corner, frayed at its outer edge (UV.x 0 at the pavement, 0.25 out).
static func _shoulder_arc(st: SurfaceTool, center: Vector3, c: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var inner := _arc(c, a, b, maxf(c.r - SHOULDER, 0.0))
	var outer := _arc(c, a, b, c.r)
	var along := 0.0
	for k in inner.size() - 1:
		var step: float = outer[k].distance_to(outer[k + 1])
		_tri_uv(st, center, [[outer[k], Vector2(0, along)], [inner[k], Vector2(1, along)],
			[inner[k + 1], Vector2(1, along + step)]], RoadStyle.Y_SIDEWALK)
		_tri_uv(st, center, [[outer[k], Vector2(0, along)], [inner[k + 1], Vector2(1, along + step)],
			[outer[k + 1], Vector2(0, along + step)]], RoadStyle.Y_SIDEWALK)
		along += step


## Gravel along one side of an arm, out from offset `edge`, `from`..`to`
## metres out from the node.
static func _shoulder_band(st: SurfaceTool, center: Vector3, arm: Dictionary, side: float, edge: float,
		from: float, to: float) -> void:
	if to - from < 0.05:
		return
	var n := maxi(1, ceili((to - from) / 3.0))
	var prev := []
	for k in n + 1:
		var at := lerpf(from, to, float(k) / n)
		var p: Array = LotPlanner.point_at(arm.pts, at)
		var q := Vector2(p[0].x - center.x, p[0].z - center.z)
		var dir := Vector2(p[1].x, p[1].z)
		var nrm := Vector2(-dir.y, dir.x) * side
		var pair := [[q + nrm * edge, Vector2(0, at)], [q + nrm * (edge + SHOULDER), Vector2(1, at)]]
		if not prev.is_empty():
			_tri_uv(st, center, [prev[0], prev[1], pair[1]], RoadStyle.Y_SIDEWALK)
			_tri_uv(st, center, [prev[0], pair[1], pair[0]], RoadStyle.Y_SIDEWALK)
		prev = pair


## Gravel round the outside of a bend, about the node.
static func _shoulder_bend(st: SurfaceTool, center: Vector3, a: Dictionary, b: Dictionary) -> void:
	var a0: float = (a.n as Vector2).angle()
	var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
	for k in 8:
		var d0 := Vector2.from_angle(a0 + sweep * k / 8.0)
		var d1 := Vector2.from_angle(a0 + sweep * (k + 1) / 8.0)
		var r0: float = a.hw
		var r1: float = a.hw + SHOULDER
		_tri_uv(st, center, [[d0 * r0, Vector2(0, k)], [d0 * r1, Vector2(1, k)], [d1 * r1, Vector2(1, k + 1)]],
			RoadStyle.Y_SIDEWALK)
		_tri_uv(st, center, [[d0 * r0, Vector2(0, k)], [d1 * r1, Vector2(1, k + 1)], [d1 * r0, Vector2(0, k + 1)]],
			RoadStyle.Y_SIDEWALK)


## A painted line round a corner's radius, between two radii from its centre.
static func _line_arc(st: SurfaceTool, center: Vector3, c: Dictionary, a: Dictionary, b: Dictionary,
		r0: float, r1: float, y: float) -> void:
	_ring(st, center, c, a, b, r0, r1, y)


## One flat triangle with its own UVs: each corner [point about the node, uv].
static func _tri_uv(st: SurfaceTool, center: Vector3, p: Array, y: float) -> void:
	var o := Vector3(center.x, center.y + y, center.z)
	RoadMesh._tri(st, [o + Vector3(p[0][0].x, 0.0, p[0][0].y), p[0][1]],
		[o + Vector3(p[1][0].x, 0.0, p[1][0].y), p[1][1]],
		[o + Vector3(p[2][0].x, 0.0, p[2][0].y), p[2][1]])


static func _draw_node(j: Dictionary, asphalt: SurfaceTool, curb: SurfaceTool, walk: SurfaceTool,
		domes: SurfaceTool) -> void:
	var arms: Array = j.arms
	var center: Vector3 = j.center
	var poly: PackedVector2Array = j.get("poly", PackedVector2Array())
	var tris: PackedInt32Array = j.get("tris", PackedInt32Array())
	var cw := RoadStyle.CURB_WIDTH
	var back := cw + RoadStyle.PARKWAY_WIDTH  # curb face to sidewalk
	var walk_w := RoadStyle.SIDEWALK_WIDTH
	for k in range(0, tris.size(), 3):
		_tri(asphalt, center, [poly[tris[k]], poly[tris[k + 1]], poly[tris[k + 2]]], RoadStyle.Y_ASPHALT)
	for c in j.corners:
		var a: Dictionary = arms[c.a]
		var b: Dictionary = arms[c.b]
		if c.fillet:
			# Curb and sidewalk wrap the return, then run straight on to where each road starts.
			if RoadMesh.raised_curbs:
				_curb_arc(curb, center, _arc(c, a, b, maxf(c.r, 0.0)), _arc(c, a, b, maxf(c.r - cw, 0.0)))
			else:
				_ring(curb, center, c, a, b, c.r - cw, c.r, RoadStyle.Y_CURB)
			_ring(walk, center, c, a, b, c.r - back - walk_w, c.r - back, RoadStyle.Y_SIDEWALK)
			_side(curb, walk, center, a, 1.0, c.ta, a.d)
			_side(curb, walk, center, b, -1.0, c.tb, b.d)
			_ramp(walk, domes, center, a, 1.0)
			_ramp(walk, domes, center, b, -1.0)
		else:
			_side(curb, walk, center, a, 1.0, 0.0, a.d)
			_side(curb, walk, center, b, -1.0, 0.0, b.d)
			if c.theta > PI and RoadMesh.raised_curbs:
				_curb_arc(curb, center, _bend_line(a, b, a.hw), _bend_line(a, b, a.hw + cw))
			elif c.theta > PI:
				_bend(curb, center, a, b, a.hw, a.hw + cw, RoadStyle.Y_CURB)
				_bend(walk, center, a, b, a.hw + back, a.hw + back + walk_w, RoadStyle.Y_SIDEWALK)


## A band of the curb return between two radii from its centre.
static func _ring(st: SurfaceTool, center: Vector3, c: Dictionary, a: Dictionary, b: Dictionary,
		r0: float, r1: float, y: float) -> void:
	var inner := _arc(c, a, b, maxf(r0, 0.0))
	var outer := _arc(c, a, b, maxf(r1, 0.0))
	for k in inner.size() - 1:
		_tri(st, center, [inner[k], outer[k], outer[k + 1]], y)
		_tri(st, center, [inner[k], outer[k + 1], inner[k + 1]], y)


## The outside of a bend: a band about the node from arm a's left to b's right.
static func _bend(st: SurfaceTool, center: Vector3, a: Dictionary, b: Dictionary, r0: float, r1: float, y: float) -> void:
	var a0: float = (a.n as Vector2).angle()
	var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
	for k in 8:
		var d0 := Vector2.from_angle(a0 + sweep * k / 8.0)
		var d1 := Vector2.from_angle(a0 + sweep * (k + 1) / 8.0)
		_tri(st, center, [d0 * r0, d0 * r1, d1 * r1], y)
		_tri(st, center, [d0 * r0, d1 * r1, d1 * r0], y)


## Straight curb and sidewalk along one side of an arm, from `from` to `to`
## metres out from the node (side +1 = toward the next arm round).
static func _side(curb: SurfaceTool, walk: SurfaceTool, center: Vector3, arm: Dictionary, side: float,
		from: float, to: float) -> void:
	if to - from < 0.05:
		return
	var hw: float = arm.hw
	var back := hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	if RoadMesh.raised_curbs:
		_curb_side(curb, center, arm, side, from, to)
	else:
		_band(curb, center, arm, side, hw, hw + RoadStyle.CURB_WIDTH, from, to, RoadStyle.Y_CURB)
	_band(walk, center, arm, side, back, back + RoadStyle.SIDEWALK_WIDTH, from, to, RoadStyle.Y_SIDEWALK)


## A raised curb (RoadMesh.add_curb) along lines of points about the node:
## the street's edge and the curb's back.
static func _curb_arc(st: SurfaceTool, center: Vector3, edge: PackedVector2Array, back: PackedVector2Array) -> void:
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for k in mini(edge.size(), back.size()):
		inner.append(center + Vector3(edge[k].x, 0.0, edge[k].y))
		outer.append(center + Vector3(back[k].x, 0.0, back[k].y))
	RoadMesh.add_curb(st, inner, outer)


## The outside of a bend at radius `r`: a line about the node from arm a's
## left to b's right (as _bend).
static func _bend_line(a: Dictionary, b: Dictionary, r: float) -> PackedVector2Array:
	var a0: float = (a.n as Vector2).angle()
	var sweep := fposmod((-b.n as Vector2).angle() - a0, TAU)
	var out := PackedVector2Array()
	for k in 9:
		out.append(Vector2.from_angle(a0 + sweep * k / 8.0) * r)
	return out


## A raised curb along one side of an arm, `from`..`to` metres out (as _band).
static func _curb_side(st: SurfaceTool, center: Vector3, arm: Dictionary, side: float, from: float, to: float) -> void:
	var hw: float = arm.hw
	var edge := PackedVector2Array()
	var back := PackedVector2Array()
	var n := maxi(1, ceili((to - from) / 3.0))
	for k in n + 1:
		var p: Array = LotPlanner.point_at(arm.pts, lerpf(from, to, float(k) / n))
		var q := Vector2(p[0].x - center.x, p[0].z - center.z)
		var nrm := Vector2(-p[1].z, p[1].x) * side
		edge.append(q + nrm * hw)
		back.append(q + nrm * (hw + RoadStyle.CURB_WIDTH))
	_curb_arc(st, center, edge, back)


## A curb ramp where people cross the arm: concrete across the grass strip
## from the sidewalk to the curb, with the warning pad at the street edge.
static func _ramp(walk: SurfaceTool, domes: SurfaceTool, center: Vector3, arm: Dictionary, side: float) -> void:
	var hw: float = arm.hw
	var from: float = arm.d + RAMP_GAP
	var to := from + RAMP_WIDTH
	if to > arm.length * 0.5:
		return
	var cw := RoadStyle.CURB_WIDTH
	_band(walk, center, arm, side, hw, hw + cw + RoadStyle.PARKWAY_WIDTH, from, to, RoadStyle.Y_SIDEWALK + 0.035)
	_band(domes, center, arm, side, hw, hw + DOMES_DEPTH, from, to, RoadStyle.Y_CURB + 0.01)


## A band beside an arm, offsets `o0`..`o1` from its centre line on `side`,
## `from`..`to` metres out. Follows the arm's own (maybe curved) line.
static func _band(st: SurfaceTool, center: Vector3, arm: Dictionary, side: float, o0: float, o1: float,
		from: float, to: float, y: float) -> void:
	var n := maxi(1, ceili((to - from) / 3.0))
	var prev := []
	for k in n + 1:
		var at := lerpf(from, to, float(k) / n)
		var p: Array = LotPlanner.point_at(arm.pts, at)
		var q := Vector2(p[0].x - center.x, p[0].z - center.z)
		var dir := Vector2(p[1].x, p[1].z)
		var nrm := Vector2(-dir.y, dir.x) * side
		var pair := [q + nrm * o0, q + nrm * o1]
		if not prev.is_empty():
			_tri(st, center, [prev[0], prev[1], pair[1]], y)
			_tri(st, center, [prev[0], pair[1], pair[0]], y)
		prev = pair


## One flat triangle, from points about the node.
static func _tri(st: SurfaceTool, center: Vector3, p: Array, y: float) -> void:
	var o := Vector3(center.x, center.y + y, center.z)
	RoadMesh._tri(st, [o + Vector3(p[0].x, 0.0, p[0].y), Vector2(p[0].x, p[0].y)],
		[o + Vector3(p[1].x, 0.0, p[1].y), Vector2(p[1].x, p[1].y)],
		[o + Vector3(p[2].x, 0.0, p[2].y), Vector2(p[2].x, p[2].y)])
