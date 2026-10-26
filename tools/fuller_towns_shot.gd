extends SceneTree
## A built-out test town (PerfTown) in mid-July, from the street, from
## 100 m and from 300 m up, to judge its yard and street trees and roofs:
## a young town (trees as planted) or a grown one (--years=N: every planted
## tree as if it went in N years earlier). Prints the trees in town and the
## draw calls and triangles of each view, to keep an eye on the web build.
## Run (a real window, not --headless; add --rendering-method
## gl_compatibility for the browser's renderer):
##   godot --resolution 1600x900 -s tools/fuller_towns_shot.gd -- OUT_DIR [--blocks=5] [--years=0]

## [name, point looked at (x, z), yaw, pitch, distance behind the point].
var VIEWS := [
	["street", Vector2(-280.0, -250.0), 0.0, 5.0, 36.0],
	["block_100m", Vector2(-280.0, -280.0), 0.6, 32.0, 190.0],
	["town_300m", Vector2(-150.0, -150.0), 0.6, 40.0, 470.0],
]

var _main: Node
var _frames := 0
var _cam: CityCamera
var _view := -1
var _view_frames := 0
var _out := "."
var _rows := []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=")[1]
	return fallback


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var args := OS.get_cmdline_user_args()
		_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else "."
		DirAccess.make_dir_recursive_absolute(_out)
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		Weather.on = false
		DayNight.cycle_on = false
		# Mid-July of the first year (a game day is a month of the seasons).
		sim.tick_count = int(fposmod(6.5 - Seasons.START_MONTH, 12.0) * Seasons.TICKS_PER_DAY)
		TreeField.extra_years = float(_arg("years", "0"))
		PerfTown.build(sim, _arg("blocks", "5"))
		# Built as the clock reads, so the yard trees are just planted.
		for key in sim.buildings:
			sim.buildings[key].built = sim.tick_count
		sim.buildings_changed.emit()
		_main.set_speed(0)
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
				_cam.ignore_floor = true
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		print("town: %d people, %d buildings" % [sim.stats.population, sim.buildings.size()])
		_street_aim(sim)
		return false
	if _cam == null:
		return false
	if _frames < 400:
		# The town draws in over a few hundred frames.
		_aim(VIEWS[0])
		return false
	if _view < 0:
		_trees()
		_next()
		return false
	_view_frames += 1
	if _view_frames > 90:
		var row: Dictionary = _rows[_view]
		row.calls = maxf(row.calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		row.prims = maxf(row.prims, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _view_frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join(VIEWS[_view][0] + ".png"))
		_next()
	return false


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


func _next() -> void:
	_view += 1
	_view_frames = 0
	if _view >= VIEWS.size():
		for r in _rows:
			print("view %-11s draw calls %5d  triangles %9d" % [r.name, r.calls, r.prims])
		print("renderer: ", RenderingServer.get_current_rendering_method())
		quit()
		return
	_rows.append({"name": VIEWS[_view][0], "calls": 0.0, "prims": 0.0})
	_aim(VIEWS[_view])


## Every tree in town: those the buildings planted (yard, street and shop
## trees), and all of them (with the woods and medians).
func _trees() -> void:
	var all := 0
	var lots := 0
	var street := -1
	for f: TreeField in TreeField.fields:
		var n := 0
		for key in f._trees:
			n += (f._trees[key] as Array).size()
		all += n
		if f.get_parent() is BuildingView:
			lots += n
	var bv: BuildingView = null
	for c in _main.get_children():
		if c is BuildingView:
			bv = c
	if bv != null and bv.get("street_trees") != null:
		street = bv.get("street_trees")
	print("trees: %d from buildings (%d of them street trees), %d in all" % [lots, street, all])
