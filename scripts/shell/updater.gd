class_name GameUpdater
extends Node
## Keeps the desktop app up to date with no installer and no admin rights.
## An autoload (Updater), first in the list so it can act before anything
## else of the game loads.
##
## Each launch it asks the "desktop" release on GitHub for latest.json. When
## that build is newer, it downloads only the game data pack (a few MB, into
## the player's own user folder) and checks its fingerprint. Every launch
## after that mounts the newest pack over the app's own data before the
## rest of the game loads, so scripts, scenes and art all come from it. On
## the title screen it restarts right away so the update shows at once.
##
## A pack can't change the app's project settings (they're read before any
## script runs), apart from shader globals, which are added by hand. So when
## project.godot itself changes, or the engine does, the menu points to the
## download page for a fresh app instead. (Official engine builds refuse
## --main-pack, so mounting the pack is the way that works everywhere.)
##
## The browser build updates by reloading the page, so this does nothing
## there, nor in the editor, headless servers or unstamped local builds.

## Says what the updater is doing, for a line in the main menu.
signal status(text: String)

const MANIFEST := "https://github.com/nathanjmetz/city/releases/download/desktop/latest.json"
const DOWNLOAD_PAGE := "https://nathanjmetz.github.io/city/download/"
const DIR := "user://updates"
const STATE := "user://updates/state.json"
const BUILD_INFO := "res://scripts/build_info.gd"
const APP_KEY := "updater/runtime/app"
const MOUNTED_KEY := "updater/runtime/mounted"
## A downloaded pack that doesn't get the game to the title screen this many
## times in a row is dropped, so a bad download can never stop it opening.
const MAX_TRIES := 2
const GLOBAL_TYPES := {"bool": RenderingServer.GLOBAL_VAR_TYPE_BOOL, "int": RenderingServer.GLOBAL_VAR_TYPE_INT,
	"float": RenderingServer.GLOBAL_VAR_TYPE_FLOAT, "vec2": RenderingServer.GLOBAL_VAR_TYPE_VEC2,
	"vec3": RenderingServer.GLOBAL_VAR_TYPE_VEC3, "vec4": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
	"color": RenderingServer.GLOBAL_VAR_TYPE_COLOR}

var active := false
## The newest build needs a new app (a different engine or project
## settings): see DOWNLOAD_PAGE.
var new_app := false
## A downloaded pack waiting for a restart.
var ready_pack := ""
## The pack mounted at launch, if any.
var mounted := ""
var last_status := ""
## The autoload, for class scripts (null in tests and tools).
static var current: GameUpdater

var _http: HTTPRequest
var _manifest := {}
var _restart_when_ready := false


func _init() -> void:
	current = self
	if OS.has_feature("web") or not OS.has_feature("template") or DisplayServer.get_name() == "headless" \
			or "--no-update" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		return
	var app := _build_info()
	if int(app.get("BUILT", 0)) == 0:
		return
	# Mounting a pack can reload this very script, which resets its
	# variables, so what _ready needs is kept in project settings.
	ProjectSettings.set_setting(APP_KEY, {"built": int(app.BUILT), "settings": str(app.get("SETTINGS", ""))})
	DirAccess.make_dir_recursive_absolute(DIR)
	var st := _read()
	var pack := str(st.get("pack", ""))
	if pack == "":
		return
	if FileAccess.file_exists(pack) and _fits(st) and int(st.get("built", 0)) > int(app.BUILT) \
			and int(st.get("tries", 0)) < MAX_TRIES:
		st.tries = int(st.get("tries", 0)) + 1
		_write(st)
		if ProjectSettings.load_resource_pack(pack, true):
			ProjectSettings.set_setting(MOUNTED_KEY, pack)
			_add_globals(st.get("globals", {}))
			return
	# The app itself is as new (a fresh download), or the pack is bad.
	DirAccess.remove_absolute(pack)
	DirAccess.remove_absolute(STATE)


func _ready() -> void:
	current = self
	if not ProjectSettings.has_setting(APP_KEY):
		return
	active = true
	mounted = str(ProjectSettings.get_setting(MOUNTED_KEY, ""))
	_tidy()
	if mounted != "":
		# It got this far: count the pack as good once the title screen is up.
		get_tree().create_timer(10.0).timeout.connect(func():
			var st := _read()
			if str(st.get("pack", "")) == mounted:
				st.tries = 0
				_write(st))
	check()


## The build this game is running: Unix time it was made (0 when unstamped).
static func built() -> int:
	return int(_build_info().get("BUILT", 0))


static func engine() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]


## Which build of the game data the release has for this computer.
static func platform() -> String:
	return "macos" if OS.has_feature("macos") else "windows" if OS.has_feature("windows") else "linux"


