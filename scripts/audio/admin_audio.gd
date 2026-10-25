extends Node
## The way into the admin Sound mixer: Ctrl+Shift+F12 (Cmd+Shift+F12 on a
## Mac), desktop app only. The browser build never listens. There is no
## sign-in and no password: it can only change this computer's sound mix.

var _mixer: SoundMixer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not SoundMixer.available():
		set_process_input(false)


func _input(e: InputEvent) -> void:
	if not SoundMixer.is_hotkey(e):
		return
	if _mixer == null:
		_mixer = SoundMixer.new()
		add_child(_mixer)
	_mixer.toggle()
	get_viewport().set_input_as_handled()
