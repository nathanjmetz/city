class_name Airports
extends RefCounted
## Airports the way Brawn asked: the player places a grass strip on open
## land and its manager runs it like a small business. Crop dusters spray
## the farms around it and townspeople keep their planes there. When it pays
## and the land allows, the manager paves it, and in time it can become a
## regional airport and then an international one. It only ever grows into
## the land right around it.
##
## Every size takes the land real FAA design rules ask for (Advisory
## Circular 150/5300-13B): the runway, its object free area, the building
## area beside it, and a runway protection zone off each end where nothing
## may be built (farming is fine there, as at real airports). The placing
## tool shows the land every size would need, so a new player can see
## whether there's room to grow.
##
## Every plane is a real trip: it taxis, takes off into the wind, flies
## somewhere for a reason (a field to spray, a town to visit), and comes
## back to land and park. Planes only leave at the edge of the map, flying
## on to a real town in the region.

signal changed

const FT := 0.3048
## Seconds of flying per tick (the same real-time scale as cars).
const DT := TrafficSim.DT
## The longest access road from the hangars out to a public road.
const MAX_DRIVE := 250.0
## The protection zone starts this far past the runway end (FAA: 200 ft
## beyond the end of the usable runway).
const RPZ_GAP := 200.0 * FT
## Sizes, smallest first. Lengths in feet as the FAA gives them; `side` is
## the building area beside the runway in metres (length, depth).
## Runway lengths follow AC 150/5325-4B for the planes each one serves.
const TIERS := [
	{"key": "grass", "name": "Grass strip", "runway": 2500.0, "width": 120.0, "surface": "turf",
		"rofa": 250.0, "beyond": 240.0, "rpz_len": 1000.0, "rpz_in": 250.0, "rpz_out": 450.0,
		"side": Vector2(150, 70), "planes": 8, "code": "A-I (small)",
		"serves": "crop dusters and small private planes"},
	{"key": "paved", "name": "Paved airfield", "runway": 3800.0, "width": 75.0, "surface": "asphalt",
		"rofa": 500.0, "beyond": 300.0, "rpz_len": 1000.0, "rpz_in": 500.0, "rpz_out": 700.0,
		"side": Vector2(320, 140), "planes": 30, "code": "B-II (small)",
		"serves": "business twins, charter and flight training"},
	{"key": "regional", "name": "Regional airport", "runway": 6500.0, "width": 150.0, "surface": "asphalt",
		"rofa": 800.0, "beyond": 1000.0, "rpz_len": 1700.0, "rpz_in": 500.0, "rpz_out": 1010.0,
		"side": Vector2(900, 380), "planes": 80, "code": "C-III",
		"serves": "regional jets, airline flights and air cargo"},
	{"key": "international", "name": "International airport", "runway": 10000.0, "width": 150.0,
		"surface": "concrete", "rofa": 800.0, "beyond": 1000.0, "rpz_len": 2500.0, "rpz_in": 1000.0,
		"rpz_out": 1750.0, "side": Vector2(2000, 800), "planes": 250, "code": "D-V",
		"serves": "wide-body jets, overseas flights and cargo hubs"},
]
## Extra end-to-end runway grade that grading can take out (a 4% rise over
## a grass strip is about 30 m of cut and fill: a big but ordinary job).
const GRADE_CUT := 0.02
## The tiers built so far; the rest come in later steps.
const MAX_TIER := 1
## A town's airport grows as far as regional. An international airport is a
## regional asset on open land, run by its own board with every town paying
## in (Brawn, 2026-10-23), so it isn't one of a town airport's sizes.
const TOWN_TIERS := 3
## Wind most often blows from the south-west in southern Indiana, so planes
## take off and land heading into it. Compass degrees it blows from.
const WIND_FROM := 220.0
## Real towns around Petersburg, Indiana: [name, compass bearing, km].
const TOWNS := [["Vincennes", 300.0, 30.0], ["Washington", 20.0, 22.0], ["Jasper", 120.0, 35.0],
	["Evansville", 205.0, 70.0], ["Princeton", 255.0, 35.0], ["Bloomington", 45.0, 110.0],
	["Indianapolis", 30.0, 170.0], ["Louisville", 110.0, 150.0]]
## Plane types: real models, wingspan and length in metres, cruise m/s.
const PLANES := {
	"duster": {"name": "Air Tractor AT-502B", "role": "Crop duster", "span": 15.8, "length": 10.2,
		"cruise": 60.0, "roll": 380.0, "color": Color(0.95, 0.78, 0.12), "trim": Color(0.15, 0.15, 0.16)},
	"cub": {"name": "Piper J-3 Cub", "role": "Private plane", "span": 10.7, "length": 6.8,
		"cruise": 33.0, "roll": 220.0, "color": Color(0.98, 0.84, 0.25), "trim": Color(0.12, 0.12, 0.12)},
	"cessna": {"name": "Cessna 172 Skyhawk", "role": "Private plane", "span": 11.0, "length": 8.3,
		"cruise": 55.0, "roll": 290.0, "color": Color(0.95, 0.95, 0.94), "trim": Color(0.16, 0.3, 0.6)},
	"cherokee": {"name": "Piper Cherokee", "role": "Private plane", "span": 9.1, "length": 7.3,
		"cruise": 55.0, "roll": 300.0, "color": Color(0.95, 0.94, 0.9), "trim": Color(0.7, 0.16, 0.14)},
	"bonanza": {"name": "Beechcraft Bonanza", "role": "Private plane", "span": 10.2, "length": 8.4,
		"cruise": 75.0, "roll": 330.0, "color": Color(0.93, 0.93, 0.95), "trim": Color(0.55, 0.42, 0.18)},
}
const PRIVATE_TYPES := ["cessna", "cherokee", "cub", "bonanza", "cessna"]
## Where new planes come from: the factory towns they're flown in from.
const FACTORIES := {"duster": "Olney, Texas", "cub": "Lock Haven, Pennsylvania",
	"cessna": "Wichita, Kansas", "cherokee": "Vero Beach, Florida", "bonanza": "Wichita, Kansas"}
