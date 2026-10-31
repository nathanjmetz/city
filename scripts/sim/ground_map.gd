class_name GroundMap
extends RefCounted
## What ground is already taken: one shared map of ground claims (Nathan,
## 2026-10-29: "railroad tracks running right through the city like
## they're just a part of the ground. They run right underneath the
## buildings. I also noticed street signs in the middle of driveways ... We
## need to get good at it though because we haven't yet implemented things
## like bus stops and items that will need to immediately make changes to
## the immediate environment like adjustments to the curb."). The plan is
## docs/spec-ground-map.md; this is its step 1: the map, filled from the
## town, that nothing in the game asks yet.
##
## A claim is one thing's footprint: its owner ("lot:322:1:1107",
## "seg:12", "node:7", "county:0") and part ("drive", "mailbox",
## "tree_trunk:3"), its kind (RANK) and one or more outline pieces (a road
## is one claim, its strip a piece per step along it). Everything is kept in
## packed arrays, and a sparse grid of `cell` metre squares lists the pieces
## that touch each square.
##
## ask() says whether something new may stand somewhere: it clashes with a
## claim when their kinds are a "never" pair (PAIRS, the overlap auditor's
## own rules) and they overlap by at least the pair's MIN_AREA. A claim
## that ranks the same or ahead (RANK: rail, then roads, public sites,
## lots, buildings, drives, posts, props) refuses it; one that ranks behind
## would give way to it.
##
## Each street side also keeps a curb ledger: the curb claims along it
## (drive cuts, ramps, crosswalks, posts, street trees, bus stops), sorted
## by how far along the street they start, so "is there 30 m of free curb
## near here?" (curb_gap) is a short walk down one list. It is CurbClaims
## grown up: CurbClaims stays the placers' answer until step 2 moves them
## over and its own grids go.
##
## The same answer on every copy: no random draws, and every answer that
## lists claims lists them by rank, kind, owner, part, never by the order
## they came in. Nothing is saved: the map is worked out from the town
## (build), which costs about what drawing its buildings does (it runs their
## builders through GroundFootprints).

## Grid square (m). Timed at 12, 16 and 24 in the big test town
## (tools/ground_map_bench.gd; the numbers are in the step 1 PR).
const CELL := 16.0

## Each kind's rank: its priority (docs/spec-ground-map.md) times ten, plus
## its order within that priority. Lower ranks come first and keep their
## ground. A kind not listed ranks last (99).
const RANK := {
	"water": 0, "steep": 1,
	"rail_bed:county": 10, "rail_bed:town": 10,
	"road": 20, "sidewalk_line": 21, "curb_ramp": 22, "crosswalk": 23, "curb_zone": 24,
	"public_site": 30,
	"lot": 40,
	"building": 50,
	"drive": 60, "curb_cut": 61, "front_walk": 62, "parking_stall": 63, "garage_apron": 64, "dock": 65,
	"post:signal_pole": 70, "post:stop_sign": 70, "post:yield_sign": 70, "post:no_turn_sign": 70,
	"post:streetlight": 71, "post:utility_pole": 71,
	"post:street_name": 72, "post:bus_stop": 72, "post:mailbox": 72,
	"tree_trunk": 80, "prop": 80, "drive_car": 81,
}
## Kinds filed as one claim per owner, every piece of it together (a road's
## strip, a lot's outline, a building's masses).
const WHOLE := ["road", "sidewalk_line", "rail_bed:county", "rail_bed:town", "lot", "building", "public_site"]
## Kinds that go in the curb ledger when they stand within the curb's reach
## of a street (a kind starting "post:" always may).
const CURB_KINDS := ["curb_cut", "curb_ramp", "crosswalk", "curb_zone", "tree_trunk"]
## How far out past the pavement's edge the curb ledger reaches: curb,
## parkway and sidewalk, and half a metre.
const CURB_REACH := RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH + 0.5

