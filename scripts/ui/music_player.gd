class_name MusicPlayer
extends PanelContainer
## The music player in the top bar: a note and the song playing; a click
## drops down the player, like a car radio. Skip goes on to the next song,
## and every song is listed to play straight away. Skips are sent with the
## play notes (GameMusic.skip), so songs players skip get looked at.

var _button: Button
var _song := Label.new()
var _time := Label.new()
var _list := VBoxContainer.new()
var _wait := 0.0
var _shown := ""


func _init() -> void:
	add_theme_stylebox_override("panel", UiStyle.dock(true))
	visible = false
	custom_minimum_size = Vector2(280, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(UiStyle.label("NOW PLAYING", 10, UiStyle.MUTED, 600))
	_song.add_theme_font_override("font", Brand.ui(700))
	_song.add_theme_font_size_override("font_size", 16)
	col.add_child(_song)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_time.add_theme_font_size_override("font_size", 13)
	_time.add_theme_color_override("font_color", UiStyle.MUTED)
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_time)
	var skip := Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "On to the next song"
	skip.pressed.connect(func():
		_music().skip()
		_refresh())
	row.add_child(skip)
	col.add_child(row)
	col.add_child(HSeparator.new())
	col.add_child(UiStyle.label("SONGS", 10, UiStyle.MUTED, 600))
	_list.add_theme_constant_override("separation", 0)
	col.add_child(_list)
	col.add_child(UiStyle.label("Music by metzguy", 11, UiStyle.MUTED))


func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Music: what's playing, skip a song or pick one"
	_button.custom_minimum_size = Vector2(34, 24)
	var middle := CenterContainer.new()
	middle.set_anchors_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(Icon.new("music", 16))
	_button.add_child(middle)
	_button.toggled.connect(func(on): open(on))
	return _button


func open(on: bool) -> void:
	visible = on
	if on:
		move_to_front()  # over the advisor's card
	if _button:
		_button.set_pressed_no_signal(on)
	if on:
		_shown = ""
		_refresh()


func close_panel() -> void:
	open(false)


func _music() -> GameMusic:
	return GameMusic.get_music(get_tree())


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.5
	_refresh()


func _refresh() -> void:
	var m := _music()
	var song := m.song() if m.is_inside_tree() and m.mode == GameMusic.Mode.TOWN else ""
	var title := GameMusic.title(song) if song != "" else "No song yet"
	if _button:
		# The song's name shows when you point at the note (the bar has no room for it).
		_button.tooltip_text = "Music: %s. Click to skip or pick a song." % (title if m.rest_left <= 0.0 else "a quiet spell")
	if not visible:
		return
	_song.text = title
	if m.rest_left > 0.0:
		_time.text = "A quiet spell. Next song in %s" % _clock(m.rest_left)
	elif song != "" and m.player.stream:
		_time.text = "%s / %s" % [_clock(m.player.get_playback_position()), _clock(m.player.stream.get_length())]
	else:
		_time.text = ""
	if song == _shown and _list.get_child_count() > 0:
		return
	_shown = song
	for c in _list.get_children():
		c.queue_free()
	for path in GameMusic.playlist():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		var on: bool = path == song and m.rest_left <= 0.0
		b.text = GameMusic.title(path) + ("  ·  playing" if on else "")
		b.add_theme_color_override("font_color", Brand.CORAL_TEXT if on else Brand.INK)
		if on:
			b.add_theme_font_override("font", Brand.ui(700))
		b.tooltip_text = "Play %s now" % GameMusic.title(path)
		b.pressed.connect(func():
			_music().choose(path)
			_refresh())
		_list.add_child(b)


static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
