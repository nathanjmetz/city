extends SceneTree
## Run: godot --headless -s tests/test_telemetry.gd
## Play telemetry: hunts (time and clicks to find things), stuck moments,
## feature use, the trip to the region server and back, and the fix list.

const PORT := 19490
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_hunts()
	_test_stuck()
	_test_insights()
	_test_replays()
	_test_scroll()
	_test_perf_window()
	await _test_server()
	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


func _test_hunts() -> void:
	var t := TelemetryTracker.new()
	# Look around, open Roads, pick Highway, then draw on the map.
	t.motion(0.2, false, 0.5)
	t.motion(0.3, true, 0.7)   # a drag: not looking around
	t.click(Vector2(0.1, 0.9), "Roads", true, false, 1.0)
	t.motion(0.1, false, 2.0)
	t.click(Vector2(0.2, 0.8), "Highway", true, false, 3.0)
	t.click(Vector2(0.5, 0.5), "", false, false, 5.0)
	var hunts := t.events.filter(func(e): return e.k == "hunt")
	_check(hunts.size() == 1, "a hunt ends when the player uses what they found")
	var h: Dictionary = hunts[0]
	_check(h.target == "Highway" and h.path == ["Roads", "Highway"], "the hunt's target and path (%s)" % str(h.path))
	_check(is_equal_approx(h.s, 2.5) and h.clicks == 2 and is_equal_approx(h.travel, 0.3),
		"time from first look to the find, clicks and travel without drags (%s)" % str(h))
	_check(h.end == "used", "it ended by being used")
	# Open a menu, poke around, back out.
	t.click(Vector2(0.3, 0.9), "Services", true, false, 10.0)
	t.click(Vector2(0.4, 0.8), "Police", true, false, 11.0)
	t.key("Escape", false, 12.0)
	_check(t.events.back().k == "hunt" and t.events.back().end == "escape", "backing out ends a hunt with escape")
	# Wandering off ends one too.
	t.click(Vector2(0.3, 0.9), "Zones", true, false, 20.0)
	t.tick(60.0)
	_check(t.events.back().end == "idle", "a hunt left hanging ends as idle")
	# Feature use and clicks on things that aren't there for it.
	t.click(Vector2(0.6, 0.9), "Bulldoze", true, true, 70.0)
	t.click(Vector2(0.7, 0.1), "TopBar", false, false, 75.0)
	t.key("R", false, 76.0)
	t.command("build_road", true, 77.0)
	var out := t.take(80.0)
	var use: Dictionary = out.back()
	_check(use.k == "use" and use.buttons.Roads == 1 and use.disabled.Bulldoze == 1 and use.dead.TopBar == 1,
		"feature use, disabled clicks and dead clicks are counted (%s)" % str(use))
	_check(use.keys.R == 1 and use.cmds.build_road == [1, 0], "shortcuts and game commands are counted")
	_check(t.take(81.0).is_empty(), "take() hands everything over once")


func _test_stuck() -> void:
	var t := TelemetryTracker.new()
	t.click(Vector2(0.2, 0.9), "Water", true, false, 1.0)
	for i in 4:
		t.click(Vector2(0.5 + i * 0.002, 0.5), "", false, false, 2.0 + i * 0.2)
	var rage := t.events.filter(func(e): return e.k == "rage")
	_check(rage.size() == 1 and rage[0].ctx == "Water", "four fast clicks in one spot are a rage click, with context")
	for i in 3:
		t.key("Escape", false, 10.0 + i * 0.3)
	_check(t.events.any(func(e): return e.k == "esc_spam"), "Escape spam is caught")
	for i in 3:
		t.key("Ctrl+Z", true, 20.0 + i)
	_check(t.events.any(func(e): return e.k == "undo_streak"), "an undo streak is caught")
	for i in 3:
		t.command("place_service", false, 30.0 + i)
	_check(t.events.any(func(e): return e.k == "refused_streak" and e.cmd == "place_service"),
		"the game saying no three times running is caught")


