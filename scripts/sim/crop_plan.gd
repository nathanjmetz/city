class_name CropPlan
extends RefCounted
## Crop rotation (Brawn 2026-10-23): every winter each farm's leader picks
## next year's crop for each of its fields, the way Indiana farmers book
## seed in January. They weigh what the field pays this year, what it
## leaves the ground for next year (soybeans and hay leave nitrogen for
## corn; corn after corn yields less), what buyers nearby want (the co-op
## elevator, a grain mill, the fairgrounds' livestock barns) and how steep
## the ground is. Educated leaders look further ahead and sow cereal rye
## as a cover crop after harvest; careful ones split the farm between crops
## so one bad price can't sink them. The choice goes through Agency.choose,
## the shared leader-decision step, so Inspect can say why.
##
## Real references: Purdue Crop Cost and Return Guide (budgets per acre),
## Purdue/ISU rotation trials (corn after corn yields about 10% less, a
## soybean or alfalfa credit cuts corn's nitrogen bill), NRCS highly
## erodible land rules (row crops off steep ground, hay on it), and Indiana
## cover-crop practice (cereal rye drilled after corn or soybeans).
##
## Fertility never changes (Resources); the rotation only moves yield up
## or down a few percent around it, so nothing ever runs out.

## Crops a farm can rotate through. Grain crops ship by truck; hay stays
## local (bales for livestock).
const CROPS := ["corn", "soybeans", "wheat", "hay"]
const GRAIN := ["corn", "soybeans", "wheat"]
## A farm with a beef herd (Livestock "cattle") can also put fields in
## pasture: perennial grass the cows graze, which holds steep ground like
## hay and makes something of poor soil.
const WITH_PASTURE := ["corn", "soybeans", "wheat", "hay", "pasture"]


## The crops farm f can choose from.
static func crops_for(f: Dictionary) -> Array:
	return WITH_PASTURE if Livestock.kind(f) == "cattle" else CROPS


## The field (a 40-acre "forty") a cell belongs to, in the farm's own frame.
static func field_of(c: Vector2i) -> Vector2i:
	return Farms.forty_of(c)


## A field's record: {crop, prev, years, health, cover, cover_prev, why}.
## New fields take the farm's main crop with average soil health.
static func field(f: Dictionary, c: Vector2i) -> Dictionary:
	var k := field_of(c)
	if f.has("fields") and f.fields.has(k):
		return f.fields[k]
	return {"crop": f.crop, "prev": "", "years": 1, "health": 0.5, "cover": false, "cover_prev": false, "why": ""}


## What a cell is growing this year.
static func crop_at(f: Dictionary, c: Vector2i) -> String:
	return str(field(f, c).crop)


## Yield against a rotated field (1.0) given last year's crop.
static func rotation(crop: String, prev: String) -> float:
	return float(Balance.CROP_ROTATION_YIELD.get(crop, {}).get(prev, 1.0))


## Dollars an acre the crop saves on fertiliser after last year's crop
## (the soybean and alfalfa nitrogen credit to corn).
static func credit(crop: String, prev: String) -> float:
	return float(Balance.CROP_N_CREDIT.get(crop, {}).get(prev, 0.0))


## How a crop's price runs against corn's over the years: the soybean to
## corn price ratio swings between about 2.2 and 2.8 (USDA), so the
## crops trade places. Hay sells locally at a steady price.
static func relative_price(crop: String, day: float) -> float:
	match crop:
		"soybeans": return 1.0 + 0.1 * sin(TAU * day / (Balance.FARM_PRICE_CYCLE_DAYS * 0.7) + 1.3)
		"wheat": return 1.0 + 0.1 * sin(TAU * day / (Balance.FARM_PRICE_CYCLE_DAYS * 1.3) + 2.6)
	return 1.0


## Net an acre a year for a crop on ground of this fertility, after last
## year's crop and at this soil health, before land costs and tax.
## `boost` multiplies the gross (what the farm has built, see Agency).
static func net_per_acre(crop: String, prev: String, health: float, fertility: float, price: float,
		boost := 1.0) -> float:
	if crop == "pasture":
		fertility = Balance.PASTURE_SOIL_FLOOR + (1.0 - Balance.PASTURE_SOIL_FLOOR) * fertility
	var gross: float = Balance.FARM_GROSS_PER_ACRE[crop] * fertility * price * boost \
		* rotation(crop, prev) * (1.0 + (health - 0.5) * Balance.CROP_HEALTH_YIELD)
	var second := Balance.CROP_DOUBLE_CROP * fertility if crop == "wheat" else 0.0
	return gross + second - Balance.FARM_COST_PER_ACRE[crop] + credit(crop, prev)


