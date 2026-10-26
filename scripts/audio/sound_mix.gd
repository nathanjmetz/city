class_name SoundMix
extends RefCounted
## The mix: one volume and a few tuning knobs for each KIND of sound, so one
## sound that is out of balance can be turned down without touching the rest.
## (Before this, all effects shared a single "Effects" slider.)
##
## Where the numbers come from, lowest to highest:
##   1. the game's own numbers (the code that plays each sound),
##   2. data/audio_mix.json, the mix shipped to every player (browser too),
##   3. on the desktop app only, this computer's tweaks from the admin
##      Sound mixer, kept in user://audio_mix.json as differences from (2).
## An empty mix means "exactly as before". Every knob is a plain number and
## lands on a real property: a volume offset in dB, AudioStreamPlayer3D
## max_distance, the number of players a sound may use, pitch_scale, and the
## master bus (compressor + limiter).
##
## Per-kind volume is an offset applied where each sound sets its level
## (SoundSettings.level). Buses added while the game runs never reach the
## speakers in the browser build, so there are no per-kind buses.

const SHIPPED_PATH := "res://data/audio_mix.json"
const LOCAL_PATH := "user://audio_mix.json"
## Where a sound's volume can be moved to, in dB (shown to the person as a percent).
const DB_LIMIT := 12.0
const SILENT := -80.0
## Meters hold the last loudness this long (s) so one-off sounds show up too.
const METER_HOLD := 0.8
## "Too loud?" keeps each sound's peak this long (s).
const PEAK_HOLD := 4.0
const UNDO_LIMIT := 60
## Quieter than this (linear) does not count as a voice playing.
const VOICE_FLOOR := 0.004

## Categories: [key, plain name]. A category slider moves all its sounds.
const CATEGORIES := [
	["traffic", "Traffic and trains"],
	["town", "Buildings and utilities"],
	["nature", "Nature and ambience"],
	["interface", "Buttons and interface"],
	["music", "Music"],
]
## Every kind of sound: id (same ids as SoundSettings.CATALOG), plain name,
## category, one-line help. `range`: metres it can be heard by default (0 =
## not placed in the world). `cap`: most that play at once by default (0 = no
## cap to tune), `max`: most it can ever use. `pitch`: default pitch variety
## (-1 = not offered). `gap`: ambient loop that can rest between repeats.
const KINDS := [
	{"id": "world/car_engine", "name": "Car engines", "cat": "traffic", "range": 260.0, "cap": 8, "max": 8, "pitch": 0.0,
		"help": "The hum of each car near the camera. Rises and falls with speed."},
	{"id": "world/rail/diesel", "name": "Train engine", "cat": "traffic", "range": 700.0, "cap": 3, "max": 3, "pitch": 0.0,
		"help": "The rumble of the lead engine of each train."},
	{"id": "world/rail/horn", "name": "Train horn", "cat": "traffic", "range": 2400.0, "cap": 2, "max": 2, "pitch": 0.0,
		"help": "The long and short blasts before a crossing. It carries a long way on purpose."},
	{"id": "world/rail/crossing_bell", "name": "Railroad crossing bell", "cat": "traffic", "range": 350.0, "cap": 3, "max": 3, "pitch": 0.0,
		"help": "The ding-ding while the gates are down."},
	{"id": "world/rooftop_hvac", "name": "Shop air conditioners", "cat": "town", "range": 420.0, "cap": 3, "max": 12, "pitch": 0.0, "gap": true,
		"help": "A soft fan hum from shop roofs."},
	{"id": "world/industry_hum", "name": "Factory hum", "cat": "town", "range": 420.0, "cap": 3, "max": 12, "pitch": 0.0, "gap": true,
		"help": "The low drone of factories."},
	{"id": "world/transformer", "name": "Substation and utility hum", "cat": "town", "range": 420.0, "cap": 2, "max": 12, "pitch": 0.0, "gap": true,
		"help": "The buzz of power and water buildings."},
	{"id": "world/birds_day", "name": "Birds (day)", "cat": "nature", "range": 420.0, "cap": 4, "max": 12, "pitch": 0.0, "gap": true,
		"help": "Birdsong around homes, from dawn to dusk."},
	{"id": "world/crickets_night", "name": "Katydids (night)", "cat": "nature", "range": 420.0, "cap": 4, "max": 12, "pitch": 0.0, "gap": true,
		"help": "Night insects around homes."},
	{"id": "world/leaves", "name": "Leaves in yards", "cat": "nature", "range": 420.0, "cap": 2, "max": 12, "pitch": 0.0, "gap": true,
		"help": "Rustling trees by houses."},
	{"id": "world/corn_field", "name": "Farm fields", "cat": "nature", "range": 420.0, "cap": 3, "max": 12, "pitch": 0.0, "gap": true,
		"help": "Wind through crops."},
	{"id": "world/wind_high", "name": "Wind (zoomed out)", "cat": "nature", "range": 0.0, "cap": 0, "max": 0, "pitch": -1.0,
		"help": "Grows louder the higher the camera climbs."},
	{"id": "world/traffic_far", "name": "Far-off traffic (zoomed out)", "cat": "nature", "range": 0.0, "cap": 0, "max": 0, "pitch": -1.0,
		"help": "A distant roll of traffic when looking down on busy roads."},
	{"id": "ui/click", "name": "Button clicks", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.03,
		"help": "Every button press, and zone painting."},
	{"id": "ui/tool", "name": "Picking a tool", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.0,
		"help": "The tap when you choose a tool."},
	{"id": "ui/road", "name": "Road built", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.03,
		"help": "The sound of laying a road."},
	{"id": "ui/build", "name": "Building placed", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.0,
		"help": "Placing a building, and new buildings going up."},
	{"id": "ui/bulldoze", "name": "Bulldoze", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.03,
		"help": "Taking something down."},
	{"id": "ui/money", "name": "Money", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.0,
		"help": "The coin sound after a milestone."},
	{"id": "ui/milestone", "name": "Milestone", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.0,
		"help": "The chime when the town reaches a new size."},
	{"id": "ui/doorbell", "name": "Neighbor doorbell", "cat": "interface", "range": 0.0, "cap": 0, "max": 0, "pitch": 0.0,
		"help": "Rings when a neighbor does something."},
	{"id": "music/theme", "name": "Background music", "cat": "music", "range": 0.0, "cap": 0, "max": 0, "pitch": -1.0,
		"help": "Brawn's songs: the theme in menus, the playlist in town."},
]
## The bus each category's sounds play on (for "Play a sample").
const SAMPLE_BUS := {"traffic": "World", "town": "World", "nature": "Ambience", "interface": "UI", "music": "Music"}
## Parts of a sound's setting: the knobs a person can move.
const FIELDS := ["db", "mute", "range", "cap", "pitch", "gap"]

