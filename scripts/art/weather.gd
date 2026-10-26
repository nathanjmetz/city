class_name Weather
extends Node3D
## Grant County weather on the town (Nathan, 2026-10-25: match the real feel
## of the place, with "a simple toggle switch" to turn it off). Drawn only:
## the town's thinking never sees it. Each game day gets its own sky from
## the date (the same for everyone, every time), by Indiana's odds for the
## month: overcast or fair, some days a few hours of rain (snow in winter),
## and some mornings fog. Overcast dims and greys the picture and softens
## shadows; rain streaks over it, snow drifts down, fog thickens the haze.
## Off: always fair.

## Share of days with rain or snow, January to December (Indianapolis has
## 10-13 days of measurable precipitation a month, five or six of them snow
## in the depth of winter), and the share of those that fall as snow.
const WET_DAYS := [0.22, 0.2, 0.3, 0.4, 0.42, 0.38, 0.33, 0.3, 0.27, 0.28, 0.3, 0.22]
const SNOW_SHARE := [1.0, 1.0, 0.35, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.9]
## Of the wet days, the share that are grey all day with steady rain or
## snow; the rest are showery: broken cloud that closes in for a few hours.
const STEADY_WET := 0.55
## Of the dry days, the share that are mostly cloudy, and then of the rest
## the share that are partly cloudy (bright, with full shadows) rather than
## clear. Altogether about 40-45% of days are mostly cloudy, about
## Indianapolis's share; the critic (2026-10-26) measured 53% of daytime
## hours overcast before, which buried the town's colour.
const OVERCAST_DAYS := 0.28
const PARTLY_DAYS := 0.45
## A brand-new town's first game day is fair, so a new player's first look
## at their land isn't fog under a grey sky (every new town starts on the
## same date, which rolled fog and overcast).
const FIRST_DAY_COVER := 0.12
## Share of days that start in fog: radiation fog after a clear, still
## night, burning off by mid-morning; most in autumn.
const FOG_DAYS := [0.06, 0.06, 0.05, 0.04, 0.05, 0.05, 0.06, 0.08, 0.1, 0.1, 0.08, 0.07]
## How much thicker than clear-day haze a full fog is: under a kilometre to
## see, against about 18 km on a clear day.
const FOG_HAZE := 15.0
## Faint streaks over the picture, three depths of them, nearer ones longer
## and faster; snow is soft flakes drifting down slower. Drawn flat over the
## screen like most city builders do: from high up, real drops would be
## thinner than a pixel.
const RAIN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float snow = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float streaks(vec2 uv, float cells, float speed) {
	vec2 p = uv * vec2(cells, cells * 0.25);
	p.x += p.y * 0.3;
	p.y -= TIME * speed;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	if (hash(cell) > amount) {
		return 0.0;
	}
	float x = 0.15 + 0.7 * hash(cell + 7.1);
	float len = 0.45 + 0.4 * hash(cell + 3.3);
	float y0 = hash(cell + 1.7) * (1.0 - len);
	float line = 1.0 - smoothstep(0.0, 0.07, abs(f.x - x));
	float along = step(y0, f.y) * step(f.y, y0 + len);
	return line * along * (f.y - y0) / len;
}

