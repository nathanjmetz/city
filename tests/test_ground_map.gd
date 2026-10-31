extends SceneTree
## Run: godot --headless -s tests/test_ground_map.gd
## The ground map, step 1 (docs/spec-ground-map.md; Nathan, 2026-10-29:
## "railroad tracks running right through the city like they're just a part
## of the ground ... we haven't yet implemented things like bus stops and
## items that will need to immediately make changes to the immediate
## environment like adjustments to the curb."):
##   - it holds the very shapes the overlap auditor checks, and finds the
##     same clashes the auditor counts, pair by pair, at every grid size
##     tried (12, 16 and 24 m);
##   - the same town gives the same map, built twice or saved and loaded;
##   - ask refuses what lands on something ranked ahead and names what
##     would give way; register and release put the map back as it was;
##   - the curb ledger finds what stands on a stretch of curb and a free
##     stretch near a spot;
##   - what one ask costs (printed).

const Audit := preload("res://tools/overlap_audit.gd")
const CELLS := [12.0, 16.0, 24.0]

var _failed := false


func _initialize() -> void:
	for name in ["small", "county_small"]:
		var sim := Audit.town(name)
		var res := Audit.audit(sim)
		var shapes := GroundFootprints.collect(sim)
		for cell in CELLS:
			var map := GroundMap.new(cell)
			map.fill_from(sim, shapes)
			_check_shapes(name, cell, map, res, shapes)
			_check_clashes(name, cell, map, res)
		if name == "small":
			var map := GroundMap.new()
			map.fill_from(sim, shapes)
			_check_same(sim, map)
			_check_shuffled(sim, shapes, map.signature())
			_check_ask(map)
			_check_curb(map)
			_time_asks(map)
		else:
			_check_rail(GroundMap.build(sim))
	_check_fixed_street()
	quit(1 if _failed else 0)


## Every shape the auditor reads is a piece of the map, kind by kind, point
## for point.
func _check_shapes(town: String, cell: float, map: GroundMap, res: Dictionary, shapes: Array) -> void:
	var want := {}
	for s in shapes:
		var k: String = Audit._skey(s)
		if not want.has(k):
			want[k] = []
		want[k].append(hash(s.poly))
	var got := {}
	for id in map.all_claims():
		var c := map.claim(id)
		if not got.has(c.kind):
			got[c.kind] = []
		for poly in c.polys:
			got[c.kind].append(hash(poly))
	var same := want.size() == got.size()
	var off := []
	for k in want:
		var a: Array = want[k]
		var b: Array = got.get(k, [])
		a.sort()
		b.sort()
		if a != b or int(res.shapes.get(k, 0)) != b.size():
			same = false
			off.append("%s %d/%d" % [k, b.size(), a.size()])
	_check(same, "%s, %.0f m squares: the map holds every shape the auditor checks (%d kinds, %d shapes) %s" % [
		town, cell, want.size(), shapes.size(), ", ".join(off)])


## The map's own search finds the auditor's clashes, pair by pair (never and
## watch), piece by piece as the auditor counts them.
func _check_clashes(town: String, cell: float, map: GroundMap, res: Dictionary) -> void:
	var got := {}
	var ids := map.all_claims()
	for p in GroundMap.PAIRS:
		var a: String = p[0]
		var b: String = (p[1] as String).trim_suffix("*other")
		for id in ids:
			var c := map.claim(id)
			if (c.kind as String).get_slice(":", 0) != a:
				continue
			var first: int = map._first[id]
			for i in c.polys.size():
				for h in map.hits(c.kind, c.polys[i], c.owner, true):
					var other: int = map._p_claim[h[0]]
					var ko := map.kind_of(other)
					if ko.get_slice(":", 0) != b or (a == b and h[0] <= first + i):
						continue
					var key := _pair_key(c.kind, ko)
					got[key] = int(got.get(key, 0)) + 1
	var want := {}
	for k in res.counts:
		if int(res.counts[k].count) > 0:
			var key := _pair_key(k.get_slice(" vs ", 0), k.get_slice(" vs ", 1))
			want[key] = int(want.get(key, 0)) + int(res.counts[k].count)
	var off := []
	for k in want.keys() + got.keys():
		if int(want.get(k, 0)) != int(got.get(k, 0)) and not k in off:
			off.append("%s: map %d, auditor %d" % [k, int(got.get(k, 0)), int(want.get(k, 0))])
	_check(off.is_empty() and not want.is_empty(), "%s, %.0f m squares: the map finds the auditor's %d kinds of clash, count for count %s" % [
		town, cell, want.size(), "; ".join(off)])


