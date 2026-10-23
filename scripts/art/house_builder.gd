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
const SHRUB := [Color("#41633a"), Color("#4c6f35"), Color("#3a5a32"), Color("#5c7238")]  # yew, boxwood, arborvitae, spirea
const MULCH := Color("#4a3426")
const LOT_HALF := 10.0  # half a lot's width when no lot is given
## House types by the era a street was built in. Before the war: American
## four-squares, Craftsman bungalows, I-houses, gabled-ell farmhouses and the
## first Cape Cods, with detached garages out back. Postwar: Capes, ranches,
## split-levels and mid-century moderns. Recent: colonials, ranches, splits.
const ERA_TYPES := {
	"prewar": ["foursquare", "foursquare", "bungalow", "bungalow", "bungalow", "i_house", "farmhouse", "cape"],
	"postwar": ["cape", "cape", "ranch", "ranch", "ranch", "split", "midcentury", "midcentury"],
	"recent": ["colonial", "colonial", "colonial", "ranch", "ranch", "split"],
}
## Lot room (see _avail) each old type needs beside its side drive.
## Types with one storey (or a storey and a half under the roof).
const ONE_STOREY := ["ranch", "midcentury", "bungalow", "cape"]
const OLD_MIN_WIDTH := {"foursquare": 11.5, "bungalow": 11.0, "i_house": 15.5, "farmhouse": 17.0, "cape": 12.0}
const CLAPBOARD_WHITE := Color("#f1efe8")

## The lot, in local space: half its width, how far back it runs, its
## outline (x, z), and for a flag lot how far the pad sits behind the street.
var half := LOT_HALF
var depth := 32.0
var outline := PackedVector2Array()
var pad := 0.0
var era := "recent"
## Set by the art gallery to draw one type.
static var force_kind := ""

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
	# The era comes from where the lot is, in blocks of about a quarter mile.
	if lot.has("era"):
		era = lot.era
	elif lot.has("at"):
		var at: Vector2 = lot.at
		var cell := Vector2i(floori(at.x / 400.0), floori(at.y / 400.0))
		era = ["prewar", "postwar", "postwar", "recent", "recent"][posmod(hash(cell), 5)]
	else:
		era = _pick(["prewar", "postwar", "recent"])
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
	# Streets are built in one era, so neighbours share a family of types.
	# A lot owner who asked for one or two storeys gets a type that has them.
	var pool: Array = ERA_TYPES[era]
	if storeys == 1:
		pool = pool.filter(func(k): return k in ONE_STOREY)
		if pool.is_empty():
			pool = ["ranch"]
	elif storeys >= 2:
		pool = pool.filter(func(k): return not k in ONE_STOREY)
		if pool.is_empty():
			pool = ["colonial"]
	var kind: String = force_kind if force_kind != "" else _pick(pool)
	var old_house := kind in ["foursquare", "bungalow", "i_house", "farmhouse", "cape"]
	if old_house and _avail() < OLD_MIN_WIDTH.get(kind, 0.0):
		kind = "colonial" if storeys >= 2 else ("cape" if _avail() >= OLD_MIN_WIDTH.cape else "ranch")
	if kind == "split" and _avail() < 15.0:
		kind = "colonial" if storeys >= 2 else "ranch"
	match kind:
		"colonial": info = _colonial(zf, gs, gw, siding, roof, shutters, shutter, door, brick_style, brick)
		"split": info = _split_level(zf, gs, siding, roof, shutters, shutter, door, brick_style, brick)
		"foursquare": info = _foursquare(zf, gs, siding, roof, shutter, door, brick)
		"bungalow": info = _bungalow(zf, gs, siding, roof, door, brick)
		"i_house": info = _i_house(zf, gs, roof, shutter, door, brick)
		"farmhouse": info = _ell_farmhouse(zf, gs, roof, door)
		"cape": info = _cape(zf, gs, siding, roof, shutters, shutter, door)
		"midcentury": info = _midcentury(zf, gs, gw, roof, door, brick)
		_: info = _ranch(zf, gs, gw, siding, roof, shutters, shutter, door, brick_style, brick)
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
		_box("brick", Vector3(w + 0.03, bh, 0.14), Vector3(cx, 0.4 + bh * 0.5, zf - 0.05), brick)
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
				_box("brick", Vector3(span[1] - span[0] + 0.03, bh, 0.14),
					Vector3((span[0] + span[1]) * 0.5, 0.5 + bh * 0.5, zf - 0.05), brick)
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
		_box("brick", Vector3(1.0, rise + 1.6, 0.7), Vector3(x0 + 0.53 if gs > 0 else x1 - 0.53, 6.3 + (rise + 1.6) * 0.5 - 0.8, cz + d * 0.15), brick)
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
		_box("brick", Vector3(tw + 0.03, 2.75, 0.14), Vector3(tx, 0.3 + 1.375, zf - 0.05), brick)
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


