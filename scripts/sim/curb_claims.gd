class_name CurbClaims
extends RefCounted
## "Is this stretch of curb free?" The one answer every curbside placer asks
## (Nathan, 2026-10-29: "I also noticed street signs in the middle of
## driveways ... we haven't yet implemented things like bus stops and items
## that will need to immediately make changes to the immediate environment
## like adjustments to the curb."). Stop, yield, No Turn and signal posts
## (JunctionView), streetlights (StreetLights.place), curbside mailboxes
## (mailbox_at: MailView, BuildingView) and street trees
## (BuildingView._parkway_free) all ask it.
##
## What claims the curb, as 2D shapes in the town's x/z:
##   - "ramp" and "crosswalk": the curb ramps and crosswalks at shaped town
##     corners (Junction.ramps, JunctionMarks), from the road view's
##     junction plans (set_junctions; RoadView pushes them as it plans).
##   - "cut": each built lot's paving across the parkway and sidewalk to the
##     street. A home's or duplex's is its plan's drive (SiteLayout.for_lot);
##     a shop's, office's, plant's or flats' is what its builder lays out to
##     the curb (BuildingView.curb_paving: a dry run of the very builder,
##     from the lot's own seed). Never from what has been drawn: the answers
##     depend on the town alone, never on the camera or the order things
##     were drawn in.
##   - "rail": the town's and the county's railroad beds (the ground map's
##     own claims): no post, lamp, mailbox or street tree on the ballast.
## Bus stops and anything else that will change the curb add their own
## kind with claim().
##
## Everything claimed is filed in the town's ground map (GroundMap, the
## live layer), and every question here is asked of its grid: one curb
## answer for the whole game (docs/spec-ground-map.md, step 2).
##
## Kept up to date cheaply: when the town's buildings or lots change, each
## built lot's inputs are compared with what its cut was worked out from
## (sync); only a lot whose inputs changed is worked out again, and only
## when its shapes really changed is the place logged (changes_since). Views
## look again only at what stands near a logged place. warm() works every
## lot out at once, for the loading screen.

## Grid cell (m) for the lots' frontages.
const CELL := 24.0
## Kinds a post must keep off (everything here).
const ALL := ["ramp", "crosswalk", "cut", "other", "rail"]
## The ground map's kinds for each kind here.
const MAP_KINDS := {"ramp": ["curb_ramp"], "crosswalk": ["crosswalk"], "cut": ["curb_cut"], "other": ["curb_zone"],
	"rail": ["rail_bed:county", "rail_bed:town"]}
## A curbside mailbox: its post stands this far beside the drive's edge (a
## USPS curbside box goes just to the side of the driveway, 6 to 8 in back
## from the curb, its door to the street; 2 ft from the drive's edge keeps
## the carrier's reach and the drive's swing clear).
const MAIL_BESIDE := 0.6
## Half of a mailbox post's footprint, and how far a box may slide along
## the curb to find a free spot.
const MAIL_HALF := 0.25
const MAIL_SLIDE := 6.0
## A street tree's trunk (half).
const TRUNK_HALF := 0.3
## A commercial apron as HouseBuilder._curb_cut draws it: the flare each
## side across the parkway (lot_cut uses COMMERCIAL_HALF where no dry run
## is to hand).
const COMMERCIAL_HALF := 3.6
const COMMERCIAL_FLARE := 1.5
## Changes kept for views to catch up on (older: look at everything again).
const LOG_KEEP := 512

var _sim: WeakRef
## Bumps only when the junction plans change (street trees re-check on it).
var junction_version := 0
var _serial := 0  # bumps with every logged change
var _log := []  # [serial, Rect2] of each place whose claims changed
var _log_floor := 0  # changes before this serial are no longer kept
var _junction := {}  # hash of kind and outline -> [[kind, owner, poly, box], its claim in the map]
var _other := {}  # owner -> [claim()'d shapes' claims in the map]
var _shape_of := {}  # claim in the map -> [kind, owner, poly, box] filed here
var _rail := {}  # rail piece in the map -> ["rail", owner, poly, box], as asked
var _lot_cells := {}  # Vector2i -> [lot keys whose frontage reaches the cell]
var _dirty := true  # buildings or lots changed since the last sync
var _cuts := {}  # lot key -> [inputs hash, [shapes], layout, the building and lot it was worked out from]
var _lots_moved := true  # lots were planned again: file them all again
var _mail := {}  # lot key -> Vector2 (where its box stands)
## Milliseconds the last sync took and how many lots it worked out again
## (for the benches and tests).
var last_sync_ms := 0.0
var last_sync_lots := 0


