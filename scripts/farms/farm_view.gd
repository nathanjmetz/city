class_name FarmView
extends Node3D
## Draws farms: the fields each farm owns (crop rows that grow, ripen and
## are cut on the crop calendar, CropCalendar), farmsteads and their gravel
## lanes, and the corn and soybean plants close to the camera (CropPlants).
## It also keeps the crop table on today's date for every field drawer.
## (The Fertility view shows the soil; see InfoView.)

var sim: CitySim
var _homes := {}  # farm id -> Node3D
var _barns := {}  # "id:x:y:kind" -> Node3D, one per livestock barn group
var _cows := MultiMeshInstance3D.new()  # beef herds on pasture
## Farmsteads and barns are built one at a time, a step or two a frame
## (FarmSteadJob): what is waiting ["home" or "barn", key] and the barn
## groups the farms want now (key -> [farm id, site, kind]).
var _steads := []
var _stead_job: FarmSteadJob
var _barn_want := {}
## The herds are placed a few hundred cows a time (FarmHerdJob).
var _herd_job: FarmHerdJob
var _herd_sig: Array = []
var _herd_dirty := false
var _trees := TreeField.new()
var _mats := {}
var _year := -1
## Each farm's drawn fields and lane (one mesh): id -> {node: MeshInstance3D,
## sig: what they were drawn from (FarmFieldJob), rows: the crop table rows
## they use, box: where they lie (view coordinates), borrows: whether a field
## borrows a county row (CropCalendar.farm_row ran out): those rows' crops
## follow the year, so those fields are redrawn when it turns}.
var _drawn := {}
## The fields are redrawn a few milliseconds a frame (see FarmFieldJob), a
## farm at a time, and only the farms that changed: the farms still to check
## in this pass, the one being drawn, and whether another pass is wanted.
var _queue := []
var _job: FarmFieldJob
var _dirty := false
## Farms to draw again even if nothing about them changed (the ground under
## them was regraded): id -> true.
var _redo := {}
## Where each farm lies, for regrading (id -> Rect2); forgotten when the
## farms change.
var _boxes := {}
## A pass ran since the table's unused farm rows were last freed.
var _rows_due := false
## Table rows something besides the drawn farms holds on to (tools, tests):
## row -> true. They are not given back.
var extra_rows := {}
var _lane_mat: Material
## Most milliseconds of field drawing in a frame.
const FIELD_BUDGET_MS := 3.0
## Frames to wait after a farms change before drawing, and what is left.
const SETTLE_FRAMES := 4
var _settle := 0
## What the last frame's farm drawing took (ms), for tools.
var work_ms := 0.0
## ... and its parts: farmsteads and barns, fields, herds (ms).
var work_parts := [0.0, 0.0, 0.0]
var _plants: CropPlants
var _signs := {}  # "farm:<id>" -> the farm's sign by the road


func setup(s: CitySim) -> void:
	sim = s
	sim.farms_changed.connect(_rebuild)
	sim.families.changed.connect(_sync_signs)
	# The same dirt track as a dirt road: two worn wheel paths with grass
	# between (Nathan, 2026-10-25: "make farms use them").
	_lane_mat = Surfaces.lane(Color(0.50, 0.41, 0.30))
	add_child(_trees)
	_cows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cows)
	_plants = CropPlants.new()
	_plants.setup(sim)
	add_child(_plants)
	_sync_date()
	CropCalendar.refresh(true)
	_rebuild()
	finish_now()  # a town that loads has its fields at once, under the loading screen


func _process(_delta: float) -> void:
	var t0 := Perf.now()
	_sync_date()
	CropCalendar.refresh(false, 1.0)
	Perf.add("frame.crop_table", t0)
	# The crops in the fields change each January when the farms plan, and
	# that redraws them (farms_changed); the table itself follows the date.
	# Only a field on a borrowed county row needs redrawing as the year turns.
	var year := Seasons.year(sim.calendar_tick())
	if year != _year:
		_year = year
		for id in _drawn:
			_dirty = _dirty or _drawn[id].borrows
		# A pass under way began in the old year: the farms it has done, or
		# is doing, took borrowed rows for that year.
		_dirty = _dirty or _job != null or not _queue.is_empty()
	Perf.add("frame.crops", t0)
	t0 = Perf.now()
	if _settle > 0:
		_settle -= 1
	else:
		_work(FIELD_BUDGET_MS)
	work_ms = (Perf.now() - t0) / 1000.0
	Perf.add("frame.farm_work", t0)


