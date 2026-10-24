class_name Rail
extends RefCounted
## Railroads the way Brawn asked: the player places a rail depot, and the
## depot's leader runs it as a business. The leader is shaped by the town
## around it (its schooling, its industry), plans real track out to the
## region and to the companies worth serving, asks the town's permission
## before laying any of it, and keeps the railroad in business on its own
## money. The player's levers are the land (where the depot goes) and money
## (a monthly subsidy); everything else the railroad decides itself.
##
## - Track follows US rules (see RailPlanner): AREMA curves and grades, and
##   grade crossings only nearly square, away from junctions, never across a
##   highway. Crossing gates come down 20 seconds or more before a train
##   arrives, as FRA rule 49 CFR 234.225 requires.
## - Every train is a real trip and never vanishes: a local freight runs
##   out to a company's siding, picks up its loaded cars, brings them back
##   to the yard, and takes them out to the region; a passenger train runs
##   to the next town and back. Trains leave the map only at the region end
##   of the main line, and come back.
## - Track is never laid through anything the player built. New track,
##   crossing a road, or taking an empty zoned lot needs a permit, and a
##   request nobody answers is shelved, never forced.
##
## Plain data, deterministic, stepped by CitySim.

## The yard: tracks this long between the ladders, 15 ft (4.6 m) apart.
const YARD_LEN := 260.0
const YARD_TRACKS := 3
const TRACK_GAP := 4.6
## Ladder (turnouts) at each end of the yard.
const LADDER := 40.0
## Depth of the yard from the road side: station, platform, three tracks.
const YARD_DEPTH := 40.0
## The station's front sits this far back from the road's edge.
const SETBACK := 4.0
## Depth along the depot axis of each part, from the road side: station
## building 0-12 m, platform 12-16 m, then the tracks.
const TRACK_V := [18.0, 22.6, 27.2]
## Track runs on past the region link this far before trains leave the map.
const REGION_RUN := 900.0
## The main line ends this far to the side of the county highway's link.
const LINK_OFFSET := 70.0
## Farthest a depot reaches for a company to serve.
const SERVE_REACH := 4500.0
## Speed limits, m/s: yard 10 mph (restricted speed), FRA class 2 industry
## track 25 mph, class 3 main line 40 mph freight, 60 mph passenger.
const SPEED := {"yard": 4.5, "spur": 11.2, "main": 17.9, "region": 17.9}
const PAX_MAIN := 26.8
## Unbalanced superelevation the curve speeds allow (3 in, FRA).
const UNBALANCE_IN := 3.0
## Cars a local freight takes at most (yard tracks hold about 12).
const MAX_CARS := 12
## Ticks a crew spends at a siding coupling cars, and dwelling at the station.
const LOAD_TICKS := 90
const DWELL_TICKS := 60
## Gate warning, seconds before the train reaches the crossing (FRA minimum 20).
const GATE_WARNING := 25.0
## Rolling stock: length (m), and what it carries.
const STOCK := {
	"sd70": {"len": 22.6, "name": "SD70 diesel"},
	"gp38": {"len": 18.0, "name": "GP38 diesel"},
	"p42": {"len": 21.0, "name": "P42 diesel"},
	"tank": {"len": 18.0, "cargo": "crude oil"},
	"hopper": {"len": 16.5, "cargo": "ore"},
	"flat": {"len": 22.0, "cargo": "logs"},
	"bilevel": {"len": 25.9, "cargo": "passengers"},
	"covered": {"len": 18.0, "cargo": "grain"},
}
const CAR_FOR := {"crude oil": "tank", "ore": "hopper", "logs": "flat", "grain": "covered"}
const DECIDE_EVERY := Balance.RAIL_DECIDE_EVERY
## The place tool's kind for a rail depot (ServiceTool, next to Mail.TOOL_KIND).
const TOOL_KIND := 120
const TICKS_PER_DAY := 24 * CitySim.TICKS_PER_HOUR

const FIRST := ["Ruth", "Walt", "June", "Earl", "Marge", "Dale", "Lois", "Gene", "Opal", "Vern", "Irene",
	"Clyde", "Darlene", "Floyd", "Hazel", "Roy", "Bev", "Merle", "Joan", "Lyle", "Doris", "Glen", "Faye", "Howard"]
const LAST := ["Hale", "Lindqvist", "Brandt", "Osterhaus", "McCready", "Pruitt", "Vogel", "Dunbar", "Kessler",
	"Ainsworth", "Bauer", "Tolliver", "Hartke", "Sowders", "Wampler", "Ellis", "Greenwell", "Kemper"]
## The depot's development tree (Agency format), shown to Brawn 2026-10-22.
## What opens depends on the leader (schooling, money), the town (people,
## farms, factories) and the region (what neighbouring towns buy and make).
## Effects: "rate*" freight earnings per car, "run*" running costs,
## "riders*" and "fare*" passengers, "pax_every*" time between passenger
## trains, "grain+" serves the town's grain elevator, "jobs+".
const TREE := [
	{"id": "team_track", "name": "Team track", "cost": 150_000, "needs": {},
		"effects": {"rate*": 0.08, "jobs+": 3}, "note": "local businesses load their own cars by truck"},
	{"id": "engine_house", "name": "Engine house", "cost": 400_000, "requires": ["team_track"],
		"needs": {"profit": 60_000}, "effects": {"run*": -0.12, "jobs+": 6}, "note": "engines are serviced at home"},
	{"id": "grain_spur", "name": "Grain elevator spur", "cost": 250_000, "requires": ["team_track"],
		"needs": {"local:farm": 2}, "effects": {"grain+": 1.0, "jobs+": 2},
		"note": "hopper cars load at the co-op elevator"},
	{"id": "station", "name": "Station with a canopy", "cost": 300_000, "needs": {"population": 1500},
		"effects": {"riders*": 0.2, "jobs+": 3}, "note": "riders wait out of the weather"},
	{"id": "car_shop", "name": "Car repair shop", "cost": 800_000, "requires": ["engine_house"],
		"needs": {"leader_edu": 0.4}, "effects": {"run*": -0.1, "jobs+": 25}},
	{"id": "intercity", "name": "Intercity stop", "cost": 1_200_000, "requires": ["station"],
		"needs": {"population": 4000, "link": 1}, "effects": {"riders*": 0.4, "fare*": 0.25, "jobs+": 6},
		"note": "trains from across the state stop here"},
	{"id": "commuter", "name": "Commuter trains", "cost": 1_500_000, "requires": ["intercity"],
		"needs": {"leader_edu": 0.5, "population": 8000}, "effects": {"pax_every*": -0.5, "riders*": 0.3, "jobs+": 10},
		"note": "trains every few hours to the next towns"},
	{"id": "unit_loop", "name": "Unit-train loop", "cost": 4_000_000, "requires": ["grain_spur"],
		"needs": {"leader_edu": 0.7, "profit": 600_000}, "effects": {"rate*": 0.2, "jobs+": 8},
		"note": "whole 100-car trains of grain at a lower cost a car"},
	{"id": "intermodal", "name": "Intermodal container yard", "cost": 3_000_000, "requires": ["team_track"],
		"needs": {"leader_edu": 0.6, "region_buys:goods": 1, "link": 1}, "effects": {"rate*": 0.3, "jobs+": 30},
		"note": "a neighbouring town buys the factories' goods by the container"},
	{"id": "interchange", "name": "Interchange yard", "cost": 2_000_000, "requires": ["engine_house"],
		"needs": {"link": 1, "region_makes:goods": 1}, "effects": {"rate*": 0.15, "jobs+": 12},
		"note": "swaps cars with the neighbouring railroad and shares the haul"},
	{"id": "classification", "name": "Classification yard", "cost": 6_000_000, "requires": ["interchange"],
		"needs": {"leader_edu": 0.8, "profit": 1_500_000}, "effects": {"rate*": 0.2, "run*": -0.1, "jobs+": 60},
		"note": "sorts the whole region's cars"},
]

const LINE_NAMES := ["Valley Railroad", "& Western", "Short Line", "Southern Railway", "Central Railroad"]

## Depots: id -> {pos, dir (toward the road), axis (along the tracks),
## name, leader {name, edu, ambition, caution} (Agency), built (its
## development tree, Agency), money, subsidy,
## state ("open" | "closed"), why, ends [node A, node B], yard [piece ids],
## pax (passenger service on), pax_train, freight_train, riders, ledger
## {income, costs} (this month), last {income, costs} (last month),
## debt_days, skip {target ref: tick until}}
var depots := {}
## Lines a leader planned: id -> {depot, kind ("main" | "spur"), target
## {ref, name, pos}, route [Vector3], cost, length, crossings, zoned,
## state ("permit" | "building" | "open" | "denied" | "shelved"), permit
## (request id with sim.permits, or -1), asked (tick), built (m),
## pieces [ids], start {piece, s} (a turnout off the main line) or node,
## loads (truck loads waiting at the siding), cars, waiting_since}
var lines := {}
var nodes := {}   # id -> Vector3
## Pieces of track: id -> {a, b, pts [Vector3], kind, depot, line, built (m)}
var pieces := {}
## Trains: id -> see _new_train.
var trains := {}
## Ends of track that lead on to the region.
var region_nodes := {}
## Grade crossings: [{seg, pos (Vector3), piece, s, closed}]. Traffic reads
## `closed` (gates down: cars stop short of it).
var crossings := []
## Where a road passes under track on a high fill, through a concrete
## underpass instead of across at grade: [{seg, pos, piece, s, fill}].
var underpasses := []
## Pieces held by a train's track warrant: piece -> train id.
var held := {}

## Goes up whenever track or yards change (trees, views).
var version := 0

## Track over water rides this high above it on a bridge (m).
const BRIDGE_CLEAR := 5.5
## A road under track on a fill at least this high (m) goes through an
## underpass: 14.5 ft (4.4 m) clearance (AASHTO) plus the deck.
const UNDERPASS_FILL := 5.5

var _next := {"depot": 1, "line": 1, "node": 1, "piece": 1, "train": 1}
var _cum := {}        # piece -> [cumulative metres at each point]
var _lim := {}        # piece -> [speed limit at each point, m/s]
var _cover := {}      # 10 m cell -> true where built track lies
var _dirty := true    # pieces changed: rebuild lengths, cover and crossings
var _roads_dirty := true
var _filing_kind := "spur"


# --- The player's commands ---------------------------------------------------

