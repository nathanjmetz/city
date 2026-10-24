class_name Terrain
extends RefCounted
## The land itself, from real data: ground heights, rivers and lakes, woods,
## farmland and what lies underground, for a real stretch of the Midwest (see
## terrain/LICENSES.md and tools/terrain/build_region.py). Baked into the game,
## so every player and the server see exactly the same land.
##
## The real area is a 36.9 km square of Grant County, Indiana, around
## Marion (terrain/grant_in/region.json). Past its edges the land carries on as a
## mirror image of itself, so the map never ends and never shows a seam.
##
## Two kinds of coordinates:
##   - Region coordinates (x east, z south, metres): the sim's functions take
##     these. A city's sim adds its own `terrain_offset` to its local points.
##   - View coordinates: what's drawn on screen, relative to your own city.
##     The `*_y` helpers add `view_origin` for you.
##
## Heights: the sim keeps every y as "metres above base", and base(x, z) is the
## level structures stand on: the ground smoothed for grading, lifted into a
## bridge deck over water. So a road drawn at sim height 0 crosses a river on
## a bridge by itself.

const DIR := "res://terrain/grant_in/"
## Width of the real area, metres (region.json size_m; the ground shader
## and Highways mirror at the same size).
const SIZE := 36864.0
## Where the middle of the real area lies, region metres (region.json
## centre): region (0, 0), where the first town starts, is Sweetser's
## crossroads, five miles west and three north of it.
const CENTRE := Vector2(8040.0, 4824.0)
## Steeper than this (rise over run) is too steep to build on: 25%, where US
## steep-slope ordinances (and FHA site guidance) stop new building.
const MAX_BUILD_SLOPE := 0.25
## Water deeper than this fraction of a sample counts as water.
const WET := 0.5

## Your own city's place in the region (0 in solo play). Views add it.
static var view_origin := Vector2.ZERO
## Where the view drawing right now sits in the world: a neighbor's city is
## drawn under a node moved over to its place. Set it around the drawing
## (see `shift_for`), and put it back to zero after.
static var shift := Vector2.ZERO

static var _loaded := false
## name -> [samples across, bytes, bytes per sample]
static var _layers := {}
## Flattening under roads and lots, written by TerrainView: chunk -> weights.
static var _flat := {}
static var _mow := {}
const FLAT_CELL := 8.0
const FLAT_CHUNK := 64  # cells per side
## A road's mowed verge fades into the wild cover over this many metres.
const MOW_FADE := 6.0


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for name in ["ground", "base", "wlevel", "cover", "resources"]:
		var img := Image.new()
		var bytes := FileAccess.get_file_as_bytes(DIR + name + ".bin")
		var err: int
		# Lossless WebP (about 30% smaller to download) or PNG. WebP has no
		# grey-plus-alpha mode, so height layers come back as RGBA with
		# R = G = B and are packed back into two bytes a sample.
		if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
			err = img.load_webp_from_buffer(bytes)
			if err == OK and name in ["ground", "base", "wlevel"]:
				img.convert(Image.FORMAT_LA8)
		else:
			err = img.load_png_from_buffer(bytes)
		if err != OK:
			push_error("Terrain: can't load %s (%d)" % [name, err])
			img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		var bpp := 2 if img.get_format() == Image.FORMAT_LA8 else 4
		_layers[name] = [img.get_width(), img.get_data(), bpp]


## Index of a sample, mirrored past the edges of the real area.
static func _mirror(i: int, n: int) -> int:
	i = posmod(i, n * 2)
	return i if i < n else n * 2 - 1 - i


