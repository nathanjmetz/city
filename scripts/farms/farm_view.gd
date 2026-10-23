class_name FarmView
extends Node3D
## Draws farms: the fields each farm owns (crop rows that change with the
## seasons), farmsteads and their gravel lanes. (The Fertility view shows
## the soil; see InfoView.)

var sim: CitySim
var _fields := MeshInstance3D.new()
var _lanes := MeshInstance3D.new()
var _homes := {}  # farm id -> Node3D
var _trees := TreeField.new()
var _mats := {}
var _month := -1
var _signs := {}  # "farm:<id>" -> the farm's sign by the road


func setup(s: CitySim) -> void:
	sim = s
	sim.farms_changed.connect(_rebuild)
	sim.families.changed.connect(_sync_signs)
	_fields.material_override = Surfaces.field()
	_lanes.material_override = RoadStyle.material(Color(0.58, 0.47, 0.33))  # tan crushed limestone and dirt
	for mi in [_fields, _lanes]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	add_child(_trees)
	_rebuild()


func _process(_delta: float) -> void:
	var month: int = DayNight.visible_month(sim)
	if month != _month:
		_month = month
		_draw_fields()


func _rebuild() -> void:
	_draw_fields()
	for id in _homes.keys():
		if not sim.farms.farms.has(id) or _homes[id].get_meta("look") != _look(sim.farms.farms[id]):
			_homes[id].queue_free()
			_homes.erase(id)
			_trees.remove(str(id))
			_trees.remove("rows %s" % str(id))
	for id in sim.farms.farms:
		if not _homes.has(id):
			_homes[id] = _farmstead(id, sim.farms.farms[id])
	_sync_signs()


## A farm sign at the end of each lane with the farm's name, the way Indiana
## farms mark theirs.
func _sync_signs() -> void:
	var lanes := {}
	for id in sim.farms.farms:
		lanes["farm:%d" % id] = sim.farms.farms[id].drive
	SignText.sync_lanes(self, _signs, sim, lanes, false)


## What the farmstead has built so far: house, then barn, then grain bins
## and a silo as the farm grows.
static func _look(f: Dictionary) -> int:
	if not f.barn:
		return 0
	return 1 + (1 if f.cells.size() >= 30 else 0) + (1 if f.cells.size() >= 100 else 0)


## What a field looks like this month in southern Indiana, by its crop
## (CropPlan): from the air corn is a dark blue-green and soybeans a
## brighter yellow-green; winter wheat greens up in March, turns gold and
## is cut in June, then double-crop soybeans follow; hay stays green all
## season. A rye cover crop greens the stubble in November (`cover`) and
## again in March and April before planting (`cover_prev`). `when` (0 to 1)
## is how early this field's planting and harvest run: farmers work one
## field at a time, so in spring and fall neighbouring forties differ
## (Purdue crop progress reports: planting runs late April to early June,
## harvest mid-September to early November).
func _season_color(crop: String, cover_prev := false, cover := false, when := 0.5) -> Color:
	var m := maxi(_month, 1)
	if m <= 2 or m == 12:
		return Color(0.84, 0.85, 0.88)  # snow over the stubble
	match crop:
		"wheat":
			return [Color(0.34, 0.47, 0.2), Color(0.3, 0.5, 0.18), Color(0.4, 0.5, 0.22), Color(0.78, 0.66, 0.32),
				Color(0.44, 0.43, 0.25), Color(0.3, 0.44, 0.2), Color(0.32, 0.45, 0.19), Color(0.68, 0.6, 0.25),
				Color(0.66, 0.56, 0.36)][m - 3]
		"hay":
			return [Color(0.5, 0.5, 0.3), Color(0.36, 0.5, 0.22), Color(0.45, 0.52, 0.25), Color(0.36, 0.5, 0.22),
				Color(0.42, 0.5, 0.24), Color(0.38, 0.5, 0.23), Color(0.45, 0.48, 0.25), Color(0.5, 0.5, 0.3),
				Color(0.52, 0.5, 0.32)][m - 3]
	if m == 3:
		return Color(0.4, 0.48, 0.24) if cover_prev else Color(0.6, 0.52, 0.38)  # rye, or winter stubble
	if m == 4:
		if cover_prev:
			return Color(0.38, 0.47, 0.24)  # rye
		# Tilled black soil, or last fall's stubble not yet worked.
		return Color(0.36, 0.27, 0.19) if when < 0.6 else Color(0.55, 0.48, 0.34)
	if m == 5:
		return Color(0.42, 0.42, 0.24) if when < 0.55 else Color(0.38, 0.29, 0.2)  # rows just up, or just planted
	if m <= 8:
		var green := Color(0.18, 0.34, 0.12) if crop == "corn" else Color(0.32, 0.46, 0.16)
		return green.lerp(Color(0.24, 0.36, 0.14), (when - 0.5) * 0.4)  # varieties, planting dates
	var ripe := Color(0.62, 0.58, 0.3) if crop == "corn" else Color(0.7, 0.62, 0.22)
	var cut := Color(0.66, 0.56, 0.36)  # harvested stubble
	if m == 9:
		return cut if when < 0.15 else ripe
	if m == 10:
		return cut if when < 0.75 else ripe
	if m == 11 and cover:
		return Color(0.42, 0.48, 0.26)  # rye coming up in the stubble
	return cut


