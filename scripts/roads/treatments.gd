class_name RoadTreatments
extends RefCounted
## Road treatments (docs/spec-road-treatments.md, step 1): each side of a
## street dresses for what's built along it. Nathan, 2026-10-29: "If you
## build a road and then put factories on it then the factory treatment
## might get applied to the road... you'll have to figure out how to treat
## spaces where there are different things on either side of the road."
##
## A layer over the roads: it reads the frontage built along each side and
## hands out a kind per side and one for the middle (the shared pavement).
## It never changes a road's width, lanes or lots. Step 1 gives two kinds a
## look and rules, from real places:
##   - Factory (GM's Marion stamping plant on the west side, the warehouses
##     by the I-69 exits): a truck route, no curb parking (MUTCD R7-1 NO
##     PARKING signs; trucks may still stand to load), jointed concrete
##     down the middle, a narrow walk.
##   - Main street (Marion's courthouse square, Gas City's Main Street):
##     20 mph on a street and 25 on bigger roads, the walk paved from the
##     curb to the storefronts with a brick band, painted stalls and no
##     driveway cuts (shops use the alley), so more curb stalls fit.
## Shops that don't make a main street (Strip shops) and homes are judged
## too, so they hold their side against a stray factory or shop, but keep
## today's look until steps 2 and 3.
##
## How a side picks (the spec's rules): the frontage of finished buildings
## along it, by kind, over the side's length. The biggest kind takes the
## side if it covers WIN of it and beats what the side has by MARGIN. Nathan
## (2026-10-29, "A"): a change comes right away once a building is done. A
## side only falls back to a lighter kind (its buildings gone) after HOLD,
## as real fixtures outlast the businesses. The middle follows the heavier
## side, and gets lighter only once the street is next resurfaced. The
## player may lock a side (Nathan 2026-10-29, "A": keeping what's there is
## free, changing it costs what resurfacing that road piece costs).
##
## Every copy of the town works the same out at the same ticks (it only
## looks on the 10-tick boundaries), and each side's kind is saved, so a
## reload never flips a side.

signal changed(segs: Array)

const FACTORY := "factory"
const MAIN := "main"
const STRIP := "strip"
const HOMES := "homes"
## Heaviest use first: ties and the middle go to the earlier one.
const HEAVY := [FACTORY, STRIP, MAIN, HOMES]
## The kinds step 1 draws and gives rules (the rest look as today).
const DRAWN := [FACTORY, MAIN]
const NAMES := {FACTORY: "Factory", MAIN: "Main street", STRIP: "Shops", HOMES: "Homes", "": "Plain"}
## Share of a side's length the biggest kind must cover, and how far ahead
## of the side's kind another must be to take it over.
const WIN := 0.40
const MARGIN := 0.15
## A side whose kind's buildings are gone keeps its fixtures this long (a
## game year: 12 sim days, Seasons.pace_year).
const HOLD := 12 * 24 * CitySim.TICKS_PER_HOUR
## It looks again on these ticks when anything changed.
const EVERY := 10
const PHASE := 3
## Main street speed limits, mph: a street, and anything bigger.
const MAIN_MPH_STREET := 20
const MAIN_MPH_ROAD := 25
## The main street limit on a street in use (20, or 25 to leave streets at
## their own limit: Nathan's call, 2026-10-29; game_day compares them).
var main_mph_street := MAIN_MPH_STREET

