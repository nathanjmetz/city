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


## `hub` is the hospital's record from Healthcare (empty for other kinds).
static func build_care(kind: int, seed: int, size: Vector2, to_curb: float, hub := {}) -> Array:
	var b := HealthBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := -size.y * 0.5
	match kind:
		Services.Kind.HOSPITAL: b._hospital(size, to_curb, hub)
		Services.Kind.NURSING_HOME: b._nursing_home(front, to_curb)
		Services.Kind.DAYCARE: b._daycare(front, to_curb)
	return [b._commit_house(), b._commit_flat(), b.trees]


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
	_sign(Vector3(mx, h - 2.2, zf - 0.14), minf(w * 0.4, 14.0), 0.9)
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
	if hub.is_empty():
		return
	# Every building the administrator has added, on its own strip.
	for p in hub.pieces:
		if p.rect.is_empty():
			continue
		var r: Array = p.rect
		var a := Vector2(float(r[0]) - cx, float(r[1]) - cx)
		var z0 := front + float(r[2])
		var z1 := front + float(r[3])
		_piece(p.key, a.x, a.y, z0, z1, brick, eifs, trim, to_curb, front)


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
	var wall := eifs if modern and key != "rehab" else brick
	_slab(cx, w, z0 + pad, d)
	_flat_roofed_at("paint" if wall == eifs else "brick", cx, w, d, cz, h, h + 0.8, wall)
	var floors := maxi(1, int(h / 4.0))
	var out := [Vector3.FORWARD, Vector3.BACK]
	for floor in floors:
		var y := 1.8 + floor * 4.0
		for o in out:
			var zz: float = z0 + pad if o == Vector3.FORWARD else z1 - pad
			if modern:
				# Curtain wall bands: a strip of glass every floor.
				_glass(Vector3(cx, y + 0.2, zz + o.z * 0.03), -Vector3(-o.z, 0, o.x), w - 2.0, 2.2, 0.15)
			else:
				_window_row(cx, zz, w - 4.0, y, 1.4, int(w / 3.2), trim, o)
		for s in [-1.0, 1.0]:
			var side := Vector3(s, 0, 0)
			if modern:
				_glass(Vector3(cx + s * (w * 0.5 + 0.03), y + 0.2, cz), Vector3(0, 0, s), d - 2.0, 2.2, 0.15)
			else:
				_window_row(cx + s * w * 0.5, cz, d - 4.0, y, 1.4, int(d / 3.4), trim, side)
	_rooftop_units(cx, w, z0 + pad, d, h, 1 + int(w * d / 900.0))
	if key == "er":
		# The ambulance canopy and the red EMERGENCY sign over the bays.
		var ez := z0 + pad
		_box("paint", Vector3(minf(w, 14.0), 0.5, 7.0), Vector3(cx, 4.6, ez - 3.5), eifs)
		for s in [-1.0, 1.0]:
			_box("paint", Vector3(0.4, 4.4, 0.4), Vector3(cx + s * (minf(w, 14.0) * 0.5 - 0.5), 2.2, ez - 6.8), eifs)
		_box("paint", Vector3(minf(w * 0.6, 9.0), 0.8, 0.12), Vector3(cx, 5.3, ez - 7.05), ER_RED)
		_flat_rect("drive", cx - 7.0, cx + 7.0, ez - 7.0, ez, 0.1)
		for i in 2:
			_overhead_door(cx - 3.0 + i * 6.0, ez, 3.6, 3.4, WHITE)
	else:
		_entry(cx, z0 + pad, trim)
		_flat_rect("drive", cx - 2.0, cx + 2.0, z0, z0 + pad, 0.09)
	if h >= 12.0:
		_sign(Vector3(cx, h - 1.8, z0 + pad - 0.14), minf(w * 0.35, 12.0), 0.9)
	# Ground around it: lawn with a few trees at the corners.
	for i in 2:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(x0 + 1.5 if i == 0 else x1 - 1.5, 0, z1 - 1.5), pick[0], pick[1], rng.randf_range(0.6, 0.85)])


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
	_sign(Vector3(0, h - 0.05, zf - 2.5), 4.0, 0.45)
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
	_sign(Vector3(1.0, h - 0.15, zf - 0.14), 5.0, 0.55)
	_parking(-14.5, 14.5, front + 0.3, zf - 2.0, to_curb, -9.0)
	_flat_rect("drive", -8.0, -4.0, zf - 2.0, zf, 0.08)
	# The fenced play yard beside and behind it.
	var y0 := zf + d + 0.5
	_flat_rect("mulch", -12.0, 14.0, y0, 15.5, 0.05, Color("#8a6a48"))
	_fence(Vector2(-12.5, y0 - 0.2), Vector2(14.5, 15.8), 1.4)
	_play_set(Vector3(-4.0, 0, y0 + 4.5))
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(11.0, 0, y0 + 3.0), pick[0], pick[1], 0.8])