const FIRST := ["Dale", "Ron", "Linda", "Gary", "Carol", "Dave", "Janet", "Larry", "Sue", "Mike",
	"Barb", "Tom", "Deb", "Rick", "Pam", "Jim"]
const LAST := ["Hoffman", "Schroeder", "Miller", "Kessler", "Bauer", "Lindgren", "Wagner", "Yoder",
	"Fischer", "Heidt", "Brenneman", "Sutton", "McCoy", "Overbeck", "Fuhrman", "Graber"]
## Ticks between plane checks, and in a game month (a game day).
const CHECK_EVERY := 10
const MONTH := 24 * 60
## Planes fly from this far around when crop dusting, metres.
const DUSTING_REACH := 6000.0
## Planes in the air leave the map this far from the field.
const EXIT := 5000.0
## Final approach: planes line up this far out (a short-field GA final).
const FINAL := 1500.0

## Airports: id -> {pos, dir (runway heading, unit), side (+1 or -1: which
## side its buildings are on), tier, drive, bank, manager: {name, ambition,
## caution}, name, ledger: {rent, dusting, fees}, last_net, founded, idle}
var sites := {}
## Planes: id -> {ap, type, tail, role ("duster", "private", "visitor",
## "sold"), spot, state ("parked", "flying", "away"), next (tick), town,
## flight: {} or {kind, start, end, ...}}
var planes := {}
var reserves: Reserves
var _next_id := 1
var _next_plane := 1
## Farms each airport sprays next, in turn (not saved: any order is fair).
var _turn := {}
## The selection panel's room-to-grow lines: id -> [tick, rows] (not saved).
var _room := {}


func clear() -> void:
	sites.clear()
	planes.clear()
	_next_id = 1
	_next_plane = 1
	changed.emit()


# --- Geometry -----------------------------------------------------------------

static func tier(t: int) -> Dictionary:
	return TIERS[clampi(t, 0, TIERS.size() - 1)]


static func right(a: Dictionary) -> Vector3:
	return Vector3(-a.dir.z, 0.0, a.dir.x)


## A point in the airport's own frame: u along the runway, v across it.
static func at(a: Dictionary, u: float, v: float) -> Vector3:
	var p: Vector3 = a.pos + a.dir * u + right(a) * v
	return Vector3(p.x, 0.0, p.z)


static func local(a: Dictionary, p: Vector3) -> Vector2:
	var d: Vector3 = p - a.pos
	return Vector2(d.x * a.dir.x + d.z * a.dir.z, d.dot(right(a)))


