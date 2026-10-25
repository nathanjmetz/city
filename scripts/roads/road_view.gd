class_name RoadView
extends Node3D
## Draws the road network. Redraws whenever the network changes, reusing
## the mesh of every road that didn't.
## Streets and avenues out in the country, with nothing built or zoned along
## them, are drawn as rural roads: gravel shoulders and utility poles instead
## of curbs and sidewalks. They get their curbs once the town reaches them.

## How far from a road a home, shop or service makes it a town street.
const TOWN_REACH := 60.0

var network: RoadNetwork
var sim: CitySim
## Draws every street and avenue as a country road (the county highways
## running on past the town to the horizon).
var all_rural := false
var _rural := {}  # segment id -> true
## Country highways drawn as curbed town streets where the town lines them
## (segment id -> true), and the same as last worked out.
var _urban := {}
var _urban_next := {}
const URBAN_TYPES := [RoadStyle.Type.STATE_HWY, RoadStyle.Type.COUNTY]
## Streets that have been town streets, so they keep their curbs while lots
## are replanned around them (segment id -> true).
var _town_ever := {}
var _recheck := -1.0  # seconds until the town edge is checked again, or -1
var _redraw := false  # a new drive needs the poles moved
var _drawn_drives := []
var _trees := TreeField.new()  # street trees down planted medians
var _street_cache := {}  # segment id -> [what it was drawn from, its mesh]
var _pole_cache := {}  # segment id -> [what they were drawn from, wood, wire]
var _bridge_cache := {}  # segment id -> [what it was drawn from, piers or null]
var _junction_cache := {}  # node -> [its plan, {part: mesh}]
## The shaped junctions as last drawn (Junction.plan), for the junction
## paint and signs; plans_version counts each change.
var plans := {}
var plans_version := 0
var _road_grid := {}  # StreetLights._pieces, for keeping poles off other roads
var _road_grid_version := -1
var _junction_grid := {}  # coarse cell -> junction centres, for keeping poles back from them
var _later := {}  # segment id -> what to redraw it from, a few each frame
var _seg_mi := {}  # segment id -> its street
var _poles_later := {}  # pole run id -> [key, run], drawn when a rebuild runs out of time
var _drops: MeshInstance3D
## Streets and avenues drawn as country roads changed (StreetLights leaves
## them unlit, as the county leaves its roads).
signal country_changed(segs: Dictionary)
var _corners_later := {}  # node -> [key, its plan], drawn when a rebuild runs out of time
var _merged := []  # the merged pole and corner meshes, redone once the later ones are drawn
var _gen := 0  # which rebuild is current; a sliced one left behind stops
var _regrade_gen := -1  # the rebuild a regrade is waiting on, or -1
var _building := false  # a sliced rebuild is part way through
const REMESH_MS := 8.0  # redraw changed streets for this long, then finish them later
## A neighbor's whole town lands at once: its streets are drawn a few each
## frame instead of in one long freeze (RegionView).
var sliced := false
## Roads that age and get repaired (RoadSurface): this view's own pavement,
## paint, chip seal and gravel materials and the wear map they read.
var _surface := RoadSurface.new()
var _dust: GravelDust

var _mats := {
	"asphalt": Surfaces.asphalt(),
	"curb": Surfaces.concrete(RoadStyle.CURB_COLOR),
	"curb_face": Surfaces.concrete(RoadStyle.CURB_COLOR.darkened(0.45)),
	"walk": Surfaces.concrete(RoadStyle.SIDEWALK_COLOR, true),
	"median": Ground.grass(),
	"yellow": Surfaces.paint(RoadStyle.MARKING_YELLOW),
	"white": Surfaces.paint(RoadStyle.MARKING_WHITE),
	"gravel": Surfaces.gravel(),
	"gravel road": Surfaces.gravel(),  # a junction where only gravel and dirt roads meet
	"shoulder": Surfaces.shoulder(),
	"bus": Surfaces.paint(Color(0.56, 0.17, 0.14)),  # red transit lane
	"pole": RoadStyle.material(Color(0.33, 0.27, 0.21)),
	"wire": RoadStyle.material(Color(0.12, 0.12, 0.12)),
	"concrete": Surfaces.concrete(Color(0.66, 0.65, 0.62)),
	"dirt": Surfaces.lane(Color(0.50, 0.41, 0.30)),
	"chip seal": Surfaces.chip_seal(),
	"brick": Surfaces.brick(),
	"apron": RoadStyle.material(Color(0.5, 0.44, 0.38)),  # tinted, textured-look concrete
	"tunnel": RoadStyle.material(Color(0.1, 0.1, 0.12, 0.45), true),
	"domes": Surfaces.concrete(Junction.DOMES_COLOR),
	"barricade": _vertex_colour(),
}


func _init() -> void:
	_surface.install(_mats)


func setup(net: RoadNetwork, s: CitySim = null) -> void:
	network = net
	sim = s
	network.changed.connect(rebuild)
	if sim != null and not sliced:
		# Dust behind cars on gravel roads (your own town's cars).
		_dust = GravelDust.new()
		_dust.setup(sim)
		add_child(_dust)
	if sim != null:
		for sig in [sim.lots_changed, sim.zones_changed, sim.buildings_changed]:
			sig.connect(func(): if _recheck < 0.0: _recheck = 1.0)
		for sig in [sim.farms_changed, sim.industry_changed]:
			sig.connect(func():
				_redraw = true
				if _recheck < 0.0: _recheck = 1.0)
	rebuild()


## Rebuilds when a road has turned from country road to town street or back
## (checked at most once a second while the town grows).
func _process(delta: float) -> void:
	var q := GraphicsQuality.current
	_surface.detail = 0.0 if q != null and q.active and (q.browser or q.tier <= GraphicsQuality.LOW) else 1.0
	_surface.tick(self, sim, delta)
	if not _building and not (_later.is_empty() and _poles_later.is_empty() and _corners_later.is_empty()):
		_remesh_later()
	if _recheck < 0.0:
		return
	_recheck -= delta
	if _recheck >= 0.0:
		return
	_recheck = -1.0
	# A farm or company that changed only matters if its drive moved.
	if (_redraw and _drives() != _drawn_drives) or _rural_segments() != _rural or _urban_next != _urban:
		rebuild()
	else:
		_rebuild_drops()  # houses built or gone along a pole line
	_redraw = false