## "a vs b"; two of one group (post vs post) by name, since which comes
## first hangs on the order they were read in.
static func _pair_key(a: String, b: String) -> String:
	if a.get_slice(":", 0) == b.get_slice(":", 0) and b < a:
		return "%s vs %s" % [b, a]
	return "%s vs %s" % [a, b]


## The same town gives the same map: built again from nothing, and saved
## and loaded (another order of roads and lots).
func _check_same(sim: CitySim, map: GroundMap) -> void:
	var sig := map.signature()
	var again := GroundMap.build(Audit.town("small"))
	_check(again.signature() == sig, "the same town built twice gives the same map (%d claims)" % map.stats().claims)
	var copy := CitySim.new()
	copy.county_rail = true
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.county_trains.tick(copy)
	var loaded := GroundMap.build(copy)
	_check(loaded.signature() == sig, "the same town saved and loaded gives the same map (%d claims, %d loaded)" % [
		map.stats().claims, loaded.stats().claims])
	if loaded.signature() != sig:
		_diff(map, loaded)
	# Asked through the sim: made once and kept.
	var kept := GroundMap.of(sim)
	_check(kept != null and GroundMap.of(sim) == kept and sim.ground == kept, "GroundMap.of keeps the town's map on the sim")


## The shapes read in any order give the same map (a claim's pieces too).
func _check_shuffled(sim: CitySim, shapes: Array, sig: int) -> void:
	var same := 0
	for i in 3:
		var mixed := shapes.duplicate()
		seed(1000 + i)
		mixed.shuffle()
		var map := GroundMap.new()
		map.fill_from(sim, mixed)
		if map.signature() == sig:
			same += 1
	_check(same == 3, "the town's shapes read in 3 shuffled orders give the same map (%d of 3)" % same)


## A street laid out by hand, with the answers written out: 100 m west to
## east along z = -50, from x = -100 to x = 0, 5 m to the pavement's edge,
## 4 m at each end taken by the cross streets.
func _check_fixed_street() -> void:
	var map := GroundMap.new()
	map.set_street(7, PackedVector2Array([Vector2(-100.0, -50.0), Vector2(0.0, -50.0)]), 5.0, 4.0, 4.0)
	map.register("seg:7", "road", "road", [PackedVector2Array([Vector2(-100.0, -55.0), Vector2(0.0, -55.0),
		Vector2(0.0, -45.0), Vector2(-100.0, -45.0)])])
	# A post at x = -40, 7 m south of the centre line: 60 m along, on the
	# right going east (south), 2 m past the pavement's edge.
	var post := map.register("lot:a", "mailbox", "post:mailbox", [GroundFootprints._sq(Vector2(-40.0, -43.0), 0.25)])
	var spot := map.curb_spot(Vector2(-40.0, -43.0))
	_check(spot.size() == 4 and spot[0] == 7 and spot[1] == 1 and is_equal_approx(spot[2], 60.0) and is_equal_approx(spot[3], 2.0),
		"fixed street: a spot 7 m south is street 7, right side, 60 m along, 2 m out (%s)" % str(spot))
	spot = map.curb_spot(Vector2(-75.0, -57.5))
	_check(spot.size() == 4 and spot[0] == 7 and spot[1] == -1 and is_equal_approx(spot[2], 25.0) and is_equal_approx(spot[3], 2.5),
		"fixed street: a spot 7.5 m north is the left side, 25 m along, 2.5 m out (%s)" % str(spot))
	_check(map.curb_spot(Vector2(-40.0, -30.0)).is_empty(), "fixed street: 20 m away is past the curb's reach")
	var c := map.claim(post)
	_check(c.curb.size() == 1 and c.curb[0][0] == 15 and is_equal_approx(c.curb[0][1], 59.75) and is_equal_approx(c.curb[0][2], 60.25),
		"fixed street: the post is filed on side key 15 from 59.75 to 60.25 m (%s)" % str(c.curb))
	_check(map.curb_at(7, 1, 59.0, 61.0) == [post] and map.curb_at(7, -1, 59.0, 61.0).is_empty()
		and map.curb_at(7, 1, 60.25, 70.0).is_empty(), "fixed street: curb_at finds it on its side and stretch only")
	# Free curb runs 4 to 59.75 and 60.25 to 96 m.
	var cases := [[60.0, 30.0, 29.75], [0.0, 30.0, 4.0], [100.0, 30.0, 66.0], [80.0, 35.75, 60.25], [50.0, 55.75, 4.0],
		[50.0, 56.0, -1.0]]
	for k in cases:
		var got := map.curb_gap(7, 1, k[0], k[1])
		_check(is_equal_approx(got, k[2]), "fixed street: %.2f m of free curb nearest %.0f m starts at %.2f (got %.2f)" % [k[1], k[0], k[2], got])
	_check(is_equal_approx(map.curb_gap(7, -1, 50.0, 92.0), 4.0) and map.curb_gap(7, -1, 50.0, 92.5) < 0.0,
		"fixed street: the empty side has 92 m between the cross streets, not 100")
	map.release("lot:a")
	_check(is_equal_approx(map.curb_gap(7, 1, 60.0, 30.0), 45.0), "fixed street: with the post gone, 30 m centred at 60 m (45)")


