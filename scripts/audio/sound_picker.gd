class_name SoundPicker
extends VBoxContainer
## The Sound picker (Audio page): every game sound on its own row, the name
## on the left, then the recording the game plays now and the free
## recordings that could replace it. Each has a play button and a checkmark;
## checking one makes it the sound in the game at once (SoundSettings.pick).
##
## The options are not in the game itself: they sit next to the browser
## build on the preview site (web/sfx/, listed in candidates.json) and each is
## fetched the first time it's played, then kept in user://sfx/.

const HOST := "https://nathanjmetz.github.io/city/sfx/"
const LIST := "candidates.json"
## A looping sound plays this long when previewed.
const PREVIEW := 6.0

## Sets the line under the page title.
var say: Callable = func(_s: String): pass

var _list := {}       # sound id -> [{file, name, source}]
var _rows := VBoxContainer.new()
var _preview := AudioStreamPlayer.new()
var _preview_gen := 0
var _http := HTTPRequest.new()
var _queue := []      # [file, callback(ok)]
var _busy := false
var _checks := {}     # sound id -> {option index (-1 = the game's own): CheckBox}
var _playing: Button
var _play_icon: Texture2D


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_preview.bus = "Master"
	add_child(_preview)
	_preview.finished.connect(_stopped)
	# No timeout in the browser: there it can fire after the answer arrived.
	_http.timeout = 0.0 if OS.has_feature("web") else 20.0
	add_child(_http)
	_http.request_completed.connect(_done)
	_play_icon = _triangle()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(800, 420)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	add_child(scroll)
	_rows.add_child(ShellStyle.text("Finding the options...", 14, 500, Brand.INK_MUTED))
	_fetch(LIST, func(ok: bool):
		var f := FileAccess.open(SoundSettings.picked_path(LIST), FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if typeof(d) == TYPE_DICTIONARY:
			_list = d.get("sounds", {})
		_build(ok or not _list.is_empty()), true)


static func base_url() -> String:
	var own := OS.get_environment("NEIGHBORS_SFX_URL")  # a local copy, for testing
	if own != "":
		return own
	if OS.has_feature("web"):
		var here = JavaScriptBridge.eval("new URL('sfx/', location.href).href", true)
		if typeof(here) == TYPE_STRING and here.begins_with("http"):
			return here
	return HOST


func _build(found: bool) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_checks.clear()
	if not found:
		_rows.add_child(ShellStyle.text("Couldn't reach the options. Check the internet and open this page again.", 14, 600, Brand.BRAND_CORAL))
		return
	var waiting := []
	for ch in SoundSettings.CHANNELS.slice(2):
		var group := SoundSettings.CATALOG.filter(func(c): return c[2] == ch[0] and not _list.get(c[0], []).is_empty())
		waiting += SoundSettings.CATALOG.filter(func(c): return c[2] == ch[0] and _list.get(c[0], []).is_empty())
		if group.is_empty():
			continue
		_rows.add_child(ShellStyle.text(ch[1].to_upper(), 12, 600, Brand.INK_MUTED))
		for c in group:
			_rows.add_child(_row(c[0]))
	if not waiting.is_empty():
		var later := ShellStyle.text("The town's own sounds (cars, trains, birds and the rest) get options next.",
			13, 500, Brand.INK_MUTED)
		later.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(later)


## One sound: its name, then "Now" (the game's own) and each option.
func _row(id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name := ShellStyle.text(SoundSettings.info(id)[1], 14, 600)
	name.custom_minimum_size = Vector2(190, 0)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var picked: String = str(SoundSettings.picks.get(id, {}).get("file", ""))
	var options: Array = _list.get(id, [])
	_checks[id] = {}
	row.add_child(_option(id, -1, "Now", "The sound the game has now", picked == ""))
	for i in options.size():
		var o: Dictionary = options[i]
		row.add_child(_option(id, i, str(i + 1), "%s\n%s" % [o.get("name", ""), o.get("source", "")], picked == o.file))
	return row


## A play button with a checkmark beside it.
func _option(id: String, i: int, label: String, tip: String, on: bool) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = tip
	var play := Button.new()
	play.text = label
	play.icon = _play_icon
	play.tooltip_text = tip
	play.focus_mode = Control.FOCUS_NONE
	play.toggle_mode = true
	play.custom_minimum_size = Vector2(54 if i >= 0 else 66, 32)
	play.add_theme_font_size_override("font_size", 13)
	play.pressed.connect(func(): _play(id, i, play))
	box.add_child(play)
	var check := CheckBox.new()
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_NONE
	check.tooltip_text = "Use this one in the game"
	check.toggled.connect(func(v: bool): _check(id, i, v))
	box.add_child(check)
	_checks[id][i] = check
	return box


func _option_data(id: String, i: int) -> Dictionary:
	return {} if i < 0 else _list[id][i]


func _play(id: String, i: int, button: Button) -> void:
	_stop()
	_playing = button
	button.set_pressed_no_signal(true)
	var o := _option_data(id, i)
	if o.is_empty():
		_start(id, load("res://assets/audio/%s.ogg" % id), "Now: the game's own %s." % SoundSettings.info(id)[1].to_lower())
		return
	say.call("Loading %s..." % o.name)
	_fetch(o.file, func(ok: bool):
		if _playing != button:
			return
		if not ok:
			say.call("Couldn't load %s." % o.name)
			_stop()
			return
		_start(id, AudioStreamOggVorbis.load_from_file(SoundSettings.picked_path(o.file)),
			"%d: %s  ·  %s" % [i + 1, o.name, o.source]))


func _start(id: String, stream: AudioStream, line: String) -> void:
	if stream == null:
		_stop()
		return
	var loops: bool = SoundSettings.info(id)[3]
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loops
	_preview.stream = stream
	_preview.play()
	var silent := SoundSettings.why_silent()
	say.call(silent if silent != "" else line)
	_preview_gen += 1
	var gen := _preview_gen
	if loops:
		get_tree().create_timer(PREVIEW).timeout.connect(func():
			if gen == _preview_gen:
				_stop())


func _stop() -> void:
	_preview_gen += 1
	_preview.stop()
	_stopped()


func _stopped() -> void:
	if is_instance_valid(_playing):
		_playing.set_pressed_no_signal(false)
	_playing = null


## A checkmark: one per sound. Unchecking the one in use goes back to Now.
func _check(id: String, i: int, on: bool) -> void:
	if not on:
		if i >= 0:
			_set_checks(id, -1)
			SoundSettings.pick(id, {})
			say.call("%s is back to the game's own." % SoundSettings.info(id)[1])
		else:
			_checks[id][-1].set_pressed_no_signal(true)
		return
	_set_checks(id, i)
	var o := _option_data(id, i)
	if o.is_empty():
		SoundSettings.pick(id, {})
		say.call("%s is back to the game's own." % SoundSettings.info(id)[1])
		return
	_fetch(o.file, func(ok: bool):
		if not ok:
			_set_checks(id, -1)
			say.call("Couldn't load %s." % o.name)
			return
		SoundSettings.pick(id, o)
		say.call("%s is now %s. You'll hear it in the game." % [SoundSettings.info(id)[1], o.name]))


func _set_checks(id: String, i: int) -> void:
	for k in _checks[id]:
		_checks[id][k].set_pressed_no_signal(k == i)


# --- Fetching ---------------------------------------------------------------------

## Gets `file` into user://sfx/ (or finds it there), then calls back with
## whether it's there. `fresh` fetches again even if it's kept already.
func _fetch(file: String, callback: Callable, fresh := false) -> void:
	if not fresh and FileAccess.file_exists(SoundSettings.picked_path(file)):
		callback.call(true)
		return
	_queue.append([file, callback])
	_next()


func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	if _http.request(base_url() + _queue[0][0]) != OK:
		_done(HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray())


func _done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# The browser can report a finished request a second time (as a timeout).
	if not _busy or _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	_busy = false
	var path := SoundSettings.picked_path(job[0])
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0
	if ok:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		ok = f != null
		if f:
			f.store_buffer(body)
			f.close()
	job[1].call(ok or FileAccess.file_exists(path))
	_next()


static func _triangle() -> Texture2D:
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			# A right-pointing triangle, soft at the slanted edges.
			var d := minf(float(y) - 0.5 * x + 0.5, 11.5 - y - 0.5 * x) + 0.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(d, 0.0, 1.0) if x >= 1 else 0.0))
	return ImageTexture.create_from_image(img)
