extends Node3D
## Every building as instanced shapes grown from its facts, a few draw calls
## for each 256 m square of town: a box for its walls (and a flat roof), a
## gable or hip roof, and, nearer than MID_B, the lighter middle version's
## pieces (windows, doors, storefronts, overhead doors) where the facts'
## rules put them. Drives, walks and parking lie in front. One shared
## material each; each building's colours ride on its instances.
##
## When a building's close-up version is ready (NearRing), its instances
## here are flagged and fade out by distance as the close-up fades in.

const Facts := preload("res://tools/scale/new_drawing/facts.gd")
const Mats := preload("res://tools/scale/new_drawing/mats.gd")
const Meshes := preload("res://tools/scale/new_drawing/meshes.gd")

const CHUNK := 256.0
const HALF_DIAG := 182.0
## The foundation shown below the floor (the box runs down into the ground).
const FOUND := 1.25
const OH := 0.3

var facts := {}  # key -> facts (the view's)
var ready_keys := {}  # key -> true: its close-up version is showing
var _chunks := {}  # Vector2i -> {keys: {}, mmi: {name: MultiMeshInstance3D}}
var _where := {}  # key -> [chunk, {name: [first, count]}]
var _dirty := {}  # Vector2i -> true

const LAYERS := {
	"box": ["shape_box", true, false, 0.0],
	"gable": ["shape_gable", true, false, 0.0],
	"hip": ["shape_hip", true, false, 0.0],
	"x_win": ["extra", false, true, Mats.MID_B + HALF_DIAG],
	"x_door": ["extra", false, true, Mats.MID_B + HALF_DIAG],
	"x_store": ["extra", false, true, Mats.MID_B + HALF_DIAG],
	"x_bay": ["extra", false, true, Mats.MID_B + HALF_DIAG],
	"pave": ["pave", false, false, 1600.0],
}


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func add(key: String) -> void:
	var c := chunk_of(facts[key].centre)
	if not _chunks.has(c):
		_chunks[c] = {"keys": {}, "mmi": {}}
	_chunks[c].keys[key] = true
	_dirty[c] = true


func remove(key: String) -> void:
	if not _where.has(key):
		for c in _chunks:
			if _chunks[c].keys.erase(key):
				_dirty[c] = true
		return
	var c: Vector2i = _where[key][0]
	_chunks[c].keys.erase(key)
	_where.erase(key)
	ready_keys.erase(key)
	_dirty[c] = true


func has_dirty() -> bool:
	return not _dirty.is_empty()


## Rebuilds dirty squares until `budget_us` is spent (at least one).
func rebuild_some(budget_us: int) -> void:
	var t := Time.get_ticks_usec()
	for c in _dirty.keys():
		_dirty.erase(c)
		_rebuild(c)
		if Time.get_ticks_usec() - t > budget_us:
			break


func rebuild_all() -> void:
	for c in _dirty.keys():
		_rebuild(c)
	_dirty.clear()


## The close-up version of `key` is showing (or not): flag its instances.
func set_ready(key: String, on: bool) -> void:
	if on:
		ready_keys[key] = true
	else:
		ready_keys.erase(key)
	if not _where.has(key):
		return
	var c: Vector2i = _where[key][0]
	var mmis: Dictionary = _chunks[c].mmi
	var spans: Dictionary = _where[key][1]
	for name in spans:
		if not mmis.has(name):
			continue
		var mm: MultiMesh = mmis[name].multimesh
		var s: Array = spans[name]
		for i in range(s[0], s[0] + s[1]):
			var cd := mm.get_instance_custom_data(i)
			cd.a = 1.0 if on else 0.0
			mm.set_instance_custom_data(i, cd)


