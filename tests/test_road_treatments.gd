extends SceneTree
## Road treatments, step 1 (docs/spec-road-treatments.md): factory and main
## street sides. Nathan, 2026-10-29: "If you build a road and then put
## factories on it then the factory treatment might get applied to the
## road... you'll have to figure out how to treat spaces where there are
## different things on either side of the road." He picked "A. Looks plus a
## few real rules" and "A. Right away" once the building is done.
## Checks: a side picks its kind from its frontage (40% to win, 15 points
## to take over, ties to what it has); a mixed street gets one kind a side
## and the middle follows the heavier use; a new factory flips its side
## right away once it's built, not while it goes up; the same town gives
## the same result, and the kept sums match a fresh count; the rules reach
## the traffic (truck route, no car parking, the main street speed); the road mesh dresses
## each side; a cut road keeps its sides; a lock is free to keep and costs
## a resurfacing to change; and saves, old and new, load the same.
## Run: godot --headless -s tests/test_road_treatments.gd

var _failed := false
## The main street speed on a street (Nathan's pick, 20 or 25).
const MPH := RoadTreatments.MAIN_MPH_STREET
## The cap the traffic keeps for a main street side on a street: none when MPH is the
## street's own limit.
var CAP: int = MPH if MPH < int(RoadStyle.TYPES[RoadStyle.Type.STREET].mph) else 0


func _init() -> void:
	_decide()
	var made := _town()
	var sim: CitySim = made[0]
	var seg: int = made[1]
	_mixed(sim, seg)
	_rules(sim, seg)
	_curb_furniture(sim)
	_same_town(sim)
	_saves(sim, seg)
	_new_factory()
	_mesh()
	_lock(sim, seg)
	_split(sim, seg)
	_undo_keeps_locks()
	_save_mid_change()
	_rebuilt_shop()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## The side rule, on its own.
func _decide() -> void:
	var F := RoadTreatments.FACTORY
	var H := RoadTreatments.HOMES
	var S := RoadTreatments.STRIP
	_check(RoadTreatments.decide("", {F: 0.6})[0] == F, "a side 60% factories becomes a factory side")
	_check(RoadTreatments.decide("", {F: 0.35})[0] == "", "35% isn't enough to take a side")
	_check(RoadTreatments.decide(H, {H: 0.6, S: 0.17})[0] == H,
		"one gas station on a block of homes (17%) changes nothing")
	_check(RoadTreatments.decide(H, {H: 0.45, F: 0.55})[0] == H, "10 points ahead isn't enough to take over")
	_check(RoadTreatments.decide(H, {H: 0.40, F: 0.56})[0] == F, "16 points ahead takes the side over")
	_check(RoadTreatments.decide("", {F: 0.5, H: 0.5})[0] == F, "a tie goes to the heavier use")
	_check(RoadTreatments.decide(H, {F: 0.5, H: 0.5})[0] == H, "a tie keeps what the side has")
	var gone := RoadTreatments.decide(F, {H: 0.2})
	_check(gone[0] == F and gone[1] and gone[2] == "", "a side whose factories are gone holds on, fading")
	_check(RoadTreatments.heavier(RoadTreatments.MAIN, F) == F and RoadTreatments.heavier("", H) == H,
		"the middle follows the heavier use")


## A small grid with one street lined with factories on one side and shops
## on the other, homes elsewhere, all built. Returns [sim, that street].
static func _town(fill := true) -> Array:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.require_utilities = false
	sim.charter.reached.merge({"town": 0, "city": 0})
	sim.apply({"type": "build_grid", "a": [0.0, 0.0], "b": [420.0, 0.0], "c": [0.0, 280.0], "block": 140.0})
	var target := -1
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var c := sim.network.curve_of(id)
		var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		# The middle east-west street's middle block.
		if absf(mid.z - 82.0) < 2.0 and absf(mid.x - 210.0) < 2.0:
			target = id
	for id in ids:
		for side in [-1, 1]:
			var zone := ZoneMap.Zone.RESIDENTIAL
			if id == target:
				zone = ZoneMap.Zone.INDUSTRIAL if side == -1 else ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone, "hold": true})
	sim.apply({"type": "zone_done"})
	sim.tick()
	if fill:
		_fill(sim)
	for i in 20:
		sim.tick()
	return [sim, target]


