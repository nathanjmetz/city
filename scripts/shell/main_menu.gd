extends Node3D
## The title screen, laid out like Cities: Skylines 2 and the Neighbors
## brand kit: the logo and a short menu docked down the left edge, over a
## deep-ink fade into a slowly turning view of your latest city.
##
## There is one shared map and one way to play: Play · Profile · Quit.
## Play drops you into your town in the family region. The first time on a
## device it asks for your PIN, six digits the host made for you (it says
## who you are, so there's no name to type either); after that, Play goes
## straight in. If the region's computer is off, you can play offline
## instead.

var _panel := PanelContainer.new()
var _pages := {}       # name -> Control
var _status := ShellStyle.text("", 14, 500, Brand.INK_MUTED)
var _cam := Camera3D.new()
const MENU_TOWN := MenuLife.MENU_TOWN
## How far out the camera circles downtown, in metres, and how high.
const ORBIT := 300.0
const ORBIT_HEIGHT := 70.0
## Seconds for one full turn: slow, so the town never feels hurried.
const TURN_SECONDS := 150.0

var _angle := 0.4
var _life: MenuLife
## The backdrop is built a piece a frame (_steps, a few milliseconds each),
## so the menu shows and answers at once; a picture of the town covers it
## meanwhile (BackdropReveal) and fades into the live one once it's drawn
## (the critic, 2026-10-26: blank and sluggish for 10-16 s while the whole
## town was built in one go). A step that returns false runs again next
## frame.
var _steps: Array = []
## The cars and people go on the streets just before the picture fades:
## too small to see in it, and drawing them slows the town's drawing.
var _people_in := false
var _reveal: BackdropReveal
## Most milliseconds of build steps a frame (a step is never split, so one
## can run over).
const STEP_MS := 6.0
## The backdrop being built, kept between the steps.
var _sim: MenuSim
var _town := {}
var _sky: SkyLight
var _land: TerrainView
var _roads: RoadView
var _buildings: BuildingView
var _wild: WildView
var _farmsteads: FarmsteadView
var _look: DayNight
var _forced := ""
## Tools taking the picture hold the camera where it starts (tools/menu_still.gd).
var hold_camera := false
var _boost := Callable()
## The look switches as the game had them, put back when the menu closes
## (the menu turns day and night and the seasons on for itself, unsaved).
var _was_cycle := false
var _was_seasons := true
## Debug (after `--`): `--menu-time=2026-12-15T23:00` shows that Marion
## time, `--menu-angle=1.5` sets where the camera starts, and
## `--menu-shot=path.png` saves the screen after a while and quits.
var _shot_path := ""
var _shot_at := 14.0
var _shot_time := 0.0
var _code := LineEdit.new()
var _server := LineEdit.new()
var _name := LineEdit.new()
var _host_info := ShellStyle.text("", 14)
var _joining := false
var _published_server := ""  # from Session.REGION_CONFIG
var _fetching := false
var _join_after_fetch := false
var _pin_after_fetch := ""
var _pin := LineEdit.new()  # your PIN, the first time on this device
var _published_code := ""  # the family region's invite code, from REGION_CONFIG
var _offline: Button  # shown when the region can't be reached
## Other invite codes to try if the region turns this one away (an old code
## kept on this device, or a typo): the family never sees "wrong code".
var _other_codes := []
var _retrying := false


# Let go of the cover lambda with the menu (a static Callable that outlives
# its script crashes the engine at quit).
func _exit_tree() -> void:
	Vegetation.cover_source = Callable()
	TrafficView.premade.clear()
	DayNight.cycle_on = _was_cycle
	DayNight.seasons_on = _was_seasons
	if _boost.is_valid() and RenderingServer.frame_pre_draw.is_connected(_boost):
		RenderingServer.frame_pre_draw.disconnect(_boost)


func _ready() -> void:
	GameMusic.play(get_tree(), GameMusic.Mode.MENU)
	_start_backdrop()
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
	for page in [_home_page(), _pin_page(), _profile_page()]:
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
		# One link and you're in once this device has played there; the
		# first time, your PIN.
		if Session.has_login("", _code.text):
			_join.call_deferred()
		else:
			_show("pin")
	else:
		_show("home")
	_fetch_server()


