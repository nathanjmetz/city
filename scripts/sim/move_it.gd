class_name MoveIt
extends RefCounted
## Move It, the Cities: Skylines 1 mod (and CS2's built-in version): pick up
## anything the player placed and slide it, turn it, or raise it.
##
## The player can move roads, junctions, service buildings, landfills,
## recycling and cemeteries, parks and landmarks, warehouses, farmhouses and companies' main
## buildings. What grew on its own (homes, shops, factories,
## fields and pads) is never picked up: it follows its owner or adapts.
##
## A move is one command, {"type": "move", "items": [[kind, id], ...],
## "pivot": [x, z], "offset": [dx, dz], "turn": degrees, "raise": metres},
## applied through CitySim.apply so every copy of a shared region agrees.
## Each point turns about the pivot, then slides by the offset.
##
## The road wins: a moved road joins the roads it now crosses, homes and
## their zoning ride along with it, and a building in its way is shifted
## clear (if there's no room, RoadWins clears it as for any new road, and
## trims fields and pads).

## The kinds of thing that can be picked up.
const KINDS := ["road", "node", "service", "hub", "park", "warehouse", "farm", "industry"]
const BUILDINGS := ["service", "hub", "park", "warehouse", "farm", "industry"]
## A junction's grab radius beyond the road's half width.
const NODE_GRAB := 3.0
## How far a building in the way of a moved road may be shifted to clear it.
const MAX_SHIFT := 60.0
const SHIFT_STEP := 2.0


## What the player may pick up at a ground point: {type, id} or {}.
static func pick(sim: CitySim, p: Vector3) -> Dictionary:
	var sid := sim.services.at(p)
	if sid != -1:
		return {"type": "service", "id": sid}
	var hid := sim.hubs.at(p)
	if hid != -1:
		return {"type": "hub", "id": hid}
	var pid := sim.parks.at(p)
	if pid != -1:
		return {"type": "park", "id": pid}
	var wid := sim.warehouses.at(p)
	if wid != -1:
		return {"type": "warehouse", "id": wid}
	var iid := sim.industry.site_at(p)
	if iid != -1:
		return {"type": "industry", "id": iid}
	var fid := sim.farms.farm_at(p)
	if fid != -1:
		return {"type": "farm", "id": fid}
	var node := sim.network.find_node_near(p, 20.0)
	if node != -1 and _flat(sim.network.nodes[node]).distance_to(_flat(p)) \
			<= RoadStyle.half_width(sim.network.widest_at(node)) + NODE_GRAB:
		return {"type": "node", "id": node}
	var near := RoadIndex.segment_near(sim.network, p, 20.0)
	if not near.is_empty() and near.dist <= RoadStyle.half_width(sim.network.segments[near.seg].type) + 1.5:
		return {"type": "road", "id": near.seg}
	return {}


static func exists(sim: CitySim, item: Dictionary) -> bool:
	match item.get("type", ""):
		"road": return sim.network.segments.has(item.id)
		"node": return sim.network.nodes.has(item.id)
		"service": return sim.services.buildings.has(item.id)
		"hub": return sim.hubs.hubs.has(item.id)
		"park": return sim.parks.sites.has(item.id)
		"warehouse":
			# Other threads' stores (silos and the like) move with their owner.
			return sim.warehouses.buildings.has(item.id) and not Warehouses.is_store(sim.warehouses.buildings[item.id])
		"farm": return sim.farms.farms.has(item.id)
		"industry": return sim.industry.sites.has(item.id)
	return false


## The middle of a selection, which it turns about.
static func centre(sim: CitySim, items: Array) -> Vector3:
	var total := Vector3.ZERO
	var n := 0
	for it in items:
		if not exists(sim, it):
			continue
		match it.type:
			"road":
				var c := sim.network.curve_of(it.id)
				total += RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
			"node": total += sim.network.nodes[it.id]
			"service": total += sim.services.buildings[it.id].pos
			"hub": total += sim.hubs.extent(it.id)[0]
			"park": total += sim.parks.sites[it.id].pos
			"warehouse": total += Warehouses.center(sim.warehouses.buildings[it.id])
			"farm": total += sim.farms.farms[it.id].pos
			"industry": total += sim.industry.sites[it.id].pos
		n += 1
	return Vector3.ZERO if n == 0 else _flat(total / n)


