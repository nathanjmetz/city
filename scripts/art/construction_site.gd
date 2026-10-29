class_name ConstructionSite
extends Node3D
## A building going up, shown stage by stage (see Construction) instead of
## popping in. Every view that draws buildings hands it the finished meshes
## its builder made and a way to ask the simulation how far along it is; it
## works out everything else from the finished building itself:
##
##   clear       bare dirt, silt fence, the builder's sign, a porta-john
##   foundation  footings and slab poured, rising out of the ground
##   frame       the structure goes up piece by piece (FrameBuilder: studs,
##               steel, posts or tilt-up panels), lumber stacked on the lot
##   dry_in      sheathing and wrap climb the frame (house wrap and roofing
##               felt, block, metal panels or roof deck)
##   exterior    the finished outside replaces the wrap from the bottom up
##   interior    looks done, but the dumpster and the trades are still there
##   landscape   the yard goes in; when it's done the trees are planted
##
## Cheap on the web build: the frame's members are drawn only within NEAR of
## the camera; farther away the frame stage is the finished shape clipped to
## its height in bare lumber or steel, one draw call. Everything extra is
## freed once the building is finished.
##
## A surface parking lot ("paving") is built the way a paving contractor
## does it instead: cleared and graded dirt, a crushed-stone base rolled in
## from the front back, curbs, light poles and signs set, fresh black
## asphalt laid in lanes from the front back, then striped and planted.
##
## Benchmark: Cities: Skylines 2 hides a new building in a scaffold box.

signal finished

## Metres from the camera within which the frame is drawn member by member.
const NEAR := 170.0
## Seconds between looks at the clock.
const POLL := 0.25
const DIRT := Color("#6e5a43")
## Buildings taller than this (metres, about six storeys) go up under a tower crane.
const CRANE_FROM := 24.0
const CONCRETE := Color("#b3afa6")
## Oriented strand board sheathing, and the share of dry-in it takes.
const OSB := Color("#c29b62")
const SHEATHE := 0.45
## Wall and roof colours of each method's shell while it's being closed in.
const SHELL := {
	"house": [Color("#e9eae6"), Color("#2f2e2d")],   # house wrap, roofing felt
	"shop": [Color("#a8a49b"), Color("#8e959a")],    # concrete block, steel deck
	"civic": [Color("#a8a49b"), Color("#8e959a")],
	"factory": [Color("#c4c8ca"), Color("#b4b9bb")], # bare galvalume panels
	"warehouse": [Color("#b9b5ab"), Color("#8e959a")],  # tilt-up concrete, deck
	"barn": [Color("#aab1b5"), Color("#aab1b5")],    # galvanized steel
	"power_feed": [Color("#7a6248"), Color("#7a6248")],  # creosoted poles
	"well": [Color("#a8a49b"), Color("#8e959a")],    # block pump house, steel deck
}
## What the frame looks like from far away.
const FRAME_FAR := {"wood": FrameBuilder.LUMBER, "steel": FrameBuilder.PRIMER, "pole": FrameBuilder.LUMBER,
	"tilt_up": FrameBuilder.PANEL}

static var _shader: Shader

var _built: Array
var _state: Callable
var _profile := "house"
var _final := MeshInstance3D.new()
var _ground := MeshInstance3D.new()
var _found: MeshInstance3D
var _shell: MeshInstance3D
var _forms: MeshInstance3D  # the footing forms while the concrete goes in
var _pad: MeshInstance3D
var _props: MeshInstance3D
var _frame: Array = []  # MeshInstance3D per FrameBuilder chunk
var _footing: Node3D
var _frame_kind := "wood"
var _height := 6.0
var _found_h := 0.45
var _box := AABB()
var _bldg := AABB()  # the finished building's own bounds (not its lot)
var _core := AABB()  # the walls and roof alone, without the walks, fences and yard things
var _crane_on := false  # a high-rise: it goes up under a tower crane
var _props_for := ""
var _paving := false
var _entrance: MeshInstance3D  # the stone construction entrance
var _drive_x := 0.0  # where the entrance comes in off the street
var _drive_w := 3.7
var _drive_len := 9.0
var _stone: MeshInstance3D
var _mat: MeshInstance3D
var _laid := {}  # paving layer -> how far back it was last drawn
var _wait := 0.0
var _done := false


## Puts `built` under `root` going up stage by stage; `plant` is called
## (with no arguments) once the yard is done, or straight away if it already
## is. `footing`, if given, is the foundation below grade on a slope: it
## shows from the foundation stage on. The one call every view makes.
static func add_to(root: Node3D, built: Array, profile: String, state: Callable, plant: Callable,
		footing: Node3D = null) -> ConstructionSite:
	var site := ConstructionSite.new()
	root.add_child(site)
	site.finished.connect(plant)
	if footing != null:
		site.add_child(footing)
		site._footing = footing
	site.setup(built, profile, state)
	if not site.building():
		plant.call()
	return site


## `built` is a builder's [building mesh, ground mesh, ...]; `state` returns
## Construction's state for this building ({} once it's finished).
func setup(built: Array, profile: String, state: Callable) -> void:
	_built = built
	_profile = profile if SHELL.has(profile) else "house"
	_paving = profile == "paving"
	_state = state
	_final.mesh = built[0]
	add_child(_final)
	_ground.mesh = built[1]
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)
	var st: Dictionary = state.call()
	if st.is_empty():
		_done = true
		set_process(false)
		return
	_frame_kind = st.frame
	_found_h = FrameBuilder.slab_top(built[0], st.found)
	var aabb: AABB = built[0].get_aabb()
	_height = aabb.end.y
	_bldg = aabb
	_core = _core_box(built[0], aabb)
	_crane_on = not _paving and _height > CRANE_FROM and _mostly_tall(built[0])
	_box = aabb
	if built[1] != null and built[1].get_surface_count() > 0:
		_box = _box.merge(built[1].get_aabb())
	if aabb.position.z >= 0.0:
		# Lots start at the street edge (z = 0): keep the dirt off the sidewalk.
		var cut := maxf(_box.position.z, 0.0)
		_box.size.z = _box.end.z - cut
		_box.position.z = cut
	_box = _box.grow(1.0)
	_make_pad()
	_show(st)


## True while the building is still going up.
func building() -> bool:
	return not _done


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = POLL
	_show(_state.call())


func _show(st: Dictionary) -> void:
	if st.is_empty():
		_finish()
		return
	var stage: String = st.name
	var t: float = st.t
	if _paving:
		_show_paving(stage, t)
		return
	var near := _near()
	_final.visible = stage in ["exterior", "interior", "landscape"]
	_ground.visible = stage == "landscape"
	_pad.visible = stage != "landscape"
	# The stone comes up with the topsoil when the drive is poured.
	_entrance.visible = stage != "landscape"
	if _footing != null:
		_footing.visible = stage != "clear"
	# Footings and slab: the finished shape clipped low, in fresh concrete.
	var show_found := stage in ["foundation", "frame", "dry_in"]
	if show_found and _found == null:
		_found = _clipped(CONCRETE, CONCRETE)
		_param(_found, "keep", _plan_keep())
	if _found != null:
		_found.visible = show_found
		if show_found:
			var h := _found_h * clampf(t * 1.4, 0.15, 1.0) if stage == "foundation" else _found_h
			_param(_found, "cut", h)
	# Forms set round the footings before the pour and stripped after:
	# aluminum wall forms on a house, lumber edge forms on a slab.
	var show_forms := stage == "foundation" and t < 0.75
	if show_forms and _forms == null:
		var fc := Color("#a7abae") if _profile == "house" else Color("#c4a26e")
		_forms = _clipped(fc, fc)
		_param(_forms, "inflate", 0.07)
		_param(_forms, "walls_only", true)
		_param(_forms, "cut", _found_h + 0.15)
		_param(_forms, "keep", _plan_keep())
	if _forms != null:
		_forms.visible = show_forms
	# The frame, member by member up close.
	var frame_chunks := 0
	if stage == "frame":
		frame_chunks = clampi(ceili(t * FrameBuilder.CHUNKS + 0.01), 1, FrameBuilder.CHUNKS)
	elif stage == "dry_in":
		frame_chunks = FrameBuilder.CHUNKS
	if frame_chunks > 0 and near and _frame.is_empty():
		for m in FrameBuilder.build(_plan_only(_built[0]), _frame_kind):
			var mi := MeshInstance3D.new()
			mi.mesh = m
			add_child(mi)
			_frame.append(mi)
	for i in _frame.size():
		_frame[i].visible = near and i < frame_chunks * _frame.size() / FrameBuilder.CHUNKS
	# The shell: a far stand-in for the frame, then the wrap going on, then
	# the wrap coming off as the finished outside goes on under it.
	var shell_on := stage == "dry_in" or stage == "exterior" or stage == "frame" and not near
	if shell_on and _shell == null:
		_shell = _clipped(Color.WHITE, Color.WHITE)
		_param(_shell, "keep", _plan_keep())
	if _shell != null:
		_shell.visible = shell_on
		if shell_on:
			var colors: Array = SHELL[_profile]
			var span := _height - _found_h
			# Never in the same plane as anything else drawn: the stand-in
			# starts above the foundation, and the wrap stands proud of the
			# frame and then of the finished walls.
			if stage == "frame":
				_shell_look(FRAME_FAR[_frame_kind], FRAME_FAR[_frame_kind], 0.0)
				_param(_shell, "pattern", 0)
				_param(_shell, "cut", _found_h + span * t)
				_param(_shell, "floor_cut", _found_h)
			elif stage == "dry_in" and _frame_kind == "wood" and t < SHEATHE:
				# Sheathing first: OSB nailed on in 4 x 8 ft sheets, walls
				# and roof deck, climbing the frame; the wrap and felt follow.
				_shell_look(OSB, OSB.darkened(0.05), 0.04)
				_param(_shell, "pattern", 3)
				_param(_shell, "cut", _found_h + span * t / SHEATHE)
				_param(_shell, "floor_cut", _found_h)
			elif stage == "dry_in":
				_shell_look(colors[0], colors[1], 0.04)
				_param(_shell, "pattern", _wrap_pattern())
				var w := (t - SHEATHE) / (1.0 - SHEATHE) if _frame_kind == "wood" else t
				_param(_shell, "cut", _found_h + span * w)
				_param(_shell, "floor_cut", _found_h)
			else:
				# The roof was shingled while it was dried in: only walls are wrapped.
				_shell_look(colors[0], colors[1], 0.08)
				_param(_shell, "pattern", _wrap_pattern())
				_param(_shell, "cut", 1000.0)
				_param(_shell, "floor_cut", _found_h + span * t)
	_final.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_props_look(stage)