static func _rect(a: Dictionary, u0: float, u1: float, v0: float, v1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
		var p := at(a, q.x, q.y)
		out.append(Vector2(p.x, p.z))
	return out


## Half the runway's length and the object free area's half width, metres.
static func half_len(t: int) -> float:
	return tier(t).runway * FT * 0.5


## The runway and the clear ground around it (object free area).
static func field(a: Dictionary, t: int) -> PackedVector2Array:
	var k := tier(t)
	var u: float = half_len(t) + k.beyond * FT
	return _rect(a, -u, u, -k.rofa * FT * 0.5, k.rofa * FT * 0.5)


## The building area beside the runway: hangars, apron, later terminals.
static func side_area(a: Dictionary, t: int) -> PackedVector2Array:
	var k := tier(t)
	var v0: float = k.rofa * FT * 0.5
	var v1: float = v0 + k.side.y
	return _rect(a, -k.side.x * 0.5, k.side.x * 0.5, minf(v0 * a.side, v1 * a.side), maxf(v0 * a.side, v1 * a.side))


## The runway protection zone off one end (end = +1 or -1): a trapezoid
## widening away from the runway.
static func rpz(a: Dictionary, t: int, end: int) -> PackedVector2Array:
	var k := tier(t)
	var u0 := (half_len(t) + RPZ_GAP) * end
	var u1: float = u0 + k.rpz_len * FT * end
	var out := PackedVector2Array()
	for q in [Vector2(u0, -k.rpz_in * FT * 0.5), Vector2(u1, -k.rpz_out * FT * 0.5),
			Vector2(u1, k.rpz_out * FT * 0.5), Vector2(u0, k.rpz_in * FT * 0.5)]:
		var p := at(a, q.x, q.y)
		out.append(Vector2(p.x, p.z))
	return out


## The land the airport owns at a size.
static func owned(a: Dictionary, t: int) -> Array:
	return [field(a, t), side_area(a, t)]


static func _in_owned(a: Dictionary, t: int, q: Vector2) -> bool:
	var k := tier(t)
	if absf(q.x) <= half_len(t) + k.beyond * FT and absf(q.y) <= k.rofa * FT * 0.5:
		return true
	var v0: float = k.rofa * FT * 0.5
	return absf(q.x) <= k.side.x * 0.5 and q.y * a.side >= v0 and q.y * a.side <= v0 + k.side.y


static func _in_rpz(t: int, q: Vector2) -> bool:
	var k := tier(t)
	var d := absf(q.x) - half_len(t) - RPZ_GAP
	var len: float = k.rpz_len * FT
	if d < 0.0 or d > len:
		return false
	return absf(q.y) <= lerpf(k.rpz_in, k.rpz_out, d / len) * FT * 0.5


## The airport that owns this point (its current size), or -1.
func site_at(p: Vector3) -> int:
	for id in sites:
		if _in_owned(sites[id], sites[id].tier, local(sites[id], p)):
			return id
	return -1


func owns(p: Vector3) -> bool:
	return site_at(p) != -1


## True on owned land or in a protection zone: nothing gets built there.
func covers(p: Vector3) -> bool:
	for id in sites:
		var a: Dictionary = sites[id]
		var q := local(a, p)
		if _in_owned(a, a.tier, q) or _in_rpz(a.tier, q):
			return true
	return false


## The gate where the access road leaves the building area.
static func gate(a: Dictionary, t: int) -> Vector3:
	var k := tier(t)
	return at(a, 0.0, (k.rofa * FT * 0.5 + k.side.y) * a.side)


## The access road from the gate to the nearest road, or [].
static func make_drive(network: RoadNetwork, a: Dictionary, t: int) -> Array:
	var g := gate(a, t)
	var near := network.find_segment_near(g, MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	var out_dir: Vector3 = right(a) * a.side
	return Farms.make_drive(g - out_dir * Farms.FARMHOUSE_SIZE.y * 0.5, out_dir, near.point)


## Tie-down spot i on the apron, in front of the hangars.
static func spot(a: Dictionary, i: int) -> Vector3:
	var k := tier(a.tier)
	var per := maxi(1, int((k.side.x - 70.0) / 15.0))
	var row := i / per
	return at(a, -k.side.x * 0.5 + 14.0 + (i % per) * 15.0, (k.rofa * FT * 0.5 + 14.0 + row * 18.0) * a.side)


## Runway number at each end, from its compass heading: "9/27".
static func runway_name(a: Dictionary) -> String:
	var hdg := fposmod(rad_to_deg(atan2(a.dir.x, -a.dir.z)), 360.0)
	var n1 := posmod(roundi(hdg / 10.0) - 1, 36) + 1
	var n2 := posmod(n1 + 17, 36) + 1
	return "%d/%d" % [mini(n1, n2), maxi(n1, n2)]


## Heading from compass degrees (north is -z, east +x).
static func bearing_dir(deg: float) -> Vector3:
	return Vector3(sin(deg_to_rad(deg)), 0.0, -cos(deg_to_rad(deg)))


## The direction planes take off and land: into the wind.
static func takeoff_dir(a: Dictionary) -> Vector3:
	return a.dir if a.dir.dot(bearing_dir(WIND_FROM)) >= 0.0 else -a.dir


# --- Placing and room to grow ---------------------------------------------------

## What's in the way of an airport of size t here: counts by kind ("roads",
## "homes", "shops", "factories", "service buildings", "farmyards",
## "companies", "airports", "reserved land"). `skip` is the airport's own id.
## `corr` is RoadWins.corridors of the network (pass it in to save time).
func blockers(sim: CitySim, a: Dictionary, t: int, corr: Array, skip := -1) -> Dictionary:
	var out := {}
	var add := func(kind: String): out[kind] = out.get(kind, 0) + 1
	var land := owned(a, t)
	var clear := land + [rpz(a, t, 1), rpz(a, t, -1)]
	var box := Rect2(clear[0][0], Vector2.ZERO)
	for poly in clear:
		for p in poly:
			box = box.expand(p)
	for c in corr:
		if not c.bounds.intersects(box):
			continue
		for poly in land:
			if RoadWins.hits([c], poly):
				add.call("roads")
				break
	var names := {ZoneMap.Zone.RESIDENTIAL: "homes", ZoneMap.Zone.COMMERCIAL: "shops", ZoneMap.Zone.INDUSTRIAL: "factories"}
	for key in sim.buildings:
		if not sim.lots.has(key) or not box.has_point(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z)):
			continue
		if _hits_any(clear, sim.lots[key].corners):
			add.call(names.get(int(sim.buildings[key].zone), "buildings"))
	for id in sim.services.buildings:
		if _hits_any(clear, sim.services.footprint(id)):
			add.call("service buildings")
	for id in sim.farms.farms:
		if _hits_any(clear, sim.farms._yard(sim.farms.farms[id])):
			add.call("farmyards")
	for id in sim.industry.sites:
		if _hits_any(clear, sim.industry._yard(sim.industry.sites[id])):
			add.call("companies")
	for id in sim.warehouses.buildings:
		if _hits_any(clear, sim.warehouses.footprint(id)):
			add.call("warehouses")
	for id in sim.hubs.hubs:
		var h: Dictionary = sim.hubs.hubs[id]
		for c in h.cells:
			var m: Vector3 = sim.hubs.cell_center(h, c)
			if box.has_point(Vector2(m.x, m.z)) and _point_in_any(clear, Vector2(m.x, m.z)):
				add.call({"landfill": "landfills", "cemetery": "cemeteries"}.get(h.kind, "recycling centers"))
				break
	for id in sim.mail.offices:
		var h: Dictionary = sim.mail.offices[id]
		for c in h.cells:
			var m: Vector3 = CivicHubs.cell_center(h, c)
			if box.has_point(Vector2(m.x, m.z)) and _point_in_any(clear, Vector2(m.x, m.z)):
				add.call("post offices")
				break
	for id in sim.power.sites:
		var s: Dictionary = sim.power.sites[id]
		var hit := _hits_any(clear, sim.power.yard(s))
		for c in s.cells:
			hit = hit or _hits_any(clear, Power.cell_corners(s, c))
		if hit:
			add.call("power plants")
	var water: WaterUtility = sim.services.water
	for id in water.utilities:
		if not sim.services.buildings.has(id):
			continue
		for w in water.utilities[id].works:
			var c: Vector2i = w[1]
			if c != Vector2i.ZERO and c.x > -99 \
					and _hits_any(clear, WaterUtility.cell_corners(sim.services.buildings[id], c)):
				add.call("water works")
				break
	for id in sim.banks.banks:
		var bk: Dictionary = sim.banks.banks[id]
		for blk in bk.blocks:
			if _hits_any(clear, Banks.block_corners(bk, blk.c)):
				add.call("banks")
				break
	for id in sim.parks.sites:
		if _hits_any(clear, sim.parks.footprint(id)):
			add.call("parks")
	for id in sim.education.campuses:
		var c: Dictionary = sim.education.campuses[id]
		for blk in c.blocks:
			if _hits_any(clear, Education.block_corners(c, blk.c)):
				add.call("campuses")
				break
	# Rail yards and track, phone company sites and big factories: sampled
	# every 25 m over the runway's clear area and the building area.
	var others := {"rail": sim.rail, "telecom": sim.telecom, "big factories": sim.big}
	for kind in others.keys():
		var o = others[kind]
		var hit := false
		for poly in clear:
			var r := Rect2(poly[0], Vector2.ZERO)
			for p in poly:
				r = r.expand(p)
			var x := r.position.x
			while x <= r.end.x and not hit:
				var y := r.position.y
				while y <= r.end.y and not hit:
					var q := Vector2(x, y)
					hit = Geometry2D.is_point_in_polygon(q, poly) and o.covers(Vector3(q.x, 0.0, q.y))
					y += 25.0
				x += 25.0
			if hit:
				break
		if hit:
			add.call(kind)
	for id in sites:
		if id == skip:
			continue
		var o: Dictionary = sites[id]
		for poly in owned(o, o.tier):
			if _hits_any(clear, poly):
				add.call("airports")
				break
	out.merge(ground(sim.terrain_offset, a, t))
	if reserves != null:
		for o in reserves.outlines:
			if o.kind != "airport" and o.kind != "" and _hits_any(land, o.points):
				add.call("reserved land")
	return out


## What the land itself has against an airport of size t here: a river or
## lake on its land, ground too steep to build on, or a runway that would
## climb so much end to end that no sensible earthwork could grade it to
## the FAA's limit (AC 150/5300-13B: 2% for small planes, 1.5% for
## airliners, after grading). Cut and fill takes care of up to GRADE_CUT
## more.
static func ground(offset: Vector2, a: Dictionary, t: int) -> Dictionary:
	var out := {}
	var k := tier(t)
	var step := 30.0
	var areas := [[half_len(t) + k.beyond * FT, 0.0, k.rofa * FT * 0.5],
		[k.side.x * 0.5, (k.rofa * FT * 0.5 + k.side.y * 0.5) * a.side, k.side.y * 0.5]]
	for area in areas:
		var nu := ceili(area[0] * 2.0 / step)
		var nv := ceili(area[2] * 2.0 / step)
		for i in nu + 1:
			for j in nv + 1:
				var p := at(a, -area[0] + i * area[0] * 2.0 / nu, area[1] - area[2] + j * area[2] * 2.0 / nv)
				var x: float = p.x + offset.x
				var z: float = p.z + offset.y
				if Terrain.water(x, z) > 0.2:
					out["water"] = 1
				elif Terrain.slope(x, z) > Terrain.MAX_BUILD_SLOPE:
					out["steep ground"] = 1
	var e0 := at(a, -half_len(t), 0.0)
	var e1 := at(a, half_len(t), 0.0)
	var rise := absf(Terrain.base(e1.x + offset.x, e1.z + offset.y) - Terrain.base(e0.x + offset.x, e0.z + offset.y))
	if rise / (half_len(t) * 2.0) > (0.02 if t < 2 else 0.015) + GRADE_CUT:
		out["steep ground"] = 1
	return out


static func _hits_any(polys: Array, poly: PackedVector2Array) -> bool:
	for p in polys:
		if not Geometry2D.intersect_polygons(p, poly).is_empty():
			return true
	return false


static func _point_in_any(polys: Array, q: Vector2) -> bool:
	for p in polys:
		if Geometry2D.is_point_in_polygon(q, p):
			return true
	return false


## "3 homes, a road" from blocker counts.
static func describe_blockers(b: Dictionary) -> String:
	var one := {"roads": "a road", "homes": "a home", "shops": "a shop", "factories": "a factory",
		"service buildings": "a service building", "farmyards": "a farmyard", "companies": "a company yard",
		"airports": "another airport", "water": "a river or lake", "steep ground": "ground too steep to grade",
		"warehouses": "a warehouse", "landfills": "a landfill", "recycling centers": "a recycling center",
		"cemeteries": "a cemetery", "post offices": "the post office",
		"power plants": "a power plant", "banks": "a bank", "rail": "a railroad",
		"telecom": "a phone company site", "big factories": "a big factory", "water works": "the water works", "parks": "a park", "campuses": "a campus",
		"reserved land": "land reserved for something else"}
	var parts := []
	var keys := b.keys()
	keys.sort()
	for k in keys:
		parts.append(one.get(k, k) if b[k] == 1 or k in ["reserved land", "water", "steep ground"] else "%d %s" % [b[k], k])
	return ", ".join(parts)


## Why an airport can't open here, or "".
func problem(sim: CitySim, a: Dictionary, corr: Array) -> String:
	var b := blockers(sim, a, 0, corr)
	if not b.is_empty():
		return "In the way: %s." % describe_blockers(b)
	if make_drive(sim.network, a, 0).is_empty():
		return "Needs a road within %d m of its hangars." % int(MAX_DRIVE)
	return ""


## The airport a placing command describes.
static func from_cmd(cmd: Dictionary) -> Dictionary:
	var dir := Vector3(float(cmd.dir[0]), 0.0, float(cmd.dir[1])).normalized()
	return {"pos": Vector3(float(cmd.pos[0]), 0.0, float(cmd.pos[1])), "dir": dir,
		"side": 1 if int(cmd.get("side", 1)) >= 0 else -1, "tier": 0}


## Player commands: place_airport {pos, dir, side}, remove_airport {id}.
func command(sim: CitySim, cmd: Dictionary) -> bool:
	match cmd.type:
		"place_airport":
			var a := from_cmd(cmd)
			if a.dir.length() < 0.5 or Balance.AIRPORT_COST > sim.economy.money:
				return false
			if problem(sim, a, RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)) != "":
				return false
			var id := _next_id
			_next_id += 1
			var h := hash([sim.city_seed, id, "manager"])
			var last: String = LAST[absi(h) % LAST.size()]
			a.merge({"drive": make_drive(sim.network, a, 0), "bank": 0, "last_net": 0,
				"ledger": {"rent": 0.0, "dusting": 0.0, "fees": 0.0},
				"manager": {"name": "%s %s" % [FIRST[absi(h / 7) % FIRST.size()], last],
					"ambition": 0.35 + 0.6 * ((absi(h / 131) % 100) / 100.0),
					"caution": 0.2 + 0.6 * ((absi(h / 1733) % 100) / 100.0)},
				"name": "%s Field" % last, "founded": sim.tick_count, "idle": ""})
			sites[id] = a
			take_fields(sim, id)
			sim.economy.money -= Balance.AIRPORT_COST
			changed.emit()
			return true
		"remove_airport":
			var id := int(cmd.id)
			if not sites.has(id):
				return false
			_close(id)
			return true
	return false


