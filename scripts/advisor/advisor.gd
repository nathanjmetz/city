class_name Advisor
extends RefCounted
## The town's advisor: reads the city and the tool in hand and picks the few
## things most worth mentioning, in a casual Midwestern voice. It points at
## problems and possibilities but leaves the next move to the player; its only
## job is to keep them from getting stuck. Pure logic, no UI, works offline.
##
## Benchmarks: the Cities: Skylines 2 advisor (context tips you open when you
## want them), Anno and Frostpunk hints (flag a problem, say where to look),
## Factorio tips (short notes about the tool in hand). Not CS1's Chirper:
## nothing chatters for the sake of it, and nothing pops up unless asked to.

enum Kind { PROBLEM, HEADS_UP, IDEA, TOOL }

## How many tips the panel shows at once.
const SHOWN := 3


## Every tip that applies right now, most urgent first:
## [{"id", "kind", "text"}]. `category` is the open tool category
## ("roads", "zones", "farms", "services", "traffic", "bulldoze", "budget"),
## an open info view ("view_fertility" and so on) or "".
static func tips(sim: CitySim, category := "") -> Array:
	var out := []
	_problems(sim, out)
	_ideas(sim, out)
	var tool := _tool_tips(sim, category)
	# Sort by kind, keeping the order within a kind (most urgent rules come first).
	for i in out.size():
		out[i].order = i
	out.sort_custom(func(a, b): return a.kind < b.kind or (a.kind == b.kind and a.order < b.order))
	# The tool in hand goes right after any problems, so it's there when you need it.
	var at := 0
	while at < out.size() and out[at].kind == Kind.PROBLEM:
		at += 1
	for t in tool:
		out.insert(at, t)
		at += 1
	return out


## The first steps for a brand-new town, for the welcome.
static func first_ideas(sim: CitySim) -> Array:
	var ideas := []
	# A region town starts with its county roads already in, so count only
	# what the player has done: no homes yet means streets come first.
	if sim.zones.cells.is_empty():
		ideas.append("Run a few streets off that road in from the highway. Roads is down at the bottom.")
	if sim.zones.cells.is_empty():
		ideas.append("Paint some homes along your streets, and folks will start showing up.")
	if sim.services.buildings.is_empty():
		ideas.append("Nobody builds without power and water, so a power line and a well (Services) go a long way.")
	if ideas.size() < 2:
		ideas.append("Out past town, good dirt grows the best corn. The Fertility view shows where.")
	return ideas


## A city is new until someone has done something with it.
static func is_new_city(sim: CitySim) -> bool:
	return sim.zones.cells.is_empty() and sim.services.buildings.is_empty() \
		and sim.farms.farms.is_empty()


# --- Problems and heads-ups --------------------------------------------------