## A parking lot going in: grade, stone base, curbs and poles, asphalt,
## then the striped lot itself.
func _show_paving(stage: String, t: float) -> void:
	var i := Construction.STAGES.find(stage)
	_final.visible = i >= 2  # curbs, light poles and signs go in before the paving
	_ground.visible = i >= 4
	_pad.visible = i <= 3
	_entrance.visible = i <= 1
	if _footing != null:
		_footing.visible = i >= 2
	# Crushed stone (#53 base, compacted), rolled in from the street back.
	_stone = _layer(_stone, "stone", Color("#8e8a81"), 0.12, (t if i == 1 else 1.0) if i >= 1 and i <= 3 else 0.0)
	# Hot-mix asphalt, laid in lanes from the street back: fresh and black.
	_mat = _layer(_mat, "asphalt", Color("#26272a"), 0.14, t if i == 3 else 0.0)
	_props_look(stage)


## A paving layer over the site's front `frac` (0 hides it), redrawn only
## when it has moved on.
func _layer(mi: MeshInstance3D, key: String, col: Color, y: float, frac: float) -> MeshInstance3D:
	frac = snappedf(clampf(frac, 0.0, 1.0), 0.05)
	if mi != null:
		mi.visible = frac > 0.0
	if frac <= 0.0 or is_equal_approx(float(_laid.get(key, -1.0)), frac):
		return mi
	_laid[key] = frac
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = _dirt_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var b := _box.grow(-0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 6
	for a in n:
		for c in n:
			for q in [[a, c], [a + 1, c], [a + 1, c + 1], [a, c], [a + 1, c + 1], [a, c + 1]]:
				var h := fposmod(sin(q[0] * 12.9898 + q[1] * 78.233) * 43758.5453, 1.0)
				st.set_color(col.lightened(h * 0.05))
				st.add_vertex(Vector3(b.position.x + b.size.x * q[0] / n, y, b.position.z + b.size.z * frac * q[1] / n))
	mi.mesh = st.commit()
	var root := get_parent() as Node3D
	if root != null and root.is_inside_tree():
		mi.mesh = Terrain.drape_local(mi.mesh, root.transform)
	return mi


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_final.visible = true
	_ground.visible = true
	if _footing != null:
		_footing.visible = true
	for n in [_found, _forms, _shell, _pad, _entrance, _props, _stone, _mat]:
		if n != null:
			n.queue_free()
	for n in _frame:
		n.queue_free()
	_frame.clear()
	_found = null
	_shell = null
	_forms = null
	_pad = null
	_entrance = null
	_props = null
	_stone = null
	_mat = null
	finished.emit()


func _near() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return true
	return cam.global_position.distance_to(global_position) < NEAR


# ---------------------------------------------------------------- shells

## The finished building's mesh drawn plain in two colours (walls, roofs)
## and clipped to a height band.
## The windows are in by then: a house is dried in with its windows set in
## the wrap (photos of houses at dry-in show dark openings in white wrap),
## so the glass is drawn dark in every shell, never wrapped over.
func _clipped(wall: Color, roof: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _built[0]
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	mat.set_shader_parameter("wall_color", wall)
	mat.set_shader_parameter("roof_color", roof)
	var glazed := mat.duplicate() as ShaderMaterial
	glazed.set_shader_parameter("wall_color", GLAZING)
	glazed.set_shader_parameter("roof_color", GLAZING)
	glazed.set_shader_parameter("glazing", true)
	var glass := HouseMaterials.get_mat("glass")
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, glazed if mi.mesh.surface_get_material(i) == glass else mat)
	mi.set_meta("mats", [mat, glazed])
	add_child(mi)
	return mi


## New windows in a wrapped wall, seen from outside: dark glass.
const GLAZING := Color("#262c31")


func _shell_look(wall: Color, roof: Color, inflate: float) -> void:
	var mats: Array = _shell.get_meta("mats")
	for mat: ShaderMaterial in mats:
		mat.set_shader_parameter("walls_only", inflate > 0.06)
		mat.set_shader_parameter("inflate", inflate)
	mats[0].set_shader_parameter("wall_color", wall)
	mats[0].set_shader_parameter("roof_color", roof)


## The finished drawing cut to the building's plan (_plan_keep), as bare
## triangles for FrameBuilder: the lot's light poles, bollards and yard
## fence aren't framed as if they were part of the building.
func _plan_only(mesh: Mesh) -> Mesh:
	var k := _plan_keep()
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var indexed: bool = idx != null and idx.size() > 0
		var count: int = idx.size() if indexed else v.size()
		var kept := PackedInt32Array()
		for i in range(0, count - 2, 3):
			var a: int = idx[i] if indexed else i
			var b: int = idx[i + 1] if indexed else i + 1
			var c: int = idx[i + 2] if indexed else i + 2
			var m := (v[a] + v[b] + v[c]) / 3.0
			if m.x >= k.x and m.z >= k.y and m.x <= k.z and m.z <= k.w:
				kept.append_array([a, b, c])
		if kept.is_empty():
			continue
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = v
		na[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	return out if out.get_surface_count() > 0 else mesh


## The building's plan with a little room for porches and stoops.
func _plan_keep() -> Vector4:
	var g := _core.grow(0.6)
	return Vector4(g.position.x, g.position.z, g.end.x, g.end.z)


## What the closed-in walls show: house wrap's print and felt laps on a
## house, block coursing where the walls are concrete block.
func _wrap_pattern() -> int:
	if _profile == "house":
		return 1
	return 2 if _profile in ["shop", "civic", "well"] else 0


static func _param(mi: MeshInstance3D, param: String, v: Variant) -> void:
	for mat: ShaderMaterial in mi.get_meta("mats"):
		mat.set_shader_parameter(param, v)


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float cut = 1000.0;
uniform float floor_cut = -1000.0;
uniform float inflate = 0.0;
uniform bool walls_only = false;
uniform bool glazing = false;
uniform vec3 wall_color : source_color = vec3(0.9);
uniform vec3 roof_color : source_color = vec3(0.3);
// 0 plain, 1 house wrap (printed rows, felt laps on the roof), 2 block.
uniform int pattern = 0;
// Drawn only inside this plan rectangle (x0, z0, x1, z1): the footings
// go under the building, not under its yard fence and walks.
uniform vec4 keep = vec4(-1e6, -1e6, 1e6, 1e6);
varying vec3 lp;
varying vec3 ln;
varying float plant;
void vertex() {
	VERTEX += NORMAL * inflate;
	lp = VERTEX;
	ln = NORMAL;
	// Foundation shrubs ride in the building mesh: they aren't planted yet.
	plant = COLOR.g > COLOR.r * 1.2 && COLOR.g > COLOR.b * 1.25 ? 1.0 : 0.0;
}
void fragment() {
	if (lp.x < keep.x || lp.z < keep.y || lp.x > keep.z || lp.z > keep.w) {
		discard;
	}
	if (lp.y > cut || lp.y < floor_cut || plant > 0.5 || walls_only && abs(ln.y) > 0.3 && !glazing) {
		discard;
	}
	ALBEDO = abs(ln.y) > 0.3 ? roof_color : wall_color;
	ROUGHNESS = 0.9;
	float run = abs(ln.x) > abs(ln.z) ? lp.z : lp.x;
	if (pattern == 1 && !glazing) {
		if (abs(ln.y) <= 0.3) {
			// House wrap comes in 9 ft rolls run round the house: the
			// maker's print in a row along each roll, a taped lap between.
			float row = fract(lp.y / 2.74);
			float dash = step(0.5, fract(run / 1.5)) * step(0.47, row) * step(row, 0.53);
			ALBEDO = mix(ALBEDO, vec3(0.32, 0.42, 0.58), dash * 0.55);
			ALBEDO *= 1.0 - 0.06 * step(row, 0.015);
		} else {
			// Felt laid in 3 ft courses up the roof, each lap a pale line.
			ALBEDO = mix(ALBEDO, vec3(0.55), step(fract(lp.y / 0.33), 0.04) * 0.5);
		}
	} else if (pattern == 3 && !glazing) {
		// 4 x 8 ft sheets, long side across the studs, joints staggered;
		// each sheet's strands a touch lighter or darker than the next.
		float u = abs(ln.y) <= 0.3 ? run : lp.x + lp.z;
		float course = floor(lp.y / 1.22);
		float across = floor(u / 2.44 + 0.5 * mod(course, 2.0));
		float joint = step(fract(lp.y / 1.22), 0.012) + step(fract(u / 2.44 + 0.5 * mod(course, 2.0)), 0.006);
		float shade = fract(sin(dot(vec2(course, across), vec2(12.9898, 78.233))) * 43758.5453);
		ALBEDO *= (0.92 + 0.14 * shade) * (1.0 - 0.3 * min(joint, 1.0));
	} else if (pattern == 2 && !glazing && abs(ln.y) <= 0.3) {
		// 8 x 16 in concrete block in running bond, mortar a shade darker.
		float course = floor(lp.y / 0.203);
		float joint = step(fract(lp.y / 0.203), 0.05) + step(fract(run / 0.406 + 0.5 * mod(course, 2.0)), 0.025);
		ALBEDO *= 1.0 - 0.18 * min(joint, 1.0);
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"""
	return _shader


# ---------------------------------------------------------------- the lot

## Bare, graded dirt over the whole site, with a little variation, and
## the stone construction entrance every stormwater permit asks for
## (Indiana's Rule 5 / IDEM Storm Water Quality Manual, EPA SWPPP detail):
## a pad of 2-3" crushed stone from the street in, about 12 ft wide on a
## house lot and 20 ft by 50 ft on a bigger job, so trucks shed their mud
## before they reach the road. Each mesh keeps (across the drive, in from
## the street) in UV for the ground shader's ruts.
func _make_pad() -> void:
	var commercial := _profile != "house" and _profile != "barn"
	_drive_w = 6.1 if commercial else 3.7
	_drive_len = minf(15.2 if commercial else 9.0, _box.size.z * 0.45)
	# Along the dumpster's side, so the roll-off truck backs in off the stone.
	_drive_x = _box.end.x - 0.8 - 2.6 - _drive_w * 0.5
	if _drive_x - _drive_w * 0.5 < _box.position.x + 1.0:
		_drive_x = _box.get_center().x
	_pad = _ground_patch(Rect2(_box.position.x, _box.position.z, _box.size.x, _box.size.z), 0.1,
		DIRT, 0.07, _site_mat(false))
	_entrance = _ground_patch(Rect2(_drive_x - _drive_w * 0.5, _box.position.z, _drive_w, _drive_len), 0.115,
		STONE, 0.04, _site_mat(true))


## A flat patch of ground at height `y`, tinted in soft blotches about
## `vary` either way, draped on the land like the yard will be.
func _ground_patch(r: Rect2, y: float, col: Color, vary: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 6
	var at := func(i: int, j: int) -> Vector3:
		return Vector3(r.position.x + r.size.x * i / n, y, r.position.y + r.size.y * j / n)
	var tint := func(i: int, j: int) -> Color:
		var h := fposmod(sin(i * 12.9898 + j * 78.233 + r.position.x) * 43758.5453, 1.0)
		return col.lightened((h - 0.5) * vary * 2.0) if h > 0.5 else col.darkened((0.5 - h) * vary * 2.0)
	for i in n:
		for j in n:
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var v: Vector3 = at.call(c[0], c[1])
				st.set_color(tint.call(c[0], c[1]))
				st.set_uv(Vector2(v.x - _drive_x, v.z - _box.position.z))
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var root := get_parent() as Node3D
	if root != null and root.is_inside_tree():
		mi.mesh = Terrain.drape_local(mi.mesh, root.transform)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static var _dirt: StandardMaterial3D
static var _props_mat: StandardMaterial3D


## The site's things in the colours they're written in (sRGB), so black
## silt fence reads black and a blue porta-john its own blue.
static func _prop_mat() -> StandardMaterial3D:
	if _props_mat == null:
		_props_mat = FrameBuilder.material().duplicate()
		_props_mat.vertex_color_is_srgb = true
	return _props_mat
static var _site_mats := {}


static func _dirt_mat() -> StandardMaterial3D:
	if _dirt == null:
		_dirt = StandardMaterial3D.new()
		_dirt.vertex_color_use_as_albedo = true
		_dirt.vertex_color_is_srgb = true
		_dirt.roughness = 1.0
	return _dirt


## The site's ground: graded clay with damp low spots and the ruts of the
## trucks and skid steer worn in from the entrance, or the entrance's
## crushed stone with mud tracked onto its inner end. The desktop's High
## tier and up lays the photographed mud and gravel (PhotoGround) over it.
static func _site_mat(stone: bool) -> ShaderMaterial:
	if not _site_mats.has(stone):
		var sh := Shader.new()
		sh.code = SITE_GROUND.replace("// PHOTO_GROUND", PhotoGround.glsl())
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("stone", stone)
		PhotoGround.apply(mat)
		_site_mats[stone] = mat
	return _site_mats[stone]


const STONE := Color("#7c776f")  # #2 crushed limestone, grey-tan, dusty
const SITE_GROUND := """
shader_type spatial;
uniform bool stone = false;
// PHOTO_GROUND
varying vec3 wp;
varying vec2 dr;
float sg_hash(vec2 c) { return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453); }
float sg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sg_hash(i), sg_hash(i + vec2(1.0, 0.0)), f.x), mix(sg_hash(i + vec2(0.0, 1.0)), sg_hash(i + 1.0), f.x), f.y);
}
// Two wheel tracks 1.7 m apart (a pickup's or a skid steer's), wandering a
// little, worn deepest near the entrance.
float sg_ruts(vec2 d, float reach) {
	float wob = (sg_noise(vec2(d.y * 0.12, 3.1)) - 0.5) * 1.4;
	float off = abs(abs(d.x - wob) - 0.85);
	float track = 1.0 - smoothstep(0.12, 0.32, off);
	return track * (1.0 - smoothstep(reach * 0.6, reach, d.y)) * step(0.0, d.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dr = UV;
}
void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float big = sg_noise(wp.xz * 0.18);
	float fine = sg_noise(wp.xz * 1.9);
	float dist = length(VERTEX);
	float pk = ph_on(dist);
	vec3 n = vec3(0.0, 1.0, 0.0);
	float rough = 0.95;
	if (stone) {
		// Stones catch light unevenly; the inner end carries the site's mud.
		base *= 0.78 + 0.22 * fine + 0.2 * sg_noise(wp.xz * 9.0);
		float mud = clamp(smoothstep(2.0, 11.0, dr.y) * (0.3 + 0.7 * sg_noise(wp.xz * 0.6)) + 0.5 * sg_ruts(dr, 30.0), 0.0, 1.0);
		base = mix(base, vec3(0.09, 0.06, 0.04), mud * 0.7);
		base *= mix(vec3(1.0), ph_gravel(wp.xz), pk);
		n = ph_lean(n, ph_gravel_s(wp.xz), pk * 0.8);
	} else {
		// Damp low spots go dark and shiny; the high ground dries pale.
		float wet = smoothstep(0.7, 0.9, big);
		base *= mix(0.9 + 0.2 * fine, 0.68, wet);
		rough = mix(0.95, 0.7, wet);
		float rut = sg_ruts(dr, 26.0);
		base *= 1.0 - 0.32 * rut;
		rough = mix(rough, 0.6, rut * 0.6);
		base *= mix(vec3(1.0), ph_mud(wp.xz), pk);
		n = ph_lean(n, ph_mud_s(wp.xz) * (1.0 + rut), pk);
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""


## What's lying around the site: silt fence early on, the builder's sign,
## a porta-john, a roll-off dumpster once there's waste, lumber while framing.
func _props_look(stage: String) -> void:
	if stage == _props_for:
		return
	_props_for = stage
	if _props != null:
		_props.queue_free()
		_props = null
	if stage == "landscape" and (_paving or _profile != "house" or _core.position.z - _box.position.z < 4.6):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := _box
	var front := b.position.z + 0.6
	var left := b.position.x + 0.8
	var right := b.end.x - 0.8
	# Builder's sign at the street.
	_prop(st, Vector3(0.08, 1.4, 0.08), Vector3(left + 2.2, 0.7, front), Color("#e9e6dc"))
	_prop(st, Vector3(1.2, 0.8, 0.04), Vector3(left + 2.2, 1.6, front), Color("#f2f0ea"))
	_prop(st, Vector3(1.1, 0.2, 0.05), Vector3(left + 2.2, 1.85, front - 0.01), Color("#2a4a7a"))
	if _paving:
		_paving_props(st, stage, b, front)
		_props = MeshInstance3D.new()
		_props.mesh = st.commit()
		_props.material_override = _prop_mat()
		add_child(_props)
		return
	var k := absi(hash([snappedf(_bldg.size.x, 0.1), snappedf(_bldg.size.z, 0.1), snappedf(_height, 0.1), "site"]))
	var fine := not OS.has_feature("web")
	if stage == "landscape":
		# Sod by the pallet, and the skid steer that brought it up.
		for n in 3:
			_cs_sod(st, Vector3(left + 1.0 + n * 1.45, 0.0, front + 1.5), k + n, fine)
		SiteMachines.skid_steer(st, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(left + 7.6, 0.0, front + 1.7)),
			SiteMachines.paint(k + 1), fine)
		_props = MeshInstance3D.new()
		_props.mesh = st.commit()
		_props.material_override = _prop_mat()
		add_child(_props)
		return
	# A porta-john by the front corner, its door to the lot.
	_cs_john(st, Vector3(left + 0.6, 0.0, front + 1.4), k, fine)
	if stage != "clear":
		_cs_power_pole(st, Vector3(left + 3.8, 0.0, front + 0.9), fine)
	if stage in ["clear", "foundation", "frame"]:
		# Silt fence: black fabric on stakes down the sides and across the back.
		var corners := [Vector3(b.position.x, 0, front + 2.0), Vector3(b.position.x, 0, b.end.z),
			Vector3(b.end.x, 0, b.end.z), Vector3(b.end.x, 0, front + 2.0)]
		for i in 3:
			_fence(st, corners[i], corners[i + 1])
	if stage in ["clear", "foundation", "frame"]:
		# Straw wattles along the street edge either side of the entrance,
		# where the silt fence would block the walk (inlet protection).
		var wz := b.position.z + 0.45
		var e0 := _drive_x - _drive_w * 0.5 - 0.3
		var e1 := _drive_x + _drive_w * 0.5 + 0.3
		for run in [[b.position.x + 0.3, e0], [e1, b.end.x - 0.3]]:
			if run[1] - run[0] > 1.0:
				_cs_wattle(st, Vector3((run[0] + run[1]) * 0.5, 0.0, wz), run[1] - run[0], fine)
	if stage in ["foundation", "frame", "dry_in", "exterior"]:
		# The concrete washout every pour's trucks rinse their chutes into.
		# Off the stone on the open side, clear of the building and its stoop.
		var wx := _drive_x - _drive_w * 0.5 - 2.0
		var wz := minf(b.position.z + minf(_drive_len, 8.0) - 1.0, _core.position.z - 3.6)
		var spot := AABB(Vector3(wx - 1.5, 0, wz - 1.5), Vector3(3.0, 1.0, 3.0))
		if wx - 1.6 > b.position.x + 4.0 and wz - 1.5 > b.position.z + 0.9 and not spot.intersects(_core.grow(1.5)):
			_cs_washout(st, Vector3(wx, 0.0, wz), fine)
	if stage in ["clear", "foundation"]:
		# Spoil from digging the footings, heaped at the back; the topsoil
		# stripped off the lot in its own darker pile beside it.
		var back := b.end.z - 3.0
		var keep := _core.grow(0.5)
		for m in [[Vector3(right - 3.2, 0.0, back), 2.6, 2.0, 1.5, DIRT.lightened(0.05)],
				[Vector3(right - 7.4, 0.0, back + 0.4), 1.9, 1.6, 1.0, Color("#3f3326")]]:
			var at: Vector3 = m[0]
			# Heaped where the building isn't going.
			if not AABB(at - Vector3(m[1], 0, m[2]), Vector3(m[1] * 2.0, 1.0, m[2] * 2.0)).intersects(keep):
				_cs_mound(st, at, m[1], m[2], m[3], m[4], k)
	if stage in ["frame", "dry_in", "exterior", "interior"]:
		# A 20-yard roll-off dumpster along the side, nose to the street.
		_cs_dumpster(st, Vector3(right - 1.3, 0.0, front + 7.85), k, fine, stage != "frame")
	if stage == "frame":
		if _frame_kind == "wood":
			# Banded lumber units on dunnage, a stack of OSB, and the roof
			# trusses lying flat until the walls are up.
			_cs_lumber(st, Vector3(left + 1.0, 0.0, front + 5.0), fine)
			_cs_lumber(st, Vector3(left + 2.6, 0.0, front + 5.0), fine)
			_cs_osb(st, Vector3(left + 1.6, 0.0, front + 9.0), k)
			var span := minf(minf(_core.size.x, _core.size.z), 12.0)
			if b.end.z - _core.end.z > 4.5:
				_cs_trusses(st, Vector3(_core.get_center().x, 0.0, _core.end.z + 1.2), span, fine)
		else:
			# Bundled steel (or panels) on dunnage.
			var col: Color = FRAME_FAR[_frame_kind] if _frame_kind != "tilt_up" else FrameBuilder.GALV
			for n in 2:
				if fine and _frame_kind == "steel":
					_cs_steel(st, Vector3(left + 1.0 + n * 1.6, 0.0, front + 5.0), col)
				else:
					_prop(st, Vector3(1.2, 0.6, 4.9), Vector3(left + 1.0 + n * 1.6, 0.42, front + 5.0), col)
	_cs_machines(st, stage, k, fine)
	if _crane_on and stage in ["frame", "dry_in", "exterior"]:
		_crane(st)
	_props = MeshInstance3D.new()
	_props.mesh = st.commit()
	_props.material_override = _prop_mat()
	add_child(_props)


## The building's own walls and roof, from its roofs: the faces up there
## that look up and are bigger than a lamp head (fences, walks, AC units
## and porch steps stay below head height; a parking lot's light poles and
## a sign's pylon are too small), so the machines and stacks are set
## beside the building, not over the whole lot.
static func _core_box(mesh: Mesh, fallback: AABB) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var indexed: bool = idx != null and idx.size() > 0
		var count: int = idx.size() if indexed else v.size()
		for t in range(0, count - 2, 3):
			var p0: Vector3 = v[idx[t]] if indexed else v[t]
			var p1: Vector3 = v[idx[t + 1]] if indexed else v[t + 1]
			var p2: Vector3 = v[idx[t + 2]] if indexed else v[t + 2]
			if minf(p0.y, minf(p1.y, p2.y)) < 2.4:
				continue
			var n := (p1 - p0).cross(p2 - p0)
			if n.length() < 0.6 or absf(n.normalized().y) < 0.6:
				continue
			for p in [p0, p1, p2]:
				lo = lo.min(p)
				hi = hi.max(p)
	if lo.x > hi.x:
		return fallback
	return AABB(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x - lo.x, hi.y, hi.z - lo.z))


