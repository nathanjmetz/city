class_name BankInfo
extends RefCounted
## The info panel for a community bank or Farm Credit office: who runs it
## and how they lend, its deposits, loans and equity, this year's lending
## and foreclosures, and its development tree. The player sets nothing about
## the loans; the leader guide below it (grow, your call, hold off) comes
## from Permits.


static func describe(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.banks.banks[id]
	var k: Dictionary = Banks.KINDS[b.kind]
	var l: Dictionary = b.leader
	var lent := Banks.loans_total(b)
	var ratio := Banks.capital_ratio(b)
	var y: Dictionary = b.get("last_year", b.year) if b.year.lent <= 0.0 and b.has("last_year") else b.year
	var rows := [
		[k.head, str(l.name)],
		["", "%s, %s" % [Education.degree_name(l.edu), Banks.leader_style(l)]],
		["Lends", "%d%% of the price, if profit covers the payments %.2f times" % [roundi(Banks.ltv(b) * 100.0),
			Banks.dscr_needed(b)]],
		["Loans", "$%s to %d borrower%s" % [CitySim.money_text(roundi(lent)), b.loans.size(),
			"" if b.loans.size() == 1 else "s"]],
	]
	if b.kind == "community":
		rows.append(["Deposits", "$%s" % CitySim.money_text(roundi(b.deposits))])
	rows.append(["Equity", "%s$%s (%.1f%% of loans)" % ["" if b.capital >= 0.0 else "-",
		CitySim.money_text(absi(roundi(b.capital))), minf(ratio, 9.99) * 100.0]])
	rows.append(["Could still lend", "$%s" % CitySim.money_text(roundi(sim.banks.room(sim, id)))])
	rows.append(["This year", "$%s lent, %s$%s profit" % [CitySim.money_text(roundi(y.lent)),
		"" if y.profit >= 0.0 else "-", CitySim.money_text(absi(roundi(y.profit)))]])
	rows.append(["Foreclosures", "%d this year, %d in all" % [int(y.foreclosed), int(b.foreclosed)]])
	rows.append(["Staff", str(Banks.staff(b))])
	rows.append(["Reputation", "%d%%" % roundi(b.reputation * 100.0)])
	var mix := {}
	for who in b.loans:
		var what: String = {"farm": "farms", "company": "companies", "timber": "timber", "build": "builders"}.get(
			str(b.loans[who].kind), "other")
		mix[what] = mix.get(what, 0.0) + float(b.loans[who].balance)
	if not mix.is_empty():
		var parts := []
		for what in ["farms", "companies", "timber", "builders"]:
			if mix.has(what):
				parts.append("%s $%s" % [what, CitySim.money_text(roundi(mix[what]))])
		rows.append(["Lent to", ", ".join(parts)])
	# Its development tree.
	var facts := Banks.town_facts(sim)
	var built := []
	for blk in b.blocks:
		built.append(Banks.dev(b.kind, blk.use).get("name", blk.use))
	if not built.is_empty():
		rows.append(["Built", ", ".join(built)])
	var next := Banks.pick_next(sim, b, facts)
	if next != "" and b.blocks.size() < int(Banks.spec(b.kind).max_blocks):
		rows.append(["Plans next", Banks.dev(b.kind, next).name])
	var shown := 0
	for d in Banks.TREE[b.kind]:
		var why := Banks.locked_by(sim, b, d.id, facts)
		if why != "" and why != "built" and shown < 3:
			rows.append([d.name, why])
			shown += 1
	var problems := []
	var status := "Lending"
	match Banks.health(b):
		"well": status = "Well capitalized: lending"
		"adequate": status = "Thin on equity: lending slowly"
		"order": status = "Under a regulator's order: not lending"
	if b.status == "sold":
		status = "Failed: the FDIC sold it to a healthier bank"
		problems.append("Too many loans went bad. The buyer put in new equity and hired %s, a careful lender." % l.name)
	if b.kind == "community" and b.deposits < 1_000_000.0:
		problems.append("Few deposits yet: a bank lends what the town saves, so it grows with the town.")
	if b.idle != "":
		problems.append(b.idle)
	elif b.get("why", "") != "":
		rows.append(["Latest", b.why])
	return {"title": b.name, "kind": k.name, "icon": k.icon, "ok": problems.is_empty(), "status": status,
		"rows": rows, "problems": problems, "actions": []}
