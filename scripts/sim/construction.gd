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
## pickup comes for the whole job, each stage brings its own truck (a dump
## truck to dig, concrete for the footings, lumber or steel on a flatbed,
## roofing, siding, the trades' vans, topsoil), and each one parks at the
## curb in front of the site and later drives back out. Nothing vanishes.
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
	"house": {"frame": "wood", "weeks": [1, 3, 4, 3, 4, 11, 2], "found": 0.45,
		"words": ["Clearing the lot", "Pouring the foundation", "Framing", "Sheathing and roofing",
			"Siding and trim", "Finishing inside", "Landscaping"]},
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
}
## What each stage sends: [vehicle kind, cargo] (the crew's pickup comes for
## the whole job). A kind the fleet doesn't have yet falls back to the next.
const DELIVERIES := {
	"clear": [["dump_truck", "fill dirt"]],
	"foundation": [["concrete_mixer", "ready-mix concrete"], ["dump_truck", "gravel"]],
	"frame": [["flatbed", "framing package"]],
	"dry_in": [["box_truck", "roofing and sheathing"]],
	"exterior": [["box_truck", "siding and windows"]],
	"interior": [["van", "trades"]],
	"landscape": [["dump_truck", "topsoil and sod"]],
}
const FALLBACK := {"concrete_mixer": "dump_truck"}
## The steel goes up on a flatbed too, but a different load.
const FRAME_CARGO := {"wood": "framing lumber", "steel": "structural steel", "tilt_up": "rebar and forms",
	"pole": "posts and trusses"}
## Ticks between checks on the sites (a game hour has 60).
const EVERY := 10
## Most vehicles parked at one site's curb at once.
const MAX_PARKED := 3

## ref -> {profile, start (tick), front [x, z], out [x, z] (toward the street),
## to_curb, stage (last stage it sent trucks for), parked: [{kind, job, cargo}]}
var sites := {}
## Traffic trip id -> {ref, kind, job, cargo, inbound}
var trips := {}


## A new building starts going up. `front` is the middle of its street edge,
## `out` points from it toward the street, `to_curb` is how far the curb is.
func start(ref: String, profile: String, tick: int, front: Vector3, out: Vector3, to_curb: float) -> void:
	if not PROFILES.has(profile):
		profile = "house"
	sites[ref] = {"profile": profile, "start": tick, "front": [snappedf(front.x, 0.01), snappedf(front.z, 0.01)],
		"out": [snappedf(out.x, 0.001), snappedf(out.z, 0.001)], "to_curb": to_curb, "stage": -1, "parked": []}


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


func is_done(ref: String, tick: int) -> bool:
	return state(ref, tick).is_empty()


func tick(sim: CitySim) -> void:
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			_arrive(trips[a.id])
			trips.erase(a.id)
	for f in sim.traffic.failed:
		trips.erase(f.id)  # it never got there: nothing to park
	if sim.tick_count % EVERY != 0:
		return
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
			s.stage = stage
			_leave(sim, ref, "delivery")  # the last stage's trucks head off
			if stage >= STAGES.size():
				_leave_all(sim, ref)
			elif sim.simulate_traffic:
				if not _has_crew(ref):
					_send(sim, ref, "work_pickup", "crew", "building crew", _crew_base(sim, s))
				for d in DELIVERIES[STAGES[stage]]:
					var cargo: String = d[1]
					if STAGES[stage] == "frame" and d[0] == "flatbed":
						cargo = FRAME_CARGO[PROFILES[s.profile].frame]
					_send(sim, ref, d[0], "delivery", cargo, sim.logistics._edge(sim, _pos(s)))
		elif s.parked.size() > 0 and st.get("t", 0.0) > 0.5:
			_leave(sim, ref, "delivery")  # dropped off: back out halfway through
		if stage >= STAGES.size():
			_leave_all(sim, ref)
			if s.parked.is_empty() and not _inbound(ref):
				sites.erase(ref)


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
			out.append([kind, Transform3D(Basis.looking_at(fwd, Vector3.UP), curb + fwd * along), hash([ref, i])])
			along -= len + 1.5
	return out


func _send(sim: CitySim, ref: String, kind: String, job: String, cargo: String, base: Dictionary) -> void:
	if base.is_empty():
		return
	kind = _kind(kind)
	var s: Dictionary = sites[ref]
	var to := {"ref": ref, "pos": s.front}
	var id: int = sim.traffic.dispatch(base, to, "construction", {"good": cargo, "amount": 1}, kind)
	if id != -1:
		trips[id] = {"ref": ref, "kind": kind, "job": job, "cargo": cargo, "inbound": true}


func _arrive(t: Dictionary) -> void:
	if not t.inbound or not sites.has(t.ref):
		return
	var s: Dictionary = sites[t.ref]
	if s.parked.size() < MAX_PARKED:
		s.parked.append({"kind": t.kind, "job": t.job, "cargo": t.cargo})


## Parked vehicles doing `job` drive away (to the highway, or the crew home).
func _leave(sim: CitySim, ref: String, job: String) -> void:
	var s: Dictionary = sites[ref]
	var keep := []
	for p in s.parked:
		if p.job != job:
			keep.append(p)
			continue
		var dest := _crew_base(sim, s) if job == "crew" else sim.logistics._edge(sim, _pos(s))
		var id := -1
		if not dest.is_empty() and sim.simulate_traffic:
			id = sim.traffic.dispatch({"ref": ref, "pos": s.front}, dest, "construction",
				{"good": "empty" if job != "crew" else "crew going home", "amount": 0}, p.kind)
		if id == -1:
			keep.append(p)  # no way out yet: it waits at the curb
		else:
			trips[id] = {"ref": ref, "kind": p.kind, "job": job, "cargo": "", "inbound": false}
	s.parked = keep


func _leave_all(sim: CitySim, ref: String) -> void:
	_leave(sim, ref, "delivery")
	_leave(sim, ref, "crew")


func _has_crew(ref: String) -> bool:
	for p in sites[ref].parked:
		if p.job == "crew":
			return true
	for id in trips:
		if trips[id].ref == ref and trips[id].job == "crew" and trips[id].inbound:
			return true
	return false


func _inbound(ref: String) -> bool:
	for id in trips:
		if trips[id].ref == ref and trips[id].inbound:
			return true
	return false


## The contractor's yard: the town's oldest shop if it has one (a local
## builder), otherwise a crew from the next town over, by the highway.
func _crew_base(sim: CitySim, s: Dictionary) -> Dictionary:
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
	return sim.logistics._edge(sim, _pos(s))


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
			"stage": int(s.stage), "parked": (s.parked as Array).duplicate(true)}
	var tt: Dictionary = d.get("trips", {})
	for id in tt:
		trips[int(id)] = tt[id]
