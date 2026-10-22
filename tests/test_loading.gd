extends SceneTree
## Run: godot --headless -s tests/test_loading.gd

var _ls: LoadingScreen
var _frames := 0
var _failed := false
var _finished := false
var _full := false


func _initialize() -> void:
	_ls = LoadingScreen.open("Pouring foundations")
	_check(LoadingScreen.open() == _ls, "opening again returns the same screen")
	_check(_ls.name == "LoadingScreen", "found at root/LoadingScreen")
	_ls.set_progress(0.5)
	_ls.set_progress(0.3)
	_check(is_equal_approx(_ls._target, 0.5), "progress never goes backwards")
	_ls.begin_step("Paving roads", 0.9)
	_ls.step_progress(0.5)
	_check(is_equal_approx(_ls._target, 0.7), "a step moves within its own range")
	_ls.finished.connect(func():
		_finished = true
		_full = _ls._shown >= 1.0)
	LoadingScreen.close()


func _process(_delta: float) -> bool:
	_frames += 1
	if _finished:
		_check(not LoadingScreen.is_open(), "closed after finishing")
		_check(_full, "filled to 100% before fading")
		print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
		quit(1 if _failed else 0)
	elif _frames > 600:
		_check(false, "finishes within 10 seconds")
		quit(1)
	return false


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
