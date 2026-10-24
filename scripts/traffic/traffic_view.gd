class_name TrafficView
extends Node3D
## Draws every vehicle, one batch per model and level of detail, moved on
## smoothly between simulation ticks.
##
## Bodies move the way real ones do (the kinematic bicycle model, the same
## one AASHTO's turning templates come from): the front axle follows the
## path the simulation drives, and the rear axle trails it, always one
## wheelbase behind and pointed at it. So a car turns about its rear wheels,
## not its bumper, cuts a little inside on a corner and eases into a lane
## change, and a long bus swings its front wide. Semis draw the tractor and
## trailer apart, hitched at the fifth wheel, the trailer's axles trailing
## the kingpin the same way. Backing out of a driveway, the rear leads.
##
## The simulation is sampled once a tick and the view glides between the
## samples (one tick behind), so motion stays smooth however coarse the
## simulation's steps are, and the costly path lookups run once a tick, not
## once a frame. None of this feeds back into the simulation.
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
## Bodies longer than this (metres) are drawn further out than cars.
const LONG := 6.5
## Front axle, metres behind the front bumper, where it isn't about a metre
## (buses and motorhomes set it well back, behind the door).
const FRONT := {"city_bus": 2.4, "coach": 2.2, "motorhome": 2.0, "school_bus": 1.0}
## How much a body dips under braking and leans in a turn, in radians per
## m/s^2, and at most. A family car pitches and rolls about a degree at
## a comfortable 3 m/s^2.
const PITCH := 0.005
const ROLL := 0.006
const LEAN_MAX := 0.03

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
var _sampled := -1.0  # the clock time the vehicles were last sampled at
const _NONE := []
var _parked := []   # [front, mesh key, transform, custom, far mesh key], for parked vehicles in sight
var _parked_version := -1
## The simulation's clock when it was last sampled, the one before, and the
## time the view is drawing (a step behind, so it always has two samples to
## glide between). _rate is simulated seconds per real second.
var _t1 := -1.0
var _t0 := -1.0
var _step := TrafficSim.DT
var _rt := 0.0
var _rate := 1.0
var _win_real := 0.0
var _win_t := 0.0
var _own_clock := false  # driven by the game's own tick clock (your town)


