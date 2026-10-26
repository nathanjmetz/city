class_name Livestock
extends RefCounted
## Livestock on farms (Brawn, 2026-10-23), chosen by the farm's leader: the
## first of the development forks Brawn picked ("forks with retooling"). A
## farm that only grows grain can take one livestock path, and a path that
## keeps losing money is given up again:
##   cattle   a cow-calf herd on pasture. The crop plan then puts the steep
##            and poor forties, where row crops wash or pay little, into
##            pasture (beef cows on Pike County's hill ground and reclaimed
##            strip-mine land).
##   hogs     contract finishing barns, 2,400 pigs a site (Dubois County).
##   dairy    a 500-cow freestall barn and parlor (northern Indiana).
##   turkeys  contract turkey barns, 16,000 toms a site (Farbest Foods).
## The leader weighs each path with Agency.choose: what it earns (with the
## manure that saves fertiliser on the farm's own ground), what the barns
## cost to carry (caution), the feed mill in town, and their own schooling.
##
## A barn group takes two of the farm's own field cells beside the farmyard,
## as far from homes as it can. One big enough to need Indiana's confined
## feeding approval (IDEM: 600 hogs, 300 cattle, 30,000 birds) goes to the
## permit bell first, with the leader's setback from homes drawn on the
## map. The player says yes (jobs, feed demand, cheaper fertiliser) or no
## (the farm stays with grain and won't ask again for a few years).
##
## Yearly, on the farms' own cadence; deterministic. Numbers in Balance
## LIVESTOCK. The animals in barns stay inside, as real ones do; only the
## herd on pasture shows (FarmView).

## Paths a farm can take, in the order they're weighed.
const PATHS := ["none", "cattle", "hogs", "dairy", "turkeys"]
## The barn paths (Balance.LIVESTOCK).
const BARNS := ["hogs", "dairy", "turkeys"]
## Each path's price cycle against the crop cycle: [length share, phase].
const CYCLE := {"hogs": [0.9, 0.7], "dairy": [1.1, 2.1], "turkeys": [0.8, 4.0]}
## A farm needs this many field cells (about 8 acres) before it takes on
## livestock: barns go on its own ground and the manure on its fields.
const MIN_CELLS := 20


## The farm's livestock record, made if it has none:
## {kind, sites: [[x, y]], pending: {req, site}, loss, wait, year, why}.
static func stock(f: Dictionary) -> Dictionary:
	if not f.has("stock"):
		f.stock = {"kind": "", "sites": [], "pending": {}, "loss": 0, "wait": 0, "year": 0, "why": ""}
	return f.stock


## The path the farm is on ("" for grain only).
static func kind(f: Dictionary) -> String:
	return str(f.get("stock", {}).get("kind", ""))


## Each barn site's anchor cell; a site covers it and the cell to its right.
static func sites(f: Dictionary) -> Array:
	var out := []
	for s in f.get("stock", {}).get("sites", []):
		out.append(Vector2i(int(s[0]), int(s[1])))
	return out


## Every field cell under barns.
static func site_cells(f: Dictionary) -> Array:
	var out := []
	for s in sites(f):
		out.append(s)
		out.append(s + Vector2i(1, 0))
	return out


## The middle of a site, on the ground plane.
static func site_center(f: Dictionary, s: Vector2i) -> Vector3:
	return (Farms.cell_center(f, s) + Farms.cell_center(f, s + Vector2i(1, 0))) * 0.5


## Acres the farm keeps in pasture this year.
static func pasture_acres(f: Dictionary) -> float:
	var n := 0
	for c in f.cells:
		if CropPlan.crop_at(f, c) == "pasture":
			n += 1
	return n * Farms.ACRES_PER_CELL


## How many animals the farm keeps.
static func head(f: Dictionary) -> int:
	var k := kind(f)
	if Balance.LIVESTOCK.has(k):
		return sites(f).size() * int(Balance.LIVESTOCK[k].per_site)
	if k == "cattle":
		return int(pasture_acres(f) / Balance.PASTURE_ACRES_PER_COW)
	return 0


