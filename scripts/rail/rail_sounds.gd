class_name RailSounds
extends Node3D
## The railroad's sounds, each tied to the thing making it: the diesel's
## rumble on the lead engine (rising with the throttle), the air horn blown
## for every grade crossing the way US engineers must (long, long, short,
## long, starting 15 to 20 seconds out and held until the engine is on the
## crossing: FRA 49 CFR 222.21, GCOR 5.8.2), two long blasts when a train
## leaves the yard ("proceed"), and the crossing bell ringing while the
## lights flash and the gates are down (MUTCD 8C). Everything is placed in
## the world and fades with distance; the camera is the listener. In a
## quiet zone the horn stays silent at crossings; the bells still ring.

## Train-time before a crossing (s) at which the horn starts: FRA says at
## least 15 and no more than 20.
const HORN_LEAD := 18.0
## Horn pattern for a crossing: [on from, on to] seconds after it starts.
## The last long is held until the engine reaches the crossing.
const CROSSING_HORN := [[0.0, 3.0], [3.5, 6.5], [7.0, 8.0], [8.5, 10.0]]
## Two long blasts: proceed.
const DEPART_HORN := [[0.0, 2.0], [2.5, 4.5]]
const ENGINE_SLOTS := 3
const BELL_SLOTS := 3
const HORN_SLOTS := 2
const ENGINE_RANGE := 700.0
const BELL_RANGE := 350.0
## A locomotive horn is about 96 to 110 dBA at 100 ft (49 CFR 229.129), so it
## carries across town.
const HORN_RANGE := 2400.0
const RAMP := 0.06  # attack and release of a blast (s)

var sim: CitySim
## Height of the rails at a point (RailView.height_at).
var ground: Callable

var _engines := []  # {player, tid, amp}
var _bells := []    # {player, index, amp}
var _horns := []    # {player, tid, amp}
var _blow := {}     # train id -> {pattern, t, crossing, reached}
var _honked := {}   # train id -> crossing index last blown for
var _stopped := {}  # train id -> seconds it has stood still
var _streams := {}
var _wait := 0.0
var _picks := -1
var _mix_version := -1
## The county's through freights near enough to hear: "c<id>" -> [head
## (view coordinates, rail height), speed m/s], refreshed with the picks.
var _county := {}
## Each county corridor's grade crossings, metres along it (county roads and
## the town's streets alike), sorted.
static var _county_xings := {}


func setup(s: CitySim, height: Callable) -> void:
	sim = s
	ground = height


func _ready() -> void:
	CityAudio.setup_buses()
	_load_streams()
	for i in ENGINE_SLOTS:
		_engines.append({"player": _player("diesel", 16.0, ENGINE_RANGE), "tid": -1, "amp": 0.0, "vary": 1.0})
	for i in BELL_SLOTS:
		_bells.append({"player": _player("crossing_bell", 10.0, BELL_RANGE), "index": -1, "amp": 0.0})
	for i in HORN_SLOTS:
		_horns.append({"player": _player("horn", 60.0, HORN_RANGE), "tid": -1, "amp": 0.0})
	_apply_mix()


## The hearing distances from the mix (SoundMix), on the players that exist.
func _apply_mix() -> void:
	_mix_version = SoundMix.version
	for s in _engines:
		s.player.max_distance = ENGINE_RANGE * SoundMix.range_scale("world/rail/diesel")
	for s in _bells:
		s.player.max_distance = BELL_RANGE * SoundMix.range_scale("world/rail/crossing_bell")
	for s in _horns:
		s.player.max_distance = HORN_RANGE * SoundMix.range_scale("world/rail/horn")


## The recordings, again after a pick in the Sound picker.
func _load_streams() -> void:
	_picks = SoundSettings.picks_version
	for f in ["diesel", "horn", "crossing_bell"]:
		_streams[f] = SoundSettings.stream("world/rail/" + f)
	for s in _engines + _bells + _horns:
		CityAudio._swap(s.player, _streams[str(s.player.get_meta("sound")).get_file()])


