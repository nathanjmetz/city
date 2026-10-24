class_name Pollution
extends RefCounted
## Smoke, noise and dirty ground, made to be traced (Brawn, 2026-10-22: in
## Cities: Skylines it was often impossible to tell where pollution came from
## or how to fix it).
##
## Nothing here is a grid. Every source is a named thing on the map (a
## factory, a quarry, the county highway, the landfill) with points and road
## lines that pollute, and the level anywhere is worked out from the sources
## themselves. So any spot can say exactly who makes its pollution and how
## much each adds:
## - Smoke drifts downwind on the real prevailing wind (from the southwest in
##   Indiana) as a widening plume.
## - Noise spreads in rings, 6 dB quieter per doubling of distance from a
##   point and 3 dB from a long road; sources add up the way sound does.
## - Dirty ground spreads a short way from the source and seeps downhill.
##
## Other systems can pollute too through emit() and stop(), so a power plant
## or an airport shows up in the views and the "who" lists like everything
## else.

const KINDS := ["smoke", "noise", "ground"]
## Sources are re-read once a game hour; lots near anything that changed are
## then re-measured a few at a time.
const UPDATE_EVERY := 60
const TICKS_PER_DAY := 24 * 60
## Noise below this is lost under ordinary town sound (dBA).
const NOISE_FLOOR_DB := 45.0
## Smoke under this is too faint to count (ug/m3).
const SMOKE_FLOOR := 0.5
## Road exhaust fades to a third this far from the road, metres (near-road
## studies find most of it gone by 150-200 m).
const LINE_SMOKE_M := 60.0
const GROUND_FLOOR := 0.02
## Reference distance for noise levels, metres (50 ft, as FHWA uses).
const REF_M := 15.0
## Source checks a tick may spend re-measuring lots (a fixed amount, so every
## copy of the city measures the same lots on the same tick). Under 4 ms.
const CHECKS_PER_TICK := 300
## Lots are found near a source through buckets this many metres across.
const BUCKET := 400.0
## Roads are measured in straight pieces about this long, metres.
const ROAD_PIECE_M := 60.0

## Every source: ref -> {ref, name, kind, select: {type, id}, center, points:
## [[pos, weight]], lines: [[a, b, noise dB, smoke]], smoke, noise, ground,
## reach, flow (downhill drift of dirty ground), box (Rect2 it can reach),
## owner (CLEAN_TECH key, or "" when the city must fix it)}.
var sources := {}
## Sources other systems registered with emit(): ref -> the same shape.
var emitters := {}
## Road segments with a noise wall beside them: seg id -> true.
var walls := {}
## Owners' cleanup plans: ref -> {level: equipment bought, saved: dollars}.
var owners := {}
## Each lot's pollution as last measured: key -> {smoke, noise (dB), ground,
## hurt: [refs whose pollution hurts it most]}. Lots with none are left out.
var lots := {}
## How worn each home has become from living with pollution, 0 to 1.
var wear := {}
## How many homes and people each source hurts: ref -> {homes, people,
## kinds: {kind: homes where it is the worst of that kind}}.
var hurts := {}
## Ambulance calls for breathing trouble blamed on each source's smoke.
var calls := {}
## Railroads whose crossings are a quiet zone (no horns): depot id -> true.
var quiet := {}
## Ground height at a point, metres (Callable(Vector3) -> float). The terrain
## sets this so dirty ground seeps downhill; flat ground when unset.
var height := Callable():
	set(v):
		height = v
		_flows.clear()
		_height_gen += 1
var _height_gen := 0
## Downhill drift worked out for a source centre: Vector3 -> Vector3.
var _flows := {}
## Bumped whenever sources change, so views know to repaint.
var version := 0
var _source_sig := 0
## Built lots still to be re-measured against the current sources, in order.
var _queue := []
## Built lots measured (or queued) against the current sources: key -> true.
var _known := {}
## Which sources can reach each BUCKET square: Vector2i -> [refs], sorted.
var _grid := {}
## A fingerprint of everything sources and lots are read from, last hour.
var _inputs := 0
## Lots finished measuring: count who hurts whom on the next tick.
var _recount := false
## Whether this hour's fingerprint differed from the last re-read's (not
## saved: a loaded copy simply re-reads, which comes out the same).
var _changed := true
var _seen := 0
## Measured lots by BUCKET square, and where each was (kept up as lots come
## and go; not saved).
var _lot_buckets := {}
var _lot_pos := {}
var _keys_hash := 0
## Last hour's sources while rebuilding, so unchanged ones are kept.
var _prev := {}
## Factory lots found on the hour, for the re-read a tick later.
var _facs := []
var _facs_ready := false
## Boxes reached by sources that changed, until their lots are queued.
var _pending := []


# --- Other systems' sources ----------------------------------------------------

## Registers (or updates) pollution from any system: a power plant, the
## airport, a rail yard. `src` keys: name, kind (a word for the panel, e.g.
## "power plant"), points (Array of Vector3), smoke (ug/m3 100 m downwind),
## noise (dBA at 15 m from each point), ground (0-1 right beside it), reach
## (metres dirty ground spreads), select ({type, id} that "Go to" selects),
## fixes (Array of plain-words ways to clean it up). Takes effect at the next
## game hour.
func emit(ref: String, src: Dictionary) -> void:
	emitters[ref] = src


func stop(ref: String) -> void:
	emitters.erase(ref)


# --- Stepping ----------------------------------------------------------------------

func tick(sim: CitySim) -> void:
	# Counting who hurts whom waits for a tick of its own.
	# Each tick does one heavy job at most, so none goes over a few ms.
	var busy := false
	if _recount:
		_recount = false
		count_hurts(sim)
		busy = true
	# The hourly re-read, spread over three ticks: has anything changed,
	# re-read the sources, then queue the lots they could have changed.
	match sim.tick_count % UPDATE_EVERY:
		0:
			_seen = _fingerprint(sim)
			_changed = _seen != _inputs or sources.is_empty()
			# Finding the factories is a third of the re-read: do it now.
			if _changed:
				_facs = factory_keys(sim)
				_facs_ready = true
			busy = true
		1:
			if _changed:
				_reread(sim, _seen)
				busy = true
		2:
			if _changed or not _pending.is_empty():
				_scan(sim)
				busy = true
	# Lots are measured a few a tick, against the sources read on the hour,
	# so a big town never stalls on one frame.
	if not _queue.is_empty() and not busy:
		_work(sim, CHECKS_PER_TICK)
	if sim.tick_count % TICKS_PER_DAY == 0:
		_daily(sim)


