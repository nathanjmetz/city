class_name Streets
extends RefCounted
## Street names (Brawn: believable names on everything). Every road gets the
## name a real southern Indiana town would give it, and keeps it:
##   - the first town street is Main Street; streets across it are numbered
##     by how far along Main they cross (3rd Street), streets alongside it
##     take the old town names (Walnut, Spring, Pike, Sycamore, then the
##     presidents), the way the original plats of Petersburg, Jasper and
##     Washington were laid out
##   - curving streets are subdivision streets (Meadow Lane, Fox Run)
##   - county roads are numbered by distance from the middle of town, the
##     Indiana county grid: County Road 300 N is three miles north
##   - gravel roads take a family's name (Kluemper Road)
##   - divided and state highways are State Roads (57, 61), freeways I-69
##   - alleys, ramps and roundabout rings have no name
## A street keeps its name through junctions where it runs on straight, when
## a new road cuts it in two, and when it's rebuilt or upgraded in place.
## Deterministic (named in segment id order), so every copy agrees.

signal changed

## Old-town street names, in the order a town of the 1850s used them.
const TOWN := ["Walnut", "Spring", "Pike", "Sycamore", "Maple", "Oak", "Vine", "Cherry", "Mill", "Church",
	"Chestnut", "Locust", "Elm", "Poplar", "Market", "High", "Water", "School", "Hickory", "Mulberry",
	"Washington", "Jefferson", "Madison", "Monroe", "Jackson", "Lincoln", "Franklin", "Harrison", "Union", "Bridge"]
## Post-war subdivision streets: whole names, suffix included.
const SUBDIVISION := ["Meadow Lane", "Ridgeview Drive", "Fox Run", "Hillcrest Drive", "Woodland Drive",
	"Briarwood Court", "Country Club Road", "Sunset Drive", "Oak Hill Road", "Willow Lane", "Park Drive",
	"Deer Run", "Cardinal Drive", "Shady Lane", "Lakeview Drive", "Orchard Lane", "Hawthorne Drive",
	"Timber Ridge", "Cedar Court", "Valley View Drive", "Dogwood Lane", "Redbud Lane", "Quail Run", "Prairie Lane"]
## Real state roads and interstates around Pike County.
const STATE_ROADS := [57, 61, 56, 257, 364, 356, 164]
## Pike County towns a road out of town is named for (Winslow Road).
const TOWNS := ["Winslow", "Otwell", "Spurgeon", "Stendal", "Velpen", "Algiers", "Oakland City", "Washington",
	"Jasper", "Glezen", "Arthur", "Blackburn"]
const INTERSTATES := [69, 64]
## A town block along Main, metres (about 330 ft, the old Indiana plat).
const BLOCK := 100.0
## Within this angle of Main's line a street counts as alongside or across it.
const SQUARE := 25.0
## A road runs on as the same street through a junction within this bend.
const STRAIGHT := 30.0

var names := {}      # segment id -> street name
var used := {}       # name -> true (pool names already given out)
var numbered := {}   # number -> distance along Main of its first street
var main_dir := Vector2.ZERO
var main_at := Vector2.ZERO
## Each named segment's shape, to hand its name on when it's cut or rebuilt.
var _shapes := {}    # segment id -> PackedVector2Array
## True while a road is built that gets its name afterwards (name_road).
var hold := false


func name_of(seg: int) -> String:
	return names.get(seg, "")


## Names every new road and forgets removed ones. Called on network changes.
func sync(sim) -> void:
	if hold:
		return
	var net: RoadNetwork = sim.network
	var gone := []
	for id in names.keys():
		if not net.segments.has(id):
			gone.append([names[id], _shapes.get(id, PackedVector2Array())])
			names.erase(id)
			_shapes.erase(id)
	var fresh := []
	for id in net.segments:
		if not names.has(id) and _named_type(int(net.segments[id].type)):
			fresh.append(id)
	if fresh.is_empty() and gone.is_empty():
		return
	fresh.sort()
	# Cut in two or rebuilt where it was: the same street.
	for id in fresh:
		var shape := _shape(net, id)
		for g in gone:
			if _lies_on(shape, g[1]):
				_name_seg(net, id, g[0])
				break
	# Then each runs on from a named street it continues straight, until
	# none do; the first still unnamed then gets a new name, and so on.
	var left: Array = fresh.filter(func(id): return not names.has(id))
	while not left.is_empty():
		var progress := true
		while progress:
			progress = false
			for id in left:
				var n := _continued(net, id)
				if n != "":
					_name_seg(net, id, n)
					progress = true
			left = left.filter(func(id): return not names.has(id))
		if left.is_empty():
			break
		_name_seg(net, left[0], _new_name(sim, left[0]))
		left.remove_at(0)
	changed.emit()


