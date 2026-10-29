class_name HotelBuilder
extends RefCounted
## A hotel on a busy road (BuildingTypes "hotel"), drawn against the ones
## along Indiana's interstate exits and bypasses (Marion's Hampton Inn and
## Holiday Inn Express by I-69, Kokomo's and Muncie's full-service hotels):
##   0  the highway hotel: a four-storey bar of rooms off a double-loaded
##      corridor (about 18 m deep), two-tone EIFS over a darker base, a
##      window and its through-wall air conditioner grille to every room, a
##      brand tower over the lobby, a porte-cochère to drop off under, an
##      indoor pool at one end, parking all along the front
##   1  the full-service hotel: an eight-storey tower of rooms on a lobby
##      and restaurant podium, a ballroom and meeting wing at one end with
##      its prefunction glass, a bigger porte-cochère with flags, the name
##      on top, and a field of parking for the banquets
## Local space as DenseBuilder: centred on the lot, -z faces the street.
## Its own random numbers (from the building's seed), so a stage keeps its
## colours as it grows.

const ROOM := 3.8  # one room's bay along the corridor (12-13 ft)
const EIFS := ["#e3d8c2", "#d8ccb4", "#ece4d4", "#cfc6b6"]
const BASE := ["#9a8a74", "#8a7f72", "#a39380", "#7d7468"]
const ACCENT := ["#2f5a8a", "#7a2e2a", "#2f5a3a", "#5a4a6a", "#b05a2a"]


static func build(seed: int, to_curb: float, lot: Dictionary, level: int, spec := {}) -> Array:
	var b := DenseBuilder._start(seed, lot, spec)
	_draw(b, to_curb, level)
	return b._done()


## Where its cars park and its door is (SiteLayout), from a dry run.
static func plan(seed: int, lot: Dictionary, level: int) -> Dictionary:
	var b := DenseBuilder._start(seed, lot)
	b._dry = true
	_draw(b, 3.9, level)
	return b.site


