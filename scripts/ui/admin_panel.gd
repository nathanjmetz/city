class_name AdminPanel
extends CanvasLayer
## Admin: one place for the host's tools, behind a crown button in the top
## bar that only the host sees (Nathan 2026-10-26: "an admin place for
## myself… management of the different players in their pins, and audio
## studio, and anything else that we end up putting there"). There is no
## sign-in: the host is whoever the region server says is host (their PIN
## says who they are), and the server refuses host requests from anyone
## else, so this only gathers tools the host already had.
##
## Inside: everyone waiting to be let in (it opens on its own when someone
## asks; the chat rings the doorbell), every player with their PIN (add,
## copy the message to send, remove), and the Sound mixer (desktop app only;
## Ctrl/Cmd+Shift+F12 still opens it too). New admin tools go in as sections.

const WIDTH := 340

var _root := Control.new()
var _panel := PanelContainer.new()
var _requests := VBoxContainer.new()
var _players := VBoxContainer.new()
var _new_name := LineEdit.new()
var _note := Label.new()
var _just_added := ""  # copied to the clipboard once its PIN comes back
var _button: Button  # in the top bar
var client: RegionClient


func setup(region_client: RegionClient) -> void:
	client = region_client


func _ready() -> void:
	layer = 3
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ShellStyle.theme()
	add_child(_root)

	var box := ShellStyle.panel(8)
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 0
	box.border_width_bottom = 1
	box.border_width_left = 1
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.visible = false
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	var title := ShellStyle.title("Admin", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): set_open(false))
	head.add_child(close)
	col.add_child(head)
	var sub := ShellStyle.text("Only you see this: you're the host.", 13, 500, Brand.INK_MUTED)
	col.add_child(sub)

	_requests.add_theme_constant_override("separation", 4)
	col.add_child(_requests)

	col.add_child(HSeparator.new())
	_players.add_theme_constant_override("separation", 4)
	col.add_child(_players)
	_note.add_theme_font_override("font", Brand.ui(500))
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Brand.BRAND_MINT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(WIDTH - 28, 0)
	_note.visible = false
	col.add_child(_note)

	col.add_child(HSeparator.new())
	col.add_child(ShellStyle.text("SOUND", 11, 700, Brand.INK_MUTED))
	var sound := HBoxContainer.new()
	sound.add_theme_constant_override("separation", 8)
	var words := ShellStyle.text("Sound mixer: every sound's volume and tuning", 14, 600)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sound.add_child(words)
	if SoundMixer.available():
		var open := Button.new()
		open.text = "Open"
		open.focus_mode = Control.FOCUS_NONE
		open.tooltip_text = "The Sound mixer  (Ctrl/Cmd+Shift+F12)"
		ShellStyle.primary(open)
		open.pressed.connect(_open_mixer)
		sound.add_child(open)
	else:
		sound.add_child(ShellStyle.text("In the desktop app", 13, 600, Brand.INK_MUTED))
	col.add_child(sound)

	get_viewport().size_changed.connect(func():
		if _panel.visible:
			_place.call_deferred())
	client.pins_changed.connect(_update)
	# Someone wants to join: Admin opens on its own with a yes and a no.
	client.requests_changed.connect(func():
		_update()
		if not client.requests.is_empty():
			set_open(true))
	_update()


## The top bar's Admin button: a crown (the host's mark), hidden for
## everyone but the host.
func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Admin: players and PINs, Sound mixer"
	_button.custom_minimum_size = Vector2(34, 24)
	var icon := Icon.new("admin", 16)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon.offset_left = -8
	icon.offset_top = -8
	icon.offset_right = 8
	icon.offset_bottom = 8
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(icon)
	_button.toggled.connect(set_open)
	_button.visible = client.is_host
	return _button


func is_open() -> bool:
	return _panel.visible


func set_open(open: bool) -> void:
	open = open and client.is_host
	_panel.visible = open
	if _button:
		_button.set_pressed_no_signal(open)
	if open:
		_note.visible = false
		_update()
		_place()


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()


## Right under the button, its right edge lined up with the button's.
func _place() -> void:
	_panel.reset_size()
	if _button == null or not _button.is_inside_tree():
		return
	var r := _button.get_global_rect()
	var x := clampf(r.end.x - _panel.size.x, 0.0, maxf(0.0, _root.size.x - _panel.size.x))
	_panel.position = Vector2(x, r.end.y + 4.0)


