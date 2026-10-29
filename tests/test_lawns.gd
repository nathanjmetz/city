extends SceneTree
## Run: godot --headless -s tests/test_lawns.gd
## Every yard its own lawn (LawnLook, LawnMap; Nathan, 2026-10-29: "every
## lawn is the same color"): the same lot always gets the same lawn, kept
## yards run greener and striped and run-down ones weedy and worn, a lot's
## lawn is painted where the lot is, and the browser's ground has none of it.

var _failed := false


func _init() -> void:
	_looks()
	_painted()
	_browser()
	print("FAILED" if _failed else "All lawn tests passed")
	quit(1 if _failed else 0)


func _looks() -> void:
	# The same lot, the same lawn, every time.
	var a := LawnLook.of(7, "12:1:340", 0)
	var b := LawnLook.of(7, "12:1:340", 0)
	_check(a == b, "the same lot gets the same lawn every time")
	_check(LawnLook.of(8, "12:1:340", 0) != a, "another town's lot is another lawn")
	# Kept-up lots differ from each other (Nathan: "every lawn is the same color").
	var lush := []
	var striped := 0
	var weedy := 0
	var worn := 0
	for i in 400:
		var l := LawnLook.of(7, "5:0:%d" % (i * 10), 0)
		lush.append(l.lush)
		striped += 1 if l.stripes > 0.0 else 0
		weedy += 1 if l.weeds > 0.25 else 0
		worn += 1 if l.wear.size() > 1 else 0
	lush.sort()
	_check(lush[360] - lush[40] > 0.2, "kept-up lawns run from tired to deep green (%.2f to %.2f)" % [lush[40], lush[360]])
	_check(striped > 20 and striped < 120, "some are mower-striped, most not (%d of 400)" % striped)
	_check(weedy > 20 and weedy < 200, "some are weedy (%d of 400)" % weedy)
	_check(worn > 40, "some have paths worn in (%d of 400)" % worn)
	# Upkeep shows: showpieces deep green and striped, run-down ones weedy.
	var by := {}
	for t in [-2, -1, 0, 1, 2]:
		var s := {"lush": 0.0, "weeds": 0.0, "stripes": 0, "wear": 0}
		for i in 100:
			var l := LawnLook.of(3, "9:1:%d" % i, t)
			s.lush += l.lush / 100.0
			s.weeds += l.weeds / 100.0
			s.stripes += 1 if l.stripes > 0.0 else 0
			s.wear += l.wear.size()
		by[t] = s
	_check(by[2].lush > by[0].lush + 0.15 and by[0].lush > by[-2].lush + 0.15,
		"greener with upkeep (%.2f derelict, %.2f kept, %.2f showpiece)" % [by[-2].lush, by[0].lush, by[2].lush])
	_check(by[-2].weeds > 0.8 and by[-1].weeds > 0.5 and by[2].weeds == 0.0, "run-down lawns are weedy, showpieces clean")
	_check(by[2].stripes > 80 and by[-1].stripes == 0, "showpieces are striped (%d of 100), run-down never" % by[2].stripes)
	_check(by[-2].wear > by[2].wear * 3, "run-down yards are worn (%d marks) more than showpieces (%d)" % [by[-2].wear, by[2].wear])
	# A non-home's grounds are kept by a crew: no swing set or dog run.
	var yard_things := 0
	for i in 50:
		for m in LawnLook.of(3, "2:0:%d" % i, -1, false).wear:
			yard_things += 0 if m[0] == "edge" else 1
	_check(yard_things == 0, "a shop's lawn has no paths, dog runs or swing sets")


