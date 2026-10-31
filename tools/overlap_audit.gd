extends SceneTree
## The overlap auditor (Nathan, 2026-10-29: "railroad tracks running right
## through the city like they're just a part of the ground. They run right
## underneath the buildings. I also noticed street signs in the middle of
## driveways. There seems to be some challenge with maybe spatial
## recognition ... We need to get good at it though because we haven't yet
## implemented things like bus stops and items that will need to
## immediately make changes to the immediate environment like adjustments
## to the curb.")
##
## This tool is the facts step. It builds a town headless, collects what
## stands on the ground as 2D footprints (GroundFootprints.collect: from the
## sim's data and the builders' own plans, never from meshes; where each
## comes from is in GroundFootprints.SRC), and checks every pair of kinds
## that must never overlap (GroundMap.PAIRS, the same rules the ground map
## answers by). It changes nothing in the game. Its own pair search is kept
## apart from the ground map's on purpose: tests/test_ground_map.gd checks
## the two find the same clashes.
##
## Run headless only, with HOME set to a scratch folder:
##   HOME=/tmp/x godot --headless -s tools/overlap_audit.gd -- OUT_DIR [--towns=look_round,perf_big,county]
## Towns: look_round (PerfTown big, 150 warm ticks, the look round's mixed
## tiers and trash), perf_big (PerfTown big as built), county (PerfTown small
## grown over the real county map where a railroad runs), small and
## county_small (for the test). Writes OUT_DIR/overlap_report.json and
## OUT_DIR/overlap_report.md.
##
## tests/test_overlaps.gd runs the audit on a small town and fails on any
## new clash in the "never" pairs.

const OUT_DEFAULT := "."
## Metres of a grid cell for the pair search.
const CELL := 24.0
const MIN_AREA_DEFAULT := GroundMap.MIN_AREA_DEFAULT
const CROSSING_REACH := GroundMap.CROSSING_REACH
const PAIRS := GroundMap.PAIRS
const ALLOWED := GroundMap.ALLOWED
const MIN_AREA := GroundMap.MIN_AREA
const SRC := GroundFootprints.SRC

var _out := OUT_DEFAULT


