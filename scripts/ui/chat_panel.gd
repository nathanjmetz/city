class_name ChatPanel
extends CanvasLayer
## The region chat: a chat button in the top bar (with how many messages
## came in since you last looked) opens a box docked to the left edge, under
## the bar: who's online (click a name to fly over to their city), the last
## messages, and a line to type in. Closed, it covers nothing (Brawn
## 2026-10-23), like the chat in Cities: Skylines 2's mods and Anno. Enter
## opens it and starts typing, Escape goes back to building.

const WIDTH := 300
## The HUD's top bar height: the chat docks right under it.
const TOP_BAR := 32
## A neighbor event rings the doorbell at most this often, in seconds.
const DOORBELL_GAP := 3.0

var cam: CityCamera
var region_view: RegionView

var _panel := PanelContainer.new()
var _who := HFlowContainer.new()
var _log := RichTextLabel.new()
var _line := LineEdit.new()
var _body := VBoxContainer.new()
var _requests := VBoxContainer.new()
var _players := VBoxContainer.new()  # (host) everyone and their PIN
var _players_button := Button.new()
var _new_name := LineEdit.new()
var _just_added := ""  # copied to the clipboard once its PIN comes back
var _toggle := Button.new()
var _unread := 0
var _bell := AudioStreamPlayer.new()
var _bell_wait := 0.0
var _button: Button  # in the top bar
var _badge := Label.new()  # messages since you last looked


func setup(camera: CityCamera, view: RegionView) -> void:
	cam = camera
	region_view = view


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ShellStyle.theme()
	add_child(root)

	# Flush with the left edge, under the top bar; only the inner corner rounds.
	var box := ShellStyle.panel(8)
	box.corner_radius_top_right = 0
	box.border_width_bottom = 1
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	_panel.position.y = TOP_BAR

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_toggle.flat = true
	_toggle.add_theme_font_override("font", Brand.ui(600))
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle.pressed.connect(func(): _set_open(false))
	head.add_child(_toggle)
	var invite := Button.new()
	invite.text = "Invite"
	invite.focus_mode = Control.FOCUS_NONE
	invite.tooltip_text = "Copy an invite link for family and friends"
	invite.pressed.connect(func():
		DisplayServer.clipboard_set(_invite_text())
		_add_line({"from": "", "text": "Invite copied: " + _invite_text()}))
	head.add_child(invite)
	# The host adds players here and sends each their PIN.
	_players_button.text = "Players"
	_players_button.toggle_mode = true
	_players_button.focus_mode = Control.FOCUS_NONE
	_players_button.tooltip_text = "Add a player and get the PIN to send them"
	_players_button.toggled.connect(func(on): _players.visible = on)
	head.add_child(_players_button)

	col.add_child(_body)
	_body.add_theme_constant_override("separation", 6)
	# The host lets new players in from here.
	_requests.add_theme_constant_override("separation", 4)
	_body.add_child(_requests)
	_players.add_theme_constant_override("separation", 4)
	_players.visible = false
	_body.add_child(_players)
	_who.add_theme_constant_override("h_separation", 4)
	_who.add_theme_constant_override("v_separation", 4)
	_body.add_child(_who)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(WIDTH - 24, 130)
	_log.add_theme_font_override("normal_font", Brand.ui(500))
	_log.add_theme_font_override("bold_font", Brand.ui(700))
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_font_size_override("bold_font_size", 14)
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_body.add_child(_log)
	_line.placeholder_text = "Press Enter to chat"
	_line.max_length = 300
	_line.custom_minimum_size = Vector2(0, 34)
	_line.text_submitted.connect(_send)
	_body.add_child(_line)

	# The brand's doorbell (E-C) means a neighbor did something.
	_bell.stream = load("res://assets/audio/ui/doorbell.ogg")
	_bell.bus = "UI" if AudioServer.get_bus_index("UI") != -1 else "Master"
	_bell.volume_db = -6.0
	add_child(_bell)

	var client := Session.client
	for line in client.region.chat:
		_add_line(line)
	_unread = 0
	client.chat_received.connect(func(line):
		_add_line(line)
		_ring_for(line)
		if not _body.visible:
			_unread += 1
			_update_title())
	client.players_changed.connect(_update_who)
	client.requests_changed.connect(func():
		_update_requests()
		if not client.requests.is_empty():
			_set_open(true)
		if not client.requests.is_empty() and _bell_wait <= 0.0:
			_bell_wait = DOORBELL_GAP
			_ring())
	_update_requests()
	client.pins_changed.connect(_update_players)
	_update_players()
	client.city_added.connect(func(_id): _update_who())
	_update_who()
	_set_open(false)


## The top bar's chat button: a speech bubble, and a count when new
## messages came in while it was closed.
func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Region chat  (Enter)"
	_button.custom_minimum_size = Vector2(34, 24)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(row)
	var icon := Icon.new("chat", 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_badge.add_theme_font_override("font", Brand.ui(700))
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Brand.BRAND_CORAL)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)
	_button.toggled.connect(func(on): _set_open(on))
	_update_title()
	return _button


func _process(delta: float) -> void:
	_bell_wait -= delta


