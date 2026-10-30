class_name TreeLook
extends RefCounted
## How trees are drawn: the leaf shader every tree shares (TreeField's
## cheap far trees and the grown trees near the camera), the grown trees'
## bark, each kind's leaf texture, and the season and distance values the
## shaders read.
##
## Detail by distance (each tree drawn at exactly one level, handed over
## with a dither so nothing pops): within NEAR the full grown tree, out to
## MID the light grown tree, then TreeField's full cards, out from its NEAR
## its light cards, and for the wild woods, past the edge of WildView's
## reach, FarWoods' one-quad stand-ins out toward the horizon. Every
## version of a tree stands at the same spot at the same size, and each
## hand-over is a dither by the tree's own distance from the camera, so a
## tree is replaced where it stands: it never grows out of the ground or
## blinks. The radii scale with the quality tier; the browser
## (Compatibility) gets the light grown tree only. zone_mode on a material
## says which version it draws:
##   0 TreeField's cards (full, or light: light_card)
##   1 full grown, inside NEAR; 2 light grown, NEAR to MID;
##   4 and 5 a card standing in for a full (4) or light (5) grown tree
##   whose mesh isn't built yet; 6 FarWoods' stand-ins.
## Each version keeps the pixels whose dither falls in its share (KEEP_GLSL):
## going out from the camera, each hand-over gives the next version the
## lower part of [0, 1), so the shares never overlap and never leave a gap.

## Desktop radii (m) at quality detail 1.0, and the width of the handover.
const NEAR := 70.0
const MID := 190.0
const BAND := 14.0

## Which share of the pixels each version of a tree draws, by its distance
## from the camera (shared by every card shader; see the header). The
## hand-over from TreeField's full cards to its light ones is 40 m wide.
const KEEP_GLSL := """
// The trees' camera (TreeLook.set_eye): xyz, w 1 once set.
uniform vec4 lod_eye = vec4(0.0);
// x: where TreeField's full cards hand over to its light ones; y: how far
// brush is drawn; z: how far FarWoods draws the wild woods (0: none).
uniform vec4 lod_dist = vec4(0.0);
// This material draws TreeField's light cards.
uniform bool light_card = false;
// A steady hash of where a tree stands: the same for every version of the
// tree (their positions differ in the last bits; a sine of a big number
// would not be).
float tree_hash(vec3 origin, float salt) {
	vec2 p = mod(floor(origin.xz * 2.0), 4096.0) + salt;
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// The share of pixels [from, to) this version of a tree draws. Going out
// from the camera: full grown [b1, 1), light grown [b2, b1), full cards
// [b3, b2), light cards [b4, b3), FarWoods [0, b4); each b rises from 0 to
// 1 across its hand-over. A wild tree past the far woods' reach, or seen
// from high up, drops out whole, each at its own distance.
// The sun's shadow map (`shadow`) is cheaper (GrownTrees.SHADOW_BIT): a
// full grown tree casts no shadow, the light grown tree at its spot casts
// it ([b1, 1), drawn into the shadow map only); past NEAR the full card at
// a tree's spot casts it, not the light grown tree ([b3, b1)). Without a
// near band (the browser) each version casts its own, as it draws.
vec2 band_keep(vec3 origin, bool grows, bool shadow) {
	// A tier with only the nearest trees' shadows (grown_zone.w, their
	// reach: GrownTrees.shadow_reach): whichever version stands at a tree's
	// spot in the shadow map casts it all the way out to there, with no
	// hand-over on the way (it would end the shadow before its thinning
	// out does: near_fade), and none past it.
	if (shadow && grown_zone.w > 0.0 && grown_cam.w > 0.5) {
		if (distance(origin, grown_cam.xyz) < grown_zone.w) {
			return vec2(0.0, 1.0);
		}
		return vec2(0.0);
	}
	float b1 = 1.0;
	float b2 = 1.0;
	if (grows && grown_cam.w > 0.5) {
		float d = distance(origin, grown_cam.xyz);
		b1 = smoothstep(grown_zone.x - grown_zone.z, grown_zone.x, d);
		b2 = min(smoothstep(grown_zone.y - grown_zone.z, grown_zone.y, d), b1);
	}
	float de = distance(origin, lod_eye.xyz);
	float b4 = 0.0;
	if (fade_on) {
		float rnd = tree_hash(origin, 0.0);
		// Toward the edge of WildView's reach the far woods take over, each
		// tree at its own distance, so the edge is ragged, not a circle.
		float jitter = (tree_hash(origin, 17.0) - 0.5) * 0.3 * tree_fade.z;
		b4 = smoothstep(tree_fade.z * 0.7, tree_fade.z * 0.97, distance(origin.xz, tree_fade.xy) + jitter);
		// From high up each tree is a speck and the ground's painted canopy
		// reads better: they drop out one by one.
		float gone = smoothstep(1200.0, 1700.0, tree_fade.w);
		if (grows) {
			if (lod_dist.z > 0.0) {
				gone = max(gone, smoothstep(lod_dist.z * 0.85, lod_dist.z, de));
			}
		} else {
			// Brush has no far version: each plant drops out whole.
			if (lod_dist.y > 0.0) {
				b4 = max(b4, smoothstep(lod_dist.y * 0.8, lod_dist.y, de));
			}
			b4 = step(rnd, b4);
		}
		if (rnd < gone) {
			return vec2(0.0);
		}
	}
	// No camera yet: each chunk draws one version whole.
	float b3 = light_card ? b2 : b4;
	if (lod_eye.w > 0.5) {
		b3 = smoothstep(lod_dist.x - 40.0, lod_dist.x, de);
	}
	// The far woods take over from whichever cards a tree is drawn with
	// there (with a short reach, straight from the full ones); neither
	// takes over a grown tree.
	b4 = min(b4, b2);
	// With no full grown trees (grown_zone.x 0: the browser) every version
	// casts its own shadow, as it draws.
	if (shadow && grown_zone.x > 0.0) {
		if (zone_mode == 0 && !light_card) {
			return vec2(max(min(b3, b1), b4), b1);
		}
		if (zone_mode == 2 || zone_mode == 5) {
			return vec2(b1, 1.0);
		}
	}
	b3 = max(min(b3, b2), b4);
	if (zone_mode == 1 || zone_mode == 4) {
		return vec2(b1, 1.0);
	}
	if (zone_mode == 2 || zone_mode == 5) {
		return vec2(b2, b1);
	}
	if (zone_mode == 6) {
		return vec2(0.0, b4);
	}
	return light_card ? vec2(b4, b3) : vec2(b3, b2);
}
float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}
"""
## The width of the hand-over from TreeField's full cards to its light ones
## (in KEEP_GLSL too).
const LIGHT_BAND := 40.0

