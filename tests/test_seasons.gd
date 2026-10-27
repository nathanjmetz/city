extends SceneTree
## Run: godot --headless -s tests/test_seasons.gd

var _failed := false


func _init() -> void:
	# A month is a day and a day is an hour (docs/spec-month-is-a-day.md):
	# a calendar day is 2 real minutes, months have their real lengths.
	var day := Seasons.TICKS_PER_DAY
	_check(day == 2 * 60 * CitySim.TICKS_PER_SECOND, "a calendar day is 2 real minutes")
	_check(Seasons.month(0) == 5 and Seasons.day(0) == 1, "calendar tick 0 is May 1")
	_check(Seasons.weekday(0) == 6, "May 1, 2027 is a Saturday")
	_check(Seasons.month(day * 30) == 5 and Seasons.month(day * 31) == 6 and Seasons.day(day * 31) == 1,
		"May has 31 days, then June 1")
	_check(Seasons.month(day * 365) == 5 and Seasons.year(day * 365) == 2, "a year is 365 days")
	_check(Seasons.month(day * (31 + 30 + 31 + 31 + 30 + 31 + 30 + 31)) == 1, "January comes 245 days in")
	var june := Seasons.tick_at(5.0)
	_check(Seasons.month(june) == 6 and Seasons.day(june) == 1 and absf(Seasons.months(june) - 5.0) < 0.001,
		"tick_at finds June 1")
	_check(absf(30.0 * day / CitySim.TICKS_PER_SECOND / 60.0 - 60.0) < 0.01, "a 30-day month takes an hour")
	# A town from the old calendar (a month a sim day) keeps its date.
	var old_tick := 50 * Seasons.OLD_TICKS_PER_MONTH + 720  # mid-July of year 5 on the old calendar
	var off := Seasons.offset_from_old(old_tick)
	_check(absf(Seasons.months(old_tick + off) - (Seasons.START_MONTH + 50.5)) < 0.01, "an old town's date carries over")
	_check(Seasons.pace_year(old_tick) == 5 and Seasons.pace_month(old_tick) == 7, "pace years keep the old calendar's count")
	# A new town opens on Friday May 7 in a bright mid-morning, not at
	# sunrise on the 1st (the critic, 2026-10-27: a dark purple first map),
	# with its own clock still at 0 so it earns and builds at the same pace.
	var fresh := CitySim.new()
	_check(fresh.tick_count == 0 and Seasons.month(fresh.calendar_tick()) == 5
		and Seasons.day(fresh.calendar_tick()) == 7 and Seasons.weekday(fresh.calendar_tick()) == 5,
		"a new town starts on Friday May 7 (%d/%d)" % [Seasons.month(fresh.calendar_tick()), Seasons.day(fresh.calendar_tick())])
	_check(fresh.sky_hour() >= 9.0 and fresh.sky_hour() <= 10.5,
		"a new town opens in mid-morning (sky hour %.2f)" % fresh.sky_hour())
	var fresh_back := CitySim.new()
	fresh_back.from_dict(JSON.parse_string(JSON.stringify(fresh.to_dict())))
	_check(fresh_back.calendar_tick() == fresh.calendar_tick() and fresh_back.calendar_from == 0,
		"and saves and reloads on the same date")
	var sim := CitySim.new()
	sim.tick_count = day * 40 + 30
	var t := sim.clock()
	# 40 days after May 7 is June 16, a Wednesday.
	_check(t.month == 6 and t.year == 1 and Seasons.day(sim.calendar_tick()) == 16 and Seasons.weekday(sim.calendar_tick()) == 3,
		"the clock shows the calendar's month and year (%s)" % str(t))
	# The sky: sunrise on the 1st, sunset 50 minutes into a 60-minute month.
	var rise := SunPath.crossings(SunPath.day_of_year(5.0), SunPath.dst_game(5.0))
	_check(absf(SkyClock.hour(5.0) - rise.x) < 0.01, "the sun rises on the 1st")
	var at_sunset := 5.0 + SkyClock.DAY_SHARE
	_check(absf(SkyClock.hour(at_sunset) - SunPath.crossings(SunPath.day_of_year(at_sunset), true).y) < 0.01,
		"and sets five-sixths of the way through the month")
	_check(SkyLight.sun_position(SkyClock.hour(5.4), 5.4).x > 30.0, "the sun is high mid-month")
	_check(SkyLight.sun_position(SkyClock.hour(5.92), 5.92).x < -12.0, "dark in the month's last days")
	var last := 0.0
	var steady := true
	for i in 600:
		var m := 5.0 + i / 600.0
		var h := fposmod(SkyClock.hour(m) - SkyClock.hour(5.0), 24.0)
		if h + 0.0001 < last:
			steady = false
		last = h
	_check(steady, "the sky's hour only moves forward through the month")
	_check(absf(SkyClock.ticks_per_hour(5.4) * (SunPath.crossings(SunPath.day_of_year(5.4), true).y
		- SunPath.crossings(SunPath.day_of_year(5.4), true).x) - SkyClock.DAY_SHARE * 30 * day) < 1.0,
		"a sky hour's ticks fill the daylight")
	# Saves: the offset keeps; a town saved before it carries its old date.
	var town := CitySim.new()
	town.tick_count = old_tick
	var saved := town.to_dict()
	saved.erase("calendar")
	saved.erase("calendar_from")
	var loaded := CitySim.new()
	loaded.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(loaded.calendar_offset == off and Seasons.month(loaded.calendar_tick()) == 7,
		"an old save keeps its month (%d)" % Seasons.month(loaded.calendar_tick()))
	# Its past keeps the old calendar: the founding reads May of year 1, and
	# something built at the old July of year 2 still reads July of year 2.
	var founded := loaded.calendar_of(0)
	var built := loaded.calendar_of(14 * Seasons.OLD_TICKS_PER_MONTH)
	_check(Seasons.month(founded) == 5 and Seasons.year(founded) == 1
		and Seasons.month(built) == 7 and Seasons.year(built) == 2,
		"an old save's past dates keep the old calendar (founded %d/%d, built %d/%d)"
		% [Seasons.month(founded), Seasons.year(founded), Seasons.month(built), Seasons.year(built)])
	# An old save from before the calendar key also keeps its date when it
	# is young: a town saved on its first day reads May 1, not May 7.
	var young := CitySim.new().to_dict()
	young.erase("calendar")
	young.erase("calendar_from")
	var young_back := CitySim.new()
	young_back.from_dict(JSON.parse_string(JSON.stringify(young)))
	_check(young_back.calendar_tick() == 0 and Seasons.day(young_back.calendar_tick()) == 1,
		"an old save without a calendar still opens on its old date (May %d)" % Seasons.day(young_back.calendar_tick()))
	# A town begun on May 1 before new towns moved to May 7 (saved with a
	# calendar offset of 0) keeps May 1.
	var may1 := CitySim.new().to_dict()
	may1["calendar"] = 0
	var may1_back := CitySim.new()
	may1_back.from_dict(JSON.parse_string(JSON.stringify(may1)))
	_check(may1_back.calendar_offset == 0 and Seasons.day(may1_back.calendar_tick()) == 1,
		"a town begun on May 1 keeps May 1")
	var again := CitySim.new()
	again.from_dict(JSON.parse_string(JSON.stringify(loaded.to_dict())))
	_check(again.calendar_offset == off and again.calendar_from == old_tick
		and again.calendar_of(14 * Seasons.OLD_TICKS_PER_MONTH) == built,
		"and the offset and the switch-over tick are saved from then on")
	# A family business ages on pace years; its sign reads the calendar.
	var pace_sim := CitySim.new()
	_check(Families.since_year(pace_sim, 1) == 2027 and Families.since_year(pace_sim, 3) == 2027,
		"a business begun in pace year 3 says Since 2027 on the calendar (%d)" % Families.since_year(pace_sim, 3))
	# One play speed: pause and play.
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(main_src.contains("const SPEEDS := [0.0, 1.0]"), "one play speed, and pause")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_check(not hud_src.contains("4x speed") and not hud_src.contains("2x speed"), "no 2x or 4x buttons")
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
