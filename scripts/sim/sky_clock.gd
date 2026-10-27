class_name SkyClock
extends RefCounted
## The sky's time of day: one sunrise to sunrise per calendar month, about a
## real hour (Nathan 2026-10-26: "a month is a day and a day is an hour…
## 50-minute day and a 10-minute nighttime"). The sun comes up on the 1st,
## crosses the sky through the month and sets with a sixth of the month
## left; that last sixth is the night, a natural break about once an hour.
##
## Everything about the look of time follows this hour: the sun, moon and
## stars, streetlights and lit windows, how many cars and people are out,
## and day or night sounds (CitySim.sky_hour). The town's own schedules
## (school buses, crews, the budget) keep the sim clock (CitySim.clock).
##
## The hours are Marion's real ones for the date (SunPath): sunrise and
## sunset move through the year, so June's daylight crosses more of the
## clock than December's, but either way it fills the same 50 minutes.

## Share of the month the sun is up: 50 minutes of a 60-minute month.
const DAY_SHARE := 50.0 / 60.0
## How much longer dusk and dawn last than the middle of the night (0 is
## even): the night slows down near sunset and sunrise so the light fades
## over a minute or two instead of seconds, and hurries through midnight.
const NIGHT_EASE := 0.8


## Local clock hour (0 to 24, fractional) in the sky for a months value
## (Seasons.months_at): the fraction through the month says how far
## through its one day the sky is.
static func hour(months: float) -> float:
	var f := months - floorf(months)
	var day := SunPath.day_of_year(months)
	var c := SunPath.crossings(day, SunPath.dst_game(months))
	var light := c.y - c.x
	if f < DAY_SHARE:
		return c.x + f / DAY_SHARE * light
	var u := (f - DAY_SHARE) / (1.0 - DAY_SHARE)
	u -= NIGHT_EASE * sin(TAU * u) / TAU
	return fposmod(c.y + u * (24.0 - light), 24.0)


## Ticks one daylight hour of the sky lasts on that date (about 2,100 in a
## 30-day month, 3.5 real minutes): how long a stay that should end at a
## sky hour (back from work at 5 pm) lasts.
static func ticks_per_hour(months: float) -> float:
	var day := SunPath.day_of_year(months)
	var c := SunPath.crossings(day, SunPath.dst_game(months))
	var m := mini(int(fposmod(months, 12.0)), 11)
	return DAY_SHARE * Seasons.DAYS_IN[m] * Seasons.TICKS_PER_DAY / (c.y - c.x)


## The months value in `month` (1 to 12) of game year `year` (never before
## the town begins) whose sky shows `hour`: for pictures and tests that want
## a town at a date and time.
static func at(month: int, hour_wanted: float, year := 2) -> float:
	var base := (year - 1) * 12.0 + month - 1
	if base < Seasons.START_MONTH:
		base += 12.0
	var best := base
	var err := 99.0
	for i in 1440:
		var m := base + i / 1440.0
		var e := absf(fposmod(hour(m) - hour_wanted + 12.0, 24.0) - 12.0)
		if e < err:
			err = e
			best = m
	return best
