class_name JunctionMarks
extends RefCounted
## The rule book for the paint at a town junction, drawn the moment the
## junction is built or changed, from its real corners (Junction.plan), so
## skewed, Y, T, offset and five-way junctions all come out the same way:
##
## - A crosswalk across every leg, in line with its curb ramps: two solid
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


## True when the plan is a junction of three or more legs (a plain corner
## or a bend has no crosswalks).
static func marked(j: Dictionary) -> bool:
	return not j.is_empty() and not j.has("bend") and j.arms.size() >= 3


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


## Paints one junction into `st`. `rules`: seg -> "stop", "yield" or ""
## (no line, traffic goes on through).
static func paint(j: Dictionary, rules: Dictionary, st: SurfaceTool, y: float) -> void:
	if not marked(j):
		return
	var center: Vector3 = j.center
	for arm in j.arms:
		var fits := room(arm)
		if fits == 0:
			continue
		var hw: float = arm.hw
		var d: float = arm.d
		for at in [d + CROSS_NEAR, d + CROSS_FAR - CROSS_LINE]:
			Junction._band(st, center, arm, 1.0, -hw, hw, at, at + CROSS_LINE, y)
		var rule: String = rules.get(arm.seg, "")
		if fits < 2 or rule == "":
			continue
		var lanes := approach(arm.type)
		var at := d + CROSS_FAR + BAR_GAP
		if rule == "yield":
			_teeth(st, center, arm, lanes[0], lanes[1], at, y)
		else:
			# Drivers arrive on the leg's -n side (they keep right).
			Junction._band(st, center, arm, -1.0, lanes[0], lanes[1], at, at + BAR, y)


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