static func _fill(sim: CitySim, only := -1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for key in sim.empty_zoned_lots():
		if only >= 0 and int(sim.lots[key].seg) != only:
			continue
		var z := sim.zones.zone_at(sim.lots[key].zone_pt)
		var bseed := rng.randi()
		sim.buildings[key] = {"zone": z, "seed": bseed, "built": 0, "cap": CitySim.capacity(z, bseed), "occ": 0}
	sim.buildings_changed.emit()


func _mixed(sim: CitySim, seg: int) -> void:
	var t := sim.treatments
	_check(seg >= 0, "the test street is there")
	_check(t.kind(seg, -1) == RoadTreatments.FACTORY, "the factory side is a Factory side (got %s, %s)"
		% [t.kind(seg, -1), t.shares.get(RoadTreatments.key_of(seg, -1))])
	_check(t.kind(seg, 1) == RoadTreatments.MAIN, "the shop side is a Main street side (got %s, %s)"
		% [t.kind(seg, 1), t.shares.get(RoadTreatments.key_of(seg, 1))])
	_check(t.mid(seg) == RoadTreatments.FACTORY, "the middle of a mixed street follows the factories")
	var homes := 0
	for k in t.sides:
		if t.sides[k].kind == RoadTreatments.HOMES:
			homes += 1
	_check(homes > 4, "the home streets are judged as homes (%d sides)" % homes)
	var rows := t.rows(sim, seg)
	var text := str(rows)
	_check("Factory" in text and "Main street" in text and "Truck route" in text and (CAP == 0 or ("%d mph" % MPH) in text)
		and "No parking on the" in text, "the road's card says each side, why, and the rules: %s" % text)
	var card := Inspect.describe(sim, {"type": "road", "id": seg})
	_check(str(card.rows).contains("%d mph" % MPH) and not card.get("actions", []).is_empty(),
		"the click card shows it, with the lock buttons")


## Lanterns, benches, bins and NO PARKING signs are curb furniture: each
## stands where CurbClaims says the curb is free (off drive cuts, ramps and
## crosswalks).
func _curb_furniture(sim: CitySim) -> void:
	var claims := CurbClaims.of(sim)
	var p := TreatmentView.plan(sim)
	var bad := []
	var n := 0
	for xf: Transform3D in p.lanterns:
		n += 1
		if not claims.is_free(Vector2(xf.origin.x, xf.origin.z), TreatmentView.LANTERN_HALF):
			bad.append(["lantern", xf.origin])
	var halves := {"bench": TreatmentView.BENCH_HALF, "bin": TreatmentView.BIN_HALF, "no_parking": TreatmentView.SIGN_HALF}
	for sq in p.props:
		for e in p.props[sq]:
			n += 1
			var o: Vector3 = e[1].origin
			if not claims.is_free(Vector2(o.x, o.z), halves[e[0]]):
				bad.append([e[0], o])
	_check(n > 0 and bad.is_empty(), "curb furniture stands only on free curb (%d placed, in the way: %s)" % [n, bad.slice(0, 4)])


func _rules(sim: CitySim, seg: int) -> void:
	var tr := sim.traffic
	_check(tr.treat_trucks.has(seg), "the factory street is a truck route")
	_check(tr.no_parking.has(seg * 2) and not tr.no_parking.has(seg * 2 + 1), "no car parking on the factory side only")
	_check(tr.no_aprons.has(seg * 2 + 1), "no driveway cuts on the main street side")
	_check(int(tr.treat_mph.get(seg, 0)) == CAP, "a main street side holds the street to %d mph" % MPH)
	var w: Dictionary = tr.ways.get(seg * 2 + 1, {})
	_check(not w.is_empty() and absf(float(w.vmax) - MPH * RoadStyle.MPH) < 0.01,
		"its lanes run at %d mph (%.2f m/s)" % [MPH, float(w.get("vmax", 0.0))])
	# Truck routes law: the factory street is a preference for through
	# trucks (half the extra a home street costs), never free and never
	# shut, so trucks spread over the town's roads instead of all taking it.
	tr.truck_routes = true
	tr._tpen_key = []
	var pen := tr._truck_pen()
	var home_seg := -1
	for id in sim.network.segments:
		if sim.treatments.kind(id, -1) == RoadTreatments.HOMES and sim.treatments.kind(id, 1) == RoadTreatments.HOMES \
				and not tr.treat_trucks.has(id) and pen.has(id * 2 + 1):
			home_seg = id
			break
	var per_m_route := _extra_per_m(tr, pen, seg * 2 + 1)
	var per_m_home := _extra_per_m(tr, pen, home_seg * 2 + 1)
	_check(home_seg >= 0 and per_m_route > 0.0 and absf(per_m_route - per_m_home * TrafficSim.TRUCK_ROUTE_SHARE) < 0.01,
		"under the Truck routes law the factory street costs through trucks half a home street's extra (%.2f vs %.2f)"
		% [per_m_route, per_m_home])
	tr.truck_routes = false
	# A car parks across the street from a factory; a truck may stand to load.
	var stop := {"seg": seg, "at_frac": 0.5, "side": -1}
	var line := tr._curb_line(stop)
	var pl := {"ref": "lot:test", "spots": [], "taken": [], "stop": stop}
	tr._places["lot:test"] = pl
	var car := tr._new_curb(pl, stop, -1, 4.8)
	var truck := tr._new_curb(pl, stop, -1, 10.0)
	_check(car >= 0 and truck >= 0, "a car and a truck both find curb")
	if car >= 0 and truck >= 0:
		var mid: Vector3 = tr._poly_point(line[0].pts, line[0].cum, float(line[1]))
		var n := Vector3(-float(line[0].pts[1].z - line[0].pts[0].z), 0.0, float(line[0].pts[1].x - line[0].pts[0].x)).normalized()
		var car_side := signf((pl.spots[car].pos - mid).dot(n))
		var truck_side := signf((pl.spots[truck].pos - mid).dot(n))
		_check(car_side != truck_side, "the car parks on the far curb, the truck at the factory's")
	tr._places.erase("lot:test")


## A way's extra seconds for a truck under the law, per second of driving.
static func _extra_per_m(tr: TrafficSim, pen: Dictionary, wid: int) -> float:
	if not tr.ways.has(wid):
		return 0.0
	var w: Dictionary = tr.ways[wid]
	return float(pen.get(wid, 0.0)) / (float(w.len) / float(w.vmax))


## The same town built twice comes out the same; the kept sums match a
## fresh count.
func _same_town(sim: CitySim) -> void:
	var again: CitySim = _town()[0]
	_check(JSON.stringify(again.treatments.to_dict()) == JSON.stringify(sim.treatments.to_dict()),
		"the same town gives the same treatments")
	_check(JSON.stringify(sim.treatments.frontage(sim)) == JSON.stringify(_sorted(sim.treatments.shares)),
		"the kept frontage sums match a fresh count")


static func _sorted(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out


func _saves(sim: CitySim, seg: int) -> void:
	var data := sim.to_dict()
	_check(data.has("road_treatments") and not data.road_treatments.sides.is_empty(), "a save carries the treatments")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(copy.treatments.kind(seg, -1) == RoadTreatments.FACTORY and copy.treatments.kind(seg, 1) == RoadTreatments.MAIN,
		"a loaded town has its sides at once")
	_check(int(copy.traffic.treat_mph.get(seg, 0)) == CAP and copy.traffic.treat_trucks.has(seg),
		"and the traffic has its rules before its first tick")
	for i in 40:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.treatments.to_dict()) == JSON.stringify(sim.treatments.to_dict()),
		"a loaded copy carries on the same")
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	old.erase("road_treatments")
	var was := CitySim.new()
	was.from_dict(old)
	_check(was.treatments.sides.is_empty(), "a town saved before treatments loads with none")
	for i in 20:
		was.tick()
	_check(was.treatments.kind(seg, -1) == RoadTreatments.FACTORY and was.treatments.kind(seg, 1) == RoadTreatments.MAIN,
		"and works them out on its first look")


