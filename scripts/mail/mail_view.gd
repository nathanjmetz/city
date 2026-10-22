class_name MailView
extends Node3D
## Draws the post office (PostOfficeBuilder), the carriers parked in its lot
## while they're in, and a curbside mailbox at every home: a post with a
## box at the curb, the way carriers reach them from the driver's seat.

var sim: CitySim
var _nodes := {}  # office id -> Node3D (meta "ver")
var _stalls := {}  # office id -> [[Transform3D, ...]] world stalls
var _trees := TreeField.new()
var _seen := -1
var _mail: Mail
var _parked := MultiMeshInstance3D.new()
var _parked_key := ""
var _boxes := MultiMeshInstance3D.new()
var _boxes_dirty := true
var _clock := 0.0


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	var mat := VehicleMaterial.get_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = VehicleModels.build(_carrier_kind(), 0)
	_parked.multimesh = mm
	_parked.material_override = mat
	add_child(_parked)
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.mesh = _mailbox_mesh()
	_boxes.multimesh = bm
	_boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boxes)
	sim.buildings_changed.connect(func(): _boxes_dirty = true)
	sim.lots_changed.connect(func(): _boxes_dirty = true)


## The model the carriers drive (the Vehicles thread's pick for "mail").
static func _carrier_kind() -> String:
	var w: Dictionary = VehicleTypes.PURPOSE.get("mail", {"van": 1.0})
	return w.keys()[0]


func _process(delta: float) -> void:
	if sim.mail != _mail or sim.mail.version != _seen:
		_mail = sim.mail
		_seen = sim.mail.version
		_redraw()
		_parked_key = ""
	_clock += delta
	if _clock >= 0.5:
		_clock = 0.0
		_park()
		if _boxes_dirty:
			_boxes_dirty = false
			_mailboxes()


func _redraw() -> void:
	for id in _nodes.keys():
		var h = sim.mail.offices.get(id)
		if h == null or int(h.get("ver", 0)) != int(_nodes[id].get_meta("ver")):
			_trees.remove("mail:%d" % id)
			_nodes[id].queue_free()
			_nodes.erase(id)
			_stalls.erase(id)
	for id in sim.mail.offices:
		if not _nodes.has(id):
			_nodes[id] = _spawn(id, sim.mail.offices[id])


func _spawn(id: int, h: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = h.pos
	root.basis = Basis.looking_at(h.dir, Vector3.UP)
	root.set_meta("ver", int(h.get("ver", 0)))
	var to_curb := CivicHubs.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var seed := int(h.pos.x * 73.0) ^ int(h.pos.z * 151.0) ^ (id << 16)
	var built := PostOfficeBuilder.build_office(h, seed, to_curb)
	var building := MeshInstance3D.new()
	building.mesh = built[0]
	root.add_child(building)
	var ground := MeshInstance3D.new()
	ground.mesh = built[1]
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	_trees.set_trees("mail:%d" % id, trees)
	var stalls := []
	for s in built[3]:
		# Model origin is the front bumper; nose toward the stall's end.
		stalls.append(frame * Transform3D(Basis(Vector3.UP, s[1]), s[0]))
	_stalls[id] = stalls
	return root


## Carriers that are in sit in the lot; they leave it when they go out.
func _park() -> void:
	var xs := []
	var ids := sim.mail.offices.keys()
	ids.sort()
	for id in ids:
		var stalls: Array = _stalls.get(id, [])
		var n := mini(stalls.size(), sim.mail.carriers(id) - sim.mail.out(id, ["carrier", "rural"]))
		for i in maxi(n, 0):
			xs.append(stalls[i])
	var key := str(xs.size()) + str(ids)
	if key == _parked_key:
		return
	_parked_key = key
	var mm := _parked.multimesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(0.93, 0.93, 0.92, 0.0))  # postal white


## A mailbox at the curb in front of each home, beside the driveway.
func _mailboxes() -> void:
	var xs := []
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		var n: Vector3 = lot.normal
		var along: Vector3 = lot.dir
		var p: Vector3 = lot.front - n * maxf(float(lot.get("to_curb", 4.0)) - 0.5, 0.3) \
			+ along * float(lot.get("width", 15.0)) * 0.3
		xs.append(Transform3D(Basis.looking_at(-n, Vector3.UP), Vector3(p.x, 0.0, p.z)))
	var mm := _boxes.multimesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])


## A black rural mailbox on a wooden post; the door faces the street (-z).
static func _mailbox_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cube(st, Vector3(0, 0.55, 0.05), Vector3(0.1, 1.1, 0.1), Color("#6b5640"))
	_cube(st, Vector3(0, 1.17, 0.0), Vector3(0.2, 0.17, 0.5), Color("#222426"))
	_cube(st, Vector3(0, 1.27, 0.0), Vector3(0.14, 0.06, 0.48), Color("#222426"))
	_cube(st, Vector3(0.115, 1.25, 0.12), Vector3(0.02, 0.14, 0.04), Color("#c0312b"))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	mesh.surface_set_material(0, mat)
	return mesh


static func _cube(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	st.set_color(col)
	StreetLights._box(st, c, size)
