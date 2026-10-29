class_name WornPathView
extends MeshInstance3D
## Draws the worn dirt paths (WornPaths) in the grass beside roads with no
## sidewalk: a strip of bare, packed earth that wanders a little, fading at
## its ends and thinner where it's only starting to wear in. Redrawn only
## when the month's wear changes.

var sim: CitySim
var _mat := StandardMaterial3D.new()
## How far the path rides above the drawn land, metres (under a sidewalk's).
const LIFT := 0.035
## Dirt: dry packed Midwestern silt loam, darker where it's worn deepest.
const DIRT := Color("#7a6a52")
const DIRT_DEEP := Color("#5e5040")


func setup(s: CitySim) -> void:
	sim = s
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 1.0
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sim.worn.changed.connect(redraw)
	sim.network.changed.connect(redraw)
	redraw()


func redraw() -> void:
	var m := build(sim)
	mesh = null if m == null else Terrain.drape_local(m, Transform3D.IDENTITY)
	if mesh != null:
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, _mat)


## The flat (undraped) mesh of every worn path, or null for none.
static func build(s: CitySim) -> ArrayMesh:
	var keys: Array = s.worn.wear.keys()
	keys.sort()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for k in keys:
		var lv: float = s.worn.level(int(k))
		var seg: int = int(k) >> 1
		if lv <= 0.0 or not s.network.segments.has(seg):
			continue
		var side := 1.0 if int(k) & 1 == 1 else -1.0
		var pts: PackedVector3Array = s.network.sample_segment(seg, 16)
		_strip(st, pts, side * WornPaths.offset(s.network.segments[seg].type), lv, hash([s.city_seed, k]))
		any = true
	if not any:
		return null
	var out := ArrayMesh.new()
	st.commit(out)
	return out


## A path beside one road: it keeps clear of the junctions at either end,
## wanders a hand's width either way, and is narrower and fainter the less
## it's walked, feathering out to grass at its edges and ends.
static func _strip(st: SurfaceTool, pts: PackedVector3Array, off: float, lv: float, seed: int) -> void:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var length := cum[cum.size() - 1]
	var clear := Balance.WORN_JUNCTION_CLEAR
	if length < clear * 2.0 + 4.0:
		return
	var step := 2.0
	var n := ceili((length - clear * 2.0) / step)
	var w := Balance.WORN_WIDTH * (0.55 + 0.45 * lv)
	var col := DIRT.lerp(DIRT_DEEP, lv)
	var prev := []
	for i in n + 1:
		var d := clear + (length - clear * 2.0) * float(i) / n
		var j := 1
		while j < cum.size() - 1 and cum[j] < d:
			j += 1
		var t := clampf((d - cum[j - 1]) / maxf(cum[j] - cum[j - 1], 0.001), 0.0, 1.0)
		var p := pts[j - 1].lerp(pts[j], t)
		var dir := pts[j] - pts[j - 1]
		dir.y = 0.0
		dir = dir.normalized()
		var nrm := Vector3(-dir.z, 0.0, dir.x)
		var wander := sin(d * 0.11 + float(seed % 97)) * 0.18 + sin(d * 0.37 + float(seed % 13)) * 0.07
		var c := Vector3(p.x, LIFT, p.z) + nrm * (off + wander * signf(off))
		# Fade in over the first few metres and out over the last.
		var fade := clampf(minf(d - clear, length - clear - d) / 6.0, 0.0, 1.0)
		var a := (0.35 + 0.55 * lv) * fade
		var row := [[c - nrm * w * 0.5, 0.0], [c - nrm * w * 0.25, a], [c + nrm * w * 0.25, a], [c + nrm * w * 0.5, 0.0]]
		if not prev.is_empty():
			for q in 3:
				for tri in [[prev[q], row[q], row[q + 1]], [prev[q], row[q + 1], prev[q + 1]]]:
					for v in tri:
						st.set_color(Color(col.r, col.g, col.b, v[1]))
						st.set_normal(Vector3.UP)
						st.add_vertex(v[0])
		prev = row
