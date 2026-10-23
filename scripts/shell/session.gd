extends Node
## The game around the city: who you are, which city is open, and the
## connection to a shared region. An autoload (Session), so it lives on
## while scenes change between the title screen and the game.

const PROFILE_PATH := "user://player.json"
const SAVE_DIR := "user://cities"
## The town from before there were save slots.
const OLD_SAVE := "user://town.json"
const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
## Address used when an invite has none: a region on this computer.
const LOCAL_SERVER := "ws://localhost:9080"
## Where the region publishes its current address ({"server": "wss://..."}),
## so Play works with just the invite code even after the host restarts.
## It lives on its own branch, so updating it doesn't rebuild the game, and
## is read through the API, which isn't cached for minutes like raw files.
## tools/host/neighbors-host.sh on the host's computer keeps it current.
const REGION_CONFIG := "https://api.github.com/repos/nathanjmetz/city/contents/server.json?ref=region"

enum Mode { SOLO, ONLINE }

var mode := Mode.SOLO
## Solo: the save file of the open city.
var save_path := ""
## The name for a new city that hasn't been saved yet.
var new_city_name := ""
## The difficulty picked for a new city that hasn't started yet.
var new_city_difficulty := ""
## Solo: the open city's name.
var current_name := ""
## Online: the connection to the region (also there while joining).
var client: RegionClient
## A region hosted by this game window, if any.
var host: RegionServer
## {"id", "name", "server", "code"}
var profile := {}
## An invite from the page address (?join=CODE&server=wss://...), used once.
var pending_invite := {}


func _ready() -> void:
	_load_profile()
	_migrate_old_save()
	_read_page_invite()


func online() -> bool:
	return mode == Mode.ONLINE and client != null and client.is_joined


# --- Solo cities -------------------------------------------------------------

## Every saved city, newest first: [{"path", "name", "population", "money", "saved"}].
func list_saves() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := SAVE_DIR.path_join(f)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = data.get("meta", {})
		out.append({"path": path, "name": meta.get("name", f.get_basename()),
			"population": int(meta.get("population", 0)), "money": int(data.get("economy", {}).get("money", 0)),
			"saved": int(meta.get("saved", FileAccess.get_modified_time(path)))})
	out.sort_custom(func(a, b): return a.saved > b.saved)
	return out


## A free save file for a new city with this name.
func new_save_path(city_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var slug := city_name.to_lower().validate_filename().replace(" ", "-")
	if slug == "":
		slug = "city"
	var path := SAVE_DIR.path_join(slug + ".json")
	var n := 2
	while FileAccess.file_exists(path):
		path = SAVE_DIR.path_join("%s-%d.json" % [slug, n])
		n += 1
	return path


func save_city(sim: CitySim, path := save_path) -> void:
	if path == "":
		return
	var d := sim.to_dict()
	d["meta"] = {"name": current_name if path == save_path else city_name(path),
		"population": sim.stats.population, "saved": int(Time.get_unix_time_from_system())}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)


func city_name(path := save_path) -> String:
	return _read(path).get("meta", {}).get("name", new_city_name if new_city_name != "" else "My Town")


## Starts a new city. Its file is written at the first save.
func new_city(name: String, difficulty := "normal") -> void:
	new_city_name = name
	new_city_difficulty = difficulty
	play_solo(new_save_path(name))


func play_solo(path: String) -> void:
	leave_region()
	mode = Mode.SOLO
	save_path = path
	current_name = city_name(path)
	Terrain.view_origin = Vector2.ZERO
	LoadingScreen.open("Opening your town")
	get_tree().change_scene_to_file(GAME_SCENE)


# --- Shared regions ----------------------------------------------------------

## Starts joining a region. The client's joined or failed signal says how it went.
func join_region(server: String, code: String, password := "", new_account := false) -> RegionClient:
	leave_region(false)
	server = normalize_server(server)
	code = code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	profile.server = server
	profile.code = code
	save_profile()
	client = RegionClient.new()
	add_child(client)
	LoadingScreen.open("Connecting to the region")
	client.failed.connect(func(_reason): LoadingScreen.close())
	client.waiting.connect(func(_message):
		_keep_token(server, code, client.token)
		LoadingScreen.close())
	client.joined.connect(func():
		_keep_token(server, code, client.token)
		_keep_page_invite(code))
	client.join(server, code, profile.id, str(profile.name), password, new_account,
		"" if password != "" else _token_for(code))
	return client


