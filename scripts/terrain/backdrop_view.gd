class_name BackdropView
extends Node3D
## Draws the backdrop towns (Backdrop: Marion, Gas City, Jonesboro) as they
## stand: every real building as a box of its real footprint and height,
## with a pitched roof on the houses, and every street, from
## terrain/grant_in/backdrop.bin (tools/terrain/build_roads.py). Nothing in
## them is simulated, so they cost only what they draw: one mesh per 2 km
## block (a few dozen draw calls for all three towns), built once, a few
## 256 m squares a frame.
##
## Benchmark: aerial photos of Marion, Indiana: brick and frame houses on a
## street grid, a downtown of two- to four-storey blocks round the
## courthouse, mills and warehouses along the rail and the river.

## Side of the squares the town is built in, a few a frame, metres.
const CHUNK := 256.0
## Squares per side of a block, which is drawn as one mesh.
const BLOCK := 8
## Time to spend building squares each frame, ms (the web build has no threads).
const BUDGET_MS := 3.0
## Street widths, metres, by class: alley or drive, street, arterial.
const WIDTHS := [5.0, 9.0, 13.0]
## A house-sized building (footprint m², height m) gets a pitched roof.
const HOUSE_AREA := 260.0
const HOUSE_HEIGHT := 9.0

## Colours from aerial and street photos of Marion: frame houses in vinyl
## and painted siding (white, cream, grey, pale blue, sage, yellow) with
## some red and brown brick; shingle roofs in greys and browns.
const HOUSE_WALLS := [Color(0.88, 0.87, 0.83), Color(0.80, 0.75, 0.64), Color(0.66, 0.68, 0.68),
	Color(0.62, 0.68, 0.72), Color(0.62, 0.66, 0.56), Color(0.85, 0.78, 0.55), Color(0.72, 0.62, 0.48),
	Color(0.55, 0.30, 0.24), Color(0.48, 0.32, 0.25), Color(0.86, 0.85, 0.80)]
const ROOFS := [Color(0.24, 0.24, 0.25), Color(0.32, 0.27, 0.24), Color(0.40, 0.40, 0.41), Color(0.20, 0.21, 0.23),
	Color(0.36, 0.30, 0.25), Color(0.45, 0.43, 0.40)]
## Stores, plants and warehouses: tan and grey block, tilt-up and metal
## panels, some brick.
const SHOP_WALLS := [Color(0.74, 0.68, 0.56), Color(0.62, 0.62, 0.60), Color(0.78, 0.76, 0.70),
	Color(0.58, 0.33, 0.26), Color(0.68, 0.64, 0.58), Color(0.42, 0.30, 0.24)]
## Downtown round the courthouse: two- to four-storey red and brown brick.
const BRICK := [Color(0.56, 0.30, 0.24), Color(0.50, 0.33, 0.26), Color(0.62, 0.40, 0.30), Color(0.45, 0.27, 0.22)]
## Flat roofs: white membrane on newer stores, grey ballast, black rubber, tar.
const FLAT_ROOFS := [Color(0.80, 0.81, 0.80), Color(0.52, 0.51, 0.49), Color(0.22, 0.22, 0.23), Color(0.34, 0.33, 0.32)]
## Share of wall that is glass (the far shader's window grid): houses,
## stores and plants, downtown blocks.
const GLASS := [0.14, 0.12, 0.3]
## A store or plant this big (m²) has a parking lot round it, about 1.3 m²
## of lot to each m² of floor (US suburban codes: 4 spaces per 1,000 ft²).
const LOT_AREA := 1500.0
const LOT_SHARE := 1.3
const LOT_ASPHALT := Color(0.33, 0.33, 0.33)
const ASPHALT := Color(0.27, 0.27, 0.28)
const WALK := Color(0.56, 0.55, 0.52)
## Yard trees, desktop only. Marion's older neighbourhoods sit under
## mature maples, oaks and ashes (Indiana's urban canopy is about a third
## of residential land; aerial photos show a crown or two in most yards),
## so bare houses on lawns read as a model town. Trees per house by
## quality tier (Low, Medium, High, Ultra, Cinematic): a domed crown of
## 28 triangles each.
const TREES_PER_HOUSE := [0.0, 0.6, 1.1, 1.5, 1.8]
## Summer crowns, dark to light (vertex alpha under 0.5 marks foliage
## for the plain material: matte and broken into leaf clumps).
const CROWNS := [Color(0.29, 0.39, 0.19, 0.3), Color(0.33, 0.43, 0.21, 0.3), Color(0.26, 0.35, 0.17, 0.3),
	Color(0.36, 0.44, 0.23, 0.3), Color(0.30, 0.37, 0.21, 0.3)]