## A clash is an overlap of at least this many square metres (per pair,
## MIN_AREA overrides): touching edges and rounding don't count.
const MIN_AREA_DEFAULT := 0.02
## An overlap of rail with a road within this many metres of a grade
## crossing is the crossing itself (allowed).
const CROSSING_REACH := 14.0
## Kinds a railroad shares ground with at a grade crossing.
const CROSSING_KINDS := ["road", "sidewalk_line", "curb_ramp", "crosswalk"]
## Pairs that must never overlap: [kind a, kind b, rule, how visible (1-5),
## why]. "never" pairs are clashes (and fail tests/test_overlaps.gd);
## "watch" pairs are counted only. Kinds "post" and "rail_bed" are split by
## what they are (post:stop_sign...). A kind ending in "*other" checks only
## things of other owners.
const PAIRS := [
	["rail_bed", "building", "never", 5, "track running under a building"],
	["rail_bed", "public_site", "never", 5, "track through a school, warehouse or service yard"],
	["rail_bed", "lot", "never", 4, "a lot cut across the track: whatever grows there stands on it"],
	["rail_bed", "road", "never", 4, "track through pavement with no grade crossing"],
	["rail_bed", "drive", "never", 3, "track across a driveway"],
	["rail_bed", "parking_stall", "never", 3, "track through a parking lot"],
	["rail_bed", "tree_trunk", "never", 2, "a tree growing on the ballast"],
	["rail_bed", "prop", "never", 2, "a yard prop on the ballast"],
	["rail_bed", "post", "never", 3, "a pole or sign on the ballast"],
	["building", "building*other", "never", 5, "two buildings in one place"],
	["building", "road", "never", 5, "a building on the street"],
	["building", "sidewalk_line", "never", 4, "a building across the sidewalk"],
	["building", "public_site", "never", 4, "a building inside a public site"],
	["building", "drive*other", "never", 3, "a neighbour's drive under a building"],
	["building", "parking_stall*other", "never", 3, "a neighbour's parking under a building"],
	["post", "drive", "never", 4, "a sign or pole in a driveway"],
	["post", "curb_cut", "never", 4, "a sign or pole in a curb cut (where the drive crosses the parkway)"],
	["post", "curb_ramp", "never", 4, "a sign or pole on a curb ramp"],
	["post", "crosswalk", "never", 3, "a sign or pole in a crosswalk"],
	["post", "sidewalk_line", "never", 3, "a sign or pole in the middle of the sidewalk"],
	["post", "front_walk", "never", 3, "a sign or pole on a front walk"],
	["post", "road", "never", 4, "a sign or pole in the street"],
	["post", "building", "never", 4, "a sign or pole inside a building"],
	["post", "parking_stall", "never", 3, "a sign or pole in a parking space"],
	["post", "post", "watch", 2, "two poles in one spot"],
	["prop", "drive", "never", 3, "a yard prop on the driveway"],
	["prop", "curb_cut", "never", 3, "a yard prop in the curb cut"],
	["prop", "front_walk", "never", 3, "a yard prop on the front walk"],
	["prop", "sidewalk_line", "never", 3, "a yard prop on the sidewalk"],
	["prop", "road", "never", 4, "a yard prop in the street"],
	["prop", "building", "never", 3, "a yard prop inside a wall"],
	["prop", "parking_stall", "never", 3, "a yard prop in a parking space"],
	["prop", "tree_trunk", "never", 2, "a yard prop through a tree trunk"],
	["prop", "prop*other", "never", 2, "two lots' props in one spot"],
	["tree_trunk", "building", "never", 4, "a tree growing through a wall"],
	["tree_trunk", "road", "never", 4, "a tree in the street"],
	["tree_trunk", "drive", "never", 3, "a tree in the driveway"],
	["tree_trunk", "curb_cut", "never", 3, "a tree in the curb cut"],
	["tree_trunk", "front_walk", "never", 3, "a tree on the front walk"],
	["tree_trunk", "sidewalk_line", "never", 3, "a tree in the middle of the sidewalk"],
	["tree_trunk", "curb_ramp", "never", 3, "a tree on a curb ramp"],
	["tree_trunk", "parking_stall", "never", 3, "a tree in a parking space"],
	["tree_trunk", "post", "watch", 2, "a tree trunk round a pole"],
	["drive_car", "front_walk", "never", 3, "a car parked across the front walk"],
	["drive_car", "sidewalk_line", "never", 3, "a car parked across the sidewalk"],
	["drive_car", "prop", "never", 3, "a car parked through a yard prop"],
	["drive_car", "tree_trunk", "never", 3, "a car parked through a tree"],
	["drive_car", "building*other", "never", 4, "a car parked in a neighbour's wall"],
	["garage_apron", "prop", "never", 3, "a yard prop blocking a garage door"],
	["garage_apron", "tree_trunk", "never", 3, "a tree blocking a garage door"],
	["garage_apron", "post", "never", 3, "a pole blocking a garage door"],
	["dock", "post", "never", 3, "a pole in a loading dock"],
	["dock", "tree_trunk", "never", 3, "a tree in a loading dock"],
	["parking_stall", "road", "never", 3, "a parking space in the street"],
	["public_site", "road", "watch", 3, "a public site over the street (its drive meets the street)"],
	["lot", "lot*other", "never", 2, "two lots on the same ground"],
	["lot", "road", "never", 3, "a lot over the street"],
	["lot", "public_site", "never", 3, "a lot over a public site"],
]
## Pairs that may overlap, and why (not checked).
const ALLOWED := [
	["tree crown", "lawn, drive, roof, sidewalk", "a crown overhangs; only its trunk claims ground"],
	["rail_bed", "road at a grade crossing", "the crossing is where they share ground (within %.0f m of one)" % CROSSING_REACH],
	["drive", "sidewalk", "a drive crosses the sidewalk at its curb cut"],
	["post", "parkway (grass strip)", "where signs, lights and poles belong"],
	["streetlight arm, signal mast arm", "road", "they hang over it"],
	["drive_car", "drive", "where it parks"],
	["building", "own drive / own parking", "an attached garage meets its drive"],
]
## Smallest overlap (m2) that counts, per pair.
const MIN_AREA := {"lot|lot*other": 1.0, "lot|road": 1.0, "building|building*other": 0.5, "building|road": 0.5,
	"rail_bed|lot": 1.0, "lot|public_site": 1.0, "public_site|road": 1.0, "building|sidewalk_line": 0.1}