## What the animals are called, plural ("hogs", "cows"...).
static func head_name(k: String) -> String:
	if Balance.LIVESTOCK.has(k):
		return str(Balance.LIVESTOCK[k].head_name)
	return "beef cows" if k == "cattle" else ""


## Prices for a path against normal on a game day (-1..1).
static func swing(k: String, day: float) -> float:
	var c: Array = CYCLE.get(k, [1.0, 0.0])
	return sin(TAU * day / (Balance.FARM_PRICE_CYCLE_DAYS * float(c[0])) + float(c[1]))


## Dollars a year the manure from `n` head saves on `acres` of the farm's
## own ground (it spreads on as many acres as it fertilises, no more).
static func manure(k: String, n: int, acres: float) -> float:
	if not Balance.LIVESTOCK.has(k):
		return 0.0
	return minf(n * float(Balance.LIVESTOCK[k].manure), acres) * Balance.MANURE_CREDIT_PER_ACRE


## The barns' yearly net on this game day, manure included (0 without
## barns). A cattle herd earns through its pasture (CropPlan), not here.
static func yearly(f: Dictionary, day: float) -> float:
	var k := kind(f)
	if not Balance.LIVESTOCK.has(k):
		return 0.0
	var spec: Dictionary = Balance.LIVESTOCK[k]
	var n := head(f)
	if n == 0:
		return 0.0
	return n * (float(spec.net) + float(spec.swing) * swing(k, day)) + manure(k, n, f.cells.size() * Farms.ACRES_PER_CELL)


## Hired hands the barns take.
static func jobs(f: Dictionary) -> int:
	var k := kind(f)
	if not Balance.LIVESTOCK.has(k):
		return 0
	return sites(f).size() * int(Balance.LIVESTOCK[k].jobs)


## Dollars a year pasture would beat the best crop on the farm's forties:
## steep ground (where row crops wash) and poor ground (where they lose).
## `fert(c)` and `slope(c)` read the land at a cell; `day` sets prices.
static func pasture_gain(f: Dictionary, fert: Callable, slope: Callable, price: float, day: float) -> float:
	var cells_of := {}
	for c in f.cells:
		var k := CropPlan.field_of(c)
		if not cells_of.has(k):
			cells_of[k] = []
		cells_of[k].append(c)
	var gain := 0.0
	for k in cells_of:
		var cells: Array = cells_of[k]
		var fr := 0.0
		var st := 0.0
		for c in cells:
			fr += fert.call(c)
			st += slope.call(c)
		fr /= cells.size()
		st /= cells.size()
		var wash := maxf(st - Balance.CROP_ERODIBLE_SLOPE, 0.0) * Balance.CROP_EROSION_PER_ACRE
		var best := -INF
		for crop in CropPlan.CROPS:
			var v := CropPlan.net_per_acre(crop, "", 0.5, fr, price * CropPlan.relative_price(crop, day))
			best = maxf(best, v - (0.0 if crop == "hay" else wash))
		var g := CropPlan.net_per_acre("pasture", "", 0.5, fr, price) - best
		if g > 0.0:
			gain += g * cells.size() * Farms.ACRES_PER_CELL
	return gain