## Farmers sell the airport the fields on its land.
func take_fields(sim: CitySim, id: int) -> void:
	var a: Dictionary = sites[id]
	var lost := false
	for fid in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[fid]
		for c in f.cells.duplicate():
			if _in_owned(a, a.tier, local(a, Farms.cell_center(f, c))):
				f.cells.erase(c)
				lost = true
	if lost:
		sim.farms_changed.emit()


func _close(id: int) -> void:
	sites.erase(id)
	# Its planes fly off to other airfields; ones in the air carry on and go.
	for pid in planes.keys():
		if planes[pid].ap == id:
			planes.erase(pid)
	changed.emit()


## The road wins: a road across an airport's land closes it (paid back), and
## a road that cuts its access road reroutes it. Protection zones may hold
## roads.
func road_wins(sim: CitySim, corr: Array, lane_end: float) -> void:
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = sites[id]
		var hit := false
		for poly in owned(a, a.tier):
			hit = hit or RoadWins.hits(corr, poly)
		if hit:
			sim.economy.money += Balance.AIRPORT_COST
			_close(id)
		elif RoadWins.cuts(corr, a.drive, lane_end) or a.drive.is_empty():
			a.drive = make_drive(sim.network, a, a.tier)


# --- Business -----------------------------------------------------------------

