class_name ZoneView
extends Node3D
## Shows lots on the ground. Empty zoned lots are always tinted; while a zone
## tool is open every lot shows its outline. Unzoned land shows no lot lines
## at all: lots are surveyed only where streets are zoned. The street side
## under the zone tool shows as a band.

var sim: CitySim
var show_all := false:
	set(v):
		show_all = v
		_dirty = true

## Street sides to highlight: [[seg, side], ...] and the zone colour.
var preview: Array = []:
	set(v):
		preview = v
		_dirty = true
var preview_zone := 0

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
	var band: Color = ZoneMap.COLORS[preview_zone] if preview_zone != ZoneMap.Zone.NONE else Color(1, 0.35, 0.3)
	for part in preview:
		var s := sim.planner.side_survey(sim.network, part[0], part[1])
		if s.is_empty():
			continue
		var rays: Array = s.rays
		for i in range(rays.size() - 1):
			var a: Array = rays[i]
			var b: Array = rays[i + 1]
			if a[3] < 0.0 or b[3] < 0.0:
				continue
			var da := minf(a[3], 8.0)
			var db := minf(b[3], 8.0)
			_quad(st, a[1], b[1], b[1] + b[2] * db, a[1] + a[2] * da, 0.08, Color(band, 0.45))
			any = true
	_mesh.mesh = Terrain.drape(st.commit(), true) if any else null


## A lot: a filled inner area and a thin border just inside its edge.
## Lots can have any number of corners.
func _lot(st: SurfaceTool, c: PackedVector2Array, fill: Color, edge: Color) -> void:
	var outer := _inset(c, 0.6)
	var inner := _inset(c, 1.4)
	if outer.size() != c.size() or inner.size() != c.size():
		return
	var y := 0.06
	for i in c.size():
		var j := (i + 1) % c.size()
		_quad(st, outer[i], outer[j], inner[j], inner[i], y, edge)
	if fill.a <= 0.0:
		return
	var tris := Geometry2D.triangulate_polygon(inner)
	st.set_color(fill)
	for k in tris:
		st.add_vertex(Vector3(inner[k].x, y, inner[k].y))


## Each corner moved `d` inward along its mitred bisector (outlines are
## counter-clockwise in x/z, so inward is to the left of each edge).
static func _inset(c: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := c.size()
	var area := 0.0
	for i in n:
		var j := (i + 1) % n
		area += c[i].x * c[j].y - c[j].x * c[i].y
	var sgn := 1.0 if area > 0.0 else -1.0
	var out := PackedVector2Array()
	for i in n:
		var prev := c[(i + n - 1) % n]
		var next := c[(i + 1) % n]
		var e0 := (c[i] - prev).normalized()
		var e1 := (next - c[i]).normalized()
		var n0 := Vector2(-e0.y, e0.x) * sgn
		var n1 := Vector2(-e1.y, e1.x) * sgn
		var bis := (n0 + n1)
		if bis.length() < 0.01:
			bis = n0
		bis = bis.normalized()
		var k := clampf(1.0 / maxf(bis.dot(n0), 0.2), 1.0, 3.0)
		out.append(c[i] + bis * d * k)
	return out


static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	if col.a <= 0.0:
		return
	st.set_color(col)
	for p in [a, b, c, a, c, d]:
		st.add_vertex(Vector3(p.x, y, p.y))
