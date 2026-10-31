extends SceneTree
## The sun over Grant County against the almanac (docs/daylight.md).
## Run: godot --headless -s tests/test_sun_path.gd

var _failed := false
var _sky: SkyLight
var _frames := 0

const JUNE_21 := 172
const DEC_21 := 355
const MAR_20 := 79


func _initialize() -> void:
	_positions()
	_rise_and_set()
	_shadows()
	_game_calendar()
	_light()
	_sky = SkyLight.new()
	root.add_child(_sky)


## The lit scene: the sun node points where the formulas say.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var june := SunPath.months_of(JUNE_21)
	_sky.set_time(13.0 + 40.0 / 60.0, june)
	var shine := -_sky.sun.global_basis.z  # the way the light travels
	var to_sun := SunPath.toward(SunPath.position_game(june, 13.0 + 40.0 / 60.0))
	_check(shine.dot(-to_sun) > 0.9999, "the scene's sunlight comes from the sun's place (%s)" % str(shine))
	_check(_sky.darkness == 0.0 and _sky.sun.light_energy > 1.0, "full daylight at 1:40 pm in June")
	var noon_color := _sky.sun.light_color
	_sky.set_time(20.0 + 50.0 / 60.0, june)
	_check(_sky.sun.light_color.b < noon_color.b * 0.6, "low evening sun is warmer than midday's")
	_sky.set_time(23.0, june)
	_check(_sky.darkness == 1.0, "dark at 11 pm in June")
	_sky.set_time(13.0, SunPath.months_of(DEC_21))
	_check(_sky.darkness == 0.0, "daylight at 1 pm in December")
	_sky.set_fixed()
	_check(is_equal_approx(_sky.sun.rotation_degrees.x, -SkyLight.SUN_ELEVATION), "day and night off: the fixed sun")
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)
	return true


func _positions() -> void:
	# Summer solstice: highest about 1:45 pm EDT (USNO), 90 - 40.5 + 23.44 = 72.9 degrees up.
	var noon := SunPath.solar_noon(JUNE_21, true)
	_check(absf(noon - (13.0 + 45.0 / 60.0)) < 3.0 / 60.0, "June 21 sun highest about 1:45 pm (%s)" % SunPath.clock_text(noon))
	var p := SunPath.position(JUNE_21, 13.0 + 40.0 / 60.0, true)
	_check(absf(p.x - 72.9) < 0.4, "June 21 at 1:40 pm EDT: 72.9 degrees up, near its highest (%.2f)" % p.x)
	_check(absf(p.y - 180.0) < 6.0, "and nearly due south (%.1f)" % p.y)
	for h in [12.5, 13.0, 14.25, 15.0]:
		_check(SunPath.position(JUNE_21, h, true).x < SunPath.position(JUNE_21, noon, true).x,
			"no higher at %s than at solar noon" % SunPath.clock_text(h))
	# Winter solstice: about 26 degrees at about 12:41 pm EST.
	var dnoon := SunPath.solar_noon(DEC_21, false)
	_check(absf(dnoon - (12.0 + 41.0 / 60.0)) < 3.0 / 60.0, "December 21 sun highest about 12:41 pm (%s)" % SunPath.clock_text(dnoon))
	var d := SunPath.position(DEC_21, dnoon, false)
	_check(absf(d.x - 26.1) < 0.4, "December 21 noon sun 26 degrees up (%.2f)" % d.x)
	# Spring equinox: sun rises nearly due east.
	var r := SunPath.crossings(MAR_20, true)
	var at_rise := SunPath.position(MAR_20, r.x + 0.05, true)
	_check(absf(at_rise.y - 90.0) < 3.0, "March 20 sun rises in the east (%.1f)" % at_rise.y)
	# June sunrise in the northeast, sunset in the northwest.
	var j := SunPath.crossings(JUNE_21, true)
	_check(absf(SunPath.position(JUNE_21, j.x, true).y - 58.0) < 2.5, "June sunrise bearing about 58 degrees")
	_check(absf(SunPath.position(JUNE_21, j.y, true).y - 302.0) < 2.5, "June sunset bearing about 302 degrees")
	_check(absf(SunPath.position(JUNE_21, j.y, true).x - (-0.833 + 0.57)) < 0.2,
		"at sunset the sun's centre shows about a quarter degree under the horizon")
	_check(absf(SunPath.refraction(0.0) - 0.48) < 0.05 and SunPath.refraction(45.0) < 0.02,
		"the air lifts the sun about half a degree at the horizon, almost nothing high up")


