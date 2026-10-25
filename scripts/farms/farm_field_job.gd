class_name FarmFieldJob
extends RefCounted
## Draws one farm's fields (and its gravel lane) a few milliseconds at a time,
## so a farm that changes never freezes a frame (FarmView runs the job a
## little each frame and swaps the new mesh in when it is whole; the old one
## stays on screen until then).
##
## The job first takes a snapshot of the farm and works out each field's
## slot in the crop table, which is also the farm's "signature": if it is
## the same as the one last drawn, nothing is rebuilt. Otherwise it builds
## the geometry a field cell at a time, drapes each piece on the ground
## (Terrain.drape, the same split and lift as the old all-at-once redraw, so
## the fields look the same), then the fencerows, then the lane.
## Fields: 40-acre forties square to the farmhouse, crop rows running back
## from the road, turn rows across the ends of each field and a grass border
## between fields, as they look from the air in Pike County.

enum Phase { SCAN, CELLS, FENCE, LANE, DONE }
## The name each phase's time is filed under (Perf), made once.
const PERF_NAMES := ["farm_job.scan", "farm_job.cells", "farm_job.fence", "farm_job.lane"]

## How wide the turn rows (headlands) are at each end of a field: two passes
## of a 12-row, 30-inch planter, about 18 m.
const HEADLAND := 18.0
## Longest side of a field triangle before it is split to follow the ground.
const MAX_EDGE := 10.0
const LANE_EDGE := 8.0

var id: Variant
var phase := Phase.SCAN
## The farm as it was when the job began (the sim goes on while it works).
var frame := {}  # {pos, dir}: all the field geometry needs of the farm
var cells: Array = []
var drive: Array = []
var trimmed: Dictionary = {}
var owned := {}
var slots: Array = []
var pasture := PackedByteArray()
var practice := 0
## What decides how the fields look; compared with the last drawn farm's.
var signature: Array = []
var borrows := false
## False when the signature matched the last drawn one: nothing to rebuild.
var changed := true
## The finished mesh, set when the job is DONE and changed: the fields are
## its surface `fields_surface` and the gravel lane its surface
## `lane_surface` (-1 when there is none). One mesh, so a farm costs the
## renderer one object, not two.
var mesh: ArrayMesh
var fields_surface := -1
var lane_surface := -1
var trees: Array = []  # volunteer trees in the fencerows
## Which table rows the farm's fields use, and the box of its cells in view
## coordinates (what CropPlants wants to know of a finished farm).
var rows := {}
var cell_box := Rect2()
## The view the ground was draped in; a job whose view moved starts over.
var view := Vector4.ZERO
var last_signature: Array = []

var _sim: CitySim
var _farm: Dictionary  # the live farm, read only while scanning
var _i := 0
## The table row for each kind of field seen so far (see FarmView.slot_from).
var _row_memo := {}
# The piece being built, and everything draped so far.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _u := PackedVector2Array()
var _av := PackedVector3Array()
var _an := PackedVector3Array()
var _ac := PackedColorArray()
var _au := PackedVector2Array()


func _init(sim: CitySim, farm_id: Variant, previous: Array) -> void:
	_sim = sim
	id = farm_id
	last_signature = previous
	view = _view_now()
	var f: Dictionary = sim.farms.farms[farm_id]
	frame = {"pos": f.pos, "dir": f.dir}
	cells = f.cells.duplicate()
	drive = f.drive.duplicate()
	trimmed = sim.farms.trim.get(farm_id, {}).duplicate(true)
	for c in cells:
		owned[c] = true
	practice = CropCalendar.farm_practice(int(farm_id), f)
	cell_box = Rect2(Vector2(f.pos.x, f.pos.z), Vector2.ZERO)
	_farm = f


## `box` grown to hold cell `c` of the farm drawn in `frame`.
static func expand_box(box: Rect2, frame: Dictionary, c: Vector2i) -> Rect2:
	for p in Farms.cell_corners(frame, c):
		box = box.expand(p)
	return box


## Everything a farm draws, in view coordinates: its cells and its lane.
static func box_of(f: Dictionary) -> Rect2:
	var box := Rect2(Vector2(f.pos.x, f.pos.z), Vector2.ZERO)
	for c in f.cells:
		box = expand_box(box, f, c)
	for p in f.drive:
		box = box.expand(Vector2(p.x, p.z))
	return box.grow(Farms.DRIVE_WIDTH)


