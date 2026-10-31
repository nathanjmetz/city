class_name TreatmentView
extends Node3D
## What a treated street side has standing on it (RoadTreatments), desktop
## only (the browser gets the pavement and walks, which RoadMesh draws, and
## none of this):
##   - Main street: black cast-iron acorn lanterns on 12 ft posts every
##     60 ft along the curb (Marion's courthouse square and Gas City's Main
##     Street use the type; wires buried, so no wooden poles), and a bench
##     and a litter bin now and then. (Trees in grates wait: 700 of them down
##     the test town's main streets cost 400,000 triangles, past the spec's
##     budget; they come with the state layer's near ring.)
##   - Factory: NO PARKING signs (MUTCD R7-1: red on white, 12 x 18 in, on a
##     7 ft post) along the curb every 150 ft. The wooden poles with their
##     cobra heads stay, as StreetLights draws them.
## A road with a main street side gives up its StreetLights pole; a side
## across from a main street that isn't one keeps a cobra head on a wooden
## pole here instead.
## Lanterns, poles and their pools are one MultiMesh each, everywhere. The
## small things (signs, benches, bins) are merged per 128 m square
## and drawn within NEAR of the camera, at High and up.

const SQUARE := 128.0
const NEAR := 160.0
## Lanterns 60 ft apart, 0.6 m in from the curb's back.
const LANTERN_GAP := 18.0
const LANTERN_IN := 0.6
const SIGN_GAP := 46.0
## Lantern post to the top of its globe (12 ft to the light centre).
const LANTERN_H := 3.7
const POOL := 13.0
## Half each thing's footprint on the curb, and how far it may slide along
## it to find a free spot.
const LANTERN_HALF := 0.3
const BENCH_HALF := 0.9
const BIN_HALF := 0.3
const SIGN_HALF := 0.2
const SLIDE := 4.0
## How often (s) the view asks whether the curb's claims changed.
const CLAIMS_EVERY := 1.0

