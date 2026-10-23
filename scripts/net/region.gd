class_name Region
extends RefCounted
## A shared region: every player's city on one open map, plus the chat.
##
## Each city is its own CitySim with its own budget, placed at an origin on
## the shared map. The server owns the real copy. Every tick it applies the
## commands players sent, then steps every city, and sends players exactly
## that ("tick n, these commands") so their copies stay identical.

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
## The county highway runs this far out of a town toward open country.
const COUNTY_REACH := 2000.0
## A new town is linked by county road to this many of its nearest towns.
const LINK_TOWNS := 2
## Trade settles once a game month (a game day).
const TRADE_EVERY := 24 * CitySim.TICKS_PER_HOUR

## city id -> {"owner": player id, "player": player name, "name": city name,
## "origin": Vector2, "color": int, "sim": CitySim}
var cities := {}
var chat := []  # [{"from", "text", "tick"}]
## Where two towns' county roads meet on the city line, so traffic can pass
## from one to the other: [{"a": city id, "a_node": node, "b": city id, "b_node": node}]
var joins := []
var tick_count := 0
var region_seed := 1
## Service deals offered between towns and waiting on both players' bells
## (Interlocal): id -> {kind, host, served, fee, host_req, served_req,
## host_link, served_link, offset, homes}. The next deal's id, and when an
## offer turned down may come again ("kind:host:served" -> tick).
var pacts := {}
var next_pact := 1
var pact_wait := {}


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
func add_city(player_id: String, player: String) -> String:
	var id := "c%d" % (cities.size() + 1)
	while cities.has(id):
		id += "x"
	var sim := new_sim()
	sim.city_seed = hash([region_seed, id])
	var origin := _free_spot()
	sim.terrain_offset = origin
	var near := _nearest_cities(origin, LINK_TOWNS)
	cities[id] = {"owner": player_id, "player": player, "name": player + "ville", "origin": origin,
		"color": cities.size() % Brand.PLAYERS.size(), "sim": sim}
	if near.is_empty():
		sim.build_county_road(Vector2(-COUNTY_REACH, 0), Vector2(COUNTY_REACH, 0), [0, 1])
	else:
		var away := Vector2.ZERO
		for other in near:
			var o: Dictionary = cities[other]
			var meet: Vector2 = ((origin + o.origin) * 0.5).snapped(Vector2(1, 1))
			away -= (meet - origin).normalized()
			var mine: Array = sim.build_county_road(Vector2.ZERO, meet - origin, [1])
			# Their half starts from their nearest road, so it joins their town.
			var their: CitySim = o.sim
			var to: Vector2 = meet - o.origin
			var from := _nearest_road_point(their, to)
			var theirs: Array = their.build_county_road(from, to, [1])
			joins.append({"a": id, "a_node": mine[1], "b": other, "b_node": theirs[1]})
		if away.length() < 0.1:
			away = (origin - cities[near[0]].origin).orthogonal()
		sim.build_county_road(Vector2.ZERO, away.normalized() * COUNTY_REACH, [1])
	sim.economy.money = Economy.START_MONEY
	return id


## A city simulation set up the way the game plays it, the same on every copy.
static func new_sim() -> CitySim:
	var sim := CitySim.new()
	sim.require_utilities = true
	sim.in_region = true
	return sim


## Applies one player's command to their own city. Players can only change
## the city they own.
func apply(city_id: String, cmd: Dictionary) -> bool:
	if not cities.has(city_id):
		return false
	return cities[city_id].sim.apply_now(cmd)


func tick() -> void:
	tick_count += 1
	var ids := cities.keys()
	ids.sort()
	for id in ids:
		cities[id].sim.tick()
	if tick_count % TRADE_EVERY == 0:
		settle_trade()
		Interlocal.region_step(self)


## A month of trade between every city: neighbors joined by county road
## first, then the outside world (see Trade).
func settle_trade() -> void:
	var sims := {}
	for id in cities:
		sims[id] = cities[id].sim
	Trade.settle(sims, trade_links())


## Who trades with whom, and where: city id -> {neighbor id: link node}.
func trade_links() -> Dictionary:
	var out := {}
	for j in joins:
		if not out.has(j.a):
			out[j.a] = {}
		if not out.has(j.b):
			out[j.b] = {}
		out[j.a][j.b] = j.a_node
		out[j.b][j.a] = j.b_node
	return out