## A move command for these items.
static func command(items: Array, pivot: Vector3, offset: Vector3, turn_deg := 0.0, raise := 0.0) -> Dictionary:
	var list := []
	for it in items:
		list.append([it.type, it.id])
	return {"type": "move", "items": list, "pivot": [pivot.x, pivot.z], "offset": [offset.x, offset.z],
		"turn": turn_deg, "raise": raise}


## The command that puts a move back.
static func inverse(cmd: Dictionary) -> Dictionary:
	var out := cmd.duplicate(true)
	out.pivot = [float(cmd.pivot[0]) + float(cmd.offset[0]), float(cmd.pivot[1]) + float(cmd.offset[1])]
	out.offset = [-float(cmd.offset[0]), -float(cmd.offset[1])]
	out.turn = -float(cmd.get("turn", 0.0))
	out.raise = -float(cmd.get("raise", 0.0))
	return out


## Works a move out without changing anything: {problem: "" if it can go
## ahead, nodes: id -> pos, ctrls: seg id -> ctrl, curves: seg id -> new
## curve (moved roads only), rejoin: [seg ids crossing a road level with it],
## merge: [[moved node, node it lands on]], services/farms/industry: id ->
## [pos, dir] (moved and shifted ones), zones: [[old cell, new cell, zone]]}.
static func plan(sim: CitySim, cmd: Dictionary) -> Dictionary:
	var net := sim.network
	var pivot := _v(cmd.get("pivot", [0, 0]))
	var offset := _v(cmd.get("offset", [0, 0]))
	var turn := deg_to_rad(float(cmd.get("turn", 0.0)))
	var raise := float(cmd.get("raise", 0.0))
	var out := {"problem": "", "nodes": {}, "ctrls": {}, "curves": {}, "rejoin": [], "merge": [],
		"services": {}, "hubs": {}, "parks": {}, "warehouses": {}, "farms": {}, "industry": {}, "zones": [], "parcels": []}
	var items := []
	for entry in cmd.get("items", []):
		var it := {"type": str(entry[0]), "id": int(entry[1])}
		if not it.type in KINDS or not exists(sim, it):
			out.problem = "That's gone."
			return out
		items.append(it)
	if items.is_empty():
		out.problem = "Nothing to move."
		return out
	var xf := func(p: Vector3) -> Vector3:
		return pivot + _flat(p - pivot).rotated(Vector3.UP, turn) + offset + Vector3(0, p.y, 0)
	out.xf = xf
	out.turn = turn

	# --- Roads -----------------------------------------------------------
	for it in items:
		if it.type == "road":
			var s: Dictionary = net.segments[it.id]
			for n in [s.a, s.b]:
				out.nodes[n] = true
		elif it.type == "node":
			out.nodes[it.id] = true
	var raised := {}
	for n in out.nodes:
		if n in sim.region_links:
			out.problem = "The county highway out to the region stays put."
			return out
		var p: Vector3 = xf.call(net.nodes[n]) + Vector3(0, raise, 0)
		if p.y < RoadTool.ELEVATION_MIN - 0.01 or p.y > RoadTool.ELEVATION_MAX + 0.01:
			out.problem = "Roads go from %d m down to %d m up." % [int(-RoadTool.ELEVATION_MIN), int(RoadTool.ELEVATION_MAX)]
			return out
		raised[n] = p
	out.nodes = raised
	var whole := {}  # seg -> true when both ends move (it keeps its shape)
	for id in net.segments:
		var s: Dictionary = net.segments[id]
		var ma: bool = out.nodes.has(s.a)
		var mb: bool = out.nodes.has(s.b)
		if not ma and not mb:
			continue
		var p0: Vector3 = out.nodes.get(s.a, net.nodes[s.a])
		var p2: Vector3 = out.nodes.get(s.b, net.nodes[s.b])
		var ctrl: Vector3
		if ma and mb:
			ctrl = xf.call(s.ctrl) + Vector3(0, raise, 0)
			whole[id] = true
		else:
			# One end moves: the bend shifts half as far, so a straight road stays straight.
			ctrl = s.ctrl + ((p0 - net.nodes[s.a]) + (p2 - net.nodes[s.b])) * 0.5
		out.ctrls[id] = ctrl
		out.curves[id] = [p0, ctrl, p2]
	for id in out.curves:
		var problem := _road_problem(sim, id, out.curves[id], whole.has(id))
		if problem != "":
			out.problem = problem
			return out
	var crossings := _crossings(net, out.curves)
	if crossings.problem != "":
		out.problem = crossings.problem
		return out
	out.rejoin = crossings.rejoin
	out.merge = _merges(net, out.nodes)
	if not whole.is_empty():
		out.zones = _carried_zones(sim, whole, xf)
		var keys := sim.lots.keys()
		keys.sort()
		for key in keys:
			if whole.has(sim.lots[key].seg):
				out.parcels.append(key)

	# --- Buildings -------------------------------------------------------
	var curves := []  # every road as it will be, with its right-of-way half width
	var moved_curves := []
	for id in net.segments:
		var c: Array = out.curves.get(id, net.curve_of(id)) + [RoadStyle.right_of_way_half(net.segments[id].type)]
		curves.append(c)
		if out.curves.has(id):
			moved_curves.append(c)
	var moving := {}  # "service:3" -> true
	for it in items:
		if it.type in BUILDINGS:
			var b := _building(sim, it.type, it.id)
			out[_group(it.type)][it.id] = [xf.call(_flat(b.pos)), (b.dir as Vector3).rotated(Vector3.UP, turn).normalized()]
			moving["%s:%d" % [it.type, it.id]] = true
	# Footprints of everything that isn't moving.
	var still := []  # [type, id, poly]
	for t in BUILDINGS:
		for id in _dict(sim, t):
			if t == "warehouse" and Warehouses.is_store(sim.warehouses.buildings[id]):
				continue
			if not moving.has("%s:%d" % [t, id]):
				var b := _building(sim, t, id)
				still.append([t, id, footprint(t, _kind(sim, t, id), b.pos, b.dir)])
				# A park's or hub's edge pieces, up to the sidewalk, are its
				# land too (Parks, CivicHubs).
				if t == "park":
					for poly in sim.parks.land_polys(id).slice(1):
						still.append([t, id, poly])
				elif t == "hub":
					for c in b.get("edge", {}):
						still.append([t, id, CivicHubs.edge_poly(b, c)])
	# Banks, campuses and the phone company don't move: their blocks and edge
	# pieces up to the sidewalk (BlockEdges) stay where they are.
	var fixed := []  # [type, id, poly]
	for id in sim.banks.banks:
		for poly in Banks.land_polys(sim.banks.banks[id]):
			fixed.append(["bank", id, poly])
	for id in sim.education.campuses:
		for poly in Education.land_polys(sim.education.campuses[id]):
			fixed.append(["campus", id, poly])
	for id in sim.telecom.companies:
		for poly in Telecom.land_polys(sim.telecom.companies[id]):
			fixed.append(["telecom", id, poly])
	var placed := []  # [type, id, poly] of moved ones, as they land
	for t in BUILDINGS:
		for id in out[_group(t)]:
			var at: Array = out[_group(t)][id]
			var poly := footprint(t, _kind(sim, t, id), at[0], at[1])
			var problem := _building_problem(sim, t, id, at[0], at[1], poly, curves, still + placed + fixed)
			if problem != "":
				out.problem = problem
				return out
			placed.append([t, id, poly])
	# The road wins: anything left standing in a moved road's way shifts clear.
	if not moved_curves.is_empty():
		for i in still.size():
			var entry: Array = still[i]
			# Hubs and parks cut their own land back when a road runs through.
			if entry[0] in ["hub", "park"] or not _clash(entry[2], moved_curves):
				continue
			var b := _building(sim, entry[0], entry[1])
			var others := []
			for j in still.size():
				if j != i:
					others.append(still[j])
			var spot := _shift_clear(sim, entry[0], entry[1], b, curves, others + placed + fixed, moved_curves)
			if spot.is_empty():
				continue  # no room: it makes way as for any new road (RoadWins)
			out[_group(entry[0])][entry[1]] = spot
			var poly := footprint(entry[0], _kind(sim, entry[0], entry[1]), spot[0], spot[1])
			still[i] = [entry[0], entry[1], poly]
	return out


