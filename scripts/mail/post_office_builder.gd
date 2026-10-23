class_name PostOfficeBuilder
extends HubBuilder
## Draws the post office over the land it has grown into, benchmarked
## against photos of real small-town Midwestern post offices:
##   - the 1930s Colonial Revival post office: one storey of red brick on a
##     limestone water table, a slate hip roof with a white cupola, tall
##     multi-pane windows, a white pedimented entry up a few steps, the
##     flagpole on the lawn and two blue collection boxes at the curb
##   - out back, a fenced carrier lot and a loading dock for the mail truck
##   - what the postmaster adds: a brick sorting room, a precast sorting
##     center with a row of truck docks, a steel parcel depot, a big
##     cross-dock ground hub, and more lot for the carriers
## Local space as HubBuilder: -z faces the road, z = 0 is the front edge of
## the land, piece (x, y) spans x*cell +- cell/2 across and y*cell..(y+1)*cell.

const PO_BRICK := ["#8a3f2e", "#9a4a34", "#7e3b2b", "#a35a3f"]
const LIMESTONE := Color("#cfc6b0")
const SLATE := Color("#4c4f55")
const USPS_BLUE := Color("#2b5797")
const PRECAST := Color("#c8bfae")
const STEEL := Color("#c4c7c6")

## Parking stalls for idle carriers, in local space ([pos, yaw]), filled in
## by build(): the view parks a vehicle in each free one.
var stalls := []


## [house mesh, ground mesh, trees, stalls].
static func build_office(h: Dictionary, seed: int, to_curb: float) -> Array:
	var b := PostOfficeBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.cells = h.cells
	b.cell = h.cell
	b._office(h, to_curb)
	for node in h.lands:
		if not h.lands[node].is_empty():
			b._annex(node, h.lands[node], Mail.done(h, node))
	b._fleet_lots(Mail.fleet_cells(h))
	return [b._commit_house(), b._commit_flat(), b.trees, b.stalls]


func _office(h: Dictionary, to_curb: float) -> void:
	var brick := Color(_pick(PO_BRICK))
	var w := 20.0
	var d := 14.0
	var zf := 9.0
	var wall := 5.2
	var cx := -4.0
	# Lawn in front, walk up to the door, the drive down the side.
	_flat_rect("drive", cx - 1.2, cx + 1.2, -to_curb + 0.4, zf - 1.6, 0.07)
	_flat_rect("drive", 14.0, 20.0, -to_curb, cell * 2.0 - 2.0, 0.08)
	# The building: brick on a limestone water table, a slate hip roof.
	_box("paint", Vector3(w + 0.3, 0.9, d + 0.3), Vector3(cx, 0.45, zf + d * 0.5), LIMESTONE)
	_box("brick", Vector3(w, wall - 0.9, d), Vector3(cx, 0.9 + (wall - 0.9) * 0.5, zf + d * 0.5), brick)
	_box("paint", Vector3(w + 0.4, 0.35, d + 0.4), Vector3(cx, wall + 0.1, zf + d * 0.5), Color("#ece8de"))
	_hip_roof(cx, zf + d * 0.5, wall + 0.25, w, d, 3.2, SLATE)
	# Cupola on the ridge.
	_box("paint", Vector3(1.8, 1.6, 1.8), Vector3(cx, wall + 3.2 + 0.6, zf + d * 0.5), Color("#f1eee6"))
	_box("paint", Vector3(2.2, 0.2, 2.2), Vector3(cx, wall + 3.2 + 1.5, zf + d * 0.5), Color("#e3dfd5"))
	_box("paint", Vector3(0.9, 1.1, 0.9), Vector3(cx, wall + 3.2 + 2.1, zf + d * 0.5), SLATE)
	_cyl_y(Vector3(cx, wall + 3.2 + 3.1, zf + d * 0.5), 0.04, 1.0, Color("#3a3a36"))
	# Tall twelve-over-twelve windows either side of the entry.
	var trim := Color("#f1eee6")
	_window_row(cx - 6.0, zf, 7.0, 2.9, 2.6, 2, trim)
	_window_row(cx + 6.0, zf, 7.0, 2.9, 2.6, 2, trim)
	for s in [-1.0, 1.0]:
		_window_row(cx + s * w * 0.5, zf + d * 0.45, d * 0.6, 2.9, 2.6, 3, trim, Vector3(s, 0, 0))
	# The entry: white pilasters and a pediment, steps down to the walk.
	_glass(Vector3(cx, 1.95, zf - 0.04), Vector3(-1, 0, 0), 1.8, 2.5, 0.0)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.45, 3.6, 0.3), Vector3(cx + s * 1.4, 2.4, zf - 0.15), trim)
	_box("paint", Vector3(3.6, 0.45, 0.4), Vector3(cx, 4.35, zf - 0.2), trim)
	var py := 4.6
	_quad("paint", Vector3(cx - 1.9, py, zf - 0.42), Vector3(cx + 1.9, py, zf - 0.42), Vector3(cx, py + 0.9, zf - 0.42),
		Vector3(cx, py + 0.9, zf - 0.42), trim, [], Vector3.FORWARD)
	for i in 3:
		_box("paint", Vector3(4.0 - i * 0.4, 0.18, 0.4), Vector3(cx, 0.09 + i * 0.18, zf - 1.4 + i * 0.4), LIMESTONE)
	# "UNITED STATES POST OFFICE" across the frieze.
	_box("paint", Vector3(10.0, 0.42, 0.05), Vector3(cx, wall - 0.45, zf - 0.04), Color("#e7e1d2"))
	_flagpole(Vector3(cx - 7.0, 0, 4.0))
	_bed(cx - 4.0, zf - 0.9, 3.0)
	_bed(cx + 4.0, zf - 0.9, 3.0)
	# Two blue collection boxes at the curb by the walk.
	for i in 2:
		var p := Vector3(cx + 2.2 + i * 0.8, 0, -to_curb + 1.0)
		_box("paint", Vector3(0.53, 1.0, 0.5), p + Vector3(0, 0.62, 0), USPS_BLUE)
		_cyl_y(p + Vector3(0, 1.12, 0), 0.25, 0.04, USPS_BLUE)
		for lx in [-0.2, 0.2]:
			_box("paint", Vector3(0.06, 0.15, 0.06), p + Vector3(lx, 0.07, 0), Color("#2a2c2e"))
	# Out back: the dock for the mail truck and the carrier lot.
	var back := zf + d
	_box("paint", Vector3(8.0, 1.2, 3.0), Vector3(cx + 4.0, 0.6, back + 1.5), Color("#a8a49c"))
	_overhead_door(cx + 4.0, back, 3.0, 3.2, Color("#d9d6cf"), true)
	_box("paint", Vector3(9.0, 0.25, 3.6), Vector3(cx + 4.0, 4.0, back + 1.8), Color("#e3dfd5"))
	_flat_rect("asphalt", -cell * 1.5 + 2.0, cell * 1.5 - 2.0, back + 0.5, cell * 2.0 - 2.0, 0.06)
	_stall_row(-cell * 1.5 + 4.0, cx - 2.0, cell * 2.0 - 2.5, PI)
	_fence(Vector2(-cell * 1.5 + 1.5, back + 0.5), Vector2(cell * 1.5 - 1.5, cell * 2.0 - 1.5), 1.8)