func _rebuild(c: Vector2i) -> void:
	var ch: Dictionary = _chunks.get(c, {})
	if ch.is_empty():
		return
	var centre := Vector3((c.x + 0.5) * CHUNK, 0.0, (c.y + 0.5) * CHUNK)
	var bufs := {}
	var counts := {}
	for name in LAYERS:
		bufs[name] = PackedFloat32Array()
		counts[name] = 0
	for key in ch.keys:
		if not facts.has(key):
			continue
		var f: Dictionary = facts[key]
		var on := 1.0 if ready_keys.has(key) else 0.0
		var spans := {}
		var o: Vector3 = f.centre - centre
		var bs: Basis = f.basis
		# Walls (and a flat roof): the box, down into the ground for the foundation.
		var wall: Color = f.wall
		wall.a = (float(f.mat) + 0.5) / 8.0
		var roof: Color = f.roof_col
		roof.a = on
		spans.box = [counts.box, 1]
		_push(bufs.box, bs * Basis.from_scale(Vector3(f.w, f.h + FOUND, f.d)), o + Vector3(0, -FOUND, 0), roof, wall)
		counts.box += 1
		if int(f.roof) != Facts.Roof.FLAT:
			var long_x: bool = f.ridge_x
			var lx: float = f.w if long_x else f.d
			var lz: float = f.d if long_x else f.w
			var turn := bs if long_x else bs * Basis(Vector3.UP, PI * 0.5)
			var p: float = f.pitch
			var rise := lz * 0.5 * p + OH * p
			var y := float(f.h) - OH * p
			var name := "gable" if int(f.roof) == Facts.Roof.GABLE else "hip"
			var sx := lx if name == "gable" else lx + 2.0 * OH
			spans[name] = [counts[name], 1]
			_push(bufs[name], turn * Basis.from_scale(Vector3(sx, rise, lz + 2.0 * OH)), o + Vector3(0, y, 0), roof, wall)
			counts[name] += 1
		# The middle version's openings.
		var firsts := {}
		for w in Facts.walls(f):
			var wf: Transform3D = Facts.wall_frame(w)
			for op in w.ops:
				var kind: String = op[4]
				var name: String = "x_" + ("win" if kind == "curtain" else kind)
				if not firsts.has(name):
					firsts[name] = counts[name]
				var u: float = w.u0 + op[0] * Facts.CELL
				var v: float = op[1] * Facts.CELL
				var at: Vector3 = wf.origin + wf.basis.x * u + Vector3.UP * v
				var xb := bs * Basis(wf.basis.x * (op[2] * Facts.CELL), Vector3.UP * (op[3] * Facts.CELL), wf.basis.z)
				var col := Color("#ecebe6")
				match kind:
					"door": col = f.door
					"store", "curtain": col = Color("#3a332c")
					"bay": col = Color("#c9c6bd")
				col.a = on
				_push(bufs[name], xb, o + bs * at, col)
				counts[name] += 1
		for name in firsts:
			spans[name] = [firsts[name], counts[name] - firsts[name]]
		# Paving, on the ground.
		for pv in _paving(f):
			var pc: Vector3 = f.centre + bs * pv[0]
			pc.y = Terrain.ground_y(pc.x, pc.z) + 0.06
			_push(bufs.pave, bs * Basis.from_scale(Vector3(pv[1].x, 1.0, pv[1].y)), pc - centre, pv[2])
			counts.pave += 1
		_where[key] = [c, spans]
	for name in LAYERS:
		var mmi: MultiMeshInstance3D = ch.mmi.get(name)
		if counts[name] == 0:
			if mmi != null:
				mmi.multimesh.instance_count = 0
			continue
		if mmi == null:
			mmi = _make(name, centre)
			ch.mmi[name] = mmi
		var mm := mmi.multimesh
		mm.instance_count = counts[name]
		mm.buffer = bufs[name]
	if ch.keys.is_empty():
		for name in ch.mmi:
			ch.mmi[name].queue_free()
		_chunks.erase(c)


func _make(name: String, centre: Vector3) -> MultiMeshInstance3D:
	var spec: Array = LAYERS[name]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = spec[1]
	mm.use_custom_data = true
	match name:
		"box": mm.mesh = Meshes.shape_box()
		"gable": mm.mesh = Meshes.shape_gable()
		"hip": mm.mesh = Meshes.shape_hip()
		"pave": mm.mesh = Meshes.pave()
		_: mm.mesh = Meshes.extra(name.substr(2))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.get_mat(spec[0])
	mmi.position = centre
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if name in ["box", "gable", "hip"] \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if spec[3] > 0.0:
		mmi.visibility_range_end = spec[3]
	add_child(mmi)
	return mmi


## One instance: transform, then (when the layer has them) colour, then custom.
static func _push(buf: PackedFloat32Array, b: Basis, o: Vector3, custom: Color, colour = null) -> void:
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
	if colour != null:
		buf.append_array([colour.r, colour.g, colour.b, colour.a])
	buf.append_array([custom.r, custom.g, custom.b, custom.a])


## Drives, walks and lots in the building's frame: [middle, size (x, z), colour].
static func _paving(f: Dictionary) -> Array:
	var concrete := Color(0.74, 0.73, 0.69)
	var asphalt := Color(0.2, 0.2, 0.21)
	var curb: float = f.front_z - f.setback - f.to_curb
	var out := []
	match String(f.type):
		"house", "row_home":
			# The drive from the curb back alongside the house; a walk to the door.
			var z1: float = f.front_z + 6.0
			out.append([Vector3(f.drive_x, 0, (curb + z1) * 0.5), Vector2(3.0, z1 - curb), concrete])
			var walk_x := 0.0
			for w in Facts.walls(f):
				if w.i == 0:
					for op in w.ops:
						if op[4] == "door":
							walk_x = float(w.p0.x) - (w.u0 + (op[0] + 1) * Facts.CELL)
			out.append([Vector3(walk_x, 0, (curb + f.front_z) * 0.5), Vector2(1.1, f.front_z - curb), concrete])
		"factory":
			out.append([Vector3(0, 0, (curb + f.front_z) * 0.5), Vector2(f.w + 6.0, f.front_z - curb), asphalt])
		_:
			if f.setback > 5.0:
				out.append([Vector3(0, 0, (curb + f.front_z) * 0.5), Vector2(f.w, f.front_z - curb), asphalt])
			else:
				out.append([Vector3(0, 0, (curb + f.front_z) * 0.5), Vector2(f.w, f.front_z - curb), concrete])
	return out
