extends SceneTree
## Run: godot --headless -s tests/test_curb_claims.gd
## The curb, kept the way real streets keep it (Nathan, 2026-10-29: "I also
## noticed street signs in the middle of driveways ... We need to get good
## at it though because we haven't yet implemented things like bus stops
## and items that will need to immediately make changes to the immediate
## environment like adjustments to the curb."):
##   - a corner house puts its drive away from the corner, 30 ft (9.1 m) or
##     more from the side street's curb (AASHTO-style corner clearance),
##     decided once as it goes up and kept, and never set further back for it;
##   - a town saved before this keeps every house as it was built;
##   - each home's mailbox stands at the curb just beside its drive, never
##     in a drive or on a curb ramp;
##   - a signal's head hangs where it was meant to, however far its pole
##     slid; a stop sign stays within 50 ft of the road it meets (MUTCD);
##   - the claims come from the town alone: the same with or without the
##     buildings drawn, after a save and load, and loaded into a used sim;
##     a shop's paving read from its plan is what its builder draws;
##   - a change away from every post moves nothing and is cheap.

const Audit := preload("res://tools/overlap_audit.gd")

var _failed := false


func _initialize() -> void:
	var sim: CitySim = Audit.town("small")
	var claims := CurbClaims.of(sim)
	claims.set_junctions(_plans(sim))
	claims.warm()
	_corner_drives(sim)
	_old_saves(sim)
	_mailboxes(sim, claims)
	_posts(sim, claims)
	# Where posts must slide: the same town grown on the county's main line,
	# with signals and No Turn posts at its busy corners.
	var county: CitySim = Audit.town("county_small")
	CurbClaims.of(county).set_junctions(_plans(county))
	_junction_posts(county, CurbClaims.of(county))
	_independent(sim)
	_cheap_changes(sim, claims)
	quit(1 if _failed else 0)


## The road view's junction plans for the town (as RoadView pushes them).
func _plans(sim: CitySim) -> Dictionary:
	var rv := _road_view(sim)
	var plans := Junction.plan(sim.network, rv._rural, rv._urban, rv._signals())
	rv.free()
	return plans


func _road_view(sim: CitySim) -> RoadView:
	var rv := RoadView.new()
	rv.sim = sim
	rv.network = sim.network
	rv._rural = rv._rural_segments()
	rv._urban = rv._urban_next
	rv.plans = Junction.plan(sim.network, rv._rural, rv._urban, rv._signals())
	return rv


