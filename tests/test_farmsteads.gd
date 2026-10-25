extends SceneTree
## Run: godot --headless -s tests/test_farmsteads.gd
## County farmsteads (FarmsteadPlan, FarmsteadFar, FarmBuilder's close-up):
## grown the same on every computer from their few facts, laid out the
## way real east-central Indiana farmsteads are (docs/farmsteads.md), and
## cheap enough to build a step a frame.

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

	# Crops and wild trees keep off the yards.
	var g: Dictionary = plans[0]
	for p in plans:
		if p.kind == "grain":
			g = p
			break
	var yard := FarmsteadPlan.to_region(g, (g.extent as Rect2).get_center())
	_check(FarmsteadPlan.covers(yard), "crops keep off a farmstead's yard")
	_check(not FarmsteadPlan.covers(yard + Vector2(700, 700)) or _any_near(places, yard + Vector2(700, 700)),
		"and grow in the fields beyond it")
	var solids := FarmsteadPlan.solids_in(Rect2(yard - Vector2(128, 128), Vector2(256, 256)))
	var bin_at := Vector2.ZERO
	for part in g.parts:
		if part.kind == "bin":
			bin_at = FarmsteadPlan.to_region(g, part.pos)
	_check(bin_at == Vector2.ZERO or FarmsteadPlan.on_solid(solids, bin_at), "no wild tree grows in a grain bin")

	# The far drawing: all of a block's farmsteads in one indexed mesh.
	var far := FarmsteadFar.new()
	var t0 := Time.get_ticks_usec()
	for i in 40:
		far.add(plans[i], Vector2.ZERO)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 40.0
	var mesh := far.commit()
	var top := 0
	for i in far.idx:
		top = maxi(top, i)
	_check(mesh != null and top < far.v.size() and far.idx.size() % 3 == 0, "the far mesh is whole (%d vertices)" % far.v.size())
	_check(far.v.size() / 40 < 900, "a far farmstead is a few hundred vertices (%d)" % (far.v.size() / 40))
	_check(ms < 5.0, "a far farmstead takes a fraction of a ms to grow (%.2f ms)" % ms)

	# The close-up, a step at a time, for each kind.
	var done := {}
	var worst := 0.0
	for p in plans:
		var kind: String = p.kind
		if done.has(kind) and done.size() < 5:
			continue
		if done.size() >= 5:
			break
		var builder := FarmBuilder.county(p)
		for i in builder.steps():
			var t := Time.get_ticks_usec()
			builder.step(i)
			worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
		var meshes := builder.commit()
		done[kind] = (meshes[0] as ArrayMesh).get_surface_count() > 0 and (meshes[1] as ArrayMesh).get_surface_count() > 0
	_check(done.size() == 5 and done.values().all(func(x): return x), "a close-up grows for every kind %s" % done)
	_check(worst < 40.0, "no close-up step freezes a frame (worst %.1f ms)" % worst)
	_check(HouseBuilder.owner_care == 0 and HouseBuilder.force_kind == "", "the close-up leaves the house builder as it found it")

	# The town's own farms still build as before.
	var town := FarmBuilder.build_farmstead(7, 3, ["grain_bins", "dryer"])
	_check((town[0] as ArrayMesh).get_surface_count() > 0, "the town's farmsteads still build")
	quit(1 if _failed else 0)


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


func _any_near(places: Array, r: Vector2) -> bool:
	for pl in places:
		if (pl[0] as Vector2).distance_to(r) < 450.0:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
