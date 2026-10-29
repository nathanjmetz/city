class_name UndoLog
## Undo the last builds, like Townscaper and Anno: roads, grids, roundabouts,
## upgrades and anything placed come back out with a full refund. The HUD
## only offers it for 30 seconds after a build (Ctrl+Z, or View + X on a
## controller). Bulldozing and zoning aren't undone.
##
## A road wins over what's in its way (CitySim._road_wins), so undoing it
## puts back everything it took: the buildings it bulldozed, with their ids,
## managers and books, and the fields and parks it cut back (critic
## 2026-10-27: a street through the water tower, then undo, took the street
## and the tower both, and the town emptied without water).
##
## Not saved: an undo is for a slip just made, so a load starts fresh.

## How long after a build it can still be undone, in real seconds (the HUD
## checks this; the sim undoes whatever is on top).
const WINDOW_MS := 30000
const KEEP := 10

## Commands that draw roads: undone by putting the road network back.
const ROAD_TYPES := ["build_road", "build_roads", "build_grid", "build_grid_shape", "build_roundabout", "upgrade_road"]
## Commands that place one thing, and the command that removes it again.
const PLACE_TYPES := {
	"place_service": "remove_service", "place_park": "remove_park", "place_warehouse": "remove_warehouse",
	"place_big_factory": "remove_big_factory", "place_power": "remove_power", "place_campus": "remove_campus",
	"place_bank": "remove_bank", "place_telecom": "remove_telecom", "place_industry": "remove_industry",
	"place_farmhouse": "remove_farm", "place_rail_depot": "remove_rail_depot", "place_hub": "remove_hub",
}

## What the road wins can bulldoze or cut back, by the command that places it
## (see things()).
const ROAD_WINS := ["place_service", "place_farmhouse", "place_industry", "place_warehouse", "place_big_factory",
	"place_park", "place_power", "place_campus", "place_telecom", "place_bank"]
## Lists of pieces a road can cut out of something it only cuts back (a
## farm's fields, a company's pads, a plant's units, a campus's blocks):
## undo adds back the pieces it lost and keeps any grown since, where every
## other field goes back to how it was before the street.
const PIECES := ["cells", "pads", "blocks"]

## [{type, money, at_ms, ...}], newest last.
var entries: Array = []


## What to remember before a command runs, or null when it can't be undone.
func before(sim: CitySim, cmd: Dictionary) -> Variant:
	var type := str(cmd.get("type", ""))
	if type in ROAD_TYPES:
		return {"type": type, "money": sim.economy.money, "roads": sim.network.snapshot(), "rev": sim.network.revision,
			"county": sim.county_joined.size(), "links": sim.region_links.size(), "held": held(sim),
			"closed": sim.traffic.closed.duplicate(), "plazas": sim.parks.trails.plazas.duplicate()}
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
		e.took = took(sim, snap.held)
		# Car-free streets the build cut in two or made an avenue: car-free
		# again on undo.
		e.closed = {}
		for seg in snap.closed:
			if not sim.traffic.closed.has(seg):
				e.closed[seg] = snap.closed[seg]
		e.plazas = snap.plazas.filter(func(seg): return not seg in sim.parks.trails.plazas)
	else:
		var added: Array = things(sim, snap.type).keys().filter(func(k): return not k in snap.ids)
		if added.size() != 1:
			return
		e.id = added[0]
	entries.append(e)
	if entries.size() > KEEP:
		entries.pop_front()


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
		sim.traffic.prune_lane_rules()
		put_back(sim, e.took)
		sim.put_back_closures({"closed": e.get("closed", {}), "plazas": e.get("plazas", [])})
		# The road built before this one is current again if no road change
		# came between; something placed between (a park, a tower) doesn't
		# count (reviewer 2026-10-27: three undos left the first street in).
		for i in range(entries.size() - 1, -1, -1):
			if entries[i].has("roads"):
				if entries[i].rev == e.rev_before:
					entries[i].rev = sim.network.revision
				break
	elif not sim.apply_now({"type": PLACE_TYPES[e.type], "id": e.id}):
		return false
	sim.economy.money += int(e.refund)
	return true


