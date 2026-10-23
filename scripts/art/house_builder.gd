class_name HouseBuilder
extends RefCounted
## Builds a realistic Midwestern house from a seed, so no two are the same.
## Ported from the art thread's house generator, which was tuned in rounds
## against real photos of Midwestern streets. What it copies:
##   - three common types: the one-storey ranch (hip or gable roof, attached
##     garage, picture window), the two-storey colonial (centre door, evenly
##     spaced windows, porch or portico) and the 1960s-70s split-level (a
##     raised one-storey wing beside a two-storey block with a tuck-under
##     garage)
##   - aluminium gutters on every eave, with downspouts at the corners
##   - vinyl lap siding in the muted colours real streets have, brick
##     wainscot or full brick fronts, asphalt shingle roofs in greys and browns
##   - white trim: corner boards, window casings, sills, fascia and soffits
##   - double-hung windows with grids, blinds at different heights, shutters
##   - concrete driveways and walks, mulch beds and foundation shrubs
## Local space: x across the lot, y up, -z toward the street. z = 0 is the
## lot's street edge (just behind the sidewalk), or the rear pad of a flag
## lot. Houses fit the lot they're given: narrow lots get a narrower house
## and a one-car garage, wide ones a bigger house and sometimes three bays.
## Output is two meshes: the house (casts shadows) and the flat ground work.

const SIDING := ["#c9c3b3", "#d8d2c2", "#9aa3a8", "#6f7f8c", "#e9e6dc", "#b8a98c",
	"#7d8a74", "#8c8f8a", "#cdc3ab", "#a39783", "#e4e1d6", "#8a9aa6"]
const SHUTTER := ["#1c1d1f", "#22324a", "#2f4632", "#5a2626", "", ""]
const DOOR := ["#1f2d3d", "#7a1f1f", "#1c1d1f", "#2f4632", "#6b4a2e", "#f3f1ea", "#3c5a6e"]
const ROOF := ["#7a7874", "#86857f", "#8f8d88", "#6e6d6a", "#5c5c5e", "#76665a", "#6f6b66"]
const BRICK := ["#8a4a38", "#9b5a42", "#7a4234", "#a8775c", "#b59a7c"]
const TRIM := Color("#efede6")
const SOFFIT := Color("#b9b6ad")
const FOUNDATION := Color("#9d9a92")
const SHRUB := [Color("#2f4a24"), Color("#3a5a2a"), Color("#29401f"), Color("#4a5e2c")]
const MULCH := Color("#4a3426")
const LOT_HALF := 10.0  # half a lot's width when no lot is given

## The lot, in local space: half its width, how far back it runs, its
## outline (x, z), and for a flag lot how far the pad sits behind the street.
var half := LOT_HALF
var depth := 32.0
var outline := PackedVector2Array()
var pad := 0.0

var _st := {}  # material key -> SurfaceTool
var _flat := SurfaceTool.new()
## Trees this lot plants: [local position, TreeField species, tint, scale].
var trees := []
var rng: RandomNumberGenerator


## `lot` (optional): width, depth, outline (local x/z points) and pad.
## `storeys` 1 gives a ranch, 2 a colonial or split-level, 0 any of them
## (the building type's stage decides).
static func build(seed: int, to_curb: float, lot := {}, storeys := 0) -> Array:
	var b := HouseBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	return b._house(to_curb, storeys)


func _fit(lot: Dictionary) -> void:
	half = float(lot.get("width", LOT_HALF * 2.0)) * 0.5
	pad = float(lot.get("pad", 0.0))
	outline = lot.get("outline", PackedVector2Array())
	depth = float(lot.get("depth", 32.0)) - pad
	if outline.size() >= 3:
		depth = -INF
		for q in outline:
			depth = maxf(depth, q.y)


## Room across the lot for the house and garage, leaving side yards.
func _avail() -> float:
	return half * 2.0 - 3.0


## True when a spot, and a little room around it, is inside the lot.
func _in_lot(p: Vector3, margin := 1.5) -> bool:
	if outline.size() < 3:
		return absf(p.x) < half - margin and p.z < depth - margin
	for d in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		if not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z) + d, outline):
			return false
	return true


func _house(to_curb: float, storeys := 0) -> Array:
	_flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var siding := Color(_pick(SIDING))
	var roof := Color(_pick(ROOF))
	var shutter_hex: String = _pick(SHUTTER)
	var door := Color(_pick(DOOR))
	var brick_style: String = _pick(["none", "none", "wainscot", "wainscot", "full"])
	var brick := Color(_pick(BRICK))
	var gs := -1.0 if rng.randf() < 0.5 else 1.0  # which side the garage is on
	# Two-car garage mostly; one-car on narrow lots, three bays on wide ones.
	var gw := 6.6 if rng.randf() < 0.85 else 3.8
	if _avail() < 16.0:
		gw = 3.8
	elif _avail() >= 22.0 and rng.randf() < 0.4:
		gw = 9.8
	var zf := rng.randf_range(7.0, 9.5)  # front wall, back from the lot edge
	if depth < 30.0:
		zf = clampf(depth * 0.22, 4.5, zf)
	var shutters := shutter_hex != ""
	var shutter := Color(shutter_hex) if shutters else TRIM
	var info: Dictionary
	var kind := rng.randf()
	if storeys == 1:
		kind = 0.99
	elif storeys >= 2:
		kind *= 0.58
	if kind < 0.38:
		info = _colonial(zf, gs, gw, siding, roof, shutters, shutter, door, brick_style, brick)
	elif kind < 0.58 and _avail() >= 15.0:
		info = _split_level(zf, gs, siding, roof, shutters, shutter, door, brick_style, brick)
	else:
		info = _ranch(zf, gs, gw, siding, roof, shutters, shutter, door, brick_style, brick)
	_yard(info, to_curb)
	_yard_trees(info, to_curb)
	return [_commit_house(), _commit_flat(), trees]