## The paths open to a farm right now, as Agency.choose options. `ctx`:
## {day, price, link (a road out to the region), mill (a grain mill in
## town), fert, slope}.
static func options(f: Dictionary, ctx: Dictionary) -> Array:
	var lead: Dictionary = f.get("leader", {})
	var acres: float = f.cells.size() * Farms.ACRES_PER_CELL
	var out := [{"id": "none", "name": "Grain only", "factors": {
		"money": [0.0, "keeps the farm in grain"], "risk": [0.0, "carries no barn loan"]}}]
	var gain := pasture_gain(f, ctx.fert, ctx.slope, float(ctx.price), float(ctx.day))
	if gain > 0.0:
		out.append({"id": "cattle", "name": "A beef herd", "factors": {
			"money": [gain, "grazes the steep and poor ground where crops pay little"],
			"land": [gain * 0.25, "keeps that ground in grass"]}})
	if not ctx.link:
		return out  # nowhere to send hogs, birds or milk
	for k in BARNS:
		var spec: Dictionary = Balance.LIVESTOCK[k]
		if float(lead.get("edu", 0.0)) < float(spec.edu):
			continue
		var n := int(spec.per_site)
		var net := n * (float(spec.net) + float(spec.swing) * swing(k, float(ctx.day)))
		var dung := manure(k, n, acres)
		var factors := {
			"money": [net, "earns about $%s every 12 days from %s %s" % [CitySim.money_text(roundi(net)), _count(n), spec.head_name]],
			"future": [dung, "its manure saves fertiliser on the farm's own fields"],
			"risk": [-float(spec.cost) * Balance.LIVESTOCK_RISK_SHARE, "costs less to build"],
			"growth": [net * 0.25, "grows the farm"],
		}
		if ctx.mill and k != "dairy":
			factors["demand"] = [Balance.CROP_DEMAND_FEED * acres, "the grain mill in town makes the feed"]
		out.append({"id": k, "name": spec.name, "factors": factors})
	return out


static func _count(n: int) -> String:
	return CitySim.money_text(n)


## Once each farm decision step: every farm with a leader takes its yearly
## livestock step, and farms waiting on a barn permit check the bell. True
## when the map changed (barns built or taken down).
static func step(sim: CitySim) -> bool:
	var changed := false
	var ids := sim.farms.farms.keys()
	ids.sort()
	var homes := []
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		if not f.barn or not f.has("leader"):
			continue
		var st := stock(f)
		if not st.pending.is_empty():
			changed = _check_permit(sim, id, f) or changed
			continue
		if int(st.year) >= sim.farms.year:
			continue
		st.year = sim.farms.year
		if homes.is_empty():
			homes = _homes(sim)
		changed = _year(sim, id, f, homes) or changed
	return changed


## Where people live, for setbacks: positions of every home.
static func _homes(sim: CitySim) -> Array:
	var out := [Vector3.INF]  # never empty, so it's worked out once a step
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			out.append(sim.lots[key].pos)
	return out


static func _leader(sim: CitySim, id: int) -> String:
	var name := sim.families.name_of("farm:%d" % id)
	return name if name != "" else "The farm"


## One farm's yearly livestock step.
static func _year(sim: CitySim, id: int, f: Dictionary, homes: Array) -> bool:
	var st := stock(f)
	var k := str(st.kind)
	var who := _leader(sim, id)
	if Balance.LIVESTOCK.has(k):
		var spec: Dictionary = Balance.LIVESTOCK[k]
		if not st.sites.is_empty():
			st.loss = int(st.loss) + 1 if yearly(f, sim.farms.day) < 0.0 else 0
			if int(st.loss) >= Balance.LIVESTOCK_LOSS_YEARS:
				return retool(sim, id, f, "%s gave up the %s after %d losing years. The barns came down and the ground went back to crops." \
					% [who, str(spec.name).to_lower(), int(st.loss)])
		# Another barn group, when the barns pay and the farm makes money.
		if st.sites.size() < int(spec.max_sites) and sim.farms.yearly_profit(id) >= 0.0:
			var lead: Dictionary = f.leader
			var n := int(spec.per_site)
			var gain := n * float(spec.net) + manure(k, (st.sites.size() + 1) * n, f.cells.size() * Farms.ACRES_PER_CELL) \
				- manure(k, st.sites.size() * n, f.cells.size() * Farms.ACRES_PER_CELL)
			var v := gain * Agency.weight(lead, "growth") - float(spec.cost) * Balance.LIVESTOCK_RISK_SHARE * Agency.weight(lead, "risk")
			if v > 0.0 or st.sites.is_empty():
				return _add_site(sim, id, f, k, homes)
		return false
	if k == "cattle":
		# A herd is kept while there's ground it beats crops on.
		if pasture_gain(f, _fert(sim, f), _slope(sim, f), sim.farms.price, sim.farms.day) <= 0.0:
			st.kind = ""
			st.why = "%s sold the herd: no ground left where pasture beats crops." % who
			return true
		return false
	if sim.farms.year < int(st.wait) or f.cells.size() < MIN_CELLS:
		return false
	var mill := false
	for key in sim.buildings:
		if sim.buildings[key].get("chain", "") == "mill":
			mill = true
			break
	var pick := Agency.choose(f.leader, options(f, {"day": sim.farms.day, "price": sim.farms.price,
		"link": not sim.region_links.is_empty(), "mill": mill, "fert": _fert(sim, f), "slope": _slope(sim, f)}))
	if pick.id == "none":
		st.why = pick.why
		return false
	st.kind = pick.id
	st.why = "%s chose %s: %s" % [who, str(pick.name).to_lower(), pick.why]
	if pick.id == "cattle":
		return true
	return _add_site(sim, id, f, pick.id, homes)