## PAIRS by kind group, both ways: group -> {group: [rule, others only, min area]}.
static var _rules := {}

var cell := CELL
## Claims (index = claim id). A released claim keeps its id, dead, until
## the map is built again.
var _owner := PackedStringArray()
var _part := PackedStringArray()
var _kind := PackedByteArray()  # index into _kinds
var _rank := PackedByteArray()
var _box := PackedFloat32Array()  # x0, z0, x1, z1 each
var _first := PackedInt32Array()  # its first piece
var _pieces := PackedInt32Array()  # how many pieces
var _alive := PackedByteArray()
var _curb := PackedInt32Array()  # two street sides each (-1: none), see _side_key
var _curb_s := PackedFloat32Array()  # from, to along the street each
## Pieces.
var _p_claim := PackedInt32Array()
var _p_box := PackedFloat32Array()
var _p_from := PackedInt32Array()  # first point
var _p_n := PackedInt32Array()
var _pts := PackedVector2Array()
var _mark := PackedInt32Array()  # per piece: the query that last saw it
var _query := 0
var _kinds := PackedStringArray()
var _kind_id := {}
## Vector2i -> PackedInt32Array of pieces touching that square.
var _grid := {}
## owner -> PackedInt32Array of its claims.
var _by_owner := {}
## Street side -> PackedInt32Array of curb claims, by where they start.
var _ledger := {}
var _ledger_longest := {}  # street side -> its longest stretch (m)
## seg -> [PackedVector2Array centre line, PackedFloat32Array metres along, half width].
var _streets := {}
var _crossings := PackedVector2Array()
var _stale := false
## Milliseconds the last build took: reading the footprints, filing them.
var last_collect_ms := 0.0
var last_file_ms := 0.0


func _init(cell_m := CELL) -> void:
	cell = cell_m


## The town's map (made on first use and kept on the sim; worked out again
## in full when roads, lots or buildings changed since). Step 1: nothing in
## the game asks it yet; step 2 files changes owner by owner instead.
static func of(sim: CitySim) -> GroundMap:
	if sim == null:
		return null
	if sim.ground == null:
		var g := GroundMap.new()
		sim.buildings_changed.connect(g._changed)
		sim.lots_changed.connect(g._changed)
		sim.county_changed.connect(g._changed)
		sim.network.changed.connect(g._changed)
		g.fill(sim)
		sim.ground = g
	elif sim.ground._stale:
		sim.ground.fill(sim)
	return sim.ground


func _changed() -> void:
	_stale = true


## A map of the town as it stands, with `cell_m` metre squares.
static func build(sim: CitySim, cell_m := CELL) -> GroundMap:
	var g := GroundMap.new(cell_m)
	g.fill(sim)
	return g


## Everything thrown away and filed again from the town: its streets and
## grade crossings, and every footprint GroundFootprints reads.
func fill(sim: CitySim) -> void:
	var t0 := Time.get_ticks_usec()
	var shapes := GroundFootprints.collect(sim)
	last_collect_ms = (Time.get_ticks_usec() - t0) / 1000.0
	fill_from(sim, shapes)