static func _view_now() -> Vector4:
	return Vector4(Terrain.view_origin.x, Terrain.view_origin.y, Terrain.shift.x, Terrain.shift.y)


## True when the ground has moved since the job began (its drape is stale).
func view_moved() -> bool:
	return _view_now() != view


## Works until `deadline` (Time.get_ticks_usec) or done; true when DONE.
## Always does at least one piece of work, so it always gets somewhere.
func step(deadline: int) -> bool:
	while phase != Phase.DONE:
		var t0 := Perf.now()
		var was := phase
		match phase:
			Phase.SCAN:
				_scan_one()
			Phase.CELLS:
				_cell_one()
			Phase.FENCE:
				_fence_one()
			Phase.LANE:
				_lane()
		Perf.add(PERF_NAMES[was], t0)
		if Time.get_ticks_usec() >= deadline:
			break
	return phase == Phase.DONE


# --- the scan: each field's slot in the crop table ---------------------

func _scan_one() -> void:
	if _i < cells.size():
		var c: Vector2i = cells[_i]
		var fl := CropPlan.field(_farm, c)
		var slot := FarmView.slot_from(id, practice, fl, c, _row_memo)
		slots.append(slot)
		pasture.append(1 if fl.crop == "pasture" else 0)
		borrows = borrows or slot.x < CropCalendar.COUNTY_ROWS
		rows[slot.x] = true
		cell_box = expand_box(cell_box, frame, c)
		_i += 1
		return
	signature = [frame.pos, frame.dir, cells, slots, pasture, drive, trimmed]
	_farm = {}  # the snapshot is all the rest of the job reads
	_i = 0
	if signature == last_signature:
		changed = false
		phase = Phase.DONE
	else:
		phase = Phase.CELLS


# --- the fields, a cell at a time ---------------------------------------

func _cell_one() -> void:
	if _i >= cells.size():
		_i = 0
		phase = Phase.FENCE
		return
	var c: Vector2i = cells[_i]
	var slot: Vector2i = slots[_i]
	var col := CropFields.color(slot.x, slot.y)
	if trimmed.has(c):
		# A field a road ran through stops at the road's edge.
		for poly in trimmed[c]:
			_add_poly(poly, 0.06, col, false, pasture[_i] == 0)
	elif pasture[_i] == 1:
		_add_poly(Farms.cell_corners(frame, c), 0.06, col, false, false)  # grass, no rows
	else:
		_add_cell(c, col)
	_flush(MAX_EDGE)
	_i += 1


## One field cell. At the front or back end of its forty the planter turned
## round, so a band of rows there runs across the field.
func _add_cell(c: Vector2i, col: Color) -> void:
	var corners := Farms.cell_corners(frame, c)
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
	_add_poly(mid, 0.06, col)
	var turn := Color(col.r, col.g, 0.96, col.a)  # the headlands a shade darker
	if front:
		_add_poly(PackedVector2Array([corners[0], corners[1], mid[1], mid[0]]), 0.06, turn, true)
	if back:
		_add_poly(PackedVector2Array([mid[3], mid[2], corners[2], corners[3]]), 0.06, turn, true)


func _add_poly(poly: PackedVector2Array, y: float, col: Color, across := false, rows := true) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	var right := Vector2(-frame.dir.z, frame.dir.x)
	var back := Vector2(-frame.dir.x, -frame.dir.z)
	var origin := Vector2(frame.pos.x, frame.pos.z)
	for k in range(0, tris.size(), 3):
		var a := poly[tris[k]]
		var b := poly[tris[k + 1]]
		var c := poly[tris[k + 2]]
		var order := [a, b, c] if (b - a).cross(c - a) > 0.0 else [a, c, b]
		for p in order:
			_c.append(col)
			_n.append(Vector3.UP)
			# Rows run back from the road: about one stripe per 2 m. Turn rows
			# at a field's ends run across it.
			var d: Vector2 = p - origin
			if not rows:
				_u.append(Vector2(0.38 / 16.0, 0.0))  # mid-row everywhere: one shade, no crop rows
			else:
				_u.append((Vector2(d.dot(back), d.dot(right)) if across else Vector2(d.dot(right), d.dot(back))) / 16.0)
			_v.append(Vector3(p.x, y, p.y))


