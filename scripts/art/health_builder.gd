class_name HealthBuilder
extends CivicBuilder
## Healthcare buildings, after photos of real small Midwestern towns:
##   - the county hospital: a two-storey brick block with ribbon windows, a
##     drive-under entry canopy and a front lot; every building its
##     administrator adds since stands on its own strip of the campus (a
##     glassy ER with an ambulance canopy, a medical office building, brick
##     and stucco wings, a tall bed tower, a striped helipad, a concrete
##     parking garage over the old front lot)
##   - the nursing home: a long single-storey brick wing with a covered
##     drop-off, windows for every room and a garden with benches
##   - the daycare: a low building with a bright fenced play yard
## Same local space as CivicBuilder (-z faces the road).

const EIFS := ["#d9d3c3", "#e3ddd0", "#c9c1ae", "#b8b2a4"]
const ER_RED := Color("#a8282a")

## The original hospital's footprint (x0, x1, z0, z1), for the corridors
## every later piece runs back to it.
var _main := [0.0, 0.0, 0.0, 0.0]
## Every piece's strip (x0, x1, z0, z1, height), so a corridor never runs
## through another building.
var _rects := []


## `hub` is the hospital's record from Healthcare (empty for other kinds).
## `built` holds a nursing home's or daycare's added pieces (Stations).
## What each campus piece's sign says (as Indiana regional hospitals letter
## their wings: Parkview, IU Health Ball).
const PIECE_SIGNS := {"er": "EMERGENCY", "maternity": "BIRTHING CENTER", "surgery": "SURGERY CENTER",
	"rehab": "REHABILITATION", "cancer": "CANCER CENTER", "teaching": "HOSPITAL", "community": "COMMUNITY HEALTH"}

static func build_care(kind: int, seed: int, size: Vector2, to_curb: float, hub := {}, built := []) -> Array:
	var b := HealthBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := -size.y * 0.5
	match kind:
		Services.Kind.HOSPITAL: b._hospital(size, to_curb, hub)
		Services.Kind.NURSING_HOME:
			b._nursing_home(front, to_curb)
			b._station_upgrades(kind, size, front, built)
		Services.Kind.DAYCARE:
			b._daycare(front, to_curb)
			b._station_upgrades(kind, size, front, built)
	b.half = size.x * 0.5
	b.depth = size.y * 0.5
	b._dress(false, true)
	return [b._commit_house(), b._commit_flat(), b.trees, b.labels]


# ---------------------------------------------------------------- hospital

func _hospital(size: Vector2, to_curb: float, hub: Dictionary) -> void:
	var brick := Color(_pick(["#8a4a38", "#9b5a42", "#a8775c", "#b59a7c"]))
	var eifs := Color(_pick(EIFS))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	var first: Vector2 = Services.KINDS[Services.Kind.HOSPITAL].size
	# Campus centre in the hospital's frame (s along the street, d back).
	var cx := 0.0
	var front := -size.y * 0.5
	if not hub.is_empty():
		cx = (float(hub.x0) + float(hub.x1)) * 0.5
	var up := 0.0  # floors added on top when it was boxed in
	var garage := false
	if not hub.is_empty():
		for p in hub.pieces:
			var t: Dictionary = Healthcare.TREE[p.key]
			if p.key == "garage":
				garage = true
			elif p.rect.is_empty() and float(t.area) > 0.0:
				up += 4.0
	# The county hospital: two storeys of brick across the first site.
	var x0 := -first.x * 0.5 - cx + 4.0
	var x1 := first.x * 0.5 - cx - 4.0
	var zf := front + 24.0
	var d := first.y - 28.0
	var w := x1 - x0
	var mx := (x0 + x1) * 0.5
	var h := 8.2 + up
	_main = [x0, x1, zf, zf + d]
	_slab(mx, w, zf, d)
	_flat_roofed_at("brick", mx, w, d, zf + d * 0.5, h, h + 0.8, brick)
	for floor in int(h / 4.0):
		var y := 1.8 + floor * 4.0
		_window_row(mx, zf, w - 6.0, y, 1.4, int(w / 3.2), trim)
		_window_row(mx, zf + d, w - 6.0, y, 1.4, int(w / 3.2), trim, Vector3.BACK)
	_box("paint", Vector3(w + 0.06, 0.6, 0.12), Vector3(mx, h - 0.5, zf - 0.04), eifs)
	# Main entry: a drive-under canopy, the sign over it.
	_vestibule(mx, zf, 5.0, 2.8, 3.6)
	_box("paint", Vector3(9.0, 0.5, 8.0), Vector3(mx, 4.3, zf - 5.0), eifs)
	_box("paint", Vector3(8.8, 0.04, 7.8), Vector3(mx, 4.04, zf - 5.0), SOFFIT)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.45, 4.1, 0.45), Vector3(mx + s * 4.0, 2.05, zf - 8.6), eifs)
	_flat_rect("drive", mx - 4.5, mx + 4.5, zf - 9.0, zf, 0.09)
	_civic_sign(Vector3(mx, h - 2.2, zf - 0.14), minf(w * 0.4, 14.0), 0.9, "HOSPITAL", "#1f3b6e", "#f2efe6", "franklin")
	_rooftop_units(mx, w, zf, d, h, 3)
	# The front lot, or a parking garage over it.
	if garage:
		var gz0 := front + 1.0
		var gz1 := zf - 10.0
		var gx0 := x0
		var gx1 := mx - 6.0
		for lvl in 4:
			_box("paint", Vector3(gx1 - gx0, 0.35, gz1 - gz0), Vector3((gx0 + gx1) * 0.5, lvl * 3.0 + 0.2, (gz0 + gz1) * 0.5), CONCRETE)
			if lvl > 0:
				_box("paint", Vector3(gx1 - gx0, 1.0, 0.2), Vector3((gx0 + gx1) * 0.5, lvl * 3.0 + 0.85, gz0), CONCRETE.darkened(0.08))
		for x in [gx0 + 0.3, (gx0 + gx1) * 0.5, gx1 - 0.3]:
			for z in [gz0 + 0.3, gz1 - 0.3]:
				_box("paint", Vector3(0.6, 9.4, 0.6), Vector3(x, 4.7, z), CONCRETE.darkened(0.1))
		_parking(mx - 5.0, x1, front + 0.3, zf - 10.0, to_curb, mx + 2.0)
	else:
		_parking(x0, x1, front + 0.3, zf - 10.0, to_curb, mx - 6.0)
	_bed(mx - 7.0, zf - 1.2, 5.0)
	_bed(mx + 7.0, zf - 1.2, 5.0)
	_flagpole(Vector3(mx - 9.0, 0, zf - 10.5))
	_hospital_service(x0, x1, zf + d, h, eifs, zf - 10.0)
	if hub.is_empty():
		return
	# Every building the administrator has added, on its own strip.
	for p in hub.pieces:
		if not p.rect.is_empty():
			var r: Array = p.rect
			_rects.append([float(r[0]) - cx, float(r[1]) - cx, front + float(r[2]), front + float(r[3]),
				float(Healthcare.TREE[p.key].height)])
	for p in hub.pieces:
		if p.rect.is_empty():
			continue
		var r: Array = p.rect
		var a := Vector2(float(r[0]) - cx, float(r[1]) - cx)
		var z0 := front + float(r[2])
		var z1 := front + float(r[3])
		_piece(p.key, a.x, a.y, z0, z1, brick, eifs, trim, to_curb, front)

