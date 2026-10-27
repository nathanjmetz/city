class_name SunPath
extends RefCounted
## Where the sun is over Grant County, Indiana, for a date and a clock time,
## and when it rises and sets. Formulas: NOAA Global Monitoring Laboratory,
## "General Solar Position Calculations" (the fractional-year series for the
## equation of time and the sun's declination), and the refraction fit from
## NOAA's solar calculator spreadsheet. Good to about a minute of time and a
## few tenths of a degree, far finer than a shadow on screen can show.
## Sources and checks: docs/daylight.md.
##
## Clock times are local: Eastern Standard Time, or Eastern Daylight Time
## (one hour later) while daylight saving is on.

## Marion, Indiana, the county seat (degrees; west is negative).
const LATITUDE := Seasons.LATITUDE
const LONGITUDE := -85.66
## Eastern Standard Time, hours from UTC.
const STANDARD_ZONE := -5.0
## Sunrise and sunset: the sun's top edge on the horizon, with the air
## bending its light (centre 0.833 degrees below).
const HORIZON := -0.833
## Civil twilight ends with the sun 6 degrees down: blue hour, then dark.
const CIVIL := -6.0
## Daylight saving on the game's calendar, in months from January (see
## Seasons.months): US clocks change in the second week of March and the
## first of November. A month is one day and night of the sky (SkyClock),
## so the game changes its clocks between months: on for March through
## October. A month starts at sunrise, so the clock hour jumps at that dawn
## (the sun itself doesn't move); a real date would move it mid-morning.
const DST_ON := 2.0
const DST_OFF := 10.0
## On a real calendar: March 10 and November 3, the middle of the weeks the
## clocks can change in (day of the year, 1 = January 1).
const DST_ON_DAY := 69
const DST_OFF_DAY := 307


## Day of the year (1 = January 1; fractional) for the game's months value.
static func day_of_year(months: float) -> float:
	var m := fposmod(months, 12.0)
	var i := mini(int(m), 11)
	return Seasons.DAYS_BEFORE[i] + (m - i) * Seasons.DAYS_IN[i] + 1.0


## The game's months value (0 = January 1) for a day of the year.
static func months_of(day: float) -> float:
	var d := clampf(day - 1.0, 0.0, Seasons.YEAR_DAYS - 0.0001)
	var i := 11
	while i > 0 and d < Seasons.DAYS_BEFORE[i]:
		i -= 1
	return i + (d - Seasons.DAYS_BEFORE[i]) / Seasons.DAYS_IN[i]


## Whether the game's clocks are on daylight saving time.
static func dst_game(months: float) -> bool:
	var m := fposmod(months, 12.0)
	return m >= DST_ON and m < DST_OFF


## Whether a real day of the year falls in daylight saving time.
static func dst_day(day: float) -> bool:
	return day >= DST_ON_DAY and day < DST_OFF_DAY


## The sun's height above the horizon (x, degrees, as seen: refraction
## included) and its compass bearing (y, degrees: 0 north, 90 east, 180
## south), on day of the year `day` at local clock time `hour`.
static func position(day: float, hour: float, dst: bool) -> Vector2:
	var g := _year_angle(day, hour)
	var decl := declination(g)
	var lat := deg_to_rad(LATITUDE)
	var ha := deg_to_rad(hour_angle(g, hour, dst))
	var elev := asin(clampf(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha), -1.0, 1.0))
	var az := atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat)) + PI
	var e := rad_to_deg(elev)
	return Vector2(e + refraction(e), fposmod(rad_to_deg(az), 360.0))


## The game's sun: its date and clock from the months value and the hour.
static func position_game(months: float, hour: float) -> Vector2:
	return position(day_of_year(months), hour, dst_game(months))


## Clock time (hours) the sun is highest.
static func solar_noon(day: float, dst: bool) -> float:
	var g := _year_angle(day, 12.0)
	var zone := STANDARD_ZONE + (1.0 if dst else 0.0)
	return (720.0 - 4.0 * LONGITUDE - equation_of_time(g) + 60.0 * zone) / 60.0


## Clock times (hours) the sun's centre crosses `height` degrees, rising (x)
## and setting (y). Sunrise and sunset by default; CIVIL for the ends of
## dawn and dusk. NAN both ways if it never gets that high or low that day.
static func crossings(day: float, dst: bool, height := HORIZON) -> Vector2:
	var noon := solar_noon(day, dst)
	var decl := declination(_year_angle(day, noon))
	var lat := deg_to_rad(LATITUDE)
	var c := (sin(deg_to_rad(height)) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
	if absf(c) > 1.0:
		return Vector2(NAN, NAN)
	var half := rad_to_deg(acos(c)) / 15.0
	return Vector2(noon - half, noon + half)


## Fractional year, radians (NOAA): the hour shifts it by up to half a day.
static func _year_angle(day: float, hour: float) -> float:
	return TAU / 365.0 * (day - 1.0 + (hour - 12.0) / 24.0)


## Equation of time, minutes: how far a sundial runs ahead of the clock's
## even sun (NOAA series).
static func equation_of_time(g: float) -> float:
	return 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
		- 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))


## The sun's declination, radians: its height over the equator (NOAA series).
static func declination(g: float) -> float:
	return 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) \
		+ 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)


## Hour angle, degrees: 0 at solar noon, 15 an hour, negative in the morning.
static func hour_angle(g: float, hour: float, dst: bool) -> float:
	var zone := STANDARD_ZONE + (1.0 if dst else 0.0)
	var true_solar := hour * 60.0 + equation_of_time(g) + 4.0 * LONGITUDE - 60.0 * zone
	return true_solar / 4.0 - 180.0


## How much the air lifts the sun's image, degrees, for a true height `e`
## (NOAA's fit): about 0.57 at the horizon, a minute of arc at 45.
static func refraction(e: float) -> float:
	if e > 85.0:
		return 0.0
	var arcsec := 0.0
	if e > 5.0:
		var t := tan(deg_to_rad(e))
		arcsec = 58.1 / t - 0.07 / pow(t, 3) + 0.000086 / pow(t, 5)
	elif e > -0.575:
		arcsec = 1735.0 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)))
	else:
		arcsec = -20.772 / tan(deg_to_rad(e))
	return arcsec / 3600.0


## A unit vector toward a point in the sky (height, bearing, degrees), in the
## game's axes: x east, y up, z south (north is -Z).
static func toward(p: Vector2) -> Vector3:
	var e := deg_to_rad(p.x)
	var a := deg_to_rad(p.y)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))


## "6:14 am" style, for tests and notes.
static func clock_text(hour: float) -> String:
	var mins := roundi(hour * 60.0)
	var h := int(mins / 60) % 24
	return "%d:%02d %s" % [(h + 11) % 12 + 1, mins % 60, "am" if h < 12 else "pm"]
