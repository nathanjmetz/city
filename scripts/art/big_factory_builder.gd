class_name BigFactoryBuilder
extends CivicBuilder
## The big local factories, each laid out and detailed after real plants
## (photos and site plans compared side by side in docs/big_factories.md):
##   - ethanol: a Midwest dry-mill plant (Cardinal Ethanol, Union City IN;
##     POET Alexandria IN): truck scale and grain receiving shed with a
##     bucket-elevator leg, corrugated grain bins, a row of stainless
##     fermenters joined by a catwalk, the distillation tower in a steel
##     frame, the DDGS dryer with its thermal-oxidizer stack, a flat
##     storage shed for distillers grains, a multi-cell cooling tower, and
##     white ethanol tanks inside a containment berm by the tanker loadout
##   - meatpacker: a hog plant (Indiana Packers, Delphi IN): one long
##     windowless white insulated-panel building with a taller kill floor
##     end, ammonia condensers on the roof, a brick office and a big staff
##     lot at the front, covered livestock pens and unloading docks at one
##     side, reefer trailers at the shipping docks, a boiler stack and a
##     wastewater lagoon at the back
##   - furniture: a Jasper, Indiana hardwood plant: long brick and metal
##     sheds, an open-sided lumber shed of stickered stacks, a row of dry
##     kilns, a sawdust silo with dust-collector cyclones, and a wood-waste
##     boiler stack
##   - RV: an Elkhart County plant: long narrow white clear-span buildings
##     with overhead doors down the long side, a frame and chassis yard, and
##     rows of finished travel trailers waiting for toters
## Each extra line (level) adds a real unit: a fermenter, another building.
## Bays add depth at the back. Local space as CivicBuilder: centred on the
## site, -z faces the road, the front is at -depth / 2.

const PANEL_WHITE := Color("#e6e6e1")
const STAINLESS := Color("#c7cbcc")
const TANK_WHITE := Color("#eceae4")
const STEEL_FRAME := Color("#6f7a80")
const SAFETY_YELLOW := Color("#d6b13a")
const BIN_STEEL := Color("#bfc3c4")
const LAGOON := Color("#4f6b5c")
const TRAILER := Color("#f1f0ec")
const LUMBER := Color("#b88f5e")
const BERM := Color("#8a8f6a")


## [buildings mesh, ground mesh, trees] for plant `f` (see BigFactories).
static func build(f: Dictionary, seed: int, to_curb: float) -> Array:
	var b := BigFactoryBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := BigFactories.site_width(f)
	var d := BigFactories.site_depth(f)
	match f.kind:
		"ethanol": b._ethanol(w, d, int(f.level), to_curb)
		"meatpacker": b._meatpacker(w, d, int(f.level), to_curb)
		"furniture": b._furniture(w, d, int(f.level), to_curb)
		"rv": b._rv(w, d, int(f.level), to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees]


# ---------------------------------------------------------------- shared

## Gravel yard, the fence round the back, the drive in and the office lot.
func _site(w: float, d: float, to_curb: float, drive_x: float, yard: String) -> void:
	var front := -d * 0.5
	_flat_rect(yard, -w * 0.5 + 0.5, w * 0.5 - 0.5, front + 0.5, d * 0.5 - 0.5, 0.05, YARD_GRAVEL if yard == "gravel" else LINE)
	_flat_rect("asphalt", drive_x - 6.0, drive_x + 6.0, front - to_curb, front + 30.0, 0.09)
	_fence(Vector2(-w * 0.5 + 1.0, front + 26.0), Vector2(w * 0.5 - 1.0, d * 0.5 - 1.0), 2.4, true)