## What every hospital has whatever it grows into: a mechanical penthouse
## on the roof; and on the service side, the bulk liquid oxygen tank in its
## fenced pad (NFPA 55: outdoors, clear of the building) with its finned
## vaporizers, the standby generator in a sound enclosure on its fuel tank
## (NFPA 99/110: a hospital's essential electrical system), and the
## loading dock with a trash compactor.
func _hospital_service(x0: float, x1: float, zb: float, h: float, eifs: Color, lot_z: float) -> void:
	var mx := (x0 + x1) * 0.5
	var pent := eifs.darkened(0.12)
	_box("paint", Vector3(12.0, 3.4, 7.0), Vector3(mx + 4.0, h + 1.7, zb - 9.0), pent)
	_box("paint", Vector3(12.4, 0.25, 7.4), Vector3(mx + 4.0, h + 3.5, zb - 9.0), pent.darkened(0.1))
	for k in 5:
		_box("paint", Vector3(1.6, 1.4, 0.05), Vector3(mx - 0.6 + k * 2.3, h + 1.8, zb - 12.53), pent.darkened(0.2))
	# The oxygen tank: a white vertical vacuum-jacketed tank on legs.
	var o := Vector3(x0 + 3.0, 0, zb + 2.0)
	_box("paint", Vector3(5.6, 0.2, 3.4), o + Vector3(1.0, 0.1, 0), CONCRETE)
	_cyl_y(o + Vector3(0, 4.7, 0), 1.05, 7.0, Color("#eceae4"))
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(0.12, 1.3, 0.12), o + Vector3(e * 0.8, 0.65, 0.5), GALV)
		_box("paint", Vector3(0.12, 1.3, 0.12), o + Vector3(e * 0.8, 0.65, -0.5), GALV)
	for k in 2:
		var v := o + Vector3(2.2 + k * 1.0, 0, 0)
		_box("paint", Vector3(0.5, 3.2, 0.5), v + Vector3(0, 1.8, 0), Color("#c9cccc"))
		for f in 4:
			_box("paint", Vector3(0.04, 3.0, 0.9), v + Vector3(0, 1.8, 0), Color("#b9bcbc"), Basis(Vector3.UP, f * PI * 0.25))
	_fence(Vector2(o.x - 2.0, o.z - 1.7), Vector2(o.x + 3.8, o.z + 1.7), 1.8)
	# The generator: a long sound enclosure on its belly tank, exhaust up.
	var g := Vector3(x0 + 13.0, 0, zb + 2.0)
	_box("paint", Vector3(9.0, 0.25, 3.0), g + Vector3(0, 0.12, 0), CONCRETE)
	_box("paint", Vector3(8.6, 0.8, 2.6), g + Vector3(0, 0.65, 0), Color("#3a3c3e"))
	_box("paint", Vector3(8.4, 2.4, 2.4), g + Vector3(0, 2.25, 0), Color("#d6d2c4"))
	for k in 6:
		_box("paint", Vector3(1.0, 1.4, 0.04), g + Vector3(-3.4 + k * 1.35, 2.3, -1.22), Color("#a9a597"))
	_box("paint", Vector3(0.35, 1.2, 0.35), g + Vector3(3.2, 4.05, 0.4), Color("#3a3c3e"))
	# The loading dock: two dock doors, the compactor, and the service
	# drive round the side from the front lot to its apron.
	var dx := mx + 6.0
	_flat_rect("drive", dx - 6.0, x1 + 3.8, zb, zb + 3.9, 0.08)
	_flat_rect("asphalt", x1 + 0.3, x1 + 3.8, lot_z, zb, 0.075)
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(2.8, 2.8, 0.06), Vector3(dx + e * 2.2, 1.6, zb + 0.04), Color("#9aa0a4"))
		_box("paint", Vector3(3.2, 0.2, 0.3), Vector3(dx + e * 2.2, 3.15, zb + 0.15), Color("#2b2f33"))
	_box("paint", Vector3(2.0, 1.8, 3.2), Vector3(dx - 6.6, 0.9, zb + 2.0), Color("#3d6a8a"))