## Sun through a crown, in the sun's shadow map. A real summer maple's
## shadow is dappled: flecks of sun come through the gaps between leaf
## clusters, a few in the middle and many round the rim, so it reads a
## little lighter than a house's shadow, never as a solid black hole (look
## round 1, 2026-10-29: the street trees' shadows were solid ovals, 22,29,45
## on a road lit at 111,103,101). Every card of a crown, near side or far,
## shares the same gaps along each ray of sun (a pattern on the plane square
## to the sun, fixed to the ground), so the gaps go right through the crown;
## a pattern of each card's own would leave none, dozens of cards deep.
## OPEN_CORE and OPEN_RIM: the share of the sun let through a crown's middle
## (its inner leaves) and its rim (its outer ones). SHADOW_FADE: how far
## before a tier's near tree shadows end (GrownTrees.shadow_reach) they
## start thinning out, the gaps widening until nothing is left, so they end
## with no ring. The browser keeps its solid shadows. FLECK_GLSL works it
## out; leaf_open and sun_keep below do the same for the tests.
const OPEN_CORE := 0.18
const OPEN_RIM := 0.5
const SHADOW_FADE := 12.0
## sun_keep's cut, fitted to the noise's spread: the noise's value above
## which a share `open` of the plane lies is 0.5 + o * (c0 + o² * (c1 + o² *
## (c2 + o² * c3))), with o = 0.5 - open (within half a percent).
const CUT := [0.3898, 1.7087, -15.0853, 54.8291]
const FLECK_GLSL := """
const float OPEN_CORE = %s;
const float OPEN_RIM = %s;
const float SHADOW_FADE = %s;
float fleck_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float fleck_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	// Kept to small numbers, so the hash is as sharp far from the middle
	// of the map (the pattern repeats every few hundred metres).
	vec2 j = mod(i + 1.0, 1024.0);
	i = mod(i, 1024.0);
	return mix(mix(fleck_hash(i), fleck_hash(vec2(j.x, i.y)), f.x),
		mix(fleck_hash(vec2(i.x, j.y)), fleck_hash(j), f.x), f.y);
}
// Where a vertex's ray of sun crosses the plane square to the sun, in
// metres, fixed to the ground (vertex(), in the shadow map's pass). Worked
// out from the matrices the vertex itself is drawn with (MODEL_MATRIX and
// MODELVIEW_MATRIX, the sun's view in that pass), and every split of the
// shadow map is turned the same way, so they agree.
vec2 sun_plane(mat4 model, mat4 modelview, vec3 v) {
	return (mat3(modelview) * (v + inverse(mat3(model)) * model[3].xyz)).xy;
}
// How far a tree is into the thinning out of a tier's near tree shadows
// (grown_zone.w: their reach, 0 for none): 0 well inside, 1 at the reach.
float near_fade(vec3 origin) {
	if (grown_zone.w <= 0.0 || grown_cam.w < 0.5) {
		return 0.0;
	}
	return smoothstep(grown_zone.w - SHADOW_FADE, grown_zone.w, distance(origin, grown_cam.xyz));
}
// The share of the sun a crown's leaves let through: more round the rim
// (inn 1) than deep inside (inn 0), half as much through a spruce or
// cedar, and rising to all of it across the thinning out (fade).
float leaf_open(float inn, bool evergreen, float fade) {
	float lit = mix(OPEN_CORE, OPEN_RIM, smoothstep(0.55, 1.0, inn));
	if (evergreen) {
		lit *= 0.5;
	}
	return mix(lit, 1.0, fade);
}
// 1 to keep a pixel of the shadow map, 0 where the sun comes through: the
// gaps are a share `lit` of the plane square to the sun.
float sun_keep(vec2 plane, float lit) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return 1.0;
#else
	if (lit >= 0.999) {
		return 0.0;
	}
	if (lit <= 0.001) {
		return 1.0;
	}
	// Gaps between leaf clusters (about 0.4 m) and between leaves (0.17 m).
	float n = fleck_noise(plane * 2.5) * 0.6 + fleck_noise(plane * 6.0 + 17.0) * 0.4;
	float o = 0.5 - lit;
	float o2 = o * o;
	float cut = 0.5 + o * (%s + o2 * (%s + o2 * (%s + o2 * %s)));
	return 1.0 - step(cut, n);
#endif
}
""" % [OPEN_CORE, OPEN_RIM, SHADOW_FADE, CUT[0], CUT[1], CUT[2], CUT[3]]


## FLECK_GLSL's leaf_open, for tests.
static func leaf_open(inn: float, evergreen: bool, fade: float) -> float:
	var open := lerpf(OPEN_CORE, OPEN_RIM, smoothstep(0.55, 1.0, inn))
	if evergreen:
		open *= 0.5
	return lerpf(open, 1.0, fade)


## FLECK_GLSL's sun_keep, for tests: 1 keeps the shadow map's pixel at this
## point of the plane square to the sun, 0 lets the sun through.
static func sun_keep(plane: Vector2, open: float) -> float:
	if open >= 0.999:
		return 0.0
	if open <= 0.001:
		return 1.0
	var n := _fleck_noise(plane * 2.5) * 0.6 + _fleck_noise(plane * 6.0 + Vector2(17.0, 17.0)) * 0.4
	var o := 0.5 - open
	var o2 := o * o
	var cut: float = 0.5 + o * (CUT[0] + o2 * (CUT[1] + o2 * (CUT[2] + o2 * CUT[3])))
	return 0.0 if n >= cut else 1.0


static func _fleck_hash(p: Vector2) -> float:
	var p3 := Vector3(p.x, p.y, p.x) * 0.1031
	p3 = Vector3(p3.x - floorf(p3.x), p3.y - floorf(p3.y), p3.z - floorf(p3.z))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	var v := (p3.x + p3.y) * p3.z
	return v - floorf(v)


static func _fleck_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var j := Vector2(fposmod(i.x + 1.0, 1024.0), fposmod(i.y + 1.0, 1024.0))
	i = Vector2(fposmod(i.x, 1024.0), fposmod(i.y, 1024.0))
	var a := lerpf(_fleck_hash(i), _fleck_hash(Vector2(j.x, i.y)), f.x)
	var b := lerpf(_fleck_hash(Vector2(i.x, j.y)), _fleck_hash(j), f.x)
	return lerpf(a, b, f.y)