static func _draw(b: DenseBuilder, to_curb: float, level: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([b.rng.seed, "hotel"])
	var upper := Color(EIFS[r.randi() % EIFS.size()])
	var base := Color(BASE[r.randi() % BASE.size()])
	var accent := Color(ACCENT[r.randi() % ACCENT.size()])
	var side := 1.0 if r.randf() < 0.5 else -1.0  # the end the pool or ballroom is on
	var w := b.half * 2.0 - 1.2
	if level >= 1:
		_full_service(b, to_curb, w, upper, base, accent, side, r)
	else:
		_highway(b, to_curb, w, upper, base, accent, side, r)


# ---------------------------------------------------------------- highway hotel

static func _highway(b: DenseBuilder, to_curb: float, w: float, upper: Color, base: Color, accent: Color,
		side: float, r: RandomNumberGenerator) -> void:
	# On a strip of road frontage too shallow for a drop-off out front and
	# two rows of parking (most lots along an Indiana bypass), the bar is a
	# little slimmer (16.5 m), the canopy goes on the end, and the field
	# keeps only an 8 ft planted strip at the street.
	var shallow := b.depth < 52.0
	var pool := w >= 70.0
	var d := 16.5 if shallow else 18.0
	var m0 := 11.0 if shallow else 3.0  # margin at the lobby end (-side)
	var m1 := 17.0 if pool else 3.0  # and at the pool's end
	var l := clampf(w - m0 - m1, 30.0, 80.0)
	var cx := -side * (w * 0.5 - m0) + side * l * 0.5
	var zf := maxf(b.depth - (2.0 if shallow else 3.0) - d, 20.0)
	var ground := 4.0
	var fh := 3.0
	var top := ground + fh * 3.0
	var xe := cx - side * l * 0.5  # the lobby end
	var lx := xe + side * 4.5 if shallow else cx  # the lobby and brand tower
	var pz := zf - 1.0 if shallow else zf - 7.0
	var cut_x := cx + side * minf(l * 0.3, 14.0)
	_field(b, -w * 0.5, w * 0.5, pz - 1.0 if not shallow else pz, cut_x, to_curb, 6, r, 2.5 if shallow else 4.0)
	b.site.door = Vector2(lx, zf - 1.0)
	if b._dry:
		return
	if not shallow:
		b._flat_rect("asphalt", cx - l * 0.5, cx + l * 0.5, pz - 1.0, zf - 2.0, 0.06)  # the drop-off lane
	b._flat_rect("drive", cx - l * 0.5, cx + l * 0.5, zf - 1.0, zf, 0.07)  # the walk along the front
	_bar(b, cx, l, d, zf, ground, fh, 3, upper, base, r, true, lx)
	# The brand tower over the lobby, its name near the top.
	var th := top + 3.0
	b._box("paint", Vector3(9.0, th, 1.2), Vector3(lx, th * 0.5, zf - 0.6), accent)
	b._box("paint", Vector3(9.6, 0.5, 1.6), Vector3(lx, th + 0.25, zf - 0.6), accent.lightened(0.2))
	b._sign(Vector3(lx, top - 0.4, zf - 1.24), 6.0, 1.6)
	b._glass(Vector3(lx, 1.9, zf - 1.23), Vector3(-1, 0, 0), 7.0, 3.2, 0.0)
	# The stair towers at the ends, a little proud and taller.
	for s in [-1.0, 1.0]:
		var sx: float = cx + s * (l * 0.5 - 2.0)
		if shallow and absf(sx - lx) < 7.0:
			continue
		b._box("paint", Vector3(4.0, top + 1.6, 0.6), Vector3(sx, (top + 1.6) * 0.5, zf - 0.3), upper.darkened(0.06))
		for f in 4:
			b._glass(Vector3(sx, ground + f * fh - 1.0 if f > 0 else 2.0, zf - 0.62), Vector3(-1, 0, 0), 0.7, 1.8, 0.0)
	if shallow:
		# The canopy off the lobby's end wall over a lane to the back.
		var cz := zf + 5.0
		b._flat_rect("asphalt", xe - side * 9.0 if side > 0.0 else xe, xe if side > 0.0 else xe - side * 9.0, pz, b.depth - 1.0, 0.06)
		var cxp := xe - side * 4.5
		b._box("paint", Vector3(9.0, 0.7, 8.0), Vector3(cxp, 4.95, cz), Color("#ece8de"))
		b._box("paint", Vector3(9.2, 0.5, 8.2), Vector3(cxp, 5.55, cz), accent)
		for sz in [-1.0, 1.0]:
			b._box("paint", Vector3(0.7, 4.6, 0.7), Vector3(xe - side * 8.4, 2.3, cz + sz * 3.4), Color("#d8d2c4"))
		b._glass(Vector3(xe - side * 0.03, 1.9, cz), Vector3(0, 0, -side), 6.0, 3.2, 0.0)
	else:
		_porte_cochere(b, cx, zf, pz, 12.0, 4.6, accent, false)
	if pool:
		# The indoor pool: a one-storey glass-fronted room at the end.
		var px := cx + side * (l * 0.5 + 7.8)  # a joint between (its own roof, far off)
		var pd := minf(12.0, d)
		var pzc := zf + d - pd * 0.5
		b._block("paint", px, 14.0, pd, pzc, 5.2, 5.8, upper)
		b._glass(Vector3(px, 2.6, pzc - pd * 0.5 - 0.03), Vector3(-1, 0, 0), 12.0, 3.6, 0.0)
		b._glass(Vector3(px + side * 7.03, 2.6, pzc), Vector3(0, 0, side), pd - 2.0, 3.6, 0.0)
		b._box("paint", Vector3(0.9, 4.4, pd - 2.0), Vector3(px - side * 7.4, 2.2, pzc), upper.darkened(0.08))  # the link
		b._box("paint", Vector3(14.2, 0.9, pd + 0.2), Vector3(px, 0.45, pzc), base)
		if b.fine_parts:
			b._box("glass", Vector3(8.0, 0.6, 4.0), Vector3(px, 5.6, pzc), Color("#9fc3d1"))  # skylight
	_monument(b, cut_x - side * 7.0, accent, base)
	_lot_lights(b, -w * 0.5, w * 0.5, pz - 1.0)


# ---------------------------------------------------------------- full service

static func _full_service(b: DenseBuilder, to_curb: float, w: float, upper: Color, base: Color, accent: Color,
		side: float, r: RandomNumberGenerator) -> void:
	var ball := w >= 90.0
	var bw := 30.0 if ball else 0.0
	var l := clampf(w - bw - 24.0, 36.0, 72.0)
	var d := 19.0
	var cx := -side * (bw + 4.0) * 0.5 if ball else 0.0
	var zf := maxf(b.depth - 6.0 - d, 34.0)
	var podium_d := 9.0
	var zp := zf - podium_d
	var ground := 5.0
	var fh := 3.1
	var storeys := 8
	var top := ground + fh * (storeys - 1)
	var pz := zp - 11.0
	var cut_x := cx + side * minf(l * 0.35, 16.0)
	_field(b, -w * 0.5, w * 0.5, pz - 1.0, cut_x, to_curb, 10, r)
	b.site.door = Vector2(cx, zp - 1.0)
	if b._dry:
		return
	b._flat_rect("asphalt", cx - l * 0.5 - 6.0, cx + l * 0.5 + 6.0, pz - 1.0, zp - 2.0, 0.06)
	b._flat_rect("drive", cx - l * 0.5 - 6.0, cx + l * 0.5 + 6.0, zp - 2.0, zp, 0.07)
	# The tower of rooms: precast with piers between pairs of rooms.
	_bar(b, cx, l, d, zf, ground, fh, storeys - 1, upper, base, r, false)
	# The podium: lobby, restaurant and bar under a deep fascia.
	var pl := l + 8.0
	b._block("paint", cx, pl, podium_d - 0.8, zp + (podium_d - 0.8) * 0.5, ground, ground + 0.8, base)
	b._box("paint", Vector3(pl - 0.4, ground - 0.4, 0.9), Vector3(cx, (ground - 0.4) * 0.5, zf - 0.4), base.darkened(0.06))
	b._glass(Vector3(cx, 2.3, zp - 0.03), Vector3(-1, 0, 0), pl - 6.0, 3.8, 0.1)
	b._box("paint", Vector3(pl + 0.4, 0.9, 0.4), Vector3(cx, ground - 0.2, zp - 0.2), accent.darkened(0.2))
	if b.fine_parts:
		var n := int((pl - 6.0) / 1.6)
		for i in range(1, n):
			b._box("metal", Vector3(0.08, 3.8, 0.1), Vector3(cx - (pl - 6.0) * 0.5 + i * (pl - 6.0) / n, 2.3, zp - 0.08), Color("#3a3530"))
	_porte_cochere(b, cx, zp, pz, 16.0, 5.6, accent, true)
	# The name along the top of the tower, and its mechanical penthouse.
	b._sign(Vector3(cx, top - 2.6, zf - 0.12), minf(l * 0.4, 16.0), 2.0)
	b._box("paint", Vector3(l * 0.3, 3.6, d * 0.5), Vector3(cx, top + 1.0 + 1.8, zf + d * 0.5), upper.darkened(0.12))
	if ball:
		_ballroom(b, cx + side * (l * 0.5 + 4.0 + bw * 0.5), bw, zf - 4.0, d + 4.0, upper, base, accent)
	_monument(b, cut_x - side * 8.0, accent, base)
	_lot_lights(b, -w * 0.5, w * 0.5, pz - 1.0)


## The ballroom and meeting wing: a tall blank box (no windows on a
## ballroom), a clerestory band, the prefunction lobby in glass along its
## front, a loading dock for the banquet kitchen at the back.
static func _ballroom(b: DenseBuilder, x: float, w: float, zf: float, d: float, upper: Color, base: Color, accent: Color) -> void:
	var h := 8.0
	b._block("paint", x, w, d, zf + d * 0.5, h, h + 0.8, upper.darkened(0.05))
	b._box("paint", Vector3(w + 0.1, 1.2, d + 0.1), Vector3(x, 0.6, zf + d * 0.5), base)
	b._box("paint", Vector3(w + 0.2, 0.6, d + 0.2), Vector3(x, h - 1.4, zf + d * 0.5), accent.darkened(0.15))
	# Prefunction: a glass gallery in front, lower.
	b._box("paint", Vector3(w, 0.5, 4.0), Vector3(x, 5.2, zf - 2.0), upper)
	b._glass(Vector3(x, 2.6, zf - 4.03), Vector3(-1, 0, 0), w - 1.0, 4.6, 0.0)
	b._box("paint", Vector3(w, 0.3, 4.0), Vector3(x, 0.15, zf - 2.0), base)
	if b.fine_parts:
		var n := int((w - 1.0) / 2.0)
		for i in range(1, n):
			b._box("metal", Vector3(0.08, 4.6, 0.1), Vector3(x - (w - 1.0) * 0.5 + i * (w - 1.0) / n, 2.6, zf - 4.08), Color("#3a3530"))
	# The banquet kitchen's dock at the back.
	b._box("paint", Vector3(3.2, 3.2, 0.1), Vector3(x, 1.6, zf + d + 0.06), Color("#6a6c6e"))
	b._box("paint", Vector3(3.6, 1.2, 0.5), Vector3(x, 1.2, zf + d + 0.3), Color("#1e1f20"))


# ---------------------------------------------------------------- parts

## A bar of hotel rooms `l` long and `d` deep from zf: a darker base storey
## (lobby and rooms), `floors` floors of rooms above, every room a window
## with its PTAC grille under it, on both long faces; `eifs` two-tone EIFS
## with a cornice (the highway hotel) or precast with a pier every two
## rooms (the full-service tower).
static func _bar(b: DenseBuilder, cx: float, l: float, d: float, zf: float, ground: float, fh: float, floors: int,
		upper: Color, base: Color, r: RandomNumberGenerator, eifs: bool, lobby_x := INF) -> void:
	if lobby_x == INF:
		lobby_x = cx
	var top := ground + fh * floors
	var cz := zf + d * 0.5
	b._block("paint", cx, l, d, cz, top, top + 1.0, upper)
	b._box("paint", Vector3(l + 0.1, ground, d + 0.1), Vector3(cx, ground * 0.5, cz), base)
	if eifs:
		b._box("paint", Vector3(l + 0.5, 0.6, d + 0.5), Vector3(cx, top + 0.7, cz), upper.lightened(0.15))  # cornice
		b._box("paint", Vector3(l + 0.2, 0.25, d + 0.2), Vector3(cx, ground + 0.1, cz), upper.lightened(0.1))
	var n := maxi(4, int(l / ROOM))
	var bay := l / n
	var grille := upper.lightened(0.08)
	for f in floors + 1:
		var y := ground + (f - 1) * fh if f > 0 else 0.0
		for i in n:
			var x := cx - l * 0.5 + (i + 0.5) * bay
			for face in [[zf - 0.03, Vector3(-1, 0, 0)], [zf + d + 0.03, Vector3(1, 0, 0)]]:
				var z: float = face[0]
				# The lobby takes the middle of the ground floor's front.
				if f == 0 and z < cz and absf(x - lobby_x) < 5.5:
					continue
				var wy := y + 1.75 if f > 0 else 2.0
				var out := -0.06 if z < cz else 0.06
				if not eifs and f > 0:
					# The tower's rooms: a wide window over a dark spandrel,
					# stacked into vertical bands.
					b._box("paint", Vector3(2.3, fh, 0.04), Vector3(x, y + fh * 0.5, z + out * 0.5), Color("#4a4f55"))
					b._glass(Vector3(x, wy, z + out), face[1], 2.1, 1.6, r.randf_range(0.2, 0.7))
					continue
				b._glass(Vector3(x, wy, z), face[1], 1.5, 1.4, r.randf_range(0.2, 0.7))
				b._box("paint", Vector3(1.05, 0.42, 0.06), Vector3(x, wy - 1.05, z + out), grille)
				if b.fine_parts:
					for k in 3:
						b._box("metal", Vector3(0.95, 0.03, 0.03), Vector3(x, wy - 1.17 + k * 0.12, z + out * 1.6), grille.darkened(0.2))
			if not eifs and i % 2 == 0 and f == floors:
				for z2 in [zf - 0.15, zf + d + 0.15]:
					b._box("paint", Vector3(0.5, top - ground, 0.3), Vector3(x - bay * 0.5, (ground + top) * 0.5, z2), upper.lightened(0.08))
	# End walls: the corridor's window at each end of each floor.
	for s in [-1.0, 1.0]:
		for f in range(1, floors + 1):
			b._glass(Vector3(cx + s * (l * 0.5 + 0.03), ground + (f - 1) * fh + 1.6, cz), Vector3(0, 0, s), 1.2, 1.6, 0.0)
	b._rooftop(l * 0.7, d * 0.5, cz, top, 4)
	# The elevator overrun over the lobby core.
	b._box("paint", Vector3(3.6, 2.4, 3.0), Vector3(lobby_x, top + 1.2, cz), upper.darkened(0.08))
	if not b.fine_parts:
		return
	# Up close, the roof of a hotel whose rooms have their own through-wall
	# units: a bathroom exhaust fan over every pair of rooms each side of the
	# corridor, and the corridors' make-up air units near the ends.
	for i in range(0, n, 2):
		var fx := cx - l * 0.5 + (i + 1.0) * bay
		if absf(fx - lobby_x) < 2.5:
			continue
		for sz in [-1.0, 1.0]:
			b._cylinder("metal", Vector3(fx, top, cz + sz * 2.4), 0.28, 0.45, Color("#b9bcbc"), 8)
			b._cylinder("metal", Vector3(fx, top + 0.45, cz + sz * 2.4), 0.42, 0.12, Color("#a6a9a9"), 8)
	for s in [-1.0, 1.0]:
		var mx: float = cx + s * l * 0.32
		b._box("metal", Vector3(3.2, 1.5, 1.6), Vector3(mx, top + 0.75, cz), Color("#c4c6c4"))
		b._box("paint", Vector3(0.9, 0.08, 0.9), Vector3(mx + 1.0, top + 1.54, cz), Color("#3a3c3e"))
	if eifs:
		# Up close: the EIFS's reveal at every floor line, and the top floor
		# a shade darker (the brands' prototype elevations).
		for f in range(2, floors + 1):
			var y := ground + (f - 1) * fh
			for z in [zf - 0.025, zf + d + 0.025]:
				b._box("paint", Vector3(l + 0.06, 0.05, 0.03), Vector3(cx, y, z), upper.darkened(0.25))
		b._box("paint", Vector3(l + 0.04, fh - 0.05, d + 0.04), Vector3(cx, top - fh * 0.5, cz), upper.darkened(0.1))
	# Foundation plantings along the back, in a mulch bed.
	if b.depth - (zf + d) > 1.7:
		b._flat_rect("mulch", cx - l * 0.5, cx + l * 0.5, zf + d + 0.15, zf + d + 1.55, 0.075)
		var x := cx - l * 0.5 + 1.2
		while x < cx + l * 0.5 - 1.0:
			b._shrub(Vector3(x, 0.1, zf + d + 0.85), r.randf_range(0.4, 0.6))
			x += r.randf_range(2.0, 3.0)


## The drop-off canopy: a flat roof out over the lane on four columns, its
## fascia in the brand colour; with `flags`, three flagpoles beside it.
static func _porte_cochere(b: DenseBuilder, cx: float, zf: float, pz: float, cw: float, h: float, accent: Color, flags: bool) -> void:
	var depth := zf - pz
	b._box("paint", Vector3(cw, 0.7, depth), Vector3(cx, h + 0.35, (zf + pz) * 0.5), Color("#ece8de"))
	b._box("paint", Vector3(cw + 0.2, 0.5, depth + 0.2), Vector3(cx, h + 0.95, (zf + pz) * 0.5), accent)
	for sx in [-1.0, 1.0]:
		b._box("paint", Vector3(0.7, h, 0.7), Vector3(cx + sx * (cw * 0.5 - 0.6), h * 0.5, pz + 0.6), Color("#d8d2c4"))
		if b.fine_parts:
			b._box("paint", Vector3(0.9, 0.8, 0.9), Vector3(cx + sx * (cw * 0.5 - 0.6), 0.4, pz + 0.6), Color("#8a7d6b"))
	if b.fine_parts:
		for i in 4:  # downlights under the canopy
			b._box("paint", Vector3(0.4, 0.05, 0.4), Vector3(cx - cw * 0.3 + i * cw * 0.2, h - 0.02, (zf + pz) * 0.5), Color("#f6efd8"))
	if flags:
		for i in 3:
			var fx := cx + cw * 0.5 + 2.5 + i * 2.2
			b._box("metal", Vector3(0.14, 10.0, 0.14), Vector3(fx, 5.0, pz + 1.0), Color("#cfd2d4"))
			b._box("paint", Vector3(1.8, 1.1, 0.04), Vector3(fx + 0.95, 9.3, pz + 1.0), [Color("#3c3b6e"), Color("#a3262a"), accent][i])


## The brand's monument sign by the drive, on a stone base in a bed.
static func _monument(b: DenseBuilder, x: float, accent: Color, base: Color) -> void:
	b._flat_rect("mulch", x - 3.0, x + 3.0, 0.8, 3.6, 0.075)
	b._box("brick", Vector3(4.6, 1.0, 0.7), Vector3(x, 0.5, 2.2), base)
	b._box("paint", Vector3(4.0, 1.6, 0.5), Vector3(x, 1.8, 2.2), accent)
	b._sign(Vector3(x, 1.2, 1.94), 3.6, 1.0)
	for i in 3:
		b._shrub(Vector3(x - 2.2 + i * 2.2, 0.1, 3.2), 0.45)


## Shoebox LED lights on 30 ft poles down the field.
static func _lot_lights(b: DenseBuilder, x0: float, x1: float, ztop: float) -> void:
	var n := maxi(2, int((x1 - x0) / 30.0))
	for i in n:
		var x := x0 + (i + 0.5) * (x1 - x0) / n
		var p := Vector3(x, 0, ztop - 12.5)
		if p.z < 4.0:
			continue
		b._box("metal", Vector3(0.2, 9.0, 0.2), p + Vector3(0, 4.5, 0), Color("#5f6266"))
		b._box("metal", Vector3(0.8, 0.2, 0.5), p + Vector3(0.45, 9.0, 0), Color("#5f6266"))
		b._box("metal", Vector3(0.8, 0.2, 0.5), p + Vector3(-0.45, 9.0, 0), Color("#5f6266"))


## The parking field in front: pairs of rows nose to nose across their own
## aisles from `ztop` (the row along the building) out toward the street,
## keeping a 4 m planted strip at the street, at most `max_rows` rows; a
## landscaped island every ten stalls; the drive in from the curb at
## `cut_x`. Every stall notes the aisle it's reached from.
static func _field(b: DenseBuilder, x0: float, x1: float, ztop: float, cut_x: float, to_curb: float, max_rows: int,
		r: RandomNumberGenerator, front := 4.0) -> void:
	var rows := []
	var rz := ztop
	while rows.size() < max_rows:
		var a := rz - 5.5
		var ai := a - 7.0
		if ai < front:
			break
		rows.append([a, Vector2(0, 1), ai + 3.5])
		var bz := ai - 5.5
		if bz < front or rows.size() >= max_rows:
			rz = ai
			break
		rows.append([bz, Vector2(0, -1), ai + 3.5])
		rz = bz
	b.site.main_street = false
	b.site.cut_x = cut_x
	b.site.aisle_z = rows[0][2] if not rows.is_empty() else ztop - 3.5
	b._flat_rect("drive", cut_x - 4.4, cut_x + 4.4, -to_curb, 0.0, 0.08)
	b._flat_rect("asphalt", cut_x - 3.5, cut_x + 3.5, 0.0, rz, 0.06)
	if rows.is_empty():
		return
	b._flat_rect("asphalt", x0, x1, rz, ztop, 0.06)
	for row in rows.size():
		var z: float = rows[row][0]
		var x := x0 + 1.0
		while x + 2.75 <= x1 - 1.0:
			var mid := x + 1.375
			var skip := row >= 1 and absf(mid - cut_x) < 4.5
			var isle := int((x - x0) / 2.75) % 11 == 10
			if not skip and not isle:
				b._flat_rect("line", x - 0.06, x + 0.06, z, z + 5.5, 0.07, CommercialBuilder.LINE)
				b._flat_rect("line", x + 2.69, x + 2.81, z, z + 5.5, 0.07, CommercialBuilder.LINE)
				b.site.stalls.append([Vector2(mid, z + 2.75), rows[row][1], rows[row][2]])
			elif isle and not skip:
				b._flat_rect("mulch", x + 0.3, x + 2.45, z + 0.3, z + 5.2, 0.075)
				if not b._dry:
					var pick := TreeField.pick(r)
					b.trees.append([Vector3(mid, 0, z + 2.75), pick[0], pick[1], r.randf_range(0.7, 0.9)])
			x += 2.75
