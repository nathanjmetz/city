extends SceneTree
## A street of homes built through hilly woods (Brawn: houses built in a
## forest kept the trees and had the ground come up through them).
## Run: godot -s tools/forest_lot_shot.gd -- out.png [yaw pitch dist]

var _main: Node
var _frames := 0
var _o := Vector3.ZERO
var _dir := Vector3.RIGHT


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_find()
	# The ground and woods are drawn before the street goes in, as in play.
	if _frames == 60:
		_scene()
	if _frames == 61 and DisplayServer.get_name() == "headless":
		quit()
	if _frames == 160:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "forest_lots.png")
		quit()
	return false


## The most wooded, steepest spot near the start: tree cover times slope.
static func wooded_slope(around: Vector3, reach: float) -> Array:
	var best := -1.0
	var at := around
	var down := Vector3.RIGHT
	var o := Terrain.view_origin
	for x in range(-int(reach), int(reach) + 1, 100):
		for z in range(-int(reach), int(reach) + 1, 100):
			var p := around + Vector3(x, 0, z)
			# Deep in the woods: wooded all along the street and its lots.
			var deep := true
			for dx in [-150, -75, 0, 75, 150]:
				for dz in [-150, -75, 0, 75, 150]:
					deep = deep and Terrain.trees(p.x + dx + o.x, p.z + dz + o.y) > 0.6
			if not deep:
				continue
			var gx := Terrain.height(p.x + 20 + o.x, p.z + o.y) - Terrain.height(p.x - 20 + o.x, p.z + o.y)
			var gz := Terrain.height(p.x + o.x, p.z + 20 + o.y) - Terrain.height(p.x + o.x, p.z - 20 + o.y)
			var s := Vector2(gx, gz).length() / 40.0
			if s > float(OS.get_environment("MAX_SLOPE") if OS.get_environment("MAX_SLOPE") != "" else "0.12"):
				continue  # a bluff, not a buildable hillside
			if s > best:
				best = s
				at = p
				down = Vector3(gz, 0, -gx).normalized()  # along the contour
	return [at, down, best]


func _find() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.require_utilities = false
	print("finding woods")
	var w: Array = wooded_slope(Vector3(2500, 0, 2500), 2000.0)
	_o = w[0]
	_dir = w[1]
	if OS.get_environment("ACROSS") != "":
		_dir = Vector3(-_dir.z, 0, _dir.x)  # straight up the hill
	print("wooded slope at %s, grade %.0f%%" % [_o, w[2] * 100.0])
	_aim()


func _scene() -> void:
	var sim: CitySim = _main.sim
	var a := _o - _dir * 160.0
	var b := _o + _dir * 160.0
	sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [_o.x, _o.z], "end": [b.x, b.z]})
	var side := Vector3(-_dir.z, 0, _dir.x)
	for t in range(-150, 151, 10):
		for s in [-32.0, 32.0]:
			var p: Vector3 = _o + _dir * t + side * s
			sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": 22, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in int(OS.get_environment("TICKS") if OS.get_environment("TICKS") != "" else "4000"):
		sim.tick()
		if i % 500 == 0:
			print("tick ", i, " buildings ", sim.buildings.size(), " lots ", sim.lots.size())
	_report(sim)
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id, 8)
		var ys := []
		for q in pts:
			ys.append(snappedf(q.y, 0.1))
		print("road %d heights over base %s" % [id, ys])
	_aim()


func _aim() -> void:
	var args := OS.get_cmdline_user_args()
	var yaw := float(args[1]) if args.size() > 1 else 200.0
	var pitch := float(args[2]) if args.size() > 2 else 30.0
	var dist := float(args[3]) if args.size() > 3 else 140.0
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(_o)
			c.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
		if c is Hud:
			c.close_all()


## How many homes stand among wild trees, and how far the drawn ground rises
## above or falls below each home's floor.
func _report(sim: CitySim) -> void:
	sim.vegetation.update(sim)
	var homes := 0
	var treed := 0
	var worst := 0.0
	var drawn := 0.0
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		homes += 1
		var lot: Dictionary = sim.lots[key]
		var poly: PackedVector2Array = lot.corners
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		for p in sim.vegetation.plants_in(box, sim.tick_count, false):
			if Geometry2D.is_point_in_polygon(Vector2(p.pos.x, p.pos.z), poly) and p.kind == Vegetation.Kind.TREE:
				treed += 1
				break
		# Under the house: 6 to 20 m back from the front line.
		var floor_y := Terrain.base_y(lot.pos.x, lot.pos.z)
		var n: Vector3 = lot.normal
		var t := Vector3(-n.z, 0, n.x)
		for d in [6.0, 13.0, 20.0]:
			for w in [-6.0, 0.0, 6.0]:
				var q: Vector3 = lot.front + n * d + t * w
				worst = maxf(worst, Terrain.ground_y(q.x, q.z) - floor_y)
				drawn = maxf(drawn, _drawn(q.x, q.z) - floor_y)
	print("homes %d, with wild trees on the lot %d, worst ground above the floor under a house %.1f m (drawn %.1f m)" % [homes, treed, worst, drawn])


## The ground as the nearest terrain mesh draws it: 8 m vertices.
static func _drawn(x: float, z: float) -> float:
	var i := floorf(x / 8.0) * 8.0
	var j := floorf(z / 8.0) * 8.0
	var fx := (x - i) / 8.0
	var fz := (z - j) / 8.0
	return lerpf(lerpf(Terrain.ground_y(i, j), Terrain.ground_y(i + 8, j), fx),
		lerpf(Terrain.ground_y(i, j + 8), Terrain.ground_y(i + 8, j + 8), fx), fz)
