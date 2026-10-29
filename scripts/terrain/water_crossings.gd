class_name WaterCrossings
extends RefCounted
## Where the county roads (CountyGrid) and state highways (Highways) cross
## the creeks and the Mississinewa. The ground shader stops painting them at
## the bank, so WaterCrossingView draws each crossing on top: the road
## carried over on fill or a deck, from the paint on one bank to the other.
##
## Indiana counts a structure spanning 20 ft or more as a bridge (inspected
## under the NBIS and numbered by the county); anything smaller is a culvert.
## So a road over a trickle of a creek (a short, barely wet gap) runs on
## fill over a pipe or box culvert with concrete headwalls (INDOT Standard
## Drawings 715), and wider water gets a bridge (BridgeMesh, by span). Past
## MAX_GAP it's a lake or a gravel pit the real road goes round, so the road
## stops at the bank as before. Region coordinates.

## Sampling step along a road, metres.
const STEP := 2.5
## A gap this short with this little water is a culvert, not a bridge.
const CULVERT_GAP := 20.0
const CULVERT_WET := 0.35
## Wider than this the road doesn't cross.
const MAX_GAP := 250.0
## Water counts here (CountyGrid.clears).
const WET := 0.1
## The ground shader's paint starts fading out this wet (TerrainView), so
## the crossing runs out to where the road is drawn in full.
const PAINT_WET := 0.06
## Steepest grade up onto a deck: county roads 6%, state highways 4%
## (AASHTO rural local roads and arterials, rolling terrain).
const GRADE := {"county": 0.06, "highway": 0.04}
## Clearance over the water: a culvert's pipe and its cover; a county bridge
## and a state one (INDOT: 2 ft freeboard over the design flood, which runs
## well above the normal water the map shows).
const OVER := {"culvert": 1.8, "county": 3.0, "highway": 5.0}
## Highways are walked in stretches this long, metres.
const CHUNK := 1000.0
## Longest approach fill up onto a deck, metres.
const MAX_APPROACH := 200.0
## Half the travelled way: a 7 m county road; two 12 ft lanes and 8 ft
## shoulders on a state road.
const HALF := {"county": CountyGrid.HALF_WIDTH, "highway": Highways.HALF_WIDTH}

static var _miles := {}  # mile key -> its crossings
static var _highways := {}  # Vector2i(route, stretch) -> its crossings


## The crossings on one mile of county road ("ns:3:-2").
static func on_mile(key: String) -> Array:
	if _miles.has(key):
		return _miles[key]
	var mile := CountyGrid.mile_of(key, 0.0, 0.0)
	var a: Vector2 = mile.a
	var b: Vector2 = mile.b
	# Most miles never meet the water: look along them coarsely first.
	var wet := false
	for k in 161:
		var q := a.lerp(b, k / 160.0)
		if Terrain.water(q.x, q.y) >= PAINT_WET:
			wet = true
			break
	if not wet:
		_miles[key] = []
		return []
	var n := ceili(a.distance_to(b) / STEP)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(a.lerp(b, float(i) / n))
	var out := []
	for g in gaps(pts, func(p: Vector2) -> bool:
			return Terrain.water(p.x, p.y) < PAINT_WET and Terrain.slope(p.x, p.y) < CountyGrid.MAX_SLOPE):
		out.append(_crossing("%s@%d" % [key, g[0]], pts, g, "county"))
	_miles[key] = out
	return out


## The crossings starting on one stretch of a state highway: CHUNK metres
## from `k` * CHUNK along route `r`, walked with enough either side to take
## in a whole crossing (found once).
static func on_highway(r: int, k: int) -> Array:
	var id := Vector2i(r, k)
	if _highways.has(id):
		return _highways[id]
	var out := []
	var pad := MAX_GAP + MAX_APPROACH + STEP * 4.0
	var from := maxf(k * CHUNK - pad, 0.0)
	var to := minf((k + 1) * CHUNK + pad, Highways.length(r))
	var pts := PackedVector2Array()
	var s := from
	while s <= to:
		pts.append(Highways.point(r, s))
		s += STEP
	for g in gaps(pts, func(p: Vector2) -> bool: return Terrain.water(p.x, p.y) < PAINT_WET):
		var at := from + int(g[0]) * STEP
		if at >= k * CHUNK and at < (k + 1) * CHUNK:
			out.append(_crossing("hw:%d@%d" % [r, roundi(at)], pts, g, "highway"))
	_highways[id] = out
	return out


## What to look at for crossings within `reach` of `c`, each cheap to list
## and a few milliseconds to walk (run_job): ["mile", key] for the county
## miles not in `hidden` (those a town has taken over), ["hw", route,
## stretch] for the highways.
static func jobs(c: Vector2, reach: float, hidden: Dictionary = {}) -> Array:
	var out := []
	var sec := CountyGrid.SECTION
	var lo := Vector2i(((c - Vector2(reach, reach)) / sec).floor())
	var hi := Vector2i(((c + Vector2(reach, reach)) / sec).floor()) + Vector2i.ONE
	for kind: String in ["ns", "ew"]:
		var lines := Vector2i(lo.x, hi.x) if kind == "ns" else Vector2i(lo.y, hi.y)
		var segs := Vector2i(lo.y, hi.y) if kind == "ns" else Vector2i(lo.x, hi.x)
		for line in range(lines.x, lines.y + 1):
			for seg in range(segs.x - 1, segs.y + 1):
				if not CountyGrid.has_mile(line + ((1 << 20) if kind == "ew" else 0), seg):
					continue
				var key := "%s:%d:%d" % [kind, line, seg]
				if hidden.has(key):
					continue
				if (CountyGrid.mile_of(key, c.x, c.y).on as Vector2).distance_to(c) <= reach:
					out.append(["mile", key])
	for r in Highways.all().size():
		var at := Highways.near(c.x, c.y, reach, r)
		if at.is_empty():
			continue
		for k in range(floori((at.along - reach * 1.5) / CHUNK), floori((at.along + reach * 1.5) / CHUNK) + 1):
			if k >= 0 and k * CHUNK < Highways.length(r):
				out.append(["hw", r, k])
	return out