## Carries a move out. True if it went through.
static func apply(sim: CitySim, cmd: Dictionary) -> bool:
	var p := plan(sim, cmd)
	if p.problem != "":
		return false
	var net := sim.network
	net.begin_batch()
	for n in p.nodes:
		net.nodes[n] = p.nodes[n]
	for id in p.ctrls:
		net.segments[id].ctrl = p.ctrls[id]
	# A moved end that lands on a junction becomes that junction.
	for pair in p.merge:
		_merge(net, pair[0], pair[1])
	# Roads now crossing level with another are rebuilt so they meet it.
	for id in p.rejoin:
		if not net.segments.has(id):
			continue
		var s: Dictionary = net.segments[id]
		var c := net.curve_of(id)
		net.remove_segment(id)
		net.build_road(c[0], c[1], c[2], s.type, s.oneway)
	net._changed()
	net.end_batch()
	# Homes and their zoning ride along with the street.
	for z in p.zones:
		sim.zones.erase_cell(z[0])
	for z in p.zones:
		sim.zones.cells[z[1]] = z[2]
		sim.zones.dirty.append(Rect2(Vector2(z[1]) * ZoneMap.CELL, Vector2.ONE * ZoneMap.CELL).grow(ZoneMap.CELL))
	for key in p.parcels:
		if sim.lots.has(key):
			_carry_lot(sim.lots[key], p.xf, p.turn)
	sim.touched_lots(p.parcels)
	for id in p.services:
		var b: Dictionary = sim.services.buildings[id]
		b.pos = p.services[id][0]
		b.dir = p.services[id][1]
		sim._clear_zones_under(sim.services.footprint(id))
	for id in p.hubs:
		var h: Dictionary = sim.hubs.hubs[id]
		h.pos = p.hubs[id][0]
		h.dir = p.hubs[id][1]
		# Edge pieces were cut to the old block's roads: they go, and come
		# back fitted to the new block if it's boxed in there too.
		h.edge = {}
		sim.hubs._touch(h)
		for c in h.cells:
			sim._clear_zones_under(CivicHubs.cell_poly(h, c))
	for id in p.parks:
		var park: Dictionary = sim.parks.sites[id]
		park.pos = p.parks[id][0]
		park.dir = p.parks[id][1]
		# Its paths, playgrounds and fields come along.
		for f in park.features:
			f.pos = p.xf.call(MoveIt._flat(f.pos))
		# Edge pieces were cut to the old block's roads: they go, and come
		# back fitted to the new block if it's boxed in there too.
		park.edge = {}
		sim._clear_zones_under(sim.parks.footprint(id))
	if not p.parks.is_empty():
		sim.parks_changed.emit()
	for id in p.warehouses:
		var w: Dictionary = sim.warehouses.buildings[id]
		w.pos = p.warehouses[id][0]
		w.dir = p.warehouses[id][1]
		sim._clear_zones_under(sim.warehouses.footprint(id))
	if not p.warehouses.is_empty():
		sim.warehouses_changed.emit()
	for id in p.farms:
		var f: Dictionary = sim.farms.farms[id]
		f.pos = p.farms[id][0]
		f.dir = p.farms[id][1]
	for id in p.industry:
		var s: Dictionary = sim.industry.sites[id]
		s.pos = p.industry[id][0]
		s.dir = p.industry[id][1]
	_settle_land(sim, p)
	return true


