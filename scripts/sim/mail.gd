class_name Mail
extends RefCounted
## The post office and the mail, Best of CS pitch #10 as Brawn green-lit it
## (2026-10-22):
##   - The player places a post office. Its postmaster plans the delivery
##     routes alone: nobody clicks streets.
##   - Carriers drive real trips through traffic and stop at the mailboxes on
##     every street: mail trucks in town, right-hand-drive jeeps on rural
##     routes. Parcel vans serve the businesses. A mail truck brings the
##     day's mail in from the region before dawn and takes the outgoing mail
##     out in the evening. Nothing vanishes: every vehicle comes home.
##   - A busy town's post office grows a sorting room, then a sorting center,
##     only into free land directly next door (never a second site), and
##     roads always win.
##   - Boxed in by roads, it fills its block up to the sidewalk with lawn
##     and fenced carrier lot, never a building (Nathan, 2026-10-26: "when a
##     hub with leader is "trapped" inside a road area, it should nicely
##     fill in that area up to the edge (sidewalk) so that it looks like its
##     using its space well."): edge pieces, as CivicHubs keeps them.
##   - Good mail service makes a town a little happier and better for
##     business.
## Like every hub, it has a leader and a thick development tree (Brawn's
## standing rule), on the shared Agency model: the postmaster unlocks
## branches from what they can do (savings, schooling, nerve) and from the
## town and the neighbouring towns around it. The player's levers are the
## land, the funding, and their word to the postmaster (Permits guidance).
##
## Plain data stepped by the city, so every copy of the simulation agrees.
## Numbers live in Balance (MAIL_*).

## Office land comes in pieces this size (metres), three along the road and
## two deep to start: a small-town post office on about 0.6 acre.
const CELL := 20.0
const BASE := [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
## Service tool kind for the HUD (ServiceTool takes ints).
const TOOL_KIND := 110
const TICKS_PER_DAY := 24 * CitySim.TICKS_PER_HOUR
## A carrier looks this far from its last stop for the next street on its
## route; streets farther apart start a new route.
const ROUTE_REACH := 1200.0

## The development tree's words. `needs` is the node before it on the
## branch; numbers (cost, land, build time, thresholds) are in
## Balance.MAIL_TREE, and agency_tree() joins the two into Agency's shape.
## Every node gets a plain-words line for the info panel.
const TREE := {
	# Counter: what the front of the post office offers the town.
	"po_boxes": {"name": "24-hour PO box lobby", "branch": "Counter", "needs": "",
		"text": "Rows of brass PO boxes, open all night. Homes nearby like it."},
	"passports": {"name": "Passport acceptance", "branch": "Counter", "needs": "po_boxes",
		"text": "A trained clerk takes passport applications. Needs a schooled postmaster."},
	"kiosk": {"name": "Self-service kiosk", "branch": "Counter", "needs": "passports",
		"text": "Stamps and labels any hour. Needs a town that went to school."},
	"mural": {"name": "Lobby mural", "branch": "Counter", "needs": "po_boxes",
		"text": "A painted mural of the county, like the 1930s ones. Lifts the blocks around it."},
	# Delivery: who goes out and how.
	"cluster_boxes": {"name": "Cluster mailboxes", "branch": "Delivery", "needs": "",
		"text": "Neighborhood box units in bigger subdivisions: each route reaches more homes."},
	"more_vans": {"name": "Parcel van fleet", "branch": "Delivery", "needs": "",
		"text": "Two more parcel vans, and parcels go out on Sundays too."},
	"electric_fleet": {"name": "Electric delivery trucks", "branch": "Delivery", "needs": "more_vans",
		"text": "New electric carrier trucks. Cheaper to run; an ambitious, schooled postmaster pushes for them."},
	"parcel_lockers": {"name": "Parcel lockers at shops", "branch": "Delivery", "needs": "more_vans",
		"text": "Lockers by the busiest shops. Shoppers stop in, and businesses do a little better."},
	# Parcels: the parcel network (agreed with the Warehouses thread).
	"business_mail": {"name": "Business mail entry unit", "branch": "Parcels", "needs": "",
		"text": "A dock where factories drop off bulk mail and freight parcels."},
	"parcel_depot": {"name": "Parcel delivery depot", "branch": "Parcels", "needs": "more_vans",
		"text": "A depot next door with its own vans, for a town that orders a lot."},
	"parcel_ground_hub": {"name": "Parcel ground hub", "branch": "Parcels", "needs": "parcel_depot",
		"text": "A FedEx- or UPS-style ground hub. Needs a warehouse district or a big region around it."},
	# Processing: sorting, then serving the neighbours.
	"sorting_room": {"name": "Sorting room", "branch": "Processing", "needs": "",
		"text": "A letter-sorting machine in a new workroom out back, once the mail gets heavy."},
	"sorting_center": {"name": "Sorting center", "branch": "Processing", "needs": "sorting_room",
		"text": "A processing plant for a busy town, with a row of truck docks."},
	"regional_hub": {"name": "Regional sorting hub", "branch": "Processing", "needs": "sorting_center",
		"text": "Sorts the neighboring towns' mail too. They get faster mail; you get their postage."},
	"rail_mail": {"name": "Rail mail spur", "branch": "Processing", "needs": "regional_hub",
		"text": "Mail cars on the railroad. Needs a rail depot in town."},
	"air_mail": {"name": "Air mail", "branch": "Processing", "needs": "regional_hub",
		"text": "Overnight mail flies out of the airport. Needs an airport with cargo."},
}
const BRANCHES := ["Counter", "Delivery", "Parcels", "Processing"]

const FIRST := ["Ruth", "Harold", "Darlene", "Wayne", "Marjorie", "Dale", "Joyce", "Gene", "Linda", "Roger",
	"Carol", "Larry", "Brenda", "Dwight", "Sharon", "Merle", "Peggy", "Lyle", "Connie", "Vernon"]
const LAST := ["Hadley", "Schroeder", "Kessler", "Pruitt", "Lindqvist", "Overton", "Brandt", "McKinney",
	"Stoll", "Huffman", "Albright", "Dearing", "Voss", "Pennington", "Kemper", "Rademacher", "Tolliver", "Yoder"]

## id -> {pos (gate: middle of the front edge), dir (unit, toward the road),
## cell, cells: [Vector2i], opened (tick), zip, leader (Agency.leader plus
## the postmaster's name), built: [tree node ids] and why (Agency), fund (the
## postmaster's own money), funding (the city's level, an index into
## Balance.MAIL_FUNDING), lands {node: [pieces]}, project {node, done
## (tick)} or {} (a node still going up), plan (what's next, plain words),
## want, short (fleet counters), boxed, pieces_today, parcels_waiting,
## delivered (pieces so far), ver, edge}
## `edge` holds the office's edge pieces, piece -> outline cut back to the
## road in its own frame, exactly as CivicHubs' `edge`: they count as its
## land (at, covers) but not as pieces for upkeep, carriers, the tree's
## buildings or the growth limit.
var offices := {}
## Street (road segment) -> the tick its mail last came.
var letters := {}
## Street -> the tick a parcel van last came.
var parcels := {}
## Vehicles on the road: traffic trip id -> {office, kind ("carrier",
## "rural", "van", "freight_in", "freight_out"), stops: [segs left], seg
## (where it's headed, -1 home, -2 the region), prev, at: [x, z], load}.
var trips := {}
## Vehicles that couldn't find a way; they try for home next round.
var parked := []
## Bumped whenever any office's land or tree changes (the view redraws).
var version := 0
## Shares of homes and businesses whose mail came recently, 0 to 1.
var home_share := 0.0
var business_share := 0.0
var _next_id := 1
var _net_dirty := true
var _hooked: RoadNetwork


## A name as it reads mid-sentence ("Sorting room" -> "sorting room", but
## "24-hour PO box lobby" keeps its capitals).
static func lower(name: String) -> String:
	return name.left(1).to_lower() + name.substr(1)


static func draft(pos: Vector3, dir: Vector3) -> Dictionary:
	return {"pos": pos, "dir": dir, "cell": CELL, "cells": BASE.duplicate()}


## Why a post office can't go here, or "" if it can.
func site_problem(sim: CitySim, pos: Vector3, dir: Vector3) -> String:
	if not offices.is_empty():
		return "The town has its post office. It grows next door as the town does."
	var h := draft(pos, dir)
	for c in BASE:
		var p := _cell_problem(sim, h, c, -1, false)
		if p != "":
			return p
	return ""


func _cell_problem(sim: CitySim, h: Dictionary, c: Vector2i, id: int, auto: bool) -> String:
	var p := sim.hubs._cell_problem(sim, h, c, -2, auto)
	if p != "":
		return p
	var mid := CivicHubs.cell_center(h, c)
	for q in CivicHubs.cell_poly(h, c, 1.0):
		for pt in [mid, mid.lerp(Vector3(q.x, 0.0, q.y), 0.9)]:
			var other := at(pt)
			if other != -1 and other != id:
				return "Overlaps the post office."
	return ""


func add(sim: CitySim, pos: Vector3, dir: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	var h := draft(pos, dir)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, id, "postmaster"])
	var lead := Agency.leader(sim, hash([sim.city_seed, "mail", id]))
	lead.name = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
	h.merge({"opened": sim.tick_count, "zip": 47500 + rng.randi_range(1, 99),
		"leader": lead, "built": [], "why": "", "fund": 0.0, "funding": 1, "lands": {}, "project": {},
		"plan": "", "want": 0, "short": 0, "boxed": false, "pieces_today": 0, "parcels_waiting": 0,
		"delivered": 0, "ver": 0, "edge": {}})
	offices[id] = h
	version += 1
	return id


