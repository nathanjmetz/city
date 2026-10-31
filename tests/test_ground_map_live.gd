extends SceneTree
## Run: godot --headless -s tests/test_ground_map_live.gd
## The ground map in the game, step 2 (docs/spec-ground-map.md; Nathan,
## 2026-10-29: "railroad tracks running right through the city like they're
## just a part of the ground. They run right underneath the buildings. I
## also noticed street signs in the middle of driveways."):
##   - the live layer, updated after a road is built and the town has grown
##     a little, is the same as one filed fresh from the town, its curb
##     worked out again without CurbClaims;
##   - the same town saved and loaded gives the same live layer;
##   - lots keep off the county railroad's right of way by the map, with
##     CountyRail's own answers, near town and far from it;
##   - the footprints read a piece at a time are the ones read at once, and
##     reading puts the builders' shared settings back;
##   - the survey files what the live layer doesn't into a map of its own,
##     finds the clashes, finishes in a town that keeps growing, and the
##     Ground view draws it all; the curb ledger holds live claims only.

const Audit := preload("res://tools/overlap_audit.gd")

var _failed := false


func _initialize() -> void:
	var sim := Audit.town("small")
	_check_updates(sim)
	_check_reload(sim)
	_check_reader(sim)
	_check_survey(sim)
	_check_growing()
	_check_rail(Audit.town("county_small"))
	quit(1 if _failed else 0)


## The junction plans as the road view works them out (a road view made for
## the purpose), pushed to CurbClaims as the game's road view does.
func _plans(sim: CitySim) -> Dictionary:
	var rv := RoadView.new()
	rv.sim = sim
	rv.network = sim.network
	rv._rural = rv._rural_segments()
	rv._urban = rv._urban_next
	var plans := Junction.plan(sim.network, rv._rural, rv._urban, rv._signals())
	rv.free()
	CurbClaims.of(sim).set_junctions(plans)
	CurbClaims.of(sim).stamp()
	return plans


## A live layer's claims by kind and owner ("kind owner part" -> pieces).
func _groups(g: GroundMap) -> Dictionary:
	var out := {}
	for id in g.all_claims():
		out["%s %s" % [g.kind_of(id), g.name_of(id)]] = g._pieces[id]
	return out


## The live layer updated as the town changes matches one filed fresh, its
## curb worked out again from the plans and lots, not read from CurbClaims.
func _check_updates(sim: CitySim) -> void:
	var plans := _plans(sim)
	var g := GroundMap.of(sim)
	_check(g.signature() == GroundMap.fresh_live(sim, plans).signature(), "the live layer of the town as built matches a fresh one")
	var roads := sim.network.segments.size()
	# A street across the middle of town, through lots and over streets.
	sim.apply({"type": "build_road", "start": [-150.0, 35.0], "ctrl": [0.0, 45.0], "end": [150.0, 35.0]})
	for i in 30:
		sim.tick()
	plans = _plans(sim)
	g = GroundMap.of(sim)
	var fresh := GroundMap.fresh_live(sim, plans)
	_check(sim.network.segments.size() > roads and g.signature() == fresh.signature() and _groups(g) == _groups(fresh),
		"after a new street and 30 ticks, the updated live layer matches a fresh one (%d roads, was %d; %d claims, fresh %d)" % [
		sim.network.segments.size(), roads, g.stats().claims, fresh.stats().claims])
	var kinds := {}
	for id in g.all_claims():
		kinds[g.kind_of(id)] = true
	for k in ["road", "rail_bed:county", "rail_row:county", "curb_cut", "curb_ramp", "crosswalk"]:
		_check(kinds.has(k), "the live layer holds %s" % k)
	# A road out past the town's edge: the railroads filed again only if
	# their beds changed, and CurbClaims told only then.
	var told := [0]
	g.rail_changed.connect(func(_box): told[0] += 1)
	var beds := _beds(g)
	sim.apply({"type": "build_road", "start": [280.0, 280.0], "ctrl": [300.0, 300.0], "end": [320.0, 330.0]})
	g = GroundMap.of(sim)
	_check((_beds(g) == beds) == (told[0] == 0), "CurbClaims hears of the railroads only when their beds change (%d)" % told[0])


