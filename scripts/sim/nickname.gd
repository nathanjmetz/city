class_name TownNickname
extends RefCounted
## The nickname a town earns from what it really is (Brawn, 2026-10-23), and
## the ones it outgrew. Part of the CORE PILLAR: as the town's culture
## (TownCulture) drifts with its jobs and the player's answers on the bell,
## its nickname follows, so the player sees the town change identity.
##
## Nicknames follow real ones: Elkhart is the "RV Capital of the World",
## Bedford the "Limestone Capital of the World", Crawfordsville the "Athens of
## Indiana", Madison is known for its historic district, and the state motto
## is "The Crossroads of America". The words come from what the town actually
## has (a mill town that becomes a steel town is renamed), and old nicknames
## are remembered ("Once the Corn Capital of Pike County, 2027 to 2041").
##
## Monthly; saved; deterministic.

signal changed

## The county the real map sits in (Marion, Grant County, Indiana).
const COUNTY := "Grant County"
const VALLEY := "the Mississinewa Valley"
## Plain words for each of TownCulture's sectors, for the Town panel.
const SECTOR_NAMES := {"farm": "Farming", "mining": "Gravel and gas", "timber": "Timber",
	"manufacturing": "Mills and factories", "trade": "Shops and Main Street", "office": "Offices and banking",
	"campus": "College and hospital", "transport": "Railroad and power"}
## Sectors whose words can change while the identity holds (a mill town
## that became a steel town). Crops trade places too often to rename a farm
## town over them.
const RENAMES := ["mining", "manufacturing", "office", "campus", "transport"]

## The nickname now: {"text", "sector", "since"} (since: calendar year), or {}.
var current := {}
## Earlier nicknames: [{"text", "from", "to"}], oldest first.
var past := []
## The lean toward history from preservation answers (fades).
var historic_lean := 0.0


## Once a game month, after the culture: has the town earned a nickname, or
## a new one?
func month(sim) -> void:
	historic_lean = snappedf(historic_lean * pow(0.5, 1.0 / Balance.NICKNAME_LEAN_HALF_LIFE_DAYS), 0.0001)
	if int(sim.stats.get("population", 0)) < Balance.NICKNAME_MIN_POP:
		return
	var sector := "historic" if historic_share(sim) >= Balance.NICKNAME_HISTORIC_SHARE else str(sim.culture.identity)
	if sector == "":
		return
	if sector == str(current.get("sector", "")) and not sector in RENAMES:
		return
	_rename(sim, title_for(sim, sector), sector)


## Buildings in protected districts as a share of the town's, plus the lean.
func historic_share(sim) -> float:
	var n: int = sim.buildings.size()
	return (float(sim.heritage.protected_count()) / n if n > 0 else 0.0) + historic_lean


## A preservation answer (Heritage) leans the town toward its history.
func lean_historic(amount: float) -> void:
	historic_lean = snappedf(clampf(historic_lean + amount, 0.0, 0.3), 0.0001)


func _rename(sim, text: String, sector: String) -> void:
	if text == "" or text == str(current.get("text", "")):
		return
	var year := Families.calendar(Seasons.year(sim.tick_count))
	if not current.is_empty():
		past.append({"text": str(current.text), "from": int(current.since), "to": year})
	current = {"text": text, "sector": sector, "since": year}
	changed.emit()


## The nickname a town known for `sector` earns, from what it actually has.
static func title_for(sim, sector: String) -> String:
	match sector:
		"farm":
			var corn := 0
			var soy := 0
			for id in sim.farms.farms:
				if str(sim.farms.farms[id].crop) == "soybeans":
					soy += sim.farms.farms[id].cells.size()
				else:
					corn += sim.farms.farms[id].cells.size()
			return ("Soybean" if soy > corn else "Corn") + " Capital of " + COUNTY
		"mining":
			var oil := 0
			var ore := 0
			for id in sim.industry.sites:
				var s: Dictionary = sim.industry.sites[id]
				if str(s.kind) == "oil":
					oil += s.pads.size()
				elif str(s.kind) == "ore":
					ore += s.pads.size()
			# Grant County's oil and gas is the Trenton field of the Indiana Gas
			# Belt (the 1887 boom); what it digs is valley sand, gravel and stone.
			return ("Gas Belt Town of " + COUNTY) if oil > ore else ("Gravel Town of " + VALLEY)
		"timber":
			return "Hardwood Capital of East Central Indiana"
		"manufacturing":
			var by := {"general": 0, "mill": 0, "sawmill": 0, "refinery": 0, "metal": 0}
			for key in sim.buildings:
				var b: Dictionary = sim.buildings[key]
				if int(b.zone) == ZoneMap.Zone.INDUSTRIAL:
					var c := str(b.get("chain", "general"))
					by[c] = int(by.get(c, 0)) + int(b.cap)
			var top := "general"
			for k in ["mill", "sawmill", "refinery", "metal"]:
				if int(by[k]) > int(by[top]):
					top = k
			return {
				"mill": "Mill Town of " + COUNTY,
				"sawmill": "Hardwood Capital of Southern Indiana",
				"refinery": "Oil Town of " + VALLEY,
				"metal": "Steel Town of Southern Indiana",
				"general": "Factory Town of " + COUNTY,
			}[top]
		"trade":
			return "Market Town of " + VALLEY
		"office":
			var office := 0
			for key in sim.buildings:
				if BuildingTypes.type_of(sim.buildings[key]) == "office":
					office += int(sim.buildings[key].cap)
			return ("Banking Center" if sim.banks.jobs() * 2 >= office else "Business Center") + " of Southern Indiana"
		"campus":
			if sim.education.jobs() >= sim.healthcare.jobs(sim):
				return "Athens of " + VALLEY
			return "Medical Center of Southern Indiana"
		"transport":
			if sim.rail.jobs() >= sim.power.jobs():
				return "Railroad Town of " + COUNTY
			return "Power Plant Town of " + COUNTY
		"historic":
			return "Historic River Town of " + COUNTY
	return ""


func to_dict() -> Dictionary:
	return {"current": current, "past": past, "lean": historic_lean}


func from_dict(d: Dictionary) -> void:
	var n: Dictionary = d.get("current", {})
	current = {} if n.is_empty() else {"text": str(n.text), "sector": str(n.sector), "since": int(n.since)}
	past.clear()
	for p in d.get("past", []):
		past.append({"text": str(p.text), "from": int(p.from), "to": int(p.to)})
	historic_lean = float(d.get("lean", 0.0))
	changed.emit()
