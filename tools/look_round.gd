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
## hides the panels and lot badges. Before each picture the sim is run
## through the day to that picture's hour (from sunrise: WARM below), so
## commuters are at work, shoppers at the shops and cars in the lots. Then takes 10 pictures from fixed camera
## spots (SHOTS): street level, 40 m, 100 m, 300 m and 1 km on a fair
## mid-July morning; the 100 m view again at dusk, at night, in rain and in
## snow (mid-January); and a 300 m view over the fields at the town's edge.
## Before each picture it waits for the land, streets, buildings, trees,
## fields and farmsteads to finish drawing (the views the loading screen
## waits on), then times 60 frames.
##
## Run in a real window on the Mac (not --headless; the renderer is needed),
## with HOME set to a throwaway folder (the game autosaves to the user folder,
## and closing the guided tour marks it done there). It refuses to start
## (exit code 1) when the user folder is not under a temp or scratch folder,
## before any of the game's own code runs:
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
## --dry does the warm-ups with no drawing and prints, per shot, the cars
## parked at shops, factories and homes (run it with --headless: it opens no
## window). --legacy-warm does the old warm-up (150 ticks, then the clock
## jumps to the hour) for a before-and-after count.
## Never change a shot here between rounds without saying so in the round's
## notes: the point is that round N and round N+1 compare like with like.
##
## 11_docks_60m (added 2026-10-29 with working doors step 2, docs/spec-
## working-doors.md): 60 m over the docks of a regional warehouse on the
## big town's east edge, across the street from the factory row, July 15,
## 10:30, with trucks backed up to its open dock doors. The big test town
## has no warehouse, so this shot adds one (DOCK_WH), only when its turn
## comes: it is taken last, after 09, so shots 01 to 10 see the very same
## town as before. The test town's factories ship no goods to a warehouse
## in a morning (their raw loads come from the county road first), so
## through shot 11's warm-up (its day starts LEAD hours early) the nearest
## factories send it a load every DOCK_EVERY ticks, on Logistics' books as
## any load is, a box truck and a 53 ft trailer in turn. After the jump from
## January the town's 400-car limit holds its morning rush (and so every
## truck) for the whole warm-up, so the limit is lifted fourfold through it,
## as the start of a day's HOME_TICKS lifts it, and put back for the picture.

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
## Shot in this order: by the hour of the day, so the sim runs forward through
## one day and the warm-ups add up (the day's views and the rain, then dusk
## and night), snow last: January redraws every field and tree.
var SHOTS := [
	["01_street", Vector3(-280.0, 0.0, -250.0), 0.0, 10.0, 40.0, "day", FAIR],
	["02_40m", Vector3(-260.0, 0.0, -60.0), 0.0, 25.0, 40.0, "day", FAIR],
	["03_100m", MID, 35.0, MID_PITCH, 100.0, "day", FAIR],
	["04_300m", Vector3(-150.0, 0.0, -150.0), 35.0, 40.0, 300.0, "day", FAIR],
	["05_1km", Vector3(0.0, 0.0, 0.0), 35.0, 45.0, 1000.0, "day", FAIR],
	["08_rain_100m", MID, 35.0, MID_PITCH, 100.0, "day", RAIN],
	["10_farm_edge_300m", Vector3(1400.0, 0.0, -900.0), 80.0, 25.0, 300.0, "day", FAIR],
	["06_dusk_100m", MID, 35.0, MID_PITCH, 100.0, "dusk", FAIR],
	["07_night_100m", MID, 35.0, MID_PITCH, 100.0, "night", FAIR],
	["09_snow_100m", MID, 35.0, MID_PITCH, 100.0, "winter", SNOW],
	# Aimed at the warehouse's truck court once it is placed (_dock_aim).
	["11_docks_60m", DOCK_WH[1], 0.0, 35.0, 60.0, "day", FAIR],
]
## Shot 11's warehouse: [kind, where to look for a site beside the east
## edge's street (Warehouses.site_near), more places to try if that one
## is taken].
const DOCK_WH := ["large", Vector3(880.0, 0.0, 70.0), [Vector3(880.0, 0.0, -70.0),
	Vector3(880.0, 0.0, 210.0), Vector3(880.0, 0.0, -210.0)]]