## A one-storey brick office with a glass entry and a striped lot by the street.
func _office(x: float, front: float, w: float, d: float, lot_w: float, to_curb: float) -> void:
	var zf := front + 16.0
	_slab(x, w, zf, d)
	_flat_roofed_at("brick", x, w, d, zf + d * 0.5, 3.8, 4.4, Color(_pick(BRICK)))
	_window_row(x, zf, w - 4.0, 2.0, 1.5, int(w / 3.5), WHITE)
	_entry(x - w * 0.25, zf, Color("#cfcbc2"))
	_sign(Vector3(x + w * 0.15, 4.9, zf - 0.08), w * 0.45, 0.9)
	_parking(x - lot_w * 0.5, x + lot_w * 0.5, front + 1.0, zf - 1.5, to_curb, x + lot_w * 0.3)
	_bed(x, zf - 1.0, w * 0.5)
	_flagpole(Vector3(x - w * 0.5 - 3.0, 0, zf - 4.0))


## A vertical tank with a cone roof, a ring stair and a top rail.
func _tank(c: Vector3, r: float, h: float, col: Color) -> void:
	_box("concrete", Vector3(r * 2.2, 0.4, r * 2.2), c + Vector3(0, 0.2, 0), CONCRETE)
	_cylinder("metal", c + Vector3(0, 0.4, 0), r, h, col, 24)
	_cone(c + Vector3(0, 0.4 + h, 0), r + 0.1, r * 0.18, col.darkened(0.06), 24)
	_ring_rail(c, h + 0.4 + r * 0.18 + 1.0, r * 0.9, GALV)
	# Stair winding up the side: a run of steps along the shell.
	var steps := int(h / 0.9)
	for i in steps:
		var a := 0.15 * i
		var p := c + Vector3(cos(a) * (r + 0.5), 0.4 + i * 0.9, sin(a) * (r + 0.5))
		_box("paint", Vector3(0.9, 0.08, 0.9), p, GALV)


## A steel bucket-elevator leg: a tall square tower with spouts out to bins.
func _leg(c: Vector3, h: float, to: Array) -> void:
	_box("metal", Vector3(2.4, h, 2.4), c + Vector3(0, h * 0.5, 0), BIN_STEEL.darkened(0.1))
	_box("metal", Vector3(4.0, 3.0, 4.0), c + Vector3(0, h + 1.5, 0), BIN_STEEL.darkened(0.15))
	for t in to:
		var top: Vector3 = t
		var a := c + Vector3(0, h - 1.0, 0)
		var mid := (a + top) * 0.5
		var len := a.distance_to(top)
		_box("paint", Vector3(0.45, 0.45, len), mid, GALV, Basis.looking_at((top - a).normalized(), Vector3.UP))


