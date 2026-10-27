extends SceneTree
## Run: godot --headless -s tests/test_farm_view.gd
## The farm fields are redrawn a little each frame, and only for the farms
## that changed (FarmView, FarmFieldJob): a change nobody can see costs no
## redraw, a farm that changes keeps showing its old fields until the new
## ones are whole, the work is spread over several frames, and the picture
## is the same however it is spread. Found 2026-10-25: the field mesh was
## rebuilt all at once (about 250 ms in one frame) on every farm change.
##
## "The same picture" is checked against the old all-at-once drawing
## (tests/old_farm_fields.gd, a copy of it): every triangle of every farm's
## fields and lane, with its colour and texture coordinates, and the trees
## in its fencerows. Then the awkward moments, each ending with that same
## comparison: a farm removed while it is being drawn, a second change
## while it is, a year that turns, the table's farm rows running short, a
## road graded beside a farm, and the ground moving under the job.

const Old := preload("res://tests/old_farm_fields.gd")

var _failed := false
var _main: Node
var _frames := 0
var _sim: CitySim
var _fv: FarmView


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run()
	print("FAIL" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)
	return true


func _run() -> void:
	_sim = _main.sim
	var sim := _sim
	var terrain: TerrainView
	for c in _main.get_children():
		if c is FarmView:
			_fv = c
		if c is TerrainView:
			terrain = c
	var fv := _fv
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	_main.set_speed(0)
	sim.apply({"type": "build_road", "start": [-1200, 0], "ctrl": [0, 0], "end": [1200, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-1150, 30], [1150, 30], [1150, 1100], [-1150, 1100]]})
	for x in [-700, -100, 500]:
		sim.apply({"type": "place_farmhouse", "pos": [x, 60], "dir": [0, -1], "crop": "corn"})
	sim.farms.price = 1.2
	for i in 200:
		sim.farms.decide(sim.field_usable)
	sim.farms_changed.emit()
	fv.finish_now()
	var ids: Array = sim.farms.farms.keys()
	_check(ids.size() >= 3, "three farms (%d)" % ids.size())
	var meshes := {}
	var all_drawn := true
	for id in ids:
		all_drawn = all_drawn and fv._drawn.has(id) and fv._drawn[id].node.mesh != null \
			and _surfaces(fv._drawn[id].node.mesh)[0] != null
		meshes[id] = fv._drawn[id].node.mesh
	_check(all_drawn, "every farm has its fields drawn")
	_check(fv.settled(), "and nothing is waiting")
	var meshes_in_view := 0
	for c in fv.get_children():
		if c is MeshInstance3D:
			meshes_in_view += 1
	_check(meshes_in_view == ids.size(), "a farm's fields and lane are one object in the scene (%d for %d)" % [meshes_in_view, ids.size()])

	# The same picture as the old all-at-once drawing, triangle for triangle.
	_same_as_old(ids, "to begin with")

	# A change nobody can see redraws nothing.
	sim.farms_changed.emit()
	_check(not fv.settled(), "a farms change starts a check")
	fv.finish_now()
	var same := true
	for id in ids:
		same = same and fv._drawn[id].node.mesh == meshes[id]
	_check(same, "farms that did not change keep the very same mesh")

	# One farm's crop changes: only its fields are redrawn, a little at a time,
	# and its old fields show until the whole new ones are ready: from the
	# first small step to the last, the old mesh stays, and then the new
	# one is there in one go.
	var id: Variant = ids[1]
	_flip(id)
	sim.farms_changed.emit()
	var steps := 0
	var changes := 0
	var seen: Mesh = meshes[id]
	var old_until_whole := true
	var never_empty := true
	var job_steps := 0
	while not fv.settled() and steps < 5000:
		fv._work(0.05)
		steps += 1
		var node: MeshInstance3D = fv._drawn[id].node
		var m: Mesh = node.mesh
		never_empty = never_empty and m != null and node.visible
		if fv._job != null and fv._job.id == id:
			job_steps += 1
			old_until_whole = old_until_whole and m == meshes[id]
		if m != seen:
			changes += 1
			seen = m
	_check(steps > 5, "the redraw is spread over many small steps (%d)" % steps)
	_check(job_steps > 5 and old_until_whole, "the old fields show through every step of the new drawing (%d steps)" % job_steps)
	_check(never_empty, "the farm's fields are never missing while it is redrawn")
	_check(changes == 1 and fv._drawn[id].node.mesh != meshes[id], "then the new fields replace the old, once, whole (%d)" % changes)
	var others := true
	for o in ids:
		if o != id:
			others = others and fv._drawn[o].node.mesh == meshes[o]
	_check(others, "the other farms were not redrawn")
	_same_as_old(ids, "after a crop change")

	# Each farm tells the close-up plants as it finishes, not at the end of
	# the whole pass.
	_flip(ids[0])
	_flip(ids[2])
	sim.farms_changed.emit()
	var before: Dictionary = {}
	for o in ids:
		before[o] = fv._drawn[o].node.mesh
	var first_told := false
	var other_waiting := false
	steps = 0
	while not fv.settled() and steps < 5000:
		fv._work(0.05)
		steps += 1
		var done := []
		for o in ids:
			if fv._drawn[o].node.mesh != before[o]:
				done.append(o)
		if done.size() == 1 and not (fv._job == null and fv._queue.is_empty()):
			first_told = fv._plants._farm_sigs[done[0]][1] == _fresh_sig(done[0])
			for o in [ids[0], ids[2]]:
				if o != done[0]:
					other_waiting = fv._plants._farm_sigs[o][1] != _fresh_sig(o)
			break
	_check(first_told, "the plants hear of a farm the moment its fields are whole")
	_check(other_waiting, "while the farm still waiting has not been told yet")
	fv.finish_now()
	_check(_plants_current(ids), "and in the end they know every farm")

	# The same picture, however the work is spread.
	var view2 := FarmView.new()
	_main.add_child(view2)
	view2.setup(sim)  # all at once, as a town that loads
	var identical := true
	for o in ids:
		var a: Array = fv._drawn[o].node.mesh.surface_get_arrays(0)
		var b: Array = view2._drawn[o].node.mesh.surface_get_arrays(0)
		identical = identical and a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_COLOR] == b[Mesh.ARRAY_COLOR] \
			and a[Mesh.ARRAY_TEX_UV] == b[Mesh.ARRAY_TEX_UV]
	_check(identical, "fields drawn in many steps and all at once are the same")

	# A farm that is gone takes its fields with it.
	var saved: Dictionary = sim.farms.farms[id]
	sim.farms.farms.erase(id)
	view2._rebuild()
	view2.finish_now()
	_check(not view2._drawn.has(id) and view2._drawn.size() == ids.size() - 1, "a farm that is gone loses its fields")
	sim.farms.farms[id] = saved
	view2.queue_free()

	# --- a farm removed while its fields are being drawn ---
	var victim: Variant = ids[1]
	_flip(victim)
	sim.farms_changed.emit()
	_step_until(func(): return fv._job != null and fv._job.id == victim and fv._job.phase == FarmFieldJob.Phase.CELLS)
	_check(fv._job != null and fv._job.id == victim, "(a drawing of the farm is under way)")
	var farm: Dictionary = sim.farms.farms[victim]
	sim.farms.farms.erase(victim)
	sim.farms_changed.emit()
	_check(not fv._drawn.has(victim) and fv._job == null, "a farm removed mid-drawing loses its fields and its job at once")
	_check(not fv._trees._trees.has("rows %s" % str(victim)) and not fv._trees._trees.has(str(victim)), "and its trees")
	_check(not fv._plants._farm_sigs.has(victim), "and the plants forget it")
	fv.finish_now()
	_check(not fv._drawn.has(victim) and _mesh_count() == ids.size() - 1, "nothing of it comes back when the work goes on (%d objects)" % _mesh_count())
	# A job that was whole when the farm went installs nothing.
	var stale := FarmFieldJob.new(sim, ids[0], [])
	while not stale.step(Time.get_ticks_usec() + 1_000_000):
		pass
	var gone: Variant = ids[0]
	var gone_farm: Dictionary = sim.farms.farms[gone]
	sim.farms.farms.erase(gone)
	var drawn_before := fv._drawn.size()
	fv._install(stale)
	_check(fv._drawn.size() == drawn_before and _mesh_count() == drawn_before, "a finished drawing of a farm that is gone is dropped")
	# A farm that never had its farmstead built goes the same way.
	sim.farms.farms[gone] = gone_farm
	sim.farms_changed.emit()
	fv.finish_now()
	_check(fv._drawn.has(gone), "(the farm is back)")
	var home = fv._homes.get(gone)
	if home != null:
		home.free()
		fv._homes.erase(gone)
	sim.farms.farms.erase(gone)
	sim.farms_changed.emit()
	_check(not fv._drawn.has(gone) and not fv._trees._trees.has("rows %s" % str(gone)) and _mesh_count() == drawn_before - 1,
		"a farm without a farmstead built yet loses its fields and trees too")
	fv.finish_now()
	sim.farms.farms[gone] = gone_farm
	sim.farms.farms[victim] = farm
	sim.farms_changed.emit()
	fv.finish_now()
	_check(_mesh_count() == ids.size() and fv.settled(), "and they come back when the farms do")
	_same_as_old(ids, "after farms went and came back")

	# --- a second change while the first is being drawn ---
	var twice: Variant = ids[2]
	_flip(twice)
	sim.farms_changed.emit()
	_step_until(func(): return fv._job != null and fv._job.id == twice and fv._job.phase == FarmFieldJob.Phase.CELLS)
	_make_wheat(twice)
	sim.farms_changed.emit()
	fv.finish_now()
	_same_as_old(ids, "when a second change came mid-drawing")
	_check(_plants_current(ids), "(and the plants know it)")

	# --- the table's farm rows running short, mid-pass ---
	var year_now := Seasons.year(sim.tick_count)
	var used_before := CropCalendar.farm_rows_used()
	var n := 0
	while CropCalendar.farm_rows_used() < 92:
		CropCalendar.farm_row("dummy", "d%d" % n, 0, false, false)
		n += 1
	var specs := {}  # every row the farms use: what it must keep meaning
	for o in ids:
		for row in fv._drawn[o].rows:
			specs[row] = CropCalendar.spec(row, year_now).duplicate()
	for o in ids:
		_flip(o)
	sim.farms_changed.emit()
	var mid_ok := true
	var checked := 0
	steps = 0
	while not fv.settled() and steps < 5000:
		fv._work(0.05)
		steps += 1
		# A row a drawn farm uses never changes its meaning: not for the
		# farms still waiting to be redrawn, not for the ones that were.
		for o in ids:
			for row in fv._drawn[o].rows:
				if specs.has(row):
					checked += 1
					mid_ok = mid_ok and CropCalendar.spec(row, year_now) == specs[row]
	_check(mid_ok and checked > 0, "a farm waiting to be redrawn keeps the meaning of its rows while the others change (%d looks)" % checked)
	_check(CropCalendar.farm_rows_used() < 92 and CropCalendar.farm_rows_used() >= used_before - 20,
		"when the pass is over the rows nobody uses are given back (%d, was 92)" % CropCalendar.farm_rows_used())
	_same_as_old(ids, "after the table's rows ran short")

	# --- the year turning while a farm is being drawn ---
	# Fill the table so every field borrows a county row, whose crops follow the year.
	CropCalendar.clear_farm_rows()
	n = 0
	while CropCalendar.farm_rows_used() < CropCalendar.ROWS - CropCalendar.COUNTY_ROWS:
		fv.extra_rows[CropCalendar.farm_row("dummy", "d%d" % n, 0, false, false)] = true
		n += 1
	sim.farms_changed.emit()
	fv.finish_now()
	var borrowing := 0
	for o in ids:
		borrowing += 1 if fv._drawn[o].borrows else 0
	_check(borrowing == ids.size(), "(every farm borrows county rows now: %d)" % borrowing)
	_same_as_old(ids, "borrowing county rows")
	var sigs_before := {}
	for o in ids:
		sigs_before[o] = fv._plants._farm_sigs[o][1]
	var turn: Variant = ids[0]
	_flip(turn)
	sim.farms_changed.emit()
	_step_until(func(): return fv._job != null and fv._job.id == turn and fv._job.phase == FarmFieldJob.Phase.CELLS)
	var tick_was := sim.tick_count
	sim.tick_count += Seasons.TICKS_PER_DAY * Seasons.YEAR_DAYS
	fv._process(0.0)
	fv.finish_now()
	_check(Seasons.year(sim.tick_count) == year_now + 1, "(the year has turned)")
	_same_as_old(ids, "after the year turned mid-drawing")
	_check(_plants_current(ids), "the plants have the new year's crops of every farm that borrows")
	var changed_by_year := 0
	for o in ids:
		changed_by_year += 1 if fv._plants._farm_sigs[o][1] != sigs_before[o] else 0
	_check(changed_by_year > 0, "and some farm's look to them changed with the year (%d)" % changed_by_year)
	# The year turns on its own, with nothing drawing: a borrowed row's crop still reaches the plants.
	var sigs_mid := {}
	for o in ids:
		sigs_mid[o] = fv._plants._farm_sigs[o][1]
	sim.tick_count += Seasons.TICKS_PER_DAY * Seasons.YEAR_DAYS
	fv._process(0.0)
	fv.finish_now()
	_same_as_old(ids, "after a year turned with nothing drawing")
	_check(_plants_current(ids), "(and the plants follow)")
	sim.tick_count = tick_was
	fv._process(0.0)
	fv.finish_now()
	fv.extra_rows.clear()
	CropCalendar.clear_farm_rows()
	sim.farms_changed.emit()
	fv.finish_now()
	_same_as_old(ids, "with the rows cleared and the first year back")

	# --- a road graded beside a farm, with no change to the farm ---
	var target: Variant = ids[0]
	var box := FarmFieldJob.box_of(sim.farms.farms[target])
	var far: Variant = ids[2]
	var far_mesh: Mesh = fv._drawn[far].node.mesh
	var target_mesh: Mesh = fv._drawn[target].node.mesh
	var mid_z := box.position.y + box.size.y * 0.5
	var a := Vector3(box.position.x + box.size.x * 0.25, 9.0, mid_z)
	var b := Vector3(box.position.x + box.size.x * 0.75, 9.0, mid_z)
	var emitted := [0]
	sim.farms_changed.connect(func(): emitted[0] += 1)
	var strip_y := Terrain.ground_y(a.x, a.z) + 6.0
	a.y = strip_y
	b.y = strip_y
	var sig_target: Array = fv._drawn[target].sig.duplicate(true)
	terrain.add_strips("farm_test", {"s1": [PackedVector3Array([a, b]), 8.0, 20.0, 12.0]})
	_check(emitted[0] == 0, "(the farms did not change)")
	_check(not fv.settled(), "grading the ground beside a farm sets its fields to be redrawn")
	fv.finish_now()
	_check(fv._drawn[target].node.mesh != target_mesh, "the farm beside the new road got a new mesh")
	_check(fv._drawn[target].sig == sig_target, "(though its crops and cells are what they were)")
	_check(fv._drawn[far].node.mesh == far_mesh, "a farm far from it was not redrawn")
	_same_as_old(ids, "after a road was graded beside a farm")
	# The grading comes before the farm's own change.
	var after_a: Mesh = fv._drawn[target].node.mesh
	terrain.add_strips("farm_test", {"s1": [PackedVector3Array([a + Vector3(0, 0, 4), b + Vector3(0, 0, 4)]), 8.0, 20.0, 12.0]})
	_flip(target)
	sim.farms_changed.emit()
	fv.finish_now()
	_check(fv._drawn[target].node.mesh != after_a, "a grading and a farm change together draw it again")
	_same_as_old(ids, "after a grading then a farm change")
	# ... and in the middle of a drawing.
	_flip(target)
	sim.farms_changed.emit()
	_step_until(func(): return fv._job != null and fv._job.id == target and fv._job.phase == FarmFieldJob.Phase.FENCE)
	var job_was := fv._job
	terrain.add_strips("farm_test", {"s1": [PackedVector3Array([a + Vector3(0, 0, -6), b + Vector3(0, 0, -6)]), 8.0, 20.0, 12.0]})
	_check(fv._job != job_was, "the ground graded under a farm being drawn starts its drawing over")
	fv.finish_now()
	_same_as_old(ids, "after a grading in the middle of a drawing")
	terrain.remove_network("farm_test")
	fv.finish_now()
	_same_as_old(ids, "after the grading was taken away")

	# --- the ground moves under a drawing ---
	var movers: Variant = ids[1]
	_flip(movers)
	sim.farms_changed.emit()
	_step_until(func(): return fv._job != null and fv._job.id == movers and fv._job.phase == FarmFieldJob.Phase.CELLS)
	job_was = fv._job
	var origin_was := Terrain.view_origin
	Terrain.view_origin += Vector2(37.0, -23.0)
	steps = 0
	while fv._job == job_was and steps < 50:
		fv._work(0.05)
		steps += 1
	_check(fv._job != job_was, "a job whose ground moved is started over")
	fv.finish_now()
	_check(fv.settled(), "and the work still finishes")
	_same_as_old([movers], "after the view moved mid-drawing")
	Terrain.view_origin = origin_was


