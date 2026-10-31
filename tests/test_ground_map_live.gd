extends SceneTree
## Run: godot --headless -s tests/test_ground_map_live.gd
## The ground map in the game, step 2 (docs/spec-ground-map.md; Nathan,
## 2026-10-29: "railroad tracks running right through the city like they're
## just a part of the ground. They run right underneath the buildings. I
## also noticed street signs in the middle of driveways."):
##   - the live layer, updated after a road is built and the town has grown
##     a little, is the same as one filed fresh from the town;
##   - lots keep off the county railroad's right of way by the map, with
##     CountyRail's own answers, near town and far from it;
##   - the footprints read a piece at a time are the ones read at once, and
##     reading puts the builders' shared settings back;
##   - the survey files what the live layer doesn't, finds the clashes, and
##     the Ground view draws them.

const Audit := preload("res://tools/overlap_audit.gd")

var _failed := false


func _initialize() -> void:
	var sim := Audit.town("small")
	_check_updates(sim)
	_check_reader(sim)
	_check_survey(sim)
	_check_rail(Audit.town("county_small"))
	quit(1 if _failed else 0)


## The live layer updated as the town changes matches one filed fresh.
func _check_updates(sim: CitySim) -> void:
	GroundFootprints.collect(sim)  # the junction plans pushed to CurbClaims, as the road view does
	var g := GroundMap.of(sim)
	CurbClaims.of(sim).stamp()
	_check(g.signature() == GroundMap.fresh_live(sim).signature(), "the live layer of the town as built matches a fresh one")
	var roads := sim.network.segments.size()
	# A street across the middle of town, through lots and over streets.
	sim.apply({"type": "build_road", "start": [-150.0, 35.0], "ctrl": [0.0, 45.0], "end": [150.0, 35.0]})
	for i in 30:
		sim.tick()
	GroundFootprints.collect(sim)
	g = GroundMap.of(sim)
	CurbClaims.of(sim).stamp()
	var fresh := GroundMap.fresh_live(sim)
	_check(sim.network.segments.size() > roads and g.signature() == fresh.signature(),
		"after a new street and 30 ticks, the updated live layer matches a fresh one (%d roads, was %d; %d claims, fresh %d)" % [
		sim.network.segments.size(), roads, g.stats().claims, fresh.stats().claims])
	var kinds := {}
	for id in g.all_claims():
		kinds[g.kind_of(id)] = true
	for k in ["road", "rail_bed:county", "rail_row:county", "curb_cut", "curb_ramp", "crosswalk"]:
		_check(kinds.has(k), "the live layer holds %s" % k)


## Read a piece at a time, the footprints are the ones read at once, and the
## builders' shared settings are put back after every step.
func _check_reader(sim: CitySim) -> void:
	var once := GroundFootprints.collect(sim)
	var mark := [Rect2(1.0, 2.0, 3.0, 4.0)]
	HouseBuilder.last_masses = mark
	var r := GroundFootprints.Reader.new(sim, false)
	var steps := 0
	var kept := true
	while not r.step(1):
		steps += 1
		kept = kept and HouseBuilder.last_masses == mark and not HouseBuilder.dry_all
	var same := r.out.size() == once.size()
	for i in mini(r.out.size(), once.size()):
		same = same and r.out[i].cat == once[i].cat and r.out[i].key == once[i].key and r.out[i].poly == once[i].poly
	_check(same and steps > 100, "the footprints read in %d steps are the %d read at once" % [steps, once.size()])
	_check(kept, "every step puts the builders' shared settings back")
	HouseBuilder.last_masses = []


