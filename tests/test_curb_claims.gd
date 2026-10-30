extends SceneTree
## Run: godot --headless -s tests/test_curb_claims.gd
## The curb, kept the way real streets keep it (Nathan, 2026-10-29: "I also
## noticed street signs in the middle of driveways ... We need to get good
## at it though because we haven't yet implemented things like bus stops
## and items that will need to immediately make changes to the immediate
## environment like adjustments to the curb."):
##   - a corner house puts its drive away from the corner, 30 ft (9.1 m) or
##     more from the side street's curb (AASHTO-style corner clearance);
##   - a town saved before this keeps every house as it was built;
##   - each home's mailbox stands at the curb just beside its drive, never
##     in a drive or on a curb ramp;
##   - CurbClaims answers "is this stretch of curb free?" for all of them,
##     slides a post off a drive, and takes new claims (a bus stop's pad).

var _failed := false


func _initialize() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	var claims := CurbClaims.of(sim)
	claims.set_junctions(_plans(sim))
	_corner_drives(sim)
	_old_saves(sim)
	_mailboxes(sim, claims)
	_posts(sim, claims)
	quit(1 if _failed else 0)


## The road view's junction plans for the town (as RoadView pushes them).
func _plans(sim: CitySim) -> Dictionary:
	var rv := RoadView.new()
	rv.sim = sim
	rv.network = sim.network
	rv._rural = rv._rural_segments()
	rv._urban = rv._urban_next
	var plans := Junction.plan(sim.network, rv._rural, rv._urban, rv._signals())
	rv.free()
	return plans


func _corner_drives(sim: CitySim) -> void:
	var corners := 0
	var away := 0
	var near := []
	var least := INF
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
		if signf(cx) == -side:
			away += 1
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


## A town saved before the rule loads with it off for the houses it had
## (they keep their drives as built); a town saved after keeps it on.
func _old_saves(sim: CitySim) -> void:
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var fresh := CitySim.new()
	fresh.from_dict(d)
	d.erase("curb_drives_from")
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
	# The same town built again puts every box in the same place.
	var again := CitySim.new()
	PerfTown.build(again, "small")
	var c2 := CurbClaims.of(again)
	c2.set_junctions(_plans(again))
	var differ := 0
	for key in keys:
		if claims.mailbox_at(key) != c2.mailbox_at(key):
			differ += 1
	_check(differ == 0, "mailboxes come out the same every time (%d differ)" % differ)


func _posts(sim: CitySim, claims: CurbClaims) -> void:
	# A post meant for the middle of a drive's curb cut slides off it, along
	# the curb, to a clear spot.
	var key := ""
	var keys := sim.buildings.keys()
	keys.sort()
	for k in keys:
		if not claims.cut_of(k).is_empty():
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


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
