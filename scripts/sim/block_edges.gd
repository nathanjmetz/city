class_name BlockEdges
extends RefCounted
## Edge pieces for the hubs that buy land a block at a time: banks, campuses
## and the phone company (Nathan, 2026-10-26: "when a hub with leader is
## "trapped" inside a road area, it should nicely fill in that area up to
## the edge (sidewalk) so that it looks like its using its space well.").
##
## A block next to one of them that a road runs through can never be bought
## whole, so the hub takes what's left of it, cut back to each road's right
## of way plus the gap its front keeps (CivicHubs' cut, the same as a
## landfill's or the post office's): grounds only (lawn, parking, a fenced
## yard), never a building, drawn by each one's builder. Only free ground:
## never a zoned or built lot, zoning painted but not yet a lot, another
## owner's land, water or a reserve. It costs nothing and adds no upkeep or
## jobs (it was the town's verge up to the road). Roads still win: a road
## built later cuts the pieces back, or takes them (prune).
##
## Each hub keeps them as `edge`: block -> outline in CivicHubs' frame (x
## along its road, z back from the front edge of its first block, metres,
## in EDGE_SNAP steps), so the shared code in CivicHubs fits them. They
## count as its land (at, covers, Move It, lot planning, the woods) but
## never as blocks.

## How often (decide rounds) a hub looks at its edge pieces: one round in
## four, the hubs taking turns by id.
const EVERY := 4
## A piece is kept only if it's at least this wide on average (m) along a
## whole side of its block: thinner, it's just the grass verge.
const MIN_WIDTH := 3.0
## Metres more than the gap a piece keeps from the roads: a road's outline
## is drawn round its curve in short straight runs and rounded ends that
## can fall up to a fifth of a metre short of the true curve.
const ROAD_SLACK := 0.25


## Hub `b` (pos: the middle of its first block) as CivicHubs sees one: the
## middle of its first block's front edge as the gate, its blocks as whole
## pieces, its `edge` shared (not a copy).
static func view(b: Dictionary, cell: float) -> Dictionary:
	if not b.has("edge"):
		b.edge = {}
	var cells := [Vector2i.ZERO]
	for blk in b.blocks:
		cells.append(blk.c)
	return {"pos": b.pos + b.dir * (cell * 0.5), "dir": b.dir, "cell": cell, "cells": cells, "edge": b.edge,
		"edge_min": MIN_WIDTH / cell, "edge_tidy": true, "edge_extra": ROAD_SLACK}


## The outline of each of `b`'s edge pieces on the ground (x, z).
static func edge_polys(b: Dictionary, cell: float) -> Array:
	var out := []
	var e: Dictionary = b.get("edge", {})
	if e.is_empty():
		return out
	var h := {"pos": b.pos + b.dir * (cell * 0.5), "dir": b.dir, "edge": e}
	for c in e:
		out.append(CivicHubs.edge_poly(h, c))
	return out


## True when ground point `p` lies on one of `b`'s edge pieces.
static func on_edge(b: Dictionary, cell: float, p: Vector3) -> bool:
	var e: Dictionary = b.get("edge", {})
	if e.is_empty():
		return false
	var d: Vector3 = p - b.pos
	var l := Vector2(d.x * -b.dir.z + d.z * b.dir.x, -(d.x * b.dir.x + d.z * b.dir.z) + cell * 0.5)
	var c := Vector2i(roundi(l.x / cell), floori(l.y / cell))
	if not e.has(c):
		return false
	var poly: PackedVector2Array = e[c]
	# Its box first: Godot's point-in-polygon can say yes outside an outline.
	var lo := poly[0]
	var hi := poly[0]
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	return l.x >= lo.x and l.y >= lo.y and l.x <= hi.x and l.y <= hi.y and Geometry2D.is_point_in_polygon(l, poly)


## True when it's hub `id`'s turn to look at its edge pieces this round
## (rounds `every` ticks apart).
static func due(tick: int, every: int, id: int) -> bool:
	return (tick / every + id) % EVERY == 0