## The same, from shapes already read (GroundFootprints.collect of `sim`).
func fill_from(sim: CitySim, shapes: Array) -> void:
	var t0 := Time.get_ticks_usec()
	clear()
	_streets_of(sim)
	for x in sim.all_crossings():
		_crossings.append(Vector2(x.pos.x, x.pos.z))
	file_shapes(shapes)
	_stale = false
	last_file_ms = (Time.get_ticks_usec() - t0) / 1000.0


func clear() -> void:
	_owner = PackedStringArray()
	_part = PackedStringArray()
	_kind = PackedByteArray()
	_rank = PackedByteArray()
	_alive = PackedByteArray()
	_first = PackedInt32Array()
	_pieces = PackedInt32Array()
	_curb = PackedInt32Array()
	_p_claim = PackedInt32Array()
	_p_from = PackedInt32Array()
	_p_n = PackedInt32Array()
	_mark = PackedInt32Array()
	_box = PackedFloat32Array()
	_curb_s = PackedFloat32Array()
	_p_box = PackedFloat32Array()
	_pts = PackedVector2Array()
	_crossings.clear()
	_kinds.clear()
	_kind_id.clear()
	_grid.clear()
	_by_owner.clear()
	_ledger.clear()
	_ledger_longest.clear()
	_streets.clear()
	_query = 0


## The street centre lines the curb ledger measures along (at grade).
func _streets_of(sim: CitySim) -> void:
	var ids := sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var pts := sim.network.sample_segment(id)
		if absf(pts[pts.size() / 2].y) > 1.0:
			continue  # a bridge or tunnel
		var line := PackedVector2Array()
		var along := PackedFloat32Array()
		var s := 0.0
		for i in pts.size():
			var p := Vector2(pts[i].x, pts[i].z)
			if i > 0:
				s += p.distance_to(line[line.size() - 1])
			line.append(p)
			along.append(s)
		_streets[int(id)] = [line, along, RoadStyle.half_width(sim.network.segments[id].type)]


## Files GroundFootprints shapes (collect's) as claims: a WHOLE kind as one claim per
## owner, anything else one claim each, numbered by where it stands (west
## to east, then north to south) so the names never hang on the order the
## shapes came in.
func file_shapes(shapes: Array) -> void:
	var groups := {}  # [kind, owner] -> [shapes]
	for s in shapes:
		var kind: String = s.cat + ":" + s.what if s.cat in ["post", "rail_bed"] else s.cat
		var owner: String = s.key
		var g := [kind, owner]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(s)
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return _before_names(rank_of(a[0]), a[0], a[1], "", rank_of(b[0]), b[0], b[1], ""))
	# Filed in one go: the grid and the ledger are put together at the end.
	var cells := {}  # Vector2i -> [pieces]
	var from := _owner.size()
	for g in keys:
		var kind: String = g[0]
		var owner: String = g[1]
		var list: Array = groups[g]
		var part := kind.get_slice(":", 1) if kind.begins_with("post:") else kind
		if kind in WHOLE:
			_add(owner, part, kind, list.map(func(s): return s.poly), cells)
			continue
		if list.size() > 1:
			list.sort_custom(func(a, b): return a.box.position.x < b.box.position.x \
				or (a.box.position.x == b.box.position.x and a.box.position.y < b.box.position.y))
		for i in list.size():
			_add(owner, part if list.size() == 1 else "%s:%d" % [part, i], kind, [list[i].poly], cells)
	for c in cells:
		var list: PackedInt32Array = _grid.get(c, PackedInt32Array())
		list.append_array(PackedInt32Array(cells[c]))
		_grid[c] = list
	for id in range(from, _owner.size()):
		_file_curb(id, false)
	for side in _ledger:
		var ids: Array = Array(_ledger[side])
		ids.sort_custom(_curb_before)
		_ledger[side] = PackedInt32Array(ids)


# ------------------------------------------------------------------ claims

## Files a claim: `owner`'s `part`, of `kind`, its outline pieces `polys`
## (PackedVector2Array each, town x/z). Its id; -1 when it has no piece.
func register(owner: String, part: String, kind: String, polys: Array) -> int:
	var id := _add(owner, part, kind, polys, null)
	if id >= 0:
		_file_curb(id, true)
	return id