## Everything the road wins could take, as it is before a road command: each
## kind's records copied whole, with what hangs off each one (sides()).
static func held(sim: CitySim) -> Dictionary:
	var out := {}
	for type in ROAD_WINS:
		var all := things(sim, type)
		var copy := {}
		for id in all:
			var hung := {}  # its place in sides() -> that table's entry
			var at := sides(sim, type, id)
			for i in at.size():
				if is_same(at[i][0], sim.families.owned):
					if at[i][0].has(at[i][1]):
						hung[i] = sim.families.keep(at[i][1])  # with its family
				elif at[i][0].has(at[i][1]):
					hung[i] = at[i][0][at[i][1]].duplicate(true)
			copy[id] = [all[id].duplicate(true), hung]
		out[type] = copy
	return out


## What a road command took, from held() before it: type -> id -> {"was":
## [record, what hung off it]} for one it bulldozed, or {"fields": {key: as
## it was}, "added": [keys], "lost": {PIECES key: [pieces]}} for one it cut
## back.
static func took(sim: CitySim, was: Dictionary) -> Dictionary:
	var out := {}
	for type in was:
		var now := things(sim, type)
		var ids: Array = was[type].keys()
		ids.sort()
		for id in ids:
			var before: Dictionary = was[type][id][0]
			var t := {}
			if not now.has(id):
				t = {"was": was[type][id]}
			elif hash(now[id]) != hash(before):
				var fields := {}
				var lost := {}
				for k in before:
					if k in PIECES and now[id].get(k) is Array and before[k] is Array:
						var gone: Array = before[k].filter(func(p): return not p in now[id][k])
						if not gone.is_empty():
							lost[k] = gone
					elif not now[id].has(k) or now[id][k] != before[k]:
						fields[k] = before[k]
				var added: Array = now[id].keys().filter(func(k): return not before.has(k))
				if fields.is_empty() and added.is_empty() and lost.is_empty():
					continue
				t = {"fields": fields, "added": added, "lost": lost}
			else:
				continue
			if not out.has(type):
				out[type] = {}
			out[type][id] = t
	return out


## Puts back what a road took (took()), once the roads it ran over are back.
static func put_back(sim: CitySim, taken: Dictionary) -> void:
	if taken.is_empty():
		return
	for type in taken:
		var now := things(sim, type)
		for id in taken[type]:
			var t: Dictionary = taken[type][id]
			if t.has("was"):
				if now.has(id):
					continue
				now[id] = t.was[0]
				# Its manager, books, family and build, unless the town still has them.
				var at := sides(sim, type, id)
				for i in t.was[1]:
					var side: Array = at[i]
					if side[0].has(side[1]):
						continue
					if is_same(side[0], sim.families.owned):
						sim.families.put_back(side[1], t.was[1][i])
					else:
						side[0][side[1]] = t.was[1][i]
			elif now.has(id):
				for k in t.fields:
					now[id][k] = t.fields[k]
				for k in t.added:
					now[id].erase(k)
				# The pieces it lost come back beside any it gained since.
				for k in t.lost:
					for p in t.lost[k]:
						if not p in now[id][k]:
							now[id][k].append(p)
	# The lots make way for them again, and whatever draws or counts them
	# catches up.
	sim._lots_dirty = true
	sim._usable_cache.clear()
	sim.farms_changed.emit()
	sim.industry_changed.emit()
	sim.warehouses_changed.emit()
	sim.big_factories_changed.emit()
	sim.parks_changed.emit()
	sim.power_changed.emit()
	sim.education_changed.emit()
	sim.telecom_changed.emit()
	sim.banks_changed.emit()
	sim.water_changed.emit()


## What hangs off a placed thing by its id outside its own record, as [table,
## key] pairs: a utility's manager and pipes, a depot's buses and routes, a
## company's books, the family that runs a farm or company, a build still
## going up. The town drops each soon after the thing goes.
static func sides(sim: CitySim, type: String, id: int) -> Array:
	match type:
		"place_service":
			return [[sim.services.water.utilities, id], [sim.buses.depots, id], [sim.buses.routes, id],
				[sim.buses.schools, id], [sim.taxis.companies, id], [sim.builders.companies, id],
				[sim.healthcare.hubs, id], [sim.construction.sites, "svc:%d" % id]]
		"place_farmhouse": return [[sim.families.owned, "farm:%d" % id], [sim.construction.sites, "farm:%d" % id]]
		"place_industry": return [[sim.families.owned, "site:%d" % id], [sim.construction.sites, "ind:%d" % id]]
		"place_warehouse": return [[sim.construction.sites, "wh:%d" % id]]
		"place_park": return [[sim.construction.sites, "park:%d" % id]]
	return []


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