## Region square -> [buildings [Array of 6 numbers]], [streets [class, PackedVector2Array]]
var _todo := {}
var _origin := Vector2.INF
## Squares still to build, a block's together.
var _queue: Array = []
## Block -> [squares left, vertices, normals, colours, uvs, tree vertices, normals, colours,
##   streetlight pool vertices, colours, uvs]
var _blocks := {}
## The player town's far-building look (sRGB colours, windows, snow).
var _material: Material
## Yard trees per house for the current quality tier (TREES_PER_HOUSE).
var _trees := 0.0


func _ready() -> void:
	_material = HouseMaterials.get_mat("far")
	_load()
	var q := GraphicsQuality.current
	if q != null:
		q.changed.connect(func() -> void:
			if _tree_share() != _trees:
				_origin = Vector2.INF)


## Yard trees per house now: none in the browser or on Low.
func _tree_share() -> float:
	var q := GraphicsQuality.current
	if q == null or not q.active or q.browser:
		return 0.0
	return TREES_PER_HOUSE[clampi(q.tier, 0, TREES_PER_HOUSE.size() - 1)]


## Reads the town and files it by square, to be built over the next frames.
func _load() -> void:
	var raw := FileAccess.get_file_as_bytes(Terrain.DIR + "backdrop.bin")
	if raw.is_empty():
		return
	var data := raw.decompress_dynamic(16 << 20, FileAccess.COMPRESSION_GZIP)
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "BKD1":
		push_error("BackdropView: can't read backdrop.bin")
		return
	var at := 4
	var n := data.decode_u32(at)
	at += 4
	for i in n:
		var b := [data.decode_s16(at), data.decode_s16(at + 2), data.decode_s16(at + 4) * 0.1,
			data.decode_s16(at + 6) * 0.1, data.decode_s16(at + 8) * 0.1, data.decode_s16(at + 10) * 0.01]
		at += 12
		_square(Vector2(b[0], b[1]))[0].append(b)
	n = data.decode_u32(at)
	at += 4
	for i in n:
		var k := data.decode_u8(at)
		var count := data.decode_u16(at + 1)
		at += 3
		var pts := PackedVector2Array()
		for j in count:
			pts.append(Vector2(data.decode_s16(at), data.decode_s16(at + 2)))
			at += 4
		# Filed by its first point; a street drawn into the next square is fine.
		_square(pts[0])[1].append([k, pts])


func _square(p: Vector2) -> Array:
	var c := Vector2i((p / CHUNK).floor())
	if not _todo.has(c):
		_todo[c] = [[], []]
	return _todo[c]


