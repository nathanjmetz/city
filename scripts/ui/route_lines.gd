class_name RouteLines
extends MeshInstance3D
## Show routes, like Cities: Skylines' route view: select a road, a building
## or a vehicle and the trips using it are drawn on the streets they take,
## bright from here to where they're going and faint back to where they set
## off. Cars mint, trucks cream, buses blue. Lines only, no labels.

## Most trips drawn, so a busy road stays readable and the planning cheap.
const MAX_TRIPS := 40
const REFRESH := 1.5
const LIFT := 0.8  # metres over the road, clear of its paint
const CAR := Color(Brand.BRAND_MINT, 0.9)
const TRUCK := Color(Brand.BRAND_CREAM, 0.9)
const BUS := Color("#7fb8e6e6")
const CAME_ALPHA := 0.35

## The ref prefix trips carry for each kind of selection (from_ref, to_ref).
const REF_OF := {
	"lot": "lot:", "service": "svc:", "water": "svc:", "hub": "hub:", "big": "big:", "warehouse": "wh:",
	"park": "park:", "power": "power:", "farm": "farm:", "industry": "site:", "post_office": "mail:",
	"campus": "campus:", "bank": "bank:", "telecom": "telecom:", "rail": "rail:",
}

var sim: CitySim
var _sel := {}
var _wait := 0.0
var _came := {}  # vehicle id -> [trip leg it was planned on, came runs], so each is planned once
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func show_for(sel: Dictionary) -> void:
	_sel = sel
	_wait = 0.0
	_came.clear()
	_rebuild()


func _process(delta: float) -> void:
	if _sel.is_empty():
		return
	_wait += delta
	if _wait >= REFRESH:
		_wait = 0.0
		_rebuild()


## The trips a selection shows: vehicles on the move on a selected road or
## going through it, coming from or going to a selected place, or the one
## selected vehicle.
static func trips(sim: CitySim, sel: Dictionary) -> Array:
	var out := []
	var t := sim.traffic
	var type: String = sel.get("type", "")
	if type == "vehicle":
		var f := t.find_vehicle(int(sel.id))
		if not f.is_empty() and f.state in ["driving", "flowing"]:
			out.append(f.car)
		return out
	if type == "road":
		var seg := int(sel.id)
		var later := []
		for list in [t.cars, t.flowing]:
			for car in list:
				var ahead: Array = t.trip_runs(car, true).ahead
				if ahead.is_empty():
					continue
				if int(ahead[0][0]) / 2 == seg:
					out.append(car)  # on it now
				else:
					for r in ahead:
						if int(r[0]) / 2 == seg:
							later.append(car)  # headed down it
							break
				if out.size() >= MAX_TRIPS:
					return out
		out.append_array(later.slice(0, MAX_TRIPS - out.size()))
		return out
	if not REF_OF.has(type):
		return out
	var want: String = REF_OF[type] + str(sel.id)
	for list in [t.cars, t.flowing]:
		for car in list:
			if str(car.get("to_ref", "")).get_slice("@", 0) == want \
					or str(car.get("from_ref", "")).get_slice("@", 0) == want:
				out.append(car)
				if out.size() >= MAX_TRIPS:
					return out
	return out


static func colour(car: Dictionary) -> Color:
	var kind := TrafficSim.vehicle_kind(car)
	if kind.contains("bus") or str(car.get("purpose", "")) in TrafficSim.BUS_PURPOSES:
		return BUS
	if VehicleTypes.spec(kind).len > 6.5:
		return TRUCK
	return CAR


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _sel.is_empty() or sim == null:
		return
	var list := trips(sim, _sel)
	if list.is_empty():
		return
	var half := 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at := Inspect.place(sim, _sel)
	if cam != null and not at.is_empty():
		# About 3 px wide on screen where the selection is.
		var dist := cam.global_position.distance_to(Terrain.lift(at[0]))
		var px := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) * dist / maxf(get_viewport().get_visible_rect().size.y, 1.0)
		half = clampf(px * 1.6, 0.6, 30.0)
	var keep := {}
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for car in list:
		var c := colour(car)
		var runs := sim.traffic.trip_runs(car, true)
		var came: Array = []
		var key := [car.get("trip", 0), car.get("from_ref", "")]
		if car.has("flow_in"):
			came = sim.traffic.trip_runs(car).came
		elif _came.has(car.id) and _came[car.id][0] == key:
			came = _came[car.id][1]
		else:
			came = sim.traffic.trip_runs(car).came
		keep[car.id] = [key, came]
		_ribbon(came, Color(c, c.a * CAME_ALPHA), half * 0.7)
		_ribbon(runs.ahead, c, half)
	_mesh.surface_end()
	_came = keep


func _ribbon(runs: Array, c: Color, half: float) -> void:
	var pts := PackedVector3Array()
	for r in runs:
		var line := sim.traffic.way_line(int(r[0]), float(r[1]), float(r[2]))
		for p in line:
			if pts.is_empty() or pts[-1].distance_to(p) > 0.3:
				pts.append(p)
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		var a := Terrain.lift(pts[i]) + Vector3.UP * LIFT
		var b := Terrain.lift(pts[i + 1]) + Vector3.UP * LIFT
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if d.length() < 0.01:
			continue
		var s := Vector3(-d.z, 0.0, d.x).normalized() * half
		for v in [a - s, a + s, b + s, a - s, b + s, b - s]:
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(v)
