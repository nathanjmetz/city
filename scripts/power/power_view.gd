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
const POLE := Color(0.36, 0.29, 0.22)  # weathered treated pine
const INSULATOR := Color(0.62, 0.64, 0.6)
const WIRE := Color(0.32, 0.33, 0.34)
const FENCE := Color(0.6, 0.62, 0.62)

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
	sim.network.changed.connect(_rebuild)
	_rebuild()
	_loaded = true


func _process(delta: float) -> void:
	_time += delta
	for i in _rotors.size():
		var r = _rotors[i]
		if is_instance_valid(r):
			r.rotation.z = _time * 1.4 + i * 0.7  # about 13 rpm


## A company is redrawn when its plant, units or add-ons change.
## So is its line to the neighbors when the roads it follows change.
func _stamp(s: Dictionary) -> String:
	var tie := _tie(s)
	return "%s|%s|%s|%d|%s" % [s.plant, str(s.cells), str(s.built), tie.size(), tie[-1] if tie.size() > 0 else ""]


func _tie(s: Dictionary) -> PackedVector3Array:
	return sim.power.tie_route(sim.network, sim.region_links, s)


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
	for lane in Power.lanes(s):
		RoadMesh.add_strip(st, PackedVector3Array(lane), -2.0, 2.0, 0.1)
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
			"hydro": pass
	if s.plant == "hydro" and not s.cells.is_empty():
		_dam(root, s)
	var tie := _tie(s)
	_line(root, tie)
	_substation(root, tie)
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


