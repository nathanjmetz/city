class_name RoadIndex
extends RefCounted
## Every road's sampled centre line and the box around it, bucketed by
## CELL squares, so a question about one patch of ground (does a road run
## through this outline?) looks only at the roads near it instead of every
## road in town. Worked out again whenever the roads change
## (RoadNetwork.revision goes up on every edit), so it never answers for
## roads as they were.

const CELL := 100.0
## Points along each road, as RoadNetwork.sample_segment(id, SAMPLES).
const SAMPLES := 24

var samples := {}  # seg id -> PackedVector3Array
## seg id -> Rect2 around its samples (x, z), grown by its right of way
## (RoadStyle.right_of_way_half): all the ground the road can reach.
var boxes := {}
var _cells := {}  # Vector2i -> [seg ids]

static var _of := {}  # network instance id -> [revision, segment count, RoadIndex]


## The index for the roads as they are now, or null mid-batch (the roads
## half edited, and the revision not yet moved on).
static func of(network: RoadNetwork) -> RoadIndex:
	if network._batch > 0 or network._batch_dirty:
		return null
	var key := network.get_instance_id()
	var e: Array = _of.get(key, [])
	if not e.is_empty() and e[0] == network.revision and e[1] == network.segments.size():
		return e[2]
	if _of.size() > 16:
		_of.clear()  # networks from tests come and go
	var ix := RoadIndex.new()
	for id in network.segments:
		var pts := network.sample_segment(id, SAMPLES)
		ix.samples[id] = pts
		var box := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
		for p in pts:
			box = box.expand(Vector2(p.x, p.z))
		box = box.grow(RoadStyle.right_of_way_half(network.segments[id].type))
		ix.boxes[id] = box
		for x in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for y in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var c := Vector2i(x, y)
				if not ix._cells.has(c):
					ix._cells[c] = []
				ix._cells[c].append(id)
	_of[key] = [network.revision, network.segments.size(), ix]
	return ix


## The roads whose right of way could reach into `area` (their box meets
## it), in no particular order, each once.
func near(area: Rect2) -> Array:
	var r := area
	var seen := {}
	for x in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for y in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			for id in _cells.get(Vector2i(x, y), []):
				if not seen.has(id) and (boxes[id] as Rect2).intersects(r, true):
					seen[id] = true
	return seen.keys()