func remove(id: int) -> bool:
	if not offices.erase(id):
		return false
	for i in range(parked.size() - 1, -1, -1):
		if parked[i].office == id:
			parked.remove_at(i)
	version += 1
	return true


## The office whose land holds this point, or -1.
func at(p: Vector3) -> int:
	for id in offices:
		var h: Dictionary = offices[id]
		var d: Vector3 = p - h.pos
		var c := Vector2i(roundi(d.dot(CivicHubs.right(h)) / h.cell), floori(-d.dot(h.dir) / h.cell))
		if c in h.cells:
			return id
		var e: Dictionary = h.get("edge", {})
		if e.has(c) and Geometry2D.is_point_in_polygon(Vector2(d.dot(CivicHubs.right(h)), -d.dot(h.dir)), e[c]):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1


func extent(id: int) -> Array:
	var h: Dictionary = offices[id]
	var mid := Vector3.ZERO
	for c in h.cells:
		mid += CivicHubs.cell_center(h, c)
	mid /= maxf(h.cells.size(), 1.0)
	var r := 0.0
	for c in h.cells:
		r = maxf(r, CivicHubs.cell_center(h, c).distance_to(mid) + h.cell * 0.71)
	for c in h.get("edge", {}):
		for q in CivicHubs.edge_poly(h, c):
			r = maxf(r, Vector2(mid.x, mid.z).distance_to(q))
	return [mid, r]


## True once a tree node is built and open (not still going up).
static func done(h: Dictionary, node: String) -> bool:
	return node in h.built and not (not h.project.is_empty() and h.project.node == node)


func has_node(id: int, node: String) -> bool:
	return offices.has(id) and done(offices[id], node)


## The pieces of fleet lot the office has grown (beyond the first six and
## what the tree's buildings stand on).
static func fleet_cells(h: Dictionary) -> Array:
	var out := []
	for c in h.cells:
		if c in BASE:
			continue
		var taken := false
		for n in h.lands:
			if c in h.lands[n]:
				taken = true
		if not taken:
			out.append(c)
	return out


static func fleet_pieces(h: Dictionary) -> int:
	return fleet_cells(h).size()


