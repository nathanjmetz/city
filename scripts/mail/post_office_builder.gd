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
##   - boxed in by roads (edge pieces, Mail), it runs up to the sidewalk:
##     lawn and shade trees along the front street, more fenced carrier lot
##     elsewhere, never a building
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
	b.edge_land = h.get("edge", {})
	b._office(h, to_curb)
	for node in h.lands:
		if not h.lands[node].is_empty():
			b._annex(node, h.lands[node], Mail.done(h, node))
	b._fleet_lots(Mail.fleet_cells(h))
	b._edge_lots()
	b._counter_and_fleet(h)
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


## The counter steps and the electric fleet, as they show from outside
## (Mail.TREE).
func _counter_and_fleet(h: Dictionary) -> void:
	var cx := -4.0
	var zf := 9.0
	if Mail.done(h, "po_boxes"):
		# The 24-hour box lobby: a glass vestibule on the side of the
		# building with its own door and lettering, open after hours.
		var v := Vector3(cx - 11.6, 0, zf + 3.5)
		_box("paint", Vector3(3.4, 0.3, 3.4), v + Vector3(0, 0.15, 0), LIMESTONE)
		for q in [[Vector3(-1.6, 0, 0), Vector3(0, 0, 1), 3.0], [Vector3(0, 0, -1.6), Vector3(-1, 0, 0), 3.0],
				[Vector3(0, 0, 1.6), Vector3(1, 0, 0), 3.0]]:
			_glass(v + q[0] + Vector3(0, 1.75, 0), q[1], q[2], 2.6, 0.0)
		_box("paint", Vector3(3.4, 0.4, 3.4), v + Vector3(0, 3.2, 0), Color("#f1eee6"))
		_box("paint", Vector3(1.6, 0.25, 0.04), v + Vector3(0, 2.75, -1.72), Color("#f1eee6"))
		_box("paint", Vector3(2.6, 2.1, 0.4), v + Vector3(0.0, 1.35, 1.2), Color("#b08d57"))  # the brass boxes
		if Mail.done(h, "kiosk"):
			# The self-service kiosk stands in the lobby, by the glass.
			_box("paint", Vector3(0.8, 1.6, 0.6), v + Vector3(-0.9, 1.1, -0.6), USPS_BLUE)
			_box("paint", Vector3(0.5, 0.35, 0.03), v + Vector3(-0.9, 1.5, -0.92), Color("#20262c"))
	if Mail.done(h, "passports"):
		# "Passport Acceptance Facility": the placard beside the door.
		_box("paint", Vector3(0.6, 0.45, 0.04), Vector3(cx + 2.4, 1.7, zf - 0.08), USPS_BLUE)
		_box("paint", Vector3(0.44, 0.08, 0.02), Vector3(cx + 2.4, 1.8, zf - 0.1), Color("#f1eee6"))
	if Mail.done(h, "mural"):
		# The county's mural on the blank back wall by the carrier lot, where
		# the town sees it (the 1930s Section of Fine Arts style: farms,
		# the river, sky).
		var z := zf + 14.04
		var mx := cx - 5.5
		for band in [[1.2, 0.9, Color("#5b7d3a")], [2.1, 0.5, Color("#4f7f9a")], [2.6, 0.9, Color("#c9a65a")],
				[3.5, 1.0, Color("#9fc0d4")]]:
			_box("paint", Vector3(7.6, band[1], 0.04), Vector3(mx, band[0] + band[1] * 0.5, z), band[2])
		_box("paint", Vector3(0.8, 1.6, 0.05), Vector3(mx - 1.8, 2.6, z + 0.01), Color("#7a3b2c"))
		_box("paint", Vector3(2.2, 0.5, 0.05), Vector3(mx + 2.0, 3.1, z + 0.01), Color("#3f5a2a"))
		for y in [1.14, 4.56]:
			_box("paint", Vector3(8.0, 0.12, 0.06), Vector3(mx, y, z), Color("#f1eee6"))
	if Mail.done(h, "electric_fleet"):
		# Chargers for the electric carrier trucks: a pedestal at the head
		# of every other stall, and the switchgear by the dock.
		var i := 0
		for st in stalls:
			if i % 2 == 0:
				var p: Vector3 = st[0]
				_box("paint", Vector3(0.45, 0.12, 0.45), p + Vector3(1.35, 0.06, 1.0), CONCRETE)
				_box("paint", Vector3(0.4, 1.5, 0.3), p + Vector3(1.35, 0.85, 1.0), Color("#e4e6e3"))
				_box("paint", Vector3(0.25, 0.25, 0.03), p + Vector3(1.35, 1.2, 0.84), USPS_BLUE)
			i += 1
		_box("paint", Vector3(2.4, 1.8, 0.9), Vector3(cx - 4.0, 0.9, zf + 15.0), Color("#c4c7c6"))
	if Mail.done(h, "air_mail") and h.lands.has("regional_hub") and not h.lands.regional_hub.is_empty():
		# Overnight air mail goes out in LD3 air cargo containers, staged on
		# dollies by the hub's docks for the truck to the airport.
		var c: Vector2i = h.lands.regional_hub[0]
		var z := c.y * cell + cell + 1.0
		for k in 3:
			var x := c.x * cell - 4.0 + k * 2.4
			_box("paint", Vector3(1.9, 0.35, 1.7), Vector3(x, 0.4, z), Color("#3a3d40"))
			_box("metal", Vector3(1.53, 1.63, 1.56), Vector3(x, 1.4, z), Color("#c9ccca"))


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


