extends SceneTree
## Run: godot --headless -s tests/test_town_laws.gd
## Town laws: the council brings real ordinances to the bell once the town
## incorporates, the player adopts or repeals them, and each one changes
## how the town works (trucks keep off neighborhood streets; new homes pay
## an impact fee and go up a little slower).

var _failed := false
const MONTH := 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	_routes()
	_council()
	print("FAIL" if _failed else "PASS", " test_town_laws")
	quit(1 if _failed else 0)


## Truck routes: a truck crossing town takes the avenue round, not the
## neighborhood street, while a car still takes the short way.
func _routes() -> void:
	var sim := CitySim.new()
	sim.city_seed = 3
	_clear_county(sim, Vector2.ZERO, 500.0)
	var ave := RoadStyle.Type.AVENUE
	for r in [[[-300, 0], [-200, 0], ave], [[200, 0], [300, 0], ave], [[-200, 0], [200, 0], RoadStyle.Type.STREET],
			[[-200, 0], [-200, 200], ave], [[-200, 200], [200, 200], ave], [[200, 200], [200, 0], ave]]:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b, "road": r[2]})
	var from := {"ref": "edge", "pos": [-280, 0]}
	var to := {"ref": "edge", "pos": [280, 0]}
	var car := sim.traffic.drive_ticks(from, to, false)
	var truck := sim.traffic.drive_ticks(from, to, true)
	_check(car < INF and absf(car - truck) < 0.01, "without the law a truck takes the street like a car (%.0f, %.0f)" % [car, truck])
	_check(not sim.apply({"type": "law", "law": "truck_routes", "on": true}), "a settlement has no council to pass laws")
	sim.charter.reached["town"] = sim.tick_count
	var money: int = sim.economy.money
	_check(sim.apply({"type": "law", "law": "truck_routes", "on": true}), "a town adopts truck routes")
	_check(sim.economy.money == money - Balance.LAW_TRUCK_SIGNS, "and pays for the signs")
	var truck2 := sim.traffic.drive_ticks(from, to, true)
	_check(truck2 > truck + 1.0, "a truck now goes round by the avenue (%.0f, was %.0f)" % [truck2, truck])
	_check(absf(sim.traffic.drive_ticks(from, to, false) - car) < 0.01, "a car still takes the street")
	# A truck delivering on the street itself still comes in.
	var mid := {"ref": "edge", "pos": [0, 0]}
	_check(sim.traffic.drive_ticks(from, mid, true) < INF, "a delivery on the street still gets there")
	# Saved and loaded, the law still holds.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.laws.has("truck_routes") and copy.traffic.truck_routes, "the law is saved")
	_check(sim.apply({"type": "law", "law": "truck_routes", "on": false}), "and it can be repealed")
	_check(absf(sim.traffic.drive_ticks(from, to, true) - truck) < 0.01, "then trucks take the street again")


## The council takes a law up on the bell, and a yes passes it.
func _council() -> void:
	var sim := _town(5)
	_check(sim.buildings.size() >= 10, "the test town grew (%d buildings)" % sim.buildings.size())
	# A settlement's council doesn't exist yet.
	_fake_truck(sim)
	sim.laws.count(sim)
	_check(sim.laws.through.is_empty(), "nobody counts trucks before the town incorporates")
	sim.charter.reached["town"] = sim.tick_count
	for i in Balance.LAW_TRUCK_ASK_MIN:
		sim.laws.count(sim)
	_unfake(sim)
	_check(not sim.laws.through.is_empty(), "through trucks on a neighborhood street are counted")
	_month(sim)
	var req := _ask(sim)
	_check(req > 0, "neighbors petition the council for truck routes")
	if req > 0:
		var r: Dictionary = sim.permits.requests[req]
		_check(str(r.title) == "Truck routes" and str(r.yes) != "" and str(r.no) != "", "the card says what a yes and a no bring")
		sim.apply({"type": "permit", "id": req, "answer": "approve"})
		sim.laws.carry_out(sim)
		_check(sim.laws.has("truck_routes") and sim.traffic.truck_routes, "a yes passes it")
	# A year of fast home building: the plan commission asks for an impact fee.
	var n := 0
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			sim.buildings[key].built = sim.tick_count
			n += 1
	_check(n >= Balance.LAW_IMPACT_ASK_HOMES or sim.laws._plan_impact_fee(sim).is_empty(),
		"a town with too few new homes isn't asked (%d)" % n)
	var plan: Dictionary = sim.laws._plan_impact_fee(sim)
	if n >= Balance.LAW_IMPACT_ASK_HOMES:
		_check(not plan.is_empty(), "the plan commission asks for an impact fee")
	_check(sim.laws.home_pace() == 1.0 and sim.laws.home_fee() == 0, "no fee before it's adopted")
	sim.apply({"type": "law", "law": "impact_fee", "on": true})
	_check(sim.laws.home_pace() < 1.0 and sim.laws.home_fee() == Balance.LAW_IMPACT_FEE, "adopted, homes pay and go up slower")
	# Every name and line is filled in.
	for law in TownLaws.LAWS:
		_check(str(TownLaws.LAWS[law].name) != "" and str(TownLaws.LAWS[law].does) != "", "%s has a name and a trade-off" % law)


## A semi parked on the town's road list, its route running down the
## town's neighborhood street, for the count to see.
func _fake_truck(sim: CitySim) -> void:
	var segs := []
	for seg in sim.network.segments:
		if int(sim.network.segments[seg].type) in TownLaws.LOCAL_STREETS:
			segs.append(seg)
	segs.sort()
	var route := [-1]
	for seg in segs:
		route.append(int(seg) * 2 + 1)
	route.append(-1)
	sim.traffic.cars.append({"id": -77, "len": 16.0, "route": route, "leg": 0, "fake": true})


func _unfake(sim: CitySim) -> void:
	sim.traffic.cars = sim.traffic.cars.filter(func(c): return not c.get("fake", false))


func _ask(sim: CitySim) -> int:
	for r in sim.permits.listed(Permits.State.OPEN):
		if str(r.get("ask", "")) == "law":
			return int(r.id)
	return -1


func _month(sim: CitySim) -> void:
	sim.tick_count += MONTH
	sim.permits.tick(sim)
	sim.laws.month(sim)


func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	_clear_county(sim, Vector2.ZERO, 300.0)
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, -75], "end": [0, 0]})
	for x in range(-150, 151, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	for i in 1800:
		sim.tick()
	return sim


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)


## Bulldozes the county roads around `at` (town coordinates).
static func _clear_county(sim: CitySim, at: Vector2, reach: float) -> void:
	var o := sim.terrain_offset
	for x in range(int(at.x - reach), int(at.x + reach) + 1, 100):
		for z in range(int(at.y - reach), int(at.y + reach) + 1, 100):
			for mile in CountyGrid.miles_at(x + o.x, z + o.y, 60.0):
				sim.apply({"type": "remove_county", "key": mile.key})
