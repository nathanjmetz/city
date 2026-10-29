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

## Colours from aerial and street photos of Marion: frame houses in vinyl
## and painted siding (white, cream, grey, pale blue, sage, yellow) with
## some red and brown brick; shingle roofs in greys and browns.
const HOUSE_WALLS := [Color(0.88, 0.87, 0.83), Color(0.80, 0.75, 0.64), Color(0.66, 0.68, 0.68),
	Color(0.62, 0.68, 0.72), Color(0.62, 0.66, 0.56), Color(0.85, 0.78, 0.55), Color(0.72, 0.62, 0.48),
	Color(0.55, 0.30, 0.24), Color(0.48, 0.32, 0.25), Color(0.86, 0.85, 0.80)]
const ROOFS := [Color(0.24, 0.24, 0.25), Color(0.32, 0.27, 0.24), Color(0.40, 0.40, 0.41), Color(0.20, 0.21, 0.23),
	Color(0.36, 0.30, 0.25), Color(0.45, 0.43, 0.40)]
## Stores, plants and warehouses: tan and grey block, tilt-up and metal
## panels, some brick.
const SHOP_WALLS := [Color(0.74, 0.68, 0.56), Color(0.62, 0.62, 0.60), Color(0.78, 0.76, 0.70),
	Color(0.58, 0.33, 0.26), Color(0.68, 0.64, 0.58), Color(0.42, 0.30, 0.24)]
## Downtown round the courthouse: two- to four-storey red and brown brick.
const BRICK := [Color(0.56, 0.30, 0.24), Color(0.50, 0.33, 0.26), Color(0.62, 0.40, 0.30), Color(0.45, 0.27, 0.22)]
## Flat roofs: white membrane on newer stores, grey ballast, black rubber, tar.
const FLAT_ROOFS := [Color(0.80, 0.81, 0.80), Color(0.52, 0.51, 0.49), Color(0.22, 0.22, 0.23), Color(0.34, 0.33, 0.32)]
## Share of wall that is glass (the far shader's window grid): houses,
## stores and plants, downtown blocks.
const GLASS := [0.14, 0.12, 0.3]
## A store or plant this big (m²) has a parking lot round it, about 1.3 m²
## of lot to each m² of floor (US suburban codes: 4 spaces per 1,000 ft²).
const LOT_AREA := 1500.0
const LOT_SHARE := 1.3
const LOT_ASPHALT := Color(0.33, 0.33, 0.33)
const ASPHALT := Color(0.27, 0.27, 0.28)
## Yard trees, desktop only. Marion's older neighbourhoods sit under
## mature maples, oaks and ashes (Indiana's urban canopy is about a third
## of residential land; aerial photos show a crown or two in most yards),
## so bare houses on lawns read as a model town. Trees per house by
## quality tier (Low, Medium, High, Ultra, Cinematic): a domed crown of
## 28 triangles each.
const TREES_PER_HOUSE := [0.0, 0.6, 1.1, 1.5, 1.8]
## Summer crowns, dark to light (vertex alpha under 0.5 marks foliage
## for the plain material: matte and broken into leaf clumps).
const CROWNS := [Color(0.29, 0.39, 0.19, 0.3), Color(0.33, 0.43, 0.21, 0.3), Color(0.26, 0.35, 0.17, 0.3),
	Color(0.36, 0.44, 0.23, 0.3), Color(0.30, 0.37, 0.21, 0.3)]

## Region square -> [buildings [Array of 6 numbers]], [streets [class, PackedVector2Array]]
var _todo := {}
var _origin := Vector2.INF
## Squares still to build, a block's together.
var _queue: Array = []
## Block -> [squares left, vertices, normals, colours, uvs, tree vertices, normals, colours]
var _blocks := {}
## The player town's far-building look (sRGB colours, windows, snow).
var _material: Material
## Yard trees per house for the current quality tier (TREES_PER_HOUSE).
var _trees := 0.0


func _ready() -> void:
	_material = HouseMaterials.get_mat("far")
	_load()
	var q := GraphicsQuality.current
	if q != null:
		q.changed.connect(func() -> void:
			if _tree_share() != _trees:
				_origin = Vector2.INF)


