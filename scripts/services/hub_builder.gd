class_name HubBuilder
extends CivicBuilder
## Draws landfills, recycling centres and cemeteries over whatever land each
## hub has grown into, benchmarked against photos of real small-town sites:
##   - the county landfill: a broad mound with 3:1 side slopes, capped and
##     grassed where it's done, a bare brown working face where trucks tip,
##     a compactor on it, gas vents on the cap, a chain-link fence, a scale
##     house and truck scale at the gate
##   - recycling: a drop-off yard of roll-off containers, then a steel
##     sorting building, then a large enclosed recovery plant, with bales of
##     cardboard, paper, plastic and cans stacked in the yard
##   - the town cemetery: gravel lanes, rows of granite headstones (older
##     sections full, new ones filling in), a few obelisks, an iron fence with
##     brick gate posts, evergreens and shade trees along the edge
## Local space: -z faces the road, z = 0 is the front edge of the land, and
## piece (x, y) spans x*cell +- cell/2 across and y*cell .. (y+1)*cell back.
## Edge pieces (a hub boxed in by roads filling its block up to the
## sidewalk, CivicHubs) are outlines in the same space: they get the same
## ground, fence and site look as the whole pieces next to them.

const GRASS_CAP := [Color("#4a5d29"), Color("#5d6d33")]
const WORKING := Color("#6b5a47")
const GRANITE := [Color("#8d8a86"), Color("#a3a19b"), Color("#6e6c6a"), Color("#b5b0a6"), Color("#4f4e4d"),
	Color("#9b8c80")]
const BALES := [Color("#9a8466"), Color("#7f8fa3"), Color("#b8bcbe"), Color("#cfc8b4"), Color("#8b6f5a")]
const BINS := [Color("#2f5d8a"), Color("#3f6d3a"), Color("#77797a"), Color("#8a3b2c")]
const IRON := Color("#1d1e20")

var cells := []
var cell := 50.0
## Edge pieces: piece -> outline (local x, z), CivicHubs' `edge`.
var edge_land := {}
## Buildings from the hub's development tree (Balance.HUB_TREES ids).
var dev := []
## Ground kept clear of headstones (chapel, memorials): [Rect2 in x, z].
var _clear := []
## The hub's own building (scale house, booth, sorting plant, mausoleum and
## chapel), kept apart from the rest of the site so it can go up stage by
## stage (ConstructionSite): material key -> SurfaceTool.
var _own := {}


static func build_hub(h: Dictionary, seed: int, to_curb: float) -> Array:
	var b := HubBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.cells = h.cells
	b.cell = h.cell
	b.edge_land = h.get("edge", {})
	b.dev = h.get("built", [])
	match h.kind:
		"landfill":
			b._landfill(h, to_curb)
		"cemetery":
			b._cemetery(to_curb)
		_:
			b._recycling(h, to_curb)
	var site := b._commit_house()
	b._st = b._own
	# [building, ground, trees, the rest of the site: mound, yard, fences, stones].
	return [b._commit_house(), b._commit_flat(), b.trees, site]


## Draws `draw` into the hub's own building instead of the site.
func _building(draw: Callable) -> void:
	var keep := _st
	_st = _own
	draw.call()
	_own = _st
	_st = keep


func _has(c: Vector2i) -> bool:
	return c in cells


func _piece_at(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x / cell), floori(z / cell))


## The outside edges of a set of pieces, as [a, b] pairs (local x, z).
func _edges(set: Array) -> Array:
	var out := []
	var hc := cell * 0.5
	for c in set:
		var cx: float = c.x * cell
		var z0: float = c.y * cell
		if not (c + Vector2i(0, -1)) in set:
			out.append([Vector2(cx - hc, z0), Vector2(cx + hc, z0)])
		if not (c + Vector2i(0, 1)) in set:
			out.append([Vector2(cx - hc, z0 + cell), Vector2(cx + hc, z0 + cell)])
		if not (c + Vector2i(-1, 0)) in set:
			out.append([Vector2(cx - hc, z0), Vector2(cx - hc, z0 + cell)])
		if not (c + Vector2i(1, 0)) in set:
			out.append([Vector2(cx + hc, z0), Vector2(cx + hc, z0 + cell)])
	return out


