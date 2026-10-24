extends SceneTree
## Headless tests for the real-world land: godot --headless -s tests/test_terrain.gd

var _failed := 0
## A line north from town across the water (the Mississinewa's lake arm).
const RIVER_X := -1500.0
const RIVER_FROM := -10000
const RIVER_TO := -13000


func _init() -> void:
	var h := Terrain.height(0, 0)
	_check(h > 200.0 and h < 320.0, "the town starts on real Indiana ground (%.1f m)" % h)
	_check(Terrain.buildable(0, 0, 20), "the town starts on dry, buildable land")
	# The town starts at Sweetser's crossroads, which is the region's 0, and
	# Mississinewa Lake's upper arm lies about seven miles north of it.
	var wet := false
	for z in range(RIVER_FROM, RIVER_TO, -20):
		wet = wet or Terrain.is_water(RIVER_X, z)
	_check(wet, "the Mississinewa is north of town")
	var marion: Dictionary = Backdrop.cities()[0]
	_check(marion.name == "Marion" and not Terrain.buildable(marion.centre.x, marion.centre.y),
		"Marion, the backdrop city, can't be built on")
	_check(Backdrop.sites()[0].name == "Sweetser" and Backdrop.sites()[0].centre.length() < 800.0,
		"the first start site is Sweetser, at the region's 0")
	# Relief: Grant County's till plain, gently rolling, not dead flat and
	# not hills.
	var lo := INF
	var hi := -INF
	for k in 400:
		var y := Terrain.height(-5000.0 + (k % 20) * 500.0, -5000.0 + (k / 20) * 500.0)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	_check(hi - lo > 10.0 and hi - lo < 150.0, "rolling land: %d m from lowest to highest" % (hi - lo))
	# The map never ends: past the edge it mirrors, with no jump.
	var e := Terrain.CENTRE.x + Terrain.SIZE * 0.5
	_check(absf(Terrain.height(e - 1.0, 300) - Terrain.height(e + 1.0, 300)) < 1.0, "no seam at the map's edge")
	_check(Terrain.height(e + 5000.0, 0) > 0.0, "land goes on past the real area")
	# Bridges: the base level stands clear above water.
	var bridged := true
	for z in range(RIVER_FROM, RIVER_TO, -20):
		if Terrain.is_water(RIVER_X, z) and Terrain.water(RIVER_X, z) > 0.9:
			bridged = bridged and Terrain.base(RIVER_X, z) > Terrain.water_level(RIVER_X, z) + 4.0
	_check(bridged, "roads over the river stand on bridge decks")
	# Resources come from the real land and stay 0 to 1.
	var seen := [0.0, 0.0, 0.0, 0.0]
	for k in 900:
		var p := Vector3(-12000.0 + (k % 30) * 800.0, 0, -12000.0 + (k / 30) * 800.0)
		for kind in 4:
			var v := Resources.at(kind, p)
			_check(v >= 0.0 and v <= 1.0, "resources stay 0 to 1") if k == 0 else null
			seen[kind] = maxf(seen[kind], v)
	for kind in 4:
		_check(seen[kind] > 0.6, "%s turns up on the map" % Resources.NAMES[kind])
	var river := Vector3.ZERO
	for z in range(RIVER_FROM, RIVER_TO, -20):
		if Terrain.is_water(RIVER_X, z):
			river = Vector3(RIVER_X, 0, z)
			break
	_check(Resources.fertility(river) == 0.0, "no farming in the river")
	# The sim keeps building off the water.
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	_check(not sim.land_ok(river), "the river is not buildable")
	_check(sim.land_ok(Vector3.ZERO, 10.0), "the town site is buildable")
	# Grading a road flattens the ground under it.
	var line := PackedVector3Array([Vector3(-200, 0, 0), Vector3(200, 0, 0)])
	Terrain.stamp_flat(line, 10.0, 20.0)
	_check(is_equal_approx(Terrain.ground_y(0, 0), Terrain.base_y(0, 0)), "ground under a road is graded to the road")
	Terrain.clear_flat(Rect2(-300, -100, 600, 200))
	_check(Terrain.flat_weight(0, 0) == 0.0, "grading clears")
	# The mouse ray finds the hills.
	var hit = Terrain.ray_hit(Vector3(0, 600, 300), Vector3(0, -1, -0.5))
	_check(hit != null and absf(hit.y - Terrain.ground_y(hit.x, hit.z)) < 0.5, "the mouse ray lands on the ground")
	# Chunks build with water where the river is.
	var any_water := false
	for z in range(-6, 0):
		var meshes := TerrainView.build_chunk(Vector2(RIVER_X - 256.0, RIVER_TO + 512.0 + z * 512.0 + 3072.0), 512.0, 32.0)
		any_water = any_water or meshes[1] != null
	_check(any_water, "the river gets a water surface")
	# Each vertex knows where it sits on the next coarser level, so detail can
	# slide off with distance instead of popping: on the coarse grid points it
	# is the same height, and halfway along a coarse edge it is the average.
	var fine: ArrayMesh = TerrainView.build_chunk(Vector2(-512, -512), 512.0, 8.0)[0]
	var arr := fine.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var low: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var row := 65
	var same := true
	var halfway := true
	for j in range(0, 64, 2):
		for i in range(0, 64, 2):
			var k := j * row + i
			same = same and absf(low[k * 4] - v[k].y) < 0.01
			halfway = halfway and absf(low[(k + 1) * 4] - (v[k].y + v[k + 2].y) * 0.5) < 0.01
	_check(same and halfway, "ground detail slides smoothly to the coarser level")
	# Water lies flat in every square, even on the coarse levels where a
	# square reaches from the water up onto dry land (it once tilted 22 m).
	var tilt := 0.0
	for cz in range(-6, 2):
		for cx in range(2, 8):
			var wm = TerrainView.build_chunk(Vector2(cx, cz) * 512.0, 512.0, 128.0, 0.0)[1]
			if wm == null:
				continue
			var wa: Array = (wm as ArrayMesh).surface_get_arrays(0)
			var wv: PackedVector3Array = wa[Mesh.ARRAY_VERTEX]
			var wi: PackedInt32Array = wa[Mesh.ARRAY_INDEX]
			for t in range(0, wi.size(), 3):
				var ys := [wv[wi[t]].y, wv[wi[t + 1]].y, wv[wi[t + 2]].y]
				tilt = maxf(tilt, ys.max() - ys.min())
	_check(tilt < 0.01, "water lies flat on every level of detail")
	# The land runs on past the chunks, out to where the haze takes it.
	var job := TerrainView.far_job(Vector2.ZERO, ceili(TerrainView.FAR_REACH / TerrainView.CHUNK))
	while not TerrainView.far_step(job):
		pass
	var box: AABB = job.mesh.get_aabb()
	_check(box.position.x <= -TerrainView.FAR_REACH and box.end.z >= TerrainView.FAR_REACH,
		"the land goes on to the haze, past the detailed chunks")
	_check(TerrainView.REACH[-1] * TerrainView.FAR_CUT < TerrainView.REACH[-1] and TerrainView.FAR_REACH < 24000.0,
		"the far land starts inside the chunks and ends inside the camera's view")
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
