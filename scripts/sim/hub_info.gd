class_name HubInfo
extends RefCounted
## The info panel for a landfill, recycling centre or cemetery: whether it
## works, its trucks and land, what it does to land value nearby, and the
## Upgrade and Demolish buttons.


## Same shape as Inspect.describe, plus `actions`: [{label, cmd, enabled}].
static func describe(sim: CitySim, id: int) -> Dictionary:
	var hubs := sim.hubs
	var h: Dictionary = hubs.hubs[id]
	var k: Dictionary = CivicHubs.KINDS[h.kind]
	var s: Dictionary = Balance.WASTE_SITES[h.kind]
	var rows := []
	var problems := []
	var linked := not RoadIndex.segment_near(sim.network, h.pos, 80.0, 1.0).is_empty()
	var acres: float = CivicHubs.land_area(h) / 4046.86
	var most := CivicHubs.max_pieces(h)
	var status := ""
	if CivicHubs.is_waste(h.kind):
		var waiting := 0.0
		var streets := 0
		for seg in hubs.trash:
			if hubs.trash[seg] >= Balance.GARBAGE_STOP_LB:
				waiting += hubs.trash[seg]
				streets += 1
		var out := hubs.trucks_out(id)
		rows.append(["Garbage trucks", "%d of %d out" % [out, hubs.trucks(id)]])
		rows.append(["Trash out in town", "%s tons on %d streets" % [_tons(waiting), streets]])
		rows.append(["Brought in so far", "%s tons" % _tons(h.received)])
		status = "Working: collecting trash" if linked else "Not working"
		if not linked:
			problems.append("Not beside a road, so its trucks can't get out.")
		elif out >= hubs.trucks(id) and streets > 0:
			problems.append("Every truck is out. When it stays this busy it takes more land next door for more trucks.")
	else:
		rows.append(["Serves", "the whole town"])
		status = "A quiet, well-kept place"
	rows.append(["Land", "%.1f acres (%d of %d pieces)" % [acres, h.cells.size(), most]])
	var effect := float(s.value)
	if h.scar > 0.0:
		rows.append(["Old landfill", "grassed over in %d days" % ceili(h.scar)])
	if absf(effect) > 0.0:
		rows.append(["Land value next door", "%+d%%, fading by %.1f mi" % [roundi(effect * 100.0), float(s.reach) / 1609.0]])
	else:
		rows.append(["Land value next door", "no change"])
	var size := 1.0 + Balance.HUB_PIECE_UPKEEP * CivicHubs.extra_pieces(h)
	rows.append(["Upkeep", "$%s / day" % CitySim.money_text(roundi(float(s.upkeep) * hubs.policy_funding(id, Balance.POLICY_UPKEEP) * size))])
	if s.has("sales"):
		rows.append(["Materials sold", "$%s / day" % CitySim.money_text(roundi(CivicHubs.sales(h) * size))])
	if h.get("boxed", false):
		problems.append("No free land next to it to grow into.")
	# Its leader and development tree: built, last move, next, and what's locked.
	rows.append_array(Inspect._development(sim, h, CivicHubs.tree(h), h.pos, CivicHubs.funding(h)).filter(
		func(r): return not r[0] in ["Built", "Could build next", "Held back"]))
	for node in CivicHubs.tree(h):
		if node.id in h.built:
			rows.append([node.name, _dev_note(sim, node.effects)])
	for node in CivicHubs.tree(h):
		var why := hubs.dev_problem(sim, id, node.id)
		if why != "built":
			rows.append([node.name, "next up" if why == "" else why])
	var actions := []
	var next: String = k.next
	if next != "":
		var cost := CivicHubs.upgrade_cost(h.kind)
		var verb := "Replace with" if h.kind == "landfill" else "Upgrade to"
		actions.append({"label": "%s %s ($%s)" % [verb, CivicHubs.KINDS[next].name.to_lower(), CitySim.money_text(cost)],
			"cmd": {"type": "upgrade_hub", "id": id}, "enabled": cost <= sim.economy.money})
	actions.append({"label": "Demolish", "cmd": {"type": "remove_hub", "id": id}, "enabled": true})
	return {"title": k.name, "kind": "Waste" if CivicHubs.is_waste(h.kind) else "Cemetery", "icon": k.icon,
		"ok": problems.is_empty() and linked, "status": status, "rows": rows, "problems": problems,
		"actions": actions}


static func _tons(lb: float) -> String:
	var t := lb / 2000.0
	return "%.1f" % t if t < 100.0 else CitySim.money_text(roundi(t))


## One line on what a development does, with last month's trade.
static func _dev_note(sim: CitySim, dv: Dictionary) -> String:
	if dv.has("sales*"):
		return "+%d%% materials sold" % roundi(float(dv["sales*"]) * 100.0)
	if dv.has("power"):
		return "%s MWh sold yesterday" % CitySim.money_text(roundi(sim.trade.sold("power")))
	if dv.has("compost"):
		return "%s tons of compost sold" % CitySim.money_text(roundi(sim.trade.sold("compost")))
	if dv.has("scrap"):
		return "%s tons of scrap sold" % CitySim.money_text(roundi(sim.trade.sold("scrap")))
	if dv.has("garbage"):
		return "%s tons taken in from neighbors" % CitySim.money_text(roundi(sim.trade.sold("garbage")))
	if dv.has("value"):
		return "+%d%% land value nearby" % roundi(float(dv.value) * 100.0)
	if dv.has("grow"):
		return "room to grow into the woods"
	return "built"
