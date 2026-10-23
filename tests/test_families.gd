extends SceneTree
## Run: godot --headless -s tests/test_families.gd

var _failed := false


func _init() -> void:
	var sim := _town(7)
	var fam := sim.families
	var shops := []
	for key in sim.buildings:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL:
			shops.append("lot:" + key)
	_check(shops.size() >= 6, "shops and factories grew (%d)" % shops.size())
	if shops.is_empty():
		quit(1)
		return
	var names := {}
	for ref in shops:
		var n := fam.name_of(ref)
		_check(n != "", "%s has a name" % ref)
		_check(not names.has(n), "names are unique (%s)" % n)
		names[n] = true
		_check(not fam.family_of(ref).is_empty(), "%s has a family behind it" % n)
		var s := fam.sign_of(sim, ref)
		_check(s.text == n and s.style in Names.STYLES, "its sign carries the name in a real lettering style")
	print("  names: ", ", ".join(names.keys()))

	# Same town, same names: every copy of a city agrees (multiplayer).
	var twin := _town(7)
	for ref in shops:
		_check(twin.families.name_of(ref) == fam.name_of(ref), "a second copy names %s the same" % ref)

	# Saved and loaded, nothing changes name.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for ref in shops:
		_check(copy.families.name_of(ref) == fam.name_of(ref), "a loaded city keeps %s" % fam.name_of(ref))

	# A family that's done well asks to branch out, by permit only.
	var ref0: String = shops[0]
	var owner := fam.family_of(ref0)
	owner.cash = 5_000_000
	owner.ambition = 1.0
	# Two years in business, so it's ready.
	var asked := -1
	for m in 400:
		_month(sim)
		if not owner.plan.is_empty():
			asked = int(owner.plan.req)
			break
	_check(asked > 0, "a family doing well files a permit to branch out")
	if asked > 0:
		var req: Dictionary = sim.permits.requests[asked]
		_check(req.hub == Families.HUB and str(req.title).begins_with("The %s family wants to" % owner.surname),
			"the bell names the family and what it wants (%s)" % req.title)
		var plan: Dictionary = owner.plan
		var before := fam.hubs_of(int(owner.id)).size()
		sim.apply({"type": "permit", "id": asked, "answer": "approve"})
		_month(sim)
		var after := fam.hubs_of(int(owner.id))
		_check(after.size() == before + 1, "approved, the family owns one more business (%d to %d)" % [before, after.size()])
		_check(fam.name_of(plan.ref) == plan.name, "it carries the family's name: %s" % plan.name)
		_check(fam.sign_of(sim, plan.ref).style == fam.sign_of(sim, ref0).style
			and fam.sign_of(sim, plan.ref).panel == fam.sign_of(sim, ref0).panel, "and the family's look")
		if plan.kind == "buy":
			_check(str(plan.from) in fam.owned[plan.ref].formerly, "a bought business remembers its old name")
		else:
			_check(sim.buildings.has(str(plan.ref).substr(4)), "a new business opens on the zoned lot")

	# Never more than the cap in one town.
	owner.cash = 50_000_000
	for m in 600:
		_month(sim)
		if not owner.plan.is_empty():
			sim.apply({"type": "permit", "id": int(owner.plan.req), "answer": "approve"})
	_check(fam.hubs_of(int(owner.id)).size() <= Balance.FAMILY_MAX_HUBS,
		"a family owns at most %d businesses (%d)" % [Balance.FAMILY_MAX_HUBS, fam.hubs_of(int(owner.id)).size()])
	_check(int(owner.gen) >= 2, "after %d years a new generation runs it (%s)" % [Balance.FAMILY_GENERATION_YEARS, owner.head])
	_check(int(owner.redone) > 0, "an old family redid its look")
	_check(fam.sign_of(sim, ref0).since > 2026 or not fam.owned.has(ref0), "an old business's sign shows its year")

	# Deny means no.
	var other := CitySim.new()
	other.from_dict(JSON.parse_string(JSON.stringify(_town(11).to_dict())))
	var f2: Dictionary = other.families.families.values()[0]
	f2.cash = 5_000_000
	f2.ambition = 1.0
	var denied := -1
	var count0 := 0
	for m in 400:
		_month(other)
		if not f2.plan.is_empty():
			denied = int(f2.plan.req)
			count0 = other.families.hubs_of(int(f2.id)).size()
			other.apply({"type": "permit", "id": denied, "answer": "deny"})
			_month(other)
			break
	_check(denied > 0 and other.families.hubs_of(int(f2.id)).size() == count0, "denied, nothing changes hands")

	_check(Families.home_name({"seed": 42}).ends_with(" home"), "homes carry their family's name")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## A main street: a road with shops on one side and homes on the other,
## grown for a while.
func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12,
			"zone": ZoneMap.Zone.COMMERCIAL if x < 40 else ZoneMap.Zone.INDUSTRIAL})
	for i in 600:
		sim.tick()
	# Fill most of the shop and factory lots straight away (leaving a few
	# empty for families to open on).
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	for k in empty.size():
		var key: String = empty[k]
		var z: int = sim.zones.zone_at(sim.lots[key].zone_pt)
		if z != ZoneMap.Zone.RESIDENTIAL and k % 4 != 0:
			sim.found_business(key, z)
	for i in 600:
		sim.tick()
	return sim


## A game month passes for the families (the rest of town stands still).
func _month(sim: CitySim) -> void:
	sim.tick_count += 24 * CitySim.TICKS_PER_HOUR
	sim.permits.tick(sim)
	sim.families.month(sim)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