## --- helpers ---

func _flip(id: Variant) -> void:
	var f: Dictionary = _sim.farms.farms[id]
	f.crop = "soybeans" if f.crop == "corn" else "corn"
	for k in f.get("fields", {}):
		f.fields[k] = f.fields[k].duplicate()
		f.fields[k].crop = "soybeans" if f.fields[k].crop == "corn" else "corn"


func _make_wheat(id: Variant) -> void:
	var f: Dictionary = _sim.farms.farms[id]
	f.crop = "wheat"
	for k in f.get("fields", {}):
		f.fields[k] = f.fields[k].duplicate()
		f.fields[k].crop = "wheat"


func _mesh_count() -> int:
	var n := 0
	for c in _fv.get_children():
		if c is MeshInstance3D and not c.is_queued_for_deletion():
			n += 1
	return n


## Runs the farm work in small steps until `cond` holds (or gives up).
func _step_until(cond: Callable) -> void:
	var steps := 0
	while not cond.call() and steps < 20000:
		_fv._work(0.02)
		steps += 1


## What the plants should know of a farm by now.
func _fresh_sig(id: Variant) -> int:
	var f: Dictionary = _sim.farms.farms[id]
	var slots := []
	for c in f.cells:
		slots.append(FarmView.slot_of(id, f, c))
	return CropPlants.sig_of({"pos": f.pos, "dir": f.dir}, f.cells, slots, _sim.farms.trim.get(id, {}))


