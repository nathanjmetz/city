extends "res://tools/screenshot.gd"
## The countryside critic's views: the farm demo (screenshot.gd "farms") in
## July at 11 am, with no panels, from a field, a pond, a woods edge and
## the open county, a creek and the railroad, near and far, saved as OUT_DIR/<view>.png in one run.
## Run: xvfb-run godot --rendering-driver vulkan --resolution 1600x900 -s tools/countryside_shot.gd -- OUT_DIR 0 0 0 farms [view ...] --quality=ultra
## Env: LOOK_MONTH (1-12, default 7), LOOK_HOUR (default 11), VIEW_FRAMES (frames each view settles, default 30).

## [name, what to look at, yaw, pitch, distance]
const VIEWS := [
	["field_close", "field", 30.0, 22.0, 60.0],
	["field_mid", "field", 30.0, 35.0, 250.0],
	["pond_close", "pond", 200.0, 25.0, 80.0],
	["pond_mid", "pond", 200.0, 35.0, 260.0],
	["woods_close", "woods", 120.0, 18.0, 70.0],
	["woods_mid", "woods", 120.0, 30.0, 300.0],
	["county_wide", "field", 30.0, 30.0, 1300.0],
	["horizon", "field", 30.0, 9.0, 450.0],
	["rail_close", "rail", 60.0, 16.0, 60.0],
	["rail_mid", "rail", 60.0, 30.0, 260.0],
	["rail_low", "rail", 75.0, 9.0, 30.0],
	["creek_close", "creek", 150.0, 22.0, 70.0],
	["woods_floor", "woods_in", 120.0, 38.0, 32.0],
	["prop_close", "prop", 140.0, 30.0, 9.0],
	["river_mid", "river", 200.0, 28.0, 220.0],
	["river_close", "river", 160.0, 40.0, 90.0],
	["river_wide", "river", 200.0, 45.0, 900.0],
	["pits_wide", "pits", 200.0, 45.0, 900.0],
	["river_low", "river", 250.0, 12.0, 45.0],
	["bare_mid", "bare", 200.0, 35.0, 250.0],
	["bare_close", "bare", 200.0, 22.0, 70.0],
	["pile_close", "prop", 120.0, 18.0, 45.0],
]

var _view := -1
var _view_frames := 0
var _cam: CityCamera
var _aims := {}
var _views: Array = []


