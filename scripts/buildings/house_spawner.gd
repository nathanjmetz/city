class_name HouseSpawner
extends Node3D
## Grows simple placeholder houses along both sides of every road, like zoning
## in Cities: Skylines. Lots are worked out from the roads alone, so the same
## roads always give the same houses (handy for multiplayer later).

signal house_count_changed(count: int)

const LOT_FRONTAGE := 20.0
## Front yard depth, from the back of the sidewalk to the house.
const SETBACK := 7.0
## Keep corners near junctions empty.
const END_MARGIN := 14.0
const SPAWN_INTERVAL := 0.08

const SIDING := [
	Color(0.93, 0.92, 0.88), Color(0.86, 0.82, 0.72), Color(0.70, 0.76, 0.80),
	Color(0.62, 0.64, 0.63), Color(0.66, 0.71, 0.60), Color(0.80, 0.73, 0.62),
	Color(0.55, 0.30, 0.26),
]
const ROOFS := [Color(0.24, 0.24, 0.26), Color(0.33, 0.29, 0.26), Color(0.40, 0.40, 0.42)]

var network: RoadNetwork
var _houses := {}  # lot key -> Node3D
var _queue := []   # lot dictionaries waiting to grow
var _timer := 0.0
var _dirty := false
var _materials := {}


func setup(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(func(): _dirty = true)
	_dirty = true


func count() -> int:
	return _houses.size()


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_refresh()
	_timer -= delta
	while _timer <= 0.0 and not _queue.is_empty():
		_timer += SPAWN_INTERVAL
		var lot: Dictionary = _queue.pop_front()
		if not _houses.has(lot.key):
			_houses[lot.key] = _spawn(lot)
			house_count_changed.emit(_houses.size())
	if _queue.is_empty():
		_timer = maxf(_timer, 0.0)


func _refresh() -> void:
	var lots := _plan_lots()
	var wanted := {}
	for lot in lots:
		wanted[lot.key] = true
	for key in _houses.keys():
		if not wanted.has(key):
			_houses[key].queue_free()
			_houses.erase(key)
	_queue.clear()
	for lot in lots:
		if not _houses.has(lot.key):
			_queue.append(lot)
	house_count_changed.emit(_houses.size())


func _plan_lots() -> Array:
	var lines := {}
	for id in network.segments:
		lines[id] = network.sample_segment(id, 48)
	var placed := []
	var lots := []
	var seg_ids := network.segments.keys()
	seg_ids.sort()
	for id in seg_ids:
		var pts: PackedVector3Array = lines[id]
		var length := RoadNetwork.polyline_length(pts)
		var usable := length - END_MARGIN * 2.0
		if usable < 0.0:
			continue
		var n := int(usable / LOT_FRONTAGE) + 1
		var start := END_MARGIN + (usable - (n - 1) * LOT_FRONTAGE) * 0.5
		for side in [-1, 1]:
			for i in n:
				var lot := _make_lot(id, side, i, pts, start + i * LOT_FRONTAGE)
				if _fits(lot, lines, placed):
					placed.append(lot.pos)
					lots.append(lot)
	return lots


func _make_lot(seg: int, side: int, index: int, pts: PackedVector3Array, at: float) -> Dictionary:
	var key := "%d:%d:%d" % [seg, side, index]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var width := rng.randf_range(9.0, 13.0)
	var depth := rng.randf_range(8.0, 10.5)
	var road := _point_at(pts, at)
	var dir: Vector3 = road[1]
	var normal := Vector3(-dir.z, 0.0, dir.x) * side
	var offset := RoadStyle.right_of_way_half() + SETBACK + depth * 0.5
	return {
		"key": key,
		"pos": road[0] + normal * offset,
		"facing": -normal,
		"offset": offset,
		"width": width,
		"depth": depth,
		"stories": 2 if rng.randf() < 0.35 else 1,
		"siding": SIDING[rng.randi() % SIDING.size()],
		"roof": ROOFS[rng.randi() % ROOFS.size()],
		"drive_left": rng.randf() < 0.5,
	}


func _fits(lot: Dictionary, lines: Dictionary, placed: Array) -> bool:
	var clearance: float = RoadStyle.right_of_way_half() + 2.0 + maxf(lot.width, lot.depth) * 0.5
	for id in lines:
		var pts: PackedVector3Array = lines[id]
		for i in range(pts.size() - 1):
			var q := Geometry3D.get_closest_point_to_segment(lot.pos, pts[i], pts[i + 1])
			if q.distance_to(lot.pos) < clearance:
				return false
	for p in placed:
		if p.distance_to(lot.pos) < 15.0:
			return false
	return true


func _point_at(pts: PackedVector3Array, at: float) -> Array:
	var dist := 0.0
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		if dist + d >= at or i == pts.size() - 2:
			var f := clampf((at - dist) / maxf(d, 0.001), 0.0, 1.0)
			var dir := Vector3(pts[i + 1].x - pts[i].x, 0.0, pts[i + 1].z - pts[i].z).normalized()
			return [pts[i].lerp(pts[i + 1], f), dir]
		dist += d
	return [pts[0], Vector3.FORWARD]


func _spawn(lot: Dictionary) -> Node3D:
	var house := Node3D.new()
	add_child(house)
	house.position = lot.pos
	# Local -Z faces the street.
	house.basis = Basis.looking_at(lot.facing, Vector3.UP)

	var w: float = lot.width
	var d: float = lot.depth
	var wall_h: float = 2.8 * lot.stories + 0.4

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, wall_h, d)
	body.mesh = box
	body.position.y = wall_h * 0.5
	body.material_override = _mat(lot.siding)
	house.add_child(body)

	var roof := MeshInstance3D.new()
	roof.mesh = _gable_roof(w + 0.8, d + 0.8, d * 0.28)
	roof.position.y = wall_h
	roof.material_override = _mat(lot.roof)
	house.add_child(roof)

	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.0, 2.1, 0.1)
	door.mesh = door_box
	door.position = Vector3(0.0, 1.05, -d * 0.5 - 0.04)
	door.material_override = _mat(Color(0.35, 0.22, 0.15))
	house.add_child(door)

	# Driveway from the garage side out to the street.
	var drive_len: float = lot.offset - d * 0.5 - RoadStyle.half_width()
	var drive := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.4, drive_len)
	drive.mesh = plane
	var drive_x: float = (w * 0.5 - 2.0) * (-1.0 if lot.drive_left else 1.0)
	drive.position = Vector3(drive_x, 0.03, -d * 0.5 - drive_len * 0.5)
	drive.material_override = _mat(Color(0.68, 0.67, 0.64))
	drive.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	house.add_child(drive)

	# Grow in, like a new house going up.
	house.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(house, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return house


func _mat(c: Color) -> StandardMaterial3D:
	if not _materials.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[c] = m
	return _materials[c]


## A simple gable roof with its ridge running left to right.
static func _gable_roof(w: float, d: float, h: float) -> ArrayMesh:
	var x := w * 0.5
	var z := d * 0.5
	var fl := Vector3(-x, 0, -z)
	var fr := Vector3(x, 0, -z)
	var bl := Vector3(-x, 0, z)
	var br := Vector3(x, 0, z)
	var rl := Vector3(-x, h, 0)
	var rr := Vector3(x, h, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [
		[fl, rl, rr], [fl, rr, fr],  # front slope
		[br, rr, rl], [br, rl, bl],  # back slope
		[bl, rl, fl], [fr, rr, br],  # gable ends
	]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
