extends SceneTree
## Trees that grow: each kind checked against how the real tree grows
## (docs/trees.md), the growth rules (space colonization, pipe model, the
## same seed the same tree), and that two copies of a town still agree on
## every tree after a save and load.
## Run: godot --headless -s tests/test_tree_growth.gd

var _failed := false


func _init() -> void:
	_curves()
	_kinds()
	_rules()
	_seasons()
	_facts()
	_save_and_load()
	_reference_doc()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## The growth curves go through the reference heights and only ever rise.
func _curves() -> void:
	for sp in TreeKinds.count():
		var k := TreeKinds.kind(sp)
		var ok := true
		for pair in [[10.0, k.h10], [30.0, k.h30], [60.0, k.h60]]:
			ok = ok and absf(TreeKinds.height(sp, pair[0]) - float(pair[1])) < 0.01 * float(pair[1])
		var rising := true
		var last := -1.0
		for age in range(0, 121):
			var h := TreeKinds.height(sp, float(age))
			rising = rising and h > last
			last = h
		_check(ok and rising, "%s: heights at 10, 30, 60 years as the reference, always rising" % k.name)
		var back := TreeKinds.age_for_size(sp, TreeKinds.size_at(sp, 23.0))
		_check(absf(back - 23.0) < 0.1 and absf(TreeKinds.size_at(sp, TreeKinds.REF_AGE) - 1.0) < 0.001,
			"%s: a tree's size gives back its age" % k.name)


## Each kind, grown, against the reference: height at 10, 30 and 60 years,
## crown shape, trunk thickness, branching angle.
func _kinds() -> void:
	var ratio := {}
	for sp in TreeKinds.count():
		var k := TreeKinds.kind(sp)
		var g := TreeGrower.grown(sp, 0)
		var heights := []
		for age in [10.0, 30.0, 60.0]:
			var m := TreeGrower.measure(g.at_age(age))
			var want := TreeKinds.height(sp, age)
			heights.append(m.height)
			_check(m.height > want * 0.8 and m.height < want * 1.12,
				"%s at %d years: %.1f m tall (real: %.1f m)" % [k.name, age, m.height, want])
			_check(absf(m.dbh_cm - TreeKinds.dbh(sp, age)) < TreeKinds.dbh(sp, age) * 0.05 + 0.5,
				"%s at %d years: trunk %.0f cm across at chest height (real: %.0f cm)" % [k.name, age, m.dbh_cm, TreeKinds.dbh(sp, age)])
		var m60 := TreeGrower.measure(g.at_age(60.0))
		var wide: float = m60.width / m60.height
		ratio[sp] = wide
		_check(wide > float(k.wide) * 0.65 and wide < float(k.wide) * 1.3,
			"%s at 60 years: crown %.2f as wide as tall (real: %.2f)" % [k.name, wide, k.wide])
		var ang := _branch_angle(g.at_age(40.0))
		_check(ang > float(k.angle[0]) - 8.0 and ang < float(k.angle[1]) + 8.0,
			"%s: side limbs leave at %.0f degrees on average (real: %d to %d)" % [k.name, ang, k.angle[0], k.angle[1]])
	var S := TreeField.Species
	_check(ratio[S.RED_CEDAR] < 0.5 and ratio[S.SPRUCE] < 0.6, "red cedar and spruce are narrow spires")
	_check(ratio[S.OAK] > ratio[S.MAPLE] and ratio[S.OAK] > ratio[S.COTTONWOOD], "white oak spreads wider than sugar maple and cottonwood")
	var tallest := 0
	for sp in TreeKinds.count():
		if TreeKinds.height(sp, 30.0) > TreeKinds.height(tallest, 30.0):
			tallest = sp
	_check(tallest == S.COTTONWOOD, "cottonwood is the fastest-growing")


## The average angle side limbs leave their parent at, measured over their
## first metre and a half (so it is the limb's real heading, not one step).
func _branch_angle(tree: Dictionary) -> float:
	var p: PackedVector3Array = tree.pos
	var par: PackedInt32Array = tree.parent
	var rad: PackedFloat32Array = tree.radius
	var main: PackedInt32Array = tree.main
	var sum := 0.0
	var n := 0
	for i in range(1, p.size()):
		var q := par[i]
		if rad[i] < 0.02 or q <= 0 or main[q] == i or par[q] < 0:
			continue
		# Follow the limb out about 1.5 m.
		var j := i
		while main[j] >= 0 and p[main[j]].distance_to(p[q]) < 1.5:
			j = main[j]
		var limb := (p[j] - p[q]).normalized()
		var axis := (p[q] - p[par[q]]).normalized()
		sum += rad_to_deg(axis.angle_to(limb))
		n += 1
	return sum / maxf(n, 1)


