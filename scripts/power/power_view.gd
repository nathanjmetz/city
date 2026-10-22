class_name PowerView
extends Node3D
## Draws power companies: the yard (switchyard and control building) with
## its access road, every unit its leader has built, and the add-ons from
## its development tree. Real sizes: a 2.8 MW turbine's 90 m tower and
## 127 m rotor, a coal unit's 120 m stack, fixed-tilt panel rows. Turbine
## rotors turn; everything else is merged into one mesh per colour.
## Each yard and unit stands on the real land; lanes drape over it.
## Placeholders until the art library has these.

const GRAVEL := Color(0.6, 0.57, 0.5)
const LANE := Color(0.58, 0.47, 0.33)
const STEEL := Color(0.56, 0.58, 0.6)
const CONCRETE := Color(0.74, 0.72, 0.68)
const WHITE := Color(0.93, 0.94, 0.94)
const PANEL := Color(0.12, 0.17, 0.3)
const BRICK := Color(0.52, 0.3, 0.24)
const COAL := Color(0.12, 0.12, 0.13)

var sim: CitySim
var _sites := {}  # site id -> Node3D
var _rotors := []
var _mats := {}
var _batch := {}
var _loaded := false
var _time := 0.0


func setup(s: CitySim) -> void:
	sim = s
	sim.power_changed.connect(_rebuild)
	_rebuild()
	_loaded = true


func _process(delta: float) -> void:
	_time += delta
	for i in _rotors.size():
		var r = _rotors[i]
		if is_instance_valid(r):
			r.rotation.z = _time * 1.4 + i * 0.7  # about 13 rpm


## A company is redrawn when its plant, units or add-ons change.
static func _stamp(s: Dictionary) -> String:
	return "%s|%s|%s" % [s.plant, str(s.cells), str(s.built)]


func _rebuild() -> void:
	for id in _sites.keys():
		var s = sim.power.sites.get(id)
		if s == null or _sites[id].get_meta("stamp") != _stamp(s):
			_sites[id].queue_free()
			_sites.erase(id)
	_rotors = _rotors.filter(func(r): return is_instance_valid(r) and not r.is_queued_for_deletion())
	for id in sim.power.sites:
		if not _sites.has(id):
			_sites[id] = _site(sim.power.sites[id])


func _site(s: Dictionary) -> Node3D:
	_batch = {}
	var root := Node3D.new()
	root.set_meta("stamp", _stamp(s))
	add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if s.drive.size() >= 2:
		RoadMesh.add_strip(st, Terrain.densify(PackedVector3Array(s.drive), 6.0), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.12)
	for c in s.cells:
		var to := Vector2i.ZERO
		for d in [Vector2i(-signi(c.x), 0), Vector2i(0, -signi(c.y))]:
			if d != Vector2i.ZERO and (c + d == Vector2i.ZERO or (c + d) in s.cells):
				to = c + d
				break
		RoadMesh.add_strip(st, PackedVector3Array([Power.cell_center(s, c), Power.cell_center(s, to)]), -2.0, 2.0, 0.1)
	var flat := MeshInstance3D.new()
	flat.mesh = Terrain.drape(st.commit(), true, 8.0)
	flat.material_override = _mat(LANE)
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flat)
	var basis := Basis.looking_at(s.dir, Vector3.UP)
	var yard := _node(root, s.pos, basis)
	_yard(yard, s)
	for c in s.cells:
		var unit := _node(root, Power.cell_center(s, c), basis)
		match s.plant:
			"solar": _solar(unit)
			"wind": _turbine(root, unit)
			"gas": _gas(unit)
			"coal": _coal(unit, "scrubbers" in s.built)
			"hydro": _dam(unit)
	for color in _batch:
		var mi := MeshInstance3D.new()
		mi.mesh = (_batch[color] as SurfaceTool).commit()
		mi.material_override = _mat(color)
		root.add_child(mi)
	_batch = {}
	if _loaded:
		root.scale = Vector3(1.0, 0.01, 1.0)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _node(root: Node3D, at: Vector3, basis: Basis) -> Node3D:
	var n := Node3D.new()
	n.set_meta("static", true)
	# Each piece stands level on the land at its middle.
	n.position = Vector3(at.x, Terrain.ground_y(at.x, at.z), at.z)
	n.basis = basis
	root.add_child(n)
	return n


