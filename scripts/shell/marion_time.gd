class_name MarionTime
extends RefCounted
## The wall clock in Marion, Indiana (America/Indiana/Indianapolis): Eastern
## time, on daylight saving from 2 am on the second Sunday of March to 2 am
## on the first Sunday of November. Godot gives the player's clock as UTC; the
## title screen turns it into Marion's date and hour here, then lights the
## town for that moment (DayNight, SkyLight and the crop calendar).

## Eastern Standard Time, hours from UTC.
const STANDARD := -5
const CUMULATIVE := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]


## Marion's date and time at a Unix time (seconds, UTC): the keys of
## Time.get_datetime_dict_from_unix_time plus `dst` and `second_f` (seconds
## with their fraction).
static func at(unix: float) -> Dictionary:
	var whole := int(floor(unix))
	var dst := is_dst(whole)
	var t := Time.get_datetime_dict_from_unix_time(whole + (STANDARD + (1 if dst else 0)) * 3600)
	t["dst"] = dst
	t["second_f"] = float(t.second) + (unix - float(whole))
	return t


## Whether Marion's clocks are on daylight saving time at a Unix time.
static func is_dst(unix: int) -> bool:
	var year: int = Time.get_datetime_dict_from_unix_time(unix + STANDARD * 3600).year
	return unix >= dst_start(year) and unix < dst_end(year)


## The moment (Unix, UTC) clocks go forward: 2:00 EST, second Sunday of March.
static func dst_start(year: int) -> int:
	return _unix(year, 3, nth_sunday(year, 3, 2), 2 - STANDARD)


## The moment clocks go back: 2:00 EDT, first Sunday of November.
static func dst_end(year: int) -> int:
	return _unix(year, 11, nth_sunday(year, 11, 1), 2 - (STANDARD + 1))


static func _unix(year: int, month: int, day: int, hour: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": hour, "minute": 0, "second": 0}))


## Day of the month of the nth Sunday.
static func nth_sunday(year: int, month: int, n: int) -> int:
	var first: int = Time.get_datetime_dict_from_unix_time(_unix(year, month, 1, 0)).weekday  # 0 is Sunday
	return 1 + (7 - first) % 7 + 7 * (n - 1)


## The Unix time of a Marion date and hour (the clock time on the wall, so
## a repeated or skipped hour takes the daylight time side).
static func to_unix(year: int, month: int, day: int, hour: float) -> float:
	var local := float(_unix(year, month, day, 0)) + hour * 3600.0
	var as_edt := local - (STANDARD + 1) * 3600.0
	if is_dst(int(floor(as_edt))):
		return as_edt
	return local - STANDARD * 3600.0


## The game's `months` value (0 is January 1, see Seasons.months) for a
## Marion date and time: the sun, the leaves, the snow and the crops all go
## by it.
static func months_of(t: Dictionary) -> float:
	var leap: bool = int(t.year) % 4 == 0 and (int(t.year) % 100 != 0 or int(t.year) % 400 == 0)
	var ordinal: int = int(CUMULATIVE[int(t.month) - 1]) + int(t.day) + (1 if leap and int(t.month) > 2 else 0)
	var frac: float = (float(t.hour) + float(t.minute) / 60.0 + float(t.get("second_f", t.second)) / 3600.0) / 24.0
	return SunPath.months_of(float(ordinal) + frac)


## The hour of day (0 to 24, fractional) on the wall clock.
static func hour_of(t: Dictionary) -> float:
	return float(t.hour) + float(t.minute) / 60.0 + float(t.get("second_f", t.second)) / 3600.0


## `months`, nudged so the game's own daylight saving (changes at its month
## boundaries, SunPath.dst_game) agrees with Marion's: the clock hour is
## then right, and the date moves at most about a week and a half.
static func months_for_sky(t: Dictionary) -> float:
	var m := months_of(t)
	if SunPath.dst_game(m) == bool(t.dst):
		return m
	# Marion still on daylight time after the game's clocks went back
	# (October 27 to November 1), or still on standard time after the
	# game's went forward (February 26 to March 8).
	return (SunPath.DST_OFF if bool(t.dst) else SunPath.DST_ON) - 0.001
