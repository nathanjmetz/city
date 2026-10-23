extends SceneTree
## Run: godot --headless -s tests/test_regional.gd
## What the region's shared projects do in each town once their stages are
## funded (Regional, reading the region's Ledger), and the Region panel:
## projects with a stage bar, your share and Pledge buttons, and the
## Services tab answering the same requests as the permit bell.

var _failed := false


func _init() -> void:
	var r := Region.new()
	r.add_city("p1", "Ann")
	r.add_city("p2", "Bob")
	var ann: CitySim = r.cities.c1.sim
	var bob: CitySim = r.cities.c2.sim

	# Nothing funded: nothing changes.
	ann.regional.sync(r, "c1")
	_check(ann.regional.import_markup("steel") == Balance.TRADE_IMPORT_MARKUP and ann.regional.land_lift() == 0.0
		and ann.regional.monthly_income(ann) == 0, "nothing funded, nothing changes")

	# The benefit: reach x (base + rest x share next to the top pledger).
	var near := Regional.benefit(Vector2.ZERO, Vector2(8000, 0), 1.0)
	_check(is_equal_approx(near, 0.9), "a top pledger 8 km away gets 0.9 (%.2f)" % near)
	_check(is_equal_approx(Regional.benefit(Vector2.ZERO, Vector2(8000, 0), 0.0), 0.36), "a near town that paid nothing gets a little")
	_check(Regional.benefit(Vector2.ZERO, Vector2(90_000, 0), 1.0) == 0.0, "past an hour's drive, nothing")

	# Ann funds the I-69 right of way and interchange.
	var took := _fund(r, "c1", "i69", 10_000_000.0)
	_check(took == 10_000_000.0 and Ledger.stages_done(r.ledger.projects.i69) == 2, "two I-69 stages funded")
	ann.regional.sync(r, "c1")
	bob.regional.sync(r, "c2")
	var a_mk := ann.regional.import_markup("steel")
	var b_mk := bob.regional.import_markup("steel")
	_check(a_mk < Balance.TRADE_IMPORT_MARKUP and a_mk >= Balance.REGION_I69_MARKUP, "the interchange cuts Ann's import markup (%.3f)" % a_mk)
	_check(b_mk < Balance.TRADE_IMPORT_MARKUP and b_mk > a_mk, "Bob gets a little too, less than Ann (%.3f)" % b_mk)
	_check(ann.regional.land_lift() > bob.regional.land_lift() and bob.regional.land_lift() > 0.0, "land near the road gains value")
	_check(ann.regional.demand_shift(ZoneMap.Zone.INDUSTRIAL) == 0.0, "four lanes aren't funded yet")
	_check(ann.regional.effects("i69").size() == 2, "the panel lists what the funded stages do (%s)" % str(ann.regional.effects("i69")))

	# Trade with the outside world uses the town's markup.
	ann.trade.want("steel", 10.0)
	Trade.settle({"c1": ann}, {})
	var outside := ann.trade.last_deals.filter(func(d): return d.good == "steel" and d.seller == "outside")
	_check(outside.size() == 1 and is_equal_approx(float(outside[0].price), Trade.base_price("steel") * a_mk),
		"steel from outside costs the cheaper markup")

	# The power co-op: members save on their line feeds, and get capital credits.
	var fs := Services.site_near(ann.network, Services.Kind.POWER_FEED, Vector3(30, 0, 30))
	ann.economy.money = 50_000_000
	_check(fs.size() > 0 and ann.apply_now({"type": "place_service", "kind": Services.Kind.POWER_FEED,
		"pos": [fs[0].x, fs[0].z], "dir": [fs[1].x, fs[1].z]}), "Ann has a power line feed")
	_fund(r, "c1", "power", 12_000_000.0)
	ann.regional.sync(r, "c1")
	bob.regional.sync(r, "c2")
	_check(ann.regional.coop_saving(ann) > 0.0, "a co-op member's feed power is cheaper ($%d a month)" % roundi(ann.regional.coop_saving(ann)))
	_check(bob.regional.coop_saving(bob) == 0.0 and bob.regional.effects("power") == ["Pledge any amount to join the co-op"],
		"Bob isn't a member until he pledges")
	var credits := ann.regional.monthly_income(ann) - roundi(ann.regional.coop_saving(ann))
	_check(credits == roundi(Balance.REGION_COOP_CREDITS_YEAR / 12.0), "Ann gets all the capital credits ($%d a month)" % credits)
	ann.economy.update_budget(ann)
	_check(int(ann.economy.budget.region) == ann.regional.monthly_income(ann), "the budget has a Regional projects line")

	# The airport: runway demand, then visitors.
	_fund(r, "c2", "airport", 23_000_000.0)
	bob.regional.sync(r, "c2")
	_check(bob.regional.demand_shift(ZoneMap.Zone.COMMERCIAL) > 0.0 and bob.regional.air_visitors_year() > 0.0,
		"the runway brings office demand and the terminal brings visitors")

	# A save keeps it.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(ann.to_dict(), "", false, true)))
	_check(var_to_str(copy.regional.projects) == var_to_str(ann.regional.projects), "a save keeps what the projects do")

	# The panel.
	var pledged := []
	var panel := RegionPanel.new()
	root.add_child(panel)
	panel.setup(ann, r, "c1", func(id, amount): pledged.append([id, amount]))
	panel.open_panel()
	_check(panel._list.get_child_count() == 2 + Balance.REGION_PROJECTS.size(), "the metro, then one card per project")
	_check(_labels(panel._list).any(func(t): return "Next: Jasper, IN" in t), "the panel shows the next metro")
	var buttons := _buttons(panel._list).filter(func(b): return b.text.begins_with("Pledge"))
	_check(buttons.size() == 2, "Pledge buttons only where the metro is big enough and a stage is open (%d)" % buttons.size())
	_check(_labels(panel._list).any(func(t): return "Opens when the metro reaches 250,000" in t), "the airport waits for a bigger metro")
	buttons[0].pressed.emit()
	_check(pledged.size() == 1 and pledged[0][1] == 100_000.0, "a pledge goes to the region")
	_check(_labels(panel._list).any(func(t): return "Your share 100%" in t), "the panel shows your share")

	# Services tab: a neighbor's offer answered here answers the bell too.
	var aid := r.ledger.offer("c2", "c1", "fire", 9_000.0, 50.0)
	ann.interlocal.sync(r, "c1", ann)
	panel.show_tab("services")
	var accept := _buttons(panel._list).filter(func(b): return b.text == "Accept")
	_check(accept.size() == 1, "Bob's offer is on the Services tab")
	if accept.size() == 1:
		accept[0].pressed.emit()
		var acts := ann.interlocal.sync(r, "c1", ann)
		_check(acts.any(func(a): return a.op == "answer" and a.id == aid and a.yes), "accepting sends the answer")
	panel.queue_free()

	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## Pledges stage after stage, as a player pressing Pledge would.
func _fund(r: Region, city: String, id: String, amount: float) -> float:
	var total := 0.0
	while amount - total > 0.5:
		var took := r.ledger.pledge(city, id, "money", amount - total)
		if took <= 0.0:
			break
		total += took
	return total


func _buttons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func _labels(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Label:
			out.append(c.text)
		out.append_array(_labels(c))
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + what)
	else:
		print("ok: " + what)
