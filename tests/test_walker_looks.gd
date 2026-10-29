extends SceneTree
## People on the street are drawn as who they are: a woman's figure for a
## woman's name, a teenager smaller than a grown-up, real adult heights.
## Run: godot --headless -s tests/test_walker_looks.gd

var _failed := false


func _init() -> void:
	_check(WalkerView.figure(1, {"first": "Mary"}) == 1 and WalkerView.figure(1, {"first": "James"}) == 0,
		"Mary is drawn as a woman and James as a man")
	var women := 0.0
	var men := 0.0
	for i in 200:
		women += WalkerView.build(i, {"first": "Linda", "age": 40}).y * 1.7
		men += WalkerView.build(i, {"first": "Robert", "age": 40}).y * 1.7
	_check(absf(women / 200.0 - 1.62) < 0.02 and absf(men / 200.0 - 1.75) < 0.02,
		"grown women average about 1.62 m and men 1.75 m (%.2f, %.2f)" % [women / 200.0, men / 200.0])
	_check(WalkerView.build(7, {"first": "Tyler", "age": 12}).y < WalkerView.build(7, {"first": "Tyler", "age": 16}).y
		and WalkerView.build(7, {"first": "Tyler", "age": 16}).y < WalkerView.build(7, {"first": "Tyler", "age": 30}).y,
		"a boy of 12 is shorter than at 16, and at 16 than grown")
	_check(WalkerView.build(7, {"first": "Betty", "age": 88}).y < WalkerView.build(7, {"first": "Betty", "age": 50}).y,
		"someone in their eighties stands a little shorter")
	# On the sidewalk: each keeps right in a lane of their own, so people
	# coming the other way pass and a family walks side by side.
	var tr := TrafficSim.new(RoadNetwork.new())
	var line := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -100)])
	var back := PackedVector3Array([Vector3(0, 0, -100), Vector3(0, 0, 0)])
	var cum := PackedFloat32Array([0.0, 100.0])
	var xs := []
	for pid in [41, 42, 43]:
		xs.append(tr.walker_pose({"person": pid, "pts": line, "cum": cum, "len": 100.0, "d": 0.0, "t": 0, "t0": 0,
			"v": 1.4}, 0.0)[0].x)
	var other: float = tr.walker_pose({"person": 41, "pts": back, "cum": cum, "len": 100.0, "d": 0.0, "t": 0,
		"t0": 0, "v": 1.4}, 0.0)[0].x
	_check(xs.all(func(x): return x > 0.1 and x < 0.75), "walkers keep to the right half of the walk (%s)" % str(xs))
	_check(absf(xs[0] - xs[1]) > 0.2 and absf(xs[1] - xs[2]) > 0.2, "a household walks side by side, not inside each other")
	_check(other < -0.1, "someone coming the other way passes on the other side (%.2f)" % other)
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
