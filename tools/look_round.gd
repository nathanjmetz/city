extends SceneTree
## The look round's fixed shot list (Nathan, 2026-10-29: "send out a critic
## to play the game, find a problem and report it ... lets make this game
## look totally real"). Every critic round runs this, so the before and
## after pictures show the same town from the same spots, at the same date,
## hour and weather.
##
## Opens the real game, clears it and builds the big test town (PerfTown
## "big": homes, shops, factories, services, parks, a farm past the edge),
## runs it a fixed number of ticks so there is traffic, then pauses it and
## hides the panels and lot badges. Then takes 10 pictures from fixed camera
## spots (SHOTS): street level, 40 m, 100 m, 300 m and 1 km on a fair
## mid-July morning; the 100 m view again at dusk, at night, in rain and in
## snow (mid-January); and a 300 m view over the fields at the town's edge.
## Before each picture it waits for the land, streets, buildings, trees,
## fields and farmsteads to finish drawing (the views the loading screen
## waits on), then times 60 frames.
##
## Run in a real window on the Mac (not --headless; the renderer is needed),
## with HOME set to a throwaway folder (the game autosaves to the user folder):
##   HOME=/tmp/x godot --resolution 1920x1080 -s tools/look_round.gd -- OUT_DIR [--quality=cinematic|medium]
## Default cinematic (the desktop look); medium stands in for the 8 GB Mac
## mini. --only=02,06 retakes just those shots (frames.json then lists only
## them). A screen too small for a 1920x1080 window (a 1080p monitor, once
## the menu bar and dock are taken off) gets the game full screen for the
## run, so every picture is 1920x1080; --windowed keeps the window and saves
## the pictures at its size instead (never stretched).
## Writes OUT_DIR/NN_name.jpg (1920x1080, quality 85) and OUT_DIR/frames.json:
## per shot frame_ms (the mean wall time of 60 frames: held to the screen's
## 16.7 ms at best, full screen on a Mac), draw_ms (60 frames drawn back to
## back without showing them: what the drawing costs, uncapped; the Mac gives
## no graphics-chip timer, so this stands in for it), render_cpu_ms, draw
## calls, triangles and video memory. The times move a few ms between runs
## when other programs share the Mac; draw calls and triangles don't.
## Never change a shot here between rounds without saying so in the round's
## notes: the point is that round N and round N+1 compare like with like.

## Fair-weather day: July 15, 10:30 in the morning.
const DAY := [7, 15, 10.5]
## Snow: January 15, 11:00, snow lying and falling.
const WINTER := [1, 15, 11.0]
## Night: 11 pm.
const NIGHT_HOUR := 23.0
## Dusk: the sun this many degrees under the horizon (just after sunset,
## the sky still coloured, the street lights coming on).
const DUSK_SUN := -2.0
## Weather, [cloud cover, rain or snow, fog, 1 if snow] (Weather.live).
const FAIR := [0.1, 0.0, 0.0, 0.0]
const RAIN := [0.95, 0.85, 0.0, 0.0]
const SNOW := [0.95, 0.75, 0.0, 1.0]

