class_name Construction
extends RefCounted
## New buildings go up the way real ones do, instead of popping in (Brawn,
## 2026-10-22). Cities: Skylines 2 hides a new building inside a scaffold
## box; here you watch the real sequence: the site is cleared, the
## foundation poured, the frame goes up stick by stick, it's wrapped and
## roofed, sided, finished inside and landscaped.
##
## Each kind of building follows its own real method (PROFILES): a house is
## wood framed, shops and civic buildings are steel and block, factories are
## pre-engineered steel, warehouses are concrete tilt-up and farm buildings
## are pole barns. Stage lengths are real US build times in weeks, scaled to
## game time by Balance.BUILD_TICKS_PER_WEEK, so they keep their real
## proportions: a pole barn is up in about two months, a house in about
## seven, a fire station in about a year.
##
## Which stage a site is in follows from its start tick and the clock alone,
## so every player in a region sees the same thing and nothing per-frame is
## saved. Crews and deliveries are real trips (Traffic's dispatch): a crew
## pickup comes for the whole job, and the two big loads come on their own
## trucks (concrete for the footings, then lumber or steel on a flatbed).
## Each one parks at the curb in front of the site and later drives back
## out. Nothing vanishes.
##
## Benchmark: Cities: Skylines 2's construction (a scaffold box that hides
## the building, then a pop). Timelines: US Census Survey of Construction
## (about 7 months for a single-family home), and typical schedules for
## pre-engineered steel, tilt-up and post-frame buildings.

## The stages every building goes through, in order.
const STAGES := ["clear", "foundation", "frame", "dry_in", "exterior", "interior", "landscape"]

