extends SceneTree
## Automatic quality, over a long run: the real game with a big grid town
## living (PerfTown, N blocks), automatic quality left on, and the camera
## touring the town over and over (high overview, a dive to 40 m, a sweep
## along the streets at 40 m, back up). A stretch in the middle runs at 4x
## speed, so the town's thinking gets heavy while the drawing doesn't.
## Every tier or sharpness change is written down with the window that set
## it off; at the end, how long each tier held and the frame times.
##
## Run: godot --resolution 1600x900 [--rendering-method gl_compatibility]
##        [--quality auto] -s tools/scale/quality_lab.gd -- SAVE BLOCKS MINUTES OUT_DIR TAG [new]
## SAVE is a throwaway save path: never a real town (it is cleared).
## A last argument "new" draws the buildings the new way (the measuring
## prototype in tools/scale/new_drawing/) instead of today's BuildingView.
## `--quality auto` starts Auto from this computer's hardware guess and
## leaves the saved setting alone (see GraphicsQuality).
var _main: Node
var _frames := 0
var _cam: CityCamera
var _span := 0.0
var _start_us := 0
var _last_us := 0
var _changes := []
var _tier_time := {}
var _scale_time := {}
var _minutes := []
var _minute_ms := []
var _all_ms := []
var _speed := 1
var _start := ""


func _q() -> Node:
	return root.get_node_or_null("/root/Quality")


func _process(_d: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		# A save left by an earlier run would load (and catch up) first.
		if FileAccess.file_exists(a[0]):
			DirAccess.remove_absolute(a[0])
		root.get_node("/root/Session").save_path = a[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		# The governor only judges the current scene once it has loaded.
		current_scene = _main
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	if _main.loading:
		return false
	_frames += 1
	var sim: CitySim = _main.sim
	if _frames == 2:
		var new_style := a.size() > 5 and a[5] == "new"
		if new_style:
			for c in _main.get_children():
				if c is BuildingView:
					c.get_parent().remove_child(c)
					c.free()
		sim.apply({"type": "clear"})
		var t := Time.get_ticks_msec()
		PerfTown.build(sim, a[1])
		sim.require_utilities = false
		for i in 3000:
			sim.tick()
		print("QLAB built %d people, %d buildings in %d s" % [sim.stats.population, sim.buildings.size(), (Time.get_ticks_msec() - t) / 1000])
		if new_style:
			var view: Node3D = load("res://tools/scale/new_drawing/new_drawing_view.gd").new()
			_main.add_child(view)
			view.setup(sim)
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_span = int(a[1]) * 140.0
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false
		_main.set_speed(1)
		var q := _q()
		q.changed.connect(_on_change)
		_start = q.describe()
		print("QLAB start ", _start)
		_start_us = Time.get_ticks_usec()
		_last_us = _start_us
		return false
	if _start_us == 0:
		return false
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1e6
	_last_us = now
	var secs := (now - _start_us) / 1e6
	var total := float(a[2]) * 60.0
	_tour(secs)
	# The middle third at 4x: heavy thinking, the same drawing.
	var want := 3 if secs > total / 3.0 and secs < total * 2.0 / 3.0 else 1
	if want != _speed:
		_speed = want
		_main.set_speed(want)
		_changes.append({"t": snappedf(secs, 0.1), "speed": "4x" if want == 3 else "1x"})
	var q := _q()
	var tn: String = GraphicsQuality.NAMES[q.tier]
	_tier_time[tn] = _tier_time.get(tn, 0.0) + dt
	var sk := "%d%%" % roundi(q.scale * 100.0)
	_scale_time[sk] = _scale_time.get(sk, 0.0) + dt
	_minute_ms.append(dt * 1000.0)
	_all_ms.append(dt * 1000.0)
	if _minute_ms.size() > 1 and secs >= (_minutes.size() + 1) * 60.0:
		_minutes.append(_summary(_minute_ms).merged({"tier": tn, "scale": sk, "focus": root.has_focus()}))
		print("QLAB minute %d %s" % [_minutes.size(), JSON.stringify(_minutes[-1])])
		_minute_ms = []
	if secs >= total:
		var out := {"tag": a[4], "start": _start,
			"tier_changes": _changes.filter(func(c): return c.has("tier")).size(),
			"changes": _changes, "seconds_at_tier": _round(_tier_time), "seconds_at_scale": _round(_scale_time),
			"frames": _summary(_all_ms), "minutes": _minutes, "population": sim.stats.population,
			"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
			"end": q.describe()}
		var f := FileAccess.open("%s/quality_%s.json" % [a[3], a[4]], FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("QLAB %s" % JSON.stringify(out))
		quit()
		return true
	return false


## A 120-second loop: overview (turning slowly), a dive to 40 m, a sweep
## along the streets, and back up.
func _tour(secs: float) -> void:
	var s := fmod(secs, 120.0)
	if s < 40.0:
		_cam.look_at_point(Vector3(0, 0, 0))
		_cam.set_view(deg_to_rad(270.0 + s * 2.0), deg_to_rad(28.0), 900.0)
	elif s < 60.0:
		var t := (s - 40.0) / 20.0
		_cam.look_at_point(Vector3(0, 0, 0))
		_cam.set_view(deg_to_rad(350.0), deg_to_rad(lerpf(60.0, 22.0, t)), lerpf(3000.0, 40.0, t * t * (3.0 - 2.0 * t)))
	elif s < 100.0:
		var t := (s - 60.0) / 40.0
		_cam.look_at_point(Vector3(lerpf(-_span * 0.4, _span * 0.4, t), 0, lerpf(-_span * 0.2, _span * 0.3, t)))
		_cam.set_view(deg_to_rad(45.0 + t * 90.0), deg_to_rad(22.0), 40.0)
	else:
		var t := (s - 100.0) / 20.0
		_cam.look_at_point(Vector3(lerpf(_span * 0.4, 0.0, t), 0, lerpf(_span * 0.3, 0.0, t)))
		_cam.set_view(deg_to_rad(lerpf(135.0, 270.0, t)), deg_to_rad(lerpf(22.0, 28.0, t)), lerpf(40.0, 900.0, t))


func _on_change() -> void:
	var q := _q()
	var secs := (Time.get_ticks_usec() - _start_us) / 1e6
	var c := {"t": snappedf(secs, 0.1), "tier": GraphicsQuality.NAMES[q.tier], "scale": snappedf(q.scale, 0.01)}
	if "last_window" in q:
		c["window"] = q.last_window
	if "last_reason" in q:
		c["why"] = q.last_reason
	_changes.append(c)
	print("QLAB change ", JSON.stringify(c))


func _summary(ms: Array) -> Dictionary:
	var s := ms.duplicate()
	s.sort()
	var sum := 0.0
	var over := 0
	for m in s:
		sum += m
		if m > 50.0:
			over += 1
	return {"avg_ms": snappedf(sum / s.size(), 0.1), "p50_ms": snappedf(s[s.size() / 2], 0.1),
		"p95_ms": snappedf(s[int(s.size() * 0.95)], 0.1), "worst_ms": snappedf(s[-1], 0.1),
		"over_50ms": over, "frames": s.size()}


func _round(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = roundi(d[k])
	return out
