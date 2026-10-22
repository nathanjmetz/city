class_name TrafficView
extends MultiMeshInstance3D
## Draws every car in one batch, moved on smoothly between simulation ticks.

const COLORS := [
	Color(0.85, 0.85, 0.84), Color(0.12, 0.12, 0.13), Color(0.55, 0.57, 0.6), Color(0.62, 0.1, 0.1),
	Color(0.12, 0.22, 0.45), Color(0.75, 0.75, 0.78), Color(0.25, 0.3, 0.28), Color(0.55, 0.45, 0.32),
]

var traffic: TrafficSim
## Returns how far through the current tick the clock is, 0 to 1.
var tick_fraction: Callable


func setup(t: TrafficSim, fraction: Callable) -> void:
	traffic = t
	tick_fraction = fraction


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _car_mesh()
	mm.instance_count = TrafficSim.MAX_CARS
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	mat.metallic = 0.3
	material_override = mat


func _process(_delta: float) -> void:
	var cars := traffic.cars
	var n := mini(cars.size(), TrafficSim.MAX_CARS)
	var frac: float = tick_fraction.call()
	for i in n:
		var car: Dictionary = cars[i]
		var pose := traffic.car_pose(car, car.v * TrafficSim.DT * frac)
		var dir: Vector3 = pose[1]
		var basis := Basis.looking_at(dir, Vector3.UP)
		multimesh.set_instance_transform(i, Transform3D(basis, pose[0]))
		multimesh.set_instance_color(i, COLORS[car.color])
	multimesh.visible_instance_count = n


## A sedan about 4.6 m long: body and a cabin with dark windows.
static func _car_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	# Local -Z is the front of the car.
	_box(st, Vector3(0, 0.55, 0), Vector3(1.8, 0.7, 4.6), Color.WHITE)
	_box(st, Vector3(0, 1.15, 0.25), Vector3(1.6, 0.55, 2.4), Color(0.25, 0.28, 0.32))
	st.generate_normals()
	return st.commit()


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, tint: Color) -> void:
	st.set_color(tint)
	var h := size * 0.5
	var v := []
	for k in 8:
		v.append(c + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	# Faces wound clockwise from outside, as Godot expects.
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		for idx in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(v[idx])
