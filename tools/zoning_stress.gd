extends SceneTree
## Zoning stress test: makes many zoning scenarios (block shapes, click,
## drag and brush orders, homes going up between clicks), plats each one and
## scores every lot, then ranks the problems by how often they happen.
##
## Brawn's four rules (2026-10-24) for lot shapes:
##   1. odd shapes are possible where the land forces them (curves, skewed
##      crossings, triangles),
##   2. nonsensical shapes are impossible (slivers, bowties, overlaps, lots on
##      roads, landlocked bits),
##   3. normal rectangles square to the street are the easy default,
##   4. odd shapes where the land is square are rare or impossible.
## The benchmark is a real county parcel map: plain rectangles on straight
## streets, pie lots on curves, angled lots only at skewed corners.
##
## Run: godot --headless -s tools/zoning_stress.gd -- [--count=1000] [--seed=1]
##   [--out=dir] [--only=index] [--budgets=tools/zoning_stress_budgets.json]
##   [--shard=k/n] [--merge=a.json,b.json] [--pngs=2]
## Writes <out>/report.json and <out>/report.md, and with --pngs a plat of the
## first examples of each problem (offending lots outlined in red). With
## --budgets it fails (exit 1) when a problem shows up in more scenarios than
## its budget allows.

const CELL := 2.0  # raster size for finding unused land between lots
const GAP_REACH := 10  # cells: lots this close on both sides make a gap
const GAP_MIN := 40.0  # m², smaller gaps are drawing noise

## Each problem: which of Brawn's rules it breaks, and what it means.
const ISSUES := {
	"overlap": ["2 impossible", "two lots overlap"],
	"on_road": ["2 impossible", "a lot runs onto a road"],
	"bowtie": ["2 impossible", "a lot's outline crosses itself"],
	"sliver": ["2 impossible", "a lot thinner than 6 m everywhere"],
	"neck": ["2 impossible", "a lot pinched into two parts by a narrow neck"],
	"tiny": ["2 impossible", "a lot too small for a building (under 140 m², 1,500 sq ft)"],
	"landlocked": ["2 impossible", "a lot with under 4 m on any street"],
	"long_strip": ["2 impossible", "a lot over 6 times deeper than wide"],
	"too_deep": ["4 rare", "a home or shop lot over 60 m (200 ft) deep"],
	"depth_jump": ["4 rare", "a lot over 1.8 times deeper than its neighbour on the same street"],
	"shop_behind": ["2 impossible", "a shop or plant lot set behind other lots (a flag lot)"],
	"jagged": ["2 impossible", "a jagged or L-shaped lot (under 80% of its hull)"],
	"odd_unforced": ["4 rare", "an odd-shaped lot where the street is straight and the corner square"],
	"odd_forced": ["1 possible", "an odd-shaped lot where a curve or skewed road forces it (fine)"],
	"empty_frontage": ["3 easy", "zoned street frontage that got no lots"],
	"gap_backs": ["3 easy", "an unused strip between the backs of two rows of lots (over 40 m²)"],
	"gap_sides": ["3 easy", "zoned land between lots on a street that no lot took (over 40 m²)"],
	"click_order": ["3 easy", "the same zoning in another order gives different lots"],
	"save_reload": ["3 easy", "lots change after a save and reload"],
	"grid_not_rect": ["3 easy", "a lot on a square grid that isn't a plain rectangle"],
	"script_error": ["2 impossible", "a zoning command failed"],
}

const FAMILIES := ["grid", "rotated_grid", "odd_grid", "skew_cross", "triangle", "curves",
	"rounded", "deep", "t_junction", "arterial", "radial", "cul_de_sac", "lanes"]
## Smart paint (SmartZoning.plan) on towns partly zoned already, with homes
## going up between steps: scenarios from SMART_FROM on.
const SMART_FAMILIES := ["smart_grid", "smart_rotated_grid", "smart_arterial", "smart_odd_grid"]
const SMART_FROM := 1000
## A full run: the 1000 hand-zoned towns and 200 smart-painted ones. Budgets
## are per full run.
const RUN := 1200
## Families where every street is straight and every corner square.
const SQUARE := ["grid", "rotated_grid", "deep", "lanes", "t_junction", "cul_de_sac",
	"smart_grid", "smart_rotated_grid"]

var budgets := {}
var pngs := 0
var out_dir := "user://zoning_stress"


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_dir = str(args.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	pngs = int(args.get("pngs", "0"))
	if args.has("budgets"):
		budgets = JSON.parse_string(FileAccess.get_file_as_string(str(args.budgets)))
	var report: Dictionary
	if args.has("merge"):
		report = _merge(str(args.merge).split(","))
	else:
		var count := int(args.get("count", str(RUN)))
		var seed := int(args.get("seed", "1"))
		var idx := []
		if args.has("only"):
			idx = [int(args.only)]
		else:
			var shard: PackedStringArray = str(args.get("shard", "0/1")).split("/")
			for i in count:
				if i % int(shard[1]) == int(shard[0]):
					idx.append(i)
		report = run(seed, idx, args.has("only"))
	var json := JSON.stringify(report, "  ")
	FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE).store_string(json)
	var md := summary(report)
	FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE).store_string(md)
	print(md)
	var over := _over_budget(report)
	for o in over:
		print("OVER BUDGET: " + o)
	quit(1 if not over.is_empty() else 0)


