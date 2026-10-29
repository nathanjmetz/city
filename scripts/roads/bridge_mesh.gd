class_name BridgeMesh
extends RefCounted
## Road bridges built the way INDOT builds them (INDOT Bridge Design Manual,
## Standard Drawings), picked by how long the crossing is:
##   - under 25 m (80 ft): one span of precast concrete box beams or a slab,
##     a thin deck edge and no piers;
##   - up to about 60 m: prestressed concrete I-beams in spans of 30 m or
##     less, on multi-column bents (a cap beam on round columns);
##   - longer: deeper bulb-tee or steel girders in spans up to about 45 m.
## Every bridge gets a 32 in concrete barrier rail along each edge (INDOT's
## FT bridge railing, MASH TL-4) and an abutment wall at each end. On
## desktop detail (High and up) the girders show under the deck, the
## columns are round, and W-beam guardrail runs 25 m (about 80 ft) along
## each approach to a MASH end terminal with its yellow-and-black marker.
##
## `parts` holds SurfaceTools: "concrete" always, and "steel" and "marker"
## for the fine parts.

const RAIL_H := 0.81  # 32 in barrier
const RAIL_TOP := 0.25
const RAIL_BASE := 0.45
const SLAB := 0.25  # cast deck over girders
const CLEAR := 1.5  # a road this far over the ground is on a bridge
const GUARD_RUN := 25.0  # approach guardrail length, metres
const GUARD_H := 0.79  # 31 in to the top of the W-beam (MASH)
const POST_SPACING := 1.905  # 6 ft 3 in


## Draws every bridge along a road's points (lifted to their drawn height).
## Returns true if any part of the road was on a bridge.
static func build(pts: PackedVector3Array, half: float, parts: Dictionary, ground: Callable, fine: bool) -> bool:
	var runs := _runs(pts, ground)
	for r in runs:
		_bridge(pts, r[0], r[1], half, parts, ground, fine)
		if fine and parts.has("steel"):
			for end: int in [0, 1]:
				_guardrail(pts, r[end], -1 if end == 0 else 1, half, parts)
	return not runs.is_empty()


## [first, last] point index of each stretch at least CLEAR over the ground.
static func _runs(pts: PackedVector3Array, ground: Callable) -> Array:
	var out := []
	var start := -1
	for i in pts.size():
		var up := pts[i].y - float(ground.call(pts[i].x, pts[i].z))
		if up >= CLEAR and start == -1:
			start = i
		elif up < CLEAR and start != -1:
			if i - 1 > start:
				out.append([start, i - 1])
			start = -1
	if start != -1 and pts.size() - 1 > start:
		out.append([start, pts.size() - 1])
	return out


## Span length most bridges of this length use, and how deep the
## superstructure is under the deck (girders about span / 20).
static func spans_for(length: float) -> Array:
	if length < 25.0:
		return [length, 0.9]  # box beams: one span
	var most := 30.0 if length <= 60.0 else 45.0
	var n := ceili(length / most)
	var span := length / n
	return [span, clampf(span / 20.0, 1.1, 2.3) + SLAB]


