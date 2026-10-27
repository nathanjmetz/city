class_name Charter
extends RefCounted
## The town's place on the real ladder (Brawn, 2026-10-24): what Indiana law
## makes it, and what the federal government counts it as. Eight steps, all
## real, in two tracks a real place climbs side by side:
##
## Indiana charters, the town's own government (each one asks on the bell):
##   settlement  Unincorporated: the county and township run things.
##   town        Incorporated (IC 36-5-1): a petition by landowners, and the
##               county finds the town can give at least 6 of the 11
##               services the law lists (36-5-1-8) at a reasonable tax rate.
##   city        Third-class city (IC 36-4-1.5): at least 2,000 people, a
##               voters' petition and a referendum, "Shall the town of ___
##               change into a city?" The law has it take effect on
##               January 1; a game year is 12 real hours (Seasons), so
##               here it takes effect on the 1st of the next month.
##   city2       Second-class city (IC 36-4-1-1, 1-1.1): 35,000 people at a
##               federal decennial census, adopted by ordinance. Optional:
##               a city may stay third class (Carmel did for years).
## Federal place types, counted, never asked (a census or the metro):
##   urban       Census urban area: 5,000 people or 2,000 homes (2020 rule).
##   micro       OMB micropolitan area: an urban core of 10,000.
##   metro       OMB metropolitan area: 50,000; an MPO forms (23 USC 134).
##   medium      NCHS medium metro: 250,000 to 999,999.
## First class (600,000; only Indianapolis) is past a town's size and left
## out. The federal areas count the road-linked towns of the region (the
## Ledger's metro, the "Grow the metro" long game), so it's one system: a
## town earns its charters, and shares its metro rank with its neighbors.
##
## Charters unlock what the town's government can do, never building types:
## the market (Market) still decides what builders build.
##
## Checked once a game month; deterministic (the vote uses a seed from the
## city and the month), and saved, so every copy of the town agrees.

signal changed
## A step reached in play (not on load): the HUD celebrates it.
signal step_reached(id: String)

const HUB := "charter"
## What the town's charter asks on the bell.
const ASK_KINDS := ["incorporate", "city_vote", "special_census", "second_class"]
## A new town within 3 miles of a city needs that city's consent
## (IC 36-5-1-7); metres.
const CONSENT_REACH := 4828.0
const TICKS_PER_MONTH := 24 * CitySim.TICKS_PER_HOUR

## The ladder in order of size. "track": "law" steps are charters the town
## asks for; "census" steps count the town's own people at a census; "area"
## steps count the metro the town belongs to.
const STEPS := [
	{"id": "settlement", "name": "Settlement", "track": "law", "title": "{town}"},
	{"id": "town", "name": "Town", "track": "law", "title": "Town of {town}"},
	{"id": "city", "name": "City", "track": "law", "title": "City of {town}"},
	{"id": "urban", "name": "Urban area", "track": "census"},
	{"id": "micro", "name": "Micropolitan area", "track": "area"},
	{"id": "city2", "name": "Second-class city", "track": "law", "title": "City of {town}"},
	{"id": "metro", "name": "Metropolitan area", "track": "area"},
	{"id": "medium", "name": "Medium metro", "track": "area"},
]

