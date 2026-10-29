extends SceneTree
## Run: godot --headless -s tests/test_bridges.gd
## Road bridges by span, the way INDOT builds them: one span of box beams
## over a creek, prestressed beams on bents across a river, barrier rail on
## every deck and, on desktop detail, guardrail along the approaches.

func _init() -> void:
	var short := BridgeMesh.spans_for(18.0)
	_check(is_equal_approx(float(short[0]), 18.0), "an 18 m creek crossing is one span")
	var mid := BridgeMesh.spans_for(50.0)
	_check(is_equal_approx(float(mid[0]), 25.0), "a 50 m river crossing is two 25 m spans (%.1f)" % mid[0])
	var long := BridgeMesh.spans_for(120.0)
	_check(float(long[0]) <= 45.0 and float(long[0]) > 30.0, "a 120 m crossing uses longer girder spans (%.1f)" % long[0])
	_check(float(long[1]) > float(mid[1]), "and deeper girders")

	# A road over a dip: level ground at 0, a 40 m valley 6 m deep.
	var ground := func(x: float, _z: float) -> float:
		return -6.0 if absf(x) < 20.0 else 0.0
	var pts := PackedVector3Array()
	for i in 41:
		pts.append(Vector3(-100.0 + i * 5.0, 0.0, 0.0))
	var runs := BridgeMesh._runs(pts, ground)
	_check(runs.size() == 1, "the road is on one bridge")
	var fine_n := _verts(pts, ground, true)
	var far_n := _verts(pts, ground, false)
	_check(far_n.concrete > 0, "the bridge draws a deck, rail and piers")
	_check(fine_n.steel > 0 and fine_n.marker > 0, "desktop detail adds guardrail and end markers")
	_check(far_n.steel == 0, "and the lighter tiers leave them off")
	_check(fine_n.concrete > far_n.concrete, "desktop shows girders under the deck")

	# An overpass: the pier that would stand on the road under it moves
	# along the span clear of it (shoulder and all).
	var deck := PackedVector3Array()
	for i in 25:
		deck.append(Vector3(-30.0 + i * 2.5, 0.0, 0.0))
	var cum := [0.0]
	for i in range(1, deck.size()):
		cum.append(cum[-1] + 2.5)
	var under := func(p: Vector3) -> bool: return absf(p.x) < 7.5
	var at := BridgeMesh._clear_spot(deck, 0, cum, 30.0, 13.5, 5.0, under)
	_check(at > 0.0 and absf(at - 30.0) >= 7.5, "the pier steps off the road under the bridge (%.0f m along)" % at)
	var wide := func(p: Vector3) -> bool: return absf(p.x) < 25.0
	_check(BridgeMesh._clear_spot(deck, 0, cum, 30.0, 13.5, 5.0, wide) < 0.0, "and where there's no room the span runs on over it")

	# A road on the ground draws no bridge.
	var flat := func(_x: float, _z: float) -> float:
		return 0.0
	var parts := _parts()
	_check(not BridgeMesh.build(pts, 5.0, parts, flat, true), "a road on the ground has no bridge")
	quit(1 if _failed else 0)


func _parts() -> Dictionary:
	var parts := {}
	for k: String in ["concrete", "steel", "marker"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[k] = st
	return parts


func _verts(pts: PackedVector3Array, ground: Callable, fine: bool) -> Dictionary:
	var parts := _parts()
	BridgeMesh.build(pts, 5.0, parts, ground, fine)
	var out := {}
	for k: String in parts:
		var arrays := (parts[k] as SurfaceTool).commit_to_arrays()
		out[k] = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arrays[Mesh.ARRAY_VERTEX] != null else 0
	return out


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