## Ticks between the loads the factories send shot 11's warehouse (30 s of
## play: oftener, its trucks queue to pull out onto its short street), and
## how many of the nearest factories take turns sending them.
const DOCK_EVERY := 300
const DOCK_FROM := 6
## Sim ticks run right after the town is built (a sim minute each), so cars
## and walkers are out; always the same number, so the town is the same.
const WARM_TICKS := 150
## The sky hour and the day of the month are one clock (a month is a sky
## day), so a shot's month and hour fix the calendar; the sim is run from
## the start of its day to the shot's hour. Same town, same seed, same
## ticks: the same result every run.
const WARM_CAP := 80000
## The first day runs from sunrise (the daytime shots: the whole morning
## commute and the shops filling). Any later day (the evening, January) would
## cost as much again, so it starts this many sky hours before its shot, with
## everyone sent home and the people whose shift covers that hour put at
## work (People.settle, the game's own jump-the-clock helper).
const LEAD := 2.0
## Ticks, at the start of such a day, the walker and car limits are lifted
## so everyone still out can get home (the game's limits, 800 walkers and
## 400 cars, hold a big town's whole evening rush up for hours).
const HOME_TICKS := 600
## Milliseconds of ticking per frame while a window is open (the rest is the
## frame), so the window keeps answering.
const WARM_MS := 30
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
var _refused := false
var _dry := false
var _legacy := false
var _month := 0       # the month the sim's day is running in (0: none yet)
var _target := 0.0    # the sky hour the sim is being run to
var _home_left := 0   # ticks of lifted limits to go (HOME_TICKS)
var _caps := Vector2i.ZERO  # the car and walker limits to put back
var _ticks := 0       # sim ticks run for the warm-ups so far
var _dock_wh := -1    # shot 11's warehouse, once placed
var _dock_from := []  # the factories that send it loads (lot keys)
var _dock_sent := 0   # loads sent to it so far
var _dock_cap := 0    # the town's car limit, lifted through shot 11's warm-up


func _initialize() -> void:
	# The game opens on the first frame, once the autoloads are up. Here they
	# are added but not yet ready (nothing of theirs has run), so a refusal
	# takes them out before they can write to a real player's folder.
	if not _throwaway_home():
		printerr("look_round: refusing to run: the user folder is %s, a real player's folder. " % OS.get_user_data_dir()
			+ "Set HOME to a scratch folder, e.g. HOME=/tmp/look_round_home godot ... -s tools/look_round.gd -- OUT_DIR")
		_refused = true
		for c in root.get_children():
			root.remove_child(c)
			c.free()
		quit(1)
		return
	if "--dry" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		printerr("look_round: --dry opens no picture, so run it with --headless (no window should open).")
		_refused = true
		quit(1)


## True when the user folder sits under a temp or scratch folder (HOME set
## to a throwaway one), never a real player's.
func _throwaway_home() -> bool:
	var dir := OS.get_user_data_dir().replace("\\", "/")
	var temp := OS.get_temp_dir().replace("\\", "/")
	for p in ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]:
		if dir.begins_with(p):
			return true
	return (temp != "" and dir.begins_with(temp)) or "/scratchpad/" in dir or "/scratch/" in dir