## The town's claims (made on first use and kept on the sim).
static func of(sim: CitySim) -> CurbClaims:
	if sim == null:
		return null
	if sim.curb == null:
		var c := CurbClaims.new()
		c._sim = weakref(sim)
		sim.buildings_changed.connect(c._changed)
		sim.lots_changed.connect(c._lots_changed)
		sim.curb = c
		GroundMap.of(sim).rail_changed.connect(c._rail_changed)
		sim.ground.compacted.connect(c._compacted)
	return sim.curb


func _changed() -> void:
	_dirty = true


func _lots_changed() -> void:
	_dirty = true
	_lots_moved = true


## The railroads were filed again: what stands near them looks again (street
## trees too).
func _rail_changed(box: Rect2) -> void:
	_rail.clear()
	junction_version += 1
	_note(box)


## The map packed its claims together again: the ids kept here follow.
func _compacted(remap: PackedInt32Array) -> void:
	var re := func(id: int) -> int: return remap[id] if id >= 0 and id < remap.size() else -1
	var shapes := {}
	for id in _shape_of:
		if re.call(id) >= 0:
			shapes[re.call(id)] = _shape_of[id]
	_shape_of = shapes
	for h in _junction:
		_junction[h][1] = re.call(_junction[h][1])
	for key in _cuts:
		_cuts[key][5] = _cuts[key][5].map(re)
	for o in _other:
		_other[o] = _other[o].map(re)
	_rail.clear()


## The town's ground map, where the claims are filed.
func _map() -> GroundMap:
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	return GroundMap.of(sim) if sim != null else null


## Everything claimed here filed in `map` (a fresh one, tests).
func file_into(map: GroundMap) -> void:
	_sync()
	for h in _junction:
		var sh: Array = _junction[h][0]
		map.register(sh[1], _part_name(sh), MAP_KINDS[sh[0]][0], [sh[2]])
	for key in _cuts:
		for sh in _cuts[key][1]:
			map.register(sh[1], _part_name(sh), "curb_cut", [sh[2]])
	for owner in _other:
		for id in _other[owner]:
			var sh: Array = _shape_of[id]
			map.register(sh[1], _part_name(sh), "curb_zone", [sh[2]])


## A shape's part name in the map: its kind and where its box's middle is
## (so it never hangs on the order things were filed in).
static func _part_name(sh: Array) -> String:
	var c := (sh[3] as Rect2).get_center()
	return "curb.%s@%.1f,%.1f" % [sh[0], c.x, c.y]


## Files shape `sh` (of the map's `kind`) in the town's map; its claim.
func _file(sh: Array, kind: String) -> int:
	var map := _map()
	if map == null:
		return -1
	var id := map.register(sh[1], _part_name(sh), kind, [sh[2]])
	if id >= 0:
		_shape_of[id] = sh
	return id


func _unfile(ids: Array) -> void:
	var map := _map()
	for id in ids:
		_shape_of.erase(id)
	if map != null:
		map.release_ids(PackedInt32Array(ids))


## Everything thrown away and worked out again from the town (a town loaded
## into this sim: CitySim.from_dict).
func reset() -> void:
	for key in _cuts:
		_unfile(_cuts[key][5])
	_cuts.clear()
	_mail.clear()
	_lot_cells.clear()
	_dirty = true
	_lots_moved = true
	_note(Rect2(-1e9, -1e9, 2e9, 2e9))


## Works every built lot out now (the loading screen does, so the first
## view to ask doesn't wait).
func warm() -> void:
	_sync()


## A number that changes whenever anything claimed changes (brings the
## claims up to date first).
func stamp() -> int:
	_sync()
	return _serial