static func _problems(sim: CitySim, out: Array) -> void:
	var e := sim.economy
	var s := sim.stats
	var net := e.monthly_net()
	if e.money < 0:
		_add(out, "broke", Kind.PROBLEM, "Ope, the town's in the red. Nothing new gets built till that's sorted out. The Economy page shows where it's all going.")
	elif net < 0:
		var months := e.money / float(-net)
		if months < 6.0:
			_add(out, "running_low", Kind.PROBLEM, "Money's going out faster than it comes in. At this rate it's gone in about %d months (a day is a month). The Economy page is the place to peek." % maxi(1, int(months)))
		elif months < 24.0 and s.population > 0:
			_add(out, "spending", Kind.HEADS_UP, "We're spending a bit more than we take in, about $%s a month. Nothing to fret over yet, but worth a look at the Economy page sometime." % CitySim.money_text(-net))

	var zoned := not sim.zones.cells.is_empty()
	var use: Dictionary = sim.services.utility_use
	var missing := []
	for u in ["power", "water"]:
		var has := false
		for id in sim.services.buildings:
			if sim.services.buildings[id].kind in Services.UTILITIES[u]:
				has = true
		if not has:
			missing.append(u)
	if zoned and not missing.is_empty():
		var short := 0  # what the cheapest missing hookups cost beyond what's in the bank
		for u in missing:
			short += int(Services.KINDS[Services.Kind.POWER_FEED if u == "power" else Services.Kind.WELL].cost)
		short -= e.money
		var text := "Folks won't build where there's no %s. You'll find that under Services." % " or ".join(missing)
		if short > 0:
			text = "Folks won't build where there's no %s, and we're about $%s short for it. The Economy page is worth a look." % [" or ".join(missing), CitySim.money_text(short)]
		_add(out, "no_utilities", Kind.PROBLEM, text)
	elif missing.is_empty():
		var unserved := sim.unserved_count()
		var full := []
		for u in ["power", "water"]:
			if use[u][1] > 0 and use[u][0] >= use[u][1] * 0.98:
				full.append(u)
		if unserved > 0 and not full.is_empty():
			_add(out, "utility_full", Kind.PROBLEM, "The %s's tapped out, so %d building%s went without. A bigger supply would cover 'em." % [" and ".join(full), unserved, "" if unserved == 1 else "s"])
		elif unserved > 0:
			_add(out, "unconnected", Kind.PROBLEM, "%d building%s can't get power or water. Could be a street that doesn't connect back to where those come from." % [unserved, " is" if unserved == 1 else "s are"])
		else:
			for u in ["power", "water"]:
				if use[u][1] > 0 and use[u][0] >= use[u][1] * 0.85:
					_add(out, u + "_near_full", Kind.HEADS_UP, "%s's at %d%% of what we've got. Might want more before the next bunch moves in." % [u.capitalize(), roundi(100.0 * use[u][0] / use[u][1])])

	if sim.traffic.cars.size() >= 30 and sim.traffic.flow < 0.55:
		_add(out, "traffic", Kind.PROBLEM, "Traffic's gettin' backed up, flow's down to %d%%. The flow view (J) shows where folks are sittin'." % roundi(sim.traffic.flow * 100.0))
	elif sim.traffic.cars.size() >= 20 and sim.traffic.flow < 0.7:
		_add(out, "traffic_slow", Kind.HEADS_UP, "Roads are a little slow, about %d%% flow. Nothing awful, but the flow view (J) is handy." % roundi(sim.traffic.flow * 100.0))

	if s.workers >= 20:
		var unemployed: float = 100.0 * (s.workers - s.employed) / s.workers
		if unemployed > 15.0:
			_add(out, "jobs", Kind.PROBLEM if unemployed > 30.0 else Kind.HEADS_UP, "Lotta folks lookin' for work, about %d%%. Shops and industry are where the jobs come from." % roundi(unemployed))

	var free := _free_lots(sim)
	if s.population > 0 or zoned:
		if sim.demand[ZoneMap.Zone.RESIDENTIAL] > 0.5 and free[ZoneMap.Zone.RESIDENTIAL] == 0 and missing.is_empty():
			_add(out, "want_homes", Kind.HEADS_UP, "People are itching to move in, but there's no empty home lot for 'em.")
		if sim.demand[ZoneMap.Zone.COMMERCIAL] > 0.5 and free[ZoneMap.Zone.COMMERCIAL] == 0 and s.population >= 30:
			_add(out, "want_shops", Kind.HEADS_UP, "Folks have to drive a ways to shop. A store or two would sell just fine.")
		if sim.demand[ZoneMap.Zone.INDUSTRIAL] > 0.5 and free[ZoneMap.Zone.INDUSTRIAL] == 0 and s.population >= 30:
			_add(out, "want_industry", Kind.HEADS_UP, "Businesses are asking around for spots to set up shop. Industry's in demand.")

	if s.population > 300 and sim.service_coverage() < 0.5:
		_add(out, "coverage", Kind.HEADS_UP, "Folks are starting to ask about fire, police, a clinic and a school. Homes without 'em fill slower now.")

	# Pollution: the one source bothering the most homes, by name, and where to look.
	var worst_ref := ""
	var worst_homes := 0
	var refs := sim.pollution.hurts.keys()
	refs.sort()
	for ref in refs:
		var homes: int = sim.pollution.hurts[ref].homes
		if homes > worst_homes and sim.pollution.sources.has(ref):
			worst_ref = ref
			worst_homes = homes
	if worst_homes >= 3:
		var src: Dictionary = sim.pollution.sources[worst_ref]
		var what := _pollution_kind(sim, worst_ref)
		_add(out, "pollution", Kind.PROBLEM if worst_homes >= 25 else Kind.HEADS_UP,
			"%s %s is botherin' %d homes. Open the %s view and click it to see how it could clean up." % [
			src.name + ("'" if str(src.name).ends_with("s") else "'s"), {"noise": "noise", "smoke": "smoke", "ground": "runoff"}[what],
			maxi(1, int(sim.pollution.hurts[worst_ref].kinds.get(what, 0))),
			{"noise": "Noise", "smoke": "Smoke", "ground": "Dirty ground"}[what]])

	# Resource industry: trucks that can't get out, and yards filled up.
	var stuck := 0
	for ref in sim.logistics.stuck:
		if str(ref).begins_with("site:") or str(ref).begins_with("farm:"):
			stuck += 1
	if stuck > 0:
		_add(out, "trucks_stuck", Kind.PROBLEM, "%s can't get %s trucks out to a buyer. Might be a lane that doesn't join up with the rest of town." % ["A company" if stuck == 1 else "%d places" % stuck, "its" if stuck == 1 else "their"])
	for id in sim.industry.sites:
		var site: Dictionary = sim.industry.sites[id]
		if site.stock >= Industry.STOCK_CAP and not sim.logistics.stuck.has("site:%d" % id):
			_add(out, "yard_full", Kind.HEADS_UP, "The %s's yard is full up, so it's quit producing till trucks haul some off. Clicking it tells you more." % Industry.KINDS[site.kind].name.to_lower())
			break
	for id in sim.farms.farms:
		if sim.farms.farms[id].cells.size() > 0 and sim.farms.yearly_profit(id) < 0.0:
			_add(out, "farm_losing", Kind.HEADS_UP, "One of the farms is losing money this year. Prices swing with the seasons, and richer soil helps.")
			break


