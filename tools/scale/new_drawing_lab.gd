extends SceneTree
## The new drawing style, measured: the real game with PerfTown (N blocks)
## living, today's BuildingView taken out, and the buildings drawn the new
## way instead (tools/scale/new_drawing/): instanced shapes from small facts
## everywhere, a lighter middle version within about 300 m, and real-size
## brick, siding, shingles and windows grown in code within about 100 m.
## Roads, land, trees, cars and people are the game's own.
##
## Modes, timed exactly as combined_lab.gd and zoom_lab.gd time today's
## drawing (frame windows, 1x then 4x; the dive and the sweep):
##   combined  frame avg, p95, worst at 1x and 4x, graphics memory
##   zoom      the 3 km to 40 m dive and the 40 m sweep, frames over 50 ms
##   shots     far, middle and street-level pictures (its own camera, down
##             to eye height, which the game's camera doesn't go to)
## A last argument "today" keeps today's BuildingView instead, so both
## styles are measured by the same lab (triangles and draw calls too).
## Pin the graphics tier (--quality high) so the game's automatic quality
## doesn't change the picture under the measurement.
## Run: godot --resolution 1600x900 [--rendering-method gl_compatibility]
##        --quality high -s tools/scale/new_drawing_lab.gd -- SAVE BLOCKS MODE OUT_DIR TAG [today]
## SAVE is a throwaway save path: never a real town (it is cleared).
## Results of 2026-10-25: docs/scale-test-2026-10-25.md.

const View := preload("res://tools/scale/new_drawing/new_drawing_view.gd")
const Facts := preload("res://tools/scale/new_drawing/facts.gd")

var _main: Node
var _view: Node3D
var _frames := 0
var _ms := []
var _prims := []
var _calls := []
var _cpu := []
## What the slow frames were doing: each measured part's time in the
## frames over 50 ms (what's left over is drawing and the graphics chip).
var _last := {}
var _tot := {}
var _stut := {}
var _stut_n := 0
var _res := {}
var _cam: CityCamera
var _shot_cam: Camera3D
var _mode := ""
var _today := false


func _process(d: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		_mode = a[2]
		_today = a.size() > 5 and a[5] == "today"
		# A save left by an earlier run would load (and catch up) first.
		if FileAccess.file_exists(a[0]):
			DirAccess.remove_absolute(a[0])
		root.get_node("/root/Session").save_path = a[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	if _main.loading:
		return false
	_frames += 1
	var sim: CitySim = _main.sim
	if _frames == 2:
		# Today's building drawing out; nothing else of the game changes.
		for c in _main.get_children():
			if c is BuildingView and not _today:
				c.get_parent().remove_child(c)
				c.free()
		sim.apply({"type": "clear"})
		var t := Time.get_ticks_msec()
		PerfTown.build(sim, a[1])
		sim.require_utilities = false
		for i in 3000:
			sim.tick()
		print("NEWDRAW built %d people, %d buildings in %d s" % [sim.stats.population, sim.buildings.size(), (Time.get_ticks_msec() - t) / 1000])
		if not _today:
			t = Time.get_ticks_msec()
			_view = View.new()
			_main.add_child(_view)
			_view.setup(sim)
			_res["draw_setup_s"] = snappedf((Time.get_ticks_msec() - t) / 1000.0, 0.1)
			print("NEWDRAW drawn %d buildings in %.1f s" % [_view.facts.size(), _res.draw_setup_s])
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_main.set_speed(1)
		return false
	if _frames == 3 or _frames == 2300:
		_main.set_speed(1)
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false
		var span: float = int(a[1]) * 140.0
		_cam.look_at_point(Vector3(span * 0.5 + 100.0, 0, 0))
		_cam.set_view(deg_to_rad(270.0), deg_to_rad(28.0), 900.0)
	match _mode:
		"combined": return _combined(d, a, sim)
		"zoom": return _zoom(d, a)
		_: return _shots(a)


func _sample(d: float) -> void:
	_ms.append(d * 1000.0)
	# Each part's time since the last frame (Telemetry zeroes Perf's sums
	# now and then, so a sum that went down started again from zero).
	var snap := {}
	var delta := {}
	for k in Perf.stats:
		snap[k] = float(Perf.stats[k].sum)
		var dk: float = snap[k] - float(_last.get(k, 0.0))
		delta[k] = snap[k] if dk < 0.0 else dk
	if not _last.is_empty():
		for k in delta:
			_tot[k] = _tot.get(k, 0.0) + delta[k]
		if d * 1000.0 > 50.0:
			_stut_n += 1
			for k in delta:
				_stut[k] = _stut.get(k, 0.0) + delta[k]
	_last = snap
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# The CPU's time spent handing the frame to the graphics chip, as the
	# engine measures it (its graphics-chip time reads 0 on this Mac).
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))