## Where a depot goes when placed beside the road nearest `hit`: [centre,
## dir toward the road, axis along the road], or [] if no road is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := network.find_segment_near(hit, 120.0, 1.0)
	if near.is_empty() or not RoadStyle.TYPES[network.segments[near.seg].type].lots:
		return []
	var c := network.curve_of(near.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	tan.y = 0.0
	tan = tan.normalized()
	var normal := Vector3(-tan.z, 0.0, tan.x)
	var p: Vector3 = near.point
	if (hit - p).dot(normal) < 0.0:
		normal = -normal
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * (front + YARD_DEPTH * 0.5), -normal, tan]


## The yard's outline (ladders included), on the ground.
static func yard_corners(pos: Vector3, dir: Vector3, axis: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	var half := YARD_LEN * 0.5 + LADDER
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + axis * half * k.x + dir * YARD_DEPTH * 0.5 * k.y
		out.append(Vector2(p.x, p.z))
	return out


func yard_poly(id: int) -> PackedVector2Array:
	var d: Dictionary = depots[id]
	return yard_corners(d.pos, d.dir, d.axis)


## Why a depot can't go here, or "" if it can.
func site_problem(sim: CitySim, pos: Vector3, dir: Vector3, axis: Vector3) -> String:
	var poly := yard_corners(pos, dir, axis)
	if Services.road_clash(sim.network, poly):
		return "The yard needs %d m of fairly straight road frontage." % int(YARD_LEN + LADDER * 2.0)
	for id in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for id in depots:
		if not Geometry2D.intersect_polygons(poly, yard_poly(id)).is_empty():
			return "Overlaps another depot."
	for key in sim.buildings:
		if sim.lots.has(key) and not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			return "There are buildings in the way. Pick open ground."
	for p in poly:
		var q := Vector3(p.x, 0.0, p.y)
		if Capital.owner_of(sim, q) != "":
			return "That ground belongs to a farm or company."
	for p in [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y)):
		if not sim.land_ok(p, 20.0):
			return "The yard needs dry, fairly level ground."
	if sim.reserves.kind_at(pos) != "":
		return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(pos)]
	return ""


func add_depot(sim: CitySim, pos: Vector3, dir: Vector3, axis: Vector3) -> int:
	var id: int = _next.depot
	_next.depot += 1
	var leader := _make_leader(sim, id, pos)
	var d := {"pos": pos, "dir": dir, "axis": axis, "leader": leader,
		"name": "%s %s" % [leader.name.split(" ")[1], LINE_NAMES[absi(hash([sim.city_seed, id, "line"])) % LINE_NAMES.size()]],
		"money": float(Balance.RAIL_START_CAPITAL), "subsidy": 0, "state": "open",
		"why": "Just opened: %s is surveying for a main line out to the region." % leader.name,
		"ends": [], "yard": [], "pax": false, "pax_train": -1, "freight_train": -1, "riders": 0.0,
		"ledger": {"income": 0.0, "costs": 0.0}, "last": {"income": 0.0, "costs": 0.0},
		"debt_days": 0, "skip": {}, "opened": sim.tick_count, "built": []}
	depots[id] = d
	_build_yard(id)
	return id


## Removes a depot with all its track and trains (the player bulldozed it).
func remove_depot(sim: CitySim, id: int) -> void:
	for lid in _lines_of(id):
		if int(lines[lid].permit) != -1:
			sim.permits.withdraw(int(lines[lid].permit))
	for pid in pieces.keys():
		if pieces[pid].depot == id:
			pieces.erase(pid)
	for lid in lines.keys():
		if lines[lid].depot == id:
			lines.erase(lid)
	for tid in trains.keys():
		if trains[tid].depot == id:
			trains.erase(tid)
	for pid in held.keys():
		if not pieces.has(pid) or not trains.has(held[pid]):
			held.erase(pid)
	depots.erase(id)
	_prune_nodes()
	_dirty = true


## Hooks the railroad into the town's permit bell: its own pricing for
## routes (grants and company shares) and where each depot stands, so the
## player can pre-approve land around it.
func attach(sim: CitySim) -> void:
	sim.permits.costers["rail"] = func(_s, req: Dictionary, route: Array, hits: Dictionary) -> int:
		if not depots.has(int(req.hub_id)):
			# Not one of ours (another rail hub, or a test): the bell's own pricing.
			return int(req.get("base", 0)) + roundi(Permits.length(route) * float(req.get("per_m", 0))) \
				+ hits.get("roads", []).size() * Permits.PER_CROSSING
		var kind := _filing_kind
		for lid in lines:
			if int(lines[lid].permit) == int(req.id):
				kind = lines[lid].kind
		return price(kind, Permits.length(route), hits.get("roads", []).size())
	sim.permits.locators["rail"] = func(_s, id: int) -> Vector2:
		var d: Dictionary = depots.get(id, {"pos": Vector3.ZERO})
		return Vector2(d.pos.x, d.pos.z)


## One effect of what a depot has built from its tree.
func fx(id: int, key: String) -> float:
	return Agency.effect(depots[id], TREE, key) if depots.has(id) else (1.0 if key.ends_with("*") else 0.0)


## The depot's yearly profit, from last month's books.
func yearly_profit(id: int) -> float:
	var d: Dictionary = depots[id]
	return (float(d.last.income) - float(d.last.costs)) * 12.0


## Jobs at every depot: the yard crew and station staff, plus what the
## tree added.
func jobs() -> int:
	var n := 0
	for id in depots:
		if depots[id].state == "open":
			n += Balance.RAIL_DEPOT_JOBS + int(fx(id, "jobs+"))
	return n


## The leader builds the next thing on the depot's tree it can afford.
func _develop(sim: CitySim, id: int) -> bool:
	var d: Dictionary = depots[id]
	var profit := yearly_profit(id)
	var before: String = d.why
	var node: Dictionary = Agency.develop(sim, d, TREE, d.pos, maxf(profit, 0.0))
	if node.is_empty():
		return false
	if float(node.cost) > d.money - cushion(d.leader):
		d.built.erase(node.id)  # can't pay for it yet after all
		d.why = before
		return false
	d.money -= float(node.cost)
	d.ledger.costs += float(node.cost)
	d.why = "%s built %s%s." % [d.leader.name, str(node.name).to_lower(),
		(": " + str(node.note)) if node.has("note") else ""]
	return true


func set_subsidy(id: int, monthly: int) -> bool:
	if not depots.has(id):
		return false
	depots[id].subsidy = clampi(monthly, 0, Balance.RAIL_MAX_SUBSIDY)
	return true


# --- The leader ---------------------------------------------------------------

