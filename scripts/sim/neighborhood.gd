class_name Neighborhood
extends RefCounted
## How well a neighborhood is doing, for anything that fills in by itself
## (Brawn's rule, 2026-10-22: a thriving area grows a curated park, a
## struggling one a worn park). A score from 0 to 1 is made from the homes
## within Balance.HOOD_RADIUS, and turns into a tier (struggling, working
## class, comfortable, thriving). Character follows the numbers slowly, so
## each place keeps a memory of what its neighborhood has been.
## Plain data and pure functions, so the simulation stays deterministic.

const TIERS := Balance.HOOD_TIERS


## The score the area around `pos` is heading for, with its parts:
## {score, land_value, services, employment, occupancy, homes, residents}.
## `amenity` is the land value lift there from parks and landmarks.
static func target(sim: CitySim, pos: Vector3, amenity: float) -> Dictionary:
	var occ := 0
	var cap := 0
	var cover := 0.0
	var homes := 0
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		if sim.lots[key].pos.distance_to(pos) > Balance.HOOD_RADIUS:
			continue
		homes += 1
		occ += int(b.occ)
		cap += int(b.cap)
		cover += sim.services.coverage(key)
	var workers: int = sim.stats.get("workers", 0)
	var parts := {
		"land_value": clampf(Balance.HOOD_LAND_BASE + (amenity + sim.telecom.lift_at(sim, pos) + sim.regional.land_lift()) * Balance.AMENITY_LAND_SCALE,
			0.0, 1.0),
		"services": cover / homes if homes > 0 else 0.0,
		"employment": float(sim.stats.get("employed", 0)) / workers if workers > 0 else 0.5,
		"occupancy": float(occ) / cap if cap > 0 else 0.0,
	}
	var score := 0.0
	for k in Balance.HOOD_WEALTH_WEIGHTS:
		score += parts[k] * Balance.HOOD_WEALTH_WEIGHTS[k]
	parts["score"] = clampf(score, 0.0, 1.0)
	parts["homes"] = homes
	parts["residents"] = occ
	return parts


## Moves a score toward its target over `days` game days: half the gap closes
## every HOOD_HALF_LIFE_DAYS, faster on the way down.
static func follow(score: float, goal: float, days: float) -> float:
	var half := Balance.HOOD_HALF_LIFE_DAYS * (Balance.HOOD_DECLINE_SPEED if goal < score else 1.0)
	return goal + (score - goal) * pow(0.5, days / half)


## The tier (index into TIERS) for a score, given the tier it had: it only
## moves once the score is past the line by HOOD_TIER_MARGIN.
static func tier_for(score: float, current: int) -> int:
	var raw := 0
	for i in TIERS.size():
		if score >= float(TIERS[i].min):
			raw = i
	if current < 0:
		return raw
	var t := current
	while t < TIERS.size() - 1 and score >= float(TIERS[t + 1].min) + Balance.HOOD_TIER_MARGIN:
		t += 1
	while t > 0 and score < float(TIERS[t].min) - Balance.HOOD_TIER_MARGIN:
		t -= 1
	return t
