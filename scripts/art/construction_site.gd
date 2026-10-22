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
## Benchmark: Cities: Skylines 2 hides a new building in a scaffold box.

signal finished

## Metres from the camera within which the frame is drawn member by member.
const NEAR := 170.0
## Seconds between looks at the clock.
const POLL := 0.25
const DIRT := Color("#6e5a43")
const CONCRETE := Color("#b3afa6")
## Wall and roof colours of each method's shell while it's being closed in.
const SHELL := {
	"house": [Color("#e9eae6"), Color("#2f2e2d")],   # house wrap, roofing felt
	"shop": [Color("#a8a49b"), Color("#8e959a")],    # concrete block, steel deck
	"civic": [Color("#a8a49b"), Color("#8e959a")],
	"factory": [Color("#c4c8ca"), Color("#b4b9bb")], # bare galvalume panels
	"warehouse": [Color("#b9b5ab"), Color("#8e959a")],  # tilt-up concrete, deck
	"barn": [Color("#aab1b5"), Color("#aab1b5")],    # galvanized steel
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
var _props_for := ""
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
			if stage == "frame":
				_shell_look(FRAME_FAR[_frame_kind], FRAME_FAR[_frame_kind], 0.0)
				_param(_shell, "cut", _found_h + span * t)
				_param(_shell, "floor_cut", -1000.0)
			elif stage == "dry_in":
				_shell_look(colors[0], colors[1], 0.02)
				_param(_shell, "cut", _found_h + span * t)
				_param(_shell, "floor_cut", -1000.0)
			else:
				# The roof was shingled while it was dried in: only walls are wrapped.
				_shell_look(colors[0], colors[1], 0.05)
				_param(_shell, "cut", 1000.0)
				_param(_shell, "floor_cut", _found_h + span * t)
	_final.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_props_look(stage)


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_final.visible = true
	_ground.visible = true
	if _footing != null:
		_footing.visible = true
	for n in [_found, _shell, _pad, _props]:
		if n != null:
			n.queue_free()
	for n in _frame:
		n.queue_free()
	_frame.clear()
	_found = null
	_shell = null
	_pad = null
	_props = null
	finished.emit()


func _near() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return true
	return cam.global_position.distance_to(global_position) < NEAR


# ---------------------------------------------------------------- shells

## The finished building's mesh drawn plain in two colours (walls, roofs)
## and clipped to a height band.
func _clipped(wall: Color, roof: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _built[0]
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	mat.set_shader_parameter("wall_color", wall)
	mat.set_shader_parameter("roof_color", roof)
	mi.material_override = mat
	add_child(mi)
	return mi


func _shell_look(wall: Color, roof: Color, inflate: float) -> void:
	var mat: ShaderMaterial = _shell.material_override
	mat.set_shader_parameter("walls_only", inflate > 0.04)
	mat.set_shader_parameter("wall_color", wall)
	mat.set_shader_parameter("roof_color", roof)
	mat.set_shader_parameter("inflate", inflate)


static func _param(mi: MeshInstance3D, param: String, v: float) -> void:
	(mi.material_override as ShaderMaterial).set_shader_parameter(param, v)


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
	if (lp.y > cut || lp.y < floor_cut || plant > 0.5 || walls_only && abs(ln.y) > 0.3) {
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
	var y := 0.07
	for i in n:
		for j in n:
			var x0 := _box.position.x + _box.size.x * i / n
			var x1 := _box.position.x + _box.size.x * (i + 1) / n
			var z0 := _box.position.z + _box.size.z * j / n
			var z1 := _box.position.z + _box.size.z * (j + 1) / n
			var h := fposmod(sin(i * 12.9898 + j * 78.233) * 43758.5453, 1.0)
			st.set_color(DIRT.lightened(h * 0.04) if h > 0.5 else DIRT.darkened(h * 0.05))
			for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
					Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
				st.add_vertex(p)
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
	# Builder's sign at the street, a porta-john by the front corner.
	_prop(st, Vector3(0.08, 1.4, 0.08), Vector3(left + 2.2, 0.7, front), Color("#e9e6dc"))
	_prop(st, Vector3(1.2, 0.8, 0.04), Vector3(left + 2.2, 1.6, front), Color("#f2f0ea"))
	_prop(st, Vector3(1.1, 0.2, 0.05), Vector3(left + 2.2, 1.85, front - 0.01), Color("#2a4a7a"))
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
	_props = MeshInstance3D.new()
	_props.mesh = st.commit()
	_props.material_override = FrameBuilder.material()
	add_child(_props)


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
