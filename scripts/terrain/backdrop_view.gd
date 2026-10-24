class_name BackdropView
extends Node3D
## Draws the backdrop towns (Backdrop: Marion, Gas City, Jonesboro) as they
## stand: every real building as a box of its real footprint and height,
## with a pitched roof on the houses, and every street, from
## terrain/grant_in/backdrop.bin (tools/terrain/build_roads.py). Nothing in
## them is simulated, so they cost only what they draw: one mesh per 2 km
## block (a few dozen draw calls for all three towns), built once, a few
## 256 m squares a frame.
##
## Benchmark: aerial photos of Marion, Indiana: brick and frame houses on a
## street grid, a downtown of two- to four-storey blocks round the
## courthouse, mills and warehouses along the rail and the river.

## Side of the squares the town is built in, a few a frame, metres.
const CHUNK := 256.0
## Squares per side of a block, which is drawn as one mesh.
const BLOCK := 8
## Time to spend building squares each frame, ms (the web build has no threads).
const BUDGET_MS := 3.0
## Street widths, metres, by class: alley or drive, street, arterial.
const WIDTHS := [5.0, 9.0, 13.0]
## A house-sized building (footprint m², height m) gets a pitched roof.
const HOUSE_AREA := 260.0
const HOUSE_HEIGHT := 9.0

const WALLS := [Color(0.62, 0.33, 0.27), Color(0.86, 0.85, 0.80), Color(0.78, 0.74, 0.64),
	Color(0.55, 0.57, 0.58), Color(0.70, 0.60, 0.48), Color(0.90, 0.89, 0.86), Color(0.50, 0.29, 0.24)]
const ROOFS := [Color(0.24, 0.24, 0.25), Color(0.32, 0.27, 0.24), Color(0.40, 0.40, 0.41), Color(0.20, 0.21, 0.23)]
const FLAT_ROOF := Color(0.45, 0.45, 0.44)
const ASPHALT := Color(0.27, 0.27, 0.28)

## Region square -> [buildings [Array of 6 numbers]], [streets [class, PackedVector2Array]]
var _todo := {}
var _origin := Vector2.INF
## Squares still to build, a block's together.
var _queue: Array = []
## Block -> [squares left, vertices, normals, colours]
var _blocks := {}
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_load()


## Reads the town and files it by square, to be built over the next frames.
func _load() -> void:
	var raw := FileAccess.get_file_as_bytes(Terrain.DIR + "backdrop.bin")
	if raw.is_empty():
		return
	var data := raw.decompress_dynamic(16 << 20, FileAccess.COMPRESSION_GZIP)
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "BKD1":
		push_error("BackdropView: can't read backdrop.bin")
		return
	var at := 4
	var n := data.decode_u32(at)
	at += 4
	for i in n:
		var b := [data.decode_s16(at), data.decode_s16(at + 2), data.decode_s16(at + 4) * 0.1,
			data.decode_s16(at + 6) * 0.1, data.decode_s16(at + 8) * 0.1, data.decode_s16(at + 10) * 0.01]
		at += 12
		_square(Vector2(b[0], b[1]))[0].append(b)
	n = data.decode_u32(at)
	at += 4
	for i in n:
		var k := data.decode_u8(at)
		var count := data.decode_u16(at + 1)
		at += 3
		var pts := PackedVector2Array()
		for j in count:
			pts.append(Vector2(data.decode_s16(at), data.decode_s16(at + 2)))
			at += 4
		# Filed by its first point; a street drawn into the next square is fine.
		_square(pts[0])[1].append([k, pts])


func _square(p: Vector2) -> Array:
	var c := Vector2i((p / CHUNK).floor())
	if not _todo.has(c):
		_todo[c] = [[], []]
	return _todo[c]


func _process(_delta: float) -> void:
	# Built where your own town sits in the region; rebuilt if that moves.
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for child in get_children():
			child.queue_free()
		_queue = _todo.keys()
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ba := Vector2i(floori(a.x / float(BLOCK)), floori(a.y / float(BLOCK)))
			var bb := Vector2i(floori(b.x / float(BLOCK)), floori(b.y / float(BLOCK)))
			return ba.x > bb.x or (ba.x == bb.x and ba.y > bb.y))
		_blocks.clear()
		for c in _queue:
			var k := _block(c)
			if not _blocks.has(k):
				_blocks[k] = [0, PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
			_blocks[k][0] += 1
	if _queue.is_empty():
		return
	var start := Time.get_ticks_msec()
	while not _queue.is_empty() and Time.get_ticks_msec() - start < BUDGET_MS:
		_build(_queue.pop_back())


func _block(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x / float(BLOCK)), floori(c.y / float(BLOCK)))


