class_name SoundSettings
extends RefCounted
## The player's audio settings, kept in user://audio.json: a volume for each
## channel (like CS2's Audio tab), mute, and the sounds they flagged as bad.
## A flagged sound goes silent at once wherever it plays, and the flag goes
## to the region server with the play notes so the sound gets replaced.
##
## Picks from the Sound picker (Audio page) swap in another recording for
## a sound: the file is kept in user://sfx/ and stream() hands it out
## instead of the one in assets/audio/.
##
## It also remembers what was heard lately, so "that sound was bad" (N, or
## the pause menu's Audio page) can offer the sounds that just played.

const SAVE_PATH := "user://audio.json"
## [key, label, bus]. Effects are the sounds of things in town; ambience is
## the background (birds, katydids, leaves, fields, wind, far-off traffic).
const CHANNELS := [["master", "Master", "Master"], ["music", "Music", "Music"],
	["ambience", "Ambience", "Ambience"], ["effects", "Effects", "World"], ["ui", "Interface", "UI"]]
## Every sound in the game: [id (file under assets/audio/, no extension),
## what it is, which channel, loops].
const CATALOG := [
	["ui/click", "Button click", "ui", false],
	["ui/tool", "Picking a tool", "ui", false],
	["ui/road", "Road built", "ui", false],
	["ui/build", "Building placed (and new buildings going up)", "ui", false],
	["ui/bulldoze", "Bulldoze", "ui", false],
	["ui/money", "Money", "ui", false],
	["ui/milestone", "Milestone", "ui", false],
	["ui/doorbell", "Neighbor doorbell (chat)", "ui", false],
	["world/car_engine", "Car engines", "effects", true],
	["world/rooftop_hvac", "Shop rooftop air conditioners", "effects", true],
	["world/industry_hum", "Factory hum", "effects", true],
	["world/transformer", "Substation and utility hum", "effects", true],
	["world/rail/diesel", "Train engine", "effects", true],
	["world/rail/horn", "Train horn", "effects", true],
	["world/rail/crossing_bell", "Railroad crossing bell", "effects", true],
	["world/birds_day", "Birds by homes (day)", "ambience", true],
	["world/crickets_night", "Katydids by homes (night)", "ambience", true],
	["world/leaves", "Leaves in yards", "ambience", true],
	["world/corn_field", "Farm fields", "ambience", true],
	["world/wind_high", "Wind (zoomed out)", "ambience", true],
	["world/traffic_far", "Far-off traffic (zoomed out)", "ambience", true],
]
## How far back "just heard" looks, in seconds.
const RECENT := 20.0
## Quieter than this (linear, after distance) does not count as heard.
const AUDIBLE := 0.03

static var volume := {"master": 1.0, "music": 1.0, "ambience": 1.0, "effects": 1.0, "ui": 1.0}
static var muted := false
static var flagged := {}
## Sound id -> the option picked for it in the Sound picker ({file, name, source}).
static var picks := {}
## Goes up on every pick, so players holding a stream fetch it again.
static var picks_version := 0
static var _picked_streams := {}
static var _heard := {}   # id -> {"t": seconds, "peak": loudness}
static var _loaded := false
## Where the settings are kept (tests point this somewhere else).
static var save_path := SAVE_PATH


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	for k in volume:
		if d.get("volume", {}).has(k):
			volume[k] = clampf(float(d.volume[k]), 0.0, 1.0)
	muted = bool(d.get("muted", false))
	for id in d.get("flagged", []):
		flagged[str(id)] = true
	var p = d.get("picks", {})
	if typeof(p) == TYPE_DICTIONARY:
		picks = p


static func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"volume": volume, "muted": muted, "flagged": flagged.keys(), "picks": picks}, "\t"))


## Sets the buses from the settings (CityAudio.setup_buses makes them).
static func apply() -> void:
	ensure_loaded()
	for c in CHANNELS:
		var i := AudioServer.get_bus_index(c[2])
		if i == -1:
			continue
		var v: float = volume[c[0]]
		var db := linear_to_db(maxf(v, 0.0001))
		var off := false
		# The mix (SoundMix) moves the master and the music; every other
		# sound is moved where it plays (level).
		if c[0] == "master":
			db += SoundMix.master_db()
		elif c[0] == "music":
			db += SoundMix.sample_db("music/theme")
			off = SoundMix.is_silenced("music/theme")
		AudioServer.set_bus_volume_db(i, db)
		AudioServer.set_bus_mute(i, off or v <= 0.0 or (c[0] == "master" and muted))
	SoundMix.apply_limiter()


static func set_volume(channel: String, v: float) -> void:
	volume[channel] = clampf(v, 0.0, 1.0)
	apply()
	save()


## Volumes back to 100%, unmuted. Flags stay.
static func reset() -> void:
	for k in volume:
		volume[k] = 1.0
	muted = false
	apply()
	save()


## Why nothing can be heard, in plain words, or "" when sound should play.
static func why_silent() -> String:
	ensure_loaded()
	if muted:
		return "All sounds are muted."
	if volume.master <= 0.0:
		return "Master volume is at 0%."
	if AudioServer.get_bus_index("Master") != -1 and AudioServer.is_bus_mute(0):
		return "The game's sound is switched off."
	if AudioServer.get_output_device() == "" or AudioServer.get_mix_rate() <= 0.0:
		return "No speaker or headphones found."
	return ""