## Takes back `owner`'s claims (only `part` when given). How many.
func release(owner: String, part := "") -> int:
	var n := 0
	var keep := PackedInt32Array()
	for id in _by_owner.get(owner, PackedInt32Array()):
		if part != "" and _part[id] != part:
			keep.append(id)
			continue
		n += 1
		_alive[id] = 0
		for p in range(_first[id], _first[id] + _pieces[id]):
			for c in _cells(_piece_box(p)):
				var list: PackedInt32Array = _grid.get(c, PackedInt32Array())
				var at := list.find(p)
				if at >= 0:
					list.remove_at(at)
					if list.is_empty():
						_grid.erase(c)
					else:
						_grid[c] = list
		for k in [_curb[id * 2], _curb[id * 2 + 1]]:
			if k >= 0:
				var list: PackedInt32Array = _ledger[k]
				list.remove_at(list.find(id))
				_ledger[k] = list
	if keep.is_empty():
		_by_owner.erase(owner)
	else:
		_by_owner[owner] = keep
	return n


func _add(owner: String, part: String, kind: String, polys: Array, cells) -> int:
	var pieces := polys.filter(func(p): return (p as PackedVector2Array).size() >= 3)
	if pieces.is_empty():
		return -1
	if not _kind_id.has(kind):
		_kind_id[kind] = _kinds.size()
		_kinds.append(kind)
	var id := _owner.size()
	_owner.append(owner)
	_part.append(part)
	_kind.append(_kind_id[kind])
	_rank.append(rank_of(kind))
	_first.append(_p_claim.size())
	_pieces.append(pieces.size())
	_alive.append(1)
	_curb.append(-1)
	_curb.append(-1)
	_curb_s.append(0.0)
	_curb_s.append(0.0)
	var all := Rect2()
	for i in pieces.size():
		var poly: PackedVector2Array = pieces[i]
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			box = box.expand(v)
		all = box if i == 0 else all.merge(box)
		var p := _p_claim.size()
		_p_claim.append(id)
		_p_box.append(box.position.x)
		_p_box.append(box.position.y)
		_p_box.append(box.end.x)
		_p_box.append(box.end.y)
		_p_from.append(_pts.size())
		_p_n.append(poly.size())
		_pts.append_array(poly)
		_mark.append(0)
		for c in _cells(box):
			if cells != null:
				if not cells.has(c):
					cells[c] = []
				cells[c].append(p)
			else:
				var list: PackedInt32Array = _grid.get(c, PackedInt32Array())
				list.append(p)
				_grid[c] = list
	_box.append(all.position.x)
	_box.append(all.position.y)
	_box.append(all.end.x)
	_box.append(all.end.y)
	var mine: PackedInt32Array = _by_owner.get(owner, PackedInt32Array())
	mine.append(id)
	_by_owner[owner] = mine
	return id


## A claim as a dictionary: {id, owner, part, kind, rank, box, polys,
## curb: [[street side, from, to]...]}.
func claim(id: int) -> Dictionary:
	var polys := []
	for p in range(_first[id], _first[id] + _pieces[id]):
		polys.append(_pts.slice(_p_from[p], _p_from[p] + _p_n[p]))
	var curb := []
	for i in 2:
		if _curb[id * 2 + i] >= 0:
			curb.append([_curb[id * 2 + i], _curb_s[id * 2], _curb_s[id * 2 + 1]])
	return {"id": id, "owner": _owner[id], "part": _part[id], "kind": _kinds[_kind[id]], "rank": _rank[id],
		"box": _claim_box(id), "polys": polys, "curb": curb, "alive": _alive[id] == 1}


## "owner/part" of claim `id`.
func name_of(id: int) -> String:
	return _owner[id] + "/" + _part[id]


func kind_of(id: int) -> String:
	return _kinds[_kind[id]]


## `owner`'s live claims, in order.
func claims_of(owner: String) -> Array:
	var out := Array(_by_owner.get(owner, PackedInt32Array()))
	out.sort_custom(_claim_before)
	return out


## Every live claim, in order (rank, kind, owner, part).
func all_claims() -> Array:
	var out := []
	for id in _owner.size():
		if _alive[id] == 1:
			out.append(id)
	out.sort_custom(_claim_before)
	return out


