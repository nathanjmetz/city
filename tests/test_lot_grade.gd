extends SceneTree
## Lots, drives and parking lie on the graded ground, never under it: when
## a town loads, and when a new street regrades the land behind its lots
## (Brawn 2026-10-24: parking lots and drives half under the grass).
## Run: godot --headless -s tests/test_lot_grade.gd

var sim := CitySim.new()
var view: BuildingView
var land: TerrainView
var _o := Vector2.ZERO
var _frames := 0
var _failed := false
var _phase := 0
var _at := 0
var _points := 0


func _initialize() -> void:
	BatchSquare.keep_parts = true
	# A hillside near town, as steep as builders take.
	var steepest := 0.0
	for k in 400:
		var p := Vector2(-1500 + (k % 20) * 150, -1500 + (k / 20) * 150)
		var sl := Terrain.slope(p.x, p.y)
		if Terrain.buildable(p.x, p.y, 120) and sl > steepest and sl < 0.08:
			steepest = sl
			_o = p
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [_o.x - 150, _o.y], "ctrl": [_o.x, _o.y], "end": [_o.x + 150, _o.y], "road": 1})
	for id in sim.network.segments.keys():
		for side in [1, -1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.COMMERCIAL})
	sim.apply({"type": "zone_done"})
	for key in sim.lots.keys():
		sim.found_business(key, ZoneMap.Zone.COMMERCIAL)
	_check(sim.buildings.size() > 10, "a street of shops on a %.0f%% slope (%d)" % [steepest * 100.0, sim.buildings.size()])
	# As main.gd does: the land graded under the roads first, then the
	# buildings drawn on it.
	land = TerrainView.new()
	root.add_child(land)
	land.setup(null, sim.network)
	view = BuildingView.new()
	root.add_child(view)
	view.setup(sim)
	land.graded.connect(view.regraded)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames > 3000:
		_check(false, "the view settles")
		print("TESTS FAILED")
		quit(1)
		return true
	# Once the town is drawn and merged.
	if _frames < 5 or not view.idle():
		return false
	if _phase == 0:
		_check(_under() < 0.03 and _points > 100, "paving lies on the graded ground as the town loads (%.2f m under, %d points)" % [_under(), _points])
		# A back street behind one row of lots regrades the land under them.
		sim.apply({"type": "build_road", "start": [_o.x - 150, _o.y + 70], "ctrl": [_o.x, _o.y + 70],
			"end": [_o.x + 150, _o.y + 70], "road": 0})
		_phase = 1
		_at = _frames
		return false
	if _frames - _at < 10:
		return false
	_check(_under() < 0.03 and _points > 100, "and on the new grade after a street goes in behind (%.2f m under)" % _under())
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
	return false


## How far the ground comes up over any lot's paving, at worst (the flat
## work of every square drawn in full, as it was merged, and of every
## building still going up).
func _under() -> float:
	var worst := 0.0
	_points = 0
	for sq in view._batches:
		for w in view._batches[sq].flat_points():
			worst = maxf(worst, Terrain.ground_y(w.x, w.z) - w.y)
			_points += 1
	# And those still going up, drawn on their own.
	for key in view._recs:
		var r = view._recs[key].site
		if r == null:
			continue
		for site in r.get_children():
			if not site is ConstructionSite or site._ground.mesh == null:
				continue
			var mesh: Mesh = site._ground.mesh
			for s in mesh.get_surface_count():
				for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = r.transform * v
					worst = maxf(worst, Terrain.ground_y(w.x, w.z) - w.y)
					_points += 1
	return worst


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