## Takes every edge piece that fits round `b`, and fits one a road had cut
## back out to the roads again once that road is gone. `problem` says why
## ground (an outline, x, z) can't be the hub's, or "" (ground_problem);
## `cut`, if given, takes outlines (x, z) and returns what's left of them
## the hub's own way (the phone company's tower yards). True when any
## changed.
static func take(sim: CitySim, b: Dictionary, cell: float, problem: Callable, cut := Callable()) -> bool:
	var h := view(b, cell)
	var full := cell * cell
	# Only what a road cut: a whole block stays free for the hub to buy, and
	# no zoned or built lot or painted zoning is ever taken.
	h.edge_cut = func(parts: Array) -> Array:
		var a := 0.0
		for part in parts:
			a += CivicHubs.area(part)
		if a > full * 0.98:
			return []
		parts = Parks._cut_by_zones(sim, Parks._cut_by_lots(sim, parts))
		return cut.call(parts) if cut.is_valid() and not parts.is_empty() else parts
	var changed := false
	var none := func(_world: PackedVector2Array) -> String: return ""
	# A piece cut back by a road since gone fits out to the roads again: the
	# cut alone first (cheap), the ground check only if it would grow. It
	# must still hold all it held (the same side of every street), joined to
	# the hub's blocks without itself, as prune sees it (joined_edges).
	for c in b.edge.keys():
		var keep: Dictionary = b.edge
		var others: Dictionary = keep.duplicate()
		others.erase(c)
		var v := h.duplicate()
		v.edge = others
		var joined := CivicHubs.joined_edges(v)
		var old: PackedVector2Array = keep[c]
		var fresh := CivicHubs.edge_shape(sim, v, c, joined, none)
		if not _grows(fresh, old):
			continue
		b.edge = others  # its own old piece isn't someone else's land
		fresh = CivicHubs.edge_shape(sim, v, c, joined, problem)
		b.edge = keep
		if _grows(fresh, old):
			keep[c] = fresh
			changed = true
	changed = _keep_joined(h) or changed
	# New pieces next to its land, the nearest its middle first.
	var mid := Vector2.ZERO
	for c in h.cells:
		mid += Vector2(c)
	mid /= h.cells.size()
	var cleared := {}
	for c in b.get("cleared", []):
		cleared[c] = true  # the player cleared it for something else
	var tried := {}
	var grew := true
	while grew:
		grew = false
		var tries := []
		for c in h.cells + b.edge.keys():
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if n.y < 0 or n in h.cells or b.edge.has(n) or cleared.has(n) or tried.has(n):
					continue
				tried[n] = true
				tries.append([Vector2(n).distance_to(mid), n])
		tries.sort_custom(func(x, y): return x[0] < y[0] - 0.001 or (absf(x[0] - y[0]) <= 0.001 and CivicHubs._less(x[1], y[1])))
		for t in tries:
			var shape := CivicHubs.edge_shape(sim, h, t[1], b.edge, problem)
			if not shape.is_empty():
				b.edge[t[1]] = shape
				changed = true
				grew = true
	return _keep_joined(h) or changed


## True when `fresh` (an outline in the hub's frame) is bigger than `old` and
## holds all of it.
static func _grows(fresh: PackedVector2Array, old: PackedVector2Array) -> bool:
	var now := CivicHubs.area(old)
	if fresh.is_empty() or CivicHubs.area(fresh) <= now + 1.0:
		return false
	var held := 0.0
	for q in Geometry2D.intersect_polygons(fresh, old):
		held += CivicHubs.area(q)
	return held >= now - 1.0


## Drops any of `h`'s edge pieces not joined to its blocks (as prune does),
## so take and prune always agree. True when any went.
static func _keep_joined(h: Dictionary) -> bool:
	var joined := CivicHubs.joined_edges(h)
	var changed := false
	for c in h.edge.keys():
		if not joined.has(c):
			h.edge.erase(c)
			changed = true
	return changed


## Roads win over edge pieces too: each is cut back to the roads as they
## are now (or goes, if too little is left), and any no longer joined to
## the hub's blocks goes (CivicHubs.prune_edges). True when any changed.
static func prune(sim: CitySim, b: Dictionary, cell: float) -> bool:
	if b.get("edge", {}).is_empty():
		return false
	var h := view(b, cell)
	# A block it bought where a piece was is whole now.
	var changed := false
	for c in h.cells:
		changed = b.edge.erase(c) or changed
	return CivicHubs.prune_edges(sim, h) or changed


## Why ground `world` (an edge piece's outline, x, z) can't be a block hub's,
## looked at every `step` metres, or "": the hubs' checks (water, reserves,
## every other owner, zoned or built lots), less the road one (it's already
## cut back), and the power company, the railroad and the big factories.
static func ground_problem(sim: CitySim, world: PackedVector2Array, step: float) -> String:
	var pts := CivicHubs._inner_pts(world, step)
	var p := sim.hubs._ground_problem(sim, world, pts, -1, true, false)
	if p != "":
		return p
	for q in pts:
		if sim.power.covers(q) or sim.rail.covers(q) or sim.big.covers(q):
			return "That ground belongs to a company."
	# Points can miss a corner of someone's land: their outlines too.
	var box := _box(world)
	for poly in others_land(sim):
		if _box(poly).intersects(box):
			for q in Geometry2D.intersect_polygons(world, poly):
				if CivicHubs.area(q) > 1.0:
					return "Overlaps someone else's land."
	return zoned_problem(sim, world)


