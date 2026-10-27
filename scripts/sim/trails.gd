class_name Trails
extends RefCounted
## Walking and biking (Brawn, pitch #14). A trailhead is a hub: its parks-
## and-trails director grows the town's trails a month at a time from
## Balance.TRAIL_TREE: a greenway along the creek, connector trails out to
## the parks, bike lanes on nearby streets, and a longer county greenway.
## Trails go only over open ground; they cross streets but never take a
## home, a field or a company's land. Bike lanes restripe the player's own
## streets, so each one goes to the permit bell first.
##
## Kept light (Brawn worried about load): nothing here runs per person or
## per tick. Trails grow once a month; the land each lot is near is worked
## out once whenever the trails or lots change; and the traffic sim asks
## on_foot() once per trip it was about to start anyway.
##
## Benchmark: Indiana greenways and rail-trails (the Monon, the Cardinal
## Greenway, small-town riverwalks): a 10 ft paved path with a yellow centre
## line, a gravel trailhead lot with a kiosk, and painted bike lanes linking
## the trail into town.

## The trailhead's director: {id (site), leader, built, why}, or {} with no
## trailhead.
var hub := {}
## Trails built: [{kind: "greenway" or "connector", pts: [[x, z], ...],
## park (connectors: the park it runs to), done (greenway: blocked)}].
var paths := []
## Street segments restriped with bike lanes.
var lanes := []
## Open bike-lane permits: request id -> segment.
var asked := {}
## Downtown blocks closed to cars as pedestrian plazas, and open requests
## for them (request id -> segment).
var plazas := []
var asked_plaza := {}
## Trips walked or biked, this month and last (for the panel; not saved).
var walked := 0
var walked_last := 0
var _month := -1

const CELL := 100.0
const BIKE_TYPES := {RoadStyle.Type.STREET: RoadStyle.Type.STREET_BIKE,
	RoadStyle.Type.AVENUE: RoadStyle.Type.AVENUE_BIKE}

# Derived, never saved.
var _grid := {}       # cell -> [[a: Vector2, b: Vector2, lane: bool], ...]
var _near := {}       # lot key -> [distance to a trail, near a bike lane]
var _rev := ""
var _pgrid := {}      # cell -> [[a, b], ...], trail pieces only
var _pkey := ""
var _creek := {}      # trailhead id -> [] or [bank Vector2, heading Vector2]
var _roads := {}      # cell -> [[a, b, half], ...] while growing
var _lots := {}       # cell -> [lot corners, ...] while growing


## Signs up a new trailhead (one per town) and lets go of a removed one.
## The trails themselves stay: a trail is still there without its lot.
func sync(sim: CitySim) -> void:
	var id := -1
	for sid in sim.parks.sites:
		if sim.parks.sites[sid].kind == "trailhead":
			id = sid
	if id == -1:
		hub = {}
		return
	if not hub.is_empty() and int(hub.id) == id:
		return
	var l := Agency.leader(sim, hash([sim.city_seed, "trails", id]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, "trails", id, "name"])
	l.name = "%s %s" % [Education.FIRST[rng.randi() % Education.FIRST.size()],
		Education.LAST[rng.randi() % Education.LAST.size()]]
	hub = {"id": id, "leader": l, "built": [], "why": ""}
	if not sim.permits.locators.has("trails"):
		sim.permits.locators["trails"] = func(s2: CitySim, _hid: int) -> Vector2:
			var h: Dictionary = s2.parks.trails.hub
			if h.is_empty() or not s2.parks.sites.has(int(h.id)):
				return Vector2.INF
			var p: Vector3 = s2.parks.sites[int(h.id)].pos
			return Vector2(p.x, p.z)


