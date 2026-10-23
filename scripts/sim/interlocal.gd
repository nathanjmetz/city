class_name Interlocal
extends RefCounted
## Shared services between towns (Brawn, 2026-10-22): a town's landfill
## manager, fire chief, police chief or school superintendent offers to serve
## a neighbor town joined to it by county road. The offer comes to both
## players' permit bells; when both approve, it's a signed deal, like a real
## Indiana interlocal agreement (IC 36-1-7): the served town pays a monthly
## share of the host's cost, and the host's people do the work.
##
##   trash   the host's garbage trucks come over the county road, pick up at
##           the curbs and haul it back to the host's landfill
##   fire    homes within 5 road miles of the host's station (through the
##           county road) count as covered, as ISO rates them
##   police  the host's officers patrol out to their reach
##   school  the host's school takes the town's children; a yellow bus runs
##           over the county road every school morning and afternoon
##
## Every vehicle is a real trip: it leaves the host's site, drives to the
## county road, and comes back loaded. In the served town it comes in from
## the county road, makes its stops and leaves the same way.
##
## Each computer runs only its own town, and each town only ever simulates
## its own half from the deal's terms (the fee, the county road, how far the
## host's station is from it), so a deal keeps running on its last terms
## while either player is away. The agreement itself lives in the region's
## ledger (Ledger): a leader's offer goes on the host's bell first, out to
## the neighbor once approved, onto the neighbor's bell, and is signed when
## that player approves too (sync).

## The services, how the card names them and who offers them.
const KINDS := {
	"trash": {"name": "trash pickup", "title": "Landfill manager", "hub": "Landfill"},
	"fire": {"name": "fire protection", "title": "Fire Chief", "hub": "Fire department"},
	"police": {"name": "police patrols", "title": "Police Chief", "hub": "Police department"},
	"school": {"name": "schooling", "title": "Superintendent", "hub": "Schools"},
}
## Covered by distance in Services (the rest have their own rounds).
const COVERAGE := {"fire": Services.Kind.FIRE, "police": Services.Kind.POLICE, "school": Services.Kind.SCHOOL}
## How often contract trucks look for trash to pick up (as CivicHubs).
const EVERY := 30
## School bus runs: the host's bus leaves its school, and the served town's
## run starts at the county road, at these hours of each game day.
const BUS_HOURS := [7, 15]

## Signed deals: id -> {"id", "kind", "role" ("host" or "served"), "other"
## (the other town's id), "other_name", "fee" ($ a month), "link" (this
## town's county road end toward the other), "offset" (road metres from the
## host's building to the county road; -1 while the host has none), "left"
## (game months of notice left, -1 if none given), "picked" (tons of trash
## picked up so far, served side), "haul" (tons still to bring back, host
## side), "homes" (the served town's)}.
var deals := {}
## Vehicles out on contract runs: trip id -> run.
var trips := {}


## The served town's deal for a service, or {} if it has none.
func served_by(kind: String) -> Dictionary:
	for id in _ids():
		if deals[id].kind == kind and deals[id].role == "served":
			return deals[id]
	return {}


## True while a deal of this kind is serving this town.
func serves(kind: String) -> bool:
	var d := served_by(kind)
	return not d.is_empty() and int(d.offset) >= 0


## Money from deals this month: fees in as host, out as the served town.
## A deal pays only while it serves.
func monthly_net() -> int:
	var total := 0
	for id in deals:
		var d: Dictionary = deals[id]
		if int(d.offset) < 0:
			continue
		total += int(d.fee) * (1 if d.role == "host" else -1)
	return total


## The player gives notice to end a deal (CitySim command "end_deal" {id}).
## The neighbor hears it from this town's copy, and the deal ends in the
## region's ledger once the notice runs out (sync).
func end(sim, id: String) -> bool:
	if not deals.has(id) or int(deals[id].left) >= 0:
		return false
	deals[id].left = Balance.INTERLOCAL_NOTICE
	return true


