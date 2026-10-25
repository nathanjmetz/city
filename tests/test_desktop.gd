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
	_review_fixes()
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


## Review fixes (PR 555, 2026-10-25): first picks capped by memory, a reload
## that isn't a crash, saved timers, very slow tabs, quick first steps.
## Every governor here runs in lab mode or on its own test file: the
## player's own saved setting is never touched.
func _review_fixes() -> void:
	var m5 := "ANGLE (Apple, ANGLE Metal Renderer: Apple M5 Max, Unspecified Version)"
	var m3pro := "ANGLE (Apple, ANGLE Metal Renderer: Apple M3 Pro)"
	var igpu := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	var dgpu := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var cases := [
		[m5, false, 8.0, GraphicsQuality.HIGH, "Chrome on a big Mac with 8 GB reported"],
		[m5, false, 0.0, GraphicsQuality.MEDIUM, "a browser that doesn't report memory: Medium at most"],
		[m5, false, 4.0, GraphicsQuality.MEDIUM, "4 GB reported: Medium at most"],
		[m5, false, 2.0, GraphicsQuality.LOW, "2 GB reported: Low"],
		[m3pro, false, 8.0, GraphicsQuality.HIGH, "the Pro chip"],
		[m3pro, false, 0.0, GraphicsQuality.MEDIUM, "the Pro chip, memory unknown"],
		["", false, 8.0, GraphicsQuality.LOW, "an empty chip name"],
		[m5, true, 8.0, GraphicsQuality.LOW, "a tablet"],
	]
	for c in cases:
		var got := GraphicsQuality.first_pick(c[0], true, c[1], c[2], igpu, 8, 0.0)
		_check(got == c[3], "first pick: %s starts on %s (got %s)" % [c[4], GraphicsQuality.NAMES[c[3]], GraphicsQuality.NAMES[got]])
	var rtx := "NVIDIA GeForce RTX 4090"
	_check(GraphicsQuality.first_pick(rtx, false, false, 0.0, dgpu, 24, 64.0, 2000.0) == GraphicsQuality.MEDIUM
		and GraphicsQuality.first_pick(rtx, false, false, 0.0, dgpu, 24, 64.0, 0.0) == GraphicsQuality.CINEMATIC
		and GraphicsQuality.first_pick(rtx, false, false, 0.0, dgpu, 24, 64.0, 24000.0) == GraphicsQuality.CINEMATIC,
		"a desktop's first pick is capped by readable video memory, and not when unreadable")
	_check(GraphicsQuality.first_pick("", false, false, 0.0, igpu, 4, 8.0) == GraphicsQuality.LOW,
		"a desktop with no chip name starts on Low")
	_check(GraphicsQuality.handheld_from(false, false, true, false, true, 5)
		and not GraphicsQuality.handheld_from(false, false, true, false, false, 0)
		and not GraphicsQuality.handheld_from(false, false, false, true, true, 10)
		and GraphicsQuality.handheld_from(true, false, false, false, false, 0),
		"an iPad that says it's a Mac is a tablet; a real Mac and a touch PC are not")
	# A reload is not a crash.
	var now := 10000.0
	_check(not GraphicsQuality.web_crashed({}, now), "a normal reload leaves no marker: not a crash")
	_check(not GraphicsQuality.web_crashed({"start": now - 4000.0, "beat": now - 600.0}, now),
		"a long session cut off later is not blamed on the look")
	_check(not GraphicsQuality.web_crashed({"start": now - 60.0, "beat": now - 5.0}, now),
		"a marker still being beaten is another open tab")
	_check(GraphicsQuality.web_crashed({"start": now - 200.0, "beat": now - 120.0}, now),
		"a short session that left its marker and stopped is a crash")
	# Saved timers: a short session still moves the wait along.
	var path := "user://test_quality_review.json"
	var q := _auto("NVIDIA GeForce RTX 4070", 32.0)
	q._lab = false
	q.save_path = path
	q._ceiling = GraphicsQuality.ULTRA
	q.tier = GraphicsQuality.ULTRA
	q._fails = 2
	q._waited = 100.0
	q._decay = 50.0
	q._scale_top = 0.85
	q._scale_waited = 30.0
	q._scale_fails = 1
	q._save()
	var r := _auto("NVIDIA GeForce RTX 4070", 32.0)
	var saved := GraphicsQuality._read(path)
	_check(r.restorable(saved), "a saved setting for this chip is taken up")
	r.restore(saved)
	_check(r.tier == GraphicsQuality.ULTRA and r._ceiling == GraphicsQuality.ULTRA and r._fails == 2
		and r._waited == 100.0 and r._decay == 50.0 and r._scale_waited == 30.0 and r._scale_fails == 1
		and absf(r._scale_top - 0.85) < 0.001, "the wait timers survive a save and a load")
	var middling := {"frame_ms": 19.0, "sim_ms": 2.0, "draw_ms": 17.0, "gpu_ms": 0.0, "cpu_ms": 9.0}
	q._settle = 0
	q._first_window = false
	for i in 12:  # 36 seconds, no tier change
		q._judge(middling, 3.0)
	var later := GraphicsQuality._read(path)
	_check(float(later.waited) >= 100.0 + 30.0, "a short session with no tier change still saves how long it waited (%s)" % later.get("waited"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Failures fade with play time even while the ceiling is held below.
	var f := _auto("NVIDIA GeForce RTX 4070", 32.0)
	f._ceiling = GraphicsQuality.HIGH
	f.tier = GraphicsQuality.HIGH
	f._fails = 3
	f._settle = 0
	f._first_window = false
	for i in int(3.2 * 3600.0 / 3.0):
		f._judge(middling, 3.0)
	_check(f._fails == 0, "failures fade over hours even with a ceiling lowered (left %d)" % f._fails)
	# A very slow tab: runs of long frames step down at once.
	var w := _auto("ANGLE (NVIDIA, NVIDIA GeForce RTX 4070)", 0.0, true)
	w._settle = 0
	for i in GraphicsQuality.STALL_RUN - 1:
		w._count_stall(400.0)
	_check(w.tier == GraphicsQuality.HIGH and w.scale == 1.0, "a few long frames alone change nothing")
	w._count_stall(400.0)
	_check(w.scale < 1.0, "a run of very long frames takes fewer pixels at once (scale %.2f)" % w.scale)
	for k in 12:
		for i in GraphicsQuality.STALL_RUN:
			w._count_stall(400.0)
	_check(w.tier == GraphicsQuality.LOW and w.scale <= 0.56, "and keeps stepping down to the floor (%s, %.2f)" % [GraphicsQuality.NAMES[w.tier], w.scale])
	# Time to step down: frames far too slow in the very first window.
	var d := _auto("NVIDIA GeForce RTX 4070", 32.0)
	var awful := {"frame_ms": 130.0, "sim_ms": 2.0, "draw_ms": 128.0, "gpu_ms": 100.0, "cpu_ms": 10.0}
	d._judge(awful, 3.0)
	_check(d.tier < GraphicsQuality.CINEMATIC or d.scale < 1.0, "frames over 100 ms in the first window step down within 3 seconds")
	var d2 := _auto("NVIDIA GeForce RTX 4070", 32.0)
	var bad := {"frame_ms": 60.0, "sim_ms": 2.0, "draw_ms": 58.0, "gpu_ms": 0.0, "cpu_ms": 10.0}
	d2._judge(bad, 3.0)
	_check(d2.tier == GraphicsQuality.CINEMATIC and d2.scale == 1.0, "just slow in the first window still settles first")
	# A weak tab isn't held after a step that didn't help.
	var h := _auto("ANGLE (NVIDIA, NVIDIA GeForce RTX 4070)", 0.0, true)
	h._settle = 0
	h._first_window = false
	h._down_hold = 40
	h._pixels_no_help = true
	h._judge({"frame_ms": 130.0, "sim_ms": 2.0, "draw_ms": 128.0, "gpu_ms": 0.0, "cpu_ms": 0.0}, 3.0)
	_check(h.tier == GraphicsQuality.MEDIUM, "drawing three times too slow ignores a hold")
	# The browser's memory cap: over it for two windows steps down, however fast the frames.
	var mem := _auto("ANGLE (NVIDIA, NVIDIA GeForce RTX 4070)", 0.0, true)
	mem._settle = 0
	mem._first_window = false
	var fat := {"frame_ms": 16.0, "sim_ms": 2.0, "draw_ms": 14.0, "gpu_ms": 0.0, "cpu_ms": 0.0, "video_mb": 1700}
	mem._judge(fat, 3.0)
	_check(mem.tier == GraphicsQuality.HIGH, "one window over the browser's memory cap waits")
	mem._judge(fat, 3.0)
	_check(mem.tier == GraphicsQuality.MEDIUM, "two windows over the browser's memory cap step down")
	# Picking a tier in the menu forgets a step waiting to be checked.
	var c := _auto("NVIDIA GeForce RTX 4070", 32.0)
	c._check = {"tier": 4, "scale": 1.0, "draw": 30.0, "pixels": false}
	c._down_hold = 9
	c.choose(GraphicsQuality.HIGH)
	_check(c._check.is_empty() and c._down_hold == 0, "a pick in the Graphics menu clears the stale step check")
	for g in [q, r, f, w, d, d2, h, mem, c]:
		g.free()


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