func _summary(hitch := false) -> Dictionary:
	var n := 0
	for m in _ms:
		n += 1 if m > 50.0 else 0
	_ms.sort()
	var sum := 0.0
	for m in _ms:
		sum += m
	var r := {"frame_avg_ms": snappedf(sum / _ms.size(), 0.1), "frame_p95_ms": snappedf(_ms[int(_ms.size() * 0.95)], 0.1),
		"frame_worst_ms": snappedf(_ms[-1], 0.1), "fps": snappedf(1000.0 / (sum / _ms.size()), 0.1),
		"render_cpu_ms_avg": snappedf(_avg(_cpu), 0.1),
		"triangles_avg": int(_avg(_prims)), "triangles_max": int(_prims.max()), "draw_calls_avg": int(_avg(_calls))}
	if hitch:
		r["stutters_over_50ms"] = n
	var ns: Dictionary = _view.near.stats if _view else {"frames": 0, "cover_sum": 0.0, "cover_min": 0.0, "grown": 0, "released": 0, "late": 0}
	r["near"] = {"cover_avg": snappedf(ns.cover_sum / maxf(ns.frames, 1.0), 0.01), "cover_min": snappedf(ns.cover_min, 0.01),
		"grown": ns.grown, "released": ns.released, "late_swaps": ns.late, "held_at_end": _view.near.grown_count() if _view else 0}
	var parts := {}
	for k in _tot:
		parts[k] = snappedf(_tot[k] / maxf(_ms.size(), 1.0), 0.1)
	_tot.clear()
	var ks := parts.keys()
	ks.sort_custom(func(x, y): return parts[x] > parts[y])
	var top := {}
	for k in ks.slice(0, 10):
		top[k] = parts[k]
	r["per_frame_ms"] = top
	var worst := {}
	for k in ["frame.nd_near", "frame.nd_sync", "frame.buildings", "frame.trees", "sim.tick"]:
		if Perf.stats.has(k):
			worst[k] = snappedf(float(Perf.stats[k].max), 0.1)
	r["worst_ms"] = worst
	var why := {}
	for k in _stut:
		why[k] = snappedf(_stut[k] / maxf(_stut_n, 1.0), 0.1)
	var wk := why.keys()
	wk.sort_custom(func(x, y): return why[x] > why[y])
	var top_why := {}
	for k in wk.slice(0, 6):
		top_why[k] = why[k]
	r["slow_frames"] = {"n": _stut_n, "parts_ms": top_why}
	_stut.clear()
	_stut_n = 0
	_ms.clear()
	_prims.clear()
	_calls.clear()
	_cpu.clear()
	return r