## A leader drawn from the town around the depot (Brawn's model): schooling
## follows how much of the town a school covers, ambition how much industry
## there is to serve, and caution the rest of their nature.
func _make_leader(sim: CitySim, id: int, pos: Vector3) -> Dictionary:
	var seed := hash([sim.city_seed, id, int(pos.x), int(pos.z), "leader"])
	var lead: Dictionary = Agency.leader(sim, seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Ambition also follows how much industry there is to serve nearby.
	var industry := 0
	for sid in sim.industry.sites:
		if sim.industry.sites[sid].pos.distance_to(pos) < SERVE_REACH:
			industry += 1
	lead.ambition = snappedf(clampf(0.6 * float(lead.ambition) + 0.1 * industry + 0.2, 0.05, 1.0), 0.01)
	lead.name = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
	return lead


static func education_text(e: float) -> String:
	if e < 0.35:
		return "High school"
	if e < 0.6:
		return "Some college"
	if e < 0.8:
		return "College degree"
	return "Engineering degree"


static func trait_text(l: Dictionary) -> String:
	var bits := []
	bits.append("bold" if l.ambition > 0.65 else ("steady" if l.ambition > 0.35 else "modest"))
	bits.append("careful" if l.caution > 0.6 else ("practical" if l.caution > 0.3 else "risk-taking"))
	return ", ".join(bits)


## Years a leader will wait for new track to pay for itself.
static func payback_limit(l: Dictionary) -> float:
	var lim: Array = Balance.RAIL_PAYBACK_YEARS
	return lerpf(float(lim[1]), float(lim[0]), l.ambition) * (1.0 - 0.35 * l.caution)


## Money a leader keeps in hand after paying for a project.
static func cushion(l: Dictionary) -> float:
	return Balance.RAIL_CUSHION * (0.4 + l.caution)


## How much a leader over-guesses freight (schooling makes better guesses):
## a high-school leader expects about 25% more than really comes.
static func optimism(l: Dictionary) -> float:
	return 1.0 + 0.4 * (0.6 - l.edu)


## Every leader takes a step: watch the permit it asked for, or choose the
## next project worth building, or start (or stop) passenger trains.
func decide(sim: CitySim) -> bool:
	var changed := false
	var ids := depots.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = depots[id]
		if d.state == "closed":
			if d.money >= 0.0:
				d.state = "open"
				d.debt_days = 0
				d.why = "Back in business, thanks to the town's help."
				changed = true
			continue
		var busy := false
		for lid in _lines_of(id):
			var l: Dictionary = lines[lid]
			if l.state == "permit":
				busy = true
				changed = _watch_permit(sim, lid) or changed
			elif l.state == "building":
				busy = true
		changed = _passengers(sim, id) or changed
		if not busy:
			changed = _next_project(sim, id) or changed
		if not busy and sim.tick_count % (DECIDE_EVERY * 4) == 0:
			changed = _develop(sim, id) or changed
	return changed


func _next_project(sim: CitySim, id: int) -> bool:
	var d: Dictionary = depots[id]
	var lead: Dictionary = d.leader
	var main := _main_line(id)
	if main == -1:
		var link := _region_target(sim, d.pos)
		if link.is_empty():
			d.why = "No road out to the region yet, so nowhere for a main line to go."
			return false
		if _skipped(sim, d, "region"):
			return false
		var plan: Dictionary = _plan(sim, id, "main", link)
		if plan.is_empty():
			d.why = "Can't find a buildable main line to the region: houses, farms, highways or steep ground are in the way."
			d.skip["region"] = sim.tick_count + TICKS_PER_DAY * 3
			return true
		if d.money < plan.cost:
			d.why = "Saving up for the main line to the region: $%s, has $%s." % [
				CitySim.money_text(plan.cost), CitySim.money_text(int(d.money))]
			return false
		_propose(sim, id, "main", link, plan,
			"A main line out to the region, so trains can carry the town's goods and people to the rest of the state")
		return true
	if lines[main].state != "open":
		return false
	# Spurs: the company whose freight would pay back its track soonest.
	var best := {}
	var best_years := INF
	var sids := sim.industry.sites.keys()
	sids.sort()
	var tried := 0
	var ranked := []
	for sid in sids:
		var s: Dictionary = sim.industry.sites[sid]
		var ref := "site:%d" % sid
		if s.pos.distance_to(d.pos) > SERVE_REACH or _serves(ref) != -1 or _skipped(sim, d, ref):
			continue
		var cars: float = _cars_per_year(sim, s) * optimism(lead)
		var guess: float = cars * Balance.RAIL_CAR_RATE - s.pos.distance_to(d.pos) * Balance.RAIL_TRACK_UPKEEP_PER_M * 12.0
		ranked.append([-guess, "site", sid])
	# The town's grain elevator, once the tree has a grain spur.
	if fx(id, "grain+") >= 1.0:
		var pids := sim.parks.sites.keys()
		pids.sort()
		for pid in pids:
			var e: Dictionary = sim.parks.sites[pid]
			var ref := "elev:%d" % pid
			if e.kind != "grain_elevator" or e.pos.distance_to(d.pos) > SERVE_REACH or _serves(ref) != -1 \
					or _skipped(sim, d, ref):
				continue
			ranked.append([-grain_cars_per_year(sim, e.pos) * Balance.RAIL_CAR_RATE, "elev", pid])
	ranked.sort()
	for entry in ranked:
		if tried >= 2:
			break  # surveys take time: a couple of candidates a step
		tried += 1
		var target := {}
		var cars := 0.0
		if entry[1] == "elev":
			var e: Dictionary = sim.parks.sites[int(entry[2])]
			target = {"ref": "elev:%d" % int(entry[2]), "name": str(e.name), "pos": e.pos,
				"allow": [sim.parks.footprint(int(entry[2]))]}
			cars = grain_cars_per_year(sim, e.pos) * optimism(lead)
		else:
			var s: Dictionary = sim.industry.sites[int(entry[2])]
			target = {"ref": "site:%d" % int(entry[2]), "name": Industry.KINDS[s.kind].name, "pos": s.pos + s.dir * 12.0,
				"allow": [sim.industry._yard(s)]}
			cars = _cars_per_year(sim, s) * optimism(lead)
		var ref: String = target.ref
		var plan: Dictionary = _plan(sim, id, "spur", target)
		if plan.is_empty():
			d.skip[ref] = sim.tick_count + TICKS_PER_DAY * 6
			continue
		var net: float = cars * Balance.RAIL_CAR_RATE * fx(id, "rate*") - cars / 6.0 * _run_cost(plan.length * 2.0 + _main_length(id) * 2.0) \
			- plan.length * Balance.RAIL_TRACK_UPKEEP_PER_M * 12.0
		if net <= 0.0:
			d.skip[ref] = sim.tick_count + TICKS_PER_DAY * 6
			continue
		var years: float = plan.cost / net
		if years < best_years:
			best_years = years
			best = {"target": target, "plan": plan, "years": years, "cars": cars}
	if best.is_empty():
		if ranked.is_empty() and not d.why.contains("years to pay off"):
			d.why = "Main line open. No company within %d km to serve yet." % int(SERVE_REACH / 1000.0)
		return false
	var cost: int = best.plan.cost
	# The town's word: "grow" makes a leader bolder.
	var limit := payback_limit(lead) * (1.5 if sim.permits.guidance("rail", id).stance == "grow" else 1.0)
	if best.years > limit:
		d.why = "A spur to the %s would take %.0f years to pay off; %s waits for one that pays within %.0f." % [
			best.target.name.to_lower(), best.years, lead.name.split(" ")[0], limit]
		d.skip[best.target.ref] = sim.tick_count + TICKS_PER_DAY * 4
		return true
	if d.money - cost < cushion(lead):
		d.why = "Saving up for a spur to the %s ($%s)." % [best.target.name.to_lower(), CitySim.money_text(cost)]
		return false
	_propose(sim, id, "spur", best.target, best.plan,
		"A spur to the %s: about %d carloads a year, paying for itself in %s" % [
			best.target.name.to_lower(), roundi(best.cars), "about a year" if best.years < 1.5 else "%d years" % roundi(best.years)])
	return true


## Starts passenger trains when they'd pay (with the town's subsidy), and
## stops them when they lose money month after month.
func _passengers(sim: CitySim, id: int) -> bool:
	var d: Dictionary = depots[id]
	var main := _main_line(id)
	if main == -1 or lines[main].state != "open":
		return false
	var pop: int = sim.stats.population
	var fare_month: float = pop * Balance.RAIL_RIDES_PER_RESIDENT * Balance.RAIL_FARE * optimism(d.leader) \
		* fx(id, "riders*") * fx(id, "fare*")
	var runs := 24.0 / Balance.RAIL_PAX_EVERY_HOURS
	var cost_month: float = Balance.RAIL_TRAINSET_LEASE + runs * _run_cost(_main_length(id) * 2.0, true)
	var gain: float = fare_month + d.subsidy - cost_month
	if not d.pax:
		if pop >= Balance.RAIL_PASSENGER_MIN_POP and gain > 0.0 and d.money > cushion(d.leader):
			d.pax = true
			d.pax_train = _new_train(id, "passenger")
			d.why = "Started passenger trains to the next town: about %s riders a month." % CitySim.money_text(
				roundi(pop * Balance.RAIL_RIDES_PER_RESIDENT))
			return true
		if pop >= Balance.RAIL_PASSENGER_MIN_POP and gain <= 0.0 and d.why.begins_with("Main line open"):
			d.why = "Passenger trains would lose about $%s a month here. A town subsidy that size would start them." \
				% CitySim.money_text(roundi(-gain))
		return false
	if gain < -Balance.RAIL_TRAINSET_LEASE * 0.5 and d.money < cushion(d.leader):
		d.pax = false
		d.why = "Stopped passenger trains: they lost money every month."
		return true
	return false


## How many carloads a year a company would ship (a game day is a month).
static func _cars_per_year(sim: CitySim, s: Dictionary) -> float:
	var k: Dictionary = Balance.INDUSTRY[s.kind]
	var loads := 0.0
	for c in s.pads:
		loads += k.loads * Industry.richness(s, c)
	if s.pads.is_empty():
		loads = k.loads * 3.0  # a new company: what its first pads will make
	return 12.0 * loads / float(Balance.RAIL_LOADS_PER_CAR[Industry.KINDS[s.kind].cargo])


## Hopper cars of grain a year the farms near an elevator would fill.
static func grain_cars_per_year(sim: CitySim, at: Vector3) -> float:
	var bushels := 0.0
	for fid in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[fid]
		if f.pos.distance_to(at) > SERVE_REACH:
			continue
		bushels += f.cells.size() * Farms.ACRES_PER_CELL * float(Balance.FARM_BUSHELS_PER_ACRE.get(f.crop, 150.0)) * 0.8
	return bushels / Balance.GRAIN_TRUCK_BUSHELS / float(Balance.RAIL_LOADS_PER_CAR["grain"])


static func _run_cost(metres: float, pax := false) -> float:
	return metres / 1000.0 * Balance.RAIL_TRAIN_KM_COST * (0.6 if pax else 1.0) + Balance.RAIL_CREW_PER_RUN


# --- Planning and permits ------------------------------------------------------

func _plan(sim: CitySim, id: int, kind: String, target: Dictionary) -> Dictionary:
	var d: Dictionary = depots[id]
	var pl: RailPlanner = RailPlanner.new()
	pl.cost_per_m = Balance.RAIL_TRACK_PER_M[kind]
	# A schooled leader steers around roads: fewer crossings to ask for.
	pl.crossing_penalty = Balance.RAIL_CROSSING_COST * 1.5 * d.leader.edu
	var allow := [yard_poly(id)]
	allow.append_array(target.get("allow", []))
	pl.setup(sim, kind, allow)
	var starts := []
	for i in 2:
		var n: int = d.ends[i]
		var out: Vector3 = d.axis * (-1.0 if i == 0 else 1.0)
		starts.append({"pos": Vector2(nodes[n].x, nodes[n].z), "heading": atan2(out.z, out.x), "node": n})
	if kind == "spur":
		# A turnout off the main line, heading away from the yard.
		for pid in _main_pieces(id):
			var pc: Dictionary = pieces[pid]
			if pc.kind == "region":
				continue
			var pts: Array = pc.pts
			for k in range(10, pts.size() - 10, 16):
				var t: Vector3 = pts[k + 1] - pts[k]
				starts.append({"pos": Vector2(pts[k].x, pts[k].z), "heading": atan2(t.z, t.x),
					"cost": Balance.RAIL_TURNOUT_COST, "piece": pid, "index": k})
	var goal := {"pos": Vector2(target.pos.x, target.pos.z), "tol": 30.0}
	if target.has("heading"):
		goal.heading = target.heading
		goal.tol = 45.0
	var plan := _plan_from(pl, starts, goal, kind == "main")
	if plan.is_empty() and pl.crossing_penalty > 0.0:
		# No way around the roads within the survey: cross them after all.
		pl.crossing_penalty = 0.0
		plan = _plan_from(pl, starts, goal, kind == "main")
	if plan.is_empty():
		return {}
	plan.from = starts[plan.start]
	plan.cost = price(kind, plan.length, plan.crossings.size())
	if plan.from.has("piece"):
		plan.cost += Balance.RAIL_TURNOUT_COST
	return plan


## A main line is surveyed from each end of the yard on its own, so a hemmed-in
## end can't use up the search the open end needs; the cheaper line wins.
func _plan_from(pl: RailPlanner, starts: Array, goal: Dictionary, each: bool) -> Dictionary:
	if not each:
		return pl.plan(starts, goal)
	var best := {}
	for i in starts.size():
		var p: Dictionary = pl.plan([starts[i]], goal)
		if not p.is_empty() and (best.is_empty() or p.cost < best.cost):
			p.start = i
			best = p
	return best


func _propose(sim: CitySim, id: int, kind: String, target: Dictionary, plan: Dictionary, why: String) -> bool:
	var d: Dictionary = depots[id]
	var title := "Main line to the region" if kind == "main" else "Spur to the %s" % str(target.name).to_lower()
	var detail := "%.1f km of track" % (plan.length / 1000.0)
	if not plan.crossings.is_empty():
		detail += ", %d road crossing%s with gates" % [plan.crossings.size(), "" if plan.crossings.size() == 1 else "s"]
	if plan.zoned > 0:
		detail += ", %d empty zoned lot%s" % [plan.zoned, "" if plan.zoned == 1 else "s"]
	_filing_kind = kind
	var pid: int = sim.permits.file(sim, {"hub": "rail", "hub_id": id, "leader": d.leader.name,
		"title": title, "why": "%s (%s.)" % [why, detail], "route": plan.pts, "width": RailPlanner.CLEAR * 2.0,
		"budget": maxi(0, int(d.money - cushion(d.leader)))})
	if pid == -1:
		d.why = "Ready to ask the town about the %s, waiting for a turn at the permit desk." % title.to_lower()
		return false
	var lid: int = _next.line
	_next.line += 1
	var from: Dictionary = plan.from
	var l := {"depot": id, "kind": kind, "target": {"ref": target.ref, "name": target.name,
		"pos": target.pos}, "route": plan.pts, "cost": plan.cost, "length": plan.length,
		"crossings": plan.crossings, "zoned": plan.zoned, "state": "permit", "permit": pid,
		"asked": sim.tick_count, "built": 0.0, "pieces": [], "loads": 0.0, "cars": 0,
		"waiting_since": -1, "why": why}
	if from.has("piece"):
		l.start = {"piece": from.piece, "index": from.index}
	else:
		l.start = {"node": from.node}
	if target.has("heading"):
		l.target.heading = [target.heading.x, target.heading.y]
	lines[lid] = l
	d.why = "Asked the town's permission: " + why
	return true


## Lines waiting for the player's answer: [line ids], oldest first.
func open_requests() -> Array:
	var out := []
	for lid in lines:
		if lines[lid].state == "permit":
			out.append(lid)
	out.sort()
	return out


## Follows the town's answer on the permit bell.
func _watch_permit(sim: CitySim, lid: int) -> bool:
	var l: Dictionary = lines[lid]
	var d: Dictionary = depots[l.depot]
	var pid: int = l.permit
	match sim.permits.state_of(pid):
		Permits.State.APPROVED:
			var req: Dictionary = sim.permits.requests[pid]
			if int(req.edits) > 0 and not _edited(sim, lid, req.route):
				sim.permits.withdraw(pid)
				l.permit = -1
				l.state = "shelved"
				d.skip[l.target.ref] = sim.tick_count + TICKS_PER_DAY * Balance.RAIL_DENIED_DAYS
				return true
			_approve(sim, lid)
			sim.permits.done(pid)
			return true
		Permits.State.DENIED:
			_deny(sim, lid)
			return true
		Permits.State.SHELVED, Permits.State.WITHDRAWN, -1:
			l.state = "shelved"
			l.permit = -1
			d.skip[l.target.ref] = sim.tick_count + TICKS_PER_DAY * Balance.RAIL_DENIED_DAYS
			d.why = "Nobody answered about the %s, so %s shelved it for now." % [
				"main line" if l.kind == "main" else "spur to the " + str(l.target.name).to_lower(), d.leader.name.split(" ")[0]]
			return true
	return false


func _approve(sim: CitySim, lid: int) -> void:
	var l: Dictionary = lines[lid]
	var d: Dictionary = depots[l.depot]
	var a: int
	if l.start.has("piece"):
		if not pieces.has(int(l.start.piece)):
			_deny(sim, lid)
			return
		a = _split(int(l.start.piece), int(l.start.index))
	else:
		a = int(l.start.node)
	var b := _add_node(l.route[-1])
	var pid := _add_piece(a, b, l.route, l.kind, l.depot, lid, 0.0)
	l.pieces = [pid]
	l.state = "building"
	l.permit = -1
	d.why = "Building the %s." % ("main line to the region" if l.kind == "main" else "spur to the " + str(l.target.name).to_lower())
	_dirty = true


func _deny(sim: CitySim, lid: int) -> void:
	var l: Dictionary = lines[lid]
	var d: Dictionary = depots[l.depot]
	l.state = "denied"
	l.permit = -1
	d.skip[l.target.ref] = sim.tick_count + TICKS_PER_DAY * Balance.RAIL_DENIED_DAYS
	d.why = "The town said no to the %s. %s will look at other work." % [
		"main line" if l.kind == "main" else "spur to the " + str(l.target.name).to_lower(), d.leader.name.split(" ")[0]]


## The player redrew the route and approved it: the leader checks it
## against the rules and re-costs it. If it breaks one, the leader lays the
## nearest line that doesn't, through the player's points. False if no
## buildable line comes close.
func _edited(sim: CitySim, lid: int, route: Array) -> bool:
	var l: Dictionary = lines[lid]
	var d: Dictionary = depots[l.depot]
	var pts := []
	for p in route:
		pts.append(p if p is Vector3 else Vector3(float(p[0]), 0.0, float(p[1])))
	if pts.size() < 2:
		return false
	var pl := RailPlanner.new()
	pl.cost_per_m = Balance.RAIL_TRACK_PER_M[l.kind]
	var allow := [yard_poly(l.depot)]
	if str(l.target.ref).begins_with("site:") and sim.industry.sites.has(int(str(l.target.ref).substr(5))):
		allow.append(sim.industry._yard(sim.industry.sites[int(str(l.target.ref).substr(5))]))
	pl.setup(sim, l.kind, allow)
	pts = _dense(pts)
	var bad: String = pl.problem(pts)
	if bad == "":
		var survey: Dictionary = pl.survey(pts)
		l.route = pts
		l.length = RoadNetwork.polyline_length(PackedVector3Array(pts))
		l.crossings = survey.crossings
		l.zoned = survey.zoned
		l.cost = price(l.kind, l.length, survey.crossings.size())
		d.why = "Going the town's way for the %s: $%s." % [
			"main line" if l.kind == "main" else "spur", CitySim.money_text(l.cost)]
		return true
	# The closest line trains can run on, through the player's points.
	var start := {"pos": Vector2(pts[0].x, pts[0].z), "heading": atan2(l.route[1].z - l.route[0].z, l.route[1].x - l.route[0].x)}
	var out := [pts[0]]
	var crossings := []
	var zoned := 0
	var step := maxi(1, pts.size() / 4)
	var marks := []
	for i in range(step, pts.size(), step):
		marks.append(pts[i])
	if marks.is_empty() or marks[-1] != pts[-1]:
		marks.append(pts[-1])
	for m in marks:
		var leg: Dictionary = pl.plan([start], {"pos": Vector2(m.x, m.z), "tol": 40.0})
		if leg.is_empty():
			d.why = "The town's route for the %s can't be built (%s), and no close line works either." % [
				"main line" if l.kind == "main" else "spur", bad.trim_suffix(".").to_lower()]
			return false
		out.append_array(leg.pts.slice(1))
		crossings.append_array(leg.crossings)
		zoned += leg.zoned
		var e: Vector3 = leg.pts[-1]
		var f: Vector3 = leg.pts[-2]
		start = {"pos": Vector2(e.x, e.z), "heading": atan2(e.z - f.z, e.x - f.x)}
	l.route = out
	l.length = RoadNetwork.polyline_length(PackedVector3Array(out))
	l.crossings = crossings
	l.zoned = zoned
	l.cost = price(l.kind, l.length, crossings.size())
	d.why = "Went close to the town's way, adjusted so trains can run on it: %s" % bad
	return true


## What new track costs the railroad: build price and crossings, less the
## grants and (for a spur) the company's share.
static func price(kind: String, length: float, n_crossings: int) -> int:
	var total: float = length * Balance.RAIL_TRACK_PER_M[kind] + n_crossings * Balance.RAIL_CROSSING_COST
	total *= 1.0 - Balance.RAIL_GRANT_SHARE
	if kind == "spur":
		total *= 1.0 - Balance.RAIL_SHIPPER_SHARE
	return roundi(total)


func _skipped(sim: CitySim, d: Dictionary, ref: String) -> bool:
	return int(d.skip.get(ref, -1)) > sim.tick_count


## Where a main line meets the region: beside the county highway's far end,
## heading out along it. {ref, name, pos, heading} or {}.
func _region_target(sim: CitySim, near: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for n in sim.region_links:
		if not sim.network.nodes.has(n) or sim.network.segments_at(n).is_empty():
			continue
		var end: Vector3 = sim.network.nodes[n]
		var seg: Dictionary = sim.network.segments[sim.network.segments_at(n)[0]]
		var out: Vector3 = end - seg.ctrl
		out.y = 0.0
		out = out.normalized()
		var side := Vector3(-out.z, 0.0, out.x)
		for sgn in [1.0, -1.0]:
			var p: Vector3 = end + side * LINK_OFFSET * sgn - out * 60.0
			var dd := p.distance_to(near)
			if dd < best_d - 0.01:
				best_d = dd
				best = {"ref": "region", "name": "the region", "pos": p, "heading": Vector2(out.x, out.z)}
	return best


# --- Building ------------------------------------------------------------------

func _build_yard(id: int) -> void:
	var d: Dictionary = depots[id]
	var half := YARD_LEN * 0.5
	var mid_v: float = TRACK_V[1]
	var a := _add_node(_yard_pt(d, -half - LADDER, mid_v))
	var b := _add_node(_yard_pt(d, half + LADDER, mid_v))
	d.ends = [a, b]
	for i in YARD_TRACKS:
		var pts := []
		var v: float = TRACK_V[i]
		var u := -half - LADDER
		while u <= half + LADDER + 0.01:
			var k := 0.0
			if u < -half:
				k = smoothstep(-half - LADDER, -half, u)
			elif u > half:
				k = smoothstep(half + LADDER, half, u)
			else:
				k = 1.0
			pts.append(_yard_pt(d, u, lerpf(mid_v, v, k)))
			u += 10.0
		pts[-1] = nodes[b]
		var pid := _add_piece(a, b, pts, "yard", id, -1, -1.0)
		d.yard.append(pid)
	_dirty = true


static func _yard_pt(d: Dictionary, u: float, v: float) -> Vector3:
	var away: Vector3 = -d.dir
	return d.pos + d.axis * u + away * (v - YARD_DEPTH * 0.5)


## Crews lay track each game hour, paid as they go from the railroad's money.
func _construct(sim: CitySim) -> void:
	var lids := lines.keys()
	lids.sort()
	for lid in lids:
		var l: Dictionary = lines[lid]
		if l.state != "building":
			continue
		var d: Dictionary = depots[l.depot]
		var pid: int = l.pieces[0]
		var pc: Dictionary = pieces[pid]
		var total: float = _length(pid)
		var rate: float = l.cost / maxf(total, 1.0)
		var m := minf(Balance.RAIL_BUILD_M_PER_DAY / 24.0, total - pc.built)
		if d.money < m * rate:
			d.why = "Out of money: building has stopped until freight or a subsidy pays for more."
			continue
		d.money -= m * rate
		d.ledger.costs += m * rate
		pc.built += m
		l.built = pc.built
		_dirty = true
		if pc.built >= total - 0.01:
			pc.built = -1.0  # complete
			l.built = total
			l.state = "open"
			if l.kind == "main":
				_region_run(l)
				d.why = "The main line to the region is open."
				if d.freight_train == -1:
					d.freight_train = _new_train(l.depot, "freight")
			else:
				d.why = "The spur to the %s is open. Cars load there for the local freight." % l.target.name.to_lower()


func _region_run(l: Dictionary) -> void:
	var end: Vector3 = l.route[-1]
	var h: Array = l.target.get("heading", [1.0, 0.0])
	var out := Vector3(float(h[0]), 0.0, float(h[1])).normalized()
	var prev: Vector3 = l.route[-2]
	var tan := (end - prev).normalized()
	var pts := [end]
	# Ease from the line's last heading onto the highway's, then run on out.
	var p := end
	var dirv := tan
	var s := 10.0
	while s <= REGION_RUN:
		dirv = dirv.slerp(out, 0.08).normalized()
		p += dirv * 10.0
		pts.append(p)
		s += 10.0
	var a: int = pieces[l.pieces[0]].b
	var b := _add_node(pts[-1])
	region_nodes[b] = true
	var pid := _add_piece(a, b, pts, "region", l.depot, -1, -1.0)
	l.pieces.append(pid)


## Splits a piece at a point index for a new turnout. Returns the new node.
func _split(pid: int, index: int) -> int:
	var pc: Dictionary = pieces[pid]
	var pts: Array = pc.pts
	index = clampi(index, 1, pts.size() - 2)
	var n := _add_node(pts[index])
	var tail := pts.slice(index)
	pc.pts = pts.slice(0, index + 1)
	var old_b: int = pc.b
	pc.b = n
	var np := _add_piece(n, old_b, tail, pc.kind, pc.depot, pc.line, -1.0)
	for lid in lines:
		var at: int = lines[lid].pieces.find(pid)
		if at != -1:
			lines[lid].pieces.insert(at + 1, np)
	if held.has(pid):
		held[np] = held[pid]
	for tid in trains:
		for list in [trains[tid].trail, trains[tid].route]:
			for i in list.size():
				if int(list[i][0]) == pid:
					# Trains on it keep their place: the far part is a new piece.
					pass
	_dirty = true
	return n


func _add_node(p: Vector3) -> int:
	var id: int = _next.node
	_next.node += 1
	nodes[id] = _v(_pt(p))
	return id


func _add_piece(a: int, b: int, pts: Array, kind: String, depot: int, line: int, built: float) -> int:
	var id: int = _next.piece
	_next.piece += 1
	var copy := []
	for p in pts:
		copy.append(_v(_pt(p)))  # saved exactly as kept
	copy[0] = nodes[a]
	copy[-1] = nodes[b]
	pieces[id] = {"a": a, "b": b, "pts": copy, "kind": kind, "depot": depot, "line": line, "built": built}
	_dirty = true
	return id


func _prune_nodes() -> void:
	var used := {}
	for pid in pieces:
		used[pieces[pid].a] = true
		used[pieces[pid].b] = true
	for n in nodes.keys():
		if not used.has(n):
			nodes.erase(n)
			region_nodes.erase(n)


# --- Every tick ---------------------------------------------------------------

func tick(sim: CitySim) -> void:
	if depots.is_empty():
		return
	if _dirty:
		_rebuild(sim)
	elif _roads_dirty:
		_find_crossings(sim)
	if sim.tick_count % DECIDE_EVERY == 0 and decide(sim):
		pass
	if sim.tick_count % CitySim.TICKS_PER_HOUR == 0:
		_construct(sim)
		_money(sim)
	if sim.tick_count % Logistics.EVERY == Logistics.EVERY / 2:
		_load_sidings(sim)
	var tids := trains.keys()
	tids.sort()
	for tid in tids:
		_step_train(sim, tid)
	_gates()
	# Cents and millimetres, so a saved railroad picks up exactly where it was.
	for tid in trains:
		trains[tid].s = snappedf(trains[tid].s, 0.0001)
		trains[tid].v = snappedf(trains[tid].v, 0.0001)
	for id in depots:
		var d: Dictionary = depots[id]
		d.money = snappedf(d.money, 0.01)
		d.riders = snappedf(d.riders, 0.01)
		for book in [d.ledger, d.last]:
			for k in book:
				book[k] = snappedf(book[k], 0.01)


## Running costs and the town's subsidy, every game hour (a day is a month).
func _money(sim: CitySim) -> void:
	var ids := depots.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = depots[id]
		var track := 0.0
		for pid in pieces:
			if pieces[pid].depot == id and pieces[pid].built < 0.0 and pieces[pid].kind != "region":
				track += _length(pid)
		var month: float = Balance.RAIL_DEPOT_UPKEEP * fx(id, "run*") + track * Balance.RAIL_TRACK_UPKEEP_PER_M
		if d.pax:
			month += Balance.RAIL_TRAINSET_LEASE
		d.money -= month / 24.0
		d.ledger.costs += month / 24.0
		if d.subsidy > 0:
			var give: float = d.subsidy / 24.0
			sim.economy.money -= roundi(give)
			d.money += give
			d.ledger.income += give
		if sim.tick_count % TICKS_PER_DAY == 0:
			d.last = d.ledger
			d.ledger = {"income": 0.0, "costs": 0.0}
			if d.money < 0.0:
				d.debt_days += 1
				if d.pax:
					d.pax = false
					d.why = "Short of money: stopped passenger trains."
				if d.debt_days >= Balance.RAIL_BANKRUPT_DAYS and d.state == "open":
					d.state = "closed"
					d.why = "Closed: ran out of money. A town subsidy would bring it back."
			else:
				d.debt_days = 0


## Loaded truck loads move from a company's yard onto its siding, unless a
## factory in town wants them (trucks take those).
func _load_sidings(sim: CitySim) -> void:
	var lids := lines.keys()
	lids.sort()
	for lid in lids:
		var l: Dictionary = lines[lid]
		if l.state != "open" or l.kind != "spur":
			continue
		var ref: String = l.target.ref
		if ref.begins_with("elev:"):
			_load_elevator(sim, l)
			continue
		var sid := int(ref.substr(5))
		if not sim.industry.sites.has(sid):
			continue
		var s: Dictionary = sim.industry.sites[sid]
		if not ships_by_rail(sim, ref):
			continue
		var per: float = Balance.RAIL_LOADS_PER_CAR[Industry.KINDS[s.kind].cargo]
		while s.stock >= 1.0 and l.cars < MAX_CARS:
			s.stock -= 1.0
			l.loads += 1.0
			if l.loads >= per:
				l.loads -= per
				l.cars += 1
				if l.waiting_since == -1:
					l.waiting_since = sim.tick_count


## Grain trucks unload at the elevator (a store in Warehouses); what no
## mill in town is waiting for goes into hopper cars on the spur.
func _load_elevator(sim: CitySim, l: Dictionary) -> void:
	var pid := int(str(l.target.ref).substr(5))
	if not sim.parks.sites.has(pid):
		return
	var e: Dictionary = sim.parks.sites[pid]
	if int(l.get("store", -1)) == -1 or not sim.warehouses.buildings.has(int(l.store)):
		l.store = sim.warehouses.add_store(e.pos + e.dir * float(e.size.y) * 0.5, Balance.RAIL_ELEVATOR_LOADS,
			["corn", "soybeans"])
	for key in sim.logistics.need:
		if sim.logistics.need[key] >= 0.5:
			return  # a mill wants it: trucks take it there
	var per: float = Balance.RAIL_LOADS_PER_CAR["grain"]
	while l.cars < MAX_CARS:
		var load := sim.warehouses.take_load(int(l.store), Warehouses.RAW)
		if load.is_empty():
			break
		l.loads += 1.0
		if l.loads >= per:
			l.loads -= per
			l.cars += 1
			if l.waiting_since == -1:
				l.waiting_since = sim.tick_count


## True when this place's loads go by rail (Logistics asks before sending
## a truck): it has an open siding and no factory in town is waiting for
## raw materials.
func ships_by_rail(sim: CitySim, ref: String) -> bool:
	var lid := _serves(ref)
	if lid == -1 or lines[lid].state != "open" or depots[lines[lid].depot].state != "open":
		return false
	if _main_line(lines[lid].depot) == -1 or lines[_main_line(lines[lid].depot)].state != "open":
		return false
	for key in sim.logistics.need:
		if sim.logistics.need[key] >= 0.5:
			return false
	return true


# --- Trains ---------------------------------------------------------------------

## A new train, parked in its depot's yard.
func _new_train(depot: int, kind: String) -> int:
	var d: Dictionary = depots[depot]
	var id: int = _next.train
	_next.train += 1
	var slot: int = d.yard[0] if kind == "passenger" else d.yard[mini(2, d.yard.size() - 1)]
	for pid in d.yard:
		if not held.has(pid) and (kind == "passenger") == (pid == d.yard[0]):
			slot = pid
			break
	var consist := ["p42", "bilevel", "bilevel", "bilevel"] if kind == "passenger" else ["gp38"]
	var t := {"depot": depot, "kind": kind, "consist": consist, "cargo": "", "cars": 0, "riders": 0,
		"state": "parked", "legs": [], "trail": [[slot, 1]], "s": _length(slot) - LADDER - 10.0,
		"route": [], "stop": 0.0, "v": 0.0, "timer": 0, "from": "Yard", "to": "Yard",
		"purpose": "Waiting for work", "number": id, "since": 0}
	trains[id] = t
	held[slot] = id
	return id


func _step_train(sim: CitySim, tid: int) -> void:
	var t: Dictionary = trains[tid]
	var d: Dictionary = depots[t.depot]
	match t.state:
		"parked":
			if d.state != "open" or sim.tick_count % 10 != 0:
				return
			if t.kind == "passenger":
				if not d.pax:
					return
				if sim.tick_count - int(t.since) >= Balance.RAIL_PAX_EVERY_HOURS * fx(t.depot, "pax_every*") * CitySim.TICKS_PER_HOUR:
					t.riders = roundi(d.riders)
					d.riders = 0.0
					var fare: float = t.riders * Balance.RAIL_FARE * fx(t.depot, "fare*")
					d.money += fare
					d.ledger.income += fare
					t.legs = ["region"]
					t.purpose = "Passenger train to the next town: %d riders" % t.riders
					t.to = "The region"
					t.from = d.name + " station"
					t.state = "ready"
				return
			var job := _freight_job(sim, t.depot)
			if job != -1:
				var l: Dictionary = lines[job]
				t.legs = ["siding:%d" % job, "yard", "region"]
				t.purpose = "Local freight: picking up %d %s cars" % [l.cars, STOCK[CAR_FOR[_cargo(sim, l)]].cargo]
				t.from = "Yard"
				t.to = l.target.name + " siding"
				t.cargo = _cargo(sim, l)
				t.job = job
				# Brings empty cars out to swap for the loaded ones.
				t.consist = ["gp38"]
				for i in l.cars:
					t.consist.append(CAR_FOR[t.cargo])
				t.state = "ready"
		"ready", "wait":
			if sim.tick_count % 10 != 0:
				return
			if _start_leg(sim, tid):
				t.state = "run"
			else:
				t.state = "wait"
		"run":
			_drive(sim, tid)
		"load":
			t.timer -= 1
			if t.timer <= 0:
				t.state = "ready"
		"dwell":
			t.timer -= 1
			if t.timer <= 0:
				t.state = "ready" if not t.legs.is_empty() else "parked"
		"away":
			t.timer -= 1
			if t.timer <= 0 and sim.tick_count % 10 == 0:
				_come_back(sim, tid)
	if d.pax and sim.tick_count % CitySim.TICKS_PER_HOUR == 0:
		d.riders += sim.stats.population * Balance.RAIL_RIDES_PER_RESIDENT * fx(t.depot, "riders*") / 24.0


## The siding whose loaded cars should go out next: the fullest one with
## enough cars, or any that has waited too long.
func _freight_job(sim: CitySim, depot: int) -> int:
	var best := -1
	var best_cars := 0
	for lid in _lines_of(depot):
		var l: Dictionary = lines[lid]
		if l.state != "open" or l.kind != "spur" or l.cars == 0:
			continue
		var waited: bool = l.waiting_since != -1 and sim.tick_count - int(l.waiting_since) \
			> Balance.RAIL_TRAIN_MAX_WAIT_DAYS * TICKS_PER_DAY
		if (l.cars >= Balance.RAIL_TRAIN_MIN_CARS or waited) and l.cars > best_cars:
			best = lid
			best_cars = l.cars
	return best


func _cargo(sim: CitySim, l: Dictionary) -> String:
	if str(l.target.ref).begins_with("elev:"):
		return "grain"
	var sid := int(str(l.target.ref).substr(5))
	if sim.industry.sites.has(sid):
		return Industry.KINDS[sim.industry.sites[sid].kind].cargo
	return "ore"


## Plans the next leg and takes a track warrant for all of it, or waits.
func _start_leg(sim: CitySim, tid: int) -> bool:
	var t: Dictionary = trains[tid]
	if t.legs.is_empty():
		t.state = "parked"
		return false
	var goal := _goal(t, str(t.legs[0]))
	if goal.is_empty():
		t.legs.clear()
		t.state = "parked"
		t.purpose = "Waiting for work"
		return false
	var plan: Dictionary = _route_to(t, goal)
	if plan.is_empty():
		_flip(t)
		plan = _route_to(t, goal)
		if plan.is_empty():
			_flip(t)
			return false
	for step in plan.route:
		if held.has(step[0]) and held[step[0]] != tid:
			return false
	for step in plan.route:
		held[step[0]] = tid
	t.route = plan.route
	t.stop = plan.stop
	return true


## Where a leg ends: {pieces: {piece: stop s}}.
func _goal(t: Dictionary, leg: String) -> Dictionary:
	var d: Dictionary = depots[t.depot]
	var out := {}
	if leg == "yard":
		for pid in d.yard:
			if (t.kind == "passenger") != (pid == d.yard[0]) and d.yard.size() > 1:
				continue
			if not held.has(pid) or held[pid] == t.get("id_hint", -2):
				out[pid] = true
		return {"yard": out}
	if leg == "region":
		var main := _main_line(t.depot)
		if main == -1 or lines[main].state != "open":
			return {}
		var rp: int = lines[main].pieces[-1]
		return {"end": rp, "at": "b"}
	if leg.begins_with("siding:"):
		var lid := int(leg.substr(7))
		if not lines.has(lid) or lines[lid].state != "open":
			return {}
		return {"end": lines[lid].pieces[-1], "at": "b", "short": 15.0}
	return {}


## The pieces from the train's head to a goal, never reversing at a turnout,
## and only through turnouts a train can take: [[piece, dir], ...] and where
## on the last piece to stop.
func _route_to(t: Dictionary, goal: Dictionary) -> Dictionary:
	var start: Array = t.trail[0]
	var targets := {}
	if goal.has("yard"):
		for pid in goal.yard:
			targets[pid] = true
	else:
		targets[goal.end] = true
	# Dijkstra over (piece, dir); first the piece the train is on.
	var dist := {}
	var prev := {}
	var heap := []
	var k0 := Vector2i(int(start[0]), int(start[1]))
	dist[k0] = 0.0
	RailPlanner._push(heap, [0.0, k0])
	var found = null
	while not heap.is_empty():
		var top: Array = RailPlanner._pop(heap)
		var k: Vector2i = top[1]
		if top[0] > dist.get(k, INF):
			continue
		if targets.has(k.x) and k != k0:
			found = k
			break
		if targets.has(k.x) and k == k0 and goal.has("end"):
			# Already on the last piece: only if the stop is still ahead.
			var at_end := _length(k.x) if goal.at == "b" else 0.0
			if (at_end - t.s) * k.y > 0.0:
				found = k
				break
		var node: int = pieces[k.x].b if k.y > 0 else pieces[k.x].a
		var away := _away(k.x, node)
		for q in _pieces_at(node):
			if q == k.x or not _complete(q):
				continue
			if _away(q, node).dot(away) > -0.5:
				continue  # that would be a reversal at the turnout
			var nk := Vector2i(q, 1 if pieces[q].a == node else -1)
			var nd: float = top[0] + _length(q)
			if nd < dist.get(nk, INF):
				dist[nk] = nd
				prev[nk] = k
				RailPlanner._push(heap, [nd, nk])
	if found == null:
		return {}
	var route := []
	var k = found
	while k != null:
		route.push_front([k.x, k.y])
		k = prev.get(k, null)
	var last: Array = route[-1]
	var len_last := _length(last[0])
	var stop := 0.0
	if goal.has("yard"):
		# Pull up to the far ladder, leaving the whole train in the yard.
		stop = len_last - LADDER - 10.0 if last[1] > 0 else LADDER + 10.0
	else:
		var short: float = goal.get("short", 2.0)
		stop = len_last - short if last[1] > 0 else short
	return {"route": route, "stop": stop}


## Turns the train around where it stands: the tail becomes the head.
func _flip(t: Dictionary) -> void:
	var tail := _behind(t, train_length(t))
	var trail := []
	for i in range(int(tail.index), -1, -1):
		trail.append([t.trail[i][0], -int(t.trail[i][1])])
	t.trail = trail
	t.s = tail.s
	t.consist.reverse()
	t.consist = t.consist  # the engine now leads from the other end (or shoves)


func _drive(sim: CitySim, tid: int) -> void:
	var t: Dictionary = trains[tid]
	var dt := TrafficSim.DT
	var pax: bool = t.kind == "passenger"
	var acc := 0.5 if pax else 0.18
	var brake := 0.7 if pax else 0.3
	# Distance to the stop, and the speed allowed now and ahead.
	var remaining := 0.0
	var cur: Array = t.route[0]
	var limit := INF
	var ahead := 0.0
	var look := 400.0
	for i in t.route.size():
		var step: Array = t.route[i]
		var pid: int = step[0]
		var dir: int = step[1]
		var from_s: float = t.s if i == 0 else (0.0 if dir > 0 else _length(pid))
		var to_s: float = t.stop if i == t.route.size() - 1 else (_length(pid) if dir > 0 else 0.0)
		var seg := (to_s - from_s) * dir
		remaining += maxf(seg, 0.0)
		# Speed limits along this piece, within the look-ahead.
		var lims: Array = _lim[pid]
		var cum: Array = _cum[pid]
		var n := lims.size()
		for j in n:
			var sj: float = cum[j]
			var dj := (sj - from_s) * dir
			if dj < -12.0 or dj > seg:
				continue
			var reach := ahead + maxf(dj, 0.0)
			if reach > look:
				break
			var lj: float = lims[j]
			if pax and pieces[pid].kind in ["main", "region"]:
				lj = minf(PAX_MAIN, _curve_v(pid, j))
			limit = minf(limit, sqrt(lj * lj + 2.0 * brake * reach))
		ahead += maxf(seg, 0.0)
	# Brake to the stop, creeping the last metre.
	var target := minf(limit, maxf(sqrt(2.0 * brake * maxf(remaining - 1.0, 0.0)), 0.6))
	if t.v < target:
		t.v = minf(target, t.v + acc * dt)
	else:
		t.v = maxf(target, t.v - brake * 2.0 * dt)
	var move: float = minf(t.v * dt, remaining)
	if remaining < 0.3:
		t.v = 0.0
		_arrive(sim, tid)
		return
	_advance(t, move)
	_release(tid)


## Moves the head forward along the route, piece to piece.
func _advance(t: Dictionary, m: float) -> void:
	while m > 0.0:
		var step: Array = t.route[0]
		var pid: int = step[0]
		var dir: int = step[1]
		var end := _length(pid) if dir > 0 else 0.0
		var left: float = (end - t.s) * dir
		if t.route.size() == 1:
			left = (t.stop - t.s) * dir
		if m <= left or t.route.size() == 1:
			t.s += dir * minf(m, maxf(left, 0.0))
			return
		m -= left
		t.route.pop_front()
		var next: Array = t.route[0]
		t.s = 0.0 if next[1] > 0 else _length(next[0])
		t.trail.push_front([next[0], next[1]])
		# Forget pieces the whole train has left.
		var keep: float = (t.s if next[1] > 0 else _length(next[0]) - t.s)
		var need := train_length(t)
		var i := 1
		while i < t.trail.size() and keep < need:
			keep += _length(t.trail[i][0])
			i += 1
		t.trail.resize(i)


## Frees the track warrant on pieces the train has fully left.
func _release(tid: int) -> void:
	var t: Dictionary = trains[tid]
	var mine := {}
	for step in t.trail:
		mine[step[0]] = true
	for step in t.route:
		mine[step[0]] = true
	for pid in held.keys():
		if held[pid] == tid and not mine.has(pid):
			held.erase(pid)


func _arrive(sim: CitySim, tid: int) -> void:
	var t: Dictionary = trains[tid]
	var d: Dictionary = depots[t.depot]
	var leg: String = t.legs.pop_front()
	var km := 0.0
	t.route = []
	_release(tid)
	if leg.begins_with("siding:"):
		var lid := int(leg.substr(7))
		if lines.has(lid):
			var l: Dictionary = lines[lid]
			t.cars = l.cars
			l.cars = 0
			l.waiting_since = -1
			t.consist = ["gp38"]
			for i in t.cars:
				t.consist.append(CAR_FOR[t.cargo])
			t.purpose = "Local freight: %d loaded %s cars for the region" % [t.cars, STOCK[CAR_FOR[t.cargo]].cargo]
			t.from = l.target.name + " siding"
			t.to = "The region"
		t.state = "load"
		t.timer = LOAD_TICKS
	elif leg == "yard":
		t.state = "dwell"
		t.timer = DWELL_TICKS
		if t.legs.is_empty():
			t.purpose = "Waiting for work" if t.kind == "freight" else "At the platform"
			t.from = t.to
			t.to = d.name + (" yard" if t.kind == "freight" else " station")
			if t.kind == "passenger":
				t.since = sim.tick_count
				# Riders from the next town get off here.
				var fare: float = t.riders * Balance.RAIL_FARE * fx(t.depot, "fare*")
				d.money += fare
				d.ledger.income += fare
				t.riders = 0
	elif leg == "region":
		t.state = "away"
		t.timer = roundi((Balance.RAIL_REGION_DAYS if t.kind == "freight" else Balance.RAIL_PAX_AWAY_DAYS) * TICKS_PER_DAY)
		if t.kind == "freight" and t.cars > 0:
			var pay: float = t.cars * Balance.RAIL_CAR_RATE * fx(t.depot, "rate*")
			d.money += pay
			d.ledger.income += pay
			d.delivered = int(d.get("delivered", 0)) + t.cars
		t.purpose = "In the region: handing over cars at the interchange" if t.kind == "freight" \
			else "In the next town"
		t.from = d.name
		t.to = "The region"
		# The trip's running cost.
		km = _main_length(t.depot) * 2.0
		for lid in _lines_of(t.depot):
			if lines[lid].kind == "spur" and t.has("job") and lid == t.job:
				km += lines[lid].length * 2.0
		var run := _run_cost(km, t.kind == "passenger") * fx(t.depot, "run*")
		d.money -= run
		d.ledger.costs += run
		# The whole train is past the end of the map now: free its track.
		for pid in held.keys():
			if held[pid] == tid:
				held.erase(pid)
		t.trail = []


## A train comes back in from the region, empty cars or new riders aboard.
func _come_back(sim: CitySim, tid: int) -> void:
	var t: Dictionary = trains[tid]
	var d: Dictionary = depots[t.depot]
	var main := _main_line(t.depot)
	if main == -1:
		return
	var rp: int = lines[main].pieces[-1]
	if held.has(rp):
		return
	t.trail = [[rp, -1]]
	t.s = _length(rp)
	t.legs = ["yard"]
	if t.kind == "freight":
		t.cars = 0
		t.consist = ["gp38"]
		t.cargo = ""
		t.purpose = "Local freight: back from the region"
	else:
		t.riders = roundi(sim.stats.population * Balance.RAIL_RIDES_PER_RESIDENT * 0.25)
		t.purpose = "Passenger train from the next town: %d riders" % t.riders
	t.from = "The region"
	t.to = d.name + (" yard" if t.kind == "freight" else " station")
	if _start_leg(sim, tid):
		t.state = "run"
	else:
		t.trail = []
		t.state = "away"
		t.timer = 30


## Crossing gates: down while a train is on the crossing or will reach it
## within the warning time.
func _gates() -> void:
	if crossings.is_empty():
		return
	var spans := {}  # piece -> [[lo, hi]]
	for tid in trains:
		var t: Dictionary = trains[tid]
		if t.trail.is_empty():
			continue
		var reach: float = t.v * GATE_WARNING + 30.0 if t.state == "run" else 0.0
		var body := _spans(t, train_length(t), reach)
		for sp in body:
			if not spans.has(sp[0]):
				spans[sp[0]] = []
			spans[sp[0]].append([sp[1], sp[2]])
	for c in crossings:
		var down := false
		for sp in spans.get(c.piece, []):
			if c.s >= sp[0] - 6.0 and c.s <= sp[1] + 6.0:
				down = true
		c.closed = down


## Stretches of track a train covers: [[piece, lo s, hi s]], with `reach`
## metres ahead of the head on its route.
func _spans(t: Dictionary, length: float, reach: float) -> Array:
	var out := []
	var left: float = length
	var s: float = t.s
	for i in t.trail.size():
		var pid: int = t.trail[i][0]
		var dir: int = t.trail[i][1]
		if i > 0:
			s = _length(pid) if dir > 0 else 0.0
		var back := s - dir * left
		var lo := minf(s, back)
		var hi := maxf(s, back)
		lo = maxf(lo, 0.0)
		hi = minf(hi, _length(pid))
		out.append([pid, lo, hi])
		left -= absf(hi - lo)
		if left <= 0.0:
			break
	if reach > 0.0 and not t.route.is_empty():
		var s2: float = t.s
		for i in t.route.size():
			var pid: int = t.route[i][0]
			var dir: int = t.route[i][1]
			if i > 0:
				s2 = 0.0 if dir > 0 else _length(pid)
			var fwd := s2 + dir * reach
			var lo := clampf(minf(s2, fwd), 0.0, _length(pid))
			var hi := clampf(maxf(s2, fwd), 0.0, _length(pid))
			out.append([pid, lo, hi])
			reach -= absf(hi - lo)
			if reach <= 0.0:
				break
	return out


## The next grade crossing ahead of a train's head on its route, within
## `look` metres: {index (into crossings), dist (m)}, or {}. The engineer
## blows for it 15 to 20 seconds out (FRA, 49 CFR 222.21).
func next_crossing(tid: int, look := 800.0) -> Dictionary:
	var t: Dictionary = trains[tid]
	if crossings.is_empty() or t.route.is_empty() or t.state != "run":
		return {}
	var ahead := 0.0
	for i in t.route.size():
		var pid: int = t.route[i][0]
		var dir: int = t.route[i][1]
		var from_s: float = t.s if i == 0 else (0.0 if dir > 0 else _length(pid))
		var best := INF
		var found := -1
		for k in crossings.size():
			if crossings[k].piece != pid:
				continue
			var d: float = (float(crossings[k].s) - from_s) * dir
			if d >= 0.0 and d < best:
				best = d
				found = k
		if found != -1:
			return {"index": found, "dist": ahead + best} if ahead + best <= look else {}
		ahead += (_length(pid) - from_s) if dir > 0 else from_s
		if ahead > look:
			break
	return {}


## True if a car must stop for a crossing at this point (gates down).
func gate_down_near(p: Vector3, radius := 12.0) -> bool:
	for c in crossings:
		if c.closed and Vector2(c.pos.x - p.x, c.pos.z - p.z).length() < radius:
			return true
	return false


# --- Train geometry ------------------------------------------------------------

func train_length(t: Dictionary) -> float:
	var total := 0.0
	for k in t.consist:
		total += float(STOCK[k].len) + 1.0
	return total


## Where a point `x` metres behind the head is: {pos, tan, index, s}, or
## {} if that part of the train is off the map (coming in from the region).
func _behind(t: Dictionary, x: float) -> Dictionary:
	var s: float = t.s
	for i in t.trail.size():
		var pid: int = t.trail[i][0]
		var dir: int = t.trail[i][1]
		var L := _length(pid)
		if i > 0:
			s = L if dir > 0 else 0.0
		var avail := s if dir > 0 else L - s
		if x <= avail + 0.001 or i == t.trail.size() - 1:
			var at := clampf(s - dir * x, 0.0, L)
			if x > avail + 0.5 and i == t.trail.size() - 1:
				return {"index": i, "s": at, "off": true}
			var pose := pose_at(pid, at)
			return {"pos": pose[0], "tan": pose[1] * dir, "index": i, "s": at}
		x -= avail
	return {}


## Every car's ends for drawing: [[kind, front Vector3, back Vector3]].
func car_poses(tid: int) -> Array:
	var t: Dictionary = trains[tid]
	var out := []
	if t.trail.is_empty() or t.state == "away":
		return out
	var x := 0.0
	for k in t.consist:
		var L: float = STOCK[k].len
		var f: Dictionary = _behind(t, x + 0.5)
		var b := _behind(t, x + L - 0.5)
		x += L + 1.0
		if f.is_empty() or b.is_empty() or f.has("off") or b.has("off"):
			continue
		out.append([k, f.pos, b.pos])
	return out


## A point on a piece and the direction of increasing s there.
func pose_at(pid: int, s: float) -> Array:
	var pts: Array = pieces[pid].pts
	var cum: Array = _cum[pid]
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span: float = cum[hi] - cum[lo]
	var f: float = 0.0 if span < 0.001 else (s - cum[lo]) / span
	var p: Vector3 = pts[lo].lerp(pts[hi], clampf(f, 0.0, 1.0))
	var tan: Vector3 = (pts[hi] - pts[lo]).normalized()
	return [p, tan]


func _length(pid: int) -> float:
	var cum: Array = _cum.get(pid, [])
	if cum.is_empty():
		_measure(pid)
		cum = _cum[pid]
	return cum[-1]


func _complete(pid: int) -> bool:
	return pieces[pid].built < 0.0


func _pieces_at(node: int) -> Array:
	var out := []
	for pid in pieces:
		if pieces[pid].a == node or pieces[pid].b == node:
			out.append(pid)
	out.sort()
	return out


## The direction a piece leaves a node in.
func _away(pid: int, node: int) -> Vector3:
	var pts: Array = pieces[pid].pts
	if pieces[pid].a == node:
		return (pts[mini(2, pts.size() - 1)] - pts[0]).normalized()
	return (pts[maxi(0, pts.size() - 3)] - pts[-1]).normalized()


## The safe speed on a curve, m/s: V = sqrt(Eu / 0.0007 D) mph (FRA, no
## superelevation on new track).
func _curve_v(pid: int, j: int) -> float:
	var pts: Array = pieces[pid].pts
	if j <= 0 or j >= pts.size() - 1:
		return INF
	var a: Vector3 = pts[j] - pts[j - 1]
	var b: Vector3 = pts[j + 1] - pts[j]
	var ang := absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	if ang < 0.0005:
		return INF
	var r := minf(a.length(), b.length()) / (2.0 * sin(ang * 0.5))
	var degree := 1746.4 / maxf(r, 1.0)  # degree of curve, 100 ft chord
	return sqrt(UNBALANCE_IN / (0.0007 * degree)) * 0.44704


func _measure(pid: int) -> void:
	var pts: Array = pieces[pid].pts
	var cum := [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[-1] + pts[i].distance_to(pts[i - 1]))
	_cum[pid] = cum
	var kind: String = pieces[pid].kind
	var lims := []
	for i in pts.size():
		lims.append(minf(float(SPEED[kind]), _curve_v(pid, i)))
	_lim[pid] = lims


func _rebuild(sim: CitySim) -> void:
	_dirty = false
	version += 1
	_cum.clear()
	_lim.clear()
	for pid in pieces:
		_measure(pid)
	_cover.clear()
	for pid in pieces:
		var pc: Dictionary = pieces[pid]
		var built: float = _length(pid) if pc.built < 0.0 else pc.built
		var cum: Array = _cum[pid]
		for i in pc.pts.size():
			if cum[i] > built + 5.0:
				break
			var p: Vector3 = pc.pts[i]
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					_cover[Vector2i(floori(p.x / 10.0) + dx, floori(p.z / 10.0) + dz)] = true
	_find_crossings(sim)
	sim.mark_lots_dirty()


## The track's base level along a line of points (`off` turns them into
## terrain coordinates): never below the graded ground, lifted over water,
## and easing on and off any fill no steeper than `grade`. The view draws
## the same profile.
static func profile(pts: Array, grade: float, off: Vector2) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(pts.size())
	for i in pts.size():
		var p: Vector3 = pts[i]
		var y := Terrain.base(p.x + off.x, p.z + off.y)
		if Terrain.is_water(p.x + off.x, p.z + off.y):
			y = maxf(y, Terrain.water_level(p.x + off.x, p.z + off.y) + BRIDGE_CLEAR)
		h[i] = y
	for pass_dir in [1, -1]:
		var r := range(1, pts.size()) if pass_dir == 1 else range(pts.size() - 2, -1, -1)
		for i in r:
			var j: int = i - pass_dir
			var ds: float = (pts[i] as Vector3).distance_to(pts[j])
			h[i] = maxf(h[i], h[j] - grade * ds)
	return h


static func grade_of(kind: String) -> float:
	return RailPlanner.LIMITS.spur.grade if kind == "spur" else RailPlanner.LIMITS.main.grade


## Grade crossings: every place built track meets a road at ground level.
## Where the track is high on a fill the road goes under it instead.
func _find_crossings(sim: CitySim) -> void:
	_roads_dirty = false
	var old := {}
	for c in crossings:
		old[Vector2i(roundi(c.pos.x), roundi(c.pos.z))] = c.closed
	crossings.clear()
	underpasses.clear()
	var seen := {}
	var pids := pieces.keys()
	pids.sort()
	for pid in pids:
		var pc: Dictionary = pieces[pid]
		if pc.kind == "region":
			continue
		var built: float = _length(pid) if pc.built < 0.0 else pc.built
		var pts: Array = pc.pts
		var cum: Array = _cum[pid]
		var box := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
		for p in pts:
			box = box.expand(Vector2(p.x, p.z))
		box = box.grow(30.0)
		var h := PackedFloat32Array()
		for seg in sim.network.segments:
			var c := sim.network.curve_of(seg)
			var rb := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)).expand(Vector2(c[2].x, c[2].z))
			if not box.intersects(rb):
				continue
			var road := sim.network.sample_segment(seg, 24)
			for i in range(1, pts.size()):
				if cum[i] > built:
					break
				var a := Vector2(pts[i - 1].x, pts[i - 1].z)
				var b := Vector2(pts[i].x, pts[i].z)
				for j in range(1, road.size()):
					if absf(road[j].y) > 4.0:
						continue  # a bridge over the track
					var hit = Geometry2D.segment_intersects_segment(a, b, Vector2(road[j - 1].x, road[j - 1].z),
						Vector2(road[j].x, road[j].z))
					if hit != null:
						var at := Vector3(hit.x, 0.0, hit.y)
						var s: float = cum[i - 1] + a.distance_to(hit)
						if h.is_empty():
							h = profile(pts, grade_of(pc.kind), sim.terrain_offset)
						var f := a.distance_to(hit) / maxf(a.distance_to(b), 0.001)
						var fill := lerpf(h[i - 1], h[i], f) - Terrain.base(at.x + sim.terrain_offset.x, at.z + sim.terrain_offset.y)
						# One per place: a road sample can end right on the track.
						var key := Vector3i(seg, roundi(at.x), roundi(at.z))
						if seen.has(key):
							continue
						seen[key] = true
						if fill >= UNDERPASS_FILL:
							underpasses.append({"seg": seg, "pos": at, "piece": pid, "s": s, "fill": fill})
							continue
						crossings.append({"seg": seg, "pos": at, "piece": pid, "s": s,
							"closed": old.get(Vector2i(roundi(at.x), roundi(at.z)), false)})


