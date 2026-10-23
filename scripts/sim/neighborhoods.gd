class_name Neighborhoods
extends RefCounted
## A town's other neighborhoods (Brawn 2026-10-23): a town hemmed in by its
## neighbors can start a new neighborhood out on open land, the way an old
## village ends up one end of a bigger city and the town grows on at its
## edge. It is the same town: one budget, one set of leaders, one
## population, all growing while its player plays. A free county road links
## it to the nearest road in town (real county roads cross other towns).
##
## Guarding against land grabs (see neighborhoods-risks.md): a town earns
## one neighborhood per stage it grows through (Balance.STAGE_TARGET_DAYS,
## Town and up), each costs double the last one ever founded, and a site
## with nothing built near it after NEIGHBORHOOD_USE_DAYS game days is let
## go (the slot comes back, the fee doesn't).
##
## sites: [{"name", "at": Vector2 (town coordinates), "founded": tick,
## "settled": bool}]

var sites := []
## Every neighborhood ever founded, released ones too: the next fee doubles
## for each.
var founded := 0


## Neighborhoods a town of this size may have: one per stage from Town up.
static func slots_for(population: int) -> int:
	var stages := 0
	for size in Balance.STAGE_TARGET_DAYS:
		if population >= int(size):
			stages += 1
	return clampi(stages - 1, 0, Balance.NEIGHBORHOOD_MAX)


func slots_free(population: int) -> int:
	return maxi(0, slots_for(population) - sites.size())


## What the next neighborhood costs.
func fee() -> int:
	return Balance.NEIGHBORHOOD_FEE * int(pow(2.0, founded))


## A plain name from where it lies, the way towns name their parts: "North
## Side", "East End".
static func side_name(at: Vector2) -> String:
	var dirs := ["East", "Southeast", "South", "Southwest", "West", "Northwest", "North", "Northeast"]
	# Town coordinates: +x east, +z south.
	var i := posmod(roundi(at.angle() / (TAU / 8.0)), 8)
	return "%s %s" % [dirs[i], "End" if at.length() > 3000.0 else "Side"]


func add(at: Vector2, name: String, tick: int) -> void:
	sites.append({"name": name, "at": at, "founded": tick, "settled": false})
	founded += 1


## Once a day: a site with buildings near it is settled for good; one still
## empty after NEIGHBORHOOD_USE_DAYS is let go. Returns the names let go.
func check(sim: CitySim) -> Array:
	var gone := []
	var limit := Balance.NEIGHBORHOOD_USE_DAYS * CitySim.TICKS_PER_HOUR * 24
	var r2 := Balance.NEIGHBORHOOD_USE_RADIUS * Balance.NEIGHBORHOOD_USE_RADIUS
	for s in sites.duplicate():
		if s.settled:
			continue
		for key in sim.buildings:
			if sim.lots.has(key):
				var p: Vector3 = sim.lots[key].pos
				if Vector2(p.x, p.z).distance_squared_to(s.at) <= r2:
					s.settled = true
					break
		if not s.settled and sim.tick_count - int(s.founded) > limit:
			sites.erase(s)
			gone.append(s.name)
	return gone


func to_dict() -> Dictionary:
	var out := []
	for s in sites:
		out.append({"name": s.name, "at": [s.at.x, s.at.y], "founded": s.founded, "settled": s.settled})
	return {"sites": out, "founded": founded}


func from_dict(d: Dictionary) -> void:
	sites = []
	for s in d.get("sites", []):
		sites.append({"name": str(s.get("name", "")), "at": Vector2(float(s.at[0]), float(s.at[1])),
			"founded": int(s.get("founded", 0)), "settled": bool(s.get("settled", false))})
	founded = int(d.get("founded", sites.size()))