## Carrier vehicles (trucks and jeeps): a few to start, two more for each
## piece of lot the office grew for them.
func carriers(id: int) -> int:
	var h: Dictionary = offices[id]
	return Balance.MAIL_CARRIERS + 2 * fleet_pieces(h)


func vans(id: int) -> int:
	var h: Dictionary = offices[id]
	var n := Balance.MAIL_VANS
	for node in h.built:
		if done(h, node):
			n += int(Balance.MAIL_TREE[node].get("vans", 0))
	return n


func out(id: int, kinds: Array) -> int:
	var n := 0
	for t in trips:
		if trips[t].office == id and trips[t].kind in kinds:
			n += 1
	for p in parked:
		if p.office == id and p.kind in kinds:
			n += 1
	return n


## What the post offices cost the city a month: the building, more for each
## piece it grew, and the funding it gets.
func monthly_cost() -> int:
	var total := 0.0
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		var size := 1.0 + Balance.HUB_PIECE_UPKEEP * maxi(0, h.cells.size() - BASE.size())
		var upkeep := float(Balance.MAIL_UPKEEP)
		if done(h, "electric_fleet"):
			upkeep *= 1.0 - Balance.MAIL_ELECTRIC_SAVING
		total += upkeep * size + float(Balance.MAIL_FUNDING[h.funding].monthly)
	return roundi(total)


## What the postmaster takes in a month: postage on the mail, plus the
## neighbours' postage once it sorts their mail.
func monthly_income(id: int) -> float:
	var h: Dictionary = offices[id]
	var income := float(h.pieces_today) * Balance.MAIL_DAYS_PER_MONTH * Balance.MAIL_MARGIN_PER_PIECE
	if done(h, "regional_hub"):
		income += neighbors().population * Balance.MAIL_REGIONAL_PER_PERSON
	return income + float(Balance.MAIL_FUNDING[h.funding].monthly)


## Neighbouring towns, from the same sources as Agency's region conditions:
## last month's trade partners (Trade) and what the region server reports
## in sim.region.neighbors ({name, population, mail_hub}). A solo town has
## no neighbours. A neighbour of unknown size counts as
## Balance.MAIL_OFFLINE_TOWN_POP people.
func neighbors_of(sim: CitySim) -> Dictionary:
	var towns := {}
	for d in sim.trade.last_deals:
		for side in ["buyer", "seller"]:
			var who := str(d.get(side, "outside"))
			# A town on its own settles its trade as "me".
			if who != "outside" and who != "" and who != "me" and who != str(sim.region.get("me", "")):
				towns[who] = towns.get(who, -1)
	var hub := false
	for town in sim.region.get("neighbors", []):
		towns[str(town.get("name", ""))] = int(town.get("population", -1))
		hub = hub or bool(town.get("mail_hub", false))
	var pop := 0
	for t in towns:
		pop += Balance.MAIL_OFFLINE_TOWN_POP if towns[t] < 0 else towns[t]
	return {"towns": towns.size(), "population": pop, "hub": hub}


var _last_neighbors := {"towns": 0, "population": 0, "hub": false}


func neighbors() -> Dictionary:
	return _last_neighbors


## True when this town sorts its neighbours' mail (the region can read it to
## give them faster mail).
func serves_region() -> bool:
	for id in offices:
		if done(offices[id], "regional_hub"):
			return true
	return false


# --- Land value and demand -------------------------------------------------------

## A lot's value factor from mail service: 1.0 is no change.
func lot_factor(sim: CitySim, key: String) -> float:
	if offices.is_empty() or not sim.lots.has(key) or not sim.buildings.has(key):
		return 1.0
	var seg: int = sim.lots[key].seg
	var zone := int(sim.buildings[key].zone)
	var f := 1.0
	if served(sim, seg):
		f += Balance.MAIL_VALUE[zone]
		if _last_neighbors.hub:
			f += Balance.MAIL_REGION_HUB_VALUE
	var id: int = offices.keys()[0]
	var h: Dictionary = offices[id]
	if zone == ZoneMap.Zone.RESIDENTIAL:
		if done(h, "po_boxes"):
			f += Balance.MAIL_PO_BOX_VALUE
		if done(h, "passports"):
			f += Balance.MAIL_PASSPORT_VALUE
	elif zone == ZoneMap.Zone.COMMERCIAL:
		if done(h, "parcel_lockers") and parcel_served(sim, seg):
			f += Balance.MAIL_LOCKER_VALUE
	elif done(h, "business_mail"):
		f += Balance.MAIL_BUSINESS_MAIL_VALUE
	if done(h, "mural"):
		var d := CivicHubs.distance(h, sim.lots[key].pos)
		if d < Balance.MAIL_MURAL_REACH:
			f += Balance.MAIL_MURAL_VALUE * (1.0 - d / Balance.MAIL_MURAL_REACH)
	return f


func served(sim: CitySim, seg: int) -> bool:
	return letters.has(seg) and sim.tick_count - int(letters[seg]) <= Balance.MAIL_SERVED_TICKS


func parcel_served(sim: CitySim, seg: int) -> bool:
	return parcels.has(seg) and sim.tick_count - int(parcels[seg]) <= Balance.MAIL_SERVED_TICKS


## How much good mail service lifts a zone's demand.
func demand_shift(zone: int) -> float:
	if offices.is_empty():
		return 0.0
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			return Balance.MAIL_DEMAND_HOMES * home_share
		ZoneMap.Zone.COMMERCIAL:
			return Balance.MAIL_DEMAND_SHOPS * business_share
	return 0.0


## What's wrong with a lot's mail, in plain words, or "".
func lot_problem(sim: CitySim, key: String) -> String:
	if offices.is_empty() or not sim.lots.has(key) or served(sim, sim.lots[key].seg):
		return ""
	if sim.tick_count - int(offices[offices.keys()[0]].opened) < Balance.MAIL_SERVED_TICKS:
		return ""  # the first rounds haven't gone out yet
	return "The mail hasn't come lately: every carrier is busy or no route reaches this street."


# --- Stepping -------------------------------------------------------------------

