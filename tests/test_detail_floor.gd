extends SceneTree
## Run: godot --headless -s tests/test_detail_floor.gd
## The detail floor (docs/detail-floor.md): every look has a closest camera
## distance, measured from screenshots, and the camera never goes nearer,
## by any route (zoom, glide, follow, a set view) and also when the look
## changes mid-game (it eases out, it does not jump).

var _fails := 0


func _initialize() -> void:
	# The table: one entry per tier, dated, with a reason, never closer than
	# the camera's own limit, and a better look never needs to stand further out.
	var table := GraphicsQuality.DETAIL_FLOOR
	_check(table.size() == GraphicsQuality.NAMES.size(), "the table has an entry for every tier (%d of %d)" % [table.size(), GraphicsQuality.NAMES.size()])
	var last := INF
	for t in table.size():
		var e: Dictionary = table[t]
		var name: String = GraphicsQuality.NAMES[t]
		_check(float(e.get("dist", 0.0)) >= CityCamera.MIN_DIST, "%s: floor %.0f m is not under the camera's own %.0f m" % [name, float(e.get("dist", 0.0)), CityCamera.MIN_DIST])
		_check(float(e.get("dist", 0.0)) <= last, "%s: no further out than the tier below it" % name)
		last = float(e.get("dist", 0.0))
		_check(str(e.get("date", "")).length() == 10 and str(e.get("date", "")).count("-") == 2, "%s: has a date (%s)" % [name, e.get("date", "")])
		_check(str(e.get("why", "")).strip_edges().length() > 12, "%s: names the weakest thing" % name)

	var q := GraphicsQuality.new()
	GraphicsQuality.current = q
	for t in GraphicsQuality.NAMES.size():
		q.tier = t
		var floor_m := GraphicsQuality.detail_floor(t)
		var name: String = GraphicsQuality.NAMES[t]
		var cam := CityCamera.new()
		_check(is_equal_approx(cam.floor_dist(), floor_m), "%s: the camera reads its floor (%.0f m)" % [name, floor_m])

		# A set view closer than the floor lands on the floor.
		cam.set_view(0.5, 0.8, 5.0)
		_check(cam._dist >= floor_m and cam._goal_dist >= floor_m, "%s: a set view can't start under the floor" % name)

		# Spinning the wheel in, holding the zoom keys, a trigger pull.
		cam._goal_dist = floor_m * 3.0
		for i in 120:
			cam.wheel_click(-1.0)
			cam._zoom_glide(1.0 / 60.0)
			cam._hold_floor(1.0 / 60.0)
		_check(cam._goal_dist >= floor_m - 0.001, "%s: wheel zoom stops at the floor (%.2f m)" % [name, cam._goal_dist])
		for i in 120:
			cam._zoom_rate(-4.5, 1.0 / 60.0)
		_check(cam._goal_dist >= floor_m - 0.001, "%s: held zoom stops at the floor (%.2f m)" % [name, cam._goal_dist])
		cam._zoom(0.01)
		_check(cam._goal_dist >= floor_m - 0.001, "%s: a pinch stops at the floor (%.2f m)" % [name, cam._goal_dist])

		# Glides and following keep outside it too.
		cam.glide_to(Vector3(10, 0, 10), 5.0)
		_check(cam._goal_dist >= floor_m, "%s: a glide can't end under the floor" % name)
		cam._goal_dist = floor_m * 4.0
		cam.follow_point(Vector3(1, 0, 1))
		_check(cam._goal_dist >= floor_m, "%s: following a car can't pull under the floor" % name)
		cam.free()

	# The look drops while the camera is right at the High floor: the camera
	# eases out to the Low floor in steps, never a jump and never under it.
	q.tier = GraphicsQuality.CINEMATIC
	var cam := CityCamera.new()
	cam.set_view(0.5, 0.8, 1.0)
	var near := cam._goal_dist
	_check(is_equal_approx(near, GraphicsQuality.detail_floor(GraphicsQuality.CINEMATIC)), "starts on the Cinematic floor (%.1f m)" % near)
	q.tier = GraphicsQuality.LOW
	var want := GraphicsQuality.detail_floor(GraphicsQuality.LOW)
	var biggest := 0.0
	var prev := cam._goal_dist
	var frames := 0
	while frames < 600 and cam._goal_dist < want:
		cam._hold_floor(1.0 / 60.0)
		biggest = maxf(biggest, cam._goal_dist - prev)
		prev = cam._goal_dist
		frames += 1
	if want > near + 0.1:
		_check(cam._goal_dist >= want and frames > 5, "dropping to Low eases the camera out to %.0f m (%d frames)" % [want, frames])
		_check(biggest < (want - near) * 0.5, "and not in one jump (largest step %.1f m of %.1f)" % [biggest, want - near])
	else:
		_check(true, "Low and Cinematic share a floor today, so nothing to ease")
	cam.free()
	GraphicsQuality.current = null
	q.free()
	print("detail floor: %s" % ("ok" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
