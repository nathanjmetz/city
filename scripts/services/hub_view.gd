class_name HubView
extends Node3D
## Draws landfills, recycling centres and cemeteries (HubBuilder), redrawing
## a hub whenever it grows, shrinks or is upgraded.

var sim: CitySim
var _nodes := {}  # hub id -> Node3D (meta "ver": the hub version drawn)
var _trees := TreeField.new()
var _seen := -1
var _hubs: CivicHubs


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)


func _process(_delta: float) -> void:
	if sim.hubs == _hubs and sim.hubs.version == _seen:
		return
	_hubs = sim.hubs
	_seen = sim.hubs.version
	for id in _nodes.keys():
		var h = sim.hubs.hubs.get(id)
		if h == null or int(h.get("ver", 0)) != int(_nodes[id].get_meta("ver")):
			_trees.remove("hub:%d" % id)
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id in sim.hubs.hubs:
		if not _nodes.has(id):
			_nodes[id] = _spawn(id, sim.hubs.hubs[id])


func _spawn(id: int, h: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(h.pos)
	# Local -Z faces the road.
	root.basis = Basis.looking_at(h.dir, Vector3.UP)
	root.set_meta("ver", int(h.get("ver", 0)))
	var to_curb := CivicHubs.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var seed := int(h.pos.x * 73.0) ^ int(h.pos.z * 151.0) ^ (id << 16)
	var built := HubBuilder.build_hub(h, seed, to_curb)
	built[1] = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	# The rest of the site (mound, yard, fences, headstones) opens with the building.
	var site := MeshInstance3D.new()
	site.mesh = built[3]
	root.add_child(site)
	# The building goes up stage by stage (ConstructionSite); the site and its
	# trees come in once it's done.
	var ref := "hub:%d" % id
	site.visible = sim.construction.state(ref, sim.tick_count).is_empty()
	ConstructionSite.add_to(root, [built[0], built[1], built[2]], "shop",
		func(): return sim.construction.state(ref, sim.tick_count), _open.bind(id, root, site, built[2], built[4]))
	return root


## The finished hub: its site shows and its trees go in.
func _open(id: int, root: Node3D, site: MeshInstance3D, planted: Array, labels: Array) -> void:
	if not is_instance_valid(root) or _nodes.get(id, root) != root:
		return
	site.visible = true
	if not labels.is_empty() and not root.has_node("Signs"):
		var signs := Node3D.new()
		signs.name = "Signs"
		SignText.add(signs, labels)
		root.add_child(signs)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in planted:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		# A hub spans a lot of land, so each tree stands on its own patch of ground.
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2]])
	_trees.set_trees("hub:%d" % id, trees)