func tick(sim: CitySim) -> void:
	if not sim.permits.locators.has("post_office"):
		# Lets the player guide the postmaster from the office's panel.
		sim.permits.locators["post_office"] = func(s: CitySim, id: int) -> Vector2:
			var at: Vector3 = s.mail.extent(id)[0] if s.mail.offices.has(id) else Vector3.ZERO
			return Vector2(at.x, at.z)
	if offices.is_empty() and trips.is_empty():
		return
	if _hooked != sim.network:
		_hooked = sim.network
		sim.network.changed.connect(func(): _net_dirty = true)
	if _net_dirty:
		_net_dirty = false
		_prune(sim)
	if sim.simulate_traffic:
		for a in sim.traffic.arrivals:
			if trips.has(a.id):
				var t: Dictionary = trips[a.id]
				trips.erase(a.id)
				_arrive(sim, t)
		for f in sim.traffic.failed:
			if trips.has(f.id):
				var t: Dictionary = trips[f.id]
				trips.erase(f.id)
				_stuck(sim, t)
	if sim.tick_count % CitySim.TICKS_PER_HOUR == 0:
		for id in offices:
			offices[id].fund += monthly_income(id) / 24.0
	var minute := minute_of_day(sim.tick_count)
	var weekday := weekday_of(sim.tick_count)
	if minute == Balance.MAIL_FREIGHT_IN_HOUR * 60 and weekday != 0:
		_freight(sim, true)
	if minute == Balance.MAIL_ROUNDS_HOUR * 60:
		_count_pieces(sim)
		if sim.simulate_traffic:
			_retry_parked(sim)
			_rounds(sim, weekday)
		else:
			_deliver_offstage(sim, weekday)
		_shares(sim)
	if minute == Balance.MAIL_FREIGHT_OUT_HOUR * 60 and weekday != 0:
		_freight(sim, false)
	if sim.tick_count % Balance.HUB_DECIDE_EVERY == Balance.ROUND_AT.mail and not offices.is_empty():
		_decide(sim)


## Minutes past midnight (tick 0 is 6:00 AM).
static func minute_of_day(tick: int) -> int:
	return (360 + tick) % TICKS_PER_DAY


## 0 is Sunday (tick 0 is a Monday).
static func weekday_of(tick: int) -> int:
	return (1 + (360 + tick) / TICKS_PER_DAY) % 7


## Delivery points on each street: one per household (about 2.5 people)
## and one per business. Also the businesses on each street.
func _streets(sim: CitySim) -> Array:
	var points := {}
	var biz := {}
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if not sim.lots.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		var seg: int = sim.lots[key].seg
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			if b.occ <= 0:
				continue
			points[seg] = points.get(seg, 0) + maxi(1, ceili(b.cap / 2.5))
		else:
			points[seg] = points.get(seg, 0) + 1
			biz[seg] = biz.get(seg, 0) + 1
	return [points, biz]


## Each street's curb: in front of its first building, where the carrier stops.
func _curbs(sim: CitySim) -> Dictionary:
	var out := {}
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if sim.lots.has(key) and not out.has(sim.lots[key].seg):
			out[sim.lots[key].seg] = sim.lots[key].front
	return out


func _count_pieces(sim: CitySim) -> void:
	var s := _streets(sim)
	var homes := 0
	for seg in s[0]:
		homes += int(s[0][seg])
	var biz := 0
	for seg in s[1]:
		biz += int(s[1][seg])
	for id in offices:
		var h: Dictionary = offices[id]
		h.pieces_today = roundi((homes - biz) * Balance.MAIL_PIECES_PER_HOME + biz * Balance.MAIL_PIECES_PER_BUSINESS)
		h.parcels_waiting += roundi(biz * Balance.MAIL_PARCELS_PER_BUSINESS)


## The postmaster's routes for today: streets in order out from the office,
## each route up to a carrier's day of delivery points. A street whose homes
## sit far apart is a rural route, driven in a right-hand-drive jeep.
func plan_routes(sim: CitySim, id: int, streets: Dictionary, per_route: int, max_stops: int) -> Array:
	var h: Dictionary = offices[id]
	var curb := _curbs(sim)
	var left := []
	for seg in streets:
		if curb.has(seg) and sim.network.segments.has(seg):
			left.append(seg)
	left.sort()
	var routes := []
	while not left.is_empty():
		# Start from the street nearest the office.
		var here: Vector3 = h.pos
		var route := {"stops": [], "points": 0, "rural": 0}
		while not left.is_empty() and route.stops.size() < max_stops and route.points < per_route:
			var best := -1
			var best_d := INF
			for seg in left:
				var d: float = curb[seg].distance_to(here)
				if d < best_d - 0.001:
					best_d = d
					best = seg
			if not route.stops.is_empty() and best_d > ROUTE_REACH:
				break
			left.erase(best)
			route.stops.append(best)
			route.points += int(streets[best])
			if _rural(sim, best, int(streets[best])):
				route.rural += 1
			here = curb[best]
		route.rural = route.rural * 2 > route.stops.size()
		routes.append(route)
	return routes


## Fewer than one delivery point every 40 m of street reads as rural.
func _rural(sim: CitySim, seg: int, points: int) -> bool:
	var c := sim.network.curve_of(seg)
	var len: float = c[0].distance_to(c[1]) + c[1].distance_to(c[2])
	return len / maxf(points, 1.0) > Balance.MAIL_RURAL_SPACING


## Every morning (Monday to Saturday) each route sends a carrier while one
## is in; parcel vans go out to the businesses (Sundays too, once the
## postmaster has the van fleet).
func _rounds(sim: CitySim, weekday: int) -> void:
	var s := _streets(sim)
	var curb := _curbs(sim)
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		var per_route := Balance.MAIL_POINTS_PER_ROUTE
		if done(h, "cluster_boxes"):
			per_route = roundi(per_route * Balance.MAIL_CLUSTER_BOOST)
		if weekday != 0:
			var routes := plan_routes(sim, id, s[0], per_route, Balance.MAIL_STOPS_PER_ROUTE)
			h.routes = routes.size()
			for r in routes:
				h.want += 1
				if out(id, ["carrier", "rural"]) >= carriers(id):
					h.short += 1
					continue
				_start(sim, id, "rural" if r.rural else "carrier", r.stops, curb)
		if weekday != 0 or done(h, "more_vans"):
			var van_routes := plan_routes(sim, id, s[1], 1 << 20, Balance.MAIL_VAN_STOPS)
			for r in van_routes:
				if out(id, ["van"]) >= vans(id):
					break
				_start(sim, id, "van", r.stops, curb)


