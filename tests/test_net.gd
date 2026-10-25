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
	_test_handed_roads()
	_test_ledger()
	_test_land_and_neighborhoods()

	var data := OS.get_user_data_dir().path_join("test-region.json")
	DirAccess.remove_absolute(data)
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(PORT, "abc123", data) == OK, "server starts")
	server.require_approval = true
	_check(server.invite_code == "ABC123", "invite code is kept, in capitals")
	var url := "ws://127.0.0.1:%d" % PORT

	# The first account is the host's: in at once, with just the code.
	var ann := _client()
	ann.join(url, "abc-123", "p-ann", "Ann")
	await _until(func(): return ann.my_city != "")
	_check(ann.my_city != "" and ann.is_host, "Ann makes the first account, hosts and gets a city")
	_check(not JSON.stringify(server.region.to_dict()).contains(server.accounts.ann.hash), "passwords never go out with the region")
	await _until(func(): return not ann.pins.is_empty())
	_check(ann.pins.size() == 1 and str(ann.pins[0].pin).length() == 6, "the host sees her own PIN (%s)" % str(ann.pins))
	var ann_pin := str(ann.pins[0].pin)
	_check(not JSON.stringify(server.region.to_dict()).contains(ann_pin), "PINs never go out with the region")

	# After that, nobody gets in without a PIN: not a wrong code, not the
	# right code with someone's name.
	var stranger := _client()
	var reason := []
	stranger.failed.connect(func(r): reason.append(r))
	stranger.join(url, "ZZZZZZ", "p-stranger", "Stranger")
	await _until(func(): return not reason.is_empty())
	_check(not reason.is_empty() and "PIN" in reason[0], "a stranger is asked for a PIN (%s)" % str(reason))
	var faker := _client()
	var faker_told := []
	faker.failed.connect(func(r): faker_told.append(r))
	faker.join(url, "ABC123", "p-fake", "Ann")
	await _until(func(): return not faker_told.is_empty())
	_check(faker.my_city == "" and not faker_told.is_empty() and "PIN" in faker_told[0], "the code and the host's name aren't enough")

	# Ann's PIN on another computer is Ann, host and all; the old window stops.
	var sneaky := _client()
	var ann_told := []
	ann.failed.connect(func(r): ann_told.append(r))
	sneaky.join(url, "", "p-sneak", "", "", false, "", ann_pin)
	await _until(func(): return sneaky.my_city != "" and not ann_told.is_empty())
	_check(sneaky.my_city == ann.my_city and sneaky.is_host, "the host's PIN on a new computer is the host, with her town")
	_check(not ann_told.is_empty() and "another computer" in ann_told[0] and not ann.reconnecting,
		"the old window is told and stops, so the two don't fight over the town")
	sneaky.leave()
	ann.join(url, "ABC123", "p-ann", "Ann", "", false, ann.token)
	await _until(func(): return ann.my_city != "" and ann.is_joined)
	_check(ann.is_joined and ann.is_host, "and playing on the first computer again brings it back")
	# The host adds Bob and gets a PIN to send him.
	ann.add_player("Bob")
	await _until(func(): return ann.pins.size() == 2)
	var bob_pin := ""
	for pp in ann.pins:
		if pp.name == "Bob":
			bob_pin = str(pp.pin)
	_check(bob_pin.length() == 6 and bob_pin != ann_pin, "the host adds Bob and gets his PIN")
	var guess := _client()
	var guess_told := []
	guess.failed.connect(func(r): guess_told.append(r))
	guess.join(url, "", "p-guess", "", "", false, "", "000000" if bob_pin != "000000" else "111111")
	await _until(func(): return not guess_told.is_empty())
	_check(not guess_told.is_empty() and "isn't right" in guess_told[0], "a wrong PIN is turned away")
	# Bob types only his PIN: no code, no name.
	var bob := _client()
	bob.join(url, "", "p-bob", "", "", false, "", bob_pin.left(3) + " " + bob_pin.substr(3))
	await _until(func(): return bob.my_city != "" and ann.region.cities.size() == 2)
	_check(bob.my_city != "" and bob.my_city != ann.my_city and bob.player_name == "Bob", "Bob is in with just his PIN, as Bob")

	# A PIN the host takes away lets nobody in.
	ann.add_player("Eve")
	await _until(func(): return ann.pins.size() == 3)
	var eve_pin := ""
	for pp in ann.pins:
		if pp.name == "Eve":
			eve_pin = str(pp.pin)
	ann.remove_pin("Eve")
	await _until(func(): return ann.pins.any(func(pp): return pp.name == "Eve" and pp.pin == ""))
	var eve := _client()
	var eve_told := []
	eve.failed.connect(func(r): eve_told.append(r))
	eve.join(url, "", "p-eve", "", "", false, "", eve_pin)
	await _until(func(): return not eve_told.is_empty())
	_check(not eve_told.is_empty() and eve.my_city == "", "the host can take a PIN away")
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
	ann.send_town(true)
	await _until(func(): return bob.region.stale_ids().has(ann.my_city) \
		and bob.region.city_data(ann.my_city).get("buildings", {}).size() == sim.buildings.size())
	_check(server.region.stale_ids().has(ann.my_city), "the server keeps Ann's copy as data until it needs it")
	await _until(func(): return int(bob.region.ledger.metro.get("population", 0)) == sim.stats.population)
	_check(sim.stats.population > 0 and server.region.ledger.metro.population == sim.stats.population \
		and server.region.ledger.metro.towns.size() == 2, "her people count toward the metro, on everyone's ledger")
	# Copies are unpacked one town at a time, a few seconds apart; now, here.
	bob.region.load_stale()
	server.region.load_stale()
	_check(bob.region.cities[ann.my_city].sim.network.segments.size() > roads_before, "Bob sees Ann's new road")
	_check(bob.region.cities[ann.my_city].sim.buildings.size() == sim.buildings.size(), "and her homes")
	_check(server.region.cities[ann.my_city].sim.buildings.size() == sim.buildings.size(), "the server keeps a copy")

	# Bob's copy only ever updates Bob's own town.
	var ann_roads: int = server.region.cities[ann.my_city].sim.network.segments.size()
	bob.my_sim().apply({"type": "clear"})
	bob.send_town(true)
	await _frames(20)
	_check(server.region.cities[ann.my_city].sim.network.segments.size() == ann_roads, "Bob can't change Ann's town")

	# Trade between the two computers, settled by the server.
	sim.trade.offer("power", 50.0)
	bob.my_sim().trade.want("power", 30.0)
	ann.send_town(true)
	bob.send_town(true)
	await _frames(20)
	var bob_money := bob.my_sim().economy.money
	server.settle_trade()
	await _until(func(): return bob.my_sim().trade.got("power") > 0.0)
	_check(bob.my_sim().trade.got("power") == 30.0 and bob.my_sim().economy.money < bob_money, "Bob buys Ann's power and pays on his computer")
	await _until(func(): return sim.trade.sold("power") > 0.0)
	_check(sim.trade.sold("power") == 50.0, "Ann is paid on hers")

	# A message far bigger than the connection's buffer (a region of big
	# towns) goes in parts and arrives whole.
	var big_text := "x".repeat(RegionServer.BUFFER_BYTES + 3_000_000)
	var big_heard := []
	bob.chat_received.connect(func(l): if str(l.text).length() > 1000: big_heard.append(l))
	var bob_peer := -1
	for peer in server._players:
		if server._players[peer].city == bob.my_city:
			bob_peer = peer
	server._send(bob_peer, {"t": "chat", "line": {"from": "", "text": big_text, "at": 0}})
	_check(server._link.waiting_bytes(bob_peer) > 0, "a message bigger than the buffer waits its turn instead of failing")
	await _until(func(): return not big_heard.is_empty(), 30.0)
	_check(not big_heard.is_empty() and str(big_heard[0].text) == big_text,
		"and arrives whole, %d MB in parts" % (big_text.length() / 1_000_000))

	# A newer copy replaces an older one still waiting, and goes behind what
	# was queued after it (never ahead of an older full copy).
	var link := NetLink.new(WebSocketMultiplayerPeer.new())
	link.send(5, "card1".to_utf8_buffer(), "card")
	link.send(5, "full1".to_utf8_buffer(), "full")
	link.send(5, "card2".to_utf8_buffer(), "card")
	var order: Array = link._out[5].map(func(e): return e.packets[0].get_string_from_utf8())
	_check(order == ["full1", "card2"], "a newer copy takes the older one's place at the back of the queue (%s)" % [order])
	var parts := NetLink.split("z".repeat(NetLink.PART_BYTES * 2 + 5).to_utf8_buffer())
	_check(parts.size() == 3 and parts[0][1] == NetLink.MORE | NetLink.FIRST and parts[1][1] == NetLink.MORE and parts[2][1] == 0,
		"a big message's first part says it's first, so one cut short is never added onto")

	# Before signing in, nobody can send the server big messages.
	var raw := WebSocketMultiplayerPeer.new()
	RegionServer.use_big_buffers(raw)
	raw.create_client(url)
	await _until(func():
		raw.poll()
		return raw.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	for pkt in NetLink.split("y".repeat(3 * NetLink.PART_BYTES).to_utf8_buffer()).slice(0, 2):
		raw.put_packet(pkt)
	for i in 20:
		raw.poll()
		await process_frame
	_check(server._link._in.is_empty(), "parts from a connection that hasn't signed in are dropped")
	raw.close()

	# The save goes on another core, and writes just what saving at once does.
	# (Compared with the region as it was when the save started: the players'
	# games keep sending copies meanwhile.)
	await _until(func(): return server._saving.is_empty(), 30.0)
	var expected := _old_save(server)
	server._start_save()
	await _until(func(): return server._saving.is_empty(), 30.0)
	_check(_same_save(expected, server.data_path), "a save made on another core is the same file as before")
	expected = _old_save(server)
	server._start_save()
	await _until(func(): return server._saving.is_empty(), 30.0)
	_check(_same_save(expected, server.data_path) and not server._town_text.is_empty(), "and again from the towns' kept text")

	# Chat reaches everyone, with the sender's name.
	var heard := []
	bob.chat_received.connect(func(line): heard.append(line))
	ann.send_chat("Hi neighbor!")
	await _until(func(): return heard.any(func(l): return l.text == "Hi neighbor!"))
	var line = heard.filter(func(l): return l.text == "Hi neighbor!")
	_check(not line.is_empty() and line[0].from == "Ann", "Bob gets Ann's chat message")
	_check(bob.players.size() == 2, "both players listed online")
	var bob_cash := bob.my_sim().economy.money
	server.region.ledger.projects.airport.unlocked = true
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
	bob2.join("ws://127.0.0.1:%d" % (PORT + 1), "", "p-bobs-laptop", "", "", false, "", bob_pin)
	await _until(func(): return bob2.my_city != "")
	_check(bob2.my_city != "" and bob2.my_city != ann_city, "Bob comes back on another computer with his PIN (kept over a restart)")
	await _until(func(): return not ann2.pins.is_empty())
	ann2.add_player("Kid")
	await _until(func(): return ann2.pins.any(func(pp): return pp.name == "Kid"))
	var kid_pin := ""
	for pp in ann2.pins:
		if pp.name == "Kid":
			kid_pin = str(pp.pin)
	var kid := _client()
	kid.join("ws://127.0.0.1:%d" % (PORT + 1), "", "p-kid", "", "", false, "", kid_pin)
	await _until(func(): return kid.my_city != "")
	_check(kid.my_city != "" and again.region.cities[kid.my_city].player == "Kid", "a player the host added plays with just the PIN")
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
	third.region.load_stale()
	_check(third.region.cities[kid_city].sim.network.segments.size() > segs, "and the road built while away reaches the server")
	# A device that has played here gets in by its sign-in even with an old code.
	var kid3 := _client()
	kid3.join("ws://127.0.0.1:%d" % (PORT + 1), "OLD999", "p-kid", "Sammy", "", false, kid2.token)
	await _until(func(): return kid3.my_city != "")
	_check(kid3.my_city == kid_city, "a returning device gets in by its sign-in even with an old invite code")
	await _frames(10)
	third.stop()
	# A first try that doesn't get through (the region still starting, a slow
	# link) is tried again before the player hears about it.
	var late := _client()
	var late_told := []
	late.failed.connect(func(r): late_told.append(r))
	late.join("ws://127.0.0.1:%d" % (PORT + 2), "ABC123", "p-kid", "Sammy", "", false, kid2.token)
	await _frames(30)
	var fourth := RegionServer.new()
	root.add_child(fourth)
	_check(fourth.start(PORT + 2, "", data) == OK, "the region starts after the first try")
	await _until(func(): return late.my_city != "", 20.0)
	_check(late.my_city != "" and late_told.is_empty(), "a join that didn't get through tries again by itself (%s)" % str(late_told))
	fourth.stop()
	# A build on a new map: the towns start fresh, everyone keeps their PIN.
	var saved = JSON.parse_string(FileAccess.get_file_as_string(data))
	saved["map"] = "some old map"
	var f := FileAccess.open(data, FileAccess.WRITE)
	f.store_string(JSON.stringify(saved))
	f.close()
	var fifth := RegionServer.new()
	root.add_child(fifth)
	_check(fifth.start(PORT + 2, "", data) == OK, "the region starts on a new map")
	_check(fifth.region.cities.is_empty(), "a new map starts the region fresh")
	var kid4 := _client()
	kid4.join("ws://127.0.0.1:%d" % (PORT + 2), "", "p-kid", "", "", false, "", kid_pin)
	await _until(func(): return kid4.my_city != "")
	_check(kid4.my_city != "" and fifth.region.cities.size() == 1, "players get in with the same PIN and found a fresh town")
	# Removing a player takes their town off the map, so no ghost label stays.
	var kid4_told := []
	kid4.failed.connect(func(r): kid4_told.append(r))
	fifth.remove_pin(fifth.region.cities[kid4.my_city].player)
	await _until(func(): return not kid4_told.is_empty())
	_check(fifth.region.cities.is_empty() and not kid4_told.is_empty(), "removing a player takes their town off the map and lets them know")
	fifth.stop()
	# The host plays under another name too: that account gets the Players list.
	var sixth := RegionServer.new()
	root.add_child(sixth)
	_check(sixth.start(PORT + 2, "", data, "Nobody, Bob") == OK, "the region starts with two host names")
	_check(sixth.accounts["bob"].host, "an account under any of the host's names is a host")
	sixth.stop()
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
	_check(c.cities.c1.sim.buildings.is_empty() and c.city_data("c1").buildings.size() == ann.buildings.size(),
		"a new copy waits as data, unpacked only when needed")
	c.load_stale()
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
	# A town right in the way: no start where the two come nearest, so it's
	# found from where the third town's own lines stopped.
	# Two towns with a third just off the line between them: nearer the
	# middle than either, so it blocks there, but further up the two are
	# neighbors again.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var mid := PackedVector2Array()
	for x in range(-60, 61, 20):
		for y in range(-60, 61, 20):
			left.append(Vector2(x - 1000, y))
			right.append(Vector2(x + 1000, y))
			mid.append(Vector2(x, y - 600))
	var sl := CityLines.PointSet.new(left)
	var sr := CityLines.PointSet.new(right)
	var sm := CityLines.PointSet.new(mid)
	var t := CityLines.Tracer.new(sl, sr, [sm])
	while not t.step():
		pass
	_check(t.blocked and t.lines.is_empty(), "a town in the way blocks the start where two towns come nearest")
	var stops := []
	for pair in [[sl, sm, sr], [sr, sm, sl]]:
		var u := CityLines.Tracer.new(pair[0], pair[1], [pair[2]])
		while not u.step():
			pass
		for st in u.stops:
			if st[0] == pair[2]:
				stops.append(st[1])
	var seeded := CityLines.Tracer.new(sl, sr, [sm], stops)
	while not seeded.step():
		pass
	_check(not stops.is_empty() and seeded.lines.size() == 1, "and the line round it starts where three towns meet (%d spots)" % stops.size())
	# Lines are traced again only when a town's edge moves: building inside
	# a town leaves its edge's number as it was.
	var grid := PackedVector2Array()
	for x in range(0, 641, 20):
		for y in range(0, 641, 20):
			grid.append(Vector2(x, y))
	var edge := CityLines.PointSet.new(grid).edge_sig()
	var inside := grid.duplicate()
	inside.append(Vector2(321, 317))
	var outside := grid.duplicate()
	outside.append(Vector2(700, 300))
	var shuffled := grid.duplicate()
	shuffled.reverse()
	_check(CityLines.PointSet.new(inside).edge_sig() == edge and CityLines.PointSet.new(shuffled).edge_sig() == edge
		and CityLines.PointSet.new(outside).edge_sig() != edge, "a town's edge counts as moved only when it grows out, not in")
	# Towns joined by county road: the road out of town doesn't count, so
	# the line runs between the towns, not where their roads meet.
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	for id in ["c1", "c2"]:
		for cmd in _starter_town(r.cities[id].sim):
			r.cities[id].sim.apply_now(cmd)
		for i in 1500:
			r.cities[id].sim.tick()
	var joined := CityLines.trace(CityLines.PointSet.new(CityLines.city_points(r.cities.c1)),
		CityLines.PointSet.new(CityLines.city_points(r.cities.c2)), [])
	var gap: float = r.cities.c1.origin.distance_to(r.cities.c2.origin)
	var mid_ok := false
	if joined.size() == 1:
		var centre: Vector2 = joined[0][joined[0].size() / 2]
		mid_ok = absf(centre.distance_to(r.cities.c1.origin) - centre.distance_to(r.cities.c2.origin)) < gap * 0.25
	_check(r.cities.c1.sim.buildings.size() > 0 and joined.size() == 1 and mid_ok,
		"towns joined by county road get a city line between them (%d)" % joined.size())


## A new town's road into a neighbor's town is handed over, not built on the
## server, and everyone who unpacks that neighbor builds it.
func _test_handed_roads() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	var ann: CitySim = r.cities.c1.sim
	for cmd in _starter_town(ann):
		ann.apply_now(cmd)
	for i in 500:
		ann.tick()
	# Ann's newest copy waits as data, as on the server.
	r.update_city("c1", JSON.parse_string(JSON.stringify(ann.to_dict(), "", false, true)))
	var segs := ann.network.segments.size()
	r.add_city("p2", "Bob", true)
	_check(r.stale_ids().has("c1") and r.pending.has("c1") and r.cities.c1.sim.network.segments.size() == segs,
		"a new neighbor's road into a waiting town is handed over, the town not unpacked")
	_check(r.handed.has("c1") and r.joins.size() == 1, "and it's still sent to her computer and joined")
	var copy := Region.new()
	copy.from_dict(RegionServer.unpack(RegionServer.pack(r.to_dict())))
	copy.load_stale()
	var at: Array = copy.joins[0].b_at if copy.joins[0].b == "c1" else copy.joins[0].a_at
	_check(copy._node_at("c1", at) != -1 and copy.cities.c1.sim.network.segments.size() > segs,
		"her full copy, unpacked (she's back), gets the road (%d roads, was %d)" % [copy.cities.c1.sim.network.segments.size(), segs])
	var seen := Region.new()
	seen.from_dict(RegionServer.unpack(RegionServer.pack(r.to_dict(""))))
	_check(seen.cities.c1.sim.network.segments.size() == segs and seen.pending.has("c1"),
		"a neighbor's postcard of her town is never planned afresh for it")
	# Her own computer builds it; once her copy has it, it isn't handed again.
	for cmd in r.handed.c1:
		ann.apply_now(cmd)
	r.update_city("c1", JSON.parse_string(JSON.stringify(ann.to_dict(), "", false, true)))
	_check(not r.pending.has("c1"), "her copy with the road ends the hand-over")
	_check(r.money_of("c1") == ann.economy.money, "a waiting town's money comes from its copy")


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
	_check(l.pledge("c1", "i69", "money", 1000.0) == 0.0, "a project waits until the metro is big enough")
	_test_metro(l)
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


## Whose land is whose, and a hemmed-in town starting a new neighborhood
## out on open land (neighborhoods-risks.md).
func _test_land_and_neighborhoods() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	var ann: CitySim = r.cities.c1.sim
	ann.land_check = func(pts): return r.land_problem("c1", pts)
	ann.site_check = func(spot): return r.site_problem("c1", spot)
	var bob_at: Vector2 = r.cities.c2.origin - r.cities.c1.origin  # Bob's centre, in Ann's coordinates
	var toward := bob_at.normalized()
	_check(r.land.has("c1") and r.land.has("c2"), "each new town has land from the start")
	# A road into the middle of Bob's town is Bob's land; one at home is fine.
	var into := [Vector3(bob_at.x - toward.x * 150.0, 0, bob_at.y - toward.y * 150.0),
		Vector3(bob_at.x - toward.x * 100.0, 0, bob_at.y - toward.y * 100.0), Vector3(bob_at.x, 0, bob_at.y)]
	_check(ann.land_problem([into]) == "That's %s's land." % r.cities.c2.name, "a road into a neighbor's town is refused (%s)" % ann.land_problem([into]))
	var home := [Vector3(0, 0, 300), Vector3(50, 0, 300), Vector3(100, 0, 300)]
	_check(ann.land_problem([home]) == "", "a road at home is fine")
	# Roads claim nothing: Bob's county road ends halfway, yet the open land
	# beside it past his half-mile is anyone's.
	var mid := bob_at * 0.5
	var open_land := [Vector3(mid.x, 0, mid.y), Vector3(mid.x + 50, 0, mid.y), Vector3(mid.x + 100, 0, mid.y)]
	_check(ann.land_problem([open_land]) == "", "open land between towns is anyone's, roads or not")
	# Bob builds up next to the halfway point: now that land is his.
	var near_mid := Vector2i(((r.cities.c1.origin + mid + toward * 300.0) / Balance.LAND_CELL).floor())
	var flat := r.land_flat("c2")
	flat.append_array([near_mid.x, near_mid.y])
	r.take_land("c2", flat)
	var past := mid + toward * 250.0
	_check(ann.land_problem([[Vector3(past.x, 0, past.y), Vector3(past.x + 10, 0, past.y), Vector3(past.x + 20, 0, past.y)]]) != "",
		"land nearer a neighbor's houses is theirs")

	# Neighborhoods: earned, priced, linked by county road, use it or lose it.
	ann.stats.population = 50
	_check(ann.neighborhood_problem(-bob_at) != "", "a village has no neighborhood to start yet")
	ann.stats.population = 600
	_check(Neighborhoods.slots_for(600) == 1 and Neighborhoods.slots_for(150_000) == Balance.NEIGHBORHOOD_MAX,
		"one neighborhood per town stage, up to the cap")
	_check(ann.neighborhood_problem(bob_at - toward * 900.0) != "", "not right next to another town")
	var spot := Vector2.ZERO
	for i in 24:
		var a := TAU * i / 24.0
		var p := -toward.rotated(a * 0.5 * (1 if i % 2 == 0 else -1)) * 2600.0
		if ann.neighborhood_problem(p) == "":
			spot = p
			break
	_check(spot != Vector2.ZERO, "open land a mile and more from everyone takes a neighborhood")
	var money := ann.economy.money
	var roads := ann.network.segments.size()
	var fee := ann.neighborhoods.fee()
	_check(ann.apply_now({"type": "found_neighborhood", "pos": [spot.x, spot.y]}), "Ann starts a neighborhood")
	_check(ann.neighborhoods.sites.size() == 1 and ann.network.segments.size() > roads, "with a county road out to it")
	_check(is_equal_approx(money - ann.economy.money, fee) and ann.neighborhoods.fee() == fee * 2,
		"it costs its fee, and the next costs double")
	_check(not ann.apply_now({"type": "found_neighborhood", "pos": [-spot.x, -spot.y]}), "one per stage")
	var cell := Vector2i((spot / Balance.LAND_CELL).floor())
	_check(Array(ann.land_cells()).any(func(c): return Vector2i((c / Balance.LAND_CELL).floor()) == cell),
		"the site counts as the town's land")
	_check(ann.neighborhoods.sites[0].name.ends_with("End") or ann.neighborhoods.sites[0].name.ends_with("Side"),
		"named for where it lies (%s)" % ann.neighborhoods.sites[0].name)
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(ann.to_dict(), "", false, true)))
	_check(copy.neighborhoods.sites.size() == 1 and copy.neighborhoods.founded == 1, "neighborhoods save and load")
	ann.tick_count += Balance.NEIGHBORHOOD_USE_DAYS * CitySim.TICKS_PER_HOUR * 24 + 1
	_check(ann.neighborhoods.check(ann).size() == 1 and ann.neighborhoods.sites.is_empty(),
		"an empty site is let go after its time")
	_check(ann.neighborhoods.slots_free(600) == 1 and ann.neighborhoods.fee() == fee * 2,
		"the slot comes back, the fee doesn't go down")
	var placed := r.to_dict()
	_check(placed.cities.c2.land.size() == r.land_flat("c2").size(), "land is saved with the region")