## A long steel catwalk between two points, with handrails.
func _catwalk(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
	var mid := (a + b) * 0.5
	_box("paint", Vector3(1.2, 0.12, len), mid, GALV, basis)
	for s in [-0.6, 0.6]:
		_box("paint", Vector3(0.05, 0.05, len), mid + basis.x * s + Vector3(0, 1.05, 0), SAFETY_YELLOW, basis)


## A rectangular multi-cell cooling tower with fan stacks.
func _cooling_tower(c: Vector3, cells: int) -> void:
	var cw := 9.0
	var w := cw * cells
	_box("concrete", Vector3(w + 1.0, 1.2, 11.0), c + Vector3(0, 0.6, 0), CONCRETE)
	_box("siding", Vector3(w, 8.0, 10.0), c + Vector3(0, 5.2, 0), Color("#9fa7a8"))
	for i in cells:
		var p := c + Vector3(-w * 0.5 + cw * (i + 0.5), 9.2, 0)
		_cylinder("paint", p, 3.6, 2.4, Color("#8e979a"), 16)
		_ring(p, 2.4, 3.2, 3.6, 0.05, Color("#3a3c3e"))


## A tall stack on a square base.
func _stack(c: Vector3, r: float, h: float) -> void:
	_box("concrete", Vector3(r * 3.0, 1.0, r * 3.0), c + Vector3(0, 0.5, 0), CONCRETE)
	_cylinder("metal", c + Vector3(0, 1.0, 0), r, h, Color("#8d9294"), 16)
	_ring(c, h + 1.0, r - 0.1, r + 0.15, 0.25, Color("#3a3c3e"))


## A big low insulated-metal-panel building: walls, flat white roof, panel joints.
func _panel_building(cx: float, zf: float, w: float, d: float, h: float, wall: Color) -> void:
	_slab(cx, w, zf, d)
	_flat_roofed_at("paint", cx, w, d, zf + d * 0.5, h, h + 0.9, wall)
	_quad("paint", Vector3(cx - w * 0.5 + 0.3, h + 0.04, zf + 0.3), Vector3(cx + w * 0.5 - 0.3, h + 0.04, zf + 0.3),
		Vector3(cx + w * 0.5 - 0.3, h + 0.04, zf + d - 0.3), Vector3(cx - w * 0.5 + 0.3, h + 0.04, zf + d - 0.3),
		Color("#e4e3de"), [], Vector3.UP)
	var n := int(w / 6.0)
	for i in range(1, n):
		_box("paint", Vector3(0.05, h + 0.9, 0.04), Vector3(cx - w * 0.5 + i * w / n, (h + 0.9) * 0.5, zf - 0.02), wall.darkened(0.12))


## A long metal-sided building with a low gable roof (Elkhart and Jasper sheds).
func _shed(cx: float, cz: float, w: float, d: float, h: float, wall: Color, roof: Color) -> void:
	_box("concrete", Vector3(w + 0.2, 0.3, d + 0.2), Vector3(cx, 0.15, cz), FOUNDATION)
	_box("metal", Vector3(w, h, d), Vector3(cx, 0.3 + h * 0.5, cz), wall)
	_metal_roof(cx, cz, 0.3 + h, w, d, roof)


## A semi trailer (53 ft) parked at a dock, back to the wall, with its tractor gone.
func _trailer(back: Vector3, out: Vector3, col: Color, reefer := false) -> void:
	var len := 16.2
	var basis := Basis.looking_at(out, Vector3.UP)
	var mid := back + out * len * 0.5 + Vector3(0, 2.55, 0)
	_box("paint", Vector3(2.6, 2.75, len), mid, col, basis)
	_box("paint", Vector3(2.4, 0.9, 1.6), back + out * (len - 1.0) + Vector3(0, 0.75, 0), DARK, basis)  # landing gear
	for k in [1.5, 2.8]:
		_box("paint", Vector3(2.5, 1.0, 1.0), back + out * k + Vector3(0, 0.6, 0), DARK, basis)  # tandem axles
	if reefer:
		_box("paint", Vector3(2.2, 1.6, 0.6), back + out * (len + 0.3) + Vector3(0, 2.8, 0), Color("#d8d8d4"), basis)


# ---------------------------------------------------------------- ethanol

func _ethanol(w: float, d: float, level: int, to_curb: float) -> void:
	var front := -d * 0.5
	var drive_x := w * 0.3
	_site(w, d, to_curb, drive_x, "gravel")
	_office(-w * 0.32, front, 22.0, 12.0, 34.0, to_curb)
	# Concrete roads round the process area.
	_flat_rect("drive", drive_x - 6.0, drive_x + 6.0, front + 30.0, d * 0.5 - 8.0, 0.07)
	_flat_rect("drive", -w * 0.5 + 6.0, w * 0.5 - 6.0, front + 64.0, front + 72.0, 0.07)
	# Truck scale and the grain receiving shed with its dump pit, then the leg and bins.
	var rz := front + 40.0
	_box("paint", Vector3(3.6, 0.25, 22.0), Vector3(drive_x - 2.0, 0.12, rz), CONCRETE)
	_shed(drive_x, rz + 22.0, 16.0, 20.0, 9.0, BIN_STEEL, Color("#9aa2a5"))
	var leg := Vector3(drive_x + 14.0, 0, rz + 22.0)
	var bins := []
	for i in 2 + mini(level, 1):
		var bc := Vector3(drive_x + 30.0 + i * 22.0, 0, rz + 30.0)
		if bc.x + 10.0 > w * 0.5 - 4.0:
			bc = Vector3(drive_x + 30.0 + (i - 1) * 22.0, 0, rz + 54.0)
		_grain_bin(bc, 9.0, 20.0)
		bins.append(bc + Vector3(0, 27.0, 0))
	_leg(leg, 46.0, bins)
	# Hammer mill and the slurry building.
	_panel_building(drive_x - 14.0, rz + 36.0, 14.0, 12.0, 11.0, PANEL_WHITE)
	# Fermenters: stainless tanks in a row, joined at the top. Real plants
	# run three or four 750,000-gallon fermenters (about 16 m across).
	var fz := front + 92.0
	var count := 3 + level
	var r := 7.5
	var x0 := -w * 0.5 + 14.0
	var tops := []
	for i in count:
		var c := Vector3(x0 + i * (r * 2.0 + 3.0), 0, fz)
		_tank(c, r, 17.0, STAINLESS)
		tops.append(c + Vector3(0, 17.6 + r * 0.18, 0))
	for i in count - 1:
		_catwalk(tops[i], tops[i + 1])
	# Beer well and the distillation tower in its steel frame.
	var dx := x0 + count * (r * 2.0 + 3.0) + 6.0
	_tank(Vector3(dx, 0, fz), 5.0, 14.0, STAINLESS)
	var tower := Vector3(dx + 16.0, 0, fz)
	_frame3(tower, 10.0, 8.0, 34.0)
	for k in [[-2.5, 1.4, 36.0], [2.0, 1.1, 30.0], [0.0, 0.9, 26.0]]:
		_cylinder("metal", tower + Vector3(k[0], 0, 0), k[1], k[2], STAINLESS, 14)
	# DDGS dryer building, the thermal oxidizer stack and the flat storage shed.
	var bz := front + 122.0
	_panel_building(-w * 0.5 + 34.0, bz, 26.0, 20.0, 14.0, Color("#d9d6cc"))
	_stack(Vector3(-w * 0.5 + 52.0, 0, bz + 10.0), 1.6, 42.0)
	_ddgs_shed(Vector3(-w * 0.5 + 40.0, 0, bz + 44.0), 50.0, 26.0)
	_cooling_tower(Vector3(dx + 4.0, 0, bz + 12.0), 3 + level)
	# Ethanol and denaturant tanks in a containment berm, and the tanker loadout.
	var tz := minf(d * 0.5 - 30.0, front + 175.0)
	var tx := w * 0.5 - 40.0
	_berm(tx, tz, 52.0, 34.0)
	_tank(Vector3(tx - 13.0, 0, tz), 10.0, 12.0, TANK_WHITE)
	_tank(Vector3(tx + 13.0, 0, tz), 10.0, 12.0, TANK_WHITE)
	_tank(Vector3(tx + 13.0, 0, tz - 14.0), 4.0, 8.0, TANK_WHITE)
	_loadout(Vector3(drive_x, 0, tz - 22.0))
	for i in 4:
		trees.append([Vector3(-w * 0.5 + 6.0 + i * 12.0, 0, front + 3.0), TreeField.pick(rng, true)[0], TreeField.pick(rng, true)[1], rng.randf_range(0.8, 1.0)])


## A steel structure frame of columns and floors, for a process tower.
func _frame3(c: Vector3, w: float, d: float, h: float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.4, h, 0.4), c + Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), STEEL_FRAME)
	var y := 6.0
	while y < h:
		_box("paint", Vector3(w + 0.4, 0.15, d + 0.4), c + Vector3(0, y, 0), GALV)
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(w, 0.05, 0.05), c + Vector3(0, y + 1.05, sz * d * 0.5), SAFETY_YELLOW)
		y += 6.0


