class_name UiSounds
extends Node
## Interface sounds in the "Front Porch" style: wooden mallets and a plucked
## guitar (built by tools/audio/make_assets.py). Plays on the UI bus.
## If several sounds are asked for in one frame, only the most important one
## plays, so picking a tool does not also play a button click.

const PRIORITY := {"click": 0, "brush": 0, "tool": 1, "road": 2, "build": 2, "bulldoze": 2,
	"money": 3, "milestone": 4}
const VOLUME := {"click": -8.0, "brush": -20.0, "tool": -6.0, "road": -5.0, "build": -4.0,
	"bulldoze": -5.0, "money": -6.0, "milestone": -3.0}
## Zone painting asks for a sound on every stroke; space them out.
const BRUSH_GAP := 0.12

var sim: CitySim
var _streams := {}
var _players := []
var _next := 0
var _pending := ""
var _brush_wait := 0.0
var _milestone := 0
var _picks := -1


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	CityAudio.setup_buses()
	_load_streams()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_players.append(p)
	sim.command_applied.connect(_on_command)
	_milestone = sim.economy.milestone
	sim.stats_changed.connect(_on_stats)
	# Every button in the game clicks, including ones made later.
	get_tree().node_added.connect(_hook)
	_hook_all(get_tree().root)


## The recordings, again after a pick in the Sound picker.
func _load_streams() -> void:
	_picks = SoundSettings.picks_version
	for name in ["click", "tool", "road", "build", "bulldoze", "money", "milestone"]:
		_streams[name] = SoundSettings.stream("ui/" + name)
	_streams.brush = _streams.click


func play(name: String) -> void:
	if _pending == "" or PRIORITY.get(name, 0) > PRIORITY.get(_pending, 0):
		_pending = name


func _process(delta: float) -> void:
	_brush_wait -= delta
	if _pending == "":
		return
	var name := _pending
	_pending = ""
	if _picks != SoundSettings.picks_version:
		_load_streams()
	if name == "brush":
		if _brush_wait > 0.0:
			return
		_brush_wait = BRUSH_GAP
	if SoundSettings.is_flagged("ui/" + _file(name)):
		return
	SoundSettings.heard("ui/" + _file(name), db_to_linear(VOLUME.get(name, -6.0)))
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = VOLUME.get(name, -6.0)
	p.pitch_scale = randf_range(0.97, 1.03) if name in ["click", "brush", "road", "bulldoze"] else 1.0
	p.play()


## The file a sound plays: zone painting uses the click.
static func _file(name: String) -> String:
	return "click" if name == "brush" else name


func _hook_all(n: Node) -> void:
	_hook(n)
	for c in n.get_children():
		_hook_all(c)


func _hook(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_on_button):
		(n as BaseButton).pressed.connect(_on_button)


func _on_button() -> void:
	play("click")


func _on_command(cmd: Dictionary) -> void:
	match cmd.get("type", ""):
		"build_road", "build_grid", "build_roundabout", "upgrade_road":
			play("road")
		"place_service", "place_farmhouse", "place_warehouse", "place_park":
			play("build")
		"remove_road", "remove_farm", "remove_service", "remove_warehouse", "remove_park":
			play("bulldoze")
		"paint_plan":
			play("brush" if str(cmd.get("kind", "")) != "" else "bulldoze")
		"paint_reserve", "paint_farmland":
			var on: bool = str(cmd.get("kind", "farm" if bool(cmd.get("on", true)) else "")) != ""
			play("road" if on else "bulldoze")
		"paint_zone":
			play("brush")
		"set_junction":
			play("click")


func _on_stats() -> void:
	if sim.economy.milestone > _milestone:
		play("milestone")
		get_tree().create_timer(0.55).timeout.connect(func(): play("money"))
	_milestone = sim.economy.milestone