## Grow the metro: towns joined by road count together, ranked on the real
## ladder, and the metro opens the regional projects as it grows.
func _test_metro(l: Ledger) -> void:
	var towns := {"c1": "Marion", "c2": "Gas City", "c3": "Fairmount", "c4": "Faraway"}
	var joins := [{"a": "c2", "b": "c1"}, {"a": "c3", "b": "c1"}]
	l.set_population("c1", 30_000)
	l.set_population("c2", 12_000)
	l.set_population("c3", 3_000)
	l.set_population("c4", 40_000)
	_check(l.update_metro(towns, joins), "the metro is worked out")
	_check(l.metro.population == 45_000 and l.metro.towns.size() == 3,
		"only towns joined by road count (%s)" % str(l.metro))
	_check(l.metro.name == "Marion-Gas City", "named for the largest town and its principal towns (%s)" % l.metro.name)
	_check(l.metro.kind == "micropolitan", "a micropolitan area")
	var next: Array = l.metro.next
	_check(not next.is_empty() and int(next[1]) > 45_000 and Balance.METRO_LADDER.all(
		func(a): return int(a[1]) <= 45_000 or int(a[1]) >= int(next[1])), "the next real metro to pass is the nearest bigger one")
	_check(l.is_unlocked("power") and not l.is_unlocked("i69"), "micropolitan opens the power co-op, not I-69 yet")
	_check(not l.update_metro(towns, joins), "nothing new, nothing to send")
	l.set_population("c3", 31_000)
	l.update_metro(towns, joins)
	_check(l.metro.name == "Fairmount-Marion-Gas City" and l.metro.kind == "metropolitan",
		"towns overtaking each other rename the metro (%s)" % l.metro.name)
	_check(l.is_unlocked("i69"), "metropolitan opens I-69")
	l.set_population("c3", 0)
	l.update_metro(towns, joins)
	_check(l.is_unlocked("i69"), "an opened project stays open")
	_check(l.metro_line().begins_with("Marion-Gas City micropolitan area, 42,000 people. Next: "),
		"one line for the regional panel (%s)" % l.metro_line())
	var copy := Ledger.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())))
	_check(copy.metro_line() == l.metro_line() and copy.is_unlocked("i69") and not copy.is_unlocked("airport"),
		"the metro saves and loads")


## The region as the server used to save it (all at once, as JSON), as text
## with its keys sorted.
func _old_save(server: RegionServer) -> String:
	var old := server.region.to_dict()
	old["code"] = server.invite_code
	old["accounts"] = server.accounts
	old["away"] = server.region.away
	return JSON.stringify(JSON.parse_string(JSON.stringify(old, "", false, true)), "", true, true)


## Whether the save file at `path` is that region.
func _same_save(expected: String, path: String) -> bool:
	var b = JSON.parse_string(FileAccess.get_file_as_string(path))
	return b is Dictionary and JSON.stringify(b, "", true, true) == expected


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
