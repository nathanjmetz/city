class_name CountyTrainView
extends Node3D
## Draws the through freights on the county's real railroads (CountyTrains)
## on the desktop app: road diesels in the road railroad's black and white,
## and their cars, on the rails CountyRailView lays, out to DRAW_TO from the
## camera. Inside a backdrop town, where the track isn't drawn, neither are
## its trains.

## Metres from the camera trains are drawn to.
const DRAW_TO := 3500.0
## Stock kind -> the model drawn for it.
const MODEL := {"gp38": "gp38_road", "sd40": "sd40_road", "covered": "covered", "tank": "tank",
	"hopper": "hopper", "boxcar": "boxcar"}

var sim: CitySim
var _frac: Callable
var _cars := {}  # model -> MultiMeshInstance3D


func setup(s: CitySim, frac: Callable) -> void:
	sim = s
	_frac = frac


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.6
	mat.metallic = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for kind in MODEL.values():
		if _cars.has(kind):
			continue
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true  # white: the browser multiplies vertex colours by it
		m.mesh = RailModels.build(kind)
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = m
		inst.material_override = mat
		add_child(inst)
		_cars[kind] = inst


func _process(_delta: float) -> void:
	if sim == null or not sim.county_rail:
		visible = false
		return
	visible = true
	var cam := get_viewport().get_camera_3d()
	var eye := Vector2(cam.global_position.x, cam.global_position.z) if cam else Vector2.ZERO
	eye += Terrain.view_origin
	var lists := poses(sim.tick_count, _frac.call() if _frac.is_valid() else 0.0, eye, DRAW_TO)
	for kind in _cars:
		var mm: MultiMesh = _cars[kind].multimesh
		var list: Array = lists.get(kind, [])
		if list.size() > mm.instance_count:
			mm.instance_count = maxi(list.size() * 2, 16)
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, Color.WHITE)
		mm.visible_instance_count = list.size()


## Every car within `reach` of `eye` (region coordinates) at tick `tick`
## plus `frac` of the next: model -> [Transform3D in view coordinates].
static func poses(tick: int, frac: float, eye: Vector2, reach: float) -> Dictionary:
	var out := {}
	var cs := CountyTrains.corridors()
	for t in CountyTrains.trains_at(tick, CountyTrains.SEED):
		var c: Dictionary = cs[t.corridor]
		var head: float = float(t.s) + float(t.dir) * CountyTrains.SPEED * TrafficSim.DT * frac
		# Skip a train with no part near the camera.
		var tail: float = head - float(t.dir) * float(t.length)
		var lo := maxf(minf(head, tail), 0.0)
		var hi := minf(maxf(head, tail), float(c.length))
		if hi <= lo:
			continue
		if not _near(c, lo, hi, eye, reach):
			continue
		var x := 0.0
		for car in t.consist:
			var L := CountyTrains.stock_len(car[0])
			var sf: float = head - float(t.dir) * (x + 0.5)
			var sb: float = head - float(t.dir) * (x + L - 0.5)
			x += L + CountyTrains.GAP_CARS
			if minf(sf, sb) < 0.0 or maxf(sf, sb) > float(c.length):
				continue
			var f := CountyTrains._at(c, sf)
			var b := CountyTrains._at(c, sb)
			if f.distance_to(eye) > reach:
				continue
			var fy := _rail_y(f)
			var by := _rail_y(b)
			if is_nan(fy) or is_nan(by):
				continue  # inside a backdrop town: its track isn't drawn
			var front := Vector3(f.x - Terrain.view_origin.x, fy, f.y - Terrain.view_origin.y)
			var back := Vector3(b.x - Terrain.view_origin.x, by, b.y - Terrain.view_origin.y)
			var dir := front - back
			if dir.length() < 0.1:
				continue
			var model: String = MODEL.get(car[0], car[0])
			if not out.has(model):
				out[model] = []
			out[model].append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (front + back) * 0.5))
	return out


## Whether any of corridor c between lo and hi metres comes within reach.
static func _near(c: Dictionary, lo: float, hi: float, eye: Vector2, reach: float) -> bool:
	var s := lo
	while s < hi:
		if CountyTrains._at(c, s).distance_to(eye) < reach + 500.0:
			return true
		s += 500.0
	return CountyTrains._at(c, hi).distance_to(eye) < reach + 500.0


## The rail top at a point of the county's track, or NAN where it isn't
## drawn (a backdrop town) or there's no mapped track (a gap in the data).
static func _rail_y(p: Vector2) -> float:
	var n := CountyRail.near(p.x, p.y, 8.0)
	if n.is_empty():
		return Terrain.base(p.x, p.y) + CountyRail.RAIL_TOP
	if CountyRail.kind_at(n.route, n.along) == 3:
		return NAN
	return CountyRail.bed_at(n.route, n.along) + CountyRail.RAIL_TOP
