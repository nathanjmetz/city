class_name Timelapse
extends RefCounted
## The town's growth, kept for a timelapse (Brawn, 2026-10-23): replay it
## from a single crossroads to today.
##
## Real reference: the Sanborn fire insurance maps (1867 to 1970s, Library of
## Congress) that drew nearly every American town block by block, sheet after
## sheet over the decades; laid side by side they are how historians watch a
## town grow. The timelapse view (scripts/ui/timelapse_view.gd) draws this
## record the same way, in Sanborn's colours.
##
## What's kept is a record, not snapshots of everything: each road and each
## building with the month it appeared and the month it went (if it did),
## plus the town's population and nickname over time. Taken once a game
## month by comparing what's there with what was (O(roads + buildings)),
## so nothing runs per tick and nothing is copied twice.

## Road id -> {"pts": [[x, z], ...], "type", "from": month, "to": month or -1,
## "seg", "shape": [type, ax, az, bx, bz]}
## (a road that changes shape is kept as a new piece).
var roads := {}
## [{"key", "zone", "type", "storeys", "corners": [[x, z] x4], "from", "to"}]
var buildings := []
## Farm fields: [{"c": [x, z], "from", "to"}] (cell centres; one record per
## field while it is farmed).
var fields := []
## [{"m": month, "pop", "nick"}]
var story := []
## Months recorded so far (the timelapse's length).
var months := 0
var _next_road := 1

## What's alive now, so a month's changes are cheap to find (rebuilt on load).
var _live_roads := {}   # segment id -> [road record id, shape]
var _live_bldg := {}    # lot key -> [index into buildings, type, storeys, (raw type, level)]
var _live_field := {}   # farm id -> {cell: index into fields}
var _farm_sig := {}     # farm id -> hash of its cells when last compared


## The current game month, counted from the start.
static func month_of(tick: int) -> int:
	return tick / (24 * CitySim.TICKS_PER_HOUR)