## The audio setup, for the play notes when sound goes missing.
static func state() -> Dictionary:
	var buses := {}
	for i in AudioServer.bus_count:
		buses[AudioServer.get_bus_name(i)] = [snappedf(AudioServer.get_bus_volume_db(i), 0.1), AudioServer.is_bus_mute(i)]
	return {"volume": volume.duplicate(), "muted": muted, "flagged": flagged.keys(), "buses": buses,
		"device": AudioServer.get_output_device(), "mix_rate": AudioServer.get_mix_rate(),
		"latency": snappedf(AudioServer.get_output_latency(), 0.001)}


static func set_muted(on: bool) -> void:
	muted = on
	apply()
	save()


static func info(id: String) -> Array:
	for c in CATALOG:
		if c[0] == id:
			return c
	return [id, id, "effects", false]


static func is_flagged(id: String) -> bool:
	ensure_loaded()
	return flagged.has(id)


## Flags a sound as bad (or takes the flag back). It goes quiet at once and
## the flag is sent with the play notes. `how`: "list" or "just_heard".
static func flag(id: String, on: bool, how := "list") -> void:
	ensure_loaded()
	if on:
		flagged[id] = true
	else:
		flagged.erase(id)
	save()
	var heard_ago := -1.0
	if _heard.has(id):
		heard_ago = snappedf(_now() - float(_heard[id].t), 0.1)
	var tel = _telemetry()
	if tel:
		tel.event("audio", state())
		tel.event("sound_flag", {"sound": id, "label": info(id)[1], "on": on, "how": how, "heard_ago": heard_ago,
			"volume": volume.duplicate(), "muted": muted})


## The recording to play for a sound: the one picked in the Sound picker
## if there is one, else the game's own. Loops are set to loop.
static func stream(id: String) -> AudioStream:
	ensure_loaded()
	var s: AudioStream = null
	if picks.has(id):
		var path := picked_path(str(picks[id].get("file", "")))
		if _picked_streams.has(path):
			return _picked_streams[path]
		if FileAccess.file_exists(path):
			s = AudioStreamOggVorbis.load_from_file(path)
			_picked_streams[path] = s
	if s == null:
		s = load("res://assets/audio/%s.ogg" % id)
	if s is AudioStreamOggVorbis:
		# A sound set to rest between repeats plays once, then is started again.
		(s as AudioStreamOggVorbis).loop = bool(info(id)[3]) and SoundMix.gap(id) <= 0.0
	return s


## Where a downloaded option is kept on this computer.
static func picked_path(file: String) -> String:
	return "user://sfx/" + file


## Makes `option` ({file, name, source}, already downloaded) the sound for
## `id`, or the game's own again for {}. Takes effect at once.
static func pick(id: String, option: Dictionary) -> void:
	ensure_loaded()
	if option.is_empty():
		picks.erase(id)
	else:
		picks[id] = {"file": option.file, "name": option.get("name", ""), "source": option.get("source", "")}
	picks_version += 1
	save()
	var tel = _telemetry()
	if tel:
		tel.event("sound_pick", {"sound": id, "label": info(id)[1], "file": option.get("file", ""),
			"name": option.get("name", ""), "source": option.get("source", ""), "picks": picks.duplicate(true)})


## The level to play a sound at: silent once flagged. Remembers that it was
## heard, at `gain` (0 to 1, after distance) times its volume.
static func level(id: String, db: float, gain := 1.0) -> float:
	if is_flagged(id):
		return -80.0
	# The mix: this kind of sound's own volume, mute and solo.
	var mixed := SoundMix.gain_db(id)
	if mixed <= SoundMix.SILENT:
		SoundMix.report(id, 0.0)
		return -80.0
	db += mixed
	var loud := db_to_linear(db) * gain
	SoundMix.report(id, loud)
	if loud >= AUDIBLE:
		heard(id, loud)
	return db


## level() for a sound placed in the world, heard from `ear`.
static func level3d(id: String, p: AudioStreamPlayer3D, db: float, ear: Vector3) -> float:
	var d := p.global_position.distance_to(ear) if p.is_inside_tree() else p.position.distance_to(ear)
	var gain := clampf(p.unit_size / maxf(d, 0.001), 0.0, 1.0)
	# A hearing distance changed in the mix fades out smoothly at its edge.
	if not is_equal_approx(SoundMix.range_scale(id), 1.0) and p.max_distance > 0.0:
		var fade := clampf((p.max_distance - d) / (p.max_distance * 0.3), 0.0, 1.0)
		db += linear_to_db(maxf(fade, 0.0001))
	return level(id, db, gain)


static func heard(id: String, loud := 1.0) -> void:
	var now := _now()
	var h: Dictionary = _heard.get(id, {})
	if h.is_empty() or now - float(h.t) > RECENT:
		h = {"peak": 0.0}
	h.t = now
	h.peak = maxf(float(h.peak), loud)
	_heard[id] = h


## What was heard in the last RECENT seconds: one-off sounds first (newest
## first), then loops, loudest first. [{id, label, ago, loud}].
static func recent() -> Array:
	var now := _now()
	var out := []
	for id in _heard:
		var h: Dictionary = _heard[id]
		if now - float(h.t) <= RECENT:
			out.append({"id": id, "label": info(id)[1], "ago": now - float(h.t), "loud": float(h.peak), "loop": info(id)[3]})
	out.sort_custom(func(a, b):
		if a.loop != b.loop:
			return not a.loop
		return a.ago < b.ago if not a.loop else a.loud > b.loud)
	return out


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The Telemetry autoload, found at run time (class scripts can't name it).
static func _telemetry() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Telemetry") if tree else null
