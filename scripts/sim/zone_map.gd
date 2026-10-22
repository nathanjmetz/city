class_name ZoneMap
extends RefCounted
## Where the player has painted zones, stored as a sparse 4 m paint layer.
## The land itself has no grid: lots come from the roads, and each lot takes
## the zone painted under its middle.

enum Zone { NONE, RESIDENTIAL, COMMERCIAL, INDUSTRIAL }

const CELL := 4.0

const NAMES := ["None", "Residential", "Commercial", "Industrial"]
## Cities: Skylines colours: green homes, blue shops, yellow industry.
const COLORS := [
	Color(1, 1, 1), Color(0.35, 0.85, 0.35), Color(0.30, 0.60, 1.0), Color(1.0, 0.80, 0.20),
]

var cells := {}  # Vector2i -> Zone
## Areas whose zoning changed since lots were last planned (Rect2 in x/z).
var dirty: Array = []


func zone_at(pos: Vector3) -> int:
	return cells.get(_cell(pos), Zone.NONE)


## Paints every cell whose middle is inside the circle. Zone.NONE erases.
func paint(center: Vector3, radius: float, zone: int) -> void:
	dirty.append(Rect2(center.x - radius - CELL, center.z - radius - CELL, radius * 2 + CELL * 2, radius * 2 + CELL * 2))
	var lo := _cell(center - Vector3(radius, 0, radius))
	var hi := _cell(center + Vector3(radius, 0, radius))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var mid := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			if mid.distance_to(Vector2(center.x, center.z)) > radius:
				continue
			if zone == Zone.NONE:
				cells.erase(Vector2i(x, y))
			else:
				cells[Vector2i(x, y)] = zone


## Clears one cell's zone, noting the change for lot planning.
func erase_cell(c: Vector2i) -> void:
	if cells.erase(c):
		dirty.append(Rect2(c.x * CELL - CELL, c.y * CELL - CELL, CELL * 3, CELL * 3))


func to_dict() -> Dictionary:
	# One string per zone type: "x,y;x,y;..." keeps saves small.
	var out := {}
	for c in cells:
		var key := str(cells[c])
		out[key] = out.get(key, "") + "%d,%d;" % [c.x, c.y]
	return out


func from_dict(d: Dictionary) -> void:
	cells.clear()
	dirty.clear()
	for key in d:
		for pair in String(d[key]).split(";", false):
			var xy := pair.split(",")
			cells[Vector2i(int(xy[0]), int(xy[1]))] = int(key)


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))