## Re-reads the sources and queues the lots whose readings could have
## changed: new lots, and lots within reach of a source that appeared,
## went away or changed. A quiet town re-measures nothing.
func _refresh(sim: CitySim) -> void:
	if _fingerprint(sim) != _inputs or sources.is_empty():
		_reread(sim)
	_scan(sim)


## A hash of everything sources and lots are read from.
func _fingerprint(sim: CitySim) -> int:
	return hash([sim.buildings.keys(), sim.network.segments, sim.industry.sites, sim.farms.farms,
		sim.power.sites, sim.hubs.hubs, sim.rail.pieces, sim.rail.crossings.size(), sim.families.owned, emitters,
		owners, walls, quiet, _height_gen])


## Re-reads the sources, and notes where any that appeared, went away or
## changed can reach (for _scan).
func _reread(sim: CitySim, inputs := 0) -> void:
	_inputs = inputs if inputs != 0 else _fingerprint(sim)
	var old := sources.duplicate()
	rebuild(sim, false)
	_prune(sim)
	var changed := []
	var refs := old.keys()
	for ref in sources:
		if not old.has(ref):
			refs.append(ref)
	refs.sort()
	for ref in refs:
		var a: Dictionary = old.get(ref, {})
		var b: Dictionary = sources.get(ref, {})
		if a.is_empty() or b.is_empty() or a.sig != b.sig:
			changed.append(ref)
			for src in [a, b]:
				if not src.is_empty():
					_pending.append(src.box)
	# The grid only changes where sources did.
	if changed.size() > 40:
		_build_grid()
	else:
		for ref in changed:
			if old.has(ref):
				_grid_each(old[ref].box, func(list: Array): list.erase(ref))
			if sources.has(ref):
				_grid_each(sources[ref].box, func(list: Array): list.insert(list.bsearch(ref), ref))


## Queues the lots whose readings could have changed: new lots, and lots
## within reach of a source that changed (_pending). A quiet town re-measures
## nothing.
func _scan(sim: CitySim) -> void:
	var boxes := _pending
	_pending = []
	var dirty := {}
	# Lots built or gone since the last scan (when the set changed at all).
	var keys := sim.buildings.keys()
	var kh := hash(keys)
	if kh != _keys_hash or _lot_buckets.is_empty():
		_keys_hash = kh
		if _lot_buckets.is_empty():
			for key in _known:
				if sim.lots.has(key):
					_bucket_lot(sim, key, true)
		for key in keys:
			if not _known.has(key) and sim.lots.has(key):
				_known[key] = true
				_bucket_lot(sim, key, true)
				dirty[key] = true
		for key in _known.keys():
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_bucket_lot(sim, key, false)
				_known.erase(key)
				lots.erase(key)
	for box in boxes:
		for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
			for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
				for key in _lot_buckets.get(Vector2i(bx, bz), []):
					var p: Vector3 = sim.lots[key].pos
					if box.has_point(Vector2(p.x, p.z)):
						dirty[key] = true
	for key in _queue:
		if _known.has(key):
			dirty[key] = true
	_queue = dirty.keys()
	_queue.sort()
	if _queue.is_empty():
		_recount = true


## Adds a measured lot to (or takes it from) its bucket.
func _bucket_lot(sim: CitySim, key: String, add: bool) -> void:
	var p: Vector3 = _lot_pos.get(key, sim.lots[key].pos if sim.lots.has(key) else Vector3.ZERO)
	var bk := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
	if add:
		_lot_pos[key] = p
		if not _lot_buckets.has(bk):
			_lot_buckets[bk] = []
		_lot_buckets[bk].append(key)
	else:
		_lot_pos.erase(key)
		if _lot_buckets.has(bk):
			_lot_buckets[bk].erase(key)


## Measures queued lots until `budget` source checks are spent.
func _work(sim: CitySim, budget: int) -> void:
	var i := 0
	while i < _queue.size() and budget > 0:
		budget -= _measure_one(sim, _queue[i])
		i += 1
	_queue = _queue.slice(i)
	if _queue.is_empty():
		_recount = true


## Calls `f` with the grid list of every square `box` reaches (made if new).
func _grid_each(box: Rect2, f: Callable) -> void:
	for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
		for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
			var bk := Vector2i(bx, bz)
			if not _grid.has(bk):
				_grid[bk] = []
			f.call(_grid[bk])


func _build_grid() -> void:
	_grid.clear()
	var refs := sources.keys()
	refs.sort()
	for ref in refs:
		var box: Rect2 = sources[ref].box
		for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
			for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
				var bk := Vector2i(bx, bz)
				if not _grid.has(bk):
					_grid[bk] = []
				_grid[bk].append(ref)


## Reads every source from the city as it is now.
## Lots with a factory on them, in order.
static func factory_keys(sim: CitySim) -> Array:
	var keys := []
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.INDUSTRIAL and sim.lots.has(key):
			keys.append(key)
	keys.sort()
	return keys


