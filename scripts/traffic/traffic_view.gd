class_name TrafficView
extends Node3D
## Draws every vehicle, one batch per model and level of detail, moved on
## smoothly between simulation ticks.
##
## Each vehicle is placed by two points on its path: the front bumper and
## the rear axle, so long vehicles swing wide through turns like real ones.
## Semis draw the tractor and trailer apart, hitched at the fifth wheel.
## Close vehicles get the detailed model (the close-up one on the desktop
## Ultra tier), far ones a simple one, and very far ones aren't drawn.
## Parked vehicles in stalls, driveways and at docks are drawn too; ones
## inside a garage or bay are out of sight.

## Metres from the camera where models switch to the simple version, and
## where they stop being drawn.
const NEAR := 240.0
const FAR := 2600.0
## Cars and pickups shrink to a few pixels sooner than trucks do.
const FAR_SMALL := 1800.0
## How far out a big town's flowing traffic is drawn as cars.
const FLOW_NEAR := 900.0
var _flow_list := []
var _flow_frames := 0
## On the desktop Ultra tier, vehicles this close (metres) get the close-up
## model: rounded body, alloy wheels, seams and clear-coat paint.
const ULTRA_NEAR := 75.0
## Kinds whose emergency lights run.
const EMERGENCY := ["fire_engine", "ambulance"]
## Bodies longer than this (metres) track their rear axle on the path up
## close; shorter ones just follow the path at the front bumper.
const LONG := 6.5

var traffic: TrafficSim
## Returns how far through the current tick the clock is, 0 to 1.
var tick_fraction: Callable
## Vehicles standing still off the traffic list (a crew's pickup at a job
## site): returns [[kind, Transform3D at the front bumper, id], ...].
var parked := Callable()

var _snow := 0.0
var _batches := {}  # mesh key -> [near MultiMeshInstance3D, far one, Ultra one]
var _ultra := false
var _xf := {}       # mesh key * lod -> [transforms]
var _cu := {}       # mesh key * lod -> [custom colours]
var _info := {}     # car id -> what _describe() worked out
const _NONE := []
var _parked := []   # [front, mesh key, transform, custom, far mesh key], for parked vehicles in sight
var _parked_version := -1


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


## Ultra close-ups are hidden when the tier turns off. Each model's is built
## the first time one comes close (about 5 ms), so other tiers and the
## browser never pay for them and turning Ultra on doesn't stall a frame.
func _set_ultra(on: bool) -> void:
	_ultra = on
	for key in _batches:
		var list: Array = _batches[key]
		if list.size() > 2:
			list[2].visible = on


