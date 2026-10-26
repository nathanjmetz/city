extends SceneTree
## Close-up lab: how much detail cars and people can carry at the closest
## zoom (CityCamera.MIN_DIST), and what it costs. Opens the real game with
## the test town, hides the game's own traffic and walkers, and draws a
## street of parked and passing cars and people walking at one of these
## levels:
##   0 today      cars LOD 0, today's box walkers
##   1 ultra      cars LOD Ultra, today's box walkers
##   2 browser    cars LOD 0, shaped people (tools/closeup/people.gd lvl 1)
##   3 desktop    Ultra cars with see-through glass, cabin and driver;
##                dressed people with knees and elbows, casting shadows
##   4 ceiling    as 3 with hands, faces, belts and soles on people
## shot: saves a picture. bench: also fills the view with the worst case a
## dense downtown can show (every walker the game allows near the camera,
## a thousand cars within close range) and records frame cost.
## Run: xvfb-run godot [--rendering-driver opengl3] --resolution 1920x1080 --quality ultra
##        -s tools/closeup_lab.gd -- shot|bench LEVEL big|huge OUT(.png|.json)

const People := preload("res://tools/closeup/people.gd")
const Cars := preload("res://tools/closeup/cars.gd")
const NAMES := ["today", "ultra", "browser", "desktop", "ceiling"]
const KINDS := ["sedan", "pickup", "suv", "crossover", "minivan", "pickup_ext", "suv_mid", "sedan_compact", "wagon", "hatchback"]
## Midwest street, a fall afternoon: work boots and seed caps, hoodies,
## a canvas work jacket, a kid with a backpack, an older man in khakis.
const OUTFITS := [
	["man", {"sleeve": "short", "cap": Color(0.2, 0.4, 0.18), "boots": true}],
	["man", {"jacket": true, "boots": true, "hair": "short", "cap": Color(0.75, 0.45, 0.15)}],
	["woman", {"sleeve": "long", "hair": "pony", "bag": "tote", "shoe": Color(0.85, 0.84, 0.82)}],
	["woman", {"hood": true, "hair": "long"}],
	["child", {"hood": true, "bag": "backpack", "shoe": Color(0.8, 0.2, 0.15)}],
	["older", {"jacket": true, "khaki": true, "cap": Color(0.15, 0.17, 0.3), "hair": "short"}],
]
const SHIRTS := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.85, 0.82, 0.74),
	Color(0.24, 0.42, 0.26), Color(0.9, 0.62, 0.2), Color(0.35, 0.35, 0.38), Color(0.55, 0.38, 0.6),
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.42, 0.3, 0.2)]
const PERSON_SHADER := """shader_type spatial;
render_mode cull_disabled;
varying vec3 tint;
varying float rough;
const vec3 TROUSERS[6] = vec3[](vec3(0.16,0.22,0.36), vec3(0.1,0.12,0.2), vec3(0.08,0.08,0.09), vec3(0.32,0.34,0.36), vec3(0.24,0.3,0.42), vec3(0.3,0.25,0.2));
const vec3 SKINS[6] = vec3[](vec3(0.89,0.72,0.6), vec3(0.8,0.6,0.47), vec3(0.62,0.45,0.33), vec3(0.45,0.31,0.22), vec3(0.3,0.2,0.14), vec3(0.93,0.78,0.68));
const vec3 HAIRS[6] = vec3[](vec3(0.12,0.08,0.05), vec3(0.3,0.2,0.12), vec3(0.55,0.42,0.26), vec3(0.06,0.05,0.05), vec3(0.62,0.6,0.58), vec3(0.45,0.25,0.12));
vec4 custom_data(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
vec2 turn(vec2 yz, float py, float a) {
	float c = cos(a); float s = sin(a); float y = yz.x - py;
	return vec2(py + y * c - yz.y * s, y * s + yz.y * c);
}
void vertex() {
	vec4 custom = custom_data(INSTANCE_CUSTOM);
	int idx = int(floor(custom.a));
	float ph = fract(custom.a) * 6.2831853;
	float code = COLOR.a;
	if (code < 0.12) { tint = lin(custom.rgb); rough = 0.92; }
	else if (code < 0.37) { tint = lin(TROUSERS[idx % 6]); rough = 0.95; }
	else if (code < 0.62) { tint = lin(SKINS[(idx / 6) % 6]); rough = 0.6; }
	else if (code < 0.87) { tint = lin(HAIRS[(idx / 36) % 6]); rough = 0.75; }
	else { tint = lin(COLOR.rgb); rough = 0.7; }
	float side = sign(UV.x);
	float a = UV.x * 0.42 * sin(ph);
	vec2 yz = VERTEX.yz;
	vec2 nyz = NORMAL.yz;
	if (UV2.x > 0.5 && UV2.x < 1.5) {        // shin: the knee folds in the swing
		float k = -(0.12 + 0.95 * pow(max(0.0, side * cos(ph)), 2.0));
		yz = turn(yz, UV2.y, k); nyz = turn(nyz, 0.0, k);
	} else if (UV2.x > 1.5) {                 // forearm: carried a little bent
		float k = 0.25 + 0.2 * max(0.0, -side * sin(ph));
		yz = turn(yz, UV2.y, k); nyz = turn(nyz, 0.0, k);
	}
	if (UV.x != 0.0) { yz = turn(yz, UV.y, a); nyz = turn(nyz, 0.0, a); }
	VERTEX.yz = yz;
	NORMAL.yz = nyz;
	VERTEX.y -= 0.8 * (1.0 - cos(0.42 * sin(ph)));
}
void fragment() { ALBEDO = tint; ROUGHNESS = rough; SPECULAR = 0.35; }
"""
const GLASS_SHADER := """shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.015, 0.02, 0.025);
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	ALPHA = mix(0.5, 0.97, fres);
}
"""