## The fee for a service: the host's cost shared by homes, plus the
## administrative share.
static func fee(kind: String, host_homes: int, served_homes: int) -> int:
	var share := float(served_homes) / maxf(host_homes + served_homes, 1)
	var f := float(Balance.INTERLOCAL[kind].upkeep) * share * (1.0 + Balance.INTERLOCAL_ADMIN)
	return maxi(roundi(f / 100.0) * 100, Balance.INTERLOCAL_MIN_FEE)


static func homes(sim) -> int:
	var n := 0
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			n += 1
	return n


## What the town lacks that a neighbor could serve: no station, school or
## waste site of its own, and enough homes to bother.
static func needs(sim, kind: String) -> bool:
	if homes(sim) < Balance.INTERLOCAL_MIN_HOMES:
		return false
	if kind == "trash":
		return sim.hubs._waste_ids().is_empty()
	for id in sim.services.buildings:
		if sim.services.buildings[id].kind == COVERAGE[kind]:
			return false
	return true


## Road metres from the host's nearest building of this kind to its county
## road end `link`, or -1 if it has none that reaches.
static func offset(sim, kind: String, link: int) -> int:
	if not sim.network.nodes.has(link):
		return -1
	if kind == "trash":
		return -1 if _site(sim, kind, link).is_empty() else 0
	var d: float = sim.services.reach_by_kind.get(COVERAGE[kind], {}).get(link, INF)
	return roundi(d) if d < float(Balance.INTERLOCAL[kind].reach) else -1


## Where the host's vehicles leave from: the waste site, or the school,
## nearest the county road end. [] if there is none.
static func _site(sim, kind: String, link: int) -> Array:
	var to: Vector3 = sim.network.nodes.get(link, Vector3.ZERO)
	var best := []
	var best_d := INF
	if kind == "trash":
		for id in sim.hubs._waste_ids():
			var p: Vector3 = sim.hubs.hubs[id].pos
			if p.distance_to(to) < best_d:
				best_d = p.distance_to(to)
				best = [p.x, p.z, id]
	elif COVERAGE.has(kind):
		var ids: Array = sim.services.buildings.keys()
		ids.sort()
		for id in ids:
			var b: Dictionary = sim.services.buildings[id]
			if b.kind != COVERAGE[kind]:
				continue
			var p: Vector3 = b.pos + b.dir * Services.size_of(b).y * 0.5
			if p.distance_to(to) < best_d:
				best_d = p.distance_to(to)
				best = [p.x, p.z, id]
	return best


## The contract coverage Services adds: kind -> [{"node", "offset", "reach"}].
func coverage() -> Dictionary:
	var out := {}
	for id in _ids():
		var d: Dictionary = deals[id]
		if d.role != "served" or not COVERAGE.has(d.kind) or int(d.offset) < 0:
			continue
		var k: int = COVERAGE[d.kind]
		if not out.has(k):
			out[k] = []
		out[k].append({"node": int(d.link), "offset": float(d.offset), "reach": float(Balance.INTERLOCAL[d.kind].reach)})
	return out


## Hands the coverage to Services; lots are re-figured on the next step.
func refresh(sim) -> void:
	var c := coverage()
	if c != sim.services.contracts:
		sim.services.contracts = c
		sim._lots_dirty = true


# --- Each town's own half --------------------------------------------------------

func tick(sim) -> void:
	if deals.is_empty() and trips.is_empty():
		return
	if not sim.simulate_traffic:
		if sim.tick_count % EVERY == 0:
			_offstage(sim)
		return
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			var run: Dictionary = trips[a.id]
			trips.erase(a.id)
			_arrive(sim, run)
	for f in sim.traffic.failed:
		if trips.has(f.id):
			var run: Dictionary = trips[f.id]
			trips.erase(f.id)
			if run.has("seg"):
				sim.hubs.claimed.erase(run.seg)
	var hour := int(sim.tick_count / CitySim.TICKS_PER_HOUR) % 24
	var on_hour: bool = sim.tick_count % CitySim.TICKS_PER_HOUR == 0
	for id in _ids():
		var d: Dictionary = deals[id]
		if int(d.offset) < 0 or not sim.network.nodes.has(int(d.link)):
			continue
		match [d.kind, d.role]:
			["trash", "served"]:
				if sim.tick_count % EVERY == 0:
					_send_pickup(sim, d)
			["trash", "host"]:
				if sim.tick_count % EVERY == 0:
					_send_haul(sim, d)
			["school", "served"]:
				if on_hour and hour in BUS_HOURS:
					_send_buses(sim, d)
			["school", "host"]:
				# The host's bus leaves its school half an hour earlier.
				if sim.tick_count % CitySim.TICKS_PER_HOUR == CitySim.TICKS_PER_HOUR / 2 and (hour + 1) in BUS_HOURS:
					_send_host_buses(sim, d)