static func _fert(sim: CitySim, f: Dictionary) -> Callable:
	return func(c): return sim.farms.fertility_at(Farms.cell_center(f, c))


static func _slope(sim: CitySim, f: Dictionary) -> Callable:
	return func(c): return sim.farms.slope_of.call(Farms.cell_center(f, c)) if sim.farms.slope_of.is_valid() else 0.0


## Where a new barn group would go: two of the farm's own cells side by
## side, near the farmyard and as far from homes as it can (Vector2i.MAX
## when none). `near` comes back as how many homes sit inside the setback.
static func best_site(f: Dictionary, k: String, homes: Array, near: Array) -> Vector2i:
	var reach := float(Balance.LIVESTOCK[k].reach)
	var taken := {}
	for c in site_cells(f):
		taken[c] = true
	var owned := {}
	for c in f.cells:
		owned[c] = true
	var best := Vector2i.MAX
	var best_score := INF
	var best_near := 0
	var cells: Array = f.cells.duplicate()
	cells.sort_custom(Farms._less)
	for c in cells:
		var r: Vector2i = c + Vector2i(1, 0)
		if not owned.has(r) or taken.has(c) or taken.has(r) or Farms.forty_of(c) != Farms.forty_of(r):
			continue
		# Clear of the farmstead, its shade trees and windbreak.
		if c.y <= 1 and c.x >= -2 and c.x <= 1:
			continue
		var mid := site_center(f, c)
		var n := 0
		for p in homes:
			if p != Vector3.INF and Vector2(p.x, p.z).distance_to(Vector2(mid.x, mid.z)) < reach:
				n += 1
		# Close to the yard (feed trucks, chores), and homes count far more.
		var score := Vector2(c).length() + n * 1000.0
		if score < best_score:
			best_score = score
			best = c
			best_near = n
	near.clear()
	near.append(best_near)
	return best


## A barn group: built at once when small, or asked for on the bell when it
## takes the farm past the confined feeding threshold.
static func _add_site(sim: CitySim, id: int, f: Dictionary, k: String, homes: Array) -> bool:
	var st := stock(f)
	var spec: Dictionary = Balance.LIVESTOCK[k]
	var who := _leader(sim, id)
	var near := []
	var s := best_site(f, k, homes, near)
	if s == Vector2i.MAX:
		st.why = "%s wants %s but has no room beside the farmyard." % [who, str(spec.name).to_lower()]
		if st.sites.is_empty():
			st.kind = ""
			st.wait = sim.farms.year + Balance.LIVESTOCK_WAIT_YEARS
		return false
	var total: int = (st.sites.size() + 1) * int(spec.per_site)
	if total < int(spec.permit_at):
		return _build(sim, id, f, s)
	var mid := site_center(f, s)
	var ring := []
	for i in 12:
		var a := TAU * i / 12.0
		ring.append([mid.x + cos(a) * float(spec.reach), mid.z + sin(a) * float(spec.reach)])
	var n := int(spec.per_site)
	var homes_line := "No homes are within %d m." % roundi(float(spec.reach)) if near[0] == 0 \
		else "%d home%s within %d m would smell it on still summer evenings and lose some value." % [
			near[0], "" if near[0] == 1 else "s", roundi(float(spec.reach))]
	var req := sim.permits.file(sim, {"hub": "farm", "hub_id": id, "leader": who, "ask": "cfo",
		"title": "%s for %s %s" % [spec.name, _count(n), spec.head_name],
		"why": "%s wants to build %s for %s %s. At %s head the farm needs a confined feeding approval, so it asks you first. %s" % [
			who, str(spec.name).to_lower(), _count(n), spec.head_name, _count(total), homes_line],
		"area": ring, "change": "Confined feeding operation",
		"yes": "The barns go up: %d job%s, feed bought from farms around town, manure that saves fertiliser, and %s for the %s." % [
			int(spec.jobs), "" if int(spec.jobs) == 1 else "s", spec.buyer, spec.head_name],
		"no": "The farm stays with what it has and won't ask again for %d years." % Balance.LIVESTOCK_WAIT_YEARS})
	if req == -1:
		st.why = "%s wants %s and will ask you when the bell has room." % [who, str(spec.name).to_lower()]
		st.year = sim.farms.year - 1  # try again at the next step
		return false
	st.pending = {"req": req, "site": [s.x, s.y]}
	st.why = "%s asked you for %s (see the bell)." % [who, str(spec.name).to_lower()]
	return false