var _main: Node
var _frames := 0
var _mode := "shot"
var _level := 0
var _size := "big"
var _out := ""
var _cam: CityCamera
var _aim := Vector3.ZERO
var _dir := Vector3.RIGHT
var _hw := 4.0
var _people := []     # [MultiMesh, MultiMesh far, [walkers]]
var _walkers := []    # {p: Vector3, dir, s, idx, shirt, var}
var _cars := []       # {xf, kind, paint, moving}
var _car_mm := {}     # key -> MultiMesh
var _t := 0.0
var _rows := {"cpu_ms": 0.0, "frame_ms": 0.0, "gpu_ms": 0.0, "draw_calls": 0.0, "primitives": 0.0, "n": 0}
var _segs := []
var _wait := 0
var _dists := []
var _views := {}
var _fill := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_mode = a[0] if a.size() > 0 else "shot"
	_level = int(a[1]) if a.size() > 1 else 0
	_size = a[2] if a.size() > 2 else "big"
	_out = a[3] if a.size() > 3 else "closeup.png"
	_dists = Array(a[4].split(",")) if a.size() > 4 else []
	_fill = a.size() > 5 and a[5] == "fill"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, _size)
		_main.set_speed(0)
		sim.tick_count = int(15.5 * 60.0 / CitySim.MINUTES_PER_TICK)  # mid afternoon
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
			if c is TrafficView or c is WalkerView or c is BusView:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				c.visible = false
		_find_street(sim)
		return false
	if _frames < 60:
		return false
	if _frames == 60:
		for c in _main.get_children():
			if c is BuildingView and not c.idle() and _wait < 150:
				_wait += 1
				_frames = 59
				return false
		print("lab setup at ", Time.get_ticks_msec())
		_setup()
		return false
	var t0 := Time.get_ticks_usec()
	_t += 1.0 / 60.0 if _mode == "bench" else 0.0
	_update()
	var cpu := (Time.get_ticks_usec() - t0) / 1000.0
	var f := _frames - 60
	if _mode == "shot" and (f - 40) % 45 == 0 and f >= 40:
		var k := (f - 40) / 45
		if _dists.is_empty():
			root.get_texture().get_image().save_png(_out)
			quit()
		else:
			var tag: String = str(_dists[k]).replace(":", "m-p")
			root.get_texture().get_image().save_png(_out.get_basename() + "-" + tag + ".png")
			_views[tag] = {"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"cars_in_view": _in_view(_cars), "people_in_view": _in_view(_walkers)}
			if k + 1 >= _dists.size():
				FileAccess.open(_out.get_basename() + ".json", FileAccess.WRITE).store_string(JSON.stringify(_views, "  "))
				quit()
			else:
				_view_at(_dists[k + 1])
	if _mode == "bench":
		if f > 40:
			var vp := root.get_viewport_rid()
			_rows.cpu_ms += cpu
			_rows.frame_ms += delta * 1000.0
			_rows.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			_rows.draw_calls = maxf(_rows.draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			_rows.primitives = maxf(_rows.primitives, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			_rows.n += 1
		if f == 30:
			RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		if f == 40:
			root.get_texture().get_image().save_png(_out.get_basename() + ".png")
		if f == 100:
			var n: float = _rows.n
			var rep := {"level": NAMES[_level], "town": _size, "population": _main.sim.stats.population,
				"people": _walkers.size(), "cars": _cars.size(),
				"cpu_ms": _rows.cpu_ms / n, "frame_ms": _rows.frame_ms / n, "gpu_ms": _rows.gpu_ms / n,
				"draw_calls": _rows.draw_calls, "primitives": _rows.primitives,
				"renderer": RenderingServer.get_current_rendering_driver_name(),
				"person_tris": _tris(_person_mesh(0)), "car_tris": _tris(_car_mesh("sedan", 2 if _level >= 1 else 0))}
			print(JSON.stringify(rep))
			FileAccess.open(_out, FileAccess.WRITE).store_string(JSON.stringify(rep, "  "))
			quit()
	return false


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
	return n


## A plain street in the test town's homes, running east-west.
func _find_street(sim: CitySim) -> void:
	var want := Vector3(-200, 0, -140)
	var best := INF
	for id in sim.network.segments:
		var c := sim.network.curve_of(id)
		var mid: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		var d: Vector3 = c[2] - c[0]
		var mid2 := Vector3(mid.x, 0, mid.z)
		_segs.append([c, sim.network.segments[id].type])
		if absf(d.z) > 1.0 or absf(d.x) < 100.0:
			continue
		var dist := mid2.distance_to(want)
		if dist < best:
			best = dist
			_aim = mid2
			_dir = Vector3(signf(d.x), 0, 0)
			_hw = RoadStyle.half_width(sim.network.segments[id].type)


func _setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var walk := _hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
	var side := Vector3(-_dir.z, 0, _dir.x)
	# The street in the picture: cars at both curbs, two passing, and
	# people along the near sidewalk and crossing the far one.
	var x := -34.0
	var i := 0
	while x < 40.0:
		for s in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				continue
			var p: Vector3 = _aim + _dir * (x + rng.randf() * 0.6) + side * s * (_hw - 1.15)
			_park(p, _dir * s, KINDS[i % KINDS.size()], i)
			i += 1
		x += 7.6
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		_cars.append({"p": _aim + _dir * (-6.0 + k * 13.0) + side * s * _hw * 0.3, "dir": _dir * -s, "kind": ["pickup", "crossover"][k], "paint": SHIRTS[k * 4], "v": 9.0})
	for k in 16:
		var s := 1.0 if k < 10 else -1.0
		var along := -18.0 + k % 10 * 4.1 + rng.randf() * 2.0
		_walkers.append({"p": _aim + _dir * along + side * s * (walk + (rng.randf() - 0.5) * 0.7),
			"dir": _dir * (1.0 if rng.randf() < 0.5 else -1.0), "idx": rng.randi() % 216, "shirt": SHIRTS[k % SHIRTS.size()],
			"var": k % OUTFITS.size(), "ph": rng.randf(), "v": 1.35 if k % 5 != 3 else 0.0})
	if _mode == "bench" or _fill:
		_fill_worst_case(rng)
	_build_batches()
	_cam.look_at_point(Terrain.lift(_aim + side * 3.0))
	var yaw := atan2(_dir.x, _dir.z) + deg_to_rad(65.0)
	_cam.set_view(yaw, deg_to_rad(18.0), CityCamera.MIN_DIST)
	if not _dists.is_empty():
		_view_at(_dists[0])


## Cars or people inside the camera's view.
func _in_view(list: Array) -> int:
	var n := 0
	for o in list:
		if _cam.camera.is_position_in_frustum(Terrain.stand(o.p)):
			n += 1
	return n


## Zoom distances to picture, for choosing the closest zoom: the camera
## keeps its angle and aims at the near curb, where cars and people meet.
func _view_at(spec) -> void:
	var parts := str(spec).split(":")
	var dist := float(parts[0])
	var side := Vector3(-_dir.z, 0, _dir.x)
	var yaw := atan2(_dir.x, _dir.z) + deg_to_rad(65.0)
	var near := Vector3(sin(yaw), 0, cos(yaw))
	var s := signf(side.dot(near))
	_cam.look_at_point(Terrain.lift(_aim + side * s * (_hw + 0.8) + _dir * 4.0))
	_cam.set_view(yaw, deg_to_rad(float(parts[1]) if parts.size() > 1 else (18.0 if dist >= 20.0 else 14.0)), dist)


func _park(p: Vector3, dir: Vector3, kind: String, i: int) -> void:
	_cars.append({"p": p, "dir": dir, "kind": kind, "paint": VehicleTypes.CAR_COLORS[(i * 7) % VehicleTypes.CAR_COLORS.size()][0], "v": 0.0})


## The worst a downtown shows at the closest zoom: the game's walker cap
## (TrafficSim.MAX_WALKERS) all within the walker draw range, and a
## thousand cars (parked and moving) within close-up car range.
func _fill_worst_case(rng: RandomNumberGenerator) -> void:
	var near := []
	for s in _segs:
		var c: Array = s[0]
		var mid: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		if Vector2(mid.x - _aim.x, mid.z - _aim.z).length() < 300.0:
			near.append(s)
	if near.is_empty():
		return
	var people_cap := TrafficSim.MAX_WALKERS
	while _walkers.size() < people_cap:
		var s: Array = near[rng.randi() % near.size()]
		var c: Array = s[0]
		var t := rng.randf()
		var p: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], t)
		var tan: Vector3 = RoadNetwork.bezier_tangent(c[0], c[1], c[2], t).normalized()
		var off := RoadStyle.half_width(s[1]) + 2.85
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		_walkers.append({"p": Vector3(p.x, 0, p.z) + Vector3(-tan.z, 0, tan.x) * off * sd, "dir": tan * sd,
			"idx": rng.randi() % 216, "shirt": SHIRTS[rng.randi() % SHIRTS.size()], "var": rng.randi() % OUTFITS.size(),
			"ph": rng.randf(), "v": 1.35})
	while _cars.size() < 1000:
		var s: Array = near[rng.randi() % near.size()]
		var c: Array = s[0]
		var t := rng.randf()
		var p: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], t)
		var tan: Vector3 = RoadNetwork.bezier_tangent(c[0], c[1], c[2], t).normalized()
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		var moving := rng.randf() < 0.4
		var off := RoadStyle.half_width(s[1]) - (3.4 if moving else 1.15)
		_cars.append({"p": Vector3(p.x, 0, p.z) + Vector3(-tan.z, 0, tan.x) * off * sd, "dir": tan * sd,
			"kind": KINDS[rng.randi() % KINDS.size()], "paint": VehicleTypes.CAR_COLORS[rng.randi() % VehicleTypes.CAR_COLORS.size()][0],
			"v": 9.0 if moving else 0.0})