## The crop table shows today (mid July while seasons are off).
func _sync_date() -> void:
	if DayNight.seasons_on:
		CropCalendar.set_date(Seasons.months(sim.calendar_tick()), Seasons.year(sim.calendar_tick()))
	else:
		CropCalendar.set_date(6.5, Seasons.year(sim.calendar_tick()))


func _rebuild() -> void:
	# Whatever else the game does about a farm change comes first, so the
	# farm drawing never lands on the same frames (not while drawing is
	# already going on, or a change every frame would hold it up for good).
	if settled():
		_settle = SETTLE_FRAMES
	_dirty = true  # the fields: a pass over the farms starts a few frames on
	_herd_dirty = true
	_boxes.clear()
	_forget_gone()
	# A farm with no farmstead yet, or whose farmstead has grown, gets a new
	# one, which replaces the old when it is whole.
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		if not _homes.has(id) or _homes[id].get_meta("look") != _look(f) \
				or _homes[id].get_meta("built") != f.get("built", []).size():
			_want_stead("home", id)
	_sync_barns()
	_sync_signs()


## A farm that is gone takes everything with it at once: its farmstead, its
## fields and lane, its trees, and any redraw under way (whether or not it
## ever got a farmstead).
func _forget_gone() -> void:
	for id in _homes.keys():
		if not sim.farms.farms.has(id):
			_homes[id].queue_free()
			_homes.erase(id)
			_trees.remove(str(id))
	for id in _drawn.keys():
		if not sim.farms.farms.has(id):
			_drawn[id].node.queue_free()
			_drawn.erase(id)
			_trees.remove("rows %s" % str(id))
			_plants.farm_removed(id)
	for id in _redo.keys():
		if not sim.farms.farms.has(id):
			_redo.erase(id)
	if _job != null and not sim.farms.farms.has(_job.id):
		_job = null
	_queue = _queue.filter(func(id): return sim.farms.farms.has(id))


## The ground was regraded inside `box` (view coordinates; a road went in or
## out): the fields and lanes of the farms beside it were draped on the land
## as it was, so they are drawn again, even though nothing about the farms
## themselves changed. A redraw begun before the grading is begun again.
func regraded(box: Rect2) -> void:
	if sim == null:
		return
	var idle := settled()
	var any := false
	for id in sim.farms.farms:
		if not _box_of(id).grow(2.0).intersects(box):
			continue
		any = true
		_redo[id] = true
		if _job != null and _job.id == id:
			_queue.push_front(id)  # its ground is stale; it starts over
			_job = null
		elif not _queue.has(id):
			_queue.append(id)
	if any and idle:
		_settle = SETTLE_FRAMES


## Where a farm's fields and lane lie, in view coordinates.
func _box_of(id: Variant) -> Rect2:
	if not _boxes.has(id):
		_boxes[id] = FarmFieldJob.box_of(sim.farms.farms[id])
	return _boxes[id]


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
	return slot_from(id, CropCalendar.farm_practice(int(id), f), CropPlan.field(f, c), c)


## slot_of with the farm's tillage habit and the field's plan already worked out.
## `memo` (a dictionary the caller keeps for one farm's pass over its fields)
## remembers the row for each set of facts, so the table is asked, and its
## key text made, once per kind of field and not once per cell.
static func slot_from(id: Variant, farm_practice: int, fl: Dictionary, c: Vector2i, memo = null) -> Vector2i:
	var practice := farm_practice
	if fl.cover or fl.cover_prev:
		practice = CropCalendar.RYE
	var row := -1
	var by_prev: Dictionary
	var bits := practice | (int(bool(fl.cover)) << 4) | (int(bool(fl.cover_prev)) << 5)
	if memo != null:
		by_prev = (memo as Dictionary).get_or_add(fl.crop, {}).get_or_add(fl.prev, {})
		row = by_prev.get(bits, -1)
	if row < 0:
		row = CropCalendar.farm_row(str(fl.crop), str(fl.prev), practice, bool(fl.cover), bool(fl.cover_prev))
		if memo != null:
			by_prev[bits] = row
	var col := int(Farms._hash01(Farms.forty_of(c) + Vector2i(int(id) * 7, 3), 23) * CropCalendar.COLS)
	return Vector2i(row, clampi(col, 0, CropCalendar.COLS - 1))