## Bumps on every change, so players re-read their numbers.
static var version := 0
## Switch off in tests so they never read or write this computer's files.
static var persist := true
static var use_local := true
static var shipped_path := SHIPPED_PATH
static var local_path := LOCAL_PATH
## Tests point this at a scratch folder so "Save for everyone" never touches the project.
static var folder_override := ""

static var _loaded := false
static var _shipped := {}
static var _mix := {}
static var _baseline := {}
static var _hear_baseline := false
static var _solo := {}
static var _undo: Array = []
static var _last_tag := ""
static var _last_t := 0.0
static var _live := {}
static var _kinds := {}


# --- Loading and saving ---------------------------------------------------------

static func blank() -> Dictionary:
	return {"master_db": 0.0, "limiter": 0.0, "groups": {}, "sounds": {}}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for k in KINDS:
		_kinds[k.id] = k
	_shipped = _read(shipped_path)
	_mix = _clean(_shipped.duplicate(true))
	# Tweaks made on this computer apply on the desktop app only.
	if use_local and persist and not OS.has_feature("web"):
		var local := _read(local_path)
		if not local.is_empty():
			_mix = _merge(_mix, local)
	_baseline = _mix.duplicate(true)


## Forget everything and read the files again.
static func reread() -> void:
	_loaded = false
	_undo.clear()
	_solo.clear()
	_hear_baseline = false
	_live.clear()
	version += 1
	ensure_loaded()


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## A mix with only sane numbers in it, whatever was in the file.
static func _clean(d: Dictionary) -> Dictionary:
	var out := blank()
	out.master_db = clampf(float(d.get("master_db", 0.0)), -DB_LIMIT, DB_LIMIT)
	out.limiter = clampf(float(d.get("limiter", 0.0)), 0.0, 1.0)
	var g = d.get("groups", {})
	if typeof(g) == TYPE_DICTIONARY:
		for c in CATEGORIES:
			if g.has(c[0]):
				out.groups[c[0]] = clampf(float(g[c[0]]), -DB_LIMIT, DB_LIMIT)
	var s = d.get("sounds", {})
	if typeof(s) == TYPE_DICTIONARY:
		for id in s:
			var k: Dictionary = _kinds.get(str(id), {})
			if k.is_empty() or typeof(s[id]) != TYPE_DICTIONARY:
				continue
			var e := {}
			var v: Dictionary = s[id]
			if v.has("db"):
				e.db = clampf(float(v.db), -DB_LIMIT, DB_LIMIT)
			if v.has("mute"):
				e.mute = bool(v.mute)
			if v.has("range"):
				e.range = clampf(float(v.range), 0.25, 2.0)
			if v.has("cap"):
				e.cap = clampi(int(v.cap), 0, maxi(int(k.max), 0))
			if v.has("pitch"):
				e.pitch = clampf(float(v.pitch), 0.0, 0.2)
			if v.has("gap"):
				e.gap = clampf(float(v.gap), 0.0, 90.0)
			if not e.is_empty():
				out.sounds[str(id)] = e
	return out


