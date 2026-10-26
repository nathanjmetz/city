extends SceneTree
## What each part of the drawing costs: a built-out test town (PerfTown) in
## mid-July seen from the street, from 100 m and from 300 m up. For each
## view it saves a picture, times the frames (the sim paused, so the times
## are the drawing's, the frame rate not held to the screen's), and reads
## the draw calls and triangles; then hides one part at a time (grown trees,
## the card trees, the buildings' close-up detail, the buildings, the
## woods, the land, the roads, cars and people, sun shadows) and reads what
## each one adds, against the frames just before with it shown. For
## before-and-after numbers of a drawing change (run the same command on
## main and on the branch).
## Run in a real window, the tier pinned:
##   godot --resolution 1600x900 [--rendering-method gl_compatibility] --quality cinematic
##     -s tools/render_budget.gd -- SAVE OUT_DIR [--blocks=5] [--years=0] [--parts=0] [--part-frames=6]
## SAVE is a throwaway save path: never a real town (it is cleared).
## --years=N: every planted tree as if it went in N years earlier.
## --parts=0 skips hiding the parts (pictures and frame times only).
## --part-frames=N counts N frames with and without each part (6 is enough
## for draw calls and triangles; about 40 for a rough frame-time price).
## Every view is timed before any part is hidden: showing a part again can
## stall a few later frames. On a Mac the frame rate is held to 60 even with
## vsync off, so frames under 16.7 ms read as 16.7, and the graphics chip's
## own time reads 0.

## [name, point looked at (x, z), yaw, pitch, distance behind the point].
var VIEWS := [
	["street", Vector2(-280.0, -250.0), 0.0, 5.0, 36.0],
	["block_100m", Vector2(-280.0, -280.0), 0.6, 32.0, 190.0],
	["town_300m", Vector2(-150.0, -150.0), 0.6, 40.0, 470.0],
]
const SETTLE := 150
const TIMED := 240
## Per part: frames to settle, then frames counted, shown and then hidden.
const PART_SETTLE := 3
var PART_COUNT := 6

var _main: Node
var _frames := 0
var _cam: CityCamera
var _out := "."
var _view := -1
var _vf := 0
var _ms := []
var _last_us := 0
var _rows := []
var _parts := []  # [name, callable(hide: bool)]
var _part := -1
var _pf := 0
var _base := Vector2.ZERO
var _sum := Vector2.ZERO
var _n := 0
var _render := Vector2.ZERO  # summed render cpu, gpu ms over the timed frames
var _with_ms := []
var _without_ms := []
var _pass := 0  # 0 timing every view, 1 hiding the parts in each


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=")[1]
	return fallback