## What each step opens. Only what the law keeps from a smaller place is
## locked; everything private, county or township is open from the start.
## A settlement is policed by the county sheriff (a town hires its marshal,
## IC 36-5-7); sewage works are a municipal utility (IC 36-9-23); a city
## sets up a public transportation corporation (IC 36-9-4) and parking
## garages (IC 36-9-11); park and ride lots come with the metropolitan
## planning organization (23 USC 134). Nothing already built is removed.
const UNLOCKS := {
	"town": {"kinds": [Services.Kind.POLICE], "works": ["lagoon"], "powers": [
		["A town council and clerk-treasurer", "permits"], ["A town marshal and police station", "police_station"],
		["Town sewers, starting with a sewage lagoon", "water_utility"]]},
	"city": {"kinds": [Services.Kind.BUS_DEPOT, Services.Kind.PARKING_GARAGE, Services.Kind.TRAFFIC_CENTER], "powers": [
		["A mayor and city council", "permits"], ["A city bus line", "bus_depot"], ["Public parking garages", "parking_garage"],
		["A traffic management center to time the lights", "signal"]]},
	"urban": {"powers": [["The Census counts the town as an urban area", "homes"]]},
	"micro": {"powers": [["The town anchors its own micropolitan area", "people"]]},
	"city2": {"powers": [["A second-class city charter, with a city clerk and a larger council", "permits"]]},
	"metro": {"kinds": [Services.Kind.PARK_AND_RIDE], "powers": [
		["A metropolitan planning organization for the area's roads", "road"], ["Park and ride lots", "park_and_ride"]]},
	"medium": {"powers": [["A medium metro, a quarter of a million strong", "people"]]},
}

## The 11 services IC 36-5-1-8(a)(4) lists, as the town can show it gives
## them. A town needs Balance.CHARTER_SERVICES_NEEDED of them.
const SERVICES := ["police", "fire", "streets", "sewers", "storm", "health", "parks", "schools",
	"planning", "utility", "streams"]
const SERVICE_NAMES := {"police": "police", "fire": "fire protection", "streets": "streets and street lights",
	"sewers": "sanitary sewers", "storm": "storm drains", "health": "a doctor", "parks": "parks",
	"schools": "a school", "planning": "zoning", "utility": "a utility", "streams": "water protection"}

## step id -> the tick it was reached.
var reached := {"settlement": 0}
## step id -> the tick it takes effect (a charter granted, not yet in force).
var coming := {}
## Bell requests this asked: permit id -> {"kind"}.
var asks := {}
## kind -> the tick it was last asked.
var last := {}
## Second-class status turned down (it's offered again at the next census).
var declined := {}
## The latest census: {"year", "people", "homes", "special": bool}.
var census := {}
## Cities within 3 miles, from the last region sync (not saved; re-read hourly).
var _near_cities := {}
## People in the metro this town belongs to (the region's road-linked towns),
## from the region server; 0 when there's no region (then the town's own).
var metro_people := 0
## The last city vote: {"year", "yes": share 0..1, "passed"}.
var vote := {}
## Our petition waiting on neighbor cities' consent: {"asked": tick,
## "cities": {city id: name}, "said": {city id: bool}}. A city that doesn't
## answer in Balance.CHARTER_CONSENT_MONTHS consents (Brawn, 2026-10-24).
var consent := {}
## Our answers to neighbors' petitions: their city id -> true (yes) / false.
var consents := {}
## Neighbors' petitions on our bell: permit id -> their city id.
var consent_asks := {}
## The last petition a neighbor city turned down: {"by": name, "tick"}.
var refused := {}


## The town's legal standing right now: "settlement", "town", "city" or "city2".
func status() -> String:
	for id in ["city2", "city", "town"]:
		if reached.has(id):
			return id
	return "settlement"


## The town's name as its charter puts it: "Town of Lyons", "City of Lyons".
func title(town: String) -> String:
	for s in STEPS:
		if s.id == status():
			return str(s.title).replace("{town}", town)
	return town


## Steps reached, of the eight.
func steps_reached() -> int:
	return STEPS.filter(func(s): return reached.has(s.id)).size()


## The step that opens a Services kind, or "" when it's open from the start.
static func step_for_kind(kind: int) -> String:
	for id in UNLOCKS:
		if kind in UNLOCKS[id].get("kinds", []):
			return id
	return ""


## Why a Services kind can't be built yet, or "" when it can.
func locked(kind: int) -> String:
	var id := step_for_kind(kind)
	if id == "" or reached.has(id):
		return ""
	return _lock_text(id) + (" Until then the county sheriff patrols." if kind == Services.Kind.POLICE else "")


## Why a water utility work (Water.TREE key) can't be built yet, or "".
func work_locked(key: String) -> String:
	for id in UNLOCKS:
		if key in UNLOCKS[id].get("works", []) and not reached.has(id):
			return _lock_text(id)
	return ""


