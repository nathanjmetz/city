class_name FarmsteadView
extends Node3D
## The farmsteads and country homes out in the county, where the real land
## cover shows them (terrain/grant_in/farmsteads.bin, from
## tools/terrain/build_roads.py). Scenery like the backdrop towns: nothing in
## them is simulated, and the town's own land clears them, as a farmstead
## is bought out when a town grows over it. One mesh per 2 km block, built a
## few blocks a frame, and rebuilt only where the town's land changes.
##
## Benchmark: USDA aerials of Grant County, Indiana: a white two-storey
## farmhouse facing the road, a red or weathered bank barn behind it, a
## steel machine shed and a pair of corrugated grain bins; between them,
## country homes: a one-storey ranch house and a detached garage.

## Side of a block, metres: one mesh each.
const BLOCK := 2048.0
## Time to spend building blocks each frame, ms.
const BUDGET_MS := 3.0
## Past this the haze has them anyway, metres.
const DRAW_TO := 9000.0

const HOUSE_WALLS := [Color(0.90, 0.89, 0.85), Color(0.86, 0.84, 0.78), Color(0.80, 0.80, 0.78), Color(0.70, 0.62, 0.52)]
const HOME_WALLS := [Color(0.78, 0.74, 0.66), Color(0.62, 0.36, 0.30), Color(0.84, 0.83, 0.80), Color(0.60, 0.62, 0.60)]
const ROOFS := [Color(0.24, 0.24, 0.25), Color(0.33, 0.28, 0.24), Color(0.42, 0.42, 0.43)]
const BARN_WALLS := [Color(0.55, 0.17, 0.13), Color(0.48, 0.42, 0.36), Color(0.86, 0.85, 0.82), Color(0.58, 0.20, 0.15)]
const BARN_ROOF := Color(0.36, 0.37, 0.38)
const STEEL := Color(0.70, 0.71, 0.70)
const SHED_ROOF := Color(0.55, 0.56, 0.56)

var sim: CitySim
## Block -> Array of [x, z, kind, facing radians, seed] (region metres).
var _places := {}
var _origin := Vector2.INF
var _queue: Array = []
var _meshes := {}  # block -> MeshInstance3D
var _material: Material


func setup(s: CitySim) -> void:
	sim = s
	# The far-building look: reads the colours as sRGB, as they're written
	# (a plain material took them as linear and washed them out to white).
	_material = HouseMaterials.get_mat("far")
	_load()
	# The town's land changed: redraw the blocks it touched.
	sim.vegetation.changed.connect(func(chunks: Array) -> void:
		var o := Terrain.view_origin
		for c in chunks:
			var p: Vector2 = (Vector2(c) + Vector2(0.5, 0.5)) * Vegetation.CHUNK + o
			var b := _block(p)
			if _places.has(b) and not b in _queue:
				_queue.append(b))


func _load() -> void:
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "FST1":
		return
	var n := data.decode_u32(4)
	var at := 8
	for i in n:
		var p := Vector2(data.decode_s16(at), data.decode_s16(at + 2))
		var b := _block(p)
		if not _places.has(b):
			_places[b] = []
		_places[b].append([p.x, p.y, data.decode_u8(at + 4), data.decode_u8(at + 5) / 256.0 * TAU, data.decode_u8(at + 6)])
		at += 7


static func _block(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BLOCK), floori(p.y / BLOCK))


func _process(_delta: float) -> void:
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for b in _meshes:
			_meshes[b].queue_free()
		_meshes.clear()
		_queue = _places.keys()
	if _queue.is_empty():
		return
	var start := Time.get_ticks_msec()
	while not _queue.is_empty() and Time.get_ticks_msec() - start < BUDGET_MS:
		_build(_queue.pop_back())


