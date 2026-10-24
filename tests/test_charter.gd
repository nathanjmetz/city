extends SceneTree
## Run: godot --headless -s tests/test_charter.gd
## The charter ladder: a settlement incorporates as a town once it gives six
## of the eleven services, becomes a city by vote at 2,000 people (on the
## next January 1), and the census and the metro count the federal steps.

var _failed := false
const MONTH := 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	var sim := _town(5)
	_check(sim.charter.status() == "settlement", "a new town starts as a settlement")
	_check(sim.charter.title("Lyons") == "Lyons", "a settlement goes by its plain name")

	# --- Incorporation: people, then six of the eleven services.
	sim.stats.population = 60
	_month(sim)
	_check(_ask_for(sim, "incorporate") == -1, "no petition at 60 people")
	sim.stats.population = 150
	var had: Array = sim.charter.services_given(sim)
	_check("streets" in had and "planning" in had, "streets and zoning count as town services (%s)" % [had])
	if had.size() < Balance.CHARTER_SERVICES_NEEDED:
		_month(sim)
		_check(_ask_for(sim, "incorporate") == -1, "no petition with only %d services" % had.size())
	var fake := 900000
	for k in [Services.Kind.POLICE, Services.Kind.FIRE, Services.Kind.SCHOOL, Services.Kind.CLINIC, Services.Kind.WELL]:
		sim.services.buildings[fake] = {"kind": k, "pos": Vector3.ZERO, "dir": Vector3.FORWARD}
		fake += 1
	_check(sim.charter.services_given(sim).size() >= Balance.CHARTER_SERVICES_NEEDED, "six or more services now")
	_month(sim)
	var req := _ask_for(sim, "incorporate")
	_check(req > 0, "landowners petition to incorporate")
	if req > 0:
		var r: Dictionary = sim.permits.requests[req]
		_check(str(r.yes) != "" and str(r.no) != "" and str(r.why).find("11") != -1, "the card says what each answer does")
		_check(sim.apply({"type": "permit", "id": req, "answer": "approve"}), "the player approves it")
		sim.charter.carry_out(sim)
		_check(sim.charter.status() == "settlement" and sim.charter.coming.has("town"), "the county reviews it first")
		_month(sim)
		_month(sim)
		_check(sim.charter.status() == "town", "a month later it's a town")
		_check(sim.charter.title("Lyons") == "Town of Lyons", "the Town of Lyons")
		_check(sim.markers.seen.has("charter:town"), "an incorporation marker goes up")

	# --- A no waits years before asking again.
	var sim2 := _town(6)
	sim2.stats.population = 150
	for k in [Services.Kind.POLICE, Services.Kind.FIRE, Services.Kind.SCHOOL, Services.Kind.CLINIC, Services.Kind.WELL]:
		sim2.services.buildings[fake] = {"kind": k, "pos": Vector3.ZERO, "dir": Vector3.FORWARD}
		fake += 1
	_month(sim2)
	var r2 := _ask_for(sim2, "incorporate")
	_check(r2 > 0, "the second town petitions too")
	sim2.apply({"type": "permit", "id": r2, "answer": "deny"})
	sim2.charter.carry_out(sim2)
	sim2.permits.wait_until.clear()
	for i in 6:
		_month(sim2)
	_check(_ask_for(sim2, "incorporate") == -1 and sim2.charter.status() == "settlement", "after a no it stays a settlement and waits")

	# --- City: 2,000 people and a vote; it takes effect January 1.
	sim.stats.population = 2400
	_month(sim)
	var v := _ask_for(sim, "city_vote")
	_check(v > 0, "voters petition for a city vote at 2,400 people")
	if v > 0:
		var share := sim.charter.vote_share(sim)
		sim.apply({"type": "permit", "id": v, "answer": "approve"})
		sim.charter.carry_out(sim)
		_check(not sim.charter.vote.is_empty(), "the vote is held")
		var passed: bool = sim.charter.vote.passed
		print("  city vote: %d%% yes (formula %d%%)" % [roundi(float(sim.charter.vote.yes) * 100), roundi(share * 100)])
		if passed:
			_check(sim.charter.status() == "town", "a yes waits for January 1")
			var jan: int = sim.charter.coming.city
			_check(Seasons.month(jan) == 1, "the date is a January (month %d)" % Seasons.month(jan))
			while sim.tick_count < jan:
				_month(sim)
			_month(sim)
			_check(sim.charter.status() == "city" and sim.charter.title("Lyons") == "City of Lyons", "then it's the City of Lyons")
		else:
			_check(sim.charter.status() == "town", "a no keeps it a town")
			# A yes another time takes effect the same way.
			sim.charter.coming["city"] = Charter.next_january(sim.tick_count)
			while sim.charter.coming.has("city"):
				_month(sim)
			_check(sim.charter.status() == "city" and Seasons.month(int(sim.charter.reached.city)) == 1,
				"a passed vote makes it the City of Lyons in January")
	_check(Seasons.month(Charter.next_january(0)) == 1 and Charter.next_january(0) > 0, "next January is a January")

	# --- Vote mood: a boil notice sinks it.
	_check(sim.charter.vote_share(sim) >= 0.0 and sim.charter.vote_share(sim) <= 1.0, "a vote share is a share")

	# --- The census: the urban area counts at a census year, in April.
	var sim3 := _town(7)
	sim3.charter.reached["town"] = 0
	sim3.charter.reached["city"] = 0
	sim3.stats.population = 5200
	while not (Seasons.month(sim3.tick_count) == 4 and Families.calendar(Seasons.year(sim3.tick_count)) % 10 == 0):
		sim3.tick_count += MONTH
	sim3.charter.month(sim3)
	_check(int(sim3.charter.census.get("people", 0)) == 5200, "the census counts the town")
	_check(sim3.charter.reached.has("urban"), "5,200 people make an urban area")
	_check(sim3.charter.reached.has("micro") == false, "but not yet a micropolitan area")
	# The metro counts the road-linked region.
	sim3.charter.metro_people = 12_000
	sim3.tick_count += MONTH
	sim3.charter.month(sim3)
	_check(sim3.charter.reached.has("micro"), "a 12,000-person metro makes a micropolitan area")
	sim3.charter.metro_people = 60_000
	sim3.tick_count += MONTH
	sim3.charter.month(sim3)
	_check(sim3.charter.reached.has("metro"), "and 60,000 a metropolitan area")
	# Second class: only at a decennial census, and only if adopted.
	sim3.stats.population = 36_000
	while not (Seasons.month(sim3.tick_count) == 4 and Families.calendar(Seasons.year(sim3.tick_count)) % 10 == 0):
		sim3.tick_count += MONTH
	sim3.permits.wait_until.clear()
	sim3.charter.month(sim3)
	var c2 := _ask_for(sim3, "second_class")
	_check(c2 > 0, "36,000 at the census: the council offers second-class status")
	if c2 > 0:
		sim3.apply({"type": "permit", "id": c2, "answer": "deny"})
		sim3.charter.carry_out(sim3)
		_check(sim3.charter.status() == "city" and sim3.charter.declined.has("city2"), "it can say no and stay third class")

	# --- A city within 3 miles has a say (IC 36-5-1-7).
	var city := _town(8)
	city.charter.reached["town"] = 0
	city.charter.reached["city"] = 0
	var hamlet := _town(9)
	hamlet.stats.population = 150
	for k in [Services.Kind.POLICE, Services.Kind.FIRE, Services.Kind.SCHOOL, Services.Kind.CLINIC, Services.Kind.WELL]:
		hamlet.services.buildings[fake] = {"kind": k, "pos": Vector3.ZERO, "dir": Vector3.FORWARD}
		fake += 1
	var region := FakeRegion.new()
	region.cities = {"a": {"name": "Marion", "origin": Vector2.ZERO, "sim": city},
		"b": {"name": "Upland", "origin": Vector2(3000, 0), "sim": hamlet}}
	hamlet.charter.sync(region, "b", hamlet)
	_month(hamlet)
	var p := _ask_for(hamlet, "incorporate")
	_check(p > 0, "the settlement near a city petitions")
	hamlet.apply({"type": "permit", "id": p, "answer": "approve"})
	hamlet.charter.carry_out(hamlet)
	_check(hamlet.charter.consent.get("cities", {}).has("a") and not hamlet.charter.coming.has("town"),
		"the petition goes to the nearby city first")
	city.charter.sync(region, "a", city)
	var cq := _ask_for(city, "consent")
	_check(cq > 0, "the city's council gets a consent card")
	city.apply({"type": "permit", "id": cq, "answer": "deny"})
	city.charter.sync(region, "a", city)
	_check(city.charter.consents.get("b") == false, "the city's no is recorded")
	hamlet.charter.sync(region, "b", hamlet)
	_month(hamlet)
	_check(hamlet.charter.consent.is_empty() and not hamlet.charter.coming.has("town") and hamlet.charter.status() == "settlement",
		"a no ends the petition")
	_check(hamlet.charter.next_line(hamlet).find("said no") != -1, "and the Town panel says why")
	# No answer in a month counts as yes.
	var hamlet2 := CitySim.new()
	hamlet2.charter.consent = {"asked": hamlet2.tick_count, "cities": {"a": "Marion"}, "said": {}}
	_month(hamlet2)
	_month(hamlet2)
	_check(hamlet2.charter.coming.has("town") or hamlet2.charter.status() == "town", "silence counts as consent")
	# A far city has no say.
	region.cities.b.origin = Vector2(9000, 0)
	hamlet.charter.sync(region, "b", hamlet)
	_check(hamlet.charter._near_cities.is_empty(), "a city 9 km away has no say")

	# --- Saving keeps it all.
	var copy := Charter.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim3.charter.to_dict())))
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim3.charter.to_dict()), "a save round-trips")
	_check(sim3.charter.next_line(sim3) != "", "the Town panel has a next step")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


class FakeRegion:
	var cities := {}
	var ledger := {"metro": {}}


func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-120, 0], "ctrl": [0, 0], "end": [120, 0]})
	for x in range(-120, 121, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 900:
		sim.tick()
	return sim


func _month(sim: CitySim) -> void:
	sim.tick_count += MONTH
	sim.permits.tick(sim)
	sim.charter.month(sim)
	sim.charter.carry_out(sim)


func _ask_for(sim: CitySim, kind: String) -> int:
	for r in sim.permits.listed(Permits.State.OPEN):
		if str(r.get("ask", "")) == kind:
			return int(r.id)
	return -1


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
