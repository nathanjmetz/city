extends "res://tools/screenshot.gd"
## Weather on the demo town (Nathan, 2026-10-25): the first daytime hour of
## hard rain in May (WEATHER_KIND=rain, the default), snow in January
## (snow) or a foggy October morning (fog); fair weather with WEATHER=off.
## Run in a real window: godot --resolution 1600x900 -s tools/weather_shot.gd -- out.png yaw pitch dist


func _process(delta: float) -> bool:
	if _frames == 3:
		var sim: CitySim = _main.sim
		Weather.on = OS.get_environment("WEATHER") != "off"
		var kind := OS.get_environment("WEATHER_KIND") if OS.get_environment("WEATHER_KIND") != "" else "rain"
		var month: int = {"rain": 5, "snow": 1, "fog": 10}[kind]
		var t := 0
		while t < 3650 * 24 * CitySim.TICKS_PER_HOUR:
			sim.tick_count = t
			var c := sim.clock()
			var w := Weather.conditions(c)
			var hit := false
			if c.month == month:
				match kind:
					"rain": hit = c.hour >= 10 and c.hour <= 16 and float(w[1]) > 0.6 and float(w[3]) < 0.5
					"snow": hit = c.hour >= 10 and c.hour <= 16 and float(w[1]) > 0.6 and float(w[3]) > 0.5
					"fog": hit = c.hour >= 6 and float(w[2]) > 0.8
			if hit:
				print("%s at %d/%d %d:00" % [kind, c.month, c.day, c.hour])
				break
			t += CitySim.TICKS_PER_HOUR
		_main.speed = 0
	return super(delta)
