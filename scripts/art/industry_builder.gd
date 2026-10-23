class_name IndustryBuilder
extends FarmBuilder
## Resource companies, built from the same realistic parts as the town.
## Benchmark: photos of Illinois Basin oil leases and Midwestern limestone
## quarries. (Forestry is ForestryBuilder's.)
##   - every company has a low metal-sided office with a gravel lot
##   - oil: beam pumpjacks on steel skids with a wellhead, and a tank battery
##     (welded tanks, catwalk, stairs) at the main yard
##   - ore: one crushed-limestone quarry for the whole company, however many
##     pads it has opened: rounded benches stepping down to a wet floor, a
##     haul ramp cut across them, an overburden berm round the rim, haul
##     trucks, and a crusher house feeding a row of graded stone stockpiles
## Local space: the company faces -z, like FarmView's farmsteads.

const OFFICE_WALL := ["#d8d6cf", "#c9cbc8", "#b9b4a6", "#c2b59b"]
const TANK := ["#b9a57e", "#c8c2b2", "#7d8a74", "#9a9fa2"]
const JACK := ["#3d4a3f", "#5b6066", "#2f3a46", "#6b5a2a"]
const QUARRY := Color("#c8c1b0")  # limestone


## [mesh, ground mesh] for a company's main yard.
static func build_hq(kind: String, seed: int) -> Array:
	var b := IndustryBuilder.new()
	b._begin(seed)
	b._flat_rect("gravel", -20, 20, -20, 20, 0.09, YARD_GRAVEL)
	b._office(-8.0, -10.0)
	match kind:
		"oil": b._tank_battery(Vector3(10, 0, 6))
		"ore":
			b._crusher(Vector3(8, 0, 4))
			# Graded stone: #57s, #8s, #53 base and screenings, each its own pile.
			b._flat_rect("gravel", -28, 34, 20, 36, 0.09, YARD_GRAVEL)
			for i in 4:
				var shade := Color("#bdb6a5").darkened(i * 0.05)
				b._cone(Vector3(-20.0 + i * 15.0, 0, 28.0), 6.5, 5.0, shade, 16, "paint")
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


## A crusher house: a tall metal building, an inclined conveyor on legs and
## the crushed-stone stockpile it feeds.
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
	_cone(pile, 9.0, 7.0, Color("#bdb6a5"), 18, "paint")


## The company's quarry as one pit over every pad it has opened, in the
## company's local frame. `cells` are the pads' centres; `toward` is the
## main yard, where the haul ramp climbs out.
## Real limestone quarries are one hole that grows outward bench by bench:
## near-vertical faces about 12 m high, 10 m benches, rounded corners, a
## ramp cut down across the benches, rain water on the floor and a berm of
## stripped overburden round the rim. Faces are shaded by the way they
## face, so the steps read as depth from above.
static func build_quarry(seed: int, cells: Array, pad: float, toward: Vector2) -> Array:
	var b := IndustryBuilder.new()
	b._begin(seed)
	b._quarry(cells, pad, toward)
	var ground := b._commit_flat()
	b._pit_st.commit(ground)
	ground.surface_set_material(ground.get_surface_count() - 1, Surfaces.quarry())
	return [b._commit_house(), ground]


var _pit_st: SurfaceTool


const BENCH := 10.0   # bench width in plan
const FACE := 5.0     # a 12 m face at about 70 degrees, seen from above
const RIM := 6.0      # the pit edge stands this far inside the pads
const LEVELS := 5
const ROUND := 10.0   # corner rounding