## Side key (seg * 2, +1 for the right-hand side) -> {"kind", "at": tick it
## changed, "fade": tick its kind stopped holding the side, or -1}.
var sides := {}
## Road piece -> {"kind", "at"}: the middle.
var mids := {}
## Side key -> kind the player locked it as ("" for plain). The lock hook
## (spec step 4): a locked side never changes on its own.
var locks := {}
## Side key -> {kind: share of the side} as last worked out (not saved: the
## first look after a load works it out again). For the road's card.
var shares := {}
var revision := 0
var _dirty := true
var _fading := {}  # side keys whose kind is fading
## The kept frontage sums: side key -> {kind: cm}, shops along each side,
## each building's part [lot, zone, counts, side key, kind, cm], and the
## sites' (warehouses, big factories) side key -> cm.
var _cm := {}
var _shops := {}
var _by_key := {}
var _site_cm := {}
var _net_rev := -1
var _next_done := -1  # tick the next building under way along a road is done
var _len := {}  # seg -> [its curve, metres]
## A town loaded from a save before treatments: every side is judged on the
## first look, not just the ones that changed.
var _judge_all := false
## Buildings or lots changed since the last look (or a building is done).
var _scan := true
## Buildings rebuilt in place, as a save had them: lot key -> [side key,
## kind, cm] of what stood there (used by the first scan after a load).
var _held_saved := {}
var _going := {}  # what's going up, as the last scan saw it


static func key_of(seg: int, side: int) -> int:
	return seg * 2 + (1 if side > 0 else 0)


static func rank(kind: String) -> int:
	var i := HEAVY.find(kind)
	return HEAVY.size() if i < 0 else i