# ---------------------------------------------------------------- house types

func _ranch(zf: float, gs: float, gw: float, siding: Color, roof: Color, shutters: bool,
		shutter: Color, door: Color, brick_style: String, brick: Color) -> Dictionary:
	var room := _avail() - gw
	var w := rng.randf_range(minf(10.0, room), clampf(room, 7.0, 13.0 + clampf(room - 14.0, 0.0, 3.0)))
	var d := rng.randf_range(8.4, 9.6)
	var cx := -gs * gw * 0.5
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var top := 3.1
	var gx := cx + gs * (w + gw) * 0.5
	var gz0 := zf - rng.randf_range(0.0, 1.5)  # garage front, often a little forward
	var gd := d + (zf - gz0)
	var gcz := gz0 + gd * 0.5
	_box("concrete", Vector3(w + 0.1, 0.4, d + 0.1), Vector3(cx, 0.2, cz), FOUNDATION)
	_box("siding", Vector3(w, 2.7, d), Vector3(cx, 1.75, cz), siding)
	_box("concrete", Vector3(gw + 0.05, 0.15, gd + 0.05), Vector3(gx, 0.075, gcz), FOUNDATION)
	_box("siding", Vector3(gw, 2.95, gd), Vector3(gx, 1.62, gcz), siding)
	_corners(x0, x1, zf, zf + d, 0.4, top)
	_corners(gx - gw * 0.5, gx + gw * 0.5, gz0, gz0 + gd, 0.15, top)
	if brick_style != "none":
		var bh := 2.65 if brick_style == "full" else 1.0
		_box("brick", Vector3(w + 0.03, bh, 0.12), Vector3(cx, 0.4 + bh * 0.5, zf - 0.06), brick)
		_box("paint", Vector3(w + 0.1, 0.07, 0.2), Vector3(cx, 0.4 + bh + 0.035, zf - 0.08), Color("#cfc8b6"))
	var rise := rng.randf_range(1.1, 1.7)
	if rng.randf() < 0.5:
		_hip_roof(cx, cz, top, w, d, rise, roof)
		_hip_roof(gx, gcz, top, gw, gd, rise * 0.95, roof)
	else:
		_gable_roof(cx, cz, top, d, rise, w, true, roof, siding)
		_gable_roof(gx, gcz, top, gw, rise * 0.9, gd, false, roof, siding)
	var door_x := cx + gs * rng.randf_range(1.0, 2.5)
	_stoop(door_x, zf, 2.2, 1.5, 0.35)
	var face := zf - (0.12 if brick_style == "full" else 0.0)  # window plane
	_front_door(door_x, face, 0.4, door)
	# Picture window on the far side of the door, double-hungs elsewhere.
	var pict_x := cx - gs * w * 0.22
	_window(Vector3(pict_x, 1.95, face), Vector3(-1, 0, 0), rng.randf_range(2.0, 2.6), 1.45,
		rng.randf() < 0.5, false, shutter)
	for i in 5:
		var x := lerpf(x0 + 1.2, x1 - 1.2, i / 4.0)
		if absf(x - door_x) > 1.3 and absf(x - pict_x) > 1.9:
			_window(Vector3(x, 2.0, face), Vector3(-1, 0, 0), 0.9, 1.35, true, shutters, shutter)
	var sx := cx - gs * w * 0.5
	for z in [cz - d * 0.25, cz + d * 0.25]:
		_window(Vector3(sx, 2.0, z), Vector3(0, 0, gs), 0.9, 1.35, true, false, shutter)
	_garage(gx, gz0, gw, 2.15)
	_back(x0, x1, zf + d, [2.0], 0.4)
	return {"drive_x": gx, "drive_w": gw - 0.8, "garage_z": gz0, "door_x": door_x,
		"walk_z": zf - 1.9, "front_z": zf, "x0": minf(x0, gx - gw * 0.5), "x1": maxf(x1, gx + gw * 0.5), "gs": gs}


