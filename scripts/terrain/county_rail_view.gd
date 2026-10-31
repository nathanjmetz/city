class_name CountyRailView
extends Node3D
## Draws the county's real railroads (CountyRail) out to the haze, with the
## same kit as a town's own track (RailView): crushed rock ballast with its
## weedy toe and fill slopes, ties every 60 cm, steel rails with a bright
## running surface, deck girder bridges on concrete piers over the creeks
## and rivers, and rubber crossing panels where a road
## crosses at grade. One mesh per 256 m square (CountyRail.BIN), the nearest
## first within a time budget; the rails and ties drop out with distance,
## where they are thinner than a pixel, and the ballast carries on. The
## browser draws a lighter look (CountyRail.light): the ballast, rails and
## bridges in one plain mesh a square, no ties, out to LIGHT_DRAW_TO.
##
## Where a town street crosses the track (_town_has) the rails run on
## through its pavement in rubber crossing panels, the bed easing down to
## the street over CountyRail.RAMP either way, as at the county's own road
## crossings (before 2026-10-31 the track simply stopped short of each
## street, a few metres of grass either side). A square is drawn again
## whenever the town builds or clears ground in it, so the track always
## matches the town's streets as they are now.

## How far out the track is drawn, metres.
const DRAW_TO := 4500.0
## How far out the browser's lighter track is drawn (CountyRail.light):
## ballast and rails, one mesh a square.
const LIGHT_DRAW_TO := 2000.0
## Rails, and ties, are drawn this near the camera (metres).
const RAILS_TO := 1500.0
const TIES_TO := 650.0
## Time to spend building squares each frame, ms.
const BUDGET_MS := 2.0
## The camera moves this far before the squares to build are chosen again.
const RESCAN_M := 256.0
const RUBBER := Color("#3c3d3e")
## The mainline's ballast section (AREMA ch. 1; a Class I line's standard
## section): the cribs between the ties filled to CROWN_Y, about 6 cm under
## the tie tops, a crown CROWN_HALF each side of the centre (3.8 m across,
## a foot of shoulder past the 8 ft 6 in ties), shoulders falling SHOULDER
## to one down to the subgrade, then a strip of cinders and weeds. Before
## 2026-10-31 the county track used the town spur's low prism (RailView:
## level with the tie bottoms, 3.2 m), and through town the ties seemed to
## lie on the lawn.
const CROWN_Y := 0.42
const CROWN_HALF := 1.9
const SHOULDER := 1.5
## The subgrade's edge, past the shoulder's toe, and how far below the
## bed it falls (m).
const SUBGRADE_HALF := 3.3
const SUBGRADE_DROP := 0.08
const STONE := Color("#77746d")
const STONE_SIDE := Color("#64615b")

## Rail top above the street's own level at a town crossing (m): the
## panels (2 cm under it) 3 cm over the asphalt (RoadStyle.Y_ASPHALT),
## lifted as the road's own marks are, so they never flicker with it.
const TOWN_RAIL := RoadStyle.Y_ASPHALT + 0.05

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
## Squares to draw again: the town built or cleared ground in them.
var _stale := {}
var _redrawn := {}  # square -> when it was last drawn again (ms)
## Seconds between redraws of one square.
const REDRAW_S := 1.0
## The browser's lighter look (CountyRail.light), and how far it reaches.
var _light := false
var _reach := DRAW_TO
## The bed eased down to the town streets it crosses (_eased), for the
## through freights to ride on (bed_at): route -> {sample: bed}, the
## samples of the squares drawn so far.
static var _sunk := {}


func setup(s: CitySim) -> void:
	sim = s
	_sunk.clear()
	if not sim.vegetation.changed.is_connected(_on_ground):
		sim.vegetation.changed.connect(_on_ground)


## The town built or cleared land in these chunks (Vegetation.CHUNK squares,
## town coordinates): the track squares they reach are drawn again.
func _on_ground(chunks: Array) -> void:
	if _origin == Vector2.INF:
		return
	for ch: Vector2i in chunks:
		var r := Rect2(Vector2(ch) * Vegetation.CHUNK + _origin, Vector2.ONE * Vegetation.CHUNK).grow(Vegetation.CELL)
		for bx in range(floori(r.position.x / CountyRail.BIN), floori(r.end.x / CountyRail.BIN) + 1):
			for bz in range(floori(r.position.y / CountyRail.BIN), floori(r.end.y / CountyRail.BIN) + 1):
				var b := Vector2i(bx, bz)
				if _built.has(b):
					_stale[b] = true