func _process(_delta: float) -> void:
	# Built where your own town sits in the region; rebuilt if that moves.
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		_trees = _tree_share()
		for child in get_children():
			child.queue_free()
		_queue = _todo.keys()
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ba := Vector2i(floori(a.x / float(BLOCK)), floori(a.y / float(BLOCK)))
			var bb := Vector2i(floori(b.x / float(BLOCK)), floori(b.y / float(BLOCK)))
			return ba.x > bb.x or (ba.x == bb.x and ba.y > bb.y))
		_blocks.clear()
		for c in _queue:
			var k := _block(c)
			if not _blocks.has(k):
				_blocks[k] = [0, PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(),
					PackedVector3Array(), PackedVector3Array(), PackedColorArray(),
					PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
			_blocks[k][0] += 1
	if _queue.is_empty():
		return
	var start := Time.get_ticks_msec()
	while not _queue.is_empty() and Time.get_ticks_msec() - start < BUDGET_MS:
		_build(_queue.pop_back())


## Yard-tree crowns through the year: Marion's street trees are mostly
## maples, oaks, ashes and lindens, so they turn yellow, orange and red
## through October (each tree a little earlier or later than the next),
## drop in early November, and stand as grey-brown twig domes, the ground
## and snow showing through, until they leaf out pale green in mid-April
## (Seasons.look via the global season_look: autumn, bare, spring, dry).
static var _crown_mat: ShaderMaterial
const CROWN_SHADER := """
global uniform vec4 season_look;
void fragment() {
	float r = hash(floor(world_pos.xz / 9.0) + 0.37);
	float turn = clamp(season_look.x * 1.5 - r * 0.5, 0.0, 1.0);
	float bare = clamp(season_look.y * 1.4 - r * 0.4, 0.0, 1.0);
	float clumps = texture(noise_grain, world_pos.xz / 0.9 + world_pos.y * 0.5).r;
	// Leaf clusters a few metres across, lit tops and darker hollows.
	float masses = texture(noise_grain, world_pos.xz / 4.0 + world_pos.y * 0.25).r;
	vec3 leaf = vcol(COLOR.rgb) * (0.7 + clumps * 0.6) * (0.65 + masses * 0.7);
	// Maples scarlet to orange, ashes and lindens yellow, oaks a dull
	// russet brown that hangs on; in linear colour, muted as seen from far.
	vec3 fall = mix(vec3(0.26, 0.05, 0.02), vec3(0.38, 0.15, 0.02), r / 0.45);
	if (r > 0.45) fall = vec3(0.34, 0.25, 0.03);
	if (r > 0.75) fall = vec3(0.16, 0.09, 0.04);
	fall *= 0.72;
	leaf = mix(leaf, vec3(0.3, 0.28, 0.04), smoothstep(0.0, 0.5, turn) * (1.0 - smoothstep(0.5, 1.0, turn)));
	leaf = mix(leaf, fall, smoothstep(0.35, 1.0, turn));
	leaf = mix(leaf, leaf * vec3(1.45, 1.4, 0.55), season_look.z * 0.8);
	// Bare: a thin net of grey-brown twigs; most of the crown is open air.
	vec3 twig = vec3(0.16, 0.13, 0.11) * (0.8 + clumps * 0.4);
	float keep = mix(1.0, 0.38, bare);
	if (hash(floor(world_pos.xz / 0.6) + floor(world_pos.y / 0.6) * 17.0) > keep) {
		discard;
	}
	ALBEDO = mix(leaf, twig, bare);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""


static func _crown_material() -> ShaderMaterial:
	if _crown_mat == null:
		_crown_mat = HouseMaterials._shader(CROWN_SHADER)
	return _crown_mat


## Streetlights after dark (desktop): seen from the air a Midwest town at
## night is strings of light along every street, each pole's pool on the
## pavement and its lamp a bright point, not just lit windows. Cobra-head
## poles about 9 m tall throw a pool about 25 m across; spacing about
## 55 m on residential streets (every other or third lot line), 45 m on
## collectors and 38 m on arterials (IES RP-8 practice). Colour in the
## real mix of a town part way through its LED change-over: warm
## high-pressure sodium (about 2,100 K) and 4,000 K LED.
const POOL_SPACING := [55.0, 45.0, 38.0]
const POOL_RADIUS := 13.0
const SODIUM := Color(1.0, 0.55, 0.2)
const LED := Color(0.8, 0.78, 0.7)
const LOT_LIGHT := Color(2.2, 2.15, 2.0)
static var _pool_mat: ShaderMaterial
## The block being built's light arrays (vertices, colours, uvs).
var _lit: Array = []


static func _pool_material() -> ShaderMaterial:
	if _pool_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
global uniform float night;
varying float dist;
void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	float r = length(UV);
	float pool = exp(-r * r * 9.0) * 0.32;
	float lamp = exp(-r * r * 900.0) * 6.0;
	ALBEDO = COLOR.rgb * (pool + lamp) * smoothstep(0.25, 0.7, night) * exp(-0.00016 * dist);
}
"""
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = sh
	return _pool_mat


## One light's pool and lamp at c (region metres), into this block's lights.
func _pool(c: Vector2, tint: Color, scale: float, o: Vector2) -> void:
	var v: PackedVector3Array = _lit[0]
	var col: PackedColorArray = _lit[1]
	var uv: PackedVector2Array = _lit[2]
	var y := Terrain.height(c.x, c.y) + 0.5
	var x0 := c.x - o.x
	var z0 := c.y - o.y
	var r := POOL_RADIUS * scale
	var q := [Vector3(x0 - r, y, z0 - r), Vector3(x0 + r, y, z0 - r), Vector3(x0 + r, y, z0 + r), Vector3(x0 - r, y, z0 + r)]
	var t := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		v.append(q[k])
		uv.append(t[k])
		col.append(tint)


func _pools(pts: PackedVector2Array, kind: int, o: Vector2) -> void:
	var gap: float = POOL_SPACING[clampi(kind, 0, POOL_SPACING.size() - 1)]
	var next := gap * 0.5
	var run := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var l := a.distance_to(b)
		while next <= run + l:
			var c := a.lerp(b, (next - run) / maxf(l, 0.001))
			var h := absi(hash(Vector2i(int(c.x), int(c.y))))
			_pool(c, SODIUM if h % 5 < 3 else LED, 1.0, o)
			next += gap
		run += l


func _block(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x / float(BLOCK)), floori(c.y / float(BLOCK)))


