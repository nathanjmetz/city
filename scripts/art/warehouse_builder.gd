class_name WarehouseBuilder
extends CivicBuilder
## Warehouses, benchmarked against photos of real Midwest industrial parks
## (I-70 and I-65 corridors, small-town flex buildings):
##   - tilt-up concrete wall panels about 7.6 m (25 ft) wide with reveal
##     joints, a painted accent band and a parapet over a flat white roof
##     with skylights and rooftop units
##   - dock doors 9 ft wide x 10 ft high at dock height (4 ft), 13 ft on
##     centre, each with a black dock seal and bumpers, over a concrete dock
##     apron and an asphalt truck court
##   - a glazed two-storey office at one front corner, car parking on the
##     side drive, and a fire lane around the back
## Taller racks (a higher level) mean a taller box; bays added at the back
## make it deeper. What the owner builds from its development tree stands
## behind it in turn, each in its own strip (Warehouses.TREE "land"):
##   - truck yard: striped 53 ft trailer stalls with parked trailers
##   - repair shop: a pre-engineered metal shop with 14 ft doors
##   - fuel island: a canopy over two diesel dispensers
##   - cold storage / freezer: insulated white metal panel boxes with
##     condenser units on the roof
##   - tank farm: vertical steel tanks in a containment berm
##   - cross-dock: dock doors in the back wall over a second truck court
##   - co-packing: a single-storey production wing
##   - regional DC: a trailer drop lot Local space as CivicBuilder: centred on the site, -z
## faces the road, the site's front is at -depth / 2.

## Tilt-up panel colours: off-white, warm grey, tan, light grey.
const TILT := ["#dcd8cd", "#cfcabd", "#d6cdb8", "#c4c3be", "#e2dfd6"]
## Accent bands: navy, teal, maroon, charcoal, none.
const ACCENT := ["#2f4a6e", "#2c6b6a", "#6e2f2f", "#3a3c3f", ""]
const SEAL := Color("#1e1f21")
const MEMBRANE := Color("#e4e3de")
const DOCK_SPACING := 4.0
const DOCK_HEIGHT := 1.2


## [house mesh, ground mesh, trees] for warehouse `w` (see Warehouses).
static func build_warehouse(w: Dictionary, seed: int, to_curb: float) -> Array:
	var b := WarehouseBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._warehouse(w, to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees]