## Lanes find their road again, and a moved farm's fields or company's pads
## give way to what's already there.
static func _settle_land(sim: CitySim, p: Dictionary) -> void:
	var roads_moved: bool = not p.curves.is_empty()
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		if roads_moved or p.farms.has(id):
			var lane := sim.farm_drive(f.pos, f.dir)
			if not lane.is_empty():
				f.drive = lane
	for id in sim.industry.sites:
		var s: Dictionary = sim.industry.sites[id]
		if roads_moved or p.industry.has(id):
			var lane := sim.industry_drive(s.pos, s.dir)
			if not lane.is_empty():
				s.drive = lane
	# A moved farm or company keeps only land nobody else is using
	# (RoadWins then trims fields and pads back from every road).
	for id in p.farms:
		var f: Dictionary = sim.farms.farms[id]
		var kept := []
		for c in f.cells:
			var mid := Farms.cell_center(f, c)
			var yard := sim.farms.farm_at(mid)
			if sim.services.covers(mid) or sim.industry.covers(mid) or sim.hubs.covers(mid) \
					or (yard != -1 and yard != id) or not _field_free(sim, id, mid):
				continue
			kept.append(c)
		f.cells = kept
	for id in p.industry:
		var s: Dictionary = sim.industry.sites[id]
		var kept := []
		for c in s.pads:
			var mid := Industry.pad_center(s, c)
			var yard := sim.industry.site_at(mid)
			if sim.services.covers(mid) or sim.hubs.covers(mid) or sim.farms.covers(mid) \
					or sim.farms.field_at(mid) != -1 or (yard != -1 and yard != id):
				continue
			kept.append(c)
		s.pads = kept
	sim._lots_dirty = true
	sim._usable_cache.clear()
	sim.farms_changed.emit()
	sim.industry_changed.emit()