func rebuild(sim: CitySim, grid := true) -> void:
	var old := sources.duplicate()
	_prev = old
	sources.clear()
	var used_names := {}
	_add_roads(sim, used_names)
	var keys := _facs if _facs_ready else factory_keys(sim)
	_facs_ready = false
	for key in keys:
		# (A factory that went in since the hour is read next hour.)
		var b: Dictionary = sim.buildings.get(key, {})
		if b.is_empty() or int(b.zone) != ZoneMap.Zone.INDUSTRIAL or not sim.lots.has(key):
			continue
		var ref: String = "lot:" + key
		var chain := str(b.get("chain", "general"))
		# A factory just like last hour keeps its source (most of a big town).
		var inp := [chain, int(b.seed), int(owners.get(ref, {}).get("level", 0)), sim.families.name_of(ref),
			sim.lots[key].pos, _height_gen]
		var was: Dictionary = old.get(ref, {})
		if not was.is_empty() and was.get("inp", []) == inp:
			was.name = _unique(used_names, was.base)
			sources[ref] = was
			continue
		var base := _named(sim, ref, factory_name(key, int(b.seed), chain))
		_add(sim, ref, _unique(used_names, base), "factory", "factory",
			{"type": "lot", "id": key}, [[sim.lots[key].pos, 1.0]],
			Balance.POLLUTION_SOURCES.factory_chains.get(chain, {}))
		if sources.has(ref):
			sources[ref].inp = inp
			sources[ref].base = base
	var ids := sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sim.industry.sites[id]
		var share: float = Balance.POLLUTION_SOURCES[s.kind].get("pad_share", 0.5)
		var pts := [[s.pos, 1.0]]
		for c in s.pads:
			pts.append([Industry.pad_center(s, c), share])
		_add(sim, "site:%d" % id, _unique(used_names, _named(sim, "site:%d" % id, company_name(s.kind, id))), s.kind, s.kind,
			{"type": "industry", "id": id}, pts)
	ids = sim.hubs.hubs.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = sim.hubs.hubs[id]
		if not Balance.POLLUTION_SOURCES.has(h.kind):
			continue
		var pts := []
		var w := 1.0 / sqrt(maxf(h.cells.size(), 1.0))
		for c in h.cells:
			pts.append([CivicHubs.cell_center(h, c), w])
		var name: String = "Town " + CivicHubs.KINDS[h.kind].name.to_lower()
		_add(sim, "hub:%d" % id, _unique(used_names, name), h.kind, "", {"type": "hub", "id": id}, pts)
	_add_power(sim, used_names)
	_add_rail(sim, used_names)
	ids = sim.farms.farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		if f.cells.is_empty():
			continue
		var pts := []
		for c in f.cells:
			pts.append([Farms.cell_center(f, c), 1.0])
		_add(sim, "farm:%d" % id, _unique(used_names, _named(sim, "farm:%d" % id, farm_name(id))), "farm", "farm",
			{"type": "farm", "id": id}, pts)
		# Its livestock barns, a source of their own (Livestock).
		var stock := Livestock.kind(f)
		if Balance.POLLUTION_SOURCES.has(stock) and not Livestock.sites(f).is_empty():
			var barns := []
			for site in Livestock.sites(f):
				barns.append([Livestock.site_center(f, site), 1.0])
			var label := "%s %s" % [_named(sim, "farm:%d" % id, farm_name(id)), str(Balance.LIVESTOCK[stock].name).to_lower()]
			_add(sim, "barns:%d" % id, _unique(used_names, label), stock, "farm", {"type": "farm", "id": id}, barns)
	var refs := emitters.keys()
	refs.sort()
	for ref in refs:
		var e: Dictionary = emitters[ref]
		var pts := []
		for p in e.get("points", []):
			pts.append([p, 1.0])
		var s := _make(ref, _unique(used_names, str(e.get("name", "Source"))), str(e.get("kind", "source")), "",
			e.get("select", {}), pts, [], float(e.get("smoke", 0.0)), float(e.get("noise", 0.0)),
			float(e.get("ground", 0.0)), float(e.get("reach", 100.0)))
		s.fixes = e.get("fixes", [])
		_finish(s)
	var sig := hash([sources.keys(), walls.keys(), owners])
	for ref in sources:
		sig = hash([sig, sources[ref].center, sources[ref].points.size(), sources[ref].lines.size()])
	if sig != _source_sig:
		_source_sig = sig
		version += 1
	_prev = {}
	if grid:
		_build_grid()


## Forgets walls on roads that are gone and owners that closed (only on the
## hourly step, so every copy of the city forgets them at the same moment).
func _prune(sim: CitySim) -> void:
	for seg in walls.keys():
		if not sim.network.segments.has(seg):
			walls.erase(seg)
	for ref in owners.keys():
		if not sources.has(ref):
			owners.erase(ref)
	for ref in calls.keys():
		if not sources.has(ref):
			calls.erase(ref)
	for id in quiet.keys():
		if not sim.rail.depots.has(id):
			quiet.erase(id)


## Highways and ramps, then boulevards, each joined into one source per
## connected stretch, sampled as lines.
func _add_roads(sim: CitySim, used_names: Dictionary) -> void:
	var net := sim.network
	for group_kind: String in ["highway", "boulevard"]:
		var types := [RoadStyle.Type.HIGHWAY, RoadStyle.Type.RAMP] if group_kind == "highway" else [RoadStyle.Type.BOULEVARD]
		var segs := []
		for id in net.segments:
			if int(net.segments[id].type) in types:
				segs.append(id)
		segs.sort()
		var seen := {}
		var n := 0
		for start in segs:
			if seen.has(start):
				continue
			# Everything joined to this segment through shared nodes.
			var group := []
			var todo := [start]
			seen[start] = true
			while not todo.is_empty():
				var id: int = todo.pop_back()
				group.append(id)
				for node in [net.segments[id].a, net.segments[id].b]:
					for other in net.segments_at(node):
						if not seen.has(other) and int(net.segments[other].type) in types:
							seen[other] = true
							todo.append(other)
			group.sort()
			var lines := []
			var link := false
			for id in group:
				var type := int(net.segments[id].type)
				var key: String = "ramp" if type == RoadStyle.Type.RAMP else group_kind
				var spec: Dictionary = Balance.POLLUTION_SOURCES[key]
				var db: float = spec.noise - (Balance.NOISE_WALL_DB if walls.has(id) else 0.0)
				var pts := net.sample_segment(id, road_pieces(net, id))
				for i in pts.size() - 1:
					lines.append([pts[i], pts[i + 1], db, float(spec.smoke)])
				link = link or sim.is_link_segment(id)
			n += 1
			var name := "County highway" if link else ("Highway" if group_kind == "highway" else "Boulevard")
			var s := _make("road:%d" % group[0], _unique(used_names, name), group_kind, "",
				{"type": "road", "id": group[0]}, [], lines, 0.0, 0.0, 0.0, 0.0)
			s.segs = group
			_finish(s)


## Power companies that burn fuel or spin turbines: one point per unit, with
## the fixes the company's own development tree offers.
func _add_power(sim: CitySim, used_names: Dictionary) -> void:
	var ids := sim.power.sites.keys()
	ids.sort()
	for id in ids:
		var site: Dictionary = sim.power.sites[id]
		var kind := "power_" + str(site.plant)
		if site.cells.is_empty() or not Balance.POLLUTION_SOURCES.has(kind):
			continue
		var spec: Dictionary = Balance.POLLUTION_SOURCES[kind]
		var pts := []
		for c in site.cells:
			pts.append([Power.cell_center(site, c), 1.0])
		var ref := "power:%d" % id
		var plain: String = Power.PLANTS[site.plant].name
		var s := _make(ref, _unique(used_names, _named(sim, ref, plain)), kind, "", {"type": "power", "id": id}, pts, [],
			float(spec.smoke) * Agency.effect(site, Power.TREE, "smoke*"), float(spec.noise), float(spec.ground),
			float(spec.reach))
		for node in Power.TREE:
			if node.id in ["scrubbers", "repower"] and site.plant in node.get("plants", []) and not node.id in site.built:
				s.fixes.append("%s (%s): %s. Its leader picks it up once the company can afford it." % [
					node.name, "$" + CitySim.money_text(int(node.cost)), node.note])
		if site.plant == "coal":
			s.fixes.append("Power companies run by better-schooled leaders build clean plants: schools in town help the next one.")
		_finish(s)


