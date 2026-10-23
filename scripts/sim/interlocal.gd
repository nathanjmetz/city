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
## while either player is away. The region server keeps the ledger: once a
## game month (Interlocal.region_step, with its latest copy of every town)
## it files new offers, signs deals both towns approved, and passes on each
## month's numbers (trash picked up, the station's distance, notice to
## end). What changes for a town goes to it as a short list of steps
## (receive), held for a player who is away until they're back.

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
## The region sees it and ends the deal on both sides after the notice.
func end(sim, id: int) -> bool:
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


func _out(deal_id: int, what: String) -> int:
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
	var trip: int = sim.traffic.dispatch({"ref": "deal:%d" % run.deal, "pos": run.at},
		{"ref": "deal:%d" % run.deal, "pos": to}, purpose, cargo)
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


# --- What the region sends this town ----------------------------------------------

## Takes the region's steps for this town, in order (see region_step):
##   {"op": "offer", "id", "kind", "fee", "other", "pays", "leader", "title", "why", "link"}
##   {"op": "withdraw", "id"}
##   {"op": "sign", "deal": {...}}
##   {"op": "update", "id", "fee", "offset", "homes", "left", "haul_add"}
##   {"op": "end", "id"}
## Every step is safe to take twice except "haul_add", which the region
## sends only once: to the town's computer if it's running, otherwise into
## the region's copy of the town, which is what its player starts from.
func receive(sim, ops: Array) -> void:
	for op in ops:
		var id := int(op.get("id", op.get("deal", {}).get("id", -1)))
		match str(op.get("op", "")):
			"offer":
				if _request(sim, id).is_empty():
					var deal := {"kind": str(op.kind), "fee": int(op.fee), "other": str(op.other)}
					if bool(op.get("pays", false)):
						deal.pays = true
					sim.permits.file(sim, {"hub": "interlocal", "hub_id": id, "leader": str(op.leader),
						"title": str(op.title), "why": str(op.why), "route": op.get("at", []), "deal": deal})
			"withdraw":
				var req := _request(sim, id)
				if not req.is_empty():
					sim.permits.withdraw(int(req.id))
			"sign":
				var d: Dictionary = op.deal
				deals[id] = {"id": id, "kind": str(d.kind), "role": str(d.role), "other": str(d.other),
					"other_name": str(d.other_name), "fee": int(d.fee), "link": int(d.link),
					"offset": int(d.offset), "left": -1, "picked": 0.0, "haul": 0.0, "homes": int(d.homes)}
				var req := _request(sim, id)
				if not req.is_empty():
					sim.permits.done(int(req.id))
			"update":
				if deals.has(id):
					var d: Dictionary = deals[id]
					for k in ["fee", "offset", "homes", "left"]:
						if op.has(k):
							d[k] = int(op[k])
					d.haul = float(d.haul) + float(op.get("haul_add", 0.0))
			"end":
				deals.erase(id)
	refresh(sim)


## This town's bell request for a deal offer, or {}.
static func _request(sim, id: int) -> Dictionary:
	for rid in sim.permits.requests:
		var q: Dictionary = sim.permits.requests[rid]
		if q.hub == "interlocal" and int(q.hub_id) == id:
			return q
	return {}


static func _state(sim, id: int) -> int:
	var q := _request(sim, id)
	return -1 if q.is_empty() else int(q.state)


# --- The region: offers, signing and each month's numbers --------------------------
# Runs on the region server, with its latest copy of every town (a town
# whose player is away keeps its last copy). The ledger lives in the Region:
#   r.pacts     offers waiting on both bells: id -> {kind, host, served, fee,
#               host_link, served_link, offset, homes, made}
#   r.deals     signed deals: id -> {kind, host, served, fee, host_link,
#               served_link, offset, homes, priced, left, seen}
#   r.month, r.next_pact, r.pact_wait ("kind:host:served" -> month)

## One game month of deals. Returns each town's steps (city id -> [steps])
## for the server to send to the towns that are running, and takes them on
## the region's own copies too: a town whose player is away starts from
## that copy when they're back.
static func region_step(r) -> Dictionary:
	r.month += 1
	var links: Dictionary = r.trade_links()
	var ops := {}
	_settle_offers(r, ops)
	_carry_over(r, ops)
	_new_offers(r, links, ops)
	for id in ops:
		if r.cities.has(id):
			r.cities[id].sim.interlocal.receive(r.cities[id].sim, ops[id])
	return ops


static func _send(ops: Dictionary, city: String, op: Dictionary) -> void:
	if not ops.has(city):
		ops[city] = []
	ops[city].append(op)


static func _sim(r, id: String):
	return r.cities[id].sim if r.cities.has(id) else null