## The first few claims two maps differ on (to see why when they do).
func _diff(a: GroundMap, b: GroundMap) -> void:
	var na := a.all_claims().map(func(id): return a.name_of(id) + " " + a.kind_of(id) + " " + str(hash(a.claim(id).polys)))
	var nb := b.all_claims().map(func(id): return b.name_of(id) + " " + b.kind_of(id) + " " + str(hash(b.claim(id).polys)))
	var kinds := {}
	for n in na:
		if not n in nb:
			kinds[n.get_slice(" ", 1)] = int(kinds.get(n.get_slice(" ", 1), 0)) + 1
	for n in nb:
		if not n in na:
			kinds["+" + n.get_slice(" ", 1)] = int(kinds.get("+" + n.get_slice(" ", 1), 0)) + 1
	print("   differ by kind (+: only in the second): ", kinds)
	var shown := 0
	for n in na:
		if not n in nb and shown < 8:
			print("   only in the first: ", n)
			shown += 1
	shown = 0
	for n in nb:
		if not n in na and shown < 8:
			print("   only in the second: ", n)
			shown += 1


func _check_ask(map: GroundMap) -> void:
	# A mailbox in a home's curb cut: refused by the cut, its own lot's too.
	var cut := _first_of(map, "curb_cut", "lot:")
	var c := map.claim(cut)
	var mid: Vector2 = (c.box as Rect2).get_center()
	var box := GroundFootprints._sq(mid, 0.25)
	var asked := map.ask("post:mailbox", box, c.owner)
	_check(not asked.ok and map.name_of(cut) in asked.refused_by, "a mailbox in a drive's curb cut is refused by it (%s)" % str(asked.refused_by))
	# A house on the town's own ground: what it lands on and who wins.
	var house := _first_of(map, "building", "lot:")
	var hb: Rect2 = map.claim(house).box
	asked = map.ask("building", GroundFootprints._sq(hb.get_center(), 2.0), "lot:elsewhere")
	_check(not asked.ok and map.name_of(house) in asked.refused_by, "a building on another lot's building is refused by it")
	asked = map.ask("rail_bed:town", GroundFootprints._obb(hb.get_center(), Vector2.RIGHT, 20.0, 2.3), "rail:new")
	_check(asked.ok and map.name_of(house) in asked.gives_way, "a new track would take the house (rail ranks ahead): %s" % str(asked.gives_way))
	# Far out of town nothing is claimed.
	asked = map.ask("building", GroundFootprints._sq(Vector2(9000.0, 9000.0), 5.0), "lot:far")
	_check(asked.ok and asked.refused_by.is_empty() and asked.gives_way.is_empty(), "nothing is claimed far out of town")
	# Register and release put the map back as it was.
	var sig := map.signature()
	var id := map.register("lot:far", "building", "building", [GroundFootprints._sq(Vector2(9000.0, 9000.0), 5.0)])
	asked = map.ask("post:mailbox", GroundFootprints._sq(Vector2(9000.0, 9000.0), 0.25), "lot:other")
	_check(id >= 0 and map.signature() != sig and not asked.ok and "lot:far/building" in asked.refused_by,
		"a registered building refuses a post inside it")
	_check(map.release("lot:far") == 1 and map.signature() == sig and map.claims_of("lot:far").is_empty(),
		"releasing it puts the map back as it was")
	asked = map.ask("post:mailbox", GroundFootprints._sq(Vector2(9000.0, 9000.0), 0.25), "lot:other")
	_check(asked.ok, "and the spot is free again")


## The county railroad refuses a house on its track.
func _check_rail(map: GroundMap) -> void:
	var rail := _first_of(map, "rail_bed:county", "county:")
	_check(rail >= 0, "the county railroad is in the map")
	if rail < 0:
		return
	var piece: PackedVector2Array = map.claim(rail).polys[0]
	var at := Vector2.ZERO
	for v in piece:
		at += v / piece.size()
	var asked := map.ask("building", GroundFootprints._sq(at, 4.0), "lot:new")
	_check(not asked.ok and map.name_of(rail) in asked.refused_by, "a house on the county track is refused by it (%s)" % str(asked.refused_by))
	asked = map.ask("lot", GroundFootprints._sq(at, 8.0), "lot:new")
	_check(not asked.ok and map.name_of(rail) in asked.refused_by, "and so is a lot across it")