## A row of carrier stalls along z = zb (vehicles face +z when yaw = 0).
func _stall_row(x0: float, x1: float, zb: float, yaw: float) -> void:
	var x := x0
	while x <= x1 - 2.6:
		_flat_rect("line", x - 0.06, x + 0.06, zb - 5.5, zb, 0.07, LINE)
		stalls.append([Vector3(x + 1.3, 0.0, zb - 0.6), yaw])
		x += 2.7


## Pieces of carrier lot the office grew: asphalt with two rows of stalls.
func _fleet_lots(set: Array) -> void:
	for c in set:
		var x0: float = c.x * cell - cell * 0.5 + 1.5
		var z0: float = c.y * cell + 1.5
		_flat_rect("asphalt", x0, x0 + cell - 3.0, z0, z0 + cell - 3.0, 0.06)
		_stall_row(x0 + 0.5, x0 + cell - 3.0, z0 + 6.0, PI)
		_stall_row(x0 + 0.5, x0 + cell - 3.0, z0 + cell - 3.5, 0.0)


## The building a tree node put on its land, filling its pieces wall to wall.
func _annex(node: String, set: Array, done: bool) -> void:
	var spec := {
		"sorting_room": ["brick", Color(_pick(PO_BRICK)), 5.5, 2],
		"sorting_center": ["siding", PRECAST, 9.0, 6],
		"regional_hub": ["siding", PRECAST, 11.0, 8],
		"parcel_depot": ["metal", STEEL, 7.5, 4],
		"parcel_ground_hub": ["metal", Color("#b9bdbd"), 10.0, 10],
		"business_mail": ["siding", Color("#bdb6a6"), 6.0, 2],
		"rail_mail": ["metal", Color("#9fa4a4"), 6.5, 1],
	}
	if not spec.has(node):
		_fleet_lots(set)  # vans and their lot
		return
	var s: Array = spec[node]
	var h: float = s[2] if done else 0.6  # a slab while it's being built
	for c in set:
		var hc := cell * 0.5
		var x0: float = c.x * cell - hc + (0.0 if (c + Vector2i(-1, 0)) in set else 3.0)
		var x1: float = c.x * cell + hc - (0.0 if (c + Vector2i(1, 0)) in set else 3.0)
		var z0: float = c.y * cell + (0.0 if (c + Vector2i(0, -1)) in set else 3.0)
		var z1: float = c.y * cell + cell - (0.0 if (c + Vector2i(0, 1)) in set else 6.0)
		_flat_rect("asphalt", c.x * cell - hc + 1.0, c.x * cell + hc - 1.0, c.y * cell + 1.0, c.y * cell + cell - 1.0, 0.05)
		if not done:
			_box("paint", Vector3(x1 - x0, 0.3, z1 - z0), Vector3((x0 + x1) * 0.5, 0.15, (z0 + z1) * 0.5), CONCRETE)
			continue
		_box(s[0], Vector3(x1 - x0, h, z1 - z0), Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5), s[1])
		_quad("paint", Vector3(x0, h + 0.02, z0), Vector3(x1, h + 0.02, z0), Vector3(x1, h + 0.02, z1),
			Vector3(x0, h + 0.02, z1), Color("#bdbbb4"), [], Vector3.UP)
		# Dock doors on the back wall where it faces the yard.
		if not (c + Vector2i(0, 1)) in set:
			var n := maxi(1, int(s[3] / maxf(set.size(), 1.0) + 0.5))
			for i in n:
				var x := lerpf(x0, x1, (i + 0.5) / n)
				_overhead_door(x, z1, 2.8, 3.0, Color("#e2dfd8"), true)
				_box("paint", Vector3(3.2, 1.2, 0.4), Vector3(x, 0.6, z1 + 0.2), Color("#2d2e30"))