## Whether this device has been in the region with this invite code before.
func has_login(_server: String, code: String) -> bool:
	return _token_for(code.strip_edges().to_upper().replace("-", "")) != ""


## This device's sign-in for a region, by its invite code (the server's
## address can change; older saves keyed it "server|code|name").
func _token_for(code: String) -> String:
	if profile.tokens.has(code):
		return str(profile.tokens[code])
	for key in profile.tokens:
		var parts := str(key).split("|")
		if parts.size() == 3 and parts[1] == code:
			return str(profile.tokens[key])
	return ""


func _keep_token(_server: String, code: String, token: String) -> void:
	if token != "":
		profile.tokens[code] = token
		save_profile()


## Hosts a region from this window (desktop only) and joins it.
func host_region(port := 9080) -> String:
	if host == null:
		host = RegionServer.new()
		add_child(host)
		var err := host.start(port, "", "user://hosted-region.json", str(profile.name))
		if err != OK:
			host.queue_free()
			host = null
			return ""
	return host.invite_code


func enter_region() -> void:
	mode = Mode.ONLINE
	save_path = ""
	# The land is drawn around your own town, which sits at the world's centre.
	Terrain.view_origin = client.region.cities[client.my_city].origin
	LoadingScreen.open("Meeting the neighbors")
	LoadingScreen.progress(0.3, "Meeting the neighbors")
	get_tree().change_scene_to_file(GAME_SCENE)


func leave_region(stop_host := true) -> void:
	if client:
		client.leave()
		client.queue_free()
		client = null
	if stop_host and host:
		host.stop()
		host.queue_free()
		host = null


func to_menu() -> void:
	leave_region(false)
	if OS.has_feature("web"):
		# Left on purpose: a refresh stays on the title screen.
		JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname)")
	mode = Mode.SOLO
	get_tree().change_scene_to_file(MENU_SCENE)


## An invite people can share: a link on the web, a code and address otherwise.
func invite_link(server := str(profile.get("server", "")), code := str(profile.get("code", ""))) -> String:
	return "https://nathanjmetz.github.io/city/?join=%s&server=%s" % [code, server.uri_encode()]


## "myhost:9080" -> "ws://myhost:9080"; https:// -> wss://.
static func normalize_server(s: String) -> String:
	s = s.strip_edges()
	if s == "":
		return LOCAL_SERVER
	if s.begins_with("https://"):
		return "wss://" + s.substr(8)
	if s.begins_with("http://"):
		return "ws://" + s.substr(7)
	if not (s.begins_with("ws://") or s.begins_with("wss://")):
		return "ws://" + s
	return s


# --- Profile -----------------------------------------------------------------

func save_profile() -> void:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))


func _load_profile() -> void:
	profile = _read(PROFILE_PATH)
	if str(profile.get("id", "")) == "":
		# A private id so the region knows which city is yours when you come back.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		profile.id = "%08x%08x" % [rng.randi(), rng.randi()]
		save_profile()
	for k in ["name", "server", "code"]:
		profile[k] = str(profile.get(k, ""))
	# Login tokens by server, invite code and name.
	if typeof(profile.get("tokens")) != TYPE_DICTIONARY:
		profile.tokens = {}


func _migrate_old_save() -> void:
	if FileAccess.file_exists(OLD_SAVE) and list_saves().is_empty():
		var data := _read(OLD_SAVE)
		if not data.is_empty():
			data["meta"] = {"name": "My Town", "saved": int(Time.get_unix_time_from_system())}
			var f := FileAccess.open(new_save_path("My Town"), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(data))
				f.close()
				DirAccess.remove_absolute(OLD_SAVE)


func _read_page_invite() -> void:
	if not OS.has_feature("web"):
		return
	var query = JavaScriptBridge.eval("window.location.search", true)
	if typeof(query) != TYPE_STRING or query == "":
		return
	for part in str(query).trim_prefix("?").split("&"):
		var kv := part.split("=", true, 1)
		if kv.size() == 2 and kv[0] in ["join", "server"]:
			pending_invite[kv[0]] = kv[1].uri_decode()


## Puts the invite code in the page's address once you're in, so a refresh
## brings you straight back to your town instead of the title screen.
func _keep_page_invite(code: String) -> void:
	if not OS.has_feature("web"):
		return
	var query := "?join=" + code.uri_encode()
	var server = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
	if typeof(server) == TYPE_STRING and server != "":
		query += "&server=" + str(server).uri_encode()
	JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + %s)" % JSON.stringify(query))


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}
