class_name ConnectionLines
extends MeshInstance3D
## Where a selected building connects, like Workers & Resources and CS2's
## household view: thin arcs from a home to where its people work, or from a
## workplace to where its staff live. Nothing else: no labels, no numbers.

## Most arcs drawn, so a big employer stays readable and cheap.
const MAX_LINES := 40
const REFRESH := 3.0
const SEGMENTS := 12

var sim: CitySim
var _sel := {}
var _wait := 0.0
var _home := false
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(Brand.BRAND_MINT, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func show_for(sel: Dictionary) -> void:
	_sel = sel
	_wait = 0.0
	_home = sel.get("type", "") == "lot" and sim != null and not sim.people.residents(sel.id).is_empty()
	_rebuild()


func _process(delta: float) -> void:
	# Homes refresh as people come and go; a workplace's scan of the whole
	# town runs once, on the click.
	if _sel.is_empty() or not _home:
		return
	_wait += delta
	if _wait >= REFRESH:
		_wait = 0.0
		_rebuild()


## The other ends: workplaces for a home, homes for a workplace.
static func ends(sim: CitySim, sel: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if sel.get("type", "") != "lot" or not sim.lots.has(sel.id):
		return out
	var key: String = sel.id
	for id in sim.people.residents(key):
		var job: String = sim.people.people[id].job if sim.people.people.has(id) else ""
		if job != "" and out.size() < MAX_LINES:
			var at := _place_of(sim, job)
			if at != Vector3.INF:
				out.append(at)
	if not out.is_empty():
		return out
	# A workplace: one pass over the town, stopping once its staff are found.
	var job_ref := "lot:" + key
	var want := mini(sim.people.staff(job_ref), MAX_LINES)
	if want == 0:
		return out
	for p in sim.people.people.values():
		if p.job == job_ref and sim.lots.has(p.home):
			out.append(sim.lots[p.home].pos)
			if out.size() >= want:
				break
	return out


static func _place_of(sim: CitySim, ref: String) -> Vector3:
	var i := ref.find(":")
	if i < 0:
		return Vector3.INF
	var type := ref.substr(0, i)
	var id: Variant = ref.substr(i + 1)
	if type != "lot" and (id as String).is_valid_int():
		id = int(id)
	var at := Inspect.place(sim, {"type": type, "id": id})
	return at[0] if not at.is_empty() else Vector3.INF


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _sel.is_empty() or sim == null:
		return
	var others := ends(sim, _sel)
	if others.is_empty() or not sim.lots.has(_sel.id):
		return
	var from: Vector3 = sim.lots[_sel.id].pos
	from.y = Terrain.ground_y(from.x, from.z)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for to in others:
		to.y = Terrain.ground_y(to.x, to.z)
		# A shallow arc, higher for longer trips.
		var lift := clampf(from.distance_to(to) * 0.15, 8.0, 120.0)
		var prev := from
		for s in range(1, SEGMENTS + 1):
			var t := float(s) / SEGMENTS
			var p := from.lerp(to, t) + Vector3.UP * (sin(t * PI) * lift + 1.0)
			_mesh.surface_add_vertex(prev)
			_mesh.surface_add_vertex(p)
			prev = p
	_mesh.surface_end()