func _check_curb(map: GroundMap) -> void:
	var st := map.stats()
	_check(st.curb_sides > 50 and st.curb_claims > 200, "the curb ledger holds the town's curb (%d street sides, %d claims)" % [
		st.curb_sides, st.curb_claims])
	# Every side's list runs in order along the street.
	var ordered := true
	for k in map._ledger:
		var list: PackedInt32Array = map._ledger[k]
		for i in range(1, list.size()):
			ordered = ordered and map._curb_s[list[i - 1] * 2] <= map._curb_s[list[i] * 2]
	_check(ordered, "each street side's curb list runs in order along it")
	# A home's curb cut is found on its stretch.
	var cut := _first_of(map, "curb_cut", "lot:")
	var c := map.claim(cut)
	_check(not c.curb.is_empty(), "a home's curb cut is on a street side (%s)" % str(c.curb))
	if c.curb.is_empty():
		return
	var side_key: int = c.curb[0][0]
	var seg := side_key / 2
	var side := 1 if side_key % 2 == 1 else -1
	var s0: float = c.curb[0][1]
	var s1: float = c.curb[0][2]
	var spot := map.curb_spot((c.box as Rect2).get_center())
	_check(not spot.is_empty() and spot[0] == seg and spot[1] == side, "curb_spot finds the street side it stands on")
	_check(cut in map.curb_at(seg, side, s0, s1), "curb_at finds the cut on its stretch")
	_check(not cut in map.curb_at(seg, side, s1 + 0.5, s1 + 1.0) and not cut in map.curb_at(seg, -side, s0, s1),
		"and not past it, nor across the street")
	# 30 m of free curb near the cut (a far-side bus stop's length).
	var at := map.curb_gap(seg, side, (s0 + s1) * 0.5, 30.0)
	_check(at >= 0.0 and map.curb_at(seg, side, at, at + 30.0).is_empty(),
		"curb_gap finds 30 m of free curb near it (from %.1f m, the cut at %.1f-%.1f)" % [at, s0, s1])
	_check(map.curb_gap(seg, side, s0, 5000.0) < 0.0, "and says when there is none that long")
	# Something new on the curb is filed in order and found; released, gone.
	var sig := map.signature()
	var pad := map.register("stop:test", "pad", "curb_zone", [GroundFootprints._sq((c.box as Rect2).get_center(), 0.5)])
	_check(pad in map.curb_at(seg, side, s0, s1) and map.curb_gap(seg, side, (s0 + s1) * 0.5, 30.0) >= 0.0,
		"a registered curb zone is on the curb list")
	map.release("stop:test")
	_check(map.signature() == sig and not pad in map.curb_at(seg, side, s0 - 5.0, s1 + 5.0), "and released, gone")
	# A crosswalk lies across the street: on both its sides.
	var both := false
	for id in map.all_claims():
		if map.kind_of(id) == "crosswalk" and map.claim(id).curb.size() == 2:
			both = true
			break
	_check(both, "a crosswalk is on both sides of its street")


## The first live claim of `kind` whose owner starts `prefix` (-1: none).
func _first_of(map: GroundMap, kind: String, prefix: String) -> int:
	for id in map.all_claims():
		if map.kind_of(id) == kind and map._owner[id].begins_with(prefix):
			return id
	return -1


## What one ask costs: a mailbox-sized post and a house-sized building at
## every tenth piece of the town.
func _time_asks(map: GroundMap) -> void:
	var spots := []
	for p in range(0, map._p_claim.size(), 10):
		spots.append(map._piece_box(p).get_center())
	var t0 := Time.get_ticks_usec()
	for q in spots:
		map.ask("post:mailbox", GroundFootprints._sq(q, 0.25))
	var t1 := Time.get_ticks_usec()
	for q in spots:
		map.ask("building", GroundFootprints._sq(q, 5.0))
	var t2 := Time.get_ticks_usec()
	var post_us := float(t1 - t0) / spots.size()
	var house_us := float(t2 - t1) / spots.size()
	print("note: one ask costs %.0f us for a post, %.0f us for a building (%d asks each)" % [post_us, house_us, spots.size()])
	_check(post_us < 1000.0 and house_us < 2000.0, "an ask is quick (well under a millisecond for a post)")


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