func _test_replays() -> void:
	var t := TelemetryTracker.new()
	t.click(Vector2(0.3, 0.95), "Roads", true, false, 1.0)
	t.click(Vector2(0.3, 0.9), "Grid", true, false, 2.0)
	t.hint("Click the first corner.  Blocks 394 x 269 ft", 2.1)
	t.hint("Click the first corner.  Blocks 400 x 270 ft", 2.2)   # same hint, other numbers
	t.click(Vector2(0.5, 0.5), "", false, false, 3.0, Vector2(120, -40))
	t.release(Vector2(0.6, 0.55), 3.5, Vector2(300, 20))
	t.command("build_grid_shape", true, 4.0, "block=120")
	t.command("remove_road", true, 10.0)
	t.command("build_grid_shape", true, 20.0)
	t.command("remove_road", true, 25.0)
	var redo := t.events.filter(func(e): return e.k == "redo_loop")
	_check(redo.size() == 1 and redo[0].cmd == "build_grid_shape", "building and tearing down twice is a redo loop")
	_check(redo[0].has("replay") and redo[0].replay.size() >= 6, "a flagged moment carries what led up to it")
	var kinds: Array = redo[0].replay.map(func(a): return a[1])
	_check(kinds.count("h") == 1 and kinds.has("d") and kinds.has("x"), "replays hold hints once, drags and commands (%s)" % str(kinds))
	var drag: Array = redo[0].replay.filter(func(a): return a[1] == "d")[0]
	_check(drag.slice(2) == [120.0, -40.0, 300.0, 20.0], "drags are kept in town meters")
	# Pick a tool, back out, three times.
	for i in 3:
		t.click(Vector2(0.4, 0.95), "Zoning", true, false, 40.0 + i * 5)
		t.click(Vector2(0.5, 0.5), "", false, false, 41.0 + i * 5)
		t.key("Escape", false, 42.0 + i * 5)
	_check(t.events.any(func(e): return e.k == "cancel_loop" and e.ctx == "Zoning"), "picking a tool and backing out three times is caught")
	# Clicking and clicking with nothing to show for it.
	t.click(Vector2(0.4, 0.95), "Water", true, false, 80.0)
	for i in TelemetryTracker.NO_PROGRESS_CLICKS:
		t.click(Vector2(0.1 + i * 0.05, 0.5), "", false, false, 81.0 + i)
	_check(t.events.any(func(e): return e.k == "no_progress" and e.ctx == "Water"), "lots of clicks and nothing built is caught")
	var out := t.take(120.0)
	var acts: Array = out.filter(func(e): return e.k == "actions")
	_check(acts.size() == 1 and acts[0].a.size() > 20, "every action goes out for full replays")
	var r := Insights.analyze([{"from": "Ann", "session": "a1", "build": "b", "events": out}])
	var f: Array = r.fixes.filter(func(x): return x.title.begins_with("Players build"))
	_check(not f.is_empty() and f[0].has("replay"), "the fix list carries the replay")
	var md := Insights.to_markdown(r)
	_check(md.contains("What Ann did") and md.contains("build_grid_shape done (block=120)") and md.contains("dragged 120, -40 to 300, 20"),
		"the report shows the moment step by step")