func _lock_text(id: String) -> String:
	match id:
		"town": return "Opens when the settlement incorporates as a town."
		"city": return "Opens when the town becomes a city."
		"metro": return "Opens when the area becomes a metropolitan area."
	return "Opens at %s." % _step(id).name.to_lower()


static func _step(id: String) -> Dictionary:
	for s in STEPS:
		if s.id == id:
			return s
	return {}


## The step after the highest reached, with how far along the town is:
## {"id", "name", "have", "need"} in people. Empty at the top.
func next_progress(sim) -> Dictionary:
	var people := int(sim.stats.get("population", 0))
	var area := maxi(metro_people, people)
	for row in [["town", people, Balance.CHARTER_TOWN_PEOPLE], ["city", people, Balance.CHARTER_CITY_PEOPLE],
			["urban", people, Balance.CHARTER_URBAN_PEOPLE], ["micro", area, Balance.METRO_MICRO_MIN],
			["city2", people, Balance.CHARTER_CITY2_PEOPLE], ["metro", area, Balance.METRO_METRO_MIN],
			["medium", area, Balance.CHARTER_MEDIUM_PEOPLE]]:
		if reached.has(row[0]) or (row[0] == "city2" and declined.has("city2")):
			continue
		return {"id": row[0], "name": _step(row[0]).name, "have": int(row[1]), "need": int(row[2])}
	return {}


## What a step reached means, for the celebration: {"title", "how", "powers",
## "kinds"}, with the town's name filled in.
func celebration(sim, id: String, town: String) -> Dictionary:
	var m := _marker(sim, id)
	var u: Dictionary = UNLOCKS.get(id, {})
	var t := str(_step(id).get("title", "")).replace("{town}", town)
	if t == "":
		t = "%s · %s" % [town, _step(id).name]
	return {"title": t, "name": _step(id).name, "how": str(m[1]).replace("{town}", town) if m.size() > 1 else "",
		"powers": u.get("powers", []), "kinds": u.get("kinds", []), "step": STEPS.map(func(s): return s.id).find(id) + 1}


## The next step and what it takes, in a line, for the Town panel. "" at the top.
func next_line(sim) -> String:
	if not reached.has("town") and not refused.is_empty() and consent.is_empty() and not coming.has("town") \
			and sim.tick_count - int(refused.tick) < int(Balance.CHARTER_ASK_WAIT_MONTHS.incorporate) * TICKS_PER_MONTH:
		return "Town: the City of %s said no. Residents can petition again in a few years." % refused.by
	if not reached.has("town"):
		var have := services_given(sim)
		return "Town: %s people and %d of the 11 town services (you give %d)." % [
			_n(Balance.CHARTER_TOWN_PEOPLE), Balance.CHARTER_SERVICES_NEEDED, have.size()]
	if coming.has("town"):
		return "Town: the county commissioners are reviewing the petition."
	if not consent.is_empty():
		return "Town: waiting on the %s to consent." % " and ".join(consent.cities.values().map(func(n): return "City of " + str(n)))
	if not reached.has("city"):
		if coming.has("city"):
			return "City: voters said yes. The town becomes a city on the 1st of next month."
		return "City: %s people, then a vote." % _n(Balance.CHARTER_CITY_PEOPLE)
	if not reached.has("urban"):
		return "Urban area: %s people or %s homes at a census." % [_n(Balance.CHARTER_URBAN_PEOPLE), _n(Balance.CHARTER_URBAN_HOMES)]
	if not reached.has("micro"):
		return "Micropolitan area: %s people in your area." % _n(Balance.METRO_MICRO_MIN)
	if not reached.has("city2") and not declined.has("city2") and not coming.has("city2"):
		return "Second-class city: %s people at the next census (in about %d minutes)." % [_n(Balance.CHARTER_CITY2_PEOPLE), next_census_minutes(sim)]
	if not reached.has("metro"):
		return "Metropolitan area: %s people in your area." % _n(Balance.METRO_METRO_MIN)
	if not reached.has("medium"):
		return "Medium metro: %s people in your area." % _n(Balance.CHARTER_MEDIUM_PEOPLE)
	return ""