# ---------------------------------------------------------------- older and postwar types

## Where an older house sits: pushed to one side, leaving a side drive on
## `gs` that runs past it to a detached garage out back (or a parking pad
## when the lot is too shallow). Returns [house centre x, drive centre x].
func _side_drive(w: float, gs: float) -> Array:
	var room := _avail()
	var cx := -gs * minf(1.9, (room - w) * 0.5 - 0.2)
	var dx := cx + gs * (w * 0.5 + 1.9)
	return [cx, dx]


## A detached garage at the back of the lot, door to the street, on the
## drive. Older garages are smaller: one bay, or two on a wide lot.
func _back_garage(dx: float, zb: float, siding: Color, roof: Color) -> Dictionary:
	var gw := 3.6 if _avail() < 14.0 or rng.randf() < 0.45 else 6.2
	var gd := 6.4
	var gz0 := zb + rng.randf_range(2.5, 4.0)
	if gz0 + gd > depth - 1.0:
		# No room out back: the drive just ends beside the house.
		return {"garage_z": zb - 1.0, "keep_out": Rect2(dx - 1.6, zb - 1.0, 3.2, 1.0)}
	var gx := clampf(dx, -half + gw * 0.5 + 0.6, half - gw * 0.5 - 0.6)
	var gcz := gz0 + gd * 0.5
	_box("concrete", Vector3(gw + 0.1, 0.15, gd + 0.1), Vector3(gx, 0.075, gcz), FOUNDATION)
	_box("siding", Vector3(gw, 2.5, gd), Vector3(gx, 1.4, gcz), siding)
	_corners(gx - gw * 0.5, gx + gw * 0.5, gz0, gz0 + gd, 0.15, 2.65)
	_gable_roof(gx, gcz, 2.65, gw, rng.randf_range(1.3, 1.8), gd, false, roof, siding)
	_garage(gx, gz0, gw, 2.0)
	return {"garage_z": gz0, "keep_out": Rect2(gx - gw * 0.5, gz0, gw, gd)}


## A gabled dormer standing on a roof whose eave wall top is `base`, its
## face `zd`, reaching back to `zr` (the ridge line).
func _dormer(x: float, zd: float, zr: float, base: float, top: float, w: float,
		siding: Color, roof: Color, shutter: Color) -> void:
	_box("siding", Vector3(w, top - base, zr - zd), Vector3(x, (base + top) * 0.5, (zd + zr) * 0.5), siding)
	_corners(x - w * 0.5, x + w * 0.5, zd, zd + 0.2, top - 1.2, top)
	_gable_roof(x, (zd + zr) * 0.5 - 0.15, top, w, w * 0.42, zr - zd + 0.3, false, roof, siding, false)
	_window(Vector3(x, top - 0.75, zd), Vector3(-1, 0, 0), minf(0.8, w - 0.6), 1.0, true, false, shutter)


## A brick chimney up the outside of a gable end.
func _chimney(x: float, z: float, top: float, brick: Color, outward: float) -> void:
	_box("brick", Vector3(0.6, top, 1.0), Vector3(x + outward * 0.28, top * 0.5, z), brick)
	_box("paint", Vector3(0.7, 0.1, 1.1), Vector3(x + outward * 0.3, top + 0.05, z), FOUNDATION)


