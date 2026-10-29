class_name Daylight
extends RefCounted
## What the light looks like for a height of the sun: its colour and
## strength, the sky's colours, the shade's skylight and the haze. One
## formula for every time of day and year, so dawn in March and dusk in
## July differ only by where the sun is (SunPath) and how humid the air is.
## Sources and the numbers behind them: docs/daylight.md.
##
## Everything is relative to the town's tuned late-morning look (sun 40
## degrees up on a clear summer day; see SkyLight), which these reproduce
## at 40 degrees: SkyLight multiplies by its own base strengths.

## Colour temperature of direct sunlight (kelvin) by the sun's height
## (degrees): reddish at the horizon, golden near 5 degrees, near white
## from about 40 degrees up. Rounded from published measurements of direct
## beam sunlight (see the doc).
const SUN_KELVIN := [[-1.0, 1850.0], [0.0, 2000.0], [2.0, 2450.0], [5.0, 3050.0], [10.0, 3850.0],
	[15.0, 4400.0], [20.0, 4800.0], [30.0, 5250.0], [40.0, 5500.0], [60.0, 5750.0], [90.0, 5850.0]]

## Sky and shade by the sun's height: [height, zenith, horizon, shade light
## colour, shade light strength (1 = the tuned daytime fill)]. The day rows
## are the tuned look; dusk rows are the warm horizon of sunset; -3 to -6 is
## blue hour (civil twilight's end), -12 nautical twilight, then night.
const SKY := [
	[-18.0, Color(0.012, 0.02, 0.05), Color(0.05, 0.06, 0.1), Color(0.32, 0.42, 0.72), 0.97],
	[-12.0, Color(0.014, 0.024, 0.06), Color(0.06, 0.07, 0.12), Color(0.32, 0.42, 0.72), 0.97],
	[-6.0, Color(0.035, 0.065, 0.17), Color(0.17, 0.19, 0.32), Color(0.34, 0.43, 0.72), 0.97],
	[-3.0, Color(0.09, 0.14, 0.32), Color(0.56, 0.42, 0.42), Color(0.44, 0.49, 0.70), 0.98],
	[0.0, Color(0.16, 0.22, 0.45), Color(0.96, 0.58, 0.36), Color(0.60, 0.56, 0.60), 0.86],
	[3.0, Color(0.17, 0.27, 0.53), Color(0.93, 0.70, 0.50), Color(0.68, 0.62, 0.58), 0.86],
	[8.0, Color(0.17, 0.32, 0.62), Color(0.84, 0.78, 0.70), Color(0.68, 0.65, 0.61), 0.92],
	[16.0, Color(0.17, 0.35, 0.68), Color(0.77, 0.79, 0.81), Color(0.66, 0.66, 0.64), 0.97],
	[30.0, Color(0.17, 0.36, 0.70), Color(0.74, 0.79, 0.84), Color(0.66, 0.66, 0.64), 1.0],
	[90.0, Color(0.15, 0.35, 0.72), Color(0.73, 0.79, 0.85), Color(0.66, 0.66, 0.64), 1.04],
]

## Haze through the year: the Midwest's humid summers whiten the sky low
## down and cut how far you see; winter air is crisp and blue.
const HAZE_SUMMER := Color(0.77, 0.80, 0.83)
const HAZE_WINTER := Color(0.66, 0.76, 0.88)
## How the haze's thickness scales, winter to summer (1 = the tuned look:
## about 24 km visibility). Summer about 19 km, winter about 32.
const HAZE_THIN := 0.75
const HAZE_THICK := 1.25


## The desktop app's night (Forward+, CloudSky; the browser keeps the rows
## above). Benchmark: an 11 pm July sky over a small Indiana town, eyes used
## to the dark. Overhead it is a deep navy, never black; low down the town's
## lights glow warm grey-orange in the haze (skyglow), about 3 times brighter
## than the zenith. Houses are dark: the moon and sky give a faint, greyish
## light, a few percent of daylight's fill once the eye has adapted, and
## lamps and lit windows do the rest. NIGHT_FILL is the shade light's share
## of its daytime strength at full night (the table's night rows keep 0.97,
## which lit walls a bright day-for-night blue).
const NIGHT_ZENITH := Color(0.075, 0.1, 0.21)
const NIGHT_GLOW := Color(0.25, 0.22, 0.2)
const NIGHT_SHADE := Color(0.42, 0.47, 0.6)
const NIGHT_FILL := 0.3


## How humid the air is at this point in the year (months from January, any
## year): 0 in mid-January, 1 in mid-July, when Indiana's dew points peak.
static func humidity(months: float) -> float:
	return 0.5 - 0.5 * cos(TAU * (fposmod(months, 12.0) - 0.55) / 12.0)