func _quarry(cells: Array, pad: float, toward: Vector2) -> void:
	var occupied := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in cells:
		var v: Vector2 = c
		occupied[Vector2i(roundi(v.x / pad), roundi(v.y / pad))] = true
		lo = lo.min(v)
		hi = hi.max(v)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / 110.0
	var half := pad * 0.5
	# Signed distance to the edge of the pads (negative inside), with rounded
	# corners: a soft minimum over the nearest pads or open cells.
	var dist := func(p: Vector2) -> float:
		var ci := Vector2i(roundi(p.x / pad), roundi(p.y / pad))
		var inside: bool = occupied.has(ci)
		var acc := 0.0
		for dj in range(-2, 3):
			for di in range(-2, 3):
				var n := ci + Vector2i(di, dj)
				if occupied.has(n) == inside:
					continue
				var q := (p - Vector2(n) * pad).abs() - Vector2(half, half)
				acc += exp(-Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() / ROUND)
		var d := -ROUND * log(acc) if acc > 0.0 else 3.0 * pad
		return -d if inside else d
	var step := 2.5
	var x0 := lo.x - half - 24.0
	var z0 := lo.y - half - 24.0
	var nx := ceili((hi.x - lo.x + pad + 48.0) / step)
	var nz := ceili((hi.y - lo.y + pad + 48.0) / step)
	var s_at := PackedFloat32Array()
	s_at.resize((nx + 1) * (nz + 1))
	var deepest := 0.0
	for j in nz + 1:
		for i in nx + 1:
			var p := Vector2(x0 + i * step, z0 + j * step)
			# How far into the pit from its rim, with a wandering edge.
			var sv: float = -dist.call(p) - RIM + noise.get_noise_2dv(p) * 4.0
			s_at[j * (nx + 1) + i] = sv
			deepest = maxf(deepest, sv)
	var floor_at := minf(LEVELS * (BENCH + FACE), deepest - 12.0)
	# The ramp: from the main yard straight in across the benches.
	var mid := (lo + hi) * 0.5
	var ramp_dir := (mid - toward).normalized() if mid.distance_to(toward) > 1.0 else Vector2(0, 1)
	var across := Vector2(-ramp_dir.y, ramp_dir.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert := func(x: float, z: float, sv: float) -> void:
		var p := Vector2(x, z)
		var along := (p - toward).dot(ramp_dir)
		var off := absf((p - toward).dot(across)) / 14.0 if along > 0.0 else 1.0
		var y := 0.1
		if sv > -9.0 and sv < 0.0 and off >= 0.5:
			y += sin((sv + 9.0) / 9.0 * PI) * 2.0  # the berm, about 2 m high
		st.set_normal(Vector3.UP)
		st.set_color(Color(clampf(floor_at / 100.0, 0.0, 1.0), clampf(off, 0.0, 1.0), 0.0, 1.0))
		st.set_uv(Vector2(sv, 0.0))
		st.add_vertex(Vector3(x, y, z))
	for j in nz:
		for i in nx:
			var k := j * (nx + 1) + i
			var quad := [k, k + 1, k + nx + 2, k + nx + 1]
			var any := false
			for q in quad:
				any = any or s_at[q] >= -9.0
			if not any:
				continue
			for t in [0, 1, 2, 0, 2, 3]:
				var q: int = quad[t]
				vert.call(x0 + (q % (nx + 1)) * step, z0 + (q / (nx + 1)) * step, s_at[q])
	# The haul road from the yard out to the rim.
	var reach := 0.0
	while reach < 400.0:
		var q := toward + ramp_dir * reach
		var qi := clampi(roundi((q.x - x0) / step), 0, nx)
		var qj := clampi(roundi((q.y - z0) / step), 0, nz)
		if s_at[qj * (nx + 1) + qi] >= -9.0:
			break
		reach += step
	if reach > 0.0:
		var e := toward + ramp_dir * (reach + step)
		var side := across * 6.0
		var quad := [toward - side, toward + side, e + side, e - side]
		if (quad[1] - quad[0]).cross(quad[2] - quad[0]) < 0.0:
			quad.reverse()
		for t in [0, 1, 2, 0, 2, 3]:
			var v: Vector2 = quad[t]
			st.set_normal(Vector3.UP)
			st.set_color(Color(clampf(floor_at / 100.0, 0.0, 1.0), 0.0, 0.0, 1.0))
			st.set_uv(Vector2(-5.0, 0.0))
			st.add_vertex(Vector3(v.x, 0.11, v.y))
	_pit_st = st
	# Two haul trucks and a front loader working the floor.
	var floor_pts := []
	for j in range(0, nz + 1, 4):
		for i in range(0, nx + 1, 4):
			if s_at[j * (nx + 1) + i] > deepest - 10.0:
				floor_pts.append(Vector3(x0 + i * step, 0, z0 + j * step))
	if not floor_pts.is_empty():
		var at: Vector3 = floor_pts[rng.randi() % floor_pts.size()]
		_haul_truck(at, rng.randf() * TAU)
		_haul_truck(at + Vector3(14, 0, 6), rng.randf() * TAU)
		_box("paint", Vector3(3.2, 3.2, 7.5), at + Vector3(4, 1.8, -10), Color("#d9a521"))
		_box("paint", Vector3(4.2, 1.6, 2.2), at + Vector3(4, 1.4, -14.6), Color("#5b5b55"))


## A rigid-frame haul truck (a Cat 777 is about 10 x 6 m, 4.5 m tall).
func _haul_truck(at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var yellow := Color("#d9a521")
	_box("paint", Vector3(6.0, 2.2, 6.4), at + b * Vector3(0, 3.0, 1.2), yellow, b)  # dump body
	_box("paint", Vector3(5.0, 2.4, 3.0), at + b * Vector3(0, 2.6, -3.6), yellow, b)  # cab deck
	_box("paint", Vector3(1.6, 1.4, 1.6), at + b * Vector3(-1.4, 4.4, -3.8), Color("#2b2f33"), b)  # cab
	for wz in [-3.6, 2.6]:
		for wx in [-2.6, 2.6]:
			_box("paint", Vector3(0.9, 2.6, 2.6), at + b * Vector3(wx, 1.3, wz), Color("#1e1e1e"), b)
