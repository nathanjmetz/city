class_name GameMenu
extends CanvasLayer
## The pause menu, like Cities: Skylines 2: a modal in the middle of the
## screen. Escape puts tools down and closes panels first (the HUD does that);
## once nothing is left, Escape opens this. Resume, save, back to the title
## screen, credits, or quit. In a shared region it shows the invite and lets you leave
## (the region keeps going). Graphics and Audio have their own pages; N
## opens Audio at "Just heard" to flag a bad sound.

var game: Node  # main.gd

var _shade := ColorRect.new()
var _col := VBoxContainer.new()
var _title := ShellStyle.title("", 28)
var _note := ShellStyle.text("", 14, 500, Brand.INK_MUTED)
var _was_speed := 1
## What was heard just before the menu opened (SoundSettings.recent), so the
## menu's own clicks don't crowd it.
var _just_heard := []
var _preview := AudioStreamPlayer.new()
var _preview_stop: SceneTreeTimer


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ShellStyle.theme()
	add_child(root)
	_shade.color = Color(Brand.SURFACE, 0.6)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	root.add_child(_shade)
	# A modal card in the middle of the screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.add_child(center)
	var panel := PanelContainer.new()
	var box := ShellStyle.panel()
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 28
	box.content_margin_bottom = 28
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 24
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	_col.add_theme_constant_override("separation", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_col)
	if Session.client:
		Session.client.disconnected.connect(_lost_connection)
	add_child(_preview)


func _exit_tree() -> void:
	MenuState.showing = false  # leaving for the title screen with the menu up


## N: "that sound was bad". Opens the Audio page with what just played.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_N or k.ctrl_pressed or k.meta_pressed:
		return
	if not _shade.visible:
		open()
	_audio()
	get_viewport().set_input_as_handled()


## While the menu is up it owns the keyboard: Escape (or the pad's B) goes
## back a page, then resumes, even with a tool in hand; N still flags a sound;
## every other key stays out of the town (Space can't unpause it, 1 can't
## pick up a road, WASD can't move the camera).
func _input(event: InputEvent) -> void:
	if not _shade.visible or not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_N:
		return
	get_viewport().set_input_as_handled()
	if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		var back := _back_button()
		if back != null:
			back.pressed.emit()
		elif _title.text != "Connection lost":
			close()


## The Back button of the Graphics or Audio page, if one is showing.
func _back_button() -> Button:
	for c in _col.get_children():
		if c is Button and c.text == "Back" and not c.is_queued_for_deletion():
			return c
	return null


func toggle() -> void:
	if _shade.visible:
		close()
	else:
		open()


func open() -> void:
	_just_heard = SoundSettings.recent()
	_fill()
	_shade.visible = true
	MenuState.showing = true
	_was_speed = game.speed
	game.set_speed(0)


func close() -> void:
	_preview.stop()
	_shade.visible = false
	MenuState.showing = false
	game.set_speed(_was_speed)


func _fill() -> void:
	# The title and note stay; only the buttons are rebuilt.
	for c in _col.get_children():
		if c != _title and c != _note:
			c.queue_free()
	if not _title.get_parent():
		_col.add_child(_title)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(_note)
	_note.text = ""
	var resume := _button("Resume", close)
	ShellStyle.primary(resume)
	_col.add_child(resume)
	if Session.mode == Session.Mode.ONLINE:
		var c := Session.client
		_title.text = c.region.cities[c.my_city].name
		_note.text = "Shared region  ·  invite code %s\nYour town waits for you while you're away." % c.invite_code
		_col.add_child(_button("Copy invite", func():
			DisplayServer.clipboard_set(Session.invite_link(c.url, c.invite_code) if c.url.begins_with("wss://") \
				else "Invite code %s, server %s" % [c.invite_code, c.url])
			_note.text = "Invite copied. Paste it to family and friends."))
		_col.add_child(_button("Leave region", Session.to_menu))
	else:
		_title.text = Session.current_name
		_col.add_child(_button("Save", func():
			Session.save_city(game.sim)
			_note.text = "Saved."))
		_col.add_child(_button("Main menu", func():
			Session.save_city(game.sim)
			Session.to_menu()))
	var q := GraphicsQuality.current
	if q and q.active:
		_col.add_child(_button("Graphics: " + q.label(), _graphics))
	_col.add_child(_button("Audio" + ("  ·  muted" if SoundSettings.muted else ""), _audio))
	_col.add_child(_button("Credits", func(): _note.text = SoundCredits.text()))
	if not OS.has_feature("web"):
		_col.add_child(_button("Quit to desktop", func():
			if Session.mode == Session.Mode.SOLO:
				Session.save_city(game.sim)
			get_tree().quit()))