func run(seed: int, idx: Array, verbose: bool) -> Dictionary:
	var report := {"seed": seed, "scenarios": 0, "lots": 0, "issues": {}, "families": {},
		"grid_lots": 0, "grid_rect": 0, "ms": 0}
	var t0 := Time.get_ticks_msec()
	for i in idx:
		var sc := scenario(seed, i)
		var res := play(sc)
		report.scenarios += 1
		report.lots += res.lots
		report.grid_lots += res.grid_lots
		report.grid_rect += res.grid_rect
		var fam: Dictionary = report.families.get(sc.family, {"scenarios": 0, "lots": 0})
		fam.scenarios += 1
		fam.lots += res.lots
		report.families[sc.family] = fam
		for kind in res.issues:
			var list: Array = res.issues[kind]
			var entry: Dictionary = report.issues.get(kind, {"scenarios": 0, "count": 0, "families": {}, "examples": []})
			entry.scenarios += 1
			entry.count += list.size()
			entry.families[sc.family] = int(entry.families.get(sc.family, 0)) + 1
			if entry.examples.size() < 6:
				entry.examples.append({"index": i, "family": sc.family, "at": list[0].at, "what": list[0].get("what", "")})
				if entry.examples.size() <= pngs:
					_draw(res.sim, list, out_dir.path_join("%s-%d.png" % [kind, i]))
			report.issues[kind] = entry
		if verbose:
			print(JSON.stringify(sc.log, "  "))
			for kind in res.issues:
				for p in res.issues[kind]:
					print("%s at %s %s" % [kind, str(p.at), p.get("what", "")])
			_draw(res.sim, res.issues.values().reduce(func(a, b): return a + b, []), out_dir.path_join("scenario-%d.png" % i))
		if report.scenarios % 100 == 0:
			print("%d scenarios, %d lots, %.0f s" % [report.scenarios, report.lots, (Time.get_ticks_msec() - t0) / 1000.0])
	report.ms = Time.get_ticks_msec() - t0
	return report


# --- Scenarios -------------------------------------------------------------

## One scenario, the same for the same seed and index: the roads to build
## and how to zone them.
func scenario(seed: int, i: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, i, "zoning"])
	var family: String = FAMILIES[i % FAMILIES.size()] if i < SMART_FROM else SMART_FAMILIES[i % SMART_FAMILIES.size()]
	return {"index": i, "family": family, "roads": _roads(family.trim_prefix("smart_"), rng), "rng": rng,
		# A third of scenarios have homes going up between clicks.
		"grow": rng.randf() < 0.35,
		# Half zone one kind only, so the click order can't matter.
		"one_zone": rng.randf() < 0.5,
		"log": [],
	}


static func _rot(p: Vector2, ang: float) -> Array:
	var q := p.rotated(ang)
	return [snappedf(q.x, 0.01), snappedf(q.y, 0.01)]


static func _road_cmd(a: Vector2, b: Vector2, type := 0, bend := 0.0) -> Dictionary:
	var mid := a.lerp(b, 0.5)
	var n := (b - a).orthogonal().normalized()
	var c := mid + n * bend
	return {"type": "build_road", "start": [a.x, a.y], "ctrl": [c.x, c.y], "end": [b.x, b.y], "road": type}


