class_name ZoneView
extends Node3D
## Shows lots on the ground. Empty zoned lots are always tinted; while a zone
## tool is open every lot shows its outline, like the zoning grid in
## Cities: Skylines.

var sim: CitySim
var show_all := false:
	set(v):
		show_all = v
		_dirty = true

var _mesh := MeshInstance3D.new()
var _dirty := true


func setup(s: CitySim) -> void:
	sim = s
	for sig in [sim.lots_changed, sim.zones_changed, sim.buildings_changed]:
		sig.connect(func(): _dirty = true)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var zone := sim.zones.zone_at(lot.zone_pt)
		var built := sim.buildings.has(key)
		if not show_all and (zone == ZoneMap.Zone.NONE or built):
			continue
		var c: Color = ZoneMap.COLORS[zone]
		var fill := 0.0 if zone == ZoneMap.Zone.NONE else (0.18 if built else 0.42)
		var edge := 0.75 if show_all else 0.0
		_lot(st, lot.corners, Color(c, fill), Color(c, maxf(edge, fill + 0.2)))
		any = true
	_mesh.mesh = Terrain.drape(st.commit(), true) if any else null


## A lot: a filled inner area and a thin border just inside its edge.
func _lot(st: SurfaceTool, c: PackedVector2Array, fill: Color, edge: Color) -> void:
	var mid := (c[0] + c[1] + c[2] + c[3]) * 0.25
	var outer := []
	var inner := []
	for p in c:
		var inward := (mid - p).normalized()
		outer.append(p + inward * 0.9)
		inner.append(p + inward * 1.9)
	var y := 0.06
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, outer[i], outer[j], inner[j], inner[i], y, edge)
	_quad(st, inner[0], inner[1], inner[2], inner[3], y, fill)


static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	if col.a <= 0.0:
		return
	st.set_color(col)
	for p in [a, b, c, a, c, d]:
		st.add_vertex(Vector3(p.x, y, p.y))
