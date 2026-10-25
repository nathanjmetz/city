class_name FarmsteadFar
extends RefCounted
## The far farmstead: what a farm looks like from a mile off, grown from its
## plan (FarmsteadPlan) in a few hundred triangles. Farmsteads are mostly
## seen from far away, so this is the version that matters most: the white
## house and its dark roof, the red, white or grey barn under its gambrel or
## gable, the bright cluster of steel bins and the dryer leg over them, long
## low pole barns, a grey stave silo, the dark rows of the windbreak on the
## north and west, a pale gravel yard and lane, and at night the yard light.
## Many farmsteads are batched into one mesh (FarmsteadView's blocks); each
## vertex carries its farmstead's anchor in UV2, so the shader can hand one
## farmstead over to its close-up (FarmsteadNear) with a dither.
##
## Vertex colours are sRGB. Alpha tells the shader what a face is: about
## 0.2 a lived-in house wall (windows, lit at night), 0.08 an empty house's
## wall (dark windows), 0.6 the grounds' grass, 0.75 the gravel, 0.9 a tree,
## 0 anything else. UV is metres along and up a house wall, for its window grid.

const TREE_ALPHA := 0.9
const LAWN_ALPHA := 0.6
const GRAVEL_ALPHA := 0.75
## Up to this many farmsteads can be handed over at once (see near_spots).
const SPOTS := 16

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
global uniform float night;
global uniform float snow;
global uniform float windows_lit;
global uniform vec4 season_look;
// Farmsteads drawn close up (FarmsteadNear): xy their anchor (view x, z),
// z how far the buildings have handed over (1 gone), w the trees.
uniform vec4 near_spots[16];
varying vec3 world_pos;
varying vec3 world_normal;
varying float hide;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hide = 0.0;
	float tree = step(0.85, COLOR.a);
	// The lawn and the gravel go the moment their close-up stands (it
	// draws the same ground, a little finer): never both, so they can't
	// fight over the same depth.
	float ground = step(0.55, COLOR.a) * step(COLOR.a, 0.8);
	for (int i = 0; i < 16; i++) {
		vec4 s = near_spots[i];
		if (distance(UV2, s.xy) < 0.5) {
			hide = mix(mix(s.z, s.w, tree), step(0.001, s.z), ground);
		}
	}
	if (hide > 0.999) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	if (hide > 0.001) {
		// Ordered dither: a farmstead fades out while its close-up comes in.
		vec2 q = mod(floor(FRAGCOORD.xy), 4.0);
		float b = (mod(q.x + q.y * 2.0, 4.0) * 4.0 + mod(q.x * 2.0 + q.y, 4.0) + 0.5) / 16.0;
		if (hide > b) {
			discard;
		}
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 base = COLOR.rgb;
#else
	vec3 base = lin(COLOR.rgb);
#endif
	// The farmstead's mown grass goes dormant and tan in a dry or cold spell.
	float lawn = step(0.55, COLOR.a) * step(COLOR.a, 0.65);
	base = mix(base, vec3(0.28, 0.22, 0.12), lawn * clamp(season_look.w * 1.1, 0.0, 0.85));
	float house = step(0.04, COLOR.a) * step(COLOR.a, 0.5);
	float lived = step(0.12, COLOR.a) * house;
	// A house's windows: 2 m bays, 3.7 m storeys, too small to draw far off
	// (then an even darkening).
	float fy = fract(UV.y / 3.0);
	float fx = fract(UV.x / 2.2);
	float aa = clamp(1.0 / max(fwidth(UV.x) * 2.0, 0.001), 0.0, 1.0);
	float win = step(0.35, fy) * step(fy, 0.8) * step(0.3, fx) * step(fx, 0.7) * house;
	win = mix(house * 0.12, win, aa);
	vec3 glass = vec3(0.03, 0.035, 0.04) + vec3(0.05, 0.06, 0.07) * (1.0 - night * 0.85);
	float up = smoothstep(0.35, 0.6, world_normal.y);
	float cover = up * smoothstep(0.15, 0.55, snow) * (1.0 - win);
	ALBEDO = mix(mix(base, glass, win), vec3(0.86, 0.88, 0.92), cover * mix(1.0, 0.5, step(0.85, COLOR.a)));
	ROUGHNESS = mix(0.85, 0.2, win);
	SPECULAR = 0.3;
	vec2 cell = floor(vec2(UV.x / 2.2, UV.y / 3.0)) + floor(world_pos.xz / 40.0);
	float on = step(hash(cell), windows_lit * 1.2) * smoothstep(0.2, 0.6, night) * lived;
	EMISSION = vec3(1.0, 0.7, 0.42) * on * win * 1.6;
}
"""

## A yard light seen from afar: a glow that stays a few pixels across at
## any distance, dimmed by the haze, lit from dusk to dawn.
const GLOW := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
uniform vec4 near_spots[16];
varying float hide;
varying float fade;
void vertex() {
	hide = 0.0;
	for (int i = 0; i < 16; i++) {
		vec4 s = near_spots[i];
		if (distance(UV2, s.xy) < 0.5) {
			hide = s.z;
		}
	}
	vec4 at = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(at.xyz);
	// About 2.5 pixels of a 900-pixel-high view, never under 0.8 m.
	float size = max(0.8, d * 0.0035);
	at.xy += (UV * 2.0 - 1.0) * size;
	fade = exp(-d / 7000.0) * (1.0 - hide);
	POSITION = PROJECTION_MATRIX * at;
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * core * 2.4 * fade * smoothstep(0.25, 0.6, night);
}
"""

