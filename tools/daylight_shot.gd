extends "res://tools/screenshot.gd"
## The demo town lit for real dates and clock times, to check the sun, sky
## and shadows (see docs/daylight.md), or to time what the lighting costs.
## Run in a real window (not --headless):
##   godot --resolution 1600x900 -s tools/daylight_shot.gd -- OUT_DIR yaw pitch dist shots
##       saves one picture per moment in MOMENTS, named like 06-21_1340.png
##   ... -- OUT_DIR yaw pitch dist fixed
##       day and night off (the default look), in July and in January
##   godot --resolution 1600x900 -s tools/daylight_shot.gd -- OUT_FILE yaw pitch dist time
##       times frames with day and night on (the clock moving a game minute a
##       frame, so the light changes every frame) against off, in turns, and
##       writes the means to OUT_FILE
## Add --rendering-method gl_compatibility for the browser's renderer.

## Month (1-12), day, clock hour (local time, daylight saving in summer).
const MOMENTS := [[6, 21, 7.0], [6, 21, 10.0], [6, 21, 13.0 + 40.0 / 60.0], [6, 21, 18.0],
	[6, 21, 20.75], [12, 21, 13.0]]
const ROUND := 300  # frames timed per turn
const ROUNDS := 4

var _step := -1
var _wait := 0
var _last_us := 0
var _turn := {"on": [], "off": []}
var _cycle_was := false
var _hour := 7.0


func _initialize() -> void:
	pass  # the game opens on the first frame, once the autoloads are up


func _open() -> void:
	# A throwaway save, so the demo town never lands on a real town.
	root.get_node("/root/Session").save_path = "user://daylight_bench.city"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _finalize() -> void:
	for f in ["user://daylight_bench.city", "user://daylight_bench.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _process(delta: float) -> bool:
	if _main == null:
		_open()
		return false
	if _frames < 3:
		return super(delta)
	var args := OS.get_cmdline_user_args()
	if _frames == 3:
		_frames += 1
		_main.speed = 0
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false  # no panels over the view
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_cycle_was = DayNight.cycle_on
		DayNight.cycle_on = true
		DayNight.seasons_on = true
		return false
	if args.size() >= 5 and args[4] == "time":
		return _time(args[0])
	if args.size() >= 5 and args[4] == "fixed":
		return _fixed(args[0])
	return _shots(args[0])


func _fixed(dir: String) -> bool:
	DayNight.cycle_on = false
	_wait += 1
	if _wait == 1:
		_set_moment(7, 15, 11.0)
	elif _wait == 60:
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("fixed_july.png"))
		_set_moment(1, 15, 11.0)
	elif _wait == 120:
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("fixed_january.png"))
		DayNight.cycle_on = _cycle_was
		quit()
	return false


func _shots(dir: String) -> bool:
	_wait += 1
	if _step >= 0 and _wait < 40:
		return false  # let the frame settle (shadows, sky)
	if _step >= 0:
		var m: Array = MOMENTS[_step]
		var name := "%02d-%02d_%02d%02d.png" % [m[0], m[1], int(m[2]), roundi(fmod(m[2], 1.0) * 60.0)]
		root.get_viewport().get_texture().get_image().save_png(dir.path_join(name))
		print("saved ", dir.path_join(name))
	_step += 1
	_wait = 0
	if _step >= MOMENTS.size():
		DayNight.cycle_on = _cycle_was
		quit()
		return false
	var m: Array = MOMENTS[_step]
	_set_moment(m[0], m[1], m[2])
	return false


## The town's calendar on that day, with the light pinned to that day and
## hour (the sky's hour comes from how far through the month it is).
func _set_moment(month: int, day: int, hour: float) -> void:
	var sim: CitySim = _main.sim
	var date := float(month - 1) + float(day - 1) / Seasons.DAYS_IN[month - 1]
	sim.set_calendar(Seasons.tick_at(12.0 + date))
	_hour = hour
	for n in _main.find_children("*", "DayNight", true, false):
		n.set("date_override", date)
		n.set("hour_override", hour)


func _time(out: String) -> bool:
	var now := Time.get_ticks_usec()
	var sim: CitySim = _main.sim
	var vp := root.get_viewport_rid()
	if _last_us == 0:
		_set_moment(6, 21, 7.0)
		RenderingServer.viewport_set_measure_render_time(vp, true)
	# One game minute a frame through a June day, 7 am to 7 pm, round and
	# round: the sun and sky change every frame, the night lights stay off.
	_hour += 1.0 / 60.0
	if _hour >= 19.0:
		_hour -= 12.0
	for n in _main.find_children("*", "DayNight", true, false):
		n.set("hour_override", _hour)
	_wait += 1
	var k := "on" if DayNight.cycle_on else "off"
	if _wait > 30 and _last_us > 0:  # skip the first frames of each turn
		# Wall time can be capped by the display; the measured work is not.
		_turn[k].append([(now - _last_us) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	_last_us = now
	if _wait >= ROUND + 30:
		_wait = 0
		if _turn.off.size() >= ROUND * ROUNDS:
			var r := {}
			for t in _turn:
				var rows: Array = _turn[t]
				var stat := {}
				for col in 4:
					var a: Array = []
					for row in rows:
						a.append(row[col])
					a.sort()
					var sum := 0.0
					for v in a:
						sum += v
					stat[["frame", "process", "render_cpu", "gpu"][col]] = {"mean_ms": snappedf(sum / a.size(), 0.001),
						"median_ms": a[a.size() / 2], "p95_ms": a[int(a.size() * 0.95)]}
				r[t] = stat
			r["renderer"] = RenderingServer.get_current_rendering_method()
			# DayNight's own CPU time a frame (both turns), where it measures it.
			r["light_cpu_ms"] = snappedf(Perf.mean("frame.light"), 0.001)
			for col in ["frame", "process", "render_cpu", "gpu"]:
				r["added_" + col + "_ms"] = snappedf(r.on[col].mean_ms - r.off[col].mean_ms, 0.001)
			print("DAYLIGHT TIME ", JSON.stringify(r))
			FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(r, "  "))
			DayNight.cycle_on = _cycle_was
			quit()
			return false
		DayNight.cycle_on = not DayNight.cycle_on
	return false