## Whether the town has built on, or cleared, the land round a place.
func _taken(at: Vector2) -> bool:
	if sim == null:
		return false
	var veg: Vegetation = sim.vegetation
	for d in [Vector2.ZERO, Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
		var c := Vegetation.cell_of(Vector3(at.x + d.x, 0.0, at.y + d.y))
		if veg.is_occupied(c) or veg.cleared.has(c):
			return true
	return false


func _build(b: Vector2i) -> void:
	if _meshes.has(b):
		_meshes[b].queue_free()
		_meshes.erase(b)
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var o := _origin
	for f in _places[b]:
		var at := Vector2(f[0], f[1]) - o
		if _taken(at):
			continue
		_place(v, nrm, col, at, int(f[2]), float(f[3]), int(f[4]))
	if v.is_empty():
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
	mi.visibility_range_end = DRAW_TO
	add_child(mi)
	_meshes[b] = mi


## One farmstead or country home: `at` in view metres, facing its road.
func _place(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		at: Vector2, kind: int, facing: float, seed: int) -> void:
	var f := Vector2(cos(facing), sin(facing))  # toward the road
	var s := Vector2(-f.y, f.x)
	var side := 1.0 if seed & 1 else -1.0
	var roof: Color = ROOFS[(seed >> 3) % ROOFS.size()]
	if kind == 0:
		# A ranch house (about 15 x 9 m, one storey) and a garage beside it.
		var wall: Color = HOME_WALLS[(seed >> 1) % HOME_WALLS.size()]
		_box(v, nrm, col, at, s, 7.5, 4.5, 3.0, 2.2, wall, roof)
		_box(v, nrm, col, at + s * side * 13.0 - f * 4.0, f, 3.6, 3.6, 2.8, 1.6, wall, roof)
		return
	# The farmhouse, two storeys, gable end to the road (an I-house turns its
	# long side to it: either is common).
	var wall: Color = HOUSE_WALLS[(seed >> 1) % HOUSE_WALLS.size()]
	var long_side := (seed >> 2) & 1 == 1
	_box(v, nrm, col, at, s if long_side else f, 6.0, 4.5, 6.0, 2.6, wall, roof)
	# The barn behind it: a bank barn about 12 x 24 m under a gambrel roof.
	var barn_at := at - f * 38.0 + s * side * 14.0
	var barn: Color = BARN_WALLS[(seed >> 4) % BARN_WALLS.size()]
	_barn(v, nrm, col, barn_at, f, 12.0, 6.0, 5.0, barn, BARN_ROOF)
	# A steel machine shed (pole barn) and two grain bins.
	_box(v, nrm, col, at - f * 44.0 - s * side * 22.0, f, 9.0, 15.0, 5.0, 1.2, STEEL, SHED_ROOF)
	for k in 2:
		_bin(v, nrm, col, at - f * (18.0 + k * 11.0) - s * side * 24.0, 4.5 - k * 0.6, 7.5 - k)


## The lowest ground under a footprint (view metres in, so it sits on it).
func _ground(at: Vector2, u: Vector2, w: Vector2) -> float:
	var lo := INF
	for c in [at - u - w, at + u - w, at + u + w, at - u + w]:
		lo = minf(lo, Terrain.height(c.x + _origin.x, c.y + _origin.y))
	return lo


## A box with a gable roof along `along`: half length hl, half width hw,
## wall height h, ridge rise r above the eaves.
func _box(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, at: Vector2,
		along: Vector2, hl: float, hw: float, h: float, r: float, wall: Color, roof: Color) -> void:
	var u := along * hl
	var w := Vector2(-along.y, along.x) * hw
	var y0 := _ground(at, u, w) - 0.3
	var y1 := y0 + 0.3 + h
	var c := [at - u - w, at + u - w, at + u + w, at - u + w]
	_walls(v, nrm, col, c, at, y0, y1, wall)
	var r0 := at - u
	var r1 := at + u
	var R0 := Vector3(r0.x, y1 + r, r0.y)
	var R1 := Vector3(r1.x, y1 + r, r1.y)
	BackdropView._quad(v, nrm, col, _p(c[0], y1), _p(c[1], y1), R1, R0, roof, _up(-w))
	BackdropView._quad(v, nrm, col, _p(c[2], y1), _p(c[3], y1), R0, R1, roof, _up(w))
	BackdropView._tri(v, nrm, col, _p(c[3], y1), _p(c[0], y1), R0, wall, Vector3(-u.x, 0.0, -u.y))
	BackdropView._tri(v, nrm, col, _p(c[1], y1), _p(c[2], y1), R1, wall, Vector3(u.x, 0.0, u.y))


## A barn under a gambrel roof: steep lower slopes, then a shallow top.
func _barn(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, at: Vector2,
		along: Vector2, hl: float, hw: float, h: float, wall: Color, roof: Color) -> void:
	var u := along * hl
	var w := Vector2(-along.y, along.x) * hw
	var y0 := _ground(at, u, w) - 0.3
	var y1 := y0 + 0.3 + h
	var c := [at - u - w, at + u - w, at + u + w, at - u + w]
	_walls(v, nrm, col, c, at, y0, y1, wall)
	var k1 := y1 + hw * 0.75  # the break in the roof
	var k2 := k1 + hw * 0.35  # the ridge
	for e: float in [-1.0, 1.0]:
		var a := at + u * e
		var lo: Array = [a - w, a + w]
		var mid: Array = [a - w * 0.55, a + w * 0.55]
		var gable: Array = [_p(lo[0], y1), _p(mid[0], k1), _p(a, k2), _p(mid[1], k1), _p(lo[1], y1)]
		var out := Vector3(u.x * e, 0.0, u.y * e)
		for i in 3:
			BackdropView._tri(v, nrm, col, gable[0], gable[i + 1], gable[i + 2], wall, out)
	for sd: float in [-1.0, 1.0]:
		var ww := w * sd
		BackdropView._quad(v, nrm, col, _p(at - u + ww, y1), _p(at + u + ww, y1),
			_p(at + u + ww * 0.55, k1), _p(at - u + ww * 0.55, k1), roof, Vector3(ww.x, 0.4, ww.y))
		BackdropView._quad(v, nrm, col, _p(at - u + ww * 0.55, k1), _p(at + u + ww * 0.55, k1),
			_p(at + u, k2), _p(at - u, k2), roof, _up(ww))


## A corrugated steel grain bin: an eight-sided drum and a cone roof.
func _bin(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, at: Vector2,
		radius: float, h: float) -> void:
	var y0 := Terrain.height(at.x + _origin.x, at.y + _origin.y) - 0.3
	var y1 := y0 + 0.3 + h
	var top := Vector3(at.x, y1 + radius * 0.45, at.y)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var p0 := at + Vector2(cos(a0), sin(a0)) * radius
		var p1 := at + Vector2(cos(a1), sin(a1)) * radius
		var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		BackdropView._quad(v, nrm, col, _p(p0, y0), _p(p1, y0), _p(p1, y1), _p(p0, y1), STEEL, out)
		BackdropView._tri(v, nrm, col, _p(p0, y1), _p(p1, y1), top, STEEL * 0.92, out + Vector3.UP)


func _walls(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, c: Array, at: Vector2,
		y0: float, y1: float, wall: Color) -> void:
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var away := (a + b) * 0.5 - at
		BackdropView._quad(v, nrm, col, _p(a, y0), _p(b, y0), _p(b, y1), _p(a, y1), wall, Vector3(away.x, 0.0, away.y))


static func _p(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, q.y)


static func _up(side: Vector2) -> Vector3:
	return Vector3(side.x, 1.0, side.y)