## Gives a run of segments one name (the county highway a town starts on).
func name_road(sim, segs: Array, name: String) -> void:
	for id in segs:
		if sim.network.segments.has(id):
			_name_seg(sim.network, id, name)
	changed.emit()


## The name of a road out of town toward a neighbouring town.
func town_road(seed: int) -> String:
	return _first_free(TOWNS.map(func(t): return t + " Road"), seed, "Road")


## A county road's name from where it runs: an east-west road is numbered
## by its distance north or south of the middle of town, a north-south one
## east or west, in hundredths of a mile rounded to 25 (Indiana county grid).
static func county_name(a: Vector2, b: Vector2) -> String:
	var mid := (a + b) * 0.5
	var ew := absf(b.x - a.x) >= absf(b.y - a.y)
	var off := mid.y if ew else mid.x
	var n := maxi(25, roundi(absf(off) / 1609.0 * 100.0 / 25.0) * 25)
	var side := ("S" if off > 0.0 else "N") if ew else ("E" if off > 0.0 else "W")
	return "County Road %d %s" % [n, side]


func to_dict() -> Dictionary:
	var n := {}
	for id in names:
		n[str(id)] = names[id]
	var num := {}
	for k in numbered:
		num[str(k)] = numbered[k]
	return {"names": n, "used": used.keys(), "numbered": num,
		"main": [main_dir.x, main_dir.y, main_at.x, main_at.y]}


func from_dict(sim, d: Dictionary) -> void:
	names.clear()
	used.clear()
	numbered.clear()
	_shapes.clear()
	for k in d.get("names", {}):
		if sim.network.segments.has(int(k)):
			_name_seg(sim.network, int(k), str(d.names[k]))
	for u in d.get("used", []):
		used[str(u)] = true
	for k in d.get("numbered", {}):
		numbered[int(k)] = float(d.numbered[k])
	var m: Array = d.get("main", [0, 0, 0, 0])
	main_dir = Vector2(float(m[0]), float(m[1]))
	main_at = Vector2(float(m[2]), float(m[3]))
	# Roads from a save made before streets had names get theirs now.
	sync(sim)
	changed.emit()


# --- Naming ------------------------------------------------------------------

static func _named_type(type: int) -> bool:
	return not type in [RoadStyle.Type.ALLEY, RoadStyle.Type.RAMP, RoadStyle.Type.RAMP2,
		RoadStyle.Type.RING, RoadStyle.Type.RING2]


func _name_seg(net: RoadNetwork, id: int, name: String) -> void:
	names[id] = name
	_shapes[id] = _shape(net, id)


## The name of a named street this segment runs straight on from, if any.
func _continued(net: RoadNetwork, id: int) -> String:
	var best := ""
	var straightest := cos(deg_to_rad(STRAIGHT))
	var s: Dictionary = net.segments[id]
	for node in [s.a, s.b]:
		var out := _out_dir(net, id, node)
		for other in net.segments_at(node):
			if other == id or not names.has(other):
				continue
			var d := -out.dot(_out_dir(net, other, node))
			if d > straightest:
				straightest = d
				best = names[other]
	return best


## Which way a segment leaves `node`, flat.
static func _out_dir(net: RoadNetwork, id: int, node: int) -> Vector2:
	var c := net.curve_of(id)
	var v: Vector3 = c[1] - c[0] if net.segments[id].a == node else c[1] - c[2]
	if Vector2(v.x, v.z).length() < 0.01:
		v = c[2] - c[0] if net.segments[id].a == node else c[0] - c[2]
	return Vector2(v.x, v.z).normalized()