func _process(delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		DayNight.cycle_on = false
		var month := float(OS.get_environment("LOOK_MONTH")) if OS.get_environment("LOOK_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("LOOK_HOUR")) if OS.get_environment("LOOK_HOUR") != "" else 11.0
		_demo_town()
		var sim: CitySim = _main.sim
		sim.set_calendar(Seasons.tick_at(SkyClock.at(int(month), hour)))
		_main.speed = 0
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is Hud:
				c.close_all()  # and the Fertility view the farms open with
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		_find_aims()
		var args := OS.get_cmdline_user_args()
		var only := Array(args.slice(5)).filter(func(a): return not a.begins_with("--"))
		for v in VIEWS:
			if only.is_empty() or v[0] in only:
				_views.append(v)
		return false
	if _frames < 150:
		return false
	if _view < 0:
		_next()
		return false
	_view_frames += 1
	if _view_frames == (int(OS.get_environment("VIEW_FRAMES")) if OS.get_environment("VIEW_FRAMES") != "" else 30):
		var out: String = OS.get_cmdline_user_args()[0].path_join(_views[_view][0] + ".png")
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out, "  draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"  primitives ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"  props ", _props())
		_next()
	return false


## Scanned props drawn near the camera (CountryProps), for the log.
func _props() -> String:
	var by := {}
	for c in _main.get_children():
		if c is CountryProps:
			for mi in c.get_children():
				var mm := (mi as MultiMeshInstance3D).multimesh
				var k := mm.mesh.resource_name if mm.mesh.resource_name != "" else str(mm.mesh.get_aabb().size.round())
				by[k] = by.get(k, 0) + mm.instance_count
	return str(by)


## Where the first scanned prop near the camera lies (the woods if none).
func _prop_spot() -> Vector3:
	# PROP_ID picks a scan by its mesh name (e.g. nettle), else the first.
	var want := OS.get_environment("PROP_ID")
	for c in _main.get_children():
		if c is CountryProps:
			for mi in c.get_children():
				var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
				if want != "" and not want in String((mi as Node).name):
					continue
				if mm.instance_count > 0:
					return (mi as Node3D).position + mm.get_instance_transform(0).origin
	return _aims.woods


func _next() -> void:
	_view += 1
	_view_frames = 0
	if _view >= _views.size():
		quit()
		return
	var v: Array = _views[_view]
	if v[1] == "prop":
		_aims.prop = _prop_spot()
	_cam.look_at_point(_aims[v[1]])
	_cam.set_view(deg_to_rad(v[2]), deg_to_rad(v[3]), v[4])


## The field is the demo's corn; the pond and the woods edge are the
## nearest real ones (region data) to the demo farms.
func _find_aims() -> void:
	_aims.field = Vector3(-420, 0, 380)
	var o := Terrain.view_origin
	var best_w := INF
	var best_t := INF
	_aims.pond = Vector3(-250, 0, 400)
	_aims.woods = Vector3(-500, 0, 100)
	_aims.woods_in = Vector3(-500, 0, 50)
	for x in range(-4000, 4001, 40):
		for z in range(-4000, 4001, 40):
			var d := Vector2(x + 250, z - 200).length()
			# Off the demo's painted farmland, which covers the land round it.
			if absf(x) < 900.0 and absf(z) < 700.0:
				continue
			if d < best_w and Terrain.water(x + o.x, z + o.y) > 0.6:
				best_w = d
				_aims.pond = Vector3(x, 0, z)
			# A woods edge: deep woods here, open ground 40 m south.
			if d < best_t and Terrain.trees(x + o.x, z + o.y) > 0.7 and Terrain.trees(x + o.x, z + 40 + o.y) < 0.2 \
					and Terrain.water(x + o.x, z + 40 + o.y) < 0.1:
				best_t = d
				_aims.woods = Vector3(x, 0, z + 20)
				# 30 m into the woods from that edge: the woods floor.
				_aims.woods_in = Vector3(x, 0, z - 30)
	# A creek: a thin wet line, not a pond (pond water reads 0.6 and up).
	_aims.creek = _aims.pond
	var best_c := INF
	for x in range(-4000, 4001, 20):
		for z in range(-4000, 4001, 20):
			var w := Terrain.water(x + o.x, z + o.y)
			var d := Vector2(x + 250, z - 200).length()
			if d < best_c and w > 0.25 and w < 0.6 and not (absf(x) < 900.0 and absf(z) < 700.0):
				best_c = d
				_aims.creek = Vector3(x, 0, z)
	# The Mississinewa: one 18 m cell of open water wide in the cover data,
	# too thin to find by scanning. Region (3030, -6750) is on it, north of
	# Marion, wooded both banks; the wettest point near there.
	_aims.river = Vector3(3030, 0, -6750)
	var best_v := 0.0
	for x in range(2950, 3111, 6):
		for z in range(-6830, -6669, 6):
			var wv := Terrain.water(x + o.x, z + o.y)
			if wv > best_v:
				best_v = wv
				_aims.river = Vector3(x, 0, z)
	# Flooded gravel pits west of Sweetser: square lakes with berms.
	_aims.pits = Vector3(-3500, 0, 600)
	# Bare worked ground beside those pits (WorldCover bare): the active
	# face of a sand and gravel pit.
	_aims.bare = Vector3(-3381, 0, -513)
	# The railroad: the point of the county's track nearest the demo
	# farms, off a crossing or bridge.
	_aims.rail = _aims.field
	var best_r := INF
	for r in CountyRail.all().size():
		var prof := CountyRail.profile(r)
		for i in prof.at.size():
			var q: Vector2 = prof.at[i] - o
			var d := Vector2(q.x + 250, q.y - 200).length()
			if d < best_r and prof.kind[i] == 0 and not (absf(q.x) < 900.0 and absf(q.y) < 700.0):
				best_r = d
				_aims.rail = Vector3(q.x, 0, q.y)
	print("aims ", _aims)