## Offers both towns approved become deals; one either town turned down (or
## let sit until shelved) is dropped, and not offered again for a while.
## An offer a town hasn't filed yet (away, or its bell was full) is sent again.
static func _settle_offers(r, ops: Dictionary) -> void:
	var ids: Array = r.pacts.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = r.pacts[pid]
		var hs = _sim(r, p.host)
		var ss = _sim(r, p.served)
		if hs == null or ss == null:
			r.pacts.erase(pid)
			continue
		var a: int = _state(hs, pid)
		var b: int = _state(ss, pid)
		var ok := [Permits.State.APPROVED, Permits.State.DONE]
		if a in ok and b in ok:
			r.deals[pid] = {"kind": p.kind, "host": p.host, "served": p.served, "fee": int(p.fee),
				"host_link": int(p.host_link), "served_link": int(p.served_link), "offset": int(p.offset),
				"homes": int(p.homes), "priced": int(r.month), "left": -1, "seen": 0.0}
			for side in [["host", p.host, p.served, int(p.host_link)], ["served", p.served, p.host, int(p.served_link)]]:
				_send(ops, side[1], {"op": "sign", "deal": {"id": int(pid), "kind": p.kind, "role": side[0],
					"other": side[2], "other_name": r.cities[side[2]].name, "fee": int(p.fee), "link": side[3],
					"offset": int(p.offset), "homes": int(p.homes)}})
			r.pacts.erase(pid)
		elif a in [Permits.State.DENIED, Permits.State.SHELVED, Permits.State.WITHDRAWN] \
				or b in [Permits.State.DENIED, Permits.State.SHELVED, Permits.State.WITHDRAWN]:
			_send(ops, p.host, {"op": "withdraw", "id": int(pid)})
			_send(ops, p.served, {"op": "withdraw", "id": int(pid)})
			r.pact_wait[_pair(p.kind, p.host, p.served)] = int(r.month) + Balance.INTERLOCAL_RETRY
			r.pacts.erase(pid)
		else:
			# Not on a bell yet: send it again.
			if a == -1:
				_send(ops, p.host, p.host_offer)
			if b == -1:
				_send(ops, p.served, p.served_offer)


## Each signed deal's month: trash picked up goes to the host to haul home,
## the host's station distance comes over, notice to end counts down, and
## once a year the fee is re-figured.
static func _carry_over(r, ops: Dictionary) -> void:
	var ids: Array = r.deals.keys()
	ids.sort()
	for did in ids:
		var d: Dictionary = r.deals[did]
		var hs = _sim(r, d.host)
		var ss = _sim(r, d.served)
		if hs == null or ss == null:
			r.deals.erase(did)
			for c in [d.host, d.served]:
				_send(ops, c, {"op": "end", "id": int(did)})
			continue
		var mine_h: Dictionary = hs.interlocal.deals.get(did, {})
		var mine_s: Dictionary = ss.interlocal.deals.get(did, {})
		# Notice from either town starts the count; it ends when it runs out.
		if int(d.left) < 0 and (int(mine_h.get("left", -1)) >= 0 or int(mine_s.get("left", -1)) >= 0):
			d.left = Balance.INTERLOCAL_NOTICE
		elif int(d.left) >= 0:
			d.left = int(d.left) - 1
		if int(d.left) == 0:
			r.deals.erase(did)
			for c in [d.host, d.served]:
				_send(ops, c, {"op": "end", "id": int(did)})
			continue
		var picked := float(mine_s.get("picked", d.seen))
		var haul := maxf(picked - float(d.seen), 0.0)
		d.seen = maxf(picked, float(d.seen))
		d.offset = offset(hs, d.kind, int(d.host_link))
		d.homes = homes(ss)
		if int(r.month) - int(d.priced) >= Balance.INTERLOCAL_REPRICE:
			d.fee = fee(d.kind, homes(hs), homes(ss))
			d.priced = r.month
		var up := {"op": "update", "id": int(did), "fee": int(d.fee), "offset": int(d.offset), "homes": int(d.homes),
			"left": int(d.left)}
		_send(ops, d.served, up)
		var host_up: Dictionary = up.duplicate()
		host_up.haul_add = haul
		_send(ops, d.host, host_up)


## Each host leader looks at the towns joined to it by county road and
## offers what one of them lacks. One offer per service per town at a time.
static func _new_offers(r, links: Dictionary, ops: Dictionary) -> void:
	var hosts: Array = links.keys()
	hosts.sort()
	for host in hosts:
		var hs = _sim(r, host)
		if hs == null:
			continue
		var near: Array = links[host].keys()
		near.sort()
		for served in near:
			var ss = _sim(r, served)
			if ss == null:
				continue
			for kind in KINDS:
				if _taken(r, kind, served) or int(r.month) < int(r.pact_wait.get(_pair(kind, host, served), -1)):
					continue
				if not needs(ss, kind):
					continue
				var host_link: int = links[host][served]
				var served_link: int = links[served].get(host, -1)
				var off := offset(hs, kind, host_link)
				if off < 0 or not ss.network.nodes.has(served_link):
					continue
				if kind == "trash":
					var site := _site(hs, kind, host_link)
					if hs.permits.guidance("hub", int(site[2])).stance == "hold":
						continue
				_offer(r, ops, kind, host, served, host_link, served_link, off)


