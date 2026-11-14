extends SceneTree
## Run: godot --headless -s tests/test_prop_log.gd
## Scanned props the builders stand on lots (PropLog, PropField): nothing is
## placed unless a view collects and the scan is on this machine; placing
## a prop never moves anything else the builder draws; and the field files,
## counts and drops them per lot.

var _failed := false


func _initialize() -> void:
	# Not collecting: place() always says no, so the builder draws its own.
	_check(not PropLog.place(null, "standing_chalkboard_01", Transform3D.IDENTITY), "no prop placed outside a collection")
	# Collecting a scan this machine doesn't have: no.
	var none := PropLog.collect(func(): _check(not PropLog.place(null, "no_such_scan", Transform3D.IDENTITY), "a missing scan is never placed"))
	_check(none.is_empty(), "nothing collected for a missing scan")
	# Main Street blocks drawn with and without the art: the same walls,
	# masses and trees (fallbacks keep the builders' random numbers).
	var seen := 0
	for sd in range(700, 730):
		var lot := {"width": 20.0, "depth": 45.0, "era": "prewar"}
		var plain: Array = DenseBuilder.build_mixed(sd, 3.9, lot, 2)
		var masses_plain: Array = HouseBuilder.last_masses.duplicate()
		var box := []
		var props := PropLog.collect(func(): box.append(DenseBuilder.build_mixed(sd, 3.9, lot, 2)))
		var with: Array = box[0]
		seen += props.size()
		_check(HouseBuilder.last_masses == masses_plain, "seed %d: same masses with the props" % sd)
		_check(plain[2].size() == with[2].size(), "seed %d: same trees with the props" % sd)
		_check(plain[3].size() == with[3].size(), "seed %d: same labels with the props" % sd)
		for p in props:
			_check(PropLog.mesh_of(p[0]) != null, "seed %d: %s has a mesh" % [sd, p[0]])
	if AssetLib.has("standing_chalkboard_01"):
		_check(seen > 0, "Main Street blocks stand some scanned props when the art is here")
	# The field: put, count, drop.
	var field := PropField.new()
	field.put("a", Transform3D(Basis(), Vector3(10, 0, 10)), [["x|", Transform3D.IDENTITY], ["x|", Transform3D.IDENTITY]])
	field.put("b", Transform3D(Basis(), Vector3(600, 0, 10)), [["x|", Transform3D.IDENTITY]])
	_check(field.count() == 3, "the field counts every lot's props")
	field.put("a", Transform3D.IDENTITY, [])
	_check(field.count() == 1, "redrawing a lot with no props clears its old ones")
	field.drop("b")
	_check(field.count() == 0, "dropping a lot drops its props")
	field.free()
	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
