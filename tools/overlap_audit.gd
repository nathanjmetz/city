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
## The game has no shared "this ground is taken" map: each feature places
## its own things and checks only some of the others. This tool is the facts
## step. It builds a town headless, collects what stands on the ground as 2D
## footprints (world x/z polygons) from the sim's data and the builders' own
## plans (never from meshes), and checks every pair of kinds that must never
## overlap (PAIRS). It changes nothing in the game.
##
## Where a footprint comes from (file and function) is in SRC; a few are
## worked out here the way their view works them out, because the view
## keeps its result only inside its drawing (noted "mirrors").
##
## Corners cut (each can make a count a little off, none hides a kind):
## the mirrored stop, yield, No Turn and signal posts can drift from their
## view if it changes (junction_view.gd _rebuild_all; where they slide off
## drives is shared: JunctionView._post_spot); a car out on the drive is
## counted for every garage whose drive is long enough (the game draws two
## cars in three there); a duplex's curb cut is taken as 3 m wide; streets
## are straight strips to the node (no curb-return pavement); a tree trunk
## is 0.5 m square. Ramps, crosswalks and drives' curb cuts are read here
## from the junction plans, the house plans and what the builders draw, not
## from CurbClaims, so what the claims miss is still caught.
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
## A clash is an overlap of at least this many square metres (per pair,
## MIN_AREA overrides): touching edges and rounding don't count.
const MIN_AREA_DEFAULT := 0.02
## An overlap of rail with a road within this many metres of a grade
## crossing is the crossing itself (allowed).
const CROSSING_REACH := 14.0
## Half widths and sizes (metres).
const RAIL_HALF := 2.3  # ballast shoulder (RailView._ballast: 1.6 top, 2.3 shoulder)
const POST := {"stop_sign": 0.15, "yield_sign": 0.15, "no_turn_sign": 0.15, "street_name": 0.15,
	"signal_pole": 0.25, "streetlight": 0.25, "utility_pole": 0.2, "mailbox": 0.25, "bus_stop": 0.2}
const TRUNK := 0.25
const WALK_CENTRE_HALF := 0.3  # the line people walk along a sidewalk, +-0.3 m
const STALL := Vector2(2.5, 5.0)
const CAR := Vector2(1.9, 4.5)

## Who places each kind of thing (file and function).
const SRC := {
	"road": "scripts/roads/road_view.gd _rebuild_all (RoadMesh.street; RoadStyle.half_width)",
	"sidewalk_line": "scripts/roads/road_mesh.gd _town (sidewalk hw+curb+parkway .. +1.5 m)",
	"curb_ramp": "scripts/roads/junction.gd _ramp / _diagonal_ramp (ramps())",
	"crosswalk": "scripts/roads/junction_marks.gd paint; plain corners: scripts/traffic/junction_view.gd _markings",
	"rail_bed:county": "scripts/terrain/county_rail.gd routes (drawn by county_rail_view.gd _build)",
	"rail_bed:town": "scripts/sim/rail.gd pieces (drawn by scripts/rail/rail_view.gd)",
	"lot": "scripts/sim/lot_planner.gd plan/_lot, kept by scripts/sim/city_sim.gd _plan_lots/_lot_blocked",
	"building": "scripts/buildings/building_view.gd _draw/build_for (HouseBuilder.last_masses)",
	"public_site": "scripts/sim/services.gd footprint, scripts/sim/warehouses.gd corners",
	"drive": "scripts/art/house_builder.gd _yard (drive_x, drive_w); others scripts/sim/site_layout.gd for_building cut_x",
	"curb_cut": "scripts/art/house_builder.gd _yard (drive across the parkway); others site_layout.gd cut_x",
	"front_walk": "scripts/art/house_builder.gd _yard (h.walk: straight or L to the drive)",
	"parking_stall": "scripts/sim/site_layout.gd for_building spots (stall)",
	"dock": "scripts/sim/site_layout.gd factory spots (bay)",
	"post:stop_sign": "scripts/traffic/junction_view.gd _rebuild_all (stop posts; mirrored here)",
	"post:yield_sign": "scripts/traffic/junction_view.gd _rebuild_all (yield posts; mirrored here)",
	"post:no_turn_sign": "scripts/traffic/junction_view.gd _rebuild_all (R3-1/R3-2 posts; mirrored here)",
	"post:signal_pole": "scripts/traffic/junction_view.gd _rebuild_all (signal poles; mirrored here)",
	"post:street_name": "scripts/roads/street_sign_view.gd _corner",
	"post:streetlight": "scripts/art/street_lights.gd place",
	"post:utility_pole": "scripts/roads/pole_line.gd place (runs: road_view.gd _pole_runs/_pole_key/_pole_blocked)",
	"post:mailbox": "scripts/sim/curb_claims.gd mailbox_at (drawn by scripts/mail/mail_view.gd _mailboxes)",
	"post:bus_stop": "scripts/transit/bus_net.gd _place_stop, bus_view.gd _draw_stops",
	"tree_trunk": "scripts/art/house_builder.gd _yard_trees/_street_trees (BuildingView.trees_of)",
	"prop": "scripts/state/lot_state.gd items/_free (StateView._place)",
	"drive_car": "scripts/traffic/traffic_view.gd _out_front/_out_pick (mirrored here)",
	"garage_apron": "scripts/art/house_builder.gd garage DoorLog.add -> door_log.gd placed",
}

