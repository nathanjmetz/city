extends SceneTree
## Run: godot --headless -s tests/test_catch_up.gd
## "While you were away": the region notes where the neighbors stood when a
## player left, their return gets what changed, and their town lives the
## game time the neighbors played (capped at a season), trading with them
## each month, then says so in a few lines.

const PORT := 19620
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_report()
	_test_catch_up()
	await _test_card()
	await _test_server()
	print("ALL PASS" if not _failed else "SOME FAILED")
	quit(1 if _failed else 0)


## Two towns in a region: Ann leaves, Bob plays and grows, Ann's return
## hears about it.
func _test_report() -> void:
	var r := Region.new()
	var ann := r.add_city("p-ann", "Ann")
	var bob := r.add_city("p-bob", "Bob")
	_check(r.away_report(ann).is_empty(), "no mark, nothing to tell")
	r.mark_away(ann, 1000)
	var carl := r.add_city("p-carl", "Carl")
	var sim: CitySim = r.cities[bob].sim
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	for i in 3000:
		sim.tick()
	r.update_city(bob, sim.to_dict(true))
	r.ledger.set_population(bob, sim.stats.population)
	var rep := r.away_report(ann, 1000 + 3600)
	_check(rep.seconds == 3600, "it knows how long Ann was away")
	_check(rep.ticks == 3000, "and how much game time the neighbors played (%d ticks)" % rep.ticks)
	var b: Dictionary = rep.towns.filter(func(t): return t.id == bob)[0]
	_check(b.pop == sim.stats.population and b.pop > 0 and b.homes > 0, "Bob's growth: +%d people, +%d homes" % [b.pop, b.homes])
	var c: Array = rep.towns.filter(func(t): return t.id == carl)
	_check(not c.is_empty() and c[0].get("new", false), "a town founded meanwhile is news")
	_check(r.away_report(ann).is_empty(), "told once")
	# A player who leaves at once after arriving (the mark is saved as JSON
	# by the server: numbers come back as floats).
	r.mark_away(ann, 5000)
	r.away = JSON.parse_string(JSON.stringify(r.away))
	rep = r.away_report(ann, 5000)
	_check(rep.ticks == 0 and CatchUp.ticks_for(rep) == 0, "nobody played: no catch-up")


## A town catches up on a report: the clock moves on by the neighbors'
## time (capped), its homes grow, trade settles with the neighbor each month.
func _test_catch_up() -> void:
	var r := Region.new()
	var ann := r.add_city("p-ann", "Ann")
	var bob := r.add_city("p-bob", "Bob")
	var sim: CitySim = r.cities[ann].sim
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	for i in 600:
		sim.tick()
	sim.trade.offer("lumber", 40.0)
	r.cities[bob].sim.trade.want("lumber", 25.0)
	_check(CatchUp.ticks_for({"ticks": 100}) == 0, "a few game minutes aren't worth it")
	_check(CatchUp.ticks_for({"ticks": 99999}) == CatchUp.MAX_TICKS, "at most a season")
	var rep := {"ticks": 2 * CatchUp.MONTH + 300, "towns": [{"id": bob, "name": "Bobville", "player": "Bob",
		"ticks": 2 * CatchUp.MONTH + 300, "pop": 240, "homes": 18, "shops": 2, "works": 1}], "projects": []}
	var c := CatchUp.new(sim, r, ann, rep)
	var start := sim.tick_count
	var pop0 := int(sim.stats.population)
	var frames := 0
	while not c.done() and frames < 100000:
		c.step(1000.0, 200)
		frames += 1
	_check(sim.tick_count - start == rep.ticks, "the clock moved on by the neighbors' time (%d ticks)" % (sim.tick_count - start))
	_check(sim.simulate_traffic, "cars run again afterwards")
	_check(c.sold_to_neighbors > 0.0, "Bob kept buying Ann's lumber each month ($%d)" % c.sold_to_neighbors)
	_check(int(sim.stats.population) >= pop0, "Ann's town kept growing (%d -> %d)" % [pop0, sim.stats.population])
	var lines := c.lines()
	print("  card: ", lines)
	_check(lines.size() >= 2 and lines.size() <= 4, "the card has 2 to 4 lines")
	_check(lines[0].begins_with("Bobville grew by 240 people and built 18 homes"), "the busiest neighbor comes first")
	_check(lines.any(func(l): return "bought" in l), "and what they bought")
	# The same town and report caught up twice comes out the same.
	var r2 := Region.new()
	var ann2 := r2.add_city("p-ann", "Ann")
	var bob2 := r2.add_city("p-bob", "Bob")
	var sim2: CitySim = r2.cities[ann2].sim
	for cmd in _starter_town(sim2):
		sim2.apply(cmd)
	for i in 600:
		sim2.tick()
	sim2.trade.offer("lumber", 40.0)
	r2.cities[bob2].sim.trade.want("lumber", 25.0)
	var c2 := CatchUp.new(sim2, r2, ann2, rep)
	while not c2.done():
		c2.step(3.0, 7)  # in other slices
	_check(sim2.buildings.size() == sim.buildings.size() and int(sim2.economy.money) == int(sim.economy.money),
		"however it's sliced, it comes out the same (%d/%d buildings, $%d/$%d)" % [
			sim2.buildings.size(), sim.buildings.size(), sim2.economy.money, sim.economy.money])


