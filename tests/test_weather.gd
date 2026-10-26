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
	for y in 10:
		for m in range(1, 13):
			for d in range(1, 29):
				days[m] = int(days.get(m, 0)) + 1
				var wet := false
				var flakes := false
				var mist := false
				for h in 24:
					var c := Weather.conditions({"year": y, "month": m, "day": d, "hour": h, "minute": 30.0})
					max_rain = maxf(max_rain, float(c[1]))
					if float(c[1]) > 0.0:
						if float(c[3]) > 0.5:
							flakes = true
						else:
							wet = true
					if float(c[2]) > 0.0:
						mist = true
						_fog_hours[h] = true
					if h == 12 and float(c[0]) < 0.5:
						fair += 1
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
	print("weather: %d failures" % _fails)
	quit(1 if _fails > 0 else 0)
