class_name DoorView
extends Node3D
## Garage doors going up and down for the cars driving in and out of them
## (DoorEvents), near the camera, on the desktop at High and up (doors_m
## and doors in GraphicsQuality.BUDGETS; off below that, and the browser
## never makes one). Nathan, 2026-10-29: "it would also help if we had
## working doors and garage doors. they could open to black, allowing
## things to come in and out."
##
## The shut door stays in the building's drawing. A door that is open or
## moving is drawn over it, a few centimetres out from it: a dark card for
## the opening, growing up from the floor, with a room painted on it in
## depth (a concrete floor, side walls and a ceiling, dimmer further in:
## interior mapping, the trick a window's rooms use too), and above it the
## part of the door still down, its panels sliding up with it and its
## bottom rail at the card's top edge. Two draw calls however many doors
## move, and only the cars near the camera are looked at (DoorEvents),
## once a tick.
##
## A door takes DoorEvents.OPEN_TICKS to go all the way (10 s at the
## game's normal speed; faster when the game is sped up, frozen when it is
## paused, as the cars are). For a car leaving, how far up its door is is
## the simulation's own (door_t: it goes up while the driver walks out);
## otherwise a door moves at that pace toward up or down, and one first
## seen already moving starts from shut.

## Metres out from the shut door the opening and the moving door are drawn.
const CARD_OUT := 0.07
const PANEL_OUT := 0.09
## The garage's room behind the opening, as painted: metres deep, and how
## much wider and taller than the door it is.
const ROOM_DEPTH := 6.4
const ROOM_WIDER := 1.2
const ROOM_TALLER := 0.45

var traffic: TrafficSim
var events: DoorEvents
## Returns the transform a lot's building is drawn with (BuildingView), or
## null when it isn't drawn: lot key -> Transform3D.
var lot_xf := Callable()

## Doors open or moving: key ("ref#door") -> [how far up (0 to 1), door
## (DoorLog), world transform of the lot's building].
var _shown := {}
var _time := -1.0
var _eye := Vector3.INF
var _open := {}
var _cards: MultiMeshInstance3D
var _panels: MultiMeshInstance3D
## Doors drawn last frame (for tests and the perf readout).
var drawn := 0

