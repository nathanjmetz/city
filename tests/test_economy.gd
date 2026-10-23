extends SceneTree
## Run: godot --headless -s tests/test_economy.gd
## The Economy page's sliders (Brawn: money is a limiter, not the game): a
## hub follows its area and an area the town until it's given its own; each
## step changes what things cost and how they grow; Growth is the same word
## as the leader's stance; and it all saves.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	var p := sim.policies
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})

	# Scopes: hub -> area -> town -> Standard.
	_check(p.step("funding", "farms", "farm:1") == Policies.STANDARD, "nothing set: Standard")
	_check(sim.apply({"type": "policy", "scope": "city", "slider": "funding", "step": 1}), "set the town's Funding")
	_check(p.step("funding", "farms", "farm:1") == 1, "an area and hub follow the town")
	_check(not sim.apply({"type": "policy", "scope": "area:farms", "slider": "funding", "step": 9}), "no step 9")
	_check(not sim.apply({"type": "policy", "scope": "area:utilities", "slider": "growth", "step": 3}),
		"power and water have no Growth slider")
	_check(not sim.apply({"type": "policy", "scope": "farm:7", "slider": "growth", "step": 3}), "no such farm")
	sim.apply({"type": "policy", "scope": "area:farms", "slider": "funding", "step": 4})
	_check(p.step("funding", "farms", "farm:1") == 4 and p.step("funding", "homes") == 1, "an area overrides the town only for itself")

	# Services: Funding sets upkeep and reach.
	var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(0, 0, -40))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a fire station")
	var sid: int = sim.services.buildings.keys()[0]
	var base := int(Services.KINDS[Services.Kind.FIRE].upkeep)
	sim.apply({"type": "policy", "scope": "city", "slider": "funding", "step": 2})
	_check(sim.services.upkeep_of(sid) == base, "Standard costs the listed upkeep")
	_check(sim.apply({"type": "policy", "scope": "service:%d" % sid, "slider": "funding", "step": 0}), "a lean fire station")
	_check(sim.services.upkeep_of(sid) == roundi(base * Balance.POLICY_UPKEEP[0]), "lean costs less (%d)" % sim.services.upkeep_of(sid))
	_check(sim.services.funding(sid, Balance.POLICY_EFFECT) < 1.0, "and reaches less far")
	_check(sim.apply({"type": "policy", "scope": "service:%d" % sid, "slider": "funding", "step": -1}), "back to following")
	_check(p.own("service:%d" % sid, "funding") == -1 and sim.services.upkeep_of(sid) == base, "following again")

	# Hubs with their own money lever take it from Funding: the post office.
	var ps := CivicHubs.site_near(sim.network, Vector3(250, 0, 40))
	_check(sim.apply({"type": "place_post_office", "pos": [ps[0].x, ps[0].z], "dir": [ps[1].x, ps[1].z]}), "a post office")
	var po: int = sim.mail.offices.keys()[0]
	var pkey := "post_office:%d" % po
	_check(sim.hub_area(pkey) == "mail" and sim.mail.offices[po].funding == 1, "it's on the page, at Basic (Standard)")
	sim.apply({"type": "policy", "scope": "area:mail", "slider": "funding", "step": 4})
	_check(sim.mail.offices[po].funding == Balance.POLICY_MAIL_FUNDING[4], "Generous: Lavish funding")
	_check(sim.apply({"type": "post_office_funding", "id": po, "level": 0}) and sim.mail.offices[po].funding == 0
		and p.own(pkey, "funding") == 0, "the old command still works and sets the slider")
	_check(sim.apply({"type": "policy", "scope": pkey, "slider": "funding", "step": -1})
		and sim.mail.offices[po].funding == 3, "following the area again")
	sim.apply({"type": "policy", "scope": "area:mail", "slider": "funding", "step": -1})
	_check(sim.mail.offices[po].funding == 1, "and back to Standard")
	sim.tick()  # the postmaster signs up with Permits on the first tick
	sim.apply({"type": "policy", "scope": pkey, "slider": "growth", "step": 0})
	_check(sim.permits.guidance("post_office", po).stance == "hold", "Growth Hold tells the postmaster to hold off")
	sim.apply({"type": "policy", "scope": pkey, "slider": "growth", "step": -1})
	_check(not sim.apply({"type": "policy", "scope": "power:9", "slider": "growth", "step": 0}), "no such power company")
	var pw := Power.new()
	var pwp := Policies.new()
	pw.policies = pwp
	pwp.set_step("area:power", "growth", 0)
	_check(pw.on_hold(1), "power companies on Hold add no units")

	# Farms: Growth Hold buys nothing; Funding is aid the town pays.
	var farm := Farms.new()
	var fp := Policies.new()
	farm.policies = fp
	# On the real valley terrain, pick good farmland for it.
	var spot := Vector3(0, 0, -600)
	var best := -1.0
	for x in range(-3000, 3001, 250):
		for z in range(-3000, 3001, 250):
			var f := Farms.fertility_at(Vector3(x, 0, z))
			if f > best:
				best = f
				spot = Vector3(x, 0, z)
	var fid := farm.add_farm(spot, Vector3(0, 0, 1), "corn", [])
	var anywhere := func(_m, _c): return true
	farm.decide(anywhere)
	fp.set_step("farm:%d" % fid, "growth", 0)
	for i in 4:
		farm.decide(anywhere)
	_check(farm.farms[fid].cells.is_empty(), "a farm on Hold buys no fields")
	fp.set_step("farm:%d" % fid, "growth", -1)
	for i in 4:
		farm.decide(anywhere)
	var standard_fields: int = farm.farms[fid].cells.size()
	_check(standard_fields == 4, "Your call: it buys a field a step (%d)" % standard_fields)
	_check(is_zero_approx(farm.yearly_support()), "Standard: no aid, no fee")
	fp.set_step("area:farms", "funding", 4)
	_check(farm.yearly_support() > 0.0, "Generous: the town pays farm aid")
	fp.set_step("area:farms", "funding", 0)
	_check(farm.yearly_support() < 0.0, "Lean: the town collects a fee")

	# Zoned growth: Hold builds no new homes.
	var town := CitySim.new()
	town.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-200, 201, 10):
		town.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	town.apply({"type": "policy", "scope": "area:homes", "slider": "growth", "step": 0})
	for i in 400:
		town.tick()
	_check(town.buildings.is_empty(), "homes on Hold: nothing new goes up")
	town.apply({"type": "policy", "scope": "area:homes", "slider": "growth", "step": 4})
	for i in 400:
		town.tick()
	_check(not town.buildings.is_empty(), "Expand: homes go up (%d)" % town.buildings.size())
	# Street care: Generous costs money, Lean saves some.
	town.apply({"type": "policy", "scope": "area:homes", "slider": "funding", "step": 4})
	town.update_stats()
	_check(int(town.economy.budget.care) > 0, "generous street care costs money")
	var rich := int(town.economy.budget.income[ZoneMap.Zone.RESIDENTIAL])
	town.apply({"type": "policy", "scope": "area:homes", "slider": "funding", "step": 0})
	town.update_stats()
	_check(int(town.economy.budget.care) < 0 and int(town.economy.budget.income[ZoneMap.Zone.RESIDENTIAL]) < rich,
		"lean saves on care, but land and taxes are worth less")

	# Growth is the leader's stance, both ways.
	sim.permits.locators["service"] = func(s, id): return Vector2(s.services.buildings[id].pos.x, s.services.buildings[id].pos.z)
	sim.apply({"type": "guide", "hub": "farm", "hub_id": 99, "stance": "hold", "grant": 0})
	_check(sim.policies.own("farm:99", "growth") == -1, "a guide for a hub that doesn't exist sets no slider")
	sim.apply({"type": "policy", "scope": "city", "slider": "growth", "step": 0})
	_check(sim.permits.guidance("service", sid).stance == "hold", "the town on Hold tells leaders to hold off")
	_check(not sim.permits.can_file(sim, "service", sid), "a leader on Hold files no permits")
	sim.apply({"type": "policy", "scope": "city", "slider": "growth", "step": 4})
	_check(sim.permits.guidance("service", sid).stance == "grow", "Expand tells them to grow")
	sim.apply({"type": "guide", "hub": "service", "hub_id": sid, "stance": "hold", "grant": 250})
	_check(sim.policies.step("growth", "public", "service:%d" % sid) == 0, "Hold off from the leader row sets Growth to Hold")
	_check(sim.policies.step("growth", "public", "service:%d" % 0) == 4, "other hubs keep the town's setting")

	# Reset and save.
	_check(sim.apply({"type": "policy_reset", "scope": "city"}), "everything follows the town again")
	_check(sim.policies.levels.keys() == ["city"], "only the town's own settings are left (%s)" % str(sim.policies.levels.keys()))
	sim.apply({"type": "policy", "scope": "area:waste", "slider": "growth", "step": 1})
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.policies.step("growth", "waste") == 1 and copy.policies.step("growth", "homes") == 4, "sliders save and load")
	sim.apply({"type": "post_office_funding", "id": po, "level": 3})
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy2.mail.offices[po].funding == 3 and copy2.policies.step("funding", "mail", pkey) == 4,
		"a saved lever keeps its amount and its slider")
	copy.apply({"type": "clear"})
	_check(copy.policies.levels.is_empty() and copy.farms.policies == copy.policies, "a new map starts at Standard")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
