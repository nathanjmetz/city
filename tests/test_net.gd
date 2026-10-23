extends SceneTree
## Run: godot --headless -s tests/test_net.gd
## A real region server and two players on this computer: joining, invite
## codes, accounts, each town running on its own computer and reaching the
## neighbors, trade, chat and the server's save.

const PORT := 19480
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_region_copies()
	_test_crossroads()
	_test_trade()
	_test_elbow_room()
	_test_city_lines()
	_test_ledger()

	var data := OS.get_user_data_dir().path_join("test-region.json")
	DirAccess.remove_absolute(data)
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(PORT, "abc123", data) == OK, "server starts")
	server.require_approval = true
	_check(server.invite_code == "ABC123", "invite code is kept, in capitals")
	var url := "ws://127.0.0.1:%d" % PORT

	# A wrong code is turned away with a reason.
	var stranger := _client()
	var reason := []
	stranger.failed.connect(func(r): reason.append(r))
	stranger.join(url, "ZZZZZZ", "p-stranger", "Stranger")
	await _until(func(): return not reason.is_empty())
	_check(not reason.is_empty() and "code" in reason[0], "wrong invite code turned away (%s)" % str(reason))

	# The first account is the host's: in at once.
	var ann := _client()
	ann.join(url, "abc-123", "p-ann", "Ann")
	await _until(func(): return ann.my_city != "")
	_check(ann.my_city != "" and ann.is_host, "Ann makes the first account, hosts and gets a city")
	_check(not JSON.stringify(server.region.to_dict()).contains(server.accounts.ann.hash), "passwords never go out with the region")
	# Everyone else waits for the host to let them in.
	var bob := _client()
	var told := []
	bob.waiting.connect(func(m): told.append(m))
	bob.join(url, "ABC123", "p-bob", "Bob")
	await _until(func(): return not told.is_empty() and ann.requests == ["Bob"])
	_check(not told.is_empty() and bob.my_city == "", "Bob signs up and waits for the host")
	_check(ann.requests == ["Bob"], "the host sees Bob waiting (%s)" % str(ann.requests))
	var sneaky := _client()
	var sneaky_told := []
	sneaky.failed.connect(func(r): sneaky_told.append(r))
	sneaky.join(url, "ABC123", "p-sneak", "Ann")
	await _until(func(): return not sneaky_told.is_empty())
	_check(not sneaky_told.is_empty() and "host" in sneaky_told[0], "nobody else can play as the host")
	var eve := _client()
	var eve_told := []
	eve.failed.connect(func(r): eve_told.append(r))
	eve.join(url, "ABC123", "p-eve", "Eve")
	await _until(func(): return ann.requests.size() == 2)
	ann.approve("Eve", false)
	await _until(func(): return not eve_told.is_empty())
	_check(not eve_told.is_empty() and eve.my_city == "", "the host can say no")
	ann.approve("Bob", true)
	await _until(func(): return bob.my_city != "" and ann.region.cities.size() == 2)
	_check(bob.my_city != "" and bob.my_city != ann.my_city, "Bob gets his own city")
	var gap: float = ann.region.cities[ann.my_city].origin.distance_to(bob.region.cities[bob.my_city].origin)
	_check(gap >= Region.ELBOW_ROOM, "Bob starts 3 miles from Ann's town, with room to grow (%d m)" % gap)

	# Bob's county road reached Ann's town on her own computer.
	await _until(func(): return ann.my_sim().region_links.size() >= 3)
	_check(ann.my_sim().region_links.size() >= 3, "Ann's computer builds her half of the road to Bob (%d links)" % ann.my_sim().region_links.size())

	# Ann's town runs on her computer; Bob sees it once a copy is sent.
	var sim := ann.my_sim()
	var roads_before: int = bob.region.cities[ann.my_city].sim.network.segments.size()
	sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [50, 80], "end": [60, 100]})
	for cmd in _starter_town(sim):
		sim.apply(cmd)
	for i in 3000:
		sim.tick()
	_check(sim.buildings.size() > 0, "homes grow in Ann's town on her own computer")
	ann.send_town()
	await _until(func(): return bob.region.cities[ann.my_city].sim.network.segments.size() > roads_before)
	_check(bob.region.cities[ann.my_city].sim.network.segments.size() > roads_before, "Bob sees Ann's new road")
	_check(bob.region.cities[ann.my_city].sim.buildings.size() == sim.buildings.size(), "and her homes")
	_check(server.region.cities[ann.my_city].sim.buildings.size() == sim.buildings.size(), "the server keeps a copy")

	# Bob's copy only ever updates Bob's own town.
	var ann_roads: int = server.region.cities[ann.my_city].sim.network.segments.size()
	bob.my_sim().apply({"type": "clear"})
	bob.send_town()
	await _frames(20)
	_check(server.region.cities[ann.my_city].sim.network.segments.size() == ann_roads, "Bob can't change Ann's town")

	# Trade between the two computers, settled by the server.
	sim.trade.offer("power", 50.0)
	bob.my_sim().trade.want("power", 30.0)
	ann.send_town()
	bob.send_town()
	await _frames(20)
	var bob_money := bob.my_sim().economy.money
	server.settle_trade()
	await _until(func(): return bob.my_sim().trade.got("power") > 0.0)
	_check(bob.my_sim().trade.got("power") == 30.0 and bob.my_sim().economy.money < bob_money, "Bob buys Ann's power and pays on his computer")
	await _until(func(): return sim.trade.sold("power") > 0.0)
	_check(sim.trade.sold("power") == 50.0, "Ann is paid on hers")

	# Chat reaches everyone, with the sender's name.
	var heard := []
	bob.chat_received.connect(func(line): heard.append(line))
	ann.send_chat("Hi neighbor!")
	await _until(func(): return heard.any(func(l): return l.text == "Hi neighbor!"))
	var line = heard.filter(func(l): return l.text == "Hi neighbor!")
	_check(not line.is_empty() and line[0].from == "Ann", "Bob gets Ann's chat message")
	_check(bob.players.size() == 2, "both players listed online")
	var bob_cash := bob.my_sim().economy.money
	bob.pledge("airport", 250_000.0)
	await _until(func(): return ann.region.ledger.projects.airport.stages[0].pledged.get("money", 0.0) > 0.0)
	_check(is_equal_approx(server.region.ledger.projects.airport.stages[0].pledged.money, 250_000.0), "Bob pledges to the airport; the server books it")
	_check(is_equal_approx(bob_cash - bob.my_sim().economy.money, 250_000.0), "and Bob's town pays it")
	_check(ann.region.ledger.share("airport", bob.my_city) == 1.0, "Ann sees Bob's share")
	ann.offer_service(bob.my_city, "garbage", 3000.0, 20.0)
	await _until(func(): return not bob.region.ledger.agreements.is_empty())
	var aid: String = bob.region.ledger.agreements.keys()[0]
	bob.answer_offer(aid, true)
	await _until(func(): return ann.region.ledger.agreements[aid].status == "active")
	_check(ann.region.ledger.agreements_of(ann.my_city).size() == 1, "Bob signs Ann's trash pickup offer")

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
	ann2.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-other-device", "Ann", "", false, ann.token)
	await _until(func(): return ann2.my_city != "")
	_check(ann2.my_city == ann_city, "Ann logs back in with her saved token and gets her own city back")
	_check(ann2.my_sim().buildings.size() == sim.buildings.size(), "with everything she built (sent as she left)")
	var bob2 := _client()
	bob2.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-bobs-laptop", "Bob")
	await _until(func(): return bob2.my_city != "")
	_check(bob2.my_city != "" and bob2.my_city != ann_city, "Bob comes back on another computer with just his name and the code")
	# By default the invite code is the only key: no name, no password, no wait.
	var kid := _client()
	kid.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-kid", "")
	await _until(func(): return kid.my_city != "")
	_check(kid.my_city != "" and again.region.cities[kid.my_city].player.begins_with("Neighbor"), "a device with just the code plays at once, as a Neighbor")
	var kid_city: String = kid.my_city
	var kid_token: String = kid.token
	kid.leave()
	await _frames(20)
	var kid2 := _client()
	kid2.join("ws://127.0.0.1:%d" % (PORT + 1), "ABC123", "p-kid", "Sammy", "", false, kid_token)
	await _until(func(): return kid2.my_city != "")
	_check(kid2.my_city == kid_city and again.region.cities[kid_city].player == "Sammy", "back by its sign-in, with the name picked in Profile")
	_check(ann2.region.chat.any(func(l): return l.text == "Hi neighbor!"), "chat history kept")
	# The host's computer restarts (an update, say): Sammy's town keeps
	# running, the game reconnects by itself and the server gets the latest.
	var back := []
	kid2.reconnected.connect(func(): back.append(true))
	again.stop()
	again.queue_free()
	await _frames(10)
	var kid_sim := kid2.my_sim()
	var segs := kid_sim.network.segments.size()
	kid_sim.apply_now({"type": "build_road", "start": [0, 0], "ctrl": [0, 60], "end": [0, 120]})
	_check(kid2.reconnecting, "a dropped connection keeps the town running and tries again")
	var third := RegionServer.new()
	root.add_child(third)
	_check(third.start(PORT + 1, "", data) == OK, "the host's server comes back")
	await _until(func(): return not back.is_empty(), 20.0)
	await _frames(20)
	_check(not back.is_empty() and kid2.is_joined, "the game reconnects by itself")
	_check(third.region.cities[kid_city].sim.network.segments.size() > segs, "and the road built while away reaches the server")
	third.stop()
	DirAccess.remove_absolute(data)

	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


