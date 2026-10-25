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
	# The far sheet is only cut away over chunks already built, so land still
	# being built while the camera scrolls never shows a hole.
	var tv := TerrainView.new()
	tv._mark(Vector2i(-3, 5), true)
	tv._mark(Vector2i(4, 4), true)
	tv._mark(Vector2i(4, 4), false)
	_check(tv._mask.get_pixel(61, 5).r > 0.5 and tv._mask.get_pixel(4, 4).r < 0.5
		and TerrainView.MASK * TerrainView.CHUNK > 2.0 * TerrainView.REACH[-1] + TerrainView.CHUNK,
		"the far land fills in wherever the chunks aren't built yet")
	# The desktop app keeps the land it built and builds the county ahead,
	# nearest first, every chunk once.
	var ring := TerrainView.ring_order(Vector2i(2, 3), Vector2i(-5, -5), Vector2i(7, 6))
	var once := {}
	for key in ring:
		once[key] = true
	var outward := true
	for k in ring.size() - 1:
		var a: Vector2i = ring[k] - Vector2i(2, 3)
		var b: Vector2i = ring[k + 1] - Vector2i(2, 3)
		outward = outward and maxi(absi(a.x), absi(a.y)) <= maxi(absi(b.x), absi(b.y))
	var past := TerrainView.ring_order(Vector2i(10, 10), Vector2i(0, 0), Vector2i(3, 2))
	_check(ring[0] == Vector2i(2, 3) and ring.size() == 12 * 11 and once.size() == ring.size() and outward
		and past.size() == 6 and past[0] == Vector2i(1, 1),
		"the county is preloaded ring by ring out from the camera, every chunk once")
	_check(TerrainView.preload_lods(8.0) == [4, 3] and TerrainView.preload_lods(64.0) == [4, 3, 2],
		"an 8 GB Mac mini preloads the two coarsest levels, a Mac Studio one more")
	tv.keep_land = true
	tv._cache_lods = TerrainView.PRELOAD_LODS
	var t := Time.get_ticks_usec()
	tv._preload_step(Vector2(100.0, 100.0))
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	var first: int = tv._cached
	var near_first: bool = tv._cache.has(Vector2i(0, 0))
	print("  preloaded %d chunks in the first frame (%.1f ms with laying out the order), %d to go"
		% [first, ms, tv._preload.size() - tv._preload_at])
	_check(first > 0 and near_first and tv._preload.size() == 2 * 72 * 72,
		"the desktop app builds the whole county's far land ahead, from the camera out")
	# Graded under a new road: the kept land there and next to it (edge
	# normals read past the chunk) is forgotten, to be built again.
	var queued: int = tv._preload.size()
	tv._mark_dirty([PackedVector3Array([Vector3(100, 0, 100), Vector3(200, 0, 100)]), 6.0, 10.0])
	var gone := true
	for key in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		gone = gone and not tv._cache.has(key)
	var counted := 0
	for key in tv._cache:
		counted += tv._cache[key].size()
	_check(gone and counted == tv._cached and tv._cached < first and tv._preload.size() - queued == first - tv._cached,
		"graded chunks are forgotten and queued to build again")
	# The finest land is never kept (0.7 MB a chunk), nor any by the menu.
	tv._keep(Vector2i(9, 9), 0, {"ground": null})
	tv.keep_land = false
	tv._keep(Vector2i(9, 10), 3, {"ground": null})
	_check(not tv._cache.has(Vector2i(9, 9)) and not tv._cache.has(Vector2i(9, 10)),
		"fine detail isn't kept, and the menu keeps none")
	tv.free()
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