## The director's turn (from Parks.decide): approved bike lanes go in, and
## once a month the trails grow and the next step of the tree is taken.
## True when something changed.
func decide(sim: CitySim) -> bool:
	sync(sim)
	var changed := _carry_out(sim)
	if _open_plazas(sim):
		changed = true
	var m := Seasons.pace_month(sim.tick_count)  # once a sim day ("a month")
	if m == _month:
		return changed
	_month = m
	walked_last = walked
	walked = 0
	if hub.is_empty():
		return changed
	_roads.clear()
	_lots.clear()
	var key := ""
	for node in Balance.TRAIL_TREE:
		if problem(sim, node.id) == "":
			key = node.id
			break
	if key != "":
		var node := _node(key)
		sim.economy.money -= int(node.cost)
		hub.built.append(key)
		hub.why = "The trails director built %s: %s." % [str(node.name).to_lower(), node.note]
		changed = true
	if _grow(sim):
		changed = true
	_ask_for_plaza(sim)
	_ask_for_lanes(sim)
	_roads.clear()
	_lots.clear()
	return changed


static func _node(key: String) -> Dictionary:
	for node in Balance.TRAIL_TREE:
		if node.id == key:
			return node
	return {}


## What a tree step waits on, or "" when the director can take it now.
func problem(sim: CitySim, key: String) -> String:
	var node := _node(key)
	if hub.is_empty() or node.is_empty():
		return "no trailhead"
	if key in hub.built:
		return "built"
	for r in node.get("requires", []):
		if not r in hub.built:
			return "needs the %s first" % str(_node(r).name).to_lower()
	var at: Vector3 = sim.parks.sites[int(hub.id)].pos
	var n: Dictionary = node.get("needs", {})
	if n.has("population") and not Agency.holds(sim, hub, at, 0.0, "population", n.population):
		return "needs %s people in town" % CitySim.money_text(int(n.population))
	if n.has("link") and not Agency.holds(sim, hub, at, 0.0, "link", n.link):
		return "needs a county road out to neighbor towns"
	if key == "greenway" and creek(sim).is_empty():
		return "needs a creek or river within half a mile"
	if key == "connectors" and _parks_near(sim).is_empty():
		return "needs a park within a mile"
	if key == "plaza" and plaza_block(sim) == -1:
		return "needs a busy downtown block (%d shops on one street)" % Balance.PLAZA_SHOPS
	var g: Dictionary = sim.permits.guidance("trails", int(hub.id))
	if g.stance == "hold":
		return "told to hold off"
	var keep := Balance.PARK_TREE_RESERVE * (0.5 + float(hub.leader.caution)) * (0.5 if g.stance == "grow" else 1.0)
	if sim.economy.money < int(node.cost) + roundi(keep):
		return "saving up ($%s)" % CitySim.money_text(int(node.cost))
	return ""


## Each tree step as [name, built or what it waits on], for the panel.
func status(sim: CitySim) -> Array:
	var rows := []
	for node in Balance.TRAIL_TREE:
		var why := problem(sim, node.id)
		rows.append([node.name, "Built" if why == "built" else ("Planned" if why == "" else why.capitalize())])
	return rows


# --- Growing ------------------------------------------------------------------

func _grow(sim: CitySim) -> bool:
	var changed := false
	if "greenway" in hub.built and _grow_greenway(sim):
		changed = true
	if "connectors" in hub.built and _connect_parks(sim):
		changed = true
	return changed


## Where a greenway meets the creek nearest the trailhead: [bank point,
## heading along the bank], or [] if no creek is in reach. Terrain never
## changes, so it is worked out once per trailhead.
func creek(sim: CitySim) -> Array:
	if hub.is_empty():
		return []
	var id := int(hub.id)
	if _creek.has(id):
		return _creek[id]
	var at: Vector3 = sim.parks.sites[id].pos
	var c := Vector2(at.x, at.z)
	var found := []
	var r := 25.0
	while r <= Balance.TRAIL_CREEK_REACH and found.is_empty():
		var n := maxi(8, int(TAU * r / 25.0))
		for k in n:
			var a := TAU * k / n
			var q := c + Vector2(cos(a), sin(a)) * r
			if Terrain.is_water(q.x, q.y):
				found = [q]
				break
		r += 25.0
	if found.is_empty():
		_creek[id] = []
		return []
	# Back from the water to dry ground, then a little further up the bank.
	var w: Vector2 = found[0]
	var toward := (c - w).normalized()
	var p := w
	for i in 160:
		p += toward * 5.0
		if not Terrain.is_water(p.x, p.y) and sim.land_ok(Vector3(p.x, 0.0, p.y)):
			break
	p += toward * 15.0
	var along := Vector2(-toward.y, toward.x)
	_creek[id] = [p, along]
	return _creek[id]