## A chain-link (or iron) fence along edges, posts every few metres, with
## an opening `gate` metres either side of the drive on the front edge.
func _fence_edges(edges: Array, h: float, col: Color, gap := 4.0, gate := 0.0) -> void:
	var runs := []
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		if gate > 0.0 and absf(a.y) < 0.5 and absf(b.y) < 0.5 and minf(a.x, b.x) < gate and maxf(a.x, b.x) > -gate:
			var lo := minf(a.x, b.x)
			var hi := maxf(a.x, b.x)
			if lo < -gate:
				runs.append([Vector2(lo, a.y), Vector2(-gate, a.y)])
			if hi > gate:
				runs.append([Vector2(gate, a.y), Vector2(hi, a.y)])
		else:
			runs.append(e)
	for e in runs:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var dir := (b - a) / len
		var yaw := Basis(Vector3.UP, atan2(dir.x, dir.y))
		var n := maxi(1, int(len / gap))
		for k in n + 1:
			var p := a + dir * (len * k / n)
			_box("paint", Vector3(0.08, h, 0.08), Vector3(p.x, h * 0.5, p.y), col)
		var mid := (a + b) * 0.5
		for y in [h, 0.15]:
			_box("paint", Vector3(0.05, 0.05, len), Vector3(mid.x, y, mid.y), col, yaw)


## The outside edges of `set`'s pieces and the edge pieces `with` (local
## outlines), as [a, b] pairs: sides shared with other land drop out. With
## no edge pieces, just _edges(set).
func _outline(set: Array, with: Dictionary) -> Array:
	if with.is_empty():
		return _edges(set)
	var polys := []
	for c in with:
		polys.append(with[c])
	var out := []
	# The pieces' own outside edges, less what runs along an edge piece.
	for e in _edges(set):
		out.append_array(_uncovered(e, polys, -1))
	# Each edge piece's sides, less what runs along a piece or another one.
	var squares := []
	var hc := cell * 0.5
	for c in set:
		squares.append(PackedVector2Array([Vector2(c.x * cell - hc, c.y * cell), Vector2(c.x * cell + hc, c.y * cell),
			Vector2(c.x * cell + hc, c.y * cell + cell), Vector2(c.x * cell - hc, c.y * cell + cell)]))
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		for k in poly.size():
			out.append_array(_uncovered([poly[k], poly[(k + 1) % poly.size()]], squares + polys, squares.size() + i))
	return out


## The parts of edge `e` ([a, b]) not running along any of `polys` (bar
## the one numbered `skip`), as [a, b] pairs.
static func _uncovered(e: Array, polys: Array, skip: int) -> Array:
	var runs := [PackedVector2Array([e[0], e[1]])]
	var box := Rect2(e[0], Vector2.ZERO).expand(e[1]).grow(0.5)
	for i in polys.size():
		if i == skip or not _bounds(polys[i]).grow(0.5).intersects(box):
			continue
		for grown in Geometry2D.offset_polygon(polys[i], 0.1):
			var next := []
			for r in runs:
				next.append_array(Geometry2D.clip_polyline_with_polygon(r, grown))
			runs = next
	var out := []
	for r in runs:
		for k in r.size() - 1:
			if r[k].distance_to(r[k + 1]) > 0.3:
				out.append([r[k], r[k + 1]])
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	return box


## A local point on the hub's land: a piece or an edge piece.
func _in_land(x: float, z: float) -> bool:
	if _inside(cells, x, z):
		return true
	for c in edge_land:
		if Geometry2D.is_point_in_polygon(Vector2(x, z), edge_land[c]):
			return true
	return false


