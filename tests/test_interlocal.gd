extends SceneTree
## Run: godot --headless -s tests/test_interlocal.gd
## Shared services between towns, the way the game runs them: each player's
## computer runs only its own town and sends the region server a copy. The
## server keeps the agreements in the region's ledger; each town's leaders
## offer through its own bell, the neighbor answers on theirs, and each town
## runs its half from the ledger and the neighbor's copy. The served town pays its
## share, the host's garbage trucks and fire coverage reach over the county
## road, a deal runs on while a player is away, and either town can end it
## with notice.

const MONTH := 24 * 60
var _failed := false
var r := Region.new()
## The players' own computers: city id -> CitySim (only the online ones run).
var homes := {}


func _init() -> void:
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	for id in ["c1", "c2"]:
		homes[id] = _welcome(id)
	var ann: CitySim = homes.c1
	var bob: CitySim = homes.c2
	for sim in [ann, bob]:
		sim.require_utilities = false
		sim.economy.money = 50_000_000
		# A street off the county road, homes on one side and work on the
		# other. Ann's runs south; Bob's east, clear of SR 13, which runs
		# north through Swayzee.
		var way := Vector2(0, 1) if sim == ann else Vector2(1, 0)
		var side := Vector2(-way.y, way.x) * 25.0
		_check(sim.apply_now({"type": "build_road", "start": [0, 0], "ctrl": [way.x * 400, way.y * 400],
			"end": [way.x * 800, way.y * 800]}), "a street")
		for k in range(20, 800, 10):
			var at := way * k
			sim.apply_now({"type": "paint_zone", "center": [at.x + side.x, at.y + side.y], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply_now({"type": "paint_zone", "center": [at.x - side.x, at.y - side.y], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	# Ann's town has a landfill and a fire station; Bob's has neither.
	var site := CivicHubs.site_near(ann.network, Vector3(60, 0, 760))
	_check(ann.apply_now({"type": "place_hub", "kind": "landfill", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "Ann builds a landfill")
	# Her station stands out on the county road toward Swayzee (8 km off),
	# so its 5 road miles reach Bob's homes.
	var fs := Services.site_near(ann.network, Services.Kind.FIRE, Vector3(-1900, 0, 30))
	_check(ann.apply_now({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [fs[0].x, fs[0].z],
		"dir": [fs[1].x, fs[1].z]}), "Ann builds a fire station")

	# Both play a few months: offers come to both bells.
	_months(4, ["c1", "c2"])
	_check(Interlocal.homes(bob) >= Balance.INTERLOCAL_MIN_HOMES, "Bob's town has homes (%d)" % Interlocal.homes(bob))
	var asks := _open(bob)
	var host_asks := _open(ann)
	for q in host_asks:
		_check(not q.deal.get("pays", false) and q.deal.other == "c2", "Ann's leaders ask her first")
	_check(asks.is_empty(), "nothing reaches Bob before Ann approves")
	_check(_open(ann).size() == 2, "Ann's landfill manager and fire chief each ask (%d)" % _open(ann).size())
	for q in host_asks:
		ann.apply_now({"type": "permit", "id": q.id, "answer": "approve"})
	_months(1, ["c1", "c2"])
	asks = _open(bob)
	var kinds := asks.map(func(q): return q.deal.kind)
	_check("trash" in kinds and "fire" in kinds, "Bob is offered trash pickup and fire protection (%s)" % str(kinds))
	_check(not "school" in kinds, "nobody offers what they don't have (no school)")
	_check(r.ledger.agreements.values().filter(func(a): return a.status == "offered").size() == 2,
		"the region's ledger holds each offer until Bob answers")
	for q in asks:
		_check(q.shape == "deal" and q.deal.pays and q.deal.fee >= Balance.INTERLOCAL_MIN_FEE, "an offer says what Bob would pay")
		_check(q.cost == 0 and q.hits.roads.is_empty(), "a service deal builds nothing")
	_check(not bob.permits.answer(bob, {"id": asks[0].id, "answer": "edit", "route": [[0, 0], [1, 1]]}),
		"a deal can't be redrawn, only approved or denied")
	_months(1, ["c1", "c2"])
	_check(_open(bob).size() == asks.size(), "an offer isn't filed twice")

	# Bob approves trash and fire.
	for q in asks:
		bob.apply_now({"type": "permit", "id": q.id, "answer": "approve"})
	_months(1, ["c1", "c2"])
	_check(not bob.interlocal.served_by("trash").is_empty() and not bob.interlocal.served_by("fire").is_empty(),
		"both deals are signed")
	_check(r.ledger.agreements_of("c2").size() == 2, "the region's ledger has them")
	var trash: Dictionary = bob.interlocal.served_by("trash")
	var host_trash: Dictionary = ann.interlocal.deals[trash.id]
	_check(host_trash.role == "host" and host_trash.fee == trash.fee, "Ann's half has the same terms")
	_check(trash.link in bob.region_links and host_trash.link in ann.region_links, "each side uses its county road")
	ann.economy.update_budget(ann)
	bob.economy.update_budget(bob)
	var fees: int = trash.fee + bob.interlocal.served_by("fire").fee
	_check(bob.economy.budget.deals == -fees and ann.economy.budget.deals == fees,
		"Bob pays Ann each month (%d, %d)" % [bob.economy.budget.deals, ann.economy.budget.deals])
	_check(r.ledger.book_month("c2", Interlocal.KINDS.keys()) == 0.0, "and the fee isn't booked twice")

	# Fire: Bob's homes are covered from Ann's station over the county road.
	bob.tick()  # lots are re-figured on the next step
	var covered := 0
	for key in bob.buildings:
		if bob.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL and bob.services.served.get(key, {}).get(Services.Kind.FIRE, false):
			covered += 1
	_check(covered > 0, "Bob's homes have fire protection from Ann's station (%d)" % covered)

	# Trash: Ann's trucks come into Bob's town and haul it back home. The
	# county road is a few miles long, so a run takes a while.
	var saw_pickup := false
	var saw_haul := false
	for m in 24:
		for i in MONTH:
			ann.tick()
			bob.tick()
			for t in bob.interlocal.trips:
				saw_pickup = saw_pickup or bob.interlocal.trips[t].what == "pickup"
			for t in ann.interlocal.trips:
				saw_haul = saw_haul or ann.interlocal.trips[t].what == "haul"
		_month_end(["c1", "c2"])
		if saw_haul:
			break
	_check(saw_pickup, "contract garbage trucks pick up in Bob's town")
	_check(float(bob.interlocal.served_by("trash").picked) > 0.0, "Bob's trash is counted as picked up")
	_check(saw_haul, "Ann's trucks drive out to the county road and back for it")
	_check(not bob.trade.wants.has("garbage"), "Bob no longer pays an outside hauler")

	# Ann goes offline: Bob keeps being served on the last terms.
	var ann_money := ann.economy.money
	var bob_fire: Dictionary = bob.interlocal.served_by("fire").duplicate()
	_months(2, ["c2"])
	_check(ann.economy.money == ann_money, "Ann's town waits while she's away")
	_check(bob.interlocal.served_by("fire").fee == bob_fire.fee and bob.services.contracts.has(Services.Kind.FIRE),
		"Bob is still covered on the last terms")
	# She comes back to the region's copy of her town, deals and all.
	homes.c1 = _welcome("c1")
	ann = homes.c1
	ann.require_utilities = false
	_check(ann.interlocal.deals.has(trash.id) and ann.interlocal.deals.size() == 2, "Ann's deals are waiting for her")

	# A save carries the ledger.
	var copy := Region.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true)))
	_check(var_to_str(copy.ledger.agreements) == var_to_str(r.ledger.agreements), "the region's ledger comes back from a save")
	_check(var_to_str(copy.cities.c2.sim.interlocal.deals) == var_to_str(r.cities.c2.sim.interlocal.deals),
		"each town's deals come back exactly")

	# Bob gives notice: it runs through the notice, then ends on both sides.
	_check(bob.apply_now({"type": "end_deal", "id": trash.id}), "Bob gives notice")
	_check(not bob.apply_now({"type": "end_deal", "id": trash.id}), "once is enough")
	_months(1, ["c1", "c2"])
	_check(int(ann.interlocal.deals[trash.id].left) >= 0, "Ann hears the notice")
	_months(Balance.INTERLOCAL_NOTICE, ["c1", "c2"])
	_check(not bob.interlocal.deals.has(trash.id) and not ann.interlocal.deals.has(trash.id), "the deal ends on both sides")
	_check(not bob.interlocal.served_by("fire").is_empty(), "the fire deal carries on")

	# A "no" from either side drops the offer, and it waits before coming back.
	_months(1, ["c1", "c2"])
	var again := _open(ann).filter(func(q): return q.deal.kind == "trash")
	_check(again.size() == 1, "the landfill manager asks Ann again (%d)" % again.size())
	if again.size() == 1:
		ann.apply_now({"type": "permit", "id": again[0].id, "answer": "approve"})
		_months(1, ["c1", "c2"])
		var bob_again := _open(bob).filter(func(q): return q.deal.kind == "trash")
		_check(bob_again.size() == 1, "and Bob gets the offer")
		if bob_again.size() == 1:
			bob.apply_now({"type": "permit", "id": bob_again[0].id, "answer": "deny"})
			_months(1, ["c1", "c2"])
			_check(r.ledger.agreements.values().any(func(a): return a.service == "trash" and a.status == "denied"),
				"Bob's no is in the ledger")
			_months(1, ["c1", "c2"])
			_check(_open(ann).filter(func(q): return q.deal.kind == "trash").is_empty(), "and it isn't offered again right away")

	# The fee: the host's cost shared by homes, plus the administrative share.
	_check(Interlocal.fee("fire", 300, 100) == roundi(Balance.INTERLOCAL["fire"]["upkeep"] * 0.25 * 1.1 / 100.0) * 100, "fire fee is a share by homes")
	_check(Interlocal.fee("trash", 10_000, 1) == Balance.INTERLOCAL_MIN_FEE, "there's a minimum fee")

	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## A player's computer starting from the region's copy of their town.
func _welcome(id: String) -> CitySim:
	var sim := Region.new_sim()
	sim.terrain_offset = r.cities[id].origin
	sim.from_dict(JSON.parse_string(JSON.stringify(r.cities[id].sim.to_dict(), "", false, true)))
	return sim


## Game months: the online towns play, then the month ends on the server.
func _months(n: int, online: Array) -> void:
	for m in n:
		for i in MONTH:
			for id in online:
				homes[id].tick()
		_month_end(online)


## What the server does: takes each running town's copy and settles trade;
## then each running town goes over its deals and the server books what it
## sends (as RegionClient and RegionServer do, through JSON like the wire).
func _month_end(online: Array) -> void:
	for id in online:
		r.update_city(id, JSON.parse_string(JSON.stringify(homes[id].to_dict(), "", false, true)))
	r.settle_trade(online)
	r.load_stale()
	_sync(online)
	_sync(online)


func _sync(online: Array) -> void:
	for id in online:
		var acts = JSON.parse_string(JSON.stringify(homes[id].interlocal.sync(r, id, homes[id])))
		for act in acts:
			match act.op:
				"offer":
					r.ledger.offer(id, act.to, act.service, act.price, act.capacity)
				"answer":
					r.ledger.answer(act.id, id, act.yes)
				"end":
					r.ledger.end(act.id, id)
	# The ledger goes back out to everyone.
	r.ledger.from_dict(JSON.parse_string(JSON.stringify(r.ledger.to_dict())))


func _open(sim: CitySim) -> Array:
	return sim.permits.listed(Permits.State.OPEN).filter(func(q): return q.hub == "interlocal")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + what)
	else:
		print("ok: " + what)
