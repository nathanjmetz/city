class_name Region
extends RefCounted
## A shared region: every player's city on one open map, plus the chat.
##
## Each city is its own CitySim with its own budget, placed at an origin on
## the shared map. Each player's own computer runs their own town and sends
## the server a copy every few seconds; the server keeps the latest copy of
## every town (a town whose player is away simply waits) and passes copies
## on, so everyone sees their neighbors. The server also places new towns,
## settles trade between towns that are online, and keeps the chat.

## "Elbow room": a new town starts at least this far from the edge of
## every other town, in metres (3 miles), so nobody is boxed in early.
const ELBOW_ROOM := 4828.0
## ...and never in the direction a town is growing: within this angle
## either side of the way it has grown from its centre (degrees).
const GROWTH_WEDGE := 30.0
## A town centre needs this much dry, gentle land around it (metres).
const SITE_RADIUS := 200.0
## Chat lines kept and sent to players who join.
const CHAT_KEEP := 100
## Which real map the region is built on. When a build changes it, the
## server starts the shared region over on the new map by itself, and every
## player keeps their account and PIN. Bump PROTOCOL in RegionServer too, so
## a computer still on the old map is asked to update instead of joining.
const MAP := "grantcounty"
## The county highway runs this far out of a town toward open country.
const COUNTY_REACH := 2000.0
## A new town is linked by county road to this many of its nearest towns.
const LINK_TOWNS := 2
## Trade between online towns settles this often, in real seconds (a game
## month, which is a game day, at normal speed).
const TRADE_SECONDS := 24.0 * 60.0 / CitySim.TICKS_PER_SECOND

## city id -> {"owner": player id, "player": player name, "name": city name,
## "origin": Vector2, "color": int, "sim": CitySim}
var cities := {}
var chat := []  # [{"from", "text", "at"}]
## Where two towns' county roads meet on the city line, so traffic can pass
## from one to the other: [{"a": city id, "a_at": [x, z], "b": city id,
## "b_at": [x, z]}], each end in its own town's coordinates.
var joins := []
var region_seed := 1
## Regional projects and service agreements between towns (see Ledger).
var ledger := Ledger.new()
## Roads the last add_city built in existing towns (their halves of the new
## county roads): city id -> [commands]. Their owners, if online, run them
## on their own computers too.
var handed := {}
## The latest copy of each town as saved data. Unpacking a copy into a full
## simulation is slow (about a second for a grown town), so a copy that
## arrives is only kept here until something needs the simulation itself
## (placing a town, trade, drawing a neighbor): see load_stale().
## Whose land is whose: city id -> {Vector2i: true}, the LAND_CELL squares
## (region coordinates) each town has built on (see CitySim.land_cells).
## Sent with each town's copy, so nobody needs a neighbor's whole town to
## know where its land is.
var land := {}
var _data := {}   # city id -> its newest copy: a postcard or a full copy (sim.to_dict())
var _stale := {}  # city ids whose simulation is older than _data
## city id -> its newest full copy (people, cars and plans too): what its
## player gets back on another computer, and what the region saves. Players
## send a full copy every few minutes and postcards in between (see
## CitySim.to_dict).
var _full := {}
## The same copies packed for the wire (RegionServer.pack), as they came in
## or packed once: city id -> text. A welcome sends them as they are.
var _full_z := {}
var _card_z := {}
## city id -> a number that goes up with each new full copy (for the
## server's save, which keeps each town's text until it changes).
var _copy_n := {}
## Roads the region handed a town (its half of a new neighbor's county
## road) that its copies may not have yet: city id -> [commands]. Its own
## computer builds them (at once if it's running, else when it comes back
## and unpacks its full copy, see _add_pending), so no neighbor's town is
## unpacked on the server when a new one joins. Never built into a
## neighbor's postcard: that would plan its lots afresh (seconds, and the
## postcard has no plans to keep). So while its player is away, others see
## that half of the road only once they're back.
var pending := {}


## The city a player owns, or "" if they have none yet.
func city_of(player_id: String) -> String:
	for id in cities:
		if cities[id].owner == player_id:
			return id
	return ""