## A greenway grows along the bank a little each month, up to the length
## its tree allows, and stops for good where something blocks it.
func _grow_greenway(sim: CitySim) -> bool:
	var g := {}
	for path in paths:
		if path.kind == "greenway":
			g = path
	var target := Agency.effect(hub, Balance.TRAIL_TREE, "length+")
	var before := -1
	if g.is_empty():
		var start := creek(sim)
		if start.is_empty():
			return false
		var at: Vector3 = sim.parks.sites[int(hub.id)].pos
		var bank: Vector2 = start[0]
		var pts := []
		if _clear_line(sim, Vector2(at.x, at.z), bank):
			pts.append(_xz(Vector2(at.x, at.z)))
		pts.append(_xz(bank))
		g = {"kind": "greenway", "pts": pts, "done": false}
		paths.append(g)
		before = 0
	if bool(g.done) or _length(g.pts) >= target:
		return before == 0
	if before == -1:
		before = g.pts.size()
	# Along the bank the way it was going; the first step turns along it.
	var stepped: bool = g.pts.size() >= 2 and absf(_v(g.pts[-1]).distance_to(_v(g.pts[-2])) - Balance.TRAIL_STEP) < 0.5
	var heading: Vector2 = (_v(g.pts[-1]) - _v(g.pts[-2])).normalized() if stepped else creek(sim)[1]
	var grown := 0.0
	while grown < Balance.TRAIL_GROW_MONTH and _length(g.pts) < target:
		var step := _bank_step(sim, g, _v(g.pts[-1]), heading)
		if step.is_empty() and not stepped and grown == 0.0:
			step = _bank_step(sim, g, _v(g.pts[-1]), -heading)
		if step.is_empty():
			g.done = true
			break
		g.pts.append(_xz(step[0]))
		heading = step[1]
		grown += Balance.TRAIL_STEP
	_rev = ""
	return g.pts.size() != before or bool(g.done)


## The next point along the bank from p: [point, heading], or [] if the way
## is blocked. Keeps about 30 m from the water and turns as little as it can.
func _bank_step(sim: CitySim, g: Dictionary, p: Vector2, h: Vector2) -> Array:
	var best := []
	var best_score := INF
	for deg in [0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90]:
		var d := h.rotated(deg_to_rad(deg))
		var q := p + d * Balance.TRAIL_STEP
		var dw := _water_dist(q)
		if dw > 75.0 or Terrain.is_water(q.x, q.y) or not sim.land_ok(Vector3(q.x, 0.0, q.y)):
			continue
		var score := absf(deg) / 90.0 * 0.5 + absf(dw - 30.0) / 30.0
		if score >= best_score:
			continue
		if _blocked(sim, q) or _blocked(sim, (p + q) * 0.5) or _crosses_water(p, q) or _doubles_back(g, q):
			continue
		best = [q, d]
		best_score = score
	return best


func _water_dist(q: Vector2) -> float:
	for r in [15.0, 30.0, 45.0, 60.0, 75.0]:
		for k in 8:
			var a := TAU * k / 8.0
			if Terrain.is_water(q.x + cos(a) * r, q.y + sin(a) * r):
				return r
	return INF


func _crosses_water(a: Vector2, b: Vector2) -> bool:
	for f in [0.25, 0.5, 0.75]:
		var q := a.lerp(b, f)
		if Terrain.is_water(q.x, q.y):
			return true
	return false


## True when q comes back within 20 m of the path behind it.
func _doubles_back(g: Dictionary, q: Vector2) -> bool:
	for i in maxi(g.pts.size() - 2, 0):
		if _v(g.pts[i]).distance_to(q) < 20.0:
			return true
	return false