func _add_ultra_batch(key: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = VehicleModels.build(key, VehicleModels.LOD_ULTRA)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = VehicleMaterial.get_material(true)
	add_child(mi)
	_batches[key].append(mi)


static func _ultra_wanted() -> bool:
	var q := GraphicsQuality.current
	return q != null and q.active and q.tier >= GraphicsQuality.ULTRA


func _process(_delta: float) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var t := Perf.now()
	_draw_cars(_delta)
	Perf.add("frame.vehicles", t)
	Terrain.shift = Vector2.ZERO


## Cars driving as part of a big town's traffic flow, near enough to draw:
## found again a few times a second, since there can be thousands.
func _flow_near(eye: Vector3) -> Array:
	if traffic.flowing.is_empty():
		_flow_list = []
		return _flow_list
	_flow_frames -= 1
	if _flow_frames > 0:
		return _flow_list
	_flow_frames = 6
	_flow_list = []
	var r2 := FLOW_NEAR * FLOW_NEAR
	for car in traffic.flowing:
		var p: Vector3 = traffic.flow_pose(car)[0]
		if (p.x - eye.x) * (p.x - eye.x) + (p.z - eye.z) * (p.z - eye.z) < r2:
			_flow_list.append(car)
	return _flow_list


func _draw_cars(_delta: float) -> void:
	for k in _xf:
		_xf[k].clear()
		_cu[k].clear()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var frac: float = tick_fraction.call()
	if _ultra_wanted() != _ultra:
		_set_ultra(not _ultra)
	var ultra2 := ULTRA_NEAR * ULTRA_NEAR if _ultra else -1.0
	# Snow cover (from DayNight). Plows go on and come off with it.
	if (Seasons.snow_now > 0.4) != (_snow > 0.4):
		_info.clear()
		_parked_version = -1
	_snow = Seasons.snow_now
	if traffic.parked_version != _parked_version:
		_parked_version = traffic.parked_version
		_rebuild_parked()
	for item in _parked:
		var dist: float = item[0].distance_to(eye)
		if dist <= FAR:
			if dist < NEAR:
				_add(item[1], 2 if dist * dist < ultra2 else 0, item[2], item[3])
			else:
				_add(item[4], 1, item[2], item[3])
	var far2 := FAR * FAR
	var near2 := NEAR * NEAR
	var small2 := FAR_SMALL * FAR_SMALL
	if _info.size() > traffic.cars.size() * 2 + 256:
		_info.clear()  # vehicles long gone
	for car in traffic.cars + _flow_near(eye):
		var ahead: float = car.get("flow_v", car.v) * TrafficSim.DT * frac
		var pose: Array = traffic.car_pose(car, ahead)
		var p0: Vector3 = pose[0]
		# Ground height can't bring a car back inside the range, so test the
		# flat distance before lifting it onto the terrain.
		var dx := p0.x - eye.x
		var dz := p0.z - eye.z
		if dx * dx + dz * dz > far2:
			continue
		var front := Terrain.lift(p0)
		var d2 := front.distance_squared_to(eye)
		if d2 > far2:
			continue
		var info: Array = _info.get(car.id, _NONE)
		if info.is_empty() or info[0] != car.get("kind", "car"):
			info = _describe(car)
			_info[car.id] = info
		if d2 > small2 and not info[6]:
			continue
		var lod := 0 if d2 < near2 else 1
		if d2 < ultra2:
			lod = 2
		var kind: String = info[1]
		var flags: float = info[4]
		if car.a < -1.2:
			flags += 1.0
		var paint: Color = info[3]
		var custom := Color(paint.r, paint.g, paint.b, flags)
		# A semi carrying a load that needs its own rig is drawn as that rig.
		if info[5]:
			var rig := VehicleTypes.for_cargo(car.get("cargo", {}))
			if rig != "" and VehicleModels.ARTIC.has(rig) and not kind in VehicleTypes.CARGO_ALT.get(rig, []):
				kind = rig
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
		elif lod != 1 and info[6]:
			# Long bodies up close: rear axle on the path, so they swing wide.
			_add(info[2], lod, _place(car, ahead, front, info[7]), custom)
		else:
			# Short ones, and anything far off: along the path at the front,
			# tipped to the ground under the rear axle.
			var dir: Vector3 = pose[1]
			dir.y = 0.0
			if dir.length_squared() < 1e-6:
				dir = Vector3.FORWARD
			dir = dir.normalized()
			if lod != 1:
				var back := Terrain.lift(p0 - dir * info[7])
				dir = (front - back).normalized()
			_add(info[8] if lod == 1 else info[2], lod, Transform3D(Basis.looking_at(dir, Vector3.UP), front), custom)
	if parked.is_valid():
		for p in parked.call():
			_add_parked(p[0], p[1], p[2], eye, ultra2)
	for key in _batches:
		for lod in 3:
			var k: String = key + str(lod)
			var list: Array = _xf.get(k, _NONE)
			var n := list.size()
			if lod == 2 and _batches[key].size() < 3:
				if n == 0:
					continue
				_add_ultra_batch(key)
			var mm: MultiMesh = _batches[key][lod].multimesh
			if n == 0:
				if mm.visible_instance_count != 0:
					mm.visible_instance_count = 0
				continue
			if n > mm.instance_count:
				mm.instance_count = maxi(n * 2, 16)
				for i in mm.instance_count:
					mm.set_instance_color(i, Color.WHITE)
			var cu: Array = _cu[k]
			for i in n:
				mm.set_instance_transform(i, list[i])
				mm.set_instance_custom_data(i, cu[i])
			mm.visible_instance_count = n


## What doesn't change over a vehicle's life, worked out once:
## [sim kind, kind, model, paint, emergency flag, may haul a rig's load,
## long body, rear axle, far model]. Far away every body style of a kind
## shares one simple model, so the distance costs one draw per kind.
func _describe(car: Dictionary) -> Array:
	var kind := _kind(car)
	var flags := 0.0
	if kind in EMERGENCY or kind == "police" and car.id % 4 == 0:
		flags = 2.0
	var model := _model(kind, car.id)
	var long: bool = float(VehicleTypes.spec(kind).len) > LONG
	return [car.get("kind", "car"), kind, model, VehicleTypes.paint(kind, car.id), flags,
		VehicleModels.ARTIC.has(kind), long, float(VehicleModels.AXLE.get(model, 3.5)), _far(kind, model)]


## The body style a vehicle keeps for life, plowing in snow: dump trucks
## and one contractor pickup in three.
func _model(kind: String, id: int) -> String:
	var model := VehicleModels.variant(kind, id)
	if _snow > 0.4 and VehicleModels.WINTER.has(model) and (kind == "dump_truck" or id % 3 == 0):
		model = VehicleModels.WINTER[model]
	return model


static func _far(kind: String, model: String) -> String:
	return kind if VehicleModels.VARIANTS.has(kind) else model


func _add_parked(kind: String, xf: Transform3D, id: int, eye: Vector3, ultra2: float) -> void:
	var dist := xf.origin.distance_to(eye)
	if dist > FAR or not VehicleTypes.SPECS.has(kind):
		return
	var lod := 0 if dist < NEAR else 1
	if dist * dist < ultra2:
		lod = 2
	var paint := VehicleTypes.paint(kind, id)
	if VehicleModels.ARTIC.has(kind):
		var art: Dictionary = VehicleModels.ARTIC[kind]
		_add(art.cab, lod, xf, Color(paint.r, paint.g, paint.b, 0.0))
		# Parked straight: the trailer lines up behind the cab.
		var fwd := -xf.basis.z
		var origin: Vector3 = xf * Vector3(0, 0, art.hitch) + fwd * float(art.pin)
		_add(art.trailer, lod, Transform3D(xf.basis, origin), Color(1, 1, 1, 0.0))
	else:
		_add(kind, lod, xf, Color(paint.r, paint.g, paint.b, 0.0))


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


static func _kind(car: Dictionary) -> String:
	return TrafficSim.vehicle_kind(car)


## Parked vehicles only move when one parks or leaves, so their places are
## worked out once then.
func _rebuild_parked() -> void:
	_parked.clear()
	for car in traffic.parked:
		if car.get("hidden", false):
			continue
		var pose := TrafficSim.parked_pose(car)
		var flat: Vector3 = pose[1]
		if flat.length() < 0.5:
			flat = Vector3.FORWARD
		var kind := _kind(car)
		# Front and back on the ground, so it sits level with the slope.
		var front: Vector3 = Terrain.lift(pose[0])
		var dir: Vector3 = (front - Terrain.lift(pose[0] - flat * float(VehicleModels.AXLE.get(kind, 3.5)))).normalized()
		var paint := VehicleTypes.paint(kind, car.id)
		var custom := Color(paint.r, paint.g, paint.b, 0.0)
		if VehicleModels.ARTIC.has(kind):
			# A rig parked straight: the trailer lined up behind the cab.
			var art: Dictionary = VehicleModels.ARTIC[kind]
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), front)
			_parked.append([front, art.cab, xf, custom, art.cab])
			var hitch: Vector3 = xf * Vector3(0, 0, art.hitch)
			_parked.append([front, art.trailer, Transform3D(xf.basis, hitch + dir * float(art.pin)),
				Color(1, 1, 1, 0.0), art.trailer])
		else:
			# Parked in the same body it drove in.
			var model := _model(kind, car.id)
			_parked.append([front, model, Transform3D(Basis.looking_at(dir, Vector3.UP), front), custom,
				_far(kind, model)])
