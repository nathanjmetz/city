extends SceneTree
## The title screen's clock and town: Marion's wall clock with daylight
## saving, the date the land is lit for, and the light replay of the town's
## day (busy at rush hour, nearly empty at night, capped by tier).
## Run: godot --headless -s tests/test_menu_life.gd

var _failed := false


func _initialize() -> void:
	_clock()
	_sky_date()
	_town()
	quit(1 if _failed else 0)


func _clock() -> void:
	var t := MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-10-25T12:00:00")))
	_check(t.hour == 8 and t.dst, "Oct 25 2026, noon UTC, is 8 am on daylight time (got %d, %s)" % [t.hour, t.dst])
	t = MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-12-15T12:00:00")))
	_check(t.hour == 7 and not t.dst, "Dec 15, noon UTC, is 7 am on standard time")
	# 2026: second Sunday of March is the 8th, first Sunday of November the 1st.
	t = MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-03-08T06:59:59")))
	_check(t.hour == 1 and t.minute == 59 and not t.dst, "1:59 am on March 8 is still standard time")
	t = MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-03-08T07:00:00")))
	_check(t.hour == 3 and t.dst, "2 am March 8 jumps to 3 am")
	t = MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-11-01T05:59:59")))
	_check(t.hour == 1 and t.dst, "1:59 am Nov 1 is still daylight time")
	t = MarionTime.at(float(Time.get_unix_time_from_datetime_string("2026-11-01T06:00:00")))
	_check(t.hour == 1 and not t.dst, "2 am Nov 1 falls back to 1 am")
	var u := MenuLife.parse("2026-12-15T23:30")
	t = MarionTime.at(u)
	_check(t.day == 15 and t.hour == 23 and t.minute == 30, "a forced 11:30 pm reads back as 11:30 pm")
	u = MenuLife.parse("2026-07-15 06:00")
	t = MarionTime.at(u)
	_check(t.hour == 6 and t.dst, "a forced summer 6 am reads back")


func _sky_date() -> void:
	var t := MarionTime.at(float(MarionTime.to_unix(2026, 7, 15, 12.0)))
	_check(absf(SunPath.day_of_year(MarionTime.months_of(t)) - 196.5) < 0.6, "July 15 noon is day 196")
	# Between the game's clocks going back (Oct 27) and the real ones (Nov 1)
	# the sky still has to be on daylight time.
	for day in [28, 30]:
		t = MarionTime.at(float(MarionTime.to_unix(2026, 10, day, 15.0)))
		_check(SunPath.dst_game(MarionTime.months_for_sky(t)) == bool(t.dst), "Oct %d: the sky's clocks match Marion's" % day)
	t = MarionTime.at(float(MarionTime.to_unix(2026, 3, 3, 15.0)))
	_check(SunPath.dst_game(MarionTime.months_for_sky(t)) == bool(t.dst), "March 3: the sky's clocks match Marion's")
	t = MarionTime.at(float(MarionTime.to_unix(2026, 5, 3, 15.0)))
	_check(MarionTime.months_for_sky(t) == MarionTime.months_of(t), "a plain day keeps its own date")


## A fresh title-screen town at a Marion time, run for `steps` steps; the
## most cars and walkers out at once.
func _day(when: String, steps: int) -> Vector2i:
	var sim := MenuSim.new()
	sim.from_dict(root.get_node("Session")._read(MenuLife.MENU_TOWN))
	var life := MenuLife.new()
	life.setup(sim, DayNight.new(), when)
	var most := Vector2i.ZERO
	for i in steps:
		life._step()
		most = Vector2i(maxi(most.x, sim.traffic.cars.size()), maxi(most.y, sim.traffic.walkers.size()))
	_check(sim.clock().hour == int(MarionTime.at(Time.get_unix_time_from_system() + life.offset).hour),
		"the town's clock is the wall clock")
	var cap := MenuLife.caps()
	_check(most.x <= cap.x and most.y <= cap.y, "cars and walkers stay under the tier's cap (%s of %s)" % [most, cap])
	return most


func _town() -> void:
	var rush := _day("2026-04-15T08:00", 1500)
	var night := _day("2026-12-15T23:30", 1500)
	print("rush: ", rush, " night: ", night)
	_check(rush.x >= 20 and rush.y >= 20, "people and cars are out at rush hour")
	_check(night.x * 4 <= rush.x and night.y * 4 <= rush.y, "the streets are nearly empty late at night")
	var cap := MenuLife.caps()
	_check(cap.x > 0 and cap.y > 0, "there is a cap on cars and people")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
