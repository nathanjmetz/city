extends RefCounted
## A copy of how FarmView drew a farm's fields and lane all at once, before
## they were spread over frames (scripts/farms/farm_view.gd on main at
## 6eb2ed2, "Measure the new drawing style on the 20-block town"), cut down
## to one farm. tests/test_farm_view.gd draws every farm with this and with
## the frame-by-frame job and compares the triangles: the new drawing must
## give the same picture. Do not "fix" this file; it is the reference.

const HEADLAND := 18.0


## [fields mesh (draped), lane mesh (draped), trees] for the farm `id`.
static func draw(sim: CitySim, id: Variant) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lanes := SurfaceTool.new()
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f: Dictionary = sim.farms.farms[id]
	var trimmed: Dictionary = sim.farms.trim.get(id, {})
	var owned := {}
	for c in f.cells:
		owned[c] = true
	for c in f.cells:
		var fl := CropPlan.field(f, c)
		var slot := slot_of(id, f, c)
		var col := CropFields.color(slot.x, slot.y)
		if trimmed.has(c):
			for poly in trimmed[c]:
				_add_poly(st, f, poly, 0.06, col, false, fl.crop != "pasture")
		elif fl.crop == "pasture":
			_add_poly(st, f, Farms.cell_corners(f, c), 0.06, col, false, false)
		else:
			_add_cell(st, f, c, owned, col)
	var trees := _fencerows(st, id, f, sim)
	var fields: ArrayMesh = null
	if f.cells.size() > 0:
		fields = Terrain.drape(st.commit(), true, 10.0)
	var lane: ArrayMesh = null
	if f.drive.size() >= 2:
		var pts := PackedVector3Array()
		for p in f.drive:
			pts.append(p)
		RoadMesh.add_strip(lanes, Terrain.densify(pts, 6.0), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.05)
		lane = Terrain.drape(lanes.commit(), true, 8.0)
	return [fields, lane, trees]


static func slot_of(id: Variant, f: Dictionary, c: Vector2i) -> Vector2i:
	var fl := CropPlan.field(f, c)
	var practice := CropCalendar.farm_practice(int(id), f)
	if fl.cover or fl.cover_prev:
		practice = CropCalendar.RYE
	var row := CropCalendar.farm_row(str(fl.crop), str(fl.prev), practice, bool(fl.cover), bool(fl.cover_prev))
	var col := int(Farms._hash01(Farms.forty_of(c) + Vector2i(int(id) * 7, 3), 23) * CropCalendar.COLS)
	return Vector2i(row, clampi(col, 0, CropCalendar.COLS - 1))


static func _add_cell(st: SurfaceTool, f: Dictionary, c: Vector2i, owned: Dictionary, col: Color) -> void:
	var corners := Farms.cell_corners(f, c)
	var forty := Farms.forty_of(c)
	var front := not owned.has(c - Vector2i(0, 1)) or Farms.forty_of(c - Vector2i(0, 1)) != forty
	var back := not owned.has(c + Vector2i(0, 1)) or Farms.forty_of(c + Vector2i(0, 1)) != forty
	var h := HEADLAND / Farms.CELL
	var t0 := h if front else 0.0
	var t1 := 1.0 - h if back else 1.0
	var mid := PackedVector2Array([corners[0].lerp(corners[3], t0), corners[1].lerp(corners[2], t0),
		corners[1].lerp(corners[2], t1), corners[0].lerp(corners[3], t1)])
	_add_poly(st, f, mid, 0.06, col)
	var turn := Color(col.r, col.g, 0.96, col.a)
	if front:
		_add_poly(st, f, PackedVector2Array([corners[0], corners[1], mid[1], mid[0]]), 0.06, turn, true)
	if back:
		_add_poly(st, f, PackedVector2Array([mid[3], mid[2], corners[2], corners[3]]), 0.06, turn, true)


static func _add_poly(st: SurfaceTool, f: Dictionary, poly: PackedVector2Array, y: float, col: Color, across := false,
		rows := true) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	var right := Vector2(-f.dir.z, f.dir.x)
	var back := Vector2(-f.dir.x, -f.dir.z)
	var origin := Vector2(f.pos.x, f.pos.z)
	for k in range(0, tris.size(), 3):
		var a := poly[tris[k]]
		var b := poly[tris[k + 1]]
		var c := poly[tris[k + 2]]
		var order := [a, b, c] if (b - a).cross(c - a) > 0.0 else [a, c, b]
		for p in order:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			var d: Vector2 = p - origin
			if not rows:
				st.set_uv(Vector2(0.38 / 16.0, 0.0))
				st.add_vertex(Vector3(p.x, y, p.y))
				continue
			st.set_uv((Vector2(d.dot(back), d.dot(right)) if across else Vector2(d.dot(right), d.dot(back))) / 16.0)
			st.add_vertex(Vector3(p.x, y, p.y))


static func _fencerows(st: SurfaceTool, id: Variant, f: Dictionary, sim: CitySim) -> Array:
	var verge := CropFields.color(0, 0, true)
	var planted := []
	var sides := [[Vector2i(-1, 0), 0, 3], [Vector2i(1, 0), 1, 2], [Vector2i(0, -1), 0, 1], [Vector2i(0, 1), 3, 2]]
	var owned := {}
	for c in f.cells:
		owned[c] = true
	var trimmed: Dictionary = sim.farms.trim.get(id, {})
	for c in f.cells:
		var corners := Farms.cell_corners(f, c)
		var mid := Farms.cell_center(f, c)
		var kept := []
		for piece in trimmed.get(c, []):
			kept.append_array(Geometry2D.offset_polygon(piece, 1.5))
		for s in sides:
			var n: Vector2i = c + s[0]
			var inner := owned.has(n)
			if inner and Farms.forty_of(n) == Farms.forty_of(c):
				continue
			var a: Vector2 = corners[s[1]]
			var b: Vector2 = corners[s[2]]
			var out := ((a + b) * 0.5 - Vector2(mid.x, mid.z)).normalized()
			var strip := PackedVector2Array([a - out * 3.0, b - out * 3.0, b, a]) if inner \
				else PackedVector2Array([a - out * 2.5, b - out * 2.5, b + out * 1.0, a + out * 1.0])
			var strips := [strip]
			if trimmed.has(c):
				strips = []
				for piece in kept:
					strips.append_array(Geometry2D.intersect_polygons(strip, piece))
			for part in strips:
				_add_poly(st, f, part, 0.07, verge)
			var h := Farms._hash01(c * 4 + s[0], 7)
			if not inner and h < 0.45:
				var at := a.lerp(b, 0.15 + 0.7 * Farms._hash01(c * 4 + s[0], 11)) - out * 1.2
				if trimmed.has(c) and not kept.any(func(piece): return Geometry2D.is_point_in_polygon(at, piece)):
					continue
				var sp: int = [TreeField.Species.OAK, TreeField.Species.MAPLE, TreeField.Species.LOCUST, TreeField.Species.CRABAPPLE][int(h * 8.9) % 4]
				planted.append([Transform3D(Basis(Vector3.UP, h * 40.0).scaled(Vector3.ONE * (0.7 + h)), Vector3(at.x, Terrain.ground_y(at.x, at.y), at.y)),
					sp, TreeField.LEAF[sp]])
	return planted
