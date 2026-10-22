class_name Reserves
extends RefCounted
## Land the player is saving for an industry to grow into: outlined with
## nodes and marked for farming, oil, ore or forestry. Roads and zoning stay
## off it, and other industries leave it alone. It's only an intention: the
## farms and companies themselves decide what to use, by what the land holds.

const KINDS := {"farm": "farming", "oil": "oil", "ore": "ore", "forest": "forestry"}
const COLORS := {
	"farm": Color(0.55, 0.8, 0.3), "oil": Color(0.35, 0.3, 0.5),
	"ore": Color(0.8, 0.45, 0.25), "forest": Color(0.2, 0.55, 0.3),
}

## Outlines in the order drawn: {points: PackedVector2Array, kind}. A later
## outline wins where they overlap; kind "" clears.
var outlines: Array = []


## Adds an outline (kind "" takes land back out). False if it's no outline.
func paint(points: Array, kind: String) -> bool:
	if points.size() < 3 or (kind != "" and not KINDS.has(kind)):
		return false
	var poly := PackedVector2Array()
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		poly.append(Vector2(p.x, p.z))
		box = box.expand(Vector2(p.x, p.z))
	if box.size.x * box.size.y > 16_000_000.0 or absf(_area_of(poly)) < 100.0:  # 4 km square at most
		return false
	if kind == "" and outlines.is_empty():
		return false
	outlines.append({"points": poly, "kind": kind})
	return true


## What a point is reserved for, or "".
func kind_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	var kind := ""
	for o in outlines:
		if Geometry2D.is_point_in_polygon(q, o.points):
			kind = o.kind
	return kind


## True when any part of the polyline crosses reserved land.
func crosses(pts: PackedVector3Array) -> String:
	if outlines.is_empty():
		return ""
	var length := RoadNetwork.polyline_length(pts)
	var n := maxi(2, int(length / 6.0))
	for k in n + 1:
		var kind := kind_at(LotPlanner.point_at(pts, length * k / n)[0])
		if kind != "":
			return kind
	return ""


static func _area_of(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


func to_dict() -> Array:
	var out := []
	for o in outlines:
		var pts := []
		for p in o.points:
			pts.append([p.x, p.y])
		out.append({"points": pts, "kind": o.kind})
	return out


func from_list(list: Array) -> void:
	outlines.clear()
	for o in list:
		var poly := PackedVector2Array()
		for p in o.points:
			poly.append(Vector2(float(p[0]), float(p[1])))
		outlines.append({"points": poly, "kind": str(o.kind)})