float flakes(vec2 uv, float cells, float speed, float sway) {
	vec2 p = uv * cells;
	p.y -= TIME * speed;
	p.x += sin(TIME * 0.7 + p.y * 0.6) * sway;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	if (hash(cell) > snow) {
		return 0.0;
	}
	vec2 c = vec2(0.2 + 0.6 * hash(cell + 7.1), 0.2 + 0.6 * hash(cell + 3.3));
	float r = 0.07 + 0.07 * hash(cell + 1.7);
	return 1.0 - smoothstep(r * 0.4, r, length(f - c));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float a = 0.0;
	if (amount > 0.0) {
		a = 0.5 * streaks(uv, 60.0, 20.0) + 0.6 * streaks(uv + 0.37, 38.0, 16.0)
			+ 0.7 * streaks(uv + 0.71, 24.0, 12.0);
	}
	float s = 0.0;
	if (snow > 0.0) {
		s = 0.5 * flakes(uv, 42.0, 1.4, 0.25) + 0.7 * flakes(uv + 0.5, 26.0, 1.0, 0.35)
			+ 0.9 * flakes(uv + 0.3, 15.0, 0.7, 0.45);
	}
	vec3 col = mix(vec3(0.82, 0.86, 0.92), vec3(1.0), step(a * 0.4, s * 0.7));
	COLOR = vec4(col, max(a * 0.4, s * 0.7));
}
"""

static var on := true

var sim: CitySim
var sky: SkyLight
## Now: how much of the sky is cloud, how hard it rains or snows, and how
## thick the fog (each 0-1).
var cover := 0.0
var rain := 0.0
var snow := 0.0
var fog := 0.0
## Real conditions to show instead of the odds, [cover, rain or snow, fog,
## snow 0/1] (the home screen's Marion report, MarionWeather), or [] for
## the odds.
var live := []
var _rain: ColorRect
## The sky's colour settings before any cloud.
var _base := []
var _rain_mat: ShaderMaterial


func setup(s: CitySim, light: SkyLight) -> void:
	sim = s
	sky = light


func _ready() -> void:
	# Under the game's menus and panels, over the town.
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var sh := Shader.new()
	sh.code = RAIN_SHADER
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = sh
	_rain = ColorRect.new()
	_rain.material = _rain_mat
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain.visible = false
	layer.add_child(_rain)


## The sky at a clock time (CitySim.clock(): year, month, day, hour,
## minute): [cover 0-1, rain or snow 0-1, fog 0-1, 1 if it falls as snow].
## Keyed to the date shown, so the home screen's real Marion clock and the
## game's own both work.
static func conditions(clock: Dictionary) -> Array:
	var month := int(clock.month)
	var hour := float(clock.hour) + float(clock.get("minute", 0.0)) / 60.0
	var h := hash([int(clock.year), month, int(clock.day), "weather"])
	var roll := float(h % 1000) / 1000.0
	var fog := 0.0
	var fh := hash([int(clock.year), month, int(clock.day), "fog"])
	if float(fh % 1000) / 1000.0 < FOG_DAYS[month - 1]:
		# Thickest at dawn, gone by eight to ten.
		var lift := 8.0 + float((fh >> 10) % 3)
		if hour >= 3.0 and hour < lift:
			fog = clampf((lift - hour) / 2.0, 0.0, 1.0) * clampf(hour - 3.0, 0.0, 1.0)
	var wet_share: float = WET_DAYS[month - 1]
	var kind := float(hash([int(clock.year), month, int(clock.day), "sky"]) % 1000) / 1000.0
	if roll < wet_share:
		# A wet day: three to seven hours of rain or snow.
		var snowy := 1.0 if float((h >> 22) % 100) / 100.0 < float(SNOW_SHARE[month - 1]) else 0.0
		var start := 4.0 + float((h >> 10) % 14)
		var length := 3.0 + float((h >> 14) % 5)
		var falling := hour >= start and hour < start + length
		var edge := clampf(minf(hour - start, start + length - hour), 0.0, 1.0)
		var amount := (0.45 + float((h >> 18) % 50) / 100.0) * edge if falling else 0.0
		if kind < STEADY_WET:
			return [0.95, amount, fog, snowy]
		# Showers: broken cloud, closing in over the hour before the spell
		# and clearing over the hour after.
		var near := clampf(minf(hour - start + 1.0, start + length + 1.0 - hour), 0.0, 1.0)
		return [lerpf(0.45, 0.9, near), amount, fog, snowy]
	var dry_roll := (roll - wet_share) / (1.0 - wet_share)
	if dry_roll < OVERCAST_DAYS:
		return [0.7, 0.0, fog, 0.0]
	if kind < PARTLY_DAYS:
		return [0.3 + float((h >> 6) % 20) / 100.0, 0.0, fog, 0.0]
	return [float((h >> 6) % 30) / 100.0, 0.0, fog, 0.0]


## The sky over a town in play: the date's odds (conditions), except that a
## new town's first game day (tick under a game day) is always fair, and
## there's no fog while Day and night is off (`cycle` false): the light is
## held at late morning then, and dawn fog under it read as a fault (the
## critic, 2026-10-26).
static func for_town(clock: Dictionary, tick: int, cycle: bool) -> Array:
	if tick < Seasons.TICKS_PER_DAY:
		return [FIRST_DAY_COVER, 0.0, 0.0, 0.0]
	var c := conditions(clock)
	if not cycle:
		c[2] = 0.0
	return c


func _process(_delta: float) -> void:
	if sim == null or sky == null:
		return
	var c := [0.0, 0.0, 0.0, 0.0]
	if on:
		if live.size() >= 4:
			c = live
		elif sim is MenuSim:
			# The home screen's real date (its tick is pinned to the season).
			c = conditions(sim.clock())
		else:
			c = for_town(sim.clock(), sim.tick_count, DayNight.cycle_on)
	var snowing := float(c[3]) > 0.5
	cover = lerpf(cover, float(c[0]), 0.02)
	rain = lerpf(rain, 0.0 if snowing else float(c[1]), 0.03)
	snow = lerpf(snow, float(c[1]) if snowing else 0.0, 0.02)
	fog = lerpf(fog, float(c[2]), 0.01)
	sky.weather_haze = 1.0 + (FOG_HAZE - 1.0) * fog
	# Overcast: a flatter, greyer, dimmer picture, but only past broken
	# cloud: a partly cloudy day keeps the full sun and shadows. Lighter than
	# it was (an overcast 0.7 lost 15% brightness, 25% colour and half its
	# shadows; now about 9%, 15% and a third).
	# On top of the sky's own colour settings, never in place of them.
	var grey := smoothstep(0.4, 0.95, cover)
	var env := sky.env
	if _base.is_empty():
		_base = [env.adjustment_enabled, env.adjustment_brightness, env.adjustment_saturation, env.adjustment_contrast]
	env.adjustment_enabled = bool(_base[0]) or grey > 0.01
	env.adjustment_brightness = float(_base[1]) * (1.0 - 0.15 * grey)
	env.adjustment_saturation = float(_base[2]) * (1.0 - 0.26 * grey)
	env.adjustment_contrast = float(_base[3]) * (1.0 - 0.1 * grey)
	# Cloud spreads the sun: shadows go soft and faint.
	sky.sun.shadow_opacity = 1.0 - 0.6 * grey
	_rain.visible = rain > 0.05 or snow > 0.05
	if _rain.visible:
		_rain_mat.set_shader_parameter("amount", clampf(rain, 0.0, 1.0) * 0.55 if rain > 0.05 else 0.0)
		_rain_mat.set_shader_parameter("snow", clampf(snow, 0.0, 1.0) * 0.6 if snow > 0.05 else 0.0)