## American four-square, 1900-1930: a two-storey box nearly as deep as it is
## wide, a hipped roof with a front dormer, a full-width porch with square
## columns, the door off to one side. Clapboard or brick.
func _foursquare(zf: float, gs: float, siding: Color, roof: Color, shutter: Color,
		door: Color, brick: Color) -> Dictionary:
	var w := rng.randf_range(8.4, minf(9.6, _avail() - 3.6))
	var d := rng.randf_range(8.6, 9.6)
	var at := _side_drive(w, gs)
	var cx: float = at[0]
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var top := 6.5
	var wall := "brick" if rng.randf() < 0.35 else "siding"
	var wall_col := brick if wall == "brick" else siding
	_box("concrete", Vector3(w + 0.1, 0.7, d + 0.1), Vector3(cx, 0.35, cz), FOUNDATION)
	_box(wall, Vector3(w, top - 0.7, d), Vector3(cx, (top + 0.7) * 0.5, cz), wall_col)
	if wall == "siding":
		_corners(x0, x1, zf, zf + d, 0.7, top)
	var rise := rng.randf_range(2.4, 2.9)
	_hip_roof(cx, cz, top, w, d, rise, roof)
	# Hipped roofs: the front slope starts at the eave and climbs toward the
	# middle; the dormer sits on it, centred.
	_dormer(cx, zf + 0.9, cz, top - 0.2, top + 1.6, 2.6, siding if wall == "siding" else TRIM, roof, shutter)
	# Full-width porch on brick piers.
	var pd := rng.randf_range(2.4, 2.8)
	var door_x := cx + gs * w * 0.27
	_stoop(cx, zf, w, pd, 0.65)
	for i in 2:
		_box("concrete", Vector3(1.6, 0.65 - 0.22 * (i + 1), 0.35),
			Vector3(door_x, (0.65 - 0.22 * (i + 1)) * 0.5, zf - pd - 0.17 - i * 0.35), FOUNDATION)
	for x in [x0 + 0.25, cx - w * 0.17, cx + w * 0.17, x1 - 0.25]:
		_box("brick", Vector3(0.5, 0.9, 0.5), Vector3(x, 1.1, zf - pd + 0.3), brick)
		_box("paint", Vector3(0.3, 1.9, 0.3), Vector3(x, 2.5, zf - pd + 0.3), TRIM)
	_box("paint", Vector3(w + 0.2, 0.3, 0.3), Vector3(cx, 3.6, zf - pd + 0.3), TRIM)
	_box("paint", Vector3(w - 0.3, 0.08, 0.08), Vector3(cx, 1.55, zf - pd + 0.3), TRIM)  # porch rail
	_shed_roof(cx, w + 0.4, zf, pd + 0.3, 3.75, 0.45, roof)
	_front_door(door_x, zf, 0.7, door)
	# Downstairs a wide window beside the door; upstairs two pairs.
	_window(Vector3(cx - gs * w * 0.18, 2.3, zf), Vector3(-1, 0, 0), 1.8, 1.6, false, false, shutter)
	for s in [-1.0, 1.0]:
		var x: float = cx + s * w * 0.25
		_window(Vector3(x - 0.5, 4.9, zf), Vector3(-1, 0, 0), 0.8, 1.45, false, false, shutter)
		_window(Vector3(x + 0.5, 4.9, zf), Vector3(-1, 0, 0), 0.8, 1.45, false, false, shutter)
		for f in [2.3, 4.9]:
			_window(Vector3(cx + s * w * 0.5, f, cz + d * 0.2 * s), Vector3(0, 0, -s), 0.85, 1.5, false, false, shutter)
	_back(x0, x1, zf + d, [2.3, 4.9], 0.7)
	var g := _back_garage(at[1], zf + d, siding, roof)
	return {"drive_x": at[1], "drive_w": 2.8, "garage_z": g.garage_z, "door_x": door_x,
		"walk_z": zf - pd - 0.9, "front_z": zf - pd, "x0": x0, "x1": x1, "gs": gs,
		"bed": [x0 + 0.3, x1 - 0.3], "keep_out": g.keep_out}