## True while some farm's fields are still being drawn or checked.
func fields_settled() -> bool:
	return _job == null and _queue.is_empty() and not _dirty


## True when nothing at all is waiting: fields, farmsteads, barns, herds.
func settled() -> bool:
	return fields_settled() and _steads.is_empty() and _stead_job == null and not _herd_dirty and _herd_job == null


## Draws every field that is waiting, now (a town that loads; tools).
func finish_now() -> void:
	while not settled():
		_work(1.0e9)


## Each farm's fields: the farms that changed are drawn again, a few
## milliseconds a frame, each into a new mesh that replaces the old one
## when whole, so there are never holes or flicker. A farm whose fields look
## just as they did is only checked.
func _draw_some(budget_ms: float) -> void:
	if sim == null:
		return
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	while true:
		if _job == null:
			if _queue.is_empty():
				if _dirty:
					_dirty = false
					_begin_pass()
					continue
				_end_pass()
				return
			var id: Variant = _queue.pop_front()
			if not sim.farms.farms.has(id):
				continue
			var before: Array = [] if _redo.has(id) or not _drawn.has(id) else _drawn[id].sig
			_redo.erase(id)
			_job = FarmFieldJob.new(sim, id, before)
		elif not sim.farms.farms.has(_job.id):
			_job = null  # the farm went; nothing to show
			continue
		elif _job.view_moved():
			# The land moved under the job: its ground heights are stale.
			_queue.push_front(_job.id)
			_job = null
			continue
		if _job.step(deadline):
			var t0 := Perf.now()
			_install(_job)
			Perf.add("farm_job.install", t0)
			_job = null
		if Time.get_ticks_usec() >= deadline:
			return


## A pass starts with every farm to check.
func _begin_pass() -> void:
	_rows_due = true
	_year = Seasons.year(sim.calendar_tick())
	_forget_gone()
	_queue = sim.farms.farms.keys()


## When a pass is done: the table's farm rows that no farm uses any more
## (last year's crops) are given back, so there is room for the next
## year's. The rows in use keep their numbers: clearing them all would show
## the farms not yet redrawn the wrong crops.
func _end_pass() -> void:
	if not _rows_due:
		return
	_rows_due = false
	if CropCalendar.farm_rows_used() <= (CropCalendar.ROWS - CropCalendar.COUNTY_ROWS) * 3 / 4:
		return
	var keep := extra_rows.duplicate()
	var borrowing := false
	for id in _drawn:
		keep.merge(_drawn[id].rows)
		borrowing = borrowing or _drawn[id].borrows
	# Fields that took a county row because the table was full can have a
	# row of their own now.
	if CropCalendar.free_farm_rows_except(keep) > 0 and borrowing:
		_dirty = true


## A finished job's mesh replaces the farm's old one, and CropPlants hears of
## it (a field on a borrowed county row can change with the year alone).
## A farm's lane is laid as the farm does well (Nathan, 2026-10-25: "start
## dirt and then upgrade to stone and then paved as they do well"): a dirt
## track while it's small, crushed stone once it farms a third of the most
## a farm can, and paved past two thirds.
func lane_material(cells: int) -> Material:
	var share := float(cells) / float(Farms.MAX_CELLS)
	if share >= 2.0 / 3.0:
		return Surfaces.asphalt()
	if share >= 1.0 / 3.0:
		return Surfaces.gravel()
	return _lane_mat


func _install(job: FarmFieldJob) -> void:
	var id: Variant = job.id
	if not sim.farms.farms.has(id):
		return  # the farm went while its fields were being drawn
	if not _drawn.has(id):
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_drawn[id] = {"node": node, "sig": [], "rows": {}, "box": Rect2(), "borrows": false}
	var d: Dictionary = _drawn[id]
	d.borrows = job.borrows
	d.rows = job.rows
	if job.changed:
		d.sig = job.signature
		d.box = job.cell_box
		var node: MeshInstance3D = d.node
		var mesh := job.mesh
		if job.fields_surface >= 0:
			mesh.surface_set_material(job.fields_surface, CropFields.material())
		if job.lane_surface >= 0:
			mesh.surface_set_material(job.lane_surface, lane_material(sim.farms.farms[id].cells.size()))
		node.mesh = mesh
		node.visible = mesh.get_surface_count() > 0
		_trees.set_trees("rows %s" % str(id), job.trees)
	if job.changed or job.borrows:
		var t0 := Perf.now()
		_plants.farm_drawn(id, job.cell_box, job.frame, job.cells, job.slots, job.trimmed)
		Perf.add("farm_job.plants_check", t0)