## Soil health after a year of `crop` following `prev` (0..1): the same
## crop again wears it down, a change builds it, hay and cover crops most.
static func next_health(health: float, crop: String, prev: String, cover: bool) -> float:
	var d := -0.1 if crop == prev and crop != "pasture" else 0.05
	if crop in ["hay", "pasture"]:
		d += 0.05
	if cover:
		d += 0.05
	return clampf(health + d, 0.0, 1.0)


## What buyers around the town pay over the usual price, in dollars an
## acre for each crop, and why: {crop: [premium, reason]}. Worked out once
## a year before the farms plan.
static func demand(sim: CitySim) -> Dictionary:
	var out := {}
	var mill := false
	for key in sim.buildings:
		if sim.buildings[key].get("chain", "") == "mill":
			mill = true
			break
	var elevator := false
	var fair := false
	for pid in sim.parks.sites:
		match sim.parks.sites[pid].kind:
			"grain_elevator": elevator = true
			"fairgrounds": fair = true
	if mill:
		out["corn"] = [Balance.CROP_DEMAND.mill_corn, "the grain mill in town buys corn for feed"]
		out["wheat"] = [Balance.CROP_DEMAND.mill_wheat, "the mill grinds soft red winter wheat for flour"]
	if elevator:
		for crop in ["corn", "soybeans"]:
			var p: Array = out.get(crop, [0.0, ""])
			out[crop] = [p[0] + Balance.CROP_DEMAND.elevator,
				"the co-op elevator pays a better price" if p[1] == "" else p[1] + " and the co-op elevator pays well"]
	if Agency._region(sim, "imports", "grain") > 0 or Agency._region(sim, "imports", "soybeans") > 0:
		var p: Array = out.get("soybeans", [0.0, ""])
		out["soybeans"] = [p[0] + Balance.CROP_DEMAND.region,
			"a neighbouring town is buying soybeans" if p[1] == "" else p[1] + ", and a neighbouring town buys soybeans"]
	if fair:
		out["hay"] = [Balance.CROP_DEMAND.fair_hay, "the fairgrounds' livestock barns buy hay"]
	for id in sim.farms.farms:
		if not Livestock.sites(sim.farms.farms[id]).is_empty():
			var p: Array = out.get("corn", [0.0, ""])
			out["corn"] = [p[0] + Balance.CROP_DEMAND_FEED,
				"the livestock barns' feed mill buys corn" if p[1] == "" else p[1] + ", and the livestock barns need feed"]
			break
	return out


## Plan next year for every field of farm f. `fert(c)` gives the soil at a
## cell's centre and `slope(c)` its steepness (rise over run). Returns how
## many fields changed crop.
static func plan(f: Dictionary, demand: Dictionary, price: float, day: float, fert: Callable, slope: Callable) -> int:
	if not f.has("fields"):
		f.fields = {}
	# Every field the farm works, with its cells.
	var cells_of := {}
	for c in f.cells:
		var k := field_of(c)
		if not cells_of.has(k):
			cells_of[k] = []
		cells_of[k].append(c)
	for k in f.fields.keys():
		if not cells_of.has(k):
			f.fields.erase(k)
	var keys := cells_of.keys()
	keys.sort()
	var lead: Dictionary = f.get("leader", {"edu": 0.5, "caution": 0.5, "ambition": 0.5})
	var crops := crops_for(f)
	var planned := {}
	var total := 0
	var changed := 0
	for k in keys:
		var cells: Array = cells_of[k]
		var old: Dictionary = field(f, cells[0])
		var fertility := 0.0
		var steep := 0.0
		for c in cells:
			fertility += fert.call(c)
			steep += slope.call(c)
		fertility /= cells.size()
		steep /= cells.size()
		var prev := str(old.crop)
		var health := float(old.health)
		var options := []
		for crop in crops:
			options.append(_option(crop, prev, health, int(old.years), fertility, steep, price, day, demand,
				float(planned.get(crop, 0) + cells.size()) / maxf(f.cells.size(), 1.0), crops))
		var pick := Agency.choose(lead, options)
		var crop: String = pick.id
		# Cover crops: rye after a corn or soybean harvest, kept by leaders
		# who count what it does for the soil over its seed and drilling.
		var cover := crop in ["corn", "soybeans"] \
			and Agency.weight(lead, "future") * Balance.CROP_COVER_SOIL_VALUE > Balance.CROP_COVER_COST
		var why: String = pick.why
		if cover:
			why += " Rye goes in as a cover crop after harvest to hold the soil over winter."
		if crop != prev:
			changed += 1
		f.fields[k] = {"crop": crop, "prev": prev, "years": int(old.years) + 1 if crop == prev else 1,
			"health": snappedf(next_health(health, crop, prev, bool(old.cover)), 0.01), "cover": cover,
			"cover_prev": bool(old.cover), "why": why}
		planned[crop] = planned.get(crop, 0) + cells.size()
		total += cells.size()
	# The farm's main grain crop (what its trucks haul) is the one on most acres.
	var best := 0
	for crop in GRAIN:
		if planned.get(crop, 0) > best:
			best = planned[crop]
			f.crop = crop
	return changed