func _process(delta: float) -> void:
	if not _steps.is_empty():
		var t0 := Time.get_ticks_usec()
		while not _steps.is_empty() and Time.get_ticks_usec() - t0 < STEP_MS * 1000.0:
			var step: Callable = _steps.pop_front()
			if step.call() == false:
				_steps.push_front(step)
				break
	if not _cam.is_inside_tree():
		return
	# Still while the picture is up, so it fades into the same view.
	if not hold_camera and (_reveal == null or not is_instance_valid(_reveal) or _reveal.fading()):
		_angle = fposmod(_angle + delta * TAU / TURN_SECONDS, TAU)
	_place_camera()
	if _shot_path != "" and _life != null:
		_shot_time += delta
		if _shot_time >= _shot_at:
			var image := get_viewport().get_texture().get_image()
			image.save_png(_shot_path)
			print("menu shot: ", _shot_path, "  Marion time ", _life.wall.get("hour", -1), ":",
				_life.wall.get("minute", -1), " cars ", _life.sim.traffic.cars.size(), " walkers ",
				_life.sim.traffic.walkers.size())
			get_tree().quit()


## Low over the rooftops, like a drone circling the square, with the
## woods and fields running out to the haze behind.
func _place_camera() -> void:
	var ground := Terrain.ground_y(0.0, 0.0)
	_cam.position = Vector3(cos(_angle) * ORBIT, ground + ORBIT_HEIGHT, sin(_angle) * ORBIT)
	_cam.look_at(Vector3(0, ground + 8.0, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_show("home")


# --- Pages -------------------------------------------------------------------

func _home_page() -> Control:
	var col := _page("home")
	# Say what Play does: "Continue: Maple Grove, 711 people" once this
	# device has a town (the critic, 2026-10-26: the old line was vague).
	var last = Session.profile.get("last_town")
	var sub := "Your town, next to the neighbors"
	if last is Dictionary and str(last.get("name", "")) != "" and _has_any_login():
		sub = "Continue: %s, %s %s" % [last.name, CitySim.money_text(int(last.get("people", 0))),
			"person" if int(last.get("people", 0)) == 1 else "people"]
	var play := _big_button("Play", sub, _play)
	ShellStyle.primary(play)
	col.add_child(play)
	col.add_child(_big_button("Profile", "How neighbors see you", func(): _show("profile")))
	if not OS.has_feature("web"):
		col.add_child(_big_button("Quit", "", func(): get_tree().quit()))
	return col


## The first Play on a device: the PIN the host made for you, then in.
func _pin_page() -> Control:
	var col := _page("pin")
	col.add_child(ShellStyle.title("Your PIN"))
	col.add_child(_label("FROM THE HOST"))
	_pin.placeholder_text = "000000"
	_pin.max_length = 7
	_pin.custom_minimum_size = Vector2(0, 46)
	# Set in Overpass, like a street sign.
	_pin.add_theme_font_override("font", Brand.sign(700))
	_pin.add_theme_font_size_override("font_size", 24)
	_pin.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_pin.text_submitted.connect(func(_t): _join_with_pin())
	col.add_child(_pin)
	_code.text = Session.profile.code
	_server.text = Session.profile.server
	var play := _big_button("Play", "", _join_with_pin)
	ShellStyle.primary(play)
	col.add_child(play)
	if not OS.has_feature("web"):
		col.add_child(_gap(8))
		col.add_child(_label("OR HOST ONE ON THIS COMPUTER"))
		col.add_child(_big_button("Host a region", "Then add players and send them their PINs", _host))
		_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_host_info)
	col.add_child(_back())
	return col


func _join_with_pin() -> void:
	var pin := RegionServer._clean_pin(_pin.text)
	if pin.length() < 6:
		_status.text = "Type the six-digit PIN the host sent you."
		_pin.grab_focus()
		return
	_join(pin)


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
	if page == "pin":
		_pin.grab_focus.call_deferred()


# --- Actions -----------------------------------------------------------------

## Play: straight into your town in the family region. The first time on
## this device, it asks for your PIN.
func _play() -> void:
	_code.text = _family_code()
	if not Session.has_login("", _code.text) and not _has_any_login():
		_show("pin")
		return
	_join()


## Whether this device has played in a region before (its sign-in works
## whatever the code is now).
func _has_any_login() -> bool:
	return Session.profile.get("tokens") is Dictionary and not Session.profile.tokens.is_empty()


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


func _join(pin := "") -> void:
	if _joining:
		return
	if _code.text.strip_edges() == "":
		_code.text = _family_code()
	if _fetching and (_server.text == "" or _server.text == Session.profile.server):
		_status.text = "Finding the region..."
		_join_after_fetch = true
		_pin_after_fetch = pin
		return
	_joining = true
	_status.text = "Joining..."
	if not _retrying:
		_other_codes = []
		for code in [_published_code, Session.FAMILY_CODE, str(Session.profile.get("code", ""))]:
			if code != "" and code != _clean(_code.text) and not code in _other_codes:
				_other_codes.append(code)
	_retrying = false
	var c := Session.join_region(_server_address(), _code.text, "", false, pin)
	c.joined.connect(func(): Session.enter_region())
	c.waiting.connect(func(message): _status.text = message)
	c.failed.connect(func(reason):
		_joining = false
		if "invite code" in reason and not _other_codes.is_empty():
			# Try the region's own code before bothering anyone.
			_code.text = _other_codes.pop_front()
			_retrying = true
			_join.call_deferred(pin)
			return
		if "PIN" in reason:
			_show("pin")
		_status.text = reason
		# The region's computer is off, asleep or out of date: don't leave
		# anyone stuck on the title screen.
		_offline.visible = "answering" in reason or "version" in reason or "reach" in reason)


static func _clean(code: String) -> String:
	return code.strip_edges().to_upper().replace("-", "").replace(" ", "")


## Where the region is: the invite link's address, else the one the region
## publishes (its quick tunnel changes on every restart), else the last used.
func _server_address() -> String:
	var typed := _server.text
	# A browser can't reach a region on "this computer": an address like
	# that left in the profile would only ever say the region is offline.
	if OS.has_feature("web") and ("localhost" in typed or "127.0.0.1" in typed):
		typed = ""
	if typed != "" and typed != Session.profile.server:
		return typed
	if _published_server != "":
		return _published_server
	return typed


func _fetch_server(url := Session.REGION_CONFIG) -> void:
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
		# The API can be refused (rate limits, filters): the plain file is
		# a few minutes behind at worst, so try it before giving up.
		if _published_server == "" and url != Session.REGION_CONFIG_RAW:
			_fetch_server(Session.REGION_CONFIG_RAW)
			return
		_fetched())
	var headers := ["Accept: application/vnd.github.raw+json"] if url == Session.REGION_CONFIG else []
	if http.request(url, headers) != OK:
		http.queue_free()
		_fetched.call_deferred()


