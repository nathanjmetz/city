class_name TrafficTool
extends Node3D
## Traffic info view and junction controls, like the Cities: Skylines 2
## traffic view plus the TM:PE junction tools. While it's open, roads are
## coloured by traffic flow; pick a control and click junctions to set it.

signal mode_changed(mode: int)
signal hint_changed(text: String)

enum Mode { NONE, VIEW, AUTO, SIGNAL, ALL_STOP, STOP, NO_CONTROL }

const RULE_FOR := {
	Mode.AUTO: -1, Mode.SIGNAL: TrafficSim.Rule.SIGNAL, Mode.ALL_STOP: TrafficSim.Rule.ALL_STOP,
	Mode.STOP: TrafficSim.Rule.PRIORITY, Mode.NO_CONTROL: TrafficSim.Rule.NONE,
}
const RULE_NAME := ["no signs or lights", "traffic lights", "an all-way stop", "stop signs on the side road"]

var sim: CitySim
var cam: CityCamera
var flow_view: FlowView
var mode := Mode.NONE

var _ring := MeshInstance3D.new()
var _hover := -1
var _hint := ""
var _refresh := 0.0


func setup(s: CitySim, camera: CityCamera, fv: FlowView) -> void:
	sim = s
	cam = camera
	flow_view = fv


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func set_mode(m: int) -> void:
	mode = m
	flow_view.visible = m != Mode.NONE
	_ring.visible = false
	_hover = -1
	_hint = ""
	mode_changed.emit(mode)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and not cam.right_dragged:
		set_mode(Mode.NONE)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed \
			and _hover != -1 and RULE_FOR.has(mode):
		sim.apply({"type": "set_junction", "node": _hover, "rule": RULE_FOR[mode]})
		_hint = ""
		_update_hint()


## J opens and closes the traffic view.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and KeyBinds.matches(k, "traffic"):
		set_mode(Mode.VIEW if mode == Mode.NONE else Mode.NONE)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if mode == Mode.NONE:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_update_hint()
	var hit = cam.mouse_ground_point()
	var node := -1
	if hit != null and RULE_FOR.has(mode):
		node = _junction_near(hit)
	if node != _hover:
		_hover = node
		_update_hint()
	_ring.visible = node != -1
	if node != -1:
		var r := RoadStyle.half_width(sim.network.widest_at(node)) + 3.0
		_ring.position = Terrain.lift(sim.network.nodes[node]) + Vector3(0, 0.4, 0)
		_ring.scale = Vector3(r, 1.0, r)


## The closest junction (three or more roads) to a point, or -1.
func _junction_near(p: Vector3) -> int:
	var best := -1
	var best_d := 30.0
	for n in sim.traffic.junctions:
		if sim.network.segments_at(n).size() < 3:
			continue
		var q: Vector3 = sim.traffic.junctions[n].pos
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


func _update_hint() -> void:
	if mode == Mode.NONE:
		return
	var text := "Traffic flow: green moves at the limit, red is jammed. %d%% overall, %d cars." \
		% [roundi(sim.traffic.flow * 100.0), sim.traffic.cars.size()]
	if RULE_FOR.has(mode):
		text = ["", "", "Click a junction to let the game choose its control.",
			"Click a junction to add traffic lights.", "Click a junction to make it an all-way stop.",
			"Click a junction to put stop signs on the smaller road.",
			"Click a junction to take its signs and lights away."][mode]
		if _hover != -1 and sim.traffic.junctions.has(_hover):
			var j: Dictionary = sim.traffic.junctions[_hover]
			var now: String = RULE_NAME[j.control]
			if j.control == TrafficSim.Rule.PRIORITY and j.sign == "yield":
				now = "yield signs"
			text += "\nThis junction has %s%s." % [now, " (your choice)" if sim.traffic.overrides.has(_hover) else ""]
	if text != _hint:
		_hint = text
		hint_changed.emit(text)
