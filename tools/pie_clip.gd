extends SceneTree
## Frames of the Roads pie opening, a flick round to Grid, and the pick, for a
## short clip. Run (with a window): godot -s tools/pie_clip.gd -- out_dir
## then: ffmpeg -framerate 30 -i out_dir/f%03d.png clip.gif

var _frames := 0
var _out := "pie_frames"
var _hud: Hud
var _shot := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Pie Clip")
	change_scene_to_file("res://scenes/main.tscn")


func _move(d: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _hud.pie._origin + d
	_hud.pie._input(m)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_hud = get_first_node_in_group("pad_hud")
		Engine.time_scale = 1.0
		_hud.pie.open("Roads", _hud.pie_items("roads"), Vector2.ZERO, KEY_NONE)
	if _frames < 30:
		return false
	var f := _frames - 30
	# Sweep the pointer round from the top to Grid, pausing on a few.
	if f >= 14 and f < 60:
		var a := lerpf(-0.6, TAU * 0.125 + TAU, float(f - 14) / 46.0)
		_move(Vector2(sin(a), -cos(a)) * 120.0)
	elif f == 60:
		_move(Vector2(sin(TAU * 0.125), -cos(TAU * 0.125)) * 120.0)
	elif f == 74:
		_hud.pie._choose(1)
	if f >= 0:
		root.get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [_out, _shot])
		_shot += 1
	if f >= 90:
		quit()
	return false