## A layer value at a point, blended between the four nearest samples.
## Height layers return metres; others return 0 to 1 for channel `ch`.
static func _sample(name: String, x: float, z: float, ch := 0) -> float:
	if not _loaded:
		_load()
	var layer: Array = _layers[name]
	var n: int = layer[0]
	var data: PackedByteArray = layer[1]
	var bpp: int = layer[2]
	var cell := SIZE / n
	var u := (x - CENTRE.x + SIZE * 0.5) / cell - 0.5
	var v := (z - CENTRE.y + SIZE * 0.5) / cell - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	var ia := i0
	var ib := i0 + 1
	var ja := j0 * n
	var jb := (j0 + 1) * n
	# Past the edge of the data the land mirrors (rarely: it's 32 km wide).
	if i0 < 0 or i0 + 1 >= n or j0 < 0 or j0 + 1 >= n:
		ia = _mirror(i0, n)
		ib = _mirror(i0 + 1, n)
		ja = _mirror(j0, n) * n
		jb = _mirror(j0 + 1, n) * n
	if bpp == 2:
		var a := data[(ja + ia) * 2] * 256 + data[(ja + ia) * 2 + 1]
		var b := data[(ja + ib) * 2] * 256 + data[(ja + ib) * 2 + 1]
		var c := data[(jb + ia) * 2] * 256 + data[(jb + ia) * 2 + 1]
		var d := data[(jb + ib) * 2] * 256 + data[(jb + ib) * 2 + 1]
		return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv) * 0.1
	var a4 := data[(ja + ia) * 4 + ch]
	var b4 := data[(ja + ib) * 4 + ch]
	var c4 := data[(jb + ia) * 4 + ch]
	var d4 := data[(jb + ib) * 4 + ch]
	return lerpf(lerpf(a4, b4, fu), lerpf(c4, d4, fu), fv) / 255.0


## Natural cover for wild plants (Vegetation): [tree share, brush share],
## each 0 to 1, from real land cover. Brush is thickest on woodland edges and
## in old fields, thin in crops and under closed canopy; none in the water.
static func wild_cover(x: float, z: float) -> Array:
	var c := cover(x, z)
	if c.g > 0.5:
		return [0.0, 0.0]
	var trees := clampf(c.r * 0.95, 0.0, 0.95)
	var open := clampf(1.0 - c.r - c.b - c.a, 0.0, 1.0)  # grass and old fields
	var brush := clampf(0.03 + 1.4 * trees * (1.0 - trees) + 0.12 * open + 0.02 * c.b, 0.0, 0.6)
	return [trees, brush]


## All four land cover fractions at once: r trees, g water, b crops, a bare.
static func cover(x: float, z: float) -> Color:
	_load()
	var layer: Array = _layers["cover"]
	var n: int = layer[0]
	var data: PackedByteArray = layer[1]
	var cell := SIZE / n
	var u := (x - CENTRE.x + SIZE * 0.5) / cell - 0.5
	var v := (z - CENTRE.y + SIZE * 0.5) / cell - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	var a := (_mirror(j0, n) * n + _mirror(i0, n)) * 4
	var b := (_mirror(j0, n) * n + _mirror(i0 + 1, n)) * 4
	var c := (_mirror(j0 + 1, n) * n + _mirror(i0, n)) * 4
	var d := (_mirror(j0 + 1, n) * n + _mirror(i0 + 1, n)) * 4
	var out := Color()
	for ch in 4:
		out[ch] = lerpf(lerpf(data[a + ch], data[b + ch], fu), lerpf(data[c + ch], data[d + ch], fu), fv) / 255.0
	return out


# --- Region coordinates (the sim) -------------------------------------------

## The real ground, in metres above sea level (river beds carved below the water).
static func height(x: float, z: float) -> float:
	return _sample("ground", x, z)


## The level roads and buildings stand on: the ground smoothed for grading,
## and a bridge deck with 7 m (23 ft) clearance over water.
static func base(x: float, z: float) -> float:
	return _sample("base", x, z)


## The water surface nearest a point (only meaningful on or by the water).
static func water_level(x: float, z: float) -> float:
	return _sample("wlevel", x, z)


## How much of the ground here is water, 0 to 1.
static func water(x: float, z: float) -> float:
	return _sample("cover", x, z, 1)


static func is_water(x: float, z: float) -> bool:
	return water(x, z) >= WET


