class_name CampusBuilder
extends CivicBuilder
## Campus buildings, benchmarked against photos of real Midwestern schools:
##   - the consolidated high school: a long two-storey brick front with a
##     glass entry, a taller gym, a bus loop and a flagpole; later a
##     football stadium with home bleachers and a press box, practice
##     fields, and more classroom wings
##   - the community college: low brick-and-glass buildings among big lots
##   - the regional university: a three-storey "Old Main" with a clock
##     tower, brick halls around green quads, a columned library, dorms
##     and a stadium
## Boxed in by roads (edge pieces, Education/BlockEdges), a campus runs up
## to the sidewalk: front lawn with rows of shade trees along its street,
## student parking edged with trees behind, never another building.
## Local space: one 120 m block centred on 0, -z toward the street side of
## the campus. `to_curb` is how far the curb lies in front of a first
## building (0 for blocks further back).

const S := Education.CELL * 0.5
const LIMESTONE := Color("#d8cfb8")  # Indiana limestone trim
const TURF := Color("#4f7a34")
const TRACK := Color("#9b4a36")


## [building mesh, ground mesh, trees] for the campus's first building.
static func build_main(kind: String, seed: int, to_curb: float) -> Array:
	var b := _start(seed)
	match kind:
		"high_school": b._high_school(to_curb)
		"college": b._college(to_curb)
		_: b._old_main(to_curb)
	b.half = 60.0
	b.depth = 60.0
	b._dress(false, true)
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels]


## The same for one block of campus, built up `levels` times.
static func build_block(use: String, levels: int, seed: int) -> Array:
	var b := _start(seed)
	match use:
		"gym": b._gym()
		"fields": b._fields()
		"stadium": b._stadium()
		"parking": b._lot()
		"quad": b._quad_lawn()
		"library": b._library(levels)
		"dorm": b._dorm(levels)
		_: b._hall_block(levels, use in ["lab", "tech"])
	b.half = 60.0
	b.depth = 60.0
	b._dress(false, true)
	return [b._commit_house(), b._commit_flat(), b.trees]


## [things, ground mesh, trees] for a campus's edge pieces (`edge`: block
## -> outline in CivicHubs' frame, z = 0 at its first block's front edge,
## -z toward the street).
static func build_edge(edge: Dictionary, seed: int) -> Array:
	var b := _start(seed)
	for c in edge:
		var poly: PackedVector2Array = edge[c]
		EdgeGrounds.ground(b, "mulch", poly, 0.04, TURF)
		var lot := HubBuilder._inset(poly, 5.0)
		if c.y > 0 and lot.size() >= 3 and CivicHubs.area(lot) >= 700.0 and HubBuilder._bounds(lot).size.y >= 18.0:
			# Student parking, shade trees in the lawn round it.
			EdgeGrounds.parking(b, lot)
			EdgeGrounds.back_drive(b, lot, poly, c, Education.CELL)
			EdgeGrounds.trees(b, poly, 12.0, 2.0, false, [HubBuilder._inset(poly, 3.5)])
			continue
		# Front lawn (or a strip too thin for a lot): shade trees in rows.
		EdgeGrounds.trees(b, poly, 14.0, 4.0)
	return [b._commit_house(), b._commit_flat(), b.trees]


static func _start(seed: int) -> CampusBuilder:
	var b := CampusBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	return b


func _brick() -> Color:
	return Color(_pick(["#8a4a38", "#9b5a42", "#7a4234", "#a8775c"]))


## A flat-roofed brick building with punched windows on every floor, front
## and back. `glassy` gives a modern curtain-wall entry bay.
func _hall(cx: float, zf: float, w: float, d: float, floors: int, brick: Color, glassy := false) -> void:
	var fh := 4.0
	var h := floors * fh + 0.4
	_slab(cx, w, zf, d)
	_flat_roofed_at("brick", cx, w, d, zf + d * 0.5, h, h + 0.7, brick)
	for f in floors:
		var y := f * fh + 2.2
		var n := int(w / 3.6)
		_window_row(cx, zf, w - 3.0, y, 1.6, n, LIMESTONE)
		_window_row(cx, zf + d, w - 3.0, y, 1.6, n, LIMESTONE, Vector3.BACK)
		_window_row(cx - w * 0.5, zf + d * 0.5, d - 3.0, y, 1.6, int(d / 3.6), LIMESTONE, Vector3.LEFT)
		_window_row(cx + w * 0.5, zf + d * 0.5, d - 3.0, y, 1.6, int(d / 3.6), LIMESTONE, Vector3.RIGHT)
		_box("paint", Vector3(w + 0.1, 0.25, 0.12), Vector3(cx, f * fh + 0.3, zf - 0.06), LIMESTONE)
	if glassy:
		var gw := minf(12.0, w * 0.3)
		for f in floors:
			for i in int(gw / 2.0):
				_glass(Vector3(cx - gw * 0.5 + 1.0 + i * 2.0, f * fh + 2.0, zf - 0.08), Vector3(-1, 0, 0), 1.9, 3.4, 0.0)
	_rooftop_units(cx, w * 0.8, zf, d, h, maxi(1, int(w / 18.0)))


