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
## Each town only ever simulates its own half from the deal's terms (the
## fee, the county road, how far the host's station is from it), so a deal
## keeps running on its last terms while either player is away. The region
## (Interlocal.region_step, once a game month) is the only part that looks
## at both towns: it files new offers, signs deals both sides approved, and
## passes on each month's numbers (trash tons, the station's distance,
## notice to end). With one town per computer that step is the server's.

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
## (the other town's id), "other_name", "fee" ($ a month), "signed" (tick),
## "link" (this town's county road end toward the other), "offset" (road
## metres from the host's building to the county road; -1 while the host
## has none), "ends" (tick, or -1), "priced" (tick), "tons" (trash picked up
## this month, served side), "haul" (tons still to bring back, host side)}.
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
## It runs on through the notice, then ends on both sides.
func end(sim, id: int) -> bool:
	if not deals.has(id) or int(deals[id].ends) >= 0:
		return false
	deals[id].ends = int(sim.tick_count) + Balance.INTERLOCAL_NOTICE
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
	var gone := []
	for id in _ids():
		if int(deals[id].ends) >= 0 and int(sim.tick_count) >= int(deals[id].ends):
			gone.append(id)
	for id in gone:
		deals.erase(id)
	if not gone.is_empty():
		refresh(sim)
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
		d.tons = float(d.tons) + float(run.load) / 2000.0
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
		d.tons = float(d.tons) + float(run.load) / 2000.0


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
		d.tons = float(d.tons) + take / 2000.0
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


# --- The region: offers, signing and each month's numbers --------------------------

## Once a game month, after trade. Looks at every pair of towns joined by
## county road. `r` is the Region.
static func region_step(r) -> void:
	var links: Dictionary = r.trade_links()
	_settle_offers(r)
	_carry_over(r, links)
	_new_offers(r, links)


## Offers both towns approved become deals; one either town turned down (or
## let sit until shelved) is dropped, and not offered again for a while.
static func _settle_offers(r) -> void:
	var ids: Array = r.pacts.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = r.pacts[pid]
		if not r.cities.has(p.host) or not r.cities.has(p.served):
			r.pacts.erase(pid)
			continue
		var hs = r.cities[p.host].sim
		var ss = r.cities[p.served].sim
		var a: int = hs.permits.state_of(int(p.host_req))
		var b: int = ss.permits.state_of(int(p.served_req))
		if a == Permits.State.APPROVED and b == Permits.State.APPROVED:
			hs.permits.done(int(p.host_req))
			ss.permits.done(int(p.served_req))
			var tick: int = r.tick_count
			hs.interlocal.deals[int(pid)] = _deal(pid, p, "host", p.served, r.cities[p.served].name, int(p.host_link), tick)
			ss.interlocal.deals[int(pid)] = _deal(pid, p, "served", p.host, r.cities[p.host].name, int(p.served_link), tick)
			ss.interlocal.refresh(ss)
			r.pacts.erase(pid)
		elif a in [Permits.State.OPEN, Permits.State.APPROVED] and b in [Permits.State.OPEN, Permits.State.APPROVED]:
			continue
		else:
			hs.permits.withdraw(int(p.host_req))
			ss.permits.withdraw(int(p.served_req))
			r.pact_wait[_pair(p.kind, p.host, p.served)] = int(r.tick_count) + Balance.INTERLOCAL_RETRY
			r.pacts.erase(pid)


static func _deal(pid, p: Dictionary, role: String, other: String, other_name: String, link: int, tick: int) -> Dictionary:
	return {"id": int(pid), "kind": p.kind, "role": role, "other": other, "other_name": other_name, "fee": int(p.fee),
		"signed": tick, "link": link, "offset": int(p.offset), "ends": -1, "priced": tick, "tons": 0.0, "haul": 0.0,
		"homes": int(p.homes)}


## Each signed deal's month: trash picked up goes to the host to haul home,
## the host's station distance comes over, notice to end goes both ways, and
## once a year the fee is re-figured. A deal whose other half is gone ends.
static func _carry_over(r, links: Dictionary) -> void:
	var ids: Array = r.cities.keys()
	ids.sort()
	for id in ids:
		var sim = r.cities[id].sim
		var mine: Array = sim.interlocal._ids()
		for did in mine:
			var d: Dictionary = sim.interlocal.deals[did]
			if d.role != "served":
				continue
			var host_sim = r.cities[d.other].sim if r.cities.has(d.other) else null
			var h: Dictionary = host_sim.interlocal.deals.get(did, {}) if host_sim != null else {}
			if h.is_empty():
				sim.interlocal.deals.erase(did)
				continue
			h.haul = float(h.haul) + float(d.tons)
			d.tons = 0.0
			var off := offset(host_sim, d.kind, int(h.link))
			d.offset = off
			h.offset = off
			var ends := int(d.ends) if int(h.ends) < 0 else (int(h.ends) if int(d.ends) < 0 else mini(int(d.ends), int(h.ends)))
			d.ends = ends
			h.ends = ends
			h.homes = homes(sim)
			d.homes = h.homes
			if int(r.tick_count) - int(d.priced) >= Balance.INTERLOCAL_REPRICE:
				var f := fee(d.kind, homes(host_sim), homes(sim))
				d.fee = f
				h.fee = f
				d.priced = r.tick_count
				h.priced = r.tick_count
		sim.interlocal.refresh(sim)
	# A host deal whose served half is gone ends too.
	for id in ids:
		var sim = r.cities[id].sim
		for did in sim.interlocal._ids():
			var d: Dictionary = sim.interlocal.deals[did]
			if d.role == "host" and (not r.cities.has(d.other) or not r.cities[d.other].sim.interlocal.deals.has(did)):
				sim.interlocal.deals.erase(did)


