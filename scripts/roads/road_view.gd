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
	for id in network.segments:
		var pts := network.sample_segment(id)
		var type: int = network.segments[id].type
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
	if any_bridge:
		piers.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = piers.commit()
		mi.material_override = _mats.concrete
		add_child(mi)
	# Fill each junction and road end so curves meet cleanly.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id in network.nodes:
		if network.nodes[id].y < -1.0:
			continue
		var r := RoadStyle.half_width(network.widest_at(id))
		RoadMesh.add_disc(st, network.nodes[id], r, RoadStyle.Y_JUNCTION)
	if not network.nodes.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mats.asphalt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## True when the middle of a road runs below ground.
static func _underground(pts: PackedVector3Array) -> bool:
	return pts[pts.size() / 2].y < -1.0