## Craftsman bungalow, 1910-1930: one and a half storeys with the gable to
## the street, a deep front porch under its own gable on tapered columns
## standing on brick piers, exposed rafter tails, paired windows.
func _bungalow(zf: float, gs: float, siding: Color, roof: Color, door: Color, brick: Color) -> Dictionary:
	var w := rng.randf_range(7.6, minf(9.0, _avail() - 3.6))
	var d := rng.randf_range(11.5, minf(13.5, depth - zf - 9.0))
	var at := _side_drive(w, gs)
	var cx: float = at[0]
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var top := 3.6
	var trim := Color(_pick(["#efede6", "#d9cfb6", "#5b4a38", "#2f4632"]))
	_box("brick", Vector3(w + 0.1, 0.75, d + 0.1), Vector3(cx, 0.375, cz), brick)
	_box("siding", Vector3(w, top - 0.75, d), Vector3(cx, (top + 0.75) * 0.5, cz), siding)
	_corners(x0, x1, zf, zf + d, 0.75, top)
	var rise := w * 0.5 * rng.randf_range(0.5, 0.62)
	_gable_roof(cx, cz, top, w, rise, d, false, roof, siding)
	# Knee braces under the gable eaves.
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.12, 0.12, 0.7), Vector3(cx + s * w * 0.32, top - 0.25, zf - 0.3), trim)
	_window(Vector3(cx, top + rise * 0.45, zf), Vector3(-1, 0, 0), 1.4, 0.8, true, false, trim)
	# Porch: full width or most of it, gable to the street.
	var pw := w if rng.randf() < 0.6 else w * 0.65
	var pcx := cx if pw >= w else cx + gs * (w - pw) * 0.5
	var pd := rng.randf_range(2.6, 3.0)
	_stoop(pcx, zf, pw, pd, 0.75)
	var door_x := pcx + gs * pw * 0.12
	for i in 3:
		var h := 0.75 - 0.2 * (i + 1)
		_box("concrete", Vector3(1.5, h, 0.32), Vector3(door_x, h * 0.5, zf - pd - 0.16 - i * 0.32), FOUNDATION)
	for x in [pcx - pw * 0.5 + 0.35, pcx + pw * 0.5 - 0.35]:
		_box("brick", Vector3(0.7, 1.0, 0.7), Vector3(x, 1.25, zf - pd + 0.4), brick)
		_box("paint", Vector3(0.42, 1.5, 0.42), Vector3(x, 2.5, zf - pd + 0.4), trim)
	_box("paint", Vector3(pw, 0.32, 0.32), Vector3(pcx, 3.4, zf - pd + 0.4), trim)
	_gable_roof(pcx, zf - pd * 0.5 + 0.1, 3.56, pw, pw * 0.5 * 0.5, pd + 0.4, false, roof, siding, false)
	_front_door(door_x, zf, 0.75, door)
	# Paired double-hungs (a "ribbon") beside the door.
	var wx := cx - gs * w * 0.22
	for k in [-0.55, 0.55]:
		_window(Vector3(wx + k, 2.25, zf), Vector3(-1, 0, 0), 0.95, 1.5, false, false, trim)
	for s in [-1.0, 1.0]:
		for z in [cz - d * 0.28, cz, cz + d * 0.28]:
			_window(Vector3(cx + s * w * 0.5, 2.25, z), Vector3(0, 0, -s), 0.9, 1.4, false, false, trim)
	_back(x0, x1, zf + d, [2.25], 0.75)
	var g := _back_garage(at[1], zf + d, siding, roof)
	return {"drive_x": at[1], "drive_w": 2.8, "garage_z": g.garage_z, "door_x": door_x,
		"walk_z": zf - pd - 1.0, "front_z": zf - pd, "x0": x0, "x1": x1, "gs": gs,
		"bed": [x0 + 0.3, x1 - 0.3], "keep_out": g.keep_out}