## Factories built along a street flip its side right away once they're
## done, not while they go up.
func _new_factory() -> void:
	var made := _town(false)
	var sim: CitySim = made[0]
	var seg: int = made[1]
	_check(sim.treatments.kind(seg, -1) == "", "an empty side has no treatment")
	_fill(sim, seg)
	var keys := []
	for key in sim.buildings:
		if int(sim.lots[key].seg) == seg and int(sim.lots[key].side) == -1:
			keys.append(key)
			var lot: Dictionary = sim.lots[key]
			sim.construction.start("lot:" + key, "factory", sim.tick_count, lot.front, -lot.normal, lot.to_curb)
	for i in 12:
		sim.tick()
	_check(sim.treatments.kind(seg, -1) == "", "factories still going up don't change the side")
	var done := int(sim.construction.sites["lot:" + keys[0]].start) + Construction.duration("factory")
	while sim.tick_count < done:
		sim.tick()
	for i in RoadTreatments.EVERY:
		sim.tick()
	_check(sim.treatments.kind(seg, -1) == RoadTreatments.FACTORY, "once they're done the side is a Factory side")


func _mesh() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(60, 0, 0), Vector3(120, 0, 0)])
	var mats := {}
	for k in ["asphalt", "curb", "curb_face", "walk", "median", "yellow", "white", "concrete", "brick"]:
		mats[k] = StandardMaterial3D.new()
	var plain := RoadMesh.street(pts, RoadStyle.Type.STREET, mats)
	var treat := RoadMesh.street(pts, RoadStyle.Type.STREET, mats, {}, false, Vector2.ZERO, [], false, Vector2.ONE,
		{"left": RoadTreatments.FACTORY, "right": RoadTreatments.MAIN, "mid": RoadTreatments.FACTORY})
	var used_plain := _materials(plain, mats)
	var used := _materials(treat, mats)
	_check(not "concrete" in used_plain and "concrete" in used and not "asphalt" in used,
		"a factory middle is concrete (%s)" % [used])
	_check(treat.get_surface_count() == plain.get_surface_count(),
		"a treated road draws no more parts than a plain one (%d, %d)" % [plain.get_surface_count(), treat.get_surface_count()])
	# The walks: narrow at the back on the factory side, curb to storefront
	# on the main street side.
	var walk := _walk_span(treat, mats, -1.0)
	var main := _walk_span(treat, mats, 1.0)
	var hw := RoadStyle.half_width(RoadStyle.Type.STREET)
	_check(absf(walk.y - walk.x - 1.2) < 0.05, "the factory side's walk is 4 ft (%.2f m)" % (walk.y - walk.x))
	_check(main.x < hw + RoadStyle.CURB_WIDTH + 0.05, "the main street side is paved from the curb (%.2f m out)" % main.x)
	# The desktop's raised curbs: the joints and stalls ride on parts the
	# road already has.
	for k in ["iron", "drain", "wear"]:
		mats[k] = StandardMaterial3D.new()
	RoadMesh.raised_curbs = true
	var plain_hi := RoadMesh.street(pts, RoadStyle.Type.STREET, mats)
	var treat_hi := RoadMesh.street(pts, RoadStyle.Type.STREET, mats, {}, false, Vector2.ZERO, [], false, Vector2.ONE,
		{"left": RoadTreatments.FACTORY, "right": RoadTreatments.MAIN, "mid": RoadTreatments.FACTORY})
	RoadMesh.raised_curbs = false
	_check(treat_hi.get_surface_count() == plain_hi.get_surface_count()
		and _count(treat_hi, mats.drain) > _count(plain_hi, mats.drain) and _count(treat_hi, mats.curb) > _count(plain_hi, mats.curb),
		"with raised curbs too: joints and stall ticks added to parts it has (%d, %d)"
		% [plain_hi.get_surface_count(), treat_hi.get_surface_count()])