## Sunrise, sunset and twilight at 40.50 N, 85.66 W, from the US Naval
## Observatory's table (aa.usno.navy.mil, 2026 dates), to within 3 minutes.
func _rise_and_set() -> void:
	var cases := [
		[JUNE_21, true, 6.0 + 12.0 / 60.0, 21.0 + 17.0 / 60.0, "June 21"],
		[DEC_21, false, 8.0 + 3.0 / 60.0, 17.0 + 19.0 / 60.0, "December 21"],
		[MAR_20, true, 7.0 + 46.0 / 60.0, 19.0 + 55.0 / 60.0, "March 20"],
	]
	for c in cases:
		var t := SunPath.crossings(c[0], c[1])
		_check(absf(t.x - c[2]) < 3.0 / 60.0, "%s sunrise %s (%s)" % [c[4], SunPath.clock_text(c[2]), SunPath.clock_text(t.x)])
		_check(absf(t.y - c[3]) < 3.0 / 60.0, "%s sunset %s (%s)" % [c[4], SunPath.clock_text(c[3]), SunPath.clock_text(t.y)])
	var june := SunPath.crossings(JUNE_21, true)
	var dec := SunPath.crossings(DEC_21, false)
	_check(absf((june.y - june.x) - 15.08) < 0.05, "a June day is about 15 hours 5 minutes (%.2f)" % (june.y - june.x))
	_check(absf((dec.y - dec.x) - 9.27) < 0.05, "a December day is about 9 hours 16 minutes (%.2f)" % (dec.y - dec.x))
	var june_dusk := SunPath.crossings(JUNE_21, true, SunPath.CIVIL).y - june.y
	var mar_dusk := SunPath.crossings(MAR_20, true, SunPath.CIVIL).y - SunPath.crossings(MAR_20, true).y
	_check(absf(june_dusk * 60.0 - 33.0) < 3.0, "June dusk (civil twilight) about 33 minutes (%.0f)" % (june_dusk * 60.0))
	_check(absf(mar_dusk * 60.0 - 27.0) < 3.0, "March dusk about 27 minutes (%.0f)" % (mar_dusk * 60.0))
	var dec_dusk := SunPath.crossings(DEC_21, false, SunPath.CIVIL).y - dec.y
	_check(absf(dec_dusk * 60.0 - 31.0) < 3.0, "December dusk about 31 minutes (%.0f)" % (dec_dusk * 60.0))


## Shadows point away from the sun, as long as the sun is low.
func _shadows() -> void:
	var noon := SunPath.toward(SunPath.position(JUNE_21, SunPath.solar_noon(JUNE_21, true), true))
	_check(noon.z > 0.0 and absf(noon.x) < 0.01, "noon sun to the south (+z), so shadows fall north (-z)")
	var morning := SunPath.toward(SunPath.position(JUNE_21, 8.0, true))
	_check(morning.x > 0.5, "morning sun in the east, so shadows fall west")
	# A 10 m pole's shadow: 10 / tan(height).
	var summer := 10.0 / tan(deg_to_rad(SunPath.position(JUNE_21, 13.0 + 40.0 / 60.0, true).x))
	var winter := 10.0 / tan(deg_to_rad(SunPath.position(DEC_21, 12.7, false).x))
	_check(absf(summer - 3.1) < 0.2, "a 10 m pole casts a 3.1 m shadow at June's midday (%.1f)" % summer)
	_check(absf(winter - 20.5) < 0.5, "and a 20.5 m one at December's (%.1f)" % winter)


## The game's calendar: real month lengths, and the clocks change on
## March 10 and November 3.
func _game_calendar() -> void:
	_check(absf(SunPath.day_of_year(SunPath.months_of(JUNE_21)) - JUNE_21) < 0.001, "months and days of the year agree")
	_check(absf(SunPath.day_of_year(2.0) - 60.0) < 0.001, "March 1 is day 60 (February has 28 days)")
	_check(SunPath.dst_game(5.6) and not SunPath.dst_game(11.6) and not SunPath.dst_game(1.5),
		"summer clocks on daylight saving, winter ones not")
	_check(not SunPath.dst_game(1.999) and SunPath.dst_game(2.0), "spring forward as March begins (in the sky's night)")
	_check(SunPath.dst_game(9.999) and not SunPath.dst_game(10.0), "fall back as November begins")
	_check(SunPath.dst_day(JUNE_21) and not SunPath.dst_day(DEC_21), "real dates: June on daylight saving")
	# Seasons' own sun check uses the same path.
	var june := SunPath.months_of(JUNE_21)
	_check(SkyLight.sun_position(13.7, june) == SunPath.position_game(june, 13.7), "SkyLight uses SunPath")