func _roads(family: String, rng: RandomNumberGenerator) -> Array:
	var cmds := []
	match family:
		"grid", "rotated_grid":
			var ang := 0.0 if family == "grid" else rng.randf_range(-PI / 2, PI / 2)
			var w := rng.randf_range(180, 420)
			var h := rng.randf_range(140, 300)
			cmds.append({"type": "build_grid", "a": _rot(Vector2.ZERO, ang), "b": _rot(Vector2(w, 0), ang),
				"c": _rot(Vector2(w, h), ang), "block": rng.randf_range(70, 160)})
		"odd_grid":
			# A grid filling odd land: a triangle, a pentagon, an L or a
			# skewed quadrilateral, as the grid tool draws any shape.
			var pts := []
			match rng.randi() % 4:
				0:
					pts = [Vector2(0, 0), Vector2(rng.randf_range(260, 400), 0), Vector2(rng.randf_range(0, 300), rng.randf_range(220, 340))]
				1:
					for k in 5:
						var a := TAU * k / 5 + rng.randf_range(-0.3, 0.3)
						pts.append(Vector2(cos(a), sin(a)) * rng.randf_range(150, 220))
				2:
					var w := rng.randf_range(240, 360)
					var h := rng.randf_range(200, 320)
					pts = [Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.45), Vector2(w * 0.5, h * 0.45), Vector2(w * 0.5, h), Vector2(0, h)]
				3:
					var sk := rng.randf_range(40, 140)
					pts = [Vector2(0, 0), Vector2(300, 0), Vector2(300 + sk, 220), Vector2(sk, 220)]
			cmds.append({"type": "build_grid_shape", "points": pts.map(func(p): return [p.x, p.y]), "block": rng.randf_range(80, 150)})
		"skew_cross":
			# A main street crossed by streets at odd angles.
			var len := rng.randf_range(300, 500)
			cmds.append(_road_cmd(Vector2(0, 0), Vector2(len, 0), rng.randi() % 2))
			var n := rng.randi_range(1, 3)
			for k in n:
				var x := len * (k + 1) / (n + 1) + rng.randf_range(-20, 20)
				var ang := rng.randf_range(0.45, 1.3) * (1 if rng.randf() < 0.5 else -1)
				var d := Vector2(cos(ang), sin(ang))
				cmds.append(_road_cmd(Vector2(x, 0) - d * rng.randf_range(100, 180), Vector2(x, 0) + d * rng.randf_range(100, 180)))
			if rng.randf() < 0.5:
				cmds.append(_road_cmd(Vector2(0, 110), Vector2(len, 110 + rng.randf_range(-40, 40))))
		"triangle":
			var a := Vector2(0, 0)
			var b := Vector2(rng.randf_range(220, 380), 0)
			var c := Vector2(rng.randf_range(-40, 300), rng.randf_range(160, 320))
			for e in [[a, b], [b, c], [c, a]]:
				var d: Vector2 = (e[1] - e[0]).normalized()
				# Streets run on a little past the corners, as real ones do.
				var over := rng.randf_range(0, 40)
				cmds.append(_road_cmd(e[0] - d * over, e[1] + d * over))
		"curves":
			var n := rng.randi_range(1, 3)
			for k in n:
				var y := k * rng.randf_range(80, 140)
				var len := rng.randf_range(250, 420)
				cmds.append(_road_cmd(Vector2(0, y), Vector2(len, y + rng.randf_range(-60, 60)), 0, rng.randf_range(-110, 110)))
			if rng.randf() < 0.7:
				var x := rng.randf_range(80, 220)
				cmds.append(_road_cmd(Vector2(x, -80), Vector2(x + rng.randf_range(-40, 40), n * 120 + 40)))
		"rounded":
			var r := rng.randf_range(25, 70)
			var w := rng.randf_range(220, 340)
			var h := rng.randf_range(140, 220)
			var pts := [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
			for k in 4:
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[(k + 1) % 4]
				var c: Vector2 = pts[(k + 2) % 4]
				var d1 := (b - a).normalized()
				var d2 := (c - b).normalized()
				var s0 := a + d1 * r
				var s1 := b - d1 * r
				cmds.append(_road_cmd(s0, s1))
				var e := b + d2 * r
				cmds.append({"type": "build_road", "start": [s1.x, s1.y], "ctrl": [b.x, b.y], "end": [e.x, e.y], "road": 0})
			if rng.randf() < 0.6:
				cmds.append(_road_cmd(Vector2(w / 2, 0), Vector2(w / 2, h)))
		"deep":
			# Two long streets far apart: deep blocks, flag lots or open
			# land behind.
			var gap := rng.randf_range(110, 320)
			var len := rng.randf_range(260, 460)
			cmds.append(_road_cmd(Vector2(0, 0), Vector2(len, 0)))
			cmds.append(_road_cmd(Vector2(0, gap), Vector2(len, gap)))
			var step := rng.randf_range(90, 200)
			var x := 0.0
			while x <= len + 1.0:
				cmds.append(_road_cmd(Vector2(x, 0), Vector2(x, gap)))
				x += step
		"t_junction":
			# Cross streets ending at a through street, from one side or
			# both, offset (real towns have many jogged T's).
			var len := rng.randf_range(300, 480)
			cmds.append(_road_cmd(Vector2(0, 0), Vector2(len, 0), rng.randi() % 3))
			var n := rng.randi_range(1, 3)
			for k in n:
				var x := len * (k + 1) / (n + 1)
				cmds.append(_road_cmd(Vector2(x, 0), Vector2(x, rng.randf_range(100, 200))))
				if rng.randf() < 0.5:
					var j := x + rng.randf_range(-40, 40)
					cmds.append(_road_cmd(Vector2(j, 0), Vector2(j, -rng.randf_range(100, 200))))
		"arterial":
			# A town grid with an avenue or boulevard through it.
			var w := rng.randf_range(240, 400)
			cmds.append({"type": "build_grid", "a": [0, 0], "b": [w, 0], "c": [w, 240], "block": rng.randf_range(80, 130)})
			var y := rng.randf_range(60, 180)
			cmds.append(_road_cmd(Vector2(-60, y), Vector2(w + 60, y + rng.randf_range(-20, 20)), 1 + rng.randi() % 2))
		"radial":
			var n := rng.randi_range(3, 6)
			var a := rng.randf_range(0, TAU)
			for k in n:
				a += TAU / n + rng.randf_range(-0.25, 0.25)
				cmds.append(_road_cmd(Vector2.ZERO, Vector2(cos(a), sin(a)) * rng.randf_range(160, 260)))
			if rng.randf() < 0.5:
				var r := rng.randf_range(90, 140)
				for k in 4:
					var a0 := TAU * k / 4
					var a1 := a0 + TAU / 4
					var am := (a0 + a1) / 2
					cmds.append({"type": "build_road", "start": [cos(a0) * r, sin(a0) * r],
						"ctrl": [cos(am) * r * 1.41, sin(am) * r * 1.41], "end": [cos(a1) * r, sin(a1) * r], "road": 0})
		"cul_de_sac":
			var len := rng.randf_range(300, 460)
			cmds.append(_road_cmd(Vector2(0, 0), Vector2(len, 0)))
			var n := rng.randi_range(1, 3)
			for k in n:
				var x := len * (k + 1) / (n + 1)
				var d := rng.randf_range(80, 220)
				cmds.append(_road_cmd(Vector2(x, 0), Vector2(x, d * (1 if k % 2 == 0 else -1))))
		"lanes":
			# Streets with an alley or gravel lane behind.
			var len := rng.randf_range(260, 420)
			var gap := rng.randf_range(55, 110)
			var lane := RoadStyle.Type.ALLEY if rng.randf() < 0.5 else RoadStyle.Type.GRAVEL
			cmds.append(_road_cmd(Vector2(0, 0), Vector2(len, 0)))
			cmds.append(_road_cmd(Vector2(0, gap), Vector2(len, gap), lane))
			if rng.randf() < 0.6:
				cmds.append(_road_cmd(Vector2(0, gap * 2), Vector2(len, gap * 2)))
			cmds.append(_road_cmd(Vector2(len / 2, -60), Vector2(len / 2, gap * 2 + 60)))
	return cmds


## Builds the scenario's roads, zones them step by step and scores the lots.
func play(sc: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = sc.rng
	var sim := _fresh_sim()
	for c in sc.roads:
		sim.apply(c)
	sim.tick()
	var issues := {}
	var cmds := _zoning(sim, sc, rng)
	var grown := 0
	for step in cmds:
		if step.type == "grow":
			for k in int(step.n):
				if sim._grow_one(k) != "":
					grown += 1
			sim.tick()
			continue
		if step.type == "smart":
			# Smart paint as the zone tool sends it: each planned street side
			# held, then the lots cut once.
			var plan := SmartZoning.plan(sim, int(step.seg), int(step.scope), step.kinds)
			for part in plan.parts:
				var cmd := {"type": "zone_frontage", "seg": part.seg, "side": part.side, "zone": part.zone, "hold": true}
				if part.span.size() == 2:
					cmd.span = part.span
				else:
					cmd.single = true
				sc.log.append(cmd)
				if not sim.apply(cmd):
					_add(issues, "script_error", {"at": [0, 0], "what": JSON.stringify(cmd)})
			sc.log.append({"type": "zone_done"})
			sim.apply({"type": "zone_done"})
			continue
		sc.log.append(step)
		if not sim.apply(step) and step.type != "zone_done":
			_add(issues, "script_error", {"at": [0, 0], "what": JSON.stringify(step)})
	sim.apply({"type": "zone_done"})
	_settle(sim)
	var res := score(sim, sc)
	_merge_issues(issues, res.issues)
	res.issues = issues
	# The same zoning (one kind, no homes between clicks) in reverse order
	# must give the same lots: a player can't know the "right" order.
	if sc.one_zone and grown == 0:
		var back := _fresh_sim()
		for c in sc.roads:
			back.apply(c)
		back.tick()
		var rev: Array = sc.log.duplicate()
		rev.reverse()
		for step in rev:
			back.apply(step)
		back.apply({"type": "zone_done"})
		_settle(back)
		var diff := _diff(sim, back)
		if not diff.is_empty():
			_add(res.issues, "click_order", {"at": diff[0], "what": "%d lots differ" % diff.size(), "lots": []})
	# A save and reload keeps every lot (multiplayer copies rely on it).
	if sc.index % 3 == 0:
		var copy := _fresh_sim()
		copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict(), "", false, true)))
		copy.tick()
		var diff := _diff(sim, copy)
		if not diff.is_empty():
			_add(res.issues, "save_reload", {"at": diff[0], "what": "%d lots differ" % diff.size()})
	res.sim = sim
	return res


