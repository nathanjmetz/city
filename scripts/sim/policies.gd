class_name Policies
extends RefCounted
## The town's broad sliders (Brawn, 2026-10-22: money is a limiter, not the
## game; nobody wants to do their taxes). Taxes run at normal rates on their
## own. Instead the player sets two sliders, each with five steps:
##   Funding: Lean, Thrifty, Standard, Well funded, Generous
##   Growth:  Hold, Slow, Your call, Grow, Expand
## at three levels: the whole town, an area (homes, farms, waste...) and a
## single hub. A hub follows its area and an area the town until it is given
## its own setting. What each step does is in Balance (POLICY_*); a campus
## reads its Funding step as its EDUCATION_FUNDING_LEVELS index.
##
## Growth on a hub is also the player's word to its leader (Permits): Hold is
## "hold", Grow and Expand are "grow", the rest "steady". CitySim keeps the
## two in step.

signal changed

const SLIDERS := ["funding", "growth"]
const STEP_NAMES := {
	"funding": ["Lean", "Thrifty", "Standard", "Well funded", "Generous"],
	"growth": ["Hold", "Slow", "Your call", "Grow", "Expand"],
}
const STEP_TIPS := {
	"funding": ["Spend as little as possible", "Trim the extras", "A normal budget",
		"A little extra", "Spare no expense"],
	"growth": ["No new land or buildings for now", "Grow only when it clearly pays",
		"Let them decide", "Grow when it makes sense", "Grow whenever there's a chance"],
}
const STANDARD := 2
## The town's areas, in the order the Economy page lists them. `sliders` says
## which of the two apply (city services don't buy land, so no Growth).
const AREAS := {
	"homes": {"name": "Homes", "icon": "homes", "sliders": ["funding", "growth"],
		"funding": "Street care, trees and upkeep. Better kept streets are worth more.",
		"growth": "How readily new homes go up."},
	"shops": {"name": "Shops", "icon": "shops", "sliders": ["funding", "growth"],
		"funding": "Main street care and upkeep.", "growth": "How readily new shops open."},
	"factories": {"name": "Factories", "icon": "industry", "sliders": ["funding", "growth"],
		"funding": "Inspections and upkeep around the plants.", "growth": "How readily new factories open."},
	"farms": {"name": "Farms", "icon": "farms", "sliders": ["funding", "growth"],
		"funding": "A fee on farmland (Lean) or farm aid (Generous).",
		"growth": "How eagerly farmers buy more fields."},
	"resources": {"name": "Oil, ore and timber", "icon": "industry", "sliders": ["funding", "growth"],
		"funding": "A fee on the companies (Lean) or business aid (Generous).",
		"growth": "How eagerly companies open new pads."},
	"warehouses": {"name": "Warehouses", "icon": "warehouse", "sliders": ["growth"],
		"growth": "Your word to their owners: how readily they add bays. They're private, so the town doesn't fund them."},
	"big": {"name": "Big factories", "icon": "industry", "sliders": ["growth"],
		"growth": "Your word to their owners: how readily they add lines and buy the land behind them. They're private, so the town doesn't fund them."},
	"power": {"name": "Power companies", "icon": "power", "sliders": ["growth"],
		"growth": "Your word to their owners: Hold adds no new units. They sell power, so the town doesn't fund them."},
	"utilities": {"name": "Substations and wells", "icon": "power", "sliders": ["funding"],
		"funding": "Upkeep, and how many homes each one serves."},
	"water": {"name": "Water and sewer", "icon": "water", "sliders": ["funding", "growth"],
		"funding": "The town's monthly subsidy to the utility, on top of water bills.",
		"growth": "Your word to the manager: hold off, their call, or grow."},
	"mail": {"name": "Post offices", "icon": "mail", "sliders": ["funding", "growth"],
		"funding": "What the town adds to postage each month, for the postmaster to build with.",
		"growth": "Your word to the postmaster: hold off, their call, or grow."},
	"telecom": {"name": "Phone company", "icon": "tower", "sliders": ["funding", "growth"],
		"funding": "The town's broadband grant. A bigger grant lets the manager plan further ahead.",
		"growth": "Your word to the manager: hold off, their call, or grow."},
	"taxis": {"name": "Taxis", "icon": "taxi", "sliders": ["growth"],
		"growth": "Your word to the owners: how readily they add cabs and bays. They run on fares, so the town doesn't fund them."},
	"transit": {"name": "Bus depots", "icon": "bus", "sliders": ["funding", "growth"],
		"funding": "The town's monthly subsidy. It decides how many buses run.",
		"growth": "Your word to the depot manager: hold off, their call, or grow."},
	"public": {"name": "Public services", "icon": "services", "sliders": ["funding"],
		"funding": "Upkeep, and how far each one reaches."},
	"waste": {"name": "Garbage and recycling", "icon": "landfill", "sliders": ["funding", "growth"],
		"funding": "Upkeep, and how many trucks they run.",
		"growth": "How soon a busy site takes more land."},
	"cemetery": {"name": "Cemeteries", "icon": "cemetery", "sliders": ["funding", "growth"],
		"funding": "Upkeep and groundskeeping.", "growth": "How far ahead they plan for more land."},
	"parks": {"name": "Parks and landmarks", "icon": "parks", "sliders": ["funding", "growth"],
		"funding": "Upkeep, and how much they lift the land around them.",
		"growth": "How soon a busy park buys the land next door."},
	"schools": {"name": "Schools and colleges", "icon": "school", "sliders": ["funding", "growth"],
		"funding": "What the town pays them each month. Better funded, they teach better.",
		"growth": "Your word to their heads: hold off, their call, or grow."},
	"health": {"name": "Health and care", "icon": "health", "sliders": ["funding", "growth"],
		"funding": "The hospital levy and upkeep, and how far each one reaches.",
		"growth": "Your word to the hospital's administrator: hold off, their call, or grow."},
	"banks": {"name": "Banks", "icon": "bank", "sliders": ["growth"],
		"growth": "Your word to their presidents: how freely they lend and grow. Banks are private, so the town doesn't fund them."},
}