func _plants_current(ids: Array) -> bool:
	var ok := true
	for id in ids:
		ok = ok and _fv._plants._farm_sigs.has(id) and _fv._plants._farm_sigs[id][1] == _fresh_sig(id)
	return ok


## [fields arrays or null, lane arrays or null] of a farm's drawn mesh.
func _surfaces(mesh: Mesh) -> Array:
	var out := [null, null]
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		out[0 if mat == CropFields.material() else 1] = mesh.surface_get_arrays(i)
	return out


## Every triangle of a surface, as text: each corner's place, colour and
## texture coordinates, the corners turned so the smallest comes first (the
## same triangle however its corners are numbered, but not a flipped one),
## counted.
func _triangles(arrays) -> Dictionary:
	var out := {}
	if arrays == null:
		return out
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx = arrays[Mesh.ARRAY_INDEX]
	var has_idx: bool = idx != null and not (idx as PackedInt32Array).is_empty()
	var n: int = idx.size() if has_idx else v.size()
	for k in range(0, n, 3):
		var keys := []
		for j in 3:
			var i: int = idx[k + j] if has_idx else k + j
			var c := col[i] if i < col.size() else Color.BLACK
			var t := uv[i] if i < uv.size() else Vector2.ZERO
			keys.append("%d,%d,%d|%d,%d,%d,%d|%d,%d" % [roundi(v[i].x * 200.0), roundi(v[i].y * 200.0), roundi(v[i].z * 200.0),
				roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0), roundi(c.a * 255.0),
				roundi(t.x * 1000.0), roundi(t.y * 1000.0)])
		var lowest := 0
		for j in 3:
			if keys[j] < keys[lowest]:
				lowest = j
		var key: String = keys[lowest] + "/" + keys[(lowest + 1) % 3] + "/" + keys[(lowest + 2) % 3]
		out[key] = out.get(key, 0) + 1
	return out