## Real build sequences. "frame" picks how FrameBuilder draws the structure,
## "weeks" is each stage's real length, "trucks" what each stage brings.
const PROFILES := {
	# Platform-framed house: 2x4 studs at 16 in, trusses at 24 in, house wrap.
	# The contractor's pickup (ladder rack on top) stays out front until the
	# house is done and one concrete truck comes for the foundation, or if it
	# can't get there by then for the driveway and walks (poured last, once
	# the heavy equipment is gone); no semi
	# (Brawn, 2026-10-24: "Bring one concrete truck and a contractor's truck
	# with the ladder on the top").
	"house": {"frame": "wood", "weeks": [1, 3, 4, 3, 4, 11, 2], "found": 0.45,
		"words": ["Clearing the lot", "Pouring the foundation", "Framing", "Sheathing and roofing",
			"Siding and trim", "Finishing inside", "Landscaping"],
		"deliveries": {}, "brings": [["concrete_mixer", "ready-mix concrete", 1, 6]]},
	# Small-town retail: slab on grade, steel columns and bar joists, block walls.
	"shop": {"frame": "steel", "weeks": [1, 3, 4, 3, 4, 8, 2], "found": 0.3,
		"words": ["Clearing the site", "Pouring the slab", "Raising the steel", "Laying block and decking the roof",
			"Brick and storefront", "Fitting out inside", "Paving and planting"]},
	# Pre-engineered metal building: rigid frames, girts and purlins, panels.
	"factory": {"frame": "steel", "weeks": [2, 4, 6, 4, 3, 10, 2], "found": 0.3,
		"words": ["Grading the site", "Pouring the slab", "Raising the steel", "Hanging wall and roof panels",
			"Doors and trim", "Installing equipment", "Paving and planting"]},
	# Concrete tilt-up: panels cast on the slab and tipped up by crane.
	"warehouse": {"frame": "tilt_up", "weeks": [2, 4, 5, 4, 3, 6, 2], "found": 0.3,
		"words": ["Grading the site", "Pouring the slab", "Tilting up the wall panels", "Joists and roof deck",
			"Dock doors and paint", "Racking and fit-out", "Paving and planting"]},
	# Civic: steel frame, block backup and brick, a long fit-out.
	"civic": {"frame": "steel", "weeks": [2, 6, 8, 6, 8, 18, 3], "found": 0.3,
		"words": ["Clearing the site", "Footings and slab", "Raising the steel", "Block walls and roof deck",
			"Brick and windows", "Finishing inside", "Landscaping"]},
	# Post-frame (pole) barn: posts in augered holes, girts, trusses, steel skin.
	"barn": {"frame": "pole", "weeks": [1, 1, 2, 2, 1, 1, 1], "found": 0.2,
		"words": ["Clearing the yard", "Setting the posts", "Girts and trusses", "Steel roof and walls",
			"Doors and trim", "Wiring and stalls", "Gravel and seeding"]},
	# A rural electric co-op's line extension: stake the route, set the poles,
	# hang the transformer, string the wire, then energize. Co-ops quote about
	# 4 to 8 weeks once the work order is in. The town has no power from it
	# until it's energized (see CitySim._update_services).
	"power_feed": {"frame": "pole", "weeks": [1, 1, 1, 1, 1, 1, 1], "found": 0.1,
		"words": ["Staking the line", "Setting the poles", "Hanging the transformer", "Stringing the wire",
			"Setting the meters", "Testing the line", "Energizing"],
		"deliveries": {"foundation": [["flatbed", "utility poles"]], "frame": [["bucket_truck", "transformer"]],
			"dry_in": [["bucket_truck", "wire reels"]]}},
	# A small public well: drilled and cased, a block pump house over it,
	# then the pump and pressure tank, and the new well is disinfected and
	# sampled before it goes on line (AWWA C654). Six to ten weeks.
	"well": {"frame": "steel", "weeks": [1, 2, 1, 1, 1, 1, 1], "found": 0.3,
		"words": ["Clearing the site", "Drilling the well", "Framing the pump house", "Roofing",
			"Block and doors", "Setting the pump and tank", "Disinfecting and testing"],
		"deliveries": {"foundation": [["flatbed", "well casing"]], "interior": [["box_truck", "pump and pressure tank"]]}},
	# A surface parking lot: graded, a crushed-stone base rolled in, curbs
	# and light pole bases set, two lifts of asphalt, then striped and
	# planted. Three to six weeks for a small-town lot.
	"paving": {"frame": "pole", "weeks": [1, 1, 1, 1, 1, 1, 1], "found": 0.0,
		"words": ["Clearing and grading", "Rolling in the stone base", "Setting curbs and light poles",
			"Paving the asphalt", "Striping the stalls", "Signs and the pay station", "Planting the islands"],
		"deliveries": {"foundation": [["dump_truck", "crushed stone"]], "dry_in": [["dump_truck", "hot-mix asphalt"]]}},
	# A precast concrete garage: footings, then double tees and spandrels
	# set by crane deck by deck, a topping and the ramps, stairs and lights.
	"garage": {"frame": "tilt_up", "weeks": [2, 4, 10, 6, 4, 4, 2], "found": 0.3,
		"words": ["Clearing the site", "Footings and the ground slab", "Setting the precast tees",
			"Topping the decks and ramps", "Spandrels, stairs and the elevator", "Lighting and striping", "Planting"],
		"deliveries": {"frame": [["flatbed", "precast double tees"]]}},
	# A phase of a subdivision, before any house (Subdivisions): the land is
	# cleared and its topsoil stripped and stockpiled, rough graded, the
	# sanitary sewer and storm drains laid deepest first, then the water
	# main, curbs on a crushed-stone base, the asphalt base course, and the
	# surveyor stakes the lots while the bare ground is seeded against
	# erosion (Indiana Rule 5 / NPDES). Three to five months for a phase.
	"subdivision": {"frame": "pole", "weeks": [2, 3, 5, 3, 2, 1, 1], "found": 0.0,
		"words": ["Clearing the land and stripping the topsoil", "Rough grading the streets and lots",
			"Laying the sewers and storm drains", "Laying the water main", "Setting the curbs and stone base",
			"Paving the streets", "Staking the lots and seeding"],
		"deliveries": {"clear": [["flatbed", "a bulldozer"]], "foundation": [["dump_truck", "fill dirt"]],
			"frame": [["flatbed", "sewer pipe and manholes"]], "dry_in": [["flatbed", "ductile iron water main"]],
			"exterior": [["dump_truck", "crushed stone"], ["concrete_mixer", "curb concrete"]],
			"interior": [["dump_truck", "hot-mix asphalt"]]}},
}
## What each stage sends: [vehicle kind, cargo] (the crew's pickup comes for
## the whole job). A profile's "brings" instead come with the crew at the
## start and stay through a later stage: [kind, cargo, stage index]. A kind the fleet doesn't have yet falls back to the next.
## The big loads only, so a street of new homes doesn't jam the town: the
## crew's pickup brings the rest.
const DELIVERIES := {
	"clear": [],
	"foundation": [["concrete_mixer", "ready-mix concrete"]],
	"frame": [["flatbed", "framing package"]],
	"dry_in": [],
	"exterior": [],
	"interior": [],
	"landscape": [],
}
const FALLBACK := {"concrete_mixer": "dump_truck"}
## The steel goes up on a flatbed too, but a different load.
const FRAME_CARGO := {"wood": "framing lumber", "steel": "structural steel", "tilt_up": "rebar and forms",
	"pole": "posts and trusses"}