## Yard trees per house now: none in the browser or on Low.
func _tree_share() -> float:
	var q := GraphicsQuality.current
	if q == null or not q.active or q.browser:
		return 0.0
	return TREES_PER_HOUSE[clampi(q.tier, 0, TREES_PER_HOUSE.size() - 1)]


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
		_trees = _tree_share()
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
				_blocks[k] = [0, PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(),
					PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
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
	var uv: PackedVector2Array = blk[4]
	var o := _origin
	for s in sq[1]:
		_street(v, nrm, col, s[1], WIDTHS[s[0]], o)
	for b in sq[0]:
		_building(v, nrm, col, uv, b, o)
		if _trees > 0.0:
			_yard_trees(blk[5], blk[6], blk[7], b, o)
	blk[0] -= 1
	if blk[0] > 0 or v.is_empty():
		return
	uv.resize(v.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	if not blk[5].is_empty():
		var ta := []
		ta.resize(Mesh.ARRAY_MAX)
		ta[Mesh.ARRAY_VERTEX] = blk[5]
		ta[Mesh.ARRAY_NORMAL] = blk[6]
		ta[Mesh.ARRAY_COLOR] = blk[7]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
		mesh.surface_set_material(1, HouseMaterials.get_mat("plain"))
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


func _building(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array,
		b: Array, o: Vector2) -> void:
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
	var area: float = b[2] * b[3]
	var house: bool = area < HOUSE_AREA and h < HOUSE_HEIGHT
	# Older two-storey-plus blocks of modest footprint read as downtown brick.
	var downtown: bool = not house and h >= 7.0 and area < LOT_AREA
	var walls: Array = HOUSE_WALLS if house else (BRICK if downtown else SHOP_WALLS)
	var wall: Color = walls[pick % walls.size()]
	wall.a = GLASS[0 if house else (2 if downtown else 1)]
	var pts := []
	for p in corners:
		pts.append(Vector2(p.x - o.x, p.y - o.y))
	var mid: Vector2 = (pts[0] + pts[2]) * 0.5
	if not house and not downtown and area >= LOT_AREA:
		_lot(v, nrm, col, centre, u, w, area, o)
	for k in 4:
		var a: Vector2 = pts[k]
		var c: Vector2 = pts[(k + 1) % 4]
		var away := (a + c) * 0.5 - mid
		uv.resize(v.size())
		var first := v.size()
		_quad(v, nrm, col, Vector3(a.x, y0, a.y), Vector3(c.x, y0, c.y), Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y),
			wall, Vector3(away.x, 0.0, away.y))
		# Windows: UVs in metres along and up the wall.
		var along := (c - a).normalized()
		for i in range(first, v.size()):
			uv.append(Vector2((Vector2(v[i].x, v[i].z) - a).dot(along) + 0.01, v[i].y - lo + 0.01))
	wall.a = 1.0
	if not house:
		var flat: Color = FLAT_ROOFS[(pick / 7) % FLAT_ROOFS.size()]
		_quad(v, nrm, col, Vector3(pts[0].x, y1, pts[0].y), Vector3(pts[3].x, y1, pts[3].y),
			Vector3(pts[2].x, y1, pts[2].y), Vector3(pts[1].x, y1, pts[1].y), flat)
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


## A house's yard trees (_trees per house on average): crowns in the front
## and back yards, off the short sides of the house, 10-14 m across and
## 12-17 m tall like a grown silver maple or pin oak, sitting on the trunk
## (too thin to see from the 450 m the camera keeps from the backdrop).
func _yard_trees(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, b: Array, o: Vector2) -> void:
	if b[2] * b[3] >= HOUSE_AREA or b[4] >= HOUSE_HEIGHT:
		return
	var pick := absi(hash(Vector2i(b[0] * 3 + 1, b[1] * 5 + 2)))
	var n := int(_trees) + (1 if float(pick % 1000) / 1000.0 < fposmod(_trees, 1.0) else 0)
	var ang := deg_to_rad(b[5])
	var u := Vector2(cos(ang), sin(ang))
	var w := Vector2(-sin(ang), cos(ang))
	for i in n:
		var h := absi(hash(pick + i * 7919))
		var f := float(h % 997) / 997.0
		var g := float((h / 997) % 991) / 991.0
		# Front or back yard, 5-9 m off the wall, anywhere along the house.
		var side := 1.0 if (h / 13) % 2 == 0 else -1.0
		if i == 1:
			side = -side
		var p: Vector2 = Vector2(b[0], b[1]) + w * side * (b[3] * 0.5 + 5.0 + f * 4.0) + u * (g - 0.5) * (b[2] + 6.0)
		var r := 5.0 + f * 2.0
		var ground := Terrain.height(p.x, p.y)
		var base := ground + 3.0 + g * 1.5
		var mid := base + r * 0.8
		var c: Color = CROWNS[h % CROWNS.size()]
		var x: float = p.x - o.x
		var z: float = p.y - o.y
		# A dome: the widest ring, a narrower one above it, a low apex; and
		# a shallow underside down to the trunk.
		var rings := [[mid, r], [mid + r * 0.55, r * 0.72]]
		var pts := []
		for ring in rings:
			var row := []
			for k in 7:
				var a := TAU * (k + f) / 7.0
				row.append(Vector3(x + cos(a) * ring[1], ring[0], z + sin(a) * ring[1]))
			pts.append(row)
		var t := Vector3(x, mid + r * (0.85 + g * 0.2), z)
		var bt := Vector3(x, base, z)
		var cen := Vector3(x, mid, z)
		var under := c * Color(0.75, 0.75, 0.75, 1.0)
		for k in 7:
			var k1 := (k + 1) % 7
			var a: Vector3 = pts[0][k]
			var d: Vector3 = pts[0][k1]
			var a2: Vector3 = pts[1][k]
			var d2: Vector3 = pts[1][k1]
			var out := (a + d) * 0.5 - cen
			_quad(v, nrm, col, a, d, d2, a2, c, out + Vector3(0, r * 0.6, 0))
			_tri(v, nrm, col, a2, d2, t, c, out * 0.5 + Vector3(0, r, 0))
			_tri(v, nrm, col, a, d, bt, under, out - Vector3(0, r * 0.5, 0))


## The parking lot round a store or plant: its footprint grown on every side
## until the asphalt is LOT_SHARE times the floor.
func _lot(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		centre: Vector2, u: Vector2, w: Vector2, area: float, o: Vector2) -> void:
	var lu := u.length()
	var lw := w.length()
	# (2lu + 2m)(2lw + 2m) = (1 + share) area, solved for the margin m.
	var s := lu + lw
	var m := (-s + sqrt(s * s + LOT_SHARE * area)) * 0.5
	var gu := u.normalized() * (lu + m)
	var gw := w.normalized() * (lw + m)
	var q := [centre - gu - gw, centre + gu - gw, centre + gu + gw, centre - gu + gw]
	var p := []
	for c in q:
		p.append(Vector3(c.x - o.x, Terrain.height(c.x, c.y) + 0.15, c.y - o.y))
	_quad(v, nrm, col, p[0], p[1], p[2], p[3], LOT_ASPHALT)


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
