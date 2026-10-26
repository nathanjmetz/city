extends "res://tools/screenshot.gd"
## Flies the camera low and forward over the woods and in over the demo
## town's edge, as a player holding the move key does, and saves a frame
## every half second: to look for trees popping in, swelling up out of the
## ground, blank land in the distance, and trees flickering between their
## drawn versions (compare each frame with the next).
## Run (a real window, not --headless):
##   godot --resolution 1280x720 -s tools/tree_lod_shot.gd -- OUT_DIR [--quality=low] [compare]
## Prints frame time and draw calls over the flight, for the budget.
## SHOT_MONTH=5.5 (in the environment) pins the season: mid-July here.
## NO_FAR=1 draws the far woods no further than the cards need (to see
## what they cost).

## Where the flight starts and ends (view metres), the view (yaw, pitch,
## distance behind the point looked at) and how long it lasts (s).
const FROM := Vector3(-2600.0, 0.0, 2100.0)
const TO := Vector3(-60.0, 0.0, -40.0)
const PITCH := 11.0
const DIST := 110.0
const SECONDS := 24.0
const EVERY := 0.5
const COMPARE_AT := 0.25

var _cam: CityCamera
var _t := -1.0
var _next_shot := 0.0
var _shot := 0
var _settle := 0
var _ms := []
var _calls := []
var _prims := []
var _still := -1  # frames since the camera was parked, after the flight
var _grown_off := 0
var _zone_off := 0
var _since_shot := 0
var _still_ms := []
var _still_calls := []
var _still_prims := []
var _out := "."
var _last_us := 0
var _just_saved := false


func _process(delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "."
		DirAccess.make_dir_recursive_absolute(_out)
		_demo_town()
		if OS.get_environment("NO_FAR") != "":
			GraphicsQuality.budget["far_woods"] = 1.0
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		_main.set_speed(0)
		_place(0.0)
		return false
	if _cam == null:
		return false
	if _t < 0.0:
		# Let the woods round the start lay out before flying.
		_settle += 1
		_place(0.0)
		if _settle > 240:
			_t = 0.0
			_last_us = Time.get_ticks_usec()
			# Frame time as the machine can draw it, not held to the screen's.
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		return false
	if "compare" in OS.get_cmdline_user_args():
		return _compare()
	# Real time between frames (the frame's whole cost, drawing included).
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_us) / 1000.0
	_last_us = now
	if _still >= 0:
		return _hold(frame_ms)
	_t += delta
	var k := clampf(_t / SECONDS, 0.0, 1.0)
	_place(k)
	# (Not the frame after a picture is saved: saving takes a while.)
	if _t > 0.25 and not _just_saved:
		_ms.append(frame_ms)
		_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		# Frames the grown trees were all handed back to cards (their lookup
		# lagged the camera): each one a flicker of every tree near by.
		if TreeLook.radii().y > 0.0 and TreeLook._cam.w < 0.5:
			_grown_off += 1
		# Frames the grown trees' hand-over rings were off the camera by
		# more than 10 m (trailing a lagging lookup, then catching up in a
		# jump: a ring of trees switching at once). Not just after a
		# picture, when the camera has jumped on.
		var zc := Vector3(TreeLook._cam.x, TreeLook._cam.y, TreeLook._cam.z)
		if TreeLook._cam.w > 0.5 and _since_shot > 2 and zc.distance_to(_cam.camera.global_position) > 10.0:
			_zone_off += 1
		_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_just_saved = _t >= _next_shot
	_since_shot += 1
	if _just_saved:
		_since_shot = 0
		_next_shot += EVERY
		var path := _out.path_join("fly_%02d.png" % _shot)
		root.get_viewport().get_texture().get_image().save_png(path)
		_shot += 1
	if k >= 1.0:
		_report()
		_still = 0
	return false


## After the flight: the camera parked over the woods (a quarter of the way
## along), and once the land and trees round it are laid out, the cost of
## drawing it, with nothing streaming in. Then it turns once round the spot
## it looks at, as a player orbits a view, a picture every 30 frames
## (orbit_XX.png): turning must not change how any tree is drawn.
func _hold(frame_ms: float) -> bool:
	_still += 1
	if _still > 480:
		var i := _still - 480
		_place(COMPARE_AT, TAU * i / 480.0)
		if i % 30 == 0:
			root.get_viewport().get_texture().get_image().save_png(_out.path_join("orbit_%02d.png" % (i / 30)))
		if i >= 480:
			quit()
		return false
	_place(COMPARE_AT)
	if _still > 240:
		_still_ms.append(frame_ms)
		_still_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_still_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _still == 480:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("still.png"))
		print("still: frame ms avg %.2f; draw calls avg %d; primitives avg %d" % [_avg(_still_ms), int(_avg(_still_calls)),
			int(_avg(_still_prims))])
		for c in _main.get_children():
			if c is WildView and c.get("far") != null:
				print("still: far woods %d trees in %d chunks" % [c.far.tree_count(), c.far.chunks().size()])
	return false


## `compare`: the camera parked a quarter of the way along, one picture with
## the woods as the tier draws them and one with the cards' reach cut to a
## quarter, so the same trees 200-700 m off are drawn by the far woods: to
## match their size and colour at the hand-over.
var _cmp := 0


func _compare() -> bool:
	_cmp += 1
	_place(COMPARE_AT)
	if _cmp == 60:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("cmp_cards.png"))
		GraphicsQuality.budget["woods"] = 0.25
	if _cmp == 180:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("cmp_far.png"))
		quit()
	return false


## The camera at a share of the way along the flight, facing along it.
func _place(k: float, turn := 0.0) -> void:
	var dir := (TO - FROM).normalized()
	var p := FROM.lerp(TO, k)
	# CityCamera's yaw 0 looks along -z from +z; face the way of travel.
	var yaw := atan2(-dir.x, -dir.z) + turn
	_cam.look_at_point(p)
	_cam.set_view(yaw, deg_to_rad(PITCH), DIST)


static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(a.size(), 1.0)


func _report() -> void:
	var ms: Array = _ms.duplicate()
	ms.sort()
	var calls: Array = _calls.duplicate()
	calls.sort()
	var avg := 0.0
	for m in _ms:
		avg += m
	avg /= maxf(_ms.size(), 1.0)
	var pavg := 0.0
	for p in _prims:
		pavg += p
	pavg /= maxf(_prims.size(), 1.0)
	print("flight: %d frames, frame ms avg %.2f p95 %.2f max %.2f; draw calls median %d max %d; primitives avg %d" % [
		_ms.size(), avg, ms[int(ms.size() * 0.95)], ms[-1], calls[calls.size() / 2], calls[-1], int(pavg)])
	print("flight: grown trees all turned back to cards in %d frames; their hand-over rings 10 m or more off the camera in %d" % [
		_grown_off, _zone_off])
	print("renderer: ", RenderingServer.get_current_rendering_method(), "  quality: ", GraphicsQuality.detail)
