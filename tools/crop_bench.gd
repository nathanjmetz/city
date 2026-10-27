extends SceneTree
## The crop calendar in a real game window: pictures of the county's fields
## from high up and close over a field through the year, and the cost of
## drawing them (frame time, graphics time, memory).
## Run (desktop renderer, a real window):
##   godot -s tools/crop_bench.gd -- --quality high [--shots DIR] [--months 4.5,6.1,8.5,9.8,0.5] [--frames 240]
## Months count from January (4.5 = mid May). Run with --disable-vsync
## --max-fps 0 so frame times are the machine's, not the screen's.
## --ab FILE: instead of one long sample per view, switch back and forth
## (8 times, 90 frames each) between the new look and the old one: the
## close-up plants off and the ground shader in FILE (the old one), and
## report the median frame of each. Other programs on the machine slow both
## halves alike, so the difference is the cost.
## --freeze: instead of the views, change the farms (a new farm, a road cut
## through the fields, a year turning, a farm growing, a plain
## farms_changed) in a town with --farms N farms (default 6) and report the
## worst frame in the two seconds after each, and how long until the fields
## show the change (FarmView.settled(), when it has one). --without-view
## disconnects FarmView, to see what the rest of the game spends on the change.

var _main: Node
var _cam: CityCamera
var _frames := 0
var _steps := []  # [name, month, yaw, pitch, dist, look]
var _step := -1
var _step_frames := 0
var _samples := PackedFloat32Array()
var _gpu := PackedFloat32Array()
var _rows := []
var _spot := Vector3.ZERO
var _spot2 := Vector3.ZERO
var _farm := Vector3.ZERO
var _last_us := 0
var _settle := 150
var _sample := 240
var _warm := 0
var _ab := ""
var _old_shader: Shader
var _new_shader: Shader
var _half := {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
var _mem := {"new": [], "old": []}
var _freeze := false
var _fz_scn := -1
var _fz_frames := 0
var _fz_t0 := 0
var _fz_times := PackedFloat32Array()
var _fz_shown := -1.0
var _fz_view: FarmView
var _fz_rows := []
var _fz_plants := PackedFloat32Array()
var _fz_worst := [0.0, []]
var _fz_work := PackedFloat32Array()  # FarmView's drawing time in each frame watched


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _arg(name: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_setup()
		return false
	if _step < 0:
		if _frames >= 2 + _warm:
			_next()
		return false
	_step_frames += 1
	var now := Time.get_ticks_usec()
	if _freeze:
		_freeze_frame(now)
		_last_us = now
		return false
	if _ab != "":
		_ab_frame(now)
		_last_us = now
		return false
	if _step_frames == _settle:
		Perf.reset_window()
	if _step_frames > _settle:
		_samples.append((now - _last_us) / 1000.0)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	_last_us = now
	if _step_frames == _settle + _sample:
		_finish_step()
	return false


func _setup() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	_main.set_speed(0)
	DayNight.seasons_on = true
	DayNight.cycle_on = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Hud:
			c.close_all()
	# A farm a few years into its rotation beside a county road, for the
	# town's own fields.
	sim.apply({"type": "build_road", "start": [-1200, 0], "ctrl": [0, 0], "end": [1200, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-1150, 30], [1150, 30], [1150, 1100], [-1150, 1100]]})
	print("farmhouse: ", sim.apply({"type": "place_farmhouse", "pos": [-500, 60], "dir": [0, -1], "crop": "corn"}))
	print("farmhouse: ", sim.apply({"type": "place_farmhouse", "pos": [450, 60], "dir": [0, -1], "crop": "soybeans"}))
	_freeze = _arg("--freeze", "x") != "x" or OS.get_cmdline_user_args().has("--freeze")
	if _freeze:
		var n := int(_arg("--farms", "6"))
		for i in n - 2:
			var x := -1000.0 + 2000.0 * float(i + 1) / float(n - 1) + 140.0
			print("farmhouse: ", sim.apply({"type": "place_farmhouse", "pos": [x, 60], "dir": [0, -1], "crop": "corn" if i % 2 == 0 else "soybeans"}))
	sim.farms.price = 1.1
	for i in 400:
		sim.farms.decide(sim.field_usable)
	for y in 3:
		sim.farms.year += 1
		sim.farms.decide(sim.field_usable)
	sim.farms_changed.emit()
	for id in sim.farms.farms:
		print("farm ", id, " cells ", sim.farms.farms[id].cells.size(), " ", Inspect._crops(sim.farms.farms[id]))
	_farm = Vector3(-500, 0, 330)
	# The spots found on the Grant County data (see _find_field), fixed so a
	# run of older code looks at the same fields.
	var spots := _arg("--spots", "-3000,1260,-3000,1020").split(",")
	_spot = Vector3(float(spots[0]), 0, float(spots[1]))
	_spot2 = Vector3(float(spots[2]), 0, float(spots[3]))
	if _arg("--find", "") != "":
		_spot = _find_field("corn")
		_spot2 = _find_field("soybeans")
	print("county corn spot (view m): ", _spot, "  soybean spot: ", _spot2)
	if _freeze:
		for c in _main.get_children():
			if c is FarmView:
				_fz_view = c
		_warm = int(_arg("--warm", "600"))
		if OS.get_cmdline_user_args().has("--without-view"):
			# What the rest of the game spends on a farm change, FarmView aside.
			sim.farms_changed.disconnect(_fz_view._rebuild)
		sim.set_calendar(Seasons.tick_at(24.0 + 8.5))
		_cam.look_at_point(_farm)
		_cam.set_view(deg_to_rad(20.0), deg_to_rad(40.0), 900.0)
		_step = 0
		_step_frames = 0
		return
	var months := _arg("--months", "4.5,6.1,8.5,9.8,0.5").split(",")
	_sample = int(_arg("--frames", "240"))
	# Let the desktop's land preload finish first (TerrainView.PRELOAD_MS).
	_cam.look_at_point(_spot)
	_cam.set_view(deg_to_rad(30.0), deg_to_rad(52.0), 2600.0)
	_warm = int(_arg("--warm", "1500"))
	_ab = _arg("--ab", "")
	if _ab != "":
		_new_shader = TerrainView.ground_material().shader
		_old_shader = Shader.new()
		_old_shader.code = FileAccess.get_file_as_string(_ab)
	for m in months:
		var mf := float(m)
		_steps.append(["county", mf, 30.0, 52.0, 2600.0, _spot])
		_steps.append(["corn", mf, 200.0, 16.0, 40.0, _spot])
		_steps.append(["beans", mf, 200.0, 16.0, 40.0, _spot2])
		_steps.append(["farm", mf, 20.0, 24.0, 60.0, _farm])


## A spot well inside the county's cropland, away from roads and woods,
## in a field growing `crop` in year 3.
func _find_field(crop: String) -> Vector3:
	var best := Vector3(600, 0, 1400)
	var best_score := -1.0
	for i in 60:
		for j in 60:
			var p := Vector2(-3000 + i * 100.0, 900 + j * 60.0)
			var r := p + Terrain.view_origin
			var score := 0.0
			for d in [Vector2.ZERO, Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60)]:
				var cov := Terrain.cover(r.x + d.x, r.y + d.y)
				score += cov.b - cov.r * 2.0 - cov.g * 4.0
			if CountyGrid.distance(r.x, r.y) < 120.0 or Highways.distance(r.x, r.y) < 120.0:
				continue
			var fld := CropCalendar.county_field(r)
			var slot := CropCalendar.county_slot(Vector2i(fld.x, fld.y))
			if CropCalendar.county_row(slot.x, 3).crop != crop:
				continue
			if score > best_score:
				best_score = score
				best = Vector3(p.x, 0, p.y)
	return best