## A region copied for the wire comes back the same, and a town's newer
## copy replaces the old one.
func _test_region_copies() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	var c := Region.new()
	c.from_dict(RegionServer.unpack(RegionServer.pack(r.to_dict())))
	_check(c.cities.size() == 2 and c.cities.c2.origin == r.cities.c2.origin, "a packed region comes back the same")
	var ann: CitySim = r.cities.c1.sim
	for cmd in _starter_town(ann):
		ann.apply_now(cmd)
	for i in 2000:
		ann.tick()
	c.update_city("c1", JSON.parse_string(JSON.stringify(ann.to_dict(), "", false, true)))
	_check(c.cities.c1.sim.buildings.size() == ann.buildings.size() and ann.buildings.size() > 0, "a town's new copy replaces the old")
	_check(not r.to_dict_without("c1").cities.c1.has("city"), "a player isn't sent their own town while it runs")


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
		var na: int = r._node_at(j.a, j.a_at)
		var nb: int = r._node_at(j.b, j.b_at)
		if na == -1 or nb == -1:
			met = false
			continue
		var pa: Vector3 = a.sim.network.nodes[na]
		var pb: Vector3 = b.sim.network.nodes[nb]
		if (a.origin + Vector2(pa.x, pa.z)).distance_to(b.origin + Vector2(pb.x, pb.z)) > 1.0:
			met = false
		if not na in a.sim.region_links or not nb in b.sim.region_links:
			met = false
	_check(met, "each pair of county roads meets at one spot on the city line")
	_check(r.handed.has("c1") and r.handed.has("c2"), "Cy's roads into Ann's and Bob's towns are handed to their computers")
	var seg: int = bob.network.segments_at(r._node_at("c2", r.joins[0].a_at))[0]
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
	r.settle_trade(["c1", "c2", "c3"])
	_check(ann.trade.got("power") == 30.0 and bob.trade.sold("power") == 50.0, "Ann buys her power from Bob")
	_check(cy.trade.got("power") == 40.0, "Cy gets the rest of Bob's power and the outside covers what's left")
	_check(bob.economy.money - money[1] == roundi(50 * price), "Bob is paid for all he sold")
	_check(money[2] - cy.economy.money == roundi(20 * price) + roundi(20 * price * Balance.TRADE_IMPORT_MARKUP),
		"buying from outside costs Cy more than buying from a neighbor")
	_check(ann.trade.sold("water") == 10.0 and ann.economy.money - money[0] == roundi(10 * Trade.base_price("water") * Balance.TRADE_EXPORT_SHARE) - roundi(30 * price),
		"what no neighbor wants sells to the outside for less")
	var to_ann = trucks.filter(func(d): return d.buyer == "c1")
	_check(not to_ann.is_empty() and to_ann[0].link in bob.region_links, "each deal says which county road the trucks take")
	# A deal reaches the player's own computer, which moves the money.
	var home := Region.new_sim()
	var home_before := home.economy.money
	home.trade.receive(home, cy.trade.last_deals)
	_check(home.trade.got("power") == 40.0 and home_before - home.economy.money == -cy.trade.net, "a town's computer takes its deals")
	# Only towns that are running trade.
	bob.trade.offer("power", 50.0)
	r.settle_trade(["c1"])
	_check(bob.trade.sold("power") == 50.0 and ann.trade.got("power") == 30.0 and ann.trade.last_deals.all(func(d): return d.seller == "outside" or d.buyer == "outside"),
		"a town whose player is away doesn't trade")
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


