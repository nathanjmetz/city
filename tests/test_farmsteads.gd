extends SceneTree
## Run: godot --headless -s tests/test_farmsteads.gd
## County farmsteads (FarmsteadPlan, FarmsteadFar, FarmBuilder's close-up):
## grown the same on every computer from their few facts, laid out the
## way real east-central Indiana farmsteads are (docs/farmsteads.md), and
## cheap enough to build a step a frame, handed over between the far and the
## close-up drawing without a gap or a double, and the same on every computer.

var _failed := false


func _init() -> void:
	var places := _places()
	_check(places.size() > 4000, "the county's farmsteads load (%d)" % places.size())

	# Same facts, same farmstead (every player in a region sees the same farm).
	var a := FarmsteadPlan.grow(places[10][0], places[10][1], places[10][2], places[10][3])
	var b := FarmsteadPlan.grow(places[10][0], places[10][1], places[10][2], places[10][3])
	_check(var_to_str(a) == var_to_str(b), "the same facts grow the same farmstead")

	var kinds := {}
	var houses := {}
	var overlaps := 0
	var bad_trees := 0
	var bad_years := 0
	var bad_bins := 0
	var windbreaks := 0
	var windward := 0
	var short_store := 0
	var grain := 0
	var lanes_ok := true
	var reach := 0.0
	var plans := []
	for pl in places:
		var p := FarmsteadPlan.grow(pl[0], pl[1], pl[2], pl[3])
		plans.append(p)
		kinds[p.kind] = kinds.get(p.kind, 0) + 1
		houses[p.house.type] = houses.get(p.house.type, 0) + 1
		var era: Array = []
		for t in (FarmsteadPlan.HOME_HOUSES if p.kind == "home" else FarmsteadPlan.FARM_HOUSES):
			if t[0] == p.house.type:
				era.append(t)
		if era.is_empty() or p.house.year < era[0][1] or p.house.year > era[0][2]:
			bad_years += 1
		# No two buildings stand on each other.
		var rects := [Rect2(p.house.x - p.house.w * 0.5, -2.5, p.house.w, p.house.d + 6.0)]
		for part in p.parts:
			if part.kind in ["dryer", "windmill", "feed_bin", "milk_house"]:
				continue
			var r := FarmsteadPlan._extent(part).grow(-0.3)
			for o: Rect2 in rects:
				if r.intersects(o):
					overlaps += 1
			rects.append(r)
		# Shade trees keep their crowns off the house, buildings and gravel.
		for t in p.trees:
			if t.size() > 4:
				continue
			for o: Rect2 in rects + p.gravel:
				if o.has_point(t[0]):
					bad_trees += 1
		# Bins: round steel, 18 to 48 ft across, eaves 16 to 38 ft.
		var store := 0.0
		for part in p.parts:
			if part.kind == "bin":
				var d: float = part.r * 2.0 / FarmsteadPlan.FT
				var h: float = part.h / FarmsteadPlan.FT
				if d < 17.9 or d > 48.1 or h < 15.9 or h > 38.1:
					bad_bins += 1
				store += 0.628 * d * d * h
		if p.kind == "grain":
			grain += 1
			# Enough for at least a third of a year's crop (118 bu an acre).
			if store < p.acres * 118.0 * 0.33:
				short_store += 1
		# The windbreak stands on the north or west of the yard.
		var wb: Array = p.trees.filter(func(t): return t.size() > 4)
		if not wb.is_empty():
			windbreaks += 1
			var c := Vector2.ZERO
			for t in wb:
				c += FarmsteadPlan.to_region(p, t[0])
			c /= wb.size()
			var mid := FarmsteadPlan.to_region(p, (p.extent as Rect2).get_center())
			var off := (c - mid).normalized()
			if off.dot(Vector2(0, -1)) > 0.2 or off.dot(Vector2(-1, 0)) > 0.2:
				windward += 1
			elif windbreaks - windward < 5:
				print("leeward windbreak: ", p.kind, " facing ", rad_to_deg(p.facing), " off ", off, " trees ", wb.size())
		# The lane runs from the road to the yard; the mailbox stands at the road.
		if p.lane < 24.0 or absf(p.mailbox.y + p.lane - 4.5) > 0.01:
			lanes_ok = false
		# Nothing of it lies past FarmsteadPlan.REACH (the searches rely on it).
		reach = maxf(reach, FarmsteadPlan._solid(p)[3] + 4.0)
		var g: Rect2 = (p.grounds as Rect2).grow(4.0)
		for c in [g.position, g.end, Vector2(g.position.x, g.end.y), Vector2(g.end.x, g.position.y)]:
			reach = maxf(reach, c.length())
	print("kinds ", kinds, "  houses ", houses)
	var farms: int = places.size() - kinds.get("home", 0)
	_check(kinds.get("grain", 0) > farms * 0.3 and kinds.get("grain", 0) < farms * 0.45,
		"about a third of farmsteads farm grain themselves (%d of %d)" % [kinds.get("grain", 0), farms])
	_check(kinds.get("dairy", 0) < farms * 0.03, "dairies are rare (%d)" % kinds.get("dairy", 0))
	_check(kinds.get("hog", 0) > farms * 0.04 and kinds.get("hog", 0) < farms * 0.12, "some hog farms (%d)" % kinds.get("hog", 0))
	_check(houses.has("i_house") and houses.has("foursquare") and houses.has("ranch") and houses.has("farmhouse"),
		"I-houses, foursquares, ell farmhouses and ranches all stand")
	_check(bad_years == 0, "every house is of a type built in its year (%d not)" % bad_years)
	_check(overlaps == 0, "no building stands on another (%d overlaps)" % overlaps)
	_check(bad_trees == 0, "shade trees keep off the buildings and gravel (%d on them)" % bad_trees)
	_check(bad_bins == 0, "bins are 18-48 ft across and 16-38 ft to the eave (%d not)" % bad_bins)
	_check(short_store == 0, "grain farms have bins for a third of a year's crop or more (%d of %d short)" % [short_store, grain])
	_check(windbreaks > places.size() * 0.3 and windward == windbreaks,
		"windbreaks stand on the north or west (%d of %d)" % [windward, windbreaks])
	_check(lanes_ok, "every lane reaches the road, the mailbox at its end")
	_check(reach <= FarmsteadPlan.REACH, "no farmstead reaches past FarmsteadPlan.REACH (%.0f of %.0f m)" % [reach, FarmsteadPlan.REACH])
	_pinned(places, plans, kinds)

	# Crops and wild trees keep off the yards, and only the yards of farmsteads
	# that are drawn.
	await _yards(places, plans)

	# The far drawing: all of a block's farmsteads in one indexed mesh.
	var far := FarmsteadFar.new()
	var ms := 1e9
	for pass_i in 3:
		far = FarmsteadFar.new()
		var t0 := Time.get_ticks_usec()
		for i in 40:
			far.add(plans[i], Vector2.ZERO)
		# The fastest of three passes: a loaded runner slows some passes, not all.
		ms = minf(ms, (Time.get_ticks_usec() - t0) / 1000.0 / 40.0)
	var mesh := far.commit()
	var top := 0
	for i in far.idx:
		top = maxi(top, i)
	_check(mesh != null and top < far.v.size() and far.idx.size() % 3 == 0, "the far mesh is whole (%d vertices)" % far.v.size())
	_check(far.v.size() / 40 < 900, "a far farmstead is a few hundred vertices (%d)" % (far.v.size() / 40))
	_check(ms < 25.0, "a far farmstead takes a fraction of a frame to grow (%.2f ms at best of 3)" % ms)
	# Gravel and lawn are faces of their own kind, for the handover.
	var gravel := 0
	var lawn := 0
	for c in far.col:
		if is_equal_approx(c.a, FarmsteadFar.GRAVEL_ALPHA):
			gravel += 1
		if is_equal_approx(c.a, FarmsteadFar.LAWN_ALPHA):
			lawn += 1
	_check(gravel > 0 and lawn > 0, "the far gravel and lawn are marked for the handover (%d, %d vertices)" % [gravel, lawn])
	# The same farmsteads a step at a time (what the view does), and the browser's lighter ones.
	var stepped := FarmsteadFar.new()
	for i in 40:
		var n := stepped.begin(plans[i], Vector2.ZERO)
		for k in n:
			stepped.step(k)
	_check(stepped.v.size() == far.v.size() and stepped.idx.size() == far.idx.size(), "drawn a step at a time it is the same mesh")
	var light := FarmsteadFar.new(true)
	for i in 40:
		light.add(plans[i], Vector2.ZERO)
	var light_mesh := light.commit()
	var light_top := 0
	for i in light.idx:
		light_top = maxi(light_top, i)
	_check(light_mesh != null and light_top < light.v.size() and light.idx.size() % 3 == 0, "the browser's far mesh is whole (%d vertices)" % light.v.size())
	_check(light.v.size() < far.v.size() * 0.9, "and lighter (%d against %d vertices)" % [light.v.size(), far.v.size()])

	# The close-up, a step at a time, for each kind.
	var done := {}
	for p in plans:
		var kind: String = p.kind
		if done.has(kind) and done.size() < 5:
			continue
		if done.size() >= 5:
			break
		# Built three times; the least of the three slowest steps counts (a loaded runner stalls one pass).
		var meshes: Array
		for pass_i in 3:
			var builder := FarmBuilder.county(p)
			var slowest := 0.0
			for i in builder.steps():
				var t := Time.get_ticks_usec()
				builder.step(i)
				slowest = maxf(slowest, (Time.get_ticks_usec() - t) / 1000.0)
			meshes = builder.commit()
			if pass_i == 0:
				_pass_worst = slowest
			else:
				_pass_worst = minf(_pass_worst, slowest)
		_worst = maxf(_worst, _pass_worst)
		done[kind] = (meshes[0] as ArrayMesh).get_surface_count() > 0 and (meshes[1] as ArrayMesh).get_surface_count() > 0
	_check(done.size() == 5 and done.values().all(func(x): return x), "a close-up grows for every kind %s" % done)
	_check(_worst < 80.0, "no close-up step freezes a frame (slowest step %.1f ms, best of 3)" % _worst)
	_check(HouseBuilder.owner_care == 0 and HouseBuilder.force_kind == "", "the close-up leaves the house builder as it found it")

	# The town's own farms still build as before.
	var town := FarmBuilder.build_farmstead(7, 3, ["grain_bins", "dryer"])
	_check((town[0] as ArrayMesh).get_surface_count() > 0, "the town's farmsteads still build")

	# The far shader's slots: set only when they change.
	_spots()
	# The near/far handover: swap, slots, origin shift, the browser's smaller one.
	await _handover(plans)
	# The view: nearest blocks first, not all of them, an origin shift.
	await _view(plans)
	quit(1 if _failed else 0)


