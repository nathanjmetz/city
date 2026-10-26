extends SceneTree
## Run: godot --headless -s tests/test_boxed_hubs.gd
## A landfill, recycling centre or cemetery boxed in by roads fills its block
## up to the sidewalk (Nathan, 2026-10-26: "when a hub with leader is
## "trapped" inside a road area, it should nicely fill in that area up to the
## edge (sidewalk) so that it looks like its using its space well."): edge
## pieces cut back to the roads, never over them, never on zoned or built
## lots, kept by a save, and cut back again by a road built later.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## How far a point is from the nearest road's right of way plus the gap a
## hub keeps (negative: over it).
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


## Four streets round a block `w` metres across and `d` deep, its front
## street along z = 0.
func _ring(sim: CitySim, w := 360, d := 260) -> void:
	var x := w / 2
	for r in [[[-x, 0], [x, 0]], [[x, 0], [x, -d]], [[x, -d], [-x, -d]], [[-x, -d], [-x, 0]]]:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})


func _grow(sim: CitySim, h: Dictionary, rounds: int) -> void:
	for i in rounds:
		h.want = 10
		h.short = 10
		sim.hubs._decide(sim)


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	_ring(sim)
	_check(sim.network.segments.size() == 4, "a block ringed by four streets (%d)" % sim.network.segments.size())
	var site := CivicHubs.site_near(sim.network, Vector3(0, 0, -60))
	_check(sim.apply({"type": "place_hub", "kind": "landfill", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a landfill goes in on the block's front street")
	var id: int = sim.hubs.hubs.keys()[0]
	var h: Dictionary = sim.hubs.hubs[id]
	# Houses zoned along the inside of the east street before it grows.
	for z in range(-40, -221, -10):
		sim.apply({"type": "paint_zone", "center": [160, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 400:
		sim.tick()
	var zoned := []
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.pos.x > 120.0 and lot.pos.z < -10.0 and lot.pos.z > -250.0 \
				and (sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE):
			zoned.append(key)
	_check(not zoned.is_empty(), "lots zoned along the east street (%d)" % zoned.size())

	# Busy for a long while: it takes every whole piece, then edge pieces.
	_grow(sim, h, 80)
	_check(h.boxed, "the landfill is boxed in by the streets and the houses")
	_check(not h.edge.is_empty(), "it took edge pieces up to the streets (%d whole, %d edge)" % [h.cells.size(), h.edge.size()])
	_check(h.cells.size() < CivicHubs.max_pieces(h), "it stopped for want of room, not its size limit")
	var full: float = h.cell * h.cell
	var nearest := INF
	var over := false
	var small := false
	for c in h.edge:
		var poly := CivicHubs.edge_poly(h, c)
		_check(not Services.road_clash(sim.network, poly), "edge piece %s isn't on a road" % c)
		for q in poly:
			var d := _clear_of_roads(sim, q)
			over = over or d < -0.05
			nearest = minf(nearest, d)
		small = small or CivicHubs.area(h.edge[c]) < full * CivicHubs.EDGE_MIN - 0.5
	_check(not over, "no edge piece reaches over a street's sidewalk and the gap")
	_check(nearest < 0.5, "edge pieces reach right up to the sidewalk gap (%.2f m)" % nearest)
	_check(not small, "every edge piece is at least a quarter of a piece")
	# The west side is filled up to the sidewalk, all the way back.
	var west := -180.0 + RoadStyle.right_of_way_half(0) + CivicHubs.SETBACK + 1.0
	for z in [-40.0, -100.0, -160.0, -200.0]:
		_check(sim.hubs.covers(Vector3(west, 0, z)), "land by the west sidewalk at z %d is the landfill's" % z)
	var back := -260.0 + RoadStyle.right_of_way_half(0) + CivicHubs.SETBACK + 1.0
	_check(sim.hubs.covers(Vector3(-20.0, 0, back)), "land by the back street's sidewalk is the landfill's")
	_check(not sim.hubs.covers(Vector3(west - 3.0, 0, -100.0)), "the sidewalk itself is not")
	# Nothing taken from the zoned and built lots.
	var taken := false
	for key in zoned:
		var lot: Dictionary = sim.lots.get(key, {})
		if lot.is_empty():
			continue
		for p in [lot.pos, lot.front, lot.zone_pt]:
			taken = taken or sim.hubs.covers(p)
	_check(not taken, "no zoned or built lot was taken")
	_check(CivicHubs.land_area(h) > h.cells.size() * full, "the panel's acres count the edge land")

	# Save, load: the same land, and the copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var ch: Dictionary = copy.hubs.hubs[id]
	_check(ch.edge == h.edge, "a save keeps every edge piece exactly")
	_check(ch.cells == h.cells, "and the whole pieces")
	for i in 30:
		sim.tick()
		copy.tick()
	_grow(sim, h, 3)
	_grow(copy, ch, 3)
	_check(JSON.stringify(copy.hubs.to_dict()) == JSON.stringify(sim.hubs.to_dict()), "copies stay in step")
	# An older save, without edge pieces, still loads.
	var old := sim.to_dict()
	for k in old.hubs.hubs:
		old.hubs.hubs[k].erase("edge")
	var aged := CitySim.new()
	aged.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(aged.hubs.hubs[id].edge.is_empty() and aged.hubs.hubs[id].cells == h.cells, "an older save loads with no edge pieces")

	# Roads win: a street built through the west edge pieces cuts them back.
	var edge_before := CivicHubs.land_area(h)
	var cut_x := -158.0
	var west_pieces := []
	for c in h.edge:
		for q in CivicHubs.edge_poly(h, c):
			if absf(q.x - cut_x) < 30.0 and not c in west_pieces:
				west_pieces.append(c)
	_check(not west_pieces.is_empty(), "edge pieces stand where the new street goes (%d)" % west_pieces.size())
	sim.apply({"type": "build_road", "start": [cut_x, -60], "ctrl": [cut_x, -130], "end": [cut_x, -200]})
	sim.tick()
	_check(sim.hubs.hubs.has(id), "the landfill is still there")
	_check(CivicHubs.land_area(h) < edge_before, "the new street took edge land (%.0f -> %.0f m2)" % [edge_before, CivicHubs.land_area(h)])
	var clash := false
	for c in h.edge:
		clash = clash or Services.road_clash(sim.network, CivicHubs.edge_poly(h, c))
		for q in CivicHubs.edge_poly(h, c):
			clash = clash or _clear_of_roads(sim, q) < -0.05
	_check(not clash, "nothing left of the edge pieces is on or by the new street")
	_check(not sim.hubs.covers(Vector3(cut_x, 0, -130.0)), "the new street's ground is not the landfill's")
	_check(not sim.hubs.covers(Vector3(west, 0, -130.0)), "the sliver cut off beyond it goes too")
	var kept := false
	for c in west_pieces:
		kept = kept or h.edge.has(c)
	_check(kept, "edge pieces cut back but big enough stay")
	_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "still one site")
	# And the cut-back land survives a save as it is.
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy2.tick()
	_check(copy2.hubs.hubs[id].edge == h.edge, "the cut-back edge pieces survive a save")

	# A cemetery boxed in the same way fills its block too, and its drawing
	# builds over edge pieces.
	var cem := CitySim.new()
	cem.economy.money = 50_000_000
	cem.simulate_traffic = false
	_ring(cem, 200, 170)
	var cs := CivicHubs.site_near(cem.network, Vector3(0, 0, -60))
	cem.apply({"type": "place_hub", "kind": "cemetery", "pos": [cs[0].x, cs[0].z], "dir": [cs[1].x, cs[1].z]})
	var cid: int = cem.hubs.hubs.keys()[0]
	var ce: Dictionary = cem.hubs.hubs[cid]
	cem.stats.population = Balance.CEMETERY_PEOPLE_PER_PIECE * 200
	for i in 120:
		cem.hubs._decide(cem)
	_check(ce.boxed and not ce.edge.is_empty(), "a boxed cemetery fills up to the sidewalks (%d whole, %d edge)" % [ce.cells.size(), ce.edge.size()])
	for kind in ["cemetery", "landfill", "recycling_2"]:
		var drawn: Dictionary = ce.duplicate()
		drawn.kind = kind
		var built := HubBuilder.build_hub(drawn, 7, 6.0)
		_check(built[3] is ArrayMesh and (built[3] as ArrayMesh).get_surface_count() > 0, "a boxed %s draws" % kind)
	print("boxed hubs: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
