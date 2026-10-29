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
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
