extends Node3D
## The title screen, laid out like Cities: Skylines 2: a menu docked down the
## left edge over a slowly turning view of your latest city.
##
## Continue · New city · Load city · Play together · Quit

var _panel := PanelContainer.new()
var _pages := {}       # name -> Control
var _status := UiStyle.label("", 14, UiStyle.MUTED)
var _cam := Camera3D.new()
var _angle := 0.4
var _code := LineEdit.new()
var _server := LineEdit.new()
var _name := LineEdit.new()
var _city_name := LineEdit.new()
var _saves_list := VBoxContainer.new()
var _host_info := UiStyle.label("", 14)
var _joining := false


func _ready() -> void:
	_build_backdrop()
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.theme()
	ui.add_child(root)

	# Docked flush to the left edge, full height.
	var box := UiStyle.panel(0)
	box.content_margin_left = 36
	box.content_margin_right = 36
	box.content_margin_top = 48
	box.content_margin_bottom = 28
	_panel.add_theme_stylebox_override("panel", box)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	col.add_child(UiStyle.label("CITY", 52))
	col.add_child(UiStyle.label("A Midwestern town, built your way", 15, UiStyle.MUTED))
	col.add_child(_gap(28))
	for page in [_home_page(), _new_page(), _load_page(), _together_page()]:
		col.add_child(page)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(UiStyle.label("Build " + Hud._build_name(), 11, Color(UiStyle.MUTED, 0.7)))

	if not Session.pending_invite.is_empty():
		# Opened from an invite link: straight to joining.
		_code.text = Session.pending_invite.get("join", "")
		_server.text = Session.pending_invite.get("server", "")
		Session.pending_invite = {}
		_show("together")
	else:
		_show("home")


func _process(delta: float) -> void:
	_angle += delta * 0.03
	_cam.position = Vector3(cos(_angle) * 320.0, 170.0, sin(_angle) * 320.0)
	_cam.look_at(Vector3(0, 0, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_show("home")


# --- Pages -------------------------------------------------------------------

func _home_page() -> Control:
	var col := _page("home")
	var saves := Session.list_saves()
	if not saves.is_empty():
		var latest: Dictionary = saves[0]
		var b := _big_button("Continue", "%s  ·  %s people" % [latest.name, CitySim.money_text(latest.population)])
		b.pressed.connect(func(): Session.play_solo(latest.path))
		col.add_child(b)
	col.add_child(_big_button("New city", "Start fresh on open land", func(): _show("new")))
	if not saves.is_empty():
		col.add_child(_big_button("Load city", "%d saved" % saves.size(), func(): _show("load")))
	col.add_child(_big_button("Play together", "Build next to family and friends", func(): _show("together")))
	if not OS.has_feature("web"):
		col.add_child(_big_button("Quit", "", func(): get_tree().quit()))
	return col


func _new_page() -> Control:
	var col := _page("new")
	col.add_child(UiStyle.label("Name your city", 18))
	_city_name.placeholder_text = "Maple Falls"
	_city_name.custom_minimum_size = Vector2(0, 40)
	_city_name.text_submitted.connect(func(_t): _start_new())
	col.add_child(_city_name)
	col.add_child(_big_button("Start", "", _start_new))
	col.add_child(_back())
	return col


func _load_page() -> Control:
	var col := _page("load")
	col.add_child(UiStyle.label("Your cities", 18))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saves_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_saves_list)
	col.add_child(scroll)
	col.add_child(_back())
	return col


func _together_page() -> Control:
	var col := _page("together")
	col.add_child(UiStyle.label("Your name", 14, UiStyle.MUTED))
	_name.text = Session.profile.name
	_name.placeholder_text = "What neighbors see over your city"
	_name.max_length = 24
	_name.custom_minimum_size = Vector2(0, 38)
	col.add_child(_name)
	col.add_child(_gap(6))
	col.add_child(UiStyle.label("Invite code", 14, UiStyle.MUTED))
	_code.text = Session.profile.code
	_code.placeholder_text = "ABC123"
	_code.max_length = 12
	_code.custom_minimum_size = Vector2(0, 46)
	_code.add_theme_font_size_override("font_size", 24)
	_code.text_submitted.connect(func(_t): _join())
	col.add_child(_code)
	var adv := Button.new()
	adv.text = "Server address ▾"
	adv.flat = true
	adv.alignment = HORIZONTAL_ALIGNMENT_LEFT
	adv.add_theme_color_override("font_color", UiStyle.MUTED)
	col.add_child(adv)
	_server.text = Session.profile.server
	_server.placeholder_text = Session.LOCAL_SERVER
	_server.custom_minimum_size = Vector2(0, 36)
	_server.visible = _server.text != ""
	adv.pressed.connect(func(): _server.visible = not _server.visible)
	col.add_child(_server)
	col.add_child(_big_button("Join", "Your city starts next to theirs", _join))
	if not OS.has_feature("web"):
		col.add_child(_gap(8))
		col.add_child(UiStyle.label("Or host a region on this computer", 14, UiStyle.MUTED))
		col.add_child(_big_button("Host a region", "Friends join with your code", _host))
		_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_host_info)
	col.add_child(_back())
	return col