func _ready() -> void:
	_light = CountyRail.light()
	_reach = LIGHT_DRAW_TO if _light else DRAW_TO
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _light:
		return  # plain ballast and rails in _mat: no stone photo or ties
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
		_stale.clear()
		_redrawn.clear()
		_sunk.clear()
		_scan_at = Vector2.INF
	var cam := get_viewport().get_camera_3d()
	var c := _origin
	if cam != null:
		c = Vector2(cam.global_position.x, cam.global_position.z) + _origin
	if _scan_at == Vector2.INF or c.distance_to(_scan_at) > RESCAN_M:
		_rescan(c)
	var start := Time.get_ticks_usec()
	var budget := LoadGate.ms(BUDGET_MS)
	# Squares the town built near, drawn again first (the old one stays
	# until the new one is ready): not while the game loads, when the land
	# under the town is still being worked out, and each at most every
	# REDRAW_S, so a growing town redraws a square once, not every build.
	var now := Time.get_ticks_msec()
	for b in ([] if LoadGate.loading else _stale.keys()):
		if (Time.get_ticks_usec() - start) / 1000.0 >= budget:
			break
		if now - int(_redrawn.get(b, -100000)) < REDRAW_S * 1000.0:
			continue
		_redrawn[b] = now
		_stale.erase(b)
		if not _built.has(b):
			continue
		var old: Array = _built[b]
		_built[b] = _build(b)
		for n in old:
			if n != null:
				n.queue_free()
	while not _queue.is_empty() and (Time.get_ticks_usec() - start) / 1000.0 < budget:
		var b: Vector2i = _queue.pop_back()
		_built[b] = _build(b)


## Chooses the squares to build within reach, the nearest last in the queue
## (popped first), and lets go of those well past it.
func _rescan(c: Vector2) -> void:
	_scan_at = c
	var r := ceili(_reach / CountyRail.BIN) + 1
	var cb := Vector2i((c / CountyRail.BIN).floor())
	var want := []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var b := cb + Vector2i(dx, dz)
			if _built.has(b) or _dist(b, c) > _reach + CountyRail.BIN:
				continue
			if not CountyRail.routes_in(b).is_empty():
				want.append(b)
	for b in _built.keys():
		if _dist(b, c) > _reach + CountyRail.BIN * 3.0:
			for n in _built[b]:
				if n != null:
					n.queue_free()
			_built.erase(b)
			_unsink(b)
	want.sort_custom(func(a, b): return _dist(a, c) > _dist(b, c))
	_queue = want


static func _dist(b: Vector2i, c: Vector2) -> float:
	return ((Vector2(b) + Vector2(0.5, 0.5)) * CountyRail.BIN).distance_to(c)


## Lets go of the eased bed (_sunk) of a square no longer drawn.
static func _unsink(b: Vector2i) -> void:
	var box := Rect2(Vector2(b) * CountyRail.BIN, Vector2.ONE * CountyRail.BIN)
	for route in CountyRail.routes_in(b):
		var sunk: Dictionary = _sunk.get(route, {})
		if sunk.is_empty():
			continue
		var at: PackedVector2Array = CountyRail.profile(route).at
		for i in sunk.keys():
			if box.has_point(at[i]):
				sunk.erase(i)
		if sunk.is_empty():
			_sunk.erase(route)


func _town_has(p: Vector3) -> bool:
	return not is_nan(_street_y(p))


## The level of the town street whose pavement covers the track at `p`
## (a grade crossing; metres above sea level, as the bed), or NAN where
## none does: the street is drawn there, not the ballast. Nothing else of
## the town's stands on the right of way (CitySim._rail_under,
## CountyRail.road_check). Only the pavement, not the street's whole right
## of way, so a skewed crossing leaves no long gap in the track.
func _street_y(p: Vector3) -> float:
	if sim == null or sim.network.segments.is_empty():
		return NAN
	var hit := RoadIndex.segment_near(sim.network, p, 12.0)
	if hit.is_empty() or (hit.point as Vector3).y > CountyRail.ROAD_RAISED:
		return NAN
	if float(hit.dist) > RoadStyle.half_width(sim.network.segments[hit.seg].type) + 0.5:
		return NAN
	var q: Vector3 = hit.point
	return Terrain.base(q.x + _origin.x, q.z + _origin.y) + q.y


## The bed at metres `s` along a route, eased down where it crosses a town
## street (_sunk): what the county's trains ride on.
static func bed_at(route: int, s: float) -> float:
	var sunk: Dictionary = _sunk.get(route, {})
	if sunk.is_empty():
		return CountyRail.bed_at(route, s)
	var f := maxf(s / CountyRail.STEP, 0.0)
	var i := floori(f)
	var a: float = sunk.get(i, CountyRail.bed_at(route, i * CountyRail.STEP))
	var b: float = sunk.get(i + 1, CountyRail.bed_at(route, (i + 1) * CountyRail.STEP))
	return lerpf(a, b, f - i)