func _colonial(zf: float, gs: float, gw: float, siding: Color, roof: Color, shutters: bool,
		shutter: Color, door: Color, brick_style: String, brick: Color) -> Dictionary:
	var room := _avail() - gw
	var w := rng.randf_range(minf(9.0, room), clampf(room, 7.2, 11.5 + clampf(room - 12.0, 0.0, 2.5)))
	var d := rng.randf_range(8.4, 9.6)
	var rise := rng.randf_range(2.0, 2.8)
	var cx := -gs * gw * 0.5
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	_box("concrete", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(cx, 0.25, cz), FOUNDATION)
	_box("siding", Vector3(w, 5.8, d), Vector3(cx, 3.4, cz), siding)
	_corners(x0, x1, zf, zf + d, 0.5, 6.3)
	_gable_roof(cx, cz, 6.3, d, rise, w, true, roof, siding)
	# Door and porch: a full-width porch, a partial one, or a small portico.
	var porch: String = _pick(["partial", "full", "portico"])
	var door_x := cx + rng.randf_range(-1.2, 1.2)
	if porch == "full":
		door_x = cx + rng.randf_range(-0.6, 0.6)
	var pw := w - 0.4 if porch == "full" else (rng.randf_range(4.5, 6.0) if porch == "partial" else 2.4)
	var px0 := x0 + 0.2 if porch == "full" else door_x - pw * 0.5
	var px1 := px0 + pw
	var pd := 1.4 if porch == "portico" else rng.randf_range(1.8, 2.4)
	if brick_style != "none":
		var bh := 3.15 if brick_style == "full" else 1.15
		for span in [[x0, px0 - 0.05], [px1 + 0.05, x1]]:
			if span[1] - span[0] > 0.3:
				_box("brick", Vector3(span[1] - span[0] + 0.03, bh, 0.12),
					Vector3((span[0] + span[1]) * 0.5, 0.5 + bh * 0.5, zf - 0.06), brick)
	_stoop((px0 + px1) * 0.5, zf, pw, pd, 0.45)
	for i in 2:
		var h := 0.3 if i == 0 else 0.15
		_box("concrete", Vector3(1.8, h, 0.4), Vector3(door_x, h * 0.5, zf - pd - 0.2 - i * 0.4), FOUNDATION)
	var posts := [px0 + 0.2, px1 - 0.2]
	if porch == "full":
		posts = [px0 + 0.2, lerpf(px0, px1, 0.36), lerpf(px0, px1, 0.64), px1 - 0.2]
	for x in posts:
		_box("paint", Vector3(0.2, 2.85, 0.2), Vector3(x, 1.88, zf - pd + 0.2), TRIM)
	_box("paint", Vector3(pw + 0.2, 0.3, 0.24), Vector3((px0 + px1) * 0.5, 3.42, zf - pd + 0.2), TRIM)
	if porch == "portico":
		_gable_roof(door_x, zf - pd * 0.5, 3.55, pw, 0.9, pd + 0.1, false, roof, TRIM, false)
	else:
		_shed_roof((px0 + px1) * 0.5, pw + 0.4, zf, pd + 0.2, 3.62, 0.5, roof)
	var face := zf - (0.12 if brick_style == "full" else 0.0)  # window plane
	_front_door(door_x, face, 0.5, door)
	# Upstairs evenly spaced; downstairs the same, skipping the door.
	var n := 5 if w > 11.0 else 4
	var ww := rng.randf_range(0.85, 1.0)
	var wh := rng.randf_range(1.35, 1.55)
	for i in n:
		var x := lerpf(x0 + 1.3, x1 - 1.3, float(i) / (n - 1))
		_window(Vector3(x, 5.0, zf), Vector3(-1, 0, 0), ww, wh, true, shutters, shutter)
		if absf(x - door_x) > 1.3:
			_window(Vector3(x, 2.45, face), Vector3(-1, 0, 0), ww, 1.5, true, shutters and porch != "full", shutter)
	var sx := cx - gs * w * 0.5
	for z in [cz - d * 0.25, cz + d * 0.25]:
		_window(Vector3(sx, 2.45, z), Vector3(0, 0, gs), ww, 1.5, true, false, shutter)
		_window(Vector3(sx, 5.0, z), Vector3(0, 0, gs), ww, wh, true, false, shutter)
	_window(Vector3(sx, 7.0, cz), Vector3(0, 0, gs), 0.55, 0.7, false, false, shutter)
	# Garage wing.
	var gx := cx + gs * (w + gw) * 0.5
	var gz0 := zf - rng.randf_range(-0.5, 1.2)
	var gd := 8.2
	var gcz := gz0 + gd * 0.5
	_box("concrete", Vector3(gw + 0.05, 0.15, gd + 0.05), Vector3(gx, 0.075, gcz), FOUNDATION)
	_box("siding", Vector3(gw, 3.0, gd), Vector3(gx, 1.65, gcz), siding)
	_corners(gx - gw * 0.5, gx + gw * 0.5, gz0, gz0 + gd, 0.15, 3.15)
	if rng.randf() < 0.6:
		_gable_roof(gx, gcz, 3.15, gw, rng.randf_range(1.6, 2.1), gd, false, roof, siding)
	else:
		_gable_roof(gx, gcz, 3.15, gd, rng.randf_range(1.6, 2.0), gw, true, roof, siding)
	_garage(gx, gz0, gw, 2.2)
	_back(x0, x1, zf + d, [2.45, 5.0], 0.5)
	if rng.randf() < 0.35:
		_box("brick", Vector3(1.0, rise + 1.6, 0.7), Vector3(x0 + 0.5 if gs > 0 else x1 - 0.5, 6.3 + (rise + 1.6) * 0.5 - 0.8, cz + d * 0.15), brick)
	return {"drive_x": gx, "drive_w": gw - 0.8, "garage_z": gz0, "door_x": door_x,
		"walk_z": zf - pd - 1.0, "front_z": zf, "x0": minf(x0, gx - gw * 0.5), "x1": maxf(x1, gx + gw * 0.5), "gs": gs}


