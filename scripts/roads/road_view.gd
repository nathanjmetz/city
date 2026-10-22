class_name RoadView
extends Node3D
## Draws the road network. Rebuilds every mesh whenever the network changes,
## which is plenty fast for a small town.

var network: RoadNetwork

var _mats := {
	"asphalt": RoadStyle.material(RoadStyle.ASPHALT_COLOR),
	"curb": RoadStyle.material(RoadStyle.CURB_COLOR),
	"walk": RoadStyle.material(RoadStyle.SIDEWALK_COLOR),
	"median": RoadStyle.material(RoadStyle.MEDIAN_COLOR),
	"yellow": RoadStyle.material(RoadStyle.MARKING_YELLOW),
	"white": RoadStyle.material(RoadStyle.MARKING_WHITE),
	"concrete": RoadStyle.material(Color(0.66, 0.65, 0.62)),
	"apron": RoadStyle.material(Color(0.5, 0.44, 0.38)),  # tinted, textured-look concrete
	"tunnel": RoadStyle.material(Color(0.1, 0.1, 0.12, 0.45), true),
}


func setup(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var piers := SurfaceTool.new()
	piers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_bridge := false
	# Ramps joining highways start where they clear the through lanes.
	var merges := RampMerge.merges(network)
	var cuts := {}  # [seg, node] -> metres
	for m in merges:
		cuts[[m.ramp, m.node]] = RampMerge.ramp_cut(m)
	for id in network.segments:
		var pts := network.sample_segment(id)
		var type: int = network.segments[id].type
		var sg: Dictionary = network.segments[id]
		pts = RampMerge.trim_ramp(pts, cuts.get([id, sg.a], 0.0), true)
		pts = RampMerge.trim_ramp(pts, cuts.get([id, sg.b], 0.0), false)
		if pts.size() < 2:
			continue
		var mi := MeshInstance3D.new()
		if _underground(pts):
			# Tunnels show as a dark path on the ground above them.
			var flat := PackedVector3Array()
			for p in pts:
				flat.append(Vector3(p.x, 0.05, p.z))
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			RoadMesh.add_strip(st, flat, -RoadStyle.half_width(type), RoadStyle.half_width(type), 0.1)
			mi.mesh = st.commit()
			mi.material_override = _mats.tunnel
		else:
			mi.mesh = RoadMesh.street(pts, type, _mats)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			any_bridge = RoadMesh.bridge(pts, RoadStyle.right_of_way_half(type), piers) or any_bridge
		add_child(mi)
	if not merges.is_empty():
		var layers := {"asphalt": SurfaceTool.new(), "white": SurfaceTool.new(), "cover": SurfaceTool.new()}
		for st in layers.values():
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for m in merges:
			RampMerge.draw(m, layers.asphalt, layers.white, layers.cover)
		for key in layers:
			var mi := MeshInstance3D.new()
			mi.mesh = layers[key].commit()
			mi.material_override = _mats.white if key == "white" else _mats.asphalt
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	if any_bridge:
		piers.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = piers.commit()
		mi.material_override = _mats.concrete
		add_child(mi)
	# Fill each junction and road end so curves meet cleanly.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_nodes := {}
	for id in network.segments:
		if RoadStyle.is_ring(network.segments[id].type):
			var hw := RoadStyle.half_width(network.segments[id].type)
			ring_nodes[network.segments[id].a] = hw
			ring_nodes[network.segments[id].b] = hw
	for id in network.nodes:
		if network.nodes[id].y < -1.0 or ring_nodes.has(id):
			continue  # rings meet their roads without a pad over the island
		var r := RoadStyle.half_width(network.widest_at(id))
		RoadMesh.add_disc(st, network.nodes[id], r, RoadStyle.Y_JUNCTION)
	if not network.nodes.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mats.asphalt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


	_build_roundabouts(ring_nodes)


## Each roundabout's planted centre island and concrete truck apron, and a
## raised splitter island on every road leading in (FHWA roundabout guide).
func _build_roundabouts(ring_nodes: Dictionary) -> void:
	var circles := {}
	for id in network.segments:
		var type: int = network.segments[id].type
		if not RoadStyle.is_ring(type):
			continue
		var c := network.curve_of(id)
		var circle := RoadShapes.arc_circle(c)
		if circle.is_empty():
			continue
		var key := Vector2i(roundi(circle[0].x), roundi(circle[0].z))
		circles[key] = [Vector3(circle[0].x, c[0].y, circle[0].z), circle[1], RoadStyle.half_width(type)]
	if circles.is_empty():
		return
	var grass := SurfaceTool.new()
	var apron := SurfaceTool.new()
	var curb := SurfaceTool.new()
	for st in [grass, apron, curb]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in circles:
		var center: Vector3 = circles[key][0]
		var inner: float = circles[key][1] - circles[key][2]
		var island := maxf(inner - RoadStyle.TRUCK_APRON, 2.0)
		_add_ring(apron, center, island, inner, RoadStyle.Y_JUNCTION + 0.03)
		_add_ring(curb, center, island - 0.3, island, RoadStyle.Y_JUNCTION + 0.08)
		RoadMesh.add_disc(grass, center, island - 0.3, RoadStyle.Y_JUNCTION + 0.1, 48)
	# Splitter islands: a raised teardrop down the middle of each approach.
	for id in network.segments:
		var s: Dictionary = network.segments[id]
		if RoadStyle.is_ring(s.type) or network.is_oneway(id) or RoadStyle.TYPES[s.type].median > 0.0:
			continue
		for end in [s.a, s.b]:
			if not ring_nodes.has(end):
				continue
			var pts := network.sample_segment(id, 32)
			if end == s.b:
				pts.reverse()
			var length := RoadNetwork.polyline_length(pts)
			var start: float = ring_nodes[end] + 1.5
			if length < start + 20.0:
				continue
			_add_splitter(curb, pts, start, 15.0, 2.0)
	for entry in [[grass, _mats.median], [apron, _mats.apron], [curb, _mats.curb]]:
		var mi := MeshInstance3D.new()
		mi.mesh = entry[0].commit()
		mi.material_override = entry[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


static func _add_ring(st: SurfaceTool, center: Vector3, r0: float, r1: float, y: float, steps := 48) -> void:
	var c := center + Vector3(0, y, 0)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for v in [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d0 * r0, c + d1 * r1, c + d1 * r0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## A tapering island along a road's centre line, from `start` metres out to
## `start + length`, `width` wide at the ring end.
static func _add_splitter(st: SurfaceTool, pts: PackedVector3Array, start: float, length: float, width: float) -> void:
	var cum := 0.0
	var last := []  # previous [left, right]
	for i in range(pts.size() - 1):
		var d := cum
		cum += pts[i].distance_to(pts[i + 1])
		if d < start or d > start + length:
			continue
		var dir := (pts[i + 1] - pts[i]).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var hw := maxf(width * 0.5 * (1.0 - (d - start) / length), 0.15)
		var p := pts[i] + Vector3(0, RoadStyle.Y_JUNCTION + 0.08, 0)
		var now := [p - side * hw, p + side * hw]
		if not last.is_empty():
			for v in [last[0], now[1], last[1], last[0], now[0], now[1]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		last = now


## True when the middle of a road runs below ground.
static func _underground(pts: PackedVector3Array) -> bool:
	return pts[pts.size() / 2].y < -1.0