func _finalize() -> void:
	if _refused:
		return
	# The quality setting's crash marker: the tier was pinned after the
	# autoload had started, so it is never cleared on its own.
	for f in [SAVE, SAVE.get_basename() + ".json", GraphicsQuality.RUNNING_PATH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _process(_delta: float) -> bool:
	if _refused:
		return true
	if _main == null:
		var args := OS.get_cmdline_user_args()
		_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else "."
		DirAccess.make_dir_recursive_absolute(_out)
		_dry = "--dry" in args
		_legacy = "--legacy-warm" in args
		var win := DisplayServer.window_get_size()
		if not _dry and (win.x < 1920 or win.y < 1080) and not "--windowed" in args:
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
		if _dry:
			_dry_run()
			return true
		_stage = 1
		return false
	if _stage == 4:
		if _warm(WARM_MS):
			_wait = 0
			_stage = 2
		return false
	if _stage == 1:
		# The whole town drawn in once, from the first spot (the first
		# warm-up runs while it draws in).
		if not _warm(WARM_MS):
			return false
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
	_prepare(SHOTS[0])
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
	_prepare(s)
	_set_shot(s)
	_stage = 4


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


## The light pinned to that day and hour (as tools/daylight_shot.gd does),
## and the town's clock brought to that hour: run through the day by _warm
## (the sim is run to `hour` of `month`'s sky day), or, with --legacy-warm,
## jumped to the date as this tool first did (the people never had the
## morning: nobody at work, nobody shopping).
func _set_moment(month: int, day: int, hour: float) -> void:
	var date: float = float(month - 1) + float(day - 1) / Seasons.DAYS_IN[month - 1]
	for n in _main.find_children("*", "DayNight", true, false):
		n.set("date_override", date)
		n.set("hour_override", hour)
	if _legacy:
		_main.sim.set_calendar(Seasons.tick_at(12.0 + date))
		return
	var sim: CitySim = _main.sim
	if _month == 0:
		# The first day: all of it, from sunrise on the 1st.
		_new_day(Seasons.tick_at(12.0 + float(month - 1)), false)
		_month = month
	elif month != _month or hour < _target - 0.01 or hour > _target + LEAD + 0.01:
		# Another day, or too far on from the last shot to run through:
		# LEAD hours before this one.
		_new_day(Seasons.tick_at(SkyClock.at(month, maxf(hour - LEAD, 0.0))), true)
		_month = month
	_target = hour


## The calendar jumps to `cal` (a calendar tick): whoever is out is due home
## now (the game's own timer, People.plan: they set off in the first
## minutes of the new day, a few at a time while the sidewalks have room),
## and with `settle` the people whose shift covers the new hour are at work.
func _new_day(cal: int, settle: bool) -> void:
	var sim: CitySim = _main.sim
	var ids: Array = sim.people.people.keys()
	ids.sort()
	var out := 0
	for id in ids:
		var p: Dictionary = sim.people.people[id]
		if p.at != "" and p.at != "travel":
			out += 1
			sim.people.set_until(p, sim.tick_count)
	print("look_round: a new day: %d people out, all due home" % out)
	if out > 0:
		_caps = Vector2i(sim.traffic.max_cars, sim.traffic.max_walkers)
		sim.traffic.max_cars = 4 * _caps.x
		sim.traffic.max_walkers = 8 * _caps.y
		_home_left = HOME_TICKS
	sim.set_calendar(cal)
	if settle:
		sim.people.settle(sim, sim.traffic)


## Runs the sim on to the sky hour asked for (_target), a few milliseconds
## of ticks at a time with a window open (budget_ms; 0: all of it at once).
## True once it is there.
func _warm(budget_ms := 0) -> bool:
	if _legacy or _month == 0:
		return true
	var sim: CitySim = _main.sim
	var t0 := Time.get_ticks_msec()
	var n := 0
	while sim.sky_hour() < _target:
		sim.tick()
		_ticks += 1
		n += 1
		if _dock_wh >= 0:
			sim.traffic.max_cars = maxi(sim.traffic.max_cars, 4 * _dock_cap)
			if _ticks % DOCK_EVERY == 0:
				_dock_load(sim)
		if _home_left > 0:
			_home_left -= 1
			if _home_left == 0:
				sim.traffic.max_cars = _caps.x
				sim.traffic.max_walkers = _caps.y
		if _ticks > WARM_CAP * 4:
			printerr("look_round: the sky hour never reached %.2f (stopped at %.2f)" % [_target, sim.sky_hour()])
			return true
		if budget_ms > 0 and n % 20 == 0 and Time.get_ticks_msec() - t0 > budget_ms:
			return false
	if _dock_wh >= 0:
		sim.traffic.max_cars = _dock_cap  # (and the walkers' limit is back by now)
	return true


## The evening hour the sun is DUSK_SUN degrees under the horizon.
func _dusk(month: int, day: int) -> float:
	var date: float = float(month - 1) + float(day - 1) / Seasons.DAYS_IN[month - 1]
	var h := 17.0
	while h < 23.5 and SkyLight.sun_position(h, date).x > DUSK_SUN:
		h += 1.0 / 60.0
	return h


## Before shot `s`: shot 11's warehouse goes in (once), finished, and the
## shot is aimed at its docks.
func _prepare(s: Array) -> void:
	if s[0] != "11_docks_60m" or _dock_wh >= 0:
		return
	var sim: CitySim = _main.sim
	_dock_cap = _caps.x if _home_left > 0 else sim.traffic.max_cars
	for at in [DOCK_WH[1]] + DOCK_WH[2]:
		var site := Warehouses.site_near(sim.network, at)
		if site.is_empty() or sim.warehouse_problem(DOCK_WH[0], site[0], site[1]) != "":
			continue
		if sim.apply({"type": "place_warehouse", "kind": DOCK_WH[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
			var ids := sim.warehouses.buildings.keys()
			ids.sort()
			_dock_wh = ids[-1]
			sim.construction.sites.erase("wh:%d" % _dock_wh)  # built already
			sim.warehouses_changed.emit()
			break
	if _dock_wh < 0:
		printerr("look_round: no site for shot 11's warehouse")
		return
	_dock_aim(s)
	var w: Dictionary = sim.warehouses.buildings[_dock_wh]
	print("look_round: shot 11's %s warehouse at %s, facing %s, %d docks" % [DOCK_WH[0], w.pos, w.dir, Warehouses.dock_xs(w).size()])


## Shot 11: one of the nearest factories sends the warehouse a load of
## goods, as Logistics does (on its books, room promised).
func _dock_load(sim: CitySim) -> void:
	var w: Dictionary = sim.warehouses.buildings.get(_dock_wh, {})
	if w.is_empty():
		return
	if _dock_from.is_empty():
		var keys := []
		for key in sim.buildings:
			if int(sim.buildings[key].zone) == ZoneMap.Zone.INDUSTRIAL and sim.lots.has(key):
				keys.append(key)
		keys.sort_custom(func(a, b): return sim.lots[a].front.distance_to(w.pos) < sim.lots[b].front.distance_to(w.pos) \
			or (sim.lots[a].front.distance_to(w.pos) == sim.lots[b].front.distance_to(w.pos) and a < b))
		_dock_from = keys.slice(0, DOCK_FROM)
	if _dock_from.is_empty() or Warehouses.free_space(w) < 1:
		return
	var key: String = _dock_from[_dock_sent % _dock_from.size()]
	var lot: Dictionary = sim.lots[key]
	var from := {"ref": "lot:" + key, "pos": [snappedf(lot.front.x, 0.01), snappedf(lot.front.z, 0.01)]}
	var to := {"ref": "wh:%d" % _dock_wh, "pos": [snappedf(w.pos.x, 0.01), snappedf(w.pos.z, 0.01)]}
	var cargo := {"good": "goods", "amount": 1}
	var id := sim.traffic.dispatch(from, to, "goods", cargo, "box_truck" if _dock_sent % 2 == 0 else "semi")
	_dock_sent += 1
	if id >= 0:
		sim.logistics.trips[id] = {"from": from, "to": to, "purpose": "goods", "cargo": cargo, "kind": "factory"}
		w.incoming = int(w.incoming) + 1


## Shot 11: the middle of the warehouse's truck court, from the street side
## and a little to the left.
func _dock_aim(s: Array) -> void:
	var w: Dictionary = _main.sim.warehouses.buildings[_dock_wh]
	var at := Warehouses.frame(w) * Vector3(Warehouses.gate_x(w), 0.0, -Warehouses.site_depth(w) * 0.5
		+ float(Warehouses.spec(w).court) * 0.55)
	s[1] = Vector3(at.x, 0.0, at.z)
	s[2] = rad_to_deg(atan2(w.dir.x, w.dir.z)) + 35.0


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


## --dry: every shot's warm-up, no drawing, and a count of where the cars
## are at that moment. "shops" and "factories" are cars parked on commercial
## and industrial lots (or at the curb of one), "homes" on residential ones,
## "at docks" trucks backed up to a warehouse's dock (shot 11).
func _dry_run() -> void:
	var sim: CitySim = _main.sim
	var t0 := Time.get_ticks_msec()
	print("look_round: dry run (%s warm-up)" % ("legacy: %d ticks, clock jumped" % WARM_TICKS if _legacy else "through the day"))
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		var t1 := Time.get_ticks_msec()
		var before := _ticks
		_shot = i
		_prepare(s)
		_set_shot(s)
		_warm()
		var c := _census(sim)
		var line := "look_round: %-18s %s hour %5.2f  parked: shops %3d  factories %3d  homes %4d  other %3d  at docks %2d | people at work %4d, at errands %3d, in transit %4d, home %4d of %d | driving %3d, walking %3d | +%d ticks %.1fs" % [
			s[0], "legacy" if _legacy else "warm  ", sim.sky_hour(), c.shops, c.factories, c.homes, c.other, c.docks,
			c.at_job, c.errands, c.travel, c.home, c.people, sim.traffic.cars.size(), sim.traffic.walkers.size(),
			_ticks - before, (Time.get_ticks_msec() - t1) / 1000.0]
		print(line)
	if "--perf" in OS.get_cmdline_user_args():
		var keys := Perf.stats.keys()
		keys.sort_custom(func(a, b): return Perf.stats[a].sum > Perf.stats[b].sum)
		for k in keys.slice(0, 14):
			print("look_round: perf %-28s %8.0f ms total, %6.2f ms/tick" % [k, Perf.stats[k].sum, Perf.stats[k].sum / maxi(_ticks, 1)])
	print("look_round: dry run took %.1f s, %d warm-up ticks" % [(Time.get_ticks_msec() - t0) / 1000.0, _ticks])
	quit()


## Parked cars by the kind of lot they are on, and where the people are.
func _census(sim: CitySim) -> Dictionary:
	var c := {"shops": 0, "factories": 0, "homes": 0, "other": 0, "docks": 0, "people": sim.people.people.size(),
		"at_job": 0, "errands": 0, "home": 0, "travel": 0}
	for car in sim.traffic.parked:
		var ref: String = car.get("at_place", "")
		if car.has("dock_t"):
			c.docks += 1  # backed up to a warehouse's dock
		var z := -1
		if ref.begins_with("lot:") and sim.buildings.has(ref.trim_prefix("lot:")):
			z = int(sim.buildings[ref.trim_prefix("lot:")].zone)
		match z:
			ZoneMap.Zone.COMMERCIAL: c.shops += 1
			ZoneMap.Zone.INDUSTRIAL: c.factories += 1
			ZoneMap.Zone.RESIDENTIAL: c.homes += 1
			_: c.other += 1
	for id in sim.people.people:
		var p: Dictionary = sim.people.people[id]
		if p.at == "":
			c.home += 1
		elif p.at == "travel":
			c.travel += 1
		elif p.at == p.job:
			c.at_job += 1
		else:
			c.errands += 1
	return c


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
		"town": "PerfTown big" + (", shot 11 with a %s warehouse added on the east edge" % DOCK_WH[0] if _dock_wh >= 0 else ""),
		"warm_ticks": WARM_TICKS, "day_ticks": _ticks, "warm": "legacy" if _legacy else "through the day", "buildings": _main.sim.buildings.size(),
		"day": DAY, "dusk_hour": snappedf(_dusk_hour, 0.01), "night_hour": NIGHT_HOUR, "winter": WINTER,
		"date": Time.get_date_string_from_system(), "shots": _rows}
	var f := FileAccess.open(_out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("look_round: wrote ", _out.path_join("frames.json"))
	quit()