## Railroads: every finished piece of track is a line source, and each grade
## crossing a horn (unless the town made its crossings a quiet zone).
func _add_rail(sim: CitySim, used_names: Dictionary) -> void:
	var rail := sim.rail
	var ids := rail.depots.keys()
	ids.sort()
	var pids := rail.pieces.keys()
	pids.sort()
	var spec: Dictionary = Balance.POLLUTION_SOURCES.rail
	for id in ids:
		var lines := []
		var mine := {}
		for pid in pids:
			var pc: Dictionary = rail.pieces[pid]
			if int(pc.depot) != id or float(pc.built) >= 0.0:
				continue
			mine[pid] = true
			# Every ~60 m of the track's points (they come every ~10 m).
			var pts: Array = pc.pts
			var step := maxi(1, roundi(ROAD_PIECE_M / 10.0))
			var i := 0
			while i < pts.size() - 1:
				var j := mini(i + step, pts.size() - 1)
				lines.append([pts[i], pts[j], float(spec.noise), float(spec.smoke)])
				i = j
		if lines.is_empty():
			continue
		var horns := []
		if not quiet.has(id):
			for c in rail.crossings:
				if mine.has(c.piece):
					horns.append([c.pos, 1.0])
		var ref := "rail:%d" % id
		var s := _make(ref, _unique(used_names, str(rail.depots[id].name)), "railroad", "", {"type": "rail", "id": id},
			horns, lines, 0.0, float(Balance.POLLUTION_SOURCES.rail_horn.noise) if not horns.is_empty() else 0.0, 0.0, 0.0)
		_finish(s)


## What a quiet zone costs on a railroad's crossings, or -1 when it has none
## to quiet (or already is one).
func quiet_cost(sim: CitySim, ref: String) -> int:
	if not ref.begins_with("rail:") or quiet.has(int(ref.substr(5))) or not sources.has(ref):
		return -1
	var n: int = sources[ref].points.size()
	return n * Balance.QUIET_ZONE_PER_CROSSING if n > 0 else -1


static func road_pieces(net: RoadNetwork, id: int) -> int:
	var m := RoadNetwork.polyline_length(net.sample_segment(id, 4))
	return clampi(ceili(m / ROAD_PIECE_M), 1, 8)


## A source from Balance numbers, made cleaner by any equipment its owner
## has bought.
func _add(_sim: CitySim, ref: String, name: String, kind: String, owner: String, sel: Dictionary, pts: Array,
		scale := {}) -> void:
	var spec: Dictionary = Balance.POLLUTION_SOURCES[kind]
	var smoke: float = spec.smoke * scale.get("smoke", 1.0)
	var noise: float = spec.noise + scale.get("noise", 0.0)
	var ground: float = spec.ground * scale.get("ground", 1.0)
	var tech := equipment(ref, owner)
	if not tech.is_empty():
		smoke *= float(tech.smoke)
		noise += float(tech.noise)
		ground *= float(tech.ground)
	# A source just like last hour is kept as it was.
	var key := hash([kind, owner, sel, pts, smoke, noise, ground, _height_gen])
	var was: Dictionary = _prev.get(ref, {})
	if not was.is_empty() and was.get("key", 0) == key:
		was.name = name
		sources[ref] = was
		return
	_finish(_make(ref, name, kind, owner, sel, pts, [], smoke, noise, ground, float(spec.reach)))
	if sources.has(ref):
		sources[ref].key = key


func _make(ref: String, name: String, kind: String, owner: String, sel: Dictionary, pts: Array, lines: Array,
		smoke: float, noise: float, ground: float, reach: float) -> Dictionary:
	return {"ref": ref, "name": name, "kind": kind, "owner": owner, "select": sel, "points": pts, "lines": lines,
		"smoke": smoke, "noise": noise, "ground": ground, "reach": reach, "flow": Vector3.ZERO,
		"center": Vector3.ZERO, "box": Rect2(), "boxes": {}, "fixes": [], "segs": []}


## Works out a source's centre, downhill drift and the boxes each kind of
## its pollution can reach (smoke only downwind).
func _finish(s: Dictionary, find_flow := true) -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	var sum := Vector3.ZERO
	var count := 0
	var loudest: float = s.noise
	var smokiest: float = s.smoke
	for pw in s.points:
		var p: Vector3 = pw[0]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		sum += p
		count += 1
	for l in s.lines:
		for p in [l[0], l[1]]:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		sum += l[0]
		count += 1
		loudest = maxf(loudest, l[2])
		smokiest = maxf(smokiest, l[3])
	if count == 0:
		return
	s.center = sum / count
	s.center.y = 0.0
	if find_flow and height.is_valid() and s.ground > 0.0:
		var c: Vector3 = s.center
		if not _flows.has(c):
			var gx: float = (height.call(c + Vector3(30, 0, 0)) - height.call(c - Vector3(30, 0, 0))) / 60.0
			var gz: float = (height.call(c + Vector3(0, 0, 30)) - height.call(c - Vector3(0, 0, 30))) / 60.0
			var grad := Vector3(gx, 0.0, gz)
			_flows[c] = -grad.normalized() * Balance.GROUND_FLOW_M * clampf(grad.length() / 0.05, 0.0, 1.5) \
				if grad.length() > 0.002 else Vector3.ZERO
		s.flow = _flows[c]
	var core := Rect2(lo, hi - lo)
	var boxes := {}
	if loudest > NOISE_FLOOR_DB:
		boxes.noise = core.grow(noise_reach(loudest))
	if smokiest >= SMOKE_FLOOR:
		if s.lines.is_empty():
			var r := smoke_reach(smokiest)
			var w := wind() * r
			var side := (Balance.SMOKE_WIDTH + Balance.SMOKE_SPREAD * r) * 2.5
			boxes.smoke = core.grow(150.0).merge(Rect2(core.position + w, core.size).grow(side))
		else:
			boxes.smoke = core.grow(LINE_SMOKE_M * 4.0)
	if s.ground >= GROUND_FLOOR:
		var f := Vector2(s.flow.x, s.flow.z)
		boxes.ground = core.grow(s.reach * 2.5).merge(Rect2(core.position + f, core.size).grow(s.reach * 2.5))
	if boxes.is_empty():
		return
	var box := Rect2()
	for k in boxes:
		box = boxes[k] if box.size == Vector2.ZERO else box.merge(boxes[k])
	s.boxes = boxes
	s.box = box
	# Worked out once here rather than for every lot.
	s.nreach = noise_reach(s.noise) if s.noise > NOISE_FLOOR_DB else 0.0
	s.loud = pow(10.0, s.noise / 10.0)
	s.greach = s.reach * 2.5 + s.flow.length()
	var lc := []
	for l in s.lines:
		var a2 := Vector2(l[0].x, l[0].z)
		var ab := Vector2(l[1].x, l[1].z) - a2
		if ab.length() < 0.01:
			continue
		lc.append([a2, ab.normalized(), ab.length(), pow(10.0, l[2] / 10.0), noise_reach(l[2]), float(l[3])])
	s.lc = lc
	s.sig = hash([s.kind, snappedf(s.smoke, 0.0001), snappedf(s.noise, 0.0001), snappedf(s.ground, 0.0001),
		snappedf(s.reach, 0.01), _snap3(s.flow), s.points.map(func(pw): return [_snap3(pw[0]), snappedf(pw[1], 0.0001)]),
		s.lines.map(func(l): return [_snap3(l[0]), _snap3(l[1]), snappedf(l[2], 0.0001), snappedf(l[3], 0.0001)])])
	sources[s.ref] = s