## The places (Rect2) whose claims changed since `seen` (a stamp()); one
## covering everything when `seen` is older than the changes kept.
func changes_since(seen: int) -> Array:
	_sync()
	if seen < _log_floor:
		return [Rect2(-1e9, -1e9, 2e9, 2e9)]
	var out := []
	for e in _log:
		if int(e[0]) > seen:
			out.append(e[1])
	return out


func _note(box: Rect2) -> void:
	_serial += 1
	_log.append([_serial, box])
	if _log.size() > LOG_KEEP:
		_log_floor = int(_log[0][0])
		_log.pop_front()
	# Mailboxes near it stand again.
	var reach := box.grow(MAIL_SLIDE + 2.0)
	if reach.size.x > 1e8:
		_mail.clear()
		return
	for c in _cells(reach):
		for key in _lot_cells.get(c, []):
			_mail.erase(key)


# ------------------------------------------------------------------ claims

## The curb ramps and crosswalks at the town's shaped corners, from the
## road view's junction plans (Junction.plan). Logs only the ones that came
## or went.
func set_junctions(plans: Dictionary) -> void:
	var keep := {}
	for s in junction_shapes(plans):
		var h := hash([s[0], s[2]])
		keep[h] = true
		if not _junction.has(h):
			_junction[h] = [s, _file(s, MAP_KINDS[s[0]][0])]
			_note(s[3])
	for h in _junction.keys():
		if not keep.has(h):
			_note(_junction[h][0][3])
			_unfile([_junction[h][1]])
			_junction.erase(h)
	junction_version += 1


## Something new on the curb (a bus stop's pad, a hydrant): its footprint.
func claim(kind: String, owner: String, poly: PackedVector2Array) -> void:
	var s := _shape(kind, owner, poly)
	if not _other.has(owner):
		_other[owner] = []
	_other[owner].append(_file(s, "curb_zone"))
	_note(s[3])


## Takes back what `owner` claimed.
func release(owner: String) -> void:
	for id in _other.get(owner, []):
		if _shape_of.has(id):
			_note(_shape_of[id][3])
	_unfile(_other.get(owner, []))
	_other.erase(owner)


## Curb ramps and crosswalks at shaped town corners, [kind, owner, poly,
## box] each: each ramp across the parkway beside the crosswalk it serves,
## from RAMP_GAP to RAMP_GAP + RAMP_WIDTH past where the road stops (a
## diagonal ramp a square at the corner's middle), each crosswalk across
## the road from CROSS_NEAR to CROSS_FAR (Junction._draw_node,
## JunctionMarks.paint).
static func junction_shapes(plans: Dictionary) -> Array:
	var out := []
	var nodes := plans.keys()
	nodes.sort()
	for n in nodes:
		var j: Dictionary = plans[n]
		if j.get("country", false) or j.has("bend"):
			continue
		var center: Vector3 = j.center
		var key := "node:%d" % n
		for r in Junction.ramps(j):
			var c: Dictionary = j.corners[r[0]]
			var a: Dictionary = j.arms[c.a]
			var b: Dictionary = j.arms[c.b]
			if r[1] == "pair":
				for pair in [[a, 1.0], [b, -1.0]]:
					var arm: Dictionary = pair[0]
					var from: float = float(arm.d) + Junction.RAMP_GAP
					if from + Junction.RAMP_WIDTH > float(arm.length) * 0.5:
						continue
					out.append(_shape("ramp", key, _arm_band(arm, pair[1], float(arm.hw),
						float(arm.hw) + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH, from, from + Junction.RAMP_WIDTH)))
			else:
				# A diagonal ramp at the corner's middle: a square at the curb return.
				var mid := (Vector2(a.n) * -1.0 + Vector2(b.n)).normalized()
				var arm_hw := maxf(float(a.hw), float(b.hw))
				var at := Vector2(center.x, center.z) + mid * (arm_hw + float(c.r) * 0.4)
				out.append(_shape("ramp", key, square(at, 1.2)))
		if JunctionMarks.marked(j):
			for arm in j.arms:
				var d: float = float(arm.d)
				if d + JunctionMarks.CROSS_FAR > float(arm.length) * 0.5:
					continue
				out.append(_shape("crosswalk", key, _arm_band(arm, 1.0, -float(arm.hw), float(arm.hw),
					d + JunctionMarks.CROSS_NEAR, d + JunctionMarks.CROSS_FAR)))
	return out