## Pairs that must never overlap: [kind a, kind b, rule, how visible (1-5),
## why]. "never" pairs fail the test; "watch" pairs are counted only.
## Kinds "post" and "rail_bed" are split by what they are (post:stop_sign...).
## A kind ending in "*other" checks only things on other lots.
const PAIRS := [
	["rail_bed", "building", "never", 5, "track running under a building"],
	["rail_bed", "public_site", "never", 5, "track through a school, warehouse or service yard"],
	["rail_bed", "lot", "never", 4, "a lot cut across the track: whatever grows there stands on it"],
	["rail_bed", "road", "never", 4, "track through pavement with no grade crossing"],
	["rail_bed", "drive", "never", 3, "track across a driveway"],
	["rail_bed", "parking_stall", "never", 3, "track through a parking lot"],
	["rail_bed", "tree_trunk", "never", 2, "a tree growing on the ballast"],
	["rail_bed", "prop", "never", 2, "a yard prop on the ballast"],
	["rail_bed", "post", "never", 3, "a pole or sign on the ballast"],
	["building", "building*other", "never", 5, "two buildings in one place"],
	["building", "road", "never", 5, "a building on the street"],
	["building", "sidewalk_line", "never", 4, "a building across the sidewalk"],
	["building", "public_site", "never", 4, "a building inside a public site"],
	["building", "drive*other", "never", 3, "a neighbour's drive under a building"],
	["building", "parking_stall*other", "never", 3, "a neighbour's parking under a building"],
	["post", "drive", "never", 4, "a sign or pole in a driveway"],
	["post", "curb_cut", "never", 4, "a sign or pole in a curb cut (where the drive crosses the parkway)"],
	["post", "curb_ramp", "never", 4, "a sign or pole on a curb ramp"],
	["post", "crosswalk", "never", 3, "a sign or pole in a crosswalk"],
	["post", "sidewalk_line", "never", 3, "a sign or pole in the middle of the sidewalk"],
	["post", "front_walk", "never", 3, "a sign or pole on a front walk"],
	["post", "road", "never", 4, "a sign or pole in the street"],
	["post", "building", "never", 4, "a sign or pole inside a building"],
	["post", "parking_stall", "never", 3, "a sign or pole in a parking space"],
	["post", "post", "watch", 2, "two poles in one spot"],
	["prop", "drive", "never", 3, "a yard prop on the driveway"],
	["prop", "curb_cut", "never", 3, "a yard prop in the curb cut"],
	["prop", "front_walk", "never", 3, "a yard prop on the front walk"],
	["prop", "sidewalk_line", "never", 3, "a yard prop on the sidewalk"],
	["prop", "road", "never", 4, "a yard prop in the street"],
	["prop", "building", "never", 3, "a yard prop inside a wall"],
	["prop", "parking_stall", "never", 3, "a yard prop in a parking space"],
	["prop", "tree_trunk", "never", 2, "a yard prop through a tree trunk"],
	["prop", "prop*other", "never", 2, "two lots' props in one spot"],
	["tree_trunk", "building", "never", 4, "a tree growing through a wall"],
	["tree_trunk", "road", "never", 4, "a tree in the street"],
	["tree_trunk", "drive", "never", 3, "a tree in the driveway"],
	["tree_trunk", "curb_cut", "never", 3, "a tree in the curb cut"],
	["tree_trunk", "front_walk", "never", 3, "a tree on the front walk"],
	["tree_trunk", "sidewalk_line", "never", 3, "a tree in the middle of the sidewalk"],
	["tree_trunk", "curb_ramp", "never", 3, "a tree on a curb ramp"],
	["tree_trunk", "parking_stall", "never", 3, "a tree in a parking space"],
	["tree_trunk", "post", "watch", 2, "a tree trunk round a pole"],
	["drive_car", "front_walk", "never", 3, "a car parked across the front walk"],
	["drive_car", "sidewalk_line", "never", 3, "a car parked across the sidewalk"],
	["drive_car", "prop", "never", 3, "a car parked through a yard prop"],
	["drive_car", "tree_trunk", "never", 3, "a car parked through a tree"],
	["drive_car", "building*other", "never", 4, "a car parked in a neighbour's wall"],
	["garage_apron", "prop", "never", 3, "a yard prop blocking a garage door"],
	["garage_apron", "tree_trunk", "never", 3, "a tree blocking a garage door"],
	["garage_apron", "post", "never", 3, "a pole blocking a garage door"],
	["dock", "post", "never", 3, "a pole in a loading dock"],
	["dock", "tree_trunk", "never", 3, "a tree in a loading dock"],
	["parking_stall", "road", "never", 3, "a parking space in the street"],
	["public_site", "road", "watch", 3, "a public site over the street (its drive meets the street)"],
	["lot", "lot*other", "never", 2, "two lots on the same ground"],
	["lot", "road", "never", 3, "a lot over the street"],
	["lot", "public_site", "never", 3, "a lot over a public site"],
]
## Pairs that may overlap, and why (not checked).
const ALLOWED := [
	["tree crown", "lawn, drive, roof, sidewalk", "a crown overhangs; only its trunk claims ground"],
	["rail_bed", "road at a grade crossing", "the crossing is where they share ground (within %.0f m of one)" % CROSSING_REACH],
	["drive", "sidewalk", "a drive crosses the sidewalk at its curb cut"],
	["post", "parkway (grass strip)", "where signs, lights and poles belong"],
	["streetlight arm, signal mast arm", "road", "they hang over it"],
	["drive_car", "drive", "where it parks"],
	["building", "own drive / own parking", "an attached garage meets its drive"],
]
## Smallest overlap (m2) that counts, per pair.
const MIN_AREA := {"lot|lot*other": 1.0, "lot|road": 1.0, "building|building*other": 0.5, "building|road": 0.5,
	"rail_bed|lot": 1.0, "lot|public_site": 1.0, "public_site|road": 1.0, "building|sidewalk_line": 0.1}

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
	var shapes := collect(sim)
	for e in extra:
		_add(shapes, e[0], e[1], e[2], e[3])
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
				var hit := _overlap(sa.poly, sb.poly)
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
				var frac: float = hit[0] / maxf(minf(_area(sa.poly), _area(sb.poly)), 0.01)
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