## Ticks between checks on the sites (a game hour has 60).
const EVERY := 10
## Most vehicles parked at one site's curb at once.
const MAX_PARKED := 3
## Trips the sites send out in one round at most (each one routes a car).
## A site past its budget waits for the next round, so a street of homes
## changing stage together doesn't hitch the game.
const MAX_SENDS := 4
## New sites that get their first trucks in one round. The first trip to a
## lot makes Traffic lay out its driveway and parking (a few ms each).
const MAX_NEW := 1
## Vehicles drive in real time but a house goes up in about 84 seconds of
## play, so a crew from the map's edge used to arrive minutes after the
## house was done, while every new lot sent more: "building anything at all
## causes a traffic jam of construction vehicles" (Brawn, 2026-10-24). Now
## a crew is sent only if it gets there before the building is finished,
## and a delivery only if it gets there by the middle of its stage; the
## site keeps to its schedule either way. And no more than this many site
## trips are heading in at once, town wide.
const MAX_ON_ROAD := 16
## The ETA leaves out turns, traffic and pulling out: a trip counts as this
## much slower (a truck longer than a pickup, slow off the line, more), plus
## this many ticks to get going. Measured against real trips: crews took
## 1.1 to 1.6 times it, loaded concrete trucks up to twice.
const ETA_MARGIN := 1.3
const TRUCK_ETA_MARGIN := 1.8
const ETA_START := 30
## For the yard's owner judging which houses its trucks could reach: roads
## run about this much longer than the straight line, at about 25 mph (m/s).
const REACH_DETOUR := 1.4
const STREET_SPEED := 11.0

## ref -> {profile, start (tick), front [x, z], out [x, z] (toward the street),
## to_curb, stage (last stage it sent trucks for), parked: [{kind, job, cargo}]}
var sites := {}
## Traffic trip id -> {ref, kind, job, cargo, inbound}
var trips := {}
## [site ref, where the trip starts, road revision] -> Traffic.drive_ticks
## (not saved: worked out again the same way after a load).
var _eta := {}
var _eta_roads := []


## A new building starts going up. `front` is the middle of its street edge,
## `out` points from it toward the street, `to_curb` is how far the curb is.
func start(ref: String, profile: String, tick: int, front: Vector3, out: Vector3, to_curb: float) -> void:
	if not PROFILES.has(profile):
		profile = "house"
	sites[ref] = {"profile": profile, "start": tick, "front": [snappedf(front.x, 0.01), snappedf(front.z, 0.01)],
		"out": [snappedf(out.x, 0.001), snappedf(out.z, 0.001)], "to_curb": to_curb, "stage": -1, "parked": [],
		"yard": -1, "got": []}


## Ticks from a build's start to the start of `stage` (the end of the build
## for STAGES.size()), as an absolute tick.
static func stage_start(profile: String, start_tick: int, stage: int) -> int:
	var weeks := 0
	for i in mini(stage, STAGES.size()):
		weeks += int(PROFILES[profile].weeks[i])
	return start_tick + weeks * Balance.BUILD_TICKS_PER_WEEK


## Total real-build length of a profile, in ticks.
static func duration(profile: String) -> int:
	var total := 0
	for w in PROFILES[profile].weeks:
		total += int(w)
	return total * Balance.BUILD_TICKS_PER_WEEK


## Where a build that began at `start` stands at `tick`: {} once it's done,
## otherwise {stage (index), name, t (0-1 through the stage), total (0-1),
## profile, words (what's happening)}.
static func state_at(profile: String, start_tick: int, tick: int) -> Dictionary:
	var p: Dictionary = PROFILES[profile]
	var at := float(tick - start_tick)
	if at < 0.0:
		at = 0.0
	var total := float(duration(profile))
	if at >= total:
		return {}
	var t0 := 0.0
	for i in STAGES.size():
		var len := float(p.weeks[i]) * Balance.BUILD_TICKS_PER_WEEK
		if at < t0 + len:
			return {"stage": i, "name": STAGES[i], "t": (at - t0) / len, "total": at / total,
				"profile": profile, "frame": p.frame, "words": p.words[i], "found": p.found}
		t0 += len
	return {}


## This site's state now ({} if it's finished or was never a site).
func state(ref: String, tick: int) -> Dictionary:
	if not sites.has(ref):
		return {}
	return state_at(sites[ref].profile, int(sites[ref].start), tick)


## For the info panel: "Under construction: Framing (40% done)", or "".
func describe(ref: String, tick: int) -> String:
	var st := state(ref, tick)
	if st.is_empty():
		return ""
	return "Under construction: %s (%d%% done)" % [st.words, roundi(float(st.total) * 100.0)]