func _piece(key: String, x0: float, x1: float, z0: float, z1: float, brick: Color, eifs: Color, trim: Color,
		to_curb: float, front: float) -> void:
	var t: Dictionary = Healthcare.TREE[key]
	var pad := 3.0
	var w := x1 - x0 - pad * 2.0
	var d := z1 - z0 - pad * 2.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	if w < 4.0 or d < 4.0:
		return
	if key == "helipad":
		var s := minf(minf(w, d), 22.0)
		_flat_rect("drive", cx - s * 0.5, cx + s * 0.5, cz - s * 0.5, cz + s * 0.5, 0.12)
		var line := Color("#f2f0ea")
		_flat_rect("line", cx - s * 0.42, cx + s * 0.42, cz - s * 0.42, cz - s * 0.39, 0.13, line)
		_flat_rect("line", cx - s * 0.42, cx + s * 0.42, cz + s * 0.39, cz + s * 0.42, 0.13, line)
		_flat_rect("line", cx - s * 0.42, cx - s * 0.39, cz - s * 0.42, cz + s * 0.42, 0.13, line)
		_flat_rect("line", cx + s * 0.39, cx + s * 0.42, cz - s * 0.42, cz + s * 0.42, 0.13, line)
		# The H.
		_flat_rect("line", cx - s * 0.2, cx - s * 0.13, cz - s * 0.25, cz + s * 0.25, 0.14, line)
		_flat_rect("line", cx + s * 0.13, cx + s * 0.2, cz - s * 0.25, cz + s * 0.25, 0.14, line)
		_flat_rect("line", cx - s * 0.13, cx + s * 0.13, cz - s * 0.035, cz + s * 0.035, 0.14, line)
		# A windsock on a pole at the corner.
		var c := Vector3(cx + s * 0.5 + 1.5, 0, cz - s * 0.5)
		_cyl_y(c + Vector3(0, 2.5, 0), 0.06, 5.0, Color("#d0d2d2"))
		_box("paint", Vector3(0.3, 0.3, 1.4), c + Vector3(0, 4.9, 0.7), Color("#e06a1e"))
		return
	var h: float = maxf(float(t.height), 4.5)
	var modern: bool = int(t.tier) >= 1
	var wall := brick if key in ["rehab", "maternity", "nursing_school"] else eifs if modern or key == "offices" else brick
	var mat := "paint" if wall == eifs else "brick"
	if key in ["offices", "nursing_school"]:
		h = 11.6  # three floors at 3.9 m, like a real medical office building
	# A piece on the street gets its own front lot with the building set back,
	# like a medical office building or school on its own parcel.
	var bz0 := z0 + pad
	if z0 <= front + 0.5 and key != "er" and d > 30.0:
		var lot := minf(d * 0.4, 26.0)
		_parking(x0 + 1.0, x1 - 1.0, z0 + 0.3, z0 + lot, to_curb, cx + (x1 - x0) * 0.3)
		bz0 = z0 + lot + 5.0
		d = z1 - pad - bz0
	else:
		# Room in front, inside its own strip, for what stands out from the
		# entry (a canopy, a drop-off, a garden).
		var apron: float = {"er": 8.0, "surgery": 10.0, "heart": 8.0, "cancer": 9.0, "teaching": 9.0,
			"offices": 5.0, "maternity": 4.5}.get(key, 0.0)
		if apron > pad:
			bz0 = z0 + apron
			d = z1 - pad - bz0
	# Rehab keeps its back third for the therapy garden; the cancer centre
	# gives an end of its strip to the treatment vaults.
	var garden := 0.0
	if key == "rehab" and d > 24.0:
		garden = d * 0.38
		d -= garden
	var vault := 0.0
	if key == "cancer" and w > 24.0:
		vault = minf(16.0, w * 0.32)
		w -= vault + 1.0
		cx -= (vault + 1.0) * 0.5
	var bz1 := bz0 + d
	cz = (bz0 + bz1) * 0.5
	if d < 4.0:
		return
	var tower := 0.0  # a teaching hospital's bed tower over a two-floor podium
	if key == "teaching" and w > 20.0:
		tower = h
		h = 8.4
	_slab(cx, w, bz0, d)
	_flat_roofed_at(mat, cx, w, d, cz, h, h + 0.8, wall)
	if key == "offices":
		# A brick ground floor under the stucco, as on most newer MOBs.
		_box("brick", Vector3(w + 0.12, 4.2, d + 0.12), Vector3(cx, 2.1, cz), brick)
	_faces(key, cx, w, bz0, d, h, modern, trim)
	if tower > 0.0:
		var tw := w * 0.62
		var td := minf(d * 0.62, 20.0)
		var tz := bz0 + d * 0.5 + 1.0
		_flat_roofed_at("paint", cx, tw, td, tz, tower, tower + 1.0, eifs)
		_faces("tower", cx, tw, tz - td * 0.5, td, tower, false, trim, h)
		_rooftop_units(cx, tw, tz - td * 0.5, td, tower + 0.2, 2)
		_civic_sign(Vector3(cx, tower - 1.8, tz - td * 0.5 - 0.14), minf(tw * 0.5, 12.0), 1.0, "HOSPITAL", "#1f3b6e", "#f2efe6", "franklin")
	_rooftop_units(cx, w, bz0, d, h, 1 + int(w * d / 900.0))
	match key:
		"er":
			# The ambulance canopy and the red EMERGENCY sign over the bays.
			_box("paint", Vector3(minf(w, 14.0), 0.5, 7.0), Vector3(cx, 4.6, bz0 - 3.5), eifs)
			for s in [-1.0, 1.0]:
				_box("paint", Vector3(0.4, 4.4, 0.4), Vector3(cx + s * (minf(w, 14.0) * 0.5 - 0.5), 2.2, bz0 - 6.8), eifs)
			_box("paint", Vector3(minf(w * 0.6, 9.0), 0.8, 0.12), Vector3(cx, 5.3, bz0 - 7.05), ER_RED)
			_flat_rect("drive", cx - 7.0, cx + 7.0, bz0 - 7.0, bz0, 0.1)
			for i in 2:
				_overhead_door(cx - 3.0 + i * 6.0, bz0, 3.6, 3.4, WHITE)
			# The red EMERGENCY pylon at the street, as every US ER has.
			var py := Vector3(x0 + 1.2, 0, z0 + 1.0)
			_box("paint", Vector3(1.6, 0.4, 0.8), py + Vector3(0, 0.2, 0), CONCRETE)
			_box("paint", Vector3(1.2, 3.4, 0.45), py + Vector3(0, 2.1, 0), ER_RED)
			_box("paint", Vector3(1.0, 0.5, 0.47), py + Vector3(0, 3.3, 0), WHITE)
		"offices":
			_canopy(cx - w * 0.2, bz0, 9.0, 4.5, 3.8, trim)
			_stair_tower(cx + w * 0.5 - 2.5, bz0, h)
			_civic_sign(Vector3(cx + 2.0, h - 1.6, bz0 - 0.14), minf(w * 0.4, 10.0), 0.8, "MEDICAL OFFICES", "#1f3b6e", "#f2efe6", "franklin")
		"maternity":
			_canopy(cx - w * 0.3, bz0, 7.0, 4.0, 3.4, Color("#6fa8a2"))
			_bed(cx + w * 0.1, bz0 - 1.4, minf(10.0, w * 0.3))
		"surgery":
			# A porte-cochère over the drop-off: day patients go home by car.
			var pw := minf(w * 0.5, 16.0)
			_box("paint", Vector3(pw, 0.6, 9.0), Vector3(cx, 4.7, bz0 - 4.5), eifs)
			_box("paint", Vector3(pw - 0.3, 0.04, 8.7), Vector3(cx, 4.38, bz0 - 4.5), SOFFIT)
			for sx in [-1.0, 1.0]:
				for zz in [bz0 - 8.4]:
					_box("paint", Vector3(0.6, 4.4, 0.6), Vector3(cx + sx * (pw * 0.5 - 0.6), 2.2, zz), eifs)
			_flat_rect("drive", cx - pw * 0.5 - 2.0, cx + pw * 0.5 + 2.0, bz0 - 9.5, bz0, 0.09)
			_vestibule(cx, bz0, 5.0, 2.4, 3.4)
			_mech_screen(cx + w * 0.15, w * 0.45, bz0 + d * 0.25, d * 0.5, h + 0.8)
		"rehab":
			_entry(cx, bz0, trim)
			_flat_rect("drive", cx - 2.0, cx + 2.0, z0, bz0, 0.09)
			if garden > 0.0:
				_therapy_garden(cx, w, bz1 + 1.0, garden - 1.0)
		"nursing_school":
			_limestone(cx, w, bz0, d, h)
			_stair_tower(cx - w * 0.5 + 3.0, bz0, h)
			_portal(cx, bz0, trim)
			_civic_sign(Vector3(cx, h - 1.7, bz0 - 0.14), minf(w * 0.45, 11.0), 0.8, "SCHOOL OF NURSING", "#5a1f24", "#f2efe6", "serif")
			for i in 6:
				_box("metal", Vector3(0.05, 0.8, 0.7), Vector3(cx + 4.0 + i * 0.7, 0.4, bz0 - 2.0), Color("#5a5e60"))
		"heart":
			_rotunda(cx, bz0, minf(7.0, w * 0.2), minf(h, 9.5), eifs)
			_civic_sign(Vector3(cx + w * 0.3, h - 1.8, bz0 - 0.14), minf(w * 0.3, 10.0), 0.9, "HEART CENTER", "#1f3b6e", "#f2efe6", "franklin")
		"cancer":
			_vestibule(cx, bz0, 6.0, 2.6, 3.8)
			_box("paint", Vector3(w + 0.1, 1.2, d + 0.1), Vector3(cx, 0.6, cz), Color("#cfc6b0"))  # limestone base
			if vault > 0.0:
				_vaults(cx + w * 0.5 + 1.0 + vault * 0.5, vault, bz0, minf(d, 24.0))
			_healing_garden(cx - w * 0.25, bz0, minf(w * 0.3, 7.0))
		"teaching":
			_vestibule(cx, bz0, 6.0, 2.6, 3.8)
			_canopy(cx, bz0 - 2.6, 12.0, 6.0, 4.4, eifs)
		_:
			_entry(cx, bz0, trim)
			_flat_rect("drive", cx - 2.0, cx + 2.0, z0, bz0, 0.09)
	if h >= 12.0 and key not in ["offices", "nursing_school", "heart"]:
		_civic_sign(Vector3(cx, h - 1.8, bz0 - 0.14), minf(w * 0.35, 12.0), 0.9, PIECE_SIGNS.get(key, "HOSPITAL"), "#1f3b6e", "#f2efe6", "franklin")
	_link(cx - w * 0.5, cx + w * 0.5, bz0, bz1, maxf(h, tower), eifs)
	# A walk to the street for pieces that front it.
	if z0 <= front + 0.5:
		_flat_rect("drive", cx - w * 0.5, cx + w * 0.5, z0 + 0.3, z0 + 2.1, 0.07)
	# Ground around it: lawn with a few trees at the corners.
	for i in 2:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(x0 + 1.5 if i == 0 else x1 - 1.5, 0, z1 - 1.5), pick[0], pick[1], rng.randf_range(0.6, 0.85)])