## The services of the 11 the town gives today (its own, or bought from a
## neighbor under an interlocal agreement, which the law counts too).
func services_given(sim) -> Array:
	var have := {}
	for id in sim.services.buildings:
		match int(sim.services.buildings[id].kind):
			Services.Kind.POLICE:
				have.police = true
			Services.Kind.FIRE:
				have.fire = true
			Services.Kind.CLINIC, Services.Kind.HOSPITAL:
				have.health = true
			Services.Kind.SCHOOL:
				have.schools = true
			Services.Kind.WATER_UTILITY:
				have.utility = true
				have.streams = true  # a town water utility protects its wellheads
			Services.Kind.WELL, Services.Kind.WATER_TOWER, Services.Kind.SUBSTATION, Services.Kind.POWER_FEED:
				have.utility = true
	for kind in sim.services.contracts:
		match int(kind):
			Services.Kind.POLICE:
				have.police = true
			Services.Kind.FIRE:
				have.fire = true
			Services.Kind.CLINIC, Services.Kind.HOSPITAL:
				have.health = true
			Services.Kind.SCHOOL:
				have.schools = true
	if not sim.education.campuses.is_empty():
		have.schools = true
	if not sim.parks.sites.is_empty():
		have.parks = true
	for u in sim.services.water.utilities.values():
		if not u.get("sewers", []).is_empty():
			have.sewers = true
	# Curbed town streets carry storm inlets; gravel and county roads drain
	# to ditches.
	for seg in sim.network.segments.values():
		var t := int(seg.type)
		have.streets = true
		if not t in [RoadStyle.Type.GRAVEL, RoadStyle.Type.DIRT, RoadStyle.Type.CHIP_SEAL, RoadStyle.Type.COUNTY,
				RoadStyle.Type.STATE_HWY]:
			have.storm = true
			break
	if not sim.buildings.is_empty():
		have.planning = true  # the town has zoned land
	return SERVICES.filter(func(k): return have.has(k))


## Once a sim day: a census in April of a census year, and anything new
## on the ladder. The decennial census counts pace years (Seasons.pace_year,
## about 29 real minutes), so one comes about every five hours of play, as
## it always did; on the calendar (a year 12 hours) it would be days apart.
## It is named for the calendar's month and year it falls in.
func month(sim) -> void:
	var before := JSON.stringify([reached, coming, census])
	var people := int(sim.stats.get("population", 0))
	var year := Families.calendar(Seasons.pace_year(sim.tick_count))
	if Seasons.pace_month(sim.tick_count) == 4 and year % 10 == 0 and int(census.get("year", 0)) != year:
		_count(sim, year, false)
	_in_force(sim)
	_consent_month(sim)
	if not reached.has("town") and not coming.has("town") and consent.is_empty():
		if people >= Balance.CHARTER_TOWN_PEOPLE and services_given(sim).size() >= Balance.CHARTER_SERVICES_NEEDED:
			_ask(sim, "incorporate")
	elif reached.has("town") and not reached.has("city") and not coming.has("city"):
		if people >= Balance.CHARTER_CITY_PEOPLE:
			_ask(sim, "city_vote")
	# A special census, paid for by the town, once it has clearly grown past
	# a step the last count missed (real towns buy them from the Census Bureau).
	if not reached.has("urban") and people >= Balance.CHARTER_URBAN_PEOPLE * Balance.CHARTER_SPECIAL_MARGIN:
		_ask(sim, "special_census")
	# The areas follow the region's metro (or the town alone).
	var area := maxi(metro_people, people)
	for s in [["micro", Balance.METRO_MICRO_MIN], ["metro", Balance.METRO_METRO_MIN], ["medium", Balance.CHARTER_MEDIUM_PEOPLE]]:
		if not reached.has(s[0]) and area >= int(s[1]):
			_reach(sim, str(s[0]))
	if JSON.stringify([reached, coming, census]) != before:
		changed.emit()