## `poly` pulled in `by` metres all round (its largest part), or empty.
static func _inset(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	for q in Geometry2D.offset_polygon(poly, -by):
		if CivicHubs.area(q) > CivicHubs.area(best):
			best = q
	return best


## Flat ground over any outline (not only convex ones), as _flat_rect.
func _flat_poly_any(kind: String, poly: PackedVector2Array, y: float, col: Color) -> void:
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	for tri in _tris(poly):
		for q in tri:
			_flat.set_normal(Vector3.UP)
			_flat.set_color(col)
			_flat.set_uv(q * 0.25)
			_flat.add_vertex(Vector3(q.x, y, q.y))


## The landfill's grassed cap, flat, over an outline.
func _grass_poly(poly: PackedVector2Array) -> void:
	var st := _tool("paint")
	for tri in _tris(poly):
		for q in tri:
			var patch := 0.5 + 0.25 * sin(q.x * 0.045 + 1.3) * sin(q.y * 0.06) + 0.25 * sin((q.x + q.y) * 0.021)
			st.set_normal(Vector3.UP)
			st.set_color(GRASS_CAP[0].lerp(GRASS_CAP[1], patch))
			st.set_uv(q)
			st.add_vertex(Vector3(q.x, 0.05, q.y))


## An outline as triangles, each wound the way the ground faces up.
static func _tris(poly: PackedVector2Array) -> Array:
	var out := []
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size() - 2, 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		if (b - a).cross(c - a) < 0.0:
			out.append([a, c, b])
		else:
			out.append([a, b, c])
	return out


## Rows of bales across an outline, wherever a whole row fits.
func _bales_in(poly: PackedVector2Array, level: int) -> void:
	var box := _bounds(poly)
	var n := 6 + level * 3
	var z := box.position.y + 4.0
	while z < box.end.y - 2.0:
		var x := box.position.x + 1.0
		while x + n * 1.3 < box.end.x:
			var ok := true
			for k in 3:
				for dz in [-0.8, 0.8]:
					if not Geometry2D.is_point_in_polygon(Vector2(x + n * 1.3 * k / 2.0, z + dz), poly):
						ok = false
			if ok:
				_bale_row(x, z, level)
				x += n * 1.3 + 3.0
			else:
				x += 2.0
		z += cell * 0.3


# ---------------------------------------------------------------- landfill

func _landfill(h: Dictionary, to_curb: float) -> void:
	var top := CivicHubs.mound_height(h)
	_mound(cells, top, true, cells[-1])
	_gate(to_curb)
	# Scale house and truck scale by the gate.
	_building(func():
		_box("paint", Vector3(7.0, 0.3, 5.0), Vector3(12.0, 0.15, 9.0), CONCRETE)
		_box("siding", Vector3(6.0, 3.0, 4.0), Vector3(12.0, 1.8, 9.0), Color("#d8d4c8"))
		_box("paint", Vector3(6.6, 0.25, 4.6), Vector3(12.0, 3.4, 9.0), Color("#6f6d68"))
		_glass(Vector3(12.0, 1.9, 6.95), Vector3(-1, 0, 0), 2.4, 1.0, 0.3))
	_box("paint", Vector3(3.6, 0.25, 21.0), Vector3(5.5, 0.12, 14.0), CONCRETE)
	_flat_rect("gravel", -5.0, 3.5, 2.0, 32.0, 0.06, Color("#8d877c"))
	# Edge pieces: the grassed buffer between the mound and the fence.
	for c in edge_land:
		_grass_poly(edge_land[c])
	_fence_edges(_outline(cells, edge_land), 2.2, GALV, 4.0, 5.0)
	_landfill_devs(0.0)


## Gas plant, compost yard and transfer station, along the front of the site
## (`back` metres further in on a capped landfill behind a recycling yard).
func _landfill_devs(back: float) -> void:
	if "gas_plant" in dev:
		# Two engine-generator sets in containers, a flare and the gas header.
		var p := Vector3(-cell * 1.1, 0, 12.0 + back)
		_box("paint", Vector3(16.0, 0.3, 11.0), p + Vector3(0, 0.15, 0), CONCRETE)
		for k in 2:
			var e := p + Vector3(-3.5 + k * 7.0, 0, 0)
			_box("metal", Vector3(2.8, 3.0, 9.0), e + Vector3(0, 1.8, 0), Color("#3d5a46"))
			_cyl_y(e + Vector3(0, 4.6, -3.0), 0.3, 3.0, Color("#77797a"))
		_cyl_y(p + Vector3(6.5, 4.3, 3.5), 0.45, 8.0, Color("#9a9c98"))
		_box("paint", Vector3(0.3, 0.3, 20.0), p + Vector3(-5.0, 0.6, 14.0), Color("#e6e4dc"))
	if "compost" in dev:
		# Long windrows of dark compost on a gravel pad.
		var x0 := cell * 0.75
		_flat_rect("gravel", x0, x0 + 26.0, 4.0 + back, 30.0 + back, 0.07, Color("#7a7062"))
		for k in 4:
			var x := x0 + 3.0 + k * 6.5
			var z0 := 6.0 + back
			var z1 := 28.0 + back
			var col := Color("#4a3a2a").lightened(k * 0.03)
			_quad("paint", Vector3(x - 2.0, 0.1, z0), Vector3(x, 1.6, z0), Vector3(x, 1.6, z1), Vector3(x - 2.0, 0.1, z1), col, [], Vector3(-1, 1, 0))
			_quad("paint", Vector3(x + 2.0, 0.1, z0), Vector3(x, 1.6, z0), Vector3(x, 1.6, z1), Vector3(x + 2.0, 0.1, z1), col, [], Vector3(1, 1, 0))
	if "transfer" in dev:
		# A tipping building where neighbor towns' trucks unload.
		var p := Vector3(-cell * 0.45, 0, 14.0 + back)
		_box("paint", Vector3(18.0, 0.3, 16.0), p + Vector3(0, 0.15, 0), CONCRETE)
		_box("metal", Vector3(16.0, 8.0, 14.0), p + Vector3(0, 4.3, 0), Color("#b8b9b4"))
		_metal_roof(p.x, p.z, 8.3, 16.0, 14.0, Color("#8e9496"))
		_box("paint", Vector3(6.0, 5.5, 0.1), p + Vector3(0, 3.05, -7.05), Color("#2a2b2d"))


## A grassed mound over `set`, rising to `top` metres with 3:1 side slopes.
## Around `face`, a bare working face where trucks tip (when `working`).
func _mound(set: Array, top: float, working: bool, face: Vector2i) -> void:
	if set.is_empty():
		return
	var edges := _edges(set)
	var ramp := top * 3.0
	var step := 5.0
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for c in set:
		minx = minf(minx, (c.x - 0.5) * cell)
		maxx = maxf(maxx, (c.x + 0.5) * cell)
		minz = minf(minz, c.y * cell)
		maxz = maxf(maxz, (c.y + 1) * cell)
	var face_at := Vector2(face.x * cell, (face.y + 0.5) * cell)
	var nx := int(round((maxx - minx) / step))
	var nz := int(round((maxz - minz) / step))
	var height := {}
	for i in nx + 1:
		for j in nz + 1:
			var x := minx + i * step
			var z := minz + j * step
			if not _inside(set, x, z):
				continue
			var d := INF
			for e in edges:
				d = minf(d, Geometry2D.get_closest_point_to_segment(Vector2(x, z), e[0], e[1]).distance_to(Vector2(x, z)))
			var y := top * smoothstep(0.0, ramp, d)
			# Flat yard at the gate.
			y *= smoothstep(10.0, 32.0, z)
			height[Vector2i(i, j)] = y
	# Smooth shading: each corner's normal from the slope around it, and the
	# grass varies in broad patches, as on a real cap.
	var hf := func(q: Vector2i) -> float: return height.get(q, 0.0)
	var st := _tool("paint")
	for i in nx:
		for j in nz:
			var k := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			if not (height.has(k[0]) and height.has(k[1]) and height.has(k[2]) and height.has(k[3])):
				continue
			var pts := []
			var normals := []
			var cols := []
			for q in k:
				var p := Vector3(minx + q.x * step, height[q] + 0.05, minz + q.y * step)
				pts.append(p)
				var gx: float = (hf.call(q + Vector2i(1, 0)) - hf.call(q - Vector2i(1, 0))) / (2.0 * step)
				var gz: float = (hf.call(q + Vector2i(0, 1)) - hf.call(q - Vector2i(0, 1))) / (2.0 * step)
				normals.append(Vector3(-gx, 1.0, -gz).normalized())
				var patch := 0.5 + 0.25 * sin(p.x * 0.045 + 1.3) * sin(p.z * 0.06) + 0.25 * sin((p.x + p.z) * 0.021)
				var col: Color = GRASS_CAP[0].lerp(GRASS_CAP[1], patch)
				if working:
					var f := 1.0 - smoothstep(cell * 0.5, cell * 0.9, Vector2(p.x, p.z).distance_to(face_at))
					f *= smoothstep(top * 0.1, top * 0.3, p.y)
					col = col.lerp(WORKING, f)
				cols.append(col)
			for t in [0, 1, 2, 0, 2, 3]:
				st.set_normal(normals[t])
				st.set_color(cols[t])
				st.set_uv(Vector2(pts[t].x, pts[t].z))
				st.add_vertex(pts[t])
	# The haul road up to the working face.
	if working:
		var from := Vector2(0.0, 30.0)
		var n := int(from.distance_to(face_at) / step)
		var side := Vector2(-(face_at - from).y, (face_at - from).x).normalized() * 3.5
		for i in n:
			var a := from.lerp(face_at, float(i) / n)
			var b := from.lerp(face_at, float(i + 1) / n)
			var ya := _height_near(height, minx, minz, step, a) + 0.2
			var yb := _height_near(height, minx, minz, step, b) + 0.2
			_quad("paint", Vector3(a.x - side.x, ya, a.y - side.y), Vector3(a.x + side.x, ya, a.y + side.y),
				Vector3(b.x + side.x, yb, b.y + side.y), Vector3(b.x - side.x, yb, b.y - side.y), Color("#6e675b"),
				[], Vector3.UP)
	# A compactor on the working face, and gas vents on the cap.
	if working:
		var fy := _height_near(height, minx, minz, step, face_at)
		var base := Vector3(face_at.x, fy, face_at.y)
		_box("paint", Vector3(3.4, 2.2, 6.0), base + Vector3(0, 1.6, 0), Color("#d9a21b"))
		_box("paint", Vector3(2.0, 1.6, 2.2), base + Vector3(0, 3.4, -0.8), Color("#2b2c2e"))
		for zs in [-2.2, 2.2]:
			_box("metal", Vector3(3.8, 1.4, 1.4), base + Vector3(0, 0.7, zs), Color("#5c5e60"))
	var k := 0
	for q in height:
		k += 1
		if k % 37 != 0 or height[q] < 2.0:
			continue
		var at := Vector3(minx + q.x * step, height[q], minz + q.y * step)
		if working and Vector2(at.x, at.z).distance_to(face_at) < cell * 0.7:
			continue
		_box("paint", Vector3(0.25, 1.4, 0.25), at + Vector3(0, 0.7, 0), Color("#e6e4dc"))
		_box("paint", Vector3(0.5, 0.15, 0.5), at + Vector3(0, 1.45, 0), Color("#e6e4dc"))


func _height_near(height: Dictionary, minx: float, minz: float, step: float, at: Vector2) -> float:
	var q := Vector2i(roundi((at.x - minx) / step), roundi((at.y - minz) / step))
	return height.get(q, 0.0)


func _inside(set: Array, x: float, z: float) -> bool:
	for dx in [-0.01, 0.01]:
		for dz in [-0.01, 0.01]:
			if _piece_at(x + dx, z + dz) in set:
				return true
	return false


## The gravel drive in from the street.
func _gate(to_curb: float) -> void:
	_flat_rect("gravel", -4.0, 4.0, -to_curb, 2.0, 0.08, Color("#8d877c"))


# ---------------------------------------------------------------- recycling

func _recycling(h: Dictionary, to_curb: float) -> void:
	var level := int(str(h.kind).substr(10))
	var capped: bool = h.get("capped", false)
	var front := cells.filter(func(c): return c.y == 0)
	if capped:
		# The old landfill behind, capped and grassed over.
		_mound(cells.filter(func(c): return c.y >= 1), CivicHubs.mound_height(h), false, Vector2i.ZERO)
	_gate(to_curb)
	var yard_back := cell if capped else cell * 2.0
	_flat_rect("asphalt", -cell * 1.5 + 3.0, cell * 1.5 - 3.0, 2.0, yard_back - 3.0, 0.06)
	match level:
		1:
			# Roll-off containers in a row, each for one material, and an
			# attendant's booth.
			var n := 6
			for i in n:
				var x := -cell * 1.2 + i * (cell * 2.4 / (n - 1))
				var col: Color = BINS[i % BINS.size()]
				_box("metal", Vector3(2.5, 1.9, 6.8), Vector3(x, 1.05, yard_back - 10.0), col)
				_box("paint", Vector3(2.6, 0.12, 6.9), Vector3(x, 2.05, yard_back - 10.0), col.darkened(0.25))
			_building(func():
				_box("siding", Vector3(3.0, 2.6, 2.4), Vector3(cell * 0.9, 1.3, 8.0), Color("#d8d4c8"))
				_box("paint", Vector3(3.4, 0.2, 2.8), Vector3(cell * 0.9, 2.7, 8.0), Color("#6f6d68")))
		2:
			_building(func(): _plant(0.0, yard_back - 14.0, 40.0, 24.0, 9.0, Color("#c9cbc6")))
		3:
			_building(func(): _plant(-8.0, yard_back - 18.0, 64.0, 32.0, 12.0, Color("#bfc4c3")))
			_box("metal", Vector3(18.0, 16.0, 18.0), Vector3(30.0, 8.0, yard_back - 18.0), Color("#a9b0b0"))
			# Infeed conveyor up the side.
			var a := Vector3(-36.0, 1.0, 6.0)
			var b := Vector3(-30.0, 10.0, yard_back - 26.0)
			var mid := (a + b) * 0.5
			_box("metal", Vector3(1.6, 0.6, a.distance_to(b)), mid, Color("#6f7476"),
				Basis.looking_at(b - a, Vector3.UP))
	# Bales stacked in the yard and on the land it has grown into.
	_bale_row(-cell * 1.2, 6.0, level)
	for c in cells:
		if c.y == 0 or (capped and c.y >= 1) or (not capped and c.y == 1):
			continue
		_flat_rect("gravel", c.x * cell - cell * 0.5 + 2.0, c.x * cell + cell * 0.5 - 2.0, c.y * cell + 2.0,
			c.y * cell + cell - 2.0, 0.06, Color("#8d877c"))
		for r in 3:
			_bale_row(c.x * cell - cell * 0.4, c.y * cell + 6.0 + r * cell * 0.3, level)
	# Edge pieces: gravel pads stacked with bales, or the old landfill's
	# grassed cap behind a recycling yard on a capped landfill.
	var yard_edges := {}
	for c in edge_land:
		if capped and c.y >= 1:
			_grass_poly(edge_land[c])
			continue
		yard_edges[c] = edge_land[c]
		var pad := _inset(edge_land[c], 2.0)
		if pad.size() >= 3:
			_flat_poly_any("gravel", pad, 0.06, Color("#8d877c"))
			_bales_in(pad, level)
	_fence_edges(_outline(front if capped else cells, yard_edges), 2.2, GALV, 4.0, 5.0)
	if capped:
		_landfill_devs(cell)
	if "scrap_yard" in dev:
		var p := Vector3(cell * 1.15, 0, 12.0)
		for k in 6:
			var q := p + Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-5.0, 5.0))
			_box("paint", Vector3(rng.randf_range(3.0, 5.0), rng.randf_range(1.0, 2.2), rng.randf_range(3.0, 5.0)),
				q + Vector3(0, 0.8, 0), Color("#6b625a").lerp(Color("#8a8f92"), rng.randf()),
				Basis(Vector3.UP, rng.randf() * TAU))
		_box("paint", Vector3(2.6, 2.4, 5.0), p + Vector3(8.0, 1.5, 0), Color("#d9a21b"))
		_box("paint", Vector3(0.4, 0.4, 12.0), p + Vector3(8.0, 6.0, -4.0), Color("#d9a21b"),
			Basis(Vector3.RIGHT, -0.6))
	if "glass_line" in dev:
		# Concrete bunkers of green, brown and clear glass.
		var p := Vector3(-cell * 1.15, 0, 10.0)
		for k in 3:
			var x := p.x - 6.0 + k * 6.0
			for side in [-2.6, 2.6]:
				_box("paint", Vector3(0.4, 1.8, 6.0), Vector3(x + side, 0.9, p.z), CONCRETE)
			_box("paint", Vector3(0.4, 1.8, 5.6), Vector3(x, 0.9, p.z + 2.8), CONCRETE, Basis(Vector3.UP, PI * 0.5))
			_box("paint", Vector3(4.4, 0.8, 5.0), Vector3(x, 0.5, p.z),
				[Color("#3e6b3a"), Color("#6b4a2a"), Color("#c9d3d2")][k])
	if "ewaste" in dev:
		var p := Vector3(14.0, 0, 12.0)
		_box("brick", Vector3(12.0, 4.5, 9.0), p + Vector3(0, 2.25, 0), Color("#a49d8f"))
		_box("paint", Vector3(12.6, 0.3, 9.6), p + Vector3(0, 4.6, 0), Color("#6f6d68"))
		_overhead_door(p.x, p.z - 4.5, 3.6, 3.4, Color("#e9e7e0"))
	if "regional_mrf" in dev:
		# Transfer trailers waiting to haul a neighbor's sorted loads.
		for k in 3:
			_box("metal", Vector3(2.6, 3.6, 14.0), Vector3(-22.0 + k * 3.6, 2.2, 28.0), Color("#c9cbc6"))


