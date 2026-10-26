extends "res://tools/screenshot.gd"
## The demo town at a chosen hour and month, for checking day/night and
## seasons. Same arguments as screenshot.gd, plus environment variables:
##   LOOK_MONTH (1-12; whole months, the hour sets the day's time), LOOK_HOUR (0-24), LOOK_CYCLE (1 = day/night on),
##   LOOK_SEASONS (0 = off).
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/look_shot.gd -- out.png yaw pitch dist


func _process(delta: float) -> bool:
	if _frames == 3:
		DayNight.cycle_on = OS.get_environment("LOOK_CYCLE") == "1"
		DayNight.seasons_on = OS.get_environment("LOOK_SEASONS") != "0"
		var month := float(OS.get_environment("LOOK_MONTH")) if OS.get_environment("LOOK_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("LOOK_HOUR")) if OS.get_environment("LOOK_HOUR") != "" else 11.0
		var sim: CitySim = _main.sim
		# The tick in year 2 with that month and the sky at that hour.
		sim.tick_count = Seasons.tick_at(SkyClock.at(int(month), hour)) - sim.calendar_offset
		_main.speed = 0
	return super(delta)
