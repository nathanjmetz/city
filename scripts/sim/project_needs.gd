class_name ProjectNeeds
extends RefCounted
## What a building project needs from the town's other leaders, and what
## each one says (Brawn, 2026-10-23: "in order for it to be completed, your
## other hub leaders have to respond"). Every yes ripples: a town without
## its own quarry pays to truck gravel in, too many projects at once stretch
## the builders, and a full water or power system stops new hookups.
## Shortages cost the project (the builder pays more and goes slower), never
## the town's own money.
##
## Real references:
## - A new home takes about 400 tons of aggregate counting its share of the
##   street, foundation and driveway (NSSGA). Crushed stone sells for about
##   $16 a ton at the quarry (USGS 2023), and its delivered price about
##   doubles every 30 miles it's trucked, so towns build near quarries.
## - Concrete: about 45 cubic yards a home (footings, slab, driveway and
##   walks). Ready-mix has to be poured within 90 minutes of batching
##   (ASTM C94), so plants sit by the quarries they draw stone from, and a
##   job far from one pays a haul charge of about $1 a yard a mile. It
##   shares the gravel line on the card: same trucks, same quarry.
## - Builders: a small market has only so many crews; stretched thin, every
##   job slows and labor costs climb.
## - Utilities: a water or sewer system at capacity stops new hookups (a
##   building moratorium, common in fast-growing towns); planners start an
##   expansion well before (Texas's 75/90 rule: plan at 75%, build at 90%).
## - Winter: Indiana's asphalt plants and road paving shut down from about
##   December to March, so new streets and foundations wait for spring.
##
## A handful of sums, worked out once a month per project: no new
## per-frame work.

enum State { OK, SLOW, STOPPED }


## The needs of a project of `homes` homes: {"lines": [[state, icon, text]],
## "extra": $ more the builder pays, "slow": how much longer it takes (0 =
## on time, 1 = twice as long), "hold": true when nothing new can start,
## "hold_why": the reason}.
static func check(sim, homes: int) -> Dictionary:
	var out := {"lines": [], "extra": 0, "slow": 0.0, "hold": false, "hold_why": ""}
	_gravel(sim, homes, out)
	_crews(sim, homes, out)
	for u in ["water", "power"]:
		_utility(sim, u, homes, out)
	_season(sim, out)
	out.slow = snappedf(out.slow, 0.01)
	return out


## Gravel and concrete: from the town's own quarry, or trucked in.
static func _gravel(sim, homes: int, out: Dictionary) -> void:
	var tons := homes * Balance.NEEDS_TONS_PER_HOME
	var quarry := ""
	var ids: Array = sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		if str(sim.industry.sites[id].kind) == "ore":
			quarry = sim.families.name_of("site:%d" % id)
			if quarry == "":
				quarry = "the mining company"
			break
	if quarry != "":
		out.lines.append([State.OK, "ore", "Gravel and concrete from %s's quarry here in town" % quarry])
		return
	var local := Balance.NEEDS_STONE_PER_TON * (1.0 + Balance.NEEDS_LOCAL_MILES / Balance.NEEDS_DOUBLE_MILES)
	var far := Balance.NEEDS_STONE_PER_TON * (1.0 + Balance.NEEDS_IMPORT_MILES / Balance.NEEDS_DOUBLE_MILES)
	var extra := roundi(tons * (far - local))
	extra += roundi(homes * Balance.NEEDS_CONCRETE_YD_PER_HOME * Balance.NEEDS_CONCRETE_HAUL * (Balance.NEEDS_IMPORT_MILES - Balance.NEEDS_LOCAL_MILES))
	out.extra += extra
	out.slow += Balance.NEEDS_IMPORT_SLOW
	out.lines.append([State.SLOW, "ore", "No quarry in town: gravel and concrete come about %d miles, $%s more" % [
		int(Balance.NEEDS_IMPORT_MILES), CitySim.money_text(extra)]])


## Builders: homes going up now against the crews a town this size has.
static func _crews(sim, homes: int, out: Dictionary) -> void:
	var going := 0
	for ref in sim.construction.sites:
		if str(sim.construction.sites[ref].profile) == "house":
			going += 1
	var crews := maxi(Balance.NEEDS_MIN_CREWS, int(sim.stats.population) / Balance.NEEDS_PEOPLE_PER_CREW)
	var room := crews * Balance.NEEDS_HOMES_PER_CREW
	var load := float(going + homes / 2) / maxf(room, 1.0)
	if load <= 1.0:
		out.lines.append([State.OK, "jobs", "Builders have room: %d homes going up, %d crews in town" % [going, crews]])
		return
	var over := minf(load - 1.0, 1.0)
	var extra := roundi(homes * Balance.NEEDS_LABOR_PER_HOME * over)
	out.extra += extra
	out.slow += over
	out.lines.append([State.SLOW, "jobs", "Builders are stretched: %d homes going up and %d more for %d crews, $%s more and slower" % [
		going, homes, crews, CitySim.money_text(extra)]])


## Water and power: room for the new hookups, or a moratorium.
static func _utility(sim, u: String, homes: int, out: Dictionary) -> void:
	var use: Array = sim.services.utility_use.get(u, [0, 0])
	var cap := int(use[1])
	var name := u.capitalize()
	if cap <= 0:
		out.lines.append([State.SLOW, u, "No %s service yet: homes won't fill until the town brings it" % u])
		return
	var pct := roundi(100.0 * (int(use[0]) + homes * int(Balance.UTILITY_LOAD[ZoneMap.Zone.RESIDENTIAL])) / cap)
	var now := roundi(100.0 * int(use[0]) / cap)
	if now >= 100:
		out.hold = true
		out.hold_why = "%s system is full: no new hookups until it's expanded" % name
		out.lines.append([State.STOPPED, u, "%s is at %d%%: no new hookups until the town adds more" % [name, now]])
	elif pct >= Balance.NEEDS_WARN_PCT:
		out.lines.append([State.SLOW, u, "%s would reach %d%% of what the town has" % [name, pct]])
	else:
		out.lines.append([State.OK, u, "%s has room (%d%% after this)" % [name, pct]])


## Winter: no new streets or foundations until spring.
static func _season(sim, out: Dictionary) -> void:
	if Seasons.month(int(sim.tick_count)) in Balance.NEEDS_WINTER_MONTHS:
		out.hold = true
		if out.hold_why == "":
			out.hold_why = "Winter: paving and foundations wait for spring"
		out.lines.append([State.SLOW, "seasons", "Winter: new streets and foundations wait for spring"])


## Needs back from a save, with whole numbers whole again ({} stays {}).
static func from_dict(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var lines := []
	for l in d.get("lines", []):
		lines.append([int(l[0]), str(l[1]), str(l[2])])
	return {"lines": lines, "extra": int(d.get("extra", 0)), "slow": float(d.get("slow", 0.0)),
		"hold": bool(d.get("hold", false)), "hold_why": str(d.get("hold_why", ""))}