## True when a point is within a town cell or next to one.
static func _near_town(town: Dictionary, p: Vector3, cell: float) -> bool:
	var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if town.has(c + Vector2i(dx, dz)):
				return true
	return false


## Streets and avenues with no zoned lot, building or service near them.
## Also works out which country highways the town has grown along
## (_urban_next).
func _rural_segments() -> Dictionary:
	var out := {}
	_urban_next = {}
	if all_rural:
		for id in network.segments:
			out[id] = true
		return out
	if sim == null:
		return out
	var cell := TOWN_REACH
	var town := {}  # Vector2i -> true where something is built or zoned
	var mark := func(p: Vector3) -> void:
		town[Vector2i(floori(p.x / cell), floori(p.z / cell))] = true
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE:
			mark.call(lot.front)
	for id in sim.services.buildings:
		mark.call(sim.services.buildings[id].pos)
	var in_town := {}
	var eligible := []
	var urban := {}
	for id in network.segments:
		var type: int = network.segments[id].type
		if type in URBAN_TYPES:
			# The state highway or a county road where the town has grown along
			# most of it becomes a curbed town street there (SR 18 through
			# Marion): curb and gutter, sidewalks, parking where its shoulders were.
			var pts := network.sample_segment(id)
			var hits := 0
			for p in pts:
				if _near_town(town, p, cell):
					hits += 1
			if hits * 2 >= pts.size() and pts[pts.size() / 2].y < 1.0:
				urban[id] = true
			continue
		if type != RoadStyle.Type.STREET and type != RoadStyle.Type.AVENUE:
			continue
		var near := false
		for p in network.sample_segment(id):
			if _near_town(town, p, cell):
				near = true
				break
		if near:
			in_town[id] = true
		else:
			eligible.append(id)
	# A street keeps its curbs once it has them (as real curbs stay while a
	# block is replatted), and a run of street that's town at both ends is
	# town all along: one style per street, no country stretch mid-block.
	for id in _town_ever:
		if network.segments.has(id):
			in_town[id] = true
	for run in _runs():
		var first := -1
		var last := -1
		for i in run.size():
			if in_town.has(run[i]):
				if first == -1:
					first = i
				last = i
		for i in range(first + 1, last):
			in_town[run[i]] = true
	_town_ever = in_town
	_urban_next = urban
	for id in eligible:
		if not in_town.has(id):
			out[id] = true
	return out


## Streets and avenues as runs of segments that carry straight on through
## their nodes (a side street meeting a road doesn't break it), each in
## order along the road.
func _runs() -> Array:
	var next := {}  # segment id -> segments it carries straight on into
	for n in network.nodes:
		var here := []
		for id in network.segments_at(n):
			var s: Dictionary = network.segments[id]
			if int(s.type) != RoadStyle.Type.STREET and int(s.type) != RoadStyle.Type.AVENUE:
				continue
			var at: Vector3 = network.nodes[n]
			var t: Vector3 = s.ctrl - at
			t.y = 0.0
			if t.length() > 0.01:
				here.append([id, t.normalized(), int(s.type)])
		# Pair the straightest continuations first.
		var pairs := []
		for i in here.size():
			for j in range(i + 1, here.size()):
				var d: float = here[i][1].dot(here[j][1])
				if d < -0.8 and here[i][2] == here[j][2]:
					pairs.append([d, here[i][0], here[j][0]])
		pairs.sort()
		var used := {}
		for p in pairs:
			if used.has(p[1]) or used.has(p[2]):
				continue
			used[p[1]] = true
			used[p[2]] = true
			next[p[1]] = next.get(p[1], []) + [p[2]]
			next[p[2]] = next.get(p[2], []) + [p[1]]
	var runs := []
	var seen := {}
	var ids := network.segments.keys()
	ids.sort()
	for id in ids:
		if seen.has(id) or not next.has(id) or next[id].size() > 1:
			continue
		# Walk from one end of the run to the other.
		var run := []
		var cur: int = id
		var prev := -1
		while cur != -1 and not seen.has(cur):
			seen[cur] = true
			run.append(cur)
			var go := -1
			for o in next.get(cur, []):
				if o != prev:
					go = o
			prev = cur
			cur = go
		runs.append(run)
	return runs


## Farm lanes and company drives, kept clear of poles.
func _drives() -> Array:
	var drives := []
	if sim != null:
		for f in sim.farms.farms.values():
			drives.append_array(f.get("drive", []))
		for c in sim.industry.sites.values():
			drives.append_array(c.get("drive", []))
	return drives


func rebuild() -> void:
	_gen += 1
	_rebuild_all(_gen)


## The land under `box` was graded again (TerrainView.graded): roads there
## are draped anew, so none is left under the new grade (Brawn 2026-10-24:
## roads going underground where a later road, rail or highway regraded
## the land beside them).
func regraded(box: Rect2) -> void:
	var near := box.grow(RoadStyle.right_of_way_half(RoadStyle.Type.HIGHWAY))
	var any := false
	for cache in [_street_cache, _pole_cache, _bridge_cache]:
		for id in cache.keys():
			if _crosses(cache[id][0][0], near):
				cache.erase(id)
				any = true
	for node in _junction_cache.keys():
		var p: Vector3 = network.nodes.get(node, Vector3.INF)
		if p == Vector3.INF or near.has_point(Vector2(p.x, p.z)):
			_junction_cache.erase(node)
			any = true
	if any and _regrade_gen < 0:
		_regrade_gen = _gen
		_after_regrade.call_deferred()


