class_name ServiceView
extends Node3D
## Draws service buildings (built by the art library's CivicBuilder) and
## what they reach on the streets, like Cities: Skylines: while placing one
## (with the new one's reach added), in a view, or for the one clicked.

var sim: CitySim
## The kind whose coverage to show on the roads, or -1 for none. Mail's and
## the civic hubs' place-tool kinds (Mail.TOOL_KIND, CivicHubs.TOOL_KINDS)
## show the streets the mail reaches and the land the hubs lift or drag.
var show_kind := -1:
	set(v):
		show_kind = v
		_draw_coverage()

## Road distances from where a service is about to go (Services.reach_from),
## shown on top of the built ones' while it's being placed; {} for none.
var preview := {}:
	set(v):
		preview = v
		_draw_coverage()

## A whole view of area effects on the streets: "parks" or "hubs" (landfill,
## recycling and cemetery), "" for none.
var show_area := "":
	set(v):
		show_area = v
		_draw_coverage()

## The Police view: the streets cruisers drove lately (Patrols), not reach.
var show_patrols := false:
	set(v):
		show_patrols = v
		_draw_coverage()

## The same, for the parks tool in hand: "parks" or "".
var tool_area := "":
	set(v):
		tool_area = v
		_draw_coverage()

## The one thing clicked whose reach shows instead (SelectTool's selection:
## a service, park, civic hub or post office), {} for none.
var focus := {}:
	set(v):
		focus = v
		_draw_coverage()

var _nodes := {}  # service id -> Node3D
var _coverage := MeshInstance3D.new()
var _cover_mat := StandardMaterial3D.new()
var _trees := TreeField.new()
static var _footing_mat: Material
## Parts of a site taller than this (metres) are buildings that need a
## foundation; fences, bollards and pads are lower.
const FOOTING_ABOVE := 2.4
## The last share of a service's reach counted as its edge (yellow).
const EDGE_SHARE := 0.25
## Roads are coloured in pieces about this long, metres.
const COVER_STEP := 40.0
const COVER_COLOR := Color(0.3, 0.9, 0.45, 0.75)
const EDGE_COLOR := Color(1.0, 0.82, 0.2, 0.8)
## Streets with homes or businesses on them that no station of the kind
## shown reaches, so a gap reads at a glance.
const GAP_COLOR := Color(0.92, 0.22, 0.2, 0.75)
## Area effects: land a park or cemetery lifts (green), land a landfill
## drags down (brown), strongest near it and fading out.
const LIFT_COLOR := Color(0.3, 0.9, 0.45, 0.85)
const DRAG_COLOR := Color(0.72, 0.4, 0.12, 0.9)
## Kinds that count toward another's coverage: a hospital serves as the
## town's clinic too.
const ALSO := {Services.Kind.CLINIC: [Services.Kind.HOSPITAL]}


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.lots_changed.connect(_sync)
	sim.stats_changed.connect(_draw_coverage)
	_cover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cover_mat.vertex_color_use_as_albedo = true
	_cover_mat.disable_fog = true
	_cover_mat.no_depth_test = true
	_coverage.material_override = _cover_mat
	_coverage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coverage)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		# Gone, moved with Move It, or grown onto the land next door.
		if not sim.services.buildings.has(id) or not _nodes[id].get_meta("at").is_equal_approx(
				Transform3D(Basis.looking_at(sim.services.buildings[id].dir, Vector3.UP), sim.services.buildings[id].pos)) \
				or _nodes[id].get_meta("size") != Services.size_of(sim.services.buildings[id]):
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id in sim.services.buildings:
		# A hospital that grew (or gave back) a building is drawn afresh.
		if _nodes.has(id) and _nodes[id].get_meta("look") != _look(id):
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
		if not _nodes.has(id):
			_nodes[id] = _spawn(id, sim.services.buildings[id])
	_draw_coverage()


## The ground was regraded inside `box` (view coordinates): sites reaching
## into it are drawn again on the new grade, their lots and drives with them.
func regraded(box: Rect2) -> void:
	var any := false
	for id in _nodes.keys():
		var at: Transform3D = _nodes[id].get_meta("at")
		var size: Vector2 = _nodes[id].get_meta("size")
		if box.grow(size.length() * 0.5 + 10.0).has_point(Vector2(at.origin.x, at.origin.z)):
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
			any = true
	if any:
		_sync()