static func _fresh_sim() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 1e12
	sim.replan_lots = 1 << 30
	sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	sim.demand[ZoneMap.Zone.COMMERCIAL] = 1.0
	sim.demand[ZoneMap.Zone.INDUSTRIAL] = 1.0
	# The scenarios are about lot shapes, laid out round the origin with no
	# county road in mind: bulldoze the section-line roads there, which lots
	# keep off on purpose (#462), so their blocked frontage isn't counted.
	for line in range(-2, 3):
		for seg in range(-2, 2):
			sim.county_removed["ns:%d:%d" % [line, seg]] = true
			sim.county_removed["ew:%d:%d" % [line, seg]] = true
	return sim


static func _settle(sim: CitySim) -> void:
	for k in 3:
		sim.tick()
	while sim._replan_at > sim.tick_count or sim._hold_until > sim.tick_count:
		sim.tick()


## The zoning commands, as a player gives them: clicks on block faces (some
## with Shift for both sides), drags along part of a street, a round brush in
## odd spots, now and then an erase, and homes going up between clicks.
func _zoning(sim: CitySim, sc: Dictionary, rng: RandomNumberGenerator) -> Array:
	if sc.family.begins_with("smart_"):
		sc.one_zone = false
		sc.grow = rng.randf() < 0.7
	var faces := []
	for id in sim.network.segments:
		for side in [-1, 1]:
			faces.append([id, side])
	faces.sort()
	# Shuffled with the scenario's own generator, so it's repeatable.
	for k in range(faces.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t = faces[k]
		faces[k] = faces[j]
		faces[j] = t
	var smart: bool = sc.family.begins_with("smart_")
	var take := maxi(1, int(faces.size() * (rng.randf_range(0.0, 0.5) if smart else rng.randf_range(0.4, 1.0))))
	var out := []
	var zone_of := func() -> int:
		if sc.one_zone:
			return ZoneMap.Zone.RESIDENTIAL
		var r := rng.randf()
		return ZoneMap.Zone.RESIDENTIAL if r < 0.6 else (ZoneMap.Zone.COMMERCIAL if r < 0.85 else ZoneMap.Zone.INDUSTRIAL)
	var dragging := false
	for k in take:
		var f: Array = faces[k]
		var r := rng.randf()
		var cmd := {"type": "zone_frontage", "seg": f[0], "side": f[1], "zone": zone_of.call()}
		if r < 0.12:
			cmd.both = true
		elif r < 0.3:
			var len := RoadNetwork.polyline_length(sim.network.sample_segment(f[0], 16))
			var a := rng.randf_range(0, len * 0.7)
			cmd.span = [snappedf(a, 0.1), snappedf(minf(len, a + rng.randf_range(20, len)), 0.1)]
		elif r < 0.36 and not sc.one_zone:
			var pts := sim.network.sample_segment(f[0], 16)
			var at := rng.randi() % pts.size()
			var p: Vector3 = pts[at]
			var d: Vector3 = (pts[mini(at + 1, pts.size() - 1)] - pts[maxi(at - 1, 0)]).normalized()
			var n: Vector3 = Vector3(-d.z, 0, d.x) * f[1] * rng.randf_range(8, 30)
			cmd = {"type": "paint_zone", "center": [snappedf(p.x + n.x, 0.1), snappedf(p.z + n.z, 0.1)],
				"radius": snappedf(rng.randf_range(8, 30), 0.1), "zone": zone_of.call()}
		elif r < 0.39 and not sc.one_zone:
			cmd.zone = ZoneMap.Zone.NONE
		# Drags: a few streets in one stroke, lots cut when it ends.
		if rng.randf() < 0.3 and cmd.type == "zone_frontage":
			cmd.hold = true
			dragging = true
		elif dragging:
			out.append({"type": "zone_done"})
			dragging = false
		out.append(cmd)
		if sc.grow and rng.randf() < 0.3:
			if dragging:
				out.append({"type": "zone_done"})
				dragging = false
			out.append({"type": "grow", "n": rng.randi_range(2, 8)})
	if smart:
		# Then Smart paint from one to three spots, homes going up between.
		if dragging:
			out.append({"type": "zone_done"})
		var segs := sim.network.segments.keys()
		segs.sort()
		for k in rng.randi_range(1, 3):
			var kinds := {ZoneMap.Zone.RESIDENTIAL: true, ZoneMap.Zone.COMMERCIAL: true}
			if rng.randf() < 0.25:
				kinds[ZoneMap.Zone.INDUSTRIAL] = true
			out.append({"type": "smart", "seg": segs[rng.randi() % segs.size()], "scope": rng.randi_range(1, 2), "kinds": kinds})
			if sc.grow:
				out.append({"type": "grow", "n": rng.randi_range(3, 10)})
	return out


# --- Scoring ---------------------------------------------------------------

## Scores every lot against the rules. Returns {issues, lots, grid_lots,
## grid_rect}; each issue entry is a list of {at, what, lots}.
func score(sim: CitySim, sc: Dictionary) -> Dictionary:
	var issues := {}
	var roads := []  # [a, b, half right-of-way, seg]
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id, 24)
		var half := RoadStyle.right_of_way_half(sim.network.segments[id].type)
		for k in pts.size() - 1:
			roads.append([Vector2(pts[k].x, pts[k].z), Vector2(pts[k + 1].x, pts[k + 1].z), half, id])
	var keys := sim.lots.keys()
	keys.sort()
	var grid_lots := 0
	var grid_rect := 0
	var square: bool = sc.family in SQUARE
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		var c: PackedVector2Array = lot.corners
		var at := LotPlanner._centroid(c)
		var hit := {"at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "lots": [key]}
		if _self_crossing(c):
			_add(issues, "bowtie", hit)
			continue
		var area := absf(LotPlanner._area(c))
		var zone := int(lot.get("plat_zone", ZoneMap.Zone.RESIDENTIAL))
		if Geometry2D.offset_polygon(c, -3.0).is_empty():
			_add(issues, "sliver", _what(hit, "%.0f m², %.1f m wide" % [area, lot.width]))
		elif not lot.flag and Geometry2D.offset_polygon(c, -2.5).size() > 1:
			_add(issues, "neck", hit)
		if area < 140.0:
			_add(issues, "tiny", _what(hit, "%.0f m²" % area))
		if not lot.flag and lot.width > 0.0 and lot.depth / lot.width > 6.0:
			_add(issues, "long_strip", _what(hit, "%.0f x %.0f m" % [lot.width, lot.depth]))
		# Real plats: shops and homes 30-50 m deep, 60 m at most; shops and
		# plants always on the street, never down a drive.
		if not lot.flag and zone != ZoneMap.Zone.INDUSTRIAL and lot.depth > 60.0:
			_add(issues, "too_deep", _what(hit, "%.0f m deep" % lot.depth))
		if lot.flag and zone != ZoneMap.Zone.RESIDENTIAL:
			_add(issues, "shop_behind", _what(hit, ZoneMap.NAMES[zone]))
		var hull := Geometry2D.convex_hull(c)
		if not lot.flag and area < absf(LotPlanner._area(hull)) * 0.8:
			_add(issues, "jagged", _what(hit, "%.0f%% of hull" % (100.0 * area / absf(LotPlanner._area(hull)))))
		# Road right-of-way under the lot, and frontage on any street.
		var box := LotPlanner._box(c)
		var mid := box.get_center()
		var reach := box.size.length() / 2.0 + 8.0
		var near := roads.filter(func(r): return Geometry2D.get_closest_point_to_segment(mid, r[0], r[1]).distance_to(mid) < reach + r[2])
		var on_road := 0.0
		for r in near:
			var strip := PackedVector2Array([r[0], r[1]])
			for q in Geometry2D.offset_polyline(strip, r[2] - 0.6, Geometry2D.JOIN_SQUARE, Geometry2D.END_BUTT):
				for x in Geometry2D.intersect_polygons(c, q):
					on_road += absf(LotPlanner._area(x))
		if on_road > 4.0:
			_add(issues, "on_road", _what(hit, "%.0f m² on the road" % on_road))
		var front := _frontage(c, near)
		if front < 4.0:
			_add(issues, "landlocked", _what(hit, "%.1f m on a street" % front))
		# Shape in the street's own frame (not the lot's, so a lot turned
		# off square to its street counts as odd too).
		var frame := _street_frame(sim, lot)
		var rect := _rectness(c, frame[0], frame[1])
		var odd := rect < 0.85
		if square and not lot.flag:
			grid_lots += 1
			if rect >= 0.97:
				grid_rect += 1
			elif not _forced(sim, lot, c, near, frame[0]):
				_add(issues, "grid_not_rect", _what(hit, "%.0f%% of its rectangle" % (rect * 100.0)))
		if odd and not lot.flag:
			if _forced(sim, lot, c, near, frame[0]):
				_add(issues, "odd_forced", _what(hit, "%.0f%%" % (rect * 100.0)))
			else:
				_add(issues, "odd_unforced", _what(hit, "%.0f%% of its rectangle" % (rect * 100.0)))
	_overlaps(sim, keys, issues)
	_depth_jumps(sim, keys, issues)
	_empty_frontage(sim, issues)
	_gaps(sim, roads, issues)
	return {"issues": issues, "lots": keys.size(), "grid_lots": grid_lots, "grid_rect": grid_rect}


static func _add(issues: Dictionary, kind: String, hit: Dictionary) -> void:
	if not issues.has(kind):
		issues[kind] = []
	issues[kind].append(hit)


static func _merge_issues(into: Dictionary, more: Dictionary) -> void:
	for k in more:
		for h in more[k]:
			_add(into, k, h)


static func _what(hit: Dictionary, what: String) -> Dictionary:
	var h := hit.duplicate()
	h.what = what
	return h


static func _self_crossing(c: PackedVector2Array) -> bool:
	var n := c.size()
	for i in n:
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var x = Geometry2D.segment_intersects_segment(c[i], c[(i + 1) % n], c[j], c[(j + 1) % n])
			if x != null:
				return true
	return false


## Metres of the lot's outline that lie along a street's edge.
static func _frontage(c: PackedVector2Array, near: Array) -> float:
	var total := 0.0
	for i in c.size():
		var a := c[i]
		var b := c[(i + 1) % c.size()]
		var n := maxi(1, ceili(a.distance_to(b)))
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			for r in near:
				if Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) < r[2] + 1.5:
					total += a.distance_to(b) / n
					break
	return total


