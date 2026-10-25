class_name Healthcare
extends RefCounted
## Hospitals, ambulances, nursing homes and daycare (Best of CS pitch #4).
##
## The hospital is a hub with a leader, Brawn's model: the player places a
## county hospital and its administrator does the rest. The administrator's
## schooling follows the town's schools when they're hired, and their
## ambition and caution are their own. Every few game hours they weigh the
## next building in the hospital's development tree (Balance.HOSPITAL_TREE):
## what the town and its neighbors need, what they're qualified to run and
## what the hospital has saved. Each new building goes on land right next to
## the hospital (buying out the homes in the way), never a second site;
## when roads, farms or other services box it in, it builds up instead.
## A hospital too big for its town closes its newest building.
##
## Every ambulance call is a real trip: the ambulance leaves its bay, drives
## to the home, stays with the patient, then drives back and parks at the
## hospital. A town without a hospital gets the county's ambulance from the
## highway, which takes far longer.
##
## Good care (a hospital or clinic, a nursing home and a daycare nearby)
## makes people want to live here, and the hospital is a big employer.

const TICKS_PER_MONTH := 24 * CitySim.TICKS_PER_HOUR
const TICKS_PER_YEAR := 12 * TICKS_PER_MONTH
const DECIDE_EVERY := Balance.HOSPITAL_DECIDE_EVERY
## The development tree, in the shared Agency format (scripts/sim/agency.gd).
const NODES := Balance.HOSPITAL_TREE
## The same nodes by id, and their ids in tree order.
static var TREE := _index()
static var ORDER: Array = NODES.map(func(n): return n.id)
const LEVELS := Balance.HOSPITAL_LEVELS
## Ticks between rolls for ambulance calls.
const CALL_EVERY := 10
## The hub kind it files permit requests under.
const PERMIT_KIND := "hospital"

const FIRST := ["Ruth", "Dale", "Linda", "Gary", "Karen", "Mark", "Joan", "Steve", "Diane", "Larry", "Carol",
	"Doug", "Marcia", "Roger", "Ann", "Tom", "Beth", "Rick", "Janet", "Bill", "Peggy", "Wayne", "Lori", "Dean"]
const LAST := ["Hollis", "Brandt", "Kessler", "Stoltz", "Meyer", "Wagner", "Ellison", "Carver", "Lindqvist",
	"Hartman", "Pruitt", "Osborne", "Becker", "Duvall", "Fenwick", "Sauer", "Whitaker", "Hayes", "Ritter", "Voss"]
const HOSPITAL_NAMES := ["Good Samaritan", "St. Mary's", "Memorial", "Mercy", "Union", "St. Joseph's",
	"Deaconess", "Methodist", "Riverside", "Lutheran", "St. Vincent's", "Community"]
const CALLS := ["chest pain", "a fall at home", "trouble breathing", "a car crash", "a diabetic emergency",
	"a stroke", "a sick child", "an allergic reaction", "a broken leg", "a high fever"]

## One per hospital: service id -> {name, level, leader: (Agency.leader,
## plus name, title, hired), built: [node ids] (Agency's record), savings,
## pieces: [{key, rect: [s0, s1, d0, d1] or []}], front: Vector3, side:
## Vector3, dir: Vector3, x0, x1, depth, area0, spare, boxed, plan, permit
## ({req, key} while a land request is with the player), why, note, streak,
## calls, treated, resp_sum, resp_n}.
## Rects are in the hospital's own frame: s along the street from its
## front centre, d back from the street.
var hubs := {}
## Ambulances on the road: trip id -> {hub, stage ("out" or "back"),
## scene: {ref, pos}, call, patient, t0}.
var trips := {}
## Crews with a patient: [{hub, scene, call, patient, t0, until}].
var on_scene := []
## Calls the county's ambulance answered (no hospital, or all ours busy).
var county_calls := 0
## Set by the region every tick: people in the neighboring towns, and how
## much their hospitals' helipads and specialty centers lift care here.
var region_pop := 0
var region_care := 0.0


# --- The administrators' decisions ------------------------------------------

static func _index() -> Dictionary:
	var out := {}
	for n in NODES:
		out[n.id] = n
	return out


func tick(sim: CitySim) -> void:
	if not sim.permits.locators.has(PERMIT_KIND):
		sim.permits.locators[PERMIT_KIND] = func(s: CitySim, id: int) -> Vector2:
			var b: Dictionary = s.services.buildings.get(id, {"pos": Vector3.ZERO})
			return Vector2(b.pos.x, b.pos.z)
	if sim.tick_count % DECIDE_EVERY == 0:
		decide(sim)
	if not sim.simulate_traffic:
		return
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			_arrive(sim, a.id)
	for f in sim.traffic.failed:
		if trips.has(f.id):
			trips.erase(f.id)  # no way through: the crew is back at base
	for crew in on_scene.duplicate():
		if sim.tick_count >= int(crew.until):
			_head_back(sim, crew)
	if sim.tick_count % CALL_EVERY == 0:
		_roll_call(sim)


