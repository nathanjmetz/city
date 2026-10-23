class_name TownCulture
extends RefCounted
## What the town is known for, and the nickname it earns (Brawn, 2026-10-23).
## The CORE PILLAR: hub leaders plus a culture that drifts let a town change
## identity on its own, with the player in control through the bell.
##
## Culture is a share for each of Balance.CULTURE_AXES (farm, industry,
## trade, office, college, heritage). It follows where the town's people work,
## slowly (a reputation lags what a place has become), plus a lean from the
## player's answers to leaders: say yes to the bank and the town leans toward
## offices; say no to tearing down an old block and it leans toward heritage.
##
## The culture feeds back, so identity can shift on its own: owners on new
## lots lean toward the town's kind of building (tilt()), and leaders of the
## town's kind are keener to build (boost()).
##
## Nicknames follow real ones: Elkhart is the "RV Capital of the World",
## Bedford the "Limestone Capital of the World", Crawfordsville the "Athens of
## Indiana", and the state motto is "The Crossroads of America". A nickname is
## earned once the town is big enough and one culture leads; it changes only
## when another leads it by NICKNAME_SWITCH, and old ones are remembered.
##
## Monthly and O(buildings): no per-tick cost. Deterministic and saved.

signal changed

const AXES := Balance.CULTURE_AXES
## Plain words for each culture, for the Town panel.
const AXIS_NAMES := {"farm": "Farming", "industry": "Industry", "trade": "Shops and Main Street",
	"office": "Offices and banking", "college": "College", "heritage": "History"}
## The county the real map sits in (Petersburg, Pike County, Indiana).
const COUNTY := "Pike County"
const VALLEY := "the White River Valley"

## Smoothed share for each axis (sums to about 1).
var mix := {}
## The lean from the player's answers, by axis (fades).
var lean := {}
## The nickname now: {"text", "axis", "since"} (since: calendar year), or {}.
var nickname := {}
## Earlier nicknames: [{"text", "from", "to"}], oldest first.
var past := []
## The tick a festival lifts shop demand until (LeaderAsks).
var festival_until := -1


func _init() -> void:
	for a in AXES:
		mix[a] = 0.0
		lean[a] = 0.0


## Once a game month: culture drifts toward the jobs, leans fade, and the
## nickname is checked.
func month(sim) -> void:
	var raw := shares(sim)
	var k := pow(0.5, 1.0 / Balance.CULTURE_HALF_LIFE_DAYS)
	var first := true
	for a in AXES:
		if float(mix[a]) > 0.0:
			first = false
	for a in AXES:
		lean[a] = _cents4(float(lean[a]) * k)
		var goal := clampf(float(raw[a]) + float(lean[a]), 0.0, 1.0)
		# A brand-new town starts out as what it is.
		mix[a] = _cents4(goal if first else goal + (float(mix[a]) - goal) * k)
	_name_it(sim)


## Where the town's people work, as shares by axis (0 to 1, summing to 1;
## all zero before anyone works).
static func shares(sim) -> Dictionary:
	var jobs := {}
	for a in AXES:
		jobs[a] = 0.0
	jobs.farm = float(sim.farms.jobs())
	jobs.industry = float(sim.industry.jobs() + sim.warehouses.jobs() + sim.power.jobs() + sim.rail.jobs())
	jobs.office = float(sim.banks.jobs())
	jobs.college = float(sim.education.jobs())
	var homes := ZoneMap.Zone.RESIDENTIAL
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) == homes:
			continue
		match BuildingTypes.type_of(b):
			"factory": jobs.industry += float(b.cap)
			"office": jobs.office += float(b.cap)
			"shop", "mixed_use": jobs.trade += float(b.cap)
	jobs.heritage = float(sim.heritage.protected_count()) * Balance.CULTURE_HERITAGE_PER_BUILDING
	var total := 0.0
	for a in AXES:
		total += float(jobs[a])
	var out := {}
	for a in AXES:
		out[a] = float(jobs[a]) / total if total > 0.0 else 0.0
	return out


## The leading axis and its share: [axis, share] ("" when none yet).
func leading() -> Array:
	var best := ""
	var best_v := 0.0
	for a in AXES:
		if float(mix[a]) > best_v:
			best_v = float(mix[a])
			best = a
	return [best, best_v]


## A player's answer to a leader leans the town (LeaderAsks, Heritage).
func nudge(axis: String, amount: float) -> void:
	if lean.has(axis):
		lean[axis] = _cents4(clampf(float(lean[axis]) + amount, -0.3, 0.3))
		changed.emit()


## How much more likely owners are to build this type on a new lot, from
## the town's culture (1.0 = no change). Used by BuildingTypes.pick.
func tilt(type: String) -> float:
	var axis := ""
	match type:
		"office": axis = "office"
		"shop", "mixed_use": axis = "trade"
		"factory": axis = "industry"
		_: return 1.0
	# An even six-way split leaves things as they are.
	return maxf(0.3, 1.0 + Balance.CULTURE_TILT * (float(mix.get(axis, 0.0)) - 1.0 / AXES.size()))


