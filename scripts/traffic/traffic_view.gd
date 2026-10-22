class_name TrafficView
extends Node3D
## Draws every vehicle, one batch per model and level of detail, moved on
## smoothly between simulation ticks.
##
## Each vehicle is placed by two points on its path: the front bumper and
## the rear axle, so long vehicles swing wide through turns like real ones.
## Semis draw the tractor and trailer apart, hitched at the fifth wheel.
## Close vehicles get the detailed model, far ones a simple one, and very far
## ones aren't drawn.

## Metres from the camera where models switch to the simple version, and
## where they stop being drawn.
const NEAR := 240.0
const FAR := 2600.0
## Kinds from before vehicle types existed. A plain "car" becomes a
## household vehicle from the real fleet mix, fixed by its id.
const OLD_KINDS := {"truck": "box_truck"}
## Kinds whose emergency lights run.
const EMERGENCY := ["fire_engine", "ambulance"]

var traffic: TrafficSim
## Returns how far through the current tick the clock is, 0 to 1.
var tick_fraction: Callable

var _batches := {}  # mesh key -> [near MultiMeshInstance3D, far one]
var _xf := {}       # mesh key * lod -> [transforms]
var _cu := {}       # mesh key * lod -> [custom colours]


func setup(t: TrafficSim, fraction: Callable) -> void:
	traffic = t
	tick_fraction = fraction


func _ready() -> void:
	var mat := VehicleMaterial.get_material()
	for key in VehicleModels.mesh_keys():
		var pair := []
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.use_colors = true
			mm.mesh = VehicleModels.build(key, lod)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = mat
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			pair.append(mi)
		_batches[key] = pair


func _process(_delta: float) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_draw_cars(_delta)
	Terrain.shift = Vector2.ZERO


func _draw_cars(_delta: float) -> void:
	for k in _xf:
		_xf[k].clear()
		_cu[k].clear()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var frac: float = tick_fraction.call()
	for car in traffic.cars:
		var ahead: float = car.v * TrafficSim.DT * frac
		var front: Vector3 = Terrain.lift(traffic.car_pose(car, ahead)[0])
		var dist := front.distance_to(eye)
		if dist > FAR:
			continue
		var lod := 0 if dist < NEAR else 1
		var kind: String = car.get("kind", "car")
		if kind == "car":
			kind = VehicleTypes.household(car.id)
		kind = OLD_KINDS.get(kind, kind)
		if not VehicleTypes.SPECS.has(kind):
			kind = "sedan"
		var flags := 0.0
		if car.a < -1.2:
			flags += 1.0
		if kind in EMERGENCY or kind == "police" and car.id % 4 == 0:
			flags += 2.0
		var paint := VehicleTypes.paint(kind, car.id)
		var custom := Color(paint.r, paint.g, paint.b, flags)
		if VehicleModels.ARTIC.has(kind):
			var art: Dictionary = VehicleModels.ARTIC[kind]
			var xf := _place(car, ahead, front, VehicleModels.AXLE[art.cab])
			_add(art.cab, lod, xf, custom)
			# Trailer: kingpin on the fifth wheel, rear axles on the path.
			var hitch: Vector3 = xf * Vector3(0, 0, art.hitch)
			var back: Vector3 = Terrain.lift(_behind(car, ahead, art.hitch - art.pin + art.axle))
			var dir := hitch - back
			if dir.length() < 1.0:
				dir = -xf.basis.z
			dir = dir.normalized()
			var origin: Vector3 = hitch + dir * float(art.pin)
			_add(art.trailer, lod, Transform3D(Basis.looking_at(dir, Vector3.UP), origin), Color(1, 1, 1, flags))
		else:
			_add(kind, lod, _place(car, ahead, front, VehicleModels.AXLE.get(kind, 3.5)), custom)
	for key in _batches:
		for lod in 2:
			var k: String = key + str(lod)
			var mm: MultiMesh = _batches[key][lod].multimesh
			var list: Array = _xf.get(k, [])
			if list.size() > mm.instance_count:
				mm.instance_count = maxi(list.size() * 2, 16)
			for i in list.size():
				mm.set_instance_transform(i, list[i])
				mm.set_instance_custom_data(i, _cu[k][i])
				mm.set_instance_color(i, Color.WHITE)
			mm.visible_instance_count = list.size()


## The body's transform: front bumper on the path, pointed back at the rear
## axle's point on the path.
func _place(car: Dictionary, ahead: float, front: Vector3, axle: float) -> Transform3D:
	# Front and back on the road, so the body tips up and down the hills.
	var back := Terrain.lift(_behind(car, ahead, axle))
	var dir := front - back
	if dir.length() < axle * 0.5:
		dir = traffic.car_pose(car, ahead)[1]
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), front)


## The point on the car's path `m` metres behind its front bumper.
func _behind(car: Dictionary, ahead: float, m: float) -> Vector3:
	if traffic.has_method("car_pose_behind"):
		return traffic.call("car_pose_behind", car, m - ahead)[0]
	return traffic.car_pose(car, ahead - m)[0]


func _add(key: String, lod: int, xf: Transform3D, custom: Color) -> void:
	var k := key + str(lod)
	if not _xf.has(k):
		_xf[k] = []
		_cu[k] = []
	_xf[k].append(xf)
	_cu[k].append(custom)
