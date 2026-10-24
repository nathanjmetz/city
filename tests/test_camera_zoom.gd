extends SceneTree
## Run: godot --headless -s tests/test_camera_zoom.gd
## Zoom with momentum: a gentle click moves a little and settles, a hard spin
## of the wheel runs out fast, up close is finer, and the speed is capped.

var _fails := 0


func _initialize() -> void:
	var cam := CityCamera.new()

	# One slow click at 260 m: a small glide, finer than the old 12% step.
	cam._goal_dist = 260.0
	cam.wheel_click(1.0)
	_run(cam, 1.0)
	var one := cam._goal_dist / 260.0
	_check(one > 1.05 and one < 1.0 / 0.88, "one click zooms out a little (x%.3f)" % one)
	_check(cam._zoom_vel == 0.0, "the glide settles by itself")

	# The glide carries on after the click: momentum.
	cam._goal_dist = 260.0
	cam._zoom_heat = 0.0
	cam.wheel_click(1.0)
	_run(cam, 1.0 / 60.0)
	var first_frame := cam._goal_dist
	_run(cam, 0.3)
	_check(cam._goal_dist > first_frame * 1.02, "the view keeps gliding after the click")

	# Slow clicks, one every half second, stay gentle: ten of them.
	cam._goal_dist = 260.0
	cam._zoom_heat = 0.0
	cam._zoom_vel = 0.0
	for i in 10:
		cam.wheel_click(1.0)
		_run(cam, 0.5)
	var slow := cam._goal_dist / 260.0
	# A hard spin: the same ten clicks inside a third of a second.
	cam._goal_dist = 260.0
	cam._zoom_heat = 0.0
	cam._zoom_vel = 0.0
	for i in 10:
		cam.wheel_click(1.0)
		_run(cam, 1.0 / 30.0)
	_run(cam, 1.5)
	var fast := cam._goal_dist / 260.0
	_check(log(fast) > log(slow) * 1.4, "a hard spin goes much further than slow clicks (x%.1f vs x%.1f)" % [fast, slow])

	# Muscle: a long hard spin from street level reaches the top in about two seconds.
	cam._goal_dist = CityCamera.MIN_DIST
	cam._zoom_heat = 0.0
	cam._zoom_vel = 0.0
	var t := 0.0
	while t < 2.2 and cam._goal_dist < CityCamera.MAX_DIST:
		cam.wheel_click(1.0)
		_run(cam, 1.0 / 30.0)
		t += 1.0 / 30.0
	_check(cam._goal_dist >= CityCamera.MAX_DIST * 0.99, "spinning hard runs all the way out (%.1f s)" % t)
	_check(t > 1.0, "but no faster than the redraw cap (%.1f s)" % t)
	_check(absf(cam._zoom_vel) <= CityCamera.ZOOM_MAX_RATE, "zoom speed stays under the cap")

	# Up close a click moves less than up high.
	cam._goal_dist = 30.0
	cam._zoom_heat = 0.0
	cam._zoom_vel = 0.0
	cam.wheel_click(-1.0)
	_run(cam, 1.0)
	var near := 30.0 / cam._goal_dist
	cam._goal_dist = 800.0
	cam._zoom_heat = 0.0
	cam.wheel_click(-1.0)
	_run(cam, 1.0)
	var far := 800.0 / cam._goal_dist
	_check(near - 1.0 < (far - 1.0) * 0.7, "a click up close is finer (x%.3f vs x%.3f)" % [near, far])

	# Turning the wheel back stops the glide at once.
	cam._goal_dist = 260.0
	cam._zoom_heat = 0.0
	for i in 5:
		cam.wheel_click(1.0)
	cam.wheel_click(-1.0)
	_check(cam._zoom_vel == 0.0, "a click the other way catches the view")

	# Triggers: a light squeeze creeps, a full pull is several times faster.
	cam._goal_dist = 260.0
	cam._zoom_rate(-(0.6 * 0.3 + 1.7 * 0.027), 1.0)
	var light := 260.0 / cam._goal_dist
	cam._goal_dist = 260.0
	cam._zoom_rate(-2.3, 1.0)
	var full := 260.0 / cam._goal_dist
	_check(light < 1.3 and full > 5.0, "trigger pressure sets the speed (x%.2f vs x%.1f a second)" % [light, full])

	cam.free()
	print("camera zoom: %s" % ("ok" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)


func _run(cam: CityCamera, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		var dt := minf(1.0 / 60.0, seconds - t)
		cam._zoom_glide(dt)
		t += dt


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
