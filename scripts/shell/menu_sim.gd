class_name MenuSim
extends CitySim
## The title screen's town: a CitySim whose clock is the wall clock in
## Marion (see MarionTime) instead of the game's. Traffic and people plan
## their day from clock().hour, so the streets are busy at rush hour and
## empty at night by the real hour.

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
