class_name RailInfo
extends RefCounted
## The info panels for a rail depot (its leader, money, lines and tree, and
## the city's subsidy, the player's one lever) and for a train (what it is,
## what it carries, where it came from and where it's going).

## City subsidy steps, dollars a month.
const SUBSIDY_STEPS := [0, 10_000, 25_000, 50_000, 100_000]


## Same shape as Inspect.describe, plus `actions`: [{label, cmd, enabled}].
static func depot(sim: CitySim, id: int) -> Dictionary:
	var rail := sim.rail
	var d: Dictionary = rail.depots[id]
	var lead: Dictionary = d.leader
	var rows := []
	var problems := []
	rows.append(["Railroad", d.name])
	rows.append(["Run by", "%s, %s, %s" % [lead.name, MailInfo._trait(float(lead.edu), ["little schooling", "some college", "a degree"]),
		MailInfo._trait(float(lead.ambition) - float(lead.caution), ["careful with money", "steady", "bold"], -0.2, 0.2)]])
	rows.append(["Money", "$%s" % CitySim.money_text(roundi(float(d.money)))])
	var profit := rail.yearly_profit(id)
	rows.append(["Yesterday", "$%s in, $%s out" % [CitySim.money_text(roundi(float(d.last.income))),
		CitySim.money_text(roundi(float(d.last.costs)))]])
	rows.append(["Profit", "%s$%s every 12 days" % ["" if profit >= 0.0 else "-", CitySim.money_text(absi(roundi(profit)))]])
	rows.append(["City subsidy", "$%s / day" % CitySim.money_text(int(d.subsidy))])
	rows.append(["Jobs", str(Balance.RAIL_DEPOT_JOBS + int(rail.fx(id, "jobs+")))])
	for lid in rail._lines_of(id):
		var l: Dictionary = rail.lines[lid]
		var what := "Main line to the region" if l.kind == "main" else "Spur to the %s" % str(l.target.name).to_lower()
		var state: String = {"permit": "waiting on your permit", "building": "crews laying track (%d%%)" % roundi(
			100.0 * float(l.built) / maxf(float(l.length), 1.0)), "open": "open", "denied": "denied",
			"shelved": "shelved"}.get(l.state, l.state)
		var extra := ""
		if l.state == "open" and l.kind == "spur":
			extra = ", %d carloads shipped" % int(l.get("cars_total", l.cars))
		rows.append([what, "%.1f km, %s%s" % [float(l.length) / 1000.0, state, extra]])
	if d.pax:
		rows.append(["Passenger trains", "every %d hours, about %s riders a day" % [
			roundi(Balance.RAIL_PAX_EVERY_HOURS * rail.fx(id, "pax_every*")), CitySim.money_text(roundi(float(d.riders)))]])
	rows.append(["Loads delivered", str(int(d.get("delivered", 0)))])
	rows.append_array(Inspect._development(sim, d, Rail.TREE, d.pos, maxf(profit, 0.0)))
	if d.state != "open":
		problems.append("Out of business: the railroad ran out of money.")
	elif float(d.money) < 0.0:
		problems.append("Losing money. A city subsidy keeps it running while it finds paying freight.")
	var status: String = d.why
	var actions := []
	var step := SUBSIDY_STEPS.find(int(d.subsidy))
	if step == -1:
		step = 0
	if step < SUBSIDY_STEPS.size() - 1:
		actions.append({"label": "More subsidy: $%s / day" % CitySim.money_text(SUBSIDY_STEPS[step + 1]),
			"cmd": {"type": "rail_subsidy", "id": id, "monthly": SUBSIDY_STEPS[step + 1]}, "enabled": true})
	if step > 0:
		actions.append({"label": "Less subsidy: $%s / day" % CitySim.money_text(SUBSIDY_STEPS[step - 1]),
			"cmd": {"type": "rail_subsidy", "id": id, "monthly": SUBSIDY_STEPS[step - 1]}, "enabled": true})
	actions.append({"label": "Close the railroad", "cmd": {"type": "remove_rail_depot", "id": id}, "enabled": true})
	return {"title": d.name, "kind": "Railroad depot", "icon": "rail_depot", "ok": problems.is_empty() and d.state == "open",
		"status": status, "rows": rows, "problems": problems, "actions": actions}


static func train(sim: CitySim, tid: int) -> Dictionary:
	var rail := sim.rail
	var t: Dictionary = rail.trains[tid]
	var d: Dictionary = rail.depots.get(t.depot, {})
	var rows := []
	var engines := []
	var cars := {}
	for k in t.consist:
		if Rail.STOCK[k].has("cargo"):
			var cargo: String = Rail.STOCK[k].cargo
			cars[cargo] = int(cars.get(cargo, 0)) + 1
		else:
			engines.append(Rail.STOCK[k].name)
	rows.append(["Engine", ", ".join(engines)])
	if t.kind == "passenger":
		rows.append(["Coaches", str(t.consist.size() - engines.size())])
		rows.append(["Riders", str(int(t.riders))])
	else:
		var parts := []
		for cargo in cars:
			parts.append("%d %s" % [cars[cargo], cargo])
		rows.append(["Cars", ", ".join(parts) if not parts.is_empty() else "none yet"])
		if str(t.cargo) != "":
			rows.append(["Carrying", "%d loaded cars of %s" % [int(t.cars), t.cargo]])
	rows.append(["From", t.from])
	rows.append(["To", t.to])
	rows.append(["Speed", "%d mph" % roundi(float(t.v) * 2.23694)])
	rows.append(["Train length", "%d ft" % roundi(rail.train_length(t) * 3.28084)])
	if not d.is_empty():
		rows.append(["Railroad", d.name])
	var title := "%s No. %d" % ["Passenger train" if t.kind == "passenger" else "Local freight", int(t.number)]
	return {"title": title, "kind": "Train", "icon": "train", "ok": true, "status": t.purpose, "rows": rows,
		"problems": []}
