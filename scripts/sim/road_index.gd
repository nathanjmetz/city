class_name RoadIndex
extends RefCounted
## Every road's box (around its control points, which its curve never
## leaves), bucketed by CELL squares, so a question about one patch of
## ground (does a road run through this outline? which road is nearest?)
## looks only at the roads near it instead of every road in town. Made
## again whenever the roads change (RoadNetwork.revision goes up on every
## edit), so it never answers for roads as they were; each road's sampled
## line is worked out the first time it's asked for.

const CELL := 100.0
## Points along each road, as RoadNetwork.sample_segment(id, SAMPLES).
const SAMPLES := 24

var network: RoadNetwork
var hulls := {}  # seg id -> Rect2 around its control points (x, z)
## seg id -> its hull grown by its right of way (RoadStyle.right_of_way_half):
## all the ground the road can reach.
var reach := {}
var order := {}  # seg id -> its place in network.segments
var _samples := {}  # seg id -> PackedVector3Array, when first asked for
var _cells := {}  # Vector2i -> [seg ids whose reach box meets it]

static var _of := {}  # network instance id -> [revision, segment count, RoadIndex]


## The index for the roads as they are now, or null mid-batch (the roads
## half edited, and the revision not yet moved on).
static func of(net: RoadNetwork) -> RoadIndex:
	if net._batch > 0 or net._batch_dirty:
		return null
	var key := net.get_instance_id()
	var e: Array = _of.get(key, [])
	if not e.is_empty() and e[0] == net.revision and e[1] == net.segments.size():
		return e[2]
	if _of.size() > 16:
		_of.clear()  # networks from tests come and go
	var ix := RoadIndex.new()
	ix.network = net
	var i := 0
	for id in net.segments:
		var c := net.curve_of(id)
		var hull := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)) \
			.expand(Vector2(c[2].x, c[2].z))
		ix.hulls[id] = hull
		var box := hull.grow(RoadStyle.right_of_way_half(net.segments[id].type))
		ix.reach[id] = box
		ix.order[id] = i
		i += 1
		for x in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for y in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var cell := Vector2i(x, y)
				if not ix._cells.has(cell):
					ix._cells[cell] = []
				ix._cells[cell].append(id)
	_of[key] = [net.revision, net.segments.size(), ix]
	return ix


## A road's sampled line, RoadNetwork.sample_segment(id, SAMPLES).
func samples(id: int) -> PackedVector3Array:
	if not _samples.has(id):
		_samples[id] = network.sample_segment(id, SAMPLES)
	return _samples[id]


## The roads whose right of way could reach into `area` (their reach box
## meets it), in no particular order, each once.
func near(area: Rect2) -> Array:
	var seen := {}
	for x in range(floori(area.position.x / CELL), floori(area.end.x / CELL) + 1):
		for y in range(floori(area.position.y / CELL), floori(area.end.y / CELL) + 1):
			for id in _cells.get(Vector2i(x, y), []):
				if not seen.has(id) and (reach[id] as Rect2).intersects(area, true):
					seen[id] = true
	return seen.keys()


## RoadNetwork.find_segment_near, looking only at the roads that could be
## within `max_dist` (in the network's own order, so a tie goes the same
## way): the same answer, without looking at every road in town.
static func segment_near(net: RoadNetwork, pos: Vector3, max_dist: float, max_dy := INF) -> Dictionary:
	var ix := of(net)
	if ix == null:
		return net.find_segment_near(pos, max_dist, max_dy)
	var p := Vector3(pos.x, 0.0, pos.z)
	var q2 := Vector2(p.x, p.z)
	var r := max_dist + 0.01
	var area := Rect2(q2 - Vector2(r, r), Vector2(r, r) * 2.0)
	var ids := []
	var seen := {}
	for x in range(floori(area.position.x / CELL), floori(area.end.x / CELL) + 1):
		for y in range(floori(area.position.y / CELL), floori(area.end.y / CELL) + 1):
			for id in ix._cells.get(Vector2i(x, y), []):
				if not seen.has(id):
					seen[id] = true
					if (ix.hulls[id] as Rect2).grow(r).has_point(q2):
						ids.append(id)
	if ids.size() > 1:
		ids.sort_custom(func(a, b): return ix.order[a] < ix.order[b])
	# From here as RoadNetwork.find_segment_near does it, road by road.
	var best := {}
	var best_d := max_dist
	for id in ids:
		var c := net.curve_of(id)
		var hull := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)) \
			.expand(Vector2(c[2].x, c[2].z)).grow(best_d + 0.01)
		if not hull.has_point(Vector2(p.x, p.z)):
			continue
		var n := 48
		var prev := RoadNetwork.bezier(c[0], c[1], c[2], 0.0)
		for i in range(1, n + 1):
			var cur := RoadNetwork.bezier(c[0], c[1], c[2], float(i) / n)
			var q := Geometry3D.get_closest_point_to_segment(p, RoadNetwork._flat(prev), RoadNetwork._flat(cur))
			var d := q.distance_to(p)
			if d <= best_d:
				var seg_len := RoadNetwork._flat(prev).distance_to(RoadNetwork._flat(cur))
				var f := 0.0 if seg_len < 0.001 else RoadNetwork._flat(prev).distance_to(q) / seg_len
				var t := (float(i - 1) + f) / n
				if absf(RoadNetwork.bezier(c[0], c[1], c[2], t).y - pos.y) > max_dy:
					prev = cur
					continue
				best_d = d
				best = {"seg": id, "t": t, "point": RoadNetwork.bezier(c[0], c[1], c[2], t), "dist": d}
			prev = cur
	return best