## The Graphics page, in place of the buttons: Auto (the default) or a
## fixed tier, and for a fixed tier how sharp to draw. Like CS2's graphics
## presets, but only tiers this computer can carry are offered (see
## GraphicsQuality.top), and nothing changes until you pick one.
func _graphics() -> void:
	var q := GraphicsQuality.current
	for c in _col.get_children():
		if c != _title and c != _note:
			c.queue_free()
	_title.text = "Graphics"
	_note.text = "Auto picks what this computer draws smoothly and adjusts while you play."
	var desc := ["fastest, shorter detail", "balanced", "soft shading, tree shadows",
		"adds reflections and bounced light", "lifelike light and haze"]
	var options := [GraphicsQuality.AUTO]
	for t in q.top() + 1:
		options.append(t)
	for m in options:
		var text: String = "%s  ·  %s" % [GraphicsQuality.NAMES[m], desc[m]] if m != GraphicsQuality.AUTO \
			else "Auto  ·  now %s" % GraphicsQuality.NAMES[q.tier] if q.mode == GraphicsQuality.AUTO \
			else "Auto  ·  recommended"
		var b := _button(text, func():
			q.choose(m)
			_graphics())
		if m == q.mode:
			ShellStyle.primary(b)
		_col.add_child(b)
	if q.top() < GraphicsQuality.CINEMATIC and not q.browser:
		_col.add_child(ShellStyle.text("Higher settings are too much for this computer.", 14, 500, Brand.INK_MUTED))
	if q.mode != GraphicsQuality.AUTO:
		_col.add_child(ShellStyle.text("Sharpness", 15, 600))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for s in ([1.0, 0.85, 0.7, 0.5] if q.browser else [1.0, 0.85, 0.7]):
			var b := _button("%d%%" % roundi(s * 100.0), func():
				q.set_scale(s)
				_graphics())
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if absf(q.scale - s) < 0.01:
				ShellStyle.primary(b)
			row.add_child(b)
		_col.add_child(row)
	_col.add_child(_button("Back", _fill))