static func _bridge(pts: PackedVector3Array, i0: int, i1: int, half: float, parts: Dictionary,
		ground: Callable, fine: bool) -> void:
	var c: SurfaceTool = parts.concrete
	var cum := [0.0]
	for i in range(i0 + 1, i1 + 1):
		cum.append(cum[-1] + _flat(pts[i] - pts[i - 1]))
	var length: float = cum[-1]
	var sd := spans_for(length)
	var depth: float = sd[1]
	var edge := minf(depth, 0.9) if not fine else SLAB + 0.3  # the fascia you see
	for i in range(i0, i1):
		var a := pts[i]
		var b := pts[i + 1]
		var sa := _side(pts, i) * half
		var sb := _side(pts, i + 1) * half
		# Deck slab: its edges and underside.
		for s: float in [-1.0, 1.0]:
			_quad(c, a + sa * s, b + sb * s, b + sb * s - Vector3(0, edge, 0), a + sa * s - Vector3(0, edge, 0))
		_quad(c, a - sa - Vector3(0, edge, 0), b - sb - Vector3(0, edge, 0), b + sb - Vector3(0, edge, 0),
			a + sa - Vector3(0, edge, 0))
		# Barrier rail on each edge: a sloped-face concrete wall.
		for s: float in [-1.0, 1.0]:
			var oa := a + sa * s
			var ob := b + sb * s
			var ina := -sa.normalized() * s
			var inb := -sb.normalized() * s
			_quad(c, oa, ob, ob + Vector3(0, RAIL_H, 0), oa + Vector3(0, RAIL_H, 0))
			_quad(c, oa + Vector3(0, RAIL_H, 0), ob + Vector3(0, RAIL_H, 0),
				ob + inb * RAIL_TOP + Vector3(0, RAIL_H, 0), oa + ina * RAIL_TOP + Vector3(0, RAIL_H, 0))
			_quad(c, oa + ina * RAIL_TOP + Vector3(0, RAIL_H, 0), ob + inb * RAIL_TOP + Vector3(0, RAIL_H, 0),
				ob + inb * RAIL_BASE, oa + ina * RAIL_BASE)
		if fine and depth > edge + 0.05 and parts.has("steel"):
			# Girders under the deck, about 2.4 m (8 ft) apart.
			var n := maxi(2, roundi(half * 2.0 / 2.4))
			for k in n:
				var f := lerpf(-1.0, 1.0, (k + 0.5) / n) * 0.92
				var ga := a + sa * f - Vector3(0, SLAB, 0)
				var gb := b + sb * f - Vector3(0, SLAB, 0)
				_beam(c, ga, gb, 0.3, depth - SLAB)
	# Piers between spans: a cap beam on columns down to the ground.
	var span: float = sd[0]
	var k := 1
	while span * k < length - 1.0:
		var at := span * k
		var j := 0
		while j < cum.size() - 2 and cum[j + 1] < at:
			j += 1
		var f: float = (at - cum[j]) / maxf(cum[j + 1] - cum[j], 0.001)
		var p := pts[i0 + j].lerp(pts[i0 + j + 1], f)
		var side := _side(pts, i0 + j)
		_pier(c, p - Vector3(0, depth, 0), side, half, float(ground.call(p.x, p.z)) - 1.0, fine)
		k += 1
	# Abutments: a wall under each end of the deck down into the bank.
	for end: int in [i0, i1]:
		var p := pts[end]
		var side := _side(pts, end)
		var along := _along(pts, end) * (-1.0 if end == i0 else 1.0)
		var foot := float(ground.call(p.x, p.z)) - 1.5
		var top := p.y - edge
		if top - foot > 0.3:
			_box(c, Vector3(p.x, (top + foot) * 0.5, p.z) + along * 0.6, side * (half + 0.6) * 2.0, along * 1.2,
				top - foot)
			# Wingwalls back into the fill at each corner.
			for s: float in [-1.0, 1.0]:
				var w0 := p + side * (half + 0.3) * s
				_box(c, Vector3(w0.x, (top + foot) * 0.5, w0.z) + along * 2.5, side * 0.45, along * 4.0, top - foot)


## A multi-column bent: a cap beam across the deck on round (or, at
## distance, square) columns about 6 m apart.
static func _pier(c: SurfaceTool, top: Vector3, side: Vector3, half: float, foot: float, fine: bool) -> void:
	var along := Vector3(-side.z, 0.0, side.x)
	var cap_h := 1.1
	_box(c, top - Vector3(0, cap_h * 0.5, 0), side * (half * 2.0 - 0.6), along * 1.2, cap_h)
	var n := maxi(2, roundi(half * 2.0 / 6.0) + 1)
	var col_top := top.y - cap_h
	if col_top - foot < 0.3:
		return
	for k in n:
		var p := top + side * lerpf(-half + 1.5, half - 1.5, float(k) / (n - 1))
		var mid := Vector3(p.x, (col_top + foot) * 0.5, p.z)
		if fine:
			_column(c, mid, 0.45, col_top - foot)
		else:
			_box(c, mid, side * 0.9, along * 0.9, col_top - foot)