## Every live claim with a piece in `box` (of `kinds`, all when empty), in order.
func near(box: Rect2, kinds := []) -> Array:
	var seen := {}
	for p in _pieces_in(box):
		var id := _p_claim[p]
		if seen.has(id) or (not kinds.is_empty() and not _kinds[_kind[id]] in kinds):
			continue
		seen[id] = true
	var out := seen.keys()
	out.sort_custom(_claim_before)
	return out


static func rank_of(kind: String) -> int:
	return int(RANK.get(kind, 99))


# ------------------------------------------------------------------ asking

## May something of `kind` stand on `poly` (owned by `own`)? {ok, refused_by:
## [names of the claims it would land on that rank the same or ahead],
## gives_way: [names of those that rank behind it]}, each in order.
func ask(kind: String, poly: PackedVector2Array, own := "") -> Dictionary:
	var refused := []
	var gives := []
	var r := rank_of(kind)
	for h in clashes(kind, poly, own):
		var id: int = h[0]
		if _rank[id] <= r:
			refused.append(name_of(id))
		else:
			gives.append(name_of(id))
	return {"ok": refused.is_empty(), "refused_by": refused, "gives_way": gives}


## The claims `poly` (of `kind`, owned by `own`) would clash with: [claim,
## overlap m2, its middle] each, in order. `watch`: "watch" pairs too.
func clashes(kind: String, poly: PackedVector2Array, own := "", watch := false) -> Array:
	var by := {}
	for h in hits(kind, poly, own, watch):
		var id: int = _p_claim[h[0]]
		if not by.has(id):
			by[id] = [id, 0.0, h[2], 0.0]
		by[id][1] += h[1]
		if h[1] > by[id][3]:
			by[id][2] = h[2]
			by[id][3] = h[1]
	var ids := by.keys()
	ids.sort_custom(_claim_before)
	return ids.map(func(id): return [id, by[id][1], by[id][2]])


## The pieces `poly` (of `kind`, owned by `own`) would clash with, one by
## one: [piece, overlap m2, its middle] each, by piece. Each pair's
## MIN_AREA applies piece by piece, and a railroad shares ground with a road
## at a grade crossing (CROSSING_REACH), as the overlap auditor counts.
func hits(kind: String, poly: PackedVector2Array, own := "", watch := false) -> Array:
	var out := []
	if poly.size() < 3:
		return out
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	var group := kind.get_slice(":", 0)
	var rules: Dictionary = _rules_of().get(group, {})
	if rules.is_empty():
		return out
	var ps := _pieces_in(box)
	ps.sort()
	for p in ps:
		var id := _p_claim[p]
		var k := _kinds[_kind[id]]
		var other := k.get_slice(":", 0)
		var rule: Array = rules.get(other, [])
		if rule.is_empty() or (rule[0] != "never" and not watch):
			continue
		if rule[1] and own != "" and _owner[id] == own:
			continue
		if not box.intersects(_piece_box(p)):
			continue
		var hit := overlap(poly, _pts.slice(_p_from[p], _p_from[p] + _p_n[p]))
		if hit[0] < float(rule[2]):
			continue
		if (group == "rail_bed" and other in CROSSING_KINDS) or (other == "rail_bed" and group in CROSSING_KINDS):
			if _at_crossing(hit[1]):
				continue
		out.append([p, hit[0], hit[1]])
	return out


func _at_crossing(at: Vector2) -> bool:
	for c in _crossings:
		if c.distance_to(at) < CROSSING_REACH:
			return true
	return false


## PAIRS as kind group -> {group: [rule, others only, min area]}, both ways.
static func _rules_of() -> Dictionary:
	if not _rules.is_empty():
		return _rules
	for p in PAIRS:
		var a: String = p[0]
		var b_full: String = p[1]
		var b := b_full.trim_suffix("*other")
		var rule := [p[2], b_full.ends_with("*other") or a == b, float(MIN_AREA.get(a + "|" + b_full, MIN_AREA_DEFAULT))]
		for pair in [[a, b], [b, a]]:
			if not _rules.has(pair[0]):
				_rules[pair[0]] = {}
			_rules[pair[0]][pair[1]] = rule
	return _rules


## Pieces with a square in `box`, each once.
func _pieces_in(box: Rect2) -> Array:
	_query += 1
	var out := []
	for c in _cells(box):
		for p in _grid.get(c, PackedInt32Array()):
			if _mark[p] != _query and _alive[_p_claim[p]] == 1:
				_mark[p] = _query
				out.append(p)
	return out


# ------------------------------------------------------------------ curb

