extends "res://tools/screenshot.gd"
## Farms a few years into their crop rotation in July, from above: corn
## dark blue-green, soybeans brighter, double-crop soybeans after wheat
## just up, hay in between (CropPlan).
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/crops_shot.gd -- out.png yaw pitch dist [x z]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.tick_count = 190 * 1440  # mid July
	sim.apply({"type": "build_road", "start": [-1200, 0], "ctrl": [0, 0], "end": [1200, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-1150, 30], [1150, 30], [1150, 1100], [-1150, 1100]]})
	sim.apply({"type": "place_farmhouse", "pos": [-500, 60], "dir": [0, -1], "crop": "corn"})
	sim.apply({"type": "place_farmhouse", "pos": [450, 60], "dir": [0, -1], "crop": "soybeans"})
	sim.farms.price = 1.1
	for i in 400:
		sim.farms.decide(sim.field_usable)
	for y in 4:
		sim.farms.year += 1
		sim.farms.decide(sim.field_usable)
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		print("farm ", id, " cells ", f.cells.size(), " ", Inspect._crops(f))
		for k in f.fields:
			print("  ", k, " ", f.fields[k].crop, ": ", f.fields[k].why)
	DayNight.seasons_on = OS.get_environment("CROPS_MONTH") != ""
	if DayNight.seasons_on:
		sim.tick_count = Seasons.tick_at(SkyClock.at(int(OS.get_environment("CROPS_MONTH")), 12.0, 5)) - sim.calendar_offset
	sim.farms_changed.emit()
	_aim_camera()