func _light() -> void:
	var noon := Daylight.at(70.0, 1.0)
	var low := Daylight.at(3.0, 1.0)
	_check(absf(Daylight.sun_strength(40.0) - 1.0) < 0.001, "the 40-degree sun keeps the tuned strength")
	_check(noon.sun_color.b > 0.85 and low.sun_color.b < 0.45 and low.sun_color.g < 0.8,
		"white midday sun, golden near sunset (%s, %s)" % [str(noon.sun_color), str(low.sun_color)])
	_check(Daylight.sun_strength(2.0) < 0.5 and Daylight.sun_strength(-1.0) == 0.0, "the sun dims low down and goes out")
	_check(Daylight.air_mass(90.0) < 1.001 and absf(Daylight.air_mass(0.0) - 38.1) < 0.5, "air mass 1 overhead, 38 at the horizon")
	var k := Daylight.kelvin_color(6600.0)
	_check(k.r > 0.98 and k.g > 0.97 and k.b > 0.97, "6,600 K is white")
	_check(noon.darkness == 0.0 and Daylight.at(-13.0, 0.5).darkness == 1.0, "dark only well after sunset")
	# Real twilight (2026-10-31): civil twilight (to 6 degrees down) keeps
	# the street readable, nautical (to 12) darkens it; the lights still come
	# on at about sunset.
	_check(Daylight.at(-2.0, 0.5).darkness < 0.2 and Daylight.at(-6.0, 0.5).darkness <= 0.25 + 0.001,
		"civil twilight stays light (%.2f at -2, %.2f at -6)" % [Daylight.at(-2.0, 0.5).darkness, Daylight.at(-6.0, 0.5).darkness])
	_check(Daylight.at(-9.0, 0.5).darkness > 0.4 and Daylight.at(-12.0, 0.5).darkness > 0.9, "nautical twilight goes dark")
	_check(Daylight.at(-2.0, 0.5).lights_on > 0.45 and Daylight.at(5.0, 0.5).lights_on == 0.0, "the lights come on around sunset")
	var blue := Daylight.at(-5.0, 0.5)
	_check(blue.zenith.b > blue.zenith.r * 3.0 and blue.stars < 0.3, "blue hour: deep blue sky, few stars yet")
	_check(Daylight.at(-15.0, 0.5).stars > 0.85, "stars out at night")
	_check(Daylight.at(0.0, 0.5).horizon.r > Daylight.at(0.0, 0.5).horizon.b * 2.0, "orange horizon at sunset")
	_check(Daylight.humidity(6.5) > 0.99 and Daylight.humidity(0.5) < 0.01, "humid July, dry January")
	# The desktop's night (rich): navy overhead, the town's glow low down,
	# dark walls; the same light as the browser's by day.
	var rn := Daylight.at(-15.0, 0.5, true)
	var pn := Daylight.at(-15.0, 0.5)
	_check(rn.zenith.b > rn.zenith.r * 2.0 and rn.zenith.v > pn.zenith.v, "desktop night: a navy sky, not black")
	_check(rn.horizon.r > rn.horizon.b and rn.horizon.v > rn.zenith.v, "desktop night: a warm glow over the town")
	_check(rn.shade_energy < pn.shade_energy * 0.5, "desktop night: dark walls, lamps and windows do the lighting")
	_check(str(Daylight.at(40.0, 0.5, true)) == str(Daylight.at(40.0, 0.5))
		and str(Daylight.at(8.0, 1.0, true)) == str(Daylight.at(8.0, 1.0)), "desktop daylight unchanged")
	var darkening := true
	var last := 2.0
	for i in 57:
		var b: float = Daylight.at(8.0 - i * 0.5, 0.5, true).zenith.b
		darkening = darkening and b <= last + 1e-6
		last = b
	_check(darkening, "desktop sky overhead never brightens as the sun sinks")
	var summer := Daylight.at(50.0, 1.0)
	var winter := Daylight.at(50.0, 0.0)
	_check(summer.haze > winter.haze and summer.horizon.b - summer.horizon.r < winter.horizon.b - winter.horizon.r,
		"summer haze: thicker and whiter than winter's")
	_tone_curve()


## The desktop's tone curve (SkyLight._tone): the old contrast above mid
## grey, darks no longer pushed toward black by day, the old line by night.
func _tone_curve() -> void:
	var day := SkyLight.tone_curve(0.0)
	var night := SkyLight.tone_curve(1.0)
	var line := func(x: float) -> float: return 0.5 + (x - 0.5) * SkyLight.TONE_CONTRAST
	var x := func(i: int) -> float: return (i + 0.5) / 256.0
	var bright_same := true
	var night_same := true
	var rising := true
	for i in 256:
		var d := day.get_pixel(i, 0).r
		if x.call(i) >= 0.5:
			bright_same = bright_same and absf(d - line.call(x.call(i))) < 0.002
		night_same = night_same and absf(night.get_pixel(i, 0).r - line.call(x.call(i))) < 0.002
		if i > 0:
			rising = rising and d > day.get_pixel(i - 1, 0).r
	_check(bright_same, "tone curve: a sunny day's contrast kept above mid grey")
	_check(night_same, "tone curve: night keeps the old straight line")
	_check(rising and day.get_pixel(0, 0).r >= 0.0 and day.get_pixel(0, 0).r < 0.005, "tone curve: rises from black")
	# Shade on asphalt or a lawn (about 0.13 out of AgX) kept at least 0.11,
	# where the straight line took it to 0.09.
	_check(day.get_pixel(33, 0).r > 0.11 and night.get_pixel(33, 0).r < 0.1, "tone curve: shade no longer crushed by day")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