func _test_ledger() -> void:
	var l := Ledger.new()
	_check(l.projects.has("i69") and l.projects.has("airport"), "regional projects are seeded at real sites")
	var p: Dictionary = l.projects.i69
	var goal: float = p.stages[0].goal.money
	_check(l.pledge("c1", "i69", "money", goal * 0.25) == goal * 0.25, "a town chips in")
	_check(l.pledge("c2", "i69", "money", goal * 10.0) == goal * 0.75, "nobody pays more than the stage still needs")
	_check(p.stages[0].status == "funded" and p.stages[1].status == "open", "a funded stage opens the next one")
	_check(is_equal_approx(l.share("i69", "c1"), 0.25) and is_equal_approx(l.share("i69", "c2"), 0.75), "shares follow what each town put in")
	_check(l.pledge("c1", "nope", "money", 10.0) == 0.0, "no pledges to a project that isn't there")
	var id := l.offer("c1", "c2", "garbage", 5000.0, 40.0)
	_check(not l.answer(id, "c1", true), "only the town an offer was made to can take it")
	_check(l.answer(id, "c2", true) and l.agreements[id].status == "active", "the neighbor signs")
	_check(l.book_month("c1") == 5000.0 and l.book_month("c2") == -5000.0, "each side books its own half of a month")
	var copy := Ledger.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())))
	_check(copy.projects.i69.stages[1].status == "open" and is_equal_approx(copy.share("i69", "c2"), 0.75) \
		and copy.agreements[id].status == "active", "the ledger saves and loads")
	_check(l.end(id, "c2") and l.book_month("c1") == 0.0, "either side can end it")


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
