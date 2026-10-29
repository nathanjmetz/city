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
	EdgeGrounds.fence(self, runs, h, col, gap)


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
	out.append_array(_edge_sides(set, with))
	return out


## Each side of the edge pieces `with` (local outlines), less what runs
## along one of `set`'s pieces or another edge piece of `all` (by default
## `with` itself), as [a, b] pairs.
func _edge_sides(set: Array, with: Dictionary, all := {}) -> Array:
	return EdgeGrounds.sides(set, cell, with, all)


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
	var st := _tool("pasture")
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
			# The flat yard at the gate (the scale and the scale house) is
			# an edge too: the 3:1 side slope rises from it.
			d = minf(d, Vector2(maxf(absf(x) - 18.0, 0.0), maxf(z - 26.0, 0.0)).length())
			height[Vector2i(i, j)] = top * smoothstep(0.0, ramp, d)
	# Smooth shading: each corner's normal from the slope around it, and the
	# grass varies in broad patches, as on a real cap.
	var hf := func(q: Vector2i) -> float: return height.get(q, 0.0)
	# Mowed grass, matte (the pasture ground's look and seasons); the
	# working face mottled in fresh trash and the day's soil cover.
	var st := _tool("pasture")
	var mottle := {}
	for q in height:
		mottle[q] = rng.randf_range(-0.22, 0.12)
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
					var m: float = mottle[q]
					col = col.lerp(WORKING.darkened(m) if m > 0.0 else WORKING.lightened(-m * 0.6), f)
				cols.append(col)
			for t in [0, 1, 2, 0, 2, 3]:
				st.set_normal(normals[t])
				st.set_color(cols[t])
				st.set_uv(Vector2(pts[t].x, pts[t].z))
				st.add_vertex(pts[t])
	# The haul road up to the working face.
	if working:
		_drape_strip(height, minx, minz, step, Vector2(0.0, 24.0), face_at, 3.5, Color("#6e675b"), 0.15)
	# A compactor on the working face, and gas vents on the cap.
	if working:
		var fy := _height_near(height, minx, minz, step, face_at)
		var base := Vector3(face_at.x, fy, face_at.y)
		_box("paint", Vector3(3.4, 2.2, 6.0), base + Vector3(0, 1.6, 0), Color("#d9a21b"))
		_box("paint", Vector3(2.0, 1.6, 2.2), base + Vector3(0, 3.4, -0.8), Color("#2b2c2e"))
		for zs in [-2.2, 2.2]:
			_box("metal", Vector3(3.8, 1.4, 1.4), base + Vector3(0, 0.7, zs), Color("#5c5e60"))
	if working:
		_working_face(height, minx, minz, step, face_at, top)
	_downchutes(set, height, minx, minz, step, ramp, face_at if working else Vector2(INF, INF))
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