const LANTERN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
global uniform float night;
void fragment() {
	float glass = 1.0 - COLOR.a;
	float on = smoothstep(0.25, 0.6, night);
	ALBEDO = mix(COLOR.rgb, vec3(0.85, 0.8, 0.68), glass * (0.4 + 0.4 * on));
	ROUGHNESS = mix(0.45, 0.2, glass);
	EMISSION = vec3(1.0, 0.78, 0.52) * glass * on * 5.0;
}
"""

var sim: CitySim
var lamps: StreetLights
var _lanterns: MultiMeshInstance3D
var _cobras: MultiMeshInstance3D
var _pools: MultiMeshInstance3D
var _squares := {}  # Vector2i -> MeshInstance3D
var _square_props := {}  # Vector2i -> the things it was merged from
var _parts := {}  # plan's cache: road piece -> [key, part]
var _mat: StandardMaterial3D
var _dirty := true
var _near_on := false
var _claims_seen := -1
var _claims_wait := 0.0


func setup(s: CitySim, street_lights: StreetLights) -> void:
	sim = s
	lamps = street_lights
	sim.treatments.changed.connect(func(_segs): _dirty = true)
	sim.network.changed.connect(func(): _dirty = true)


func _ready() -> void:
	var lantern := ShaderMaterial.new()
	lantern.shader = Shader.new()
	lantern.shader.code = LANTERN_SHADER
	var mesh := lantern_mesh()
	mesh.surface_set_material(0, lantern)
	_lanterns = _multi(mesh, false)  # a slim post: its shadow is not worth a second pass
	_cobras = _multi(StreetLights._pole_mesh("wood", 9.0, 1.8), true)
	var quad := QuadMesh.new()
	quad.size = Vector2(POOL, POOL)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = StreetLights._shader_mat(StreetLights.POOL_SHADER)
	_pools = _multi(quad, false)


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


func _process(delta: float) -> void:
	_claims_wait -= delta
	if _claims_wait <= 0.0 and sim != null:
		_claims_wait = CLAIMS_EVERY
		var claims := CurbClaims.of(sim)
		var now := claims.stamp()
		if now != _claims_seen:
			var boxes := claims.changes_since(_claims_seen)
			_claims_seen = now
			_forget_near(boxes)
	var near := RoadView.curbs_wanted()
	if near != _near_on:
		_near_on = near
		_dirty = true
	if _dirty and not LoadGate.loading:
		_dirty = false
		var t := Perf.now()
		_rebuild()
		Perf.add("frame.treatments", t)
	if _pools != null and lamps != null:
		_pools.visible = lamps.visible_amount > 0.0


## The curb's claims changed in these places (Rect2s; [] for anywhere): the
## roads by them are worked out again.
func _forget_near(boxes: Array) -> void:
	if _parts.is_empty():
		return
	for id in _parts.keys():
		var c: Array = _parts[id][0][3]
		var box := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)) \
			.expand(Vector2(c[2].x, c[2].z)).grow(20.0)
		if boxes.is_empty() or boxes.any(func(b): return (b as Rect2).intersects(box)):
			_parts.erase(id)
			_dirty = true


## Where everything stands: {"lanterns", "cobras", "pools": [Transform3D],
## "props": {square: [[kind, Transform3D]]},
## "skip": road pieces StreetLights leaves to us}. `cache` (road piece ->
## [what it was worked out from, its part]) keeps each road's part until
## its shape or sides change.
static func plan(s: CitySim, cache := {}) -> Dictionary:
	var out := {"lanterns": [], "cobras": [], "pools": [], "lamps": [], "props": {}, "skip": {}}
	var t: RoadTreatments = s.treatments
	var segs := {}
	for k in t.sides:
		segs[int(k) >> 1] = true
	var ids := segs.keys()
	ids.sort()
	var kept := {}
	for id in ids:
		if not s.network.segments.has(id):
			continue
		var key := [s.network.segments[id].type, t.kind(id, -1), t.kind(id, 1), s.network.curve_of(id)]
		var had: Array = cache.get(id, [])
		var part: Dictionary = had[1] if not had.is_empty() and had[0] == key else _road_part(s, id)
		kept[id] = [key, part]
		for k in ["lanterns", "cobras", "pools", "lamps"]:
			out[k].append_array(part[k])
		for e in part.props:
			_prop(out.props, e[0], e[1])
		if part.skip:
			out.skip[id] = true
	cache.clear()
	cache.merge(kept)
	return out


## One road piece's lanterns, poles and props.
static func _road_part(s: CitySim, id: int) -> Dictionary:
	var out := {"lanterns": [], "cobras": [], "pools": [], "lamps": [], "props": [], "skip": false}
	var t: RoadTreatments = s.treatments
	var type: int = s.network.segments[id].type
	var spec: Dictionary = RoadStyle.TYPES[type]
	if spec.get("rural", false) or RoadStyle.is_freeway(type):
		return out
	if not (t.kind(id, -1) in RoadTreatments.DRAWN or t.kind(id, 1) in RoadTreatments.DRAWN):
		return out
	var pts := s.network.sample_segment(id)
	if absf(pts[pts.size() / 2].y) > 1.0:
		return out  # a bridge or a tunnel
	var length := RoadNetwork.polyline_length(pts)
	var hw := RoadStyle.half_width(type)
	var back := hw + RoadStyle.CURB_WIDTH
	var main := t.kind(id, -1) == RoadTreatments.MAIN or t.kind(id, 1) == RoadTreatments.MAIN
	out.skip = main
	# Everything here is curb furniture: it stands only where the curb is
	# free (CurbClaims: off drive cuts, curb ramps and crosswalks), slid
	# along the curb to the nearest free spot, or left out.
	var claims := CurbClaims.of(s)
	for side in [-1, 1]:
		var kind := t.kind(id, side)
		var start := hw + 9.0
		var stop := length - hw - 9.0
		if kind == RoadTreatments.MAIN:
			var n := maxi(int((stop - start) / LANTERN_GAP), 0)
			for i in n + 1:
				var d := start + (stop - start) * (float(i) / maxf(n, 1))
				var at := _free(claims, pts, d, side, back + LANTERN_IN, LANTERN_HALF, SLIDE)
				if not at.is_empty():
					out.lanterns.append(at[0])
					out.pools.append(_pool(at[0], at[1], 1.4, 1.0))
					out.lamps.append(_lamp(at, 0.3, LANTERN_H + 0.45))
				if i % 2 == 1 and i < n:
					var bench := _free(claims, pts, d + 3.0, side, back + LANTERN_IN + 0.2, BENCH_HALF, SLIDE)
					if not bench.is_empty():
						out.props.append(["bench", bench[0]])
					var bin := _free(claims, pts, d - 1.6, side, back + LANTERN_IN, BIN_HALF, SLIDE)
					if not bin.is_empty():
						out.props.append(["bin", bin[0]])
		elif kind == RoadTreatments.FACTORY:
			var n := maxi(int((stop - start) / SIGN_GAP), 0)
			for i in n + 1:
				var d := start + (stop - start) * (float(i) / maxf(n, 1))
				var sign := _free(claims, pts, d, side, back + 0.3, SIGN_HALF, SLIDE)
				if not sign.is_empty():
					out.props.append(["no_parking", sign[0]])
		if main and kind != RoadTreatments.MAIN:
			# The other side keeps a cobra head on a wooden pole, one a block.
			var n := maxi(int(length / 62.0), 1)
			for i in n:
				var at := _free(claims, pts, (i + 0.5) * length / n, side, back + 0.3, LANTERN_HALF, SLIDE)
				if at.is_empty():
					continue
				out.cobras.append(at[0])
				out.pools.append(_pool(at[0], at[1], 3.3, 2.0))
				out.lamps.append(_lamp(at, 1.8, 9.0))
	return out


## [where a thing stands, facing the road], `d` metres along, `off` metres
## out on `side`.
static func _spot(pts: PackedVector3Array, d: float, side: int, off: float) -> Array:
	var at: Array = LotPlanner.point_at(pts, d)
	var dir: Vector3 = at[1]
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var out := Vector3(-dir.z, 0.0, dir.x) * float(side)
	var p: Vector3 = at[0] + out * off
	var face := -out  # toward the street
	return [Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), Terrain.lift(Vector3(p.x, 0.0, p.z))), face]


## _spot, slid along the curb to where it is free (CurbClaims), or [] if
## nothing within `slide` metres either way is.
static func _free(claims: CurbClaims, pts: PackedVector3Array, d: float, side: int, off: float, half: float,
		slide: float) -> Array:
	var at := _spot(pts, d, side, off)
	if claims == null:
		return at
	var o: Vector3 = at[0].origin
	var along: Vector3 = Vector3(at[1].z, 0.0, -at[1].x)  # down the curb
	var q := claims.slide(Vector2(o.x, o.z), Vector2(along.x, along.z).normalized(), half, slide, slide)
	if q == Vector2.INF:
		return []
	if q != Vector2(o.x, o.z):
		at[0] = Transform3D(at[0].basis, Terrain.lift(Vector3(q.x, 0.0, q.y)))
	return at


## A pool of light on the street `reach` metres out from a lamp, `scale`
## times the lantern's pool.
static func _pool(lamp: Transform3D, face: Vector3, reach: float, scale: float) -> Transform3D:
	var p := lamp.origin + face * reach
	return Transform3D(Basis.IDENTITY.scaled(Vector3(scale, 1.0, scale)),
		Vector3(p.x, p.y + RoadStyle.Y_JUNCTION + 0.03, p.z))


## A lamp for the light map (LampLight), as StreetLights.place gives them:
## [kind, base on the ground, toward the road, arm reach, mounting height].
static func _lamp(at: Array, reach: float, h: float) -> Array:
	var p: Vector3 = at[0].origin
	return ["treat", Vector3(p.x, 0.0, p.z), at[1], reach, h]


static func _prop(props: Dictionary, kind: String, at: Transform3D) -> void:
	var sq := Vector2i(floori(at.origin.x / SQUARE), floori(at.origin.z / SQUARE))
	if not props.has(sq):
		props[sq] = []
	props[sq].append([kind, at])


func _rebuild() -> void:
	var p := plan(sim, _parts)
	if lamps != null and (p.skip != lamps.treated or p.lamps != lamps.extra):
		lamps.set_treated(p.skip, p.lamps)
	# Where the desktop's light map lights the ground, the flat pools go.
	if lamps != null and lamps._map != null:
		p.pools = []
	for pair in [[_lanterns, p.lanterns], [_cobras, p.cobras], [_pools, p.pools]]:
		var mm: MultiMesh = pair[0].multimesh
		mm.instance_count = pair[1].size()
		for i in pair[1].size():
			mm.set_instance_transform(i, pair[1][i])
	if not _near_on:
		p.props = {}
	# Only the squares whose things changed are merged again.
	for sq in _squares.keys():
		if not p.props.has(sq) or p.props[sq] != _square_props.get(sq):
			_squares[sq].queue_free()
			_squares.erase(sq)
			_square_props.erase(sq)
	if _mat == null:
		_mat = RoadView._vertex_colour()
	for sq in p.props:
		if _squares.has(sq):
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in p.props[sq]:
			_add_prop(st, e[0], e[1])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat
		mi.visibility_range_end = NEAR
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		_squares[sq] = mi
		_square_props[sq] = p.props[sq]


# ------------------------------------------------------------------ meshes

const IRON := Color(0.06, 0.07, 0.065)
const STEEL := Color(0.55, 0.56, 0.55)
const SIGN_WHITE := Color(0.92, 0.92, 0.9)
const SIGN_RED := Color(0.72, 0.08, 0.08)
const SLAT := Color(0.24, 0.27, 0.22)


## An acorn lantern: a fluted base, a slim post and a glass acorn globe
## under a black finial (alpha 0 marks the glass, which glows at night).
## Six-sided, about 60 triangles, as every lantern in town is drawn
## wherever one shows.
static func lantern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_post(st, Vector3.ZERO, Vector3(0, 0.7, 0), 0.16, 0.08, IRON)
	_post(st, Vector3(0, 0.7, 0), Vector3(0, LANTERN_H, 0), 0.06, 0.12, IRON)
	var glass := Color(0.9, 0.86, 0.72, 0.0)
	_post(st, Vector3(0, LANTERN_H, 0), Vector3(0, LANTERN_H + 0.35, 0), 0.2, 0.22, glass)
	_post(st, Vector3(0, LANTERN_H + 0.35, 0), Vector3(0, LANTERN_H + 0.62, 0), 0.22, 0.06, glass)
	_post(st, Vector3(0, LANTERN_H + 0.6, 0), Vector3(0, LANTERN_H + 0.78, 0), 0.07, 0.01, IRON)
	st.generate_normals()
	return st.commit()


static func _add_prop(st: SurfaceTool, kind: String, at: Transform3D) -> void:
	match kind:
		"no_parking":
			_box(st, at, Vector3(0, 1.05, 0), Vector3(0.06, 2.1, 0.06), STEEL)
			# The plate faces along the curb, both ways, as R7 signs do
			# (MUTCD 2B.46: at an angle to the curb, readable to drivers).
			var face := Transform3D(at.basis * Basis(Vector3.UP, PI * 0.5), at.origin)
			_box(st, face, Vector3(0, 2.0, 0.04), Vector3(0.3, 0.45, 0.02), SIGN_WHITE)
			for k in 3:
				_box(st, face, Vector3(0, 2.13 - k * 0.12, 0.052), Vector3(0.22, 0.05, 0.004), SIGN_RED)
		"bench":
			# Park bench facing the street: cast iron ends, steel slats.
			for x in [-0.75, 0.75]:
				_box(st, at, Vector3(x, 0.3, 0), Vector3(0.06, 0.6, 0.5), IRON)
			_box(st, at, Vector3(0, 0.45, 0.02), Vector3(1.6, 0.05, 0.42), SLAT)
			_box(st, at, Vector3(0, 0.75, -0.2), Vector3(1.6, 0.4, 0.04), SLAT)
		"bin":
			_box(st, at, Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.5), Color(0.08, 0.1, 0.09))


static func _box(st: SurfaceTool, at: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for k in 8:
		v.append(at * (c + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)))
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(v[f[i]])


## A six-sided post from a to b, radius r0 to r1, in one colour.
static func _post(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		for p in [a + o0 * r0, b + o1 * r1, b + o0 * r1, a + o0 * r0, a + o1 * r0, b + o1 * r1]:
			st.set_color(col)
			st.add_vertex(p)