## A steel sorting building with overhead doors facing the yard.
func _plant(cx: float, cz: float, w: float, d: float, h: float, wall: Color) -> void:
	_box("paint", Vector3(w + 1.0, 0.3, d + 1.0), Vector3(cx, 0.15, cz), CONCRETE)
	_box("metal", Vector3(w, h, d), Vector3(cx, h * 0.5 + 0.3, cz), wall)
	_metal_roof(cx, cz, h + 0.3, w, d, Color("#8e9496"))
	var doors := int(w / 12.0)
	for i in doors:
		_overhead_door(cx - w * 0.5 + (i + 0.5) * w / doors, cz - d * 0.5, 4.2, 4.8, Color("#e9e7e0"))
	_sign(Vector3(cx + w * 0.3, h - 1.5, cz - d * 0.5 - 0.1), 4.0, 1.0)


## A row of bales: cardboard, paper, plastic and cans, two or three high.
func _bale_row(x0: float, z: float, level: int) -> void:
	var n := 6 + level * 3
	for i in n:
		var col: Color = BALES[(i + int(z)) % BALES.size()].lightened(rng.randf_range(-0.05, 0.05))
		var high := 2 + rng.randi() % 2
		for k in high:
			_box("paint", Vector3(1.1, 0.8, 1.5), Vector3(x0 + i * 1.3, 0.4 + k * 0.82, z), col)


