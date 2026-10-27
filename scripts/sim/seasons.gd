class_name Seasons
extends RefCounted
## The calendar, worked out from the town's calendar tick alone
## (CitySim.calendar_tick), so nothing extra is sent around a region.
##
## A month is a day and a day is an hour (Nathan 2026-10-26: "every hour you
## see on your screen one day pass, but there's been 1 month of progress"):
## a calendar day is TICKS_PER_DAY ticks (2 real minutes), months have their
## real 28 to 31 days, and each month is one sunrise-to-sunrise in the sky
## (SkyClock), about an hour. A year is 365
## game days, about 12 real hours, and each season about 3. Calendar tick 0
## is May 1, 2027, but a new city starts on May 7 (START_DAY), in a bright
## mid-morning. There are no leap years: February always has 28 days, so
## weekdays drift from a real calendar by a day after each February 29.
##
## The town itself runs on its own clock, untouched: a sim day is still
## 24 * CitySim.TICKS_PER_HOUR ticks (2.4 real minutes) and the budget
## settles once each (Balance still calls that "a month"), so a town earns
## and builds at the pace it always did. Only the calendar and the sky on
## top of it changed. Lifecycles counted in years (family businesses) keep
## that pace too: pace_year() is the old calendar's year, 12 sim days.
##
## Benchmark: what each season looks like is benchmarked against southern
## Indiana: green by mid-April, leaves turning in October and down by
## mid-November, snow cover from mid-December into early March. There is no
## weather: no rain, no falling snow.

## A calendar day: 2 real minutes, so a 30-day month is an hour.
const TICKS_PER_DAY := 1200
## Month a new city starts in, counted from 0 (January). Calendar tick 0 is
## its 1st, so sunrise falls on the 1st (SkyClock).
const START_MONTH := 4
## Day of START_MONTH a new city starts on. Starting on the 1st opened a new
## town at sunrise, a dark purple map for its first minutes (the critic,
## 2026-10-27); the 7th puts the sky near 9:50 am. Only the calendar moves
## (CitySim.calendar_offset): the town's own clock still starts at tick 0,
## so it builds and earns at the same pace, and towns begun before this keep
## their date.
const START_DAY := 7
## The calendar offset a new city starts with: START_DAY's first tick.
const NEW_TOWN_OFFSET := (START_DAY - 1) * TICKS_PER_DAY
const NAMES := ["Winter", "Spring", "Summer", "Fall"]
## Days in each month, and days from January 1 to the start of each.
const DAYS_IN := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const DAYS_BEFORE := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
const YEAR_DAYS := 365
## The calendar before 2026-10-27 ran a month a sim day; an older town's
## date is carried over from it (CitySim.from_dict), and pace_year counts on
## it.
const OLD_TICKS_PER_MONTH := 24 * CitySim.TICKS_PER_HOUR
## Marion, Indiana (Grant County): sets how high the sun climbs and how long
## days are.
const LATITUDE := 40.5
## Snow cover on screen right now (0 to 1), set by DayNight each frame, for
## views that change with it (plows on the trucks).
static var snow_now := 0.0


## Months since January 1 of the first year, with the fraction through the
## current month: 4.5 is the middle of May. `tick` is a calendar tick
## (CitySim.calendar_tick); fractions of a tick are fine.
static func months_at(tick: float) -> float:
	var d: float = DAYS_BEFORE[START_MONTH] + tick / TICKS_PER_DAY
	var y := floorf(d / YEAR_DAYS)
	var r := d - y * YEAR_DAYS
	var m := 11
	while m > 0 and r < DAYS_BEFORE[m]:
		m -= 1
	return y * 12.0 + m + (r - DAYS_BEFORE[m]) / DAYS_IN[m]


static func months(tick: int) -> float:
	return months_at(tick)


## The month, 1 to 12.
static func month(tick: int) -> int:
	return int(fposmod(floorf(months(tick)), 12.0)) + 1


## Year number, starting at 1.
static func year(tick: int) -> int:
	return int(floorf(months(tick) / 12.0)) + 1