## Spots on the map (metres; PerfTown "big" spans -840..840 both ways, the
## middle avenues are shops, homes in the quarters, factories on the east).
## The 100 m view: the shops on the middle avenue with homes behind them,
## tilted low enough to show the sky (dusk, rain and snow show there too).
const MID := Vector3(-210.0, 0.0, -40.0)
const MID_PITCH := 22.0
## [file name, aim point, yaw deg, pitch deg, distance m, when, weather].
## 01 aims down the residential street nearest its point instead (_street_aim),
## 02 at the front of the shop nearest its point (_shop_aim).
## Shot in this order (snow last: January redraws every field and tree).
var SHOTS := [
	["01_street", Vector3(-280.0, 0.0, -250.0), 0.0, 10.0, 40.0, "day", FAIR],
	["02_40m", Vector3(-260.0, 0.0, -60.0), 0.0, 25.0, 40.0, "day", FAIR],
	["03_100m", MID, 35.0, MID_PITCH, 100.0, "day", FAIR],
	["04_300m", Vector3(-150.0, 0.0, -150.0), 35.0, 40.0, 300.0, "day", FAIR],
	["05_1km", Vector3(0.0, 0.0, 0.0), 35.0, 45.0, 1000.0, "day", FAIR],
	["06_dusk_100m", MID, 35.0, MID_PITCH, 100.0, "dusk", FAIR],
	["07_night_100m", MID, 35.0, MID_PITCH, 100.0, "night", FAIR],
	["08_rain_100m", MID, 35.0, MID_PITCH, 100.0, "day", RAIN],
	["10_farm_edge_300m", Vector3(1400.0, 0.0, -900.0), 80.0, 25.0, 300.0, "day", FAIR],
	["09_snow_100m", MID, 35.0, MID_PITCH, 100.0, "winter", SNOW],
]
## Sim ticks run before the pictures (a sim minute each), so cars and
## walkers are out; always the same number, so the town is the same.
const WARM_TICKS := 150
## Frames to wait after a move before checking the views, the calm frames
## in a row everything must read drawn, the most frames to wait, and the
## frames timed.
const MIN_WAIT := 90
const CALM := 20
const MAX_WAIT := 2400
const TIMED := 60
const SAVE := "user://look_round.city"

var _main: Node
var _cam: CityCamera
var _weather: Weather
var _out := "."
var _stage := 0
var _shot := -1
var _wait := 0
var _calm := 0
var _timed := 0
var _last_us := 0
var _row := {}
var _rows := []
var _dusk_hour := 21.0


func _initialize() -> void:
	pass  # the game opens on the first frame, once the autoloads are up


func _finalize() -> void:
	for f in [SAVE, SAVE.get_basename() + ".json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _process(_delta: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else "."
		DirAccess.make_dir_recursive_absolute(_out)
		var win := DisplayServer.window_get_size()
		if (win.x < 1920 or win.y < 1080) and not "--windowed" in args:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# A throwaway save, so the test town never lands on a real town.
		root.get_node("/root/Session").save_path = SAVE
		_pin_quality()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _main.loading:
		return false
	if _stage == 0:
		_build()
		_stage = 1
		return false
	if _stage == 1:
		# The whole town drawn in once, from the first spot.
		_wait += 1
		if _wait < 300 or (not _drawn() and _wait < MAX_WAIT * 2):
			return false
		_stage = 2
		_next()
		return false
	if _stage == 2:
		_wait += 1
		_calm = _calm + 1 if _drawn() else 0
		if _wait < MIN_WAIT or (_calm < CALM and _wait < MAX_WAIT):
			return false
		if _calm < CALM:
			_row.not_drawn = _main._gate.missing()
			print("look_round: %s still drawing after %d frames: %s" % [_row.name, _wait, _row.not_drawn])
		_row.wait_frames = _wait
		_stage = 3
		_timed = 0
		_last_us = 0
		return false
	if _stage == 3:
		var now := Time.get_ticks_usec()
		var vp := root.get_viewport_rid()
		if _last_us > 0:
			_timed += 1
			_row.frame_ms += (now - _last_us) / 1000.0 / TIMED
			_row.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp) / TIMED
			_row.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) / TIMED
			_row.triangles += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / TIMED
		_last_us = now
		if _timed >= TIMED:
			_save_shot()
			_time_draws()
			_next()
	return false


## Pins the tier for the run (cinematic unless --quality says otherwise),
## without writing the saved setting.
func _pin_quality() -> void:
	var q := GraphicsQuality.current
	if q == null or GraphicsQuality._cmdline_tier() >= GraphicsQuality.LOW:
		return  # --quality=X: the autoload pinned it already
	q._pinned = true
	q.mode = GraphicsQuality.CINEMATIC
	q.tier = GraphicsQuality.CINEMATIC
	q.scale = 1.0
	q.apply()