## Split-level: a two-storey block with the garage tucked under it, beside a
## one-storey wing whose floor sits half a level up, reached by a few steps.
func _split_level(zf: float, gs: float, siding: Color, roof: Color, shutters: bool,
		shutter: Color, door: Color, brick_style: String, brick: Color) -> Dictionary:
	var tw := rng.randf_range(7.0, 8.2)  # two-storey block
	var ww := rng.randf_range(7.6, minf(9.2, _avail() - tw))  # raised wing
	var d := rng.randf_range(8.4, 9.4)
	var total := tw + ww
	var tx := gs * (total * 0.5 - tw * 0.5)
	var wx := -gs * (total * 0.5 - ww * 0.5)
	var cz := zf + d * 0.5
	var t_top := 5.6
	var w_floor := 1.2
	var w_top := 3.95
	# Two-storey block, its lower level a little below the wing's floor.
	_box("concrete", Vector3(tw + 0.1, 0.3, d + 0.1), Vector3(tx, 0.15, cz), FOUNDATION)
	_box("siding", Vector3(tw, t_top - 0.3, d), Vector3(tx, (t_top + 0.3) * 0.5, cz), siding)
	_corners(tx - tw * 0.5, tx + tw * 0.5, zf, zf + d, 0.3, t_top)
	# The wing: a high foundation, then one storey.
	_box("concrete", Vector3(ww + 0.1, w_floor, d + 0.1), Vector3(wx, w_floor * 0.5, cz), FOUNDATION)
	_box("siding", Vector3(ww, w_top - w_floor, d), Vector3(wx, (w_top + w_floor) * 0.5, cz), siding)
	_corners(wx - ww * 0.5, wx + ww * 0.5, zf, zf + d, w_floor, w_top)
	# Brick often wraps the lower level of the tall block.
	if brick_style != "none":
		_box("brick", Vector3(tw + 0.03, 2.75, 0.12), Vector3(tx, 0.3 + 1.375, zf - 0.06), brick)
		_box("paint", Vector3(tw + 0.1, 0.07, 0.2), Vector3(tx, 3.08, zf - 0.08), Color("#cfc8b6"))
	if rng.randf() < 0.5:
		_gable_roof(tx, cz, t_top, d, rng.randf_range(1.6, 2.1), tw, true, roof, siding)
	else:
		_hip_roof(tx, cz, t_top, tw, d, rng.randf_range(1.4, 1.8), roof)
	_gable_roof(wx, cz, w_top, d, rng.randf_range(1.2, 1.6), ww, true, roof, siding)
	# Tuck-under garage, upstairs windows above it.
	var gdw := minf(tw - 1.6, 4.9)
	var face := zf - (0.12 if brick_style != "none" else 0.0)
	_garage(tx, face, gdw + 1.6, 2.15)
	for i in 2:
		var x := tx + (i - 0.5) * tw * 0.45
		_window(Vector3(x, 4.3, zf), Vector3(-1, 0, 0), 0.95, 1.35, true, shutters, shutter)
	# Door at the inside end of the wing, up a few steps; windows along it.
	var door_x := wx + gs * (ww * 0.5 - 1.1)
	_stoop(door_x, zf, 1.9, 1.5, w_floor - 0.15)
	for k in [1, 2]:
		var h: float = (w_floor - 0.15) * (3 - k) / 3.0
		_box("concrete", Vector3(1.4, h, 0.32), Vector3(door_x, h * 0.5, zf - 1.66 - (k - 1) * 0.32), FOUNDATION)
	_front_door(door_x, zf, w_floor, door)
	var pict_x := wx - gs * ww * 0.12
	_window(Vector3(pict_x, w_floor + 1.5, zf), Vector3(-1, 0, 0), rng.randf_range(2.2, 2.8), 1.4,
		rng.randf() < 0.5, false, shutter)
	_window(Vector3(wx - gs * (ww * 0.5 - 1.0), w_floor + 1.55, zf), Vector3(-1, 0, 0), 0.9, 1.3, true, shutters, shutter)
	# Side and back.
	var sx := tx + gs * tw * 0.5
	_window(Vector3(sx, 1.7, cz), Vector3(0, 0, -gs), 0.9, 1.0, false, false, shutter)
	_window(Vector3(sx, 4.3, cz), Vector3(0, 0, -gs), 0.9, 1.3, true, false, shutter)
	var ex := wx - gs * ww * 0.5
	_window(Vector3(ex, w_floor + 1.55, cz), Vector3(0, 0, gs), 0.9, 1.3, true, false, shutter)
	_back(minf(wx - ww * 0.5, wx + ww * 0.5), maxf(wx - ww * 0.5, wx + ww * 0.5), zf + d, [w_floor + 1.5], w_floor)
	for i in 2:
		_window(Vector3(tx + (i - 0.5) * tw * 0.45, 4.3, zf + d), Vector3(1, 0, 0), 0.9, 1.3, true, false, TRIM)
	var x0 := -total * 0.5
	return {"drive_x": tx, "drive_w": gdw + 0.8, "garage_z": zf, "door_x": door_x,
		"walk_z": zf - 2.6, "front_z": zf, "x0": x0, "x1": x0 + total, "gs": gs}