## `over` laid on top of `base`, field by field.
static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var o := _clean(over.duplicate(true))
	var out := base.duplicate(true)
	for k in ["master_db", "limiter"]:
		if over.has(k):
			out[k] = o[k]
	for c in o.groups:
		out.groups[c] = o.groups[c]
	for id in o.sounds:
		var e: Dictionary = out.sounds.get(id, {})
		for f in o.sounds[id]:
			e[f] = o.sounds[id][f]
		out.sounds[id] = e
	return out


## The mix as a sparse dictionary: only what differs from `base`.
static func diff(mix: Dictionary, base: Dictionary) -> Dictionary:
	var out := {}
	for k in ["master_db", "limiter"]:
		if not is_equal_approx(float(mix.get(k, 0.0)), float(base.get(k, 0.0))):
			out[k] = snappedf(float(mix.get(k, 0.0)), 0.01)
	var groups := {}
	for c in CATEGORIES:
		var a := float(mix.get("groups", {}).get(c[0], 0.0))
		if not is_equal_approx(a, float(base.get("groups", {}).get(c[0], 0.0))):
			groups[c[0]] = snappedf(a, 0.01)
	if not groups.is_empty():
		out.groups = groups
	var sounds := {}
	var ids := {}
	for id in mix.get("sounds", {}):
		ids[id] = true
	for id in base.get("sounds", {}):
		ids[id] = true
	for id in ids:
		var e := {}
		for f in FIELDS:
			var mv = mix.get("sounds", {}).get(id, {}).get(f, default_of(id, f))
			var bv = base.get("sounds", {}).get(id, {}).get(f, default_of(id, f))
			if not _same(mv, bv):
				e[f] = snappedf(mv, 0.001) if typeof(mv) == TYPE_FLOAT else mv
		if not e.is_empty():
			sounds[id] = e
	if not sounds.is_empty():
		out.sounds = sounds
	return out


