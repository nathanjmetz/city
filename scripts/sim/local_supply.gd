class_name LocalSupply
extends RefCounted
## Building materials from the town's own industry (Brawn's pick #12, after
## Banished, Pioneers of Pagonia and Workers & Resources, where a town's
## own sawmill and quarry feed its building sites). A job site's big loads
## come from the nearest source in town that makes them, on a real truck
## that drives back there once it has unloaded; a town with none still
## gets them off the highway, as before.
##
##   ready-mix, curb concrete   the quarry's batch plant (as Irving Materials
##                              and other Indiana producers run ready-mix at
##                              their sand and gravel pits)
##   hot-mix asphalt            the quarry's asphalt plant (Milestone and
##                              other Indiana pavers set plants at quarries)
##   crushed stone, fill dirt   the quarry itself
##   lumber, posts and trusses  a sawmill in town
##   structural steel           a metal works in town (a steel fabricator)
##
## The quarry is a mining company (Industry "ore"): what it sells a job site
## goes into its own cash. Each source has a real haul limit
## (Balance.LOCAL_SUPPLY_REACH). Resources never run out, so a source never
## turns a site away. Deterministic: sources are picked from sorted ids.

## What each cargo is (Balance.LOCAL_SUPPLY_REACH keys).
const CARGO := {
	"ready-mix concrete": "ready_mix", "curb concrete": "ready_mix",
	"hot-mix asphalt": "asphalt",
	"crushed stone": "stone", "fill dirt": "stone",
	"framing lumber": "lumber", "framing package": "lumber", "posts and trusses": "lumber",
	"structural steel": "steel",
}
## The zoned factory chain (Balance.FACTORY_CHAINS) that makes each one.
const CHAIN := {"lumber": "sawmill", "steel": "metal"}


## The trip end a load of `cargo` for a site at `at` comes from: the
## nearest source in town within its haul reach, or {} for none.
static func source(sim, cargo: String, at: Vector3) -> Dictionary:
	var what: String = CARGO.get(cargo, "")
	if what == "":
		return {}
	var reach: float = Balance.LOCAL_SUPPLY_REACH[what]
	var best := {}
	var best_d := reach
	if CHAIN.has(what):
		for key in sim.ledger().by_zone.get(ZoneMap.Zone.INDUSTRIAL, []):
			var b: Dictionary = sim.buildings[key]
			if str(b.get("chain", "general")) != CHAIN[what] or not sim.lots.has(key) \
					or not sim.utilities_ok(key) or not sim.construction.is_done("lot:" + key, sim.tick_count):
				continue
			var f: Vector3 = sim.lots[key].front
			var d := Vector2(f.x - at.x, f.z - at.z).length()
			if d < best_d - 0.01:
				best_d = d
				best = {"ref": "lot:" + key, "pos": Logistics._xz(f)}
		return best
	var ids: Array = sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sim.industry.sites[id]
		if str(s.kind) != "ore" or s.drive.is_empty():
			continue
		var g: Vector3 = s.drive[-1]
		var d := Vector2(g.x - at.x, g.z - at.z).length()
		if d < best_d - 0.01:
			best_d = d
			best = {"ref": "site:%d" % id, "pos": Logistics._xz(g), "drive": Logistics._lane(s.drive)}
	return best


## A local load of `cargo` from `src` (a trip end from source) reached its
## site: the quarry is paid, and the town's tally of local loads goes up.
static func delivered(sim, src: Dictionary, cargo: String) -> void:
	var ref := str(src.get("ref", ""))
	sim.construction.local_loads[cargo] = int(sim.construction.local_loads.get(cargo, 0)) + 1
	if ref.begins_with("site:"):
		var s = sim.industry.sites.get(int(ref.substr(5)))
		if s != null:
			s.cash = float(s.get("cash", 0.0)) + float(Balance.LOCAL_SUPPLY_PRICE.get(cargo, 0))


## Where a local truck goes home to once it has unloaded: its source, if it
## is still there ({} if not, and it leaves town like anyone's truck).
static func home(sim, src: Dictionary) -> Dictionary:
	var ref := str(src.get("ref", ""))
	if ref.begins_with("site:"):
		var s = sim.industry.sites.get(int(ref.substr(5)))
		if s == null or s.drive.is_empty():
			return {}
		return {"ref": ref, "pos": Logistics._xz(s.drive[-1]), "drive": Logistics._lane(s.drive)}
	if ref.begins_with("lot:"):
		var key := ref.substr(4)
		if not sim.buildings.has(key) or not sim.lots.has(key):
			return {}
		return {"ref": ref, "pos": Logistics._xz(sim.lots[key].front)}
	return {}