## Tree cover, 0 to 1 (real woods).
static func trees(x: float, z: float) -> float:
	return _sample("cover", x, z, 0)


## Cropland, 0 to 1 (real farm fields).
static func crops(x: float, z: float) -> float:
	return _sample("cover", x, z, 2)


## Bare ground (strip mines, gravel), 0 to 1.
static func bare(x: float, z: float) -> float:
	return _sample("cover", x, z, 3)


## Resource fields, 0 to 1: channel 0 fertility, 1 oil, 2 ore, 3 forest.
static func resource(ch: int, x: float, z: float) -> float:
	return _sample("resources", x, z, ch)


## Steepness of the ground, rise over run.
static func slope(x: float, z: float) -> float:
	var d := 8.0
	var gx := height(x + d, z) - height(x - d, z)
	var gz := height(x, z + d) - height(x, z - d)
	return Vector2(gx, gz).length() / (2.0 * d)


## True when a footprint of `radius` metres around a point is dry, gently
## sloped land.
static func buildable(x: float, z: float, radius := 0.0) -> bool:
	if water(x, z) > 0.2 or slope(x, z) > MAX_BUILD_SLOPE or Backdrop.inside(Vector2(x, z), radius):
		return false
	if radius > 0.0:
		for k in 8:
			var a := TAU * k / 8.0
			var px := x + cos(a) * radius
			var pz := z + sin(a) * radius
			if water(px, pz) > 0.2 or slope(px, pz) > MAX_BUILD_SLOPE:
				return false
	return true


## Where a straight line from a to b crosses water: an Array of
## [from, to] fractions along it (empty when it stays dry).
static func crossing(a: Vector2, b: Vector2) -> Array:
	var spans := []
	var n := maxi(2, int(a.distance_to(b) / 6.0))
	var start := -1.0
	for k in n + 1:
		var t := float(k) / n
		var p := a.lerp(b, t)
		var wet := is_water(p.x, p.y)
		if wet and start < 0.0:
			start = t
		elif not wet and start >= 0.0:
			spans.append([start, t])
			start = -1.0
	if start >= 0.0:
		spans.append([start, 1.0])
	return spans


# --- View coordinates (drawing) ---------------------------------------------

## Height things stand on (roads, cars, buildings) at a point on screen.
static func base_y(x: float, z: float) -> float:
	return base(x + shift.x + view_origin.x, z + shift.y + view_origin.y)


## Height of the ground as drawn: the real ground, graded flat where roads
## and lots are, except under bridges.
static func ground_y(x: float, z: float) -> float:
	var rx := x + shift.x + view_origin.x
	var rz := z + shift.y + view_origin.y
	var g := height(rx, rz)
	var w := flat_weight(x + shift.x, z + shift.y)
	if w <= 0.0:
		return g
	var b := base(rx, rz)
	# Leave the valley under a bridge alone.
	w *= 1.0 - smoothstep(2.5, 5.0, b - g)
	return lerpf(g, b, w)


## The shift for a view node: how far its parent has moved it over.
static func shift_for(node: Node3D) -> Vector2:
	if node == null or not node.is_inside_tree():
		return Vector2.ZERO
	var p := (node.get_parent() as Node3D).global_position if node.get_parent() is Node3D else Vector3.ZERO
	return Vector2(p.x, p.z)


## A point lifted onto the base level.
static func lift(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y + base_y(p.x, p.z), p.z)


## A point lifted onto what's drawn there for wheels and feet: the road
## level on streets and bridges, and off them the ground as graded and
## drawn, which lots, drives and yards are draped on (so a car in a lot up a
## slope sits on its pavement, not inside it).
static func stand(p: Vector3) -> Vector3:
	var b := base_y(p.x, p.z)
	var g := ground_y(p.x, p.z)
	# A bridge deck stands well above the valley under it.
	return Vector3(p.x, p.y + (b if b - g > 2.5 else g), p.z)