func _fetched() -> void:
	_fetching = false
	if _join_after_fetch:
		_join_after_fetch = false
		_join(_pin_after_fetch)


func _host() -> void:
	var code := Session.host_region()
	if code == "":
		_status.text = "Couldn't start a region: port 9080 is busy."
		return
	_code.text = code
	_server.text = Session.LOCAL_SERVER
	_published_server = ""
	_host_info.text = "Region running. In the game, open the region panel and press Players to add each person and copy their PIN.\nFamily on your network join with this computer's address, port 9080."
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


## The town as it is in Marion right now, circled slowly behind the menu:
## the picture first (cheap), then the town a piece a frame (_steps).
func _start_backdrop() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--menu-time="):
			_forced = a.trim_prefix("--menu-time=")
		elif a.begins_with("--menu-angle="):
			_angle = float(a.trim_prefix("--menu-angle="))
		elif a.begins_with("--menu-shot="):
			_shot_path = a.trim_prefix("--menu-shot=")
		elif a.begins_with("--menu-shot-after="):
			_shot_at = float(a.trim_prefix("--menu-shot-after="))
	# The day and the season are the real ones (and the sun, the haze, the
	# leaves, the snow and the crop calendar follow them: DayNight, as in
	# the game with day and night and seasons on). Not saved: the choice in
	# the game's own settings is put back on the way out.
	DayNight.load_settings()
	_was_cycle = DayNight.cycle_on
	_was_seasons = DayNight.seasons_on
	DayNight.cycle_on = true
	DayNight.seasons_on = true
	_reveal = BackdropReveal.cover(self, MenuStill.texture_for(_marion_now()))
	# The streets first, then the land under them, then the rest: drawn
	# side by side, the streets and the land each took two to three times
	# longer (measured 2026-10-26; why wasn't pinned down).
	_steps = [_bd_sky, _bd_camera, _bd_read, _bd_sim, _bd_life, _bd_roads, func(): return _roads.is_drawn(),
		_bd_land, func(): return _land.is_drawn(), _bd_buildings, _bd_wild, _bd_farmsteads, _bd_farms, _bd_exits]
	# The cars' models a few a frame (all at once they stall a frame).
	for key in VehicleModels.mesh_keys():
		_steps.append(func():
			for lod in 2:
				TrafficView.premade["%s/%d" % [key, lod]] = VehicleModels.build(key, lod))
	_steps.append_array([_bd_lights, _bd_signals, _bd_done, _bd_drawn, _bd_cars, _bd_walkers])


## Marion's clock now (or the debug time), for picking the picture.
func _marion_now() -> Dictionary:
	var unix := Time.get_unix_time_from_system()
	if _forced != "":
		var f := MenuLife.parse(_forced)
		if f > 0.0:
			unix = f
	return MarionTime.at(unix)


func _bd_sky() -> void:
	_sky = SkyLight.new()
	add_child(_sky)


