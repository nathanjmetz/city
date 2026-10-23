class_name CityAudio
extends Node3D
## The sound of the town, placed in the world. Cars, homes, shops, factories,
## utilities and farm fields each carry their own sound, and only the ones
## nearest the camera play, getting quieter with distance (the camera is the
## listener). From high up you hear wind and the far-off hum of whatever
## traffic is in view. A new building makes a soft thud where it goes up.

const CAR_SLOTS := 8
const AREA_SLOTS := 12
const CAR_RANGE := 260.0
const AREA_RANGE := 420.0
## How often (seconds) to re-pick the nearest sources.
const PICK_EVERY := 0.25
const FADE_PER_SEC := 2.5

var sim: CitySim
var camera: Camera3D
## Returns how far through the current tick the clock is, 0 to 1.
var tick_fraction: Callable

var _streams := {}
var _cars := []   # slots: {player, car, amp, want}
var _areas := []  # slots: {player, key, amp, want, next}
var _sources := []
var _sources_dirty := true
var _day := true
var _pick_wait := 0.0
var _wind: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _known_buildings := {}
var _build_sound: AudioStream
var _ear := Vector3.ZERO


func setup(s: CitySim, cam: Camera3D, fraction: Callable) -> void:
	sim = s
	camera = cam
	tick_fraction = fraction


func _ready() -> void:
	setup_buses()
	for f in SoundSources.GAIN.keys() + SoundSources.BEDS:
		_streams[f] = load_loop("res://assets/audio/world/%s.ogg" % f)
	_build_sound = load("res://assets/audio/ui/build.ogg")
	for i in CAR_SLOTS:
		var p := _spatial(10.0, CAR_RANGE)
		p.stream = _streams.car_engine
		_cars.append({"player": p, "car": null, "amp": 0.0, "want": 0.0})
	for i in AREA_SLOTS:
		_areas.append({"player": _spatial(14.0, AREA_RANGE), "key": "", "amp": 0.0, "want": 0.0, "next": null})
	_wind = _flat(_streams.wind_high, "Ambience")
	_hum = _flat(_streams.traffic_far, "Distant")
	for sig in [sim.buildings_changed, sim.lots_changed, sim.farms_changed, sim.zones_changed]:
		sig.connect(func(): _sources_dirty = true)
	sim.buildings_changed.connect(_on_buildings)
	_known_buildings = sim.buildings.duplicate()