## How much keener a leader of this kind is to build (Agency.develop).
func boost(axis: String) -> float:
	return maxf(0.5, 1.0 + Balance.CULTURE_LEADER_BOOST * (float(mix.get(axis, 0.0)) - 1.0 / AXES.size()) * 2.0)


## Checks whether the town has earned a nickname, or a new one.
func _name_it(sim) -> void:
	if int(sim.stats.get("population", 0)) < Balance.NICKNAME_MIN_POP:
		return
	var lead := leading()
	if lead[0] == "" or float(lead[1]) < Balance.NICKNAME_MIN_SHARE:
		return
	var axis: String = lead[0]
	if not nickname.is_empty():
		var cur := str(nickname.axis)
		if cur == axis or float(lead[1]) < float(mix.get(cur, 0.0)) + Balance.NICKNAME_SWITCH:
			# Same identity: the words can still change when what leads within
			# it does (a mill town that became a steel town). Crops trade
			# places too often to rename a farm town over them.
			if cur == axis and cur in ["industry", "office"]:
				_rename(sim, title_for(sim, cur), cur)
			return
	_rename(sim, title_for(sim, axis), axis)


func _rename(sim, text: String, axis: String) -> void:
	if text == "" or text == str(nickname.get("text", "")):
		return
	var year := Families.calendar(Seasons.year(sim.tick_count))
	if not nickname.is_empty():
		past.append({"text": str(nickname.text), "from": int(nickname.since), "to": year})
	nickname = {"text": text, "axis": axis, "since": year}
	changed.emit()


## The nickname a town known for `axis` earns, from what it actually has.
static func title_for(sim, axis: String) -> String:
	match axis:
		"farm":
			var corn := 0
			var soy := 0
			for id in sim.farms.farms:
				if str(sim.farms.farms[id].crop) == "soybeans":
					soy += sim.farms.farms[id].cells.size()
				else:
					corn += sim.farms.farms[id].cells.size()
			return ("Soybean" if soy > corn else "Corn") + " Capital of " + COUNTY
		"industry":
			var by := {"mill": 0.0, "sawmill": 0.0, "refinery": 0.0, "metal": 0.0, "general": 0.0,
				"oil": 0.0, "ore": 0.0, "forest": 0.0}
			for key in sim.buildings:
				var b: Dictionary = sim.buildings[key]
				if BuildingTypes.type_of(b) == "factory":
					by[str(b.get("chain", "general"))] = float(by.get(str(b.get("chain", "general")), 0.0)) + float(b.cap)
			for id in sim.industry.sites:
				var s: Dictionary = sim.industry.sites[id]
				by[str(s.kind)] = float(by.get(str(s.kind), 0.0)) + 10.0 * s.pads.size()
			var top := "general"
			for k in ["mill", "sawmill", "refinery", "metal", "oil", "ore", "forest"]:
				if float(by[k]) > float(by[top]):
					top = k
			return {
				"mill": "Mill Town of " + COUNTY,
				"sawmill": "Hardwood Capital of Southern Indiana",
				"forest": "Hardwood Capital of Southern Indiana",
				"refinery": "Oil Town of " + VALLEY,
				"oil": "Oil Town of " + VALLEY,
				"metal": "Steel Town of Southern Indiana",
				"ore": "Mining Town of " + COUNTY,
				"general": "Factory Town of " + COUNTY,
			}[top]
		"trade":
			return "Market Town of " + VALLEY
		"office":
			var office := 0
			for key in sim.buildings:
				if BuildingTypes.type_of(sim.buildings[key]) == "office":
					office += int(sim.buildings[key].cap)
			return ("Banking Center" if sim.banks.jobs() * 2 >= office else "Business Center") + " of Southern Indiana"
		"college":
			return "Athens of " + VALLEY
		"heritage":
			return "Historic River Town of " + COUNTY
	return ""


static func _cents4(v: float) -> float:
	return roundi(v * 10000.0) / 10000.0


func to_dict() -> Dictionary:
	return {"mix": mix, "lean": lean, "nickname": nickname, "past": past, "festival": festival_until}


func from_dict(d: Dictionary) -> void:
	_init()
	for a in AXES:
		mix[a] = float(d.get("mix", {}).get(a, 0.0))
		lean[a] = float(d.get("lean", {}).get(a, 0.0))
	var n: Dictionary = d.get("nickname", {})
	nickname = {} if n.is_empty() else {"text": str(n.text), "axis": str(n.axis), "since": int(n.since)}
	past.clear()
	for p in d.get("past", []):
		past.append({"text": str(p.text), "from": int(p.from), "to": int(p.to)})
	festival_until = int(d.get("festival", -1))
	changed.emit()