## The street's direction at the lot (along, back), from its own segment.
static func _street_frame(sim: CitySim, lot: Dictionary) -> Array:
	var pts := sim.network.sample_segment(int(lot.seg), 48)
	var p := Vector2(lot.front.x, lot.front.z) if lot.front is Vector3 else LotPlanner._centroid(lot.corners)
	var best := INF
	var dir := Vector2(lot.dir.x, lot.dir.z)
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < best:
			best = d
			dir = (b - a).normalized()
	return [dir, dir.orthogonal()]


## Lot area over the rectangle around it, square to the street.
static func _rectness(c: PackedVector2Array, u: Vector2, v: Vector2) -> float:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in c:
		var q := Vector2(p.dot(u), p.dot(v))
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var box := (hi.x - lo.x) * (hi.y - lo.y)
	return absf(LotPlanner._area(c)) / box if box > 0.0 else 0.0


## Whether the land forces an odd shape here: its street bends along the lot,
## or another road near it runs at a skewed angle (not along or square).
static func _forced(sim: CitySim, lot: Dictionary, c: PackedVector2Array, near: Array, u: Vector2) -> bool:
	for r in near:
		var d: Vector2 = (r[1] - r[0]).normalized()
		var close := INF
		for p in c:
			close = minf(close, Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p))
		if close > r[2] + 10.0:
			continue
		var ang := rad_to_deg(absf(u.angle_to(d)))
		var off := fmod(ang, 90.0)
		if minf(off, 90.0 - off) > 6.0:
			return true
	return false