func _test_scroll() -> void:
	var t := TelemetryTracker.new()
	# Three bursts of Magic Mouse panning; the camera never moves.
	for burst in 3:
		for i in 4:
			t.scroll("pan", 2.0, 300.0, 10.0 * burst + i * 0.05)
		t.tick(10.0 * burst + 1.0, 300.0)
	var dead := t.events.filter(func(e): return e.k == "scroll_dead")
	_check(dead.size() == 1 and dead[0].kind == "pan", "scrolling that never zooms is caught")
	var s: Array = t.actions.filter(func(a): return a[1] == "s")
	_check(s.size() == 3 and s[0][3] == 4, "each burst is one action (%s)" % str(s))
	_check(Insights.action_text(s[0]).contains("didn't move"), "replays say the camera didn't move")
	# A wheel that zooms is fine.
	var ok := TelemetryTracker.new()
	for burst in 3:
		ok.scroll("wheel_up", 1.0, 300.0, 10.0 * burst)
		ok.scroll("wheel_up", 1.0, 290.0, 10.0 * burst + 0.1)
		ok.tick(10.0 * burst + 1.0, 250.0)
	_check(not ok.events.any(func(e): return e.k == "scroll_dead"), "a wheel that zooms isn't flagged")
	# Icon cards are named by their caption.
	var card := Button.new()
	var cap := Label.new()
	cap.text = "Water tower"
	card.add_child(cap)
	_check(load("res://scripts/telemetry/telemetry.gd").label_of(card) == "Water tower", "a card without text is named by its caption")
	card.free()


func _test_insights() -> void:
	var batches := []
	for who in ["Ann", "Bob", "Cy"]:
		var events := [
			{"k": "hunt", "target": "Water tower", "path": ["Services", "Utilities", "Water tower"], "s": 14.0,
				"clicks": 6, "travel": 3.0, "end": "used"},
			{"k": "hunt", "target": "Roads", "path": ["Roads"], "s": 1.0, "clicks": 1, "travel": 0.2, "end": "used"},
			{"k": "load", "what": "Opening your town", "s": 25.0},
			{"k": "load", "what": "Connecting to the region", "s": 8.0, "steps": {"Connecting to the region": 6.0, "Drawing your town": 2.0},
				"net": {"connected": 3.0, "welcome": 5.0, "unpack": 0.5, "tries": 2}},
			{"k": "perf", "fps": 22.0, "worst_ms": 300, "hitches": 3, "scene": "main", "pop": 900,
				"tick_ms": 40.0, "tick_max_ms": 90.0, "top_sim": {"sim.traffic": 14.0, "sim.lots": 6.0}},
			{"k": "boot", "page_ms": 70000, "download_ms": 65000, "start_ms": 3000, "bytes": 49 * 1048576},
		]
		if who == "Ann":
			events.append({"k": "perf", "fps": 50.0, "worst_ms": 40, "hitches": 0, "scene": "main",
				"free_mb": 180, "vram_mb": 2900})
			events.append({"k": "crashed", "t": 80.0, "replay": [[62.4, "x", "build_road", true, "road=0"]]})
			events.append({"k": "stall", "ms": 3364000, "scene": "menu", "ctx": "", "stages": {}})
			events.append({"k": "stall", "ms": 4350, "scene": "main", "ctx": "Grid", "stages": {"frame.roads": 4200.0}})
		if who != "Cy":
			events.append({"k": "error", "sig": "x:1 boom", "file": "res://scripts/traffic/traffic_sim.gd", "line": 1,
				"msg": "Invalid access to key 'lane'", "type": "script", "trace": "", "ctx": "Roads"})
		batches.append({"from": who, "session": who + "1", "build": "abc1234", "events": events})
	batches.append({"from": "Dee", "session": "d1", "build": "abc1234",
		"events": [{"k": "join_fail", "reason": "That invite code doesn't match this region.", "s": 1.0}]})
	var r := Insights.analyze(batches)
	var titles: Array = r.fixes.map(func(f): return f.title)
	_check(titles[0].begins_with("Crashes"), "a crash ranks first (%s)" % titles[0])
	_check(r.fixes[1].kind == "multiplayer", "a failed join ranks next (%s)" % titles[1])
	_check(titles.any(func(x): return "Invalid access" in x), "script errors become fixes")
	var err: Dictionary = r.fixes.filter(func(f): return "Invalid access" in f.title)[0]
	_check(err.owner == "Traffic simulation" and err.players == 2, "errors go to the thread that owns the file")
	_check(titles.has("Hard to find: Water tower") and not titles.has("Hard to find: Roads"),
		"slow finds become fixes, quick ones don't")
	_check(titles.any(func(x): return x.begins_with("Slow loading screen")), "slow loads become fixes")
	var join: Array = r.fixes.filter(func(f): return f.title.begins_with("Slow loading screen \"Connecting"))
	_check(not join.is_empty() and "link open 3.0 s" in join[0].detail and "3 of them needed a retry" in join[0].detail \
		and "Connecting to the region 6.0 s" in join[0].detail, "slow joins split into link, welcome, unpack and drawing (%s)" % (join[0].detail if join else "none"))
	_check(titles.any(func(x): return x.begins_with("Low frame rate")), "low frame rate becomes a fix")
	_check(titles.has("Machine nearly out of memory: 180 MB free"), "low free memory becomes a fix")
	var crash: Array = r.fixes.filter(func(f): return f.title.begins_with("Crashes: 1"))
	_check(not crash.is_empty() and crash[0].has("replay"), "a session that never closed is a fix with its last actions")
	var stall: Array = r.fixes.filter(func(f): return f.title.begins_with("Freezes: 1 frames"))
	_check(not stall.is_empty() and "frame.roads" in stall[0].detail, "freezes become a fix naming the stage")
	_check(titles.any(func(x): return x.begins_with("The download takes")) \
		and not titles.any(func(x): return x.begins_with("The engine takes")), "a slow line is told apart from a slow start")
	var tick: Array = r.fixes.filter(func(f): return f.title.begins_with("Sim ticks"))
	_check(not tick.is_empty() and "sim.traffic" in tick[0].detail, "slow ticks name the costliest system")
	_check(r.summary.players == 4 and r.summary.find_seconds_by_build.has("abc1234"), "summary by player and build")
	var md := Insights.to_markdown(r)
	_check(md.contains("## Fix first") and md.contains("Water tower"), "the report reads as a fix list")