func _out(deal_id: String, what: String) -> int:
	return trips.values().filter(func(r): return r.deal == deal_id and r.what == what).size()


## Contract garbage trucks come in from the county road to the fullest street.
func _send_pickup(sim, d: Dictionary) -> void:
	if _out(d.id, "pickup") >= Balance.INTERLOCAL_TRASH_TRUCKS:
		return
	var curb: Dictionary = sim.hubs._curbs(sim)
	var best := -1
	var segs: Array = sim.hubs.trash.keys()
	segs.sort()
	for seg in segs:
		if sim.hubs.trash[seg] < Balance.GARBAGE_STOP_LB or sim.hubs.claimed.has(seg) or not curb.has(seg):
			continue
		if best == -1 or sim.hubs.trash[seg] > sim.hubs.trash[best]:
			best = seg
	if best == -1:
		return
	var at := _link_xz(sim, d)
	_go(sim, {"deal": d.id, "what": "pickup", "seg": best, "load": 0.0, "stops": 0, "at": at},
		_xz(curb[best]), "garbage", {"good": "trash", "amount": 0, "for": d.other_name})


## The host's trucks drive out to the county road and come back loaded.
func _send_haul(sim, d: Dictionary) -> void:
	if float(d.haul) < 0.5 or _out(d.id, "haul") >= Balance.INTERLOCAL_TRASH_TRUCKS:
		return
	var site := _site(sim, "trash", int(d.link))
	if site.is_empty():
		return
	var tons := minf(float(d.haul), Balance.GARBAGE_TRUCK_LB / 2000.0)
	d.haul = float(d.haul) - tons
	_go(sim, {"deal": d.id, "what": "haul", "leg": 0, "tons": tons, "home": [site[0], site[1]], "hub": site[2],
		"at": [site[0], site[1]]}, _link_xz(sim, d), "garbage", {"good": "trash", "amount": 0, "for": d.other_name})


## The host's school buses head out to the county road for the children.
func _send_host_buses(sim, d: Dictionary) -> void:
	var site := _site(sim, "school", int(d.link))
	if site.is_empty():
		return
	for i in _buses(int(d.get("homes", 0))) - _out(d.id, "bus"):
		_go(sim, {"deal": d.id, "what": "bus", "legs": [_link_xz(sim, d), [site[0], site[1]]], "leg": 0,
			"at": [site[0], site[1]]}, _link_xz(sim, d), "school", {"good": "pupils", "amount": 0, "for": d.other_name})


## The served town's run: in from the county road, stops on the streets
## with the most homes, and back out to the host's school.
func _send_buses(sim, d: Dictionary) -> void:
	var stops := _bus_stops(sim)
	if stops.is_empty():
		return
	var n := _buses(homes(sim))
	for i in n - _out(d.id, "bus"):
		var legs := []
		for j in range(i, stops.size(), n):
			legs.append(stops[j])
		if legs.is_empty():
			break
		legs.append(_link_xz(sim, d))
		_go(sim, {"deal": d.id, "what": "bus", "legs": legs, "leg": 0, "at": _link_xz(sim, d)},
			legs[0], "school", {"good": "pupils", "amount": 0, "for": d.other_name})


static func _buses(n_homes: int) -> int:
	return clampi(ceili(float(n_homes) / Balance.INTERLOCAL_HOMES_PER_BUS), 1, Balance.INTERLOCAL_MAX_BUSES)


