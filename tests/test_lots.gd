extends SceneTree
## Run: godot --headless -s tests/test_lots.gd
## Natural lots: zoned frontage is surveyed into real-world lots that fill
## the block, with corner lots, curves and flag lots.

var failed := false


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var sim := CitySim.new()
	# One 120 x 160 m block, like a Midwestern town block.
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [240, 0], "c": [240, 160], "block": 120.0})
	print("roads: %d  (%d ms)" % [sim.network.segments.size(), Time.get_ticks_msec() - t0])
	_check(sim.lots.is_empty(), "no lots before zoning (got %d)" % sim.lots.size())
	t0 = Time.get_ticks_msec()
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	print("zoned all: %d lots (%d ms)" % [sim.lots.size(), Time.get_ticks_msec() - t0])
	var area := 0.0
	var widths := {}
	var corners := 0
	var flags := 0
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.pos.x > 0.0 and lot.pos.x < 240.0 and lot.pos.z > 0.0 and lot.pos.z < 160.0:
			area += lot.area
		widths[snappedf(lot.width, 0.5)] = true
		corners += 1 if lot.corner else 0
		flags += 1 if lot.flag else 0
	print("widths: %s corners %d flags %d" % [str(widths.keys()), corners, flags])
	_check(widths.size() > 3, "lot widths vary")
	_check(corners > 0, "corner lots")
	var overlaps := _overlaps(sim)
	_check(overlaps == 0, "lots don't overlap (%d)" % overlaps)
	# The block is filled: little land is left between the lots.
	var block := (120.0 - 2 * 8.4) * (80.0 - 2 * 8.4)
	var filled := area / (block * 4.0)
	_check(filled > 0.9, "blocks are filled with lots, no wasted land (%.0f%%)" % (filled * 100.0))
	# Built lots become parcels: they survive a save and stay put when the
	# zoning around them changes.
	sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	for i in 3000:
		sim.tick()
	_check(sim.buildings.size() > 10, "homes grew (%d)" % sim.buildings.size())
	var built: String = sim.buildings.keys()[0]
	var shape: PackedVector2Array = sim.lots[built].corners
	var copy := CitySim.new()
	# Full precision, as the region server sends it.
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true)))
	_check(copy.lots.has(built) and copy.lots[built].corners == shape, "save keeps a parcel's exact shape")
	_check(copy.buildings.size() == sim.buildings.size(), "save keeps every building")
	for i in 30:
		sim.tick()
		copy.tick()
	var da := copy.to_dict()
	var db := sim.to_dict()
	var diff := []
	for k in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			diff.append(k)
	_check(diff.is_empty(), "copies stay in sync %s" % str(diff))
	# A big town (here the copy acts big) puts a zoning or road edit in at
	# once and plans its lots over the next ticks, the same on every copy,
	# even one saved halfway through.
	copy.replan_lots = 0
	var side_seg: int = copy.network.segments.keys()[1]
	var before_lots := copy.lots.duplicate()
	copy.apply({"type": "zone_frontage", "seg": side_seg, "side": 1, "zone": ZoneMap.Zone.COMMERCIAL})
	copy.apply({"type": "build_road", "start": [60, 0], "ctrl": [60, 40], "end": [60, 80]})
	_check(copy._replan_at > copy.tick_count and copy.lots == before_lots, "a big town's lots catch up after the edit")
	var half: CitySim
	for i in CitySim.REPLAN_ROAD_TICKS + 5:
		if i == 7:
			half = CitySim.new()
			half.from_dict(JSON.parse_string(JSON.stringify(copy.to_dict(), "", false, true)))
			half.replan_lots = 0
		copy.tick()
		if half != null:
			half.tick()
	_check(copy._replan_at == 0 and copy.lots != before_lots, "the lots caught up")
	for key in copy.lots:
		var c: PackedVector2Array = copy.lots[key].corners
		_check(not Geometry2D.is_point_in_polygon(Vector2(60, 40), c), "no lot under the new road (%s)" % key)
	da = half.to_dict()
	db = copy.to_dict()
	diff = []
	for k in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			diff.append(k)
	_check(diff.is_empty(), "a copy saved while catching up stays in sync %s" % str(diff))
	# Rounded block corners and curving streets: the lots fan radially round
	# each bend (none lost to it, none cut on a diagonal), and none overlap.
	for scene in ["rounded", "curves"]:
		var bend := CitySim.new()
		bend.simulate_traffic = false
		load("res://tools/lot_map.gd").build(bend, scene)
		bend.tick()
		var bad := 0
		var ks := bend.lots.keys()
		ks.sort()
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				for q in Geometry2D.intersect_polygons(bend.lots[ks[i]].corners, bend.lots[ks[j]].corners):
					if absf(LotPlanner._area(q)) > 4.0:
						bad += 1
		_check(bad == 0, "%s: no lots overlap (%d)" % [scene, bad])
		if scene == "rounded":
			var on_bends := {}
			for key in bend.lots:
				var c := bend.network.curve_of(bend.lots[key].seg)
				# Inside the block (side 1 here), where the corner used to be lost.
				if bend.lots[key].side == 1 and Vector2(c[1].x - c[0].x, c[1].z - c[0].z).normalized().dot(Vector2(c[2].x - c[1].x, c[2].z - c[1].z).normalized()) < 0.5:
					on_bends[bend.lots[key].seg] = true
			_check(on_bends.size() == 4, "every rounded corner has lots fanning round it (%d of 4)" % on_bends.size())
	# A local street 50 m from an arterial: one row of real-depth house lots
	# fronting the local street, backing onto the arterial, not two 15 m rows.
	var strip := CitySim.new()
	strip.simulate_traffic = false
	strip.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, 0], "end": [0, 150], "road": 1})
	strip.apply({"type": "build_road", "start": [50, -100], "ctrl": [50, 0], "end": [50, 100]})
	for id in strip.network.segments.keys():
		strip.apply({"type": "zone_frontage", "seg": id, "side": 1, "both": true, "zone": ZoneMap.Zone.RESIDENTIAL})
	var in_strip := []
	for key in strip.lots:
		var l: Dictionary = strip.lots[key]
		if l.pos.x > 0.0 and l.pos.x < 50.0 and absf(l.pos.z) < 80.0:
			in_strip.append(l)
	_check(not in_strip.is_empty() and in_strip.all(func(l): return strip.network.segments[l.seg].type != 1 and l.depth > 25.0),
		"one row of full-depth lots between a street and an arterial (%s)" % str(in_strip.map(func(l): return [strip.network.segments[l.seg].type, snappedf(l.depth, 0.1)])))
	# Zoning just a stretch of a street (a drag over part of a block face):
	# a few shop lots there, none along the rest of the street.
	var bit := CitySim.new()
	bit.simulate_traffic = false
	bit.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, 0], "end": [300, 0]})
	var bit_seg: int = bit.network.segments.keys()[0]
	bit.apply({"type": "zone_frontage", "seg": bit_seg, "side": 1, "zone": ZoneMap.Zone.COMMERCIAL, "span": [120.0, 170.0]})
	var xs := bit.lots.values().map(func(l): return l.pos.x)
	_check(xs.size() >= 1 and xs.size() <= 3 and xs.all(func(x): return x > 105.0 and x < 185.0),
		"a stretch zones just a few lots there (%s)" % str(xs))
	# The tool: a short drag still zones a lot's width; one ending near a
	# corner runs on to it.
	var zt := ZoneTool.new()
	zt.sim = bit
	zt._spans = {"a": [bit_seg, -1, 140.0, 142.0], "b": [bit_seg, 1, 5.0, 60.0]}
	var runs := zt._runs()
	_check(runs[0][3] - runs[0][2] >= ZoneTool.MIN_RUN - 0.01 and runs[1][2] == 0.0,
		"a short drag zones a lot's width, and one near the corner runs to it (%s)" % str(runs))
	# Smart paint plans a neighborhood the way a planner would: shops on the
	# avenue and the main crossing's corners, homes on the local streets, only
	# the zones ticked, and never over zoning already there.
	var hood := CitySim.new()
	hood.simulate_traffic = false
	hood.economy.money = 1.0e8
	hood.apply({"type": "build_grid", "a": [0, 0], "b": [300, 0], "c": [300, 300], "block": 100.0})
	hood.apply({"type": "build_road", "start": [-40, 310], "ctrl": [150, 310], "end": [340, 310], "road": RoadStyle.Type.AVENUE})
	var mid_seg: int = hood.network.find_segment_near(Vector3(150, 0, 100), 20.0, 1.0).seg
	hood.apply({"type": "zone_frontage", "seg": mid_seg, "side": 1, "zone": ZoneMap.Zone.INDUSTRIAL, "single": true})
	var both := {ZoneMap.Zone.RESIDENTIAL: true, ZoneMap.Zone.COMMERCIAL: true}
	var hp: Dictionary = SmartZoning.plan(hood, mid_seg, SmartZoning.Scope.EXTENDED, both)
	var by := {}
	for p in hp.parts:
		by[p.zone] = by.get(p.zone, 0) + 1
	_check(by.get(ZoneMap.Zone.RESIDENTIAL, 0) > by.get(ZoneMap.Zone.COMMERCIAL, 0) and by.get(ZoneMap.Zone.COMMERCIAL, 0) >= 2
		and not by.has(ZoneMap.Zone.INDUSTRIAL), "smart paint: mostly homes, some shops, no unticked industry (%s)" % str(by))
	_check(hp.parts.all(func(p): return not (p.seg == mid_seg and p.side == 1)), "smart paint never paints over zoning")
	var on_avenue: Array = hp.parts.filter(func(p): return hood.network.segments[p.seg].type == RoadStyle.Type.AVENUE)
	_check(not on_avenue.is_empty() and on_avenue.all(func(p): return p.zone == ZoneMap.Zone.COMMERCIAL),
		"smart paint puts shops on the avenue (%d sides)" % on_avenue.size())
	_check(hp.parts.any(func(p): return p.zone == ZoneMap.Zone.COMMERCIAL and hood.network.segments[p.seg].type != RoadStyle.Type.AVENUE),
		"smart paint puts corner shops at the main crossing")
	var homes_only: Dictionary = SmartZoning.plan(hood, mid_seg, SmartZoning.Scope.SMALL, {ZoneMap.Zone.RESIDENTIAL: true})
	_check(not homes_only.parts.is_empty() and homes_only.parts.all(func(p): return p.zone == ZoneMap.Zone.RESIDENTIAL),
		"smart paint uses only the zones ticked")
	var one_street: Dictionary = SmartZoning.plan(hood, mid_seg, SmartZoning.Scope.STREET, both)
	var street_segs := {}
	for p in one_street.parts:
		street_segs[p.seg] = true
	_check(street_segs.size() == 3, "smart paint's Street runs straight on through the crossings (%d pieces)" % street_segs.size())
	zt.free()
	# Click order: zoning streets one by one with homes going up between
	# clicks cuts the same plain lots as zoning them all at once (a built
	# corner lot keeps its corner; the cross street's lots start behind it).
	var order := CitySim.new()
	order.simulate_traffic = false
	order.economy.money = 1.0e8
	var ou := Vector2(cos(-0.5), sin(-0.5)) * 500.0
	var ov := Vector2(-sin(-0.5), cos(-0.5)) * 200.0
	order.apply({"type": "build_grid", "a": [0, 0], "b": [ou.x, ou.y], "c": [ov.x, ov.y], "block": 100.0})
	var oids := order.network.segments.keys()
	oids.sort()
	oids.reverse()
	for i in oids.size():
		for side in [1, -1]:
			order.apply({"type": "zone_frontage", "seg": oids[i], "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
		if i % 3 == 2:
			for t in 300:
				order.tick()
	for t in 300:
		order.tick()
	var odd := order.lots.values().filter(func(l): return _squareness(l) < 0.85).size()
	_check(order.buildings.size() > 10 and odd <= 4,
		"zoning street by street with homes going up between keeps lots plain (%d odd of %d)" % [odd, order.lots.size()])
	_check(_overlaps(order) == 0, "and they don't overlap")
	# A zoning drag: the zones go in at once, the lots once, when it ends.
	var drag := CitySim.new()
	drag.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	drag.apply({"type": "build_road", "start": [200, 0], "ctrl": [200, 100], "end": [200, 200]})
	var ids: Array = drag.network.segments.keys()
	drag.apply({"type": "zone_frontage", "seg": ids[0], "side": 1, "zone": ZoneMap.Zone.RESIDENTIAL, "hold": true})
	drag.tick()
	drag.apply({"type": "zone_frontage", "seg": ids[1], "side": -1, "zone": ZoneMap.Zone.RESIDENTIAL, "hold": true})
	_check(drag.lots.is_empty() and drag._hold_until > 0, "no lots while the drag goes on")
	var mid := CitySim.new()
	mid.from_dict(JSON.parse_string(JSON.stringify(drag.to_dict(), "", false, true)))
	drag.apply({"type": "zone_done"})
	mid.apply({"type": "zone_done"})
	_check(not drag.lots.is_empty() and drag._hold_until == 0, "the lots come when the drag ends (%d)" % drag.lots.size())
	_check(mid.lots.keys() == drag.lots.keys(), "a copy saved mid-drag cuts the same lots")
	var lone := CitySim.new()
	lone.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	lone.apply({"type": "zone_frontage", "seg": lone.network.segments.keys()[0], "side": 1, "zone": ZoneMap.Zone.RESIDENTIAL, "hold": true})
	for i in CitySim.HOLD_TICKS:
		lone.tick()
	_check(not lone.lots.is_empty() and lone._hold_until == 0, "a drag that never ends still gets its lots")
	# Merge two neighbours, then split them again (business agency).
	var face := LotPlanner.block_face(sim, built)
	_check(face.size() >= 2, "block face lists the street's lots (%d)" % face.size())
	var plant := CitySim.new()
	plant.apply({"type": "build_road", "start": [0, 0], "ctrl": [200, 0], "end": [400, 0]})
	plant.apply({"type": "zone_frontage", "seg": plant.network.segments.keys()[0], "side": 1, "zone": ZoneMap.Zone.INDUSTRIAL})
	var row := LotPlanner.block_face(plant, plant.lots.keys()[0])
	_check(row.size() >= 4, "a row of plant lots (%d)" % row.size())
	_check(LotPlanner.can_merge(plant, row[0], row[1]), "two neighbouring plants can merge")
	_check(not LotPlanner.can_merge(plant, row[0], row[2]), "lots that don't touch can't merge")
	var before: float = plant.lots[row[0]].area + plant.lots[row[1]].area
	_check(LotPlanner.merge_lots(plant, row[0], row[1]) == row[0], "merge keeps the first key")
	_check(not plant.lots.has(row[1]) and absf(plant.lots[row[0]].area - before) < before * 0.05,
		"merged lot covers both (%.0f of %.0f m²)" % [plant.lots[row[0]].area, before])
	var halves := LotPlanner.split_lot(plant, row[0])
	_check(halves.size() == 2 and plant.lots.has(row[0] + "/1"), "a merged lot splits back in two")
	# Homes stay within real lot sizes: three wide lots can't become one estate.
	var big := 0.0
	for k in face:
		big += sim.lots[k].width
	_check(face.size() < 3 or not LotPlanner.can_merge(sim, face[0], face[1]) or big > 46.0, "home lots have a size cap")
	# A new road through a built block re-cuts or drops the parcels it hits.
	var lost := []
	sim.parcels_lost.connect(func(keys): lost.append_array(keys))
	var victim := ""
	for key in sim.buildings:
		var l: Dictionary = sim.lots[key]
		if absf(l.normal.z) > 0.9 and l.pos.x > 20.0 and l.pos.x < 220.0 and l.pos.z > 10.0 and l.pos.z < 150.0 and absf(fmod(l.pos.x, 120.0) - 60.0) < 40.0:
			victim = key
			break
	_check(victim != "", "a built home to run a road through")
	if victim != "":
		var x: float = sim.lots[victim].pos.x
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 80], "end": [x, 160]})
		sim.tick()
		for key in sim.lots:
			var c: PackedVector2Array = sim.lots[key].corners
			_check(not Geometry2D.is_point_in_polygon(Vector2(x, 40), c) and not Geometry2D.is_point_in_polygon(Vector2(x, 120), c),
				"no lot left under the new road (%s)" % key)
		_check(lost.has(victim) and not sim.buildings.has(victim), "the home it ran through is gone and reported for a refund")
	# Curves: lots fan out radially and never overlap.
	var curve := CitySim.new()
	_clear_county(curve, Vector2(150, 0), 300.0)
	curve.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, -90], "end": [300, 0]})
	for side in [-1, 1]:
		curve.apply({"type": "zone_frontage", "seg": curve.network.segments.keys()[0], "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(curve.lots.size() >= 20, "lots along a curve (%d)" % curve.lots.size())
	_check(_overlaps(curve) == 0, "curve lots don't overlap")
	# One street side zoned in a grid: plain rectangles right to the cross
	# streets, no triangles at the corners (real plats square their corners).
	var sq := CitySim.new()
	sq.simulate_traffic = false
	sq.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [360, 240], "block": 120.0})
	var street := -1
	var near := INF
	for id in sq.network.segments:
		var d: float = sq.network.sample_segment(id, 2)[1].distance_to(Vector3(180, 0, 120))
		if d < near:
			near = d
			street = id
	sq.apply({"type": "zone_frontage", "seg": street, "side": 1, "zone": ZoneMap.Zone.RESIDENTIAL})
	sq.tick()
	var skewed := 0
	for k in sq.lots:
		# Its outline against the rectangle around it, square to its street.
		var l: Dictionary = sq.lots[k]
		var u := Vector2(l.dir.x, l.dir.z)
		var v := Vector2(l.normal.x, l.normal.z)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for c in l.corners:
			var q := Vector2(c.dot(u), c.dot(v))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		if l.area < (hi.x - lo.x) * (hi.y - lo.y) * 0.9:
			skewed += 1
	_check(sq.lots.size() >= 4 and skewed == 0, "lots are rectangles out to the corners (%d of %d skewed)" % [skewed, sq.lots.size()])
	# Back lanes: homes front the paved street and their lots run back to an
	# alley or a gravel lane behind; nothing fronts the lane on that side.
	for lane in [RoadStyle.Type.ALLEY, RoadStyle.Type.GRAVEL]:
		var town := CitySim.new()
		town.simulate_traffic = false
		town.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, 0], "end": [300, 0]})
		town.apply({"type": "build_road", "start": [0, 70], "ctrl": [150, 70], "end": [300, 70], "road": lane})
		for id in town.network.segments:
			for side in [-1, 1]:
				town.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
		town.tick()
		var fronting := 0
		var shallow := 0
		var between := 0
		for k in town.lots:
			var l: Dictionary = town.lots[k]
			if l.pos.z <= 0.0 or l.pos.z >= 70.0:
				continue
			between += 1
			if town.network.segments[l.seg].type == lane:
				fronting += 1
			elif l.depth < 50.0:
				shallow += 1
		var name: String = RoadStyle.TYPES[lane].name
		_check(between >= 10 and fronting == 0, "no homes front the %s behind a street (%d of %d)" % [name, fronting, between])
		_check(shallow == 0, "street lots run back to the %s (%d short)" % [name, shallow])
		_check(_overlaps(town) == 0, "lots by the %s don't overlap" % name)
	if failed:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if failed else 0)


