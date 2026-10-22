class_name Seasons
extends RefCounted
## The year, worked out from the tick count alone, so every player in a
## region sees the same season without anything extra to save or send.
##
## One game day settles one month of budget (see Balance), so the calendar
## moves on a month a day: a year is 12 days, about 29 real minutes at
## normal speed, and each season about 7. A new city starts in May.
##
## Benchmark: Cities: Skylines 2 runs its months on the same clock as its
## budget and shows the season on the land. What each season looks like is
## benchmarked against southern Indiana: green by mid-April, leaves turning
## in October and down by mid-November, snow cover from mid-December into
## early March. There is no weather: no rain, no falling snow.

const TICKS_PER_DAY := 24 * 60 / CitySim.MINUTES_PER_TICK
## Month a new city starts in, counted from 0 (January).
const START_MONTH := 4
const NAMES := ["Winter", "Spring", "Summer", "Fall"]
## Petersburg, Indiana: sets how high the sun climbs and how long days are.
const LATITUDE := 38.5


## Months since January of the first year, with the fraction through the
## current one: 4.5 is the middle of May.
static func months(tick: int) -> float:
	return START_MONTH + float(tick) / TICKS_PER_DAY


## The month, 1 to 12.
static func month(tick: int) -> int:
	return int(fposmod(floorf(months(tick)), 12.0)) + 1


## Year number, starting at 1.
static func year(tick: int) -> int:
	return int(floorf(months(tick) / 12.0)) + 1


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
	# Lawns brown off after the first hard frosts and green up in April.
	var dry := _ramp(y, 9.6, 10.4) if y > 6.0 else 1.0 - _ramp(y, 2.8, 3.6)
	dry = maxf(dry, 0.3 * _ramp(y, 6.8, 7.4) * (1.0 - _ramp(y, 8.4, 9.0)))  # late-summer heat
	return {"snow": snow, "autumn": autumn, "bare": bare, "spring": spring, "dry": dry}


## The summer look, for when seasons are switched off.
static func summer() -> Dictionary:
	return look(6.5)


static func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)
