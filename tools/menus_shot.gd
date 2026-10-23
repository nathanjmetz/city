extends SceneTree
## Pictures of each bottom bar menu, to check they stay compact.
## Run: godot -s tools/menus_shot.gd -- out_prefix

const CATS := ["roads", "industry", "utilities", "civic", "education", "health", "transport", "parks"]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "menu"
	var hud: Hud
	for c in _main.get_children():
		if c is Hud:
			hud = c
	var i := _frames / 20 - 1
	if _frames % 20 == 0 and i < CATS.size():
		hud.close_all()
		hud._open(CATS[i])
	if _frames % 20 == 10 and i >= 0 and i < CATS.size():
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, CATS[i]])
		print("saved ", CATS[i])
	if i >= CATS.size():
		quit()
	return false