## Adds a square to its block, and draws the block once it's whole.
func _build(c: Vector2i) -> void:
	var sq: Array = _todo[c]
	var blk: Array = _blocks[_block(c)]
	var v: PackedVector3Array = blk[1]
	var nrm: PackedVector3Array = blk[2]
	var col: PackedColorArray = blk[3]
	var uv: PackedVector2Array = blk[4]
	var o := _origin
	_lit = [blk[8], blk[9], blk[10]]
	for s in sq[1]:
		_street(v, nrm, col, s[1], WIDTHS[s[0]], o)
		if _trees > 0.0:
			_pools(s[1], s[0], o)
	var near := _street_grid(c) if _trees > 0.0 else {}
	for b in sq[0]:
		_building(v, nrm, col, uv, b, o)
		if _trees > 0.0:
			_yard_trees(blk[5], blk[6], blk[7], b, o)
			_driveway(v, nrm, col, b, near, o)
	blk[0] -= 1
	if blk[0] > 0 or v.is_empty():
		return
	uv.resize(v.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	if not blk[5].is_empty():
		var ta := []
		ta.resize(Mesh.ARRAY_MAX)
		ta[Mesh.ARRAY_VERTEX] = blk[5]
		ta[Mesh.ARRAY_NORMAL] = blk[6]
		ta[Mesh.ARRAY_COLOR] = blk[7]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
		mesh.surface_set_material(1, _crown_material())
	if not blk[8].is_empty():
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = blk[8]
		la[Mesh.ARRAY_COLOR] = blk[9]
		la[Mesh.ARRAY_TEX_UV] = blk[10]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, la)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _pool_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	_blocks.erase(_block(c))


func _street(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		pts: PackedVector2Array, width: float, o: Vector2) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length() < 0.5:
			continue
		var side := Vector2(-d.y, d.x).normalized() * width * 0.5
		var q := [a + side, a - side, b - side, b + side]
		var y := []
		for p in q:
			y.append(Terrain.height(p.x, p.y) + 0.2)
		var w := []
		for k in 4:
			w.append(Vector3(q[k].x - o.x, y[k], q[k].y - o.y))
		_quad(v, nrm, col, w[0], w[1], w[2], w[3], ASPHALT)
		if _trees > 0.0:
			# Sidewalks (desktop): Marion's streets have a 1.5 m concrete
			# walk on each side past a 2 m grass tree lawn, the pale lines
			# that frame every block from the air.
			for sgn: float in [-1.0, 1.0]:
				var n: Vector2 = side.normalized() * sgn
				var i0: Vector2 = n * (width * 0.5 + 2.0)
				var i1: Vector2 = n * (width * 0.5 + 3.5)
				var sw := [a + i0, a + i1, b + i1, b + i0]
				var sp := []
				for k in sw:
					sp.append(Vector3(k.x - o.x, Terrain.height(k.x, k.y) + 0.14, k.y - o.y))
				_quad(v, nrm, col, sp[0], sp[1], sp[2], sp[3], WALK)