## Switchyard (gantries and transformers) and the control building, plus
## any add-on buildings from the tree along the back fence.
func _yard(n: Node3D, s: Dictionary) -> void:
	_box(n, Vector3(Power.HQ_SIZE.x, 0.1, Power.HQ_SIZE.y), Vector3.ZERO, GRAVEL)
	_box(n, Vector3(14, 4.5, 10), Vector3(-15, 2.25, 10), Color(0.82, 0.8, 0.74))  # control building
	_box(n, Vector3(14.6, 0.5, 10.6), Vector3(-15, 4.75, 10), Color(0.3, 0.3, 0.32))
	for i in 3:
		var x := -2.0 + i * 9.0
		_box(n, Vector3(4, 3.2, 3), Vector3(x, 1.6, 4), Color(0.42, 0.45, 0.4))  # transformer
		_box(n, Vector3(0.4, 12, 0.4), Vector3(x - 3, 6, -8), STEEL)  # gantry legs
		_box(n, Vector3(0.4, 12, 0.4), Vector3(x + 3, 6, -8), STEEL)
		_box(n, Vector3(6.4, 0.4, 0.4), Vector3(x, 12, -8), STEEL)
	var spots := [Vector3(-16, 0, -12), Vector3(18, 0, 14), Vector3(-2, 0, 15)]
	var k := 0
	for key in s.built:
		if k >= spots.size():
			break
		var at: Vector3 = spots[k]
		match key:
			"battery":  # shipping-container battery racks
				for j in 4:
					_box(n, Vector3(12, 2.6, 2.4), at + Vector3(0, 1.3, j * 3.2 - 4.8), WHITE)
			"training", "lab":
				_box(n, Vector3(12, 5, 9), at + Vector3(0, 2.5, 0), Color(0.78, 0.74, 0.66))
				_box(n, Vector3(12.4, 0.4, 9.4), at + Vector3(0, 5.2, 0), Color(0.28, 0.3, 0.33))
			"blade_yard":
				_box(n, Vector3(16, 8, 10), at + Vector3(0, 4, 0), STEEL)
			"tie_line", "steam":
				_cyl(n, 0.5, 18, at + Vector3(0, 9, 0), STEEL)
				_box(n, Vector3(6, 0.4, 0.4), at + Vector3(0, 17, 0), STEEL)
			_:
				continue
		k += 1


## Fixed-tilt rows facing south-ish: eight rows of panels on an 80 m cell.
func _solar(n: Node3D) -> void:
	_box(n, Vector3(76, 0.06, 76), Vector3(0, 0.03, 0), Color(0.42, 0.52, 0.3))  # mown grass
	for i in 8:
		var m := BoxMesh.new()
		m.size = Vector3(70, 0.12, 4.0)
		_add(n, m, Vector3(0, 1.6, -31.5 + i * 9.0), PANEL, Vector3(deg_to_rad(25.0), 0, 0))


## A 2.8 MW turbine: 90 m tapered tower, nacelle and a turning 127 m rotor.
func _turbine(root: Node3D, n: Node3D) -> void:
	_box(n, Vector3(36, 0.08, 36), Vector3(0, 0.04, 0), GRAVEL)
	var tower := CylinderMesh.new()
	tower.top_radius = 1.6
	tower.bottom_radius = 2.4
	tower.height = 90.0
	_add(n, tower, Vector3(0, 45, 0), WHITE)
	_box(n, Vector3(4, 4, 12), Vector3(0, 91.5, 1.5), WHITE)
	var hub := Node3D.new()
	hub.position = n.position + n.basis * Vector3(0, 91.5, -5)
	hub.basis = n.basis
	root.add_child(hub)
	var rotor := Node3D.new()
	hub.add_child(rotor)
	for b in 3:
		var blade := BoxMesh.new()
		blade.size = Vector3(2.2, 62, 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = blade
		mi.material_override = _mat(WHITE)
		var a := TAU * b / 3.0
		mi.rotation = Vector3(0, 0, a)
		mi.position = Vector3(-sin(a), cos(a), 0) * 32.0
		rotor.add_child(mi)
	_rotors.append(rotor)


## A reciprocating-engine hall with its exhaust stacks and radiators.
func _gas(n: Node3D) -> void:
	_box(n, Vector3(70, 0.1, 70), Vector3.ZERO, GRAVEL)
	_box(n, Vector3(40, 14, 22), Vector3(0, 7, 0), Color(0.7, 0.72, 0.74))
	for i in 3:
		_cyl(n, 1.2, 30, Vector3(-14 + i * 14.0, 15, -14), STEEL)
	_box(n, Vector3(30, 4, 10), Vector3(0, 2, 20), STEEL)


## An old coal unit: brick boiler house, a 120 m stack (sleeker with
## scrubbers' absorber tower beside it) and the coal pile.
func _coal(n: Node3D, scrubbed: bool) -> void:
	_box(n, Vector3(76, 0.1, 76), Vector3.ZERO, Color(0.36, 0.34, 0.32))
	_box(n, Vector3(32, 42, 26), Vector3(-10, 21, 6), BRICK)
	_box(n, Vector3(20, 22, 16), Vector3(16, 11, 10), Color(0.58, 0.55, 0.5))  # turbine hall
	var stack := CylinderMesh.new()
	stack.top_radius = 3.0
	stack.bottom_radius = 5.5
	stack.height = 120.0
	_add(n, stack, Vector3(-10, 60, -22), CONCRETE)
	_cyl(n, 3.2, 2.0, Vector3(-10, 112, -22), Color(0.7, 0.2, 0.15))  # red aviation band
	if scrubbed:
		_cyl(n, 7.0, 36, Vector3(14, 18, -20), CONCRETE)
	var pile := CylinderMesh.new()
	pile.top_radius = 2.0
	pile.bottom_radius = 16.0
	pile.height = 9.0
	_add(n, pile, Vector3(20, 4.5, -26), COAL)


## A low run-of-river dam bay with its powerhouse.
func _dam(n: Node3D) -> void:
	_box(n, Vector3(80, 8, 10), Vector3(0, 2, 0), CONCRETE)
	_box(n, Vector3(22, 10, 14), Vector3(-24, 5, 12), Color(0.66, 0.64, 0.6))


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(root, m, pos, color)


func _cyl(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _add(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	if not _batch.has(color):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[color] = st
	(_batch[color] as SurfaceTool).append_from(mesh, 0, root.transform * Transform3D(Basis.from_euler(rot), pos))


func _mat(color: Color) -> Material:
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	return _mats[color]
