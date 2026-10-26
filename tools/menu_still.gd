extends SceneTree
## Takes the home screen's pictures (MenuStill): the menu's town from its
## camera where it starts, without the menu, at the Marion time each look is
## taken at, in clear weather, once it's all drawn. One look a run, in a
## real window 2.4 times as wide as it is high, on the browser's renderer:
##   godot --resolution 1920x800 --rendering-driver opengl3 --rendering-method gl_compatibility \
##     -s tools/menu_still.gd -- --look=summer --quality=high
## (looks: summer, autumn, bare, snow, night). Saves
## assets/menu/still_<look>.jpg, WIDTH pixels wide: it sits behind the
## menu's fade for a few seconds, so soft is fine and small matters (the
## browser downloads it).

const WIDTH := 1152
const QUALITY := 0.7
## Seconds to let the near trees and detail settle once the town is drawn.
const SETTLE_S := 3.0

var _menu: Node
var _look := "summer"
var _drawn_at := -1.0
var _time := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			_look = a.trim_prefix("--look=")
	if not MenuStill.TAKEN_AT.has(_look):
		push_error("no look %s (%s)" % [_look, ", ".join(MenuStill.LOOKS)])
		quit(1)
		return
	Weather.on = false
	_menu = load("res://scenes/menu.tscn").instantiate()
	_menu._forced = MenuStill.TAKEN_AT[_look]
	_menu.hold_camera = true
	root.add_child(_menu)
	current_scene = _menu


func _process(delta: float) -> bool:
	_time += delta
	if _menu == null:
		return false
	for c in _menu.get_children():
		if c is CanvasLayer and not c is BackdropReveal:
			c.visible = false
	var covered := false
	for c in _menu.get_children():
		if c is BackdropReveal:
			covered = true
	if not covered and _drawn_at < 0.0 and _time > 1.0:
		_drawn_at = _time
		print("drawn after %.1f s" % _time)
	if _drawn_at >= 0.0 and _time - _drawn_at > SETTLE_S:
		var image := root.get_viewport().get_texture().get_image()
		var h := int(round(WIDTH / MenuStill.ASPECT))
		if absf(float(image.get_width()) / image.get_height() - MenuStill.ASPECT) > 0.05:
			push_warning("window is %dx%d, not %.1f:1" % [image.get_width(), image.get_height(), MenuStill.ASPECT])
		image.resize(WIDTH, h, Image.INTERPOLATE_LANCZOS)
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			push_warning("taken on the desktop renderer: the pictures are meant to be the browser's")
		var out := ProjectSettings.globalize_path(MenuStill.path(_look))
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		image.save_jpg(out, QUALITY)
		print("saved %s (%d KB)" % [out, FileAccess.get_file_as_bytes(out).size() / 1024])
		quit()
	if _time > 60.0:
		push_error("not drawn after 60 s")
		quit(1)
	return false