## Redraws after a regrade, unless a rebuild since (as when the roads
## themselves changed) already did.
func _after_regrade() -> void:
	if _regrade_gen == _gen:
		rebuild()
	_regrade_gen = -1


## True where two roads of any kinds meet end to end, nearly in line (a
## street running on as a gravel road): each simply ends at the node, with
## no round pad sticking out past the narrower one.
func _end_to_end(node: int) -> bool:
	var segs := network.segments_at(node)
	if segs.size() != 2:
		return false
	var arms := Junction.arms_at(network, node)
	return (arms[0].u as Vector2).dot(arms[1].u) < -0.9


## True where just two pieces of the same kind of road meet nearly in line,
## so the road runs on through the node with nothing to fill.
func _straight_on(node: int) -> bool:
	var segs := network.segments_at(node)
	if segs.size() != 2 or network.segments[segs[0]].type != network.segments[segs[1]].type:
		return false
	var c: Vector3 = network.nodes[node]
	var dirs := []
	for id in segs:
		var sg: Dictionary = network.segments[id]
		var ctrl: Vector3 = sg.ctrl
		var to: Vector3 = ctrl if ctrl.distance_to(c) > 0.5 else network.nodes[sg.b if sg.a == node else sg.a]
		dirs.append(Vector2(to.x - c.x, to.z - c.z).normalized())
	return dirs[0].dot(dirs[1]) < -0.995


static func _crosses(pts: PackedVector3Array, box: Rect2) -> bool:
	for p in pts:
		if box.has_point(Vector2(p.x, p.z)):
			return true
	return false