## The bed at sample i, eased down to each town street within
## CountyRail.RAMP (`paved`: sample -> the level of the street over it,
## _street_y) so the rail tops sit flush in it (TOWN_RAIL), the same curve
## CountyRail.profile gives the county's own road crossings.
static func _eased(i: int, bed: PackedFloat32Array, paved: Dictionary) -> float:
	var y := bed[i]
	var ramp := int(CountyRail.RAMP / CountyRail.STEP)
	for j in range(i - ramp, i + ramp + 1):
		if not paved.has(j):
			continue
		var flush: float = paved[j] - CountyRail.RAIL_TOP + TOWN_RAIL
		var t := clampf((absf(j - i) - 1.0) * CountyRail.STEP / (CountyRail.RAMP - CountyRail.STEP), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		y = minf(y, lerpf(flush, maxf(y, flush), t))
	return y


## The crown's height over the bed at `c` (a track centre, view
## coordinates): CROWN_Y, or where the bed eases down to a street under
## the ground beside it (its approach), up to the ground, as a crossing's
## approach is filled to the tie tops (a few cm over them at most, the
## last metres before the panels, where the lawn would cover them anyway).
static func _crown(c: Vector3) -> float:
	var g := Terrain.ground_y(c.x, c.z) + 0.04 - c.y
	return clampf(g, CROWN_Y, RailView.TIE_Y + 0.04)


## The ballast between samples c0 and c1 (their track centres at the bed,
## n0 and n1 their lefts): the crown, the shoulders, the cinder strip, and
## fill slopes down to the ground wherever the bed rides above it.
static func _ballast(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3) -> void:
	var y0 := Vector3(0, _crown(c0), 0)
	var y1 := Vector3(0, _crown(c1), 0)
	RailView._quad(st, c0 - n0 * CROWN_HALF + y0, c0 + n0 * CROWN_HALF + y0, c1 + n1 * CROWN_HALF + y1,
		c1 - n1 * CROWN_HALF + y1, STONE)
	var toe := CROWN_HALF + CROWN_Y * SHOULDER
	var down := Vector3(0, -SUBGRADE_DROP, 0)
	for side: float in [-1.0, 1.0]:
		var a0 := c0 + n0 * side * CROWN_HALF + y0
		var a1 := c1 + n1 * side * CROWN_HALF + y1
		var b0 := c0 + n0 * side * toe
		var b1 := c1 + n1 * side * toe
		RailView._quad(st, a0, b0, b1, a1, STONE_SIDE)
		var f0 := c0 + n0 * side * SUBGRADE_HALF + down
		var f1 := c1 + n1 * side * SUBGRADE_HALF + down
		RailView._quad(st, b0, f0, f1, b1, RailView.WEEDS)
		# Fill slopes at 2:1 (AREMA) down to the ground beside the track.
		var drop0 := minf(f0.y - Terrain.base_y(f0.x, f0.z), RailView.MAX_FILL)
		var drop1 := minf(f1.y - Terrain.base_y(f1.x, f1.z), RailView.MAX_FILL)
		if drop0 > 0.15 or drop1 > 0.15:
			var e0 := f0 + n0 * side * maxf(drop0, 0.0) * 2.0
			var e1 := f1 + n1 * side * maxf(drop1, 0.0) * 2.0
			e0.y = minf(f0.y, Terrain.ground_y(e0.x, e0.z)) - 0.3
			e1.y = minf(f1.y, Terrain.ground_y(e1.x, e1.z)) - 0.3
			RailView._quad(st, f0, e0, e1, f1, RailView.EARTH)


## Rubber panels from the paved end of c0-c1 (c0's when `from_c0`) to
## where the street's pavement ends, found by halving the step.
func _panel_to_edge(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3, from_c0: bool) -> void:
	var lo := 0.0  # paved
	var hi := 1.0  # not
	for k in 5:
		var t := (lo + hi) * 0.5
		var p := c0.lerp(c1, t if from_c0 else 1.0 - t)
		if _town_has(p):
			lo = t
		else:
			hi = t
	var a := c0 if from_c0 else c1
	var na := n0 if from_c0 else n1
	var e := c0.lerp(c1, lo if from_c0 else 1.0 - lo)
	var ne := n0.lerp(n1, lo if from_c0 else 1.0 - lo).normalized()
	var y := Vector3(0, CountyRail.RAIL_TOP - 0.02, 0)
	RailView._quad(st, a - na * 1.6 + y, a + na * 1.6 + y, e + ne * 1.6 + y, e - ne * 1.6 + y, RUBBER)


## The track in one square: every route's samples that fall in it, and
## the step on to the next sample, so squares meet.
func _build(b: Vector2i) -> Array:
	var box := Rect2(Vector2(b) * CountyRail.BIN, Vector2.ONE * CountyRail.BIN)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The browser's lighter look: the ballast in the one mesh, plain.
	var rock := st
	if not _light:
		rock = SurfaceTool.new()
		rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := st
	if not _light:
		rails = SurfaceTool.new()
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
		# The samples under a town street's pavement, from RAMP before the
		# square to RAMP past it (the ease reaches that far).
		var paved := {}
		var first := -1
		var last := -1
		for i in at.size():
			if box.has_point(at[i]):
				if first < 0:
					first = i
				last = i
		if first < 0:
			continue
		var ramp := int(CountyRail.RAMP / CountyRail.STEP)
		for j in range(maxi(first - ramp, 0), mini(last + ramp + 2, at.size())):
			if kind[j] != 2 and kind[j] != 3:
				var sy := _street_y(Vector3(at[j].x - o.x, bed[j], at[j].y - o.y))
				if not is_nan(sy):
					paved[j] = sy
		var sunk: Dictionary = _sunk.get(route, {})
		for i in range(first, last + 1):
			if not box.has_point(at[i]):
				continue
			var y := _eased(i, bed, paved) if not paved.is_empty() else bed[i]
			if y < bed[i] - 0.001:
				sunk[i] = y
			else:
				sunk.erase(i)
		if sunk.is_empty():
			_sunk.erase(route)
		else:
			_sunk[route] = sunk
		for i in range(first, mini(last + 1, at.size() - 1)):
			if not box.has_point(at[i]):
				continue
			if kind[i] == 3 or kind[i + 1] == 3:
				continue
			var c0 := Vector3(at[i].x - o.x, sunk.get(i, bed[i]), at[i].y - o.y)
			var c1 := Vector3(at[i + 1].x - o.x, _eased(i + 1, bed, paved) if not paved.is_empty() else bed[i + 1], at[i + 1].y - o.y)
			var bridge := kind[i] == 2 or kind[i + 1] == 2
			if bridge and (_town_has(c0) or _town_has(c1)):
				continue
			# A grade crossing: a county road's (kind 1) or a town street's.
			var xing := (kind[i] == 1 and kind[i + 1] == 1) or (paved.has(i) and paved.has(i + 1))
			var n0 := _left(at, i)
			var n1 := _left(at, i + 1)
			if not xing and paved.has(i) != paved.has(i + 1):
				# The pavement's edge falls between the samples: panels over
				# the paved part only, the track as usual under the rest.
				_panel_to_edge(st, c0, c1, n0, n1, paved.has(i))
			any = true
			if bridge:
				RailView._bridge_span(st, c0, c1, n0, n1, i)
			elif xing:
				# A grade crossing: rubber panels across the track's width,
				# level with the rail tops, as the road runs over it.
				var y := Vector3(0, CountyRail.RAIL_TOP - 0.02, 0)
				RailView._quad(st, c0 - n0 * 1.6 + y, c0 + n0 * 1.6 + y, c1 + n1 * 1.6 + y, c1 - n1 * 1.6 + y, RUBBER)
			else:
				_ballast(rock, c0, c1, n0, n1)
				# Double track: one crown of ballast across both, not two
				# prisms with a ditch between.
				var pair: Dictionary = prof.get("pair", {})
				if pair.has(i) and pair.has(i + 1):
					var y := Vector3(0, CROWN_Y, 0)
					var q0: Vector2 = pair[i] - o
					var q1: Vector2 = pair[i + 1] - o
					RailView._quad(rock, c0 + y, Vector3(q0.x, c0.y, q0.y) + y, Vector3(q1.x, c1.y, q1.y) + y, c1 + y, RailView.BALLAST)
			for side: float in [-1.0, 1.0]:
				RailView._rail(rails, c0 + n0 * side * RailModels.GAUGE * 0.5, c1 + n1 * side * RailModels.GAUGE * 0.5, n0, n1)
			if _light:
				continue  # no ties
			if xing:
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
	out.append(_instance(st.commit(), _reach))
	if _light:
		return out
	rock.index()
	rock.generate_normals()
	var ri := _instance(rock.commit(), _reach)
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