func _build() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	PerfTown.build(sim, "big")
	sim.require_utilities = false
	for i in WARM_TICKS:
		sim.tick()
	_main.set_speed(0)
	for n in _main.find_children("*", "FirstTownTour", true, false):
		n.stop()
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Weather:
			_weather = c
		# The picture is of the town: no panels, tour or status icons.
		if c is CanvasLayer or c is LotAlerts:
			c.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Weather.on = true
	DayNight.cycle_on = true
	DayNight.seasons_on = true
	_dusk_hour = _dusk(DAY[0], DAY[1])
	_street_aim(sim)
	_shop_aim(sim)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			var only := a.trim_prefix("--only=").split(",")
			SHOTS = SHOTS.filter(func(s): return s[0].left(2) in only)
	print("look_round: %d buildings, %d people, %d farms, %d cars, %d walkers, %s, dusk at %.2f" % [sim.buildings.size(),
		sim.stats.population, sim.farms.farms.size(), sim.traffic.cars.size(), sim.traffic.walkers.size(),
		GraphicsQuality.current.describe() if GraphicsQuality.current else "?", _dusk_hour])
	_set_shot(SHOTS[0])


## Every view the loading screen waits on has drawn what the camera sees,
## the buildings are merged and faded in, and the crops have caught up.
func _drawn() -> bool:
	if not _main._gate.missing().is_empty() or CropCalendar.busy():
		return false
	for c in _main.get_children():
		if c is BuildingView and not c.idle():
			return false
	return true


func _next() -> void:
	_shot += 1
	_wait = 0
	_calm = 0
	if _shot >= SHOTS.size():
		_finish()
		return
	var s: Array = SHOTS[_shot]
	_row = {"name": s[0], "frame_ms": 0.0, "render_cpu_ms": 0.0, "draw_calls": 0.0,
		"triangles": 0.0, "when": s[5], "weather": s[6]}
	_set_shot(s)
	_stage = 2


func _set_shot(s: Array) -> void:
	_cam.look_at_point(s[1])
	_cam.set_view(deg_to_rad(s[2]), deg_to_rad(s[3]), s[4])
	match s[5]:
		"day": _set_moment(DAY[0], DAY[1], DAY[2])
		"dusk": _set_moment(DAY[0], DAY[1], _dusk_hour)
		"night": _set_moment(DAY[0], DAY[1], NIGHT_HOUR)
		"winter": _set_moment(WINTER[0], WINTER[1], WINTER[2])
	# The weather asked for, at once (it eases in over seconds otherwise).
	_weather.live = s[6]
	_weather.cover = s[6][0]
	_weather.rain = 0.0 if s[6][3] > 0.5 else s[6][1]
	_weather.snow = s[6][1] if s[6][3] > 0.5 else 0.0
	_weather.fog = s[6][2]


## The town's calendar on that day, with the light pinned to that day and
## hour (as tools/daylight_shot.gd does).
func _set_moment(month: int, day: int, hour: float) -> void:
	var date: float = float(month - 1) + float(day - 1) / Seasons.DAYS_IN[month - 1]
	_main.sim.set_calendar(Seasons.tick_at(12.0 + date))
	for n in _main.find_children("*", "DayNight", true, false):
		n.set("date_override", date)
		n.set("hour_override", hour)


## The evening hour the sun is DUSK_SUN degrees under the horizon.
func _dusk(month: int, day: int) -> float:
	var date: float = float(month - 1) + float(day - 1) / Seasons.DAYS_IN[month - 1]
	var h := 17.0
	while h < 23.5 and SkyLight.sun_position(h, date).x > DUSK_SUN:
		h += 1.0 / 60.0
	return h