static func _snap3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func noise_reach(level: float) -> float:
	return minf(REF_M * pow(10.0, (level - NOISE_FLOOR_DB) / 20.0), 2500.0)


## How far downwind a source's smoke stays above the floor, metres.
static func smoke_reach(q: float) -> float:
	if _reaches.has(q):
		return _reaches[q]
	var w := WIND
	var d := 100.0
	while d < 5000.0 and _plume(q, w * d, w) >= SMOKE_FLOOR:
		d += 50.0
	_reaches[q] = d
	return d


static var _reaches := {}


## The way smoke drifts, worked out once.
static var WIND := wind()


## The way smoke drifts, on the ground (x east, z south).
static func wind() -> Vector2:
	var to := deg_to_rad(Balance.WIND_FROM_DEG + 180.0)
	return Vector2(sin(to), -cos(to))


## Compass words for where the wind comes from and goes.
static func wind_words() -> Array:
	var names := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
	var i := posmod(roundi(Balance.WIND_FROM_DEG / 45.0), 8)
	return [names[i], names[(i + 4) % 8]]


# --- Measuring -------------------------------------------------------------------

## What one source adds at a point: Vector3(smoke ug/m3, noise as sound
## intensity relative to 0 dB, dirty ground 0-1). `only` limits it to one
## kind ("smoke", "noise" or "ground") for speed.
func source_at(s: Dictionary, p: Vector3, only := "") -> Vector3:
	var q := Vector2(p.x, p.z)
	if not s.box.has_point(q):
		return Vector3.ZERO
	var b: Dictionary = s.boxes
	var do_smoke: bool = (only == "" or only == "smoke") and b.has("smoke") and b.smoke.has_point(q)
	var do_noise: bool = (only == "" or only == "noise") and b.has("noise") and b.noise.has_point(q)
	var do_ground: bool = (only == "" or only == "ground") and b.has("ground") and b.ground.has_point(q)
	if not (do_smoke or do_noise or do_ground):
		return Vector3.ZERO
	var smoke := 0.0
	var energy := 0.0
	var clean := 1.0
	var w := WIND
	var nreach: float = s.nreach
	var loud: float = s.loud
	var greach: float = s.greach
	for pw in s.points:
		var c: Vector3 = pw[0]
		var weight: float = pw[1]
		var d := q - Vector2(c.x, c.z)
		var r := d.length()
		if do_noise and r < nreach:
			energy += weight * loud * _spread(r)
		if do_smoke and s.smoke >= SMOKE_FLOOR * 0.1:
			smoke += weight * _plume(s.smoke, d, w)
		if do_ground and r < greach:
			clean *= 1.0 - minf(weight * _seep(s.ground, s.reach, s.flow, d), 0.99)
	if not s.lc.is_empty() and (do_noise or do_smoke):
		var line_smoke := 0.0
		for l in s.lc:
			var dir: Vector2 = l[1]
			var len: float = l[2]
			var rel: Vector2 = q - l[0]
			var x := rel.dot(dir)
			var dist := maxf(absf(rel.x * dir.y - rel.y * dir.x), 5.0)
			var gap := Vector2(x - clampf(x, 0.0, len), dist).length()
			if do_noise and gap < l[4]:
				# A stretch of road: sound from every metre of it, added up
				# (3 dB quieter per doubling of distance from a long road).
				energy += l[3] * REF_M / PI \
					* (atan((len - x) / dist) - atan(-x / dist)) / dist * exp(-gap / 2000.0)
			if do_smoke and gap < LINE_SMOKE_M * 4.0:
				line_smoke = maxf(line_smoke, float(l[5]) * exp(-gap / LINE_SMOKE_M))
		smoke += line_smoke
	return Vector3(smoke, energy, 1.0 - clean)


## Sound energy share left at r metres from a point (6 dB per doubling,
## plus a little lost to air and soft ground).
static func _spread(r: float) -> float:
	var k := REF_M / maxf(r, REF_M * 0.5)
	return k * k * exp(-r / 2000.0)


## Smoke at an offset from a stack: a plume that widens and thins downwind,
## with a little haze all round the yard.
static func _plume(q: float, d: Vector2, w: Vector2) -> float:
	var along := d.dot(w)
	var cross := absf(d.x * w.y - d.y * w.x)
	var width := Balance.SMOKE_WIDTH + Balance.SMOKE_SPREAD * maxf(along, 0.0)
	# Far off to the side or upwind: nothing worth working out.
	if (along <= 0.0 or cross > width * 4.0) and absf(along) + cross > 700.0:
		return 0.0
	var around := q * 1.2 * exp(-d.length() / 70.0)
	if along <= 0.0:
		return around
	var ref_width := Balance.SMOKE_WIDTH + Balance.SMOKE_SPREAD * 100.0
	var plume := q * ref_width / width * exp(-0.5 * (cross / width) * (cross / width)) \
		* exp(-(along - 100.0) / Balance.SMOKE_FADE_M)
	return maxf(plume, around)