## The next decennial census's pace year (see month()).
func next_census_year(sim) -> int:
	var year := Families.calendar(Seasons.pace_year(sim.tick_count))
	return (year / 10 + 1) * 10 if year % 10 != 0 or int(census.get("year", 0)) == year else year


## Real minutes until the next decennial census, roughly.
func next_census_minutes(sim) -> int:
	var pace := next_census_year(sim) - 2026
	var at := Seasons.pace_tick(pace) + 3 * Seasons.OLD_TICKS_PER_MONTH
	return maxi(1, roundi(float(at - sim.tick_count) / CitySim.TICKS_PER_SECOND / 60.0))


## What a census is called: the calendar's month and year it was taken in
## ("the May 2027 census").
func census_name() -> String:
	return str(census.get("when", str(census.get("year", ""))))


## The census counts the town: the urban area, and second-class status.
func _count(sim, year: int, special: bool) -> void:
	var people := int(sim.stats.get("population", 0))
	var homes := 0
	for slice in sim.ledger().home_slices:
		homes += slice.size()
	var cal: int = sim.calendar_tick()
	census = {"year": year, "people": people, "homes": homes, "special": special,
		"when": "%s %d" % [["January", "February", "March", "April", "May", "June", "July", "August", "September",
			"October", "November", "December"][Seasons.month(cal) - 1], Families.calendar(Seasons.year(cal))]}
	if not reached.has("urban") and (people >= Balance.CHARTER_URBAN_PEOPLE or homes >= Balance.CHARTER_URBAN_HOMES):
		_reach(sim, "urban")
	# Only a federal decennial census counts for the class of a city.
	if not special and reached.has("city") and not reached.has("city2") and not coming.has("city2") \
			and people >= Balance.CHARTER_CITY2_PEOPLE:
		declined.erase("city2")
		_ask(sim, "second_class")


## Our petition's consent: any city's no ends it; all yes, or no answer in
## time, sends it on to the county.
func _consent_month(sim) -> void:
	if consent.is_empty():
		return
	for id in consent.cities:
		if consent.said.has(id) and not bool(consent.said[id]):
			refused = {"by": str(consent.cities[id]), "tick": sim.tick_count}
			consent = {}
			last["incorporate"] = sim.tick_count
			return
	var waited: bool = sim.tick_count - int(consent.asked) >= Balance.CHARTER_CONSENT_MONTHS * TICKS_PER_MONTH
	if waited or consent.said.size() >= consent.cities.size():
		consent = {}
		coming["town"] = sim.tick_count + Balance.CHARTER_REVIEW_MONTHS * TICKS_PER_MONTH


## Charters granted earlier that take effect now.
func _in_force(sim) -> void:
	var ids := coming.keys()
	ids.sort()
	for id in ids:
		if sim.tick_count >= int(coming[id]):
			coming.erase(id)
			_reach(sim, id)


func _reach(sim, id: String) -> void:
	if reached.has(id):
		return
	reached[id] = sim.tick_count
	sim.markers.charter(sim, id, _marker(sim, id))
	step_reached.emit(id)


## A marker's title and text for a step.
func _marker(sim, id: String) -> Array:
	var year := Families.calendar(Seasons.year(sim.calendar_tick()))
	match id:
		"town":
			return ["Incorporated %d" % year, "{town} was incorporated as a town in %d, with its own council, clerk-treasurer and town marshal." % year]
		"city":
			var share := roundi(float(vote.get("yes", 0.0)) * 100.0)
			return ["City of {town}", "Voters chose %d%% to %d%% to make {town} a city. It became one in %d." % [share, 100 - share, year]]
		"city2":
			return ["Second-Class City", "With %s people at the %s census, {town} became a second-class city." % [_n(int(census.get("people", 0))), census_name()]]
		"urban":
			return ["Urban Area", "The %s census counted %s people here, and {town} became an urban area." % [census_name(), _n(int(census.get("people", 0)))]]
		"micro":
			return ["Micropolitan Area", "By %d, %s people lived in the area around {town}, a micropolitan area." % [year, _n(maxi(metro_people, int(sim.stats.get("population", 0))))]]
		"metro":
			return ["Metropolitan Area", "By %d the area passed 50,000 people. It became a metropolitan area, and its towns formed a planning organization." % year]
		"medium":
			return ["Medium Metro", "By %d a quarter of a million people lived in the metro around {town}." % year]
	return [id, ""]