func _painted() -> void:
	var sim := _town(31)
	_check(sim.buildings.size() >= 10, "the test town grew (%d buildings)" % sim.buildings.size())
	var map := _paint(sim)
	_check(map.tile_count() > 0, "the yards are painted (%d tiles)" % map.tile_count())
	_check(map.is_drawn(), "and done")
	# Each built lot's middle holds its own lawn.
	var keys := sim.buildings.keys()
	keys.sort()
	var right := 0
	var seen := {}
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		var look := LawnLook.of(sim.city_seed, key, sim.care.tier_of(key),
			int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL)
		var tx := map.texel(Vector2(lot.pos.x, lot.pos.z))
		if not tx.is_empty() and absf(tx[0].r - look.lush) < 0.01 and absf(tx[0].g - look.weeds) < 0.01:
			right += 1
		if not tx.is_empty():
			seen[snappedf(tx[0].r, 0.02)] = true
	_check(right >= keys.size() * 9 / 10, "each lot's middle holds its own lawn (%d of %d)" % [right, keys.size()])
	_check(seen.size() >= 4, "and they differ yard to yard (%d shades)" % seen.size())
	# Off the lots, the even lawn of before.
	var off := map.texel(Vector2(0.0, -140.0))
	_check(off.is_empty() or _near(off[0], LawnLook.NEUTRAL_A), "off the lots the lawn is as before")
	# The same town painted again (another copy, another player) is the
	# same picture, texel for texel.
	var again := _paint(_town(31))
	var same := true
	for key in keys:
		var p: Vector3 = sim.lots[key].pos
		for d in [Vector2.ZERO, Vector2(5, 3), Vector2(-4, 6)]:
			same = same and map.texel(Vector2(p.x, p.z) + d) == again.texel(Vector2(p.x, p.z) + d)
	_check(same, "the same town paints the same lawns every time")
	# A run-down owner's lawn goes weedy; nothing else on the street changes.
	var key: String = keys[0]
	var other: String = keys[keys.size() - 1]
	var lp: Vector3 = sim.lots[key].pos
	var op: Vector3 = sim.lots[other].pos
	var other_was := map.texel(Vector2(op.x, op.z))
	sim.care.tier[key] = -1
	sim.buildings_changed.emit()
	for i in 200:
		map._process(0.016)
	var now := map.texel(Vector2(lp.x, lp.z))
	_check(now[0].g > 0.5, "a run-down yard goes weedy (%.2f)" % now[0].g)
	_check(map.texel(Vector2(op.x, op.z)) == other_was, "the neighbours' lawns stay as they were")
	# Where the map paints a town's lawns, the builders leave out their flat
	# weed patches (hard-edged blobs); elsewhere (the browser) they stay.
	_check(LawnMap.paints(sim) and not LawnMap.paints(CitySim.new()), "the map knows which town it paints")
	var lot := {"width": 22.0, "depth": 45.0}
	HouseBuilder.owner_care = -2
	var blobs := _ground_tris(HouseBuilder.build(4242, 6.0, lot, 1)[1])
	HouseBuilder.flat_weeds = false
	var soft := _ground_tris(HouseBuilder.build(4242, 6.0, lot, 1)[1])
	HouseBuilder.flat_weeds = true
	HouseBuilder.owner_care = 0
	var kept := _ground_tris(HouseBuilder.build(4242, 6.0, lot, 1)[1])
	_check(blobs > soft + 100 and soft == kept, "no flat weed blobs where the ground draws the weeds (%d, %d, kept %d)" % [blobs, soft, kept])
	map.free()
	again.free()


func _browser() -> void:
	# The browser's ground compiles none of it: every lawn sampler sits
	# behind DESKTOP_DETAIL, which only the desktop app defines.
	var code := TerrainView.SHADER
	var gate := code.find("#ifdef DESKTOP_DETAIL")
	_check(gate >= 0 and gate < code.find("sampler2DArray lawn_a"), "the lawn maps are desktop only")
	var body := code.substr(code.find("void fragment()"))
	var open := body.find("float lawn_resp = 1.0;")
	_check(open >= 0 and body.find("#ifdef DESKTOP_DETAIL", open) == body.find("#ifdef", open),
		"the lawn look is desktop only too")


func _paint(sim: CitySim) -> LawnMap:
	var map := LawnMap.new()
	map.setup(sim)
	for i in 400:
		map._process(0.016)
		if map.is_drawn():
			break
	return map


func _ground_tris(m: ArrayMesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		n += m.surface_get_array_len(i) / 3
	return n


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	sim.economy.money = 500_000_000
	sim.apply({"type": "build_road", "start": [-120, 0], "ctrl": [0, 0], "end": [120, 0]})
	for x in range(-120, 121, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 300:
		sim.tick()
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	for key in empty:
		var b := {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": hash([seed, key]), "built": sim.tick_count,
			"changed": sim.tick_count, "occ": 2}
		sim.buildings[key] = BuildingTypes.make(sim, key, b, "house", 0)
	return sim


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		_failed = true