static var _mat: ShaderMaterial
static var _glow: ShaderMaterial
## The spots last handed to the shaders (they are set only when they change).
static var _spots: Array = []
## Tests: act as the browser build does.
static var force_web := false


## Whether this is the browser build (lighter farmsteads, fewer close-ups).
static func web() -> bool:
	return force_web or OS.has_feature("web")


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_spots = [Vector4.ONE]  # not the empty list: set it for the first time
		clear_spots()
	return _mat


static func glow_material() -> ShaderMaterial:
	if _glow == null:
		var sh := Shader.new()
		sh.code = GLOW
		_glow = ShaderMaterial.new()
		_glow.shader = sh
		_glow.set_shader_parameter("near_spots", _padded())
	return _glow


static func clear_spots() -> void:
	set_spots([])


## The spots the shaders have now: Vector4 (anchor x, anchor z, how far the
## buildings have handed over, how far the trees have).
static func spots() -> Array:
	return _spots


## Which farmsteads are handing over to their close-ups (see SHADER). At
## most SPOTS: the caller keeps within it (FarmsteadNear drops the farthest
## close-up, so no tree is drawn both far and near). The shaders are told
## only when something changed.
static func set_spots(spots: Array) -> void:
	var a := spots.slice(0, SPOTS)
	if a.size() == _spots.size():
		var same := true
		for i in a.size():
			if a[i] != _spots[i]:
				same = false
				break
		if same and _mat != null:
			return
	_spots = a
	material().set_shader_parameter("near_spots", _padded())
	glow_material().set_shader_parameter("near_spots", _padded())


## The spots as the shaders want them: SPOTS of them, the unused far away.
static func _padded() -> Array:
	var padded := _spots.duplicate()
	while padded.size() < SPOTS:
		padded.append(Vector4(1e9, 1e9, 0.0, 0.0))
	return padded


# ---------------------------------------------------------------- the mesh

## The arrays a block of farmsteads is drawn into.
var v := PackedVector3Array()
var nrm := PackedVector3Array()
var col := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var idx := PackedInt32Array()
## The yard lights' glows: their own surface.
var gv := PackedVector3Array()
var gcol := PackedColorArray()
var guv := PackedVector2Array()
var guv2 := PackedVector2Array()
## Lighter: fewer trees, fewer sides (the browser).
var light := false

var _xf := Transform3D.IDENTITY
var _origin := Vector2.ZERO
var _anchor := Vector2.ZERO
var _p: Dictionary
var _base := 0.0


func _init(lighter := false) -> void:
	light = lighter


## Adds one farmstead, its plan `p`, with the view's origin `origin`; the
## mesh is drawn about `centre` (view metres), where its node will stand.
## All at once; FarmsteadView uses begin and step to spread it over frames.
func add(p: Dictionary, origin: Vector2, centre := Vector3.ZERO) -> void:
	var n := begin(p, origin, centre)
	for i in n:
		step(i)


## Starts a farmstead; returns how many steps (step(0) to step(n - 1)) draw it.
## The browser is slow enough that one farmstead is split into its parts.
func begin(p: Dictionary, origin: Vector2, centre := Vector3.ZERO) -> int:
	_p = p
	_origin = origin
	_base = Terrain.height(p.at.x, p.at.y)
	_xf = Transform3D(Basis.IDENTITY, -centre) * FarmsteadPlan.frame(p, origin, _base)
	_anchor = p.at - origin
	return 3 + (p.parts as Array).size()