## How one vehicle is moving, for drawing: two samples of its front axle
## (time, point, heading), where its rear axle and trailer axles are now, and
## how far its body is pitched and leaning.
class Motion:
	var t0 := -1.0
	var a0 := Vector3.ZERO
	var h0 := Vector3.FORWARD
	var t1 := -1.0
	var a1 := Vector3.ZERO
	var h1 := Vector3.FORWARD
	## Backing up at the last sample, with where the path puts the rear axle
	## (the rear leads when reversing, so it is taken from the path).
	var rev1 := false
	var r0 := Vector3.ZERO
	var r1 := Vector3.ZERO
	var tr0 := Vector3.ZERO
	var tr1 := Vector3.ZERO
	var a := Vector3.ZERO
	var rear := Vector3.ZERO
	var trailer := Vector3.ZERO
	## The kingpin at the last frame, which the trailer's axles follow.
	var kp := Vector3.INF
	var started := false
	var heading := Vector3.FORWARD
	var pitch := 0.0
	var roll := 0.0


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
	_clock(_delta)
	var cars: Array = traffic.cars + _flow_near(eye)
	if _sampled != _t1:
		_sampled = _t1
		for car in cars:
			_sample(car, _info_of(car))
	var blend := 1.0 - exp(-_delta * 4.0)
	for car in cars:
		var info: Array = _info_of(car)
		var m: Motion = info[9]
		if m.t1 < 0.0:
			_sample(car, info)
		var fo: float = info[10]
		var a := _axle_at(m)
		# Ground height can't bring a car back inside the range, so test the
		# flat distance before lifting it onto the terrain.
		var dx := a.x - eye.x
		var dz := a.z - eye.z
		if dx * dx + dz * dz > far2:
			m.started = false  # out of sight: it picks up afresh when back
			continue
		var wb: float = info[11]
		var h := _steer(m, a, wb, info[12], _delta)
		var flat_front := a + h * fo
		var front := Terrain.stand(flat_front)
		var d2 := front.distance_squared_to(eye)
		if d2 > far2:
			continue
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
		var basis := _body(m, car, h, front, lod, blend, _delta)
		var xf := Transform3D(basis, front)
		if VehicleModels.ARTIC.has(kind):
			var art: Dictionary = VehicleModels.ARTIC[kind]
			_add(art.cab, lod, xf, custom)
			# Trailer: kingpin on the fifth wheel, its axles trailing it.
			var hitch: Vector3 = xf * Vector3(0, 0, art.hitch)
			var tl: float = float(art.axle) - float(art.pin)
			var back := _trail(m, Vector3(hitch.x, a.y, hitch.z), tl)
			var dir := hitch - (Terrain.stand(back) if lod != 1 else Vector3(back.x, hitch.y, back.z))
			if dir.length() < 1.0:
				dir = -xf.basis.z
			dir = dir.normalized()
			var origin: Vector3 = hitch + dir * float(art.pin)
			_add(VehicleModels.trailer_for(art.trailer, car.get("cargo", {})), lod,
				Transform3D(Basis.looking_at(dir, Vector3.UP), origin), Color(1, 1, 1, flags))
		else:
			_add(info[8] if lod == 1 else info[2], lod, xf, custom)
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
## long body, rear axle, far model, Motion, front axle, wheelbase, track to
## keep]. Far away
## every body style of a kind shares one simple model, so the distance costs
## one draw per kind.
func _describe(car: Dictionary) -> Array:
	var kind := _kind(car)
	var flags := 0.0
	if kind in EMERGENCY or kind == "police" and car.id % 4 == 0:
		flags = 2.0
	var model := _model(kind, car.id)
	var long: bool = float(VehicleTypes.spec(kind).len) > LONG
	# A rig steers by its tractor's axles.
	var body: String = VehicleModels.ARTIC[kind].cab if VehicleModels.ARTIC.has(kind) else model
	var rear := float(VehicleModels.AXLE.get(body, 3.5))
	var fo := float(FRONT.get(body, 1.0))
	var wb := maxf(rear - fo, 1.0)
	var need := wb + 1.0
	if VehicleModels.ARTIC.has(kind):
		var art: Dictionary = VehicleModels.ARTIC[kind]
		need = float(art.hitch) - fo + float(art.axle) - float(art.pin) + 1.0
	return [car.get("kind", "car"), kind, model, VehicleTypes.paint(kind, car.id), flags,
		VehicleModels.ARTIC.has(kind), long, rear, _far(kind, model), Motion.new(), fo, wb, need]


func _info_of(car: Dictionary) -> Array:
	var info: Array = _info.get(car.id, _NONE)
	if info.is_empty() or info[0] != car.get("kind", "car"):
		info = _describe(car)
		_info[car.id] = info
	return info


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


## Keeps the drawing clock a step behind the simulation's, so it can glide
## between the last two samples. For your own town it is the game's own
## clock (how far through the tick it is), so every frame moves each car
## exactly as far as the time that passed; a neighbor's town, which only
## arrives now and then, runs on a clock matched to how fast it comes.
func _clock(delta: float) -> void:
	var now: float = traffic.time
	if now < _t1 or _t1 < 0.0 or now - _t1 > 30.0:
		# A fresh start, a loaded town or a neighbor's long-awaited update.
		_t0 = now
		_t1 = now
		_rt = now
		_win_t = now
		_win_real = 0.0
		_info.clear()
	elif now > _t1:
		_t0 = _t1
		_t1 = now
	var frac: float = tick_fraction.call() if tick_fraction.is_valid() else 0.0
	if frac > 0.0:
		_own_clock = true
	if _own_clock:
		# One tick behind the game clock, which runs smoothly whatever the
		# frame rate (a tick is TrafficSim.DT of driving).
		_step = TrafficSim.DT
		_rt = now - TrafficSim.DT + clampf(frac, 0.0, 1.0) * TrafficSim.DT
		return
	if now > _t0 and _t1 == now:
		_step = maxf(now - _t0, 0.001)
	_win_real += delta
	if _win_real >= 0.5:
		_rate = lerpf(_rate, (now - _win_t) / _win_real, 0.5)
		_win_t = now
		_win_real = 0.0
	_rt += delta * _rate
	# Drift back toward a step behind, gently enough not to be seen.
	_rt += (_t1 - _step - _rt) * minf(delta * 0.5, 1.0)
	_rt = clampf(_rt, _t1 - _step * 2.0, _t1)


