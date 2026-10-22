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
	_check(gap >= Region.NEIGHBOR_GAP * 0.9, "Bob starts next to Ann, not on top of her (%d m)" % gap)

	# Ann builds through the server; both copies get it in the same tick.
	var sim := ann.my_sim()
	sim.send_command = ann.send_command
	var roads_before := sim.network.segments.size()
	sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [80, 120], "end": [120, 180]})
	for x in range(-80, 0, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
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
	await _until(func(): return server.region.tick_count >= 250, 40.0)
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
		for x in range(-80, 0, 10):
			r.apply("c1", {"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			r.apply("c2", {"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
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
