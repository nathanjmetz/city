class_name FarmView
extends Node3D
## Draws farms: the fields each farm owns (crop rows that grow, ripen and
## are cut on the crop calendar, CropCalendar), farmsteads and their gravel
## lanes, and the corn and soybean plants close to the camera (CropPlants).
## It also keeps the crop table on today's date for every field drawer.
## (The Fertility view shows the soil; see InfoView.)

var sim: CitySim
var _fields := MeshInstance3D.new()
var _lanes := MeshInstance3D.new()
var _homes := {}  # farm id -> Node3D
var _barns := {}  # "id:x:y:kind" -> Node3D, one per livestock barn group
var _cows := MultiMeshInstance3D.new()  # beef herds on pasture
var _trees := TreeField.new()
var _mats := {}
var _year := -1
## Whether a field borrows a county row (CropCalendar.farm_row ran out):
## those rows' crops follow the year, so the fields are redrawn when it turns.
var _borrowing := false
var _plants: CropPlants
var _signs := {}  # "farm:<id>" -> the farm's sign by the road


func setup(s: CitySim) -> void:
	sim = s
	sim.farms_changed.connect(_rebuild)
	sim.families.changed.connect(_sync_signs)
	_fields.material_override = CropFields.material()
	_lanes.material_override = RoadStyle.material(Color(0.58, 0.47, 0.33))  # tan crushed limestone and dirt
	for mi in [_fields, _lanes]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	add_child(_trees)
	_cows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cows)
	_plants = CropPlants.new()
	_plants.setup(sim)
	add_child(_plants)
	_sync_date()
	CropCalendar.refresh(true)
	_rebuild()


func _process(_delta: float) -> void:
	var t0 := Perf.now()
	_sync_date()
	CropCalendar.refresh(false, 1.0)
	Perf.add("frame.crop_table", t0)
	# The crops in the fields change each January when the farms plan, and
	# that redraws them (farms_changed); the table itself follows the date.
	# Only a field on a borrowed county row needs redrawing as the year turns.
	var year := Seasons.year(sim.tick_count)
	if year != _year:
		_year = year
		if _borrowing:
			_draw_fields()
	Perf.add("frame.crops", t0)


## The crop table shows today (mid July while seasons are off).
func _sync_date() -> void:
	if DayNight.seasons_on:
		CropCalendar.set_date(Seasons.months(sim.tick_count), Seasons.year(sim.tick_count))
	else:
		CropCalendar.set_date(6.5, Seasons.year(sim.tick_count))


func _rebuild() -> void:
	_draw_fields()
	for id in _homes.keys():
		if not sim.farms.farms.has(id) or _homes[id].get_meta("look") != _look(sim.farms.farms[id]) \
				or _homes[id].get_meta("built") != sim.farms.farms[id].get("built", []).size():
			_homes[id].queue_free()
			_homes.erase(id)
			_trees.remove(str(id))
			_trees.remove("rows %s" % str(id))
	for id in sim.farms.farms:
		if not _homes.has(id):
			_homes[id] = _farmstead(id, sim.farms.farms[id])
	_sync_barns()
	_draw_cows()
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


