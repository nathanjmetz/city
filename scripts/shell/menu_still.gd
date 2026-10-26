class_name MenuStill
extends RefCounted
## Pictures of the home screen's town, one for each look it can have: shown
## the moment the game opens, while the live town is built behind them a
## piece a frame, then faded into it (BackdropReveal). Taken from the menu's
## own camera, where it starts, by tools/menu_still.gd, on the browser's
## renderer (the one most players have; the desktop app's look is close
## enough for the fade). Each is a small JPEG, wide enough for an ultrawide
## screen; a narrower window shows its middle, as the camera does.

const DIR := "res://assets/menu/"
## Width over height of the pictures (3440 x 1440 is 2.39).
const ASPECT := 2.4
const LOOKS := ["summer", "autumn", "bare", "snow", "night"]
## The sun this far below the horizon (degrees) is the night picture.
const NIGHT_SUN := -3.0
## Marion times the pictures are taken at, one for each look.
const TAKEN_AT := {
	"summer": "2026-07-10T13:00",
	"autumn": "2026-10-18T13:00",
	"bare": "2026-11-28T13:00",
	"snow": "2026-01-20T13:00",
	"night": "2026-07-10T23:30",
}


## Which picture fits Marion's clock `t` (MarionTime.at): night, else the
## season the leaves and snow are in.
static func look_for(t: Dictionary) -> String:
	var months := MarionTime.months_for_sky(t)
	if SunPath.position_game(months, MarionTime.hour_of(t)).x < NIGHT_SUN:
		return "night"
	var look := Seasons.look(months)
	if look.snow > 0.5:
		return "snow"
	if look.autumn > 0.5:
		return "autumn"
	if look.bare > 0.5:
		return "bare"
	return "summer"


## The file for a look.
static func path(look: String) -> String:
	return DIR + "still_%s.jpg" % look


## The picture for Marion's clock `t`, or null.
static func texture_for(t: Dictionary) -> Texture2D:
	var p := path(look_for(t))
	return load(p) if ResourceLoader.exists(p) else null