## I-house, 1850-1910: two storeys, wide and only one room deep, side gables
## with chimneys, five bays across with the door in the middle, a small
## porch, and a one-and-a-half-storey kitchen ell behind. Mostly white.
func _i_house(zf: float, gs: float, roof: Color, shutter: Color, door: Color, brick: Color) -> Dictionary:
	var w := rng.randf_range(11.0, minf(13.0, _avail() - 3.6))
	var d := rng.randf_range(5.4, 6.0)
	var at := _side_drive(w, gs)
	var cx: float = at[0]
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var top := 6.3
	var wall := CLAPBOARD_WHITE if rng.randf() < 0.7 else Color(_pick(SIDING))
	_box("concrete", Vector3(w + 0.1, 0.6, d + 0.1), Vector3(cx, 0.3, cz), FOUNDATION)
	_box("siding", Vector3(w, top - 0.6, d), Vector3(cx, (top + 0.6) * 0.5, cz), wall)
	_corners(x0, x1, zf, zf + d, 0.6, top)
	var rise := rng.randf_range(1.8, 2.2)
	_gable_roof(cx, cz, top, d, rise, w, true, roof, wall)
	for s in [-1.0, 1.0]:
		_chimney(cx + s * w * 0.5, cz, top + rise + 0.6, brick, s)
	# Rear ell.
	var ew := w * 0.42
	var ex := cx - gs * (w * 0.5 - ew * 0.5)
	var ed := rng.randf_range(5.5, 7.0)
	var ez := zf + d + ed * 0.5
	_box("concrete", Vector3(ew + 0.1, 0.5, ed), Vector3(ex, 0.25, ez), FOUNDATION)
	_box("siding", Vector3(ew, 3.3, ed), Vector3(ex, 2.15, ez), wall)
	_gable_roof(ex, ez + 0.2, 3.8, ew, rng.randf_range(1.6, 2.0), ed + 0.4, false, roof, wall)
	# Five bays; the door in the middle under a small porch.
	for i in 5:
		var x := lerpf(x0 + 1.3, x1 - 1.3, i / 4.0)
		_window(Vector3(x, 4.7, zf), Vector3(-1, 0, 0), 0.85, 1.55, false, true, shutter)
		if i != 2:
			_window(Vector3(x, 2.2, zf), Vector3(-1, 0, 0), 0.85, 1.6, false, true, shutter)
	_stoop(cx, zf, 3.4, 2.0, 0.6)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.18, 2.8, 0.18), Vector3(cx + s * 1.5, 2.0, zf - 1.8), TRIM)
	_box("paint", Vector3(3.6, 0.25, 0.25), Vector3(cx, 3.5, zf - 1.8), TRIM)
	_shed_roof(cx, 3.8, zf, 2.2, 3.65, 0.4, roof)
	_front_door(cx, zf, 0.6, door)
	_back(x0, x1, zf + d, [2.2, 4.7], 0.6)
	var g := _back_garage(at[1], zf + d + ed, wall, roof)
	return {"drive_x": at[1], "drive_w": 2.8, "garage_z": g.garage_z, "door_x": cx,
		"walk_z": zf - 2.6, "front_z": zf, "x0": x0, "x1": x1, "gs": gs,
		"bed": [x0 + 0.3, x1 - 0.3], "keep_out": g.keep_out}


