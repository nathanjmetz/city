extends SceneTree
## Renders power companies (a coal plant and a wind farm) for a look.
## Run: godot -s tools/power_shot.gd -- out.png

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		sim.economy.money = 50_000_000
		sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
		sim.region_links.append(sim.network.find_node_near(Vector3(600, 0, 0), 1.0))
		sim.apply({"type": "place_power", "pos": [-250, 60], "dir": [0, -1]})
		sim.apply({"type": "place_power", "pos": [250, 60], "dir": [0, -1]})
		var ids := sim.power.sites.keys()
		var a: Dictionary = sim.power.sites[ids[0]]
		a.plant = "coal"
		a.cells = [Vector2i(0, 1), Vector2i(1, 1)]
		a.built = ["scrubbers", "training", "tie_line"]
		var b: Dictionary = sim.power.sites[ids[1]]
		b.plant = "wind"
		b.cells = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(0, 2)]
		b.built = ["battery"]
		sim.power_changed.emit()
		var cam: CityCamera
		for c in _main.get_children():
			if c is CityCamera:
				cam = c
		cam.look_at_point(Vector3(0, 0, 150))
		cam.set_view(deg_to_rad(20.0), deg_to_rad(28.0), 700.0)
	if _frames == 60:
		var out: String = OS.get_cmdline_user_args()[0]
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