## True when a good share of the drawing stands above CRANE_FROM: a tower
## or a mid-rise, not a church whose steeple alone is tall.
static func _mostly_tall(mesh: Mesh) -> bool:
	var high := 0
	var all := 0
	for i in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		all += v.size()
		for p in v:
			if p.y > CRANE_FROM:
				high += 1
	return all > 0 and high > all / 4


## A hammerhead tower crane over a building of more than about six storeys,
## from the frame until the outside is done (Liebherr and Potain flat-top
## and hammerhead cranes on Indianapolis and Chicago high-rises): a square
## lattice mast about 2 m across standing behind the building where the lot
## has room (or climbing inside its core where it doesn't), 12 m clear over
## the roof, the operator's cab, a jib reaching over the building, the
## counter-jib with its concrete counterweights, the A-frame and its
## pendants, and a bundle of steel on the hook. Picked from the building's
## size, so every player sees the same crane.
func _crane(st: SurfaceTool) -> void:
	var c := _bldg.get_center()
	var k := absi(hash([snappedf(_bldg.size.x, 0.1), snappedf(_bldg.size.z, 0.1), snappedf(_height, 0.1)]))
	var col: Color = [Color("#e8b712"), Color("#e8b712"), Color("#e9e7e1"), Color("#c8432b")][k % 4]
	var behind := _box.end.z - _bldg.end.z >= 5.0
	var base := Vector3(c.x + _bldg.size.x * 0.25, 0.0, _bldg.end.z + 3.0) if behind else Vector3(c.x, 0.0, c.z)
	var mast_h := _height + 12.0
	var m := 1.0  # half the mast's width
	# The mast: four chords and a ring every 2.5 m; a concrete pad under it.
	_prop(st, Vector3(4.5, 0.6, 4.5), base + Vector3(0, 0.3, 0), CONCRETE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_prop(st, Vector3(0.16, mast_h, 0.16), base + Vector3(sx * m, mast_h * 0.5, sz * m), col)
	var y := 2.5
	while y < mast_h:
		for sx in [-1.0, 1.0]:
			_prop(st, Vector3(0.1, 0.1, m * 2.0), base + Vector3(sx * m, y, 0), col)
			_prop(st, Vector3(m * 2.0, 0.1, 0.1), base + Vector3(0, y, sx * m), col)
		# One diagonal a side per section, as the lattice reads from afar.
		_prop(st, Vector3(0.08, 3.2, 0.08), base + Vector3(0, y - 1.25, -m), col, Basis(Vector3.BACK, 0.68))
		_prop(st, Vector3(0.08, 3.2, 0.08), base + Vector3(0, y - 1.25, m), col, Basis(Vector3.BACK, -0.68))
		y += 2.5
	# Slew: the jib swings out over the building, at an angle from the size.
	var to_bldg := Vector2(c.x - base.x, c.z - base.z)
	var yaw := (atan2(to_bldg.y, to_bldg.x) if to_bldg.length() > 1.0 else 0.0) + deg_to_rad(float(k % 70) - 35.0)
	var along := Vector3(cos(yaw), 0, sin(yaw))
	var side := along.cross(Vector3.UP)
	var rot := Basis(along, Vector3.UP, side)
	var top := base + Vector3(0, mast_h, 0)
	var jib := clampf(maxf(_bldg.size.x, _bldg.size.z) * 1.1, 40.0, 65.0)
	var counter := jib * 0.3
	_prop(st, Vector3(2.6, 1.0, 2.6), top + Vector3(0, 0.5, 0), col)  # slewing ring
	# The jib: a triangular lattice, two bottom chords and a top one.
	var mid := top + along * (jib * 0.5) + Vector3(0, 1.0, 0)
	for sd in [-0.7, 0.7]:
		_prop(st, Vector3(jib, 0.14, 0.14), mid + side * sd, col, rot)
	_prop(st, Vector3(jib, 0.14, 0.14), mid + Vector3(0, 1.5, 0), col, rot)
	var t := 2.0
	while t < jib:
		_prop(st, Vector3(0.08, 1.6, 1.4), top + along * t + Vector3(0, 1.75, 0), col, rot)
		t += 2.5
	# The counter-jib with its counterweights, and the A-frame and pendants.
	_prop(st, Vector3(counter, 0.5, 2.0), top - along * (counter * 0.5) + Vector3(0, 1.0, 0), col, rot)
	_prop(st, Vector3(3.0, 2.4, 2.2), top - along * (counter - 2.0) + Vector3(0, 2.4, 0), CONCRETE.darkened(0.1), rot)
	var apex := top + Vector3(0, 7.0, 0)
	_prop(st, Vector3(0.3, 7.0, 0.3), top + Vector3(0, 3.5, 0), col)
	for end in [top + along * jib * 0.7 + Vector3(0, 2.5, 0), top - along * counter + Vector3(0, 1.2, 0)]:
		var span: Vector3 = end - apex
		var axis := span.normalized()
		var bx := axis.cross(Vector3.UP).normalized()
		_prop(st, Vector3(0.06, span.length(), 0.06), apex + span * 0.5, Color("#3a3a3a"), Basis(bx, axis, bx.cross(axis)))
	# The cab, glazed toward the jib, just under it.
	_prop(st, Vector3(1.6, 2.2, 1.8), top + along * 1.6 - side * 1.6 + Vector3(0, -0.4, 0), col.darkened(0.1), rot)
	_prop(st, Vector3(0.05, 1.2, 1.5), top + along * 2.42 - side * 1.6 + Vector3(0, -0.1, 0), Color("#2b3a44"), rot)
	# The trolley partway out, the hoist line and a bundle of steel beams.
	var reach := jib * (0.45 + float(k % 30) / 100.0)
	var hook := top + along * reach
	var drop := clampf(_height * 0.35, 8.0, 30.0)
	_prop(st, Vector3(1.6, 0.5, 1.8), hook + Vector3(0, 0.4, 0), Color("#3a3a3a"), rot)
	_prop(st, Vector3(0.05, drop, 0.05), hook - Vector3(0, drop * 0.5 - 0.2, 0), Color("#222222"))
	_prop(st, Vector3(0.5, 0.6, 0.4), hook - Vector3(0, drop, 0), Color("#e8b712"))
	_prop(st, Vector3(6.0, 0.6, 0.9), hook - Vector3(0, drop + 2.4, 0), FrameBuilder.PRIMER, rot)


## A paving job's site: orange barrels across the entrance while it's dug
## up, a stone pile while the base goes in, and a tracked paver and a
## steel-drum roller while the asphalt is laid. No porta-john or dumpster:
## a lot is a few weeks' work for a paving crew that comes and goes.
func _paving_props(st: SurfaceTool, stage: String, b: AABB, front: float) -> void:
	var right := b.end.x - 0.8
	if stage in ["clear", "foundation"]:
		for k in 4:
			_prop(st, Vector3(0.6, 0.95, 0.6), Vector3(-2.7 + k * 1.8, 0.48, front - 0.4), Color("#e8642a"))
		var corners := [Vector3(b.position.x, 0, front + 2.0), Vector3(b.position.x, 0, b.end.z),
			Vector3(b.end.x, 0, b.end.z), Vector3(b.end.x, 0, front + 2.0)]
		for i in 3:
			_fence(st, corners[i], corners[i + 1])
	if stage == "foundation":
		_prop(st, Vector3(4.0, 1.1, 3.2), Vector3(right - 3.0, 0.55, b.end.z - 3.0), Color("#8f8a80"))
		_prop(st, Vector3(2.6, 0.7, 2.0), Vector3(right - 3.0, 1.4, b.end.z - 3.0), Color("#99948a"))
	if stage == "dry_in":
		# The paver mid-lot on the fresh mat, the roller working behind it.
		var z := b.position.z + (b.size.z - 1.6) * 0.5
		_prop(st, Vector3(3.0, 1.6, 4.5), Vector3(0.0, 1.0, z), Color("#e0b21c"))
		_prop(st, Vector3(1.2, 1.2, 1.2), Vector3(0.0, 2.2, z + 0.8), Color("#2b2b2b"))
		_prop(st, Vector3(1.8, 1.3, 3.2), Vector3(3.2, 0.9, z - 6.0), Color("#e0b21c"))
		_prop(st, Vector3(1.9, 1.1, 1.1), Vector3(3.2, 0.55, z - 7.2), Color("#3d3f42"))


# ---------------------------------------------------------------- site things

## The machines on the lot at each stage (SiteMachines), each where the
## work is: the excavator digging the footings where the building will
## stand, a skid steer at the spoil pile and then backfilling, the
## telehandler on the stone setting lumber up on a house's walls, a boom
## lift along the front of a bigger building while it's framed and closed in.
func _cs_machines(st: SurfaceTool, stage: String, k: int, fine: bool) -> void:
	if _crane_on:
		return
	var col := SiteMachines.paint(k)
	var b := _box
	match stage:
		"clear":
			var at := Vector3(_core.position.x + 2.2, 0.0, _core.position.z + 1.2)
			SiteMachines.excavator(st, Transform3D(Basis(Vector3.UP, 0.25), at), col, -0.35, fine)
			if b.size.z > 22.0:
				SiteMachines.skid_steer(st, Transform3D(Basis(Vector3.UP, 0.4), Vector3(b.end.x - 4.0, 0.0, b.end.z - 8.5)),
					SiteMachines.paint(k + 1), fine)
		"foundation":
			var z := minf(b.position.z + _drive_len + 1.6, _core.position.z - 2.4)
			if z > b.position.z + 1.6:
				SiteMachines.skid_steer(st, Transform3D(Basis(Vector3.UP, 0.5), Vector3(_drive_x, 0.0, z)),
					SiteMachines.paint(k + 1), fine)
		"frame", "dry_in":
			if _frame_kind == "wood":
				# Lumber up to the walls, then shingles up to the roof: on the
				# stone clear of the walls (the forks reach 4.3 m ahead), or
				# else alongside the house where the side yard has room.
				var tcol := Color("#d9661f") if k % 2 == 0 else Color("#e6e4dc")
				var z := minf(b.position.z + _drive_len * 0.5, _core.position.z - 4.6)
				var left_gap := _core.position.x - b.position.x
				var right_gap := b.end.x - _core.end.x
				if z > b.position.z + 2.2:
					SiteMachines.telehandler(st, Transform3D(Basis.IDENTITY, Vector3(_drive_x, 0.0, z)), tcol, fine)
				elif maxf(left_gap, right_gap) > 3.0:
					var x := _core.position.x - left_gap * 0.5 if left_gap >= right_gap else _core.end.x + right_gap * 0.5
					# Past the lumber and OSB stacked at the front corner.
					var tz := maxf(_core.position.z + 2.2, b.position.z + 13.2)
					if tz + 4.4 < b.end.z:
						SiteMachines.telehandler(st, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, tz)), tcol, fine)
	if _frame_kind == "tilt_up" and stage == "frame" and minf(_core.size.x, _core.size.z) > 36.0:
		# Standing the panels from the slab, boom toward the wall going up.
		var cc := _core.get_center()
		SiteMachines.crawler_crane(st, Transform3D(Basis(Vector3.UP, PI * (0.15 + 0.1 * (k % 5))), Vector3(cc.x, 0.0, cc.z)),
			Color("#b8322a") if k % 2 == 0 else Color("#e0a81a"), fine)
	var masonry := _profile in ["shop", "civic"] and stage == "exterior" and _core.position.z - b.position.z > 2.6
	if masonry:
		_cs_scaffold(st, k, fine)
	if _profile != "house" and stage in ["frame", "dry_in", "exterior"] and not masonry and _core.position.z - b.position.z > 4.6:
		var at := Vector3(_core.get_center().x - _core.size.x * 0.2, 0.0, _core.position.z - 2.0)
		SiteMachines.boom_lift(st, Transform3D(Basis(Vector3.UP, PI * 0.5), at),
			Color("#d9661f") if k % 3 == 0 else Color("#3d6fb0"), fine)