func _draw_coverage() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	if not focus.is_empty():
		any = _draw_focus(st)
	elif show_patrols and show_kind == Services.Kind.POLICE and preview.is_empty():
		any = _draw_patrols(st)
	elif show_kind == Mail.TOOL_KIND:
		any = _draw_mail(st, true)
	elif CivicHubs.TOOL_KINDS.has(show_kind) or show_area == "hubs":
		any = _draw_areas(st, _hub_effects(sim.hubs.hubs.keys()))
	elif tool_area == "parks" or show_area == "parks":
		any = _draw_areas(st, _park_effects(sim.parks.sites.keys()))
	elif show_area == "mail":
		any = _draw_mail(st, true)
	elif show_kind != -1 and Services.KINDS.has(show_kind):
		var sources := []
		for kind in [show_kind] + ALSO.get(show_kind, []):
			if sim.services.reach_by_kind.has(kind):
				sources.append([sim.services.reach_by_kind[kind], float(Services.KINDS[kind].get("reach", INF))])
		if not preview.is_empty():
			sources.append([preview, float(Services.KINDS[show_kind].get("reach", INF))])
		any = _draw_reach(st, sources, Services.KINDS[show_kind].has("reach"))
	_coverage.visible = any
	if any:
		_coverage.mesh = Terrain.drape(st.commit())


## The clicked thing's own reach.
func _draw_focus(st: SurfaceTool) -> bool:
	var id = focus.get("id")
	match focus.get("type", ""):
		"service":
			if not sim.services.buildings.has(id):
				return false
			var spec: Dictionary = Services.KINDS[int(sim.services.buildings[id].kind)]
			if not spec.has("reach"):
				return false
			var reach := float(spec.reach)
			return _draw_reach(st, [[sim.services.reach_of(sim.network, id, reach), reach]], false)
		"hub":
			return sim.hubs.hubs.has(id) and _draw_areas(st, _hub_effects([id]))
		"park":
			return sim.parks.sites.has(id) and _draw_areas(st, _park_effects([id]))
		"post_office":
			return _draw_mail(st, false)
	return false


## Roads within reach light up, like Cities: Skylines 2's coverage: green
## well inside it, yellow in its last stretch (EDGE_SHARE of the reach,
## where response times run long), nothing past it. `sources` are [road
## distances (node -> metres), reach]; each piece takes the best of them.
## With `gaps`, streets with homes or businesses past every reach are red,
## so a player sees where another station would fill a gap rather than
## double up.
func _draw_reach(st: SurfaceTool, sources: Array, gaps: bool) -> bool:
	if sources.is_empty() and not gaps:
		return false
	var lined := _lined_streets() if gaps else {}
	var any := false
	for id in sim.network.segments:
		var s: Dictionary = sim.network.segments[id]
		# The ends' share of each reach (1.0 is its edge).
		var near := INF
		for src in sources:
			near = minf(near, minf(src[0].get(s.a, INF), src[0].get(s.b, INF)) / src[1])
		if near > 1.0 and not lined.has(id):
			continue
		# Coloured piece by piece: the distance along a long road grows from
		# whichever end is nearer a station, so its far part can be the edge
		# or past it.
		var pts := Terrain.densify(sim.network.sample_segment(id), COVER_STEP)
		var total := 0.0
		for i in range(1, pts.size()):
			total += pts[i - 1].distance_to(pts[i])
		var run := 0.0
		for i in range(1, pts.size()):
			var piece := pts[i - 1].distance_to(pts[i])
			var mid := run + piece * 0.5
			run += piece
			var share := INF
			for src in sources:
				var d := minf(src[0].get(s.a, INF) + mid, src[0].get(s.b, INF) + total - mid)
				share = minf(share, d / src[1])
			var color := GAP_COLOR
			if share <= 1.0:
				color = edge_color(share, 1.0)
			elif not lined.has(id):
				continue
			_piece(st, s, pts[i - 1], pts[i], color)
			any = true
	return any