const CARD_SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
global uniform float night;
uniform float depth = 6.4;
uniform float wider = 1.2;
uniform float taller = 0.45;
// INSTANCE_CUSTOM: door width, how high it is open, door height (m).
varying vec3 v_pos;
varying vec3 v_cam;
varying vec3 v_size;
void vertex() {
	v_size = INSTANCE_CUSTOM.xyz;
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	// The card's own metres: x across, y up from the floor, z out of the wall.
	v_pos = vec3(VERTEX.x * v_size.x, (VERTEX.y + 0.5) * v_size.y, 0.0);
	v_cam = vec3(cam.x * v_size.x, (cam.y + 0.5) * v_size.y, cam.z);
}
void fragment() {
	vec3 d = normalize(v_pos - v_cam);
	d.z = min(d.z, -0.001);
	float hw = v_size.x * 0.5 + wider * 0.5;
	float top = v_size.z + taller;
	// The first of the room's back wall, side walls, floor and ceiling the
	// eye's ray meets behind the opening.
	float tb = (-depth - v_pos.z) / d.z;
	float ts = abs(d.x) > 1e-4 ? (sign(d.x) * hw - v_pos.x) / d.x : 1e6;
	float tv = abs(d.y) > 1e-4 ? ((d.y > 0.0 ? top : 0.0) - v_pos.y) / d.y : 1e6;
	float t = min(tb, min(ts, tv));
	vec3 hit = v_pos + d * t;
	float in_m = -hit.z;
	vec3 col = vec3(0.42, 0.42, 0.40);  // back wall: painted block
	if (t == ts) col = vec3(0.48, 0.47, 0.44);  // drywall
	if (t == tv) col = d.y > 0.0 ? vec3(0.36, 0.36, 0.35) : vec3(0.30, 0.29, 0.27);  // ceiling, concrete floor
	// Daylight comes in at the door and dies off inside; dark corners.
	float lit = mix(1.0, 0.12, smoothstep(0.0, depth, in_m));
	float edge = min(min(hw - abs(hit.x), hit.y), top - hit.y);
	lit *= mix(0.55, 1.0, smoothstep(0.0, 0.6, edge));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = col * lit * (0.2 * (1.0 - night * 0.95) + 0.004);
}
"""

const PANEL_SHADER := """
shader_type spatial;
render_mode cull_back;
// INSTANCE_CUSTOM: door width, door height, how high it is open (m).
varying vec3 v_size;
void vertex() {
	v_size = INSTANCE_CUSTOM.xyz;
}
void fragment() {
	// Metres up the door from its bottom rail: what shows is its lowest
	// part (the rest has rolled up into the garage), so the sections'
	// joints ride up with it.
	float y = (1.0 - UV.y) * max(v_size.y - v_size.z, 0.0);
	// Sections 21 in high with a shadowed joint, as the house's own doors
	// are drawn (HouseMaterials SIDING, alpha 0), faded before they shimmer.
	float t = y / 0.53;
	float f = fract(t);
	float s = mix(0.92, 1.03, smoothstep(0.0, 0.85, f));
	s *= 1.0 - 0.16 * (1.0 - smoothstep(0.0, 0.07, f));
	s = mix(s, 0.94, smoothstep(0.12, 0.45, fwidth(t)));
	// The bottom rail's rubber seal.
	s *= mix(0.35, 1.0, smoothstep(0.03, 0.06, y));
	ALBEDO = COLOR.rgb * s;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
}
"""


func setup(t: TrafficSim, sim: CitySim, out_front: Callable, xf_of: Callable) -> void:
	traffic = t
	events = DoorEvents.new(t, sim)
	events.out_front = out_front
	lot_xf = xf_of


func _ready() -> void:
	_cards = _batch(CARD_SHADER)
	_panels = _batch(PANEL_SHADER)
	var m: ShaderMaterial = _cards.material_override
	m.set_shader_parameter("depth", ROOM_DEPTH)
	m.set_shader_parameter("wider", ROOM_WIDER)
	m.set_shader_parameter("taller", ROOM_TALLER)


func _batch(code: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(_delta: float) -> void:
	var t := Perf.now()
	var cam := get_viewport().get_camera_3d()
	step(cam.global_position if cam else Vector3.ZERO)
	Perf.add("frame.doors", t)


## Moves the doors on to the simulation's clock and draws them, for a
## camera at `eye`.
func step(eye: Vector3) -> void:
	var reach := float(GraphicsQuality.knob("doors_m", 0.0))
	var cap := int(GraphicsQuality.knob("doors", 0))
	if traffic == null or reach <= 0.0 or cap <= 0:
		_shown.clear()
		_time = -1.0
		_draw([])
		return
	var now: float = traffic.time
	var dt := now - _time
	if _time < 0.0 or dt < 0.0 or dt > 30.0:
		_shown.clear()  # a fresh start, a loaded town or a jump in time
		dt = 0.0
	if now != _time or eye.distance_squared_to(_eye) > 64.0:
		_open = events.open_near(eye, reach)
		_eye = eye
	_time = now
	var go := dt / (DoorEvents.OPEN_TICKS * TrafficSim.DT)
	for key in _open:
		var e: Array = _open[key]
		if not _shown.has(key):
			var xf = lot_xf.call(str(e[0]).substr(4)) if lot_xf.is_valid() else null
			if xf == null:
				continue  # its building isn't drawn (yet)
			_shown[key] = [0.0, e[2], xf]
		var sh: Array = _shown[key]
		sh[0] = float(e[3]) if float(e[3]) >= 0.0 else minf(float(sh[0]) + go, 1.0)
	var r2 := reach * reach
	var list := []
	for key in _shown.keys():
		var sh: Array = _shown[key]
		if not _open.has(key):
			sh[0] = maxf(float(sh[0]) - go, 0.0)
		var at: Vector3 = (sh[2] as Transform3D) * (sh[1][1] as Vector3)
		var d2 := Vector2(at.x - eye.x, at.z - eye.z).length_squared()
		if float(sh[0]) <= 0.0 or d2 > r2:
			_shown.erase(key)  # shut, or out of reach: shut as the building draws it
			continue
		list.append([d2, sh])
	if list.size() > cap:
		list.sort_custom(func(a, b): return a[0] < b[0])
		list.resize(cap)
	_draw(list)


func _draw(list: Array) -> void:
	drawn = list.size()
	var cards: MultiMesh = _cards.multimesh
	var panels: MultiMesh = _panels.multimesh
	if list.size() > cards.instance_count:
		for mm in [cards, panels]:
			mm.instance_count = list.size() + 8
	var n := 0
	var p := 0
	for item in list:
		var sh: Array = item[1]
		var up: float = sh[0]
		var d: Array = sh[1]
		var xf: Transform3D = sh[2]
		var c: Vector3 = d[1]
		var f: Vector3 = d[2]
		var w: float = d[3]
		var h: float = d[4]
		var right := Vector3.UP.cross(f).normalized()
		var bottom := c - Vector3.UP * h * 0.5
		var open_h := up * h
		var paint: Color = (d[5] as Color).srgb_to_linear()
		if open_h > 0.005:
			var b := xf.basis * Basis(right * w, Vector3.UP * open_h, f)
			cards.set_instance_transform(n, Transform3D(b, xf * (bottom + Vector3.UP * open_h * 0.5 + f * CARD_OUT)))
			cards.set_instance_custom_data(n, Color(w, open_h, h, 0.0))
			cards.set_instance_color(n, Color.WHITE)
			n += 1
		if h - open_h > 0.005:
			var b := xf.basis * Basis(right * w, Vector3.UP * (h - open_h), f)
			panels.set_instance_transform(p, Transform3D(b, xf * (bottom + Vector3.UP * (open_h + (h - open_h) * 0.5) + f * PANEL_OUT)))
			panels.set_instance_custom_data(p, Color(w, h, open_h, 0.0))
			panels.set_instance_color(p, paint)
			p += 1
	cards.visible_instance_count = n
	panels.visible_instance_count = p
