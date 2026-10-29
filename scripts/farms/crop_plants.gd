class_name CropPlants
extends Node3D
## Corn and soybean plants close to the camera, on the desktop at High and
## above: real rows 30 inches apart (beans in 15 inch rows on farms that
## drill them narrow), corn about 6.5 in apart in the row (34,000 seeds an
## acre), at the height, colour and stage the crop calendar gives for
## today (CropCalendar). Past them the ground's rows carry on (TerrainView's
## shader, CropFields), and the plants thin out toward the edge so there is
## no line where they stop.
##
## Detail by distance: 16 m tiles of plants stream in nearest first around
## where the camera looks, a few a frame; each tile is one MultiMesh of 4 m
## row pieces per crop, full plants near the camera and a lighter plant
## (fewer leaves) farther out. Height, colour, tassels, leaf drop and
## stubble come from the crop table in the shader, so a day passing costs
## nothing here; a tile is only rebuilt when a field in it is planted,
## harvested or tilled under.

const TILE := 16.0
const CELL := 4.0  # one row piece is 4 m: 24 corn plants
const PLANTS := 24
## Full plants within this many metres of the camera, the light plant past it.
const NEAR := 30.0
## How far round the look spot plants are drawn (scaled by the tier's detail).
const RADIUS := 60.0
## Above this camera height (m) plants are gone, faded out from FADE_FROM.
const FADE_FROM := 110.0
const OFF_ABOVE := 160.0
const BUDGET_MS := 2.0
## Corn casts shadows at Cinematic, across the whole patch of plants (a
## shadow only near the camera showed as a darker square); beans never (too
## short to matter for what a shadow pass costs). Measured at Ultra: shadows
## on every plant tripled the triangles drawn (6.6 to 14.9 million).
## (The tier's crop_shadows: see GraphicsQuality.BUDGETS.)

## Tests and tools can turn the plants on without a graphics tier, or off.
static var force := false
static var off := false

var sim: CitySim
## Vector2i -> {"nodes": [MultiMeshInstance3D], "crops": [its crop], "kinds": {slot: kind}, "near": bool}
var _tiles := {}
var _version := -1
var _stale := {}
var _focus := Vector2.INF
var _radius := RADIUS
var _shadows := false
var _farm_boxes := []  # [Rect2, farm id] (view coordinates)
## What each farm's tiles were built from: farm id -> [Rect2, signature].
var _farm_sigs := {}
## Last measured cost: tiles built and ms spent this frame (for the benches).
var built_ms := 0.0
var instances := 0

static var _meshes := {}
static var _mat: ShaderMaterial
static var _steads := {}  # Vector2i (256 m bin, region) -> [Vector2]


func setup(s: CitySim) -> void:
	sim = s


## Every farm's fields at once, from the live farms (tools, a cold start).
## FarmView tells farms one at a time as each finishes (farm_drawn).
func fields_changed() -> void:
	if sim == null:
		return
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var cells: Array = f.cells
		var slots := []
		var frame := {"pos": f.pos, "dir": f.dir}
		var cell_box := Rect2(Vector2(f.pos.x, f.pos.z), Vector2.ZERO)
		for c in cells:
			slots.append(FarmView.slot_of(id, f, c))
			cell_box = FarmFieldJob.expand_box(cell_box, frame, c)
		farm_drawn(id, cell_box, frame, cells, slots, sim.farms.trim.get(id, {}))
	for id in _farm_sigs.keys():
		if not sim.farms.farms.has(id):
			farm_removed(id)


## What a farm's tiles are built from: its place, its cells' slots, and the
## facts behind each row too (a row number can stand for another crop once
## the table's farm rows are freed, and a row borrowed from the county
## follows the year).
static func sig_of(frame: Dictionary, cells: Array, slots: Array, trim: Dictionary) -> int:
	var rows := {}
	for slot: Vector2i in slots:
		rows[slot.x] = true
	var specs := []
	var year := int(CropCalendar.today().y)
	for row in rows:
		specs.append([row, CropCalendar.spec(row, year)])
	return [frame.pos, frame.dir, cells, slots, specs, trim].hash()


