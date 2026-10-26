class_name HistoricMarkers
extends RefCounted
## Roadside historical markers for the town's firsts (Brawn, 2026-10-23).
##
## Real reference: the Indiana Historical Bureau's state markers, cast
## aluminium in dark blue with gold letters, a short title and a few
## sentences, signed "Indiana Historical Bureau" and the year it went up;
## the Hoosier Homestead Award (Indiana State Department of Agriculture) for
## farms kept in one family for a century; and the National Register's plaque
## for a historic district. Like Kokomo, the "City of Firsts", a town here
## remembers its first store, first school, first stoplight...
##
## Checked once a game month; each first is found once and kept for good,
## even if the building is gone later (the marker stays, as real ones do).
## Title and text may hold "{town}", filled with the town's name when shown.

signal changed

## Each first: [key, title, text]. {name}, {year}, {street} and {makes} are
## filled when it's found.
const FIRSTS := [
	["founded", "{town}", "Settled in {year} beside the county road. The first buildings in town went up here on {street}."],
	["first_home", "First Home", "{name} was the first family home in town, built in {year}."],
	["first_store", "First Store", "{name} opened here in {year}, the first store in town."],
	["first_factory", "First Factory", "{name} began making {makes} here in {year}, the town's first factory."],
	["first_farm", "Pioneer Farm", "{name} broke the first ground for a farm here in {year}."],
	["first_main_street", "Main Street", "The first shop with flats upstairs went up here in {year}, and Main Street grew around it."],
	["first_school", "First School", "The town's first school opened here in {year}."],
	["first_bank", "First Bank", "{name} opened here in {year}, the first bank in town."],
	["first_post_office", "First Post Office", "Mail first came to town at this post office in {year}."],
	["first_park", "First Park", "{name}, the town's first park, opened in {year}."],
	["first_college", "First College", "The town's first college opened here in {year}."],
	["first_hospital", "First Hospital", "The town's first hospital opened here in {year}."],
	["first_rail", "The Railroad Comes", "{name} opened its depot here in {year}, bringing the railroad to town."],
	["first_signal", "First Stoplight", "The town's first traffic signal went up at this corner in {year}."],
	["first_office", "First Office Building", "The town's first office building went up here in {year}."],
	["oldest_business", "Family Business", "{name} has done business here since {since}, the oldest family business in town."],
]

## [{"id", "key", "title", "text", "year", "pos": [x, z], "face": [x, z],
## "kind": "state" | "homestead" | "district"}], oldest first.
var markers := []
var next_id := 1
## Firsts already marked (key -> marker id).
var seen := {}
## Bumped whenever the markers change (views redraw on it).
var version := 0
## The firsts found by the oldest building of a kind: kind -> first.
const LOT_FIRSTS := {"any": "founded", "home": "first_home", "store": "first_store",
	"mixed_use": "first_main_street", "office": "first_office", "factory": "first_factory"}
## This month's oldest building of each kind (_scan; not saved).
var _oldest_of = null


## Once a game month: anything new worth a marker.
func month(sim) -> void:
	var before := markers.size()
	_oldest_of = {}
	# A few a month: a town that appears at once gets its markers over a
	# season, as a real historical society would put them up.
	for f in FIRSTS:
		if markers.size() - before >= Balance.MARKERS_PER_MONTH:
			break
		if not seen.has(f[0]):
			var found := _find(sim, str(f[0]))
			if not found.is_empty():
				_add(sim, str(f[0]), str(f[1]), str(f[2]), found, "state")
	# Hoosier Homestead: a farm kept by one family for a generation (the real
	# award is for a century; Families passes a farm on every 25 game years).
	for ref in sim.families.owned:
		if markers.size() - before >= Balance.MARKERS_PER_MONTH:
			break
		if not str(ref).begins_with("farm:") or seen.has("homestead:" + ref):
			continue
		var o: Dictionary = sim.families.owned[ref]
		if Seasons.pace_year(sim.tick_count) - int(o.since) < Balance.FAMILY_GENERATION_YEARS:
			continue
		var id := int(str(ref).substr(5))
		if not sim.farms.farms.has(id):
			continue
		var fam: Dictionary = sim.families.family_of(ref)
		_add(sim, "homestead:" + ref, "Hoosier Homestead",
			"The %s family has farmed this land since %d." % [fam.get("surname", "same"), Families.since_year(sim, int(o.since))],
			_farm_spot(sim.farms.farms[id]), "homestead")
	_oldest_of = null
	if markers.size() != before:
		version += 1
		changed.emit()