## Leaf textures are this many pixels across, and a full-size card is
## TreeMesher.CARD[0] metres across, which sets how big a leaf is drawn.
const TEX := 256

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_tex : filter_linear_mipmap;
uniform sampler2D twig_tex : filter_linear_mipmap;
// Set by DayNight: snow cover, and the season as (autumn, bare, spring, dry).
global uniform float snow;
global uniform vec4 season_look;
// Where WildView draws the wild trees as cards (set by it as the camera's
// x, z, the reach and the camera's height); past it FarWoods draws them.
global uniform vec4 tree_fade;
uniform bool fade_on = false;
// Which band of distance this material draws (see TreeLook).
uniform int zone_mode = 0;
uniform vec4 grown_cam = vec4(0.0);
uniform vec4 grown_zone = vec4(0.0, 0.0, 1.0, 0.0);
uniform float sway = 0.025;
// Per kind (TreeField.Species): autumn colour, this moment's look
// (autumn, bare, spring), spring blossom (alpha: has one), and the winter
// tint of an evergreen (alpha: evergreen).
uniform vec3 kind_fall[16];
uniform vec3 kind_look[16];
uniform vec4 kind_bloom[16];
uniform vec4 kind_winter[16];
uniform bool kind_seasons = false;
// FarWoods: each kind's crown at full size (centre height, half width,
// half height, trunk radius over half width), which its one quad is drawn
// at; and how much darker than lit leaves the quad is drawn (a crown of
// cards shades itself: its inner leaves and the side away from the sun).
uniform vec4 crown_box[16];
uniform float far_shade = 0.75;
// Summer green (see vertex) and the crown's own shade (see fragment).
const float LEAF_RED = 0.66;
const float LEAF_GREEN = 0.75;
const float LEAF_BLUE = 0.12;
const float LEAF_INNER = 0.38;
const float LEAF_UNDER = 0.72;
#ifdef FAR_WOODS
// Where on the quad the crown begins (below it, the trunk) and how wide
// the trunk is, as a share of the quad's half width.
varying float crown_v;
varying float trunk_w;
#endif
varying float inner;
varying float top;
varying vec3 tint;
varying vec3 crown_normal;
varying vec3 leaf_pos;
varying float species;
varying float tree_rand;
varying float far_card;
varying float fleck_fade;
varying vec2 sun_xy;
varying vec2 keep;
// The Compatibility renderer (the browser) hands INSTANCE_CUSTOM's rgb
// over as if it were an sRGB colour, already turned linear (alpha comes
// through as is); undo that so custom data reads as on the desktop.
vec4 custom_data(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
}
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
""" + KEEP_GLSL + FLECK_GLSL + """
void vertex() {
	vec4 custom = custom_data(INSTANCE_CUSTOM);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float code = floor(custom.a * 32.0);
	species = mod(code, 16.0);
	keep = band_keep(origin, code < 15.5, PROJECTION_MATRIX[3][3] > 0.5);
#ifdef FAR_WOODS
	// One quad facing the camera, the size of the crown (UV2 is its corner,
	// -1 to 1), turned back into the tree's own space.
	vec4 box = crown_box[int(species + 0.5)];
	float size = length(MODEL_MATRIX[1].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_back = INV_VIEW_MATRIX[2].xyz;
	// From above a crown is as wide as it is across, not as tall, and the
	// trunk is hidden under it.
	float above = abs(cam_back.y);
	float half_h = mix(box.z, box.y, above);
	float crown_lo = box.x - half_h;
	float lo = crown_lo * above;
	float hi = box.x + half_h;
	float y = mix(lo, hi, UV2.y * 0.5 + 0.5);
	crown_v = (crown_lo - lo) / (hi - lo);
	trunk_w = box.w;
	mat3 to_tree = transpose(mat3(MODEL_MATRIX)) / (size * size);
	VERTEX = vec3(0.0, box.x, 0.0) + to_tree * ((cam_right * UV2.x * box.y + cam_up * (y - box.x)) * size);
	// Shaded like a soft ball of leaves: out from its middle, a little up.
	float cy = clamp((y - box.x) / half_h, -1.0, 1.0);
	NORMAL = to_tree * normalize(cam_right * UV2.x * 0.6 + cam_up * (cy * 0.6 + 0.35) + cam_back * 0.7) * size;
#endif
	// Nothing to draw here: no triangles.
	VERTEX *= step(0.0001, keep.y - keep.x);
	// In the sun's shadow map: how far the tree is into the thinning out of
	// a tier's near tree shadows (near_fade; nothing left past them).
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	fleck_fade = shadow_pass ? near_fade(origin) : 0.0;
	VERTEX *= step(fleck_fade, 0.999);
	leaf_pos = VERTEX;
	tree_rand = tree_hash(origin, 31.0);
	far_card = step(COLOR.a, 0.75);  // a far tree's few big cards (see _card)
	float phase = TIME * 1.1 + origin.x * 0.31 + origin.z * 0.17;
	float s = sin(phase + VERTEX.y * 0.25) * sway * VERTEX.y;
	VERTEX.x += s;
	VERTEX.z += s * 0.6;
	sun_xy = shadow_pass ? sun_plane(MODEL_MATRIX, MODELVIEW_MATRIX, VERTEX) : vec2(0.0);
	inner = COLOR.r;
	top = COLOR.g;
	// Keep the crown normal on both sides of each card (no back-face flip),
	// so the whole crown shades like one soft volume.
	crown_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Summer leaves as photos show them, not a paint-chip green: a deep,
	// slightly blue-grey green (a July maple or oak crown in sun is about
	// 70, 85, 50, darker in its shade), so less red and yellow and more
	// blue than the kinds' leaf colours (TreeField.LEAF) carry.
	vec3 green = lin(custom.rgb);
	green = vec3(green.r * LEAF_RED, green.g * LEAF_GREEN, green.b + green.g * LEAF_BLUE);
	// Each leaf cluster drifts a little toward yellow or blue-green.
	tint = green * mix(vec3(0.93, 0.98, 1.06), vec3(1.07, 1.02, 0.9), COLOR.b);
}
void fragment() {
	// The sun's shadow map is drawn square-on (orthographic): there each
	// tree switches at the middle of the handover instead of dithering, so
	// its shadow on the ground is whole, not speckled.
	float dth = PROJECTION_MATRIX[3][3] > 0.5 ? 0.5 : dither(FRAGCOORD.xy);
	if (dth < keep.x || dth >= keep.y) discard;
	int sp = int(species + 0.5);
	vec2 uv = UV;
	bool trunk_px = false;
	float inn = inner;
	float tp = top;
#ifdef FAR_WOODS
	// The quad: the crown's leaves above crown_v, a thin trunk below. The
	// leaf texture runs on smoothly below the crown, so its mip level
	// doesn't jump at the join.
	float v = UV2.y * 0.5 + 0.5;
	uv = vec2(UV2.x * 0.5 + 0.5, 1.0 - (v - crown_v) / max(1.0 - crown_v, 0.01));
	trunk_px = v < crown_v;
	if (trunk_px && abs(UV2.x) > trunk_w) discard;
#endif
	if (uv.x < -0.5 || trunk_px) {
		// A far tree's trunk (see tree_mesh): plain bark grey-brown.
		ALBEDO = vec3(0.075, 0.062, 0.05) * (0.85 + tree_rand * 0.3);
		NORMAL = crown_normal;
		ROUGHNESS = 0.9;
	} else {
	vec4 t = texture(leaf_tex, uv);
#ifdef FAR_WOODS
	// One texture across a whole crown makes leaves the size of branches:
	// its colour is taken finer, as a crown of cards shows it.
	// (The texture is clear black between leaves, so its blurred levels are
	// darkened by the gaps: divided back out.)
	vec4 fine = texture(leaf_tex, uv * 3.0 + 0.37);
	t.rgb = mix(vec3(0.8), min(fine.rgb / max(fine.a, 0.02), vec3(1.0)), smoothstep(0.02, 0.25, fine.a));
	// Far off the leaf texture's blurred levels fill the whole square: kept
	// to a soft round crown, so its edges never show the quad.
	float r = length(vec2(UV2.x, uv.y * 2.0 - 1.0));
	t.a *= 1.0 - smoothstep(0.75, 1.0, r);
	// Shaded as a crown of cards is: inner leaves darker, the top lighter.
	inn = r;
	tp = 1.0 - uv.y;
#endif
	// Mipmaps average the leaf alpha toward the gaps, so distant cards
	// would fall under the cut-off and vanish. Boost alpha with the mip level.
	vec2 texel = uv * 256.0;
	float lod = log2(max(max(length(dFdx(texel)), length(dFdy(texel))), 1.0));
	t.a *= 1.0 + lod * 0.3;
	NORMAL = crown_normal;
	// Inner leaves sit in the shade of outer ones; the top of the crown
	// catches the open sky.
	vec3 leaf = tint;
	float alpha = t.a;
	bool evergreen = kind_seasons ? kind_winter[sp].a > 0.5 : abs(species - 3.0) < 0.5;
	vec3 look = kind_seasons ? kind_look[sp] : season_look.xyz;
	if (evergreen) {
		// Red cedar bronzes in the cold; spruce stays blue-green.
		if (kind_seasons) leaf = mix(leaf, kind_winter[sp].rgb, season_look.y * 0.7);
	} else {
		// Each tree turns, drops and leafs out a little earlier or later
		// than its neighbours.
		float turn = clamp(look.x * 1.5 - tree_rand * 0.5, 0.0, 1.0);
		float bare = clamp(look.y * 1.4 - tree_rand * 0.4, 0.0, 1.0);
		// Fall colour, the kind's own (docs/trees.md); sugar maples vary
		// tree to tree from scarlet through orange to yellow.
		vec3 fall = kind_seasons ? kind_fall[sp] * (0.8 + tree_rand * 0.4) : vec3(0.24, 0.09, 0.02) * (0.8 + tree_rand * 0.4);
		if (sp == 0) {
			fall = mix(vec3(0.5, 0.06, 0.01), vec3(0.78, 0.3, 0.02), tree_rand);
			if (tree_rand > 0.75) fall = vec3(0.7, 0.46, 0.03);
		}
		// Green goes to yellow first, then to the tree's own colour.
		leaf = mix(leaf, vec3(0.32, 0.3, 0.03), smoothstep(0.0, 0.5, turn) * (1.0 - smoothstep(0.5, 1.0, turn)));
		leaf = mix(leaf, fall, smoothstep(0.35, 1.0, turn));
		// New leaves are a pale yellow-green; crabapples bloom pink first.
		vec3 fresh = leaf * vec3(1.55, 1.45, 0.45);
		if (kind_seasons && kind_bloom[sp].a > 0.5) fresh = kind_bloom[sp].rgb;
		leaf = mix(leaf, fresh, look.z);
		// Leaves fall and the crown becomes a lace of fine grey-brown twigs:
		// each card switches to a branching twig texture. Up close it reads
		// as twigs; far off its mipmaps blur it to a soft haze, never black
		// speckle. Benchmark: aerial and oblique photos of Indiana woods in
		// November to March.
		float b = smoothstep(0.3, 0.9, bare);
		vec4 tw = texture(twig_tex, uv);
		// Bare crowns from above are a see-through haze (aerial photos show
		// the snow or leaf litter through them), so the twigs get much less
		// of the far-off alpha boost than leaves do.
		tw.a *= 1.0 + lod * 0.12;
		// A far tree has a few big cards instead of many small ones, so the
		// same thin twigs would leave its crown empty and its trunk standing
		// alone (black poles in winter woods). Seen across the woods, a
		// line of sight passes through many crowns and they close into a
		// grey-brown haze, so its twigs get the boost a whole near crown's
		// overlapping cards add up to; from straight above they stay thin.
		float across = 1.0 - smoothstep(0.55, 0.9, abs(dot(normalize(-VERTEX), (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)));
		tw.a *= 1.0 + far_card * lod * 0.35 * across;
		float h = fract(sin(dot(floor(leaf_pos * 0.55), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		alpha = mix(alpha, tw.a * step(bare * 0.3, h), b);
		// A grown tree's own limbs show in winter; its cards only add the
		// finest twigs, thinly.
		if (zone_mode == 1) alpha *= mix(1.0, 0.55, b);
		t.rgb = mix(t.rgb, tw.rgb, b);
		vec3 twig = vec3(0.2, 0.17, 0.15) * (0.85 + tree_rand * 0.3);
		leaf = mix(leaf, twig, b);
	}
	// Snow resting on the tops of the crowns.
	leaf = mix(leaf, vec3(0.4, 0.42, 0.45), snow * smoothstep(0.35, 0.95, tp) * 0.75);
	// A crown holds real shade: the leaves deep inside and on its underside
	// see only a little of the sky, so it reads as a solid with dark gaps,
	// not lit from within. Every version of a tree (grown, cards, far quad)
	// carries the same inn and tp, so they are shaded alike.
	float crown = mix(LEAF_INNER, 1.1, smoothstep(0.1, 0.95, inn)) * mix(LEAF_UNDER, 1.12, tp);
	ALBEDO = leaf * t.rgb * crown * 2.0;
#ifdef FAR_WOODS
	ALBEDO *= far_shade;
#endif
	// A card seen edge-on smears its leaves into long streaks; real crowns
	// never show them. Fade each card out as it turns edge-on, judged by its
	// own flat face (from screen derivatives), not the crown normal.
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	alpha *= smoothstep(0.1, 0.35, abs(dot(face, normalize(-VERTEX))));
#ifndef FAR_WOODS
	// The sun's shadow map (square-on): the sun comes through the crown's
	// gaps (FLECK_GLSL), so its shadow is dappled, not a solid hole.
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		alpha *= sun_keep(sun_xy, leaf_open(inn, evergreen, fleck_fade));
	}
#endif
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	// With MSAA, leaf edges become partial coverage instead of popping on
	// and off as the camera moves.
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = uv * 128.0;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	}
}
"""

## FarWoods' stand-ins: the leaf shader, one quad a tree (FAR_WOODS).
static func far_shader_code() -> String:
	return LEAF_SHADER.replace("render_mode cull_disabled;", "render_mode cull_disabled;\n#define FAR_WOODS")


## The cheap trees' trunks (TreeField), with the same handover.
const CARD_BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
global uniform vec4 tree_fade;
uniform bool fade_on = false;
uniform int zone_mode = 0;
uniform vec4 grown_cam = vec4(0.0);
uniform vec4 grown_zone = vec4(0.0, 0.0, 1.0, 0.0);
varying vec2 keep;
varying float fleck_fade;
varying vec2 sun_xy;
""" + KEEP_GLSL + FLECK_GLSL + """
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	keep = band_keep(origin, INSTANCE_CUSTOM.a * 32.0 < 15.5, shadow_pass);
	// A tier's near tree shadows thin out with the crown's (near_fade).
	fleck_fade = shadow_pass ? near_fade(origin) : 0.0;
	VERTEX *= step(0.0001, keep.y - keep.x) * step(fleck_fade, 0.999);
	sun_xy = shadow_pass ? sun_plane(MODEL_MATRIX, MODELVIEW_MATRIX, VERTEX) : vec2(0.0);
}
void fragment() {
	// The sun's shadow map is drawn square-on (orthographic): there each
	// tree switches at the middle of the handover instead of dithering, so
	// its shadow on the ground is whole, not speckled.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	float dth = shadow_pass ? 0.5 : dither(FRAGCOORD.xy);
	if (dth < keep.x || dth >= keep.y) discard;
	if (shadow_pass && sun_keep(sun_xy, fleck_fade) < 0.5) discard;
	float ridges = 0.85 + 0.15 * sin(UV.x * 40.0 + sin(UV.y * 6.0) * 2.0);
	ALBEDO = vec3(0.085, 0.07, 0.058) * ridges;
	ROUGHNESS = 0.95;
}
"""

## Grown bark: each kind's own pattern (TreeKinds bark), in real metres
## round and along the limb. Young limbs are smooth; sycamore limbs go
## white as their outer bark peels.
const BARK_SHADER := """
shader_type spatial;
global uniform float snow;
uniform int zone_mode = 1;
uniform vec4 grown_cam = vec4(0.0);
uniform vec4 grown_zone = vec4(0.0, 0.0, 1.0, 0.0);
uniform float sway = 0.006;
uniform vec3 bark_base[16];
uniform vec3 bark_dark[16];
uniform vec3 bark_patch[16];
uniform vec2 bark_kind[16];
varying vec2 keep;
varying float species;
varying float radius;
varying float hfrac;
varying vec3 tint;
varying float fleck_fade;
varying vec2 sun_xy;
""" + FLECK_GLSL + """
float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float code = floor(INSTANCE_CUSTOM.a * 32.0);
	species = mod(code, 16.0);
	keep = vec2(0.0, 1.0);
	if (grown_cam.w > 0.5) {
		float d = distance(origin, grown_cam.xyz);
		float t_mid = smoothstep(grown_zone.x - grown_zone.z, grown_zone.x, d);
		float t_far = smoothstep(grown_zone.y - grown_zone.z, grown_zone.y, d);
		keep = zone_mode == 1 ? vec2(t_mid, 1.0) : vec2(t_far, t_mid);
		// The light tree casts the full one's shadow (band_keep).
		if (PROJECTION_MATRIX[3][3] > 0.5 && zone_mode == 2 && grown_zone.x > 0.0) {
			keep = vec2(t_mid, 1.0);
		}
		// A tier's near tree shadows (grown_zone.w): cast out to their reach
		// with no hand-over, as band_keep has the leaves', thinning out with
		// the crown's (near_fade, in fragment()).
		if (PROJECTION_MATRIX[3][3] > 0.5 && grown_zone.w > 0.0) {
			keep = d < grown_zone.w ? vec2(0.0, 1.0) : vec2(0.0);
		}
	}
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	fleck_fade = shadow_pass ? near_fade(origin) : 0.0;
	VERTEX *= step(0.0001, keep.y - keep.x) * step(fleck_fade, 0.999);
	float phase = TIME * 1.1 + origin.x * 0.31 + origin.z * 0.17;
	float s = sin(phase + VERTEX.y * 0.25) * sway * VERTEX.y;
	VERTEX.x += s;
	VERTEX.z += s * 0.6;
	sun_xy = shadow_pass ? sun_plane(MODEL_MATRIX, MODELVIEW_MATRIX, VERTEX) : vec2(0.0);
	radius = COLOR.r * 0.5;
	hfrac = COLOR.g;
	tint = vec3(0.9 + 0.2 * fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453));
}
void fragment() {
	// The sun's shadow map is drawn square-on (orthographic): there each
	// tree switches at the middle of the handover instead of dithering, so
	// its shadow on the ground is whole, not speckled.
	float dth = PROJECTION_MATRIX[3][3] > 0.5 ? 0.5 : dither(FRAGCOORD.xy);
	if (dth < keep.x || dth >= keep.y) discard;
	// The trunk's shadow thins out with its crown's (near_fade).
	if (PROJECTION_MATRIX[3][3] > 0.5 && sun_keep(sun_xy, fleck_fade) < 0.5) discard;
	int sp = int(species + 0.5);
	vec3 base = bark_base[sp];
	vec3 dark = bark_dark[sp];
	vec3 light = bark_patch[sp];
	int pattern = int(bark_kind[sp].x + 0.5);
	float sc = bark_kind[sp].y;
	vec2 uv = UV / sc;
	float depth = 1.0;  // 1 on the bark's face, 0 down in a crack
	vec3 col = base;
	if (pattern == 0) {
		// Plates: blocks split by cracks, each a shade of its own.
		vec2 g = vec2(uv.x * 1.6, uv.y * 0.55);
		g.x += floor(g.y) * 0.5;
		vec2 f = fract(g);
		float edge = min(min(f.x, 1.0 - f.x) * 2.4, min(f.y, 1.0 - f.y) * 1.2);
		depth = smoothstep(0.0, 0.25, edge + noise(uv * 6.0) * 0.15);
		col = mix(base, light, hash(floor(g)) * 0.6);
	} else if (pattern == 1) {
		// Long furrows between flat-topped ridges that join and part.
		float w = uv.x * 2.2 + noise(vec2(uv.x * 2.0, uv.y * 0.35)) * 1.6;
		depth = smoothstep(0.08, 0.4, abs(fract(w) - 0.5) * 2.0);
		col = mix(base, light, smoothstep(0.75, 1.0, depth) * noise(uv * 3.0) * 0.8);
	} else if (pattern == 2) {
		// Black walnut: ridges crossing into a diamond net.
		float a = abs(fract(uv.x * 1.8 + uv.y * 0.45 + noise(uv) * 0.3) - 0.5);
		float b = abs(fract(uv.x * 1.8 - uv.y * 0.45 + noise(uv + 9.0) * 0.3) - 0.5);
		depth = smoothstep(0.05, 0.3, min(a, b) * 2.0);
		depth = 1.0 - depth * 0.85;
	} else if (pattern == 3) {
		// Shaggy: long strips lifting at their ends.
		float strip = floor(uv.x * 3.0);
		float lift = fract(uv.y * (0.35 + hash(vec2(strip, 1.0)) * 0.4) + hash(vec2(strip, 2.0)));
		depth = smoothstep(0.0, 0.18, abs(fract(uv.x * 3.0) - 0.5) * 2.0 - 0.2) * mix(0.55, 1.0, lift);
		col = mix(base, light, hash(vec2(strip, floor(uv.y * 0.8))) * 0.7);
	} else if (pattern == 4) {
		// Hackberry: smooth grey with corky warts and short ridges.
		float n = noise(uv * vec2(7.0, 3.0));
		float wart = smoothstep(0.68, 0.8, n);
		col = mix(base, light, wart * 0.7);
		depth = 1.0 - smoothstep(0.62, 0.68, n) * (1.0 - wart) * 0.6;
	} else if (pattern == 6) {
		// Red cedar: thin fibres shredding in long vertical strips.
		float f = abs(fract(uv.x * 6.0 + noise(vec2(uv.x * 4.0, uv.y * 0.6)) * 2.0) - 0.5) * 2.0;
		depth = smoothstep(0.05, 0.5, f);
		col = mix(dark, light, depth * noise(uv * vec2(3.0, 0.5)));
	} else if (pattern == 7) {
		// Sycamore: the brown outer bark flakes off in patches, showing
		// cream, white and pale green; high limbs are almost all white.
		float n = noise(uv * 2.2) * 0.6 + noise(uv * 5.3) * 0.4;
		float white = smoothstep(0.22, 0.04, radius) * 0.9 + smoothstep(0.25, 0.8, hfrac) * 0.45;
		float peel = smoothstep(0.62 - white, 0.66 - white, n);
		vec3 inner = mix(light, vec3(0.62, 0.68, 0.55), noise(uv * 3.1 + 4.0) * 0.4);
		col = mix(base, inner, peel);
		depth = 1.0 - (1.0 - smoothstep(0.0, 0.05, abs(n - (0.64 - white)))) * 0.4;
	}
	// Twigs and young limbs are smooth, whatever the bark becomes.
	float young = smoothstep(0.06, 0.012, radius);
	if (pattern != 7) col = mix(col, mix(base, light, 0.35), young);
	depth = mix(depth, 1.0, young);
	col = mix(dark, col, depth);
	// Bark reflects little light (albedo about 0.1 to 0.25; sycamore's
	// peeled limbs much more).
	col *= tint * 0.62;
	// Snow along the tops of limbs.
	float upward = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	col = mix(col, vec3(0.8, 0.82, 0.86), snow * smoothstep(0.45, 0.8, upward) * 0.85);
	ALBEDO = col;
	AO = mix(0.45, 1.0, depth);
	ROUGHNESS = 0.9;
}
"""

static var _shaders := {}  # code -> Shader
static var _leaf_mats := {}  # "sp,lod" -> ShaderMaterial
static var _bark_mats := {}  # lod -> ShaderMaterial
static var _textures := {}  # sp -> ImageTexture
static var _card_mats: Array[ShaderMaterial] = []  # every card material, for the zone and season values
static var _zone := Vector4.ZERO
static var _cam := Vector4.ZERO
static var _eye := Vector4.ZERO
static var _dist := Vector4.ZERO
static var _eye_frame := -1
## How far brush and the far woods are drawn (set by WildView; 0 when
## there are none), for the hand-overs.
static var brush_reach := 0.0
static var far_reach := 0.0
## WildView's tree_fade (the camera's x, z, the cards' reach, the camera's
## height), kept here for TreeField.
static var wild_fade := Vector4.ZERO
static var _look := PackedVector3Array()
static var _seasons := false


## The near and middle radii for this machine: scaled with the quality
## tier; the browser draws no full trees, only the light ones, nearer.
static func radii() -> Vector2:
	var d := clampf(GraphicsQuality.detail, 0.4, 2.5)
	if browser():
		# Low (the browser's start) keeps today's cheap trees everywhere.
		return Vector2.ZERO if d < 0.6 else Vector2(0.0, MID * 0.55 * d)
	return Vector2(NEAR * d, MID * d)


static func browser() -> bool:
	return OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Every frame, from the grown trees: where the camera is and how far each
## band reaches (radius 0 turns the grown trees off), and how far their
## shadows reach on a tier with only the nearest trees' (0: no limit).
static func set_zone(cam: Vector3, near_r: float, mid_r: float, on: bool, shadow_r := 0.0) -> void:
	_cam = Vector4(cam.x, cam.y, cam.z, 1.0 if on else 0.0)
	_zone = Vector4(near_r, mid_r, BAND, shadow_r)
	for m in _all_mats():
		m.set_shader_parameter("grown_cam", _cam)
		m.set_shader_parameter("grown_zone", _zone)


## Once a frame, from WildView: each kind's look for the date (its own
## leaf-out, colour and leaf-fall), in months as Seasons counts them.
static func set_season(months: float, on := true) -> void:
	_look.resize(16)
	for sp in TreeKinds.count():
		_look[sp] = TreeKinds.season(sp, months if on else 6.5)
	_seasons = true
	for m in _all_mats():
		m.set_shader_parameter("kind_look", _look)
		m.set_shader_parameter("kind_seasons", true)


## Once a frame (the first TreeField to draw calls it): where the camera is
## and how far each version of the cheap trees reaches, for the hand-overs.
## The full cards give way to the light ones at TreeField.NEAR (scaled
## with the quality tier).
static func set_eye(eye: Vector3, again := false) -> void:
	var frame := Engine.get_process_frames()
	if frame == _eye_frame and not again:
		return
	_eye_frame = frame
	_eye = Vector4(eye.x, eye.y, eye.z, 1.0)
	_dist = Vector4(card_near(), brush_reach, far_reach, 0.0)
	for m in _card_mats:
		m.set_shader_parameter("lod_eye", _eye)
		m.set_shader_parameter("lod_dist", _dist)


## Where TreeField's full cards hand over to its light ones.
static func card_near() -> float:
	return TreeField.NEAR * GraphicsQuality.detail


## The camera and reaches the shaders were last given (lod_eye, lod_dist).
static func eye() -> Vector4:
	return _eye


static func reaches() -> Vector4:
	return _dist


## The share of pixels [from, to) one version of a tree draws: KEEP_GLSL's
## band_keep worked out here too, for the tests (the grown bands left out:
## `light` TreeField's light cards, else its full ones; `far` FarWoods).
static func keep_share(origin: Vector3, light: bool, far: bool, fades := true) -> Vector2:
	var de := origin.distance_to(Vector3(_eye.x, _eye.y, _eye.z))
	var b4 := 0.0
	if fades:
		var fade := wild_fade
		var jitter := (hash01(origin, 17.0) - 0.5) * 0.3 * fade.z
		b4 = smoothstep(fade.z * 0.7, fade.z * 0.97, Vector2(origin.x, origin.z).distance_to(Vector2(fade.x, fade.y)) + jitter)
		var gone := smoothstep(1200.0, 1700.0, fade.w)
		if _dist.z > 0.0:
			gone = maxf(gone, smoothstep(_dist.z * 0.85, _dist.z, de))
		if hash01(origin, 0.0) < gone:
			return Vector2.ZERO
	var b3 := maxf(smoothstep(_dist.x - LIGHT_BAND, _dist.x, de), b4)
	if far:
		return Vector2(0.0, b4)
	return Vector2(b4, b3) if light else Vector2(b3, 1.0)


## KEEP_GLSL's tree_hash.
static func hash01(origin: Vector3, salt: float) -> float:
	var p := Vector2(fposmod(floorf(origin.x * 2.0), 4096.0), fposmod(floorf(origin.z * 2.0), 4096.0)) + Vector2(salt, salt)
	var p3 := Vector3(fposmod(p.x * 0.1031, 1.0), fposmod(p.y * 0.1031, 1.0), fposmod(p.x * 0.1031, 1.0))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	return fposmod((p3.x + p3.y) * p3.z, 1.0)


static func _all_mats() -> Array:
	var out: Array = _card_mats.duplicate()
	out.append_array(_leaf_mats.values())
	out.append_array(_bark_mats.values())
	return out


## A card material (TreeField's): the shared leaf shader with the kinds'
## colours filled in, and kept up to date with the zone and season.
## One shader for each piece of code, shared by every material using it:
## each shader is compiled once, not once per kind and level (a stall the
## first time each is drawn).
static func shader(code: String) -> Shader:
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	return _shaders[code]


static func card_material(code: String, mode: int, fades: bool, leaf_tex: Texture2D, twig_tex: Texture2D,
		light := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(code)
	if leaf_tex:
		m.set_shader_parameter("leaf_tex", leaf_tex)
		m.set_shader_parameter("twig_tex", twig_tex)
	m.set_shader_parameter("fade_on", fades)
	m.set_shader_parameter("zone_mode", mode)
	m.set_shader_parameter("light_card", light)
	_fill_kinds(m)
	_card_mats.append(m)
	return m


static func _fill_kinds(m: ShaderMaterial) -> void:
	var fall := PackedVector3Array()
	var bloom := PackedVector4Array()
	var winter := PackedVector4Array()
	for sp in 16:
		var k := TreeKinds.kind(sp) if sp < TreeKinds.count() else TreeKinds.kind(0)
		var f: Color = Color(k.fall).srgb_to_linear()
		fall.append(Vector3(f.r, f.g, f.b))
		var b: Color = k.bloom
		var bl := b.srgb_to_linear()
		bloom.append(Vector4(bl.r, bl.g, bl.b, b.a))
		var w: Color = Color(k.winter).srgb_to_linear()
		winter.append(Vector4(w.r, w.g, w.b, 1.0 if k.evergreen else 0.0))
	m.set_shader_parameter("kind_fall", fall)
	m.set_shader_parameter("kind_bloom", bloom)
	m.set_shader_parameter("kind_winter", winter)
	m.set_shader_parameter("grown_cam", _cam)
	m.set_shader_parameter("grown_zone", _zone)
	m.set_shader_parameter("lod_eye", _eye)
	m.set_shader_parameter("lod_dist", _dist)
	if _seasons:
		m.set_shader_parameter("kind_look", _look)
		m.set_shader_parameter("kind_seasons", true)


## A grown tree's leaves: the kind's own leaf texture, at the band its
## detail level draws in.
static func leaf_material(sp: int, lod: int) -> ShaderMaterial:
	var key := "%d,%d" % [sp, lod]
	if _leaf_mats.has(key):
		return _leaf_mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader(LEAF_SHADER)
	m.set_shader_parameter("leaf_tex", leaf_texture(sp))
	m.set_shader_parameter("twig_tex", TreeField.twig_texture())
	m.set_shader_parameter("zone_mode", 1 if lod == TreeMesher.Lod.FULL else 2)
	m.set_shader_parameter("sway", 0.006)
	_fill_kinds(m)
	_leaf_mats[key] = m
	return m


static func bark_material(lod: int) -> ShaderMaterial:
	if _bark_mats.has(lod):
		return _bark_mats[lod]
	var m := ShaderMaterial.new()
	m.shader = shader(BARK_SHADER)
	m.set_shader_parameter("zone_mode", 1 if lod == TreeMesher.Lod.FULL else 2)
	var base := PackedVector3Array()
	var dark := PackedVector3Array()
	var light := PackedVector3Array()
	var kinds := PackedVector2Array()
	for sp in 16:
		var k := TreeKinds.kind(sp) if sp < TreeKinds.count() else TreeKinds.kind(0)
		var b: Array = k.bark
		for pair in [[base, b[0]], [dark, b[1]], [light, b[2]]]:
			var c: Color = Color(pair[1]).srgb_to_linear()
			pair[0].append(Vector3(c.r, c.g, c.b))
		kinds.append(Vector2(float(b[3]), float(b[4])))
	m.set_shader_parameter("bark_base", base)
	m.set_shader_parameter("bark_dark", dark)
	m.set_shader_parameter("bark_patch", light)
	m.set_shader_parameter("bark_kind", kinds)
	m.set_shader_parameter("grown_cam", _cam)
	m.set_shader_parameter("grown_zone", _zone)
	_bark_mats[lod] = m
	return m


# --------------------------------------------------------------- leaf textures

## Is the kind's leaf texture ready (made a piece at a time by LeafPainter)?
static func has_texture(sp: int) -> bool:
	return _textures.has(sp)


static func leaf_texture(sp: int) -> Texture2D:
	if not _textures.has(sp):
		var p := LeafPainter.new(sp)
		while not p.step(1_000_000):
			pass
	return _textures[sp]


static func store_texture(sp: int, tex: Texture2D) -> void:
	_textures[sp] = tex


## Paints one kind's leaves onto a card texture in slices: a few stamps of
## the leaf's real shape at its real size (TreeKinds leaf_cm, for a card
## TreeMesher.CARD[0] across), turned and scattered, thinner toward the edge.
class LeafPainter:
	var sp := 0
	var _img: Image
	var _stamps := []
	var _rng := RandomNumberGenerator.new()
	var _placed := 0
	var _count := 0

	func _init(kind: int) -> void:
		sp = kind
		_rng.seed = 4111 + kind
		_img = Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
		_img.fill(Color(0, 0, 0, 0))

	func step(budget_us: int) -> bool:
		var start := Time.get_ticks_usec()
		var k := TreeKinds.kind(sp)
		var px_per_m := float(TEX) / TreeMesher.CARD[0]
		var leaf_px := clampf(float(k.leaf_cm) / 100.0 * px_per_m, 3.0, 90.0)
		while _stamps.size() < 4:
			_stamps.append(_stamp(int(k.leaf), leaf_px, _stamps.size()))
			if Time.get_ticks_usec() - start > budget_us:
				return false
		if _count == 0:
			# Enough leaves to fill most of the card with some gaps.
			var area := float(TEX * TEX) * 0.42
			var one := leaf_px * leaf_px * (0.35 if int(k.leaf) != TreeKinds.Leaf.COMPOUND else 1.2)
			_count = clampi(int(area / maxf(one, 4.0)), 60, 2600)
			if int(k.leaf) == TreeKinds.Leaf.SCALE or int(k.leaf) == TreeKinds.Leaf.NEEDLE:
				_count = 260  # sprays 40 px across: enough to fill, with gaps
		while _placed < _count:
			var s: Image = _stamps[_rng.randi() % _stamps.size()]
			var c := Vector2(_rng.randf_range(0, TEX), _rng.randf_range(0, TEX))
			_placed += 1
			if (c - Vector2(TEX, TEX) * 0.5).length() > TEX * _rng.randf_range(0.3, 0.52):
				continue
			var shade := _rng.randf_range(0.62, 1.0)
			var tinted := s
			if shade < 0.97:
				tinted = s.duplicate()
				tinted.adjust_bcs(shade, 1.0, 1.0)
			_img.blend_rect(tinted, Rect2i(0, 0, s.get_width(), s.get_height()), Vector2i(c) - s.get_size() / 2)
			if Time.get_ticks_usec() - start > budget_us:
				return false
		_img.generate_mipmaps()
		TreeLook.store_texture(sp, ImageTexture.create_from_image(_img))
		return true

	## One leaf (or a compound leaf, or a spray of needles) in grey on
	## transparency, turned to one of a few angles.
	func _stamp(shape: int, len_px: float, turn: int) -> Image:
		var size := int(ceil(len_px * (2.6 if shape == TreeKinds.Leaf.COMPOUND else 1.3))) + 4
		if shape == TreeKinds.Leaf.SCALE or shape == TreeKinds.Leaf.NEEDLE:
			size = 40
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ang := TAU * float(turn) / 4.0 + _rng.randf_range(-0.4, 0.4)
		var dir := Vector2(cos(ang), sin(ang))
		var mid := Vector2(size, size) * 0.5
		match shape:
			TreeKinds.Leaf.LOBED, TreeKinds.Leaf.OVATE:
				_blade(img, mid, dir, len_px * 0.5, shape == TreeKinds.Leaf.LOBED)
			TreeKinds.Leaf.COMPOUND:
				# Leaflets in pairs along a stalk.
				var n := 7
				var stalk := len_px * 2.4
				for i in n:
					var t := (float(i) + 0.5) / float(n) - 0.5
					var at := mid + dir * t * stalk
					for side in [-1.0, 1.0]:
						var d2: Vector2 = (dir + Vector2(-dir.y, dir.x) * float(side) * 1.5).normalized()
						_blade(img, at + d2 * len_px * 0.45, d2, len_px * 0.45, false)
			_:
				# A spray of needles or scale leaves off a twig.
				for i in 26:
					var t := float(i) / 26.0
					var at := mid + dir * (t - 0.5) * size * 0.85
					var side := -1.0 if i % 2 == 0 else 1.0
					var d2 := (dir * 0.6 + Vector2(-dir.y, dir.x) * side).normalized()
					var l := (5.0 if shape == TreeKinds.Leaf.NEEDLE else 3.5) * (1.0 - absf(t - 0.5))
					for s in int(l * 2.0):
						var q := at + d2 * float(s) * 0.5
						_dot(img, q, 1.3 if shape == TreeKinds.Leaf.SCALE else 0.8)
				for s in int(size * 1.7):
					_dot(img, mid + dir * (float(s) / (size * 1.7) - 0.5) * size * 0.85, 0.9)
		return img

	## A leaf blade: an ellipse, or with lobes (maple, oak, sycamore).
	func _blade(img: Image, c: Vector2, dir: Vector2, half: float, lobed: bool) -> void:
		var wid := half * (0.85 if lobed else 0.5)
		var r := int(ceil(half)) + 1
		var n := Vector2(-dir.y, dir.x)
		for y in range(int(c.y) - r, int(c.y) + r + 1):
			for x in range(int(c.x) - r, int(c.x) + r + 1):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var d := Vector2(x, y) - c
				var along := d.dot(dir) / half
				var across := d.dot(n) / wid
				var rr := along * along + across * across
				var edge := 1.0
				if lobed:
					var a := atan2(across, along)
					edge = 0.78 + 0.22 * cos(a * 5.0)
				if rr <= edge * edge:
					var l := 0.88 + 0.12 * along
					if absf(across) < 0.07:
						l *= 0.9
					img.set_pixel(x, y, Color(l, l, l, 1.0))

	func _dot(img: Image, q: Vector2, r: float) -> void:
		for y in range(int(q.y - r), int(q.y + r) + 1):
			for x in range(int(q.x - r), int(q.x + r) + 1):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				if Vector2(x, y).distance_to(q) <= r:
					var l := _rng.randf_range(0.8, 1.0)
					img.set_pixel(x, y, Color(l, l, l, 1.0))