func _warehouse(w: Dictionary, to_curb: float) -> void:
	var s := Warehouses.spec(w)
	var bw: float = s.w
	var bd := Warehouses.building_depth(w)
	var sw := Warehouses.site_width(w)
	var sd := Warehouses.site_depth(w)
	var front := -sd * 0.5
	var zf: float = front + float(s.court)
	var cx := -sw * 0.5 + bw * 0.5  # the building; the side drive runs at +x
	var h: float = Balance.WAREHOUSE_HEIGHTS[int(w.level)] + 1.6  # clear height plus joists and deck
	var wall := Color(_pick(TILT))
	var accent_hex: String = _pick(ACCENT)
	# The box: tilt-up panels, parapet, flat white roof.
	_slab(cx, bw, zf, bd)
	_flat_roofed_at("paint", cx, bw, bd, zf + bd * 0.5, h, h + 1.0, wall)
	var y := h + 0.04
	_quad("paint", Vector3(cx - bw * 0.5 + 0.3, y, zf + 0.3), Vector3(cx + bw * 0.5 - 0.3, y, zf + 0.3),
		Vector3(cx + bw * 0.5 - 0.3, y, zf + bd - 0.3), Vector3(cx - bw * 0.5 + 0.3, y, zf + bd - 0.3), MEMBRANE, [], Vector3.UP)
	_panel_joints(cx, bw, zf, bd, h + 1.0, wall.darkened(0.22))
	if accent_hex != "":
		var accent := Color(accent_hex)
		_box("paint", Vector3(bw + 0.08, 0.7, 0.06), Vector3(cx, h - 0.2, zf - 0.03), accent)
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.06, 0.7, bd + 0.08), Vector3(cx + e * (bw * 0.5 + 0.03), h - 0.2, zf + bd * 0.5), accent)
	_skylights(cx, bw, zf, bd, h)
	_rooftop_units(cx, bw, zf, bd, h, maxi(1, int(bw * bd / 1500.0)))
	# Office at the front corner: glazed, two storeys on the bigger ones.
	var ow := clampf(bw * 0.22, 8.0, 24.0)
	var ox := cx - bw * 0.5 + ow * 0.5
	var floors := 1 if bw < 60.0 else 2
	for f in floors:
		var gy := 1.6 + f * 3.6
		_glass(Vector3(ox, gy, zf - 0.04), Vector3(-1, 0, 0), ow - 0.6, 2.4, rng.randf_range(0.0, 0.4))
		_box("paint", Vector3(ow, 0.25, 0.1), Vector3(ox, gy + 1.35, zf - 0.06), MULLION[0])
		_glass(Vector3(cx - bw * 0.5 - 0.04, gy, zf + ow * 0.35), Vector3(0, 0, 1), ow * 0.6, 2.4, rng.randf_range(0.0, 0.4))
	_entry(ox, zf, wall.darkened(0.1))
	_sign(Vector3(ox, floors * 3.6 + 0.6, zf - 0.08), ow * 0.8, 0.8)
	# Dock doors along the rest of the front wall.
	var x0 := ox + ow * 0.5 + 2.5
	var x1 := cx + bw * 0.5 - 2.0
	var docks := mini(int(s.docks), int((x1 - x0) / DOCK_SPACING))
	var start := x1 - docks * DOCK_SPACING
	for i in docks:
		_dock_door(start + (i + 0.5) * DOCK_SPACING, zf)
	# One drive-in door at grade, with a ramp, on the side drive.
	if bd > 24.0:
		var dz := zf + 6.0
		_box("siding", Vector3(0.08, 4.3, 3.7), Vector3(cx + bw * 0.5 + 0.03, 0.3 + 2.15, dz), Color(WHITE, 0.0))
		_box("paint", Vector3(0.12, 0.15, 3.9), Vector3(cx + bw * 0.5 + 0.06, 4.7, dz), Color("#cfcbc2"))
	# Concrete dock apron, asphalt truck court, and the drives out to the street.
	var apron := minf(float(s.court), 15.0)
	_flat_rect("drive", start - 1.0, x1 + 1.0, zf - apron, zf, 0.08)
	_flat_rect("asphalt", -sw * 0.5 + 0.3, sw * 0.5 - 0.3, front + 0.3, zf, 0.06)
	var truck_x := (start + x1) * 0.5
	_flat_rect("asphalt", truck_x - 6.0, truck_x + 6.0, front - to_curb, front + 0.3, 0.1)
	# Visitor parking in front of the office.
	var vx := cx - bw * 0.5 + 0.5
	while vx < start - 2.5:
		_flat_rect("line", vx - 0.06, vx + 0.06, zf - 6.5, zf - 1.0, 0.07, LINE)
		vx += 2.75
	# Side drive to the back, with staff parking along it.
	var lane_x := sw * 0.5 - 6.0
	_flat_rect("asphalt", lane_x - 5.6, lane_x + 5.6, zf - apron, sd * 0.5 - 0.3, 0.06)
	_flat_rect("asphalt", -sw * 0.5 + 0.3, sw * 0.5 - 0.3, zf + bd, sd * 0.5 - 0.3, 0.06)
	var pz := zf + 3.0
	var stalls := int(minf(bd - 6.0, 6.0 + float(s.jobs) * 2.75) / 2.75)
	for i in stalls + 1:
		var z := pz + i * 2.75
		_flat_rect("line", lane_x + 0.4, lane_x + 5.6, z - 0.06, z + 0.06, 0.07, LINE)
	_annexes(w, cx, bw, lane_x - 5.6, zf + bd, h)
	_automation(w.get("built", []), cx, bw, zf, bd, h, wall, ox, ow, truck_x, front)
	# A few street trees and a strip of shrubs by the office.
	_bed(ox, zf - 1.6, ow * 0.6)
	for i in rng.randi_range(1, 3):
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(cx - bw * 0.5 + 3.0 + i * 9.0, 0, front + 1.5), pick[0], pick[1], rng.randf_range(0.8, 1.05)])


