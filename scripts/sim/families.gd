class_name Families
extends RefCounted
## Who owns what (Brawn): every shop, factory, farm and resource company
## belongs to a family and carries a believable name (Names). Each family
## has a brand, its lettering and sign colours, so everything it owns looks
## like one business.
##
## A family that does well branches out, like real small-town families
## where the one with the grain elevator also owns the diner and the
## hardware store. It never sprawls on its own (Brawn): it may only open on
## a lot the player already zoned, or buy a business that's already there,
## each move is a permit the player approves or denies, and it owns at most
## Balance.FAMILY_MAX_HUBS businesses in town. What it opens or buys is an
## ordinary hub after that (it only grows next door).
##
## Over the years the brand gets a history: "Since 2031" on old signs, a
## "formerly" when a business changes hands, a new generation taking over,
## and now and then a family redoing its look in modern lettering.
##
## A business is keyed by ref: "lot:<key>" (shops and factories),
## "farm:<id>", "site:<id>". Names are given in the tick (CitySim connects
## sync() ahead of the views), so every copy of a city agrees.

signal changed

## The permit bell's name for a family's requests.
const HUB := "family"

var families := {}   # id -> family Dictionary
var owned := {}      # ref -> business Dictionary
var next_id := 1
var _used := {}      # business name -> ref, rebuilt from owned
var _by_family := {} # family id -> its refs, oldest first; rebuilt when stale
var _stale := true
var _asking := false  # some family has a request open (set in month())


## Names any business that has none yet and forgets ones that are gone.
func sync(sim) -> void:
	var live := {}
	var fresh := []
	for key in sim.buildings:
		var z := int(sim.buildings[key].zone)
		if z == ZoneMap.Zone.COMMERCIAL or z == ZoneMap.Zone.INDUSTRIAL:
			var ref := "lot:" + str(key)
			live[ref] = true
			if not owned.has(ref):
				fresh.append(ref)
	for id in sim.farms.farms:
		var ref := "farm:%d" % id
		live[ref] = true
		if not owned.has(ref):
			fresh.append(ref)
	for id in sim.industry.sites:
		var ref := "site:%d" % id
		live[ref] = true
		if not owned.has(ref):
			fresh.append(ref)
	var gone := []
	for ref in owned:
		if not live.has(ref):
			gone.append(ref)
	for ref in gone:
		_used.erase(owned[ref].name)
		owned.erase(ref)
		_stale = true
	fresh.sort()
	var trades := {}
	if not fresh.is_empty():
		for ref in owned:
			trades[owned[ref].what] = int(trades.get(owned[ref].what, 0)) + 1
	for ref in fresh:
		_found(sim, ref, trades)
	if not fresh.is_empty() or not gone.is_empty():
		changed.emit()


## What a business is: a shop's trade, a factory's chain, "farm", or a
## company's kind. Shops pick their trade when first named.
static func kind_of(sim, ref: String) -> String:
	var parts := ref.split(":", true, 1)
	match parts[0]:
		"farm": return "farm"
		"site": return str(sim.industry.sites[int(parts[1])].kind)
		"lot":
			var b: Dictionary = sim.buildings[parts[1]]
			if int(b.zone) == ZoneMap.Zone.INDUSTRIAL:
				return str(b.get("chain", "general"))
	return "shop"


## A new business with a new family behind it.
## `trades` counts the town's businesses by trade: a town of a few thousand
## has one hardware store, not three, so a crowded trade is passed over.
func _found(sim, ref: String, trades: Dictionary) -> void:
	var what := kind_of(sim, ref)
	var year := Seasons.year(sim.tick_count)
	var shops := owned.size()
	for attempt in 12:
		var seed := hash([sim.city_seed, ref, attempt])
		if what == "shop":
			# An office building's tenant is an office: an agent, a lawyer,
			# an accountant, a realtor.
			var office := ref.begins_with("lot:") and BuildingTypes.type_of(sim.buildings[ref.substr(4)]) == "office"
			for pick in 8:
				var t: Dictionary = Names.trade(hash([seed, pick]), office)
				what = t.trade
				if int(trades.get(what, 0)) < 1 + shops * int(t.w) / 60:
					break
		var sur := Names.surname(seed)
		# Farms always carry the family's name; a shop or company now and
		# then takes a local place's instead.
		var brand := sur
		if what != "farm" and absi(hash([seed, "place"])) % 100 < 22:
			brand = Names.place(seed)
		var fam := _new_family(sim, sur, brand, Names.patterns(what).style, seed, year)
		var name := _name_for(fam, what, seed)
		if name != "":
			families[fam.id] = fam
			next_id += 1
			_own(ref, fam.id, what, name, year)
			trades[what] = int(trades.get(what, 0)) + 1
			return
		what = kind_of(sim, ref)
	# Every pattern taken twelve times over (a huge town): number it.
	var fam := _new_family(sim, "Miller", "Miller", "gothic", hash([sim.city_seed, ref]), year)
	families[fam.id] = fam
	next_id += 1
	_own(ref, fam.id, what, "%s %s No. %d" % [fam.brand, Names.trade_word(what).capitalize(), next_id], year)