## A 69 kV line on single wood poles: an 18 m pole with a crossarm and
## three conductors, sagging about 1.5 m mid-span (real rural co-op
## subtransmission). The wires are merged into the batch like the rest.
func _line(root: Node3D, route: PackedVector3Array) -> void:
	var spots := Power.poles(route)
	if spots.size() < 2:
		return
	var tops := []
	for i in spots.size():
		var p := spots[i]
		var ahead := spots[mini(i + 1, spots.size() - 1)] - spots[maxi(i - 1, 0)]
		ahead.y = 0.0
		var basis := Basis.looking_at(ahead.normalized() if ahead.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
		var n := _node(root, p, basis)
		_cyl(n, 0.16, 18.0, Vector3(0, 9.0, 0), POLE)
		_box(n, Vector3(3.6, 0.15, 0.15), Vector3(0, 17.2, 0), POLE)
		var arms := []
		for x in [-1.6, 0.0, 1.6]:
			_box(n, Vector3(0.12, 0.5, 0.12), Vector3(x, 17.55 + (0.6 if x == 0.0 else 0.0), 0), INSULATOR)
			arms.append(n.transform * Vector3(x, 17.8 + (0.6 if x == 0.0 else 0.0), 0))
		tops.append(arms)
	for i in range(1, tops.size()):
		for k in 3:
			var a: Vector3 = tops[i - 1][k]
			var b: Vector3 = tops[i][k]
			var prev := a
			for j in range(1, 5):
				var t := j / 4.0
				var q := a.lerp(b, t) - Vector3(0, 4.0 * Balance.POWER_TIE_SAG * t * (1.0 - t), 0)
				_wire(prev, q)
				prev = q


func _wire(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.05, len)
	if not _batch.has(WIRE):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[WIRE] = st
	var basis := Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	(_batch[WIRE] as SurfaceTool).append_from(m, 0, Transform3D(basis, (a + b) * 0.5))


## The metering substation at the end of the line: a gravel yard inside
## a chain-link fence, a wood H-frame dead-end where the line lands, a bank
## of three regulators, the meter cabinet and a small control house.
func _substation(root: Node3D, route: PackedVector3Array) -> void:
	var sub := Power.substation(route)
	if sub.is_empty():
		return
	var t: Vector3 = sub[1]
	var n := _node(root, sub[0], Basis.looking_at(Vector3(-t.z, 0.0, t.x), Vector3.UP))
	var w: float = Balance.POWER_SUBSTATION_SIZE.x
	var d: float = Balance.POWER_SUBSTATION_SIZE.y
	# Graded flat: the pad is cut into the slope, its top just above grade.
	_box(n, Vector3(w, 1.6, d), Vector3(0, -0.5, 0), GRAVEL)
	# Chain-link: posts every 3 m with a top rail and line wires.
	for side in [-1.0, 1.0]:
		for i in int(w / 3.0) + 1:
			_box(n, Vector3(0.08, 2.4, 0.08), Vector3(-w * 0.5 + i * w / int(w / 3.0), 1.5, side * d * 0.5), FENCE)
		for i in int(d / 3.0) + 1:
			_box(n, Vector3(0.08, 2.4, 0.08), Vector3(side * w * 0.5, 1.5, -d * 0.5 + i * d / int(d / 3.0)), FENCE)
		for y in [0.9, 1.8, 2.6]:
			_box(n, Vector3(w, 0.04, 0.04), Vector3(0, y, side * d * 0.5), FENCE)
			_box(n, Vector3(0.04, 0.04, d), Vector3(side * w * 0.5, y, 0), FENCE)
	# The line comes in from the road side (-z) onto the H-frame.
	for x in [-3.0, 3.0]:
		_cyl(n, 0.2, 14.0, Vector3(x, 7.0, d * 0.5 - 5.0), POLE)
	_box(n, Vector3(7.6, 0.3, 0.3), Vector3(0, 12.8, d * 0.5 - 5.0), POLE)
	for i in 3:
		_box(n, Vector3(1.6, 3.0, 1.6), Vector3(-4.0 + i * 4.0, 1.5, 0.0), Color(0.5, 0.53, 0.5))  # regulators
	_box(n, Vector3(1.2, 2.0, 0.8), Vector3(8.0, 1.0, -2.0), STEEL)  # meter cabinet
	_box(n, Vector3(6.0, 3.2, 4.0), Vector3(-w * 0.5 + 5.0, 1.6, -d * 0.5 + 4.0), Color(0.78, 0.76, 0.7))  # control house


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


## A low-head run-of-river dam, like Norway Dam on the Tippecanoe: a
## concrete weir bank to bank across the flow with piers every 12 m, and
## the powerhouse on the bank nearer the yard, one turbine bay per unit.
func _dam(root: Node3D, s: Dictionary) -> void:
	var span: Array = sim.power.dam_span(Power.cell_center(s, s.cells[0]))
	if span.size() < 2:
		return
	var a: Vector3 = span[0]
	var b: Vector3 = span[1]
	if b.distance_to(s.pos) < a.distance_to(s.pos):
		var t := a
		a = b
		b = t
	var length := maxf(a.distance_to(b), 20.0)
	var along := (b - a).normalized() if a.distance_to(b) > 1.0 else Vector3.RIGHT
	var n := _node(root, (a + b) * 0.5, Basis.looking_at(Vector3(-along.z, 0.0, along.x), Vector3.UP))
	# The weir sits on the river's surface, not its bed (as rail bridges do).
	var m := (a + b) * 0.5
	n.position.y = maxf(n.position.y, Terrain.water_level(m.x + Terrain.shift.x + Terrain.view_origin.x,
		m.z + Terrain.shift.y + Terrain.view_origin.y))
	# An overflow weir from bank to bank, its crest a little over the pool,
	# with white water spilling down its face; a gated section with piers
	# beside the powerhouse.
	_box(n, Vector3(length + 8.0, 3.2, 7.0), Vector3(0, 0.4, 0), CONCRETE)
	_box(n, Vector3(length, 0.3, 5.0), Vector3(0, 0.15, 5.5), WHITE)
	var gates := mini(4, maxi(1, int(length / 30.0)))
	for i in gates + 1:
		var px := length * 0.5 - i * 10.0
		_box(n, Vector3(1.8, 7.0, 10.0), Vector3(px, 2.5, 0), CONCRETE)
		if i < gates:
			_box(n, Vector3(8.2, 1.0, 1.2), Vector3(px - 5.0, 5.4, -1.0), STEEL)  # gate leaf, raised
	_box(n, Vector3(gates * 10.0 + 1.8, 0.8, 4.0), Vector3(length * 0.5 - gates * 5.0, 6.4, 0), CONCRETE)  # hoist deck
	# Powerhouse on the yard's bank: one bay per unit.
	var bays: int = s.cells.size()
	var house := 10.0 + 9.0 * bays
	var hx := length * 0.5 + house * 0.5 - 4.0  # +x runs toward the yard bank
	_box(n, Vector3(house, 11.0, 18.0), Vector3(hx, 4.5, 3.0), Color(0.66, 0.64, 0.6))
	_box(n, Vector3(house + 0.6, 0.6, 18.6), Vector3(hx, 10.3, 3.0), Color(0.3, 0.3, 0.32))
	for i in bays:
		_box(n, Vector3(6.0, 2.0, 2.0), Vector3(hx - house * 0.5 + 9.0 * i + 9.5, 9.0, -6.5), STEEL)  # gate hoists


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
