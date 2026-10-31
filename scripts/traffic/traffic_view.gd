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
## inside a bay or a home's garage are out of sight, except that on the
## desktop two household cars in three that the simulation has in its
## garage are drawn out on the drive (see _out_front).
## On the desktop, shop, office and plant lots also fill by the hour with
## cars the simulation doesn't drive (see _update_lot_cars).
## One drawn out on the drive stays there while it is really backing out
## of the garage behind it, and one coming home stops there, so it never
## drives through the shut garage door (DoorEvents opens the door only for
## the others: out_front).

## Metres from the camera where models switch to the simple version, and
## where they stop being drawn, on a full desktop (High and up); lower
## graphics tiers set their own (cars_m, car_near_m in GraphicsQuality).
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
## Household cars the simulation puts in a home's garage that are drawn out
## on the drive instead: OUT_FRONT in OUT_OF. A Grant County home has about
## 1.8 vehicles and most stand outside even with a garage, which holds the
## mower, the bikes and the boxes (look critic, round 0, 2026-10-29).
const OUT_FRONT := 2
const OUT_OF := 3
## Metres a car drawn out front stands from its garage spot (the drive spot
## in front of a bay, SiteLayout.house), and how far back from the street
## edge of the lot its middle must be, as the drive spot's must (its rear
## bumper must be on the lot too).
const DRIVE_OUT := 6.2
const DRIVE_MIN_Z := 2.6
## Metres over which a car drawn out on the drive eases from its path onto
## the place it stands parked, coming home or backing out.
const DRIVE_EASE := 4.0
## Lot cars (desktop, the tier's lot_cars): the simulation drives a few
## hundred cars at once (TrafficSim.MAX_CARS), so its shop lots stand about
## a tenth full at mid-morning, where a Marion strip lot is 30 to 60% full
## late in the morning and fuller at noon (look critic, round 3,
## 2026-10-30). The view parks stand-ins in the free stalls by the hour:
## the staff at the far end of the lot from the door, there from before
## opening to after closing, and customers from the door outward as the
## day's trade comes and goes. Drawing only: the simulation, saves and the
## copies never see them, and a stall the simulation takes (or a car is
## heading for) is left to it. Every stall decides from its own hash and
## the hour, so every run and every computer shows the same cars.
## Share of a lot's stalls its staff take (the farthest from the door),
## and the hours they're there, by building type; customers' share of the
## other stalls through the day, as [hour, share] points eased between.
const LOT_STAFF := {"shop": 0.15, "office": 0.5, "hotel": 0.12, "factory": 0.75}
const LOT_STAFF_HOURS := {"shop": [8.0, 18.5], "office": [7.5, 17.5], "hotel": [0.0, 24.0], "factory": [6.0, 18.0]}
## Overnight, a plant's night shift keeps this share of its staff stalls.
const LOT_NIGHT_SHIFT := 0.3
const LOT_CUSTOMERS := {
	"shop": [[8.5, 0.0], [9.5, 0.25], [11.0, 0.45], [12.5, 0.6], [14.0, 0.45], [16.5, 0.45], [17.5, 0.55], [18.0, 0.5], [18.75, 0.0]],
	"shop_late": [[8.5, 0.0], [9.5, 0.25], [11.0, 0.45], [12.5, 0.6], [14.0, 0.45], [16.5, 0.45], [17.5, 0.6], [20.0, 0.45], [21.0, 0.3], [21.75, 0.0]],
	"evening": [[10.5, 0.0], [11.5, 0.35], [12.5, 0.55], [14.0, 0.25], [17.0, 0.35], [18.5, 0.65], [20.0, 0.55], [21.5, 0.2], [22.5, 0.0]],
	"office": [[8.5, 0.0], [9.5, 0.15], [16.0, 0.15], [17.0, 0.0]],
	"hotel": [[0.0, 0.6], [8.0, 0.55], [11.0, 0.25], [16.0, 0.25], [19.0, 0.5], [24.0, 0.6]],
	"factory": [[0.0, 0.0]],
}
## Building types by their lot's pattern above (a shop let to an office
## trade, Names.is_office, keeps office hours).
const LOT_KIND := {"shop": "shop", "mixed_use": "shop", "commercial_block": "shop", "shopping_center": "shop",
	"office": "office", "office_park": "office", "hotel": "hotel", "factory": "factory"}