## Open-sided pole shed for distillers grains, with a pile showing under it.
func _ddgs_shed(c: Vector3, w: float, d: float) -> void:
	_box("concrete", Vector3(w, 0.3, d), c + Vector3(0, 0.15, 0), CONCRETE)
	var n := int(w / 8.0)
	for i in n + 1:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.35, 9.0, 0.35), c + Vector3(-w * 0.5 + i * w / n, 4.8, sz * d * 0.5), GALV)
	_metal_roof(c.x, c.z, 9.3, w, d, Color("#a7aeb1"))
	_box("concrete", Vector3(w * 0.3, 3.0, d * 0.8), c + Vector3(w * 0.3, 0.3 + 1.5, 0), CONCRETE)  # push wall
	_cone(c + Vector3(-w * 0.15, 0.3, 0), d * 0.35, 4.5, Color("#a8823f"), 16, "paint")


## An earth containment berm round a tank farm.
func _berm(x: float, z: float, w: float, d: float) -> void:
	_flat_rect("gravel", x - w * 0.5, x + w * 0.5, z - d * 0.5, z + d * 0.5, 0.06, YARD_GRAVEL.darkened(0.05))
	for e in [[0.0, -d * 0.5, w, 1.5], [0.0, d * 0.5, w, 1.5], [-w * 0.5, 0.0, 1.5, d], [w * 0.5, 0.0, 1.5, d]]:
		_box("paint", Vector3(e[2], 1.2, e[3]), Vector3(x + e[0], 0.6, z + e[1]), BERM)