## A moved farm keeps a field only where no other farm already works.
static func _field_free(sim: CitySim, fid: int, mid: Vector3) -> bool:
	for other in sim.farms.farms:
		if other == fid:
			continue
		var o: Dictionary = sim.farms.farms[other]
		var local := Farms._local(o, mid)
		var c := Vector2i(roundi(local.x / Farms.CELL), roundi(local.y / Farms.CELL))
		if c in o.cells:
			return false
	return sim.farms.reserved_ok(mid)


## Moves a lot (and the home on it) with its street.
static func _carry_lot(lot: Dictionary, xf: Callable, turn: float) -> void:
	for k in ["front", "road", "zone_pt", "pos"]:
		if lot.has(k):
			lot[k] = xf.call(_flat(lot[k]))
	for k in ["dir", "normal"]:
		if lot.has(k):
			lot[k] = (lot[k] as Vector3).rotated(Vector3.UP, turn)
	var poly := PackedVector2Array()
	for q in lot.corners:
		var v: Vector3 = xf.call(Vector3(q.x, 0.0, q.y))
		poly.append(Vector2(v.x, v.z))
	lot.corners = poly


# --- Roads ---------------------------------------------------------------

## Real road rules for a road whose shape changed (one that only slid or
## turned keeps its shape, so it's still fine).
static func _road_problem(sim: CitySim, id: int, c: Array, rigid: bool) -> String:
	var type: int = sim.network.segments[id].type
	var flat := _flat(c[2]).distance_to(_flat(c[0]))
	if flat < RoadNetwork.MIN_LENGTH:
		return "That would squash a road too short."
	if not rigid:
		var r := RoadNetwork.min_radius(c[0], c[1], c[2])
		if r < RoadStyle.MIN_CURVE_RADIUS:
			return "Bend too tight: %d m. Roads need at least %d m (42 ft) so trucks can turn (AASHTO)." \
				% [int(r), int(RoadStyle.MIN_CURVE_RADIUS)]
		var spec: Dictionary = RoadStyle.TYPES[type]
		var grade := absf(c[2].y - c[0].y) / flat
		if grade > spec.grade + 0.0001:
			return "Too steep: %d%% grade. %s can climb at most %d%% (AASHTO)." \
				% [roundi(grade * 100.0), Words.a_first(Words.mid(spec.name)), roundi(spec.grade * 100.0)]
	var saved := sim.reserves.crosses(RoadNetwork.sample_curve(c[0], c[1], c[2], 24))
	if saved != "":
		return "That land is reserved for %s. Clear the reserve first." % Reserves.KINDS[saved]
	return ""


