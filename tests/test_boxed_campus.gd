extends SceneTree
## Run: godot --headless -s tests/test_boxed_campus.gd
## A bank, a campus and the phone company boxed in by roads fill their
## block up to the sidewalk (Nathan, 2026-10-26: "when a hub with leader is
## "trapped" inside a road area, it should nicely fill in that area up to
## the edge (sidewalk) so that it looks like its using its space well."):
## edge pieces cut back to the roads (BlockEdges), grounds only, never over
## a road, never on zoned or built lots or painted zoning, kept by a save
## byte for byte, cut back by a road built later and fitted out again when
## it goes, and seen by Move It.
var _fails := 0

## Each kind's ring: x of its middle, its block size, the gap left beside
## and behind its first block before the sidewalk's setback.
const KINDS := {
	"bank": {"x": 0.0, "cell": Banks.CELL, "side": 14.0, "back": 20.0, "remove": "remove_bank_block"},
	"telecom": {"x": 260.0, "cell": Telecom.CELL, "side": 15.0, "back": 22.0, "remove": "remove_telecom_at"},
	"campus": {"x": -420.0, "cell": Education.CELL, "side": 30.0, "back": 45.0, "remove": "remove_campus_block"},
}


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


static func _hubs(sim: CitySim, kind: String) -> Dictionary:
	match kind:
		"bank": return sim.banks.banks
		"telecom": return sim.telecom.companies
	return sim.education.campuses


static func _owner(sim: CitySim, kind: String) -> Object:
	match kind:
		"bank": return sim.banks
		"telecom": return sim.telecom
	return sim.education


static func _name(sim: CitySim, kind: String, b: Dictionary) -> String:
	match kind:
		"bank": return str(b.name)
		"telecom": return "phone company"
	return Education.KINDS[b.kind].name.to_lower()


## How far a point is from the nearest road's right of way plus the gap the
## hubs keep (negative: over it).
func _clear_of_roads(sim: CitySim, p: Vector2) -> float:
	var best := INF
	for id in sim.network.segments:
		var w := RoadStyle.right_of_way_half(sim.network.segments[id].type) + CivicHubs.SETBACK
		var pts := sim.network.sample_segment(id, 64)
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - w)
	return best


func _road(sim: CitySim, a: Array, b: Array) -> void:
	sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})


## The ring of streets round kind `k`'s block: [west x, east x, back z].
func _ring(sim: CitySim, k: Dictionary, row: float) -> Array:
	var half: float = k.cell * 0.5 + k.side + row
	var back: float = -(row + k.cell + k.back + row)
	var w: float = k.x - half
	var e: float = k.x + half
	for r in [[[w, 0], [e, 0]], [[e, 0], [e, back]], [[e, back], [w, back]], [[w, back], [w, 0]]]:
		_road(sim, r[0], r[1])
	return [w, e, back]


