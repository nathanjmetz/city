class_name GravelDust
extends MultiMeshInstance3D
## Dust behind cars on gravel and dirt roads in dry weather: a pale
## limestone plume that rises, spreads and drifts off for a few seconds.
## None on snow or in the spring thaw (March and April, when the roads are
## wet), none from a car under about 20 mph, and only near the camera.
## Reads the cars from TrafficSim (read only).

const MAX_PUFFS := 160
const LIFE := 6.0
const EVERY := 0.12      # seconds between puffs from one car
const MIN_SPEED := 9.0   # m/s, about 20 mph
const REACH := 700.0     # metres from the camera
const DUST := Color(0.76, 0.72, 0.64)

var sim
var _puffs := []   # [position, age, size, drift]
var _since := {}   # car id -> seconds since its last puff
var _wind := Vector3(0.6, 0.0, 0.25)



func setup(s) -> void:
	sim = s


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = MAX_PUFFS
	mm.visible_instance_count = 0
	multimesh = mm
	# A soft round puff, always facing the camera, its size from the
	# instance's scale and its strength from the instance's colour.
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.8))
	soft.gradient = g
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if sim == null or multimesh == null:
		return
	var t := Perf.now()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var yf := fposmod(Seasons.months(int(sim.tick_count)), 12.0) / 12.0
	var dry := Seasons.snow_now < 0.05 and not (yf > 0.17 and yf < 0.33)
	if cam != null and dry and GraphicsQuality.detail >= 0.6:
		_emit(cam.global_position - global_position, delta)
	_age(delta)
	Perf.add("frame.road_wear", t)


func _emit(eye: Vector3, delta: float) -> void:
	var tr: TrafficSim = sim.traffic
	for car in tr.cars:
		if not car.has("route") or car.get("j") != null or float(car.get("v", 0.0)) < MIN_SPEED:
			continue
		var w = tr.ways.get(car.route[car.leg])
		if w == null or not int(w.type) in [RoadStyle.Type.GRAVEL, RoadStyle.Type.DIRT]:
			continue
		var id: int = car.get("id", 0)
		var since: float = _since.get(id, EVERY) + delta
		if since < EVERY:
			_since[id] = since
			continue
		_since[id] = 0.0
		var pose: Array = tr.car_pose(car)
		var pos: Vector3 = pose[0]
		if pos.distance_to(eye) > REACH or _puffs.size() >= MAX_PUFFS:
			continue
		var back: Vector3 = pose[1]
		pos = Terrain.lift(pos - back * 3.5) + Vector3(0, 0.8, 0)
		var speed := clampf((float(car.v) - MIN_SPEED * 0.7) / 8.0, 0.4, 1.0)
		_puffs.append([pos, 0.0, speed, back * -1.5])
	if _since.size() > 4 * MAX_PUFFS:
		_since.clear()


func _age(delta: float) -> void:
	var keep := []
	for p in _puffs:
		p[1] += delta
		if p[1] < LIFE:
			p[0] += (_wind + p[3] * exp(-p[1])) * delta + Vector3(0, 0.35 * delta, 0)
			keep.append(p)
	_puffs = keep
	var mm := multimesh
	mm.visible_instance_count = _puffs.size()
	for i in _puffs.size():
		var p: Array = _puffs[i]
		var life: float = p[1] / LIFE
		var size: float = lerpf(2.5, 10.0, sqrt(life)) * (0.6 + 0.4 * float(p[2]))
		# Lifted by most of its size, so the ground doesn't cut the puff square.
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p[0] + Vector3(0, size * 0.35, 0)))
		mm.set_instance_color(i, Color(DUST, 0.6 * smoothstep(0.0, 0.05, life) * pow(1.0 - life, 1.5) * float(p[2])))