## Each farm's fields: 40-acre forties square to its farmhouse, crop rows
## running back from the road, turn rows across the ends of each field and
## a grass border between fields, the way they look from the air in Pike
## County.
func _draw_fields() -> void:
	if sim == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lanes := SurfaceTool.new()
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var any_lane := false
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var trimmed: Dictionary = sim.farms.trim.get(id, {})
		var owned := {}
		for c in f.cells:
			owned[c] = true
		for c in f.cells:
			var fl := CropPlan.field(f, c)
			var col := _season_color(fl.crop, fl.cover_prev, fl.cover,
				Farms._hash01(Farms.forty_of(c) + Vector2i(int(id) * 7, 3), 23))
			if trimmed.has(c):
				# A field a road ran through stops at the road's edge.
				for poly in trimmed[c]:
					_add_poly(st, f, poly, 0.06, col)
			else:
				_add_cell(st, f, c, owned, col)
			any = true
		_fencerows(st, id, f)
		if f.drive.size() >= 2:
			var pts := PackedVector3Array()
			for p in f.drive:
				pts.append(p)
			RoadMesh.add_strip(lanes, Terrain.densify(pts, 6.0), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.05)
			any_lane = true
	_fields.visible = any
	if any:
		_fields.mesh = Terrain.drape(st.commit(), true, 10.0)
	_lanes.visible = any_lane
	if any_lane:
		_lanes.mesh = Terrain.drape(lanes.commit(), true, 8.0)


## How wide the turn rows (headlands) are at each end of a field: two passes
## of a 12-row, 30-inch planter, about 18 m.
const HEADLAND := 18.0


## One field cell. At the front or back end of its forty the planter turned
## round, so a band of rows there runs across the field.
func _add_cell(st: SurfaceTool, f: Dictionary, c: Vector2i, owned: Dictionary, col: Color) -> void:
	var corners := Farms.cell_corners(f, c)
	var forty := Farms.forty_of(c)
	# corners: 0 front-left, 1 front-right, 2 back-right, 3 back-left
	# (front is toward the road, -y in the farm's frame).
	var front := not owned.has(c - Vector2i(0, 1)) or Farms.forty_of(c - Vector2i(0, 1)) != forty
	var back := not owned.has(c + Vector2i(0, 1)) or Farms.forty_of(c + Vector2i(0, 1)) != forty
	var h := HEADLAND / Farms.CELL
	var t0 := h if front else 0.0
	var t1 := 1.0 - h if back else 1.0
	var mid := PackedVector2Array([corners[0].lerp(corners[3], t0), corners[1].lerp(corners[2], t0),
		corners[1].lerp(corners[2], t1), corners[0].lerp(corners[3], t1)])
	_add_poly(st, f, mid, 0.06, col)
	if front:
		_add_poly(st, f, PackedVector2Array([corners[0], corners[1], mid[1], mid[0]]), 0.06, col.darkened(0.04), true)
	if back:
		_add_poly(st, f, PackedVector2Array([mid[3], mid[2], corners[2], corners[3]]), 0.06, col.darkened(0.04), true)


func _add_poly(st: SurfaceTool, f: Dictionary, poly: PackedVector2Array, y: float, col: Color, across := false) -> void:
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
			# Rows run back from the road: about one stripe per 2 m. Turn rows
			# at a field's ends run across it.
			var d: Vector2 = p - origin
			st.set_uv((Vector2(d.dot(back), d.dot(right)) if across else Vector2(d.dot(right), d.dot(back))) / 16.0)
			st.add_vertex(Vector3(p.x, y, p.y))