## [overlap area, its middle].
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	var parts := Geometry2D.intersect_polygons(a, b)
	var total := 0.0
	var mid := Vector2.ZERO
	for q: PackedVector2Array in parts:
		if Geometry2D.is_polygon_clockwise(q):
			continue  # a hole
		var ar := _area(q)
		total += ar
		var c := Vector2.ZERO
		for v in q:
			c += v
		mid += c / q.size() * ar
	return [total, mid / total if total > 0.0 else Vector2.ZERO]


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


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


# ------------------------------------------------------------------ shapes

## Everything that stands on the ground, as shapes: {cat, what, key (owner:
## a lot key, "seg:N", "node:N"), poly (world x/z), box, id}.
static func collect(sim: CitySim) -> Array:
	var out := []
	var net := sim.network
	# The road view's own reading of which streets are country roads, which
	# are town streets, and its junction plans (curb returns, ramps).
	var rv := RoadView.new()
	rv.sim = sim
	rv.network = net
	rv._rural = rv._rural_segments()
	rv._urban = rv._urban_next
	var plans := Junction.plan(net, rv._rural, rv._urban, rv._signals())
	# The curb claims as the game has them (RoadView pushes its plans).
	var claims := CurbClaims.of(sim)
	claims.set_junctions(plans)
	_roads(out, sim, rv, plans)
	_junction_bits(out, sim, plans)
	_rail(out, sim)
	_lots(out, sim)
	_public(out, sim)
	# The buildings first: their builders' aprons claim the curb (as the game's
	# signs and lamps stand once the town is drawn).
	_built(out, sim)
	_signs(out, sim, rv, plans)
	_name_posts(out, sim)
	for l in StreetLights.place(net, rv._rural, claims):
		var p: Vector3 = l[1]
		_add(out, "post", "streetlight", "", _sq(Vector2(p.x, p.z), POST.streetlight))
	_poles(out, sim, rv)
	rv.free()
	for id in sim.buses.stops:
		var st: Dictionary = sim.buses.stops[id]
		var pos: Vector3 = st.pos
		var pt: Vector3 = st.get("pt", pos)
		var outward := Vector3(pos.x - pt.x, 0.0, pos.z - pt.z).normalized()
		var at := pos + outward * (RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
		_add(out, "post", "bus_stop", "stop:%s" % id, _sq(Vector2(at.x, at.z), POST.bus_stop))
	for i in out.size():
		out[i].id = i
	return out


static func _add(out: Array, cat: String, what: String, key: String, poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	out.append({"cat": cat, "what": what, "key": key, "poly": poly, "box": box, "id": -1})


static func _sq(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half), c + Vector2(-half, half)])


## A box `half_len` along `along` and `half_w` across, round `c`.
static func _obb(c: Vector2, along: Vector2, half_len: float, half_w: float) -> PackedVector2Array:
	var u := along.normalized()
	var n := Vector2(-u.y, u.x)
	return PackedVector2Array([c - u * half_len - n * half_w, c + u * half_len - n * half_w,
		c + u * half_len + n * half_w, c - u * half_len + n * half_w])


