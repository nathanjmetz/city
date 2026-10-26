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
		"edge_min": MIN_WIDTH / cell, "edge_tidy": true}


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
	# cut alone first (cheap), the ground check only if it would grow.
	for c in b.edge.keys():
		var keep: Dictionary = b.edge
		var others: Dictionary = keep.duplicate()
		others.erase(c)
		var v := h.duplicate()
		v.edge = others
		var now := CivicHubs.area(keep[c])
		var fresh := CivicHubs.edge_shape(sim, v, c, others, none)
		if fresh.is_empty() or CivicHubs.area(fresh) <= now + 1.0:
			continue
		b.edge = others  # its own old piece isn't someone else's land
		fresh = CivicHubs.edge_shape(sim, v, c, others, problem)
		b.edge = keep
		if not fresh.is_empty() and CivicHubs.area(fresh) > now + 1.0:
			keep[c] = fresh
			changed = true
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
	return zoned_problem(sim, world)


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


## Edge pieces from a save (older saves have none), less any on a block.
static func from_save(saved, blocks: Array) -> Dictionary:
	var out := CivicHubs.edge_from_save(saved)
	out.erase(Vector2i.ZERO)
	for blk in blocks:
		out.erase(blk.c)
	return out