## Every administrator takes a step: retire, save, then build the next
## piece of the tree if the hospital can afford its down payment.
func decide(sim: CitySim) -> bool:
	var changed := false
	for id in hubs.keys():
		if not sim.services.buildings.has(id) or sim.services.buildings[id].kind != Services.Kind.HOSPITAL:
			hubs.erase(id)
	var ids := sim.services.buildings.keys()
	ids.sort()
	for id in ids:
		if sim.services.buildings[id].kind != Services.Kind.HOSPITAL:
			continue
		if not hubs.has(id):
			hubs[id] = _new_hub(sim, id)
		var h: Dictionary = hubs[id]
		_follow(sim, id)
		if sim.tick_count - int(h.leader.hired) >= Balance.HOSPITAL_TENURE_DAYS * TICKS_PER_MONTH:
			var old: String = h.leader.name
			h.leader = _hire(sim, id)
			h.note = "%s retired; %s took over." % [old, h.leader.name]
		var net := monthly_net(sim, id)
		h.savings = roundf(h.savings + net * DECIDE_EVERY / float(TICKS_PER_MONTH))  # whole dollars
		if h.savings < 0.0:
			h.streak += 1
			if h.streak >= 4 and not h.pieces.is_empty():
				_close_newest(sim, id)
				changed = true
			continue
		h.streak = 0
		if not h.permit.is_empty():
			changed = _permit_step(sim, id) or changed
			continue
		h.plan = _pick(sim, id)
		if h.plan == "":
			continue
		var cost := project_cost(sim, id, h.plan)
		if cost.is_empty() or h.savings < cost.down:
			continue
		if not cost.buyout.is_empty():
			# Homes or shops in the way are the player's call: ask first.
			_ask(sim, id, h.plan, cost)
			continue
		h.savings -= roundf(cost.down)
		_build(sim, id, h.plan, cost)
		changed = true
	return changed


## Asks the player (the permits bell) to let the hospital buy the homes or
## shops on the strip it wants. The player can reshape the strip.
func _ask(sim: CitySim, id: int, key: String, cost: Dictionary) -> void:
	var h: Dictionary = hubs[id]
	var area := []
	for p in rect_poly(h, cost.rect):
		area.append([p.x, p.y])
	var size: float = (float(cost.rect[1]) - float(cost.rect[0])) * (float(cost.rect[3]) - float(cost.rect[2]))
	var req: int = sim.permits.file(sim, {"hub": PERMIT_KIND, "hub_id": id, "leader": h.leader.name,
		"title": "%s for %s" % [TREE[key].name, h.name],
		"why": "%s wants to buy %d %s next door for the hospital's %s." % [h.leader.name, cost.buyout.size(),
			"property" if cost.buyout.size() == 1 else "properties", TREE[key].name.to_lower()],
		"area": area, "change": "Homes to hospital", "per_m2": roundi(cost.price / maxf(size, 1.0)),
		"budget": roundi(h.savings)})
	if req != -1:
		h.permit = {"req": req, "key": key}
		h.note = "Asked to buy the land next door for the %s." % TREE[key].name.to_lower()


## While a land request is out: build once the player says yes (on the
## land they agreed to), or drop it when they say no.
func _permit_step(sim: CitySim, id: int) -> bool:
	var h: Dictionary = hubs[id]
	var req_id := int(h.permit.req)
	var state: int = sim.permits.state_of(req_id)
	if state == Permits.State.OPEN:
		return false
	var key: String = h.permit.key
	if state != Permits.State.APPROVED:
		h.permit = {}
		h.note = "Was told no on the land for the %s: it will build up instead." % TREE[key].name.to_lower()
		h.boxed = true
		return false
	var req: Dictionary = sim.permits.requests[req_id]
	var land := _land_at(sim, id, _frame_rect(h, req.route))
	if land.is_empty():
		sim.permits.done(req_id)
		h.permit = {}
		return false
	var cost := project_cost(sim, id, key, land)
	if h.savings < cost.down:
		return false  # saving up for it
	h.savings -= roundf(cost.down)
	_build(sim, id, key, cost)
	sim.permits.done(req_id)
	h.permit = {}
	return true


