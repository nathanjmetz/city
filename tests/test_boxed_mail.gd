extends SceneTree
## Run: godot --headless -s tests/test_boxed_mail.gd
## A post office boxed in by roads fills its block up to the sidewalk with
## lawn and carrier lot (Nathan, 2026-10-26: "when a hub with leader is
## "trapped" inside a road area, it should nicely fill in that area up to
## the edge (sidewalk) so that it looks like its using its space well."):
## edge pieces cut back to the roads, never over them, never on zoned or
## built lots, never under a building, kept by a save byte for byte, and
## cut back again by a road built later.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## How far a point is from the nearest road's right of way plus the gap the
## office keeps (negative: over it).
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
func _ring(sim: CitySim, w: int, d: int) -> void:
	var x := w / 2
	for r in [[[-x, 0], [x, 0]], [[x, 0], [x, -d]], [[x, -d], [-x, -d]], [[-x, -d], [-x, 0]]]:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})


## Carriers short on every route, for `rounds` of the postmaster's decisions.
func _grow(sim: CitySim, h: Dictionary, rounds: int) -> void:
	for i in rounds:
		h.want = 10
		h.short = 10
		sim.mail._decide(sim)


func _no_edge_over_roads(sim: CitySim, h: Dictionary) -> bool:
	for c in h.edge:
		var poly := CivicHubs.edge_poly(h, c)
		if Services.road_clash(sim.network, poly):
			return false
		for q in poly:
			if _clear_of_roads(sim, q) < -0.05:
				return false
	return true


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	_ring(sim, 160, 110)
	_check(sim.network.segments.size() == 4, "a block ringed by four streets (%d)" % sim.network.segments.size())
	var site := CivicHubs.site_near(sim.network, Vector3(-10, 0, -30))
	_check(sim.apply({"type": "place_post_office", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"a post office goes in on the block's front street")
	var id: int = sim.mail.offices.keys()[0]
	var h: Dictionary = sim.mail.offices[id]
	_check(h.edge.is_empty(), "a new post office has no edge pieces")
	# Houses zoned along the inside of the east street before it grows.
	for z in range(-20, -91, -10):
		sim.apply({"type": "paint_zone", "center": [60, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 400:
		sim.tick()
	var zoned := []
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.pos.x > 30.0 and lot.pos.z < -5.0 and lot.pos.z > -105.0 \
				and (sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE):
			zoned.append(key)
	_check(not zoned.is_empty(), "lots zoned along the east street (%d)" % zoned.size())

	# Carriers short for a long while: every whole piece, then edge pieces.
	_grow(sim, h, 60)
	_check(sim.mail._best_piece(sim, id) == Vector2i.MAX, "the post office is boxed in by the streets and the houses")
	_check(not h.edge.is_empty(), "it took edge pieces up to the streets (%d whole, %d edge)" % [h.cells.size(), h.edge.size()])
	_check(h.cells.size() < int(Mail.BASE.size() * Balance.HUB_MAX_GROWTH), "it stopped for want of room, not its size limit")
	var full: float = h.cell * h.cell
	var nearest := INF
	var small := false
	for c in h.edge:
		for q in CivicHubs.edge_poly(h, c):
			nearest = minf(nearest, _clear_of_roads(sim, q))
		small = small or CivicHubs.area(h.edge[c]) < full * CivicHubs.EDGE_MIN - 0.5
		_check(not c in h.cells, "edge piece %s isn't also a whole piece" % c)
	_check(_no_edge_over_roads(sim, h), "no edge piece reaches over a street's sidewalk and the gap")
	_check(nearest < 0.5, "edge pieces reach right up to the sidewalk gap (%.2f m)" % nearest)
	_check(not small, "every edge piece is at least a quarter of a piece")
	# The west side and the back are the office's up to the sidewalk.
	var row := RoadStyle.right_of_way_half(0) + CivicHubs.SETBACK
	var west := -80.0 + row + 1.0
	for z in [-15.0, -45.0, -75.0]:
		_check(sim.mail.covers(Vector3(west, 0, z)), "land by the west sidewalk at z %d is the post office's" % z)
	_check(sim.mail.covers(Vector3(-20.0, 0, -110.0 + row + 1.0)), "land by the back street's sidewalk is the post office's")
	_check(not sim.mail.covers(Vector3(west - 3.0, 0, -45.0)), "the sidewalk itself is not")
	# Nothing taken from the zoned and built lots, and no lot left on its land.
	var taken := false
	for key in zoned:
		var lot: Dictionary = sim.lots.get(key, {})
		if lot.is_empty():
			continue
		for p in [lot.pos, lot.front, lot.zone_pt]:
			taken = taken or sim.mail.covers(p)
	_check(not taken, "no zoned or built lot was taken")
	var under := false
	for key in sim.lots:
		under = under or sim.mail.covers(sim.lots[key].pos)
	_check(not under, "no lot is left on the post office's land")
	# Lawn and lot only: the tree's buildings stand on whole pieces.
	var built_on := false
	for n in h.lands:
		for c in h.lands[n]:
			built_on = built_on or h.edge.has(c)
	_check(not built_on, "no building stands on an edge piece")
	_check(CivicHubs.land_area(h) > h.cells.size() * full, "the panel's acres count the edge land")
	var cost := sim.mail.monthly_cost()
	var carriers := sim.mail.carriers(id)
	h.edge.clear()
	_check(sim.mail.monthly_cost() == cost and sim.mail.carriers(id) == carriers,
		"edge pieces don't change the upkeep or the carriers")
	_grow(sim, h, 60)
	_check(not h.edge.is_empty(), "and it takes them again")
	# Something else built later can't take its edge land either.
	var some: Vector2i = h.edge.keys()[0]
	var inside := CivicHubs._inner_pts(CivicHubs.edge_poly(h, some), 4.0)
	_check(not inside.is_empty() and sim.hubs.at(inside[0]) == -1 and sim.mail.at(inside[0]) == id,
		"its edge land is its own")

	# Save, load: byte for byte the same, and the copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var ch: Dictionary = copy.mail.offices[id]
	_check(ch.edge == h.edge, "a save keeps every edge piece exactly")
	_check(ch.cells == h.cells, "and the whole pieces")
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "a loaded copy saves byte for byte the same")
	for i in 30:
		sim.tick()
		copy.tick()
	_grow(sim, h, 3)
	_grow(copy, ch, 3)
	_check(JSON.stringify(copy.mail.to_dict()) == JSON.stringify(sim.mail.to_dict()), "copies stay in step")
	# An older save, without edge pieces, still loads.
	var old := sim.to_dict()
	for k in old.mail.offices:
		old.mail.offices[k].erase("edge")
	var aged := CitySim.new()
	aged.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(aged.mail.offices[id].edge.is_empty() and aged.mail.offices[id].cells == h.cells,
		"an older save loads with no edge pieces")
	_check(not JSON.stringify(aged.mail.to_dict()).contains("\"edge\""), "and saves the old way until it takes some")

	# Roads win: a lane in from the west street cuts the strips back.
	var before := CivicHubs.land_area(h)
	var shapes: Dictionary = h.edge.duplicate()
	sim.apply({"type": "build_road", "start": [-80, -45], "ctrl": [-70, -45], "end": [-60, -45]})
	sim.tick()
	_check(sim.network.segments.size() > 4, "the lane is built")
	_check(sim.mail.offices.has(id), "the post office is still there")
	_check(CivicHubs.land_area(h) < before, "the lane took edge land (%.0f -> %.0f m2)" % [before, CivicHubs.land_area(h)])
	_check(_no_edge_over_roads(sim, h), "nothing left of the edge pieces is on or by the lane")
	_check(not sim.mail.covers(Vector3(-66.0, 0, -45.0)), "the lane's ground is not the post office's")
	var cut := 0
	for c in h.edge:
		if shapes.has(c) and shapes[c] != h.edge[c]:
			cut += 1
	_check(cut > 0, "edge pieces cut back but big enough stay (%d)" % cut)
	_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "still one site")
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy2.tick()
	_check(copy2.mail.offices[id].edge == h.edge, "the cut-back edge pieces survive a save")

	# Its drawing builds over the edge pieces: lawn and lot, no building.
	var built := PostOfficeBuilder.build_office(h, 7, 6.0)
	_check(built[1] is ArrayMesh and (built[1] as ArrayMesh).get_surface_count() > 0, "a boxed post office draws")
	print("boxed mail: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