var _pass_worst := 0.0
var _worst := 0.0


## Same facts, same farmstead, on every computer: values pinned from a run
## (a change to the rules should change them on purpose, here).
func _pinned(places: Array, plans: Array, kinds: Dictionary) -> void:
	# [index, kind, house type, house year, parts, trees, acres, windbreak, first tree x, y]
	var pins := [
		[10, "grain", "farmhouse", 1907, 14, 134, 3370, "SPRUCE", 24.36, 6.18],
		[100, "grain", "ranch", 1974, 6, 35, 450, "SPRUCE", 22.12, 4.38],
		[1000, "home", "ranch", 1953, 0, 32, 0, "SPRUCE", -23.58, 0.65],
		[2500, "home", "colonial", 1995, 1, 1, 0, "", 12.28, 23.66],
		[4000, "hog", "ranch", 1961, 11, 76, 210, "RED_CEDAR", 46.37, 4.39],
		[5000, "home", "ranch", 1975, 0, 23, 0, "RED_CEDAR", -22.88, -6.81]]
	var bad := []
	for pin in pins:
		var p: Dictionary = plans[pin[0]]
		var t0: Vector2 = p.trees[0][0]
		var got := [pin[0], p.kind, p.house.type, p.house.year, p.parts.size(), p.trees.size(), p.acres, p.windbreak]
		if got != pin.slice(0, 8) or absf(t0.x - pin[8]) > 0.01 or absf(t0.y - pin[9]) > 0.01:
			bad.append("%s (got %s, first tree %s)" % [pin, got, t0])
	_check(bad.is_empty(), "farmsteads grow the same on every computer (pinned values) %s" % str(bad))
	var parts := 0
	var trees := 0
	for p in plans:
		parts += p.parts.size()
		trees += p.trees.size()
	_check(kinds == {"home": 3406, "hog": 129, "grain": 626, "retired": 926, "dairy": 11} and parts == 12257 and trees == 121780,  # 696 fewer since windbreaks keep out of ponds
		"and so do all %d together (%s, %d buildings, %d trees)" % [places.size(), kinds, parts, trees])
	_check(CropCalendar.hash32(0, 0, 0) == 946720379 and CropCalendar.hash32(123, -456, 789) == 1989847715,
		"the hash behind them is the crops' own")
	# The windbreak pick is the plan's own roll, whatever the trees code has drawn.
	var names := {}
	for p in plans:
		names[p.windbreak] = true
	_check(names.keys().all(func(n): return n == "" or n in FarmsteadPlan.WINDBREAK_TREES) and names.size() == 3,
		"windbreak trees come from the fixed list %s" % [names.keys()])