## The temporary electric service the electrician sets before the pour
## and the utility feeds until the house's own meter goes live: a treated
## 6x6 post, the meter base, a small breaker panel with weatherproof
## outlets and the trades' cords, and the ground rod at its foot.
func _cs_power_pole(st: SurfaceTool, at: Vector3, fine: bool) -> void:
	_prop(st, Vector3(0.14, 3.4, 0.14), at + Vector3(0, 1.7, 0), Color("#8a7a5c"))
	_prop(st, Vector3(0.4, 0.06, 0.14), at + Vector3(0, 3.0, 0), Color("#8a7a5c"))  # crossarm brace
	_prop(st, Vector3(0.3, 0.42, 0.12), at + Vector3(0, 1.75, -0.13), Color("#9ea3a6"))  # meter base
	_prop(st, Vector3(0.36, 0.5, 0.14), at + Vector3(0, 1.1, -0.14), Color("#6f757a"))  # panel
	_prop(st, Vector3(0.05, 1.2, 0.05), at + Vector3(0, 2.6, -0.1), Color("#3a3a3a"))  # riser
	if fine:
		_prop(st, Vector3(0.14, 0.14, 0.06), at + Vector3(0, 1.8, -0.2), Color("#c9d3d6"))  # meter glass
		_prop(st, Vector3(0.26, 0.08, 0.05), at + Vector3(0, 0.95, -0.22), Color("#2a2a2a"))  # outlets
		_prop(st, Vector3(0.025, 0.25, 0.025), at + Vector3(0.12, 0.12, -0.12), Color("#b4743c"))  # ground rod
		# A yellow cord off to the work, lying on the dirt.
		_prop(st, Vector3(0.025, 0.025, 4.0), at + Vector3(0.1, 0.03, 2.2), Color("#e3b51e"))
		_prop(st, Vector3(0.025, 0.9, 0.025), at + Vector3(0.1, 0.47, 0.2), Color("#e3b51e"))