## Draws one step of the farmstead begun: the ground, the house, each
## building in turn, then the trees and the yard light.
func step(i: int) -> void:
	var parts: Array = _p.parts
	if i == 0:
		_ground_work(_p)
	elif i == 1:
		_house(_p.house)
	elif i < 2 + parts.size():
		var part: Dictionary = parts[i - 2]
		match part.kind:
			"barn": _barn(part)
			"shed": _shed(part)
			"quonset": _quonset(part)
			"bin": _bin(part)
			"dryer": _dryer(part)
			"silo": _silo(part)
			"windmill": _windmill(part)
			"hog_barn": _hog_barn(part)
			"feed_bin": _feed_bin(part)
			"milk_house": _box_roof(part.pos, Vector2(part.w, part.l), 3.4, 1.0, true, Color("#e9e9e4"), Color("#9a9fa2"))
	else:
		_trees(_p)
		if not _p.light.is_empty():
			_yard_light(_p.light)


## The ground (region metres) under a local point, less the farm's base.
func _lift(q: Vector2) -> float:
	var r := FarmsteadPlan.to_region(_p, q)
	return Terrain.height(r.x, r.y) - _base


## The lowest ground under a local footprint, as a lift from the base.
func _foot(c: Vector2, half: Vector2) -> float:
	var lo := INF
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
		lo = minf(lo, _lift(c + half * d))
	return lo


## Adds a vertex (local metres); returns its index.
func _vert(p: Vector3, n: Vector3, c: Color, t := Vector2.ZERO) -> int:
	if c.a > 0.99:
		c.a = 0.0  # a plain face (see the class notes)
	v.append(_xf * p)
	nrm.append((_xf.basis * n).normalized())
	col.append(c)
	uv.append(t)
	uv2.append(_anchor)
	return v.size() - 1