func _new_family(sim, sur: String, brand: String, style: String, seed: int, year: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var first: String = Names.FIRST_OLD[rng.randi() % Names.FIRST_OLD.size()]
	return {
		"id": next_id, "surname": sur, "brand": brand, "first": first, "head": "%s %s" % [first, sur],
		"gen": 1, "head_since": year, "founded": year, "style": style, "colors": rng.randi() % Names.COLORS.size(),
		"redone": -1, "old_style": "", "cash": Balance.FAMILY_START_CASH,
		"ambition": snappedf(rng.randf(), 0.01), "caution": snappedf(rng.randf(), 0.01), "plan": {},
	}


## A unique name for this family's business of this kind, or "".
func _name_for(fam: Dictionary, what: String, seed: int) -> String:
	var list: Array = Names.patterns(what).names
	for i in list.size():
		var n := Names.fill(list[(absi(seed) + i) % list.size()], fam.brand, fam.first)
		if not _used.has(n):
			return n
	return ""


func _own(ref: String, fam_id: int, what: String, name: String, year: int, formerly := []) -> void:
	owned[ref] = {"family": fam_id, "what": what, "name": name, "since": year, "formerly": formerly}
	_used[name] = ref
	_stale = true


# ------------------------------------------------------------- reading

func name_of(ref: String) -> String:
	return str(owned[ref].name) if owned.has(ref) else ""


func family_of(ref: String) -> Dictionary:
	return families.get(int(owned[ref].family), {}) if owned.has(ref) else {}


## Every business a family owns, oldest first.
func hubs_of(fam_id: int) -> Array:
	if _stale:
		_by_family.clear()
		for ref in owned:
			var id := int(owned[ref].family)
			if not _by_family.has(id):
				_by_family[id] = []
			_by_family[id].append(ref)
		for id in _by_family:
			_by_family[id].sort_custom(func(a, b): return [owned[a].since, a] < [owned[b].since, b])
		_stale = false
	return _by_family.get(fam_id, []).duplicate()


## What a sign shows: {text, style, panel, letter, since (year or -1)}, or
## {} for a business with no name yet.
func sign_of(sim, ref: String) -> Dictionary:
	if not owned.has(ref):
		return {}
	var b: Dictionary = owned[ref]
	var fam := family_of(ref)
	var year := Seasons.year(sim.tick_count)
	var pair: Array = Names.COLORS[int(fam.get("colors", 0)) % Names.COLORS.size()]
	return {"text": str(b.name), "style": str(fam.get("style", "gothic")), "panel": Color(pair[0]),
		"letter": Color(pair[1]), "since": calendar(int(b.since)) if year - int(b.since) >= Balance.FAMILY_SINCE_SHOWN else -1}


## The calendar year a game year falls in: Year 1 is 2027, when the game's
## clock starts (CitySim.START_UNIX), so signs read like real ones.
static func calendar(year: int) -> int:
	return 2026 + year


## A short key that changes whenever a business's sign would look different.
func sign_key(sim, ref: String) -> String:
	var s := sign_of(sim, ref)
	return "" if s.is_empty() else "%s|%s|%s|%d" % [s.text, s.style, s.panel.to_html(), s.since]


## Rows for a business's info panel.
func rows(sim, ref: String) -> Array:
	if not owned.has(ref):
		return []
	var b: Dictionary = owned[ref]
	var fam := family_of(ref)
	var out := [["Owned by", "The %s family" % fam.surname], ["Run by", _head_text(fam)],
		["In business since", str(calendar(int(b.since)))]]
	if not b.formerly.is_empty():
		out.append(["Formerly", ", ".join(b.formerly)])
	var also := []
	for other in hubs_of(int(fam.id)):
		if other != ref:
			also.append(name_of(other))
	if not also.is_empty():
		out.append(["The family also owns", ", ".join(also)])
	if int(fam.redone) > 0:
		out.append(["New look", "Redid its signs in %d" % calendar(int(fam.redone))])
	var plan: Dictionary = fam.get("plan", {})
	if not plan.is_empty():
		out.append(["The family's plans", str(plan.title)])
	return out


func _head_text(fam: Dictionary) -> String:
	match int(fam.gen):
		1: return str(fam.head)
		2: return "%s, the second generation" % fam.head
		3: return "%s, the third generation" % fam.head
	return "%s, generation %d" % [fam.head, fam.gen]


## A home's family, from its seed: "The Hayes home".
static func home_name(b: Dictionary) -> String:
	return "%s home" % Names.surname(hash([int(b.seed), "home"]))


# ------------------------------------------------------------- monthly

## Once a game month: owners take their draw, generations pass, old brands
## get a new look, and families ready to branch out ask the player.
func month(sim) -> void:
	var year := Seasons.year(sim.tick_count)
	var any := false
	var ids := families.keys()
	ids.sort()
	var counts := {}
	for ref in owned:
		counts[int(owned[ref].family)] = int(counts.get(int(owned[ref].family), 0)) + 1
		# Old enough now for "SINCE 2031" on the sign.
		if year - int(owned[ref].since) == Balance.FAMILY_SINCE_SHOWN and Seasons.month(sim.tick_count) == 1:
			any = true
	_asking = false
	for fam in families.values():
		if not fam.plan.is_empty():
			_asking = true
	for id in ids:
		var fam: Dictionary = families[id]
		if not counts.has(id):
			# Sold or closed everything: the family is gone from town.
			if fam.plan.is_empty():
				families.erase(id)
			continue
		for ref in hubs_of(id):
			fam.cash += _draw(sim, ref)
		if year - int(fam.head_since) >= Balance.FAMILY_GENERATION_YEARS:
			fam.gen += 1
			fam.head_since = year
			fam.first = Names.FIRST_NEW[absi(hash([id, fam.gen, sim.city_seed])) % Names.FIRST_NEW.size()]
			fam.head = "%s %s" % [fam.first, fam.surname]
		if int(fam.redone) < 0 and year - int(fam.founded) >= Balance.FAMILY_REBRAND_YEARS \
				and fam.cash >= Balance.FAMILY_REBRAND_COST * 3:
			fam.old_style = fam.style
			fam.style = "franklin" if fam.style == "gothic" else "gothic"
			fam.redone = year
			fam.cash -= Balance.FAMILY_REBRAND_COST
			any = true
		if _carry_out(sim, fam):
			any = true
		_maybe_expand(sim, fam, int(counts[id]), year)
	if any:
		changed.emit()


## What the owners take home this month from one business.
func _draw(sim, ref: String) -> int:
	var parts := ref.split(":", true, 1)
	match parts[0]:
		"farm": return roundi(maxf(sim.farms.yearly_profit(int(parts[1])), 0.0) / 12.0 * Balance.FAMILY_PROFIT_SHARE)
		"site": return roundi(maxf(sim.industry.yearly_profit(int(parts[1])), 0.0) / 12.0 * Balance.FAMILY_PROFIT_SHARE)
		"lot":
			if sim.utilities_ok(parts[1]):
				return int(sim.buildings[parts[1]].cap) * Balance.FAMILY_PER_JOB
	return 0


## True once every business of the family has been going a while and pays.
func _doing_well(sim, fam_id: int, year: int) -> bool:
	var hubs := hubs_of(fam_id)
	if hubs.is_empty() or year - int(owned[hubs[0]].since) < Balance.FAMILY_EXPAND_AFTER:
		return false
	for ref in hubs:
		var parts: PackedStringArray = ref.split(":", true, 1)
		match parts[0]:
			"farm":
				if sim.farms.yearly_profit(int(parts[1])) < 0.0:
					return false
			"site":
				if sim.industry.yearly_profit(int(parts[1])) < 0.0:
					return false
			"lot":
				if not sim.utilities_ok(parts[1]):
					return false
	return true


## A family ready to branch out picks one move and files it as a permit:
## open on an empty lot the player zoned, or buy a one-business family's
## shop, factory, farm or company. It pays from its own money.
func _maybe_expand(sim, fam: Dictionary, count: int, year: int) -> void:
	if not fam.plan.is_empty() or count >= Balance.FAMILY_MAX_HUBS or not _doing_well(sim, int(fam.id), year):
		return
	# One family at a time asks, so families never crowd the bell (the
	# railroad and the bus company need room there too).
	if _asking:
		return
	var roll := float(absi(hash([sim.city_seed, fam.id, sim.tick_count]) % 10000)) / 10000.0
	if roll >= float(fam.ambition) * Balance.FAMILY_EXPAND_CHANCE:
		return
	if not sim.permits.can_file(sim, HUB, int(fam.id)):
		return
	var plan := _start_plan(sim, fam)
	if plan.is_empty() or float(fam.cash) < float(plan.cost) or roll < float(fam.ambition) * Balance.FAMILY_EXPAND_CHANCE * 0.35:
		var buy := _buy_plan(sim, fam)
		if not buy.is_empty() and float(fam.cash) >= float(buy.cost):
			plan = buy
	if plan.is_empty() or float(fam.cash) < float(plan.cost):
		return
	var area := []
	for p in plan.outline:
		area.append([p.x, p.y])
	var mine := []
	for ref in hubs_of(int(fam.id)):
		mine.append(name_of(ref))
	var rid: int = sim.permits.file(sim, {"hub": HUB, "hub_id": int(fam.id), "leader": str(fam.head),
		"title": plan.title, "why": "The %s family's %s %s doing well, and they want to branch out." % [fam.surname,
			" and ".join(mine), "is" if mine.size() == 1 else "are"],
		"area": area, "change": plan.change, "base": int(plan.cost), "per_m2": 0, "budget": int(fam.cash)})
	if rid < 0:
		return
	plan.req = rid
	plan.erase("outline")
	fam.plan = plan
	_asking = true


## Opening on an empty lot the player zoned for shops or industry, with
## power and water and demand for it: a trade the family doesn't run yet.
func _start_plan(sim, fam: Dictionary) -> Dictionary:
	var have := {}
	for ref in hubs_of(int(fam.id)):
		have[owned[ref].what] = true
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	if empty.is_empty():
		return {}
	var start := absi(hash([sim.city_seed, fam.id, sim.tick_count, "lot"])) % empty.size()
	for i in empty.size():
		var key: String = empty[(start + i) % empty.size()]
		var z: int = sim.zones.zone_at(sim.lots[key].zone_pt)
		if z != ZoneMap.Zone.COMMERCIAL and z != ZoneMap.Zone.INDUSTRIAL:
			continue
		if float(sim.demand.get(z, 0.0)) < 0.05 or not sim.utilities_ok(key):
			continue
		var what := ""
		var name := ""
		if z == ZoneMap.Zone.INDUSTRIAL:
			what = sim.factory_chain(sim.lots[key].pos)
			name = _name_for(fam, what, hash([fam.id, key]))
		else:
			for j in Names.TRADES.size():
				var t: Dictionary = Names.trade(hash([fam.id, key, j]))
				if not have.has(t.trade):
					what = t.trade
					name = _name_for(fam, what, hash([fam.id, key, j]))
					if name != "":
						break
		if name == "":
			continue
		var size := "factory" if z == ZoneMap.Zone.INDUSTRIAL else "shop"
		return {"kind": "start", "ref": "lot:" + key, "zone": z, "what": what, "name": name,
			"cost": Balance.FAMILY_START_COST[size], "outline": sim.lots[key].corners,
			"title": "The %s family wants to open %s" % [fam.surname, name], "change": "Opens %s" % name}
	return {}


## Buying out a family that owns just one business (most often one getting
## on in years), renamed under this family's brand.
func _buy_plan(sim, fam: Dictionary) -> Dictionary:
	var counts := {}
	for ref in owned:
		counts[int(owned[ref].family)] = int(counts.get(int(owned[ref].family), 0)) + 1
	var refs := owned.keys()
	refs.sort()
	if refs.is_empty():
		return {}
	var start := absi(hash([sim.city_seed, fam.id, sim.tick_count, "buy"])) % refs.size()
	for i in refs.size():
		var ref: String = refs[(start + i) % refs.size()]
		var b: Dictionary = owned[ref]
		if int(b.family) == int(fam.id) or int(counts[int(b.family)]) > 1 or not families.has(int(b.family)):
			continue
		# A business that's on its last legs isn't worth having; one whose
		# owners are nearing retirement is the classic sale.
		var other: Dictionary = families[int(b.family)]
		if not other.plan.is_empty():
			continue
		var name := _name_for(fam, b.what, hash([fam.id, ref]))
		if name == "":
			continue
		var parts := ref.split(":", true, 1)
		var cost := 0
		var outline := PackedVector2Array()
		match parts[0]:
			"farm":
				var f: Dictionary = sim.farms.farms[int(parts[1])]
				cost = roundi(f.cells.size() * Farms.ACRES_PER_CELL * Farms.LAND_PER_ACRE)
				outline = sim.farms._yard(f)
			"site":
				cost = Balance.FAMILY_BUY_COST.company
				outline = sim.industry._yard(sim.industry.sites[int(parts[1])])
			"lot":
				if not sim.lots.has(parts[1]) or not sim.utilities_ok(parts[1]):
					continue
				var factory: bool = int(sim.buildings[parts[1]].zone) == ZoneMap.Zone.INDUSTRIAL
				cost = Balance.FAMILY_BUY_COST["factory" if factory else "shop"]
				outline = sim.lots[parts[1]].corners
		if outline.size() < 3 or float(fam.cash) < cost:
			continue
		return {"kind": "buy", "ref": ref, "what": b.what, "name": name, "from": b.name, "cost": cost, "outline": outline,
			"title": "The %s family wants to buy %s" % [fam.surname, b.name],
			"change": "%s becomes %s" % [b.name, name]}
	return {}


## Acts on the player's answer to the family's request. True if anything
## in town changed hands or opened.
func _carry_out(sim, fam: Dictionary) -> bool:
	var plan: Dictionary = fam.plan
	if plan.is_empty():
		return false
	var state: int = sim.permits.state_of(int(plan.req))
	if state == Permits.State.OPEN:
		return false
	fam.plan = {}
	if state != Permits.State.APPROVED:
		return false
	sim.permits.done(int(plan.req))
	var year := Seasons.year(sim.tick_count)
	var ref: String = plan.ref
	var key := ref.substr(4)
	var cost := int(sim.permits.requests.get(int(plan.req), {}).get("cost", plan.cost))
	if fam.cash < cost or _used.has(str(plan.name)):
		return false
	if plan.kind == "start":
		# The lot must still be empty and zoned the same.
		if not sim.lots.has(key) or sim.buildings.has(key) or sim.zones.zone_at(sim.lots[key].zone_pt) != int(plan.zone):
			return false
		_own(ref, int(fam.id), str(plan.what), str(plan.name), year)
		sim.found_business(key, int(plan.zone), str(plan.what))
	else:
		if not owned.has(ref) or str(owned[ref].name) != str(plan.from):
			return false
		var seller := int(owned[ref].family)
		_used.erase(owned[ref].name)
		var was: Array = owned[ref].formerly.duplicate()
		was.append(str(plan.from))
		_own(ref, int(fam.id), str(plan.what), str(plan.name), year, was)
		if families.has(seller):
			families[seller].cash += cost
	fam.cash -= cost
	return true


## Where a family stands (its oldest business), for pre-approved permits.
func locate(sim, fam_id: int) -> Vector2:
	for ref in hubs_of(fam_id):
		var parts: PackedStringArray = ref.split(":", true, 1)
		match parts[0]:
			"farm": return Vector2(sim.farms.farms[int(parts[1])].pos.x, sim.farms.farms[int(parts[1])].pos.z)
			"site": return Vector2(sim.industry.sites[int(parts[1])].pos.x, sim.industry.sites[int(parts[1])].pos.z)
			"lot":
				if sim.lots.has(parts[1]):
					return Vector2(sim.lots[parts[1]].pos.x, sim.lots[parts[1]].pos.z)
	return Vector2.INF


# ------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var fams := {}
	for id in families:
		fams[str(id)] = families[id]
	return {"families": fams, "owned": owned, "next": next_id}


func from_dict(d: Dictionary) -> void:
	families.clear()
	owned.clear()
	_used.clear()
	_stale = true
	next_id = int(d.get("next", 1))
	for k in d.get("families", {}):
		var f: Dictionary = d.families[k].duplicate(true)
		for n in ["id", "gen", "head_since", "founded", "colors", "redone", "cash"]:
			f[n] = int(f.get(n, 0))
		if not f.has("plan"):
			f.plan = {}
		families[int(k)] = f
	for ref in d.get("owned", {}):
		var b: Dictionary = d.owned[ref].duplicate(true)
		b.family = int(b.family)
		b.since = int(b.since)
		owned[str(ref)] = b
		_used[str(b.name)] = str(ref)