## Crops and wild trees: what they keep off.
func _yards(places: Array, plans: Array) -> void:
	var g: Dictionary = plans[0]
	for p in plans:
		if p.kind == "grain":
			g = p
			break
	var yard := FarmsteadPlan.to_region(g, (g.extent as Rect2).get_center())
	_check(FarmsteadPlan.covers(yard), "crops keep off a farmstead's yard")
	# covers agrees with the plans themselves, inside and just outside the
	# grounds, on 300 farmsteads (every 17th) and a point 30 m past each.
	var wrong := 0
	var inside := 0
	var outside := 0
	for i in range(0, plans.size(), 17):
		var p: Dictionary = plans[i]
		var gr: Rect2 = p.grounds
		for q in [gr.get_center(), gr.position + Vector2(2.0, 2.0), Vector2(gr.end.x + 2.0, gr.get_center().y),
				Vector2(gr.end.x + 30.0, gr.get_center().y), Vector2(gr.position.x - 30.0, gr.end.y + 30.0)]:
			var r := FarmsteadPlan.to_region(p, q)
			var want := _brute_covers(plans, r)
			if want:
				inside += 1
			else:
				outside += 1
			if FarmsteadPlan.covers(r) != want:
				wrong += 1
	_check(wrong == 0 and inside > 200 and outside > 200, "crops keep off exactly the farmsteads' grounds (%d wrong of %d inside, %d outside)" % [wrong, inside, outside])
	# Far from every farmstead is field.
	var field := Vector2(-1e5, -1e5)
	_check(not FarmsteadPlan.covers(field), "and grow in the fields beyond")
	# An isolated farmstead that is not drawn (the town has built over it, or it
	# is in water) takes nothing from the crops or the wild trees.
	var iso: Dictionary = {}
	for p in plans:
		if p.kind == "grain" and _isolated(plans, p):
			iso = p
			break
	var key := FarmsteadPlan.key_of(iso)
	var lawn_pt := FarmsteadPlan.to_region(iso, (iso.grounds as Rect2).position + Vector2(1.5, 1.5))
	var box := Rect2(lawn_pt - Vector2(128, 128), Vector2(256, 256))
	_check(FarmsteadPlan.covers(lawn_pt) and FarmsteadPlan.on_solid(FarmsteadPlan.solids_in(box), lawn_pt),
		"crops and wild trees keep off a drawn farmstead's lawn")
	FarmsteadPlan.hidden[key] = true
	_check(not FarmsteadPlan.covers(lawn_pt) and not FarmsteadPlan.on_solid(FarmsteadPlan.solids_in(box), lawn_pt),
		"and take it back when the farmstead is not drawn")
	FarmsteadPlan.hidden.erase(key)
	_check(FarmsteadPlan.covers(lawn_pt), "and again when it is")
	var wet_plan := {}
	for p in plans:
		if FarmsteadPlan.wet(p):
			wet_plan = p
			break
	if wet_plan.is_empty():
		print("no farmstead stands in water on this map")
	else:
		var wp := FarmsteadPlan.to_region(wet_plan, (wet_plan.extent as Rect2).get_center())
		_check(FarmsteadPlan.covers(wp) == _brute_covers(plans, wp) and not _brute_covers([wet_plan], wp) ,
			"a farmstead in water takes no ground from the crops")
	# Wild trees stay off the buildings, the gravel and the lawn.
	var solids := FarmsteadPlan.solids_in(Rect2(yard - Vector2(128, 128), Vector2(256, 256)))
	var bin_at := Vector2.ZERO
	for part in g.parts:
		if part.kind == "bin":
			bin_at = FarmsteadPlan.to_region(g, part.pos)
	_check(bin_at == Vector2.ZERO or FarmsteadPlan.on_solid(solids, bin_at), "no wild tree grows in a grain bin")
	var yard_pt := FarmsteadPlan.to_region(g, Vector2((g.gravel[0] as Rect2).get_center()))
	_check(FarmsteadPlan.on_solid(solids, yard_pt), "nor in the gravel yard")
	# Asking about trees (solids_in) does not grow the crops' yard entries.
	var yards_before: int = FarmsteadPlan._yards.size()
	FarmsteadPlan.solids_in(Rect2(Vector2(-31000, 20000), Vector2(256, 256)))
	_check(FarmsteadPlan._yards.size() == yards_before, "asking for solid ground adds nothing to the crops' yard list")
	# The plan cache keeps to its size, drops the oldest, and keeps the ones in use.
	var keep: Dictionary = plans[3]
	FarmsteadPlan.of(keep.at, true, keep.facing, keep.seed)
	FarmsteadPlan.pinned = {FarmsteadPlan.key_of(keep): true}
	for i in 700:
		var p: Dictionary = plans[10 + i]
		FarmsteadPlan.of(p.at, p.kind != "home", p.facing, p.seed)
	_check(FarmsteadPlan._cache.size() <= FarmsteadPlan.CACHE_MAX, "the plan cache keeps to its size (%d)" % FarmsteadPlan._cache.size())
	_check(FarmsteadPlan._cache.has(FarmsteadPlan.key_of(keep)), "and keeps a plan a close-up is using")
	var newest: Dictionary = plans[10 + 699]
	_check(FarmsteadPlan._cache.has(FarmsteadPlan.key_of(newest)), "and the newest")
	_check(not FarmsteadPlan._cache.has(FarmsteadPlan.key_of(plans[10])), "but not the oldest")
	FarmsteadPlan.pinned = {}
	await process_frame