func _check_survey(sim: CitySim) -> void:
	var g := GroundMap.of(sim)
	g.survey_start()
	var frames := 0
	while not g.survey_step(2.0) and frames < 100_000:
		frames += 1
	_check(g.surveyed() and frames > 10, "the survey finishes a few milliseconds at a time (%d frames, worst %.1f ms)" % [
		frames, g.survey_max_ms])
	var kinds := {}
	var cuts_ok := true
	for id in g.all_claims():
		var k := g.kind_of(id)
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k in ["curb_cut", "curb_ramp"]:
			cuts_ok = cuts_ok and g._part[id].begins_with("curb.")
	for k in ["lot", "building", "post:mailbox", "post:stop_sign", "tree_trunk", "drive", "sidewalk_line"]:
		_check(int(kinds.get(k, 0)) > 0, "the survey filed %s (%d)" % [k, int(kinds.get(k, 0))])
	_check(cuts_ok, "curb cuts and ramps come from CurbClaims alone, not twice")
	var lot_clash := false
	for p in g.clash_pieces:
		lot_clash = lot_clash or g.kind_of(g._p_claim[p]) == "lot"
	_check(g.clash_pairs > 0 and lot_clash, "the survey finds the clashes, two lots on one patch among them (%d)" % g.clash_pairs)
	# Surveyed again, the same claims (the last survey's taken back first,
	# the map packed together again), and the curb asked as before.
	var sig := g.signature()
	var claims := CurbClaims.of(sim)
	var spots := []
	for id in g.all_claims():
		if g.kind_of(id) in ["post:mailbox", "post:stop_sign", "tree_trunk"]:
			spots.append((g.claim(id).box as Rect2).get_center())
	var free_before := spots.map(func(q): return claims.is_free(q, 0.3))
	var size_before := g._owner.size()
	g.survey_start()
	while not g.survey_step(50.0):
		pass
	_check(g.signature() == sig, "a second survey of the same town gives the same map")
	_check(g._owner.size() <= size_before, "and leaves no pile of taken-back claims (%d slots, %d before)" % [
		g._owner.size(), size_before])
	_check(spots.map(func(q): return claims.is_free(q, 0.3)) == free_before and spots.size() > 100,
		"the curb answers the same after the map packs itself (%d spots)" % spots.size())
	# The Ground view draws every claim, and outlines each clashing piece.
	var view := GroundView.new()
	view.sim = sim
	root.add_child(view)
	view.set_on(true)
	view.build_now()
	var pieces := 0
	for id in g.all_claims():
		pieces += g._pieces[id]
	_check(view.pieces_drawn == pieces and view.outlines_drawn == g.clash_pieces.size() and view._fill.mesh.get_surface_count() == 1
		and view._lines.mesh.get_surface_count() == 1, "the Ground view draws %d pieces and outlines %d in red" % [
		view.pieces_drawn, view.outlines_drawn])
	view.set_on(false)
	_check(not view.visible, "and off, it hides")
	view.queue_free()


## Lots keep off the county railroad's right of way by the map: the same
## answer CountyRail gives, for every lot, the lots moved about, and far
## out of town.
func _check_rail(sim: CitySim) -> void:
	var g := GroundMap.of(sim)
	var o := sim.terrain_offset
	var asked := 0
	var near := 0
	var same := true
	for key in sim.lots:
		var c: PackedVector2Array = sim.lots[key].corners
		for shift in [Vector2.ZERO, Vector2(12.0, 0.0), Vector2(0.0, -12.0), Vector2(-25.0, 25.0)]:
			var poly := PackedVector2Array()
			var reg := PackedVector2Array()
			for q in c:
				poly.append(q + shift)
				reg.append(q + shift + o)
			for half in [CountyRail.ROW_HALF - CitySim.RAIL_LOT_SLACK, CountyRail.ROW_HALF]:
				var a := g.rail_row_distance(poly, half)
				var b := CountyRail.poly_distance(reg, half)
				same = same and a == b
				asked += 1
				if b < half:
					near += 1
	_check(same and near > 0, "the map's right of way answers as CountyRail does (%d asks, %d on it)" % [asked, near])
	var far := GroundFootprints._sq(Vector2(20000.0, 20000.0), 10.0)
	var reg := PackedVector2Array()
	for q in far:
		reg.append(q + o)
	_check(g.rail_row_distance(far, 15.0) == CountyRail.poly_distance(reg, 15.0), "and far out of town too")


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
