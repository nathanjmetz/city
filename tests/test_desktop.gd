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
		"the browser grows detail in at most %.0f ms and has no field plants" % GraphicsQuality.BROWSER_GROW_MS)
	_check(GraphicsQuality.knob("far_from") == 1.0 and not GraphicsQuality.knob("crops")
		and GraphicsQuality.knob("cars_m") == TrafficView.FAR and GraphicsQuality.knob("people_m") == WalkerView.FAR
		and GraphicsQuality.knob("cars") == GraphicsQuality.NO_CAP and GraphicsQuality.knob("grow_ms") == WildView.BUDGET_MS,
		"headless views keep the untiered look, with no count caps")
	# Never cap a full-strength desktop: High and up draw at least what the
	# game drew before budgets.
	for t in range(GraphicsQuality.HIGH, GraphicsQuality.CINEMATIC + 1):
		var b := GraphicsQuality.budget_for(t)
		_check(b.cars_m >= TrafficView.FAR and b.car_near_m >= TrafficView.NEAR and b.people_m >= WalkerView.FAR
			and b.woods >= 1.0 and b.grow_ms >= WildView.BUDGET_MS and b.crops,
			"%s draws cars, people and woods at least as far as before budgets" % GraphicsQuality.NAMES[t])
	var low := GraphicsQuality.budget_for(GraphicsQuality.LOW)
	_check(low.cars_m < TrafficView.FAR and low.people_m < WalkerView.FAR and low.woods < 1.0 and low.people < 1000,
		"Low draws fewer cars, people and trees")
	# The most-at-once: walkers spread over the ground, 2,000 inside 320 m.
	var crowd := func(r: float) -> int: return roundi(2000.0 * r * r / (320.0 * 320.0))
	var reach := 320.0
	var drawn := 0
	var most := 0
	for i in 300:
		drawn = crowd.call(reach)
		if i > 10:
			most = maxi(most, drawn)
		reach = GraphicsQuality.fit_reach(reach, drawn, 400, 320.0)
	_check(most <= 400 and drawn >= 250, "a crowded street draws the nearest 400 people, no more (%d, %.0f m)" % [drawn, reach])
	reach = 320.0
	for i in 50:
		reach = GraphicsQuality.fit_reach(reach, crowd.call(reach), GraphicsQuality.NO_CAP, 320.0)
	_check(reach == 320.0, "with no cap the reach stays full")
	reach = 100.0
	for i in 200:
		reach = GraphicsQuality.fit_reach(reach, 50, 400, 320.0)
	_check(reach == 320.0, "a quiet street grows the reach back to full")


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
	# Cinematic is too heavy for this town; Ultra draws it easily.
	var cost := func(t: int, _s: float) -> Dictionary:
		if t == GraphicsQuality.CINEMATIC:
			return {"frame_ms": 30.0, "sim_ms": 3.0, "draw_ms": 27.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
		return {"frame_ms": 9.0, "sim_ms": 1.0, "draw_ms": 8.0, "gpu_ms": 0.0, "cpu_ms": 4.0}
	var steps := []
	for i in 4:
		q._judge(cost.call(q.tier, q.scale), 3.0)
		steps.append(q.tier)
	_check(steps == [4, 3, 3, 3], "slow drawing steps down one tier, then waits for the new look to settle (%s)" % [steps])
	_play(q, 3.0, cost)
	_check(q.tier == GraphicsQuality.ULTRA, "a tier that proved too slow stays out of reach for minutes")
	var again := _play(q, 3.0, cost)
	_check(again.any(func(c): return c[1] == GraphicsQuality.CINEMATIC), "after the wait it tries that tier again")
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
	b._guess = GraphicsQuality.LOW
	b.mode = GraphicsQuality.AUTO
	b._first_guess()
	b.apply()
	var smooth := {"frame_ms": 16.7, "sim_ms": 4.0, "draw_ms": 12.7, "gpu_ms": 0.0, "cpu_ms": 0.0}
	for i in 100:
		b._judge(smooth, 3.0)
	_check(b.tier == GraphicsQuality.HIGH, "a browser with room climbs to High and no further")
	# A laptop whose chip is the limit: fewer pixels help, then a tier.
	var laptop := func(t: int, s: float) -> Dictionary:
		var draw: float = [40.0, 55.0, 70.0][t] * (0.4 + 0.6 * s * s)
		return {"frame_ms": draw + 4.0, "sim_ms": 4.0, "draw_ms": draw, "gpu_ms": 0.0, "cpu_ms": 0.0}
	_play(b, 3.0, laptop)
	_check(b.scale < 1.0 and b.tier < GraphicsQuality.HIGH, "a slow browser takes fewer pixels, then a lower tier")
	q.free()
	b.free()
	_first_pick()
	_machines()
	_no_flapping()
	GraphicsQuality.budget = GraphicsQuality.INACTIVE.duplicate()
	GraphicsQuality.detail = 1.0
	GraphicsQuality.tree_shadows = true


## A governor in Auto for a made-up computer, as _ready would set it up.
func _auto(chip: String, memory_gb: float, on_browser := false) -> GraphicsQuality:
	var q := GraphicsQuality.new()
	q.active = true
	q._lab = true
	q.browser = on_browser
	q.adapter = chip
	q._memory_gb = memory_gb
	q._guess = GraphicsQuality.browser_first(chip, false) if on_browser \
		else GraphicsQuality.guess_tier(chip, RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU if chip.begins_with("Apple") \
			else RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, 8, memory_gb)
	q.mode = GraphicsQuality.AUTO
	q._first_guess()
	q.apply()
	return q


## Plays `minutes` of 3-second windows, each made by `look` from the
## governor's tier and scale; returns every change as [minute, tier, scale].
func _play(q: GraphicsQuality, minutes: float, look: Callable) -> Array:
	var changes := []
	var was := [q.tier, q.scale]
	for i in int(minutes * 20.0):
		q._judge(look.call(q.tier, q.scale), 3.0)
		if [q.tier, q.scale] != was:
			was = [q.tier, q.scale]
			changes.append([snappedf(i * 3.0 / 60.0, 0.1), q.tier, snappedf(q.scale, 0.01)])
	return changes


## The first tier from the hardware: the browser by the chip its WebGL
## names, the desktop by chip and memory (see the cases above).
func _first_pick() -> void:
	var cases := [
		["ANGLE (Apple, ANGLE Metal Renderer: Apple M5 Max, Unspecified Version)", false, GraphicsQuality.HIGH,
			"Chrome on the M5 Max"],
		["ANGLE (Apple, ANGLE Metal Renderer: Apple M2 Ultra, Unspecified Version)", false, GraphicsQuality.HIGH,
			"a Mac Studio's browser"],
		["ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)", false, GraphicsQuality.LOW,
			"an 8 GB Mac mini's browser"],
		["ANGLE (NVIDIA, NVIDIA GeForce RTX 4070 (0x00002786) Direct3D11 vs_5_0 ps_5_0, D3D11)", false,
			GraphicsQuality.HIGH, "a gaming PC's browser"],
		["ANGLE (NVIDIA, NVIDIA GeForce GTX 1660 SUPER Direct3D11 vs_5_0 ps_5_0, D3D11)", false,
			GraphicsQuality.MEDIUM, "an older gaming PC's browser"],
		["ANGLE (Intel, Intel(R) UHD Graphics 620 (0x00005917) Direct3D11 vs_5_0 ps_5_0, D3D11)", false,
			GraphicsQuality.LOW, "an office laptop's browser"],
		["WebKit WebGL", false, GraphicsQuality.LOW, "a browser that hides the chip"],
		["ANGLE (NVIDIA, NVIDIA GeForce RTX 4070)", true, GraphicsQuality.LOW, "a tablet"],
	]
	for c in cases:
		var got := GraphicsQuality.browser_first(c[0], c[1])
		_check(got == c[2], "%s starts on %s (got %s)" % [c[3], GraphicsQuality.NAMES[c[2]], GraphicsQuality.NAMES[got]])


## Each kind of machine and its budget.
func _machines() -> void:
	var mini := _auto("Apple M2", 8.0)
	var studio := _auto("Apple M2 Max", 64.0)
	var pro := _auto("Apple M4 Pro", 24.0)
	var pc := _auto("NVIDIA GeForce RTX 4070", 32.0)
	var web := _auto("ANGLE (Apple, ANGLE Metal Renderer: Apple M2 Max)", 0.0, true)
	_check(mini.machine() == "small" and mini.tier == GraphicsQuality.LOW and mini.auto_top() == GraphicsQuality.MEDIUM,
		"the 8 GB Mac mini: small, starts on Low, climbs no higher than Medium")
	_check(studio.machine() == "full" and studio.tier == GraphicsQuality.CINEMATIC
		and studio.auto_top() == GraphicsQuality.CINEMATIC, "the Mac Studio: full strength, Cinematic")
	_check(pro.machine() == "shared" and pro.auto_top() == GraphicsQuality.ULTRA, "a 24 GB Pro chip: shared, up to Ultra")
	_check(pc.machine() == "full" and pc.auto_top() == GraphicsQuality.CINEMATIC, "a Windows gaming PC: full strength")
	_check(web.machine() == "browser" and web.auto_top() == GraphicsQuality.HIGH and web.tier == GraphicsQuality.HIGH,
		"a browser: up to High, a strong chip starting there")
	# Graphics memory: the mini holds where it is near its budget, and
	# climbs once there's room; a full-strength desktop has no memory cap.
	var roomy := func(_t: int, _s: float, mb: int) -> Dictionary:
		return {"frame_ms": 9.0, "sim_ms": 1.0, "draw_ms": 8.0, "gpu_ms": 0.0, "cpu_ms": 4.0, "video_mb": mb}
	_play(mini, 3.0, func(t, s): return roomy.call(t, s, 2400))
	_check(mini.tier == GraphicsQuality.LOW, "the mini doesn't climb with its graphics memory near full")
	_play(mini, 3.0, func(t, s): return roomy.call(t, s, 900))
	_check(mini.tier == GraphicsQuality.MEDIUM, "with memory to spare it climbs to Medium, and stops there")
	studio.tier = GraphicsQuality.HIGH
	studio._settle = 0
	_play(studio, 3.0, func(t, s): return roomy.call(t, s, 9000))
	_check(studio.tier == GraphicsQuality.CINEMATIC, "the Mac Studio climbs to Cinematic whatever memory it uses")
	for q in [mini, studio, pro, pc, web]:
		q.free()


## No flapping: a machine at the edge of a tier doesn't switch back and
## forth. Before (2026-10-25) the wait for a tier that proved too slow was
## forgiven while it was being waited out, so it came back every 10
## minutes all session; and the sharpness could step down and back up
## every half minute.
func _no_flapping() -> void:
	# A Mac Studio whose town is too heavy for Cinematic, light on Ultra.
	var studio := _auto("Apple M2 Max", 64.0)
	var heavy_top := func(t: int, _s: float) -> Dictionary:
		if t == GraphicsQuality.CINEMATIC:
			return {"frame_ms": 30.0, "sim_ms": 3.0, "draw_ms": 27.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
		return {"frame_ms": 9.0, "sim_ms": 1.0, "draw_ms": 8.0, "gpu_ms": 0.0, "cpu_ms": 4.0}
	var changes := _play(studio, 60.0, heavy_top)
	var tries := changes.filter(func(c): return c[1] == GraphicsQuality.CINEMATIC).map(func(c): return c[0])
	var gaps_grow := true
	for i in range(2, tries.size()):
		gaps_grow = gaps_grow and tries[i] - tries[i - 1] > tries[i - 1] - tries[i - 2]
	_check(tries.size() <= 3 and gaps_grow and studio.tier == GraphicsQuality.ULTRA,
		"a tier that's too slow is tried again less and less often (an hour: Cinematic again at minutes %s)" % [tries])
	# A browser right at the edge of full sharpness on Low.
	var web := _auto("ANGLE (Intel, Intel(R) UHD Graphics 620)", 0.0, true)
	var edge := func(t: int, s: float) -> Dictionary:
		if t == GraphicsQuality.LOW and s < 0.99:
			return {"frame_ms": 18.0, "sim_ms": 4.0, "draw_ms": 14.0, "gpu_ms": 0.0, "cpu_ms": 0.0}
		return {"frame_ms": 40.0, "sim_ms": 4.0, "draw_ms": 36.0, "gpu_ms": 0.0, "cpu_ms": 0.0}
	changes = _play(web, 10.0, edge)
	_check(changes.size() <= 4 and web.tier == GraphicsQuality.LOW,
		"a browser at the edge of full sharpness doesn't flip back and forth (10 minutes: %s)" % [changes])
	# A computer whose frames wobble around Ultra's cost: 30 minutes of
	# noisy windows (the same made-up noise every run).
	var pc := _auto("NVIDIA GeForce RTX 4060", 16.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wobble := func(t: int, _s: float) -> Dictionary:
		var draw := (12.0 if t <= GraphicsQuality.ULTRA else 23.0) + rng.randf_range(-5.0, 5.0)
		var sim := rng.randf_range(0.0, 8.0)
		return {"frame_ms": draw + sim, "sim_ms": sim, "draw_ms": draw, "gpu_ms": 0.0, "cpu_ms": draw * 0.4}
	changes = _play(pc, 30.0, wobble)
	tries = changes.filter(func(c): return c[1] == GraphicsQuality.CINEMATIC).map(func(c): return c[0])
	var gaps := []
	for i in range(1, tries.size()):
		gaps.append(tries[i] - tries[i - 1])
	var spaced := gaps.all(func(g): return g >= GraphicsQuality.PATIENCE_MIN)
	for i in range(1, gaps.size()):
		spaced = spaced and gaps[i] > gaps[i - 1]
	_check(changes.size() <= 6 and spaced,
		"frames that wobble around a tier's cost: tries of the tier above at least 5 minutes apart, then further (30 minutes: %s)" % [changes])
	for q in [studio, web, pc]:
		q.free()
	_steps_must_help()


## A step down has to make the drawing faster, or it's taken back from the
## record (GraphicsQuality.HELPED).
func _steps_must_help() -> void:
	# The window lab on the M5 Max (2026-10-25): a new town still building
	# its detail is slow at every tier for a minute; then Cinematic draws
	# it in 15 ms. Before, this walked Cinematic to Low in 43 s and held
	# it there for 40 minutes.
	var studio := _auto("Apple M5 Max", 48.0)
	var windows := [0]
	var building := func(t: int, _s: float) -> Dictionary:
		var draw := 60.0 if windows[0] < 20 else (15.0 if t == GraphicsQuality.CINEMATIC else 10.0)
		windows[0] += 1
		return {"frame_ms": draw + 3.0, "sim_ms": 3.0, "draw_ms": draw, "gpu_ms": 0.0, "cpu_ms": 4.0}
	var changes := _play(studio, 3.0, building)
	var lowest := GraphicsQuality.CINEMATIC
	for c in changes:
		lowest = mini(lowest, c[1])
	_check(lowest >= GraphicsQuality.ULTRA and studio.tier == GraphicsQuality.CINEMATIC and studio._fails == 0,
		"a town still building doesn't walk the look down: one step, back to Cinematic once built (%s)" % [changes])
	# A browser whose slowness isn't pixels (the town's drawing work on the
	# CPU): a sharpness step that didn't help is given back, then a tier.
	var web := _auto("ANGLE (Apple, ANGLE Metal Renderer: Apple M5 Max)", 0.0, true)
	var cpu_bound := func(t: int, _s: float) -> Dictionary:
		var draw := 45.0 if t == GraphicsQuality.HIGH else 25.0
		return {"frame_ms": draw + 4.0, "sim_ms": 4.0, "draw_ms": draw, "gpu_ms": 0.0, "cpu_ms": 0.0}
	changes = _play(web, 5.0, cpu_bound)
	_check(web.tier == GraphicsQuality.MEDIUM and web.scale == 1.0 and changes.size() <= 3,
		"fewer pixels that don't help are given back, and a tier steps instead (%s)" % [changes])
	studio.free()
	web.free()


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