# --- Ideas: only the ones that fit where the town is -----------------------

static func _ideas(sim: CitySim, out: Array) -> void:
	var s := sim.stats
	var e := sim.economy
	# The town has taken on a new reputation (TownCulture): say so for a year.
	var c := sim.culture
	var day := sim.tick_count / (24 * CitySim.TICKS_PER_HOUR)
	if c.identity != "" and day - c.since < Balance.CULTURE_NEWS_DAYS:
		_add(out, "identity_" + c.identity, Kind.HEADS_UP, "Folks around the county have started calling us a %s. Leaders in that line of work find it a little easier to grow here now. The Economy page shows what's rising." % c.title().to_lower())
	if sim.network.segments.size() <= 2:
		_add(out, "first_streets", Kind.IDEA, "That road in from the highway is all yours. Towns tend to start with a few streets off it.")
	elif sim.zones.cells.is_empty():
		_add(out, "first_zones", Kind.IDEA, "Got some streets down. Painting zones along 'em is how homes and shops show up.")
	if s.population >= 40 and _free_lots(sim)[ZoneMap.Zone.COMMERCIAL] == 0 and sim.count_buildings(ZoneMap.Zone.COMMERCIAL) == 0:
		_add(out, "first_shops", Kind.IDEA, "Town's big enough now that a little main street could do alright.")
	if s.population >= 60 and sim.farms.farms.is_empty():
		_add(out, "farms", Kind.IDEA, "Out past town, good dirt is steady money. Views up top shows where the soil is richest.")
	if e.milestone < Economy.MILESTONES.size() and s.population > 0:
		var goal: Array = Economy.MILESTONES[e.milestone]
		var left: int = int(goal[0]) - s.population
		if left <= maxi(40, int(goal[0]) / 4):
			_add(out, "grant", Kind.IDEA, "Another %d folks and the state sends a $%s grant." % [left, CitySim.money_text(int(goal[1]))])
	if s.population >= 120 and sim.industry.sites.is_empty():
		_add(out, "industry", Kind.IDEA, "There's oil, ore and timber out there that never runs dry. The Views up top show where it's richest.")
	if s.population >= 150 and sim.services.buildings.size() <= 2:
		_add(out, "safety", Kind.IDEA, "Once the town's a few hundred strong, people start wanting a fire station and the like nearby.")
	if sim.traffic.cars.size() >= 15 and sim.traffic.flow >= 0.7:
		_add(out, "junctions", Kind.IDEA, "If a corner ever gets busy, the Traffic tab swaps stop signs for lights.")
	for z in [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL]:
		if e.tax[z] > Economy.DEFAULT_TAX[z] * 1.3 and sim.demand[z] < 0.2:
			_add(out, "tax_%d" % z, Kind.IDEA, "%s taxes are up there, and that cools demand. Just something to know." % ["", "Home", "Shop", "Industry"][z])


