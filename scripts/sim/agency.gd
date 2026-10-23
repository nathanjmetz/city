class_name Agency
extends RefCounted
## Every hub has a leader and a development tree (Brawn): a farm, company,
## factory, depot, park or university is run by someone who decides, on a
## slow cadence, what to build next from its own tree. What's open to them
## depends on what they can do (education, money in hand) and on what's
## around them: locally (resources, other industry nearby), across the city
## (population, jobs) and across the region (what the neighbouring towns
## make and buy). So a town's growth depends on and feeds its neighbours.
##
## Shared by every hub thread. A hub plugs in with:
##   1. A tree in its own file: Array of nodes
##        {id, name, cost, requires: [ids], needs: {condition: value},
##         effects: {key: value}, note}
##      (see TREES below for the resource companies and farms).
##   2. A hub dictionary carrying "leader" (from Agency.leader) and
##      "built": Array of node ids, both saved with the hub.
##   3. A call on its own decide cadence: Agency.develop(sim, hub, tree, at,
##      money) returns the node it builds ({} for none) and records why.
##   4. Agency.effect(hub, tree, key) sums an effect (1.0-based for "*"
##      keys like "output*", 0-based otherwise) for its own numbers.
##   5. For choices between ways to run (not things to buy), Agency.choose
##      (lead, options) picks one and says why (crop rotation: CropPlan).
## Deterministic: no clocks or global random, only seeds and city state.
## No player nudges: the player only sets money and can remove buildings.
##
## Conditions a node can need (all must hold):
##   education      town education 0..1 (share of homes with a school)
##   leader_edu     the leader's own schooling 0..1
##   profit         the hub's yearly profit in dollars
##   population     people in town
##   local:<chain>  a factory of that chain (Balance.FACTORY_CHAINS key)
##                  within FACTORY_CHAIN_REACH of the hub
##   local:<kind>   a resource company ("oil", "ore", "forest") or "farm"
##                  within the same reach
##   region_buys:<good>   a neighbouring town imports that good
##   region_makes:<good>  a neighbouring town exports that good
##   link           the town has a way out to the region
##   hub:<fact>     a number the hub keeps in its own "facts" dictionary
##                  (e.g. the phone company's "towers" or "fiber_km")

