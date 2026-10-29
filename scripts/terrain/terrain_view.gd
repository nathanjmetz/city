class_name TerrainView
extends Node3D
## Draws the land: ground, rivers and lakes, in square chunks streamed in
## around the camera, finer up close and coarser far away, like Cities:
## Skylines 2's terrain. Detail falls off smoothly with distance, the way the
## eye sees it: each vertex slides toward the next coarser level as it gets
## farther from the camera (geomorphing), so by the time a chunk switches to
## the coarser mesh it already looks exactly like it, and nothing pops.
## Trees are WildView's; past them the ground paints the woods' canopy.
##
## Benchmark: aerial photos of the White River valley near Petersburg,
## Indiana: tan and green crop fields, dark wooded hills and creek bottoms,
## a muddy green-brown river with bare sandy banks.
##
## It also grades the ground flat under roads and the lots along them, so
## roads sit on the land instead of cutting into it.

const CHUNK := 512.0
## Grid spacing for each level of detail, and how far each one reaches.
const STEPS := [8.0, 16.0, 32.0, 64.0, 128.0]
const REACH := [700.0, 1400.0, 2800.0, 5600.0, 9000.0]
## A chunk goes finer once it is MORPH_END of its reach away, and coarser
## only past HYST_OUT; its vertices finish morphing by MORPH_END, so the
## switch is seamless both ways.
const MORPH_END := 0.9
## Past the last level the land goes on, one square per chunk, out to here,
## so from high up it fades into the haze instead of ending at an edge.
const FAR_REACH := 20000.0
## The far land is rebuilt once the camera has moved this far from where it
## was last built, a few rows each frame.
const FAR_MOVE := 2048.0
## The far land is cut away inside this share of the last level's reach,
## where the chunks are, and sits this far lower so they win where both draw.
const FAR_CUT := 0.97
const FAR_DROP := 3.0
const FAR_BUDGET_MS := 2
const HYST_OUT := 0.95
## Ground graded flat this far each side of a road with lots (curb, walk,
## and the 32 m lots), fading out over the next few metres.
const LOT_GRADE := 34.0
const GRADE_FADE := 14.0
const REGRADE_CELL := 256.0  # metres: the grid _regrade finds touched strips with
## Mowed grass past a road's right of way before the wild cover starts.
const MOW_VERGE := 3.0
## How much of the woods floor a yard thins to lawn (see build_chunk).
const YARD_THIN := 0.6
## Milliseconds per frame spent building chunks after the first frame: the
## browser keeps it light, the desktop app spends more so the land keeps up
## with a fast scroll.
const BUDGET_MS := 6
const DESKTOP_BUDGET_MS := 12
## Chunks across the built-chunks mask the far sheet reads (wraps; must be
## wider than the chunks' reach both ways).
const MASK := 64
## The desktop app keeps the coarse levels of every chunk it has built, and
## in spare time builds them for the whole county ahead of the camera, so
## scrolling back or far only puts ready land on screen. Only coarse levels:
## a finest chunk is about 0.7 MB, a level 3 one about 10 KB, so the whole
## county's levels 3 and 4 fit an 8 GB Mac mini. Machines with this much
## memory or more (GB) keep level 2 too (about 250 MB for the county).
const PRELOAD_LODS := [4, 3]
const PRELOAD_BIG_LODS := [4, 3, 2]
const PRELOAD_BIG_GB := 30.0
## A guard on how many chunks are kept (the county is 72 x 72 chunks).
const CACHE_MAX := 16384
## Milliseconds of a settled frame spent preloading: small, so the quality
## governor never mistakes it for a slow machine (MACHINES slow_ms).
const PRELOAD_MS := 3
## How far the camera moves (metres, height counted) before the chunks'
## detail levels are worked out again; far smaller than any level's reach.
const SETTLE_MOVE := 8.0
## Rows of a chunk built between checks of the frame's budget.
const JOB_ROWS := 4

const SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
uniform vec4 lush : source_color = vec4(0.29, 0.38, 0.17, 1.0);
uniform vec4 dry : source_color = vec4(0.45, 0.47, 0.25, 1.0);
uniform vec4 dark : source_color = vec4(0.20, 0.28, 0.12, 1.0);
uniform vec4 soil : source_color = vec4(0.46, 0.40, 0.29, 1.0);
uniform vec4 litter : source_color = vec4(0.22, 0.20, 0.12, 1.0);
uniform vec4 canopy : source_color = vec4(0.13, 0.22, 0.09, 1.0);
uniform vec4 gravel : source_color = vec4(0.45, 0.43, 0.38, 1.0);
uniform vec4 spoil : source_color = vec4(0.52, 0.49, 0.43, 1.0);
uniform vec4 mud : source_color = vec4(0.42, 0.37, 0.27, 1.0);
// Where wild trees are drawn (WildView): centre x, z and reach. Past them
// the woods are painted as canopy.
global uniform vec4 tree_fade;
// The season (Seasons.look, set by DayNight): snow cover, and (autumn, bare,
// spring, dry) for leaves, harvest, green-up and dormant grass.
global uniform float snow;
global uniform vec4 season_look;
// Dormant grass: tan-olive in the pasture and ditches (fescue gone off,
// not straw), a muted olive in a town's mowed lawns.
uniform vec4 dormant : source_color = vec4(0.52, 0.48, 0.33, 1.0);
uniform vec4 lawn_dormant : source_color = vec4(0.45, 0.47, 0.30, 1.0);
uniform vec4 twigs : source_color = vec4(0.30, 0.27, 0.24, 1.0);
uniform vec4 fall_leaves : source_color = vec4(0.42, 0.27, 0.11, 1.0);
// The camera's x, height above the ground, z: level of detail is measured
// from it the way TerrainView picks chunk detail.
uniform vec3 lod_eye;
// Where this town sits in the region (Terrain.view_origin): the field and
// county road grid is the region's.
uniform vec2 region_origin;
// County road miles not painted (CountyGrid.hidden_texture): bulldozed ones.
// r north-south, g east-west.
uniform sampler2D county_hidden : hint_default_black, filter_nearest, repeat_enable;
uniform sampler2D county_miles : hint_default_black, filter_nearest, repeat_enable;
// Middle of the real map in region metres (Terrain.CENTRE; 36864 = Terrain.SIZE).
uniform vec2 map_centre;
// The state highways (Highways.texture): signed metres from each group of
// routes' middle line + 128, one group per channel, over the region map.
uniform sampler2D highway_field : hint_default_white, filter_nearest;
// The far land (TerrainView's far sheet) is cut away nearer than this, where
// the chunks draw the ground; 0 for the chunks themselves.
uniform float far_cut = 0.0;
// Which chunks are built (TerrainView._mask, chunk index wrapped by 64): the
// far sheet is only cut away over a built chunk, so land still being built
// shows the far sheet instead of a hole.
uniform sampler2D chunk_built : hint_default_white, filter_nearest, repeat_enable;
// The desktop's photographed ground (PhotoGround.glsl() goes here):
// PHOTO_GROUND
#ifdef DESKTOP_DETAIL
// Each yard's own lawn (LawnMap, LawnLook): 256 m tiles of 2 m texels in
// two arrays, and a page table (64 tiles across, centred on the town) of
// which layer + 1 holds each tile (0: none). a: lushness, weeds, grass
// kind, wear; b: mower stripes, their direction (cos 2a, sin 2a), shade.
uniform float lawn_on = 0.0;
uniform sampler2D lawn_pages : filter_nearest, hint_default_black;
uniform sampler2DArray lawn_a : filter_linear_mipmap, repeat_disable;
uniform sampler2DArray lawn_b : filter_linear_mipmap, repeat_disable;
#endif
// CUSTOM0: (height, normal x, normal z) on the next coarser level, and w the
// reach of this chunk's level (0 for the coarsest): vertices slide to the
// coarser level between MORPH_START and MORPH_END of that reach.

""" + CropCalendar.GLSL + """
varying vec3 world_pos;
varying vec4 cover;
varying float steep;
varying vec2 town;
varying float lift;

