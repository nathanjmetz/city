class_name LandPlan
extends RefCounted
## The town's future land use map (Brawn, 2026-10-23: guide the system
## instead of answering every card). The player outlines big, soft areas:
## homes here, shops along this road, jobs by the rail, keep these farms.
## It's a plan, not zoning: nothing is blocked. Builders look inside it
## first, and a proposal that matches it moves faster; a builder never
## proposes homes on land planned for something else.
##
## Real: every Indiana town's comprehensive plan has a future land use map
## (IC 36-7-4-500 to 512). Plan commissions weigh proposals against it, and
## a rezoning that matches the plan is routine and quick while one against
## it is slow and often denied.
##
## Outlines are kept the way Reserves keeps them; it's read once a month by
## the builders, so no per-frame work.

const KINDS := {"homes": "homes", "shops": "shops", "jobs": "jobs", "farms": "farming"}
const COLORS := {
	"homes": Color("#7cc36b"), "shops": Color("#5aa8e0"),
	"jobs": Color("#e3b341"), "farms": Color("#c8b27a"),
}

## Outlines in the order drawn: {points: PackedVector2Array, kind}. A later
## outline wins where they overlap; kind "" clears.
var outlines: Array = []


## Adds an outline (kind "" takes land back out of the plan). False if it's
## no outline.
func paint(points: Array, kind: String) -> bool:
	if points.size() < 3 or (kind != "" and not KINDS.has(kind)):
		return false
	var poly := PackedVector2Array()
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		poly.append(Vector2(p.x, p.z))
		box = box.expand(Vector2(p.x, p.z))
	if box.size.x * box.size.y > 64_000_000.0 or absf(Reserves._area_of(poly)) < 100.0:  # 8 km square at most
		return false
	if kind == "" and outlines.is_empty():
		return false
	# Cut the new area out of the older ones, so the map stays a handful of
	# pieces and draws as it reads. Where the new area makes a hole in one,
	# that one is kept whole (a later outline wins where they overlap).
	var hole := false
	var kept := []
	for o in outlines:
		var cut := Geometry2D.clip_polygons(o.points, poly)
		var turns := {}
		for c in cut:
			turns[Geometry2D.is_polygon_clockwise(c)] = true
		if turns.size() > 1:
			hole = true
			kept.append(o)
			continue
		for c in cut:
			if absf(Reserves._area_of(c)) >= 100.0:
				kept.append({"points": c, "kind": o.kind})
	if kind == "" and not hole and kept.size() == outlines.size() and _same(kept, outlines):
		return false
	outlines = kept
	if kind != "" or hole:
		outlines.append({"points": poly, "kind": kind})
	return true


static func _same(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i].points != b[i].points:
			return false
	return true


## What the plan says for a point, or "" (no plan there).
func kind_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	var kind := ""
	for o in outlines:
		if Geometry2D.is_point_in_polygon(q, o.points):
			kind = o.kind
	return kind


func to_dict() -> Array:
	var out := []
	for o in outlines:
		var pts := []
		for p in o.points:
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		out.append({"points": pts, "kind": o.kind})
	return out


func from_list(list: Array) -> void:
	outlines.clear()
	for o in list:
		var poly := PackedVector2Array()
		for p in o.points:
			poly.append(Vector2(float(p[0]), float(p[1])))
		outlines.append({"points": poly, "kind": str(o.kind)})