## The card: it waits a moment, catches up with a progress bar, then says
## what happened and closes with a click.
func _test_card() -> void:
	var r := Region.new()
	var ann := r.add_city("p-ann", "Ann")
	var bob := r.add_city("p-bob", "Bob")
	var sim: CitySim = r.cities[ann].sim
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	var rep := {"ticks": CatchUp.MONTH, "towns": [{"id": bob, "name": "Bobville", "player": "Bob",
		"ticks": CatchUp.MONTH, "pop": 30, "homes": 3, "shops": 0, "works": 0}], "projects": []}
	var card := AwayCard.new()
	card.setup(CatchUp.new(sim, r, ann, rep), null, null, null)
	root.add_child(card)
	await _until(func(): return card.visible)
	_check(card.visible and card._title.text == "Catching up with the neighbors", "the card says it's catching up")
	await _until(func(): return card._phase == "summary", 60.0)
	_check(card._title.text.begins_with("While you were away, your neighbors were at work"), "then says what the neighbors did")
	_check(card._list.get_child_count() >= 1 and card._list.get_child_count() <= 4, "in a few lines (%d)" % card._list.get_child_count())
	card._ok.pressed.emit()
	await _frames(2)
	_check(not is_instance_valid(card), "and closes with a click")


## Over the network: Ann leaves, Bob plays, the server restarts (an
## update), Ann comes back and her welcome says what Bob did.
func _test_server() -> void:
	var data := OS.get_user_data_dir().path_join("test-catch-up.json")
	DirAccess.remove_absolute(data)
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(PORT, "abc123", data) == OK, "server starts")
	var url := "ws://127.0.0.1:%d" % PORT
	var ann := _client()
	ann.join(url, "ABC123", "p-ann", "Ann")
	await _until(func(): return ann.is_joined)
	_check(ann.away.is_empty(), "a first visit has nothing to catch up")
	# The host adds Bob; he gets in with his PIN.
	ann.add_player("Bob")
	await _until(func(): return ann.pins.size() == 2)
	var bob_pin := ""
	for pp in ann.pins:
		if pp.name == "Bob":
			bob_pin = str(pp.pin)
	var bob := _client()
	bob.join(url, "", "p-bob", "", "", false, "", bob_pin)
	await _until(func(): return bob.is_joined)
	ann.leave()
	await _until(func(): return server.region.away.has(ann.my_city))
	_check(server.region.away.has(ann.my_city), "the server notes where everyone stood as Ann left")
	var sim := bob.my_sim()
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	for i in 3000:
		sim.tick()
	bob._full_at = -RegionClient.FULL_EVERY  # the whole town, as every 2 minutes
	bob.send_town(true)
	await _until(func(): return server.region._full.has(bob.my_city) \
		and int(server.region._full[bob.my_city].get("tick", 0)) == sim.tick_count)
	server.save()
	server.stop()
	server.queue_free()
	await _frames(5)
	var again := RegionServer.new()
	root.add_child(again)
	_check(again.start(PORT + 1, "", data) == OK, "server restarts")
	var ann2 := _client()
	ann2.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-ann", "Ann", "", false, ann.token)
	await _until(func(): return ann2.is_joined)
	_check(int(ann2.away.get("ticks", 0)) == sim.tick_count, "Ann's welcome says how long Bob played (%s)" % str(ann2.away.get("ticks")))
	var t: Array = ann2.away.get("towns", []).filter(func(x): return x.id == bob.my_city)
	_check(not t.is_empty() and int(t[0].homes) > 0, "and what he built")
	_check(CatchUp.ticks_for(ann2.away) > 0, "enough for a catch-up")
	ann2.leave()
	bob.leave()
	await _frames(5)
	again.stop()


func _starter_town(sim: CitySim) -> Array:
	var link: Vector3 = sim.network.nodes[sim.region_links[0]]
	var along := Vector2(link.x, link.z).normalized()
	var side := along.orthogonal()
	var out := []
	for k in [[Services.Kind.SUBSTATION, 330], [Services.Kind.WATER_TOWER, 270]]:
		var p: Vector2 = along * k[1] + side * 40
		var site := Services.site_near(sim.network, k[0], Vector3(p.x, 0, p.y))
		out.append({"type": "place_service", "kind": k[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for d in range(100, 380, 10):
		var a: Vector2 = along * d - side * 25
		var b: Vector2 = along * d + side * 25
		out.append({"type": "paint_zone", "center": [a.x, a.y], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		out.append({"type": "paint_zone", "center": [b.x, b.y], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	return out


func _client() -> RegionClient:
	var c := RegionClient.new()
	root.add_child(c)
	return c


func _until(cond: Callable, max_seconds := 10.0) -> void:
	var end := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
