extends SceneTree
## Saves frames of the loading screen at a few progress points.
## Run: godot -s tools/loading_shot.gd -- out_dir [frames]

var _ls: LoadingScreen
var _frame := 0
var _out := "."
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "."
	_frames = int(args[1]) if args.size() > 1 else 0
	_ls = LoadingScreen.open("Pouring foundations")


func _process(_delta: float) -> bool:
	_frame += 1
	# Fake a load: steps of real-looking progress over ~6 seconds at 60 fps.
	var p := clampf(_frame / 360.0, 0.0, 1.0)
	var labels := ["Pouring foundations", "Paving roads", "Building homes", "Planting trees", "Waking up the neighbors"]
	LoadingScreen.progress(snappedf(p, 0.07), labels[mini(int(p * labels.size()), labels.size() - 1)])
	if _frame == 380:
		LoadingScreen.close()
	if _frames > 0:
		if _frame % 3 == 0 and _frame <= _frames:
			root.get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [_out, _frame / 3])
	elif _frame in [20, 130, 250, 395]:
		root.get_viewport().get_texture().get_image().save_png("%s/p%d.png" % [_out, _frame])
	if _frame > maxi(_frames, 460):
		quit()
	return false
