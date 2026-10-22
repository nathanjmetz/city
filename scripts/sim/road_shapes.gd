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
const ROUNDABOUT_MIN := 14.0
const ROUNDABOUT_MAX := 45.0
## FHWA: two-lane roundabouts need at least a 150 ft inscribed circle.
const ROUNDABOUT_MIN_2LANE := 23.0


## The ring radius actually used for a roundabout of this road type.
static func roundabout_radius(radius: float, type: int) -> float:
	var lo := ROUNDABOUT_MIN if RoadStyle.ring_type(type) == RoadStyle.Type.RING else ROUNDABOUT_MIN_2LANE
	return clampf(radius, lo, ROUNDABOUT_MAX)


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