## The same answer as state(ref, tick).is_empty(), without working out the
## stage: the town asks this of every building every few ticks.
func is_done(ref: String, tick: int) -> bool:
	var s = sites.get(ref)
	if s == null:
		return true
	var profile: String = s.profile
	if not _durations.has(profile):
		_durations[profile] = duration(profile)
	return float(maxi(tick - int(s.start), 0)) >= float(_durations[profile])


static var _durations := {}  # profile -> duration(profile)
## Worked out once per round: trips left to send, the contractor's yard,
## and which sites have trips coming (ref -> true).
var _budget := 0
var _fresh := 0
var _yard = null
var _coming := {}
var _crew_coming := {}
var _heading_in := 0
var _booked := {}  # site ref -> {cargo: true} for trips heading there
var _away := {}    # yard -> {kind: trucks at houses or on the road}
var _waits := {}   # cargo -> houses building without one of the yard's trucks


func tick(sim: CitySim) -> void:
	var t0 := Perf.now()
	_tick(sim)
	Perf.add("sim.construction", t0)


func _tick(sim: CitySim) -> void:
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			_arrive(sim, trips[a.id], int(a.get("vid", -1)))
			trips.erase(a.id)
	for f in sim.traffic.failed:
		trips.erase(f.id)  # it never got there: nothing to park
	if sim.tick_count % EVERY != 0:
		return
	_budget = MAX_SENDS
	_fresh = MAX_NEW
	if _eta_roads != [sim.network.revision, sim.traffic.version]:
		_eta_roads = [sim.network.revision, sim.traffic.version]
		_eta.clear()  # the roads changed: every way there is worked out again
	_yard = null
	_coming.clear()
	_crew_coming.clear()
	_heading_in = 0
	_count(sim)
	for id in trips:
		var t: Dictionary = trips[id]
		if t.inbound:
			_heading_in += 1
			_coming[t.ref] = true
			if t.job == "crew":
				_crew_coming[t.ref] = true
	var refs := sites.keys()
	refs.sort()
	for ref in refs:
		var s: Dictionary = sites[ref]
		if not _exists(sim, ref):
			_leave_all(sim, ref)  # demolished or rezoned: everyone packs up
			if s.parked.is_empty():
				sites.erase(ref)
			s.stage = STAGES.size()
			continue
		var st := state_at(s.profile, int(s.start), sim.tick_count)
		var stage: int = STAGES.size() if st.is_empty() else int(st.stage)
		if stage != int(s.stage):
			if sim.simulate_traffic and (_budget < _sends_for(s, stage) or int(s.stage) < 0 and _fresh <= 0):
				continue  # its trucks go next round
			if int(s.stage) < 0:
				_fresh -= 1
			s.stage = stage
			_leave(sim, ref, "delivery", stage - 1)  # the last stage's trucks head off
			if stage >= STAGES.size():
				if int(s.get("yard", -1)) != -1:
					sim.builders.paid(int(s.yard))
					s.yard = -1
				_leave_all(sim, ref)
			elif sim.simulate_traffic:
				if _yard_house(sim, s):
					pass  # its builder's trucks are sent below, each round
				else:
					if not _has_crew(ref):
						_send(sim, ref, "work_pickup", "crew", "building crew", _crew_base(sim, s),
							int(s.start) + duration(s.profile))
					if stage == 0:
						for b in PROFILES[s.profile].get("brings", []):
							_send(sim, ref, b[0], "delivery", b[1], sim.logistics._edge(sim, _pos(s)),
								_deadline(s, [b[0], b[1], "delivery", int(b[2])]), int(b[2]), true)
				var mid := (stage_start(s.profile, int(s.start), stage) + stage_start(s.profile, int(s.start), stage + 1)) / 2
				for d in PROFILES[s.profile].get("deliveries", DELIVERIES).get(STAGES[stage], []):
					var cargo: String = d[1]
					if STAGES[stage] == "frame" and d[0] == "flatbed":
						cargo = FRAME_CARGO[PROFILES[s.profile].frame]
					_send(sim, ref, d[0], "delivery", cargo, sim.logistics._edge(sim, _pos(s)), mid, stage)
		elif s.parked.size() > 0 and st.get("t", 0.0) > 0.5:
			_leave(sim, ref, "delivery", stage)  # dropped off: back out halfway through
		if stage < STAGES.size() and int(s.stage) >= 0 and sim.simulate_traffic and _yard_house(sim, s):
			_from_yard(sim, ref, s)
		if stage >= STAGES.size():
			_leave_all(sim, ref)
			if s.parked.is_empty() and not _coming.has(ref):
				sites.erase(ref)


## A house with a builder's yard in town: its trucks come from there.
static func _yard_house(sim: CitySim, s: Dictionary) -> bool:
	return PROFILES[s.profile].has("brings") and sim.services.yard() != -1