func jobs() -> int:
	var n := 0
	for id in sites:
		n += Balance.AIRPORT_JOBS[sites[id].tier]
	return n


func taxable_value() -> float:
	var v := 0.0
	for id in sites:
		v += Balance.AIRPORT_VALUE[sites[id].tier]
	return v


## Planes based at an airport (parked, flying or away on a trip).
func based(id: int, role := "") -> Array:
	var out := []
	var ids := planes.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = planes[pid]
		if p.ap == id and p.role in ["duster", "private"] and (role == "" or p.role == role):
			out.append(pid)
	return out


## Farmland within crop dusting reach, acres.
static func acres_near(sim: CitySim, a: Dictionary) -> float:
	var acres := 0.0
	for fid in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[fid]
		if f.pos.distance_to(a.pos) <= DUSTING_REACH:
			acres += f.cells.size() * Farms.ACRES_PER_CELL
	return acres


## How many planes of each kind the manager wants based here.
func wanted(sim: CitySim, id: int) -> Dictionary:
	var a: Dictionary = sites[id]
	var cap: int = tier(a.tier).planes
	var dusters := mini(ceili(acres_near(sim, a) / Balance.AIRPORT_ACRES_PER_DUSTER), 3 + a.tier * 2)
	var private := int(sim.stats.population / Balance.AIRPORT_PEOPLE_PER_PLANE) + 1
	dusters = mini(dusters, cap)
	return {"duster": dusters, "private": mini(private, cap - dusters)}


func tick(sim: CitySim) -> void:
	if sites.is_empty():
		return
	if sim.tick_count % CHECK_EVERY == 0:
		_fly(sim)
	if sim.tick_count % MONTH == 0:
		_month(sim)


## Once a month the manager settles the books, buys or sells planes and
## decides whether to grow.
func _month(sim: CitySim) -> void:
	var ids := sites.keys()
	ids.sort()
	var corr := []
	for id in ids:
		var a: Dictionary = sites[id]
		var n := based(id).size()
		a.ledger.rent += n * Balance.AIRPORT_HANGAR_RENT
		var net := roundi(a.ledger.rent + a.ledger.dusting + a.ledger.fees) - int(Balance.AIRPORT_UPKEEP[a.tier])
		a.last_net = net
		a.bank += net
		a.ledger = {"rent": 0.0, "dusting": 0.0, "fees": 0.0}
		# Planes: buy what the town and farms want (flown in from the
		# factory), sell one that's sat unwanted.
		var want := wanted(sim, id)
		for role in ["duster", "private"]:
			var have := based(id, role)
			if have.size() < want[role]:
				_deliver(sim, id, role)
			elif have.size() > want[role] + 1:
				for pid in have:
					if planes[pid].state == "parked":
						planes[pid].role = "sold"
						planes[pid].next = sim.tick_count
						break
		# Growing: the next size needs its savings and clear land around.
		# The player's word counts: "grow" pushes, "hold" stops it.
		var stance: String = sim.permits.guidance("airport", id).stance
		var push: float = {"grow": 0.5, "hold": 0.0}.get(stance, 1.0)
		a.idle = ""
		if stance == "hold":
			a.idle = "Holding off on growing, as you asked."
		elif a.tier < MAX_TIER and a.tier + 1 < TOWN_TIERS:
			var cost: int = Balance.AIRPORT_UPGRADE[a.tier + 1]
			var busy := float(based(id).size()) / float(tier(a.tier).planes)
			if a.bank < cost:
				a.idle = "Saving for a %s: $%s of $%s." % [tier(a.tier + 1).name.to_lower(),
					CitySim.money_text(maxi(a.bank, 0)), CitySim.money_text(cost)]
			elif busy < 0.6 * (1.2 - a.manager.ambition) * push:
				a.idle = "Has the money to grow, but not enough planes need it yet."
			else:
				if corr.is_empty():
					corr = RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)
				var b := blockers(sim, a, a.tier + 1, corr, id)
				if b.is_empty():
					a.tier += 1
					a.bank -= cost
					a.drive = make_drive(sim.network, a, a.tier)
					take_fields(sim, id)
					changed.emit()
				else:
					a.idle = "Ready to build a %s, but its land isn't clear: %s." % [tier(a.tier + 1).name.to_lower(),
						describe_blockers(b)]


