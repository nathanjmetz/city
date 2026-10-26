extends Node
## The way into the admin Sound mixer: the host's Admin button, or
## Ctrl+Shift+F12 (Cmd+Shift+F12 on a Mac), desktop app only. The browser build never listens. There is no
## sign-in and no password: it can only change this computer's sound mix.

var _mixer: SoundMixer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not SoundMixer.available():
		set_process_input(false)


func _input(e: InputEvent) -> void:
	if not SoundMixer.is_hotkey(e):
		return
	_ensure_mixer().toggle()
	get_viewport().set_input_as_handled()


## Opens the mixer: the host's Admin panel (AdminPanel) has a button for it.
func open_mixer() -> void:
	if SoundMixer.available():
		_ensure_mixer().open()


func _ensure_mixer() -> SoundMixer:
	if _mixer == null:
		_mixer = SoundMixer.new()
		add_child(_mixer)
	return _mixer