func roads_changed() -> void:
	_roads_dirty = true


## True where built track or a depot yard lies (no lots, fields or pads there).
func covers(p: Vector3) -> bool:
	if depots.is_empty():
		return false
	if _cover.has(Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))):
		return true
	var q := Vector2(p.x, p.z)
	for id in depots:
		if Geometry2D.is_point_in_polygon(q, yard_poly(id)):
			return true
	return false


## The depot whose yard holds this point, or -1.
func depot_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in depots:
		if Geometry2D.is_point_in_polygon(q, yard_poly(id)):
			return id
	return -1


## The train with a car on this point, or -1.
func train_at(p: Vector3) -> int:
	var tids := trains.keys()
	tids.sort()
	for tid in tids:
		for car in car_poses(tid):
			var a := Vector2(car[1].x, car[1].z)
			var b := Vector2(car[2].x, car[2].z)
			var q := Vector2(p.x, p.z)
			if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < 3.0:
				return tid
	return -1


# --- Lookups -----------------------------------------------------------------

func _lines_of(depot: int) -> Array:
	var out := []
	for lid in lines:
		if lines[lid].depot == depot:
			out.append(lid)
	out.sort()
	return out


func _main_line(depot: int) -> int:
	for lid in _lines_of(depot):
		if lines[lid].kind == "main" and lines[lid].state in ["building", "open", "permit"]:
			return lid
	return -1


