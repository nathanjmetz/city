extends SceneTree
## Run: godot --headless -s tests/test_seasons.gd

var _failed := false


func _init() -> void:
	var day := Seasons.TICKS_PER_DAY
	_check(Seasons.month(0) == 5, "a new city starts in May")
	_check(Seasons.month(day * 12) == 5 and Seasons.year(day * 12) == 2, "a year is 12 game days")
	_check(Seasons.month(day * 8) == 1, "January comes 8 days in")
	var sim := CitySim.new()
	sim.tick_count = day * 3 + 60 * 4
	var t := sim.clock()
	_check(t.month == 8 and t.year == 1 and t.hour == 10, "the clock shows the season's month (%s)" % str(t))
	# What the land looks like through the year.
	var winter := Seasons.look(Seasons.START_MONTH + 8.5)  # mid January
	_check(winter.snow == 1.0 and winter.bare == 1.0, "snow and bare trees in January")
	var july := Seasons.look(6.5)
	_check(july.snow == 0.0 and july.bare == 0.0 and july.autumn == 0.0, "green, snow-free July")
	_check(Seasons.look(9.5).autumn > 0.8, "fall colour in mid October")
	_check(Seasons.look(3.6).spring > 0.5, "fresh spring green in April")
	_check(Seasons.season(0.5) == 0 and Seasons.season(4.5) == 1 and Seasons.season(6.5) == 2 \
		and Seasons.season(9.5) == 3 and Seasons.season(11.5) == 0, "season names follow the months")
	_check(Seasons.look(18.5).hash() == july.hash(), "every year looks the same")
	# The sun over Petersburg, Indiana.
	var noon_june := SkyLight.sun_position(13.8, 5.7)
	_check(noon_june.x > 70.0 and noon_june.x < 76.0, "June noon sun about 75 degrees up (%.1f)" % noon_june.x)
	_check(absf(noon_june.y - 180.0) < 5.0, "noon sun due south (%.1f)" % noon_june.y)
	var noon_dec := SkyLight.sun_position(12.8, 11.7)
	_check(noon_dec.x > 25.0 and noon_dec.x < 31.0, "December noon sun about 28 degrees up (%.1f)" % noon_dec.x)
	_check(SkyLight.sun_position(1.0, 6.5).x < -20.0, "dark at 1 AM")
	_check(SkyLight.sun_position(7.0, 6.5).y < 90.0 + 30.0, "morning sun in the east")
	_check(SkyLight.sun_position(20.5, 6.5).x > 0.0 and SkyLight.sun_position(21.5, 6.5).x < 0.0,
		"July sunset just after 9 PM")
	_check(DayNight.window_share(20.0) > DayNight.window_share(3.0), "more windows lit in the evening than at 3 AM")
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
