extends "res://tools/look_shot.gd"
## Brawn's farm (2026-10-24): a county road on the section line runs
## through a farm's land, the way a farm grown before fields kept off
## county roads looks once the road cuts its fields back. Checks the field
## edge along the road, the fencerows and their trees, and the crop colour.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/farm_county_shot.gd -- out.png yaw pitch dist


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	# The farm's own road on the east-west section line, the farmhouse
	# 200 m east of the north-south one, so that county road runs through
	# its first block.
	sim.apply({"type": "build_road", "start": [-1500, -2], "ctrl": [200, -2], "end": [1900, -2]})
	print("farmhouse: ", sim.apply({"type": "place_farmhouse", "pos": [200, 180], "dir": [0, -1], "crop": "corn"}))
	var f: Dictionary = sim.farms.farms.values()[0]
	f.barn = true
	# Grown over the years before the county road counted: the whole block.
	for x in range(-10, 10):
		for y in range(-2, 10):
			var c := Vector2i(x, y)
			if not c in f.cells and Geometry2D.intersect_polygons(Farms.cell_corners(f, c), sim.farms._yard(f)).is_empty():
				f.cells.append(c)
	sim._road_wins()
	print("county mile here: ", CountyGrid.has_mile(0, 0), "  cells ", f.cells.size(), " trimmed ", sim.farms.trim.get(sim.farms.farms.keys()[0], {}).size())
	sim.farms_changed.emit()
	var la := OS.get_cmdline_user_args()
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(float(OS.get_environment("LOOK_X")) if OS.get_environment("LOOK_X") != "" else 0.0, 0, float(OS.get_environment("LOOK_Z")) if OS.get_environment("LOOK_Z") != "" else 200.0))
			c.set_view(deg_to_rad(float(la[1])), deg_to_rad(float(la[2])), float(la[3]))
		if c is Hud:
			c.close_all()