## The strip a (maybe reshaped) outline asks for, in the hospital's frame,
## kept touching the campus on the side it grows from.
func _frame_rect(h: Dictionary, outline: Array) -> Array:
	var s0 := INF
	var s1 := -INF
	var d0 := INF
	var d1 := -INF
	for p in outline:
		var v: Vector3 = Vector3(float(p[0]), 0.0, float(p[1])) - h.front
		var s := v.dot(h.side)
		var d := -v.dot(h.dir)
		s0 = minf(s0, s)
		s1 = maxf(s1, s)
		d0 = minf(d0, d)
		d1 = maxf(d1, d)
	d0 = maxf(d0, 0.0)
	if d0 >= float(h.depth) - 1.0:
		d0 = h.depth
		s0 = maxf(s0, h.x0)
		s1 = minf(s1, h.x1)
	elif s1 <= float(h.x0) + 1.0:
		s1 = h.x0
	elif s0 >= float(h.x1) - 1.0:
		s0 = h.x1
	return [s0, s1, d0, d1].map(func(v): return snappedf(v, 0.25))


## The player moved the hospital (Move It): its frame follows the building.
func _follow(sim: CitySim, id: int) -> void:
	var h: Dictionary = hubs[id]
	var b: Dictionary = sim.services.buildings[id]
	if b.dir.is_equal_approx(h.dir) and b.pos.is_equal_approx(h.front + h.side * (h.x0 + h.x1) * 0.5 - h.dir * h.depth * 0.5):
		return
	h.dir = b.dir
	h.side = Vector3(-b.dir.z, 0.0, b.dir.x)
	h.front = b.pos + b.dir * h.depth * 0.5 - h.side * (h.x0 + h.x1) * 0.5


