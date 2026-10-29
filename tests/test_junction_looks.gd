extends SceneTree
## Run: godot --headless -s tests/test_junction_looks.gd
## No two corners need look alike (Nathan, 2026-10-29: "every intersection
## is exactly the same shape"). Each junction's corner radius, ramps,
## warning plates, crosswalks and paint wear come from its place, its era
## and its traffic control: the same every time, on every computer, after a
## save and after an undo. And every look keeps the rules: the radius in its
## era's range, a ramp wherever a sidewalk meets the street, ramps in line
## with every marked crosswalk, no paint across a car-free street.

const CONTROLS := ["signal", "all_stop", "two_way", "none"]

var failed := false


func _init() -> void:
	var sim := _town()
	var plans := Junction.plan(sim.network)
	var town := plans.values().filter(func(j): return not j.get("country", false) and not j.has("bend"))
	_check(town.size() >= 30, "a town grid of shaped junctions (%d)" % town.size())

	# The same junction always gets the same look: planned again, and in a
	# second town built the same way.
	var looks := _looks(plans)
	_check(looks == _looks(Junction.plan(sim.network)), "planned again: every junction looks the same")
	_check(looks == _looks(Junction.plan(_town().network)), "a second town built the same way looks the same")

	# They vary.
	var radii := {}
	var eras := {}
	var ramp_kinds := {}
	var plates := {}
	var styles := {}
	var wears := {}
	for j in town:
		eras[j.look.era] = true
		plates[j.look.domes] = true
		for c in j.corners:
			if c.fillet:
				radii[snappedf(c.r, 0.5)] = true
		for r in Junction.ramps(j):
			ramp_kinds[r[1]] = true
		for control in CONTROLS:
			wears[JunctionMarks.wear(j, control)] = true
			for arm in j.arms:
				for rule in ["stop", ""]:
					styles[JunctionMarks.style(j, arm, rule, control)] = true
	_check(eras.size() >= 2, "more than one era of junction (%s)" % [eras.keys()])
	_check(radii.size() >= 5, "corners of many sizes (%s)" % [radii.keys()])
	_check(ramp_kinds.size() == 2, "both pairs of ramps and diagonal ones (%s)" % [ramp_kinds.keys()])
	_check(plates.size() >= 2, "warning plates in more than one colour (%s)" % [plates.keys()])
	_check(styles.size() == 3, "ladder, two-line and unmarked crosswalks (%s)" % [styles.keys()])
	_check(wears.size() == 3, "fresh, worn and ghost paint (%s)" % [wears.keys()])

	# Every look keeps the rules.
	_check(is_equal_approx(Junction.RAMP_GAP, JunctionMarks.CROSS_NEAR)
		and Junction.RAMP_GAP + Junction.RAMP_WIDTH <= JunctionMarks.CROSS_FAR,
		"a pair of ramps lands inside the crosswalk")
	var bad_radius := []
	var no_ramp := []
	var bad_diagonal := []
	var unramped_paint := []
	for j in town:
		var ramps := {}
		for r in Junction.ramps(j):
			ramps[r[0]] = r[1]
		for i in j.corners.size():
			var c: Dictionary = j.corners[i]
			if not c.fillet:
				continue
			var g := maxi(RoadStyle.group(j.arms[c.a].type), RoadStyle.group(j.arms[c.b].type))
			var span: Array = Junction.ERA_RADIUS[j.look.era].get(g, [0.0, 0.0])
			if c.r < maxf(span[0], 3.0) - 0.01 or c.r > span[1] + 0.01:
				bad_radius.append("%.1f m (%s)" % [c.r, j.look.era])
			if not ramps.has(i):
				no_ramp.append(j.center)
			elif ramps[i] == "diagonal" and c.r > Junction.DIAGONAL_MAX:
				bad_diagonal.append(c.r)
		# The ramps are drawn: warning plates at every corner.
		var st := []
		for k in 6:
			st.append(SurfaceTool.new())
			st[k].begin(Mesh.PRIMITIVE_TRIANGLES)
		Junction.draw({0: j}, st[0], st[1], st[2], st[3], {"domes yellow": st[4], "iron": st[5]})
		var plate_tris := 0
		for k in [3, 4, 5]:
			var m: ArrayMesh = st[k].commit()
			plate_tris += m.get_faces().size() / 3 if m.get_surface_count() > 0 else 0
		if plate_tris < 2 * ramps.size():
			no_ramp.append(j.center)
		# A marked crosswalk has a ramp in line with it at each end.
		for control in CONTROLS:
			for arm in j.arms:
				for rule in ["stop", ""]:
					if JunctionMarks.style(j, arm, rule, control) != "none" and ramps.values().has("diagonal"):
						unramped_paint.append(j.center)
	_check(bad_radius.is_empty(), "every corner's radius is in its era's range, 10 ft or more %s" % [bad_radius])
	_check(no_ramp.is_empty(), "a ramp wherever a sidewalk meets the street %s" % [no_ramp])
	_check(bad_diagonal.is_empty(), "diagonal ramps only on tight corners %s" % [bad_diagonal])
	_check(unramped_paint.is_empty(), "every marked crosswalk has ramps in line with it %s" % [unramped_paint])

	# No paint across a car-free street, at any control.
	var crossed := []
	var painted_shut := 0
	var painted_open := 0
	for j in town:
		var shut := {j.arms[0].seg: true}
		var all_shut := {}
		for arm in j.arms:
			all_shut[arm.seg] = true
		for control in CONTROLS:
			var rules := {}
			for arm in j.arms:
				rules[arm.seg] = "stop"
			if JunctionMarks.style(j, j.arms[0], "stop", control, shut) != "none":
				crossed.append(j.center)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			JunctionMarks.paint(j, rules, st, 0.0, control, shut)
			var m := st.commit()
			if m.get_surface_count() > 0 and _paint_on(m.get_faces(), j, j.arms[0]):
				crossed.append(j.center)
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			JunctionMarks.paint(j, rules, st, 0.0, control, all_shut)
			painted_shut += st.commit().get_surface_count()
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			JunctionMarks.paint(j, rules, st, 0.0, control)
			m = st.commit()
			if m.get_surface_count() > 0 and _paint_on(m.get_faces(), j, j.arms[0]):
				painted_open += 1
	_check(painted_open > 0, "open to cars, the same legs are painted (%d)" % painted_open)
	_check(crossed.is_empty(), "no crosswalk or stop line across a car-free leg %s" % [crossed])
	_check(painted_shut == 0, "a junction of car-free streets has no paint at all")

	# Raised curbs (desktop High): round an old corner's diagonal ramp the
	# curb drops flush, and the streets' curbs stay up where no ramp meets them.
	var diagonal: Array = town.filter(func(j): return Junction.ramps(j).any(func(r): return r[1] == "diagonal"))
	if not diagonal.is_empty():
		var j: Dictionary = diagonal[0]
		var c: Dictionary = j.corners.filter(func(c): return c.fillet)[0]
		var rises := Junction._diagonal_rises(c, j.arms[c.a], j.arms[c.b], 24)
		_check(rises[12] < 0.0 and is_equal_approx(rises[0], RoadMesh.CURB_RISE),
			"a diagonal ramp's curb is flush at the corner's middle, full height at its ends")
		_check(not Junction.pair_ramps({0: j}, 0, j.arms[0].seg), "no ramps in line on its streets")
		RoadMesh.raised_curbs = true
		var sts := []
		for k in 4:
			sts.append(SurfaceTool.new())
			sts[k].begin(Mesh.PRIMITIVE_TRIANGLES)
		Junction.draw({0: j}, sts[0], sts[1], sts[2], sts[3])
		RoadMesh.raised_curbs = false
		_check(sts[1].commit().get_surface_count() == 1 and sts[3].commit().get_surface_count() == 1,
			"an old corner with raised curbs draws its curb and warning plates")
	_check(is_equal_approx(RoadMesh._ramp_rise(1.5, 60.0, Vector2(0, 1)), RoadMesh.CURB_RISE)
		and RoadMesh._ramp_rise(58.5, 60.0, Vector2(0, 1)) < 0.0, "a street's curb drops only at ends with ramps in line")

	# Saves and undo carry nothing new: the looks come back the same.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(looks == _looks(Junction.plan(copy.network)), "after a save and load, every junction looks the same")
	_check(sim.apply({"type": "build_road", "start": [-490, -350], "ctrl": [0, -350], "end": [490, -350]}),
		"a new street across the grid")
	_check(_looks(Junction.plan(sim.network)) != looks, "it makes new junctions")
	_check(sim.apply({"type": "undo"}), "and is undone")
	_check(looks == _looks(Junction.plan(sim.network)), "after the undo, every junction looks as before")

	print("ALL TESTS PASSED" if not failed else "TESTS FAILED")
	quit(1 if failed else 0)