## Drapes what has been built since the last flush on the ground (splitting
## long triangles so it follows the slope, then lifting each corner onto the
## land, as Terrain.drape does for a whole mesh) and adds it to the whole.
## Done on the arrays, not on a mesh: reading a mesh back from the graphics
## card for every field cell was the slow part.
func _flush(max_edge: float) -> void:
	if _v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _u
	var out := _lifted(Terrain._split(arrays, max_edge))
	_av.append_array(out[Mesh.ARRAY_VERTEX])
	_an.append_array(out[Mesh.ARRAY_NORMAL])
	_ac.append_array(out[Mesh.ARRAY_COLOR])
	_au.append_array(out[Mesh.ARRAY_TEX_UV])
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_u = PackedVector2Array()


## The arrays with every vertex lifted by the height of the ground under it.
static func _lifted(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3(v.x, v.y + Terrain.ground_y(v.x, v.z), v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays


# --- fencerows -------------------------------------------------------------

## Neighbour offsets and the cell_corners() edge each one shares.
const SIDES := [[Vector2i(-1, 0), 0, 3], [Vector2i(1, 0), 1, 2], [Vector2i(0, -1), 0, 1], [Vector2i(0, 1), 3, 2]]


## A grassy, brushy fencerow along each outside edge of a farm's land, with
## the odd volunteer tree in it, as on real section-line field edges, and a
## narrower grass border (a field edge or grassed waterway, NRCS practice
## 386 and 412) between the farm's own forties. One cell's edges a step.
func _fence_one() -> void:
	if _i >= cells.size():
		phase = Phase.LANE
		_i = 0
		return
	var c: Vector2i = cells[_i]
	_i += 1
	var verge := CropFields.color(0, 0, true)
	var corners := Farms.cell_corners(frame, c)
	var mid := Farms.cell_center(frame, c)
	# Where a road cut the field back, its fencerows stop at the road too.
	var kept := []
	for piece in trimmed.get(c, []):
		kept.append_array(Geometry2D.offset_polygon(piece, 1.5))
	for s in SIDES:
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
			_add_poly(part, 0.07, verge)
		# Volunteer trees grow only in the fencerows round the farm's
		# land, never out in the grass strip between two of its fields,
		# which the farmer mows and works across.
		var h := Farms._hash01(c * 4 + s[0], 7)
		if not inner and h < 0.45:
			var at := a.lerp(b, 0.15 + 0.7 * Farms._hash01(c * 4 + s[0], 11)) - out * 1.2
			if trimmed.has(c) and not kept.any(func(piece): return Geometry2D.is_point_in_polygon(at, piece)):
				continue
			var sp: int = [TreeField.Species.OAK, TreeField.Species.MAPLE, TreeField.Species.LOCUST, TreeField.Species.CRABAPPLE][int(h * 8.9) % 4]
			trees.append([Transform3D(Basis(Vector3.UP, h * 40.0).scaled(Vector3.ONE * (0.7 + h)), Vector3(at.x, Terrain.ground_y(at.x, at.y), at.y)),
				sp, TreeField.LEAF[sp]])
	_flush(MAX_EDGE)


# --- the lane and the finished meshes -------------------------------------

func _lane() -> void:
	mesh = ArrayMesh.new()
	# The fields' mesh, whole.
	if not _av.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _av
		arrays[Mesh.ARRAY_NORMAL] = _an
		arrays[Mesh.ARRAY_COLOR] = _ac
		arrays[Mesh.ARRAY_TEX_UV] = _au
		fields_surface = mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if drive.size() >= 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := PackedVector3Array()
		for p in drive:
			pts.append(p)
		RoadMesh.add_strip(st, Terrain.densify(pts, 6.0), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.05)
		var strip := _lifted(Terrain._split(st.commit_to_arrays(), LANE_EDGE))
		lane_surface = mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, strip)
	_av = PackedVector3Array()
	_an = PackedVector3Array()
	_ac = PackedColorArray()
	_au = PackedVector2Array()
	phase = Phase.DONE