## With cars switched off (the balance harness), each route that has a
## carrier is simply delivered.
func _deliver_offstage(sim: CitySim, weekday: int) -> void:
	if weekday == 0:
		return
	var s := _streets(sim)
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		var routes := plan_routes(sim, id, s[0], Balance.MAIL_POINTS_PER_ROUTE, Balance.MAIL_STOPS_PER_ROUTE)
		h.routes = routes.size()
		for i in routes.size():
			h.want += 1
			if i >= carriers(id):
				h.short += 1
				continue
			for seg in routes[i].stops:
				letters[seg] = sim.tick_count
		for seg in s[1]:
			parcels[seg] = sim.tick_count
		h.delivered += h.pieces_today


func _start(sim: CitySim, id: int, kind: String, stops: Array, curb: Dictionary) -> void:
	var h: Dictionary = offices[id]
	var rest: Array = stops.duplicate()
	var first: int = rest.pop_front()
	var t := {"office": id, "kind": kind, "stops": rest, "seg": first, "prev": -1, "at": _xz(h.pos), "load": 0}
	if kind == "van":
		t.load = mini(int(h.parcels_waiting), Balance.MAIL_VAN_PARCELS)
		h.parcels_waiting -= t.load
	_dispatch(sim, t, curb[first])


const PURPOSE := {"carrier": "mail", "rural": "rural_mail", "van": "parcels", "freight_in": "mail_freight",
	"freight_out": "mail_freight"}


func _dispatch(sim: CitySim, t: Dictionary, to: Vector3) -> bool:
	var from_ref := "mail:%d" % t.office if t.prev == -1 else "street:%d" % t.prev
	if t.prev == -2:
		from_ref = "edge"
	var to_ref := "mail:%d" % t.office
	if t.seg >= 0:
		to_ref = "street:%d" % t.seg
	elif t.seg == -2:
		to_ref = "edge"
	var good := "parcels" if t.kind == "van" else "mail"
	var trip: int = sim.traffic.dispatch({"ref": from_ref, "pos": t.at}, {"ref": to_ref, "pos": _xz(to)},
		PURPOSE[t.kind], {"good": good, "amount": int(t.load)})
	if trip == -1:
		return false
	trips[trip] = t
	return true


func _arrive(sim: CitySim, t: Dictionary) -> void:
	if not offices.has(t.office):
		return  # its office was torn down: the vehicle stays parked where it is
	var h: Dictionary = offices[t.office]
	if t.seg == -1:
		if t.kind == "freight_in":
			pass  # the morning's mail is in, to be sorted
		return  # back in the lot
	if t.seg == -2:
		return  # out to the region, where it came from
	var seg: int = t.seg
	if t.kind == "van":
		parcels[seg] = sim.tick_count
	else:
		letters[seg] = sim.tick_count
		h.delivered += roundi(float(h.pieces_today) / maxf(_street_count(sim), 1.0))
	t.prev = seg
	var curb := _curbs(sim)
	t.at = _xz(curb.get(seg, Vector3(t.at[0], 0.0, t.at[1])))
	while not t.stops.is_empty():
		var next: int = t.stops.pop_front()
		if curb.has(next):
			t.seg = next
			if _dispatch(sim, t, curb[next]):
				return
	_head_home(sim, t)


var _streets_cache := [-1, 0]


func _street_count(sim: CitySim) -> int:
	if _streets_cache[0] != sim.tick_count / TICKS_PER_DAY:
		_streets_cache = [sim.tick_count / TICKS_PER_DAY, _streets(sim)[0].size()]
	return _streets_cache[1]


func _head_home(sim: CitySim, t: Dictionary) -> void:
	t.seg = -1
	if not _dispatch(sim, t, offices[t.office].pos):
		parked.append(t)


func _stuck(sim: CitySim, t: Dictionary) -> void:
	if not offices.has(t.office):
		return
	if t.seg == -1:
		parked.append(t)
	elif t.seg == -2:
		return  # the region truck couldn't get out: it stays in the lot
	else:
		_arrive_skip(sim, t)


## A street it couldn't reach is skipped; the rest of the route goes on.
func _arrive_skip(sim: CitySim, t: Dictionary) -> void:
	var curb := _curbs(sim)
	while not t.stops.is_empty():
		var next: int = t.stops.pop_front()
		if curb.has(next):
			t.seg = next
			if _dispatch(sim, t, curb[next]):
				return
	_head_home(sim, t)


func _retry_parked(sim: CitySim) -> void:
	var waiting := parked.duplicate()
	parked.clear()
	for p in waiting:
		if offices.has(p.office):
			_head_home(sim, p)


## The mail truck to and from the region (the county highway's far end):
## in before dawn with the day's mail, out in the evening with the town's.
## A regional hub runs one more each way for every neighbouring town.
func _freight(sim: CitySim, inbound: bool) -> void:
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		var edge := _edge(sim, h.pos)
		if edge == Vector3.INF:
			continue
		var n := 1
		if done(h, "regional_hub"):
			n += mini(_last_neighbors.towns, Balance.MAIL_REGIONAL_TRUCKS)
		for i in n:
			if inbound:
				var t := {"office": id, "kind": "freight_in", "stops": [], "seg": -1, "prev": -2,
					"at": _xz(edge), "load": h.pieces_today}
				_dispatch(sim, t, h.pos)
			else:
				var t := {"office": id, "kind": "freight_out", "stops": [], "seg": -2, "prev": -1,
					"at": _xz(h.pos), "load": h.pieces_today}
				_dispatch(sim, t, edge)