static func _count(mesh: ArrayMesh, mat: Material) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		if mesh.surface_get_material(i) == mat:
			n += mesh.surface_get_array_len(i)
	return n


## How far out a road's walk reaches on one side: (inner, outer), metres.
static func _walk_span(mesh: ArrayMesh, mats: Dictionary, side: float) -> Vector2:
	var lo := INF
	var hi := 0.0
	for i in mesh.get_surface_count():
		if mesh.surface_get_material(i) != mats.walk:
			continue
		for v: Vector3 in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			if signf(v.z) == side and absf(v.x - 60.0) < 30.0:
				lo = minf(lo, absf(v.z))
				hi = maxf(hi, absf(v.z))
	return Vector2(lo, hi)


static func _materials(mesh: ArrayMesh, mats: Dictionary) -> Array:
	var out := []
	for i in mesh.get_surface_count():
		for k in mats:
			if mesh.surface_get_material(i) == mats[k]:
				out.append(k)
	return out


func _lock(sim: CitySim, seg: int) -> void:
	var t := sim.treatments
	var money: int = sim.economy.money
	_check(sim.apply({"type": "road_treatment", "seg": seg, "side": 1, "kind": RoadTreatments.MAIN}),
		"lock the main street side as it is")
	_check(sim.economy.money == money, "keeping what's there is free")
	var cost := t.lock_cost(sim, seg, -1, RoadTreatments.MAIN)
	var type: int = sim.network.segments[seg].type
	_check(cost > 0 and cost == StreetAge.repave_cost(t.seg_length(sim, seg) * RoadStyle.TYPES[type].lanes, type),
		"changing a side costs what resurfacing the road piece costs ($%d)" % cost)
	_check(sim.apply({"type": "road_treatment", "seg": seg, "side": -1, "kind": RoadTreatments.MAIN}),
		"make the factory side a main street")
	_check(sim.economy.money == money - cost and t.kind(seg, -1) == RoadTreatments.MAIN, "it is, and it was paid for")
	_check(t.mid(seg) == RoadTreatments.MAIN and not t.truck_route(seg) and not sim.traffic.treat_trucks.has(seg),
		"paid for as a resurfacing, the middle is laid new at once: no concrete truck route (%s)" % t.mid(seg))
	for i in 30:
		sim.tick()
	_check(t.kind(seg, -1) == RoadTreatments.MAIN, "a locked side never changes on its own")
	sim.apply({"type": "road_treatment", "seg": seg, "side": -1, "kind": "auto"})
	for i in 30:
		sim.tick()
	_check(t.kind(seg, -1) == RoadTreatments.FACTORY, "back on Auto, the factories take it back (60 points ahead)")


