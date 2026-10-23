extends SceneTree
## Run: godot --headless -s tests/test_interlocal.gd
## Shared services between towns: a host town's leaders offer what a
## neighbor lacks on both bells, a deal both approve is signed, the served
## town pays its share each month, the host's garbage trucks and coverage
## reach over the county road, it comes out the same on every copy, and
## either town can end it with notice.

var _failed := false


func _init() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	var ann: CitySim = r.cities.c1.sim
	var bob: CitySim = r.cities.c2.sim
	for sim in [ann, bob]:
		sim.require_utilities = false
		sim.economy.money = 50_000_000
		# A street off the county road, with homes along it.
		_check(sim.apply_now({"type": "build_road", "start": [0, 0], "ctrl": [0, 400], "end": [0, 800]}), "a street")
		for z in range(20, 800, 10):
			sim.apply_now({"type": "paint_zone", "center": [-25, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply_now({"type": "paint_zone", "center": [25, z], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	# Ann's town has a landfill and a fire station; Bob's has neither.
	var site := CivicHubs.site_near(ann.network, Vector3(60, 0, 760))
	_check(ann.apply_now({"type": "place_hub", "kind": "landfill", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "Ann builds a landfill")
	var fs := Services.site_near(ann.network, Services.Kind.FIRE, Vector3(-60, 0, 60))
	_check(ann.apply_now({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [fs[0].x, fs[0].z],
		"dir": [fs[1].x, fs[1].z]}), "Ann builds a fire station")

	# Let the towns fill in and a month or two pass: offers come to both bells.
	_ticks(r, 4 * Region.TRADE_EVERY)
	_check(Interlocal.homes(bob) >= Balance.INTERLOCAL_MIN_HOMES, "Bob's town has homes (%d)" % Interlocal.homes(bob))
	var asks := _open(bob)
	var host_asks := _open(ann)
	var kinds := asks.map(func(q): return q.deal.kind)
	_check("trash" in kinds and "fire" in kinds, "Bob is offered trash pickup and fire protection (%s)" % str(kinds))
	_check(not "school" in kinds, "nobody offers what they don't have (no school)")
	_check(host_asks.size() == asks.size(), "Ann's bell has the same offers")
	_check(r.pacts.size() == asks.size(), "the region holds each offer until both answer")
	for q in asks:
		_check(q.shape == "deal" and q.deal.pays and q.deal.fee >= Balance.INTERLOCAL_MIN_FEE, "an offer says what Bob would pay")
		_check(q.cost == 0 and q.hits.roads.is_empty(), "a service deal builds nothing")
	_check(not bob.permits.answer(bob, {"id": asks[0].id, "answer": "edit", "route": [[0, 0], [1, 1]]}),
		"a deal can't be redrawn, only approved or denied")

	# Both approve trash and fire.
	var bob_money_line: int = bob.economy.budget.get("deals", 0)
	for q in asks:
		bob.apply_now({"type": "permit", "id": q.id, "answer": "approve"})
	for q in host_asks:
		ann.apply_now({"type": "permit", "id": q.id, "answer": "approve"})
	_ticks(r, Region.TRADE_EVERY)
	_check(bob.interlocal.served_by("trash").size() > 0 and bob.interlocal.served_by("fire").size() > 0,
		"both deals are signed")
	_check(r.pacts.is_empty(), "nothing left waiting")
	var trash: Dictionary = bob.interlocal.served_by("trash")
	var host_trash: Dictionary = ann.interlocal.deals[trash.id]
	_check(host_trash.role == "host" and host_trash.fee == trash.fee, "Ann's half has the same terms")
	_check(trash.link in bob.region_links and host_trash.link in ann.region_links, "each side uses its county road")
	ann.economy.update_budget(ann)
	bob.economy.update_budget(bob)
	var fees: int = trash.fee + bob.interlocal.served_by("fire").fee
	_check(bob.economy.budget.deals == -fees and ann.economy.budget.deals == fees,
		"Bob pays Ann each month (%d, %d, was %d)" % [bob.economy.budget.deals, ann.economy.budget.deals, bob_money_line])

	# Fire: Bob's homes are covered from Ann's station over the county road.
	r.tick()  # lots are re-figured on the next step
	var covered := 0
	for key in bob.buildings:
		if bob.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL and bob.services.served.get(key, {}).get(Services.Kind.FIRE, false):
			covered += 1
	_check(covered > 0, "Bob's homes have fire protection from Ann's station (%d)" % covered)

	# Trash: Ann's trucks come into Bob's town from the county road.
	var saw_pickup := false
	var saw_haul := false
	var received: float = ann.hubs.hubs.values()[0].received
	# The county road is a few miles long: a run takes a while.
	for i in 8 * Region.TRADE_EVERY:
		r.tick()
		for t in bob.interlocal.trips:
			saw_pickup = saw_pickup or bob.interlocal.trips[t].what == "pickup"
		for t in ann.interlocal.trips:
			saw_haul = saw_haul or ann.interlocal.trips[t].what == "haul"
	_check(saw_pickup, "contract garbage trucks pick up in Bob's town")
	_check(saw_haul, "Ann's trucks drive out to the county road and back")
	_check(ann.hubs.hubs.values()[0].received > received, "Bob's trash reaches Ann's landfill")
	_check(not bob.trade.wants.has("garbage"), "Bob no longer pays an outside hauler")

	# A save carries the deals, the offers and the trucks on their runs.
	var copy := Region.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true)))
	for id in ["c1", "c2"]:
		var a: Interlocal = r.cities[id].sim.interlocal
		var b: Interlocal = copy.cities[id].sim.interlocal
		_check(var_to_str(a.deals) == var_to_str(b.deals) and var_to_str(a.trips) == var_to_str(b.trips),
			"%s's deals and runs come back exactly from a save" % id)
	_check(copy.next_pact == r.next_pact and copy.pact_wait == r.pact_wait, "the region's offers are saved")

	# Bob gives notice: it runs through the notice, then ends on both sides.
	_check(bob.apply_now({"type": "end_deal", "id": trash.id}), "Bob gives notice")
	_check(not bob.apply_now({"type": "end_deal", "id": trash.id}), "once is enough")
	_ticks(r, Region.TRADE_EVERY)
	_check(ann.interlocal.deals.has(trash.id) and int(ann.interlocal.deals[trash.id].ends) > 0, "Ann hears the notice")
	_ticks(r, Balance.INTERLOCAL_NOTICE + Region.TRADE_EVERY)
	_check(not bob.interlocal.deals.has(trash.id) and not ann.interlocal.deals.has(trash.id), "the deal ends on both sides")
	_check(bob.interlocal.served_by("fire").size() > 0, "the fire deal carries on")

	# A "no" from either side drops the offer, and it waits before coming back.
	_ticks(r, Region.TRADE_EVERY)
	var again := _open(bob).filter(func(q): return q.deal.kind == "trash")
	_check(again.size() == 1, "the trash offer comes again (%d)" % again.size())
	if again.size() == 1:
		bob.apply_now({"type": "permit", "id": again[0].id, "answer": "deny"})
		_ticks(r, Region.TRADE_EVERY)
		_check(_open(ann).filter(func(q): return q.deal.kind == "trash").is_empty(), "Ann's half is withdrawn")
		_ticks(r, Region.TRADE_EVERY)
		_check(_open(bob).filter(func(q): return q.deal.kind == "trash").is_empty(), "and it isn't offered again right away")

	# The fee: the host's cost shared by homes, plus the administrative share.
	_check(Interlocal.fee("fire", 300, 100) == roundi(45_000 * 0.25 * 1.1 / 100.0) * 100, "fire fee is a share by homes")
	_check(Interlocal.fee("trash", 10_000, 1) == Balance.INTERLOCAL_MIN_FEE, "there's a minimum fee")

	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _ticks(r: Region, n: int) -> void:
	for i in n:
		r.tick()


func _open(sim: CitySim) -> Array:
	return sim.permits.listed(Permits.State.OPEN).filter(func(q): return q.hub == "interlocal")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + what)
	else:
		print("ok: " + what)