## The windows of a piece: ribbons of glass a floor on the newer pieces,
## punched windows in the older brick ones, bay windows on maternity rooms,
## and the tight punched grid of patient rooms on a bed tower.
func _faces(key: String, cx: float, w: float, bz0: float, d: float, h: float, modern: bool, trim: Color,
		base := 0.0) -> void:
	var floors := maxi(1, int((h - base) / 4.0))
	var cz := bz0 + d * 0.5
	for floor in floors:
		var y := base + 1.8 + floor * 4.0
		for o in [Vector3.FORWARD, Vector3.BACK]:
			var zz: float = bz0 if o == Vector3.FORWARD else bz0 + d
			if key == "maternity":
				_bays(cx, zz, w - 6.0, o, trim)
			elif key == "tower" or key == "offices" or key == "nursing_school":
				_window_row(cx, zz, w - 3.0, y, 1.6, int(w / 2.6), trim, o)
			elif modern:
				# Curtain wall bands: a strip of glass every floor.
				_glass(Vector3(cx, y + 0.2, zz + o.z * 0.03), Vector3.UP.cross(o), w - 2.0, 2.2, 0.15)
			else:
				_window_row(cx, zz, w - 4.0, y, 1.4, int(w / 3.2), trim, o)
		for s in [-1.0, 1.0]:
			var side := Vector3(s, 0, 0)
			if modern and key != "tower":
				_glass(Vector3(cx + s * (w * 0.5 + 0.03), y + 0.2, cz), Vector3.UP.cross(side), d - 2.0, 2.2, 0.15)
			else:
				_window_row(cx + s * w * 0.5, cz, d - 4.0, y, 1.4, int(d / 3.0), trim, side)


## Labor, delivery and recovery rooms each get a bay window, like the
## family-centred maternity wings built since the 1990s.
func _bays(cx: float, zz: float, span: float, o: Vector3, trim: Color) -> void:
	var n := int(span / 4.8)
	for i in n:
		var x := cx + ((i + 0.5) / n - 0.5) * span
		var c := Vector3(x, 0, zz) + o * 0.45
		_box("paint", Vector3(2.6, 0.5, 0.9), c + Vector3(0, 0.75, 0), trim)
		_box("paint", Vector3(2.7, 0.25, 1.0), c + Vector3(0, 3.15, 0), trim)
		_glass(Vector3(x, 1.95, zz) + o * 0.91, Vector3.UP.cross(o), 2.3, 2.1, 0.3)
		for e in [-1.0, 1.0]:
			_glass(Vector3(x + e * 1.31, 1.95, zz) + o * 0.45, Vector3.UP.cross(Vector3(e, 0, 0)), 0.8, 2.1, 0.3)


## A flat steel canopy on two round columns, out from a wall facing -z.
func _canopy(x: float, zf: float, w: float, d: float, h: float, fascia: Color) -> void:
	_box("paint", Vector3(w, 0.45, d), Vector3(x, h, zf - d * 0.5), fascia)
	_box("paint", Vector3(w - 0.2, 0.04, d - 0.2), Vector3(x, h - 0.24, zf - d * 0.5), SOFFIT)
	for s in [-1.0, 1.0]:
		_cylinder("paint", Vector3(x + s * (w * 0.5 - 0.6), 0, zf - d + 0.6), 0.2, h - 0.2, Color("#d6d4cc"), 10)
	_flat_rect("drive", x - w * 0.5, x + w * 0.5, zf - d, zf, 0.08)
	_vestibule(x, zf, 3.6, 2.0, 3.2)


## A glazed stair tower that stands a little proud of the wall and rises
## past the roof, at a front corner.
func _stair_tower(x: float, zf: float, h: float) -> void:
	var th := h + 2.4
	_box("paint", Vector3(4.2, 0.6, 4.4), Vector3(x, th, zf + 1.6), Color("#cfcbc2"))
	_glass(Vector3(x, th * 0.5, zf - 0.62), Vector3(-1, 0, 0), 3.6, th - 0.8, 0.0)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.3, th, 0.3), Vector3(x + s * 1.95, th * 0.5, zf - 0.5), MULLION[0])
		_glass(Vector3(x + s * 2.0, th * 0.5, zf + 0.2), Vector3(0, 0, s), 1.2, th - 0.8, 0.0)
	for i in int(th / 3.9):
		_box("paint", Vector3(3.6, 0.12, 0.08), Vector3(x, 3.9 * (i + 1) - 0.2, zf - 0.66), MULLION[0])