vec2 turn(vec2 p, float a) {
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

void vertex() {
	vec2 d = VERTEX.xz - lod_eye.xz;
	float morph = CUSTOM0.w > 0.0 ? smoothstep(CUSTOM0.w * 0.5, CUSTOM0.w * 0.9, sqrt(dot(d, d) + lod_eye.y * lod_eye.y)) : 0.0;
	VERTEX.y = mix(VERTEX.y, CUSTOM0.x, morph);
	vec3 coarse = vec3(CUSTOM0.y, sqrt(max(1.0 - CUSTOM0.y * CUSTOM0.y - CUSTOM0.z * CUSTOM0.z, 0.0)), CUSTOM0.z);
	NORMAL = normalize(mix(NORMAL, coarse, morph));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Woods past the drawn trees stand up as their canopy, about as tall as
	// the trees (a hardwood woodlot is 15-25 m): a shell over the land with a
	// shaded wall at each edge, as Flight Simulator and Anno draw far
	// forest, so they keep their volume and skyline where the trees stop,
	// not a flat painted ring. Lower in winter, when the crowns are bare
	// twigs; never on graded or mowed town land, where roads and lots lie.
	float reach_v = distance(world_pos.xz, tree_fade.xy);
	float painted_v = max(smoothstep(tree_fade.z * 0.55, tree_fade.z * 0.97, reach_v),
		smoothstep(250.0, 1100.0, tree_fade.w));
	// Only well off toward the horizon (Brawn 2026-10-24): nearer, the shell
	// stood up as steep green mesas on flat Grant County, and its slopes
	// lay over the county roads beside a fencerow; there the woods are
	// painted flat and the drawn trees give them height.
	float off = smoothstep(2500.0, 5000.0, distance(world_pos.xz, lod_eye.xz));
	lift = smoothstep(0.45, 0.8, COLOR.r) * painted_v * off * (1.0 - clamp(max(UV.x, UV.y) * 4.0, 0.0, 1.0));
	// Uneven, as crowns of different ages and species are: 10-18 m.
	float rough = textureLod(noise_soft, world_pos.xz / 90.0, 0.0).r;
	VERTEX.y += lift * mix(10.0, 18.0, rough) * (1.0 - season_look.y * 0.5);
	world_pos.y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	cover = COLOR;
	steep = 1.0 - NORMAL.y;
	town = UV;
}

// County roads (CountyGrid; keep the two the same): a gravel road on a
// mile of section line where the real county has one (county_miles: red
// north-south, green east-west, at line and mile wrapped to 64).

// Coverage, 0 to 1, of a strip `half_w` metres each side of the county
// roads near region point r, spread over `px` metres (its pixel footprint),
// so far off it thins out instead of crawling.
// Metres from the middle of the nearest state highway (up to 127). Past
// the map the land mirrors (Terrain), and so do the highways.
float highway_d(vec2 r) {
	// Filtered here, not by the sampler: its weights are too coarse.
	int n = textureSize(highway_field, 0).x;
	vec2 g = (1.0 - abs(mod((r - map_centre + 18432.0) / 36864.0, 2.0) - 1.0)) * float(n) - 0.5;
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	ivec2 lo = clamp(i, ivec2(0), ivec2(n - 1));
	ivec2 hi = clamp(i + 1, ivec2(0), ivec2(n - 1));
	vec3 a = mix(texelFetch(highway_field, lo, 0).rgb, texelFetch(highway_field, ivec2(hi.x, lo.y), 0).rgb, f.x);
	vec3 b = mix(texelFetch(highway_field, ivec2(lo.x, hi.y), 0).rgb, texelFetch(highway_field, hi, 0).rgb, f.x);
	vec3 v = abs(mix(a, b, f.y) * 255.0 - 128.0);
	return min(v.r, min(v.g, v.b));
}

// `px`: the pixel footprint across a north-south road (x) and across an
// east-west one (y). Only the footprint across a road blurs its edges: a
// road seen at a low angle is long in the pixel along it, not across, and
// summing both smeared it into a pale streak that faded out (look check
// 2026-10-25).
float county_road(vec2 r, float half_w, vec2 px) {
	vec2 w = max(vec2(half_w), px * 0.5);
	vec2 soft = max(vec2(0.35), px * 0.5);
	float ns_line = floor(r.x / 1608.0 + 0.5);
	float ew_line = floor(r.y / 1608.0 + 0.5);
	int ns_seg = int(floor(r.y / 1608.0));
	int ew_seg = int(floor(r.x / 1608.0));
	float ns = texelFetch(county_miles, ivec2(int(ns_line) & 63, ns_seg & 63), 0).r
		* (1.0 - texelFetch(county_hidden, ivec2(int(ns_line) & 63, ns_seg & 63), 0).r)
		* (1.0 - smoothstep(w.x - soft.x, w.x + soft.x, abs(r.x - ns_line * 1608.0))) * clamp(half_w / w.x, 0.0, 1.0);
	float ew = texelFetch(county_miles, ivec2(int(ew_line) & 63, ew_seg & 63), 0).g
		* (1.0 - texelFetch(county_hidden, ivec2(int(ew_line) & 63, ew_seg & 63), 0).g)
		* (1.0 - smoothstep(w.y - soft.y, w.y + soft.y, abs(r.y - ew_line * 1608.0))) * clamp(half_w / w.y, 0.0, 1.0);
	return max(ns, ew);
}

void fragment() {
	vec2 p = world_pos.xz;
	if (far_cut > 0.0) {
		vec2 e = p - lod_eye.xz;
		if (dot(e, e) + lod_eye.y * lod_eye.y < far_cut * far_cut
				&& texelFetch(chunk_built, ivec2(mod(floor(p / 512.0), 64.0)), 0).r > 0.5) {
			discard;
		}
	}
	float dist = length(VERTEX);
	float big = texture(noise_soft, p / 900.0).r;
	float mid = texture(noise_soft, turn(p, 1.1) / 210.0 + 0.31).r;
	float clump = texture(noise_soft, turn(p, 2.3) / 19.0 + 0.62).r;
	float grain = texture(noise_grain, turn(p, 0.7) / 3.1).r;
	float blades = texture(noise_grain, turn(p, 2.9) / 0.6 + 0.5).r;
	float fade = clamp(1.0 - dist / 180.0, 0.0, 1.0);

	// Pasture and lawn: the grass of the old ground. Mowed lawns, lots and
	// verges in town are an even turf: photos of Indiana yards in July show
	// soft lighter and darker greens, never the dark tussocks of a pasture.
	float mowed = smoothstep(0.2, 0.6, max(town.x, town.y));
	float dryness = smoothstep(0.42, 0.78, big * 0.55 + mid * 0.45);
	vec3 col = mix(lush.rgb, dry.rgb, dryness * mix(0.55, 0.4, mowed));
	// The desktop's photographed ground (PhotoGround): `pr` its detail over
	// the painted colour, `ps` its slope, blended in step with the colours.
	float pk = ph_on(dist);
	vec3 pr = vec3(1.0);
	vec2 ps = vec2(0.0);
	if (pk > 0.0) {
		pr = ph_grass(p);
		ps = ph_grass_s(p);
	}
	// Darker, lusher clumps; in a lawn only where it's green, since a dry
	// patch goes straw-light, and dark clumps in tan read as bare dirt.
	col = mix(col, dark.rgb, smoothstep(0.35, 0.95, clump) * mix(0.3, 0.14 * (1.0 - dryness), mowed));
	// How hard this lawn browns in a dry spell (1: as every lawn did).
	float lawn_resp = 1.0;
#ifdef DESKTOP_DETAIL
	// Each yard its own lawn (LawnMap, LawnLook; Nathan, 2026-10-29: "every
	// lawn is the same color"): watered and fed or left to the weather,
	// weedy or clean, fescue or bluegrass, striped by the mower, worn bare
	// along paths, thin under a big tree. Outside the lots, as before.
	vec4 la = vec4(0.5, 0.0, 0.5, 0.0);
	vec4 lb = vec4(0.0, 0.5, 0.5, 0.0);
	vec2 luv = p / 256.0;
	vec2 lgx = dFdx(luv);
	vec2 lgy = dFdy(luv);
	// Metres one pixel covers here.
	float foot = length(fwidth(p));
	if (lawn_on > 0.5) {
		ivec2 pc = ivec2(floor(luv)) + 32;
		if (pc.x >= 0 && pc.y >= 0 && pc.x < 64 && pc.y < 64) {
			float layer = floor(texelFetch(lawn_pages, pc, 0).r * 255.0 + 0.5) - 1.0;
			if (layer >= 0.0) {
				// The gradients of the whole map, not of the tile's own
				// coordinates (they jump at its edge, which would pick a
				// tiny mip there and draw a line round every tile).
				vec3 at = vec3(fract(luv), layer);
				la = textureGrad(lawn_a, at, lgx, lgy);
				lb = textureGrad(lawn_b, at, lgx, lgy);
			}
		}
	}
	// Far off, at several metres a pixel, the yards fade to the town's
	// average, so the far town never sparkles.
	float lot_far = smoothstep(6.0, 14.0, foot);
	la = mix(la, vec4(0.5, 0.0, 0.5, 0.0), lot_far);
	lb = mix(lb, vec4(0.0, 0.5, 0.5, 0.0), lot_far);
	float l_rich = clamp(la.r * 2.0 - 1.0, 0.0, 1.0);
	float l_tired = clamp(1.0 - la.r * 2.0, 0.0, 1.0);
	// Blotches 2 to 5 m across, at scales and turns no other layer uses.
	float patchy = texture(noise_soft, turn(p, 0.8) / 31.0 + 0.53).r;
	float blot = texture(noise_soft, turn(p, 1.9) / 13.0 + 0.11).r;
	// Fed and watered: a deep, cooler green.
	col *= mix(vec3(1.0), vec3(0.6, 0.8, 0.66), l_rich);
	// The grass: yellow-green fescue and rye to blue-green bluegrass.
	col *= 1.0 + (la.b * 2.0 - 1.0) * vec3(-0.12, -0.03, 0.18);
	// Never watered or fed: paler, with straw patches where it dries first.
	vec3 straw = mix(lawn_dormant.rgb, dormant.rgb, 0.5) * (0.88 + 0.24 * blot);
	float dry_spot = smoothstep(0.35, 0.75, patchy * 0.7 + blot * 0.3 + l_tired * 0.25);
	col = mix(col, straw, l_tired * mix(0.4, 0.8, dry_spot));
	// Weeds: light clover and crabgrass patches, dark clumps of coarse fescue.
	col = mix(col, col * vec3(1.16, 1.1, 0.8), smoothstep(0.5, 0.78, blot) * la.g * 0.75);
	col = mix(col, dark.rgb * 1.05, smoothstep(0.55, 0.82, 1.0 - patchy) * la.g * 0.45);
	// Under a big tree: thinner, darker grass with soil showing.
	col = mix(col, col * vec3(0.74, 0.8, 0.72), lb.a * 0.8);
	col = mix(col, soil.rgb * 0.7, lb.a * smoothstep(0.45, 0.8, blot) * 0.3);
	// An unwatered lawn browns far more in a dry spell; a watered one hardly.
	lawn_resp = la.r < 0.5 ? mix(2.6, 1.0, la.r * 2.0) : mix(1.0, 0.3, la.r * 2.0 - 1.0);
	// Worn ground: thin and tan at a path's edge, bare packed soil in it
	// (the map holds a soft line; the blotches give it a ragged edge).
	float l_wear = la.a + (blot - 0.5) * 0.3 + (grain - 0.5) * 0.12 * fade;
	float l_thin = smoothstep(0.16, 0.42, l_wear);
	float l_bare = smoothstep(0.5, 0.7, l_wear);
	col = mix(col, mix(col, straw, 0.55), l_thin * 0.65);
	col = mix(col, soil.rgb * (0.8 + 0.28 * clump), l_bare * 0.85);
	if (pk > 0.0 && l_bare > 0.0) {
		pr = mix(pr, ph_soil(p), l_bare * 0.8);
		ps = mix(ps, ph_soil_s(p) * 0.5, l_bare * 0.8);
	}
	// Mower stripes, 0.9 m passes back and forth: grass laid away from the
	// eye reads lighter, toward it darker, so which rows are light flips
	// with the view. Gone where a pass is under a few pixels (no moire), in
	// dormant grass and under snow.
	vec2 s2 = lb.gb * 2.0 - 1.0;
	float s_ang = atan(s2.y, s2.x + 0.0001) * 0.5;
	vec2 s_dir = vec2(cos(s_ang), sin(s_ang));
	float s_across = dot(p, vec2(-s_dir.y, s_dir.x)) / 1.8;
	float s_fw = min(foot / 1.8, 0.2);
	float s_sq = smoothstep(0.25 - s_fw, 0.25 + s_fw + 0.001, abs(fract(s_across) - 0.5)) * 2.0 - 1.0;
	vec3 l_eye = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float s_face = dot(normalize(l_eye.xz + vec2(0.0001)), s_dir);
	float s_k = lb.r * min(length(s2), 1.0) * (1.0 - smoothstep(0.1, 0.22, foot / 1.8))
		* (1.0 - season_look.w * 0.8) * (1.0 - smoothstep(0.1, 0.4, snow));
	col *= 1.0 + s_sq * mix(s_face, 1.0, 0.2) * 0.11 * s_k;
#endif
	// Spring green-up, then cool-season grass going tan and dormant in the
	// late-summer dry spell and over winter (Indiana pasture). A town's
	// mowed lawns (bluegrass and fescue) only go a muted olive, never sand:
	// the whole town read as desert from November to April (the critic,
	// 2026-10-26).
	col = mix(col, col * vec3(0.92, 1.12, 0.78), season_look.z);
	float brown = clamp(season_look.w * 1.1 - (1.0 - dryness) * 0.3, 0.0, 0.85);
	float lawn_brown = clamp(season_look.w * 0.45 * lawn_resp - (1.0 - dryness) * 0.1, 0.0, min(0.4 * max(lawn_resp, 1.0), 0.75));
	vec3 gone_off = mix(dormant.rgb, lawn_dormant.rgb, mowed);
	col = mix(col, gone_off * (0.85 + big * 0.3) * mix(1.0, 0.92 + 0.16 * clump, mowed), mix(brown, lawn_brown, mowed));

	// Crop fields (CropCalendar): the county's 40, 80 and 160 acre fields,
	// each with this year's crop in its rows, at today's stage: bare worked
	// soil, rows just up, the canopy closing, tassels, browning, stubble,
	// fall tillage or a green cover crop, read from the shared crop table.
	vec2 r = p + region_origin;
	ivec3 fld = crop_field(r);
	ivec2 slot = crop_slot(fld.xy);
	float pick = crop_h01(fld.xy, 7u);
	float across = fld.z == 1 ? r.x : r.y;
	// The stripe width from the smooth position, not from `across`: where
	// two fields' rows turn a corner, `across` jumps from r.x to r.y inside
	// one 2x2 pixel block, and its fwidth would blur a line along the border.
	vec2 rw = fwidth(r);
	float aw = fld.z == 1 ? rw.x : rw.y;
	vec3 to_eye = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float tilt = length(to_eye.xz) / max(abs(to_eye.y), 0.05);
	float bare;
	vec3 crop = crop_look_bare(slot, p, across, aw, tilt, mid, bare);
	// Each field a shade different (soil, variety, how it was sprayed).
	crop *= (0.93 + 0.14 * pick) * (0.92 + 0.16 * mid);
#ifdef DESKTOP_DETAIL
	// A field ends at its edge, not in a 30 m blur of crop into pasture
	// (aerial photos of Grant County: the plow line is sharp, the fencerow
	// or grass headland beside it): the land cover's crop share cut at half,
	// a pixel or two wide, wandering a little as a headland does.
	float cut = 0.5 + (clump - 0.5) * 0.12;
	float in_crop = smoothstep(cut - 0.03 - fwidth(cover.b), cut + 0.03 + fwidth(cover.b), cover.b) * 0.92;
#else
	float in_crop = smoothstep(0.3, 0.7, cover.b) * 0.92;
#endif
	col = mix(col, crop, in_crop);
	if (pk > 0.0 && in_crop > 0.0) {
		// Worked soil between the rows; the crop's own leaves over it.
		pr = mix(pr, mix(ph_grass(p * 1.6), ph_soil(p), bare), in_crop);
		ps = mix(ps, mix(ph_grass_s(p * 1.6) * 0.7, ph_soil_s(p) * 0.35, bare), in_crop);
	}

	// Woods: leaf litter under the trees up close; from far off, where the
	// trees aren't drawn, the canopy itself, lumpy with crowns.
	float crowns = texture(noise_soft, p / 11.0).r * 0.6 + clump * 0.4;
	vec3 leaves = mix(canopy.rgb, fall_leaves.rgb * (0.8 + 0.5 * mid), season_look.x);
	leaves = mix(leaves, twigs.rgb, season_look.y);
	// Crowns: aerial photos of hardwoods show each crown as a lit dome
	// about 8 m across with dark gaps between, not a flat green. A jittered
	// cell pattern gives each painted crown its own dome (lit by the real sun
	// through NORMAL below), tint and gap, fading to its average where a
	// crown is smaller than a few pixels so it never crawls.
	vec2 cq = turn(p, 0.4) / 7.5;
	vec2 ci = floor(cq);
	float f1 = 9.0;
	vec2 to_c = vec2(0.0);
	vec2 cell = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = ci + vec2(float(i), float(j));
			vec2 o = fract(sin(vec2(dot(g, vec2(127.1, 311.7)), dot(g, vec2(269.5, 183.3)))) * 43758.5453);
			vec2 dd = g + 0.15 + o * 0.7 - cq;
			float l = dot(dd, dd);
			if (l < f1) { f1 = l; to_c = dd; cell = g; }
		}
	}
	float crown_hash = fract(sin(dot(cell, vec2(41.3, 289.1))) * 43758.5453);
	float relief = 1.0 - smoothstep(0.12, 0.45, length(fwidth(cq)));
	vec2 slope = -to_c / 0.62;
	float gap = smoothstep(0.75, 1.05, length(slope));
	vec3 tint = mix(vec3(1.08, 1.04, 0.82), vec3(0.9, 1.0, 1.08), crown_hash);
	vec3 tops = leaves * 1.5 * mix(vec3(1.0), tint, 0.6) * (0.85 + 0.3 * big) * (0.8 + 0.4 * crowns);
	// As dark as the drawn woods it carries on from: their crowns shade
	// each other and the gaps between are in shadow, so seen from above they
	// read darker and a little bluer than a lit crown top (measured where
	// they meet in the browser, 2026-10-24; the canopy shell's own shaded
	// sides do the rest).
	tops *= vec3(0.9, 0.88, 0.93);
	tops *= mix(0.88, 1.0 - gap * 0.55, relief);
	// Painted past the trees drawn (fading in as they thin out, each crown
	// at its own distance, so the edge is ragged like the trees'), and under
	// them too from high up, as the woods look from a plane: all canopy.
	float reach_d = distance(p, tree_fade.xy) + (crown_hash - 0.5) * 0.3 * tree_fade.z;
	float painted = max(smoothstep(tree_fade.z * 0.55, tree_fade.z * 0.97, reach_d),
		smoothstep(250.0, 1100.0, tree_fade.w));
	// In a yard the trees stay but the ground under them is shaded, thin
	// lawn (TerrainView.YARD_THIN), not the woods' brown leaf litter, which
	// read as patches of bare dirt across every lot.
	float yard = clamp(town.y - town.x, 0.0, 1.0);
	// Under a woodlot's edge the floor is the shaded grass it grew out of
	// with leaf litter on it, not bare brown earth: a dark brown ring round
	// every wood read as a ditch or a burn scar from the air. Deep in the
	// wood (cover.r near 1) it is mostly litter, as photos of Indiana
	// hardwoods show.
	vec3 shade_grass = col * vec3(0.62, 0.7, 0.55);
	vec3 litter_floor = mix(shade_grass, litter.rgb * (0.8 + 0.4 * clump), 0.25 + 0.5 * smoothstep(0.55, 0.95, cover.r));
	vec3 yard_floor = mix(litter_floor, col * vec3(0.82, 0.86, 0.76), yard);
	vec3 woods = mix(yard_floor, tops, painted);
	// A ragged edge, as real woods have, not the straight line between samples.
	float in_woods = smoothstep(0.3, 0.65, cover.r + (clump - 0.5) * 0.45 + (mid - 0.5) * 0.25);
	col = mix(col, woods, in_woods);
	if (pk > 0.0 && in_woods > 0.0) {
		// Leaf litter on the floor, more of it deeper in; none on the
		// painted canopy (its crowns carry their own relief).
		float floor_k = in_woods * (1.0 - painted) * (1.0 - yard) * (0.4 + 0.6 * smoothstep(0.4, 0.9, cover.r));
		pr = mix(pr, ph_litter(p), floor_k);
		ps = mix(ps, ph_litter_s(p), floor_k);
		pr = mix(pr, vec3(1.0), in_woods * painted);
		ps = mix(ps, vec2(0.0), in_woods * painted);
	}
	// The dome of each painted crown, leaning the ground normal toward its edge.
	float dome = in_woods * painted * relief * (1.0 - gap) * (1.0 - season_look.y * 0.7);
	vec3 up_n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// The canopy shell's own slopes (its edges) from the drawn surface: they
	// face the sun or turn away from it, and are the woods' shaded sides.
	vec3 shell_n = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	shell_n *= sign(shell_n.y + 0.0001);
	float side = (1.0 - shell_n.y) * smoothstep(0.02, 0.2, lift);
	up_n = normalize(mix(up_n, shell_n, smoothstep(0.02, 0.2, lift)));
	col *= 1.0 - side * 0.45;
	vec3 crown_n = normalize(up_n + vec3(slope.x, 0.0, slope.y) * 1.1 * dome);
	crown_n = ph_lean(crown_n, ps, pk * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(crown_n, 0.0)).xyz);

	// County roads on the section lines of the PLSS mile grid (CR 100 N,
	// 200 E...): gravel with mowed ditches. They stop at the water and on
	// steep bluffs (CountyGrid.clears). The gravel runs on through town
	// (lots and fields keep off it), so a road met there meets it, not a gap
	// in the paint (Brawn 2026-10-24), and stops at the verge of a town road
	// it hasn't joined, as at a crossroads, rather than running under it
	// (UV.x: mowed). Its mowed ditches give way to the town's yards (UV.y).
	float px = fwidth(r.x) + fwidth(r.y);
	vec2 cross_px = vec2(length(vec2(dFdx(r.x), dFdy(r.x))), length(vec2(dFdx(r.y), dFdy(r.y))));
	float open_land = (1.0 - smoothstep(0.06, 0.12, cover.g)) * (1.0 - smoothstep(0.012, 0.02, steep));
	float verge = county_road(r, 8.0, cross_px) * open_land * (1.0 - smoothstep(0.2, 0.6, max(town.x, town.y)));
	float county = county_road(r, 3.5, cross_px) * open_land * (1.0 - smoothstep(0.3, 0.7, town.x));
	vec3 ditch = mix(lush.rgb, dry.rgb, 0.3);
	ditch = mix(ditch, dormant.rgb, brown);
	col = mix(col, ditch * (0.92 + 0.16 * clump), verge * 0.65);
	col = mix(col, gravel.rgb * (0.88 + 0.24 * grain) * (0.95 + 0.1 * clump), county);
	if (pk > 0.0 && county > 0.0) {
		pr = mix(pr, ph_gravel(p), county);
		ps = mix(ps, ph_gravel_s(p) * 0.6, county);
	}
	// State highways (SR 57, SR 61, SR 56; Highways): two 12 ft lanes and
	// 8 ft paved shoulders (INDOT), white edge lines and a yellow centre line
	// in a mowed right of way. Cut through the bluffs, so only the water
	// stops them. No lots are platted on them (CitySim._lot_blocked), and
	// they run on under the town's roads (whose own pavement lies on top),
	// so a road crossing one meets it at a junction. Plowed in winter.
	float hd = highway_d(r);
	float hw_land = 1.0 - smoothstep(0.06, 0.12, cover.g);
	float hw_aa = max(px, 0.05);
	float hw_verge = (1.0 - smoothstep(13.0, 16.0, hd)) * hw_land;
	float hw_paved = (1.0 - smoothstep(6.0 - hw_aa, 6.0 + hw_aa, hd)) * hw_land;
	float hw_lane = 1.0 - smoothstep(3.6 - hw_aa, 3.6 + hw_aa, hd);
	col = mix(col, ditch * (0.95 + 0.12 * clump), hw_verge * 0.75);
	vec3 asphalt = vec3(0.25, 0.25, 0.25) * (0.9 + 0.2 * grain) * (0.96 + 0.08 * clump);
	vec3 hw_col = mix(asphalt * 1.25, asphalt, hw_lane);
	// Painted lines 4 in (0.1 m) wide fade to their share of the pixel.
	float line_k = min(1.0, 0.1 / hw_aa);
	float edge_line = (1.0 - smoothstep(0.05, 0.05 + hw_aa, abs(hd - 3.55))) * line_k;
	float mid_line = (1.0 - smoothstep(0.15, 0.15 + hw_aa, hd)) * min(1.0, 0.3 / hw_aa);
	hw_col = mix(hw_col, vec3(0.82, 0.82, 0.78), edge_line * 0.9);
	hw_col = mix(hw_col, vec3(0.80, 0.62, 0.12), mid_line * 0.9);
	col = mix(col, hw_col, hw_paved);
	pr = mix(pr, vec3(1.0), hw_paved);
	ps = mix(ps, vec2(0.0), hw_paved);
	// Strip mine spoil and gravel.
	col = mix(col, spoil.rgb * (0.85 + 0.3 * clump), smoothstep(0.3, 0.7, cover.a));
	// Muddy, sandy banks by the water.
	float banks = smoothstep(0.03, 0.3, cover.g);
	col = mix(col, mud.rgb * (0.9 + 0.2 * grain), banks);
	if (pk > 0.0 && banks > 0.0) {
		pr = mix(pr, ph_mud(p), banks);
		ps = mix(ps, ph_mud_s(p), banks);
	}
	// Worn, bare soil on steep banks.
	col = mix(col, soil.rgb * 0.9, smoothstep(0.2, 0.45, steep) * 0.6);

	// The painted grain stands in for the photo's detail where there is none.
	col *= 1.0 + ((grain - 0.5) * mix(0.4, 0.22, mowed) * fade + (blades - 0.5) * 0.3 * fade * fade) * (1.0 - pk * 0.8);
	col *= mix(vec3(1.0), pr, pk);
	// Snow lies thinner under the woods and on steep banks, and drifts in
	// patches before it covers everything.
	float under = smoothstep(0.3, 0.65, cover.r) * (1.0 - painted) * 0.45 + smoothstep(0.2, 0.45, steep) * 0.4;
	float lies = smoothstep(0.05, 0.45, snow * 1.15 - clump * 0.35 - (1.0 - mid) * 0.15 + 0.1 - under);
	lies *= 1.0 - smoothstep(0.03, 0.3, cover.g) * 0.5;
	lies *= 1.0 - hw_paved * 0.85;
	vec3 snowy = vec3(0.80, 0.83, 0.88) * (0.94 + big * 0.08) * (1.0 + (blades - 0.5) * 0.08 * fade);
	// Fields read through the snow from the air: corn stubble and tilled
	// clods poke through, and each field drifts a little differently.
	float in_field = smoothstep(0.3, 0.7, cover.b);
	vec4 under_snow = crop_texel(slot, 1);
	vec3 poking = crop_lin(under_snow.rgb);
	float through = (0.12 + 0.25 * under_snow.a) * (0.6 + 0.8 * clump);
	snowy = mix(snowy * (0.95 + 0.06 * fract(pick * 3.7)), poking, through * in_field);
	// Far canopy shows dark trunks through the snow.
	// From the air bare woods read grey-brown against snowy fields, with the
	// snow showing in the gaps between crowns.
	snowy = mix(snowy, twigs.rgb * 1.05 * (0.85 + 0.3 * crown_hash), in_woods * painted * mix(0.8, 0.55, gap * relief));
	if (pk > 0.0 && lies > 0.0) {
		snowy *= mix(vec3(1.0), ph_snowy(p * 1.7), pk * 0.7);
	}
	col = mix(col, snowy, lies);
	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.75, lies);
	SPECULAR = 0.25;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