## A new plane is flown in from where it was built and parks here.
func _deliver(sim: CitySim, id: int, role: String) -> void:
	var a: Dictionary = sites[id]
	var spot_i := _free_spot(id)
	if spot_i < 0:
		return
	var h := absi(hash([sim.city_seed, _next_plane, "plane"]))
	var type: String = "duster" if role == "duster" else PRIVATE_TYPES[h % PRIVATE_TYPES.size()]
	var pid := _next_plane
	_next_plane += 1
	planes[pid] = {"ap": id, "type": type, "tail": _tail(h), "role": role, "spot": spot_i,
		"state": "parked", "next": 0, "town": FACTORIES[type], "flight": {}}
	_start(sim, pid, {"kind": "arrive", "town": FACTORIES[type], "bearing": _bearing_to(FACTORIES[type], h),
		"why": "Delivery flight, new from the factory in %s" % FACTORIES[type]})


static func _tail(h: int) -> String:
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	return "N%d%s%s" % [100 + h % 900, letters[(h / 900) % letters.length()], letters[(h / 20000) % letters.length()]]


func _bearing_to(town: String, h: int) -> float:
	for t in TOWNS:
		if t[0] == town:
			return t[1]
	return float(h % 360)


func _free_spot(id: int) -> int:
	var used := {}
	for pid in planes:
		if planes[pid].ap == id and planes[pid].state != "gone":
			used[planes[pid].spot] = true
	for i in tier(sites[id].tier).planes + 2:
		if not used.has(i):
			return i
	return -1


## Every few ticks: planes that landed park, planes due to leave go.
func _fly(sim: CitySim) -> void:
	var t := sim.tick_count
	var ids := planes.keys()
	ids.sort()
	var month := Seasons.month(t)
	for pid in ids:
		var p: Dictionary = planes[pid]
		if not sites.has(p.ap):
			planes.erase(pid)
			continue
		var a: Dictionary = sites[p.ap]
		var h := absi(hash([sim.city_seed, pid, t]))
		match p.state:
			"flying":
				if t < p.flight.end:
					continue
				var kind: String = p.flight.kind
				a.ledger.fees += Balance.AIRPORT_FEE_PER_FLIGHT
				if kind == "spray":
					a.ledger.dusting += float(p.flight.acres) * Balance.AIRPORT_DUSTING_PER_ACRE
				p.flight = {}
				if kind == "depart":
					if p.role in ["visitor", "sold"]:
						planes.erase(pid)  # gone on to its home field in the region
					else:
						p.state = "away"
						p.next = t + 900 + h % 2400
				else:
					p.state = "parked"
					p.next = t + (120 if p.role == "duster" else 600) + h % 600
			"away":
				if t >= p.next:
					_start(sim, pid, {"kind": "arrive", "town": p.town, "bearing": _bearing_to(p.town, h),
						"why": "Flying home from %s" % p.town})
			"parked":
				if t < p.next:
					continue
				match p.role:
					"duster":
						var job := _spray_job(sim, p.ap) if month >= 5 and month <= 9 else {}
						if job.is_empty():
							p.next = t + 600
						else:
							_start(sim, pid, job)
					"private":
						var town: Array = TOWNS[h % TOWNS.size()]
						p.town = town[0]
						_start(sim, pid, {"kind": "depart", "town": town[0], "bearing": town[1],
							"why": "Flying to %s for the day" % town[0]})
					"visitor":
						_start(sim, pid, {"kind": "depart", "town": p.town, "bearing": _bearing_to(p.town, h),
							"why": "Flying home to %s" % p.town})
					"sold":
						_start(sim, pid, {"kind": "depart", "town": "Ohio", "bearing": 75.0,
							"why": "Sold: delivering to its new owner in Ohio"})
	# Now and then a visitor from another town flies in for a while.
	if t % 240 == 0:
		var aids := sites.keys()
		aids.sort()
		for id in aids:
			var h := absi(hash([sim.city_seed, id, t, "visit"]))
			if h % 100 >= 8 + mini(int(sim.stats.population / 100), 30):
				continue
			var spot_i := _free_spot(id)
			if spot_i < 0:
				continue
			var town: Array = TOWNS[h % TOWNS.size()]
			var type: String = PRIVATE_TYPES[(h / 100) % PRIVATE_TYPES.size()]
			var pid := _next_plane
			_next_plane += 1
			planes[pid] = {"ap": id, "type": type, "tail": _tail(h), "role": "visitor", "spot": spot_i,
				"state": "parked", "next": 0, "town": town[0], "flight": {}}
			_start(sim, pid, {"kind": "arrive", "town": town[0], "bearing": town[1],
				"why": "Visiting from %s" % town[0]})


## A field to spray: the next farm in reach, in turn, with its fields.
func _spray_job(sim: CitySim, id: int) -> Dictionary:
	var a: Dictionary = sites[id]
	var farm_ids := []
	for fid in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[fid]
		if not f.cells.is_empty() and f.pos.distance_to(a.pos) <= DUSTING_REACH:
			farm_ids.append(fid)
	if farm_ids.is_empty():
		return {}
	farm_ids.sort()
	var n: int = _turn.get(id, 0)
	_turn[id] = n + 1
	var fid: int = farm_ids[n % farm_ids.size()]
	var f: Dictionary = sim.farms.farms[fid]
	# The fields' extent in the farm's frame: passes run along its rows.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in f.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	var mid := (lo + hi) * 0.5
	var center := Farms.cell_center(f, Vector2i(roundi(mid.x), roundi(mid.y)))
	center += Farms._right(f) * (mid.x - roundf(mid.x)) * Farms.CELL - f.dir * (mid.y - roundf(mid.y)) * Farms.CELL
	var length := (hi.x - lo.x + 1.0) * Farms.CELL
	var depth := (hi.y - lo.y + 1.0) * Farms.CELL
	var passes := clampi(ceili(depth / 18.0), 2, 8)
	var acres := float(f.cells.size()) * Farms.ACRES_PER_CELL * minf(1.0, passes * 18.0 / depth)
	return {"kind": "spray", "center": [center.x, center.z], "axis": [Farms._right(f).x, Farms._right(f).z],
		"across": [-f.dir.x, -f.dir.z], "length": length, "depth": passes * 18.0, "passes": float(passes),
		"acres": acres,
		"why": "Spraying %s on the %s farm" % ["fungicide" if f.crop == "corn" else "the soybeans", _farm_name(fid)]}


