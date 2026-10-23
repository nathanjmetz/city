class_name IndustryBuilder
extends FarmBuilder
## Resource companies, built from the same realistic parts as the town.
## Benchmark: photos of Illinois Basin oil leases and southern Indiana
## surface coal mines. (Forestry is ForestryBuilder's.)
##   - every company has a low metal-sided office with a gravel lot
##   - oil: beam pumpjacks on steel skids with a wellhead, and a tank battery
##     (welded tanks, catwalk, stairs) at the main yard
##   - ore (coal on this map): a preparation plant whose conveyor feeds a
##     black coal pile, with raw and clean coal stockpiles beside it; the
##     mine itself is one strip mine for the whole company (build_strip_mine)
## Local space: the company faces -z, like FarmView's farmsteads.

const OFFICE_WALL := ["#d8d6cf", "#c9cbc8", "#b9b4a6", "#c2b59b"]
const TANK := ["#b9a57e", "#c8c2b2", "#7d8a74", "#9a9fa2"]
const JACK := ["#3d4a3f", "#5b6066", "#2f3a46", "#6b5a2a"]
const QUARRY := Color("#c8c1b0")  # limestone


## [mesh, ground mesh] for a company's main yard. `built` is what its
## leader has built (Agency.TREES) and `addons` where each add-on stands
## (Industry.ADDONS), so every upgrade shows (UpgradeKits).
static func build_hq(kind: String, seed: int, built := [], addons := {}) -> Array:
	var b := IndustryBuilder.new()
	b._begin(seed)
	b._flat_rect("gravel", -20, 20, -20, 20, 0.09, YARD_GRAVEL)
	b._office(-8.0, -10.0)
	match kind:
		"oil":
			if "tank_battery" in built:
				b._tank_battery(Vector3(10, 0, 6))
			else:
				UpgradeKits.lease_tanks(b, Vector3(10, 0, 6))
		"ore":
			if "crusher" in built:
				b._crusher(Vector3(8, 0, 4))
			else:
				# Trucks tip run-of-mine coal straight onto the pile.
				b._cone(Vector3(8.0, 0, 6.0), 6.0, 4.0, COAL.lightened(0.05), 16, "paint")
			# Raw coal waiting for the plant and washed coal waiting for trucks.
			b._flat_rect("gravel", -28, 34, 20, 36, 0.09, COAL.lightened(0.15))
			b._cone(Vector3(-14.0, 0, 28.0), 9.0, 6.0, COAL.lightened(0.05), 18, "paint")
			b._cone(Vector3(16.0, 0, 28.0), 8.0, 5.5, COAL, 18, "paint")
	for node in addons:
		var at := Vector3(float(addons[node][0]), 0, float(addons[node][1]))
		match str(node):
			"gas_plant": UpgradeKits.gas_plant(b, at)
			"pipeline": UpgradeKits.pipeline(b, at - Vector3(1.5, 0, 1.5), 40.0 if at.x > 0.0 else -40.0)
			"frac_crew": UpgradeKits.completion_yard(b, at)
			"terminal": UpgradeKits.crude_terminal(b, at)
			"wash_plant": UpgradeKits.prep_plant(b, at)
			"conveyor":
				# Out of the crusher's side, to a transfer house at the yard's edge.
				UpgradeKits.overland_conveyor(b, Vector3(14.0, 9.0, at.z), Vector3(at.x + 11.0, 0, at.z))
			"rail_loadout": UpgradeKits.rail_loadout(b, at)
	return [b._commit_house(), b._commit_flat()]


## [mesh, ground mesh] for one pad: a well or a pit.
## A well's walking beam is separate (see build_beam) so it can rock.
static func build_pad(kind: String, seed: int) -> Array:
	var b := IndustryBuilder.new()
	b._begin(seed)
	match kind:
		"oil": b._well_pad()
		"ore": b._pit()
	return [b._commit_house(), b._commit_flat()]


## A pumpjack's walking beam and horsehead, pivoting at the origin (the
## saddle bearing on top of the samson post). The horsehead is toward -x.
static func build_beam(seed: int) -> ArrayMesh:
	var b := IndustryBuilder.new()
	b._begin(seed)
	var col := Color(b._pick(JACK))
	b._box("paint", Vector3(8.6, 0.55, 0.35), Vector3(-0.6, 0.0, 0), col)
	b._box("paint", Vector3(8.6, 0.08, 0.6), Vector3(-0.6, 0.27, 0), col)
	b._box("paint", Vector3(8.6, 0.08, 0.6), Vector3(-0.6, -0.27, 0), col)
	# Horsehead: a curved plate built from short segments.
	for i in 7:
		var a := lerpf(-0.9, 0.9, i / 6.0)
		var p := Vector3(-4.9 - cos(a) * 0.6, sin(a) * 1.3, 0)
		b._box("paint", Vector3(0.35, 0.42, 0.7), p, col, Basis(Vector3(0, 0, 1), a))
	# Equalizer at the tail, and the pitman arms down to the cranks.
	b._box("paint", Vector3(0.3, 0.3, 1.8), Vector3(3.6, 0, 0), col)
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(0.18, 3.2, 0.18), Vector3(3.6, -1.6, s * 0.85), col)
	return b._commit_house()