## Area effects on the streets: `effects` are [centre, how far it reaches
## (metres, from the centre), Callable(Vector3) -> -1..1]. Each piece is
## tinted by their sum, green for a lift and brown for a drag, fading out.
func _draw_areas(st: SurfaceTool, effects: Array) -> bool:
	if effects.is_empty():
		return false
	var any := false
	for id in sim.network.segments:
		var s: Dictionary = sim.network.segments[id]
		# Quick out: the curve lies within its ends' and control point's
		# reach of the middle.
		var a: Vector3 = sim.network.nodes[s.a]
		var b: Vector3 = sim.network.nodes[s.b]
		var mid := (a + b) * 0.5
		var r := maxf(mid.distance_to(a), mid.distance_to(s.ctrl))
		var near := []
		for e in effects:
			if Vector2(mid.x - e[0].x, mid.z - e[0].z).length() <= r + float(e[1]):
				near.append(e)
		if near.is_empty():
			continue
		var pts := Terrain.densify(sim.network.sample_segment(id), COVER_STEP)
		for i in range(1, pts.size()):
			var p := (pts[i - 1] + pts[i]) * 0.5
			var v := 0.0
			for e in near:
				v += float(e[2].call(p))
			var color := area_color(v)
			if color.a <= 0.0:
				continue
			_piece(st, s, pts[i - 1], pts[i], color)
			any = true
	return any


## Green for a lift, brown for a drag, fading out with its strength (-1..1).
static func area_color(v: float) -> Color:
	var k := clampf(absf(v), 0.0, 1.0)
	if k < 0.04:
		return Color(0, 0, 0, 0)
	var c := LIFT_COLOR if v > 0.0 else DRAG_COLOR
	return Color(c, c.a * (0.25 + 0.75 * k))


## The landfill, recycling and cemetery hubs' pull on land value, as a share
## of a landfill's full drag.
func _hub_effects(ids: Array) -> Array:
	var out := []
	var full := absf(float(Balance.WASTE_SITES.landfill.value))
	for id in ids:
		var h: Dictionary = sim.hubs.hubs[id]
		if not Balance.WASTE_SITES.has(h.kind):
			continue
		var reach: float = sim.hubs.lift_reach(id)
		if reach <= 0.0:
			continue
		var size := 0.0
		for c in h.cells:
			size = maxf(size, (Vector2(c) + Vector2.ONE).length() * float(h.cell))
		out.append([h.pos, reach + size, func(p: Vector3) -> float: return sim.hubs.lift_from(id, p) / full])
	return out


## Parks' and landmarks' lift on land value, as a share of the most land can
## get from them.
func _park_effects(ids: Array) -> Array:
	var out := []
	for id in ids:
		var site: Dictionary = sim.parks.sites[id]
		var a: Dictionary = Balance.AMENITIES[site.kind]
		var reach: float = float(a.value_reach) * sim.parks.reach_of(id)
		var full: float = float(a.value) * sim.parks.quality(id) + sim.parks.tree_lift(id, "value")
		var k := full / Balance.AMENITY_VALUE_CAP
		out.append([site.pos, reach + Vector2(site.size).length() * 0.5,
			func(p: Vector3) -> float: return k * maxf(0.0, 1.0 - sim.parks.distance_to(id, p) / reach)])
	return out


## The streets the mail reached lately (green); with `gaps`, those with
## homes or businesses it hasn't reached are red.
func _draw_mail(st: SurfaceTool, gaps: bool) -> bool:
	var lined := _lined_streets()
	var any := false
	for id in sim.network.segments:
		var served := sim.mail.served(sim, id)
		if not served and not (gaps and lined.has(id) and not sim.mail.offices.is_empty()):
			continue
		var s: Dictionary = sim.network.segments[id]
		var pts := Terrain.densify(sim.network.sample_segment(id), COVER_STEP)
		for i in range(1, pts.size()):
			_piece(st, s, pts[i - 1], pts[i], COVER_COLOR if served else GAP_COLOR)
			any = true
	return any


## The streets police cruisers drove lately, brightest where one just went
## by and fading over a week; lined streets none has driven that long are red.
func _draw_patrols(st: SurfaceTool) -> bool:
	var lined := _lined_streets()
	var police := false
	for b in sim.services.buildings.values():
		police = police or int(b.kind) == Services.Kind.POLICE
	var any := false
	for id in sim.network.segments:
		var f := sim.patrols.freshness(sim, id)
		if f < 0.0 and not (police and lined.has(id)):
			continue
		var color := GAP_COLOR if f < 0.0 else Color(COVER_COLOR, COVER_COLOR.a * (0.3 + 0.7 * f))
		var s: Dictionary = sim.network.segments[id]
		var pts := Terrain.densify(sim.network.sample_segment(id), COVER_STEP)
		for i in range(1, pts.size()):
			_piece(st, s, pts[i - 1], pts[i], color)
			any = true
	return any


