class_name RoadView
extends Node3D
## Draws the road network. Rebuilds every mesh whenever the network changes,
## which is plenty fast for a small town.

var network: RoadNetwork

var _asphalt := RoadStyle.material(RoadStyle.ASPHALT_COLOR)
var _curb := RoadStyle.material(RoadStyle.CURB_COLOR)
var _walk := RoadStyle.material(RoadStyle.SIDEWALK_COLOR)


func setup(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	for id in network.segments:
		var mi := MeshInstance3D.new()
		mi.mesh = RoadMesh.street(network.sample_segment(id), _asphalt, _curb, _walk)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# Fill each junction and road end so curves meet cleanly.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id in network.nodes:
		RoadMesh.add_disc(st, network.nodes[id], RoadStyle.half_width(), RoadStyle.Y_JUNCTION)
	if not network.nodes.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _asphalt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