func _begin(seed: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	_flat.begin(Mesh.PRIMITIVE_TRIANGLES)


## A one-storey pre-engineered metal office with a brick wainscot.
func _office(cx: float, cz: float) -> void:
	var w := 14.0
	var d := 10.0
	var wall := Color(_pick(OFFICE_WALL))
	var zf := cz - d * 0.5
	_box("concrete", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(cx, 0.15, cz), FOUNDATION)
	_box("metal", Vector3(w, 3.6, d), Vector3(cx, 2.1, cz), wall)
	_box("brick", Vector3(w + 0.04, 1.0, d + 0.04), Vector3(cx, 0.8, cz), Color(_pick(BRICK)))
	_metal_roof(cx, cz, 3.9, w, d, Color("#8e9aa3"))
	_front_door(cx - 3.0, zf - 0.02, 0.3, Color("#2a2a2c"))
	for x in [cx - 5.5, cx + 0.5, cx + 4.5]:
		_window(Vector3(x, 2.1, zf), Vector3(-1, 0, 0), 1.6, 1.1, false, false, TRIM)
	_stoop(cx - 3.0, zf, 2.0, 1.4, 0.3)
	_sign(Vector3(cx + 2.5, 3.35, zf - 0.08), 5.0, 0.45)
	# A few parking stalls.
	_flat_rect("asphalt", cx - 7, cx + 7, zf - 7.0, zf - 1.5, 0.1)
	for i in 6:
		var x := cx - 6.5 + i * 2.7
		_flat_rect("line", x - 0.05, x + 0.05, zf - 6.6, zf - 2.0, 0.11, LINE)


## Three welded stock tanks on a gravel pad with a catwalk and stairs.
func _tank_battery(at: Vector3) -> void:
	var col := Color(_pick(TANK))
	_flat_rect("gravel", at.x - 10, at.x + 10, at.z - 5, at.z + 5, 0.1, GRAVEL)
	for i in 3:
		var c := at + Vector3(-6.0 + i * 6.0, 0, 0)
		_cylinder("paint", c + Vector3(0, 0.2, 0), 2.6, 6.6, col, 18)
		_cone(c + Vector3(0, 6.8, 0), 2.7, 0.5, col.darkened(0.05), 18, "paint")
		_box("paint", Vector3(0.6, 0.12, 0.6), c + Vector3(0, 7.35, 0), Color("#4a4a4a"))  # thief hatch
	_box("paint", Vector3(14, 0.1, 1.0), at + Vector3(0, 7.0, 0), Color("#5b6066"))  # catwalk
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(14, 0.06, 0.06), at + Vector3(0, 8.0, s * 0.5), Color("#c9a020"))
	# Stairs up one end.
	for k in 13:
		_box("paint", Vector3(0.35, 0.08, 1.0), at + Vector3(-14.0 + k * 0.55, 0.3 + k * 0.53, 0), Color("#5b6066"))
	for s in [-1.0, 1.0]:
		var foot := at + Vector3(-14.0, 0.6, s * 0.5)
		var top := at + Vector3(-7.0, 7.6, s * 0.5)
		var dir := (top - foot).normalized()
		var side := Vector3(0, 0, 1).cross(dir).normalized()
		_box("paint", Vector3(0.06, (top - foot).length(), 0.06), (foot + top) * 0.5, Color("#c9a020"), Basis(side, dir, side.cross(dir)))
	# Separator and a low firewall berm around the tanks.
	_cylinder("paint", at + Vector3(0, 0.3, -4.0), 0.7, 3.2, Color("#9a9fa2"), 10)
	_flat_rect("gravel", at.x - 9.6, at.x + 9.6, at.z - 3.6, at.z - 3.0, 0.12, Color("#8d7a5e"))
	_flat_rect("gravel", at.x - 9.6, at.x + 9.6, at.z + 3.0, at.z + 3.6, 0.12, Color("#8d7a5e"))


