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
##               change into a city?" It takes effect on January 1.
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

const HUB := "charter"
## What the town's charter asks on the bell.
const ASK_KINDS := ["incorporate", "city_vote", "special_census", "second_class"]
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
## People in the metro this town belongs to (the region's road-linked towns),
## from the region server; 0 when there's no region (then the town's own).
var metro_people := 0
## The last city vote: {"year", "yes": share 0..1, "passed"}.
var vote := {}


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


## The next step and what it takes, in a line, for the Town panel. "" at the top.
func next_line(sim) -> String:
	if not reached.has("town"):
		var have := services_given(sim)
		return "Town: %s people and %d of the 11 town services (you give %d)." % [
			_n(Balance.CHARTER_TOWN_PEOPLE), Balance.CHARTER_SERVICES_NEEDED, have.size()]
	if coming.has("town"):
		return "Town: the county commissioners are reviewing the petition."
	if not reached.has("city"):
		if coming.has("city"):
			return "City: voters said yes. The town becomes a city on January 1."
		return "City: %s people, then a vote." % _n(Balance.CHARTER_CITY_PEOPLE)
	if not reached.has("urban"):
		return "Urban area: %s people or %s homes at a census." % [_n(Balance.CHARTER_URBAN_PEOPLE), _n(Balance.CHARTER_URBAN_HOMES)]
	if not reached.has("micro"):
		return "Micropolitan area: %s people in your area." % _n(Balance.METRO_MICRO_MIN)
	if not reached.has("city2") and not declined.has("city2") and not coming.has("city2"):
		return "Second-class city: %s people at the next census (%d)." % [_n(Balance.CHARTER_CITY2_PEOPLE), next_census_year(sim)]
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
		if not t in [RoadStyle.Type.GRAVEL, RoadStyle.Type.COUNTY, RoadStyle.Type.STATE_HWY]:
			have.storm = true
			break
	if not sim.buildings.is_empty():
		have.planning = true  # the town has zoned land
	return SERVICES.filter(func(k): return have.has(k))


## Once a game month: a census in April of a census year, and anything new
## on the ladder.
func month(sim) -> void:
	var before := JSON.stringify([reached, coming, census])
	var people := int(sim.stats.get("population", 0))
	var year := Families.calendar(Seasons.year(sim.tick_count))
	if Seasons.month(sim.tick_count) == 4 and year % 10 == 0 and int(census.get("year", 0)) != year:
		_count(sim, year, false)
	_in_force(sim)
	if not reached.has("town") and not coming.has("town"):
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


## The next decennial census year.
func next_census_year(sim) -> int:
	var year := Families.calendar(Seasons.year(sim.tick_count))
	return (year / 10 + 1) * 10 if year % 10 != 0 or int(census.get("year", 0)) == year else year


## The census counts the town: the urban area, and second-class status.
func _count(sim, year: int, special: bool) -> void:
	var people := int(sim.stats.get("population", 0))
	var homes := 0
	for slice in sim.ledger().home_slices:
		homes += slice.size()
	census = {"year": year, "people": people, "homes": homes, "special": special}
	if not reached.has("urban") and (people >= Balance.CHARTER_URBAN_PEOPLE or homes >= Balance.CHARTER_URBAN_HOMES):
		_reach(sim, "urban")
	# Only a federal decennial census counts for the class of a city.
	if not special and reached.has("city") and not reached.has("city2") and not coming.has("city2") \
			and people >= Balance.CHARTER_CITY2_PEOPLE:
		declined.erase("city2")
		_ask(sim, "second_class")


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