## A grassy, brushy fencerow along each outside edge of a farm's land, with
## the odd volunteer tree in it, as on real section-line field edges, and a
## narrower grass border (a field edge or grassed waterway, NRCS practice
## 386 and 412) between the farm's own forties.
func _fencerows(st: SurfaceTool, id: Variant, f: Dictionary) -> void:
	var verge := Color(0.5, 0.5, 0.3, 0.0)
	var planted := []
	# Neighbour offsets and the cell_corners() edge each one shares.
	var sides := [[Vector2i(-1, 0), 0, 3], [Vector2i(1, 0), 1, 2], [Vector2i(0, -1), 0, 1], [Vector2i(0, 1), 3, 2]]
	var owned := {}
	for c in f.cells:
		owned[c] = true
	for c in f.cells:
		var corners := Farms.cell_corners(f, c)
		var mid := Farms.cell_center(f, c)
		for s in sides:
			var n: Vector2i = c + s[0]
			var inner := owned.has(n)
			if inner and Farms.forty_of(n) == Farms.forty_of(c):
				continue
			var a: Vector2 = corners[s[1]]
			var b: Vector2 = corners[s[2]]
			var out := ((a + b) * 0.5 - Vector2(mid.x, mid.z)).normalized()
			# Between two of its own fields each side gives up 3 m of grass.
			var strip := PackedVector2Array([a - out * 3.0, b - out * 3.0, b, a]) if inner \
				else PackedVector2Array([a - out * 2.5, b - out * 2.5, b + out * 1.0, a + out * 1.0])
			_add_poly(st, f, strip, 0.07, verge)
			var h := Farms._hash01(c * 4 + s[0], 7)
			if h < (0.06 if inner else 0.45):
				var at := a.lerp(b, 0.15 + 0.7 * Farms._hash01(c * 4 + s[0], 11)) - out * 1.2
				var sp: int = [TreeField.Species.OAK, TreeField.Species.MAPLE, TreeField.Species.LOCUST, TreeField.Species.CRABAPPLE][int(h * 8.9) % 4]
				planted.append([Transform3D(Basis(Vector3.UP, h * 40.0).scaled(Vector3.ONE * (0.7 + h)), Vector3(at.x, Terrain.ground_y(at.x, at.y), at.y)),
					sp, TreeField.LEAF[sp]])
	_trees.set_trees("rows %s" % str(id), planted)


## A Midwestern farmstead: white farmhouse first, then a red barn, grain
## bins and a concrete silo as the farm grows (see FarmBuilder). Its gravel
## lane is lined with a few shade trees.
func _farmstead(id: Variant, f: Dictionary) -> Node3D:
	var look := _look(f)
	var root := Node3D.new()
	root.set_meta("look", look)
	add_child(root)
	root.position = Vector3(f.pos.x, Terrain.ground_y(f.pos.x, f.pos.z), f.pos.z)
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	var built := FarmBuilder.build_farmstead(hash(str(id)), look)
	# A footing under the yard, for farmsteads on a slope.
	var footing := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(34, 3.0, 38)
	footing.mesh = cube
	footing.position = Vector3(0, -1.55, 0)
	footing.material_override = _footing_mat()
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(footing)
	# The yard's gravel and grass lie on the ground, following it.
	built[1] = Terrain.drape_local(built[1], root.transform)
	# The farmhouse goes up stage by stage (ConstructionSite).
	var ref := "farm:%s" % str(id)
	ConstructionSite.add_to(root, built, "house", func(): return sim.construction.state(ref, sim.tick_count),
		func(): pass)
	var xf := Transform3D(root.basis, root.position)
	var planted := []
	for t in built[2]:
		var at := xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		planted.append([at, t[1], t[2]])
	# Shade trees along the lane, alternating sides, the same every time.
	var drive: Array = f.drive
	var k := 0
	for i in range(2, drive.size() - 2, maxi(2, drive.size() / 4)):
		var a: Vector3 = drive[i]
		var b: Vector3 = drive[i + 1]
		var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * (5.5 if k % 2 == 0 else -5.5)
		var h := Farms._hash01(Vector2i(roundi(a.x), roundi(a.z)), 3)
		var sp: int = TreeField.Species.OAK if h < 0.5 else TreeField.Species.MAPLE
		var size := 0.9 + 0.35 * h
		var spot := a + side
		spot.y = Terrain.ground_y(spot.x, spot.z)
		planted.append([Transform3D(Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * size), spot), sp, TreeField.LEAF[sp]])
		k += 1
	_trees.set_trees(str(id), planted)
	return root


static var _footing: Material


static func _footing_mat() -> Material:
	if _footing == null:
		_footing = Surfaces.concrete(Color(0.5, 0.48, 0.44))
	return _footing
