extends SceneTree
## Weather (Nathan, 2026-10-25: "include the weather", with "a simple toggle
## switch"): each day's sky comes from the date alone, so every copy of a
## town sees the same rain; winter brings none (the seasons draw snow), and
## spring and summer rain about as often as Indiana does.
var _fails := 0
var _fog_hours := {}


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	var noon := {"year": 3, "month": 5, "day": 9, "hour": 12, "minute": 0.0}
	_check(Weather.conditions(noon) == Weather.conditions(noon.duplicate()), "the same date and hour always bring the same sky")
	# Ten years of days, counted by month.
	var rainy := {}
	var snowy := {}
	var foggy := {}
	var days := {}
	var max_rain := 0.0
	var fair := 0
	var grey_days := 0
	var partly_days := 0
	var day_hours := 0
	var grey_hours := 0
	var a_fog := {}
	for y in 10:
		for m in range(1, 13):
			for d in range(1, 29):
				days[m] = int(days.get(m, 0)) + 1
				var wet := false
				var flakes := false
				var mist := false
				var day_cover := 0.0
				for h in 24:
					var c := Weather.conditions({"year": y, "month": m, "day": d, "hour": h, "minute": 30.0})
					if h >= 8 and h <= 18:
						day_cover += float(c[0])
						day_hours += 1
						if float(c[0]) >= 0.7:
							grey_hours += 1
					max_rain = maxf(max_rain, float(c[1]))
					if float(c[1]) > 0.0:
						if float(c[3]) > 0.5:
							flakes = true
						else:
							wet = true
					if float(c[2]) > 0.0:
						mist = true
						_fog_hours[h] = true
						if a_fog.is_empty() and y > 0:
							a_fog = {"year": y, "month": m, "day": d, "hour": h, "minute": 30.0}
					if h == 12 and float(c[0]) < 0.5:
						fair += 1
				if day_cover / 11.0 >= 0.65:
					grey_days += 1
				elif day_cover / 11.0 >= 0.3:
					partly_days += 1
				if wet:
					rainy[m] = int(rainy.get(m, 0)) + 1
				if flakes:
					snowy[m] = int(snowy.get(m, 0)) + 1
				if mist:
					foggy[m] = int(foggy.get(m, 0)) + 1
	var winter_rain := int(rainy.get(1, 0)) + int(rainy.get(2, 0))
	_check(winter_rain == 0, "no rain in January or February: it falls as snow (%d rainy days)" % winter_rain)
	_check(int(snowy.get(12, 0)) > int(rainy.get(12, 0)) * 3, "December mostly snows (%d snowy, %d rainy)" % [snowy.get(12, 0), rainy.get(12, 0)])
	var jan_snow := float(snowy.get(1, 0)) / float(days[1])
	_check(jan_snow > 0.12 and jan_snow < 0.35, "January snows on about one day in five (%.2f)" % jan_snow)
	_check(int(snowy.get(6, 0)) + int(snowy.get(7, 0)) + int(snowy.get(8, 0)) == 0, "no snow in summer")
	var oct_fog := float(foggy.get(10, 0)) / float(days[10])
	_check(oct_fog > 0.04 and oct_fog < 0.2, "October has a foggy morning about one day in ten (%.2f)" % oct_fog)
	_check(_fog_hours.keys().all(func(hr): return hr >= 3 and hr < 11), "fog only in the early morning (%s)" % [_fog_hours.keys()])
	var may := float(rainy.get(5, 0)) / float(days[5])
	_check(may > 0.3 and may < 0.55, "May rains on about four days in ten (%.2f)" % may)
	_check(max_rain > 0.4 and max_rain <= 1.0, "rain is heavy at most to full strength (%.2f)" % max_rain)
	var all := 10 * 12 * 28
	# Indianapolis: about half its days clear or partly cloudy.
	_check(fair > all * 0.4 and fair < all * 0.65, "about half the days are fair at noon (%d of %d)" % [fair, all])
	# Indiana: about 40-45% of days mostly cloudy, with brighter partly
	# cloudy days between (the critic, 2026-10-26: 53% of daytime hours were
	# overcast, which buried the town's colour).
	var grey_share := float(grey_days) / all
	_check(grey_share > 0.37 and grey_share < 0.47, "about 40-45%% of days are mostly cloudy (%.2f)" % grey_share)
	_check(float(partly_days) / all > 0.18, "partly cloudy days come between (%.2f)" % (float(partly_days) / all))
	var grey_hour_share := float(grey_hours) / day_hours
	_check(grey_hour_share < 0.47, "under half the daytime hours are overcast (%.2f)" % grey_hour_share)
	# A brand-new town's first month (its first hour of sky) is fair: every
	# new town starts on the same date, and it rolled fog and overcast
	# (critic).
	var calm := true
	var start_sim := CitySim.new()
	for t in range(0, 30 * Seasons.TICKS_PER_DAY, 300):
		start_sim.tick_count = t
		var w := Weather.for_town(Weather.sky_clock(start_sim), t, true)
		calm = calm and float(w[0]) < 0.3 and float(w[1]) == 0.0 and float(w[2]) == 0.0
	_check(calm, "a new town's first month is fair, with no fog or rain")
	start_sim.tick_count = 31 * Seasons.TICKS_PER_DAY + 600
	var later := Weather.sky_clock(start_sim)
	_check(Weather.for_town(later, start_sim.tick_count, true) == Weather.conditions(later), "after the first month, the date's own sky")
	_check(later.day == 1 and absf(later.hour + later.minute / 60.0 - start_sim.sky_hour()) < 0.01,
		"a town's weather keys on the month and the sky's hour")
	# Fog only with Day and night on: with it off the light stays at late
	# morning, and dawn fog under it read as a fault.
	_check(not a_fog.is_empty() and float(Weather.for_town(a_fog, 99999, true)[2]) > 0.0, "a foggy morning has fog with Day and night on")
	_check(not a_fog.is_empty() and float(Weather.for_town(a_fog, 99999, false)[2]) == 0.0, "and none with it off")
	# The game's clock and the home screen's both carry a date to key on.
	var sim := CitySim.new()
	var c0: Dictionary = sim.clock()
	_check(c0.has("year") and c0.has("month") and c0.has("day") and c0.has("hour"), "the game's clock gives a date and hour")
	# Marion's real report on the home screen (MarionWeather.read).
	var now := Time.get_unix_time_from_datetime_string("2026-10-26T12:00:00")
	var fresh := "2026-10-26T11:35:00+00:00"
	_check(MarionWeather.read({"timestamp": "2026-10-26T07:00:00+00:00", "cloudLayers": [{"amount": "OVC"}]}, now).is_empty(),
		"a report five hours old is ignored (the odds stand in)")
	_check(MarionWeather.read({"timestamp": fresh, "cloudLayers": [{"amount": "CLR"}], "presentWeather": []}, now) == [0.0, 0.0, 0.0, 0.0],
		"clear skies read as fair")
	_check(MarionWeather.read({"timestamp": fresh, "cloudLayers": [{"amount": "SCT"}, {"amount": "OVC"}]}, now) == [1.0, 0.0, 0.0, 0.0],
		"overcast reads as full cloud, by the thickest layer")
	var wet := MarionWeather.read({"timestamp": fresh, "cloudLayers": [{"amount": "BKN"}],
		"presentWeather": [{"weather": "rain", "intensity": "light"}]}, now)
	_check(wet.size() == 4 and float(wet[3]) == 0.0 and float(wet[0]) >= 0.9 and float(wet[1]) > 0.2 and float(wet[1]) < 0.5, "light rain: overcast and a light shower (%s)" % [wet])
	var storm := MarionWeather.read({"timestamp": fresh, "presentWeather": [{"weather": "thunderstorms", "intensity": "heavy"}]}, now)
	_check(float(storm[1]) >= 0.9, "a heavy thunderstorm pours (%s)" % [storm])
	var mist := MarionWeather.read({"timestamp": fresh, "presentWeather": [{"weather": "fog_mist"}]}, now)
	_check(float(mist[1]) == 0.0 and float(mist[2]) > 0.2 and float(mist[2]) < 0.6, "mist isn't rain: a light fog (%s)" % [mist])
	var flurry := MarionWeather.read({"timestamp": fresh, "presentWeather": [{"weather": "snow", "intensity": "light"}]}, now)
	_check(float(flurry[1]) > 0.0 and float(flurry[3]) == 1.0, "light snow falls as snow (%s)" % [flurry])
	_check(float(MarionWeather.read({"timestamp": fresh, "presentWeather": [{"weather": "fog"}]}, now)[2]) == 1.0, "fog is full fog")
	_wet_streets()
	print("weather: %d failures" % _fails)
	quit(1 if _fails > 0 else 0)


