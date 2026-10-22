extends "res://tools/screenshot.gd"
## Turns the camera a little each frame and counts pixels that flip back and
## forth between three frames (shimmer), as opposed to edges that just move.
## Run: godot -s tools/flicker_test.gd -- out_prefix yaw pitch dist town x z [variant] [motion]
##   variant: normal | noshadow | fixed (shadow range pinned)
##   motion: turn | zoom | tilt

var _cam: CityCamera
var _shots := []


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var variant := args[7] if args.size() > 7 else "normal"
	var motion := args[8] if args.size() > 8 else "turn"
	if _frames == 2:
		_demo_town()
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		if variant.contains("msaa4"):
			root.msaa_3d = Viewport.MSAA_4X
		if variant.contains("msaa8"):
			root.msaa_3d = Viewport.MSAA_8X
		if variant.contains("fxaa"):
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_main.set_speed(0)  # hold traffic still, so only the camera moves
		for sky in _main.find_children("*", "SkyLight", true, false):
			if variant == "noshadow":
				sky.sun.shadow_enabled = false
			if variant == "fixed":
				sky.set_process(false)
				sky.sun.directional_shadow_max_distance = 500.0
	if _frames > 40 and _cam:
		var t := _frames - 40
		var yaw := float(args[1]) + (t * 0.05 if motion == "turn" else 0.0)
		var pitch := float(args[2]) + (t * 0.03 if motion == "tilt" else 0.0)
		var dist := float(args[3]) * (1.0 + (t * 0.002 if motion == "zoom" else 0.0))
		_cam.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
	if _frames >= 70 and _frames <= 72:
		_shots.append(root.get_viewport().get_texture().get_image())
	if _frames == 73:
		for i in 3:
			_shots[i].save_png("%s_%d.png" % [args[0], i])
		print("saved ", args[0])
		quit()
	return false