## A lot-frame Rect2 (x across, z back from the street) in the world.
static func _rect(frame: Transform3D, r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var w := frame * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


## Quads along a polyline between offsets o0..o1 (to the right of travel
## when positive), one per step.
static func _strip(out: Array, cat: String, what: String, key: String, pts: PackedVector3Array, o0: float, o1: float) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		if a.distance_to(b) < 0.01:
			continue
		var u := (b - a).normalized()
		var n := Vector2(-u.y, u.x)
		_add(out, cat, what, key, PackedVector2Array([a + n * o0, b + n * o0, b + n * o1, a + n * o1]))


static func _roads(out: Array, sim: CitySim, rv: RoadView, plans: Dictionary) -> void:
	var net := sim.network
	for id in net.segments:
		var sg: Dictionary = net.segments[id]
		var type: int = sg.type
		var pts := net.sample_segment(id)
		if absf(pts[pts.size() / 2].y) > 1.0:
			continue  # a bridge or tunnel: it claims no ground at grade
		var hw := RoadStyle.half_width(type)
		var key := "seg:%d" % id
		_strip(out, "road", RoadStyle.TYPES[type].get("name", str(type)), key, pts, -hw, hw)
		var spec: Dictionary = RoadStyle.TYPES[type]
		if RoadStyle.is_freeway(type) or not spec.get("walk", true):
			continue
		var urban: bool = rv._urban.has(id)
		var rural: bool = (rv._rural.has(id) or spec.get("rural", false))
		if not urban and (spec.get("rural", false) or (rural and float(spec.median) == 0.0)):
			continue  # a country road: no sidewalk
		# Its sidewalks, trimmed where a shaped corner takes over.
		var ja := Junction.trim(plans, sg.a, id)
		var jb := Junction.trim(plans, sg.b, id)
		if ja > 0.0 or jb > 0.0:
			pts = RoadMesh._between(pts, ja, RoadNetwork.polyline_length(pts) - jb)
		var mid := hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
		for side in [-1.0, 1.0]:
			_strip(out, "sidewalk_line", "sidewalk", key, pts, side * (mid - WALK_CENTRE_HALF), side * (mid + WALK_CENTRE_HALF))


## Curb ramps and crosswalks at shaped town corners (Junction._draw_node,
## JunctionMarks.paint): across each arm from d + 0.3 to d + 2.7 m out.
## Worked out here from the junction plans themselves, not from CurbClaims,
## so a post the claims let stand on a ramp is still caught.
static func _junction_bits(out: Array, sim: CitySim, plans: Dictionary) -> void:
	for n in plans:
		var j: Dictionary = plans[n]
		if j.get("country", false) or j.has("bend"):
			continue
		var center: Vector3 = j.center
		var key := "node:%d" % n
		var ramps := Junction.ramps(j)
		for r in ramps:
			var c: Dictionary = j.corners[r[0]]
			var a: Dictionary = j.arms[c.a]
			var b: Dictionary = j.arms[c.b]
			if r[1] == "pair":
				for pair in [[a, 1.0], [b, -1.0]]:
					var arm: Dictionary = pair[0]
					var from: float = float(arm.d) + Junction.RAMP_GAP
					if from + Junction.RAMP_WIDTH > float(arm.length) * 0.5:
						continue
					_arm_band(out, "curb_ramp", "pair", key, center, arm, pair[1], float(arm.hw),
						float(arm.hw) + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH, from, from + Junction.RAMP_WIDTH)
			else:
				# A diagonal ramp at the corner's middle: a square at the curb return.
				var mid := (Vector2(a.n) * -1.0 + Vector2(b.n)).normalized()
				var arm_hw := maxf(float(a.hw), float(b.hw))
				var at := Vector2(center.x, center.z) + mid * (arm_hw + float(c.r) * 0.4)
				_add(out, "curb_ramp", "diagonal", key, _sq(at, 1.2))
		if JunctionMarks.marked(j):
			for arm in j.arms:
				var d: float = float(arm.d)
				if d + JunctionMarks.CROSS_FAR > float(arm.length) * 0.5:
					continue
				_arm_band(out, "crosswalk", "shaped", key, center, arm, 1.0, -float(arm.hw), float(arm.hw),
					d + JunctionMarks.CROSS_NEAR, d + JunctionMarks.CROSS_FAR)


static func _arm_band(out: Array, cat: String, what: String, key: String, center: Vector3, arm: Dictionary,
		side: float, o0: float, o1: float, from: float, to: float) -> void:
	var p0: Array = LotPlanner.point_at(arm.pts, from)
	var p1: Array = LotPlanner.point_at(arm.pts, to)
	var a := Vector2(p0[0].x, p0[0].z)
	var b := Vector2(p1[0].x, p1[0].z)
	var dir := Vector2(p0[1].x, p0[1].z).normalized()
	var nrm := Vector2(-dir.y, dir.x) * side
	_add(out, cat, what, key, PackedVector2Array([a + nrm * o0, b + nrm * o0, b + nrm * o1, a + nrm * o1]))


static func _rail(out: Array, sim: CitySim) -> void:
	for id in sim.rail.pieces:
		var pc: Dictionary = sim.rail.pieces[id]
		var pts: PackedVector3Array = PackedVector3Array(pc.get("pts", []))
		if pts.size() < 2:
			continue
		_strip(out, "rail_bed", "town", "rail:%d" % id, pts, -RAIL_HALF, RAIL_HALF)
	# The county's real railroads near the town (region -> local).
	var box := Rect2()
	var first := true
	for id in sim.network.nodes:
		var p: Vector3 = sim.network.nodes[id]
		if first:
			box = Rect2(Vector2(p.x, p.z), Vector2.ZERO)
			first = false
		box = box.expand(Vector2(p.x, p.z))
	if first:
		return
	box = box.grow(300.0)
	var o := sim.terrain_offset
	var rbox := Rect2(box.position + o, box.size)
	for route in CountyRail.all().size():
		var prof := CountyRail.profile(route)
		var at: PackedVector2Array = prof.at
		var kind: PackedByteArray = prof.kind
		for i in at.size() - 1:
			if not rbox.has_point(at[i]):
				continue
			if kind[i] == 3 or kind[i + 1] == 3 or kind[i] == 2 or kind[i + 1] == 2:
				continue  # inside a backdrop town (not drawn), or on a bridge
			var a := at[i] - o
			var b := at[i + 1] - o
			if a.distance_to(b) < 0.01:
				continue
			var u := (b - a).normalized()
			var n := Vector2(-u.y, u.x)
			_add(out, "rail_bed", "county", "county:%d" % route,
				PackedVector2Array([a - n * RAIL_HALF, b - n * RAIL_HALF, b + n * RAIL_HALF, a + n * RAIL_HALF]))


static func _lots(out: Array, sim: CitySim) -> void:
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var c: PackedVector2Array = lot.get("corners", PackedVector2Array())
		if c.size() >= 3:
			_add(out, "lot", "built" if sim.buildings.has(key) else "empty", key, c)


static func _public(out: Array, sim: CitySim) -> void:
	for id in sim.services.buildings:
		_add(out, "public_site", "service", "service:%d" % id, sim.services.footprint(id))
	for id in sim.warehouses.buildings:
		var poly := PackedVector2Array()
		for p in Warehouses.corners(sim.warehouses.buildings[id]):
			poly.append(Vector2(p.x, p.y))
		_add(out, "public_site", "warehouse", "warehouse:%d" % id, poly)


## Stop, yield and No Left/Right posts and signal poles, where
## JunctionView._rebuild_all stands them (mirrors junction_view.gd 183-327:
## positions only; each slid off drives and ramps by the same
## JunctionView._post_spot and no_turn_spot).
static func _signs(out: Array, sim: CitySim, rv: RoadView, plans: Dictionary) -> void:
	var traffic := sim.traffic
	var claims := CurbClaims.of(sim)
	var nodes := traffic.junctions.keys()
	nodes.sort()
	var sign_at := {}
	for n in nodes:
		var j: Dictionary = traffic.junctions[n]
		if j.control == TrafficSim.Rule.NONE:
			continue
		var cross := 0.0
		for w2 in traffic.ways_into(n):
			cross = maxf(cross, RoadStyle.TYPES[traffic.ways[w2].type].width * 0.5)
		var plain := cross + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
		var country_plan := {}
		for wid in traffic.ways_into(n):
			var seg: int = traffic.ways[wid].seg
			var sl := traffic.stop_line(wid)
			var dir: Vector3 = sl.dir
			var right: Vector3 = sl.right
			var half: float = RoadStyle.TYPES[traffic.ways[wid].type].width * 0.5
			var base := Vector3.ZERO
			var arm := {}
			if _is_country(traffic, rv, plans, n, seg):
				if country_plan.is_empty():
					country_plan = _country_plan(traffic, rv, plans, n)
				arm = _arm(country_plan, seg)
			if not arm.is_empty():
				var s := JunctionMarks.country_near(country_plan, arm) + JunctionMarks.BAR + 0.6
				var at: Array = LotPlanner.point_at(arm.pts, s)
				var t: Vector3 = at[1] if at.size() > 1 else Vector3.FORWARD
				t.y = 0.0
				t = t.normalized()
				dir = -t
				right = Vector3(-dir.z, 0.0, dir.x)
				var back: float = Junction.SHOULDER + 0.6 if arm.get("country", true) \
					else RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5
				var off := JunctionMarks.country_edge(country_plan, arm, s) + back
				var meant: Vector3 = at[0] + right * off
				base = JunctionView._post_spot(claims, meant, dir, j.control == TrafficSim.Rule.SIGNAL,
					JunctionView.post_back(sim.network.nodes[n], meant, dir, cross, j.control == TrafficSim.Rule.SIGNAL),
					JunctionView.post_ahead(false, true))
			else:
				var walk := plain
				if Junction.trim(plans, n, seg) > 0.0:
					walk = -TrafficSim.CROSSWALK_AHEAD
				var back := walk + 3.3
				base = sl.pos + right * sl.curb - dir * 1.0
				if not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
					base = sl.pos + right * (half + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5) - dir * back
				base = JunctionView._post_spot(claims, base, dir, j.control == TrafficSim.Rule.SIGNAL,
					JunctionView.post_back(sim.network.nodes[n], base, dir, cross, j.control == TrafficSim.Rule.SIGNAL),
					JunctionView.post_ahead(Junction.trim(plans, n, seg) > 0.0, false))
				# A crosswalk at a plain (unshaped) corner (_markings).
				var stops_here: bool = j.control == TrafficSim.Rule.SIGNAL or j.control == TrafficSim.Rule.ALL_STOP \
					or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid) and j.sign != "yield")
				var spec: Dictionary = RoadStyle.TYPES[traffic.ways[wid].type]
				var walks: bool = spec.get("walk", true) and not spec.get("rural", false) and not rv._rural.has(seg)
				if stops_here and not JunctionMarks.marked(plans.get(n, {})) and not spec.oneway and walks:
					var c: Vector3 = sl.pos - dir * walk
					_add(out, "crosswalk", "plain", "node:%d" % n, _obb(Vector2(c.x, c.z), Vector2(dir.x, dir.z), 1.2, half))
			sign_at[wid] = [base, dir]
			var at2 := Vector2(base.x, base.z)
			if j.control == TrafficSim.Rule.SIGNAL:
				_add(out, "post", "signal_pole", "node:%d" % n, _sq(at2, POST.signal_pole))
			elif j.control == TrafficSim.Rule.ALL_STOP or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid)):
				var what := "yield_sign" if j.sign == "yield" and j.control == TrafficSim.Rule.PRIORITY else "stop_sign"
				_add(out, "post", what, "node:%d" % n, _sq(at2, POST.stop_sign))
	var rule_keys := traffic.lane_rules.keys()
	rule_keys.sort()
	for k in rule_keys:
		var rule: Dictionary = traffic.lane_rules[k]
		var wid := -1
		var node := int(k.get_slice(":", 0))
		var seg := int(k.get_slice(":", 1))
		for w in traffic.ways_into(node):
			if traffic.ways[w].seg == seg:
				wid = w
		if wid == -1 or not (rule.get("no_left", false) or rule.get("no_right", false)):
			continue
		var sl := traffic.stop_line(wid)
		var post: Vector3 = sl.pos + sl.right * (sl.curb + 0.9) - sl.dir * 1.5
		var pdir: Vector3 = sl.dir
		if sign_at.has(wid):
			pdir = sign_at[wid][1]
			post = sign_at[wid][0] - pdir * 2.5
		post = JunctionView.no_turn_spot(claims, post, pdir)
		_add(out, "post", "no_turn_sign", "node:%d" % node, _sq(Vector2(post.x, post.z), POST.no_turn_sign))