func _process(_delta: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		if FileAccess.file_exists(a[0]):
			DirAccess.remove_absolute(a[0])
		root.get_node("/root/Session").save_path = a[0]
		_out = a[1]
		DirAccess.make_dir_recursive_absolute(_out)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	if _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		Weather.on = false
		DayNight.cycle_on = false
		# Mid-July of the first year (a game day is a month of the seasons).
		sim.tick_count = int(fposmod(6.5 - Seasons.START_MONTH, 12.0) * Seasons.TICKS_PER_DAY)
		TreeField.extra_years = float(_arg("years", "0"))
		PerfTown.build(sim, _arg("blocks", "5"))
		for key in sim.buildings:
			sim.buildings[key].built = sim.tick_count
		sim.buildings_changed.emit()
		sim.require_utilities = false
		_main.set_speed(0)
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
				_cam.ignore_floor = true
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		print("town: %d people, %d buildings" % [sim.stats.population, sim.buildings.size()])
		_street_aim(sim)
		PART_COUNT = int(_arg("part-frames", "6"))
		if _arg("parts", "1") != "0":
			_make_parts()
		return false
	if _cam == null:
		return false
	if _frames < 400:
		# The town draws in over a few hundred frames.
		_aim(VIEWS[0])
		return false
	if _view < 0:
		_trees()
		_next_view()
		return false
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	_vf += 1
	var row: Dictionary = _rows[_view]
	if _pass == 1:
		# The parts, once every view is timed (showing a part again can
		# stall a few later frames, which would spoil the timing).
		if _vf == 60:
			_part = -1
			_next_part()
		elif _vf > 60:
			_part_frame(row, ms)
		return false
	if _vf <= SETTLE:
		if _vf == SETTLE:
			Perf.reset_window()
		return false
	if _vf <= SETTLE + TIMED:
		_ms.append(ms)
		if ms > 50.0:
			# A slow frame: the engine's own times for it, to tell the
			# game's work from the drawing's.
			if not row.has("slow"):
				row.slow = []
			if row.slow.size() < 6:
				row.slow.append({"frame": _vf, "ms": snappedf(ms, 0.1),
					"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
					"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
						+ RenderingServer.get_frame_setup_time_cpu(), 0.1),
					"render_gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), 0.1)})
		_sum += _counts()
		_n += 1
		var vp := root.get_viewport_rid()
		_render += Vector2(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
			RenderingServer.viewport_get_measured_render_time_gpu(vp))
		if _vf == SETTLE + TIMED:
			var avg := _sum / _n
			row.calls = avg.x
			row.tris = avg.y
			row.render_cpu_ms = snappedf(_render.x / _n, 0.01)
			row.render_gpu_ms = snappedf(_render.y / _n, 0.01)
			row.merge(_summary(_ms))
			row.slowest_parts = _slowest()
			var g := _grown()
			if g:
				row.grown = g.stats()
			root.get_texture().get_image().save_png(_out.path_join(VIEWS[_view][0] + ".png"))
			_next_view()
	return false


## One part hidden at a time: what the frame loses without it, against
## the frames just before with it shown.
func _part_frame(row: Dictionary, ms: float) -> void:
	_pf += 1
	var span := PART_SETTLE + PART_COUNT
	if _pf > PART_SETTLE and _pf <= span:
		_sum += _counts()
		_n += 1
		_with_ms.append(ms)
	if _pf == span:
		_base = _sum / _n
		_sum = Vector2.ZERO
		_n = 0
		(_parts[_part][1] as Callable).call(true)
	if _pf > span + PART_SETTLE:
		_sum += _counts()
		_n += 1
		_without_ms.append(ms)
	if _pf >= span * 2:
		var without := _sum / _n
		(_parts[_part][1] as Callable).call(false)
		row.parts[_parts[_part][0]] = [int(_base.x - without.x), int(_base.y - without.y),
			snappedf(_median(_with_ms) - _median(_without_ms), 0.1)]
		_next_part()


func _counts() -> Vector2:
	return Vector2(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _next_part() -> void:
	_part += 1
	_with_ms.clear()
	_without_ms.clear()
	_pf = 0
	_sum = Vector2.ZERO
	_n = 0
	if _part >= _parts.size():
		_next_view()


func _next_view() -> void:
	_view += 1
	_vf = 0
	_ms.clear()
	_sum = Vector2.ZERO
	_n = 0
	_last_us = 0
	_render = Vector2.ZERO
	if _view >= VIEWS.size():
		if _pass == 0 and not _parts.is_empty():
			_pass = 1
			_view = 0
			_aim(VIEWS[_view])
			return
		_report()
		quit()
		return
	if _pass == 0:
		_rows.append({"name": VIEWS[_view][0], "parts": {}})
	_aim(VIEWS[_view])


func _report() -> void:
	print("renderer: %s, %s" % [RenderingServer.get_current_rendering_method(),
		GraphicsQuality.current.describe() if GraphicsQuality.current else "?"])
	for r in _rows:
		print("view %-11s draw calls %5d  triangles %9d  frame median %5.1f ms  p95 %5.1f ms  worst %5.1f ms  over 33 ms %d/%d  render cpu %.2f gpu %.2f ms" % [
			r.name, r.calls, r.tris, r.median_ms, r.p95_ms, r.worst_ms, r.over_33ms, TIMED, r.render_cpu_ms, r.render_gpu_ms])
		print("    slowest measured parts (mean / worst ms): ", r.slowest_parts)
		if r.has("slow"):
			print("    slow frames: ", r.slow)
		if r.has("grown"):
			print("    grown trees: ", r.grown)
		for k in r.parts:
			if absi(r.parts[k][0]) < 8 and absi(r.parts[k][1]) < 20000 and absf(r.parts[k][2]) < 0.5:
				continue
			print("    without %-22s -%5d calls  -%9d triangles  -%5.1f ms (median)" % [k, r.parts[k][0], r.parts[k][1], r.parts[k][2]])
	print("graphics memory %d MB, static memory %d MB" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	var f := FileAccess.open(_out.path_join("render_budget.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_rows, "  "))


func _grown() -> GrownTrees:
	var g := _main.find_children("*", "GrownTrees", true, false)
	return g[0] if g.size() > 0 else null


## The parts hidden one at a time. Grown trees show themselves each frame,
## so their groups are hidden instead.
func _make_parts() -> void:
	var by_class := {}
	for c in _main.get_children():
		if c is Node3D and not c is CityCamera:
			var cls: String = c.get_script().get_global_name() if c.get_script() else c.get_class()
			by_class[cls] = by_class.get(cls, []) + [c]
	_parts.append(["grown trees", func(h: bool):
		var g := _grown()
		if g:
			for m in g.get_children():
				m.visible = not h])
	_parts.append(["grown tree shadows", func(h: bool):
		var g := _grown()
		if g:
			_shadows(g.get_children(), h)])
	for lod in 2:
		var lname: String = ["full", "light"][lod]
		_parts.append(["grown %s trees" % lname, func(h: bool): _show(_grown_groups(lod), not h)])
		_parts.append(["grown %s shadows" % lname, func(h: bool): _shadows(_grown_groups(lod), h)])
	_parts.append(["card trees (lots)", func(h: bool): _show(_fields(true), not h)])
	_parts.append(["card tree shadows (lots)", func(h: bool): _shadows(_fields(true), h)])
	_parts.append(["card trees (woods)", func(h: bool): _show(_fields(false), not h)])
	_parts.append(["card tree shadows (woods)", func(h: bool): _shadows(_fields(false), h)])
	_parts.append(["building shadows", func(h: bool): _shadows(_main.find_children("*", "BuildingView", true, false), h)])
	_parts.append(["far woods", func(h: bool): _show(_main.find_children("*", "FarWoods", true, false), not h)])
	_parts.append(["near detail", func(h: bool): _show(_main.find_children("*", "NearDetail", true, false), not h)])
	_parts.append(["building squares", func(h: bool): _show(_main.find_children("*", "BatchSquare", true, false), not h)])
	_parts.append(["far squares", func(h: bool): _show(_main.find_children("*", "FarSquares", true, false), not h)])
	for cls in by_class:
		_parts.append([cls, func(h: bool): _show(by_class[cls], not h)])
	for fx in ["sdfgi", "ssil", "ssr", "ssao", "volumetric_fog", "glow"]:
		_parts.append([fx, func(h: bool):
			for we in root.find_children("*", "WorldEnvironment", true, false):
				var env: Environment = we.environment
				if env == null:
					continue
				if h:
					we.set_meta("rb_" + fx, env.get(fx + "_enabled"))
					env.set(fx + "_enabled", false)
				elif we.has_meta("rb_" + fx):
					env.set(fx + "_enabled", we.get_meta("rb_" + fx))])
	_parts.append(["sun shadows", func(h: bool):
		for l in _main.find_children("*", "DirectionalLight3D", true, false):
			l.shadow_enabled = not h])


## The grown trees' groups of one level (grown meshes and the cards standing
## in for them).
func _grown_groups(lod: int) -> Array:
	var out := []
	var g := _grown()
	if g == null:
		return out
	for key in g._groups:
		var l: int = (key & 1) if key >= 0 else ((-1 - key) & 1)
		if l == lod:
			out.append(g._groups[key])
	return out


func _fields(lots: bool) -> Array:
	var out := []
	for f: TreeField in TreeField.fields:
		if is_instance_valid(f) and (f.get_parent() is BuildingView) == lots:
			out.append(f)
	return out


## Turns off the sun shadows of these nodes and everything drawn under them
## (`off`), or gives back what each had. The buildings' card trees are left
## out of the buildings' own.
func _shadows(nodes: Array, off: bool) -> void:
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var all: Array = [n] + n.find_children("*", "GeometryInstance3D", true, false)
		for g in all:
			if not g is GeometryInstance3D or (n is BuildingView and _under_field(g)):
				continue
			if off:
				g.set_meta("rb_shadow", g.cast_shadow)
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif g.has_meta("rb_shadow"):
				g.cast_shadow = g.get_meta("rb_shadow")
				g.remove_meta("rb_shadow")


func _under_field(n: Node) -> bool:
	while n != null:
		if n is TreeField:
			return true
		n = n.get_parent()
	return false


func _show(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.visible = on


## The street view: down the middle of the town street nearest the
## street view's spot, from a little way back along it, at eye height.
func _street_aim(sim: CitySim) -> void:
	var want: Vector2 = VIEWS[0][1]
	var best := INF
	for id in sim.network.segments:
		if sim.network.segments[id].type != RoadStyle.Type.STREET:
			continue
		var pts := sim.network.sample_segment(id)
		var mid := pts[pts.size() / 2]
		var d := Vector2(mid.x, mid.z).distance_to(want)
		if d < best:
			best = d
			var dir := (pts[pts.size() - 1] - pts[0]).normalized()
			VIEWS[0][1] = Vector2(mid.x, mid.z) + Vector2(dir.x, dir.z) * 12.0
			VIEWS[0][2] = atan2(-dir.x, -dir.z)


func _aim(v: Array) -> void:
	_cam.look_at_point(Vector3(v[1].x, 0.0, v[1].y))
	_cam.set_view(v[2], deg_to_rad(v[3]), v[4])


func _trees() -> void:
	var all := 0
	var lots := 0
	for f: TreeField in TreeField.fields:
		var n := 0
		for key in f._trees:
			n += (f._trees[key] as Array).size()
		all += n
		if f.get_parent() is BuildingView:
			lots += n
	print("trees: %d from buildings, %d in all" % [lots, all])


## The game's own measured parts (Perf) that took longest in the timed frames.
static func _slowest() -> Dictionary:
	var keys := Perf.stats.keys().filter(func(k): return k.begins_with("frame.") and Perf.stats[k].n > 0)
	keys.sort_custom(func(a, b): return Perf.stats[a].max > Perf.stats[b].max)
	var out := {}
	for k in keys.slice(0, 6):
		out[k] = [snappedf(Perf.stats[k].sum / Perf.stats[k].n, 0.01), snappedf(Perf.stats[k].max, 0.1)]
	return out


static func _median(ms: Array) -> float:
	if ms.is_empty():
		return 0.0
	var s := ms.duplicate()
	s.sort()
	return s[s.size() / 2]


static func _summary(ms: Array) -> Dictionary:
	var s := ms.duplicate()
	s.sort()
	var slow := 0
	for m in s:
		if m > 33.4:
			slow += 1
	return {"median_ms": snappedf(s[s.size() / 2], 0.1), "p95_ms": snappedf(s[int(s.size() * 0.95)], 0.1),
		"worst_ms": snappedf(s[-1], 0.1), "over_33ms": slow}