## Development trees for the hubs this thread owns. Costs come out of the
## hub's own money (its profit), never the city budget.
const TREES := {
	"oil": [
		{"id": "tank_battery", "name": "Tank battery", "cost": 120_000, "needs": {},
			"effects": {"stock+": 6.0}, "note": "more crude waits for trucks"},
		{"id": "gas_plant", "name": "Gas processing plant", "cost": 900_000, "requires": ["tank_battery"],
			"needs": {"leader_edu": 0.4, "profit": 200_000}, "effects": {"output*": 0.15, "jobs+": 10},
			"note": "sells the gas too"},
		{"id": "pipeline", "name": "Pipeline to the plastics plant", "cost": 600_000, "requires": ["tank_battery"],
			"needs": {"local:refinery": 1}, "effects": {"haul*": -0.5}, "note": "crude flows instead of trucking"},
		{"id": "frac_crew", "name": "Completion crew", "cost": 1_500_000, "requires": ["gas_plant"],
			"needs": {"leader_edu": 0.6, "education": 0.5}, "effects": {"output*": 0.25, "jobs+": 20},
			"note": "skilled crews get more from each well"},
		{"id": "terminal", "name": "Regional crude terminal", "cost": 2_000_000, "requires": ["gas_plant"],
			"needs": {"region_buys:crude oil": 1, "link": 1}, "effects": {"price*": 0.15, "jobs+": 8},
			"note": "a neighbouring town buys crude"},
	],
	"ore": [
		{"id": "crusher", "name": "Primary crusher", "cost": 300_000, "needs": {},
			"effects": {"output*": 0.1, "jobs+": 6}},
		{"id": "wash_plant", "name": "Wash plant", "cost": 800_000, "requires": ["crusher"],
			"needs": {"leader_edu": 0.4}, "effects": {"price*": 0.2, "jobs+": 10}, "note": "cleaner ore sells higher"},
		{"id": "conveyor", "name": "Conveyor to the metal works", "cost": 700_000, "requires": ["crusher"],
			"needs": {"local:metal": 1}, "effects": {"haul*": -0.5}},
		{"id": "rail_loadout", "name": "Rail loadout", "cost": 2_500_000, "requires": ["wash_plant"],
			"needs": {"region_buys:ore": 1, "link": 1, "profit": 500_000}, "effects": {"price*": 0.2, "jobs+": 12}},
	],
	"forest": [
		{"id": "log_yard", "name": "Log yard", "cost": 150_000, "needs": {},
			"effects": {"stock+": 6.0, "jobs+": 4}},
		{"id": "chip_plant", "name": "Chip plant", "cost": 500_000, "requires": ["log_yard"],
			"needs": {"profit": 100_000}, "effects": {"output*": 0.1, "jobs+": 6}, "note": "sells the tops and slash"},
		{"id": "replanting", "name": "Replanting crew", "cost": 250_000, "requires": ["log_yard"],
			"needs": {"leader_edu": 0.5}, "effects": {"output*": 0.15, "jobs+": 8}, "note": "stands come back faster"},
		{"id": "dry_kiln", "name": "Dry kiln", "cost": 900_000, "requires": ["chip_plant"],
			"needs": {"local:sawmill": 1, "leader_edu": 0.5}, "effects": {"price*": 0.25, "jobs+": 10}},
		{"id": "pellet_mill", "name": "Wood pellet mill", "cost": 1_800_000, "requires": ["chip_plant"],
			"needs": {"region_buys:logs": 1, "link": 1}, "effects": {"price*": 0.2, "jobs+": 15}},
	],
	"farm": [
		{"id": "grain_bins", "name": "Grain bins", "cost": 80_000, "needs": {},
			"effects": {"stock+": 2000.0}, "note": "holds the harvest for a better price"},
		{"id": "dryer", "name": "Grain dryer", "cost": 150_000, "requires": ["grain_bins"],
			"needs": {"profit": 40_000}, "effects": {"price*": 0.05}},
		{"id": "precision", "name": "Precision planting", "cost": 120_000, "requires": ["grain_bins"],
			"needs": {"leader_edu": 0.5, "education": 0.3}, "effects": {"output*": 0.1},
			"note": "GPS rows and variable-rate seed"},
		{"id": "co_op", "name": "Co-op elevator share", "cost": 200_000, "requires": ["dryer"],
			"needs": {"local:mill": 1}, "effects": {"price*": 0.08}, "note": "sells straight to the local mill"},
		{"id": "seed_dealer", "name": "Seed dealership", "cost": 300_000, "requires": ["precision"],
			"needs": {"leader_edu": 0.6, "region_makes:grain": 1}, "effects": {"price*": 0.05, "jobs+": 3},
			"note": "neighbouring farm towns buy seed here"},
	],
}