## Each host leader looks at the towns joined to it by county road and
## offers what one of them lacks. One offer per service per town at a time.
static func _new_offers(r, links: Dictionary) -> void:
	var hosts: Array = links.keys()
	hosts.sort()
	for host in hosts:
		if not r.cities.has(host):
			continue
		var hs = r.cities[host].sim
		var near: Array = links[host].keys()
		near.sort()
		for served in near:
			if not r.cities.has(served):
				continue
			var ss = r.cities[served].sim
			for kind in KINDS:
				if not ss.interlocal.served_by(kind).is_empty() or _pending(r, kind, served) \
						or int(r.tick_count) < int(r.pact_wait.get(_pair(kind, host, served), -1)):
					continue
				if not needs(ss, kind):
					continue
				var host_link: int = links[host][served]
				var off := offset(hs, kind, host_link)
				if off < 0:
					continue
				if kind == "trash":
					var site := _site(hs, kind, host_link)
					if hs.permits.guidance("hub", int(site[2])).stance == "hold":
						continue
				_offer(r, kind, host, served, host_link, int(links[served][host]), off)


static func _pending(r, kind: String, served: String) -> bool:
	for pid in r.pacts:
		if r.pacts[pid].kind == kind and r.pacts[pid].served == served:
			return true
	return false


## Files the offer on both bells. If either town's bell is full, neither
## is filed and the leader tries again next month.
static func _offer(r, kind: String, host: String, served: String, host_link: int, served_link: int, off: int) -> void:
	var hs = r.cities[host].sim
	var ss = r.cities[served].sim
	var pid: int = r.next_pact
	var f := fee(kind, homes(hs), homes(ss))
	var info: Dictionary = KINDS[kind]
	var who := "%s %s" % [info.title, _name(hash([r.region_seed, host, kind]))]
	var host_name: String = r.cities[host].name
	var served_name: String = r.cities[served].name
	var money := CitySim.money_text(f)
	var deal := {"kind": kind, "fee": f, "other": served}
	var a: int = hs.permits.file(hs, {"hub": "interlocal", "hub_id": pid, "leader": who + " (" + host_name + ")",
		"title": "Offer %s to %s" % [info.name, served_name],
		"why": "%s has no %s of its own. We can cover it over the county road for $%s a month, our cost shared by homes." % [
			served_name, _lacks(kind), money],
		"route": [_xz(hs.network.nodes[host_link])], "deal": deal})
	if a == -1:
		return
	deal = {"kind": kind, "fee": f, "other": host, "pays": true}
	var b: int = ss.permits.file(ss, {"hub": "interlocal", "hub_id": pid, "leader": who + " (" + host_name + ")",
		"title": "%s offers us %s" % [host_name, info.name],
		"why": "We'd serve your town from %s over the county road, for $%s a month: your share of our cost, by homes." % [
			host_name, money],
		"route": [_xz(ss.network.nodes[served_link])], "deal": deal})
	if b == -1:
		hs.permits.withdraw(a)
		return
	r.next_pact = pid + 1
	r.pacts[pid] = {"kind": kind, "host": host, "served": served, "fee": f, "host_req": a, "served_req": b,
		"host_link": host_link, "served_link": served_link, "offset": off, "homes": homes(ss)}


static func _lacks(kind: String) -> String:
	return {"trash": "landfill", "fire": "fire station", "police": "police station", "school": "school"}[kind]


static func _name(seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return "%s %s" % [Power.FIRST_NAMES[rng.randi() % Power.FIRST_NAMES.size()],
		Power.LAST_NAMES[rng.randi() % Power.LAST_NAMES.size()]]


static func _pair(kind: String, host: String, served: String) -> String:
	return "%s:%s:%s" % [kind, host, served]


# --- Saving -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list := []
	for id in _ids():
		list.append(deals[id])
	# Vehicles out on runs come back with the save (exact types, so every
	# copy of the region carries on the same).
	return {"deals": list, "trips": var_to_str(trips)}


func from_dict(d: Dictionary) -> void:
	deals.clear()
	trips.clear()
	for x in d.get("deals", []):
		deals[int(x.id)] = {"id": int(x.id), "kind": str(x.kind), "role": str(x.role), "other": str(x.other),
			"other_name": str(x.get("other_name", "")), "fee": int(x.fee), "signed": int(x.get("signed", 0)),
			"link": int(x.link), "offset": int(x.get("offset", -1)), "ends": int(x.get("ends", -1)),
			"priced": int(x.get("priced", 0)), "tons": float(x.get("tons", 0.0)), "haul": float(x.get("haul", 0.0)),
			"homes": int(x.get("homes", 0))}
	if d.has("trips"):
		var t = str_to_var(str(d.trips))
		if t is Dictionary:
			trips = t