## The curbs of the streets with the most homes, most first.
static func _bus_stops(sim) -> Array:
	var count := {}
	var front := {}
	var keys: Array = sim.buildings.keys()
	keys.sort()
	for key in keys:
		if sim.buildings[key].zone != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		var seg: int = sim.lots[key].seg
		count[seg] = count.get(seg, 0) + 1
		if not front.has(seg):
			front[seg] = sim.lots[key].front
	var segs := count.keys()
	segs.sort_custom(func(a, b): return count[a] > count[b] or (count[a] == count[b] and a < b))
	return segs.slice(0, Balance.INTERLOCAL_BUS_STOPS).map(func(s): return _xz(front[s]))


func _go(sim, run: Dictionary, to: Array, purpose: String, cargo: Dictionary) -> bool:
	var trip: int = sim.traffic.dispatch({"ref": "deal:%s" % run.deal, "pos": run.at},
		{"ref": "deal:%s" % run.deal, "pos": to}, purpose, cargo)
	if trip == -1:
		return false
	trips[trip] = run
	if run.what == "pickup":
		sim.hubs.claimed[run.seg] = true
	return true


func _arrive(sim, run: Dictionary) -> void:
	if not deals.has(run.deal):
		return  # the deal ended while it drove: it parks where it is
	var d: Dictionary = deals[run.deal]
	match run.what:
		"pickup":
			_pickup(sim, d, run)
		"haul":
			if run.leg == 0:
				# At the county road: loaded with the neighbor's trash, back home.
				run.leg = 1
				run.at = _link_xz(sim, d)
				_go(sim, run, run.home, "garbage", {"good": "trash", "amount": roundi(run.tons), "for": "landfill"})
			elif sim.hubs.hubs.has(run.hub):
				sim.hubs.hubs[run.hub].received += float(run.tons) * 2000.0
		"bus":
			run.at = run.legs[run.leg]
			run.leg += 1
			if run.leg < run.legs.size():
				_go(sim, run, run.legs[run.leg], "school", {"good": "pupils", "amount": 0, "for": d.other_name})


## A contract truck at a street: takes what's out, then the next street
## nearby, and when it's full or done heads back out the county road.
func _pickup(sim, d: Dictionary, run: Dictionary) -> void:
	if run.seg == -1:
		d.picked = float(d.picked) + float(run.load) / 2000.0
		return
	var seg: int = run.seg
	sim.hubs.claimed.erase(seg)
	var take := minf(sim.hubs.trash.get(seg, 0.0), Balance.GARBAGE_TRUCK_LB - float(run.load))
	if sim.hubs.trash.has(seg):
		sim.hubs.trash[seg] -= take
	run.load = float(run.load) + take
	run.stops = int(run.stops) + 1
	var curb: Dictionary = sim.hubs._curbs(sim)
	run.at = _xz(curb.get(seg, Vector3(run.at[0], 0.0, run.at[1])))
	if run.load < Balance.GARBAGE_TRUCK_LB * 0.9 and run.stops < Balance.GARBAGE_STOPS_PER_RUN:
		var here := Vector3(run.at[0], 0.0, run.at[1])
		var next := -1
		var next_d: float = CivicHubs.NEXT_STOP_REACH
		var segs: Array = sim.hubs.trash.keys()
		segs.sort()
		for s in segs:
			if sim.hubs.trash[s] < Balance.GARBAGE_STOP_LB * 0.5 or sim.hubs.claimed.has(s) or not curb.has(s):
				continue
			var dist: float = curb[s].distance_to(here)
			if dist < next_d:
				next_d = dist
				next = s
		if next != -1:
			run.seg = next
			if _go(sim, run, _xz(curb[next]), "garbage", {"good": "trash", "amount": roundi(run.load / 2000.0), "for": d.other_name}):
				return
	run.seg = -1
	if not _go(sim, run, _link_xz(sim, d), "garbage", {"good": "trash", "amount": roundi(run.load / 2000.0), "for": d.other_name}):
		d.picked = float(d.picked) + float(run.load) / 2000.0