## The National Register plaque when a district is protected (Heritage).
func district(sim, d: Dictionary, outline: Array) -> void:
	var key := "district:%d" % int(d.id)
	if seen.has(key) or outline.is_empty():
		return
	# At the front of its first building, on the street.
	var spot := {}
	for k in sim.heritage.district_of:
		if sim.heritage.district_of[k] == int(d.id) and sim.lots.has(k):
			spot = _lot_spot(sim, k)
			break
	if spot.is_empty():
		return
	spot.year = Families.calendar(Seasons.year(sim.calendar_tick()))
	_add(sim, key, str(d.name), "Its buildings from the town's early years are protected as a local historic district, designated in {year}.",
		spot, "district")
	version += 1
	changed.emit()


## A marker for a step on the charter ladder (Charter): on Main Street, in
## front of the lot nearest the town's centre.
func charter(sim, step: String, words: Array) -> void:
	var key := "charter:" + step
	if seen.has(key):
		return
	var at: Vector2 = sim.streets.main_at
	var best := ""
	var best_d := INF
	for k in sim.lots:
		if not sim.buildings.has(k):
			continue
		var f: Vector3 = sim.lots[k].front
		var d := Vector2(f.x, f.z).distance_squared_to(at)
		if d < best_d or (d == best_d and k < best):
			best = k
			best_d = d
	if best == "":
		return
	var spot := _lot_spot(sim, best)
	# Beside any marker already standing there.
	for m in markers:
		if Vector2(m.pos[0], m.pos[1]).distance_to(Vector2(spot.pos[0], spot.pos[1])) < 2.0:
			spot.pos = [snappedf(float(spot.pos[0]) + float(spot.face[1]) * 2.5, 0.01),
				snappedf(float(spot.pos[1]) - float(spot.face[0]) * 2.5, 0.01)]
	_add(sim, key, str(words[0]), str(words[1]), spot, "state")
	version += 1
	changed.emit()


func _add(sim, key: String, title: String, text: String, found: Dictionary, kind: String) -> void:
	var year := int(found.get("year", Families.calendar(Seasons.year(sim.calendar_tick()))))
	var fill := {"{name}": str(found.get("name", "")), "{year}": str(year), "{street}": str(found.get("street", "this street")),
		"{makes}": str(found.get("makes", "goods")), "{since}": str(found.get("since", year))}
	for k in fill:
		title = title.replace(k, fill[k])
		text = text.replace(k, fill[k])
	var m := {"id": next_id, "key": key, "title": title, "text": text,
		"year": Families.calendar(Seasons.year(sim.calendar_tick())), "pos": found.pos, "face": found.face, "kind": kind}
	next_id += 1
	markers.append(m)
	seen[key] = m.id


