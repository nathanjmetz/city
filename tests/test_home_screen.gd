extends SceneTree
## The home screen opens at once: its menu is up and answering on the first
## frame, with a picture of the town (MenuStill) where the live town will
## be, and the town is then built a piece a frame behind it and faded in
## (the critic, 2026-10-26: blank and sluggish for 10-16 s while the whole
## town was built in _ready). Also the picture for each season and hour, and
## the views' shared frame budget (LoadGate.share_ms).
## Run: godot --headless -s tests/test_home_screen.gd

## Most milliseconds the menu may take to open, once its scripts are
## loaded (it took seconds when it built the whole town first; headless on
## a slow CI machine, well under).
const OPEN_MS := 300.0
## Most seconds for the town to be drawn and faded in, headless.
const DRAWN_S := 90.0

var _failed := false


func _initialize() -> void:
	_pictures()
	_share()
	await _menu()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _pictures() -> void:
	var at := func(when: String) -> String:
		return MenuStill.look_for(MarionTime.at(MenuLife.parse(when)))
	_check(at.call("2026-07-10T13:00") == "summer", "a July afternoon is the summer picture")
	_check(at.call("2026-05-20T10:00") == "summer", "late May is green too")
	_check(at.call("2026-10-20T13:00") == "autumn", "late October is the autumn picture (got %s)" % at.call("2026-10-20T13:00"))
	_check(at.call("2026-11-28T13:00") == "bare", "late November is bare trees (got %s)" % at.call("2026-11-28T13:00"))
	_check(at.call("2026-01-20T13:00") == "snow", "January is snow (got %s)" % at.call("2026-01-20T13:00"))
	_check(at.call("2026-07-10T23:30") == "night", "a summer night is the night picture")
	_check(at.call("2026-12-21T17:45") == "night", "after dark in December is the night picture")
	_check(at.call("2026-07-10T21:00") == "summer", "a July evening before dusk is still day (sunset about 9:15)")
	for look in MenuStill.LOOKS:
		var p := MenuStill.path(look)
		var tex = load(p) if ResourceLoader.exists(p) else null
		_check(tex is Texture2D, "the %s picture is there" % look)
		if tex is Texture2D:
			var aspect: float = float(tex.get_width()) / tex.get_height()
			_check(absf(aspect - MenuStill.ASPECT) < 0.02, "the %s picture is %.1f:1 (got %.2f)" % [look, MenuStill.ASPECT, aspect])
			_check(tex.get_width() <= 1400, "the %s picture is small (%d px wide)" % [look, tex.get_width()])


func _share() -> void:
	LoadGate.loading = false
	_check(LoadGate.ms(4.0, 20.0) == 4.0, "out of loading, a view gets its normal budget")
	LoadGate.loading = true
	_check(LoadGate.ms(4.0, 20.0) == 20.0, "behind the loading screen, its wide one")
	LoadGate.share_ms = 10.0
	LoadGate.frame_begins()
	var got := LoadGate.ms(4.0, 20.0)
	_check(got <= 10.0 and got > 9.0, "sharing, a view gets what's left of the frame's share (got %.1f)" % got)
	OS.delay_msec(12)
	_check(LoadGate.ms(4.0, 20.0) == LoadGate.SHARE_FLOOR_MS, "a used-up share leaves the floor")
	LoadGate.loading = false
	LoadGate.share_ms = 0.0


func _menu() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/menu.tscn")
	var t := Time.get_ticks_usec()
	var menu: Node = scene.instantiate()
	root.add_child(menu)
	current_scene = menu
	var open_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("menu open in %.0f ms" % open_ms)
	_check(open_ms < OPEN_MS, "the menu opens in under %d ms (%.0f)" % [OPEN_MS, open_ms])
	var play := _find_play(menu)
	_check(play != null and play.is_visible_in_tree(), "Play is up at once")
	var reveal := _reveal(menu)
	_check(reveal != null, "the town is covered while it's built")
	_check(reveal != null and reveal._picture.texture != null, "by a picture of it, not a blank")
	_check(LoadGate.loading and LoadGate.share_ms > 0.0, "the views share a frame budget meanwhile")
	_check(not _has(menu, BuildingView), "the town isn't built in the first frame")
	var start := Time.get_ticks_msec()
	var worst_step := 0.0
	# On a slow machine the picture gives up first (BackdropReveal.CAP_S) and
	# the town carries on being built behind the menu: wait for both.
	while (_reveal(menu) != null or not menu._steps.is_empty()) and Time.get_ticks_msec() - start < DRAWN_S * 1000.0:
		var f := Time.get_ticks_usec()
		await process_frame
		worst_step = maxf(worst_step, (Time.get_ticks_usec() - f) / 1000.0)
	print("drawn and faded in after %.1f s; worst frame %.0f ms" % [(Time.get_ticks_msec() - start) / 1000.0, worst_step])
	_check(_reveal(menu) == null, "the picture fades into the live town")
	_check(menu._steps.is_empty(), "every piece got built")
	_check(_has(menu, BuildingView) and _has(menu, RoadView) and _has(menu, TerrainView) and _has(menu, WildView),
		"the town's views are there")
	_check(_has(menu, TrafficView) and _has(menu, WalkerView) and menu._people_in, "and its cars and people")
	_check(TrafficView.premade.is_empty(), "the cars' ready-made models are let go")
	_check(not LoadGate.loading and LoadGate.share_ms == 0.0, "the views get their own budgets back")
	_check(DayNight.cycle_on, "the menu runs day and night")
	menu.queue_free()
	await process_frame
	await process_frame


func _find_play(n: Node) -> Button:
	if n is Button and n.has_meta("title") and (n.get_meta("title") as Label).text == "Play":
		return n
	for c in n.get_children():
		var b := _find_play(c)
		if b:
			return b
	return null


func _reveal(menu: Node) -> BackdropReveal:
	for c in menu.get_children():
		if c is BackdropReveal and not c.is_queued_for_deletion():
			return c
	return null


func _has(menu: Node, type) -> bool:
	for c in menu.get_children():
		if is_instance_of(c, type):
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