## Draws every road. A sliced view spreads it over frames, its old drawing
## staying up until the new one is done.
func _rebuild_all(gen: int) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var slice := Perf.now()
	_building = true
	var old := []
	for child in get_children():
		if child != _trees and child != _dust:
			old.append(child)
	if _trees.get_parent() == null:
		add_child(_trees)
	var median_trees := []
	var piers := []
	var was_rural := _rural
	_rural = _rural_segments()
	_urban = _urban_next
	if _rural != was_rural:
		country_changed.emit(_rural)
	_redraw = false
	var wood := []
	var wire := []
	var drives := _drives()
	_drawn_drives = drives
	# Ramps joining highways start where they clear the through lanes.
	var merges := RampMerge.merges(network)
	var cuts := {}  # [seg, node] -> metres
	var gaps := {}  # seg -> {side: [from, to]} where its barrier opens
	for m in merges:
		cuts[[m.ramp, m.node]] = RampMerge.ramp_cut(m)
		var g := RampMerge.barrier_gaps(m, network)
		for seg in g:
			if not gaps.has(seg):
				gaps[seg] = {}
			for side in g[seg]:
				gaps[seg][side] = g[seg][side]
	# Town street junctions get real corners; their roads stop short of them.
	var junctions := Junction.plan(network, _rural, _urban)
	if junctions != plans:
		plans = junctions
		plans_version += 1
	var street_cache := {}
	var t0 := Perf.now()
	_later.clear()
	_seg_mi.clear()
	_poles_later.clear()
	_corners_later.clear()
	_merged.clear()
	var pole_cache := {}
	var bridge_cache := {}
	var pole_segs := {}  # country roads at grade, for their pole lines
	for id in network.segments.keys():
		if sliced and (Perf.now() - t0) / 1000.0 > REMESH_MS and is_inside_tree():
			Perf.add(_perf_key(), slice)
			Terrain.shift = Vector2.ZERO
			await get_tree().process_frame
			if gen != _gen or not is_inside_tree():
				return
			Terrain.shift = Terrain.shift_for(self)
			slice = Perf.now()
			t0 = slice
		if not network.segments.has(id):
			continue
		var pts := network.sample_segment(id)
		var type: int = network.segments[id].type
		var sg: Dictionary = network.segments[id]
		var ja := Junction.trim(junctions, sg.a, id)
		var jb := Junction.trim(junctions, sg.b, id)
		var line_cuts := Vector2(JunctionMarks.line_cut(junctions, sg.a, id), JunctionMarks.line_cut(junctions, sg.b, id))
		# Where side roads come in at a country junction, this road's edge
		# line and shoulder stop: [side, metres, at the start].
		var breaks := []
		for end in [[sg.a, true], [sg.b, false]]:
			for b in junctions.get(end[0], {}).get("breaks", {}).get(id, []):
				# The junction's sides look out from the node; this road's run a to b.
				breaks.append([b[0] if end[1] else -b[0], b[1], end[1]])
		if ja > 0.0 or jb > 0.0:
			pts = RoadMesh._between(pts, ja, RoadNetwork.polyline_length(pts) - jb)
		var seg_gaps: Dictionary = gaps.get(id, {})
		var cut_a: float = cuts.get([id, sg.a], 0.0)
		pts = RampMerge.trim_ramp(pts, cut_a, true)
		pts = RampMerge.trim_ramp(pts, cuts.get([id, sg.b], 0.0), false)
		if cut_a > 0.0:
			# The trimmed ramp starts later, so its gaps move back too.
			var moved := {}
			for side in seg_gaps:
				moved[side] = [seg_gaps[side][0] - cut_a, seg_gaps[side][1] - cut_a]
			seg_gaps = moved
		if pts.size() < 2:
			continue
		# Close enough points that the road follows the rise and fall of the land.
		pts = Terrain.densify(pts, 6.0)
		var mi := MeshInstance3D.new()
		if _underground(pts):
			# Tunnels show as a dark path on the ground above them.
			var flat := PackedVector3Array()
			for p in pts:
				flat.append(Vector3(p.x, 0.05, p.z))
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			RoadMesh.add_strip(st, flat, -RoadStyle.half_width(type), RoadStyle.half_width(type), 0.1)
			mi.mesh = Terrain.drape(st.commit(), true)
			mi.material_override = _mats.tunnel
		else:
			var spec: Dictionary = RoadStyle.TYPES[type]
			var rural: bool = (_rural.has(id) or spec.get("rural", false)) and pts[pts.size() / 2].y < 1.0
			# A road that hasn't changed keeps its mesh (one edit doesn't redo
			# the whole town's streets).
			var urban := _urban.has(id)
			if urban:
				rural = false
			var key := [pts, type, rural, seg_gaps, Terrain.shift, line_cuts, breaks, urban]
			var cached: Array = _street_cache.get(id, [])
			if cached.is_empty() or cached[0] != key:
				if (sliced or not cached.is_empty()) and (Perf.now() - t0) / 1000.0 > REMESH_MS:
					# When the town edge moves, many streets turn from country
					# road to town street at once (and their corners trim
					# them); a street keeps its old look a few frames while
					# they're redrawn. A new street is drawn at once, except a
					# neighbor's, which just appears a few frames late.
					_later[id] = [key, pts, type, seg_gaps, rural, line_cuts, breaks, urban]
				else:
					cached = [key, Terrain.drape(RoadMesh.street(pts, type, _mats, seg_gaps, rural, line_cuts, breaks,
						urban))]
			if not cached.is_empty():
				street_cache[id] = cached
				mi.mesh = cached[1]
			_seg_mi[id] = mi
			if rural or urban:
				# A pole line runs down one side of a country road (on into
				# town along the highway), and down the alley behind the homes.
				pole_segs[id] = true
			if spec.get("trees", false):
				median_trees.append_array(_median_trees(id, pts, type))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var bkey := [pts, type, Terrain.shift]
			var span: Array = _bridge_cache.get(id, [])
			if span.is_empty() or span[0] != bkey:
				var pst := SurfaceTool.new()
				pst.begin(Mesh.PRIMITIVE_TRIANGLES)
				var any := RoadMesh.bridge(Terrain.lift_all(pts), RoadStyle.right_of_way_half(type), pst,
					Terrain.ground_y)
				span = [bkey, pst.commit() if any else null]
			bridge_cache[id] = span
			if span[1] != null:
				piers.append(span[1])
		add_child(mi)
	if not merges.is_empty():
		var layers := {"asphalt": SurfaceTool.new(), "white": SurfaceTool.new(), "cover": SurfaceTool.new(),
			"barrier": SurfaceTool.new()}
		for st in layers.values():
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for m in merges:
			RampMerge.draw(m, layers.asphalt, layers.white, layers.cover, layers.barrier)
		for key in layers:
			var mi := MeshInstance3D.new()
			mi.mesh = Terrain.drape(layers[key].commit())
			mi.material_override = {"white": _mats.white, "barrier": _mats.curb}.get(key, _mats.asphalt)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# Pole lines, one down each country road's whole run.
	for run in _pole_runs(pole_segs):
		var pkey := _pole_key(run, drives)
		var poles: Array = _pole_cache.get(run.id, [])
		if (poles.is_empty() or poles[0] != pkey) and (Perf.now() - t0) / 1000.0 > REMESH_MS:
			# Out of time: drawn a few frames later, the old ones up meanwhile.
			_poles_later[run.id] = [pkey, run]
		elif poles.is_empty() or poles[0] != pkey:
			poles = _draw_pole_run(pkey, run)
		if not poles.is_empty():
			pole_cache[run.id] = poles
			wood.append(poles[1])
			wire.append(poles[2])
	_add_poles(wood, wire)
	if not piers.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = _merge(piers, true)
		mi.material_override = _mats.concrete
		add_child(mi)
	_street_cache = street_cache
	_pole_cache = pole_cache
	_bridge_cache = bridge_cache
	_trees.set_trees("medians", median_trees)
	# Fill each junction and road end so curves meet cleanly; where only
	# gravel roads or alleys meet, the junction is gravel or concrete too.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low := SurfaceTool.new()  # under country roads' own pavement, so their lines show
	low.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plain := {}  # surface -> SurfaceTool
	var ring_nodes := {}
	for id in network.segments:
		if RoadStyle.is_ring(network.segments[id].type):
			var hw := RoadStyle.half_width(network.segments[id].type)
			ring_nodes[network.segments[id].a] = hw
			ring_nodes[network.segments[id].b] = hw
	for id in network.nodes:
		if network.nodes[id].y < -1.0 or ring_nodes.has(id) or (junctions.has(id) and not junctions[id].has("bend")):
			continue  # rings meet their roads without a pad over the island
		if network.segments_at(id).size() == 1:
			continue  # a dead end stops square, not in a round pad (Brawn 2026-10-24)
		if _straight_on(id) or _end_to_end(id):
			continue  # one road running straight on: no pad at the joint (Brawn 2026-10-24)
		var r := RoadStyle.half_width(network.widest_at(id))
		var surface := _junction_surface(id)
		if surface != "asphalt":
			if not plain.has(surface):
				plain[surface] = SurfaceTool.new()
				plain[surface].begin(Mesh.PRIMITIVE_TRIANGLES)
			RoadMesh.add_disc(plain[surface], network.nodes[id], r, RoadStyle.Y_JUNCTION, 24,
					Vector2(0.72, 0.0) if surface == "dirt" else Vector2.ZERO)
			continue
		if network.segments_at(id).size() == 2 and _country_node(id):
			# Two country roads meeting nearly in line: the disc only fills the
			# wedge between their ends, under their lines (no round pad).
			RoadMesh.add_disc(low, network.nodes[id], r, Junction.Y_COUNTRY, 24)
			continue
		RoadMesh.add_disc(st, network.nodes[id], r, RoadStyle.Y_JUNCTION)
	for surface in plain:
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape(plain[surface].commit())
		mi.material_override = _mats["gravel road" if surface == "gravel" else surface]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if not network.nodes.is_empty():
		for disc in [st, low]:
			var mi := MeshInstance3D.new()
			mi.mesh = Terrain.drape(disc.commit())
			mi.material_override = _mats.asphalt
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# Each corner keeps its mesh until its own plan changes.
	var junction_cache := {}
	var corners := _corner_lists()
	for node in junctions:
		var jkey := [junctions[node], Terrain.shift]
		var drawn: Array = _junction_cache.get(node, [])
		if (drawn.is_empty() or drawn[0] != jkey) and (Perf.now() - t0) / 1000.0 > REMESH_MS:
			# Out of time: drawn a few frames later, the old corner up meanwhile.
			_corners_later[node] = [jkey, junctions[node]]
			if drawn.is_empty():
				continue
		elif drawn.is_empty() or drawn[0] != jkey:
			drawn = [jkey, _corner_meshes(node, junctions[node])]
		junction_cache[node] = drawn
		for key in corners:
			corners[key].append(drawn[1][key])
	_junction_cache = junction_cache
	if not junction_cache.is_empty():
		_add_corners(corners)

	_build_roundabouts(ring_nodes)
	_build_dead_ends()
	_rebuild_drops()
	for child in old:
		# A sliced rebuild spans frames, and a piece may have gone meanwhile
		# (merged poles redone): freeing it again crashes the game.
		if is_instance_valid(child):
			child.queue_free()
	_building = false
	Perf.add(_perf_key(), slice)
	Terrain.shift = Vector2.ZERO