## One farm's fields were just drawn (FarmView; `slots` go with `cells`,
## `cell_box` holds the cells in view coordinates): only the tiles under it
## are redrawn, and only if its fields, slots or place changed since the
## last time, where it was and where it is now.
func farm_drawn(id: Variant, cell_box: Rect2, frame: Dictionary, cells: Array, slots: Array, trim: Dictionary) -> void:
	var sig := sig_of(frame, cells, slots, trim)
	if not _farm_sigs.has(id) or _farm_sigs[id][1] != sig:
		_stale_under(cell_box)
		if _farm_sigs.has(id):
			_stale_under(_farm_sigs[id][0])
	_farm_sigs[id] = [cell_box, sig]
	_farm_boxes = _boxes()


## A farm is gone: the tiles under it are redrawn.
func farm_removed(id: Variant) -> void:
	if _farm_sigs.has(id):
		_stale_under(_farm_sigs[id][0])
		_farm_sigs.erase(id)
		_farm_boxes = _boxes()


func _boxes() -> Array:
	var out := []
	for id in _farm_sigs:
		out.append([(_farm_sigs[id][0] as Rect2).grow(4.0), id])
	return out


## Marks the built tiles over a farm's box (and its 30 m farmyard) stale.
func _stale_under(box: Rect2) -> void:
	var b := box.grow(32.0)
	for t in _tiles:
		if Rect2(Vector2(t) * TILE, Vector2(TILE, TILE)).intersects(b):
			_stale[t] = true


static func enabled() -> bool:
	if off:
		return false
	if force:
		return true
	if OS.has_feature("web"):
		return false
	var q := GraphicsQuality.current
	return q != null and q.active and bool(GraphicsQuality.knob("crops", false))


func _process(_delta: float) -> void:
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	built_ms = 0.0
	if not enabled():
		if not _tiles.is_empty():
			_clear()
		if visible:
			_tell_ground(Vector4.ZERO)
		visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var height := eye.y - Terrain.ground_y(eye.x, eye.z)
	visible = height < OFF_ABOVE
	if not visible:
		_tell_ground(Vector4.ZERO)
		if not _tiles.is_empty() and height > OFF_ABOVE * 1.5:
			_clear()
		return
	_radius = float(GraphicsQuality.knob("crop_m", RADIUS))
	var focus := _look_spot(cam, height)
	var mat := material()
	var gone := smoothstep(FADE_FROM, OFF_ABOVE, height)
	mat.set_shader_parameter("fade", Vector4(focus.x, focus.y, _radius, gone))
	_tell_ground(Vector4(focus.x, focus.y, _radius, 1.0 - gone))
	var q := GraphicsQuality.current
	var shadows: bool = q != null and bool(GraphicsQuality.knob("crop_shadows", false))
	# A field planted, harvested or tilled since the tiles were built.
	if CropCalendar.version != _version:
		_version = CropCalendar.version
		for t in _tiles:
			if _changed(_tiles[t]):
				_stale[t] = true
	# Drop tiles well past the edge, then build the nearest missing ones.
	var reach := _radius + TILE
	for t in _tiles.keys():
		if _centre(t).distance_to(focus) > reach + TILE * 1.5:
			_drop(t)
	var want := []
	var lo := Vector2i(floori((focus.x - reach) / TILE), floori((focus.y - reach) / TILE))
	var hi := Vector2i(floori((focus.x + reach) / TILE), floori((focus.y + reach) / TILE))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var t := Vector2i(x, z)
			var d := _centre(t).distance_to(focus)
			if d > reach:
				continue
			var near := Vector2(eye.x, eye.z).distance_to(_centre(t)) < NEAR or height < 25.0 and d < NEAR
			if not _tiles.has(t) or _stale.has(t) or bool(_tiles[t].near) != near:
				want.append([d, t, near])
	want.sort_custom(func(a, b): return a[0] < b[0])
	instances = 0
	for w in want:
		var t: Vector2i = w[1]
		if _tiles.has(t) and not _stale.has(t):
			# Only nearer or farther: the same plants, the other mesh.
			for i in _tiles[t].nodes.size():
				_tiles[t].nodes[i].multimesh.mesh = mesh(_tiles[t].crops[i], w[2])
			_tiles[t].near = w[2]
			continue
		if (Time.get_ticks_usec() - t0) / 1000.0 > BUDGET_MS:
			break
		_build(t, w[2], shadows)
		_stale.erase(t)
	if shadows != _shadows:
		_shadows = shadows
		for t in _tiles:
			for n in _tiles[t].nodes:
				_shade(n, shadows and n.get_meta("crop") != "soybeans")
	for t in _tiles:
		for n in _tiles[t].nodes:
			instances += (n.multimesh as MultiMesh).instance_count
	built_ms = (Time.get_ticks_usec() - t0) / 1000.0
	Perf.count("crop_plants", instances)
	Perf.add("frame.crop_plants", t0)