## Where a first stands, and its name and year: {} if the town hasn't one.
func _find(sim, key: String) -> Dictionary:
	match key:
		"founded":
			var k := _oldest(sim, "any")
			if k == "":
				return {}
			var out := _lot_spot(sim, k)
			out.street = sim.streets.name_of(int(sim.lots[k].seg)) if sim.lots.has(k) else ""
			if str(out.street) == "":
				out.street = "this street"
			return out
		"first_home":
			return _lot_first(sim, "home")
		"first_store":
			return _lot_first(sim, "store")
		"first_main_street":
			return _lot_first(sim, "mixed_use")
		"first_office":
			return _lot_first(sim, "office")
		"first_factory":
			var out := _lot_first(sim, "factory")
			if not out.is_empty():
				out.makes = Balance.FACTORY_CHAINS[str(sim.buildings[out.key].get("chain", "general"))].makes
			return out
		"first_farm":
			var ids: Array = sim.farms.farms.keys()
			if ids.is_empty():
				return {}
			ids.sort()
			var out := _farm_spot(sim.farms.farms[ids[0]])
			out.name = _named(sim, "farm:%d" % ids[0], "The family here")
			return out
		"first_school", "first_hospital":
			var kind: int = Services.Kind.SCHOOL if key == "first_school" else Services.Kind.HOSPITAL
			var ids: Array = sim.services.buildings.keys()
			ids.sort()
			for id in ids:
				var s: Dictionary = sim.services.buildings[id]
				if int(s.kind) == kind:
					return _spot(s.pos, s.dir, Services.SETBACK + RoadStyle.SIDEWALK_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
			if key == "first_school":
				return _first_of(sim.education.campuses, func(c): return str(c.kind) == "high_school", "")
			return {}
		"first_bank":
			return _first_of(sim.banks.banks, func(_c): return true, "name")
		"first_post_office":
			return _first_of(sim.mail.offices, func(_c): return true, "")
		"first_park":
			return _first_of(sim.parks.sites, func(_c): return true, "name")
		"first_college":
			return _first_of(sim.education.campuses, func(c): return str(c.kind) != "high_school", "")
		"first_rail":
			return _first_of(sim.rail.depots, func(_c): return true, "name")
		"first_signal":
			var nodes: Array = sim.traffic.junctions.keys()
			nodes.sort()
			for n in nodes:
				if int(sim.traffic.junctions[n].get("control", -1)) == TrafficSim.Rule.SIGNAL and sim.network.nodes.has(n):
					return _corner_spot(sim, int(n))
			return {}
		"oldest_business":
			var best := ""
			var refs: Array = sim.families.owned.keys()
			refs.sort()
			for ref in refs:
				if str(ref).begins_with("lot:") and sim.lots.has(str(ref).substr(4)) \
						and (best == "" or int(sim.families.owned[ref].since) < int(sim.families.owned[best].since)):
					best = ref
			if best == "" or Seasons.pace_year(sim.tick_count) - int(sim.families.owned[best].since) < Balance.FAMILY_GENERATION_YEARS:
				return {}
			var out := _lot_spot(sim, str(best).substr(4))
			out.name = sim.families.name_of(best)
			out.since = Families.since_year(sim, int(sim.families.owned[best].since))
			return out
	return {}


## The oldest building of a kind ("any", "home", "store", "mixed_use",
## "office", "factory"): its lot key, or "". One pass over the buildings a
## month finds them all; ties go to the smaller key, so every copy agrees.
func _oldest(sim, kind: String) -> String:
	if _oldest_of == null or _oldest_of.is_empty():
		var need := {}
		for k in LOT_FIRSTS:
			if not seen.has(LOT_FIRSTS[k]):
				need[k] = true
		_oldest_of = _scan(sim, need)
	return str(_oldest_of.get(kind, [0, ""])[1])


## `need`: the kinds still unmarked (homes are skipped once neither the
## founding nor the first home is wanted).
static func _scan(sim, need: Dictionary) -> Dictionary:
	var best := {}  # kind -> [built, key]
	var lots: Dictionary = sim.lots
	var homes := need.has("any") or need.has("home")
	for k in sim.buildings:
		var b: Dictionary = sim.buildings[k]
		var home := int(b.zone) == ZoneMap.Zone.RESIDENTIAL
		if (home and not homes) or not lots.has(k):
			continue
		var built := int(b.built)
		var kinds := ["any"]
		if home:
			kinds.append("home")
		else:
			var t := BuildingTypes.type_of(b)
			if t == "shop":
				kinds.append("store")
			elif t == "mixed_use":
				kinds.append("store")
				kinds.append("mixed_use")
			elif t == "office" or t == "factory":
				kinds.append(t)
		for kind in kinds:
			var cur = best.get(kind)
			if cur == null or built < int(cur[0]) or (built == int(cur[0]) and k < str(cur[1])):
				best[kind] = [built, k]
	best["_done"] = [0, ""]
	return best


func _lot_first(sim, kind: String) -> Dictionary:
	var k := _oldest(sim, kind)
	if k == "":
		return {}
	var out := _lot_spot(sim, k)
	var b: Dictionary = sim.buildings[k]
	out.key = k
	out.year = Families.calendar(Seasons.year(int(b.built) + sim.calendar_offset))
	out.name = _named(sim, "lot:" + k, Families.home_name(b) if int(b.zone) == ZoneMap.Zone.RESIDENTIAL
		else "The " + BuildingTypes.name_of(b).to_lower())
	return out


## The first hub in a dictionary of {pos, dir} hubs that passes `test`.
func _first_of(hubs: Dictionary, test: Callable, name_field: String) -> Dictionary:
	var ids := hubs.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = hubs[id]
		if not test.call(h) or not h.has("pos"):
			continue
		var dir: Vector3 = h.get("dir", Vector3.FORWARD)
		var out := _spot(h.pos, dir, 6.0)
		if name_field != "":
			out.name = str(h.get(name_field, ""))
		return out
	return {}


func _named(sim, ref: String, plain: String) -> String:
	var n: String = sim.families.name_of(ref)
	return n if n != "" else plain


## On the grass strip in front of a lot, to one side of its front walk,
## facing the street.
func _lot_spot(sim, key: String) -> Dictionary:
	var lot: Dictionary = sim.lots[key]
	var toward: Vector3 = -lot.normal
	var along: Vector3 = lot.dir
	var p: Vector3 = lot.front + toward * maxf(float(lot.to_curb) - RoadStyle.CURB_WIDTH - RoadStyle.PARKWAY_WIDTH * 0.5, 0.5) \
		+ along * minf(float(lot.get("width", 12.0)) * 0.3, 5.0)
	return {"pos": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)], "face": [snappedf(toward.x, 0.001), snappedf(toward.z, 0.001)]}