## How wide the turn rows (headlands) are at each end of a field.
const HEADLAND := FarmFieldJob.HEADLAND


## Queues a farmstead or barn group to be built (FarmSteadJob), unless it
## is already waiting.
func _want_stead(kind: String, key: Variant) -> void:
	for w in _steads:
		if w[0] == kind and w[1] == key:
			return
	# (One being built right now was begun from the farm as it was a moment
	# ago, so this one waits its turn and builds it again.)
	_steads.append([kind, key])


static var _footing: Material


static func _footing_mat() -> Material:
	if _footing == null:
		_footing = Surfaces.concrete(Color(0.5, 0.48, 0.44))
	return _footing


## Livestock barns on their pads beside the farmyards (Livestock, FarmBuilder).
func _sync_barns() -> void:
	_barn_want.clear()
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var kind := Livestock.kind(f)
		for site in Livestock.sites(f):
			_barn_want["%d:%d:%d:%s" % [id, site.x, site.y, kind]] = [id, site, kind]
	for key in _barn_want:
		if not _barns.has(key):
			_want_stead("barn", key)


## Barn groups the farms no longer want go once the new ones are up.
func _free_stale_barns() -> void:
	for w in _steads:
		if w[0] == "barn":
			return
	if _stead_job != null and _stead_job.kind == "barn":
		return
	for key in _barns.keys():
		if not _barn_want.has(key):
			_barns[key].queue_free()
			_barns.erase(key)


## Runs the waiting work: a farmstead step first (each is a few ms at
## most), then the fields and the herds with what is left of `budget_ms`.
func _work(budget_ms: float) -> void:
	if sim == null:
		return
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var t0 := Perf.now()
	_stead_step()
	var t1 := Perf.now()
	var left := (deadline - Time.get_ticks_usec()) / 1000.0
	if left > 0.0:
		_draw_some(left)
	var t2 := Perf.now()
	if Time.get_ticks_usec() < deadline:
		_herd_step(deadline)
	_free_stale_barns()
	work_parts = [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (Perf.now() - t2) / 1000.0]


## One farmstead or barn step, at most one a frame: the biggest unit of work
## here, so it goes first and the fields get what is left of the budget.
func _stead_step() -> void:
	while true:
		if _stead_job == null:
			if _steads.is_empty():
				return
			var w: Array = _steads.pop_front()
			var arg := []
			if w[0] == "barn":
				if not _barn_want.has(w[1]) or _barns.has(w[1]):
					continue
				arg = _barn_want[w[1]]
			else:
				if not sim.farms.farms.has(w[1]):
					continue
				var f: Dictionary = sim.farms.farms[w[1]]
				if _homes.has(w[1]) and _homes[w[1]].get_meta("look") == _look(f) \
						and _homes[w[1]].get_meta("built") == f.get("built", []).size():
					continue  # an earlier job already built it as it is now
			_stead_job = FarmSteadJob.new(self, _trees, sim, w[0], w[1], arg)
			if _stead_job.cancelled():
				_stead_job = null
				continue
		if not _stead_job.step():
			return
		var job := _stead_job
		_stead_job = null
		if job.root == null:
			return
		if job.kind == "home":
			if _homes.has(job.key):
				_homes[job.key].queue_free()
			_homes[job.key] = job.root
		else:
			if _barns.has(job.key):
				_barns[job.key].queue_free()
			_barns[job.key] = job.root
		return  # one step a frame


## Most cows drawn at once, across every herd.
const MAX_COWS := FarmHerdJob.MAX_COWS


## Every beef herd grazing its pasture (FarmHerdJob), when the herds changed.
func _herd_step(deadline: int) -> void:
	if _herd_job == null:
		if not _herd_dirty:
			return
		_herd_dirty = false
		_herd_job = FarmHerdJob.new(sim, _herd_sig)
	if not _herd_job.step(deadline):
		return
	var job := _herd_job
	_herd_job = null
	if not job.changed:
		return
	_herd_sig = job.signature
	_cows.multimesh = job.multimesh
	_cows.visible = job.multimesh != null


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