static func _same(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


static func default_of(id: String, field: String):
	var k: Dictionary = kind(id)
	match field:
		"db":
			return 0.0
		"mute":
			return false
		"range":
			return 1.0
		"cap":
			return int(k.get("cap", 0))
		"pitch":
			return maxf(float(k.get("pitch", 0.0)), 0.0)
		"gap":
			return 0.0
	return null


## Saves this computer's tweaks (desktop app only): the differences from the shipped mix.
static func save_local() -> void:
	if not persist or OS.has_feature("web"):
		return
	var f := FileAccess.open(local_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(diff(_mix, _clean(_shipped)), "\t"))


## Where the project folder is on this computer ("" if there isn't one).
static func project_folder() -> String:
	if folder_override != "":
		return folder_override if FileAccess.file_exists(folder_override.path_join("project.godot")) else ""
	var here := ProjectSettings.globalize_path("res://")
	var cands := [here, OS.get_environment("HOME").path_join("dev/city")]
	for c in cands:
		if FileAccess.file_exists(str(c).path_join("project.godot")):
			return str(c)
	return ""


## "Save for everyone": writes the whole mix to data/audio_mix.json in the
## project folder, to be committed. Returns {ok, message}.
static func save_for_everyone() -> Dictionary:
	if OS.has_feature("web"):
		return {"ok": false, "message": "Only the desktop app can save for everyone."}
	var dir := project_folder()
	if dir == "":
		return {"ok": false, "message": "The project folder isn't on this computer (looked in ~/dev/city), so this can't be saved for everyone. Your changes are still saved here."}
	DirAccess.make_dir_recursive_absolute(dir.path_join("data"))
	var path := dir.path_join("data/audio_mix.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "message": "Couldn't write %s." % path}
	var body := diff(_mix, blank())
	body["version"] = 1
	f.store_string(JSON.stringify(body, "\t") + "\n")
	f.close()
	return {"ok": true, "message": "Saved to %s. Commit that file to ship this mix to everyone." % path, "path": path}


# --- Reading the mix ------------------------------------------------------------

static func kind(id: String) -> Dictionary:
	ensure_loaded()
	return _kinds.get(id, {})


static func _eff() -> Dictionary:
	ensure_loaded()
	return _baseline if _hear_baseline else _mix


static func value_of(id: String, field: String):
	var e: Dictionary = _eff().sounds.get(id, {})
	return e[field] if e.has(field) else default_of(id, field)


static func master_db() -> float:
	return float(_eff().master_db)


static func limiter() -> float:
	return float(_eff().limiter)


static func group_db(cat: String) -> float:
	return float(_eff().groups.get(cat, 0.0))


static func db_of(id: String) -> float:
	return float(value_of(id, "db"))


static func is_muted(id: String) -> bool:
	return bool(value_of(id, "mute"))


## Heard only if nothing is soloed, or this one is.
static func is_silenced(id: String) -> bool:
	if is_muted(id):
		return true
	return not _solo.is_empty() and not _solo.has(id)


## Volume offset to add to a sound's level (dB): its own plus its category's.
## -80 when it should be silent (muted, or something else is soloed).
static func gain_db(id: String) -> float:
	ensure_loaded()
	if is_silenced(id):
		return SILENT
	return db_of(id) + group_db(str(kind(id).get("cat", "")))


## The same without mute and solo: what "Play a sample" uses.
static func sample_db(id: String) -> float:
	ensure_loaded()
	return db_of(id) + group_db(str(kind(id).get("cat", "")))


## Hearing distance as a multiple of the normal one (1 = as now).
static func range_scale(id: String) -> float:
	return float(value_of(id, "range"))


## How many of this sound may play at once, out of `available` players.
static func cap(id: String, available: int) -> int:
	if int(kind(id).get("max", 0)) <= 0:
		return available
	return mini(int(value_of(id, "cap")), available)


## Pitch variety: each play is sped up or slowed down by up to this fraction.
static func pitch_variety(id: String) -> float:
	return float(value_of(id, "pitch"))


## A random pitch for one play of this sound.
static func pitch_for(id: String) -> float:
	var v := pitch_variety(id)
	return 1.0 + randf_range(-v, v) if v > 0.0 else 1.0


## Seconds a looping ambient sound rests between repeats (0 = plays straight through).
static func gap(id: String) -> float:
	return float(value_of(id, "gap"))


# --- Changing the mix -----------------------------------------------------------

static func _checkpoint(tag: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if tag == _last_tag and now - _last_t < 1.2:
		_last_t = now
		return
	_last_tag = tag
	_last_t = now
	_undo.append(_mix.duplicate(true))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


static func _changed() -> void:
	version += 1
	_hear_baseline = false
	save_local()
	SoundSettings.apply()


static func set_sound(id: String, field: String, v) -> void:
	ensure_loaded()
	_checkpoint(id + field)
	var e: Dictionary = _mix.sounds.get(id, {})
	e[field] = v
	_mix.sounds[id] = e
	_mix = _clean(_mix)
	_changed()


static func set_group(cat: String, db: float) -> void:
	ensure_loaded()
	_checkpoint("group" + cat)
	if absf(db) < 0.01:
		_mix.groups.erase(cat)
	else:
		_mix.groups[cat] = clampf(db, -DB_LIMIT, DB_LIMIT)
	_changed()


static func set_master_db(db: float) -> void:
	ensure_loaded()
	_checkpoint("master")
	_mix.master_db = clampf(db, -DB_LIMIT, DB_LIMIT)
	_changed()


static func set_limiter(v: float) -> void:
	ensure_loaded()
	_checkpoint("limiter")
	_mix.limiter = clampf(v, 0.0, 1.0)
	_changed()


## One row back to the game's own numbers (the shipped mix for it, if there is one).
static func reset_sound(id: String) -> void:
	ensure_loaded()
	_checkpoint("reset" + id)
	var base := _clean(_shipped)
	if base.sounds.has(id):
		_mix.sounds[id] = base.sounds[id].duplicate()
	else:
		_mix.sounds.erase(id)
	_solo.erase(id)
	_changed()


## Everything back to the shipped mix.
static func reset_all() -> void:
	ensure_loaded()
	_checkpoint("resetall" + str(Time.get_ticks_msec()))
	_mix = _clean(_shipped)
	_solo.clear()
	_changed()


static func can_undo() -> bool:
	return not _undo.is_empty()


static func undo() -> void:
	if _undo.is_empty():
		return
	_mix = _undo.pop_back()
	_last_tag = ""
	_changed()


# --- Solo and "before and after" --------------------------------------------------

static func is_solo(id: String) -> bool:
	return _solo.has(id)


static func has_solo() -> bool:
	return not _solo.is_empty()


static func set_solo(id: String, on: bool) -> void:
	if on:
		_solo[id] = true
	else:
		_solo.erase(id)
	version += 1
	SoundSettings.apply()


static func clear_solo() -> void:
	_solo.clear()
	version += 1
	SoundSettings.apply()


## true: hear the mix as it was when the game started ("before").
static func set_hear_before(on: bool) -> void:
	ensure_loaded()
	_hear_baseline = on
	version += 1
	SoundSettings.apply()


static func hearing_before() -> bool:
	return _hear_baseline


static func mix_snapshot() -> Dictionary:
	ensure_loaded()
	return _mix.duplicate(true)


# --- Live meters ----------------------------------------------------------------

## A sound reports how loud it is right now (linear, 1 = full scale, after
## distance). Called every frame by each voice of a looping sound.
static func report(id: String, loud: float) -> void:
	var f := Engine.get_process_frames()
	var now := Time.get_ticks_msec() / 1000.0
	var m: Dictionary = _live.get(id, {})
	if m.is_empty():
		m = {"frame": -1, "level": 0.0, "voices": 0, "t": now, "peak": 0.0, "peak_t": now}
		_live[id] = m
	if int(m.frame) != f:
		m.frame = f
		m.level = 0.0
		m.voices = 0
	m.t = now
	m.level = maxf(float(m.level), loud)
	if loud >= VOICE_FLOOR:
		m.voices = int(m.voices) + 1
	if loud >= float(m.peak) or now - float(m.peak_t) > PEAK_HOLD:
		m.peak = loud
		m.peak_t = now


## {level, voices, peak} for the meter: zero once the sound has gone quiet.
static func meter(id: String) -> Dictionary:
	var m: Dictionary = _live.get(id, {})
	if m.is_empty():
		return {"level": 0.0, "voices": 0, "peak": 0.0}
	var now := Time.get_ticks_msec() / 1000.0
	var age := now - float(m.t)
	var peak := float(m.peak) if now - float(m.peak_t) <= PEAK_HOLD else 0.0
	if age > METER_HOLD:
		return {"level": 0.0, "voices": 0, "peak": peak}
	return {"level": float(m.level) * (1.0 - age / METER_HOLD), "voices": m.voices if age < 0.25 else 0, "peak": peak}


## The sounds ranked by how loud they have been lately, loudest first.
static func loudest() -> Array:
	ensure_loaded()
	var out := []
	for k in KINDS:
		var m := meter(k.id)
		if float(m.peak) >= VOICE_FLOOR:
			out.append({"id": k.id, "name": k.name, "peak": m.peak, "level": m.level, "voices": m.voices})
	out.sort_custom(func(a, b): return a.peak > b.peak)
	return out


## Meter position, 0 to 1, for a loudness (linear): -48 dB to 0 dB.
static func meter_fill(loud: float) -> float:
	return clampf((linear_to_db(maxf(loud, 0.00001)) + 48.0) / 48.0, 0.0, 1.0)


## A volume offset in dB as a friendly percent: "as now" at 0.
static func percent_text(db: float) -> String:
	var pct := roundi((db_to_linear(db) - 1.0) * 100.0)
	if pct == 0:
		return "As now"
	return "%s%d%%" % ["+" if pct > 0 else "-", absi(pct)]


# --- Applying to the buses ---------------------------------------------------------

## The master compressor ("keep everything balanced"): added on first use,
## to a bus that already exists (so it is safe in the browser build).
static func apply_limiter() -> void:
	var s := limiter()
	var comp: AudioEffectCompressor = null
	var idx := -1
	for i in AudioServer.get_bus_effect_count(0):
		var e := AudioServer.get_bus_effect(0, i)
		if e is AudioEffectCompressor:
			comp = e
			idx = i
	if comp == null:
		if s <= 0.0:
			return
		comp = AudioEffectCompressor.new()
		comp.resource_name = "KeepBalanced"
		AudioServer.add_bus_effect(0, comp, 0)
		idx = 0
	comp.threshold = lerpf(0.0, -24.0, s)
	comp.ratio = lerpf(1.0, 4.0, s)
	comp.attack_us = 20000.0
	comp.release_ms = 250.0
	comp.gain = lerpf(0.0, 4.0, s)  # make up for what the squeeze takes
	AudioServer.set_bus_effect_enabled(0, idx, s > 0.0)
