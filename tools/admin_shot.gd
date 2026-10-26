extends SceneTree
## A picture of the host's Admin panel open in a town, for checking the look.
## Run (in a window): godot -s tools/admin_shot.gd -- out.png
## Made-up players and PINs; no server, nothing sent anywhere.

var _main: Node
var _frames := 0
var _admin: AdminPanel


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "admin.png"
	if _frames == 400:
		var hud: Hud
		for c in _main.get_children():
			if c is Hud:
				hud = c
		var client := RegionClient.new()
		root.add_child(client)
		client.is_host = true
		client.pins = [{"name": "Nathan", "pin": "482913", "host": true},
			{"name": "Sam", "pin": "305871", "host": false},
			{"name": "Ada", "pin": "", "host": false}]
		_admin = AdminPanel.new()
		_admin.setup(client)
		_main.add_child(_admin)
		hud.add_top_button(_admin.make_button())
	if _frames == 420:
		_admin.client.requests = ["Lee"]
		_admin.client.requests_changed.emit()
	if _frames == 460:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
