class_name SoundSettings
extends RefCounted
## The player's audio settings, kept in user://audio.json: a volume for each
## channel (like CS2's Audio tab), mute, and the sounds they flagged as bad.
## A flagged sound goes silent at once wherever it plays, and the flag goes
## to the region server with the play notes so the sound gets replaced.
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
static var _heard := {}   # id -> {"t": seconds, "peak": loudness}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
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


static func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"volume": volume, "muted": muted, "flagged": flagged.keys()}, "\t"))


## Sets the buses from the settings (CityAudio.setup_buses makes them).
static func apply() -> void:
	ensure_loaded()
	for c in CHANNELS:
		var i := AudioServer.get_bus_index(c[2])
		if i == -1:
			continue
		var v: float = volume[c[0]]
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.0 or (c[0] == "master" and muted))


static func set_volume(channel: String, v: float) -> void:
	volume[channel] = clampf(v, 0.0, 1.0)
	apply()
	save()


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
		tel.event("sound_flag", {"sound": id, "label": info(id)[1], "on": on, "how": how, "heard_ago": heard_ago,
			"volume": volume.duplicate(), "muted": muted})


## The level to play a sound at: silent once flagged. Remembers that it was
## heard, at `gain` (0 to 1, after distance) times its volume.
static func level(id: String, db: float, gain := 1.0) -> float:
	if is_flagged(id):
		return -80.0
	var loud := db_to_linear(db) * gain
	if loud >= AUDIBLE:
		heard(id, loud)
	return db


## level() for a sound placed in the world, heard from `ear`.
static func level3d(id: String, p: AudioStreamPlayer3D, db: float, ear: Vector3) -> float:
	var d := p.global_position.distance_to(ear) if p.is_inside_tree() else p.position.distance_to(ear)
	return level(id, db, clampf(p.unit_size / maxf(d, 0.001), 0.0, 1.0))


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