## Connector trails: a straight path from the trailhead to each park within
## a mile, where the ground between is open (streets are crossed).
func _connect_parks(sim: CitySim) -> bool:
	var done := {}
	for path in paths:
		if path.kind == "connector":
			done[int(path.park)] = true
	var at: Vector3 = sim.parks.sites[int(hub.id)].pos
	var a := Vector2(at.x, at.z)
	var added := false
	var n := done.size()
	for pid in _parks_near(sim):
		if n >= 4:
			break
		if done.has(pid):
			continue
		var pp: Vector3 = sim.parks.sites[pid].pos
		var b := Vector2(pp.x, pp.z)
		if _clear_line(sim, a, b):
			paths.append({"kind": "connector", "pts": [_xz(a), _xz(b)], "park": pid})
			added = true
			n += 1
	if added:
		_rev = ""
	return added


## Parks within a mile of the trailhead, nearest first.
func _parks_near(sim: CitySim) -> Array:
	if hub.is_empty():
		return []
	var at: Vector3 = sim.parks.sites[int(hub.id)].pos
	var out := []
	for pid in sim.parks.sites:
		if sim.parks.sites[pid].kind == "park" and sim.parks.sites[pid].pos.distance_to(at) < 1609.0:
			out.append(pid)
	out.sort_custom(func(x, y): return sim.parks.sites[x].pos.distance_to(at) < sim.parks.sites[y].pos.distance_to(at))
	return out


## True when a trail can run straight from a to b: open ground, crossing
## streets where it meets them.
func _clear_line(sim: CitySim, a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, int(a.distance_to(b) / 10.0))
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		if Terrain.is_water(q.x, q.y):
			return false
		if _on_road(sim, q, 2.0):
			continue
		if _blocked(sim, q, false):
			return false
	return true


## True when a trail can't stand at q: someone's lot, field, yard or
## building, a landmark, or right along a street.
func _blocked(sim: CitySim, q: Vector2, roads := true) -> bool:
	var p := Vector3(q.x, 0.0, q.y)
	if roads and _on_road(sim, q, 4.0):
		return true
	var pid := sim.parks.at(p)
	if pid != -1 and not sim.parks.sites[pid].kind in ["park", "trailhead"]:
		return true
	if Capital.owner_of(sim, p) != "" or sim.warehouses.covers(p) \
			or sim.education.covers(p) or sim.banks.covers(p) or sim.services.covers(p) or sim.hubs.covers(p) \
			or sim.mail.covers(p) or sim.power.covers(p) or sim.reserves.kind_at(p) != "":
		return true
	if _lots.is_empty():
		for key in sim.lots:
			if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE:
				continue
			var cs: PackedVector2Array = sim.lots[key].corners
			var c := _cell(cs[0])
			if not _lots.has(c):
				_lots[c] = []
			_lots[c].append(cs)
		_lots[Vector2i(1 << 30, 0)] = []  # filled, even with no lots
	var c0 := _cell(q)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for cs in _lots.get(c0 + Vector2i(dx, dz), []):
				if Geometry2D.is_point_in_polygon(q, cs):
					return true
	return false


## True when q is within a street's half width plus `pad`.
func _on_road(sim: CitySim, q: Vector2, pad: float) -> bool:
	if _roads.is_empty():
		for seg in sim.network.segments:
			var half := RoadStyle.half_width(sim.network.segments[seg].type)
			var pts := sim.network.sample_segment(seg, 16)
			for i in pts.size() - 1:
				var a := Vector2(pts[i].x, pts[i].z)
				var b := Vector2(pts[i + 1].x, pts[i + 1].z)
				var c := _cell((a + b) * 0.5)
				if not _roads.has(c):
					_roads[c] = []
				_roads[c].append([a, b, half])
		_roads[Vector2i(1 << 30, 0)] = []
	var c0 := _cell(q)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for r in _roads.get(c0 + Vector2i(dx, dz), []):
				if Geometry2D.get_closest_point_to_segment(q, r[0], r[1]).distance_to(q) < float(r[2]) + pad:
					return true
	return false


# --- Bike lanes ------------------------------------------------------------------

