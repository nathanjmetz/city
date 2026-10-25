extends SceneTree
## The desktop app's first-run graphics guess and the version range that
## lets slightly different builds share a region.
## Run: godot --headless -s tests/test_desktop.gd

var _failed := false


func _init() -> void:
	var dgpu := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var igpu := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	_check(GraphicsQuality.guess_tier("Apple M2 Max", igpu, 12, 48.0) == GraphicsQuality.CINEMATIC,
		"a Mac Studio with 48 GB starts on Cinematic")
	_check(GraphicsQuality.guess_tier("Apple M2", igpu, 8, 8.0) == GraphicsQuality.LOW,
		"an 8 GB Mac mini starts on Low")
	_check(GraphicsQuality.guess_tier("Apple M4", igpu, 10, 16.0) == GraphicsQuality.MEDIUM,
		"a 16 GB base Mac starts on Medium")
	_check(GraphicsQuality.guess_tier("Apple M4 Pro", igpu, 12, 24.0) == GraphicsQuality.HIGH, "a Pro chip starts on High")
	_check(GraphicsQuality.guess_tier("NVIDIA GeForce RTX 4070", dgpu, 16, 32.0) == GraphicsQuality.CINEMATIC,
		"a gaming PC starts on Cinematic")
	_check(GraphicsQuality.guess_tier("Intel(R) UHD Graphics 620", igpu, 4, 8.0) == GraphicsQuality.LOW,
		"an old office laptop starts on Low")
	_check(GraphicsQuality.guess_tier("llvmpipe (LLVM 20)", RenderingDevice.DEVICE_TYPE_CPU, 32, 64.0) == GraphicsQuality.LOW,
		"software drawing starts on Low")
	for t in GraphicsQuality.TIERS.size() - 1:
		var lo: Dictionary = GraphicsQuality.TIERS[t]
		var hi: Dictionary = GraphicsQuality.TIERS[t + 1]
		_check(hi.detail >= lo.detail and hi.shadow_size >= lo.shadow_size and hi.lod <= lo.lod,
			"%s never looks worse than %s" % [GraphicsQuality.NAMES[t + 1], GraphicsQuality.NAMES[t]])
	_windows_gpus()
	_budgets()
	_governor()

	# Versions: the server takes anything from MIN_PROTOCOL to its own.
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(9391, "ABC123", "user://test-desktop-region.json", "Host") == OK, "a region starts")
	_check(_hello(9391, {"v": RegionServer.PROTOCOL, "min": RegionServer.MIN_PROTOCOL}), "the same version gets in")
	_check(not _hello(9391, {"v": RegionServer.MIN_PROTOCOL - 1}), "a too-old game is turned away")
	_check(not _hello(9391, {"v": RegionServer.PROTOCOL + 1, "min": RegionServer.PROTOCOL + 1}),
		"a game that needs a newer server is turned away")
	server.stop()
	DirAccess.remove_absolute("user://test-desktop-region.json")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Windows and Linux graphics chips, by name (what Vulkan and Direct3D
## report), and the memory beside them.
func _windows_gpus() -> void:
	var d := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var i := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	var cases := [
		["NVIDIA GeForce RTX 4090", d, 24, 64.0, GraphicsQuality.CINEMATIC, "a top gaming PC"],
		["NVIDIA GeForce RTX 3070", d, 8, 16.0, GraphicsQuality.CINEMATIC, "an RTX 3070"],
		["NVIDIA GeForce RTX 4060", d, 12, 16.0, GraphicsQuality.ULTRA, "a mid card of today"],
		["NVIDIA GeForce RTX 3060 Laptop GPU", d, 16, 16.0, GraphicsQuality.HIGH, "a gaming laptop, a step down"],
		["NVIDIA GeForce RTX 2060", d, 6, 16.0, GraphicsQuality.HIGH, "an older RTX"],
		["NVIDIA GeForce GTX 1660 SUPER", d, 6, 16.0, GraphicsQuality.HIGH, "a GTX 1660"],
		["NVIDIA GeForce GTX 1050 Ti", d, 4, 8.0, GraphicsQuality.MEDIUM, "an old budget card"],
		["NVIDIA GeForce MX450", d, 8, 16.0, GraphicsQuality.LOW, "a thin laptop's MX chip"],
		["NVIDIA GeForce RTX 4080", d, 8, 8.0, GraphicsQuality.ULTRA, "a big card with 8 GB of memory waits for Cinematic"],
		["AMD Radeon RX 7900 XTX", d, 16, 32.0, GraphicsQuality.CINEMATIC, "a top Radeon"],
		["AMD Radeon RX 6600", d, 6, 16.0, GraphicsQuality.ULTRA, "a mid Radeon"],
		["AMD Radeon RX 6800M", d, 8, 16.0, GraphicsQuality.ULTRA, "a laptop Radeon, a step down"],
		["AMD Radeon RX 580 Series", d, 4, 16.0, GraphicsQuality.MEDIUM, "an old Radeon"],
		["AMD Radeon RX 9070 XT", d, 8, 32.0, GraphicsQuality.CINEMATIC, "a new Radeon"],
		["Intel(R) Arc(TM) A770 Graphics", d, 8, 16.0, GraphicsQuality.HIGH, "an Intel Arc card"],
		["Intel(R) Iris(R) Xe Graphics", i, 8, 16.0, GraphicsQuality.MEDIUM, "a newer office laptop"],
		["Intel(R) UHD Graphics 770", i, 6, 8.0, GraphicsQuality.LOW, "an office desktop's built-in graphics"],
		["AMD Radeon(TM) Graphics", i, 6, 8.0, GraphicsQuality.LOW, "a small AMD laptop"],
		["AMD Radeon 780M Graphics", i, 16, 32.0, GraphicsQuality.MEDIUM, "a strong built-in Radeon"],
		["Some Future GPU 9000", d, 16, 32.0, GraphicsQuality.ULTRA, "an unknown card, climbing from Ultra"],
		["Microsoft Basic Render Driver", i, 8, 16.0, GraphicsQuality.LOW, "no graphics driver"],
	]
	for c in cases:
		var got := GraphicsQuality.guess_tier(c[0], c[1], c[2], c[3])
		_check(got == c[4], "%s starts on %s (got %s)" % [c[5], GraphicsQuality.NAMES[c[4]], GraphicsQuality.NAMES[got]])


## Every tier's detail budget gives at least as much as the tier below.
func _budgets() -> void:
	for t in GraphicsQuality.BUDGETS.size() - 1:
		var lo := GraphicsQuality.budget_for(t)
		var hi := GraphicsQuality.budget_for(t + 1)
		var ok := true
		for k in lo:
			if typeof(lo[k]) == TYPE_BOOL:
				ok = ok and (hi[k] or not lo[k])
			else:
				ok = ok and hi[k] >= lo[k]
		_check(ok, "%s's detail budget is at least %s's" % [GraphicsQuality.NAMES[t + 1], GraphicsQuality.NAMES[t]])
	var web := GraphicsQuality.budget_for(GraphicsQuality.HIGH, true)
	_check(web.grow_ms <= GraphicsQuality.BROWSER_GROW_MS and not web.crops,
		"the browser grows detail in 2 ms and has no field plants")
	_check(GraphicsQuality.knob("far_from") == 1.0 and not GraphicsQuality.knob("crops"),
		"headless views keep the untiered look")


## The governor, fed made-up 3-second windows: the town's thinking never
## moves the tier; slow drawing steps down one tier at a time with a
## settle between; a tier that was too slow isn't tried again for minutes.
func _governor() -> void:
	var q := GraphicsQuality.new()
	q.active = true
	q._lab = true
	q.adapter = "Apple M5 Max"
	q._memory_gb = 48.0
	q._guess = GraphicsQuality.CINEMATIC
	q.mode = GraphicsQuality.AUTO
	q._first_guess()
	q.apply()
	var busy_town := {"frame_ms": 60.0, "sim_ms": 48.0, "draw_ms": 12.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
	for i in 40:
		q._judge(busy_town, 3.0)
	_check(q.tier == GraphicsQuality.CINEMATIC, "a busy town's thinking alone never lowers the look")
	var heavy := {"frame_ms": 30.0, "sim_ms": 3.0, "draw_ms": 27.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
	var steps := []
	for i in 4:
		q._judge(heavy, 3.0)
		steps.append(q.tier)
	_check(steps == [4, 3, 3, 3], "slow drawing steps down one tier, then waits for the new look to settle (%s)" % [steps])
	var quiet := {"frame_ms": 9.0, "sim_ms": 1.0, "draw_ms": 8.0, "gpu_ms": 0.0, "cpu_ms": 4.0}
	for i in 60:  # 3 minutes of room
		q._judge(quiet, 3.0)
	_check(q.tier == GraphicsQuality.ULTRA, "a tier that proved too slow stays out of reach for minutes")
	for i in 60:  # past 5 minutes
		q._judge(quiet, 3.0)
	_check(q.tier == GraphicsQuality.CINEMATIC, "after the wait it tries that tier again")
	for i in 4:
		q._judge(heavy, 3.0)
	_check(q.tier == GraphicsQuality.ULTRA and q.patience() > GraphicsQuality.PATIENCE_MIN,
		"failing again waits longer (%.0f minutes)" % q.patience())
	var middling := {"frame_ms": 19.0, "sim_ms": 2.0, "draw_ms": 17.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
	var before: int = q.tier
	for i in 200:
		q._judge(middling, 3.0)
	_check(q.tier == before, "between room and too slow, it holds")
	# The browser: judged against 30 fps, Low to High.
	var b := GraphicsQuality.new()
	b.active = true
	b._lab = true
	b.browser = true
	b._guess = GraphicsQuality.MEDIUM
	b.mode = GraphicsQuality.AUTO
	b._first_guess()
	b.apply()
	var smooth := {"frame_ms": 16.7, "sim_ms": 4.0, "draw_ms": 12.7, "gpu_ms": 0.0, "cpu_ms": 0.0}
	for i in 100:
		b._judge(smooth, 3.0)
	_check(b.tier == GraphicsQuality.HIGH, "a browser with room climbs to High and no further")
	var laptop := {"frame_ms": 40.0, "sim_ms": 4.0, "draw_ms": 36.0, "gpu_ms": 0.0, "cpu_ms": 0.0}
	for i in 30:
		b._judge(laptop, 3.0)
	_check(b.scale < 1.0 and b.tier < GraphicsQuality.HIGH, "a slow browser takes fewer pixels, then a lower tier")
	q.free()
	b.free()
	GraphicsQuality.budget = GraphicsQuality.INACTIVE.duplicate()
	GraphicsQuality.detail = 1.0
	GraphicsQuality.tree_shadows = true


## Whether a hello with these version fields is let in (welcomed or asked to
## wait) rather than turned away.
func _hello(port: int, versions: Dictionary) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	peer.create_client("ws://127.0.0.1:%d" % port)
	var msg := {"t": "hello", "code": "ABC123", "id": "t%d" % randi(), "name": "Tester %d" % randi_range(1, 9999),
		"password": "", "new": true, "token": ""}
	msg.merge(versions)
	var sent := false
	for i in 400:
		peer.poll()
		for n in root.get_children():
			if n is RegionServer:
				n._process(0.016)
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not sent:
			peer.put_packet(JSON.stringify(msg).to_utf8_buffer())
			sent = true
		while peer.get_available_packet_count() > 0:
			var reply = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if typeof(reply) == TYPE_DICTIONARY and reply.get("t") in ["welcome", "waiting", "reject"]:
				peer.close()
				return reply.t != "reject"
		OS.delay_msec(5)
	peer.close()
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
