extends SceneTree
## The detail floor, measured (docs/detail-floor.md): opens the real game with
## a lived-in town (PerfTown, plus a few apartment blocks, row homes, Main
## Street blocks and offices, a power plant and a farm), and from each camera
## distance and tilt saves a picture of each kind of thing, at the look the
## game is running (--quality). The camera's floor is switched off, so it can
## go as close as asked: the pictures show what each look holds up to.
## Run (a real window, not headless):
##   godot --resolution 1600x900 --quality high -s tools/detail_floor_shots.gd -- OUT_DIR [targets=a,b] [dists=25,40] [tilts=20,40]
##   add --rendering-driver opengl3 for the browser's renderer.
## Pictures land in OUT_DIR/<renderer>_<tier>/<target>_d<dist>_t<tilt>.png.
## Then tools/detail_floor_sheet.gd makes the contact sheets.
## Never writes the saved quality setting: --quality pins the tier for the run
## and the setting file is only read.

const DISTS := [25, 40, 60, 80, 100, 150, 200]
const TILTS := [20, 40, 65]
const ALL := ["house", "row_home", "apartments", "shop", "mixed_use", "office", "factory", "car", "person",
	"trees", "woods", "junction", "street", "field", "farmstead", "power"]
## Metres east of town where the farm and the power plant go, as PerfTown does.
const SETTLE_NEW := 70
const SETTLE := 14

var _main: Node
var _cam: CityCamera
var _frames := 0
var _stage := 0
var _wait := 0
var _out := ""
var _dir := ""
var _targets := {}   # name -> {aim: Vector3, yaw: float}
var _want: Array = []
var _dists: Array = DISTS
var _tilts: Array = TILTS
var _queue := []     # [target, dist, tilt]
var _last_target := ""
var _log := {}


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _stage == 0:
		if _main.loading:
			return false
		var args := OS.get_cmdline_user_args()
		_out = args[0] if args.size() > 0 else "."
		_want = ALL.duplicate()
		for a in args:
			if a.begins_with("targets="):
				_want = a.trim_prefix("targets=").split(",")
			elif a.begins_with("dists="):
				_dists = Array(a.trim_prefix("dists=").split(",")).map(func(x): return int(x))
			elif a.begins_with("tilts="):
				_tilts = Array(a.trim_prefix("tilts=").split(",")).map(func(x): return int(x))
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, "big")
		_vary(sim)
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			# The picture is of the town: no panels, tour or status icons.
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		_cam.ignore_floor = true
		_main.set_speed(4)
		_stage = 1
		_frames = 0
		return false
	_frames += 1
	if _stage == 1:
		# Every building up and merged, and traffic running for a while.
		if _frames < 300:
			return false
		for c in _main.get_children():
			if c is BuildingView and (not c._pending.is_empty() or not c._bake_due.is_empty() or c._filling):
				return false
		# Stop the moment someone is out walking, so a walker is in the picture.
		if _main.sim.traffic.walkers.is_empty() and _frames < 5000:
			return false
		_main.set_speed(0)
		print("cars ", _main.sim.traffic.cars.size(), " walkers ", _main.sim.traffic.walkers.size(), " tick ", _main.sim.tick_count)
		_find_targets(_main.sim)
		for t in _want:
			if _targets.has(t):
				for tilt in _tilts:
					for d in _dists:
						_queue.append([t, d, tilt])
			else:
				print("no target found for ", t)
		_dir = _out.path_join("%s_%s" % [_renderer(), GraphicsQuality.NAMES[GraphicsQuality.current.tier].to_lower()])
		DirAccess.make_dir_recursive_absolute(_dir)
		print("shooting ", _queue.size(), " into ", _dir)
		_stage = 2
		_wait = 0
		return false
	if _stage == 2:
		if _wait > 0:
			_wait -= 1
			return false
		if _queue.is_empty():
			_finish()
			return true
		var q: Array = _queue.pop_front()
		var t: Dictionary = _targets[q[0]]
		var first: bool = q[0] != _last_target
		_last_target = q[0]
		_cam.look_at_point(t.aim)
		_cam.set_view(t.yaw, deg_to_rad(q[2]), float(q[1]))
		_stage = 3
		_wait = SETTLE_NEW if first else SETTLE
		_pending = q
		return false
	if _stage == 3:
		if _wait > 0:
			_wait -= 1
			return false
		var q := _pending
		root.get_texture().get_image().save_png(_dir.path_join("%s_d%d_t%d.png" % [q[0], q[1], q[2]]))
		_stage = 2
		return false
	return false


var _pending := []


func _renderer() -> String:
	return "browser" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else "desktop"


func _finish() -> void:
	var f := FileAccess.open(_dir.path_join("targets.json"), FileAccess.WRITE)
	var out := {}
	for k in _targets:
		out[k] = {"aim": [_targets[k].aim.x, _targets[k].aim.z], "yaw_deg": rad_to_deg(_targets[k].yaw), "note": _targets[k].get("note", "")}
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("done: ", _dir)
	quit()