## Dirty ground at an offset from a source, drawn out downhill.
static func _seep(g: float, reach: float, flow: Vector3, d: Vector2) -> float:
	var f := Vector2(flow.x, flow.z)
	if f.length() < 1.0:
		return g * exp(-d.length_squared() / (reach * reach))
	var dir := f.normalized()
	var rel := d - f * 0.5
	var along := rel.dot(dir)
	var cross := rel.x * dir.y - rel.y * dir.x
	var long := reach + f.length() * 0.5
	return g * exp(-(along * along) / (long * long) - (cross * cross) / (reach * reach))


static func db(energy: float) -> float:
	return 10.0 * log(maxf(energy, 1.0)) / log(10.0)


## Everything at a point: {smoke, noise (dBA), ground, by: {kind: [[ref,
## share 0-1, amount]]}} with the biggest share first. `amount` is ug/m3,
## dB the source alone would make, or ground 0-1.
func sample(p: Vector3) -> Dictionary:
	var parts := {"smoke": [], "noise": [], "ground": []}
	var total := Vector3.ZERO
	var clean := 1.0
	for ref in _grid.get(Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET)), []):
		var v := source_at(sources[ref], p)
		if v == Vector3.ZERO:
			continue
		total.x += v.x
		total.y += v.y
		clean *= 1.0 - v.z
		if v.x >= SMOKE_FLOOR * 0.25:
			parts.smoke.append([ref, v.x, v.x])
		if db(v.y) >= NOISE_FLOOR_DB - 6.0:
			parts.noise.append([ref, v.y, db(v.y)])
		if v.z >= GROUND_FLOOR * 0.5:
			parts.ground.append([ref, v.z, v.z])
	var sums := {"smoke": total.x, "noise": total.y}
	var gsum := 0.0
	for e in parts.ground:
		gsum += e[1]
	sums.ground = gsum
	for k in parts:
		for e in parts[k]:
			e[1] = e[1] / maxf(sums[k], 1e-9)
		parts[k].sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	return {"smoke": total.x, "noise": db(total.y), "ground": 1.0 - clean, "by": parts}


## Re-measures every built lot now (tests, tools; the game itself measures a
## few lots a tick, see tick).
func measure_lots(sim: CitySim) -> void:
	lots.clear()
	_known.clear()
	_lot_buckets.clear()
	_lot_pos.clear()
	for key in sim.buildings:
		if sim.lots.has(key):
			_known[key] = true
	_queue = _known.keys()
	_queue.sort()
	_work(sim, 1 << 62)
	count_hurts(sim)
	_recount = false


## Measures one built lot against the sources that can reach its square.
## Returns how many source checks it took.
func _measure_one(sim: CitySim, key: String) -> int:
	lots.erase(key)
	if not sim.lots.has(key) or not sim.buildings.has(key):
		return 1
	var p: Vector3 = sim.lots[key].pos
	var checks := 1
	var a := [0.0, 0.0, 1.0, {}]   # smoke, energy, clean, {ref: Vector3}
	for ref in _grid.get(Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET)), []):
		checks += 1
		var v := source_at(sources[ref], p)
		if v == Vector3.ZERO:
			continue
		a[0] += v.x
		a[1] += v.y
		a[2] *= 1.0 - v.z
		a[3][ref] = v
	# Rounded as saved, so a loaded copy has exactly the same land values.
	var e := {"smoke": snappedf(a[0], 0.001), "noise": snappedf(db(a[1]), 0.001),
		"ground": snappedf(1.0 - a[2], 0.0001), "hurt": []}
	if e.smoke < SMOKE_FLOOR and e.noise < Balance.NOISE_QUIET_DB - 5.0 and e.ground < GROUND_FLOOR:
		return checks
	# Who hurts it: the biggest share of each kind that is over the line.
	var hurt := {}
	var worst := {}
	for k in [["smoke", 0, Balance.HURT_SMOKE], ["noise", 1, Balance.HURT_NOISE_DB], ["ground", 2, Balance.HURT_GROUND]]:
		if e[k[0]] < k[2]:
			continue
		var best := ""
		var best_v := 0.0
		for ref in a[3]:
			var v: Vector3 = a[3][ref]
			if v[k[1]] > best_v:
				best_v = v[k[1]]
				best = ref
		if best != "":
			hurt[best] = true
			worst[k[0]] = best
	var h := hurt.keys()
	h.sort()
	e.hurt = h
	e.by = worst
	lots[key] = e
	return checks


func count_hurts(sim: CitySim) -> void:
	hurts.clear()
	for key in lots:
		var b: Dictionary = sim.buildings.get(key, {})
		if b.is_empty() or int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		for ref in lots[key].hurt:
			if not hurts.has(ref):
				hurts[ref] = {"homes": 0, "people": 0, "kinds": {}}
			hurts[ref].homes += 1
			hurts[ref].people += int(b.occ)
		for kind in lots[key].get("by", {}):
			var ref: String = lots[key].by[kind]
			if hurts.has(ref):
				hurts[ref].kinds[kind] = int(hurts[ref].kinds.get(kind, 0)) + 1


# --- Effects ---------------------------------------------------------------------

## How much more likely a home is to call an ambulance, from its smoke (1.0
## is no change), for Healthcare.
func call_weight(key: String) -> float:
	var e: Dictionary = lots.get(key, {})
	if e.is_empty():
		return 1.0
	return 1.0 + Balance.SMOKE_CALL_WEIGHT * maxf(float(e.smoke) - Balance.HURT_SMOKE, 0.0) / Balance.HURT_SMOKE \
		+ (Balance.SMOKE_CALL_WEIGHT if float(e.smoke) >= Balance.HURT_SMOKE else 0.0)


## A call from a home over the smoke line: true (and blamed on the source
## with the biggest share of its smoke) when it is breathing trouble.
## `roll` is a 0-1 draw from the caller's own random numbers.
func breathing_call(sim: CitySim, key: String, roll: float) -> bool:
	var e: Dictionary = lots.get(key, {})
	if e.is_empty() or float(e.smoke) < Balance.HURT_SMOKE or roll >= Balance.SMOKE_BREATHING_SHARE \
			or not sim.lots.has(key):
		return false
	var by: Array = sample(sim.lots[key].pos).by.smoke
	if by.is_empty():
		return false
	calls[by[0][0]] = int(calls.get(by[0][0], 0)) + 1
	return true


## A lot's land value factor from pollution and wear: 1.0 is no change.
func lot_factor(sim: CitySim, key: String) -> float:
	var e: Dictionary = lots.get(key, {})
	var worn: float = wear.get(key, 0.0)
	if e.is_empty() and worn <= 0.0:
		return 1.0
	var zone := ZoneMap.Zone.RESIDENTIAL
	if sim.buildings.has(key):
		zone = int(sim.buildings[key].zone)
	var weight: float = Balance.POLLUTION_ZONE_WEIGHT.get(zone, 1.0)
	return 1.0 + maxf(penalty(e) * weight + worn * Balance.WEAR_VALUE, Balance.POLLUTION_VALUE_FLOOR)