## A leader for a new hub. Their schooling follows the town's (with some
## spread); caution and ambition are temperament. Saved with the hub.
static func leader(sim: CitySim, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# The town's own graduates raise the bar too (Education.leader_education).
	var town := maxf(education(sim), sim.education.leader_education(maxi(int(sim.stats.workers), 1)))
	var edu := clampf(town + rng.randf_range(-0.25, 0.25), 0.0, 1.0)
	return {"edu": _cents(edu), "caution": _cents(rng.randf()), "ambition": _cents(rng.randf())}


## Two decimals, as the same float a save reads back (snappedf(0.35, 0.01)
## is 35 * 0.01 = 0.35000000000000003, which JSON writes as 0.35).
static func _cents(v: float) -> float:
	return roundi(v * 100.0) / 100.0


## Town-wide facts worked out once and reused by every hub deciding in the
## same tick (a monthly round asks the same things thousands of times in a
## big town): "edu" and "local" -> value, "_at" -> what they were measured
## on. Anything that adds buildings, farms or sites starts it over.
static var _memo := {}


static func _fresh(sim: CitySim) -> void:
	var at := [sim.get_instance_id(), sim.tick_count, sim.buildings.size(), sim.services.served.size(),
		sim.farms.farms.size(), sim.industry.sites.size()]
	if _memo.get("_at", []) != at:
		_memo = {"_at": at}


## The town's education: the share of homes a school covers.
static func education(sim: CitySim) -> float:
	_fresh(sim)
	if not _memo.has("edu"):
		_memo["edu"] = _education(sim)
	return _memo.edu


static func _education(sim: CitySim) -> float:
	var homes := 0
	var schooled := 0
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			homes += 1
			if sim.services.served.get(key, {}).get(Services.Kind.SCHOOL, false):
				schooled += 1
	return 0.0 if homes == 0 else float(schooled) / homes


## True when one condition holds for a hub at `at` with this yearly profit.
static func holds(sim: CitySim, hub: Dictionary, at: Vector3, profit: float, cond: String, value) -> bool:
	match cond:
		"education": return education(sim) >= float(value)
		"leader_edu": return float(hub.get("leader", {}).get("edu", 0.0)) >= float(value)
		"profit": return profit >= float(value)
		"population": return sim.stats.population >= int(value)
		"link": return not sim.region_links.is_empty()
	if cond.begins_with("hub:"):
		return float(hub.get("facts", {}).get(cond.substr(4), 0.0)) >= float(value)
	if cond.begins_with("local:"):
		return _local(sim, at, cond.substr(6)) >= int(value)
	if cond.begins_with("region_buys:"):
		return _region(sim, "imports", cond.substr(12)) >= int(value)
	if cond.begins_with("region_makes:"):
		return _region(sim, "exports", cond.substr(13)) >= int(value)
	return false


## What's open to a hub right now: nodes not yet built whose requirements
## are built and whose conditions all hold.
static func open(sim: CitySim, hub: Dictionary, tree: Array, at: Vector3, profit: float) -> Array:
	var built: Array = hub.get("built", [])
	var out := []
	for node in tree:
		if node.id in built:
			continue
		var ok := true
		for r in node.get("requires", []):
			ok = ok and r in built
		for c in node.get("needs", {}):
			ok = ok and holds(sim, hub, at, profit, c, node.needs[c])
		if ok:
			out.append(node)
	return out


## The leader's next move: of what's open and affordable from the hub's
## own money, the node it values most. Ambitious leaders reach for bigger
## projects; cautious ones keep a cushion. Records "built" and "why".
static func develop(sim: CitySim, hub: Dictionary, tree: Array, at: Vector3, profit: float) -> Dictionary:
	var lead: Dictionary = hub.get("leader", {"edu": 0.5, "caution": 0.5, "ambition": 0.5})
	# A cautious leader keeps up to a year's profit in hand before spending.
	var budget := profit * (2.0 + 3.0 * float(lead.ambition)) - profit * float(lead.caution)
	# A hub with its own money (Capital) spends only what it has saved, less
	# a cushion a cautious leader keeps bigger (Brawn: growth from profit).
	var saved := hub.has("cap_day")  # run by Capital (hubs paying their own way do it themselves)
	if saved:
		budget = float(hub.cash) - Balance.CAPITAL_RESERVE * (0.5 + float(lead.caution))
	var best := {}
	var best_v := -INF
	for node in open(sim, hub, tree, at, profit):
		if float(node.cost) > budget:
			continue
		var gain := 0.0
		for k in node.get("effects", {}):
			gain += absf(float(node.effects[k])) * (1.0 if k.ends_with("*") else 0.02)
		# Ambition favours the big step; caution the cheap one.
		var v := gain * (1.0 + float(lead.ambition)) - float(node.cost) / 1.0e7 * (0.5 + float(lead.caution))
		if v > best_v or (v == best_v and str(node.id) < str(best.get("id", ""))):
			best_v = v
			best = node
	if best.is_empty():
		return {}
	if not hub.has("built"):
		hub.built = []
	hub.built.append(best.id)
	if saved:
		hub.cash = float(hub.cash) - float(best.cost)
	hub.why = "%s built %s%s." % ["Its owner" if float(lead.edu) < 0.5 else "Its college-educated owner",
		str(best.name).to_lower(), (": " + str(best.note)) if best.has("note") else ""]
	return best


## A leader's choice between options (Brawn 2026-10-23: "a leader of a
## hub decision"): a farmer picking next year's crop, a factory what to
## make, a school what to teach. Unlike develop() nothing is bought; the
## hub picks one of several ways to run. Each option is
## {id, name, factors: {kind: [value, reason]}}, values in dollars (or a
## like score) a unit a year. The leader weighs each kind by temperament
## (see weight()) and the best total wins, ties to the lower id. Returns
## {id, name, score, why}: why names the reasons that beat the runner-up,
## for Inspect. Deterministic.
static func choose(lead: Dictionary, options: Array) -> Dictionary:
	var scored := []
	for o in options:
		var total := 0.0
		for k in o.factors:
			total += weight(lead, k) * float(o.factors[k][0])
		scored.append([total, str(o.id), o])
	scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var best: Dictionary = scored[0][2]
	var reasons := []
	if scored.size() > 1:
		var other: Dictionary = scored[1][2]
		var edges := []
		for k in best.factors:
			var d := weight(lead, k) * (float(best.factors[k][0]) - float(other.factors.get(k, [0.0])[0]))
			if d > 1.0:
				edges.append([d, str(best.factors[k][1])])
		edges.sort_custom(func(a, b): return a[0] > b[0])
		for e in edges.slice(0, 2):
			reasons.append(e[1])
		if reasons.is_empty():
			reasons.append("it edges out %s" % str(other.name).to_lower())
		return {"id": best.id, "name": best.name, "score": scored[0][0], "runner_up": other.id,
			"why": "%s over %s: it %s." % [best.name, str(other.name).to_lower(), ", and it ".join(reasons)]}
	return {"id": best.id, "name": best.name, "score": scored[0][0], "runner_up": "", "why": "%s." % best.name}


## How much a leader counts one kind of reason. Money and buyers count in
## full; schooling makes a leader look further ahead (future); caution
## weighs money at stake and spreading risk; ambition weighs growth.
static func weight(lead: Dictionary, kind: String) -> float:
	var edu := float(lead.get("edu", 0.5))
	var caution := float(lead.get("caution", 0.5))
	match kind:
		"future": return 0.3 + 0.7 * edu
		"risk", "spread": return 0.5 + caution
		"growth": return 0.5 + float(lead.get("ambition", 0.5))
	return 1.0


## The sum of one effect over what a hub has built: "output*" style keys
## come back as a multiplier (1.0 plus the sum), the rest as a plain sum.
static func effect(hub: Dictionary, tree: Array, key: String) -> float:
	var total := 0.0
	var built: Array = hub.get("built", [])
	for node in tree:
		if node.id in built:
			total += float(node.get("effects", {}).get(key, 0.0))
	return 1.0 + total if key.ends_with("*") else total


## Hubs of a kind within reach: factory chains, resource companies or farms.
## Counted from buckets FACTORY_CHAIN_REACH across, built once a tick, so a
## check looks at the hubs in nine buckets instead of every building.
static func _local(sim: CitySim, at: Vector3, what: String) -> int:
	_fresh(sim)
	if not _memo.has("local"):
		_memo["local"] = _local_index(sim)
	var reach := Balance.FACTORY_CHAIN_REACH
	var kinds: Dictionary = _memo.local
	if not kinds.has(what):
		return 0
	var b := Vector2i(floori(at.x / reach), floori(at.z / reach))
	var n := 0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for p in kinds[what].get(b + Vector2i(dx, dz), []):
				if p.distance_to(at) < reach:
					n += 1
	return n


## kind -> bucket -> positions of every factory (by chain), farm and
## resource company (by kind).
static func _local_index(sim: CitySim) -> Dictionary:
	var reach := Balance.FACTORY_CHAIN_REACH
	var out := {}
	var put := func(kind: String, p: Vector3) -> void:
		if not out.has(kind):
			out[kind] = {}
		var b := Vector2i(floori(p.x / reach), floori(p.z / reach))
		if not out[kind].has(b):
			out[kind][b] = []
		out[kind][b].append(p)
	for key in sim.buildings:
		var chain := str(sim.buildings[key].get("chain", ""))
		if chain != "" and sim.lots.has(key):
			put.call(chain, sim.lots[key].pos)
	for id in sim.farms.farms:
		put.call("farm", sim.farms.farms[id].pos)
	for id in sim.industry.sites:
		put.call(str(sim.industry.sites[id].kind), sim.industry.sites[id].pos)
	return out


## Neighbouring towns that import or export a good: from last month's
## trade deals (Trade), plus anything the region server reports in
## sim.region {"neighbors": [{"name", "imports": {good: loads},
## "exports": {good: loads}}]}. Solo towns have no neighbours.
static func _region(sim: CitySim, side: String, good: String) -> int:
	var towns := {}
	for d in sim.trade.last_deals:
		if d.get("good", "") != good:
			continue
		var other: String = str(d.get("buyer" if side == "imports" else "seller", "outside"))
		if other != "outside":
			towns[other] = true
	for town in sim.region.get("neighbors", []):
		if float(town.get(side, {}).get(good, 0.0)) > 0.0:
			towns[str(town.get("name", ""))] = true
	return towns.size()