## A lot's area over its bounding rectangle along its street (1 = a plain rectangle).
func _squareness(lot: Dictionary) -> float:
	var d := Vector2(lot.dir.x, lot.dir.z).normalized()
	var n := Vector2(-d.y, d.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in lot.corners:
		var q := Vector2(p.dot(d), p.dot(n))
		lo = lo.min(q)
		hi = hi.max(q)
	return absf(LotPlanner._area(lot.corners)) / maxf((hi.x - lo.x) * (hi.y - lo.y), 0.01)


func _overlaps(sim: CitySim) -> int:
	var keys := sim.lots.keys()
	var n := 0
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Dictionary = sim.lots[keys[i]]
			var b: Dictionary = sim.lots[keys[j]]
			if (a.pos as Vector3).distance_to(b.pos) > 120.0:
				continue
			for p in Geometry2D.intersect_polygons(a.corners, b.corners):
				if absf(LotPlanner._area(p)) > 4.0:
					n += 1
	return n


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL: " + what)


## Bulldozes the county roads around `at` (town coordinates), for a test
## town laid out across the section lines with no county road in mind.
static func _clear_county(sim: CitySim, at: Vector2, reach: float) -> void:
	var o := sim.terrain_offset
	for x in range(int(at.x - reach), int(at.x + reach) + 1, 100):
		for z in range(int(at.y - reach), int(at.y + reach) + 1, 100):
			for mile in CountyGrid.miles_at(x + o.x, z + o.y, 60.0):
				sim.apply({"type": "remove_county", "key": mile.key})