func _new_hub(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	var size := Services.size_of(b)
	var names := HOSPITAL_NAMES.size()
	var pick := (absi(hash([sim.city_seed, "hospital"])) + id) % names
	return {"name": HOSPITAL_NAMES[pick], "level": 0, "leader": _hire(sim, id), "savings": 0.0, "pieces": [],
		"front": b.pos + b.dir * size.y * 0.5, "side": Vector3(-b.dir.z, 0.0, b.dir.x), "dir": b.dir,
		"x0": -size.x * 0.5, "x1": size.x * 0.5, "depth": size.y, "area0": size.x * size.y, "spare": 0.0,
		"built": [], "boxed": false, "plan": "", "permit": {}, "why": "", "note": "", "streak": 0, "calls": 0, "treated": 0, "resp_sum": 0, "resp_n": 0}


## A new administrator (Agency.leader): their schooling follows the town's
## schools today; ambition and caution are their own.
func _hire(sim: CitySim, id: int) -> Dictionary:
	var seed := hash([sim.city_seed, id, sim.tick_count, "administrator"])
	var lead := Agency.leader(sim, seed)
	for k in ["edu", "caution", "ambition"]:
		lead[k] = roundf(float(lead[k]) * 100.0) / 100.0  # the nearest double, so saves round-trip
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	var edu: float = lead.edu
	var title := "RN"
	if edu >= 0.8:
		title = "MD, MPH"
	elif edu >= 0.55:
		title = "MD"
	elif edu >= 0.3:
		title = "MBA"
	var name: String = FIRST[rng.randi() % FIRST.size()] + " " + LAST[rng.randi() % LAST.size()]
	if title.begins_with("MD"):
		name = "Dr. " + name
	lead.merge({"name": name, "title": title, "hired": sim.tick_count})
	return lead


## The next piece the administrator wants: of everything the hospital
## qualifies for, an ambitious one aims for the biggest project and a
## modest one the smallest. "" if nothing is open to it.
func _pick(sim: CitySim, id: int) -> String:
	var open := []
	for key in ORDER:
		if unmet(sim, id, key) == "":
			open.append(key)
	if open.is_empty():
		return ""
	open.sort_custom(func(a, b): return TREE[a].cost < TREE[b].cost or (TREE[a].cost == TREE[b].cost and a < b))
	return open[roundi(hubs[id].leader.ambition * (open.size() - 1))]


## Why the hospital can't take on this piece yet, in plain words, or "".
func unmet(sim: CitySim, id: int, key: String) -> String:
	var h: Dictionary = hubs[id]
	var t: Dictionary = TREE[key]
	if has_piece(id, key):
		return "built"
	if int(t.tier) > int(h.level):
		return "needs the %s first" % LEVELS[int(t.tier)].name.to_lower()
	for r in t.get("requires", []):
		if not has_piece(id, r):
			return "needs the %s first" % TREE[r].name.to_lower()
	var needs: Dictionary = t.needs
	# Ambitious administrators move before the numbers are all there, and
	# more so when the player told them to grow.
	var ambition := float(h.leader.ambition)
	if sim.permits.guidance(PERMIT_KIND, id).stance == "grow":
		ambition += 0.3
	var push := 1.3 - 0.6 * ambition
	var pop := covered_pop(sim, id)
	for need in needs:
		var v = needs[need]
		match need:
			"pop":
				if pop < int(v) * push:
					return "needs %s people nearby (has %s)" % [CitySim.money_text(roundi(int(v) * push)), CitySim.money_text(pop)]
			"catchment":
				var c := pop + regional_pop(sim)
				if c < int(v) * push:
					return "needs %s people in town and the region (has %s)" % [CitySim.money_text(roundi(int(v) * push)),
						CitySim.money_text(c)]
			"region_pop":
				if regional_pop(sim) < int(v):
					return "needs neighboring towns of %s people" % CitySim.money_text(int(v))
			"leader_edu":
				if float(h.leader.edu) < float(v):
					return "needs a better educated administrator (better schools help the next hire)"
			"education":
				var s := school_share(sim)
				if s < float(v):
					return "needs good schools: %d%% of homes near a school, needs %d%%" % [roundi(s * 100.0), roundi(float(v) * 100.0)]
			"daycare":
				if not _town_has(sim, Services.Kind.DAYCARE):
					return "needs a daycare in town"
			"nursing_home":
				if not _town_has(sim, Services.Kind.NURSING_HOME):
					return "needs a nursing home in town"
			"boxed":
				if not h.boxed:
					return "only once the hospital runs out of land"
			_:
				if not Agency.holds(sim, h, h.front, monthly_net(sim, id) * 12.0, need, v):
					return "not yet (%s)" % need.replace("_", " ").replace(":", ": ")
	return ""


## What a piece would cost now: {total, down, rect (or [] to build up),
## buyout: [lot keys]}. `land` is a strip already agreed (else it looks).
func project_cost(sim: CitySim, id: int, key: String, land := {}) -> Dictionary:
	var h: Dictionary = hubs[id]
	var t: Dictionary = TREE[key]
	var a: Dictionary = h.leader
	var total: float = float(t.cost) * (1.0 - Balance.HOSPITAL_EDU_SAVING * float(a.edu))
	var rect := []
	var buyout := []
	var area: float = t.area
	var grown: float = (h.x1 - h.x0) * h.depth
	if not land.is_empty():
		rect = land.rect
		buyout = land.buyout
		total += land.price
	elif area > 0.0 and h.spare < area and grown + area <= Balance.HUB_MAX_GROWTH * h.area0 \
			and sim.permits.guidance(PERMIT_KIND, id).stance != "hold":
		land = find_land(sim, id, area)
		h.boxed = land.is_empty()
		if not land.is_empty():
			rect = land.rect
			buyout = land.buyout
			total += land.price
	if area > 0.0 and rect.is_empty() and h.spare < area:
		total *= Balance.HOSPITAL_BUILD_UP_COST
	var down := total * (Balance.HOSPITAL_DOWN_PAYMENT + Balance.HOSPITAL_DOWN_PAYMENT_CAUTION * float(a.caution))
	return {"total": total, "down": down, "rect": rect, "buyout": buyout, "price": land.get("price", 0.0)}


## Land right next to the hospital for `area` square metres: a strip behind
## it, or beside it (the side it was built facing first). Open land comes
## first; a strip with homes or shops on it is bought out only with the
## player's say-so (a permit). Roads, farms, companies, reserves, water,
## steep slopes and other services are never touched. {rect, buyout,
## price}, or {} if boxed in.
func find_land(sim: CitySim, id: int, area: float) -> Dictionary:
	var h: Dictionary = hubs[id]
	var w: float = h.x1 - h.x0
	var dw: float = area / h.depth
	var tries := [[h.x0, h.x1, h.depth, h.depth + area / w], [h.x0 - dw, h.x0, 0.0, h.depth],
		[h.x1, h.x1 + dw, 0.0, h.depth]]
	if id % 2 == 1:
		tries = [tries[0], tries[2], tries[1]]
	var with_homes := {}
	for r in tries:
		var land := _land_at(sim, id, r.map(func(v): return snappedf(v, 0.25)))  # exact in binary: saves round-trip
		if land.is_empty():
			continue
		if land.buyout.is_empty():
			return land
		if with_homes.is_empty():
			with_homes = land
	if not with_homes.is_empty() and sim.permits.can_file(sim, PERMIT_KIND, id):
		return with_homes
	return {}


## A strip the hospital could take: {rect, buyout, price}, or {} if
## something it may never touch is on it.
func _land_at(sim: CitySim, id: int, r: Array) -> Dictionary:
	if float(r[1]) - float(r[0]) < 4.0 or float(r[3]) - float(r[2]) < 4.0:
		return {}
	var h: Dictionary = hubs[id]
	var poly := rect_poly(h, r, 0.5)
	if Services.road_clash(sim.network, poly) or _blocked(sim, id, poly):
		return {}
	# Lots it reaches into are taken whole, so no house is left half under
	# a hospital wing: the strip stretches to cover them (never inward).
	var keys := sim.lots.keys()
	keys.sort()
	var touched := []
	var out := r.duplicate()
	for key in keys:
		if Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			continue
		touched.append(key)
		for c in sim.lots[key].corners:
			var v: Vector3 = Vector3(c.x, 0.0, c.y) - h.front
			out[0] = minf(out[0], v.dot(h.side))
			out[1] = maxf(out[1], v.dot(h.side))
			out[3] = maxf(out[3], -v.dot(h.dir))
	if not touched.is_empty():
		if r[2] >= float(h.depth) - 0.01:
			out[2] = r[2]  # behind: starts at the back wall
		elif r[1] <= float(h.x0) + 0.01:
			out[1] = r[1]  # to the left: ends at its side
		else:
			out[0] = r[0]
		out[2] = maxf(out[2], 0.0)
		out = out.map(func(v): return snappedf(v, 0.25))
		poly = rect_poly(h, out, 0.5)
		if Services.road_clash(sim.network, poly) or _blocked(sim, id, poly):
			return {}
	var buyout := []
	var price := 0.0
	for key in touched:
		if not sim.buildings.has(key):
			continue
		var bd: Dictionary = sim.buildings[key]
		buyout.append(key)
		price += Balance.VALUE_PER_PLACE[int(bd.zone)] * int(bd.cap) * Balance.HOSPITAL_BUYOUT_PREMIUM
	return {"rect": out, "buyout": buyout, "price": price}


func _blocked(sim: CitySim, id: int, poly: PackedVector2Array) -> bool:
	for other in sim.services.buildings:
		if other != id and not Geometry2D.intersect_polygons(poly, sim.services.footprint(other)).is_empty():
			return true
	var pts := Array(poly)
	var mid := Vector2.ZERO
	for p in poly:
		mid += p
	pts.append(mid / poly.size())
	for i in poly.size():
		pts.append((poly[i] + poly[(i + 1) % poly.size()]) * 0.5)
	for q in pts:
		var p := Vector3(q.x, 0.0, q.y)
		if Capital.owner_of(sim, p) != "" or sim.reserves.kind_at(p) != "" \
				or sim.hubs.covers(p) or sim.warehouses.covers(p) or sim.parks.covers(p) or sim.education.covers(p) \
				or not sim.land_ok(p):
			return true
	return false


func _build(sim: CitySim, id: int, key: String, cost: Dictionary) -> void:
	var h: Dictionary = hubs[id]
	var t: Dictionary = TREE[key]
	var rect: Array = cost.rect
	if rect.is_empty() and float(t.area) > 0.0 and h.spare >= float(t.area):
		h.spare -= float(t.area)  # on ground the parking garage freed
	h.pieces.append({"key": key, "rect": rect})
	h.built.append(key)
	var lead: Dictionary = h.leader
	h.why = "%s opened the %s%s." % [lead.name, str(t.name).to_lower(), (": " + str(t.note)) if t.has("note") else ""]
	h.note = ""
	if key == "garage":
		h.spare += Balance.HOSPITAL_GARAGE_FREES
	if t.has("level"):
		h.level = int(t.level)
	if not rect.is_empty():
		_fit(sim, id)
		sim.land_taken(rect_poly(h, rect))


## Closes the newest building when the hospital can't pay its way.
func _close_newest(sim: CitySim, id: int) -> void:
	var h: Dictionary = hubs[id]
	var last: Dictionary = h.pieces.pop_back()
	h.built.erase(last.key)
	var t: Dictionary = TREE[last.key]
	if t.has("level"):
		h.level = int(t.level) - 1
	if last.key == "garage":
		h.spare = maxf(0.0, h.spare - Balance.HOSPITAL_GARAGE_FREES)
	h.savings = 0.0
	h.streak = 0
	h.note = "Too big for the town: closed the %s." % t.name.to_lower()
	_fit(sim, id)
	sim.land_taken(PackedVector2Array())


## Sizes the service building to the campus: the first footprint plus every
## strip added since.
func _fit(sim: CitySim, id: int) -> void:
	var h: Dictionary = hubs[id]
	var b: Dictionary = sim.services.buildings[id]
	var first: Vector2 = Services.KINDS[Services.Kind.HOSPITAL].size
	var x0 := -first.x * 0.5
	var x1 := first.x * 0.5
	var depth := first.y
	for p in h.pieces:
		if not p.rect.is_empty():
			x0 = minf(x0, p.rect[0])
			x1 = maxf(x1, p.rect[1])
			depth = maxf(depth, p.rect[3])
	h.x0 = x0
	h.x1 = x1
	h.depth = depth
	b.pos = h.front + h.side * (x0 + x1) * 0.5 - h.dir * depth * 0.5
	if is_equal_approx(x1 - x0, first.x) and is_equal_approx(depth, first.y):
		b.erase("size")
	else:
		b.size = Vector2(x1 - x0, depth)


## A rect in the hospital's frame as a ground polygon, shrunk by `inset`.
static func rect_poly(h: Dictionary, r: Array, inset := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in [[r[0] + inset, r[2] + inset], [r[1] - inset, r[2] + inset], [r[1] - inset, r[3] - inset],
			[r[0] + inset, r[3] - inset]]:
		var p: Vector3 = h.front + h.side * c[0] - h.dir * c[1]
		out.append(Vector2(p.x, p.z))
	return out


func has_piece(id: int, key: String) -> bool:
	for p in hubs[id].pieces:
		if p.key == key:
			return true
	return false


# --- What the hospital means for the town -----------------------------------

## The hospital's monthly surplus: what it keeps per person it serves (and
## per patient from the region), less its running costs at its size.
func monthly_net(sim: CitySim, id: int) -> float:
	var h: Dictionary = hubs[id]
	var centers := Agency.effect(h, NODES, "center+")
	var share := Balance.HOSPITAL_REGION_SHARE + Balance.HOSPITAL_REGION_SHARE_PER_CENTER * centers
	return (covered_pop(sim, id) + regional_pop(sim) * share) * Balance.HOSPITAL_NET_PER_PERSON \
		- Balance.HOSPITAL_OVERHEAD[int(h.level)]


## People living in homes this hospital's ambulances reach.
func covered_pop(sim: CitySim, id: int) -> int:
	var dist: Dictionary = sim.services.reach_by_kind.get(Services.Kind.HOSPITAL, {})
	if dist.is_empty():
		return 0
	var n := 0
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if b.zone == ZoneMap.Zone.RESIDENTIAL and sim.services.served.get(key, {}).get(Services.Kind.HOSPITAL, false):
			n += int(b.occ)
	# Two hospitals split the town between them.
	var count := 0
	for other in hubs:
		count += 1
	return n / maxi(count, 1)


## People in the region who could come here for care: the countryside down
## each county highway, plus the neighboring towns.
func regional_pop(sim: CitySim) -> int:
	return Balance.HOSPITAL_COUNTY_POP * sim.region_links.size() + region_pop


## How much this town's hospitals lift care in neighboring towns.
func care_offered() -> float:
	var total := 0.0
	for id in hubs:
		total += Agency.effect(hubs[id], NODES, "region_care+")
	return minf(total, 0.3)


## Share of homes near a school, 0 to 1.
static func school_share(sim: CitySim) -> float:
	var homes := 0
	var near := 0
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			homes += 1
			if sim.services.served.get(key, {}).get(Services.Kind.SCHOOL, false):
				near += 1
	return 0.0 if homes == 0 else float(near) / homes


## How educated the town's people are, 0 to 1: its schools and the local
## college graduates the leaders are hired from, plus a nursing school or
## teaching hospital.
func town_education(sim: CitySim) -> float:
	var e := 0.5 * school_share(sim) + 0.5 * sim.education.leader_education(sim.stats.workers)
	for id in hubs:
		e += Agency.effect(hubs[id], NODES, "education+")
	return clampf(e, 0.0, 1.0)


## Share of the hospital's jobs filled (the rest commute in from the
## region): an educated town staffs it, a nursing school trains more.
func staffing(sim: CitySim, id: int) -> float:
	var s := 0.55 + 0.45 * town_education(sim)
	s += Agency.effect(hubs[id], NODES, "staffing+")
	return clampf(s, 0.0, 1.0)


## Staff the hospital employs at its size.
func hospital_jobs(id: int) -> int:
	var h: Dictionary = hubs[id]
	return int(LEVELS[int(h.level)].jobs) + roundi(Agency.effect(h, NODES, "jobs+"))


## Jobs in healthcare that local people hold.
func jobs(sim: CitySim) -> int:
	var n := 0
	for id in sim.services.buildings:
		match sim.services.buildings[id].kind:
			Services.Kind.NURSING_HOME: n += Balance.NURSING_HOME_JOBS
			Services.Kind.DAYCARE: n += Balance.DAYCARE_JOBS
	for id in hubs:
		n += roundi(hospital_jobs(id) * staffing(sim, id))
	return n


## How well cared for the town's homes are, 0 to 1: a hospital (or at
## least a clinic), a nursing home and a daycare in reach, plus what the
## neighbors' helipads and specialty centers add.
func care(sim: CitySim) -> float:
	var homes := 0
	var total := 0.0
	for key in sim.buildings:
		if sim.buildings[key].zone != ZoneMap.Zone.RESIDENTIAL:
			continue
		homes += 1
		total += care_of(sim.services.served.get(key, {}))
	if homes == 0:
		return 0.0
	return clampf(total / homes + region_care, 0.0, 1.0)


## One home's care, 0 to 1, from its row in Services.served.
static func care_of(s: Dictionary) -> float:
	var health := 1.0 if s.get(Services.Kind.HOSPITAL, false) else (0.6 if s.get(Services.Kind.CLINIC, false) else 0.0)
	return 0.5 * health + 0.25 * (1.0 if s.get(Services.Kind.NURSING_HOME, false) else 0.0) \
		+ 0.25 * (1.0 if s.get(Services.Kind.DAYCARE, false) else 0.0)


## How much good care lifts the want for homes (people stay, families come).
## `care_now` is care(sim) when the caller already has it.
func demand_shift(sim: CitySim, care_now := -1.0) -> float:
	var shift := Balance.CARE_DEMAND * (care(sim) if care_now < 0.0 else care_now)
	for id in hubs:
		if has_piece(id, "maternity"):
			shift += Balance.CARE_MATERNITY
			break
	return shift


func _town_has(sim: CitySim, kind: int) -> bool:
	for id in sim.services.buildings:
		if sim.services.buildings[id].kind == kind:
			return true
	return false


# --- Ambulances --------------------------------------------------------------

func ambulances(id: int) -> int:
	return int(LEVELS[int(hubs[id].level)].ambulances) + roundi(Agency.effect(hubs[id], NODES, "ambulances+"))


## Ambulances out on calls (driving, or with a patient).
func busy(id: int) -> int:
	var n := 0
	for t in trips:
		if int(trips[t].hub) == id:
			n += 1
	for crew in on_scene:
		if int(crew.hub) == id:
			n += 1
	return n


## Someone in town calls 911, at the real US rate per resident.
func _roll_call(sim: CitySim) -> void:
	var pop: int = sim.stats.population
	if pop == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, sim.tick_count, "ems"])
	if rng.randf() >= pop * Balance.EMS_CALLS_PER_PERSON_YEAR * CALL_EVERY / float(TICKS_PER_YEAR):
		return
	var scene := _scene(sim, rng)
	if scene.is_empty():
		return
	var patient: String = FIRST[rng.randi() % FIRST.size()] + " " + LAST[rng.randi() % LAST.size()]
	var call: String = CALLS[rng.randi() % CALLS.size()]
	# Smoke: a home over the smoke line calls more, often for breathing trouble.
	if str(scene.ref).begins_with("lot:") and sim.pollution.breathing_call(sim, str(scene.ref).substr(4), rng.randf()):
		call = "trouble breathing"
	# The nearest hospital with an ambulance in the bay answers.
	var at := Vector3(scene.pos[0], 0.0, scene.pos[1])
	var best := -1
	var ids := hubs.keys()
	ids.sort()
	for id in ids:
		if busy(id) < ambulances(id) and (best == -1 or _door(sim, id).distance_to(at) < _door(sim, best).distance_to(at)):
			best = id
	var from := {}
	if best != -1:
		from = {"ref": "hospital:%d" % best, "pos": _xz(_door(sim, best))}
	else:
		from = _county(sim, at)
	if from.is_empty():
		return
	var trip: int = sim.traffic.dispatch(from, scene, "medical", {"good": "patient care", "call": call, "patient": patient})
	if trip == -1:
		return
	trips[trip] = {"hub": best, "stage": "out", "scene": scene, "from": from, "call": call, "patient": patient,
		"t0": sim.tick_count}
	if best == -1:
		county_calls += 1
	else:
		hubs[best].calls += 1