## Indiana limestone: a band at every floor line and a cap, the trim on
## nearly every brick school and college building in the state.
func _limestone(cx: float, w: float, zf: float, d: float, h: float) -> void:
	var stone := Color("#d8cfb8")
	for i in int(h / 3.9):
		var y := 3.9 * (i + 1) - 0.25
		_box("paint", Vector3(w + 0.16, 0.3, d + 0.16), Vector3(cx, y, zf + d * 0.5), stone)
	_box("paint", Vector3(w + 0.16, 0.5, d + 0.16), Vector3(cx, 0.55, zf + d * 0.5), stone)


## A limestone entry portal two floors tall around the doors.
func _portal(x: float, zf: float, trim: Color) -> void:
	var stone := Color("#d8cfb8")
	_box("paint", Vector3(7.0, 1.0, 1.2), Vector3(x, 7.4, zf - 0.6), stone)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(1.2, 7.4, 1.2), Vector3(x + s * 2.9, 3.7, zf - 0.6), stone)
	_glass(Vector3(x, 4.6, zf - 0.04), Vector3(-1, 0, 0), 4.4, 3.4, 0.0)
	_entry(x, zf, trim)


## A curved glass entry atrium two floors tall, after the heart institutes
## at Parkview (Fort Wayne) and St. Vincent (Indianapolis).
func _rotunda(x: float, zf: float, r: float, h: float, cap: Color) -> void:
	var n := 12
	var c := Vector3(x, 0, zf)
	for i in n:
		var a0 := PI + PI * i / n
		var a1 := PI + PI * (i + 1) / n
		var p0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var m := (p0 + p1) * 0.5
		var out := (m - c).normalized()
		_glass(m + Vector3(0, h * 0.5, 0), Vector3.UP.cross(out), p0.distance_to(p1), h - 0.6, 0.0)
		_box("paint", Vector3(0.14, h, 0.14), p1 + Vector3(0, h * 0.5, 0), MULLION[0])
		_tri("paint", c + Vector3(0, h, 0), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), cap, [], Vector3.UP)
		_quad("paint", p0 * 1.0 + out * 0.3 + Vector3(0, h - 0.2, 0), p1 + out * 0.3 + Vector3(0, h - 0.2, 0),
			p1 + out * 0.3 + Vector3(0, h + 0.5, 0), p0 + out * 0.3 + Vector3(0, h + 0.5, 0), cap, [], out)
		_tri("paint", c + Vector3(0, 0.12, 0), p0 + Vector3(0, 0.12, 0), p1 + Vector3(0, 0.12, 0), CONCRETE, [], Vector3.UP)
		_tri("paint", c + Vector3(0, h + 0.5, 0), p0 + out * 0.3 + Vector3(0, h + 0.5, 0), p1 + out * 0.3 + Vector3(0, h + 0.5, 0), cap, [], Vector3.UP)


## Radiation oncology: linear accelerator vaults, windowless concrete
## bunkers with walls 1.5 to 2 m thick (NCRP 151), set at one end of the
## cancer centre and partly bermed.
func _vaults(x: float, w: float, zf: float, d: float) -> void:
	var col := Color("#a9a59c")
	_box("slipform", Vector3(w, 6.6, d), Vector3(x, 3.3, zf + d * 0.5), col)
	_box("paint", Vector3(w + 0.2, 0.3, d + 0.2), Vector3(x, 6.75, zf + d * 0.5), col.darkened(0.12))
	# Board-formed panels 2.4 m wide; a seam between the two vaults.
	for i in int(d / 2.4):
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.06, 6.2, 0.05), Vector3(x + s * (w * 0.5 + 0.02), 3.3, zf + 2.4 * (i + 1)), col.darkened(0.15))
	for i in int(w / 2.4):
		_box("paint", Vector3(0.05, 6.2, 0.06), Vector3(x - w * 0.5 + 2.4 * (i + 1), 3.3, zf - 0.02), col.darkened(0.15))
	_box("paint", Vector3(w + 0.04, 6.4, 0.12), Vector3(x, 3.3, zf + d * 0.5), col.darkened(0.1))
	# The berm: grass sloping up the outer wall.
	var gx := x + w * 0.5
	_quad("pasture", Vector3(gx, 0.02, zf), Vector3(gx + 5.0, 0.02, zf), Vector3(gx + 5.0, 0.02, zf + d),
		Vector3(gx, 0.02, zf + d), Color("#6f8a48"), [], Vector3.UP)
	_quad("pasture", Vector3(gx, 4.0, zf), Vector3(gx + 5.0, 0.05, zf), Vector3(gx + 5.0, 0.05, zf + d),
		Vector3(gx, 4.0, zf + d), Color("#6f8a48"), [], Vector3(1, 1, 0))
	_rooftop_units(x, w, zf, d, 6.6, 1)


## A healing garden by the entry: a round fountain in a limestone curb,
## benches and planting, as at most cancer centres built since 2000.
func _healing_garden(x: float, z: float, r: float) -> void:
	var c := Vector3(x, 0, z - 4.6)
	_flat_rect("drive", x - r, x + r, c.z - r * 0.5, c.z + r * 0.5, 0.06)
	_cylinder("paint", c, 2.4, 0.5, Color("#d8cfb8"), 20)
	_cylinder("paint", c + Vector3(0, 0.38, 0), 2.1, 0.02, Color("#4a6670"), 20)
	_cyl_y(c + Vector3(0, 0.9, 0), 0.25, 1.0, Color("#d8cfb8"))
	for s in [-1.0, 1.0]:
		_garden_bench(c + Vector3(s * (r - 1.5), 0, 0), 0.0)
		_bed(x + s * r * 0.6, c.z + r * 0.5 + 1.0, 3.6)