## A field's slot in the crop table (CropCalendar): its row from its facts
## (this year's crop, last year's, the farm's tillage habit, rye before and
## after) and its timing column: farmers work one field at a time, so in
## spring and fall neighbouring forties differ.
static func slot_of(id: Variant, f: Dictionary, c: Vector2i) -> Vector2i:
	var fl := CropPlan.field(f, c)
	var practice := CropCalendar.farm_practice(int(id), f)
	if fl.cover or fl.cover_prev:
		practice = CropCalendar.RYE
	var row := CropCalendar.farm_row(str(fl.crop), str(fl.prev), practice, bool(fl.cover), bool(fl.cover_prev))
	var col := int(Farms._hash01(Farms.forty_of(c) + Vector2i(int(id) * 7, 3), 23) * CropCalendar.COLS)
	return Vector2i(row, clampi(col, 0, CropCalendar.COLS - 1))


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
	# A row per kind of field stays put while the farms change, so most
	# redraws find their rows ready; when they run short, start over.
	if CropCalendar.farm_rows_used() > (CropCalendar.ROWS - CropCalendar.COUNTY_ROWS) * 3 / 4:
		CropCalendar.clear_farm_rows()
	_year = Seasons.year(sim.tick_count)
	_borrowing = false
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var trimmed: Dictionary = sim.farms.trim.get(id, {})
		var owned := {}
		for c in f.cells:
			owned[c] = true
		for c in f.cells:
			var fl := CropPlan.field(f, c)
			var slot := slot_of(id, f, c)
			_borrowing = _borrowing or slot.x < CropCalendar.COUNTY_ROWS
			var col := CropFields.color(slot.x, slot.y)
			if trimmed.has(c):
				# A field a road ran through stops at the road's edge.
				for poly in trimmed[c]:
					_add_poly(st, f, poly, 0.06, col, false, fl.crop != "pasture")
			elif fl.crop == "pasture":
				_add_poly(st, f, Farms.cell_corners(f, c), 0.06, col, false, false)  # grass, no rows
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
	if _plants != null:
		_plants.fields_changed()
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
	var turn := Color(col.r, col.g, 0.96, col.a)  # the headlands a shade darker
	if front:
		_add_poly(st, f, PackedVector2Array([corners[0], corners[1], mid[1], mid[0]]), 0.06, turn, true)
	if back:
		_add_poly(st, f, PackedVector2Array([mid[3], mid[2], corners[2], corners[3]]), 0.06, turn, true)


func _add_poly(st: SurfaceTool, f: Dictionary, poly: PackedVector2Array, y: float, col: Color, across := false,
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
			# Rows run back from the road: about one stripe per 2 m. Turn rows
			# at a field's ends run across it.
			var d: Vector2 = p - origin
			if not rows:
				st.set_uv(Vector2(0.38 / 16.0, 0.0))  # mid-row everywhere: one shade, no crop rows
				st.add_vertex(Vector3(p.x, y, p.y))
				continue
			st.set_uv((Vector2(d.dot(back), d.dot(right)) if across else Vector2(d.dot(right), d.dot(back))) / 16.0)
			st.add_vertex(Vector3(p.x, y, p.y))


## A grassy, brushy fencerow along each outside edge of a farm's land, with
## the odd volunteer tree in it, as on real section-line field edges, and a
## narrower grass border (a field edge or grassed waterway, NRCS practice
## 386 and 412) between the farm's own forties.
func _fencerows(st: SurfaceTool, id: Variant, f: Dictionary) -> void:
	var verge := CropFields.color(0, 0, true)
	var planted := []
	# Neighbour offsets and the cell_corners() edge each one shares.
	var sides := [[Vector2i(-1, 0), 0, 3], [Vector2i(1, 0), 1, 2], [Vector2i(0, -1), 0, 1], [Vector2i(0, 1), 3, 2]]
	var owned := {}
	for c in f.cells:
		owned[c] = true
	var trimmed: Dictionary = sim.farms.trim.get(id, {})
	for c in f.cells:
		var corners := Farms.cell_corners(f, c)
		var mid := Farms.cell_center(f, c)
		# Where a road cut the field back, its fencerows stop at the road too.
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
			# Between two of its own fields each side gives up 3 m of grass.
			var strip := PackedVector2Array([a - out * 3.0, b - out * 3.0, b, a]) if inner \
				else PackedVector2Array([a - out * 2.5, b - out * 2.5, b + out * 1.0, a + out * 1.0])
			var strips := [strip]
			if trimmed.has(c):
				strips = []
				for piece in kept:
					strips.append_array(Geometry2D.intersect_polygons(strip, piece))
			for part in strips:
				_add_poly(st, f, part, 0.07, verge)
			# Volunteer trees grow only in the fencerows round the farm's
			# land, never out in the grass strip between two of its fields,
			# which the farmer mows and works across.
			var h := Farms._hash01(c * 4 + s[0], 7)
			if not inner and h < 0.45:
				var at := a.lerp(b, 0.15 + 0.7 * Farms._hash01(c * 4 + s[0], 11)) - out * 1.2
				if trimmed.has(c) and not kept.any(func(piece): return Geometry2D.is_point_in_polygon(at, piece)):
					continue
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
	root.set_meta("built", f.get("built", []).size())
	add_child(root)
	root.position = Vector3(f.pos.x, Terrain.ground_y(f.pos.x, f.pos.z), f.pos.z)
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	var built := FarmBuilder.build_farmstead(hash(str(id)), look, f.get("built", []))
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


## Livestock barns on their pads beside the farmyards (Livestock, FarmBuilder).
func _sync_barns() -> void:
	var want := {}
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var kind := Livestock.kind(f)
		for site in Livestock.sites(f):
			want["%d:%d:%d:%s" % [id, site.x, site.y, kind]] = [f, site, kind]
	for key in _barns.keys():
		if not want.has(key):
			_barns[key].queue_free()
			_barns.erase(key)
	for key in want:
		if _barns.has(key):
			continue
		var f: Dictionary = want[key][0]
		var mid := Livestock.site_center(f, want[key][1])
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(mid.x, Terrain.ground_y(mid.x, mid.z), mid.z)
		root.basis = Basis.looking_at(f.dir, Vector3.UP)
		var built := FarmBuilder.build_barns(want[key][2], hash(key))
		var footing := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(78, 3.0, 38)
		footing.mesh = cube
		footing.position = Vector3(0, -1.55, 0)
		footing.material_override = _footing_mat()
		footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(footing)
		var barns := MeshInstance3D.new()
		barns.mesh = built[0]
		root.add_child(barns)
		var ground := MeshInstance3D.new()
		ground.mesh = Terrain.drape_local(built[1], root.transform)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ground)
		_barns[key] = root