## Files a request on the bell. One open at a time per kind, and not again
## soon after a no.
func _ask(sim, kind: String) -> void:
	if asks.values().any(func(a): return a.kind == kind):
		return
	if sim.tick_count - int(last.get(kind, -1_000_000_000)) < int(Balance.CHARTER_ASK_WAIT_MONTHS[kind]) * TICKS_PER_MONTH:
		return
	var hub_id := 1 + ASK_KINDS.find(kind)
	if not sim.permits.can_file(sim, HUB, hub_id, true):
		return
	var plan := _plan(sim, kind)
	var at: Vector2 = sim.streets.main_at
	var half := 40.0
	var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": hub_id, "leader": plan.leader,
		"title": plan.title, "why": plan.why, "ask": kind, "yes": plan.yes, "no": plan.no,
		"area": [[at.x - half, at.y - half], [at.x + half, at.y - half], [at.x + half, at.y + half], [at.x - half, at.y + half]]})
	if req <= 0:
		return
	last[kind] = sim.tick_count
	asks[req] = {"kind": kind}
	changed.emit()


func _plan(sim, kind: String) -> Dictionary:
	var people := int(sim.stats.get("population", 0))
	match kind:
		"incorporate":
			var given := services_given(sim).map(func(k): return SERVICE_NAMES[k])
			return {"leader": "Landowners' petition", "title": "Incorporate as a town",
				"why": "%s landowners signed a petition to make this settlement a town. It already gives %d of the 11 town services: %s." % [
					_n(maxi(people / 10, 5)), given.size(), ", ".join(given)],
				"yes": "The county commissioners review it. In a day it's a town, with a council, a marshal and a plan commission.",
				"no": "It stays a county settlement. Residents can ask again in a few years."}
		"city_vote":
			return {"leader": "Voters' petition", "title": "Hold a vote to become a city",
				"why": "With %s people, voters petitioned to put it on the ballot: \"Shall the town change into a city?\"" % _n(people),
				"yes": "The town votes next month. If most say yes, it becomes a city on the 1st of the next month, with a mayor and a city council.",
				"no": "It stays a town. Voters can petition again in a few years."}
		"special_census":
			return {"leader": "Clerk-treasurer", "title": "Pay for a special census",
				"why": "The town has grown well past the last count. The Census Bureau will count it again for a fee.",
				"yes": "The town pays $%s and gets an official count now." % CitySim.money_text(special_cost(sim)),
				"no": "The town waits for the next census, in about %d minutes." % next_census_minutes(sim)}
		"second_class":
			return {"leader": "City council", "title": "Adopt second-class city status",
				"why": "The %s census counted %s people. The council can adopt second-class status by ordinance." % [
					census_name(), _n(int(census.people))],
				"yes": "On the 1st of next month the city gets a nine-member council, a city clerk and a controller who can sell city bonds.",
				"no": "It stays a third-class city. The council can take it up again after the next census."}
	return {}


## What a special census costs (about the Census Bureau's fee per person
## counted, from memory; tune).
func special_cost(sim) -> int:
	return maxi(int(sim.stats.get("population", 0)) * Balance.CHARTER_SPECIAL_PER_PERSON, 10_000)


## Carries out the player's answers (CitySim, every game hour).
func carry_out(sim) -> void:
	if asks.is_empty():
		return
	var ids := asks.keys()
	ids.sort()
	var any := false
	for id in ids:
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		var kind := str(asks[id].kind)
		asks.erase(id)
		any = true
		if st != Permits.State.APPROVED:
			if kind == "second_class":
				declined["city2"] = true
			continue
		sim.permits.done(id)
		var note := _yes(sim, kind)
		if sim.permits.requests.has(id):
			sim.permits.requests[id].note = note
	if any:
		changed.emit()


