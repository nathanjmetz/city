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
var _pad: MeshInstance3D
var _props: MeshInstance3D
var _frame: Array = []  # MeshInstance3D per FrameBuilder chunk
var _footing: Node3D
var _frame_kind := "wood"
var _height := 6.0
var _found_h := 0.45
var _box := AABB()
var _bldg := AABB()  # the finished building's own bounds (not its lot)
var _crane_on := false  # a high-rise: it goes up under a tower crane
var _props_for := ""
var _paving := false
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
	if _footing != null:
		_footing.visible = stage != "clear"
	# Footings and slab: the finished shape clipped low, in fresh concrete.
	var show_found := stage in ["foundation", "frame", "dry_in"]
	if show_found and _found == null:
		_found = _clipped(CONCRETE, CONCRETE)
	if _found != null:
		_found.visible = show_found
		if show_found:
			var h := _found_h * clampf(t * 1.4, 0.15, 1.0) if stage == "foundation" else _found_h
			_param(_found, "cut", h)
	# The frame, member by member up close.
	var frame_chunks := 0
	if stage == "frame":
		frame_chunks = clampi(ceili(t * FrameBuilder.CHUNKS + 0.01), 1, FrameBuilder.CHUNKS)
	elif stage == "dry_in":
		frame_chunks = FrameBuilder.CHUNKS
	if frame_chunks > 0 and near and _frame.is_empty():
		for m in FrameBuilder.build(_built[0], _frame_kind):
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
				_param(_shell, "cut", _found_h + span * t)
				_param(_shell, "floor_cut", _found_h)
			elif stage == "dry_in":
				_shell_look(colors[0], colors[1], 0.04)
				_param(_shell, "cut", _found_h + span * t)
				_param(_shell, "floor_cut", _found_h)
			else:
				# The roof was shingled while it was dried in: only walls are wrapped.
				_shell_look(colors[0], colors[1], 0.08)
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
	for n in [_found, _shell, _pad, _props, _stone, _mat]:
		if n != null:
			n.queue_free()
	for n in _frame:
		n.queue_free()
	_frame.clear()
	_found = null
	_shell = null
	_pad = null
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


static func _param(mi: MeshInstance3D, param: String, v: float) -> void:
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
	if (lp.y > cut || lp.y < floor_cut || plant > 0.5 || walls_only && abs(ln.y) > 0.3 && !glazing) {
		discard;
	}
	ALBEDO = abs(ln.y) > 0.3 ? roof_color : wall_color;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"""
	return _shader


# ---------------------------------------------------------------- the lot

## Bare, graded dirt over the whole site, with a little variation.
func _make_pad() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 6
	var y := 0.1  # above the lot tint (0.06) and the yard it replaces
	var at := func(i: int, j: int) -> Vector3:
		return Vector3(_box.position.x + _box.size.x * i / n, y, _box.position.z + _box.size.z * j / n)
	# A soft blotch of lighter and darker dirt, smooth across the corners.
	var tint := func(i: int, j: int) -> Color:
		var h := fposmod(sin(i * 12.9898 + j * 78.233) * 43758.5453, 1.0)
		return DIRT.lightened(h * 0.06) if h > 0.5 else DIRT.darkened((0.5 - h) * 0.08)
	for i in n:
		for j in n:
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				st.set_color(tint.call(c[0], c[1]))
				st.add_vertex(at.call(c[0], c[1]))
	_pad = MeshInstance3D.new()
	_pad.mesh = st.commit()
	var root := get_parent() as Node3D
	if root != null and root.is_inside_tree():
		# Graded dirt follows the land like the yard will.
		_pad.mesh = Terrain.drape_local(_pad.mesh, root.transform)
	_pad.material_override = _dirt_mat()
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pad)


static var _dirt: StandardMaterial3D


static func _dirt_mat() -> StandardMaterial3D:
	if _dirt == null:
		_dirt = StandardMaterial3D.new()
		_dirt.vertex_color_use_as_albedo = true
		_dirt.roughness = 1.0
	return _dirt


## What's lying around the site: silt fence early on, the builder's sign,
## a porta-john, a roll-off dumpster once there's waste, lumber while framing.
func _props_look(stage: String) -> void:
	if stage == _props_for:
		return
	_props_for = stage
	if _props != null:
		_props.queue_free()
		_props = null
	if stage == "landscape":
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
		_props.material_override = FrameBuilder.material()
		add_child(_props)
		return
	# A porta-john by the front corner.
	_prop(st, Vector3(1.12, 2.3, 1.12), Vector3(left + 0.6, 1.15, front + 1.4), Color("#2f6db0"))
	_prop(st, Vector3(1.16, 0.08, 1.16), Vector3(left + 0.6, 2.33, front + 1.4), Color("#e8e8e6"))
	if stage in ["clear", "foundation", "frame"]:
		# Silt fence: black fabric on stakes down the sides and across the back.
		var corners := [Vector3(b.position.x, 0, front + 2.0), Vector3(b.position.x, 0, b.end.z),
			Vector3(b.end.x, 0, b.end.z), Vector3(b.end.x, 0, front + 2.0)]
		for i in 3:
			_fence(st, corners[i], corners[i + 1])
	if stage == "clear":
		# Spoil from digging the footings, heaped at the back.
		_prop(st, Vector3(4.0, 1.0, 3.0), Vector3(right - 3.0, 0.5, b.end.z - 2.5), DIRT.darkened(0.15))
		_prop(st, Vector3(2.6, 0.6, 1.8), Vector3(right - 3.0, 1.3, b.end.z - 2.5), DIRT.darkened(0.1))
	if stage in ["frame", "dry_in", "exterior", "interior"]:
		# A 20-yard roll-off dumpster along the side, nose to the street.
		var dz := front + 4.5
		_prop(st, Vector3(2.4, 1.3, 6.7), Vector3(right - 1.3, 0.75, dz + 3.35), Color("#2c5a8c"))
		_prop(st, Vector3(2.2, 0.06, 6.5), Vector3(right - 1.3, 1.38, dz + 3.35), Color("#6b5a48"))
	if stage == "frame":
		# Bundled lumber (or steel) on dunnage.
		var col: Color = FRAME_FAR[_frame_kind] if _frame_kind != "tilt_up" else FrameBuilder.GALV
		for k in 2:
			_prop(st, Vector3(1.2, 0.6, 4.9), Vector3(left + 1.0 + k * 1.6, 0.42, front + 5.0), col)
	if _crane_on and stage in ["frame", "dry_in", "exterior"]:
		_crane(st)
	_props = MeshInstance3D.new()
	_props.mesh = st.commit()
	_props.material_override = FrameBuilder.material()
	add_child(_props)


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