## Gives a new player their own city in open land next to the others,
## joined to them by county road: a crossroads start. The first town gets a
## county highway straight through; each later one gets a road to each of
## its nearest towns (meeting theirs halfway, on the city line) and one on
## out to open country. The roads are free and can't be bulldozed.
## Takes a town off the map: its label, land, copies and road links. Its
## neighbors keep their halves of the county roads.
func remove_city(id: String) -> void:
	for d in [cities, land, _data, _stale, _full, _full_z, _card_z, _copy_n, away, handed, pending]:
		d.erase(id)
	joins = joins.filter(func(j): return j.a != id and j.b != id)


##
## With `quick` (the server, where players are waiting), no town is
## unpacked: the new one is placed from what is already unpacked and each
## town's land, and the neighbors' halves of the county roads are handed
## over as `pending` instead of built here (their computers build them).
func add_city(player_id: String, player: String, quick := false) -> String:
	if not quick:
		load_stale()
	handed = {}
	var id := "c%d" % (cities.size() + 1)
	while cities.has(id):
		id += "x"
	var sim := new_sim()
	sim.city_seed = hash([region_seed, id])
	var origin := _free_spot()
	sim.terrain_offset = origin
	var near := _nearest_cities(origin, LINK_TOWNS)
	# A town founded at a real small town's crossroads takes its name.
	var town_name := player + "ville"
	for site in Backdrop.sites():
		if site.centre.snapped(Vector2(CountyGrid.SECTION, CountyGrid.SECTION)) == origin:
			town_name = site.name
	cities[id] = {"owner": player_id, "player": player, "name": town_name, "origin": origin,
		"color": cities.size() % Brand.PLAYERS.size(), "sim": sim}
	if near.is_empty():
		sim.build_county_road(Vector2(-COUNTY_REACH, 0), Vector2(COUNTY_REACH, 0), [0, 1])
	else:
		var away := Vector2.ZERO
		for other in near:
			var o: Dictionary = cities[other]
			var meet: Vector2 = ((origin + o.origin) * 0.5).snapped(Vector2(1, 1))
			away -= (meet - origin).normalized()
			sim.build_county_road(Vector2.ZERO, meet - origin, [1])
			# Their half starts from their nearest road, so it joins their town.
			var to: Vector2 = meet - o.origin
			var cmd := {}
			if quick:
				var from := _nearest_road_of(other, to)
				cmd = {"type": "build_county_road", "a": [from.x, from.y], "b": [to.x, to.y], "links": [1]}
				if not pending.has(other):
					pending[other] = []
				pending[other].append(cmd)
			else:
				# Their newest full copy, so the road goes into a whole town.
				_load_full(other)
				var their: CitySim = o.sim
				var from := _nearest_road_point(their, to)
				cmd = {"type": "build_county_road", "a": [from.x, from.y], "b": [to.x, to.y], "links": [1]}
				their.apply_now(cmd)
			if not handed.has(other):
				handed[other] = []
			handed[other].append(cmd)
			var here: Vector2 = meet - origin
			joins.append({"a": id, "a_at": [here.x, here.y], "b": other, "b_at": [to.x, to.y]})
		if away.length() < 0.1:
			away = (origin - cities[near[0]].origin).orthogonal()
		sim.build_county_road(Vector2.ZERO, away.normalized() * COUNTY_REACH, [1])
	sim.economy.money = Economy.START_MONEY
	take_land(id, land_of_sim(id))
	touched(id)
	if not quick:
		for other in handed:
			touched(other)
	return id


## A city simulation set up the way the game plays it, the same on every copy.
static func new_sim() -> CitySim:
	var sim := CitySim.new()
	sim.require_utilities = true
	sim.in_region = true
	return sim