static func _arm_band(arm: Dictionary, side: float, o0: float, o1: float, from: float, to: float) -> PackedVector2Array:
	var p0: Array = LotPlanner.point_at(arm.pts, from)
	var p1: Array = LotPlanner.point_at(arm.pts, to)
	var a := Vector2(p0[0].x, p0[0].z)
	var b := Vector2(p1[0].x, p1[0].z)
	var dir := Vector2(p0[1].x, p0[1].z).normalized()
	var nrm := Vector2(-dir.y, dir.x) * side
	return PackedVector2Array([a + nrm * o0, b + nrm * o0, b + nrm * o1, a + nrm * o1])


## A home's or duplex's curb cut: its drive across the parkway and
## sidewalk, from the lot line out to the curb, as wide as its plan draws
## it ([] without a drive). Anything else: a commercial apron at the
## layout's cut (the stand-in when no builder's paving is to hand).
static func lot_cut(lot: Dictionary, lay: Dictionary, type: String) -> PackedVector2Array:
	if lay.is_empty() or lay.get("main_street", false) or (lay.get("spots", []) as Array).is_empty() and type != "house":
		return PackedVector2Array()
	var cx := float(lay.cut_x)
	var tc := float(lot.get("to_curb", 2.0))
	if type in ["house", "duplex"]:
		var cw := float(lay.get("cut_w", 3.0))
		return _local_poly(lot, [Vector2(cx - cw * 0.5, -tc), Vector2(cx + cw * 0.5, -tc), Vector2(cx + cw * 0.5, 0.0),
			Vector2(cx - cw * 0.5, 0.0)])
	return paving_poly(lot, [cx - COMMERCIAL_HALF, cx + COMMERCIAL_HALF, -tc, COMMERCIAL_FLARE])


## One piece of paving out to the curb (HouseBuilder.cuts_drawn's [x0, x1,
## curb z, flare]) in the town: from the curb across the parkway and
## sidewalk, flared `flare` each side across the parkway (a commercial
## apron) or straight.
static func paving_poly(lot: Dictionary, c: Array) -> PackedVector2Array:
	var x0 := float(c[0])
	var x1 := float(c[1])
	var cz := float(c[2])
	var f := float(c[3])
	var walk0 := cz + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	var walk1 := walk0 + RoadStyle.SIDEWALK_WIDTH
	if f <= 0.0:
		return _local_poly(lot, [Vector2(x0, cz), Vector2(x1, cz), Vector2(x1, walk1), Vector2(x0, walk1)])
	return _local_poly(lot, [Vector2(x0 - f, cz), Vector2(x1 + f, cz), Vector2(x1, walk0),
		Vector2(x1, walk1), Vector2(x0, walk1), Vector2(x0, walk0)])


## Lot-frame points (x across, z back from the street) in the town.
static func _local_poly(lot: Dictionary, pts: Array) -> PackedVector2Array:
	var frame := SiteLayout.frame(lot)
	var out := PackedVector2Array()
	for q: Vector2 in pts:
		var w := frame * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


# ------------------------------------------------------------------ queries

## True when a post `half` metres either way round `p` stands clear of
## everything claimed (of `kinds`), other than what `own` claimed.
func is_free(p: Vector2, half: float, kinds := ALL, own := "") -> bool:
	var box := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
	for s in near(box, kinds):
		if s[1] != own and _hits(s, p, half):
			return false
	return true


## True when nothing at the junction corners (ramps, crosswalks) nor a
## railroad's bed is under a spot (street trees ask this: they only need
## re-checking when the roads or railroads change).
func junction_free(p: Vector2, half: float) -> bool:
	return is_free(p, half, ["ramp", "crosswalk", "rail"])


## The nearest free spot to `p` along `along` (a unit vector down the
## curb), at most `back` metres that way or `ahead` metres the other way,
## tried in half-metre steps, nearest first (back first on a tie); `p`
## itself if it is free, Vector2.INF if none is.
func slide(p: Vector2, along: Vector2, half: float, back: float, ahead := 0.0, kinds := ALL, own := "") -> Vector2:
	var step := 0.5
	var k := 0
	while true:
		var tried := false
		for s in ([0.0] if k == 0 else [k * step, -k * step]):
			if (s > 0.0 and s > back + 0.001) or (s < 0.0 and -s > ahead + 0.001):
				continue
			tried = true
			var q: Vector2 = p + along * s
			if is_free(q, half, kinds, own):
				return q
		if not tried and k > 0:
			return Vector2.INF
		k += 1
	return Vector2.INF