func _edge(sim: CitySim, near: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for n in sim.region_links:
		if sim.network.nodes.has(n) and sim.network.nodes[n].distance_to(near) < best_d - 0.01:
			best_d = sim.network.nodes[n].distance_to(near)
			best = sim.network.nodes[n]
	return best


func _shares(sim: CitySim) -> void:
	var homes := 0
	var homes_ok := 0
	var biz := 0
	var biz_ok := 0
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var seg: int = sim.lots[key].seg
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			homes += 1
			if served(sim, seg):
				homes_ok += 1
		else:
			biz += 1
			if served(sim, seg) or parcel_served(sim, seg):
				biz_ok += 1
	home_share = 0.0 if homes == 0 else float(homes_ok) / homes
	business_share = 0.0 if biz == 0 else float(biz_ok) / biz
	for seg in letters.keys():
		if not sim.network.segments.has(seg):
			letters.erase(seg)
	for seg in parcels.keys():
		if not sim.network.segments.has(seg):
			parcels.erase(seg)


# --- Warehouses hand parcels over ------------------------------------------------

## Where a warehouse truck should bring parcels: {} or {id, ref, pos}.
func parcel_dropoff(pos: Vector3) -> Dictionary:
	var best := -1
	var best_d := INF
	for id in offices:
		var d: float = offices[id].pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	if best == -1:
		return {}
	return {"id": best, "ref": "mail:%d" % best, "pos": _xz(offices[best].pos)}


## Parcels a warehouse truck brought in; the vans take them out.
func receive_parcels(id: int, count: int) -> void:
	if offices.has(id):
		offices[id].parcels_waiting += maxi(0, count)


# --- The postmaster decides ---------------------------------------------------------

## Every few game hours: finish what's being built, grow the fleet lot when
## carriers ran short, and pick what to build next from the tree.
func _decide(sim: CitySim) -> void:
	_last_neighbors = neighbors_of(sim)
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		if not h.project.is_empty() and sim.tick_count >= int(h.project.done):
			h.project = {}
			_touch(h)
		# The player's word to the postmaster: grow sooner, or hold off.
		var stance: String = sim.permits.guidance("post_office", id).stance
		# Carriers all out on half the routes they wanted: a bigger lot.
		var share := Balance.HUB_GROW_BUSY_SHARE * (0.5 if stance == "grow" else 1.0)
		var short: bool = h.want > 0 and float(h.short) / h.want >= share
		h.want = 0
		h.short = 0
		if short and stance != "hold" and h.cells.size() < int(BASE.size() * Balance.HUB_MAX_GROWTH):
			var c := _best_piece(sim, id)
			h.boxed = c == Vector2i.MAX
			if not h.boxed:
				# An edge piece the road has since let go of becomes whole.
				h.edge.erase(c)
				h.cells.append(c)
				_touch(h)
				sim.zones_changed.emit()
			elif CivicHubs.take_edge(sim, h, _edge_problem.bind(sim, id)):
				# Boxed in: lot and lawn up to the sidewalk instead.
				_touch(h)
				sim.zones_changed.emit()
		if h.project.is_empty():
			_choose(sim, id, stance)


## Why a node isn't open to this postmaster yet, or "" if it is. Gates are
## the postmaster's own schooling and the town and region around them.
func locked(sim: CitySim, id: int, node: String) -> String:
	var h: Dictionary = offices[id]
	var n: Dictionary = TREE[node]
	var b: Dictionary = Balance.MAIL_TREE[node]
	if n.needs != "" and not done(h, n.needs):
		return "Needs %s first." % lower(TREE[n.needs].name)
	# Agency's shared conditions first.
	if not Agency.holds(sim, h, h.pos, yearly(id), "leader_edu", float(b.get("education", 0.0))):
		return "Needs a postmaster with more schooling."
	if float(h.leader.ambition) < float(b.get("ambition", 0.0)):
		return "This postmaster isn't one to push for it."
	if not Agency.holds(sim, h, h.pos, yearly(id), "population", int(b.get("population", 0))):
		return "Needs %s people in town." % CitySim.money_text(int(b.population))
	if b.has("town_school") and not Agency.holds(sim, h, h.pos, yearly(id), "education", float(b.town_school)):
		return "Needs more of the town's homes near a school."
	if b.has("link") and not Agency.holds(sim, h, h.pos, yearly(id), "link", 1):
		return "Needs a road out to the region."
	if h.pieces_today < int(b.get("pieces", 0)):
		return "Needs %s pieces of mail a day (now %s)." % [CitySim.money_text(int(b.pieces)),
			CitySim.money_text(int(h.pieces_today))]
	var counts := _business_counts(sim)
	if counts[0] < int(b.get("shops", 0)):
		return "Needs %d shops in town." % int(b.shops)
	if counts[1] < int(b.get("factories", 0)):
		return "Needs %d factories in town." % int(b.factories)
	var nb := _last_neighbors
	if nb.towns < int(b.get("towns", 0)):
		return "Needs %d neighboring towns linked by road." % int(b.towns)
	if nb.population < int(b.get("region_pop", 0)) and not (node == "parcel_ground_hub" and _has_warehouses(sim)):
		return "Needs %s people in the towns around." % CitySim.money_text(int(b.region_pop))
	if node == "rail_mail" and not _has(sim, "rail"):
		return "Needs a rail depot in town."
	if node == "air_mail" and not _has(sim, "airports"):
		return "Needs an airport with cargo."
	return ""


func _has(sim: CitySim, prop: String) -> bool:
	var v = sim.get(prop)
	if v == null:
		return false
	for list_name in ["depots", "airports", "sites", "warehouses"]:
		var l = v.get(list_name)
		if l is Dictionary and not l.is_empty():
			return true
	return false


func _has_warehouses(sim: CitySim) -> bool:
	return _has(sim, "warehouses")


func _business_counts(sim: CitySim) -> Array:
	var shops := 0
	var factories := 0
	for key in sim.buildings:
		match int(sim.buildings[key].zone):
			ZoneMap.Zone.COMMERCIAL: shops += 1
			ZoneMap.Zone.INDUSTRIAL: factories += 1
	return [shops, factories]


## The tree in Agency's shape: {id, name, cost, requires, needs, effects,
## note}. Mail's own gates (mail volume, shops, neighbours) are checked by
## locked() before Agency sees a node; "weight" is how much a node does,
## which Agency weighs against its cost by the postmaster's temperament.
static func agency_tree() -> Array:
	var out := []
	for node in TREE:
		var b: Dictionary = Balance.MAIL_TREE[node]
		out.append({"id": node, "name": TREE[node].name, "cost": int(b.cost),
			"requires": [] if TREE[node].needs == "" else [TREE[node].needs], "needs": {},
			"effects": {"service*": 0.05 * float(b.weight)}, "note": TREE[node].text})
	return out


## What the office takes in a year, as Agency reads a hub's profit.
func yearly(id: int) -> float:
	return monthly_income(id) * 12.0


## The postmaster's next move, through Agency: of the nodes open to them
## that the fund covers and that have land next door, the one they value
## most (ambition reaches for the big step, caution keeps a cushion).
func _choose(sim: CitySim, id: int, stance := "steady") -> void:
	var h: Dictionary = offices[id]
	var open := []
	var saving := ""
	var boxed := ""
	var lands := {}
	for node in agency_tree():
		if node.id in h.built or locked(sim, id, node.id) != "":
			continue
		var b: Dictionary = Balance.MAIL_TREE[node.id]
		if float(b.cost) > h.fund:
			if saving == "":
				saving = "Saving up for %s ($%s)." % [lower(node.name), CitySim.money_text(int(b.cost))]
			continue
		if int(b.land) > 0 and stance == "hold":
			continue
		var pieces := []
		for k in int(b.land):
			var c := _best_piece(sim, id, pieces)
			if c == Vector2i.MAX:
				break
			pieces.append(c)
		if pieces.size() < int(b.land):
			if boxed == "":
				boxed = "Wants to build %s but there's no free land next door." % lower(node.name)
			continue
		lands[node.id] = pieces
		open.append(node)
	h.boxed = boxed != "" and open.is_empty()
	var pick := Agency.develop(sim, h, open, h.pos, yearly(id))
	if pick.is_empty():
		h.plan = boxed if boxed != "" else saving if saving != "" else \
			"Running the routes. Nothing new to build until the town or its neighbors grow."
		if open.size() > 0 and saving == "":
			h.plan = "Saving up before the next step."
		return
	var b: Dictionary = Balance.MAIL_TREE[pick.id]
	var pieces: Array = lands[pick.id]
	for c in pieces:
		h.edge.erase(c)
	h.cells.append_array(pieces)
	h.lands[pick.id] = pieces
	h.fund -= float(b.cost)
	h.project = {"node": pick.id, "done": sim.tick_count + int(float(b.days) * TICKS_PER_DAY)}
	h.plan = "Building %s." % lower(pick.name)
	_touch(h)
	if not pieces.is_empty():
		sim.zones_changed.emit()


## The free piece touching the office that keeps it most compact.
func _best_piece(sim: CitySim, id: int, taking := []) -> Vector2i:
	var h: Dictionary = offices[id]
	var cells: Array = h.cells + taking
	var mid := Vector2.ZERO
	for c in cells:
		mid += Vector2(c)
	mid /= cells.size()
	var best := Vector2i.MAX
	var best_d := INF
	var seen := {}
	# A building's pieces stay together: next to what it already took.
	if not taking.is_empty():
		var joined := _best_piece_from(sim, id, h, cells, taking, mid)
		if joined != Vector2i.MAX:
			return joined
	for c in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n in cells or seen.has(n):
				continue
			seen[n] = true
			var dist := Vector2(n).distance_to(mid)
			if dist > best_d + 0.001 or (absf(dist - best_d) <= 0.001 and CivicHubs._less(best, n)):
				continue
			if _cell_problem(sim, h, n, id, true) == "":
				best = n
				best_d = dist
	return best


func _best_piece_from(sim: CitySim, id: int, h: Dictionary, cells: Array, from: Array, mid: Vector2) -> Vector2i:
	var best := Vector2i.MAX
	var best_d := INF
	for c in from:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n in cells:
				continue
			var dist := Vector2(n).distance_to(mid)
			if dist > best_d + 0.001 or (absf(dist - best_d) <= 0.001 and CivicHubs._less(best, n)):
				continue
			if _cell_problem(sim, h, n, id, true) == "":
				best = n
				best_d = dist
	return best


## Why ground `world` (an edge piece's outline, x, z) can't be office
## `id`'s, or "": the hubs' checks (water, reserves, other owners, zoned or
## built lots), less the road one (it's already cut back), and no other post
## office on it.
func _edge_problem(world: PackedVector2Array, sim: CitySim, id: int) -> String:
	var pts := CivicHubs._inner_pts(world, offices[id].cell * 0.2)
	var p := sim.hubs._ground_problem(sim, world, pts, -2, true, false)
	if p != "":
		return p
	for pt in pts:
		var other := at(pt)
		if other != -1 and other != id:
			return "Overlaps the post office."
	return ""


## Roads win: pieces a road now runs through go; if that splits the office,
## the part by the gate (or the biggest) stays. Edge pieces are cut back to
## the new roads (CivicHubs.prune_edges).
func _prune(sim: CitySim) -> void:
	var ids := offices.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = offices[id]
		var keep := []
		for c in h.cells:
			if not Services.road_clash(sim.network, CivicHubs.cell_poly(h, c, 1.0)):
				keep.append(c)
		if keep.size() == h.cells.size():
			if not h.edge.is_empty() and CivicHubs.prune_edges(sim, h):
				_touch(h)
			continue
		var best := []
		var left := keep.duplicate()
		while not left.is_empty():
			var part := CivicHubs._connected(left)
			left = left.filter(func(c): return not c in part)
			if part.size() > best.size() or (part.size() == best.size() and CivicHubs._gate_side(part) < CivicHubs._gate_side(best)):
				best = part
		h.cells = h.cells.filter(func(c): return c in best)
		for n in h.lands:
			h.lands[n] = h.lands[n].filter(func(c): return c in best)
		CivicHubs.prune_edges(sim, h)
		_touch(h)
		if h.cells.is_empty():
			remove(id)


func _touch(h: Dictionary) -> void:
	h.ver = int(h.get("ver", 0)) + 1
	version += 1


static func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]


