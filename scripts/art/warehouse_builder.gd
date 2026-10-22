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
## make it deeper. Local space as CivicBuilder: centred on the site, -z
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
	# A few street trees and a strip of shrubs by the office.
	_bed(ox, zf - 1.6, ow * 0.6)
	for i in rng.randi_range(1, 3):
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(cx - bw * 0.5 + 3.0 + i * 9.0, 0, front + 1.5), pick[0], pick[1], rng.randf_range(0.8, 1.05)])


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