static func _is_country(traffic: TrafficSim, rv: RoadView, plans: Dictionary, n: int, seg: int) -> bool:
	var j: Dictionary = plans.get(n, {})
	if j.get("country", false) or j.get("unmarked", false):
		return true
	if plans.has(n) or not traffic.network.segments.has(seg):
		return false
	var spec: Dictionary = RoadStyle.TYPES[traffic.network.segments[seg].type]
	if spec.oneway:
		return false
	return spec.get("rural", false) or not spec.get("walk", true) or rv._rural.has(seg)


static func _country_plan(traffic: TrafficSim, rv: RoadView, plans: Dictionary, n: int) -> Dictionary:
	var j: Dictionary = plans.get(n, {})
	if j.get("country", false) or j.get("unmarked", false):
		return j
	var net: RoadNetwork = traffic.network
	return {"center": net.nodes[n], "arms": Junction.arms_at(net, n, rv._rural, rv._urban), "corners": []}


static func _arm(plan: Dictionary, seg: int) -> Dictionary:
	for arm in plan.get("arms", []):
		if arm.seg == seg:
			return arm
	return {}


## Corner street-name posts (StreetSignView._corner, called as is).
static func _name_posts(out: Array, sim: CitySim) -> void:
	var ssv := StreetSignView.new()
	ssv.sim = sim
	for n in sim.network.nodes:
		var spec := ssv._corner(n)
		if not spec.is_empty():
			_add(out, "post", "street_name", "node:%d" % n, _sq(spec.at, POST.street_name))
	ssv.free()