## A pallet of Kentucky bluegrass sod, the rolls stacked on the slats.
func _cs_sod(st: SurfaceTool, at: Vector3, k: int, fine: bool) -> void:
	_prop(st, Vector3(1.2, 0.13, 1.2), at + Vector3(0, 0.065, 0), Color("#9c8562"))
	var h := 0.55 + 0.2 * float(k % 3) / 2.0
	_prop(st, Vector3(1.14, h, 1.14), at + Vector3(0, 0.13 + h * 0.5, 0), Color("#4e3b28"))  # soil side
	_prop(st, Vector3(1.15, 0.05, 1.15), at + Vector3(0, 0.13 + h, 0), Color("#4f7a31"))
	if fine:
		var y := 0.13 + 0.09
		while y < 0.13 + h:
			_prop(st, Vector3(1.16, 0.035, 1.16), at + Vector3(0, y, 0), Color("#5b7d36"))  # grass at the roll ends
			y += 0.11


## Frame scaffolding across the front while the masons lay the face
## brick or block: 5 ft wide walk-through frames in 7 ft bays, a lift
## every 6.5 ft up to the wall's height, X braces on the outside, planks
## on the working lift; brick on pallets and a mortar mixer at its foot.
func _cs_scaffold(st: SurfaceTool, k: int, fine: bool) -> void:
	var frame: Color = [Color("#b8382c"), Color("#8d969b"), Color("#c96a22")][(k >> 2) % 3]
	var z0 := _core.position.z - 0.35  # the inner uprights, a hand's width off the wall
	var z1 := z0 - 1.52
	var top := minf(_height - 0.6, 12.0)
	var lifts := maxi(1, floori(top / 1.98))
	var x := _core.position.x + 0.3
	var bays := maxi(1, floori((_core.size.x - 0.6) / 2.13))
	var h := lifts * 1.98
	for i in bays + 1:
		var bx := x + i * 2.13
		for z in [z0, z1]:
			_prop(st, Vector3(0.05, h, 0.05), Vector3(bx, h * 0.5, z), frame)
			_prop(st, Vector3(0.15, 0.04, 0.15), Vector3(bx, 0.02, z), Color("#6b5a48"))  # base plate on a mud sill
		for l in lifts:
			_prop(st, Vector3(0.05, 0.05, 1.52), Vector3(bx, (l + 1) * 1.98, (z0 + z1) * 0.5), frame)
			if fine:
				_prop(st, Vector3(0.04, 0.04, 1.52), Vector3(bx, l * 1.98 + 1.55, (z0 + z1) * 0.5), frame)
	for i in bays:
		var mid := x + i * 2.13 + 1.065
		for l in lifts:
			var y := l * 1.98 + 0.99
			if fine:
				# Cross braces in an X on the outside of each bay.
				for sgn in [-1.0, 1.0]:
					_prop(st, Vector3(2.9, 0.03, 0.03), Vector3(mid, y, z1 - 0.04), frame.darkened(0.15),
						Basis(Vector3.BACK, sgn * atan2(1.98, 2.13)))
		# Planks on the top lift and one below, where the masons stand.
		for l in [lifts, maxi(1, lifts - 1)]:
			_prop(st, Vector3(2.1, 0.05, 1.4), Vector3(mid, l * 1.98 + 0.05, (z0 + z1) * 0.5), Color("#b89a6a"))
		if fine:
			# Brick on the plank, ready to hand.
			_prop(st, Vector3(0.5, 0.35, 0.4), Vector3(mid - 0.4, lifts * 1.98 + 0.25, (z0 + z1) * 0.5), Color("#9a4a32"))
	# Cubes of brick on pallets and the mortar mixer out front.
	var gz := z1 - 1.6
	for i in 3:
		var px := x + 1.0 + i * 1.4
		_prop(st, Vector3(1.1, 0.12, 1.1), Vector3(px, 0.06, gz), Color("#9c8562"))
		_prop(st, Vector3(1.0, 0.85, 1.0), Vector3(px, 0.55, gz), Color("#9a4a32") if k % 2 == 0 else Color("#a88e72"))
		if fine:
			_prop(st, Vector3(1.02, 0.02, 1.02), Vector3(px, 0.75, gz), Color("#e6e3d8"))  # banding wrap
	var mx := x + 1.0 + 3 * 1.4 + 0.6
	_prop(st, Vector3(1.0, 0.75, 1.4), Vector3(mx, 0.85, gz), Color("#d9661f"))  # drum
	_prop(st, Vector3(0.1, 0.5, 0.1), Vector3(mx, 0.25, gz - 0.5), Color("#2a2a2a"))
	SiteMachines._wheel(st, Transform3D.IDENTITY, Vector3(mx - 0.6, 0.3, gz + 0.3), 0.3, 0.18, Color("#232323"), 10)
	SiteMachines._wheel(st, Transform3D.IDENTITY, Vector3(mx + 0.6, 0.3, gz + 0.3), 0.3, 0.18, Color("#232323"), 10)