## Once a game month: note what came and went. New records are added in
## sorted order, so every copy of the town keeps the same record. At most
## Balance.TIMELAPSE_RECORDS_PER_MONTH new ones a month: a town that appears
## all at once (an old save, the test town) is caught up over a few months
## instead of in one long tick. A building's record starts the month it went
## up, however late it is noticed.
func month(sim) -> void:
	var m := month_of(sim.tick_count)
	months = maxi(months, m + 1)
	var room: int = Balance.TIMELAPSE_RECORDS_PER_MONTH
	# Roads.
	var fresh := []
	var segs: Dictionary = sim.network.segments
	for seg in segs:
		var live = _live_roads.get(seg)
		if live == null or live[1] != _road_shape(sim, seg):
			fresh.append(seg)
	for seg in _live_roads.keys():
		if not segs.has(seg):
			roads[_live_roads[seg][0]].to = m
			_live_roads.erase(seg)
	fresh.sort()
	if fresh.size() > room:
		fresh.resize(room)
	room -= fresh.size()
	for seg in fresh:
		if _live_roads.has(seg):
			roads[_live_roads[seg][0]].to = m
		var shape := _road_shape(sim, seg)
		var pts := []
		for p in sim.network.sample_segment(seg, 8):
			pts.append([snappedf(p.x, 0.1), snappedf(p.z, 0.1)])
		var rid := _next_road
		_next_road += 1
		roads[rid] = {"pts": pts, "type": int(shape[0]), "from": m, "to": -1, "seg": seg, "shape": shape}
		_live_roads[seg] = [rid, shape]
	# Buildings.
	fresh.clear()
	var lots: Dictionary = sim.lots
	var gone := []
	for key in _live_bldg:
		if not sim.buildings.has(key) or not lots.has(key):
			gone.append(key)
	for key in gone:
		buildings[_live_bldg[key][0]].to = m
		_live_bldg.erase(key)
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		var live = _live_bldg.get(key)
		if live == null:
			if lots.has(key):
				fresh.append(key)
			continue
		var raw = b.get("type")
		var level = b.get("level")
		if live.size() == 5 and live[3] == raw and live[4] == level:
			continue  # as it was last month
		if live[1] == BuildingTypes.type_of(b) and live[2] == BuildingTypes.storeys(b):
			live.resize(3)  # the same to look at (or just loaded)
			live.append(raw)
			live.append(level)
			continue
		fresh.append(key)
	fresh.sort()
	if fresh.size() > room:
		fresh.resize(room)
	for key in fresh:
		var b: Dictionary = sim.buildings[key]
		if _live_bldg.has(key):
			buildings[_live_bldg[key][0]].to = m
		var corners := []
		for p in _footprint(lots[key]):
			corners.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		var type := BuildingTypes.type_of(b)
		var storeys := BuildingTypes.storeys(b)
		var since := m if _live_bldg.has(key) else mini(m, month_of(int(b.get("fabric", b.built))))
		buildings.append({"key": key, "zone": int(b.zone), "type": type,
			"storeys": storeys, "corners": corners, "from": since, "to": -1})
		_live_bldg[key] = [buildings.size() - 1, type, storeys, b.get("type"), b.get("level")]
	# Farm fields: only farms whose fields changed are looked at.
	var farms: Dictionary = sim.farms.farms
	for id in _live_field.keys():
		if not farms.has(id):
			for c in _live_field[id]:
				fields[_live_field[id][c]].to = m
			_live_field.erase(id)
			_farm_sig.erase(id)
	var fids: Array = farms.keys()
	fids.sort()
	for id in fids:
		var f: Dictionary = farms[id]
		var sig := hash(f.cells)
		if _farm_sig.get(id) == sig:
			continue
		_farm_sig[id] = sig
		var live: Dictionary = _live_field.get(id, {})
		_live_field[id] = live
		var here := {}
		for c in f.cells:
			here[c] = true
		for c in live.keys():
			if not here.has(c):
				fields[live[c]].to = m
				live.erase(c)
		for c in f.cells:
			if live.has(c):
				continue
			var mid := Farms.cell_center(f, c)
			fields.append({"c": [snappedf(mid.x, 0.1), snappedf(mid.z, 0.1)],
				"a": snappedf(atan2(f.dir.z, f.dir.x), 0.001), "from": m, "to": -1, "k": "%d:%d,%d" % [id, c.x, c.y]})
			live[c] = fields.size() - 1
	var nick := str(sim.nicknames.current.get("text", ""))
	if story.is_empty() or int(story[-1].pop) != int(sim.stats.population) or str(story[-1].nick) != nick:
		story.append({"m": m, "pop": int(sim.stats.population), "nick": nick})


## What a road's record depends on: its type and its two ends (to the metre).
static func _road_shape(sim, seg: int) -> Array:
	var s: Dictionary = sim.network.segments[seg]
	var a: Vector3 = sim.network.nodes.get(s.a, Vector3.ZERO)
	var b: Vector3 = sim.network.nodes.get(s.b, Vector3.ZERO)
	return [int(s.type), roundi(a.x), roundi(a.z), roundi(b.x), roundi(b.z)]


## A building's footprint inside its lot: the front part, set back from the
## street the way a Sanborn sheet draws it.
static func _footprint(lot: Dictionary) -> PackedVector2Array:
	var c: PackedVector2Array = lot.corners
	if c.size() < 3:
		return c
	var mid := Vector2.ZERO
	for p in c:
		mid += p / c.size()
	var out := PackedVector2Array()
	for p in c:
		out.append(mid + (p - mid) * 0.7)
	return out