static func _farm_name(fid: int) -> String:
	return LAST[(fid * 5 + 3) % LAST.size()]


func _start(sim: CitySim, pid: int, flight: Dictionary) -> void:
	var p: Dictionary = planes[pid]
	flight.start = sim.tick_count
	var path := flight_path(sites[p.ap], p, flight)
	flight.end = sim.tick_count + ceili(path[1][-1] / DT) + 1
	p.flight = flight
	p.state = "flying"


# --- Flight paths -------------------------------------------------------------
# Worked out the same way from the same numbers everywhere, so only the
# flight's few parameters are saved and every copy flies the same path.

## [PackedVector3Array points, PackedFloat32Array seconds at each point].
static func flight_path(a: Dictionary, p: Dictionary, f: Dictionary) -> Array:
	var spec: Dictionary = PLANES[p.type]
	var pts := PackedVector3Array()
	var times := PackedFloat32Array()
	var add := func(q: Vector3, speed: float):
		if pts.is_empty():
			times.append(0.0)
		else:
			times.append(times[-1] + q.distance_to(pts[-1]) / maxf(speed, 1.0))
		pts.append(q)
	var td := takeoff_dir(a)
	var half := half_len(a.tier)
	var k := tier(a.tier)
	var taxi_v: float = (k.width * FT * 0.5 + 12.0) * a.side
	var threshold: Vector3 = a.pos - td * (half - 10.0)
	var stop: Vector3 = spot(a, p.spot)
	var taxi_line := func(q: Vector3) -> Vector3:
		var l := local(a, q)
		return at(a, l.x, taxi_v)
	var cruise: float = spec.cruise
	if f.kind in ["depart", "spray"]:
		add.call(stop, 0.0)
		add.call(taxi_line.call(stop), 5.0)
		add.call(taxi_line.call(threshold), 7.0)
		add.call(threshold, 4.0)
		var lift: Vector3 = threshold + td * float(spec.roll)
		add.call(lift + Vector3(0, 0.5, 0), 14.0)
		var climb: Vector3 = lift + td * 1500.0 + Vector3(0, 90, 0)
		add.call(climb, cruise * 0.7)
		if f.kind == "depart":
			var out := bearing_dir(f.bearing)
			add.call(climb + (td + out).normalized() * 900.0 + Vector3(0, 70, 0), cruise * 0.8)
			add.call(a.pos + out * 2500.0 + Vector3(0, 300, 0), cruise)
			add.call(a.pos + out * EXIT + Vector3(0, 450, 0), cruise)
			return [pts, times]
		# Crop dusting: low passes across the field, pulling up to turn.
		var c := Vector3(f.center[0], 0.0, f.center[1])
		var ax := Vector3(f.axis[0], 0.0, f.axis[1])
		var ac := Vector3(f.across[0], 0.0, f.across[1])
		var first: Vector3 = c - ac * f.depth * 0.5
		var flip := 1.0 if (first - ax * f.length * 0.5).distance_to(climb) < (first + ax * f.length * 0.5).distance_to(climb) else -1.0
		add.call(first - ax * flip * (f.length * 0.5 + 250.0) + Vector3(0, 60, 0), cruise)
		for i in int(f.passes):
			var lane: Vector3 = first + ac * (18.0 * i + 9.0)
			var s := -flip if i % 2 == 0 else flip
			add.call(lane - ax * s * (f.length * 0.5 + 40.0) + Vector3(0, 5, 0), cruise * 0.9)
			add.call(lane + ax * s * (f.length * 0.5) + Vector3(0, 4, 0), cruise * 0.9)
			add.call(lane + ax * s * (f.length * 0.5 + 90.0) + ac * 9.0 + Vector3(0, 35, 0), cruise * 0.7)
		var back: Vector3 = pts[-1]
		back.y = 0.0
		_approach(a, p, add, back, td, threshold, stop, taxi_line, cruise)
		return [pts, times]
	# Arriving from the region.
	var from := bearing_dir(f.bearing)
	add.call(a.pos + from * EXIT + Vector3(0, 450, 0), 0.0)
	_approach(a, p, add, a.pos + from * 2500.0, td, threshold, stop, taxi_line, cruise)
	return [pts, times]


## Join the pattern, fly final down a 3 degree glide path, land, roll out
## and taxi in to the plane's spot.
static func _approach(a: Dictionary, p: Dictionary, add: Callable, from: Vector3, td: Vector3,
		threshold: Vector3, stop: Vector3, taxi_line: Callable, cruise: float) -> void:
	var spec: Dictionary = PLANES[p.type]
	var side: Vector3 = right(a) * a.side
	add.call(Vector3(from.x, 300.0, from.z), cruise)
	# Downwind leg on the building side, then base, then a 2.5 km final.
	var final_start: Vector3 = threshold - td * FINAL
	add.call(threshold + td * 400.0 + side * 800.0 + Vector3(0, 300, 0), cruise)
	add.call(final_start + side * 800.0 + Vector3(0, 200, 0), cruise * 0.8)
	add.call(final_start + Vector3(0, FINAL * tan(deg_to_rad(3.0)) + 15.0, 0), cruise * 0.7)
	add.call(threshold + Vector3(0, 15, 0), cruise * 0.6)
	var touch: Vector3 = threshold + td * 120.0
	add.call(touch, cruise * 0.55)
	var rolled: Vector3 = touch + td * float(spec.roll)
	add.call(rolled, 14.0)
	add.call(taxi_line.call(rolled), 5.0)
	add.call(taxi_line.call(stop), 7.0)
	add.call(stop, 4.0)