func _corner_drives(sim: CitySim) -> void:
	var corners := 0
	var away := 0
	var near := []
	var least := INF
	var deeper := []
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		var lot: Dictionary = sim.lots.get(key, {})
		var b: Dictionary = sim.buildings[key]
		if lot.is_empty() or not lot.get("corner", false) or BuildingTypes.type_of(b) != "house":
			continue
		var side := SiteLayout.corner_side(sim.network, lot)
		if side == 0.0 or lot.get("flag", false):
			continue
		corners += 1
		var lay := SiteLayout.for_lot(sim, key)
		var cx := float(lay.cut_x)
		var cw := float(lay.cut_w)
		if signf(cx) == -side and SiteLayout.drive_away(sim, key) == -side:
			away += 1
		# Never pushed back for it: its front wall no deeper than with the
		# dice's side (a shallow corner lot keeps its building line).
		var r := RandomNumberGenerator.new()
		r.seed = int(b.seed)
		var art: Dictionary = SiteLayout._fit(lot).art
		var seed := r.randi()
		var free_pick := HouseBuilder.plan_info(seed, art, BuildingTypes.storeys(b))
		var kept: Dictionary = art.duplicate()
		kept.drive_away = -side
		var with_rule := HouseBuilder.plan_info(seed, kept, BuildingTypes.storeys(b))
		if float(with_rule.front_z) > float(free_pick.front_z) + 0.01:
			deeper.append("%s %.1f > %.1f" % [key, float(with_rule.front_z), float(free_pick.front_z)])
		# The drive's edge nearest the corner, at the curb, to the side
		# street's curb line.
		var tc := float(lot.get("to_curb", 4.0))
		var edge := SiteLayout.world(lot, Vector2(cx + side * cw * 0.5, -tc))
		var probe := SiteLayout.world(lot, Vector2(side * float(lot.width) * 0.5, maxf(float(lot.get("depth", 32.0)) * 0.5, 14.0)))
		var hit := sim.network.find_segment_near(probe, 13.0)
		if hit.is_empty():
			continue
		var seg: int = hit.seg
		var pts := sim.network.sample_segment(seg)
		var d := INF
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(Vector2(edge.x, edge.z), Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z))
			d = minf(d, q.distance_to(Vector2(edge.x, edge.z)))
		d -= RoadStyle.half_width(sim.network.segments[seg].type)
		least = minf(least, d)
		if d < 9.1:
			near.append("%s %.1f m" % [key, d])
	_check(corners >= 10 and away == corners, "every corner house's drive is on the side away from the corner (%d of %d)" % [away, corners])
	_check(near.is_empty(), "corner drives keep 30 ft (9.1 m) from the side street's curb (least %.1f m) %s" % [least, near.slice(0, 4)])
	_check(deeper.is_empty(), "no corner house is set further back to keep its drive away %s" % [deeper.slice(0, 3)])
	# Decided once: a lot that becomes a corner later keeps its house as built.
	var plain := ""
	for key in keys:
		if BuildingTypes.type_of(sim.buildings[key]) == "house" and not sim.lots[key].get("corner", false) \
				and SiteLayout.corner_side(sim.network, sim.lots[key]) == 0.0:
			plain = key
			break
	var lot: Dictionary = sim.lots[plain]
	var before := float(SiteLayout.for_lot(sim, plain).cut_x)
	lot.corner = true
	var after := float(SiteLayout.for_lot(sim, plain).cut_x)
	lot.erase("corner")
	_check(is_equal_approx(before, after) and SiteLayout.drive_away(sim, plain) == 0.0,
		"a house whose lot turns into a corner later keeps its drive as built")
	# A house going up on a corner decides its side then (BuildingTypes.make).
	var corner_key := ""
	for key in keys:
		if BuildingTypes.type_of(sim.buildings[key]) == "house" and SiteLayout.corner_side(sim.network, sim.lots[key]) != 0.0 \
				and sim.lots[key].get("corner", false):
			corner_key = key
			break
	var fresh := {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": 5, "built": sim.tick_count, "changed": sim.tick_count, "occ": 0}
	var made := BuildingTypes.make(sim, corner_key, fresh, "house", 0)
	_check(int(made.get("drive", 0)) == -int(SiteLayout.corner_side(sim.network, sim.lots[corner_key])),
		"a house going up on a corner lot decides its drive side as it is built (%s)" % made.get("drive"))
	# The yard props' own reading of a plan (LotState, no drawing) keeps it too.
	var differ := 0
	for key in keys:
		if SiteLayout.drive_away(sim, key) == 0.0:
			continue
		var y := LotState.yard_of(sim, key)
		if not is_equal_approx(float(y.drive_x), float(SiteLayout.for_lot(sim, key).cut_x)):
			differ += 1
	_check(differ == 0, "the yard props read a corner house's drive where it was built (%d differ)" % differ)


## A town saved before the rule loads with it off for the houses it had
## (they keep their drives as built); a town saved after keeps it on.
func _old_saves(sim: CitySim) -> void:
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var fresh := CitySim.new()
	fresh.from_dict(d)
	d.erase("curb_drives_from")
	for key in d.buildings:
		d.buildings[key].erase("drive")
	var old := CitySim.new()
	old.from_dict(d)
	_check(fresh.curb_drives_from == 0 and old.curb_drives_from == old.tick_count + 1,
		"the rule is saved (%d) and an old save starts it after its last tick (%d, tick %d)" % [fresh.curb_drives_from, old.curb_drives_from, old.tick_count])
	var same := 0
	var kept := 0
	var moved := 0
	var houses := 0
	for key in sim.buildings:
		if not old.lots.has(key) or BuildingTypes.type_of(sim.buildings[key]) != "house":
			continue
		houses += 1
		var b: Dictionary = sim.buildings[key]
		var as_built := SiteLayout.for_building(int(b.zone), int(b.seed), sim.lots[key], BuildingTypes.storeys(b),
			"house", int(b.get("level", 0)), sim.network, int(b.get("added_from", 0)))
		if is_equal_approx(float(SiteLayout.for_lot(old, key).cut_x), float(as_built.cut_x)):
			kept += 1
		if is_equal_approx(float(SiteLayout.for_lot(fresh, key).cut_x), float(SiteLayout.for_lot(sim, key).cut_x)):
			same += 1
		if not is_equal_approx(float(as_built.cut_x), float(SiteLayout.for_lot(sim, key).cut_x)):
			moved += 1
	_check(houses > 50 and kept == houses, "an old save keeps every house's drive as it was built (%d of %d)" % [kept, houses])
	_check(same == houses, "a save made with the rule loads with the same drives (%d of %d)" % [same, houses])
	_check(moved > 0 and moved < houses / 4, "only corner houses' drives moved (%d of %d)" % [moved, houses])


func _mailboxes(sim: CitySim, claims: CurbClaims) -> void:
	var homes := 0
	var in_drive := []
	var on_ramp := []
	var beside := 0
	var with_drive := 0
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		var box := claims.mailbox_at(key)
		if not box.is_finite():
			continue
		homes += 1
		var area := Rect2(box - Vector2(0.25, 0.25), Vector2(0.5, 0.5))
		for s in claims.near(area, ["cut"]):
			if CurbClaims._hits(s, box, 0.25):
				in_drive.append("%s in %s's drive" % [key, s[1]])
		if not claims.junction_free(box, 0.25):
			on_ramp.append(key)
		if BuildingTypes.type_of(sim.buildings[key]) not in ["house", "duplex"]:
			continue
		var own := claims.cut_of(key)
		if not own.is_empty():
			with_drive += 1
			var gap := INF
			var poly: PackedVector2Array = own[0][2]
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(box, poly[i], poly[(i + 1) % poly.size()])
				gap = minf(gap, q.distance_to(box))
			if gap < 1.5:
				beside += 1
	_check(homes > 50 and in_drive.is_empty(), "no mailbox stands in a drive (%d homes) %s" % [homes, in_drive.slice(0, 3)])
	_check(on_ramp.is_empty(), "no mailbox stands on a curb ramp %s" % [on_ramp.slice(0, 3)])
	_check(with_drive > 50 and beside >= with_drive * 0.9, "mailboxes stand just beside their own drive (%d of %d)" % [beside, with_drive])


func _posts(sim: CitySim, claims: CurbClaims) -> void:
	# A post meant for the middle of a drive's curb cut slides off it, along
	# the curb, to a clear spot.
	var key := ""
	var keys := sim.buildings.keys()
	keys.sort()
	for k in keys:
		if BuildingTypes.type_of(sim.buildings[k]) == "house" and not claims.cut_of(k).is_empty():
			key = k
			break
	var poly: PackedVector2Array = claims.cut_of(key)[0][2]
	var mid := Vector2.ZERO
	for v in poly:
		mid += v
	mid /= poly.size()
	var lot: Dictionary = sim.lots[key]
	var along: Vector3 = lot.dir
	_check(not claims.is_free(mid, 0.15), "the middle of a drive's cut is taken")
	var at := claims.post_spot(Vector3(mid.x, 0.0, mid.y), along, 0.15)
	_check(claims.is_free(Vector2(at.x, at.z), 0.15) and Vector2(at.x, at.z).distance_to(mid) <= CurbClaims.POST_BACK + 0.01,
		"a post meant for a drive slides %.1f m along the curb to a clear spot" % Vector2(at.x, at.z).distance_to(mid))
	# Something new on the curb (a bus stop's pad) claims its spot, and gives it back.
	var spot := Vector2(9000.0, 9000.0)
	_check(claims.is_free(spot, 0.2), "open ground is free")
	claims.claim("bus_stop", "stop:1", CurbClaims.square(spot, 1.5))
	_check(not claims.is_free(spot + Vector2(1.0, 0.0), 0.2), "a bus stop's pad claims the curb")
	claims.release("stop:1")
	_check(claims.is_free(spot, 0.2), "and gives it back when it goes")


## The junction view's own posts and signal heads, stood with the curb
## claims and without: every signal head hangs where it was meant to (its
## arm reaches the pole wherever it slid, no longer than a real 75 ft mast
## arm), and every stop or yield sign that slid stays within 50 ft of the
## edge of the road it meets.
func _junction_posts(sim: CitySim, claims: CurbClaims) -> void:
	var rv := _road_view(sim)
	var jv := JunctionView.new()
	jv.setup(sim.traffic)
	jv.roads = rv
	jv._ready()  # its batches, without a running tree
	jv._rebuild_all()
	var heads := _origins(jv.stood.heads)
	var arms: Array = jv.stood.arms.map(func(t): return (t as Transform3D).basis.x.length())
	var poles := _origins(jv.stood.poles)
	var stops := _origins(jv.stood.stops) + _origins(jv.stood.yields)
	rv.sim = null  # no claims: every post where it was meant to stand
	jv._rebuild_all()
	var heads0 := _origins(jv.stood.heads)
	var stops0 := _origins(jv.stood.stops) + _origins(jv.stood.yields)
	var poles0 := _origins(jv.stood.poles)
	rv.sim = sim
	var moved_heads := 0
	for i in mini(heads.size(), heads0.size()):
		if heads[i].distance_to(heads0[i]) > 0.01:
			moved_heads += 1
	var slid := 0
	for i in mini(poles.size(), poles0.size()):
		if Vector2(poles[i].x, poles[i].z).distance_to(Vector2(poles0[i].x, poles0[i].z)) > 0.01:
			slid += 1
	_check(slid > 0 and heads.size() >= 8 and heads.size() == heads0.size() and moved_heads == 0,
		"every signal head hangs where it was meant to (%d heads, %d poles slid)" % [heads.size(), slid])
	_check(arms.all(func(a): return a <= 22.9), "no mast arm is longer than 75 ft (%.1f m longest)" % [arms.max() if not arms.is_empty() else 0.0])
	# Something on the curb where every stop sign was meant to stand (a 3 m
	# pad each): each slides back off it, no further than 50 ft from the
	# road it meets.
	var stops_meant := stops0
	for i in stops_meant.size():
		claims.claim("pad", "test:%d" % i, CurbClaims.square(Vector2(stops_meant[i].x, stops_meant[i].z), 1.5))
	jv._rebuild_all()
	var slid_stops := _origins(jv.stood.stops) + _origins(jv.stood.yields)
	for i in stops_meant.size():
		claims.release("test:%d" % i)
	var far := []
	var moved_stops := 0
	var stuck := 0
	for i in mini(slid_stops.size(), stops_meant.size()):
		var p := Vector2(slid_stops[i].x, slid_stops[i].z)
		var m := Vector2(stops_meant[i].x, stops_meant[i].z)
		if p.distance_to(m) < 0.01:
			stuck += 1
			continue
		moved_stops += 1
		var best := INF
		var edge := 0.0
		for n in sim.traffic.junctions:
			var c: Vector3 = sim.network.nodes[n]
			var d := Vector2(c.x, c.z).distance_to(m)
			if d < best:
				best = d
				var cross := 0.0
				for w in sim.traffic.ways_into(n):
					cross = maxf(cross, RoadStyle.TYPES[sim.traffic.ways[w].type].width * 0.5)
				# Along its curb, toward the junction.
				var toward := (p - m).normalized()
				if (Vector2(c.x, c.z) - m).dot(toward) < 0.0:
					toward = -toward
				edge = (Vector2(c.x, c.z) - p).dot(toward) - cross
		if edge > JunctionView.STOP_REACH + 0.05:
			far.append("%.1f m" % edge)
	_check(moved_stops > 10 and far.is_empty(),
		"stop and yield signs slide back off what takes their spot, every one within 50 ft of the road it meets (%d slid, %d had no room) %s" % [moved_stops, stuck, far.slice(0, 3)])
	jv.free()
	rv.free()


static func _origins(xforms: Array) -> Array:
	return xforms.map(func(t): return (t as Transform3D).origin)


## The claims come from the town alone.
func _independent(sim: CitySim) -> void:
	# A shop's, office's or plant's paving read from its plan (a dry run of
	# its builder) is what its builder draws.
	var bv := BuildingView.new()
	bv.sim = sim
	var keys := sim.buildings.keys()
	keys.sort()
	var checked := 0
	var differ := []
	var before := _snapshot(sim)
	for key in keys:
		if not sim.lots.has(key) or BuildingTypes.type_of(sim.buildings[key]) in ["house", "duplex"]:
			continue
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key]
		var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
		var rng := RandomNumberGenerator.new()
		rng.seed = b.seed
		HouseBuilder.cuts_drawn = []
		bv._draw(key, lot, b, bv.fit_of(key, xf), rng.randi())
		var drawn: Array = HouseBuilder.cuts_drawn
		HouseBuilder.cuts_drawn = null
		var plan := BuildingView.curb_paving(sim, key)
		checked += 1
		if str(drawn) != str(plan):
			differ.append("%s %s: %s vs %s" % [key, BuildingTypes.type_of(b), plan, drawn])
	bv.free()
	_check(checked > 20 and differ.is_empty(), "every shop's, office's and plant's paving read from its plan is what is drawn (%d) %s" % [checked, differ.slice(0, 2)])
	_check(_snapshot(sim) == before, "the claims are the same before and after every building is drawn")
	# Saved and loaded: the same spots.
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var copy := CitySim.new()
	copy.from_dict(d)
	var after := _snapshot(copy)
	_check(after == before, "a saved and loaded town stands its posts, lamps and mailboxes in the same spots %s" % _first_diff(before, after))
	# Loaded into a sim that already had another town's curb worked out.
	var used := CitySim.new()
	PerfTown.build(used, "small")
	for key in used.buildings.keys().slice(0, 40):
		used.buildings.erase(key)
	used.buildings_changed.emit()
	CurbClaims.of(used).set_junctions(_plans(used))
	CurbClaims.of(used).warm()
	used.from_dict(d)
	var reused := _snapshot(used)
	_check(reused == before, "a town loaded into a used sim gets its own curb, not the last one's %s" % _first_diff(before, reused))