## The Audio page: a volume for each channel and mute (like CS2's Audio
## tab), then every sound with Play and Flag. A flagged sound goes quiet
## right away and the flag is sent to us so it gets replaced. "Just heard"
## lists what played in the seconds before the menu opened.
func _audio() -> void:
	for c in _col.get_children():
		if c != _title and c != _note:
			c.queue_free()
	_title.text = "Audio"
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.event("audio", SoundSettings.state())
	_note.text = "Hear a bad sound? Flag it. It goes quiet right away, and we replace it."
	for ch in SoundSettings.CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := ShellStyle.text(ch[1], 15, 600)
		name.custom_minimum_size = Vector2(96, 0)
		row.add_child(name)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = roundf(SoundSettings.volume[ch[0]] * 100.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		# Scrolling the page must never turn a volume down by itself.
		slider.scrollable = false
		var pct := ShellStyle.text("%d%%" % slider.value, 14, 500, Brand.INK_MUTED)
		pct.custom_minimum_size = Vector2(44, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.value_changed.connect(func(v: float):
			pct.text = "%d%%" % v
			SoundSettings.set_volume(ch[0], v / 100.0))
		row.add_child(slider)
		row.add_child(pct)
		_col.add_child(row)
	_col.add_child(ShellStyle.text("Music is for your own songs; none are in the game yet.", 13, 500, Brand.INK_MUTED))
	var silent := SoundSettings.why_silent()
	if silent != "":
		_col.add_child(ShellStyle.text(silent, 14, 600, Brand.BRAND_CORAL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mute := _button("Unmute all sounds" if SoundSettings.muted else "Mute all sounds", func():
		SoundSettings.set_muted(not SoundSettings.muted)
		_audio())
	mute.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mute)
	var reset := _button("Reset to normal", func():
		SoundSettings.reset()
		_audio())
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	_col.add_child(row)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heard := _just_heard.filter(func(h): return not SoundSettings.is_flagged(h.id))
	if not heard.is_empty():
		list.add_child(ShellStyle.text("Just heard", 15, 600))
		for h in heard.slice(0, 6):
			list.add_child(_sound_row(h.id, "just_heard"))
	var flagged := SoundSettings.CATALOG.filter(func(c): return SoundSettings.is_flagged(c[0]))
	if not flagged.is_empty():
		list.add_child(ShellStyle.text("Flagged (muted, being replaced)", 15, 600))
		for c in flagged:
			list.add_child(_sound_row(c[0], "list"))
	for ch in SoundSettings.CHANNELS.slice(2):
		list.add_child(ShellStyle.text(ch[1], 15, 600))
		for c in SoundSettings.CATALOG:
			if c[2] == ch[0] and not SoundSettings.is_flagged(c[0]):
				list.add_child(_sound_row(c[0], "list"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(480, 300)
	scroll.add_child(list)
	_col.add_child(scroll)
	_col.add_child(ShellStyle.text("Press N any time to flag what you just heard.", 13, 500, Brand.INK_MUTED))
	_col.add_child(_button("Back", func():
		_preview.stop()
		_fill()))


## One sound: its name, Play (always plays, even when flagged, so you can
## hear what you flagged) and Flag or Unflag.
func _sound_row(id: String, how: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var bad := SoundSettings.is_flagged(id)
	var name := ShellStyle.text(SoundSettings.info(id)[1], 14, 500, Brand.INK_MUTED if bad else Brand.INK)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var play := _button("Play", func(): _play(id))
	_small(play)
	row.add_child(play)
	var flag := _button("Unflag" if bad else "Flag bad", func():
		SoundSettings.flag(id, not bad, how)
		_note.text = ("Flagged \"%s\". It's muted now, and it's on the list to replace." if not bad \
			else "\"%s\" is back on.") % SoundSettings.info(id)[1]
		var keep := _note.text
		_audio()
		_note.text = keep)
	_small(flag)
	row.add_child(flag)
	# Room for the scroll bar.
	row.add_child(Control.new())
	row.get_child(-1).custom_minimum_size = Vector2(6, 0)
	return row


func _small(b: Button) -> void:
	b.custom_minimum_size = Vector2(86, 32)
	b.add_theme_font_size_override("font_size", 14)


## Plays a sound on its own (loops for 4 seconds), whatever its flag.
func _play(id: String) -> void:
	var stream = load("res://assets/audio/%s.ogg" % id)
	if stream == null:
		return
	_preview.stop()
	_preview.stream = stream
	_preview.bus = "Master"
	_preview.play()
	var silent := SoundSettings.why_silent()
	_note.text = silent if silent != "" else "Playing \"%s\"." % SoundSettings.info(id)[1]
	var t := get_tree().create_timer(4.0)
	_preview_stop = t
	t.timeout.connect(func():
		if _preview_stop == t:
			_preview.stop())


func _lost_connection() -> void:
	_fill()
	_shade.visible = true
	MenuState.showing = true
	_title.text = "Connection lost"
	_note.text = "The region's server stopped answering. Your city is safe on the server."
	for c in _col.get_children():
		if c is Button and c.text == "Resume":
			c.text = "Rejoin"
			for conn in c.pressed.get_connections():
				c.pressed.disconnect(conn.callable)
			c.pressed.connect(_rejoin)


func _rejoin() -> void:
	var old := Session.client
	_note.text = "Rejoining..."
	var c := Session.join_region(old.url, old.invite_code)
	c.joined.connect(Session.enter_region)
	c.failed.connect(func(reason): _note.text = reason)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override("font", Brand.ui(600))
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(action)
	return b
