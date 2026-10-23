class_name Ledger
extends RefCounted
## The region's shared book: regional projects every town can chip in to,
## and service agreements between two towns. The region server keeps it
## (saved with the region and sent to every player); each player's computer
## acts on its own part: paying a pledge, booking an agreement's monthly
## fee, and whatever a finished project or a signed agreement does in town.
##
## Projects (seeded from Balance.REGION_PROJECTS): id -> {"name", "kind",
## "board", "site": [x, z], "stages": [{"name", "goal": {good: amount},
## "pledged": {good: amount}, "status": "open" | "funded" | "waiting"}],
## "pledges": [{"player", "good", "amount", "at"}], "shares": {player: value}}.
## Pledges are final and never expire; the next stage opens only when the
## current one is funded. Shares count everything a player has pledged, at
## Trade.base_price, so each town can work out its own benefit from its
## share and its distance to the site.
##
## Agreements: id -> {"id", "host": city, "client": city, "service",
## "price_per_month", "capacity", "status": "offered" | "active" | "ended" |
## "denied"}. Each side runs its own half from the last terms, so an
## agreement keeps going while either player is away.
##
## The metro (Brawn's long game, 2026-10-23): the towns joined to each other
## by road count as one metro, ranked against real US metros
## (Balance.METRO_LADDER). Each town's population comes in with its copy;
## update_metro() works out the biggest road-linked group, its OMB-style
## name and its place on the ladder, and opens any project whose
## Balance.REGION_PROJECT_GATES size it has reached. An opened project stays
## open if the metro shrinks again.

## OMB's rule for smaller principal cities, simplified: a town is named in
## the metro's title when it has at least a third of the largest town's
## people. The title names at most three.
const PRINCIPAL_SHARE := 1.0 / 3.0
const PRINCIPAL_MAX := 3

var projects := {}
var agreements := {}
var _next_agreement := 1
## city id -> its latest population.
var populations := {}
## {"population", "name", "kind": "town" | "micropolitan" | "metropolitan",
## "towns": [city ids], "rank": place among the ladder plus us (1 = biggest),
## "of": how many that is, "next": [real area, population] or []}.
var metro := {}


func _init() -> void:
	seed_projects()


## Adds any project in Balance.REGION_PROJECTS the ledger doesn't have yet.
func seed_projects() -> void:
	for p in Balance.REGION_PROJECTS:
		if projects.has(p.id):
			continue
		var stages := []
		for i in p.stages.size():
			var st: Dictionary = p.stages[i]
			stages.append({"name": st.name, "goal": st.goal.duplicate(), "pledged": {},
				"status": "open" if i == 0 else "waiting"})
		projects[p.id] = {"name": p.name, "kind": p.kind, "board": p.board, "site": p.site.duplicate(),
			"stages": stages, "pledges": [], "shares": {}, "unlocked": gate(p.id) <= 0}


## The metro population a project needs before it takes pledges.
static func gate(project_id: String) -> int:
	return int(Balance.REGION_PROJECT_GATES.get(project_id, 0))


## Whether the metro has grown big enough for a project.
func is_unlocked(project_id: String) -> bool:
	return projects.has(project_id) and bool(projects[project_id].get("unlocked", false))


## The stage taking pledges now, or {} when every stage is funded.
static func open_stage(project: Dictionary) -> Dictionary:
	for st in project.stages:
		if st.status == "open":
			return st
	return {}


## How much more of a good the open stage needs.
func still_needed(project_id: String, good: String) -> float:
	if not projects.has(project_id):
		return 0.0
	var st := open_stage(projects[project_id])
	if st.is_empty():
		return 0.0
	return maxf(0.0, float(st.goal.get(good, 0.0)) - float(st.pledged.get(good, 0.0)))


## Books a pledge to a project's open stage. Returns the amount taken (never
## more than the stage still needs); the pledger's computer pays exactly that.
func pledge(player: String, project_id: String, good: String, amount: float) -> float:
	if not is_unlocked(project_id):
		return 0.0
	var take := minf(amount, still_needed(project_id, good))
	if take <= 0.0:
		return 0.0
	var p: Dictionary = projects[project_id]
	var st := open_stage(p)
	st.pledged[good] = float(st.pledged.get(good, 0.0)) + take
	p.pledges.append({"player": player, "good": good, "amount": take, "at": int(Time.get_unix_time_from_system())})
	p.shares[player] = float(p.shares.get(player, 0.0)) + value_of(good, take)
	if _funded(st):
		st.status = "funded"
		for other in p.stages:
			if other.status == "waiting":
				other.status = "open"
				break
	return take