## Within this many metres of the camera a lot changes one car at a time,
## LOT_TRICKLE real seconds apart (one pulling in or leaving), so nothing
## pops in or out in front of you; further out it is set as it should be.
const LOT_NEAR_M := 300.0
const LOT_TRICKLE := 6.0
## A stall the simulation had stays empty this many real seconds after (its
## car backing out, or one on its way in that just took it).
const LOT_HOLD := 15.0
## Lots further than the cars' reach plus this aren't worked out at all.
const LOT_MARGIN := 100.0
## Metres the camera goes before the lots are listed nearest first again.
const LOT_RESORT_M := 400.0
## The lots are looked at in turn, nearest the camera first, for at most
## LOT_BUDGET_MS a frame (a big town has a thousand of them, and working
## out a lot's stalls the first time takes a fraction of a millisecond),
## each at most every LOT_EVERY real seconds, and one lot's stalls worked
## out a frame. The list of lots is made again, a slice a frame too, when
## the town's buildings or roads change or the camera has gone far.
const LOT_EVERY := 1.0
const LOT_BUDGET_MS := 0.35
const _STAYS := [0.0, 0.0, Vector3.ZERO]
## Metres the camera moves, or the reach changes, before the parked
## vehicles' batches are filled again, and the fewest frames between
## fills (one car parking or the camera panning never refills every frame).
const REFILL_M := 16.0
const REFILL_FRAMES := 4
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
## The town the traffic belongs to (see setup); null draws no car out on a
## drive.
var town: CitySim
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
## Each parked vehicle's drawing, kept while it stays put: car id ->
## [place, spot, pos, cargo, items where it is, items out on the drive, id].
var _pcache := {}
## What the kept drawings were worked out against: the roads' version (the
## ground is graded with them) and whether cars go out on the drive.
var _pcache_for := []
## Household cars drawn out on the drive at the last _rebuild_parked, ones
## drawn there that have since set off and are still backing out (drawn
## from the drive, not the garage), and for cars coming home, whether
## they'll stand on the drive: car id -> [place, spot, out front].
var _out_ids := {}
var _leaving_out := {}
var _arrive_out := {}
## Parked vehicles' own batches (mesh key -> [near, far, Ultra] or null),
## filled again only when the camera has moved or the reach changed (see
## _fill_parked), and what they were last filled for.
var _pmm := {}
var _pfill := [Vector3.INF, 0.0, 0.0, 0.0]
var _pfill_due := true
var _pfill_age := 0
var _parked_drawn := 0
## Lot cars (see LOT_STAFF): each lot's stalls ({lot key: [signature,
## stalls]}, see _lot_stall_list); what each lot shows now ({lot key:
## [stall list indices, real time of its last change, where it is, its
## stall list]}); stalls held for the simulation ({lot key: {stall index:
## real time it's free}}); the lots in the order they are looked at (see
## _lot_index), where each lot is, what that list was made for and where
## the camera was; the next one to look at, when this pass began and the
## hour then; whether the batches must be filled again at the end of the
## pass; and whether _lot_stall_list just worked a lot's stalls out.
var _lot_stalls := {}
var _lot_shown := {}
var _lot_block := {}
var _lot_list := []
var _lot_at := {}
var _lot_list_for := []
var _lot_sort_eye := Vector3.INF
## The list being made: the buildings' keys, how far through, what it has
## so far, and what it is for.
var _lot_scan := []
var _lot_scan_at := 0
var _lot_scan_list := []
var _lot_scan_for := []
var _lot_next := 0
var _lot_pass_t := -INF
var _lot_hour := -100.0
var _lot_jumped := false
var _lot_dirty := false
var _lot_built_now := false
## A lot's stalls being worked out ({} for none; see _lot_stall_list).
var _lot_build := {}
## The lot cars' own batches (mesh key -> [near, far, Ultra] or null), the
## fill under way ({} for none), whether one is due, what the last was for,
## and how many it drew.
var _lmm := {}
var _lfill := {}
var _lfill_due := true
var _lfill_for := []
var _lot_drawn := 0
## How far vehicles are drawn now, and inside it the full model: the
## graphics tier's cars_m and car_near_m, pulled in on a crowded road to
## stay under its most-at-once (cars; GraphicsQuality.fit_reach).
var _reach_far := FAR
var _reach_near := NEAR
var _drawn := 0
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


## Car meshes built ahead, a few a frame, by a screen that can't stall on
## them all at once (the home screen: about 60 ms for every model):
## "key/lod" -> ArrayMesh. Built here if missing.
static var premade := {}


## `sim` is the town the traffic belongs to, for its lots and buildings
## (which garage cars stand out on the drive): passed in, since a
## neighbor's town or one just loaded hasn't stepped its traffic yet.
func setup(t: TrafficSim, fraction: Callable, sim: CitySim = null) -> void:
	traffic = t
	tick_fraction = fraction
	town = sim


