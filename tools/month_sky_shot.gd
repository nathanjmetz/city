extends SceneTree
## A saved town through one month of the sky (SkyClock: sunrise on the 1st,
## sunset five-sixths of the way through, then the night), with the top bar
## showing, to check the light and that the town stays readable at night.
## The light comes from the calendar alone (no pinned date or hour).
## Run in a window: godot --resolution 1600x900 -s tools/month_sky_shot.gd --
##     town.city OUT_DIR month(1-12) x z yaw pitch dist
## (pass a copy of the .city: the game autosaves into it).

## How far through the month each picture is.
const AT := [0.01, 0.2, 0.42, 0.8, 0.835, 0.86, 0.92, 0.985]

var _main: Node
var _frames := 0
var _step := -1
var _wait := 0


func _initialize() -> void:
	root.get_node("Session").save_path = OS.get_cmdline_user_args()[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames < 60:
		if _frames == 2 or _frames == 50:
			_main.set_speed(0)
			DayNight.cycle_on = true
			DayNight.seasons_on = true
			var x := float(args[3])
			var z := float(args[4])
			for c in _main.get_children():
				if c is CityCamera:
					c.look_at_point(Vector3(x, Terrain.ground_y(x, z), z))
					c.set_view(deg_to_rad(float(args[5])), deg_to_rad(float(args[6])), float(args[7]))
		return false
	_wait += 1
	if _step >= 0 and _wait < 45:
		return false  # let the light, lamps and shadows settle
	var sim: CitySim = _main.sim
	if _step >= 0:
		var out := str(args[1]).path_join("sky_%02d.png" % roundi(AT[_step] * 100.0))
		root.get_viewport().get_texture().get_image().save_png(out)
		var t := sim.clock()
		print("saved %s  (%d-%02d-%02d, sky %.2f h)" % [out, t.year, t.month, t.day, sim.sky_hour()])
	_step += 1
	_wait = 0
	if _step >= AT.size():
		quit()
		return false
	var month := float(int(args[2]) - 1)
	if month < Seasons.START_MONTH:
		month += 12.0
	sim.tick_count = Seasons.tick_at(month + AT[_step]) - sim.calendar_offset
	return false