## The railroad beds filed: [kind, owner, hash of outlines] each, in order.
func _beds(g: GroundMap) -> Array:
	var out := []
	for k in g._bed_by:
		out.append([k[0], k[1], g._bed_by[k][0]])
	out.sort()
	return out


## The same town saved and loaded gives the same live layer.
func _check_reload(sim: CitySim) -> void:
	_plans(sim)
	var g := GroundMap.of(sim)
	var copy := CitySim.new()
	copy.county_rail = true
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.county_trains.tick(copy)
	_plans(copy)
	var h := GroundMap.of(copy)
	_check(_groups(h) == _groups(g), "saved and loaded: the same claims by kind and owner (%d)" % _groups(g).size())
	_check(h.signature() == g.signature(), "saved and loaded: the same live layer")


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


func _survey(g: GroundMap, ms := 2.0) -> int:
	g.survey_start()
	var frames := 0
	while not g.survey_step(ms) and frames < 100_000:
		frames += 1
	return frames


func _check_survey(sim: CitySim) -> void:
	var g := GroundMap.of(sim)
	g.curb_gap(0, 1, 0.0, 30.0)  # the ledger put together before any survey
	var ledger: int = g.stats().curb_claims
	var live := g.signature()
	var frames := _survey(g)
	var s := g.survey
	_check(g.surveyed() and frames > 10, "the survey finishes a few milliseconds at a time (%d frames, worst %.1f ms)" % [
		frames, g.survey_max_ms])
	var kinds := {}
	for id in s.all_claims():
		var k := s.kind_of(id)
		kinds[k] = int(kinds.get(k, 0)) + 1
	for k in ["lot", "building", "post:mailbox", "post:stop_sign", "tree_trunk", "drive", "sidewalk_line"]:
		_check(int(kinds.get(k, 0)) > 0, "the survey filed %s (%d)" % [k, int(kinds.get(k, 0))])
	for k in GroundMap.LIVE_KINDS:
		_check(not kinds.has(k), "the survey leaves %s to the live layer" % k)
	_check(g.signature() == live and g.stats().curb_claims == ledger,
		"the live layer and its curb ledger are the same after the survey (%d on the curb)" % ledger)
	var lot_clash := false
	for p in s.clash_pieces:
		lot_clash = lot_clash or s.kind_of(s._p_claim[p]) == "lot"
	_check(s.clash_pairs > 0 and lot_clash, "the survey finds the clashes, two lots on one patch among them (%d)" % s.clash_pairs)
	# Surveyed again: the same map, and the last one shown until it's done.
	var sig := s.signature()
	g.survey_start()
	g.survey_step(1.0)
	_check(g.survey == s, "while the next survey runs, the last one finished stays")
	while not g.survey_step(50.0):
		pass
	_check(g.survey != s and g.survey.signature() == sig, "a second survey of the same town gives the same map")
	# The Ground view draws every claim, and outlines each clashing piece.
	var view := GroundView.new()
	view.sim = sim
	root.add_child(view)
	view.set_on(true)
	view.build_now()
	var pieces := 0
	for m in [g, g.survey]:
		for id in m.all_claims():
			pieces += m._pieces[id]
	_check(view.pieces_drawn == pieces and view.outlines_drawn == g.survey.clash_pieces.size() + g.survey.live_clashes.size()
		and view._fill.mesh.get_surface_count() >= 1, "the Ground view draws %d pieces and outlines %d in red" % [
		view.pieces_drawn, view.outlines_drawn])
	view.set_on(false)
	_check(not view.visible, "and off, it hides")
	view.queue_free()


## A town that keeps growing while it's surveyed still finishes a survey.
func _check_growing() -> void:
	var sim := Audit.town("small")
	sim.require_utilities = false
	var g := GroundMap.of(sim)
	g.survey_start()
	var frames := 0
	var changed := false
	while not g.surveyed() and frames < 20_000:
		sim.tick()
		if frames % 10 == 0:
			# A new street every ten frames, out past the town.
			var x := 420.0 + 30.0 * (frames / 10)
			sim.apply({"type": "build_road", "start": [x, -200.0], "ctrl": [x, -170.0], "end": [x + 5.0, -140.0]})
		changed = changed or g.survey_stale()
		g.survey_step(3.0)
		frames += 1
	_check(g.surveyed() and changed, "a town growing all the while still gets its survey (%d frames, the town changed: %s)" % [
		frames, changed])


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