## Takes a sample of where a vehicle's front axle is now.
func _sample(car: Dictionary, info: Array) -> void:
	var m: Motion = info[9]
	var pose: Array = traffic.car_pose(car)
	var fo: float = info[10]
	var h: Vector3 = pose[1]
	h.y = 0.0
	h = h.normalized() if h.length_squared() > 1e-6 else Vector3.FORWARD
	var a: Vector3 = pose[0] - h * fo
	var c = car.get("j")
	var rev: bool = c != null and car.jd < float(c.get("rev", 0.0))
	var r := Vector3.ZERO
	var tr := Vector3.ZERO
	if rev:
		# Backing up: the path the front bumper backs along is where the
		# rear has just been, so both axles sit on it.
		a = _rev_point(car, fo)
		r = _rev_point(car, info[7])
		if info[5]:
			var art: Dictionary = VehicleModels.ARTIC[info[1]]
			tr = _rev_point(car, float(art.hitch) - float(art.pin) + float(art.axle))
	if m.t1 < 0.0 or a.distance_to(m.a1) > maxf(float(car.get("flow_v", car.v)), 8.0) * maxf(_t1 - m.t1, _step) * 2.0 + 6.0:
		# New, or moved too far to have driven there: starts here.
		m.t0 = _t1 - _step
		m.a0 = a
		m.h0 = h
		m.started = false
	else:
		m.t0 = m.t1
		m.a0 = m.a1
		m.h0 = m.h1
	m.t1 = _t1
	m.a1 = a
	m.h1 = h
	if rev or m.rev1:
		m.r0 = m.r1 if m.rev1 else (m.rear if m.started else r)
		m.tr0 = m.tr1 if m.rev1 else (m.trailer if m.started and m.trailer.is_finite() else tr)
		m.r1 = r
		m.tr1 = tr
	m.rev1 = rev


## A point `x` metres further along the path a car is backing along: on the
## path up to where it stops backing, then straight on past it.
func _rev_point(car: Dictionary, x: float) -> Vector3:
	var room: float = float(car.j.rev) - float(car.jd)
	if x <= room:
		return traffic.car_pose(car, x)[0]
	var p: Vector3 = traffic.car_pose(car, room)[0]
	var q: Vector3 = traffic.car_pose(car, maxf(room - 0.6, 0.0))[0]
	var go := p - q
	go.y = 0.0
	if go.length_squared() < 1e-6:
		return p
	return p + go.normalized() * (x - room)


## The front axle now: a curve through the two samples that leaves and
## arrives along the way the vehicle was heading (a cubic Hermite), so it
## follows the bends between samples.
func _axle_at(m: Motion) -> Vector3:
	var span := m.t1 - m.t0
	var u := 1.0 if span <= 0.0 else clampf((_rt - m.t0) / span, 0.0, 1.0)
	var chord := m.a1 - m.a0
	var len := chord.length()
	if len < 0.01:
		return m.a1
	var d0 := m.h0 if m.h0.dot(chord) >= 0.0 else -m.h0
	var d1 := m.h1 if m.h1.dot(chord) >= 0.0 else -m.h1
	var u2 := u * u
	var u3 := u2 * u
	return m.a0 * (2.0 * u3 - 3.0 * u2 + 1.0) + d0 * (len * (u3 - 2.0 * u2 + u)) \
		+ m.a1 * (3.0 * u2 - 2.0 * u3) + d1 * (len * (u3 - u2))


## Moves the rear axle on behind the front axle `a` and returns the body's
## heading. Driving forward, the front wheels steer along the lane and the
## rear wheels can only roll the way the body points, so each step the
## rear axle is pulled straight toward the front one (a tractrix, as real
## tyres do: no sideways slide). Round a corner the rear cuts inside the
## front's line, as cars and trucks do, and the body lines up again
## gradually after it; on a U-turn it swings round behind the front just
## as smoothly. Backing up the rear leads, so it comes from the path.
func _steer(m: Motion, a: Vector3, wb: float, need: float, delta := 0.0) -> Vector3:
	if m.rev1:
		var span := m.t1 - m.t0
		var u := 1.0 if span <= 0.0 else clampf((_rt - m.t0) / span, 0.0, 1.0)
		var r := m.r0.lerp(m.r1, u)
		m.rear = Vector3(r.x, a.y, r.z)
		var t := m.tr0.lerp(m.tr1, u)
		m.trailer = Vector3(t.x, a.y, t.z)
		m.kp = Vector3.INF
	else:
		var flat := Vector2(a.x - m.a.x, a.z - m.a.z).length()
		if not m.started or flat > need * 2.0:
			m.heading = m.h1
			m.roll = 0.0
			m.rear = a - Vector3(m.h1.x, 0.0, m.h1.z).normalized() * wb
			m.kp = Vector3.INF
		else:
			m.rear = _pull(m.rear, m.a, a, wb)
	m.started = true
	m.a = a
	var h := Vector3(a.x - m.rear.x, 0.0, a.z - m.rear.z)
	if h.length_squared() < 1e-6:
		return m.heading
	return h.normalized()