## (Host) everyone waiting to be let in, with a yes and a no.
func _update_requests() -> void:
	for c in _requests.get_children():
		c.queue_free()
	for name in Session.client.requests:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var l := ShellStyle.text("%s wants to join" % name, 14, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var yes := Button.new()
		yes.text = "Let in"
		yes.focus_mode = Control.FOCUS_NONE
		ShellStyle.primary(yes)
		yes.pressed.connect(func(): Session.client.approve(name, true))
		row.add_child(yes)
		var no := Button.new()
		no.text = "No"
		no.focus_mode = Control.FOCUS_NONE
		no.pressed.connect(func(): Session.client.approve(name, false))
		row.add_child(no)
		_requests.add_child(row)


## (Host) every player with their PIN, and a line to add someone. A PIN
## says who a player is, so it's all they type to get in.
func _update_players() -> void:
	var client := Session.client
	_players_button.visible = client.is_host
	if not client.is_host:
		_players.visible = false
		return
	for c in _players.get_children():
		if c != _new_name.get_parent():
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
			_add_line({"from": "", "text": "%s's PIN is %s. A message with it and the link is copied: paste it to them." % [name, pin]})
		var l := ShellStyle.text(name, 14, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var code := ShellStyle.text(pin.left(3) + " " + pin.substr(3) if pin != "" else "no PIN", 15, 700)
		code.add_theme_font_override("font", Brand.sign(700))
		row.add_child(code)
		if pin != "":
			var copy := Button.new()
			copy.text = "Copy"
			copy.focus_mode = Control.FOCUS_NONE
			copy.tooltip_text = "Copy a message with the link and %s's PIN" % name
			copy.pressed.connect(func():
				DisplayServer.clipboard_set(pin_message(name, pin))
				_add_line({"from": "", "text": "Copied %s's PIN message." % name}))
			row.add_child(copy)
		if not p.get("host", false):
			var off := Button.new()
			off.text = "Remove" if pin != "" else "New PIN"
			off.focus_mode = Control.FOCUS_NONE
			off.tooltip_text = "Their PIN stops working" if pin != "" else "Let them in again"
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
		Session.client.add_player(n)
		_new_name.text = ""


## What the host sends a player: where to play, and their PIN.
static func pin_message(name: String, pin: String) -> String:
	return "%s, come build next to me in Neighbors: https://nathanjmetz.github.io/city/ (or the free Mac/Windows app from there). Your PIN is %s." % [name, pin]


## Rings when someone else writes or a neighbor joins (never for your own lines).
func _ring_for(line: Dictionary) -> void:
	var from := str(line.get("from", ""))
	var me := Session.client.player_name
	var neighbor_joined := from == "" and str(line.get("text", "")).ends_with("joined the region") \
		and not str(line.text).begins_with(me + " ")
	if (from != "" and from != me) or neighbor_joined:
		if _bell_wait <= 0.0:
			_bell_wait = DOORBELL_GAP
			_ring()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		_set_open(true)
		_line.grab_focus()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Escape while typing goes back to the city without closing anything else.
	if _line.has_focus() and event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_line.release_focus()
		get_viewport().set_input_as_handled()


func _send(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		Session.client.send_chat(text)
	_line.clear()
	_line.release_focus()


func _add_line(line: Dictionary) -> void:
	var from := str(line.get("from", ""))
	var text := str(line.get("text", "")).replace("[", "[lb]")
	if from == "":
		_log.append_text("[color=#%s]%s[/color]\n" % [Brand.INK_MUTED.to_html(false), text])
	else:
		# A dot in the player's color, then their name in cream (dark colors
		# like lake and plum stay readable that way).
		var color := _color_of(from).to_html(false)
		_log.append_text("[color=#%s]•[/color] [b]%s[/b]  %s\n" % [color, from.replace("[", "[lb]"), text])


## A chip for every city: click to fly over and watch it. Online players
## are bright, away ones dimmed.
func _update_who() -> void:
	for c in _who.get_children():
		c.queue_free()
	var client := Session.client
	var ids := client.region.cities.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = client.region.cities[id]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var mine: bool = id == client.my_city
		b.text = "Home" if mine else c.player
		b.tooltip_text = "Fly to " + c.name
		var online := client.players.any(func(p): return p.id == c.owner)
		b.icon = _dot(client.region.color_of(id, client.my_city), online)
		b.add_theme_color_override("font_color", Brand.INK if online else Brand.INK_FAINT)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): cam.fly_to(region_view.city_position(id)))
		_who.add_child(b)
	_update_title()


func _update_title() -> void:
	var n := Session.client.players.size()
	_toggle.text = "−  Region chat  ·  %d online" % n
	_badge.text = str(_unread) if _unread > 0 else ""
	_badge.visible = _unread > 0
	if _button:
		_button.custom_minimum_size.x = 34 + (14 if _unread > 0 else 0)
		_button.tooltip_text = "Region chat  (Enter)  ·  %d online%s" % [n, ", %d new" % _unread if _unread > 0 else ""]


func _set_open(open: bool) -> void:
	_body.visible = open
	_panel.visible = open
	if open:
		_unread = 0
	if _button:
		_button.set_pressed_no_signal(open)
	_update_title()


func _color_of(player_name: String) -> Color:
	var client := Session.client
	for id in client.region.cities:
		if client.region.cities[id].player == player_name:
			return client.region.color_of(id, client.my_city)
	return Brand.INK


## A small round badge in a player's color (hollow while they're away).
static func _dot(color: Color, filled: bool) -> ImageTexture:
	const S := 12
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - S * 0.5, y + 0.5 - S * 0.5).length()
			var a := clampf(S * 0.5 - d, 0.0, 1.0)
			if not filled:
				a *= clampf(d - (S * 0.5 - 3.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(img)


func _invite_text() -> String:
	var c := Session.client
	if c.url.begins_with("wss://"):
		return Session.invite_link(c.url, c.invite_code)
	return "Invite code %s, server %s" % [c.invite_code, c.url]


## The doorbell, unless the player flagged it as a bad sound.
func _ring() -> void:
	if SoundSettings.is_flagged("ui/doorbell"):
		return
	SoundSettings.heard("ui/doorbell", db_to_linear(_bell.volume_db))
	_bell.play()
