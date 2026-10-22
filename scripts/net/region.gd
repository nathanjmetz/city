class_name Region
extends RefCounted
## A shared region: every player's city on one open map, plus the chat.
##
## Each city is its own CitySim with its own budget, placed at an origin on
## the shared map. The server owns the real copy. Every tick it applies the
## commands players sent, then steps every city, and sends players exactly
## that ("tick n, these commands") so their copies stay identical.

## New cities start this far from the nearest city centre, in metres
## (about a mile: close enough to see, far enough to grow).
const NEIGHBOR_GAP := 1600.0
## Chat lines kept and sent to players who join.
const CHAT_KEEP := 100

## city id -> {"owner": player id, "player": player name, "name": city name,
## "origin": Vector2, "color": int, "sim": CitySim}
var cities := {}
var chat := []  # [{"from", "text", "tick"}]
var tick_count := 0
var region_seed := 1


## The city a player owns, or "" if they have none yet.
func city_of(player_id: String) -> String:
	for id in cities:
		if cities[id].owner == player_id:
			return id
	return ""


## Gives a new player their own city in open land next to an existing one.
func add_city(player_id: String, player: String) -> String:
	var id := "c%d" % (cities.size() + 1)
	while cities.has(id):
		id += "x"
	var sim := new_sim()
	sim.city_seed = hash([region_seed, id])
	cities[id] = {"owner": player_id, "player": player, "name": player + "ville", "origin": _free_spot(),
		"color": cities.size() % Brand.PLAYERS.size(), "sim": sim}
	# Every city starts with a free road in from the edge of the map, like a highway exit.
	sim.apply_now({"type": "build_road", "start": [-400, 0], "ctrl": [-250, 0], "end": [-100, 0]})
	sim.apply_now({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	sim.economy.money = Economy.START_MONEY
	return id


## A city simulation set up the way the game plays it, the same on every copy.
static func new_sim() -> CitySim:
	var sim := CitySim.new()
	sim.require_utilities = true
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
		out[id] = hash([s.tick_count, s.economy.money, s.buildings.size(),
			s.network.segments.size(), s.stats.population])
	return out


## The nearest open spot to the existing cities, walking round them in rings.
func _free_spot() -> Vector2:
	if cities.is_empty():
		return Vector2.ZERO
	var centre := Vector2.ZERO
	for id in cities:
		centre += cities[id].origin
	centre /= cities.size()
	var ring := 1
	while true:
		var steps := 6 * ring
		for i in steps:
			var a := TAU * i / steps + ring * 0.5
			var p := centre + Vector2(cos(a), sin(a)) * NEIGHBOR_GAP * ring
			p = p.snapped(Vector2(10, 10))
			var clear := true
			for id in cities:
				if p.distance_to(cities[id].origin) < NEIGHBOR_GAP * 0.95:
					clear = false
					break
			if clear:
				return p
		ring += 1
	return Vector2.ZERO


# --- Saving (also what a joining player is sent) ----------------------------

func to_dict() -> Dictionary:
	var cs := {}
	for id in cities:
		var c: Dictionary = cities[id]
		cs[id] = {"owner": c.owner, "player": c.player, "name": c.name, "origin": [c.origin.x, c.origin.y],
			"color": c.color, "city": c.sim.to_dict()}
	return {"version": 1, "tick": tick_count, "seed": region_seed, "cities": cs, "chat": chat}


func from_dict(d: Dictionary) -> void:
	tick_count = int(d.get("tick", 0))
	region_seed = int(d.get("seed", 1))
	chat = d.get("chat", [])
	cities.clear()
	var cs: Dictionary = d.get("cities", {})
	for id in cs:
		var c: Dictionary = cs[id]
		var sim := new_sim()
		sim.from_dict(c.city)
		cities[id] = {"owner": str(c.owner), "player": str(c.get("player", "")), "name": str(c.name),
			"origin": Vector2(float(c.origin[0]), float(c.origin[1])), "color": int(c.color), "sim": sim}