## Without cars (the balance harness): the contract still takes the trash.
func _offstage(sim) -> void:
	var d := served_by("trash")
	if d.is_empty() or int(d.offset) < 0:
		return
	var room: float = Balance.GARBAGE_TRUCK_LB * Balance.INTERLOCAL_TRASH_TRUCKS
	var segs: Array = sim.hubs.trash.keys()
	segs.sort()
	for seg in segs:
		var take := minf(sim.hubs.trash[seg], room)
		sim.hubs.trash[seg] -= take
		room -= take
		d.picked = float(d.picked) + take / 2000.0
	for id in deals:
		var h: Dictionary = deals[id]
		if h.kind == "trash" and h.role == "host" and float(h.haul) > 0.0:
			var site := _site(sim, "trash", int(h.link))
			if not site.is_empty():
				sim.hubs.hubs[site[2]].received += float(h.haul) * 2000.0
			h.haul = 0.0


func _link_xz(sim, d: Dictionary) -> Array:
	return _xz(sim.network.nodes[int(d.link)])


static func _xz(p: Vector3) -> Array:
	return [p.x, p.z]


func _ids() -> Array:
	var ids := deals.keys()
	ids.sort()
	return ids


# --- The region's ledger: offers on both bells -----------------------------------
# Agreements live in the region's ledger (Ledger, kept by the region server
# and sent to every player). This computer runs only its own town's half:
# sync reads the ledger and the neighbors' latest copies, files offers on
# this town's bell, and hands back what to tell the server.

## Host side: agreement id -> the neighbor's trash (tons) already brought home.
var seen := {}
## Agreement id -> the tick this town first saw the neighbor turn it down.
var told_no := {}
## The last game month notice was counted down.
var month := -1
## Offers sent that the ledger doesn't show yet: "kind:other" -> tick sent.
var _pending := {}


## Brings this town's deals in line with the region's ledger. Called when the
## ledger changes and every game hour. Returns the actions for the server:
##   {"op": "offer", "to", "service", "price", "capacity"}
##   {"op": "answer", "id", "yes"}
##   {"op": "end", "id"}
func sync(region, me: String, sim) -> Array:
	var acts := []
	var links: Dictionary = region.trade_links()
	var mine: Dictionary = links.get(me, {})
	var live := {}
	var ids: Array = region.ledger.agreements.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = region.ledger.agreements[aid]
		if not KINDS.has(a.service) or not me in [a.host, a.client]:
			continue
		var other: String = a.client if a.host == me else a.host
		match str(a.status):
			"active":
				live[a.id] = true
				_keep(region, me, sim, a, other, links)
			"offered":
				if a.client == me:
					_ask(region, sim, a, other, mine, acts)
			_:
				var req := _request(sim, "agreement", a.id)
				if not req.is_empty() and int(req.state) in [Permits.State.OPEN, Permits.State.SHELVED]:
					sim.permits.withdraw(int(req.id))
				if a.status == "denied" and a.host == me and not told_no.has(a.id):
					told_no[a.id] = int(sim.tick_count)
	for id in deals.keys():
		if not live.has(id):
			deals.erase(id)
			seen.erase(id)
	# Notice runs out a month at a time; at the end, the deal ends.
	var m := int(sim.tick_count / (24 * CitySim.TICKS_PER_HOUR))
	if month < 0 or m < month:
		month = m
	while month < m:
		month += 1
		for id in deals:
			if int(deals[id].left) > 0:
				deals[id].left = int(deals[id].left) - 1
	for id in _ids():
		if int(deals[id].left) == 0:
			acts.append({"op": "end", "id": id})
	# Offers this town's leaders made that the player approved go out.
	for rid in sim.permits.requests:
		var q: Dictionary = sim.permits.requests[rid]
		if q.hub == "interlocal" and q.get("deal", {}).has("key") and int(q.state) == Permits.State.APPROVED:
			acts.append({"op": "offer", "to": str(q.deal.other), "service": str(q.deal.kind),
				"price": float(q.deal.fee), "capacity": float(maxi(int(q.deal.get("homes", 1)), 1))})
			sim.permits.done(int(rid))
			_pending[str(q.deal.key)] = int(sim.tick_count)
	_new_offers(region, me, sim, links, acts)
	refresh(sim)
	return acts