## The land value change from a pollution reading (0 or below).
static func penalty(e: Dictionary) -> float:
	if e.is_empty():
		return 0.0
	var v := maxf(float(e.noise) - Balance.NOISE_QUIET_DB, 0.0) * Balance.NOISE_VALUE_PER_DB
	v += float(e.smoke) * Balance.SMOKE_VALUE_PER_UG
	v += float(e.ground) * Balance.GROUND_VALUE
	return maxf(v, Balance.POLLUTION_VALUE_FLOOR)


## Once a game day (a month): homes wear toward how bad their air, noise and
## ground are, and owners put money toward cleaner equipment.
func _daily(sim: CitySim) -> void:
	var k := 1.0 - pow(0.5, 1.0 / Balance.WEAR_HALF_LIFE_DAYS)
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		var goal := clampf(-penalty(lots.get(key, {})) / 0.25, 0.0, 1.0)
		var w: float = wear.get(key, 0.0)
		w += (goal - w) * k
		if w < 0.01 and goal == 0.0:
			wear.erase(key)
		else:
			wear[key] = snappedf(w, 0.0001)
	for key in wear.keys():
		if not sim.buildings.has(key):
			wear.erase(key)
	var refs := sources.keys()
	refs.sort()
	for ref in refs:
		var s: Dictionary = sources[ref]
		if s.owner == "" or next_equipment(ref, s.owner).is_empty():
			continue
		var plan: Dictionary = owners.get(ref, {"level": 0, "saved": 0.0})
		plan.saved = roundf(float(plan.saved) + monthly_saving(sim, s))
		var next := next_equipment(ref, s.owner)
		if plan.saved >= float(next.cost):
			plan.saved -= float(next.cost)
			plan.level = int(plan.level) + 1
		owners[ref] = plan


## What an owner puts toward cleaner equipment a month.
func monthly_saving(sim: CitySim, s: Dictionary) -> float:
	var base: float = Balance.CLEAN_SAVE_PER_MONTH.get(s.owner, 0.0)
	base *= lerpf(Balance.CLEAN_UNEDUCATED, 1.0, owner_education(sim, s))
	var homes: int = hurts.get(s.ref, {}).get("homes", 0)
	return base * (1.0 + minf(homes * Balance.CLEAN_COMPLAINT_PER_HOME, Balance.CLEAN_COMPLAINT_MAX))


## How educated an owner is, 0 to 1: the leaders the town's graduates make
## (Education.leader_education), or at least CLEAN_SCHOOL_EDUCATION with a
## school nearby. Educated owners know the cleaner ways and have the people
## to run them.
func owner_education(sim: CitySim, s: Dictionary) -> float:
	var e := sim.education.leader_education(int(sim.stats.workers))
	var reach: float = Services.KINDS[Services.Kind.SCHOOL].reach
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if int(b.kind) == Services.Kind.SCHOOL and b.pos.distance_to(s.center) <= reach:
			return maxf(e, Balance.CLEAN_SCHOOL_EDUCATION)
	return e


func educated(sim: CitySim, s: Dictionary) -> bool:
	return owner_education(sim, s) >= 0.5


## The equipment an owner has now ({} for none), and what comes next.
func equipment(ref: String, owner: String) -> Dictionary:
	var level: int = owners.get(ref, {}).get("level", 0)
	if owner == "" or level <= 0:
		return {}
	return Balance.CLEAN_TECH[owner][mini(level, Balance.CLEAN_TECH[owner].size()) - 1]


func next_equipment(ref: String, owner: String) -> Dictionary:
	if owner == "" or not Balance.CLEAN_TECH.has(owner):
		return {}
	var level: int = owners.get(ref, {}).get("level", 0)
	var list: Array = Balance.CLEAN_TECH[owner]
	return list[level] if level < list.size() else {}


## What the city would pay to finish an owner's next upgrade now.
func help_cost(ref: String) -> int:
	if not sources.has(ref):
		return -1
	var next := next_equipment(ref, sources[ref].owner)
	if next.is_empty():
		return -1
	return maxi(roundi(float(next.cost) - float(owners.get(ref, {}).get("saved", 0.0))), 0)


## Metres of noise wall a road source needs, and what it costs the city.
func wall_cost(sim: CitySim, ref: String) -> int:
	var s: Dictionary = sources.get(ref, {})
	if s.is_empty() or s.segs.is_empty():
		return -1
	var m := 0.0
	for seg in s.segs:
		if not walls.has(seg) and sim.network.segments.has(seg):
			m += RoadNetwork.polyline_length(sim.network.sample_segment(seg, 8))
	return roundi(m * Balance.NOISE_WALL_PER_M) if m > 0.0 else -1


## Player commands: {type: "fund_cleanup", ref} pays the rest of an owner's
## next upgrade; {type: "noise_wall", ref} walls a road source;
## {type: "quiet_zone", ref} quiets a railroad's crossings.
func command(sim: CitySim, cmd: Dictionary) -> bool:
	var ref := str(cmd.get("ref", ""))
	match cmd.type:
		"fund_cleanup":
			var cost := help_cost(ref)
			if cost < 0 or cost > sim.economy.money:
				return false
			sim.economy.money -= cost
			var plan: Dictionary = owners.get(ref, {"level": 0, "saved": 0.0})
			plan.level = int(plan.level) + 1
			plan.saved = 0.0
			owners[ref] = plan
		"noise_wall":
			var cost := wall_cost(sim, ref)
			if cost < 0 or cost > sim.economy.money:
				return false
			sim.economy.money -= cost
			for seg in sources[ref].segs:
				walls[seg] = true
		"quiet_zone":
			var cost := quiet_cost(sim, ref)
			if cost < 0 or cost > sim.economy.money:
				return false
			sim.economy.money -= cost
			quiet[int(ref.substr(5))] = true
		_:
			return false
	_refresh(sim)
	return true


# --- Names -------------------------------------------------------------------------

const _SURNAMES := ["Hoosier", "Mississinewa", "Gas Belt", "Wabash", "Grant County", "Kessler", "Brandt", "Overman",
	"Harmon", "Schulte", "Vogel", "Eckert", "Lugar", "Ohler", "Meyer", "Jonesboro", "Krieg", "Lindsey",
	"Black Creek", "Hackleman", "Arthur", "Matthews", "Fowlerton", "Point Isabel"]