## The heavier of two kinds ("" is lightest).
static func heavier(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a if rank(a) <= rank(b) else b


func kind(seg: int, side: int) -> String:
	return str(sides.get(key_of(seg, side), {}).get("kind", ""))


func mid(seg: int) -> String:
	return str(mids.get(seg, {}).get("kind", ""))


## What the road mesh needs: {"left", "right", "mid"} with only the drawn
## kinds, or {} for a plain road (so plain roads keep their cached mesh).
func look(seg: int) -> Dictionary:
	var l := kind(seg, -1)
	var r := kind(seg, 1)
	var m := mid(seg)
	if not (l in DRAWN or r in DRAWN or m in DRAWN):
		return {}
	return {"left": l if l in DRAWN else "", "right": r if r in DRAWN else "", "mid": m if m in DRAWN else ""}


# ------------------------------------------------------------------- rules

## The road piece's speed limit with its treatment, mph (the lower of the
## two sides'), or 0 when the treatment leaves it be.
func mph(seg: int, type: int) -> int:
	var own: int = int(RoadStyle.TYPES[type].mph)
	var cap := 0
	for side in [-1, 1]:
		if kind(seg, side) == MAIN:
			var m := main_mph_street if RoadStyle.group(type) == RoadStyle.Type.STREET else MAIN_MPH_ROAD
			cap = m if cap == 0 else mini(cap, m)
	return cap if cap > 0 and cap < own else 0


## A factory middle is a truck route under the Truck routes law.
func truck_route(seg: int) -> bool:
	return mid(seg) == FACTORY


## No car parking at the curb on a factory side.
func no_parking(seg: int, side: int) -> bool:
	return kind(seg, side) == FACTORY


## No driveway cuts on a main street side: the curb is all stalls.
func no_aprons(seg: int, side: int) -> bool:
	return kind(seg, side) == MAIN


# ------------------------------------------------------------- the ticking

## Something along the roads changed: look again on the next boundary.
func touch() -> void:
	_dirty = true
	_scan = true


func tick(sim) -> void:
	var now: int = sim.tick_count
	if now % EVERY != PHASE:
		return
	if _next_done >= 0 and now >= _next_done:
		_dirty = true
		_scan = true
	if _dirty:
		_dirty = false
		update(sim)
	elif not _fading.is_empty():
		_decide_all(sim, _fading.keys())


## Looks again at the sides whose frontage changed (and those fading).
func update(sim) -> void:
	var t := Perf.now()
	var keys := _frontage_changes(sim)
	Perf.add("sim.treatments.sums", t)
	for k in _fading:
		keys[k] = true
	if _judge_all:
		_judge_all = false
		for k in shares:
			keys[k] = true
		for k in sides:
			keys[k] = true
	_decide_all(sim, keys.keys())
	Perf.add("sim.treatments", t)


func _decide_all(sim, keys: Array) -> void:
	keys.sort()
	var now: int = sim.tick_count
	var touched := {}
	for k in keys:
		var seg: int = int(k) >> 1
		if not sim.network.segments.has(seg):
			continue
		var cur: Dictionary = sides.get(k, {"kind": "", "at": 0, "fade": -1})
		var want := ""
		var fade := -1
		if locks.has(k):
			want = str(locks[k])
		else:
			var d := _judge(str(cur.kind), shares.get(k, {}))
			want = d[0]
			if d[1]:
				fade = int(cur.get("fade", -1))
				if fade < 0:
					fade = now
				elif now - fade >= HOLD:
					want = d[2]
					fade = -1
		if want != str(cur.kind):
			cur = {"kind": want, "at": now, "fade": -1}
			touched[seg] = true
		else:
			cur.fade = fade
		if str(cur.kind) == "" and int(cur.fade) < 0:
			sides.erase(k)
		else:
			sides[k] = cur
		if int(cur.fade) >= 0:
			_fading[k] = true
		else:
			_fading.erase(k)
	for seg in touched:
		_set_mid(sim, seg)
	# A lighter middle waits for the street to be resurfaced.
	for seg in mids.keys():
		if not touched.has(seg) and sim.network.segments.has(seg):
			var want := heavier(kind(seg, -1), kind(seg, 1))
			if want != mid(seg) and _repaved_since(sim, seg, int(mids[seg].at)):
				_set_mid(sim, seg)
				touched[seg] = true
	if not touched.is_empty():
		var segs := touched.keys()
		segs.sort()
		revision += 1
		push(sim, segs)
		changed.emit(segs)


func _set_mid(sim, seg: int, repaved := false) -> void:
	var want := heavier(kind(seg, -1), kind(seg, 1))
	var have := mid(seg)
	if want == have:
		return
	if have != "" and rank(want) > rank(have) and not repaved and not _repaved_since(sim, seg, int(mids[seg].at)):
		return  # the concrete stays till the street is next resurfaced
	if want == "":
		mids.erase(seg)
	else:
		mids[seg] = {"kind": want, "at": int(sim.tick_count)}


static func _repaved_since(sim, seg: int, at: int) -> bool:
	var paved: Dictionary = sim.street_age.paved
	return int(paved.get(StreetAge.cell_of(sim, seg), -1)) > at


## decide, with the holds that keep fixtures in place (spec rule 6, and
## Nathan's "A" on 2026-10-29: the lanterns and brick stay and wear): a side
## goes to a lighter kind only after HOLD, and a main street whose shops
## drop under Balance.MAIN_STREET_SHOPS (one being rebuilt, say) stays a
## main street through the same hold rather than turning Strip and back.
## Heavier kinds still take a side right away, past the margin.
static func _judge(cur: String, side_shares: Dictionary) -> Array:
	var d := decide(cur, side_shares)
	if cur == MAIN and d[0] == STRIP and not side_shares.has(MAIN):
		return [MAIN, true, STRIP]  # the same shops, relabelled: held
	if cur != "" and d[0] != cur and rank(d[0]) > rank(cur):
		return [cur, true, d[0]]  # lighter: held a game year
	return d


## A side's kind from its kind now and the shares of its length:
## [kind, fading (its kind no longer holds the side), what it falls back to
## once the fade is over].
static func decide(cur: String, side_shares: Dictionary) -> Array:
	var best := ""
	var best_s := 0.0
	for k: String in side_shares:
		var s: float = side_shares[k]
		if s > best_s + 0.0001 or (absf(s - best_s) <= 0.0001 and best != cur
				and (k == cur or rank(k) < rank(best))):
			best = k
			best_s = s
	var cur_s: float = side_shares.get(cur, 0.0)
	var fallback := best if best_s >= WIN else ""
	if best != cur and best_s >= WIN and (cur == "" or best_s >= cur_s + MARGIN - 0.0001):
		return [best, false, fallback]
	return [cur, cur != "" and cur_s < WIN, fallback]


## Adds up what's built along every road once, as a town loads, so its
## first look in play only looks at what changed (the whole town's sums
## cost the big town 6.5-9 ms, too long for a frame: review, 2026-10-29).
## Decides nothing, so it changes nothing a copy of the town would see.
func warm(sim) -> void:
	var t := Perf.now()
	_frontage_changes(sim)
	# Frontage that changed in the ticks before the save hasn't been judged
	# yet: the first look judges every side (a side with nothing new comes
	# out as it is), as the town that saved would have.
	_judge_all = true
	Perf.add("load.treatments", t)


## Every side's frontage: side key -> {kind: share of its length}, worked
## out afresh (what the kept sums add up to; for tests).
func frontage(sim) -> Dictionary:
	var fresh := RoadTreatments.new()
	fresh._frontage_changes(sim)
	return fresh.shares


## Brings the frontage sums up to date with what's built, a building at a
## time (each building's part is kept, so only what changed is added or
## taken away), and works out the shares of the sides that changed.
## Lengths are summed in whole centimetres, so the sums come out the same
## in whatever order buildings came and went (a reloaded copy agrees).
## Only finished buildings count; empty lots count as length, not a kind.
## Returns the side keys that changed, as a set.
func _frontage_changes(sim) -> Dictionary:
	var changed := {}
	if _net_rev != int(sim.network.revision):
		# The roads changed: only the sides of road pieces that are gone or
		# reshaped are looked at again (a lot cut afresh along a new road is
		# a new lot, so its building's part moves over below). Wiping it all
		# cost the big town 6.5-9 ms on every road drawn (review,
		# 2026-10-29).
		_net_rev = int(sim.network.revision)
		var keys := {}
		for k in _cm:
			keys[k] = true
		for k in shares:
			keys[k] = true
		for k in keys:
			var seg: int = int(k) >> 1
			if not sim.network.segments.has(seg):
				changed[k] = true
				_len.erase(seg)
			elif _len.has(seg) and not is_same(_len[seg][2], sim.network.segments[seg]):
				changed[k] = true
	if _scan:
		_scan = false
		_scan_buildings(sim, changed)
	# Warehouses and big factories face their road too (a handful: worked
	# out afresh each time).
	var sites := {}
	for id in sim.warehouses.buildings:
		var w: Dictionary = sim.warehouses.buildings[id]
		if not Warehouses.is_store(w) and not _going.has("wh:%d" % id):
			_add_site(sim, sites, w.pos, w.dir, Warehouses.site_width(w))
	for id in sim.big.sites:
		var f: Dictionary = sim.big.sites[id]
		_add_site(sim, sites, f.pos, f.dir, BigFactories.site_width(f))
	if sites != _site_cm:
		for k in sites:
			if int(sites[k]) != int(_site_cm.get(k, -1)):
				changed[k] = true
		for k in _site_cm:
			if not sites.has(k):
				changed[k] = true
		_site_cm = sites
	for k in changed:
		_share(sim, k)
	return changed


## Brings each building's part up to date (built, gone, rezoned, done going
## up, its lot cut afresh). Only when buildings or lots changed: a road drawn
## alone needs just its own sides looked at.
func _scan_buildings(sim, changed: Dictionary) -> void:
	var going := {}  # lot key -> true while it's going up
	_going = going
	_next_done = -1
	var now: int = sim.tick_count
	for ref: String in sim.construction.sites:
		var lot_ref := ref.begins_with("lot:")
		if not lot_ref and not ref.begins_with("wh:"):
			continue
		var c: Dictionary = sim.construction.sites[ref]
		var profile := str(c.profile)
		if not Construction.PROFILES.has(profile):
			continue
		var done := int(c.start) + Construction.duration(profile)
		if done > now:
			going[ref.substr(4) if lot_ref else ref] = true
			_next_done = done if _next_done < 0 else mini(_next_done, done)
	# Every building is looked at, so this loop is kept lean (2,800 in the
	# big town): most are unchanged.
	var lots: Dictionary = sim.lots
	var blds: Dictionary = sim.buildings
	var any_going := not going.is_empty()
	for key: String in blds:
		var lot = lots.get(key)
		var z = blds[key].zone
		var part = _by_key.get(key)
		var rising: bool = any_going and going.has(key)
		var counts: bool = lot != null and not rising
		if part != null:
			if rising and int(part[3]) >= 0:
				# Rebuilt in place (redevelopment): what stood there counts
				# until the new one is done, so a main street doesn't flip
				# to Strip and back while a shop is rebuilt.
				part[6] = true
				continue
			if not part[6] and is_same(part[0], lot) and part[1] == z and part[2] == counts:
				continue
			_take(part, changed)
		elif rising and _held_saved.has(key):
			# Saved as rebuilt in place: counts as what stood there.
			var h: Array = _held_saved[key]
			part = [lot, z, false, int(h[0]), str(h[1]), int(h[2]), true]
			_put(part, changed)
			_by_key[key] = part
			continue
		part = [lot, z, counts, -1, "", 0, false]
		if counts and sim.network.segments.has(int(lot.get("seg", -1))):
			var what := ""
			if z == ZoneMap.Zone.INDUSTRIAL:
				what = FACTORY
			elif z == ZoneMap.Zone.COMMERCIAL:
				what = STRIP
			elif z == ZoneMap.Zone.RESIDENTIAL:
				what = HOMES
			if what != "":
				part[3] = key_of(int(lot.seg), int(lot.side))
				part[4] = what
				part[5] = roundi(float(lot.get("width", 0.0)) * 100.0)
				_put(part, changed)
		_by_key[key] = part
	if _by_key.size() != sim.buildings.size():
		for key in _by_key.keys():
			if not sim.buildings.has(key):
				_take(_by_key[key], changed)
				_by_key.erase(key)
	_held_saved.clear()


func _put(part: Array, changed: Dictionary) -> void:
	var k: int = part[3]
	if not _cm.has(k):
		_cm[k] = {}
	_cm[k][part[4]] = int(_cm[k].get(part[4], 0)) + int(part[5])
	if part[4] == STRIP:
		_shops[k] = int(_shops.get(k, 0)) + 1
	changed[k] = true


func _take(part: Array, changed: Dictionary) -> void:
	var k: int = part[3]
	if k < 0 or not _cm.has(k):
		return
	_cm[k][part[4]] = int(_cm[k].get(part[4], 0)) - int(part[5])
	if int(_cm[k][part[4]]) <= 0:
		_cm[k].erase(part[4])
	if part[4] == STRIP:
		_shops[k] = int(_shops.get(k, 0)) - 1
		if int(_shops[k]) <= 0:
			_shops.erase(k)
	if _cm[k].is_empty():
		_cm.erase(k)
	changed[k] = true


## One side's shares from its sums. Shops make a main street where enough
## line the side (BuildingTypes' own Main Street test,
## Balance.MAIN_STREET_SHOPS); otherwise they're strip shops.
func _share(sim, k: int) -> void:
	var length := seg_length(sim, k >> 1)
	var cm: Dictionary = _cm.get(k, {}).duplicate()
	if _site_cm.has(k):
		cm[FACTORY] = int(cm.get(FACTORY, 0)) + int(_site_cm[k])
	if cm.has(STRIP) and int(_shops.get(k, 0)) >= Balance.MAIN_STREET_SHOPS:
		cm[MAIN] = cm[STRIP]
		cm.erase(STRIP)
	if length < 1.0 or cm.is_empty():
		shares.erase(k)
		return
	var row := {}
	for what in cm:
		row[what] = snappedf(minf(float(cm[what]) / (length * 100.0), 1.0), 0.0001)
	shares[k] = row


## A site facing a road from `pos` (the middle of its street edge), `dir`
## pointing out to the road: its width, in cm, on that side.
static func _add_site(sim, sites: Dictionary, pos: Vector3, dir: Vector3, width: float) -> void:
	var near := RoadIndex.segment_near(sim.network, pos + dir * 4.0, 30.0, 2.0)
	if near.is_empty():
		return
	var c: Array = sim.network.curve_of(near.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	var normal := Vector3(-tan.z, 0.0, tan.x)
	var side := 1 if (pos - near.point).dot(normal) > 0.0 else -1
	var k := key_of(near.seg, side)
	sites[k] = int(sites.get(k, 0)) + roundi(width * 100.0)


## A road piece's length, kept until that piece changes shape.
func seg_length(sim, seg: int) -> float:
	if not sim.network.segments.has(seg):
		return 0.0
	var had: Array = _len.get(seg, [])
	if had.is_empty() or not is_same(had[2], sim.network.segments[seg]):
		var c: Array = sim.network.curve_of(seg)
		if had.is_empty() or had[0] != c:
			had = [c, RoadNetwork.polyline_length(sim.network.sample_segment(seg)), null]
		had[2] = sim.network.segments[seg]
		_len[seg] = had
	return float(had[1])


## Hands the rules for these road pieces to the traffic.
func push(sim, segs: Array) -> void:
	for seg in segs:
		if not sim.network.segments.has(seg):
			continue
		var type: int = sim.network.segments[seg].type
		var park := []
		var aprons := []
		for side in [-1, 1]:
			if no_parking(seg, side):
				park.append(side)
			if no_aprons(seg, side):
				aprons.append(side)
		sim.traffic.set_treatment(seg, mph(seg, type), truck_route(seg), park, aprons)


func push_all(sim) -> void:
	var segs := {}
	for k in sides:
		segs[int(k) >> 1] = true
	for seg in mids:
		segs[seg] = true
	var list := segs.keys()
	list.sort()
	sim.traffic.clear_treatments()
	push(sim, list)


# -------------------------------------------------------- roads changing

## A road piece cut in two: both halves keep its sides, middle and locks.
func split(seg: int, first: int, second: int, sim = null) -> void:
	for side in [0, 1]:
		var k: int = seg * 2 + side
		for half in [first, second]:
			if sides.has(k):
				sides[half * 2 + side] = sides[k].duplicate()
			if locks.has(k):
				locks[half * 2 + side] = locks[k]
		sides.erase(k)
		locks.erase(k)
		if _fading.has(k):
			_fading.erase(k)
			_fading[first * 2 + side] = true
			_fading[second * 2 + side] = true
	if mids.has(seg):
		mids[first] = mids[seg].duplicate()
		mids[second] = mids[seg].duplicate()
		mids.erase(seg)
	_dirty = true
	if sim != null:
		# The halves carry the street's rules at once, as a reloaded copy
		# would (review, 2026-10-30: they looked treated but drove plain).
		sim.traffic.set_treatment(seg, 0, false, [], [])
		push(sim, [first, second])
		revision += 1
		changed.emit([first, second])


## The roads changed: what was on road pieces now gone goes with them.
func roads_changed(sim) -> void:
	for k in sides.keys():
		if not sim.network.segments.has(int(k) >> 1):
			sides.erase(k)
			_fading.erase(k)
	for k in locks.keys():
		if not sim.network.segments.has(int(k) >> 1):
			locks.erase(k)
	for seg in mids.keys():
		if not sim.network.segments.has(seg):
			mids.erase(seg)
	sim.traffic.forget_gone_treatments()
	_dirty = true


## What undo puts back with the roads (UndoLog): each side's kind, the
## middles and the locks, as they were before a road command.
func snapshot() -> Dictionary:
	return {"sides": sides.duplicate(true), "mids": mids.duplicate(true), "locks": locks.duplicate()}


## Puts back a snapshot() once the roads are as they were, and hands the
## rules to the traffic again.
func restore(sim, snap: Dictionary) -> void:
	var segs := {}
	for k in sides:
		segs[int(k) >> 1] = true
	for seg in mids:
		segs[seg] = true
	sides = snap.sides.duplicate(true)
	mids = snap.mids.duplicate(true)
	locks = snap.locks.duplicate()
	_fading.clear()
	for k in sides:
		segs[int(k) >> 1] = true
		if int(sides[k].get("fade", -1)) >= 0:
			_fading[k] = true
	for seg in mids:
		segs[seg] = true
	roads_changed(sim)
	_dirty = true
	_scan = true
	revision += 1
	push_all(sim)
	var list := segs.keys().filter(func(seg): return sim.network.segments.has(seg))
	list.sort()
	changed.emit(list)


# ---------------------------------------------------------------- locking

## What it costs to set a side to `want` ("auto" to let it go again): free
## to keep what's there or go back to Auto; resurfacing the road piece to
## change it (StreetAge.repave_cost, about $130 a lane-metre).
func lock_cost(sim, seg: int, side: int, want: String) -> int:
	if not sim.network.segments.has(seg):
		return -1
	if want == "auto" or want == kind(seg, side):
		return 0
	var type: int = sim.network.segments[seg].type
	return StreetAge.repave_cost(seg_length(sim, seg) * float(RoadStyle.TYPES[type].lanes), type)


## Locks a side as `want`, or lets it go ("auto"). Returns the cost, or -1.
func set_lock(sim, seg: int, side: int, want: String) -> int:
	if not sim.network.segments.has(seg) or not (want == "auto" or want == "" or want in HEAVY):
		return -1
	var cost := lock_cost(sim, seg, side, want)
	var k := key_of(seg, side)
	if want == "auto":
		locks.erase(k)
	else:
		locks[k] = want
	_decide_all(sim, [k])
	if cost > 0:
		# Paid for as a resurfacing: the middle is laid new at once (no
		# waiting for the next natural repave), and its rules with it.
		var was := mid(seg)
		_set_mid(sim, seg, true)
		if mid(seg) != was:
			revision += 1
			push(sim, [seg])
			changed.emit([seg])
	return cost


## The card's buttons for a road piece: lock each treated side, or change
## it to the other treatment. A side with today's look gets none yet (the
## full picker, any kind on any side, is step 4), so a home street's card
## stays as it was.
func actions(sim, seg: int) -> Array:
	var out := []
	if not sim.network.segments.has(seg) or not RoadStyle.TYPES[sim.network.segments[seg].type].lots \
			or RoadStyle.is_freeway(sim.network.segments[seg].type):
		return out
	for side in [-1, 1]:
		var name := side_name(sim, seg, side)
		var k := key_of(seg, side)
		var now := kind(seg, side)
		if not now in DRAWN and not locks.has(k):
			continue
		if locks.has(k):
			out.append({"label": "%s: back to Auto" % name,
				"cmd": {"type": "road_treatment", "seg": seg, "side": side, "kind": "auto"}})
		else:
			out.append({"label": "%s: keep it %s (free)" % [name, NAMES[now]],
				"cmd": {"type": "road_treatment", "seg": seg, "side": side, "kind": now}})
		for other in DRAWN:
			if other == now:
				continue
			var cost := lock_cost(sim, seg, side, other)
			out.append({"label": "%s: make it %s ($%s)" % [name, NAMES[other], CitySim.money_text(cost)],
				"cmd": {"type": "road_treatment", "seg": seg, "side": side, "kind": other},
				"enabled": cost <= sim.economy.money})
	return out


# ------------------------------------------------------------- the card

## "North side" and so on: which way a side of the road piece faces.
static func side_name(sim, seg: int, side: int) -> String:
	var c: Array = sim.network.curve_of(seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], 0.5)
	var n := Vector2(-tan.z, tan.x) * float(side)
	# -z is north on the map.
	if absf(n.y) >= absf(n.x):
		return "North side" if n.y < 0.0 else "South side"
	return "East side" if n.x > 0.0 else "West side"


## Rows for the road's card: each side's kind and why, then the rules.
func rows(sim, seg: int) -> Array:
	var out := []
	var type: int = sim.network.segments[seg].type
	if not RoadStyle.TYPES[type].lots or RoadStyle.is_freeway(type):
		return out
	var parts := []
	for side in [-1, 1]:
		var k := key_of(seg, side)
		var now := kind(seg, side)
		var why := ""
		var share: float = shares.get(k, {}).get(now, 0.0)
		if locks.has(k):
			why = "locked"
		elif now != "" and share > 0.0:
			why = "%d%% of the frontage" % roundi(share * 100.0)
		elif now != "":
			why = "kept from before"
		elif not shares.get(k, {}).is_empty():
			why = "nothing has 40% of the frontage"
		var shown: String = NAMES[now] + ("" if now in DRAWN or now == "" else " (today's look)")
		out.append([side_name(sim, seg, side), shown + (" (%s)" % why if why != "" else "")])
	if truck_route(seg):
		parts.append("Truck route")
	for side in [-1, 1]:
		if no_parking(seg, side):
			parts.append("No parking on the %s" % side_name(sim, seg, side).to_lower())
	var limit := mph(seg, type)
	if limit > 0:
		parts.append("%d mph" % limit)
	if not parts.is_empty():
		out.append(["Street rules", " · ".join(parts)])
	return out


# ----------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var s := []
	var keys := sides.keys()
	keys.sort()
	for k in keys:
		s.append([k, str(sides[k].kind), int(sides[k].at), int(sides[k].get("fade", -1))])
	var m := []
	keys = mids.keys()
	keys.sort()
	for k in keys:
		m.append([k, str(mids[k].kind), int(mids[k].at)])
	var l := []
	keys = locks.keys()
	keys.sort()
	for k in keys:
		l.append([k, str(locks[k])])
	# Buildings being rebuilt in place, counted as what stood there.
	var h := []
	keys = _by_key.keys()
	keys.sort()
	for key in keys:
		var part: Array = _by_key[key]
		if part[6] and int(part[3]) >= 0:
			h.append([key, int(part[3]), str(part[4]), int(part[5])])
	return {"sides": s, "mids": m, "locks": l, "held": h}


## `d` empty (a town saved before treatments): worked out fresh on the
## first look.
func from_dict(d: Dictionary) -> void:
	sides.clear()
	mids.clear()
	locks.clear()
	shares.clear()
	for e in d.get("sides", []):
		sides[int(e[0])] = {"kind": str(e[1]), "at": int(e[2]), "fade": int(e[3])}
	for e in d.get("mids", []):
		mids[int(e[0])] = {"kind": str(e[1]), "at": int(e[2])}
	for e in d.get("locks", []):
		locks[int(e[0])] = str(e[1])
	_held_saved.clear()
	for e in d.get("held", []):
		_held_saved[str(e[0])] = [int(e[1]), str(e[2]), int(e[3])]
	_dirty = true
	_next_done = -1
	_fading.clear()
	for k in sides:
		if int(sides[k].fade) >= 0:
			_fading[k] = true
	_cm.clear()
	_shops.clear()
	_by_key.clear()
	_site_cm.clear()
	_net_rev = -1
	_len.clear()
	_scan = true
	_going = {}
	_judge_all = d.is_empty()
	revision += 1