## The light for a sun at height `e` (degrees, as seen) on air of humidity
## `humid` (0 to 1). Colours are as the editor shows them (sRGB), like
## SkyLight's own; strengths are relative to the tuned 40-degree look.
## `rich`: the desktop app's dusk and night (NIGHT_ZENITH and the rest);
## the same light as the browser's while the sun is 8 degrees or more up.
static func at(e: float, humid: float, rich := false) -> Dictionary:
	var row := _sky_row(e)
	var haze := HAZE_WINTER.lerp(HAZE_SUMMER, humid)
	# Haze shows most in a high sun's sky and fades into the sunset colours.
	var haze_share := smoothstep(4.0, 16.0, e)
	var horizon: Color = row[1]
	horizon = horizon.lerp(horizon * haze / Color(0.74, 0.79, 0.84), haze_share)
	var zenith: Color = row[0]
	# A humid summer sky is a paler blue overhead.
	zenith = zenith.lerp(zenith.lerp(Color(0.32, 0.47, 0.72), 0.12), humid * haze_share)
	var day := smoothstep(-8.0, 5.0, e)
	var sun := sun_strength(e)
	var l := {
		"sun_color": kelvin_color(sun_kelvin(e) - 250.0 * humid * (1.0 - smoothstep(5.0, 30.0, e))),
		"sun_energy": sun,
		"exposure": exposure(e, sun, row[3]),
		"zenith": zenith,
		"horizon": horizon,
		"shade_color": row[2],
		"shade_energy": row[3],
		# The air glows with the sky low down; at dusk only a little of the
		# sunset's colour, since the land is lit by the open blue sky.
		"fog_color": Color(0.05, 0.06, 0.1).lerp(haze, day).lerp(Color(0.62, 0.5, 0.5),
			0.35 * (1.0 - smoothstep(0.0, 22.0, absf(e))) * (1.0 - smoothstep(-1.0, 6.0, -e))),
		"haze": lerpf(HAZE_THIN, HAZE_THICK, humid),
		"darkness": 1.0 - smoothstep(-7.0, 3.0, e),
		# First stars at the end of civil twilight, most of them by nautical.
		"stars": 0.9 * (1.0 - smoothstep(-13.0, -5.0, e)),
	}
	if rich and e < 8.0:
		# Overhead, twilight's blue has a little more green in it than the
		# table's: the desktop's tone curve (AgX) turns so pure a blue
		# purple. Then the zenith darkens no further than the night's navy.
		var z: Color = l.zenith
		var dusk := smoothstep(-9.0, -3.0, e) * (1.0 - smoothstep(2.0, 8.0, e))
		z.r *= 1.0 - 0.25 * dusk
		z.g *= 1.0 + 0.4 * dusk
		l.zenith = Color(maxf(z.r, NIGHT_ZENITH.r), maxf(z.g, NIGHT_ZENITH.g), maxf(z.b, NIGHT_ZENITH.b)) \
			if e < 0.0 else z
	if rich and e < -2.0:
		# Past blue hour the horizon turns to the town's glow.
		var night := 1.0 - smoothstep(-12.0, -4.0, e)
		l.horizon = (l.horizon as Color).lerp(NIGHT_GLOW, night)
		l.fog_color = (l.fog_color as Color).lerp(NIGHT_GLOW.darkened(0.3), night)
		var dark := 1.0 - smoothstep(-10.0, -2.0, e)
		l.shade_color = (l.shade_color as Color).lerp(NIGHT_SHADE, dark)
		l.shade_energy = float(l.shade_energy) * lerpf(1.0, NIGHT_FILL, dark)
	return l


## How the eye (or a camera) opens up as daylight fades: light on open
## ground (sun on flat land plus skylight, in SkyLight's tuned strengths),
## against the tuned 40-degree look, to the power 0.6: adaptation only
## partly makes up the difference. Brighter after sunrise and before
## sunset, a touch darker at summer noon; at night the dark stays dark.
static func exposure(e: float, sun: float, shade: float) -> float:
	var at40 := 1.7 * sin(deg_to_rad(40.0)) + 0.62
	var now := 1.7 * sun * maxf(sin(deg_to_rad(e)), 0.0) + 0.62 * shade
	return lerpf(1.0, clampf(pow(at40 / now, 0.6), 0.92, 2.0), smoothstep(-4.0, 2.0, e))


## Direct sunlight's colour temperature at height `e` (degrees).
static func sun_kelvin(e: float) -> float:
	var t: Array = SUN_KELVIN
	if e <= t[0][0]:
		return t[0][1]
	for i in range(1, t.size()):
		if e <= t[i][0]:
			return lerpf(t[i - 1][1], t[i][1], (e - t[i - 1][0]) / (t[i][0] - t[i - 1][0]))
	return t[t.size() - 1][1]


## Strength of direct sunlight at height `e`, relative to 40 degrees up.
## Meinel and Meinel's clear-air fit, I = 0.7 ^ (AM ^ 0.678) with the
## Kasten and Young air mass, then softened by a square root the way an
## eye or camera adapts (the game has no exposure change of its own): a
## real sunset sun is about 30 times dimmer than at noon, and looks about a
## sixth as bright. It fades as the sun's disc slips under the horizon.
static func sun_strength(e: float) -> float:
	var at40 := pow(0.7, pow(air_mass(40.0), 0.678))
	var now := pow(0.7, pow(air_mass(maxf(e, 0.0)), 0.678))
	return sqrt(now / at40) * smoothstep(-0.8, 1.0, e)


## How many atmospheres of air sunlight crosses at height `e` (degrees):
## Kasten and Young (1989). 1 overhead, about 38 at the horizon.
static func air_mass(e: float) -> float:
	return 1.0 / (sin(deg_to_rad(e)) + 0.50572 * pow(e + 6.07995, -1.6364))


## A blackbody's colour at `kelvin`, scaled so its brightest channel is 1
## (Tanner Helland's fit to the blackbody curve, 2012). 6,600 K is white.
static func kelvin_color(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var r := 255.0
	var g := 0.0
	var b := 255.0
	if t > 66.0:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	else:
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0)


static func _sky_row(e: float) -> Array:
	var t: Array = SKY
	if e <= t[0][0]:
		return t[0].slice(1)
	for i in range(1, t.size()):
		if e <= t[i][0]:
			var a: Array = t[i - 1]
			var b: Array = t[i]
			var f := smoothstep(a[0], b[0], e)
			return [a[1].lerp(b[1], f), a[2].lerp(b[2], f), a[3].lerp(b[3], f), lerpf(a[4], b[4], f)]
	return t[t.size() - 1].slice(1)