func _brute_covers(plans: Array, r: Vector2) -> bool:
	for p in plans:
		if (p.at as Vector2).distance_to(r) > 400.0:
			continue
		if FarmsteadPlan.hidden.has(FarmsteadPlan.key_of(p)) or FarmsteadPlan.wet(p):
			continue
		var f := Vector2(cos(p.facing), sin(p.facing))
		var d: Vector2 = r - p.at
		if (p.grounds as Rect2).grow(4.0).has_point(Vector2(d.dot(Vector2(-f.y, f.x)), -d.dot(f))):
			return true
	return false


func _isolated(plans: Array, p: Dictionary) -> bool:
	for o in plans:
		if o != p and (o.at as Vector2).distance_to(p.at) < 600.0:
			return false
	return not FarmsteadPlan.wet(p)


## The far shader's slots are set only when they change.
func _spots() -> void:
	var a := [Vector4(10, 20, 0.5, 0.0)]
	FarmsteadFar.set_spots(a)
	_check(FarmsteadFar.material().get_shader_parameter("near_spots").size() == FarmsteadFar.SPOTS, "the far shader gets all its slots")
	FarmsteadFar.material().set_shader_parameter("near_spots", ["marker"])
	FarmsteadFar.set_spots([Vector4(10, 20, 0.5, 0.0)])
	_check(FarmsteadFar.material().get_shader_parameter("near_spots") == ["marker"], "the same spots are not set again")
	FarmsteadFar.set_spots([Vector4(10, 20, 0.6, 0.0)])
	_check(FarmsteadFar.material().get_shader_parameter("near_spots").size() == FarmsteadFar.SPOTS, "changed spots are")
	var many := []
	for i in 40:
		many.append(Vector4(i, i, 0.0, 0.0))
	FarmsteadFar.set_spots(many)
	_check(FarmsteadFar.spots().size() == FarmsteadFar.SPOTS, "never more spots than slots")
	FarmsteadFar.clear_spots()
	_check(FarmsteadFar.spots().is_empty(), "and they clear")