## Moved roads against the roads staying put: a crossing must meet level or
## clear by real bridge clearance. Level crossings away from a shared
## junction are listed to rebuild as junctions.
static func _crossings(net: RoadNetwork, curves: Dictionary) -> Dictionary:
	var out := {"problem": "", "rejoin": []}
	var n := 32
	for id in curves:
		var c: Array = curves[id]
		var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], n)
		var box := _bounds(pts)
		var s: Dictionary = net.segments[id]
		for other in net.segments:
			if curves.has(other):
				continue
			var o: Dictionary = net.segments[other]
			var old := net.sample_segment(other, n)
			if not box.intersects(_bounds(old), true):
				continue
			var shared := []
			for e in [o.a, o.b]:
				if e == s.a or e == s.b:
					shared.append(net.nodes[e])
			for i in n:
				for j in n:
					var hit = Geometry2D.segment_intersects_segment(_v2(pts[i]), _v2(pts[i + 1]), _v2(old[j]), _v2(old[j + 1]))
					if hit == null:
						continue
					var fi := _v2(pts[i]).distance_to(hit) / maxf(_v2(pts[i]).distance_to(_v2(pts[i + 1])), 0.001)
					var fj := _v2(old[j]).distance_to(hit) / maxf(_v2(old[j]).distance_to(_v2(old[j + 1])), 0.001)
					var dy := absf(lerpf(pts[i].y, pts[i + 1].y, fi) - lerpf(old[j].y, old[j + 1].y, fj))
					if dy >= RoadNetwork.SAME_LEVEL and dy < RoadNetwork.CLEARANCE:
						out.problem = "Not enough room to pass: %.1f m. Crossings need 16.5 ft (5 m) clearance under the deck (AASHTO)." % dy
						return out
					if dy >= RoadNetwork.SAME_LEVEL:
						continue
					var at_shared := false
					for q in shared:
						at_shared = at_shared or _v2(q).distance_to(hit) < RoadNetwork.MERGE_DIST
					if not at_shared and not id in out.rejoin:
						out.rejoin.append(id)
	out.rejoin.sort()
	return out


## Moved road ends that land on a junction staying put: [[moved, there]].
static func _merges(net: RoadNetwork, moved: Dictionary) -> Array:
	var out := []
	var ids := moved.keys()
	ids.sort()
	for m in ids:
		var best := -1
		var best_d := RoadNetwork.MERGE_DIST
		for n in net.nodes:
			if moved.has(n) or absf(net.nodes[n].y - moved[m].y) >= RoadNetwork.SAME_LEVEL:
				continue
			var d := _flat(net.nodes[n]).distance_to(_flat(moved[m]))
			if d < best_d:
				best_d = d
				best = n
		if best != -1:
			out.append([m, best])
	return out


static func _merge(net: RoadNetwork, from: int, into: int) -> void:
	if not net.nodes.has(from) or not net.nodes.has(into):
		return
	for id in net.segments.keys():
		var s: Dictionary = net.segments[id]
		if s.a == from:
			s.a = into
		if s.b == from:
			s.b = into
		if s.a == s.b:
			net.segments.erase(id)
	# Two roads now joining the same junctions: keep the first.
	var seen := {}
	var ids := net.segments.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = net.segments[id]
		var key := Vector2i(mini(s.a, s.b), maxi(s.a, s.b))
		if seen.has(key):
			net.segments.erase(id)
		else:
			seen[key] = true
	net.nodes.erase(from)


## Zoning along streets that move whole: [[old cell, new cell, zone]].
static func _carried_zones(sim: CitySim, whole: Dictionary, xf: Callable) -> Array:
	var net := sim.network
	var reach := LotPlanner.DEPTH + 4.0
	var lines := {}
	var boxes := {}
	for id in net.segments:
		var pts := net.sample_segment(id, 24)
		lines[id] = pts
		boxes[id] = _bounds(pts).grow(reach + RoadStyle.right_of_way_half(net.segments[id].type))
	var out := []
	var cells := sim.zones.cells.keys()
	cells.sort()
	for cell in cells:
		var mid := Vector2((cell.x + 0.5) * ZoneMap.CELL, (cell.y + 0.5) * ZoneMap.CELL)
		# The street this cell fronts is the nearest one.
		var best := -1
		var best_d := INF
		for id in lines:
			if not (boxes[id] as Rect2).has_point(mid):
				continue
			var pts: PackedVector3Array = lines[id]
			for i in pts.size() - 1:
				var d := Geometry2D.get_closest_point_to_segment(mid, _v2(pts[i]), _v2(pts[i + 1])).distance_to(mid)
				if d < best_d:
					best_d = d
					best = id
		if best == -1 or not whole.has(best) or best_d > reach + RoadStyle.right_of_way_half(net.segments[best].type):
			continue
		var to: Vector3 = xf.call(Vector3(mid.x, 0.0, mid.y))
		out.append([cell, Vector2i(floori(to.x / ZoneMap.CELL), floori(to.z / ZoneMap.CELL)), sim.zones.cells[cell]])
	return out


