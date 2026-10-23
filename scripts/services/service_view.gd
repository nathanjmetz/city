class_name ServiceView
extends Node3D
## Draws service buildings (built by the art library's CivicBuilder) and,
## while placing one, which roads it would cover.

var sim: CitySim
## The kind whose coverage to show on the roads, or -1 for none.
var show_kind := -1:
	set(v):
		show_kind = v
		_draw_coverage()

var _nodes := {}  # service id -> Node3D
var _coverage := MeshInstance3D.new()
var _cover_mat := StandardMaterial3D.new()
var _trees := TreeField.new()
static var _footing_mat: Material


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.lots_changed.connect(_sync)
	sim.stats_changed.connect(_draw_coverage)
	_cover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cover_mat.albedo_color = Color(0.35, 0.85, 0.45, 0.45)
	_cover_mat.no_depth_test = true
	_coverage.material_override = _cover_mat
	_coverage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coverage)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		# Gone, moved with Move It, or grown onto the land next door.
		if not sim.services.buildings.has(id) or not _nodes[id].get_meta("at").is_equal_approx(
				Transform3D(Basis.looking_at(sim.services.buildings[id].dir, Vector3.UP), sim.services.buildings[id].pos)) \
				or _nodes[id].get_meta("size") != Services.size_of(sim.services.buildings[id]):
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id in sim.services.buildings:
		# A hospital that grew (or gave back) a building is drawn afresh.
		if _nodes.has(id) and _nodes[id].get_meta("look") != _look(id):
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
		if not _nodes.has(id):
			_nodes[id] = _spawn(id, sim.services.buildings[id])
	_draw_coverage()


## Roads within reach of the shown kind turn green; utilities light up every
## road they flow along.
func _draw_coverage() -> void:
	_coverage.visible = show_kind != -1 and sim.services.reach_by_kind.has(show_kind)
	if not _coverage.visible:
		return
	var dist: Dictionary = sim.services.reach_by_kind[show_kind]
	var reach: float = Services.KINDS[show_kind].get("reach", INF)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.network.segments:
		var s: Dictionary = sim.network.segments[id]
		if dist.get(s.a, INF) <= reach or dist.get(s.b, INF) <= reach:
			var hw := RoadStyle.half_width(s.type)
			RoadMesh.add_strip(st, sim.network.sample_segment(id), -hw, hw, 0.35)
			any = true
	_coverage.visible = any
	if any:
		_coverage.mesh = Terrain.drape(st.commit())


## What a building looks like, so a change shows: its size, and a hospital's
## buildings.
func _look(id: int) -> String:
	var b: Dictionary = sim.services.buildings[id]
	var hub: Dictionary = sim.healthcare.hubs.get(id, {})
	return str([Services.size_of(b), hub.get("pieces", []), hub.get("level", 0)])


func _spawn(id: int, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(b.pos)
	# Local -Z faces the road.
	root.basis = Basis.looking_at(b.dir, Vector3.UP)
	root.set_meta("at", root.transform)
	var size: Vector2 = Services.size_of(b)
	root.set_meta("size", size)
	# Paved footing under the site, its edge running down into the ground on a slope.
	var footing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 3.0, size.y)
	footing.mesh = box
	footing.position = Vector3(0, -1.55, 0)
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	footing.material_override = _footing_mat
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(footing)
	var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	# Seeded from the front door, which stays put as a hospital grows.
	var door: Vector3 = sim.healthcare.hubs[id].front if sim.healthcare.hubs.has(id) else b.pos + b.dir * size.y * 0.5
	var seed := int(door.x * 73.0) ^ int(door.z * 151.0) ^ (int(b.kind) << 20)
	var built: Array
	if int(b.kind) in Services.CARE:
		built = HealthBuilder.build_care(int(b.kind), seed, size, to_curb, sim.healthcare.hubs.get(id, {}))
	else:
		built = CivicBuilder.build_service(int(b.kind), seed, size, to_curb)
	built[1] = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	root.set_meta("tree_key", str(b.pos))
	root.set_meta("look", _look(id))
	# It goes up stage by stage (ConstructionSite); trees go in at the end.
	var ref := "svc:%d" % id
	ConstructionSite.add_to(root, built, "civic", func(): return sim.construction.state(ref, sim.tick_count),
		func():
			if not is_instance_valid(root):
				return
			var frame := Transform3D(root.basis, root.position)
			var trees := []
			for t in built[2]:
				var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
				trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
			_trees.set_trees(str(b.pos), trees))
	return root