# ---------------------------------------------------------------- cemetery

func _cemetery(to_curb: float) -> void:
	_clear = [Rect2(-cell * 0.6 - 4.0, cell * 1.4 - 5.0, 8.0, 10.0)]
	if "chapel" in dev:
		_clear.append(Rect2(cell * 0.6 - 6.0, cell * 1.3 - 9.0, 12.0, 18.0))
	if "garden" in dev:
		_clear.append(Rect2(-cell * 0.6 - 8.0, 8.0, 16.0, 14.0))
	if "veterans" in dev:
		_clear.append(Rect2(cell * 0.6 - 8.0, 6.0, 16.0, 12.0))
	var lane := Color("#b9b2a2")
	_flat_rect("gravel", -2.0, 2.0, -to_curb, 2.0, 0.08, lane)
	for i in cells.size():
		var c: Vector2i = cells[i]
		var x0: float = c.x * cell - cell * 0.5
		var x1: float = x0 + cell
		var z0: float = c.y * cell
		# A lane along each section's front and one down the middle.
		_flat_rect("gravel", x0, x1, z0, z0 + 3.0, 0.06, lane)
		_flat_rect("gravel", c.x * cell - 1.5, c.x * cell + 1.5, z0, z0 + cell, 0.06, lane)
		# Older sections are full; newer ones are still filling in.
		var fill := 1.0 if i < CivicHubs.BASE.size() else maxf(0.2, 0.75 - 0.12 * (i - CivicHubs.BASE.size()))
		var z := z0 + 6.0
		while z < z0 + cell - 2.5:
			var x := x0 + 2.5
			while x < x1 - 2.0:
				if absf(x - c.x * cell) > 2.5 and rng.randf() < fill and not _kept_clear(x, z) \
						and not ("woods" in dev and i >= CivicHubs.BASE.size() and rng.randf() < 0.7):
					_stone(Vector3(x + rng.randf_range(-0.1, 0.1), 0, z), i < CivicHubs.BASE.size())
				x += 1.9
			z += 3.4
		# Shade trees inside the bigger sections.
		if rng.randf() < 0.6:
			trees.append([Vector3(x0 + rng.randf_range(6.0, cell - 6.0), 0, z0 + rng.randf_range(8.0, cell - 6.0)),
				TreeField.Species.OAK if rng.randf() < 0.5 else TreeField.Species.MAPLE,
				TreeField.LEAF[TreeField.Species.OAK], rng.randf_range(0.9, 1.2)])
	# Edge pieces: newer sections still filling in, up to the fence.
	for c in edge_land:
		var plot := _inset(edge_land[c], 2.5)
		if plot.size() < 3:
			continue
		var box := _bounds(plot)
		var z: float = c.y * cell + 6.0
		while z < box.end.y:
			var x: float = c.x * cell - cell * 0.5 + 2.5
			while x < box.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, z), plot) and rng.randf() < 0.45 and not _kept_clear(x, z):
					_stone(Vector3(x + rng.randf_range(-0.1, 0.1), 0, z), false)
				x += 1.9
			z += 3.4
	var outline := _outline(cells, edge_land)
	# Evergreens and shade trees along the edge.
	for e in outline:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var len := a.distance_to(b)
		var n := int(len / 14.0)
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			if absf(p.y) < 0.5 and absf(p.x) < 8.0:
				continue  # keep the gate open
			var inward := _inward(a, b)
			var sp := TreeField.Species.SPRUCE if k % 2 == 0 else TreeField.Species.MAPLE
			trees.append([Vector3(p.x, 0, p.y) + inward * 3.0, sp, TreeField.LEAF[sp], rng.randf_range(0.8, 1.1)])
	_fence_edges(outline, 1.5, IRON, 2.4, 3.0)
	for x in [-3.2, 3.2]:
		_box("brick", Vector3(0.7, 2.2, 0.7), Vector3(x, 1.1, 0.0), Color("#8a4a38"))
		_box("paint", Vector3(0.85, 0.15, 0.85), Vector3(x, 2.27, 0.0), CONCRETE)
	_flagpole(Vector3(7.0, 0, 5.0))
	_building(func():
		_mausoleum(Vector3(-cell * 0.6, 0, cell * 1.4))
		if "chapel" in dev:
			_chapel(Vector3(cell * 0.6, 0, cell * 1.3)))
	if "garden" in dev:
		var g := Vector3(-cell * 0.6, 0, 15.0)
		_flat_rect("gravel", g.x - 7.0, g.x + 7.0, g.z - 6.0, g.z + 6.0, 0.07, Color("#b9b2a2"))
		_cyl_y(g + Vector3(0, 0.3, 0), 1.6, 0.6, Color("#bdb6a8"))
		_cyl_y(g + Vector3(0, 0.9, 0), 0.25, 1.2, Color("#bdb6a8"))
		for k in 6:
			var a := TAU * k / 6.0
			var q := g + Vector3(cos(a) * 4.5, 0, sin(a) * 4.0)
			_box("paint", Vector3(2.2, 0.3, 1.2), q + Vector3(0, 0.15, 0), Color("#4a3426"))
			for f in 4:
				_box("paint", Vector3(0.35, 0.35, 0.35), q + Vector3(-0.8 + f * 0.55, 0.45, 0),
					[Color("#c23b4a"), Color("#e8c547"), Color("#f2f0ea"), Color("#8a5bbf")][(k + f) % 4])
	if "veterans" in dev:
		var v := Vector3(cell * 0.6, 0, 12.0)
		_box("paint", Vector3(7.0, 0.3, 7.0), v + Vector3(0, 0.15, 0), CONCRETE)
		_box("paint", Vector3(1.2, 4.5, 1.2), v + Vector3(0, 2.55, 0), Color("#8d8a86"))
		for k in 5:
			var a := PI * (0.15 + k * 0.175)
			_flagpole(v + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0 - 1.0))
	if "woods" in dev:
		for i in range(CivicHubs.BASE.size(), cells.size()):
			var c: Vector2i = cells[i]
			for k in 4:
				var sp := TreeField.Species.OAK if k % 2 == 0 else TreeField.Species.MAPLE
				trees.append([Vector3(c.x * cell + rng.randf_range(-cell * 0.4, cell * 0.4), 0,
					c.y * cell + rng.randf_range(5.0, cell - 4.0)), sp, TreeField.LEAF[sp], rng.randf_range(0.9, 1.25)])


