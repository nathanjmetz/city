class_name GameMenu
extends CanvasLayer
## The pause menu, like Cities: Skylines 2: a modal in the middle of the
## screen. Escape puts tools down and closes panels first (the HUD does that);
## once nothing is left, Escape opens this. Resume, save, back to the title
## screen, credits, or quit. In a shared region it shows the invite and lets you leave
## (the region keeps going).

var game: Node  # main.gd

var _shade := ColorRect.new()
var _col := VBoxContainer.new()
var _title := ShellStyle.title("", 28)
var _note := ShellStyle.text("", 14, 500, Brand.INK_MUTED)
var _was_speed := 1


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


func toggle() -> void:
	if _shade.visible:
		close()
	else:
		open()


func open() -> void:
	_fill()
	_shade.visible = true
	_was_speed = game.speed
	game.set_speed(0)


func close() -> void:
	_shade.visible = false
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
		# Auto picks what this computer can draw smoothly; the rest are fixed.
		var gfx := _button("Graphics: " + q.label(), func(): pass)
		gfx.pressed.connect(func():
			q.cycle()
			gfx.text = "Graphics: " + q.label())
		_col.add_child(gfx)
	_col.add_child(_button("Credits", func(): _note.text = SoundCredits.text()))
	if not OS.has_feature("web"):
		_col.add_child(_button("Quit to desktop", func():
			if Session.mode == Session.Mode.SOLO:
				Session.save_city(game.sim)
			get_tree().quit()))


func _lost_connection() -> void:
	_fill()
	_shade.visible = true
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