## The steps of its owner's tree that happen inside the walls (Warehouses
## TREE nodes with no land), as they show from outside on real buildings.
func _automation(built: Array, cx: float, bw: float, zf: float, bd: float, h: float, wall: Color,
		ox: float, ow: float, truck_x: float, front: float) -> void:
	if "sortation" in built:
		# A sorter's motors and the people working it need far more power
		# and air: a row of big rooftop units and exhaust fans down the roof.
		var n := maxi(3, int(bw / 18.0))
		for i in n:
			var x := cx - bw * 0.5 + (i + 0.5) * bw / n
			_box("metal", Vector3(3.2, 1.6, 2.0), Vector3(x, h + 0.8, zf + bd * 0.3), Color("#b9bcbc"))
			_cylinder("paint", Vector3(x + 2.6, h, zf + bd * 0.3), 0.55, 1.0, Color("#9ea3a6"), 10)
	if "robotics" in built:
		# Robotic storage (an AS/RS) needs racks far taller than the old
		# clear height: a high-bay roof raised over the back of the box.
		var hz0 := zf + bd * 0.55
		var hz1 := zf + bd - 1.0
		var hw := bw - 6.0
		var top := h + 9.0
		_box("paint", Vector3(hw, top - h, hz1 - hz0), Vector3(cx, h + (top - h) * 0.5, (hz0 + hz1) * 0.5), wall)
		_quad("paint", Vector3(cx - hw * 0.5, top + 0.02, hz0), Vector3(cx + hw * 0.5, top + 0.02, hz0),
			Vector3(cx + hw * 0.5, top + 0.02, hz1), Vector3(cx - hw * 0.5, top + 0.02, hz1), MEMBRANE, [], Vector3.UP)
		_box("paint", Vector3(hw + 0.1, 0.4, 0.3), Vector3(cx, top + 0.2, hz0), Color("#cfcbc2"))
	if "fulfillment" in built:
		# Order fulfillment runs shifts of pickers: a big covered staff
		# entrance at the office and a guard booth at the truck gate.
		_box("paint", Vector3(ow * 0.8, 0.3, 3.4), Vector3(ox, 4.3, zf - 1.7), Color("#2f3a44"))
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 4.2, 0.3), Vector3(ox + e * ow * 0.36, 2.1, zf - 3.2), Color("#2f3a44"))
		var g := Vector3(truck_x + 7.6, 0, front + 3.0)
		_box("paint", Vector3(2.6, 0.2, 2.6), g + Vector3(0, 0.1, 0), Color("#b9b5ab"))
		_box("paint", Vector3(2.2, 2.6, 2.2), g + Vector3(0, 1.5, 0), Color("#d8d6cf"))
		_box("paint", Vector3(2.3, 0.9, 2.3), g + Vector3(0, 2.0, 0), Color(0.55, 0.65, 0.7))
		_box("paint", Vector3(2.6, 0.2, 2.6), g + Vector3(0, 2.9, 0), Color("#3a3734"))


## Reveal joints between tilt-up panels, front and sides.
func _panel_joints(cx: float, bw: float, zf: float, bd: float, top: float, col: Color) -> void:
	var n := int(bw / 7.6)
	for i in range(1, n):
		var x := cx - bw * 0.5 + i * bw / n
		_box("paint", Vector3(0.06, top, 0.04), Vector3(x, top * 0.5, zf - 0.02), col)
	var m := int(bd / 7.6)
	for e in [-1.0, 1.0]:
		for i in range(1, m):
			var z := zf + i * bd / m
			_box("paint", Vector3(0.04, top, 0.06), Vector3(cx + e * (bw * 0.5 + 0.02), top * 0.5, z), col)


## A dock door at dock height with its seal and two bumpers.
func _dock_door(x: float, zf: float) -> void:
	_box("siding", Vector3(2.7, 3.0, 0.08), Vector3(x, DOCK_HEIGHT + 1.5, zf - 0.03), Color(WHITE, 0.0))
	_box("paint", Vector3(3.5, 0.45, 0.35), Vector3(x, DOCK_HEIGHT + 3.2, zf - 0.17), SEAL)
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(0.35, 3.4, 0.35), Vector3(x + e * 1.55, DOCK_HEIGHT + 1.6, zf - 0.17), SEAL)
		_box("paint", Vector3(0.3, 0.3, 0.2), Vector3(x + e * 1.0, DOCK_HEIGHT - 0.2, zf - 0.1), SEAL)
	# Dock leveler lip and the light above.
	_box("paint", Vector3(2.4, 0.08, 0.5), Vector3(x, DOCK_HEIGHT, zf - 0.25), Color("#55585a"))
	_box("paint", Vector3(0.3, 0.2, 0.3), Vector3(x + 1.7, DOCK_HEIGHT + 3.7, zf - 0.15), Color("#3a3c3f"))