## A well pad: gravel, a pumpjack's base, gearbox and samson post, the
## wellhead, and a small tank.
func _well_pad() -> void:
	_flat_rect("gravel", -13, 13, -11, 11, 0.09, YARD_GRAVEL)
	var col := Color(_pick(JACK))
	var at := Vector3(-3, 0, 0)
	# Skid: two steel I-beams with cross members.
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(9.5, 0.45, 0.3), at + Vector3(0.2, 0.42, s * 0.9), col)
	for x in [-4.0, 0.0, 4.0]:
		_box("paint", Vector3(0.3, 0.3, 2.1), at + Vector3(x, 0.35, 0), col)
	_box("concrete", Vector3(10, 0.2, 2.8), at + Vector3(0.2, 0.1, 0), FOUNDATION)
	# Samson post: an A-frame of two legs each side up to the saddle.
	for s in [-1.0, 1.0]:
		for lean in [-1.0, 1.0]:
			var foot := at + Vector3(lean * 1.0, 0.6, s * 0.8)
			var top := at + Vector3(0, 5.5, s * 0.25)
			var mid := (foot + top) * 0.5
			var dir := (top - foot).normalized()
			var side := dir.cross(Vector3(0, 0, 1)).normalized()
			_box("paint", Vector3(0.22, (top - foot).length(), 0.22), mid, col, Basis(side, dir, side.cross(dir)))
	# Gearbox, crank arms and counterweights.
	var g := at + Vector3(3.6, 0, 0)
	_box("paint", Vector3(1.6, 1.4, 1.1), g + Vector3(0, 1.4, 0), col)
	_box("paint", Vector3(0.9, 0.9, 0.8), g + Vector3(1.4, 1.0, 0), Color("#3a3a3a"))  # motor
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(2.2, 0.35, 0.2), g + Vector3(-0.2, 1.9, s * 0.75), col)
		_box("paint", Vector3(1.0, 1.0, 0.28), g + Vector3(-1.2, 1.7, s * 0.85), Color("#2a2a2a"))
	# Wellhead under the horsehead, with its polished rod.
	var w := at + Vector3(-5.5, 0, 0)
	_box("concrete", Vector3(1.6, 0.25, 1.6), w + Vector3(0, 0.12, 0), FOUNDATION)
	_cylinder("paint", w + Vector3(0, 0.25, 0), 0.22, 1.3, Color("#8a2f22"), 8)
	_box("paint", Vector3(0.06, 2.6, 0.06), w + Vector3(0, 2.8, 0), Color("#c8c8c8"))
	_box("paint", Vector3(1.2, 0.12, 0.12), w + Vector3(0, 1.0, 0), Color("#8a2f22"))
	# A small stock tank by the edge.
	var t := Vector3(8, 0, 6)
	_cylinder("paint", t + Vector3(0, 0.2, 0), 1.6, 4.6, Color(_pick(TANK)), 14)
	_cone(t + Vector3(0, 4.8, 0), 1.7, 0.35, Color(_pick(TANK)), 14, "paint")


## A stepped limestone quarry: pale benches, darker faces, a wet floor and
## a haul ramp, with a stockpile at one corner.
func _pit() -> void:
	var y := 0.09
	for i in 5:
		var h := 36.0 - i * 6.5
		var bench := QUARRY.darkened(i * 0.07)
		var face := QUARRY.darkened(0.25 + i * 0.07)
		_ring(h, h - 3.5, y, bench)
		_ring(h - 3.5, h - 6.5, y + 0.01, face)
		y += 0.02
	_flat_rect("gravel", -4.0, 4.0, -4.0, 4.0, y, Color("#6d7466"))  # rain water on the floor
	_flat_rect("gravel", 30.0, 34.0, -36.0, 30.0, y + 0.01, QUARRY.darkened(0.1))  # haul ramp
	_cone(Vector3(28, 0, -28), 6.0, 4.5, Color("#b5ae9e"), 16, "paint")


## A square ring between two half-widths.
func _ring(outer: float, inner: float, y: float, col: Color) -> void:
	_flat_rect("gravel", -outer, outer, -outer, -inner, y, col)
	_flat_rect("gravel", -outer, outer, inner, outer, y, col)
	_flat_rect("gravel", -outer, -inner, -inner, inner, y, col)
	_flat_rect("gravel", inner, outer, -inner, inner, y, col)


## A coal preparation plant: a tall metal building, an inclined conveyor on
## legs and the coal pile it feeds.
func _crusher(at: Vector3) -> void:
	var wall := Color("#b9b4a6")
	_box("concrete", Vector3(12.2, 0.4, 12.2), at + Vector3(0, 0.2, 0), FOUNDATION)
	_box("metal", Vector3(12, 11.6, 12), at + Vector3(0, 6.2, 0), wall)
	_metal_roof(at.x, at.z, 12.0, 12, 12, Color("#8e9aa3"))
	_box("metal", Vector3(4.5, 4.5, 0.1), at + Vector3(0, 2.65, -6.05), wall.darkened(0.25))  # truck door
	# Conveyor from the top of the house down to the pile.
	var top := at + Vector3(-6.0, 10.0, 4.0)
	var pile := at + Vector3(-22.0, 0, 6.0)
	var foot := pile + Vector3(0, 7.5, 0)
	var dir := (foot - top).normalized()
	var side := Vector3(0, 1, 0).cross(dir).normalized()
	var up := dir.cross(side)
	_box("paint", Vector3((foot - top).length(), 0.5, 1.0), (top + foot) * 0.5, Color("#6b6f73"), Basis(dir, up, side))
	for t in [0.3, 0.65]:
		var p: Vector3 = top.lerp(foot, t)
		_box("paint", Vector3(0.25, p.y, 0.25), Vector3(p.x, p.y * 0.5, p.z), Color("#6b6f73"))
	_cone(pile, 9.0, 7.0, COAL, 18, "paint")


