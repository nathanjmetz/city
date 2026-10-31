extends "res://tools/look_round.gd"
## Close pictures of road treatments (docs/spec-road-treatments.md, step 1),
## taken the look round's way (same town, date, hour and weather; see
## tools/look_round.gd for how to run it, with a throwaway HOME):
##   HOME=/tmp/x godot --resolution 1920x1080 -s tools/treatment_shot.gd -- OUT_DIR
## PerfTown "big" has factory streets on its east edge and main streets on
## its middle rows; one block of a shop street near the middle is zoned for
## factories on one side and built out, so it is a mixed street (the shops
## across keep their main street).
## Shots: a factory street, a main street, the mixed street (40 m), and the
## main street at night (its lanterns).

## Near the shop street block made mixed.
const MIXED := Vector3(0.0, 0.0, -210.0)


func _init() -> void:
	SHOTS = [
		["t1_factory_street", Vector3(560.0, 0.0, -150.0), 0.0, 18.0, 38.0, "day", FAIR],
		["t2_main_street", Vector3(-70.0, 0.0, 184.0), 90.0, 18.0, 38.0, "day", FAIR],
		["t3_mixed_street", MIXED, 90.0, 20.0, 40.0, "day", FAIR],
		["t4_main_street_night", Vector3(-230.0, 0.0, 0.0), 90.0, 18.0, 38.0, "night", FAIR],
	]


func _build() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	PerfTown.build(sim, "big")
	sim.require_utilities = false
	# The mixed block: one side of a shop street rezoned for factories and
	# built out once its lots are cut (after the sides' first look).
	for i in 2 * RoadTreatments.EVERY:
		sim.tick()
	var mixed := -1
	var best := INF
	for id in sim.network.segments:
		if sim.network.segments[id].type != RoadStyle.Type.STREET or sim.treatments.kind(id, -1) != RoadTreatments.MAIN \
				or sim.treatments.kind(id, 1) != RoadTreatments.MAIN:
			continue
		var c := sim.network.curve_of(id)
		var d := RoadNetwork.bezier(c[0], c[1], c[2], 0.5).distance_to(MIXED)
		if d < best:
			best = d
			mixed = id
	if mixed >= 0:
		sim.apply({"type": "zone_frontage", "seg": mixed, "side": 1, "zone": ZoneMap.Zone.INDUSTRIAL})
		for i in 400:
			sim.tick()
			var ready := false
			for key in sim.empty_zoned_lots():
				if int(sim.lots[key].seg) == mixed:
					ready = true
			if ready:
				break
		PerfTown._fill(sim)
	for i in WARM_TICKS:
		sim.tick()
	_main.set_speed(0)
	for n in _main.find_children("*", "FirstTownTour", true, false):
		n.stop()
	for c in _main.get_children():
		if c is CityCamera:
			_cam = c
		if c is Weather:
			_weather = c
		if c is CanvasLayer or c is LotAlerts:
			c.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Weather.on = true
	DayNight.cycle_on = true
	DayNight.seasons_on = true
	_dusk_hour = _dusk(DAY[0], DAY[1])
	_aim(sim, 0, _factory)
	_aim(sim, 1, _main_side)
	_aim(sim, 2, _mixed, mixed)
	SHOTS[3][1] = SHOTS[1][1]
	SHOTS[3][2] = SHOTS[1][2]
	_set_shot(SHOTS[0])


static func _factory(t: RoadTreatments, id: int) -> bool:
	return t.kind(id, -1) == RoadTreatments.FACTORY and t.kind(id, 1) == RoadTreatments.FACTORY


static func _main_side(t: RoadTreatments, id: int) -> bool:
	return t.kind(id, -1) == RoadTreatments.MAIN and t.kind(id, 1) == RoadTreatments.MAIN


static func _mixed(t: RoadTreatments, id: int) -> bool:
	return t.kind(id, -1) != t.kind(id, 1) and RoadTreatments.FACTORY in [t.kind(id, -1), t.kind(id, 1)]


## Points shot `i` down the middle of the street nearest its spot that
## `want` picks (or of road `pick`), looking along it.
func _aim(sim: CitySim, i: int, want: Callable, pick := -1) -> void:
	var at: Vector3 = SHOTS[i][1]
	var best := INF
	var ids := sim.network.segments.keys() if pick < 0 else []
	ids.sort()
	for id in ids:
		if sim.network.segments[id].type != RoadStyle.Type.STREET or not want.call(sim.treatments, id):
			continue
		var c := sim.network.curve_of(id)
		var d := Vector2(RoadNetwork.bezier(c[0], c[1], c[2], 0.5).x, RoadNetwork.bezier(c[0], c[1], c[2], 0.5).z) \
			.distance_to(Vector2(at.x, at.z))
		if d < best:
			best = d
			pick = id
	if pick < 0:
		return
	var c := sim.network.curve_of(pick)
	var dir: Vector3 = (c[2] - c[0]).normalized()
	SHOTS[i][1] = RoadNetwork.bezier(c[0], c[1], c[2], 0.5) - dir * 14.0
	SHOTS[i][2] = rad_to_deg(atan2(dir.x, dir.z))
	print("treatment_shot: %s on road %d: %s" % [SHOTS[i][0], pick, sim.treatments.rows(sim, pick)])
