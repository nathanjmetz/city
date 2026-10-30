class_name RoadShapes
extends RefCounted
## Whole road layouts placed in one go, like the Cities: Skylines 2 grid and
## roundabout tools. Each returns curves as [start, control, end] so the
## preview and the simulation build exactly the same thing.

## Room for two 32 m lots back to back between parallel streets
## (2 x (8.1 m half street + 0.3 m + 32 m lot), plus a little slack).
const GRID_ACROSS := 82.0
const GRID_BLOCK_MIN := 60.0
const GRID_BLOCK_MAX := 240.0
## Smallest ring centre-line radius, metres (a 72 ft mini roundabout).
const ROUNDABOUT_MIN := 8.0
## FHWA: two-lane roundabouts need at least a 150 ft inscribed circle.
const ROUNDABOUT_MIN_ICD_2LANE := 150.0 / 3.28084
## Largest inscribed circles [ ] can reach: 180 ft for one lane (NCHRP 672),
## 250 ft for two (the old FHWA 2000 guide's rural double-lane top end).
const ROUNDABOUT_MAX_ICD_1LANE := 180.0 / 3.28084
const ROUNDABOUT_MAX_ICD_2LANE := 250.0 / 3.28084
## At or under this inscribed diameter (90 ft) it is a mini roundabout: the
## whole central island is a low domed apron that trucks drive over.
const MINI_ICD := 90.0 / 3.28084
## Sizes the player picks from, by inscribed circle diameter (curb to curb
## across the outside of the ring) and lane count. FHWA Roundabouts: An
## Informational Guide (NCHRP Report 672, Exhibit 6-9): mini 45-90 ft,
## single-lane 90-180 ft, two-lane 150-220 ft.
const ROUNDABOUT_SIZES := [
	{"name": "Mini", "icd": 80.0, "lanes": 1,
		"about": "Mini roundabout, 80 ft: a drive-over island for tight town corners (FHWA 45-90 ft)"},
	{"name": "Compact", "icd": 110.0, "lanes": 1,
		"about": "Compact single-lane, 110 ft: neighborhood and downtown streets (FHWA 90-180 ft)"},
	{"name": "Single lane", "icd": 150.0, "lanes": 1,
		"about": "Single-lane, 150 ft: collectors and country roads, room for semis (FHWA 90-180 ft)"},
	{"name": "Two lane", "icd": 180.0, "lanes": 2,
		"about": "Two-lane, 180 ft: busy avenues meeting (FHWA 150-220 ft)"},
	{"name": "Two lane, large", "icd": 220.0, "lanes": 2,
		"about": "Two-lane, 220 ft: boulevards and highways at speed (FHWA 150-220 ft)"},
]


## The ring type of a roundabout with this many lanes.
static func ring_for_lanes(lanes: int) -> int:
	return RoadStyle.Type.RING2 if lanes >= 2 else RoadStyle.Type.RING


## The ring centre-line radius for an inscribed diameter, in metres.
static func radius_for_icd(icd_m: float, ring: int) -> float:
	return icd_m * 0.5 - RoadStyle.half_width(ring)


## The inscribed diameter of a ring, metres.
static func icd_of(radius: float, ring: int) -> float:
	return (radius + RoadStyle.half_width(ring)) * 2.0


## The ring radius actually used for a roundabout of this ring type.
static func roundabout_radius(radius: float, ring: int) -> float:
	if ring == RoadStyle.Type.RING2:
		return clampf(radius, radius_for_icd(ROUNDABOUT_MIN_ICD_2LANE, ring), radius_for_icd(ROUNDABOUT_MAX_ICD_2LANE, ring))
	return clampf(radius, ROUNDABOUT_MIN, radius_for_icd(ROUNDABOUT_MAX_ICD_1LANE, ring))


## True for a mini roundabout (a drive-over centre).
static func is_mini(radius: float, ring: int) -> bool:
	return icd_of(radius, ring) <= MINI_ICD + 0.5


## A grid of streets. a to b sets the direction and length of the first
## street; c sets how far back the grid reaches. Streets along a-b are
## GRID_ACROSS apart, cross streets are `block` apart. Sizes snap to whole
## blocks, so the far corner may not sit exactly under the mouse.
static func grid(a: Vector3, b: Vector3, c: Vector3, block: float) -> Array:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := along.length()
	if length < RoadNetwork.MIN_LENGTH:
		return []
	var u := along / length
	var v := Vector3(-u.z, 0.0, u.x)
	var reach := (c - a).dot(v)
	if reach < 0.0:
		v = -v
		reach = -reach
	var cols := maxi(1, roundi(length / block))
	var rows := roundi(reach / GRID_ACROSS)
	var step_u := length / cols
	var out := []
	for r in rows + 1:
		var s := a + v * (r * GRID_ACROSS)
		out.append(_line(s, s + u * length))
	if rows > 0:
		for col in cols + 1:
			var s := a + u * (col * step_u)
			out.append(_line(s, s + v * (rows * GRID_ACROSS)))
	return out