func _ready() -> void:
	var mat := VehicleMaterial.get_material()
	for key in VehicleModels.mesh_keys():
		var pair := []
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.use_colors = true
			mm.mesh = premade.get("%s/%d" % [key, lod], null)
			if mm.mesh == null:
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
	return q != null and q.active and bool(GraphicsQuality.knob("car_detail", false))


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
	var full := float(GraphicsQuality.knob("cars_m", FAR))
	_reach_far = minf(_reach_far, full)
	_reach_near = minf(float(GraphicsQuality.knob("car_near_m", NEAR)), _reach_far)
	# Snow cover (from DayNight). Plows go on and come off with it.
	if (Seasons.snow_now > 0.4) != (_snow > 0.4):
		_info.clear()
		_pcache.clear()
		_parked_version = -1
	_snow = Seasons.snow_now
	var rebuilt := traffic.parked_version != _parked_version or _pcache_for != _pcache_key()
	if rebuilt:
		_parked_version = traffic.parked_version
		_rebuild_parked()
	_update_lot_cars(eye, ultra2)
	_fill_parked(eye, ultra2, rebuilt)
	_drawn = _parked_drawn
	var far2 := _reach_far * _reach_far
	var near2 := _reach_near * _reach_near
	var small := FAR_SMALL * _reach_far / FAR
	var small2 := small * small
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
		_drawn += 1
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
	_reach_far = GraphicsQuality.fit_reach(_reach_far, _drawn, int(GraphicsQuality.knob("cars", GraphicsQuality.NO_CAP)), full)
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
	if dist > _reach_far or not VehicleTypes.SPECS.has(kind):
		return
	_drawn += 1
	var lod := 0 if dist < _reach_near else 1
	if dist * dist < ultra2:
		lod = 2
	var paint := VehicleTypes.paint(kind, id)
	if VehicleModels.ARTIC.has(kind):
		var art: Dictionary = VehicleModels.ARTIC[kind]
		_add(art.cab, lod, xf, Color(paint.r, paint.g, paint.b, VehicleMaterial.OFF))
		# Parked straight: the trailer lines up behind the cab.
		var fwd := -xf.basis.z
		var origin: Vector3 = xf * Vector3(0, 0, art.hitch) + fwd * float(art.pin)
		_add(art.trailer, lod, Transform3D(xf.basis, origin), Color(1, 1, 1, VehicleMaterial.OFF))
	else:
		_add(kind, lod, xf, Color(paint.r, paint.g, paint.b, VehicleMaterial.OFF))


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
	var c = car.get("j")
	# One drawn out on the drive comes home to stand there, and backs out
	# from there: drawn short of (or ahead of) where it is along its path.
	var drv := _on_drive(car, c)
	var short: float = drv[0]
	var pose: Array = traffic.car_pose(car, -short) if short > 0.0 else traffic.car_pose(car)
	var fo: float = info[10]
	var h: Vector3 = pose[1]
	h.y = 0.0
	h = h.normalized() if h.length_squared() > 1e-6 else Vector3.FORWARD
	var a: Vector3 = pose[0] - h * fo + drv[2]
	var rev: bool = c != null and car.jd < float(c.get("rev", 0.0))
	var r := Vector3.ZERO
	var tr := Vector3.ZERO
	if rev:
		# Backing up: the path the front bumper backs along is where the
		# rear has just been, so both axles sit on it.
		a = _rev_point(car, fo + drv[1]) + drv[2]
		r = _rev_point(car, float(info[7]) + drv[1]) + drv[2]
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
## worked out then, each vehicle's kept for as long as it stays put.
func _rebuild_parked() -> void:
	_parked.clear()
	if _pcache_for != _pcache_key():
		_pcache_for = _pcache_key()
		_pcache.clear()
	var cache := {}
	var fronts := {}  # place -> front bumpers of what is drawn there
	var outs := []
	for car in traffic.parked:
		var at = car.get("at_place", "")
		var c: Array = _pcache.get(car.id, _NONE)
		if c.is_empty() or c[0] != at or c[1] != car.get("spot", -1) or c[2] != car.pos or c[3] != car.get("cargo"):
			var hidden: bool = car.get("hidden", false)
			var pose := TrafficSim.parked_pose(car)
			c = [at, car.get("spot", -1), car.pos, car.get("cargo"), _NONE if hidden else _parked_items(car, pose[0], pose[1]),
				_out_front(car) if hidden else _NONE, car.id]
		cache[car.id] = c
		if not c[4].is_empty():
			_parked.append_array(c[4])
			if fronts.has(at):
				fronts[at].append(c[4][0][0])
			else:
				fronts[at] = [c[4][0][0]]
		elif not c[5].is_empty():
			outs.append(c)
	_pcache = cache
	# Ones drawn out front that have just set off back out from the drive.
	for id in _out_ids:
		if not cache.has(id):
			_leaving_out[id] = true
	if _leaving_out.size() > 1024:
		_leaving_out.clear()
	_out_ids = {}
	# Out on the drive only where nothing else stands (a duplex's drive spot
	# is right in front of its garage).
	for c in outs:
		var front: Vector3 = c[5][0][0]
		var here: Array = fronts.get(c[0], _NONE)
		var clear := true
		for f in here:
			if Vector2(f.x - front.x, f.z - front.z).length_squared() < 4.0:
				clear = false
				break
		if not clear:
			continue
		_parked.append_array(c[5])
		_out_ids[c[6]] = true
		if here.is_empty():
			fronts[c[0]] = [front]
		else:
			here.append(front)


func _pcache_key() -> Array:
	return [traffic.version, _drive_cars()]


## Garage cars drawn out on the drive: on the desktop where the graphics
## tier's budget allows (drive_cars), never in the browser, which draws
## and counts its cars as it always has.
static func _drive_cars() -> bool:
	return not OS.has_feature("web") and bool(GraphicsQuality.knob("drive_cars", true))


## The most lot cars a tier draws (its lot_cars; 0 for none), on the
## desktop only, never in the browser.
static func _lot_cap() -> int:
	if OS.has_feature("web"):
		return 0
	return int(GraphicsQuality.knob("lot_cars", 0))