## The street side and how far along it `p` stands: [seg, side (1 to the
## right going from its first node to its last, -1 to the left), metres
## along, metres out from the pavement's edge], or [] when no street's
## curb reaches it.
func curb_spot(p: Vector2) -> Array:
	var best := []
	for id in near(Rect2(p, Vector2.ZERO).grow(CURB_REACH + 2.0), ["road"]):
		var seg := int(_owner[id].get_slice(":", 1))
		if not _streets.has(seg):
			continue
		var at := _project(seg, p)
		var out: float = absf(at[1]) - float(_streets[seg][2])
		if out <= CURB_REACH and (best.is_empty() or out < best[3] or (out == best[3] and seg < best[0])):
			best = [seg, 1 if at[1] >= 0.0 else -1, at[0], out]
	return best


## The curb claims on street `seg`'s `side` whose stretch overlaps
## `from`..`to` metres along it (only touching it at an end doesn't count) (of `kinds`, all when empty), by where they start.
func curb_at(seg: int, side: int, from: float, to: float, kinds := []) -> Array:
	var k := _side_key(seg, side)
	var out := []
	var reach := from - float(_ledger_longest.get(k, 0.0))
	for id in _ledger.get(k, PackedInt32Array()):
		var s0 := _curb_s[id * 2]
		if s0 >= to:
			break
		if s0 < reach or _curb_s[id * 2 + 1] <= from:
			continue
		if kinds.is_empty() or _kinds[_kind[id]] in kinds or (_kinds[_kind[id]].begins_with("post:") and "post" in kinds):
			out.append(id)
	return out


## Where `length` metres of free curb start on street `seg`'s `side`,
## nearest `at` metres along it (its middle as close to `at` as it can be),
## free of every curb claim of `kinds` (all when empty); -1.0 when the side
## has no stretch that long.
func curb_gap(seg: int, side: int, at: float, length: float, kinds := []) -> float:
	if not _streets.has(seg):
		return -1.0
	var along: PackedFloat32Array = _streets[seg][1]
	var end := along[along.size() - 1]
	var free := []  # [from, to]
	var edge := 0.0
	for id in curb_at(seg, side, 0.0, end, kinds):
		var s0 := _curb_s[id * 2]
		if s0 > edge:
			free.append([edge, s0])
		edge = maxf(edge, _curb_s[id * 2 + 1])
	if end > edge:
		free.append([edge, end])
	var best := -1.0
	var best_d := INF
	for g in free:
		if g[1] - g[0] < length:
			continue
		var s := clampf(at - length * 0.5, g[0], g[1] - length)
		var d := absf(s + length * 0.5 - at)
		if d < best_d:
			best = s
			best_d = d
	return best


## Files a curb claim in the ledger of the street side it stands on (both
## sides for one across the street, a crosswalk). `sorted`: keep the
## side's list in order now (else filled in one go and sorted after).
func _file_curb(id: int, sorted: bool) -> void:
	var kind := _kinds[_kind[id]]
	if not (kind in CURB_KINDS or kind.begins_with("post:")):
		return
	var box := _claim_box(id)
	var spot := curb_spot(box.get_center())
	if spot.is_empty():
		return
	var seg: int = spot[0]
	var lo := INF
	var hi := -INF
	var sides := {}
	var hw: float = _streets[seg][2]
	for p in range(_first[id], _first[id] + _pieces[id]):
		for i in _p_n[p]:
			var at := _project(seg, _pts[_p_from[p] + i])
			lo = minf(lo, at[0])
			hi = maxf(hi, at[0])
			if absf(at[1]) > hw * 0.5:
				sides[1 if at[1] >= 0.0 else -1] = true
	if sides.is_empty():
		sides[spot[1]] = true
	var keys := sides.keys()
	keys.sort()
	_curb_s[id * 2] = lo
	_curb_s[id * 2 + 1] = hi
	for i in keys.size():
		var k := _side_key(seg, keys[i])
		_curb[id * 2 + i] = k
		var list: PackedInt32Array = _ledger.get(k, PackedInt32Array())
		if sorted:
			var at := 0
			while at < list.size() and _curb_before(list[at], id):
				at += 1
			list.insert(at, id)
		else:
			list.append(id)
		_ledger[k] = list
		_ledger_longest[k] = maxf(float(_ledger_longest.get(k, 0.0)), hi - lo)


## A street side's ledger key: seg * 2, plus one on its right.
static func _side_key(seg: int, side: int) -> int:
	return seg * 2 + (1 if side > 0 else 0)