# ---------------------------------------------------------------- parts

## Driveway, front walk, mulch beds and shrubs.
func _yard(h: Dictionary, to_curb: float) -> void:
	var dx: float = h.drive_x
	var dw: float = h.drive_w
	if pad > 0.0:
		# Flag lot: the drive runs out along the strip, then widens to the garage.
		var sx := _strip_x(-pad * 0.5)
		_flat_rect("drive", sx - 1.5, sx + 1.5, -to_curb, 0.5, 0.1)
		_flat_rect("drive", minf(sx - 1.5, dx - dw * 0.5), maxf(sx + 1.5, dx + dw * 0.5), 0.0, h.garage_z, 0.1)
	else:
		_flat_rect("drive", dx - dw * 0.5, dx + dw * 0.5, -to_curb, h.garage_z, 0.1)
	var door_x: float = h.door_x
	var walk_z: float = h.walk_z
	if rng.randf() < 0.55 and pad <= 0.0:
		_flat_rect("drive", door_x - 0.6, door_x + 0.6, -0.3, walk_z, 0.06)
	else:
		_flat_rect("drive", minf(door_x, dx) - 0.6, maxf(door_x, dx), walk_z - 1.2, walk_z, 0.06)
	# Foundation bed with shrubs along the front, skipping the garage.
	var fz: float = h.front_z
	var gs: float = h.gs
	var bed0: float = h.x0 + (7.0 if gs < 0 else 0.3)
	var bed1: float = h.x1 - (7.0 if gs > 0 else 0.3)
	if bed1 - bed0 > 1.0:
		_flat_rect("mulch", bed0, bed1, fz - 1.4, fz, 0.05)
		var x := bed0 + 0.5
		while x < bed1 - 0.4:
			if absf(x - door_x) > 1.3:
				_shrub(Vector3(x, 0.0, fz - 0.7), rng.randf_range(0.45, 0.65))
			x += rng.randf_range(0.9, 1.5)


## Back wall: a patio door and windows on each floor.
func _back(x0: float, x1: float, zb: float, floors: Array, sill: float) -> void:
	var w := x1 - x0
	var n := 3 if w < 11.0 else 4
	var slider := rng.randi_range(0, n - 1)
	for f in floors.size():
		for i in n:
			var x := lerpf(x0 + 1.4, x1 - 1.4, float(i) / (n - 1))
			if f == 0 and i == slider:
				_box("paint", Vector3(1.95, 2.25, 0.04), Vector3(x, sill + 1.1, zb), TRIM)
				_glass(Vector3(x, sill + 1.05, zb + 0.03), Vector3(1, 0, 0), 1.8, 2.1, rng.randf_range(0.0, 0.3))
				_box("concrete", Vector3(3.0, sill, 2.5), Vector3(x, sill * 0.5, zb + 1.25), FOUNDATION)
			else:
				_window(Vector3(x, floors[f], zb), Vector3(1, 0, 0), 0.9, 1.35, true, false, TRIM)


## A front-yard tree, a street tree in the parkway, and one or two out back,
## kept clear of the driveway and the house.
func _yard_trees(h: Dictionary, to_curb: float) -> void:
	var dx: float = h.drive_x
	var clear: float = h.drive_w * 0.5 + 3.0
	var spots := []
	var span := half - 2.0
	var back: float = h.front_z + 13.0
	if rng.randf() < 0.7:
		spots.append([Vector3(rng.randf_range(-span, span), 0, rng.randf_range(1.5, h.front_z - 3.5)), true])
	if rng.randf() < 0.55 and pad <= 0.0:
		spots.append([Vector3(rng.randf_range(-span, span), 0, -to_curb + 1.2), false])
	if depth - 2.0 > back:
		for i in rng.randi_range(1, 2):
			spots.append([Vector3(rng.randf_range(-span, span), 0, rng.randf_range(back, depth - 2.0)), false])
	for s in spots:
		var p: Vector3 = s[0]
		if p.z < h.front_z and absf(p.x - dx) < clear:
			continue
		# Street trees stand in the parkway, outside the lot itself.
		if p.z > 0.0 and not _in_lot(p):
			continue
		var pick := TreeField.pick(rng, s[1])
		trees.append([p, pick[0], pick[1], rng.randf_range(0.75, 1.15)])


## The middle of a flag lot's drive strip, `z` metres along it.
func _strip_x(z: float) -> float:
	if outline.size() < 3:
		return 0.0
	var xs := []
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if (a.y - z) * (b.y - z) < 0.0:
			xs.append(lerpf(a.x, b.x, (z - a.y) / (b.y - a.y)))
	if xs.size() < 2:
		return 0.0
	xs.sort()
	return (xs[0] + xs[1]) * 0.5