## A tanker loadout: a canopy over two bays with the loading arms.
func _loadout(c: Vector3) -> void:
	_box("concrete", Vector3(14.0, 0.25, 22.0), c + Vector3(0, 0.12, 0), CONCRETE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.4, 6.5, 0.4), c + Vector3(sx * 6.0, 3.25, sz * 9.0), STEEL_FRAME)
	_box("metal", Vector3(14.0, 0.5, 22.0), c + Vector3(0, 6.75, 0), Color("#d7d6d0"))
	for sx in [-3.2, 3.2]:
		_box("paint", Vector3(0.25, 1.8, 0.25), c + Vector3(sx, 5.2, 0), SAFETY_YELLOW)
	_trailer(c + Vector3(-3.2, 0, -8.0), Vector3(0, 0, 1), Color("#d5d6d3"))


# ---------------------------------------------------------------- meatpacker

func _meatpacker(w: float, d: float, level: int, to_curb: float) -> void:
	var front := -d * 0.5
	var drive_x := w * 0.38
	_site(w, d, to_curb, drive_x, "gravel")
	# A big staff lot: plants like this run two shifts of hundreds.
	_parking(-w * 0.5 + 2.0, w * 0.15, front + 1.0, front + 30.0, to_curb, -w * 0.1)
	var zf := front + 36.0
	var bw := w * 0.62 + level * 8.0
	bw = minf(bw, w - 40.0)
	var bd := minf(d - 70.0, 70.0 + level * 12.0)
	var cx := -w * 0.5 + 6.0 + bw * 0.5
	# Fabrication and cooler: low, wide and windowless. The harvest floor at
	# the back end stands taller.
	_panel_building(cx, zf, bw, bd * 0.65, 9.0, PANEL_WHITE)
	_panel_building(cx, zf + bd * 0.65, bw, bd * 0.35, 13.0, PANEL_WHITE.darkened(0.03))
	# The office: brick front with ribbon windows, on the street side.
	var ox := cx - bw * 0.25
	_box("brick", Vector3(30.0, 7.5, 10.0), Vector3(ox, 0.3 + 3.75, zf - 5.0), Color(_pick(BRICK)))
	_window_row(ox, zf - 10.0, 26.0, 2.0, 1.4, 8, WHITE)
	_window_row(ox, zf - 10.0, 26.0, 5.6, 1.4, 8, WHITE)
	_entry(ox, zf - 10.0, Color("#cfcbc2"))
	_sign(Vector3(ox + 8.0, 8.4, zf - 10.08), 12.0, 1.0)
	# Ammonia condensers on the roof and the engine room.
	for i in int(bw / 14.0):
		var p := Vector3(cx - bw * 0.5 + 7.0 + i * 14.0, 9.0, zf + bd * 0.3)
		_box("metal", Vector3(4.5, 2.2, 9.0), p + Vector3(0, 1.1, 0), Color("#b9bcbc"))
		for k in [-2.2, 2.2]:
			_cylinder("paint", p + Vector3(0, 2.2, k), 1.4, 0.4, Color("#3a3c3e"), 12)
	_rooftop_units(cx, bw, zf, bd * 0.6, 9.0, int(bw / 10.0))
	# Shipping docks down the long side, reefer trailers backed in.
	var sx := cx + bw * 0.5
	var docks := int(bd * 0.6 / 4.2)
	for i in docks:
		var z := zf + 4.0 + i * 4.2
		_box("paint", Vector3(0.35, 3.4, 3.3), Vector3(sx + 0.17, 2.9, z), DARK)
		if i % 3 != 1:
			_trailer(Vector3(sx + 0.6, 0, z), Vector3(1, 0, 0), TRAILER, true)
	_flat_rect("asphalt", sx, w * 0.5 - 2.0, zf - 4.0, zf + bd * 0.65, 0.07)
	# Livestock receiving: unloading docks into covered pens beside the harvest floor.
	var pz := zf + bd * 0.65 + 4.0
	var pw := minf(30.0, w * 0.5 - bw * 0.5 - 4.0)
	var px := sx + pw * 0.5 + 3.0
	for i in 3:
		var z := pz + i * 9.0
		for k in int(pw / 5.0):
			_box("paint", Vector3(0.12, 1.1, 8.0), Vector3(px - pw * 0.5 + k * 5.0, 0.55, z), Color("#9fa4a3"))
	_box("paint", Vector3(pw, 0.2, 27.0), Vector3(px, 0.1, pz + 9.0), CONCRETE)
	var roof_y := 4.5
	for k in [-1.0, 1.0]:
		for i in 4:
			_box("paint", Vector3(0.25, roof_y, 0.25), Vector3(px + k * pw * 0.5, roof_y * 0.5, pz - 4.0 + i * 9.0), GALV)
	_metal_roof(px, pz + 9.0, roof_y, pw, 28.0, Color("#a9b0b2"))
	_trailer(Vector3(px + pw * 0.5 + 1.0, 0, pz + 9.0), Vector3(1, 0, 0), Color("#b7bcbe"))
	# Boiler stack, and the wastewater lagoon at the back of the site.
	_stack(Vector3(cx - bw * 0.5 + 8.0, 0, zf + bd + 6.0), 1.0, 22.0)
	var lz := zf + bd + 14.0
	if d * 0.5 - lz > 16.0:
		_flat_rect("gravel", -w * 0.5 + 8.0, w * 0.5 - 30.0, lz, d * 0.5 - 6.0, 0.05, BERM)
		_flat_rect("line", -w * 0.5 + 12.0, w * 0.5 - 34.0, lz + 4.0, d * 0.5 - 10.0, 0.08, LAGOON)
	for i in 5:
		trees.append([Vector3(-w * 0.5 + 6.0 + i * 11.0, 0, front + 2.0), TreeField.pick(rng, true)[0], TreeField.pick(rng, true)[1], rng.randf_range(0.8, 1.05)])