## W-beam guardrail on steel posts from a bridge end back along the
## approach, both sides, ending in a MASH end terminal (an impact head with
## a yellow-and-black object marker, MUTCD OM-3).
static func _guardrail(pts: PackedVector3Array, end: int, dir: int, half: float, parts: Dictionary) -> void:
	var steel: SurfaceTool = parts.steel
	var line := PackedVector3Array([pts[end]])
	var i := end
	var got := 0.0
	while got < GUARD_RUN:
		i -= dir
		if i < 0 or i >= pts.size():
			break
		var seg := _flat(pts[i] - line[-1])
		if got + seg > GUARD_RUN:
			line.append(line[-1].lerp(pts[i], (GUARD_RUN - got) / seg))
			got = GUARD_RUN
		else:
			line.append(pts[i])
			got += seg
	if line.size() < 2 or got < 4.0:
		return
	for s: float in [-1.0, 1.0]:
		var rail := PackedVector3Array()
		for q in line.size():
			var k := clampi(end - dir * q, 0, pts.size() - 1)
			rail.append(line[q] + _side(pts, k) * (half - 0.35) * s)
		var walked := 0.0
		var next_post := 0.0
		for q in rail.size() - 1:
			var a := rail[q]
			var b := rail[q + 1]
			# The rail: a 12 in deep W-beam face 0.55-0.79 m up.
			_quad(steel, a + Vector3(0, GUARD_H - 0.31, 0), b + Vector3(0, GUARD_H - 0.31, 0),
				b + Vector3(0, GUARD_H, 0), a + Vector3(0, GUARD_H, 0))
			var seg := _flat(b - a)
			var run := Vector3(b.x - a.x, 0.0, b.z - a.z) / maxf(seg, 0.001)
			while next_post <= walked + seg:
				# W6x9 steel posts behind the rail on blockouts.
				var p := a.lerp(b, (next_post - walked) / maxf(seg, 0.001))
				var out := Vector3(a.x - line[q].x, 0.0, a.z - line[q].z).normalized()
				_box(steel, p + out * 0.2 + Vector3(0, GUARD_H * 0.5 - 0.1, 0), out * 0.15, run * 0.1, GUARD_H + 0.2)
				next_post += POST_SPACING
			walked += seg
		# The end terminal's impact head with its marker facing traffic.
		if parts.has("marker"):
			var tail := rail[rail.size() - 1]
			var back := (rail[rail.size() - 1] - rail[rail.size() - 2])
			back.y = 0.0
			back = back.normalized()
			var across := Vector3(-back.z, 0.0, back.x)
			_box(parts.marker, tail + back * 0.25 + Vector3(0, GUARD_H - 0.25, 0), across * 0.6, back * 0.5, 0.6)


static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len := dir.length()
	if len < 0.01:
		return
	var across := Vector3(-dir.z, 0.0, dir.x) / len
	var mid := (a + b) * 0.5 - Vector3(0, h * 0.5, 0)
	_box(st, mid, across * w, dir, h)


## A box centred on `c`, its sides along the vectors `u` and `v` (full
## widths) and `h` tall, with outward faces.
static func _box(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, h: float) -> void:
	var hu := u * 0.5
	var hv := v * 0.5
	var y := Vector3(0, h * 0.5, 0)
	var p := [c - hu - hv - y, c + hu - hv - y, c + hu + hv - y, c - hu + hv - y]
	var q := [c - hu - hv + y, c + hu - hv + y, c + hu + hv + y, c - hu + hv + y]
	for k in 4:
		_quad(st, p[k], p[(k + 1) % 4], q[(k + 1) % 4], q[k])
	_quad(st, q[0], q[1], q[2], q[3])
	_quad(st, p[3], p[2], p[1], p[0])


## A round column, 12 sides.
static func _column(st: SurfaceTool, c: Vector3, r: float, h: float) -> void:
	var y := Vector3(0, h * 0.5, 0)
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		var d0 := Vector3(cos(a0), 0.0, sin(a0)) * r
		var d1 := Vector3(cos(a1), 0.0, sin(a1)) * r
		_quad(st, c + d0 - y, c + d1 - y, c + d1 + y, c + d0 + y)


## A four-cornered face drawn both ways round (bridges are seen from every
## side), with its normal.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a)
	if n.length() < 0.000001:
		n = (c - b).cross(a - b)
	n = n.normalized()
	for face in [[a, b, c, a, c, d], [a, c, b, a, d, c]]:
		var nn: Vector3 = n if face[1] == b else -n
		for v in face:
			st.set_normal(nn)
			st.set_uv(Vector2(v.x + v.z, v.y) * 0.25)
			st.add_vertex(v)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _side(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-dir.z, 0.0, dir.x)


static func _along(pts: PackedVector3Array, i: int) -> Vector3:
	var s := _side(pts, i)
	return Vector3(s.z, 0.0, -s.x)