# --- Buildings -------------------------------------------------------------

## The ground a building covers at a spot.
static func footprint(type: String, kind, pos: Vector3, dir: Vector3) -> PackedVector2Array:
	if type == "park":
		return Parks.corners(pos, dir, kind.size)
	if type == "warehouse":
		# `kind` is the warehouse: its site grows deeper with each bay.
		return Warehouses.corners({"kind": kind.kind, "pos": pos, "dir": dir, "bays": kind.bays})
	if type == "hub":
		# `kind` is the hub: its land, laid out from the gate.
		var pts := PackedVector2Array()
		for c in kind.cells:
			pts.append_array(CivicHubs.cell_poly({"pos": pos, "dir": dir, "cell": kind.cell}, c))
		var hull := Geometry2D.convex_hull(pts)
		hull.remove_at(hull.size() - 1)
		return hull
	var size: Vector2
	match type:
		"service": size = Services.KINDS[kind].size
		"farm": size = Farms.FARMHOUSE_SIZE
		_: size = Industry.HQ_SIZE
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * size.x * 0.5 * s.x + dir * size.y * 0.5 * s.y
		poly.append(Vector2(p.x, p.z))
	return poly


## Why a building can't land here, or "".
static func _building_problem(sim: CitySim, type: String, id: int, pos: Vector3, dir: Vector3,
		poly: PackedVector2Array, curves: Array, others: Array) -> String:
	if _clash(poly, curves):
		return "Too close to a road."
	for o in others:
		if not Geometry2D.intersect_polygons(poly, o[2]).is_empty():
			return "Overlaps the %s." % _name(sim, o[0], o[1])
	var pts := [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y))
	match type:
		"farm":
			if not sim.farms.reserved_ok(pos):
				return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(pos)]
			if _nearest_road(curves, pos) > Farms.MAX_DRIVE:
				return "Needs a road within %d m for its farm lane." % int(Farms.MAX_DRIVE)
			for p in pts:
				var pad := sim.industry.pad_at(p)
				if pad != -1:
					return "That ground belongs to a company."
				var field := sim.farms.field_at(p)
				if field != -1 and field != id:
					return "That ground is another farm's field."
		"industry":
			var kind: String = sim.industry.sites[id].kind
			if not sim.industry.reserved_ok(kind, pos):
				return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(pos)]
			if sim.industry_reach(kind, pos) < Industry.MIN_RICHNESS:
				return "No %s near here." % Industry.KINDS[kind].cargo
			if _nearest_road(curves, pos) > Industry.MAX_DRIVE:
				return "Needs a road within %d m for its access road." % int(Industry.MAX_DRIVE)
			for p in pts:
				if sim.farms.field_at(p) != -1:
					return "That ground is farmland."
				var pad := sim.industry.pad_at(p)
				if pad != -1 and pad != id:
					return "That ground belongs to another company."
		"hub":
			var h: Dictionary = sim.hubs.hubs[id]
			var moved := {"pos": pos, "dir": dir, "cell": h.cell}
			for c in h.cells:
				var cell := CivicHubs.cell_poly(moved, c, 1.0)
				if _clash(cell, curves):
					return "Too close to a road."
				var mid := CivicHubs.cell_center(moved, c)
				for q in [mid] + Array(cell).map(func(v): return mid.lerp(Vector3(v.x, 0.0, v.y), 0.9)):
					if sim.reserves.kind_at(q) != "":
						return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(q)]
					var owner := Capital.owner_of(sim, q)
					if owner.begins_with("farm:"):
						return "That ground is farmland."
					if owner.begins_with("site:"):
						return "That ground belongs to a company."
					var other := sim.hubs.at(q)
					if other != -1 and other != id:
						return "Overlaps the %s." % CivicHubs.KINDS[sim.hubs.hubs[other].kind].name.to_lower()
		"park":
			var problem := sim.parks.ground_problem(sim, poly, id)
			if problem != "" and problem != "Too close to a road.":
				return problem
		"warehouse":
			var w: Dictionary = sim.warehouses.buildings[id]
			var mid := Warehouses.center({"kind": w.kind, "pos": pos, "dir": dir, "bays": w.bays})
			if sim.reserves.kind_at(mid) != "":
				return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(mid)]
			for p in pts + [mid]:
				var owner := Capital.owner_of(sim, p)
				if owner.begins_with("farm:"):
					return "That ground is farmland."
				if owner.begins_with("site:"):
					return "That ground belongs to a company."
		"service":
			for p in pts:
				if sim.farms.field_at(p) != -1:
					return "That ground is farmland."
				if sim.industry.pad_at(p) != -1:
					return "That ground belongs to a company."
	return ""


