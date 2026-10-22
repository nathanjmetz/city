class_name ChatPanel
extends CanvasLayer
## The region chat, docked to the left edge: who's online (click a name to
## fly over to their city), the last messages, and a line to type in. Enter
## starts typing and sends, Escape goes back to building, like the chat in
## Anno and Minecraft.

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
var _toggle := Button.new()
var _unread := 0
var _bell := AudioStreamPlayer.new()
var _bell_wait := 0.0


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
	_toggle.pressed.connect(func(): _set_open(not _body.visible))
	head.add_child(_toggle)
	var invite := Button.new()
	invite.text = "Invite"
	invite.focus_mode = Control.FOCUS_NONE
	invite.tooltip_text = "Copy an invite link for family and friends"
	invite.pressed.connect(func():
		DisplayServer.clipboard_set(_invite_text())
		_add_line({"from": "", "text": "Invite copied: " + _invite_text()}))
	head.add_child(invite)

	col.add_child(_body)
	_body.add_theme_constant_override("separation", 6)
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
	client.city_added.connect(func(_id): _update_who())
	_update_who()
	_set_open(true)


func _process(delta: float) -> void:
	_bell_wait -= delta


## Rings when someone else writes or a neighbor joins (never for your own lines).
func _ring_for(line: Dictionary) -> void:
	var from := str(line.get("from", ""))
	var me := Session.client.player_name
	var neighbor_joined := from == "" and str(line.get("text", "")).ends_with("joined the region") \
		and not str(line.text).begins_with(me + " ")
	if (from != "" and from != me) or neighbor_joined:
		if _bell_wait <= 0.0:
			_bell_wait = DOORBELL_GAP
			_bell.play()


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
	_toggle.text = "%s  Region chat  ·  %d online%s" % ["−" if _body.visible else "+", n,
		"  ·  %d new" % _unread if _unread > 0 and not _body.visible else ""]


func _set_open(open: bool) -> void:
	_body.visible = open
	if open:
		_unread = 0
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