## A park bench: two cast legs and a slatted wood seat.
func _garden_bench(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_box("paint", Vector3(1.8, 0.08, 0.5), p + b * Vector3(0, 0.45, 0), Color("#6b4a2e"), b)
	_box("paint", Vector3(1.8, 0.4, 0.06), p + b * Vector3(0, 0.75, 0.24), Color("#6b4a2e"), b)
	for s in [-0.8, 0.8]:
		_box("paint", Vector3(0.06, 0.45, 0.5), p + b * Vector3(s, 0.22, 0), Color("#2f3234"), b)


## A rooftop mechanical screen: operating rooms need big air handlers,
## hidden behind a louvred metal wall.
func _mech_screen(cx: float, w: float, z0: float, d: float, y: float) -> void:
	var col := Color("#b4b6b4")
	var sh := 2.8
	for z in [z0, z0 + d]:
		_box("metal", Vector3(w, sh, 0.12), Vector3(cx, y + sh * 0.5, z), col)
	for x in [cx - w * 0.5, cx + w * 0.5]:
		_box("metal", Vector3(0.12, sh, d), Vector3(x, y + sh * 0.5, z0 + d * 0.5), col)
	for i in int(w / 1.2):
		_box("paint", Vector3(0.05, sh, 0.05), Vector3(cx - w * 0.5 + 0.6 + i * 1.2, y + sh * 0.5, z0 - 0.08), col.darkened(0.2))
	for i in 2:
		_box("metal", Vector3(w * 0.35, 2.2, d * 0.6), Vector3(cx - w * 0.22 + i * w * 0.44, y + 1.1, z0 + d * 0.5), Color("#c4c6c4"))


## A rehab therapy garden: a walk loop with the surfaces patients practise
## on before going home (gravel, brick, a ramp and a short stair with
## handrails), after hospital rehab gardens such as Rehabilitation
## Hospital of Indiana's.
func _therapy_garden(cx: float, w: float, z0: float, d: float) -> void:
	var x0 := cx - w * 0.5 + 2.0
	var x1 := cx + w * 0.5 - 2.0
	var z1 := z0 + d - 2.0
	_flat_rect("drive", x0, x1, z0 + 1.0, z0 + 2.6, 0.06)
	_flat_rect("drive", x0, x1, z1 - 1.6, z1, 0.06)
	_flat_rect("drive", x0, x0 + 1.6, z0 + 1.0, z1, 0.06)
	_flat_rect("drive", x1 - 1.6, x1, z0 + 1.0, z1, 0.06)
	var mz := (z0 + z1) * 0.5
	var stx := cx - w * 0.15
	_flat_rect("gravel", stx - 6.0, stx - 2.0, mz - 0.8, mz + 0.8, 0.07, Color("#a89f8c"))
	_flat_rect("mulch", stx - 2.0, stx + 1.0, mz - 0.8, mz + 0.8, 0.07, Color("#9a4e38"))
	# Three steps up, a landing, a ramp down; rails both sides.
	for i in 3:
		_box("paint", Vector3(0.35, 0.17 * (i + 1), 1.6), Vector3(stx + 1.2 + i * 0.35, 0.085 * (i + 1), mz), CONCRETE)
	_box("paint", Vector3(1.6, 0.51, 1.6), Vector3(stx + 2.95, 0.255, mz), CONCRETE)
	var ra := Vector3(stx + 3.75, 0.51, mz)
	var rb := Vector3(stx + 9.75, 0.0, mz)
	_quad("paint", ra + Vector3(0, 0, -0.8), rb + Vector3(0, 0.02, -0.8), rb + Vector3(0, 0.02, 0.8), ra + Vector3(0, 0, 0.8), CONCRETE, [], Vector3.UP)
	for s in [-1.0, 1.0]:
		_strut(Vector3(stx + 1.0, 0.9, mz + s * 0.85), Vector3(stx + 3.75, 1.4, mz + s * 0.85), 0.05, Color("#8a8d8f"))
		_strut(Vector3(stx + 3.75, 1.4, mz + s * 0.85), rb + Vector3(0, 0.9, s * 0.85), 0.05, Color("#8a8d8f"))
	for i in 2:
		_garden_bench(Vector3(x0 + 4.0 + i * 6.0, 0, z1 + 0.6), PI)
	_bed(cx + w * 0.3, mz, 5.0)
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(cx + w * 0.3, 0, z0 + 4.5), pick[0], pick[1], 0.7])


## A corridor from a piece to the original hospital, so the campus reads as
## one building the way real ones grow: an enclosed link at ground level
## when they stand close, a glazed skybridge a floor up when farther.
func _link(bx0: float, bx1: float, bz0: float, bz1: float, h: float, col: Color) -> void:
	var oz0 := maxf(bz0, _main[2])
	var oz1 := minf(bz1, _main[3])
	var ox0 := maxf(bx0, _main[0])
	var ox1 := minf(bx1, _main[1])
	var a := 0.0
	var b := 0.0
	var mid := 0.0
	var along_x := oz1 - oz0 >= 6.0
	if along_x:
		mid = (oz0 + oz1) * 0.5
		if bx0 >= _main[1]:
			a = _main[1]
			b = bx0
		elif bx1 <= _main[0]:
			a = bx1
			b = _main[0]
	elif ox1 - ox0 >= 6.0:
		mid = (ox0 + ox1) * 0.5
		if bz0 >= _main[3]:
			a = _main[3]
			b = bz0
		elif bz1 <= _main[2]:
			a = bz1
			b = _main[2]
	var gap := b - a
	if gap < 0.5 or gap > 45.0:
		return
	var low := gap <= 14.0 or h < 8.0
	if low and gap > 14.0:
		return
	var y0 := 0.0 if low else 4.6
	# Never through another building; a skybridge only over low ones.
	var f := [a, b, mid - 2.1, mid + 2.1] if along_x else [mid - 2.1, mid + 2.1, a, b]
	for r in _rects:
		var inside: bool = bx0 >= r[0] - 0.1 and bx1 <= r[1] + 0.1 and bz0 >= r[2] - 0.1 and bz1 <= r[3] + 0.1
		if inside:
			continue
		if r[0] + 3.0 < f[1] and r[1] - 3.0 > f[0] and r[2] + 3.0 < f[3] and r[3] - 3.0 > f[2]:
			if low or float(r[4]) + 0.8 > y0:
				return
	var ch := 4.0 if low else 3.8
	var cw := 4.2
	var mp := (a + b) * 0.5
	var c := Vector3(mp, y0 + ch * 0.5, mid) if along_x else Vector3(mid, y0 + ch * 0.5, mp)
	var size := Vector3(gap, ch, cw) if along_x else Vector3(cw, ch, gap)
	_box("paint", size, c, col)
	var cap := Vector3(gap, 0.35, cw + 0.3) if along_x else Vector3(cw + 0.3, 0.35, gap)
	_box("paint", cap, c + Vector3(0, ch * 0.5, 0), Color("#cfcbc2"))
	for s in [-1.0, 1.0]:
		var out := Vector3(0, 0, s) if along_x else Vector3(s, 0, 0)
		var pc := c + out * (cw * 0.5 + 0.03)
		pc.y = y0 + ch * 0.55
		_glass(pc, Vector3.UP.cross(out), gap - 0.8, ch * 0.6, 0.0)


# ---------------------------------------------------------------- nursing home

