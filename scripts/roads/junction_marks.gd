class_name JunctionMarks
extends RefCounted
## The rule book for the paint at a town junction, drawn the moment the
## junction is built or changed, from its real corners (Junction.plan), so
## skewed, Y, T, offset and five-way junctions all come out the same way:
##
## - A crosswalk across a leg (style(), below), in line with its curb ramps: two solid
##   white transverse lines 10 in wide with 6.2 ft between them (Indiana
##   MUTCD 3B.17: lines 6 to 24 in wide, at least 6 ft apart), square to
##   the leg wherever it points, curb to curb.
## - A 24 in stop line across the approach lanes of every leg that stops
##   (a stop sign or a signal), 4 ft before the crosswalk (3B.16).
## - A yield line on a leg that yields: white triangles 24 in wide and
##   36 in long, 12 in apart, pointing at the drivers (3B.16).
## - Centre, lane, bike and bus lines end at the crosswalk (3B.08: lines
##   are not carried through the junction as solid lines).
##
## A leg too short to fit them all gets what fits: the crosswalk first.
## Junctions that aren't shaped (country roads, one-ways, ramps) keep
## JunctionView's simple marks.
##
## Not every leg is painted alike (Nathan, 2026-10-29: "every intersection
## is exactly the same shape"). Given the junction's traffic control, each
## leg's crosswalk is one of (style()):
## - "continental": high-visibility bars 24 in wide and 24 in apart, along
##   the road (MUTCD 3B.18, Figure 3B-19), at signals on main streets and
##   avenues, where towns put them.
## - "lines": the two transverse lines.
## - "none": no paint (the crosswalk is still there in law, unmarked, as at
##   most quiet residential corners; MUTCD 3B.18 leaves marking to the
##   town). Often no stop line either where a stop sign stands alone.
##   Always at an old corner with one diagonal ramp (Junction.ramps).
## None across a car-free street: people walk all of it.
## The paint is fresh, worn or a grey ghost of itself (wear()), more often
## worn in the old town, fresher at signals where it is redone with them.
## Where traffic stops does not change with the paint: cars stop at the
## stop line, painted or not (stop_back).

## Metres past where a leg's road starts (the end of its curb return).
const CROSS_NEAR := 0.3  # the crosswalk's first line, at the curb ramp
const CROSS_LINE := 0.25  # 10 in lines
const CROSS_FAR := 2.7  # the outside of its second line
const BAR_GAP := 1.2  # 4 ft
const BAR := 0.6  # 24 in
## Where traffic stops: the back of the stop line (TrafficSim.STOP_PAST_RETURN).
const STOP := CROSS_FAR + BAR_GAP + BAR
const TOOTH := 0.6  # yield triangle base
const TOOTH_GAP := 0.3


## True when the plan is a town junction of three or more legs (a plain
## corner, a bend or a country junction has no crosswalks).
static func marked(j: Dictionary) -> bool:
	return not j.is_empty() and not j.has("bend") and j.arms.size() >= 3 and not j.get("country", false) \
		and not j.get("unmarked", false)


## Country junctions have no crosswalks: a leg's stop line stands 4 ft
## before the edge line of the road it meets (MUTCD 3B.16: 4 to 30 ft from
## the edge of the traveled way), and never out on that road's pavement or
## shoulder; on a skewed leg, far enough back that its nearer end keeps the
## 4 ft. `j` needs only "arms" (Junction.arms_at, or a plan's). Metres from
## the node to the junction side of the stop line.
static func country_near(j: Dictionary, arm: Dictionary) -> float:
	var best := INF
	var lanes := country_lanes(arm)
	var span: float = lanes[1] - lanes[0]
	for o in j.arms:
		if o.seg == arm.seg:
			continue
		var s := absf((arm.u as Vector2).cross(o.u))
		if s < 0.35:
			continue  # running on the same way, not across it
		var need := maxf(RoadMesh.edge_line(o.type, o.get("country", true)) + BAR_GAP, o.hw + 0.3)
		var c := absf((arm.u as Vector2).dot(o.u))
		best = minf(best, (need + span * c) / s)
	if best == INF:
		best = arm.hw + BAR_GAP
	return best