## A surface coal mine in the company's local frame. Benchmark: aerial
## photos of Indiana area strip mines (Peabody's Bear Run in Sullivan County,
## Lynnville in Warrick County, the old Ayrshire mines in Pike County).
## The mine advances one long straight cut at a time:
##   - the open pit lies against the highwall of unmined ground: a straight
##     face of till, shale and sandstone with the coal seam black at its foot
##   - the coal is uncovered on the pit floor, loaded by a loader into haul
##     trucks, which climb a ramp at the end of the pit; rain gathers in a
##     sump at the far end
##   - a walking dragline stands on the highwall side and casts each cut's
##     overburden into the cut before, so spoil lies in long parallel ridges
##   - older ridges are graded back to pasture, sometimes with a pond in the
##     last trough
## `outlines` is the mined ground (x, z); `rows` is one [z, age] per cut,
## `pitch` metres deep along z, age 0 being the newest ground opened.
## The haul road leaves the pit toward `toward` (the main yard).
static func build_strip_mine(seed: int, outlines: Array, rows: Array, pitch: float, toward := Vector2.ZERO) -> Array:
	var b := IndustryBuilder.new()
	b._begin(seed)
	b._water = SurfaceTool.new()
	b._water.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._grass = SurfaceTool.new()
	b._grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._strip_mine(outlines, rows, pitch, toward)
	var flat := b._commit_flat()
	if b._water_n > 0:
		b._water.commit(flat)
		flat.surface_set_material(flat.get_surface_count() - 1, TerrainView.water_material())
	if b._grass_n > 0:
		b._grass.commit(flat)
		flat.surface_set_material(flat.get_surface_count() - 1, _reclaimed_mat())
	return [b._commit_house(), flat]


var _water: SurfaceTool
var _plant_yard := Rect2()
var _grass: SurfaceTool
var _water_n := 0
var _grass_n := 0

const SPOIL := Color("#8b8170")      # fresh cast overburden: grey-brown shale and till
const SPOIL_OLD := Color("#7d8459")  # a few years on: weeds coming in
const SPOIL_GREEN := Color("#667f45") # fescue, broomsedge and autumn olive over the ridge
const COAL := Color("#24221f")
const BENCH := Color("#857358")      # subsoil left after the topsoil is scraped off
const TOPSOIL := Color("#5a4a37")
const UNDERCLAY := Color("#6f6b62")  # the grey fireclay under the seam
const RAMP := Color("#93897a")
# The highwall from the crest down: soil and till, grey shale, sandstone,
# dark shale, a thin limestone, then the coal seam itself.
const STRATA := [[0.0, 1.2, "#9c8f76"], [1.2, 2.4, "#6f5a42"], [2.4, 3.5, "#7e7d78"],
	[3.5, 4.5, "#a8966f"], [4.5, 5.3, "#4f4e4a"], [5.3, 5.9, "#a19c8f"], [5.9, 7.4, "#1b1a18"]]
const RIDGE_H := 12.0
const YARD := Vector2(50.0, 40.0)  # half-size of the plant yard kept clear  # cast spoil stands 10-15 m above the old ground


static func _reclaimed_mat() -> Material:
	return HouseMaterials.get_mat("pasture")