## Shifts a building straight away from the moved road until it's clear:
## [pos, dir], or [] if there's no room.
static func _shift_clear(sim: CitySim, type: String, id: int, b: Dictionary, curves: Array,
		others: Array, moved_curves: Array) -> Array:
	var best := Vector3.ZERO
	var best_d := INF
	var at := _v2(b.pos)
	for c in moved_curves:
		var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], 32)
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(at, _v2(pts[i]), _v2(pts[i + 1]))
			if q.distance_to(at) < best_d:
				best_d = q.distance_to(at)
				best = Vector3(q.x, 0.0, q.y)
	var away := _flat(b.pos) - best
	if away.length() < 0.01:
		away = -(b.dir as Vector3)
	away = away.normalized()
	var d := SHIFT_STEP
	while d <= MAX_SHIFT:
		var pos: Vector3 = _flat(b.pos) + away * d
		var poly := footprint(type, _kind(sim, type, id), pos, b.dir)
		if _building_problem(sim, type, id, pos, b.dir, poly, curves, others) == "":
			return [pos, b.dir]
		d += SHIFT_STEP
	return []


## True when a footprint runs onto any of these roads.
static func _clash(poly: PackedVector2Array, curves: Array) -> bool:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	for c in curves:
		var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], 24)
		if not box.grow(40.0).intersects(_bounds(pts)):
			continue
		var hw := float(c[3])
		for p in pts:
			var q := _v2(p)
			if Geometry2D.is_point_in_polygon(q, poly):
				return true
			for i in poly.size():
				if Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q) < hw - 0.5:
					return true
	return false


static func _nearest_road(curves: Array, pos: Vector3) -> float:
	var best := INF
	for c in curves:
		for q in RoadNetwork.sample_curve(c[0], c[1], c[2], 24):
			best = minf(best, _flat(q).distance_to(_flat(pos)))
	return best


static func _group(type: String) -> String:
	return {"service": "services", "hub": "hubs", "park": "parks", "warehouse": "warehouses", "farm": "farms", "industry": "industry"}[type]


static func _dict(sim: CitySim, type: String) -> Dictionary:
	match type:
		"service": return sim.services.buildings
		"hub": return sim.hubs.hubs
		"park": return sim.parks.sites
		"warehouse": return sim.warehouses.buildings
		"farm": return sim.farms.farms
	return sim.industry.sites


static func _building(sim: CitySim, type: String, id: int) -> Dictionary:
	return _dict(sim, type)[id]


static func _kind(sim: CitySim, type: String, id: int):
	match type:
		"service": return sim.services.buildings[id].kind
		"hub": return sim.hubs.hubs[id]
		"park": return sim.parks.sites[id]
		"warehouse": return sim.warehouses.buildings[id]
	return null


static func _name(sim: CitySim, type: String, id: int) -> String:
	match type:
		"service": return Services.KINDS[sim.services.buildings[id].kind].name.to_lower()
		"hub": return CivicHubs.KINDS[sim.hubs.hubs[id].kind].name.to_lower()
		"park": return sim.parks.sites[id].name
		"warehouse": return Warehouses.KINDS[sim.warehouses.buildings[id].kind].name.to_lower()
		"farm": return "farmhouse"
		"bank": return str(sim.banks.banks[id].name)
		"campus": return Education.KINDS[sim.education.campuses[id].kind].name.to_lower()
		"telecom": return "phone company"
	return Industry.KINDS[sim.industry.sites[id].kind].name.to_lower()


# --- Helpers -------------------------------------------------------------

static func _bounds(pts: PackedVector3Array) -> Rect2:
	var r := Rect2(_v2(pts[0]), Vector2.ZERO)
	for p in pts:
		r = r.expand(_v2(p))
	return r.grow(0.5)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), 0.0, float(a[1]))
