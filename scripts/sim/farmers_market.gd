class_name FarmersMarket
extends RefCounted
## The Saturday farmers' market (Brawn's pick #19, after Farthest Frontier's
## and Anno's markets): from May through October, farm families load a
## pickup with sweet corn, tomatoes, eggs or beef and drive to town to sell
## from a stall. It sets up on the courthouse square, or with no courthouse
## under the shelter of the town's park, as Indiana markets do (numbers in
## Balance FARMERS_MARKET_*).
##
## Each pickup is a real trip: it leaves the farm in time to be set up when
## the market opens, parks by the square, and drives home after. What a
## stall sells goes into its farm's own cash. Tents stand on the square
## through the market day (ParkBuilder draws them). Deterministic: which
## farms come follows from the town's seed, the farm and the year.

## Ticks between looks (the calendar day is Seasons.TICKS_PER_DAY ticks).
const EVERY := 10
## A pickup sets out this much earlier than its drive takes, so it's set up
## by opening (ticks and a share of the drive).
const LEAD := 30
const MARGIN := 1.3

## The market day being worked on (a calendar day index), -1 for none.
var day := -1
## Farms selling that day, sorted.
var vendors := []
## Farms whose pickup has set out, and those that got there.
var sent := {}
var arrived := []
## The park site it's held at (-1 for none) and whether it's on now.
var venue := -1
var open := false
## The last market: {"day", "vendors", "sales"}; and this year's sales.
var last := {}
var season_sales := 0
var _season_year := -1
## Traffic trip id -> farm id.
var trips := {}
var _eta := {}
var _eta_roads := []


func tick(sim) -> void:
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			_arrive(sim, int(trips[a.id]))
			trips.erase(a.id)
	for f in sim.traffic.failed:
		trips.erase(f.id)
	if sim.tick_count % EVERY != 0:
		return
	var cal: int = sim.calendar_tick()
	var tpd := Seasons.TICKS_PER_DAY
	var today := int(floorf(float(cal) / tpd))
	# Shut at the end of its day.
	if open and today != day:
		_close(sim)
	var next := today + posmod(Balance.FARMERS_MARKET_DAY - Seasons.weekday(cal), 7)
	var start := next * tpd
	if not Seasons.month(start) in Balance.FARMERS_MARKET_MONTHS or start - cal > tpd:
		return  # no market within a day
	var v := find_venue(sim)
	if v == -1:
		return
	if next != day:
		day = next
		venue = v
		vendors = pick(sim, v, start)
		sent = {}
		arrived = []
	# Pickups set out in time to be set up by opening.
	if sim.simulate_traffic:
		var gate := _gate(sim, venue)
		for id in vendors:
			if sent.has(id) or not sim.farms.farms.has(id):
				continue
			var from := _farm_end(sim, id)
			if from.is_empty() or gate.is_empty():
				continue
			if _eta_roads != [sim.network.revision, sim.traffic.version]:
				_eta_roads = [sim.network.revision, sim.traffic.version]
				_eta.clear()
			var key := [id, gate.pos]
			if not _eta.has(key):
				_eta[key] = sim.traffic.drive_ticks(from, gate)
			var eta: float = _eta[key]
			if is_inf(eta):
				sent[id] = true  # no road there: it stays home
				continue
			if cal >= start - eta * MARGIN - LEAD and cal < start + tpd / 2:
				var tid: int = sim.traffic.dispatch(from, gate, "market", {"good": "produce", "amount": 1}, "pickup")
				sent[id] = true
				if tid != -1:
					trips[tid] = id
	var on: bool = today == day and not vendors.is_empty() and sim.parks.sites.has(venue)
	if on != open:
		if on:
			open = true
			sim.parks_changed.emit()
		else:
			_close(sim)


## Its stalls on the square now (0 when it isn't on), for the drawing.
func stalls_at(id: int) -> int:
	return vendors.size() if open and id == venue else 0