## Neighbouring lots along one street side whose depths differ a lot: a real
## block face has one depth, back to the same line.
static func _depth_jumps(sim: CitySim, keys: Array, issues: Dictionary) -> void:
	var faces := {}
	for k in keys:
		var l: Dictionary = sim.lots[k]
		if l.flag:
			continue
		var f := "%d:%d" % [l.seg, l.side]
		if not faces.has(f):
			faces[f] = []
		faces[f].append(k)
	for f in faces:
		var row: Array = faces[f]
		row.sort_custom(func(a, b): return sim.lots[a].at_frac < sim.lots[b].at_frac)
		for i in row.size() - 1:
			var a: Dictionary = sim.lots[row[i]]
			var b: Dictionary = sim.lots[row[i + 1]]
			if not LotPlanner._box(a.corners).grow(1.0).intersects(LotPlanner._box(b.corners)):
				continue
			var hi := maxf(a.depth, b.depth)
			var lo := minf(a.depth, b.depth)
			if lo > 0.0 and hi / lo > 1.8:
				var at := LotPlanner._centroid(a.corners)
				_add(issues, "depth_jump", {"at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "lots": [row[i], row[i + 1]],
					"what": "%.0f m next to %.0f m" % [hi, lo]})


static func _overlaps(sim: CitySim, keys: Array, issues: Dictionary) -> void:
	for i in keys.size():
		var a: Dictionary = sim.lots[keys[i]]
		var ba := LotPlanner._box(a.corners)
		for j in range(i + 1, keys.size()):
			var b: Dictionary = sim.lots[keys[j]]
			if not ba.intersects(LotPlanner._box(b.corners)):
				continue
			var over := 0.0
			for p in Geometry2D.intersect_polygons(a.corners, b.corners):
				over += absf(LotPlanner._area(p))
			if over > 4.0:
				var at := LotPlanner._centroid(a.corners)
				_add(issues, "overlap", {"at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "lots": [keys[i], keys[j]],
					"what": "%.0f m²" % over})


