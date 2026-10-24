class_name Highways
## The state highways across the region (SR 9, 15, 18, 22, 26, 37 and US 35
## around Marion), built by tools/terrain/build_roads.py from their real
## routes. Two-lane INDOT roads with paved shoulders (RoadStyle STATE_HWY).
## I-69 is here too, each carriageway its own route, but `limited`: an
## interstate has no driveways or crossings, so towns can't join it.
## Inside the backdrop towns (Backdrop) there are none: those towns draw
## their own streets.
##
## Like the county roads (CountyGrid) they are scenery until a town joins
## one: the ground shader paints them from a signed distance field
## (highways.bin, one channel per group of routes) and wild trees keep off,
## so they cost the simulation nothing. Region coordinates throughout.

## Half the paved road: two 12 ft lanes and 8 ft shoulders (INDOT).
const HALF_WIDTH := 6.0
## Half the cleared strip: the road, its ditches and mowed right of way.
const HALF_CLEAR := 15.0
## Trees stand back this far from the middle of the road.
const TREE_CLEAR := 18.0
## Size of the bins the routes are filed in for lookups, metres.
const BIN := 256.0

static var _loaded := false
## Each route (read them through all()): {name, short, pts: PackedVector2Array, cum: PackedFloat32Array}.
static var routes: Array = []
static var _bins := {}  # Vector2i -> [[route, segment], ...]
static var _field := PackedByteArray()
static var _n := 0
static var _range := 127.0
static var _tex: ImageTexture


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var json = JSON.parse_string(FileAccess.get_file_as_string(Terrain.DIR + "highways.json"))
	if typeof(json) != TYPE_DICTIONARY:
		push_error("Highways: can't read highways.json")
		return
	_range = float(json.get("range", 127.0))
	for r in json.routes:
		var pts := PackedVector2Array()
		var cum := PackedFloat32Array()
		var total := 0.0
		for q in r.pts:
			var p := Vector2(float(q[0]), float(q[1]))
			if not pts.is_empty():
				total += pts[pts.size() - 1].distance_to(p)
			pts.append(p)
			cum.append(total)
		var id := routes.size()
		routes.append({"name": str(r.name), "short": str(r.short), "pts": pts, "cum": cum,
			"limited": bool(r.get("limited", false))})
		if routes[id].limited:
			continue  # painted, but nothing can join it or cross it at grade
		for i in pts.size() - 1:
			var lo := Vector2i((pts[i].min(pts[i + 1]) / BIN).floor())
			var hi := Vector2i((pts[i].max(pts[i + 1]) / BIN).floor())
			for bx in range(lo.x, hi.x + 1):
				for bz in range(lo.y, hi.y + 1):
					var k := Vector2i(bx, bz)
					if not _bins.has(k):
						_bins[k] = []
					_bins[k].append([id, i])
	var img := Image.new()
	if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(Terrain.DIR + "highways.bin")) == OK:
		img.convert(Image.FORMAT_RGB8)
		_n = img.get_width()
		_field = img.get_data()
		_tex = ImageTexture.create_from_image(img)


## The routes (see `routes`), loaded.
static func all() -> Array:
	_load()
	return routes


## The distance field for the ground shader (RGB: signed metres + 128).
static func texture() -> Texture2D:
	_load()
	return _tex


## How far a point is from the middle of the nearest highway, metres (the
## field's reach at most): what the ground paints, cheap enough per tree.
static func distance(x: float, z: float) -> float:
	_load()
	if _n == 0:
		return INF
	var cell := Terrain.SIZE / _n
	var u := (x - Terrain.CENTRE.x + Terrain.SIZE * 0.5) / cell - 0.5
	var v := (z - Terrain.CENTRE.y + Terrain.SIZE * 0.5) / cell - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	var ia := Terrain._mirror(i0, _n)
	var ib := Terrain._mirror(i0 + 1, _n)
	var ja := Terrain._mirror(j0, _n)
	var jb := Terrain._mirror(j0 + 1, _n)
	var best := INF
	for ch in 3:
		var a := float(_field[(ja * _n + ia) * 3 + ch])
		var b := float(_field[(ja * _n + ib) * 3 + ch])
		var c := float(_field[(jb * _n + ia) * 3 + ch])
		var d := float(_field[(jb * _n + ib) * 3 + ch])
		var s := lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv) - 128.0
		best = minf(best, absf(s))
	return best


## True where a highway's cleared strip runs: the road, ditches and right of
## way, on dry land. `half` widens it (trees).
static func clears(x: float, z: float, half := HALF_CLEAR) -> bool:
	return distance(x, z) <= half and Terrain.water(x, z) < 0.1


## The highway nearest a point, if one runs within `reach` metres:
## {route, seg (index of the piece), on (the nearest point), along (metres
## from the route's start), dist}, or {}. Only `route`'s, if given.
static func near(x: float, z: float, reach: float, route := -1) -> Dictionary:
	_load()
	var p := Vector2(x, z)
	var best := {}
	var best_d := reach
	var lo := Vector2i(((p - Vector2(reach, reach)) / BIN).floor())
	var hi := Vector2i(((p + Vector2(reach, reach)) / BIN).floor())
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			for e in _bins.get(Vector2i(bx, bz), []):
				var r: Dictionary = routes[e[0]]
				var a: Vector2 = r.pts[e[1]]
				var b: Vector2 = r.pts[e[1] + 1]
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := q.distance_to(p)
				if d <= best_d:
					best_d = d
					best = {"route": e[0], "seg": e[1], "on": q, "dist": d,
						"along": r.cum[e[1]] + a.distance_to(q)}
	return best


## Where the line a-b (region coordinates) crosses a highway: {route, seg,
## on, along}, or {}.
static func crossing(a: Vector2, b: Vector2) -> Dictionary:
	_load()
	var lo := Vector2i((a.min(b) / BIN).floor())
	var hi := Vector2i((a.max(b) / BIN).floor())
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			for e in _bins.get(Vector2i(bx, bz), []):
				var r: Dictionary = routes[e[0]]
				var p: Vector2 = r.pts[e[1]]
				var q: Vector2 = r.pts[e[1] + 1]
				var hit = Geometry2D.segment_intersects_segment(a, b, p, q)
				if hit != null:
					return {"route": e[0], "seg": e[1], "on": hit, "along": r.cum[e[1]] + p.distance_to(hit)}
	return {}


## The route's line from metres `from` along it, out toward `to` (either
## way), as points.
static func path(route: int, from: float, to: float) -> PackedVector2Array:
	_load()
	var r: Dictionary = routes[route]
	var pts: PackedVector2Array = r.pts
	var cum: PackedFloat32Array = r.cum
	to = clampf(to, 0.0, cum[cum.size() - 1])
	var out := PackedVector2Array([point(route, from)])
	if to > from:
		for i in pts.size():
			if cum[i] > from and cum[i] < to:
				out.append(pts[i])
	else:
		for i in range(pts.size() - 1, -1, -1):
			if cum[i] < from and cum[i] > to:
				out.append(pts[i])
	out.append(point(route, to))
	return out


## A route's length, metres.
static func length(route: int) -> float:
	_load()
	var cum: PackedFloat32Array = routes[route].cum
	return cum[cum.size() - 1]


## The point metres `s` along a route.
static func point(route: int, s: float) -> Vector2:
	_load()
	var r: Dictionary = routes[route]
	var pts: PackedVector2Array = r.pts
	var cum: PackedFloat32Array = r.cum
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var i := cum.bsearch(s) - 1
	i = clampi(i, 0, pts.size() - 2)
	var span := cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], (s - cum[i]) / span if span > 0.0 else 0.0)