## Skylights in rows across the roof.
func _skylights(cx: float, bw: float, zf: float, bd: float, h: float) -> void:
	var col := Color("#c9d6dc")
	var xs := int(bw / 15.0)
	var zs := int(bd / 12.0)
	for i in xs:
		for j in zs:
			var p := Vector3(cx - bw * 0.5 + (i + 0.5) * bw / xs, h + 0.12, zf + (j + 0.5) * bd / zs)
			_box("paint", Vector3(1.4, 0.18, 2.4), p, col)


## The owner's annexes behind the building, in tree order (see
## Warehouses.annex_depth): x from the site's left edge to `x1` (the side
## drive), z from the back wall `zb`.
func _annexes(w: Dictionary, cx: float, bw: float, x1: float, zb: float, h: float) -> void:
	var x0 := cx - bw * 0.5
	var z := zb
	for node in Warehouses.TREE:
		if float(node.land) <= 0.0 or not node.id in w.get("built", []):
			continue
		var d := float(node.land)
		match node.id:
			"truck_yard", "regional_dc":
				_trailer_lot(x0, x1, z + 1.0, z + d - 1.0, node.id == "regional_dc")
			"repair_shop":
				var sw := minf(24.0, x1 - x0 - 4.0)
				var sx := x0 + 2.0 + sw * 0.5
				_slab(sx, sw, z + 1.0, d - 3.0)
				_flat_roofed_at("siding", sx, sw, d - 3.0, z + 1.0 + (d - 3.0) * 0.5, 6.2, 6.6, Color("#b9bdbf"))
				for i in 2:
					_overhead_door(sx - sw * 0.25 + i * sw * 0.5, z + 1.0 + (d - 3.0), 4.3, 4.3, Color("#9aa0a4"), true)
				_flat_rect("drive", x0 + 1.0, x1, z + d - 2.0, z + d, 0.08)
			"fuel_island":
				var fx := x0 + 2.0 + 9.0
				var fz := z + d * 0.5
				_flat_rect("drive", fx - 9.0, fx + 9.0, z + 1.0, z + d - 1.0, 0.08)
				for e in [-1.0, 1.0]:
					_box("paint", Vector3(1.2, 0.2, 4.5), Vector3(fx + e * 4.0, 0.1, fz), CONCRETE)
					_box("paint", Vector3(0.8, 1.6, 0.6), Vector3(fx + e * 4.0, 1.0, fz), Color("#d9dcdd"))
					_box("paint", Vector3(0.3, 4.9, 0.3), Vector3(fx + e * 4.0, 2.45, fz + 2.0), Color("#d9dcdd"))
				_box("paint", Vector3(16.0, 0.9, d - 4.0), Vector3(fx, 5.4, fz), Color("#eeeeea"))
				_box("paint", Vector3(16.1, 0.25, d - 3.9), Vector3(fx, 5.0, fz), Color("#2c6b6a"))
			"cold_storage", "freezer":
				var tall := h + (3.0 if node.id == "freezer" else 0.0)
				var cd := d - 2.0
				_slab(cx, bw, z, cd)
				_flat_roofed_at("siding", cx, bw, cd, z + cd * 0.5, tall, tall + 0.6, Color("#eef0ee"))
				for i in maxi(1, int(bw / 25.0)):
					_box("paint", Vector3(5.0, 1.8, 2.2), Vector3(x0 + 6.0 + i * 25.0, tall + 0.9, z + cd * 0.5), Color("#c9ccca"))
					_cyl_y(Vector3(x0 + 4.8 + i * 25.0, tall + 1.9, z + cd * 0.5), 0.8, 0.2, DARK)
					_cyl_y(Vector3(x0 + 7.2 + i * 25.0, tall + 1.9, z + cd * 0.5), 0.8, 0.2, DARK)
			"tank_farm":
				var r := minf(5.0, (d - 6.0) * 0.5)
				var n := maxi(1, int((x1 - x0 - 4.0) / (r * 2.0 + 4.0)))
				_flat_rect("drive", x0 + 1.0, x0 + 3.0 + n * (r * 2.0 + 4.0), z + 1.0, z + d - 1.0, 0.08)
				_box("paint", Vector3(n * (r * 2.0 + 4.0), 1.2, 0.6), Vector3(x0 + 2.0 + n * (r * 2.0 + 4.0) * 0.5, 0.6, z + 1.3), CONCRETE)
				_box("paint", Vector3(n * (r * 2.0 + 4.0), 1.2, 0.6), Vector3(x0 + 2.0 + n * (r * 2.0 + 4.0) * 0.5, 0.6, z + d - 1.3), CONCRETE)
				for i in n:
					var tc := Vector3(x0 + 4.0 + r + i * (r * 2.0 + 4.0), 0.0, z + d * 0.5)
					_cyl_y(tc + Vector3(0, 4.5, 0), r, 9.0, Color("#e2e2dc"))
					_cyl_y(tc + Vector3(0, 9.1, 0), r * 0.98, 0.2, Color("#c8c8c2"))
			"cross_dock":
				var docks := int((bw - 6.0) / DOCK_SPACING)
				for i in docks:
					var dx := x0 + 3.0 + (i + 0.5) * DOCK_SPACING
					_box("siding", Vector3(2.7, 3.0, 0.08), Vector3(dx, DOCK_HEIGHT + 1.5, zb + 0.03), Color(WHITE, 0.0))
					_box("paint", Vector3(3.5, 0.45, 0.35), Vector3(dx, DOCK_HEIGHT + 3.2, zb + 0.17), SEAL)
				_flat_rect("drive", x0 + 2.0, x0 + bw - 2.0, zb, zb + minf(d, 15.0), 0.08)
			"co_packing":
				var cd := d - 2.0
				_slab(cx, bw * 0.7, z, cd)
				_flat_roofed_at("siding", cx - bw * 0.15, bw * 0.7, cd, z + cd * 0.5, 6.5, 7.2, Color("#c7c3b8"))
				_rooftop_units(cx - bw * 0.15, bw * 0.7, z, cd, 6.5, 2)
		z += d