## One street at a time, nearest the trailhead first, each through the bell.
func _ask_for_lanes(sim: CitySim) -> void:
	if not "bike_lanes" in hub.built or not asked.is_empty() or not asked_plaza.is_empty():
		return
	if lanes.size() >= int(Agency.effect(hub, Balance.TRAIL_TREE, "lanes+")):
		return
	if sim.permits.guidance("trails", int(hub.id)).stance == "hold":
		return
	var at: Vector3 = sim.parks.sites[int(hub.id)].pos
	var best := -1
	var best_d := 800.0
	var ids := sim.network.segments.keys()
	ids.sort()
	for seg in ids:
		if seg in lanes or not BIKE_TYPES.has(sim.network.segments[seg].type):
			continue
		var pts := sim.network.sample_segment(seg, 8)
		var d := pts[pts.size() / 2].distance_to(at)
		if d < best_d:
			best_d = d
			best = seg
	if best == -1:
		return
	var route := []
	for p in sim.network.sample_segment(best, 8):
		route.append([p.x, p.z])
	var id := sim.permits.file(sim, {"hub": "trails", "hub_id": int(hub.id), "leader": hub.leader.name,
		"title": "Bike lanes on a street near the trail",
		"why": "A safe bike route from the trail into town. The street is restriped with a 5 ft lane each way; parking goes.",
		"route": route, "width": RoadStyle.half_width(sim.network.segments[best].type) * 2.0,
		"per_m": 20, "base": 2_000, "budget": 60_000})
	if id != -1:
		asked[id] = best


## Bike lanes the player approved are striped; denied or shelved ones are let go.
func _carry_out(sim: CitySim) -> bool:
	if asked.is_empty():
		return false
	var changed := false
	var ids := asked.keys()
	ids.sort()
	for rid in ids:
		var state := sim.permits.state_of(rid)
		if state == Permits.State.APPROVED:
			var seg: int = asked[rid]
			if sim.network.segments.has(seg) and BIKE_TYPES.has(sim.network.segments[seg].type):
				var req: Dictionary = sim.permits.requests.get(rid, {})
				sim.economy.money -= int(req.get("cost", 0))
				sim.network.set_type(seg, BIKE_TYPES[sim.network.segments[seg].type])
				lanes.append(seg)
				changed = true
			sim.permits.done(rid)
			asked.erase(rid)
		elif state != Permits.State.OPEN:
			asked.erase(rid)
	if changed:
		_rev = ""
	return changed


# --- Plazas ---------------------------------------------------------------------

## The busiest downtown block that could become a plaza: the street segment
## with the most shops along it (at least PLAZA_SHOPS), where cars can still
## get around (both ends join other streets). -1 if none.
func plaza_block(sim: CitySim) -> int:
	var shops := {}
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.COMMERCIAL and sim.lots.has(key):
			var seg := int(sim.lots[key].get("seg", -1))
			shops[seg] = int(shops.get(seg, 0)) + 1
	var best := -1
	var most := Balance.PLAZA_SHOPS - 1
	var ids := shops.keys()
	ids.sort()
	for seg in ids:
		if seg in plazas or not sim.network.segments.has(seg) or int(shops[seg]) <= most:
			continue
		var s: Dictionary = sim.network.segments[seg]
		if not s.type in Balance.PLAZA_TYPES:
			continue
		if sim.network.segments_at(int(s.a)).size() < 2 or sim.network.segments_at(int(s.b)).size() < 2:
			continue
		most = int(shops[seg])
		best = seg
	return best


## Asks the bell to close the busiest block to cars, one plaza at a time.
func _ask_for_plaza(sim: CitySim) -> void:
	if not "plaza" in hub.built or not asked.is_empty() or not asked_plaza.is_empty():
		return
	if plazas.size() >= int(Agency.effect(hub, Balance.TRAIL_TREE, "plazas+")):
		return
	if sim.permits.guidance("trails", int(hub.id)).stance == "hold":
		return
	var seg := plaza_block(sim)
	if seg == -1:
		return
	var route := []
	for p in sim.network.sample_segment(seg, 8):
		route.append([p.x, p.z])
	var id := sim.permits.file(sim, {"hub": "trails", "hub_id": int(hub.id), "leader": hub.leader.name,
		"title": "A pedestrian plaza on a downtown block",
		"why": "Close this busy block to cars for a plaza: pavers, benches, trees in planters and cafe tables. Delivery trucks still come at night, and drivers park around the corner.",
		"route": route, "width": RoadStyle.half_width(sim.network.segments[seg].type) * 2.0,
		"per_m": Balance.PLAZA_PER_M, "base": Balance.PLAZA_BASE, "budget": Balance.PLAZA_BUDGET})
	if id != -1:
		asked_plaza[id] = seg


