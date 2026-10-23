class_name TownJump
extends RefCounted
## Quick ways back to a town centre, so nobody gets lost on the open map
## (Brawn, 2026-10-23): the home button in the top bar (or the Home key)
## glides back to the middle of your own town, and the list beside it to
## any neighbor's.
##
## Real reference: Cities: Skylines 2 has no such button and players get lost
## on its big maps; SimCity 4's region view and Google Maps' "your location"
## button are the models. A town's centre is the middle of its Main Street
## (where its addresses count from, Streets.main_at), or where it was
## founded until it has one.

var sim: CitySim
var cam: CityCamera


func _init(s: CitySim, c: CityCamera) -> void:
	sim = s
	cam = c


## Every town you can go to: [{id, name, player, people, at, mine, online}],
## yours first, then the neighbors by name.
func towns() -> Array:
	var out := [{"id": "", "name": "Your town", "player": "", "people": int(sim.stats.population),
		"at": centre_of(sim, Vector3.ZERO), "mine": true, "online": true}]
	var session = Engine.get_main_loop().root.get_node_or_null("/root/Session") if Engine.get_main_loop() else null
	if session == null or not session.online():
		return out
	var c: RegionClient = session.client
	var cities: Dictionary = c.region.cities
	if not cities.has(c.my_city):
		return out
	var o: Vector2 = cities[c.my_city].origin
	out[0].name = str(cities[c.my_city].get("name", "Your town"))
	var others := []
	for id in cities:
		if id == c.my_city:
			continue
		var city: Dictionary = cities[id]
		var p: Vector2 = city.origin - o
		var their = city.get("sim")
		others.append({"id": id, "name": str(city.get("name", "A town")), "player": str(city.get("player", "")),
			"people": int(their.stats.population) if their != null else 0,
			"at": centre_of(their, Vector3(p.x, 0.0, p.y)), "mine": false,
			"online": c.players.any(func(pl): return pl.id == city.get("owner"))})
	others.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return out + others


## The middle of a town (its Main Street, else where it was founded), in
## this world; `origin` is where the town sits.
static func centre_of(town, origin: Vector3) -> Vector3:
	if town == null:
		return origin
	var m: Vector2 = town.streets.main_at
	return origin + Vector3(m.x, 0.0, m.y)


## Glides the camera over to a town's centre.
func go(at: Vector3) -> void:
	cam.following = false
	cam.fly_to(at)


func go_home() -> void:
	go(centre_of(sim, Vector3.ZERO))