## What a yes does; returns the note the bell's history shows.
func _yes(sim, kind: String) -> String:
	match kind:
		"incorporate":
			if not _near_cities.is_empty():
				consent = {"asked": sim.tick_count, "cities": _near_cities.duplicate(), "said": {}}
				return "Sent to the %s for consent first." % " and ".join(_near_cities.values().map(func(n): return "City of " + str(n)))
			coming["town"] = sim.tick_count + Balance.CHARTER_REVIEW_MONTHS * TICKS_PER_MONTH
			return "The county commissioners approved it."
		"city_vote":
			var share := vote_share(sim)
			var year := Families.calendar(Seasons.year(sim.calendar_tick()))
			vote = {"year": year, "yes": share, "passed": share > 0.5}
			if share > 0.5:
				coming["city"] = next_month(sim)
				return "Voters said yes, %d%% to %d%%. It becomes a city on the 1st of next month." % [roundi(share * 100.0), 100 - roundi(share * 100.0)]
			return "Voters said no, %d%% to %d%%. It stays a town for now." % [roundi(share * 100.0), 100 - roundi(share * 100.0)]
		"special_census":
			sim.economy.money -= special_cost(sim)
			_count(sim, Families.calendar(Seasons.year(sim.calendar_tick())), true)
			return "Counted: %s people." % _n(int(census.people))
		"second_class":
			coming["city2"] = next_month(sim)
			return "Adopted. It takes effect on the 1st of next month."
	return "Done."


## How residents vote on becoming a city: they back the town that looks
## after them (services, care, parks) and turn on one under a boil notice.
## A little chance, from the city and the month, so it's never certain.
func vote_share(sim) -> float:
	var homes: Dictionary = sim._home_scan(-2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, sim.tick_count, "city_vote"])
	return clampf(Balance.CHARTER_VOTE_BASE + Balance.CHARTER_VOTE_COVER * float(homes.cover)
		+ Balance.CHARTER_VOTE_CARE * float(homes.care) + Balance.CHARTER_VOTE_HAPPY * float(homes.happy)
		- Balance.CHARTER_VOTE_BOIL * float(homes.boil) + rng.randf_range(-0.05, 0.05), 0.0, 1.0)


## The sim tick the calendar's next month begins on.
static func next_month(sim) -> int:
	return Seasons.tick_at(floorf(Seasons.months(sim.calendar_tick())) + 1.0) - int(sim.calendar_offset)


## Reads the metro this town is in (called with the town's region view,
## like Market).
func sync(region, me: String, sim = null) -> void:
	var m: Dictionary = region.ledger.metro
	metro_people = int(m.get("population", 0)) if me in m.get("towns", []) else 0
	if sim == null or not region.cities.has(me):
		return
	var here: Vector2 = region.cities[me].origin + sim.streets.main_at
	_near_cities = {}
	var ids: Array = region.cities.keys()
	ids.sort()
	for id in ids:
		if id == me:
			continue
		var c: Dictionary = region.cities[id]
		var them = c.sim
		if them == null:
			continue
		var name := str(c.get("name", id))
		# A city near enough that our petition needs its say.
		if them.charter.status() in ["city", "city2"] and _gap(them, c.origin, here) <= CONSENT_REACH:
			_near_cities[id] = name
		# Its answer to our petition.
		if not consent.is_empty() and consent.cities.has(id) and them.charter.consents.has(me):
			consent.said[id] = bool(them.charter.consents[me])
		# Its petition, asking us.
		if status() in ["city", "city2"] and them.charter.consent.get("cities", {}).has(me) \
				and not consents.has(id) and not consent_asks.values().has(id):
			_ask_consent(sim, id, name)
	_carry_consents(sim)