func _bd_camera() -> void:
	_cam.fov = 45.0
	_cam.h_offset = -70.0  # keeps the town clear of the menu
	# As in play (CityCamera): out past the far land, so the county runs on
	# into the haze instead of stopping at a line 4 km out.
	_cam.near = 1.0
	_cam.far = 24000.0
	add_child(_cam)
	_place_camera()


## A grown town, made once by tools/menu_town.gd: a player's own early
## town is mostly bare lots and half-built shops. Its clock is Marion's.
func _bd_read() -> void:
	_town = Session._read(MENU_TOWN)


func _bd_sim() -> void:
	_sim = MenuSim.new()
	_sim.from_dict(_town)
	_town = {}


func _bd_life() -> void:
	_look = DayNight.new()
	_life = MenuLife.new()
	_life.setup(_sim, _look, _forced)
	add_child(_life)
	# Marion's real rain and cloud (MarionWeather), else the same odds as in
	# play; off if switched off there.
	var weather := Weather.new()
	weather.setup(_sim, _sky)
	add_child(weather)
	if _forced == "":
		var report := MarionWeather.new()
		report.setup(weather)
		add_child(report)


func _bd_roads() -> void:
	_roads = RoadView.new()
	# Drawn a few streets a frame, as a neighbor's town is.
	_roads.sliced = true
	add_child(_roads)
	_roads.setup(_sim.network, _sim)


func _bd_land() -> void:
	_land = TerrainView.new()
	# The menu's camera stays near the town: no preloading the county.
	_land.keep_land = false
	_land.gradual = true
	add_child(_land)
	_land.setup(_cam, _sim.network)
	TerrainView.set_county_hidden(_sim.county_removed.keys())


func _bd_buildings() -> void:
	_buildings = BuildingView.new()
	_buildings.sliced = true
	add_child(_buildings)
	_buildings.setup(_sim)


## The same wild woods, brush and county highways as the game.
func _bd_wild() -> void:
	_wild = WildView.new()
	add_child(_wild)
	_wild.setup(_sim)
	_land.graded.connect(_wild.regraded)


## Farmsteads and country homes out in the county.
func _bd_farmsteads() -> void:
	_farmsteads = FarmsteadView.new()
	add_child(_farmsteads)
	_farmsteads.setup(_sim)


## The farms' own fields, and the crop calendar for the county's.
func _bd_farms() -> void:
	var farms := FarmView.new()
	add_child(farms)
	farms.setup(_sim)


func _bd_exits() -> void:
	var exits := ExitRoads.new()
	add_child(exits)
	exits.setup(_sim, _land, "exits")


## The town's people and cars, as in the game.
func _bd_cars() -> void:
	var cars := TrafficView.new()
	cars.setup(_sim.traffic, _life.tick_fraction)
	add_child(cars)
	TrafficView.premade.clear()


func _bd_walkers() -> void:
	var walkers := WalkerView.new()
	walkers.setup(_sim.traffic, _life.tick_fraction)
	add_child(walkers)
	_people_in = true


func _bd_signals() -> void:
	var signals := JunctionView.new()
	signals.setup(_sim.traffic)
	signals.roads = _roads
	add_child(signals)


func _bd_lights() -> void:
	_look.setup(_sim, _sky, _life.tick_fraction)
	add_child(_look)  # street lights, headlights, windows at night
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# The browser's renderer has no sky bounce light, and a low sun
		# alone leaves the town flat and grey there: lift sun and shade,
		# after DayNight has set them for the frame.
		var sky := _sky
		_boost = func():
			sky.sun.light_energy *= 2.0
			sky.env.ambient_light_energy *= 2.2
		RenderingServer.frame_pre_draw.connect(_boost)
	var sim := _sim
	Vegetation.cover_source = func(p: Vector3) -> Array:
		var x := p.x + sim.terrain_offset.x
		var z := p.z + sim.terrain_offset.y
		return Terrain.wild_cover(x, z) + [Terrain.crops(x, z)]


## The picture fades into the town once it's drawn (BackdropReveal).
func _bd_done() -> void:
	# The picture may have given up and gone on a very slow machine.
	if is_instance_valid(_reveal):
		_reveal.watch(_drawn_checks() + [func(): return _people_in])


func _drawn_checks() -> Array:
	return [_land.is_drawn, _roads.is_drawn, _buildings.is_drawn, _wild.is_drawn, _farmsteads.is_drawn]


## Waits (false: again next frame) until the town is drawn, or the picture
## gave up waiting.
func _bd_drawn() -> bool:
	if not is_instance_valid(_reveal) or _reveal.fading():
		return true
	for check in _drawn_checks():
		if not check.call():
			return false
	return true
