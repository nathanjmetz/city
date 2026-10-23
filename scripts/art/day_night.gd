class_name DayNight
extends Node3D
## The two look switches Brawn asked for, kept apart like in Cities:
## Skylines 2's settings:
##   - Day and night: off by default, so the town stays in late-morning sun.
##     On, the sun follows the clock, then dusk, moonlight and stars, with
##     streetlights, lit windows and headlights coming on.
##   - Seasons: spring, summer, fall colour and harvest, and winter with snow
##     on the ground (never falling: there is no weather). Off, it's always
##     summer.
## Both only change how the town looks. The clock and the year come from the
## simulation's tick count (see Seasons), so they stay in step for everyone
## in a region; each player picks for themselves whether to see them.
##
## Everything that changes with the hour or the season reads a few global
## shader values set here: night, snow, season_look and windows_lit.

const SETTINGS_PATH := "user://look.json"

static var cycle_on := false
static var seasons_on := true
static var _loaded := false

var sim: CitySim
var sky: SkyLight
## Returns how far through the current tick the clock is, 0 to 1.
var tick_fraction := Callable()
var _lamps: StreetLights
var _beams: Headlights
var _was_cycle := false


func setup(s: CitySim, light: SkyLight, fraction := Callable()) -> void:
	sim = s
	sky = light
	tick_fraction = fraction


func _ready() -> void:
	load_settings()
	_lamps = StreetLights.new()
	_lamps.setup(sim.network)
	add_child(_lamps)
	_beams = Headlights.new()
	_beams.setup(sim.traffic, tick_fraction)
	add_child(_beams)


func _process(_delta: float) -> void:
	var frac: float = tick_fraction.call() if tick_fraction.is_valid() else 0.0
	var months: float = Seasons.months(sim.tick_count) + frac / Seasons.TICKS_PER_DAY
	var look := Seasons.look(months) if seasons_on else Seasons.summer()
	RenderingServer.global_shader_parameter_set("snow", look.snow)
	Seasons.snow_now = look.snow
	RenderingServer.global_shader_parameter_set("season_look",
		Vector4(look.autumn, look.bare, look.spring, look.dry))
	var night := 0.0
	var lit := 0.0
	if cycle_on:
		var clock := sim.clock()
		var hour: float = clock.hour + (clock.minute + frac) / 60.0
		sky.set_time(hour, months if seasons_on else 6.5)
		night = sky.darkness
		lit = window_share(hour)
	elif _was_cycle:
		sky.set_fixed()
	_was_cycle = cycle_on
	RenderingServer.global_shader_parameter_set("night", night)
	RenderingServer.global_shader_parameter_set("windows_lit", lit)
	_lamps.visible_amount = smoothstep(0.25, 0.6, night)
	_beams.amount = smoothstep(0.3, 0.7, night)


## Share of windows with a light on at this hour: most in the evening,
## a few through the small hours, some again before work.
static func window_share(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 5.0:
		return lerpf(0.22, 0.1, h / 5.0)
	if h < 8.0:
		return 0.1 + 0.25 * sin((h - 5.0) / 3.0 * PI)
	if h < 17.0:
		return 0.12
	if h < 22.0:
		return lerpf(0.4, 0.68, smoothstep(17.0, 20.0, h))
	return lerpf(0.68, 0.22, (h - 22.0) / 2.0)


## The month fields and anything else seasonal should show (1 to 12):
## July while seasons are off.
static func visible_month(s: CitySim) -> int:
	return s.clock().month if seasons_on else 7


static func set_cycle(on: bool) -> void:
	cycle_on = on
	save_settings()


static func set_seasons(on: bool) -> void:
	seasons_on = on
	save_settings()


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		cycle_on = bool(data.get("day_night", false))
		seasons_on = bool(data.get("seasons", true))


static func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"day_night": cycle_on, "seasons": seasons_on}))