## A straw wattle (a 9 in fiber roll in its netting) staked along a
## line `len` long across x, to slow muddy water before the street.
func _cs_wattle(st: SurfaceTool, c: Vector3, len: float, fine: bool) -> void:
	SiteMachines._wheel(st, Transform3D.IDENTITY, c + Vector3(0, 0.1, 0), 0.115, len, Color("#b49a5e"), 8 if fine else 5)
	if fine:
		var x := -len * 0.5 + 0.6
		while x < len * 0.5:
			_prop(st, Vector3(0.04, 0.45, 0.04), c + Vector3(x, 0.2, -0.13), Color("#8a6b45"))
			x += 1.2


## A concrete washout (EPA SWPPP / Indiana Rule 5 practice): a pit ringed
## with straw bales and lined in black plastic, its floor grey with the
## slurry rinsed off the trucks' chutes.
func _cs_washout(st: SurfaceTool, c: Vector3, fine: bool) -> void:
	var w := 2.8
	var straw := Color("#c2a764")
	for sz in [-1.0, 1.0]:
		_prop(st, Vector3(w, 0.45, 0.46), c + Vector3(0, 0.225, sz * (w * 0.5 - 0.23)), straw)
		_prop(st, Vector3(0.46, 0.45, w - 0.92), c + Vector3(sz * (w * 0.5 - 0.23), 0.225, 0), straw)
	_prop(st, Vector3(w - 0.9, 0.06, w - 0.9), c + Vector3(0, 0.12, 0), Color("#8f8c86"))  # slurry
	if fine:
		# The liner lapped over the bales, and the sign on its stake.
		for sz in [-1.0, 1.0]:
			_prop(st, Vector3(w - 0.4, 0.02, 0.3), c + Vector3(0, 0.46, sz * (w * 0.5 - 0.45)), Color("#1b1b1c"))
			_prop(st, Vector3(0.3, 0.02, w - 0.9), c + Vector3(sz * (w * 0.5 - 0.45), 0.46, 0), Color("#1b1b1c"))
		_prop(st, Vector3(0.05, 1.1, 0.05), c + Vector3(w * 0.5 + 0.2, 0.55, -w * 0.5), Color("#8a6b45"))
		_prop(st, Vector3(0.6, 0.4, 0.03), c + Vector3(w * 0.5 + 0.2, 1.0, -w * 0.5 - 0.03), Color("#e9e6dc"))