## [metres along street `seg` to the nearest point to `p`, metres out from
## its centre line (to the right positive)].
func _project(seg: int, p: Vector2) -> Array:
	var line: PackedVector2Array = _streets[seg][0]
	var along: PackedFloat32Array = _streets[seg][1]
	var best_d := INF
	var best := [0.0, 0.0]
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-6 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			var side := signf(ab.cross(p - a))
			best = [along[i] + sqrt(len2) * t, sqrt(d) * (side if side != 0.0 else 1.0)]
	return best


# ------------------------------------------------------------------ order

func _claim_before(a: int, b: int) -> bool:
	return _before_names(_rank[a], _kinds[_kind[a]], _owner[a], _part[a], _rank[b], _kinds[_kind[b]], _owner[b], _part[b])


func _curb_before(a: int, b: int) -> bool:
	if _curb_s[a * 2] != _curb_s[b * 2]:
		return _curb_s[a * 2] < _curb_s[b * 2]
	return _claim_before(a, b)


static func _before_names(ra: int, ka: String, oa: String, pa: String, rb: int, kb: String, ob: String, pb: String) -> bool:
	if ra != rb:
		return ra < rb
	if ka != kb:
		return ka < kb
	if oa != ob:
		return oa < ob
	return pa < pb


# ------------------------------------------------------------------ measures

## A number that is the same for two maps holding the same claims, however
## they came to be filed.
func signature() -> int:
	var h := 0
	for id in all_claims():
		var polys := []
		for p in range(_first[id], _first[id] + _pieces[id]):
			polys.append(_pts.slice(_p_from[p], _p_from[p] + _p_n[p]))
		var sides := [_curb[id * 2], _curb[id * 2 + 1]]
		h = hash([h, _owner[id], _part[id], _kinds[_kind[id]], polys, sides,
			snappedf(_curb_s[id * 2], 0.001), snappedf(_curb_s[id * 2 + 1], 0.001)])
	return h


## {claims, pieces, points, cells, curb_sides, curb_claims, bytes (the packed
## arrays and grid lists, by their sizes)}.
func stats() -> Dictionary:
	var live := 0
	for a in _alive:
		live += a
	var grid_refs := 0
	for c in _grid:
		grid_refs += (_grid[c] as PackedInt32Array).size()
	var curb_refs := 0
	for k in _ledger:
		curb_refs += (_ledger[k] as PackedInt32Array).size()
	var text := 0
	for i in _owner.size():
		text += _owner[i].length() + _part[i].length()
	var n := _owner.size()
	var np := _p_claim.size()
	var bytes := n * (3 + 4 * 4 + 4 + 4 + 2 * 4 + 2 * 4) + text * 4 + n * 2 * 16 \
		+ np * (4 + 4 * 4 + 4 + 4 + 4) + _pts.size() * 8 + grid_refs * 4 + _grid.size() * 48 + curb_refs * 4
	return {"claims": live, "pieces": np, "points": _pts.size(), "cells": _grid.size(), "grid_refs": grid_refs,
		"curb_sides": _ledger.size(), "curb_claims": curb_refs, "bytes": bytes}


# ------------------------------------------------------------------ geometry

## [overlap area, its middle] of two outlines.
static func overlap(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	var parts := Geometry2D.intersect_polygons(a, b)
	var total := 0.0
	var mid := Vector2.ZERO
	for q: PackedVector2Array in parts:
		if Geometry2D.is_polygon_clockwise(q):
			continue  # a hole
		var ar := area(q)
		total += ar
		var c := Vector2.ZERO
		for v in q:
			c += v
		mid += c / q.size() * ar
	return [total, mid / total if total > 0.0 else Vector2.ZERO]


static func area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _piece_box(p: int) -> Rect2:
	var i := p * 4
	return Rect2(_p_box[i], _p_box[i + 1], _p_box[i + 2] - _p_box[i], _p_box[i + 3] - _p_box[i + 1])


func _claim_box(id: int) -> Rect2:
	var i := id * 4
	return Rect2(_box[i], _box[i + 1], _box[i + 2] - _box[i], _box[i + 3] - _box[i + 1])


func _cells(box: Rect2) -> Array:
	var out := []
	for cx in range(floori(box.position.x / cell), floori(box.end.x / cell) + 1):
		for cz in range(floori(box.position.y / cell), floori(box.end.y / cell) + 1):
			out.append(Vector2i(cx, cz))
	return out
