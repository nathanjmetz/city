extends SceneTree
## Run: godot --headless -s tests/test_road_wear.gd
## Roads that age (RoadWear, RoadSurface): every road type has its surface,
## traffic and wheel paths; the wear map packs each square's paving date
## exactly and spills it one square round, the newest winning; two copies
## of a town make the same map; a road view hands every road its own ageing
## pavement, and gravel and chip seal pads their own looks.

var _failed := false
const YEAR := 12 * 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	# Every type is covered.
	for t in RoadStyle.TYPES.size():
		_check(RoadWear.TRAFFIC.has(t), "traffic for %s" % RoadStyle.TYPES[t].name)
		var l := RoadWear.lanes(t)
		var hw: float = RoadStyle.TYPES[t].width * 0.5
		var outer: float = absf(l.start) + l.width * (l.count - 0.5) if l.mirror else l.start + l.width * (l.count - 0.5)
		_check(l.count >= 1 and outer <= hw + 0.01, "%s: wheel paths inside the paving" % RoadStyle.TYPES[t].name)
	_check(RoadWear.kind(RoadStyle.Type.GRAVEL) == RoadWear.Kind.GRAVEL, "gravel is gravel")
	_check(RoadWear.kind(RoadStyle.Type.CHIP_SEAL) == RoadWear.Kind.CHIP, "chip seal is chip seal")
	_check(RoadWear.kind(RoadStyle.Type.FREEWAY2) == RoadWear.Kind.CONCRETE, "the interstate is concrete")
	_check(RoadWear.kind(RoadStyle.Type.ALLEY) == RoadWear.Kind.CONCRETE, "alleys are concrete")
	_check(RoadWear.kind(RoadStyle.Type.STREET) == RoadWear.Kind.ASPHALT, "streets are asphalt")
	_check(RoadWear.fatigue(RoadStyle.Type.FREEWAY4) > RoadWear.fatigue(RoadStyle.Type.AVENUE)
		and RoadWear.fatigue(RoadStyle.Type.AVENUE) > RoadWear.fatigue(RoadStyle.Type.STREET),
		"trucks wear the interstate most, then avenues, then streets")

	# Dates pack to 1/256 of a year.
	for y in [-25.0, 0.0, 3.3, 41.75, 150.0]:
		_check(absf(RoadWear.unpack_years(RoadWear.pack_years(y)) - y) <= 1.0 / 512.0, "date %s packs" % y)

	# The wear map.
	var paved := {Vector2i(2, 3): 5 * YEAR, Vector2i(3, 3): 9 * YEAR, Vector2i(10, -4): 0}
	var m := RoadWear.map_image(paved)
	var img: Image = m.image
	var r: Vector4 = m.rect
	_check(r == Vector4(1, -5, 11, 10), "the map covers the squares with one spare round (%s)" % r)
	var at := func(k: Vector2i) -> float:
		var c := img.get_pixel(k.x - int(r.x), k.y - int(r.y))
		if c.a < 0.5:
			return -999.0
		return RoadWear.unpack_years(roundi(c.r * 255.0) * 256 + roundi(c.g * 255.0))
	var y5: float = Seasons.months(5 * YEAR) / 12.0
	var y9: float = Seasons.months(9 * YEAR) / 12.0
	_check(absf(at.call(Vector2i(2, 3)) - y5) < 0.01, "a square keeps its own date")
	_check(absf(at.call(Vector2i(3, 3)) - y9) < 0.01, "and its neighbor its own")
	_check(absf(at.call(Vector2i(2, 4)) - y9) < 0.01, "a square beside both takes the newer")
	_check(absf(at.call(Vector2i(1, 2)) - y5) < 0.01, "the spill reaches one square")
	_check(at.call(Vector2i(6, 0)) < -100.0, "squares far from any street stay empty")
	_check(RoadWear.map_image({}).is_empty(), "no streets, no map")

	# Two copies of a town make the same map.
	var a := CitySim.new()
	a.simulate_traffic = false
	a.economy.money = 50_000_000
	a.tick_count = 3 * YEAR
	a.street_age.paved[Vector2i(999, 999)] = 0
	a.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -200], "end": [0, -400]})
	a.apply({"type": "build_road", "start": [-200, -200], "ctrl": [0, -200], "end": [200, -200], "road": RoadStyle.Type.AVENUE})
	a.street_age.month(a)
	var b := CitySim.new()
	b.from_dict(a.to_dict())
	var ma := RoadWear.map_image(a.street_age.paved)
	var mb := RoadWear.map_image(b.street_age.paved)
	_check(ma.rect == mb.rect and ma.image.get_data() == mb.image.get_data(), "two copies of a town draw the same wear")

	# A road view gives each road its own ageing pavement.
	var view := RoadView.new()
	view.setup(a.network, a)
	var types := {}
	for id in a.network.segments:
		types[a.network.segments[id].type] = true
	for t in types:
		_check(view._mats.get("pave %d" % t) is ShaderMaterial, "%s has its own pavement" % RoadStyle.TYPES[t].name)
	_check(view._mats.has("gravel road") and view._mats.has("chip seal"), "gravel and chip seal pads")
	view._surface.tick(view, a, 1.0)
	var mat: ShaderMaterial = view._mats["pave %d" % RoadStyle.Type.STREET]
	_check(mat.get_shader_parameter("has_map") == 1.0, "the pavement reads the town's wear map")
	_check(absf(float(mat.get_shader_parameter("now_years")) - Seasons.months(a.tick_count) / 12.0) < 0.001,
		"and today's date")
	view.free()
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true