## Wet streets (Nathan, 2026-10-29: "lets make this game look totally
## real"): rain soaks them within the hour, a light rain only part way, and
## once it stops they dry over an hour or two of the sky's clock, slower at
## night.
func _wet_streets() -> void:
	var w := 0.0
	for i in 4:
		w = Weather.wet_after(w, 0.8, 0.1)
	_check(is_equal_approx(w, 1.0), "a steady rain soaks the streets within the hour (%.2f)" % w)
	var light := 0.0
	for i in 10:
		light = Weather.wet_after(light, 0.1, 0.1)
	_check(light > 0.2 and light < 0.6, "a sprinkle only dampens them (%.2f)" % light)
	var day := Weather.wet_after(1.0, 0.0, 0.5)
	_check(day > 0.5 and day < 0.85, "half an hour after the rain they are still wet (%.2f)" % day)
	_check(Weather.wet_after(1.0, 0.0, 2.0) == 0.0, "two hours on they are dry")
	_check(Weather.wet_after(1.0, 0.0, 0.5, 1.0) > day, "they dry slower at night")
	_check(Weather.wet_after(0.4, 0.8, 0.0) == 0.4, "with no time gone nothing changes")
	# The streetlight map covers every lamp with room to spare.
	var lamps := [["a", Vector3(-500, 0, 20), Vector3.FORWARD, 2.0, 9.0], ["a", Vector3(300, 0, 900), Vector3.FORWARD, 2.0, 9.0]]
	var c := LampLight.cover(lamps)
	var ok := true
	for l in lamps:
		var p: Vector3 = l[1]
		ok = ok and p.x - float(c[0]) >= LampLight.MARGIN - 0.01 and p.z - float(c[1]) >= LampLight.MARGIN - 0.01 \
			and float(c[0]) + float(c[2]) - p.x >= LampLight.MARGIN - 0.01 and float(c[1]) + float(c[2]) - p.z >= LampLight.MARGIN - 0.01
	_check(ok and float(c[2]) <= 880.0 + 2.0 * LampLight.MARGIN + 2.0 * LampLight.STEP, "the lamp map covers every lamp (%s)" % [c])
	lamps.append(["a", Vector3(310, 0, 905), Vector3.FORWARD, 2.0, 9.0])
	_check(LampLight.cover(lamps) == c, "a lamp more inside the town leaves the map where it was")
	# Read from the sky's odds: a load mid-afternoon after a morning's rain
	# finds the streets still wet, and they dry a few hours on.
	var before := Weather.clock_before({"year": 3, "month": 1, "day": 1, "hour": 1, "minute": 30.0}, 2.0)
	_check(int(before.month) == 12 and int(before.year) == 2 and int(before.hour) == 23 and is_equal_approx(float(before.minute), 30.0),
		"two sky hours before 1:30 am on the 1st of January is 11:30 pm in December's sky (%s)" % [before])
	var spell := {}
	for y in 6:
		for m in range(5, 9):
			for h in range(8, 17):
				var at := {"year": y, "month": m, "day": 1, "hour": h, "minute": 0.0}
				if spell.is_empty() and float(Weather.conditions(at)[1]) > 0.4 \
						and float(Weather.conditions(Weather.clock_before(at, -2.0))[1]) == 0.0 \
						and float(Weather.conditions(Weather.clock_before(at, -6.0))[1]) == 0.0:
					spell = at
	var odds := func(t): return Weather.conditions(t)
	_check(not spell.is_empty() and Weather.wet_at(spell, odds) > 0.95, "in a summer rain the streets are soaked (%s)" % [spell])
	var after := Weather.clock_before(spell, -2.0)
	var later := Weather.clock_before(spell, -6.0)
	var damp := Weather.wet_at(after, odds)
	_check(damp > 0.0 and damp < 1.0, "an hour or so after it stops they are still drying (%.2f)" % damp)
	_check(Weather.wet_at(later, odds) == 0.0, "hours later they are dry")
	_check(Weather.wet_at(after, odds) == damp, "the same hour always reads the same")