## Sends a house the builder's trucks it's still missing, if the yard has one
## free: the crew as soon as it can, the concrete truck timed to get there as
## its pour starts (the foundation, else the driveway).
func _from_yard(sim: CitySim, ref: String, s: Dictionary) -> void:
	var y: Array = sim.builders.yard(sim)
	if int(y[1]) == -1:
		return
	var crew := ["work_pickup", "building crew", "crew", -1]
	if not _has(ref, s, crew[1]) and _free(sim, int(y[1]), crew[0]):
		_send(sim, ref, crew[0], crew[2], crew[1], y[0], _deadline(s, crew), -1, false, int(y[1]))
	for b in PROFILES[s.profile].get("brings", []):
		if _has(ref, s, b[1]) or not _free(sim, int(y[1]), b[0]):
			continue
		for at in b.slice(2):
			var n := [b[0], b[1], "delivery", int(at)]
			if sim.tick_count >= _deadline(s, n):
				continue
			var sent := _send(sim, ref, n[0], n[2], n[1], y[0], _deadline(s, n), n[3], true, int(y[1]), false,
				stage_start(s.profile, int(s.start), int(at)))
			if sent >= 0:
				break  # on its way, or it leaves in time for this pour


## Where the builder's trucks are and which houses wait for one, worked out
## again each round from the sites and trips (so nothing drifts).
func _count(sim: CitySim) -> void:
	_booked.clear()
	_away.clear()
	_waits.clear()
	for id in trips:
		var t: Dictionary = trips[id]
		if t.inbound:
			if not _booked.has(t.ref):
				_booked[t.ref] = {}
			_booked[t.ref][t.cargo] = true
		_tally(int(t.get("yard", -1)), t.kind)
	for ref in sites:
		var s: Dictionary = sites[ref]
		for p in s.parked:
			_tally(int(p.get("yard", -1)), p.kind)
		# A house going up without one of the yard's trucks it could still
		# use: what the owner buys more of.
		if PROFILES[s.profile].has("brings") and int(s.stage) >= 0 and int(s.stage) < STAGES.size() \
				and not is_done(ref, sim.tick_count):
			for n in _needs_full(s, sim.tick_count):
				if not _has(ref, s, n[1]) and _reachable(sim, ref, s, n):
					_waits[n[1]] = int(_waits.get(n[1], 0)) + 1


func _tally(yard: int, kind: String) -> void:
	if yard == -1:
		return
	if not _away.has(yard):
		_away[yard] = {}
	_away[yard][kind] = int(_away[yard].get(kind, 0)) + 1


## The trucks a house's builder sends: [kind, cargo, job, stage it stays
## through (-1: to the end)]. What it brings ("brings": [kind, cargo, the
## stages it's wanted for]) is for the first of those stages still to come
## by `tick` (the foundation, else the driveway), or left out once all are.
static func _needs_full(s: Dictionary, tick := -1) -> Array:
	var out := [["work_pickup", "building crew", "crew", -1]]
	for b in PROFILES[s.profile].get("brings", []):
		if b[1] in s.get("got", []):
			continue  # it came already (one concrete truck a house)
		for at in b.slice(2):
			var n := [b[0], b[1], "delivery", int(at)]
			if tick < 0 or tick < _deadline(s, n):
				out.append(n)
				break
	return out


## A builder with `cargo` is parked at site `ref` or on its way there.
func _has(ref: String, s: Dictionary, cargo: String) -> bool:
	for p in s.parked:
		if p.cargo == cargo:
			return true
	return _booked.get(ref, {}).has(cargo)


## Trucks of each kind the builder's yard `yard` has out (Builders).
func away_from(yard: int) -> Dictionary:
	if _away.is_empty() and not trips.is_empty():
		_count_away()
	return _away.get(yard, {})


func _count_away() -> void:
	for id in trips:
		_tally(int(trips[id].get("yard", -1)), trips[id].kind)
	for s in sites.values():
		for p in s.parked:
			_tally(int(p.get("yard", -1)), p.kind)


## Houses waiting for each kind of builder (cargo -> count), for the yard's
## owner deciding what to buy.
func waiting_for(_yard_id: int) -> Dictionary:
	return _waits


## A truck from the builder's yard could still get to `ref` in time for `n`,
## going by the straight line there at street speed (saved state only, so
## every copy of the town buys the same trucks).
func _reachable(sim: CitySim, _ref: String, s: Dictionary, n: Array) -> bool:
	var y: Array = sim.builders.yard(sim)
	if int(y[1]) == -1:
		return false
	var at := Vector3(float(y[0].pos[0]), 0.0, float(y[0].pos[1]))
	var truck: bool = float(VehicleTypes.spec(n[0]).len) > 6.5
	var ticks := _pos(s).distance_to(at) * REACH_DETOUR / (STREET_SPEED * TrafficSim.DT) \
		* (TRUCK_ETA_MARGIN if truck else ETA_MARGIN) + ETA_START
	return sim.tick_count + ticks <= _deadline(s, n)