## A plan like `base`, standing `dx` metres along x, as its own farmstead.
func _copy(base: Dictionary, i: int, dx: float) -> Dictionary:
	var p: Dictionary = base.duplicate(true)
	p.at = base.at + Vector2(dx, 0.0)
	p.seed = i
	return p


func _anchor(p: Dictionary, origin: Vector2) -> Vector3:
	var a: Vector2 = p.at - origin
	return Vector3(a.x, Terrain.height(p.at.x, p.at.y), a.y)


## The close-up and the far version handing over to each other.
func _handover(plans: Array) -> void:
	var base: Dictionary = plans[0]
	for p in plans:
		if p.kind == "grain" and p.trees.size() > 40 and p.parts.size() > 8:
			base = p
			break
	var near := FarmsteadNear.new()
	root.add_child(near)
	await process_frame
	var origin := Vector2.ZERO
	var anchor := _anchor(base, origin)
	var cam := anchor + Vector3(40, 30, 60)
	var key := Vector2i(int(base.at.x), int(base.at.y))
	# Swap in: the trees and the buildings come, the far version fades out.
	var steps := 0
	while steps < 600 and not (near._built.has(key) and near._built[key].fade >= 1.0 and near._trees.has(key) and near._trees[key].fade >= 1.0):
		near.update(cam, [[base, anchor]], origin, 0.05)
		steps += 1
	var spots := FarmsteadFar.spots()
	_check(near._built.has(key) and spots.size() == 1 and spots[0].z >= 1.0 and spots[0].w >= 1.0,
		"the close-up stands and the far farmstead is wholly handed over (%d frames)" % steps)
	_check(is_equal_approx(spots[0].x, base.at.x - origin.x) and is_equal_approx(spots[0].y, base.at.y - origin.y),
		"at the farmstead's own place")
	_check(FarmsteadPlan.pinned.has(FarmsteadPlan.key_of(base)), "the plan in use is kept")
	# Near trees are turned and tinted from the farmstead's own coordinates, as the far ones are.
	var list: Array = near._field._trees[str(key)]
	var t0: Array = base.trees[0]
	var xf: Transform3D = list[0][0]
	var yaw := FarmsteadPlan.tree_turn(t0[0])
	var want_x := Vector3(cos(yaw), 0.0, -sin(yaw))
	var tint_ok: bool = (list[0][2] as Color).is_equal_approx(FarmsteadPlan.tree_tint(TreeField.LEAF[t0[1]] if t0[1] < TreeField.LEAF.size() else TreeField.LEAF[0], t0[0]))
	_check(xf.basis.x.normalized().is_equal_approx(want_x) and tint_ok, "near trees are turned and tinted as the far ones are")
	# Swap out: the camera leaves; the close-up goes and the far version is whole again.
	var gone := anchor + Vector3(3000, 30, 0)
	steps = 0
	while steps < 200 and not (near._built.is_empty() and near._trees.is_empty()):
		near.update(gone, [], origin, 0.05)
		steps += 1
	_check(near._built.is_empty() and near._trees.is_empty() and FarmsteadFar.spots().is_empty(),
		"when the camera leaves, the close-up goes the same frame its far version is whole again")
	# An origin shift: everything is let go and handed over afresh, at the new place.
	near.update(cam, [[base, anchor]], origin, 0.05)
	var shifted := Vector2(2048.0, -2048.0)
	var anchor2 := _anchor(base, shifted)
	near.update(anchor2 + Vector3(40, 30, 60), [[base, anchor2]], shifted, 0.05)
	var sp := FarmsteadFar.spots()
	_check(near._origin == shifted and sp.size() == 1 and is_equal_approx(sp[0].x, base.at.x - shifted.x) and sp[0].w < 0.5,
		"after an origin shift the farmstead is handed over afresh at its new place")
	var moved: Array = near._field._trees[str(key)]
	var r := FarmsteadPlan.to_region(base, t0[0])
	_check(((moved[0][0] as Transform3D).origin - Vector3(r.x - shifted.x, Terrain.height(r.x, r.y), r.y - shifted.y)).length() < 0.01,
		"and its trees stand where they should")
	# Crowded: more farmsteads than slots, the camera moving along them, so
	# close-ups come and go. Never more than the shader has slots for, never a
	# close-up without its slot, and the nearest always has one.
	var ground := Terrain.height(base.at.x, base.at.y)
	var row := []
	for i in 30:
		row.append(_copy(base, i + 1, i * 22.0))
	var max_used := 0
	var bad := 0
	var nearest_missing := 0
	var built_max := 0
	for step in 160:
		var cx := fposmod(step * 33.0, 1100.0)
		if cx > 550.0:
			cx = 1100.0 - cx
		var camx := Vector3(base.at.x - shifted.x + cx, ground + 30.0, base.at.y - shifted.y + 40.0)
		var places := []
		for p in row:
			places.append([p, _anchor(p, shifted)])
		near.update(camx, places, shifted, 0.1)
		var spots2 := FarmsteadFar.spots()
		var keys: Dictionary = near._keys()
		max_used = maxi(max_used, spots2.size())
		built_max = maxi(built_max, near._built.size())
		if spots2.size() > FarmsteadFar.SPOTS or spots2.size() != keys.size():
			bad += 1
		for k in keys:
			var found := false
			for sv in spots2:
				if is_equal_approx(sv.x, near._plan_of(k).at.x - shifted.x):
					found = true
			if not found:
				bad += 1
		# The farmstead nearest the camera holds a slot.
		var best_d := INF
		var best: Dictionary = row[0]
		for p in row:
			var d := Vector2(camx.x, camx.z).distance_to(p.at - shifted)
			if d < best_d:
				best_d = d
				best = p
		if best_d < FarmsteadNear.TREE_R and not keys.has(Vector2i(int(best.at.x), int(best.at.y))):
			nearest_missing += 1
	_check(bad == 0, "close-ups and far slots always agree, never past %d (%d wrong)" % [FarmsteadFar.SPOTS, bad])
	_check(max_used == FarmsteadFar.SPOTS, "the crowded run did fill every slot (%d used)" % max_used)
	_check(nearest_missing == 0, "the nearest farmstead always holds a slot (%d frames without)" % nearest_missing)
	_check(built_max <= FarmsteadNear.MAX_BUILT, "only a few are built at once (%d)" % built_max)
	# The browser: fewer and nearer close-ups.
	var desktop_reach := FarmsteadNear.reach_scale()
	FarmsteadFar.force_web = true
	_check(FarmsteadNear.reach_scale() < desktop_reach * 0.7 and FarmsteadView.draw_to() < FarmsteadView.DRAW_TO,
		"the browser's close-ups reach less far (%.2f against %.2f)" % [FarmsteadNear.reach_scale(), desktop_reach])
	built_max = 0
	for step in 120:
		var camx := Vector3(base.at.x - shifted.x + 100.0, ground + 30.0, base.at.y - shifted.y + 40.0)
		var places := []
		for p in row:
			places.append([p, _anchor(p, shifted)])
		near.update(camx, places, shifted, 0.1)
		built_max = maxi(built_max, near._built.size())
	_check(built_max >= 1 and built_max <= FarmsteadNear.MAX_BUILT_WEB, "and at most %d are built (%d)" % [FarmsteadNear.MAX_BUILT_WEB, built_max])
	FarmsteadFar.force_web = false
	# Freed, the near view leaves the shared far material with nothing handed over.
	near.queue_free()
	await process_frame
	await process_frame
	_check(FarmsteadFar.spots().is_empty() and FarmsteadPlan.pinned.is_empty(), "a freed view leaves no farmstead handed over")