## How far a town's nearest building is from `at` (region metres).
static func _gap(town, origin: Vector2, at: Vector2) -> float:
	var best := INF
	for k in town.lots:
		if town.buildings.has(k):
			var f: Vector3 = town.lots[k].front
			best = minf(best, (origin + Vector2(f.x, f.z)).distance_to(at))
	return best


## A neighbor settlement within 3 miles petitions to incorporate: our council's say.
func _ask_consent(sim, id: String, name: String) -> void:
	var hub_id := 100 + absi(hash(id)) % 100_000
	if not sim.permits.can_file(sim, HUB, hub_id, true):
		return
	var at: Vector2 = sim.streets.main_at
	var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": hub_id, "leader": "City council",
		"title": "Let %s incorporate?" % name, "ask": "consent",
		"why": "%s, within 3 miles of the city, has petitioned to become a town. The law gives the city council a say." % name,
		"yes": "%s becomes a town, with its own council and services." % name,
		"no": "It stays a settlement. It can petition again in a few years.",
		"area": [[at.x - 40, at.y - 40], [at.x + 40, at.y - 40], [at.x + 40, at.y + 40], [at.x - 40, at.y + 40]]})
	if req > 0:
		consent_asks[req] = id
		changed.emit()


## Our council's answers to neighbors' petitions. Unanswered or shelved
## counts as yes when their wait runs out on their side.
func _carry_consents(sim) -> void:
	for req in consent_asks.keys():
		var st: int = sim.permits.state_of(req)
		if st == Permits.State.OPEN:
			continue
		var id: String = consent_asks[req]
		consent_asks.erase(req)
		if st == Permits.State.APPROVED:
			sim.permits.done(req)
			consents[id] = true
		elif st == Permits.State.DENIED:
			consents[id] = false
		changed.emit()


static func _n(n: int) -> String:
	return Ledger._thousands(n)


func to_dict() -> Dictionary:
	return {"reached": reached, "coming": coming, "asks": asks, "last": last, "declined": declined,
		"census": census, "metro": metro_people, "vote": vote, "consent": consent, "consents": consents,
		"consent_asks": consent_asks, "refused": refused}


func from_dict(d: Dictionary) -> void:
	reached = {"settlement": 0}
	for k in d.get("reached", {}):
		reached[str(k)] = int(d.reached[k])
	coming = {}
	for k in d.get("coming", {}):
		coming[str(k)] = int(d.coming[k])
	asks = {}
	for k in d.get("asks", {}):
		asks[int(k)] = {"kind": str(d.asks[k].kind)}
	last = {}
	for k in d.get("last", {}):
		last[str(k)] = int(d.last[k])
	declined = {}
	for k in d.get("declined", {}):
		declined[str(k)] = true
	var c: Dictionary = d.get("census", {})
	census = {} if c.is_empty() else {"year": int(c.year), "people": int(c.people), "homes": int(c.get("homes", 0)),
		"special": bool(c.get("special", false))}
	if c.has("when"):
		census.when = str(c.when)
	metro_people = int(d.get("metro", 0))
	var v: Dictionary = d.get("vote", {})
	vote = {} if v.is_empty() else {"year": int(v.year), "yes": float(v.yes), "passed": bool(v.passed)}
	var cs: Dictionary = d.get("consent", {})
	consent = {}
	if not cs.is_empty():
		consent = {"asked": int(cs.asked), "cities": {}, "said": {}}
		for k in cs.get("cities", {}):
			consent.cities[str(k)] = str(cs.cities[k])
		for k in cs.get("said", {}):
			consent.said[str(k)] = bool(cs.said[k])
	consents = {}
	for k in d.get("consents", {}):
		consents[str(k)] = bool(d.consents[k])
	consent_asks = {}
	for k in d.get("consent_asks", {}):
		consent_asks[int(k)] = str(d.consent_asks[k])
	var rf: Dictionary = d.get("refused", {})
	refused = {} if rf.is_empty() else {"by": str(rf.by), "tick": int(rf.tick)}
	changed.emit()
