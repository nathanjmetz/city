class_name MenuSim
extends CitySim
## The title screen's town: a CitySim whose clock and sky are the wall clock
## in Marion (see MarionTime) instead of the game's. Traffic and people plan
## their day from sky_hour(), so the streets are busy at rush hour and empty
## at night by the real hour.

## Marion's date and time now (MarionTime.at), set by MenuLife each frame.
var wall := {}
## How far through its step the traffic is (0 to 1). DayNight adds that
## fraction of a minute to the clock to line the lights up with the cars; the
## wall clock is already exact, so it is taken off here.
var minute_bias := 0.0


func clock() -> Dictionary:
	if wall.is_empty():
		return super.clock()
	var t := wall.duplicate()
	t["minute"] = float(wall.minute) + float(wall.second_f) / 60.0 - minute_bias
	return t


## The menu's people keep the sim clock's hour for their stays, as before.
func sky_ticks_per_hour() -> float:
	return TICKS_PER_HOUR


func sky_hour(_frac := 0.0) -> float:
	if wall.is_empty():
		return super.sky_hour(_frac)
	var t := clock()
	return float(t.hour) + float(t.minute) / 60.0