func _inward(a: Vector2, b: Vector2) -> Vector3:
	var mid := (a + b) * 0.5
	var n := Vector2(-(b - a).y, (b - a).x).normalized()
	if _in_land(mid.x + n.x * 2.0, mid.y + n.y * 2.0):
		return Vector3(n.x, 0, n.y)
	return Vector3(-n.x, 0, -n.y)


## An upright granite tablet, a flat marker or now and then an obelisk.
func _stone(p: Vector3, old: bool) -> void:
	var col: Color = GRANITE[rng.randi() % GRANITE.size()]
	var r := rng.randf()
	var lean := Basis.IDENTITY
	if old and rng.randf() < 0.15:
		lean = Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
	_box("paint", Vector3(0.9, 0.12, 0.45), p + Vector3(0, 0.06, 0), col.darkened(0.1))
	if r < 0.7:
		var w := rng.randf_range(0.6, 0.95)
		var h := rng.randf_range(0.55, 1.0)
		_box("paint", Vector3(w, h, rng.randf_range(0.14, 0.22)), p + Vector3(0, 0.1 + h * 0.5, 0), col, lean)
	elif r < 0.96:
		_box("paint", Vector3(0.7, 0.08, 0.35), p + Vector3(0, 0.16, 0), col)
	else:
		_box("paint", Vector3(0.45, 0.4, 0.45), p + Vector3(0, 0.3, 0), col)
		_box("paint", Vector3(0.3, 1.9, 0.3), p + Vector3(0, 1.45, 0), col)