## Where a sign or signal post meant for `base` stands (y kept): there if it
## is clear, else slid along its curb to the nearest clear spot, back
## (`back_dir`, away from the junction) up to `back` or ahead up to
## `ahead`; `base` if none is. Clear means off every drive, ramp, pad and
## railroad bed, and 4 ft (CROSSWALK_GAP) or more behind any crosswalk
## (MUTCD 2B.10).
## JunctionView sets `back` so a stop sign stays within 50 ft of the road
## it meets.
const POST_BACK := 9.0
## How much further back a post may go when a drive takes every spot
## within `back` (about one commercial apron's width).
const POST_PAST := 8.0
const POST_AHEAD := 0.5
const CROSSWALK_GAP := 1.22
func post_spot(base: Vector3, back_dir: Vector3, half: float, back := POST_BACK, ahead := POST_AHEAD) -> Vector3:
	var p := Vector2(base.x, base.z)
	var along := Vector2(back_dir.x, back_dir.z).normalized()
	var others := ["ramp", "cut", "other", "rail"]
	# 4 ft behind the crosswalk where the curb has room; where a drive takes
	# all of it, just off the crosswalk (a sign beside the crosswalk beats one
	# in a drive).
	for gap in [CROSSWALK_GAP, 0.1]:
		var k := 0
		while k * 0.5 <= maxf(back, ahead) + 0.001:
			for s in ([0.0] if k == 0 else [k * 0.5, -k * 0.5]):
				if (s > 0.0 and s > back + 0.001) or (s < 0.0 and -s > ahead + 0.001):
					continue
				var q: Vector2 = p + along * s
				if is_free(q, half + 0.1, others) and is_free(q, half + gap, ["crosswalk"]):
					return Vector3(q.x, base.y, q.y)
			k += 1
	# A drive, ramp or track takes the whole stretch allowed: just past it,
	# up to POST_PAST further back (a sign beyond a corner shop's apron
	# beats one standing in it).
	var k := int(ceilf(back / 0.5))
	while back > 0.0 and k * 0.5 <= back + POST_PAST + 0.001:
		var q: Vector2 = p + along * (k * 0.5)
		if is_free(q, half + 0.1, others) and is_free(q, half + 0.1, ["crosswalk"]):
			return Vector3(q.x, base.y, q.y)
		k += 1
	return base


## Everything claimed in `box` (of `kinds`): [kind, owner, poly, box] each,
## asked of the town's ground map.
func near(box: Rect2, kinds := ALL) -> Array:
	var out := []
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null:
		return out
	if "cut" in kinds:
		_sync()
	var map := GroundMap.of(sim)  # brought up to date with the town first
	var want := []
	for k in kinds:
		want.append_array(MAP_KINDS.get(k, ["curb_zone"]))
	var found := map.pieces_of(box, want)
	for i in range(0, found.size(), 2):
		var p := found[i]
		var id := found[i + 1]
		var sh = _shape_of.get(id)
		if sh == null:
			if map.kind_of(id).begins_with("rail_bed"):
				if not _rail.has(p):
					_rail[p] = ["rail", map._owner[id], map.piece_poly(p), map.piece_box(p)]
				sh = _rail[p]
			else:
				continue  # filed in the map by someone else
		elif map.kind_of(id) == "curb_zone" and not (sh[0] in kinds or "other" in kinds):
			continue
		if (sh[3] as Rect2).intersects(box, true):
			out.append(sh)
	return out


## Lot `key`'s curb cut shapes ([] when it has none).
func cut_of(key: String) -> Array:
	_sync()
	return _cuts.get(key, [0, []])[1]