func _walk(x0: float, x1: float, z0: float, z1: float) -> void:
	_flat_rect("asphalt", x0, x1, z0, z1, 0.07, Color("#c9c4b8"))


func _tree_row(x0: float, x1: float, z: float, step: float, front := false) -> void:
	var x := x0
	while x <= x1:
		var pick := TreeField.pick(rng, front)
		trees.append([Vector3(x + rng.randf_range(-1.0, 1.0), 0, z + rng.randf_range(-1.0, 1.0)), pick[0], pick[1],
			rng.randf_range(0.85, 1.15)])
		x += step


# ---------------------------------------------------------------- first buildings

func _high_school(to_curb: float) -> void:
	var brick := _brick()
	var front := -S
	# Two-storey classroom front along the street, a gym behind one end.
	var zf := front + 34.0
	_hall(0.0, zf, 86.0, 20.0, 2, brick)
	_hall(-30.0, zf + 20.0, 22.0, 40.0, 2, brick)
	_slab(22.0, 40.0, zf + 20.0, 34.0)
	_flat_roofed_at("brick", 22.0, 40.0, 34.0, zf + 37.0, 11.0, 11.8, brick)
	# Glass entry with the school's sign over a flat canopy.
	_vestibule(0.0, zf, 10.0, 4.0, 4.0)
	_box("paint", Vector3(14.0, 0.45, 7.0), Vector3(0.0, 4.4, zf - 5.5), LIMESTONE)
	_civic_sign(Vector3(0.0, 6.0, zf - 0.1), 12.0, 1.0, "HIGH SCHOOL", "#5a1f24", "#f2efe6", "serif")
	# Bus loop and the walk up to the doors; staff parking to one side.
	_flat_rect("asphalt", -50.0, 50.0, front + 6.0, front + 16.0, 0.06)
	for x in [-50.0, 43.0]:
		_flat_rect("asphalt", x, x + 7.0, front - to_curb, front + 6.0, 0.1)
	_walk(-3.0, 3.0, front + 16.0, zf - 4.0)
	_parking(-58.0, -12.0, front + 18.0, zf - 2.0, 0.0, -35.0)
	_flagpole(Vector3(10.0, 0, front + 22.0))
	_tree_row(16.0, 56.0, front + 22.0, 8.0, true)


func _college(to_curb: float) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38"]))
	var front := -S
	var zf := front + 50.0
	_hall(0.0, zf, 70.0, 26.0, 2, brick, true)
	_hall(26.0, zf + 26.0, 18.0, 34.0, 1, brick)
	_vestibule(0.0, zf, 12.0, 4.0, 4.5)
	_civic_sign(Vector3(0.0, 8.6, zf - 0.1), 14.0, 1.0, "COMMUNITY COLLEGE", "#1f3b6e", "#f2efe6", "serif")
	# Commuter college: the parking comes first.
	_parking(-56.0, 56.0, front + 4.0, zf - 4.0, to_curb, -40.0)
	_flat_rect("asphalt", 40.0, 47.0, front - to_curb, front + 4.0, 0.1)
	_walk(-3.0, 3.0, front + 20.0, zf - 4.0)
	_flagpole(Vector3(-10.0, 0, zf - 8.0))
	_tree_row(-50.0, -10.0, zf + 34.0, 9.0)


