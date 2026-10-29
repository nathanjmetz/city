extends SceneTree
## Run: godot --headless -s tests/test_people_dress.gd
## People dress for the month like north-central Indiana (WalkerView.dress):
## coats and long sleeves in winter, shorts in summer, each person the same
## whenever they're seen; dogs come in real coats and sizes.

var _failed := false


func _init() -> void:
	var coats := {1: 0, 7: 0}
	var shorts := {1: 0, 7: 0}
	var sleeves := {1: 0, 7: 0}
	var jeans := 0
	const N := 2000
	for p in N:
		for m in [1, 7]:
			var worn := WalkerView.dress(p, m, 40)
			var o := int(worn[1])
			_check_quiet(o >= 0 and o < 4096, "outfit fits the shader's bits")
			if o & 2048:
				coats[m] += 1
			if o & 16:
				shorts[m] += 1
			if o & 8:
				sleeves[m] += 1
			if m == 7 and (o & 7) >= 1 and (o & 7) <= 3:
				jeans += 1
	_check(coats[1] > N * 0.8 and coats[7] == 0, "coats in January, none in July (%d, %d)" % [coats[1], coats[7]])
	_check(shorts[7] > N * 0.4 and shorts[1] < N * 0.05, "shorts in July, hardly any in January (%d, %d)" % [shorts[7], shorts[1]])
	_check(sleeves[1] == N and sleeves[7] < N * 0.15, "long sleeves all winter, few in summer (%d)" % sleeves[7])
	_check(jeans > N * 0.5 and jeans < N * 0.8, "most wear blue jeans (%d)" % jeans)
	_check(WalkerView.dress(42, 3, 30) == WalkerView.dress(42, 3, 30), "the same person dresses the same way")
	# Coats come out a few at a time: anyone in a coat in November still has
	# it on in December.
	var kept := true
	for p in 500:
		if int(WalkerView.dress(p, 11, 40)[1]) & 2048 and not int(WalkerView.dress(p, 12, 40)[1]) & 2048:
			kept = false
	_check(kept, "a coat out in November stays on in December")
	var grey := 0
	for p in 500:
		if (int(WalkerView.dress(p, 7, 80)[1]) >> 9) & 3 == 3:
			grey += 1
	_check(grey > 250 and (int(WalkerView.dress(7, 7, 20)[1]) >> 9) & 3 != 3, "grey hair with age (%d of 500 at 80)" % grey)
	# The plain outfit (0) is the browser's old look: navy trousers.
	var dog := WalkerView.dog_of(5)
	_check(float(dog[1]) >= 0.6 and float(dog[1]) <= 1.1, "a dog from beagle to shepherd size")
	_check(WalkerView._dog_mesh().get_surface_count() == 1, "a dog mesh")
	# Close up, people keep their figure's sex and long sleeves in the cold.
	var np := NearPeople.new()
	if NearPeople.available():
		np.setup(null, func(): return 0.0)
		var ok := true
		for p in 300:
			var worn := WalkerView.dress(p, 1, 40)
			var m: Dictionary = np._models[np._model_for(p, int(worn[1]))]
			if m.female != (WalkerView.figure(p) == 1) or not m.long:
				ok = false
		_check(ok, "near models match the figure and wear long sleeves in January")
	np.free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check_quiet(ok: bool, what: String) -> void:
	if not ok and not _failed:
		_check(ok, what)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