## Mixes the town up: some apartments, row homes, Main Street blocks and
## offices among the houses and shops, a power plant and a farm further out.
func _vary(sim: CitySim) -> void:
	var i := 0
	for key in sim.buildings.keys():
		var b: Dictionary = sim.buildings[key]
		i += 1
		match int(b.zone):
			ZoneMap.Zone.RESIDENTIAL:
				if i % 9 == 0:
					b.type = "apartments"
					b.level = 1 if i % 18 == 0 else 0
					b.cap = 20
				elif i % 7 == 0:
					b.type = "row_home"
					b.units = 3
					b.level = 0
			ZoneMap.Zone.COMMERCIAL:
				if i % 4 == 0:
					b.type = "mixed_use"
					b.level = 1
				elif i % 5 == 0:
					b.type = "office"
					b.level = 1
	sim.buildings_changed.emit()
	sim.economy.money = 900_000_000
	var placed := false
	for x in [-1300.0, -1500.0, 1700.0, 2000.0, -1100.0]:
		var why := sim.power_problem(Vector3(x, 0.0, -840.0), Vector3(0, 0, -1))
		print("power plant at ", x, ": ", why if why != "" else "ok")
		if why == "" and not placed:
			placed = sim.apply({"type": "place_power", "pos": [x, -840.0], "dir": [0, -1]})
	for s in sim.power.sites.values():
		s.plant = "coal"
		s.cells = [Vector2i(0, 1), Vector2i(1, 1)]
		s.built = ["scrubbers", "tie_line"]
	sim.power_changed.emit()


func _find_targets(sim: CitySim) -> void:
	var by_type := {}
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if not sim.lots.has(key):
			continue
		var t := BuildingTypes.type_of(b)
		var lot: Dictionary = sim.lots[key]
		by_type[t] = by_type.get(t, [])
		by_type[t].append([key, lot])
	# Homes from the north-west quarter, shops and offices from the middle.
	var home_at := Vector2(-430.0, -330.0)
	for t in ["house", "row_home", "apartments", "shop", "mixed_use", "office", "factory"]:
		if not by_type.has(t):
			continue
		var from := Vector2.ZERO
		if t in ["house", "row_home", "apartments"]:
			from = home_at
		elif t == "factory":
			from = Vector2(600.0, 0.0)
		var best: Array = []
		var bd := INF
		for e in by_type[t]:
			var d: float = from.distance_to(Vector2(e[1].pos.x, e[1].pos.z))
			if d < bd:
				bd = d
				best = e
		var lot: Dictionary = best[1]
		var n: Vector3 = lot.normal
		_targets[t] = {"aim": Vector3(lot.pos.x, 0.0, lot.pos.z), "yaw": atan2(-n.x, -n.z) + 0.45,
			"note": "%s at %s" % [t, best[0]]}
	var tr: TrafficSim = sim.traffic
	var best_car = null
	var bd := INF
	for car in tr.cars:
		var p: Vector3 = tr.car_pose(car)[0]
		var d := Vector2(p.x, p.z).length()
		if d < bd and d > 40.0:
			bd = d
			best_car = [p, tr.car_pose(car)[1]]
	if best_car != null:
		var h: Vector3 = best_car[1]
		_targets["car"] = {"aim": Vector3(best_car[0].x, 0.0, best_car[0].z), "yaw": atan2(-h.z, h.x) + 0.6, "note": "a moving car"}
	var best_w = null
	bd = INF
	for w in tr.walkers:
		var p: Vector3 = tr.walker_pose(w, 0.0)[0]
		var d := Vector2(p.x, p.z).length()
		if d < bd:
			bd = d
			best_w = [p, tr.walker_pose(w, 0.0)[1]]
	if best_w != null:
		_targets["person"] = {"aim": Vector3(best_w[0].x, 0.0, best_w[0].z), "yaw": 0.6, "note": "a walker"}
	_targets["junction"] = {"aim": Vector3(0.0, 0.0, 0.0), "yaw": 0.6, "note": "the middle crossroads"}
	_targets["street"] = {"aim": Vector3(70.0, 0.0, 140.0), "yaw": 0.6, "note": "a block's length of street"}
	# Trees: the spot with the most trees in a 60 m box, south of town (yard
	# trees and wild woods); woods: the same further out, where it is wild.
	_targets["trees"] = _tree_spot(sim, Rect2(-800.0, -700.0, 1600.0, 1400.0), "yard and street trees")
	_targets["woods"] = _tree_spot(sim, Rect2(-1500.0, 900.0, 3000.0, 1500.0), "wild woods")
	# Farms and the power plant.
	if not sim.farms.farms.is_empty():
		var f: Dictionary = sim.farms.farms.values()[0]
		var h: Vector3 = f.pos
		_targets["farmstead"] = {"aim": Vector3(h.x, 0.0, h.z), "yaw": 0.6, "note": "the farmhouse"}
		var c: Vector3 = Farms.cell_center(f, f.cells[f.cells.size() / 2]) if not f.cells.is_empty() else h
		_targets["field"] = {"aim": Vector3(c.x, 0.0, c.z), "yaw": 0.3, "note": "a crop field"}
	if not sim.power.sites.is_empty():
		var s: Dictionary = sim.power.sites.values()[0]
		var p = s.get("pos", Vector3(-300, 0, -840))
		_targets["power"] = {"aim": Vector3(p.x, 0.0, p.z) if p is Vector3 else Vector3(p[0], 0.0, p[1]), "yaw": 0.6, "note": "power plant and its line"}
	for k in _targets:
		print(k, " -> ", _targets[k].aim, " ", _targets[k].get("note", ""))


func _tree_spot(sim: CitySim, area: Rect2, note: String) -> Dictionary:
	var best := Vector2(area.position + area.size / 2.0)
	var most := -1
	var step := 128.0
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var box := Rect2(x, y, step, step)
			var n := 0
			for p in sim.vegetation.plants_in(box, sim.tick_count, false):
				if int(p.kind) == Vegetation.Kind.TREE:
					n += 1
			if n > most:
				most = n
				best = box.get_center()
			x += step
		y += step
	return {"aim": Vector3(best.x, 0.0, best.y), "yaw": 0.6, "note": "%s (%d trees in 128 m)" % [note, most]}