# --- Commands -------------------------------------------------------------------------

## place_post_office {pos, dir}, remove_post_office {id}, post_office_funding
## {id, level}. Returns true if anything changed.
func command(sim: CitySim, cmd: Dictionary) -> bool:
	match cmd.type:
		"place_post_office":
			var pos := Vector3(float(cmd.pos[0]), 0.0, float(cmd.pos[1]))
			var dir := Vector3(float(cmd.dir[0]), 0.0, float(cmd.dir[1])).normalized()
			if dir.length() < 0.5 or Balance.MAIL_COST > sim.economy.money or site_problem(sim, pos, dir) != "":
				return false
			var id := add(sim, pos, dir)
			sim.economy.money -= Balance.MAIL_COST
			for c in offices[id].cells:
				sim._clear_zones_under(CivicHubs.cell_poly(offices[id], c))
			return true
		"remove_post_office":
			return remove(int(cmd.id))
		"post_office_funding":
			var id := int(cmd.id)
			var level := int(cmd.level)
			if not offices.has(id) or level < 0 or level >= Balance.MAIL_FUNDING.size() or offices[id].funding == level:
				return false
			offices[id].funding = level
			return true
	return false


# --- Saving -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out_offices := {}
	for id in offices:
		var h: Dictionary = offices[id]
		var cells := []
		for c in h.cells:
			cells.append([c.x, c.y])
		var o := {}
		for k in h:
			if not k in ["pos", "dir", "cells", "cell", "ver", "boxed", "lands", "edge"]:
				o[k] = h[k]
		o.pos = [h.pos.x, h.pos.z]
		o.dir = [h.dir.x, h.dir.z]
		o.cells = cells
		var lands := {}
		for n in h.lands:
			lands[n] = h.lands[n].map(func(c): return [c.x, c.y])
		o.lands = lands
		if not h.edge.is_empty():
			o.edge = CivicHubs.edge_to_save(h.edge)
		out_offices[str(id)] = o
	var tr := {}
	for id in trips:
		tr[str(id)] = trips[id]
	var l := {}
	for seg in letters:
		l[str(seg)] = letters[seg]
	var p := {}
	for seg in parcels:
		p[str(seg)] = parcels[seg]
	return {"offices": out_offices, "next_id": _next_id, "trips": tr, "parked": parked, "letters": l,
		"parcels": p}