static func _avg(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / maxf(xs.size(), 1.0)


func _begin() -> void:
	Perf.reset()
	_last = {}
	if _view:
		_view.near.reset_stats()


func _combined(d: float, a: PackedStringArray, sim: CitySim) -> bool:
	# Settle until the town is drawn, then time 600 frames at 1x, then 600 at 4x.
	if _frames == 2400 or _frames == 3200:
		_begin()
	if _frames > 2400 and _frames <= 3000 or _frames > 3200 and _frames <= 3800:
		_sample(d)
	if _frames == 3000 or _frames == 3800:
		var key := "1x" if _frames == 3000 else "4x"
		_res[key] = _summary()
		if _frames == 3000:
			root.get_viewport().get_texture().get_image().save_png("%s/newdraw_combined_%s.png" % [a[3], a[4]])
			_main.set_speed(3)
	if _frames == 3800:
		_res["population"] = sim.stats.population
		_res["buildings"] = sim.buildings.size()
		_res["mem_mb"] = OS.get_static_memory_usage() / 1048576
		_res["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576
		_res["texture_mb"] = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576
		_res["buffer_mb"] = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576
		_res["renderer"] = RenderingServer.get_current_rendering_method()
		print("NEWDRAW combined %s %s" % [a[4], JSON.stringify(_res)])
		quit()
		return true
	return false


func _zoom(d: float, a: PackedStringArray) -> bool:
	# Dive from 3 km to 40 m over 600 frames, then sweep at 40 m for 1,200.
	var span: float = int(a[1]) * 140.0
	if _frames == 2400:
		_begin()
	if _frames > 2400 and _frames <= 3000:
		var t := float(_frames - 2400) / 600.0
		_cam.look_at_point(Vector3(0, 0, 0))
		_cam.set_view(deg_to_rad(45.0), deg_to_rad(lerpf(60.0, 22.0, t)), lerpf(3000.0, 40.0, t * t * (3.0 - 2.0 * t)))
	elif _frames > 3000 and _frames <= 4200:
		var t := float(_frames - 3000) / 1200.0
		_cam.look_at_point(Vector3(lerpf(-span * 0.45, span * 0.45, t), 0, lerpf(-span * 0.2, span * 0.3, t)))
		_cam.set_view(deg_to_rad(45.0 + t * 90.0), deg_to_rad(22.0), 40.0)
	if _frames > 2400 and _frames <= 4200:
		_sample(d)
	if _frames in [2550, 2800, 3000, 3300, 3900]:
		root.get_viewport().get_texture().get_image().save_png("%s/newdraw_zoom_%s_%d.png" % [a[3], a[4], _frames])
	if _frames == 3000 or _frames == 4200:
		_res["dive" if _frames == 3000 else "sweep"] = _summary(true)
		_begin()
	if _frames == 4200:
		_res["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576
		_res["renderer"] = RenderingServer.get_current_rendering_method()
		print("NEWDRAW zoom %s %s" % [a[4], JSON.stringify(_res)])
		quit()
		return true
	return false


## Pictures: far, middle, a street of homes at eye height, and a brick wall
## close enough to see each brick.
func _shots(a: PackedStringArray) -> bool:
	var span: float = int(a[1]) * 140.0
	if _frames == 2400:
		_main.set_speed(0)
		_shot_cam = Camera3D.new()
		_shot_cam.fov = 50.0
		_shot_cam.far = 20000.0
		_main.add_child(_shot_cam)
		_shot_cam.current = true
	if _frames < 2400:
		return false
	var f := _target(span)
	var c: Vector3 = f.centre
	var front: Vector3 = f.basis * Vector3(0, 0, -1)
	var side: Vector3 = f.basis * Vector3(1, 0, 0)
	var shots := [
		["far", c + Vector3(-1300, 750, 1300), c],
		["middle", c + front * 150.0 + side * 120.0 + Vector3.UP * 70.0, c],
		["street", c + front * (f.d * 0.5 + 16.0) + side * 9.0 + Vector3.UP * 1.7, c + Vector3.UP * 2.6 - side * 2.0],
		["brick", c + front * (f.d * 0.5 + 2.4) + side * 1.2 + Vector3.UP * 1.6, c + front * (f.d * 0.5) - side * 1.5 + Vector3.UP * 1.3],
		["roofline", c + front * (f.d * 0.5 + 7.0) - side * (f.w * 0.5 + 4.0) + Vector3.UP * 4.5, c + Vector3.UP * (f.h + 0.5)],
	]
	var i := (_frames - 2400) / 90
	var k := (_frames - 2400) % 90
	if i >= shots.size():
		print("NEWDRAW shots %s target %s %s" % [a[4], f.key, Facts.Mat.keys()[f.mat]])
		quit()
		return true
	var s: Array = shots[i]
	if k == 0:
		_shot_cam.look_at_from_position(s[1], s[2], Vector3.UP)
	if k == 89:
		root.get_viewport().get_texture().get_image().save_png("%s/newdraw_%s_%s.png" % [a[3], a[4], s[0]])
	return false


var _picked := {}


## A brick house in the homes west of downtown, facing its street.
func _target(span: float) -> Dictionary:
	if not _picked.is_empty():
		return _picked
	var want := Vector3(-span * 0.22, 0, span * 0.12)
	var best := INF
	for key in _view.facts:
		var f: Dictionary = _view.facts[key]
		if f.type != "house" or int(f.mat) != Facts.Mat.BRICK:
			continue
		var dd: float = Vector2(f.centre.x - want.x, f.centre.z - want.z).length()
		if dd < best:
			best = dd
			_picked = f
	if _picked.is_empty() and not _view.facts.is_empty():
		_picked = _view.facts.values()[0]
	return _picked
