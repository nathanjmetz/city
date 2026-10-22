class_name Headlights
extends MultiMeshInstance3D
## At night, the patch of road each car's low beams light up ahead of it.
## (The lamps themselves glow in the vehicle shader.) One MultiMesh for every
## car near the camera, drawn only after dark.

## Low beams reach about 50 m on a real car; the bright part is the first
## 15 m or so, which is what reads from a city-builder camera.
const LENGTH := 16.0
const WIDTH := 4.2
const RANGE := 450.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
void fragment() {
	// UV.y runs from the bumper (1) to the far end (0) of the beam.
	float along = 1.0 - UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float spread = mix(0.45, 1.0, along);
	float f = (1.0 - smoothstep(spread * 0.6, spread, across)) * pow(1.0 - along, 1.6) * smoothstep(0.0, 0.08, along);
	ALBEDO = vec3(1.0, 0.93, 0.8) * f * 0.5 * smoothstep(0.3, 0.7, night);
}
"""

var traffic: TrafficSim
var tick_fraction := Callable()
## 0 by day, 1 at night (DayNight sets it).
var amount := 0.0


func setup(t: TrafficSim, fraction := Callable()) -> void:
	traffic = t
	tick_fraction = fraction


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, LENGTH)
	quad.orientation = PlaneMesh.FACE_Y
	# The quad's centre sits half a beam ahead of the bumper.
	quad.center_offset = Vector3(0, 0, -LENGTH * 0.5)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	visible = amount > 0.0 and traffic != null
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var frac: float = tick_fraction.call() if tick_fraction.is_valid() else 0.0
	var list := []
	for car in traffic.cars:
		var ahead: float = car.v * TrafficSim.DT * frac
		var pose: Array = traffic.car_pose(car, ahead)
		var front: Vector3 = pose[0]
		if front.distance_to(eye) > RANGE:
			continue
		var dir: Vector3 = pose[1]
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		var origin := front + Vector3(0, RoadStyle.Y_JUNCTION + 0.05, 0)
		list.append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), origin))
	if list.size() > multimesh.instance_count:
		multimesh.instance_count = maxi(list.size() * 2, 32)
	for i in list.size():
		multimesh.set_instance_transform(i, list[i])
	multimesh.visible_instance_count = list.size()
