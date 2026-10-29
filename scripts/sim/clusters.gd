class_name Clusters
extends RefCounted
## Like businesses gather (Brawn's pick, 2026-10-29, after Civilization VI's
## district bonuses). Nobody places a shop in this game: a lot's owner picks
## the trade (Families). Owners pick the way real ones do, toward their own
## kind:
##   auto     garages and car dealers line the fast road out of town (an
##            auto row; Marion's is on Baldwin Avenue);
##   medical  doctors', dentists' and drug stores open within a few blocks
##            of a hospital or clinic (most medical office buildings stand
##            on or right by a hospital campus);
##   legal    lawyers, insurance agents, accountants and realtors take the
##            offices round the courthouse square;
##   dining   restaurants, pizza places and taverns open where others
##            already draw a crowd.
## A business among its own kind does better (comparison shopping, shared
## customers, referrals: retail rents run higher in a cluster), so its land
## is worth more. Zoning shops shows the cluster at the cursor
## (PlacementHints), so the player sees the bonus before painting.
##
## Light: the land lift is worked out once a month (or when businesses
## change) through 250 m buckets; owners look once, when they open.

## Each cluster: its name on the hint card, the trades in it, a word for a
## few of them, and what anchors it ("hospital", "courthouse", or a fast
## road for an auto row).
const KINDS := {
	"auto": {"name": "Auto row", "trades": ["auto", "dealer"], "word": "garages and car lots", "road": true},
	"medical": {"name": "Medical offices", "trades": ["doctor", "dentist", "pharmacy"], "word": "doctors' offices",
		"anchor": "hospital"},
	"legal": {"name": "Courthouse square", "trades": ["law", "insurance", "accounting", "realty"], "word": "offices",
		"anchor": "courthouse"},
	"dining": {"name": "Restaurant row", "trades": ["restaurant", "pizza", "tavern", "bakery"], "word": "places to eat"},
}
const CELL := 250.0

var _lift := {}       # lot key -> land value multiplier
var _key := []


## The cluster a trade belongs to, or "".
static func of_trade(trade: String) -> String:
	for k in KINDS:
		if trade in KINDS[k].trades:
			return k
	return ""


## True when a road is fast enough to grow an auto row on (a highway, an
## avenue or a country road at 40 mph or more).
static func fast_road(sim, seg: int) -> bool:
	if not sim.network.segments.has(seg):
		return false
	var t: int = sim.network.segments[seg].type
	return int(RoadStyle.TYPES[t].get("mph", 25)) >= Balance.CLUSTER_AUTO_MPH or int(RoadStyle.TYPES[t].lanes) >= 4


## Where each cluster's anchors stand: kind -> [Vector3].
static func anchors(sim) -> Dictionary:
	var out := {"hospital": [], "courthouse": []}
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if int(b.kind) == Services.Kind.HOSPITAL or int(b.kind) == Services.Kind.CLINIC:
			out.hospital.append(b.pos)
	for id in sim.parks.sites:
		if str(sim.parks.sites[id].kind) == "courthouse":
			out.courthouse.append(sim.parks.sites[id].pos)
	return out


## What's around a point for each cluster: kind -> {"n": like businesses
## within reach, "anchor": true by its anchor, "road": true on a fast road}.
## `seg` is the street the spot faces (-1 for none).
static func around(sim, at: Vector3, seg := -1, skip := "") -> Dictionary:
	var out := {}
	for k in KINDS:
		out[k] = {"n": 0, "anchor": false, "road": seg >= 0 and fast_road(sim, seg)}
	var reach2 := Balance.CLUSTER_REACH * Balance.CLUSTER_REACH
	for ref in sim.families.owned:
		if ref == skip or not str(ref).begins_with("lot:"):
			continue
		var k := of_trade(str(sim.families.owned[ref].what))
		var key := str(ref).substr(4)
		if k == "" or not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		if Vector2(p.x - at.x, p.z - at.z).length_squared() <= reach2:
			out[k].n += 1
	var an := anchors(sim)
	for k in KINDS:
		if KINDS[k].has("anchor"):
			for p in an[KINDS[k].anchor]:
				if Vector2(p.x - at.x, p.z - at.z).length() <= Balance.CLUSTER_ANCHOR_REACH:
					out[k].anchor = true
	return out