## An active agreement: this town's half of it, on the ledger's terms, with
## what changed over there (the host's station, the town's homes, trash
## picked up, notice given) from the neighbor's latest copy.
func _keep(region, me: String, sim, a: Dictionary, other: String, links: Dictionary) -> void:
	var host: bool = a.host == me
	var them = region.cities[other].sim if region.cities.has(other) else null
	var d: Dictionary = deals.get(a.id, {})
	if d.is_empty():
		d = {"id": a.id, "kind": a.service, "role": "host" if host else "served", "other": other,
			"other_name": "", "fee": 0, "link": -1, "offset": -1, "left": -1, "picked": 0.0, "haul": 0.0, "homes": 0}
		deals[a.id] = d
		var req := _request(sim, "agreement", a.id)
		if not req.is_empty():
			sim.permits.done(int(req.id))
	d.fee = roundi(float(a.price_per_month))
	d.link = int(links.get(me, {}).get(other, d.link))
	if region.cities.has(other):
		d.other_name = str(region.cities[other].name)
	var their_deal: Dictionary = them.interlocal.deals.get(a.id, {}) if them else {}
	if host:
		d.offset = offset(sim, d.kind, int(d.link))
		if them:
			d.homes = homes(them)
		# The neighbor's trash picked up since last time comes home with our trucks.
		var picked := float(their_deal.get("picked", 0.0))
		d.haul = float(d.haul) + maxf(picked - float(seen.get(a.id, 0.0)), 0.0)
		seen[a.id] = maxf(picked, float(seen.get(a.id, 0.0)))
	else:
		d.homes = homes(sim)
		if them:
			d.offset = offset(them, d.kind, int(links.get(other, {}).get(me, -1)))
	if int(d.left) < 0 and int(their_deal.get("left", -1)) >= 0:
		d.left = int(their_deal.left)


## A neighbor's offer to this town: on the bell until the player answers.
func _ask(region, sim, a: Dictionary, other: String, mine: Dictionary, acts: Array) -> void:
	var req := _request(sim, "agreement", a.id)
	if req.is_empty():
		var info: Dictionary = KINDS[a.service]
		var host_name: String = region.cities[other].name if region.cities.has(other) else "A neighbor"
		var money := CitySim.money_text(roundi(float(a.price_per_month)))
		var at := []
		if sim.network.nodes.has(int(mine.get(other, -1))):
			at = [_xz(sim.network.nodes[int(mine[other])])]
		sim.permits.file(sim, {"hub": "interlocal", "hub_id": _hub_id("agreement:" + a.id),
			"leader": "%s %s (%s)" % [info.title, _name(hash([other, a.service])), host_name],
			"title": "%s offers us %s" % [host_name, info.name],
			"why": "We'd serve your town from %s over the county road, for $%s a month: your share of our cost, by homes." % [
				host_name, money],
			"route": at, "deal": {"kind": a.service, "fee": roundi(float(a.price_per_month)), "other": other,
				"pays": true, "agreement": a.id}})
		return
	match int(req.state):
		Permits.State.APPROVED:
			acts.append({"op": "answer", "id": a.id, "yes": true})
		Permits.State.DENIED, Permits.State.WITHDRAWN:
			acts.append({"op": "answer", "id": a.id, "yes": false})