func _building(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array,
		b: Array, o: Vector2) -> void:
	var centre := Vector2(b[0], b[1])
	var ang := deg_to_rad(b[5])
	var u: Vector2 = Vector2(cos(ang), sin(ang)) * b[2] * 0.5
	var w: Vector2 = Vector2(-sin(ang), cos(ang)) * b[3] * 0.5
	var corners := [centre - u - w, centre + u - w, centre + u + w, centre - u + w]
	var lo := INF
	for p in corners:
		lo = minf(lo, Terrain.height(p.x, p.y))
	var y0 := lo - 0.4
	var h: float = b[4]
	var y1 := lo + h
	var pick := absi(hash(Vector2i(b[0], b[1])))
	var area: float = b[2] * b[3]
	var house: bool = area < HOUSE_AREA and h < HOUSE_HEIGHT
	# Older two-storey-plus blocks of modest footprint read as downtown brick.
	var downtown: bool = not house and h >= 7.0 and area < LOT_AREA
	var walls: Array = HOUSE_WALLS if house else (BRICK if downtown else SHOP_WALLS)
	var wall: Color = walls[pick % walls.size()]
	wall.a = GLASS[0 if house else (2 if downtown else 1)]
	var pts := []
	for p in corners:
		pts.append(Vector2(p.x - o.x, p.y - o.y))
	var mid: Vector2 = (pts[0] + pts[2]) * 0.5
	if not house and not downtown and area >= LOT_AREA:
		_lot(v, nrm, col, centre, u, w, area, o)
	for k in 4:
		var a: Vector2 = pts[k]
		var c: Vector2 = pts[(k + 1) % 4]
		var away := (a + c) * 0.5 - mid
		uv.resize(v.size())
		var first := v.size()
		_quad(v, nrm, col, Vector3(a.x, y0, a.y), Vector3(c.x, y0, c.y), Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y),
			wall, Vector3(away.x, 0.0, away.y))
		# Windows: UVs in metres along and up the wall.
		var along := (c - a).normalized()
		for i in range(first, v.size()):
			uv.append(Vector2((Vector2(v[i].x, v[i].z) - a).dot(along) + 0.01, v[i].y - lo + 0.01))
	wall.a = 1.0
	if not house:
		var flat: Color = FLAT_ROOFS[(pick / 7) % FLAT_ROOFS.size()]
		if _trees > 0.0:
			# Desktop: a white membrane weathers to a dirty light grey within a
			# few years (aged TPO reflects about 0.6-0.7, fresh about 0.8), each
			# roof its own age; and the roof carries its heating and cooling.
			if flat.r > 0.7:
				flat = Color(0.80, 0.81, 0.80).lerp(Color(0.60, 0.60, 0.58), 0.45 + 0.4 * float(pick % 11) / 10.0)
			_roof_units(v, nrm, col, pts, y1, area, pick)
		_quad(v, nrm, col, Vector3(pts[0].x, y1, pts[0].y), Vector3(pts[3].x, y1, pts[3].y),
			Vector3(pts[2].x, y1, pts[2].y), Vector3(pts[1].x, y1, pts[1].y), flat)
		return
	# A gable roof along the longer side, pitched about 6 in 12.
	var roof: Color = ROOFS[(pick / 7) % ROOFS.size()]
	var long_u: bool = b[2] >= b[3]
	var span: float = (b[3] if long_u else b[2]) * 0.5
	var ridge := y1 + span * 0.5
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var p2: Vector2 = pts[2]
	var p3: Vector2 = pts[3]
	if not long_u:
		var t := p0
		p0 = p1
		p1 = p2
		p2 = p3
		p3 = t
	# Ridge from the middle of side p0-p3 to the middle of side p1-p2.
	var r0 := (p0 + p3) * 0.5
	var r1 := (p1 + p2) * 0.5
	var R0 := Vector3(r0.x, ridge, r0.y)
	var R1 := Vector3(r1.x, ridge, r1.y)
	_quad(v, nrm, col, Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), R1, R0, roof)
	_quad(v, nrm, col, Vector3(p2.x, y1, p2.y), Vector3(p3.x, y1, p3.y), R0, R1, roof)
	var e0 := r0 - mid
	var e1 := r1 - mid
	_tri(v, nrm, col, Vector3(p3.x, y1, p3.y), Vector3(p0.x, y1, p0.y), R0, wall, Vector3(e0.x, 0.0, e0.y))
	_tri(v, nrm, col, Vector3(p1.x, y1, p1.y), Vector3(p2.x, y1, p2.y), R1, wall, Vector3(e1.x, 0.0, e1.y))


## Packaged rooftop units on a flat-roofed store, office or plant
## (desktop): a commercial building is heated and cooled by boxes about
## 3 x 2 m and 1.4 m tall, roughly one per 450 m² of floor (aerial
## photos of Midwest big-box stores show 30-50 units on 15,000-20,000 m²
## of roof), galvanised or beige and darker than the membrane, set in rows
## down the middle of the roof with walkway room to the edge. From the
## backdrop's 450 m they read as rows of light dots with short shadows,
## the way every big-box roof does from the air.
func _roof_units(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		pts: Array, y1: float, area: float, pick: int) -> void:
	if area < 450.0:
		return
	var a: Vector2 = pts[0]
	var du: Vector2 = pts[1] - pts[0]
	var dw: Vector2 = pts[3] - pts[0]
	if du.length() < dw.length():
		var t := du
		du = dw
		dw = t
	var lu := du.length()
	var lw := dw.length()
	if lu < 14.0 or lw < 10.0:
		return
	var n := clampi(int(area / 450.0 + 0.5), 1, 60)
	var rows := clampi(int(round(sqrt(float(n) * lw / lu))), 1, 6)
	var per := ceili(float(n) / rows)
	var eu := du / lu
	var ew := dw / lw
	var grey := Color(0.56, 0.56, 0.53).lerp(Color(0.46, 0.47, 0.46), float(pick % 5) / 4.0)
	var side := grey.darkened(0.2)
	var k := 0
	for r in rows:
		var fw := (r + 1.0) / (rows + 1.0)
		for i in per:
			if k >= n:
				return
			k += 1
			var fu := (i + 1.0) / (per + 1.0)
			# A little scatter: units go where the ducts below need them.
			var h := absi(hash(Vector3i(pick, r, i)))
			fu += (float(h % 7) - 3.0) / 7.0 * 0.4 / (per + 1.0)
			var c := a + du * fu + dw * fw
			var hu := eu * (1.5 if h % 3 else 1.0)
			var hw := ew * 1.0
			var q := [c - hu - hw, c + hu - hw, c + hu + hw, c - hu + hw]
			var top := y1 + 1.4
			_quad(v, nrm, col, Vector3(q[0].x, top, q[0].y), Vector3(q[1].x, top, q[1].y),
				Vector3(q[2].x, top, q[2].y), Vector3(q[3].x, top, q[3].y), grey)
			for s in 4:
				var p0: Vector2 = q[s]
				var p1: Vector2 = q[(s + 1) % 4]
				var away := (p0 + p1) * 0.5 - c
				_quad(v, nrm, col, Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y),
					Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y), side, Vector3(away.x, 0.0, away.y))