## An approved plaza closes its block to cars (trucks at night only).
func _open_plazas(sim: CitySim) -> bool:
	var changed := false
	for seg in plazas.duplicate():
		if not sim.network.segments.has(seg):
			# The street was taken out: so is its plaza.
			plazas.erase(seg)
			changed = true
	var ids := asked_plaza.keys()
	ids.sort()
	for rid in ids:
		var state := sim.permits.state_of(rid)
		if state == Permits.State.APPROVED:
			var seg: int = asked_plaza[rid]
			if sim.network.segments.has(seg) and not seg in plazas:
				var req: Dictionary = sim.permits.requests.get(rid, {})
				sim.economy.money -= int(req.get("cost", 0))
				sim.traffic.close_segment(seg, true, "night")
				plazas.append(seg)
				changed = true
			sim.permits.done(rid)
			asked_plaza.erase(rid)
		elif state != Permits.State.OPEN:
			asked_plaza.erase(rid)
	if changed:
		_rev = ""
	return changed


# --- What trails do for the town ----------------------------------------------

## True when p is on a trail's cleared strip (no lots or fields there).
func on_path(p: Vector3) -> bool:
	if paths.is_empty():
		return false
	var key := "%d|%d" % [paths.size(), int(length())]
	if key != _pkey:
		_pkey = key
		_pgrid.clear()
		for path in paths:
			for i in path.pts.size() - 1:
				var a := _v(path.pts[i])
				var b := _v(path.pts[i + 1])
				var n := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
				for k in n + 1:
					var c := _cell(a.lerp(b, float(k) / n))
					if not _pgrid.has(c):
						_pgrid[c] = []
					if _pgrid[c].is_empty() or _pgrid[c][-1] != [a, b]:
						_pgrid[c].append([a, b])
	var q := Vector2(p.x, p.z)
	var c0 := _cell(q)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for e in _pgrid.get(c0 + Vector2i(dx, dz), []):
				if Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q) < Balance.TRAIL_CLEAR * 0.5:
					return true
	return false


## Land value or happiness a lot gets from a trail nearby.
func lift(sim: CitySim, key: String, effect: String) -> float:
	if paths.is_empty() and plazas.is_empty():
		return 0.0
	_refresh(sim)
	var near: Array = _near.get(key, [INF, false])
	if float(near[0]) >= Balance.TRAIL_REACH:
		return 0.0
	var top := Balance.TRAIL_VALUE if effect == "value" else Balance.TRAIL_HAPPY
	return top * (1.0 - float(near[0]) / Balance.TRAIL_REACH)


## Asked by the traffic sim before a trip by car: true when this one goes on
## foot or by bike instead (both ends near the trails, and not too far).
func on_foot(sim: CitySim, from_key: String, to_key: String, rng: RandomNumberGenerator) -> bool:
	if paths.is_empty() and lanes.is_empty() and plazas.is_empty():
		return false
	_refresh(sim)
	var a: Array = _near.get(from_key, [])
	var b: Array = _near.get(to_key, [])
	if a.is_empty() or b.is_empty() or float(a[0]) > Balance.WALK_NEAR and not a[1] \
			or float(b[0]) > Balance.WALK_NEAR and not b[1]:
		return false
	if sim.lots[from_key].pos.distance_to(sim.lots[to_key].pos) > Balance.WALK_MAX:
		return false
	var share := Balance.WALK_SHARE + (Balance.WALK_SHARE_BIKE if a[1] and b[1] else 0.0)
	if rng.randf() < share:
		walked += 1
		return true
	return false