## Where the plants stand, for the ground and field shaders (see
## CropCalendar.GLSL's plants_near).
static func _tell_ground(v: Vector4) -> void:
	for m in [TerrainView.ground_material(), TerrainView.far_material(), CropFields.material()]:
		m.set_shader_parameter("plants_near", v)


static func _shade(n: GeometryInstance3D, on: bool) -> void:
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _clear() -> void:
	for t in _tiles.keys():
		_drop(t)
	_stale.clear()


func _drop(t: Vector2i) -> void:
	for n in _tiles[t].nodes:
		n.queue_free()
	_tiles.erase(t)
	_stale.erase(t)


func _centre(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE


## Where the camera looks on the ground, no farther ahead than the reach.
func _look_spot(cam: Camera3D, height: float) -> Vector2:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.001:
		return Vector2(from.x, from.z)
	var ahead := _radius * 0.6
	if dir.y < -0.05:
		ahead = minf(maxf(height, 1.0) / -dir.y * flat.length(), ahead)
	return Vector2(from.x, from.z) + flat.normalized() * ahead


## What each field slot in a tile should show now: "corn", "stalks" (the
## stubble after harvest), "soybeans" or "".
static func kind_of(slot: Vector2i) -> String:
	var s := CropCalendar.state_at(slot.x, slot.y)
	if s.is_empty():
		return ""
	match str(s.crop):
		"corn":
			if float(s.height) <= 0.02:
				return ""
			return "stalks" if float(s.harvested) > 0.5 else "corn"
		"soybeans":
			return "soybeans" if float(s.height) > 0.02 and float(s.harvested) < 0.5 else ""
	return ""


func _changed(tile: Dictionary) -> bool:
	for slot in tile.kinds:
		if kind_of(slot) != tile.kinds[slot]:
			return true
	return false


# --- Building a tile --------------------------------------------------------

func _build(t: Vector2i, near: bool, shadows: bool) -> void:
	var t0 := Perf.now()
	if _tiles.has(t):
		for n in _tiles[t].nodes:
			n.queue_free()
	var o := Vector2(t) * TILE
	var n := int(TILE / CELL) + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = Terrain.ground_y(o.x + i * CELL, o.y + j * CELL)
	var bufs := {"corn": PackedFloat32Array(), "soybeans": PackedFloat32Array(), "stalks": PackedFloat32Array()}
	var kinds := {}
	var farms := []
	var box := Rect2(o, Vector2(TILE, TILE))
	for fb in _farm_boxes:
		if (fb[0] as Rect2).intersects(box) and sim.farms.farms.has(fb[1]):
			farms.append(fb[1])
	# The county's fields: world-square 4 m cells, rows north-south or east-west.
	var vo := Terrain.view_origin
	for j in n - 1:
		for i in n - 1:
			var c := o + Vector2(i + 0.5, j + 0.5) * CELL
			if not farms.is_empty() and _in_farm(farms, c):
				continue
			if not _county_crop(c):
				continue
			var fld := CropCalendar.county_field(c + vo)
			var slot := CropCalendar.county_slot(Vector2i(fld.x, fld.y))
			var kind := kind_of(slot)
			kinds[slot] = kind
			if kind == "":
				continue
			var ns := fld.z == 1
			var along := Vector2(0, 1) if ns else Vector2(1, 0)
			var across := Vector2(1, 0) if ns else Vector2(0, 1)
			# Rows sit where the ground paints them: region metres (k + 0.5) x spacing.
			var sp := _spacing(slot)
			var a0 := (c + vo).dot(across) - CELL * 0.5
			var k0 := ceili(a0 / sp - 0.5)
			var k1 := floori((a0 + CELL) / sp - 0.5 - 0.0001)
			for k in range(k0, k1 + 1):
				var off := (k + 0.5) * sp - (c + vo).dot(across)
				_emit(bufs[kind], c + across * off, across, along, slot, k, hs, o, n)
	# The town's farm fields: 4 m cells square to each farm, rows running
	# back from the road, across the field in the headlands.
	for id in farms:
		_farm_rows(bufs, kinds, id, sim.farms.farms[id], box, hs, o, n)
	var nodes := []
	var crops := []
	for kind in bufs:
		var buf: PackedFloat32Array = bufs[kind]
		if buf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh(kind, near)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = material()
		mi.set_meta("crop", kind)
		_shade(mi, shadows and kind != "soybeans")
		add_child(mi)
		nodes.append(mi)
		crops.append(kind)
	_tiles[t] = {"nodes": nodes, "crops": crops, "kinds": kinds, "near": near}
	Perf.add("crop_plants.tile", t0)


static func _spacing(slot: Vector2i) -> float:
	var s := CropCalendar.state_at(slot.x, slot.y)
	return CropCalendar.NARROW_M if float(s.get("spacing", 1.0)) < 0.75 else CropCalendar.ROW_M


## One 4 m piece of row centred at p (view metres).
func _emit(buf: PackedFloat32Array, p: Vector2, across: Vector2, along: Vector2, slot: Vector2i, k: int,
		hs: PackedFloat32Array, o: Vector2, n: int) -> void:
	var g := (p - o) / CELL
	var i := clampi(floori(g.x), 0, n - 2)
	var j := clampi(floori(g.y), 0, n - 2)
	var fx := clampf(g.x - i, 0.0, 1.0)
	var fz := clampf(g.y - j, 0.0, 1.0)
	var h00 := hs[j * n + i]
	var h10 := hs[j * n + i + 1]
	var h01 := hs[(j + 1) * n + i]
	var h11 := hs[(j + 1) * n + i + 1]
	var y := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	# The ground's slope, so the row piece lies on it.
	var dx := (lerpf(h10, h11, fz) - lerpf(h00, h01, fz)) / CELL
	var dz := (lerpf(h01, h11, fx) - lerpf(h00, h10, fx)) / CELL
	var up := Vector3(-dx, 1.0, -dz).normalized()
	var z := Vector3(along.x, 0.0, along.y)
	z = (z - up * z.dot(up)).normalized()
	var x := up.cross(z)
	# The plant's seed from where it stands in the region, so every player
	# sees the same plants in a field (p is in this player's view metres).
	var seed := float(CropCalendar.hash32(k, roundi((p + Terrain.view_origin).dot(along) * 4.0), slot.y) & 255)
	buf.append_array([x.x, up.x, z.x, p.x, x.y, up.y, z.y, y, x.z, up.z, z.z, p.y,
		float(slot.x), float(slot.y), seed, 0.0])


## Whether the county paints crops at a point (view metres), as TerrainView's
## shader does: real cropland, off the woods, water, towns, county roads,
## highways and farmyards.
func _county_crop(c: Vector2) -> bool:
	var r := c + Terrain.view_origin
	var cov := Terrain.cover(r.x, r.y)
	# The ragged edge is dithered in region metres, the same for every player.
	if cov.b < 0.45 + 0.15 * CropCalendar.h01(floori(r.x), floori(r.y), 9) or cov.r > 0.35 or cov.g > 0.03:
		return false
	if Terrain.mow_weight(c.x, c.y) > 0.05 or Terrain.flat_weight(c.x, c.y) > 0.05:
		return false
	if CountyGrid.distance(r.x, r.y) < 9.5 or Highways.distance(r.x, r.y) < 17.0 or CountyRail.clears(r.x, r.y, CountyRail.CROP_CLEAR):
		return false
	if Backdrop.inside(r, 40.0) or _near_farmstead(r, 55.0) or FarmsteadPlan.covers(r):
		return false
	return true


func _in_farm(farms: Array, c: Vector2) -> bool:
	for id in farms:
		var f: Dictionary = sim.farms.farms[id]
		var d := c - Vector2(f.pos.x, f.pos.z)
		var right := Vector2(-f.dir.z, f.dir.x)
		var back := Vector2(-f.dir.x, -f.dir.z)
		var cell := Vector2i(roundi(d.dot(right) / Farms.CELL), roundi(d.dot(back) / Farms.CELL))
		if cell in f.cells or (absf(d.dot(right)) < 30.0 and absf(d.dot(back)) < 30.0):
			return true
	return false


func _farm_rows(bufs: Dictionary, kinds: Dictionary, id: Variant, f: Dictionary, box: Rect2,
		hs: PackedFloat32Array, o: Vector2, n: int) -> void:
	var pos := Vector2(f.pos.x, f.pos.z)
	var right := Vector2(-f.dir.z, f.dir.x)
	var back := Vector2(-f.dir.x, -f.dir.z)
	var owned := {}
	for c in f.cells:
		owned[c] = true
	var trimmed: Dictionary = sim.farms.trim.get(id, {})
	# The tile's corners in the farm's frame.
	var amin := INF
	var amax := -INF
	var bmin := INF
	var bmax := -INF
	for k in 4:
		var q: Vector2 = box.position + box.size * Vector2(k % 2, k / 2) - pos
		amin = minf(amin, q.dot(right))
		amax = maxf(amax, q.dot(right))
		bmin = minf(bmin, q.dot(back))
		bmax = maxf(bmax, q.dot(back))
	var h := Farms.CELL * 0.5
	var turn := FarmView.HEADLAND
	for bj in range(floori(bmin / CELL), ceili(bmax / CELL)):
		for ai in range(floori(amin / CELL), ceili(amax / CELL)):
			var a := (ai + 0.5) * CELL
			var b := (bj + 0.5) * CELL
			var p := pos + right * a + back * b
			if not box.has_point(p):
				continue
			var cell := Vector2i(roundi(a / Farms.CELL), roundi(b / Farms.CELL))
			if not owned.has(cell):
				continue
			var la := a - cell.x * Farms.CELL
			var lb := b - cell.y * Farms.CELL
			var forty := Farms.forty_of(cell)
			var open_side := func(dc: Vector2i) -> bool:
				return not owned.has(cell + dc) or Farms.forty_of(cell + dc) != forty
			# Keep off the fencerows and the grass strips between fields.
			if (la < -h + 3.0 and open_side.call(Vector2i(-1, 0))) or (la > h - 3.0 and open_side.call(Vector2i(1, 0))) \
					or (lb < -h + 3.0 and open_side.call(Vector2i(0, -1))) or (lb > h - 3.0 and open_side.call(Vector2i(0, 1))):
				continue
			if trimmed.has(cell) and not trimmed[cell].any(func(poly): return Geometry2D.is_point_in_polygon(p, poly)):
				continue
			var slot := FarmView.slot_of(id, f, cell)
			var kind := kind_of(slot)
			kinds[slot] = kind
			if kind == "":
				continue
			var head: bool = (lb < -h + turn and open_side.call(Vector2i(0, -1))) or (lb > h - turn and open_side.call(Vector2i(0, 1)))
			var along := right if head else back
			var across := back if head else right
			var coord := b if head else a
			var sp := _spacing(slot)
			var k0 := ceili((coord - CELL * 0.5) / sp - 0.5)
			var k1 := floori((coord + CELL * 0.5) / sp - 0.5 - 0.0001)
			for k in range(k0, k1 + 1):
				var off := (k + 0.5) * sp - coord
				_emit(bufs[kind], p + across * off, across, along, slot, k, hs, o, n)


## Farmsteads out in the county (terrain/grant_in/farmsteads.bin, the same
## places FarmsteadView draws), binned by 256 m.
static func _near_farmstead(r: Vector2, reach: float) -> bool:
	if _steads.is_empty():
		_steads[Vector2i(1 << 20, 0)] = []  # loaded, even if the file is missing
		var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
		if data.size() >= 8 and data.slice(0, 4).get_string_from_ascii() == "FST1":
			var count := data.decode_u32(4)
			for i in count:
				var at := 8 + i * 7
				var p := Vector2(data.decode_s16(at), data.decode_s16(at + 2))
				var b := Vector2i(floori(p.x / 256.0), floori(p.y / 256.0))
				if not _steads.has(b):
					_steads[b] = []
				_steads[b].append(p)
	var b0 := Vector2i(floori(r.x / 256.0), floori(r.y / 256.0))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for p in _steads.get(b0 + Vector2i(dx, dz), []):
				if (p as Vector2).distance_to(r) < reach:
					return true
	return false


# --- The plants -------------------------------------------------------------

## A 4 m piece of row of corn or soybeans, full or light. Built at full size
## (corn 2.7 m, beans 0.92 m); the shader sizes it for today.
##   COLOR: r part (0 stalk, 0.5 leaf, 1 tassel), g the plant's own random,
##     b how far along the leaf, a where on the stalk it grows (0 to 1)
##   UV2: the plant's foot (x, z), to thin plants out whole at the edge
static func mesh(kind: String, near: bool) -> Mesh:
	var key := "%s %s" % [kind, near]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "corn" or kind == "stalks":
		for i in PLANTS:
			var z := -CELL * 0.5 + (i + 0.5) * CELL / PLANTS
			var rnd := CropCalendar.h01(i, 0, 31)
			_corn_plant(st, Vector3((rnd - 0.5) * 0.05, 0.0, z), rnd, near, kind == "stalks")
	else:
		# Farther out, half as many bushes, each a little fuller.
		var bushes := 20 if near else 10
		for i in bushes:
			var z := -CELL * 0.5 + (i + 0.5) * CELL / bushes
			var rnd := CropCalendar.h01(i, 1, 31)
			_soy_plant(st, Vector3((rnd - 0.5) * 0.04, 0.0, z), rnd, near)
	var m := st.commit()
	_meshes[key] = m
	return m


static func _vert(st: SurfaceTool, p: Vector3, n: Vector3, part: float, rnd: float, along: float, at: float,
		foot: Vector3) -> void:
	st.set_color(Color(part, rnd, along, at))
	st.set_uv2(Vector2(foot.x, foot.z))
	st.set_normal(n.normalized())
	st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, part: float,
		rnd: float, along: Array, at: float, foot: Vector3) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		_vert(st, [a, b, c, d][idx], n, part, rnd, along[idx], at, foot)