## A country leg's approach lanes, [inner, outer] metres from its centre
## line: from beside the centre line out to its edge line.
static func country_lanes(arm: Dictionary) -> Array:
	var lanes := approach(arm.type)
	if arm.get("country", true):
		lanes[1] = maxf(minf(lanes[1], RoadMesh.edge_line(arm.type, true) - 0.15), lanes[0] + 1.0)
	return lanes


## Paints a country leg's stop line, square across its approach lanes.
static func country_bar(j: Dictionary, arm: Dictionary, st: SurfaceTool, y: float) -> void:
	var at := country_near(j, arm)
	var lanes := country_lanes(arm)
	Junction._band(st, j.center, arm, -1.0, lanes[0], lanes[1], at, at + BAR, y)


## How far out from a country leg's centre line its pavement reaches,
## `s` metres from the node, on its approach side (where its radius flares
## out to the road it meets), for standing a sign clear of it.
static func country_edge(j: Dictionary, arm: Dictionary, s: float) -> float:
	var e: float = arm.hw
	for c in j.get("corners", []):
		if not c.fillet or j.arms[c.b].seg != arm.seg or s >= c.tb:
			continue
		var r: float = c.r
		var k: float = c.tb - s
		e = maxf(e, arm.hw + r - sqrt(maxf(r * r - k * k, 0.0)) if k < r else arm.hw + r)
	return e


## What fits on a leg before the half-way point of its road: 0 nothing,
## 1 the crosswalk, 2 the crosswalk and a stop or yield line.
static func room(arm: Dictionary) -> int:
	var half: float = arm.length * 0.5
	if arm.d + STOP + 0.3 <= half:
		return 2
	if arm.d + CROSS_FAR <= half:
		return 1
	return 0


## How far past the junction's own trim a road's lines stop at this node:
## at the outside of the crosswalk, or 0 where there is none.
static func line_cut(plans: Dictionary, node: int, seg: int) -> float:
	var j: Dictionary = plans.get(node, {})
	if not marked(j):
		return 0.0
	for arm in j.arms:
		if arm.seg == seg:
			return CROSS_FAR if room(arm) >= 1 else 0.0
	return 0.0


## Metres from a junction's centre to where traffic on `seg` stops, at the
## back of its stop line; -1 when the junction has no painted stop line there.
static func stop_back(j: Dictionary, seg: int) -> float:
	if not marked(j):
		return -1.0
	for arm in j.arms:
		if arm.seg == seg and arm.d > 0.0 and room(arm) == 2:
			return arm.d + STOP
	return -1.0


## Continental crosswalk bars, 24 in wide with 24 in between.
const STRIPE := 0.6
const STRIPE_GAP := 0.6
## A ghost of a paint job: this share of it worn off to the asphalt, in
## pieces about a metre long.
const GHOST_GONE := 0.35
const GHOST_PIECE := 0.9


## A junction's traffic control as paint picks by it, from TrafficSim's
## junction ({} when it has none): "signal", "all_stop", "two_way" (stop or
## yield on the side roads) or "none".
static func control_of(tj: Dictionary) -> String:
	if tj.is_empty():
		return "none"
	match int(tj.control):
		TrafficSim.Rule.SIGNAL: return "signal"
		TrafficSim.Rule.ALL_STOP: return "all_stop"
		TrafficSim.Rule.PRIORITY: return "two_way"
	return "none"