## True when a town already has, or is being offered, this service.
static func _taken(r, kind: String, served: String) -> bool:
	for book in [r.pacts, r.deals]:
		for id in book:
			if book[id].kind == kind and book[id].served == served:
				return true
	return false


## Sends the offer to both bells.
static func _offer(r, ops: Dictionary, kind: String, host: String, served: String, host_link: int,
		served_link: int, off: int) -> void:
	var hs = _sim(r, host)
	var ss = _sim(r, served)
	var pid: int = r.next_pact
	r.next_pact = pid + 1
	var f := fee(kind, homes(hs), homes(ss))
	var info: Dictionary = KINDS[kind]
	var host_name: String = r.cities[host].name
	var served_name: String = r.cities[served].name
	var who := "%s %s (%s)" % [info.title, _name(hash([r.region_seed, host, kind])), host_name]
	var money := CitySim.money_text(f)
	var host_offer := {"op": "offer", "id": pid, "kind": kind, "fee": f, "other": served, "leader": who,
		"title": "Offer %s to %s" % [info.name, served_name],
		"why": "%s has no %s of its own. We can cover it over the county road for $%s a month, our cost shared by homes." % [
			served_name, _lacks(kind), money],
		"at": [_xz(hs.network.nodes[host_link])]}
	var served_offer := {"op": "offer", "id": pid, "kind": kind, "fee": f, "other": host, "pays": true, "leader": who,
		"title": "%s offers us %s" % [host_name, info.name],
		"why": "We'd serve your town from %s over the county road, for $%s a month: your share of our cost, by homes." % [
			host_name, money],
		"at": [_xz(ss.network.nodes[served_link])]}
	r.pacts[pid] = {"kind": kind, "host": host, "served": served, "fee": f, "host_link": host_link,
		"served_link": served_link, "offset": off, "homes": homes(ss), "made": int(r.month),
		"host_offer": host_offer, "served_offer": served_offer}
	_send(ops, host, host_offer)
	_send(ops, served, served_offer)


static func _lacks(kind: String) -> String:
	return {"trash": "landfill", "fire": "fire station", "police": "police station", "school": "school"}[kind]


static func _name(seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return "%s %s" % [Power.FIRST_NAMES[rng.randi() % Power.FIRST_NAMES.size()],
		Power.LAST_NAMES[rng.randi() % Power.LAST_NAMES.size()]]


static func _pair(kind: String, host: String, served: String) -> String:
	return "%s:%s:%s" % [kind, host, served]


## The region's ledger for saving: plain JSON, so int keys come back as
## strings and load_ledger turns them back.
static func ledger_to_dict(r) -> Dictionary:
	return {"pacts": r.pacts, "deals": r.deals, "month": r.month, "next": r.next_pact, "wait": r.pact_wait}


static func load_ledger(r, d: Dictionary) -> void:
	r.pacts = {}
	r.deals = {}
	for pair in [[r.pacts, d.get("pacts", {})], [r.deals, d.get("deals", {})]]:
		for k in pair[1]:
			var e: Dictionary = pair[1][k].duplicate(true)
			for f in ["fee", "host_link", "served_link", "offset", "homes", "made", "priced", "left"]:
				if e.has(f):
					e[f] = int(e[f])
			for o in ["host_offer", "served_offer"]:
				if e.has(o):
					e[o].id = int(e[o].id)
					e[o].fee = int(e[o].fee)
			pair[0][int(k)] = e
	r.month = int(d.get("month", 0))
	r.next_pact = int(d.get("next", 1))
	r.pact_wait = {}
	for k in d.get("wait", {}):
		r.pact_wait[str(k)] = int(d.wait[k])


# --- Saving -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list := []
	for id in _ids():
		list.append(deals[id])
	# Vehicles out on runs come back with the save (exact types).
	return {"deals": list, "trips": var_to_str(trips)}


func from_dict(d: Dictionary) -> void:
	deals.clear()
	trips.clear()
	for x in d.get("deals", []):
		deals[int(x.id)] = {"id": int(x.id), "kind": str(x.kind), "role": str(x.role), "other": str(x.other),
			"other_name": str(x.get("other_name", "")), "fee": int(x.fee), "link": int(x.link),
			"offset": int(x.get("offset", -1)), "left": int(x.get("left", -1)), "picked": float(x.get("picked", 0.0)),
			"haul": float(x.get("haul", 0.0)), "homes": int(x.get("homes", 0))}
	if d.has("trips"):
		var t = str_to_var(str(d.trips))
		if t is Dictionary:
			trips = t