func _show(page: String) -> void:
	for p in _pages:
		_pages[p].visible = p == page
	_status.text = ""
	if page == "load":
		_fill_saves()
	elif page == "new":
		_city_name.grab_focus.call_deferred()
	elif page == "together":
		(_name if _name.text == "" else _code).grab_focus.call_deferred()


func _fill_saves() -> void:
	for c in _saves_list.get_children():
		c.queue_free()
	for s in Session.list_saves():
		var row := HBoxContainer.new()
		var when := Time.get_datetime_string_from_unix_time(s.saved, true).left(16)
		var b := _big_button(s.name, "%s people  ·  $%s  ·  %s" % [
			CitySim.money_text(s.population), CitySim.money_text(s.money), when])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): Session.play_solo(s.path))
		row.add_child(b)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Delete this city (click twice)"
		del.custom_minimum_size = Vector2(36, 0)
		del.pressed.connect(func():
			if del.text == "Delete?":
				Session.delete_save(s.path)
				_fill_saves()
			else:
				del.text = "Delete?")
		row.add_child(del)
		_saves_list.add_child(row)


# --- Actions -----------------------------------------------------------------

func _start_new() -> void:
	var n := _city_name.text.strip_edges()
	if n == "":
		n = _city_name.placeholder_text
	Session.new_city(n)


func _join() -> void:
	if _joining:
		return
	var n := _name.text.strip_edges()
	if n == "":
		_status.text = "Pick a name first."
		_name.grab_focus()
		return
	if _code.text.strip_edges() == "":
		_status.text = "Type the invite code you were sent."
		_code.grab_focus()
		return
	Session.profile.name = n
	Session.save_profile()
	_joining = true
	_status.text = "Joining..."
	var c := Session.join_region(_server.text, _code.text)
	c.joined.connect(func(): Session.enter_region())
	c.failed.connect(func(reason):
		_joining = false
		_status.text = reason)


func _host() -> void:
	var code := Session.host_region()
	if code == "":
		_status.text = "Couldn't start a region: port 9080 is busy."
		return
	_code.text = code
	_server.text = Session.LOCAL_SERVER
	_host_info.text = "Region running. Invite code: %s\nFriends on your network join with this computer's address, port 9080." % code
	if _name.text.strip_edges() != "":
		_join()


# --- Building blocks ---------------------------------------------------------

func _page(name: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_pages[name] = col
	return col


func _big_button(title: String, sub: String, action := Callable()) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54 if sub != "" else 46)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	col.add_child(UiStyle.label(title, 19))
	if sub != "":
		col.add_child(UiStyle.label(sub, 12, UiStyle.MUTED))
	if action.is_valid():
		b.pressed.connect(action)
	return b


func _back() -> Button:
	var b := Button.new()
	b.text = "‹ Back"
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _show("home"))
	return b


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Your latest city slowly turning behind the menu (or a demo town).
func _build_backdrop() -> void:
	add_child(SkyLight.new())
	add_child(Ground.new())
	_cam.fov = 45.0
	_cam.h_offset = -70.0  # keeps the town clear of the menu
	_cam.far = 4000.0
	add_child(_cam)
	var sim := CitySim.new()
	var saves := Session.list_saves()
	var data := Session._read(saves[0].path) if not saves.is_empty() else {}
	if not data.is_empty():
		sim.from_dict(data)
	else:
		sim.apply({"type": "build_grid", "a": [-150, -120], "b": [150, -120], "c": [150, 120], "block": 80})
		for x in range(-150, 151, 20):
			for z in range(-120, 121, 20):
				sim.apply({"type": "paint_zone", "center": [x, z], "radius": 14,
					"zone": ZoneMap.Zone.RESIDENTIAL if absi(x) > 40 else ZoneMap.Zone.COMMERCIAL})
		for i in 300:
			sim.tick()
	var roads := RoadView.new()
	add_child(roads)
	roads.setup(sim.network)
	var buildings := BuildingView.new()
	add_child(buildings)
	buildings.setup(sim)