func _main_pieces(depot: int) -> Array:
	var main := _main_line(depot)
	if main == -1 or lines[main].state != "open":
		return []
	return lines[main].pieces


func _main_length(depot: int) -> float:
	var total := 0.0
	for pid in _main_pieces(depot):
		total += _length(pid)
	return total


## The open or planned line that serves this place, or -1.
func _serves(ref: String) -> int:
	for lid in lines:
		if lines[lid].target.ref == ref and lines[lid].state in ["permit", "building", "open"]:
			return lid
	return -1


## Points along a drawn route every 10 m or so.
static func _dense(pts: Array) -> Array:
	var out := [pts[0]]
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var n := maxi(1, ceili(a.distance_to(b) / 10.0))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


# --- Saving ----------------------------------------------------------------------

static func _pt(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


func to_dict() -> Dictionary:
	var ds := {}
	for id in depots:
		var d: Dictionary = depots[id].duplicate(true)
		d.pos = _pt(d.pos)
		d.dir = _pt(d.dir)
		d.axis = _pt(d.axis)
		ds[str(id)] = d
	var ls := {}
	for id in lines:
		var l: Dictionary = lines[id].duplicate(true)
		l.route = l.route.map(_pt)
		l.target.pos = _pt(l.target.pos)
		ls[str(id)] = l
	var ns := {}
	for id in nodes:
		ns[str(id)] = _pt(nodes[id])
	var ps := {}
	for id in pieces:
		var pc: Dictionary = pieces[id].duplicate(true)
		pc.pts = pc.pts.map(_pt)
		ps[str(id)] = pc
	var ts := {}
	for id in trains:
		ts[str(id)] = trains[id].duplicate(true)
	var h := {}
	for pid in held:
		h[str(pid)] = held[pid]
	return {"depots": ds, "lines": ls, "nodes": ns, "pieces": ps, "trains": ts, "held": h,
		"region": region_nodes.keys(), "next": _next}


func from_dict(d: Dictionary) -> void:
	depots.clear()
	lines.clear()
	nodes.clear()
	pieces.clear()
	trains.clear()
	held.clear()
	region_nodes.clear()
	for k in d.get("depots", {}):
		var x: Dictionary = d.depots[k].duplicate(true)
		x.pos = _v(x.pos)
		x.dir = _v(x.dir)
		x.axis = _v(x.axis)
		x.ends = x.ends.map(func(n): return int(n))
		x.yard = x.yard.map(func(n): return int(n))
		x.pax_train = int(x.pax_train)
		x.freight_train = int(x.freight_train)
		x.debt_days = int(x.debt_days)
		if not x.has("built"):
			x.built = []
		x.subsidy = int(x.subsidy)
		x.opened = int(x.get("opened", 0))
		if x.has("delivered"):
			x.delivered = int(x.delivered)
		for ref in x.skip:
			x.skip[ref] = int(x.skip[ref])
		depots[int(k)] = x
	for k in d.get("lines", {}):
		var l: Dictionary = d.lines[k].duplicate(true)
		l.route = l.route.map(_v)
		l.target.pos = _v(l.target.pos)
		l.depot = int(l.depot)
		l.pieces = l.pieces.map(func(n): return int(n))
		l.cars = int(l.cars)
		l.permit = int(l.permit)
		l.asked = int(l.asked)
		l.waiting_since = int(l.waiting_since)
		l.zoned = int(l.zoned)
		l.cost = int(l.cost)
		for key in l.start:
			l.start[key] = int(l.start[key])
		for c in l.crossings:
			c.seg = int(c.seg)
		lines[int(k)] = l
	for k in d.get("nodes", {}):
		nodes[int(k)] = _v(d.nodes[k])
	for k in d.get("pieces", {}):
		var pc: Dictionary = d.pieces[k].duplicate(true)
		pc.pts = pc.pts.map(_v)
		pc.a = int(pc.a)
		pc.b = int(pc.b)
		pc.depot = int(pc.depot)
		pc.line = int(pc.line)
		pieces[int(k)] = pc
	for k in d.get("trains", {}):
		var t: Dictionary = d.trains[k].duplicate(true)
		t.depot = int(t.depot)
		t.trail = t.trail.map(func(e): return [int(e[0]), int(e[1])])
		t.route = t.route.map(func(e): return [int(e[0]), int(e[1])])
		t.cars = int(t.cars)
		t.timer = int(t.timer)
		t.riders = int(t.riders)
		t.number = int(t.number)
		t.since = int(t.since)
		if t.has("job"):
			t.job = int(t.job)
		trains[int(k)] = t
	for k in d.get("held", {}):
		held[int(k)] = int(d.held[k])
	for n in d.get("region", []):
		region_nodes[int(n)] = true
	var nx: Dictionary = d.get("next", {})
	for key in _next:
		_next[key] = int(nx.get(key, 1))
	_dirty = true