## The street view: down the middle of the town street nearest its spot,
## from a little way back along it.
func _street_aim(sim: CitySim) -> void:
	var want: Vector3 = SHOTS[0][1]
	var best := INF
	for id in sim.network.segments:
		if sim.network.segments[id].type != RoadStyle.Type.STREET:
			continue
		var pts := sim.network.sample_segment(id)
		var mid := pts[pts.size() / 2]
		var d := Vector2(mid.x, mid.z).distance_to(Vector2(want.x, want.z))
		if d < best:
			best = d
			var dir := (pts[pts.size() - 1] - pts[0]).normalized()
			SHOTS[0][1] = Vector3(mid.x, 0.0, mid.z) + Vector3(dir.x, 0.0, dir.z) * 20.0
			SHOTS[0][2] = rad_to_deg(atan2(-dir.x, -dir.z))


## The 40 m view: the shop nearest its spot, from the street in front of
## it and a little to one side.
func _shop_aim(sim: CitySim) -> void:
	var want: Vector3 = SHOTS[1][1]
	var best := INF
	for key in sim.buildings:
		if sim.buildings[key].zone != ZoneMap.Zone.COMMERCIAL or not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		var front: Vector3 = lot.front
		var d := Vector2(front.x, front.z).distance_to(Vector2(want.x, want.z))
		if d < best:
			best = d
			var n: Vector3 = lot.normal
			SHOTS[1][1] = front + n * 8.0
			SHOTS[1][2] = rad_to_deg(atan2(-n.x, -n.z)) + 30.0


func _save_shot() -> void:
	var img := root.get_texture().get_image()
	_row.picture_size = [img.get_width(), img.get_height()]
	if img.get_width() != 1920 or img.get_height() != 1080:
		print("look_round: %s is %dx%d, not 1920x1080" % [_row.name, img.get_width(), img.get_height()])
	img.save_jpg(_out.path_join(_row.name + ".jpg"), 0.85)
	_row.video_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	for k in ["frame_ms", "render_cpu_ms", "video_mb"]:
		_row[k] = snappedf(_row[k], 0.01)
	_row.draw_calls = roundi(_row.draw_calls)
	_row.triangles = roundi(_row.triangles)
	var cam := _cam.camera.global_position
	_row.camera = [snappedf(cam.x, 0.1), snappedf(cam.y, 0.1), snappedf(cam.z, 0.1)]
	_rows.append(_row)
	print("look_round: %s  %.1f ms  %d calls  %d tris  %.0f MB" % [_row.name, _row.frame_ms, _row.draw_calls,
		_row.triangles, _row.video_mb])


## What drawing the view costs, the screen's 60 Hz taken out: TIMED frames
## drawn back to back without showing them, so the time is the graphics
## chip's (or the drawing's on the processor, whichever is slower). The game's
## own per-frame work is not in it (the town is paused).
func _time_draws() -> void:
	for i in 5:
		RenderingServer.force_draw(false)
	var t := Time.get_ticks_usec()
	for i in TIMED:
		RenderingServer.force_draw(false)
	_rows[-1].draw_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0 / TIMED, 0.01)
	print("look_round: %s  draw %.1f ms" % [_rows[-1].name, _rows[-1].draw_ms])


func _finish() -> void:
	_rows.sort_custom(func(a, b): return a.name < b.name)
	var q := GraphicsQuality.current
	var report := {"tier": GraphicsQuality.NAMES[q.tier] if q else "?", "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": [root.size.x, root.size.y],
		"town": "PerfTown big", "warm_ticks": WARM_TICKS, "buildings": _main.sim.buildings.size(),
		"day": DAY, "dusk_hour": snappedf(_dusk_hour, 0.01), "night_hour": NIGHT_HOUR, "winter": WINTER,
		"date": Time.get_date_string_from_system(), "shots": _rows}
	var f := FileAccess.open(_out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("look_round: wrote ", _out.path_join("frames.json"))
	quit()