## The record as the view wants it at month `m`: what stood then.
func at(m: int) -> Dictionary:
	var rs := []
	for id in roads:
		var r: Dictionary = roads[id]
		if int(r.from) <= m and (int(r.to) == -1 or int(r.to) > m):
			rs.append(r)
	var bs := []
	for b in buildings:
		if int(b.from) <= m and (int(b.to) == -1 or int(b.to) > m):
			bs.append(b)
	var fs := []
	for f in fields:
		if int(f.from) <= m and (int(f.to) == -1 or int(f.to) > m):
			fs.append(f)
	var pop := 0
	var nick := ""
	for s in story:
		if int(s.m) <= m:
			pop = int(s.pop)
			nick = str(s.nick)
	return {"roads": rs, "buildings": bs, "fields": fs, "pop": pop, "nick": nick}


## Saved compactly: points as flat lists of decimetres, one list per kind.
func to_dict() -> Dictionary:
	var rs := []
	var ids := roads.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = roads[id]
		rs.append([id, r.type, r.from, r.to, r.seg, r.shape, _flat(r.pts)])
	var bs := []
	for b in buildings:
		bs.append([b.key, b.zone, b.type, b.storeys, b.from, b.to, _flat(b.corners)])
	var fs := []
	for f in fields:
		fs.append([roundi(float(f.c[0]) * 10.0), roundi(float(f.c[1]) * 10.0), roundi(float(f.a) * 1000.0),
			f.from, f.to, f.k])
	return {"roads": rs, "buildings": bs, "fields": fs, "story": story, "months": months, "next": _next_road}


static func _flat(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(roundi(float(p[0]) * 10.0))
		out.append(roundi(float(p[1]) * 10.0))
	return out


static func _unflat(v: Array) -> Array:
	var out := []
	for i in range(0, v.size() - 1, 2):
		out.append([float(v[i]) / 10.0, float(v[i + 1]) / 10.0])
	return out


## Loads the record and works out what's alive from it (anything without an
## end month).
func from_dict(_sim, d: Dictionary) -> void:
	roads.clear()
	buildings.clear()
	fields.clear()
	story.clear()
	_live_roads.clear()
	_live_bldg.clear()
	_live_field.clear()
	_farm_sig.clear()
	for r in d.get("roads", []):
		var shape := []
		for v in r[5]:
			shape.append(int(v))
		roads[int(r[0])] = {"pts": _unflat(r[6]), "type": int(r[1]), "from": int(r[2]), "to": int(r[3]),
			"seg": int(r[4]), "shape": shape}
	for b in d.get("buildings", []):
		buildings.append({"key": str(b[0]), "zone": int(b[1]), "type": str(b[2]), "storeys": int(b[3]),
			"corners": _unflat(b[6]), "from": int(b[4]), "to": int(b[5])})
	for f in d.get("fields", []):
		fields.append({"c": [float(f[0]) / 10.0, float(f[1]) / 10.0], "a": float(f[2]) / 1000.0,
			"from": int(f[3]), "to": int(f[4]), "k": str(f[5])})
	for s in d.get("story", []):
		story.append({"m": int(s.m), "pop": int(s.pop), "nick": str(s.nick)})
	months = int(d.get("months", 0))
	_next_road = int(d.get("next", 1))
	# Whatever the record had standing carries on, as recorded: next month
	# compares it with the town exactly as the saved copy would have.
	for id in roads:
		if int(roads[id].to) == -1:
			_live_roads[int(roads[id].seg)] = [id, roads[id].shape]
	for i in buildings.size():
		if int(buildings[i].to) == -1:
			_live_bldg[str(buildings[i].key)] = [i, str(buildings[i].type), int(buildings[i].storeys)]
	for i in fields.size():
		if int(fields[i].to) == -1:
			var k := str(fields[i].k)
			var id := int(k.get_slice(":", 0))
			var xy := k.get_slice(":", 1)
			if not _live_field.has(id):
				_live_field[id] = {}
			_live_field[id][Vector2i(int(xy.get_slice(",", 0)), int(xy.get_slice(",", 1)))] = i