static func _first_diff(a: String, b: String) -> String:
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			return "[at %d: ...%s... vs ...%s...]" % [i, a.substr(maxi(i - 80, 0), 160), b.substr(maxi(i - 80, 0), 160)]
	return "" if a.length() == b.length() else "[lengths %d vs %d]" % [a.length(), b.length()]


## Everything the claims answer for a town: each lot's cut, each home's
## mailbox, every lamp and every junction post's spot (the overlap
## auditor's mirror of the junction view).
func _snapshot(sim: CitySim) -> String:
	var claims := CurbClaims.of(sim)
	claims.set_junctions(_plans(sim))
	var keys := sim.buildings.keys()
	keys.sort()
	var out := []
	for key in keys:
		out.append([key, claims.cut_of(key).map(func(s): return s[2]), claims.mailbox_at(key)])
	var rv := _road_view(sim)
	out.append(StreetLights.place(sim.network, rv._rural, claims).map(func(l): return l[1]))
	var shapes := []
	sim.traffic._rebuild()  # its junctions as a first tick sets them up (a town just loaded has none yet)
	GroundFootprints._signs(shapes, sim, rv, rv.plans)
	out.append(shapes.map(func(s): return s.poly))
	rv.free()
	return str(out)


## A change away from every post and lamp is logged where it is, moves
## nothing and costs little; one next to a post makes the junction view
## stand its posts again.
func _cheap_changes(sim: CitySim, claims: CurbClaims) -> void:
	var rv := _road_view(sim)
	var jv := JunctionView.new()
	jv.setup(sim.traffic)
	jv.roads = rv
	jv._ready()  # its batches, without a running tree
	jv._rebuild_all()
	# The home furthest from every post.
	var far := ""
	var near := ""
	var far_d := -1.0
	var near_d := INF
	for key in sim.buildings:
		if BuildingTypes.type_of(sim.buildings[key]) != "house" or not sim.lots.has(key):
			continue
		var f: Vector3 = sim.lots[key].front
		var d := INF
		for m: Vector2 in jv._meant:
			d = minf(d, m.distance_to(Vector2(f.x, f.z)))
		if d > far_d:
			far_d = d
			far = key
		if d < near_d:
			near_d = d
			near = key
	var seen := claims.stamp()
	var mails := claims._mail.size()
	var b: Dictionary = sim.buildings[far]
	sim.buildings.erase(far)
	sim.buildings_changed.emit()
	var boxes := claims.changes_since(seen)
	var ms := claims.last_sync_ms
	_check(boxes.size() >= 1 and boxes.all(func(r): return (r as Rect2).get_center().distance_to(Vector2(sim.lots[far].front.x, sim.lots[far].front.z)) < 20.0),
		"a home taken down far from any junction logs only where it stood (%d places)" % boxes.size())
	_check(ms < 25.0, "bringing the claims up to date after it takes %.1f ms" % ms)
	_check(claims._mail.size() >= mails - 12, "only the mailboxes near it stand again (%d of %d kept)" % [claims._mail.size(), mails])
	jv._claims_wait = 0.0
	_check(not jv._curb_moved(0.0), "the junction view leaves its posts where they are")
	sim.buildings[far] = b
	sim.buildings_changed.emit()
	claims.stamp()
	jv._claims_wait = 0.0
	jv._curb_moved(0.0)
	var nb: Dictionary = sim.buildings[near]
	sim.buildings.erase(near)
	sim.buildings_changed.emit()
	jv._claims_wait = 0.0
	_check(jv._curb_moved(0.0), "one taken down beside a post (%.1f m) makes it look again" % near_d)
	sim.buildings[near] = nb
	sim.buildings_changed.emit()
	jv.free()
	rv.free()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
