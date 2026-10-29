extends SceneTree
## Run: godot --headless -s tests/test_water_crossings.gd
## County roads and highways carry on over the creeks and the river instead
## of stopping at the bank: a culvert under the fill where the creek is a
## trickle, a bridge over wider water (Indiana: 20 ft or more is a bridge).

func _init() -> void:
	var all := WaterCrossings.near(Terrain.CENTRE, 18000.0)
	var bridges := all.filter(func(x): return x.kind == "bridge")
	_check(bridges.size() >= 5,
		"the county's roads cross its creeks and river (%d crossings)" % all.size())
	for x in all:
		var n: int = x.pts.size()
		var a: Vector2 = x.pts[0]
		var b: Vector2 = x.pts[n - 1]
		if Terrain.water(a.x, a.y) >= WaterCrossings.WET or Terrain.water(b.x, b.y) >= WaterCrossings.WET:
			_check(false, "%s starts and ends on dry land" % x.key)
		if x.span > WaterCrossings.MAX_GAP:
			_check(false, "%s is no wider than a real county bridge" % x.key)
		var steepest := 0.0
		for i in n - 1:
			# Up on its fill or deck (on the ground it runs as the land does).
			if x.deck[i] - Terrain.height(x.pts[i].x, x.pts[i].y) > 0.3:
				steepest = maxf(steepest, absf(x.deck[i + 1] - x.deck[i]) / (x.pts[i] as Vector2).distance_to(x.pts[i + 1]))
		if steepest > 0.09:
			_check(false, "%s: no steep ramp onto the deck (%.0f%%)" % [x.key, steepest * 100.0])
		var low := INF
		for i in n:
			if Terrain.is_water(x.pts[i].x, x.pts[i].y):
				low = minf(low, x.deck[i] - x.level)
		if low < 0.5:
			_check(false, "%s stays over the water (%.1f m)" % [x.key, low])
	_check(not _failed, "every crossing runs bank to bank, above the water, at a drivable grade")

	# A trickle of a creek under a gravel road, 3 m below its banks.
	var cul: Dictionary = bridges[0].duplicate()
	cul.kind = "culvert"
	cul.pts = PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0), Vector2(15, 0), Vector2(20, 0)])
	var g := Terrain.height(0, 0)
	cul.deck = PackedFloat32Array([g, g + 0.5, g + 1.0, g + 0.5, g])
	cul.wettest = 2
	var parts := WaterCrossingView.build(cul, Vector2.ZERO, true)
	_check(parts.has("gravel") and parts.has("fill") and parts.has("concrete") and parts.has("dark"),
		"a culvert: the gravel road on its fill, concrete headwalls and the pipe's mouth")
	var bridge: Dictionary = bridges[0]
	var fine := WaterCrossingView.build(bridge, Vector2.ZERO, true)
	var far := WaterCrossingView.build(bridge, Vector2.ZERO, false)
	_check(fine.has("concrete") and fine.has("steel"), "a bridge with its barrier rail and approach guardrail on desktop")
	_check(not far.has("steel"), "and plainer on the lighter tiers")
	_check(WaterCrossings.near(bridge.mid, 50.0, {bridge.key.split("@")[0]: true}).filter(
		func(x): return x.key == bridge.key).is_empty(), "a mile the town has taken over draws no scenery crossing")
	quit(1 if _failed else 0)


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
