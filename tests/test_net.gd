extends SceneTree
## Run: godot --headless -s tests/test_net.gd
## A real region server and two players on this computer: joining, invite
## codes, building in step, chat and the server's save.

const PORT := 19480
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_region_in_step()
	_test_crossroads()
	_test_trade()
	_test_elbow_room()
	_test_city_lines()

	var data := OS.get_user_data_dir().path_join("test-region.json")
	DirAccess.remove_absolute(data)
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(PORT, "abc123", data) == OK, "server starts")
	_check(server.invite_code == "ABC123", "invite code is kept, in capitals")
	var url := "ws://127.0.0.1:%d" % PORT

	# A wrong code is turned away with a reason.
	var stranger := _client()
	var reason := []
	stranger.failed.connect(func(r): reason.append(r))
	stranger.join(url, "ZZZZZZ", "p-stranger", "Stranger")
	await _until(func(): return not reason.is_empty())
	_check(not reason.is_empty() and "code" in reason[0], "wrong invite code turned away (%s)" % str(reason))

	var ann := _client()
	ann.join(url, "abc-123", "p-ann", "Ann")
	await _until(func(): return ann.my_city != "")
	_check(ann.my_city != "", "Ann joins and gets a city")
	var bob := _client()
	bob.join(url, "ABC123", "p-bob", "Bob")
	await _until(func(): return bob.my_city != "" and ann.region.cities.size() == 2)
	_check(bob.my_city != "" and bob.my_city != ann.my_city, "Bob gets his own city")
	var gap: float = ann.region.cities[ann.my_city].origin.distance_to(bob.region.cities[bob.my_city].origin)
	_check(gap >= Region.ELBOW_ROOM, "Bob starts 3 miles from Ann's town, with room to grow (%d m)" % gap)

	# Ann builds through the server; both copies get it in the same tick.
	var sim := ann.my_sim()
	sim.send_command = ann.send_command
	var roads_before := sim.network.segments.size()
	sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [50, 80], "end": [60, 100]})
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	await _until(func(): return bob.region.cities[ann.my_city].sim.network.segments.size() > roads_before)
	_check(bob.region.cities[ann.my_city].sim.network.segments.size() > roads_before, "Bob sees Ann's new road")
	_check(sim.network.segments.size() > roads_before, "Ann's road comes back to her from the server")

	# Bob can't build in Ann's city: commands only go to your own.
	var ann_roads: int = server.region.cities[ann.my_city].sim.network.segments.size()
	bob.send_command({"type": "remove_road", "seg": server.region.cities[ann.my_city].sim.network.segments.keys()[0]})
	await _frames(20)
	_check(server.region.cities[ann.my_city].sim.network.segments.size() == ann_roads, "Bob can't bulldoze Ann's roads")

	# Chat reaches everyone, with the sender's name.
	var heard := []
	bob.chat_received.connect(func(line): heard.append(line))
	ann.send_chat("Hi neighbor!")
	await _until(func(): return heard.any(func(l): return l.text == "Hi neighbor!"))
	var line = heard.filter(func(l): return l.text == "Hi neighbor!")
	_check(not line.is_empty() and line[0].from == "Ann", "Bob gets Ann's chat message")
	_check(bob.players.size() == 2, "both players listed online")

	# Let the cities grow a while: everyone's copy stays identical.
	await _until(func(): return server.region.cities[ann.my_city].sim.buildings.size() > 3, 60.0)
	await _frames(10)
	var t: int = server.region.tick_count
	await _until(func(): return ann.region.tick_count == t and bob.region.tick_count == t)
	_check(ann.region.checksums() == server.region.checksums(), "Ann's copy matches the server")
	_check(bob.region.checksums() == server.region.checksums(), "Bob's copy matches the server")
	_check(server.region.cities[ann.my_city].sim.buildings.size() > 0, "homes grew in Ann's city")

	# The region is saved, and Ann gets the same city back when she returns.
	var ann_city: String = ann.my_city
	ann.leave()
	await _frames(30)
	server.stop()
	var again := RegionServer.new()
	root.add_child(again)
	_check(again.start(PORT + 1, "", data) == OK, "server restarts from its save")
	_check(again.invite_code == "ABC123", "invite code survives a restart")
	_check(again.region.cities.size() == 2, "both cities saved")
	var ann2 := _client()
	ann2.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-ann", "Ann")
	await _until(func(): return ann2.my_city != "")
	_check(ann2.my_city == ann_city, "Ann gets her own city back")
	_check(ann2.region.chat.any(func(l): return l.text == "Hi neighbor!"), "chat history kept")
	again.stop()
	DirAccess.remove_absolute(data)

	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


