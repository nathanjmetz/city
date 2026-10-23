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

var projects := {}
var agreements := {}
var _next_agreement := 1


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
			"stages": stages, "pledges": [], "shares": {}}


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
## paid, the client pays. Returns the change in the town's money. Services
## in `skip` are booked by the town's own budget (Interlocal deals are).
func book_month(city: String, skip := []) -> float:
	var net := 0.0
	for a in agreements_of(city):
		if a.service in skip:
			continue
		net += float(a.price_per_month) if a.host == city else -float(a.price_per_month)
	return net


# --- Saving --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"projects": projects, "agreements": agreements, "next": _next_agreement}


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
		projects[id] = {"name": str(p.name), "kind": str(p.get("kind", "")), "board": str(p.get("board", "")),
			"site": [float(p.site[0]), float(p.site[1])], "stages": stages, "pledges": pledges,
			"shares": _amounts(p.get("shares", {}))}
	var as_: Dictionary = d.get("agreements", {})
	for id in as_:
		var a: Dictionary = as_[id]
		agreements[id] = {"id": str(id), "host": str(a.host), "client": str(a.client), "service": str(a.service),
			"price_per_month": float(a.price_per_month), "capacity": float(a.capacity), "status": str(a.status)}
	_next_agreement = int(d.get("next", agreements.size() + 1))
	seed_projects()


static func _amounts(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = float(d[k])
	return out