## A triangle in local metres, facing `out`.
func tri(a: Vector3, b: Vector3, c: Vector3, colour: Color, out := Vector3.UP, ta := Vector2.ZERO,
		tb := Vector2.ZERO, tc := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-8:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
		var u := tb
		tb = tc
		tc = u
	# Godot's fronts wind clockwise as seen from the front.
	var i := _vert(a, n, colour, ta)
	_vert(b, n, colour, tb)
	_vert(c, n, colour, tc)
	idx.append_array([i, i + 2, i + 1])


## A flat four-sided face a b c d (in order round its edge), facing `out`:
## four vertices, two triangles.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color, out := Vector3.UP,
		ta := Vector2.ZERO, tb := Vector2.ZERO, tc := Vector2.ZERO, td := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-8:
		n = (c - a).cross(d - a)
		if n.length_squared() < 1e-8:
			return
	n = n.normalized()
	var flip := n.dot(out) < 0.0
	if flip:
		n = -n
	var i := _vert(a, n, colour, ta)
	_vert(b, n, colour, tb)
	_vert(c, n, colour, tc)
	_vert(d, n, colour, td)
	if flip:
		idx.append_array([i, i + 1, i + 2, i, i + 2, i + 3])
	else:
		idx.append_array([i, i + 2, i + 1, i, i + 3, i + 2])


static func _p3(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, q.y)


## Four walls round a rectangle (centre c, half sizes h, x and z), from y0
## to y1, their UVs metres along and up (for the house's windows).
func _walls(c: Vector2, h: Vector2, y0: float, y1: float, wall: Color) -> void:
	var k := [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
	for i in 4:
		var a: Vector2 = k[i]
		var b: Vector2 = k[(i + 1) % 4]
		var away := (a + b) * 0.5 - c
		var len := a.distance_to(b)
		quad(_p3(a, y0), _p3(b, y0), _p3(b, y1), _p3(a, y1), wall, Vector3(away.x, 0, away.y),
			Vector2(0.4, 0.0), Vector2(len + 0.4, 0.0), Vector2(len + 0.4, y1 - y0), Vector2(0.4, y1 - y0))


## A box with a gable roof (ridge along local x when `ridge_x`), or a hip
## roof: footprint size s (x, z), eave height, ridge rise.
func _box_roof(c: Vector2, s: Vector2, eave: float, rise: float, ridge_x: bool, wall: Color, roof: Color,
		hip := false, glass := 0.0) -> void:
	var h := s * 0.5
	var y0 := _foot(c, h) - 0.3
	var y1 := y0 + 0.3 + eave
	var w := wall
	w.a = glass
	_walls(c, h, y0, y1, w)
	var over := 0.4
	var e := h + Vector2.ONE * over
	var drop := rise * over / maxf(h.y if ridge_x else h.x, 0.5)
	var ye := y1 - drop
	var top := y1 + rise
	var wall_plain := wall
	wall_plain.a = 0.0
	if hip:
		var ridge := maxf(e.x - e.y, 0.0)
		var r0 := _p3(c + Vector2(-ridge, 0), top)
		var r1 := _p3(c + Vector2(ridge, 0), top)
		var k := [c + Vector2(-e.x, -e.y), c + Vector2(e.x, -e.y), c + Vector2(e.x, e.y), c + Vector2(-e.x, e.y)]
		quad(_p3(k[0], ye), _p3(k[1], ye), r1, r0, roof, Vector3(0, 1, -1))
		quad(_p3(k[2], ye), _p3(k[3], ye), r0, r1, roof, Vector3(0, 1, 1))
		tri(_p3(k[1], ye), _p3(k[2], ye), r1, roof, Vector3(1, 1, 0))
		tri(_p3(k[3], ye), _p3(k[0], ye), r0, roof, Vector3(-1, 1, 0))
		return
	if ridge_x:
		var r0 := _p3(c + Vector2(-e.x, 0), top)
		var r1 := _p3(c + Vector2(e.x, 0), top)
		quad(_p3(c + Vector2(-e.x, -e.y), ye), _p3(c + Vector2(e.x, -e.y), ye), r1, r0, roof, Vector3(0, 1, -1))
		quad(_p3(c + Vector2(e.x, e.y), ye), _p3(c + Vector2(-e.x, e.y), ye), r0, r1, roof, Vector3(0, 1, 1))
		for sd in [-1.0, 1.0]:
			tri(_p3(c + Vector2(sd * h.x, -h.y), y1), _p3(c + Vector2(sd * h.x, h.y), y1), _p3(c + Vector2(sd * h.x, 0), top),
				wall_plain, Vector3(sd, 0, 0))
	else:
		var r0 := _p3(c + Vector2(0, -e.y), top)
		var r1 := _p3(c + Vector2(0, e.y), top)
		quad(_p3(c + Vector2(-e.x, -e.y), ye), _p3(c + Vector2(-e.x, e.y), ye), r1, r0, roof, Vector3(-1, 1, 0))
		quad(_p3(c + Vector2(e.x, e.y), ye), _p3(c + Vector2(e.x, -e.y), ye), r0, r1, roof, Vector3(1, 1, 0))
		for sd in [-1.0, 1.0]:
			tri(_p3(c + Vector2(-h.x, sd * h.y), y1), _p3(c + Vector2(h.x, sd * h.y), y1), _p3(c + Vector2(0, sd * h.y), top),
				wall_plain, Vector3(0, 0, sd))


func _house(h: Dictionary) -> void:
	var glass := 0.08 if h.vacant else 0.2
	var wall: Color = h.wall
	if h.vacant:
		wall = wall.lerp(Color(0.62, 0.6, 0.55), 0.45)
	var c := Vector2(h.x, h.d * 0.5)
	_box_roof(c, Vector2(h.w, h.d), h.eave, h.rise, h.get("ridge_x", true), wall, h.roof, h.get("hip", false), glass)
	var ell: Vector2 = h.ell
	if ell != Vector2.ZERO:
		_box_roof(Vector2(h.x - _p.side * (h.w * 0.5 - ell.x * 0.5), h.d + ell.y * 0.5), ell, 3.3, 1.8, false, wall, h.roof,
			false, glass)


## A gambrel (two slopes a side) or bank barn (gable, with the earthen
## ramp up to the loft doors on one long side). Weathered barns fade and
## their roofs rust; sagging ones bow at the ridge; fallen ones are a heap.
func _barn(b: Dictionary) -> void:
	var c: Vector2 = b.pos
	var hw: float = b.w * 0.5
	var hl: float = b.l * 0.5
	var paint: Color = b.paint
	var roof := Color("#8e9396")
	match b.cond:
		"weathered":
			paint = paint.lerp(Color("#8a8070"), 0.35)
			roof = Color("#7d6450")
		"sagging":
			paint = paint.lerp(Color("#7a7064"), 0.55)
			roof = Color("#6e5444")
		"fallen":
			paint = paint.lerp(Color("#6a6258"), 0.65)
	var y0 := _foot(c, Vector2(hw, hl)) - 0.3
	var eave: float = b.eave
	if b.cond == "fallen":
		# A low heap of boards and roof steel, a gable end still standing.
		var hh := 2.2
		quad(_p3(c + Vector2(-hw, -hl), y0 + 0.3), _p3(c + Vector2(hw, -hl), y0 + 0.3), _p3(c + Vector2(hw * 0.3, hl), y0 + hh),
			_p3(c + Vector2(-hw * 0.4, hl), y0 + hh * 0.8), roof, Vector3.UP)
		_walls(Vector2(c.x, c.y + hl - 0.3), Vector2(hw, 0.3), y0, y0 + eave * 0.8, paint)
		return
	var y1 := y0 + 0.3 + eave
	_walls(c, Vector2(hw, hl), y0, y1, paint)
	var sag := 0.0
	var lean := 0.0
	if b.cond == "sagging":
		sag = 0.9
		lean = float(b.lean) * 0.6
	var prof: Array
	if b.style == "gambrel":
		prof = [Vector2(-hw, 0.0), Vector2(-hw * 0.62, hw * 0.75), Vector2(0.0, hw * 1.05), Vector2(hw * 0.62, hw * 0.75), Vector2(hw, 0.0)]
	else:
		prof = [Vector2(-hw, 0.0), Vector2(0.0, hw * 0.75), Vector2(hw, 0.0)]
	# Gable ends, then the roof slopes along the barn (z), the middle of
	# the ridge lower on a sagging barn.
	for e in [-1.0, 1.0]:
		var z: float = c.y + e * hl
		for i in prof.size() - 1:
			var a: Vector2 = prof[i]
			var bq: Vector2 = prof[i + 1]
			tri(Vector3(c.x + a.x + lean, y1 + a.y, z), Vector3(c.x + bq.x + lean, y1 + bq.y, z), Vector3(c.x + lean * 0.5, y1, z), paint, Vector3(0, 0, e))
	var over := 0.5
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var bq: Vector2 = prof[i + 1]
		var out := Vector3(signf(a.x + bq.x), 1.0, 0.0)
		var steps := 2 if sag > 0.0 else 1
		for k in steps:
			var z0 := lerpf(-hl - over, hl + over, float(k) / steps)
			var z1 := lerpf(-hl - over, hl + over, float(k + 1) / steps)
			var s0 := sag * (1.0 - absf(z0) / (hl + over)) * (a.y / (hw * 1.05))
			var s1 := sag * (1.0 - absf(z1) / (hl + over)) * (a.y / (hw * 1.05))
			var t0 := sag * (1.0 - absf(z0) / (hl + over)) * (bq.y / (hw * 1.05))
			var t1 := sag * (1.0 - absf(z1) / (hl + over)) * (bq.y / (hw * 1.05))
			quad(Vector3(c.x + a.x + lean, y1 + a.y - s0, c.y + z0), Vector3(c.x + a.x + lean, y1 + a.y - s1, c.y + z1),
				Vector3(c.x + bq.x + lean, y1 + bq.y - t1, c.y + z1), Vector3(c.x + bq.x + lean, y1 + bq.y - t0, c.y + z0), roof, out)
	if b.style == "bank":
		# The bank: an earthen ramp up to the big doors on the long side
		# away from the yard, grassed over.
		var sx: float = -_p.side
		var foot := Vector2(c.x + sx * (hw + 6.0), c.y)
		var gr := Color("#5f6b3a")
		quad(_p3(Vector2(c.x + sx * hw, c.y - 3.0), y0 + 3.0), _p3(Vector2(c.x + sx * hw, c.y + 3.0), y0 + 3.0),
			_p3(foot + Vector2(0, 3.0), y0 + 0.2), _p3(foot - Vector2(0, 3.0), y0 + 0.2), gr, Vector3(sx, 1, 0))


## A pole barn: steel walls, a low (4 in 12) roof, ridge along its length.
func _shed(s: Dictionary) -> void:
	var rise: float = s.w * 0.5 * (4.0 / 12.0)
	_box_roof(s.pos, Vector2(s.l, s.w), s.eave, rise, true, s.wall, s.roof)


## A 1950s-60s Quonset: a half-round of galvanised steel.
func _quonset(s: Dictionary) -> void:
	var c: Vector2 = s.pos
	var hl: float = s.l * 0.5
	var r: float = s.w * 0.5
	var y0 := _foot(c, Vector2(hl, r)) - 0.2
	var n := 4 if light else 6
	var steel := FarmsteadPlan.OLD_GALV
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var p0 := Vector2(c.y - cos(a0) * r, y0 + sin(a0) * r)
		var p1 := Vector2(c.y - cos(a1) * r, y0 + sin(a1) * r)
		quad(Vector3(c.x - hl, p0.y, p0.x), Vector3(c.x + hl, p0.y, p0.x), Vector3(c.x + hl, p1.y, p1.x), Vector3(c.x - hl, p1.y, p1.x),
			steel, Vector3(0, sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5)))
		for e in [-1.0, 1.0]:
			tri(Vector3(c.x + e * hl, y0, c.y), Vector3(c.x + e * hl, p0.y, p0.x), Vector3(c.x + e * hl, p1.y, p1.x), steel, Vector3(e, 0, 0))


## A round steel thing standing on the ground: n sides and a cone roof.
func _drum(c: Vector2, r: float, h: float, roof_rise: float, body: Color, roof: Color, n: int, y0 := INF) -> float:
	if y0 == INF:
		y0 = _foot(c, Vector2(r, r)) - 0.2
	var y1 := y0 + 0.2 + h
	# Smooth sides (a ring at the foot and one at the eave share their
	# vertices round the drum), then the roof cone on its own ring.
	var inside := Vector3(c.x, (y0 + y1) * 0.5, c.y)
	var foot := []
	var eave := []
	var rim := []
	for i in n:
		var a0 := TAU * i / n
		var d := Vector3(cos(a0), 0.0, sin(a0))
		var q := c + Vector2(d.x, d.z) * r
		foot.append(_vert(_p3(q, y0), d, body))
		eave.append(_vert(_p3(q, y1), d, body))
		rim.append(_vert(_p3(q, y1), (d * roof_rise / maxf(r, 0.1) + Vector3.UP).normalized() if roof_rise > 0.0 else Vector3.UP,
			roof))
	var apex := _vert(Vector3(c.x, y1 + roof_rise, c.y), Vector3.UP, roof)
	for i in n:
		var j := (i + 1) % n
		_face(foot[i], foot[j], eave[j], inside)
		_face(foot[i], eave[j], eave[i], inside)
		_face(rim[i], rim[j], apex, inside)
	return y1


## A corrugated steel bin under its 30-degree cone roof.
func _bin(b: Dictionary) -> void:
	var c: Color = b.col
	_drum(b.pos, b.r, b.h, b.r * 0.55, c, c.darkened(0.08), 6 if light else 9)


## The bucket elevator leg (a tall thin tower), its head, the spouts down
## to each bin, and the column dryer beside it.
func _dryer(d: Dictionary) -> void:
	var c: Vector2 = d.pos
	var y0 := _lift(c) - 0.2
	var h: float = d.h
	var steel := Color("#a5a9aa")
	_post(c, 0.45, y0, y0 + h, steel)
	_post(c, 0.9, y0 + h - 1.2, y0 + h + 0.4, steel)
	for b in d.bins:
		var to := Vector3((b.pos as Vector2).x, y0 + b.h + b.r * 0.55, (b.pos as Vector2).y)
		_line(Vector3(c.x, y0 + h - 1.0, c.y), to, 0.18, steel.darkened(0.2))
	var dc: Vector2 = d.dryer_at
	_box_roof(dc, Vector2(3.0, 6.0), 7.0, 0.3, false, Color("#c7c9c6"), Color("#8f9394"))


## A grey concrete stave silo, with its dome or open to the sky.
func _silo(s: Dictionary) -> void:
	var body := Color("#3d5f8a") if s.harvestore else _stave(s)
	var roof := Color("#3d5f8a") if s.harvestore else Color("#9a9fa2")
	_drum(s.pos, s.r, s.h, s.r * 0.6 if s.dome else 0.0, body, roof if s.dome else body.darkened(0.5), 6 if light else 9)


static func _stave(s: Dictionary) -> Color:
	return FarmsteadPlan.STAVE if s.used else FarmsteadPlan.STAVE.darkened(0.12)


## The windmill: four splayed legs to the wheel, the wheel a thin disc.
func _windmill(w: Dictionary) -> void:
	if light:
		return
	var c: Vector2 = w.pos
	var y0 := _lift(c)
	var h: float = w.h
	var steel := Color("#8d8f8c")
	var top := Vector3(c.x, y0 + h, c.y)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		_line(_p3(c + d * h * 0.09, y0), top, 0.12, steel)
	var r: float = w.wheel * 0.5
	var ax := Vector3(cos(w.yaw), 0, sin(w.yaw))
	var side := Vector3.UP.cross(ax).normalized()
	var hub := top + Vector3(0, 0.4, 0) + ax * 0.5
	var n := 6
	for i in n:
		if w.broken and i % 3 == 0:
			continue
		var a0 := TAU * i / n
		var a1 := TAU * (i + 0.6) / n
		tri(hub, hub + (side * cos(a0) + Vector3.UP * sin(a0)) * r, hub + (side * cos(a1) + Vector3.UP * sin(a1)) * r, steel, ax)
	# The tail vane behind the wheel.
	tri(top - ax * 0.4, top - ax * 2.2 + Vector3(0, 0.3, 0), top - ax * 2.2 + Vector3(0, 1.0, 0), steel, side)


func _hog_barn(b: Dictionary) -> void:
	_box_roof(b.pos, Vector2(b.l, b.w), 2.9, 2.1, true, Color("#e9e9e4"), Color("#9a9fa2"))


func _feed_bin(b: Dictionary) -> void:
	var y0 := _lift(b.pos) + 2.2
	_drum(b.pos, b.r, b.h, b.r * 0.6, Color("#c3c7c8"), Color("#b5b9ba"), 6, y0)
	_post(b.pos, 0.35, y0 - 2.4, y0, Color("#8f9394"))


## A square post from y0 to y1 (four sides).
func _post(c: Vector2, r: float, y0: float, y1: float, colour: Color) -> void:
	var k := [c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)]
	for i in 4:
		var a: Vector2 = k[i]
		var b: Vector2 = k[(i + 1) % 4]
		var away := (a + b) * 0.5 - c
		quad(_p3(a, y0), _p3(b, y0), _p3(b, y1), _p3(a, y1), colour, Vector3(away.x, 0, away.y))