## What a working face looks like from the road: the day's trash spread
## and pushed (white and black bags, cardboard, blue tarps), a dozer
## spreading it, a tri-axle tipping, and portable litter fences downwind
## (benchmarked on Indiana county landfills' aerial photos).
func _working_face(height: Dictionary, minx: float, minz: float, step: float, face_at: Vector2, top: float) -> void:
	var trash := [Color("#e8e6df"), Color("#d9d6cc"), Color("#2a2b2d"), Color("#3a3b3d"), Color("#a8865a"),
		Color("#3a6ea8"), Color("#8a8c88"), Color("#c9c2a8")]
	var reach := cell * 0.42
	for i in 260:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * reach
		var at := face_at + Vector2(cos(a), sin(a)) * r
		var y := _height_at(height, minx, minz, step, at)
		if y < top * 0.3:
			continue
		var sz := rng.randf_range(0.3, 1.1)
		_box("paint", Vector3(sz, rng.randf_range(0.15, 0.45), sz * rng.randf_range(0.6, 1.4)), Vector3(at.x, y + 0.15, at.y),
			trash[rng.randi() % trash.size()], Basis(Vector3.UP, rng.randf() * TAU))
	# A dozer spreading the day's load, blade down.
	var dz := face_at + Vector2(-9.0, 6.0)
	var dy := _height_at(height, minx, minz, step, dz)
	var yaw := Basis(Vector3.UP, 0.6)
	var d := Vector3(dz.x, dy, dz.y)
	_box("paint", Vector3(2.6, 1.6, 4.2), d + yaw * Vector3(0, 1.3, 0), Color("#d9a21b"), yaw)
	_box("paint", Vector3(1.6, 1.4, 1.6), d + yaw * Vector3(0, 2.8, 0.6), Color("#2b2c2e"), yaw)
	_box("paint", Vector3(3.8, 1.3, 0.3), d + yaw * Vector3(0, 0.75, -2.7), Color("#c99418"), yaw)
	for sx in [-1.0, 1.0]:
		_box("metal", Vector3(0.6, 0.9, 4.0), d + yaw * Vector3(sx * 1.4, 0.45, 0), Color("#3a3b3d"), yaw)
	# A tri-axle dump truck tipping at the edge of the face.
	var tz := face_at + Vector2(10.0, -8.0)
	var ty := _height_at(height, minx, minz, step, tz)
	var tyaw := Basis(Vector3.UP, -0.4)
	var t := Vector3(tz.x, ty, tz.y)
	_box("paint", Vector3(2.5, 2.4, 2.4), t + tyaw * Vector3(0, 1.7, -3.6), Color("#e8e6df"), tyaw)
	_box("paint", Vector3(1.0, 0.5, 7.4), t + tyaw * Vector3(0, 0.8, 0), Color("#2b2c2e"), tyaw)
	_box("paint", Vector3(2.5, 1.5, 5.4), t + tyaw * Vector3(0, 2.6, 1.6), Color("#a83a2a"), tyaw * Basis(Vector3.RIGHT, -0.45))
	# Portable litter fences: chain-link panels on skids, 5 m tall.
	for k in 3:
		var a := 2.2 + k * 0.35
		var p0 := face_at + Vector2(cos(a), sin(a)) * (reach + 6.0)
		var p1 := face_at + Vector2(cos(a + 0.3), sin(a + 0.3)) * (reach + 6.0)
		var y0 := _height_at(height, minx, minz, step, p0)
		var y1 := _height_at(height, minx, minz, step, p1)
		var q0 := Vector3(p0.x, y0, p0.y)
		var q1 := Vector3(p1.x, y1, p1.y)
		for q in [q0, q1]:
			_box("paint", Vector3(0.12, 5.0, 0.12), q + Vector3(0, 2.5, 0), GALV)
		_quad("chain", q0 + Vector3(0, 0.3, 0), q1 + Vector3(0, 0.3, 0), q1 + Vector3(0, 5.0, 0), q0 + Vector3(0, 5.0, 0), GALV,
			[Vector2(0, 0), Vector2(q0.distance_to(q1), 0), Vector2(q0.distance_to(q1), 4.7), Vector2(0, 4.7)],
			Vector3(q1.z - q0.z, 0, q0.x - q1.x))


## Rock-lined downchutes carrying the cap's runoff straight down the side
## slopes to the perimeter ditch, one on each long side.
func _downchutes(set: Array, height: Dictionary, minx: float, minz: float, step: float, ramp: float, face_at: Vector2) -> void:
	var mid := Vector2.ZERO
	for c in set:
		mid += Vector2(c.x * cell, (c.y + 0.5) * cell)
	mid /= set.size()
	var rock := Color("#706d66")
	for e in _sides(set):
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var m := (a + b) * 0.5
		if absf(m.y) < 0.5 or m.distance_to(face_at) < cell * 0.6:
			continue  # the gate side, or the working face
		var ab := (b - a).normalized()
		var inward := Vector2(-ab.y, ab.x)
		if inward.dot(mid - m) < 0.0:
			inward = -inward
		var end := m + inward * ramp
		if not _inside(set, end.x, end.y):
			continue
		if Geometry2D.get_closest_point_to_segment(face_at, m, end).distance_to(face_at) < cell * 0.6:
			continue  # it would run over the working face
		_drape_strip(height, minx, minz, step, m + inward * 0.3, end, 1.2, rock, 0.1)


## A strip laid on the mound from `a` to `b`, `half` wide each side of its
## middle: every vertex on the surface (2 m along, three across), so it
## follows the slope instead of floating over it.
func _drape_strip(height: Dictionary, minx: float, minz: float, step: float, a: Vector2, b: Vector2, half: float,
		col: Color, lift: float) -> void:
	var n := maxi(1, int(a.distance_to(b) / 2.0))
	var side := Vector2(-(b - a).y, (b - a).x).normalized() * half
	var on := func(q: Vector2) -> Vector3: return Vector3(q.x, _height_at(height, minx, minz, step, q) + lift, q.y)
	for i in n:
		var p := a.lerp(b, float(i) / n)
		var q := a.lerp(b, float(i + 1) / n)
		var shade := col.darkened(rng.randf_range(0.0, 0.06))
		for k in [-1.0, 0.0]:
			var p0: Vector2 = p + side * k
			var p1: Vector2 = p + side * (k + 1.0)
			var q0: Vector2 = q + side * k
			var q1: Vector2 = q + side * (k + 1.0)
			# The yard shader's loose gravel (alpha 1): rock and haul road grit.
			_quad("yard", on.call(p0), on.call(p1), on.call(q1), on.call(q0), shade, [], Vector3.UP)