## A corn plant: a stalk, leaves alternating on two sides (corn's leaves are
## two-ranked) that rise and arch over, longest in the middle, and a tassel.
## `stalks_only`: just the stalk, for the stubble after harvest (the
## shader cuts it to about 40 cm).
static func _corn_plant(st: SurfaceTool, foot: Vector3, rnd: float, near: bool, stalks_only := false) -> void:
	var top := 2.3
	var turn := rnd * TAU
	for side in ([0.0, PI * 0.5] if near else [turn]):
		var w := Vector3(cos(turn + side), 0.0, sin(turn + side)) * 0.013
		_quad(st, foot - w * 1.4, foot + w * 1.4, foot + w + Vector3(0, top, 0), foot - w + Vector3(0, top, 0),
			Vector3(-w.z, 0.2, w.x), 0.0, rnd, [0.0, 0.0, 1.0, 1.0], 0.0, foot)
	if stalks_only:
		return
	# Leaves face across the row (the field's canopy closes between rows).
	var leaves := 8 if near else 4
	var base_az := PI * 0.5 + (rnd - 0.5) * 0.8
	for k in leaves:
		var kk := k if near else k * 2 + 1
		var at := 0.1 + 0.085 * kk
		var length := 0.55 + 0.4 * sin(PI * (kk + 1) / 9.0)
		var az := base_az + (PI if kk % 2 == 1 else 0.0) + (CropCalendar.h01(kk, int(rnd * 999.0), 7) - 0.5) * 0.7
		var out := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-out.z, 0.0, out.x)
		var p0 := foot + Vector3(0, at * 2.7, 0)
		var p1 := p0 + out * length * 0.5 + Vector3(0, length * 0.3, 0)
		var p2 := p1 + out * length * 0.5 - Vector3(0, length * 0.28, 0)
		var w0 := 0.035
		var w1 := 0.05
		var n := Vector3(0, 1, 0) + out * 0.2
		var a := at
		if near:
			_quad(st, p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1, n, 0.5, rnd, [0.0, 0.0, 0.5, 0.5], a, foot)
			for idx in 3:
				_vert(st, [p1 - side * w1, p1 + side * w1, p2][idx], n, 0.5, rnd, [0.5, 0.5, 1.0][idx], a, foot)
		else:
			_quad(st, p0 - side * w0, p0 + side * w0, p2 + side * w0 * 0.5, p2 - side * w0 * 0.5, n, 0.5, rnd,
				[0.0, 0.0, 1.0, 1.0], a, foot)
	# The tassel, 2.3 to 2.7 m: a thin central spike and its side branches,
	# narrow, as a diamond.
	for side in ([0.0, PI * 0.5] if near else [turn]):
		var w := Vector3(cos(turn + side), 0.0, sin(turn + side)) * 0.03
		var b := foot + Vector3(0, top, 0)
		_quad(st, b, b + w + Vector3(0, 0.18, 0), b + Vector3(0, 0.4, 0), b - w + Vector3(0, 0.18, 0),
			Vector3(-w.z, 0.5, w.x), 1.0, rnd, [0.0, 0.5, 1.0, 0.5], 1.0, foot)


