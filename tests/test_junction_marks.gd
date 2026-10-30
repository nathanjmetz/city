extends SceneTree
## Run: godot --headless -s tests/test_junction_marks.gd
## Junction paint by the Indiana MUTCD rules: every leg of a town junction
## has room for its crosswalk at the curb ramps, painted lines end there,
## cars stop at the painted stop line, and a gentle bend keeps its sidewalk
## whole. The paint the game draws (each leg's crosswalk by the junction's
## control and look, JunctionMarks.style) is marked where the rules say,
## always at a signal, and never across a car-free street.

var failed := false


func _init() -> void:
	_check(is_equal_approx(JunctionMarks.STOP, TrafficSim.STOP_PAST_RETURN), "paint and traffic agree where cars stop")

	# Skewed, Y and five-leg junctions: every leg is marked past its own
	# curb return, so no crosswalk lies inside the junction.
	var shapes := {
		"skewed": [[[-150, 0], [150, 0]], [[-60, 150], [60, -150]]],
		"y": [[[-150, 0], [150, 0]], [[0, 0], [-120, 150]], [[0, 0], [120, 150]]],
		"five legs": [[[-150, 0], [150, 0]], [[0, 0], [0, -150]], [[0, 0], [-120, 150]], [[0, 0], [120, 150]]],
		"t": [[[-150, 0], [150, 0]], [[0, 0], [0, 150]]],
	}
	for name in shapes:
		var sim := CitySim.new()
		for r in shapes[name]:
			var a: Array = r[0]
			var b: Array = r[1]
			sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})
		var node := _node_at(sim.network, Vector3.ZERO)
		var plans := Junction.plan(sim.network)
		var j: Dictionary = plans.get(node, {})
		_check(JunctionMarks.marked(j), "%s: the junction is marked" % name)
		if j.is_empty():
			continue
		var outline: PackedVector2Array = j.poly
		for arm in j.arms:
			_check(JunctionMarks.room(arm) == 2, "%s: leg %d has room for its crosswalk and stop line" % [name, arm.seg])
			# The crosswalk's corners sit on the leg's own pavement, outside
			# the junction's.
			var p: Array = LotPlanner.point_at(arm.pts, arm.d + JunctionMarks.CROSS_NEAR + 0.05)
			var at := Vector2(p[0].x, p[0].z) - Vector2(j.center.x, j.center.z)
			var n := Vector2(-p[1].z, p[1].x).normalized()
			for side in [-1.0, 1.0]:
				var corner: Vector2 = at + n * side * (arm.hw - 0.3)
				_check(not Geometry2D.is_point_in_polygon(corner, outline),
					"%s: leg %d's crosswalk is clear of the junction" % [name, arm.seg])
			_check(JunctionMarks.line_cut(plans, node, arm.seg) == JunctionMarks.CROSS_FAR,
				"%s: leg %d's lines end at the crosswalk" % [name, arm.seg])
			# Cars on this leg stop at the back of its stop line.
			var back := JunctionMarks.stop_back(j, arm.seg)
			for wid in sim.traffic.ways_into(node):
				var w: Dictionary = sim.traffic.ways[wid]
				if w.seg == arm.seg:
					_check(absf((w.len - w.s1) - back) < 0.01,
						"%s: leg %d stops at its stop line (%.1f m, painted %.1f m)" % [name, arm.seg, w.len - w.s1, back])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rules := {}
		for arm in j.arms:
			rules[arm.seg] = "stop"
		JunctionMarks.paint(j, rules, st, 0.1)
		_check(st.commit().get_surface_count() == 1, "%s: paint drawn" % name)
		_real_paint(sim, node, name)

	# A street bending a little at a node: a bend plan fills its outside,
	# with no trim and no crosswalks.
	var bend := CitySim.new()
	bend.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-50, 0], "end": [0, 0]})
	bend.apply({"type": "build_road", "start": [0, 0], "ctrl": [50, -8], "end": [100, -16]})
	var bj := Junction.plan_node(bend.network, _node_at(bend.network, Vector3.ZERO))
	_check(bj.has("bend"), "a bend gets a plan for its outside curb")
	_check(not JunctionMarks.marked(bj), "a bend has no crosswalks")

	# A gravel road meeting a street: a country junction (no curbs on gravel,
	# no round pad: Nathan 2026-10-25, "a circle node shape").
	var g := CitySim.new()
	g.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	g.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 75], "end": [0, 150], "road": RoadStyle.Type.GRAVEL})
	var gj := Junction.plan_node(g.network, _node_at(g.network, Vector3.ZERO))
	_check(gj.get("country", false) and not JunctionMarks.marked(gj), "gravel meets a street in a country junction, unmarked")

	quit(1 if failed else 0)