## Where the market is held: the courthouse square, else the town park with
## a picnic shelter that has the most in it; -1 for none. Only a finished one.
static func find_venue(sim) -> int:
	var ids: Array = sim.parks.sites.keys()
	ids.sort()
	var best := -1
	var best_n := -1
	for id in ids:
		var s: Dictionary = sim.parks.sites[id]
		if not sim.construction.is_done("park:%d" % id, sim.tick_count):
			continue
		if s.kind == "courthouse":
			return id
		if s.kind == "park" and s.features.any(func(f): return f.type == "pavilion") and s.features.size() > best_n:
			best_n = s.features.size()
			best = id
	return best


## The farms that come on the market day starting at calendar tick `start`.
static func pick(sim, v: int, start: int) -> Array:
	var out := []
	var ids: Array = sim.farms.farms.keys()
	ids.sort()
	var at: Vector3 = sim.parks.sites[v].pos
	var year := Seasons.year(start)
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		if f.drive.is_empty() or Vector2(f.drive[-1].x - at.x, f.drive[-1].z - at.z).length() > Balance.FARMERS_MARKET_REACH:
			continue
		if posmod(hash([sim.city_seed, id, year, "market"]), 100) < Balance.FARMERS_MARKET_SHARE:
			out.append(id)
		if out.size() >= Balance.FARMERS_MARKET_MAX_VENDORS:
			break
	return out


func _arrive(sim, id: int) -> void:
	if not id in arrived:
		arrived.append(id)
	var f = sim.farms.farms.get(id)
	if f != null:
		f.cash = float(f.get("cash", 0.0)) + Balance.FARMERS_MARKET_SALES
	sim.chains.count(sim.calendar_tick(), "farm", "market", "produce")


func _close(sim) -> void:
	open = false
	var year := Seasons.year(day * Seasons.TICKS_PER_DAY)
	if year != _season_year:
		_season_year = year
		season_sales = 0
	var sales: int = arrived.size() * Balance.FARMERS_MARKET_SALES
	season_sales += sales
	last = {"day": day, "vendors": arrived.size(), "sales": sales}
	vendors = []
	arrived = []
	sim.parks_changed.emit()


static func _farm_end(sim, id: int) -> Dictionary:
	var f: Dictionary = sim.farms.farms[id]
	if f.drive.is_empty():
		return {}
	return {"ref": "farm:%d" % id, "pos": Logistics._xz(f.drive[-1]), "drive": Logistics._lane(f.drive)}


## The square's front, on the street, where the pickups park.
static func _gate(sim, id: int) -> Dictionary:
	var s = sim.parks.sites.get(id)
	if s == null:
		return {}
	var p: Vector3 = s.pos + s.dir * float(s.size.y) * 0.5
	return {"ref": "market:%d" % id, "pos": Logistics._xz(p)}


func to_dict() -> Dictionary:
	var t := {}
	for id in trips:
		t[str(id)] = trips[id]
	return {"day": day, "vendors": vendors, "sent": sent.keys(), "arrived": arrived, "venue": venue, "open": open,
		"last": last, "season_sales": season_sales, "season_year": _season_year, "trips": t}


func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", -1))
	vendors = Array(d.get("vendors", [])).map(func(x): return int(x))
	sent = {}
	for id in d.get("sent", []):
		sent[int(id)] = true
	arrived = Array(d.get("arrived", [])).map(func(x): return int(x))
	venue = int(d.get("venue", -1))
	open = bool(d.get("open", false))
	last = {}
	var l: Dictionary = d.get("last", {})
	for k in l:
		last[str(k)] = int(l[k])
	season_sales = int(d.get("season_sales", 0))
	_season_year = int(d.get("season_year", -1))
	trips = {}
	var tt: Dictionary = d.get("trips", {})
	for id in tt:
		trips[int(id)] = int(tt[id])