## Day of the month, 1 to 31.
static func day(tick: int) -> int:
	var r: float = fposmod(DAYS_BEFORE[START_MONTH] + floorf(float(tick) / TICKS_PER_DAY), YEAR_DAYS)
	return int(r) - DAYS_BEFORE[month(tick) - 1] + 1


## Day of the week, 0 Sunday to 6 Saturday: May 1, 2027 was a Saturday.
static func weekday(tick: int) -> int:
	return int(fposmod(6.0 + floorf(float(tick) / TICKS_PER_DAY), 7.0))


## The calendar tick a months value falls on (the other way from months_at).
static func tick_at(m: float) -> int:
	var y := floorf(m / 12.0)
	var mi := int(floorf(m) - y * 12.0)
	var d: float = y * YEAR_DAYS + DAYS_BEFORE[mi] + (m - floorf(m)) * DAYS_IN[mi] - DAYS_BEFORE[START_MONTH]
	return roundi(d * TICKS_PER_DAY)


## A town saved on the old calendar keeps its date: the calendar offset that
## puts `tick` on the same months value the old calendar had it on.
static func offset_from_old(tick: int) -> int:
	return tick_at(START_MONTH + float(tick) / OLD_TICKS_PER_MONTH) - tick


## The old calendar's year (12 sim days, about 29 real minutes) for a sim
## tick (CitySim.tick_count, no calendar offset): how lifecycles that
## should be seen in a session count their years (family businesses and
## their signs, historical markers), and the "month" (one sim day) they turn
## over on.
static func pace_year(tick: int) -> int:
	return int(floorf((START_MONTH + float(tick) / OLD_TICKS_PER_MONTH) / 12.0)) + 1


static func pace_month(tick: int) -> int:
	return int(fposmod(START_MONTH + floorf(float(tick) / OLD_TICKS_PER_MONTH), 12.0)) + 1


## The first sim tick of a pace year (0 for years before the town began).
static func pace_tick(y: int) -> int:
	return maxi(0, ((y - 1) * 12 - START_MONTH) * OLD_TICKS_PER_MONTH)


## 0 winter, 1 spring, 2 summer, 3 fall (meteorological: Dec-Feb is winter).
static func season(m: float) -> int:
	return int(fposmod(floorf(m) + 1.0, 12.0) / 3.0)


## How the land looks at a point in the year (m from months(), any year):
##   snow: ground covered (0 bare to 1 deep cover)
##   autumn: leaves turned to fall colour
##   bare: leaves down on the broadleaf trees
##   spring: fresh new green and blossom
##   dry: grass gone dormant and tan
static func look(m: float) -> Dictionary:
	var y := fposmod(m, 12.0)
	# Snow comes in mid-December and is gone by mid-March.
	var snow := _ramp(y, 11.4, 11.8) if y > 6.0 else 1.0 - _ramp(y, 2.1, 2.6)
	# Leaves turn through October and drop in early November; the buds
	# break in mid-April.
	var autumn := _ramp(y, 8.8, 9.6) * (1.0 - _ramp(y, 10.6, 11.0))
	var bare := _ramp(y, 10.2, 10.8) if y > 6.0 else 1.0 - _ramp(y, 3.2, 3.9)
	var spring := _ramp(y, 3.2, 3.8) * (1.0 - _ramp(y, 5.0, 5.8))
	# Cool-season grass (fescue, bluegrass) stays green into December in
	# Indiana: early November's frosts only touch it, it goes dormant in the
	# first half of December and greens up in April (the critic, 2026-10-26:
	# browning from mid-October made the town read as desert for 4.5
	# months). Shaders turn this into each kind of grass's own look: town
	# lawns only go a muted olive.
	var dry := maxf(0.35 * _ramp(y, 10.0, 10.6), _ramp(y, 11.0, 11.5)) if y > 6.0 else 1.0 - _ramp(y, 2.8, 3.6)
	dry = maxf(dry, 0.3 * _ramp(y, 6.8, 7.4) * (1.0 - _ramp(y, 8.4, 9.0)))  # late-summer heat
	return {"snow": snow, "autumn": autumn, "bare": bare, "spring": spring, "dry": dry}


## The summer look, for when seasons are switched off.
static func summer() -> Dictionary:
	return look(6.5)


static func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)
