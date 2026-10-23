class_name PollutionInfo
extends RefCounted
## Pollution in the info panel, so it is never a mystery (Brawn: in Cities:
## Skylines it was often impossible to tell where pollution came from or how
## to fix it):
## - any spot or home says how much smoke, noise and dirty ground it has, and
##   exactly which sources make it, with their shares;
## - any source says what it puts out, how many homes it hurts, whether its
##   owner is already saving for cleaner equipment, and every way to fix it;
## - "Go to" buttons jump between the two.

## How many sources to name for each kind.
const TOP := 3


## The pollution source a selection is, or "".
static func ref_of(sim: CitySim, sel: Dictionary) -> String:
	var p := sim.pollution
	var ref := ""
	match sel.get("type", ""):
		"lot": ref = "lot:" + str(sel.id)
		"industry": ref = "site:%d" % int(sel.id)
		"hub": ref = "hub:%d" % int(sel.id)
		"farm": ref = "farm:%d" % int(sel.id)
		"road":
			for r in p.sources:
				if int(sel.id) in p.sources[r].segs:
					return r
	if p.sources.has(ref):
		return ref
	for r in p.sources:
		if p.sources[r].select == sel:
			return r
	return ""


## Adds pollution to an Inspect.describe() result.
static func add(sim: CitySim, sel: Dictionary, d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	if sim.pollution.sources.is_empty() and sim.pollution.version == 0:
		sim.pollution.rebuild(sim)
	var ref := ref_of(sim, sel)
	if ref != "":
		_source_part(sim, ref, d)
	if sel.type == "lot":
		_lot_part(sim, str(sel.id), d)
	return d


## The panel for a click on open ground while a pollution view is on.
static func spot(sim: CitySim, p: Vector3) -> Dictionary:
	if sim.pollution.sources.is_empty() and sim.pollution.version == 0:
		sim.pollution.rebuild(sim)
	var s := sim.pollution.sample(p)
	var d := {"title": "Pollution here", "kind": "Pollution", "icon": "pollution", "ok": true,
		"status": "", "rows": [], "problems": [], "notes": [], "actions": []}
	var worst := _readings(sim, s, d)
	d.ok = worst == ""
	d.status = "Clean and quiet" if worst == "" else worst
	if s.smoke >= Pollution.SMOKE_FLOOR:
		var w := Pollution.wind_words()
		d.notes.append("The wind blows from the %s, so smoke drifts %s." % [w[0], w[1]])
	if d.rows.is_empty():
		d.rows.append(["Smoke", "None"])
		d.rows.append(["Noise", "Quiet"])
		d.rows.append(["Dirty ground", "None"])
	return d


static func _lot_part(sim: CitySim, key: String, d: Dictionary) -> void:
	var lot: Dictionary = sim.lots[key]
	var s := sim.pollution.sample(lot.pos)
	var worst := _readings(sim, s, d)
	var b: Dictionary = sim.buildings.get(key, {})
	var home := not b.is_empty() and int(b.zone) == ZoneMap.Zone.RESIDENTIAL
	var worn: float = sim.pollution.wear.get(key, 0.0)
	if home and worn >= 0.1:
		d.rows.append(["Upkeep", "Worn" if worn < 0.5 else "Run down"])
		d.notes.push_front("Pollution is wearing this home down: stained siding, peeling paint. It sells for less.")
	if worst != "" and home:
		d.ok = false


## Rows for each kind of pollution at a reading, with the sources behind it,
## problems for what's over the line, and Go to buttons. Returns the worst
## problem in a few words, or "".
static func _readings(sim: CitySim, s: Dictionary, d: Dictionary) -> String:
	var p := sim.pollution
	if not d.has("notes"):
		d.notes = []
	if not d.has("actions"):
		d.actions = []
	var worst := ""
	var go := {}
	for kind in ["noise", "smoke", "ground"]:
		var v: float = s[kind]
		var by: Array = s.by[kind]
		var shows: bool = (kind == "noise" and v >= Balance.NOISE_QUIET_DB - 5.0) \
			or (kind == "smoke" and v >= Pollution.SMOKE_FLOOR) or (kind == "ground" and v >= Pollution.GROUND_FLOOR)
		if not shows:
			continue
		d.rows.append([label(kind), amount(kind, v) + "  ·  " + words(kind, v)])
		for i in mini(by.size(), TOP):
			var ref: String = by[i][0]
			if not p.sources.has(ref):
				continue
			d.rows.append(["   %d%%" % roundi(by[i][1] * 100.0), p.sources[ref].name])
			go[ref] = true
		if hurts(kind, v) and not by.is_empty() and p.sources.has(by[0][0]):
			var src: Dictionary = p.sources[by[0][0]]
			var line := "%s %s, mostly from %s (%d%%)." % [label(kind), amount(kind, v), src.name, roundi(by[0][1] * 100.0)]
			var fix := quick_fix(sim, src, kind)
			if fix != "":
				line += " " + fix
			d.problems.append(line)
			if worst == "":
				worst = "%s: %s" % [words(kind, v), amount(kind, v)]
	var refs := go.keys()
	refs.sort_custom(func(a, b): return p.sources[a].name < p.sources[b].name)
	for ref in refs:
		var src: Dictionary = p.sources[ref]
		if src.select.is_empty():
			continue
		d.actions.append({"label": "Go to " + src.name, "go": src.select, "at": src.center})
	return worst


## Adds what a source puts out, who it hurts and how to fix it.
static func _source_part(sim: CitySim, ref: String, d: Dictionary) -> void:
	var p := sim.pollution
	var s: Dictionary = p.sources[ref]
	# Every place has its own name; the panel's old title says what it is.
	# (Businesses already show their family's name; roads get theirs here.)
	if s.select.get("type", "") == "road" and d.title != s.name:
		d.kind = "%s  ·  %s" % [d.title, d.kind]
		d.title = s.name
	if not d.has("notes"):
		d.notes = []
	if not d.has("actions"):
		d.actions = []
	var makes := []
	var smoke: float = s.smoke
	var noise: float = s.noise
	for l in s.lines:
		smoke = maxf(smoke, l[3])
		noise = maxf(noise, l[2])
	if smoke >= Pollution.SMOKE_FLOOR:
		makes.append("smoke")
	if noise > Pollution.NOISE_FLOOR_DB:
		makes.append("%d dB noise" % roundi(noise))
	if s.ground >= Pollution.GROUND_FLOOR:
		makes.append("dirty ground")
	if makes.is_empty():
		return
	d.rows.append(["Pollution", ", ".join(makes)])
	var h: Dictionary = p.hurts.get(ref, {})
	if h.is_empty():
		d.rows.append(["Homes it hurts", "None"])
	else:
		d.rows.append(["Homes it hurts", "%d (%s people)" % [h.homes, CitySim.money_text(int(h.people))]])
	if s.owner != "":
		var now := p.equipment(ref, s.owner)
		d.rows.append(["Cleaner equipment", "None yet" if now.is_empty() else str(now.name).capitalize()])
	for f in fixes(sim, s):
		d.notes.append(f)
	var help := p.help_cost(ref)
	if help >= 0:
		var next := p.next_equipment(ref, s.owner)
		d.actions.append({"label": "Help pay for %s ($%s)" % [next.name, CitySim.money_text(help)],
			"cmd": {"type": "fund_cleanup", "ref": ref}, "enabled": help <= sim.economy.money})
	var wall := p.wall_cost(sim, ref)
	if wall >= 0:
		d.actions.append({"label": "Build noise walls ($%s)" % CitySim.money_text(wall),
			"cmd": {"type": "noise_wall", "ref": ref}, "enabled": wall <= sim.economy.money})


## Every way to clean a source up, in plain words.
static func fixes(sim: CitySim, s: Dictionary) -> Array:
	var p := sim.pollution
	var out := []
	if s.owner != "":
		var next := p.next_equipment(s.ref, s.owner)
		if next.is_empty():
			out.append("Already runs the cleanest equipment there is.")
		else:
			var plan: Dictionary = p.owners.get(s.ref, {"saved": 0.0})
			var saving := p.monthly_saving(sim, s)
			var left := maxf(float(next.cost) - float(plan.saved), 0.0)
			if p.educated(sim, s):
				out.append("The owner is saving for %s: %d%% there, about %d months to go." % [next.name,
					roundi(100.0 * float(plan.saved) / float(next.cost)), ceili(left / maxf(saving, 1.0))])
			else:
				out.append("The owner is barely saving for %s (%d%% there): few educated leaders in town. A school within %.0f miles, or local graduates, gets owners investing in cleaner ways." % [
					next.name, roundi(100.0 * float(plan.saved) / float(next.cost)),
					Services.KINDS[Services.Kind.SCHOOL].reach / 1609.0])
			out.append("You can help pay for it now, below.")
	match s.kind:
		"highway", "boulevard":
			if p.wall_cost(sim, s.ref) >= 0:
				out.append("Noise walls along it cut its noise by %d dB." % roundi(Balance.NOISE_WALL_DB))
			else:
				out.append("It has noise walls.")
		"landfill":
			out.append("Replace it with a recycling centre: far less dust, smell and dirty ground.")
		"recycling_1", "recycling_2":
			out.append("Upgrade it to cut its noise and dirt further.")
	for f in s.get("fixes", []):
		out.append(str(f))
	var reach := []
	var loud: float = s.noise
	for l in s.lines:
		loud = maxf(loud, l[2])
	if loud > Balance.HURT_NOISE_DB:
		reach.append("its noise carries about %d m" % roundi(Pollution.REF_M * pow(10.0, (loud - Balance.HURT_NOISE_DB) / 20.0)))
	if s.smoke > Balance.HURT_SMOKE * 0.5 and s.lines.is_empty():
		reach.append("its smoke drifts %s about %d m" % [Pollution.wind_words()[1], roundi(smoke_reach(s.smoke))])
	if s.ground >= Pollution.GROUND_FLOOR * 3.0:
		reach.append("dirty ground spreads about %d m%s" % [roundi(s.reach * 1.5), " and seeps downhill" if s.flow.length() > 1.0 else ""])
	if not reach.is_empty():
		var w := Pollution.wind_words()
		out.append("Keep homes away: %s. Upwind (to the %s) is the clean side." % [", ".join(reach), w[0]])
	return out


## Distance downwind where a source's smoke falls under EPA's yearly limit.
static func smoke_reach(q: float) -> float:
	var w := Pollution.wind()
	var d := 50.0
	while d < 5000.0 and Pollution._plume(q, w * d, w) >= Balance.HURT_SMOKE:
		d += 25.0
	return d


## The one-line fix for a home hurt by a source.
static func quick_fix(sim: CitySim, s: Dictionary, kind: String) -> String:
	match s.kind:
		"highway", "boulevard":
			if kind == "noise" and sim.pollution.wall_cost(sim, s.ref) >= 0:
				return "Noise walls on it would help."
		"landfill":
			return "Replacing it with recycling would help."
	if s.owner != "" and not sim.pollution.next_equipment(s.ref, s.owner).is_empty():
		return "Cleaner equipment there would help."
	return "Homes farther away would be spared."


static func hurts(kind: String, v: float) -> bool:
	match kind:
		"noise": return v >= Balance.HURT_NOISE_DB
		"smoke": return v >= Balance.HURT_SMOKE
		_: return v >= Balance.HURT_GROUND


static func label(kind: String) -> String:
	return {"smoke": "Smoke", "noise": "Noise", "ground": "Dirty ground"}[kind]


static func amount(kind: String, v: float) -> String:
	match kind:
		"smoke": return "%.1f µg/m³" % v if v < 10.0 else "%d µg/m³" % roundi(v)
		"noise": return "%d dB" % roundi(v)
		_: return "%d%%" % roundi(v * 100.0)


## Plain words for a level (EPA and FHWA lines).
static func words(kind: String, v: float) -> String:
	match kind:
		"smoke":
			if v < 3.0: return "clean"
			if v < 9.0: return "a little hazy"
			if v < 35.0: return "smoky, over EPA's yearly limit"
			return "unhealthy"
		"noise":
			if v < 45.0: return "quiet"
			if v < 55.0: return "ordinary town sound"
			if v < 65.0: return "noisy"
			if v < 75.0: return "very loud"
			return "deafening"
		_:
			if v < 0.1: return "trace"
			if v < 0.3: return "dirty"
			if v < 0.6: return "wells unsafe"
			return "contaminated"