func _initialize() -> void:
	if not _throwaway_home():
		printerr("overlap_audit: refusing to run: the user folder is %s. Set HOME to a scratch folder." % OS.get_user_data_dir())
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(_out)
	var towns := ["look_round", "perf_big", "county"]
	for a in args:
		if a.begins_with("--towns="):
			towns = Array(a.trim_prefix("--towns=").split(","))
	var report := {"date": Time.get_date_string_from_system(), "pairs": PAIRS.map(func(p): return {"a": p[0], "b": p[1],
		"rule": p[2], "visible": p[3], "why": p[4]}), "allowed": ALLOWED, "src": SRC, "towns": {}}
	for name in towns:
		var t0 := Time.get_ticks_msec()
		print("overlap_audit: building town %s" % name)
		var sim := town(name)
		var t1 := Time.get_ticks_msec()
		var res := audit(sim)
		res.build_s = (t1 - t0) / 1000.0
		res.audit_s = (Time.get_ticks_msec() - t1) / 1000.0
		var vf := FileAccess.open(_out.path_join("overlap_views_%s.json" % name), FileAccess.WRITE)
		vf.store_string(JSON.stringify(res.views))
		vf.close()
		res.erase("views")
		report.towns[name] = res
		print("overlap_audit: %s: %d buildings, %d shapes, %d never-clashes (%.0f s build, %.0f s audit)" % [name,
			sim.buildings.size(), int(res.shapes_total), int(res.never_total), res.build_s, res.audit_s])
		for k in res.ranked:
			print("   %-44s %6d  vis %d" % [k, int(res.counts[k].count), int(res.counts[k].visible)])
	var f := FileAccess.open(_out.path_join("overlap_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	var md := FileAccess.open(_out.path_join("overlap_report.md"), FileAccess.WRITE)
	md.store_string(markdown(report))
	md.close()
	print("overlap_audit: wrote %s" % _out.path_join("overlap_report.json"))
	quit(0)


static func _throwaway_home() -> bool:
	var dir := OS.get_user_data_dir().replace("\\", "/")
	for p in ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]:
		if dir.begins_with(p):
			return true
	return "/scratchpad/" in dir or "/scratch/" in dir


# ------------------------------------------------------------------ towns

## A town by name (see the header). County towns sit on the real county map
## where a railroad runs, with the county lines on (as the desktop game has
## them: main.gd sets sim.county_rail = CountyRail.drawn()).
static func town(name: String) -> CitySim:
	var sim := CitySim.new()
	sim.county_rail = true
	match name:
		"county", "county_small":
			var c: Dictionary = CountyTrains.corridors()[0]
			sim.terrain_offset = CountyTrains._at(c, 9000.0)
			PerfTown.build(sim, "small")
			_mixed_town(sim)
			_controls(sim)
		"small":
			PerfTown.build(sim, "small")
			_mixed_town(sim)
			_controls(sim)
		"perf_big":
			PerfTown.build(sim, "big")
		"look_round":
			PerfTown.build(sim, "big")
			sim.require_utilities = false
			for i in 150:  # look_round.gd WARM_TICKS
				sim.tick()
			_mixed_town(sim)
		_:
			PerfTown.build(sim, name)
	sim.county_trains.tick(sim)
	return sim


## Signals at the four 4-way junctions nearest the middle of town, and a No
## Left Turn on one approach at each of the next four (the player's tools:
## TrafficSim.set_rule, set_lane_rule), so their poles and posts are audited.
static func _controls(sim: CitySim) -> void:
	var fours := []
	for n in sim.network.nodes:
		if sim.network.segments_at(n).size() == 4:
			var p: Vector3 = sim.network.nodes[n]
			fours.append([Vector2(p.x, p.z).length(), n])
	fours.sort()
	for i in mini(8, fours.size()):
		var n: int = fours[i][1]
		if i < 4:
			sim.traffic.set_rule(n, TrafficSim.Rule.SIGNAL)
		else:
			var segs: Array = sim.network.segments_at(n)
			segs.sort()
			sim.traffic.set_lane_rule(n, segs[0], true, [], i % 2 == 0)


## The look round's mixed tiers (tools/look_round.gd _mixed_town): each
## built lot set to the middle of its 80 m square's tier, trash on the two
## streets nearest shot 01.
static func _mixed_town(sim: CitySim) -> void:
	var lr = load("res://tools/look_round.gd")
	var at: Array = Balance.CARE_TIERS
	var bands := [at[0] * 0.5, (at[0] + at[1]) * 0.5, (at[1] + at[2]) * 0.5, (at[2] + at[3]) * 0.5, (at[3] + 1.0) * 0.5]
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var t: int = lr.town_tier(sim.lots[key].pos)
		sim.care.cond[key] = bands[t + 2]
		sim.care.tier[key] = t
	var want := Vector2(-280.0, -250.0)
	var near := []
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id)
		var mid := pts[pts.size() / 2]
		near.append([Vector2(mid.x, mid.z).distance_to(want), id])
	near.sort()
	for i in mini(2, near.size()):
		sim.hubs.trash[near[i][1]] = Balance.GARBAGE_PILE_LB * 1.5


# ------------------------------------------------------------------ audit

