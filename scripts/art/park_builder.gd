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
## Local space as in CivicBuilder: centred on the site, -z faces the road.

const LAWN_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
uniform vec4 dry : source_color = vec4(0.50, 0.48, 0.28, 1.0);
uniform vec4 soil : source_color = vec4(0.47, 0.40, 0.29, 1.0);
varying vec3 world_pos;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
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
	vec3 col = mix(lin(COLOR.rgb), dry.rgb, smoothstep(0.4, 0.8, mid) * mix(0.8, 0.15, care));
	col *= 1.0 - smoothstep(0.4, 0.9, clump) * mix(0.08, 0.18, care);
	// Bare, trodden spots where nobody keeps the grass up.
	float bare = smoothstep(mix(0.68, 1.2, care), mix(0.82, 1.3, care), clump * 0.6 + mid * 0.5);
	col = mix(col, soil.rgb, bare * 0.65);
	// Mowing stripes on a curated lawn, 4 m wide.
	float stripe = step(0.5, fract(UV.x / 8.0));
	col *= 1.0 + (stripe - 0.5) * 0.12 * smoothstep(0.75, 1.0, care);
	float fade = clamp(1.0 - length(VERTEX) / 160.0, 0.0, 1.0);
	col *= 1.0 + (grain - 0.5) * 0.3 * fade;
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
		"football": b._football(size, to_curb)
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
	var has_paths := false
	for f in site.features:
		has_paths = has_paths or f.type == "paths"
	# Walks from the street to each thing, and a loop round the lawn in
	# kept parks. Worn parks get dirt desire lines instead.
	if has_paths:
		var kind := "drive" if tier >= 2 else ("asphalt" if tier == 1 else "gravel")
		var col := Color("#8f7a5c") if tier == 0 else MULCH
		var w := 2.4 if tier >= 1 else 1.4
		_strip(entrance + Vector3(0, 0, -to_curb), entrance + Vector3(0, 0, 6.0), w, kind, col)
		for s in spots:
			_strip(entrance + Vector3(0, 0, 6.0), s[0] + Vector3(0, 0, -s[1].y * 0.5), w, kind, col)
		if tier >= 2 and size.x > 40.0 and size.y > 40.0:
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
	for i in 6:
		edge.append(Vector3(rng.randf_range(-hx + 8.0, hx - 8.0), 0, rng.randf_range(-hz + 10.0, hz - 6.0)))
	for p in edge:
		if rng.randf() < skip or _in_spots(p, spots, 5.0) or absf(p.x) < 4.0 and p.z < -hz + 30.0:
			continue
		var pick := TreeField.pick(rng)
		var q := Vector3(p.x + rng.randf_range(-1.5, 1.5), 0, p.z + rng.randf_range(-1.5, 1.5))
		trees.append([q, pick[0], pick[1], rng.randf_range(0.85, 1.2)])


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
func _strip(a: Vector3, b: Vector3, w: float, kind: String, col: Color) -> void:
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	if d.length() < 0.5:
		return
	var n := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	var y := 0.045  # under mulch beds and courts, which sit on top of the walks
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
	var concrete := Color("#cbc5b6")
	# A row of slip-formed silos, 8.5 m across and 36 m tall.
	var n := 4
	var r := 4.25
	var zc := 4.0
	for i in n:
		var x := -12.0 + i * r * 2.0
		_cylinder("paint", Vector3(x, 0, zc), r, 36.0, concrete.darkened(rng.randf_range(0.0, 0.06)), 20)
	# The gallery on top and the tall headhouse at one end.
	_box("metal", Vector3(n * r * 2.0, 3.0, 4.0), Vector3(-12.0 + (n - 1) * r, 37.5, zc), Color("#b9b4a6"))
	var hx := -12.0 + n * r * 2.0 + 1.0
	_box("paint", Vector3(9.0, 46.0, 10.0), Vector3(hx, 23.0, zc), concrete.lightened(0.04))
	_box("metal", Vector3(7.0, 5.0, 8.0), Vector3(hx, 48.5, zc), Color("#b9b4a6"))
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


# ---------------------------------------------------------------- football

func _football(size: Vector2, to_curb: float) -> void:
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
	_bleachers(Vector3(0, 0, fz + 5.0), 60.0, 10, true)
	_bleachers(Vector3(0, 0, -fz - 5.0), 30.0, 5, false)
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
