class_name CurbClaims
extends RefCounted
## "Is this stretch of curb free?" The one answer every curbside placer asks
## (Nathan, 2026-10-29: "I also noticed street signs in the middle of
## driveways ... we haven't yet implemented things like bus stops and items
## that will need to immediately make changes to the immediate environment
## like adjustments to the curb."). Stop, yield, No Turn and signal posts
## (JunctionView), streetlights (StreetLights.place), curbside mailboxes
## (mailbox_at: MailView, BuildingView) and street trees
## (BuildingView._parkway_free) all ask it, and so does the overlap auditor
## (tools/overlap_audit.gd), so they agree on what is taken.
##
## What claims the curb, as 2D shapes in the town's x/z:
##   - "ramp" and "crosswalk": the curb ramps and crosswalks at shaped town
##     corners (Junction.ramps, JunctionMarks), from the road view's
##     junction plans (set_junctions; RoadView pushes them as it plans).
##   - "cut": each built lot's drive where it crosses the parkway and
##     sidewalk to the street (its curb cut), from the lot's layout
##     (SiteLayout.for_lot: the house plan's drive, a shop's entrance).
## Bus stops and anything else that will change the curb add their own
## kind with claim().
##
## Read lazily and kept: a lot's cut is worked out the first time a query
## comes near it and again only when its building or lot changes. Plain
## data in, plain answers out: the same town gives the same answers.

## Grid cell (m) for the shapes and the lots' frontages.
const CELL := 24.0
## Kinds a post must keep off (everything here).
const ALL := ["ramp", "crosswalk", "cut", "other"]
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

var _sim: WeakRef
## Bumps when a junction plan or anything claimed changes (views redraw on it).
var version := 0
## Bumps only when the junction plans change (street trees re-check on it).
var junction_version := 0
var _junction := []  # [kind, owner, poly, box]
var _jgrid := {}  # Vector2i -> [shape index into _junction]
var _other := []  # claim()'d shapes
var _ogrid := {}
var _lot_cells := {}  # Vector2i -> [lot keys whose frontage reaches the cell]
var _lots_dirty := true
var _cuts := {}  # lot key -> [signature, [shapes]]
var _mail := {}  # lot key -> [stamp, Vector2]
var _drawn := {}  # lot key -> [shapes] of the aprons its builder drew (set_drawn)


## The town's claims (made on first use and kept on the sim).
static func of(sim: CitySim) -> CurbClaims:
	if sim == null:
		return null
	if sim.curb == null:
		var c := CurbClaims.new()
		c._sim = weakref(sim)
		sim.buildings_changed.connect(c._changed)
		sim.lots_changed.connect(c._changed)
		sim.curb = c
	return sim.curb


func _changed() -> void:
	_lots_dirty = true
	_mail.clear()
	version += 1


# ------------------------------------------------------------------ claims

## The curb ramps and crosswalks at the town's shaped corners, from the
## road view's junction plans (Junction.plan).
func set_junctions(plans: Dictionary) -> void:
	_junction = junction_shapes(plans)
	_jgrid = _index(_junction)
	_mail.clear()
	junction_version += 1
	version += 1


## Something new on the curb (a bus stop's pad, a hydrant): its footprint.
func claim(kind: String, owner: String, poly: PackedVector2Array) -> void:
	_other.append(_shape(kind, owner, poly))
	_ogrid = _index(_other)
	_mail.clear()
	version += 1


