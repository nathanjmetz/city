class_name ParkBuilder
extends CivicBuilder
## Parks and landmarks, benchmarked against photos of real Midwestern towns:
##   - the town park: mown lawn under big shade trees, concrete walks, a
##     playground on wood-chip mulch, an open picnic shelter with tables, a
##     half basketball court and a Little League diamond with a backstop.
##     A thriving neighborhood's park has striped turf, flowerbeds, lamp
##     posts and a fountain; a struggling one has patchy grass, dirt paths
##     worn across the lawn, a faded playground and a dry fountain.
##   - the courthouse square: a three-storey limestone courthouse with a
##     clock tower and dome on a full block of lawn, diagonal walks, a war
##     memorial and big maples (Indiana county seats)
##   - the town water tower: a multi-leg tank with the town's name on it
##   - the co-op grain elevator: a row of slip-formed concrete silos, a tall
##     headhouse, steel bins and a truck scale
##   - the high school football field: striped turf with yard lines, end
##     zones, goalposts, aluminium bleachers, a press box and light towers
##   - a park boxed in by roads (edge pieces, Parks) runs up to the sidewalk:
##     more of its lawn, a walk back along each side and across the back
##     with benches, and shade trees, never a playground or a field
## Local space as in CivicBuilder: centred on the site, -z faces the road.