func _strip_mine(outlines: Array, rows: Array, pitch: float, toward: Vector2) -> void:
	if rows.is_empty() or outlines.is_empty():
		return
	rows = rows.duplicate()
	rows.sort_custom(func(a, b): return a[0] < b[0])
	# The plant and its yard stay on unmined ground, whole cuts deep so
	# every band is cut clean through and nothing is left with a hole in it.
	var y0: float = floorf((-YARD.y - rows[0][0]) / pitch) * pitch + rows[0][0]
	var y1: float = ceilf((YARD.y - rows[0][0]) / pitch) * pitch + rows[0][0]
	_plant_yard = Rect2(-YARD.x, y0, YARD.x * 2.0, y1 - y0)
	var by_z := {}
	for i in rows.size():
		by_z[roundi(rows[i][0] / pitch)] = i
	# The pit: the newest cut at the edge of the mined ground. The highwall
	# is the side with no mined ground beyond it.
	var youngest := INF
	for r in rows:
		youngest = minf(youngest, r[1])
	var pit := -1
	var hs := 1.0
	for i in rows.size():
		if rows[i][1] != youngest:
			continue
		var key := roundi(rows[i][0] / pitch)
		for s in [1, -1]:
			if not by_z.has(key + s) and (pit < 0 or rows[i][0] * s > rows[pit][0] * hs):
				pit = i
				hs = s
	if pit < 0:
		pit = rows.size() - 1
	for i in rows.size():
		var z0: float = rows[i][0]
		var age: float = rows[i][1]
		var rect := PackedVector2Array([Vector2(-1e4, z0), Vector2(1e4, z0), Vector2(1e4, z0 + pitch), Vector2(-1e4, z0 + pitch)])
		if i == pit:
			_pit_row(outlines, z0, pitch, hs, toward)
		elif absi(i - pit) <= 5:
			# Spoil: each cut back from the pit is a season or two older
			# (a dragline casts a cut every few months), so the ridges go
			# from bare shale beside the pit to weedy, then grassed over,
			# before they are graded back to pasture.
			var fresh := clampf((absi(i - pit) - 1 + (age - youngest) * 0.5) / 4.0, 0.0, 1.0)
			var col := SPOIL.lerp(SPOIL_OLD, fresh * 2.0) if fresh < 0.5 else SPOIL_OLD.lerp(SPOIL_GREEN, fresh * 2.0 - 1.0)
			_flat_clip(outlines, rect, 0.13, col)
			_ridge(outlines, z0 + pitch * 0.5, pitch, RIDGE_H * (1.0 - fresh * 0.2), col)
			# Rain water stands in some troughs between older ridges.
			if fresh > 0.5 and rng.randf() < 0.5:
				var span := _span(outlines, z0)
				if span.y - span.x > 60.0:
					var a := rng.randf_range(span.x + 10.0, span.y - 50.0)
					_water_clip(outlines, PackedVector2Array([Vector2(a, z0 - 3.0), Vector2(a + rng.randf_range(30.0, 60.0), z0 - 3.0),
						Vector2(a + rng.randf_range(30.0, 60.0), z0 + 3.0), Vector2(a, z0 + 3.0)]), 0.6)
		else:
			# Graded back to hay and pasture, a shade per cut.
			var g := Color("#6c8746").lerp(Color("#7a8f4e"), rng.randf())
			for poly in _clip(outlines, rect):
				_poly_into(_grass, poly, 0.13, g)
				_grass_n += 1


## The open cut: highwall, coal seam, uncovered coal, the underclay floor
## with a sump, the ramp at the end nearer the yard, and the equipment.
## `hs` is +1 when the highwall is the cut's high-z side.
func _pit_row(outlines: Array, z0: float, pitch: float, hs: float, toward: Vector2) -> void:
	# u: metres from the highwall crest into the pit.
	var zu := func(u: float) -> float:
		return z0 + pitch - u if hs > 0.0 else z0 + u
	# The cut runs the full length of the ground behind it, square at the
	# ends, not rounded off with the edge of the mined ground.
	var span := _span(outlines, zu.call(pitch + 2.0))
	if span.y - span.x < 30.0:
		span = _span(outlines, zu.call(pitch * 0.5))
	if span.y - span.x < 30.0:
		return
	var band := func(u0: float, u1: float, y: float, col: Color) -> void:
		var a: float = zu.call(u0)
		var c: float = zu.call(u1)
		_poly_into(_flat, PackedVector2Array([Vector2(span.x, minf(a, c)), Vector2(span.y, minf(a, c)),
			Vector2(span.y, maxf(a, c)), Vector2(span.x, maxf(a, c))]), y, col)
	# Ahead of the face scrapers have stripped the topsoil for the next cut
	# and the dragline walks on the bare bench; the topsoil waits in a long
	# windrow to go back on the graded spoil.
	var yard := PackedVector2Array([_plant_yard.position, Vector2(_plant_yard.end.x, _plant_yard.position.y), _plant_yard.end, Vector2(_plant_yard.position.x, _plant_yard.end.y)])
	var a0: float = zu.call(-32.0)
	var a1: float = zu.call(0.0)
	# Dozed ground has no square corners: its outer edge wanders and its
	# ends round off.
	var bench := PackedVector2Array()
	var lo_z := minf(a0, a1)
	var hi_z := maxf(a0, a1)
	var outer_lo := a0 < a1  # the outer edge is the one away from the cut
	var steps := maxi(ceili((span.y - span.x) / 10.0), 2)
	for k in steps + 1:
		var x := lerpf(span.x, span.y, float(k) / steps)
		var end := 1.0 - minf(minf(k, steps - k) / 2.0, 1.0)
		var jig := rng.randf_range(-3.0, 3.0) + end * 9.0
		bench.append(Vector2(x, lo_z + (jig if outer_lo else end * 4.0)))
	for k in steps + 1:
		var x := lerpf(span.y, span.x, float(k) / steps)
		var end := 1.0 - minf(minf(k, steps - k) / 2.0, 1.0)
		var jig := rng.randf_range(-3.0, 3.0) + end * 9.0
		bench.append(Vector2(x, hi_z - (end * 4.0 if outer_lo else jig)))
	for piece in (Geometry2D.clip_polygons(bench, yard) if _plant_yard.has_area() else [bench]):
		if not Geometry2D.is_polygon_clockwise(piece):
			_poly_into(_flat, piece, 0.12, BENCH)
	_ridge_on(Vector2(span.x + (span.y - span.x) * 0.15, span.y - (span.y - span.x) * 0.15), zu.call(-29.0), 7.0, 3.5, TOPSOIL)
	for s in STRATA:
		band.call(s[0], s[1], 0.13, Color(s[2]).darkened(0.12))  # the face is steep and half in shade
	band.call(7.4, 16.0, 0.13, COAL)
	band.call(16.0, pitch, 0.13, UNDERCLAY)
	# The ramp climbs out at the end nearer the yard, along the cut.
	var near_end := span.x if absf(span.x - toward.x) < absf(span.y - toward.x) else span.y
	var dirx := 1.0 if near_end == span.x else -1.0
	var r0: float = zu.call(8.0)
	var r1: float = zu.call(20.0)
	_flat_rect("gravel", minf(near_end, near_end + dirx * 45.0), maxf(near_end, near_end + dirx * 45.0), minf(r0, r1), maxf(r0, r1), 0.15, RAMP)
	# The haul road from the top of the ramp to the plant, around the end
	# of the spoil rather than over it: graded, about 15 m wide for two
	# 100-ton trucks to pass, the mine's palest and straightest line.
	var top := Vector2(near_end - dirx * 6.0, (r0 + r1) * 0.5)
	var edge := INF if dirx > 0.0 else -INF
	for o in outlines:
		for q in o:
			edge = minf(edge, q.x) if dirx > 0.0 else maxf(edge, q.x)
	edge -= dirx * 16.0
	var route := [top, Vector2(edge, top.y), Vector2(edge, toward.y), toward]
	for i in route.size() - 1:
		_road(route[i], route[i + 1], 15.0)
	# The sump at the far end, in the lowest corner of the floor.
	var far_end := span.y if dirx > 0.0 else span.x
	var s0: float = zu.call(17.0)
	var s1: float = zu.call(pitch - 2.0)
	var sl := rng.randf_range(18.0, 30.0)
	_water_clip(outlines, PackedVector2Array([Vector2(minf(far_end, far_end - dirx * sl), minf(s0, s1)), Vector2(maxf(far_end, far_end - dirx * sl), minf(s0, s1)),
		Vector2(maxf(far_end, far_end - dirx * sl), maxf(s0, s1)), Vector2(minf(far_end, far_end - dirx * sl), maxf(s0, s1))]), 0.16)
	# A loader filling two haul trucks on the coal.
	var cx := lerpf(span.x, span.y, rng.randf_range(0.35, 0.65))
	var cz: float = zu.call(11.5)
	_loader(Vector3(cx, 0.0, cz), PI * 0.5 * dirx)
	_haul_truck(Vector3(cx + 11.0, 0.0, cz), PI * 0.5)
	_haul_truck(Vector3(cx - dirx * 40.0, 0.0, zu.call(13.0)), PI * 0.5 * dirx)
	# The dragline on the bench above the highwall, boom out over the pit.
	var dx := lerpf(span.x, span.y, rng.randf_range(0.25, 0.75))
	_dragline(Vector3(dx, 0.0, zu.call(-16.0)), Vector2(rng.randf_range(-0.5, 0.5), -hs).normalized())