## Fills the free stalls of the town's shop, office, hotel and plant lots
## by the hour (see LOT_STAFF): a slice of the lots each frame, then their
## batches filled again a slice a frame too (_fill_lots).
func _update_lot_cars(eye: Vector3, ultra2: float) -> void:
	var cap := _lot_cap()
	if town == null or cap <= 0:
		if not _lot_shown.is_empty() or not _lot_list.is_empty() or not _lot_stalls.is_empty():
			_lot_clear()
		return
	var t0 := Time.get_ticks_usec()
	var until := t0 + int(LOT_BUDGET_MS * 1000.0)
	var now := t0 / 1000000.0
	var built := [town.buildings.size(), traffic.version]
	# A new list once the last one is done (a growing town never keeps one
	# from finishing): when the buildings or roads changed, or the camera
	# has gone far enough that "nearest first" is out of order.
	if _lot_scan_for.is_empty() and (built != _lot_list_for \
			or Vector2(eye.x - _lot_sort_eye.x, eye.z - _lot_sort_eye.z).length() > LOT_RESORT_M):
		_lot_scan = town.buildings.keys()
		_lot_scan_at = 0
		_lot_scan_list = []
		_lot_scan_for = built
		if _lot_list_for.is_empty() or built[1] != _lot_list_for[1]:
			_lot_at.clear()  # the roads were rebuilt, and the lots may have moved
	if not _lot_scan_for.is_empty():
		_lot_index(eye, until)
	if _lot_next >= _lot_list.size() and now - _lot_pass_t >= LOT_EVERY:
		# A new pass. The clock jumped (a load, the time set, a new day):
		# every lot is set as it should be at once, near or not.
		_lot_next = 0
		_lot_pass_t = now
		var hour := town.sky_hour()
		_lot_jumped = absf(hour - _lot_hour) > 1.0 and absf(hour - _lot_hour) < 23.0
		_lot_hour = hour
	var may_build := true
	while _lot_next < _lot_list.size() and Time.get_ticks_usec() < until:
		var entry: Array = _lot_list[_lot_next]
		var r := _lot_look(entry[1], entry[2], eye, now, may_build, until)
		if r == LOOK_WAIT:
			break  # its stalls are worked out over the next frames
		_lot_next += 1
		if r == LOOK_BUILT or r == LOOK_BUILT_CHANGED:
			may_build = false
		if r == LOOK_CHANGED or r == LOOK_BUILT_CHANGED:
			_lot_dirty = true
	if _lot_dirty and _lot_next >= _lot_list.size():
		_lot_dirty = false
		_lfill_due = true
	_fill_lots(eye, ultra2, cap, until)


## Drops every lot car (the tier turned them off, or no town).
func _lot_clear() -> void:
	_lot_stalls.clear()
	_lot_shown.clear()
	_lot_block.clear()
	_lot_build = {}
	_lot_list = []
	_lot_list_for = []
	_lot_scan = []
	_lot_scan_for = []
	_lot_next = 0
	_lfill = {}
	_lfill_due = true
	for key in _lmm:
		for mi in _lmm[key]:
			if mi != null:
				mi.multimesh.instance_count = 0
	_lot_drawn = 0


## Makes the list of lots that fill (LOT_KIND), a slice until `until`
## (microseconds) each frame; once done, nearest `eye` first, so a town
## just loaded fills round the camera first: [[distance, key, where]].
## Where each lot is, is kept between lists; lots no longer listed lose
## their stalls, what they showed and their holds.
func _lot_index(eye: Vector3, until: int) -> void:
	while _lot_scan_at < _lot_scan.size() and Time.get_ticks_usec() < until:
		var key: String = _lot_scan[_lot_scan_at]
		_lot_scan_at += 1
		if not town.buildings.has(key) or not town.lots.has(key) or _lot_kind(key) == "":
			continue
		var at: Vector3 = _lot_at.get(key, Vector3.INF)
		if at == Vector3.INF:
			at = SiteLayout.world(town.lots[key], Vector2.ZERO)
			_lot_at[key] = at
		_lot_scan_list.append([Vector2(at.x - eye.x, at.z - eye.z).length_squared(), key, at])
	if _lot_scan_at < _lot_scan.size():
		return
	var list := _lot_scan_list
	list.sort()
	_lot_list = list
	_lot_list_for = _lot_scan_for
	_lot_sort_eye = eye
	_lot_scan = []
	_lot_scan_list = []
	_lot_scan_for = []
	_lot_next = mini(_lot_next, list.size())
	var listed := {}
	for e in list:
		listed[e[1]] = true
	for d in [_lot_shown, _lot_stalls, _lot_block, _lot_at]:
		for key in d.keys():
			if not listed.has(key):
				d.erase(key)
				_lot_dirty = true


## What _lot_look did: nothing new, what the lot draws changed, it worked
## out the lot's stalls (and maybe changed too), or it must wait a frame to
## work them out (one lot's a frame).
enum { LOOK_SAME, LOOK_CHANGED, LOOK_BUILT, LOOK_BUILT_CHANGED, LOOK_WAIT }