## A soybean plant: a stem and trifoliate leaves in tiers, a bushy mound
## about 0.9 m tall that fills the row.
static func _soy_plant(st: SurfaceTool, foot: Vector3, rnd: float, near: bool) -> void:
	var turn := rnd * TAU
	var w := Vector3(cos(turn), 0.0, sin(turn)) * 0.007
	_quad(st, foot - w, foot + w, foot + w + Vector3(0, 0.6, 0), foot - w + Vector3(0, 0.6, 0),
		Vector3(-w.z, 0.3, w.x), 0.0, rnd, [0.0, 0.0, 1.0, 1.0], 0.0, foot)
	var leaves := 10 if near else 5
	for k in leaves:
		var h := CropCalendar.h01(k, int(rnd * 997.0), 13)
		var at := 0.3 + 0.7 * (k + 0.5) / leaves
		var az := turn + k * 2.4 + h
		var out := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-out.z, 0.0, out.x)
		var reach := 0.06 + 0.16 * h * (1.2 - at)
		var c := foot + out * reach + Vector3(0, at * 0.92, 0)
		var size := 0.13 if near else 0.2
		var tip := c + out * size + Vector3(0, -0.02, 0)
		var n := Vector3(0, 1, 0) + out * 0.3
		_quad(st, c - side * size * 0.45, c + side * size * 0.45, tip + side * size * 0.4, tip - side * size * 0.4, n,
			0.5, rnd, [0.0, 0.0, 1.0, 1.0], at, foot)


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER_HEAD + CropCalendar.GLSL + SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("crop_table", CropCalendar.texture())
	return _mat