## Where a home's curbside mailbox stands (town x/z), or Vector2.INF when
## the lot has none (not a home). Real USPS curbside boxes stand just to
## the side of the driveway at the curb: here MAIL_BESIDE past the drive's
## edge, on the side toward the middle of the lot (else the other side),
## half a metre back from the curb, clear of any ramp, crosswalk and the
## neighbours' drives; slid along the curb if those take both sides. A
## home with no drive of its own (flats) keeps its box where it always
## stood, three tenths of the way across its frontage. `own_only`: where
## it goes by the lot's own drive alone, before anything else is looked at.
func mailbox_at(key: String, own_only := false) -> Vector2:
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null or not sim.lots.has(key) or not sim.buildings.has(key):
		return Vector2.INF
	var b: Dictionary = sim.buildings[key]
	if int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
		return Vector2.INF
	_sync()
	if not own_only and _mail.has(key):
		return _mail[key]
	var lot: Dictionary = sim.lots[key]
	var n: Vector3 = lot.normal
	var tc := float(lot.get("to_curb", 4.0))
	var z := -maxf(tc - 0.5, 0.3)
	var spots := []  # [where, which way along the curb is away from the drive]
	var entry: Array = _cuts.get(key, [0, [], {}])
	var lay: Dictionary = entry[2]
	if not lay.is_empty() and not lay.get("main_street", false) and not (entry[1] as Array).is_empty() \
			and BuildingTypes.type_of(b) in ["house", "duplex"]:
		var cx := float(lay.cut_x)
		var cw := float(lay.get("cut_w", 3.0))
		var inward := -1.0 if cx > 0.0 else 1.0  # toward the middle of the lot
		for s in [inward, -inward]:
			var w := SiteLayout.world(lot, Vector2(cx + s * (cw * 0.5 + MAIL_BESIDE + MAIL_HALF), z))
			spots.append([Vector2(w.x, w.z), SiteLayout.world_dir(lot, Vector2(s, 0.0))])
	else:
		var p: Vector3 = lot.front - n * maxf(tc - 0.5, 0.3) + (lot.dir as Vector3) * float(lot.get("width", 15.0)) * 0.3
		spots.append([Vector2(p.x, p.z), lot.dir as Vector3])
	if own_only:
		return spots[0][0]
	var pick := Vector2.INF
	for sp in spots:
		if is_free(sp[0], MAIL_HALF):
			pick = sp[0]
			break
	if pick == Vector2.INF:
		# Both sides taken (a ramp, a neighbour's drive): the nearest free
		# spot along the curb, away from the drive.
		var away: Vector3 = spots[0][1]
		pick = slide(spots[0][0], Vector2(away.x, away.z).normalized(), MAIL_HALF, MAIL_SLIDE, 0.0)
		if pick == Vector2.INF:
			pick = spots[0][0]
	_mail[key] = pick
	return pick


## A square `half` metres either way round `c`.
static func square(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half), c + Vector2(-half, half)])


# ------------------------------------------------------------------ lots

## Brings the lots' cuts up to date with the town: each built lot whose
## building or lot is a different one than its cut was worked out from
## (the sim replaces a building's dictionary when it is built, grown or
## rebuilt, and a lot's when it is planned again) and whose inputs really
## changed is worked out again; a lot gone takes its cut with it. Only a
## cut whose shapes changed is logged.
func _sync() -> void:
	if not _dirty:
		return
	_dirty = false
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	var redone := 0
	var first := _cuts.is_empty()
	var refile := _lots_moved or first
	_lots_moved = false
	if refile:
		_lot_cells.clear()
	var keys := sim.buildings.keys()
	keys.sort()
	var todo := []
	for key in keys:
		var lot = sim.lots.get(key)
		if lot == null or not lot.has("front") or not lot.has("dir"):
			continue
		var b: Dictionary = sim.buildings[key]
		var had: Array = _cuts.get(key, [])
		if refile or had.is_empty() or not is_same(had[4], lot):
			_file_lot(key, lot)
		if not had.is_empty() and is_same(had[3], b) and is_same(had[4], lot):
			continue
		todo.append(key)
	for key in todo:
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key]
		var had: Array = _cuts.get(key, [])
		var sig := _inputs(b, lot)
		if not had.is_empty() and int(had[0]) == sig:
			had[3] = b
			had[4] = lot
			continue
		redone += 1
		var entry := _work_out(sim, key, b, lot, sig)
		if not had.is_empty():
			_unfile(had[5])
		var ids := []
		for sh in entry[1]:
			ids.append(_file(sh, "curb_cut"))
		entry.append(ids)
		_cuts[key] = entry
		if not first:
			_log_shapes(had[1] if not had.is_empty() else [], entry[1])
	if _cuts.size() != keys.size():
		for key in _cuts.keys():
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_log_shapes(_cuts[key][1], [])
				_unfile(_cuts[key][5])
				_cuts.erase(key)
				_mail.erase(key)
	if first and redone > 0:
		_note(Rect2(-1e9, -1e9, 2e9, 2e9))
	last_sync_ms = (Time.get_ticks_usec() - t0) / 1000.0
	last_sync_lots = redone