func _nursing_home(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38", "#c9c1ae"]))
	var trim := Color(_pick(["#efede6", "#d9d3c3"]))
	var w := 42.0
	var d := 12.0
	var zf := front + 16.0
	var h := 3.6
	# The front wing with the lobby, and a wing back toward the garden.
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, zf + d * 0.5, h, h + 0.6, brick)
	_slab(-w * 0.5 + 6.0, 12.0, zf + d, 16.0)
	_flat_roofed_at("brick", -w * 0.5 + 6.0, 12.0, 16.0, zf + d + 8.0, h, h + 0.6, brick)
	_window_row(-11.0, zf, 16.0, 1.6, 1.3, 5, trim)
	_window_row(11.0, zf, 16.0, 1.6, 1.3, 5, trim)
	_window_row(0.0, zf + d, w - 14.0, 1.6, 1.3, 8, trim, Vector3.BACK)
	_window_row(-w * 0.5, zf + d * 0.5, d - 3.0, 1.6, 1.3, 3, trim, Vector3.RIGHT * -1.0)
	_window_row(w * 0.5, zf + d * 0.5, d - 3.0, 1.6, 1.3, 3, trim, Vector3.RIGHT)
	_window_row(-w * 0.5, zf + d + 8.0, 13.0, 1.6, 1.3, 4, trim, Vector3.RIGHT * -1.0)
	_window_row(-w * 0.5 + 12.0, zf + d + 8.0, 13.0, 1.6, 1.3, 4, trim, Vector3.RIGHT)
	# A covered drop-off at the lobby.
	_vestibule(0.0, zf, 4.0, 2.4, h - 0.4)
	_box("paint", Vector3(7.0, 0.4, 6.0), Vector3(0, 3.4, zf - 3.0), trim)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.35, 3.2, 0.35), Vector3(s * 3.2, 1.6, zf - 5.6), trim)
	_flat_rect("drive", -3.6, 3.6, zf - 6.0, zf, 0.09)
	_civic_sign(Vector3(0, h - 0.05, zf - 2.5), 4.0, 0.45, "HEALTH & REHABILITATION", "#2f4a3a", "#f2efe6", "serif")
	_parking(-23.0, 23.0, front + 0.3, zf - 6.0, to_curb, -16.0)
	_rooftop_units(0.0, w, zf, d, h + 0.6, 3)
	# The garden out back: a path loop and benches.
	_flat_rect("drive", -6.0, 20.0, zf + d + 6.0, zf + d + 7.2, 0.06)
	for i in 3:
		var x := -2.0 + i * 8.0
		_box("paint", Vector3(1.6, 0.45, 0.5), Vector3(x, 0.45, zf + d + 8.2), Color("#6b4a2e"))
		_bed(x, zf + d + 4.5, 3.0)
	for i in 3:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(6.0 + i * 7.0, 0, zf + d + 12.0), pick[0], pick[1], rng.randf_range(0.7, 0.95)])


# ---------------------------------------------------------------- daycare

func _daycare(front: float, to_curb: float) -> void:
	var siding := Color(_pick(["#c9c3b3", "#d8d2c2", "#e9e6dc", "#9aa3a8"]))
	var trim := Color("#efede6")
	var w := 20.0
	var d := 11.0
	var zf := front + 11.0
	var h := 3.4
	_slab(-3.0, w, zf, d)
	_flat_roofed_at("siding", -3.0, w, d, zf + d * 0.5, h, h + 0.5, siding)
	_box("paint", Vector3(w + 0.06, 0.5, d + 0.06), Vector3(-3.0, h - 0.2, zf + d * 0.5), Color(_pick(["#2f5a8a", "#b83a2a", "#3a7a4a"])))
	_entry(-6.0, zf, trim)
	_window_row(2.0, zf, 8.0, 1.4, 1.2, 3, trim)
	_window_row(-12.0, zf, 4.0, 1.4, 1.2, 1, trim)
	_civic_sign(Vector3(1.0, h - 0.15, zf - 0.14), 5.0, 0.55, "CHILD CARE", "#2a6a9a", "#f2efe6", "franklin")
	_parking(-14.5, 14.5, front + 0.3, zf - 2.0, to_curb, -9.0)
	_flat_rect("drive", -8.0, -4.0, zf - 2.0, zf, 0.08)
	# The fenced play yard beside and behind it.
	var y0 := zf + d + 0.5
	_flat_rect("mulch", -12.0, 14.0, y0, front + 31.5, 0.05, Color("#8a6a48"))
	_fence(Vector2(-12.5, y0 - 0.2), Vector2(14.5, front + 31.8), 1.4)
	_play_set(Vector3(-4.0, 0, y0 + 4.5))
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(11.0, 0, y0 + 3.0), pick[0], pick[1], 0.8])


# ---------------------------------------------------------------- growth