func _corners(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> void:
	for x in [x0, x1]:
		for z in [z0, z1]:
			_box("paint", Vector3(0.14, y1 - y0, 0.14), Vector3(x, (y0 + y1) * 0.5, z), TRIM)


func _stoop(x: float, zf: float, w: float, d: float, h: float) -> void:
	_box("concrete", Vector3(w, h, d), Vector3(x, h * 0.5, zf - d * 0.5), FOUNDATION)


func _front_door(x: float, zf: float, sill: float, c: Color) -> void:
	_box("paint", Vector3(0.95, 2.1, 0.06), Vector3(x, sill + 1.05, zf - 0.02), c)
	_box("paint", Vector3(1.25, 0.14, 0.1), Vector3(x, sill + 2.17, zf - 0.05), TRIM)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.12, 2.2, 0.1), Vector3(x + s * 0.55, sill + 1.1, zf - 0.05), TRIM)
	# Storm door glass and a porch light.
	_glass(Vector3(x, sill + 1.45, zf - 0.06), Vector3(-1, 0, 0), 0.6, 0.8, 0.0)
	_box("paint", Vector3(0.14, 0.26, 0.1), Vector3(x + 0.85, sill + 1.75, zf - 0.06), Color("#1c1c1c"))


func _garage(gx: float, gz0: float, gw: float, h: float) -> void:
	var doors := [[gx, gw - 1.7]] if gw > 5.0 else [[gx, gw - 1.2]]
	if gw > 8.0:
		doors = [[gx - gw * 0.17, gw * 0.6 - 1.2], [gx + gw * 0.33, gw * 0.3 - 0.6]]
	elif gw > 5.0 and rng.randf() < 0.25:
		doors = [[gx - gw * 0.25, gw * 0.5 - 1.0], [gx + gw * 0.25, gw * 0.5 - 1.0]]
	for dd in doors:
		# Garage doors share the siding surface; alpha 0 asks for wide panels.
		_box("siding", Vector3(dd[1], h, 0.08), Vector3(dd[0], 0.15 + h * 0.5, gz0 - 0.02), Color(TRIM, 0.0))
		_box("paint", Vector3(dd[1] + 0.3, 0.14, 0.1), Vector3(dd[0], 0.15 + h + 0.07, gz0 - 0.05), TRIM)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.18, 0.36, 0.12), Vector3(gx + s * (gw * 0.5 - 0.35), 2.2, gz0 - 0.07), Color("#1c1c1c"))


## A double-hung window centred on `c` (on the wall face), `right` along the wall.
func _window(c: Vector3, right: Vector3, w: float, h: float, grid: bool, shutters: bool, shutter: Color) -> void:
	var out := right.cross(Vector3.UP)  # points out of the wall
	var basis := Basis(right, Vector3.UP, out)
	var put := func(size: Vector3, off: Vector3, mat: String, col: Color) -> void:
		_box(mat, size, c + basis * off, col, basis)
	_glass(c + out * 0.02, right, w, h, rng.randf_range(0.1, 0.6))
	put.call(Vector3(w + 0.24, 0.12, 0.07), Vector3(0, h * 0.5 + 0.06, 0.035), "paint", TRIM)
	put.call(Vector3(0.12, h + 0.24, 0.07), Vector3(-(w * 0.5 + 0.06), 0, 0.035), "paint", TRIM)
	put.call(Vector3(0.12, h + 0.24, 0.07), Vector3(w * 0.5 + 0.06, 0, 0.035), "paint", TRIM)
	put.call(Vector3(w + 0.34, 0.07, 0.12), Vector3(0, -h * 0.5 - 0.05, 0.06), "paint", TRIM)
	put.call(Vector3(w, 0.06, 0.05), Vector3(0, 0, 0.04), "paint", TRIM)  # meeting rail
	if grid:
		for s in [-1.0, 1.0]:
			var cy: float = s * h * 0.25
			put.call(Vector3(0.025, h * 0.5 - 0.06, 0.02), Vector3(-w / 6.0, cy, 0.04), "paint", TRIM)
			put.call(Vector3(0.025, h * 0.5 - 0.06, 0.02), Vector3(w / 6.0, cy, 0.04), "paint", TRIM)
			put.call(Vector3(w, 0.025, 0.02), Vector3(0, cy, 0.04), "paint", TRIM)
	if shutters:
		for s in [-1.0, 1.0]:
			put.call(Vector3(w * 0.46, h + 0.1, 0.04), Vector3(s * (w * 0.5 + 0.16 + w * 0.23), 0, 0.03), "shutter", shutter)