## A long ridge of cast spoil along x at `zc`, ragged along its crest and
## tapering at the ends, cut into 8 m pieces so it follows the ground.
func _ridge(outlines: Array, zc: float, pitch: float, h: float, col: Color) -> void:
	for span in _spans(outlines, zc):
		_ridge_on(span, zc, pitch, h, col)


func _ridge_on(span: Vector2, zc: float, pitch: float, h: float, col: Color) -> void:
	var x0 := span.x + 6.0
	var x1 := span.y - 6.0
	if x1 - x0 < 50.0:  # a stub of spoil reads as a heap, not a ridge
		return
	var hw := pitch * 0.5 + 1.0
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / 35.0
	var prof := func(x: float) -> Array:
		# The ends run out at the angle of repose, about 35 degrees.
		var taper := smoothstep(0.0, 1.0, minf(x - x0, x1 - x) / (h * 1.6 + 4.0))
		var hh := maxf(h * (0.85 + noise.get_noise_1d(x) * 0.35) * taper, 0.2)
		var shift := noise.get_noise_1d(x + 500.0) * 3.0
		# Base, shoulder, crest, shoulder, base: steep angle-of-repose sides.
		return [Vector3(x, 0.1, zc - hw), Vector3(x, hh * 0.7, zc - hw * 0.4 + shift), Vector3(x, hh, zc + shift),
			Vector3(x, hh * 0.75, zc + hw * 0.35 + shift), Vector3(x, 0.1, zc + hw)]
	var n := ceili((x1 - x0) / 8.0)
	var prev: Array = prof.call(x0)
	for i in n:
		var cur: Array = prof.call(lerpf(x0, x1, float(i + 1) / n))
		for k in 4:
			var shade := col.darkened(0.06 * absf(k - 1.5))
			_quad("yard", prev[k], cur[k], cur[k + 1], prev[k + 1], shade, [], Vector3.UP)
		prev = cur
	# Close the ends.
	var first: Array = prof.call(x0)
	var last: Array = prof.call(x1)
	for k in 3:
		_tri("yard", first[0], first[k + 1], first[k + 2] if k < 3 else first[4], col, [], Vector3.LEFT)
		_tri("yard", last[0], last[k + 1], last[k + 2] if k < 3 else last[4], col, [], Vector3.RIGHT)


