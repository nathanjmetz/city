class_name StreetLights
extends Node3D
## Streetlights along every road, the way a Midwestern town lights them:
##   - local streets: a cobra-head LED on a 30 ft wooden utility pole, one
##     side of the street, about every 200 ft and at corners
##   - avenues and boulevards: galvanised steel davit poles, staggered from
##     side to side about every 150 ft
##   - highways and ramps: 40 ft steel poles on the outside shoulder
## (Spacing and mounting heights follow common US municipal practice and
## the IES RP-8 roadway lighting guide.) The poles stand all day; at night
## the heads glow and each throws a soft warm pool on the street below:
## on the desktop a real one, drawn into LampLight's map and lighting the
## road, walks, grass and car roofs in their own colours; in the browser a
## flat glow laid on the ground. One MultiMesh per pole kind (and one for
## the browser's pools), so a whole town of lights is a handful of draw
## calls.

## 3000 K LED, the warm white most US towns chose when they replaced the
## old orange sodium lamps.
const LAMP := Color(1.0, 0.78, 0.52)
## Per road type: spacing in metres, pole kind, mounting height, arm reach,
## and whether lamps alternate sides.
const KINDS := {
	RoadStyle.Type.STREET: [62.0, "wood", 9.0, 1.8, false],
	RoadStyle.Type.AVENUE: [46.0, "steel", 10.0, 2.6, true],
	RoadStyle.Type.BOULEVARD: [46.0, "steel", 11.0, 3.0, true],
	RoadStyle.Type.HIGHWAY: [70.0, "tall", 12.0, 3.6, false],
	RoadStyle.Type.RAMP: [55.0, "tall", 12.0, 3.0, false],
	RoadStyle.Type.RING: [30.0, "steel", 9.0, 2.0, false],
	RoadStyle.Type.RING2: [30.0, "steel", 10.0, 2.4, false],
}
## No two lamps closer than this (where roads meet).
const MIN_GAP := 22.0
## How big a lamp's pool of light is on the ground, in metres across.
const POOL := 26.0

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
uniform vec4 lamp : source_color;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float f = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = lamp.rgb * f * 0.8 * smoothstep(0.25, 0.6, night);
}
"""

## The head. On the desktop a grey housing whose flat glass lens underneath
## glows at night, with a little light spilling up its sides; the browser
## keeps its whole head glowing evenly, as before.
const HEAD_SHADER := """
shader_type spatial;
global uniform float night;
uniform vec4 lamp : source_color;
void fragment() {
	float on = smoothstep(0.25, 0.6, night);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = mix(vec3(0.55, 0.55, 0.52), vec3(0.2), on);
	ROUGHNESS = 0.3;
	EMISSION = lamp.rgb * on * 6.0;
#else
	vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float lens = smoothstep(-0.5, -0.9, n.y);
	ALBEDO = mix(vec3(0.55, 0.55, 0.52), vec3(0.2), on * lens);
	ROUGHNESS = 0.3;
	EMISSION = lamp.rgb * on * mix(1.2, 14.0, lens);
#endif
}
"""

var network: RoadNetwork
## Kept for DayNight; the shaders read `night` themselves.
var visible_amount := 0.0
var _multis := {}  # mesh key or "pool" -> MultiMeshInstance3D
var _dirty := true
## The desktop's light map (null in the browser, which draws the pools).
var _map: LampLight
## Streets and avenues drawn as country roads (RoadView): unlit, like the
## county roads, with no second row of poles beside the pole line.
var country := {}
## What stands on the curb (drives' cuts, corner ramps), so no pole stands
## in them (CurbClaims; DayNight hands it the town's).
var claims: CurbClaims
var _claims_seen := -1
var _claims_wait := 0.0
const CLAIMS_EVERY := 0.5
var _meant := []  # every lamp where it was meant to stand (place without claims)
var _stood := []  # each of _meant as it stands now ([] where it has no room)
var _pieces_now := {}  # the roads in pieces (_pieces), for slid
var _redo := {}  # indices into _meant to look at again
## Times the lamps were placed again because the curb changed near one.
var claim_rebuilds := 0


func set_country(segs: Dictionary) -> void:
	country = segs
	_dirty = true


## Main streets light themselves with their own lanterns (TreatmentView):
## the roads it lights, and its lamps for the light map (as place gives).
var treated := {}
var extra := []


func set_treated(segs: Dictionary, lamps := []) -> void:
	treated = segs
	extra = lamps
	_dirty = true


func setup(net: RoadNetwork) -> void:
	network = net
	network.changed.connect(func(): _dirty = true)


func _ready() -> void:
	for type in KINDS:
		var key := mesh_key(type)
		if not _multis.has(key):
			var spec: Array = KINDS[type]
			_multis[key] = _multi(_pole_mesh(spec[1], spec[2], spec[3]), true)
	if LampLight.wanted():
		_map = LampLight.new()
		add_child(_map)
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(POOL, POOL)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _shader_mat(POOL_SHADER)
	_multis["pool"] = _multi(quad, false)


func _process(delta: float) -> void:
	if _dirty or _curb_moved(delta):
		_rebuild(_dirty)
		_dirty = false
	if _map != null:
		_map.set_amount(visible_amount)
	else:
		# The pools cost nothing to hide by day.
		_multis["pool"].visible = visible_amount > 0.0


func _multi(mesh: Mesh, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Where every lamp goes: [mesh key, base position, direction to the road,
## arm reach, mounting height]. With `claims`, a pole that would stand in a
## drive's curb cut or on a curb ramp slides along the curb to the nearest
## clear spot (up to LAMP_SLIDE either way), or is left out.
const LAMP_SLIDE := 6.0
static func place(net: RoadNetwork, skip := {}, claims: CurbClaims = null) -> Array:
	var out := []
	var taken := {}  # coarse cell -> positions, to keep lamps apart
	var pieces := _pieces(net)
	# In the order of the roads' ids, so where two lamps meet at a corner the
	# same one stands every time (a town loaded from a save lists its roads
	# in another order).
	var ids := net.segments.keys()
	ids.sort()
	for id in ids:
		_place_one(out, taken, pieces, net, id, skip, claims)
	return out


## The lamps of road `id` (place's own steps, one road at a time: `taken`
## and `pieces` carried from road to road).
static func _place_one(out: Array, taken: Dictionary, pieces: Dictionary, net: RoadNetwork, id: int, skip: Dictionary,
		claims: CurbClaims) -> void:
	var seg: Dictionary = net.segments[id]
	var type: int = seg.type
	# Variants light like their menu's road; country roads and alleys go unlit.
	var kind := RoadStyle.group(type) if not RoadStyle.is_ring(type) else type
	if not KINDS.has(kind) or RoadStyle.TYPES[type].get("rural", false) or skip.has(id):
		return
	var spec: Array = KINDS[kind]
	var pts := net.sample_segment(id)
	if pts[pts.size() / 2].y < -1.0:
		return  # tunnel
	var length := RoadNetwork.polyline_length(pts)
	var out_by := RoadStyle.half_width(type) + (1.2 if RoadStyle.is_freeway(type) else RoadStyle.CURB_WIDTH + 0.6)
	# Start half a gap in, so corners get a lamp from one road or the
	# other but never one standing in the crossing street.
	var n := maxi(int(floorf(length / spec[0])), 1)
	for i in n:
		var along := (i + 0.5) * length / n
		var p := _at(pts, along)
		var side := 1.0
		if spec[4] and i % 2 == 1:
			side = -1.0
		var fwd: Vector3 = p[1]
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var base: Vector3 = p[0] + right * side * out_by
		if _near(taken, base) or _on_other_road(pieces, base, id):
			continue
		var cell := Vector2i(floori(base.x / MIN_GAP), floori(base.z / MIN_GAP))
		if not taken.has(cell):
			taken[cell] = []
		taken[cell].append(base)
		var lamp := [mesh_key(kind), base, -right * side, spec[3], spec[2], fwd, id]
		if claims != null:
			lamp = slid(lamp, claims, pieces)
			if lamp.is_empty():
				continue
		out.append(lamp)


## A lamp (as place gives it, where it was meant to stand) slid along its
## curb off any drive's cut or curb ramp (CurbClaims), up to LAMP_SLIDE
## either way, and not onto another road; [] when nowhere is clear. Each
## lamp on its own (their spacing is kept where they were meant to stand),
## so one can be looked at again alone.
static func slid(lamp: Array, claims: CurbClaims, pieces: Dictionary) -> Array:
	var base: Vector3 = lamp[1]
	var fwd: Vector3 = lamp[5]
	var q := claims.slide(Vector2(base.x, base.z), Vector2(fwd.x, fwd.z).normalized(), 0.35, LAMP_SLIDE, LAMP_SLIDE)
	if not q.is_finite():
		return []
	var out := lamp.duplicate()
	out[1] = Vector3(q.x, base.y, q.y)
	if _on_other_road(pieces, out[1], int(lamp[6])):
		return []
	return out


static func mesh_key(type: int) -> String:
	var spec: Array = KINDS[type]
	return "%s_%d_%d" % [spec[1], roundi(spec[2] * 10.0), roundi(spec[3] * 10.0)]


## Point and direction `along` metres down a polyline.
static func _at(pts: PackedVector3Array, along: float) -> Array:
	var left := along
	for i in range(1, pts.size()):
		var d := pts[i].distance_to(pts[i - 1])
		if left <= d or i == pts.size() - 1:
			var f := clampf(left / maxf(d, 0.001), 0.0, 1.0)
			var dir := pts[i] - pts[i - 1]
			dir.y = 0.0
			return [pts[i - 1].lerp(pts[i], f), dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD]
		left -= d
	return [pts[pts.size() - 1], Vector3.FORWARD]


static func _near(taken: Dictionary, p: Vector3) -> bool:
	var c := Vector2i(floori(p.x / MIN_GAP), floori(p.z / MIN_GAP))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q in taken.get(c + Vector2i(dx, dz), []):
				if Vector2(q.x - p.x, q.z - p.z).length() < MIN_GAP:
					return true
	return false


const PIECE_CELL := 32.0


## Every road as short straight pieces in a coarse grid: [a, b, segment,
## half width], for quick "is this spot on a road" checks.
static func _pieces(net: RoadNetwork) -> Dictionary:
	var grid := {}
	for id in net.segments:
		_pieces_of(grid, net, id)
	return grid


## Road `id`'s pieces filed in `grid` (_pieces, one road at a time).
static func _pieces_of(grid: Dictionary, net: RoadNetwork, id: int) -> void:
	var hw := RoadStyle.half_width(net.segments[id].type)
	var pts := net.sample_segment(id)
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1].x, pts[i - 1].z)
		var b := Vector2(pts[i].x, pts[i].z)
		var lo := Vector2i(floori((minf(a.x, b.x) - hw) / PIECE_CELL), floori((minf(a.y, b.y) - hw) / PIECE_CELL))
		var hi := Vector2i(floori((maxf(a.x, b.x) + hw) / PIECE_CELL), floori((maxf(a.y, b.y) + hw) / PIECE_CELL))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var c := Vector2i(x, z)
				if not grid.has(c):
					grid[c] = []
				grid[c].append([a, b, id, hw])


## True when a pole would stand on another road's pavement or curb.
static func _on_other_road(grid: Dictionary, p: Vector3, own: int, margin := 1.0) -> bool:
	var q := Vector2(p.x, p.z)
	for piece in grid.get(Vector2i(floori(q.x / PIECE_CELL), floori(q.y / PIECE_CELL)), []):
		if piece[2] == own:
			continue
		var c := Geometry2D.get_closest_point_to_segment(q, piece[0], piece[1])
		if c.distance_to(q) < piece[3] + margin:
			return true
	return false


## True when the curb changed (CurbClaims) near where a lamp was meant to
## stand, looked at every CLAIMS_EVERY seconds: a drive or corner ramp
## built away from every lamp moves none and redraws nothing.
func _curb_moved(delta: float) -> bool:
	_claims_wait -= delta
	if claims == null or _claims_wait > 0.0:
		return false
	_claims_wait = CLAIMS_EVERY
	var now := claims.stamp()
	if now == _claims_seen:
		return false
	var boxes := claims.changes_since(_claims_seen)
	_claims_seen = now
	_redo.clear()
	var reach := boxes.map(func(r): return (r as Rect2).grow(LAMP_SLIDE + 1.0))
	for i in _meant.size():
		var m: Vector3 = _meant[i][1]
		if reach.any(func(r): return (r as Rect2).has_point(Vector2(m.x, m.z))):
			_redo[i] = true
	if not _redo.is_empty():
		claim_rebuilds += 1
	return not _redo.is_empty()


## `all`: every lamp placed again (the roads changed); otherwise only those
## the curb changed beside (_redo), each slid again on its own.
func _rebuild(all := true) -> void:
	var lists := {}
	for k in _multis:
		lists[k] = []
	_claims_seen = claims.stamp() if claims != null else -1
	if all or _meant.is_empty():
		_meant = place(network, country.merged(treated))
		_pieces_now = _pieces(network)
		_redo.clear()
		for i in _meant.size():
			_redo[i] = true
		_stood.resize(_meant.size())
	var moved := false
	for i in _redo:
		var l: Array = slid(_meant[i], claims, _pieces_now) if claims != null else _meant[i]
		if l != _stood[i]:
			_stood[i] = l
			moved = true
	_redo.clear()
	if not all and not moved:
		return  # nothing moved (a building went up beside a lamp that had room)
	var lamps := _stood.filter(func(l): return l != null and not (l as Array).is_empty())
	for l in lamps:
		var dir: Vector3 = l[2]
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
		lists[l[0]].append(Transform3D(basis, Terrain.lift(l[1])))
		if lists.has("pool"):
			var under: Vector3 = l[1] + dir * (float(l[3]) + 1.5)
			lists.pool.append(Transform3D(Basis.IDENTITY, Terrain.lift(Vector3(under.x, l[1].y + RoadStyle.Y_JUNCTION + 0.03, under.z))))
	if _map != null:
		_map.draw(lamps + extra)
	for k in lists:
		var mm: MultiMesh = _multis[k].multimesh
		mm.instance_count = lists[k].size()
		for i in lists[k].size():
			mm.set_instance_transform(i, lists[k][i])


## A pole `h` metres to the lamp with an arm reaching `reach` metres out
## along +Z, and the lamp head at the arm's end as a second surface.
static func _pole_mesh(kind: String, h: float, reach: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := kind == "wood"
	var top := h + (1.2 if wood else 0.2)
	_prism(st, Vector3.ZERO, Vector3(0, top, 0), 0.15 if wood else 0.11, 0.11 if wood else 0.08)
	# The arm rises gently out over the road.
	_prism(st, Vector3(0, h - 0.35, 0), Vector3(0, h, reach), 0.05, 0.05)
	if wood:
		# A crossarm near the top carrying the power lines.
		_prism(st, Vector3(-1.2, h + 0.9, 0), Vector3(1.2, h + 0.9, 0), 0.06, 0.06)
	var mesh := ArrayMesh.new()
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(0, _pole_material(kind))
	# Cobra head: a flat, rounded box at the arm's end.
	var head := SurfaceTool.new()
	head.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(head, Vector3(0, h - 0.06, reach + 0.25), Vector3(0.36, 0.16, 0.75))
	head.generate_normals()
	head.commit(mesh)
	mesh.surface_set_material(1, _shader_mat(HEAD_SHADER))
	return mesh


## An eight-sided post from a to b, tapering from radius r0 to r1.
static func _prism(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var axis := (b - a).normalized()
	var u := Vector3(1, 0, 0) if absf(axis.x) < 0.9 else Vector3(0, 1, 0)
	var v := axis.cross(u).normalized()
	u = v.cross(axis).normalized()
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var o0 := u * cos(a0) + v * sin(a0)
		var o1 := u * cos(a1) + v * sin(a1)
		for p in [a + o0 * r0, b + o0 * r1, b + o1 * r1, a + o0 * r0, b + o1 * r1, a + o1 * r0]:
			st.add_vertex(p)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
		[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)],
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
	]
	for f in faces:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + f[i] * h)


static func _pole_material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if kind == "wood":
		m.albedo_color = Color(0.29, 0.22, 0.16)  # creosote-treated pine, weathered
		m.roughness = 0.95
	else:
		m.albedo_color = Color(0.6, 0.61, 0.6)  # galvanised steel
		m.roughness = 0.5
		m.metallic = 0.5
	return m


static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("lamp", LAMP)
	return m