## A house's yard trees (_trees per house on average): crowns in the front
## and back yards, off the short sides of the house, 10-14 m across and
## 12-17 m tall like a grown silver maple or pin oak, sitting on the trunk
## (too thin to see from the 450 m the camera keeps from the backdrop).
func _yard_trees(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, b: Array, o: Vector2) -> void:
	if b[2] * b[3] >= HOUSE_AREA or b[4] >= HOUSE_HEIGHT:
		return
	var pick := absi(hash(Vector2i(b[0] * 3 + 1, b[1] * 5 + 2)))
	var n := int(_trees) + (1 if float(pick % 1000) / 1000.0 < fposmod(_trees, 1.0) else 0)
	var ang := deg_to_rad(b[5])
	var u := Vector2(cos(ang), sin(ang))
	var w := Vector2(-sin(ang), cos(ang))
	for i in n:
		var h := absi(hash(pick + i * 7919))
		var f := float(h % 997) / 997.0
		var g := float((h / 997) % 991) / 991.0
		# Front or back yard, 5-9 m off the wall, anywhere along the house.
		var side := 1.0 if (h / 13) % 2 == 0 else -1.0
		if i == 1:
			side = -side
		var p: Vector2 = Vector2(b[0], b[1]) + w * side * (b[3] * 0.5 + 5.0 + f * 4.0) + u * (g - 0.5) * (b[2] + 6.0)
		var r := 5.0 + f * 2.0
		var ground := Terrain.height(p.x, p.y)
		var base := ground + 3.0 + g * 1.5
		var mid := base + r * 0.8
		var c: Color = CROWNS[h % CROWNS.size()]
		var x: float = p.x - o.x
		var z: float = p.y - o.y
		# A dome: the widest ring, a narrower one above it, a low apex; and
		# a shallow underside down to the trunk.
		var rings := [[mid, r], [mid + r * 0.55, r * 0.72]]
		var pts := []
		for ring in rings:
			var row := []
			for k in 7:
				var a := TAU * (k + f) / 7.0
				row.append(Vector3(x + cos(a) * ring[1], ring[0], z + sin(a) * ring[1]))
			pts.append(row)
		var t := Vector3(x, mid + r * (0.85 + g * 0.2), z)
		var bt := Vector3(x, base, z)
		var cen := Vector3(x, mid, z)
		var under := c * Color(0.75, 0.75, 0.75, 1.0)
		var first := v.size()
		for k in 7:
			var k1 := (k + 1) % 7
			var a: Vector3 = pts[0][k]
			var d: Vector3 = pts[0][k1]
			var a2: Vector3 = pts[1][k]
			var d2: Vector3 = pts[1][k1]
			var out := (a + d) * 0.5 - cen
			_quad(v, nrm, col, a, d, d2, a2, c, out + Vector3(0, r * 0.6, 0))
			_tri(v, nrm, col, a2, d2, t, c, out * 0.5 + Vector3(0, r, 0))
			_tri(v, nrm, col, a, d, bt, under, out - Vector3(0, r * 0.5, 0))
		# A crown is a rounded mass of leaves, not a cut gem: shade it with
		# normals from its middle (a squashed sphere), so light rolls round
		# it smoothly instead of lighting seven flat facets.
		var ec := Vector3(x, mid - r * 0.15, z)
		for idx in range(first, v.size()):
			nrm[idx] = ((v[idx] - ec) * Vector3(1.0, 1.4, 1.0)).normalized()


