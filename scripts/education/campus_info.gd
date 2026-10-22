class_name CampusInfo
extends RefCounted
## The info panel for a high school, college or university: its head and
## how they run it, students, books, its development tree (what it has
## built, plans next, and what is still locked and why), and the one lever
## the player holds, its funding. The leader guide below it (grow, your
## call, hold off) comes from Permits.


## A high school, college or university: who runs it, its students and
## books, and buttons for the one thing the player sets, its funding.
static func describe(sim: CitySim, id: int) -> Dictionary:
	var c: Dictionary = sim.education.campuses[id]
	var k: Dictionary = Education.KINDS[c.kind]
	var l: Dictionary = c.leader
	var m := Education.books(c, c.enrolled)
	var net: float = (m[0] - m[1]) * 12.0
	var levels: Array = Balance.EDUCATION_FUNDING_LEVELS
	var level := clampi(int(c.funding), 0, levels.size() - 1)
	var rows := [
		[k.head, Education.leader_name(l)],
		["", "%s, %s" % [Education.degree_name(l.edu), Education.leader_style(l)]],
		["Students", "%s of %s seats" % [CitySim.money_text(c.enrolled), CitySim.money_text(Education.seats(c))]],
		["Applying", CitySim.money_text(c.applicants)],
		["Campus", "%d block%s (%.0f acres)" % [c.blocks.size() + 1, "" if c.blocks.is_empty() else "s",
			(c.blocks.size() + 1) * Education.CELL * Education.CELL / 4046.86]],
		["Graduates so far", CitySim.money_text(floori(c.grads))],
		["City funding", "$%s / month (%d%%)" % [CitySim.money_text(Education.monthly_funding(c)), roundi(levels[level] * 100.0)]],
		["Surplus", "%s$%s / year" % ["" if net >= 0.0 else "-", CitySim.money_text(absi(roundi(net)))]],
		["Savings", "%s$%s" % ["" if c.savings >= 0.0 else "-", CitySim.money_text(absi(roundi(c.savings)))]],
	]
	if c.kind != "high_school":
		rows.append(["Reputation", "%d%%" % roundi(c.reputation * 100.0)])
	# Its development tree: what it has, what's open next, what's still locked.
	var facts := Education.town_facts(sim)
	var built := []
	for use in c.built:
		built.append(Education.dev(c.kind, use).get("name", use))
	if not built.is_empty():
		rows.append(["Built", ", ".join(built)])
	var next := Education.pick_next(sim, c, facts, true)
	if next != "":
		rows.append(["Plans next", Education.dev(c.kind, next).name])
	var shown := 0
	for node in Education.TREE[c.kind]:
		var why := Education.locked_by(sim, c, node.id, facts)
		if why != "" and why != "built" and shown < 3:
			rows.append([node.name, why])
			shown += 1
	if c.why != "":
		rows.append(["Latest", c.why])
	var problems := []
	var status := "Growing: room for everyone who applies"
	if c.applicants == 0:
		status = "Waiting for students"
		problems.append("No homes near it yet. Students come from the homes closest to it.")
	elif c.enrolled < c.applicants:
		status = "Full: %s turned away" % CitySim.money_text(c.applicants - c.enrolled)
	if c.idle != "":
		problems.append(c.idle)
	var actions := []
	actions.append({"label": "Less funding", "cmd": {"type": "set_campus_funding", "id": id, "level": level - 1},
		"enabled": level > 0})
	actions.append({"label": "More funding", "cmd": {"type": "set_campus_funding", "id": id, "level": level + 1},
		"enabled": level < levels.size() - 1})
	return {"title": k.name, "kind": "Education", "icon": k.icon, "ok": problems.is_empty(), "status": status,
		"rows": rows, "problems": problems, "actions": actions}