## The whole audit of a town: {shapes: {kind: n}, counts: {pair: {...}},
## ranked: [pair keys, most first], never_total, worst: [10 worst]}.
## `extra`: more shapes ([cat, what, owner key, polygon]), for the test to
## plant a clash and see it caught.
static func audit(sim: CitySim, extra := []) -> Dictionary:
	var shapes := GroundFootprints.collect(sim)
	for e in extra:
		GroundFootprints._add(shapes, e[0], e[1], e[2], e[3])
	for i in shapes.size():
		shapes[i].id = i
	var by_kind := {}
	for s in shapes:
		var k: String = s.cat
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(s)
	var grids := {}
	for k in by_kind:
		grids[k] = _grid(by_kind[k])
	var crossings := []
	for x in sim.all_crossings():
		crossings.append(Vector2(x.pos.x, x.pos.z))
	var counts := {}
	var worst_all := []
	var shape_counts := {}
	for s in shapes:
		var sk := _skey(s)
		shape_counts[sk] = int(shape_counts.get(sk, 0)) + 1
	for p in PAIRS:
		var a: String = p[0]
		var b_full: String = p[1]
		var other_only := b_full.ends_with("*other")
		var b := b_full.trim_suffix("*other")
		var min_area: float = MIN_AREA.get(a + "|" + b_full, MIN_AREA_DEFAULT)
		if not by_kind.has(a) or not by_kind.has(b):
			continue
		var seen := {}
		for sa in by_kind[a]:
			for ib in _near(grids[b], sa.box):
				var sb: Dictionary = by_kind[b][ib]
				if sa.id == sb.id or (a == b and seen.has([sb.id, sa.id])):
					continue
				if (other_only or a == b) and sa.key != "" and sa.key == sb.key:
					continue
				if not sa.box.intersects(sb.box):
					continue
				var hit := GroundMap.overlap(sa.poly, sb.poly)
				if hit[0] < min_area:
					continue
				seen[[sa.id, sb.id]] = true
				var at: Vector2 = hit[1]
				var allowed := false
				if a == "rail_bed" and b in ["road", "sidewalk_line", "curb_ramp", "crosswalk"]:
					for c in crossings:
						if c.distance_to(at) < CROSSING_REACH:
							allowed = true
							break
				var key := "%s vs %s" % [_skey(sa), _skey(sb)]
				if not counts.has(key):
					counts[key] = {"rule": p[2], "visible": p[3], "why": p[4], "count": 0, "allowed": 0, "worst": [],
						"src_a": SRC.get(_skey(sa), SRC.get(a, "")), "src_b": SRC.get(_skey(sb), SRC.get(b, ""))}
				var row: Dictionary = counts[key]
				if allowed:
					row.allowed += 1
					continue
				row.count += 1
				var frac: float = hit[0] / maxf(minf(GroundMap.area(sa.poly), GroundMap.area(sb.poly)), 0.01)
				var ex := {"score": snappedf(frac * float(p[3]), 0.001), "area_m2": snappedf(hit[0], 0.01),
					"x": snappedf(at.x, 0.1), "z": snappedf(at.y, 0.1),
					"region_x": snappedf(at.x + sim.terrain_offset.x, 0.1), "region_z": snappedf(at.y + sim.terrain_offset.y, 0.1),
					"a": _desc(sa), "b": _desc(sb), "pair": key}
				_keep(row.worst, ex, 5)
				if p[2] == "never":
					_keep(worst_all, ex, 10)
	var ranked := counts.keys().filter(func(k): return counts[k].count > 0)
	ranked.sort_custom(func(x, y): return counts[x].count * counts[x].visible > counts[y].count * counts[y].visible)
	var never := 0
	for k in counts:
		if counts[k].rule == "never":
			never += counts[k].count
	# Everything within 25 m of each pair's worst clash, to draw a map of it.
	var views := []
	for k in ranked:
		var w: Dictionary = counts[k].worst[0]
		var area := Rect2(Vector2(w.x, w.z) - Vector2(25.0, 25.0), Vector2(50.0, 50.0))
		var near := []
		for s in shapes:
			if s.box.intersects(area):
				near.append({"kind": _skey(s), "owner": s.key, "poly": Array(s.poly).map(func(v): return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)])})
		views.append({"pair": k, "x": w.x, "z": w.z, "shapes": near})
	return {"shapes": shape_counts, "shapes_total": shapes.size(), "counts": counts, "ranked": ranked,
		"never_total": never, "worst": worst_all, "terrain_offset": [sim.terrain_offset.x, sim.terrain_offset.y],
		"buildings": sim.buildings.size(), "lots": sim.lots.size(), "notes": _notes(sim), "views": views}