func _place(sim: CitySim, kind: String, k: Dictionary) -> bool:
	var hit := Vector3(k.x, 0, -20)
	match kind:
		"bank":
			var s := Banks.site_near(sim.network, hit)
			return sim.apply({"type": "place_bank", "kind": "community", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
		"telecom":
			var s := Telecom.site_near(sim.network, hit)
			return sim.apply({"type": "place_telecom", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
	var s := Education.site_near(sim.network, hit)
	return sim.apply({"type": "place_campus", "kind": "high_school", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})


func _no_edge_over_roads(sim: CitySim, b: Dictionary, cell: float) -> bool:
	for poly in BlockEdges.edge_polys(b, cell):
		if Services.road_clash(sim.network, poly):
			return false
		for q in poly:
			if _clear_of_roads(sim, q) < -0.05:
				return false
	return true


static func _edge_area(b: Dictionary) -> float:
	var a := 0.0
	for c in b.get("edge", {}):
		a += CivicHubs.area(b.edge[c])
	return a


func _new_town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.simulate_traffic = false
	return sim


func _init() -> void:
	var sim := _new_town()
	_road(sim, [-5, 0], [5, 0])
	var row := RoadStyle.right_of_way_half(sim.network.segments.values()[0].type) + CivicHubs.SETBACK
	sim.apply({"type": "remove_road", "seg": sim.network.segments.keys()[0]})
	var rings := {}
	for kind in KINDS:
		rings[kind] = _ring(sim, KINDS[kind], row)
	for kind in KINDS:
		_check(_place(sim, kind, KINDS[kind]), "a %s goes in on its block's front street" % kind)
	# Houses zoned along the inside of each block's east street.
	for kind in KINDS:
		var e: float = rings[kind][1]
		for z in range(-15, int(rings[kind][2]) + 10, -10):
			sim.apply({"type": "paint_zone", "center": [e - 8, z], "radius": 9, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 400:
		sim.tick()
	var zoned := {}
	for kind in KINDS:
		zoned[kind] = []
		var e: float = rings[kind][1]
		for key in sim.lots:
			var lot: Dictionary = sim.lots[key]
			if lot.pos.x > e - 40.0 and lot.pos.x < e and lot.pos.z < -5.0 and lot.pos.z > rings[kind][2] + 5.0 \
					and (sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE):
				zoned[kind].append(key)
	var blocks0 := {}
	for kind in KINDS:
		var b: Dictionary = _hubs(sim, kind).values()[0]
		blocks0[kind] = b.blocks.size()
		_check(b.edge.is_empty(), "a new %s has no edge pieces" % kind)

	var n_zoned := 0
	for kind in KINDS:
		n_zoned += zoned[kind].size()
	_check(n_zoned > 0, "lots zoned along the east streets (%d)" % n_zoned)
	# A few rounds of each one's leader: boxed in, it takes its edge pieces.
	for i in 1440 * (BlockEdges.EVERY * 2 + 1):
		sim.tick()
	for kind in KINDS:
		_kind_checks(sim, kind, rings[kind], row, zoned[kind], blocks0[kind])

	# Save, load: byte for byte the same, and the copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for kind in KINDS:
		var id: int = _hubs(sim, kind).keys()[0]
		_check(_hubs(copy, kind)[id].edge == _hubs(sim, kind)[id].edge, "a save keeps every %s edge piece exactly" % kind)
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "a loaded copy saves byte for byte the same")
	for i in 1440 * 2:
		sim.tick()
		copy.tick()
	for kind in KINDS:
		var id: int = _hubs(sim, kind).keys()[0]
		var mine: Dictionary = _hubs(sim, kind)[id]
		var theirs: Dictionary = _hubs(copy, kind)[id]
		_check(theirs.edge == mine.edge and JSON.stringify(theirs.blocks) == JSON.stringify(mine.blocks),
			"%s copies keep the same land as they go" % kind)
	# An older save, without edge pieces, still loads.
	var old := sim.to_dict()
	for k in old.banks.banks:
		old.banks.banks[k].erase("edge")
	for k in old.telecom.companies:
		old.telecom.companies[k].erase("edge")
	for k in old.education.campuses:
		old.education.campuses[k].erase("edge")
	var aged := CitySim.new()
	aged.from_dict(JSON.parse_string(JSON.stringify(old)))
	for kind in KINDS:
		_check(_hubs(aged, kind).values()[0].edge.is_empty(), "an older save loads with no %s edge pieces" % kind)
		_check(not JSON.stringify(_owner(aged, kind).to_dict()).contains("\"edge\""),
			"and saves the %s the old way until it takes some" % kind)

	for kind in KINDS:
		_road_checks(sim, kind, rings[kind], row)
	_zoned_cells(row)
	print("boxed campus, bank and phone company: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)


func _kind_checks(sim: CitySim, kind: String, ring: Array, row: float, zoned: Array, blocks0: int) -> void:
	var k: Dictionary = KINDS[kind]
	var cell: float = k.cell
	var owner := _owner(sim, kind)
	var id: int = _hubs(sim, kind).keys()[0]
	var b: Dictionary = _hubs(sim, kind)[id]
	_check(b.blocks.size() == blocks0, "boxed in, the %s never bought a whole block (%d)" % [kind, b.blocks.size()])
	# It faces +z: its own right (+x along its road) runs west.
	_check(b.edge.has(Vector2i(1, 0)) and b.edge.has(Vector2i(0, 1)) and b.edge.has(Vector2i(1, 1)),
		"the %s took edge pieces up to the west and back streets and the corner between (%s)" % [kind,
		str(b.edge.keys())])
	_check(_no_edge_over_roads(sim, b, cell), "no %s edge piece reaches over a street's sidewalk and the gap" % kind)
	var nearest := INF
	for poly in BlockEdges.edge_polys(b, cell):
		for q in poly:
			nearest = minf(nearest, _clear_of_roads(sim, q))
	_check(nearest < 0.5, "%s edge pieces reach right up to the sidewalk gap (%.2f m)" % [kind, nearest])
	# The west side, the back and the back corner are its own up to the sidewalk.
	var west: float = ring[0] + row + 1.0
	var back: float = ring[2] + row + 1.0
	var mid_z := -(row + cell * 0.5)
	_check(owner.covers(Vector3(west, 0, mid_z)) and owner.at(Vector3(west, 0, mid_z)) == id,
		"land by the west sidewalk is the %s's" % kind)
	# (West of the middle: a house on the east street runs into the back gap.)
	_check(owner.covers(Vector3(k.x - cell * 0.3, 0, back)), "land by the back street's sidewalk is the %s's" % kind)
	_check(owner.covers(Vector3(west, 0, back)), "and the %s's back corner" % kind)
	_check(not owner.covers(Vector3(west - 3.0, 0, mid_z)), "the sidewalk itself is not the %s's" % kind)
	# Nothing taken from the zoned and built lots, and no lot left on its land.
	print("  (%d lots zoned along the %s's east street)" % [zoned.size(), kind])
	var taken := false
	for key in zoned:
		var lot: Dictionary = sim.lots.get(key, {})
		if lot.is_empty():
			continue
		for poly in BlockEdges.edge_polys(b, cell):
			for q in Geometry2D.intersect_polygons(poly, lot.corners):
				taken = taken or CivicHubs.area(q) > 1.0
	_check(not taken, "no zoned or built lot was taken by the %s" % kind)
	var under := false
	for key in sim.lots:
		under = under or BlockEdges.on_edge(b, cell, sim.lots[key].pos)
	_check(not under, "no lot is left on the %s's edge land" % kind)
	# Grounds only: never a block on an edge piece, nothing tall drawn on it.
	var on_block := false
	for blk in b.blocks:
		on_block = on_block or b.edge.has(blk.c)
	_check(not on_block and not b.edge.has(Vector2i.ZERO), "no %s block stands on an edge piece" % kind)
	var cells := [Vector2i.ZERO]
	for blk in b.blocks:
		cells.append(blk.c)
	var built: Array
	match kind:
		"bank": built = BankBuilder.build_edge(b.edge, 7)
		"telecom": built = TelecomBuilder.build_edge(b.edge, cells, 7)
		_: built = CampusBuilder.build_edge(b.edge, 7)
	var things: ArrayMesh = built[0]
	var tall := 0.0
	if things.get_surface_count() > 0:
		tall = things.get_aabb().end.y
	_check(tall < 3.2, "the %s's edge land is grounds only, nothing over 3.2 m (%.1f m)" % [kind, tall])
	var flat: ArrayMesh = built[1]
	_check(flat.get_surface_count() > 0 and flat.surface_get_array_len(0) > 0, "its edge land is drawn (%s)" % kind)
	var off := false
	var front := {"pos": b.pos + b.dir * (cell * 0.5), "dir": b.dir}
	for t in built[2]:
		var q := CivicHubs.to_world(front, Vector2(t[0].x, t[0].z))
		off = off or owner.at(Vector3(q.x, 0, q.y)) != id
	_check(not built[2].is_empty() and not off, "%d %s trees, every one on its land" % [built[2].size(), kind])
	var far := 0.0
	for i in flat.get_surface_count():
		for v in flat.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			var q := CivicHubs.to_world(front, Vector2(v.x, v.z))
			far = maxf(far, -_clear_of_roads(sim, q))
	# (A parking lot's drive crosses the sidewalk to the curb, as any drive.)
	var to_curb := CivicHubs.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	_check(far < to_curb + 0.1, "nothing of the %s's grounds runs further out than the curb (%.2f m past the gap)" % [kind, far])
	# Something else can't take its edge land.
	var poly0: PackedVector2Array = BlockEdges.edge_polys(b, cell)[0]
	var inside := CivicHubs._inner_pts(poly0, 4.0)
	_check(sim.hubs._ground_problem(sim, poly0, inside, -1, true, false) != "",
		"a landfill or post office can't take the %s's edge land" % kind)
	_check(sim.parks.ground_problem(sim, poly0) != "", "nor a park")
	# Nor can Move It set a building down on it.
	var feed := Services.site_near(sim.network, Services.Kind.POWER_FEED, Vector3(k.x, 0, 30))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.POWER_FEED, "pos": [feed[0].x, feed[0].z],
		"dir": [feed[1].x, feed[1].z]}), "a power line feed goes in across the %s's front street" % kind)
	var fid: int = sim.services.buildings.keys()[-1]
	var mid := Vector3.ZERO
	var west_piece := PackedVector2Array()
	for poly in BlockEdges.edge_polys(b, cell):
		if Geometry2D.is_point_in_polygon(Vector2(west, mid_z), poly):
			west_piece = poly
	for q in west_piece:
		mid += Vector3(q.x, 0, q.y)
	mid /= maxf(1.0, west_piece.size())
	var fpos: Vector3 = sim.services.buildings[fid].pos
	var mv := MoveIt.plan(sim, MoveIt.command([{"type": "service", "id": fid}], fpos, Vector3(mid.x, 0, mid.z) - fpos))
	_check(str(mv.problem).contains(_name(sim, kind, b)), "Move It can't set a building down on the %s's edge land (%s)" %
		[kind, mv.problem])
	var away := MoveIt.plan(sim, MoveIt.command([{"type": "service", "id": fid}], fpos, Vector3(-12, 0, 0)))
	_check(away.problem == "", "but can move it along its own street (%s)" % away.problem)
	sim.apply({"type": "remove_service", "id": fid})
	# Edge land costs nothing and brings no jobs.
	var jobs: int = owner.jobs()
	var kept: Dictionary = b.edge
	b.edge = {}
	_check(owner.jobs() == jobs, "the %s's edge pieces add no jobs" % kind)
	b.edge = kept


## Roads win: a short lane in from the west street cuts the west piece back;
## when it's taken up, the piece fits back out to the street.
func _road_checks(sim: CitySim, kind: String, ring: Array, row: float) -> void:
	var k: Dictionary = KINDS[kind]
	var cell: float = k.cell
	var owner := _owner(sim, kind)
	var id: int = _hubs(sim, kind).keys()[0]
	var b: Dictionary = _hubs(sim, kind)[id]
	var before := _edge_area(b)
	var n_blocks: int = b.blocks.size()
	var z := -(row + cell * 0.5)
	var end: float = k.x - cell * 0.5 - row - 3.0
	_road(sim, [ring[0], z], [end, z])
	sim.tick()
	_check(_hubs(sim, kind).has(id) and b.blocks.size() == n_blocks, "the %s itself is untouched by the lane" % kind)
	_check(_edge_area(b) < before, "the lane took %s edge land (%.0f -> %.0f m2)" % [kind, before, _edge_area(b)])
	_check(_no_edge_over_roads(sim, b, cell), "nothing left of the %s's edge pieces is on or by the lane" % kind)
	_check(not owner.covers(Vector3(end - 2.0, 0, z)), "the lane's ground is not the %s's" % kind)
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "the cut-back town saves byte for byte the same")
	var lane := -1
	for seg in sim.network.segments:
		var cv := sim.network.curve_of(seg)
		for e in [cv[0], cv[2]]:
			if Vector2(e.x, e.z).distance_to(Vector2(end, z)) < 1.0:
				lane = seg
	_check(lane != -1 and sim.apply({"type": "remove_road", "seg": lane}), "the lane by the %s is taken up" % kind)
	var cut_area := _edge_area(b)
	for i in 1440 * (BlockEdges.EVERY + 1):
		sim.tick()
	_check(_edge_area(b) > cut_area + 50.0, "the %s's west piece fits back out to the street (%.0f -> %.0f m2)" %
		[kind, cut_area, _edge_area(b)])
	_check(_no_edge_over_roads(sim, b, cell), "still clear of every street")
	# The player clears a piece: it goes and isn't taken straight back.
	var west := Vector3(ring[0] + row + 1.0, 0, z)
	var n: int = b.edge.size()
	_check(sim.apply({"type": k.remove, "pos": [west.x, west.z]}) and b.edge.size() == n - 1
		and _hubs(sim, kind).has(id) and b.blocks.size() == n_blocks, "the player clears the %s's west piece" % kind)
	for i in 1440 * (BlockEdges.EVERY + 1):
		sim.tick()
	_check(not owner.covers(west), "and the %s doesn't take it back" % kind)


## Zoning painted in a gap, not yet a lot, is never taken (or wiped) by the
## edge pieces.
func _zoned_cells(row: float) -> void:
	var sim := _new_town()
	var rings := {}
	for kind in KINDS:
		rings[kind] = _ring(sim, KINDS[kind], row)
		_place(sim, kind, KINDS[kind])
	var painted := {}
	for kind in KINDS:
		var k: Dictionary = KINDS[kind]
		# A patch in the middle of the back gap.
		sim.zones.paint(Vector3(k.x, 0, rings[kind][2] + row + k.back * 0.5), 3.0, ZoneMap.Zone.RESIDENTIAL)
		painted[kind] = []
	for c in sim.zones.cells:
		for kind in KINDS:
			if absf((c.x + 0.5) * ZoneMap.CELL - KINDS[kind].x) < 20.0:
				painted[kind].append(c)
	for i in 1440 * (BlockEdges.EVERY + 1):
		sim.tick()
	for kind in KINDS:
		var b: Dictionary = _hubs(sim, kind).values()[0]
		_check(not painted[kind].is_empty(), "zoning painted behind the %s (%d cells)" % [kind, painted[kind].size()])
		_check(not b.edge.is_empty(), "the %s took edge pieces (%s)" % [kind, str(b.edge.keys())])
		var kept := true
		var covered := false
		for c in painted[kind]:
			kept = kept and sim.zones.cells.has(c)
			covered = covered or _owner(sim, kind).covers(Vector3((c.x + 0.5) * ZoneMap.CELL, 0, (c.y + 0.5) * ZoneMap.CELL))
		_check(kept, "the zoning behind the %s is all still there" % kind)
		_check(not covered, "and none of it is the %s's" % kind)
