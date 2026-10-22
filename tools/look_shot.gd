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
		# Pick the tick in year 2 with that month and hour (day 0 starts at 6:00).
		var day := 12.0 + fposmod(month - 1.0 - Seasons.START_MONTH, 12.0)
		sim.tick_count = int(floorf(day)) * Seasons.TICKS_PER_DAY + roundi((hour - 6.0) * 60.0)
		_main.speed = 0
	return super(delta)