## `ahead` metres in front of a hub that faces the street along `dir`.
static func _spot(pos: Vector3, dir: Vector3, ahead: float) -> Dictionary:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	var p := pos + d * ahead + side * 4.0
	return {"pos": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)], "face": [snappedf(d.x, 0.001), snappedf(d.z, 0.001)]}


## Beside a farm lane where it meets the road.
static func _farm_spot(f: Dictionary) -> Dictionary:
	var drive: Array = f.get("drive", [])
	if drive.size() < 2:
		return _spot(f.pos, f.dir, 12.0)
	var end: Vector3 = drive[-1]
	var back: Vector3 = (drive[-2] - end).normalized()
	var side := Vector3(-back.z, 0.0, back.x)
	var p: Vector3 = end + back * 9.0 + side * 5.0
	return {"pos": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)], "face": [snappedf(-back.x, 0.001), snappedf(-back.z, 0.001)]}


## On the corner of a junction, in the widest gap between its roads.
static func _corner_spot(sim, node: int) -> Dictionary:
	var at: Vector3 = sim.network.nodes[node]
	var angles := []
	var widest := 0.0
	for seg in sim.network.segments_at(node):
		var pts: PackedVector3Array = sim.network.sample_segment(seg)
		var far: Vector3 = pts[1] if pts[0].distance_to(at) < pts[-1].distance_to(at) else pts[-2]
		angles.append(atan2(far.z - at.z, far.x - at.x))
		widest = maxf(widest, RoadStyle.right_of_way_half(sim.network.segments[seg].type))
	angles.sort()
	var gap := -1.0
	var mid := 0.0
	for i in angles.size():
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		if b - a > gap:
			gap = b - a
			mid = (a + b) * 0.5
	var d := Vector3(cos(mid), 0.0, sin(mid))
	var p := at + d * (widest + 3.0) * 1.42
	return {"pos": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)], "face": [snappedf(-d.x, 0.001), snappedf(-d.z, 0.001)]}


## A marker's words with the town's name in.
static func filled(text: String, town: String) -> String:
	return text.replace("{town}", town if town != "" else "Our Town")


func to_dict() -> Dictionary:
	return {"markers": markers, "next": next_id}


func from_dict(d: Dictionary) -> void:
	markers.clear()
	seen.clear()
	for m in d.get("markers", []):
		var out := {"id": int(m.id), "key": str(m.key), "title": str(m.title), "text": str(m.text),
			"year": int(m.year), "pos": [float(m.pos[0]), float(m.pos[1])],
			"face": [float(m.face[0]), float(m.face[1])], "kind": str(m.get("kind", "state"))}
		markers.append(out)
		seen[out.key] = out.id
	next_id = int(d.get("next", markers.size() + 1))
	version += 1
	changed.emit()
