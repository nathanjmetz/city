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
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var am := (a0 + a1) * 0.5
		out.append([
			center + Vector3(cos(a0), 0.0, sin(a0)) * radius,
			center + Vector3(cos(am), 0.0, sin(am)) * ctrl_r,
			center + Vector3(cos(a1), 0.0, sin(a1)) * radius,
		])
	return out


static func _line(s: Vector3, e: Vector3) -> Array:
	return [s, s.lerp(e, 0.5), e]