## The parking lot round a store or plant: its footprint grown on every side
## until the asphalt is LOT_SHARE times the floor.
func _lot(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		centre: Vector2, u: Vector2, w: Vector2, area: float, o: Vector2) -> void:
	var lu := u.length()
	var lw := w.length()
	# (2lu + 2m)(2lw + 2m) = (1 + share) area, solved for the margin m.
	var s := lu + lw
	var m := (-s + sqrt(s * s + LOT_SHARE * area)) * 0.5
	var gu := u.normalized() * (lu + m)
	var gw := w.normalized() * (lw + m)
	var q := [centre - gu - gw, centre + gu - gw, centre + gu + gw, centre - gu + gw]
	var p := []
	for c in q:
		p.append(Vector3(c.x - o.x, Terrain.height(c.x, c.y) + 0.15, c.y - o.y))
	_quad(v, nrm, col, p[0], p[1], p[2], p[3], LOT_ASPHALT)
	if _trees > 0.0 and m > 12.0:
		_parked(v, nrm, col, centre, u, w, m, o)
	if _trees > 0.0:
		# Lot lights: poles about 30 m apart round the store, brighter and
		# whiter (LED or metal halide, 2-5 footcandles) than the street, so
		# from the air at night the shopping strips are the brightest patches.
		var e1 := u.normalized()
		var e2 := w.normalized()
		var hu := lu + m * 0.5
		var hw := lw + m * 0.5
		for side in 4:
			var along := e1 if side % 2 == 0 else e2
			var out := (e2 if side % 2 == 0 else e1) * (hw if side % 2 == 0 else hu) * (1.0 if side < 2 else -1.0)
			var half := hu if side % 2 == 0 else hw
			var n := maxi(1, int(half * 2.0 / 30.0))
			for i in n:
				var t := -half + (i + 0.5) * half * 2.0 / n
				_pool(centre + out + along * t, LOT_LIGHT, 1.5, o)


## This square's and its neighbours' street segments, filed by 40 m cell:
## cell -> [[a, b, half width], ...].
func _street_grid(c: Vector2i) -> Dictionary:
	var grid := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var sq: Array = _todo.get(c + Vector2i(dx, dz), [])
			if sq.is_empty():
				continue
			for st in sq[1]:
				var pts: PackedVector2Array = st[1]
				var hw: float = WIDTHS[st[0]] * 0.5
				for i in pts.size() - 1:
					var a := pts[i]
					var e := pts[i + 1]
					var lo := (Vector2(minf(a.x, e.x), minf(a.y, e.y)) / DRIVE_CELL).floor()
					var hi := (Vector2(maxf(a.x, e.x), maxf(a.y, e.y)) / DRIVE_CELL).floor()
					for gx in range(int(lo.x), int(hi.x) + 1):
						for gz in range(int(lo.y), int(hi.y) + 1):
							var k := Vector2i(gx, gz)
							if not grid.has(k):
								grid[k] = []
							grid[k].append([a, e, hw])
	return grid


## A house's driveway (desktop): nearly every Marion house has one, a
## strip of pale concrete or asphalt about 3 m wide from beside the house
## (the garage end) straight to the street, the way it reads from the air.
const DRIVE_CELL := 40.0
const DRIVE_WIDTH := 3.2
const DRIVE_COLOURS := [Color(0.60, 0.59, 0.56), Color(0.55, 0.54, 0.52), Color(0.36, 0.36, 0.36)]


func _driveway(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		b: Array, grid: Dictionary, o: Vector2) -> void:
	if b[2] * b[3] >= HOUSE_AREA or b[4] >= HOUSE_HEIGHT:
		return
	var c := Vector2(b[0], b[1])
	var cell := (c / DRIVE_CELL).floor()
	var best := INF
	var bp := Vector2.ZERO
	var bhw := 0.0
	for gx in range(int(cell.x) - 1, int(cell.x) + 2):
		for gz in range(int(cell.y) - 1, int(cell.y) + 2):
			for seg in grid.get(Vector2i(gx, gz), []):
				var p := Geometry2D.get_closest_point_to_segment(c, seg[0], seg[1])
				var d := p.distance_squared_to(c)
				if d < best:
					best = d
					bp = p
					bhw = seg[2]
	if best > 45.0 * 45.0:
		return
	var ang := deg_to_rad(b[5])
	var u := Vector2(cos(ang), sin(ang))
	var w := Vector2(-sin(ang), cos(ang))
	var to := bp - c
	# The wall that faces the street, and the axis along it.
	var n := u if absf(to.dot(u)) > absf(to.dot(w)) else w
	if to.dot(n) < 0.0:
		n = -n
	var along := w if n.is_equal_approx(u) or n.is_equal_approx(-u) else u
	var depth: float = (b[2] if along.is_equal_approx(w) or along.is_equal_approx(-w) else b[3]) * 0.5
	var length: float = (b[3] if along.is_equal_approx(w) or along.is_equal_approx(-w) else b[2]) * 0.5
	var pick := absi(hash(Vector2i(int(b[0] * 7.0), int(b[1] * 3.0))))
	var side := 1.0 if pick % 2 == 0 else -1.0
	# Beside the house at its garage end: just past the end wall.
	var start := c + along * side * (length + DRIVE_WIDTH * 0.5 + 0.5) + n * (depth - 6.0)
	var reach := (bp - start).dot(n) - bhw + 0.5
	if reach < 3.0 or reach > 35.0:
		return
	var tint: Color = DRIVE_COLOURS[pick % DRIVE_COLOURS.size()]
	var hw := along * DRIVE_WIDTH * 0.5
	var q := [start - hw, start + hw, start + hw + n * reach, start - hw + n * reach]
	var p := []
	for k in q:
		p.append(Vector3(k.x - o.x, Terrain.height(k.x, k.y) + 0.12, k.y - o.y))
	_quad(v, nrm, col, p[0], p[1], p[2], p[3], tint)