## Looks at one lot: which stalls should have a car at the pass's hour,
## near the camera one change at a time, never one the simulation has or
## had in the last LOT_HOLD seconds (a car backing out of it, or one on its
## way in). `may_build`: whether working out its stalls may begin now;
## `until`: when this frame's share of the work is up (microseconds).
func _lot_look(key: String, at: Vector3, eye: Vector3, now: float, may_build := true, until := 1 << 62) -> int:
	var had: Array = _lot_shown.get(key, _NONE)
	var gone := LOOK_CHANGED if not had.is_empty() else LOOK_SAME
	var kind := "" if not town.buildings.has(key) or not town.lots.has(key) else _lot_kind(key)
	if kind == "" or town.care.tier_of(key) <= -2:
		# Boarded up (a lease sign), gone, or not one that fills now.
		_lot_shown.erase(key)
		_lot_block.erase(key)
		return gone
	var reach := _reach_far + LOT_MARGIN
	if Vector2(at.x - eye.x, at.z - eye.z).length_squared() > reach * reach:
		_lot_shown.erase(key)  # too far to draw: nothing to work out
		return gone
	var ref: String = "lot:" + key
	var pl := traffic.cached_place(ref)
	if pl.is_empty():
		# The simulation hasn't laid it out (no car has come yet), or its
		# layout is out of date (the building changed) and its cars' spots
		# may not mean these stalls: none until it lays it out again.
		# (Laying a lot out here would take up to a millisecond.)
		_lot_shown.erase(key)
		return gone
	var stalls = _lot_stall_list(key, ref, kind, pl, may_build, until)
	if stalls == null:
		return LOOK_WAIT
	var built := _lot_built_now
	_lot_built_now = false
	# Stalls the simulation has now hold for LOT_HOLD seconds after.
	var taken: Array = pl.get("taken", _NONE)
	var block: Dictionary = _lot_block.get(key, {})
	for st in stalls:
		var i: int = st[0]
		if i < taken.size() and int(taken[i]) != -1:
			block[i] = now + LOT_HOLD
	for i in block.keys():
		if float(block[i]) <= now:
			block.erase(i)
	if block.is_empty():
		_lot_block.erase(key)
	else:
		_lot_block[key] = block
	var want := _lot_want(kind, ref, stalls, _lot_hour)
	if not block.is_empty():
		want = want.filter(func(k): return not block.has(stalls[k][0]))
	var shown: Array = want
	var since := now
	if not had.is_empty() and is_same(had[3], stalls):
		shown = had[0]
		since = had[1]
		if not block.is_empty():
			shown = shown.filter(func(k): return not block.has(stalls[k][0]))
		if _lot_jumped or Vector2(at.x - eye.x, at.z - eye.z).length_squared() >= LOT_NEAR_M * LOT_NEAR_M:
			shown = want
		elif shown != want and now - since >= LOT_TRICKLE:
			# Near: one car in or out at a time.
			shown = _lot_step(shown, want, hash([key, int(now / LOT_TRICKLE)]))
			since = now
	var changed: bool = had.is_empty() or had[0] != shown
	_lot_shown[key] = [shown, since, at, stalls]
	if built:
		return LOOK_BUILT_CHANGED if changed else LOOK_BUILT
	return LOOK_CHANGED if changed else LOOK_SAME


## The stalls lot `key` would fill (all but the accessible ones), farthest
## from the door first: [[stall index, parts, staff stall, customer
## threshold 0-1, jitter 0-1]], each part [summer mesh key, its far one,
## snow mesh key, its far one, the instance's 20 floats (MultiMesh buffer:
## transform, colour, custom)]. On the simulation's own layout (its place
## `pl`), worked out again when that would be (its place seed), the roads
## change or the trade does. Worked out a few stalls at a time until
## `until` (microseconds), carrying on next frame (null until it's done);
## a new one is begun only when `may_build`.
func _lot_stall_list(key: String, ref: String, kind: String, pl: Dictionary, may_build: bool, until: int) -> Variant:
	var sig := [traffic._place_seed(ref), traffic.version, kind]
	var had: Array = _lot_stalls.get(key, _NONE)
	if not had.is_empty() and had[0] == sig:
		return had[1]
	var job := _lot_build
	if job.is_empty() or job.key != key or job.sig != sig:
		if not may_build:
			return null
		var lay: Dictionary = pl.lay
		var door: Vector2 = lay.get("door", Vector2.ZERO)
		var found := []
		for i in lay.spots.size():
			var sp: Dictionary = lay.spots[i]
			if sp.kind == "stall" and not sp.get("ada", false):
				found.append([-(sp.pos as Vector2).distance_to(door), i])
		found.sort()
		var staff := roundi(found.size() * float(LOT_STAFF[kind]))
		if staff == 0 and found.size() >= 4:
			staff = 1
		job = {"key": key, "sig": sig, "lot": town.lots[key], "spots": lay.spots, "found": found,
			"staff": staff, "k": 0, "list": []}
		_lot_build = job
	_lot_built_now = true
	var lot: Dictionary = job.lot
	var found: Array = job.found
	var n := found.size()
	var staff: int = job.staff
	var winter := _snow
	while job.k < n and Time.get_ticks_usec() < until:
		var k: int = job.k
		job.k += 1
		var i: int = found[k][1]
		var sp: Dictionary = job.spots[i]
		var id := absi(hash([key, i, "lot car"])) % 1000000000 + 1000000000
		var car := {"id": id, "kind": "car"}
		var kind_of := _kind(car)
		var face := SiteLayout.world_dir(lot, sp.face)
		var front := SiteLayout.world(lot, sp.pos) + face * float(VehicleTypes.spec(kind_of).get("len", 4.5)) * 0.5
		# The same car, its body as it is with snow on the ground.
		_snow = 1.0
		var snowy := _model(kind_of, id)
		_snow = 0.0
		var parts := []
		for p in _parked_items(car, front, face):
			parts.append([p[1], p[4], snowy, _far(kind_of, snowy), _lot_floats(p[2], p[3])])
		# Customers fill from the door outward, give or take a few stalls.
		var rank := 1.0 - float(k - staff) / maxf(float(n - staff), 1.0)
		var jitter := float(absi(hash([key, i, "lot when"])) % 1000) / 1000.0
		job.list.append([i, parts, k < staff, rank * 0.65 + jitter * 0.35, jitter])
	_snow = winter
	if job.k < n:
		return null
	_lot_build = {}
	_lot_stalls[key] = [sig, job.list]
	return job.list


## One instance's MultiMesh buffer floats: the transform's three rows, a
## white colour and the custom data.
static func _lot_floats(xf: Transform3D, custom: Color) -> PackedFloat32Array:
	var b := xf.basis
	var o := xf.origin
	return PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		1.0, 1.0, 1.0, 1.0, custom.r, custom.g, custom.b, custom.a])