## Adds a square to its block, and draws the block once it's whole.
func _build(c: Vector2i) -> void:
	var sq: Array = _todo[c]
	var blk: Array = _blocks[_block(c)]
	var v: PackedVector3Array = blk[1]
	var nrm: PackedVector3Array = blk[2]
	var col: PackedColorArray = blk[3]
	var o := _origin
	for s in sq[1]:
		_street(v, nrm, col, s[1], WIDTHS[s[0]], o)
	for b in sq[0]:
		_building(v, nrm, col, b, o)
	blk[0] -= 1
	if blk[0] > 0 or v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	_blocks.erase(_block(c))


func _street(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		pts: PackedVector2Array, width: float, o: Vector2) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length() < 0.5:
			continue
		var side := Vector2(-d.y, d.x).normalized() * width * 0.5
		var q := [a + side, a - side, b - side, b + side]
		var y := []
		for p in q:
			y.append(Terrain.height(p.x, p.y) + 0.2)
		var w := []
		for k in 4:
			w.append(Vector3(q[k].x - o.x, y[k], q[k].y - o.y))
		_quad(v, nrm, col, w[0], w[1], w[2], w[3], ASPHALT)


func _building(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, b: Array, o: Vector2) -> void:
	var centre := Vector2(b[0], b[1])
	var ang := deg_to_rad(b[5])
	var u: Vector2 = Vector2(cos(ang), sin(ang)) * b[2] * 0.5
	var w: Vector2 = Vector2(-sin(ang), cos(ang)) * b[3] * 0.5
	var corners := [centre - u - w, centre + u - w, centre + u + w, centre - u + w]
	var lo := INF
	for p in corners:
		lo = minf(lo, Terrain.height(p.x, p.y))
	var y0 := lo - 0.4
	var h: float = b[4]
	var y1 := lo + h
	var pick := absi(hash(Vector2i(b[0], b[1])))
	var wall: Color = WALLS[pick % WALLS.size()]
	var pts := []
	for p in corners:
		pts.append(Vector2(p.x - o.x, p.y - o.y))
	var mid: Vector2 = (pts[0] + pts[2]) * 0.5
	for k in 4:
		var a: Vector2 = pts[k]
		var c: Vector2 = pts[(k + 1) % 4]
		var away := (a + c) * 0.5 - mid
		_quad(v, nrm, col, Vector3(a.x, y0, a.y), Vector3(c.x, y0, c.y), Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y),
			wall, Vector3(away.x, 0.0, away.y))
	var house: bool = b[2] * b[3] < HOUSE_AREA and h < HOUSE_HEIGHT
	if not house:
		_quad(v, nrm, col, Vector3(pts[0].x, y1, pts[0].y), Vector3(pts[3].x, y1, pts[3].y),
			Vector3(pts[2].x, y1, pts[2].y), Vector3(pts[1].x, y1, pts[1].y), FLAT_ROOF)
		return
	# A gable roof along the longer side, pitched about 6 in 12.
	var roof: Color = ROOFS[(pick / 7) % ROOFS.size()]
	var long_u: bool = b[2] >= b[3]
	var span: float = (b[3] if long_u else b[2]) * 0.5
	var ridge := y1 + span * 0.5
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var p2: Vector2 = pts[2]
	var p3: Vector2 = pts[3]
	if not long_u:
		var t := p0
		p0 = p1
		p1 = p2
		p2 = p3
		p3 = t
	# Ridge from the middle of side p0-p3 to the middle of side p1-p2.
	var r0 := (p0 + p3) * 0.5
	var r1 := (p1 + p2) * 0.5
	var R0 := Vector3(r0.x, ridge, r0.y)
	var R1 := Vector3(r1.x, ridge, r1.y)
	_quad(v, nrm, col, Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), R1, R0, roof)
	_quad(v, nrm, col, Vector3(p2.x, y1, p2.y), Vector3(p3.x, y1, p3.y), R0, R1, roof)
	var e0 := r0 - mid
	var e1 := r1 - mid
	_tri(v, nrm, col, Vector3(p3.x, y1, p3.y), Vector3(p0.x, y1, p0.y), R0, wall, Vector3(e0.x, 0.0, e0.y))
	_tri(v, nrm, col, Vector3(p1.x, y1, p1.y), Vector3(p2.x, y1, p2.y), R1, wall, Vector3(e1.x, 0.0, e1.y))


## Two triangles, a b c d round the face's edge; the face looks toward `out`.
static func _quad(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color, out := Vector3.UP) -> void:
	_tri(v, nrm, col, a, b, c, colour, out)
	_tri(v, nrm, col, a, c, d, colour, out)


static func _tri(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, colour: Color, out := Vector3.UP) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-8:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# Godot's fronts wind clockwise as seen from the front.
	v.append_array([a, c, b])
	nrm.append_array([n, n, n])
	col.append_array([colour, colour, colour])