## A molded-plastic portable toilet (about 44 x 44 in, 7.5 ft tall): skid
## base, body, the pale translucent roof and its dome, a vent stack, and
## the door with its latch, toward the lot. Rental fleets run blue, green,
## grey and tan.
func _cs_john(st: SurfaceTool, at: Vector3, k: int, fine: bool) -> void:
	var col: Color = [Color("#2f63a6"), Color("#2f6e4a"), Color("#6f7478"), Color("#b39b74")][k % 4]
	_prop(st, Vector3(1.16, 0.1, 1.16), at + Vector3(0, 0.05, 0), col.darkened(0.35))
	_prop(st, Vector3(1.08, 2.08, 1.08), at + Vector3(0, 1.14, 0), col)
	_prop(st, Vector3(1.16, 0.08, 1.16), at + Vector3(0, 2.2, 0), Color("#e6e3d8"))
	_prop(st, Vector3(0.86, 0.12, 0.86), at + Vector3(0, 2.3, 0), Color("#dcd9cf"))
	_prop(st, Vector3(0.1, 0.4, 0.1), at + Vector3(-0.38, 2.4, 0.38), Color("#1e1e1e"))
	# The door, on the side facing into the lot.
	_prop(st, Vector3(0.03, 1.86, 0.78), at + Vector3(0.555, 1.1, 0), col.lightened(0.06))
	if fine:
		_prop(st, Vector3(0.05, 0.06, 0.12), at + Vector3(0.58, 1.12, -0.3), Color("#d9d6cc"))
		_prop(st, Vector3(0.035, 0.12, 0.6), at + Vector3(0.565, 1.95, 0), col.darkened(0.25))  # vent slots
		for z in [-0.36, 0.36]:
			_prop(st, Vector3(0.04, 0.1, 0.06), at + Vector3(0.57, 0.55, z * 0.95), Color("#8a8a86"))


## A 20-yard roll-off (22 ft x 7.5 ft x 4.5 ft high) on its rails: the
## steel tub with a sloped nose for the truck's cable, vertical stiffeners
## down the sides, a top rail, the swing door at the back, and offcuts,
## drywall, cardboard and wrap inside once the trades are throwing them in.
func _cs_dumpster(st: SurfaceTool, c: Vector3, k: int, fine: bool, full: bool) -> void:
	var paint: Color = [Color("#2a568a"), Color("#2e5a3a"), Color("#8a3328"), Color("#4b5056")][(k >> 3) % 4]
	var len := 6.7
	var w := 2.36
	var h := 1.37
	var y0 := 0.16
	# Rails and the tub.
	for x in [-0.6, 0.6]:
		_prop(st, Vector3(0.14, y0, len), c + Vector3(x, y0 * 0.5, 0), Color("#2b2b2b"))
	# An open tub: floor, two sides and the back door, 3/16" plate.
	var t := 0.06
	var body := len - 0.8
	_prop(st, Vector3(w, 0.1, body), c + Vector3(0, y0 + 0.05, 0.4), paint)
	for sx in [-1.0, 1.0]:
		_prop(st, Vector3(t, h, body), c + Vector3(sx * (w - t) * 0.5, y0 + h * 0.5, 0.4), paint)
	_prop(st, Vector3(w, h, t), c + Vector3(0, y0 + h * 0.5, 0.4 + body * 0.5 - t * 0.5), paint)
	# The nose slopes in toward the street end.
	var nose := Basis(Vector3.RIGHT, -0.5)
	_prop(st, Vector3(w, h * 1.05, 0.9), c + Vector3(0, y0 + h * 0.46, -len * 0.5 + 0.72), paint, nose)
	for sx in [-1.0, 1.0]:
		_prop(st, Vector3(0.12, 0.1, body), c + Vector3(sx * (w * 0.5 - 0.03), y0 + h + 0.03, 0.4), paint.darkened(0.2))
	if fine:
		var z := -len * 0.5 + 1.4
		while z < len * 0.5 - 0.3:
			for sx in [-1.0, 1.0]:
				_prop(st, Vector3(0.07, h - 0.05, 0.09), c + Vector3(sx * (w * 0.5 + 0.03), y0 + h * 0.5, z), paint.darkened(0.12))
			z += 0.62
		# The back door's hinges and its latch bar.
		for x in [-0.95, 0.95]:
			_prop(st, Vector3(0.12, 0.16, 0.06), c + Vector3(x, y0 + h * 0.75, len * 0.5 + 0.03), Color("#2b2b2b"))
		_prop(st, Vector3(w * 0.9, 0.06, 0.05), c + Vector3(0, y0 + h * 0.45, len * 0.5 + 0.04), Color("#3a3a3a"))
		# Rust and scrapes along the top edge.
		for sx in [-1.0, 1.0]:
			_prop(st, Vector3(0.13, 0.04, len * 0.6), c + Vector3(sx * (w * 0.5 - 0.03), y0 + h - 0.06, 0.6), Color("#6b4630"))
	# What's in it: a bed of broken-up waste, then a heap of it.
	_prop(st, Vector3(w - 0.14, 0.5, body - 0.14), c + Vector3(0, y0 + 0.35, 0.4), Color("#4a4038"))
	if full and fine:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([k, "dumpster"])
		var waste := [Color("#cdb48a"), Color("#e3e1da"), Color("#a5845a"), Color("#5f6a74"), Color("#d8d4c4")]
		for i in 18:
			var size := Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(0.04, 0.25), rng.randf_range(0.3, 2.2))
			var at := c + Vector3(rng.randf_range(-0.8, 0.8), y0 + h - 0.3 + rng.randf_range(0.0, 0.35), rng.randf_range(-2.2, 2.6))
			_prop(st, size, at, waste[rng.randi() % waste.size()], Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)).rotated(
				Vector3.RIGHT, rng.randf_range(-0.25, 0.25)))