## Fills the lot cars' own batches again (they never count against the
## simulation's cars: the tier's lot_cars caps them, nearest lots first),
## a slice a frame until `until`, when a lot's cars changed, the snow came
## or went, the camera moved REFILL_M or the reach changed; the batches
## change all at once when it's done.
func _fill_lots(eye: Vector3, ultra2: float, cap: int, until: int) -> void:
	var snowy := _snow > 0.4
	if _lfill.is_empty():
		var last: Array = _lfill_for
		if not _lfill_due and not last.is_empty() and eye.distance_squared_to(last[0]) < REFILL_M * REFILL_M \
				and absf(_reach_far - float(last[1])) < maxf(REFILL_M, _reach_far * 0.05) \
				and absf(_reach_near - float(last[2])) < REFILL_M and ultra2 == last[3] and snowy == last[4]:
			return
		_lfill_due = false
		_lfill = {"eye": eye, "far": _reach_far, "near": _reach_near, "ultra2": ultra2, "snow": snowy,
			"keys": _lot_shown.keys(), "at": 0, "by": [{}, {}, {}], "n": 0}
	var job := _lfill
	var keys: Array = job.keys
	var e: Vector3 = job.eye
	var far2: float = job.far * job.far
	var near2: float = job.near * job.near
	var by: Array = job.by
	var winter := 2 if job.snow else 0
	while job.at < keys.size() and job.n < cap and Time.get_ticks_usec() < until:
		var shown: Array = _lot_shown.get(keys[job.at], _NONE)
		job.at += 1
		if shown.is_empty():
			continue
		var at: Vector3 = shown[2]
		var d2 := Vector2(at.x - e.x, at.z - e.z).length_squared()
		if d2 > far2:
			continue
		var lod := 1
		if d2 < near2:
			lod = 2 if d2 < job.ultra2 else 0
		var lists: Dictionary = by[lod]
		var stalls: Array = shown[3]
		for k in shown[0]:
			for part in stalls[k][1]:
				var key: String = part[winter + (1 if lod == 1 else 0)]
				if not lists.has(key):
					lists[key] = PackedFloat32Array()
				(lists[key] as PackedFloat32Array).append_array(part[4])
				job.n += 1
	if job.at < keys.size() and job.n < cap:
		return
	# Done: every batch at once.
	for key in _lmm:
		for lod in 3:
			var mi = _lmm[key][lod]
			if mi != null and not by[lod].has(key):
				mi.multimesh.instance_count = 0
	for lod in 3:
		for key in by[lod]:
			if not _batches.has(key):
				continue
			var buf: PackedFloat32Array = by[lod][key]
			var mm: MultiMesh = _lot_batch(key, lod).multimesh
			mm.instance_count = buf.size() / 20
			mm.buffer = buf
	_lot_drawn = job.n
	_lfill_for = [job.eye, job.far, job.near, job.ultra2, job.snow]
	_lfill = {}


## The lot cars' batch for a model and level of detail, made the first time
## one is drawn, sharing the moving ones' mesh and material.
func _lot_batch(key: String, lod: int) -> MultiMeshInstance3D:
	if not _lmm.has(key):
		_lmm[key] = [null, null, null]
	if _lmm[key][lod] != null:
		return _lmm[key][lod]
	if lod == 2 and _batches[key].size() < 3:
		_add_ultra_batch(key)
	var src: MultiMeshInstance3D = _batches[key][lod]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = src.multimesh.mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = src.material_override
	mi.cast_shadow = src.cast_shadow
	add_child(mi)
	_lmm[key][lod] = mi
	return mi


## Lot `key`'s pattern (LOT_KIND), "" for a lot that fills none.
func _lot_kind(key: String) -> String:
	var kind: String = LOT_KIND.get(BuildingTypes.type_of(town.buildings[key]), "")
	if kind == "shop" and _office_trades().has(str(town.families.owned.get("lot:" + key, {}).get("what", ""))):
		return "office"
	return kind


## The trades an office building can house (Names.is_office), as a set.
static var _offices := {}
static func _office_trades() -> Dictionary:
	if _offices.is_empty():
		for t in Names.TRADES:
			if t.get("office", false):
				_offices[t.trade] = true
	return _offices


## Which of a lot's stalls (indices into its list) have a car at `hour`.
func _lot_want(kind: String, ref: String, stalls: Array, hour: float) -> Array:
	var pattern := kind
	if kind == "shop":
		var b: Dictionary = town.families.owned.get(ref, {})
		if str(b.get("what", "")) in Balance.SHOP_EVENING_TRADES:
			pattern = "evening"
		elif bool(b.get("late", false)):
			pattern = "shop_late"
	var share := _eased(LOT_CUSTOMERS[pattern], hour)
	var span: Array = LOT_STAFF_HOURS[kind]
	var close := float(span[1]) + (3.0 if pattern != "shop" and kind == "shop" else 0.0)
	var out := []
	for k in stalls.size():
		var st: Array = stalls[k]
		var on := false
		if st[2]:
			# Staff come in over the hour before opening, leave over the
			# three quarters of an hour after closing.
			var j := float(st[4])
			on = hour >= float(span[0]) + j - 1.0 and hour < close + j * 0.75
			if kind == "factory" and not on:
				on = j < LOT_NIGHT_SHIFT
		else:
			on = float(st[3]) < share
		if on:
			out.append(k)
	return out


## Eased between [hour, share] points (flat before the first, after the last).
static func _eased(points: Array, hour: float) -> float:
	if hour <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		if hour < float(points[i][0]):
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return lerpf(float(a[1]), float(b[1]), smoothstep(float(a[0]), float(b[0]), hour))
	return float(points[-1][1])


