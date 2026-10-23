extends Node3D
## The title screen, laid out like Cities: Skylines 2 and the Neighbors
## brand kit: the logo and a short menu docked down the left edge, over a
## deep-ink fade into a slowly turning view of your latest city.
##
## There is one shared map and one way to play: Play · Profile · Quit.
## Play drops you into your town in the family region; the first time, it
## asks only your name. The region's invite code comes with the game (or
## from the region itself), so nobody types one; "Join with a code" is for
## a different region. If the region's computer is off, you can play
## offline instead.

var _panel := PanelContainer.new()
var _pages := {}       # name -> Control
var _status := ShellStyle.text("", 14, 500, Brand.INK_MUTED)
var _cam := Camera3D.new()
var _angle := 0.4
var _code := LineEdit.new()
var _server := LineEdit.new()
var _name := LineEdit.new()
var _host_info := ShellStyle.text("", 14)
var _joining := false
var _published_server := ""  # from Session.REGION_CONFIG
var _fetching := false
var _join_after_fetch := false
var _who := LineEdit.new()  # your name, on the invite code page
var _first := LineEdit.new()  # your name, the first time you press Play
var _published_code := ""  # the family region's invite code, from REGION_CONFIG
var _offline: Button  # shown when the region can't be reached
## Other invite codes to try if the region turns this one away (an old code
## kept on this device, or a typo): the family never sees "wrong code".
var _other_codes := []
var _retrying := false