## A nursing home's or daycare's added pieces (Stations), each on its strip
## behind the first lot (CivicBuilder._station_upgrades calls this).
func _care_piece(key: String, w: float, z: float, g: float) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38", "#c9c1ae"]))
	var siding := Color(_pick(["#c9c3b3", "#d8d2c2", "#e9e6dc", "#9aa3a8"]))
	var trim := Color(_pick(["#efede6", "#d9d3c3"]))
	var roof := Color(_pick(["#4a4a4c", "#5a4a3e", "#3e4448"]))
	match key:
		"therapy_gym":
			# A one-storey therapy wing with tall windows, and the outdoor
			# practice course rehab patients walk before going home: a
			# ramp, three steps and a curb.
			var ww := 24.0
			var x := -w * 0.5 + 4.0 + ww * 0.5
			var wd := g - 4.0
			_slab(x, ww, z + 1.0, wd)
			_flat_roofed_at("brick", x, ww, wd, z + 1.0 + wd * 0.5, 4.2, 4.8, brick)
			_window_row(x + ww * 0.5, z + 1.0 + wd * 0.5, wd - 2.0, 1.0, 2.2, 3, trim, Vector3.RIGHT)
			_rooftop_units(x, ww, z + 1.0, wd, 4.8, 1)
			var c := Vector3(x + ww * 0.5 + 7.0, 0, z + g * 0.5)
			_flat_rect("drive", c.x - 4.0, c.x + 4.0, c.z - 4.0, c.z + 4.0, 0.07)
			_box("paint", Vector3(1.2, 0.45, 3.0), c + Vector3(-2.0, 0.22, 0), CONCRETE)
			for k in 3:
				_box("paint", Vector3(1.2, 0.15 * (k + 1), 0.3), c + Vector3(1.6, 0.075 * (k + 1), -0.9 + k * 0.3), CONCRETE)
			for e in [-1.0, 1.0]:
				_box("paint", Vector3(0.05, 0.05, 3.2), c + Vector3(-2.0 + e * 0.65, 1.1, 0), GALV)
		"assisted":
			# Assisted living: two storeys under a gable roof, residential
			# windows, small balconies, its own entry canopy.
			var ww := w - 8.0
			var wd := minf(g - 6.0, 16.0)
			var zf := z + 3.0
			_slab(0.0, ww, zf, wd)
			_box("paint", Vector3(ww, 6.2, wd), Vector3(0, 3.1, zf + wd * 0.5), siding)
			_box("paint", Vector3(ww + 0.06, 1.0, wd + 0.06), Vector3(0, 0.5, zf + wd * 0.5), brick)
			_gable_roof(0.0, zf + wd * 0.5, 6.2, wd, 3.0, ww, true, roof, siding)
			for f in 2:
				_window_row(0.0, zf, ww - 4.0, 1.0 + f * 3.0, 1.4, int(ww / 4.0), trim)
				_window_row(0.0, zf + wd, ww - 4.0, 1.0 + f * 3.0, 1.4, int(ww / 4.0), trim, Vector3.BACK)
			for k in int(ww / 8.0):
				var bx := -ww * 0.5 + 4.0 + k * 8.0
				_box("paint", Vector3(2.6, 0.15, 1.2), Vector3(bx, 3.1, zf + wd + 0.6), trim)
				_box("paint", Vector3(2.6, 0.9, 0.05), Vector3(bx, 3.6, zf + wd + 1.2), Color("#3a3c3e"))
			_box("paint", Vector3(5.0, 0.35, 3.0), Vector3(ww * 0.25, 3.0, zf - 1.5), trim)
			_flat_rect("drive", ww * 0.25 - 1.5, ww * 0.25 + 1.5, z, zf, 0.08)
		"memory_care":
			# Memory care: a one-storey wing round a secure courtyard
			# garden with a looping path (no dead ends, by design).
			var ww := w - 10.0
			var wd := 9.0
			_slab(0.0, ww, z + 1.0, wd)
			_flat_roofed_at("brick", 0.0, ww, wd, z + 1.0 + wd * 0.5, 3.6, 4.2, brick)
			_window_row(0.0, z + 1.0 + wd, ww - 4.0, 1.0, 1.3, int(ww / 3.5), trim, Vector3.BACK)
			var g0 := z + 1.0 + wd
			var g1 := z + g - 1.0
			for e in [[Vector3(-ww * 0.5, 0, g0), Vector3(-ww * 0.5, 0, g1)], [Vector3(ww * 0.5, 0, g0), Vector3(ww * 0.5, 0, g1)],
					[Vector3(-ww * 0.5, 0, g1), Vector3(ww * 0.5, 0, g1)]]:
				_fence_run(e[0], e[1], 1.8)
			var cz := (g0 + g1) * 0.5
			var rx := ww * 0.5 - 3.0
			var rz := (g1 - g0) * 0.5 - 1.6
			for i in 16:
				var a := TAU * i / 16.0
				var b := TAU * (i + 1) / 16.0
				var p := Vector3(cos(a) * rx, 0, cz + sin(a) * rz)
				var q := Vector3(cos(b) * rx, 0, cz + sin(b) * rz)
				_flat_rect("drive", minf(p.x, q.x) - 0.6, maxf(p.x, q.x) + 0.6, minf(p.z, q.z) - 0.6, maxf(p.z, q.z) + 0.6, 0.06 + (i % 2) * 0.004)
			_bed(0.0, cz, 4.0)
			_box("paint", Vector3(3.0, 2.6, 3.0), Vector3(rx * 0.4, 1.3, cz), Color(trim), Basis.IDENTITY)
			_box("paint", Vector3(3.6, 0.2, 3.6), Vector3(rx * 0.4, 2.7, cz), roof)
		"cottages":
			# Independent living: brick duplex cottages with a garage each
			# and a front porch, along a private drive.
			_flat_rect("asphalt", -w * 0.5 + 1.0, w * 0.5 - 1.0, z + 0.5, z + 6.0, 0.06)
			var n := maxi(1, int((w - 4.0) / 22.0))
			for k in n:
				var cx := -w * 0.5 + 2.0 + (k + 0.5) * (w - 4.0) / n
				var cd := 10.0
				var cw := 18.0
				var zf := z + 8.0
				_slab(cx, cw, zf, cd)
				_box("paint", Vector3(cw, 2.8, cd), Vector3(cx, 1.4, zf + cd * 0.5), brick)
				_gable_roof(cx, zf + cd * 0.5, 2.8, cd, 2.2, cw, true, roof, siding)
				for e in [-1.0, 1.0]:
					_box("paint", Vector3(2.7, 2.2, 0.06), Vector3(cx + e * 6.0, 1.1, zf - 0.03), Color("#e6e3da"))
					_flat_rect("drive", cx + e * 6.0 - 1.6, cx + e * 6.0 + 1.6, z + 6.0, zf, 0.08)
					_glass(Vector3(cx + e * 2.0, 1.5, zf - 0.03), Vector3(-1, 0, 0), 1.2, 1.2, 0.3)
				var pick := TreeField.pick(rng, true)
				trees.append([Vector3(cx, 0, zf + cd + 3.0), pick[0], pick[1], rng.randf_range(0.6, 0.8)])
		"infant_room":
			# An infant and toddler room, and its own small fenced yard of
			# rubber tiles (Indiana licensing keeps under-threes apart).
			var ww := 12.0
			var x := -w * 0.5 + 2.0 + ww * 0.5
			var wd := g - 3.0
			_slab(x, ww, z + 1.0, wd)
			_flat_roofed_at("siding", x, ww, wd, z + 1.0 + wd * 0.5, 3.2, 3.7, siding)
			_window_row(x + ww * 0.5, z + 1.0 + wd * 0.5, wd - 2.0, 0.9, 1.2, 2, trim, Vector3.RIGHT)
			var y0 := x + ww * 0.5 + 1.0
			_flat_rect("mulch", y0, w * 0.5 - 1.0, z + 1.0, z + g - 1.0, 0.05, Color("#4a6a8a"))
			_fence(Vector2(y0 - 0.2, z + 0.8), Vector2(w * 0.5 - 0.8, z + g - 0.8), 1.2)
			_box("paint", Vector3(1.6, 0.5, 1.6), Vector3(y0 + 3.0, 0.25, z + g * 0.5), Color("#d9a92a"))
		"school_age":
			# A before- and after-school room and a half-court.
			var ww := 14.0
			var x := w * 0.5 - 2.0 - ww * 0.5
			var wd := g - 3.0
			_slab(x, ww, z + 1.0, wd)
			_flat_roofed_at("siding", x, ww, wd, z + 1.0 + wd * 0.5, 3.4, 3.9, siding)
			_window_row(x - ww * 0.5, z + 1.0 + wd * 0.5, wd - 2.0, 1.0, 1.2, 2, trim, Vector3.LEFT)
			var c0 := -w * 0.5 + 1.0
			var c1 := x - ww * 0.5 - 1.0
			_flat_rect("asphalt", c0, c1, z + 1.0, z + g - 1.0, 0.06)
			_hoop(Vector3((c0 + c1) * 0.5, 0, z + 1.8))
		"garden":
			# An outdoor classroom: raised beds under a shade sail.
			for k in 4:
				_box("wood", Vector3(3.0, 0.45, 1.2), Vector3(-w * 0.5 + 4.0 + k * 3.8, 0.22, z + 2.5), Color("#8a6a48"))
				_box("paint", Vector3(2.8, 0.06, 1.0), Vector3(-w * 0.5 + 4.0 + k * 3.8, 0.47, z + 2.5), Color("#4a6a2a"))
			for e in [-1.0, 1.0]:
				_box("paint", Vector3(0.12, 3.2, 0.12), Vector3(e * 6.0, 1.6, z + g - 1.5), GALV)
			_box("paint", Vector3(12.0, 0.04, 4.0), Vector3(0, 2.9, z + g - 3.0), Color("#e6e1d0"), Basis(Vector3.RIGHT, 0.12))
