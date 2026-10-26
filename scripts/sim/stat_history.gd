class_name StatHistory
extends RefCounted
## The town's numbers over time, for the charts behind the top bar's stats
## (Brawn, 2026-10-23: every readout opens a chart).
##
## Real reference: Cities: Skylines 2's info panels and statistics graph
## (population, jobs, money, demand over time), and the monthly series a
## real town tracks (Census population estimates, BLS local unemployment,
## INDOT traffic counts, the clerk-treasurer's cash balance).
##
## Two series, so short and long views both read well: one sample every sim
## hour (6 real seconds) for the last 12 sim days, and one every sim day
## (2.4 real minutes) for the town's whole life. The charts label them on the
## calendar (Seasons: a day is 2 real minutes): spans of a day, two weeks
## and five months. Nothing here changes the sim's outcome, so neighbors
## never check it.

## What each sample holds, in order.
const FIELDS := ["pop", "jobs", "workers", "employed", "cars", "flow", "dem_h", "dem_s", "dem_i", "money", "net", "unserved"]
## Hourly samples kept: a game year (12 game days of 24 hours).
const HOURS_KEPT := 24 * 12
## Monthly samples kept: a century.
const MONTHS_KEPT := 1200

## [[tick, value per FIELDS...], ...], oldest first.
var hourly := []
var monthly := []


static func sample_of(sim) -> Array:
	var s: Dictionary = sim.stats
	return [sim.tick_count, int(s.get("population", 0)), int(s.get("jobs", 0)), int(s.get("workers", 0)),
		int(s.get("employed", 0)), sim.traffic.cars.size(), snappedf(sim.traffic.flow, 0.001),
		snappedf(float(sim.demand.get(ZoneMap.Zone.RESIDENTIAL, 0.0)), 0.001),
		snappedf(float(sim.demand.get(ZoneMap.Zone.COMMERCIAL, 0.0)), 0.001),
		snappedf(float(sim.demand.get(ZoneMap.Zone.INDUSTRIAL, 0.0)), 0.001),
		int(sim.economy.money), sim.economy.monthly_net(), sim.unserved_count()]


## On the hour (the tick calls it); the first hour of each game day also
## closes a month.
func hour(sim) -> void:
	var s := sample_of(sim)
	hourly.append(s)
	if hourly.size() > HOURS_KEPT:
		hourly = hourly.slice(hourly.size() - HOURS_KEPT)
	if monthly.is_empty() or sim.tick_count % (24 * CitySim.TICKS_PER_HOUR) == 0:
		monthly.append(s)
		if monthly.size() > MONTHS_KEPT:
			monthly = monthly.slice(monthly.size() - MONTHS_KEPT)


## The samples of a span, oldest first, ending with the town as it is now:
## [[tick, value per FIELDS...], ...] (col() finds a field).
## `span` is "month" (the last calendar day, hourly), "year" (the last
## two calendar weeks, hourly), "decade" (about five calendar months, a
## sample a sim day) or "all" (a sample a sim day).
func rows(sim, span: String) -> Array:
	var src: Array = hourly if span in ["month", "year"] else monthly
	var per_day := float(Seasons.TICKS_PER_DAY) / CitySim.TICKS_PER_HOUR
	var n: int = {"month": roundi(per_day), "year": roundi(14 * per_day),
		"decade": roundi(150.0 * Seasons.TICKS_PER_DAY / (24 * CitySim.TICKS_PER_HOUR))}.get(span, src.size())
	var out := src.slice(maxi(src.size() - n, 0))
	var now := sample_of(sim)
	if not out.is_empty() and int(out[-1][0]) == int(now[0]):
		out[-1] = now
	else:
		out.append(now)
	return out


## Where a field sits in a row.
static func col(field: String) -> int:
	return FIELDS.find(field) + 1


## The value a field had about `ticks` ago (the oldest kept if not that old).
func value_ago(sim, field: String, ticks: int):
	var i := col(field)
	var src: Array = hourly if ticks <= HOURS_KEPT * CitySim.TICKS_PER_HOUR else monthly
	var want: int = sim.tick_count - ticks
	for s in src:
		if int(s[0]) >= want:
			return s[i]
	return null


func to_dict() -> Dictionary:
	return {"hourly": hourly, "monthly": monthly}


func from_dict(d: Dictionary) -> void:
	hourly = _clean(d.get("hourly", []))
	monthly = _clean(d.get("monthly", []))


static func _clean(rows: Array) -> Array:
	var out := []
	for r in rows:
		if r is Array and r.size() == FIELDS.size() + 1:
			var row := [int(r[0])]
			for k in FIELDS.size():
				row.append(float(r[k + 1]) if FIELDS[k] in ["flow", "dem_h", "dem_s", "dem_i"] else int(r[k + 1]))
			out.append(row)
	return out
