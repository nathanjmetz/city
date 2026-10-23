class_name RoadView
extends Node3D
## Draws the road network. Rebuilds every mesh whenever the network changes,
## which is plenty fast for a small town.
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
var _recheck := -1.0  # seconds until the town edge is checked again, or -1
var _redraw := false  # a new drive needs the poles moved
var _trees := TreeField.new()  # street trees down planted medians

var _mats := {
	"asphalt": Surfaces.asphalt(),
	"curb": Surfaces.concrete(RoadStyle.CURB_COLOR),
	"curb_face": Surfaces.concrete(RoadStyle.CURB_COLOR.darkened(0.45)),
	"walk": Surfaces.concrete(RoadStyle.SIDEWALK_COLOR, true),
	"median": Ground.grass(),
	"yellow": Surfaces.paint(RoadStyle.MARKING_YELLOW),
	"white": Surfaces.paint(RoadStyle.MARKING_WHITE),
	"gravel": Surfaces.gravel(),
	"bus": Surfaces.paint(Color(0.56, 0.17, 0.14)),  # red transit lane
	"pole": RoadStyle.material(Color(0.33, 0.27, 0.21)),
	"wire": RoadStyle.material(Color(0.12, 0.12, 0.12)),
	"concrete": Surfaces.concrete(Color(0.66, 0.65, 0.62)),
	"apron": RoadStyle.material(Color(0.5, 0.44, 0.38)),  # tinted, textured-look concrete
	"tunnel": RoadStyle.material(Color(0.1, 0.1, 0.12, 0.45), true),
	"domes": Surfaces.concrete(Junction.DOMES_COLOR),
}


func setup(net: RoadNetwork, s: CitySim = null) -> void:
	network = net
	sim = s
	network.changed.connect(rebuild)
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
	if _recheck < 0.0:
		return
	_recheck -= delta
	if _recheck < 0.0 and (_redraw or _rural_segments() != _rural):
		rebuild()


## Streets and avenues with no zoned lot, building or service near them.
func _rural_segments() -> Dictionary:
	var out := {}
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
	for id in network.segments:
		var type: int = network.segments[id].type
		if type != RoadStyle.Type.STREET and type != RoadStyle.Type.AVENUE:
			continue
		var near := false
		for p in network.sample_segment(id):
			var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if town.has(c + Vector2i(dx, dz)):
						near = true
			if near:
				break
		if not near:
			out[id] = true
	return out


func rebuild() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var t := Perf.now()
	_rebuild_all()
	Perf.add("frame.roads", t)
	Terrain.shift = Vector2.ZERO


func _rebuild_all() -> void:
	for child in get_children():
		if child != _trees:
			child.queue_free()
	if _trees.get_parent() == null:
		add_child(_trees)
	var median_trees := []
	var piers := SurfaceTool.new()
	piers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_bridge := false
	_rural = _rural_segments()
	_redraw = false
	var wood := SurfaceTool.new()
	var wire := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	wire.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_pole := false
	var drives := []  # farm lanes and company drives, kept clear of poles
	if sim != null:
		for f in sim.farms.farms.values():
			drives.append_array(f.get("drive", []))
		for c in sim.industry.sites.values():
			drives.append_array(c.get("drive", []))
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
	var junctions := Junction.plan(network, _rural)
	for id in network.segments:
		var pts := network.sample_segment(id)
		var type: int = network.segments[id].type
		var sg: Dictionary = network.segments[id]
		var ja := Junction.trim(junctions, sg.a, id)
		var jb := Junction.trim(junctions, sg.b, id)
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
			mi.mesh = Terrain.drape(RoadMesh.street(pts, type, _mats, seg_gaps, rural))
			if rural:
				# Poles run down one side of a country road, and down the
				# alley behind the homes in town.
				var side := 1.0 if hash(id) % 2 == 0 else -1.0
				RoadMesh.add_poles(wood, wire, pts, side * (RoadStyle.half_width(type) + spec.get("verge", 4.0)), drives)
				any_pole = true
			if spec.get("trees", false):
				median_trees.append_array(_median_trees(id, pts, type))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			any_bridge = RoadMesh.bridge(Terrain.lift_all(pts), RoadStyle.right_of_way_half(type), piers,
				Terrain.ground_y) or any_bridge
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
	if any_pole:
		for entry in [[wood, _mats.pole], [wire, _mats.wire]]:
			var pm := MeshInstance3D.new()
			pm.mesh = Terrain.drape(entry[0].commit(), true)
			pm.material_override = entry[1]
			add_child(pm)
	if any_bridge:
		piers.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = piers.commit()
		mi.material_override = _mats.concrete
		add_child(mi)
	_trees.set_trees("medians", median_trees)
	# Fill each junction and road end so curves meet cleanly; where only
	# gravel roads or alleys meet, the junction is gravel or concrete too.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plain := {}  # surface -> SurfaceTool
	var ring_nodes := {}
	for id in network.segments:
		if RoadStyle.is_ring(network.segments[id].type):
			var hw := RoadStyle.half_width(network.segments[id].type)
			ring_nodes[network.segments[id].a] = hw
			ring_nodes[network.segments[id].b] = hw
	for id in network.nodes:
		if network.nodes[id].y < -1.0 or ring_nodes.has(id) or junctions.has(id):
			continue  # rings meet their roads without a pad over the island
		var r := RoadStyle.half_width(network.widest_at(id))
		var surface := _junction_surface(id)
		if surface != "asphalt":
			if not plain.has(surface):
				plain[surface] = SurfaceTool.new()
				plain[surface].begin(Mesh.PRIMITIVE_TRIANGLES)
			RoadMesh.add_disc(plain[surface], network.nodes[id], r, RoadStyle.Y_JUNCTION)
			continue
		RoadMesh.add_disc(st, network.nodes[id], r, RoadStyle.Y_JUNCTION)
	for surface in plain:
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape(plain[surface].commit())
		mi.material_override = _mats[surface]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if not network.nodes.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape(st.commit())
		mi.material_override = _mats.asphalt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if not junctions.is_empty():
		var parts := {"asphalt": SurfaceTool.new(), "curb": SurfaceTool.new(), "walk": SurfaceTool.new(),
			"domes": SurfaceTool.new()}
		for p in parts.values():
			p.begin(Mesh.PRIMITIVE_TRIANGLES)
		Junction.draw(junctions, parts.asphalt, parts.curb, parts.walk, parts.domes)
		for key in parts:
			var mi := MeshInstance3D.new()
			mi.mesh = Terrain.drape(parts[key].commit(), false, 6.0)
			mi.material_override = _mats[key]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

	_build_roundabouts(ring_nodes)


## The surface of a junction: gravel or concrete only if every road there is.
func _junction_surface(node: int) -> String:
	var surface := ""
	for seg in network.segments_at(node):
		var here: String = RoadStyle.TYPES[network.segments[seg].type].get("surface", "asphalt")
		if surface != "" and here != surface:
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
		circles[key] = [Vector3(circle[0].x, c[0].y, circle[0].z), circle[1], RoadStyle.half_width(type)]
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