## Two copies of a region fed the same events stay identical, and a copy
## made from a snapshot keeps in step too.
func _test_region_in_step() -> void:
	var a := Region.new()
	var b := Region.new()
	for r in [a, b]:
		r.add_city("p1", "Ann")
		r.add_city("p2", "Bob")
	for r in [a, b]:
		for cmd in _starter_town(r.cities.c1.sim):
			r.apply("c1", cmd)
		for cmd in _starter_town(r.cities.c2.sim):
			r.apply("c2", cmd)
		for i in 300:
			r.tick()
	_check(a.checksums() == b.checksums(), "two copies of a region stay in step")
	var c := Region.new()
	c.from_dict(JSON.parse_string(JSON.stringify(a.to_dict(), "", false, true)))
	for i in 300:
		a.tick()
		c.tick()
	_check(a.checksums() == c.checksums(), "a copy sent to a joining player keeps in step")
	_check(a.cities.c1.sim.buildings.size() > 0, "cities grow in a region")
	_check(a.cities.c1.origin != a.cities.c2.origin, "cities get their own spots")


## New towns start on a county road that meets each neighbor's halfway.
func _test_crossroads() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	var ann: CitySim = r.cities.c1.sim
	_check(ann.region_links.size() == 2, "the first town sits on a county highway, both ends out to the region")
	_check(ann.economy.money == Economy.START_MONEY, "the county road is free")
	r.add_city("p2", "Bob")
	r.add_city("p3", "Cy")
	var bob: CitySim = r.cities.c2.sim
	_check(bob.economy.money == Economy.START_MONEY and ann.economy.money == Economy.START_MONEY, "nobody pays for the joining roads")
	_check(r.joins.size() == 1 + 2, "Bob joins Ann; Cy joins both (%d joins)" % r.joins.size())
	var met := true
	for j in r.joins:
		var a: Dictionary = r.cities[j.a]
		var b: Dictionary = r.cities[j.b]
		var pa: Vector3 = a.sim.network.nodes[j.a_node]
		var pb: Vector3 = b.sim.network.nodes[j.b_node]
		if (a.origin + Vector2(pa.x, pa.z)).distance_to(b.origin + Vector2(pb.x, pb.z)) > 1.0:
			met = false
		if not j.a_node in a.sim.region_links or not j.b_node in b.sim.region_links:
			met = false
	_check(met, "each pair of county roads meets at one spot on the city line")
	var seg: int = bob.network.segments_at(r.joins[0].a_node)[0]
	_check(not bob.apply_now({"type": "remove_road", "seg": seg}), "a county road can't be bulldozed")
	var copy := Region.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true)))
	_check(copy.joins == r.joins, "the joins are saved")


## A new town keeps elbow room and stays out of the way a town is growing.
func _test_elbow_room() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	var ann: CitySim = r.cities.c1.sim
	for cmd in _starter_town(ann):
		ann.apply_now(cmd)
	for i in 2000:
		ann.tick()
	var grow := Vector2.ZERO
	var n := 0
	for key in ann.buildings:
		if ann.lots.has(key):
			grow += Vector2(ann.lots[key].pos.x, ann.lots[key].pos.z)
			n += 1
	r.add_city("p2", "Bob")
	var bob: Vector2 = r.cities.c2.origin
	var nearest := INF
	for key in ann.buildings:
		if ann.lots.has(key):
			nearest = minf(nearest, bob.distance_to(Vector2(ann.lots[key].pos.x, ann.lots[key].pos.z)))
	_check(n > 0 and nearest >= Region.ELBOW_ROOM, "Bob starts 3 miles from Ann's nearest building (%d m)" % nearest)
	_check(absf(rad_to_deg(bob.angle_to(grow))) >= Region.GROWTH_WEDGE, "and not where Ann is growing")