func _rules() -> void:
	# The same seed always grows the same tree; another seed another tree.
	var a := TreeGrower.grown(TreeField.Species.MAPLE, 7)
	var b := TreeGrower.grown(TreeField.Species.MAPLE, 7)
	var c := TreeGrower.grown(TreeField.Species.MAPLE, 8)
	_check(a.pos == b.pos and a.parent == b.parent and a.born == b.born, "the same seed grows the same tree")
	_check(a.pos != c.pos, "another seed grows another tree")
	# A young tree is the old one's younger self: every limb it has is still
	# there, in the same place, years later (unless the crown lifted past it).
	var young := a.at_age(10.0)
	var old := a.at_age(30.0)
	var kept := 0
	var yk: PackedByteArray = young.keep
	var ok: PackedByteArray = old.keep
	for i in yk.size():
		if yk[i] == 1 and ok[i] == 1:
			kept += 1
	_check(kept > 20, "the 30-year-old keeps the 10-year-old's limbs (%d of them)" % kept)
	_check(TreeGrower.measure(old).height > TreeGrower.measure(young).height * 2.0, "and is much bigger")
	# Pipe model: a limb's cross-section is the sum of the limbs beyond it.
	var r: PackedFloat32Array = old.radius
	var par: PackedInt32Array = old.parent
	var sums := PackedFloat32Array()
	sums.resize(r.size())
	sums.fill(0.0)
	for i in range(1, r.size()):
		if r[i] > 0.0:
			sums[par[i]] += pow(r[i], TreeGrower.PIPE_N)
	var worst := 0.0
	for i in r.size():
		if sums[i] > 0.0:
			worst = maxf(worst, absf(pow(r[i], TreeGrower.PIPE_N) / sums[i] - 1.0))
	_check(worst < 0.01, "limb thickness follows the pipe model (worst %.4f off)" % worst)
	# Two levels of detail from the same branches, the light one much lighter.
	var full := TreeMesher.build(TreeField.Species.MAPLE, old, TreeMesher.Lod.FULL, 7)
	var light := TreeMesher.build(TreeField.Species.MAPLE, old, TreeMesher.Lod.LIGHT, 7)
	var tf := _tris(full)
	var tl := _tris(light)
	_check(not full[0].is_empty() and not full[1].is_empty() and not light[0].is_empty() and not light[1].is_empty(),
		"both levels have bark and leaves")
	_check(tl * 3 < tf, "the light tree is under a third of the full one (%d against %d triangles)" % [tl, tf])
	_check(JSON.stringify(full[0][Mesh.ARRAY_VERTEX]) == JSON.stringify(TreeMesher.build(TreeField.Species.MAPLE, old,
		TreeMesher.Lod.FULL, 7)[0][Mesh.ARRAY_VERTEX]), "the same tree always gives the same mesh")
	# Built a slice at a time, it comes out the same as all at once.
	var sliced := TreeGrower.new(TreeField.Species.MAPLE, 7)
	var slices := 0
	while not sliced.step(2000):
		slices += 1
	_check(slices > 3 and sliced.pos == a.pos, "growing in slices gives the same tree (%d slices)" % slices)
	_check(GrownTrees.bucket(5.0) == 2 and GrownTrees.bucket(40.0) == 8 and GrownTrees.bucket(500.0) == 12,
		"ages round to the nearest grown age")