## The people mesh for an outfit at this level (near), or its far stand-in.
func _person_mesh(v: int, far := false) -> Mesh:
	var lvl: int = [0, 0, 1, 2, 3][_level]
	if far:
		lvl = mini(lvl, 1)
	if lvl == 0:
		return WalkerView._person_mesh()
	return People.build(lvl, OUTFITS[v][0], OUTFITS[v][1])


func _car_mesh(kind: String, lod: int) -> Mesh:
	if lod == 2 and _level >= 3:
		var m := Cars.build_split(kind, true, kind.hash() & 0xff)
		m.surface_set_material(0, VehicleMaterial.get_material(true))
		var g := ShaderMaterial.new()
		g.shader = Shader.new()
		g.shader.code = GLASS_SHADER
		m.surface_set_material(1, g)
		return m
	return VehicleModels.build(kind, lod)


func _build_batches() -> void:
	var pmat := ShaderMaterial.new()
	pmat.shader = Shader.new()
	if _level < 2:
		var wv := WalkerView.new()
		wv._ready()
		pmat = (wv.get_child(0) as MultiMeshInstance3D).material_override
	else:
		pmat.shader.code = PERSON_SHADER
	var nv := 1 if _level < 2 else OUTFITS.size()
	for v in nv:
		var pair := []
		for far in [false, true]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _person_mesh(v, far)
			mm.instance_count = _walkers.size()
			for i in mm.instance_count:
				mm.set_instance_color(i, Color.WHITE)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = pmat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _level >= 3 and not far else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_main.add_child(mi)
			pair.append(mm)
		_people.append(pair)
	for kind in KINDS + ["pickup", "crossover"]:
		for lod in [0, 1, 2]:
			var key: String = kind + str(lod)
			if _car_mm.has(key) or lod == 2 and _level == 0 or lod == 2 and _level == 2:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _car_mesh(kind, lod)
			mm.instance_count = _cars.size()
			for i in mm.instance_count:
				mm.set_instance_color(i, Color.WHITE)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			if not (lod == 2 and _level >= 3):
				mi.material_override = VehicleMaterial.get_material(lod == 2)
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_main.add_child(mi)
			_car_mm[key] = mm


