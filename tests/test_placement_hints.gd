extends SceneTree
## Run: godot --headless -s tests/test_placement_hints.gd
## Placement hints: a polluting tool previews its smoke downwind on the real
## prevailing wind and its noise rings, and counts the homes it would reach.

var _failed := false


func _init() -> void:
	var hints := PlacementHints.new()
	var w := Pollution.WIND
	var src := Vector3(1000, 0, 1000)
	# Homes 400 m downwind, 400 m upwind and 40 m to the side.
	var down := Vector2(src.x, src.z) + w * 400.0
	var up := Vector2(src.x, src.z) - w * 400.0
	var near := Vector2(src.x, src.z) + Vector2(-w.y, w.x) * 40.0
	for h in [down, up, near]:
		var bk := Vector2i(floori(h.x / PlacementHints.BUCKET), floori(h.y / PlacementHints.BUCKET))
		if not hints._homes.has(bk):
			hints._homes[bk] = []
		hints._homes[bk].append(h)
	var f: Dictionary = Balance.POLLUTION_SOURCES.factory
	var c := hints.count_homes(src, float(f.smoke), float(f.noise))
	_check(c.smoke >= 1, "a factory's smoke reaches the home downwind (%s)" % c)
	_check(Pollution._plume(float(f.smoke), up - Vector2(src.x, src.z), w) < PlacementHints.SMOKE_SEEN,
		"the home upwind gets none of its smoke")
	_check(c.noise == 1, "its noise reaches only the home next door (%s)" % c)
	var coal: Dictionary = Balance.POLLUTION_SOURCES.power_coal
	var cc := hints.count_homes(src, float(coal.smoke), float(coal.noise))
	_check(cc.smoke >= c.smoke and cc.unhealthy >= 1, "a coal plant is worse, unhealthy downwind (%s)" % cc)

	# Noise rings fall 6 dB per doubling: 68 dBA at 15 m is 62 at about 30 m.
	var r := PlacementHints._noise_radius(68.0, 62.0)
	_check(r > 27.0 and r < 31.0, "62 dBA ring of a 68 dBA source at ~30 m (%.1f)" % r)
	_check(PlacementHints._noise_radius(50.0, 55.0) == 0.0, "a quiet source has no ring")

	# The wind is the real one: from the southwest, so smoke drifts northeast.
	_check(Pollution.wind_words() == ["southwest", "northeast"], "wind words (%s)" % [Pollution.wind_words()])
	hints.free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
