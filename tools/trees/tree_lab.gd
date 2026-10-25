extends SceneTree
## What the trees cost in a big town, close up: the real game with a big
## grid town (PerfTown, N blocks; "20" is about 16,000 people), its yard
## trees aged as if planted 30 years ago (TreeField.extra_years, a lab
## knob: a new town's trees are saplings), timed with the camera at street
## level, then sweeping across town at 60 m.
## Run in a window:
##   godot --resolution 1600x900 -s tools/trees/tree_lab.gd -- SAVE BLOCKS OUT_DIR TAG MODE
## MODE: "grown" (the grown trees on) or "cards" (off: the cheap trees
## everywhere, as before). SAVE is a throwaway save path, never a real town.
## Runs on older versions too (without the grown trees), for a before number.
var _main: Node
var _frames := 0
var _ms := []
var _res := {}
var _cam: CityCamera
var _span := 0.0
const SETTLE := 900
const TIME := 600
const AB_WINDOW := 450
const AB_TURNS := 6
var _ab := {"on": [], "off": []}


func _process(d: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
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
		sim.apply({"type": "clear"})
		PerfTown.build(sim, a[1])
		sim.require_utilities = false
		for i in 3000:
			sim.tick()
		_span = int(a[1]) * 140.0
		var tf: Script = load("res://scripts/art/tree_field.gd")
		if tf.get("extra_years") != null:
			tf.set("extra_years", 30.0)
		if ResourceLoader.exists("res://scripts/art/trees/grown_trees.gd"):
			load("res://scripts/art/trees/grown_trees.gd").set("enabled", a[4] == "grown")
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer:
				c.visible = false
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		_main.set_speed(1)
		print("TREELAB built %d people, %d buildings" % [sim.stats.population, sim.buildings.size()])
		_street()
		return false
	if _frames == SETTLE:
		Perf.reset()
	if _frames > SETTLE and _frames <= SETTLE + TIME:
		_ms.append(d * 1000.0)
	if _frames == SETTLE + TIME:
		_report("street")
		root.get_viewport().get_texture().get_image().save_png("%s/treelab_%s_street.png" % [a[2], a[3]])
	# The sweep: across the residential corner of town at 60 m.
	if _frames > SETTLE + TIME and _frames <= SETTLE + TIME * 2:
		var t := float(_frames - SETTLE - TIME) / TIME
		_cam.look_at_point(Terrain.lift(Vector3(lerpf(-_span * 0.45, _span * 0.45, t), 0, -_span * 0.4)))
		_cam.set_view(deg_to_rad(200.0), deg_to_rad(22.0), 60.0)
		_ms.append(d * 1000.0)
	if _frames == SETTLE + TIME * 2:
		_report("sweep")
		_street()
	# Same place, same moment: the grown trees on and off in turns, so the
	# town's own frame-to-frame swings even out.
	var ab := _frames - SETTLE - TIME * 2
	if ab > 0 and ResourceLoader.exists("res://scripts/art/trees/grown_trees.gd"):
		var gt: Script = load("res://scripts/art/trees/grown_trees.gd")
		var turn := (ab - 1) / AB_WINDOW
		if turn < AB_TURNS:
			var on := turn % 2 == 0
			gt.set("enabled", on)
			if (ab - 1) % AB_WINDOW >= AB_WINDOW / 3:
				_ab["on" if on else "off"].append(d * 1000.0)
			if (ab - 1) % AB_WINDOW == AB_WINDOW - 1 and on:
				for n in _main.find_children("*", "GrownTrees", true, false):
					_res["street_grown"] = n.stats()
			return false
		for k in _ab:
			var arr: Array = _ab[k]
			arr.sort()
			var s := 0.0
			for m in arr:
				s += m
			_res["street_ab_" + k] = {"frame_avg_ms": snappedf(s / arr.size(), 0.01), "frame_p95_ms": snappedf(arr[int(arr.size() * 0.95)], 0.1)}
	if ab > 0:
		_res["population"] = sim.stats.population
		_res["mem_mb"] = OS.get_static_memory_usage() / 1048576
		_res["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576
		for n in _main.find_children("*", "GrownTrees", true, false):
			_res["grown"] = n.stats()
		print("TREELAB %s %s" % [a[3], JSON.stringify(_res)])
		quit()
		return true
	return false


func _street() -> void:
	_cam.look_at_point(Terrain.lift(Vector3(-_span * 0.35, 0, -_span * 0.35)))
	_cam.set_view(deg_to_rad(225.0), deg_to_rad(20.0), 80.0)


func _report(key: String) -> void:
	_ms.sort()
	var sum := 0.0
	var slow := 0
	for m in _ms:
		sum += m
		if m > 50.0:
			slow += 1
	var parts := {}
	for k in Perf.stats:
		parts[k] = snappedf(float(Perf.stats[k].sum) / TIME, 0.01)
	var ks := parts.keys()
	ks.sort_custom(func(x, y): return parts[x] > parts[y])
	var top := {}
	for k in ks.slice(0, 8):
		top[k] = parts[k]
	_res[key] = {"frame_avg_ms": snappedf(sum / _ms.size(), 0.1), "frame_p95_ms": snappedf(_ms[int(_ms.size() * 0.95)], 0.1),
		"frame_worst_ms": snappedf(_ms[-1], 0.1), "over_50ms": slow, "per_frame_ms": top}
	_ms.clear()
	Perf.reset()
