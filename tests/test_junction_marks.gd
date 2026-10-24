extends SceneTree
## Run: godot --headless -s tests/test_junction_marks.gd
## Junction paint by the Indiana MUTCD rules: every leg of a town junction
## gets its crosswalk at the curb ramps, painted lines end there, cars stop
## at the painted stop line, and a gentle bend keeps its sidewalk whole.

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

	# A street bending a little at a node: a bend plan fills its outside,
	# with no trim and no crosswalks.
	var bend := CitySim.new()
	bend.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-50, 0], "end": [0, 0]})
	bend.apply({"type": "build_road", "start": [0, 0], "ctrl": [50, -8], "end": [100, -16]})
	var bj := Junction.plan_node(bend.network, _node_at(bend.network, Vector3.ZERO))
	_check(bj.has("bend"), "a bend gets a plan for its outside curb")
	_check(not JunctionMarks.marked(bj), "a bend has no crosswalks")

	# A gravel road meeting a street keeps a plain join (no curbs on gravel).
	var g := CitySim.new()
	g.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	g.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 75], "end": [0, 150], "road": RoadStyle.Type.GRAVEL})
	_check(Junction.plan_node(g.network, _node_at(g.network, Vector3.ZERO)).is_empty(), "gravel meets a street in a plain join")

	quit(1 if failed else 0)


func _node_at(net: RoadNetwork, p: Vector3) -> int:
	for n in net.nodes:
		if Vector2(net.nodes[n].x - p.x, net.nodes[n].z - p.z).length() < 1.0:
			return n
	return -1


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true