## The parts a junction's corner is drawn in (country corners add gravel
## and paint), each an empty list of meshes.
static func _corner_lists() -> Dictionary:
	return {"asphalt": [], "curb": [], "walk": [], "domes": [], "shoulder": [], "white": [], "yellow": [],
		"gravel road": []}


## One junction's corner pieces: {part: mesh}.
func _corner_meshes(node: int, plan) -> Dictionary:
	var parts := {}
	for key in _corner_lists():
		parts[key] = SurfaceTool.new()
		parts[key].begin(Mesh.PRIMITIVE_TRIANGLES)
	Junction.draw({node: plan}, parts.asphalt, parts.curb, parts.walk, parts.domes,
		{"shoulder": parts.shoulder, "white": parts.white, "yellow": parts.yellow, "gravel road": parts["gravel road"]})
	var meshes := {}
	for key in parts:
		meshes[key] = Terrain.drape(parts[key].commit(), false, 6.0)
	return meshes


## True when every road at a node is drawn as a country road.
func _country_node(node: int) -> bool:
	for id in network.segments_at(node):
		var spec: Dictionary = RoadStyle.TYPES[network.segments[id].type]
		if spec.oneway or not (spec.get("rural", false) or not spec.get("walk", true) or _rural.has(id)):
			return false
	return true


## For a pole line: true where a pole would stand on another road (its
## pavement and shoulder) or near a junction, where the corners flare out.
func _pole_blocked(own: Array) -> Callable:
	if _road_grid.is_empty() or _road_grid_version != _gen:
		_road_grid = StreetLights._pieces(network)
		_road_grid_version = _gen
		_junction_grid.clear()
		for n in network.nodes:
			var segs := network.segments_at(n)
			if segs.size() >= 3 or (segs.size() == 2 and not _straight_on(n)):
				var p: Vector3 = network.nodes[n]
				var c := Vector2i(floori(p.x / StreetLights.PIECE_CELL), floori(p.z / StreetLights.PIECE_CELL))
				_junction_grid[c] = _junction_grid.get(c, []) + [Vector2(p.x, p.z)]
	var grid := _road_grid
	var nodes := _junction_grid
	var mine := {}
	for s in own:
		mine[s] = true
	return func(p: Vector3) -> bool:
		var q := Vector2(p.x, p.z)
		var c := Vector2i(floori(q.x / StreetLights.PIECE_CELL), floori(q.y / StreetLights.PIECE_CELL))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for at in nodes.get(c + Vector2i(dx, dz), []):
					if q.distance_to(at) < PoleLine.CLEAR:
						return true
		for piece in grid.get(c, []):
			if mine.has(piece[2]):
				continue
			if Geometry2D.get_closest_point_to_segment(q, piece[0], piece[1]).distance_to(q) < piece[3] + 3.0:
				return true
		return false


## Country roads at grade as runs for their pole lines: segments joined
## where one carries nearly straight on into another, each in order along
## the run. Each: {"id" (its first segment), "ids", "pts" (the whole line,
## points close enough to follow the land), "ends" (Vector2: how far in
## from each end the poles start)}.
func _pole_runs(segs: Dictionary) -> Array:
	var samples := {}
	for id in segs:
		samples[id] = network.sample_segment(id)
	var next := {}  # segment -> [segments it carries straight on into]
	var nodes := {}
	for id in segs:
		nodes[network.segments[id].a] = true
		nodes[network.segments[id].b] = true
	var node_ids := nodes.keys()
	node_ids.sort()
	for n in node_ids:
		var here := []
		for id in network.segments_at(n):
			if segs.has(id):
				here.append([id, _leaving(samples[id], network.segments[id].a == n)])
		var pairs := []
		for i in here.size():
			for k in range(i + 1, here.size()):
				var d: float = (here[i][1] as Vector2).dot(here[k][1])
				if d < -0.9:
					pairs.append([d, here[i][0], here[k][0]])
		pairs.sort()
		var used := {}
		for p in pairs:
			if used.has(p[1]) or used.has(p[2]) or p[1] == p[2]:
				continue
			used[p[1]] = true
			used[p[2]] = true
			next[p[1]] = next.get(p[1], []) + [p[2]]
			next[p[2]] = next.get(p[2], []) + [p[1]]
	var ids := segs.keys()
	ids.sort()
	var runs := []
	var seen := {}
	# Open runs from an end first, then any loop that's left.
	for pass_open in [true, false]:
		for id in ids:
			if seen.has(id) or (pass_open and next.get(id, []).size() > 1):
				continue
			var run := []
			var cur: int = id
			var prev := -1
			while cur != -1 and not seen.has(cur):
				seen[cur] = true
				run.append(cur)
				var go := -1
				for o in next.get(cur, []):
					if o != prev and not seen.has(o):
						go = o
				prev = cur
				cur = go
			runs.append(_run_line(run, samples))
	return runs