## The view builds the nearest blocks first, not the whole county, and
## starts over at an origin shift; in the browser too.
func _view(plans: Array) -> void:
	for web in [false, true]:
		FarmsteadFar.force_web = web
		var base: Dictionary = plans[200]
		Terrain.view_origin = Vector2.ZERO
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.current = true
		cam.global_position = Vector3(base.at.x, 400.0, base.at.y)
		var view := FarmsteadView.new()
		root.add_child(view)
		view.setup(null)
		var total := view._places.size()
		var frames := 0
		while frames < 4000 and not (frames > 2 and view._queue.is_empty() and view._job.is_empty()):
			view._process(0.016)
			frames += 1
		var home := FarmsteadView._block(base.at)
		var reach := FarmsteadView.draw_to() + FarmsteadView.BLOCK * 0.75
		var far_built := 0
		for b in view._shown:
			if sqrt(FarmsteadView._dist(b, base.at)) > reach:
				far_built += 1
		_check(view._shown.has(home) and view.blocks_built > 0 and view.blocks_built < total and far_built == 0,
			"%s: the view builds the blocks near the camera, not the whole county (%d of %d blocks)" % ["browser" if web else "desktop", view.blocks_built, total])
		_check(view.worst_frame_ms < 400.0, "no frame spent long on the farmsteads (%.1f ms)" % view.worst_frame_ms)
		# Fly to the farthest farmstead in the county: the blocks round the first
		# spot are let go, those round the new one built.
		var farthest: Dictionary = base
		for p in plans:
			if (p.at as Vector2).distance_to(base.at) > (farthest.at as Vector2).distance_to(base.at):
				farthest = p
		var before := view.blocks_built
		cam.global_position = Vector3(farthest.at.x, 400.0, farthest.at.y)
		frames = 0
		while frames < 4000 and not (frames > 2 and view._queue.is_empty() and view._job.is_empty()):
			view._process(0.016)
			frames += 1
		var gone := (farthest.at as Vector2).distance_to(base.at) > FarmsteadView.draw_to() + FarmsteadView.BLOCK * 2.75
		_check(view.blocks_built > before and view._shown.has(FarmsteadView._block(farthest.at)) and (not gone or not view._shown.has(home)),
			"flying on, the new blocks are built and the old ones let go (%.0f km apart)" % ((farthest.at as Vector2).distance_to(base.at) / 1000.0))
		# Back again, then an origin shift: the blocks start over, where they now stand.
		cam.global_position = Vector3(base.at.x, 400.0, base.at.y)
		frames = 0
		while frames < 4000 and not (frames > 2 and view._queue.is_empty() and view._job.is_empty()):
			view._process(0.016)
			frames += 1
		var built_before := view._shown.size()
		Terrain.view_origin = Vector2(1024.0, 1024.0)
		cam.global_position = Vector3(base.at.x - 1024.0, 400.0, base.at.y - 1024.0)
		view._process(0.016)
		_check(view._origin == Vector2(1024.0, 1024.0) and view._shown.size() < built_before and not view._queue.is_empty(),
			"an origin shift starts the blocks over")
		frames = 0
		while frames < 4000 and not (frames > 2 and view._queue.is_empty() and view._job.is_empty()):
			view._process(0.016)
			frames += 1
		var mesh_ok := true
		for b in view._meshes:
			var centre: Vector2 = (Vector2(b) + Vector2(0.5, 0.5)) * FarmsteadView.BLOCK - view._origin
			if (view._meshes[b].position as Vector3).distance_to(Vector3(centre.x, 0.0, centre.y)) > 0.01:
				mesh_ok = false
		_check(mesh_ok and view._shown.has(home), "and they stand at their new places")
		view.queue_free()
		cam.queue_free()
		Terrain.view_origin = Vector2.ZERO
		await process_frame
	FarmsteadFar.force_web = false


func _places() -> Array:
	var out := []
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	if data.size() < 8:
		return out
	for i in data.decode_u32(4):
		var at := 8 + i * 7
		out.append([Vector2(data.decode_s16(at), data.decode_s16(at + 2)), data.decode_u8(at + 4) == 1,
			data.decode_u8(at + 5) / 256.0 * TAU, data.decode_u8(at + 6)])
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