func from_dict(d: Dictionary) -> void:
	offices.clear()
	for k in d.get("offices", {}):
		var s: Dictionary = d.offices[k]
		var cells := []
		for c in s.cells:
			cells.append(Vector2i(int(c[0]), int(c[1])))
		var h := {}
		for key in s:
			h[key] = s[key]
		h.pos = Vector3(s.pos[0], 0.0, s.pos[1])
		h.dir = Vector3(s.dir[0], 0.0, s.dir[1]).normalized()
		h.cell = CELL
		h.cells = cells
		h.ver = 0
		h.boxed = false
		h.funding = int(s.get("funding", 1))
		h.fund = float(s.get("fund", 0.0))
		for n in ["opened", "zip", "want", "short", "pieces_today", "parcels_waiting", "delivered", "routes"]:
			h[n] = int(s.get(n, 0))
		var built := []
		var saved_built = s.get("built", [])
		# The first saves kept the tree as {node: tick}.
		for n in (saved_built if saved_built is Array else []) + s.get("tree", {}).keys():
			if TREE.has(str(n)) and not str(n) in built:
				built.append(str(n))
		h.built = built
		h.why = str(s.get("why", ""))
		var lands := {}
		for n in s.get("lands", {}):
			if TREE.has(n):
				lands[str(n)] = s.lands[n].map(func(c): return Vector2i(int(c[0]), int(c[1])))
		h.lands = lands
		h.edge = CivicHubs.edge_from_save(s.get("edge", []))
		var pr: Dictionary = s.get("project", {})
		h.project = {} if pr.is_empty() or not TREE.has(str(pr.get("node", ""))) else \
			{"node": str(pr.node), "done": int(pr.done)}
		h.plan = str(s.get("plan", ""))
		var pm: Dictionary = s.get("leader", s.get("postmaster", {}))
		h.leader = {"name": str(pm.get("name", "Ruth Hadley")), "edu": float(pm.get("edu", pm.get("education", 0.5))),
			"caution": float(pm.get("caution", 0.5)), "ambition": float(pm.get("ambition", 0.5))}
		offices[int(k)] = h
	_next_id = int(d.get("next_id", 1))
	trips.clear()
	for id in d.get("trips", {}):
		trips[int(id)] = _vehicle(d.trips[id])
	parked.clear()
	for t in d.get("parked", []):
		parked.append(_vehicle(t))
	letters.clear()
	for seg in d.get("letters", {}):
		letters[int(seg)] = int(d.letters[seg])
	parcels.clear()
	for seg in d.get("parcels", {}):
		parcels[int(seg)] = int(d.parcels[seg])
	_net_dirty = true
	version += 1


static func _vehicle(t: Dictionary) -> Dictionary:
	var stops := []
	for s in t.get("stops", []):
		stops.append(int(s))
	return {"office": int(t.office), "kind": str(t.kind), "stops": stops, "seg": int(t.seg),
		"prev": int(t.get("prev", -1)), "at": [float(t.at[0]), float(t.at[1])], "load": int(t.get("load", 0))}
