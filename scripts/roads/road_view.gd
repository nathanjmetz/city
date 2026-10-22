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
}


func setup(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	for id in network.segments:
		var mi := MeshInstance3D.new()
		mi.mesh = RoadMesh.street(network.sample_segment(id), network.segments[id].type, _mats)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# Fill each junction and road end so curves meet cleanly.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id in network.nodes:
		var r := RoadStyle.half_width(network.widest_at(id))
		RoadMesh.add_disc(st, network.nodes[id], r, RoadStyle.Y_JUNCTION)
	if not network.nodes.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mats.asphalt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
