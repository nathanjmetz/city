extends "res://tools/screenshot.gd"
## Faint straight lines over grass and roads (Nathan, 2026-10-25): a picture
## of the bare land from the air, with the sun's shadow settings overridable
## from the environment. After the picture it switches the sun's shadows off
## and takes the same frame again; over open grass the two should differ
## only by real shadows (trees, poles), so what is left in the patches (the
## mean difference, in 1/1000 of full brightness, and the share of pixels
## that moved by more than 1/255) is shadow acne.
## Run in a real window (not --headless), for the browser's renderer too:
##   godot --rendering-driver opengl3 --rendering-method gl_compatibility --resolution 1600x900 \
##     -s tools/ground_lines_shot.gd -- out.png yaw pitch dist land lookx lookz
## Environment (all optional): LINES_BIAS (sun.shadow_bias), LINES_NORMAL (sun.shadow_normal_bias),
##   LINES_GROUND_CAST (1: the land casts shadows as before the fix; 0: none), LINES_HOUR (clock, day/night on),
##   LINES_MONTH (1-12), LINES_PATCHES ("x,y,w,h;x,y,w,h" in pixels).
## Prints "ACNE <patch values>" (lower is cleaner) and saves out.png and out_off.png.

const SHOT := 90

var _patches := [Rect2i(1000, 150, 250, 150), Rect2i(1180, 160, 200, 100)]
var _on: Image
var _sky: SkyLight


## "perftown" as the fifth argument: the test town (PerfTown, the same every
## run) instead of bare land, aimed at its homes.
func _demo_town() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 5 and args[4] == "perftown":
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, "big")
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(Vector3(-430.0, 0.0, -330.0))
				c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
			if c is CanvasLayer:
				c.visible = false
		return
	super()


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_demo_town()
	if _frames == 3:
		_main.speed = 0
		var month := float(OS.get_environment("LINES_MONTH")) if OS.get_environment("LINES_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("LINES_HOUR")) if OS.get_environment("LINES_HOUR") != "" else 11.0
		DayNight.cycle_on = OS.get_environment("LINES_HOUR") != ""
		_main.sim.tick_count = Seasons.tick_at(SkyClock.at(int(month), hour)) - _main.sim.calendar_offset
		if OS.get_environment("LINES_PATCHES") != "":
			_patches = []
			for p in OS.get_environment("LINES_PATCHES").split(";"):
				var v := p.split(",")
				_patches.append(Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3])))
	if _frames == 10:
		_sky = _main.find_children("*", "SkyLight", true, false)[0]
		if OS.get_environment("LINES_BIAS") != "":
			_sky.sun.shadow_bias = float(OS.get_environment("LINES_BIAS"))
		if OS.get_environment("LINES_NORMAL") != "":
			_sky.sun.shadow_normal_bias = float(OS.get_environment("LINES_NORMAL"))
		print("sun bias ", _sky.sun.shadow_bias, " normal ", _sky.sun.shadow_normal_bias, " blur ", _sky.sun.shadow_blur,
			" splits ", _sky.sun.directional_shadow_mode, " reach ", _sky.sun.directional_shadow_max_distance,
			" sun rot ", _sky.sun.rotation_degrees, " method ", RenderingServer.get_current_rendering_method())
	if _frames >= 11 and _frames < SHOT and OS.get_environment("LINES_GROUND_CAST") != "":
		# 1: the land casts shadows nearer than the coarse levels, as it did
		# before the fix; 0: it casts none.
		var on := OS.get_environment("LINES_GROUND_CAST") == "1"
		for v in _main.find_children("*", "TerrainView", true, false):
			for k in v._chunks:
				var e: Dictionary = v._chunks[k]
				e.ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on and e.lod <= 1 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _frames == SHOT:
		_on = root.get_viewport().get_texture().get_image()
		_sky.sun.shadow_enabled = false
	if _frames == SHOT + 6:
		var off := root.get_viewport().get_texture().get_image()
		var out: String = OS.get_cmdline_user_args()[0]
		_on.save_png(out)
		off.save_png(out.replace(".png", "_off.png"))
		_measure(_on, off)
		quit()
	return false


func _measure(on: Image, off: Image) -> void:
	on.convert(Image.FORMAT_RGB8)
	off.convert(Image.FORMAT_RGB8)
	# Switching shadows off also moves the brightness of the whole frame, so
	# only the fine part of the difference counts.
	var blur_on := on.duplicate()
	var blur_off := off.duplicate()
	for b: Image in [blur_on, blur_off]:
		b.resize(on.get_width() / 12, on.get_height() / 12, Image.INTERPOLATE_BILINEAR)
		b.resize(on.get_width(), on.get_height(), Image.INTERPOLATE_BILINEAR)
	# The same difference over the whole picture, stretched 20 times, grey where
	# the shadows changed nothing: lines in it are shadow acne.
	var map := Image.create(on.get_width(), on.get_height(), false, Image.FORMAT_RGB8)
	for y in on.get_height():
		for x in on.get_width():
			var v: float = ((on.get_pixel(x, y).g - off.get_pixel(x, y).g) - (blur_on.get_pixel(x, y).g - blur_off.get_pixel(x, y).g)) * 20.0 + 0.5
			map.set_pixel(x, y, Color(v, v, v))
	map.save_png((OS.get_cmdline_user_args()[0] as String).replace(".png", "_acne.png"))
	var parts := []
	for r in _patches:
		var sum := 0.0
		var moved := 0
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var a: Color = on.get_pixel(x, y)
				var b: Color = off.get_pixel(x, y)
				var d := absf((a.g - b.g) - (blur_on.get_pixel(x, y).g - blur_off.get_pixel(x, y).g))
				sum += d
				if d > 1.0 / 255.0:
					moved += 1
		var n: int = r.size.x * r.size.y
		parts.append([snappedf(sum / n * 1000.0, 0.01), snappedf(float(moved) / n, 0.001)])
	print("ACNE ", parts)