## Takes the latest copy of a town from its player's computer: a postcard
## or a full copy.
## `full_z` and `card_z` are the copy packed (the server has them as they
## came in), kept for sending on. Returns whether it was taken.
func update_city(id: String, d: Dictionary, full_z := "", card_z := "") -> bool:
	# A full copy without roads is broken (a cut-short save): never let it
	# replace a town.
	if not d.get("postcard", false) and not d.has("roads"):
		return false
	if not cities.has(id):
		return false
	_data[id] = d
	_stale[id] = true
	_card_z.erase(id)
	if card_z != "":
		_card_z[id] = card_z
	if not d.get("postcard", false):
		_full[id] = d
		_full_z.erase(id)
		if full_z != "":
			_full_z[id] = full_z
		_count_copy(id)
	_drop_built(id, d)
	return true


var _copies := 0


func _count_copy(id: String) -> void:
	_copies += 1
	_copy_n[id] = _copies


## A number that changes whenever the town's full copy does.
func copy_number(id: String) -> int:
	return int(_copy_n.get(id, 0))


## The town's newest full copy, packed (packed here only if it wasn't).
func packed_full(id: String) -> String:
	if not _full_z.has(id):
		_full_z[id] = RegionServer.pack(city_data(id))
	return _full_z[id]


## The town's newest postcard, packed (packed here only if it wasn't).
func packed_card(id: String) -> String:
	if not _card_z.has(id):
		_card_z[id] = RegionServer.pack(postcard_data(id))
	return _card_z[id]


## Packs every town (the server, while starting up).
func pack_all() -> void:
	for id in cities:
		packed_full(id)
		packed_card(id)


## A town's money, from its newest copy (without unpacking it).
func money_of(id: String) -> float:
	if _stale.has(id):
		return float(_data[id].get("economy", {}).get("money", 0.0))
	return cities[id].sim.economy.money if cities.has(id) else 0.0


## A town's road node nearest a spot (its coordinates), from its newest copy.
func _nearest_road_of(id: String, to: Vector2) -> Vector2:
	if _stale.has(id) and _data[id].get("roads") is Dictionary:
		return _nearest_road_point_in(_data[id].roads, to)
	return _nearest_road_point(cities[id].sim, to)


