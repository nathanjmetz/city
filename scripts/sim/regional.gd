class_name Regional
extends RefCounted
## What the region's big shared projects (a new I-69 interchange, the power
## co-op's station, the regional airport) do in this town once their
## stages are funded. The region's ledger (Ledger) holds the pledges; this
## town works out its own benefit from its share and its distance to each
## site (Balance.REGION_*), and keeps the result so a save, and the region
## server's copy, carry it.
##
## benefit = reach x (BASE + (1 - BASE) x share next to the top pledger)
## reach   = 1 at the site, 0 at Balance.REGION_REACH (about an hour's drive)

## project id -> {"stages": funded stages, "benefit": 0..1, "share": 0..1, "member": bool}
var projects := {}


## Reads the ledger (called with the town's region view, like Interlocal).
func sync(region, me: String) -> void:
	projects = {}
	if not region.cities.has(me):
		return
	var at: Vector2 = region.cities[me].origin
	for id in region.ledger.projects:
		var p: Dictionary = region.ledger.projects[id]
		var share: float = region.ledger.share(id, me)
		var top := 0.0
		for v in p.shares.values():
			top = maxf(top, float(v))
		var weight: float = float(p.shares.get(me, 0.0)) / top if top > 0.0 else 0.0
		projects[id] = {"stages": Ledger.stages_done(p), "share": share, "member": float(p.shares.get(me, 0.0)) > 0.0,
			"benefit": snappedf(benefit(at, Vector2(p.site[0], p.site[1]), weight), 0.001)}


static func benefit(town: Vector2, site: Vector2, weight: float) -> float:
	var reach := clampf(1.0 - town.distance_to(site) / Balance.REGION_REACH, 0.0, 1.0)
	return reach * (Balance.REGION_BASE_SHARE + (1.0 - Balance.REGION_BASE_SHARE) * clampf(weight, 0.0, 1.0))


func _stages(id: String) -> int:
	return int(projects.get(id, {}).get("stages", 0))


func _benefit(id: String) -> float:
	return float(projects.get(id, {}).get("benefit", 0.0))


## The outside world's markup on a good this town brings in (Trade.settle).
func import_markup(_good: String) -> float:
	var m := Balance.TRADE_IMPORT_MARKUP
	if _stages("i69") >= 2:
		m = lerpf(m, Balance.REGION_I69_MARKUP, _benefit("i69"))
	return m


## Zone demand the projects add (CitySim's demand bars).
func demand_shift(zone: int) -> float:
	var d := 0.0
	if _stages("i69") >= 3:
		d += float(Balance.REGION_I69_DEMAND.get(zone, 0.0)) * _benefit("i69")
	if _stages("airport") >= 1:
		d += float(Balance.REGION_RUNWAY_DEMAND.get(zone, 0.0)) * _benefit("airport")
	if _stages("airport") >= 3:
		d += float(Balance.REGION_INTL_DEMAND.get(zone, 0.0)) * _benefit("airport")
	return d


## Land value lift, in amenity units (Neighborhood).
func land_lift() -> float:
	var l := 0.0
	if _stages("i69") >= 1:
		l += Balance.REGION_I69_LAND * _benefit("i69")
	if _stages("airport") >= 3:
		l += Balance.REGION_INTL_LAND * _benefit("airport")
	return l


## Money in each month: air visitors' spending taxed in town, and for co-op
## members the cheaper power on the town's line feeds and the capital
## credits, spread over the year.
func monthly_income(sim) -> int:
	var total := coop_saving(sim)
	if _stages("airport") >= 2:
		total += air_visitors_year() * Balance.TOURISM_SPEND * Balance.TOURISM_LOCAL_TAX / 12.0
	if _stages("power") >= 2:
		total += Balance.REGION_COOP_CREDITS_YEAR * float(projects.power.share) / 12.0
	return roundi(total)


## What a co-op member saves each month on its power line feeds.
func coop_saving(sim) -> float:
	if not projects.get("power", {}).get("member", false) or _stages("power") < 1:
		return 0.0
	var rate := Balance.REGION_COOP_GAS_FEED if _stages("power") >= 2 else Balance.REGION_COOP_FEED
	var upkeep := 0.0
	for id in sim.services.buildings:
		if sim.services.buildings[id].kind == Services.Kind.POWER_FEED:
			upkeep += float(Services.KINDS[Services.Kind.POWER_FEED].upkeep)
	return upkeep * (1.0 - rate)


func air_visitors_year() -> float:
	return Balance.REGION_AIR_VISITORS_YEAR * _benefit("airport") if _stages("airport") >= 2 else 0.0


## What a project's funded stages do here, one line each, for the panel.
func effects(id: String) -> Array:
	var out := []
	var b := _benefit(id)
	match id:
		"i69":
			if _stages(id) >= 1:
				out.append("Land value +%d%% near the road" % roundi(Balance.REGION_I69_LAND * b * Balance.AMENITY_LAND_SCALE * 100.0))
			if _stages(id) >= 2:
				out.append("Imports cost %.2fx instead of %.1fx" % [import_markup(""), Balance.TRADE_IMPORT_MARKUP])
			if _stages(id) >= 3:
				out.append("Industry demand +%d%%" % roundi(demand_shift(ZoneMap.Zone.INDUSTRIAL) * 100.0))
		"power":
			if not projects.get(id, {}).get("member", false):
				if _stages(id) >= 1:
					out.append("Pledge any amount to join the co-op")
				return out
			if _stages(id) >= 1:
				var rate := Balance.REGION_COOP_GAS_FEED if _stages(id) >= 2 else Balance.REGION_COOP_FEED
				out.append("Power on your line feeds %d%% cheaper" % roundi((1.0 - rate) * 100.0))
			if _stages(id) >= 2:
				out.append("Capital credits $%s a year" % CitySim.money_text(roundi(Balance.REGION_COOP_CREDITS_YEAR * float(projects[id].share))))
		"airport":
			if _stages(id) >= 1:
				out.append("Shop and office demand +%d%%" % roundi(demand_shift(ZoneMap.Zone.COMMERCIAL) * 100.0))
			if _stages(id) >= 2:
				out.append("%s air visitors a year" % CitySim.money_text(roundi(air_visitors_year())))
	return out


func to_dict() -> Dictionary:
	return {"projects": projects}


func from_dict(d: Dictionary) -> void:
	projects = {}
	var ps: Dictionary = d.get("projects", {})
	for id in ps:
		var p: Dictionary = ps[id]
		projects[str(id)] = {"stages": int(p.get("stages", 0)), "share": float(p.get("share", 0.0)),
			"member": bool(p.get("member", false)), "benefit": float(p.get("benefit", 0.0))}