## Where the call comes from: a home, or now and then the nursing home.
func _scene(sim: CitySim, rng: RandomNumberGenerator) -> Dictionary:
	var homes := []
	var buildings: Dictionary = sim.buildings
	var lots: Dictionary = sim.lots
	for key in sim.ledger().by_zone.get(ZoneMap.Zone.RESIDENTIAL, []):  # sorted
		if int(buildings[key].occ) > 0 and lots.has(key):
			homes.append(key)
	var care_homes := []
	for id in sim.services.buildings:
		if sim.services.buildings[id].kind == Services.Kind.NURSING_HOME:
			care_homes.append(id)
	care_homes.sort()
	if not care_homes.is_empty() and rng.randf() < 0.25:
		var id: int = care_homes[rng.randi() % care_homes.size()]
		var b: Dictionary = sim.services.buildings[id]
		return {"ref": "service:%d" % id, "pos": _xz(b.pos + b.dir * Services.size_of(b).y * 0.5)}
	if homes.is_empty():
		return {}
	# Homes in heavy smoke call more often (Pollution.call_weight). Each
	# home's weight is read once, and added and taken off in the same order.
	var total := 0.0
	var weights := PackedFloat64Array()
	weights.resize(homes.size())
	var smoke: Dictionary = sim.pollution.lots
	for i in homes.size():
		var k: String = homes[i]
		var w: float = 1.0 if not smoke.has(k) else sim.pollution.call_weight(k)
		weights[i] = w
		total += w
	var pick := rng.randf() * total
	var key: String = homes[-1]
	for i in homes.size():
		pick -= weights[i]
		if pick < 0.0:
			key = homes[i]
			break
	return {"ref": "lot:" + key, "pos": _xz(sim.lots[key].front)}