func _player(stream: String, unit: float, range_m: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[stream]
	p.set_meta("sound", "world/rail/" + stream)
	p.bus = "World"
	p.unit_size = unit
	p.max_distance = range_m
	p.attenuation_filter_cutoff_hz = 20500.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.volume_db = -80.0
	add_child(p)
	return p


## True while a horn pattern is sounding, `t` seconds after it started.
## `reached`: seconds after the start at which the engine got to the
## crossing (INF until then); the last long is held until it does.
static func horn_on(pattern: Array, t: float, reached: float = 0.0) -> bool:
	var last: Array = pattern[-1]
	if t >= last[0] and t < maxf(last[1], reached):
		return true
	for span in pattern:
		if t >= span[0] and t < span[1]:
			return true
	return false


## When the horn should start for a crossing `dist` metres ahead at `v` m/s.
static func horn_due(dist: float, v: float) -> bool:
	return v > 0.5 and dist / v <= HORN_LEAD


func _process(delta: float) -> void:
	if sim == null or _streams.is_empty():
		return
	if _picks != SoundSettings.picks_version:
		_load_streams()
	if _mix_version != SoundMix.version:
		_apply_mix()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ear := cam.global_position
	_wait -= delta
	if _wait <= 0.0:
		_wait = 0.25
		_watch_county(ear)
		_watch_trains(0.25)
		_pick_engines(ear)
		_pick_bells(ear)
	for tid in _blow.keys():
		_blow[tid].t += delta
	_update_horns(ear, delta)
	for s in _engines:
		_fade(s, delta)
	for s in _bells:
		_fade(s, delta)


## Starts horn patterns: for each crossing coming up, and when a train
## pulls out after standing.
func _watch_trains(dt: float) -> void:
	for tid in _blow.keys():
		if not sim.rail.trains.has(tid) and not _county.has(tid):
			_blow.erase(tid)
	for tid in sim.rail.trains:
		var t: Dictionary = sim.rail.trains[tid]
		var moving: bool = t.state == "run" and float(t.v) > 0.3
		if not moving:
			_stopped[tid] = float(_stopped.get(tid, 0.0)) + dt
		elif float(_stopped.get(tid, 0.0)) > 8.0 and not _blow.has(tid):
			_blow[tid] = {"pattern": DEPART_HORN, "t": 0.0, "crossing": -1, "reached": 0.0}
			_stopped[tid] = 0.0
		else:
			_stopped[tid] = 0.0
		var nc := sim.rail.next_crossing(tid)
		var b: Dictionary = _blow.get(tid, {})
		if not b.is_empty() and int(b.crossing) != -1 and b.reached == INF \
				and (nc.is_empty() or int(nc.index) != int(b.crossing) or float(nc.dist) < 3.0):
			b.reached = b.t
		# Once past it, the crossing gets the horn again on the way back.
		if _honked.has(tid) and (nc.is_empty() or int(nc.index) != int(_honked[tid])):
			_honked.erase(tid)
		if nc.is_empty() or _honked.get(tid, -1) == int(nc.index):
			continue
		# A quiet zone (49 CFR 222): no routine horn at the town's crossings.
		if sim.pollution.quiet.has(int(t.depot)):
			continue
		if horn_due(float(nc.dist), float(t.v)) and (b.is_empty() or int(b.crossing) == -1):
			_honked[tid] = int(nc.index)
			_blow[tid] = {"pattern": CROSSING_HORN, "t": 0.0, "crossing": int(nc.index), "reached": INF}


## The county's through freights blow for every public grade crossing on
## the line, out in the country as in town (no quiet zones out there). At
## track speed the engine reaches the crossing a known time after the horn
## starts, and holds the last long until then.
func _watch_county(ear: Vector3) -> void:
	_county.clear()
	if not sim.county_rail:
		return
	var reach := HORN_RANGE * SoundMix.range_scale("world/rail/horn")
	var cs := CountyTrains.corridors()
	for t in sim.county_trains.now(sim.tick_count):
		var c: Dictionary = cs[t.corridor]
		var p := CountyTrains._at(c, float(t.s))
		var head := Vector3(p.x - Terrain.view_origin.x, 0.0, p.y - Terrain.view_origin.y)
		if head.distance_to(Vector3(ear.x, 0.0, ear.z)) > reach:
			continue
		var y := CountyTrainView._rail_y(p)
		if is_nan(y):
			continue  # inside a backdrop town
		head.y = y
		var key := "c%d" % int(t.id)
		var v := 0.0 if t.get("stopped", false) else CountyTrains.SPEED
		_county[key] = [head, v]
		if v <= 0.0 or (_blow.has(key) and int(_blow[key].crossing) != -1):
			continue
		var ahead := INF
		var at := -1.0
		for xs in _xings_on(int(t.corridor)):
			var d := (float(xs) - float(t.s)) * float(t.dir)
			if d > 0.0 and d < ahead:
				ahead = d
				at = xs
		if at < 0.0 or _honked.get(key, -1.0) == at:
			continue
		if horn_due(ahead, v):
			_honked[key] = at
			_blow[key] = {"pattern": CROSSING_HORN, "t": 0.0, "crossing": 0, "reached": ahead / v}


## Grade crossings along county corridor `ci`, metres: the mapped county
## roads' crossings (CountyRail kind 1) and the town's streets.
func _xings_on(ci: int) -> Array:
	if not _county_xings.has(ci):
		var out := []
		var c: Dictionary = CountyTrains.corridors()[ci]
		var s := 0.0
		var last := -INF
		while s < float(c.length):
			var p := CountyTrains._at(c, s)
			var n := CountyRail.near(p.x, p.y, 8.0)
			if not n.is_empty() and CountyRail.kind_at(n.route, n.along) == 1:
				if s - last > 40.0:
					out.append(s)
				last = s
			s += 10.0
		_county_xings[ci] = out
	var all: Array = _county_xings[ci].duplicate()
	for x in sim.county_trains.crossings:
		if int(x.corridor) == ci:
			all.append(float(x.s))
	return all


func _update_horns(ear: Vector3, delta: float) -> void:
	var want := {}
	for tid in _blow:
		var b: Dictionary = _blow[tid]
		var last: Array = b.pattern[-1]
		if b.t > maxf(float(last[1]), float(b.reached)) + 0.5:
			_blow.erase(tid)
			continue
		var head := _head(tid)
		if head.x == INF or head.distance_to(ear) > HORN_RANGE * SoundMix.range_scale("world/rail/horn"):
			continue
		want[tid] = [horn_on(b.pattern, float(b.t), float(b.reached)), head]
	# The mix can allow fewer horns at once than there are players.
	var usable := _horns.slice(0, SoundMix.cap("world/rail/horn", HORN_SLOTS))
	for s in _horns:
		if str(s.tid) != "-1" and (not want.has(s.tid) or not s in usable):
			s.tid = -1
	for tid in want:
		var slot: Dictionary = {}
		for s in usable:
			if str(s.tid) == str(tid):
				slot = s
		if slot.is_empty():
			for s in usable:
				if str(s.tid) == "-1" and float(s.amp) <= 0.0:
					slot = s
					slot.tid = tid
					break
		if slot.is_empty():
			continue
		slot.player.global_position = want[tid][1] + Vector3.UP * 4.5
	for s in _horns:
		var on: bool = str(s.tid) != "-1" and want[s.tid][0]
		s.amp = move_toward(float(s.amp), 1.0 if on else 0.0, delta / RAMP)
		_apply(s, -2.0)


## The nearest moving or idling locomotives get the diesel loop.
func _pick_engines(ear: Vector3) -> void:
	var near := []
	for tid in sim.rail.trains.keys() + _county.keys():
		var head := _head(tid)
		if head.x == INF:
			continue
		var d := head.distance_to(ear)
		if d < ENGINE_RANGE * SoundMix.range_scale("world/rail/diesel"):
			near.append([d, tid, head])
	near.sort_custom(func(a, b): return a[0] < b[0])
	near = near.slice(0, SoundMix.cap("world/rail/diesel", ENGINE_SLOTS))
	var ids := near.map(func(e): return str(e[1]))
	for s in _engines:
		if not str(s.tid) in ids:
			s.want = 0.0
			if float(s.amp) <= 0.0:
				s.tid = -1
	for e in near:
		var slot: Dictionary = {}
		for s in _engines:
			if str(s.tid) == str(e[1]):
				slot = s
		if slot.is_empty():
			for s in _engines:
				if str(s.tid) == "-1":
					slot = s
					slot.tid = e[1]
					slot.vary = SoundMix.pitch_for("world/rail/diesel")
					break
		if slot.is_empty():
			continue
		var v: float = _county[e[1]][1] if _county.has(e[1]) else float(sim.rail.trains[e[1]].v)
		var throttle := clampf(v / 18.0, 0.0, 1.0)
		slot.player.global_position = e[2] + Vector3.UP * 3.5
		# Notch 8 runs the prime mover near 900 rpm against about 300 at idle;
		# the recording is sped up a little with the throttle.
		slot.player.pitch_scale = lerpf(0.85, 1.2, throttle) * float(slot.vary)
		slot.want = lerpf(0.55, 1.0, throttle)


## Bells ring at the nearest crossings whose gates are down.
func _pick_bells(ear: Vector3) -> void:
	var near := []
	var xs := sim.all_crossings()
	for k in xs.size():
		var c: Dictionary = xs[k]
		if not c.closed:
			continue
		var p: Vector3 = c.pos
		var d := p.distance_to(Vector3(ear.x, p.y, ear.z))
		if d < BELL_RANGE * 1.5 * SoundMix.range_scale("world/rail/crossing_bell"):
			near.append([d, k])
	near.sort_custom(func(a, b): return a[0] < b[0])
	near = near.slice(0, SoundMix.cap("world/rail/crossing_bell", BELL_SLOTS))
	var ids := near.map(func(e): return e[1])
	for s in _bells:
		if not int(s.index) in ids:
			s.want = 0.0
			if float(s.amp) <= 0.0:
				s.index = -1
	for e in near:
		var slot: Dictionary = {}
		for s in _bells:
			if int(s.index) == int(e[1]):
				slot = s
		if slot.is_empty():
			for s in _bells:
				if int(s.index) == -1:
					slot = s
					slot.index = e[1]
					break
		if slot.is_empty():
			continue
		var p: Vector3 = xs[e[1]].pos
		var y: float = ground.call(p) if ground.is_valid() else p.y
		# The bell sits on top of the signal mast, beside the road.
		slot.player.global_position = Vector3(p.x, y + 4.0, p.z)
		slot.want = 1.0


func _fade(s: Dictionary, delta: float) -> void:
	s.amp = move_toward(float(s.amp), float(s.get("want", 0.0)), delta * 1.5)
	_apply(s, 0.0)


func _apply(s: Dictionary, gain_db: float) -> void:
	var p: AudioStreamPlayer3D = s.player
	var amp: float = s.amp
	if amp <= 0.001:
		if p.playing:
			p.stop()
		p.volume_db = -80.0
		return
	if not p.playing:
		p.play()
	var cam := get_viewport().get_camera_3d()
	p.volume_db = linear_to_db(amp) + gain_db
	if cam:
		p.volume_db = SoundSettings.level3d(p.get_meta("sound"), p, p.volume_db, cam.global_position)


## Where a train's lead engine is, with the rails' height (INF if it's away).
func _head(tid) -> Vector3:
	if tid is String:
		return _county[tid][0] if _county.has(tid) else Vector3(INF, 0, 0)
	var poses := sim.rail.car_poses(tid)
	if poses.is_empty():
		return Vector3(INF, 0, 0)
	var f: Vector3 = poses[0][1]
	var y: float = ground.call(f) if ground.is_valid() else f.y
	return Vector3(f.x, y, f.z)