## A ring of eight arcs. Quadratic curves over 45 degrees stay within a few
## centimetres of a true circle.
static func roundabout(center: Vector3, radius: float) -> Array:
	var out := []
	var n := 8
	var ctrl_r := radius / cos(PI / n)
	# Arcs run with falling angle: counter-clockwise seen from above, so
	# traffic keeps the island on its left as in the US.
	for i in n:
		var a0 := -TAU * i / n
		var a1 := -TAU * (i + 1) / n
		var am := (a0 + a1) * 0.5
		out.append([
			center + Vector3(cos(a0), 0.0, sin(a0)) * radius,
			center + Vector3(cos(am), 0.0, sin(am)) * ctrl_r,
			center + Vector3(cos(a1), 0.0, sin(a1)) * radius,
		])
	return out


## The same road shifted sideways by `gap` (to the right of its direction).
static func offset(curve: Array, gap: float) -> Array:
	var p0: Vector3 = curve[0]
	var p1: Vector3 = curve[1]
	var p2: Vector3 = curve[2]
	var t0 := _flat_dir(p1 - p0, p2 - p0)
	var t1 := _flat_dir(p2 - p1, p2 - p0)
	var a := p0 + _right(t0) * gap
	var b := p2 + _right(t1) * gap
	# The new bend point is where the shifted end tangents meet.
	var mid := a.lerp(b, 0.5)
	var hit = Geometry2D.line_intersects_line(Vector2(a.x, a.z), Vector2(t0.x, t0.z),
		Vector2(b.x, b.z), Vector2(t1.x, t1.z))
	if hit == null or Vector2(mid.x, mid.z).distance_to(hit) > a.distance_to(b) * 2.0:
		return [a, mid, b]
	return [a, Vector3(hit.x, 0.0, hit.y), b]


## An S-curve from a start, two bend points and an end (CS2's complex
## curve), as two roads [start, control, end] that meet in the middle with
## no kink. Roads are quadratic curves, so the cubic through the four points
## is split at its middle and each half gets the control point where its
## end directions cross, which keeps the direction smooth at all three ends.
static func s_curve(p0: Vector3, c1: Vector3, c2: Vector3, p3: Vector3) -> Array:
	var m := p0 * 0.125 + c1 * 0.375 + c2 * 0.375 + p3 * 0.125
	var tm := _flat_dir(p3 + c2 - c1 - p0, p3 - p0)
	var d0 := _flat_dir(c1 - p0, p3 - p0)
	var d3 := _flat_dir(p3 - c2, p3 - p0)
	var y := lerpf(p0.y, p3.y, 0.5)
	m.y = y
	var left = _meet(p0, d0, m, tm)
	var right = _meet(m, tm, p3, d3)
	# Where a half's directions run parallel (nearly straight) or double
	# back, that half goes straight.
	if left == null:
		left = p0.lerp(m, 0.5)
	if right == null:
		right = m.lerp(p3, 0.5)
	left.y = lerpf(p0.y, y, 0.5)
	right.y = lerpf(y, p3.y, 0.5)
	return [[p0, left, m], [m, right, p3]]


## Where a line from `a` heading `da` meets one through `b` heading `db`,
## ahead of `a` and behind `b`, or null.
static func _meet(a: Vector3, da: Vector3, b: Vector3, db: Vector3):
	var hit = Geometry2D.line_intersects_line(Vector2(a.x, a.z), Vector2(da.x, da.z), Vector2(b.x, b.z), Vector2(db.x, db.z))
	if hit == null:
		return null
	var p := Vector3(hit.x, 0.0, hit.y)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	if (p - a).dot(da) < 0.0 or (b - p).dot(db) < 0.0 or Vector2(p.x - a.x, p.z - a.z).length() > span * 2.0:
		return null
	return p


static func _flat_dir(d: Vector3, fallback: Vector3) -> Vector3:
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(fallback.x, 0.0, fallback.z)
	return d.normalized()


static func _right(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0.0, d.x)


static func _line(s: Vector3, e: Vector3) -> Array:
	return [s, s.lerp(e, 0.5), e]


## Centre and radius of the circle a curve follows, or [] if it is straight.
static func arc_circle(c: Array) -> Array:
	var p0 := Vector3(c[0].x, 0.0, c[0].z)
	var t := Vector3(c[1].x - c[0].x, 0.0, c[1].z - c[0].z).normalized()
	var chord := Vector3(c[2].x, 0.0, c[2].z) - p0
	var side := chord - t * chord.dot(t)
	var theta := t.angle_to(chord)
	if theta < 0.01 or side.length() < 0.001:
		return []
	var r := chord.length() * 0.5 / sin(theta)
	return [p0 + side.normalized() * r, r]