const LAWN_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
uniform vec4 dry : source_color = vec4(0.50, 0.48, 0.28, 1.0);
uniform vec4 soil : source_color = vec4(0.47, 0.40, 0.29, 1.0);
// Set by DayNight: snow cover, and the season as (autumn, bare, spring, dry).
global uniform float snow;
global uniform vec4 season_look;
varying vec3 world_pos;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// The turf colour is sRGB; the browser's renderer (Compatibility) hands it
// over already made linear.
vec3 vcol(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return lin(c);
#endif
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Vertex colour: the turf's green; alpha: how well it is kept (0 worn,
	// 1 curated). UV: metres along the site, for mowing stripes.
	vec2 p = world_pos.xz;
	float care = COLOR.a;
	float mid = texture(noise_soft, p / 60.0 + 0.31).r;
	float clump = texture(noise_soft, p / 7.0 + 0.62).r;
	float grain = texture(noise_grain, p / 2.3).r;
	vec3 col = mix(vcol(COLOR.rgb), dry.rgb, smoothstep(0.4, 0.8, mid) * mix(0.8, 0.15, care));
	col *= 1.0 - smoothstep(0.4, 0.9, clump) * mix(0.08, 0.18, care);
	// Bare, trodden spots where nobody keeps the grass up.
	float bare = smoothstep(mix(0.68, 1.2, care), mix(0.82, 1.3, care), clump * 0.6 + mid * 0.5);
	col = mix(col, soil.rgb, bare * 0.65);
	// Mowing stripes on a curated lawn, 4 m wide.
	float stripe = step(0.5, fract(UV.x / 8.0));
	col *= 1.0 + (stripe - 0.5) * 0.12 * smoothstep(0.75, 1.0, care);
	float fade = clamp(1.0 - length(VERTEX) / 160.0, 0.0, 1.0);
	col *= 1.0 + (grain - 0.5) * 0.3 * fade;
	// Seasons, as on the town's lawns around it: fresh in spring, a muted
	// olive when dormant after the December frosts (a fed, watered lawn
	// holds its green a little longer; never the pasture's tan), and under
	// the same snow as the fields in winter.
	// Benchmark: Indiana town parks in March and January.
	col = mix(col, col * vec3(0.92, 1.12, 0.78), season_look.z);
	vec3 dormant = lin(vec3(0.45, 0.47, 0.30)) * (0.85 + mid * 0.3);
	col = mix(col, dormant, clamp(season_look.w * 0.45 - clump * 0.08 - care * 0.08, 0.0, 0.4));
	float cover = smoothstep(0.05, 0.45, snow * 1.15 - clump * 0.35 + 0.1);
	col = mix(col, vec3(0.80, 0.83, 0.88) * (0.94 + mid * 0.08), cover);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
"""

const LIMESTONE := Color("#bdb08f")
const SLATE := Color("#4a4d52")
const WOOD := Color("#6b5038")
const ALUMINUM := Color("#c4c8c8")

static var _lawn_mat: ShaderMaterial

var _lawn := SurfaceTool.new()
## Text painted on the site goes in labels (CommercialBuilder):
## [{pos, normal (facing out), text, height, color}].
## 0 struggling .. 3 thriving, and how well it is kept (0 to 1).
var tier := 2
var care := 0.7


## Builds a park or landmark from its sim record. Returns [mesh, ground,
## trees, labels, lawn]. `town` is painted on the water tower.
static func build_site(site: Dictionary, seed: int, to_curb: float, town: String) -> Array:
	var b := ParkBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.tier = clampi(int(site.tier), 0, 3)
	b.care = [0.15, 0.5, 0.75, 1.0][b.tier]
	var size: Vector2 = site.size
	var front := -size.y * 0.5
	match str(site.kind):
		"park": b._park(site, size, to_curb)
		"courthouse": b._courthouse(size, to_curb)
		"water_tower": b._town_tower(size, to_curb, town)
		"grain_elevator": b._elevator(size, to_curb)
		"football": b._football(size, to_curb, site.get("venue_built", []), bool(site.get("event_on", false)))
		"fairgrounds": b._fairgrounds(size, to_curb, str(site.name), site.get("venue_built", []),
			bool(site.get("event_on", false)))
		"motel": b._motel(size, to_curb, str(site.name))
		"diner": b._diner(size, to_curb, str(site.name))
		"gas_station": b._gas_station(size, to_curb, str(site.name))
		"trailhead": b._trailhead(size, to_curb)
	var lawn := b._lawn.commit()
	if lawn.get_surface_count() > 0:
		lawn.surface_set_material(0, lawn_material())
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels, lawn]


static func lawn_material() -> ShaderMaterial:
	if _lawn_mat == null:
		_lawn_mat = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = LAWN_SHADER
		_lawn_mat.shader = shader
		_lawn_mat.set_shader_parameter("noise_soft", Ground.noise(512, 0.012, 4, 11))
		_lawn_mat.set_shader_parameter("noise_grain", Ground.noise(256, 0.09, 2, 23))
	return _lawn_mat


# ---------------------------------------------------------------- park

func _park(site: Dictionary, size: Vector2, to_curb: float) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var green: Color = [Color("#7d8a4c"), Color("#5d7a36"), Color("#527633"), Color("#4b7431")][tier]
	_lawn_rect(-hx, hx, -hz, hz, green, care)
	# Features in the park's own frame (the sim keeps them in world space).
	var frame := Basis.looking_at(site.dir, Vector3.UP).inverse()
	var spots := []  # [local centre, size, type]
	for f in site.features:
		if f.type == "paths":
			continue
		var l: Vector3 = frame * (f.pos - site.pos)
		spots.append([Vector3(l.x, 0, l.z), f.size, f.type])
	var entrance := Vector3(0, 0, -hz)
	var has := {}
	for f in site.features:
		has[f.type] = true
	var has_paths: bool = has.has("paths")
	# Walks from the street to each thing, and a loop round the lawn in
	# kept parks. Worn parks get dirt desire lines instead.
	if has_paths:
		var kind := "drive" if tier >= 2 else ("asphalt" if tier == 1 else "gravel")
		var col := Color("#8f7a5c") if tier == 0 else MULCH
		var w := 2.4 if tier >= 1 else 1.4
		_strip(entrance + Vector3(0, 0, -to_curb), entrance + Vector3(0, 0, 6.0), w, kind, col)
		if tier == 0:
			# Worn desire lines, straight from the gate to each thing.
			for s in spots:
				_strip(entrance + Vector3(0, 0, 6.0), s[0] + Vector3(0, 0, -s[1].y * 0.5), w, kind, col)
		else:
			# A main walk from the gate back into the park, with a side
			# walk out to each thing, the way a parks department lays them.
			var back := -hz + 6.0
			for s in spots:
				back = maxf(back, minf(s[0].z, hz - 8.0))
			_strip(entrance + Vector3(0, 0, 6.0 - w * 0.5), Vector3(0, 0, back + w * 0.5), w, kind, col)
			for s in spots:
				var z: float = clampf(s[0].z, -hz + 6.0, back)
				var edge: float = s[0].x - signf(s[0].x) * s[1].x * 0.5
				if absf(s[0].x) < s[1].x * 0.5:
					# Right on the main walk: meet it at its near end.
					_strip(Vector3(0, 0, z), Vector3(0, 0, s[0].z - signf(s[0].z - z) * s[1].y * 0.5), w, kind, col)
				else:
					_strip(Vector3(-signf(s[0].x) * w * 0.5, 0, z), Vector3(edge, 0, z), w, kind, col)
		if has.has("walking_loop") and size.x > 40.0 and size.y > 40.0:
			var ix := hx - 6.0
			var iz := hz - 6.0
			var loop := [Vector3(-ix, 0, -iz), Vector3(ix, 0, -iz), Vector3(ix, 0, iz), Vector3(-ix, 0, iz)]
			# The walking loop is asphalt, as in most town parks.
			for i in 4:
				_strip(loop[i], loop[(i + 1) % 4], 1.8, "asphalt", col)
	for s in spots:
		match s[2]:
			"playground": _playground(s[0], s[1])
			"pavilion": _pavilion(s[0], s[1])
			"court": _court(s[0], s[1])
			"ball_diamond": _park_diamond(s[0], s[1])
			"flower_beds": _flower_beds(s[0], s[1])
			"fountain": _fountain(s[0])
			"splash_pad": _splash_pad(s[0], s[1])
			"all_abilities": _all_abilities(s[0], s[1])
			"youth_complex": _youth_complex(s[0], s[1], has.has("field_lights"))
			"tournament": _concessions(s[0], s[1])
			"bandstand": _bandstand(s[0], s[1])
			"pond": _pond(s[0], s[1])
			"pool": _pool(s[0], s[1], false)
			"aquatic_center": _pool(s[0], s[1], true)
			"pickleball": _pickleball(s[0], s[1])
			"tennis": _tennis(s[0], s[1])
			"volleyball": _volleyball(s[0], s[1])
			"dog_park": _dog_park(s[0], s[1])
			"skate_park": _skate_park(s[0], s[1])
			"shelter_house": _shelter_house(s[0], s[1])
			"amphitheater": _amphitheater(s[0], s[1])
			"veterans_memorial": _veterans_memorial(s[0], s[1])
			"community_garden": _community_garden(s[0], s[1])
	if has.has("field_lights"):
		for s in spots:
			if s[2] == "ball_diamond":
				_field_lights(s[0] + Vector3(0, 0, s[1].y * 0.5 - 8.0))
	if has.has("nature_trail"):
		_nature_trail(size, spots)
	if has.has("disc_golf"):
		_disc_golf(size, spots)
	# A sign at the entrance with the park's name; benches, bins and lamps.
	_park_sign(entrance + Vector3(-4.0, 0, 2.5), str(site.name))
	if has_paths:
		var n: int = [1, 2, 4, 6][tier]
		for i in n:
			var s: Array = spots[i % spots.size()] if not spots.is_empty() else [Vector3(0, 0, 0), Vector2(8, 8)]
			var p: Vector3 = s[0] + Vector3((s[1].x * 0.5 + 2.0) * (1 if i % 2 == 0 else -1), 0, -s[1].y * 0.3)
			_bench(p, PI * 0.5 if i % 2 == 0 else -PI * 0.5)
		if tier >= 2:
			for i in 4:
				_lamp(entrance + Vector3(1.8 * (1 if i % 2 == 0 else -1), 0, 4.0 + i * 8.0))
	_park_trees(size, spots)
	_edge_lawns(site.get("edge", {}), size, to_curb, green, has_paths)


## Edge pieces, cut back to the sidewalk (Parks' edge, in the park's frame):
## more of the same lawn; where a piece is deep enough, a walk from the
## front sidewalk back along each side and one across the back, with
## benches; and shade trees, kept off the walks and back from the edges.
func _edge_lawns(edge: Dictionary, size: Vector2, to_curb: float, green: Color, has_paths: bool) -> void:
	if edge.is_empty():
		return
	var hz := size.y * 0.5
	for c in edge:
		_lawn_poly(edge[c], green, care)
	var kind := "drive" if tier >= 2 else ("asphalt" if tier == 1 else "gravel")
	var col := Color("#8f7a5c") if tier == 0 else MULCH
	var w := 2.0 if tier >= 1 else 1.4
	var walks := []  # [from, to], local (x, z)
	if has_paths:
		# Where the walk across the back runs, if the back piece is deep enough.
		var back_z := INF
		if edge.has(Vector2i(0, 1)) and HubBuilder._bounds(edge[Vector2i(0, 1)]).size.y >= 8.0:
			back_z = HubBuilder._bounds(edge[Vector2i(0, 1)]).get_center().y
		# Back along each side from the front sidewalk, on through the corner
		# behind it to the back walk.
		var side_x := {}
		for sx in [-1, 1]:
			var c := Vector2i(sx, 0)
			if not edge.has(c) or HubBuilder._bounds(edge[c]).size.x < 8.0:
				continue
			var x := HubBuilder._bounds(edge[c]).get_center().x
			var end := back_z if back_z != INF else 5000.0
			var inner := HubBuilder._inset(_edge_row(edge, [c, Vector2i(sx, 1)]), 1.6)
			if inner.size() < 3:
				continue
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, -hz - 1.0),
					Vector2(x, end)]), inner):
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[seg.size() - 1]
				if a.y > b.y:
					var t := a
					a = b
					b = t
				if a.y <= -hz + 2.0:
					a.y = -hz - to_curb  # out to the sidewalk, like the gate's walk
				if b.y >= end - 2.0 and back_z != INF:
					b.y = back_z + w * 0.5
					side_x[sx] = x
				walks.append([a, b])
		# Across the back, through the back corners as far as the side walks.
		var back := HubBuilder._inset(_edge_row(edge, [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]), 1.6)
		if back_z != INF and back.size() >= 3:
			for seg in Geometry2D.intersect_polyline_with_polygon(
					PackedVector2Array([Vector2(-5000, back_z), Vector2(5000, back_z)]), back):
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[seg.size() - 1]
				if a.x > b.x:
					var t := a
					a = b
					b = t
				if side_x.has(-1):
					a.x = maxf(a.x, side_x[-1] - w * 0.5)
				if side_x.has(1):
					b.x = minf(b.x, side_x[1] + w * 0.5)
				if b.x > a.x:
					walks.append([a, b])
	var kept := []
	for wk in walks:
		var a: Vector2 = wk[0]
		var b: Vector2 = wk[1]
		if a.distance_to(b) < 6.0:
			continue
		kept.append(wk)
		_strip(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), w, kind, col)
		# Benches beside it every 24 m or so, on alternate sides.
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var t := 10.0
		var k := 0
		while t < a.distance_to(b) - 6.0 and tier >= 1:
			var off := n * (w * 0.5 + 1.0) * (1.0 if k % 2 == 0 else -1.0)
			var p := a + d * t + off
			_bench(Vector3(p.x, 0, p.y), atan2(off.x, off.y))
			t += 24.0
			k += 1
	# Shade trees lining each walk, then on a loose grid over the rest, fewer
	# and patchier in a neglected park.
	var gap: float = [17.0, 14.0, 12.0, 11.0][tier]
	var skip: float = [0.35, 0.15, 0.05, 0.0][tier]
	var plots := []
	for c in edge:
		plots.append(HubBuilder._inset(edge[c], 2.5))
	for wk in kept:
		var a: Vector2 = wk[0]
		var b: Vector2 = wk[1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * (w * 0.5 + 3.5)
		var t := gap * 0.5
		while t < a.distance_to(b):
			for q in [a + d * t + n, a + d * t - n]:
				var on := false
				for plot in plots:
					on = on or (plot.size() >= 3 and Geometry2D.is_point_in_polygon(q, plot))
				if on and rng.randf() >= skip:
					var pick := TreeField.pick(rng)
					trees.append([Vector3(q.x, 0, q.y), pick[0], pick[1], rng.randf_range(0.85, 1.2)])
			t += gap
	for c in edge:
		var plot := HubBuilder._inset(edge[c], 3.0)
		if plot.size() < 3:
			continue
		var box := HubBuilder._bounds(plot)
		var z := box.position.y + fmod(box.size.y, gap) * 0.5
		while z <= box.end.y:
			var x := box.position.x + fmod(box.size.x, gap) * 0.5
			while x <= box.end.x:
				var q := Vector2(x + rng.randf_range(-1.5, 1.5), z + rng.randf_range(-1.5, 1.5))
				if rng.randf() >= skip and Geometry2D.is_point_in_polygon(q, plot) and not _near_walk(q, kept, w * 0.5 + 5.5):
					var pick := TreeField.pick(rng)
					trees.append([Vector3(q.x, 0, q.y), pick[0], pick[1], rng.randf_range(0.85, 1.2)])
				x += gap
			z += gap


## The edge pieces `keys` (those there) as one outline, the biggest part
## where they meet.
static func _edge_row(edge: Dictionary, keys: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in keys:
		if not edge.has(c):
			continue
		if out.is_empty():
			out = edge[c]
			continue
		# (A hole, if any, is always smaller than the outline round it.)
		var best := out
		for q in Geometry2D.merge_polygons(out, edge[c]):
			if CivicHubs.area(q) > CivicHubs.area(best):
				best = q
		out = best
	return out


static func _near_walk(q: Vector2, walks: Array, reach: float) -> bool:
	for wk in walks:
		if Geometry2D.get_closest_point_to_segment(q, wk[0], wk[1]).distance_to(q) < reach:
			return true
	return false


## Shade trees along the edges and in clumps on open lawn, fewer and patchier
## where the park is neglected.
func _park_trees(size: Vector2, spots: Array) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var gap: float = [17.0, 14.0, 12.0, 10.0][tier]
	var skip: float = [0.35, 0.15, 0.05, 0.0][tier]
	var edge := []
	var x := -hx + 4.0
	while x <= hx - 4.0:
		edge.append(Vector3(x, 0, hz - 3.5))
		if absf(x) > 6.0:
			edge.append(Vector3(x, 0, -hz + 4.0))
		x += gap
	var z := -hz + 4.0 + gap
	while z <= hz - 4.0 - gap * 0.5:
		edge.append(Vector3(-hx + 3.5, 0, z))
		edge.append(Vector3(hx - 3.5, 0, z))
		z += gap
	# Shade trees out on the lawn too, more the bigger the park.
	for i in maxi(6, int(size.x * size.y / 900.0)):
		edge.append(Vector3(rng.randf_range(-hx + 8.0, hx - 8.0), 0, rng.randf_range(-hz + 10.0, hz - 6.0)))
	for p in edge:
		if rng.randf() < skip or _in_spots(p, spots, 5.0) or absf(p.x) < 4.0 or _on_walk(p, spots):
			continue
		var pick := TreeField.pick(rng)
		var q := Vector3(p.x + rng.randf_range(-1.5, 1.5), 0, p.z + rng.randf_range(-1.5, 1.5))
		trees.append([q, pick[0], pick[1], rng.randf_range(0.85, 1.2)])


## True when a point is on a side walk out to one of the things.
func _on_walk(p: Vector3, spots: Array) -> bool:
	for s in spots:
		if absf(p.z - s[0].z) < 3.5 and signf(p.x) == signf(s[0].x) and absf(p.x) < absf(s[0].x):
			return true
	return false


func _in_spots(p: Vector3, spots: Array, pad: float) -> bool:
	for s in spots:
		var size: Vector2 = s[1]
		if absf(p.x - s[0].x) < size.x * 0.5 + pad and absf(p.z - s[0].z) < size.y * 0.5 + pad:
			return true
	return false


func _playground(c: Vector3, size: Vector2) -> void:
	var worn := tier == 0
	_flat_rect("mulch", c.x - size.x * 0.5, c.x + size.x * 0.5, c.z - size.y * 0.5, c.z + size.y * 0.5, 0.05,
		Color("#9a8c74") if worn else Color("#8a6a48"))
	# Timber edging round the mulch.
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(size.x, 0.2, 0.2), c + Vector3(0, 0.1, s * size.y * 0.5), WOOD)
		_box("paint", Vector3(0.2, 0.2, size.y), c + Vector3(s * size.x * 0.5, 0.1, 0), WOOD)
	var fade := 0.45 if worn else 0.0
	var red := Color("#b83a2a").lerp(Color("#9a8a7a"), fade)
	var blue := Color("#2f5a8a").lerp(Color("#8a8f94"), fade)
	var yel := Color("#d9a92a").lerp(Color("#a89a7a"), fade)
	var p := c + Vector3(-3.5, 0, 0)
	# Play tower with a deck, a roof and a slide.
	_box("paint", Vector3(2.6, 0.12, 2.6), p + Vector3(0, 1.6, 0), blue)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.12, 3.2, 0.12), p + Vector3(sx * 1.25, 1.6, sz * 1.25), yel)
	_box("paint", Vector3(2.8, 0.15, 2.8), p + Vector3(0, 3.2, 0), red)
	_box("paint", Vector3(0.8, 0.06, 3.4), p + Vector3(0.6, 0.85, 2.9), yel, Basis(Vector3.RIGHT, -0.5))
	if tier >= 2:
		# A second deck and a climbing wall in kept parks.
		_box("paint", Vector3(2.2, 0.12, 2.2), p + Vector3(-2.6, 1.0, 0), blue)
		_box("paint", Vector3(0.1, 1.0, 2.0), p + Vector3(-3.7, 0.5, 0), red)
	# Swing set; a worn one has a seat missing.
	var s := c + Vector3(4.0, 0, 0)
	_box("paint", Vector3(0.1, 0.1, 4.5), s + Vector3(0, 2.4, 0), DARK if not worn else Color("#6a4a3a"))
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.08, 2.6, 0.08), s + Vector3(sx * 0.6, 1.2, sz * 2.2), DARK, Basis(Vector3.BACK, sx * 0.25))
	for i in 3:
		if worn and i == 1:
			continue
		_box("paint", Vector3(0.25, 0.04, 0.5), s + Vector3(0, 0.55, -1.4 + i * 1.4), DARK)
		_box("paint", Vector3(0.02, 1.85, 0.02), s + Vector3(0, 1.48, -1.4 + i * 1.4 - 0.22), GALV)
		_box("paint", Vector3(0.02, 1.85, 0.02), s + Vector3(0, 1.48, -1.4 + i * 1.4 + 0.22), GALV)


func _pavilion(c: Vector3, size: Vector2) -> void:
	var w := size.x - 2.0
	var d := size.y - 2.0
	_box("paint", Vector3(w + 1.0, 0.2, d + 1.0), c + Vector3(0, 0.1, 0), CONCRETE)
	var post := WOOD if tier < 3 else Color("#3e3a34")
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 2.9, 0.3), c + Vector3(sx * (w * 0.5 - 0.3), 1.65, sz * (d * 0.5 - 0.3)), post)
	_box("paint", Vector3(w, 0.3, 0.3), c + Vector3(0, 3.05, -(d * 0.5 - 0.3)), post)
	_box("paint", Vector3(w, 0.3, 0.3), c + Vector3(0, 3.05, d * 0.5 - 0.3), post)
	var roof: Color = [Color("#7a5a44"), Color("#6e6d6a"), Color("#3e5a48"), Color("#5a2a26")][tier]
	_hip_roof(c.x, c.z, 3.2, w, d, 1.6, roof)
	# Picnic tables: a top and two benches each.
	var n := 2 if tier == 0 else 4
	for i in n:
		var t := c + Vector3(-w * 0.3 + (i % 2) * w * 0.6, 0, -d * 0.2 + (i / 2) * d * 0.4)
		_table(t)
	if tier >= 1:
		_bin(c + Vector3(w * 0.5 + 1.0, 0, -d * 0.5))


func _table(t: Vector3) -> void:
	_box("paint", Vector3(2.4, 0.06, 0.8), t + Vector3(0, 0.76, 0), WOOD.lightened(0.15))
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(2.4, 0.05, 0.28), t + Vector3(0, 0.45, s * 0.65), WOOD.lightened(0.1))
		_box("paint", Vector3(0.08, 0.75, 1.6), t + Vector3(s * 0.9, 0.38, 0), GALV.darkened(0.2))


func _court(c: Vector3, size: Vector2) -> void:
	_flat_rect("asphalt", c.x - size.x * 0.5, c.x + size.x * 0.5, c.z - size.y * 0.5, c.z + size.y * 0.5, 0.06)
	if tier >= 2:
		# Acrylic court colours in kept parks.
		_flat_rect("line", c.x - size.x * 0.5 + 1.0, c.x + size.x * 0.5 - 1.0, c.z - size.y * 0.5 + 1.0,
			c.z + size.y * 0.5 - 1.0, 0.065, Color("#3c6a5a"))
	_flat_rect("line", c.x - 2.4, c.x + 2.4, c.z + size.y * 0.5 - 7.0, c.z + size.y * 0.5 - 1.0, 0.07,
		Color("#a8443a") if tier >= 2 else LINE)
	_hoop(Vector3(c.x, 0, c.z + size.y * 0.5 - 0.6) + Vector3(0, 0, 0))
	if tier >= 1:
		_fence(Vector2(c.x - size.x * 0.5, c.z - size.y * 0.5), Vector2(c.x + size.x * 0.5, c.z + size.y * 0.5), 3.0)


func _hoop_back(p: Vector3) -> void:
	_box("paint", Vector3(0.14, 3.2, 0.14), p + Vector3(0, 1.6, 0.6), DARK)
	_box("paint", Vector3(1.8, 1.1, 0.05), p + Vector3(0, 3.35, 0.45), WHITE)


func _park_diamond(c: Vector3, size: Vector2) -> void:
	# Home plate near the back so the field opens toward the street.
	var home := c + Vector3(0, 0, size.y * 0.5 - 8.0)
	_diamond(home)
	if tier >= 1:
		# Outfield fence: an arc of chain link 46 m out.
		var prev := Vector3.ZERO
		for i in 13:
			var a := lerpf(-PI * 0.25, PI * 0.25, i / 12.0)
			var p := home + Vector3(sin(a), 0, -cos(a)) * 46.0
			_box("paint", Vector3(0.08, 2.0, 0.08), p + Vector3(0, 1.0, 0), GALV)
			if i > 0:
				_strut(prev + Vector3(0, 2.0, 0), p + Vector3(0, 2.0, 0), 0.05, GALV)
				_strut(prev + Vector3(0, 0.1, 0), p + Vector3(0, 0.1, 0), 0.04, GALV)
			prev = p
	if tier >= 2:
		# Aluminium bleachers behind the first-base line.
		var b := home + Vector3(12.0, 0, 3.0)
		for r in 4:
			_box("paint", Vector3(7.0, 0.08, 0.6), b + Vector3(0, 0.45 + r * 0.42, r * 0.7), ALUMINUM, Basis(Vector3.UP, 0.6))


func _flower_beds(c: Vector3, size: Vector2) -> void:
	# A curated park plants annuals; once the area slips the beds go to weeds.
	var colors := [Color("#c23a3a"), Color("#e8c23a"), Color("#d86aa0"), Color("#f2efe6"), Color("#8a5ac2")]
	for s in [-1.0, 1.0]:
		var bc := c + Vector3(s * size.x * 0.27, 0, 0)
		_flat_rect("mulch", bc.x - size.x * 0.22, bc.x + size.x * 0.22, bc.z - size.y * 0.4, bc.z + size.y * 0.4, 0.05,
			MULCH if tier >= 2 else Color("#5a5a34"))
		for i in 10:
			var p := bc + Vector3(rng.randf_range(-size.x * 0.2, size.x * 0.2), 0, rng.randf_range(-size.y * 0.35, size.y * 0.35))
			if tier >= 2:
				var col: Color = colors[rng.randi() % colors.size()]
				_box("foliage", Vector3(0.5, 0.35, 0.5), p + Vector3(0, 0.2, 0), col)
			else:
				_shrub(p, rng.randf_range(0.25, 0.4))


func _fountain(c: Vector3) -> void:
	var stone := LIMESTONE if tier >= 2 else Color("#a8a294")
	_cylinder("paint", c, 4.2, 0.55, stone, 24)
	if tier >= 2:
		_cylinder("paint", c + Vector3(0, 0.05, 0), 3.9, 0.45, Color("#3a6a7a"), 24)  # water
		_cyl_y(c + Vector3(0, 1.2, 0), 0.25, 2.0, stone)
		_cylinder("paint", c + Vector3(0, 1.6, 0), 1.2, 0.2, stone, 16)
		_cylinder("paint", c + Vector3(0, 1.75, 0), 1.0, 0.08, Color("#4a7a8a"), 16)
		_box("paint", Vector3(0.12, 1.4, 0.12), c + Vector3(0, 2.6, 0), Color("#d8e8ee"))  # the jet
	else:
		# Turned off: a dry basin with a stain line.
		_cylinder("paint", c + Vector3(0, 0.05, 0), 3.9, 0.4, Color("#8a8476"), 24)
		_cyl_y(c + Vector3(0, 1.2, 0), 0.25, 2.0, stone)


func _bench(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_box("paint", Vector3(1.8, 0.06, 0.45), p + Vector3(0, 0.45, 0), WOOD.lightened(0.1), b)
	_box("paint", Vector3(1.8, 0.4, 0.06), p + b * Vector3(0, 0.72, 0.22), WOOD.lightened(0.1), b)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.08, 0.45, 0.45), p + b * Vector3(s * 0.8, 0.22, 0), DARK, b)


func _bin(p: Vector3) -> void:
	_cylinder("paint", p, 0.32, 0.95, Color("#2f4632"), 10)


func _lamp(p: Vector3) -> void:
	_cyl_y(p + Vector3(0, 2.0, 0), 0.07, 4.0, Color("#202224"))
	_box("paint", Vector3(0.36, 0.5, 0.36), p + Vector3(0, 4.2, 0), Color("#e8e2c8"))
	_box("paint", Vector3(0.46, 0.08, 0.46), p + Vector3(0, 4.5, 0), Color("#202224"))


func _park_sign(p: Vector3, name: String) -> void:
	# Routed wood sign on two posts, the classic parks-department look.
	var face := Color("#5a3e2a") if tier < 3 else Color("#2f4632")
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.18, 1.6, 0.18), p + Vector3(s * 1.4, 0.8, 0), WOOD)
	_box("paint", Vector3(3.2, 0.8, 0.12), p + Vector3(0, 1.2, 0), face)
	labels.append({"pos": p + Vector3(0, 1.2, -0.08), "normal": Vector3(0, 0, -1), "text": name,
		"height": 0.28, "color": Color("#efe6c8")})
	if tier >= 2:
		_bed(p.x, p.z - 0.2, 3.6)


## A flat strip of walk from a to b (on the ground), any direction.
func _strip(a: Vector3, b: Vector3, w: float, kind: String, col: Color, y := 0.045) -> void:
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	if d.length() < 0.5:
		return
	var n := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	# y: under mulch beds and courts, which sit on top of the walks
	var pts := [Vector3(a.x, y, a.z) - n, Vector3(b.x, y, b.z) - n, Vector3(b.x, y, b.z) + n, Vector3(a.x, y, a.z) + n]
	var order := [0, 1, 2, 0, 2, 3]
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).y > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	# Distance along the walk in UV.y * 4, so concrete joints run across it.
	var len := d.length()
	var uvs := [Vector2(0, 0), Vector2(0, len / 4.0), Vector2(w / 4.0, len / 4.0), Vector2(w / 4.0, 0)]
	for i in order:
		_flat.set_normal(Vector3.UP)
		_flat.set_color(col)
		_flat.set_uv(uvs[i])
		_flat.add_vertex(pts[i])


## Lawn over any outline (x, z), in the park lawn shader.
func _lawn_poly(poly: PackedVector2Array, col: Color, kept: float, y := 0.03) -> void:
	col.a = kept
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in idx:
		_lawn.set_normal(Vector3.UP)
		_lawn.set_color(col)
		_lawn.set_uv(poly[i])
		_lawn.add_vertex(Vector3(poly[i].x, y, poly[i].y))


## Lawn over a rectangle, in the park lawn shader.
func _lawn_rect(x0: float, x1: float, z0: float, z1: float, col: Color, kept: float, y := 0.03) -> void:
	col.a = kept
	var pts := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	for i in [0, 1, 2, 0, 2, 3]:
		_lawn.set_normal(Vector3.UP)
		_lawn.set_color(col)
		_lawn.set_uv(Vector2(pts[i].x, pts[i].z))
		_lawn.add_vertex(pts[i])


# ---------------------------------------------------------------- courthouse

func _courthouse(size: Vector2, to_curb: float) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_lawn_rect(-hx, hx, -hz, hz, Color("#4f7532"), maxf(care, 0.6))
	# A walk round the square, diagonal walks from each corner and a wide
	# front walk to the steps.
	for s in [-1.0, 1.0]:
		_flat_rect("drive", -hx, hx, s * (hz - 1.5) - 1.5, s * (hz - 1.5) + 1.5, 0.05)
		_flat_rect("drive", s * (hx - 1.5) - 1.5, s * (hx - 1.5) + 1.5, -hz, hz, 0.05)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_strip(Vector3(sx * (hx - 2.0), 0, sz * (hz - 2.0)), Vector3(sx * 17.0, 0, sz * 13.0), 2.6, "drive", MULCH)
	_flat_rect("drive", -3.5, 3.5, -hz - to_curb, -13.0, 0.06)
	var w := 34.0
	var d := 26.0
	var h := 15.0
	# Rusticated base storey, two storeys of tall windows, a deep cornice.
	_box("paint", Vector3(w + 0.6, 0.6, d + 0.6), Vector3(0, 0.3, 0), LIMESTONE.darkened(0.12))
	_box("paint", Vector3(w, h, d), Vector3(0, h * 0.5, 0), LIMESTONE)
	_box("paint", Vector3(w + 0.3, 0.35, d + 0.3), Vector3(0, 4.6, 0), LIMESTONE.darkened(0.08))
	_box("paint", Vector3(w + 1.2, 0.8, d + 1.2), Vector3(0, h + 0.2, 0), LIMESTONE.lightened(0.05))
	for floor in 3:
		var y := 2.4 + floor * 4.6
		var wh := 1.9 if floor == 0 else 2.6
		for out in [Vector3.FORWARD, Vector3.BACK]:
			for i in 9:
				var x := -w * 0.5 + 2.2 + i * (w - 4.4) / 8.0
				if absf(x) < 4.0 and out == Vector3.FORWARD and floor == 0:
					continue
				_glass(Vector3(x, y, out.z * (d * 0.5 + 0.03)), Vector3(-out.z, 0, 0), 1.3, wh, 0.2)
				_box("paint", Vector3(1.6, 0.18, 0.2), Vector3(x, y + wh * 0.5 + 0.15, out.z * (d * 0.5 + 0.08)), LIMESTONE.lightened(0.08))
		for out in [Vector3.LEFT, Vector3.RIGHT]:
			for i in 7:
				var z := -d * 0.5 + 2.2 + i * (d - 4.4) / 6.0
				_glass(Vector3(out.x * (w * 0.5 + 0.03), y, z), Vector3(0, 0, out.x), 1.3, wh, 0.2)
	# Portico: steps, four columns and a pediment over the front doors.
	var zf := -d * 0.5
	for i in 4:
		_box("paint", Vector3(12.0 - i * 0.6, 0.3, 1.0), Vector3(0, 0.15 + i * 0.3, zf - 4.6 + i * 0.6), LIMESTONE.darkened(0.05))
	_box("paint", Vector3(11.0, 0.4, 4.0), Vector3(0, 1.2, zf - 2.0), LIMESTONE.darkened(0.05))
	for i in 4:
		_cylinder("paint", Vector3(-4.2 + i * 2.8, 1.4, zf - 3.4), 0.42, 8.6, LIMESTONE.lightened(0.06), 12)
	_box("paint", Vector3(11.6, 1.0, 4.4), Vector3(0, 10.5, zf - 2.0), LIMESTONE.lightened(0.04))
	_tri("paint", Vector3(-5.8, 11.0, zf - 4.2), Vector3(5.8, 11.0, zf - 4.2), Vector3(0, 13.4, zf - 4.2), LIMESTONE, [], Vector3.FORWARD)
	_quad("roof", Vector3(-5.8, 11.0, zf - 4.2), Vector3(0, 13.4, zf - 4.2), Vector3(0, 13.4, zf), Vector3(-5.8, 11.0, zf), SLATE, [], Vector3(-1, 1, 0))
	_quad("roof", Vector3(5.8, 11.0, zf - 4.2), Vector3(0, 13.4, zf - 4.2), Vector3(0, 13.4, zf), Vector3(5.8, 11.0, zf), SLATE, [], Vector3(1, 1, 0))
	_box("paint", Vector3(3.0, 3.4, 0.1), Vector3(0, 3.1, zf - 0.03), Color("#4a3426"))  # doors
	labels.append({"pos": Vector3(0, 9.6, zf - 4.25), "normal": Vector3(0, 0, -1), "text": "COUNTY COURTHOUSE",
		"height": 0.55, "color": Color("#4a4438")})
	# Low hip roof behind the parapet.
	_hip_roof(0.0, 0.0, h + 0.6, w - 1.0, d - 1.0, 3.0, SLATE)
	# Clock tower: a square shaft, clock faces, a lantern and a dome.
	var t := 9.0
	_box("paint", Vector3(t, 12.0, t), Vector3(0, h + 6.0, 0), LIMESTONE)
	_box("paint", Vector3(t + 0.8, 0.6, t + 0.8), Vector3(0, h + 12.2, 0), LIMESTONE.lightened(0.05))
	for out in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var c := Vector3(out.x * (t * 0.5 + 0.06), h + 9.0, out.z * (t * 0.5 + 0.06))
		var right := Vector3(-out.z, 0, out.x)
		var face := []
		for i in 16:
			var a := TAU * i / 16.0
			face.append(c + right * cos(a) * 1.7 + Vector3(0, sin(a) * 1.7, 0))
		for i in 16:
			_tri("paint", c, face[i], face[(i + 1) % 16], Color("#f2efe4"), [], out)
		_box("paint", Vector3(absf(right.x) * 0.12 + absf(out.x) * 0.05, 1.3, absf(right.z) * 0.12 + absf(out.z) * 0.05),
			c + out * 0.04 + Vector3(0, 0.55, 0), DARK)
		_box("paint", Vector3(absf(right.x) * 1.0 + absf(out.x) * 0.05, 0.1, absf(right.z) * 1.0 + absf(out.z) * 0.05),
			c + out * 0.05 + right * 0.45, DARK)
	for i in 8:
		var a := TAU * i / 8.0
		_cyl_y(Vector3(cos(a) * 3.0, h + 14.2, sin(a) * 3.0), 0.25, 3.4, LIMESTONE.lightened(0.06))
	var prof := []
	for i in 9:
		var a := PI * 0.5 * i / 8.0
		prof.append(Vector2(cos(a) * 3.6, h + 15.9 + sin(a) * 4.2))
	_lathe(Vector3.ZERO, prof, Color("#6f8a7e"), 20)  # weathered copper
	_cyl_y(Vector3(0, h + 21.0, 0), 0.08, 2.4, Color("#c9a24a"))
	# War memorial, flag, benches and big trees round the square.
	var m := Vector3(-18.0, 0, -hz + 14.0)
	_box("paint", Vector3(3.0, 0.6, 3.0), m + Vector3(0, 0.3, 0), Color("#8a8a86"))
	_box("paint", Vector3(1.2, 6.0, 1.2), m + Vector3(0, 3.6, 0), Color("#9d9b94"))
	_box("paint", Vector3(0.5, 0.8, 0.5), m + Vector3(0, 7.0, 0), Color("#9d9b94"))
	_flagpole(Vector3(18.0, 0, -hz + 14.0))
	for i in 6:
		_bench(Vector3(-15.0 + i * 6.0, 0, -hz + 6.0), PI)
	var x := -hx + 6.0
	while x <= hx - 6.0:
		for zz in [-hz + 6.5, hz - 6.5]:
			if absf(x) > 6.0 or zz > 0.0:
				var pick := TreeField.pick(rng)
				trees.append([Vector3(x, 0, zz), pick[0], pick[1], rng.randf_range(1.1, 1.35)])
		x += 13.0
	var z := -hz + 19.5
	while z <= hz - 19.0:
		for xx in [-hx + 6.5, hx - 6.5]:
			var pick := TreeField.pick(rng)
			trees.append([Vector3(xx, 0, z), pick[0], pick[1], rng.randf_range(1.1, 1.35)])
		z += 13.0
	for s in [-1.0, 1.0]:
		_bed(s * 9.0, zf - 6.0, 5.0)


# ---------------------------------------------------------------- water tower

func _town_tower(size: Vector2, to_curb: float, town: String) -> void:
	_lawn_rect(-size.x * 0.5, size.x * 0.5, -size.y * 0.5, size.y * 0.5, Color("#557a36"), 0.6)
	_water_tower(-size.y * 0.5, to_curb)
	# The town's name in big letters round the tank, front and back.
	var c := Vector3(0, 0, -size.y * 0.5 + 15.0)
	# Letter by letter, so the name wraps round the curve of the tank.
	var text := town.to_upper()
	var step := 1.45 / 9.1  # letter pitch over the tank's radius
	for side in [0.0, PI]:
		for i in text.length():
			# Left to right as seen from outside, on either face.
			var a: float = side - PI * 0.5 - (i - (text.length() - 1) * 0.5) * step
			var out := Vector3(cos(a), 0, sin(a))
			labels.append({"pos": c + Vector3(0, 36.0, 0) + out * 9.08, "normal": out, "text": text[i],
				"height": 2.2, "color": Color("#16305c")})


# ---------------------------------------------------------------- grain elevator

func _elevator(size: Vector2, to_curb: float) -> void:
	var hz := size.y * 0.5
	_flat_rect("gravel", -size.x * 0.5, size.x * 0.5, -hz, hz, 0.04, GRAVEL)
	_flat_rect("gravel", -4.0, 4.0, -hz - to_curb, -hz, 0.08, GRAVEL)
	var concrete := Color("#d2cfc6")
	# A row of slip-formed silos, 8.5 m across and 36 m tall.
	var n := 4
	var r := 4.25
	var zc := 4.0
	for i in n:
		var x := -12.0 + i * r * 2.0
		_cylinder("slipform", Vector3(x, 0, zc), r, 36.0, concrete.darkened(rng.randf_range(0.0, 0.06)), 28)
	# The gallery on top and the tall headhouse at one end.
	_box("metal", Vector3(n * r * 2.0, 3.0, 4.0), Vector3(-12.0 + (n - 1) * r, 37.5, zc), Color("#b9b4a6"))
	var hx := -12.0 + n * r * 2.0 + 1.0
	_slip_box(Vector3(9.0, 46.0, 10.0), Vector3(hx, 0, zc), concrete.lightened(0.04))
	_box("metal", Vector3(7.0, 5.0, 8.0), Vector3(hx, 48.5, zc), Color("#b9b4a6"))
	_elevator_detail(hx, zc, r, n)
	labels.append({"pos": Vector3(hx, 41.0, zc - 5.06), "normal": Vector3(0, 0, -1), "text": "FARMERS CO-OP",
		"height": 1.4, "color": Color("#7a1f1f")})
	# Leg spouts down to the bins, and the drive-through dump pit shed.
	for i in 2:
		_strut(Vector3(hx - 3.0, 44.0, zc - 3.0), Vector3(-22.0 + i * 0.0, 13.0 + i * 0.0, -10.0 + i * 12.0), 0.35, GALV)
	_box("metal", Vector3(10.0, 7.0, 12.0), Vector3(hx + 1.0, 3.5, -10.0), Color("#c9cbc8"))
	_metal_roof(hx + 1.0, -10.0, 7.0, 10.0, 12.0, Color("#8e9aa3"))
	# Corrugated steel bins with cone roofs beside the silos.
	for i in 2:
		var c := Vector3(-22.0, 0, -10.0 + i * 12.0)
		_cylinder("metal", c, 5.5, 11.0, Color("#c4c8c6"), 20)
		var prof := [Vector2(5.8, 11.0), Vector2(0.6, 14.6), Vector2(0.0, 14.8)]
		_lathe(c, prof, Color("#b9bcbc"), 20)
	# Truck scale and the scale house by the street.
	_flat_rect("drive", 8.0, 11.5, -hz + 2.0, -hz + 22.0, 0.07)
	_box("siding", Vector3(4.0, 3.0, 4.0), Vector3(15.0, 1.5, -hz + 8.0), Color("#d8d2c2"))
	_metal_roof(15.0, -hz + 8.0, 3.0, 4.0, 4.0, Color("#5a2a26"))
	_glass(Vector3(13.0 - 0.03, 1.6, -hz + 8.0), Vector3(0, 0, 1), 1.6, 1.0, 0.1)


## A slip-formed box standing on the ground at `foot`: UV.y is the height
## up each wall, for the slipform shader's lift lines and grime.
func _slip_box(size: Vector3, foot: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [foot + Vector3(-h.x, 0, -h.z), foot + Vector3(h.x, 0, -h.z), foot + Vector3(h.x, 0, h.z), foot + Vector3(-h.x, 0, h.z)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var w := a.distance_to(b)
		var out := Vector3(b.z - a.z, 0, a.x - b.x).normalized()
		_quad("slipform", a, b, b + Vector3(0, size.y, 0), a + Vector3(0, size.y, 0), col,
			[Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)], out)
	_quad("paint", c[0] + Vector3(0, size.y, 0), c[1] + Vector3(0, size.y, 0), c[2] + Vector3(0, size.y, 0),
		c[3] + Vector3(0, size.y, 0), col.darkened(0.15), [], Vector3.UP)


## What makes a country elevator read as one up close: the headhouse's
## stair windows and lit top floor with a roof rail and radio mast, a
## galvanised tower grain dryer, and aeration fans, caged ladders and roof
## vents on the steel bins (benchmarked on Indiana co-op elevators).
func _elevator_detail(hx: float, zc: float, r: float, n: int) -> void:
	var front := zc - 5.0
	# The stair tower's small windows, one a landing, up the front face.
	var y := 4.0
	while y < 44.0:
		_glass(Vector3(hx + 3.0, y, front - 0.03), Vector3(-1, 0, 0), 0.7, 1.0, 0.0)
		y += 4.2
	# The head floor's window band, its roof rail and a radio mast.
	for i in 3:
		_glass(Vector3(hx - 2.2 + i * 2.2, 49.0, zc - 4.03), Vector3(-1, 0, 0), 1.4, 0.9, 0.0)
	for e in [[Vector3(-3.4, 0, -3.9), Vector3(3.4, 0, -3.9)], [Vector3(3.4, 0, -3.9), Vector3(3.4, 0, 3.9)],
			[Vector3(3.4, 0, 3.9), Vector3(-3.4, 0, 3.9)], [Vector3(-3.4, 0, 3.9), Vector3(-3.4, 0, -3.9)]]:
		var a: Vector3 = Vector3(hx, 51.0, zc) + e[0]
		var b: Vector3 = Vector3(hx, 51.0, zc) + e[1]
		_strut(a + Vector3(0, 1.05, 0), b + Vector3(0, 1.05, 0), 0.05, Color("#e8c23a"))
		for k in 4:
			_box("paint", Vector3(0.05, 1.05, 0.05), a.lerp(b, k / 3.0) + Vector3(0, 0.52, 0), Color("#e8c23a"))
	_box("paint", Vector3(0.12, 9.0, 0.12), Vector3(hx + 2.4, 55.5, zc + 2.4), GALV)
	_box("paint", Vector3(0.9, 0.06, 0.06), Vector3(hx + 2.4, 58.0, zc + 2.4), GALV)
	# Dust-stained concrete round the dump pit, where the trucks tip.
	_flat_rect("gravel", hx - 4.0, hx + 6.0, -18.0, -2.0, 0.05, Color("#9a9384"))
	# A galvanised tower dryer in front of the bins: the column, its
	# burner plenum at the foot, a cone cap and a caged ladder.
	var dc := Vector3(-8.0, 0, -11.0)
	_cylinder("metal", dc, 2.6, 22.0, Color("#b8bcbc"), 20)
	_lathe(dc, [Vector2(2.8, 22.0), Vector2(0.4, 23.6), Vector2(0.0, 23.7)], Color("#a9adab"), 20)
	_box("metal", Vector3(3.2, 3.4, 2.4), dc + Vector3(3.6, 1.7, 0), Color("#c4c8c6"))
	_box("paint", Vector3(1.0, 1.0, 1.4), dc + Vector3(5.6, 1.4, 0), Color("#3f4a52"))
	_caged_ladder(dc + Vector3(0, 0, -2.6), 22.0, Vector3(0, 0, -1))
	_strut(Vector3(hx - 3.5, 44.0, zc - 4.0), dc + Vector3(0, 23.2, 0), 0.3, GALV)
	# The steel bins: aeration fans and their ducts, caged ladders, roof
	# vents and eave rings.
	for i in 2:
		var c := Vector3(-22.0, 0, -10.0 + i * 12.0)
		var face := Vector3(1, 0, 0) if i == 0 else Vector3(-1, 0, 0).rotated(Vector3.UP, 0.6)
		var fan := c + Vector3(5.5 + 1.2, 0, 0) if i == 0 else c + Vector3(0, 0, 5.5 + 1.2)
		_box("metal", Vector3(1.6, 1.4, 1.4), fan + Vector3(0, 0.9, 0), Color("#c4c8c6"))
		_cyl_y(fan + Vector3(0.9 if i == 0 else 0.0, 0.9, 0.9 if i == 1 else 0.0), 0.62, 0.3, Color("#3f4a52"))
		_caged_ladder(c + Vector3(-5.6, 0, 0), 11.0, Vector3(-1, 0, 0))
		_box("paint", Vector3(11.6, 0.12, 0.1), c + Vector3(0, 10.95, -5.55), Color("#9a9fa2"))
		for v in 3:
			var a := TAU * v / 3.0 + 0.4
			_box("metal", Vector3(0.9, 0.5, 0.9), c + Vector3(cos(a) * 3.6, 13.0, sin(a) * 3.6), Color("#a9adab"))
	# A floodlight pole over the scale.
	_cyl_y(Vector3(12.5, 5.0, -16.0), 0.13, 10.0, POLE)
	_box("paint", Vector3(0.6, 0.35, 0.5), Vector3(12.5, 9.6, -15.6), Color("#4a4e52"))


## A fixed steel ladder with a safety cage, `h` tall, standing off a wall
## that faces `out`.
func _caged_ladder(foot: Vector3, h: float, out: Vector3) -> void:
	var side := Vector3(out.z, 0, -out.x) * 0.25
	var base := foot + out * 0.25
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.05, h, 0.05), base + side * s + Vector3(0, h * 0.5, 0), GALV)
	var y := 2.4
	while y < h:
		for k in 4:
			var a0 := PI * k / 4.0
			var a1 := PI * (k + 1) / 4.0
			_strut(base + out * (0.35 + sin(a0) * 0.35) + side * cos(a0) * 1.4 + Vector3(0, y, 0),
				base + out * (0.35 + sin(a1) * 0.35) + side * cos(a1) * 1.4 + Vector3(0, y, 0), 0.04, GALV.darkened(0.1))
		y += 1.0
	for k in 3:
		var a := PI * (k + 1) / 4.0
		var p := base + out * (0.35 + sin(a) * 0.35) + side * cos(a) * 1.4
		_box("paint", Vector3(0.05, h - 2.4, 0.05), p + Vector3(0, 2.4 + (h - 2.4) * 0.5, 0), GALV.darkened(0.1))


# ---------------------------------------------------------------- football

func _football(size: Vector2, to_curb: float, built := [], on := false) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_lawn_rect(-hx, hx, -hz, hz, Color("#557a36"), maxf(care, 0.75))
	# 120 yards by 53 1/3: a 100 yd field and two 10 yd end zones.
	var yd := 0.9144
	var fx := 60.0 * yd
	var fz := 26.667 * yd
	for i in 20:
		var x0 := -50.0 * yd + i * 5.0 * yd
		_lawn_rect(x0, x0 + 5.0 * yd, -fz, fz, Color("#3f7a2c") if i % 2 == 0 else Color("#4a8634"), 1.0, 0.04)
	for s in [-1.0, 1.0]:
		var e0: float = s * 50.0 * yd
		_lawn_rect(minf(e0, s * fx), maxf(e0, s * fx), -fz, fz, Color("#6e1f2a"), 1.0, 0.04)
	# Yard lines every 5 yards, hash marks, sidelines and end lines.
	for i in 21:
		var x := -50.0 * yd + i * 5.0 * yd
		_flat_rect("line", x - 0.06, x + 0.06, -fz, fz, 0.06, LINE)
	for s in [-1.0, 1.0]:
		_flat_rect("line", -fx, fx, s * fz - 0.1, s * fz + 0.1, 0.06, LINE)
		_flat_rect("line", s * fx - 0.1, s * fx + 0.1, -fz, fz, 0.06, LINE)
		# Goalposts: a gooseneck post, crossbar at 10 ft, uprights 18'6" apart.
		var g := Vector3(s * (fx + 0.5), 0, 0)
		var yel := Color("#e8c23a")
		_cyl_y(g + Vector3(s * 1.2, 1.6, 0), 0.12, 3.2, yel)
		_strut(g + Vector3(s * 1.2, 3.2, 0), g + Vector3(0, 3.05, 0), 0.2, yel)
		_box("paint", Vector3(0.14, 0.14, 5.64), g + Vector3(0, 3.05, 0), yel)
		for u in [-1.0, 1.0]:
			_box("paint", Vector3(0.1, 6.1, 0.1), g + Vector3(0, 6.1, u * 2.82), yel)
	# Midfield circle in school colours.
	var ring := []
	for i in 20:
		ring.append(Vector3(cos(TAU * i / 20.0) * 4.0, 0, sin(TAU * i / 20.0) * 4.0))
	_flat_poly(ring, 0.065, Color("#6e1f2a"))
	# Home bleachers on the far side, a press box on top; visitors near the street.
	# The boosters' home grandstand doubles the home side.
	_bleachers(Vector3(0, 0, fz + 5.0), 80.0 if "home_stands" in built else 60.0, 14 if "home_stands" in built else 10, true)
	# A regional playoff host brings in portable visitor stands and a gate.
	_bleachers(Vector3(0, 0, -fz - 5.0), 54.0 if "playoffs" in built else 30.0, 7 if "playoffs" in built else 5, false)
	if "playoffs" in built:
		var gate := Vector3(5.5, 0, -hz + 3.0)
		_box("siding", Vector3(3.0, 2.6, 2.4), gate + Vector3(0, 1.3, 0), Color("#d8d2c2"))
		_box("paint", Vector3(3.4, 0.2, 2.8), gate + Vector3(0, 2.7, 0), Color("#6e1f2a"))
		_glass(Vector3(gate.x, 1.5, gate.z - 1.23), Vector3(-1, 0, 0), 2.0, 0.9, 0.0)
	if "turf" in built:
		# Synthetic turf has its yard numbers inlaid: 10 to 50 and back,
		# both sides, 12 yards in from the sidelines.
		for i in range(1, 10):
			var x := -50.0 * yd + i * 10.0 * yd
			for z in [-fz + 11.0 * yd, fz - 11.0 * yd]:
				_flat_rect("line", x - 1.0, x - 0.3, z - 0.9, z + 0.9, 0.065, LINE)
				_flat_rect("line", x + 0.3, x + 1.0, z - 0.9, z + 0.9, 0.065, LINE)
	if "track" in built:
		# Track and field where a small school's site has room (no full
		# 400 m oval): a four-lane red straightaway behind the visitor
		# stands, a long-jump runway and sand pit, and a shot put ring.
		var t0 := -fz - 11.2
		_flat_rect("gravel", 6.0, hx - 4.0, t0 - 4.9, t0, 0.07, Color("#a8452f"))
		for k in 5:
			_flat_rect("line", 6.0, hx - 4.0, t0 - k * 1.22 - 0.03, t0 - k * 1.22 + 0.03, 0.075, LINE)
		_flat_rect("gravel", -hx + 6.0, -24.0, t0 - 2.6, t0 - 1.4, 0.07, Color("#a8452f"))
		_flat_rect("gravel", -24.0, -15.0, t0 - 3.4, t0 - 0.6, 0.07, Color("#d9c79a"))
		var shot := []
		for i in 16:
			shot.append(Vector3(-10.0 + cos(TAU * i / 16.0) * 1.07, 0, t0 - 2.0 + sin(TAU * i / 16.0) * 1.07))
		_flat_poly(shot, 0.07, CONCRETE)
	if "concerts" in built:
		# A summer stage at the west end zone, its roof on four trusses.
		var st := Vector3(-fx - 6.0, 0, 0)
		_box("paint", Vector3(6.0, 1.2, 14.0), st + Vector3(0, 0.6, 0), DARK)
		for u in [-1.0, 1.0]:
			for v in [-1.0, 1.0]:
				_box("paint", Vector3(0.4, 7.0, 0.4), st + Vector3(u * 2.6, 4.2, v * 6.8), GALV)
		_box("paint", Vector3(6.6, 0.5, 14.6), st + Vector3(0, 7.9, 0), DARK)
	if on:
		# Game night: a crowd in the stands (bands of colour on the seats).
		for i in 3:
			_box("paint", Vector3(50.0, 0.5, 0.5), Vector3(0, 1.2 + i * 1.1, fz + 6.0 + i * 1.5), Color("#6e1f2a").lerp(WHITE, 0.3 * i))
	_box("siding", Vector3(14.0, 3.0, 3.6), Vector3(0, 6.6, fz + 5.0 + 10 * 0.75 + 1.4), Color("#d8d2c2"))
	_flat_roofed_at("siding", 0.0, 14.0, 3.6, fz + 5.0 + 10 * 0.75 + 1.4, 8.1, 8.4, Color("#d8d2c2"))
	_glass(Vector3(0, 7.0, fz + 5.0 + 10 * 0.75 - 0.42), Vector3(-1, 0, 0), 12.0, 1.4, 0.0)
	# Four light towers and a scoreboard past the end zone.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 32.0, 0, sz * (fz + 12.0 if sz > 0 else fz + 9.0))
			_cyl_y(p + Vector3(0, 12.5, 0), 0.3, 25.0, Color("#8a8f94"))
			_box("paint", Vector3(4.0, 2.2, 0.4), p + Vector3(0, 25.6, -sz * 0.4), Color("#d8dadb"))
			_box("paint", Vector3(4.2, 0.12, 0.6), p + Vector3(0, 24.4, -sz * 0.4), Color("#5a5e60"))
	var sb := Vector3(-hx + 4.0, 0, 0)
	for u in [-1.0, 1.0]:
		_box("paint", Vector3(0.3, 6.0, 0.3), sb + Vector3(0, 3.0, u * 3.0), DARK)
	_box("paint", Vector3(0.4, 3.0, 8.0), sb + Vector3(0, 6.5, 0), Color("#1d2a20"))
	labels.append({"pos": sb + Vector3(0.22, 7.3, 0), "normal": Vector3(1, 0, 0), "text": "HOME   GUEST",
		"height": 0.5, "color": Color("#e8c23a")})
	_fence(Vector2(-hx + 1.0, -hz + 1.0), Vector2(hx - 1.0, hz - 1.0), 1.8)
	_flat_rect("drive", -3.0, 3.0, -hz - to_curb, -fz - 9.0, 0.06)


## Aluminium bleachers: `rows` of seats stepping up away from the field,
## facing it. `far` is on the +z side.
func _bleachers(c: Vector3, length: float, rows: int, far: bool) -> void:
	var s := 1.0 if far else -1.0
	for r in rows:
		var z := c.z + s * r * 0.75
		var y := 0.5 + r * 0.42
		_box("paint", Vector3(length, 0.06, 0.32), Vector3(c.x, y, z), ALUMINUM)
		_box("paint", Vector3(length, 0.04, 0.3), Vector3(c.x, y - 0.3, z - s * 0.32), ALUMINUM.darkened(0.15))
	var depth := rows * 0.75
	for i in int(length / 6.0) + 1:
		var x := c.x - length * 0.5 + i * 6.0
		_strut(Vector3(x, 0, c.z), Vector3(x, 0.5 + rows * 0.42, c.z + s * depth), 0.12, GALV.darkened(0.2))
		_box("paint", Vector3(0.12, 0.5 + rows * 0.42, 0.12), Vector3(x, (0.5 + rows * 0.42) * 0.5, c.z + s * depth), GALV.darkened(0.2))
	_box("paint", Vector3(length, 1.0, 0.05), Vector3(c.x, 1.0 + rows * 0.42, c.z + s * (depth + 0.1)), ALUMINUM)


# ---------------------------------------------------------------- park tree

## A chain-link fence from a to b, `h` tall: posts every 3 m, a top rail,
## the fabric (see-through, the chain material), and below `screen` metres
## a dark windscreen (tennis), or none.
func _chain_run(a: Vector3, b: Vector3, h: float, col: Color, screen := 0.0) -> void:
	var len := a.distance_to(b)
	if len < 0.3:
		return
	var dir := (b - a) / len
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var n := maxi(1, int(len / 3.0))
	for k in n + 1:
		_box("paint", Vector3(0.07, h, 0.07), a + dir * (len * k / n) + Vector3(0, h * 0.5, 0), col)
	_box("paint", Vector3(0.05, 0.05, len), (a + b) * 0.5 + Vector3(0, h, 0), col, yaw)
	var off := Vector3(dir.z, 0, -dir.x) * 0.05
	_quad("chain", a + off + Vector3(0, 0.05, 0), b + off + Vector3(0, 0.05, 0), b + off + Vector3(0, h, 0), a + off + Vector3(0, h, 0),
		col, [Vector2(0, 0), Vector2(len, 0), Vector2(len, h), Vector2(0, h)], off)
	if screen > 0.0:
		_quad("paint", a + off * 2.0 + Vector3(0, 0.1, 0), b + off * 2.0 + Vector3(0, 0.1, 0), b + off * 2.0 + Vector3(0, screen, 0),
			a + off * 2.0 + Vector3(0, screen, 0), Color("#24382c"), [], off)


func _chain_box(c: Vector3, size: Vector2, h: float, col: Color, gate := 0.0, screen := 0.0) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	# The gate: a gap in the front (-z) run, `gate` wide, left of centre.
	if gate > 0.0:
		_chain_run(c + Vector3(-hx, 0, -hz), c + Vector3(-gate - 1.0, 0, -hz), h, col, screen)
		_chain_run(c + Vector3(-1.0, 0, -hz), c + Vector3(hx, 0, -hz), h, col, screen)
	else:
		_chain_run(c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz), h, col, screen)
	_chain_run(c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz), h, col, screen)
	_chain_run(c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz), h, col, screen)
	_chain_run(c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz), h, col, screen)


## A court line: a white strip on the surface.
func _court_line(a: Vector3, b: Vector3, y: float) -> void:
	var lo := Vector3(minf(a.x, b.x), 0, minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), 0, maxf(a.z, b.z))
	_flat_rect("line", lo.x - 0.025, hi.x + 0.025, lo.z - 0.025, hi.z + 0.025, y, LINE)


## A net across x at `c`: two posts and a dark band, `h` at the posts.
func _net(c: Vector3, w: float, h: float, band := 0.9) -> void:
	for sx in [-1.0, 1.0]:
		_box("paint", Vector3(0.08, h, 0.08), c + Vector3(sx * w * 0.5, h * 0.5, 0), Color("#3a3c3e"))
	_box("paint", Vector3(w, band, 0.02), c + Vector3(0, h - band * 0.5, 0), Color("#1d1f22"))
	_box("paint", Vector3(w, 0.06, 0.03), c + Vector3(0, h - 0.03, 0), WHITE)


## Four pickleball courts side by side (the courts' long side back from the
## walk): blue playing surface on a green pad, the kitchen lines, nets and
## a 10 ft chain-link fence round the block (USA Pickleball's layout).
func _pickleball(c: Vector3, size: Vector2) -> void:
	_flat_rect("gravel", c.x - size.x * 0.5 + 0.8, c.x + size.x * 0.5 - 0.8, c.z - size.y * 0.5 + 0.8,
		c.z + size.y * 0.5 - 0.8, 0.06, Color("#3f6f4c"))
	var pad := 9.14
	for i in 4:
		var x: float = c.x + (i - 1.5) * pad
		var cw := 6.1
		var cl := 13.41
		_flat_rect("gravel", x - cw * 0.5 - 0.3, x + cw * 0.5 + 0.3, c.z - cl * 0.5 - 0.3, c.z + cl * 0.5 + 0.3, 0.065, Color("#3d6ea6"))
		for sx in [-1.0, 1.0]:
			_court_line(Vector3(x + sx * cw * 0.5, 0, c.z - cl * 0.5), Vector3(x + sx * cw * 0.5, 0, c.z + cl * 0.5), 0.07)
		for sz in [-1.0, 1.0]:
			_court_line(Vector3(x - cw * 0.5, 0, c.z + sz * cl * 0.5), Vector3(x + cw * 0.5, 0, c.z + sz * cl * 0.5), 0.07)
			# The non-volley zone, 7 ft each side of the net, and the centre line.
			_court_line(Vector3(x - cw * 0.5, 0, c.z + sz * 2.13), Vector3(x + cw * 0.5, 0, c.z + sz * 2.13), 0.07)
			_court_line(Vector3(x, 0, c.z + sz * 2.13), Vector3(x, 0, c.z + sz * cl * 0.5), 0.07)
		_net(Vector3(x, 0, c.z), cw + 0.6, 0.91, 0.75)
	_chain_box(c, size - Vector2(1.6, 1.6), 3.0, Color("#2b2d2f"), 1.2)
	for i in 3:
		_bench(c + Vector3((i - 1) * pad * 1.33, 0, -size.y * 0.5 + 1.6), PI)


## Two tennis courts side by side: green inside the lines on a red-brown
## surround, the full doubles lines, nets, and a 12 ft fence with a green
## windscreen along the bottom (ITF court, 78 x 36 ft, with runoff).
func _tennis(c: Vector3, size: Vector2) -> void:
	_flat_rect("gravel", c.x - size.x * 0.5 + 0.8, c.x + size.x * 0.5 - 0.8, c.z - size.y * 0.5 + 0.8,
		c.z + size.y * 0.5 - 0.8, 0.06, Color("#8a3f36"))
	var half_l := 11.885
	var dbl := 5.485
	var sgl := 4.115
	for i in 2:
		var x: float = c.x + (i - 0.5) * 18.3
		_flat_rect("gravel", x - dbl, x + dbl, c.z - half_l, c.z + half_l, 0.065, Color("#3e7a52"))
		for e in [-dbl, -sgl, sgl, dbl]:
			_court_line(Vector3(x + e, 0, c.z - half_l), Vector3(x + e, 0, c.z + half_l), 0.07)
		for sz in [-1.0, 1.0]:
			_court_line(Vector3(x - dbl, 0, c.z + sz * half_l), Vector3(x + dbl, 0, c.z + sz * half_l), 0.07)
			_court_line(Vector3(x - sgl, 0, c.z + sz * 6.4), Vector3(x + sgl, 0, c.z + sz * 6.4), 0.07)
			_court_line(Vector3(x, 0, c.z), Vector3(x, 0, c.z + sz * 6.4), 0.07)
		_net(Vector3(x, 0, c.z), dbl * 2.0 + 1.8, 1.07, 0.85)
	_chain_box(c, size - Vector2(1.6, 1.6), 3.66, Color("#2b2d2f"), 1.2, 1.8)


## Two sand volleyball courts, front to back: timber-edged sand, blue
## boundary tape, nets on posts at the men's height (FIVB beach court,
## 16 x 8 m inside a 3 m free zone).
func _volleyball(c: Vector3, size: Vector2) -> void:
	for sz in [-1.0, 1.0]:
		var cz: float = c.z + sz * size.y * 0.25
		var w := size.x - 2.0
		var d := size.y * 0.5 - 1.2
		_flat_rect("gravel", c.x - w * 0.5, c.x + w * 0.5, cz - d * 0.5, cz + d * 0.5, 0.06, Color("#d9c79a"))
		for e in [[Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5)], [Vector3(-w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, d * 0.5)]]:
			_box("paint", Vector3(w + 0.3, 0.2, 0.15), Vector3(c.x, 0.1, cz) + (e[0] + e[1]) * 0.5, WOOD)
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.15, 0.2, d), Vector3(c.x + sx * w * 0.5, 0.1, cz), WOOD)
		# The court runs across the lot: 16 m along x, 8 m along z.
		var tape := Color("#2f6fb0")
		for sx in [-8.0, 8.0]:
			_box("paint", Vector3(0.05, 0.02, 8.0), Vector3(c.x + sx, 0.08, cz), tape)
		for zz in [-4.0, 4.0]:
			_box("paint", Vector3(16.0, 0.02, 0.05), Vector3(c.x, 0.08, cz + zz), tape)
		_box("paint", Vector3(0.1, 2.6, 0.1), Vector3(c.x, 1.3, cz - 4.9), Color("#3a3c3e"))
		_box("paint", Vector3(0.1, 2.6, 0.1), Vector3(c.x, 1.3, cz + 4.9), Color("#3a3c3e"))
		_box("paint", Vector3(0.02, 1.0, 9.6), Vector3(c.x, 1.93, cz), Color("#1d1f22"))
		_box("paint", Vector3(0.04, 0.05, 9.6), Vector3(c.x, 2.43, cz), WHITE)


## A dog park: 5 ft black chain link split into a big-dog and a small-dog
## yard, each entered through a double-gated vestibule; worn ground at the
## gates, a few agility pieces, a drinking fountain, benches and a waste
## station (benchmarked on Indiana town dog parks of the 2010s-20s).
func _dog_park(c: Vector3, size: Vector2) -> void:
	var hx := size.x * 0.5 - 0.5
	var hz := size.y * 0.5 - 0.5
	var black := Color("#202224")
	var split: float = c.x + hx * 0.4
	_chain_run(c + Vector3(-hx, 0, hz), c + Vector3(hx, 0, hz), 1.5, black)
	_chain_run(c + Vector3(-hx, 0, -hz), c + Vector3(-hx, 0, hz), 1.5, black)
	_chain_run(c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz), 1.5, black)
	_chain_run(Vector3(split, 0, c.z - hz), Vector3(split, 0, c.z + hz), 1.5, black)
	# The front with a vestibule for each yard.
	for g in [c.x - hx * 0.3, split + (hx - (split - c.x)) * 0.5]:
		_chain_run(Vector3(g - 1.5, 0, c.z - hz - 3.0), Vector3(g + 1.5, 0, c.z - hz - 3.0), 1.5, black)
		_chain_run(Vector3(g - 1.5, 0, c.z - hz - 3.0), Vector3(g - 1.5, 0, c.z - hz), 1.5, black)
		_chain_run(Vector3(g + 1.5, 0, c.z - hz - 3.0), Vector3(g + 1.5, 0, c.z - hz), 1.5, black)
		# Worn dirt where every dog comes in.
		_flat_rect("gravel", g - 3.5, g + 3.5, c.z - hz, c.z - hz + 6.0, 0.05, Color("#8a7458"))
	var front := [c.x - hx, c.x - hx * 0.3 - 1.5, c.x - hx * 0.3 + 1.5, split, split + 0.01,
		split + (hx - (split - c.x)) * 0.5 - 1.5, split + (hx - (split - c.x)) * 0.5 + 1.5, c.x + hx]
	for i in range(0, front.size(), 2):
		_chain_run(Vector3(front[i], 0, c.z - hz), Vector3(front[i + 1], 0, c.z - hz), 1.5, black)
	# Agility: an A-frame, two hurdles and a tunnel in the big yard.
	var a := c + Vector3(-hx * 0.45, 0, hz * 0.3)
	for s in [-1.0, 1.0]:
		_quad("paint", a + Vector3(-0.6, 0.05, s * 1.6), a + Vector3(0.6, 0.05, s * 1.6), a + Vector3(0.6, 1.4, 0),
			a + Vector3(-0.6, 1.4, 0), Color("#d9a21b") if s < 0 else Color("#2f6fb0"), [], Vector3(0, 1, s))
	for k in 2:
		var h := c + Vector3(-hx * 0.1 + k * 3.0, 0, -hz * 0.2)
		for sx in [-0.6, 0.6]:
			_box("paint", Vector3(0.06, 0.7, 0.06), h + Vector3(sx, 0.35, 0), WHITE)
		_box("paint", Vector3(1.2, 0.05, 0.05), h + Vector3(0, 0.5, 0), Color("#c23a3a"))
	_cylinder("paint", c + Vector3(-hx * 0.75, 0.0, -hz * 0.35), 0.35, 0.9, Color("#5a7a9a"), 10)
	_box("paint", Vector3(0.4, 0.9, 0.4), c + Vector3(split - c.x - 1.5, 0.45, hz - 2.0), Color("#3a5a3a"))
	for p in [c + Vector3(-hx * 0.6, 0, hz - 1.5), c + Vector3(hx * 0.7, 0, hz - 1.5)]:
		_bench(p, 0.0)
	_box("paint", Vector3(0.08, 1.4, 0.08), c + Vector3(-hx - 1.2, 0.7, -hz - 1.0), Color("#3a5a3a"))
	_box("paint", Vector3(0.35, 0.45, 0.2), c + Vector3(-hx - 1.2, 1.2, -hz - 1.0), Color("#2f6b3a"))


## A street-style skate park, the kind small Indiana towns pour: a
## concrete pad with two quarter pipes facing each other, a funbox with a
## rail, a ledge and a flat bar (benchmarked on 2010s town skate parks).
func _skate_park(c: Vector3, size: Vector2) -> void:
	var pad := CONCRETE.lightened(0.05)
	_flat_rect("gravel", c.x - size.x * 0.5 + 0.5, c.x + size.x * 0.5 - 0.5, c.z - size.y * 0.5 + 0.5,
		c.z + size.y * 0.5 - 0.5, 0.06, pad)
	for s in [-1.0, 1.0]:
		_quarter_pipe(c + Vector3(s * (size.x * 0.5 - 3.4), 0, 0), -s, 8.0, 1.5)
	# The funbox: a flat top, a slope each end, a handrail down one side.
	var fb := c + Vector3(0, 0, -2.0)
	_box("paint", Vector3(3.0, 0.6, 2.4), fb + Vector3(0, 0.3, 0), pad.darkened(0.04))
	for s in [-1.0, 1.0]:
		var e: float = fb.x + s * 1.5
		var f: float = fb.x + s * 3.8
		_quad("paint", Vector3(e, 0.6, fb.z - 1.2), Vector3(f, 0.07, fb.z - 1.2), Vector3(f, 0.07, fb.z + 1.2),
			Vector3(e, 0.6, fb.z + 1.2), pad.darkened(0.02), [], Vector3(s * 0.25, 1, 0))
		for z in [fb.z - 1.2, fb.z + 1.2]:
			_tri("paint", Vector3(e, 0.6, z), Vector3(f, 0.07, z), Vector3(e, 0.07, z), pad.darkened(0.1), [], Vector3(0, 0, z - fb.z))
	_strut(fb + Vector3(-3.6, 0.45, 1.4), fb + Vector3(-1.4, 0.95, 1.4), 0.05, GALV)
	_strut(fb + Vector3(-1.4, 0.95, 1.4), fb + Vector3(1.4, 0.95, 1.4), 0.05, GALV)
	for x in [-3.4, -1.4, 1.4]:
		_box("paint", Vector3(0.05, 0.95, 0.05), fb + Vector3(x, 0.47, 1.4), GALV)
	# A ledge with steel edging and a flat bar.
	var ld := c + Vector3(-2.0, 0, size.y * 0.5 - 4.0)
	_box("paint", Vector3(6.0, 0.45, 0.9), ld + Vector3(0, 0.225, 0), pad.darkened(0.06))
	_box("paint", Vector3(6.0, 0.04, 0.06), ld + Vector3(0, 0.47, -0.44), GALV)
	var fbar := c + Vector3(3.5, 0, size.y * 0.5 - 6.5)
	_box("paint", Vector3(4.0, 0.05, 0.05), fbar + Vector3(0, 0.35, 0), GALV)
	for x in [-1.8, 1.8]:
		_box("paint", Vector3(0.05, 0.35, 0.05), fbar + Vector3(x, 0.17, 0), GALV)
	for i in 2:
		_bench(c + Vector3(-size.x * 0.25 + i * size.x * 0.5, 0, -size.y * 0.5 - 1.2), PI)


## An enclosed shelter house, the kind park boards rent out: split-face
## block walls, a deep gable roof, a stone chimney for the fireplace,
## restrooms at one end and an open porch with picnic tables at the other
## (benchmarked on Indiana city park shelter houses, 1950s to now).
func _shelter_house(c: Vector3, size: Vector2) -> void:
	var w := size.x - 4.0
	var d := size.y - 6.0
	var hall := w * 0.62
	var wall := Color("#b9a98e")
	var x0: float = c.x - w * 0.5
	_box("paint", Vector3(w + 1.0, 0.25, d + 1.0), c + Vector3(0, 0.125, 0), CONCRETE)
	_box("paint", Vector3(hall, 3.0, d), Vector3(x0 + hall * 0.5, 1.75, c.z), wall)
	_gable_roof(c.x, c.z, 3.25, d, 2.6, w, true, Color("#5a3a2e"), wall)
	# The porch: posts under the same roof, tables on the slab.
	for k in 3:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 3.0, 0.3), Vector3(x0 + hall + 1.0 + k * (w - hall - 1.2) / 2.0, 1.75, c.z + sz * (d * 0.5 - 0.2)), WOOD)
	for k in 2:
		_table(Vector3(x0 + hall + 2.5 + k * 3.2, 0.25, c.z))
	# Windows along the front, double doors, the restroom doors at the end.
	for i in 3:
		_glass(Vector3(x0 + 2.0 + i * (hall - 4.0) / 2.0, 1.9, c.z - d * 0.5 - 0.03), Vector3(-1, 0, 0), 1.6, 1.2, 0.0)
	_box("paint", Vector3(1.8, 2.2, 0.06), Vector3(x0 + hall * 0.5, 1.35, c.z - d * 0.5 - 0.05), Color("#5a3a2e"))
	for sz in [-1.0, 1.0]:
		_box("paint", Vector3(0.06, 2.1, 0.95), Vector3(x0 - 0.05, 1.3, c.z + sz * 1.6), Color("#5a6a74"))
	_box("paint", Vector3(1.4, 7.0, 1.0), Vector3(x0 + 1.2, 3.5, c.z + d * 0.5 + 0.3), Color("#8a7a68"))
	_box("paint", Vector3(1.6, 0.15, 1.2), Vector3(x0 + 1.2, 7.05, c.z + d * 0.5 + 0.3), CONCRETE)
	_park_sign(c + Vector3(w * 0.5 - 1.0, 0, -size.y * 0.5 + 0.6), "SHELTER HOUSE")


## An amphitheatre: a band shell (a raised stage under a curved steel and
## timber shell) facing a lawn ringed by low concrete seat walls, a sound
## booth on the centre aisle (benchmarked on Indiana
## park band shells of the 2000s-20s).
func _amphitheater(c: Vector3, size: Vector2) -> void:
	# The stage at the back (+z), the audience in front of it.
	var stage := c + Vector3(0, 0, size.y * 0.5 - 7.0)
	_box("paint", Vector3(16.0, 1.2, 9.0), stage + Vector3(0, 0.6, 0), CONCRETE)
	_box("paint", Vector3(16.0, 0.1, 9.0), stage + Vector3(0, 1.25, 0), WOOD.lightened(0.15))
	# The shell: ribs bending over the stage, panels between them.
	var segs := 7
	var r := 8.5
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(cos(a0) * r, sin(a0) * r * 0.9 + 1.3, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r * 0.9 + 1.3, 0)
		_quad("metal", stage + p0 + Vector3(0, 0, 4.4), stage + p1 + Vector3(0, 0, 4.4), stage + p1 * Vector3(0.6, 0.85, 1) + Vector3(0, 0.3, -4.6),
			stage + p0 * Vector3(0.6, 0.85, 1) + Vector3(0, 0.3, -4.6), Color("#d8dadb"), [], -(p0 + p1))
		_strut(stage + p0 + Vector3(0, 0, 4.5), stage + p0 * Vector3(0.6, 0.85, 1) + Vector3(0, 0.3, -4.5), 0.2, Color("#5a3e2a"))
	_box("paint", Vector3(17.0, 9.0, 0.3), stage + Vector3(0, 4.5, 4.7), Color("#5a3e2a"))
	# The lawn: arcs of low concrete seat walls, people bring blankets
	# and chairs between them.
	for row in 6:
		var rr := 10.0 + row * 3.6
		var y := 0.06
		var n := 12
		for i in n:
			var a0 := PI + PI * 0.15 + (PI * 0.7) * i / n
			var a1 := PI + PI * 0.15 + (PI * 0.7) * (i + 1) / n
			var q0 := stage + Vector3(cos(a0) * rr, y + 0.45, -sin(a0) * rr * -1.0)
			var q1 := stage + Vector3(cos(a1) * rr, y + 0.45, -sin(a1) * rr * -1.0)
			var mid := (q0 + q1) * 0.5
			if mid.z < c.z - size.y * 0.5 + 2.0:
				continue
			_box("paint", Vector3(q0.distance_to(q1), 0.45, 0.4), mid - Vector3(0, 0.22, 0), CONCRETE,
				Basis(Vector3.UP, atan2(q1.x - q0.x, q1.z - q0.z) - PI * 0.5))
	# The sound booth on the centre aisle.
	var booth := stage + Vector3(0, 0, -26.0)
	if booth.z > c.z - size.y * 0.5 + 2.0:
		_box("siding", Vector3(3.0, 2.6, 2.4), booth + Vector3(0, 1.3, 0), Color("#d8d2c2"))
		_box("paint", Vector3(3.4, 0.2, 2.8), booth + Vector3(0, 2.7, 0), Color("#4a4d52"))
	for sx in [-1.0, 1.0]:
		_cyl_y(stage + Vector3(sx * 11.0, 4.5, -2.0), 0.15, 9.0, GALV)
		_box("paint", Vector3(1.2, 0.8, 0.5), stage + Vector3(sx * 11.0, 9.0, -2.4), Color("#2b2d2f"))


## A veterans memorial plaza: a ring of pavers, a curved black granite
## wall with the names, the three flagpoles (the US flag, Indiana's and
## POW-MIA), a granite centre stone, benches and low clipped hedges.
func _veterans_memorial(c: Vector3, size: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.5
	var ring := []
	for i in 24:
		ring.append(c + Vector3(cos(TAU * i / 24.0) * r, 0, sin(TAU * i / 24.0) * r))
	_flat_poly(ring, 0.065, Color("#b9ad98"))
	var inner := []
	for i in 24:
		inner.append(c + Vector3(cos(TAU * i / 24.0) * r * 0.45, 0, sin(TAU * i / 24.0) * r * 0.45))
	_flat_poly(inner, 0.075, Color("#9a8f80"))
	# The wall: black granite panels on an arc round the back.
	var n := 7
	for i in n:
		var a0 := PI * 0.2 + PI * 0.6 * i / n
		var a1 := PI * 0.2 + PI * 0.6 * (i + 1) / n
		var p0 := c + Vector3(cos(a0) * (r - 1.0), 0, sin(a0) * (r - 1.0))
		var p1 := c + Vector3(cos(a1) * (r - 1.0), 0, sin(a1) * (r - 1.0))
		_box("paint", Vector3(p0.distance_to(p1) - 0.05, 1.8, 0.3), (p0 + p1) * 0.5 + Vector3(0, 0.9, 0), Color("#1c1d1f"),
			Basis(Vector3.UP, atan2(p1.x - p0.x, p1.z - p0.z) - PI * 0.5))
	# The centre stone and the three flags.
	_box("paint", Vector3(1.2, 1.5, 0.5), c + Vector3(0, 0.75, 0), Color("#4a4c50"))
	_box("paint", Vector3(1.6, 0.2, 0.8), c + Vector3(0, 0.1, 0), Color("#6a6c70"))
	for k in 3:
		var fp := c + Vector3(-2.5 + k * 2.5, 0, -r * 0.55)
		var h := 9.0 if k == 1 else 7.5
		_cyl_y(fp + Vector3(0, h * 0.5, 0), 0.07, h, Color("#d8dadb"))
		_box("paint", Vector3(1.5, 0.95, 0.02), fp + Vector3(0.8, h - 0.6, 0),
			[Color("#1f3a6e"), Color("#b22234"), Color("#202022")][k])
	for i in 4:
		var a := PI * 1.25 + PI * 0.5 * i / 3.0
		_bench(c + Vector3(cos(a) * (r - 1.6), 0, sin(a) * (r - 1.6)), -a + PI * 0.5)
	# Clipped boxwood round the outside.
	for i in 18:
		var a := TAU * i / 18.0
		if a > PI * 0.15 and a < PI * 0.85:
			continue
		if absf(a - PI * 1.5) < 0.25:
			continue  # the way in from the walk
		_box("foliage", Vector3(1.4, 0.7, 0.9), c + Vector3(cos(a) * (r + 0.3), 0.35, sin(a) * (r + 0.3)),
			Color(0.2, 0.36, 0.17, 0.3), Basis(Vector3.UP, -a))


## A community garden: rows of cedar raised beds on wood chips, each
## planted differently, a deer fence of black mesh round it, a tool shed,
## a rain barrel and a pair of compost bins.
func _community_garden(c: Vector3, size: Vector2) -> void:
	var hx := size.x * 0.5 - 1.0
	var hz := size.y * 0.5 - 1.0
	_flat_rect("gravel", c.x - hx, c.x + hx, c.z - hz, c.z + hz, 0.055, Color("#6a5038"))
	var crops := [Color("#4f7a33"), Color("#6a8a3a"), Color("#3d6a2f"), Color("#7a8a42"), Color("#8a6a3a"), Color("#5a7a2e")]
	var cedar := Color("#9a6a44")
	var rows := 4
	var cols := 5
	for i in cols:
		for j in rows:
			var p := c + Vector3(-hx + 3.4 + i * (2 * hx - 9.0) / (cols - 1), 0, -hz + 2.6 + j * (2 * hz - 5.2) / (rows - 1))
			_box("paint", Vector3(1.2, 0.4, 3.0), p + Vector3(0, 0.2, 0), cedar)
			_box("foliage", Vector3(1.0, 0.45, 2.8), p + Vector3(0, 0.55, 0), Color(crops[(i * 3 + j) % crops.size()], 0.3))
	# Shed, barrel and bins along the right end.
	var shed := c + Vector3(hx - 2.0, 0, hz - 2.4)
	_box("siding", Vector3(2.4, 2.2, 2.4), shed + Vector3(0, 1.1, 0), Color("#8a3a2e"))
	_gable_roof(shed.x, shed.z, 2.2, 2.4, 0.8, 2.4, false, Color("#4a4d52"), Color("#8a3a2e"))
	_cylinder("paint", c + Vector3(hx - 0.8, 0, hz - 5.0), 0.35, 0.9, Color("#2f4a6e"), 10)
	for k in 2:
		_box("paint", Vector3(1.1, 0.9, 1.1), c + Vector3(hx - 1.2, 0.45, -hz + 1.4 + k * 1.3), WOOD)
	var black := Color("#202224")
	_chain_run(c + Vector3(-hx, 0, -hz), c + Vector3(-1.2, 0, -hz), 2.4, black)
	_chain_run(c + Vector3(1.2, 0, -hz), c + Vector3(hx, 0, -hz), 2.4, black)
	_chain_run(c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz), 2.4, black)
	_chain_run(c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz), 2.4, black)
	_chain_run(c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz), 2.4, black)


## A nine-hole disc golf course threaded round the park's edges: a
## concrete tee pad and a tee sign at each hole, and a chain basket on a
## pole out where the disc should land, the holes kept clear of everything
## else in the park (a PDGA-style short course).
func _disc_golf(size: Vector2, spots: Array) -> void:
	var hx := size.x * 0.5 - 6.0
	var hz := size.y * 0.5 - 6.0
	var loop := [Vector3(-hx, 0, -hz * 0.4), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz * 0.4)]
	var total := 0.0
	for i in 3:
		total += loop[i].distance_to(loop[i + 1])
	var holes := 9
	var step := total / holes
	var at := func(t: float) -> Vector3:
		var left := t
		for i in 3:
			var l: float = loop[i].distance_to(loop[i + 1])
			if left <= l:
				return loop[i].lerp(loop[i + 1], left / l)
			left -= l
		return loop[3]
	for h in holes:
		var tee: Vector3 = at.call(h * step + 1.0)
		var pin: Vector3 = at.call(h * step + step * 0.8)
		pin += Vector3(0, 0, -4.0 if pin.z > 0.0 else 0.0) + Vector3(-4.0 if pin.x > 0.0 else 4.0, 0, 0) * 0.5
		if _in_spots(tee, spots, 2.0) or _in_spots(pin, spots, 2.0):
			continue
		var dir := (pin - tee).normalized()
		_box("paint", Vector3(1.5, 0.12, 3.0), tee + dir * 1.5 + Vector3(0, 0.06, 0), CONCRETE,
			Basis(Vector3.UP, atan2(dir.x, dir.z)))
		_box("paint", Vector3(0.08, 1.1, 0.08), tee + Vector3(dir.z, 0, -dir.x) * 1.4 + Vector3(0, 0.55, 0), GALV)
		_box("paint", Vector3(0.6, 0.45, 0.04), tee + Vector3(dir.z, 0, -dir.x) * 1.4 + Vector3(0, 1.2, 0), Color("#2f5a3a"),
			Basis(Vector3.UP, atan2(dir.x, dir.z)))
		# The basket: a pole, a yellow chain-holder band, the chains, the tray.
		_cyl_y(pin + Vector3(0, 0.7, 0), 0.03, 1.4, GALV)
		_cylinder("paint", pin + Vector3(0, 1.2, 0), 0.32, 0.08, Color("#e8c23a"), 10)
		_cylinder("chain", pin + Vector3(0, 0.75, 0), 0.26, 0.45, GALV, 10)
		_cylinder("paint", pin + Vector3(0, 0.55, 0), 0.32, 0.2, GALV.darkened(0.1), 10)


## A quarter pipe `w` wide with a radius of `r`, rising toward `face`
## (+1: rising toward +x) from `c`, with a deck and steel coping.
func _quarter_pipe(c: Vector3, face: float, w: float, r: float) -> void:
	var col := CONCRETE.lightened(0.02)
	var segs := 7
	var deck := 1.4
	for i in segs:
		var a0 := (PI * 0.5) * i / segs
		var a1 := (PI * 0.5) * (i + 1) / segs
		var x0: float = c.x + face * (r * sin(a0) - r)
		var x1: float = c.x + face * (r * sin(a1) - r)
		var y0 := r - r * cos(a0) + 0.06
		var y1 := r - r * cos(a1) + 0.06
		_quad("paint", Vector3(x0, y0, c.z - w * 0.5), Vector3(x1, y1, c.z - w * 0.5), Vector3(x1, y1, c.z + w * 0.5),
			Vector3(x0, y0, c.z + w * 0.5), col, [], Vector3(-face * sin(a0 + 0.1), cos(a0 + 0.1), 0))
		for z in [c.z - w * 0.5, c.z + w * 0.5]:
			_quad("paint", Vector3(x0, 0.06, z), Vector3(x1, 0.06, z), Vector3(x1, y1, z), Vector3(x0, y0, z), col.darkened(0.1),
				[], Vector3(0, 0, z - c.z))
	_box("paint", Vector3(deck, r, w), c + Vector3(face * deck * 0.5, r * 0.5 + 0.06, 0), col.darkened(0.05))
	_box("paint", Vector3(0.08, 0.08, w), c + Vector3(0, r + 0.1, 0), GALV)
	_chain_run(c + Vector3(face * deck, r + 0.06, -w * 0.5), c + Vector3(face * deck, r + 0.06, w * 0.5), 1.0, GALV)


## A splash pad: coloured rubber surfacing with spray posts and a dumping
## bucket, the standard small-town install of the 2010s.
func _splash_pad(c: Vector3, size: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.5 - 0.5
	_cylinder("paint", c, r + 0.6, 0.06, CONCRETE, 24)
	_cylinder("paint", c + Vector3(0, 0.01, 0), r, 0.07, Color("#3f8fb0"), 24)
	_cylinder("paint", c + Vector3(0, 0.02, 0), r * 0.45, 0.07, Color("#e0b23a"), 20)
	var cols := [Color("#d24a3a"), Color("#2f7ac0"), Color("#e8c23a"), Color("#4aa86a")]
	for i in 6:
		var a := TAU * i / 6.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r * 0.7
		_cyl_y(p + Vector3(0, 0.9, 0), 0.12, 1.8, cols[i % cols.size()])
		_cylinder("paint", p + Vector3(0, 1.8, 0), 0.35, 0.15, cols[(i + 1) % cols.size()], 10)
	# The tipping bucket on its arch.
	_cyl_y(c + Vector3(-1.2, 1.6, 0), 0.15, 3.2, cols[1])
	_cyl_y(c + Vector3(1.2, 1.6, 0), 0.15, 3.2, cols[1])
	_box("paint", Vector3(2.6, 0.2, 0.2), c + Vector3(0, 3.2, 0), cols[1])
	_cylinder("paint", c + Vector3(0, 2.4, 0), 0.55, 0.7, cols[2], 12)
	_bench(c + Vector3(r + 2.0, 0, 0), PI * 0.5)
	_bench(c + Vector3(-r - 2.0, 0, 0), -PI * 0.5)


## An inclusive playground on poured rubber: ramps up to the decks, wide
## slides, a group swing and shade sails.
func _all_abilities(c: Vector3, size: Vector2) -> void:
	_flat_rect("asphalt", c.x - size.x * 0.5, c.x + size.x * 0.5, c.z - size.y * 0.5, c.z + size.y * 0.5, 0.055)
	_flat_rect("line", c.x - size.x * 0.5 + 0.8, c.x + size.x * 0.5 - 0.8, c.z - size.y * 0.5 + 0.8,
		c.z + size.y * 0.5 - 0.8, 0.06, Color("#3d7a6a"))
	_flat_rect("line", c.x - 4.0, c.x + 4.0, c.z - 3.0, c.z + 3.0, 0.065, Color("#c27a3a"))
	var green := Color("#4f9a4a")
	var tan := Color("#d9c08a")
	# Two decks joined by a ramp, with a roof over the high one.
	_box("paint", Vector3(4.0, 0.15, 4.0), c + Vector3(-7.0, 1.0, -2.0), tan)
	_box("paint", Vector3(4.0, 0.15, 4.0), c + Vector3(-1.0, 1.8, -2.0), tan)
	_box("paint", Vector3(2.0, 0.12, 6.0), c + Vector3(-7.0, 0.5, 3.0), tan, Basis(Vector3.RIGHT, 0.17))
	_box("paint", Vector3(2.0, 0.12, 2.2), c + Vector3(-4.0, 1.4, -2.0), tan, Basis(Vector3.BACK, -0.25))
	for d in [Vector3(-7.0, 0, -2.0), Vector3(-1.0, 0, -2.0)]:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_cyl_y(c + d + Vector3(sx * 1.9, 1.3, sz * 1.9), 0.09, 2.6, green)
	_box("paint", Vector3(4.4, 0.15, 4.4), c + Vector3(-1.0, 3.6, -2.0), green)
	_box("paint", Vector3(1.4, 0.08, 4.5), c + Vector3(-1.0, 0.95, 2.0), Color("#e8c23a"), Basis(Vector3.RIGHT, -0.35))
	# A group (basket) swing and a spinner.
	var sw := c + Vector3(7.0, 0, -1.0)
	_box("paint", Vector3(5.0, 0.12, 0.12), sw + Vector3(0, 2.6, 0), DARK)
	for sx in [-1.0, 1.0]:
		_box("paint", Vector3(0.1, 2.7, 0.1), sw + Vector3(sx * 2.4, 1.3, 0), DARK)
	_cylinder("paint", sw + Vector3(0, 0.55, 0), 0.6, 0.12, Color("#c23a3a"), 14)
	_cylinder("paint", c + Vector3(6.0, 0.06, 6.0), 1.4, 0.2, Color("#2f7ac0"), 16)
	# Shade sails on tall posts.
	for i in 3:
		var p := c + Vector3(-size.x * 0.3 + i * size.x * 0.3, 0, size.y * 0.5 - 2.0)
		_cyl_y(p + Vector3(0, 2.4, 0), 0.08, 4.8, GALV)
	_quad("paint", c + Vector3(-size.x * 0.3, 4.6, size.y * 0.5 - 2.0), c + Vector3(size.x * 0.3, 4.6, size.y * 0.5 - 2.0),
		c + Vector3(size.x * 0.2, 3.8, size.y * 0.5 - 8.0), c + Vector3(-size.x * 0.2, 3.8, size.y * 0.5 - 8.0), Color("#e8e2d0"))
	_bench(c + Vector3(size.x * 0.5 + 1.5, 0, 0), PI * 0.5)


## Four Little League diamonds back to back round a central concession
## stand, the usual layout of a county youth sports complex.
func _youth_complex(c: Vector3, size: Vector2, lights: bool) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# Home plates face the middle, so the outfields fan out to the corners.
			var home := c + Vector3(sx * 9.0, 0, sz * 9.0)
			_diamond_facing(home, Vector3(sx, 0, sz).normalized(), lights)
	_flat_rect("drive", c.x - 6.0, c.x + 6.0, c.z - 6.0, c.z + 6.0, 0.05)
	_box("paint", Vector3(6.0, 3.0, 5.0), c + Vector3(0, 1.5, 0), Color("#a8462e"))
	_hip_roof(c.x, c.z, 3.0, 6.6, 5.6, 1.0, Color("#3e4448"))
	_flagpole(c + Vector3(4.5, 0, 4.5))


## A Little League diamond with its home plate at `home`, the field running
## out along `out`: the infield, a backstop, a fence 46 m out, dugout
## benches and (when lit) four light poles.
func _diamond_facing(home: Vector3, out: Vector3, lights: bool) -> void:
	var yaw := atan2(out.x, out.z)
	var b := Basis(Vector3.UP, yaw)
	# A skinned infield: a fan of dirt from home plate out past the bases
	# (18.3 m apart), with white bases and a mound.
	var pts := [home]
	for i in 9:
		var a := lerpf(-PI * 0.25, PI * 0.25, i / 8.0)
		pts.append(home + b * Vector3(sin(a), 0, cos(a)) * 25.0)
	_flat_poly(pts, 0.05, DIRT)
	for v in [Vector3(12.9, 0, 12.9), Vector3(0, 0, 25.9), Vector3(-12.9, 0, 12.9)]:
		_box("paint", Vector3(0.4, 0.08, 0.4), home + b * v + Vector3(0, 0.06, 0), WHITE)
	for sx in [-1.0, 1.0]:
		_strut(home + Vector3(0, 0.07, 0), home + b * Vector3(sx * 30.0, 0.07, 30.0), 0.05, WHITE)
	_cylinder("paint", home + b * Vector3(0, 0, 14.0), 2.6, 0.08, DIRT.darkened(0.08), 12)
	# Backstop behind the plate.
	for i in 5:
		var a := lerpf(-0.8, 0.8, i / 4.0)
		var p := home + b * Vector3(sin(a) * 6.0, 0, -cos(a) * 6.0)
		_box("paint", Vector3(0.08, 4.0, 0.08), p + Vector3(0, 2.0, 0), GALV)
	_strut(home + b * Vector3(-4.3, 4.0, -4.2), home + b * Vector3(4.3, 4.0, -4.2), 0.05, GALV)
	var prev := Vector3.ZERO
	for i in 11:
		var a := lerpf(-PI * 0.25, PI * 0.25, i / 10.0)
		var p := home + b * Vector3(sin(a), 0, cos(a)) * 46.0
		_box("paint", Vector3(0.08, 1.8, 0.08), p + Vector3(0, 0.9, 0), GALV)
		if i > 0:
			_strut(prev + Vector3(0, 1.8, 0), p + Vector3(0, 1.8, 0), 0.05, GALV)
		prev = p
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(5.0, 0.45, 0.5), home + b * Vector3(s * 9.0, 0.22, 1.0), ALUMINUM, b * Basis(Vector3.UP, s * 0.8))
	if lights:
		_field_lights(home, out)


## Four galvanized light poles round a diamond, 20 m tall with a head of
## floodlights each.
func _field_lights(home: Vector3, out := Vector3(0, 0, -1)) -> void:
	var b := Basis(Vector3.UP, atan2(out.x, out.z))
	for v in [Vector3(-8.0, 0, 2.0), Vector3(8.0, 0, 2.0), Vector3(-26.0, 0, 34.0), Vector3(26.0, 0, 34.0)]:
		var p: Vector3 = home + b * v
		_cyl_y(p + Vector3(0, 10.0, 0), 0.2, 20.0, GALV)
		_box("paint", Vector3(2.4, 1.2, 0.3), p + Vector3(0, 20.2, 0), GALV.darkened(0.2), b)


## Concessions and restrooms with a paved lot, for tournament weekends.
func _concessions(c: Vector3, size: Vector2) -> void:
	_flat_rect("asphalt", c.x - size.x * 0.5, c.x + size.x * 0.5, c.z - size.y * 0.5, c.z + size.y * 0.5 - 10.0, 0.05)
	var x := c.x - size.x * 0.5 + 3.0
	while x < c.x + size.x * 0.5 - 2.0:
		_flat_rect("line", x - 0.06, x + 0.06, c.z - size.y * 0.5 + 1.0, c.z - size.y * 0.5 + 6.5, 0.055, LINE)
		_flat_rect("line", x - 0.06, x + 0.06, c.z + size.y * 0.5 - 16.5, c.z + size.y * 0.5 - 11.0, 0.055, LINE)
		x += 2.8
	var hc := c + Vector3(0, 0, size.y * 0.5 - 5.0)
	_box("paint", Vector3(14.0, 3.2, 7.0), hc + Vector3(0, 1.6, 0), Color("#b8ad98"))
	_hip_roof(hc.x, hc.z, 3.2, 14.6, 7.6, 1.2, Color("#2f4a5a"))
	_box("paint", Vector3(4.0, 1.0, 0.1), hc + Vector3(-3.0, 1.6, -3.55), Color("#3a3a36"))
	for i in 3:
		_table(hc + Vector3(-5.0 + i * 5.0, 0, -6.0))


## An octagonal bandstand on a raised deck, white with a shingled roof, as on
## so many Midwestern town squares.
func _bandstand(c: Vector3, size: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.0
	_cylinder("paint", c, r + 0.4, 0.9, Color("#8a8a84") if tier < 2 else Color("#a89a84"), 8)
	_cylinder("paint", c + Vector3(0, 0.9, 0), r + 0.2, 0.12, WOOD.lightened(0.2), 8)
	var white := WHITE if tier >= 1 else WHITE.darkened(0.15)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		_cyl_y(p + Vector3(0, 2.4, 0), 0.12, 3.0, white)
		var a2 := TAU * (i + 1.5) / 8.0
		var q := c + Vector3(cos(a2), 0, sin(a2)) * r
		if i != 6:  # the steps side stays open
			_strut(p + Vector3(0, 1.8, 0), q + Vector3(0, 1.8, 0), 0.06, white)
	_lathe(c + Vector3(0, 3.9, 0), [Vector2(r + 0.8, 0.0), Vector2(r * 0.3, 1.6), Vector2(0.2, 2.1), Vector2(0.0, 2.3)], Color("#4a4d52"), 8)
	_box("paint", Vector3(2.4, 0.9, 1.6), c + Vector3(0, 0.45, -r - 0.8), CONCRETE)
	for i in 3:
		_bench(c + Vector3(-4.0 + i * 4.0, 0, -r - 5.0), 0.0)


## A dug fishing pond with a grassy bank, a gravel edge and a small dock.
func _pond(c: Vector3, size: Vector2) -> void:
	var pts := []
	var water := []
	for i in 20:
		var a := TAU * i / 20.0
		var k := 0.9 + 0.1 * sin(a * 3.0 + rng.randf())
		pts.append(c + Vector3(cos(a) * size.x * 0.5 * k, 0, sin(a) * size.y * 0.5 * k))
		water.append(c + Vector3(cos(a) * (size.x * 0.5 * k - 2.0), 0, sin(a) * (size.y * 0.5 * k - 2.0)))
	_flat_poly(pts, 0.05, Color("#8a7a5a"))
	_flat_poly(water, 0.07, Color("#3e5a52") if tier >= 1 else Color("#4f5a3e"))
	var dock := c + Vector3(0, 0, -size.y * 0.5 + 3.0)
	_box("paint", Vector3(1.8, 0.15, 6.0), dock + Vector3(0, 0.45, 1.5), WOOD.lightened(0.15))
	for sx in [-1.0, 1.0]:
		_cyl_y(dock + Vector3(sx * 0.8, 0.25, 4.0), 0.08, 0.6, WOOD)
	for i in 5:
		var a := rng.randf() * TAU
		_shrub(c + Vector3(cos(a) * size.x * 0.5, 0, sin(a) * size.y * 0.5), rng.randf_range(0.5, 0.9))
	_bench(dock + Vector3(4.0, 0, -1.5), 0.0)


## A town pool: a rectangle of blue with lane lines, a white deck, a diving
## board, a guard chair, a bathhouse and a chain-link fence. The aquatic
## center adds a zero-depth entry pool and a pair of slides off a tower.
func _pool(c: Vector3, size: Vector2, big: bool) -> void:
	var hx := size.x * 0.5 - 1.0
	var hz := size.y * 0.5 - 1.0
	var pw := 25.0 if not big else 50.0
	var pd := 15.0 if not big else 21.0
	var pc := c + Vector3(-hx + pw * 0.5 + (7.0 if big else 3.0), 0, hz - pd * 0.5 - 3.0)
	# A concrete deck round the pools; the rest is lawn for towels.
	_flat_rect("drive", c.x - hx, pc.x + pw * 0.5 + 4.0, pc.z - pd * 0.5 - 5.0, c.z + hz, 0.05)
	if big:
		_flat_rect("drive", c.x + hx - 20.0, c.x + hx, c.z + hz - 19.0, c.z + hz, 0.05)
	_flat_rect("drive", c.x + hx - 14.0, c.x + hx, c.z - hz, c.z - hz + 10.0, 0.05)
	_box("paint", Vector3(pw, 0.1, pd), pc + Vector3(0, 0.06, 0), Color("#4fa8c8"))
	var lanes := int(pd / 2.5)
	for i in range(1, lanes):
		_box("paint", Vector3(pw - 2.0, 0.02, 0.15), pc + Vector3(0, 0.12, -pd * 0.5 + i * pd / lanes), Color("#2a4a8a"))
	_box("paint", Vector3(0.5, 0.15, 3.5), pc + Vector3(pw * 0.5 - 1.0, 0.8, 0.0), WHITE)
	_cyl_y(pc + Vector3(-pw * 0.5 - 1.0, 1.0, 0), 0.08, 2.0, WHITE)
	_box("paint", Vector3(0.7, 0.1, 0.7), pc + Vector3(-pw * 0.5 - 1.0, 2.0, 0), WHITE)
	# Bathhouse by the entrance.
	var bh := c + Vector3(hx - 7.0, 0, -hz + 4.5)
	_box("paint", Vector3(12.0, 3.4, 7.0), bh + Vector3(0, 1.7, 0), Color("#c9bfa8"))
	_hip_roof(bh.x, bh.z, 3.4, 12.6, 7.6, 1.1, Color("#2f5a6a"))
	if big:
		# Zero-depth play pool with a mushroom fountain, and a slide tower.
		var zp := c + Vector3(hx - 10.0, 0, hz - 9.0)
		_cylinder("paint", zp, 7.0, 0.1, Color("#6cc0d8"), 20)
		_cyl_y(zp + Vector3(0, 1.2, 0), 0.2, 2.4, Color("#e8c23a"))
		_cylinder("paint", zp + Vector3(0, 2.4, 0), 1.6, 0.2, Color("#d24a3a"), 14)
		# The tower stands on the deck at the deep end; the flumes land in the pool.
		var t := pc + Vector3(-pw * 0.5 - 3.5, 0, pd * 0.5 - 2.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_cyl_y(t + Vector3(sx * 1.6, 5.0, sz * 1.6), 0.15, 10.0, GALV)
		_box("paint", Vector3(3.6, 0.2, 3.6), t + Vector3(0, 10.0, 0), Color("#2f7ac0"))
		_box("paint", Vector3(3.8, 1.0, 3.8), t + Vector3(0, 10.6, 0), Color("#2f7ac0"))
		# Two flume slides spiralling down to the pool.
		for k in 2:
			var col: Color = [Color("#e8c23a"), Color("#d24a3a")][k]
			var prev := t + Vector3(0, 10.0, 0)
			for i in range(1, 13):
				var a := i * 0.55 + k * PI
				var p := t + Vector3(cos(a) * 3.0 + i * 0.6, 10.0 - i * 0.78, sin(a) * 3.0 - i * 0.25)
				_strut(prev, p, 0.55, col)
				prev = p
	for i in 6:
		_lounge(pc + Vector3(-pw * 0.5 + 2.0 + i * 3.0, 0, -pd * 0.5 - 2.0))
	_box("paint", Vector3(0.8, 0.1, 0.8), pc + Vector3(0, 2.0, -pd * 0.5 - 1.2), WHITE)
	_cyl_y(pc + Vector3(0, 1.0, -pd * 0.5 - 1.2), 0.06, 2.0, WHITE)
	_fence(Vector2(c.x - hx, c.z - hz), Vector2(c.x + hx, c.z + hz), 1.8)


func _lounge(p: Vector3) -> void:
	_box("paint", Vector3(0.7, 0.08, 1.9), p + Vector3(0, 0.35, 0), WHITE)
	_box("paint", Vector3(0.7, 0.08, 0.7), p + Vector3(0, 0.6, 0.85), WHITE, Basis(Vector3.RIGHT, -0.7))


## A dirt trail winding round the back of the park under extra trees.
func _nature_trail(size: Vector2, spots: Array) -> void:
	var hx := size.x * 0.5 - 3.0
	var hz := size.y * 0.5 - 2.5
	var prev := Vector3(-hx, 0, hz * 0.2)
	var n := maxi(8, int(size.x / 6.0))
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := Vector3(lerpf(-hx, hx, t), 0, hz - 1.5 + sin(t * 9.0) * 1.2)
		_strip(prev, p, 1.2, "gravel", Color("#7a6248"))
		prev = p
		if i % 2 == 0 and not _in_spots(p, spots, 3.0):
			var pick := TreeField.pick(rng)
			trees.append([p + Vector3(rng.randf_range(-2.5, 2.5), 0, -3.5), pick[0], pick[1], rng.randf_range(0.9, 1.25)])
	_strip(Vector3(-hx, 0, hz * 0.2), Vector3(-hx, 0, hz - 1.5), 1.2, "gravel", Color("#7a6248"))
	var sign := Vector3(-hx + 1.0, 0, hz * 0.2)
	_box("paint", Vector3(0.15, 1.3, 0.15), sign + Vector3(0, 0.65, 0), WOOD)
	_box("paint", Vector3(0.9, 0.5, 0.08), sign + Vector3(0, 1.1, 0), Color("#5a3e2a"))


# ---------------------------------------------------------------- tourism

## A county fairgrounds, benchmarked against Indiana county fairs: a
## gravel lot and an entrance arch at the road, a steel exhibit building,
## long open-sided livestock barns, a covered grandstand facing a dirt
## arena or a half-mile harness track, and open ground where the midway
## sets up for fair week.
func _fairgrounds(size: Vector2, to_curb: float, name: String, built: Array, on: bool) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_lawn_rect(-hx, hx, -hz, hz, Color("#6a8a40"), 0.35)
	var gravel := Color("#b5ad9c")
	# The way in: a gravel drive, an arch with the fair's name, the lot.
	_flat_rect("gravel", -4.0, 4.0, -hz - to_curb, -hz + 30.0, 0.05, gravel)
	for sx in [-1.0, 1.0]:
		_box("paint", Vector3(0.6, 6.0, 0.6), Vector3(sx * 5.5, 3.0, -hz + 6.0), WHITE)
	_box("paint", Vector3(12.0, 1.4, 0.3), Vector3(0, 6.2, -hz + 6.0), Color("#2f5a3a"))
	labels.append({"pos": Vector3(0, 6.2, -hz + 5.8), "normal": Vector3(0, 0, -1), "text": name.to_upper(),
		"height": 0.7, "color": Color("#f2ecd8")})
	_flat_rect("gravel", -hx + 4.0, -14.0, -hz + 4.0, -hz + 50.0, 0.05, gravel)
	if on:
		# Fair week: the lot fills with cars and pickups.
		var x := -hx + 7.0
		while x < -18.0:
			for row in 4:
				if rng.randf() < 0.85:
					var col: Color = [Color("#8a1f1f"), Color("#e8e6df"), Color("#2f3d55"), Color("#4a4d52"),
						Color("#6a6e30"), Color("#b0b4b6")][rng.randi() % 6]
					_box("paint", Vector3(1.9, 1.5, 4.8), Vector3(x, 0.75, -hz + 10.0 + row * 10.0), col)
			x += 2.8
	_fence(Vector2(-hx + 1.0, -hz + 1.0), Vector2(hx - 1.0, hz - 1.0), 1.5)
	# The exhibit building: a steel hall with a gable roof.
	var ex := Vector3(40.0, 0, -hz + 32.0)
	_box("metal", Vector3(40.0, 5.0, 18.0), ex + Vector3(0, 2.5, 0), Color("#c9ccc8"))
	_gable_roof(ex.x, ex.z, 5.0, 18.0, 2.4, 40.0, true, Color("#8a2a24"), Color("#c9ccc8"))
	_overhead_door(ex.x - 8.0, ex.z - 9.0, 4.0, 3.6, Color("#e2e0d8"))
	# Livestock barns: long, low, open-sided pole barns.
	var barns := 5 if "show_barns" in built else 2
	for i in barns:
		var bz := -20.0 + i * 18.0
		_barn_shed(Vector3(-hx + 40.0, 0, bz), 52.0, 12.0)
	if "show_barns" in built:
		_box("paint", Vector3(10.0, 0.2, 6.0), Vector3(-hx + 80.0, 0.1, -20.0), CONCRETE)  # wash rack
	if "expo_hall" in built:
		var eh := Vector3(-30.0, 0, hz - 26.0)
		_box("metal", Vector3(60.0, 8.0, 30.0), eh + Vector3(0, 4.0, 0), Color("#d8d6cc"))
		_gable_roof(eh.x, eh.z, 8.0, 30.0, 3.0, 60.0, true, Color("#3f4a52"), Color("#d8d6cc"))
		_overhead_door(eh.x, eh.z - 15.0, 6.0, 5.0, Color("#e8e6df"))
	# The grandstand faces a track or a dirt arena.
	var arena := Vector3(55.0, 0, 30.0)
	if "harness" in built:
		# An oval of packed clay with a white rail, the infield in grass.
		_oval(arena, 150.0, 70.0, 12.0, Color("#a07a54"))
		_oval(arena, 124.0, 44.0, 0.6, WHITE, 0.07)
	else:
		_flat_rect("gravel", arena.x - 35.0, arena.x + 35.0, arena.z - 18.0, arena.z + 14.0, 0.05, Color("#9a7a58"))
	if "derby" in built:
		# Concrete barriers round the pit.
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.6, 0.8, 30.0), arena + Vector3(sx * 22.0, 0.4, -2.0), CONCRETE)
		_box("paint", Vector3(44.0, 0.8, 0.6), arena + Vector3(0, 0.4, -17.0), CONCRETE)
		if on:
			for i in 6:
				_box("paint", Vector3(2.0, 1.4, 5.0), arena + Vector3(-15.0 + i * 6.0, 0.7, -6.0 + (i % 2) * 6.0),
					[Color("#c23a3a"), Color("#e8c23a"), Color("#2f7ac0"), Color("#4aa86a")][i % 4], Basis(Vector3.UP, i * 0.7))
	var gs := arena + Vector3(0, 0, 26.0 if "harness" not in built else 44.0)
	var long := 70.0 if "grandstand" in built else 30.0
	_bleachers(gs, long, 12 if "grandstand" in built else 6, true)
	if "grandstand" in built:
		# A steel roof over the seats on posts at the back.
		for i in 6:
			_box("paint", Vector3(0.3, 9.0, 0.3), gs + Vector3(-long * 0.5 + i * long / 5.0, 4.5, 9.5), GALV)
		_box("metal", Vector3(long + 2.0, 0.3, 11.0), gs + Vector3(0, 9.2, 5.0), Color("#8a8f94"),
			Basis(Vector3.RIGHT, -0.08))
	# The midway: open gravel ground, with the carnival only in fair week.
	var mid := Vector3(-20.0, 0, 10.0)
	_flat_rect("gravel", mid.x - 30.0, mid.x + 30.0, mid.z - 25.0, mid.z + 25.0, 0.05, gravel)
	if "midway" in built:
		# The carnival's contract brings permanent power to the midway:
		# rows of service pedestals the rides plug into all fair week.
		for i in 4:
			for j in 3:
				var q := mid + Vector3(-22.5 + i * 15.0, 0, -12.0 + j * 12.0)
				_box("paint", Vector3(0.5, 1.2, 0.4), q + Vector3(0, 0.6, 0), Color("#8d918f"))
				_box("paint", Vector3(0.6, 0.1, 0.5), q + Vector3(0, 1.25, 0), Color("#5a5e60"))
	if on and "midway" in built:
		_ferris_wheel(mid + Vector3(-14.0, 0, 8.0))
		_ride(mid + Vector3(10.0, 0, 10.0))
		for i in 6:
			# Food stands: white trailers with coloured awnings.
			var p := mid + Vector3(-24.0 + i * 9.0, 0, -18.0)
			_box("paint", Vector3(6.0, 2.8, 2.6), p + Vector3(0, 1.6, 0), WHITE)
			_box("paint", Vector3(6.4, 0.1, 1.6), p + Vector3(0, 2.7, -1.9), [Color("#c23a3a"), Color("#e8c23a"),
				Color("#2f7ac0")][i % 3], Basis(Vector3.RIGHT, 0.25))
	_fair_life(hx, hz, built)


## What every Indiana 4-H fairground has beyond the big buildings: gravel
## lanes lit by floodlights on wood poles, a covered show arena with a
## pipe-rail ring, an enclosed poultry and rabbit barn, the 4-H food stand,
## a block restroom house, and old shade trees along the lanes.
func _fair_life(hx: float, hz: float, built: Array) -> void:
	var gravel := Color("#aaa292")
	var lanes := [[Vector3(0, 0, -55.0), Vector3(0, 0, -38.0)], [Vector3(-54.0, 0, -38.0), Vector3(64.0, 0, -38.0)],
		[Vector3(14.0, 0, -38.0), Vector3(14.0, 0, 50.0)]]
	for l in lanes:
		_strip(l[0], l[1], 6.0, "gravel", gravel, 0.048)
	# Floodlights on wood poles along the lanes, 30 m apart.
	for l in lanes:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var side := Vector3(dir.z, 0, -dir.x) * 4.2
		var n := int(len / 30.0)
		for k in n + 1:
			var p := a + dir * (len * (k + 0.5) / (n + 1)) + side
			_cyl_y(p + Vector3(0, 4.5, 0), 0.13, 9.0, POLE)
			_box("paint", Vector3(0.12, 0.12, 1.4), p + Vector3(0, 8.6, 0), POLE, Basis(Vector3.UP, atan2(dir.x, dir.z) + PI * 0.5))
			_box("paint", Vector3(0.5, 0.3, 0.4), p - side.normalized() * 0.5 + Vector3(0, 8.4, 0), Color("#4a4e52"))
	# The show arena: an open steel roof on posts over a dirt ring.
	var sa := Vector3(92.0, 0, -25.0)
	var aw := 26.0
	var ad := 40.0
	_flat_rect("gravel", sa.x - aw * 0.5, sa.x + aw * 0.5, sa.z - ad * 0.5, sa.z + ad * 0.5, 0.052, DIRT)
	for i in 7:
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.25, 4.2, 0.25), sa + Vector3(sx * aw * 0.5, 2.1, -ad * 0.5 + i * ad / 6.0), GALV)
	_gable_roof(sa.x, sa.z, 4.2, aw, 2.6, ad, false, Color("#9a9fa2"), Color("#c9ccc8"))
	var rx := aw * 0.5 - 4.0
	var rz := ad * 0.5 - 4.0
	for e in [[Vector3(-rx, 0, -rz), Vector3(rx, 0, -rz)], [Vector3(rx, 0, -rz), Vector3(rx, 0, rz)],
			[Vector3(rx, 0, rz), Vector3(-rx, 0, rz)], [Vector3(-rx, 0, rz), Vector3(-rx, 0, -rz)]]:
		_pipe_rail(sa + e[0], sa + e[1])
	# A few rows of seats along one long side, inside the roof.
	for r in 3:
		_box("paint", Vector3(0.3, 0.06, ad - 10.0), sa + Vector3(-aw * 0.5 + 1.0 + r * 0.7, 0.45 + r * 0.4, 0), ALUMINUM)
	# Poultry and rabbit barn: enclosed, white steel, a row of windows.
	var pb := Vector3(90.0, 0, -66.0)
	_box("metal", Vector3(30.0, 3.4, 11.0), pb + Vector3(0, 1.7, 0), Color("#e2e2dc"))
	_gable_roof(pb.x, pb.z, 3.4, 11.0, 1.6, 30.0, true, Color("#2f5a3a"), Color("#e2e2dc"))
	for i in 6:
		_glass(Vector3(pb.x - 12.5 + i * 5.0, 2.2, pb.z + 5.53), Vector3(1, 0, 0), 1.6, 0.8, 0.0)
	_overhead_door(pb.x - 15.0 + 0.0, pb.z - 5.5, 3.0, 2.6, Color("#e8e6df"))
	# The 4-H food stand: block walls, a serving window, a lean-to awning.
	var fs := Vector3(30.0, 0, -28.0)
	_box("paint", Vector3(10.0, 3.0, 6.0), fs + Vector3(0, 1.5, 0), Color("#d9d3c4"))
	_box("paint", Vector3(10.6, 0.25, 6.6), fs + Vector3(0, 3.12, 0), Color("#5a5e60"))
	_glass(Vector3(fs.x, 1.6, fs.z - 3.03), Vector3(-1, 0, 0), 6.0, 1.0, 0.0)
	_box("paint", Vector3(6.4, 0.08, 0.5), fs + Vector3(0, 1.02, -3.25), Color("#b0b4b6"))
	_box("paint", Vector3(10.4, 0.1, 2.6), fs + Vector3(0, 2.55, -4.2), Color("#2f5a3a"), Basis(Vector3.RIGHT, 0.2))
	labels.append({"pos": fs + Vector3(0, 2.75, -3.04), "normal": Vector3(0, 0, -1), "text": "4-H FOOD STAND",
		"height": 0.35, "color": Color("#2f5a3a")})
	for i in 4:
		_table(fs + Vector3(-6.0 + i * 4.0, 0, -11.0))
	# The restroom house: tan block under a hip roof.
	var rr := Vector3(-30.0, 0, -28.0)
	_box("paint", Vector3(8.0, 2.8, 5.0), rr + Vector3(0, 1.4, 0), Color("#cbb994"))
	_hip_roof(rr.x, rr.z, 2.8, 8.0, 5.0, 1.4, Color("#5a3a2e"))
	for sx in [-1.0, 1.0]:
		_box("paint", Vector3(1.0, 2.1, 0.06), rr + Vector3(sx * 2.0, 1.05, -2.53), Color("#6a7a84"))
	_box("paint", Vector3(5.0, 0.12, 2.0), rr + Vector3(0, 0.06, -3.5), CONCRETE)
	# Old maples and oaks along the back fence and the east side.
	var x := -hx + 8.0
	while x < hx - 8.0:
		var p := Vector3(x + rng.randf_range(-2.0, 2.0), 0, hz - 6.0 + rng.randf_range(-1.5, 1.5))
		if not ("expo_hall" in built and x > -64.0 and x < 4.0):
			var pick := TreeField.pick(rng)
			trees.append([p, pick[0], pick[1], rng.randf_range(0.9, 1.25)])
		x += rng.randf_range(11.0, 16.0)
	var z := 8.0
	while z < hz - 14.0:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(hx - 7.0, 0, z), pick[0], pick[1], rng.randf_range(0.9, 1.2)])
		z += 14.0
	for i in 4:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(9.0, 0, -20.0 + i * 18.0), pick[0], pick[1], rng.randf_range(0.85, 1.1)])


## A livestock pipe-rail fence: galvanised posts and two round rails.
func _pipe_rail(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var dir := (b - a) / len
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var n := maxi(1, int(len / 3.0))
	for k in n + 1:
		_box("paint", Vector3(0.09, 1.35, 0.09), a + dir * (len * k / n) + Vector3(0, 0.675, 0), GALV.darkened(0.1))
	for y in [0.6, 1.25]:
		_box("paint", Vector3(0.06, 0.06, len), (a + b) * 0.5 + Vector3(0, y, 0) + Vector3(dir.z, 0, -dir.x) * 0.07, GALV, yaw)


## A long open-sided livestock barn: posts, a gable roof, pens of gates.
func _barn_shed(c: Vector3, length: float, depth: float) -> void:
	var n := int(length / 6.0)
	for i in n + 1:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.25, 3.2, 0.25), c + Vector3(-length * 0.5 + i * length / n, 1.6, sz * depth * 0.5), WOOD)
	_gable_roof(c.x, c.z, 3.2, depth, 1.8, length, true, Color("#9a9fa2"), Color("#c9c4b4"))
	_flat_rect("gravel", c.x - length * 0.5, c.x + length * 0.5, c.z - depth * 0.5, c.z + depth * 0.5, 0.055, Color("#a08a64"))
	# Two rows of pipe-gate pens either side of a centre aisle, bedded in
	# straw, with square bales stacked at one end.
	var x0 := c.x - length * 0.5 + 3.0
	var x1 := c.x + length * 0.5 - 3.0
	for sz in [-1.0, 1.0]:
		var zi: float = c.z + sz * 1.6
		var zo: float = c.z + sz * (depth * 0.5 - 0.6)
		_pipe_rail(Vector3(x0, 0, zi), Vector3(x1, 0, zi))
		var x := x0
		while x < x1 + 0.1:
			_pipe_rail(Vector3(x, 0, zi + sz * 0.15), Vector3(x, 0, zo))
			x += 3.0
		_flat_rect("gravel", x0, x1, minf(zi, zo), maxf(zi, zo), 0.065, Color("#c9b06a"))
	for i in 6:
		_box("paint", Vector3(0.9, 0.4, 0.46), Vector3(x1 + 1.3, 0.2 + (i / 3) * 0.4, c.z - 1.0 + (i % 3) * 0.48),
			Color("#c4ab68").darkened(rng.randf_range(0.0, 0.12)))


## A flat ring (an oval track or rail) of `width`.
func _oval(c: Vector3, w: float, d: float, width: float, col: Color, y := 0.055) -> void:
	var segs := 40
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var pts := []
		for e in [[a0, 0.5], [a1, 0.5], [a1, -0.5], [a0, -0.5]]:
			var a: float = e[0]
			var k: float = e[1] * width
			pts.append(c + Vector3(cos(a) * (w * 0.5 + k), 0, sin(a) * (d * 0.5 + k)))
		_flat_poly(pts, y, col)


func _ferris_wheel(c: Vector3) -> void:
	var r := 9.0
	var hub := c + Vector3(0, r + 1.5, 0)
	for sz in [-0.8, 0.8]:
		_strut(c + Vector3(-4.0, 0, sz), hub + Vector3(0, 0, sz), 0.25, WHITE)
		_strut(c + Vector3(4.0, 0, sz), hub + Vector3(0, 0, sz), 0.25, WHITE)
	var prev := Vector3.ZERO
	for i in 17:
		var a := TAU * i / 16.0
		var p := hub + Vector3(cos(a) * r, sin(a) * r, 0)
		if i > 0:
			_strut(prev, p, 0.15, Color("#e8c23a"))
			_strut(hub, p, 0.06, WHITE)
			_box("paint", Vector3(1.2, 1.0, 1.0), p + Vector3(0, -0.7, 0),
				[Color("#c23a3a"), Color("#2f7ac0"), Color("#4aa86a")][i % 3])
		prev = p


func _ride(c: Vector3) -> void:
	# A swing ride: a tower, a spinning crown and seats on chains.
	_cyl_y(c + Vector3(0, 5.0, 0), 0.5, 10.0, Color("#d8d2c2"))
	_cylinder("paint", c + Vector3(0, 9.0, 0), 5.0, 0.8, Color("#c23a3a"), 16)
	for i in 12:
		var a := TAU * i / 12.0
		var p := c + Vector3(cos(a) * 6.5, 5.0, sin(a) * 6.5)
		_strut(c + Vector3(cos(a) * 5.0, 9.0, sin(a) * 5.0), p, 0.04, GALV)
		_box("paint", Vector3(0.6, 0.4, 0.6), p, Color("#e8c23a"))
	_cylinder("paint", c, 7.5, 0.3, CONCRETE, 20)


## A one-storey roadside motel: a row of rooms under a low roof with a
## walkway, a lobby at the end, a pole sign and parking in front.
func _motel(size: Vector2, to_curb: float, name: String) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_parking(-hx + 1.0, hx - 1.0, -hz, -hz + 14.0, to_curb, 0.0)
	var wall := Color("#d9cdb4")
	var z := hz - 8.0
	_box("brick", Vector3(size.x - 6.0, 3.2, 10.0), Vector3(0, 1.6, z), wall)
	_hip_roof(0.0, z, 3.2, size.x - 6.0, 10.0, 1.4, Color("#5a4038"))
	_box("paint", Vector3(size.x - 6.0, 0.15, 2.2), Vector3(0, 3.0, z - 6.1), Color("#e8e2d0"))
	var n := int((size.x - 10.0) / 3.6)
	for i in n:
		var x := -hx + 5.0 + i * 3.6
		_box("paint", Vector3(0.95, 2.1, 0.05), Vector3(x, 1.05, z - 5.03), [Color("#3a6a8a"), Color("#8a3a2a")][i % 2])
		_glass(Vector3(x + 1.4, 1.5, z - 5.03), Vector3(1, 0, 0), 1.2, 1.0, 0.6)
	var sign := Vector3(hx - 4.0, 0, -hz + 2.0)
	_cyl_y(sign + Vector3(0, 4.0, 0), 0.15, 8.0, DARK)
	_box("paint", Vector3(4.6, 1.8, 0.3), sign + Vector3(0, 7.4, 0), Color("#b8342a"))
	labels.append({"pos": sign + Vector3(0, 7.4, -0.17), "normal": Vector3(0, 0, -1), "text": name.to_upper(),
		"height": 0.35, "color": Color("#fff6d8")})
	labels.append({"pos": sign + Vector3(0, 6.2, -0.17), "normal": Vector3(0, 0, -1), "text": "VACANCY",
		"height": 0.3, "color": Color("#ff6a4a")})


## A small-town diner: brick and stainless with a band of windows, a pole
## sign and a lot.
func _diner(size: Vector2, to_curb: float, name: String) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_parking(-hx + 1.0, hx - 1.0, -hz, -hz + 12.0, to_curb, hx - 5.0)
	var c := Vector3(-1.0, 0, hz - 9.0)
	_box("brick", Vector3(18.0, 1.1, 11.0), c + Vector3(0, 0.55, 0), Color("#8a3a2a"))
	_box("metal", Vector3(18.0, 2.6, 11.0), c + Vector3(0, 2.4, 0), Color("#c8ccce"))
	_glass(c + Vector3(0, 2.2, -5.53), Vector3(1, 0, 0), 15.0, 1.4, 0.2)
	_box("paint", Vector3(18.6, 0.4, 11.6), c + Vector3(0, 3.9, 0), Color("#b8342a"))
	labels.append({"pos": c + Vector3(0, 3.9, -5.82), "normal": Vector3(0, 0, -1), "text": name.to_upper(),
		"height": 0.32, "color": Color("#fff6d8")})
	var sign := Vector3(-hx + 3.0, 0, -hz + 2.0)
	_cyl_y(sign + Vector3(0, 3.5, 0), 0.15, 7.0, DARK)
	_box("paint", Vector3(3.6, 1.6, 0.3), sign + Vector3(0, 6.6, 0), Color("#f2ecd8"))
	labels.append({"pos": sign + Vector3(0, 6.6, -0.17), "normal": Vector3(0, 0, -1), "text": "EAT",
		"height": 0.8, "color": Color("#b8342a")})


## A gas station: a canopy over two islands of pumps, a convenience store
## at the back and a price sign by the road.
func _gas_station(size: Vector2, to_curb: float, name: String) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_flat_rect("asphalt", -hx + 1.0, hx - 1.0, -hz, hz - 1.0, 0.05)
	for x in [-hx + 7.0, hx - 7.0]:
		_flat_rect("asphalt", x - 4.0, x + 4.0, -hz - to_curb, -hz, 0.06)
	var cz := -hz + 13.0
	for i in 2:
		var ix := -6.0 + i * 12.0
		_box("paint", Vector3(1.2, 0.2, 7.0), Vector3(ix, 0.1, cz), CONCRETE)
		for j in 2:
			_box("paint", Vector3(0.7, 1.7, 1.0), Vector3(ix, 0.95, cz - 1.8 + j * 3.6), Color("#e8e6df"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.5, 5.0, 0.5), Vector3(sx * 7.0, 2.5, cz + sz * 3.0), WHITE)
	_box("paint", Vector3(26.0, 1.0, 12.0), Vector3(0, 5.4, cz), WHITE)
	_box("paint", Vector3(26.1, 0.35, 12.1), Vector3(0, 5.2, cz), Color("#2f5a8a"))
	var st := Vector3(0, 0, hz - 8.0)
	_box("brick", Vector3(18.0, 4.0, 11.0), st + Vector3(0, 2.0, 0), Color("#b8ad98"))
	_box("paint", Vector3(18.4, 0.6, 11.4), st + Vector3(0, 4.3, 0), Color("#2f5a8a"))
	_glass(st + Vector3(-2.0, 1.6, -5.53), Vector3(1, 0, 0), 10.0, 2.2, 0.3)
	labels.append({"pos": st + Vector3(0, 4.3, -5.72), "normal": Vector3(0, 0, -1), "text": name.to_upper(),
		"height": 0.3, "color": Color("#ffffff")})
	var sign := Vector3(hx - 3.0, 0, -hz + 2.0)
	_cyl_y(sign + Vector3(0, 3.0, 0), 0.15, 6.0, DARK)
	_box("paint", Vector3(2.4, 2.6, 0.3), sign + Vector3(0, 5.8, 0), Color("#2f5a8a"))
	labels.append({"pos": sign + Vector3(0, 5.8, -0.17), "normal": Vector3(0, 0, -1), "text": "GAS\n3.19",
		"height": 0.45, "color": Color("#ffffff")})


# ----------------------------------------------------------------- trails

## A trailhead: a gravel lot for about 20 cars off the street, a timber map
## kiosk, a vault toilet, a bike rack and a bench, and the trail heading off
## the back (typical Indiana greenway and rail-trail trailheads).
func _trailhead(size: Vector2, to_curb: float) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var gravel := Color("#a39a88")
	_flat_rect("gravel", -hx + 2.0, hx - 2.0, -hz, -hz + 17.0, 0.05, gravel)
	_flat_rect("gravel", -3.0, 3.0, -hz - to_curb, -hz, 0.08, gravel)
	# Timber wheel stops along the back of the lot.
	var x := -hx + 4.0
	while x < hx - 4.0:
		_box("paint", Vector3(1.8, 0.15, 0.2), Vector3(x, 0.08, -hz + 15.8), WOOD)
		x += 2.75
	# The trail starts behind the lot.
	_strip(Vector3(0, 0, -hz + 17.0), Vector3(0, 0, hz + 1.0), Balance.TRAIL_WIDTH, "asphalt", Color("#4a4a48"))
	_strip(Vector3(0, 0, -hz + 17.0), Vector3(0, 0, hz + 1.0), 0.1, "line", Color("#d8b030"), 0.055)
	# Map kiosk: two posts, a shingled roof, a board under it.
	var k := Vector3(-5.0, 0, -hz + 19.5)
	for sx in [-1.1, 1.1]:
		_box("paint", Vector3(0.2, 2.6, 0.2), k + Vector3(sx, 1.3, 0), WOOD)
	_box("paint", Vector3(2.0, 1.2, 0.08), k + Vector3(0, 1.4, 0), Color("#2f4632"))
	_gable_roof(k.x, k.z, 2.6, 1.4, 0.5, 2.8, true, Color("#4a3a30"), WOOD, false)
	labels.append({"pos": k + Vector3(0, 1.75, -0.05), "normal": Vector3(0, 0, -1), "text": "TRAIL MAP",
		"height": 0.18, "color": Color("#efe6c8")})
	# Vault toilet: a small concrete block with a roof.
	var t := Vector3(hx - 7.0, 0, -hz + 20.5)
	_box("brick", Vector3(3.0, 2.6, 2.4), t + Vector3(0, 1.3, 0), Color("#b8b2a4"))
	_gable_roof(t.x, t.z, 2.6, 2.8, 0.6, 3.4, true, Color("#5a4a3e"), Color("#b8b2a4"), false)
	_box("paint", Vector3(0.9, 2.0, 0.05), t + Vector3(0, 1.0, -1.23), Color("#4a5a4a"))
	# Bike rack: inverted U hoops.
	for i in 4:
		var r := Vector3(3.0 + i * 0.9, 0, -hz + 18.5)
		_box("metal", Vector3(0.05, 0.9, 0.05), r + Vector3(-0.3, 0.45, 0), DARK)
		_box("metal", Vector3(0.05, 0.9, 0.05), r + Vector3(0.3, 0.45, 0), DARK)
		_box("metal", Vector3(0.65, 0.05, 0.05), r + Vector3(0, 0.9, 0), DARK)
	_bench(Vector3(-5.0, 0, -hz + 22.5), 0.0)
	_park_sign(Vector3(hx - 5.0, 0, -hz + 1.5), "TRAILHEAD")
	# What real Indiana trailheads add (Cardinal Greenway, Nickel Plate,
	# Monon): a split-rail fence round the lot, a concrete van-accessible
	# stall with its blue sign, a picnic table in the shade, a trash can and
	# a dog-waste station by the trail, and shade trees round the edge.
	var rail := Color("#8a7458")
	_split_rail(Vector3(-hx + 1.2, 0, -hz + 3.0), Vector3(-hx + 1.2, 0, -hz + 17.5), rail)
	_split_rail(Vector3(hx - 1.2, 0, -hz + 3.0), Vector3(hx - 1.2, 0, -hz + 17.5), rail)
	_split_rail(Vector3(-hx + 1.2, 0, -hz + 17.5), Vector3(-Balance.TRAIL_WIDTH - 1.0, 0, -hz + 17.5), rail)
	_split_rail(Vector3(Balance.TRAIL_WIDTH + 1.0, 0, -hz + 17.5), Vector3(hx - 1.2, 0, -hz + 17.5), rail)
	var ax := -hx + 4.0 + 1.4
	_flat_rect("drive", ax - 2.4, ax + 2.4, -hz + 9.5, -hz + 16.0, 0.07)
	# The 8 ft access aisle beside it: a blue outline and diagonal hatching.
	var blue := Color("#2a5aa8")
	_flat_rect("line", ax + 0.2, ax + 0.3, -hz + 9.6, -hz + 15.9, 0.075, blue)
	_flat_rect("line", ax + 2.2, ax + 2.3, -hz + 9.6, -hz + 15.9, 0.075, blue)
	for i in 6:
		var z := -hz + 10.2 + i * 1.0
		_strip(Vector3(ax + 0.3, 0, z), Vector3(ax + 2.2, 0, z + 0.7), 0.1, "line", blue, 0.076)
	_box("metal", Vector3(0.07, 2.1, 0.07), Vector3(ax - 1.6, 1.05, -hz + 16.3), GALV)
	_box("paint", Vector3(0.3, 0.45, 0.03), Vector3(ax - 1.6, 1.9, -hz + 16.26), Color("#2a5aa8"))
	_table(Vector3(5.5, 0, -hz + 23.5))
	var bin := Vector3(Balance.TRAIL_WIDTH * 0.5 + 1.6, 0, -hz + 18.4)
	_cylinder("metal", bin, 0.32, 0.95, Color("#2f4632"), 12)
	_box("metal", Vector3(0.06, 1.2, 0.06), bin + Vector3(1.0, 0.6, 0), Color("#2f4632"))
	_box("paint", Vector3(0.36, 0.4, 0.12), bin + Vector3(1.0, 1.05, -0.06), Color("#2f4632"))
	for i in 7:
		var pick := TreeField.pick(rng)
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * (hx - 3.0 - rng.randf_range(0.0, 2.0)), 0, -hz + 19.0 + i * 2.5)
		if absf(p.x) > Balance.TRAIL_WIDTH + 2.0 and p.z < hz - 2.0:
			trees.append([p, pick[0], pick[1], rng.randf_range(0.8, 1.1)])


## A two-rail split-rail fence (cedar posts about 3 m apart) from a to b.
func _split_rail(a: Vector3, b: Vector3, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var dir := (b - a) / len
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var n := maxi(1, int(len / 3.0))
	for k in n + 1:
		_box("paint", Vector3(0.16, 1.15, 0.16), a + dir * (len * k / n) + Vector3(0, 0.575, 0), col.darkened(0.1))
	for y in [0.45, 0.9]:
		_box("paint", Vector3(0.1, 0.12, len), (a + b) * 0.5 + Vector3(0, y, 0) + Vector3(dir.z, 0, -dir.x) * 0.1, col, yaw)


## The town's trails as one flat mesh in world space (y = 0, to drape over
## the land): a 10 ft asphalt path with a dashed yellow centre line, broken
## where it crosses a street. `on_road` says whether a point is on a street.
static func trails_mesh(paths: Array, on_road: Callable) -> ArrayMesh:
	var b := ParkBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Balance.TRAIL_WIDTH
	for path in paths:
		var pts: Array = path.pts
		for i in pts.size() - 1:
			var a := Vector3(float(pts[i][0]), 0, float(pts[i][1]))
			var c := Vector3(float(pts[i + 1][0]), 0, float(pts[i + 1][1]))
			var n := maxi(1, ceili(a.distance_to(c) / 4.0))
			for k in n:
				var p0 := a.lerp(c, float(k) / n)
				var p1 := a.lerp(c, float(k + 1) / n)
				if on_road.call((p0 + p1) * 0.5):
					continue
				# A little past each end so bends close up.
				var d := (p1 - p0).normalized() * w * 0.25
				b._strip(p0 - d, p1 + d, w, "asphalt", Color("#4a4a48"))
				if k % 2 == 0:
					b._strip(p0.lerp(p1, 0.15), p0.lerp(p1, 0.85), 0.1, "line", Color("#d8b030"), 0.055)
	return b._commit_flat()


## Pedestrian plazas on closed downtown blocks, like the Kalamazoo Mall or
## Iowa City's Ped Mall: brick pavers curb to curb with concrete bands,
## planters and benches down the middle, cafe tables out front of the
## shops, and bollards at each end that drop for night deliveries.
## blocks: [{pts (PackedVector3Array along the street), w (curb to curb)}].
## Returns [flat, furniture, trees ([pos, species, variant, scale])].
static func plaza_mesh(blocks: Array) -> Array:
	var b := ParkBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = 11
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	for block in blocks:
		var pts: PackedVector3Array = block.pts
		var w := float(block.w)
		var along := 0.0
		var next_band := 6.0
		var next_spot := 10.0
		var spot := 0
		for i in pts.size() - 1:
			var p0 := Vector3(pts[i].x, 0, pts[i].z)
			var p1 := Vector3(pts[i + 1].x, 0, pts[i + 1].z)
			var seg := p0.distance_to(p1)
			if seg < 0.1:
				continue
			var d := (p1 - p0) / seg
			var side := Vector3(-d.z, 0, d.x)
			var yaw := atan2(d.x, d.z)
			b._strip(p0 - d * 0.5, p1 + d * 0.5, w, "line", Color("#8a5e4e"), 0.06)
			while next_band < along + seg:
				var c := p0 + d * (next_band - along)
				b._strip(c - d * 0.25, c + d * 0.25, w, "drive", Color("#b8b2a6"), 0.07)
				next_band += 12.0
			while next_spot < along + seg:
				var c := p0 + d * (next_spot - along)
				if spot % 2 == 0:
					# A raised limestone planter with a honey locust, the downtown
					# mall tree: light shade, small leaves that don't need raking.
					b._box("paint", Vector3(1.8, 0.5, 3.2), c + Vector3(0, 0.25, 0), LIMESTONE, Basis(Vector3.UP, yaw))
					b._box("paint", Vector3(1.5, 0.04, 2.9), c + Vector3(0, 0.5, 0), MULCH, Basis(Vector3.UP, yaw))
					var tint: Color = TreeField.LEAF[TreeField.Species.LOCUST]
					b.trees.append([c + Vector3(0, 0.5, 0), TreeField.Species.LOCUST,
						tint.lightened(b.rng.randf_range(-0.06, 0.08)), b.rng.randf_range(0.6, 0.75)])
					b._bench(c + side * 1.8, yaw + PI * 0.5)
					b._bench(c - side * 1.8, yaw - PI * 0.5)
				else:
					for s in [-1.0, 1.0]:
						var t: Vector3 = c + side * s * (w * 0.5 - 2.2)
						b._cylinder("paint", t + Vector3(0, 0.72, 0), 0.4, 0.04, Color("#2c3a34"), 10)
						b._cyl_y(t + Vector3(0, 0.36, 0), 0.04, 0.72, Color("#202224"))
						for k in 2:
							var ch: Vector3 = t + d * (0.75 if k == 0 else -0.75)
							b._box("paint", Vector3(0.42, 0.45, 0.42), ch + Vector3(0, 0.22, 0), Color("#2c3a34"))
					b._lamp(c)
				spot += 1
				next_spot += 9.0
			along += seg
		# Bollards across each end.
		for e in [0, pts.size() - 1]:
			var o := Vector3(pts[e].x, 0, pts[e].z)
			var nb := pts[1] if e == 0 else pts[pts.size() - 2]
			var d2 := (Vector3(nb.x, 0, nb.z) - o).normalized()
			var side2 := Vector3(-d2.z, 0, d2.x)
			o += d2 * 2.0
			var n := maxi(2, int(w / 1.6))
			for k in n + 1:
				var q := o + side2 * lerpf(-w * 0.5 + 0.6, w * 0.5 - 0.6, float(k) / n)
				b._cyl_y(q + Vector3(0, 0.45, 0), 0.11, 0.9, Color("#2a2c2e"))
	return [b._commit_flat(), b._commit_house(), b.trees]