const _PLANTS := ["Feed Mill", "Tool & Die", "Plastics", "Foundry", "Box Co.", "Machine Works", "Packing Plant",
	"Cannery", "Brick Works", "Coatings", "Millwork", "Fabrication"]


## What each industry chain's plants are called.
const _CHAIN_PLANTS := {"mill": ["Feed Mill", "Grain Mill", "Ethanol Plant", "Cannery"],
	"sawmill": ["Sawmill", "Millwork", "Pallet Co.", "Furniture"], "refinery": ["Refinery", "Asphalt Plant"],
	"metal": ["Foundry", "Steel Works", "Machine Works", "Fabrication"]}


static func factory_name(key: String, bseed: int, chain := "general") -> String:
	var h := absi(hash([key, bseed]))
	var plants: Array = _CHAIN_PLANTS.get(chain, _PLANTS)
	return "%s %s" % [_SURNAMES[h % _SURNAMES.size()], plants[(h / 7) % plants.size()]]


static func company_name(kind: String, id: int) -> String:
	var h := absi(hash(["company", kind, id]))
	var tail := {"oil": "Oil Co.", "ore": "Coal Co.", "forest": "Timber"}
	return "%s %s" % [_SURNAMES[h % _SURNAMES.size()], tail.get(kind, "Co.")]


static func farm_name(id: int) -> String:
	var h := absi(hash(["farm", id]))
	return "%s farm" % _SURNAMES[h % _SURNAMES.size()]


## The family business's own name (Families), or ours until it has one.
static func _named(sim: CitySim, ref: String, plain: String) -> String:
	var n := sim.families.name_of(ref)
	return n if n != "" else plain


static func _unique(used: Dictionary, name: String) -> String:
	var n: int = used.get(name, 0) + 1
	used[name] = n
	return name if n == 1 else "%s %d" % [name, n]


# --- Saving ------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var lot_out := {}
	for key in lots:
		var e: Dictionary = lots[key]
		lot_out[key] = [snappedf(e.smoke, 0.001), snappedf(e.noise, 0.001), snappedf(e.ground, 0.0001), e.hurt,
			e.get("by", {})]
	var wear_out := {}
	for key in wear:
		wear_out[key] = snappedf(wear[key], 0.0001)
	var out := {"walls": walls.keys(), "owners": owners.duplicate(true), "lots": lot_out, "wear": wear_out,
		"calls": calls.duplicate(), "quiet": quiet.keys()}
	# The sources lots are measured against, and where measuring is, so a
	# loaded copy carries on exactly the same way.
	var srcs := []
	var refs := sources.keys()
	refs.sort()
	for ref in refs:
		srcs.append(_source_out(sources[ref]))
	out.sources = srcs
	out.queue = _queue.duplicate()
	var known := _known.keys()
	known.sort()
	out.known = known
	out.pending = _pending.map(func(r: Rect2): return [r.position.x, r.position.y, r.size.x, r.size.y])
	return out


func _source_out(s: Dictionary) -> Dictionary:
	var pts := []
	for pw in s.points:
		pts.append([pw[0].x, pw[0].y, pw[0].z, pw[1]])
	var lines := []
	for l in s.lines:
		lines.append([l[0].x, l[0].y, l[0].z, l[1].x, l[1].y, l[1].z, l[2], l[3]])
	return {"ref": s.ref, "name": s.name, "kind": s.kind, "owner": s.owner, "select": s.select, "points": pts,
		"lines": lines, "smoke": s.smoke, "noise": s.noise, "ground": s.ground, "reach": s.reach,
		"flow": [s.flow.x, s.flow.z], "segs": s.segs, "fixes": s.fixes}


func _source_in(d: Dictionary) -> void:
	var pts := []
	for p in d.points:
		pts.append([Vector3(p[0], p[1], p[2]), float(p[3])])
	var lines := []
	for l in d.lines:
		lines.append([Vector3(l[0], l[1], l[2]), Vector3(l[3], l[4], l[5]), float(l[6]), float(l[7])])
	var sel: Dictionary = d.select
	if sel.has("id") and sel.get("type", "") != "lot" and sel.get("type", "") != "spot":
		sel = {"type": sel.type, "id": int(sel.id)}
	var s := _make(d.ref, d.name, d.kind, d.owner, sel, pts, lines, float(d.smoke), float(d.noise),
		float(d.ground), float(d.reach))
	s.segs = Array(d.segs).map(func(x): return int(x))
	s.fixes = d.fixes
	s.flow = Vector3(d.flow[0], 0.0, d.flow[1])
	_finish(s, false)


## After loading: the sources as the save had them.
func after_load(sim: CitySim) -> void:
	if sources.is_empty():
		rebuild(sim)  # an older save without its sources
	count_hurts(sim)


func from_dict(d: Dictionary) -> void:
	walls.clear()
	for seg in d.get("walls", []):
		walls[int(seg)] = true
	owners.clear()
	var o: Dictionary = d.get("owners", {})
	for ref in o:
		owners[ref] = {"level": int(o[ref].level), "saved": float(o[ref].saved)}
	lots.clear()
	var l: Dictionary = d.get("lots", {})
	for key in l:
		var e: Array = l[key]
		lots[key] = {"smoke": float(e[0]), "noise": float(e[1]), "ground": float(e[2]), "hurt": Array(e[3]),
			"by": Dictionary(e[4]) if e.size() > 4 else {}}
	wear.clear()
	var w: Dictionary = d.get("wear", {})
	for key in w:
		wear[key] = float(w[key])
	quiet.clear()
	for id in d.get("quiet", []):
		quiet[int(id)] = true
	calls.clear()
	var c: Dictionary = d.get("calls", {})
	for ref in c:
		calls[ref] = int(c[ref])
	sources.clear()
	hurts.clear()
	_source_sig = 0
	for src in d.get("sources", d.get("pass", [])):
		_source_in(src)
	_build_grid()
	_queue = Array(d.get("queue", []))
	_pending = Array(d.get("pending", [])).map(func(r): return Rect2(r[0], r[1], r[2], r[3]))
	_changed = true
	# The factory list is a cache for the hour's re-read, never saved: a
	# copy finds it again, so saves match whichever tick they're taken on.
	_facs_ready = false
	_facs = []
	_lot_buckets.clear()
	_lot_pos.clear()
	_keys_hash = 0
	_known.clear()
	for key in d.get("known", []):
		_known[key] = true
	version += 1