## Striped stalls for 53 ft trailers (16.2 m by 3.7 m), some taken.
func _trailer_lot(x0: float, x1: float, z0: float, z1: float, full: bool) -> void:
	_flat_rect("asphalt", x0, x1, z0, z1, 0.07)
	var x := x0 + 1.0
	while x + 3.7 < x1:
		_flat_rect("line", x - 0.06, x + 0.06, z0 + 0.5, z1 - 0.5, 0.08, LINE)
		if rng.randf() < (0.8 if full else 0.45):
			var len := minf(16.2, z1 - z0 - 2.0)
			var col: Color = [Color("#e8e8e4"), Color("#d8d9d6"), Color("#b23a2e"), Color("#2f4a6e")][rng.randi() % 4]
			_box("paint", Vector3(2.6, 2.9, len), Vector3(x + 1.85, 1.25 + 1.45, (z0 + z1) * 0.5), col)
			_box("paint", Vector3(2.2, 1.0, 0.3), Vector3(x + 1.85, 0.5, (z0 + z1) * 0.5 + len * 0.5 - 2.0), DARK)
		x += 3.7


## Flat ground work cut into cells about 8 m across, so a big truck court
## follows the real terrain when it's draped instead of sinking under it.
func _flat_rect(kind: String, x0: float, x1: float, z0: float, z1: float, y: float, col := MULCH) -> void:
	var nx := maxi(1, ceili(absf(x1 - x0) / 8.0))
	var nz := maxi(1, ceili(absf(z1 - z0) / 8.0))
	if nx == 1 and nz == 1:
		super(kind, x0, x1, z0, z1, y, col)
		return
	for i in nx:
		for j in nz:
			super(kind, lerpf(x0, x1, float(i) / nx), lerpf(x0, x1, float(i + 1) / nx),
				lerpf(z0, z1, float(j) / nz), lerpf(z0, z1, float(j + 1) / nz), y, col)
