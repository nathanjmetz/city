extends SceneTree
## Pictures of the country-road look Nathan checked on 2026-10-25: a grid of
## 2-lane streets laid onto the state highway (yellow centre line), with
## nothing zoned yet so they are drawn as country roads, and a few homes
## along the highway past the grid, for the pole line and its service drops.
## Same camera spots every run, so before and after line up.
## Run (a real window):
##   godot -s tools/road_look_shot.gd -- --shots DIR
## Add --rendering-method gl_compatibility for the browser's renderer.

## [name, look at, yaw, pitch, distance]
const SPOTS := [
	["tee_close", Vector3(540, 0, 594), 200.0, 38.0, 34.0],
	["tee_mid", Vector3(540, 0, 590), 215.0, 32.0, 90.0],
	["cross_close", Vector3(660, 0, 480), 225.0, 40.0, 40.0],
	["shoulder_40m", Vector3(480, 0, 598), 160.0, 22.0, 40.0],
	["shoulder_120m", Vector3(340, 0, 540), 200.0, 30.0, 120.0],
	["poles_homes", Vector3(-100, 0, 700), 250.0, 26.0, 90.0],
	["grid_300m", Vector3(540, 0, 450), 210.0, 45.0, 300.0],
	["county_cross", Vector3(-100, 0, 600), 200.0, 35.0, 45.0],
	["gravel_tee", Vector3(-100, 0, 420), 160.0, 35.0, 40.0],
	["dead_end", Vector3(-400, 0, 420), 120.0, 30.0, 30.0],
	["y_merge", Vector3(1340, 0, 580), 200.0, 45.0, 70.0],
	["shoulder_300m", Vector3(0, 0, 600), 190.0, 25.0, 300.0],
	["drops_close", Vector3(-100, 0, 720), 300.0, 22.0, 38.0],
	["homes_top", Vector3(-100, 0, 720), 180.0, 89.0, 130.0],
	["y_top", Vector3(1320, 0, 590), 180.0, 89.0, 90.0],
	["cross_top", Vector3(-100, 0, 600), 180.0, 89.0, 70.0],
]

var _main: Node
var _cam: CityCamera
var _frames := 0
var _jobs := []  # [frame, Callable]
var _out := ""


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _arg(name: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_setup()
	for j in _jobs.duplicate():
		if j[0] == _frames:
			j[1].call()
			_jobs.erase(j)
	return false


func _setup() -> void:
	var sim: CitySim = _main.sim
	_main.set_speed(0)
	DayNight.cycle_on = false
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Hud:
			c.close_all()
	_out = _arg("--shots", ".")
	DirAccess.make_dir_recursive_absolute(_out)
	sim.apply({"type": "clear"})
	# Whatever the last saved game left (clear keeps the way out, not lots).
	sim.buildings.clear()
	sim.zones.cells.clear()
	sim.economy.money = 50_000_000
	sim.require_utilities = false
	# July, late morning.
	sim.tick_count = Seasons.tick_at(SkyClock.at(7, 11.0)) - sim.calendar_offset
	# Clear of the crossroads a new town starts from (CitySim "clear").
	sim.apply({"type": "build_road", "start": [-200, 600], "ctrl": [600, 600], "end": [1400, 600],
		"road": RoadStyle.Type.STATE_HWY})
	# The grid, its south side on the highway, the way the grid tool joins it.
	sim.apply({"type": "build_grid_shape", "points": [[300, 240], [780, 240], [780, 600], [300, 600]],
		"block": 120, "join": true})
	# A paved county road across the highway, a gravel road teed off it that
	# ends in a field, and a street branching off the highway in a Y.
	sim.apply({"type": "build_road", "start": [-100, 380], "ctrl": [-100, 600], "end": [-100, 820],
		"road": RoadStyle.Type.COUNTY})
	sim.apply({"type": "build_road", "start": [-100, 420], "ctrl": [-250, 420], "end": [-400, 420],
		"road": RoadStyle.Type.GRAVEL})
	sim.apply({"type": "build_road", "start": [1300, 600], "ctrl": [1420, 555], "end": [1560, 480]})
	# Homes along the county road north of the highway (the grid stays a
	# country grid: nothing within 60 m of it), so it becomes a town street.
	var hwy := -1
	for id in sim.network.segments:
		var c := sim.network.curve_of(id)
		if int(sim.network.segments[id].type) == RoadStyle.Type.COUNTY and minf(c[0].z, c[2].z) > 590.0:
			hwy = id
	if hwy >= 0:
		for side in [1, -1]:
			sim.apply({"type": "zone_frontage", "seg": hwy, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.tick()
	var keys := sim.lots.keys()
	keys.sort()
	var i := 0
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		if sim.zones.zone_at(lot.zone_pt) == ZoneMap.Zone.NONE or absf(lot.front.z - 600.0) < 30.0:
			continue
		var cap := CitySim.capacity(ZoneMap.Zone.RESIDENTIAL, i)
		sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": i, "built": 0, "cap": cap, "occ": cap}
		i += 1
	print("homes: ", i, " roads: ", sim.network.segments.size())
	sim.buildings_changed.emit()
	sim.lots_changed.emit()
	var f := 60
	# The nearest painted county mile running north-south across z = 700, seen
	# low along it (the look check's "blurry streak").
	var spots := SPOTS.duplicate()
	var best := [INF, 0.0]
	for x in range(-900, 900, 4):
		var d := CountyGrid.distance(x + sim.terrain_offset.x, 700.0 + sim.terrain_offset.y)
		if d < best[0]:
			best = [d, float(x)]
	if best[0] < 3.0:
		spots.append(["county_paint_low", Vector3(best[1], 0, 760), 180.0, 10.0, 120.0])
		spots.append(["county_paint_60m", Vector3(best[1], 0, 700), 150.0, 35.0, 60.0])
	for s in spots:
		if _arg("--only", s[0]) != s[0]:
			continue
		_jobs.append([f, func(): _aim(s[1], s[2], s[3], s[4])])
		_jobs.append([f + 30, func(): _save(s[0] + ".png")])
		f += 32
	_jobs.append([f + 2, func(): quit()])


func _aim(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	_cam.look_at_point(at)
	_cam.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)


func _save(name: String) -> void:
	var path := _out.path_join(name)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