## Gabled-ell (upright-and-wing) farmhouse, 1870-1920: a two-storey wing with
## its gable to the street, and a lower side wing set back, a porch tucked in
## the corner between them. White clapboard, tall narrow windows.
func _ell_farmhouse(zf: float, gs: float, roof: Color, door: Color) -> Dictionary:
	var uw := rng.randf_range(6.4, 7.2)  # upright
	var ud := rng.randf_range(8.5, 9.5)
	var ww := rng.randf_range(5.6, minf(7.0, _avail() - 3.6 - uw))  # wing
	var wd := ud - 2.0
	var total := uw + ww
	var at := _side_drive(total, gs)
	var cx: float = at[0]
	# Upright on the drive side, wing on the other.
	var ux := cx + gs * (total * 0.5 - uw * 0.5)
	var wx := cx - gs * (total * 0.5 - ww * 0.5)
	var wz0 := zf + 2.0
	var wall := CLAPBOARD_WHITE if rng.randf() < 0.75 else Color(_pick(["#e9e0c8", "#c9c3b3", "#9aa3a8"]))
	var trim := TRIM
	_box("concrete", Vector3(uw + 0.1, 0.6, ud + 0.1), Vector3(ux, 0.3, zf + ud * 0.5), FOUNDATION)
	_box("siding", Vector3(uw, 5.5, ud), Vector3(ux, 3.35, zf + ud * 0.5), wall)
	_corners(ux - uw * 0.5, ux + uw * 0.5, zf, zf + ud, 0.6, 6.1)
	_gable_roof(ux, zf + ud * 0.5, 6.1, uw, uw * 0.5 * 0.85, ud, false, roof, wall)
	_box("concrete", Vector3(ww, 0.6, wd + 0.1), Vector3(wx, 0.3, wz0 + wd * 0.5), FOUNDATION)
	_box("siding", Vector3(ww, 3.6, wd), Vector3(wx, 2.4, wz0 + wd * 0.5), wall)
	_gable_roof(wx - gs * 0.01, wz0 + wd * 0.5, 4.2, wd, wd * 0.5 * 0.75, ww, true, roof, wall)
	# Porch along the wing's front, in the crook of the L.
	_stoop(wx, wz0, ww, 2.0, 0.6)
	for x in [wx - ww * 0.5 + 0.25, wx, wx + ww * 0.5 - 0.25]:
		_box("paint", Vector3(0.16, 2.8, 0.16), Vector3(x, 2.0, wz0 - 1.8), trim)
	_box("paint", Vector3(ww, 0.24, 0.24), Vector3(wx, 3.45, wz0 - 1.8), trim)
	_shed_roof(wx, ww + 0.1, wz0, 2.2, 3.6, 0.45, roof)
	var door_x := wx + gs * ww * 0.2
	_front_door(door_x, wz0, 0.6, door)
	_window(Vector3(wx - gs * ww * 0.2, 2.2, wz0), Vector3(-1, 0, 0), 0.8, 1.7, false, false, trim)
	# Upright: two tall windows down, two up, one in the gable.
	for s in [-1.0, 1.0]:
		_window(Vector3(ux + s * uw * 0.22, 2.2, zf), Vector3(-1, 0, 0), 0.8, 1.7, false, false, trim)
		_window(Vector3(ux + s * uw * 0.22, 4.8, zf), Vector3(-1, 0, 0), 0.8, 1.6, false, false, trim)
	_window(Vector3(ux, 7.0, zf), Vector3(-1, 0, 0), 0.6, 0.9, false, false, trim)
	for f in [2.2, 4.8]:
		_window(Vector3(ux + gs * uw * 0.5, f, zf + ud * 0.5), Vector3(0, 0, -gs), 0.8, 1.6, false, false, trim)
	_back(minf(ux, wx) - (uw if gs < 0 else ww) * 0.5, maxf(ux, wx) + (uw if gs > 0 else ww) * 0.5, zf + ud, [2.2], 0.6)
	var g := _back_garage(at[1], zf + ud, wall, roof)
	var x0 := cx - total * 0.5
	return {"drive_x": at[1], "drive_w": 2.8, "garage_z": g.garage_z, "door_x": door_x,
		"walk_z": wz0 - 2.8, "front_z": zf, "x0": x0, "x1": x0 + total, "gs": gs,
		"bed": [ux - uw * 0.5 + 0.3, ux + uw * 0.5 - 0.3], "keep_out": g.keep_out}