## UI, World (effects), Ambience and Music buses under Master, plus a
## muffled "Distant" bus for far-off traffic. Made in code so there is no
## bus layout file to keep. The player's volumes (SoundSettings) go on them.
static func setup_buses() -> void:
	if AudioServer.get_bus_index("World") != -1:
		return
	for name in ["UI", "World", "Ambience", "Music", "Distant"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Ambience" if name == "Distant" else "Master")
	# Many loops at once must never clip.
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 500.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Distant"), lp)
	SoundSettings.apply()


static func load_loop(path: String) -> AudioStream:
	var s = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func _spatial(unit: float, range_m: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "World"
	p.unit_size = unit
	p.max_distance = range_m
	p.attenuation_filter_cutoff_hz = 20500.0  # no muffling; distance alone sets the volume
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.volume_db = -80.0
	add_child(p)
	return p


func _flat(stream: AudioStream, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	var t := Perf.now()
	_update(delta)
	Perf.add("frame.audio", t)


func _update(delta: float) -> void:
	if camera == null:
		return
	var ear := camera.global_position
	_ear = ear
	var day := SoundSources.is_day(int(sim.clock().hour))
	if day != _day:
		_day = day
		_sources_dirty = true
	_pick_wait -= delta
	if _pick_wait <= 0.0:
		_pick_wait = PICK_EVERY
		_pick_cars(ear)
		_pick_areas(ear)
	_move_cars()
	var step := FADE_PER_SEC * delta
	for s in _cars:
		_fade(s, step)
	for s in _areas:
		_fade_area(s, step)
	_update_beds(ear)


# --- Cars ---------------------------------------------------------------------

func _pick_cars(ear: Vector3) -> void:
	var near := []
	var max2 := CAR_RANGE * CAR_RANGE
	for car in sim.traffic.cars:
		var d2 := ear.distance_squared_to(sim.traffic.car_pose(car)[0])
		if d2 < max2:
			near.append([d2, car])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var chosen := []
	for e in near.slice(0, CAR_SLOTS):
		chosen.append(e[1])
	# Keep slots that still follow a chosen car; free the rest.
	var free := []
	for s in _cars:
		var keep := false
		for c in chosen:
			if is_same(c, s.car):
				keep = true
				chosen.erase(c)
				break
		s.want = 1.0 if keep else 0.0
		if not keep:
			free.append(s)
	for c in chosen:
		# Take a silent slot first so cars do not cut out mid-sound.
		free.sort_custom(func(a, b): return a.amp < b.amp)
		if free.is_empty():
			break
		var s: Dictionary = free.pop_front()
		s.car = c
		s.want = 1.0
		var p: AudioStreamPlayer3D = s.player
		if not p.playing:
			p.play(randf() * 3.5)


func _move_cars() -> void:
	var frac: float = tick_fraction.call()
	for s in _cars:
		var car = s.car
		if car == null:
			continue
		if not sim.traffic.cars.has(car):
			s.want = 0.0  # arrived; let it fade where it stopped
			continue
		var p: AudioStreamPlayer3D = s.player
		p.position = Terrain.lift(sim.traffic.car_pose(car, car.v * TrafficSim.DT * frac)[0]) + Vector3.UP * 0.6
		# Engine note rises with speed: idling at a light up to 65 mph.
		p.pitch_scale = clampf(0.65 + car.v / 28.0, 0.6, 1.7)
		s.speed_db = lerpf(-10.0, 0.0, clampf(car.v / 25.0, 0.0, 1.0))


func _fade(s: Dictionary, step: float) -> void:
	s.amp = move_toward(s.amp, s.want, step)
	var p: AudioStreamPlayer3D = s.player
	p.volume_db = SoundSettings.level3d("world/car_engine", p,
		linear_to_db(maxf(s.amp, 0.0001)) + s.get("speed_db", 0.0), _ear)
	if s.amp <= 0.0 and s.want <= 0.0:
		s.car = null
		if p.playing:
			p.stop()


# --- Homes, shops, factories, utilities, fields --------------------------------

func _pick_areas(ear: Vector3) -> void:
	if _sources_dirty:
		_sources_dirty = false
		_sources = SoundSources.gather(sim, int(sim.clock().hour))
	var chosen := SoundSources.pick(_sources, ear, AREA_SLOTS, AREA_RANGE)
	var by_key := {}
	for c in chosen:
		by_key[c.key] = c
	var free := []
	for s in _areas:
		if by_key.has(s.key):
			s.want = 1.0
			s.next = null
			by_key.erase(s.key)
		else:
			s.want = 0.0
			free.append(s)
	free.sort_custom(func(a, b): return a.amp < b.amp)
	for c in by_key.values():
		if free.is_empty():
			break
		free.pop_front().next = c


func _fade_area(s: Dictionary, step: float) -> void:
	var p: AudioStreamPlayer3D = s.player
	# A slot handed a new source fades out first, then moves and fades in.
	if s.next != null and s.amp <= 0.0:
		var c: Dictionary = s.next
		s.next = null
		s.key = c.key
		s.sound = c.sound
		s.want = 1.0
		p.stream = _streams[c.sound]
		# Birds, katydids, leaves and fields are ambience; the rest effects.
		p.bus = "Ambience" if SoundSettings.info("world/" + c.sound)[2] == "ambience" else "World"
		p.position = Terrain.lift(c.pos)
		p.play(randf() * 4.0)
	s.amp = move_toward(s.amp, s.want, step)
	var sound: String = s.get("sound", "")
	p.volume_db = linear_to_db(maxf(s.amp, 0.0001)) + SoundSources.GAIN.get(sound, 0.0)
	if sound != "" and p.playing:
		p.volume_db = SoundSettings.level3d("world/" + sound, p, p.volume_db, _ear)
	if s.amp <= 0.0 and s.want <= 0.0 and s.next == null and p.playing:
		p.stop()
		s.key = ""


# --- Zoomed-out beds -----------------------------------------------------------

func _update_beds(ear: Vector3) -> void:
	var h := maxf(ear.y, 1.0)
	# Wind grows as you climb: barely there at street level, broad from above.
	var wind := clampf((h - 20.0) / 500.0, 0.05, 0.8)
	_wind.volume_db = SoundSettings.level("world/wind_high", linear_to_db(wind) - 8.0)
	# The far-off hum is the traffic actually in view: count cars around the
	# spot the camera looks at, within a radius that grows with height.
	var fwd := -camera.global_basis.z
	var look := ear
	if fwd.y < -0.05:
		look = ear + fwd * (ear.y / -fwd.y)
	var r2 := pow(h * 1.4, 2.0)
	var n := 0
	for car in sim.traffic.cars:
		var p: Vector3 = sim.traffic.car_pose(car)[0]
		if Vector2(p.x - look.x, p.z - look.z).length_squared() < r2:
			n += 1
	var hum := clampf(n / 60.0, 0.0, 1.0) * clampf((h - 60.0) / 300.0, 0.0, 1.0)
	_hum.volume_db = SoundSettings.level("world/traffic_far", linear_to_db(maxf(hum, 0.0001)))


# --- New buildings -------------------------------------------------------------

func _on_buildings() -> void:
	if camera == null:
		_known_buildings = sim.buildings.duplicate()
		return
	var ear := camera.global_position
	var fresh := sim.buildings.keys().filter(func(k): return not _known_buildings.has(k))
	_known_buildings = sim.buildings.duplicate()
	# A whole town appearing at once is a save loading, not construction.
	if fresh.size() > 4:
		return
	if SoundSettings.is_flagged("ui/build"):
		return
	var plays := 0
	for key in fresh:
		if not sim.lots.has(key) or plays >= 2:
			continue
		var pos: Vector3 = sim.lots[key].pos
		if ear.distance_to(pos) < 350.0:
			plays += 1
			var p := _spatial(12.0, 350.0)
			p.stream = _build_sound
			p.position = Terrain.lift(pos)
			p.volume_db = -10.0
			p.finished.connect(p.queue_free)
			p.play()
			SoundSettings.level3d("ui/build", p, p.volume_db, ear)