## Total length of trail, metres.
func length() -> float:
	var total := 0.0
	for path in paths:
		total += _length(path.pts)
	return total


func upkeep() -> float:
	return length() / 1000.0 * Balance.TRAIL_UPKEEP_KM


## Rebuilds the lookup of trail pieces and how near each lot is, when the
## trails, lanes or lots changed.
func _refresh(sim: CitySim) -> void:
	var rev := "%d|%d|%d|%d|%d" % [paths.size(), int(length()), lanes.size(), sim.lots.size(), plazas.size()]
	if rev == _rev:
		return
	_rev = rev
	_grid.clear()
	_near.clear()
	for path in paths:
		for i in path.pts.size() - 1:
			_add_piece(_v(path.pts[i]), _v(path.pts[i + 1]), false)
	for seg in lanes:
		if sim.network.segments.has(seg):
			var pts := sim.network.sample_segment(seg, 8)
			for i in pts.size() - 1:
				_add_piece(Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z), true)
	# A plaza is a walking place too: the shops on it gain like trailside homes.
	for seg in plazas:
		if sim.network.segments.has(seg):
			var pts := sim.network.sample_segment(seg, 8)
			for i in pts.size() - 1:
				_add_piece(Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z), false)
	var reach := maxf(Balance.TRAIL_REACH, Balance.WALK_NEAR)
	var span := ceili(reach / CELL)
	for key in sim.lots:
		var q := Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z)
		var c0 := _cell(q)
		var best := INF
		var lane := false
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				for e in _grid.get(c0 + Vector2i(dx, dz), []):
					var d := Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q)
					if e[2]:
						lane = lane or d < 150.0
					elif d < best:
						best = d
		if best < reach or lane:
			_near[key] = [best, lane]


## Adds a trail piece to every cell it passes through (pieces are short).
func _add_piece(a: Vector2, b: Vector2, lane: bool) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
	var seen := {}
	for i in n + 1:
		var c := _cell(a.lerp(b, float(i) / n))
		if seen.has(c):
			continue
		seen[c] = true
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append([a, b, lane])


static func _cell(q: Vector2) -> Vector2i:
	return Vector2i(floori(q.x / CELL), floori(q.y / CELL))


static func _v(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


## A point as saved: [x, z] to the decimetre, so a save reads back the same.
static func _xz(q: Vector2) -> Array:
	return [roundi(q.x * 10.0) / 10.0, roundi(q.y * 10.0) / 10.0]


static func _length(pts: Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += _v(pts[i]).distance_to(_v(pts[i + 1]))
	return total


func to_dict() -> Dictionary:
	var a := {}
	for rid in asked:
		a[str(rid)] = asked[rid]
	var ap := {}
	for rid in asked_plaza:
		ap[str(rid)] = asked_plaza[rid]
	return {"hub": hub, "paths": paths, "lanes": lanes, "asked": a, "month": _month, "plazas": plazas,
		"asked_plaza": ap}


func from_dict(d: Dictionary) -> void:
	hub = {}
	var h: Dictionary = d.get("hub", {})
	if not h.is_empty():
		var l: Dictionary = h.leader
		hub = {"id": int(h.id), "leader": {"edu": float(l.edu), "caution": float(l.caution),
			"ambition": float(l.ambition), "name": str(l.name)}, "built": Array(h.built).map(func(x): return str(x)),
			"why": str(h.get("why", ""))}
	paths = []
	for p in d.get("paths", []):
		var e := {"kind": str(p.kind), "pts": Array(p.pts).map(func(q): return [float(q[0]), float(q[1])])}
		if p.has("park"):
			e.park = int(p.park)
		if p.has("done"):
			e.done = bool(p.done)
		paths.append(e)
	lanes = Array(d.get("lanes", [])).map(func(x): return int(x))
	asked = {}
	for k in d.get("asked", {}):
		asked[int(k)] = int(d.asked[k])
	plazas = Array(d.get("plazas", [])).map(func(x): return int(x))
	asked_plaza = {}
	for k in d.get("asked_plaza", {}):
		asked_plaza[int(k)] = int(d.asked_plaza[k])
	_month = int(d.get("month", -1))
	_rev = ""
