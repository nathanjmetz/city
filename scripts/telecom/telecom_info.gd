class_name TelecomInfo
extends RefCounted
## The info panel for the phone company: its manager and how they run it,
## customers, the network (towers, fiber), its books, its development tree
## (what it has, plans next, and what is still locked and why), and the one
## lever the player holds besides the leader guide: the city's broadband
## grant. The leader guide below it (grow, your call, hold off) comes from
## Permits.


static func describe(sim: CitySim, id: int) -> Dictionary:
	var c: Dictionary = sim.telecom.companies[id]
	var l: Dictionary = c.leader
	var m := Telecom.books(c)
	var net: float = (m[0] - m[1]) * 12.0
	var levels: Array = Balance.TELECOM_FUNDING_LEVELS
	var level := clampi(int(c.funding), 0, levels.size() - 1)
	var kinds := {}
	for t in c.towers:
		kinds[t.kind] = kinds.get(t.kind, 0) + 1
	var towers := []
	for k in ["lattice", "monopole", "monopine"]:
		if kinds.has(k):
			towers.append("%d %s" % [kinds[k], {"lattice": "lattice", "monopole": "monopole", "monopine": "monopine"}[k]])
	var s: Dictionary = c.subs
	var rows := [
		["General manager", Telecom.leader_name(l)],
		["", Telecom.leader_style(l)],
		["Cell towers", ", ".join(towers) if not towers.is_empty() else "none"],
		["Fiber", "%.1f km of street (%d crew%s)" % [Telecom.fiber_m(c) / 1000.0, Telecom.crews(c),
			"" if Telecom.crews(c) == 1 else "s"]],
		["Customers", "%s homes on fiber, %s businesses, %s cell households" % [CitySim.money_text(roundi(s.fiber)),
			CitySim.money_text(roundi(s.business)), CitySim.money_text(roundi(s.wireless))]],
		["Town signal", "%d%% (households with good service)" % roundi(sim.telecom.town_signal * 100.0)],
		["Remote workers", CitySim.money_text(sim.telecom.remote_workers)],
		["Plans ahead", "%d years" % roundi(Telecom.horizon(sim, id, c))],
		["City grant", "$%s / month (%d%%)" % [CitySim.money_text(Telecom.monthly_grant(c)), roundi(levels[level] * 100.0)]],
		["Surplus", "%s$%s / year" % ["" if net >= 0.0 else "-", CitySim.money_text(absi(roundi(net)))]],
		["Savings", "%s$%s" % ["" if c.savings >= 0.0 else "-", CitySim.money_text(absi(roundi(c.savings)))]],
	]
	if int(s.fixed) > 0:
		rows.insert(5, ["Fixed wireless", "%s farm and rural homes" % CitySim.money_text(roundi(s.fixed))])
	# Its development tree, on the shared Agency model.
	c.facts = Telecom.facts_of(sim, c)
	var dev_rows := Inspect._development(sim, c, Telecom.TREE, c.pos, minf(Telecom.yearly_profit(c), c.savings))
	rows.append_array(dev_rows.slice(1))  # the manager is shown above
	var problems := []
	var status := "Building out the network"
	if not c.pending.is_empty():
		status = "Waiting on your answer: a new %s" % Telecom.TOWERS[c.pending.kind].name
	elif sim.telecom.town_signal >= 0.9 and Telecom.fiber_m(c) > 0.0:
		status = "Town well covered"
	if c.idle != "":
		problems.append(c.idle)
	# The grant is set by its Funding slider (Economy page).
	return {"title": "Phone company", "kind": "Phone and internet", "icon": "tower", "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems}