## Zoned frontage with no lot behind it: walks each zoned street side's
## survey lines (the planner's own) and looks 6 m back from the sidewalk.
static func _empty_frontage(sim: CitySim, issues: Dictionary) -> void:
	var lots := sim.lots.values()
	for id in sim.network.segments:
		for side in [-1, 1]:
			var s := sim.planner.side_survey(sim.network, id, side)
			if s.is_empty():
				continue
			var run := []
			var rays: Array = s.rays
			for k in rays.size() + 1:
				var empty := false
				var p := Vector2.ZERO
				if k < rays.size():
					var r: Array = rays[k]
					# Not where the street ends: corners belong to whichever
					# street holds them.
					if r[3] >= 12.0 and r[0] > 15.0 and r[0] < s.len - 15.0:
						var probe: Vector2 = r[1] + r[2] * LotPlanner.ZONE_PROBE
						if sim.zones.zone_at(Vector3(probe.x, 0, probe.y)) != ZoneMap.Zone.NONE:
							p = r[1] + r[2] * 6.0
							empty = not lots.any(func(l): return Geometry2D.is_point_in_polygon(p, l.corners))
				if empty:
					run.append(p)
				elif not run.is_empty():
					if run.size() >= 4:  # 12 m or more: a lot's worth
						var at: Vector2 = run[run.size() / 2]
						_add(issues, "empty_frontage", {"at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)],
							"what": "%d m on seg %d side %d" % [run.size() * LotPlanner.RAY_STEP, id, side], "lots": []})
					run = []


## Unused land between lots: rasterizes lots and roads, then finds empty
## cells with a lot close on both sides, in clusters over GAP_MIN.
static func _gaps(sim: CitySim, roads: Array, issues: Dictionary) -> void:
	if sim.lots.is_empty():
		return
	var box := Rect2()
	var first := true
	for l in sim.lots.values():
		var b := LotPlanner._box(l.corners)
		box = b if first else box.merge(b)
		first = false
	box = box.grow(CELL * 2)
	var w := int(box.size.x / CELL) + 1
	var h := int(box.size.y / CELL) + 1
	var grid := PackedInt32Array()
	grid.resize(w * h)
	var cell_at := func(x: int, y: int) -> Vector2:
		return box.position + Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
	for r in roads:
		var rb := Rect2(r[0], Vector2.ZERO).expand(r[1]).grow(r[2])
		for y in range(maxi(0, int((rb.position.y - box.position.y) / CELL)), mini(h, int((rb.end.y - box.position.y) / CELL) + 1)):
			for x in range(maxi(0, int((rb.position.x - box.position.x) / CELL)), mini(w, int((rb.end.x - box.position.x) / CELL) + 1)):
				var p: Vector2 = cell_at.call(x, y)
				if Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) <= r[2]:
					grid[y * w + x] = -1
	var n := 1
	for l in sim.lots.values():
		var lb := LotPlanner._box(l.corners)
		for y in range(maxi(0, int((lb.position.y - box.position.y) / CELL)), mini(h, int((lb.end.y - box.position.y) / CELL) + 1)):
			for x in range(maxi(0, int((lb.position.x - box.position.x) / CELL)), mini(w, int((lb.end.x - box.position.x) / CELL) + 1)):
				if grid[y * w + x] == 0 and Geometry2D.is_point_in_polygon(cell_at.call(x, y), l.corners):
					grid[y * w + x] = n
		n += 1
	var normals := sim.lots.values().map(func(l): return Vector2(l.normal.x, l.normal.z))
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	var gap := PackedByteArray()
	gap.resize(w * h)
	for y in h:
		for x in w:
			if grid[y * w + x] != 0:
				continue
			# Land the player zoned but no lot took, or a strip left between
			# the backs of two rows of lots (they should meet mid-block).
			var p: Vector2 = cell_at.call(x, y)
			var zoned := sim.zones.zone_at(Vector3(p.x, 0, p.y)) != ZoneMap.Zone.NONE
			for d in dirs:
				var a := _hits_lot(grid, w, h, x, y, d)
				var b := _hits_lot(grid, w, h, x, y, -d)
				if a > 0 and b > 0:
					if (normals[a - 1] as Vector2).dot(normals[b - 1]) < -0.5:
						gap[y * w + x] = 1
						break
					if zoned:
						gap[y * w + x] = 3
	# Clusters of gap cells.
	for y in h:
		for x in w:
			var kind := gap[y * w + x]
			if kind != 1 and kind != 3:
				continue
			var stack := [Vector2i(x, y)]
			gap[y * w + x] = kind + 1
			var cells := []
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				cells.append(q)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var o: Vector2i = q + d
					if o.x >= 0 and o.y >= 0 and o.x < w and o.y < h and gap[o.y * w + o.x] == kind:
						gap[o.y * w + o.x] = kind + 1
						stack.append(o)
			var area := cells.size() * CELL * CELL
			if area >= GAP_MIN:
				var mid: Vector2 = cell_at.call(cells[cells.size() / 2].x, cells[cells.size() / 2].y)
				_add(issues, "gap_backs" if kind == 1 else "gap_sides", {"at": [snappedf(mid.x, 0.1), snappedf(mid.y, 0.1)], "what": "%.0f m²" % area, "lots": []})


## The lot (1-based) first met from a cell going one way, or 0 if a road or
## nothing comes first.
static func _hits_lot(grid: PackedInt32Array, w: int, h: int, x: int, y: int, d: Vector2i) -> int:
	for k in range(1, GAP_REACH + 1):
		var px := x + d.x * k
		var py := y + d.y * k
		if px < 0 or py < 0 or px >= w or py >= h:
			return 0
		var v := grid[py * w + px]
		if v != 0:
			return maxi(v, 0)
	return 0