func _ready() -> void:
	GameMusic.play(get_tree(), GameMusic.Mode.MENU)
	_build_backdrop()
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ShellStyle.theme()
	ui.add_child(root)
	root.add_child(_fade())

	# Docked flush to the left edge, full height.
	var box := ShellStyle.panel()
	box.content_margin_left = 36
	box.content_margin_right = 36
	box.content_margin_top = 44
	box.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", box)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.custom_minimum_size = Vector2(400, 0)
	root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var logo := TextureRect.new()
	logo.texture = load(Brand.LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(328, 94)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo)
	var tag := ShellStyle.text("Build your town. Wave to the neighbors.", 16, 500, Brand.INK_MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	col.add_child(_gap(24))
	for page in [_home_page(), _name_page(), _code_page(), _profile_page()]:
		col.add_child(page)
	_offline = _big_button("Play offline instead", "Your town on this computer, until the region is back", _play_offline)
	_offline.visible = false
	col.add_child(_offline)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(_app_line())
	col.add_child(ShellStyle.text("Build " + Hud._build_name(), 11, 500, Brand.INK_FAINT))

	if not Session.pending_invite.is_empty():
		# Opened from an invite link: straight to joining.
		_code.text = Session.pending_invite.get("join", "")
		_server.text = Session.pending_invite.get("server", "")
		Session.pending_invite = {}
		_show("code")
		# One link and you're in: once this device knows your name, it plays.
		if Session.profile.name != "" or Session.has_login("", _code.text):
			_join.call_deferred()
		else:
			_who.grab_focus.call_deferred()
	else:
		_show("home")
	_fetch_server()


func _process(delta: float) -> void:
	_angle += delta * 0.03
	var ground := Terrain.ground_y(0.0, 0.0)
	_cam.position = Vector3(cos(_angle) * 320.0, ground + 170.0, sin(_angle) * 320.0)
	_cam.look_at(Vector3(0, ground, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_show("home")


# --- Pages -------------------------------------------------------------------

func _home_page() -> Control:
	var col := _page("home")
	var play := _big_button("Play", "Your town, next to the neighbors", _play)
	ShellStyle.primary(play)
	col.add_child(play)
	col.add_child(_big_button("Profile", "How neighbors see you", func(): _show("profile")))
	var other := _back()
	other.text = "Join with a code"
	other.pressed.connect(func(): _show("code"))
	col.add_child(other)
	if not OS.has_feature("web"):
		col.add_child(_big_button("Quit", "", func(): get_tree().quit()))
	return col


func _code_page() -> Control:
	var col := _page("code")
	col.add_child(ShellStyle.title("Invite code"))
	col.add_child(_label("FROM THE HOST"))
	_code.text = Session.profile.code
	_code.placeholder_text = "ABC123"
	_code.max_length = 12
	_code.custom_minimum_size = Vector2(0, 46)
	# Invite codes are set in Overpass, like a street sign.
	_code.add_theme_font_override("font", Brand.sign(700))
	_code.add_theme_font_size_override("font_size", 24)
	_code.text_submitted.connect(func(_t): _join())
	col.add_child(_code)
	col.add_child(_gap(6))
	col.add_child(_label("YOUR NAME"))
	var who := _who
	who.text = Session.profile.name
	who.placeholder_text = "Who you are, over your town"
	who.max_length = 24
	who.custom_minimum_size = Vector2(0, 38)
	who.text_changed.connect(func(t):
		Session.profile.name = t.strip_edges()
		_name.text = t
		Session.save_profile())
	who.text_submitted.connect(func(_t): _join())
	col.add_child(who)
	# The server comes from the invite link or the region's config; there's
	# nothing to type.
	_server.text = Session.profile.server
	var play := _big_button("Play", "", _join)
	ShellStyle.primary(play)
	col.add_child(play)
	if not OS.has_feature("web"):
		col.add_child(_gap(8))
		col.add_child(_label("OR HOST ONE ON THIS COMPUTER"))
		col.add_child(_big_button("Host a region", "Family joins with your code", _host))
		_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_host_info)
	col.add_child(_back())
	return col


## The first Play: just your name, then straight in.
func _name_page() -> Control:
	var col := _page("name")
	col.add_child(ShellStyle.title("Welcome"))
	col.add_child(_label("YOUR NAME"))
	_first.placeholder_text = "Who you are, over your town"
	_first.max_length = 24
	_first.custom_minimum_size = Vector2(0, 38)
	_first.text_submitted.connect(func(_t): _name_and_play())
	col.add_child(_first)
	var play := _big_button("Play", "", _name_and_play)
	ShellStyle.primary(play)
	col.add_child(play)
	col.add_child(_back())
	return col


func _name_and_play() -> void:
	var n := _first.text.strip_edges()
	if n == "":
		_status.text = "Type your name: it goes over your town."
		_first.grab_focus()
		return
	Session.profile.name = n
	_name.text = n
	_who.text = n
	Session.save_profile()
	_play()


func _profile_page() -> Control:
	var col := _page("profile")
	col.add_child(ShellStyle.title("Profile"))
	col.add_child(_label("NAME OVER YOUR TOWN"))
	_name.text = Session.profile.name
	_name.placeholder_text = "Who you are, over your town"
	_name.max_length = 24
	_name.custom_minimum_size = Vector2(0, 38)
	_name.text_changed.connect(func(t):
		Session.profile.name = t.strip_edges()
		Session.save_profile())
	col.add_child(_name)
	col.add_child(_back())
	return col


func _show(page: String) -> void:
	for p in _pages:
		_pages[p].visible = p == page
	_status.text = ""
	_offline.visible = false
	if page == "code":
		_code.grab_focus.call_deferred()
	elif page == "name":
		_first.grab_focus.call_deferred()


# --- Actions -----------------------------------------------------------------

## Play: straight into your town in the family region. The first time,
## it asks your name; there is no code to type.
func _play() -> void:
	if str(Session.profile.get("name", "")).strip_edges() == "":
		_show("name")
		return
	_code.text = _family_code()
	_join()


## The family region's invite code: the one the region publishes, else the
## one this device last played with, else the one the game ships with.
func _family_code() -> String:
	if _published_code != "":
		return _published_code
	if str(Session.profile.get("code", "")) != "":
		return str(Session.profile.code)
	return Session.FAMILY_CODE


## The region can't be reached: your own town on this computer instead
## (the newest one saved here, or a new one).
func _play_offline() -> void:
	var saves := Session.list_saves()
	if saves.is_empty():
		var n := str(Session.profile.get("name", "")).strip_edges()
		Session.new_city((n if n != "" else "My") + "ville")
	else:
		Session.play_solo(saves[0].path)


func _join() -> void:
	if _joining:
		return
	if _code.text.strip_edges() == "":
		_status.text = "Type the invite code the host sent you."
		_code.grab_focus()
		return
	if _fetching and _server.text == "":
		_status.text = "Finding the region..."
		_join_after_fetch = true
		return
	_joining = true
	_status.text = "Joining..."
	if not _retrying:
		_other_codes = []
		for code in [_published_code, Session.FAMILY_CODE, str(Session.profile.get("code", ""))]:
			if code != "" and code != _clean(_code.text) and not code in _other_codes:
				_other_codes.append(code)
	_retrying = false
	var c := Session.join_region(_server_address(), _code.text)
	c.joined.connect(func(): Session.enter_region())
	c.waiting.connect(func(message): _status.text = message)
	c.failed.connect(func(reason):
		_joining = false
		if "invite code" in reason and not _other_codes.is_empty():
			# Try the region's own code before bothering anyone.
			_code.text = _other_codes.pop_front()
			_retrying = true
			_join.call_deferred()
			return
		_status.text = reason
		# The region's computer is off, asleep or out of date: don't leave
		# anyone stuck on the title screen.
		_offline.visible = "answering" in reason or "version" in reason or "reach" in reason)


static func _clean(code: String) -> String:
	return code.strip_edges().to_upper().replace("-", "").replace(" ", "")


## Where the region is: the invite link's address, else the one the region
## publishes (its quick tunnel changes on every restart), else the last used.
func _server_address() -> String:
	if _server.text != "" and _server.text != Session.profile.server:
		return _server.text
	if _published_server != "":
		return _published_server
	return _server.text


func _fetch_server() -> void:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	_fetching = true
	http.request_completed.connect(func(result, code, _h, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var d = JSON.parse_string(body.get_string_from_utf8())
			if d is Dictionary and str(d.get("server", "")).begins_with("ws"):
				_published_server = str(d.server)
			if d is Dictionary and str(d.get("code", "")) != "":
				_published_code = str(d.code).strip_edges().to_upper()
		http.queue_free()
		_fetched())
	if http.request(Session.REGION_CONFIG, ["Accept: application/vnd.github.raw+json"]) != OK:
		http.queue_free()
		_fetched.call_deferred()


func _fetched() -> void:
	_fetching = false
	if _join_after_fetch:
		_join_after_fetch = false
		_join()


func _host() -> void:
	var code := Session.host_region()
	if code == "":
		_status.text = "Couldn't start a region: port 9080 is busy."
		return
	_code.text = code
	_server.text = Session.LOCAL_SERVER
	_published_server = ""
	_host_info.text = "Region running. Invite code: %s\nFamily on your network join with this computer's address, port 9080." % code
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
	var t := ShellStyle.text(title, 17, 600)
	col.add_child(t)
	b.set_meta("title", t)
	var st: Label = null
	if sub != "":
		st = ShellStyle.text(sub, 12, 500, Brand.INK_MUTED)
		col.add_child(st)
	# Text on coral turns dark, as the kit asks.
	b.ready.connect(func():
		if b.has_meta("primary"):
			t.add_theme_color_override("font_color", Brand.ON_CORAL)
			if st:
				st.add_theme_color_override("font_color", Color(Brand.ON_CORAL, 0.75)))
	if action.is_valid():
		b.pressed.connect(action)
	return b


func _back() -> Button:
	var b := Button.new()
	b.text = "‹ Back"
	b.flat = true
	b.add_theme_color_override("font_color", Brand.INK_MUTED)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _show("home"))
	return b


## An uppercase label above a field, like the kit's "label" style.
## The desktop app: a link to it from the browser, and in the app what the
## updater is doing (or a link to a new app when the engine changed).
func _app_line() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var link := LinkButton.new()
	link.text = "Get the free Mac and Windows app"
	link.add_theme_font_override("font", Brand.ui(600))
	link.add_theme_font_size_override("font_size", 13)
	link.add_theme_color_override("font_color", Brand.INK_MUTED)
	link.focus_mode = Control.FOCUS_NONE
	link.pressed.connect(func(): OS.shell_open(Updater.DOWNLOAD_PAGE))
	link.visible = OS.has_feature("web")
	row.add_child(link)
	var note := ShellStyle.text(Updater.last_status, 12, 500, Brand.INK_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = note.text != ""
	row.add_child(note)
	var show := func(text: String):
		note.text = text
		note.visible = text != ""
		if Updater.new_app:
			link.text = "Download the new version"
			link.visible = true
	Updater.status.connect(show)
	if Updater.new_app:
		show.call(Updater.last_status)
	return row


func _label(s: String) -> Label:
	var l := ShellStyle.text(s, 11, 600, Brand.INK_MUTED)
	return l


## Deep ink behind the menu, fading out across the town.
func _fade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(Brand.SURFACE, 0.92))
	g.set_color(1, Color(Brand.SURFACE, 0.0))
	g.set_offset(0, 0.18)
	g.set_offset(1, 0.62)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Your latest city slowly turning behind the menu (or a demo town).
func _build_backdrop() -> void:
	add_child(SkyLight.new())
	_cam.fov = 45.0
	_cam.h_offset = -70.0  # keeps the town clear of the menu
	_cam.far = 4000.0
	add_child(_cam)
	var land := TerrainView.new()
	add_child(land)
	var woods := TerrainForest.new()
	woods.setup(_cam)
	add_child(woods)
	var sim := CitySim.new()
	var saves := Session.list_saves()
	var data := Session._read(saves[0].path) if not saves.is_empty() else {}
	if not data.is_empty():
		sim.from_dict(data)
	else:
		sim.apply({"type": "build_grid", "a": [-150, -120], "b": [150, -120], "c": [150, 120], "block": 80})
		# Every street side zoned: shops down the middle, homes either side.
		for id in sim.network.segments.keys():
			var c := sim.network.curve_of(id)
			var mid_x: float = (c[0].x + c[2].x) * 0.5
			for side in [-1, 1]:
				sim.apply({"type": "zone_frontage", "seg": id, "side": side,
					"zone": ZoneMap.Zone.RESIDENTIAL if absf(mid_x) > 40.0 else ZoneMap.Zone.COMMERCIAL})
		for i in 300:
			sim.tick()
	var roads := RoadView.new()
	add_child(roads)
	roads.setup(sim.network, sim)
	land.setup(_cam, sim.network)
	var buildings := BuildingView.new()
	add_child(buildings)
	buildings.setup(sim)
