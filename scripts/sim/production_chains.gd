class_name ProductionChains
extends RefCounted
## The production chain page (Brawn's pick #15, after Anno's production
## overview): where the town's loads went over the last year, link by link,
## following each good from where it's grown, cut or dug to where it's made
## into something and on to the stores, the job sites or out of town:
##   corn  farms -> grain mill / ethanol plant / elevator -> region
##   logs  woods -> sawmill -> job sites; woods -> furniture maker -> stores
##   stone quarry -> job sites (ready-mix, asphalt, crushed stone)
##
## Every count is a real truck (or train) that arrived: Logistics, Rail and
## Construction tell it here as each one does. A year is kept as twelve
## calendar months, so the page reads "loads a year" whatever the speed.
## Nothing here is a warning or a tip: it only shows what happened.

## Months kept (one game year).
const KEEP := 12

## Places, in the order a chain reads left to right, with their name and
## icon. A link's ends are these keys.
const NODES := {
	"farm": {"name": "Farms", "icon": "farms"},
	"livestock": {"name": "Livestock farms", "icon": "farms"},
	"forest": {"name": "Woods", "icon": "forest"},
	"ore": {"name": "Quarry", "icon": "ore"},
	"oil": {"name": "Oil wells", "icon": "oil"},
	"elevator": {"name": "Grain elevator", "icon": "elevator"},
	"warehouse": {"name": "Warehouses", "icon": "warehouse"},
	"mill": {"name": "Grain mill", "icon": "industry"},
	"sawmill": {"name": "Sawmill", "icon": "industry"},
	"metal": {"name": "Metal works", "icon": "industry"},
	"refinery": {"name": "Plastics plant", "icon": "industry"},
	"general": {"name": "Factories", "icon": "industry"},
	"ethanol": {"name": "Ethanol plant", "icon": "ethanol"},
	"meatpacker": {"name": "Meatpacking plant", "icon": "meatpacker"},
	"furniture": {"name": "Furniture maker", "icon": "furniture"},
	"rv": {"name": "RV plant", "icon": "rv_plant"},
	"shop": {"name": "Stores", "icon": "shops"},
	"post": {"name": "Post office", "icon": "mail"},
	"build": {"name": "Job sites", "icon": "builder_yard"},
	"rail": {"name": "Out by rail", "icon": "rail_depot"},
	"region": {"name": "Region", "icon": "region"},
}
## How the page groups links: each chain's name and the place it starts
## from; a link belongs to the first chain whose start reaches it.
const CHAINS := [
	["Grain", ["farm"]],
	["Livestock", ["livestock"]],
	["Timber", ["forest"]],
	["Stone and gravel", ["ore"]],
	["Oil", ["oil"]],
	["Made in town", ["mill", "sawmill", "metal", "refinery", "general", "ethanol", "meatpacker", "furniture",
		"rv", "warehouse", "elevator"]],
	["Brought in", ["region"]],
]

## Where a chain ends: what goes there is used up or gone.
const ENDS := ["shop", "build", "post", "rail", "region"]

## month index -> {"from>to>good": loads}
var months := {}


## Counts one load of `good` from place `from` to place `to` (NODES keys)
## arriving in the calendar month of `cal`.
func count(cal: int, from: String, to: String, good: String, loads := 1.0) -> void:
	if from == "" or to == "" or from == to:
		return
	var m := int(floorf(Seasons.months(cal)))
	if not months.has(m):
		months[m] = {}
		var old := months.keys()
		old.sort()
		while old.size() > KEEP:
			months.erase(old.pop_front())
	var key := "%s>%s>%s" % [from, to, good]
	months[m][key] = float(months[m].get(key, 0.0)) + loads


## The place a Logistics/Construction trip end ref stands for (a NODES key),
## or "" for one the page doesn't show.
static func node_of(sim, ref: String) -> String:
	if ref == "edge":
		return "region"
	var i := ref.find(":")
	if i == -1:
		return ""
	var what := ref.substr(0, i)
	var id := ref.substr(i + 1)
	match what:
		"site":
			var s = sim.industry.sites.get(int(id))
			return "" if s == null else str(s.kind)
		"farm":
			return "farm"
		"lot":
			var b = sim.buildings.get(id)
			if b == null:
				return ""
			if int(b.zone) == ZoneMap.Zone.INDUSTRIAL:
				return str(b.get("chain", "general"))
			return "shop" if int(b.zone) == ZoneMap.Zone.COMMERCIAL else ""
		"wh":
			var w = sim.warehouses.buildings.get(int(id))
			return "elevator" if w != null and Warehouses.is_store(w) else "warehouse"
		"big":
			var f = sim.big.sites.get(int(id))
			return "" if f == null else str(f.kind)
		"mail":
			return "post"
		"livestock":
			return "livestock"
	return ""


## The last year's links: [{from, to, good, loads}], biggest first.
func links() -> Array:
	var sum := {}
	for m in months:
		for key in months[m]:
			sum[key] = float(sum.get(key, 0.0)) + float(months[m][key])
	var out := []
	var keys := sum.keys()
	keys.sort()
	for key in keys:
		var p: PackedStringArray = str(key).split(">")
		out.append({"from": p[0], "to": p[1], "good": p[2], "loads": roundi(float(sum[key]))})
	out.sort_custom(func(a, b): return a.loads > b.loads or a.loads == b.loads and str(a) < str(b))
	return out.filter(func(l): return int(l.loads) > 0)


## The page: [{name, links: [...]}], each chain's links in the order the
## goods move (from its start outward), chains with nothing left out.
func chains() -> Array:
	var left := links()
	var out := []
	for c in CHAINS:
		var reach := {}
		for n in c[1]:
			reach[n] = true
		var mine := []
		var grew := true
		while grew:
			grew = false
			for l in left.duplicate():
				if reach.has(l.from):
					mine.append(l)
					left.erase(l)
					if not l.to in ENDS:
						reach[l.to] = true  # the chain goes on from there
					grew = true
		if not mine.is_empty():
			out.append({"name": c[0], "links": mine})
	if not left.is_empty():
		out.append({"name": "Other", "links": left})
	return out


func to_dict() -> Dictionary:
	var out := {}
	for m in months:
		out[str(m)] = months[m].duplicate()
	return out


func from_dict(d: Dictionary) -> void:
	months.clear()
	for m in d:
		var row := {}
		for key in d[m]:
			row[str(key)] = float(d[m][key])
		months[int(m)] = row