## "Old Main": a three-storey brick hall with limestone trim and a clock
## tower, set back behind a lawn with a walk up the middle.
func _old_main(to_curb: float) -> void:
	var brick := Color(_pick(["#8a4a38", "#7a4234", "#9b5a42"]))
	var front := -S
	var zf := front + 46.0
	var w := 64.0
	var d := 22.0
	_slab(0.0, w, zf, d)
	_box("brick", Vector3(w, 13.0, d), Vector3(0, 6.5, zf + d * 0.5), brick)
	_gable_roof(0.0, zf + d * 0.5, 13.0, d + 0.6, 5.5, w + 0.8, true, Color("#5c5c5e"), brick)
	for f in 3:
		_window_row(0.0, zf, w - 6.0, f * 4.2 + 2.4, 2.0, 14, LIMESTONE)
		_window_row(0.0, zf + d, w - 6.0, f * 4.2 + 2.4, 2.0, 14, LIMESTONE, Vector3.BACK)
	_box("paint", Vector3(w + 0.2, 0.5, d + 0.2), Vector3(0, 0.8, zf + d * 0.5), LIMESTONE)
	# The tower over the entry, with a clock face and a pyramid cap.
	_box("brick", Vector3(8.0, 26.0, 8.0), Vector3(0, 13.0, zf - 1.0), brick)
	_box("paint", Vector3(8.4, 0.5, 8.4), Vector3(0, 26.2, zf - 1.0), LIMESTONE)
	_box("paint", Vector3(3.6, 3.6, 0.1), Vector3(0, 21.0, zf - 5.03), Color("#efede6"))
	_hip_roof(0.0, zf - 1.0, 26.4, 8.4, 8.4, 5.0, Color("#3f4a46"))
	_box("paint", Vector3(4.0, 3.2, 0.2), Vector3(0, 1.6, zf - 5.1), Color("#3a2a20"))
	# Lawn, walk and a ring of old trees.
	_walk(-2.5, 2.5, front - to_curb, zf - 5.0)
	_walk(-28.0, 28.0, zf - 12.0, zf - 9.0)
	_flagpole(Vector3(-8.0, 0, front + 12.0))
	_tree_row(-52.0, -12.0, front + 10.0, 10.0)
	_tree_row(12.0, 52.0, front + 10.0, 10.0)
	_tree_row(-50.0, 50.0, zf + d + 14.0, 12.5)


# ---------------------------------------------------------------- blocks

func _hall_block(levels: int, glassy: bool) -> void:
	var brick := _brick()
	var floors := 1 + levels
	_hall(0.0, -30.0, 70.0, 22.0, floors, brick, glassy)
	_hall(-24.0, -8.0, 22.0, 32.0, floors, brick)
	_walk(-60.0, 60.0, -46.0, -43.0)
	_walk(-2.0, 2.0, -43.0, -30.0)
	_tree_row(10.0, 50.0, 18.0, 10.0)
	_tree_row(-50.0, 50.0, -52.0, 12.5)


func _library(levels: int) -> void:
	var brick := _brick()
	var floors := 2 + levels
	var zf := -28.0
	_hall(0.0, zf, 56.0, 34.0, floors, brick)
	# A limestone portico: six columns under a plain pediment band.
	var h := floors * 4.0 + 0.4
	for i in 6:
		_cylinder("paint", Vector3(-12.5 + i * 5.0, 0.3, zf - 4.5), 0.55, h - 1.6, LIMESTONE, 12)
	_box("paint", Vector3(30.0, 1.4, 5.5), Vector3(0, h - 0.6, zf - 2.75), LIMESTONE)
	_box("paint", Vector3(30.0, 0.6, 6.5), Vector3(0, 0.3, zf - 3.0), LIMESTONE)
	_walk(-2.5, 2.5, -S, zf - 6.0)
	_tree_row(-50.0, -36.0, -40.0, 7.0)
	_tree_row(36.0, 50.0, -40.0, 7.0)


func _dorm(levels: int) -> void:
	var brick := _brick()
	var floors := 3 + levels
	_hall(-20.0, -40.0, 18.0, 70.0, floors, brick)
	_hall(20.0, -40.0, 18.0, 70.0, floors, brick)
	_walk(-11.0, 11.0, -10.0, -6.0)
	_parking(-55.0, 55.0, 34.0, 52.0, 0.0, 0.0)
	_tree_row(-6.0, 6.0, -30.0, 6.0)


func _gym() -> void:
	var brick := _brick()
	_slab(0.0, 54.0, -30.0, 44.0)
	_flat_roofed_at("brick", 0.0, 54.0, 44.0, -8.0, 12.5, 13.3, brick)
	_box("paint", Vector3(54.2, 0.3, 0.2), Vector3(0, 9.0, -30.1), LIMESTONE)
	_entry(0.0, -30.0, LIMESTONE)
	_rooftop_units(0.0, 40.0, -30.0, 44.0, 12.5, 3)
	_parking(-56.0, 56.0, 20.0, 50.0, 0.0, 0.0)


