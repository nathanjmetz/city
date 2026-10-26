extends SceneTree
## Run: godot --headless -s tests/test_sound_mix.gd
## The admin Sound mixer's mix: the shipped data/audio_mix.json loads and
## applies, per-sound volume, mute, solo, hearing distance, pitch and the
## voice cap all take hold, and the panel opens.

const SHIP := "user://test_mix_ship.json"
const LOCAL := "user://test_mix_local.json"
const FOLDER := "user://test_mix_project"

var _failed := false


func _init() -> void:
	# Never touch this computer's real settings, mix or project.
	# (A class sets its static variables the first time it is used, so use both first.)
	SoundMix.blank()
	SoundSettings.info("ui/click")
	SoundSettings.save_path = "user://test_audio_mix_settings.json"
	SoundMix.persist = false
	SoundMix.use_local = false

	# The shipped file is real, parses, and means "exactly as before".
	_check(FileAccess.file_exists(SoundMix.SHIPPED_PATH), "data/audio_mix.json exists")
	_check(typeof(JSON.parse_string(FileAccess.get_file_as_string(SoundMix.SHIPPED_PATH))) == TYPE_DICTIONARY, "the shipped mix parses")
	SoundMix.reread()
	_check(SoundMix.gain_db("world/birds_day") == 0.0 and SoundMix.master_db() == 0.0, "the shipped mix changes nothing by default")
	_check(SoundSettings.level("world/leaves", -6.0) == -6.0, "a sound plays at its own level with no mix")
	_check(SoundMix.range_scale("world/leaves") == 1.0 and SoundMix.pitch_for("world/leaves") == 1.0 and SoundMix.gap("world/leaves") == 0.0, "no range, pitch or rest change by default")

	# Every kind is a real sound, and the numbers match the code's own.
	var ids := SoundSettings.CATALOG.map(func(c): return c[0])
	for c in ids:
		_check(not SoundMix.kind(c).is_empty(), "%s has a row in the mixer" % c)
	for k in SoundMix.KINDS:
		_check(k.id == "music/theme" or k.id in ids, "mixer row %s is a game sound" % k.id)
		_check(SoundMix.CATEGORIES.any(func(c): return c[0] == k.cat), "%s is in a real group" % k.id)
		if k.id.begins_with("world/") and SoundSources.CAPS.has(k.id.get_file()):
			_check(int(k.cap) == SoundSources.CAPS[k.id.get_file()], "%s default cap matches the game's" % k.id)
	_check(SoundMix.kind("world/car_engine").cap == CityAudio.CAR_SLOTS, "car default cap matches the game's")

	# A mix file applies, and bad numbers are tamed.
	_write(SHIP, {"version": 1, "master_db": 3.0, "limiter": 0.5, "groups": {"nature": -6.0},
		"sounds": {"world/birds_day": {"db": -4.0, "cap": 1, "range": 0.5, "pitch": 0.1, "gap": 20},
			"world/car_engine": {"mute": true}, "ui/click": {"db": 99.0}, "nope/nothing": {"db": 5.0}}})
	SoundMix.shipped_path = SHIP
	SoundMix.reread()
	_check(is_equal_approx(SoundMix.master_db(), 3.0), "the mix sets the master")
	_check(is_equal_approx(SoundMix.gain_db("world/birds_day"), -10.0), "a sound's volume adds to its group's (%s)" % SoundMix.gain_db("world/birds_day"))
	_check(SoundSettings.level("world/birds_day", -2.0) == -12.0, "level() carries the mix")
	_check(SoundMix.gain_db("world/car_engine") <= SoundMix.SILENT and SoundSettings.level("world/car_engine", 0.0) <= -80.0, "a muted sound is silent")
	_check(is_equal_approx(SoundMix.db_of("ui/click"), SoundMix.DB_LIMIT), "an out-of-range volume is held to the limit")
	_check(SoundMix.kind("nope/nothing").is_empty() and SoundMix.db_of("nope/nothing") == 0.0, "unknown sounds in the file are ignored")
	_check(SoundMix.range_scale("world/birds_day") == 0.5, "hearing distance comes from the mix")
	var pitches := []
	for i in 40:
		pitches.append(SoundMix.pitch_for("world/birds_day"))
	_check(pitches.all(func(p): return p >= 0.9 and p <= 1.1) and pitches.min() < pitches.max(), "pitch variety varies within its range")
	_check(SoundMix.gap("world/birds_day") == 20.0, "the repeat gap comes from the mix")
	_check(not (SoundSettings.stream("world/birds_day") as AudioStreamOggVorbis).loop, "a resting sound plays once, then is started again")
	_check((SoundSettings.stream("world/crickets_night") as AudioStreamOggVorbis).loop, "other loops still loop")
	# Master, music and the "keep balanced" squeeze reach the buses.
	SoundSettings.apply()
	_check(absf(AudioServer.get_bus_volume_db(0) - (linear_to_db(SoundSettings.volume.master) + 3.0)) < 0.01, "the master offset sets the Master bus")
	var comp: AudioEffectCompressor = null
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectCompressor:
			comp = AudioServer.get_bus_effect(0, i)
			_check(AudioServer.is_bus_effect_enabled(0, i), "keep-balanced is on")
	_check(comp != null and comp.threshold < 0.0 and comp.ratio > 1.0, "keep-balanced squeezes the master")

	# The voice cap holds: a street of homes never plays more than the cap.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-200, 201, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	var day := SoundSources.gather(sim, 12)
	var ear := Vector3(0, 20, -30)
	SoundMix.shipped_path = SoundMix.SHIPPED_PATH
	SoundMix.reread()
	var plain := _count(SoundSources.pick(day, ear, 12, 420.0), "birds_day")
	_check(plain == SoundSources.CAPS.birds_day, "birds use their normal cap (%d)" % plain)
	SoundMix.set_sound("world/birds_day", "cap", 1)
	_check(_count(SoundSources.pick(day, ear, 12, 420.0), "birds_day") == 1, "a voice cap of 1 holds")
	SoundMix.set_sound("world/birds_day", "cap", 0)
	_check(_count(SoundSources.pick(day, ear, 12, 420.0), "birds_day") == 0, "a voice cap of 0 plays none")
	SoundMix.set_sound("world/birds_day", "cap", 9)
	var nine := _count(SoundSources.pick(day, ear, 12, 420.0), "birds_day")
	_check(nine > plain and nine <= 9, "a higher cap lets more play, never past it (%d)" % nine)
	_check(SoundMix.cap("world/car_engine", 8) == 8 and SoundMix.cap("world/car_engine", 3) == 3, "the car cap never goes over the players built")
	SoundMix.set_sound("world/car_engine", "cap", 2)
	_check(SoundMix.cap("world/car_engine", 8) == 2, "cars can be capped")
	# Muting or soloing something else frees its slots.
	SoundMix.set_sound("world/birds_day", "mute", true)
	_check(_count(SoundSources.pick(day, ear, 12, 420.0), "birds_day") == 0, "a muted sound takes no slot")
	SoundMix.set_sound("world/birds_day", "mute", false)
	SoundMix.set_solo("world/leaves", true)
	_check(SoundMix.gain_db("world/birds_day") <= SoundMix.SILENT and SoundMix.gain_db("world/leaves") > SoundMix.SILENT, "solo hears only that sound")
	_check(SoundSources.pick(day, ear, 12, 420.0).all(func(s): return s.sound == "leaves"), "solo leaves the slots to that sound")
	SoundMix.clear_solo()
	# A shorter hearing distance leaves out far ones.
	var far := Vector3(0, 20, -330)
	var all_far := SoundSources.pick(day, far, 12, 420.0).size()
	SoundMix.set_sound("world/birds_day", "range", 0.25)
	SoundMix.set_sound("world/leaves", "range", 0.25)
	_check(SoundSources.pick(day, far, 12, 420.0).size() < all_far, "a shorter hearing distance drops far sounds")

	# Undo, A/B, reset and saving.
	SoundMix.reread()
	SoundMix.set_sound("ui/click", "db", -6.0)
	SoundMix.set_sound("ui/money", "db", 3.0)
	_check(SoundMix.can_undo(), "there is something to undo")
	SoundMix.undo()
	_check(SoundMix.db_of("ui/money") == 0.0 and SoundMix.db_of("ui/click") == -6.0, "undo takes back only the last change")
	_check(is_equal_approx(SoundMix.gain_db("ui/click"), -6.0), "the changed sound carries its volume")
	SoundMix.set_hear_before(true)
	_check(SoundMix.gain_db("ui/click") == 0.0, "before: the mix as the game started")
	SoundMix.set_hear_before(false)
	_check(SoundMix.gain_db("ui/click") == -6.0, "after: your changes")
	SoundMix.reset_sound("ui/click")
	_check(SoundMix.gain_db("ui/click") == 0.0, "reset this row")
	SoundMix.set_group("music", -3.0)
	SoundMix.set_master_db(2.0)
	SoundMix.reset_all()
	_check(SoundMix.master_db() == 0.0 and SoundMix.group_db("music") == 0.0, "reset all")
	_check(SoundMix.percent_text(0.0) == "As now" and SoundMix.percent_text(6.0).begins_with("+") and SoundMix.percent_text(-6.0).begins_with("-"), "volumes read as friendly percents")
	_check(SoundMix.diff(SoundMix.mix_snapshot(), SoundMix.blank()).is_empty(), "an untouched mix is an empty file")
	SoundMix.set_sound("world/leaves", "db", -3.0)
	SoundMix.set_sound("world/leaves", "cap", 2)  # the game's own number: not a difference
	var d := SoundMix.diff(SoundMix.mix_snapshot(), SoundMix.blank())
	_check(d.sounds.keys() == ["world/leaves"] and d.sounds["world/leaves"].keys() == ["db"], "only real differences are written (%s)" % str(d))

	# Local tweaks (desktop) sit on top of the shipped mix as differences.
	_write(SHIP, {"sounds": {"world/leaves": {"db": -6.0}, "ui/tool": {"db": 2.0}}})
	SoundMix.shipped_path = SHIP
	SoundMix.local_path = LOCAL
	SoundMix.persist = true
	SoundMix.use_local = true
	_write(LOCAL, {"sounds": {"world/leaves": {"db": -1.0}}})
	SoundMix.reread()
	if not OS.has_feature("web"):
		_check(is_equal_approx(SoundMix.db_of("world/leaves"), -1.0), "this computer's tweak wins over the shipped mix")
		_check(is_equal_approx(SoundMix.db_of("ui/tool"), 2.0), "the shipped mix still applies under it")
		SoundMix.set_sound("ui/tool", "db", 0.0)
		var saved = JSON.parse_string(FileAccess.get_file_as_string(LOCAL))
		_check(saved.sounds["ui/tool"].db == 0.0, "going back to the game's number is still saved over a shipped one")
	SoundMix.use_local = false
	SoundMix.reread()
	_check(is_equal_approx(SoundMix.db_of("world/leaves"), -6.0), "without the desktop admin, only the shipped mix applies")
	SoundMix.persist = false

	# Save for everyone: into the project folder, only when it exists.
	DirAccess.make_dir_recursive_absolute(FOLDER)
	SoundMix.folder_override = ProjectSettings.globalize_path(FOLDER) + "/nowhere"
	_check(not SoundMix.save_for_everyone().ok, "no project folder: it says so and writes nothing")
	var f := FileAccess.open(FOLDER + "/project.godot", FileAccess.WRITE)
	f.close()
	SoundMix.folder_override = ProjectSettings.globalize_path(FOLDER)
	SoundMix.shipped_path = SoundMix.SHIPPED_PATH
	SoundMix.reread()
	SoundMix.set_sound("ui/click", "db", -3.0)
	var r := SoundMix.save_for_everyone()
	_check(r.ok and FileAccess.file_exists(FOLDER + "/data/audio_mix.json"), "saves data/audio_mix.json in the project folder")
	var out = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "/data/audio_mix.json"))
	_check(typeof(out) == TYPE_DICTIONARY and is_equal_approx(float(out.sounds["ui/click"].db), -3.0), "the saved file holds the mix")
	SoundMix.shipped_path = FOLDER + "/data/audio_mix.json"
	SoundMix.reread()
	_check(is_equal_approx(SoundMix.db_of("ui/click"), -3.0), "the saved file loads back as the shipped mix")
	SoundMix.folder_override = ""

	# Live meters and the "too loud" ranking.
	SoundMix.shipped_path = SoundMix.SHIPPED_PATH
	SoundMix.reread()
	SoundMix.report("world/industry_hum", 0.2)
	SoundMix.report("world/birds_day", 0.6)
	SoundMix.report("world/birds_day", 0.1)
	var loud := SoundMix.loudest()
	_check(loud.size() >= 2 and loud[0].id == "world/birds_day", "the loudest sound is ranked first")
	_check(SoundMix.meter("world/birds_day").voices == 2, "the meter counts voices")

	# The hotkey, and the panel itself.
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_F12
	ev.shift_pressed = true
	ev.meta_pressed = true
	_check(SoundMixer.is_hotkey(ev), "Cmd+Shift+F12 opens the mixer")
	ev.meta_pressed = false
	_check(not SoundMixer.is_hotkey(ev), "Shift+F12 alone does not")
	ev.ctrl_pressed = true
	_check(SoundMixer.is_hotkey(ev), "Ctrl+Shift+F12 opens the mixer")
	var panel := SoundMixer.new()
	root.add_child(panel)
	await process_frame
	panel.open()
	await process_frame
	await process_frame
	_check(panel.is_open() and panel._rows.size() == SoundMix.KINDS.size(), "the panel opens with a row for every sound")
	panel._rows["ui/click"].slider.value = -4.5
	_check(is_equal_approx(SoundMix.db_of("ui/click"), -4.5), "moving a row's slider changes that sound only")
	panel._rows["ui/click"].mute.button_pressed = true
	_check(SoundMix.is_muted("ui/click") and not SoundMix.is_muted("ui/road"), "a row's mute silences that sound only")
	panel._play_sample("world/leaves")
	panel.close()
	_check(not panel.is_open(), "the panel closes")

	for p in [SHIP, LOCAL, FOLDER + "/data/audio_mix.json", FOLDER + "/project.godot", "user://test_audio_mix_settings.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER + "/data"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _count(picked: Array, sound: String) -> int:
	return picked.filter(func(s): return s.sound == sound).size()


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