## A trailing axle `l` behind a point that moved from `from` to `to`: pulled
## straight toward it in short steps, so it never slides sideways.
static func _pull(rear: Vector3, from: Vector3, to: Vector3, l: float) -> Vector3:
	var n := maxi(1, ceili(Vector2(to.x - from.x, to.z - from.z).length() / 0.1))
	for i in n:
		var p := from.lerp(to, float(i + 1) / n)
		var d := Vector2(p.x - rear.x, p.z - rear.z)
		if d.length_squared() > 1e-8:
			d = d.normalized() * l
			rear = Vector3(p.x - d.x, rear.y, p.z - d.y)
	return rear


## The trailer's axles, `l` metres behind the kingpin `k`, pulled after it
## the same way the tractor's rear axle follows its front one.
func _trail(m: Motion, k: Vector3, l: float) -> Vector3:
	if m.rev1:
		return m.trailer
	var gap := Vector2(k.x - m.trailer.x, k.z - m.trailer.z).length() if m.trailer.is_finite() else -1.0
	if not m.kp.is_finite() and absf(gap - l) < l * 0.3:
		m.trailer = _pull(m.trailer, k, k, l)  # just stopped backing: on from where it stands
	elif not m.kp.is_finite() or Vector2(k.x - m.kp.x, k.z - m.kp.z).length() > l:
		# Fresh: lined up behind the tractor as it stands.
		var hb := Vector3(m.a.x - m.rear.x, 0.0, m.a.z - m.rear.z).normalized()
		m.trailer = k - hb * l
	else:
		m.trailer = _pull(m.trailer, m.kp, k, l)
	m.kp = k
	return m.trailer


## The body's orientation: along its heading, tipped to the ground under
## the rear axle, and up close dipping a little under braking and leaning
## out in a turn.
func _body(m: Motion, car: Dictionary, h: Vector3, front: Vector3, lod: int, blend: float, delta: float) -> Basis:
	var dir := h
	if lod != 1:
		var back := Terrain.stand(m.rear)
		dir = (front - back).normalized() if (front - back).length_squared() > 0.25 else h
	var basis := Basis.looking_at(dir, Vector3.UP)
	if lod != 1 and delta > 0.0:
		var yaw := m.heading.signed_angle_to(h, Vector3.UP) / delta
		var v: float = float(car.get("flow_v", car.v))
		m.pitch = lerpf(m.pitch, clampf(float(car.a) * PITCH, -LEAN_MAX, LEAN_MAX), blend)
		m.roll = lerpf(m.roll, clampf(-v * yaw * ROLL, -LEAN_MAX, LEAN_MAX), blend)
		if absf(m.pitch) + absf(m.roll) > 0.002:
			basis = basis * Basis.from_euler(Vector3(m.pitch, 0.0, m.roll))
	m.heading = h
	return basis


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
		var front: Vector3 = Terrain.stand(pose[0])
		var dir: Vector3 = (front - Terrain.stand(pose[0] - flat * float(VehicleModels.AXLE.get(kind, 3.5)))).normalized()
		var paint := VehicleTypes.paint(kind, car.id)
		var custom := Color(paint.r, paint.g, paint.b, 0.0)
		if VehicleModels.ARTIC.has(kind):
			# A rig parked straight: the trailer lined up behind the cab.
			var art: Dictionary = VehicleModels.ARTIC[kind]
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), front)
			_parked.append([front, art.cab, xf, custom, art.cab])
			var hitch: Vector3 = xf * Vector3(0, 0, art.hitch)
			var trailer := VehicleModels.trailer_for(art.trailer, car.get("cargo", {}))
			_parked.append([front, trailer, Transform3D(xf.basis, hitch + dir * float(art.pin)),
				Color(1, 1, 1, 0.0), trailer])
		else:
			# Parked in the same body it drove in.
			var model := _model(kind, car.id)
			_parked.append([front, model, Transform3D(Basis.looking_at(dir, Vector3.UP), front), custom,
				_far(kind, model)])
