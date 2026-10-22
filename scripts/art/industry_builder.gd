class_name IndustryBuilder
extends FarmBuilder
## Resource companies, built from the same realistic parts as the town.
## Benchmark: photos of Illinois Basin oil leases and Midwestern limestone
## quarries. (Forestry is ForestryBuilder's.)
##   - every company has a low metal-sided office with a gravel lot
##   - oil: beam pumpjacks on steel skids with a wellhead, and a tank battery
##     (welded tanks, catwalk, stairs) at the main yard
##   - ore: a stepped quarry pit with pale benches and a haul ramp, a crusher
##     house with an inclined conveyor feeding a stockpile
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
		"ore": b._crusher(Vector3(8, 0, 4))
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
