class_name MailInfo
extends RefCounted
## The info panel for the post office: the postmaster and why they do what
## they do, the routes and vehicles, what the mail does for the town, the
## development tree branch by branch, and the funding buttons (the player's
## lever, with the land).


## Same shape as Inspect.describe, plus `actions`: [{label, cmd, enabled}].
static func describe(sim: CitySim, id: int) -> Dictionary:
	var mail := sim.mail
	var h: Dictionary = mail.offices[id]
	var pm: Dictionary = h.leader
	var rows := []
	var problems := []
	var linked := not sim.network.find_segment_near(h.pos, 80.0, 1.0).is_empty()
	rows.append(["Postmaster", pm.name])
	rows.append(["", "%s, %s" % [_trait(float(pm.edu), ["little schooling", "some college", "a degree"]),
		_trait(float(pm.ambition) - float(pm.caution), ["careful with money", "steady", "ambitious"], -0.2, 0.2)]])
	rows.append(["Routes", "%d today" % int(h.get("routes", 0))])
	rows.append(["Carriers", "%d of %d out" % [mail.out(id, ["carrier", "rural"]), mail.carriers(id)]])
	rows.append(["Parcel vans", "%d of %d out, %d parcels waiting" % [mail.out(id, ["van"]), mail.vans(id),
		int(h.parcels_waiting)]])
	rows.append(["Mail a day", "%s pieces" % CitySim.money_text(int(h.pieces_today))])
	rows.append(["Homes getting mail", "%d%%" % roundi(mail.home_share * 100.0)])
	rows.append(["Businesses served", "%d%%" % roundi(mail.business_share * 100.0)])
	var nb := mail.neighbors()
	if int(nb.towns) > 0:
		rows.append(["Towns around", "%d, about %s people" % [int(nb.towns), CitySim.money_text(int(nb.population))]])
	rows.append(["Postmaster's fund", "$%s (+$%s / month)" % [CitySim.money_text(roundi(h.fund)),
		CitySim.money_text(roundi(mail.monthly_income(id)))]])
	rows.append(["City funding", "%s, $%s / month" % [Balance.MAIL_FUNDING[h.funding].name,
		CitySim.money_text(int(Balance.MAIL_FUNDING[h.funding].monthly))]])
	var acres: float = h.cells.size() * h.cell * h.cell / 4046.86
	rows.append(["Land", "%.1f acres (%d pieces)" % [acres, h.cells.size()]])
	rows.append(["ZIP code", str(h.zip)])
	# The tree, a line per branch: what's built, what's coming and why.
	for branch in Mail.BRANCHES:
		var built := []
		var next := ""
		# In tree order; "next" is the first one whose step before it is built.
		for node in Mail.TREE:
			if Mail.TREE[node].branch != branch:
				continue
			var needs: String = Mail.TREE[node].needs
			if Mail.done(h, node):
				built.append(Mail.TREE[node].name)
			elif not h.project.is_empty() and h.project.node == node:
				next = "building %s" % Mail.lower(Mail.TREE[node].name)
			elif next == "" and (needs == "" or Mail.done(h, needs)):
				var why := mail.locked(sim, id, node)
				next = "next: %s%s" % [Mail.lower(Mail.TREE[node].name), "" if why == "" else " (%s)" % Mail.lower(why.trim_suffix("."))]
		var text := ", ".join(built)
		if next != "":
			text = next if text == "" else text + "; " + next
		rows.append([branch, text if text != "" else "all built"])
	var status := "Delivering the mail" if linked else "Not working"
	if h.plan != "":
		status += ". " + h.plan.trim_suffix(".")
	if not linked:
		problems.append("Not beside a road, so its carriers can't get out.")
	elif mail.out(id, ["carrier", "rural"]) >= mail.carriers(id) and int(h.get("routes", 0)) > mail.carriers(id):
		problems.append("More routes than carriers: some streets wait a day. When it stays this busy it takes land next door for more trucks.")
	if h.get("boxed", false):
		problems.append("No free land next to it to grow into.")
	var actions := []
	actions.append({"label": "Demolish", "cmd": {"type": "remove_post_office", "id": id}, "enabled": true})
	return {"title": "Post Office", "kind": "Mail · ZIP %d" % int(h.zip), "icon": "post_office",
		"ok": problems.is_empty() and linked, "status": status, "rows": rows, "problems": problems,
		"actions": actions}


static func _trait(v: float, words: Array, lo := 0.4, hi := 0.65) -> String:
	return words[0] if v < lo else (words[2] if v >= hi else words[1])