## The road node nearest a spot, from roads as saved data (city
## coordinates), or the centre: the same as _nearest_road_point.
static func _nearest_road_point_in(roads: Dictionary, to: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var nodes: Dictionary = roads.get("nodes", {})
	var ids := []
	for k in nodes:
		ids.append(int(k))
	ids.sort()
	for n in ids:
		var p: Array = nodes[str(n)]
		var d := Vector2(float(p[0]), float(p[1])).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = Vector2(float(p[0]), float(p[1]))
	return best


## The node of roads (as saved data) within `within` metres of a spot, -1
## if none: the same as RoadNetwork.find_node_near.
static func _node_in(roads: Dictionary, at: Vector2, within: float) -> int:
	var best := -1
	var best_d := within
	var nodes: Dictionary = roads.get("nodes", {})
	for k in nodes:
		var p: Array = nodes[k]
		var d := Vector2(float(p[0]), float(p[1])).distance_to(at)
		if d <= best_d:
			best_d = d
			best = int(k)
	return best


## A copy that has a handed road already: it needn't be handed again.
func _drop_built(id: String, d: Dictionary) -> void:
	if not pending.has(id) or not d.get("roads") is Dictionary:
		return
	pending[id] = pending[id].filter(func(cmd): return _node_in(d.roads, _cmd_end(cmd), 3.0) < 0)
	if pending[id].is_empty():
		pending.erase(id)


static func _cmd_end(cmd: Dictionary) -> Vector2:
	var b: Array = cmd.get("b", [0, 0])
	return Vector2(float(b[0]), float(b[1]))


## Builds the handed roads a town's simulation doesn't have yet (only for
## a full copy: see pending).
func _add_pending(id: String) -> void:
	if pending.has(id) and cities.has(id):
		build_missing(cities[id].sim, pending[id])


## Builds the county roads handed to a town that it doesn't have yet (each
## ends at a node on the city line, so one there means it's built).
static func build_missing(sim: CitySim, cmds: Array) -> void:
	for cmd in cmds:
		if cmd is Dictionary:
			var end := _cmd_end(cmd)
			if sim.network.find_node_near(Vector3(end.x, 0, end.y), 3.0) < 0:
				sim.apply_now(cmd)


## Loads a town's simulation from its newest full copy, for changing it
## here (a postcard has no people or plans to keep).
func _load_full(id: String) -> void:
	var d: Dictionary = _full.get(id, {})
	if d.is_empty():
		load_stale(id)
		return
	cities[id].sim.terrain_offset = cities[id].origin
	cities[id].sim.from_dict(d)
	_stale.erase(id)
	_add_pending(id)


## Unpacks the waiting copies into their simulations: all of them, or just
## the one given. Returns the ids loaded.
func load_stale(only := "") -> Array:
	var ids: Array = [only] if only != "" else _stale.keys()
	var done := []
	for id in ids:
		if _stale.has(id) and cities.has(id):
			var sim: CitySim = cities[id].sim
			sim.terrain_offset = cities[id].origin
			sim.from_dict(_data[id])
			done.append(id)
			_stale.erase(id)
			if not _data[id].get("postcard", false):
				_add_pending(id)
		_stale.erase(id)
	if not done.is_empty():
		share_care()
	return done


## The towns whose newest copy hasn't been unpacked yet.
func stale_ids() -> Array:
	return _stale.keys()


## A town's full saved data, made from its simulation only when there's no
## copy (a town made or changed here).
func city_data(id: String) -> Dictionary:
	if not _full.has(id):
		_full[id] = cities[id].sim.to_dict()
		_data[id] = _full[id]
		_full_z.erase(id)
		_card_z.erase(id)
		_count_copy(id)
	return _full[id]


## A town as its neighbors need it: its newest postcard.
func postcard_data(id: String) -> Dictionary:
	if _data.has(id) and _data[id].get("postcard", false):
		return _data[id]
	return postcard_of(city_data(id))


## A full copy cut down to a postcard (it shares the full copy's parts).
static func postcard_of(d: Dictionary) -> Dictionary:
	if d.get("postcard", false):
		return d
	var p := d.duplicate()
	for key in CitySim.POSTCARD_SKIP:
		p.erase(key)
	p.postcard = true
	return p


## Call after changing a town's simulation directly, so its saved data is
## made afresh.
func touched(id: String) -> void:
	for d in [_data, _full, _stale, _full_z, _card_z]:
		d.erase(id)
	_count_copy(id)


## Neighbors' hospitals draw patients from every town in the region, and
## their helipads and specialty centers lift care in the others.
func share_care() -> void:
	for id in cities:
		var others := 0
		var offered := 0.0
		for other in cities:
			if other != id:
				others += int(cities[other].sim.stats.get("population", 0))
				offered = maxf(offered, cities[other].sim.healthcare.care_offered())
		cities[id].sim.healthcare.region_pop = others
		cities[id].sim.healthcare.region_care = offered


# --- While you were away ----------------------------------------------------

## Where every other town stood when a player left: city id -> {"at": unix
## seconds, "towns": {other id: glance}, "stages": {project id: stages
## funded}}. Their return compares it with now (away_report), so their town
## can catch up on what the neighbors did meanwhile (CatchUp). The server
## saves it with the region.
var away := {}


## A town at a glance, from its newest copy (no unpacking): its clock in
## ticks, its people and how many homes, shops and workplaces it has.
func glance(id: String) -> Dictionary:
	var sim: CitySim = cities[id].sim
	var d: Dictionary = _data.get(id, {})
	var tick := int(d.get("tick", sim.tick_count))
	var b: Dictionary = d.get("buildings", sim.buildings) if d.has("buildings") else sim.buildings
	var counts := [0, 0, 0, 0]
	for key in b:
		var z := int(b[key].get("zone", 0))
		if z >= 0 and z < counts.size():
			counts[z] += 1
	var pop := int(ledger.populations.get(id, sim.stats.get("population", 0)))
	return {"tick": tick, "pop": pop, "homes": counts[ZoneMap.Zone.RESIDENTIAL],
		"shops": counts[ZoneMap.Zone.COMMERCIAL], "works": counts[ZoneMap.Zone.INDUSTRIAL]}


## Notes where everyone else stands as a player leaves.
func mark_away(id: String, now := int(Time.get_unix_time_from_system())) -> void:
	if not cities.has(id):
		return
	var towns := {}
	for other in cities:
		if other != id:
			towns[other] = glance(other)
	var stages := {}
	for pid in ledger.projects:
		stages[pid] = Ledger.stages_done(ledger.projects[pid])
	away[id] = {"at": now, "towns": towns, "stages": stages}


## What the neighbors did while a player was away, used once (their
## next return asks again from a new mark): {"seconds", "ticks": the most
## game time any neighbor played, "towns": [{"id", "name", "player",
## "ticks", "pop", "homes", "shops", "works" (the changes), "new": a town
## founded meanwhile}], "projects": [{"name", "stage"}] for regional
## project stages funded meanwhile}. {} when there's no mark.
func away_report(id: String, now := int(Time.get_unix_time_from_system())) -> Dictionary:
	if not away.has(id):
		return {}
	var m: Dictionary = away[id]
	away.erase(id)
	var then_towns: Dictionary = m.get("towns", {})
	var towns := []
	var most := 0
	var ids := cities.keys()
	ids.sort()
	for other in ids:
		if other == id:
			continue
		var g := glance(other)
		var t := {"id": other, "name": cities[other].name, "player": cities[other].player}
		if then_towns.has(other):
			var was: Dictionary = then_towns[other]
			t.ticks = maxi(0, g.tick - int(was.get("tick", g.tick)))
			for k in ["pop", "homes", "shops", "works"]:
				t[k] = g[k] - int(was.get(k, g[k]))
		else:
			t.new = true
			t.ticks = 0
			t.pop = g.pop
		most = maxi(most, int(t.ticks))
		towns.append(t)
	var projects := []
	var then_stages: Dictionary = m.get("stages", {})
	for pid in ledger.projects:
		var p: Dictionary = ledger.projects[pid]
		var done := Ledger.stages_done(p)
		var was := int(then_stages.get(pid, done))
		if done > was:
			projects.append({"name": str(p.name), "stage": str(p.stages[done - 1].name)})
	return {"seconds": maxi(0, now - int(m.get("at", now))), "ticks": most, "towns": towns,
		"projects": projects}


## Works out the metro again (see Ledger.update_metro). Returns whether it
## changed.
func update_metro() -> bool:
	var towns := {}
	for id in cities:
		towns[id] = cities[id].name
	return ledger.update_metro(towns, joins)


## Takes a town's land as sent: a flat list of cells [x0, z0, x1, z1...].
func take_land(id: String, flat: Array) -> void:
	var cells := {}
	for i in range(0, flat.size() - 1, 2):
		cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
	land[id] = cells


## A town's land, worked out from its simulation, as a flat list to send.
func land_of_sim(id: String) -> Array:
	var origin: Vector2 = cities[id].origin
	var flat := []
	for p in cities[id].sim.land_cells():
		var c := Vector2i(((p + origin) / Balance.LAND_CELL).floor())
		flat.append(c.x)
		flat.append(c.y)
	return flat


func land_flat(id: String) -> Array:
	var flat := []
	for c in land.get(id, {}):
		flat.append(c.x)
		flat.append(c.y)
	return flat


## Whether a town may build at these points (its own coordinates): "" if
## they are its land or open land, else whose land they are. A point is
## another town's when that town has built within LAND_CLAIM of it and
## nearer than this town has: the city line, as a rule.
func land_problem(me: String, pts: Array) -> String:
	if not cities.has(me):
		return ""
	var origin: Vector2 = cities[me].origin
	for p in pts:
		var q: Vector2 = p + origin
		var nearest := Balance.LAND_CLAIM
		var who := ""
		for id in land:
			if id != me and cities.has(id):
				var d := _land_distance(land[id], q, nearest)
				if d < nearest:
					nearest = d
					who = id
		if who != "" and _land_distance(land.get(me, {}), q, nearest) > nearest:
			return "That's %s's land." % cities[who].name
	return ""


## Why a town can't start a neighborhood at this spot (its coordinates):
## too near another town's buildings, or not dry, level ground.
func site_problem(me: String, spot: Vector2) -> String:
	if not cities.has(me):
		return ""
	var q: Vector2 = spot + cities[me].origin
	for id in land:
		if id != me and cities.has(id) and _land_distance(land[id], q, Balance.NEIGHBORHOOD_SPACING) < Balance.NEIGHBORHOOD_SPACING:
			return "Too close to %s: a new neighborhood starts at least a mile from other towns." % cities[id].name
	if not Terrain.buildable(q.x, q.y, SITE_RADIUS):
		return "A neighborhood needs dry, level ground."
	return ""


## Distance from a spot to the nearest of these land cells, looking no
## further than `within` (INF past it).
static func _land_distance(cells: Dictionary, q: Vector2, within: float) -> float:
	if cells.is_empty():
		return INF
	var size := Balance.LAND_CELL
	var r := ceili(within / size) + 1
	var at := Vector2i((q / size).floor())
	var best := INF
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var c := at + Vector2i(dx, dz)
			if cells.has(c):
				best = minf(best, q.distance_to((Vector2(c) + Vector2(0.5, 0.5)) * size))
	return best if best <= within + size else INF


## A month of trade between towns: neighbors joined by county road first,
## then the outside world (see Trade). Only the listed towns take part
## (the ones whose players are online; the others are waiting).
func settle_trade(ids: Array) -> void:
	var sims := {}
	for id in ids:
		if cities.has(id):
			_trade_from_copy(id)
			sims[id] = cities[id].sim
	Trade.settle(sims, trade_links())


## Trade needs only a town's offers, wants, links and regional projects:
## a town whose newest copy waits as data takes just those from it, so
## trade never unpacks a whole town (a second for a grown one, on the
## server's loop). The rest of its simulation stays as it was, still
## waiting to be unpacked when something needs it.
func _trade_from_copy(id: String) -> void:
	if not _stale.has(id):
		return
	var d: Dictionary = _data[id]
	var sim: CitySim = cities[id].sim
	sim.trade.from_dict(d.get("trade", {}))
	sim.regional.from_dict(d.get("regional", {}))
	if d.get("links") is Array:
		sim.region_links.clear()
		for n in d.links:
			sim.region_links.append(int(n))


## Who trades with whom, and where: city id -> {neighbor id: link node}.
func trade_links() -> Dictionary:
	var out := {}
	for j in joins:
		if not out.has(j.a):
			out[j.a] = {}
		if not out.has(j.b):
			out[j.b] = {}
		out[j.a][j.b] = _node_at(j.a, j.a_at)
		out[j.b][j.a] = _node_at(j.b, j.b_at)
	return out


func _node_at(id: String, at: Array) -> int:
	if not cities.has(id):
		return -1
	if _stale.has(id) and _data[id].get("roads") is Dictionary:
		return _node_in(_data[id].roads, Vector2(float(at[0]), float(at[1])), 3.0)
	return cities[id].sim.network.find_node_near(Vector3(float(at[0]), 0, float(at[1])), 3.0)


## A city's player color as one viewer sees it: coral for their own city,
## otherwise the neighbor color it was given on joining (kept for good).
func color_of(city_id: String, viewer_city: String) -> Color:
	if not cities.has(city_id):
		return Brand.INK
	return Brand.player_color(cities[city_id].color, city_id == viewer_city)


func add_chat(from: String, text: String) -> Dictionary:
	var line := {"from": from, "text": text.strip_edges().left(300), "at": int(Time.get_unix_time_from_system())}
	chat.append(line)
	while chat.size() > CHAT_KEEP:
		chat.pop_front()
	return line


## The open spot nearest the middle of the region that keeps elbow room
## from every town and stays out of each town's way of growth.
func _free_spot() -> Vector2:
	# The real small towns first (Backdrop.sites), in order: a new town is
	# founded at its original crossroads, the section corner nearest it.
	var taken := PackedVector2Array()
	for id in cities:
		taken.append(cities[id].origin)
	for site in Backdrop.sites():
		var p: Vector2 = site.centre.snapped(Vector2(CountyGrid.SECTION, CountyGrid.SECTION))
		if _clear_of(p, taken) and Terrain.buildable(p.x, p.y, SITE_RADIUS):
			return p
	if cities.is_empty():
		return Vector2.ZERO
	var ids := cities.keys()
	ids.sort()
	var centre := Vector2.ZERO
	var pts := PackedVector2Array()
	var wedges := []  # [origin, growth direction]
	for id in ids:
		var c: Dictionary = cities[id]
		centre += c.origin
		pts.append(c.origin)
		var built := Vector2.ZERO
		var n := 0
		for p: Vector3 in _built_at(id):
			pts.append(c.origin + Vector2(p.x, p.z))
			built += Vector2(p.x, p.z)
			n += 1
		if n > 0 and (built / n).length() > 150.0:
			wedges.append([c.origin, (built / n).normalized()])
		# Its land too: neighborhood sites, and towns not unpacked here.
		for cell in land.get(id, {}):
			pts.append((Vector2(cell) + Vector2(0.5, 0.5)) * Balance.LAND_CELL)
	centre /= ids.size()
	var grid := _grid_of(pts)
	var ring := 1
	while ring < 200:
		var steps := 12 * ring
		for i in steps:
			var a := TAU * i / steps + ring * 0.5
			# On a section corner, so the town's county highway runs along a
			# section line like the county roads around it (CountyGrid).
			var p := (centre + Vector2(cos(a), sin(a)) * ELBOW_ROOM * 0.5 * ring).snapped(
				Vector2(CountyGrid.SECTION, CountyGrid.SECTION))
			if _clear_of_grid(p, grid) and not _in_growth_way(p, wedges) and Terrain.buildable(p.x, p.y, SITE_RADIUS) \
					and Backdrop.distance_to(p) > ELBOW_ROOM * 0.5:
				return p
		ring += 1
	return centre + Vector2(ELBOW_ROOM * 100.0, 0)


## Where a town's buildings stand (its coordinates), from its newest copy:
## a town waiting as data is read from it, not unpacked.
func _built_at(id: String) -> Array:
	var out := []
	if _stale.has(id):
		var d: Dictionary = _data[id]
		var parcels: Dictionary = d.get("parcels", {})
		for key in d.get("buildings", {}):
			var pos = parcels.get(key, {}).get("pos") if parcels.get(key) is Dictionary else null
			if pos is Vector3:
				out.append(pos)
			elif pos is Array and pos.size() == 3:
				out.append(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		return out
	var sim: CitySim = cities[id].sim
	for key in sim.buildings:
		if sim.lots.has(key):
			out.append(sim.lots[key].pos)
	return out


static func _clear_of(p: Vector2, pts: PackedVector2Array) -> bool:
	var room := ELBOW_ROOM * ELBOW_ROOM
	for q in pts:
		if p.distance_squared_to(q) < room:
			return false
	return true


## Points bucketed by ELBOW_ROOM squares, so _clear_of_grid looks at the
## few near a spot, not every building in the region.
static func _grid_of(pts: PackedVector2Array) -> Dictionary:
	var grid := {}
	for q in pts:
		var c := Vector2i((q / ELBOW_ROOM).floor())
		if not grid.has(c):
			grid[c] = PackedVector2Array()
		grid[c].append(q)
	return grid


## The same as _clear_of, on points bucketed by _grid_of.
static func _clear_of_grid(p: Vector2, grid: Dictionary) -> bool:
	var c := Vector2i((p / ELBOW_ROOM).floor())
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell = grid.get(c + Vector2i(dx, dy))
			if cell != null and not _clear_of(p, cell):
				return false
	return true


static func _in_growth_way(p: Vector2, wedges: Array) -> bool:
	for w in wedges:
		if absf(rad_to_deg((p - w[0]).angle_to(w[1]))) < GROWTH_WEDGE:
			return true
	return false


## The ids of up to `count` cities nearest a spot, nearest first.
func _nearest_cities(p: Vector2, count: int) -> Array:
	var ids := cities.keys()
	ids.sort()
	ids.sort_custom(func(a, b): return p.distance_squared_to(cities[a].origin) < p.distance_squared_to(cities[b].origin))
	return ids.slice(0, count)


## The road point of a city nearest a spot (city coordinates), or its centre.
static func _nearest_road_point(sim: CitySim, to: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var ids := sim.network.nodes.keys()
	ids.sort()
	for n in ids:
		var q: Vector3 = sim.network.nodes[n]
		var d := Vector2(q.x, q.z).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = Vector2(q.x, q.z)
	return best


# --- Saving (also what a joining player is sent) ----------------------------

## Everything, to save. With `full_for` set to a town's id, only that town
## is a full copy and the others are postcards (for its player); "" sends
## postcards only.
##
## Without `with_data`, the towns are only named and placed (the server
## sends and saves each town's data on its own).
func to_dict(full_for := "*", with_data := true) -> Dictionary:
	var cs := {}
	for id in cities:
		var c: Dictionary = cities[id]
		cs[id] = {"owner": c.owner, "player": c.player, "name": c.name, "origin": [c.origin.x, c.origin.y],
			"color": c.color, "land": land_flat(id)}
		if with_data:
			cs[id].city = city_data(id) if full_for == "*" or full_for == id else postcard_data(id)
	var d := {"version": 2, "map": MAP, "seed": region_seed, "cities": cs, "chat": chat, "joins": joins,
		"ledger": ledger.to_dict()}
	if not pending.is_empty():
		d.pending = pending
	return d


## With `first` set, only that town is unpacked now (a player's own, so
## they can start playing at once); the others wait as data (load_stale).
func from_dict(d: Dictionary, first := "") -> void:
	region_seed = int(d.get("seed", 1))
	chat = d.get("chat", [])
	ledger = Ledger.new()
	ledger.from_dict(d.get("ledger", {}))
	joins = []
	for j in d.get("joins", []):
		if j.has("a_at"):
			joins.append({"a": str(j.a), "a_at": [float(j.a_at[0]), float(j.a_at[1])],
				"b": str(j.b), "b_at": [float(j.b_at[0]), float(j.b_at[1])]})
	cities.clear()
	land = {}
	_data = {}
	_full = {}
	_stale = {}
	_full_z = {}
	_card_z = {}
	_copy_n = {}
	pending = pending_from(d)
	var cs: Dictionary = d.get("cities", {})
	for id in cs:
		var c: Dictionary = cs[id]
		var sim := new_sim()
		sim.terrain_offset = Vector2(float(c.origin[0]), float(c.origin[1]))
		if first == "" or id == first:
			sim.from_dict(c.city)
			if not c.city.get("postcard", false):
				_full[id] = c.city
		else:
			_data[id] = c.city
			_stale[id] = true
			if not c.city.get("postcard", false):
				_full[id] = c.city
		cities[id] = {"owner": str(c.owner), "player": str(c.get("player", "")), "name": str(c.name),
			"origin": Vector2(float(c.origin[0]), float(c.origin[1])), "color": int(c.color), "sim": sim}
		if _full.has(id):
			_count_copy(id)
		if not _stale.has(id) and not c.city.get("postcard", false):
			_add_pending(id)
		if c.get("land") is Array and not c.land.is_empty():
			take_land(id, c.land)
		elif not _stale.has(id):
			take_land(id, land_of_sim(id))


## The handed roads in a saved or sent region (see pending).
static func pending_from(d: Dictionary) -> Dictionary:
	var out := {}
	var p = d.get("pending", {})
	if p is Dictionary:
		for id in p:
			if p[id] is Array and not p[id].is_empty():
				out[str(id)] = p[id].filter(func(cmd): return cmd is Dictionary)
	return out


## The region with every town in it but the one listed, whose own computer
## has the newer copy (sent to a player whose town is running).
func to_dict_without(skip: String) -> Dictionary:
	var d := to_dict("")
	if d.cities.has(skip):
		d.cities[skip].erase("city")
	return d


## The region with only the listed towns' data (the others just named and
## placed), for players who already have the rest.
func to_dict_with(ids: Array) -> Dictionary:
	var d := to_dict("")
	for id in d.cities:
		if not id in ids:
			d.cities[id].erase("city")
	return d