## Every point of a line lifted onto the base level.
static func lift_all(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = lift(pts[i])
	return out


## A line with extra points so none are more than `step` metres apart, so
## what's drawn along it follows the land.
static func densify(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := ceili(a.distance_to(b) / step)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


## A copy of a flat mesh (built at y = 0 in view coordinates) with every
## vertex raised onto the land: onto the base level, or with `on_ground`
## onto the ground as drawn (for things painted on the land: fields, zones).
## Triangles longer than `max_edge` metres are split first, so big flat
## pieces bend over the hills too.
static func drape(mesh: Mesh, on_ground := false, max_edge := 0.0) -> ArrayMesh:
	var out := ArrayMesh.new()
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if max_edge > 0.0 and mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
			arrays = _split(arrays, max_edge)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			verts[i] = Vector3(v.x, v.y + (ground_y(v.x, v.z) if on_ground else base_y(v.x, v.z)), v.z)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


## Splits long triangles (in halves along their longest side) until no side
## is longer than `max_edge`. Keeps normals, colours and UVs.
static func _split(arrays: Array, max_edge: float) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var colors = arrays[Mesh.ARRAY_COLOR]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var order = arrays[Mesh.ARRAY_INDEX]
	if order == null or (order as PackedInt32Array).is_empty():
		order = PackedInt32Array(range(verts.size()))
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	var ou := PackedVector2Array()
	var has_n: bool = normals != null and (normals as PackedVector3Array).size() == verts.size()
	var has_c: bool = colors != null and (colors as PackedColorArray).size() == verts.size()
	var has_u: bool = uvs != null and (uvs as PackedVector2Array).size() == verts.size()
	var stack := []
	for k in range(0, order.size(), 3):
		var tri := []
		for c in 3:
			var i: int = order[k + c]
			tri.append([verts[i], normals[i] if has_n else Vector3.UP, colors[i] if has_c else Color.WHITE,
				uvs[i] if has_u else Vector2.ZERO])
		stack.append(tri)
	var guard := 0
	while not stack.is_empty() and guard < 200000:
		guard += 1
		var tri: Array = stack.pop_back()
		var longest := -1
		var best := max_edge * max_edge
		for e in 3:
			var d: float = (tri[e][0] as Vector3).distance_squared_to(tri[(e + 1) % 3][0])
			if d > best:
				best = d
				longest = e
		if longest < 0:
			for c in tri:
				ov.append(c[0])
				on.append(c[1])
				oc.append(c[2])
				ou.append(c[3])
			continue
		var a: Array = tri[longest]
		var b: Array = tri[(longest + 1) % 3]
		var o: Array = tri[(longest + 2) % 3]
		var m := [(a[0] as Vector3).lerp(b[0], 0.5), (a[1] as Vector3).lerp(b[1], 0.5).normalized(),
			(a[2] as Color).lerp(b[2], 0.5), (a[3] as Vector2).lerp(b[3], 0.5)]
		stack.append([a, m, o])
		stack.append([m, b, o])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	if has_n:
		out[Mesh.ARRAY_NORMAL] = on
	if has_c:
		out[Mesh.ARRAY_COLOR] = oc
	if has_u:
		out[Mesh.ARRAY_TEX_UV] = ou
	return out


## A copy of a flat mesh placed by `xform` (a node standing on the land),
## bent so each vertex keeps its height above the ground as drawn rather
## than above the node. Long triangles are split first (no side over
## `max_edge` metres) so a big yard follows the slope instead of a corner
## sinking into it and leaving a wedge showing.
static func drape_local(mesh: Mesh, xform: Transform3D, max_edge := 4.0) -> ArrayMesh:
	var out := ArrayMesh.new()
	if mesh == null:
		return out
	var inv := xform.affine_inverse()
	# Triangles share corners (each one is listed again for every triangle
	# that meets there), so each spot's ground is looked up once.
	var seen := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if max_edge > 0.0 and mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
			arrays = _split(arrays, max_edge)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var w := xform * verts[i]
			var at := Vector2(w.x, w.z)
			var g = seen.get(at)
			if g == null:
				g = ground_y(w.x, w.z)
				seen[at] = g
			w.y = g + verts[i].y
			verts[i] = inv * w
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


## Where a ray meets the drawn ground (view coordinates), or null.
static func ray_hit(from: Vector3, dir: Vector3, max_dist := 20000.0):
	dir = dir.normalized()
	var t := 0.0
	var step := 4.0
	var prev_t := 0.0
	var above := from.y - ground_y(from.x, from.z)
	if above < 0.0:
		return null
	while t < max_dist:
		prev_t = t
		# Big steps high above the land, small ones near it.
		step = clampf(above * 0.5, 1.0, 200.0)
		t += step
		var p := from + dir * t
		above = p.y - ground_y(p.x, p.z)
		if above <= 0.0:
			# Refine between the last two steps.
			var lo := prev_t
			var hi := t
			for k in 12:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y - ground_y(q.x, q.z) > 0.0:
					lo = mid
				else:
					hi = mid
			return from + dir * hi
	return null


# --- Flattening (written by the views) --------------------------------------

## How flat the ground is graded at a point on screen, 0 to 1.
static func flat_weight(x: float, z: float) -> float:
	return _weight(_flat, x, z)


## How far the wild cover is cleared at a point on screen, 0 to 1: the road
## itself and a mowed verge beside it, narrower than the grading.
static func mow_weight(x: float, z: float) -> float:
	return _weight(_mow, x, z)


## True when any land in a box (view coordinates) is mowed.
static func any_mowed(box: Rect2) -> bool:
	var span := FLAT_CELL * FLAT_CHUNK
	for cz in range(floori((box.position.y - FLAT_CELL) / span), floori((box.end.y + FLAT_CELL) / span) + 1):
		for cx in range(floori((box.position.x - FLAT_CELL) / span), floori((box.end.x + FLAT_CELL) / span) + 1):
			if _mow.has(Vector2i(cx, cz)):
				return true
	return false


static func _weight(layer: Dictionary, x: float, z: float) -> float:
	if layer.is_empty():
		return 0.0
	var u := x / FLAT_CELL - 0.5
	var v := z / FLAT_CELL - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	# Mostly all four cells are in one chunk: look it up once.
	var ci := posmod(i0, FLAT_CHUNK)
	var cj := posmod(j0, FLAT_CHUNK)
	if ci < FLAT_CHUNK - 1 and cj < FLAT_CHUNK - 1:
		var cells = layer.get(Vector2i(floori(float(i0) / FLAT_CHUNK), floori(float(j0) / FLAT_CHUNK)))
		if cells == null:
			return 0.0
		var c: PackedFloat32Array = cells
		var at := cj * FLAT_CHUNK + ci
		return lerpf(lerpf(c[at], c[at + 1], fu), lerpf(c[at + FLAT_CHUNK], c[at + FLAT_CHUNK + 1], fu), fv)
	return lerpf(lerpf(_cell(layer, i0, j0), _cell(layer, i0 + 1, j0), fu),
		lerpf(_cell(layer, i0, j0 + 1), _cell(layer, i0 + 1, j0 + 1), fu), fv)


static func _cell(layer: Dictionary, i: int, j: int) -> float:
	var key := Vector2i(floori(float(i) / FLAT_CHUNK), floori(float(j) / FLAT_CHUNK))
	var cells = layer.get(key)
	if cells == null:
		return 0.0
	return (cells as PackedFloat32Array)[posmod(j, FLAT_CHUNK) * FLAT_CHUNK + posmod(i, FLAT_CHUNK)]


## Clears the flattening (and mowing) in a box (view coordinates).
static func clear_flat(box: Rect2) -> void:
	for layer in [_flat, _mow]:
		_clear(layer, box)


static func _clear(layer: Dictionary, box: Rect2) -> void:
	var c0 := Vector2i(floori(box.position.x / FLAT_CELL / FLAT_CHUNK), floori(box.position.y / FLAT_CELL / FLAT_CHUNK))
	var c1 := Vector2i(floori(box.end.x / FLAT_CELL / FLAT_CHUNK), floori(box.end.y / FLAT_CELL / FLAT_CHUNK))
	var i0 := floori(box.position.x / FLAT_CELL)
	var i1 := ceili(box.end.x / FLAT_CELL)
	var j0 := floori(box.position.y / FLAT_CELL)
	var j1 := ceili(box.end.y / FLAT_CELL)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cy)
			if not layer.has(key):
				continue
			var cells: PackedFloat32Array = layer[key]
			layer.erase(key)  # so the writes below don't copy it
			for j in range(maxi(j0, cy * FLAT_CHUNK), mini(j1, (cy + 1) * FLAT_CHUNK - 1) + 1):
				for i in range(maxi(i0, cx * FLAT_CHUNK), mini(i1, (cx + 1) * FLAT_CHUNK - 1) + 1):
					cells[posmod(j, FLAT_CHUNK) * FLAT_CHUNK + posmod(i, FLAT_CHUNK)] = 0.0
			layer[key] = cells


## Grades a strip along a polyline flat: fully within `inner` metres of it,
## fading out by `outer`. With `mow` (metres) it also clears the wild cover
## that close, fading over MOW_FADE. Only cells inside `clip` change, when
## given.
static func stamp_flat(pts: PackedVector3Array, inner: float, outer: float, clip := Rect2(), mow := -1.0) -> void:
	_stamp(_flat, pts, inner, outer, clip)
	if mow >= 0.0:
		_stamp(_mow, pts, mow, mow + MOW_FADE, clip)


static func _stamp(layer: Dictionary, pts: PackedVector3Array, inner: float, outer: float, clip: Rect2) -> void:
	var line := PackedVector2Array()
	for p in pts:
		line.append(Vector2(p.x, p.z))
	var box := Rect2(line[0], Vector2.ZERO)
	for p in line:
		box = box.expand(p)
	box = box.grow(outer)
	if clip.has_area():
		box = box.intersection(clip)
		if not box.has_area():
			return
	var i0 := floori(box.position.x / FLAT_CELL)
	var i1 := ceili(box.end.x / FLAT_CELL)
	var j0 := floori(box.position.y / FLAT_CELL)
	var j1 := ceili(box.end.y / FLAT_CELL)
	for cy in range(floori(float(j0) / FLAT_CHUNK), floori(float(j1) / FLAT_CHUNK) + 1):
		for cx in range(floori(float(i0) / FLAT_CHUNK), floori(float(i1) / FLAT_CHUNK) + 1):
			var key := Vector2i(cx, cy)
			var cells := PackedFloat32Array()
			if layer.has(key):
				cells = layer[key]
				layer.erase(key)  # so the writes below don't copy it
			else:
				cells.resize(FLAT_CHUNK * FLAT_CHUNK)
			for j in range(maxi(j0, cy * FLAT_CHUNK), mini(j1, (cy + 1) * FLAT_CHUNK - 1) + 1):
				for i in range(maxi(i0, cx * FLAT_CHUNK), mini(i1, (cx + 1) * FLAT_CHUNK - 1) + 1):
					var c := Vector2((i + 0.5) * FLAT_CELL, (j + 0.5) * FLAT_CELL)
					var best := INF
					for k in line.size() - 1:
						var q := Geometry2D.get_closest_point_to_segment(c, line[k], line[k + 1])
						best = minf(best, c.distance_squared_to(q))
					if best >= outer * outer:
						continue
					var w := 1.0 - smoothstep(inner, outer, sqrt(best))
					var idx := (j - cy * FLAT_CHUNK) * FLAT_CHUNK + (i - cx * FLAT_CHUNK)
					if w > cells[idx]:
						cells[idx] = w
			layer[key] = cells