## Most cows drawn at once, across every herd.
const MAX_COWS := 3000
## Angus black, Hereford red and the odd black baldy: the beef breeds on
## southern Indiana pasture.
const COW_COLORS := [Color("#1c1a19"), Color("#1c1a19"), Color("#6e3420"), Color("#2a2522")]


## Every beef herd grazing its pasture, one cow per 2 acres (Livestock).
func _draw_cows() -> void:
	var spots := []
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		if Livestock.kind(f) != "cattle":
			continue
		var grass := []
		for c in f.cells:
			if CropPlan.crop_at(f, c) == "pasture":
				grass.append(c)
		var n := mini(Livestock.head(f), MAX_COWS - spots.size())
		for i in n:
			var c: Vector2i = grass[int(Farms._hash01(Vector2i(int(id), i), 31) * grass.size()) % grass.size()]
			var corners := Farms.cell_corners(f, c)
			var u := Farms._hash01(c + Vector2i(i, 0), 37)
			var v := Farms._hash01(c + Vector2i(0, i), 41)
			var p := corners[0].lerp(corners[1], 0.1 + 0.8 * u).lerp(corners[3].lerp(corners[2], 0.1 + 0.8 * u), 0.1 + 0.8 * v)
			spots.append([Vector3(p.x, Terrain.ground_y(p.x, p.y), p.y), Farms._hash01(c + Vector2i(i, i), 43)])
	if spots.is_empty():
		_cows.visible = false
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _cow_mesh()
	mm.instance_count = spots.size()
	for i in spots.size():
		var h: float = spots[i][1]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, h * TAU), spots[i][0]))
		mm.set_instance_color(i, COW_COLORS[int(h * 97.0) % COW_COLORS.size()])
	_cows.multimesh = mm
	_cows.visible = true


static var _cow: Mesh


## A beef cow, about 2.4 m nose to tail and 1.3 m at the shoulder.
static func _cow_mesh() -> Mesh:
	if _cow != null:
		return _cow
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [[Vector3(0.75, 0.75, 1.7), Vector3(0, 0.95, 0)],    # body
		[Vector3(0.42, 0.45, 0.55), Vector3(0, 1.05, -1.05)],           # head
		[Vector3(0.6, 0.35, 0.6), Vector3(0, 1.25, -0.55)]]             # shoulders
	for x in [-0.25, 0.25]:
		for z in [-0.6, 0.6]:
			parts.append([Vector3(0.14, 0.62, 0.14), Vector3(x, 0.31, z)])  # legs
	for part in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		st.append_from(box, 0, Transform3D(Basis.IDENTITY, part[1]))
	_cow = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_cow.surface_set_material(0, mat)
	return _cow
