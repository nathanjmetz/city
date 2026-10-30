extends SceneTree
## House lots: yard trees stand clear of the house, the traffic sim parks
## cars on the drive the art paints, and homes built on a wooded hillside
## clear their lots and meet the ground.
## Run: godot --headless -s tests/test_house_lots.gd


func _init() -> void:
	var lots := []
	for i in 160:
		lots.append({"width": [14.0, 16.5, 19.0, 21.0, 24.0][i % 5], "depth": [30.0, 36.0, 44.0][i % 3],
			"at": Vector2((i % 16) * 90.0, (i / 16) * 130.0)})

	# A shade tree's crown never passes through a wall (Brawn saw a maple
	# planted in a front window).
	var bad := []
	var trees := 0
	for i in lots.size():
		var b := HouseBuilder.new()
		b.rng = RandomNumberGenerator.new()
		b.rng.seed = i * 7919 + 13
		b._fit(lots[i])
		var built: Array = b._house(6.0, [0, 1, 2][i % 3])
		for t in built[2]:
			var p: Vector3 = t[0]
			if p.z <= 0.0:
				continue  # street trees, in the parkway
			trees += 1
			var need: float = TreeField.SPREAD[t[1]] * t[3] * 0.9
			if b._wall_gap(p) < need - 0.01:
				bad.append("lot %d: %s %.1f m from the house, crown %.1f m" % [i, TreeField.Species.keys()[t[1]], b._wall_gap(p), need])
	_check(trees > 100 and bad.is_empty(), "yard trees keep their crowns off the walls (%d trees) %s" % [trees, bad.slice(0, 3)])
	_grown_yards(lots)

	# The foundation and far-off blocks cover the house and garage, not the
	# whole lot out to the back-yard fences (critic round 25: concrete slabs
	# across yards on sloping lots).
	var slabs := []
	for i in lots.size():
		var built: Array = HouseBuilder.build(i * 31 + 7, 6.0, lots[i], 0)
		var area := 0.0
		if not HouseBuilder.last_masses.is_empty():
			var box: Rect2 = HouseBuilder.last_masses[0]
			for m: Rect2 in HouseBuilder.last_masses:
				box = box.merge(m)
			area = box.get_area()
		if HouseBuilder.last_masses.is_empty() or area > lots[i].width * lots[i].depth * 0.6:
			slabs.append("lot %d: %.0f of %.0f m2" % [i, area, lots[i].width * lots[i].depth])
	_check(slabs.is_empty(), "foundations stay under the house %s" % [slabs.slice(0, 3)])

	# From afar a house is its own walls, roof and windows in its own
	# colours, a few hundred triangles at most, never a blank block.
	var poor := []
	for i in lots.size():
		var built: Array = HouseBuilder.build(i * 31 + 7, 6.0, lots[i], 0)
		var far := BuildingView.far_version(built[0], HouseBuilder.last_masses, false, Color.WHITE, Color.GRAY, built[1])
		var tris := far.surface_get_array_index_len(0) / 3
		var cols: PackedColorArray = far.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var shades := {}
		for c in cols:
			shades[c.to_html(false)] = true
		var box := far.get_aabb()
		if tris < 30 or tris > 600 or shades.size() < 3 or box.size.y < 3.0:
			poor.append("lot %d: %d tris, %d colours, %.1f m tall" % [i, tris, shades.size(), box.size.y])
	_check(poor.is_empty(), "far-off houses keep their walls, roofs and windows %s" % [poor.slice(0, 3)])

	# The traffic sim lays a plan out without drawing it: the drive, garage
	# and door come out exactly as when the plan is drawn.
	var differ := []
	for i in lots.size():
		var seed := i * 104729 + 5
		HouseBuilder._plans.clear()
		HouseBuilder._infos.clear()
		var dry: Dictionary = HouseBuilder.plan_info(seed, lots[i], 0)
		HouseBuilder.build(seed, 6.0, lots[i], 0)
		HouseBuilder._infos.clear()
		var drawn: Dictionary = HouseBuilder.plan_info(seed, lots[i], 0)
		if str(dry) != str(drawn):
			differ.append("lot %d" % i)
	_check(differ.is_empty(), "a plan laid out without drawing matches the drawn one %s" % [differ.slice(0, 3)])

	# A plan is drawn once per shape and each lot paints, mirrors and
	# weathers it: every upkeep tier of every lot needs few drawings, no
	# lot shows the stand-in paint, and mirrored houses face out.
	HouseBuilder._plans.clear()
	var was_drawn := HouseBuilder.drawn
	var leaks := []
	var inside := []
	var builds := 0
	for i in lots.size():
		for care in [-2, -1, 0, 1, 2]:
			HouseBuilder.owner_care = care
			var built: Array = HouseBuilder.build(i * 131, 6.0, lots[i], 0)
			builds += 1
			var mesh: ArrayMesh = built[0]
			for s in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(s)
				for c: Color in a[Mesh.ARRAY_COLOR]:
					if c.g == HouseBuilder.STAND_IN.siding.g and c.b == HouseBuilder.STAND_IN.siding.b:
						leaks.append("lot %d care %d" % [i, care])
						break
				if not _faces_out(a):
					inside.append("lot %d care %d surface %d" % [i, care, s])
	HouseBuilder.owner_care = 0
	var drawings := HouseBuilder.drawn - was_drawn
	_check(drawings <= lots.size(), "%d houses in every upkeep need only %d drawings" % [builds, drawings])
	_check(leaks.is_empty(), "every lot is painted in its own scheme %s" % [leaks.slice(0, 3)])
	_check(inside.is_empty(), "mirrored and unmirrored houses face out %s" % [inside.slice(0, 3)])

	# A builder reads the lot before siting the house (Brawn saw homes
	# built past the lines of small and angled lots): on a skewed, tapering
	# or pie-shaped lot the house keeps its side yards inside the lot lines,
	# square to the street, and the drive the cars use is still the painted one.
	var odd := []
	var odd_lots := []
	for i in 60:
		var w: float = [16.0, 18.0, 20.0, 24.0][i % 4]
		var d: float = [30.0, 36.0, 42.0][i % 3]
		var poly: PackedVector2Array
		match i % 3:
			0:  # a skewed crossing: side lines at 30 degrees (and as wide
				# across as a plain lot)
				w /= cos(deg_to_rad(30.0))
				var k: float = d * tan(deg_to_rad(30.0)) * (1.0 if i % 2 == 0 else -1.0)
				poly = PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2 + k, d), Vector2(-w / 2 + k, d)])
			1:  # tapering to the back, the outside of a curve
				w = maxf(w, 20.0)
				poly = PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w * 0.2, d), Vector2(-w * 0.2, d)])
			2:  # a pie lot on the inside of a curve, narrow at the street
				poly = PackedVector2Array([Vector2(-w * 0.3, 0), Vector2(w * 0.3, 0), Vector2(w * 0.75, d), Vector2(-w * 0.75, d)])
		odd_lots.append({"width": w, "depth": d, "outline": poly, "at": Vector2(i * 410.0, 0.0)})
	var was_unseated := HouseBuilder.unseated
	for i in odd_lots.size():
		var lot: Dictionary = odd_lots[i]
		var seed := i * 7727 + 3
		var built: Array = HouseBuilder.build(seed, 6.0, lot, 1 + i % 2)
		for m: Rect2 in HouseBuilder.last_masses:
			for c in [m.position, Vector2(m.end.x, m.position.y), m.end, Vector2(m.position.x, m.end.y)]:
				if not Geometry2D.is_point_in_polygon(c, lot.outline):
					odd.append("lot %d (%s) corner %s" % [i, ["skewed", "tapering", "pie"][i % 3], c])
		var lay := SiteLayout.house(seed, {"half": lot.width * 0.5, "depth": lot.depth, "art": lot}, 1 + i % 2)
		for s in lay.spots:
			if s.kind == "drive" and not _on_drive(built[1], s.pos):
				odd.append("lot %d: car off the drive at %s" % [i, s.pos])
	if HouseBuilder.unseated != was_unseated:
		odd.append("%d lots no plan fitted" % (HouseBuilder.unseated - was_unseated))
	_check(odd.is_empty(), "houses on skewed, tapering and pie lots stay inside the lot lines %s" % [odd.slice(0, 3)])

	# The car's garage and drive spots lie on the painted drive.
	var off := []
	for i in lots.size():
		var seed := i * 104729 + 5
		var built: Array = HouseBuilder.build(seed, 6.0, lots[i], 0)
		var lay := SiteLayout.house(seed, {"half": lots[i].width * 0.5, "depth": lots[i].depth, "art": lots[i]}, 0)
		for s in lay.spots:
			if s.kind == "drive" and not _on_drive(built[1], s.pos):
				off.append("lot %d at %s" % [i, s.pos])
		if not _on_drive(built[1], Vector2(lay.cut_x, -1.0)):
			off.append("lot %d curb cut at %.1f" % [i, lay.cut_x])
	_check(off.is_empty(), "cars use the drive the art paints %s" % [off.slice(0, 3)])

	# A house on a wooded hillside (Brawn built a street through a forest:
	# the hill came up through the homes and the woods stayed). The house
	# stands on the high side of its pad and its foundation reaches the low
	# side, at any slope a lot may have and any way the lot faces.
	var buried := []
	for i in 40:
		var built: Array = HouseBuilder.build(i * 31 + 7, 6.0, lots[i], 0)
		var masses: Array = HouseBuilder.last_masses
		var grade := 0.04 + 0.21 * (i % 8) / 7.0  # up to Terrain.MAX_BUILD_SLOPE
		var fall := Vector2.from_angle(i * 0.9) * grade
		var hill := func(x: float, z: float) -> float: return 30.0 + fall.x * x + fall.y * z
		var xform := Transform3D(Basis(Vector3.UP, i * 0.37), Vector3(i * 5.0, 30.0, -i * 3.0))
		var seat := BuildingView.seat_on(masses, xform, hill)
		var floor_y := xform.origin.y + seat.x
		for m: Rect2 in masses:
			for fx in 6:
				for fz in 6:
					var w := xform * Vector3(m.position.x + m.size.x * (0.05 + 0.18 * fx), 0.0, m.position.y + m.size.y * (0.05 + 0.18 * fz))
					var g: float = hill.call(w.x, w.z)
					if g > floor_y + 0.02:
						buried.append("lot %d: ground %.2f m into the floor" % [i, g - floor_y])
					elif g < floor_y - seat.y:
						buried.append("lot %d: foundation %.2f m short of the ground" % [i, floor_y - seat.y - g])
	_check(buried.is_empty(), "on a hillside the ground meets the foundation, never the walls %s" % [buried.slice(0, 3)])
	var level := BuildingView.seat_on(HouseBuilder.last_masses, Transform3D(Basis.IDENTITY, Vector3(0, 12, 0)), func(_x, _z): return 12.0)
	_check(level == Vector2(0.0, BuildingView.FOOTING_DEPTH), "on level ground a house sits where it was put %s" % level)

	# The woods are cleared off every built lot, and stay beside them.
	var sim := CitySim.new()
	var wood := _woodlot()
	sim.apply({"type": "build_road", "start": [wood.x - 150, wood.z], "ctrl": [wood.x, wood.z], "end": [wood.x + 150, wood.z]})
	for x in range(-140, 141, 10):
		for side in [-30.0, 30.0]:
			sim.apply({"type": "paint_zone", "center": [wood.x + x, wood.z + side], "radius": 18, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	var treed := []
	var homes := 0
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		homes += 1
		var poly: PackedVector2Array = sim.lots[key].corners
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		for pl in sim.vegetation.plants_in(box, sim.tick_count):
			if Geometry2D.is_point_in_polygon(Vector2(pl.pos.x, pl.pos.z), poly):
				treed.append(key)
				break
	var behind := sim.vegetation.plants_in(Rect2(wood.x - 100, wood.z + 90, 200, 80), sim.tick_count).size()
	_check(homes >= 10 and treed.is_empty() and behind > 20,
		"homes built in the woods stand on cleared lots (%d homes, %d trees and shrubs in the woods behind) %s" % [homes, behind, treed.slice(0, 3)])

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## A yard that comes in grown (TreeField.yard_age) gets no tree older than
## its room: at its starting age no crown reaches a wall, and two yard
## trees' crowns at most touch. The same lot always gets the same room.
func _grown_yards(lots: Array) -> void:
	var bad := []
	var trees := 0
	var capped := 0
	var ages := []
	var drives := 0
	var props := 0
	for i in lots.size():
		var runs := []
		var b: HouseBuilder
		for k in 2:
			b = HouseBuilder.new()
			b.rng = RandomNumberGenerator.new()
			b.rng.seed = i * 7919 + 13
			b._fit(lots[i])
			runs.append(b._house(6.0, [0, 1, 2][i % 3]))
		var built: Array = runs[0]
		var yard := (built[2] as Array).filter(func(t): return (t[0] as Vector3).z > 0.0)
		if JSON.stringify(built[2]) != JSON.stringify(runs[1][2]):
			bad.append("lot %d: built twice, different trees" % i)
		var reach := []
		for t in yard:
			if t.size() < 5:
				bad.append("lot %d: a yard tree with no room given" % i)
				continue
			var age := TreeField.yard_age(t[1], hash([i, t[0].x]), float(t[4]))
			var free := TreeField.yard_age(t[1], hash([i, t[0].x]), 99.0)
			capped += 1 if age < free - 0.01 else 0
			ages.append(age)
			reach.append(TreeField.SPREAD[t[1]] * float(t[3]) * TreeKinds.size_at(t[1], age))
			# At its starting age the crown keeps off the walls, and by the
			# same rule (its reach times 0.9) off the garage, shed, pool,
			# cottage, the paved drive and its parking, and the thing out back.
			var q := Vector2(t[0].x, t[0].z)
			var need: float = reach[-1] * 0.9 - 0.01
			if age > TreeKinds.nursery_age(t[1]) + 0.01:
				for what in [["the house", b._masses], ["the garage", [b._keep_out]], ["the shed or pool", [b._improved]],
						["the cottage", [b._cottage_at]], ["the drive", b._paved], ["the thing out back", b._props]]:
					var rects: Array = (what[1] as Array).filter(func(r): return (r as Rect2).has_area())
					if not rects.is_empty() and HouseBuilder._gap_to(rects, q) < need:
						bad.append("lot %d: a %d-year %s %.1f m from %s, crown %.1f m" % [i, age,
							TreeField.Species.keys()[t[1]], HouseBuilder._gap_to(rects, q), what[0], reach[-1]])
				# And off the drive as painted (wide paving only: not the walks).
				for k in 13:
					var at := q if k == 12 else q + Vector2.from_angle(k * TAU / 12.0) * need
					if _on_drive(built[1], at) and _on_drive(built[1], at + Vector2(0.95, 0)) and _on_drive(built[1], at - Vector2(0.95, 0)) \
							and _on_drive(built[1], at + Vector2(0, 0.95)) and _on_drive(built[1], at - Vector2(0, 0.95)):
						bad.append("lot %d: a %d-year %s's crown over the painted drive" % [i, age, TreeField.Species.keys()[t[1]]])
						break
			trees += 1
		drives += 1 if not b._paved.is_empty() else 0
		props += b._props.size()
		for a in yard.size():
			for c in range(a + 1, yard.size()):
				var d := Vector2(yard[a][0].x, yard[a][0].z).distance_to(Vector2(yard[c][0].x, yard[c][0].z))
				# A sapling can't be any smaller (nursery stock is the least).
				var young: bool = ages[ages.size() - yard.size() + a] <= TreeKinds.nursery_age(yard[a][1]) + 0.01 \
					or ages[ages.size() - yard.size() + c] <= TreeKinds.nursery_age(yard[c][1]) + 0.01
				if reach.size() == yard.size() and reach[a] + reach[c] > d * 1.15 + 0.01 and not young:
					bad.append("lot %d: two yard trees %.1f m apart, crowns %.1f and %.1f m" % [i, d, reach[a], reach[c]])
	var old := ages.filter(func(a): return a > 40.0).size()
	_check(trees > 100 and bad.is_empty() and old > 0,
		"a grown yard's trees fit their room: crowns off house, garage, shed, pool, drive and the things out back, at most touching (%d trees, %d kept younger to fit, %d over 40 years) %s"
		% [trees, capped, old, bad.slice(0, 3)])
	_check(drives > lots.size() * 0.9 and props > 20,
		"the room counts every lot's drive (%d of %d) and the things out back (%d)" % [drives, lots.size(), props])


## The most wooded spot near the start (as test_vegetation finds it).
func _woodlot() -> Vector3:
	var best := Vector3.ZERO
	var best_v := -1.0
	for x in range(-2000, 2001, 100):
		for z in range(-2000, 2001, 100):
			var v := Resources.at(Resources.Kind.FOREST, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	return best


## True when a spot lies on a concrete drive (yard alpha 0) in the flat mesh.
## Every triangle winds clockwise seen from the side its normal faces
## (Godot's front face), mirrored or not. Shrubs (alpha 0.3) have rounded
## normals, so they are left out.
func _faces_out(a: Array) -> bool:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := idx.size() if not idx.is_empty() else v.size()
	for t in range(0, count - 2, 3):
		var i0 := idx[t] if not idx.is_empty() else t
		var i1 := idx[t + 1] if not idx.is_empty() else t + 1
		var i2 := idx[t + 2] if not idx.is_empty() else t + 2
		var face := (v[i1] - v[i0]).cross(v[i2] - v[i0])
		if absf(col[i0].a - 0.3) < 0.002:
			continue
		if face.length() > 1e-6 and face.dot(n[i0]) > 0.0:
			return false
	return true


func _on_drive(flat: ArrayMesh, p: Vector2) -> bool:
	if flat.get_surface_count() == 0:
		return false
	var a := flat.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 3):
		if c[i].a > 0.01:
			continue
		var tri := PackedVector2Array([Vector2(v[i].x, v[i].z), Vector2(v[i + 1].x, v[i + 1].z), Vector2(v[i + 2].x, v[i + 2].z)])
		if Geometry2D.is_point_in_polygon(p, tri):
			return true
	return false


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