const FZ_SCENARIOS := ["plain farms_changed", "new farm", "road through fields", "year turns (new crops)", "farm grows"]
const FZ_ROAD_X := -250.0
const FZ_WAIT := 90
const FZ_WATCH := 420


## One frame of the freeze test: wait, change the farms, watch FZ_WATCH frames.
func _freeze_frame(now: int) -> void:
	var sim: CitySim = _main.sim
	if _step_frames < _warm + (0 if _fz_scn >= 0 else 1):
		return
	if _fz_scn < 0 or _fz_frames >= FZ_WAIT + FZ_WATCH:
		if _fz_scn >= 0:
			_freeze_report()
		_fz_scn += 1
		_fz_frames = 0
		_fz_times.clear()
		_fz_work.clear()
		_fz_plants.clear()
		_fz_worst = [0.0, []]
		_fz_shown = -1.0
		if _fz_scn >= FZ_SCENARIOS.size():
			var out := _arg("--out", "")
			if out != "":
				FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(_fz_rows, "  "))
			quit()
			return
	_fz_frames += 1
	if _fz_frames == FZ_WAIT - 30 and _fz_scn == 2:
		# Take the farm reserve off a strip first, so a road can be laid there.
		print("  reserve cleared: ", sim.apply({"type": "paint_reserve", "kind": "", "points": [
			[FZ_ROAD_X - 25, 5], [FZ_ROAD_X + 25, 5], [FZ_ROAD_X + 25, 310], [FZ_ROAD_X - 25, 310]]}))
	if _fz_frames == FZ_WAIT - 30 and _fz_scn == 3:
		sim.farms.year += 1
		sim.farms.decide(sim.field_usable)
	if _fz_frames == FZ_WAIT - 30 and _fz_scn == 4:
		sim.farms.price = 1.4
		for i in 30:
			sim.farms.decide(sim.field_usable)
	if _fz_frames <= FZ_WAIT:
		return
	if _fz_frames == FZ_WAIT + 1:
		Perf.reset_window()
		FarmSteadJob.worst.clear()
		_freeze_change(sim)
		_fz_t0 = Time.get_ticks_usec() - int(_fz_emit_ms * 1000.0)
	_fz_times.append((now - _last_us) / 1000.0)
	_fz_work.append(_fz_view.work_ms if "work_ms" in _fz_view else 0.0)
	_fz_plants.append(_fz_view._plants.built_ms)
	if "work_parts" in _fz_view and _fz_view.work_ms > _fz_worst[0]:
		_fz_worst = [_fz_view.work_ms, _fz_view.work_parts.duplicate()]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _fz_shown < 0.0 and _fz_view.has_method("settled") and _fz_view.settled():
		_fz_shown = (now - _fz_t0) / 1000.0
	elif _fz_shown < 0.0 and not _fz_view.has_method("settled") and _fz_frames > FZ_WAIT + 1:
		_fz_shown = (now - _fz_t0) / 1000.0


