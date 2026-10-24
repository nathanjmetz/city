class_name GameMusic
extends Node
## Brawn's own music (made in Suno), on the Music bus so the Audio page's
## Music slider sets it. The theme song plays on the title screen, from the
## very start when the game opens. In town a playlist of gameplay songs
## plays in shuffled order, resting between songs so the town's own sounds
## come through (like CS2's radio); the music player in the top bar
## (MusicPlayer) shows the song and can skip it or pick another, and every
## skip is sent with the play notes. Opening the pause menu fades over to the
## middle of the theme, and closing it fades back to the town song where it
## left off.
##
## Adding a gameplay song: drop an .ogg into assets/audio/music/gameplay/,
## named for how it feels (porch_swing.ogg plays as "Porch Swing"). Nothing
## else to change; the playlist is whatever is in that folder.

const THEME := "res://assets/audio/music/theme.ogg"
const THEME_TITLE := "Neighbors (theme)"
const GAMEPLAY_DIR := "res://assets/audio/music/gameplay"
const NODE := "GameMusic"
const VOLUME_DB := -8.0
## Quiet between songs in town, in seconds.
const REST := 60.0
const FADE := 2.0
## Opening the menu again starts the theme somewhere in here (share of its length).
const THEME_MIDDLE := Vector2(0.25, 0.6)

enum Mode { MENU, TOWN }

## A town song was skipped: what the play notes get (see _note_skip).
signal skipped(info: Dictionary)

var mode := -1
## The player playing now, and the one fading out (two, to cross-fade).
var player: AudioStreamPlayer
var _other: AudioStreamPlayer
var _theme_heard := false
var _town_song := ""
var _town_at := 0.0
var _queue := []
var _last := ""
## Seconds until the next town song, while resting between songs (else 0).
var rest_left := 0.0
var _want := -1


## Every gameplay song, sorted. In an exported game the folder lists
## "name.ogg.import" or ".remap", so those endings are taken off.
static func playlist() -> Array:
	var out := []
	for f in DirAccess.get_files_at(GAMEPLAY_DIR):
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name.ends_with(".ogg") and not out.has(name):
			out.append(name)
	out.sort()
	return out.map(func(n): return GAMEPLAY_DIR + "/" + n)


## A song's name: "porch_swing.ogg" is "Porch Swing".
static func title(path: String) -> String:
	if path == THEME:
		return THEME_TITLE
	var words := Array(path.get_file().get_basename().split("_"))
	for i in words.size():
		words[i] = words[i] if i > 0 and words[i] in ["a", "at", "in", "of", "on", "the", "and"] else words[i].capitalize()
	return " ".join(words)


## The music, made the first time it's needed.
static func get_music(tree: SceneTree) -> GameMusic:
	var m := tree.root.get_node_or_null(NODE) as GameMusic
	if m == null:
		m = GameMusic.new()
		m.name = NODE
		tree.root.add_child.call_deferred(m)
	return m


## Switches to the menu theme or the town playlist. Safe to call again:
## the same mode keeps the song that is playing.
static func play(tree: SceneTree, to: Mode) -> void:
	SoundSettings.apply()
	var m := get_music(tree)
	if m.is_inside_tree():
		m.switch(to)
	else:
		m._want = to  # it plays once it's in the tree


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		p.finished.connect(func(): _finished(p))
		add_child(p)
	player = get_child(0)
	_other = get_child(1)


func _ready() -> void:
	if _want != -1:
		switch(_want)
		_want = -1


func switch(to: int) -> void:
	if to == mode:
		return
	# Leaving town: remember the song and where it was, to pick it up again.
	if mode == Mode.TOWN and player.playing and player.stream:
		_town_song = player.stream.resource_path
		_town_at = player.get_playback_position()
	mode = to
	rest_left = 0.0
	if to == Mode.MENU:
		# From the very start the first time; after that, somewhere in the middle.
		var at := 0.0
		var theme := load(THEME) as AudioStream
		if _theme_heard and theme:
			at = theme.get_length() * randf_range(THEME_MIDDLE.x, THEME_MIDDLE.y)
		_theme_heard = true
		_start(THEME, at)
	elif _town_song != "":
		_start(_town_song, _town_at)
		_town_song = ""
	else:
		next()


## The song playing (or resting before), or "" if none.
func song() -> String:
	return player.stream.resource_path if player.stream and (player.playing or rest_left > 0.0) else ""


## Skips the town song: on to the next one now, and the skip goes in the play
## notes (`how`: "skip", or "pick" when another song was chosen).
func skip(how := "skip") -> void:
	if mode != Mode.TOWN:
		return
	_note_skip(how)
	next()


## Plays `path` now (from the music player's list).
func choose(path: String) -> void:
	if mode != Mode.TOWN or (path == song() and player.playing):
		return
	_note_skip("pick", path)
	_queue.erase(path)
	_last = path
	_start(path, 0.0)


func _note_skip(how: String, to := "") -> void:
	if not player.playing or player.stream == null:
		return
	var path := player.stream.resource_path
	var info := {"song": title(path), "file": path.get_file(), "how": how,
		"at": snappedf(player.get_playback_position(), 0.1), "length": snappedf(player.stream.get_length(), 0.1),
		"to": title(to) if to != "" else ""}
	skipped.emit(info)
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.event("music_skip", info)


## The next gameplay song: shuffled, never the same one twice in a row.
func next() -> void:
	rest_left = 0.0
	var songs := playlist()
	if songs.is_empty():
		_fade_out(player)
		return
	_queue = _queue.filter(func(s): return s in songs)
	if _queue.is_empty():
		_queue = songs.duplicate()
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _last:
			_queue.reverse()
	_last = _queue.pop_front()
	_start(_last, 0.0)


## Cross-fades from what's playing to `path`, from `at` seconds in.
func _start(path: String, at: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		_fade_out(player)
		return
	var old := player
	player = _other
	_other = old
	_fade_out(old)
	player.stream = stream
	player.volume_db = -40.0
	player.play(at)
	_tween(player, VOLUME_DB)


func _fade_out(p: AudioStreamPlayer) -> void:
	if not p.playing:
		return
	_tween(p, -60.0).tween_callback(func():
		if p != player:
			p.stop())


func _tween(p: AudioStreamPlayer, db: float) -> Tween:
	if p.has_meta("tween") and is_instance_valid(p.get_meta("tween")):
		(p.get_meta("tween") as Tween).kill()
	var t := p.create_tween()
	t.tween_property(p, "volume_db", db, FADE)
	p.set_meta("tween", t)
	return t


func _process(delta: float) -> void:
	if rest_left <= 0.0:
		return
	rest_left -= delta
	if rest_left <= 0.0:
		if mode == Mode.TOWN:
			next()
		else:
			rest_left = 0.0


func _finished(p: AudioStreamPlayer) -> void:
	if p != player:
		return
	if mode == Mode.TOWN:
		rest_left = REST
	else:
		get_tree().create_timer(2.0).timeout.connect(func():
			if mode == Mode.MENU and not player.playing:
				_start(THEME, 0.0))