## Gable roof. `ridge_x` true: the ridge runs along x and `span` is measured
## along z; false: the ridge runs along z (a gable facing the street).
func _gable_roof(cx: float, cz: float, base: float, span: float, rise: float, length: float,
		ridge_x: bool, roof: Color, gable: Color, gutters := true) -> void:
	var over := 0.45
	var rake := 0.3
	var hs := span * 0.5 + over
	var hl := length * 0.5 + rake
	var drop := rise * over / (span * 0.5)
	var to_world := func(a: float, s: float, y: float) -> Vector3:
		return Vector3(cx + a, y, cz + s) if ridge_x else Vector3(cx + s, y, cz + a)
	var slope_len := Vector2(hs, rise + drop).length()
	var up := Vector3(0, 0.12, 0)
	for side in [-1.0, 1.0]:
		var eave_l: Vector3 = to_world.call(-hl, side * hs, base - drop)
		var eave_r: Vector3 = to_world.call(hl, side * hs, base - drop)
		var ridge_l: Vector3 = to_world.call(-hl, 0.0, base + rise)
		var ridge_r: Vector3 = to_world.call(hl, 0.0, base + rise)
		var outward: Vector3 = to_world.call(0.0, side, 0.0) - to_world.call(0.0, 0.0, 0.0)
		_quad("roof", eave_l + up, eave_r + up, ridge_r + up, ridge_l + up, roof,
			[Vector2(-hl, 0), Vector2(hl, 0), Vector2(hl, slope_len), Vector2(-hl, slope_len)], Vector3.UP)
		# Underside (soffit) and the fascia board along the eave.
		_quad("paint", eave_l, eave_r, ridge_r, ridge_l, SOFFIT, [], Vector3.DOWN)
		_quad("paint", eave_l, eave_r, eave_r + Vector3(0, 0.2, 0), eave_l + Vector3(0, 0.2, 0), TRIM, [], outward)
	# Gable-end triangles in siding, and rake boards.
	for end in [-1.0, 1.0]:
		var a: float = end * length * 0.5
		var endward: Vector3 = to_world.call(end, 0.0, 0.0) - to_world.call(0.0, 0.0, 0.0)
		var l: Vector3 = to_world.call(a, -span * 0.5, base)
		var r: Vector3 = to_world.call(a, span * 0.5, base)
		var t: Vector3 = to_world.call(a, 0.0, base + rise)
		_tri("siding", l, r, t, gable, [], endward)
		for s in [-1.0, 1.0]:
			var e: Vector3 = to_world.call(end * hl, s * hs, base - drop)
			var p: Vector3 = to_world.call(end * hl, 0.0, base + rise)
			_quad("paint", e, p, p + Vector3(0, 0.14, 0) + up, e + Vector3(0, 0.14, 0) + up, TRIM, [], endward)


func _hip_roof(cx: float, cz: float, base: float, w: float, d: float, rise: float, roof: Color) -> void:
	var over := 0.5
	var hx := w * 0.5 + over
	var hz := d * 0.5 + over
	var drop := rise * over / (d * 0.5)
	var ridge := maxf(hx - hz, 0.0)
	var y0 := base - drop
	var y1 := base + rise
	var c := [Vector3(cx - hx, y0, cz - hz), Vector3(cx + hx, y0, cz - hz),
		Vector3(cx + hx, y0, cz + hz), Vector3(cx - hx, y0, cz + hz)]
	var rl := Vector3(cx - ridge, y1, cz)
	var rr := Vector3(cx + ridge, y1, cz)
	var slope := Vector2(hz, rise + drop).length()
	var end_slope := Vector2(hx - ridge, rise + drop).length()
	var up := Vector3(0, 0.12, 0)
	# Front and back trapezoids, then the two hip ends.
	var trap := [Vector2(-hx, 0), Vector2(hx, 0), Vector2(ridge, slope), Vector2(-ridge, slope)]
	_quad("roof", c[0] + up, c[1] + up, rr + up, rl + up, roof, trap, Vector3.UP)
	_quad("roof", c[2] + up, c[3] + up, rl + up, rr + up, roof, trap, Vector3.UP)
	var tri := [Vector2(-hz, 0), Vector2(hz, 0), Vector2(0, end_slope)]
	_tri("roof", c[1] + up, c[2] + up, rr + up, roof, tri, Vector3.UP)
	_tri("roof", c[3] + up, c[0] + up, rl + up, roof, tri, Vector3.UP)
	var center := Vector3(cx, y0, cz)
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		_quad("paint", a, b, b + Vector3(0, 0.2, 0), a + Vector3(0, 0.2, 0), TRIM, [], (a + b) * 0.5 - center)
	_quad("paint", c[0], c[1], c[2], c[3], SOFFIT, [], Vector3.DOWN)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(hx * 2.0 + 0.14, 0.13, 0.13), Vector3(cx, y0 + 0.03, cz + s * (hz + 0.07)), TRIM)
		_box("paint", Vector3(0.13, 0.13, hz * 2.0), Vector3(cx + s * (hx + 0.07), y0 + 0.03, cz), TRIM)
		for e in [-1.0, 1.0]:
			_downspout(Vector3(cx + e * (w * 0.5 - 0.15), 0, cz + s * (d * 0.5 + 0.06)),
				Vector3(cx + e * (w * 0.5 - 0.15), 0, cz + s * (hz + 0.07)), y0)


## A downspout down the wall at `wall` (y ignored), joined by an elbow to the
## gutter above `eave`, `top` metres up.
func _downspout(wall: Vector3, eave: Vector3, top: float) -> void:
	_box("paint", Vector3(0.08, top, 0.08), Vector3(wall.x, top * 0.5, wall.z), TRIM)
	var mid := (wall + eave) * 0.5
	var run := eave - wall
	_box("paint", Vector3(absf(run.x) + 0.08, 0.08, absf(run.z) + 0.08), Vector3(mid.x, top - 0.08, mid.z), TRIM)
	# Splash block at the foot.
	_box("concrete", Vector3(0.3, 0.05, 0.3), Vector3(wall.x + run.normalized().x * 0.3, 0.03, wall.z + run.normalized().z * 0.3), FOUNDATION)


