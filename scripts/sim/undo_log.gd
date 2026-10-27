class_name UndoLog
## Undo the last builds, like Townscaper and Anno: roads, grids, roundabouts,
## upgrades and anything placed come back out with a full refund. The HUD
## only offers it for 30 seconds after a build (Ctrl+Z, or View + X on a
## controller). Bulldozing and zoning aren't undone.
##
## Not saved: an undo is for a slip just made, so a load starts fresh.

## How long after a build it can still be undone, in real seconds (the HUD
## checks this; the sim undoes whatever is on top).
const WINDOW_MS := 30000
const KEEP := 10

## Commands that draw roads: undone by putting the road network back.
const ROAD_TYPES := ["build_road", "build_grid", "build_grid_shape", "build_roundabout", "upgrade_road"]
## Commands that place one thing, and the command that removes it again.
const PLACE_TYPES := {
	"place_service": "remove_service", "place_park": "remove_park", "place_warehouse": "remove_warehouse",
	"place_big_factory": "remove_big_factory", "place_power": "remove_power", "place_campus": "remove_campus",
	"place_bank": "remove_bank", "place_telecom": "remove_telecom", "place_industry": "remove_industry",
	"place_farmhouse": "remove_farm", "place_rail_depot": "remove_rail_depot", "place_hub": "remove_hub",
}

## [{type, money, at_ms, ...}], newest last.
var entries: Array = []


## What to remember before a command runs, or null when it can't be undone.
func before(sim: CitySim, cmd: Dictionary) -> Variant:
	var type := str(cmd.get("type", ""))
	if type in ROAD_TYPES:
		return {"type": type, "money": sim.economy.money, "roads": sim.network.snapshot(), "rev": sim.network.revision,
			"county": sim.county_joined.size(), "links": sim.region_links.size(),
			"closed": sim.traffic.closed.duplicate(), "plazas": sim.parks.trails.plazas.duplicate(),
			"bans": sim.traffic.turn_bans.duplicate(true), "no_cross": sim.traffic.no_crosswalks.duplicate(true)}
	if PLACE_TYPES.has(type):
		return {"type": type, "money": sim.economy.money, "ids": things(sim, type).keys()}
	return null


## Records a command that went through.
func after(sim: CitySim, snap: Dictionary) -> void:
	var e := {"type": snap.type, "refund": snap.money - sim.economy.money, "at_ms": Time.get_ticks_msec()}
	if snap.has("roads"):
		# A road joined onto a county road or a region link changes more
		# than the roads; that stays.
		if sim.county_joined.size() != snap.county or sim.region_links.size() != snap.links:
			return
		e.roads = snap.roads
		e.rev_before = snap.rev
		e.rev = sim.network.revision
		# Car-free streets the build cut in two: whole again on undo.
		e.closed = {}
		for seg in snap.closed:
			if not sim.network.segments.has(int(seg)):
				e.closed[seg] = snap.closed[seg]
		e.plazas = snap.plazas.filter(func(seg): return not sim.network.segments.has(int(seg)))
		# And no-turn signs and missing crosswalks at the junctions it
		# changed, only those: one the player clears later elsewhere stays
		# cleared (third reader, 2026-10-26).
		var changed := func(n) -> bool:
			return not sim.network.nodes.has(int(n)) or _roads_at(snap.roads, int(n)) != _sorted(sim.network.segments_at(int(n)))
		e.bans = {}
		for n in snap.bans:
			if changed.call(n):
				e.bans[n] = snap.bans[n]
		e.no_cross = {}
		for n in snap.no_cross:
			if changed.call(n):
				e.no_cross[n] = snap.no_cross[n]
	else:
		var added: Array = things(sim, snap.type).keys().filter(func(k): return not k in snap.ids)
		if added.size() != 1:
			return
		e.id = added[0]
	entries.append(e)
	if entries.size() > KEEP:
		entries.pop_front()


## The roads meeting node `n` in a network snapshot, sorted.
static func _roads_at(roads: Dictionary, n: int) -> Array:
	var out := []
	for id in roads.segments:
		if roads.segments[id].a == n or roads.segments[id].b == n:
			out.append(id)
	return _sorted(out)


static func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


## A street made car-free: when the newest road build made that street,
## undoing it refunds the pavers too (second reader, 2026-10-26).
func note_car_free(sim: CitySim, seg: int, cost: int) -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries.back()
	if e.has("roads") and e.rev == sim.network.revision and not e.roads.segments.has(seg):
		e.refund = int(e.refund) + cost


## The newest build that can still be undone, or {} (stale ones are dropped).
func last(sim: CitySim) -> Dictionary:
	while not entries.is_empty():
		var e: Dictionary = entries.back()
		if e.has("roads") and e.rev == sim.network.revision:
			return e
		if e.has("id") and things(sim, e.type).has(e.id):
			return e
		entries.pop_back()  # something else changed it since
	return {}


## Undoes the newest build. True if anything came back out.
func undo(sim: CitySim) -> bool:
	var e := last(sim)
	if e.is_empty():
		return false
	entries.pop_back()
	if e.has("roads"):
		sim.network.restore(e.roads)
		# At once, not at the next traffic rebuild: undo hands out junction
		# ids again, and a new junction mustn't start with an old one's signs
		# (second reader, 2026-10-26). Not on every road change, though: a
		# roundabout resize takes its ring out and puts it back in two steps.
		# restore_junction_settings prunes first, then gives back what the
		# build took.
		sim.traffic.restore_junction_settings(e.get("bans", {}), e.get("no_cross", {}))
		for seg in e.get("closed", {}):
			sim.traffic.close_segment(int(seg), true, str(e.closed[seg]))
		for seg in e.get("plazas", []):
			if not seg in sim.parks.trails.plazas:
				sim.parks.trails.plazas.append(seg)
				sim.parks.trails._rev = ""
		if not e.get("plazas", []).is_empty():
			sim.parks_changed.emit()
		# The build before this one is current again if nothing came between.
		if not entries.is_empty() and entries.back().has("roads"):
			var prev: Dictionary = entries.back()
			if prev.rev == e.rev_before:
				prev.rev = sim.network.revision
	elif not sim.apply_now({"type": PLACE_TYPES[e.type], "id": e.id}):
		return false
	sim.economy.money += int(e.refund)
	return true


## What a placing command adds to, keyed by id.
static func things(sim: CitySim, type: String) -> Dictionary:
	match type:
		"place_service": return sim.services.buildings
		"place_park": return sim.parks.sites
		"place_warehouse": return sim.warehouses.buildings
		"place_big_factory": return sim.big.sites
		"place_power": return sim.power.sites
		"place_campus": return sim.education.campuses
		"place_bank": return sim.banks.banks
		"place_telecom": return sim.telecom.companies
		"place_industry": return sim.industry.sites
		"place_farmhouse": return sim.farms.farms
		"place_rail_depot": return sim.rail.depots
		"place_hub": return sim.hubs.hubs
	return {}
