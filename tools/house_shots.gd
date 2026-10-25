extends SceneTree
## Houses at 40, 100 and 300 m: opens the real game with the test town
## (PerfTown), finds a street of houses, and from each distance saves a
## picture and times the frames (the sim paused, so the times are the
## drawing's), then dives from 2 km to 40 m and sweeps along the street at
## 40 m, counting frames over 50 ms. Ends with graphics and static memory.
## For before-and-after pictures and numbers of a drawing change (run the
## same command on main and on the branch).
## Run in a real window, the tier pinned:
##   godot --resolution 1600x900 [--rendering-method gl_compatibility] --quality high
##     -s tools/house_shots.gd -- SAVE OUT_DIR [blocks]
## SAVE is a throwaway save path: never a real town (it is cleared).

const VIEWS := [["house40", 40.0, 24.0], ["house100", 100.0, 30.0], ["house300", 300.0, 38.0]]
const AIM := Vector3(-430.0, 0.0, -330.0)

var _main: Node
var _frames := 0
var _cam: CityCamera
var _out := ""
var _view := -1
var _vf := 0
var _ms := []
var _res := {}
var _yaw := 0.0
var _home := Vector3.ZERO
var _along := Vector3.RIGHT
var _phase := "wait"
var _t := 0.0
var _last_us := 0


func _process(d: float) -> bool:
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
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		PerfTown.build(sim, a[2] if a.size() > 2 else "big")
		sim.require_utilities = false
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_main.set_speed(0)
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		# The house nearest the aim, seen from its street, a little to one side.
		var best := INF
		for key in sim.buildings:
			if BuildingTypes.type_of(sim.buildings[key]) != "house" or not sim.lots.has(key):
				continue
			var p: Vector3 = sim.lots[key].pos
			var dd := Vector2(p.x - AIM.x, p.z - AIM.z).length()
			if dd < best:
				best = dd
				_home = p
				var to_street: Vector3 = (sim.lots[key].front - p)
				_yaw = atan2(to_street.x, to_street.z) + deg_to_rad(28.0)
				_along = Vector3(-to_street.z, 0, to_street.x).normalized()
		_cam.look_at_point(_home)
		_cam.set_view(_yaw, deg_to_rad(40.0), 300.0)
		return false
	if _frames < 40:
		return false
	if _phase == "wait":
		# Every building drawn and merged before the first picture.
		for c in _main.get_children():
			if not c is BuildingView:
				continue
			if c.has_method("idle"):
				if not c.idle():
					return false
			elif not c._pending.is_empty() or not c._bake_due.is_empty() or c._filling:
				return false
		_phase = "views"
		_find_brick()
		_next_view()
		return false
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	match _phase:
		"views":
			_vf += 1
			if _vf > 60 and _vf <= 240:
				_ms.append(ms)
			if _vf == 250:
				var v: Array = _views[_view]
				_res[v[0]] = _summary(_ms)
				_res[v[0]].draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				_res[v[0]].primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				root.get_texture().get_image().save_png(_out.path_join(v[0] + ".png"))
				_next_view()
		"dive":
			if _t == 0.0:
				Perf.reset_window()
			_t += d
			_ms.append(ms)
			var k := clampf(_t / 8.0, 0.0, 1.0)
			_cam.look_at_point(_home)
			_cam.set_view(_yaw, deg_to_rad(lerpf(55.0, 24.0, k)), exp(lerpf(log(2000.0), log(40.0), k)))
			if _t > 9.0:
				_res.dive = _summary(_ms)
				_res.dive.parts = _parts()
				_ms.clear()
				_t = 0.0
				_phase = "sweep"
		"sweep":
			_t += d
			_ms.append(ms)
			# Along the street and back, at a brisk 30 m/s.
			var s := pingpong(_t * 30.0, 300.0) - 150.0
			_cam.look_at_point(_home + _along * s)
			_cam.set_view(_yaw, deg_to_rad(24.0), 40.0)
			if _t > 20.0:
				_res.sweep = _summary(_ms)
				_res.sweep.parts = _parts()
				_res.video_mb = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 1)
				_res.static_mb = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 1)
				_res.buildings = sim.buildings.size()
				_res.renderer = RenderingServer.get_current_rendering_method()
				_res.quality = GraphicsQuality.current.describe() if GraphicsQuality.current else ""
				print("HOUSESHOTS ", JSON.stringify(_res))
				FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(_res, "  "))
				quit()
	return false


func _next_view() -> void:
	_view += 1
	_vf = 0
	_ms.clear()
	if _view >= _views.size():
		_phase = "dive"
		_t = 0.0
		return
	var v: Array = _views[_view]
	_cam.look_at_point(v[3] if v.size() > 3 else _home)
	_cam.set_view(v[4] if v.size() > 4 else _yaw, deg_to_rad(v[2]), v[1])


var _views := VIEWS.duplicate()


## A brick house near the aim, for one more close picture (the same lot on
## main and the branch: the nearest house with a brick front or body, by
## its builder's own drawing).
func _find_brick() -> void:
	var sim: CitySim = _main.sim
	var keys := []
	for key in sim.buildings:
		if BuildingTypes.type_of(sim.buildings[key]) == "house" and sim.lots.has(key):
			var p: Vector3 = sim.lots[key].pos
			keys.append([Vector2(p.x - AIM.x, p.z - AIM.z).length(), key])
	keys.sort()
	for e in keys.slice(0, 80):
		var key: String = e[1]
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key]
		var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), lot.front)
		var rng := RandomNumberGenerator.new()
		rng.seed = b.seed
		var fit := BuildingView._local_lot(lot, xf)
		var built := HouseBuilder.build(rng.randi(), lot.to_curb, fit, BuildingTypes.storeys(b))
		var mesh: ArrayMesh = built[0]
		var area := 0.0
		for i in mesh.get_surface_count():
			if mesh.surface_get_material(i) != HouseMaterials.get_mat("brick"):
				continue
			var arr := mesh.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n: int = (idx.size() if idx != null else v.size()) / 3
			for t in n:
				var a: Vector3 = v[idx[t * 3] if idx != null else t * 3]
				var c: Vector3 = v[idx[t * 3 + 1] if idx != null else t * 3 + 1]
				var d: Vector3 = v[idx[t * 3 + 2] if idx != null else t * 3 + 2]
				area += (c - a).cross(d - a).length() * 0.5
		if area > 25.0:
			var to_street: Vector3 = lot.front - lot.pos
			_views.append(["brick40", 40.0, 18.0, lot.pos, atan2(to_street.x, to_street.z) + deg_to_rad(20.0)])
			return


## Mean ms of the buildings' measured parts since the last call.
static func _parts() -> Dictionary:
	var out := {}
	for k in ["frame.buildings", "frame.buildings_merge", "frame.buildings_near"]:
		var s: Dictionary = Perf.stats.get(k, {})
		if not s.is_empty() and s.n > 0:
			out[k] = {"mean_ms": snappedf(s.sum / s.n, 0.01), "max_ms": snappedf(s.max, 0.1)}
	Perf.reset_window()
	return out


static func _summary(ms: Array) -> Dictionary:
	if ms.is_empty():
		return {}
	var s := ms.duplicate()
	s.sort()
	var tot := 0.0
	var over := 0
	for m in s:
		tot += m
		if m > 50.0:
			over += 1
	return {"avg_ms": snappedf(tot / s.size(), 0.1), "p95_ms": snappedf(s[int(s.size() * 0.95)], 0.1),
		"worst_ms": snappedf(s[-1], 0.1), "over_50ms": over, "frames": s.size()}