## Cape Cod, 1935-1955: one and a half storeys, steep side gables, two gabled
## dormers, a centre door with a pediment, shutters. Small and symmetrical.
func _cape(zf: float, gs: float, siding: Color, roof: Color, shutters: bool, shutter: Color, door: Color) -> Dictionary:
	var w := rng.randf_range(8.6, minf(10.4, _avail() - 3.6))
	var d := rng.randf_range(7.4, 8.2)
	var at := _side_drive(w, gs)
	var cx: float = at[0]
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var top := 3.1
	_box("concrete", Vector3(w + 0.1, 0.5, d + 0.1), Vector3(cx, 0.25, cz), FOUNDATION)
	_box("siding", Vector3(w, top - 0.5, d), Vector3(cx, (top + 0.5) * 0.5, cz), siding)
	_corners(x0, x1, zf, zf + d, 0.5, top)
	var rise := d * 0.5 * rng.randf_range(0.95, 1.1)
	_gable_roof(cx, cz, top, d, rise, w, true, roof, siding)
	for s in [-1.0, 1.0]:
		_dormer(cx + s * w * 0.25, zf + 1.2, cz, top, top + 1.75, 1.6, siding, roof, shutter)
	_chimney(cx - gs * w * 0.5, cz, top + rise + 0.5, Color(_pick(BRICK)), -gs)
	_stoop(cx, zf, 1.9, 1.3, 0.5)
	_front_door(cx, zf, 0.5, door)
	# Pediment over the door.
	_tri("paint", Vector3(cx - 0.75, 2.75, zf - 0.1), Vector3(cx + 0.75, 2.75, zf - 0.1), Vector3(cx, 3.1, zf - 0.1), TRIM, [], Vector3.FORWARD)
	for s in [-1.0, 1.0]:
		for k in [0.2, 0.36]:
			_window(Vector3(cx + s * w * k, 1.95, zf), Vector3(-1, 0, 0), 0.85, 1.35, true, shutters, shutter)
		_window(Vector3(cx + s * w * 0.5, 4.2, cz), Vector3(0, 0, -s), 0.7, 0.9, true, false, shutter)
	_back(x0, x1, zf + d, [1.95], 0.5)
	var g := _back_garage(at[1], zf + d, siding, roof)
	return {"drive_x": at[1], "drive_w": 2.8, "garage_z": g.garage_z, "door_x": cx,
		"walk_z": zf - 1.9, "front_z": zf, "x0": x0, "x1": x1, "gs": gs,
		"bed": [x0 + 0.3, x1 - 0.3], "keep_out": g.keep_out}


## Mid-century modern ranch, 1950-1965: long and low under one shallow gable
## that runs over the attached garage too, wide eaves, a band of tall glass
## by the door, vertical board accents and a stone or brick planter wall.
func _midcentury(zf: float, gs: float, gw: float, roof: Color, door: Color, brick: Color) -> Dictionary:
	var room := _avail() - gw
	var w := rng.randf_range(minf(10.0, room), clampf(room, 7.5, 14.0))
	var d := rng.randf_range(8.6, 9.6)
	var cx := -gs * gw * 0.5
	var cz := zf + d * 0.5
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var gx := cx + gs * (w + gw) * 0.5
	var top := 2.9
	var wall := Color(_pick(["#d8cfb8", "#c9c3b3", "#7a8a84", "#b8a98c", "#e9e6dc"]))
	var board := Color(_pick(["#5b4a38", "#3b4a3a", "#2e3a44", "#7a5a3a"]))
	var total := w + gw
	var mx := (minf(x0, gx - gw * 0.5) + maxf(x1, gx + gw * 0.5)) * 0.5
	_box("concrete", Vector3(total + 0.1, 0.25, d + 0.1), Vector3(mx, 0.125, cz), FOUNDATION)
	_box("siding", Vector3(total, top - 0.25, d), Vector3(mx, (top + 0.25) * 0.5, cz), wall)
	_gable_roof(mx, cz, top, d, rng.randf_range(0.7, 1.0), total, true, roof, wall)
	# Vertical board panels and a long low planter wall in front.
	var door_x := cx + gs * w * 0.3
	_box("paint", Vector3(2.4, top - 0.3, 0.1), Vector3(door_x, (top + 0.25) * 0.5, zf - 0.03), board)
	_box("paint", Vector3(1.0, 2.1, 0.06), Vector3(door_x - gs * 0.5, 1.3, zf - 0.1), door)
	_glass(Vector3(door_x + gs * 0.65, 1.4, zf - 0.1), Vector3(-1, 0, 0), 0.6, 2.2, 0.0)
	_glass(Vector3(cx - gs * w * 0.05, 1.55, zf - 0.01), Vector3(-1, 0, 0), minf(4.2, w * 0.35), 2.2, rng.randf_range(0.0, 0.3))
	_box("paint", Vector3(minf(4.2, w * 0.35) + 0.2, 0.1, 0.14), Vector3(cx - gs * w * 0.05, 2.7, zf - 0.05), board)
	# High strip windows toward the bedroom end.
	for i in 3:
		var x := cx - gs * (w * 0.5 - 1.0 - i * 1.4)
		_glass(Vector3(x, 2.2, zf - 0.01), Vector3(-1, 0, 0), 1.2, 0.6, 0.6)
		_box("paint", Vector3(1.3, 0.06, 0.12), Vector3(x, 1.87, zf - 0.04), board)
	_box("brick", Vector3(w * 0.5, 0.6, 0.35), Vector3(cx - gs * w * 0.22, 0.3, zf - 1.3), brick)
	_stoop(door_x, zf, 2.6, 1.4, 0.2)
	_garage(gx, zf, gw, 2.15)
	_back(x0, x1, zf + d, [1.8], 0.25)
	return {"drive_x": gx, "drive_w": gw - 0.8, "garage_z": zf, "door_x": door_x,
		"walk_z": zf - 1.4, "front_z": zf, "x0": minf(x0, gx - gw * 0.5), "x1": maxf(x1, gx + gw * 0.5), "gs": gs}


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
	if h.has("bed"):
		bed0 = h.bed[0]
		bed1 = h.bed[1]
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
		if h.has("keep_out") and (h.keep_out as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)):
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