// A Midwest river: silty, green-brown, darker where deep.
uniform vec4 shallow : source_color = vec4(0.30, 0.31, 0.21, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.16, 0.12, 1.0);
// The silt and mud of the bottom where it's shallow by the bank.
uniform vec4 shore : source_color = vec4(0.36, 0.33, 0.24, 1.0);
global uniform float snow;

varying vec3 world_pos;
// Metres of water under this point, over 3. TerrainView._water_mesh puts
// 1 - that in UV2.x (not a colour, which the browser converts), so a sheet
// with no UV2 (a strip mine's pit pond) reads as deep.
varying float depth3;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth3 = 1.0 - UV2.x;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * 0.02;
	float a = texture(noise_soft, p / 37.0 + vec2(t, t * 0.6)).r;
	float b = texture(noise_soft, p / 13.0 - vec2(t * 0.7, t * 1.3)).r;
	float c = texture(noise_soft, p / 160.0 + vec2(t * 0.2, 0.0)).r;
	// Farm ponds and the Mississinewa are calm: a light ripple, smoothed
	// away where it's smaller than a pixel so the sun doesn't glitter off it
	// as white static from above.
	float calm = 0.45 * (1.0 - smoothstep(0.15, 1.2, length(fwidth(p))));
	vec3 n = normalize(vec3(((a - 0.5) * 0.35 + (b - 0.5) * 0.2) * calm, 1.0, ((b - 0.5) * 0.35 - (a - 0.5) * 0.2) * calm));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Real ponds and the Mississinewa from above: the brown bottom shows
	// through the first half metre by the bank, then green-brown, darker
	// over the deep water (aerial photos of Grant County pit ponds), so the
	// shore is a soft band, not a hard line of dark water against grass.
	float d = depth3 * 3.0 + (b - 0.5) * 0.4;
	vec3 col = mix(shallow.rgb, deep.rgb, clamp(0.25 + 0.4 * c + 0.45 * smoothstep(0.8, 3.0, d), 0.0, 1.0));
	col = mix(col, shore.rgb * (0.85 + 0.3 * a), 1.0 - smoothstep(0.05, 0.7, d));
	// Ice in a hard winter: still, shallow water freezes first, from the
	// banks out (Indiana ponds usually skin over by mid-January, the river
	// channel rarely), grey and smooth with the snow drifted over it.
	float ice = smoothstep(0.5, 0.85, snow + (1.0 - smoothstep(0.3, 2.5, d)) * 0.25 - (c - 0.5) * 0.2);
	vec3 frozen = mix(vec3(0.52, 0.56, 0.58), vec3(0.80, 0.83, 0.88), smoothstep(0.3, 0.7, snow * (0.8 + 0.4 * a)));
	ALBEDO = mix(col, frozen, ice);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, ice));
	ROUGHNESS = mix(mix(0.3, 0.16, smoothstep(0.1, 0.8, d)), 0.55, ice);
	SPECULAR = mix(0.55, 0.35, ice);
	METALLIC = 0.0;
}
"""

## The ground was regraded inside this box (view coordinates).
signal graded(box: Rect2)

static var _ground_mat: ShaderMaterial
static var _water_mat: ShaderMaterial

## The camera the chunks follow.
var camera: Camera3D
var network: RoadNetwork

## More roads to grade besides the town's own: name -> [RoadNetwork,
## Vector2 offset where it is drawn, lots] for a neighbor's town, or
## [strips] (see add_strips) for the county highways out to the horizon.
var _others := {}

## Vector2i chunk -> {lod, ground: MeshInstance3D, water: MeshInstance3D}
var _chunks := {}
var _dirty := {}  # Vector2i chunk -> [Rect2] graded since it was built
var _graded := {}  # segment id -> [points, inner, outer, bounds]
var _first := true
## The first drawing comes all at once, so the land is there when the game
## opens behind its loading screen; `gradual` draws it a slice a frame like
## any later change (the home screen, which shows a picture meanwhile).
var gradual := false
var _far: MeshInstance3D
static var _far_mat: ShaderMaterial
var _far_centre := Vector2(INF, INF)
## Where the camera was when every chunk last reached its wanted detail:
## until it moves SETTLE_MOVE or ground is graded, nothing needs redoing.
var _settled_eye := Vector3(INF, INF, INF)
## A chunk being built a few rows a frame (see chunk_job), or empty: the
## finest chunks take longer than a frame's share to build in one go.
var _job := {}
## The far land being built (see far_job), or empty.
var _far_job := {}
var _mask := Image.create(MASK, MASK, false, Image.FORMAT_L8)
var _mask_tex: ImageTexture
var _mask_dirty := true
var _budget_ms := BUDGET_MS if OS.has_feature("web") else DESKTOP_BUDGET_MS
## Keep and preload the coarse land (desktop only; see PRELOAD_LODS).
var keep_land := not OS.has_feature("web")
var _cache_lods := preload_lods(float(OS.get_memory_info().get("physical", 0)) / 1e9)
var _cache := {}  # Vector2i chunk -> {lod: chunk data}
var _cached := 0
var _preload: Array = []  # [key, lod] to build, coarsest level first, nearest first
var _preload_at := 0
var _preload_ready := false


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER.replace("// PHOTO_GROUND", PhotoGround.defines() + PhotoGround.glsl())
		_ground_mat.shader = sh
		_ground_mat.set_shader_parameter("noise_soft", Ground.noise(512, 0.012, 4, 11))
		_ground_mat.set_shader_parameter("noise_grain", Ground.noise(256, 0.09, 2, 23))
		_ground_mat.set_shader_parameter("highway_field", Highways.texture())
		_ground_mat.set_shader_parameter("county_miles", CountyGrid.texture())
		_ground_mat.set_shader_parameter("map_centre", Terrain.CENTRE)
		_ground_mat.set_shader_parameter("crop_table", CropCalendar.texture())
		PhotoGround.apply(_ground_mat)
	return _ground_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water_mat.shader = sh
		_water_mat.set_shader_parameter("noise_soft", Ground.noise(256, 0.02, 3, 41))
	return _water_mat


func setup(cam: Camera3D, net: RoadNetwork = null) -> void:
	camera = cam
	network = net
	if network != null:
		network.changed.connect(_regrade)
		_regrade()


## True once the land round the camera stands at its final level of detail
## (the loading screen waits for this; LoadGate).
func is_drawn() -> bool:
	return not _first and _dirty.is_empty() and _job.is_empty() and _settled_eye.x < INF \
		and _far_job.is_empty() and _far != null


## Where the chunks centre: the ground the camera looks at.
func focus() -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	var t := camera.global_transform
	var fwd := -t.basis.z
	var p := t.origin
	var ground := Terrain.ground_y(p.x, p.z)
	var h := maxf(p.y - ground, 1.0)
	var flat := Vector2(fwd.x, fwd.z)
	var reach := 0.0
	if fwd.y < -0.05:
		reach = minf(h / -fwd.y * flat.length(), 2000.0)
	return Vector2(p.x, p.z) + flat.normalized() * reach if flat.length() > 0.001 else Vector2(p.x, p.z)


func _process(_delta: float) -> void:
	var t0 := Perf.now()
	var eye := _eye()
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("lod_eye", Vector3(eye.x, eye.z, eye.y))
		_ground_mat.set_shader_parameter("region_origin", Terrain.view_origin)
	if _far_mat != null:
		_far_mat.set_shader_parameter("lod_eye", Vector3(eye.x, eye.z, eye.y))
		_far_mat.set_shader_parameter("region_origin", Terrain.view_origin)
	var flat_eye := Vector2(eye.x, eye.y)
	if _dirty.is_empty() and eye.distance_to(_settled_eye) < SETTLE_MOVE:
		_preload_step(flat_eye)
		_update_far(flat_eye)
		Perf.add("frame.terrain", t0)
		return
	var start := Time.get_ticks_msec()
	var done := true
	# Wanted level of detail for every chunk in reach: finer once well
	# inside a level's reach, coarser only once well past it.
	var want := {}
	var r := ceili(REACH[REACH.size() - 1] / CHUNK)
	var fc := Vector2i(floori(eye.x / CHUNK), floori(eye.y / CHUNK))
	for cz in range(fc.y - r, fc.y + r + 1):
		for cx in range(fc.x - r, fc.x + r + 1):
			var key := Vector2i(cx, cz)
			var d := _chunk_distance(key, flat_eye, eye.z)
			if d >= REACH[REACH.size() - 1]:
				continue
			var have = _chunks.get(key)
			for lod in REACH.size():
				var edge: float = REACH[lod] * (HYST_OUT if have != null and have.lod <= lod else MORPH_END)
				if d < edge or lod == REACH.size() - 1:
					want[key] = lod
					break
	for key in _chunks.keys():
		if not want.has(key):
			_drop(key)
	# Nearest first.
	var todo := []
	for key in want:
		var have = _chunks.get(key)
		if have == null or have.lod != want[key] or _dirty.has(key):
			todo.append([_chunk_distance(key, flat_eye, eye.z), key])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	# A chunk already part built is finished first.
	if not _job.is_empty():
		var at := todo.find_custom(func(e): return e[1] == _job.key)
		if at > 0 and want.get(_job.key) == _job.lod:
			todo.push_front(todo.pop_at(at))
	for item in todo:
		var key: Vector2i = item[1]
		var have = _chunks.get(key)
		if have != null and have.lod == want[key] and _dirty.has(key):
			# Graded under a new road: redo just that strip of the chunk.
			patch_chunk(have.data, _dirty[key])
			have.ground.mesh = have.data.ground
		elif (_first and not gradual) or _cache.get(key, {}).has(want[key]):
			_build(key, want[key])
		else:
			# A few rows at a time; the old chunk shows until it's done.
			var lod: int = want[key]
			if _job.get("key") != key or _job.lod != lod:
				_job = {"key": key, "lod": lod, "data": chunk_job(Vector2(key) * CHUNK, CHUNK, STEPS[lod],
					REACH[lod] if lod < STEPS.size() - 1 else 0.0)}
			var finished := false
			var budget := LoadGate.ms(_budget_ms)
			while not finished and Time.get_ticks_usec() - start * 1000 < budget * 1000:
				finished = chunk_step(_job.data, JOB_ROWS)
			if not finished:
				done = false
				break
			_build(key, lod, _job.data)
			_job = {}
		_dirty.erase(key)
		# Build everything at once the first time, so the land is there
		# when the game opens; then a little each frame.
		if (not _first or gradual) and Time.get_ticks_msec() - start > LoadGate.ms(_budget_ms):
			done = false
			break
	_settled_eye = eye if done else Vector3(INF, INF, INF)
	_update_far(flat_eye, _first and not gradual)
	_update_mask()
	_first = false
	Perf.add("frame.terrain", t0)


## The far land: one coarse sheet around the camera out to FAR_REACH, cut
## away in the shader where the chunks are. Rebuilt in slices of
## FAR_BUDGET_MS a frame (all at once the first time), with no threads, so
## it runs the same on the web.
func _update_far(flat_eye: Vector2, all_now := false) -> void:
	var start := Time.get_ticks_msec()
	if _far_job.is_empty():
		if flat_eye.distance_to(_far_centre) < FAR_MOVE:
			return
		var c := (flat_eye / CHUNK).round()
		_far_job = far_job(c * CHUNK, ceili((FAR_REACH + FAR_MOVE) / CHUNK))
	while not far_step(_far_job):
		if not all_now and Time.get_ticks_msec() - start > LoadGate.ms(FAR_BUDGET_MS):
			return
	if _far == null:
		_far = MeshInstance3D.new()
		_far.material_override = far_material()
		_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_far)
	_far.mesh = _far_job.mesh
	_far_centre = _far_job.centre
	_far_job = {}


## Hides the county road miles a town has joined or bulldozed.
static func set_county_hidden(keys: Array) -> void:
	var tex := CountyGrid.hidden_texture(keys)
	ground_material().set_shader_parameter("county_hidden", tex)
	far_material().set_shader_parameter("county_hidden", tex)


static func far_material() -> ShaderMaterial:
	if _far_mat == null:
		_far_mat = ground_material().duplicate()
		_far_mat.set_shader_parameter("far_cut", REACH[REACH.size() - 1] * FAR_CUT)
	return _far_mat


## A job building the far sheet: (2r + 1) squares of CHUNK a side around
## `centre`. Run it with far_step until that returns true; the mesh is then
## in job.mesh.
static func far_job(centre: Vector2, r: int) -> Dictionary:
	var n := 2 * r + 1
	return {"centre": centre, "origin": centre - Vector2(r + 0.5, r + 0.5) * CHUNK, "n": n,
		"row": 0, "hs": PackedFloat32Array(), "verts": PackedVector3Array(),
		"normals": PackedVector3Array(), "colors": PackedColorArray(), "coarse": PackedFloat32Array()}


## One slice of a far job: a row of heights, then once they are all in, a
## row of vertices, then the mesh.
## True once the mesh is made.
static func far_step(job: Dictionary) -> bool:
	var n: int = job.n
	var m := n + 3
	var origin: Vector2 = job.origin
	var off := Terrain.shift + Terrain.view_origin
	if job.hs.size() < m * m:
		# A row of heights, with one extra all round for the normals. The raw
		# ground, not ground_y: grading near town is the chunks' to draw, and
		# none of it shows from 9 km.
		var j: int = job.hs.size() / m
		for i in m:
			job.hs.append(Terrain.height(origin.x + (i - 1) * CHUNK + off.x, origin.y + (j - 1) * CHUNK + off.y) - FAR_DROP)
		return false
	if job.row <= n:
		var hs: PackedFloat32Array = job.hs
		var j: int = job.row
		for i in n + 1:
			var x := origin.x + i * CHUNK
			var z := origin.y + j * CHUNK
			var c := (j + 1) * m + (i + 1)
			var nrm := Vector3(hs[c - 1] - hs[c + 1], 2.0 * CHUNK, hs[c - m] - hs[c + m]).normalized()
			job.verts.append(Vector3(x, hs[c], z))
			job.normals.append(nrm)
			job.coarse.append_array([hs[c], nrm.x, nrm.z, 0.0])
			job.colors.append(Terrain.cover(x + Terrain.view_origin.x, z + Terrain.view_origin.y))
		job.row += 1
		return false
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = job.verts
	arrays[Mesh.ARRAY_NORMAL] = job.normals
	arrays[Mesh.ARRAY_COLOR] = job.colors
	arrays[Mesh.ARRAY_CUSTOM0] = job.coarse
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	job.mesh = mesh
	return true


## The camera's ground position and its height above the land: x, z, height.
func _eye() -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return Vector3.ZERO
	var p := camera.global_position
	return Vector3(p.x, p.z, maxf(p.y - Terrain.ground_y(p.x, p.z), 1.0))


## How far a chunk's nearest point is from the camera, counting its height.
func _chunk_distance(key: Vector2i, f: Vector2, height := 0.0) -> float:
	var r := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var dx := maxf(maxf(r.position.x - f.x, f.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - f.y, f.y - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz + height * height)


func _drop(key: Vector2i) -> void:
	var c: Dictionary = _chunks[key]
	for k in ["ground", "water"]:
		if c[k] != null:
			c[k].queue_free()
	if not _dirty.has(key):
		_keep(key, c.lod, c.data)
	_chunks.erase(key)
	_dirty.erase(key)
	_mark(key, false)


func _build(key: Vector2i, lod: int, data := {}) -> void:
	if _chunks.has(key):
		_drop(key)
	if data.is_empty():
		data = _cache.get(key, {}).get(lod, {})
	if data.is_empty():
		data = chunk_data(Vector2(key) * CHUNK, CHUNK, STEPS[lod], REACH[lod] if lod < STEPS.size() - 1 else 0.0)
	var meshes := [data.ground, data.water]
	var entry := {"lod": lod, "ground": null, "water": null, "data": data}
	var g := MeshInstance3D.new()
	g.mesh = meshes[0]
	g.material_override = ground_material()
	# The land never casts: every pixel of it is also a receiver, and a
	# surface lit by a shadow map of itself shows the map's texels as faint
	# parallel diagonal stripes over every lawn and road ("shadow acne": no
	# bias value clears it at every sun height and quality tier, and the
	# roads, lots and trees standing on it get shaded all the same). Half
	# the county's chunks have under 4 m of relief and three in four under
	# 8, so what is lost is a hillside shading the valley below it, at a
	# low sun. It also drops the ground's triangles from every shadow pass.
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	entry.ground = g
	if meshes[1] != null:
		var w := MeshInstance3D.new()
		w.mesh = meshes[1]
		w.material_override = water_material()
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		entry.water = w
	_chunks[key] = entry
	_mark(key, true)


## Which levels the desktop app keeps and preloads, for this much memory (GB).
static func preload_lods(memory_gb: float) -> Array:
	return PRELOAD_BIG_LODS if memory_gb >= PRELOAD_BIG_GB else PRELOAD_LODS


## Every chunk from `lo` to `hi` (not included), ring by ring out from `c`.
static func ring_order(c: Vector2i, lo: Vector2i, hi: Vector2i) -> Array:
	var out := []
	var far := maxi(maxi(c.x - lo.x, hi.x - 1 - c.x), maxi(c.y - lo.y, hi.y - 1 - c.y))
	for r in far + 1:
		for cz in range(c.y - r, c.y + r + 1):
			if cz < lo.y or cz >= hi.y:
				continue
			# Top and bottom rows whole; between them only the two ends.
			var across := 1 if r == 0 or cz == c.y - r or cz == c.y + r else 2 * r
			for cx in range(c.x - r, c.x + r + 1, across):
				if cx >= lo.x and cx < hi.x:
					out.append(Vector2i(cx, cz))
	return out


func _keep(key: Vector2i, lod: int, data: Dictionary) -> void:
	if not keep_land or data.is_empty() or not lod in _cache_lods:
		return
	if not _cache.has(key):
		if _cached >= CACHE_MAX:
			return
		_cache[key] = {}
	if not _cache[key].has(lod):
		_cached += 1
	_cache[key][lod] = data


## Forgets a chunk's kept land (it was graded under a new road).
func _forget(key: Vector2i) -> void:
	if _cache.has(key):
		_cached -= _cache[key].size()
		# Built again in spare time, graded as it is now.
		for lod in _cache[key]:
			_preload.append([key, lod])
		_cache.erase(key)


## In spare frame time, builds the coarse levels of the whole county ahead
## of the camera, coarsest first, nearest first (desktop only). The order is
## laid out once, in ring order rather than sorted (a sort of the county's
## chunks took a whole frame), and the budget starts after it.
func _preload_step(flat_eye: Vector2) -> void:
	if not keep_land or _cached >= CACHE_MAX:
		return
	if not _preload_ready:
		_preload_ready = true
		var mid := Terrain.CENTRE - Terrain.view_origin
		var half := ceili(Terrain.SIZE * 0.5 / CHUNK)
		var c0 := Vector2i(floori(mid.x / CHUNK), floori(mid.y / CHUNK))
		var ring := ring_order(Vector2i(floori(flat_eye.x / CHUNK), floori(flat_eye.y / CHUNK)),
			c0 - Vector2i(half, half), c0 + Vector2i(half, half))
		for lod in _cache_lods:
			for key in ring:
				_preload.append([key, lod])
	var start := Time.get_ticks_usec()
	while _preload_at < _preload.size() and Time.get_ticks_usec() - start < PRELOAD_MS * 1000:
		var item: Array = _preload[_preload_at]
		_preload_at += 1
		var key: Vector2i = item[0]
		var lod: int = item[1]
		if _cache.get(key, {}).has(lod) or (_chunks.has(key) and _chunks[key].lod == lod):
			continue
		_keep(key, lod, chunk_data(Vector2(key) * CHUNK, CHUNK, STEPS[lod], REACH[lod] if lod < STEPS.size() - 1 else 0.0))
	if _preload_at >= _preload.size():
		_preload = []
		_preload_at = 0


func _mark(key: Vector2i, built: bool) -> void:
	_mask.set_pixel(key.x & (MASK - 1), key.y & (MASK - 1), Color.WHITE if built else Color.BLACK)
	_mask_dirty = true


## Sends which chunks are built to the far sheet's shader.
func _update_mask() -> void:
	if not _mask_dirty or _far == null:
		return
	_mask_dirty = false
	if _mask_tex == null:
		_mask_tex = ImageTexture.create_from_image(_mask)
		far_material().set_shader_parameter("chunk_built", _mask_tex)
	else:
		_mask_tex.update(_mask)


## Where grid point (i, j) of a chunk sits on the next coarser level (twice
## the step): its height there and that level's normal (x, z), as the
## coarser mesh would draw it, including which way its squares are split.
## `hs` holds heights with two extra samples all round, `m` wide.
static func _coarse_at(hs: PackedFloat32Array, m: int, i: int, j: int, step: float) -> Vector3:
	var odd_i := i % 2 == 1
	var odd_j := j % 2 == 1
	var pts := []
	if not odd_i and not odd_j:
		pts = [Vector2i(i, j)]
	elif odd_i and not odd_j:
		pts = [Vector2i(i - 1, j), Vector2i(i + 1, j)]
	elif not odd_i and odd_j:
		pts = [Vector2i(i, j - 1), Vector2i(i, j + 1)]
	else:
		var a := hs[(j + 1) * m + (i + 1)]
		var b := hs[(j + 1) * m + (i + 3)]
		var c := hs[(j + 3) * m + (i + 1)]
		var d := hs[(j + 3) * m + (i + 3)]
		if absf(a - d) < absf(b - c):
			pts = [Vector2i(i - 1, j - 1), Vector2i(i + 1, j + 1)]
		else:
			pts = [Vector2i(i + 1, j - 1), Vector2i(i - 1, j + 1)]
	var y := 0.0
	var nrm := Vector3.ZERO
	for qv in pts:
		var q: Vector2i = qv
		var at := (q.y + 2) * m + (q.x + 2)
		y += hs[at]
		# The coarse level's slope, from samples two steps apart (fewer at
		# the edge of what was sampled).
		var x := q.x + 2
		var z := q.y + 2
		var l := mini(2, x)
		var r := mini(2, m - 1 - x)
		var u := mini(2, z)
		var dn := mini(2, m - 1 - z)
		var sx := (hs[at + r] - hs[at - l]) / ((l + r) * step)
		var sz := (hs[at + dn * m] - hs[at - u * m]) / ((u + dn) * step)
		nrm += Vector3(-sx, 1.0, -sz).normalized()
	nrm = nrm.normalized()
	return Vector3(y / pts.size(), nrm.x, nrm.z)


## The ground mesh and the water mesh (or null) for one square chunk with
## its corner at `origin`, a grid `step` metres apart. View coordinates.
static func build_chunk(origin: Vector2, size: float, step: float, reach := 0.0) -> Array:
	var d := chunk_data(origin, size, step, reach)
	return [d.ground, d.water]


## A chunk's samples, vertices and meshes, kept so patch_chunk can redo only
## the part a new road grades.
static func chunk_job(origin: Vector2, size: float, step: float, reach := 0.0) -> Dictionary:
	var n := int(size / step)
	var m := n + 5  # two extra samples all round, for normals at both levels
	var count := (n + 1) * (n + 1)
	var d := {"origin": origin, "step": step, "reach": reach, "n": n, "m": m,
		"hs": PackedFloat32Array(), "verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"colors": PackedColorArray(), "town": PackedVector2Array(), "coarse": PackedFloat32Array(),
		"wet": PackedFloat32Array(), "idx": PackedInt32Array(), "water": null}
	d.hs.resize(m * m)
	d.verts.resize(count)
	d.normals.resize(count)
	d.colors.resize(count)
	d.town.resize(count)
	# Each vertex also carries where it sits on the next coarser level (its
	# height and normal there), for the shader to slide toward with distance.
	d.coarse.resize(count * 4)
	d.wet.resize(count)
	d.idx.resize(n * n * 6)
	d.phase = 0
	d.row = 0
	d.any_water = false
	return d


## Does up to `rows` rows of a chunk_job (heights, then vertices, then
## squares, then the meshes); true once it is finished.
static func chunk_step(d: Dictionary, rows: int) -> bool:
	var n: int = d.n
	var m: int = d.m
	match int(d.phase):
		0:
			var r1 := mini(int(d.row) + rows, m)
			_sample_heights(d, 0, m - 1, d.row, r1 - 1)
			d.row = r1
			if r1 >= m:
				d.phase = 1
				d.row = 0
		1:
			var r1 := mini(int(d.row) + rows, n + 1)
			if _fill_vertices(d, 0, n, d.row, r1 - 1):
				d.any_water = true
			d.row = r1
			if r1 >= n + 1:
				d.phase = 2
				d.row = 0
		2:
			var r1 := mini(int(d.row) + rows, n)
			_fill_squares(d, 0, n - 1, d.row, r1 - 1)
			d.row = r1
			if r1 >= n:
				d.phase = 3
		3:
			d.ground = _ground_mesh(d)
			if d.any_water:
				d.water = _water_mesh(d)
			d.phase = 4
	return int(d.phase) >= 4


static func chunk_data(origin: Vector2, size: float, step: float, reach := 0.0) -> Dictionary:
	var d := chunk_job(origin, size, step, reach)
	while not chunk_step(d, 1 << 20):
		pass
	return d




## Redoes a chunk's ground under `boxes` (view coordinates) after grading:
## the samples there, the vertices whose normals and coarser level read
## them, and the squares between, then the mesh once. The water stays.
static func patch_chunk(d: Dictionary, boxes: Array) -> void:
	var o: Vector2 = d.origin
	var step: float = d.step
	var n: int = d.n
	var m: int = d.m
	# Per row, the columns to redo (boxes along one road overlap; each
	# point is done once). Sample indices are grid indices plus 2.
	var samples := _spans(m)
	var verts := _spans(n + 1)
	var squares := _spans(n)
	for box: Rect2 in boxes:
		var i0 := floori((box.position.x - o.x) / step)
		var i1 := ceili((box.end.x - o.x) / step)
		var j0 := floori((box.position.y - o.y) / step)
		var j1 := ceili((box.end.y - o.y) / step)
		_widen(samples, i0 + 1, i1 + 3, j0 + 1, j1 + 3)
		_widen(verts, i0 - 3, i1 + 3, j0 - 3, j1 + 3)
		_widen(squares, i0 - 4, i1 + 3, j0 - 4, j1 + 3)
	var changed := false
	for j in m:
		if samples[0][j] <= samples[1][j]:
			_sample_heights(d, samples[0][j], samples[1][j], j, j)
	for j in n + 1:
		if verts[0][j] <= verts[1][j]:
			_fill_vertices(d, verts[0][j], verts[1][j], j, j)
			changed = true
	for j in n:
		if squares[0][j] <= squares[1][j]:
			_fill_squares(d, squares[0][j], squares[1][j], j, j)
	if changed:
		d.ground = _ground_mesh(d)


## Empty column spans for `size` rows: [lows, highs].
static func _spans(size: int) -> Array:
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(size)
	hi.resize(size)
	lo.fill(size)
	hi.fill(-1)
	return [lo, hi]


static func _widen(spans: Array, i0: int, i1: int, j0: int, j1: int) -> void:
	var lo: PackedInt32Array = spans[0]
	var hi: PackedInt32Array = spans[1]
	var size := lo.size()
	i0 = maxi(i0, 0)
	i1 = mini(i1, size - 1)
	if i0 > i1:
		return
	for j in range(maxi(j0, 0), mini(j1, size - 1) + 1):
		lo[j] = mini(lo[j], i0)
		hi[j] = maxi(hi[j], i1)
	spans[0] = lo
	spans[1] = hi


static func _sample_heights(d: Dictionary, a0: int, a1: int, b0: int, b1: int) -> void:
	var o: Vector2 = d.origin
	var step: float = d.step
	var m: int = d.m
	var hs: PackedFloat32Array = d.hs
	var half := step * 0.5
	for j in range(b0, b1 + 1):
		for i in range(a0, a1 + 1):
			var x := o.x + (i - 2) * step
			var z := o.y + (j - 2) * step
			var h := Terrain.ground_y(x, z)
			# By a road, the grid takes the lowest graded ground within half a
			# step: a corner up on the bank beside the cut would otherwise
			# lay its triangles over the road, and the road would seem to go
			# underground (Brawn 2026-10-24).
			if Terrain.flat_weight(x, z) > 0.0:
				h = minf(h, minf(minf(Terrain.ground_y(x - half, z), Terrain.ground_y(x + half, z)),
					minf(Terrain.ground_y(x, z - half), Terrain.ground_y(x, z + half))))
			hs[j * m + i] = h
	d.hs = hs


## Fills grid vertices i0..i1, j0..j1; true when any of them is wet.
static func _fill_vertices(d: Dictionary, i0: int, i1: int, j0: int, j1: int) -> bool:
	var o: Vector2 = d.origin
	var step: float = d.step
	var n: int = d.n
	var m: int = d.m
	var reach: float = d.reach
	var hs: PackedFloat32Array = d.hs
	var verts: PackedVector3Array = d.verts
	var normals: PackedVector3Array = d.normals
	var colors: PackedColorArray = d.colors
	var town: PackedVector2Array = d.town
	var coarse: PackedFloat32Array = d.coarse
	var wet: PackedFloat32Array = d.wet
	var any_water := false
	var rail_row := CountyRail.drawn() and CountyRail.any_in(Rect2(o.x + i0 * step + Terrain.view_origin.x,
		o.y + j0 * step + Terrain.view_origin.y, (i1 - i0) * step, (j1 - j0) * step).grow(CountyRail.TREE_CLEAR + 3.0))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * (n + 1) + i
			var x := o.x + i * step
			var z := o.y + j * step
			var c := (j + 2) * m + (i + 2)
			verts[k] = Vector3(x, hs[c], z)
			normals[k] = Vector3(hs[c - 1] - hs[c + 1], 2.0 * step, hs[c - m] - hs[c + m]).normalized()
			var lo := _coarse_at(hs, m, i, j, step)
			coarse[k * 4] = lo.x
			coarse[k * 4 + 1] = lo.y
			coarse[k * 4 + 2] = lo.z
			coarse[k * 4 + 3] = reach
			var cov := Terrain.cover(x + Terrain.view_origin.x, z + Terrain.view_origin.y)
			# r trees, g water, b crops, a bare (as the shader reads them),
			# cleared off the road and its mowed verge.
			var mowed := Terrain.mow_weight(x, z)
			var keep := 1.0 - mowed
			# Yards (graded for lots but past the mowed verge) keep their trees,
			# but the ground under them is thin, patchy lawn with some leaves,
			# not the bare leaf litter of the woods.
			var graded := Terrain.flat_weight(x, z)
			var yard := clampf(graded - mowed, 0.0, 1.0)
			# No crops anywhere on graded town land: a yard is lawn, not the
			# farm field the town was built on (the critic, 2026-10-26: yards
			# showed tilled soil in May and a hard-edged rectangle of winter
			# wheat in November, lined up with the field outside town).
			var crops := cov.b * clampf(1.0 - 1.25 * maxf(mowed, graded), 0.0, 1.0)
			# A railroad's right of way (desktop): rough grass and weeds
			# between its fences, cut back from the woods and never cropped.
			if rail_row:
				var row := smoothstep(CountyRail.TREE_CLEAR - 3.0, CountyRail.TREE_CLEAR + 3.0,
					CountyRail.distance(x + Terrain.view_origin.x, z + Terrain.view_origin.y, CountyRail.TREE_CLEAR + 3.0))
				keep *= row
				crops *= row
			colors[k] = Color(cov.r * keep * (1.0 - YARD_THIN * yard), cov.g, crops, cov.a * keep)
			# Towns' roads and lots, where the county roads give way.
			town[k] = Vector2(mowed, graded)
			wet[k] = cov.g
			any_water = any_water or cov.g > 0.02
	d.verts = verts
	d.normals = normals
	d.colors = colors
	d.town = town
	d.coarse = coarse
	d.wet = wet
	return any_water


## Splits each square i0..i1, j0..j1 along the diagonal that follows the land.
static func _fill_squares(d: Dictionary, i0: int, i1: int, j0: int, j1: int) -> void:
	var n: int = d.n
	var verts: PackedVector3Array = d.verts
	var idx: PackedInt32Array = d.idx
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var a := j * (n + 1) + i
			var s := (j * n + i) * 6
			if absf(verts[a].y - verts[a + n + 2].y) < absf(verts[a + 1].y - verts[a + n + 1].y):
				idx[s] = a
				idx[s + 1] = a + 1
				idx[s + 2] = a + n + 2
				idx[s + 3] = a
				idx[s + 4] = a + n + 2
				idx[s + 5] = a + n + 1
			else:
				idx[s] = a
				idx[s + 1] = a + 1
				idx[s + 2] = a + n + 1
				idx[s + 3] = a + 1
				idx[s + 4] = a + n + 2
				idx[s + 5] = a + n + 1
	d.idx = idx


static func _ground_mesh(d: Dictionary) -> ArrayMesh:
	var n: int = d.n
	var step: float = d.step
	var reach: float = d.reach
	var count := (n + 1) * (n + 1)
	var verts: PackedVector3Array = d.verts.duplicate()
	var normals: PackedVector3Array = d.normals.duplicate()
	var colors: PackedColorArray = d.colors.duplicate()
	var town: PackedVector2Array = d.town.duplicate()
	var coarse: PackedFloat32Array = d.coarse.duplicate()
	var idx: PackedInt32Array = d.idx.duplicate()
	# A skirt hangs from each edge to hide cracks against coarser neighbours.
	var drop := step * 0.6 + 1.0
	var edges := [range(0, n + 1), range(n * (n + 1), count), range(0, count, n + 1), range(n, count, n + 1)]
	for e in edges.size():
		var line: Array = Array(edges[e])
		var base := verts.size()
		for k in line:
			verts.append(verts[k] - Vector3(0, drop, 0))
			normals.append(normals[k])
			colors.append(colors[k])
			town.append(town[k])
			coarse.append_array([coarse[k * 4] - drop, coarse[k * 4 + 1], coarse[k * 4 + 2], reach])
		for s in line.size() - 1:
			var a: int = line[s]
			var b: int = line[s + 1]
			idx.append_array([a, b, base + s + 1, a, base + s + 1, base + s])
			idx.append_array([a, base + s + 1, b, a, base + s, base + s + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = town
	arrays[Mesh.ARRAY_CUSTOM0] = coarse
	arrays[Mesh.ARRAY_INDEX] = idx
	var ground := ArrayMesh.new()
	ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return ground


## Water: a sheet at the water level over every square that touches water.
## The banks rise above it, so the shore draws itself where they meet.
static func _water_mesh(d: Dictionary) -> ArrayMesh:
	var n: int = d.n
	var verts: PackedVector3Array = d.verts
	var wet: PackedFloat32Array = d.wet
	var wverts := PackedVector3Array()
	var wdepth := PackedVector2Array()
	var widx := PackedInt32Array()
	var index := {}
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			if maxf(maxf(wet[a], wet[a + 1]), maxf(wet[a + n + 1], wet[a + n + 2])) < 0.02:
				continue
			# Flat at the level of the wettest corner. The level is only known
			# on or by the water, so a dry corner read on its own could tilt
			# the sheet tens of metres up into the air on the coarser levels.
			var corners := [a, a + 1, a + n + 2, a + n + 1]
			var wettest: int = corners[0]
			for c in corners:
				if wet[c] > wet[wettest]:
					wettest = c
			if not index.has(wettest):
				var v := verts[wettest]
				index[wettest] = Terrain.water_level(v.x + Terrain.view_origin.x, v.z + Terrain.view_origin.y)
			var level: float = index[wettest]
			var base := wverts.size()
			for c in corners:
				# Each wet corner at its own level, so squares that meet share
				# their edge (no steps or seams across the water); a dry one
				# at the square's wettest level.
				var at := level
				if wet[c] >= 0.02:
					if not index.has(c):
						index[c] = Terrain.water_level(verts[c].x + Terrain.view_origin.x, verts[c].z + Terrain.view_origin.y)
					at = index[c]
				wverts.append(Vector3(verts[c].x, at, verts[c].z))
				# How deep the water is here, for the shore's shading.
				wdepth.append(Vector2(1.0 - clampf((at - verts[c].y) / 3.0, 0.0, 1.0), 0.0))
			widx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if widx.is_empty():
		return null
	var wn := PackedVector3Array()
	wn.resize(wverts.size())
	wn.fill(Vector3.UP)
	var warrays := []
	warrays.resize(Mesh.ARRAY_MAX)
	warrays[Mesh.ARRAY_VERTEX] = wverts
	warrays[Mesh.ARRAY_NORMAL] = wn
	warrays[Mesh.ARRAY_TEX_UV2] = wdepth
	warrays[Mesh.ARRAY_INDEX] = widx
	var water := ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warrays)
	return water


# --- Grading under roads ----------------------------------------------------

## More strips to grade besides roads (the railroad's track): returns
## {key: [PackedVector3Array, inner, outer]}. Call regrade() when they change.
var extra_grades := Callable()


func regrade() -> void:
	_regrade()


## Grades the ground under another road network too, drawn moved over by
## `offset` (a neighbor's town); `lots` false grades only the road itself
## (no town lots along it). Setting a name again replaces it.
func add_network(name: String, net: RoadNetwork, offset := Vector2.ZERO, lots := true) -> void:
	remove_network(name, false)
	_others[name] = [net, offset, lots]
	if not net.changed.is_connected(_regrade):
		net.changed.connect(_regrade)
	_regrade()


## Grades strips that aren't part of any network: key -> [points (view
## coordinates), graded half width, fade-out half width, mowed half width].
## Setting a name again replaces them.
func add_strips(name: String, strips: Dictionary) -> void:
	remove_network(name, false)
	_others[name] = [strips]
	_regrade()


func remove_network(name: String, now := true) -> void:
	if not _others.has(name):
		return
	if _others[name][0] is RoadNetwork and _others[name][0].changed.is_connected(_regrade):
		_others[name][0].changed.disconnect(_regrade)
	_others.erase(name)
	if now:
		_regrade()


## Grades the ground under every road that changed, and marks those chunks
## to be rebuilt.
## Each neighbor network's strips from the last regrade: name -> [sig, strips].
var _net_strips := {}


func _regrade() -> void:
	var now := {}
	if network != null:
		_grade_network(now, network, Vector2.ZERO, true, "")
	var keep := {}
	for name in _others:
		var o: Array = _others[name]
		if o[0] is RoadNetwork:
			# A neighbor's roads that haven't changed since last time keep
			# their strips as they were (edits there bump its revision).
			var sig := [o[0].get_instance_id(), o[0].revision, o[0].segments.size(), o[1], o[2]]
			var last: Array = _net_strips.get(name, [])
			if not last.is_empty() and last[0] == sig:
				now.merge(last[1])
				keep[name] = last
				continue
			var mine := {}
			_grade_network(mine, o[0], o[1], o[2], name + ":")
			now.merge(mine)
			keep[name] = [sig, mine]
		else:
			for key in o[0]:
				now[name + ":" + str(key)] = o[0][key]
	_net_strips = keep
	if extra_grades.is_valid():
		now.merge(extra_grades.call())
	# Roads removed long ago needn't be remembered.
	if _strips.size() > 2 * now.size() + 2000:
		_strips.clear()
	var changed := []
	var changed_strips := []
	for id in _graded:
		if not now.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(_graded[id]))
			changed_strips.append(_graded[id])
	for id in now:
		if not _graded.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(now[id]))
			changed_strips.append(now[id])
	_graded = now
	if changed.is_empty():
		return
	for box in changed:
		Terrain.clear_flat(box)
	# Each strip is stamped once over all the cleared boxes it touches, found
	# through a coarse grid rather than by testing every box. Stamping keeps
	# the higher value and a strip never reaches past its bounds, so cells
	# it covers outside those boxes (never cleared) already hold the same.
	var grid := {}
	for n in changed.size():
		var box: Rect2 = changed[n]
		for cz in range(floori(box.position.y / REGRADE_CELL), floori(box.end.y / REGRADE_CELL) + 1):
			for cx in range(floori(box.position.x / REGRADE_CELL), floori(box.end.x / REGRADE_CELL) + 1):
				var cell := Vector2i(cx, cz)
				if not grid.has(cell):
					grid[cell] = []
				grid[cell].append(n)
	for id in _graded:
		var g: Array = _graded[id]
		var b := _bounds(g)
		var clip := Rect2()
		var hit := false
		for cz in range(floori(b.position.y / REGRADE_CELL), floori(b.end.y / REGRADE_CELL) + 1):
			for cx in range(floori(b.position.x / REGRADE_CELL), floori(b.end.x / REGRADE_CELL) + 1):
				for n in grid.get(Vector2i(cx, cz), []):
					var box: Rect2 = changed[n]
					if b.intersects(box):
						clip = clip.merge(box) if hit else box
						hit = true
		if hit:
			# Cover is cleared to the mowed verge (or, without one, the graded strip).
			Terrain.stamp_flat(g[0], g[1], g[2], clip.intersection(b), g[3] if g.size() > 3 else g[1])
	for box in changed:
		graded.emit(box)
	for g in changed_strips:
		_mark_dirty(g)


## Marks the chunks a graded strip runs through, with the boxes along it in
## each (a long diagonal road touches a thin band, not its whole bounds).
func _mark_dirty(g: Array) -> void:
	var pts: PackedVector3Array = g[0]
	var grow: float = g[2] + Terrain.FLAT_CELL
	var pieces := []
	if pts.size() == 1:
		pieces.append(Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO).grow(grow))
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var cuts := maxi(1, ceili(a.distance_to(b) / 64.0))
		for c in cuts:
			var p := a.lerp(b, float(c) / cuts)
			var q := a.lerp(b, float(c + 1) / cuts)
			pieces.append(Rect2(p, Vector2.ZERO).expand(q).grow(grow))
	# Kept land is forgotten a little wider: a chunk's edge normals read
	# samples up to two of its steps outside it.
	for box: Rect2 in pieces:
		var wide := box.grow(2.0 * STEPS[STEPS.size() - 1])
		for cz in range(floori(wide.position.y / CHUNK), floori(wide.end.y / CHUNK) + 1):
			for cx in range(floori(wide.position.x / CHUNK), floori(wide.end.x / CHUNK) + 1):
				_forget(Vector2i(cx, cz))
	for box: Rect2 in pieces:
		var c0 := Vector2i(floori(box.position.x / CHUNK), floori(box.position.y / CHUNK))
		var c1 := Vector2i(floori(box.end.x / CHUNK), floori(box.end.y / CHUNK))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				# A chunk not built yet gets the grading when it is built
				# (one half built starts over).
				if _job.get("key") == key:
					_job = {}
				if not _chunks.has(key):
					continue
				if not _dirty.has(key):
					_dirty[key] = []
				_dirty[key].append(box)


## The strips to grade under one network's roads, keyed by segment id
## (with `prefix` for networks other than the town's own).
static func _grade_network(now: Dictionary, net: RoadNetwork, offset: Vector2, lots: bool, prefix: String) -> void:
	var shift := Vector3(offset.x, 0.0, offset.y)
	for id in net.segments:
		var key = id if prefix == "" else prefix + str(id)
		# A road's strip follows only from its curve and type: when a
		# neighbor's town is reloaded, unchanged roads keep theirs.
		var c := net.curve_of(id)
		var sig := [c[0], c[1], c[2], net.segments[id].type, offset, lots]
		var hit = _strips.get(key)
		if hit != null and hit[0] == sig:
			if not hit[1].is_empty():
				now[key] = hit[1]
			continue
		var pts := _straightened(net.sample_segment(id, 24))
		var type: int = net.segments[id].type
		_strips[key] = [sig, []]
		if absf(pts[0].y) > 3.0 and absf(pts[pts.size() - 1].y) > 3.0 and absf(pts[pts.size() / 2].y) > 3.0:
			continue  # bridges and tunnels leave the ground alone
		if offset != Vector2.ZERO:
			for i in pts.size():
				pts[i] += shift
		var inner := RoadStyle.right_of_way_half(type) + (LOT_GRADE if lots and RoadStyle.TYPES[type].lots else 2.0)
		# The verge is mowed a few metres past the shoulder; woods start there.
		now[key] = [pts, inner, inner + GRADE_FADE, RoadStyle.right_of_way_half(type) + MOW_VERGE]
		_strips[key][1] = now[key]


## Each road's last graded strip, by its key in _graded: [what it was made
## from, the strip] (an empty strip for a bridge or tunnel).
static var _strips := {}


## A straight road's samples cut down to its two ends (grading costs one
## pass over the ground per piece of line); curves keep every point.
static func _straightened(pts: PackedVector3Array) -> PackedVector3Array:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var dir := Vector2(b.x - a.x, b.z - a.z)
	var length := dir.length()
	if length < 1.0:
		return pts
	dir /= length
	for p in pts:
		if absf((p.y - a.y) - (b.y - a.y) * Vector2(p.x - a.x, p.z - a.z).dot(dir) / length) > 0.2:
			return pts
		if absf(Vector2(p.x - a.x, p.z - a.z).cross(dir)) > 0.25:
			return pts
	return PackedVector3Array([a, b])


static func _same(a: Array, b: Array) -> bool:
	return a[1] == b[1] and (a[0] as PackedVector3Array) == (b[0] as PackedVector3Array)


static func _bounds(g: Array) -> Rect2:
	var pts: PackedVector3Array = g[0]
	var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(g[2] + Terrain.FLAT_CELL)