## Cars parked in a store's lot (desktop): 90-degree stalls 2.75 m wide
## and 5.5 m deep in double-loaded bays with 7.3 m aisles (ITE / ULI
## parking design norms), starting past a 7 m sidewalk and fire lane.
## Daytime lots run about half full, fullest near the doors, the back lot
## mostly staff. Colours in the real US mix (white, black, grey and silver
## about three in four cars; then blue, red, the odd brown or green).
func _parked(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		centre: Vector2, u: Vector2, w: Vector2, m: float, o: Vector2) -> void:
	var a := u
	var b := w
	if a.length() < b.length():
		a = w
		b = u
	var la := a.length()
	var lb := b.length()
	var ea := a / la
	var eb := b / lb
	var seed := absi(hash(Vector2i(int(centre.x), int(centre.y))))
	for side in [-1.0, 1.0]:
		var fill := 0.6 if side < 0.0 else 0.25
		var rows := []
		var d := 7.0
		while d + 5.5 <= m - 1.0:
			rows.append(d)
			if rows.size() % 2 == 1:
				d += 5.5 + 7.3
			else:
				d += 5.5
		for ri in rows.size():
			var near: float = 1.0 - 0.6 * float(ri) / maxf(rows.size(), 1.0)
			var x := -la + 2.0
			var k := 0
			while x <= la - 2.0:
				k += 1
				var h := absi(hash(Vector3i(seed, ri * 2 + int(side > 0.0), k)))
				if float(h % 1000) / 1000.0 < fill * near:
					var c: Vector2 = centre + ea * x + eb * side * (lb + rows[ri] + 2.75)
					_car(v, nrm, col, c, ea, eb, h, o)
				x += 2.75


const CAR_COLOURS := [Color(0.82, 0.82, 0.80), Color(0.82, 0.82, 0.80), Color(0.06, 0.06, 0.07),
	Color(0.06, 0.06, 0.07), Color(0.36, 0.37, 0.38), Color(0.36, 0.37, 0.38), Color(0.62, 0.63, 0.64),
	Color(0.14, 0.22, 0.40), Color(0.50, 0.08, 0.07), Color(0.30, 0.24, 0.18), Color(0.16, 0.24, 0.17),
	Color(0.82, 0.82, 0.80)]


## One parked car or pickup as a low box nose to the aisle, 4.7 x 1.85 m
## and 1.5 m tall (a pickup 5.8 m and 1.9 m).
func _car(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		c: Vector2, along: Vector2, across: Vector2, h: int, o: Vector2) -> void:
	var truck := h % 5 == 0
	var half_l := (2.9 if truck else 2.35)
	var half_w := 0.93
	var top := Terrain.height(c.x, c.y) + (1.9 if truck else 1.5)
	var body: Color = CAR_COLOURS[(h / 7) % CAR_COLOURS.size()]
	var side := body.darkened(0.25)
	var q := [c - across * half_l - along * half_w, c + across * half_l - along * half_w,
		c + across * half_l + along * half_w, c - across * half_l + along * half_w]
	var lo := top - (1.9 if truck else 1.5) + 0.15
	var pts := []
	for p in q:
		pts.append(Vector2(p.x - o.x, p.y - o.y))
	var mid := Vector2(c.x - o.x, c.y - o.y)
	_quad(v, nrm, col, Vector3(pts[0].x, top, pts[0].y), Vector3(pts[1].x, top, pts[1].y),
		Vector3(pts[2].x, top, pts[2].y), Vector3(pts[3].x, top, pts[3].y), body)
	for s in 4:
		var p0: Vector2 = pts[s]
		var p1: Vector2 = pts[(s + 1) % 4]
		var away := (p0 + p1) * 0.5 - mid
		_quad(v, nrm, col, Vector3(p0.x, lo, p0.y), Vector3(p1.x, lo, p1.y),
			Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y), side, Vector3(away.x, 0.0, away.y))


## Two triangles, a b c d round the face's edge; the face looks toward `out`.
static func _quad(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color, out := Vector3.UP) -> void:
	_tri(v, nrm, col, a, b, c, colour, out)
	_tri(v, nrm, col, a, c, d, colour, out)


static func _tri(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, colour: Color, out := Vector3.UP) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-8:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# Godot's fronts wind clockwise as seen from the front.
	v.append_array([a, c, b])
	nrm.append_array([n, n, n])
	col.append_array([colour, colour, colour])
