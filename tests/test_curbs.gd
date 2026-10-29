extends SceneTree
## Run: godot --headless -s tests/test_curbs.gd
## Raised curbs (desktop High and up): a 4 in rolled curb stands along a
## town street and round its corners, and drops flush where the curb ramps
## meet the street.

var failed := false


func _init() -> void:
	var rv := RoadView.new()
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(30, 0, 0), Vector3(60, 0, 0)])
	RoadMesh.raised_curbs = false
	var flat := RoadMesh.street(pts, RoadStyle.Type.STREET, rv._mats)
	_check(_top(flat, rv._mats.curb) < RoadStyle.Y_ASPHALT + 0.01, "flat curbs lie flat")
	RoadMesh.raised_curbs = true
	var raised := RoadMesh.street(pts, RoadStyle.Type.STREET, rv._mats)
	_check(is_equal_approx(_top(raised, rv._mats.curb), RoadStyle.Y_ASPHALT + RoadMesh.CURB_RISE),
		"the curb stands 4 in above the pavement")
	_check(not _has(raised, rv._mats.curb_face), "no flat curb face line under a raised curb")
	# Flush at the ramps, full height mid-block.
	_check(RoadMesh._ramp_rise(1.5, 60.0) < 0.0, "the curb drops at the start's curb ramp")
	_check(RoadMesh._ramp_rise(58.5, 60.0) < 0.0, "and at the end's")
	_check(is_equal_approx(RoadMesh._ramp_rise(30.0, 60.0), RoadMesh.CURB_RISE), "full height mid-block")
	# Corners: a curb return stands up too.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 75], "end": [0, 150]})
	var plans := Junction.plan(sim.network)
	var sts := []
	for k in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	Junction.draw(plans, sts[0], sts[1], sts[2], sts[3])
	var corner := sts[1].commit() as ArrayMesh
	_check(_top_any(corner) > RoadStyle.Y_ASPHALT + RoadMesh.CURB_RISE * 0.9, "corner curbs stand up")
	RoadMesh.raised_curbs = false
	rv.free()
	print("ALL TESTS PASSED" if not failed else "SOME TESTS FAILED")
	quit(1 if failed else 0)


static func _top(mesh: ArrayMesh, mat: Material) -> float:
	var top := -INF
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) == mat:
			for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				top = maxf(top, v.y)
	return top


static func _top_any(mesh: ArrayMesh) -> float:
	var top := -INF
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, v.y)
	return top


static func _has(mesh: ArrayMesh, mat: Material) -> bool:
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) == mat:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true