func _new_name(sim, id: int) -> String:
	var net: RoadNetwork = sim.network
	var s: Dictionary = net.segments[id]
	var type := int(s.type)
	var c := net.curve_of(id)
	var a := Vector2(c[0].x, c[0].z)
	var b := Vector2(c[2].x, c[2].z)
	var seed := hash([sim.city_seed, id])
	match type:
		RoadStyle.Type.HIGHWAY, RoadStyle.Type.FREEWAY2, RoadStyle.Type.FREEWAY4:
			return _first_free(INTERSTATES.map(func(n): return "I-%d" % n), seed, "Highway")
		RoadStyle.Type.DIVIDED_HWY, RoadStyle.Type.STATE_HWY:
			return _first_free(STATE_ROADS.map(func(n): return "State Road %d" % n), seed, "Highway")
		RoadStyle.Type.COUNTY:
			return county_name(a, b)
		RoadStyle.Type.GRAVEL:
			return _first_free([], seed, "Road")
	var suffix := _suffix(type)
	var dir := (b - a).normalized()
	if main_dir == Vector2.ZERO and suffix == "Street":
		main_dir = dir
		main_at = (a + b) * 0.5
		used["Main Street"] = true
		return "Main Street"
	# A curving street is a subdivision street.
	var mid := (a + b) * 0.5
	var chord := a.distance_to(b)
	if chord > 1.0 and Vector2(c[1].x, c[1].z).distance_to(mid) > chord * 0.12:
		return _first_free(SUBDIVISION, seed, suffix)
	if main_dir != Vector2.ZERO:
		var across := absf(dir.dot(main_dir)) < sin(deg_to_rad(SQUARE))
		var along := (mid - main_at).dot(main_dir)
		if across and along > BLOCK * 0.5:
			return _ordinal(_number(along)) + " " + suffix
	return _first_free(TOWN.map(func(t): return t + " " + suffix), seed, suffix)


## The number for a street crossing Main `along` metres out: one per block,
## moved on to the next free number when a street already has it.
func _number(along: float) -> int:
	var n := maxi(1, roundi(along / BLOCK))
	while numbered.has(n) and absf(float(numbered[n]) - along) > BLOCK * 0.4:
		n += 1
	if not numbered.has(n):
		numbered[n] = along
	return n


func _first_free(pool: Array, seed: int, suffix: String) -> String:
	for p in pool:
		if not used.has(p):
			used[p] = true
			return p
	# Out of town names: a family's (rural roads are named for the farm
	# families along them).
	for i in 64:
		var n := "%s %s" % [Names.surname(hash([seed, i])), suffix]
		if not used.has(n):
			used[n] = true
			return n
	return "%s %s %d" % [Names.surname(seed), suffix, absi(seed) % 1000]


static func _suffix(type: int) -> String:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var group := int(spec.get("group", type))
	if type == RoadStyle.Type.PARKWAY:
		return "Parkway"
	if type == RoadStyle.Type.STRIP:
		return "Road"
	match group:
		RoadStyle.Type.AVENUE: return "Avenue"
		RoadStyle.Type.BOULEVARD: return "Boulevard"
	return "Street"


static func _ordinal(n: int) -> String:
	var tail := "th"
	if n % 100 < 11 or n % 100 > 13:
		tail = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, tail]


# --- Shapes --------------------------------------------------------------------

static func _shape(net: RoadNetwork, id: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in net.sample_segment(id, 16):
		out.append(Vector2(p.x, p.z))
	return out


## True when every point of `shape` lies within a couple of metres of the
## old road `on` (a piece of it, after a cut or rebuild).
static func _lies_on(shape: PackedVector2Array, on: PackedVector2Array) -> bool:
	if on.size() < 2 or shape.is_empty():
		return false
	for p in shape:
		var near := INF
		for i in on.size() - 1:
			near = minf(near, p.distance_to(Geometry2D.get_closest_point_to_segment(p, on[i], on[i + 1])))
		if near > 2.5:
			return false
	return true