func _freeze_change(sim: CitySim) -> void:
	var t0 := Time.get_ticks_usec()
	match _fz_scn:
		0:
			sim.farms_changed.emit()
		1:
			print("  new farm: ", sim.apply({"type": "place_farmhouse", "pos": [-770, 60], "dir": [0, -1], "crop": "corn"}))
		2:
			print("  road: ", sim.apply({"type": "build_road", "start": [FZ_ROAD_X, 0], "ctrl": [FZ_ROAD_X, 150], "end": [FZ_ROAD_X, 300]}))
		3:
			t0 = Time.get_ticks_usec()
			sim.farms_changed.emit()
		4:
			t0 = Time.get_ticks_usec()
			sim.farms_changed.emit()
	_fz_emit_ms = (Time.get_ticks_usec() - t0) / 1000.0


var _fz_emit_ms := 0.0


func _freeze_report() -> void:
	var sorted := _fz_times.duplicate()
	sorted.sort()
	var over := 0
	for v in _fz_times:
		if v > 16.7:
			over += 1
	var row := {"change": FZ_SCENARIOS[_fz_scn], "emit_ms": _fz_emit_ms, "worst_frame_ms": sorted[-1],
		"second_worst_ms": sorted[-2], "median_ms": sorted[sorted.size() / 2], "frames_over_16ms": over,
		"shown_after_ms": _fz_shown}
	_fz_rows.append(row)
	print("FREEZE %-24s emit call %6.1f ms  worst frame %6.1f ms (next %5.1f, median %4.1f)  frames over 16.7 ms: %d  shown after %6.0f ms" % [
		row.change, row.emit_ms, row.worst_frame_ms, row.second_worst_ms, row.median_ms, over, row.shown_after_ms])
	# The farm drawing's own share: its worst frame, and how many frames it
	# was over 3.5 ms (its budget is 3 ms; one farmstead step can run over).
	var worst_work := 0.0
	var long_work := 0
	var slow_frames_with_work := 0
	for i in _fz_work.size():
		worst_work = maxf(worst_work, _fz_work[i])
		long_work += 1 if _fz_work[i] > 3.5 else 0
		if _fz_times[i] > 14.0 and _fz_work[i] > 1.0:
			slow_frames_with_work += 1
	row["worst_farm_work_ms"] = worst_work
	if not FarmSteadJob.worst.is_empty():
		print("   slowest farmstead/barn steps (ms): ", FarmSteadJob.worst)
	print("   first frames after the change (ms): ", ", ".join(Array(_fz_times.slice(0, 6)).map(func(x): return "%.1f" % x)))
	var order := range(_fz_times.size())
	order.sort_custom(func(a, b): return _fz_times[a] > _fz_times[b])
	print("   slowest frames (frame number after the change: ms, of which farm drawing and plants): ", ", ".join(order.slice(0, 4).map(
		func(i): return "#%d: %.1f (farm %.1f, plants %.1f)" % [i, _fz_times[i], _fz_work[i], _fz_plants[i]])))
	print("   farm drawing: worst %.1f ms in a frame (farmsteads %s ms, fields, herds); %d frames over 3.5 ms; frames over 14 ms with farm work in them: %d" % [
		worst_work, ", ".join(Array(_fz_worst[1]).map(func(x): return "%.1f" % x)), long_work, slow_frames_with_work])
	var parts := []
	for k in ["farms.homes", "farms.barns", "farms.cows", "farms.signs", "frame.farm_fields", "frame.crops", "frame.crop_plants", "farm_job.scan", "farm_job.cells", "farm_job.fence", "farm_job.lane", "farm_job.install", "farm_job.plants_check", "farm_stead.build", "farm_stead.drape", "farm_stead.place", "frame.farm_work"]:
		if Perf.stats.has(k):
			parts.append("%s %.1f/%.2f x%d" % [k, Perf.stats[k].max, Perf.stats[k].sum / maxf(Perf.stats[k].n, 1), Perf.stats[k].n])
	print("   worst/mean ms x calls: ", ", ".join(parts))