func _arrive(sim: CitySim, trip: int) -> void:
	var t: Dictionary = trips[trip]
	trips.erase(trip)
	var hub := int(t.hub)
	if t.stage == "out":
		if hubs.has(hub):
			hubs[hub].resp_sum += sim.tick_count - int(t.t0)
			hubs[hub].resp_n += 1
		on_scene.append({"hub": hub, "scene": t.scene, "home": t.from, "call": t.call, "patient": t.patient,
			"t0": t.t0, "until": sim.tick_count + Balance.EMS_ON_SCENE_MINUTES})
	elif hubs.has(hub):
		hubs[hub].treated += 1


## The crew has the patient aboard and drives back to the hospital (or the
## county ambulance back out to the highway). Waits if there's no way yet.
func _head_back(sim: CitySim, crew: Dictionary) -> void:
	var hub := int(crew.hub)
	var home: Dictionary = crew.home
	if hubs.has(hub):
		home = {"ref": "hospital:%d" % hub, "pos": _xz(_door(sim, hub))}
	var trip: int = sim.traffic.dispatch(crew.scene, home, "medical",
		{"good": "a patient", "call": crew.call, "patient": crew.patient})
	if trip == -1:
		crew.until = sim.tick_count + CALL_EVERY
		return
	on_scene.erase(crew)
	trips[trip] = {"hub": hub, "stage": "back", "scene": crew.scene, "from": home, "call": crew.call,
		"patient": crew.patient, "t0": crew.t0}