func _test_perf_window() -> void:
	Perf.record("sim.traffic", 10.0)
	Perf.record("sim.traffic", 20.0)
	Perf.record("sim.tick", 30.0)
	var e := {}
	var tel := root.get_node_or_null("Telemetry")
	if tel:
		tel._perf_systems(e)
		_check(e.get("tick_ms") == 30.0 and e.top_sim.has("sim.traffic"), "perf samples carry the sim's timings (%s)" % str(e))
	else:
		Perf.reset_window()
	_check(Perf.stats["sim.traffic"].n == 0 and Perf.stats["sim.traffic"].avg > 0.0,
		"a new perf window keeps the overlay's smoothed numbers")


func _test_server() -> void:
	var dir := OS.get_user_data_dir().path_join("test-telemetry")
	var data := OS.get_user_data_dir().path_join("test-telemetry-region.json")
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else []:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(data)
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(PORT, "TEL123", data) == OK, "server starts")
	_check(server.telemetry_dir == data.get_basename() + "-telemetry", "telemetry goes next to the region file")
	server.telemetry_dir = dir
	var c := RegionClient.new()
	root.add_child(c)
	c.join("ws://127.0.0.1:%d" % PORT, "TEL123", "p-tel", "Tess")
	await _until(func(): return c.is_joined)
	var acked := []
	c.telemetry_acked.connect(func(id): acked.append(id))
	c.send_telemetry({"id": "s1-1", "session": "s1", "build": "dev",
		"events": [{"k": "hunt", "target": "Parks", "path": ["Parks"], "s": 9.0, "clicks": 5, "travel": 1.0, "end": "used"}]})
	await _until(func(): return not acked.is_empty())
	_check(acked == ["s1-1"], "the server confirms it kept the batch")
	var batches := Insights.read_dir(dir)
	_check(batches.size() == 1 and batches[0].from == "Tess" and batches[0].events[0].target == "Parks",
		"it's kept in the day's file, with who sent it")
	server.write_report()
	_check(FileAccess.get_file_as_string(dir.path_join("report.md")).contains("Hard to find: Parks"),
		"the server writes the fix list")
	c.leave()
	server.stop()


func _until(cond: Callable, max_seconds := 10.0) -> void:
	var end := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
