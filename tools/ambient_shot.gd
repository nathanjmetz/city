extends "res://tools/screenshot.gd"
## Ambient life on the demo town (Nathan, 2026-10-25: "come up with as many
## ambient life ideas as possible"): AMB_SCENE picks the scene every home
## near the camera shows (AmbientLife.force), AMB_MONTH and AMB_HOUR the
## time (so the season shows: snow for snowmen).
## Run in a real window: godot --resolution 1600x900 -s tools/ambient_shot.gd -- out.png yaw pitch dist


func _process(delta: float) -> bool:
	if _frames == 3:
		var sim: CitySim = _main.sim
		AmbientLife.force = OS.get_environment("AMB_SCENE")
		var month := int(OS.get_environment("AMB_MONTH")) if OS.get_environment("AMB_MONTH") != "" else 7
		var hour := float(OS.get_environment("AMB_HOUR")) if OS.get_environment("AMB_HOUR") != "" else 14.0
		var day := 12.0 + fposmod(month - 1.0 - Seasons.START_MONTH, 12.0)
		sim.tick_count = int(floorf(day)) * Seasons.TICKS_PER_DAY + roundi((hour - 6.0) * 60.0)
		Weather.on = false
		_main.speed = 0
	return super(delta)