## One step from `shown` toward `want` (both sorted stall lists): one car
## that should go leaves, or else one that should come pulls in, picked by
## `pick`.
static func _lot_step(shown: Array, want: Array, pick: int) -> Array:
	var gone := shown.filter(func(k): return not want.has(k))
	if not gone.is_empty():
		var out := shown.duplicate()
		out.erase(gone[absi(pick) % gone.size()])
		return out
	var come := want.filter(func(k): return not shown.has(k))
	var out := shown.duplicate()
	out.append(come[absi(pick) % come.size()])
	out.sort()
	return out


## What a parked vehicle draws, standing with its front bumper at `pos`
## facing `face`: [[front, mesh key, transform, custom, far mesh key], ...].
func _parked_items(car: Dictionary, pos: Vector3, face: Vector3) -> Array:
	var flat := face
	if flat.length() < 0.5:
		flat = Vector3.FORWARD
	var kind := _kind(car)
	# Front and back on the ground, so it sits level with the slope.
	var front: Vector3 = Terrain.stand(pos)
	var dir: Vector3 = (front - Terrain.stand(pos - flat * float(VehicleModels.AXLE.get(kind, 3.5)))).normalized()
	var paint := VehicleTypes.paint(kind, car.id)
	var custom := Color(paint.r, paint.g, paint.b, VehicleMaterial.OFF)
	if VehicleModels.ARTIC.has(kind):
		# A rig parked straight: the trailer lined up behind the cab.
		var art: Dictionary = VehicleModels.ARTIC[kind]
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), front)
		var hitch: Vector3 = xf * Vector3(0, 0, art.hitch)
		var trailer := VehicleModels.trailer_for(art.trailer, car.get("cargo", {}))
		return [[front, art.cab, xf, custom, art.cab], [front, trailer, Transform3D(xf.basis, hitch + dir * float(art.pin)),
			Color(1, 1, 1, VehicleMaterial.OFF), trailer]]
	# Parked in the same body it drove in.
	var model := _model(kind, car.id)
	return [[front, model, Transform3D(Basis.looking_at(dir, Vector3.UP), front), custom, _far(kind, model)]]


## A household car in its home's garage, drawn out on the drive in front of
## its bay instead (OUT_FRONT cars in OUT_OF, picked by the car's id, so
## every computer and every load shows the same ones), where the drive is
## long enough. Only the drawing moves it: the simulation, saves and the
## copies still have it in the garage. [] for one that stays inside.
func _out_front(car: Dictionary) -> Array:
	if not car.has("face") or not _out_pick(car, str(car.get("at_place", "")), car.pos, car.face):
		return _NONE
	return _parked_items(car, car.pos - car.face * DRIVE_OUT, car.face)


## Whether car `car`, in (or bound for) its home's garage at place `ref`
## with its front bumper at `pos` facing `face`, is one drawn out on the
## drive (see _out_front; whether the drive is clear is looked at there).
func _out_pick(car: Dictionary, ref: String, pos: Vector3, face: Vector3) -> bool:
	if town == null or not _drive_cars() or not ref.begins_with("lot:") \
			or absi(hash([car.id, "out front"])) % OUT_OF >= OUT_FRONT:
		return false
	var kind := _kind(car)
	if kind == "golf_cart" or VehicleModels.ARTIC.has(kind):
		return false
	var b = town.buildings.get(ref.substr(4))
	var lot = town.lots.get(ref.substr(4))
	if b == null or lot == null or int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
		return false  # a factory's bay or an office deck stays shut
	var at: Vector3 = pos - face * DRIVE_OUT
	var len := float(car.get("len", 4.5))
	var inv := SiteLayout.frame(lot).affine_inverse()
	# (A short drive, or a long pickup: it would stick out over the sidewalk.)
	return (inv * (at - face * len * 0.5)).z >= DRIVE_MIN_Z and (inv * (at - face * len)).z >= 0.0


## True for a household car drawn out on the drive rather than in its
## garage: parked there now, or (`leaving`) backing out from there, or
## coming home to stand there. DoorEvents opens no door for it.
func out_front(car: Dictionary, leaving := false) -> bool:
	if car.has("at_place"):
		return _out_ids.has(car.id)
	if leaving:
		return _leaving_out.has(car.id) or _out_ids.has(car.id)
	var ref: String = car.get("to_place", "")
	var spot: int = car.get("to_spot", -1)
	var had: Array = _arrive_out.get(car.id, _NONE)
	if not had.is_empty() and had[0] == ref and had[1] == spot:
		return had[2]
	var s := _spot(ref, spot, car.get("spot_geo", {}))
	var out: bool = not s.is_empty() and s.kind == "garage" \
		and _out_pick(car, ref, s.pos + s.face * float(car.get("len", 4.5)) * 0.5, s.face)
	if _arrive_out.size() > 2048:
		_arrive_out.clear()
	_arrive_out[car.id] = [ref, spot, out]
	return out