## A banded unit of framing lumber off the yard's truck (2x4s and 2x6s in
## 16 ft lengths, about 4 ft wide and 2.5 ft high) on 4x4 dunnage, steel
## straps round it and the yard's white wrap over its top.
func _cs_lumber(st: SurfaceTool, at: Vector3, fine: bool) -> void:
	var wood := Color("#d6bd8a")
	for z in [-1.8, 0.0, 1.8]:
		_prop(st, Vector3(1.4, 0.09, 0.09), at + Vector3(0, 0.045, z), wood.darkened(0.25))
	_prop(st, Vector3(1.2, 0.72, 4.88), at + Vector3(0, 0.45, 0), wood)
	# Wrap over the top and down the sides, the ends left open.
	_prop(st, Vector3(1.24, 0.3, 4.4), at + Vector3(0, 0.68, 0), Color("#ebe9e2"))
	if fine:
		for z in [-1.6, 0.0, 1.6]:
			_prop(st, Vector3(1.26, 0.76, 0.03), at + Vector3(0, 0.45, z), Color("#4a4d50"))
		# Board ends: the end grain darker, the gaps between boards darker still.
		for e in [-1.0, 1.0]:
			_prop(st, Vector3(1.18, 0.7, 0.02), at + Vector3(0, 0.45, e * 2.445), wood.darkened(0.12))
			for i in 4:
				_prop(st, Vector3(1.18, 0.012, 0.022), at + Vector3(0, 0.18 + i * 0.14, e * 2.446), wood.darkened(0.45))


## Wide-flange beams and joists off the steel hauler, shop-primed, laid
## side by side two layers deep on timber dunnage: each an I in section
## (two flanges and a web), so the ends read as steel, not a block.
func _cs_steel(st: SurfaceTool, at: Vector3, col: Color) -> void:
	for z in [-1.8, 0.0, 1.8]:
		_prop(st, Vector3(1.4, 0.12, 0.12), at + Vector3(0, 0.06, z), Color("#7d6448"))
	var d := 0.3  # a W12: about a foot deep, 6.5 in wide
	var bf := 0.165
	for layer in 2:
		var y := 0.12 + layer * (d + 0.01)
		for i in 6:
			var x := -0.52 + i * 0.205 + layer * 0.1
			if layer == 1 and i > 4:
				continue
			var c := at + Vector3(x, y, 0)
			_prop(st, Vector3(bf, 0.016, 5.4), c + Vector3(0, 0.008, 0), col)
			_prop(st, Vector3(bf, 0.016, 5.4), c + Vector3(0, d - 0.008, 0), col)
			_prop(st, Vector3(0.01, d, 5.4), c + Vector3(0, d * 0.5, 0), col.darkened(0.15))


## A stack of OSB sheathing (4 x 8 ft sheets, a few dozen high), the
## mill's coloured edge seal down its sides and the strand face on top.
func _cs_osb(st: SurfaceTool, at: Vector3, k: int) -> void:
	var edge: Color = [Color("#3e7a52"), Color("#c9433a"), Color("#3a6aa0")][(k >> 5) % 3]
	for z in [-0.9, 0.0, 0.9]:
		_prop(st, Vector3(1.3, 0.09, 0.09), at + Vector3(0, 0.045, z), Color("#9c8560"))
	_prop(st, Vector3(1.22, 0.55, 2.44), at + Vector3(0, 0.365, 0), edge)
	_prop(st, Vector3(1.224, 0.03, 2.444), at + Vector3(0, 0.63, 0), Color("#c9a467"))


## Roof trusses as the truck leaves them, lying flat in a stack on dunnage
## until the walls are up: a 6:12 Fink truss, its two top chords, bottom
## chord, W webs and tails, a dozen high.
func _cs_trusses(st: SurfaceTool, at: Vector3, span: float, fine: bool) -> void:
	var wood := Color("#d9c597")
	var n := 12
	var hgt := n * 0.04
	var y := 0.1 + hgt * 0.5
	var rise := span * 0.25
	var l := at + Vector3(-span * 0.5, 0, 0)
	var r := at + Vector3(span * 0.5, 0, 0)
	var apex := at + Vector3(0, 0, rise)
	for x in [-span * 0.35, 0.0, span * 0.35]:
		_prop(st, Vector3(0.09, 0.09, rise + 0.6), at + Vector3(x, 0.045, rise * 0.5), wood.darkened(0.3))
	var member := func(p0: Vector3, p1: Vector3, wdt: float) -> void:
		var d: Vector3 = p1 - p0
		var dir := d.normalized()
		var bas := Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir)
		_prop(st, Vector3(wdt, hgt, d.length()), (p0 + p1) * 0.5 + Vector3(0, y, 0), wood, bas)
	member.call(l - Vector3(0.6, 0, 0), r + Vector3(0.6, 0, 0), 0.09)
	member.call(l - Vector3(0.6, 0, -0.3), apex, 0.09)
	member.call(r + Vector3(0.6, 0, 0.3), apex, 0.09)
	if fine:
		var q1 := at + Vector3(-span / 6.0, 0, 0)
		var q2 := at + Vector3(span / 6.0, 0, 0)
		member.call(q1, at + Vector3(-span / 3.0, 0, rise / 3.0 * 2.0), 0.064)
		member.call(q1, apex, 0.064)
		member.call(q2, apex, 0.064)
		member.call(q2, at + Vector3(span / 3.0, 0, rise / 3.0 * 2.0), 0.064)
		# Galvanized plates at the joints.
		for p in [l, r, apex, q1, q2]:
			_prop(st, Vector3(0.22, hgt + 0.01, 0.16), p + Vector3(0, y, 0.04), FrameBuilder.GALV)


## A heaped pile of dirt: a lumpy dome, `rx` by `rz` across and `h` high.
static func _cs_mound(st: SurfaceTool, c: Vector3, rx: float, rz: float, h: float, col: Color, k: int) -> void:
	var rings := 8
	var segs := 20
	var pt := func(i: int, j: int) -> Vector3:
		var t := float(i) / rings  # 0 at the top, 1 at the foot
		var a := TAU * j / segs
		var lump := 1.0 + 0.12 * sin(a * 3.0 + k) + 0.08 * sin(a * 5.0 + k * 1.7)
		var r := sin(t * PI * 0.5) * lump
		return c + Vector3(cos(a) * rx * r, h * cos(t * PI * 0.5) * (1.0 + 0.1 * sin(a * 2.0 + k)) * (1.0 if i < rings else 0.0) + 0.05, sin(a) * rz * r)
	for i in rings:
		for j in segs:
			var q := [pt.call(i, j), pt.call(i, j + 1), pt.call(i + 1, j + 1), pt.call(i + 1, j)]
			var n: Vector3 = (q[2] - q[0]).cross(q[1] - q[3]).normalized()
			if n.y < 0.0:
				n = -n
			st.set_color(col.darkened(0.05 * (i % 2)))
			st.set_normal(n)
			for v in [q[0], q[2], q[1], q[0], q[3], q[2]]:
				st.add_vertex(v)


func _fence(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return
	var dir := d / len
	var basis := Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir)
	var mid := (a + b) * 0.5
	_prop(st, Vector3(0.02, 0.6, len), mid + Vector3(0, 0.3, 0), Color("#1b1b1c"), basis)
	var k := 0.0
	while k <= len:
		_prop(st, Vector3(0.05, 0.9, 0.05), a + dir * k + Vector3(0, 0.45, 0), Color("#8a6b45"))
		k += 2.4


static func _prop(st: SurfaceTool, size: Vector3, center: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var u := basis * Vector3(h.x, 0, 0)
	var up := basis * Vector3(0, h.y, 0)
	var f := basis * Vector3(0, 0, h.z)
	FrameBuilder._box(st, center - up, center + up, u, size.x, f, size.z, col)