## What the player has set: scope -> {slider: step}. Scope is "city",
## "area:<key>" or a hub, "<kind>:<id>" (farm:3, industry:2, service:5, hub:1,
## park:2, campus:1, post_office:1, water:4, bus_depot:6, power:2, warehouse:3, hospital:4).
var levels := {}


## The step in force for a hub (or "" for none) in an area: its own, else
## the area's, else the town's.
func step(slider: String, area: String, hub := "") -> int:
	for scope in [hub, "area:" + area, "city"]:
		if scope != "" and levels.has(scope) and levels[scope].has(slider):
			return int(levels[scope][slider])
	return STANDARD


## The step set on exactly this scope, or -1 if it follows the one above.
func own(scope: String, slider: String) -> int:
	return int(levels.get(scope, {}).get(slider, -1))


## A Balance list's value for the step in force.
func pick(list: Array, slider: String, area: String, hub := "") -> float:
	return float(list[step(slider, area, hub)])


## Sets a slider (step -1 goes back to following the scope above). Returns
## true if anything changed.
func set_step(scope: String, slider: String, s: int) -> bool:
	if not slider in SLIDERS or s < -1 or s >= STEP_NAMES[slider].size() or not _valid(scope):
		return false
	if own(scope, slider) == s:
		return false
	if s == -1:
		levels[scope].erase(slider)
		if levels[scope].is_empty():
			levels.erase(scope)
	else:
		if not levels.has(scope):
			levels[scope] = {}
		levels[scope][slider] = s
	changed.emit()
	return true


## Clears every hub's own settings in an area (or every area's and hub's
## for "city"), so they all follow it again.
func reset_below(scope: String, hub_area: Callable) -> bool:
	var hit := false
	for k in levels.keys():
		if k == "city" or k == scope:
			continue
		var below: bool = scope == "city" or (not k.begins_with("area:") and hub_area.call(k) == scope.trim_prefix("area:"))
		if below:
			levels.erase(k)
			hit = true
	if hit:
		changed.emit()
	return hit


## The leader stance a growth step stands for (see Permits.STANCES).
static func stance(growth: int) -> String:
	return "hold" if growth == 0 else ("grow" if growth >= 3 else "steady")


## The growth step a leader stance means (Slow and Your call are both
## "steady", so a steady stance keeps Slow).
static func growth_for(stance_name: String, now: int) -> int:
	match stance_name:
		"hold":
			return 0
		"grow":
			return now if now >= 3 else 3
	return now if now in [1, 2] else 2


## Forgets a hub that's gone.
func forget(hub: String) -> void:
	if levels.erase(hub):
		changed.emit()


static func _valid(scope: String) -> bool:
	if scope == "city":
		return true
	if scope.begins_with("area:"):
		return AREAS.has(scope.trim_prefix("area:"))
	var parts := scope.split(":")
	return parts.size() == 2 and parts[0] != "" and parts[1].is_valid_int()


func to_dict() -> Dictionary:
	return levels.duplicate(true)


func from_dict(d: Dictionary) -> void:
	levels.clear()
	for scope in d:
		var v: Dictionary = d[scope]
		var out := {}
		for slider in SLIDERS:
			if v.has(slider):
				out[slider] = clampi(int(v[slider]), 0, STEP_NAMES[slider].size() - 1)
		if not out.is_empty() and _valid(str(scope)):
			levels[str(scope)] = out
	changed.emit()