## The yard has a truck of `kind` that isn't out at a house or on the road.
func _free(sim: CitySim, yard: int, kind: String) -> bool:
	return sim.builders.owned(yard, kind) - int(_away.get(yard, {}).get(kind, 0)) > 0


## The last tick a builder's truck is any use at site `s`: a crew before the
## house is done, the concrete truck by the middle of the pour.
static func _deadline(s: Dictionary, n: Array) -> int:
	if int(n[3]) < 0:
		return int(s.start) + duration(s.profile)
	var at := int(n[3])
	return (stage_start(s.profile, int(s.start), at) + stage_start(s.profile, int(s.start), at + 1)) / 2


## The nearest houses going up that could still use a builder's truck with
## `cargo`, nearest first (at most a few, each tried with its ETA).
func _next_jobs(sim: CitySim, from: Vector3, cargo: String) -> Array:
	var out := []
	var refs := sites.keys()
	refs.sort()
	for r in refs:
		var t: Dictionary = sites[r]
		if not PROFILES[t.profile].has("brings") or int(t.stage) < 0 or int(t.stage) >= STAGES.size() \
				or not _exists(sim, r) or _has(r, t, cargo):
			continue
		for n in _needs_full(t, sim.tick_count):
			if n[1] == cargo:
				out.append([_pos(t).distance_squared_to(from), r, n])
	out.sort_custom(func(a, b): return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
	return out.slice(0, 3)


## How much of a round's budget a site uses on reaching `stage`: its parked
## trucks leaving, then two for each new trip (the route worked out for its
## ETA, then the trip): a crew if it has none, the stage's deliveries, and
## what it brings at the start.
func _sends_for(s: Dictionary, stage: int) -> int:
	var n: int = s.parked.size()
	if stage < STAGES.size():
		n += 2 * (PROFILES[s.profile].get("deliveries", DELIVERIES).get(STAGES[stage], []).size() + 1)
	if stage == 0:
		n += 2 * PROFILES[s.profile].get("brings", []).size()
	return mini(n, MAX_SENDS)


## Vehicles standing at a site's curb: [[kind, Transform3D, id], ...] for
## TrafficView, facing the way traffic runs on that side.
func parked_poses() -> Array:
	var out := []
	var refs := sites.keys()
	refs.sort()
	for ref in refs:
		var s: Dictionary = sites[ref]
		var o := Vector3(float(s.out[0]), 0.0, float(s.out[1]))
		var curb: Vector3 = _pos(s) + o * (float(s.to_curb) + 1.3)
		var fwd := Vector3.UP.cross(-o).normalized()  # lot on the driver's right
		var along := 6.0
		for i in s.parked.size():
			var p: Dictionary = s.parked[i]
			var kind: String = p.kind
			var len: float = float(VehicleTypes.spec(kind).len)
			# Stood on the road, not at sea level (the land is real ground, 250 m up).
			out.append([kind, Transform3D(Basis.looking_at(fwd, Vector3.UP), Terrain.stand(curb + fwd * along)),
				hash([ref, i])])
			along -= len + 1.5
	return out


## Sends a crew or delivery from `base` if it can be there by tick `by` and
## the town's streets aren't already busy with site trips. A delivery stays
## parked through stage `until`; `yard` is the builder's yard the truck is
## from (`counted`: it's already counted out, leaving another house); it
## doesn't set out so early it would get there before tick `not_before`.
## 1 if it went, 0 if not this round (busy streets, the round's budget, too
## early), -1 if it can't make it in time.
func _send(sim: CitySim, ref: String, kind: String, job: String, cargo: String, base: Dictionary, by: int,
		until := -1, brought := false, yard := -1, counted := false, not_before := -1) -> int:
	if base.is_empty():
		return -1
	if _heading_in >= MAX_ON_ROAD:
		return 0
	kind = _kind(kind)
	var s: Dictionary = sites[ref]
	var to := _curb(ref, s)
	var truck: bool = float(VehicleTypes.spec(kind).len) > 6.5
	var key := [ref, base.get("ref", ""), base.get("pos"), truck, sim.network.revision, sim.traffic.version]
	# Worked out once per trip and kept while the roads stay the same, so a
	# copy of the town loaded from a save (with none kept yet) decides the same.
	if not _eta.has(key):
		_eta[key] = sim.traffic.drive_ticks(base, to, truck)
	var eta: float = _eta[key]
	var trip := eta * (TRUCK_ETA_MARGIN if truck else ETA_MARGIN) + ETA_START
	if sim.tick_count + trip > by:
		return -1  # it would get there after the work is done
	if sim.tick_count + trip < not_before or _budget <= 0:
		return 0  # it sets out later
	_budget -= 1
	var id: int = sim.traffic.dispatch(base, to, "construction", {"good": cargo, "amount": 1}, kind)
	if id == -1:
		return -1
	_heading_in += 1
	trips[id] = {"ref": ref, "kind": kind, "job": job, "cargo": cargo, "inbound": true, "until": until,
		"brought": brought, "yard": yard}
	_coming[ref] = true
	if job == "crew":
		_crew_coming[ref] = true
	if not _booked.has(ref):
		_booked[ref] = {}
	_booked[ref][cargo] = true
	if not counted:
		_tally(yard, kind)
	return 1


## A truck got to its site (`vid`: Traffic's vehicle): it stands at the curb
## out front, drawn from here (parked_poses), so Traffic's own copy of it
## parked on the lot goes.
func _arrive(sim: CitySim, t: Dictionary, vid := -1) -> void:
	if not t.inbound or not sites.has(t.ref):
		return
	var s: Dictionary = sites[t.ref]
	if s.parked.size() < MAX_PARKED:
		if vid != -1:
			sim.traffic.retire_vehicle(vid)
		if t.get("brought", false) and not t.cargo in s.got:
			s.got.append(t.cargo)
		s.parked.append({"kind": t.kind, "job": t.job, "cargo": t.cargo, "until": int(t.get("until", -1)),
			"brought": bool(t.get("brought", false)), "yard": int(t.get("yard", -1))})
		if t.job == "crew" and int(t.get("yard", -1)) != -1 and int(s.get("yard", -1)) == -1:
			# The builder's first draw now, the rest when the house is done.
			s.yard = int(t.yard)
			sim.builders.started(int(t.yard))


## Parked vehicles doing `job` drive away (to the highway, or the crew home),
## all but those staying on past stage `upto` (the concrete truck stays
## until halfway through the foundation, the pour).
func _leave(sim: CitySim, ref: String, job: String, upto := 1 << 30) -> void:
	var s: Dictionary = sites[ref]
	var keep := []
	for p in s.parked:
		if p.job != job or int(p.get("until", -1)) > upto:
			keep.append(p)
			continue
		if _budget <= 0 and sim.simulate_traffic:
			keep.append(p)  # it pulls out next round
			continue
		var yard := int(p.get("yard", -1))
		if yard != -1 and sim.simulate_traffic:
			# The builder's own truck: straight on to the nearest house that
			# can still use it, or back to the yard.
			var went := false
			for j in _next_jobs(sim, _pos(s), p.cargo):
				var n: Array = j[2]
				# From the curb, where it's parked, straight onto the street.
				var curb := {"ref": "edge", "pos": s.front}
				if _send(sim, j[1], p.kind, job, p.cargo, curb, _deadline(sites[j[1]], n), n[3], n[3] >= 0,
						yard, true) == 1:
					went = true
					break
			if not went:
				var home: Dictionary = sim.builders.yard(sim)[0]
				var hid := -1
				if not home.is_empty() and _budget > 0:
					_budget -= 1
					hid = sim.traffic.dispatch({"ref": "edge", "pos": s.front}, home, "construction",
						{"good": "back to the yard", "amount": 0}, p.kind)
				if home.is_empty():
					p.yard = -1  # the yard's gone: it leaves town like anyone's truck
				elif hid == -1:
					keep.append(p)  # no way out yet: it waits at the curb
					continue
				else:
					trips[hid] = {"ref": ref, "kind": p.kind, "job": job, "cargo": "", "inbound": false, "yard": yard}
					continue
			else:
				continue
		var dest := _crew_base(sim, s) if job == "crew" else _edge_ahead(sim, s)
		var id := -1
		if not dest.is_empty() and sim.simulate_traffic:
			_budget -= 1
			id = sim.traffic.dispatch(_curb(ref, s), dest, "construction",
				{"good": "empty" if job != "crew" else "crew going home", "amount": 0}, p.kind)
		if id == -1:
			keep.append(p)  # no way out yet: it waits at the curb
		else:
			trips[id] = {"ref": ref, "kind": p.kind, "job": job, "cargo": "", "inbound": false}
	s.parked = keep


## Where an emptied truck leaves town: the nearest way off the map ahead of
## it at the curb, so a 70 ft rig drives on (through town if need be)
## rather than hunting for room to turn around on a two-lane highway.
static func _edge_ahead(sim: CitySim, s: Dictionary) -> Dictionary:
	var pos := _pos(s)
	var o := Vector3(float(s.out[0]), 0.0, float(s.out[1]))
	var fwd := Vector3.UP.cross(-o).normalized()  # lot on the driver's right
	var best := -1
	var best_d := INF
	for n in sim.region_links:
		if not sim.network.nodes.has(n):
			continue
		var to: Vector3 = sim.network.nodes[n] - pos
		to.y = 0.0
		if to.normalized().dot(fwd) > 0.2 and to.length() < best_d:
			best_d = to.length()
			best = n
	if best == -1:
		return sim.logistics._edge(sim, pos)
	return {"ref": "edge", "pos": Logistics._xz(sim.network.nodes[best])}


func _leave_all(sim: CitySim, ref: String) -> void:
	_leave(sim, ref, "delivery")
	_leave(sim, ref, "crew")


func _has_crew(ref: String) -> bool:
	for p in sites[ref].parked:
		if p.job == "crew":
			return true
	return _crew_coming.has(ref)


func _inbound(ref: String) -> bool:
	for id in trips:
		if trips[id].ref == ref and trips[id].inbound:
			return true
	return false


## The contractor's yard: the town's oldest shop if it has one (a local
## builder), otherwise a crew from the next town over, by the highway.
func _crew_base(sim: CitySim, s: Dictionary) -> Dictionary:
	if _yard == null:
		_yard = _find_yard(sim)
	if not _yard.is_empty():
		return _yard
	return sim.logistics._edge(sim, _pos(s))


## The town's oldest finished shop, as a trip end ({} if it has none).
func _find_yard(sim: CitySim) -> Dictionary:
	var best := ""
	var best_t := 1 << 62
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if b.zone == ZoneMap.Zone.COMMERCIAL and sim.lots.has(key) and is_done("lot:" + key, sim.tick_count):
			if int(b.built) < best_t or int(b.built) == best_t and key < best:
				best_t = int(b.built)
				best = key
	if best != "":
		var f: Vector3 = sim.lots[best].front
		return {"ref": "lot:" + best, "pos": [snappedf(f.x, 0.01), snappedf(f.z, 0.01)]}
	return {}


## Where trucks stop: the site's own lot.
static func _curb(ref: String, s: Dictionary) -> Dictionary:
	return {"ref": ref, "pos": s.front}


static func _kind(kind: String) -> String:
	while not VehicleTypes.SPECS.has(kind) and FALLBACK.has(kind):
		kind = FALLBACK[kind]
	return kind if VehicleTypes.SPECS.has(kind) else "work_pickup"


static func _pos(s: Dictionary) -> Vector3:
	return Vector3(float(s.front[0]), 0.0, float(s.front[1]))


static func _exists(sim: CitySim, ref: String) -> bool:
	var i := ref.find(":")
	var what := ref.substr(0, i)
	var id := ref.substr(i + 1)
	match what:
		"lot": return sim.buildings.has(id)
		"svc": return sim.services.buildings.has(int(id))
		"wh": return sim.warehouses.buildings.has(int(id))
		"farm": return sim.farms.farms.has(int(id))
		"hub": return sim.hubs.hubs.has(int(id))
		"park": return sim.parks.sites.has(int(id))
		"ind": return sim.industry.sites.has(int(id))
		"subdiv":
			var a = sim.subdivisions.active.get(int(id.get_slice(":", 0)))
			return a != null and a.has("works") and int(a.works.k) == int(id.get_slice(":", 1))
	return false


func to_dict() -> Dictionary:
	var t := {}
	for id in trips:
		t[str(id)] = trips[id]
	return {"sites": sites.duplicate(true), "trips": t}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	trips.clear()
	var ss: Dictionary = d.get("sites", {})
	for ref in ss:
		var s: Dictionary = ss[ref]
		sites[ref] = {"profile": str(s.profile) if PROFILES.has(str(s.profile)) else "house",
			"start": int(s.start), "front": [float(s.front[0]), float(s.front[1])],
			"out": [float(s.out[0]), float(s.out[1])], "to_curb": float(s.to_curb),
			"stage": int(s.stage), "parked": (s.parked as Array).duplicate(true), "yard": int(s.get("yard", -1)),
			"got": (s.get("got", []) as Array).duplicate()}
	var tt: Dictionary = d.get("trips", {})
	for id in tt:
		var t: Dictionary = tt[id]
		for f in ["until", "yard"]:
			if t.has(f):
				t[f] = int(t[f])  # whole numbers again after a JSON copy
		trips[int(id)] = t