func _split(sim: CitySim, seg: int) -> void:
	var t := sim.treatments
	var before := t.kind(seg, -1)
	var c := sim.network.curve_of(seg)
	var at := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
	sim.apply({"type": "build_road", "start": [at.x, at.z], "ctrl": [at.x, at.z + 40.0], "end": [at.x, at.z + 80.0]})
	_check(not sim.network.segments.has(seg), "a road joined the street mid-block")
	var halves := []
	for id in sim.network.segments:
		var cc := sim.network.curve_of(id)
		var m := RoadNetwork.bezier(cc[0], cc[1], cc[2], 0.5)
		if absf(m.z - 82.0) < 2.0 and m.x > 140.0 and m.x < 280.0:
			halves.append(id)
	_check(halves.size() == 2 and t.kind(halves[0], -1) == before and t.kind(halves[1], -1) == before,
		"both halves keep the side's treatment")
	var tr := sim.traffic
	var ruled := 0
	for h in halves:
		if int(tr.treat_mph.get(h, 0)) == CAP and tr.treat_trucks.has(h) and tr.no_parking.has(h * 2) \
				and tr.no_aprons.has(h * 2 + 1):
			ruled += 1
	_check(halves.size() == 2 and ruled == 2, "and the traffic has both halves' rules at once")
	_check(not tr.treat_mph.has(seg) and not tr.treat_trucks.has(seg) and not tr.no_parking.has(seg * 2),
		"the cut road piece's own rules are gone")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(_rules_of(copy.traffic) == _rules_of(tr), "the live town's rules equal a reloaded copy's")