## Takes back what `owner` claimed.
func release(owner: String) -> void:
	_other = _other.filter(func(s): return s[1] != owner)
	_ogrid = _index(_other)
	_mail.clear()
	version += 1


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
					out.append(_shape("ramp", key, _arm_band(center, arm, pair[1], float(arm.hw),
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
				out.append(_shape("crosswalk", key, _arm_band(center, arm, 1.0, -float(arm.hw), float(arm.hw),
					d + JunctionMarks.CROSS_NEAR, d + JunctionMarks.CROSS_FAR)))
	return out


static func _arm_band(_center: Vector3, arm: Dictionary, side: float, o0: float, o1: float, from: float, to: float) -> PackedVector2Array:
	var p0: Array = LotPlanner.point_at(arm.pts, from)
	var p1: Array = LotPlanner.point_at(arm.pts, to)
	var a := Vector2(p0[0].x, p0[0].z)
	var b := Vector2(p1[0].x, p1[0].z)
	var dir := Vector2(p0[1].x, p0[1].z).normalized()
	var nrm := Vector2(-dir.y, dir.x) * side
	return PackedVector2Array([a + nrm * o0, b + nrm * o0, b + nrm * o1, a + nrm * o1])


## A built lot's curb cut: its drive across the parkway and sidewalk, from
## the lot line out to the curb ([] when it has none: built to the
## sidewalk, row homes and flats whose people park on the street). A
## house's or duplex's drive is as wide as its plan draws it. A shop's,
## office's or factory's entrance is the commercial apron their builders
## draw (HouseBuilder._curb_cut): COMMERCIAL_HALF either side of its middle,
## flared COMMERCIAL_FLARE more each side across the parkway to the curb.
const COMMERCIAL_HALF := 3.6
const COMMERCIAL_FLARE := 1.5
static func lot_cut(lot: Dictionary, lay: Dictionary, type: String) -> PackedVector2Array:
	if lay.is_empty() or lay.get("main_street", false) or (lay.get("spots", []) as Array).is_empty() and type != "house":
		return PackedVector2Array()
	var cx := float(lay.cut_x)
	var tc := float(lot.get("to_curb", 2.0))
	if type in ["house", "duplex"]:
		var cw := float(lay.get("cut_w", 3.0))
		return _local_poly(lot, [Vector2(cx - cw * 0.5, -tc), Vector2(cx + cw * 0.5, -tc), Vector2(cx + cw * 0.5, 0.0),
			Vector2(cx - cw * 0.5, 0.0)])
	return apron(lot, cx, COMMERCIAL_HALF, -tc)


## A commercial apron as HouseBuilder._curb_cut draws it: `half` either side
## of `x`, from the curb (`curb_z`, lot frame) across the parkway and
## sidewalk, flared COMMERCIAL_FLARE each side across the parkway.
static func apron(lot: Dictionary, x: float, half: float, curb_z: float) -> PackedVector2Array:
	var f := COMMERCIAL_FLARE
	var walk0 := curb_z + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	var walk1 := walk0 + RoadStyle.SIDEWALK_WIDTH
	return _local_poly(lot, [Vector2(x - half - f, curb_z), Vector2(x + half + f, curb_z), Vector2(x + half, walk0),
		Vector2(x + half, walk1), Vector2(x - half, walk1), Vector2(x - half, walk0)])


## What building `key`'s builder paved out to the curb (HouseBuilder.
## cuts_drawn: [x0, x1, curb z, flare] each, from BuildingView._draw for
## shops, offices and plants): where a drawing differs from the layout's
## reading (a brick works' drive straight in to its door), what is drawn is
## what claims the curb. None: the layout's cut stands.
func set_drawn(key: String, cuts) -> void:
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null or not sim.lots.has(key):
		return
	var shapes := []
	var lot: Dictionary = sim.lots[key]
	for c in (cuts if cuts != null else []):
		var x0 := float(c[0])
		var x1 := float(c[1])
		var cz := float(c[2])
		if float(c[3]) > 0.0:
			shapes.append(_shape("cut", "lot:" + key, apron(lot, (x0 + x1) * 0.5, (x1 - x0) * 0.5, cz)))
		else:
			var back := cz + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
			shapes.append(_shape("cut", "lot:" + key, _local_poly(lot, [Vector2(x0, cz), Vector2(x1, cz), Vector2(x1, back),
				Vector2(x0, back)])))
	var had: Array = _drawn.get(key, [])
	if had.size() == shapes.size() and shapes.all(func(s): return had.any(func(h): return h[2] == s[2])):
		return
	if shapes.is_empty():
		_drawn.erase(key)
	else:
		_drawn[key] = shapes
	_cuts.erase(key)
	_mail.clear()
	version += 1


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


## True when nothing at the junction corners (ramps, crosswalks) is under
## a spot (street trees ask this: they only need re-checking when the
## roads change).
func junction_free(p: Vector2, half: float) -> bool:
	return is_free(p, half, ["ramp", "crosswalk"])


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
## is clear, else slid back along its curb (`back_dir`, away from the
## junction) up to POST_BACK, or ahead up to POST_AHEAD, to the nearest
## clear spot; `base` if none is (MUTCD 2B.10: as near the stop point as
## practical, never more than 50 ft from the road it meets, and 4 ft or
## more behind the crosswalk, which POST_AHEAD keeps). 9 m back clears even
## a shop's flared 10 m apron.
const POST_BACK := 9.0
const POST_AHEAD := 0.5
func post_spot(base: Vector3, back_dir: Vector3, half: float, back := POST_BACK, ahead := POST_AHEAD) -> Vector3:
	var q := slide(Vector2(base.x, base.z), Vector2(back_dir.x, back_dir.z).normalized(), half + 0.1, back, ahead)
	if not q.is_finite():
		return base
	return Vector3(q.x, base.y, q.y)


## Everything claimed in `box` (of `kinds`): [kind, owner, poly, box] each.
func near(box: Rect2, kinds := ALL) -> Array:
	var out := []
	if "ramp" in kinds or "crosswalk" in kinds:
		for i in _in(_jgrid, box):
			var s: Array = _junction[i]
			if s[0] in kinds and (s[3] as Rect2).intersects(box, true):
				out.append(s)
	if "cut" in kinds:
		_sync_lots()
		var seen := {}
		for c in _cells(box):
			for key in _lot_cells.get(c, []):
				if seen.has(key):
					continue
				seen[key] = true
				for s in _cut_of(key):
					if (s[3] as Rect2).intersects(box, true):
						out.append(s)
	for i in _in(_ogrid, box):
		var s: Array = _other[i]
		if (s[0] in kinds or "other" in kinds) and (s[3] as Rect2).intersects(box, true):
			out.append(s)
	return out


## Lot `key`'s curb cut shapes ([] when it has none).
func cut_of(key: String) -> Array:
	_sync_lots()
	return _cut_of(key)


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
	var stamp := version
	var hit: Array = _mail.get(key, [])
	if not own_only and not hit.is_empty() and hit[0] == stamp:
		return hit[1]
	var lot: Dictionary = sim.lots[key]
	var n: Vector3 = lot.normal
	var tc := float(lot.get("to_curb", 4.0))
	var z := -maxf(tc - 0.5, 0.3)
	var spots := []  # [where, which way along the curb is away from the drive]
	var entry := _entry(key)
	var lay: Dictionary = entry[3]
	if not lay.is_empty() and not lay.get("main_street", false) and not (entry[1] as Array).is_empty():
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
	_mail[key] = [stamp, pick]
	return pick


## A square `half` metres either way round `c`.
static func square(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half), c + Vector2(-half, half)])


# ------------------------------------------------------------------ lots

## The lots' frontages by grid cell, again when lots or buildings changed.
func _sync_lots() -> void:
	if not _lots_dirty:
		return
	_lots_dirty = false
	_lot_cells.clear()
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null:
		return
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		if not lot.has("front") or not lot.has("dir"):
			continue
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
	# Lots gone, or no longer built, drop their cuts.
	for key in _cuts.keys():
		if not sim.buildings.has(key) or not sim.lots.has(key):
			_cuts.erase(key)
			_drawn.erase(key)


## A lot's cut shapes.
func _cut_of(key: String) -> Array:
	return _entry(key)[1]


## A built lot's [what it was worked out from, cut shapes, version last
## looked at, layout]: worked out again only when its building or lot
## changed (or, on a corner, the roads: which side its side street is).
func _entry(key: String) -> Array:
	var sim: CitySim = _sim.get_ref() if _sim != null else null
	if sim == null or not sim.buildings.has(key) or not sim.lots.has(key):
		return [0, [], -1, {}]
	var hit: Array = _cuts.get(key, [])
	if not hit.is_empty() and hit[2] == version:
		return hit  # looked at since the town last changed
	var b: Dictionary = sim.buildings[key]
	var lot: Dictionary = sim.lots[key]
	var corner: bool = lot.get("corner", false)
	var sig := hash([b.get("seed"), b.get("zone"), b.get("type", ""), b.get("level", 0), b.get("units", 1),
		b.get("added_from", 0), int(b.get("built", 0)) >= sim.curb_drives_from, lot.hash(),
		sim.network.revision if corner else 0])
	if not hit.is_empty() and hit[0] == sig:
		hit[2] = version
		return hit
	var lay := _layout(sim, key)
	var shapes := []
	if _drawn.has(key):
		shapes = _drawn[key]  # as its builder drew it
	else:
		var poly := lot_cut(lot, lay, BuildingTypes.type_of(b))
		if poly.size() >= 3:
			shapes.append(_shape("cut", "lot:" + key, poly))
	var entry := [sig, shapes, version, lay]
	_cuts[key] = entry
	return entry


## A built lot's layout (SiteLayout.for_lot), the traffic sim's copy when
## it has one.
static func _layout(sim: CitySim, key: String) -> Dictionary:
	if not sim.buildings.get(key, {}).has("seed"):
		return {}  # a bare stand-in building (tests): no drawn drive to read
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


static func _index(shapes: Array) -> Dictionary:
	var g := {}
	for i in shapes.size():
		for c in _cells(shapes[i][3]):
			if not g.has(c):
				g[c] = []
			g[c].append(i)
	return g


static func _in(g: Dictionary, box: Rect2) -> Array:
	var out := {}
	for c in _cells(box):
		for i in g.get(c, []):
			out[i] = true
	var keys := out.keys()
	keys.sort()
	return keys