## The paint the game draws at a junction (as JunctionView paints it): as
## the town controls it, then with lights the player put up, then with one
## leg made car-free.
func _real_paint(sim: CitySim, node: int, name: String) -> void:
	sim.tick()  # traffic sets up its junctions
	_legs(sim, node, Junction.plan(sim.network).get(node, {}), "%s as built" % name, false)
	sim.traffic.set_rule(node, TrafficSim.Rule.SIGNAL)
	var lit: Dictionary = Junction.plan(sim.network, {}, {}, {node: true}).get(node, {})
	_check(not lit.is_empty() and Junction.ramps(lit).all(func(r): return r[1] == "pair"),
		"%s with lights: a ramp in line with each crosswalk" % name)
	_legs(sim, node, lit, "%s with lights" % name, true)
	sim.traffic.close_segment(lit.arms[0].seg, true)
	_legs(sim, node, lit, "%s with lights and a car-free leg" % name, true)
	sim.traffic.close_segment(lit.arms[0].seg, false)


## Each leg is painted across exactly when its style says it is marked;
## `lit`: every leg open to cars must be.
func _legs(sim: CitySim, node: int, j: Dictionary, what: String, lit: bool) -> void:
	if j.is_empty():
		_check(false, "%s: shaped" % what)
		return
	var t := sim.traffic
	var rules := JunctionMarks.leg_rules(t, node)
	var control := JunctionMarks.control_of(t.junctions.get(node, {}))
	var shut := JunctionMarks.car_free_legs(t, j)
	if lit:
		_check(control == "signal", "%s: the junction has lights" % what)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	JunctionMarks.paint(j, rules, st, 0.1, control, shut)
	var m := st.commit()
	var faces := m.get_faces() if m.get_surface_count() > 0 else PackedVector3Array()
	var center: Vector3 = j.center
	for arm in j.arms:
		var style := JunctionMarks.style(j, arm, rules.get(arm.seg, ""), control, shut)
		var across := false  # paint on the crosswalk
		var on := false  # paint anywhere up to the stop line
		for k in range(0, faces.size(), 3):
			var mid: Vector3 = (faces[k] + faces[k + 1] + faces[k + 2]) / 3.0 - center
			var p := Vector2(mid.x, mid.z)
			var along: float = p.dot(arm.u)
			if absf(p.dot(arm.n)) >= arm.hw or along < arm.d:
				continue
			across = across or along < arm.d + JunctionMarks.CROSS_FAR
			on = on or along < arm.d + JunctionMarks.STOP + 0.5
		if shut.has(arm.seg):
			_check(style == "none" and not on, "%s: no paint across car-free leg %d" % [what, arm.seg])
			continue
		_check(across == (style != "none"), "%s: leg %d is %s" % [what, arm.seg, "marked" if across else "unmarked"])
		if lit:
			_check(style != "none", "%s: leg %d is marked at the signal" % [what, arm.seg])


func _node_at(net: RoadNetwork, p: Vector3) -> int:
	for n in net.nodes:
		if Vector2(net.nodes[n].x - p.x, net.nodes[n].z - p.z).length() < 1.0:
			return n
	return -1


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true
