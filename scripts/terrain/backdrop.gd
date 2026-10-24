class_name Backdrop
## The real towns on the map that nobody plays: Marion, the county seat, and
## Gas City and Jonesboro just south of it, inside their real town limits
## (terrain/grant_in/places.json, from tools/terrain/build_roads.py). They
## stand finished, nothing can be built inside them, and the towns players
## found grow up around them, as the small towns of Grant County grew up
## around Marion. Also the start sites: the real small towns a new player
## founds a town at, as its original crossroads.
##
## Region coordinates throughout.

static var _loaded := false
## {name, pop (2020 Census), centre: Vector2, outlines: [PackedVector2Array], box: Rect2}
static var _cities: Array = []
## {name, pop, centre: Vector2}, in the order new towns are offered them.
static var _sites: Array = []
static var _box := Rect2()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var json = JSON.parse_string(FileAccess.get_file_as_string(Terrain.DIR + "places.json"))
	if typeof(json) != TYPE_DICTIONARY:
		return
	for c in json.get("backdrop", []):
		var outlines := []
		var box := Rect2()
		for o in c.outlines:
			var poly := PackedVector2Array()
			for q in o:
				poly.append(Vector2(float(q[0]), float(q[1])))
			outlines.append(poly)
			var r := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				r = r.expand(q)
			box = r if box.size == Vector2.ZERO else box.merge(r)
		_cities.append({"name": str(c.name), "pop": int(c.pop),
			"centre": Vector2(float(c.centre[0]), float(c.centre[1])), "outlines": outlines, "box": box})
		_box = box if _box.size == Vector2.ZERO else _box.merge(box)
	for s in json.get("sites", []):
		_sites.append({"name": str(s.name), "pop": int(s.pop), "centre": Vector2(float(s.centre[0]), float(s.centre[1]))})


## The backdrop towns: {name, pop, centre, outlines, box}.
static func cities() -> Array:
	_load()
	return _cities


## The start sites, in the order they're offered: {name, pop, centre}.
static func sites() -> Array:
	_load()
	return _sites


## True inside a backdrop town's limits, or within `radius` metres of them.
static func inside(p: Vector2, radius := 0.0) -> bool:
	_load()
	if _cities.is_empty() or not _box.grow(radius).has_point(p):
		return false
	for c in _cities:
		if not c.box.grow(radius).has_point(p):
			continue
		for poly in c.outlines:
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
		if radius > 0.0 and _edge(p, c) <= radius:
			return true
	return false


## True if a box (region metres) reaches into any backdrop town's bounds:
## a cheap first check before inside() on many points.
static func overlaps(box: Rect2) -> bool:
	_load()
	for c in _cities:
		if c.box.intersects(box):
			return true
	return false


## Metres from a point to the nearest backdrop town's limits (0 inside).
static func distance_to(p: Vector2) -> float:
	_load()
	var best := INF
	for c in _cities:
		for poly in c.outlines:
			if Geometry2D.is_point_in_polygon(p, poly):
				return 0.0
		best = minf(best, _edge(p, c))
	return best


## The backdrop town whose limits hold `p` (or come nearest), as cities()
## gives it, or {} if there are none.
static func nearest(p: Vector2) -> Dictionary:
	_load()
	var best := {}
	var best_d := INF
	for c in _cities:
		var d := 0.0
		var hit := false
		for poly in c.outlines:
			hit = hit or Geometry2D.is_point_in_polygon(p, poly)
		if not hit:
			d = _edge(p, c)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _edge(p: Vector2, c: Dictionary) -> float:
	var best := INF
	for poly in c.outlines:
		var n: int = poly.size()
		for i in n:
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
			best = minf(best, q.distance_to(p))
	return best


## Jobs in the backdrop towns a town at `at` can commute to, each town's
## weighed by how far it is (Market.weight, from its limits).
static func commute_jobs(at: Vector2) -> float:
	_load()
	var total := 0.0
	for c in _cities:
		var d := 0.0
		var hit := false
		for poly in c.outlines:
			hit = hit or Geometry2D.is_point_in_polygon(at, poly)
		if not hit:
			d = _edge(at, c)
		total += c.pop * Balance.BACKDROP_JOBS_PER_PERSON * Market.weight(d)
	return total