static func run_job(job: Array) -> Array:
	return on_mile(job[1]) if job[0] == "mile" else on_highway(job[1], job[2])


## Crossings within `reach` of `c` (all the jobs at once).
static func near(c: Vector2, reach: float, hidden: Dictionary = {}) -> Array:
	var out := []
	for job in jobs(c, reach, hidden):
		for x in run_job(job):
			if x.mid.distance_to(c) <= reach:
				out.append(x)
	return out


## Gaps in the road along `pts` where `ok` fails, with water in them and
## the road on both banks: [first bad sample, last bad sample, most water].
static func gaps(pts: PackedVector2Array, ok: Callable) -> Array:
	var out := []
	var start := -1
	var wet := 0.0
	for i in pts.size():
		if ok.call(pts[i]):
			if start > 0 and wet >= WET and (i - start) * STEP <= MAX_GAP:
				out.append([start, i - 1, wet])
			start = -1
			wet = 0.0
		else:
			if start == -1:
				start = i
			wet = maxf(wet, Terrain.water(pts[i].x, pts[i].y))
	return out


## A crossing from a gap: its line from the bank on one side to the other,
## with the approach fill run back far enough to climb to the deck, the
## deck's height at each point, and what carries it.
static func _crossing(key: String, all: PackedVector2Array, g: Array, road: String) -> Dictionary:
	var span := (int(g[1]) - int(g[0]) + 1) * STEP
	var kind := "culvert" if span <= CULVERT_GAP and float(g[2]) < CULVERT_WET else "bridge"
	var level := -INF
	for i in range(g[0], g[1] + 1):
		if Terrain.water(all[i].x, all[i].y) >= WET:
			level = maxf(level, Terrain.water_level(all[i].x, all[i].y))
	var need: float = level + OVER["culvert" if kind == "culvert" else road]
	var grade: float = GRADE[road]
	var i0 := _approach(all, int(g[0]) - 1, -1, need, grade)
	var i1 := _approach(all, int(g[1]) + 1, 1, need, grade)
	var pts := all.slice(i0, i1 + 1)
	var wettest := 0
	var most := 0.0
	for i in pts.size():
		var w := Terrain.water(pts[i].x, pts[i].y)
		if w > most:
			most = w
			wettest = i
	return {"key": key, "road": road, "kind": kind, "pts": pts, "deck": profile(pts, need, grade), "span": span,
		"wettest": wettest, "level": level, "mid": all[(int(g[0]) + int(g[1])) / 2]}


## How far back along the road from the bank (sample `i`, going `dir`) the
## approach starts: far enough to climb to `need` at `grade`, over dry
## land, two steps at least.
static func _approach(all: PackedVector2Array, i: int, dir: int, need: float, grade: float) -> int:
	var rise := need - Terrain.height(all[i].x, all[i].y)
	var steps := clampi(ceili(rise / grade / STEP) + 2, 2, ceili(MAX_APPROACH / STEP))
	var j := i
	for k in steps:
		var n := j + dir
		if n < 0 or n >= all.size() or Terrain.water(all[n].x, all[n].y) >= PAINT_WET:
			break
		j = n
	return j


## The deck's height along `pts`: straight from end to end, up to `need`
## over the water, no steeper than `grade` off either end, and never under
## the ground (but through a bluff).
static func profile(pts: PackedVector2Array, need: float, grade: float) -> PackedFloat32Array:
	var n := pts.size()
	var ground := PackedFloat32Array()
	var cum := PackedFloat32Array()
	for i in n:
		ground.append(Terrain.height(pts[i].x, pts[i].y))
		cum.append(0.0 if i == 0 else cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var length := cum[n - 1]
	var ya := ground[0]
	var yb := ground[n - 1]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := cum[i] / maxf(length, 0.001)
		var y := maxf(lerpf(ya, yb, t), need)
		y = minf(y, minf(ya + grade * cum[i], yb + grade * (length - cum[i])))
		out[i] = maxf(y, _floor(pts[i], ground[i])) if i > 0 and i < n - 1 else ground[i] + 0.08
	# Round the crest and sags a little (a vertical curve), ends held.
	for _round in 3:
		var prev := out.duplicate()
		for i in range(1, n - 1):
			out[i] = maxf((prev[i - 1] + prev[i] * 2.0 + prev[i + 1]) * 0.25, _floor(pts[i], ground[i]))
	return out


## The lowest the deck goes at a point: just over the ground, except where
## a bluff stands in the way, which the road cuts through.
static func _floor(p: Vector2, ground: float) -> float:
	if Terrain.water(p.x, p.y) < WET and Terrain.slope(p.x, p.y) >= CountyGrid.MAX_SLOPE:
		return -INF
	return ground + 0.1