## The crosswalk across one leg: "continental", "lines" or "none" (see the
## top). `rule` is the leg's ("stop", "yield", or "" where traffic goes on
## through); `closed`: segments closed to cars. With no control given (""),
## the plain rule book: two lines on every leg.
static func style(j: Dictionary, arm: Dictionary, rule: String, control: String, closed := {}) -> String:
	if closed.has(arm.seg):
		return "none"
	if control == "":
		return "lines"
	if Junction.ramps(j).any(func(r): return r[1] == "diagonal"):
		return "none"  # an old corner's one diagonal ramp lands outside any markings (ADA 406.6)
	var center: Vector3 = j.center
	var era: String = j.get("look", {}).get("era", "postwar")
	var main := false
	var big := false  # an avenue or bigger meets here
	for o in j.arms:
		main = main or o.type == RoadStyle.Type.MAIN_STREET
		big = big or RoadStyle.group(o.type) != RoadStyle.Type.STREET
	var r := Junction.roll(center, "walk %d" % j.arms.find(arm))
	var quiet: float = {"prewar": 0.35, "postwar": 0.5, "recent": 0.65}.get(era, 0.5)
	match control:
		"signal":
			if main or big:
				return "continental" if Junction.roll(center, "high vis") < (0.8 if main else 0.55) else "lines"
			return "lines"
		"all_stop":
			if main:
				return "continental" if Junction.roll(center, "high vis") < 0.5 else "lines"
			if big:
				return "lines"
			return "none" if r < quiet * 0.5 else "lines"
		"two_way":
			if main:
				return "lines"
			if rule == "":
				# Across the through road at a side street: often unmarked.
				if RoadStyle.group(arm.type) != RoadStyle.Type.STREET:
					return "lines" if r < 0.5 else "none"
				return "none" if r < 0.8 else "lines"
			if big:
				return "lines"
			return "none" if r < quiet else "lines"
	return "none" if r < 0.85 and not main else "lines"


## How worn a junction's paint is: 0 fresh, 1 worn, 2 a grey ghost. Fresh
## with no control given (the plain rule book).
static func wear(j: Dictionary, control: String) -> int:
	if control == "":
		return 0
	var era: String = j.get("look", {}).get("era", "postwar")
	var fresh: float = {"prewar": 0.3, "postwar": 0.4, "recent": 0.6}.get(era, 0.4)
	var ghost: float = {"prewar": 0.25, "postwar": 0.15, "recent": 0.05}.get(era, 0.15)
	if control == "signal" or j.arms.any(func(a): return a.type == RoadStyle.Type.MAIN_STREET):
		# Redone with the signal's upkeep, or for the downtown.
		fresh += 0.2
		ghost *= 0.5
	var r := Junction.roll(j.center, "paint")
	if r < fresh:
		return 0
	return 2 if r > 1.0 - ghost else 1


## Paints one junction into `st`. `rules`: seg -> "stop", "yield" or ""
## (no line, traffic goes on through). `control` (control_of) picks each
## leg's crosswalk and the paint's wear (drawn into `st` all the same: the
## caller picks the paint for wear()); "" paints every leg the plain way.
## No paint on a leg in `closed` (car-free).
static func paint(j: Dictionary, rules: Dictionary, st: SurfaceTool, y: float, control := "",
		closed := {}) -> void:
	if not marked(j):
		return
	var center: Vector3 = j.center
	var worn := wear(j, control)
	for i in j.arms.size():
		var arm: Dictionary = j.arms[i]
		var fits := room(arm)
		if fits == 0 or closed.has(arm.seg):
			continue
		var hw: float = arm.hw
		var d: float = arm.d
		var rule: String = rules.get(arm.seg, "")
		var kind := style(j, arm, rule, control, closed)
		var bits := [center, worn, "leg %d" % i]
		if kind == "lines":
			for at in [d + CROSS_NEAR, d + CROSS_FAR - CROSS_LINE]:
				_piece(st, arm, bits, 1.0, -hw, hw, at, at + CROSS_LINE, y)
		elif kind == "continental":
			# Bars along the road, centred on it, curb to curb.
			var n := int((2.0 * hw + STRIPE_GAP) / (STRIPE + STRIPE_GAP))
			var o := -hw + (2.0 * hw - (n * STRIPE + (n - 1) * STRIPE_GAP)) * 0.5
			for k in n:
				var o0 := o + k * (STRIPE + STRIPE_GAP)
				_piece(st, arm, bits, 1.0, o0, o0 + STRIPE, d + CROSS_NEAR, d + CROSS_FAR, y)
		if fits < 2 or rule == "":
			continue
		if kind == "none" and control != "signal" and Junction.roll(center, "bar %d" % i) < 0.45:
			continue  # a stop sign alone, no line (MUTCD 3B.16: a stop line is optional there)
		var lanes := approach(arm.type)
		var at := d + CROSS_FAR + BAR_GAP
		if rule == "yield":
			_teeth(st, center, arm, lanes[0], lanes[1], at, y)
		else:
			# Drivers arrive on the leg's -n side (they keep right).
			_piece(st, arm, bits, -1.0, lanes[0], lanes[1], at, at + BAR, y)


