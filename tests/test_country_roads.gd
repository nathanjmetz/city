extends SceneTree
## Run: godot --headless -s tests/test_country_roads.gd
## Country roads the way Indiana builds them (Nathan, 2026-10-25, at a grid
## of streets meeting the highway): no round pad where roads meet, edge
## lines that stop at the corner instead of crossing into a "T", stop lines
## 4 ft before the edge line of the road met and square to the lane, and a
## pole line that keeps to one side at a steady spacing and never stands on
## a road.

var failed := false


func _init() -> void:
	# A county road teed onto the state highway.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0],
		"road": RoadStyle.Type.STATE_HWY})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200],
		"road": RoadStyle.Type.COUNTY})
	var node := _node_at(sim.network, Vector3.ZERO)
	var plans := Junction.plan(sim.network)
	var j: Dictionary = plans.get(node, {})
	_check(j.get("country", false), "\"a circle node shape\": the tee is a shaped country junction, not a round pad")
	_check(not JunctionMarks.marked(j), "a country junction has no crosswalks")
	_check(j.get("through", []).size() == 2, "the highway runs on through the tee")
	var side: Dictionary = {}
	for arm in j.get("arms", []):
		if int(arm.type) == RoadStyle.Type.COUNTY:
			side = arm
	_check(not side.is_empty() and side.d > RoadStyle.half_width(RoadStyle.Type.STATE_HWY) + 6.0,
		"the county road stops where its corner radius starts (%.1f m out)" % side.get("d", 0.0))
	# "The white lines on the sides of the road intersect to a T": the
	# highway's edge line and shoulder stop on the county road's side only.
	var broken := 0
	for seg in j.get("breaks", {}):
		for b in j.breaks[seg]:
			broken += 1
			_check(b[1] > RoadStyle.half_width(RoadStyle.Type.COUNTY) + 1.0,
				"the edge line stops %.1f m out, at the radius, not across the side road" % b[1])
	_check(broken == 2, "the highway's edge line breaks on the tee's side only, each way (%d)" % broken)
	# "The white lines for an intersection are not where they are supposed
	# to be": 4 ft before the highway's edge line, never on its shoulder.
	var near := JunctionMarks.country_near(j, side)
	var edge := RoadMesh.edge_line(RoadStyle.Type.STATE_HWY, true)
	_check(near >= edge + JunctionMarks.BAR_GAP - 0.01 and near >= RoadStyle.half_width(RoadStyle.Type.STATE_HWY),
		"stop line %.1f m from the middle: 4 ft past the edge line (%.1f), off the highway's pavement" % [near, edge])
	_check(near < edge + 9.0, "and no more than 30 ft back from it")
	var lanes := JunctionMarks.country_lanes(side)
	_check(lanes[0] > 0.0 and lanes[1] <= RoadMesh.edge_line(RoadStyle.Type.COUNTY, true),
		"the stop line spans the approach lane, centre line to edge line")

	# A crossroads of equal country roads: no road runs through, each stops
	# at its radius, and none gets a round pad.
	var grid := CitySim.new()
	grid.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.COUNTY})
	grid.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200], "road": RoadStyle.Type.COUNTY})
	var cj: Dictionary = Junction.plan(grid.network).get(_node_at(grid.network, Vector3.ZERO), {})
	_check(cj.get("country", false) and cj.get("through", [1]).is_empty() and cj.get("breaks", {1: 1}).is_empty(),
		"a crossroads of equal roads: every road stops at its radius")
	_check(cj.get("corners", []).filter(func(c): return c.fillet).size() == 4, "four radii at a crossroads")

	# A street branching off the highway in a shallow Y is shaped too.
	var y := CitySim.new()
	y.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": RoadStyle.Type.STATE_HWY})
	y.apply({"type": "build_road", "start": [0, 0], "ctrl": [120, -45], "end": [260, -120], "road": RoadStyle.Type.COUNTY})
	_check(Junction.plan(y.network).get(_node_at(y.network, Vector3.ZERO), {}).get("country", false),
		"a shallow Y off the highway is a shaped country junction")

	# "The power lines don't make any sense": one side all along, a pole
	# every 100-150 ft, none on the road, and every road running the same
	# way keeps to the same side.
	var pts := PackedVector3Array()
	for k in 41:
		pts.append(Vector3(k * 10.0, 0, 0))
	var off := PoleLine.side_for(Vector3.RIGHT) * 10.0
	var poles := PoleLine.place(pts, off, Vector2(6.0, 6.0))
	var sides := {}
	var gaps := []
	for i in poles.size():
		var b: Vector3 = poles[i][0]
		sides[signf(b.z)] = true
		_check(absf(b.z) > RoadStyle.half_width(RoadStyle.Type.STATE_HWY) + Junction.SHOULDER,
			"pole %d stands past the shoulder (%.1f m out)" % [i, absf(b.z)])
		if i > 0:
			gaps.append(b.distance_to(poles[i - 1][0]))
	_check(sides.size() == 1, "the poles keep to one side of the road")
	_check(gaps.all(func(g): return g >= 30.0 and g <= 46.0), "poles every 100-150 ft (%s)" % [gaps])
	_check(PoleLine.side_for(Vector3.RIGHT) == -PoleLine.side_for(Vector3.LEFT),
		"a road drawn the other way keeps its line on the same side of the land")
	# A pole kept off a side road slides along, it isn't left in the road.
	var blocked := func(p: Vector3) -> bool: return absf(p.x - 200.0) < 12.0
	for pole in PoleLine.place(pts, off, Vector2(6.0, 6.0), [], blocked):
		_check(absf(pole[0].x - 200.0) >= 12.0, "no pole in the side road at x %.0f" % pole[0].x)
	# Wires sag between poles.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	PoleLine.span(st, Vector3(0, 10, 0), Vector3(40, 10, 0))
	var low := INF
	for v in st.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		low = minf(low, v.y)
	_check(low < 9.4 and low > 8.5, "a 40 m span sags about 2 ft (lowest %.2f m)" % low)
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