## What a pledge is worth in dollars: money as is, goods at Trade prices.
static func value_of(good: String, amount: float) -> float:
	return amount if good == "money" else amount * Trade.base_price(good)


## A player's share of everything pledged to a project, 0 to 1.
func share(project_id: String, player: String) -> float:
	if not projects.has(project_id):
		return 0.0
	var total := 0.0
	for v in projects[project_id].shares.values():
		total += float(v)
	return float(projects[project_id].shares.get(player, 0.0)) / total if total > 0.0 else 0.0


## How many stages of a project are funded.
static func stages_done(project: Dictionary) -> int:
	return project.stages.filter(func(st): return st.status == "funded").size()


static func _funded(st: Dictionary) -> bool:
	for good in st.goal:
		if float(st.pledged.get(good, 0.0)) < float(st.goal[good]) - 0.001:
			return false
	return true


# --- Service agreements --------------------------------------------------------

## One town offers another a service (trash pickup, water, an ambulance...)
## for a monthly price. Returns the new agreement's id.
func offer(host: String, client: String, service: String, price_per_month: float, capacity: float) -> String:
	if host == client or service == "" or not is_finite(price_per_month) or price_per_month < 0.0 \
			or not is_finite(capacity) or capacity <= 0.0:
		return ""
	var id := "a%d" % _next_agreement
	_next_agreement += 1
	agreements[id] = {"id": id, "host": host, "client": client, "service": service,
		"price_per_month": price_per_month, "capacity": capacity, "status": "offered"}
	return id


## The other town says yes or no to an offer. Only the town it was made to.
func answer(id: String, city: String, yes: bool) -> bool:
	var a: Dictionary = agreements.get(id, {})
	if a.is_empty() or a.status != "offered" or a.client != city:
		return false
	a.status = "active" if yes else "denied"
	return true


## Either side ends an agreement.
func end(id: String, city: String) -> bool:
	var a: Dictionary = agreements.get(id, {})
	if a.is_empty() or not a.status in ["offered", "active"] or not city in [a.host, a.client]:
		return false
	a.status = "ended"
	return true


## The active agreements a town is part of.
func agreements_of(city: String) -> Array:
	return agreements.values().filter(func(a): return a.status == "active" and city in [a.host, a.client])


## A month of a town's agreements, booked on its own computer: the host is
## paid, the client pays. Returns the change in the town's money.
func book_month(city: String) -> float:
	var net := 0.0
	for a in agreements_of(city):
		net += float(a.price_per_month) if a.host == city else -float(a.price_per_month)
	return net


# --- The metro -----------------------------------------------------------------

## Notes a town's population. Returns whether it changed.
func set_population(city: String, population: int) -> bool:
	population = maxi(0, population)
	if int(populations.get(city, -1)) == population:
		return false
	populations[city] = population
	return true