## A small stone mausoleum with a pediment.
func _mausoleum(p: Vector3) -> void:
	var stone := Color("#bdb6a8")
	_box("paint", Vector3(5.0, 0.4, 6.0), p + Vector3(0, 0.2, 0), stone.darkened(0.1))
	_box("paint", Vector3(4.2, 3.4, 5.2), p + Vector3(0, 2.1, 0), stone)
	_box("paint", Vector3(4.6, 0.3, 5.6), p + Vector3(0, 3.95, 0), stone.lightened(0.05))
	var y := 4.1
	var roof := Color("#6e6d6a")
	for side in [-1.0, 1.0]:
		var z: float = p.z + side * 2.8
		_tri("paint", Vector3(p.x - 2.3, y, z), Vector3(p.x + 2.3, y, z), Vector3(p.x, y + 1.0, z), stone,
			[], Vector3(0, 0, side))
		_quad("roof", Vector3(p.x + side * 2.3, y, p.z - 2.8), Vector3(p.x + side * 2.3, y, p.z + 2.8),
			Vector3(p.x, y + 1.0, p.z + 2.8), Vector3(p.x, y + 1.0, p.z - 2.8), roof, [], Vector3(side, 1, 0))
	_box("paint", Vector3(1.2, 2.2, 0.08), p + Vector3(0, 1.5, -2.62), Color("#3b3a36"))