## The outlines (x, z) of the land every hub with land holds: banks,
## campuses and the phone company (blocks, edge pieces, tower yards),
## landfills, recycling and cemeteries, the post office, parks, warehouses
## and the big factories. (A block hub's own land touches a new piece of
## its own along a side only, never over it.)
static func others_land(sim: CitySim) -> Array:
	var out := []
	for id in sim.banks.banks:
		out.append_array(Banks.land_polys(sim.banks.banks[id]))
	for id in sim.education.campuses:
		out.append_array(Education.land_polys(sim.education.campuses[id]))
	for id in sim.telecom.companies:
		var c: Dictionary = sim.telecom.companies[id]
		out.append_array(Telecom.land_polys(c))
		for t in c.towers:
			out.append(Telecom.compound(Vector2(t.pos[0], t.pos[1])))
	for id in sim.hubs.hubs:
		out.append_array(CivicHubs.land_polys(sim.hubs.hubs[id]))
	for id in sim.mail.offices:
		out.append_array(CivicHubs.land_polys(sim.mail.offices[id]))
	for id in sim.parks.sites:
		out.append_array(sim.parks.land_polys(id))
	for id in sim.warehouses.buildings:
		out.append(sim.warehouses.footprint(id))
	for id in sim.big.sites:
		out.append(BigFactories.corners(sim.big.sites[id]))
	return out


static func _box(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	return box


## "Zoned or built on." when a zoned or built lot runs onto ground `world`
## (an outline, x, z), "Zoned." when zoning painted but not yet a lot is on
## it, else "" (Parks' edge pieces too).
static func zoned_problem(sim: CitySim, world: PackedVector2Array) -> String:
	var box := Rect2(world[0], Vector2.ZERO)
	for q in world:
		box = box.expand(q)
	for key in sim.lots_near(box):
		var lot: Dictionary = sim.lots[key]
		if not sim.buildings.has(key) and sim.zones.zone_at(lot.zone_pt) == ZoneMap.Zone.NONE:
			continue
		for q in Geometry2D.intersect_polygons(world, lot.corners):
			if CivicHubs.area(q) > 1.0:
				return "Zoned or built on."
	# Zoning painted but not yet a lot.
	for x in range(floori(box.position.x / ZoneMap.CELL), floori(box.end.x / ZoneMap.CELL) + 1):
		for y in range(floori(box.position.y / ZoneMap.CELL), floori(box.end.y / ZoneMap.CELL) + 1):
			if sim.zones.cells.has(Vector2i(x, y)) and Geometry2D.is_point_in_polygon(
					Vector2((x + 0.5) * ZoneMap.CELL, (y + 0.5) * ZoneMap.CELL), world):
				return "Zoned."
	return ""


## `parts` (outlines, x, z) less `poly` (and half a metre round it), less
## any part it sits wholly inside (it would leave a hole).
static func cut_out(parts: Array, poly: PackedVector2Array) -> Array:
	for grown in Geometry2D.offset_polygon(poly, 0.5):
		var next := []
		for part in parts:
			var inside := true
			for q in grown:
				if not Geometry2D.is_point_in_polygon(q, part):
					inside = false
					break
			if inside:
				continue  # that part goes (it would have a hole); the rest stay
			next.append_array(Geometry2D.clip_polygons(part, grown))
		parts = next
	return parts


## The player clears the edge piece under `p`: it goes, and the hub won't
## take it straight back (`cleared`). True when there was one.
static func clear_at(b: Dictionary, cell: float, p: Vector3) -> bool:
	if not on_edge(b, cell, p):
		return false
	var d: Vector3 = p - b.pos
	var l := Vector2(d.x * -b.dir.z + d.z * b.dir.x, -(d.x * b.dir.x + d.z * b.dir.z) + cell * 0.5)
	var c := Vector2i(roundi(l.x / cell), floori(l.y / cell))
	b.edge.erase(c)
	if not b.has("cleared"):
		b.cleared = []
	if not c in b.cleared:
		b.cleared.append(c)
	return true


## A saved direction as it was: normalising a unit vector again moves its
## last bits, and then a loaded town wouldn't save byte for byte the same
## (its edge pieces sit in its frame).
static func unit(v: Vector3) -> Vector3:
	return v if absf(v.length_squared() - 1.0) < 1e-5 else v.normalized()


## Edge pieces from a save (older saves have none), less any on a block.
static func from_save(saved, blocks: Array) -> Dictionary:
	var out := CivicHubs.edge_from_save(saved)
	out.erase(Vector2i.ZERO)
	for blk in blocks:
		out.erase(blk.c)
	return out