# ---------------------------------------------------------------- furniture

func _furniture(w: float, d: float, level: int, to_curb: float) -> void:
	var front := -d * 0.5
	var drive_x := w * 0.36
	_site(w, d, to_curb, drive_x, "gravel")
	_office(-w * 0.28, front, 26.0, 12.0, 40.0, to_curb)
	# The plant: a long brick front building with metal sheds behind it, one
	# more shed per line. Jasper plants grew this way, shed by shed.
	var zf := front + 32.0
	var pw := w * 0.58
	var cx := -w * 0.5 + 6.0 + pw * 0.5
	var brick := Color(_pick(BRICK))
	_slab(cx, pw, zf, 22.0)
	_flat_roofed_at("brick", cx, pw, 22.0, zf + 11.0, 7.0, 7.8, brick)
	_window_row(cx, zf, pw - 6.0, 4.2, 1.6, int(pw / 5.0), WHITE)
	_overhead_door(cx + pw * 0.5 - 8.0, zf, 4.2, 4.5, Color(WHITE, 0.0))
	for i in 1 + level:
		var z := zf + 22.0 + 2.0 + i * 26.0
		if z + 12.0 > d * 0.5 - 30.0:
			break
		_shed(cx, z + 12.0, pw, 24.0, 7.5, Color(_pick(METAL_WALL)), Color("#8f979b"))
	# Dust collection: cyclones on a steel stand over a sawdust silo, ducts to the plant.
	var dx := cx + pw * 0.5 + 10.0
	var dz := zf + 30.0
	_silo(Vector3(dx, 0, dz), 3.5, 16.0)
	for k in [-3.0, 3.0]:
		_box("paint", Vector3(0.3, 14.0, 0.3), Vector3(dx + k, 7.0, dz + 6.0), STEEL_FRAME)
		_cylinder("metal", Vector3(dx + k, 14.0, dz + 6.0), 1.4, 4.0, GALV, 14)
		_cone(Vector3(dx + k, 14.0, dz + 6.0), 1.4, -3.5, GALV, 14)
	_box("paint", Vector3(dx - (cx + pw * 0.5) + 1.0, 0.9, 0.9), Vector3((dx + cx + pw * 0.5) * 0.5, 12.0, dz + 6.0), GALV)
	_stack(Vector3(dx + 10.0, 0, dz - 4.0), 0.9, 20.0)
	# Dry kilns: a row of insulated metal chambers with big doors.
	var kz := zf + 50.0
	for i in 3 + level:
		var kx := dx - 2.0 + i * 9.0
		if kx + 4.0 > w * 0.5 - 4.0:
			break
		_box("metal", Vector3(8.0, 7.0, 16.0), Vector3(kx, 3.8, kz), Color("#a6aaa6"))
		_box("paint", Vector3(7.2, 6.0, 0.15), Vector3(kx, 3.4, kz - 8.05), Color("#7c8282"))
	# The lumber shed: open-sided, full of stickered stacks.
	var lz := minf(d * 0.5 - 22.0, kz + 34.0)
	var lw := minf(w - 20.0, 70.0)
	var lx := w * 0.5 - 8.0 - lw * 0.5
	_box("concrete", Vector3(lw, 0.25, 18.0), Vector3(lx, 0.12, lz), CONCRETE)
	for i in int(lw / 8.0) + 1:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 6.0, 0.3), Vector3(lx - lw * 0.5 + i * lw / int(lw / 8.0), 3.2, lz + sz * 9.0), GALV)
	_metal_roof(lx, lz, 6.2, lw, 18.0, Color("#9aa1a3"))
	var stacks := int(lw / 3.2)
	for i in stacks:
		var h := rng.randf_range(1.6, 3.2)
		var p := Vector3(lx - lw * 0.5 + 1.6 + i * 3.2, 0.3, lz + rng.randf_range(-3.0, 3.0))
		_box("wood", Vector3(2.4, h, 5.0), p + Vector3(0, h * 0.5, 0), LUMBER.darkened(rng.randf_range(0.0, 0.15)))
		for k in int(h / 0.35):
			_box("paint", Vector3(2.5, 0.04, 5.05), p + Vector3(0, 0.35 * (k + 1), 0), LUMBER.darkened(0.45))
	for i in 4:
		trees.append([Vector3(-w * 0.5 + 6.0 + i * 13.0, 0, front + 2.0), TreeField.pick(rng, true)[0], TreeField.pick(rng, true)[1], rng.randf_range(0.8, 1.05)])


