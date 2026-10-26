class_name TrafficTool
extends Node3D
## Traffic info view and junction controls, like the Cities: Skylines 2
## traffic view plus the TM:PE junction tools. While it's open, roads are
## coloured by traffic flow; pick a control and click junctions to set it.

signal mode_changed(mode: int)
signal hint_changed(text: String)

enum Mode { NONE, VIEW, AUTO, SIGNAL, ALL_STOP, STOP, NO_CONTROL, TIMING, SMART }

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
## The light a green wave runs from (Timing: Ctrl-click), or -1.
var _wave_from := -1


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
	_wave_from = -1
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
			and _hover != -1 and mode == Mode.SMART:
		# Sensors on or off at this light.
		sim.apply({"type": "set_actuated", "node": _hover, "on": not sim.traffic.actuated.has(_hover)})
		_hint = ""
		_update_hint()
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed \
			and _hover != -1 and mode == Mode.TIMING:
		# Ctrl-click: a green wave, light by light down a street.
		if mb.ctrl_pressed or mb.meta_pressed:
			if _wave_from != -1 and _wave_from != _hover and sim.traffic.junctions.has(_wave_from):
				var v := 0.0
				for seg in sim.network.segments_at(_hover):
					v = maxf(v, float(RoadStyle.TYPES[sim.network.segments[seg].type].mph) * RoadStyle.MPH)
				sim.apply({"type": "link_wave", "from": _wave_from, "to": _hover, "v": v})
			_wave_from = _hover
			_hint = ""
			_update_hint()
			return
		# Click near a direction: 5 s more green for it; Shift-click: 5 s less.
		var hit = cam.mouse_ground_point()
		var ph := _phase_near(_hover, hit) if hit != null else -1
		if ph != -1:
			var now: Array = sim.traffic.greens_at(_hover)
			sim.apply({"type": "set_green", "node": _hover, "phase": ph,
				"seconds": float(now[ph]) + (-5.0 if mb.shift_pressed else 5.0)})
			_hint = ""
			_update_hint()
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
	elif hit != null and (mode == Mode.TIMING or mode == Mode.SMART):
		node = _junction_near(hit)
		if node != -1 and sim.traffic.junctions[node].control != TrafficSim.Rule.SIGNAL:
			node = -1
	if node != _hover:
		_hover = node
		_update_hint()
	_ring.visible = node != -1
	if node != -1:
		var r := RoadStyle.half_width(sim.network.widest_at(node)) + 3.0
		_ring.position = Terrain.lift(sim.network.nodes[node]) + Vector3(0, 0.4, 0)
		_ring.scale = Vector3(r, 1.0, r)


## The light's phase whose approach is nearest the point, or -1.
func _phase_near(node: int, p: Vector3) -> int:
	var j: Dictionary = sim.traffic.junctions[node]
	var best := -1
	var best_d := INF
	for i in j.phases.size():
		for wi in j.phases[i].ways:
			var q: Vector3 = sim.traffic.stop_line(wi).pos
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if d < best_d:
				best_d = d
				best = i
	return best


## "north-south" or "east-west" for a phase, by its first approach.
func _phase_name(node: int, i: int) -> String:
	var ways: Dictionary = sim.traffic.junctions[node].phases[i].ways
	if ways.is_empty():
		return "phase %d" % (i + 1)
	var d: Vector3 = sim.traffic.stop_line(ways.keys()[0]).dir
	return "north-south" if absf(d.z) > absf(d.x) else "east-west"


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
	if mode == Mode.SMART:
		text = "Click a traffic light to give it sensors: it holds the green while cars keep coming and skips a way with no one waiting. Click again for a fixed cycle."
		if _hover != -1 and sim.traffic.junctions.has(_hover):
			text += "\nThis light is %s." % ("smart (sensors)" if sim.traffic.actuated.has(_hover) else "on a fixed cycle")
	elif mode == Mode.TIMING:
		text = "Click near a direction at a traffic light for 5 s more green; Shift-click for 5 s less. Ctrl-click lights one after another down a street for a green wave."
		if _hover != -1 and sim.traffic.junctions.has(_hover):
			var parts := []
			var g: Array = sim.traffic.greens_at(_hover)
			for i in g.size():
				var mine: bool = sim.traffic.greens.get(_hover, {}).has(i)
				var theirs: bool = not mine and sim.traffic.tuned.get(_hover, {}).has(i)
				parts.append("%s %d s%s" % [_phase_name(_hover, i).capitalize(), roundi(float(g[i])),
					" (yours)" if mine else (" (engineers')" if theirs else "")])
			text += "\nGreen: " + ", ".join(parts) + "."
			if sim.traffic.retimed.has(_hover) and not sim.traffic.greens.has(_hover):
				var ago := (sim.tick_count - int(sim.traffic.retimed[_hover])) / CitySim.TICKS_PER_HOUR
				text += " The traffic engineers retimed it %s by the counts." % (
					"this hour" if ago < 1 else ("an hour ago" if ago == 1 else "%d hours ago" % ago))
		if _wave_from != -1:
			text += "\nGreen wave: Ctrl-click the next light down the street (it will turn green as cars from the last one arrive)."
	elif RULE_FOR.has(mode):
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
