extends SceneTree
## A picture of the admin Sound mixer, for checking the look.
## Run (in a window): godot -s tools/sound_mixer_shot.gd -- out.png [loud] [width height]
## Uses made-up meter readings and changes nothing on disk.

var _frames := 0
var _out := "mixer.png"
var _loud := false
var _panel: SoundMixer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "mixer.png"
	_loud = args.size() > 1 and args[1] == "loud"
	SoundMix.blank()
	SoundMix.persist = false
	SoundMix.use_local = false
	SoundSettings.info("ui/click")
	SoundSettings.save_path = "user://shot_audio.json"
	SoundMix.reread()
	_panel = SoundMixer.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frames += 1
	# Made-up readings: a loud car roar, birds, a click now and then.
	SoundMix.report("world/car_engine", 0.5)
	SoundMix.report("world/car_engine", 0.35)
	SoundMix.report("world/car_engine", 0.2)
	SoundMix.report("world/birds_day", 0.12)
	SoundMix.report("world/birds_day", 0.05)
	SoundMix.report("world/industry_hum", 0.22)
	SoundMix.report("world/leaves", 0.03)
	SoundMix.report("world/wind_high", 0.09)
	if _frames == 5:
		_panel.open()
		SoundMix.set_sound("world/car_engine", "db", -4.5)
		SoundMix.set_sound("world/car_engine", "cap", 5)
		SoundMix.set_group("nature", 3.0)
		SoundMix.set_sound("world/leaves", "mute", true)
		_panel._sync()
		_panel._rows["world/car_engine"].tune_btn.button_pressed = true
		_panel._rows["world/birds_day"].tune_btn.button_pressed = true
		if _loud:
			_panel._show_tab("loud")
	if _frames == 40:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