func _trees_of(list: Array) -> Array:
	var out := []
	for t in list:
		var o: Vector3 = t[0].origin
		out.append("%d,%d,%d|%d" % [roundi(o.x * 100.0), roundi(o.y * 100.0), roundi(o.z * 100.0), t[1]])
	out.sort()
	return out


## Every farm's fields, lane and trees as drawn now against the old
## all-at-once drawing of the same farm now.
func _same_as_old(ids: Array, when: String) -> void:
	var fields_ok := true
	var lane_ok := true
	var trees_ok := true
	var total := 0
	var detail := ""
	for id in ids:
		if not _sim.farms.farms.has(id):
			continue
		var old: Array = Old.draw(_sim, id)
		var now: Array = _surfaces(_fv._drawn[id].node.mesh)
		var old_fields := _triangles(old[0].surface_get_arrays(0) if old[0] != null and old[0].get_surface_count() > 0 else null)
		var old_lane := _triangles(old[1].surface_get_arrays(0) if old[1] != null and old[1].get_surface_count() > 0 else null)
		var new_fields := _triangles(now[0])
		var new_lane := _triangles(now[1])
		total += new_fields.size() + new_lane.size()
		if old_fields != new_fields:
			fields_ok = false
			detail += " fields of %s: %d triangles now, %d before;" % [str(id), new_fields.size(), old_fields.size()]
		if old_lane != new_lane:
			lane_ok = false
		var tree_now: Array = _trees_of(_fv._trees._trees.get("rows %s" % str(id), []))
		trees_ok = trees_ok and tree_now == _trees_of(old[2])
	_check(total > 100, "(%s: there are triangles to compare, %d)" % [when, total])
	_check(fields_ok, "fields are the old drawing's triangles %s%s" % [when, detail])
	_check(lane_ok, "lanes are the old drawing's triangles %s" % when)
	_check(trees_ok, "fencerow trees are the old drawing's %s" % when)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