## A band of paint (Junction._band, about the junction's centre), or what
## is left of it on a ghost: pieces across it worn away, picked by the
## junction's own hash. `bits`: [centre, wear, a name for the leg].
static func _piece(st: SurfaceTool, arm: Dictionary, bits: Array, side: float, o0: float, o1: float,
		from: float, to: float, y: float) -> void:
	var center: Vector3 = bits[0]
	if bits[1] < 2:
		Junction._band(st, center, arm, side, o0, o1, from, to, y)
		return
	var n := maxi(1, roundi((o1 - o0) / GHOST_PIECE))
	for k in n:
		if Junction.roll(center, "%s %s %.1f %d" % [bits[2], side, from, k]) < GHOST_GONE:
			continue
		Junction._band(st, center, arm, side, lerpf(o0, o1, float(k) / n), lerpf(o0, o1, float(k + 1) / n), from, to, y)


## The approach lanes' span from the centre line, [inner, outer] metres:
## from the centre line (or median) out to the curb, or to the parking lane.
static func approach(type: int) -> Array:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hm: float = spec.median * 0.5
	var inner := 0.1
	if RoadStyle.raised_median(type):
		inner = hm + RoadStyle.CURB_WIDTH
	elif hm > 0.0:
		inner = hm
	elif spec.lanes > 2 or spec.get("bike", false) or spec.get("angle", false):
		inner = 0.3  # beside the double yellow
	var outer := RoadStyle.half_width(type) - maxf(RoadStyle.parking_width(type), 0.15)
	return [inner, maxf(outer, inner + 1.0)]


## A yield line: a row of triangles across the approach lanes, bases on
## the junction side, points toward the drivers coming up to it.
static func _teeth(st: SurfaceTool, center: Vector3, arm: Dictionary, o0: float, o1: float, at: float, y: float) -> void:
	var near: Array = LotPlanner.point_at(arm.pts, at)
	var far: Array = LotPlanner.point_at(arm.pts, at + TOOTH * 1.5)
	var n := maxi(1, int((o1 - o0 + TOOTH_GAP) / (TOOTH + TOOTH_GAP)))
	var used := n * TOOTH + (n - 1) * TOOTH_GAP
	var o := o0 + (o1 - o0 - used) * 0.5
	for k in n:
		var a := _off(center, near, -(o + k * (TOOTH + TOOTH_GAP)))
		var b := _off(center, near, -(o + k * (TOOTH + TOOTH_GAP) + TOOTH))
		var tip := _off(center, far, -(o + k * (TOOTH + TOOTH_GAP) + TOOTH * 0.5))
		Junction._tri(st, center, [a, b, tip], y)


## A point `off` metres along the leg's n side from a point on it, about
## the junction centre.
static func _off(center: Vector3, at: Array, off: float) -> Vector2:
	var p: Vector3 = at[0]
	var dir := Vector2(at[1].x, at[1].z).normalized()
	return Vector2(p.x - center.x, p.z - center.z) + Vector2(-dir.y, dir.x) * off