## The direction a sampled segment leaves its node at (`from_a`: its a end).
static func _leaving(pts: PackedVector3Array, from_a: bool) -> Vector2:
	var p0 := pts[0] if from_a else pts[pts.size() - 1]
	var p1 := pts[mini(2, pts.size() - 1)] if from_a else pts[maxi(pts.size() - 3, 0)]
	return Vector2(p1.x - p0.x, p1.z - p0.z).normalized()


## One run's whole line, its segments joined end to end.
func _run_line(run: Array, samples: Dictionary) -> Dictionary:
	var pts := PackedVector3Array()
	var start := -1
	var end := -1
	for i in run.size():
		var sg: Dictionary = network.segments[run[i]]
		var p: PackedVector3Array = samples[run[i]].duplicate()
		var forward := true
		if i == 0:
			if run.size() > 1:
				var nx: Dictionary = network.segments[run[1]]
				forward = sg.b == nx.a or sg.b == nx.b
		else:
			forward = sg.a == end
		if not forward:
			p.reverse()
		if i == 0:
			start = sg.a if forward else sg.b
		end = sg.b if forward else sg.a
		if not pts.is_empty():
			p = p.slice(1)
		pts.append_array(p)
	var ends := Vector2(_end_margin(start), _end_margin(end))
	return {"id": run[0], "ids": run, "pts": Terrain.densify(pts, 6.0), "ends": ends}


## How far in from a run's end node its poles start: a little way at a dead
## end; at a junction, the poles keep clear of it anyway (_pole_blocked).
func _end_margin(node: int) -> float:
	return 6.0 if network.segments_at(node).size() <= 1 else 0.0


## What a run's poles are drawn from (they are redrawn when it changes).
func _pole_key(run: Dictionary, drives: Array) -> Array:
	var pts: PackedVector3Array = run.pts
	var chord := pts[pts.size() - 1] - pts[0]
	chord.y = 0.0
	if chord.length() < 5.0:
		chord = pts[mini(1, pts.size() - 1)] - pts[0]
		chord.y = 0.0
	var dir := chord.normalized() if chord.length() > 0.01 else Vector3.RIGHT
	var off := 0.0
	var three := false
	for s in run.ids:
		var type: int = network.segments[s].type
		# In the grass strip between curb and sidewalk where the road is a
		# town street, past the shoulder in the country.
		var back: float = RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5 if _urban.has(s) \
			else RoadStyle.TYPES[type].get("verge", 4.0)
		off = maxf(off, RoadStyle.half_width(type) + back)
		three = three or PoleLine.three_phase(type)
	return [pts, run.ids, PoleLine.side_for(dir) * off, run.ends, _drives_near(drives, pts), Terrain.shift, three,
		PoleLine.top_for(dir)]


## Draws one run's poles and wires: [key, wood, wire, the poles].
func _draw_pole_run(pkey: Array, run: Dictionary) -> Array:
	var w := SurfaceTool.new()
	var r := SurfaceTool.new()
	w.begin(Mesh.PRIMITIVE_TRIANGLES)
	r.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poles: Array = PoleLine.place(run.pts, pkey[2], pkey[3], pkey[4], _pole_blocked(run.ids))
	PoleLine.draw(w, r, poles, pkey[6], pkey[7])
	return [pkey, Terrain.drape(w.commit(), true), Terrain.drape(r.commit(), true), poles]