## Works the metro out again from the towns (city id -> town name) and the
## road joins between them ([{"a", "b"}...]). Returns whether anything
## players would see changed.
func update_metro(towns: Dictionary, joins: Array) -> bool:
	# Group the towns by road: each group is a would-be metro.
	var group := {}
	for id in towns:
		group[id] = id
	var find := func(id: String) -> String:
		while group[id] != id:
			id = group[id]
		return id
	for j in joins:
		if group.has(j.a) and group.has(j.b):
			group[find.call(j.a)] = find.call(j.b)
	var members := {}
	for id in towns:
		var root: String = find.call(id)
		if not members.has(root):
			members[root] = []
		members[root].append(id)
	var best := []
	var best_pop := -1
	for root in members:
		var pop := 0
		for id in members[root]:
			pop += int(populations.get(id, 0))
		if pop > best_pop or (pop == best_pop and str(members[root]) < str(best)):
			best = members[root]
			best_pop = pop
	best.sort_custom(func(a, b): return int(populations.get(a, 0)) > int(populations.get(b, 0)) \
		or (int(populations.get(a, 0)) == int(populations.get(b, 0)) and a < b))
	var named := []
	for id in best:
		if named.is_empty() or (named.size() < PRINCIPAL_MAX and int(populations.get(id, 0)) > 0 \
				and populations.get(id, 0) >= PRINCIPAL_SHARE * int(populations.get(best[0], 0))):
			named.append(str(towns[id]))
	var pop := maxi(best_pop, 0)
	var rank := 1
	var next := []
	for area in Balance.METRO_LADDER:
		if int(area[1]) > pop:
			rank += 1
			if next.is_empty():
				next = [str(area[0]), int(area[1])]
	var kind := "metropolitan" if pop >= Balance.METRO_METRO_MIN \
		else "micropolitan" if pop >= Balance.METRO_MICRO_MIN else "town"
	var was := metro.duplicate()
	metro = {"population": pop, "name": "-".join(named), "kind": kind, "towns": best,
		"rank": rank, "of": Balance.METRO_LADDER.size() + 1, "next": next}
	var opened := false
	for id in projects:
		if not projects[id].get("unlocked", false) and pop >= gate(id):
			projects[id].unlocked = true
			opened = true
	return opened or JSON.stringify(was) != JSON.stringify(metro)


## The metro in one line, for the regional panel: "Petersburg-Oakland City
## micropolitan area, 12,400 people. Next: Connersville, IN, 10,600 to go."
func metro_line() -> String:
	if metro.is_empty():
		return ""
	var line := "%s, %s people." % [metro.name if metro.kind == "town" else "%s %s area" % [metro.name, metro.kind],
		_thousands(int(metro.population))]
	if not metro.next.is_empty():
		line += " Next: %s, %s to go." % [metro.next[0], _thousands(int(metro.next[1]) - int(metro.population))]
	return line


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Saving --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"projects": projects, "agreements": agreements, "next": _next_agreement,
		"populations": populations, "metro": metro}


func from_dict(d: Dictionary) -> void:
	projects = {}
	agreements = {}
	var ps: Dictionary = d.get("projects", {})
	for id in ps:
		var p: Dictionary = ps[id]
		var stages := []
		for st in p.get("stages", []):
			stages.append({"name": str(st.name), "goal": _amounts(st.get("goal", {})),
				"pledged": _amounts(st.get("pledged", {})), "status": str(st.get("status", "waiting"))})
		var pledges := []
		for pl in p.get("pledges", []):
			pledges.append({"player": str(pl.player), "good": str(pl.good), "amount": float(pl.amount), "at": int(pl.get("at", 0))})
		# A project already taking pledges before gates existed stays open.
		var unlocked := bool(p.get("unlocked", gate(str(id)) <= 0 or not pledges.is_empty()))
		projects[id] = {"name": str(p.name), "kind": str(p.get("kind", "")), "board": str(p.get("board", "")),
			"site": [float(p.site[0]), float(p.site[1])], "stages": stages, "pledges": pledges,
			"shares": _amounts(p.get("shares", {})), "unlocked": unlocked}
	var as_: Dictionary = d.get("agreements", {})
	for id in as_:
		var a: Dictionary = as_[id]
		agreements[id] = {"id": str(id), "host": str(a.host), "client": str(a.client), "service": str(a.service),
			"price_per_month": float(a.price_per_month), "capacity": float(a.capacity), "status": str(a.status)}
	_next_agreement = int(d.get("next", agreements.size() + 1))
	populations = {}
	var pops: Dictionary = d.get("populations", {})
	for id in pops:
		populations[str(id)] = int(pops[id])
	metro = {}
	var m: Dictionary = d.get("metro", {})
	if not m.is_empty():
		var towns := []
		for t in m.get("towns", []):
			towns.append(str(t))
		var next := []
		if m.get("next", []).size() == 2:
			next = [str(m.next[0]), int(m.next[1])]
		metro = {"population": int(m.get("population", 0)), "name": str(m.get("name", "")),
			"kind": str(m.get("kind", "town")), "towns": towns, "rank": int(m.get("rank", 0)),
			"of": int(m.get("of", 0)), "next": next}
	seed_projects()


static func _amounts(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = float(d[k])
	return out