static func _rules_of(tr: TrafficSim) -> String:
	var out := []
	for d: Dictionary in [tr.treat_mph, tr.treat_trucks, tr.no_parking, tr.no_aprons]:
		var keys := d.keys()
		keys.sort()
		out.append(keys.map(func(k): return [int(k), d[k]]))
	return JSON.stringify(out)


## Lock a side, draw a cross street, undo: the lock is back, and a change
## paid for on the new road's pieces is refunded with the road.
func _undo_keeps_locks() -> void:
	var made := _town()
	var sim: CitySim = made[0]
	var seg: int = made[1]
	var t := sim.treatments
	sim.apply({"type": "road_treatment", "seg": seg, "side": 1, "kind": RoadTreatments.MAIN})
	var money: float = sim.economy.money
	var c := sim.network.curve_of(seg)
	var at := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
	_check(sim.apply({"type": "build_road", "start": [at.x, at.z], "ctrl": [at.x, at.z + 40.0], "end": [at.x, at.z + 80.0]}),
		"a cross street cuts the locked block")
	var half := -1
	for id in sim.network.segments:
		if t.locks.has(id * 2 + 1):
			half = id
	_check(half >= 0 and not sim.network.segments.has(seg), "its halves carry the lock")
	var paid := t.lock_cost(sim, half, -1, RoadTreatments.MAIN)
	sim.apply({"type": "road_treatment", "seg": half, "side": -1, "kind": RoadTreatments.MAIN})
	_check(paid > 0 and t.kind(half, -1) == RoadTreatments.MAIN, "a half's factory side made a main street, paid")
	_check(sim.apply({"type": "undo"}), "undo the cross street")
	_check(sim.network.segments.has(seg) and t.locks.get(seg * 2 + 1, "") == RoadTreatments.MAIN
		and t.kind(seg, 1) == RoadTreatments.MAIN and t.kind(seg, -1) == RoadTreatments.FACTORY,
		"the block is back with its lock and its factory side")
	_check(absf(sim.economy.money - money) < 1.0, "the road and the paid change are both refunded (%.0f vs %.0f)"
		% [sim.economy.money, money])
	_check(int(sim.traffic.treat_mph.get(seg, 0)) == CAP and sim.traffic.treat_trucks.has(seg), "and its rules are back")
	# Draw a road, then pay to change a street it never touched, then undo:
	# that street keeps its change and nothing of it is refunded.
	var other := -1
	for id in sim.network.segments:
		if id != seg and t.kind(id, -1) == RoadTreatments.HOMES and absf(sim.network.curve_of(id)[0].x - 420.0) > 1.0 \
				and sim.network.curve_of(id)[0].z > 150.0:
			other = id
			break
	var before_road: float = sim.economy.money
	_check(sim.apply({"type": "build_road", "start": [at.x, at.z], "ctrl": [at.x, at.z + 40.0], "end": [at.x, at.z + 80.0]}),
		"the cross street again")
	var cost := t.lock_cost(sim, other, -1, RoadTreatments.MAIN)
	sim.apply({"type": "road_treatment", "seg": other, "side": -1, "kind": RoadTreatments.MAIN})
	_check(other >= 0 and cost > 0 and t.kind(other, -1) == RoadTreatments.MAIN, "another street's side made a main street, paid")
	var paved_at: int = sim.street_age.paved.get(StreetAge.cell_of(sim, other), -1)
	_check(paved_at == sim.tick_count, "paid as a resurfacing, its resurfacing clock starts again")
	_check(sim.apply({"type": "undo"}), "undo the cross street")
	_check(t.kind(other, -1) == RoadTreatments.MAIN and t.locks.get(other * 2, "") == RoadTreatments.MAIN
		and sim.traffic.no_aprons.has(other * 2),
		"the other street keeps its paid change and lock")
	_check(absf(sim.economy.money - (before_road - cost)) < 1.0,
		"the road is refunded, the other street's change isn't (%.0f vs %.0f)" % [sim.economy.money, before_road - cost])
	_check(sim.network.segments.has(seg) and t.locks.get(seg * 2 + 1, "") == RoadTreatments.MAIN,
		"and the cut block is back with its lock")


