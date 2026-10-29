class_name CountyRailView
extends Node3D
## Draws the county's real railroads (CountyRail) out to the haze on the
## desktop app, with the same kit as a town's own track (RailView): crushed
## rock ballast with its weedy toe and fill slopes, ties every 60 cm, steel
## rails with a bright running surface, deck girder bridges on concrete piers
## over the creeks and rivers, and rubber crossing panels where a road
## crosses at grade. One mesh per 256 m square (CountyRail.BIN), the nearest
## first within a time budget; the rails and ties drop out with distance,
## where they are thinner than a pixel, and the ballast carries on.

## How far out the track is drawn, metres.
const DRAW_TO := 4500.0
## Rails, and ties, are drawn this near the camera (metres).
const RAILS_TO := 1500.0
const TIES_TO := 650.0
## Time to spend building squares each frame, ms.
const BUDGET_MS := 2.0
## The camera moves this far before the squares to build are chosen again.
const RESCAN_M := 256.0
const RUBBER := Color("#3c3d3e")

## The ballast: its painted grey (sRGB vertex colours) times the county
## gravel photo at 2.5 times its size, since mainline ballast is 1 to 2.5
## inch crushed granite and trap rock (AREMA No. 4 and 24), larger than road
## gravel, and grey: the photo adds only its stones' light and shade.
const ROCK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
PHOTO
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec3 col = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, vec3(lessThan(c, vec3(0.04045))));
	float pk = ph_on(length(world_pos - CAMERA_POSITION_WORLD));
	vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	if (pk > 0.0) {
		vec2 p = world_pos.xz / 2.5;
		float l = dot(ph_gravel(p), vec3(0.3333));
		col *= mix(1.0, l, pk);
		n = ph_lean(n, ph_gravel_s(p), pk * 0.8);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""

var sim: CitySim
var _origin := Vector2.INF
var _scan_at := Vector2.INF
var _queue: Array = []
## Square -> [track MeshInstance3D, rails MeshInstance3D, ties MultiMeshInstance3D]
var _built := {}
var _mat: StandardMaterial3D
## The ballast's own material: its painted grey with the gravel photo's
## stones on the desktop's High tier and up (PhotoGround).
var _rock: ShaderMaterial
var _tie_mesh: BoxMesh


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rock = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ROCK_SHADER.replace("PHOTO", PhotoGround.glsl())
	_rock.shader = sh
	PhotoGround.apply(_rock)
	_tie_mesh = BoxMesh.new()
	_tie_mesh.size = Vector3(2.6, 0.18, 0.23)
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = RailView.TIE
	tie_mat.roughness = 1.0
	_tie_mesh.material = tie_mat


func _process(_delta: float) -> void:
	if not CountyRail.drawn():
		set_process(false)
		return
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for b in _built:
			for n in _built[b]:
				if n != null:
					n.queue_free()
		_built.clear()
		_scan_at = Vector2.INF
	var cam := get_viewport().get_camera_3d()
	var c := _origin
	if cam != null:
		c = Vector2(cam.global_position.x, cam.global_position.z) + _origin
	if _scan_at == Vector2.INF or c.distance_to(_scan_at) > RESCAN_M:
		_rescan(c)
	var start := Time.get_ticks_usec()
	var budget := LoadGate.ms(BUDGET_MS)
	while not _queue.is_empty() and (Time.get_ticks_usec() - start) / 1000.0 < budget:
		var b: Vector2i = _queue.pop_back()
		_built[b] = _build(b)


## Chooses the squares to build within reach, the nearest last in the queue
## (popped first), and lets go of those well past it.
func _rescan(c: Vector2) -> void:
	_scan_at = c
	var r := ceili(DRAW_TO / CountyRail.BIN) + 1
	var cb := Vector2i((c / CountyRail.BIN).floor())
	var want := []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var b := cb + Vector2i(dx, dz)
			if _built.has(b) or _dist(b, c) > DRAW_TO + CountyRail.BIN:
				continue
			if not CountyRail.routes_in(b).is_empty():
				want.append(b)
	for b in _built.keys():
		if _dist(b, c) > DRAW_TO + CountyRail.BIN * 3.0:
			for n in _built[b]:
				if n != null:
					n.queue_free()
			_built.erase(b)
	want.sort_custom(func(a, b): return _dist(a, c) > _dist(b, c))
	_queue = want


static func _dist(b: Vector2i, c: Vector2) -> float:
	return ((Vector2(b) + Vector2(0.5, 0.5)) * CountyRail.BIN).distance_to(c)


## True where the town has built on the land (its own streets and lots win).
func _town_has(p: Vector3) -> bool:
	return sim != null and sim.vegetation.is_occupied(Vegetation.cell_of(p))


## The track in one square: every route's samples that fall in it, and
## the step on to the next sample, so squares meet.
func _build(b: Vector2i) -> Array:
	var box := Rect2(Vector2(b) * CountyRail.BIN, Vector2.ONE * CountyRail.BIN)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ties := []
	var any := false
	var o := _origin
	CountyRail.settle(b)
	for route in CountyRail.routes_in(b):
		var prof := CountyRail.profile(route)
		var at: PackedVector2Array = prof.at
		var bed: PackedFloat32Array = prof.bed
		var kind: PackedByteArray = prof.kind
		for i in at.size() - 1:
			if not box.has_point(at[i]):
				continue
			if kind[i] == 3 or kind[i + 1] == 3:
				continue
			var c0 := Vector3(at[i].x - o.x, bed[i], at[i].y - o.y)
			var c1 := Vector3(at[i + 1].x - o.x, bed[i + 1], at[i + 1].y - o.y)
			if _town_has(c0) or _town_has(c1):
				continue
			var n0 := _left(at, i)
			var n1 := _left(at, i + 1)
			any = true
			if kind[i] == 2 or kind[i + 1] == 2:
				RailView._bridge_span(st, c0, c1, n0, n1, i)
			elif kind[i] == 1 and kind[i + 1] == 1:
				# A grade crossing: rubber panels across the track's width,
				# level with the rail tops, as the road runs over it.
				var y := Vector3(0, CountyRail.RAIL_TOP - 0.02, 0)
				RailView._quad(st, c0 - n0 * 1.6 + y, c0 + n0 * 1.6 + y, c1 + n1 * 1.6 + y, c1 - n1 * 1.6 + y, RUBBER)
			else:
				RailView._ballast(rock, c0, c1, n0, n1)
				# Double track: one crown of ballast across both, not two
				# prisms with a ditch between.
				var pair: Dictionary = prof.get("pair", {})
				if pair.has(i) and pair.has(i + 1):
					var y := Vector3(0, RailView.BALLAST_Y, 0)
					var q0: Vector2 = pair[i] - o
					var q1: Vector2 = pair[i + 1] - o
					RailView._quad(rock, c0 + y, Vector3(q0.x, c0.y, q0.y) + y, Vector3(q1.x, c1.y, q1.y) + y, c1 + y, RailView.BALLAST)
			for side: float in [-1.0, 1.0]:
				RailView._rail(rails, c0 + n0 * side * RailModels.GAUGE * 0.5, c1 + n1 * side * RailModels.GAUGE * 0.5, n0, n1)
			if kind[i] == 1 and kind[i + 1] == 1:
				continue
			var seg := c1 - c0
			var len := Vector2(seg.x, seg.z).length()
			var k := fposmod(float(i) * CountyRail.STEP, RailView.TIE_EVERY)
			while k < len:
				var p := c0.lerp(c1, k / len) + Vector3(0, RailView.TIE_Y - 0.09, 0)
				ties.append(Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), p))
				k += RailView.TIE_EVERY
	if not any:
		return []
	var out := []
	st.index()
	st.generate_normals()
	out.append(_instance(st.commit(), DRAW_TO))
	rock.index()
	rock.generate_normals()
	var ri := _instance(rock.commit(), DRAW_TO)
	ri.material_override = _rock
	out.append(ri)
	rails.index()
	rails.generate_normals()
	out.append(_instance(rails.commit(), RAILS_TO))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tie_mesh
	mm.instance_count = ties.size()
	for t in ties.size():
		mm.set_instance_transform(t, ties[t])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = mm
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tmi.visibility_range_end = TIES_TO
	add_child(tmi)
	out.append(tmi)
	return out


func _instance(mesh: Mesh, reach: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.visibility_range_end = reach
	add_child(mi)
	return mi


## The track's left at sample i (the way across it, level).
static func _left(at: PackedVector2Array, i: int) -> Vector3:
	var a := at[maxi(i - 1, 0)]
	var b := at[mini(i + 1, at.size() - 1)]
	var t := (b - a).normalized()
	return Vector3(-t.y, 0.0, t.x)
