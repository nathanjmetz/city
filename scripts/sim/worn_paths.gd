class_name WornPaths
extends RefCounted
## Worn dirt paths (Brawn's pick, 2026-10-29, after Manor Lords' roads that
## people walk into being). Where people walk along a road with no sidewalk
## (a county road out to the grocery, a gravel road to the next farm, a
## state highway's shoulder), their feet wear a dirt path into the grass
## beside it, the "desire line" every town has that tells the town where a
## sidewalk belongs. It deepens with use, grows back in a season or two once
## people stop, and is gone when the road gets sidewalks.
##
## Real: trampling studies on grass (Cole and Bayfield; Cole 1995) find the
## cover thinning after a few hundred passes and worn to bare ground after
## several hundred more; grass grows back over a season once left alone.
##
## Light: TrafficSim notes each walk it plans along a road without
## sidewalks (note), and once a month they're added up here.

signal changed

## Wear on each side of each road: segment * 2 + (1 on the right, 0 on the
## left) -> passes a month (real ones: a sim day of walks is one day of the
## month, so it counts for Balance.WORN_DAYS of them), with last months'
## worn down by Balance.WORN_REGROW.
var wear := {}
## Walks along each side this month (same keys). Saved.
var foot := {}


## A walk planned along one side of a road (TrafficSim). Only roads with no
## sidewalk wear in.
func note(net: RoadNetwork, seg: int, side: int) -> void:
	if not net.segments.has(seg) or RoadStyle.TYPES[net.segments[seg].type].get("walk", true):
		return
	var k := seg * 2 + (1 if side > 0 else 0)
	foot[k] = int(foot.get(k, 0)) + 1


## Once a game month: this month's walks wear in, last month's grow back.
func month(sim) -> void:
	var out := {}
	var keys := wear.keys()
	for k in foot:
		if not wear.has(k):
			keys.append(k)
	for k in keys:
		var seg: int = int(k) >> 1
		if not sim.network.segments.has(seg) or RoadStyle.TYPES[sim.network.segments[seg].type].get("walk", true):
			continue  # the road's gone, or has sidewalks now
		var w: float = float(wear.get(k, 0.0)) * Balance.WORN_REGROW + float(foot.get(k, 0)) * Balance.WORN_DAYS
		if w >= Balance.WORN_GONE:
			out[k] = snappedf(w, 0.1)
	foot.clear()
	if out != wear:
		wear = out
		changed.emit()


## How worn a side of a road is, 0 (grass) to 1 (bare dirt); 0 under
## Balance.WORN_SHOW.
func level(key: int) -> float:
	var w := float(wear.get(key, 0.0))
	if w < Balance.WORN_SHOW:
		return 0.0
	return clampf((w - Balance.WORN_SHOW) / (Balance.WORN_BARE - Balance.WORN_SHOW), 0.0, 1.0) * 0.75 + 0.25


## How far from a road's centre line the worn path runs: just off the edge
## of the road and its gravel shoulder, in the grass.
static func offset(type: int) -> float:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var edge := RoadStyle.half_width(type)
	if spec.get("surface", "asphalt") == "asphalt" and not spec.has("shoulder"):
		edge += Junction.SHOULDER
	return edge + Balance.WORN_WIDTH * 0.5 + 0.1


func to_dict() -> Dictionary:
	var out := {}
	for k in wear:
		out[str(k)] = wear[k]
	var f := {}
	for k in foot:
		f[str(k)] = foot[k]
	return {"wear": out, "foot": f}


func from_dict(d: Dictionary) -> void:
	wear.clear()
	for k in d.get("wear", {}):
		wear[int(k)] = float(d.wear[k])
	foot.clear()
	for k in d.get("foot", {}):
		foot[int(k)] = int(d.foot[k])
	changed.emit()