## Places everyone for this frame, as the game's views do: distance picks
## the level of detail, walkers further than WalkerView.FAR aren't drawn.
func _update() -> void:
	var eye := _cam.camera.global_position
	var counts := {}
	for pair in _people:
		pair[0].visible_instance_count = 0
		pair[1].visible_instance_count = 0
	var nv := _people.size()
	for w in _walkers:
		var p: Vector3 = Terrain.stand(w.p + w.dir * w.v * _t)
		var d := p.distance_to(eye)
		if d > WalkerView.FAR:
			continue
		var v: int = w.var % nv
		var far := 1 if d > 60.0 else 0
		var mm: MultiMesh = _people[v][far]
		var n := mm.visible_instance_count
		mm.set_instance_transform(n, Transform3D(Basis.looking_at(w.dir, Vector3.UP), p))
		var shirt: Color = w.shirt
		var stride := fposmod(w.ph + w.v * _t / WalkerView.STRIDE, 1.0) if w.v > 0.0 else 0.0
		shirt.a = (float(w.idx) + stride) if _level >= 2 else stride
		mm.set_instance_custom_data(n, shirt)
		mm.visible_instance_count = n + 1
	for k in _car_mm:
		_car_mm[k].visible_instance_count = 0
	var ultra := _level == 1 or _level >= 3
	for c in _cars:
		var p: Vector3 = Terrain.stand(c.p + c.dir * c.v * _t)
		var d := p.distance_to(eye)
		if d > TrafficView.FAR:
			continue
		var lod := 1
		if d < TrafficView.NEAR:
			lod = 2 if ultra and d < TrafficView.ULTRA_NEAR else 0
		var mm: MultiMesh = _car_mm[c.kind + str(lod)]
		var n := mm.visible_instance_count
		mm.set_instance_transform(n, Transform3D(Basis.looking_at(c.dir, Vector3.UP), p))
		var paint: Color = c.paint
		mm.set_instance_custom_data(n, Color(paint.r, paint.g, paint.b, 0.0))
		mm.visible_instance_count = n + 1
