extends "res://tools/screenshot.gd"
## Weather on the demo town (Nathan, 2026-10-25): the first daytime hour of
## hard rain in May, or the same moment in fair weather with WEATHER=off.
## Run in a real window: godot --resolution 1600x900 -s tools/weather_shot.gd -- out.png yaw pitch dist


func _process(delta: float) -> bool:
	if _frames == 3:
		var sim: CitySim = _main.sim
		Weather.on = OS.get_environment("WEATHER") != "off"
		var t := 0
		while t < 3650 * 24 * CitySim.TICKS_PER_HOUR:
			sim.tick_count = t
			var c := sim.clock()
			if c.month == 5 and c.hour >= 10 and c.hour <= 16 and float(Weather.conditions(c)[1]) > 0.6:
				print("rain at ", c.month, "/", c.day, " ", c.hour, ":00")
				break
			t += CitySim.TICKS_PER_HOUR
		_main.speed = 0
	return super(delta)