## The outside edges of `set` joined into whole straight sides.
func _sides(set: Array) -> Array:
	var lines := {}
	for e in _edges(set):
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var key := "x%d" % roundi(a.x) if absf(a.x - b.x) < 0.01 else "z%d" % roundi(a.y)
		if not lines.has(key):
			lines[key] = []
		lines[key].append(e)
	var out := []
	for key in lines:
		var along_x: bool = str(key).begins_with("z")
		var segs: Array = lines[key]
		segs.sort_custom(func(p, q): return (p[0].x if along_x else p[0].y) < (q[0].x if along_x else q[0].y))
		var cur: Array = [segs[0][0], segs[0][1]]
		for k in range(1, segs.size()):
			var s0: Vector2 = segs[k][0]
			if s0.distance_to(cur[1]) < 0.01:
				cur[1] = segs[k][1]
			else:
				out.append(cur)
				cur = [segs[k][0], segs[k][1]]
		out.append(cur)
	return out


## The mound's height at `at`, on the same two triangles per grid square
## the mesh draws, so things laid on it sit on it.
func _height_at(height: Dictionary, minx: float, minz: float, step: float, at: Vector2) -> float:
	var fx := (at.x - minx) / step
	var fz := (at.y - minz) / step
	var i := floori(fx)
	var j := floori(fz)
	var u := fx - i
	var v := fz - j
	var h0: float = height.get(Vector2i(i, j), 0.0)
	var h1: float = height.get(Vector2i(i + 1, j), 0.0)
	var h2: float = height.get(Vector2i(i + 1, j + 1), 0.0)
	var h3: float = height.get(Vector2i(i, j + 1), 0.0)
	if u >= v:
		return h0 + u * (h1 - h0) + v * (h2 - h1)
	return h0 + v * (h3 - h0) + u * (h2 - h3)


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
	# A drop-off paves only what its traffic needs; the rest stays mowed.
	var paved := yard_back if level > 1 else minf(yard_back, cell + 8.0)
	_flat_rect("asphalt", -cell * 1.5 + 3.0, cell * 1.5 - 3.0, 2.0, paved - 3.0, 0.06)
	if paved < yard_back:
		_grass_poly(PackedVector2Array([Vector2(-cell * 1.5, paved - 3.0), Vector2(cell * 1.5, paved - 3.0),
			Vector2(cell * 1.5, yard_back), Vector2(-cell * 1.5, yard_back)]))
	match level:
		1:
			# The attendant's booth by the gate (the roll-offs are at the
			# drop-off dock, below).
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
	_drop_off(Vector3(cell * 0.92, 0, 14.0))
	_recycling_yard(level, paved)
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