func _tris(parts: Array) -> int:
	var t := 0
	for s in parts:
		if not s.is_empty():
			t += (s[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return t


## Each kind keeps its own calendar: black walnut drops its leaves weeks
## before the oaks; evergreens stay green; crabapples bloom.
func _seasons() -> void:
	var S := TreeField.Species
	var early_oct := 9.15
	_check(TreeKinds.season(S.WALNUT, early_oct).x > TreeKinds.season(S.OAK, early_oct).x,
		"black walnut turns before white oak")
	var mid_nov := 10.55
	_check(TreeKinds.season(S.OAK, mid_nov).y < TreeKinds.season(S.MAPLE, mid_nov).y + 0.001
		and TreeKinds.season(S.WALNUT, mid_nov).y >= TreeKinds.season(S.MAPLE, mid_nov).y,
		"in November walnuts are bare first, oaks hold their leaves longest")
	_check(TreeKinds.season(S.SPRUCE, 0.5) == Vector3.ZERO and TreeKinds.season(S.RED_CEDAR, 10.5) == Vector3.ZERO,
		"evergreens keep their needles")
	_check(TreeKinds.season(S.MAPLE, 0.5).y > 0.9 and TreeKinds.season(S.MAPLE, 6.5) == Vector3.ZERO,
		"bare in January, full green in July")
	_check(Color(TreeKinds.kind(S.CRABAPPLE).bloom).a > 0.5 and Color(TreeKinds.kind(S.MAPLE).bloom).a == 0.0,
		"crabapples bloom")


## A tree is facts: kind, seed (where it stands) and age from its planting
## date. Planted trees start as nursery saplings and grow with the clock.
func _facts() -> void:
	var sp := TreeField.Species.MAPLE
	var xf := Transform3D(Basis().scaled(Vector3.ONE * 0.9), Vector3(10, 0, 20))
	var year := Seasons.TICKS_PER_DAY * 12
	TreeField.now_tick = 1000
	var r0 := TreeField.resolve([xf, sp, Color.GREEN, {"planted": 1000}])
	TreeField.now_tick = 1000 + year * 10
	var r10 := TreeField.resolve([xf, sp, Color.GREEN, {"planted": 1000}])
	TreeField.now_tick = 1000 + year * 35
	var r35 := TreeField.resolve([xf, sp, Color.GREEN, {"planted": 1000}])
	var h0 := (r0[0] as Transform3D).basis.get_scale().y * TreeKinds.height(sp, TreeKinds.REF_AGE)
	var h10 := (r10[0] as Transform3D).basis.get_scale().y * TreeKinds.height(sp, TreeKinds.REF_AGE)
	var h35 := (r35[0] as Transform3D).basis.get_scale().y * TreeKinds.height(sp, TreeKinds.REF_AGE)
	_check(absf(float(r0[3]) - TreeKinds.NURSERY_AGE) < 0.01 and h0 > 1.5 and h0 < 4.0,
		"a yard tree goes in as a nursery sapling (%.1f m)" % h0)
	_check(absf(float(r10[3]) - TreeKinds.NURSERY_AGE - 10.0) < 0.01 and h10 > h0 * 2.0 and h35 > h10 * 1.4,
		"and grows with the game's years (%.1f m after 10, %.1f m after 35)" % [h10, h35])
	_check(r0[4] == TreeField.resolve([xf, sp, Color.RED])[4], "its seed is where it stands")
	var wild := TreeField.resolve([xf, sp, Color.GREEN])
	_check(absf(float(wild[3]) - TreeKinds.age_for_size(sp, 0.9)) < 0.01, "a tree without a date is as old as its size")
	_check(not TreeField.resolve([xf, sp, Color.GREEN, {"shrub": true}])[5], "brush never grows up close")
	TreeField.now_tick = 0


## Two copies of a town agree on every tree after a save and load: yard
## trees by their building's build date, wild trees by the land.
func _save_and_load() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "clear"})
	PerfTown.build(sim, "small")
	sim.require_utilities = false
	for i in 2500:
		sim.tick()
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.tick()
	sim.tick()
	var same := sim.buildings.size() == copy.buildings.size() and sim.buildings.size() > 20
	for key in sim.buildings:
		same = same and copy.buildings.has(key) and int(copy.buildings[key].built) == int(sim.buildings[key].built)
	_check(same, "the copy plants every yard tree on the same date (%d buildings)" % sim.buildings.size())
	var area := Rect2(-600, -600, 1200, 1200)
	var a := _wild_facts(sim, area)
	var b := _wild_facts(copy, area)
	_check(a.size() > 500 and JSON.stringify(a) == JSON.stringify(b),
		"the copy grows the same wild trees: kind, place and age (%d trees)" % a.size())


func _wild_facts(sim: CitySim, area: Rect2) -> Array:
	var out := []
	for p in sim.vegetation.plants_in(area, sim.tick_count):
		var f := WildView.facts(p, false)
		out.append([f[1], TreeField.seed_of((f[0] as Transform3D).origin), f[3]])
	return out


## The written reference covers every kind.
func _reference_doc() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/trees.md").to_lower()
	var missing := []
	for sp in TreeKinds.count():
		if not doc.contains("### " + str(TreeKinds.kind(sp).name)):
			missing.append(TreeKinds.kind(sp).name)
	_check(missing.is_empty(), "docs/trees.md describes every kind (missing: %s)" % ", ".join(missing))


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