# --- Notes about the tool in hand (Factorio-style) ---------------------------

const TOOL_NOTES := {
	"roads": [
		"Hold Shift while drawing to snap your angles.",
		"The Grid tool (3) lays out a whole neighborhood in a few clicks.",
		"Page Up and Page Down raise a road into a bridge or drop it into a tunnel.",
		"Parallel (P) draws a second road alongside, handy for highways.",
	],
	"zones": [
		"Zones only fill in along roads, and only when there's demand.",
		"Brackets [ and ] make the brush bigger or smaller.",
		"The bars up top show what folks want: homes, shops or industry.",
	],
	"industry": [
		"Open the Oil, Ore or Forest view first: a company does best set down where its view is richest.",
		"The company lays out its own wells, pits or stands as they pay. Reserve keeps roads off that land.",
		"Every load leaves on a real truck, so a company needs a road out to town or the highway.",
	],
	"services": [
		"Power and water travel along connected roads, so build 'em where the streets reach.",
		"Green roads while placing show how far a station covers.",
	],
	"farms": [
		"Views, top left, has Fertility: the greener the soil, the better the corn.",
		"Place a farmhouse near good dirt within 250 m of a road, and the farmer picks the fields.",
		"Reserve keeps roads and zoning off land you're saving for farming.",
		"Farms buy more fields when they're doing well and sell off losers in bad years.",
	],
	"traffic": [
		"Auto picks signs and lights by US rules, so you only need to step in where it's busy.",
		"All-way stops are fine on quiet corners; lights earn their keep on busy ones.",
	],
	"budget": [
		"Taxes look after themselves. Lean saves a little but things run thinner; Generous costs more and they run better.",
		"Set the whole town once, then just nudge the odd area or hub that needs it.",
	],
	"view_fertility": [
		"Corn likes the greenest dirt; soybeans hold up better on poorer ground.",
	],
	"view_oil": [
		"Oil never runs out, so a good field stays good.",
	],
	"view_ore": [
		"Ore never runs out either. Wherever it shows, it stays.",
	],
	"view_forest": [
		"Woods grow back after they're cut.",
	],
	"view_smoke": [
		"Smoke drifts with the wind, from the southwest here, so homes upwind of a plant stay clear.",
		"Click any spot to see who's making the smoke there and what each one could do about it.",
	],
	"view_noise": [
		"Noise falls off fast from a single spot, slower along a busy highway. Noise walls take a good bite out of it.",
		"Click any home or spot to see what's making the racket there.",
	],
	"view_ground": [
		"Dirty ground runs downhill, so wells and homes below a landfill or plant get the worst of it.",
	],
	"view_traffic": [
		"Red is stuck, green is moving. Busy corners are where lights or a roundabout earn their keep.",
	],
	"bulldoze": [
		"Click a road or a service building to clear it. Esc puts the dozer away.",
	],
}


static func _tool_tips(sim: CitySim, category: String) -> Array:
	var notes: Array = TOOL_NOTES.get(category, [])
	if notes.is_empty():
		return []
	# One note at a time, changing every game hour or so.
	var i := int(sim.tick_count / CitySim.TICKS_PER_HOUR) % notes.size()
	return [{"id": "tool_%s_%d" % [category, i], "kind": Kind.TOOL, "text": notes[i]}]


# --- Helpers --------------------------------------------------------------------

## What a source mostly bothers homes with: "noise", "smoke" or "ground".
static func _pollution_kind(sim: CitySim, ref: String) -> String:
	var kinds: Dictionary = sim.pollution.hurts.get(ref, {}).get("kinds", {})
	var best := "smoke"
	for kind in ["smoke", "noise", "ground"]:
		if int(kinds.get(kind, 0)) > int(kinds.get(best, 0)):
			best = kind
	return best


static func _add(out: Array, id: String, kind: int, text: String) -> void:
	out.append({"id": id, "kind": kind, "text": text})


## Empty lots for each zone, counting only lots that could grow now.
static func _free_lots(sim: CitySim) -> Dictionary:
	var free := {ZoneMap.Zone.RESIDENTIAL: 0, ZoneMap.Zone.COMMERCIAL: 0, ZoneMap.Zone.INDUSTRIAL: 0}
	for key in sim.empty_zoned_lots():
		var z := sim.zones.zone_at(sim.lots[key].zone_pt)
		if free.has(z):
			free[z] += 1
	return free
