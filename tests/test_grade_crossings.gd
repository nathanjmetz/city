extends SceneTree
## Run: godot --headless -s tests/test_grade_crossings.gd
## Where the county roads and highways cross the county's railroads at
## grade: every crossing is found once, highways get lights and gates, and
## the gates come down for a passing county train (GradeCrossingView).

var failed := false


func _init() -> void:
	var all := GradeCrossingView.crossings()
	_check(all.size() > 20, "the county's grade crossings are found (%d)" % all.size())
	var active := 0
	var twice := false
	for i in all.size():
		var e: Dictionary = all[i]
		if e.active:
			active += 1
		if e.highway:
			_check(e.active, "a highway crossing has lights and gates")
		_check(CountyGrid.distance(e.at.x, e.at.y) < 1.0 or Highways.distance(e.at.x, e.at.y) < 2.0,
			"a crossing sits on its road")
		for j in range(i + 1, all.size()):
			if all[j].at.distance_to(e.at) < GradeCrossingView.JOIN:
				twice = true
	_check(not twice, "a double track crossing is one crossing")
	_check(active > all.size() / 4 and active < all.size(), "some passive crossings, many active (%d of %d)" % [active, all.size()])
	# A train on a crossing's line closes it; none, it stays open.
	var e: Dictionary
	for c in all:
		if c.active and not c.hits.is_empty():
			e = c
			break
	_check(not e.is_empty(), "an active crossing on a train's line")
	if not e.is_empty():
		var h: Array = e.hits[0]
		var train := {"corridor": h[0], "dir": 1, "s": h[1] + 20.0, "length": 400.0}
		_check(GradeCrossingView._closed(e, [train]), "the gates are down as a train crosses")
		train.s = h[1] - CountyTrains.SPEED * 10.0
		_check(GradeCrossingView._closed(e, [train]), "and come down before it arrives")
		train.s = h[1] + 2000.0
		_check(not GradeCrossingView._closed(e, [train]), "and go up once it has cleared")
		_check(not GradeCrossingView._closed(e, []), "open with no train")
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("  failed: ", what)
