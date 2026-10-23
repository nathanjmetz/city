class_name BigFactoryInfo
extends RefCounted
## The info panel for a big local factory: who runs it, what it makes, where
## its inputs come from, its books, its development tree and why it did what
## it did last.


## Same shape as Inspect.describe, plus `actions`.
static func describe(sim: CitySim, id: int) -> Dictionary:
	var big := sim.big
	var f: Dictionary = big.sites[id]
	var k: Dictionary = BigFactories.KINDS[f.kind]
	var s := BigFactories.spec(f)
	var lead: Dictionary = f.leader
	var ref := "big:%d" % id
	var rows := [
		["Owner", "%s%s" % [BigFactories.leader_name(f), ", college-educated" if float(lead.edu) >= 0.5 else ""]],
		["Makes", "%s (%.0f loads a month at most)" % [k.makes, big.capacity(f)]],
	]
	var inputs := []
	for input in s["in"]:
		inputs.append("%.0f %s" % [float(f.stock[input]), input])
	rows.append(["Inputs on hand", ", ".join(inputs)])
	var coming := 0.0
	var bought := 0.0
	for input in s["in"]:
		coming += float(f.promised[input])
		bought += float(f.due[input])
	rows.append(["On the way in", "%.0f loads, %.0f more bought from the region" % [coming, bought]])
	var waiting := []
	for good in f.out:
		if float(f.out[good]) >= 1.0:
			waiting.append("%d %s" % [floori(float(f.out[good])), good])
	rows.append(["Waiting to ship", ", ".join(waiting) if not waiting.is_empty() else "nothing"])
	rows.append(["Trucks on the road", str(sim.logistics.trucks_for(ref))])
	var last: Dictionary = f.get("last", {})
	if not last.is_empty():
		rows.append(["Last month", "%d made, %d%% busy" % [roundi(float(last.made)), roundi(float(last.util) * 100.0)]])
	var profit := big.yearly_profit(f)
	rows.append(["Profit", "%s$%s / year" % ["" if profit >= 0.0 else "-", CitySim.money_text(absi(roundi(profit)))]])
	rows.append(["Owner's money", "$%s" % CitySim.money_text(roundi(float(f.cash)))])
	rows.append(["Jobs", str(big.jobs_at(f))])
	rows.append(["Property tax to town", "$%s / month" % CitySim.money_text(roundi(BigFactories.value(f)
		* sim.economy.tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0))])
	rows.append(["Size", "%d × %d m, %d line%s" % [roundi(BigFactories.site_width(f)), roundi(BigFactories.site_depth(f)),
		int(f.level) + 1, "" if int(f.level) == 0 else "s"]])
	# The development tree: what's built, what's open, and what each still needs.
	for node in BigFactories.TREES[f.kind]:
		var mark := "✓ built"
		if not node.id in f.built:
			mark = _missing(sim, f, node)
		rows.append([str(node.name), mark])
	var problems := []
	var status := "Working: making %s" % k.makes
	if last.is_empty():
		status = "Starting up: buying its first loads"
	elif float(last.made) < 0.5:
		status = "Idle: waiting for inputs"
	if sim.region_links.is_empty():
		problems.append("The town has no county road out, so it can't buy from or sell to the region.")
	if sim.logistics.stuck.has(ref):
		problems.append("Its trucks can't get through. Connect its street to the rest of town.")
	if f.get("boxed", false):
		problems.append(str(f.why))
	if float(f.cash) < 0.0:
		problems.append("It's borrowing to stay open.")
	var why := str(f.get("why", ""))
	if why != "" and not f.get("boxed", false):
		status += " · " + why
	var actions := [{"label": "Demolish", "cmd": {"type": "remove_big_factory", "id": id}, "enabled": true}]
	return {"title": str(f.name), "kind": k.name, "icon": k.icon, "ok": problems.is_empty(),
		"status": status, "rows": rows, "problems": problems, "actions": actions}


## What a tree step still needs, in a few words.
static func _missing(sim: CitySim, f: Dictionary, node: Dictionary) -> String:
	for r in node.get("requires", []):
		if not r in f.built:
			for other in BigFactories.TREES[f.kind]:
				if other.id == r:
					return "after the %s" % str(other.name).to_lower()
	var profit := sim.big.yearly_profit(f)
	for c in node.get("needs", {}):
		var v = node.needs[c]
		if Agency.holds(sim, f, BigFactories.center(f), profit, c, v):
			continue
		match c:
			"population": return "needs %s people in town" % CitySim.money_text(int(v))
			"leader_edu": return "needs a more educated owner"
			"education": return "needs more schooling in town"
			"profit": return "needs $%s a year profit" % CitySim.money_text(int(v))
			"link": return "needs a road out to the region"
			"local:farm": return "needs %d farm%s nearby" % [int(v), "" if int(v) == 1 else "s"]
			"local:forest": return "needs a forestry company nearby"
			"local:metal": return "needs a metal works nearby"
		return "not yet"
	return "$%s, when the owner can afford it" % CitySim.money_text(int(node.cost))