## Each of this town's leaders looks at the towns joined to it by county road
## and offers what one of them lacks: on this town's bell first, and to the
## neighbor once the player approves. One offer per service per town at a time.
func _new_offers(region, me: String, sim, links: Dictionary, acts: Array) -> void:
	var near: Array = links.get(me, {}).keys()
	near.sort()
	for other in near:
		if not region.cities.has(other):
			continue
		var them = region.cities[other].sim
		var link: int = links[me][other]
		if not them.network.nodes.has(int(links.get(other, {}).get(me, -1))):
			continue
		for kind in KINDS:
			if _taken(region, me, kind, other, sim) or not needs(them, kind):
				continue
			if offset(sim, kind, link) < 0:
				continue
			if kind == "trash" and sim.permits.guidance("hub", int(_site(sim, kind, link)[2])).stance == "hold":
				continue
			var info: Dictionary = KINDS[kind]
			var f := fee(kind, homes(sim), homes(them))
			sim.permits.file(sim, {"hub": "interlocal", "hub_id": _hub_id("offer:%s:%s" % [kind, other]),
				"leader": "%s %s" % [info.title, _name(hash([me, kind]))],
				"title": "Offer %s to %s" % [info.name, region.cities[other].name],
				"why": "%s has no %s of its own. We can cover it over the county road for $%s a month, our cost shared by homes." % [
					region.cities[other].name, _lacks(kind), CitySim.money_text(f)],
				"route": [_xz(sim.network.nodes[link])],
				"deal": {"kind": kind, "fee": f, "other": other, "key": "%s:%s" % [kind, other], "homes": homes(them)}})


## True when the town is already served, offered or being asked about this
## service, or turned this town down for it lately.
func _taken(region, me: String, kind: String, other: String, sim) -> bool:
	for a in region.ledger.agreements.values():
		if a.service != kind or a.client != other:
			continue
		if a.status in ["offered", "active"]:
			_pending.erase("%s:%s" % [kind, other])
			return true
		if a.host == me and int(sim.tick_count) - int(told_no.get(a.id, -(1 << 40))) \
				< Balance.INTERLOCAL_RETRY * 24 * CitySim.TICKS_PER_HOUR:
			return true
	var key := "%s:%s" % [kind, other]
	if int(sim.tick_count) - int(_pending.get(key, -(1 << 40))) < 24 * CitySim.TICKS_PER_HOUR:
		return true
	var req := _request(sim, "key", key)
	return not req.is_empty() and int(req.state) in [Permits.State.OPEN, Permits.State.SHELVED, Permits.State.APPROVED]


## This town's latest bell request whose deal has this field, or {}.
static func _request(sim, field: String, value: String) -> Dictionary:
	var best := {}
	for rid in sim.permits.requests:
		var q: Dictionary = sim.permits.requests[rid]
		if q.hub == "interlocal" and str(q.get("deal", {}).get(field, "")) == value:
			if best.is_empty() or int(q.id) > int(best.id):
				best = q
	return best


## A steady bell id for an offer, so the bell keeps one per offer.
static func _hub_id(key: String) -> int:
	return absi(hash(key)) % 1_000_000_000


static func _lacks(kind: String) -> String:
	return {"trash": "landfill", "fire": "fire station", "police": "police station", "school": "school"}[kind]


static func _name(seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return "%s %s" % [Power.FIRST_NAMES[rng.randi() % Power.FIRST_NAMES.size()],
		Power.LAST_NAMES[rng.randi() % Power.LAST_NAMES.size()]]


# --- Saving -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list := []
	for id in _ids():
		list.append(deals[id])
	# Vehicles out on runs come back with the save (exact types).
	return {"deals": list, "trips": var_to_str(trips), "seen": seen, "told_no": told_no, "month": month}


func from_dict(d: Dictionary) -> void:
	deals.clear()
	trips.clear()
	for x in d.get("deals", []):
		deals[str(x.id)] = {"id": str(x.id), "kind": str(x.kind), "role": str(x.role), "other": str(x.other),
			"other_name": str(x.get("other_name", "")), "fee": int(x.fee), "link": int(x.link),
			"offset": int(x.get("offset", -1)), "left": int(x.get("left", -1)), "picked": float(x.get("picked", 0.0)),
			"haul": float(x.get("haul", 0.0)), "homes": int(x.get("homes", 0))}
	if d.has("trips"):
		var t = str_to_var(str(d.trips))
		if t is Dictionary:
			trips = t
	seen = {}
	for k in d.get("seen", {}):
		seen[str(k)] = float(d.seen[k])
	told_no = {}
	for k in d.get("told_no", {}):
		told_no[str(k)] = int(d.told_no[k])
	month = int(d.get("month", -1))