## A thin bar from a to b, as two crossed ribbons.
func _line(a: Vector3, b: Vector3, r: float, colour: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * r
	var s2 := d.cross(s1).normalized() * r
	quad(a - s1, a + s1, b + s1, b - s1, colour, s2)
	quad(a - s2, a + s2, b + s2, b - s2, colour, s1)


## Gravel yard, lane and drive: crushed limestone, pale from the air,
## draped over the land in pieces a little above it.
func _ground_work(p: Dictionary) -> void:
	var stone := Color("#b5ad9c")
	stone.a = GRAVEL_ALPHA
	for r: Rect2 in p.gravel:
		var nx := clampi(ceili(r.size.x / 40.0), 1, 6)
		var nz := clampi(ceili(r.size.y / 40.0), 1, 12)
		for i in nx:
			for j in nz:
				var q := [r.position + r.size * Vector2(float(i) / nx, float(j) / nz),
					r.position + r.size * Vector2(float(i + 1) / nx, float(j) / nz),
					r.position + r.size * Vector2(float(i + 1) / nx, float(j + 1) / nz),
					r.position + r.size * Vector2(float(i) / nx, float(j + 1) / nz)]
				var pts := []
				for k in q:
					pts.append(_p3(k, _lift(k) + FarmsteadPlan.GRAVEL_LIFT))
				quad(pts[0], pts[1], pts[2], pts[3], stone, Vector3.UP)
	# The mown grass of the farmstead's grounds, out to the windbreak: no
	# crop grows there. An empty house's lawn has gone to tall grass.
	var lawn := Color("#4f6a2e") if not p.house.vacant else Color("#727a40")
	lawn.a = LAWN_ALPHA
	var g: Rect2 = p.grounds
	var nx := clampi(ceili(g.size.x / 48.0), 1, 6)
	var nz := clampi(ceili(g.size.y / 48.0), 1, 6)
	for i in nx:
		for j in nz:
			var q := [g.position + g.size * Vector2(float(i) / nx, float(j) / nz),
				g.position + g.size * Vector2(float(i + 1) / nx, float(j) / nz),
				g.position + g.size * Vector2(float(i + 1) / nx, float(j + 1) / nz),
				g.position + g.size * Vector2(float(i) / nx, float(j + 1) / nz)]
			var pts := []
			for k in q:
				pts.append(_p3(k, _lift(k) + FarmsteadPlan.LAWN_LIFT))
			quad(pts[0], pts[1], pts[2], pts[3], lawn, Vector3.UP)


## Trees as cheap stand-ins: a conifer is a cone, a shade tree a squat
## double cone, sized as the trees code grows them (TreeField's kinds).
func _trees(p: Dictionary) -> void:
	var i := 0
	for t in p.trees:
		i += 1
		var windbreak: bool = t.size() > 4
		# From afar a windbreak reads as a dark row, not as trees: every
		# other tree stands in for two (every fourth for four, lighter).
		if windbreak and i % (4 if light else 2) != 0:
			continue
		var at: Vector2 = t[0]
		var sp: int = t[1]
		var s: float = t[2]
		var wide := (1.6 if light else 1.35) if windbreak else 1.0
		var leaf: Color = TreeField.LEAF[sp] if sp < TreeField.LEAF.size() else TreeField.LEAF[0]
		leaf = FarmsteadPlan.tree_tint(leaf, at)
		leaf.a = TREE_ALPHA
		var y0 := _lift(at) - 0.2
		var conifer: bool = sp == TreeField.Species.SPRUCE or sp == FarmsteadPlan.species("RED_CEDAR", -1)
		var n := 3 if light else 4
		var turn := FarmsteadPlan.tree_turn(at)
		if conifer:
			# A cone: a ring of n at the foot of the crown, one apex.
			var h := 15.0 * s
			var r := (2.4 if sp == TreeField.Species.SPRUCE else 1.4) * s * wide
			var apex := _vert(_p3(at, y0 + h), Vector3.UP, leaf)
			var ring := []
			for k in n:
				var a0 := TAU * k / n + turn
				var d := Vector3(cos(a0), 0.0, sin(a0))
				ring.append(_vert(_p3(at + Vector2(d.x, d.z) * r, y0 + h * 0.08), (d + Vector3.UP * 0.4).normalized(), leaf.darkened(0.12)))
			for k in n:
				_face(ring[k], ring[(k + 1) % n], apex, _p3(at, y0 + h * 0.4))
		else:
			# A squat double cone: the crown's widest ring, a top and a foot.
			var h := 17.0 * s
			var r := 6.5 * s
			var top := _vert(_p3(at, y0 + h), Vector3.UP, leaf)
			var foot := _vert(_p3(at, y0 + h * 0.22), Vector3.DOWN, leaf.darkened(0.3))
			var ring := []
			for k in n:
				var a0 := TAU * k / n + turn
				var d := Vector3(cos(a0), 0.0, sin(a0))
				ring.append(_vert(_p3(at + Vector2(d.x, d.z) * r, y0 + h * 0.55), d, leaf.darkened(0.1)))
			var mid := _p3(at, y0 + h * 0.55)
			for k in n:
				_face(ring[k], ring[(k + 1) % n], top, mid)
				_face(ring[k], ring[(k + 1) % n], foot, mid)


## A triangle of three vertices already added, wound to face away from
## `inside` (a point in the crown, view metres before the frame).
func _face(a: int, b: int, c: int, inside: Vector3) -> void:
	var n := (v[b] - v[a]).cross(v[c] - v[a])
	if n.dot(v[a] - _xf * inside) >= 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## The yard light: its glow at the lamp, drawn by the glow material.
func _yard_light(l: Dictionary) -> void:
	var at: Vector2 = l.pos
	var y := _lift(at) + float(l.h)
	var c := _xf * Vector3(at.x, y, at.y)
	var lamp: Color = l.col
	for k in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
		gv.append(c)
		gcol.append(lamp)
		guv.append(k)
		guv2.append(_anchor)
	# The pole, a few pixels of dark wood by day.
	_post(at, 0.15, _lift(at) - 0.2, y + 0.4, Color("#4a3f33"))


## The block's mesh (the buildings and the glows), or null when empty.
func commit() -> ArrayMesh:
	if v.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	if not gv.is_empty():
		var g := []
		g.resize(Mesh.ARRAY_MAX)
		g[Mesh.ARRAY_VERTEX] = gv
		g[Mesh.ARRAY_COLOR] = gcol
		g[Mesh.ARRAY_TEX_UV] = guv
		g[Mesh.ARRAY_TEX_UV2] = guv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g)
		mesh.surface_set_material(1, glow_material())
	return mesh