## Streets with lots on them (seg -> true): homes and businesses that need
## the service.
func _lined_streets() -> Dictionary:
	var out := {}
	for key in sim.lots:
		out[int(sim.lots[key].seg)] = true
	return out


## One piece of a street's tint, wider than the road so it reads from high up.
func _piece(st: SurfaceTool, s: Dictionary, a: Vector3, b: Vector3, color: Color) -> void:
	var hw := maxf(RoadStyle.half_width(s.type) * 1.6, 9.0)
	st.set_color(color)
	RoadMesh.add_strip(st, PackedVector3Array([a, b]), -hw, hw, 0.35)


## Green well within reach, yellow at its edge.
static func edge_color(d: float, reach: float) -> Color:
	return EDGE_COLOR if d > reach * (1.0 - EDGE_SHARE) else COVER_COLOR


## What a building looks like, so a change shows: its size, and a hospital's
## buildings.
func _look(id: int) -> String:
	var b: Dictionary = sim.services.buildings[id]
	var hub: Dictionary = sim.healthcare.hubs.get(id, {})
	return str([Services.size_of(b), hub.get("pieces", []), hub.get("level", 0), b.get("angled", false), _dev(id).size()])


## The steps of its owner's development tree a depot or cab company has built.
func _dev(id: int) -> Array:
	if sim.buses.depots.has(id):
		return sim.buses.depots[id].get("built", [])
	if sim.taxis.companies.has(id):
		return sim.taxis.companies[id].get("built", [])
	return []


func _spawn(id: int, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(b.pos)
	# Local -Z faces the road.
	root.basis = Basis.looking_at(b.dir, Vector3.UP)
	root.set_meta("at", root.transform)
	var size: Vector2 = Services.size_of(b)
	root.set_meta("size", size)
	var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	# Seeded from the front door, which stays put as a hospital grows.
	var door: Vector3 = sim.healthcare.hubs[id].front if sim.healthcare.hubs.has(id) else b.pos + b.dir * size.y * 0.5
	var seed := int(door.x * 73.0) ^ int(door.z * 151.0) ^ (int(b.kind) << 20)
	var built: Array
	if int(b.kind) in Services.PARKING:
		built = ParkingBuilder.build_lot(b, seed, to_curb)
	elif int(b.kind) in Services.CARE:
		built = HealthBuilder.build_care(int(b.kind), seed, size, to_curb, sim.healthcare.hubs.get(id, {}))
	else:
		built = CivicBuilder.build_service(int(b.kind), seed, size, to_curb, _dev(id))
	built[1] = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	# A surface lot's light poles stand on their own concrete bases.
	var surface: bool = int(b.kind) in Services.PARKING and int(b.kind) != Services.Kind.PARKING_GARAGE
	var footing: MeshInstance3D = null if surface else _footing(built[0])
	if footing != null:
		root.add_child(footing)
	root.set_meta("tree_key", str(b.pos))
	root.set_meta("look", _look(id))
	# It goes up stage by stage (ConstructionSite); trees go in at the end.
	var ref := "svc:%d" % id
	ConstructionSite.add_to(root, built, Services.profile_of(int(b.kind)), func(): return sim.construction.state(ref, sim.tick_count),
		func():
			if not is_instance_valid(root):
				return
			var frame := Transform3D(root.basis, root.position)
			var trees := []
			for t in built[2]:
				var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
				trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
			_trees.set_trees(str(b.pos), trees))
	return root


## A foundation under the site's buildings, running down into the ground on
## a slope, or null. Only under what stands taller than the fences: the yard
## itself follows the ground, as a real site's lawn and gravel do, so a
## site-wide slab doesn't show above the low side of the slope.
func _footing(building: Mesh) -> MeshInstance3D:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in building.get_surface_count():
		for v in building.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if v.y > FOOTING_ABOVE:
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	if lo.x > hi.x:
		return null
	var footing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(hi.x - lo.x + 0.4, 3.0, hi.y - lo.y + 0.4)
	footing.mesh = box
	footing.position = Vector3((lo.x + hi.x) * 0.5, -1.55, (lo.y + hi.y) * 0.5)
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	footing.material_override = _footing_mat
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return footing