## Utility poles down country roads and town streets (RoadView's own runs,
## keys and blocks: road_view.gd 570-620).
static func _poles(out: Array, sim: CitySim, rv: RoadView) -> void:
	var segs := {}
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id)
		var spec: Dictionary = RoadStyle.TYPES[sim.network.segments[id].type]
		if RoadStyle.is_freeway(sim.network.segments[id].type) or absf(pts[pts.size() / 2].y) > 1.0:
			continue
		var rural: bool = (rv._rural.has(id) or spec.get("rural", false)) and pts[pts.size() / 2].y < 1.0
		if rv._urban.has(id) or rural:
			segs[id] = true
	var drives := rv._drives()
	for run in rv._pole_runs(segs):
		var pkey := rv._pole_key(run, drives)
		for pole in PoleLine.place(run.pts, pkey[2], pkey[3], pkey[4], rv._pole_blocked(run.ids)):
			var b: Vector3 = pole[0]
			_add(out, "post", "utility_pole", "run:%d" % int(run.id), _sq(Vector2(b.x, b.z), POST.utility_pole))


## Each building as its builder draws it (BuildingView._spawn's own steps:
## its footprints, its plan, its trees), then what stands on its lot: the
## drive and curb cut, the front walk, parking and docks, garage doors' aprons,
## a car drawn out on the drive, the mailbox, the yard props.
static func _built(out: Array, sim: CitySim) -> void:
	var bv := BuildingView.new()
	bv.sim = sim
	bv._check_parkways()  # the view's keep-clear spots for street trees
	var net := sim.network
	var keys := sim.buildings.keys()
	keys.sort()
	var drawn := {}  # key -> [masses, plan, trees (world entries)]
	var tree_grid := {}  # Vector2i (40 m) -> [world tree entries]
	var stale := 0
	for key in keys:
		if not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key]
		var frame := SiteLayout.frame(lot)
		var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
		var rng := RandomNumberGenerator.new()
		rng.seed = b.seed
		var fit := bv.fit_of(key, xf)
		var type := BuildingTypes.type_of(b)
		HouseBuilder.last_info = {}
		var before := HouseBuilder.last_masses
		HouseBuilder.last_masses = []
		# What its builder paves across the parkway, as it draws it (the
		# curb claims read the plan instead, so the two are checked apart).
		HouseBuilder.cuts_drawn = []
		var parts := bv._draw(key, lot, b, fit, rng.randi())
		var paved: Array = HouseBuilder.cuts_drawn
		HouseBuilder.cuts_drawn = null
		var masses: Array = HouseBuilder.last_masses
		if masses.is_empty() and not before.is_empty():
			stale += 1  # BuildingView would have used the previous building's masses here
		var plan: Dictionary = HouseBuilder.last_info.duplicate() if type == "house" else {}
		var trees := []
		# The trees as BuildingView._set_trees keeps them: street trees off
		# its keep-clear spots and the mailbox, a corner lot's side-street
		# trees too.
		var mailbox := CurbClaims.of(sim).mailbox_at(key, true)  # BuildingView._set_trees' own reading
		var planted := []
		if parts.size() > 2:
			for t: Array in parts[2]:
				var w := frame * (t[0] as Vector3)
				var street := (t[0] as Vector3).z < -0.5
				if street and (not bv._parkway_free(Vector2(w.x, w.z)) \
						or Vector2(w.x, w.z).distance_to(mailbox) < BuildingView.MAILBOX_CLEAR):
					continue
				planted.append([w, int(t[1]), float(t[3]), float(t[4]) if t.size() > 4 else -1.0, street])
		for t: Array in bv._side_trees(key):
			var q: Vector2 = t[0]
			if bv._parkway_free(q):
				planted.append([Vector3(q.x, 0.0, q.y), int(t[1]), float(t[3]), -1.0, true])
		for e in planted:
			var w: Vector3 = e[0]
			trees.append(e)
			var c := Vector2i(floori(w.x / 40.0), floori(w.z / 40.0))
			if not tree_grid.has(c):
				tree_grid[c] = []
			tree_grid[c].append(e)
		drawn[key] = [masses, plan, trees]
		for m: Rect2 in masses:
			_add(out, "building", type, key, _rect(frame, m))
		for e in trees:
			var w: Vector3 = e[0]
			_add(out, "tree_trunk", "street" if e[4] else "yard", key, _sq(Vector2(w.x, w.z), TRUNK))
		var tc := float(lot.get("to_curb", 2.0))
		# Drive and curb cut, front walk.
		var lay := SiteLayout.for_lot(sim, key)
		if type == "house" and plan.has("drive_x"):
			var dx := float(plan.drive_x)
			var dw := float(plan.drive_w)
			_add(out, "drive", "house", key, _rect(frame, Rect2(dx - dw * 0.5, 0.0, dw, maxf(float(plan.get("garage_z", 6.0)), 1.0))))
			_add(out, "curb_cut", "house", key, _rect(frame, Rect2(dx - dw * 0.5, -tc, dw, tc)))
			if plan.has("walk"):
				# Where an L walk meets the drive, the drive takes over.
				var wr: Rect2 = plan.walk
				if wr.end.x > dx - dw * 0.5 and wr.position.x < dx + dw * 0.5 and wr.size.y < 2.0:
					if wr.position.x < dx:
						wr = Rect2(wr.position, Vector2(maxf(dx - dw * 0.5 - wr.position.x, 0.0), wr.size.y))
					else:
						wr = Rect2(Vector2(dx + dw * 0.5, wr.position.y), Vector2(maxf(wr.end.x - dx - dw * 0.5, 0.0), wr.size.y))
				if wr.size.x > 0.1:
					_add(out, "front_walk", "house", key, _rect(frame, wr))
			for d in DoorLog.placed(plan):
				if d[0] != "garage":
					continue
				var c: Vector3 = d[1]
				var f: Vector3 = d[2]
				var w := float(d[3])
				var a2 := Vector2(c.x, c.z) + Vector2(f.x, f.z) * 1.5
				var poly := PackedVector2Array()
				for q in _obb(a2, Vector2(f.x, f.z), 1.5, w * 0.5):
					var wq := frame * Vector3(q.x, 0.0, q.y)
					poly.append(Vector2(wq.x, wq.z))
				_add(out, "garage_apron", "house", key, poly)
		else:
			if type == "duplex":
				if not lay.get("main_street", false) and not lay.spots.is_empty():
					var dcx := float(lay.cut_x)
					_add(out, "curb_cut", type, key, _rect(frame, Rect2(dcx - 1.5, -tc, 3.0, tc)))
			else:
				for c in paved:
					_add(out, "curb_cut", type, key, _paved_poly(frame, c))
			if not lay.get("main_street", false) and not lay.spots.is_empty():
				var cx := float(lay.cut_x)
				var cw := 3.0 if type == "duplex" else 6.0  # the drive on the lot (as #940 measured it)
				_add(out, "drive", type, key, _rect(frame, Rect2(cx - cw * 0.5, 0.0, cw, maxf(float(lay.get("aisle_z", 0.0)), 3.0))))
		for sp in lay.spots:
			var at: Vector2 = sp.pos
			var face: Vector2 = sp.get("face", Vector2(0, 1))
			match String(sp.kind):
				"stall":
					_add(out, "parking_stall", type, key, _local_obb(frame, at, face, STALL.y * 0.5, STALL.x * 0.5))
				"bay", "dock":
					_add(out, "dock", type, key, _local_obb(frame, at - face * 3.0, face, 3.0, 1.8))
				"garage":
					if int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
						continue
					# Drawn out on the drive where it's long enough (TrafficView._out_pick).
					var front := at - face * 6.2
					if (front - face * CAR.y * 0.5).y >= 2.6 and (front - face * CAR.y).y >= 0.0:
						_add(out, "drive_car", type, key, _local_obb(frame, front - face * CAR.y * 0.5, face, CAR.y * 0.5, CAR.x * 0.5))
	# Mailboxes once every lot is drawn (they keep off the neighbours' drives).
	for key in keys:
		if drawn.has(key) and int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			var box := bv._mailbox_at(key)
			if box.is_finite():
				_add(out, "post", "mailbox", key, _sq(box, POST.mailbox))
	bv.free()
	if stale > 0:
		print("overlap_audit: %d buildings drew no masses of their own (BuildingView would reuse the last one's)" % stale)
	# Yard props (StateView._place: the drawn masses, plan and nearby trees).
	for key in keys:
		if not drawn.has(key) or LotState.kind_of(sim.buildings[key]) == "":
			continue
		var p: Vector3 = sim.lots[key].pos
		var near := []
		var c0 := Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for e in tree_grid.get(c0 + Vector2i(dx, dz), []):
					if Vector2(e[0].x, e[0].z).distance_to(Vector2(p.x, p.z)) < 40.0:
						near.append([e[0], e[1], e[2], e[3]])
		var yard := LotState.yard_of(sim, key, drawn[key][0], drawn[key][1], near)
		var b: Dictionary = sim.buildings[key]
		var piled := float(sim.hubs.trash.get(int(sim.lots[key].seg), 0.0)) >= Balance.GARBAGE_PILE_LB
		var items := LotState.items(sim.city_seed, key, int(b.seed), sim.care.tier_of(key), sim.care.cond_of(key), yard, piled)
		var frame := SiteLayout.frame(sim.lots[key])
		for it in items:
			if it.item in ["lease", "flag"]:
				continue  # a sign on a post or a flag pole: stands where it's meant to
			_add(out, "prop", String(it.item), key, _rect(frame, LotState.footprint(it.item, it.at, it.yaw)))


## Paving a builder drew out to the curb ([x0, x1, curb z, flare], lot
## frame) as it lies: across the parkway and sidewalk, a commercial apron
## flared at the curb (HouseBuilder._curb_cut's triangles).
static func _paved_poly(frame: Transform3D, c: Array) -> PackedVector2Array:
	var x0 := float(c[0])
	var x1 := float(c[1])
	var cz := float(c[2])
	var f := float(c[3])
	var w0 := cz + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var pts := [Vector2(x0 - f, cz), Vector2(x1 + f, cz), Vector2(x1, w0), Vector2(x1, w1), Vector2(x0, w1), Vector2(x0, w0)]
	var out := PackedVector2Array()
	for q: Vector2 in pts:
		var w := frame * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


static func _local_obb(frame: Transform3D, c: Vector2, along: Vector2, half_len: float, half_w: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for q in _obb(c, along, half_len, half_w):
		var w := frame * Vector3(q.x, 0.0, q.y)
		poly.append(Vector2(w.x, w.z))
	return poly


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