## Practice fields: two soccer-size grass fields with goals.
func _fields() -> void:
	for z in [-28.0, 28.0]:
		_flat_rect("mulch", -50.0, 50.0, z - 24.0, z + 24.0, 0.05, TURF)
		_flat_rect("line", -0.08, 0.08, z - 24.0, z + 24.0, 0.06, LINE)
		for sx in [-1.0, 1.0]:
			_flat_rect("line", sx * 50.0 - 0.08, sx * 50.0 + 0.08, z - 24.0, z + 24.0, 0.06, LINE)
			var gx: float = sx * 50.5
			for gz in [-3.6, 3.6]:
				_box("paint", Vector3(0.12, 2.4, 0.12), Vector3(gx, 1.2, z + gz), WHITE)
			_box("paint", Vector3(0.12, 0.12, 7.3), Vector3(gx, 2.4, z), WHITE)


## A football stadium: a 120-yard turf field with yard lines, home
## bleachers with a press box, light poles and a scoreboard.
func _stadium() -> void:
	var lx := 54.9  # half of 120 yards
	var lz := 24.4  # half of 53 1/3 yards
	var cz := 6.0
	_flat_rect("mulch", -58.0, 58.0, cz - lz - 4.0, cz + lz + 4.0, 0.05, TURF.darkened(0.1))
	_flat_rect("mulch", -lx, lx, cz - lz, cz + lz, 0.055, TURF)
	for i in 21:
		var x := -45.7 + i * 4.57
		_flat_rect("line", x - 0.08, x + 0.08, cz - lz, cz + lz, 0.06, LINE)
	for sx in [-1.0, 1.0]:
		_flat_rect("mulch", sx * 45.7, sx * lx, cz - lz, cz + lz, 0.057, Color("#7a1f1f") if sx < 0.0 else Color("#1f3b6e"))
		_box("paint", Vector3(0.2, 6.0, 0.2), Vector3(sx * (lx + 0.5), 3.0, cz), Color("#e6c84a"))
		_box("paint", Vector3(0.2, 0.2, 5.6), Vector3(sx * (lx + 0.5), 3.0, cz), Color("#e6c84a"))
	# Home bleachers on the far side, rising in rows, and the press box.
	for r in 10:
		_box("paint", Vector3(70.0, 0.45, 0.9), Vector3(0, 0.5 + r * 0.45, cz + lz + 6.0 + r * 0.9), GALV)
	_box("siding", Vector3(18.0, 3.2, 4.0), Vector3(0, 7.5, cz + lz + 12.0), Color("#c9cbc8"))
	_glass(Vector3(0, 7.8, cz + lz + 9.98), Vector3(-1, 0, 0), 16.0, 1.5, 0.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 40.0, 0, cz + sz * (lz + 8.0))
			_box("paint", Vector3(0.5, 22.0, 0.5), p + Vector3(0, 11.0, 0), GALV)
			_box("paint", Vector3(4.0, 2.0, 0.6), p + Vector3(0, 22.0, 0), DARK)
	_box("paint", Vector3(10.0, 4.0, 0.6), Vector3(-lx - 2.5, 7.0, cz), DARK, Basis(Vector3.UP, PI * 0.5))
	_box("paint", Vector3(0.4, 5.0, 0.4), Vector3(-lx - 2.5, 2.5, cz), GALV)


func _lot() -> void:
	_parking(-56.0, 56.0, -52.0, -4.0, 0.0, 0.0)
	_parking(-56.0, 56.0, 4.0, 52.0, 0.0, 0.0)
	_flat_rect("asphalt", -56.0, 56.0, -4.0, 4.0, 0.06)
	_tree_row(-52.0, 52.0, 0.0, 13.0)


## A green quad crossed by diagonal walks, lined with trees.
func _quad_lawn() -> void:
	_walk(-2.0, 2.0, -S, S)
	_walk(-S, S, -2.0, 2.0)
	for sx in [-1.0, 1.0]:
		_tree_row(-50.0, 50.0, sx * 50.0, 10.0)
	for sz in [-1.0, 1.0]:
		for i in 4:
			var pick := TreeField.pick(rng)
			trees.append([Vector3(sz * (12.0 + i * 10.0), 0, sz * 18.0 * (1 if i % 2 == 0 else -1)), pick[0], pick[1],
				rng.randf_range(0.9, 1.2)])
	_box("paint", Vector3(3.0, 0.6, 3.0), Vector3(0, 0.3, 0), LIMESTONE)
	_box("paint", Vector3(1.0, 2.6, 1.0), Vector3(0, 1.9, 0), Color("#5a5d55"))