## A walking dragline (a Marion 8750 or Bucyrus-Erie 1370-W class machine):
## a house about 30 m long on a round tub, a gantry, and a lattice boom
## about 100 m long at 35 degrees with its bucket hanging over the pit.
func _dragline(at: Vector3, boom_dir: Vector2) -> void:
	var yaw := Basis(Vector3.UP, atan2(-boom_dir.x, -boom_dir.y))
	var cream := Color("#e3dccb")
	var red := Color("#9b2a22")
	var steel := Color("#5f6266")
	_cyl(at + Vector3(0, 1.0, 0), 11.0, 2.0, steel)  # the tub it rests on
	_box("paint", Vector3(22.0, 12.0, 30.0), at + yaw * Vector3(0, 8.0, 3.0), cream, yaw)
	_box("paint", Vector3(22.1, 1.2, 30.1), at + yaw * Vector3(0, 5.0, 3.0), red, yaw)
	_box("metal", Vector3(22.4, 0.6, 30.4), at + yaw * Vector3(0, 14.3, 3.0), cream.darkened(0.15), yaw)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(5.0, 3.0, 26.0), at + yaw * Vector3(s * 13.5, 2.0, 3.0), steel, yaw)  # walking shoes
	# Gantry (A-frame) on the roof.
	var g := at + yaw * Vector3(0, 30.0, -4.0)
	for s in [-1.0, 1.0]:
		var foot := at + yaw * Vector3(s * 8.0, 14.0, -12.0)
		_strut(foot, g + yaw * Vector3(s * 2.0, 0, 0), 1.0, steel)
		_strut(at + yaw * Vector3(s * 8.0, 14.0, 8.0), g + yaw * Vector3(s * 2.0, 0, 0), 0.8, steel)
	# Boom from the front of the house, out over the pit.
	var foot := at + yaw * Vector3(0, 6.0, -13.0)
	var dir := yaw * Vector3(0, sin(deg_to_rad(35.0)), -cos(deg_to_rad(35.0)))
	var tip := foot + dir * 100.0
	for s in [-1.0, 1.0]:
		_strut(foot + yaw * Vector3(s * 3.5, 0, 0), tip + yaw * Vector3(s * 1.2, 0, 0), 1.6, steel)
	_strut(foot + Vector3(0, 3.0, 0), tip, 1.4, steel)  # top chord: the boom is a triangular lattice
	_strut(g, tip, 0.25, Color("#2b2b2b"))  # suspension ropes
	_strut(tip, tip - Vector3(0, tip.y - at.y - 8.0, 0), 0.2, Color("#2b2b2b"))  # hoist rope to the bucket
	_box("paint", Vector3(7.0, 5.0, 8.0), Vector3(tip.x, at.y + 6.5, tip.z), steel.darkened(0.2), yaw)  # bucket