## A grid of streets 140 m apart over several quarter-mile era blocks, a
## main street and an avenue through it.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 100_000_000
	for k in 7:
		var x := -420 + k * 140
		var type := RoadStyle.Type.MAIN_STREET if k == 3 else RoadStyle.Type.STREET
		sim.apply({"type": "build_road", "start": [x, -490], "ctrl": [x, 0], "end": [x, 490], "road": type})
	for k in 7:
		var z := -420 + k * 140
		var type := RoadStyle.Type.AVENUE if k == 4 else RoadStyle.Type.STREET
		sim.apply({"type": "build_road", "start": [-490, z], "ctrl": [0, z], "end": [490, z], "road": type})
	return sim


## Every junction's look by where it is: its look, corner radii, ramps,
## and its crosswalks and wear under each control.
func _looks(plans: Dictionary) -> Dictionary:
	var out := {}
	for n in plans:
		var j: Dictionary = plans[n]
		var radii := []
		for c in j.corners:
			radii.append(snappedf(c.get("r", 0.0), 0.001))
		var paint := []
		if JunctionMarks.marked(j):
			for control in CONTROLS:
				paint.append(JunctionMarks.wear(j, control))
				for arm in j.arms:
					paint.append(JunctionMarks.style(j, arm, "stop", control))
					paint.append(JunctionMarks.style(j, arm, "", control))
		out[Vector2i(roundi(j.center.x), roundi(j.center.z))] = [j.get("look", {}), radii, Junction.ramps(j), paint]
	return out


## True when a painted triangle lies across `arm` between where its road
## starts and its stop line (faces are about the world; the arm about the
## junction's centre).
func _paint_on(faces: PackedVector3Array, j: Dictionary, arm: Dictionary) -> bool:
	for k in range(0, faces.size(), 3):
		var center: Vector3 = j.center
		var mid: Vector3 = (faces[k] + faces[k + 1] + faces[k + 2]) / 3.0 - center
		var p := Vector2(mid.x, mid.z)
		var along: float = p.dot(arm.u)
		if along > arm.d and along < arm.d + JunctionMarks.STOP + 0.5 and absf(p.dot(arm.n)) < arm.hw:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true