## Counts of never-clashes by pair key ("a:what vs b:what"), for the test.
static func never_counts(res: Dictionary) -> Dictionary:
	var out := {}
	for k in res.counts:
		if res.counts[k].rule == "never" and res.counts[k].count > 0:
			out[k] = int(res.counts[k].count)
	return out


static func _notes(sim: CitySim) -> Array:
	var out := []
	out.append("hydrants: none on streets (only subdivision_works_view.gd and civic_builder.gd draw any)")
	if sim.buses.stops.is_empty():
		out.append("bus stops: none in this town")
	return out


static func _skey(s: Dictionary) -> String:
	return s.cat + ":" + s.what if s.cat in ["post", "rail_bed"] else s.cat


static func _desc(s: Dictionary) -> Dictionary:
	return {"kind": _skey(s), "what": s.what, "owner": s.key, "src": SRC.get(_skey(s), SRC.get(s.cat, ""))}


static func _keep(list: Array, ex: Dictionary, n: int) -> void:
	list.append(ex)
	list.sort_custom(func(x, y): return x.score > y.score or (x.score == y.score and x.area_m2 > y.area_m2))
	if list.size() > n:
		list.resize(n)


static func _grid(list: Array) -> Dictionary:
	var g := {}
	for i in list.size():
		var box: Rect2 = list[i].box
		for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var c := Vector2i(cx, cz)
				if not g.has(c):
					g[c] = []
				g[c].append(i)
	return g


static func _near(g: Dictionary, box: Rect2) -> Array:
	var out := {}
	for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			for i in g.get(Vector2i(cx, cz), []):
				out[i] = true
	return out.keys()


# ------------------------------------------------------------------ report

static func markdown(report: Dictionary) -> String:
	var s := "# Overlap audit (%s)\n\n" % report.date
	s += "Built by tools/overlap_audit.gd. Footprints come from the sim and the builders' plans, not meshes.\n"
	s += "Rank = count x how visible (1-5). \"never\" pairs fail tests/test_overlaps.gd if they grow.\n\n"
	for name in report.towns:
		var t: Dictionary = report.towns[name]
		s += "## Town: %s\n\n%d buildings, %d lots, %d shapes; %d never-clashes. Built in %.0f s, audited in %.0f s. Terrain offset %s.\n\n" % [
			name, int(t.buildings), int(t.lots), int(t.shapes_total), int(t.never_total), t.build_s, t.audit_s, str(t.terrain_offset)]
		s += "| Clash | Rule | Count | Visible | Worst place (x, z) | Placed by (a) | Placed by (b) |\n|---|---|---|---|---|---|---|\n"
		for k in t.ranked:
			var row: Dictionary = t.counts[k]
			var w: Dictionary = row.worst[0] if not row.worst.is_empty() else {}
			s += "| %s | %s | %d | %d | %s | %s | %s |\n" % [k, row.rule, int(row.count), int(row.visible),
				"(%.1f, %.1f)" % [w.x, w.z] if not w.is_empty() else "", row.src_a, row.src_b]
		var allowed := []
		for k in t.counts:
			if t.counts[k].allowed > 0:
				allowed.append("%s: %d" % [k, int(t.counts[k].allowed)])
		if not allowed.is_empty():
			s += "\nAllowed (at grade crossings): " + ", ".join(allowed) + "\n"
		s += "\n### 10 worst\n\n| # | Clash | Area m2 | x, z (town) | region x, z | a (owner) | b (owner) |\n|---|---|---|---|---|---|---|\n"
		var i := 1
		for w in t.worst:
			s += "| %d | %s | %.2f | %.1f, %.1f | %.0f, %.0f | %s (%s) | %s (%s) |\n" % [i, w.pair, w.area_m2, w.x, w.z,
				w.region_x, w.region_z, w.a.what, w.a.owner, w.b.what, w.b.owner]
			i += 1
		s += "\nShapes: %s\n\nNotes: %s\n\n" % [JSON.stringify(t.shapes), "; ".join(t.notes)]
	s += "## Pairs that may overlap\n\n"
	for a in report.allowed:
		s += "- %s over %s: %s\n" % a
	return s