## How strong a cluster is at a spot: like neighbors, plus its anchor.
static func score(a: Dictionary) -> float:
	return float(a.n) + (Balance.CLUSTER_ANCHOR_SCORE if a.anchor else 0.0)


## The trade an owner opening on this lot leans toward, or "": a cluster
## close by pulls about half of them in (Balance.CLUSTER_PULL).
static func pull(sim, key: String, seed: int, office: bool) -> String:
	if not sim.lots.has(key):
		return ""
	var lot: Dictionary = sim.lots[key]
	var a := around(sim, lot.pos, int(lot.get("seg", -1)))
	var best := ""
	var best_s := 0.0
	for k in KINDS:
		var c: Dictionary = a[k]
		var s := score(c)
		if KINDS[k].get("road", false) and not c.road:
			continue  # an auto row is on the fast road out of town
		if s >= Balance.CLUSTER_PULL_MIN and s > best_s:
			best = k
			best_s = s
	if best == "" or absi(hash([seed, "cluster"])) % 100 >= roundi(Balance.CLUSTER_PULL * 100.0):
		return ""
	# An office building's tenant is an office (Families).
	var trades: Array = KINDS[best].trades.filter(func(t): return not office or Names.is_office(t))
	if best == "auto" and sim.market.people(sim) < Balance.CLUSTER_DEALER_PEOPLE:
		trades.erase("dealer")
	if trades.is_empty():
		return ""
	return str(trades[absi(hash([seed, "trade"])) % trades.size()])


## A business's land value lift from its cluster (1.0 for none).
func land(sim, key: String) -> float:
	var sig := [sim.families.owned.size(), sim.buildings.size(), sim.tick_count / (24 * CitySim.TICKS_PER_HOUR)]
	if sig != _key:
		_key = sig
		_rebuild(sim)
	return float(_lift.get(key, 1.0))


func _rebuild(sim) -> void:
	_lift.clear()
	# Every clustered business, by kind and 250 m bucket.
	var grid := {}
	var all := []
	for ref in sim.families.owned:
		if not str(ref).begins_with("lot:"):
			continue
		var k := of_trade(str(sim.families.owned[ref].what))
		var key := str(ref).substr(4)
		if k == "" or not sim.lots.has(key) or not sim.buildings.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var cell := Vector3i(floori(p.x / CELL), floori(p.z / CELL), KINDS.keys().find(k))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(p)
		all.append([key, k, p, cell, int(sim.lots[key].get("seg", -1))])
	if all.is_empty():
		return
	var an := anchors(sim)
	var reach2 := Balance.CLUSTER_REACH * Balance.CLUSTER_REACH
	for e in all:
		var p: Vector3 = e[2]
		var cell: Vector3i = e[3]
		var n := -1  # itself
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for q in grid.get(Vector3i(cell.x + dx, cell.y + dz, cell.z), []):
					if Vector2(q.x - p.x, q.z - p.z).length_squared() <= reach2:
						n += 1
		var kind: Dictionary = KINDS[e[1]]
		var near := false
		if kind.has("anchor"):
			for q in an[kind.anchor]:
				if Vector2(q.x - p.x, q.z - p.z).length() <= Balance.CLUSTER_ANCHOR_REACH:
					near = true
		if kind.get("road", false) and not fast_road(sim, e[4]):
			n = mini(n, 1)  # garages off the main road are just garages
		var s := score({"n": n, "anchor": near})
		if s > 0.0:
			_lift[e[0]] = 1.0 + Balance.CLUSTER_LIFT * minf(s, Balance.CLUSTER_FULL) / Balance.CLUSTER_FULL


## A line for the hint card while zoning shops at a spot, or "".
static func hint(sim, at: Vector3, seg := -1) -> String:
	var a := around(sim, at, seg)
	var best := ""
	var best_s := 0.0
	for k in KINDS:
		var s := score(a[k])
		if KINDS[k].get("road", false) and not a[k].road:
			s = 0.0
		if s >= Balance.CLUSTER_PULL_MIN and s > best_s:
			best = k
			best_s = s
	if best == "":
		return ""
	var c: Dictionary = a[best]
	var by := ""
	if c.anchor:
		by = " by the %s" % ("hospital" if KINDS[best].anchor == "hospital" else "courthouse")
	var count := (", %d %s nearby" % [c.n, KINDS[best].word]) if int(c.n) > 0 else ""
	return "%s%s%s. Shops of the same kind do better here." % [KINDS[best].name, by, count]