## What a lot's cut is worked out from: its building (seed, type, stage,
## the drive side its house was given) and the lot itself.
static func _inputs(b: Dictionary, lot: Dictionary) -> int:
	return hash([b.get("seed"), b.get("zone"), b.get("type", ""), b.get("level", 0), b.get("units", 1),
		b.get("added_from", 0), b.get("drive", 0), b.get("chain", ""), lot.hash()])


func _file_lot(key: String, lot: Dictionary) -> void:
	var f: Vector3 = lot.front
	var d: Vector3 = lot.dir
	var hw := float(lot.get("width", 20.0)) * 0.5 + 2.0
	var tc := float(lot.get("to_curb", 4.0)) + 1.0
	var a := Vector2(f.x, f.z) + Vector2(d.x, d.z) * hw
	var b := Vector2(f.x, f.z) - Vector2(d.x, d.z) * hw
	var n := Vector2(lot.normal.x, lot.normal.z) * tc
	var box := Rect2(a, Vector2.ZERO).expand(b).expand(a - n).expand(b - n)
	for c in _cells(box):
		if not _lot_cells.has(c):
			_lot_cells[c] = []
		_lot_cells[c].append(key)


## Logs where a lot's cut shapes changed (none when they came out the same).
func _log_shapes(was: Array, now: Array) -> void:
	if was.size() == now.size():
		var same := true
		for i in was.size():
			same = same and was[i][2] == now[i][2]
		if same:
			return
	for s in was + now:
		_note(s[3])


## [inputs, cut shapes, layout] of built lot `key`: a home's or duplex's
## drive from its plan; anything else's paving from a dry run of its
## builder (BuildingView.curb_paving).
static func _work_out(sim: CitySim, key: String, b: Dictionary, lot: Dictionary, sig: int) -> Array:
	var lay := _layout(sim, key)
	var type := BuildingTypes.type_of(b)
	var shapes := []
	if type in ["house", "duplex"] or not b.has("seed"):
		var poly := lot_cut(lot, lay, type)
		if poly.size() >= 3:
			shapes.append(_shape("cut", "lot:" + key, poly))
	else:
		for c in BuildingView.curb_paving(sim, key):
			shapes.append(_shape("cut", "lot:" + key, paving_poly(lot, c)))
	return [sig, shapes, lay, b, lot]


## A built lot's layout (SiteLayout.for_lot), the traffic sim's copy when
## it has one.
static func _layout(sim: CitySim, key: String) -> Dictionary:
	if not sim.buildings.get(key, {}).has("seed"):
		return {}  # a bare stand-in building (tests): no drive to read
	if sim.traffic != null:
		var pl: Dictionary = sim.traffic.cached_place("lot:" + key)
		if pl.has("lay"):
			return pl.lay
	return SiteLayout.for_lot(sim, key)


# ------------------------------------------------------------------ geometry

static func _shape(kind: String, owner: String, poly: PackedVector2Array) -> Array:
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	return [kind, owner, poly, box]


## True when a square post `half` round `p` overlaps shape `s`.
static func _hits(s: Array, p: Vector2, half: float) -> bool:
	if not (s[3] as Rect2).intersects(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)):
		return false
	var post := square(p, half)
	for q in Geometry2D.intersect_polygons(post, s[2]):
		if not Geometry2D.is_polygon_clockwise(q) and _area(q) > 0.005:
			return true
	return false


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func _cells(box: Rect2) -> Array:
	var out := []
	for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			out.append(Vector2i(cx, cz))
	return out
