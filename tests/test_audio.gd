extends SceneTree
## Run: godot --headless -s tests/test_audio.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-200, 201, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 3000:
		sim.tick()
	var day := SoundSources.gather(sim, 12)
	var night := SoundSources.gather(sim, 23)
	_check(day.any(func(s): return s.sound == "birds_day"), "homes have birds by day")
	_check(night.any(func(s): return s.sound == "crickets_night") and not night.any(func(s): return s.sound == "birds_day"),
		"crickets, not birds, at night")
	_check(day.any(func(s): return s.sound == "industry_hum"), "factories hum")

	# Only what is near the listener plays, nearest first, within the caps.
	var ear := Vector3(150, 20, -30)
	var picked := SoundSources.pick(day, ear, 12, 420.0)
	_check(picked.size() <= 12, "no more than the slots (%d)" % picked.size())
	var counts := {}
	for s in picked:
		counts[s.sound] = counts.get(s.sound, 0) + 1
	var within := true
	for k in counts:
		within = within and counts[k] <= SoundSources.CAPS[k]
	_check(within, "each sound stays under its cap %s" % str(counts))
	var first: Dictionary = picked[0]
	for s in day:
		if s.sound == first.sound:
			_check(ear.distance_to(s.pos) >= ear.distance_to(first.pos) - 0.01, "nearest source comes first")
			break
	_check(SoundSources.pick(day, Vector3(5000, 20, 5000), 12, 420.0).is_empty(), "nothing plays far from town")

	# Farm fields make sound where they are.
	sim.apply({"type": "paint_farmland", "points": [[400, 400], [700, 400], [700, 700], [400, 700]]})
	var fields := SoundSources.gather(sim, 12).filter(func(s): return s.sound == "corn_field")
	_check(fields.is_empty(), "painted land without a farm is quiet")

	# Every sound file the game asks for exists.
	for f in SoundSources.GAIN.keys() + SoundSources.BEDS:
		_check(ResourceLoader.exists("res://assets/audio/world/%s.ogg" % f), "world sound %s exists" % f)
	for f in UiSounds.VOLUME.keys():
		if f != "brush":
			_check(ResourceLoader.exists("res://assets/audio/ui/%s.ogg" % f), "ui sound %s exists" % f)

	# Commands tell listeners what happened.
	var heard := []
	sim.command_applied.connect(func(c): heard.append(c.type))
	sim.apply({"type": "build_road", "start": [-200, 100], "ctrl": [0, 100], "end": [200, 100]})
	_check(heard == ["build_road"], "a built road is announced (%s)" % str(heard))

	# Audio settings: every sound is in the list and its file exists.
	var ids := SoundSettings.CATALOG.map(func(c): return c[0])
	for f in SoundSources.GAIN.keys() + SoundSources.BEDS:
		_check(("world/" + f) in ids, "world/%s is in the Audio list" % f)
	for f in UiSounds.VOLUME.keys():
		_check(("ui/" + UiSounds._file(f)) in ids, "ui sound %s is in the Audio list" % f)
	for f in ["diesel", "horn", "crossing_bell"]:
		_check(("world/rail/" + f) in ids, "rail %s is in the Audio list" % f)
	for c in SoundSettings.CATALOG:
		_check(ResourceLoader.exists("res://assets/audio/%s.ogg" % c[0]), "listed sound %s exists" % c[0])
		_check(SoundSettings.CHANNELS.any(func(ch): return ch[0] == c[2]), "%s is on a real channel" % c[0])

	# A flagged sound goes silent at once and stays flagged.
	SoundSettings.ensure_loaded()
	SoundSettings.flagged.clear()
	_check(SoundSettings.level("world/leaves", -6.0) == -6.0, "an unflagged sound plays at its level")
	SoundSettings.flag("world/leaves", true)
	_check(SoundSettings.level("world/leaves", -6.0) <= -80.0, "a flagged sound is silent")
	SoundSettings._loaded = false
	SoundSettings.flagged.clear()
	SoundSettings.ensure_loaded()
	_check(SoundSettings.is_flagged("world/leaves"), "the flag is remembered")
	SoundSettings.flag("world/leaves", false)
	_check(not SoundSettings.is_flagged("world/leaves"), "a flag can be taken back")

	# "Just heard": one-off sounds first, quiet ones left out.
	SoundSettings._heard.clear()
	SoundSettings.level("world/birds_day", 0.0)
	SoundSettings.heard("ui/road", 0.5)
	SoundSettings.level("world/industry_hum", -60.0)
	var recent := SoundSettings.recent().map(func(h): return h.id)
	_check(recent == ["ui/road", "world/birds_day"], "just heard lists what was audible (%s)" % str(recent))

	# Volumes go on the buses.
	CityAudio.setup_buses()
	SoundSettings.set_volume("ambience", 0.5)
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")) - linear_to_db(0.5)) < 0.01,
		"the ambience slider sets its bus")
	SoundSettings.set_muted(true)
	_check(AudioServer.is_bus_mute(0), "mute silences everything")
	SoundSettings.set_muted(false)
	SoundSettings.set_volume("ambience", 1.0)

	# Flags reach the fix list, and taking one back clears it.
	var batch := {"from": "Brawn", "events": [
		{"k": "sound_flag", "t": 1.0, "sound": "world/car_engine", "label": "Car engines", "on": true, "how": "just_heard"},
		{"k": "sound_flag", "t": 2.0, "sound": "ui/click", "label": "Button click", "on": true, "how": "list"},
		{"k": "sound_flag", "t": 3.0, "sound": "ui/click", "label": "Button click", "on": false, "how": "list"}]}
	var titles: Array = Insights.analyze([batch]).fixes.filter(func(f): return f.kind == "sound").map(func(f): return f.title)
	_check(titles.size() == 1 and "car_engine" in titles[0], "flagged sounds become fixes (%s)" % str(titles))
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