## A porch roof sloping down toward the street.
func _shed_roof(cx: float, w: float, z0: float, run: float, y: float, drop: float, roof: Color) -> void:
	var a := Vector3(cx - w * 0.5, y + drop, z0)
	var b := Vector3(cx + w * 0.5, y + drop, z0)
	var c := Vector3(cx + w * 0.5, y, z0 - run)
	var d := Vector3(cx - w * 0.5, y, z0 - run)
	var len := Vector2(run, drop).length()
	# The roofing sits on rafters above the ceiling, never in its plane:
	# building materials are two-sided, so two faces in one plane flicker.
	var up := Vector3(0, 0.12, 0)
	_quad("roof", d + up, c + up, b + up, a + up, roof, [Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, len), Vector2(-w * 0.5, len)], Vector3.UP)
	_quad("paint", a, b, c, d, SOFFIT, [], Vector3.DOWN)
	_quad("paint", d + up, c + up, c + Vector3(0, -0.2, 0), d + Vector3(0, -0.2, 0), TRIM, [], Vector3.FORWARD)
	for e in [[a, d, Vector3.LEFT], [b, c, Vector3.RIGHT]]:
		_quad("paint", e[0], e[1], e[1] + up, e[0] + up, TRIM, [], e[2])


func _shrub(p: Vector3, r: float) -> void:
	var col: Color = SHRUB[rng.randi() % SHRUB.size()]
	var rings := 4
	var segs := 7
	var pts := []
	for i in rings + 1:
		var row := []
		var t := PI * i / rings
		for j in segs:
			var a := TAU * j / segs
			var k := r * rng.randf_range(0.82, 1.12)
			row.append(p + Vector3(sin(t) * cos(a) * k, (1.0 - cos(t)) * k * 0.8, sin(t) * sin(a) * k))
		pts.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % segs]
			var c: Vector3 = pts[i + 1][(j + 1) % segs]
			var d: Vector3 = pts[i + 1][j]
			var shade := col.darkened(0.25 * (1.0 - float(i) / rings))
			var outward := (a + c) * 0.5 - (p + Vector3(0, r * 0.8, 0))
			_tri("foliage", a, b, c, shade, [], outward)
			_tri("foliage", a, c, d, shade, [], outward)


# ---------------------------------------------------------------- geometry

func _tool(mat: String) -> SurfaceTool:
	# Plain vertex-coloured parts share one surface, to save draw calls.
	if mat == "shutter" or mat == "foliage" or mat == "concrete":
		mat = "paint"
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]


func _box(mat: String, size: Vector3, center: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3:
		return center + basis * Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1)],
		[p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1)],
		[p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1)],
		[p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1)],
		[p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1)],
	]
	for f in faces:
		_quad(mat, f[0], f[1], f[2], f[3], col)


## Adds a quad a-b-c-d (counter-clockwise seen from the front). Without
## explicit UVs, walls get (along the wall, height) in metres so lap siding
## and brick courses line up across the whole house.
func _quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uvs := [],
		want := Vector3.ZERO) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot(want) < 0.0:
		# Flip so the face looks the way the caller wants.
		var t := b
		b = d
		d = t
		n = -n
		if not uvs.is_empty():
			uvs = [uvs[0], uvs[3], uvs[2], uvs[1]]
	if uvs.is_empty():
		uvs = [_auto_uv(a, n), _auto_uv(b, n), _auto_uv(c, n), _auto_uv(d, n)]
	var st := _tool(mat)
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[i])
		st.add_vertex([a, b, c, d][i])


func _tri(mat: String, a: Vector3, b: Vector3, c: Vector3, col: Color, uvs := [],
		want := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
		if not uvs.is_empty():
			uvs = [uvs[0], uvs[2], uvs[1]]
	if uvs.is_empty():
		uvs = [_auto_uv(a, n), _auto_uv(b, n), _auto_uv(c, n)]
	var st := _tool(mat)
	for i in [0, 2, 1]:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[i])
		st.add_vertex([a, b, c][i])


static func _auto_uv(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.7:
		return Vector2(p.x, p.z)
	return Vector2(p.z if absf(n.x) > absf(n.z) else p.x, p.y)


## A window pane: UV runs 0..1 so the glass shader can draw blinds; the
## blind height rides in the vertex colour's alpha.
func _glass(c: Vector3, right: Vector3, w: float, h: float, blinds: float) -> void:
	var r := right * w * 0.5
	var u := Vector3(0, h * 0.5, 0)
	_quad("glass", c - r - u, c + r - u, c + r + u, c - r + u, Color(0.85, 0.82, 0.74, blinds),
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


## Flat ground work. Kinds (packed into vertex alpha for the yard shader):
## drive (concrete), asphalt, line (painted, in `col`), mulch or gravel (in `col`).
func _flat_rect(kind: String, x0: float, x1: float, z0: float, z1: float, y: float, col := MULCH) -> void:
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	var pts := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	for i in [0, 1, 2, 0, 2, 3]:  # clockwise seen from above
		_flat.set_normal(Vector3.UP)
		_flat.set_color(col)
		# Matches the road ribbons: distance along the drive in UV.y * 4.
		_flat.set_uv(Vector2(pts[i].x, pts[i].z) * 0.25)
		_flat.add_vertex(pts[i])


func _commit_house() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat in _st:
		_st[mat].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, HouseMaterials.get_mat(mat))
	return mesh


func _commit_flat() -> ArrayMesh:
	var mesh := _flat.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, HouseMaterials.get_mat("yard"))
	return mesh


func _pick(list: Array) -> Variant:
	return list[rng.randi() % list.size()]