func _next() -> void:
	_step += 1
	_step_frames = 0
	Perf.reset_window()
	_samples.clear()
	_gpu.clear()
	if _step >= _steps.size():
		_report()
		return
	var s: Array = _steps[_step]
	var sim: CitySim = _main.sim
	var month: float = s[1]
	# Year 3, so the farm's rotation has turned.
	sim.set_calendar(Seasons.tick_at(24.0 + month))
	_cam.look_at_point(s[5])
	_cam.set_view(deg_to_rad(s[2]), deg_to_rad(s[3]), s[4])


const AB_SWITCHES := 8
const AB_FRAMES := 90
const AB_SETTLE := 40


## Switches halves every AB_FRAMES frames: even halves new, odd old.
func _ab_frame(now: int) -> void:
	var f := _step_frames - 1 - _settle
	if f < 0:
		return
	var half := f / AB_FRAMES
	var within := f % AB_FRAMES
	if half >= AB_SWITCHES * 2:
		_ab_report()
		return
	var which := "new" if half % 2 == 0 else "old"
	if within == 0:
		_use(which)
	elif within > AB_SETTLE:
		_half[which].append((now - _last_us) / 1000.0)
	var dir := _arg("--shots", "")
	if within == AB_FRAMES - 1 and half < 2 and dir != "":
		var s: Array = _steps[_step]
		root.get_texture().get_image().save_png(dir.path_join("%s-%s-%s.png" % [s[0], _month_name(s[1]), which]))
	if within == AB_FRAMES - 1:
		_mem[which].append([Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _use(which: String) -> void:
	CropPlants.off = which == "old"
	var sh := _new_shader if which == "new" else _old_shader
	TerrainView.ground_material().shader = sh
	TerrainView.far_material().shader = sh


static func _median(a: PackedFloat32Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2] if not b.is_empty() else 0.0


func _ab_report() -> void:
	var s: Array = _steps[_step]
	var row := {"view": s[0], "month": s[1]}
	for which in ["new", "old"]:
		var b: PackedFloat32Array = _half[which].duplicate()
		b.sort()
		var m: Array = _mem[which][-1]
		row[which] = {"median_ms": _median(b), "p95_ms": b[int(b.size() * 0.95)], "video_mb": m[0], "ram_mb": m[1],
			"tris": m[2]}
	_rows.append(row)
	var tile: Dictionary = Perf.stats.get("crop_plants.tile", {})
	print("   plants: %.2f ms a frame on average; a tile takes %.2f ms on average, %.2f ms at worst" % [
		Perf.mean("frame.crop_plants"), tile.get("sum", 0.0) / maxf(tile.get("n", 0), 1), tile.get("max", 0.0)])
	print("AB %-7s month %4.1f  new: %6.2f ms (p95 %6.2f) video %5.0f MB ram %5.0f MB tris %8d  |  old: %6.2f ms (p95 %6.2f) video %5.0f MB ram %5.0f MB tris %8d" % [
		row.view, row.month, row.new.median_ms, row.new.p95_ms, row.new.video_mb, row.new.ram_mb, row.new.tris,
		row.old.median_ms, row.old.p95_ms, row.old.video_mb, row.old.ram_mb, row.old.tris])
	_half = {"new": PackedFloat32Array(), "old": PackedFloat32Array()}
	_mem = {"new": [], "old": []}
	var dir := _arg("--shots", "")
	if dir != "":
		_use("new")
	_next()


func _finish_step() -> void:
	var s: Array = _steps[_step]
	if s[0] == "farm" and _arg("--debug", "") != "":
		var sim: CitySim = _main.sim
		for id in sim.farms.farms:
			var f: Dictionary = sim.farms.farms[id]
			var seen := {}
			for c in f.cells:
				var k := Farms.forty_of(c)
				if seen.has(k):
					continue
				seen[k] = true
				var slot := FarmView.slot_of(id, f, c)
				var st := CropCalendar.state_at(slot.x, slot.y)
				print("  farm %s forty %s at %s: %s slot %s %s cover %.2f h %.2f %s" % [id, k, Farms.cell_center(f, c),
					CropPlan.field(f, c).crop, slot, st.get("stage"), st.get("cover", 0.0), st.get("height", 0.0),
					Color(st.get("plant", Color.BLACK)).to_html(false)])
	var sorted := _samples.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in _samples:
		mean += v
	mean /= maxf(_samples.size(), 1)
	var gpu := 0.0
	for v in _gpu:
		gpu += v
	gpu /= maxf(_gpu.size(), 1)
	var row := {"view": s[0], "month": s[1], "frame_ms": mean, "p95_ms": sorted[int(sorted.size() * 0.95)],
		"worst_ms": sorted[-1], "gpu_ms": gpu,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"crops_ms": Perf.mean("frame.crops") if Perf.stats.has("frame.crops") else 0.0,
		"plants_ms": Perf.mean("frame.crop_plants") if Perf.stats.has("frame.crop_plants") else 0.0,
		"terrain_ms": Perf.mean("frame.terrain") if Perf.stats.has("frame.terrain") else 0.0,
		"plants": _plant_count()}
	_rows.append(row)
	print("%-7s month %4.1f  frame %6.2f ms (p95 %6.2f, worst %6.1f)  gpu %6.2f ms  video %5.0f MB  ram %5.0f MB  tris %8d  draws %5d  crops %.2f ms  plants %.2f ms (%d)" % [
		row.view, row.month, row.frame_ms, row.p95_ms, row.worst_ms, row.gpu_ms, row.video_mb, row.static_mb,
		row.primitives, row.draw_calls, row.crops_ms, row.plants_ms, row.plants])
	var dir := _arg("--shots", "")
	if dir != "":
		var img := root.get_texture().get_image()
		img.save_png(dir.path_join("%s-%s.png" % [s[0], _month_name(s[1])]))
	_next()


func _plant_count() -> int:
	return int(Perf.counts.get("crop_plants", 0))


static func _month_name(m: float) -> String:
	var names := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
	var day := int(fposmod(m, 1.0) * 30.0) + 1
	return "%s%02d" % [names[int(fposmod(floorf(m), 12.0))], day]


func _report() -> void:
	var out := _arg("--out", "")
	if out != "":
		FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(_rows, "  "))
	quit()
