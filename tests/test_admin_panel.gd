extends SceneTree
## Run: godot --headless -s tests/test_admin_panel.gd
## The host's Admin button: hidden (and shut) for everyone but the host; for
## the host it lists each player with their PIN, the people waiting to get
## in (and opens itself when someone asks), and opens the Sound mixer. The
## region chat no longer carries the players list.

var _failed := false


func _init() -> void:
	# Never touch this computer's real sound mix.
	SoundMix.blank()
	SoundSettings.info("ui/click")
	SoundSettings.save_path = "user://test_admin_mix_settings.json"
	SoundMix.persist = false
	SoundMix.use_local = false
	await process_frame
	var client := RegionClient.new()
	root.add_child(client)

	# A player who isn't the host never sees it, and it won't open for them.
	client.is_host = false
	client.pins = [{"name": "Nathan", "pin": "123456", "host": true}]
	var admin := AdminPanel.new()
	admin.setup(client)
	root.add_child(admin)
	var button := admin.make_button()
	root.add_child(button)
	await process_frame
	_check(not button.visible, "the Admin button is hidden from a player who isn't the host")
	admin.set_open(true)
	_check(not admin.is_open(), "Admin won't open for a player who isn't the host")
	_check(_labels(admin).all(func(t): return not t.contains("123 456")), "no PIN is shown to them")

	# The host (the server says so) sees the button and every player's PIN.
	client.is_host = true
	client.pins = [{"name": "Nathan", "pin": "123456", "host": true},
		{"name": "Sam", "pin": "654321", "host": false}, {"name": "Ada", "pin": "", "host": false}]
	client.pins_changed.emit()
	await process_frame
	_check(button.visible, "the host sees the Admin button")
	admin.set_open(true)
	await process_frame
	_check(admin.is_open() and button.button_pressed, "the host's Admin button opens the panel")
	var words := _labels(admin)
	_check(words.has("Nathan  (you)") and words.has("123 456"), "the host is listed, marked as you, with their PIN")
	_check(words.has("Sam") and words.has("654 321"), "a player is listed with their PIN")
	_check(words.has("Ada") and words.has("no PIN"), "a removed player shows no PIN")
	var buttons := _buttons(admin)
	_check(buttons.count("Remove") == 1 and buttons.count("New PIN") == 1, "players can be removed or given a new PIN, but not the host")
	_check(buttons.has("Add player"), "there is a line to add a player")
	_check(buttons.has("Open"), "the Sound mixer has an Open button in the desktop app")
	_check(AdminPanel.pin_message("Sam", "654321").contains("654321") and AdminPanel.pin_message("Sam", "654321").contains("https://"),
		"the copied message has the link and the PIN")

	# Someone asks to join: Admin opens on its own with a yes and a no.
	admin.set_open(false)
	client.requests = ["Lee"]
	client.requests_changed.emit()
	await process_frame
	_check(admin.is_open(), "a join request opens Admin")
	_check(_labels(admin).has("Lee") and _buttons(admin).has("Let in"), "the request shows with Let in")
	admin.set_open(false)
	client.requests_changed.emit()
	await process_frame
	_check(not admin.is_open(), "closing Admin while Lee waits sticks when the list comes again")
	client.requests = ["Lee", "Kim"]
	client.requests_changed.emit()
	await process_frame
	_check(admin.is_open(), "someone new asking opens it again")
	client.requests = []
	client.requests_changed.emit()
	await process_frame
	_check(not _labels(admin).has("Lee"), "an answered request goes away")

	# Escape closes it.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	_check(not admin.is_open() and not button.button_pressed, "Escape closes Admin")

	# Open in Admin opens the Sound mixer (and closes Admin).
	admin.set_open(true)
	var open_btn: Button = _find_button(admin, "Open")
	open_btn.pressed.emit()
	await process_frame
	var mixer: SoundMixer = null
	for c in root.get_node("AdminAudio").get_children():
		if c is SoundMixer:
			mixer = c
	_check(mixer != null and mixer.is_open(), "Open shows the Sound mixer")
	_check(not admin.is_open(), "Admin steps aside for the mixer")
	if mixer:
		mixer.close()

	# Losing host (the server says otherwise) hides and shuts it.
	admin.set_open(true)
	client.is_host = false
	client.pins_changed.emit()
	await process_frame
	_check(not button.visible and not admin.is_open() and not button.button_pressed, "no longer host: the button goes and the panel shuts")
	client.is_host = true
	client.joined.emit()
	await process_frame
	_check(button.visible, "host again after a reconnect: the button comes back")

	# The chat keeps chatting, without the players list.
	var chat_src := FileAccess.get_file_as_string("res://scripts/ui/chat_panel.gd")
	_check(not chat_src.contains("_players_button") and not chat_src.contains("pin_message"), "the region chat no longer carries players and PINs")

	client.queue_free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _labels(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Label", true, false):
		if c.is_visible_in_tree():
			out.append((c as Label).text)
	return out


func _buttons(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Button", true, false):
		if c.is_visible_in_tree():
			out.append((c as Button).text)
	return out


func _find_button(n: Node, text: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).text == text:
			return c
	return null


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