## The player answered (or the bell shelved it).
static func _check_permit(sim: CitySim, id: int, f: Dictionary) -> bool:
	var st := stock(f)
	var req := int(st.pending.req)
	var state := sim.permits.state_of(req)
	if state == Permits.State.OPEN:
		return false
	var s := Vector2i(int(st.pending.site[0]), int(st.pending.site[1]))
	st.pending = {}
	if state == Permits.State.APPROVED:
		sim.permits.done(req)
		if s in f.cells and s + Vector2i(1, 0) in f.cells:
			return _build(sim, id, f, s)
		st.year = sim.farms.year - 1  # the ground changed: pick again next step
		return false
	st.wait = sim.farms.year + Balance.LIVESTOCK_WAIT_YEARS
	if st.sites.is_empty():
		st.kind = ""
	st.why = "%s kept to what it has after the town said no to new barns." % _leader(sim, id)
	return false


## Puts up a barn group on two of the farm's cells.
static func _build(sim: CitySim, id: int, f: Dictionary, s: Vector2i) -> bool:
	var st := stock(f)
	f.cells.erase(s)
	f.cells.erase(s + Vector2i(1, 0))
	st.sites.append([s.x, s.y])
	var spec: Dictionary = Balance.LIVESTOCK[st.kind]
	st.why = "%s built %s: %s %s now, sold to %s." % [_leader(sim, id), str(spec.name).to_lower(),
		_count(head(f)), spec.head_name, spec.buyer]
	return true


## Gives a path up: barns come down and their ground goes back to fields.
static func retool(sim: CitySim, id: int, f: Dictionary, why: String) -> bool:
	var st := stock(f)
	for c in site_cells(f):
		if not c in f.cells:
			f.cells.append(c)
	st.sites = []
	st.kind = ""
	st.loss = 0
	st.wait = sim.farms.year + Balance.LIVESTOCK_WAIT_YEARS
	st.why = why
	return true


## For saves: the record as plain data.
static func to_save(f: Dictionary) -> Dictionary:
	if not f.has("stock"):
		return {}
	var st: Dictionary = f.stock
	return {"kind": st.kind, "sites": st.sites, "pending": st.pending, "loss": st.loss, "wait": st.wait,
		"year": st.year, "why": st.why}


static func from_save(d: Dictionary) -> Dictionary:
	var sites_in := []
	for s in d.get("sites", []):
		sites_in.append([int(s[0]), int(s[1])])
	var pending: Dictionary = d.get("pending", {})
	if not pending.is_empty():
		pending = {"req": int(pending.req), "site": [int(pending.site[0]), int(pending.site[1])]}
	return {"kind": str(d.get("kind", "")), "sites": sites_in, "pending": pending, "loss": int(d.get("loss", 0)),
		"wait": int(d.get("wait", 0)), "year": int(d.get("year", 0)), "why": str(d.get("why", ""))}