# ---------------------------------------------------------------- RV

func _rv(w: float, d: float, level: int, to_curb: float) -> void:
	var front := -d * 0.5
	var drive_x := w * 0.42
	_site(w, d, to_curb, drive_x, "gravel")
	_office(-w * 0.34, front, 20.0, 10.0, 30.0, to_curb)
	# Long, narrow production buildings with doors down the long side: units
	# roll in one end on their frames and out the other finished.
	var lines := 1 + mini(level, 2)
	var bw := 30.0
	var zf := front + 30.0
	var bd := minf(d - 70.0, 130.0)
	for i in lines:
		var cx := -w * 0.5 + 10.0 + bw * 0.5 + i * (bw + 14.0)
		_shed(cx, zf + bd * 0.5, bw, bd, 8.5, Color(_pick(["#eeede6", "#e4dfcf", "#d9d7cf"])), Color("#9aa3a6"))
		for k in int(bd / 16.0):
			var z := zf + 8.0 + k * 16.0
			_box("siding", Vector3(0.08, 4.8, 4.4), Vector3(cx + bw * 0.5 + 0.04, 2.7, z), Color(WHITE, 0.0))
		_overhead_door(cx, zf, 4.6, 5.0, Color(WHITE, 0.0))
		_flat_rect("asphalt", cx + bw * 0.5, cx + bw * 0.5 + 12.0, zf, zf + bd, 0.07)
	# Frame and chassis yard: steel frames stacked on cribbing.
	var fx := -w * 0.5 + 10.0 + lines * (bw + 14.0) + 12.0
	for i in 4:
		for k in 3:
			_box("paint", Vector3(2.4, 0.3, 10.0), Vector3(fx + i * 3.4, 0.4 + k * 0.4, zf + 10.0), Color("#3c3f42"))
	# Finished travel trailers in rows, waiting for toter drivers.
	var yx0 := fx - 4.0
	var yx1 := w * 0.5 - 8.0
	var rz := zf + 28.0
	while rz < d * 0.5 - 10.0 and yx1 - yx0 > 6.0:
		var x := yx0
		while x < yx1 - 3.0:
			if rng.randf() < 0.85:
				_camper(Vector3(x + 1.3, 0, rz), rng.randf_range(8.0, 10.5))
			x += 3.6
		rz += 14.0
	for i in 3:
		trees.append([Vector3(-w * 0.5 + 6.0 + i * 12.0, 0, front + 2.0), TreeField.pick(rng, true)[0], TreeField.pick(rng, true)[1], rng.randf_range(0.8, 1.05)])


## A towable travel trailer: white box, dark windows, a graphic swoosh, the
## A-frame hitch on its jack.
func _camper(c: Vector3, len: float) -> void:
	var swoosh := Color(_pick(["#2f4a6e", "#6e2f2f", "#3a3c3f", "#7a6a4a", "#2c6b6a"]))
	_box("paint", Vector3(2.45, 2.7, len), c + Vector3(0, 1.85, 0), TRAILER)
	_box("paint", Vector3(2.5, 0.35, len * 0.7), c + Vector3(0, 1.4, 0.1 * len), swoosh)
	_box("paint", Vector3(2.5, 0.6, 1.4), c + Vector3(0, 2.4, -len * 0.25), Color("#26292c"))
	_box("paint", Vector3(2.5, 0.6, 1.0), c + Vector3(0, 2.4, len * 0.2), Color("#26292c"))
	_box("paint", Vector3(2.3, 0.15, len - 0.4), c + Vector3(0, 3.25, 0), Color("#dedcd6"))
	_box("paint", Vector3(0.3, 0.6, 1.4), c + Vector3(0, 0.55, -len * 0.5 - 0.7), DARK)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.25, 0.75, 0.75), c + Vector3(s * 1.15, 0.38, 0.0), Color("#1b1c1e"))