## The public drop-off, as at county solid waste district sites: residents
## drive up a ramp onto a raised concrete dock and tip into open-top
## roll-offs set below its wall, one per material, each under its own
## sign; bollards along the edge and a guard rail behind them. `c` is the
## middle of the dock's front edge.
func _drop_off(c: Vector3) -> void:
	var deck := 1.4
	var len := 28.0
	var ramp := 7.0
	var dz := 8.0
	_box("paint", Vector3(len, deck, dz), c + Vector3(0, deck * 0.5, dz * 0.5), CONCRETE)
	for sx in [-1.0, 1.0]:
		var e: float = c.x + sx * len * 0.5
		var f: float = e + sx * ramp
		_quad("paint", Vector3(e, deck, c.z), Vector3(f, 0.06, c.z), Vector3(f, 0.06, c.z + dz), Vector3(e, deck, c.z + dz),
			CONCRETE.darkened(0.04), [], Vector3(sx * 0.2, 1, 0))
		for z in [c.z, c.z + dz]:
			_tri("paint", Vector3(e, deck, z), Vector3(f, 0.06, z), Vector3(e, 0.06, z), CONCRETE.darkened(0.1), [],
				Vector3(0, 0, -1 if z == c.z else 1))
	# Bollards along the tipping edge and a rail along the front.
	var back := c.z + dz
	var x := c.x - len * 0.5 + 1.0
	while x < c.x + len * 0.5 - 0.5:
		_dr_bollard(Vector3(x, deck, back - 0.4))
		x += 2.3
	_box("paint", Vector3(len, 0.08, 0.08), c + Vector3(0, deck + 1.0, 0.3), Color("#e0b81e"))
	for k in 8:
		_box("paint", Vector3(0.08, 1.0, 0.08), c + Vector3(-len * 0.5 + 0.2 + k * (len - 0.4) / 7.0, deck + 0.5, 0.3), Color("#e0b81e"))
	# The roll-offs below the wall: open tops, side ribs, what's in them.
	var stuff := [["CARDBOARD", Color("#a8865a"), BINS[0]], ["PAPER", Color("#cfcbc0"), BINS[1]],
		["PLASTIC 1-2", Color("#d9dcdc"), BINS[0]], ["CANS", Color("#b8bcbe"), BINS[2]],
		["GLASS", Color("#4f6f4a"), BINS[1]], ["OIL", Color("#2a2b2d"), BINS[3]]]
	for i in stuff.size():
		var rx: float = c.x - len * 0.5 + 2.3 + i * (len - 4.6) / (stuff.size() - 1)
		var rz := back + 3.9
		var col: Color = stuff[i][2]
		_box("metal", Vector3(2.4, 1.6, 6.8), Vector3(rx, 0.95, rz), col)
		_box("paint", Vector3(2.0, 0.1, 6.4), Vector3(rx, 1.62, rz), stuff[i][1])
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.1, 0.12, 6.9), Vector3(rx + sx * 1.22, 1.8, rz), col.darkened(0.2))
			var z := rz - 2.8
			while z < rz + 3.0:
				_box("paint", Vector3(0.08, 1.5, 0.12), Vector3(rx + sx * 1.25, 0.95, z), col.darkened(0.12))
				z += 1.4
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(2.5, 0.12, 0.1), Vector3(rx, 1.8, rz + sz * 3.45), col.darkened(0.2))
		# The material's sign on two posts at the back.
		for sx in [-0.7, 0.7]:
			_box("paint", Vector3(0.08, 3.2, 0.08), Vector3(rx + sx, 1.6, rz + 3.9), GALV)
		_box("paint", Vector3(2.0, 0.8, 0.05), Vector3(rx, 2.9, rz + 3.85), col.lightened(0.15))
		_box("paint", Vector3(1.7, 0.18, 0.06), Vector3(rx, 2.95, rz + 3.82), Color("#f2f0ea"))


## The working yard behind the gate: baled material stacked in blocks,
## empty roll-offs waiting, trucks at the plant, light poles.
func _recycling_yard(level: int, yard_back: float) -> void:
	# Bale blocks, three high, on the left behind the bale row at the gate.
	var z := 22.0
	while z < minf(yard_back - 8.0, 62.0):
		_bale_row(-cell * 1.35, z, level)
		_bale_row(-cell * 1.35, z + 1.6, level)
		z += 9.0
	# Empty roll-offs lined up on the right, waiting for a truck.
	for i in 4:
		var col: Color = BINS[(i + 1) % BINS.size()]
		var q := Vector3(cell * 1.3, 0, minf(46.0, yard_back - 20.0) + i * 3.4)
		_box("metal", Vector3(6.8, 1.6, 2.4), q + Vector3(0, 0.95, 0), col)
		_box("paint", Vector3(6.4, 0.1, 2.0), q + Vector3(0, 1.62, 0), col.darkened(0.45))
	# The plant's trucks: a tractor-trailer at the dock and a front-loader.
	if level >= 2:
		var front := yard_back - (28.0 if level == 2 else 34.0)
		_dr_trailer(Vector3(-8.0, 0, front - 8.5))
		_dr_trailer(Vector3(-2.0 if level == 2 else 4.0, 0, front - 8.5))
		var t := Vector3(12.0, 0, front - 12.0)
		_box("paint", Vector3(2.5, 2.6, 2.4), t + Vector3(0, 1.75, -3.2), Color("#e9e7e0"))
		_box("paint", Vector3(2.5, 3.0, 5.2), t + Vector3(0, 2.0, 0.9), Color("#3f6d3a"))
		_box("paint", Vector3(0.9, 0.5, 6.8), t + Vector3(0, 0.6, -0.3), Color("#1c1d1f"))
		_box("paint", Vector3(2.2, 0.15, 2.0), t + Vector3(0, 3.9, -2.6), Color("#5a5e60"))
	# Light poles round the yard.
	for p in [Vector3(-cell * 0.6, 0, 4.0), Vector3(cell * 0.4, 0, 40.0), Vector3(-cell * 1.4, 0, yard_back - 6.0),
			Vector3(cell * 1.4, 0, yard_back - 6.0)]:
		_cyl_y(p + Vector3(0, 5.5, 0), 0.12, 11.0, GALV)
		_box("paint", Vector3(0.7, 0.3, 0.55), p + Vector3(0, 11.1, 0.3), Color("#4a4e52"))


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