## A marker's title and text for a step.
func _marker(sim, id: String) -> Array:
	var year := Families.calendar(Seasons.year(sim.tick_count))
	match id:
		"town":
			return ["Incorporated %d" % year, "{town} was incorporated as a town in %d, with its own council, clerk-treasurer and town marshal." % year]
		"city":
			var share := roundi(float(vote.get("yes", 0.0)) * 100.0)
			return ["City of {town}", "Voters chose %d%% to %d%% to make {town} a city. It became one on January 1, %d." % [share, 100 - share, year]]
		"city2":
			return ["Second-Class City", "With %s people at the %d census, {town} became a second-class city." % [_n(int(census.get("people", 0))), int(census.get("year", year))]]
		"urban":
			return ["Urban Area", "The %d census counted %s people here, and {town} became an urban area." % [int(census.get("year", year)), _n(int(census.get("people", 0)))]]
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
				"yes": "The county commissioners review it. In a month it's a town, with a council, a marshal and a plan commission.",
				"no": "It stays a county settlement. Residents can ask again in a few years."}
		"city_vote":
			return {"leader": "Voters' petition", "title": "Hold a vote to become a city",
				"why": "With %s people, voters petitioned to put it on the ballot: \"Shall the town change into a city?\"" % _n(people),
				"yes": "The town votes next month. If most say yes, it becomes a city on January 1, with a mayor and a city council.",
				"no": "It stays a town. Voters can petition again in a few years."}
		"special_census":
			return {"leader": "Clerk-treasurer", "title": "Pay for a special census",
				"why": "The town has grown well past the last count. The Census Bureau will count it again for a fee.",
				"yes": "The town pays $%s and gets an official count now." % CitySim.money_text(special_cost(sim)),
				"no": "The town waits for the next census, in %d." % next_census_year(sim)}
		"second_class":
			return {"leader": "City council", "title": "Adopt second-class city status",
				"why": "The %d census counted %s people. The council can adopt second-class status by ordinance." % [
					int(census.year), _n(int(census.people))],
				"yes": "On January 1 the city gets a nine-member council, a city clerk and a controller who can sell city bonds.",
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
			coming["town"] = sim.tick_count + Balance.CHARTER_REVIEW_MONTHS * TICKS_PER_MONTH
			return "The county commissioners approved it."
		"city_vote":
			var share := vote_share(sim)
			var year := Families.calendar(Seasons.year(sim.tick_count))
			vote = {"year": year, "yes": share, "passed": share > 0.5}
			if share > 0.5:
				coming["city"] = next_january(sim.tick_count)
				return "Voters said yes, %d%% to %d%%. It becomes a city on January 1." % [roundi(share * 100.0), 100 - roundi(share * 100.0)]
			return "Voters said no, %d%% to %d%%. It stays a town for now." % [roundi(share * 100.0), 100 - roundi(share * 100.0)]
		"special_census":
			sim.economy.money -= special_cost(sim)
			_count(sim, Families.calendar(Seasons.year(sim.tick_count)), true)
			return "Counted: %s people." % _n(int(census.people))
		"second_class":
			coming["city2"] = next_january(sim.tick_count)
			return "Adopted. It takes effect on January 1."
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


## The first tick of the next January.
static func next_january(tick: int) -> int:
	var m := Seasons.months(tick)
	var jan := (floorf(m / 12.0) + 1.0) * 12.0
	return int(ceilf((jan - Seasons.START_MONTH) * Seasons.TICKS_PER_DAY))


## Reads the metro this town is in (called with the town's region view,
## like Market).
func sync(region, me: String) -> void:
	var m: Dictionary = region.ledger.metro
	metro_people = int(m.get("population", 0)) if me in m.get("towns", []) else 0


static func _n(n: int) -> String:
	return Ledger._thousands(n)


func to_dict() -> Dictionary:
	return {"reached": reached, "coming": coming, "asks": asks, "last": last, "declined": declined,
		"census": census, "metro": metro_people, "vote": vote}


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
	metro_people = int(d.get("metro", 0))
	var v: Dictionary = d.get("vote", {})
	vote = {} if v.is_empty() else {"year": int(v.year), "yes": float(v.yes), "passed": bool(v.passed)}
	changed.emit()