## A city's player color as one viewer sees it: coral for their own city,
## otherwise the neighbor color it was given on joining (kept for good).
func color_of(city_id: String, viewer_city: String) -> Color:
	if not cities.has(city_id):
		return Brand.INK
	return Brand.player_color(cities[city_id].color, city_id == viewer_city)


func add_chat(from: String, text: String) -> Dictionary:
	var line := {"from": from, "text": text.strip_edges().left(300), "tick": tick_count}
	chat.append(line)
	while chat.size() > CHAT_KEEP:
		chat.pop_front()
	return line


## A short fingerprint of each city, so players can check their copy still
## matches the server's.
func checksums() -> Dictionary:
	var out := {}
	for id in cities:
		var s: CitySim = cities[id].sim
		out[id] = hash([s.tick_count, s.economy.money, s.trade.net, s.buildings.size(),
			s.network.segments.size(), s.stats.population, s.traffic.cars.size()])
	return out


## The open spot nearest the middle of the region that keeps elbow room
## from every town and stays out of each town's way of growth.
func _free_spot() -> Vector2:
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
		for key in c.sim.buildings:
			if c.sim.lots.has(key):
				var p: Vector3 = c.sim.lots[key].pos
				pts.append(c.origin + Vector2(p.x, p.z))
				built += Vector2(p.x, p.z)
				n += 1
		if n > 0 and (built / n).length() > 150.0:
			wedges.append([c.origin, (built / n).normalized()])
	centre /= ids.size()
	var ring := 1
	while ring < 200:
		var steps := 12 * ring
		for i in steps:
			var a := TAU * i / steps + ring * 0.5
			var p := (centre + Vector2(cos(a), sin(a)) * ELBOW_ROOM * 0.5 * ring).snapped(Vector2(10, 10))
			if _clear_of(p, pts) and not _in_growth_way(p, wedges) and Terrain.buildable(p.x, p.y, SITE_RADIUS):
				return p
		ring += 1
	return centre + Vector2(ELBOW_ROOM * 100.0, 0)


static func _clear_of(p: Vector2, pts: PackedVector2Array) -> bool:
	var room := ELBOW_ROOM * ELBOW_ROOM
	for q in pts:
		if p.distance_squared_to(q) < room:
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

func to_dict() -> Dictionary:
	var cs := {}
	for id in cities:
		var c: Dictionary = cities[id]
		cs[id] = {"owner": c.owner, "player": c.player, "name": c.name, "origin": [c.origin.x, c.origin.y],
			"color": c.color, "city": c.sim.to_dict()}
	return {"version": 1, "tick": tick_count, "seed": region_seed, "cities": cs, "chat": chat, "joins": joins,
		"pacts": pacts, "next_pact": next_pact, "pact_wait": pact_wait}


func from_dict(d: Dictionary) -> void:
	tick_count = int(d.get("tick", 0))
	region_seed = int(d.get("seed", 1))
	chat = d.get("chat", [])
	joins = []
	for j in d.get("joins", []):
		joins.append({"a": str(j.a), "a_node": int(j.a_node), "b": str(j.b), "b_node": int(j.b_node)})
	load_pacts(d)
	cities.clear()
	var cs: Dictionary = d.get("cities", {})
	for id in cs:
		var c: Dictionary = cs[id]
		var sim := new_sim()
		sim.terrain_offset = Vector2(float(c.origin[0]), float(c.origin[1]))
		sim.from_dict(c.city)
		cities[id] = {"owner": str(c.owner), "player": str(c.get("player", "")), "name": str(c.name),
			"origin": Vector2(float(c.origin[0]), float(c.origin[1])), "color": int(c.color), "sim": sim}


## Service deals still waiting on both bells (also on a resync).
func load_pacts(d: Dictionary) -> void:
	pacts = {}
	for k in d.get("pacts", {}):
		var p: Dictionary = d.pacts[k]
		pacts[int(k)] = {"kind": str(p.kind), "host": str(p.host), "served": str(p.served), "fee": int(p.fee),
			"host_req": int(p.host_req), "served_req": int(p.served_req), "host_link": int(p.host_link),
			"served_link": int(p.served_link), "offset": int(p.offset), "homes": int(p.homes)}
	next_pact = int(d.get("next_pact", 1))
	pact_wait = {}
	for k in d.get("pact_wait", {}):
		pact_wait[str(k)] = int(d.pact_wait[k])
