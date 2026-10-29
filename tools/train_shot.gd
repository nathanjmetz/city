extends "res://tools/screenshot.gd"
## The trains critic's views: a through freight on the county's real rail
## nearest the farm demo (screenshot.gd "farms"), stopped where its engines
## and then its cars pass the camera, saved as OUT_DIR/<view>.png.
## Run: xvfb-run godot --resolution 1600x900 -s tools/train_shot.gd -- OUT_DIR 0 0 0 farms [view ...] --quality=ultra
## Env: LOOK_MONTH (default 7), LOOK_HOUR (default 11), TRAIN_KIND (grain, tank, manifest or stone; any by default),
## TRAIN_OFF=1 (the same views with the trains hidden: a before shot), SHOT_PREFIX and SHOT_SUFFIX (around each file name).

## [name, metres behind the lead engine to aim at, yaw off the track, pitch, distance]
const VIEWS := [
	["engines_close", 20.0, 70.0, 14.0, 55.0],
	["engines_low", 15.0, 35.0, 6.0, 35.0],
	["cars_close", 120.0, 100.0, 16.0, 70.0],
	["train_mid", 200.0, 80.0, 28.0, 320.0],
	["train_far", 400.0, 60.0, 35.0, 900.0],
]

var _view := -1
var _view_frames := 0
var _cam: CityCamera
var _views: Array = []
var _train := {}


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		DayNight.cycle_on = false
		var month := float(OS.get_environment("LOOK_MONTH")) if OS.get_environment("LOOK_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("LOOK_HOUR")) if OS.get_environment("LOOK_HOUR") != "" else 11.0
		_demo_town()
		var sim: CitySim = _main.sim
		_find_train(sim)
		sim.set_calendar(Seasons.tick_at(SkyClock.at(int(month), hour)))
		_main.speed = 0
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is Hud:
				c.close_all()
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
			if c is CountyTrainView and OS.get_environment("TRAIN_OFF") != "":
				c.queue_free()
		var args := OS.get_cmdline_user_args()
		var only := Array(args.slice(5)).filter(func(a): return not a.begins_with("--"))
		for v in VIEWS:
			if only.is_empty() or v[0] in only:
				_views.append(v)
		return false
	if _frames < 150:
		return false
	if _view < 0:
		_next()
		return false
	_view_frames += 1
	if _view_frames == 30:
		var out: String = OS.get_cmdline_user_args()[0].path_join(OS.get_environment("SHOT_PREFIX") + _views[_view][0] + OS.get_environment("SHOT_SUFFIX") + ".png")
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		_next()
	return false


## The tick a train has its lead engine 150 m past the point of the county's
## open track nearest the demo, and sets the sim's clock to it.
func _find_train(sim: CitySim) -> void:
	var o := Terrain.view_origin
	var best := INF
	var at := [0, 0.0]
	var cs := CountyTrains.corridors()
	for ci in cs.size():
		var c: Dictionary = cs[ci]
		var s := 600.0
		while s < float(c.length) - 600.0:
			var p := CountyTrains._at(c, s)
			var d := (p - o).length()
			var n := CountyRail.near(p.x, p.y, 8.0)
			if d < best and d > 1200.0 and not n.is_empty() and CountyRail.kind_at(n.route, n.along) == 0:
				best = d
				at = [ci, s]
			s += 50.0
	var want := OS.get_environment("TRAIN_KIND")
	for t in range(0, 600000, 10):
		for tr in CountyTrains.trains_at(t, CountyTrains.SEED):
			if tr.corridor != at[0] or (want != "" and tr.kind != want):
				continue
			var past: float = (float(tr.s) - float(at[1])) * float(tr.dir)
			if past > 150.0 and past < 152.0:
				sim.tick_count = t
				_train = tr
				print("train ", tr.kind, " ", tr.consist.size(), " cars at tick ", t, " corridor ", at[0], " s ", at[1])
				return
	push_error("no train found")


func _next() -> void:
	_view += 1
	_view_frames = 0
	if _view >= _views.size():
		quit()
		return
	var v: Array = _views[_view]
	var s: float = float(_train.s) - float(_train.dir) * float(v[1])
	var pose := CountyTrains.pose(_train.corridor, s)
	var p: Vector2 = pose[0] - Terrain.view_origin
	var heading := atan2(pose[1].x, pose[1].y)
	_cam.look_at_point(Vector3(p.x, 0, p.y))
	_cam.set_view(heading + deg_to_rad(v[2]), deg_to_rad(v[3]), v[4])