## Edge pieces, cut back to the sidewalk: along the front street, lawn with
## a few shade trees; elsewhere, carrier lot with stalls wherever a whole
## one fits, fenced where it meets the sidewalk or a neighbour.
func _edge_lots() -> void:
	var lots := {}
	for c in edge_land:
		var poly: PackedVector2Array = edge_land[c]
		if c.y == 0:
			continue
		lots[c] = poly
		var pad := _inset(poly, 1.0)
		if pad.size() >= 3:
			_flat_poly_any("asphalt", pad, 0.06, MULCH)
			_stalls_in(pad)
	_fence_edges(_edge_sides(cells, lots, edge_land), 1.8, GALV, 3.0)
	# The lawn's shade trees, about 11 m apart, kept back from its edges.
	for c in edge_land:
		if c.y != 0:
			continue
		var plot := _inset(edge_land[c], 3.0)
		if plot.size() < 3:
			continue
		var box := _bounds(plot)
		var z := box.position.y + fmod(box.size.y, 11.0) * 0.5
		while z <= box.end.y:
			var x := box.position.x + fmod(box.size.x, 11.0) * 0.5
			while x <= box.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, z), plot):
					var sp := TreeField.Species.MAPLE if rng.randf() < 0.5 else TreeField.Species.OAK
					trees.append([Vector3(x, 0, z), sp, TreeField.LEAF[sp], rng.randf_range(0.8, 1.0)])
				x += 11.0
			z += 11.0


## Carrier stalls (as _stall_row) in rows across an outline, each wherever
## a whole stall fits inside it.
func _stalls_in(poly: PackedVector2Array) -> void:
	var box := _bounds(poly)
	var zb := box.position.y + 5.8
	while zb <= box.end.y:
		var x := box.position.x + 0.3
		while x + 2.7 <= box.end.x:
			var fits := true
			for q in [Vector2(x, zb - 5.5), Vector2(x + 2.7, zb - 5.5), Vector2(x, zb), Vector2(x + 2.7, zb)]:
				fits = fits and Geometry2D.is_point_in_polygon(q, poly)
			if fits:
				_flat_rect("line", x - 0.06, x + 0.06, zb - 5.5, zb, 0.07, LINE)
				stalls.append([Vector3(x + 1.3, 0.0, zb - 0.6), PI])
			x += 2.7
		zb += 12.0


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