## Frontage that changed just before a save is judged after the load, as
## the town that saved judges it.
func _save_mid_change() -> void:
	var made := _town(false)
	var sim: CitySim = made[0]
	var seg: int = made[1]
	while sim.tick_count % RoadTreatments.EVERY != 0:
		sim.tick()
	_fill(sim, seg)  # factories done, between two looks
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for i in RoadTreatments.EVERY + 2:
		sim.tick()
		copy.tick()
	_check(sim.treatments.kind(seg, -1) == RoadTreatments.FACTORY and copy.treatments.kind(seg, -1) == RoadTreatments.FACTORY,
		"a side that changed just before the save is judged after the load too")
	_check(JSON.stringify(copy.treatments.to_dict()) == JSON.stringify(sim.treatments.to_dict()),
		"the loaded copy and the town that saved agree")


## A shop rebuilt in place counts as what stood there till it's done, and a
## main street whose shops drop under two stays one through the hold, not
## Strip and back.
func _rebuilt_shop() -> void:
	var made := _town()
	var sim: CitySim = made[0]
	var seg: int = made[1]
	var t := sim.treatments
	var shops := []
	for key in sim.buildings:
		if int(sim.lots[key].seg) == seg and int(sim.lots[key].side) == 1:
			shops.append(key)
	shops.sort()
	_check(t.kind(seg, 1) == RoadTreatments.MAIN and shops.size() >= 2, "a main street side with %d shops" % shops.size())
	var share: float = t.shares.get(seg * 2 + 1, {}).get(RoadTreatments.MAIN, 0.0)
	# Each shop but one rebuilt at once (redevelopment.gd's way: a new record
	# and its construction).
	for key in shops.slice(1):
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key].duplicate()
		b.built = sim.tick_count
		sim.buildings[key] = b
		sim.construction.start("lot:" + key, "shop", sim.tick_count, lot.front, -lot.normal, lot.to_curb)
	sim.buildings_changed.emit()
	for i in 2 * RoadTreatments.EVERY:
		sim.tick()
	_check(t.kind(seg, 1) == RoadTreatments.MAIN and is_equal_approx(float(t.shares.get(seg * 2 + 1, {}).get(RoadTreatments.MAIN, 0.0)), share),
		"while they're rebuilt they count as the shops they were: still a main street")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for i in RoadTreatments.EVERY:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.treatments.to_dict()) == JSON.stringify(sim.treatments.to_dict())
		and is_equal_approx(float(copy.treatments.shares.get(seg * 2 + 1, {}).get(RoadTreatments.MAIN, 0.0)), share),
		"a save mid-rebuild keeps counting them")
	# Now they're gone for good: one shop left, too few for a main street.
	for key in shops.slice(1):
		sim.buildings.erase(key)
		sim.construction.sites.erase("lot:" + key)
	sim.buildings_changed.emit()
	for i in 2 * RoadTreatments.EVERY:
		sim.tick()
	_check(t.kind(seg, 1) == RoadTreatments.MAIN and t._fading.has(seg * 2 + 1),
		"down to one shop, the side stays a main street and starts its hold (%s)" % t.kind(seg, 1))
	var fade: int = t.sides[seg * 2 + 1].fade
	t._decide_all(sim, [seg * 2 + 1])
	sim.tick_count = fade + RoadTreatments.HOLD
	t._decide_all(sim, [seg * 2 + 1])
	_check(t.kind(seg, 1) != RoadTreatments.MAIN, "after the hold it lets go (%s)" % t.kind(seg, 1))