## Where a plane is right now and the way it faces: [position, forward], or
## [] when it isn't in sight. `t` is in ticks and may be fractional.
static func pose(a: Dictionary, p: Dictionary, path: Array, t: float) -> Array:
	if p.state == "parked" or p.flight.is_empty():
		if p.state == "away":
			return []
		var s := spot(a, p.spot)
		return [s, -right(a) * a.side]
	var secs: float = (t - float(p.flight.start)) * DT
	var pts: PackedVector3Array = path[0]
	var times: PackedFloat32Array = path[1]
	if secs >= times[-1]:
		var last := pts.size() - 1
		return [pts[last], (pts[last] - pts[last - 1]).normalized()]
	var i := times.bsearch(secs, true)
	i = clampi(i, 1, pts.size() - 1)
	var span := maxf(times[i] - times[i - 1], 0.001)
	var w := clampf((secs - times[i - 1]) / span, 0.0, 1.0)
	var dir := pts[i] - pts[i - 1]
	# Ease the heading into the next leg over the last stretch of this one.
	if i + 1 < pts.size() and w > 0.7:
		dir = dir.normalized().slerp((pts[i + 1] - pts[i]).normalized(), (w - 0.7) / 0.6)
	if dir.length() < 0.001:
		dir = a.dir
	return [pts[i - 1].lerp(pts[i], w), dir.normalized()]


# --- The selection panel --------------------------------------------------------

## For Inspect: {title, kind, icon, ok, status, rows, problems}.
func describe(sim: CitySim, id: int) -> Dictionary:
	var a: Dictionary = sites[id]
	var k := tier(a.tier)
	var dusters := based(id, "duster").size()
	var private := based(id, "private").size()
	var rows := [
		["Manager", a.manager.name],
		["Runway %s" % runway_name(a), "%s ft %s (FAA %s)" % [CitySim.money_text(int(k.runway)), k.surface, k.code]],
		["Planes based", "%d crop duster%s, %d private" % [dusters, "" if dusters == 1 else "s", private]],
	]
	var aloft := []
	var ids := planes.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = planes[pid]
		if p.ap == id and p.state == "flying":
			aloft.append("%s %s: %s" % [PLANES[p.type].name, p.tail, p.flight.why])
	rows.append(["In the air", "Nobody" if aloft.is_empty() else str(aloft.size())])
	for line in aloft.slice(0, 4):
		rows.append(["", line])
	rows.append(["Profit last month", "%s$%s" % ["" if a.last_net >= 0 else "-", CitySim.money_text(absi(a.last_net))]])
	rows.append(["Manager's savings", "%s$%s" % ["" if a.bank >= 0 else "-", CitySim.money_text(absi(a.bank))]])
	rows.append(["Jobs", str(Balance.AIRPORT_JOBS[a.tier])])
	rows.append(["Property tax to town", "$%s / month" % CitySim.money_text(roundi(Balance.AIRPORT_VALUE[a.tier]
		* sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))])
	# Room to grow: each bigger size and whether its land is clear today
	# (worked out at most once a game hour; it's the slow part).
	var room: Array = _room.get(id, [-1000, []])
	if sim.tick_count - int(room[0]) >= 60 or room[0] > sim.tick_count:
		var corr := RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)
		var lines := []
		for t in range(a.tier + 1, TOWN_TIERS):
			var b := blockers(sim, a, t, corr, id)
			lines.append([TIERS[t].name, "Room to grow" if b.is_empty() else "Blocked: " + describe_blockers(b)])
		room = [sim.tick_count, lines]
		_room[id] = room
	rows.append_array(room[1])
	var problems := []
	if a.drive.is_empty():
		problems.append("No road within %d m of the hangars, so pilots can't get there." % int(MAX_DRIVE))
	var status := "Open: %s" % k.serves
	if a.idle != "":
		status = a.idle
	return {"title": a.name, "kind": k.name, "icon": "airport", "ok": problems.is_empty() and a.last_net >= 0,
		"status": status, "rows": rows, "problems": problems}


# --- Saving -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id in sites:
		var a: Dictionary = sites[id]
		var lane := []
		for q in a.drive:
			lane.append([q.x, q.z])
		out[str(id)] = {"pos": [a.pos.x, a.pos.z], "dir": [a.dir.x, a.dir.z], "side": a.side, "tier": a.tier,
			"drive": lane, "bank": a.bank, "last_net": a.last_net, "ledger": a.ledger.duplicate(),
			"manager": a.manager.duplicate(), "name": a.name, "founded": a.founded, "idle": a.idle}
	var pl := {}
	for pid in planes:
		pl[str(pid)] = planes[pid].duplicate(true)
	return {"sites": out, "planes": pl, "next_id": _next_id, "next_plane": _next_plane}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	planes.clear()
	_turn.clear()
	for k in d.get("sites", {}):
		var s: Dictionary = d.sites[k]
		var lane := []
		for q in s.get("drive", []):
			lane.append(Vector3(float(q[0]), 0.0, float(q[1])))
		var led: Dictionary = s.get("ledger", {})
		sites[int(k)] = {"pos": Vector3(float(s.pos[0]), 0.0, float(s.pos[1])),
			"dir": Vector3(float(s.dir[0]), 0.0, float(s.dir[1])).normalized(),
			"side": 1 if int(s.get("side", 1)) >= 0 else -1, "tier": int(s.get("tier", 0)), "drive": lane,
			"bank": int(s.get("bank", 0)), "last_net": int(s.get("last_net", 0)),
			"ledger": {"rent": float(led.get("rent", 0.0)), "dusting": float(led.get("dusting", 0.0)),
				"fees": float(led.get("fees", 0.0))},
			"manager": {"name": str(s.manager.name), "ambition": float(s.manager.ambition),
				"caution": float(s.manager.caution)},
			"name": str(s.get("name", "Airfield")), "founded": int(s.get("founded", 0)), "idle": str(s.get("idle", ""))}
	for k in d.get("planes", {}):
		var p: Dictionary = d.planes[k].duplicate(true)
		p.ap = int(p.ap)
		p.spot = int(p.spot)
		p.next = int(p.next)
		if not p.flight.is_empty():
			p.flight.start = int(p.flight.start)
			p.flight.end = int(p.flight.end)
		planes[int(k)] = p
	_next_id = int(d.get("next_id", 1))
	_next_plane = int(d.get("next_plane", 1))
	changed.emit()
