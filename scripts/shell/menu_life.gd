class_name MenuLife
extends Node
## Runs the title screen town's day: Marion's real date and hour (or the
## one a screenshot asks for with `--menu-time=2026-12-15T23:00`) light the
## sky and the land, and the town's own people and traffic go about it, a
## light version of the game's tick: only the people's plans and the
## traffic step run (no building, budget or growth), at most a few
## milliseconds a frame, so the menu never stalls. How many cars and people
## are out comes from the hour (People.plan and TrafficSim._spawn rush at
## 6-9 and 4-7, are quiet from 10 pm to 5 am) and is capped by graphics
## tier, so a browser stays light. At night an occasional police car
## patrols.

## The grown town the title screen shows (tools/menu_town.gd made it).
const MENU_TOWN := "res://art/menu/town.city"

## Cars and people at most, by graphics tier (Low .. Cinematic).
const CAPS := [[26, 22], [44, 36], [80, 64], [120, 96], [150, 120]]
## Real milliseconds a frame may spend stepping the town.
const BUDGET_MS := 5.0
## Steps to run up front, so the streets already have people on them (a
## minute and a half of driving); spread over the first frames.
const PREROLL := 900
const STEP := 1.0 / CitySim.TICKS_PER_SECOND

var sim: MenuSim
var look: DayNight
## Seconds to add to the player's clock (the debug time).
var offset := 0.0
var wall := {}

## The weather over Marion, the one input a later change feeds (the National
## Weather Service's observation): sky cover 0 to 1, rain, snow and fog 0
## to 1. Clear until something sets it; nothing draws it yet. Date, hour and
## season above come from the clock alone, so weather lands on top of them.
var conditions := {"cloud": 0.0, "rain": 0.0, "snow": 0.0, "fog": 0.0}

var _tick := 0
var _accum := 0.0
var _preroll := PREROLL
var _next_police := 20.0
var _police_lot := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


## `forced` is a Marion local time like "2026-12-15T23:00" (or "" for now).
func setup(s: MenuSim, daynight: DayNight, forced := "") -> void:
	sim = s
	look = daynight
	process_priority = -10  # before DayNight and the views
	_tick = sim.tick_count
	_rng.seed = hash([sim.city_seed, "menu"])
	if forced != "":
		var f := parse(forced)
		if f > 0.0:
			offset = f - Time.get_unix_time_from_system()
	var cap := caps()
	# New trips stop short of the tier's numbers: cars already on their way
	# (people walking to them, vehicles heading home) still arrive after.
	sim.traffic.max_cars = maxi(int(cap.x * 0.4), 4)
	sim.traffic.max_walkers = maxi(int(cap.y * 0.6), 4)
	# The patrol leaves the police station (else the fire station, else
	# the middle of Main Street).
	_police_lot = Vector2(0.0, 40.0)
	for want in [Services.Kind.FIRE, Services.Kind.POLICE]:
		for id in sim.services.buildings:
			var b: Dictionary = sim.services.buildings[id]
			if int(b.kind) == want:
				_police_lot = Vector2(b.pos.x, b.pos.z)
	_update_clock()


## Sets the weather (any of cloud, rain, snow, fog, each 0 to 1).
func set_conditions(c: Dictionary) -> void:
	for k in conditions:
		conditions[k] = clampf(float(c.get(k, 0.0)), 0.0, 1.0)


## Marion's local time as text (2026-12-15T23:00) to a Unix time, or 0.
static func parse(text: String) -> float:
	var parts := text.strip_edges().replace(" ", "T").split("T")
	var d := parts[0].split("-")
	if d.size() != 3:
		return 0.0
	var hour := 12.0
	if parts.size() > 1:
		var hm := parts[1].split(":")
		hour = float(hm[0]) + (float(hm[1]) / 60.0 if hm.size() > 1 else 0.0)
	return MarionTime.to_unix(int(d[0]), int(d[1]), int(d[2]), hour)


## Cars and people to allow at the running graphics tier.
static func caps() -> Vector2i:
	var q := GraphicsQuality.current
	var tier := GraphicsQuality.HIGH
	if q != null and q.active:
		tier = q.tier
	var c: Array = CAPS[clampi(tier, 0, CAPS.size() - 1)]
	return Vector2i(int(c[0]), int(c[1]))


func _process(delta: float) -> void:
	if sim == null:
		return
	_update_clock()
	var t0 := Time.get_ticks_usec()
	var budget := BUDGET_MS * 1000.0
	_accum += delta
	if _preroll > 0:
		# Catching the morning up: as many steps as fit, a few frames' worth
		# of time, not a stall.
		while _preroll > 0 and float(Time.get_ticks_usec() - t0) < budget * 2.0:
			_step()
			_preroll -= 1
	else:
		var n := 0
		while _accum >= STEP and n < 6 and float(Time.get_ticks_usec() - t0) < budget:
			_accum -= STEP
			_step()
			n += 1
	# A frame that fell behind drops the backlog rather than rushing the cars.
	_accum = minf(_accum, STEP) if _preroll <= 0 else 0.0
	sim.minute_bias = _accum / STEP
	sim.tick_count = _pinned()
	_patrol(delta)


## Marion's time now, and the date it puts on the land.
func _update_clock() -> void:
	wall = MarionTime.at(Time.get_unix_time_from_system() + offset)
	sim.wall = wall
	sim.tick_count = _pinned()
	look.date_override = MarionTime.months_for_sky(wall)


## The tick count the views see: the date as the game's calendar has it
## (Seasons.months), years on so every building is grown. The town's own
## counter (_tick) runs separately, one step per traffic step.
func _pinned() -> int:
	return int((MarionTime.months_of(wall) + 24.0 - Seasons.START_MONTH) * Seasons.TICKS_PER_DAY)


## One tenth of a second of the town: people decide, cars drive.
func _step() -> void:
	_tick += 1
	sim.tick_count = _tick
	var prng := RandomNumberGenerator.new()
	prng.seed = hash([sim.city_seed, _tick, "people"])
	sim.people.sync(sim, sim.traffic, prng)
	sim.people.plan(sim, sim.traffic, prng)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, _tick, "traffic"])
	sim.traffic.step(sim, rng)
	sim.tick_count = _pinned()


func tick_fraction() -> float:
	return _accum / STEP


## In the small hours a patrol car leaves the station now and then, drives
## to a street in town and goes back.
func _patrol(delta: float) -> void:
	_next_police -= delta
	if _next_police > 0.0:
		return
	_next_police = _rng.randf_range(40.0, 110.0)
	var hour: int = int(wall.hour)
	if not (hour >= 22 or hour < 5) or _preroll > 0:
		return
	for car in sim.traffic.cars:
		if car.kind == "police":
			return
	var spot := Vector2(_rng.randf_range(-250.0, 250.0), _rng.randf_range(-40.0, 40.0))
	sim.traffic.dispatch({"ref": "menu:station", "pos": [_police_lot.x, _police_lot.y]},
		{"ref": "menu:patrol", "pos": [spot.x, spot.y]}, "police")
