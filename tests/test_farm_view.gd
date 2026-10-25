extends SceneTree
## Run: godot --headless -s tests/test_farm_view.gd
## The farm fields are redrawn a little each frame, and only for the farms
## that changed (FarmView, FarmFieldJob): a change nobody can see costs no
## redraw, a farm that changes keeps showing its old fields until the new
## ones are whole, the work is spread over several frames, and the picture
## is the same however it is spread. Found 2026-10-25: the field mesh was
## rebuilt all at once (about 250 ms in one frame) on every farm change.

var _failed := false
var _main: Node
var _frames := 0


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
	var sim: CitySim = _main.sim
	var fv: FarmView
	for c in _main.get_children():
		if c is FarmView:
			fv = c
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
		all_drawn = all_drawn and fv._drawn.has(id) and fv._drawn[id].fields.mesh != null \
			and fv._drawn[id].fields.mesh.get_surface_count() == 1
		meshes[id] = fv._drawn[id].fields.mesh
	_check(all_drawn, "every farm has its fields drawn")
	_check(fv.settled(), "and nothing is waiting")

	# A change nobody can see redraws nothing.
	sim.farms_changed.emit()
	_check(not fv.settled(), "a farms change starts a check")
	fv.finish_now()
	var same := true
	for id in ids:
		same = same and fv._drawn[id].fields.mesh == meshes[id]
	_check(same, "farms that did not change keep the very same mesh")

	# One farm's crop changes: only its fields are redrawn, a little at a time,
	# and its old fields show until the new are whole.
	var id: Variant = ids[1]
	var f: Dictionary = sim.farms.farms[id]
	f.crop = "soybeans" if f.crop == "corn" else "corn"
	for k in f.get("fields", {}):
		f.fields[k] = f.fields[k].duplicate()
		f.fields[k].crop = "soybeans" if f.fields[k].crop == "corn" else "corn"
	sim.farms_changed.emit()
	var steps := 0
	var old_until_whole := true
	var never_empty := true
	while not fv.settled() and steps < 5000:
		fv._work(0.05)
		steps += 1
		var m: Mesh = fv._drawn[id].fields.mesh
		never_empty = never_empty and m != null and fv._drawn[id].fields.visible
		if steps == 1:
			old_until_whole = m == meshes[id]
	_check(steps > 5, "the redraw is spread over many small steps (%d)" % steps)
	_check(old_until_whole, "the old fields show while the new are being drawn")
	_check(never_empty, "the farm's fields are never missing while it is redrawn")
	_check(fv._drawn[id].fields.mesh != meshes[id], "then the new fields replace the old")
	var others := true
	for o in ids:
		if o != id:
			others = others and fv._drawn[o].fields.mesh == meshes[o]
	_check(others, "the other farms were not redrawn")

	# The same picture, however the work is spread.
	var view2 := FarmView.new()
	_main.add_child(view2)
	view2.setup(sim)  # all at once, as a town that loads
	var identical := true
	for o in ids:
		var a: Array = fv._drawn[o].fields.mesh.surface_get_arrays(0)
		var b: Array = view2._drawn[o].fields.mesh.surface_get_arrays(0)
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


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