const SHADER_HEAD := """
shader_type spatial;
render_mode cull_disabled;
"""

const SHADER := """
// x, z: where the plants are centred; radius; how far faded out by height.
uniform vec4 fade = vec4(0.0, 0.0, 60.0, 0.0);
varying vec3 tint;
varying float shade;

void vertex() {
	ivec2 slot = ivec2(int(INSTANCE_CUSTOM.x + 0.5), int(INSTANCE_CUSTOM.y + 0.5));
	vec4 t0 = crop_texel(slot, 0);
	vec4 t2 = crop_texel(slot, 2);
	vec4 t3 = crop_texel(slot, 3);
	float crop = floor(t2.a * 8.0 + 0.5);
	bool corn = crop < 1.5;
	float part = COLOR.r;
	float rnd = fract(COLOR.g + INSTANCE_CUSTOM.z / 256.0 * 0.618);
	float along = COLOR.b;
	float at = COLOR.a;
	float full = corn ? 2.7 : 0.92;
	float h = t2.r * 4.0 * (0.9 + 0.2 * rnd);
	float harvested = t3.b;
	float sy = h / full;
	// As wide as the share of the row the leaves cover (corn's leaves reach
	// about 0.9 m out at full size, a bean plant about 0.25 m).
	float cover = t0.a;
	float sxz = corn ? clamp(max(cover * 1.05, h / 2.7), 0.22, 1.0) : clamp(cover * 1.55 + 0.15, 0.3, 1.15);
	bool gone = false;
	// Tassels only once the corn has reached its full height.
	if (part > 0.75 && (h < t3.a * 4.0 * 0.95 || harvested > 0.5)) {
		gone = true;
	}
	if (harvested > 0.5) {
		// Corn stalks after the combine: the stalk cut off about 40 cm up.
		sy = 0.4 * (0.75 + 0.5 * rnd) / 2.3;
		sxz = 1.0;
		gone = gone || part > 0.25;
	}
	// Soybean leaves fall at maturity, a few at a time.
	if (!corn && part > 0.25 && fract(at * 7.13 + rnd * 3.7) > t3.g) {
		gone = true;
	}
	// Thinned out toward the edge of where plants are drawn, and as the
	// camera climbs, whole plants at a time.
	vec2 foot = (MODEL_MATRIX * vec4(UV2.x, 0.0, UV2.y, 1.0)).xz;
	float edge = smoothstep(fade.z * 0.6, fade.z, distance(foot, fade.xy));
	if (fract(rnd * 13.7 + at * 0.01) < max(edge, fade.w) * 1.02) {
		gone = true;
	}
	if (gone) {
		VERTEX = vec3(UV2.x, -0.3, UV2.y);
	} else {
		vec3 base = vec3(UV2.x, 0.0, UV2.y);
		vec3 d = VERTEX - base;
		// Drying corn leaves hang down along the stalk.
		if (corn && part > 0.25 && part < 0.75) {
			d.y -= along * along * 0.45 * (1.0 - t2.g);
		}
		VERTEX = base + vec3(d.x * sxz, d.y * sy, d.z * sxz);
	}
	// Colour: today's crop colour from the table, the leaves lighter than
	// the field seen from above (which counts the shade between them), the
	// lower leaves firing first as the corn matures.
	float green = t2.g;
	vec3 leaf = crop_lin(t0.rgb) * 1.2;
	vec3 dry = crop_lin(vec3(0.56, 0.48, 0.33));
	float fire = clamp((1.0 - green) * 1.8 - at * 0.8, 0.0, 1.0);
	tint = mix(leaf, dry, fire * 0.8);
	if (part < 0.25) {
		tint = corn ? mix(tint * 1.05, dry, max(1.0 - green, 0.06)) : mix(tint * 0.8, crop_lin(vec3(0.45, 0.36, 0.25)), 1.0 - green);
	}
	if (part > 0.75) {
		tint = crop_lin(vec3(0.62, 0.55, 0.36));
	}
	if (harvested > 0.5) {
		tint = crop_lin(t0.rgb) * 0.95;
	}
	tint *= (0.88 + 0.24 * rnd) * (0.92 + 0.16 * along);
	// Deeper in the canopy is darker.
	shade = mix(0.65, 1.0, clamp(at * 1.3 + 0.2, 0.0, 1.0));
}

void fragment() {
	ALBEDO = tint * shade * (FRONT_FACING ? 1.0 : 0.82);
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.18, 0.22, 0.1);
}
"""
