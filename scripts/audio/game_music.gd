class_name GameMusic
extends RefCounted
## Brawn's own music (made in Suno), on the Music bus so the Audio page's
## Music slider sets it. The theme song plays on the title screen and in the
## pause menu; in town a playlist of gameplay songs plays in shuffled order,
## resting between songs so the town's own sounds come through (like CS2's
## radio). Opening the pause menu swaps in the theme, and closing it picks
## the town song up where it left off.
##
## Adding a gameplay song: drop an .ogg into assets/audio/music/gameplay/.
## Nothing else to change; the playlist is whatever is in that folder.

const THEME := "res://assets/audio/music/theme.ogg"
const GAMEPLAY_DIR := "res://assets/audio/music/gameplay"
const NODE := "GameMusic"
const VOLUME_DB := -8.0
## Quiet between songs in town, in seconds.
const REST := 60.0
const FADE := 2.0

enum Mode { MENU, TOWN }


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


## Switches to the menu theme or the town playlist. Safe to call again:
## the same mode keeps the song that is playing.
static func play(tree: SceneTree, mode: Mode) -> void:
	SoundSettings.apply()
	var p := tree.root.get_node_or_null(NODE) as AudioStreamPlayer
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = NODE
		p.bus = "Music"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.set_meta("mode", -1)
		p.finished.connect(func(): _finished(p))
		tree.root.add_child.call_deferred(p)
		p.ready.connect(func(): _switch(p, mode), CONNECT_ONE_SHOT)
		return
	if p.is_inside_tree():
		_switch(p, mode)
	else:
		p.set_meta("want", mode)


static func _switch(p: AudioStreamPlayer, mode: int) -> void:
	mode = int(p.get_meta("want", mode))
	p.remove_meta("want")
	if int(p.get_meta("mode")) == mode:
		return
	# Leaving town: remember the song and where it was, to pick it up again.
	if int(p.get_meta("mode")) == Mode.TOWN and p.playing:
		p.set_meta("town_song", p.stream.resource_path)
		p.set_meta("town_at", p.get_playback_position())
	p.set_meta("mode", mode)
	p.set_meta("gen", int(p.get_meta("gen", 0)) + 1)
	if mode == Mode.MENU:
		_start(p, THEME, 0.0)
	elif p.has_meta("town_song"):
		_start(p, p.get_meta("town_song"), float(p.get_meta("town_at")))
		p.remove_meta("town_song")
	else:
		_next(p)


static func _start(p: AudioStreamPlayer, path: String, at: float) -> void:
	var stream = load(path)
	if stream == null:
		p.stop()
		return
	p.stream = stream
	p.volume_db = -40.0
	p.play(at)
	p.create_tween().tween_property(p, "volume_db", VOLUME_DB, FADE)


## The next gameplay song: shuffled, never the same one twice in a row.
static func _next(p: AudioStreamPlayer) -> void:
	var songs := playlist()
	if songs.is_empty():
		p.stop()
		return
	var queue: Array = p.get_meta("queue", [])
	if queue.is_empty():
		queue = songs.duplicate()
		queue.shuffle()
		if queue.size() > 1 and queue[0] == p.get_meta("last", ""):
			queue.reverse()
	var song: String = queue.pop_front()
	p.set_meta("queue", queue)
	p.set_meta("last", song)
	_start(p, song, 0.0)


static func _finished(p: AudioStreamPlayer) -> void:
	var gen := int(p.get_meta("gen", 0))
	var town := int(p.get_meta("mode")) == Mode.TOWN
	p.get_tree().create_timer(REST if town else 2.0).timeout.connect(func():
		# Only if nothing switched the music meanwhile.
		if not is_instance_valid(p) or p.playing or int(p.get_meta("gen", 0)) != gen:
			return
		if town:
			_next(p)
		else:
			_start(p, THEME, 0.0))