## Where two towns' lots differ: centres of lots in one and not the other.
static func _diff(a: CitySim, b: CitySim) -> Array:
	var sa := _shapes(a)
	var sb := _shapes(b)
	var out := []
	for k in sa:
		if not sb.has(k):
			out.append(sa[k])
	for k in sb:
		if not sa.has(k):
			out.append(sb[k])
	return out


static func _shapes(sim: CitySim) -> Dictionary:
	var out := {}
	for l in sim.lots.values():
		var at := LotPlanner._centroid(l.corners)
		var key := "%d,%d,%d" % [roundi(at.x), roundi(at.y), roundi(absf(LotPlanner._area(l.corners)) / 10.0)]
		out[key] = [snappedf(at.x, 0.1), snappedf(at.y, 0.1)]
	return out


# --- Reports ---------------------------------------------------------------

func summary(report: Dictionary) -> String:
	var kinds: Array = report.issues.keys()
	kinds.sort_custom(func(a, b): return report.issues[a].scenarios > report.issues[b].scenarios)
	var s := "# Zoning stress test\n\n%d scenarios, %d lots, %.0f s (seed %s).\n\n" % [
		report.scenarios, report.lots, report.ms / 1000.0, str(report.seed)]
	if report.grid_lots > 0:
		s += "Square streets: %.1f%% of %d lots are plain rectangles (rule 3).\n\n" % [
			100.0 * report.grid_rect / report.grid_lots, report.grid_lots]
	s += "| Problem | Rule | Scenarios | Times | Most in | Example |\n|---|---|---|---|---|---|\n"
	for k in kinds:
		var e: Dictionary = report.issues[k]
		var fams := (e.families as Dictionary).keys()
		fams.sort_custom(func(a, b): return e.families[a] > e.families[b])
		var ex: Dictionary = e.examples[0] if not e.examples.is_empty() else {}
		s += "| %s: %s | %s | %d (%.0f%%) | %d | %s | --only=%d at %s %s |\n" % [k, ISSUES.get(k, ["", ""])[1],
			ISSUES.get(k, ["?"])[0], e.scenarios, 100.0 * e.scenarios / maxi(1, report.scenarios), e.count,
			", ".join(fams.slice(0, 3)), int(ex.get("index", -1)), str(ex.get("at", "")), str(ex.get("what", ""))]
	return s


func _merge(files: PackedStringArray) -> Dictionary:
	var out := {"seed": 0, "scenarios": 0, "lots": 0, "issues": {}, "families": {}, "grid_lots": 0, "grid_rect": 0, "ms": 0}
	for f in files:
		var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
		out.seed = r.seed
		for k in ["scenarios", "lots", "grid_lots", "grid_rect"]:
			out[k] += int(r[k])
		out.ms = maxf(out.ms, r.ms)
		for fam in r.families:
			var e: Dictionary = out.families.get(fam, {"scenarios": 0, "lots": 0})
			e.scenarios += int(r.families[fam].scenarios)
			e.lots += int(r.families[fam].lots)
			out.families[fam] = e
		for k in r.issues:
			var src: Dictionary = r.issues[k]
			var e: Dictionary = out.issues.get(k, {"scenarios": 0, "count": 0, "families": {}, "examples": []})
			e.scenarios += int(src.scenarios)
			e.count += int(src.count)
			for fam in src.families:
				e.families[fam] = int(e.families.get(fam, 0)) + int(src.families[fam])
			e.examples = (e.examples + src.examples).slice(0, 6)
			out.issues[k] = e
	return out


## Problems seen in more scenarios than the budget allows (per 1000).
func _over_budget(report: Dictionary) -> Array:
	var over := []
	for k in budgets:
		if k.begins_with("_"):
			continue
		var limit: float = float(budgets[k]) * report.scenarios / RUN
		var seen := int(report.issues.get(k, {}).get("scenarios", 0))
		if seen > ceili(limit):
			over.append("%s in %d scenarios, budget %d" % [k, seen, ceili(limit)])
	return over


## The plat with the problem lots outlined in red and problem spots marked.
func _draw(sim: CitySim, hits: Array, path: String) -> void:
	var img: Image = load("res://tools/lot_map.gd").render(sim)
	var box := Rect2()
	var first := true
	for id in sim.network.segments:
		for p in sim.network.sample_segment(id, 16):
			var q := Vector2(p.x, p.z)
			box = Rect2(q, Vector2.ZERO) if first else box.expand(q)
			first = false
	box = box.grow(70.0)
	var sc: float = load("res://tools/lot_map.gd").SCALE
	for h in hits:
		for key in h.get("lots", []):
			if not sim.lots.has(key):
				continue
			var c: PackedVector2Array = sim.lots[key].corners
			for i in c.size():
				for o in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]:
					_line(img, (c[i] - box.position) * sc + o, (c[(i + 1) % c.size()] - box.position) * sc + o, Color.RED)
		var at := (Vector2(h.at[0], h.at[1]) - box.position) * sc
		for d in range(-6, 7):
			_dot(img, at + Vector2(d, d), Color.MAGENTA)
			_dot(img, at + Vector2(d, -d), Color.MAGENTA)
	img.save_png(path)


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(a.distance_to(b), 1.0))
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), col)


static func _dot(img: Image, p: Vector2, col: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
		img.set_pixel(int(p.x), int(p.y), col)