## Asks the release what the newest build is, and fetches it if it's newer.
func check(restart_when_ready := false) -> void:
	if not active:
		return
	_restart_when_ready = _restart_when_ready or restart_when_ready
	if ready_pack != "":
		if _restart_when_ready:
			restart()
		return
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	var url := OS.get_environment("NEIGHBORS_MANIFEST")  # for testing the updater
	if url == "":
		url = MANIFEST
	# A query string so no cache in between serves an old copy.
	if _http.request(url + "?t=%d" % Time.get_unix_time_from_system()) != OK:
		_done()


## Opens the game again, which mounts the downloaded pack on the way up.
func restart() -> void:
	if OS.create_instance(PackedStringArray()) <= 0:
		return
	# Out of the way at once; the new window takes over in a moment.
	get_window().mode = Window.MODE_MINIMIZED
	get_tree().quit()


## The region turned us away for running another version: update now and
## come back on the newest build.
func on_version_mismatch() -> void:
	_say("Updating to match the region...")
	check(true)


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_done()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var m = JSON.parse_string(body.get_string_from_utf8())
	if typeof(m) != TYPE_DICTIONARY:
		return
	_manifest = m
	var newest := maxi(built(), int(_read().get("built", 0)))
	if int(m.get("built", 0)) <= newest:
		_restart_when_ready = false
		return
	if not _fits(m):
		new_app = true
		_say("A new version of the app is out.")
		return
	var pack: Dictionary = m.get("packs", {}).get(platform(), {})
	if str(pack.get("url", "")) == "":
		return
	_say("Downloading the newest version...")
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	# Off the main thread and in big pieces, so the menu stays smooth and a
	# few MB arrive in seconds.
	_http.use_threads = true
	_http.download_chunk_size = 1 << 20
	_http.download_file = DIR.path_join("download.part")
	add_child(_http)
	_http.request_completed.connect(_on_pack.bind(pack))
	if _http.request(str(pack.url)) != OK:
		_done()


func _on_pack(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, pack: Dictionary) -> void:
	var part := _http.download_file
	_done()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or FileAccess.get_sha256(part) != str(pack.get("sha256", "")):
		DirAccess.remove_absolute(part)
		_say("")
		return
	var path := DIR.path_join("game-%s.pck" % str(_manifest.get("commit", "new")).left(10))
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(part, path) != OK:
		return
	_write({"pack": path, "built": int(_manifest.built), "commit": str(_manifest.get("commit", "")),
		"engine": str(_manifest.engine), "settings": str(_manifest.get("settings", "")),
		"globals": _manifest.get("globals", {}), "tries": 0})
	ready_pack = path
	_say("Updated. It'll be ready next time you open Neighbors.")
	# On the title screen nothing is lost by restarting now.
	if _restart_when_ready or _on_title_screen():
		_say("Updating...")
		restart.call_deferred()


## Whether a build (a manifest or a downloaded pack's state) can run inside
## this app: the same engine and the same project settings.
func _fits(build: Dictionary) -> bool:
	var app: Dictionary = ProjectSettings.get_setting(APP_KEY, {})
	return str(build.get("engine", "")) == engine() and str(build.get("settings", "")) == str(app.get("settings", ""))


## Shader globals the pack's art uses that this app's settings don't have yet.
func _add_globals(globals) -> void:
	if typeof(globals) != TYPE_DICTIONARY:
		return
	for name in globals:
		var g = globals[name]
		if ProjectSettings.has_setting("shader_globals/" + name) or typeof(g) != TYPE_DICTIONARY or not GLOBAL_TYPES.has(str(g.get("type", ""))):
			continue
		RenderingServer.global_shader_parameter_add(name, GLOBAL_TYPES[g.type], str_to_var(str(g.get("value", "0"))))


func _on_title_screen() -> bool:
	var scene := get_tree().current_scene
	# By path: this script is compiled before autoload names exist in tests.
	var session := get_node_or_null("/root/Session")
	return scene != null and scene.scene_file_path == "res://scenes/menu.tscn" \
		and session != null and session.client == null and session.host == null


## Removes packs left over from earlier updates.
func _tidy() -> void:
	var keep := str(_read().get("pack", ""))
	for f in DirAccess.get_files_at(DIR):
		var path := DIR.path_join(f)
		if f.ends_with(".pck") and path != keep and path != mounted:
			DirAccess.remove_absolute(path)


func _done() -> void:
	if _http:
		_http.queue_free()
		_http = null


func _say(text: String) -> void:
	last_status = text
	status.emit(text)


## The stamped build (BUILD, COMMIT, BUILT, SETTINGS), read fresh each time:
## a copy cached before the pack was mounted would be the app's own.
static func _build_info() -> Dictionary:
	if not ResourceLoader.exists(BUILD_INFO):
		return {}
	var s := ResourceLoader.load(BUILD_INFO, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	return s.get_script_constant_map() if s else {}


static func _read() -> Dictionary:
	if not FileAccess.file_exists(STATE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(STATE))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _write(st: Dictionary) -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(st))
