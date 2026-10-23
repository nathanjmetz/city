extends "res://tools/look_shot.gd"
## A farm grown for years on open ground on a county road: its fields
## (forties with turn rows and grass borders) and the gravel roads it built
## when each 80-acre block filled.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/farm_road_shot.gd -- out.png yaw pitch dist farms x z


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	# The best soil along a county road, the way a player picks it.
	var at := Vector3(0, 0, 180)
	var rich := -1.0
	for x in range(-1200, 1300, 100):
		var soil := 0.0
		for i in range(-400, 400, 80):
			for j in range(0, 400, 80):
				soil += Farms.fertility_at(Vector3(x + i, 0, 180 + j))
		if soil > rich:
			rich = soil
			at.x = x
	# FARM_X picks a spot instead (patchier soil shows how fields stay square).
	if OS.get_environment("FARM_X") != "":
		at.x = float(OS.get_environment("FARM_X"))
	sim.apply({"type": "build_road", "start": [at.x - 1500, at.z - 180], "ctrl": [at.x, at.z - 180], "end": [at.x + 1500, at.z - 180]})
	print("farmhouse: ", sim.apply({"type": "place_farmhouse", "pos": [at.x, at.z], "dir": [0, -1], "crop": "corn"}))
	sim.farms.price = float(OS.get_environment("FARM_PRICE")) if OS.get_environment("FARM_PRICE") != "" else 1.1
	for i in 900:
		sim.farms.day = i * 0.25
		if sim.farms.decide(sim.field_usable):
			sim._refresh()
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		print("farm ", id, ": $", sim.farms.yearly_profit(id), " wants road ", sim.farms.wants_road(id), " ", f.cells.size(), " cells, blocks ", f.blocks, ", why: ", f.get("why", ""))
	print("roads: ", sim.network.segments.size())
	sim.farms_changed.emit()
	var la := OS.get_cmdline_user_args()
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(float(la[5]), 0, float(la[6])) if la.size() >= 7 else at)
			c.set_view(deg_to_rad(float(la[1])), deg_to_rad(float(la[2])), float(la[3]))
		if c is Hud:
			c.close_all()