func _kept_clear(x: float, z: float) -> bool:
	for r in _clear:
		if (r as Rect2).has_point(Vector2(x, z)):
			return true
	return false


## A small white clapboard chapel with a steeple, facing the lane.
func _chapel(p: Vector3) -> void:
	var white := Color("#ece9e0")
	_box("paint", Vector3(8.0, 0.5, 13.0), p + Vector3(0, 0.25, 0), CONCRETE)
	_box("siding", Vector3(7.0, 4.5, 12.0), p + Vector3(0, 2.75, 0), white)
	_gable_roof(p.x, p.z, 5.0, 7.0, 2.8, 12.0, false, Color("#5c5c5e"), white, false)
	_box("siding", Vector3(2.6, 3.0, 2.6), p + Vector3(0, 9.3, -4.6), white)
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var b := p + Vector3(0, 10.8, -4.6)
		_tri("roof", b + Vector3(-1.4, 0, -1.4).rotated(Vector3.UP, atan2(side.x, side.z)),
			b + Vector3(1.4, 0, -1.4).rotated(Vector3.UP, atan2(side.x, side.z)), b + Vector3(0, 4.0, 0),
			Color("#5c5c5e"), [], side + Vector3(0, 0.3, 0))
	_box("paint", Vector3(1.4, 2.4, 0.1), p + Vector3(0, 1.7, -6.05), Color("#6b2a22"))
	for z in [-3.0, 0.0, 3.0]:
		for x in [-3.55, 3.55]:
			_glass(Vector3(p.x + x, 3.0, p.z + z), Vector3(0, 0, 1 if x > 0 else -1), 0.9, 1.8, 0.0)