## For a car drawn out on the drive, on its way into or out of the garage
## behind it (path `c`): [metres to draw it short of where it is along the
## path, metres to draw it ahead while backing out, and a nudge onto the
## very place it stands parked (the path runs a little off square to the
## garage), eased in or out over DRIVE_EASE metres]. Nothing for any other.
func _on_drive(car: Dictionary, c) -> Array:
	if c == null or int(c.get("node", 0)) != -1:
		_leaving_out.erase(car.id)  # out in the street now
		return _STAYS
	var jd := float(car.jd)
	var len := float(car.get("len", 4.5))
	if int(c.wi) == -1:
		# Backing out of where it was parked: from the drive, not the garage.
		if jd > DRIVE_OUT + DRIVE_EASE or not (_leaving_out.has(car.id) or _out_ids.has(car.id)):
			return _STAYS
		var ahead := maxf(DRIVE_OUT - jd, 0.0)
		# Its path starts at its front bumper in the garage, facing in (d0).
		var pts: PackedVector3Array = c.pts
		var nudge := _nudge(car, pts[0] - c.d0 * DRIVE_OUT, DRIVE_OUT - jd)
		return [0.0, ahead, nudge * clampf(1.0 - (jd + ahead - DRIVE_OUT) / DRIVE_EASE, 0.0, 1.0)]
	if int(c.wo) != -1:
		return _STAYS
	# Turning in and up the drive to the garage: it stops on the drive.
	var stop := float(c.len) - DRIVE_OUT
	if jd < stop - DRIVE_EASE or not out_front(car):
		return _STAYS
	var s := _spot(car.get("to_place", ""), car.get("to_spot", -1), car.get("spot_geo", {}))
	var nudge := Vector3.ZERO
	if not s.is_empty():
		nudge = _nudge(car, s.pos + s.face * (len * 0.5 - DRIVE_OUT), stop - jd) \
			* clampf(1.0 - (stop - minf(jd, stop)) / DRIVE_EASE, 0.0, 1.0)
	return [maxf(jd - stop, 0.0), 0.0, nudge]


## From the point `along` metres on along a car's path to `want`, where its
## front bumper stands parked out on the drive, flat.
func _nudge(car: Dictionary, want: Vector3, along: float) -> Vector3:
	var d: Vector3 = want - traffic.car_pose(car, along)[0]
	return Vector3(d.x, 0.0, d.z)


## A place's spot, or `geo` when there is one (where a path ends).
func _spot(ref: String, spot: int, geo: Dictionary) -> Dictionary:
	if not geo.is_empty():
		return geo
	if ref == "" or ref == "edge" or spot < 0:
		return {}
	var spots: Array = traffic.place(ref).get("spots", [])
	return spots[spot] if spot < spots.size() else {}


## Parked vehicles go in batches of their own, filled again when one parks
## or leaves, the camera has moved REFILL_M or the reach has changed by
## that much, and at most every REFILL_FRAMES frames, not every frame: a big
## town has thousands standing in drives and lots. The count drawn (for the
## tier's cap) is the last fill's, a little off while the reach changes.
func _fill_parked(eye: Vector3, ultra2: float, rebuilt: bool) -> void:
	_pfill_due = _pfill_due or rebuilt
	_pfill_age += 1
	if _pfill[0] != Vector3.INF and _pfill_age < REFILL_FRAMES:
		return
	if not _pfill_due and eye.distance_squared_to(_pfill[0]) < REFILL_M * REFILL_M \
			and absf(_reach_far - float(_pfill[1])) < maxf(REFILL_M, _reach_far * 0.05) \
			and absf(_reach_near - float(_pfill[2])) < REFILL_M and ultra2 == _pfill[3]:
		return
	_pfill = [eye, _reach_far, _reach_near, ultra2]
	_pfill_due = false
	_pfill_age = 0
	var by := [{}, {}, {}]  # lod -> mesh key -> [[transforms], [customs]]
	_parked_drawn = 0
	for item in _parked:
		var dist: float = item[0].distance_to(eye)
		if dist > _reach_far:
			continue
		_parked_drawn += 1
		var lod := 1
		var key: String = item[4]
		if dist < _reach_near:
			lod = 2 if dist * dist < ultra2 else 0
			key = item[1]
		var lists: Dictionary = by[lod]
		if not lists.has(key):
			lists[key] = [[], []]
		lists[key][0].append(item[2])
		lists[key][1].append(item[3])
	for key in _pmm:
		for lod in 3:
			var mi = _pmm[key][lod]
			if mi != null and not by[lod].has(key) and mi.multimesh.visible_instance_count != 0:
				mi.multimesh.visible_instance_count = 0
	for lod in 3:
		for key in by[lod]:
			if not _batches.has(key):
				continue
			var mm: MultiMesh = _parked_batch(key, lod).multimesh
			var xfs: Array = by[lod][key][0]
			var cu: Array = by[lod][key][1]
			var n := xfs.size()
			if n > mm.instance_count:
				mm.instance_count = n + n / 4 + 8
				for i in mm.instance_count:
					mm.set_instance_color(i, Color.WHITE)
			for i in n:
				mm.set_instance_transform(i, xfs[i])
				mm.set_instance_custom_data(i, cu[i])
			mm.visible_instance_count = n


## The parked vehicles' batch for a model and level of detail, made the
## first time one is drawn, sharing the moving ones' mesh and material.
func _parked_batch(key: String, lod: int) -> MultiMeshInstance3D:
	if not _pmm.has(key):
		_pmm[key] = [null, null, null]
	if _pmm[key][lod] != null:
		return _pmm[key][lod]
	if lod == 2 and _batches[key].size() < 3:
		_add_ultra_batch(key)
	var src: MultiMeshInstance3D = _batches[key][lod]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = src.multimesh.mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = src.material_override
	mi.cast_shadow = src.cast_shadow
	add_child(mi)
	_pmm[key][lod] = mi
	return mi