## One crop as a choice for a field, with the reasons a leader weighs.
static func _option(crop: String, prev: String, health: float, years: int, fertility: float, steep: float,
		price: float, day: float, demand: Dictionary, share: float, crops := CROPS) -> Dictionary:
	var p := price * relative_price(crop, day)
	var now := net_per_acre(crop, prev, health, fertility, p)
	var factors := {}
	var said := "pays about $%d an acre this year" % roundi(now)
	if rotation(crop, prev) > 1.0 or credit(crop, prev) > 0.0:
		said = "follows last year's %s well (%s)" % [prev, _after(prev)]
	elif rotation(crop, prev) < 1.0:
		said = "yields less after %s" % prev
	factors["money"] = [now, said]
	# Next year: the best crop to follow this one, at half weight (row
	# crops on steep ground lose what washes away, as below).
	var wash := maxf(steep - Balance.CROP_ERODIBLE_SLOPE, 0.0) * Balance.CROP_EROSION_PER_ACRE
	var h2 := next_health(health, crop, prev, false)
	var then := -INF
	var follow := ""
	for c2 in crops:
		var v := net_per_acre(c2, crop, h2, fertility, price) - (0.0 if c2 in ["hay", "pasture"] else wash)
		if v > then:
			then = v
			follow = c2
	factors["future"] = [then * 0.5, "leaves the ground ready for %s next year" % follow
		if follow != crop else "keeps the field in %s" % crop]
	if demand.has(crop):
		factors["demand"] = [float(demand[crop][0]), demand[crop][1]]
	# Seed, fertiliser and fuel at stake up front: corn costs the most.
	factors["risk"] = [-0.1 * Balance.FARM_COST_PER_ACRE[crop], "costs less to put in"]
	# Splitting the farm spreads work at planting and harvest, and price
	# risk: past half the farm in one crop, more of it counts against it.
	# (Pasture is the herd's ground, not a crop to balance.)
	if crop == "pasture":
		share = 0.0
	factors["spread"] = [-Balance.CROP_SPREAD_PER_ACRE * maxf(share - 0.5, 0.0) * 2.0, "balances the farm between crops"]
	# Steep ground washes under row crops (NRCS erodible land): hay holds it.
	if crop == "pasture":
		factors["land"] = [wash, "the herd grazes steep ground where row crops would wash"]
		if prev == "pasture":
			factors["money"][0] += Balance.CROP_HAY_ESTABLISH
			factors["money"][1] = "keeps pasture that is already fenced and seeded"
		else:
			factors["money"][1] = "feeds the beef herd for about $%d an acre" % roundi(now)
	elif crop == "hay":
		factors["land"] = [wash, "holds the steep ground where row crops would wash"]
		# An alfalfa stand lasts three or four years once it's paid for.
		if prev == "hay" and years < Balance.CROP_HAY_STAND_YEARS:
			factors["money"][0] += Balance.CROP_HAY_ESTABLISH
			factors["money"][1] = "keeps a hay stand that is already paid for"
	else:
		factors["land"] = [-wash, "keeps off steep ground"]
	return {"id": crop, "name": crop.capitalize(), "factors": factors}


static func _after(prev: String) -> String:
	match prev:
		"soybeans": return "soybeans leave nitrogen"
		"hay": return "alfalfa leaves a big nitrogen credit"
		"corn": return "a break from corn pests"
		"wheat": return "wheat breaks the disease cycle"
	return "a fresh rotation"