## A concrete landing at the door, with steps down to the walk: risers of
## at most 7 3/4 in and 11 in treads (IRC R311.7), and a pipe handrail on
## each side once there are four or more risers.
func _stoop(x: float, zf: float, w: float, d: float, h: float) -> void:
	_box("concrete", Vector3(w, h, d), Vector3(x, h * 0.5, zf - d * 0.5), FOUNDATION)
	if h < 0.25:
		return
	var n := ceili(h / 0.195)
	var rise := h / n
	var run := 0.28
	var sw := minf(w, 1.3)
	var z0 := zf - d
	for k in range(1, n):
		var sh := h - k * rise
		_box("concrete", Vector3(sw, sh, run + 0.02), Vector3(x, sh * 0.5, z0 - (k - 0.5) * run), FOUNDATION.lightened(0.04))
	if n < 4:
		return
	var rail := Color("#222222")
	var zb := z0 - (n - 1) * run + 0.12
	var zt := z0 + 0.15
	var yb := rise + 0.86
	var yt := h + 0.86
	var tilt := Basis(Vector3.RIGHT, -atan2(yt - yb, zt - zb))
	for side in [-1.0, 1.0]:
		var rx: float = x + side * (sw * 0.5 - 0.06)
		_box("metal", Vector3(0.045, 0.86, 0.045), Vector3(rx, rise + 0.43, zb), rail)
		_box("metal", Vector3(0.045, 0.86, 0.045), Vector3(rx, h + 0.43, zt), rail)
		_box("metal", Vector3(0.045, 0.045, Vector2(zt - zb, yt - yb).length() + 0.05),
			Vector3(rx, (yb + yt) * 0.5, (zb + zt) * 0.5), rail, tilt)


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
	# Smooth normals from the middle, so it shades as a rounded clipped
	# yew or boxwood rather than a cut stone; alpha marks it as foliage.
	var mid := p + Vector3(0, r * 0.8, 0)
	var st := _tool("foliage")
	for i in rings:
		for j in segs:
			var quad: Array = [pts[i][j], pts[i][(j + 1) % segs], pts[i + 1][(j + 1) % segs], pts[i + 1][j]]
			var face_n: Vector3 = (quad[1] - quad[0]).cross(quad[3] - quad[0])
			var order := [0, 2, 1, 0, 3, 2] if face_n.dot((quad[0] + quad[2]) * 0.5 - mid) >= 0.0 else [0, 1, 2, 0, 2, 3]
			for k in order:
				var v: Vector3 = quad[k]
				var shade := col.darkened(0.25 * (1.0 - (v.y - p.y) / (r * 1.6)))
				shade.a = 0.3
				st.set_normal(((v - mid).normalized() + Vector3(0, 0.4, 0)).normalized())
				st.set_color(shade)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)


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