## The hospital's ambulance bay, at the front of its campus.
func _door(sim: CitySim, id: int) -> Vector3:
	var b: Dictionary = sim.services.buildings[id]
	return b.pos + b.dir * Services.size_of(b).y * 0.5


## The county's ambulance, coming in by the nearest region link.
func _county(sim: CitySim, near: Vector3) -> Dictionary:
	var best := -1
	for n in sim.region_links:
		if sim.network.nodes.has(n) and (best == -1 or sim.network.nodes[n].distance_to(near) < sim.network.nodes[best].distance_to(near)):
			best = n
	if best == -1:
		return {}
	return {"ref": "edge", "pos": _xz(sim.network.nodes[best])}


## Average minutes from a call to the ambulance's arrival, or -1.
func response_minutes(id: int) -> float:
	var h: Dictionary = hubs[id]
	return -1.0 if int(h.resp_n) == 0 else float(h.resp_sum) / int(h.resp_n) * CitySim.MINUTES_PER_TICK


static func _xz(p: Vector3) -> Array:
	# Rounded so the value reads back exactly from a save's text.
	return [roundf(p.x * 100.0) / 100.0, roundf(p.z * 100.0) / 100.0]


# --- Saving ------------------------------------------------------------------

func to_dict() -> Dictionary:
	var hs := {}
	for id in hubs:
		var h: Dictionary = hubs[id].duplicate(true)
		for k in ["front", "side", "dir"]:
			h[k] = [h[k].x, h[k].z]
		hs[str(id)] = h
	var ts := {}
	for id in trips:
		ts[str(id)] = trips[id]
	return {"hubs": hs, "trips": ts, "on_scene": on_scene, "county_calls": county_calls}


func from_dict(d: Dictionary) -> void:
	hubs.clear()
	for k in d.get("hubs", {}):
		var h: Dictionary = d.hubs[k].duplicate(true)
		for v in ["front", "side", "dir"]:
			h[v] = Vector3(float(h[v][0]), 0.0, float(h[v][1]))
		for v in ["level", "streak", "calls", "treated", "resp_sum", "resp_n"]:
			h[v] = int(h[v])
		h.leader.hired = int(h.leader.hired)
		hubs[int(k)] = h
	trips.clear()
	for k in d.get("trips", {}):
		trips[int(k)] = d.trips[k]
		for v in ["hub", "t0"]:
			trips[int(k)][v] = int(trips[int(k)][v])
	on_scene = d.get("on_scene", []).duplicate(true)
	for crew in on_scene:
		for v in ["hub", "t0", "until"]:
			crew[v] = int(crew[v])
	county_calls = int(d.get("county_calls", 0))