## A thick line between two points as a box.
func _strut(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var f := d / len
	var side := (Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).cross(f).normalized()
	var up := f.cross(side)
	_box("paint", Vector3(w, w, len), (a + b) * 0.5, col, Basis(side, up, f))


## A short round column as a sixteen-sided prism.
func _cyl(center: Vector3, r: float, h: float, col: Color) -> void:
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var lo := center - Vector3(0, h * 0.5, 0)
		var hi := center + Vector3(0, h * 0.5, 0)
		_quad("paint", lo + p0, lo + p1, hi + p1, hi + p0, col, [], p0 + p1)
		_tri("paint", hi, hi + p0, hi + p1, col, [], Vector3.UP)


## A rigid-frame haul truck (a Cat 777 is about 10 x 6 m, 4.5 m tall),
## its bed heaped with coal.
func _haul_truck(at: Vector3, yaw_a: float) -> void:
	var b := Basis(Vector3.UP, yaw_a)
	var yellow := Color("#d9a521")
	_box("paint", Vector3(6.0, 2.2, 6.4), at + b * Vector3(0, 3.0, 1.2), yellow, b)  # dump body
	_box("paint", Vector3(5.4, 0.6, 5.8), at + b * Vector3(0, 4.3, 1.2), COAL, b)  # its load
	_box("paint", Vector3(5.0, 2.4, 3.0), at + b * Vector3(0, 2.6, -3.6), yellow, b)  # engine and deck
	_box("paint", Vector3(1.6, 1.4, 1.6), at + b * Vector3(-1.4, 4.5, -3.8), Color("#2b2f33"), b)  # cab
	for wz in [-3.6, 2.6]:
		for wx in [-2.6, 2.6]:
			_box("paint", Vector3(0.9, 2.6, 2.6), at + b * Vector3(wx, 1.3, wz), Color("#1e1e1e"), b)


## A large wheel loader (a Cat 992 class), bucket down on the coal.
func _loader(at: Vector3, yaw_a: float) -> void:
	var b := Basis(Vector3.UP, yaw_a)
	var yellow := Color("#d9a521")
	_box("paint", Vector3(3.6, 2.6, 6.5), at + b * Vector3(0, 2.6, 1.5), yellow, b)
	_box("paint", Vector3(2.4, 2.0, 2.2), at + b * Vector3(0, 4.9, 0.4), Color("#2b2f33"), b)
	_box("paint", Vector3(3.2, 1.6, 4.0), at + b * Vector3(0, 2.4, -3.2), yellow, b)
	_box("paint", Vector3(5.6, 2.2, 2.0), at + b * Vector3(0, 1.2, -6.2), Color("#4a4a46"), b)  # bucket
	for wz in [-3.0, 2.6]:
		for wx in [-2.1, 2.1]:
			_box("paint", Vector3(1.0, 2.6, 2.6), at + b * Vector3(wx, 1.3, wz), Color("#1e1e1e"), b)


## A gravel haul road between two points, `w` metres wide.
func _road(a: Vector2, b: Vector2, w: float) -> void:
	if a.distance_to(b) < 1.0:
		return
	var along := (b - a).normalized()
	a -= along * w * 0.5  # run on through the corners
	b += along * w * 0.5
	var side := along.orthogonal() * w * 0.5
	_poly_into(_flat, PackedVector2Array([a - side, b - side, b + side, a + side]), 0.14, Color("#b3aa97"), 1.0)
	# Safety berms of pushed spoil along both edges (MSHA 77.1605: axle high).
	for sd in [-1.0, 1.0]:
		var o: Vector2 = side * sd
		var e: Vector2 = o + along.orthogonal() * sd * 1.6
		_poly_into(_flat, PackedVector2Array([a + o, b + o, b + e, a + e]) if sd < 0.0 else PackedVector2Array([a + e, b + e, b + o, a + o]), 0.15, Color("#7f7563"), 1.0)


## Where a line along x at `z` crosses the mined ground, the plant yard
## left out: a list of (west, east) stretches.
func _spans(outlines: Array, z: float) -> Array:
	var out := []
	for o in outlines:
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(-1e5, z), Vector2(1e5, z)]), o):
			var a := minf(seg[0].x, seg[seg.size() - 1].x)
			var b := maxf(seg[0].x, seg[seg.size() - 1].x)
			if z > _plant_yard.position.y and z < _plant_yard.end.y:
				out.append_array([Vector2(a, minf(b, _plant_yard.position.x)), Vector2(maxf(a, _plant_yard.end.x), b)])
			else:
				out.append(Vector2(a, b))
	return out.filter(func(p): return p.y > p.x)


## The longest stretch (west, east) along x at `z`.
func _span(outlines: Array, z: float) -> Vector2:
	var best := Vector2(INF, -INF)
	for p in _spans(outlines, z):
		if p.y - p.x > best.y - best.x:
			best = p
	return best


## A polygon cut to the mined ground.
func _clip(outlines: Array, poly: PackedVector2Array) -> Array:
	var out := []
	var yard := PackedVector2Array([_plant_yard.position, Vector2(_plant_yard.end.x, _plant_yard.position.y), _plant_yard.end, Vector2(_plant_yard.position.x, _plant_yard.end.y)])
	for o in outlines:
		for part in Geometry2D.intersect_polygons(poly, o):
			if Geometry2D.is_polygon_clockwise(part):
				continue
			for piece in (Geometry2D.clip_polygons(part, yard) if _plant_yard.has_area() else [part]):
				if not Geometry2D.is_polygon_clockwise(piece):
					out.append(piece)
	return out


func _flat_clip(outlines: Array, poly: PackedVector2Array, y: float, col: Color) -> void:
	for part in _clip(outlines, poly):
		_poly_into(_flat, part, y, col, 1.0)


func _water_clip(outlines: Array, poly: PackedVector2Array, y: float) -> void:
	for part in _clip(outlines, poly):
		_poly_into(_water, part, y, Color.WHITE)
		_water_n += 1


## A flat polygon (x, z) at height `y`, facing up.
func _poly_into(st: SurfaceTool, poly: PackedVector2Array, y: float, col: Color, alpha := 1.0) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	col.a = alpha
	for t in range(0, tris.size(), 3):
		# Wound to face up, whichever way the outline runs.
		var order := [tris[t], tris[t + 1], tris[t + 2]]
		var a := poly[order[0]]
		if (poly[order[1]] - a).cross(poly[order[2]] - a) < 0.0:  # as _flat_rect: clockwise seen from above
			order = [tris[t], tris[t + 2], tris[t + 1]]
		for v in order:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.set_uv(poly[v] * 0.25)
			st.add_vertex(Vector3(poly[v].x, y, poly[v].y))