## Neighbors trade first, at a fair price; the outside fills the gaps for more.
func _test_trade() -> void:
	var r := Region.new()
	for p in [["p1", "Ann"], ["p2", "Bob"], ["p3", "Cy"]]:
		r.add_city(p[0], p[1])
	var ann: CitySim = r.cities.c1.sim
	var bob: CitySim = r.cities.c2.sim
	var cy: CitySim = r.cities.c3.sim
	var price := Trade.base_price("power")
	bob.trade.offer("power", 50.0)
	ann.trade.want("power", 30.0)
	cy.trade.want("power", 40.0)
	ann.trade.offer("water", 10.0)
	var trucks := []
	bob.trade.deal.connect(func(d): trucks.append(d))
	var money := [ann.economy.money, bob.economy.money, cy.economy.money]
	r.settle_trade()
	_check(ann.trade.got("power") == 30.0 and bob.trade.sold("power") == 50.0, "Ann buys her power from Bob")
	_check(cy.trade.got("power") == 40.0, "Cy gets the rest of Bob's power and the outside covers what's left")
	_check(bob.economy.money - money[1] == roundi(50 * price), "Bob is paid for all he sold")
	_check(money[2] - cy.economy.money == roundi(20 * price) + roundi(20 * price * Balance.TRADE_IMPORT_MARKUP),
		"buying from outside costs Cy more than buying from a neighbor")
	_check(ann.trade.sold("water") == 10.0 and ann.economy.money - money[0] == roundi(10 * Trade.base_price("water") * Balance.TRADE_EXPORT_SHARE) - roundi(30 * price),
		"what no neighbor wants sells to the outside for less")
	var to_ann = trucks.filter(func(d): return d.buyer == "c1")
	_check(not to_ann.is_empty() and to_ann[0].link in bob.region_links, "each deal says which county road the trucks take")
	var copy := Region.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true)))
	copy.settle_trade()
	r.settle_trade()
	_check(copy.checksums() == r.checksums(), "trade comes out the same on every copy")
	# A solo city trades with the outside world once a game month.
	var solo := CitySim.new()
	solo.trade.want("power", 10.0)
	var before := solo.economy.money
	for i in 24 * CitySim.TICKS_PER_HOUR:
		solo.tick()
	_check(solo.trade.got("power") == 10.0 and solo.trade.net == -roundi(10 * price * Balance.TRADE_IMPORT_MARKUP),
		"a solo city buys from the outside (%s)" % str(solo.trade.bought))
	_check(before - solo.economy.money >= roundi(10 * price * Balance.TRADE_IMPORT_MARKUP) - 1000000, "and pays for it")


## The city line runs halfway between two towns, and stops where a third is nearer.
func _test_city_lines() -> void:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for x in range(0, 200, 20):
		for y in range(-300, 301, 20):
			a.append(Vector2(x, y))
			b.append(Vector2(x + 800, y))
	var lines := CityLines.trace(CityLines.PointSet.new(a), CityLines.PointSet.new(b), [])
	_check(lines.size() == 1 and lines[0].size() > 20, "a city line between two towns (%d points)" % (lines[0].size() if lines.size() else 0))
	var halfway := true
	for p in lines[0]:
		if absf(p.x - 490.0) > 3.0:
			halfway = false
	_check(halfway, "the line is halfway between the closest buildings")
	var c := PackedVector2Array()
	for x in range(400, 600, 20):
		for y in range(400, 600, 20):
			c.append(Vector2(x, y))
	var cut := CityLines.trace(CityLines.PointSet.new(a), CityLines.PointSet.new(b), [CityLines.PointSet.new(c)])
	var max_y := -INF
	for p in cut[0]:
		max_y = maxf(max_y, p.y)
	_check(max_y < 400.0, "the line stops where a third town is nearer (reaches y=%d)" % max_y)


## Power, water and zones along a city's starter road (its county road out
## to the first region link): commands to grow a town.
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