## Service drops: each home or business on a road with a pole line gets a
## wire from the nearest pole on it to its front wall, under a transformer
## can. Redone when buildings come and go.
func _rebuild_drops() -> void:
	if _drops != null and is_instance_valid(_drops):
		_drops.queue_free()
	_drops = null
	if sim == null or _pole_cache.is_empty():
		return
	Terrain.shift = Terrain.shift_for(self)
	# Every pole, in coarse cells: [pole, its line's key].
	var cell := 40.0
	var grid := {}
	for id in _pole_cache:
		var line: Array = _pole_cache[id]
		if line.size() < 4:
			continue
		for pole in line[3]:
			var b: Vector3 = pole[0]
			var c := Vector2i(floori(b.x / cell), floori(b.z / cell))
			grid[c] = grid.get(c, []) + [[pole, line[0]]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var cans := {}
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		var lot: Dictionary = sim.lots.get(key, {})
		if lot.is_empty():
			continue
		# The nearest pole (a drop runs at most about 100 ft).
		var house: Vector3 = lot.front + lot.normal * PoleLine.HOUSE_SETBACK
		var best := []
		var best_d := PoleLine.DROP_REACH
		var c0 := Vector2i(floori(house.x / cell), floori(house.z / cell))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for entry in grid.get(c0 + Vector2i(dx, dz), []):
					var b: Vector3 = entry[0][0]
					var d := Vector2(b.x - house.x, b.z - house.z).length()
					if d < best_d:
						best_d = d
						best = entry
		if best.is_empty():
			continue
		var pole: Array = best[0]
		var pkey: Array = best[1]
		var neutral: Vector3 = PoleLine.attach(pole, pkey[6], pkey[7]).back()
		var from := Vector3(neutral.x, neutral.y + Terrain.ground_y(neutral.x, neutral.z), neutral.z)
		var to := Vector3(house.x, Terrain.ground_y(house.x, house.z) + PoleLine.HOUSE_ATTACH, house.z)
		var at := Vector2i(roundi(pole[0].x), roundi(pole[0].z))
		PoleLine.drop(st, from, to, not cans.has(at))
		cans[at] = true
		any = true
	Terrain.shift = Vector2.ZERO
	if not any:
		return
	_drops = MeshInstance3D.new()
	_drops.mesh = st.commit()
	_drops.material_override = _mats.wire
	add_child(_drops)


func _add_poles(wood: Array, wire: Array) -> void:
	if wood.is_empty():
		return
	for entry in [[wood, _mats.pole], [wire, _mats.wire]]:
		var pm := MeshInstance3D.new()
		pm.mesh = _merge(entry[0])
		pm.material_override = entry[1]
		add_child(pm)
		_merged.append(pm)


func _add_corners(corners: Dictionary) -> void:
	for key in corners:
		var mi := MeshInstance3D.new()
		mi.mesh = _merge(corners[key])
		mi.material_override = _mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_merged.append(mi)


## Redraws streets left over from the last rebuild, for a few ms a frame;
## then a sliced view's poles and corners, merged again once all are drawn.
func _remesh_later() -> void:
	var t := Perf.now()
	Terrain.shift = Terrain.shift_for(self)
	for id in _later.keys():
		var job: Array = _later[id]
		_later.erase(id)
		var mi: MeshInstance3D = _seg_mi.get(id)
		if mi == null or not is_instance_valid(mi):
			continue
		var mesh := Terrain.drape(RoadMesh.street(job[1], job[2], _mats, job[3], job[4], job[5], job[6], job[7]))
		_street_cache[id] = [job[0], mesh]
		mi.mesh = mesh
		if (Perf.now() - t) / 1000.0 > REMESH_MS:
			break
	for id in _poles_later.keys():
		if (Perf.now() - t) / 1000.0 > REMESH_MS:
			break
		var job: Array = _poles_later[id]
		_poles_later.erase(id)
		_pole_cache[id] = _draw_pole_run(job[0], job[1])
		if _poles_later.is_empty() and _corners_later.is_empty():
			_remerge()
	for node in _corners_later.keys():
		if (Perf.now() - t) / 1000.0 > REMESH_MS:
			break
		var job: Array = _corners_later[node]
		_corners_later.erase(node)
		_junction_cache[node] = [job[0], _corner_meshes(node, job[1])]
		if _poles_later.is_empty() and _corners_later.is_empty():
			_remerge()
	Terrain.shift = Vector2.ZERO
	Perf.add(_perf_key(), t)


## Neighbors' roads are timed apart from your own.
func _perf_key() -> String:
	return "frame.roads_theirs" if sliced else "frame.roads"


## Poles and corners all drawn: merge them again with the late ones in.
func _remerge() -> void:
	_rebuild_drops()
	for mi in _merged:
		if is_instance_valid(mi):
			mi.queue_free()
	_merged.clear()
	var wood := []
	var wire := []
	for id in _pole_cache:
		wood.append(_pole_cache[id][1])
		wire.append(_pole_cache[id][2])
	_add_poles(wood, wire)
	if not _junction_cache.is_empty():
		var corners := _corner_lists()
		for node in _junction_cache:
			for key in corners:
				corners[key].append(_junction_cache[node][1][key])
		_add_corners(corners)


## Drives close enough to a road to move one of its poles.
static func _drives_near(drives: Array, pts: PackedVector3Array) -> Array:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	box = box.grow(40.0)
	var out := []
	for q in drives:
		if q.x >= box.position.x and q.x <= box.end.x and q.z >= box.position.z and q.z <= box.end.z:
			out.append(q)
	return out


## Joins the cached pieces into one mesh, so the town still draws them in
## one go.
static func _merge(meshes: Array, normals := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in meshes:
		if m != null and m.get_surface_count() > 0:
			st.append_from(m, 0, Transform3D.IDENTITY)
	if normals:
		st.generate_normals()
	return st.commit()


## The surface of a junction: gravel, dirt, brick or concrete only if every
## road there is. Dirt meeting gravel is gravel.
func _junction_surface(node: int) -> String:
	var surface := ""
	for seg in network.segments_at(node):
		var here: String = RoadStyle.TYPES[network.segments[seg].type].get("surface", "asphalt")
		if surface != "" and here != surface:
			if surface in ["gravel", "dirt"] and here in ["gravel", "dirt"]:
				here = "gravel"
			else:
				return "asphalt"
		surface = here
	return surface if surface != "" else "asphalt"


## Street trees down a planted median, about every 12 m (40 ft, a common
## city street tree spacing), clear of the junctions. Honey locust, maple
## and oak, the usual Midwest boulevard trees; no spruce, which would block
## drivers' view.
func _median_trees(id: int, pts: PackedVector3Array, type: int) -> Array:
	var out := []
	var hw := RoadStyle.half_width(type)
	var length := RoadNetwork.polyline_length(pts)
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 17
	var at := hw + 10.0
	while at < length - hw - 10.0:
		var p: Vector3 = LotPlanner.point_at(pts, at)[0]
		at += rng.randf_range(11.0, 13.0)
		if p.y > 1.0 or p.y < -1.0:
			continue  # on a bridge or in a tunnel
		var sp: int = [TreeField.Species.LOCUST, TreeField.Species.MAPLE, TreeField.Species.OAK][rng.randi() % 3]
		var tint: Color = TreeField.LEAF[sp].lightened(rng.randf_range(-0.05, 0.08))
		var size := rng.randf_range(0.7, 0.95) if RoadStyle.TYPES[type].median < 6.0 else rng.randf_range(0.85, 1.1)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		out.append([Transform3D(basis, Terrain.lift(Vector3(p.x, 0.0, p.z))), sp, tint])
	return out


## Post, white rail and orange rail of a Type III barricade.
const BARRICADE := [Color(0.52, 0.53, 0.52), Color(0.9, 0.9, 0.88), Color(0.93, 0.42, 0.08)]


static func _vertex_colour() -> StandardMaterial3D:
	var m := RoadStyle.material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


## A Type III barricade across every road that ends in the open (MUTCD
## 6F.68 and 2C.66: a road isn't left to stop square in the grass): a
## module of three rails, striped orange and white, across each lane, just
## past where the pavement ends. Not where a road leads off the map (it runs
## on to the horizon), on a bridge, or on a roundabout.
func _build_dead_ends() -> void:
	var links: Array = sim.region_links if sim != null else []
	# One mesh, coloured by vertex: a single draw for every barricade.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var ids := network.nodes.keys()
	ids.sort()
	for n in ids:
		var segs := network.segments_at(n)
		if segs.size() != 1 or n in links:
			continue
		var p: Vector3 = network.nodes[n]
		var sg: Dictionary = network.segments[segs[0]]
		var type: int = sg.type
		if absf(p.y) > 1.0 or RoadStyle.is_ring(type) or RoadStyle.is_freeway(type) or sg.a == sg.b:
			continue
		var pts := network.sample_segment(segs[0])
		if sg.a == n:
			pts.reverse()
		var out := pts[pts.size() - 1] - pts[pts.size() - 2]
		out.y = 0.0
		if out.length() < 0.01:
			continue
		out = out.normalized()
		var across := Vector3(-out.z, 0.0, out.x)
		var hw := RoadStyle.half_width(type)
		var lanes := maxi(1, mini(4, roundi(hw * 2.0 / 3.6)))
		var yaw := atan2(across.x, across.z) - PI * 0.5
		# Stood on the ground at the road's end (one lookup, not one a vertex).
		var at := p + out * 0.8
		var lift := Vector3(0, Terrain.ground_y(at.x, at.z), 0)
		for k in lanes:
			var off := (k + 0.5 - lanes * 0.5) * (hw * 2.0 / lanes)
			var c := p + out * 0.8 + across * off + lift
			for side in [-1.0, 1.0]:
				st.set_color(BARRICADE[0])
				RoadMesh.add_box(st, c + across * side * 1.15 + Vector3(0, 0.8, 0), Vector3(0.08, 1.6, 0.08), yaw)
			for h in [0.75, 1.1, 1.45]:
				# Striped orange, white, orange along each 2.4 m rail.
				for i in 3:
					var mid := c + across * ((i - 1) * 0.8) + Vector3(0, h, 0)
					st.set_color(BARRICADE[2] if i != 1 else BARRICADE[1])
					RoadMesh.add_box(st, mid,
						Vector3(0.8, 0.2, 0.04), yaw)
		any = true
	if not any:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mats.barricade
	add_child(mi)


## Each roundabout's planted centre island and concrete truck apron, and a
## raised splitter island on every road leading in (FHWA roundabout guide).
func _build_roundabouts(ring_nodes: Dictionary) -> void:
	var circles := {}
	for id in network.segments:
		var type: int = network.segments[id].type
		if not RoadStyle.is_ring(type):
			continue
		var c := network.curve_of(id)
		var circle := RoadShapes.arc_circle(c)
		if circle.is_empty():
			continue
		var key := Vector2i(roundi(circle[0].x), roundi(circle[0].z))
		circles[key] = [Vector3(circle[0].x, c[0].y, circle[0].z), circle[1], RoadStyle.half_width(type),
			RoadShapes.is_mini(circle[1], type)]
	if circles.is_empty():
		return
	var grass := SurfaceTool.new()
	var apron := SurfaceTool.new()
	var curb := SurfaceTool.new()
	for st in [grass, apron, curb]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in circles:
		var center: Vector3 = circles[key][0]
		var inner: float = circles[key][1] - circles[key][2]
		if circles[key][3]:
			# Mini roundabout (FHWA): no planting, the whole centre is a low
			# concrete dome that buses and trucks drive over.
			RoadMesh.add_disc(apron, center, inner, RoadStyle.Y_JUNCTION + 0.05, 48)
			_add_ring(curb, center, inner - 0.3, inner, RoadStyle.Y_JUNCTION + 0.06)
			continue
		var island := maxf(inner - RoadStyle.TRUCK_APRON, 2.0)
		_add_ring(apron, center, island, inner, RoadStyle.Y_JUNCTION + 0.03)
		_add_ring(curb, center, island - 0.3, island, RoadStyle.Y_JUNCTION + 0.08)
		RoadMesh.add_disc(grass, center, island - 0.3, RoadStyle.Y_JUNCTION + 0.1, 48)
	# Splitter islands: a raised teardrop down the middle of each approach.
	for id in network.segments:
		var s: Dictionary = network.segments[id]
		if RoadStyle.is_ring(s.type) or network.is_oneway(id) or RoadStyle.TYPES[s.type].median > 0.0:
			continue
		for end in [s.a, s.b]:
			if not ring_nodes.has(end):
				continue
			var pts := network.sample_segment(id, 32)
			if end == s.b:
				pts.reverse()
			var length := RoadNetwork.polyline_length(pts)
			var start: float = ring_nodes[end] + 1.5
			if length < start + 20.0:
				continue
			_add_splitter(curb, pts, start, 15.0, 2.0)
	for entry in [[grass, _mats.median], [apron, _mats.apron], [curb, _mats.curb]]:
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape(entry[0].commit())
		mi.material_override = entry[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


static func _add_ring(st: SurfaceTool, center: Vector3, r0: float, r1: float, y: float, steps := 48) -> void:
	var c := center + Vector3(0, y, 0)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for v in [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d0 * r0, c + d1 * r1, c + d1 * r0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## A tapering island along a road's centre line, from `start` metres out to
## `start + length`, `width` wide at the ring end.
static func _add_splitter(st: SurfaceTool, pts: PackedVector3Array, start: float, length: float, width: float) -> void:
	var cum := 0.0
	var last := []  # previous [left, right]
	for i in range(pts.size() - 1):
		var d := cum
		cum += pts[i].distance_to(pts[i + 1])
		if d < start or d > start + length:
			continue
		var dir := (pts[i + 1] - pts[i]).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var hw := maxf(width * 0.5 * (1.0 - (d - start) / length), 0.15)
		var p := pts[i] + Vector3(0, RoadStyle.Y_JUNCTION + 0.08, 0)
		var now := [p - side * hw, p + side * hw]
		if not last.is_empty():
			for v in [last[0], now[1], last[1], last[0], now[0], now[1]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		last = now


## True when the middle of a road runs below ground.
static func _underground(pts: PackedVector3Array) -> bool:
	return pts[pts.size() / 2].y < -1.0
