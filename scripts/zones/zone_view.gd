class_name ZoneView
extends Node3D
## Shows lots on the ground while a zone tool is open: every lot's outline,
## empty zoned lots tinted. Otherwise the ground stays plain, as a platted
## but unbuilt lot is in real life (and CS2 shows zone colour only in the
## zoning tool). Unzoned land shows no lot lines at all: lots are surveyed
## only where streets are zoned. The street side under the zone tool shows
## as a band.

var sim: CitySim
var show_all := false:
	set(v):
		show_all = v
		_dirty = true

## Street sides to highlight: [[seg, side], ...] (or [seg, side, from, to]
## for a stretch of one) and the zone colour.
var preview: Array = []:
	set(v):
		preview = v
		_dirty = true
var preview_zone := 0
## Each preview part's own zone (smart paint), or [] for preview_zone.
var preview_zones: Array = []
## A held plan (smart paint waiting for Paint it): the band glows and
## pulses, ready but not done.
var pulse := false:
	set(v):
		pulse = v
		_preview_mat.albedo_color = Color.WHITE

## Lot outlines go in square blocks, so a change redraws (and drapes on the
## ground) only the blocks it touched; the street-side band is its own mesh.
const BLOCK := 128.0

var _mesh := MeshInstance3D.new()
var _lot_mat := StandardMaterial3D.new()
var _preview_mat := StandardMaterial3D.new()
var _dirty := true
var _blocks := {}  # Vector2i -> MeshInstance3D
var _block_sig := {}  # Vector2i -> hash of what the block shows


func setup(s: CitySim) -> void:
	sim = s
	for sig in [sim.lots_changed, sim.zones_changed, sim.buildings_changed]:
		sig.connect(func(): _dirty = true)


func _ready() -> void:
	for mat in [_lot_mat, _preview_mat]:
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _preview_mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(_delta: float) -> void:
	if pulse:
		# About one breath a second, brighter and more solid at the peak.
		var t := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0055)
		_preview_mat.albedo_color = Color(1.0 + 0.6 * t, 1.0 + 0.6 * t, 1.0 + 0.6 * t, 1.2 + 0.8 * t)
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	# What each block shows: its lots' outlines, zones and whether built.
	var shows := {}  # Vector2i -> [[key, lot, zone, built], ...]
	for key in (sim.lots if show_all else {}):
		var lot: Dictionary = sim.lots[key]
		var b := Vector2i(floori(lot.pos.x / BLOCK), floori(lot.pos.z / BLOCK))
		if not shows.has(b):
			shows[b] = []
		shows[b].append([key, lot, sim.zones.zone_at(lot.zone_pt), sim.buildings.has(key)])
	for b in _blocks.keys():
		if not shows.has(b):
			_blocks[b].queue_free()
			_blocks.erase(b)
			_block_sig.erase(b)
	for b in shows:
		var sig := hash(shows[b].map(func(e): return [e[0], e[1].corners, e[2], e[3]]))
		if _block_sig.get(b) == sig:
			continue
		_block_sig[b] = sig
		var bst := SurfaceTool.new()
		bst.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in shows[b]:
			var c: Color = ZoneMap.COLORS[e[2]]
			var fill := 0.0 if e[2] == ZoneMap.Zone.NONE else (0.18 if e[3] else 0.42)
			var edge := 0.75
			_lot(bst, e[1].corners, Color(c, fill), Color(c, maxf(edge, fill + 0.2)))
		if not _blocks.has(b):
			var mi := MeshInstance3D.new()
			mi.material_override = _lot_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_blocks[b] = mi
		_blocks[b].mesh = Terrain.drape(bst.commit(), true)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var band: Color = ZoneMap.COLORS[preview_zone] if preview_zone != ZoneMap.Zone.NONE else Color(1, 0.35, 0.3)
	for pi in preview.size():
		var part: Array = preview[pi]
		if pi < preview_zones.size():
			var pz: int = preview_zones[pi]
			band = ZoneMap.COLORS[pz] if pz != ZoneMap.Zone.NONE else Color(1, 0.35, 0.3)
		var s := sim.planner.side_survey(sim.network, part[0], part[1])
		if s.is_empty():
			continue
		var rays: Array = s.rays
		for i in range(rays.size() - 1):
			var a: Array = rays[i]
			var b: Array = rays[i + 1]
			if a[3] < 0.0 or b[3] < 0.0:
				continue
			if part.size() == 4 and (a[0] < part[2] - 0.01 or b[0] > part[3] + 0.01):
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