func _open_mixer() -> void:
	set_open(false)
	var admin_audio := get_node_or_null("/root/AdminAudio")
	if admin_audio:
		admin_audio.open_mixer()


func _update() -> void:
	if _button:
		_button.visible = client.is_host
	if not client.is_host:
		_panel.visible = false
		return
	_update_requests()
	_update_players()
	if _panel.visible:
		_place.call_deferred()


## Everyone waiting to be let in, with a yes and a no.
func _update_requests() -> void:
	for c in _requests.get_children():
		_requests.remove_child(c)
		c.queue_free()
	var waiting: Array = client.requests
	_requests.visible = not waiting.is_empty()
	if waiting.is_empty():
		return
	_requests.add_child(ShellStyle.text("WAITING TO JOIN", 11, 700, Brand.INK_MUTED))
	for name in waiting:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var l := ShellStyle.text(str(name), 14, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var yes := Button.new()
		yes.text = "Let in"
		yes.focus_mode = Control.FOCUS_NONE
		ShellStyle.primary(yes)
		yes.pressed.connect(func(): client.approve(name, true))
		row.add_child(yes)
		var no := Button.new()
		no.text = "No"
		no.focus_mode = Control.FOCUS_NONE
		no.pressed.connect(func(): client.approve(name, false))
		row.add_child(no)
		_requests.add_child(row)


## Every player with their PIN, and a line to add someone. A PIN says who a
## player is, so it's all they type to get in.
func _update_players() -> void:
	for c in _players.get_children():
		if c != _new_name.get_parent():
			_players.remove_child(c)
			c.queue_free()
	_players.add_child(ShellStyle.text("PLAYERS AND THEIR PINS", 11, 700, Brand.INK_MUTED))
	for p in client.pins:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name := str(p.get("name", ""))
		var pin := str(p.get("pin", ""))
		if pin != "" and name.to_lower() == _just_added.to_lower():
			_just_added = ""
			DisplayServer.clipboard_set(pin_message(name, pin))
			_say("%s's PIN is %s. A message with it and the link is copied: paste it to them." % [name, pin])
		var l := ShellStyle.text(name + ("  (you)" if p.get("host", false) else ""), 14, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
		row.add_child(l)
		var code := ShellStyle.text(pin.left(3) + " " + pin.substr(3) if pin != "" else "no PIN", 15, 700)
		code.add_theme_font_override("font", Brand.sign(700))
		code.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(code)
		if pin != "":
			var copy := Button.new()
			copy.text = "Copy"
			copy.focus_mode = Control.FOCUS_NONE
			copy.tooltip_text = "Copy a message with the link and %s's PIN" % name
			copy.pressed.connect(func():
				DisplayServer.clipboard_set(pin_message(name, pin))
				_say("Copied %s's PIN message." % name))
			row.add_child(copy)
		if not p.get("host", false):
			var off := Button.new()
			off.text = "Remove" if pin != "" else "New PIN"
			off.focus_mode = Control.FOCUS_NONE
			off.tooltip_text = "Their PIN stops working and their town comes off the map" if pin != "" else "Let them in again, with a fresh town"
			off.pressed.connect(func():
				if pin != "":
					client.remove_pin(name)
				else:
					_just_added = name
					client.add_player(name))
			row.add_child(off)
		_players.add_child(row)
	if _new_name.get_parent() == null:
		var add := HBoxContainer.new()
		add.add_theme_constant_override("separation", 4)
		_new_name.placeholder_text = "Their name"
		_new_name.max_length = 24
		_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_new_name.text_submitted.connect(func(_t): _add_player())
		add.add_child(_new_name)
		var make := Button.new()
		make.text = "Add player"
		make.focus_mode = Control.FOCUS_NONE
		ShellStyle.primary(make)
		make.pressed.connect(_add_player)
		add.add_child(make)
		_players.add_child(add)
	_players.move_child(_new_name.get_parent(), -1)


func _add_player() -> void:
	var n := _new_name.text.strip_edges()
	if n != "":
		_just_added = n
		client.add_player(n)
		_new_name.text = ""


func _say(text: String) -> void:
	_note.text = text
	_note.visible = true
	if _panel.visible:
		_place.call_deferred()


## What the host sends a player: where to play, and their PIN.
static func pin_message(name: String, pin: String) -> String:
	return "%s, come build next to me in Neighbors: https://nathanjmetz.github.io/city/ (or the free Mac/Windows app from there). Your PIN is %s." % [name, pin]
